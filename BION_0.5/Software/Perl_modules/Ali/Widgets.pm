package Ali::Widgets;     #  -*- perl -*-

# Alignment related widgets that produce strings of XHTML. They typically
# define strings, styles and images and then invoke the generic equivalent.
# They do not reach into database. It is okay to use arguments that are 
# complex data structures (like state hash), whereas in Common::Widgets 
# the arguments should be simple. 

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &col_collapse_down
                 &col_collapse_up
                 &col_zoom_down
                 &col_zoom_up
                 &control_icon
                 &control_menu
                 &downloads_icon
                 &downloads_panel
                 &features_icon
                 &features_menu
                 &features_panel
                 &format_header
                 &format_page
                 &help_icon
                 &inputdb_icon
                 &inputdb_menu
                 &nav_begin
                 &nav_begin_rows
                 &nav_bottom
                 &nav_bottom_cols
                 &nav_buttons
                 &nav_down
                 &nav_down_cols
                 &nav_end
                 &nav_end_rows
                 &nav_left
                 &nav_left_rows
                 &nav_menus
                 &nav_reset
                 &nav_right
                 &nav_right_rows
                 &nav_top
                 &nav_top_cols
                 &nav_up
                 &nav_up_cols
                 &nav_zoom_in
                 &nav_zoom_out
                 &pos_info
                 &prefs_panel
                 &print_icon
                 &print_panel
                 &row_collapse_down
                 &row_collapse_up
                 &row_zoom_down
                 &row_zoom_up
                 &user_icon
                 &user_menu
                 );

use Common::Config;
use Common::Messages;

use Ali::Menus;

use Common::Names;
use Common::Options;
use Common::Widgets;

# >>>>>>>>>>>>>>>>>>>>>>>> WIDGET SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Viewer_name = "array_viewer";

# Default colors, 

our $FG_color = "#ffffcc";
our $BG_color = "#006666";

# Default tooltip settings,

