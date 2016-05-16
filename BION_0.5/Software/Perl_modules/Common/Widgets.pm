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
                 &array_viewer_icon
                 &arrow_down
                 &arrow_right
                 &create_account_button
                 &delete_columns_button
                 &delete_selection_button
                 &differences_button
                 &download_seqs_button
                 &footer_bar
                 &form_page
                 &_form_row
                 &header_bar
                 &help_page
                 &help_title
                 &home_page
                 &job_icon
                 &login_button
                 &login_page
                 &login_panel
                 &menu_icon
                 &menu_icon_close
                 &message_box
                 &nav_bars
                 &nav_button
                 &nav_icon
                 &popup_bar
                 &pulldown_menu
                 &register_button
                 &register_page
                 &save_selection_button
                 &search_icon
                 &selections_icon
                 &show_page
                 &spacer
                 &summary_bar
                 &text_area
                 &text_field
                 &title_area
                 &title_box
                 &vxhtml_button
                 &window_icon
                 );

use Common::Config;
use Common::Messages;

use Common::Util;
use Common::States;

use base qw ( Common::Menus Common::Option );

# >>>>>>>>>>>>>>>>>>>>>>>> TOOLTIP SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Default colors, 

our $FG_color = "#ffffcc";
our $BG_color = "#666666";

# Default tooltip sizes,

