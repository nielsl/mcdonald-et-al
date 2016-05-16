package Common::Widgets;     #  -*- perl -*-

# Generic widgets that produce strings of xhtml. They use CSS1 and rely
# on the styles being defined for a given class, which is usually given
# as argument. Some functions in here also depend on Javascript for 
# submitting forms (we do not like JavaScript and try to minimize it.)
# 
# We are also trying to get a situation where this module is the only
# one that generates XHTML code (HTML we do not generate at all.)

use strict;
use warnings FATAL => qw ( all );

use POSIX;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &expr_selections_menu
                 );

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub expr_selections_menu
{
    # Niels Larsen, April 2004.

    # Generates a menu with names of currently selection expression experiments.
    # When a menu option is chosen the "expr_selections_menu" parameter is set 
    # to corresponding experiment id. By default a cancel button is attached
    # that makes the menu disappear. 

    my ( $sid,         # Session id
         $ids,         # List of ids - OPTIONAL
         $button,      # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    $button = 1 if not defined $button;

    my ( @items, $action, $icon_xhtml, $key, $title, $text, 
         $fgcolor, $bgcolor, $xhtml );

    @items = &Common::Menus::expr_selections_items( $sid );
    @items = &Common::Widgets::show_items_selected( \@items, $ids );

    $action = "javascript:handle_menu(this.form.expr_selections_menu,'add_expression_column')";

    $xhtml = &Common::Widgets::select_menu( "expr_selections_menu", \@items,
                                            $items[0]->{"id"}, "grey_button", $action );

    if ( $button )
    {
        $key = "expr_selections_menu";
        
        $title = "Close expression menu";
        
        $text = qq (Removes the expression data selections menu.);

        $fgcolor ||= "#ffffcc";
        $bgcolor ||= "#cc6633";

        $icon_xhtml = &Common::Widgets::cancel_icon( $key, $title, $text, $fgcolor, $bgcolor );

        $xhtml = qq (
<table cellpadding="2" cellspacing="0"><tr>
     <td>$xhtml</td>
     <td valign="middle">$icon_xhtml</td>
</tr></table>
);
    }

    return $xhtml;
}

1;

__END__
