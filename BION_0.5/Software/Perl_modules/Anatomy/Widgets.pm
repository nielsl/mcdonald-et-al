package Anatomy::Widgets;     #  -*- perl -*-

# Widgets that produce strings of xhtml. Most of the routines invoke
# their generic equivalents in Common::Widgets. They use CSS1 and rely
# on the styles being defined for a given class, which is usually given
# as argument. Some functions in here also depend on Javascript for 
# submitting forms (we do not like JavaScript and try to minimize it.)

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;
use POSIX;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &cancel_icon
                 &control_icon
                 &control_menu
                 &data_icon
                 &data_menu
                 &delete_columns_button
                 &delete_selection_button
                 &help_icon
                 &report_title
                 &save_selection_button
                 &search_icon
                 &selections_icon
                 &selections_menu
                 &statistics_icon
                 &statistics_menu
                 );

use Anatomy::Menus;

use Common::Config;
use Common::Widgets;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub cancel_icon
{
    # Niels Larsen, October 2004.

    # A button that closes a menu. 

    # Returns an XHTML string. 

    return &Anatomy::Widgets::cancel_icon( "ana_col_checkboxes",
                                           "Delete checkboxes",
                                           "Deletes the row of column checkboxes",
                                           "#ffffcc",
                                           "#006666",
                                           );
}