our $TT_border = 3;
our $TT_textsize = "12px";
our $TT_captsize = "12px";
our $TT_delay = 400;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub array_viewer_icon
{
    # Niels Larsen, February 2007.

    # Returns an icon that brings up the array viewer when pressed.

    my ( $sid,                    # Session id
         $page,                   # 
         $fgcolor,
         $bgcolor,
         ) = @_;

    # Returns a string.
    
    my ( $xhtml, $img, $args );

    $fgcolor ||= $FG_color;
    $bgcolor ||= $BG_color;
    
    $img = qq (<img src="$Common::Config::img_url/array_viewer.gif" border="0" alt="Array viewer" />);

    $args = qq (LEFT,OFFSETX,-50,OFFSETY,20,CAPTION,'View Alignment',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

    $xhtml = qq (<a href="javascript:show_array_viewer('$page');")
           . qq ( onmouseover="return overlib('Displays a page where the alignment can be navigated.',$args);")
           . qq ( onmouseout="return nd();">$img</a>);
    
    return $xhtml;
}

sub arrow_down
{
    # Niels Larsen, September 2001

    # Small black down-arrow image.

    # Returns a string.

    return qq (<img src="$Common::Config::img_url/hier_down.gif" border="0" alt="Down arrow" />);
}

sub arrow_right
{
    # Niels Larsen, May 2003.

    # Small black right-arrow image. 

    # Returns a string.
 
    return qq (<img src="$Common::Config::img_url/hier_right.gif" border="0" alt="Right arrow" />);
}

sub create_account_button
{
    # Niels Larsen, March 2004.
    
    # Returns a "Create account" button which will invoke the registration
    # page. 

    my ( $sid,       # Session id
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml, $tip );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $tip = qq (Creates an account and then immediately takes you to the organism page.);

    $args = qq (LEFT,OFFSETX,-150,OFFSETY,20,WIDTH,150,CAPTION,'Create account',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (   <input type="button" class="summary_button" value="Create account and log me in")
            . qq (       onclick="javascript:create_account()")
            . qq (   onmouseover="return overlib('$tip',$args);")
            . qq (    onmouseout="return nd();" />);
    
    return $xhtml;
}

sub delete_columns_button
{
    # Niels Larsen, February 2004.

    # Returns a "Delete columns" button which will delete the selected
    # columns, if any. 

    my ( $sid,       # Session id
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#FFFFCC";

    $url = qq ($Common::Config::cgi_url/index.cgi?);
    $url .= ";session_id=$sid" if $sid;
    
    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Delete columns',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (   <input type="button" class="grey_button" value="Delete columns")
            . qq (       onclick="javascript:delete_columns()")
            . qq (   onmouseover="return overlib('Deletes all checked columns, if any.',$args);")
            . qq (    onmouseout="return nd();" />);
    
    return $xhtml;
}

sub delete_selection_button
{
    # Niels Larsen, February 2004.

    # Returns a "Delete selection" button which will delete the currently
    # visible selection and show the next one, if any.

    my ( $sid,       # Session id
         $index,     # Index among saved selections to delete
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml, $tip );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $url = qq ($Common::Config::cgi_url/index.cgi?);
    $url .= ";session_id=$sid" if $sid;
    
    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Delete selection',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $tip = "Deletes the currently visible hierarchy selection and shows the next one."
         . " If none are left, the default display is shown.";
    
    if ( not defined $index ) {
        &Common::Messages::error( qq (\$index not defined) );
    }

    $xhtml  = qq (   <input type="button" class="grey_button" value="Delete selection")
            . qq (       onclick="javascript:delete_selection('$index')")
            . qq (   onmouseover="return overlib('$tip',$args);")
            . qq (    onmouseout="return nd();" />);
    
    return $xhtml;
}

sub differences_button
{
    # Niels Larsen, February 2004.

    # Returns a "Compare columns" button which will display the tree
    # that exactly spans the nodes are not identical between the 
    # selected columns. 

    my ( $sid,       # Session id
         $type,      # Column type
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $url = qq ($Common::Config::cgi_url/index.cgi?);
    $url .= ";session_id=$sid" if $sid;
    
    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Compare columns',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (   <input type="button" class="grey_button" value="Compare columns")
            . qq (       onclick="javascript:column_differences('$type')")
            . qq (   onmouseover="return overlib('Displays a tree that shows the differences between the colums selected.',$args);")
            . qq (    onmouseout="return nd();" />);
    
    return $xhtml;
}

sub download_seqs_button
{
    # Niels Larsen, January 2005.

    # A button which will return SSU RNA sequences in fasta format
    # for the selected taxa, if any.

    my ( $sid,       # Session id
         $inputdb,  
         $title,
         $tiptext,
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#FFFFCC";

    $url = qq ($Common::Config::cgi_url/index.cgi?);
    $url .= ";session_id=$sid" if $sid;
    
    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Download Sequence',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (   <input type="button" class="grey_button" value="$title")
            . qq (       onclick="javascript:download_seqs('$inputdb')")
            . qq (   onmouseover="return overlib('$tiptext',$args);")
            . qq (    onmouseout="return nd();" />);
    
    return $xhtml;
}

sub footer_bar
{
    # Niels Larsen, September 2006.

    # Returns a table with run-time seconds the the left and "Made by 
    # Danish Genome Institute" to the right.

    my ( $class,
         $text,
         ) = @_;

    # Returns an XHTML string. 

    my ( $xhtml, $secs );

    $class = "footer_bar_blue" if not defined $class;

    if ( $Common::Config::Run_secs )
    {
        $secs = sprintf "%8.3f", $Common::Config::Run_secs;
        $secs .= " seconds";
    }
    else {
        $secs = "";
    }

    $text ||= qq (By <a href="http://genomics.dk" style="color:#ffffff;">genomics.dk</a> and pure web 1.0);
    
    $xhtml = qq (
<table class="$class" cellpadding="0" cellspacing="2" width="100%">
<tr>
    <td align="left">&nbsp;$secs&nbsp;</td>
    <td align="right">&nbsp;$text&nbsp;</td>
</tr>
</table>
);

    return $xhtml;
}

sub form_page
{
    # Niels Larsen, May 2007.

    # Generates a report page, given a structure of what should be shown. This 
    # structure is basically a menu with options, where each option may be a 
    # menu. Each option has these fields as a minimum,
    # 
    # title
    # value
    # 
    # but may also have 
    # 
    # name                   used if a form
    # description            tool tips
    # datatype               
    # selectable
    # visible
    # 
    # In addition the following arguments ... explain 
    #
    # Returns an XHTML string.

    my ( $menu,
         $args,
         ) = @_;

    # Returns a string.

    my ( $xhtml,  @texts, $text, $icon, $header_title, $viewer, $col_indent, $rowheight, 
         $hspace, $vspace, $tt_fgcolor, $tt_bgcolor, $tt_border, $tt_textsize, 
         $tt_captsize, $tt_delay, $tt_text, $tt_title, $tt_width, $url, $style_header,
         $script, $sid, $sect, $row, $form_name, $param_key, $type, $target, $uri_path,
         $name, $request, $value, $style, $button, $argstr, $hidden, $row_args,
         $sect_title, $sect_descr, $onclick, $hash, $style_descr, $def_args, $css );

    $args = &Registry::Args::check( $args, {
        "S:1" => [
            "form_name", "param_key", "param_values", "uri_path", "viewer",
            ],
        "S:0" => [
            "session_id", "url", "description", "citation", "header_icon", "header_title",
            "css_header", "css_body", "css_desc", "css_panel", "css_titles", "css_text",
            "css_keys", "style_input", "css_values", "css_buttons",
            "tt_fgcolor", "tt_bgcolor", "tt_border", "tt_textsize", "tt_captsize", "tt_delay",
        ],
        "AR:1" => "buttons",
        "AR:0" => "hidden",
    });

    # Merge defaults,

    $def_args = {
        "css_header" => "stdform_header",
        "css_body" => "stdform_body",
        "css_descr" => "stdform_descr",
        "css_panel" => "stdform_panel",
        "css_titles" => "stdform_title",
        "css_texts" => "stdform_text",
        "css_keys" => "stdform_key",
        "css_inputs" => "stdform_input",
        "css_values" => "stdform_value",
        "css_buttons" => "stdform_button",
        "tt_fgcolor" => "$FG_color",
        "tt_bgcolor" => "$BG_color",
        "tt_border" => $TT_border,
        "tt_textsize" => $TT_textsize,
        "tt_captsize" => $TT_captsize,
        "tt_delay" => $TT_delay,
    };

    $args = &Common::Util::merge_params( $args, $def_args );
    
    # Initialize,

    $xhtml = "";         # This string is built and returned

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HEADER BAR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $icon = $args->header_icon and $header_title = $args->header_title )
    {
        $text = qq (<table border="0" cellpadding="0" cellspacing="0">)
            . qq (<tr><td><img src="/Software/Images/$icon" alt="$icon" /></td>)
            . qq (<td>&nbsp;&nbsp;$header_title</td></tr>)
            . qq (</table>\n\n);

        $xhtml .= &Common::Widgets::popup_bar( $text );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> START FORM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $form_name = $args->form_name;
    $uri_path = $args->uri_path ."/index.cgi";
    $viewer = $args->viewer;
    
    $xhtml .= qq (
<form target="viewer" name="$form_name" action="/$uri_path" method="post">

<input type="hidden" name="form_name" value="$form_name" />
<input type="hidden" name="viewer" value="$viewer" />
);

    if ( $sid = $args->session_id ) {
        $xhtml .= qq (<input type="hidden" name="session_id" value="$sid" />\n);
    }

    $xhtml .= "\n";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> START BODY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $css = $args->css_body;
    $xhtml .= qq (\n<table border="0" cellpadding="0" cellspacing="0" class="$css">\n);

    # >>>>>>>>>>>>>>>>>>> DESCRIPTION / CITATION TEXT <<<<<<<<<<<<<<<<<<<<<<<

    # If page description or citation given, format a table with those 
    # elements, 

    if ( $text = $args->description )
    {
        $css = $args->css_descr;
        $xhtml .= qq (<tr><td colspan="2" class="$css">$text</td></tr>\n);
        
#         if ( $url = $args->url ) {
#             push @texts, qq (<tr><td colspan="2" class="$css"><a target="help" style="color:blue" href="$url">Read more.</a>\n);
#         }
    }
    
    if ( $text = $args->citation )
    {
        $css = $args->css_texts;
        $xhtml .= qq (<tr><td colspan="2" class="$css">Please cite: <cite>$text</cite></td></tr>\n);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE SECTIONS / ROWS <<<<<<<<<<<<<<<<<<<<<<<

    # Make a table of rows. The input structure is a menu of options, where 
    # an option may be a menu (but no more levels than that). Each option has
    # options set that decide how the xhtml is created.

    $hidden = [];
    
    foreach $sect ( @{ $menu->options } )
    {
        if ( ref $sect )
        {
            # Gets here if an option is a menu. This creates a separate section
            # with its own (optional) title.
            
            if ( $text = $sect->title )
            {
                $css = $args->css_titles;
                $xhtml .= qq (<tr><td colspan="2" class="$css">$text</td></tr>\n);
            }
            
            if ( $text = $sect->description )
            {
                $css = $args->css_texts;
                $xhtml .= qq (<tr><td colspan="2" class="$css">$text</td></tr>\n);
            }

            foreach $row ( $sect->options ) {
                $xhtml .= &Common::Widgets::_form_row( $row, $args, $hidden );
            }
        }
        else
        {
            # Gets here if an ordinary row,

            $xhtml .= &Common::Widgets::_form_row( $sect, $args, $hidden );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL BUTTONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Creates one or more buttons at the bottom of the form. We should keep 
    # the forms fairly small and the surrounding window on the large side,
    # because we dont know which fonts the client uses.

    if ( $args->buttons )
    {
        $css = $args->css_buttons;

        $xhtml .= qq (
<tr><td colspan="2" class="$css">
<table border="0" cellpadding="0" cellspacing="0">
<tr>);

        $tt_fgcolor =  $args->tt_fgcolor;
        $tt_bgcolor =  $args->tt_bgcolor;
        $tt_delay =  $args->tt_delay;
        $tt_textsize = $args->tt_textsize;
        $tt_captsize = $args->tt_captsize;
        
        foreach $button ( @{ $args->buttons } )
        {
            $button = &Registry::Args::check( $button,{
                "S:1" => [ qw ( description value type request style ) ],
                "S:0" => "onclick",
            });

            $tt_text = $button->description;
            $tt_text =~ s/\s+/ /g;
            $tt_title = $button->value;
            $tt_width = &Common::Util::max( ( length $tt_text ) * 2, 200 );

            $type = $button->type;
            $request = $button->request;
            $value = $button->value;
            $style = $button->style || "grey_button";

            if ( $onclick = $button->onclick ) {
                $onclick = qq ($onclick; return nd(););
            } else {
                $onclick = qq (return nd(););
            }

            $argstr = qq (RIGHT,OFFSETX,25,OFFSETY,-20,WIDTH,$tt_width,CAPTION,'$tt_title',)
                . qq (FGCOLOR,'$tt_fgcolor',BGCOLOR,'$tt_bgcolor',BORDER,3,DELAY,$tt_delay)
                . qq (,TEXTSIZE,'$tt_textsize',CAPTIONSIZE,'$tt_captsize');

            $xhtml .= qq (<td class="$css"><input type="$type" name="$request" value="$value" class="$style")
                . qq ( onmouseover="return overlib('$tt_text',$argstr);")
                . qq ( onmouseout="return nd();" onclick="$onclick" /></td>\n);
        }

        $xhtml .= qq (\n</tr>\n</table></td></tr>\n\n);
    }

    $xhtml .= "</table>\n";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HIDDEN FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Each input field has the same name, because we dont wish to have millions  
    # of different ones to check at the receiving end. But we would like to keep 
    # a list of keys, so it possible to make key/value assignments nevertheless.
    # The _form_row routine pushes onto a list of keys, which we write here and
    # send along under a name given in the arguments,

    if ( $args->hidden ) 
    {
        foreach $hash ( @{ $args->hidden } )
        {
            $xhtml .= qq (<input type="hidden" name="$hash->{'name'}" value="$hash->{'value'}" />\n);
        }            
    }

    if ( @{ $hidden } )
    {
        $param_key = $args->param_key;

        foreach $value ( @{ $hidden } )
        {
            $xhtml .= qq (<input type="hidden" name="$param_key" value="$value" />\n);
        }
    }


    $xhtml .= qq (\n</form>\n);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FOOTER BAR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#    $xhtml .= &Common::Widgets::footer_bar( "form_footer" );

    return $xhtml;
}

sub _form_row
{
    # Niels Larsen, May 2007.

    # Formats a single row in a report or form page. It will make a pulldown 
    # menu if the row structure contains choices, and fields of numbers or 
    # text otherwise; these will show as selectable if the "selectable" flag 
    # is set, otherwise just the value. Each row should be an object with 
    # these fields,
    # 

    my ( $row,         # Row structure
         $args,        # Arguments hash
         $hidden,      # Outgoing hidden field names
         ) = @_;

    # Returns a string.

    my ( $row_name, $row_value, $row_title, $maxlen, $text, $style, $tt_height,
         $tt_text, $tt_width, $tt_fgcolor, $tt_bgcolor, $tt_delay, $tt_textsize,
         $tt_captsize, $tt_args, $col_indent, $css_key, $css_input, $row_text,
         $css_value, $xhtml, $row_xhtml, $input, $size );

    bless $args, "Registry::Args";

    $row_name = $args->param_values;
    $row_value = $row->value;

    if ( not defined $row_value ) {
        &Common::Messages::error( qq (Row option without value -> "$row_name") );
    }

    $css_input = $args->css_inputs;
    $css_value = $args->css_values;

    # >>>>>>>>>>>>>>>>>>>>>>> FORMAT FIELD VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This section formats input elements (input fields, pulldown menus) and
    # plain text. 

    if ( $row->selectable )
    {
        # Gets here when input elements,
        
        if ( defined $row->datatype and $row->datatype =~ /^integer|real|text$/ )
        {
            if ( $row->width ) {
                $size = $row->width;
            } else {
                $size = 10;
            }
            
            if ( $row->maxlength ) {
                $maxlen = $row->maxlength;
            } else {
                $maxlen = $size;
            }
            
            $xhtml = qq (<input maxlength="$maxlen" class="$css_input" name="$row_name")
                   . qq ( value="$row_value" size="$size" />\n);

            $style = "";     # 
        }
        elsif ( $input = $row->choices )
        {
            $input->name( $row_name );
            $input->title( "" );
            $input->onchange( "javascript:handle_menu(this.form.$row_name)" );
            $input->selected( $row_value );

            $xhtml = &Common::Widgets::pulldown_menu( $input, {
                "mark_selected" => 0,
                "close_button" => 0,
                "value_key" => "name",
            });

            $style = "";
        }
        else {
            &Common::Messages::error( qq (No choice menu given) );
        }

        push @{ $hidden }, $row->name;
    }
    else
    {
        # Gets here when no input element, just text; but if a choice
        # structure is given anyway, then fish out the one selected 
        # and show that. This is good when choosing doesnt make sense
        # in the context. 

        if ( $input = $row->choices ) {
            $row_text = $input->match_option( "name" => $row_value )->title;
        } else {
            $row_text = $row_value;
        }
        
        if ( $row_text ) {
            $xhtml = qq (<table cellpadding="0" cellspacing="0" class="$css_value"><tr><td>$row_text</td></tr></table>);
        } else {
            $xhtml = "";
        }

        $style = ""; # $css_value;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT ROW <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $row_title = $row->title;
    $css_key = $args->css_keys;
    
    if ( $tt_text = $row->description )
    {
        # Gets here if caller wants tooltip,

        $tt_text =~ s/\s+/ /g;
        
        $tt_width = &Common::Util::tooltip_box_width( $row_title, $tt_text );

        $tt_fgcolor =  $args->tt_fgcolor;
        $tt_bgcolor =  $args->tt_bgcolor;
        $tt_delay =  $args->tt_delay;
        $tt_textsize = $args->tt_textsize;
        $tt_captsize = $args->tt_captsize;

        $tt_args = qq (RIGHT,OFFSETX,-50,OFFSETY,20,WIDTH,$tt_width,CAPTION,'$row_title',)
            . qq (FGCOLOR,'$tt_fgcolor',BGCOLOR,'$tt_bgcolor',BORDER,3,DELAY,'$tt_delay')
            . qq (,TEXTSIZE,'$tt_textsize',CAPTIONSIZE,'$tt_captsize');
        
        $row_xhtml .= qq (<tr>\n)
            . qq (<td width="1%" onmouseover="return overlib('$tt_text',$tt_args);")
            . qq ( onmouseout="return nd();" class="$css_key">$row_title</td>\n)
            . qq (<td class="$style">$xhtml</td>\n)
            . qq (</tr>\n);
    }
    else 
    {
        # Otherwise normal table row,

        $row_xhtml .= qq (<tr>\n)
            . qq (<td width="1%" class="$css_key">$row_title</td>\n)
            . qq (<td class="$style">$xhtml</td>\n)
            . qq (</tr>\n);
    }            
    
    return $row_xhtml;
}

sub header_bar
{
    # Niels Larsen, June 2003.

    # Produces a header bar with optional title (left), logo(s) (right) 
    # and style. 

    my ( $head,     # Header hash
         $user,     # User name
         ) = @_;

    # Returns a string. 

    my ( $title, $logo_image, $logo_text, $logo_link, $logo_elem, $title_elem, 
         $user_elem, $xhtml, $home_elem, $home_link, $args, $tip, $style_css );

    $title = $head->{"title"} || "";
    $style_css = $head->{"header_style"} || "header_bar_blue";
    $logo_image = $head->{"logo_image"} || "";
    $logo_text = $head->{"logo_text"} || "";
    $logo_link = $head->{"logo_link"} || "";
    $home_link = $head->{"home_link"} || "";

    # Title element,

    if ( $title ) {
        $title_elem = qq (&nbsp;$title&nbsp;);
    } else {
        $title_elem = qq (&nbsp;$Common::Config::sys_title&nbsp;);
    }

    # User element,

    if ( $user ) {
        $user_elem = qq (<table class="username"><tr><td>$user</td></tr></table>);
    } else {
        $user_elem = "";
    }

    # Logo element with image (and link maybe) or text,

    if ( $logo_image )
    {
        if ( $logo_image !~ m|/| ) {
            $logo_image = "$Common::Config::img_url/$logo_image";
        }

        $logo_elem = qq (<img src="$logo_image" height="60" border="0" alt="Logo" />);
        
        if ( $logo_link ) {
            $logo_elem = qq (<a href="$logo_link">$logo_elem</a>);
        }
    }
    elsif ( $logo_text )
    {
        $logo_elem = qq (&nbsp;$logo_text&nbsp;);
    }
    else {
        $logo_elem = "";
    }

    # Make bar with good padding,

    $xhtml = qq (
<table class="$style_css" cellpadding="5" cellspacing="2">
<tr>
);

    # Add home page link icon,

    if ( $home_link )
    {
        $home_elem = qq (<img src="$Common::Config::img_url/sys_home.png" border="0" alt="Homepage" />);
        
        $tip = qq (Click for home page and other projects. Anonymous sessions will be lost.);

        $args = qq (LEFT,OFFSETX,-60,OFFSETY,20,WIDTH,200,CAPTION,'Other projects')
              . qq (,FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3);

        $home_elem = qq (<a href="/" onmouseover="return overlib('$tip',$args);")
                   . qq (    onmouseout="return nd();">$home_elem</a>);

        $xhtml .= qq (   <td width="1%" align="right">$home_elem</td>\n);
    }

    $xhtml .= qq (
   <td width="99%" height="70" align="left">$title_elem</td>
   <td width="1%" align="right">$user_elem</td>
   <td width="1%" align="right">$logo_elem</td>
</tr>
</table>
);

    return $xhtml;
}

sub help_page
{
    # Niels Larsen, August 2003.

    # Renders a help page with title bar, close button and a body
    # with light yellow background. 

    my ( $body,      # XHTML for the body
         $title,     # Title text
         ) = @_;

    if ( not $title ) {
        $title = "$Common::Config::sys_name Help";
    }

    my ( $xhtml, $title_bar );

    $title_bar = &Common::Widgets::help_title( $title );

    $xhtml = qq (
<table cellspacing="0" cellpadding="0" width="100%">
<tr><td>$title_bar</td></tr>
<tr><td class="help_content">

$body

</td></tr>
</table>
);

    return $xhtml;
}

sub help_title
{
    # Niels Larsen, August 2003.

    # Creates a small bar with a close button. It is to be used
    # in a help window. 

    my ( $text,     # Title text
         ) = @_;

    my ( $xhtml, $close );

    $close = qq (<img src="$Common::Config::img_url/sys_cancel.gif" border="0" alt="Cancel button" />);

    $xhtml = qq (
<table cellpadding="0" cellspacing="0" width="100%"><tr>
     <td align="left" class="help_bar_text" width="98%">$text</td>
     <td align="right" class="help_bar_close" width="1%"><a href="javascript:window.close()">$close</a></td>
</tr></table>

);

    return $xhtml;
}

sub home_page
{
    # Niels Larsen, August 2008.

    # Creates a "home page" with a list of available projects and links to 
    # documentation.
    
    # Returns a string.

    my ( @table, $xhtml, $proj, $state, $page_xhtml, $row, 
         $key, $value, $projpath, $title, $args, $tip );

    require Common::Tables;

    $page_xhtml = qq (<table cellspacing="0" cellpadding="0">\n\n);
    $page_xhtml .= qq (<tr><td>\n  ). &Common::Widgets::spacer( 5 ) . qq (\n</td></tr>\n);

    $page_xhtml .= qq (
<tr><td>
<p>
Genome Office is the beginning of a web based framework that aims to provide 
better overview of large molecular biology data volumes. It is a freely available
(GNU license) prototype, currently sponsored by the 
<a href="http://www.rna.dk/jk"> Kjems Laboratory</a> at the 
<a href="http://www.mb.au.dk/en">Molecular Biology Department</a>, 
<a href="http://www.au.dk/en">Aarhus University</a>, 
<a href="http://en.wikipedia.org/wiki/Denmark">Denmark</a>. 
</p>
</td></tr>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PROJECTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $page_xhtml .= qq (
<tr><td>
<h3>Projects</h3>
<p>
Datasets and methods can be bundled into "projects". Below are listed all
projects and those installed are highlighted and clickable.
</p>
</td></tr>
);

    @table = ();

    $tip = qq (Click to see this project\\'s home page.);

    $args = qq (LEFT,HAUTO,VAUTO,WIDTH,150,CAPTION,'Go to pages')
          . qq (,FGCOLOR,'$FG_color',BGCOLOR,'#336699',BORDER,3);

    foreach $proj ( Registry::Get->projects->options )
    {
        $projpath = $proj->projpath;
        $title = $proj->description->title;

        if ( -d "$Common::Config::www_dir/$projpath" )
        {
            $key = qq (<a href="/$projpath" onmouseover="return overlib('$tip',$args);")
                 . qq (    onmouseout="return nd();" style="color: #ffffff">$projpath</a>);

            $key = &Common::Tables::xhtml_style( $key, "info_report_key" );
        }
        else {
            $key = &Common::Tables::xhtml_style( $projpath, "grey_report_key" );
        }
        
        $value = &Common::Tables::xhtml_style( $title, "info_report_value" );
        
        push @table, [ $key, $value ];
    }

    if ( @table ) {
        $xhtml = &Common::Tables::render_html( \@table );
    } else {
        $xhtml = "No projects installed";
    }
        
    $page_xhtml .= qq (
<tr><td>
  <table cellspacing="5">
     <tr><td>$xhtml</td></tr>
  </table>
</td></tr>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DOCUMENTATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $page_xhtml .= qq (
<tr><td>
<h3>Documentation (movies not done yet)</h3>
<p>
Below are short movies that describe different sides of the system. In 
addition, on the viewer pages there are tooltips on every button and help 
summaries in separate windows. There are also README files in many 
directories and comments in the code. But there is no manual. 
</p>
</td></tr>
);

    @table = (
        [ "Array Viewer", "Usage, with alignment example" ],
        [ "Hiearchy Viewer", "Usage, organism taxonomy example" ],
        [ "Analyses", "Shows upload, launch and analysis results" ],
        [ "Installation", "The installation process" ],
        [ "Code and files", "Organisation of directories, files and code" ],
        );

    foreach $row ( @table )
    {
        $row->[0] = &Common::Tables::xhtml_style( $row->[0], "info_report_key" );
        $row->[1] = &Common::Tables::xhtml_style( $row->[1], "info_report_value" );
    }

    $xhtml = &Common::Tables::render_html( \@table );

    $page_xhtml .= qq (
<tr><td>
  <table cellspacing="5">
     <tr><td>$xhtml</td></tr>
  </table>
</td></tr>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONTACT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $page_xhtml .= qq (
<tr><td>
<h3>Contact</h3>
</td></tr>
);
    $xhtml = &Common::Messages::format_contacts_for_browser( "info_report_key", "info_report_value" );

    $page_xhtml .= qq (
<tr><td>
  <table cellspacing="5">
     <tr><td>$xhtml</td></tr>
  </table>
</td></tr>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $page_xhtml .= qq (<tr><td>\n  ). &Common::Widgets::spacer( 10 ) . qq (\n</td></tr>\n);
    $page_xhtml .= qq (</table>\n);

    $state = {
        "with_menu_bar" => 0,
        "with_header_bar" => 0,
        "with_footer_bar" => 1,
        "with_home_link" => 0,
    };

    $proj = {
        "header" => {
            "title" => $Common::Config::sys_title,
        },
        "meta" => {
            "title" => $Common::Config::sys_name,
        }            
    };

    $page_xhtml = &Common::Widgets::show_page(
        {
            "body" => $page_xhtml,
            "sys_state" => $state,
            "project" => $proj,
        });

    if ( defined wantarray ) {
        return $page_xhtml;
    } else {
        print $page_xhtml;
    }

    return;
}
    
sub job_icon
{
    my ( $status,
         ) = @_;

    my ( $icon );

    if ( $status eq "pending" ) {
        $icon = "sys_pending.gif";
    } elsif ( $status eq "running" ) {
        $icon = "sys_running.gif";
    } elsif ( $status eq "aborted" ) {
        $icon = "sys_aborted.png";
    } elsif ( $status eq "completed" ) {
        $icon = "sys_completed.png";
    } else {
        &Common::Messages::error( qq (Wrong looking status -> "$status") );
    }

    return $icon;
}

sub login_button
{
    # Niels Larsen, March 2004.
    
    # Returns a "Login" button which will invoke the login page.

    my ( $sid,       # Session id
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml, $tip );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $url = qq ($Common::Config::cgi_url/index.cgi?with_menu_bar=1;menu_1=Login);
    $url .= ";session_id=$sid" if $sid;
    $url .= ";sys_request=login_page";

    $tip = qq (Displays the login page.);

    $args = qq (LEFT,OFFSETX,-60,OFFSETY,20,WIDTH,100,CAPTION,'Log in',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (   <a href="$url">)
            . qq (   <input type="button" class="summary_button" value="Log in")
            . qq (   onmouseover="return overlib('$tip',$args);")
            . qq (    onmouseout="return nd();" /></a>);
    
    return $xhtml;
}

sub login_page
{
    # Niels Larsen, May 2003
    
    # Creates xhtml for a login panel, with its own form. The 
    # widget contains a textbox with user name, below it a password
    # field and then a submit button. A list of error messages is 
    # displayed if given. 
    
    my ( $sid,          # Session id
         $messages,     # Message list - OPTIONAL
         $username,     # User name to appear - OPTIONAL
         $password,     # Password to appear - OPTIONAL
         ) = @_;

    # Returns a string. 

    $username ||= "";
    $password ||= "";

    my ( $xhtml, $error, $error_text, $login_panel, $browse_button,
         $register_button, $img );

    $register_button = &Common::Widgets::register_button( $sid );

    $img = qq (<img src="$Common::Config::img_url/sys_account.png" alt="Man" />);

    $xhtml = qq (
<div id="login_page">
<table><tr><td>
);

    $xhtml .= qq (
<h2>$img&nbsp;Log in</h2>

<table cellpadding="8">
<tr><td>If you have an account already: enter user name and password below
        and all pages should look as when the last session was ended. 
</td></tr>
);

    $login_panel = &Common::Widgets::login_panel( $username, $password, $messages );

    $xhtml .= qq (<tr><td>$login_panel</td></tr>\n);
    $xhtml .= qq (
<tr><td>
    If not, consider creating an account. Then selections, preferred
    views and uploads will be preserved between logins. If you give us your
    name, we will give you an account and keep your name invisible to all
    others. To create an account, press the "Create account" button below.
    To just browse without creating an account, click an item in the top
    menu bar.
</td></tr>
<tr><td>
    <table><tr><td>$register_button</td></tr></table>
</td></tr>
<tr><td>
<strong>Note:</strong> This machine is a prototype machine with purely public
data and it may not always work as we use it for building up things. So it is
too early to depend on this machine. You may show the site to your friends, 
but please do not yet post the site on the network or in mailing lists.
</td></tr></table>

</td></tr></table>
</div>
);

    return $xhtml;
}

sub login_panel
{
    # Niels Larsen, September 2003.

    # Creates a login page with input fields for user name and 
    # password. 

    my ( $username,         # User name
         $password,         # Password
         $messages,         # Message list - OPTIONAL
         $fgcolor,          # Foreground color of tooltip - OPTIONAL
         $bgcolor,          # Background color of tooltip - OPTIONAL
         ) = @_;

    # Returns an xhtml string.

    my ( $img_keys, $tip, $args, $xhtml );

    $username ||= "";
    $password ||= "";

    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $img_keys = qq (<img src="$Common::Config::img_url/sys_keys.gif" alt="Keys" />);

    $tip = qq (Logs in and restores your last session.);

    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Enter',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    if ( $messages and @{ $messages } )
    {
        $xhtml .= &Common::Widgets::message_box( $messages );
    }

    $xhtml .= qq (

<div id="login_panel">

<table cellpadding="0" cellspacing="0">
   <tr><td rowspan="2" width="70">$img_keys</td>
       <td class="grey_button_up">&nbsp;&nbsp;&nbsp;Username&nbsp;<big>&raquo;</big>&nbsp;</td>
       <td height="30"><input class="login_input" type="text" name="username" value="$username" size="12" maxlength="12" /></td>
   </tr>
   <tr><td class="grey_button_up">&nbsp;&nbsp;&nbsp;Password&nbsp;<big>&raquo;</big>&nbsp;</td>
       <td height="30"><input class="login_input" type="password" name="password" value="$password" size="12" maxlength="12" /></td>
   </tr>
   <tr><td></td><td></td><td height="30">&nbsp;
<input type="submit" name="sys_request" value="Enter" class="summary_button" style="width: 7em"
    onmouseover="return overlib('$tip',$args);" onmouseout="return nd();" />

</td></tr>
</table>

</div>
);

    return $xhtml;
}

sub menu_icon
{
    # Niels Larsen, May 2007.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server about what to do. This is a generic routine that different 
    # viewers should typically call with input arguments set as needed.

    my ( $args,    # Arguments hash
         ) = @_;

    # Returns a string. 

    my ( $name, $title, $tiptext, $icon, $tt_fgcolor, $tt_bgcolor, 
         $tt_textsize, $tt_captsize, $tt_delay, $tt_width, $img, $argstr,
         $xhtml );

    $name = $args->{"name"};
    $title = $args->{"title"} || "";
    $tiptext = $args->{"description"} || "";

    $icon = $args->{"icon"};
    
    $tt_fgcolor = $args->{"tt_fgcolor"} || "#ffffcc";
    $tt_bgcolor = $args->{"tt_bgcolor"} || "#666666";

    $tt_textsize = $args->{"tt_textsize"} || $TT_textsize;
    $tt_captsize = $args->{"tt_captsize"} || $TT_captsize;
    $tt_delay = $args->{"tt_delay"} || $TT_delay;

    $tt_width = $args->{"tt_width"} || 150;

    $img = qq (<img src="$Common::Config::img_url/$icon" border="0" alt="$title" />);

    $argstr = qq (RIGHT,OFFSETX,-50,OFFSETY,20,WIDTH,'$tt_width',CAPTION,'$title')
            . qq (,FGCOLOR,'$tt_fgcolor',BGCOLOR,'$tt_bgcolor',BORDER,3)
            . qq (,TEXTSIZE,'$tt_textsize',CAPTIONSIZE,'$tt_captsize',DELAY,'$tt_delay');

    $xhtml = qq (<a href="javascript:show_widget('$name')")
           . qq ( onmouseover="return overlib('$tiptext',$argstr);")
           . qq ( onmouseout="return nd();">$img</a>);
    
    return $xhtml;
}

sub menu_icon_close
{
    # Niels Larsen, October 2005.

    # Returns a javascript link that submits the page with a signal to the 
    # server that it should not show the statistics menu. 

    my ( $widget,         # Name of the widget to hide 
         ) = @_;

    # Returns a string.

    my ( $title, $tiptext, $fgcolor, $bgcolor, $name, $img, $xhtml, $args );

    $name = $widget->name;

    $title = "Cancel button";
    $tiptext = "Iconifies this menu.";

    $fgcolor = $widget->fgcolor;
    $bgcolor = $widget->bgcolor;

    $img = qq (<img src="$Common::Config::img_url/sys_cancel_half.gif" border="0" alt="Cancel button" />);
    $args = qq (RIGHT,CENTER,OFFSETY,20,CAPTION,'$title',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize',WIDTH,150);

    $xhtml = qq (<a href="javascript:hide_widget('$name')")
           . qq ( onmouseover="return overlib('$tiptext',$args);")
           . qq ( onmouseout="return nd();">$img</a>);

    return $xhtml;
}

sub message_box
{
    # Niels Larsen, January 2005.

    # Wraps a given list of messages into a table. Its look 
    # depends on the given CSS class name. 

    my ( $tuples,      # List of message tuples
         $class,       # Class name 
         ) = @_; 

    # Returns an XHTML string.

    $class ||= "error_message";
   
    my ( $xhtml, $tuple, $key );

    $xhtml = qq (<table cellspacing="8" cellpadding="0" class="$class">)
           . qq (<tr><td><table cellspacing="5" cellpadding="0">);

    foreach $tuple ( @{ $tuples } )
    {
        if ( $tuple->[0] =~ /error/i ) {
            $key = qq (<font color="#ff0000"><strong>$tuple->[0]</strong></font>);
        } elsif ( $tuple->[0] =~ /warning/i ) {
            $key = qq (<font color="#ff6600"><strong>$tuple->[0]</strong></font>);
        } elsif ( $tuple->[0] =~ /submitted|success|results|done/i or $tuple->[0] =~ /^ok$/i ) {
            $key = qq (<font color="#339933"><strong>$tuple->[0]</strong></font>);
        } elsif ( $tuple->[0] =~ /info|tip|advice|help/i ) {
            $key = qq (<font color="#3333CC"><strong>$tuple->[0]</strong></font>);
        } else {
            $key = qq (<font color="#666666"><strong>$tuple->[0]</strong></font>);
#            &Common::Messages::error( qq (Wrong looking key -> "$tuple->[0]") );
        }

        $xhtml .= qq (<tr>
   <td style="white-space: nowrap;">$key</td>
   <td>&nbsp;<strong>-&gt;</strong>&nbsp;</td>
   <td>$tuple->[1]</td>
</tr>
);
    }

    $xhtml .= qq (</table></td></tr></table>);

    return $xhtml;
}

sub nav_bars
{
    # Niels Larsen, June 2003.

    # Creates XHTML navigation bars without javascript or pulldown menus. Instead,
    # when an option is clicked, a submenu bar appears with options, positioned 
    # near the selected parent item. An optional icon, given by its image file
    # name, is shown at the right edge of the main bar.

    my ( $nav_menu,      # Menu structure
         $menu_1,        # Main menu name to show as selected - OPTIONAL
         $menu_2,        # Sub-menu name to show as selected - OPTIONAL
         $icon,          # Busy-icon to show - OPTIONAL 
         ) = @_;

    # Returns a string.

    my ( $xhtml, $menu, $i, $sub_menu, $menu_1_ndx, $base_link, $menu_1_title,
         $link, @link, $text, $sid, $options, $expr, $option, $fg_color_def,
         $bg_color_def, @options_1, $fg_color_clicked_def, $bg_color_clicked_def,
         $class, $style, $fg_color, $bg_color, $bl_color, 
         $bd_color, $class_down, $indent, $center_1, $width_2 );

    $base_link = "$Common::Config::cgi_url/index.cgi";
    $sid = $nav_menu->session_id;

    @options_1 = $nav_menu->options;

    $fg_color_clicked_def = "#ffffff";
    $bg_color_clicked_def = "#666666";

    $fg_color_def = "#ffffff";
    $bg_color_def = "#888888";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MAIN MENU BAR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This is a straight bar all across the page where the items are left-aligned.
    # There is a table inside another, so the text in menubars below can be 
    # independently justified, 

    $xhtml = qq (
<table class="nav_bars" cellspacing="0" cellpadding="0" border="0">
<tr><td align="left">
<table cellspacing="2" cellpadding="0" border="0">
<tr>
);

    for ( $i = 0; $i <= $#options_1; $i++ )
    {
        $option = $options_1[$i];

        $text = $option->label;
        $link = $base_link;

        @link = ();

        if ( &Common::Types::is_menu_option( $option ) )
        {
            push @link, "viewer=". $option->method if $option->method;
            push @link, "sys_request=". $option->sys_request if $option->sys_request;
            push @link, "request=". $option->request if $option->request;
        }

        push @link, "menu_1=". $option->name;
        push @link, "session_id=$sid";

        $link = "$base_link?". ( join ";", @link );

        if ( &Common::Types::is_menu( $option ) )
        {
            $fg_color = $option->fgcolor || $fg_color_clicked_def;
            $bg_color = $option->bgcolor || $bg_color_clicked_def;

            $style = qq (color:$fg_color; background-color:$bg_color);

            $xhtml .= qq (   <td class="nav_bars">)
                    . qq (<a class="nav_bars_clicked" style="$style" href="$link">$text</a></td>\n);

            $menu_1_ndx = $i;
            $sub_menu = $option;
        }
        else
        {
            if ( $menu_1 eq "login" and $option->name eq "login" )
            {
                $fg_color = $option->fgcolor || $fg_color_clicked_def;
                $bg_color = $option->bgcolor || $bg_color_clicked_def;

                $style = qq (color:$fg_color; background-color:$bg_color);

                $xhtml .= qq (   <td class="nav_bars">)
                        . qq (<a class="nav_bars_clicked" style="$style" href="$link">$text</a></td>\n);

            }elsif ( $option->is_active )
            {
                $xhtml .= qq (   <td class="nav_bars">)
                        . qq (<a class="nav_bars" href="$link">$text</a></td>\n);
            }
            else
            {
                $xhtml .= qq (   <td class="nav_bars">)
                        . qq (<a class="nav_bars" style="color: #888888;">$text</a></td>\n);
            }
        }
    }

    $xhtml .= qq (</tr>
</table>
</td>
);

    if ( $icon )
    {
        $xhtml .= qq (
<td align="right" valign="bottom"><img src="$Common::Config::img_url/$icon" />&nbsp;&nbsp;</td>
);
    }

    $xhtml .= qq (</tr>
</table>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SUB-MENU BAR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This is again a straight bar all across the page, but the items are aligned
    # so they center around the item in the main bar that is expanded,

    if ( $sub_menu and $sub_menu->options )
    {
        $options = $sub_menu->options;

        # Indent as best we can, counting characters in the menus,

        if ( $menu_1_ndx > 0 )
        {
            $center_1 = length join "   ", map { $_->label } $nav_menu->get_options( [ 0 .. $menu_1_ndx - 1 ] );
            $center_1 += length ( $nav_menu->get_option( $menu_1_ndx )->label ) / 2;

            $width_2 = length join "   ", map { $_->label } $sub_menu->get_options( [ 0 .. $sub_menu->options_count - 1 ] );

            if ( $center_1 > $width_2 / 2 ) {
                $indent = ( $center_1 - $width_2 / 2 ) * 0.66 + 1;  # the 2/3 compensates for cell spacing 
            } else {
                $indent = 0;
            }
        }
        else {
            $indent = 0;
        }

        $xhtml .= qq (
<table class="nav_bars" cellspacing="0" cellpadding="0" border="0">
<tr><td align="left">
<table cellspacing="2" cellpadding="0" border="0">
<tr>
);

        if ( $menu_1_ndx > 0 ) {
            $xhtml .= qq (<td style="width:$indent) . "em;" . qq (">&nbsp;</td>\n);
        }
        
        foreach $option ( $sub_menu->options )
        {
            $text = $option->label;
            $link = $base_link;

            @link = ();

            if ( &Common::Types::is_menu_option( $option ) )
            {
                push @link, "sys_request=". $option->sys_request if $option->sys_request;
                push @link, "request=". $option->request if $option->request;
            }
            
            push @link, "method=". $option->method if $option->method;
            push @link, "menu_2=". $option->name;
            push @link, "session_id=$sid";
            
            $link = "$base_link?". ( join ";", @link );

            if ( $option->name eq $menu_2 )
            {
                # Button pressed,

                $fg_color = $option->fgcolor || $fg_color_clicked_def;
                $bg_color = $option->bgcolor || $bg_color_clicked_def;
                $style = qq (color:$fg_color; background-color:$bg_color);

                $xhtml .= qq (   <td class="nav_bars_sub">)
                        . qq (<a class="nav_bars_clicked" style="$style" href="$link">$text</a></td>\n);
            }
            else
            {
                # Button not pressed,

                $fg_color = $option->fgcolor || $fg_color_def;
                $bg_color = $option->bgcolor || $bg_color_def;

                if ( $option->is_active )
                {
                    $style = qq (color:$fg_color; background-color:$bg_color);

                    $xhtml .= qq (   <td class="nav_bars">)
                        . qq (<a class="nav_bars" style="$style" href="$link">$text</a></td>\n);
                }
                else
                {
                    $xhtml .= qq (   <td class="nav_bars">)
                            . qq (<a class="nav_bars" style="color: #888888;">$text</a></td>\n);
                    }
            }
        }
        
        $xhtml .= qq (
</tr></table>
</td></tr>
</table>
);
    }

    return $xhtml;
}

sub nav_button
{
    # Niels Larsen, August 2005.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server about what it should do.

    my ( $args,
         ) = @_;

    # Returns a string. 

    my ( $class, $width, $fgcolor, $bgcolor, $request, $tiptext, 
         $argstr, $tiptitle, $xhtml, $label );

    $class = $args->{"class"};
    $label = $args->{"label"};

    if ( $args->{"nolink"} )
    {
        $xhtml = qq (<input type="button" class="$class" value="$label" />);
    }
    else
    {
        $fgcolor = $args->{"fgcolor"} || $FG_color;
        $bgcolor = $args->{"bgcolor"} || $BG_color;

        $request = $args->{"request"};
        
        $tiptitle = $args->{"tiptitle"};
        $tiptext = $args->{"tiptext"};
        
        $width = &Common::Util::max( ( length $tiptext ) * 2, 200 );
        
        $argstr = qq (RIGHT,OFFSETX,-50,OFFSETY,20,WIDTH,$width,CAPTION,'$tiptitle')
                . qq (,FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3,DELAY,$TT_delay)
                . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');
        
        $xhtml = qq (<a class="$class" href="javascript:request('$request')")
               . qq ( onmouseover="return overlib('$tiptext',$argstr);")
               . qq ( onmouseout="return nd();">$label</a>);
    }

    return $xhtml;
}

sub nav_icon
{
    # Niels Larsen, August 2005.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server about what it should do.

    my ( $args,
         ) = @_;

    # Returns a string. 

    my ( $img, $width, $fgcolor, $bgcolor, $request, $tiptext, $argstr, 
         $tiptitle, $xhtml );

    $img = qq (<img src="$args->{'icon'}" border="0" alt="" />);

    if ( $args->{"nolink"} )
    {
        $xhtml = $img;
    }
    else
    {
        $fgcolor = $args->{"fgcolor"} || $FG_color;
        $bgcolor = $args->{"bgcolor"} || $BG_color;

        $request = $args->{"request"};
        
        $tiptitle = $args->{"tiptitle"};
        $tiptext = $args->{"tiptext"};
        
        $width = &Common::Util::max( ( length $tiptext ) * 2.5, 130 );
        
        $argstr = qq (RIGHT,OFFSETX,-50,OFFSETY,20,WIDTH,$width,CAPTION,'$tiptitle')
                . qq (,FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3,DELAY,$TT_delay)
                . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

        $xhtml = qq (<a href="javascript:request('$request')")
               . qq ( onmouseover="return overlib('$tiptext',$argstr);")
               . qq ( onmouseout="return nd();">$img</a>);
    }
    
    return $xhtml;
}

sub popup_bar
{
    # Niels Larsen, August 2003.

    # Creates a small bar with a close button. 

    my ( $text,       # Title text
         $class_l,    # Class name for left part of bar
         $class_r,    # Class name for right part with close button
         ) = @_;

    # Returns a string of xhtml.

    my ( $xhtml, $close );

    $class_l ||= "stdform_bar_text";
    $class_r ||= "stdform_bar_close";

    $close = qq (<img src="$Common::Config::img_url/sys_cancel.gif" border="0" alt="Cancel button" />);

    $xhtml = qq (
<table cellpadding="0" cellspacing="0" width="100%" border="0"><tr>
     <td align="left" class="$class_l" width="98%">$text</td>
     <td align="right" class="$class_r" width="1%"><a href="javascript:window.close()">$close</a></td>
</tr></table>

);

    return $xhtml;
}

sub pulldown_menu
{
    # Niels Larsen, October 2005.

    # Creates xhtml from a given menu object. 

    my ( $menu,       # Menu object
         $args,       # Arguments hash
         ) = @_;

    # Returns XHTML as string or array.

    my ( $conf, $name, $css, $onchange, $selected, $xhtml, $text, $id, 
         $option, $title, $button_xhtml, $button, $mark_selected, $style,
         $value_key );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf = {
        "mark_selected" => 1,
        "close_button" => 1,
        "close_name" => "",
        "value_key" => "id",
    };

    if ( defined $args and ref $args eq "HASH" )
    {
        $conf = { %{ $conf }, %{ $args } };
    }
    
    $xhtml = "\n";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Open tag,

    $name = $menu->name;

    if ( $menu->css ) {
        $style = 'class="'. $menu->css .'"';
    } else {
        $style = 'class="beige_menu"';
    }

    $onchange = $menu->onchange;

    if ( $onchange ) {
#        $xhtml .= qq (<select name="$name" $style onmouseup="$onchange">\n);
        $xhtml .= qq (<select name="$name" $style onchange="$onchange">\n);
    } else {
        $xhtml .= qq (<select name="$name" $style>\n);
    }

    # First row as title if given,
    
    $title = $menu->title || "";

    if ( $title ) {
        $xhtml .= qq (   <option value="" label="">$title</option>\n);
    }

    # Row tags,

    $selected = $menu->selected;
    $mark_selected = $conf->{"mark_selected"};
    $value_key = $conf->{"value_key"};

    foreach $option ( @{ $menu->options } )
    {
        $id = $option->$value_key;
        $text = $option->title;

        if ( $mark_selected )
        {
            if ( $option->selected ) {
                $text = "&nbsp;*&nbsp;$text";
            } else {
                $text = "&nbsp;&nbsp;&nbsp;$text";
            }
        }
        
        $css = $option->css || "menu_item";

        if ( defined $selected and $id eq $selected ) {
            $xhtml .= qq (   <option value="$id" label="$text" class="$css" selected="selected">$text</option>\n);
        } else {
            $xhtml .= qq (   <option value="$id" label="$text" class="$css">$text</option>\n);
        }
    }

    # Close tag,

    $xhtml .= qq(</select>\n);

    # >>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL CLOSE BUTTON <<<<<<<<<<<<<<<<<<<<<

    if ( $conf->{"close_button"} )
    {
        $button = Common::Option->new();

        if ( $conf->{"close_name"} ) {
            $button->name( $conf->{"close_name"} );
        } else {
            $button->name( $name );
        }

        $button->fgcolor( $menu->fgcolor );
        $button->bgcolor( $menu->bgcolor );

        $button_xhtml = &Common::Widgets::menu_icon_close( $button );
        
        $xhtml = qq (
<table cellpadding="2" cellspacing="0"><tr>
     <td>$xhtml</td>
     <td valign="middle">$button_xhtml</td>
</tr></table>
);
    }
    
    return $xhtml;
}

sub register_button
{
    # Niels Larsen, March 2004.
    
    # Returns a "Register" button which will invoke the registration
    # page.

    my ( $sid,       # Session id
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml, $tip );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $tip = qq (Displays the registration page. If you just give us your name, we)
         . qq ( give you an account.);

    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Create account',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (<input type="submit" class="summary_button" value="Create account")
            . qq (   onmouseover="return overlib('$tip',$args);")
            . qq (    onmouseout="return nd();" />)
            . qq (<input type="hidden" name="sys_request" value="register_page">);
    
    return $xhtml;
}

sub register_page
{
    # Niels Larsen, March 2004.
    
    # Creates xhtml for a registration page, with its own form. The 
    # page contains a textbox with user name, below it a password
    # field and then a submit button. A list of error messages is 
    # displayed if given. 
    
    my ( $sid,            # Session id
         $info,           # Registration info
         $messages,       # Message texts - OPTIONAL
         ) = @_;

    # Returns a string. 

    my ( $xhtml, $error, $error_text, $account_button, $message,
         $register_button, $img, $first_name, $last_name, $user_name, $password );

    $first_name = $info->{"first_name"} || "";
    $last_name = $info->{"last_name"} || "";
    $user_name = $info->{"username"} || "";
    $password = $info->{"password"} || "";

    $account_button = &Common::Widgets::create_account_button();
    $img = qq (<img src="$Common::Config::img_url/sys_account.png" alt="Create Account" />);

    $xhtml = qq (<div id="login_page">\n);

    $xhtml .= qq (
<h2>$img&nbsp;Create an account</h2>

<p>
The procedure is simple: give us your first and last name, decide on
a user name and password, and press the button. 
</p>
<p>
&nbsp;
</p>
<table width="70%"><tr><td align="center">
<table cellpadding="0" cellspacing="0">
<tr>
    <td class="grey_button_up" align="right">&nbsp;&nbsp;&nbsp;First name&nbsp;<big>&raquo;</big>&nbsp;</td>
    <td><input class="login_input" type="text" name="first_name" value="$first_name" size="40" maxlength="40" /></td>
</tr>
<tr>
    <td class="grey_button_up" align="right">&nbsp;&nbsp;&nbsp;Last name&nbsp;<big>&raquo;</big>&nbsp;</td>
    <td><input class="login_input" type="text" name="last_name" value="$last_name" size="40" maxlength="40" /></td>
</tr>
<tr><td>&nbsp;</td><td></td></tr>
<tr>
    <td class="grey_button_up" align="right">&nbsp;&nbsp;&nbsp;User name&nbsp;<big>&raquo;</big>&nbsp;</td>
    <td><input class="login_input" type="text" name="username" value="$user_name" size="12" maxlength="12" /></td>
</tr>
<tr>
    <td class="grey_button_up" align="right">&nbsp;&nbsp;&nbsp;Password&nbsp;<big>&raquo;</big>&nbsp;</td>
    <td><input class="login_input" type="password" name="password" value="$password" size="12" maxlength="12" /></td>
</tr>
</table>
</td></tr></table>
<p>
&nbsp;
<input type="hidden" name="sys_request" value="" />
</p>
);

    if ( $messages and @{ $messages } ) 
    {
        $xhtml .= &Common::Widgets::message_box( $messages );
        $xhtml .= qq (<table><tr><td height="20">&nbsp;</td></tr></table>);
    }
 
    $xhtml .= qq (
<table>
<tr><td>$account_button</td></tr>
</table>
<p>
<strong>Note:</strong> This machine is a prototype machine with purely public
data and it may not always work as we use it for building up things. So it is
too early to depend on this machine. You may show the site to your friends, 
but please do not yet post the site on the network or in mailing lists.
</p>
</div>
);

    return $xhtml;
}

sub save_selection_button
{
    # Niels Larsen, February 2004.

    # Returns a "Save selection" button which will pop up a save window
    # when pressed. 

    my ( $sid,       # Session id
         $page,      # Page id
         $text,      # Text on the button
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml, $height, $width );

    $text ||= "Save selection";
    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $height ||= 350;
    $width ||= 500;
    
    $url = qq ($Common::Config::cgi_url/index.cgi?page=$page;request=save_selection_window);
    $url .= ";session_id=$sid" if $sid;
    
    $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Save row selections',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (   <input type="button" class="grey_button" value="$text")
            . qq (       onclick="javascript:open_window('popup','$url',$width,$height,1)")
            . qq (   onmouseover="return overlib('Displays a panel for annotating and saving row selections.',$args);")
            . qq (    onmouseout="return nd();" />\n);
    
    return $xhtml;
}

sub window_icon
{
    # Niels Larsen, August 2008.
    
    # Returns a button link that opens a new window that sends a url (GET request) 
    # which fills the window with content. The caller should set height, width, 
    # session id, background color and ... 

    my ( $args,
         ) = @_;

    my ( $viewer, $request, $sid, $title, $description, $icon, $height, $width, 
         $tt_fgcolor, $tt_bgcolor, $tt_border, $tt_textsize, $tt_captsize, $tt_delay,
         $tt_width, $argstr, $img, $url, $xhtml );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( viewer request sid title description icon ) ],
        "S:0" => [ qw ( height width tt_fgcolor tt_bgcolor tt_border tt_textsize tt_captsize tt_width ) ],
    });

    # Returns a string.

    $viewer = $args->viewer;
    $request = $args->request;
    $sid = $args->sid;
    $title = $args->title;
    $description = $args->description;
    $icon = $args->icon;

    $height = $args->height // 500;
    $width = $args->width // 400;
    $tt_fgcolor = $args->tt_fgcolor // $FG_color;
    $tt_bgcolor = $args->tt_bgcolor // $BG_color;
    $tt_border = $args->tt_border // $TT_border;
    $tt_textsize = $args->tt_textsize // $TT_textsize;
    $tt_captsize = $args->tt_captsize // $TT_captsize;
    $tt_width = $args->tt_width // 200;
    $tt_delay = 100;

    $img = qq (<img src="$Common::Config::img_url/$icon" border="0" alt="$title" />);

    $url = qq ($Common::Config::cgi_url/index.cgi?viewer=$viewer;session_id=$sid;request=$request);

    $argstr = qq (LEFT,OFFSETX,-50,OFFSETY,20,CAPTION,'$title',FGCOLOR,'$tt_fgcolor',BGCOLOR,'$tt_bgcolor',BORDER,3)
            . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize',DELAY,'$tt_delay',WIDTH,'$tt_width');

    $xhtml = qq (<a href="javascript:popup_window('$url',$width,$height);")
           . qq ( onmouseover="return overlib('$description',$argstr);")
           . qq ( onmouseout="return nd();">$img</a>);
    
    return $xhtml;
}

sub show_page
{
    # Niels Larsen, February 2003.

    # Accepts XHTML as a string and creates a page with headers and styles.
    # A main header bar is optionally put at the top of the page, then one 
    # or more navigation menu bars, then a page canvas and then a footer bar
    # at the bottom. These state flags have effect,
    # 
    # with_header_bar
    # with_menu_bar
    # with_footer_bar
    # 
    # TODO - explain more

    my ( $args,
         $msgs,
        ) = @_;

    # Returns a string. 

    my ( $viewer_xhtml, $sid, $state, $target, $nav_menu, $proj, $caller,
         $http_head, $page_head, $page_body, $xhtml, $title, $enctype, $script,
         $keywords, $onload, $job_icon, $job_status, $header, $css );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( body ) ],
            "HR:0" => [ qw ( sys_state ) ],
            "O:0" => [ qw ( project nav_menu ) ],
            "S:0" => [ qw ( head window_target ) ],
        });

    if ( not $state = $args->{"sys_state"} )
    {
        $state = &Common::States::default_states()->{"system"};
        $state->{"with_menu_bar"} = 0;
    }

    $proj = $args->{"project"};
    $viewer_xhtml = $args->{"body"};

    if ( defined $proj and $proj->{"projpath"} ) {
        $script = "/". $proj->{"projpath"} ."/index.cgi";
    } else {
        $script = "/index.cgi";
    }    

    $sid = $state->{"session_id"} // "";
    $page_body = "";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> HELP PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $state->{"is_help_page"} )
    {
        $target = $args->{"window_target"} || "viewer";

        $page_body .= qq (
<body class="help_body">
<form name="help" method="post" style="height: 100%" action="$script" target="$target">

<input type="hidden" name="session_id" value="$sid" />

$viewer_xhtml

</form>
</body>
);
    }
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> POPUP PAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # These are configuration panels, search windows etc,

    elsif ( $state->{"is_popup_page"} )
    {
        $page_body .= qq (
<body style="margin: 0px;">

$viewer_xhtml

</body>
);
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> MAIN PAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Content that appears in main browser window: ordinary pages and errors.

        if ( $state->{"page_refresh"} ) {
            $onload = qq ( onLoad="doLoad();");
        } else {
            $onload = "";
        }
    
        if ( $state->{"multipart_form"} ) {
            $enctype = qq (enctype="multipart/form-data");
        } else {
            $enctype = "";
        }

        $page_body .= qq ( 
<body$onload>

<div id="overDiv" style="position:absolute; visibility:hidden; z-index:1000;"></div>

<script type="text/javascript">
   window.name = "viewer";
</script>

<form name="viewer" $enctype method="post" action="$script">
<input type="hidden" name="session_id" value="$sid" />

<table cellpadding="0" cellspacing="0" width="100%" border="0">
);

        # --------- Main bar with bold title and logo wanted,

        if ( exists $state->{"with_header_bar"} )
        {
            if ( defined $proj ) 
            {
                $header = $proj->{"header"};
            }
            elsif ( $state->{"description"} ) 
            {
                $header = $state->{"header"};
            }
            else {
                $header = {
                    "title" => "System Error",
                    "logo_text" => $Common::Config::sys_name, 
                }
            }

            if ( $proj->{"home_link"} )
            {
                $header->{"home_link"} = "/";
            }

            $page_body .= qq (<tr><td>\n)
                . &Common::Widgets::header_bar( $header, $state->{"username"} )
                . qq (\n</td></tr>\n);
        }

        # --------- Menu bars wanted,

        if ( $state->{"with_menu_bar"} )
        {
            $nav_menu = $args->{"nav_menu"};

            if ( not $nav_menu )
            {
                if ( defined $proj and %{ $proj } ) {
                    $nav_menu = Common::Menus->navigation_menu( $proj->{"projpath"}, $state );
                } elsif ( exists $state->{"projpath"} ) {
                    $nav_menu = Common::Menus->navigation_menu( $state->{"projpath"}, $state );                    
                } else {
                    &Common::Messages::error( qq (No data directory given for menu bars) );
                }
            }

            $nav_menu->{"session_id"} = $sid;
            $job_status = &Common::States::restore_job_status( $sid );

            if ( $job_status ) {
                $job_icon = &Common::Widgets::job_icon( $job_status );
            }

            $page_body .= qq (<tr><td>\n)
                . &Common::Widgets::nav_bars( $nav_menu, $state->{"sys_menu_1"}, 
                                              $state->{"sys_menu_2"}, $job_icon )
                . qq (\n</td></tr>\n);
        }

        # --------- Content,

        $page_body .= qq (
<tr><td height="100%">
<div id="content">

$viewer_xhtml

</div>
</td>
</tr>
);
        # --------- Footer bar wanted,

        if ( $state->{"with_footer_bar"} )
        {
            $css = $header->{"footer_style"} if defined $header->{"footer_style"};

            $xhtml = &Common::Widgets::footer_bar( $css );
            $page_body .= qq (<tr><td height="1%">\n$xhtml\n</td></tr>\n);
            
            $xhtml = &Common::Widgets::vxhtml_button();
            $page_body .= qq (<tr><td height="1%">\n$xhtml\n</td></tr>\n);
        }

        $page_body .= qq (</table>\n</form>\n\n</body>);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GENERAL HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( exists $state->{"title"} ) {
        $title = $state->{"title"};
    } elsif ( defined $proj ) {
        $title = $proj->{"meta"}->{"title"};
    } else {
        $title = "System Error";
    }

    if ( defined $proj and $proj->{"description"}->{"keywords"} ) {
        $keywords = $proj->{"description"}->{"keywords"};
    } else {
        $keywords = "computer biology, bioinformatics, free software, GPL";
    }

    $page_head = &Common::Messages::html_header(
        {
            "title" => $title,
            "keywords" => $keywords,
            "insert" => $args->{"head"},
            "viewer" => $state->{"viewer"} // "common",
            "body_length" => length $page_body,
        });
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> RETURN OR PRINT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If in void content, print. Otherwise return entire page as a string,
    
    if ( defined wantarray )
    {
        return $page_head . $page_body . "</html>\n";
    }
    else
    {
        print $page_head;
        print $page_body;
        print "</html>\n";

        return;
    }
}

sub spacer
{
    # Niels Larsen, June 2008.

    # Returns an empty table of one row with the given pixel height. 
    # Used as spacers in XHTML formatting here and there. 

    my ( $px,
        ) = @_;

    # Returns a string.

    return qq (<table cellspacing="0" cellpadding="0"><tr><td height="$px">&nbsp;</td></tr></table>\n);
}

sub summary_bar
{
    # Bo Mikkelsen, Niels Larsen, August 2003.

    # Generates a colored bar from a list of [ color, width ] tuples. The 
    # color can be given either as "#cc6633" or a number, which is then 
    # used as an index in a given or default color ramp. The length and 
    # height of the bar can be given, but defaults to 30 and 20 pixels 
    # respectively. All numbers are scaled to fit the colors and width
    # given. The output is an xhtml table. 

    my ( $tuples,   # List of tuples [ color, width ]
         $length,   # Bar pixel length - OPTIONAL, default 30
         $height,   # Bar pixel height - OPTIONAL, default 20
         $ramp,     # Color ramp values - OPTIONAL
         $class,    # Style class - OPTIONAL
         ) = @_;

    # Returns html string which will draw the bar specified.

    my ( $min, $max, $sum, $index, $width_scale, $tuple, $width_off, $color,
         $width, $width_pix, $xhtml );

    # Defaults,

    $length = 30 if not $length;
    $height = 20 if not $height;
    
    if ( not $ramp ) {
        $ramp = &Common::Util::color_ramp( "#999999", "#dddddd", $length );
    }

    $sum = 0;
#    $min = $tuples->[0]->[0];
#    $max = $tuples->[0]->[0];

    foreach $tuple ( @{ $tuples } )
    {
#        if ( $tuple->[0] =~ /^\d+$/ ) 
#        {
#            $min = $tuple->[0] if $tuple->[0] < $min;
#            $max = $tuple->[0] if $tuple->[0] > $max;
#        }
        
        $sum += $tuple->[1];
    }

    $sum ||= $length;

    $width_scale = $length / $sum;

    if ( $class ) {
        $xhtml = qq (<table class="$class" cellpadding="0" cellspacing="0"><tr>);
    } else {
        $xhtml = qq (<table cellpadding="0" cellspacing="0"><tr>);
    }

    $width_off = 0;

    foreach $tuple ( @{ $tuples } )
    {
        if ( $tuple->[0] =~ /^\d+$/ )
        {
            $color = $ramp->[ $tuple->[0] ];
        }
        else {
            $color = $tuple->[0];
        }

        $width = $tuple->[1] * $width_scale + $width_off;
        $width_pix = int $width;
        $width_off = $width - $width_pix;

        $xhtml .= qq (<td bgcolor="$color" width="$width_pix" height="$height"></td>);
    }

    $xhtml .= qq (</tr></table>);

    return $xhtml;
}

sub text_area
{
    # Niels Larsen, October 2004.

    # Creates a text area with given name, rows and columns.

    my ( $name,    # Name
         $value,   # Value
         $rows,    # Number of rows
         $cols,    # Number of columns
         ) = @_;
    
    # Returns an XHTML string. 

    my ( $xhtml );

    $rows ||= 5;
    $cols ||= 70;

    $xhtml = qq (\n<textarea name="$name" value="$value" rows="$rows" cols="$cols"></textarea>);

    return $xhtml;
}

sub text_field
{
    # Niels Larsen, October 2004.

    # Prints an input text field. 

    my ( $name,    # Name
         $value,   # Value
         $size,    # Width 
         $maxl,    # Maximum number of characters
         ) = @_;
    
    # Returns an XHTML string. 

    my ( $xhtml );

    $value = "" if not defined $value;
    $size ||= 70;
    $maxl ||= 200;

    $xhtml = qq (\n<input type="text" name="$name" value="$value" size="$size" maxlength="$maxl" />);

    return $xhtml;
}

sub title_area
{
    # Niels Larsen, August 2003.

    # Creates a row of widgets to be placed as first line of the main pages.
    # The caller decides which widgets to include, but normally there should
    # be a title box as first element and a help button as the last element.

    my ( $l_widgets,       # Left-justified widgets
         $r_widgets,       # Right-justified widgets - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $widget, $xhtml );

    $xhtml = qq (<table border="0">\n<tr>\n);

    foreach $widget ( @{ $l_widgets } )
    {
        $xhtml .= qq (   <td width="1%" align="left">$widget</td>\n);
        $xhtml .= qq (   <td width="20">&nbsp;</td>\n);
    }

    $xhtml .= qq (   <td width="90%">&nbsp;</td>\n);

    foreach $widget ( @{ $r_widgets } )
    {
        $xhtml .= qq (   <td width="1%" align="left">$widget</td>\n);
        $xhtml .= qq (   <td width="20">&nbsp;</td>\n);
    }

    $xhtml .= qq (</tr>\n</table>\n);

    return $xhtml;
}

sub title_box
{
    # Niels Larsen, October 2006.

    # Prints a title box. If a title length maximum is given and 
    # exceeded, then the text is truncated and a tooltip is made 
    # with the full length text. 

    my ( $text,       # Title text
         $class,      # Title stylesheet class
         $maxlen,     # Max title length
         $fgcolor,    # Foreground color - OPTIONAL
         $bgcolor,    # Background color - OPTIONAL
         ) = @_;

    # Returns a string.

    my ( $xhtml, $elem, $substr, $args );

    $class ||= "title_box";
    $maxlen ||= 20;
    $bgcolor ||= "#666666";
    $fgcolor ||= "#ffffcc";

    if ( length $text > $maxlen + 5 )
    {
        $substr = ( substr $text, 0, $maxlen ) ." ...";

        $args = qq (RIGHT,OFFSETX,-50,OFFSETY,20,CAPTION,'Page Title',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3)
              . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize',DELAY,$TT_delay);

        $text = qq (<span onmouseover="return overlib('$text',$args);" onmouseout="return nd();">$substr</span>);

        $xhtml = qq (<table cellpadding="5"><tr><td class="$class">&nbsp;$text&nbsp;</td></tr></table>);
    }
    else {
        $xhtml = qq (<table cellpadding="5"><tr><td class="$class">&nbsp;$text&nbsp;</td></tr></table>);
    }

    return $xhtml;
}

sub vxhtml_button
{
    # Niels Larsen, February 2003.

    # Small button from W3C that when pressed submits the page its on
    # to validation. Back comes a report of what is incorrect according
    # to the DID used. 

    # Returns string.

    my $xhtml = qq (<div id="validation">\n<a href="http://validator.w3.org/check/referer">)
              . qq ( <img src="$Common::Config::img_url/vxhtml.gif" title="XHTML validation button" )
              . qq ( alt="XHTML validation button" border="0"/></a>\n</div>\n);

    return $xhtml;
}

1;

__END__

# sub window_icon
# {
#     # Niels Larsen, May 2007.
    
#     # Returns a link that activates a popup window. The content depends
#     # the viewer and request keys in the link.

#     my ( $args,
#          ) = @_;

#     # Returns a string.

#     my ( $viewer, $request, $sid, $win_height, $win_width, $icon, $title,
#          $tiptext, $tt_fgcolor, $tt_bgcolor, $tt_textsize, $tt_captsize, 
#          $tt_delay, $tt_width, $url, $argstr, $img, $xhtml );

#     $viewer = $args->{"viewer"};
#     $request = $args->{"request"};
#     $sid = $args->{"sid"};

#     $win_height = $args->{"win_height"} || 500;
#     $win_width = $args->{"win_width"} || 400;

#     $icon = $args->{"icon"};
#     $title = $args->{"title"} || "";
#     $tiptext = $args->{"description"} || "";
    
#     $tt_fgcolor = $args->{"tt_fgcolor"} || "#ffffcc";
#     $tt_bgcolor = $args->{"tt_bgcolor"} || "#666666";

#     $tt_textsize = $args->{"tt_textsize"} || $TT_textsize;
#     $tt_captsize = $args->{"tt_captsize"} || $TT_captsize;
#     $tt_delay = $args->{"tt_delay"} || $TT_delay;

#     $tt_width = $args->{"tt_width"} || 150;
    
#     $url = qq ($Common::Config::cgi_url/index.cgi?viewer=$viewer;request=$request);
#     $url .= ";session_id=$sid";

#     $argstr = qq (RIGHT,OFFSETX,-50,OFFSETY,20,WIDTH,'$tt_width',CAPTION,'$title')
#             . qq (,FGCOLOR,'$tt_fgcolor',BGCOLOR,'$tt_bgcolor',BORDER,3)
#             . qq (,TEXTSIZE,'$tt_textsize',CAPTIONSIZE,'$tt_captsize',DELAY,'$tt_delay');

#     $img = qq (<img src="$Common::Config::img_url/$icon" border="0" alt="$title" />);

#     $xhtml = qq (<a href="javascript:open_window('popup','$url',$win_width,$win_height);")
#            . qq ( onmouseover="return overlib('$tiptext',$argstr);")
#            . qq ( onmouseout="return nd();">$img</a>);
    
#     return $xhtml;
# }

# sub selections_icon
# {
#     # Niels Larsen, August 2003.
    
#     # Returns a javascript link that submits the page with a signal to the 
#     # server it should show the selections menu. 

#     my ( $icon,         # Icon for widget
#          $key,          # Name of widget 
#          $title,        # Tooltip title
#          $text,         # Tooltip text
#          $fgcolor,      # Foreground color - OPTIONAL, default '#FFFFCC'
#          $bgcolor,      # Background color - OPTIONAL, default '#003366'
#          ) = @_;

#     # Returns a string. 

#     $fgcolor ||= "#ffffcc";
#     $bgcolor ||= "#003366";

#     my ( $xhtml, $img, $args );

#     $img = qq (<img src="$icon" border="0" alt="Statistics menu" />);

#     $args = qq (RIGHT,OFFSETX,-70,OFFSETY,20,WIDTH,180,CAPTION,'$title',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3)
#           . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

#     $xhtml = qq (<a href="javascript:show_widget('$key')")
#            . qq ( onmouseover="return overlib('$text',$args);")
#            . qq ( onmouseout="return nd();">$img</a>);
    
#     return $xhtml;
# }

# sub pulldown_menu_js
# {
#     # Niels Larsen, November 2005.

#     # Creates xhtml from a given menu object. 

#     my ( $menu,     # Menu object
#          $class,    
#          ) = @_;

#     # Returns a string.

#     $class ||= "menu";

#     my ( $option, $title, $href, $menu_id, $class_bar, $class_button, $class_item,
#          $xhtml, $xhtml_sub );

#     $class_bar = $class . "Bar";

#     $xhtml = qq (<!-- Menu titles visible on the menu bar -->\n\n<div class="$class_bar">\n);

#     # Menu head,

#     $title = $menu->title || "";
#     $href = $menu->href || "";
        
#     $class_button = $class . "Button";
#     $menu_id = $class ."Menu";
        
#     $xhtml .= qq (   <a class="$class_button" href="$href") 
#             . qq ( onclick="return buttonClick(event,'$menu_id');")
#             . qq ( onmouseover="buttonMouseover(event,'$menu_id');">$title</a>\n);

#     # Generate the pulldown of its options,

#     $xhtml_sub = qq (<div id="$menu_id" class="$class" onmouseover="menuMouseover(event)">\n);

#     foreach $option ( $menu->options )
#     {
#         $title = $option->title;
#         $href = $option->href;

#         if ( not $title ) {
#             &Common::Messages::error( qq (Menu option no title found) );
#         }
                
#         $class_item = $class . "Item";
        
#         $xhtml_sub .= qq (   <a class="$class_item" href="$href">$title</a>\n);
#     }

#     $xhtml_sub .= qq (</div>\n\n);

#     $xhtml .= qq (</div>\n\n);

#     $xhtml .= $xhtml_sub;

#     return $xhtml;
# }

# sub upgrade_page
# {
#     # Niels Larsen, 2003.
    
#     # Prints a page that tells the user to upgrade their browser.

#     my ( $info,
#          ) = @_;

#     if ( not $info )
#     {
#         $info = &Common::Users::get_client_info();
#     }

#     my ( $xhtml, $str, $os, $browser, $idstr );

#     $os = $info->{"os_name"};
#     $browser = $info->{"name"};
#     $browser .= ", version ". $info->{"version"} if $info->{"version"};
#     $browser .= ".". $info->{"minor_version"} if $info->{"minor_version"};
#     $idstr = $info->{"user_agent"};

#     $xhtml = &Common::Messages::http_header();
#     $xhtml .= qq (
# <table cellpadding="2" width="100%"><tr><td>

# <table cellpadding="0" border="2" cellspacing="0" width="100%"><tr><td>
# <table cellpadding="10" border="0" bgcolor="666666" cellspacing="0" width="100%">
# <tr>
#    <td align="left"><strong><font size="+2" color="#ffffff">Outdated Browser</font></strong></td>
#    <td align="right"><strong><font size="+2" color="#ffffff">Problem</font></strong></td>
# </tr>
# </table>
# </td></tr></table>

# </td></tr>
# <tr><td>
# <table cellspacing="0" cellpadding="10"><tr><td>

# <h2>The Reason for This Message</h2>
# <p>
# Our server detected your operating system and browser as
# </p>
# <p>
# <ul>
# <li>$os</li>
# <li>$browser</li>
# </ul>
# </p>
# Unfortunately this browser is not capable of displaying our pages.
# We do follow web standards and avoid proprietary extensions, but 
# browsers older than 2-3 years simply cannot display the more modern
# standards. 
# </p>
# <p>
# The solution is to try upgrade the browser. 
# </p>
# </td></tr>
# <tr><td>

#     if ( defined wantarray ) {
#         return $xhtml;
#     } else {
#         print $xhtml;
#     }
# }

# sub gold_title
# {
#     # Niels Larsen, August 2003.
    
#     # Creates a small bar with a close button. It is to be used
#     # in a GOLD report window. 

#     my ( $text,     # Title text
#          ) = @_;

#     # Returns an xhtml string. 

#     my ( $xhtml, $close );

#     $close = qq (<img src="$Common::Config::img_url/sys_cancel.gif" border="0" alt="Cancel button" />);

#     $xhtml = qq (
# <table cellpadding="4" cellspacing="0" width="100%"><tr>
#      <td align="left" class="gold_bar_text" width="98%">$text</td>
#      <td align="right" class="gold_bar_close" width="1%"><a href="javascript:window.close()">$close</a></td>
# </tr></table>

# );

#     return $xhtml;
# }

# sub xxxxxxxxxxxxxx
# {
#     # Niels Larsen, February 2003

#     # Accepts a list of menu structures and returns xhtml with div tags 
#     # and links that define the pulldown menus of the menu bar. Each menu
#     # structure is a list of [ text, url ] elements. The url can be a 
#     # reference to a menu structure itself, a sub-menu will be made then. 
#     # If text is some sequence of '-' or '=' then a divider is shown. If 
#     # url is the empty string, then the menu item will be in bold-face. 

#     my ( $menus,    # Input list of lists
#          $class,    # Class name - OPTIONAL
#          ) = @_;

#     # Returns a string.

#     $class ||= "menu";

#     my ( $menu, $text, $link, $i, $j, $menu_id, $sub_menu_id,
#          $class_bar, $class_menu, $class_button, $class_item, $class_text, 
#          $class_hdr, $class_sep, $class_arrow, $sub_menu, $items, $item,
#          $sub_item, @xhtml, @xhtml_menus, @xhtml_sub_menus );

#     $class_bar = $class . "Bar";

#     @xhtml = qq (<!-- Menu titles visible on the menu bar -->\n\n<div class="$class_bar">\n);

#     # For each menu title on the menu bar do,

#     foreach $menu ( @{ $menus } )
#     {
#         $text = $menu->{"name"} || "";
#         $link = $menu->{"link"} || "";
        
#         $class_button = $class . "Button";
#         $menu_id = $text . "Menu";
        
#         push @xhtml, qq (   <a class="$class_button" href="$link") 
#                    . qq ( onclick="return buttonClick(event, '$menu_id');")
#                    . qq ( onmouseover="buttonMouseover(event, '$menu_id');">$text</a>\n);

#         # If its a real menu with items (normal case),

#         if ( $menu->{"items"} )
#         {
#             push @xhtml_menus, qq (<div id="$menu_id" class="$class" onmouseover="menuMouseover(event)">\n);

#             # Then loop through these,

#             for ( $i = 1; $i < @{ $menu->{"items"} }; $i++ )
#             {
#                 $item = $menu->{"items"}->[ $i ];

#                 $text = $item->{"name"};
#                 $link = $item->{"link"};
                
#                 $class_item = $class . "Item";
#                 $class_text = $class . "ItemText";
#                 $class_hdr = $class . "ItemHdr";
#                 $class_sep = $class . "ItemSep";
#                 $class_arrow = $class . "ItemArrow";
                
#                 if ( not $text ) {
#                     &Common::Messages::error( qq (Menu option without text found) );
#                 }

#                 # Make divider,
                
#                 if ( $text =~ /^[-= ]+$/ )
#                 {
#                     push @xhtml_menus, qq (   <div class="$class_sep"></div>\n);
#                 }
#                 elsif ( $item->{"items"} )
#                 {
#                     # If there are submenus attached,
                    
#                     if ( $item->{"items"} )
#                     {
#                         $sub_menu_id = $text . "SubMenu";
#                         $sub_menu = $item->{"items"};
                        
#                         push @xhtml_menus, qq (   <a class="$class_item" href="" onclick="return false;")
#                             . qq ( onmouseover="menuItemMouseover(event, '$sub_menu_id');">)
#                             . qq ( <span class="$class_text">$text</span><span class="$class_arrow">&\#9654;</span></a>\n);
                        
#                         push @xhtml_sub_menus, qq (<div id="$sub_menu_id" class="$class" onmouseover="menuMouseover(event)">\n);
                        
#                         if ( scalar @{ $sub_menu } > 0 )
#                         {
#                             for ( $j = 0; $j < @{ $sub_menu }; $j++ )
#                             {
#                                 $sub_item = $sub_menu->[ $j ];
                                
#                                 $text = $sub_item->{"name"};
#                                 $link = $sub_item->{"link"};
                                
#                                 next if not $link;
#                                 push @xhtml_sub_menus, qq (   <a class="$class_item" href="$link">$text</a>\n);
#                             }
                        
#                             push @xhtml_sub_menus, qq (</div>\n\n);
#                         }
#                     }
#                     else {
#                         push @xhtml_menus, qq (   <a class="$class_item" href="$link">$text</a>\n);
#                     }
#                 }
#                 else {
#                     push @xhtml_menus, qq (   <a class="$class_item" href="$link">$text</a>\n);
#                 }
#             }
            
#             push @xhtml_menus, qq (</div>\n\n);
#         }
#     }
 
#     push @xhtml, qq (</div>\n\n);

#     if ( @xhtml_menus )
#     {
#         push @xhtml, qq (<!-- Menu items for each menu -->\n\n);
#         push @xhtml, @xhtml_menus;
#     }

#     if ( @xhtml_sub_menus )
#     {
#         push @xhtml, qq (<!-- Second-level menu items -->\n\n);
#         push @xhtml, @xhtml_sub_menus;
#     }

#     return join "", @xhtml;
# }




# sub select_panel
# {
#     # Far from final form 

#     my ( $list,
#           $class,
#           ) = @_;

#     $class ||= "select_panel";
    
#     my ( @xhtml, $text, $url, $elem, $link, $class_elem );

#     push @xhtml, qq (<table>);

#     foreach $elem ( @{ $list } )
#     {
#          ( $text, $url, $class_elem ) = @{ $elem };

#         $class_elem = $class if not $class_elem;

#          if ( $url )
#         {
#             $link = qq (<a href="$url" class="$class_elem">$text</a>);
#             push @xhtml, qq (<tr><td class="$class_elem">$link</td></tr>);
#         }
#         else
#         {
#             push @xhtml, qq (<tr><td class="$class_elem">$text</td></tr>);
#         }
#     }

#     push @xhtml, qq (</table>);

#     return join "\n", @xhtml;
# }                           

# sub select_menu
# {
#     # Niels Larsen, January 2005.

#     my ( $name,       # Name of menu, for the <select> tag
#          $items,      # List of menu item hashes
#          $selected,   # Text of menu option to be selected - OPTIONAL
#          $class,      # Style for menu as a whole - OPTIONAL
#          $action,     # Javascript function - OPTIONAL
#          ) = @_;

#     # Returns XHTML as string or array.

#     $selected ||= "";
#     $class ||= "grey_menu";

#     my ( $xhtml, $item, $text, $id );

#     if ( $class ) 
#     {
#         if ( $action ) {
#             $xhtml = qq (<select name="$name" class="$class" onchange="$action">\n);
#         } else {
#             $xhtml = qq (<select name="$name" class="$class">\n);
#         }
#     }
#     else
#     {
#         if ( $action ) {
#             $xhtml = qq (<select name="$name" onchange="$action">\n);
#         } else {
#             $xhtml = qq (<select name="$name">\n);
#         }
#     }

#     foreach $item ( @{ $items } )
#     {
#         $id = $item->{"id"};
#         $text = $item->{"text"};
#         $class = $item->{"class"} || "menu_item";

#         if ( not defined $id ) {
#             &Common::Messages::error( qq (\$id is not defined) );
#         }

#         if ( $id eq $selected ) {
#             $xhtml .= qq (   <option value="$id" label="$text" class="$class" selected="selected">$text</option>\n);
#         } else {
#             $xhtml .= qq (   <option value="$id" label="$text" class="$class">$text</option>\n);
#         }
#     }

#     $xhtml .= qq(</select>\n);

#     return $xhtml;
# }

# sub slide_forward_icon
# {
#     # Niels Larsen, March 2004.
    
#     # Returns a blue forward arrow with a tooltip. When pressed
#     # a slide show should start. 
    
#     my ( $sid,       # Session id
#          $fgcolor,   # Foreground tooltip color - OPTIONAL
#          $bgcolor,   # Background tooltip color - OPTIONAL
#          ) = @_;

#     # Returns an xhtml string. 

#     my ( $url, $args, $xhtml, $tip );

#     $bgcolor ||= "#003366";
#     $fgcolor ||= "#ffffcc";

#     $url = qq ($Common::Config::cgi_url/index.cgi?);
#     $url .= ";session_id=$sid" if $sid;
#     $url .= ";sys_request=slide_show";

#     $tip = qq (Starts a series of pages that show what the system can do.);
    
#     $args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'Slide show',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3)
#           . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

#     $xhtml  = qq (   <a href="$url"><img src="$Common::Config::img_url/sys_forward.png" border="0")
#             . qq (   onmouseover="return overlib('$tip',$args);")
#             . qq (    onmouseout="return nd();" alt="Slide button" /></a>);
    
#     return $xhtml;
# }

# sub error_box
# {
#     # Niels Larsen, January 2005.

#     # Wraps a given list of error messages into a table. Its look 
#     # depends on the given CSS class name, but by default it is a 
#     # "sunken" area with beige background.

#     my ( $errors,     # List of messages
#          $class,      # Class name - OPTIONAL
#          ) = @_; 

#     # Returns an XHTML string.

#     my ( $xhtml, $error, @messages );

#     $class ||= "error_message";

#     foreach $error ( @{ $errors } )
#     {
#         push @messages, [ qq (<font color="red"><strong>Error</strong></font>), $error ];
#     }

#     $xhtml = &Common::Widgets::message_box( \@messages, $class );

#     return $xhtml;
# }

# sub show_items_selected
# {
#     # Niels Larsen, January 2005.

#     # As a primitive way to show an item as highlighted, this routine
#     # preprends an asterisk to a given item. The items to be "highlighted"
#     # are given by a list of their ids. 

#     my ( $items,   # Items list
#          $ids,     # Ids to highlight
#          ) = @_;

#     # Returns an updated items list.

#     my ( $item, %show );

#     if ( defined $ids and @{ $ids } )
#     {
#         %show = map { $_, 1 } @{ $ids };
        
#         foreach $item ( @{ $items } )
#         {
#             if ( $show{ $item->{"id"} } ) {
#                 $item->{"text"} = qq (&nbsp;*&nbsp;$item->{"text"});
#             } else { # if ( $item->{"key"} ) {
#                 $item->{"text"} = qq (&nbsp;&nbsp;&nbsp;$item->{"text"});
#             }
#         }
#     }

#     return wantarray ? @{ $items } : $items;
# }


    # ------- Check input unless error page,

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> BROWSER CHECK <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $browser_info = &Common::Users::get_client_info();

#     if ( not &Common::Users::browser_is_css_capable( $browser_info ) )
#     {
#         &Common::Widgets::upgrade_page( $browser_info );
#     }
