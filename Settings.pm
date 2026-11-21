package Plugins::PlayAPE::Settings;

use strict;
use warnings;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.playape');

sub name {
    return 'PLUGIN_PLAYAPE';
}

sub page {
    return 'plugins/PlayAPE/settings/basic.html';
}

sub prefs {
    return ($prefs, qw(embeddedCue));
}

1;