sub control_icon
{
    # Niels Larsen, October 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the GO control menu. 

    # Returns an xhtml string. 

    my ( $icon, $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $icon = "$Common::Config::img_url/sys_menu.gif";

    $key = "ana_control_menu";

    $title = "Control menu";

    $text = qq (Shows a menu with options for selections, column deletions and comparison.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#006666";

    $xhtml = &Common::Widgets::control_icon( $icon, $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub control_menu
{
    # Niels Larsen, October 2004.

    # Generates a menu where the user can activate select columns etc. 

    my ( $options,      # Selected options
         $button,       # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    $options = [] if not defined $options;
    $button = 1 if not defined $button;

    my ( @options, @menu, $o, $menu, $key, $text, $fgcolor, $bgcolor, $xhtml,
         $icon_xhtml, $title, %selected, @temp );

    @options = &Anatomy::Menus::control_info();

    @menu = ( [ "", "Control menu" ] );

    foreach $o ( @{ $options } )
    {
        if ( exists $o->{"request"} ) {
            $selected{ $o->{"request"} } = 1;
        }
    }
    
    if ( grep { exists $_->{"checked"} and $_->{"checked"} == 0 } @{ $options } ) {
        $selected{"add_unchecked_row"} = 1;
    }

    if ( grep { exists $_->{"checked"} and $_->{"checked"} == 1 } @{ $options } ) {
        $selected{"add_checked_row"} = 1;
    }

    foreach $o ( @options )
    {
        $key = $o->{"request"};

        if ( $selected{ $key } ) {
            push @menu, [ $o->{"index"}, qq (&nbsp;*&nbsp;) . $o->{"menu"} ];
        } else {
            push @menu, [ $o->{"index"}, qq (&nbsp;&nbsp;&nbsp;) . $o->{"menu"} ];
        }
    }

    $xhtml = &Common::Widgets::select_menu( "ana_control_menu", \@menu, $menu[0]->[1], "grey_button",
                          "javascript:handle_menu(this.form.ana_control_menu,'show_control_menu')" );
    
    if ( $button )
    {
        $key = "ana_control_menu";
        
        $title = "Close control menu";
        
        $text = qq (Iconifies the control menu.);
        
        $fgcolor ||= "#ffffcc";
        $bgcolor ||= "#006666";
        
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

sub data_icon
{
    # Niels Larsen, October 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the data menu. 

    # Returns an xhtml string. 

    my ( $icon, $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $icon = "$Common::Config::img_url/sys_data_book.png";

    $key = "ana_data_menu";

    $title = "Data menu";

    $text = qq (Shows a menu with data that can be added to the tree view.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#006666";

    $xhtml = &Common::Widgets::data_icon( $icon, $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub data_menu
{
    # Niels Larsen, October 2004.

    # Generates a menu with names of data options. When a menu option 
    # is chosen the "ana_data_menu" parameter is set to the value of the 
    # index of the menu option: the first returns 0, the next 1 and so 
    # on. By default a cancel button is attached. (TODO)

    my ( $columns,     # Columns list - OPTIONAL
         $db,          # Database prefix
         $state,       # State hash
         $button,      # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    $button = 1 if not defined $button;

    my ( @options, %hilite, $o, @menu, $icon_xhtml, $key, $title, $text, 
         $fgcolor, $bgcolor, $xhtml );

    @options = &Anatomy::Menus::data_info( $db );

    if ( $columns ) {
        %hilite = map { $_->{"key"}, 1 } @{ $columns };
    } else {
        %hilite = ();
    }

    foreach $key ( "ana_statistics_menu_open", 
                   "ana_selections_menu_open" )
    {
        if ( $state->{ $key } ) { 
            $hilite{ $key } = 1;
        }
    }

    @menu = ( [ "", "Data menu" ] );

    foreach $o ( @options )
    {
        if ( $hilite{ $o->{"key"} } or $hilite{ $o->{"key"} ."_open" } ) {
            push @menu, [ $o->{"index"}, qq (&nbsp;*&nbsp;$o->{"menu"}) ];
        } else {
            push @menu, [ $o->{"index"}, qq (&nbsp;&nbsp;&nbsp;$o->{"menu"}) ];
        }            
    }

    $xhtml = &Common::Widgets::select_menu( "ana_data_menu", \@menu, $menu[0]->[1], "grey_button",
                            "javascript:handle_menu(this.form.ana_data_menu,'show_data_menu')" );

    if ( $button )
    {
        $key = "ana_data_menu";
        
        $title = "Close data menu";
        
        $text = qq (Iconifies the data menu.);

        $fgcolor ||= "#ffffcc";
        $bgcolor ||= "#006666";
        
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

sub delete_columns_button
{
    # Niels Larsen, October 2004.

    # A button with tooltip that deletes selected columns. 

    my ( $sid,    # Session id
         ) = @_; 

    # Returns an XHTML string. 

    return &Common::Widgets::delete_columns_button( $sid, '#ffffcc', '#006666' );
}

sub delete_selection_button
{
    # Niels Larsen, October 2004.

    # A button with tooltip that deletes a saved selection, given
    # by its index.

    my ( $db,     # Database prefix
         $sid,    # Session id
         $index,  # 
         ) = @_; 

    # Returns an XHTML string. 

    return &Common::Widgets::delete_selection_button( $sid, $index, $db, '#ffffcc', '#006666' );
}

sub help_icon
{
    # Niels Larsen, October 2004.

    # A button that activates a help window.

    my ( $db,     # Database prefix
         $sid,    # Session id
         ) = @_;

    # Returns an XHTML string. 

    return &Common::Widgets::help_icon( $db, "", 700, 600, $sid, '#006666' );
}

sub report_title
{
    # Niels Larsen, October 2004.
    
    # Creates a small bar with a close button. It is to be used 
    # in report windows.

    my ( $text,     # Title text
         ) = @_;

    # Reports an xhtml string.

    my ( $xhtml, $close );

    $close = qq (<img src="$Common::Config::img_url/sys_cancel.gif" border="0" alt="Cancel button" />);

    $xhtml = qq (
<table cellpadding="4" cellspacing="0" width="100%"><tr>
     <td align="left" class="ana_report_title_l" width="98%">$text</td>
     <td align="right" class="ana_report_title_r" width="1%"><a href="javascript:window.close()">$close</a></td>
</tr></table>

);

    return $xhtml;
}

sub save_selection_button
{
    # Niels Larsen, October 2004.

    # A button with tooltip that saves selection.

    my ( $db,     # Database prefix
         $sid,    # Session id
         ) = @_; 

    # Returns an XHTML string. 

    return &Common::Widgets::save_selection_button( $sid, $db, "Save terms", '#ffffcc', '#006666' );
}

sub search_icon
{
    # Niels Larsen, October 2004.

    # A button that activates a search window.

    my ( $db,    # Database prefix
         $sid,   # Session id
         ) = @_;

    # Returns an XHTML string. 

    return &Common::Widgets::search_icon( $db, 350, 550, $sid, "#006666" );
}

sub selections_icon
{
    # Niels Larsen, October 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the statistics menu. 

    # Returns an xhtml string. 

    my ( $icon, $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $icon = "$Common::Config::img_url/sys_folder_red.gif";

    $key = "ana_selections_menu";

    $title = "Anatomy selections menu";

    $text = qq (Shows a menu with user selected sets of anatomy terms or groups.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#006666";

    $xhtml = &Common::Widgets::selections_icon( $icon, $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub selections_menu
{
    # Niels Larsen, October 2004.

    # Generates a menu with select and save options that allow the user
    # to save named sets of functions or function groups to be used later.
    # If sets have been saved, their names appear in the menu. If a set 
    # is chosen, the display becomes the subtree that exactly spans the 
    # subset. 

    my ( $sid,       # Session id
         $db,        # Database prefix
         $title,     # Selection title - OPTIONAL
         $button,    # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    $button = 1 if not defined $button;

    my ( @options, @menu, $o, $menu, $key, $text, $fgcolor, $bgcolor, $xhtml,
         $icon_xhtml, $idstr );

    @options = &Anatomy::Menus::selections_info( $sid, $db );

    if ( @options )
    {
        @menu = ( [ "", "Selections menu" ] );

        foreach $o ( @options )
        {
            if ( $o->{"menu"} eq $title ) {
                push @menu, [ $o->{"index"}, qq (&nbsp;*&nbsp;) . $o->{"menu"} ];
            } else {
                push @menu, [ $o->{"index"}, qq (&nbsp;&nbsp;&nbsp;) . $o->{"menu"} ];
            }
        }        
        
        $xhtml = &Common::Widgets::select_menu( "ana_selections_menu", \@menu,
                                                $menu[0]->[1], "grey_button",
              "javascript:handle_menu(this.form.ana_selections_menu,'restore_terms_selection')" );
    
        if ( $button )
        {
            $key = "ana_selections_menu";
            
            $title = "Close selections menu";
            
            $text = qq (Removes the menu with selected sets of anatomy terms.);
            
            $fgcolor ||= "#ffffcc";
            $bgcolor ||= "#006666";
            
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
    else {
        return;
    }
}

sub statistics_icon
{
    # Niels Larsen, October 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the statistics menu. 

    # Returns an xhtml string. 

    my ( $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $key = "ana_statistics_menu";

    $title = "Statistics menu";

    $text = qq (Shows a menu from which columns with system provided anatomy statistics can be )
          . qq (added or removed. Asterisks indicate the option(s) currently selected.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#006666";

    $xhtml = &Common::Widgets::statistics_icon( $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub statistics_menu
{
    # Niels Larsen, October 2004.

    # Generates a menu with names of statistics options. When a menu option 
    # is chosen the "ana_statistics_menu" parameter is set to the value of the 
    # index of the menu option: the first returns 0, the next 1 and so on. By
    # default a cancel button is attached. 

    my ( $db,          # Database prefix
         $columns,     # Columns list - OPTIONAL
         $button,      # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    $button = 1 if not defined $button;

    my ( @options, %hilite, $o, @menu, $icon_xhtml, $key, $title, $text, 
         $fgcolor, $bgcolor, $xhtml );

    @options = &Anatomy::Menus::statistics_info( $db );

    if ( $columns ) {
        %hilite = map { $_->{"key"}, 1 } @{ $columns };
    } else {
        %hilite = ();
    }

    @menu = ( [ "", "Statistics menu" ] );

    foreach $o ( @options )
    {
        if ( $hilite{ $o->{"key"} } ) {
            push @menu, [ $o->{"index"}, qq (&nbsp;*&nbsp;$o->{"menu"}) ];
        } else {
            push @menu, [ $o->{"index"}, qq (&nbsp;&nbsp;&nbsp;$o->{"menu"}) ];
        }            
    }

    $xhtml = &Common::Widgets::select_menu( "ana_statistics_menu", \@menu,
                                            $menu[0]->[1], "grey_button",
                  "javascript:handle_menu(this.form.ana_statistics_menu,'add_statistics_column')" );

    if ( $button )
    {
        $key = "ana_statistics_menu";
        
        $title = "Close statistics menu";
        
        $text = qq (Removes the ontology statistics menu.);

        $fgcolor ||= "#ffffcc";
        $bgcolor ||= "#006666";

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

