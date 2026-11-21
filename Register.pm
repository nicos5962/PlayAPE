package Plugins::PlayAPE::Register;

# Registers the PlayAPE tag handler. Kept free of any web/UI dependency so it
# can be used by both the server plugin and the scanner importer.

use strict;
use warnings;

use Slim::Formats;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use constant HANDLER => 'Plugins::PlayAPE::Formats::APE';

my $log   = logger('plugin.playape');
my $prefs = preferences('plugin.playape');

$prefs->init({
    embeddedCue => 1,
});

sub registerFormatHandler {
    my ($class, $tagClasses) = @_;

    Slim::Formats->init();

    $tagClasses ||= \%Slim::Formats::tagClasses;

    return 0 unless ref($tagClasses) eq 'HASH';

    my $current = $tagClasses->{ape};
    return 1 if defined($current) && $current eq HANDLER;

    $tagClasses->{ape} = HANDLER;

    main::DEBUGLOG && $log->is_debug && $log->debug('PlayAPE: registered APE tag handler');

    return 1;
}

1;
