package Plugins::PlayAPE::Formats::APE;

use strict;
use warnings;
use base qw(Slim::Formats::APE);

use Audio::Scan;
use File::Basename qw(dirname);

use Slim::Formats::Playlists::CUE;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log   = logger('plugin.playape');
my $prefs = preferences('plugin.playape');

# Applied on top of the core mapping (Slim::Formats::APE::doTagMapping).
# A mapping never overwrites a value that is already present.
my %tagMapping = (
    'ALBUM ARTIST SORT' => 'ALBUMARTISTSORT',
    'ALBUMARTIST_SORT'  => 'ALBUMARTISTSORT',
    'UNSYNCEDLYRICS'    => 'LYRICS',
    'UNSYNCED LYRICS'   => 'LYRICS',
    'RELEASEDATE'       => 'YEAR',
    'DISCOGS_RELEASE_ID' => 'ALBUM_EXTID',
);

# File level values that must not be copied onto the cuesheet tracks.
my %notInherited = map { $_ => 1 } qw(
    CUESHEET ARTWORK SECS SIZE TITLE TITLESORT TRACKNUM URI START END
    FILENAME CT AUDIO ARTISTSORT ISRC LYRICS
    MUSICBRAINZ_TRACKID MUSICBRAINZ_RELEASETRACKID
    REPLAYGAIN_TRACK_GAIN REPLAYGAIN_TRACK_PEAK
);

sub getTag {
    my ($class, $file, $anchor) = @_;
    return {} unless $file;

    $anchor //= '';

    my $s = Audio::Scan->scan($file);
    return {} unless $s->{info}{samplerate};

    my $info = $s->{info};
    my $tags = $s->{tags};

    _normalizeKeys($tags);

    # Add info
    $tags->{SIZE}     = $info->{file_size};
    $tags->{BITRATE}  = $info->{bitrate};
    $tags->{SECS}     = $info->{song_length_ms} / 1000;
    $tags->{RATE}     = $info->{samplerate};
    $tags->{CHANNELS} = $info->{channels};

    $class->_mapDisc($tags);
    $class->doTagMapping($tags);
    $class->_mapExtraTags($tags);

    return $tags unless $prefs->get('embeddedCue') && $tags->{CUESHEET};

    my $cue = ref $tags->{CUESHEET} eq 'ARRAY'
        ? join("\n", @{ $tags->{CUESHEET} })
        : $tags->{CUESHEET};

    my $cuesheet = [ split /\s*\n/, $cue ];

    push @$cuesheet, '    REM END ' . $tags->{SECS};

    $tags->{FILENAME} = $file;

    my $tracks = Slim::Formats::Playlists::CUE->parse(
        $cuesheet, dirname($file), $file
    );

    unless ($tracks && scalar keys %$tracks) {
        $log->warn("PlayAPE: cuesheet parse failed or empty for $file");
        return $tags;
    }

    my $items = $class->_getTrackTags($tags, $tracks);

    for my $track (values %$tracks) {
        Slim::Formats::sanitizeTagValues($track, $file);
    }

    my ($first) = sort { $a <=> $b } keys %$tracks;

    $tags->{CT}    = 'fec';
    $tags->{AUDIO} = 0;
    $tags->{TITLE} = $tracks->{$first}{ALBUM} || $tags->{ALBUM};

    my $fileurl = Slim::Utils::Misc::fileURLFromPath($file) . "#$anchor";
    my $fileage = (stat($file))[9];
    my $rs      = Slim::Schema->rs('Track');

    for my $key (sort { $a <=> $b } keys %$tracks) {
        my $track = $tracks->{$key};

        $track->{AGE}     = $fileage;
        $track->{FS}      = $tags->{SIZE};
        $track->{VIRTUAL} = 1;

        next unless exists $track->{URI};

        Slim::Formats::Playlists::CUE->processAnchor($track);

        $rs->updateOrCreate({
            url        => $track->{URI},
            attributes => $track,
            readTags   => 0,
        });

        if ($anchor && $track->{URI} eq $fileurl) {
            $tags = $track;
            main::DEBUGLOG && $log->is_debug
                && $log->debug("PlayAPE: found tags for $file#$anchor");
        }
    }

    main::DEBUGLOG && $log->is_debug
        && $log->debug("PlayAPE: returning $items virtual tracks for $file");

    return $tags;
}