our $TT_border = 3;
our $TT_textsize = "12px";
our $TT_captsize = "12px";
our $TT_delay = 300;   # milliseconds before tooltips show

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub col_collapse_down
{
    # Niels Larsen, April 2006.
    
    # Returns a javascript link that turns off the column collapse feature.

    my ( $active,
        ) = @_;

    # Returns an XHTML string. 

    my ( $args, $xhtml );

    $args = {
        "request" => "toggle_col_collapse",
        "label" => "C",
        "tiptitle" => "Collapse Columns (on)",
        "tiptext" => qq (Only columns containing data are currently shown. Press here)
                   . qq ( to reset the behavior so all columns are shown as they are in the original alignment.),
        "class" => "toggle_down",
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_button( $args );
    
    return $xhtml;
}

sub col_collapse_up
{
    # Niels Larsen, April 2006.

    # Returns a javascript link that turns on the column collapse feature.

    my ( $active,
        ) = @_;

    # Returns a string. 

    my ( $args, $xhtml );

    $args = {
        "request" => "toggle_col_collapse",
        "label" => "C",
        "tiptitle" => "Collapse Columns (off)",
        "tiptext" => qq (Removes gap-only columns from the display. This is useful for)
                   . qq ( skipping the stretches of gap-only columns that often occur in alignments.),
        "class" => "toggle_up",
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_button( $args );

    return $xhtml;
}

sub col_zoom_down
{
    # Niels Larsen, April 2006.

    my ( $active,
        ) = @_;

    my ( $args, $xhtml );

    $args = {
        "request" => "toggle_col_zoom",
        "label" => "V",
        "tiptitle" => "Vertical zoom (on)",
        "tiptext" => qq (Vertical-only zoom enabled, i.e. zoom only stretches/shrinks the)
                   . qq ( display along the vertical axis, but does not change which columns are visible.),
        "class" => "toggle_down",
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_button( $args );

    return $xhtml;
}

sub col_zoom_up
{
    # Niels Larsen, April 2006.

    my ( $active,
        ) = @_;

    my ( $args, $xhtml );

    $args = {
        "request" => "toggle_col_zoom",
        "label" => "V",
        "tiptitle" => "Vertical zoom (off)",
        "tiptext" => qq (Vertical-only zoom disabled, i.e. zoom stretches/shrinks the display)
                   . qq ( both horizontally and vertically.),
        "class" => "toggle_up",
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_button( $args );

    return $xhtml;
}

sub control_icon
{
    # Niels Larsen, May 2007.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the alignment control menu. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args );

    $args = {
        "name" => "ali_control_menu",
        "title" => "Control menu",
        "description" => qq (Shows a menu of control panels for setting preferences, download and print.),
        "icon" => "sys_params_large.png",
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
        "active" => $active //= 1,
    };

    return &Common::Widgets::menu_icon( $args );
}

sub control_menu
{
    my ( $sid,
         ) = @_;

    my ( $name, $menu, $xhtml );

    $menu = Ali::Menus->control_menu( $sid );

    $name = $menu->name;
    $menu->onchange( "javascript:handle_control_menu(this.form.$name)" );

    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $menu->selected( 0 );

    $menu->session_id( $sid );

    $xhtml = &Common::Widgets::pulldown_menu( $menu, { "mark_selected" => 0 } );
    
    return $xhtml;
}

sub downloads_icon
{
    # Niels Larsen, August 2008.
    
    my ( $sid,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $descr = "Downloads fasta-formatted sequences - aligned or unaligned - for either the"
        ." whole dataset, or the visible part only.";

    $args = {
        "viewer" => $Viewer_name,
        "request" => "ali_downloads_panel",
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
    # Niels Larsen, May 2007.

    # Builds a menu structure of available download options. The structure 
    # is then passed on to a generic report page rendering routine along with 
    # settings for form values and looks.

    my ( $args,           # Arguments hash
         ) = @_;

    # Returns an XHTML string.

    my ( $menu, @opts, $xhtml, $page_descr, $but1_descr, $sub_menu );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer sid uri_path ali_name ) ],
    });

    $sub_menu = Ali::Menus->downloads_menu( $args->ali_name );
    push @opts, Registry::Get->new( "options" => [ $sub_menu->options ] );

    $menu = Registry::Get->new();
    $menu->options( \@opts );

    $page_descr = qq (
Different types of aligned and un-aligned sequences can be
downloaded here, choices below. There are mouse-over explanations
on the titles.
);

    $but1_descr = qq (
Pressing the button should make data arrive at your browser
in a pop-up window.
);

    $xhtml = &Common::Widgets::form_page( $menu, {

        "form_name" => "downloads_panel",
        "param_key" => "ali_download_keys",
        "param_values" => "ali_download_values",

        "viewer" => $args->viewer,
        "session_id" => $args->sid,
        "uri_path" => $args->uri_path,

        "header_icon" => "sys_download.png",
        "header_title" => "Download data",
        "description" => $page_descr,

        "tt_fgcolor" => "$FG_color",
        "tt_bgcolor" => "#666666",
        "tt_border" => $TT_border,
        "tt_textsize" => $TT_textsize,
        "tt_captsize" => $TT_captsize,
        "tt_delay" => 300,

        "buttons" => [{
            "type" => "submit",
            "request" => "request",
            "value" => "Download",
            "description" => $but1_descr,
            "style" => "grey_button",
        }],
        });

    return $xhtml;
}

sub features_icon
{
    # Niels Larsen, May 2007.
    
    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args );

    $args = {
        "name" => "ali_features_menu",
        "title" => "Highlights menu",
        "description" =>
            qq (Lists available features and highlights that can be toggled one by one.),
        "icon" => "sys_paint.png",
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_delay" => $TT_delay,
        "tt_width" => 200,
        "active" => $active //= 1,
    };

    return &Common::Widgets::menu_icon( $args );
}

sub features_menu
{
    my ( $sid,
         $state,
         ) = @_;

    my ( $name, $menu, $xhtml );

    $menu = &Storable::dclone( $state->{"ali_features"} );
    $menu->prune_expr( '$_->name ne "ali_sid_text"' );
    
    $name = $menu->name;
    $menu->onchange( "javascript:handle_menu(this.form.$name,'handle_$name')" );

    $menu->css( "grey_menu" );
    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $menu->session_id( $sid );

    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

sub features_panel
{
    # Niels Larsen, May 2007.

    # Builds a menu structure of the features/highlights that the viewer can
    # show and that are registered with the current project. Those relevant 
    # to the current dataset are shown changable, the with only their values.
    # The structure, plus settings for form values and looks, are sent to a
    # generic report page routine and rendered.

    my ( $args,           # Arguments hash
         ) = @_;

    # Returns an XHTML string.

    my ( $viewer, $dataset, $menu, $ft_menu, $opts, @opts, $xhtml, 
         $but1_descr, $page_descr, $type, $title );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( viewer sid uri_path ) ],
        "O:2" => "features",
    });

    $menu = Registry::Get->new( "options" => [ $args->features ] );

    $page_descr = qq (
Lists available highlights. Feature choices can be saved for the current dataset, 
or as default for whenever that feature appears elsewhere. There are mouse-over
explanations on each title.
);
    
    $but1_descr = qq (Saves the chosen highlights and makes them the default for)
                . qq ( this feature elsewhere.);

    $xhtml = &Common::Widgets::form_page( $menu, {

        "form_name" => "features_panel",
        "param_key" => "ali_features_keys",
        "param_values" => "ali_features_values",

        "viewer" => $args->viewer,
        "session_id" => $args->sid,
        "uri_path" => $args->uri_path,

        "header_icon" => "sys_params_large.png",
        "header_title" => "Configure highlights",
        "description" => $page_descr,

        "tt_fgcolor" => "$FG_color",
        "tt_bgcolor" => "#666666",
        "tt_border" => $TT_border,
        "tt_textsize" => $TT_textsize,
        "tt_captsize" => $TT_captsize,
        "tt_delay" => 300,

        "buttons" => [{
            "type" => "submit",
            "request" => "request",
            "value" => "Save",
            "description" => "Updates the view.",
            "style" => "grey_button",
        },{
            "type" => "submit",
            "request" => "request",
            "value" => "Save as default",
            "description" => $but1_descr,
            "style" => "grey_button",
        },{
            "type" => "submit",
            "request" => "request",
            "onclick" => qq (this.form.target='_self'),
            "value" => "Reset",
            "description" => "Resets the form to system defaults.",
            "style" => "grey_button",
        }],
    });

    return $xhtml;
}

sub format_header
{
    my ( $state,
        ) = @_;

    my ( $text, $jvs_url, $height, $width );

    $jvs_url = "$Common::Config::jvs_url/cross-browser.com";

    $height = $state->{"ali_prefs"}->{"ali_img_height"}."px";
    $width = $state->{"ali_prefs"}->{"ali_img_width"}."px";

    $text = qq (

<script type='text/javascript' src='$jvs_url/x/x_core.js'></script>
<script type='text/javascript' src='$jvs_url/x/x_event.js'></script>

<script type='text/javascript' src='$jvs_url/x/lib/xenabledrag.js'></script>

<style type='text/css'>

.Viewer {
  position:relative;
  overflow:hidden;
  width:$width;
  height:$height;
}

.ViewerImg {
  width:$width;
  height:$height;
  border:none;
}

</style>

<script type='text/javascript'>

function image_tip( title, text )
{
    return overlib( text,LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,title,FGCOLOR,'$FG_color',WIDTH,250,BGCOLOR,'$BG_color',BORDER,3,DELAY,$TT_delay); 
}

</script>
);

    return $text;
}
    
