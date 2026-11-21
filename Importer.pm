package Plugins::PlayAPE::Importer;

use strict;
use warnings;

use Plugins::PlayAPE::Register;

sub initPlugin {
    my $class = shift;

    Plugins::PlayAPE::Register->registerFormatHandler();
    return 1;
}

sub startScan {
    my $class = shift;
    return;
}

1;
