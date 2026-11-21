package Plugins::PlayAPE::Plugin;

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Plugins::PlayAPE::Register;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.playape',
    defaultLevel => 'INFO',
    description  => 'PLUGIN_PLAYAPE',
});

sub initPlugin {
    my $class = shift;

    my $version = $class->_pluginDataFor('version') || 'unknown';
    $log->info("Initializing PlayAPE plugin $version");

    Plugins::PlayAPE::Register->registerFormatHandler();

    if (main::WEBUI) {
        require Plugins::PlayAPE::Settings;
        Plugins::PlayAPE::Settings->new;
    }

    $class->SUPER::initPlugin(@_);
}

sub getDisplayName { 'PLUGIN_PLAYAPE' }

1;