sub format_page
{
    # Niels Larsen, September 2005.

    # Formats the page content and returns XHTML.

    my ( $sid,          # Session id
         $state,        # State hash
         $inputdb,      # Alignment path 
         ) = @_;

    # Returns an xhtml string.

    my ( $xhtml, $colstr, $rowstr, $ali_image, $height, $width, $ses_dir,
         $buttons_xhtml, $img_map, @img_map, $area, $border );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> NAVIGATION MENUS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $xhtml = &Ali::Widgets::nav_menus( $sid, $state );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> NAVIGATION BUTTONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $buttons_xhtml = &Ali::Widgets::nav_buttons( $sid, $state );
    $xhtml .= &Common::Widgets::spacer( 5 );

    $xhtml .= qq (
<table cellpadding="0" cellspacing="0" width="100%" border="0">
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $state->{"ali_messages"} and @{ $state->{"ali_messages"} } )
    {
        $xhtml .= "<tr><td>". &Common::Widgets::message_box( $state->{"ali_messages"} ) ."</td></tr>\n";
        $xhtml .= qq (<tr><td height="20">&nbsp;</td></tr>\n);
    }

    $height = $state->{"ali_prefs"}->{"ali_img_height"}; #  + 10;
    $width = $state->{"ali_prefs"}->{"ali_img_width"}; #  + 10;

    if ( $state->{"ali_prefs"}->{"ali_with_border"} ) {
        $border = 1;   # 1 pixel table border
    }

    $xhtml .= qq (   <tr><td align="left">$buttons_xhtml</td></tr>
   <tr><td height="2">&nbsp;</td></tr>
   <tr><td align="left" valign="middle" height="$height" width="$width">
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> IMAGE AREA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ali_image = "/Sessions/$sid/". $state->{"ali_img_file"};

    $colstr = $state->{"ali_colstr"};
    $rowstr = $state->{"ali_rowstr"};

    $ses_dir = "$Common::Config::ses_dir/$sid";

    if ( defined $border ) {
        $xhtml .= qq (<table cellpadding="0" cellspacing="0" border="1"><tr><td>\n);
    }

    $xhtml .= qq (<div class="Viewer">\n);

    $xhtml .= qq (<map id="ali_image_map" name="ali_image_map">\n);

    if ( $state->{"ali_img_map_file"} )
    {
        # The map file format changed from list html <area .. /> lines to lines of 
        #  [ shape, "xbeg,ybeg,xend,yend", title, text ]. The test that follows is
        # to avoid crash if one of the old type maps are encountered, as might 
        # happen with accounts that have not been touched for a long time. 

        $img_map = &Common::File::retrieve_file( "$ses_dir/". $state->{"ali_img_map_file"} );

        if ( ref $img_map->[0] )
        {

            foreach $area ( @{ $img_map } )
            {
                push @img_map, qq (<area shape="$area->[0]" coords="$area->[1]")
                    . qq ( onmouseover="image_tip('$area->[2]', '$area->[3]')")
                    . qq ( onmouseout="return nd();" alt="" />);
            }
            
            $xhtml .= join "\n", @img_map;
        }
    }

    $xhtml .= qq (\n</map>\n\n);

    $xhtml .= qq (   <img id="ali_image" name="ali_image" class="ViewerImg")
            . qq ( src="$ali_image" usemap="#ali_image_map" alt="" />\n);

    $xhtml .= qq (</div>\n);

    if ( defined $border ) {
        $xhtml .= qq (</td></tr></table>\n);
    }

    $xhtml .= qq (
   </td></tr>
</table>

<input type="hidden" name="request" value="" />
<input type="hidden" name="inputdb" value="$inputdb" />

<input type="hidden" name="ali_show_widget" value="" />
<input type="hidden" name="ali_hide_widget" value="" />

<input type="hidden" name="ali_colstr" value="$colstr" />
<input type="hidden" name="ali_rowstr" value="$rowstr" />

<input type="hidden" name="ali_image_area" value="" />

<table><tr><td height="20">&nbsp;</td></tr></table>

);

    return $xhtml;
}

sub help_icon
{
    # Niels Larsen, August 2008.
  
    # Configures a call to Common::Widgets::window_icon, which creates a javascript
    # link that opens a window and fills it with help text.

    my ( $sid,            # Session id 
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $descr = "Offers help with navigation and use of this page.";

    $args = {
        "viewer" => $Viewer_name,
        "request" => "ali_help_panel",
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


sub inputdb_icon
{
    # Niels Larsen, February 2006.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the alignment control menu. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args );

    $args = {
        "name" => "ali_inputdb_menu",
        "title" => "Data menu",
        "description" => qq (Shows a menu with other alignments to choose from.),
        "icon" => "sys_data_book.png",
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
        "active" => $active //= 1,
    };

    return &Common::Widgets::menu_icon( $args );
}

sub inputdb_menu
{
    # Niels Larsen, August 2005.

    # Generates a menu where the user can highlight and overlay external data.

    my ( $sid,           # Session id
         $state,          # Menu structure
         ) = @_;

    # Returns an xhtml string. 

    my ( $menu, $file, $xhtml, $js_func );

    $file = "$Common::Config::www_dir/$state->{'ali_www_path'}/navigation_menu";

    $menu = Ali::Menus->inputdb_menu( $sid, $file );

    $js_func = "javascript:handle_menu(this.form.ali_inputdb_menu,'handle_ali_inputdb_menu')";

    $menu->onchange( $js_func, );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu, { "close_name" => "ali_inputdb_menu" } );
    
    return $xhtml;
}

sub nav_begin
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should show the left edge of the alignment. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_begin.png",
        "request" => "ali_nav_begin",
        "tiptitle" => "Go to beginning",
        "tiptext" => qq (Moves to the left edge of the alignment.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_begin_rows
{
    # Niels Larsen, September 2007.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should should the left edge of the alignment,
    # using the current row set. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_begin_rows.png",
        "request" => "ali_nav_begin_rows",
        "tiptitle" => "Go to beginning fixed",
        "tiptext" => qq (Moves to the left edge of the alignment, showing the rows currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_bottom
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should show the bottom of the alignment. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_bottom.png",
        "request" => "ali_nav_bottom",
        "tiptitle" => "Go to bottom",
        "tiptext" => qq (Moves to the bottom edge of the alignment.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_bottom_cols
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should show the bottom of the alignment, using
    # same as current columns.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_bottom_cols.png",
        "request" => "ali_nav_bottom_cols",
        "tiptitle" => "Go to bottom fixed",
        "tiptext" => qq (Moves to the bottom edge of the alignment, showing only the columns currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_buttons
{
    # Niels Larsen, March 2006.

    # Returns XHTML for the navigation buttons on the page. The buttons come
    # with tooltips and 2-3 lines of javascript to submit the form. Buttons 
    # appear only when it makes sense to press them, e.g. the right-scroll 
    # button disappears when the right edge is visible, and so on. Buttons 
    # may disappear but they never shift around.

    my ( $sid,          # Session id
         $state,        # State hash
         ) = @_;

    # Returns a string.

    my ( $clip, $nav_buttons, $zoom_pct, $ali_image, $xhtml,
         $button, $td, $text, $cancel_icon );

    $clip = $state->{"ali_clipping"};

    # >>>>>>>>>>>>>>>>>>>>>>> MAKE HELPER HASH <<<<<<<<<<<<<<<<<<<<<<<<<

    # If a button should show, make its code; otherwise make a spacer of 
    # the same size. The $nav_buttons hash holds this XHTML, which is then
    # combined in the next section.

    # Left and begin buttons,

    if ( $clip->{"left"} <= 0 )
    {
        $nav_buttons->{"left"} = qq (<td width="20">&nbsp;</td>);
        $nav_buttons->{"begin"} = qq (<td width="22">&nbsp;</td>);

        if ( $state->{"ali_prefs"}->{"ali_with_row_collapse"} )
        {
            $nav_buttons->{"left_rows"} = qq (<td width="20">&nbsp;</td>);
            $nav_buttons->{"begin_rows"} = qq (<td width="20">&nbsp;</td>);
        }
    }
    else 
    {
        $nav_buttons->{"left"} = "<td>". &Ali::Widgets::nav_left() ."</td>";
        $nav_buttons->{"begin"} = "<td>". &Ali::Widgets::nav_begin() ."</td>";

        if ( $state->{"ali_prefs"}->{"ali_with_row_collapse"} )
        {
            $nav_buttons->{"left_rows"} = "<td>". &Ali::Widgets::nav_left_rows() ."</td>";
            $nav_buttons->{"begin_rows"} = "<td>". &Ali::Widgets::nav_begin_rows() ."</td>";
        }
    }

    # Right and end buttons,

    if ( $clip->{"right"} <= 0 )
    {
        $nav_buttons->{"right"} = qq (<td width="21">&nbsp;</td>);
        $nav_buttons->{"end"} = qq (<td width="22">&nbsp;</td>);

        if ( $state->{"ali_prefs"}->{"ali_with_row_collapse"} )
        {
            $nav_buttons->{"right_rows"} = qq (<td width="20">&nbsp;</td>);
            $nav_buttons->{"end_rows"} = qq (<td width="20">&nbsp;</td>);
        }        
    }
    else
    {
        $nav_buttons->{"right"} = "<td>". &Ali::Widgets::nav_right() ."</td>";
        $nav_buttons->{"end"} = "<td>". &Ali::Widgets::nav_end() ."</td>";

        if ( $state->{"ali_prefs"}->{"ali_with_row_collapse"} )
        {
            $nav_buttons->{"right_rows"} = "<td>". &Ali::Widgets::nav_right_rows() ."</td>";
            $nav_buttons->{"end_rows"} = "<td>". &Ali::Widgets::nav_end_rows() ."</td>";
        }
    }

    # Up and top buttons,

    if ( $clip->{"top"} <= 0 )
    {
        $nav_buttons->{"up"} = qq (<td width="20">&nbsp;</td>);
        $nav_buttons->{"top"} = qq (<td width="20">&nbsp;</td>);

        if ( $state->{"ali_prefs"}->{"ali_with_col_collapse"} )
        {
            $nav_buttons->{"up_cols"} = qq (<td width="20">&nbsp;</td>);
            $nav_buttons->{"top_cols"} = qq (<td width="20">&nbsp;</td>);
        }
    }
    else
    {
        $nav_buttons->{"up"} = "<td>". &Ali::Widgets::nav_up() ."</td>";
        $nav_buttons->{"top"} = "<td>". &Ali::Widgets::nav_top() ."</td>";

        if ( $state->{"ali_prefs"}->{"ali_with_col_collapse"} )
        {
            $nav_buttons->{"up_cols"} = "<td>". &Ali::Widgets::nav_up_cols() ."</td>";
            $nav_buttons->{"top_cols"} = "<td>". &Ali::Widgets::nav_top_cols() ."</td>";
        }
    }

    # Down and bottom buttons,

    if ( $clip->{"bottom"} <= 0 )
    {
        $nav_buttons->{"down"} = qq (<td width="20">&nbsp;</td>);
        $nav_buttons->{"bottom"} = qq (<td width="20">&nbsp;</td>);

        if ( $state->{"ali_prefs"}->{"ali_with_col_collapse"} )
        {        
            $nav_buttons->{"down_cols"} = qq (<td width="20">&nbsp;</td>);
            $nav_buttons->{"bottom_cols"} = qq (<td width="20">&nbsp;</td>);
        }
    }
    else
    {
        $nav_buttons->{"down"} = "<td>". &Ali::Widgets::nav_down() ."</td>";
        $nav_buttons->{"bottom"} = "<td>". &Ali::Widgets::nav_bottom() ."</td>";

        if ( $state->{"ali_prefs"}->{"ali_with_col_collapse"} ) 
        {
            $nav_buttons->{"down_cols"} = "<td>". &Ali::Widgets::nav_down_cols() ."</td>";
            $nav_buttons->{"bottom_cols"} = "<td>". &Ali::Widgets::nav_bottom_cols() ."</td>";
        }
    }

    # Reset button,

    $nav_buttons->{"reset"} = "<td>". &Ali::Widgets::nav_reset() ."</td>";

    # Zoom in/out buttons,

    if ( $state->{"ali_pix_per_row"} <= 1 ) {
        $nav_buttons->{"zoom_out"} = qq (<td width="21">&nbsp;</td>);
    } else {
        $nav_buttons->{"zoom_out"} = "<td>". &Ali::Widgets::nav_zoom_out() ."</td>";
    }
        
    if ( $state->{"ali_data_cols"} > 3 ) {
        $nav_buttons->{"zoom_in"} = "<td>". &Ali::Widgets::nav_zoom_in() ."</td>";
    } else {
        $nav_buttons->{"zoom_in"} = qq (<td width="21">&nbsp;</td>);
    }

    # Column and row zoom buttons, 

    # TODO: enable, but needs parameter passing fixes, reset button and displey
    # improvement.

#     if ( $state->{"ali_with_col_zoom"} ) {
#         $nav_buttons->{"col_zoom"} = "<td>". &Ali::Widgets::col_zoom_up() ."</td>";
#     } else {
#         $nav_buttons->{"col_zoom"} = "<td>". &Ali::Widgets::col_zoom_down() ."</td>";
#     }

#     if ( $state->{"ali_with_row_zoom"} ) {
#         $nav_buttons->{"row_zoom"} = "<td>". &Ali::Widgets::row_zoom_up() ."</td>";
#     } else {
#         $nav_buttons->{"row_zoom"} = "<td>". &Ali::Widgets::row_zoom_down() ."</td>";
#     }

    # Column collapse button, 

    if ( $state->{"ali_prefs"}->{"ali_with_col_collapse"} ) {
        $nav_buttons->{"col_collapse"} = "<td>". &Ali::Widgets::col_collapse_down() ."</td>";
    } else {
        $nav_buttons->{"col_collapse"} = "<td>". &Ali::Widgets::col_collapse_up() ."</td>";
    }

    # Row collapse button, 

    if ( $state->{"ali_prefs"}->{"ali_with_row_collapse"} ) {
        $nav_buttons->{"row_collapse"} = "<td>". &Ali::Widgets::row_collapse_down() ."</td>";
    } else {
        $nav_buttons->{"row_collapse"} = "<td>". &Ali::Widgets::row_collapse_up() ."</td>";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CREATE XHTML <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Right/left begin/end buttons,
    
    $xhtml = qq (<table cellpadding="0" cellspacing="0"><tr>
<td>
   <table cellpadding="0" cellspacing="1"><tr>
      $nav_buttons->{"begin"}
      $nav_buttons->{"left"}
      $nav_buttons->{"right"}
      $nav_buttons->{"end"}
        <td width="10">&nbsp;</td>
      $nav_buttons->{"col_collapse"}
   </tr></table>
</td>
);

#      $nav_buttons->{"row_collapse"}
#     # Right/left begin/end buttons with fixed rows,

#     if ( $state->{"ali_prefs"}->{"ali_with_row_collapse"} )
#     {
#         $xhtml .= qq (
# <td>
#    <table cellpadding="0" cellspacing="1"><tr>
#       $nav_buttons->{"begin_rows"}
#       $nav_buttons->{"left_rows"}
#       $nav_buttons->{"right_rows"}
#       $nav_buttons->{"end_rows"}
#    </tr></table>
# </td>
# );
#     }
#     else {
#         $xhtml .= qq (<td width="81">&nbsp;</td>);
#     }

    # Up/down top/bottom buttons,

    $xhtml .= qq (
<td width="10">&nbsp;</td>
<td>
   <table cellpadding="0" cellspacing="1"><tr>
      $nav_buttons->{"top"}
      $nav_buttons->{"up"}
      $nav_buttons->{"down"}
      $nav_buttons->{"bottom"}
   </tr></table>
</td>
);

    # Up/down top/bottom buttons with fixed columns,

    if ( $state->{"ali_prefs"}->{"ali_with_col_collapse"} )
    {
        $xhtml .= qq (
<td>
   <table cellpadding="0" cellspacing="1"><tr>
      $nav_buttons->{"top_cols"}
      $nav_buttons->{"up_cols"}
      $nav_buttons->{"down_cols"}
      $nav_buttons->{"bottom_cols"}
   </tr></table>
</td>
);
    }
    else {
        $xhtml .= qq (<td width="81">&nbsp;</td>);
    }

    # Zoom buttons,

#      $nav_buttons->{"row_zoom"}
#      $nav_buttons->{"col_zoom"}
    
    $zoom_pct = $state->{"ali_prefs"}->{"ali_zoom_pct"};

    $xhtml .= qq (
<td width="10">&nbsp;</td>
<td>
   <table cellpadding="0" cellspacing="1"><tr>
      $nav_buttons->{"zoom_in"}
      <td><input type="text" name="ali_zoom_pct" size="4" value="$zoom_pct" maxlength="4" /></td> 
      $nav_buttons->{"zoom_out"}
   </tr></table>
</td>
);

    # Position info box,

    $text = ($state->{"ali_min_col"}+1) ."-". ($state->{"ali_max_col"}+1) ."/".
            ($state->{"ali_min_row"}+1) ."-". ($state->{"ali_max_row"}+1);

    $td = &Ali::Widgets::pos_info( $text );
    
    $xhtml .= qq (<td><table><tr><td>&nbsp;</td>$td</tr></table></td>\n);

    # Reset button,

    $xhtml .= qq (<td width="10">&nbsp;</td>$nav_buttons->{"reset"}\n);

    $xhtml .= qq (</tr></table>\n);

    return $xhtml;
}

sub nav_down
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page down. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_down.png",
        "request" => "ali_nav_down",
        "tiptitle" => "Scroll down",
        "tiptext" => qq (Scrolls one page down, with no page overlap.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_down_cols
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page down, using
    # current column set.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_down_cols.png",
        "request" => "ali_nav_down_cols",
        "tiptitle" => "Scroll down fixed",
        "tiptext" => qq (Scrolls one page down, with no overlap between pages. Displays only the columns currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_end
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should show the right edge of the alignment. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_end.png",
        "request" => "ali_nav_end",
        "tiptitle" => "Go to end",
        "tiptext" => qq (Moves to the right edge of the alignment.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_end_rows
{
    # Niels Larsen, September 2007.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should should the right edge of the alignment,
    # using the current row set. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_end_rows.png",
        "request" => "ali_nav_end_rows",
        "tiptitle" => "Go to end fixed",
        "tiptext" => qq (Moves to the right edge of the alignment, showing the rows currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_left
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page to the left.
    # Gap-only columns are shown.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_left.png",
        "request" => "ali_nav_left",
        "tiptitle" => "Scroll left",
        "tiptext" => qq (Scrolls one page left, with no page overlap.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_left_rows
{
    # Niels Larsen, September 2007.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page to the 
    # left, using the current row set.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_left_rows.png",
        "request" => "ali_nav_left_rows",
        "tiptitle" => "Scroll left fixed",
        "tiptext" => qq (Scrolls one page left, with no overlap between pages. Displays only the rows currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_menus
{
    # Niels Larsen, February 2004.

    # Composes the top row on the page with title, menus and/or icons. 

    my ( $sid,           # Session ID
         $state,         # State hash
         ) = @_;
    
    # Returns an array. 

    my ( $title, @l_widgets, @r_widgets, $xhtml, $menu, $dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TITLE BOX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $state->{"ali_title"} ) {
        $title = $state->{"ali_title"};
    } else {
        &error( qq (Alignment has no title (missing "ali_title" in state)) );
    }
    
    $title = &Common::Names::format_display_name( $title );
    
    push @l_widgets, &Common::Widgets::title_box( $title, "ali_title_box", 20, $FG_color, $BG_color );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DATA MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $state->{'ali_www_path'} and
         -r "$Common::Config::www_dir/$state->{'ali_www_path'}/navigation_menu.yaml" )
    {
        if ( $state->{"ali_inputdb_menu_open"} ) {
            push @l_widgets, &Ali::Widgets::inputdb_menu( $sid, $state );
        } else {
            push @l_widgets, &Ali::Widgets::inputdb_icon();
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> CONTROL MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $state->{"ali_control_menu_open"} ) {
        push @l_widgets, &Ali::Widgets::control_menu( $sid, $state );
    } else {
        push @l_widgets, &Ali::Widgets::control_icon();
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> HIGHLIGHTS MENU <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $state->{"ali_features_menu_open"} ) {
        push @l_widgets, &Ali::Widgets::features_menu( $sid, $state );
    } else {
        push @l_widgets, &Ali::Widgets::features_icon();
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRINT PANEL <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    push @l_widgets, &Ali::Widgets::print_icon( $sid );

    # >>>>>>>>>>>>>>>>>>>>>>>> DOWNLOADS PANEL <<<<<<<<<<<<<<<<<<<<<<<<<<<

    push @l_widgets, &Ali::Widgets::downloads_icon( $sid );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> USER MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $menu = Ali::Menus->user_menu( $sid );

    if ( @{ $menu->options } )
    {
        if ( $state->{"ali_user_menu_open"} ) {
            push @l_widgets, &Ali::Widgets::user_menu( $sid, undef, $menu );
        } else {
            push @l_widgets, &Ali::Widgets::user_icon();
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> HELP BUTTON <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    push @r_widgets, &Ali::Widgets::help_icon( $sid );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PUT IT TOGETHER <<<<<<<<<<<<<<<<<<<<<<<<<

    $xhtml = &Common::Widgets::spacer( 5 );
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, \@r_widgets );

    return $xhtml;
}

sub nav_reset
{
    # Niels Larsen, September 2007.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server that it should reset the view to the original.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_reset2.gif",
        "request" => "ali_nav_reset",
        "tiptitle" => "Reset to original",
        "tiptext" => qq (Resets the display to the original rows, columns and zoom level.)
            . qq ( It is just a way to escape if something goes wrong.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_right
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page to the right.
    # Gap-only columns are shown.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_right.png",
        "request" => "ali_nav_right",
        "tiptitle" => "Scroll right",
        "tiptext" => qq (Scrolls one page right, with no page overlap.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_right_rows
{
    # Niels Larsen, September 2007.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page to the 
    # right, using the current row set.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_right_rows.png",
        "request" => "ali_nav_right_rows",
        "tiptitle" => "Scroll right fixed",
        "tiptext" => qq (Scrolls one page right, with no overlap between pages. Displays only the rows currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_top
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should show the top of the alignment. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_top.png",
        "request" => "ali_nav_top",
        "tiptitle" => "Go to top",
        "tiptext" => qq (Moves to the top edge of the alignment.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_top_cols
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should show the top of the alignment, using
    # same as current columns.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_top_cols.png",
        "request" => "ali_nav_top_cols",
        "tiptitle" => "Go to top fixed",
        "tiptext" => qq (Moves to the top edge of the alignment, showing only the columns currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_up
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page up. 

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_up.png",
        "request" => "ali_nav_up",
        "tiptitle" => "Scroll up",
        "tiptext" => qq (Scrolls one page up, with no page overlap.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_up_cols
{
    # Niels Larsen, September 2005.
    
    my ( $active,
        ) = @_;

    # Returns a javascript link that submits the page with a signal 
    # to the server it should scroll the alignment one page up, using
    # current column set.

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_up_cols.png",
        "request" => "ali_nav_up_cols",
        "tiptitle" => "Scroll up fixed",
        "tiptext" => qq (Scrolls one page up, with no page overlap, showing only the columns currently in view.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_zoom_in
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should zoom in, i.e. show less data in the same
    # screen area, centered as before.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_zoom_in.png",
        "request" => "ali_nav_zoom_in",
        "tiptitle" => "Zoom in",
        "tiptext" => qq (Zooms in by the given percentage. Click on image to center it.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub nav_zoom_out
{
    # Niels Larsen, September 2005.
    
    # Returns a javascript link that submits the page with a signal 
    # to the server it should zoom out, i.e. show more data in the same
    # screen area, centered as before.

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml );

    $args = {
        "icon" => "$Common::Config::img_url/ali_zoom_out.png",
        "request" => "ali_nav_zoom_out",
        "tiptitle" => "Zoom out",
        "tiptext" => qq (Zooms out by the given percentage. Click on image to center it.),
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_icon( $args );
    
    return $xhtml;
}

sub pos_info
{
    # Niels Larsen, January 2006.
    
    # Returns a <td> element that renders a button with the column and row 
    # ranges currently displayed. 

    my ( $text,      # Text to display
         ) = @_;

    # Returns an xhtml string. 

    my ( $args, $xhtml, $tip );

    $tip = qq (Shows the column and row ranges in view, in alignment numbering.);

    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Positions',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3,DELAY,$TT_delay);

    $xhtml  = qq (   <td class="status_box")
            . qq (   onmouseover="return overlib('$tip',$args);")
            . qq (    onmouseout="return nd();">&nbsp;$text&nbsp;</td>);
    
    return $xhtml;
}

sub prefs_panel
{
    # Niels Larsen, May 2007.

    # Builds a menu structure of basic display preferences. The structure
    # is then passed on to a generic report page rendering routine along 
    # with settings for form values and looks.

    my ( $args,           # Arguments hash
         ) = @_;

    # Returns an XHTML string.

    my ( $viewer, $sid, $menu, $opts, @opts, $page_descr, $but2_descr, $xhtml );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer sid uri_path ) ],
        "HR:1" => "prefs",
    });
    
    $opts = &Common::Options::build_viewer_prefs_options(
        {
            "viewer" => $args->viewer,
            "prefs" => $args->prefs,
        });

    $menu = Registry::Get->new( "options" => [ Registry::Get->new( "options" => $opts ) ] );

    $page_descr = qq (
Lists basic viewer settings. Choices can be saved for the dataset in view 
(when this window was opened), or saved as default for all datasets not 
yet visited. There are mouse-over explanations on each title.
);

    $but2_descr = qq (
Saves the chosen settings and makes them default
for all datasets not yet visited.
);

    $xhtml = &Common::Widgets::form_page( $menu, {

        "form_name" => "prefs_panel",
        "param_key" => "ali_prefs_keys",
        "param_values" => "ali_prefs_values",

        "viewer" => $args->viewer,
        "session_id" => $args->sid,
        "uri_path" => $args->uri_path,

        "header_icon" => "sys_params_large.png",
        "header_title" => "Configure viewer settings",
        "description" => $page_descr,

        "tt_fgcolor" => "$FG_color",
        "tt_bgcolor" => "#666666",
        "tt_border" => $TT_border,
        "tt_textsize" => $TT_textsize,
        "tt_captsize" => $TT_captsize,
        "tt_delay" => 300,

        "buttons" => [{
            "type" => "submit",
            "request" => "request",
            "value" => "Save",
            "description" => "Updates the view.",
            "style" => "grey_button",
        },{
            "type" => "submit",
            "request" => "request",
            "value" => "Save as default",
            "description" => $but2_descr,
            "style" => "grey_button",
        },{
            "type" => "submit",
            "request" => "request",
            "onclick" => qq (this.form.target='_self'),
            "value" => "Reset",
            "description" => "Resets the form to system defaults.",
            "style" => "grey_button",
        }],
    });

    return $xhtml;
}

sub print_icon
{
    # Niels Larsen, August 2008.
    
    my ( $sid,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $descr = "Downloads a PNG or GIF formatted image of the visible alignment, in higher than screen resolution.";

    $args = {
        "viewer" => $Viewer_name,
        "request" => "ali_print_panel",
        "sid" => $sid,
        "title" => "Prints Panel",
        "description" => $descr,
        "icon" => "sys_photo.png",
        "height" => 400,
        "width" => 500,
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
    };

    return &Common::Widgets::window_icon( $args );
}

sub print_panel
{
    # Niels Larsen, May 2007.

    # Builds a page of available image download options. It is a form with a 
    # choices of format, resolution, image name and title.

    my ( $args,           # Arguments hash
         ) = @_;

    # Returns an XHTML string.

    my ( $menu, $sub_menu, $xhtml, $page_descr, $but1_descr, @opts, $ali );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer sid uri_path ali_name ) ],
    });

    $sub_menu = Ali::Menus->print_menu( $args->ali_name );
    push @opts, Registry::Get->new( "options" => [ $sub_menu->options ] );

    $menu = Registry::Get->new();
    $menu->options( \@opts );

    $page_descr = qq (
Downloads bitmap images with white background,
suitable for creating publication figures with third party tools
and for printing directly. We will improve this later with
vector-graphics like PDF and SVG.
);

    $but1_descr = qq (
Pressing the button should make an image file arrive in a 
pop-up window.
);

    $xhtml = &Common::Widgets::form_page( $menu, {

        "form_name" => "print_panel",
        "param_key" => "ali_print_keys",
        "param_values" => "ali_print_values",

        "viewer" => $args->viewer,
        "session_id" => $args->sid,
        "uri_path" => $args->uri_path,

        "header_icon" => "sys_photo.png",
        "header_title" => "Download printable image",
        "description" => $page_descr,

        "tt_fgcolor" => "$FG_color",
        "tt_bgcolor" => "#666666",
        "tt_border" => $TT_border,
        "tt_textsize" => $TT_textsize,
        "tt_captsize" => $TT_captsize,
        "tt_delay" => 300,

        "buttons" => [{
            "type" => "submit",
            "request" => "request",
            "value" => "Download",
            "description" => $but1_descr,
            "style" => "grey_button",
        }],
        });

    return $xhtml;
}

sub row_collapse_down
{
    # Niels Larsen, September 2007.

    # Returns a javascript link that turns on the row collapse feature.

    my ( $active,
        ) = @_;

    # Returns a string. 

    my ( $args, $xhtml );

    $args = {
        "request" => "toggle_row_collapse",
        "label" => "R",
        "tiptitle" => "Collapse Rows (on)",
        "tiptext" => qq (Only rows containing are currently shown. Press here)
                   . qq ( to reset the behavior so all rows are shown as they are in the original alignment.),
        "class" => "toggle_down",
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_button( $args );

    return $xhtml;
}

sub row_collapse_up
{
    # Niels Larsen, September 2007.

    # Returns a javascript link that turns on the row collapse feature.

    my ( $active,
        ) = @_;

    # Returns a string. 

    my ( $args, $xhtml );

    $args = {
        "request" => "toggle_row_collapse",
        "label" => "R",
        "tiptitle" => "Collapse Rows (off)",
        "tiptext" => qq (Removes gap-only rows from the display. This is useful for)
                   . qq ( skipping the sequences with gaps-only in certain alignment regions.),
        "class" => "toggle_up",
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_button( $args );

    return $xhtml;
}

sub row_zoom_up
{
    # Niels Larsen, April 2006.

    my ( $active,
        ) = @_;

    my ( $args, $xhtml );

    $args = {
        "request" => "toggle_row_zoom",
        "label" => "H",
        "tiptitle" => "Horizontal zoom (off)",
        "tiptext" => qq (Horizontal-only zoom disabled, i.e. zoom stretches/shrinks the display)
                   . qq ( both horizontally and vertically.),
        "class" => "toggle_up",
        "fgcolor" => $FG_color,
        "bgcolor" => $BG_color,
        "active" => $active //= 1,
    };

    $xhtml = &Common::Widgets::nav_button( $args );

    return $xhtml;
}

sub user_icon
{
    # Niels Larsen, January 2006.
    
    # Explain

    my ( $active,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args );

    $args = {
        "name" => "ali_user_menu",
        "title" => "User menu",
        "description" => qq (Shows a menu with user uploads and results.),
        "icon" => "sys_account.png",
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
        "active" => $active //= 1,
    };

    return &Common::Widgets::menu_icon( $args );
}

sub user_menu
{
    # Niels Larsen, January 2006.

    # Generates a menu with user uploads. An asterisk indicates options 
    # selected. 

    my ( $sid,        # Session id
         $display,    # Display structure
         ) = @_;

    # Returns an xhtml string. 

    my ( $ids, $menu, $xhtml, $name, $option, @divs );

    $menu = Ali::Menus->user_menu( $sid );

    if ( defined $display ) {
        $ids = $display->columns->match_options_ids( "name" => "ali_user_menu" );
    } else {
        $ids = [];
    }

    foreach $option ( $menu->options )
    {
        if ( $option->jid ) {
            $option->title( $option->title ." (job ". $option->jid .")" );
        } else {
            $option->title( $option->title );
        }
    }

    @divs = (
        [ "dna_ali", "DNA Alignments", "green_menu_divider" ],
        [ "rna_ali", "RNA Alignments", "green_menu_divider" ],
        [ "prot_ali", "Protein Alignments", "green_menu_divider" ],
        );

    $menu->add_dividers( \@divs );

    $menu->select_options( $ids );

    $menu->onchange( "javascript:handle_menu(this.form.ali_user_menu,'handle_ali_user_menu')" );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

1;

__END__

# sub row_collapse_down
# {
#     my ( $xhtml, $title, $text, $args );

#     $title = "Collapse Rows (on)";

#     $text = qq (Only rows containing data are currently shown. Press here)
#           . qq ( to reset the behavior so all rows are shown as they are in the original alignment.);

#     $args = qq (RIGHT,OFFSETX,-50,OFFSETY,20,WIDTH,250,CAPTION,'$title',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3,DELAY,$TT_delay);

#     $xhtml = qq (<table cellpadding="0" cellspacing="0"><tr><td>)
#            . qq (<a class="toggle_down" href="javascript:request('toggle_row_collapse')")
#            . qq ( onmouseover="return overlib('$text',$args);")
#            . qq ( onmouseout="return nd();">R</a>)
#            . qq (</td></tr></table>);

#     return $xhtml;
# }

# sub row_collapse_up
# {
#     my ( $xhtml, $title, $text, $args );

#     $title = "Collapse Rows (off)";

#     $text = qq (Removes gap-only rows from the display. This is useful for)
#           . qq ( skipping the stretches of gap-only rows that often occur in alignments.);

#     $args = qq (RIGHT,OFFSETX,-50,OFFSETY,20,WIDTH,250,CAPTION,'$title',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3,DELAY,$TT_delay);

#     $xhtml = qq (<table cellpadding="0" cellspacing="0"><tr><td>)
#            . qq (<a class="toggle_up" href="javascript:request('toggle_row_collapse')")
#            . qq ( onmouseover="return overlib('$text',$args);")
#            . qq ( onmouseout="return nd();">R</a>)
#            . qq (</td></tr></table>);

#     return $xhtml;
# }







How do I get the position of the mouse when an "onMouseOver" is activated?

May 15th, 2000 08:07
Mike Hall, Pete Ruby,


Both Netscape and IE provide an Event object that contains data for any 
given event. Netscape creates a new Event object for each event while IE 
has a single, global Event that can be referenced using 'window.event'.

Both browsers set the current mouse coordinates in the Event object, but 
naturally they use different property names. This example shows how you 
can retrieve those coordinates for either one.

<html>
<head>
<title></title>
<script language="JavaScript">

var isMinNS4 = (document.layers) ? 1 : 0;
var isMinIE4 = (document.all)    ? 1 : 0;

function myMouseOver(e) {

  var x, y;

  if (isMinNS4) {
    x = e.pageX;
    y = e.pageY;
  }
  if (isMinIE4) {
    x = window.event.x;
    y = window.event.y;
  }
  window.status = x + "," + y;
  return true;
}
</script>
</head>
<body>

<a href="myPage.html" 
   onmouseover="myMouseOver(event);">My Page</a>

</body>
</html>

Note that for NS, you need to pass 'event' explicity when setting the 
event handler in an HTML tag. This is not necessary in IE since there is 
only one, global Event object. Adding it won't cause an error in IE so 
this works nicely in either browser.
