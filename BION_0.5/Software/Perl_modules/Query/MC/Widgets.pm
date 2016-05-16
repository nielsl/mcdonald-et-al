package Query::MC::Widgets;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Widget routines specific to miRConnect.
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &downloads_icon
                 &downloads_panel
                 &help_icon
                 );

use Common::Config;
use Common::Messages;

use Common::Widgets;

use Registry::Get;
use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Default colors, 

our $FG_color = "#ffffcc";
our $BG_color = "#666666";

# Viewer name,

our $Viewer_name = "query_viewer";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub downloads_icon
{
    # Niels Larsen, July 2009.
    
    my ( $sid,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $descr = "Downloads comma-separated tables for a given miRNA or miRNA family,"
            ." either all genes, or just the ones being shown in the browser.";

    $args = {
        "viewer" => $Viewer_name,
        "request" => "downloads_panel",
        "sid" => $sid,
        "title" => "Downloads Panel",
        "description" => $descr,
        "icon" => "sys_download.png",
        "height" => 400,
        "width" => 500,
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 250,
    };

    return &Common::Widgets::window_icon( $args );
}

sub downloads_panel
{
    # Niels Larsen, July 2009.

    # Builds a menu structure of available download options. The structure 
    # is then passed on to a generic report page rendering routine along with 
    # settings for form values and looks.

    my ( $args,           # Arguments hash
         ) = @_;

    # Returns an XHTML string.

    my ( $menu, @opts, $xhtml, $page_descr, $but_descr, $sub_menu,
         $filename );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer sid uri_path ) ],
        "HR:2" => [ qw ( params ) ],
    });

    $filename = $args->params->{"mirna_single"};
    $filename = $args->params->{"mirna_family"} if not $filename;
    $filename = "?" if not $filename;

    $filename =~ s/\*/-star/;

    $sub_menu = Query::MC::Menus->downloads_menu( $filename );
    push @opts, Registry::Get->new( "options" => [ $sub_menu->options ] );

    $menu = Registry::Get->new();
    $menu->options( \@opts );

    if ( $filename eq "?" )
    {
        $page_descr = qq (
The table data can be downloaded here, choices below. There are mouse-over 
explanations on the titles. The download file needs a better name, but we 
recommend keeping the .csv ending.
);
    } 
    else
    {
        $page_descr = qq (
The table data for $filename can be downloaded here, choices below. There are 
mouse-over explanations on the titles.
);
    }

    $but_descr = qq (
Pressing the button should make data arrive at your browser
in a pop-up window.
);

    $xhtml = &Common::Widgets::form_page(
        $menu,
        {
            "form_name" => "downloads_panel",
            "param_key" => "download_keys",
            "param_values" => "download_values",
            
            "viewer" => $args->viewer,
            "session_id" => $args->sid,
            "uri_path" => $args->uri_path,
            
            "header_icon" => "sys_download.png",
            "header_title" => "Download data",
            "description" => $page_descr,
            
            "buttons" => [{
                "type" => "submit",
                "request" => "request",
                "value" => "Download",
                "description" => $but_descr,
                "style" => "grey_button",
                          }],
        });
    
    return $xhtml;
}

sub help_icon
{
    # Niels Larsen, July 2009.
    
    my ( $sid,
         $request,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $request //= "help";

    if ( $request eq "help_mirconnect" ) {
        $descr = "Displays credits and description of usage in a pop-up window.";
    } else {
        $descr = "Provides help in a pop-up window.";
    }

    $args = {
        "viewer" => $Viewer_name,
        "request" => $request,
        "sid" => $sid,
        "title" => "Help Window",
        "description" => $descr,
        "icon" => "sys_help2.gif",
        "height" => 700,
        "width" => 600,
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
    };

    return &Common::Widgets::window_icon( $args );
}

1;

__END__