# APE keys are case insensitive: work with upper case names only.
sub _normalizeKeys {
    my ($tags) = @_;

    for my $key (keys %$tags) {
        my $upper = uc $key;
        next if $upper eq $key;

        my $value = delete $tags->{$key};
        $tags->{$upper} = $value unless exists $tags->{$upper};
    }
}

# Names under which taggers store the disc number, the number of discs and the
# disc title, in order of preference. Core only knows DISCNUMBER and DISCSUBTITLE.
my @discNumberKeys = ('DISCNUMBER', 'DISC', 'DISC NUMBER', 'DISC_NUMBER');
my @discTotalKeys  = ('DISCTOTAL', 'TOTALDISCS', 'DISC_TOTAL', 'DISC TOTAL', 'DISCC');
my @discTitleKeys  = (
    'DISCSUBTITLE', 'DISC SUBTITLE', 'DISC_SUBTITLE',
    'DISCTITLE', 'DISC TITLE', 'DISC_TITLE', 'SETSUBTITLE', 'SET SUBTITLE',
);

# Sets DISC, DISCC and DISCSUBTITLE the way the server expects them: plain
# numbers (core drops anything else, and disc 0), first value only.
sub _mapDisc {
    my ($class, $tags) = @_;

    my $disc  = _takeFirst($tags, @discNumberKeys);
    my $discc = _takeFirst($tags, @discTotalKeys);
    my $title = _takeFirst($tags, @discTitleKeys);

    if (defined $disc) {
        # 1/2, 1-2, 1 of 2: a number of discs in its own tag wins
        if ($disc =~ m{(\d+)\s*(?:/|-|of)\s*(\d+)}i) {
            ($disc, $discc) = ($1, $discc // $2);
        }
        # Disc 2, 02
        elsif ($disc =~ /(\d+)/) {
            $disc = $1;
        }
        else {
            undef $disc;
        }
    }

    $discc = $1 if defined $discc && $discc =~ /(\d+)/;

    $tags->{DISC}         = $disc + 0  if $disc;
    $tags->{DISCC}        = $discc + 0 if $discc;
    $tags->{DISCSUBTITLE} = $title     if defined $title;
}

# Removes the tags and returns the first value that is not empty.
sub _takeFirst {
    my ($tags, @keys) = @_;

    my $found;

    for my $key (@keys) {
        next unless exists $tags->{$key};

        my $values = delete $tags->{$key};

        for my $value (ref $values eq 'ARRAY' ? @$values : $values) {
            next if !defined $value || ref $value;

            (my $trimmed = $value) =~ s/^\s+|\s+$//g;

            $found //= $trimmed if length $trimmed;
        }
    }

    return $found;
}

sub _mapExtraTags {
    my ($class, $tags) = @_;

    while (my ($old, $new) = each %tagMapping) {
        next unless exists $tags->{$old};

        my $value = delete $tags->{$old};
        $tags->{$new} = $value unless defined $tags->{$new};
    }

    # TRACK=3/12
    if (defined $tags->{TRACKNUM} && $tags->{TRACKNUM} =~ m{^\s*(\d+)\s*/}) {
        $tags->{TRACKNUM} = $1;
    }
}

# Complete the tracks found in the cuesheet with the file's metadata.
# Returns the number of tracks.
sub _getTrackTags {
    my ($class, $tags, $tracks) = @_;

    # numbered tags, e.g. TITLE[3], override what the cuesheet provides
    my %numbered;
    for my $key (keys %$tags) {
        next unless $key =~ /^(.+)\[(\d+)\]$/;

        my ($field, $num) = ($1, $2 + 0);
        $numbered{$num}{$field} = delete $tags->{$key} if $tracks->{$num};
    }

    for my $num (keys %numbered) {
        my $values = $numbered{$num};
        $class->_mapDisc($values);
        $class->doTagMapping($values);
        $class->_mapExtraTags($values);

        $tracks->{$num}{$_} = $values->{$_} for keys %$values;
    }

    for my $track (values %$tracks) {
        for my $field (keys %$tags) {
            next if $notInherited{$field} || $field =~ /\[\d+\]$/;
            $track->{$field} = $tags->{$field} unless defined $track->{$field};
        }
    }

    return scalar keys %$tracks;
}

1;
