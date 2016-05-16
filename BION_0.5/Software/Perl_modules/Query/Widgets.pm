package Query::Widgets;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Widgets routines that are not project specific. The project specific
# routines are in sub-modules (sub-directories).
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &message_area
                 &message_box
                 );

use Common::Config;
use Common::Messages;

use Common::Widgets;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub message_area
{
    # Niels Larsen, January 2007.

    # Returns a message area with lots of spacing around it. 

    my ( $msg,
         ) = @_;

    # Returns a string.

    my ( $xhtml );

    $xhtml .= qq (<p>\n<table><tr><td height="10"></td></tr></table>\n);
    $xhtml .= qq (<p>\n<table align="center" width="50%" class="message_area"><tr><td class="info_page">$msg</td></tr></table>\n);
    $xhtml .= qq (<table><tr><td height="130"></td></tr></table>\n);

    return $xhtml;
}

sub message_box
{
    # Niels Larsen, January 2007.

    # Returns a message box with a bit of spacing around it. 

    my ( $msgs,
         ) = @_;

    # Returns a string.

    my ( $xhtml );

    $xhtml = qq (<p>\n<table><tr><td height="5"></td></tr></table>\n)
               . &Common::Widgets::message_box( $msgs ) ."\n</p>\n"
               . qq (<table><tr><td height="5"></td></tr></table>\n);

    return $xhtml;
}

1;

__END__
