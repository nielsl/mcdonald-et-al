package Ali::Option;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use base qw ( Common::Option );

# >>>>>>>>>>>>>>>>>>>> SIMPLE GET/SET FUNCTIONS <<<<<<<<<<<<<<<<<<<<

# Define here, but reuse the AUTOLOAD function from the parent 
# module,

foreach ( qw (
              min_pix_per_col min_pix_per_row visible hidden
              ))
{
    $Common::Option::Auto_get_setters{ $_ } = 1;
}

sub AUTOLOAD
{
    our $AUTOLOAD;

    $Common::Option::AUTOLOAD = $AUTOLOAD;
    &Common::Option::AUTOLOAD;
}

# >>>>>>>>>>>>>>>>>>>>>>>>>> CLASS METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<


1;

__END__

