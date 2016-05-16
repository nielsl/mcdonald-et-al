package Taxonomy::Widgets;     #  -*- perl -*-

# Taxonomy related widgets that produce strings of xhtml. They typically
# define strings, styles and images and then invoke the generic equivalent.
# They do not reach into database. It is okay to use arguments that are 
# complex data structures (like state hash), whereas in Common::Widgets 
# the arguments should be simple. 

use strict;
use warnings FATAL => qw ( all );

use POSIX;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &action_buttons
                 &checkbox_cell
                 &checkbox_row
                 &col_headers
                 &control_icon
                 &control_menu
                 &data_icon
                 &data_menu
                 &display_col_row
                 &display_data_rows
                 &display_node_row
                 &display_rows
                 &format_display_name
                 &format_page
                 &help_icon
                 &id_cell
                 &menu_row
                 &orgs_taxa_report
                 &parents_menu
                 &rna_seq_report
                 &save_taxa_window
                 &search_window
                 &sims_cell
                 &stats_cell
                 &user_menu
                 &user_icon
                 );

use Common::Config;
use Common::Messages;

use Taxonomy::Menus;
use Taxonomy::Nodes;
use Taxonomy::Display;

use Common::Widgets;
use Common::Names;
use Common::Util;
use Common::DB;
use Common::Menus;

# >>>>>>>>>>>>>>>>>>>>>>>> WIDGET SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Viewer_name = "orgs_viewer";
our $Proj_site_dir;

# Default colors, 

our $FG_color = "#ffffcc";
our $BG_color = "#336699";

# Default tooltip settings,

our $TT_border = 3;
our $TT_textsize = "12px";
our $TT_captsize = "12px";
our $TT_delay = 300;   # milliseconds before tooltips show

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub action_buttons
{
    # Niels Larsen, February 2004.

    # Prints a row of buttons, save selection and delete selection so 
    # far. It also prints a text string that indicates if the action
    # completed successfully.

    my ( $sid,        # Session id
         $state,      # State hash
         $display,    # Display structure
         ) = @_;

    # Returns an xhtml string.

    my ( @cols, $xhtml, $index, $flag, $fgcolor, $bgcolor, $columns, $buttons, 
         $menu, $option, $title, $tiptext );

    $fgcolor = $FG_color;
    $bgcolor = $BG_color;

    $columns = $display->columns;
    $buttons = $display->column_buttons;
    
    $xhtml = qq (<table cellpadding="0" cellspacing="0" height="50"><tr>);

    # Save taxa button,

    if ( @{ $columns->match_options( "datatype" => "save_orgs_taxa" ) } )
    {
        $xhtml .= qq (<td valign="middle">)
               . &Common::Widgets::save_selection_button( $sid, "taxonomy", "Save taxa", $fgcolor, $bgcolor )
               . "</td>";

        $flag = 1;
    }

    # Delete columns button, 

    if ( @{ $buttons->match_options( "datatype" => "delete_column" ) } )
    {
        $xhtml .= qq (<td valign="middle">)
               . &Common::Widgets::delete_columns_button( $sid, $fgcolor, $bgcolor )
               . "</td>";

        $flag = 1;
    }

    # Download sequence button,

    if ( @{ $columns->match_options( "datatype" => "download_seqs" ) } )
    {
        $menu = Common::Menus->searchdbs_menu();
        $option = $menu->match_option( "name" => $state->{"tax_inputdb"} );

        $title = "Download ". $option->title;
        $tiptext = "To download (". $option->tiptext ."), select taxa and press this button";

        $xhtml .= qq (<td valign="middle">)
               . &Common::Widgets::download_seqs_button( $sid, $option->name, $title, $tiptext,
                                                         $fgcolor, $bgcolor )
               . "</td>";

        $flag = 1;
    }

    $xhtml .= qq (</tr></table>);

    if ( not $flag ) 
    {
        $xhtml = qq (<table><tr><td height="10">&nbsp;</td></tr></table>\n);
    }

    return $xhtml;
}

sub checkbox_cell
{
    # Niels Larsen, March 2004.

    # Displays a checkbox element.

    my ( $cell,         # Column cell structure
         $id,            # Node id
         $valndx,
         ) = @_;

    # Returns an xhtml string.

    return "<td></td>" if $valndx > 0;

    my ( $xhtml );

    if ( $cell->selected ) {
        $xhtml .= qq (<td>&nbsp;<input type="checkbox" name="tax_row_ids" value="$id" class="checkbox" checked />&nbsp;</td>);
    } else {
        $xhtml .= qq (<td>&nbsp;<input type="checkbox" name="tax_row_ids" value="$id" class="checkbox" />&nbsp;</td>);
    }
    
    return $xhtml;
}

sub checkbox_row
{
    # Niels Larsen, February 2004.

    # Displays the row of column-checkboxes. This row can include
    # one or more headers for projection columns. 

    my ( $display,     # Display structure
         ) = @_;

    # Returns an xhtml string.

    my ( $button, $columns, $column, $xhtml, $i, $icon_xhtml, 
         $type, $value, $style );

    $columns = $display->column_buttons;

    $xhtml = "";

    $button = Common::Option->new();

    $button->name( "tax_col_checkboxes" );
    $button->title( "Delete checkboxes" );
    $button->tiptext( "Deletes the row of column checkboxes." );
    $button->fgcolor( $FG_color );
    $button->bgcolor( $BG_color );
    
    $icon_xhtml = &Common::Widgets::menu_icon_close( $button );
    
    $i = 0;
    $style = "std_col_checkbox";
    
    foreach $column ( $columns->options )
    {
        $type = $column->datatype;
        $value = $column->selected;
        
        if ( $type =~ /^checkbox/ )
        {
            $xhtml .= qq (<td class="$style">$icon_xhtml</td>);
        }
        else
        {
            if ( $value ) {
                $xhtml .= qq (<td class="$style"><input name="tax_col_ids" type="checkbox" value="$i" checked></td>);
            } else {
                $xhtml .= qq (<td class="$style"><input name="tax_col_ids" type="checkbox" value="$i"></td>);
            }
        }
        
            $i += 1;
    }
    
    $xhtml .= qq (<td><table><tr><td valign="middle" align="center" width="25">$icon_xhtml</td></tr></table></td>);
    
    return $xhtml;
}

sub col_headers
{
    # Niels Larsen, December 2003.

    # Displays the header row for the Taxonomy hierarchy. This row can include
    # one or more headers for projection columns, and always includes
    # a pull-down menu with the parent nodes of the current view. 

    my ( $display,    # Display structure
         $state,      # State hash
         ) = @_;

    # Returns a string.

    my ( $xhtml, $title, $key, $root_node, $text, $args, $link, $tip, $i,
         $column, $datatype, $len, $style, $columns, $nodes, $img );

    $columns = $display->columns;
    $nodes = $display->nodes;

    $root_node = $nodes->{ $state->{"tax_root_id"} };

    # -------- Optional columns for statistics etc,

    $i = 0;

    foreach $column ( $columns->options )
    {
        $title = $column->coltext || $column->id;
        $len = length $title;
        
        $text = &Common::Names::format_display_name( $column->title ) || "";
        $tip = $column->tiptext || "";
        $datatype = $column->datatype || "";

        $tip .= " Click to delete.";

        # Set header and tooltip styles,
        
        if ( $datatype eq "orgs_taxa" or &Taxonomy::Display::is_select_item( $column ) )
        {
            $style = "tax_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3);
        }
        elsif ( $datatype =~ /^dna_/ )
        {
            $style = "std_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'#FFFFCC',BGCOLOR,'#666666',BORDER,3);
        }
        elsif ( $datatype =~ /^rna_/ )
        {
            $style = "rna_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'#FFFFCC',BGCOLOR,'#339966',BORDER,3);
        } 
        elsif ( $datatype =~ /^prot_/ )
        {
            $style = "prot_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'#FFFFCC',BGCOLOR,'#339966',BORDER,3);
        }
        elsif ( $datatype =~ /^func_/ )
        {
            $style = "go_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'#FFFFCC',BGCOLOR,'#cc6633',BORDER,3);
        }
        else {
            &error( qq (Wrong looking column data type -> "$datatype") );
            exit;
        }

        # Set link,

        if ( &Taxonomy::Display::is_select_item( $column ) )
        {
            $img = qq (<img src="$Common::Config::img_url/sys_cancel_half.gif" border="0" alt="Cancel button" />);
            $link = qq (<a style="color: #ffffff" href="javascript:delete_column($i)">$img</a>);
        }
        else
        {
#             if ( $len <= 2 ) {
#                 $title = "&nbsp;&nbsp;&nbsp;$title&nbsp;&nbsp;&nbsp;";
#             } elsif ( $len <= 3 ) {
#                 $title = "&nbsp;&nbsp;$title&nbsp;&nbsp;";
#             } elsif ( $len <= 4 ) {
#                 $title = "&nbsp;$title&nbsp;";
#             } else {
            if ( $len > 4 ) {
                &error( qq (Column title longer than 4 characters -> "$title") );
            }

            $link = qq (<a style="color: #ffffff" href="javascript:delete_column($i)">$title</a>);
        }
        
        # Add table element,

        $xhtml .= qq (<td class="$style" onmouseover="return overlib('$tip',$args)" onmouseout="return nd();">$link</td>);
        
        $i += 1;
    }

    # -------- Select menu that shows parent nodes,

    if ( $root_node->{"parent_id"} )
    {
        $xhtml .= "<td>". &Taxonomy::Widgets::parents_menu( $nodes, $state->{"tax_root_id"},
                                                            "tax_parents_menu", 1 ) ."</td>";
    }

    if ( $xhtml ) {
        return qq (<tr>$xhtml</tr>\n);
    } else {
        return;
    }
}

sub display_rows
{
    # Niels Larsen, October 2005.
    
    # Starting at the top node, follows the node children and creates xhtml for 
    # each taxon, including all its columns. The nodes are indented to relect 
    # hierarchy depth. For each taxon the children are sorted by display name. 

    my ( $sid,      # User or session id
         $display,  # Display structure
         $state,    # State hash
         $nid,      # Starting node id
         $indent,   # Starting indentation level - OPTIONAL 
         ) = @_;

    # Returns a list. 

    my ( $xhtml, $child, $node, $cid, $valndx, $column, $valndx_max, $cell, $cells, $values );

    $indent = 0 if not defined $indent;

    $node = &Taxonomy::Nodes::get_node( $display->nodes, $nid );

    $valndx = 0;

    $xhtml = "<tr>";

    if ( $display->columns ) 
    {
        $xhtml .= &Taxonomy::Widgets::display_col_row( $display, $nid, $valndx );
    }

    $xhtml .= "<td>". &Taxonomy::Widgets::display_node_row( $node, $valndx, $indent ) ."</td>";
    $xhtml .= "</tr>\n";

     if ( $display->columns )
     {
         $xhtml .= &Taxonomy::Widgets::display_data_rows( $display, $nid, $indent );
     }

    $indent += 1;

    foreach $child ( sort { $a->{"name"} cmp $b->{"name"} }
                     &Taxonomy::Nodes::get_children( $display->nodes, $nid ) )
    {
        $cid = &Taxonomy::Nodes::get_id( $child );
        $xhtml .= &Taxonomy::Widgets::display_rows( $sid, $display, $state, $cid, $indent );
    }

    return $xhtml;
}

sub display_col_row
{
    # Niels Larsen, February 2005.

    # Creates xhtml for the column cells of a given node. Depending 
    # on the types of the column cells of the node, this routine will
    # invoke different functions to paint them.

    my ( $display,
         $node_id,         # Node hash
         $valndx,
         ) = @_;

    # Returns an xhtml string.

    my ( $cell, $colndx, $datatype, $objtype, $abr_flag, $css_flag, $exp_flag, $xhtml, $link,
         $node, $column );

    $colndx = 0;
    $xhtml = "";

    $node = &Taxonomy::Nodes::get_node( $display->nodes, $node_id );

    foreach $column ( $display->columns->options )
    {
        if ( $column->values and $cell = $column->values->{ $node_id } )
        {
            $datatype = $cell->datatype;
            $objtype = $cell->objtype;

            if ( $objtype =~ /^checkbox/ )
            {
                $xhtml .= &Taxonomy::Widgets::checkbox_cell( $cell, $node_id, $valndx );
            }
            elsif ( $objtype =~ /_sims$/ )
            {
                $xhtml .= &Taxonomy::Widgets::sims_cell( $node, $cell, $valndx );
            }            
            elsif ( $objtype eq "tax_id" )
            {
                $xhtml .= &Taxonomy::Widgets::id_cell( $node_id, $valndx );
            }
            elsif ( $datatype =~ /^orgs_/ or $datatype =~ /_(seq|bases)$/ )
            {
                if ( $objtype =~ /_tsum$/ ) {
                    $exp_flag = 1;
                } else {
                    $exp_flag = 0;
                }
                
                $xhtml .= &Taxonomy::Widgets::stats_cell( $node, $cell, $colndx );
            }
#             elsif ( $datatype =~ /^dna_/ )
#             {
#                 if ( $objtype eq "dna_gc_distrib_tsum" ) {
#                     $xhtml .= &Taxonomy::Widgets::distrib_cell( $node, $colndx );
#                 } else {
#                     $xhtml .= &Taxonomy::Widgets::stats_cell( $node, $cell, $colndx );
#                 }
#             }
            elsif ( $datatype =~ /^prot_/ )
            {
                $xhtml .= &Taxonomy::Widgets::stats_cell( $node, $cell, $colndx, $valndx, "green_button", 0 );
            }
            elsif ( $datatype =~ /^func_/ )
            {
#                 if ( $objtype eq "go_link" )
#                 {
#                     $xhtml .= &Taxonomy::Widgets::go_link_cell( $node_id, $valndx );
#                 }
#                 else
#                 {
                    $xhtml .= &Taxonomy::Widgets::stats_cell( $node, $cell, $colndx, $valndx, "orange_button", 1 );
#                }
            }
            else
            {
                &error( qq (Wrong looking column datatype -> "$datatype") );
                exit;
            }
        }
        else {
            $xhtml .= qq (<td></td>);
        }

        $colndx += 1;
    }
    
    return $xhtml;
}

sub display_data_rows
{
    # Niels Larsen, November 2005.

    # IN FLUX 

    my ( $display,
         $node_id,
         $indent,
         ) = @_;

    my ( $maxrow, @cells, $cell, $link, $request, $column, $values, 
         $row, $col, $xhtml, $width, $title );

    $maxrow = -1;

    foreach $column ( $display->columns->options )
    {
        if ( exists $column->values->{ $node_id } and 
             $values = $column->values->{ $node_id }->values )
        {
            push @cells, $values;

            $maxrow = $#{ $values } if $maxrow < $#{ $values };
        }
        else {
            push @cells, [];
        }
    }

    $xhtml = "";

    if ( $maxrow >= 0 )
    {
        for ( $row = 0; $row <= $maxrow; $row++ )
        {
            $xhtml .= "<tr>";

            for ( $col = 0; $col <= $#cells; $col++ )
            {
                if ( exists $cells[$col]->[$row] )
                {
                    $cell = $cells[$col]->[$row];

                    $request = $cell->request;

                    $link = qq (<a href="javascript:$request">)
                          . qq (<img border="0" src="$Common::Config::img_url/report.gif" /></a>);

                    $xhtml .= qq (<td class="bullet_link">&nbsp;$link&nbsp;</td>);

                    $title = $cell->title;
                }
                else {
                    $xhtml .= qq (<td></td>);
                }
            }

            $width = 18 * ($indent + 1);

            $xhtml .= qq (<td><table border="0" cellspacing="0" cellpadding="0"><tr>);
            $xhtml .= qq (<td width="$width"></td>);
            $xhtml .= qq (<td class="leaf">$title</td>);
            $xhtml .= qq (</tr></table></td>);

            $xhtml .= "</tr>\n";
        }
    }

    return $xhtml;
}

sub display_node_row
{
    # Niels Larsen, May 2003.

    # Generates XHTML for a given node. It indents, puts arrows, names 
    # and links on. This part is a table. 
    
    my ( $node,    # Node hash
         $valndx,
         $indent,  # Indentation 
         )= @_;

    # Returns a string. 

    my ( $xhtml, $width, $arrow, $arrow_link, $text, $node_id, $name, $alt_name,
         $leaf_node, $has_children );

    return "" if $valndx > 0;

    $node_id = &Taxonomy::Nodes::get_id( $node );

    if ( &Taxonomy::Nodes::is_leaf( $node ) ) {
        $leaf_node = 1;
    } else {
        $leaf_node = 0;
    }

    if ( &Taxonomy::Nodes::get_ids_children( $node ) ) {
        $has_children = 1;
    } else {
        $has_children = 0;
    }

    $xhtml = qq (<table border="0" cellspacing="0" cellpadding="0"><tr>);
    
    # Indentation,

    if ( defined $indent and $indent > 0 )
    {
        if ( $leaf_node ) {
            $width = 18 * ($indent - 1);
        } else {
            $width = 18 * $indent;
        }
        
        $xhtml .= qq (<td width="$width"></td>);
    }

    # Optional left open/close arrow,

    if ( $leaf_node )
    {
        $xhtml .= qq (<td width="18" align="center">&nbsp;</td>);
    }
    else
    {
        if ( $has_children ) 
        {
            $arrow = &Common::Widgets::arrow_down();
            $arrow_link = qq (<a class="arrow_l" href="javascript:close_node($node_id)">$arrow</a>);
        }
        else
        {
            $arrow = &Common::Widgets::arrow_right();
            $arrow_link = qq (<a class="arrow_l" href="javascript:open_node($node_id)">$arrow</a>);
        }
        
        $xhtml .= qq (<td class="arrow_l">$arrow_link</td>);
    }

    # Main text,

    $text = &Taxonomy::Nodes::get_key( $node, "text" );
    $name = &Taxonomy::Nodes::get_name( $node );

    if ( $text ) {
        $text = &Taxonomy::Widgets::format_display_name( $text );
    } elsif ( $name ) {
        $text = &Taxonomy::Widgets::format_display_name( $name );
    } else {
        &error( qq (Node "$node_id" has no name or text to display) );
    }

    $alt_name = &Taxonomy::Nodes::get_key( $node, "alt_name" );

    if ( defined $alt_name ) {
        $text .= qq ( ($alt_name));
    }

    if ( $leaf_node ) 
    {
        $xhtml .= qq (<td class="leaf">$text</td>);
    }
    else 
    {
        if ( $has_children ) {
            $xhtml .= qq (<td class="group_arrow"><a class="group" href="javascript:focus_node($node_id)">$text</a></td>);
        } else {
            $xhtml .= qq (<td class="group"><a class="group" href="javascript:focus_node($node_id)">$text</a></td>);
        }
    }

    # Optional right open/close arrow,

    if ( $has_children )
    {
        $arrow = &Common::Widgets::arrow_right();
        $arrow_link = qq (<a class="arrow_r" href="javascript:open_node($node_id)">$arrow</a>);
        $xhtml .= qq (<td class="arrow_r" width="18" align="center">$arrow_link</td>);
    }

    $xhtml .= qq (</tr></table>);
}

sub format_display_name
{
    # Niels Larsen, August 2003.

    # Substitutes titles that are not good for display with a more 
    # familiar name. For example "root" becomes "NCBI Taxonomy"
    # and so on. 

    my ( $name,    # Name string
         ) = @_;

    # Returns a string.
    
    $name ||= "";

    if ( $name eq "root" )
    {
        $name = "NCBI Taxonomy";
    }
    elsif ( $name eq "cellular organisms" )
    {
        $name = "Cellular Organisms";
    }
    else
    {
        $name = &Common::Names::format_display_name( $name );
    }

    return $name;
}

sub format_page
{
    # Niels Larsen, January 2005.

    # Composes the page. At the top there is a title plus a row of opened or
    # closed menus, then an optional row of buttons (depends on previous 
    # choices), then the display itself. If a list of messages is given,
    # a panel is shown across the screen with the message. 
   
    my ( $sid,            # Session id
         $display,        # Display structure
         $state,          # State hash
         $messages,       # List of messages - OPTIONAL
         ) = @_;

    # Returns an xhtml string.

    my ( $xhtml, $root_id );

    $xhtml = "";

    # At the top of the page there is a row with widgets and pullout 
    # menus, then follows the hierarchy,

    $xhtml .= &Taxonomy::Widgets::menu_row( $sid, $display, $state );

    # ------ Display message(s) if any,

    if ( $messages and @{ $messages } )
    {
        $xhtml .= qq (<table><tr><td height="10">&nbsp;</td></tr></table>\n);
        $xhtml .= "\n". &Common::Widgets::message_box( $messages ) ."\n";
        $xhtml .= qq (<table><tr><td height="5"></td></tr></table>\n);
    }

    # -------- Optional save and delete button

    $xhtml .= &Taxonomy::Widgets::action_buttons( $sid, $state, $display ) || "";

    # Each skeleton row is a table row,

    $xhtml .= qq (\n<table border="0" cellspacing="0" cellpadding="0">\n);

    # ------ Optional row with column checkboxes,

    if ( @{ $display->column_buttons->options } ) 
    {
        $xhtml .= &Taxonomy::Widgets::checkbox_row( $display );
    }

    # ------ Optional row with column headers and parents menu,

    if ( $display->columns->options ) 
    {
        $xhtml .= &Taxonomy::Widgets::col_headers( $display, $state );
    }

    # ------ Display children only if at the root,

    $root_id = $state->{"tax_root_id"};

    $xhtml .= &Taxonomy::Widgets::display_rows( $sid, $display, $state, $root_id, 0 );
    
    $xhtml .= qq (</table>\n);
    $xhtml .= qq (<table><tr><td height="15">&nbsp;</td></tr></table>\n);

    # ------ Initialize hidden variables,

    # They are needed by the javascript functions in taxonomy.js,

#<input type="hidden" name="tax_col_ids" value="" />
#<input type="hidden" name="tax_row_ids" value="" />
#<input type="hidden" name="tax_root_name" value="" />

    $xhtml .= qq (
<input type="hidden" name="viewer" value="" />
<input type="hidden" name="input" value="" />
<input type="hidden" name="request" value="" />
<input type="hidden" name="tax_click_id" value="" />
<input type="hidden" name="tax_col_key" value="" />
<input type="hidden" name="tax_orgs_key" value="" />
<input type="hidden" name="tax_col_index" value="" />
<input type="hidden" name="tax_info_index" value="" />
<input type="hidden" name="tax_info_type" value="" />
<input type="hidden" name="tax_info_key" value="" />
<input type="hidden" name="tax_info_menu" value="" />
<input type="hidden" name="tax_info_tip" value="" />
<input type="hidden" name="tax_info_col" value="" />
<input type="hidden" name="tax_info_ids" value="" />
<input type="hidden" name="tax_inputdb" value="" />
<input type="hidden" name="tax_show_widget" value="" />
<input type="hidden" name="tax_hide_widget" value="" />
);

    return $xhtml;
}

sub help_icon
{
    # Niels Larsen, August 2008.
    
    my ( $sid,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $descr = "Offers help with navigation and use of this page.";

    $args = {
        "viewer" => $Viewer_name,
        "request" => "help",
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

sub id_cell
{
    # Niels Larsen, March 2004.

    # Creates the content of an id column cell. 
    
    my ( $id,     # Node id
         $valndx, # 
         ) = @_;

    # Returns an xhtml string. 

    return "<td></td>" if $valndx > 0;
    
    my ( $text, $xhtml, $link );

    $text = sprintf "%07i", $id;

    $link = qq (<a style="font-family: monospace" )
           .qq (href="javascript:orgs_taxa_report('$id','/$Proj_site_dir')">&nbsp;&nbsp;<tt>$text</tt>&nbsp;</a>);

    $xhtml = qq (<td class="light_grey_button_up">$link</td>);
    
    return $xhtml;
}

sub menu_row
{
    # Niels Larsen, February 2004.

    # Composes the top row on the page with title, menus and/or icons. 

    my ( $sid,           # Session ID
         $display,       # Display structure
         $state,         # Viewer state 
         ) = @_;
    
    # Returns an array. 

    my ( $title, $alt_title, @l_widgets, @r_widgets, $xhtml, $menu );

    # ------ Title box,

    $title = $display->title;
    $alt_title = $display->alt_title;

    if ( $alt_title and length $title <= 30 ) {
        $title .= " ($alt_title)";
    }
        
    push @l_widgets, &Common::Widgets::title_box( $title, "taxonomy_title", 20, $FG_color, $BG_color );

    # ------ Control menu,

    if ( $state->{"tax_control_menu_open"} ) {
        push @l_widgets, &Taxonomy::Widgets::control_menu( $sid, $display, $state );
    } else {
        push @l_widgets, &Taxonomy::Widgets::control_icon();
    }
    
    # ------ Data menu,

#    if ( $state->{"tax_data_menu_open"} ) {
#        push @l_widgets, &Taxonomy::Widgets::data_menu( $sid, $display );
#    } else {
#        push @l_widgets, &Taxonomy::Widgets::data_icon();
#    }
    
    # ------ User menu,

#     if ( $state->{"tax_has_selections"} )
#     {
#         $menu = Taxonomy::Menus->user_menu( $sid );
        
#         if ( @{ $menu->options } )
#         {
#             if ( $state->{"tax_user_menu_open"} ) {
#                 push @l_widgets, &Taxonomy::Widgets::user_menu( $sid, $display, $menu );
#             } else {
#                 push @l_widgets, &Taxonomy::Widgets::user_icon();
#             }
#         }
#     }
    
    # ------ Search icon,

    push @r_widgets, &Taxonomy::Widgets::search_icon( $sid );

    # ------ Help button,

    push @r_widgets, &Taxonomy::Widgets::help_icon( $sid );

    # ------ Put everything together as a single row,

    $xhtml = qq (<table><tr><td height="10">&nbsp;</td></tr></table>\n);
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, \@r_widgets );

    return $xhtml;
}

sub control_icon
{
    # Niels Larsen, February 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the taxonomy control menu. 

    # Returns an xhtml string. 

    my ( $args );

    $args = {
        "name" => "tax_control_menu",
        "title" => "Control menu",
        "description" => qq (Shows a menu with options for selections, column deletions, and other control options.),
        "icon" => "sys_params_large.png",
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
    };

    return &Common::Widgets::menu_icon( $args );
}

sub control_menu
{
    # Niels Larsen, October 2005.

    # Generates a menu where the user can activate select columns etc. 

    my ( $sid,        # Session id
         $display,    # Display object - OPTIONAL
         $state,
         ) = @_;

    # Returns an xhtml string. 

    my ( $ids, %ids, $menu, @options, $option, $xhtml, @divs );

    if ( defined $display )
    {
        $ids = $display->columns->match_options_ids( "name" => "tax_control_menu" );
        
        if ( @options = @{ $display->column_buttons->options } )
        {
            %ids = map { $_->id, 1 } @options;        
            push @{ $ids }, keys %ids;
        }
    }
    else {
        $ids = [];
    }

    $menu = Taxonomy::Menus->control_menu( $sid, $state->{"tax_www_path"} );

    @divs = (
        [ "orgs_taxa", "Information", "blue_menu_divider" ],
        [ "save", "Save", "blue_menu_divider" ],
        [ "delete", "Delete", "blue_menu_divider" ],
        [ "download", "Download selected", "blue_menu_divider" ],
        );

    $menu->add_dividers( \@divs );

    $menu->select_options( $ids );

    $menu->onchange( "javascript:handle_menu(this.form.tax_control_menu,'handle_tax_control_menu')" );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

sub data_icon
{
    # Niels Larsen, April 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the taxonomy data menu. 

    # Returns an xhtml string. 

    my ( $args );

    $args = {
        "name" => "tax_data_menu",
        "title" => "Data menu",
        "description" => qq (Shows a menu with mostly database statistics that can be added to the tree view.),
        "icon" => "sys_data_book.png",
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
    };

    return &Common::Widgets::menu_icon( $args );
}

sub data_menu
{
    # Niels Larsen, October 2005.

    # Generates a menu where the user can overlay data as columns. The menu 
    # includes data that are in the system and colored dividers separate the 
    # different kinds of options. An asterisk indicates options selected. 

    my ( $sid,        # Session id
         $display,    # Display structure - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $ids, $menu, $xhtml, @divs );

    if ( defined $display ) {
        $ids = $display->columns->match_options_ids( "name" => "tax_data_menu" );
    } else {
        $ids = [];
    }
    
    $menu = Taxonomy::Menus->data_menu( $sid );

    @divs = (
             [ "orgs_taxa", "Organism Taxa", "blue_menu_divider" ],
             [ "rna_bases", "RNA Bases", "green_menu_divider" ],
             [ "rna_seq", "RNA Sequences", "green_menu_divider" ],
             [ "rna_ali", "RNA Alignments", "green_menu_divider" ],
             [ "dna", "DNA Sequences", "green_menu_divider" ],
             [ "prot", "Protein Sequences", "green_menu_divider" ],
             );

    $menu->add_dividers( \@divs );

    $menu->select_options( $ids );

    $menu->onchange( "javascript:handle_menu(this.form.tax_data_menu,'handle_tax_data_menu')" );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

sub user_menu
{
    # Niels Larsen, January 2006.

    # Generates a menu with user selections and results, separated by 
    # colored dividers. An asterisk indicates options selected. 

    my ( $sid,        # Session id
         $display,    # Display structure
         ) = @_;

    # Returns an xhtml string. 

    my ( $ids, $menu, $xhtml, $name, $option, @divs );

    $menu = Taxonomy::Menus->user_menu( $sid );

    if ( defined $display ) {
        $ids = $display->columns->match_options_ids( "name" => "tax_user_menu" );
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
             [ "orgs_taxa", "Organism Taxa", "blue_menu_divider" ],
             [ "rna_seq", "RNA Sequences", "green_menu_divider" ],
             [ "rna_ali", "RNA Alignments", "green_menu_divider" ],
             );

    $menu->add_dividers( \@divs );

    $menu->select_options( $ids );

    $menu->onchange( "javascript:handle_menu(this.form.tax_user_menu,'handle_tax_user_menu')" );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );
    
    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

sub orgs_taxa_report
{
    # Niels Larsen, December 2003.

    # Produces a simple report page for a single taxonomy entry. 

    my ( $sid,       # Session id 
         $entry,     # Taxonomy entry structure
         ) = @_;

    # Returns an xhtml string. 

    my ( $xhtml, $width, $elem, $menu, $menu_xhtml, $key, $style, $option, $title );

    $width = 20;
    
    $xhtml = &Taxonomy::Widgets::report_title( "NCBI Taxonomy Entry" );

    $xhtml .= qq (<table cellpadding="0" cellspacing="0">\n);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="tax_report_title"><tr><td>Names</td></tr></table></td></tr>
);

    foreach $elem ( @{ $entry->{"names"} } )
    {
        $key = &Common::Names::format_display_name( $elem->[0] );
        $title = &Common::Names::format_display_name( $elem->[1] );

        $xhtml .= qq (<tr><td width="$width"></td><td class="tax_report_key">$key</td>)
                . qq (<td class="tax_report_value">$title</td><td width="$width"></td></tr>\n);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> CLASSIFICATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $style = qq (padding-top: 0px; padding-bottom: 0px; padding-left: 1px;);

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="tax_report_title"><tr><td>Classification</td></tr></table></td></tr>
);

    # Various keys,

    foreach $elem ( @{ $entry->{"classification"} } )
    {
        $key = &Common::Names::format_display_name( $elem->[0] );

        $title = $elem->[1] || "&nbsp;";
        $title = &Common::Names::format_display_name( $elem->[1] ) if $elem->[1];

        $xhtml .= qq (<tr><td width="$width"></td><td class="tax_report_key">$key</td>)
                . qq (<td class="tax_report_value">$title</td><td width="$width"></td></tr>\n);
    }

    # Parents menu,

    $menu = Taxonomy::Menus->new();
    $menu->name( "report_menu" );
    $menu->css( "beige_menu" );

    foreach $elem ( @{ $entry->{"parents"} } )
    {
        $title = &Common::Names::format_display_name( $elem->[1] );
        $option = Common::Option->new( "id" => $elem->[0], "title" => $title );
        $menu->append_option( $option );
    }

    if ( @{ $menu->options } ) {
        $menu_xhtml = &Common::Widgets::pulldown_menu( $menu, { "close_button" => 0 } );
    } else {
        $menu_xhtml = "";
    }
    
    $xhtml .= qq (<tr><td width="$width"></td><td class="tax_report_key">Higher Taxa</td>)
            . qq (    <td class="tax_report_value" style="$style">$menu_xhtml</td><td width="$width"></td></tr>\n);

    # Children menu,

    $menu = Taxonomy::Menus->new();
    $menu->name( "report_menu" );
    $menu->css( "beige_menu" );

    foreach $elem ( @{ $entry->{"children"} } )
    {
        $title = &Common::Names::format_display_name( $elem->[1] );
        $option = Common::Option->new( "id" => $elem->[0], "title" => $title );
        $menu->append_option( $option );
    }

    if ( @{ $menu->options } ) {
        $menu_xhtml = &Common::Widgets::pulldown_menu( $menu, { "close_button" => 0 } );
    } else {
        $menu_xhtml = "";
    }
    
    $xhtml .= qq (<tr><td width="$width"></td><td class="tax_report_key">Lower Taxa</td>)
            . qq (    <td class="tax_report_value" style="$style">$menu_xhtml</td><td width="$width"></td></tr>\n);
    
    # Organism count,

    $title = &Common::Util::commify_number( $entry->{"organisms"} );
    
    if ( $entry->{"organisms"} > 1 ) {
        $title .= " organisms within this group";
    } elsif ( $entry->{"organisms"} > 0 ) {
        $title .= " organism within this group";
    } else {
        $title = "";
    }
    
    $xhtml .= qq (<tr><td width="$width"></td><td class="tax_report_key">Organism count</td>)
           . qq (    <td class="tax_report_value">$title</td><td width="$width"></td></tr>\n);        

    # >>>>>>>>>>>>>>>>>>>>>>>> GENETIC DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="tax_report_title"><tr><td>Genetic Information</td></tr></table></td></tr>
);

    foreach $elem ( @{ $entry->{"genetic"} } )
    {
        $key = &Common::Names::format_display_name( $elem->[0] );

        $title = $elem->[1];
        $title = &Common::Names::format_display_name( $elem->[1] ) if $elem->[1];

        $xhtml .= qq (<tr><td width="$width"></td><td class="tax_report_key">$key</td>)
                . qq (<td class="tax_report_value">$title</td><td width="$width"></td></tr>\n);
    }

    $xhtml .= "</table>\n";

#     $title = qq (Data from the <strong>NCBI Taxonomy</strong>);
# #    $xhtml .= &Common::Widgets::footer_bar( $title );

#      $xhtml .= qq (<table width="100%"><tr height="60"><td align="right" valign="bottom">
#     <div class="tax_report_author">$title</div>
#   </td></tr></table>\n);

    return $xhtml;
}

sub parents_menu
{
    # Niels Larsen, January 2004.

    # Generates a pull-down menu where all parents to the current root (as
    # specified by the given state hash) are listed. 

    my ( $nodes,   # Nodes hash
         $root_id, # Root node id
         $name,    # Input field name - OPTIONAL, default "tax_parents_menu"
         $head,    # Add header with count - OPTIONAL, default off
         ) = @_;

    # Returns an xhtml string.

    $head = "" if not defined $head;

    my ( $root_node, $nid, $id, $node, $title, $xhtml, $menu, $option, $count );

    if ( $name ) {
        $menu = Taxonomy::Menus->new( "name" => $name );
    } else {
        $menu = Taxonomy::Menus->new( "name" => "tax_parents_menu" );
    }        

    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $menu->onchange( "javascript:handle_parents_menu(this.form.tax_parents_menu)" );
    
    $root_node = &Taxonomy::Nodes::get_node( $nodes, $root_id );

    if ( not $head )
    {
        $title = &Taxonomy::Nodes::get_name( $root_node );
        $title = &Taxonomy::Widgets::format_display_name( $title );

        $option = Common::Option->new( "id" => $root_id, 
                                       "title" => $title,
                                       "style" => "grey_menu" );
                                       
        $menu->append_option( $option );
    }

    $nid = &Taxonomy::Nodes::get_id_parent( $root_node );

    while ( $nodes->{ $nid } )
    {
        $node = &Taxonomy::Nodes::get_node( $nodes, $nid );
        $title = &Taxonomy::Nodes::get_name( $node );
        $title = &Taxonomy::Widgets::format_display_name( $title );

        $option = Common::Option->new( "id" => $nid, 
                                       "title" => $title,
                                       "style" => "menu_item" );
                                       
        $menu->append_option( $option );

        $nid = &Taxonomy::Nodes::get_id_parent( $node );
    }
    
    $count = $menu->options_count();

    if ( $head )
    {
        $option = Common::Option->new( "id" => "",
                                       "title" => $count > 1 ? "$count parents" : "$count parent",
                                       "style" => "grey_menu" );

        $menu->prepend_option( $option );
    }

    $menu->selected( $menu->options->[0]->id );
    
    $xhtml = &Common::Widgets::pulldown_menu( $menu, { "close_button" => 0 } );
    
    return $xhtml;
}

sub report_title
{
    # Niels Larsen, January 2005.
    
    # Creates a small bar with a close button. It is to be used
    # in report windows.

    my ( $text,     # Title text
         ) = @_;

    # Reports an xhtml string.

    my ( $xhtml, $close );

    $close = qq (<img src="$Common::Config::img_url/sys_cancel.gif" border="0" alt="Cancel button" />);

    $xhtml = qq (
<table cellpadding="4" cellspacing="0" width="100%"><tr>
     <td align="left" class="tax_report_title_l" width="98%">$text</td>
     <td align="right" class="tax_report_title_r" width="1%"><a href="javascript:window.close()">$close</a></td>
</tr></table>

);

    return $xhtml;
}

sub rna_seq_report
{
    # Niels Larsen, January 2003.
    
    # Produces a report page for a single RNA entry. 

    my ( $sid,    # Session id 
         $entry,  # Entry structure
         $types,  # List of [ rna type, readable rna name ]
         ) = @_;

    # Returns an xhtml string. 

    my ( $xhtml, $width, $elem, $text, $menu, $key, @items, $msgs,
         $style, $type, @tuples, $tuple, $rna_id, $idstr, $loc, $ref,
         @text );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> REPORT TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $entry )
    {
        $type = $entry->{"rna_origin"}->{"type"};

        if ( @tuples = grep { $_->[0] eq $type } @{ $types } )
        {
            $xhtml = &Taxonomy::Widgets::report_title( "$tuples[0]->[1] Entry" );
        }
        else {
            &error( qq (Wrong looking RNA type -> "$type") );
            exit;
        }
    }
    else {
        $xhtml = &Taxonomy::Widgets::report_title( "Missing Entry" );
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ORGANISM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $entry )
    {
        $xhtml .= qq (<table cellpadding="0" cellspacing="0">\n);
        $width = 20;
        
        # Organism description,

        $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="tax_report_title"><tr><td>Organism</td></tr></table></td></tr>
);

        $elem = $entry->{"rna_organism"};
        
        foreach $tuple ( [ "genus", "Genus" ], [ "species", "Species" ] )
        {
            $key = $tuple->[0];
            
            if ( $elem->{ $key } ) {
                $text = &Common::Names::format_display_name( $elem->{ $key } );
            } else {
                $text = "";
            }
            
            $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">$tuple->[1]</td>)
                    . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
        }

        foreach $tuple ( [ "sub_species", "Sub-species" ], [ "strain", "Strain" ],
                         [ "sub_strain", "Sub-strain" ], [ "cultivar", "Cultivar" ],
                         [ "biovar", "Biovar" ], [ "serotype", "Serotype" ],
                         [ "serovar", "Serovar" ], [ "variety", "Variety" ], 
                         [ "ecotype", "Ecotype" ], [ "haplotype", "Haplotype" ],
                         [ "common_name", "Common name" ], [ "tax_id", "Taxonomy ID" ] )
        {
            $key = $tuple->[0];
            
            if ( $elem->{ $key } )
            {
                $text = &Common::Names::format_display_name( $elem->{ $key } );
                
                $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">$tuple->[1]</td>)
                        . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
            }
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> MOLECULE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="tax_report_title"><tr><td>Molecule</td></tr></table></td></tr>
);

        # Molecule source,

        $elem = $entry->{"rna_source"};

        foreach $tuple ( [ "tissue_lib", "Tissue library" ], [ "dev_stage", "Devel. stage" ],
                         [ "environmental_sample", "Env. sample" ], [ "clone", "Clone" ],
                         [ "specific_host", "Specific host" ], [ "isolate", "Isolate" ],
                         [ "cell_line", "Cell line" ], [ "sub_clone", "Sub-clone" ], 
                         [ "isolation_source", "Isol. source" ], [ "tissue_type", "Tissue type" ],
                         [ "lab_host", "Lab. host" ], [ "tissue", "Tissue" ],
                         [ "organelle", "Organelle" ], [ "clone_lib", "Clone library" ],
                         [ "note", "Note" ], [ "cell_type", "Cell type" ],
                         [ "label", "Label" ], [ "plasmid", "Plasmid" ] )
        {
            $key = $tuple->[0];
            
            if ( $elem->{ $key } )
            {
                $text = &Common::Names::format_display_name( $elem->{ $key } );
                
                $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">$tuple->[1]</td>)
                        . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
            }
        }

        $xhtml .= qq (\n<tr height="12"><td></td></tr>\n);

        # Molecule description,
        
        $text = $entry->{"rna_molecule"}->{"length"};
        
        $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">Length</td>)
                . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);

        $text = $entry->{"rna_molecule"}->{"other"};

        $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">Non-WC bases</td>)
                . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);

        $text = $entry->{"rna_molecule"}->{"gc_pct"};

        $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">Percent G+C</td>)
                . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA SOURCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="tax_report_title"><tr><td>Data source</td></tr></table></td></tr>
);

        $elem = $entry->{"rna_origin"};
        
        foreach $tuple ( [ "src_db", "Databank" ], [ "src_ac", "Accession #(s)" ],
                         [ "src_id", "Entry ID" ], [ "src_kw", "Keywords" ], 
                         [ "src_de", "Description" ], [ "method", "Extraction method" ] )
        {
            $key = $tuple->[0];
            
            if ( $elem->{ $key } )
            {
                $text = &Common::Names::format_display_name( $elem->{ $key } );
                
                $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">$tuple->[1]</td>)
                        . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
            }
        }
        
        @text = map { $_->{"rna_beg"} ."&nbsp;-&nbsp;". $_->{"rna_end"} } @{ $entry->{"rna_locations"} };
        $text = join ", ", @text;
        
        $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">RNA positions</td>)
                . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
    
        @text = map { $_->{"dna_beg"} ."&nbsp;-&nbsp;". $_->{"dna_end"} } @{ $entry->{"rna_locations"} };
        $text = join ", ", @text;
        
        $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">DNA positions</td>)
                . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
    
        @text = map { $_->{"strand"} } @{ $entry->{"rna_locations"} };
        $text = join ", ", @text;
    
        $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">Strand(s)</td>)
                . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);   

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REFERENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="tax_report_title"><tr><td>References</td></tr></table></td></tr>
);

        foreach $ref ( @{ $entry->{"rna_references"} } )
        {
            foreach $tuple ( [ "authors", "Authors" ], 
                             [ "title", "Title" ], [ "literature", "Literature" ] )
            {
                $key = $tuple->[0];
                
                if ( $ref->{ $key } )
                {
                    $text = &Common::Names::format_display_name( $ref->{ $key } );
                    
                    $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">$tuple->[1]</td>)
                            . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
                }
            }
            
            $xhtml .= qq (\n<tr height="12"><td></td></tr>\n);
        }

        if ( @{ $entry->{"rna_references"} } )
        {
            foreach $ref ( @{ $entry->{"rna_xrefs"} } )
            {
                foreach $tuple ( [ "name", "Database name" ], [ "id", "ID" ] )
                {
                    $key = $tuple->[0];
                
                    if ( $ref->{ $key } )
                    {
                        $text = &Common::Names::format_display_name( $ref->{ $key } );
                        
                        $xhtml .= qq (<tr><td width="$width"></td><td class="rna_report_key">$tuple->[1]</td>)
                                . qq (<td class="rna_report_value">$text</td><td width="$width"></td></tr>\n);
                    }
                }
            }
            
            $xhtml .= qq (\n<tr height="12"><td></td></tr>\n);
        }
        
        $xhtml .= "</table>\n";
    }
    else
    {
        $msgs = [[ "Error", "No RNA in database." ]];

        $xhtml .= qq (<table cellpadding="50" cellspacing="50"><tr><td>\n);

        $xhtml .= &Common::Widgets::message_box( $msgs );

        $xhtml .= qq (</td></tr></table>\n);        
    }

    # Report footer,

    $xhtml .= qq (<table width="100%" cellpadding="0" cellspacing="0">
 <tr height="40"><td align="right" valign="bottom">
 <div class="tax_report_author">Data from <strong>EMBL</strong></div>
 </td></tr></table>\n);

    return $xhtml;
}

sub save_taxa_window
{
    # Niels Larsen, February 2004.

    # Creates a save selection page with title bar, close button and a 
    # form that accepts a menu title and a column header for the selection.

    my ( $sid,   # Session id 
         $state,  # States hash 
         ) = @_;

    # Returns a string. 

    my ( $title, $title_bar, $xhtml, $id, $script );

    # -------- Title,

    $title = qq (Save Taxa Selection);
    $title_bar = &Common::Widgets::popup_bar( $title, "form_bar_text", "form_bar_close" );

    # -------- Page html,

    $script = "$Proj_site_dir/index.cgi";

    $xhtml = qq (

<table cellpadding="0" cellspacing="0" width="100%">
<tr><td>
$title_bar
</td></tr>

<tr><td>
<div id="form_content">
<p>
Saved selections can appear in menus and as display columns. Below 
please enter the name that should appear in the menu and a short 
abbreviation to be used as column title. 
</p>
<form target="viewer" name="selection_window" action="" method="post">

<input type="hidden" name="viewer" value="$state->{'tax_viewer_name'}" />
<input type="hidden" name="session_id" value="$sid" />
<input type="hidden" name="request" value="save_orgs" />
);

    foreach $id ( @{ $state->{"tax_row_ids"} } )
    {
        $xhtml .= qq (<input type="hidden" name="tax_row_ids" value="$id" />\n);
    }

$xhtml .= qq (

<table cellspacing="3">
<tr>
   <td align="right">Menu title&nbsp;&raquo;</td>
   <td><input type="text" size="20" maxlength="20" name="tax_info_menu" value="">&nbsp;(Max. 20 characters)</td>
</tr>
<tr>
   <td align="right">Column header&nbsp;&raquo;</td>
   <td><input type="text" size="4" maxlength="4" name="tax_info_col" value="" />&nbsp;(Max. 4 characters)</td>
</tr>
<tr>
   <td align="right">Tooltip text&nbsp;&raquo;</td>
   <td><input type="text" size="20" maxlength="200" name="tax_info_tip" value="" />&nbsp;(Optional, max. 200 characters)</td>
</tr>
<tr>
   <td></td>
   <td height="60"><input type="submit" value="Save" class="grey_button" /></td>
</tr>
</table>
</div>

</form>
</td></tr></table>

<script language="JavaScript">

   document.selection_window.tax_info_menu.focus();

   opener.document.viewer.request.value = "";
   opener.document.viewer.submit();

</script>
);

    return $xhtml;
}

sub search_icon
{
    # Niels Larsen, August 2008.

    # Returns a javascript link that opens a window with a form to enter search words
    # into. 
    
    my ( $sid,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $descr = "Displays a panel for entering search words.";

    $args = {
        "viewer" => $Viewer_name,
        "request" => "search_window",
        "sid" => $sid,
        "title" => "Search Panel",
        "description" => $descr,
        "icon" => "sys_search.gif",
        "height" => 450,
        "width" => 600,
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 180,
    };

    return &Common::Widgets::window_icon( $args );
}

sub search_window
{
    # Niels Larsen, August 2003.

    # Creates a search page with title bar, close button and a 
    # form that specifies what to search against and how. 

    my ( $sid,       # Session id 
         $state,     # State hash
         $title,     # Header title
         $nodes,     # Nodes for parents menu
         ) = @_;

    # Returns a string. 

    my ( $title_bar, $xhtml, $search_text, $menu, $option, $tuple, 
         $titles_xhtml, $target_xhtml, $type_xhtml, $script );

    # -------- Title,

    $title = &Taxonomy::Widgets::format_display_name( $title );

    $title_bar = &Common::Widgets::popup_bar( "Search $title", "form_bar_text", "form_bar_close" );

    # -------- Initialize search box,

    $search_text = $state->{"tax_search_text"} || "";

    $search_text =~ s/^\s*//;
    $search_text =~ s/\s*$//;

    # -------- Search titles,
    
    $titles_xhtml = &Taxonomy::Widgets::parents_menu( $nodes, $state->{"tax_root_id"}, "tax_search_id" );

    # -------- Target select menu,

    $menu = Taxonomy::Menus->new();

    $menu->name( "tax_search_target" );
    $menu->css( "grey_menu" );
    $menu->selected( $state->{"tax_search_target"} );

    foreach $tuple ( [ "ids", "ids" ],
                     [ "scientific_names", "latin names" ],
                     [ "common_names", "common names" ],
                     [ "synonyms", "synonyms" ],
                     [ "all_names", "all names" ] )
    {
        $option = Common::Option->new();

        $option->id( $tuple->[0] );
        $option->title( $tuple->[1] );
        $option->css( "menu_item" );

        $menu->append_option( $option );
    }

    $target_xhtml = &Common::Widgets::pulldown_menu( $menu, { "close_button" => 0 } );
    
    # -------- Type select menu,
    
    $menu = Taxonomy::Menus->new();

    $menu->name( "tax_search_type" );
    $menu->css( "grey_menu" );
    $menu->selected( $state->{"tax_search_type"} );

    foreach $tuple ( [ "partial_words", "partial words" ],
                     [ "name_beginnings", "name beginnings" ],
                     [ "whole_words", "whole words only" ] )
    {
        $option = Common::Option->new();

        $option->id( $tuple->[0] );
        $option->title( $tuple->[1] );
        $option->css( "menu_item" );

        $menu->append_option( $option );
    }
    
    $type_xhtml = &Common::Widgets::pulldown_menu( $menu, { "close_button" => 0 } );

    # -------- Page html,

    $script = "$Proj_site_dir/index.cgi";

    $xhtml = qq (

<table cellpadding="0" cellspacing="0" width="100%">
<tr><td>
$title_bar
</td></tr>

<tr><td>
<div id="form_content">
<p>
The text in the search box below is used to search against the names 
of all <strong>$title</strong>. It is possible to search against ids,
latin (scientific) names, common names, synonyms or against all names.
Matches may occur in the middle of names but can be limited to whole 
words only, in which case your search word should have three characters
or more. The matching is done case-independently.
</p>
<form target="viewer" name="search_window" action="$script" method="post">

<input type="hidden" name="session_id" value="$sid" />

<table cellspacing="5">
<tr height="25">
   <td align="right">Search</td>
   <td colspan="3">$titles_xhtml</td>
</tr>
<tr height="25">
   <td align="right">for</td>
   <td colspan="3"><input type="text" size="50" name="tax_search_text" value=" $search_text" /></td>
</tr>
<tr height="25">
   <td align="right">against</td>
   <td>$target_xhtml</td>
   <td align="right">while matching</td>
   <td>$type_xhtml</td>
</tr>
<tr>
   <td></td>
   <td height="60"><input type="submit" name="request" value="Search" class="grey_button" /></td>
</tr>
</table>

</form>
</div>
</td></tr></table>

<script language="JavaScript">

   document.search_window.tax_search_text.focus();

</script>
);

    return $xhtml;
}

sub sims_cell
{
    # Niels Larsen, December 2005.

    # 

    my ( $node,
         $cell,
         $colndx,
          ) = @_;

    my ( $value, $style, $xhtml );

    $value = $cell->value;

    if ( defined $value )
    {
        $style = $cell->style || "";
        
        if ( $style ) {
            $xhtml .= qq (<td class="std_button_up" style="$style">&nbsp;$value&nbsp;</td>);
        } else {
            $xhtml .= qq (<td class="std_button_up">&nbsp;$value&nbsp;</td>);
        }
    }
    else {
        $xhtml .= qq (<td></td>);
    }        

    return $xhtml;
}

sub stats_cell
{
    # Niels Larsen, November 2005.

    # Displays the content of a "cell" of the table of taxonomy groups
    # and data columns. Three flags determine how the cell is shown: 
    # with numbers abbreviated or not, to include backgroud highlight
    # or not, and whether to put an expansion button or not. 

    my ( $node,        # Node structure
         $cell,
         $colndx,      # Column index position
         ) = @_;

    # Returns an xhtml string.

    my ( $xhtml, $count, $sum_count, $style, $status, $links, $link, 
         $class, $key, $node_id, $expanded_node, $expanded_data, $js_data,
         $js_node, $data_button, $sum_str,
         $abbreviate, $css, $css_node, $css_data, $request, $alt_title );

    $sum_count = $cell->sum_count || $cell->value;

    if ( defined $sum_count )
    {
        $node_id = &Taxonomy::Nodes::get_id( $node );

        $count = $cell->count || 0;
        $request = $cell->request;
        $alt_title = $cell->datatype || "";
        
        $expanded_node = $cell->expanded || "";
        $expanded_data = $cell->expanded_data || "";

        $css = $cell->css || "";

        if ( $cell->abbreviate ) {
            $sum_str = &Common::Util::abbreviate_number( $sum_count );
        } else {
            $sum_str = $sum_count;
        }
        
        $style = $cell->style || "";
        
        if ( $count > 0 )
        {
            if ( $expanded_data ) {
                $css_data = "light_grey_button_down";
                $js_data = "close_data";
            } else {
                $css_data = "light_grey_button_up";
                $js_data = "expand_data";
            }
            
            if ( $count > 1 ) {
                $data_button = qq (<td class="$css_data"><a href="javascript:$js_data($node_id,$colndx)">$count</a></td>);
            }
            else
            {
                $link = qq (<a href="javascript:$request">)
                      . qq (<img border="0" src="$Common::Config::img_url/report.gif" alt="$alt_title" /></a>);
                
                $data_button = qq (<td class="bullet_link">$link</td>);
            }
        }

        if ( &Taxonomy::Nodes::is_leaf( $node ) )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>> LEAF NODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $count > 0 )
            {
                if ( $count > 1 )
                {
                    if ( $cell->data_ids )
                    {
                        $xhtml .= qq (<td align="right"><table cellpadding="0" cellspacing="0" border="0"><tr>)
                                . qq ($data_button)
                                . qq (</tr></table></td>);
                    }
                    else
                    {
                        if ( $style ) {
                            $xhtml .= qq (<td class="std_button_up" style="$style">$sum_str</td>);
                        } else {
                            $xhtml .= qq (<td class="std_button_up">$sum_str</td>);
                        }
                    }
                }
                else {
                    $xhtml .= $data_button;
                }
            }
            else {
                $xhtml .= qq (<td></td>);
            }
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>> INTERNAL NODE <<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $sum_count <= 300 )
            {
                # ---- Clickable,

                if ( $expanded_node ) {
                    $css_node = $css ."_down";
                    $js_node = "collapse_node";
                } else {
                    $css_node = $css ."_up";
                    $js_node = "expand_node";
                }

                if ( $data_button )
                {
                    if ( $sum_count > $count )
                    {
                        $xhtml .= qq (<td align="right"><table cellpadding="0" cellspacing="0" border="0"><tr>)
                            . qq (<td class="$css_node"><a href="javascript:$js_node($node_id,$colndx)">$sum_str</a></td>)
                            . qq ($data_button</tr></table></td>);
                    }
                    else
                    {
                        $xhtml .= qq (<td align="right"><table cellpadding="0" cellspacing="0" border="0"><tr>)
                            . qq ($data_button</tr></table></td>);
                    }
                }
                else {
                    $xhtml .= qq (<td class="$css_node"><a href="javascript:$js_node($node_id,$colndx)">$sum_str</a></td>);
                }
            }
            else
            {
                # ---- Non-clickable,

                if ( $style ) {
                    $xhtml .= qq (<td class="std_button_up" style="$style">$sum_str</td>);
                } else {
                    $xhtml .= qq (<td class="std_button_up">$sum_str</td>);
                }                        
            }
        }
    }
    else
    {
        $xhtml .= qq (<td></td>);
    }
    
    return $xhtml;
}

sub user_icon
{
    # Niels Larsen, December 2005.
    
    # Explain

    # Returns an xhtml string. 

    my ( $args );

    $args = {
        "name" => "tax_user_menu",
        "title" => "User menu",
        "description" => qq (Shows a menu with user uploads, selections or results.),
        "icon" => "sys_account.png",
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
    };

    return &Common::Widgets::menu_icon( $args );
}

1;

__END__

sub selections_icon
{
    # Niels Larsen, February 2004.
    
    # Explain

    # Returns an xhtml string. 

    my ( $icon, $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $icon = "$Common::Config::img_url/sys_selections.png";

    $key = "tax_selections_menu";

    $title = "Selections";

    $text = qq (Shows a menu with user selections.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#336699";

    $xhtml = &Common::Widgets::selections_icon( $icon, $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub selections_menu
{
    # Niels Larsen, November 2005.

    # Generates a menu with the selections that where the user can overlay data as columns. The menu 
    # includes data that are in the system and colored dividers separate the 
    # different kinds of options. An asterisk indicates options selected. 

    my ( $menu,        # Menu object
         $columns,     # Columns header object
         ) = @_;

    # Returns an xhtml string. 

    my ( @ids, $xhtml, $name );

    $menu->add_dividers;

    $name = $menu->name;

    if ( $columns )
    {
        @ids = @{ $columns->match_options_ids( "name" => $name ) };
        $menu->select_options( \@ids );
    }

    $menu->onchange( "javascript:handle_menu(this.form.$name,'handle_$name')" );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

sub go_link_cell
{
    # Niels Larsen, February 2005.

    # Creates the content of a link cell, where the link leads to
    # another viewer. 
    
    my ( $id,         # Node id
         $valndx,
         ) = @_;

    # Returns an xhtml string. 

    return "<td></td>" if $valndx > 0;

    my ( $xhtml, $link );
    
    $link = qq (<a class="bullet_link" href="javascript:go_projection('go_terms_usum',$id)">)
          . qq (<img src="$Common::Config::img_url/go_bullet.gif" border="0" alt="GO link" /></a>);

    $xhtml .= qq (<td class="bullet_link">$link</td>);
    
    return $xhtml;
}

sub distrib_cell
{
    my ( $node,
         $index,
          ) = @_;

    my ( $value, $value_sum, $ramp, $counts, @tuples, $xhtml, $bgcolor, $i );

    $value = $node->{"column_values"}->[ $index ]->[0];
    $value_sum = $node->{"column_values"}->[ $index ]->[1];

    $ramp = &Common::Util::color_ramp( "#ffffff", "#336699", 9 );
        
    if ( $value_sum )
    {
        if ( $value_sum =~ /^\[/ )
        {
            $counts = eval $value_sum;
            @tuples = ();
            
            for ( $i = 6; $i <= 14; $i++ )
            {
                push @tuples, [ $i-6, $counts->[$i] ] if $counts->[$i] > 0;
            }
            
            $xhtml .= qq (<td class="distrib_node">) . &Common::Widgets::summary_bar( \@tuples, 50, 15, $ramp ) . qq (</td>);
        }
        else
        {
            $xhtml .= qq (<td>$value</td>);
        }
    }
    elsif ( $value )
    {
        $ramp = &Common::Util::color_ramp( "#ffffff", "#336699", 12 );
        $bgcolor = $ramp->[ int ( $value / 5 ) - 4 ];
        
        $value = sprintf "%.1f", $value;
        $xhtml .= qq (<td class="sand_button_down" style="background-color: $bgcolor; text-align: center;">$value</td>);
    }
    else
    {
        $xhtml .= qq (<td></td>);
    }

    return $xhtml;
}

sub results_menu
{
    # Niels Larsen, December 2005.

    # Generates a menu of selections and results of comparisons. Colored dividers 
    # separate selections from uploads or other user inputs. An asterisk indicates
    # options selected. Results are shown as columns added to the left of the 
    # hierarchy. 

    my ( $sid,        # Session id
         $display,    # Display structure - OPTIONAL
         $menu,       # Results menu - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $ids, $xhtml, $name, $option );

    if ( not defined $menu ) {
        $menu = Taxonomy::Menus->results_menu( $sid );
    }

    $name = $menu->name;

    if ( defined $display ) {
        $ids = $display->columns->match_options_ids( "name" => "tax_results_menu" );
    } else {
        $ids = [];
    }

    foreach $option ( $menu->options )
    {
        $option->title( "(". $option->id .") ". $option->coltext ." - ". $option->title );
    }

    $menu->select_options( $ids );

    $menu->onchange( "javascript:handle_menu(this.form.$name,'handle_$name')" );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

sub uploads_menu
{
    # Niels Larsen, October 2005.

    # Generates a menu where the user can overlay data as columns. The menu 
    # includes data that are in the system and colored dividers separate the 
    # different kinds of options. An asterisk indicates options selected. 

    my ( $sid,        # Session id
         $columns,    # Columns header object
         ) = @_;

    # Returns an xhtml string. 

    my ( $ids, $menu, $xhtml, $name );

    $menu = Taxonomy::Menus->uploads_menu( $sid );
    $name = $menu->name;

    $ids = $columns->match_options_ids( "name" => $name );

    $menu->select_options( $ids );

    $menu->onchange( "javascript:handle_menu(this.form.$name,'handle_$name')" );
    $menu->css( "grey_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu );
    
    return $xhtml;
}

sub sims_cell_prev
{
    # Niels Larsen, February 2005.

    my ( $node,
         $colndx,
          ) = @_;

    my ( $distrib, $ramp, $xhtml, $bgcolor, $i, @counts, $count, @tuples );

    $distrib = $node->{"cells"}->[$colndx]->{"distrib"} || "";

    if ( not $distrib ) {
        return qq (<td></td>);
    }

    $ramp = &Common::Util::color_ramp( "#bbbbbb", "#ffffff", 21 );

    $distrib = eval $distrib;
    @counts = grep { $_ > 0 } @{ $distrib };

    if ( scalar @counts > 1 )
    {
        for ( $i = 0; $i <= $#{ $distrib }; $i++ )
        {
            push @tuples, [ $i, $distrib->[$i] ] if $distrib->[$i] > 0;
        }

        $xhtml = qq (<td class="distrib_node">) . &Common::Widgets::summary_bar( \@tuples, 45, 15, $ramp ) . qq (</td>);
    }
    elsif ( scalar @counts == 1 )
    {
        $count = $counts[0];

        for ( $i = 0; $i <= $#{ $distrib }; $i++ )
        {
            if ( $distrib->[$i] == $count ) 
            {
                $bgcolor = $ramp->[$i];
                last;
            }
        }

        $count = sprintf "%.2f", $count;
        $xhtml = qq (<td class="grey_button_down" style="background-color: $bgcolor; text-align: center;">$count</td>);
    }
    else
    {
        $xhtml = qq (<td></td>);
    }

    return $xhtml;
}

sub rna_cell
{
    # RETIRED - stats_cell accomodates

    # Niels Larsen, March 2004.

    # Displays the content of a rna "cell" of the table of taxonomy groups
    # and data columns. 

    my ( $node,         # Node structure
         $cell,
         $colndx,       # Column index position
         $valndx,       # Extra rows index position
         ) = @_;

    # Returns an xhtml string.
 
    my ( $xhtml, $value, $sum_count, $style, $link, $node_id, $expanded, 
         $css, $values, $cgi_url );

    $node_id = &Taxonomy::Nodes::get_id( $node );
    
    $sum_count = $cell->sum_count;
    $expanded = $cell->expanded || "";
    $values = $cell->values || [];

    $cgi_url = $Common::Config::cgi_url;

    if ( defined $sum_count )
    {
        if ( $sum_count <= 300 )
        {
            if ( $expanded )
            {
                if ( &Taxonomy::Nodes::is_leaf( $node ) or $valndx > 0 )
                {
                    if ( @{ $values } and $valndx < @{ $values } )
                    {
                        $xhtml .= qq (<td class="bullet_link">)
                                . qq (&nbsp;<a href="javascript:rna_report('$values->[ $valndx ]','$cgi_url')">)
                                . qq (<img border="0" src="$Common::Config::img_url/report.gif" alt="RNA molecules" /></a>)
                                . qq (&nbsp;</td>);
                    }
                    else {
                        $xhtml .= qq (<td></td>);
                    }
                }
                else
                {
                    $xhtml .= qq (<td class="green_button_down">);

                    if ( @{ $values } )
                    {
                        $link = qq (<a href="javascript:rna_report('$values->[ $valndx ]','$cgi_url')">)
                              . qq (<img border="0" src="$Common::Config::img_url/report.gif" alt="RNA molecules" /></a>);

                        $xhtml .= $link;
                    }
                
                    $xhtml .= qq (<a href="javascript:collapse_node($node_id,$colndx)">&nbsp;$sum_count&nbsp;</a></td>);
                }
            }
            else
            {
                if ( @{ $values } == 1 and &Taxonomy::Nodes::is_leaf( $node ) )
                {
                    $xhtml .= qq (<td class="bullet_link">)
                            . qq (&nbsp;<a href="javascript:rna_report('$values->[ $valndx ]','$cgi_url')">)
                            . qq (<img border="0" src="$Common::Config::img_url/report.gif" alt="RNA molecules" /></a>)
                            . qq (&nbsp;</td>);
                }
                elsif ( $sum_count >= 1 )
                {
                    $xhtml .= qq (<td class="green_button_up">)
                            . qq (<a href="javascript:expand_node($node_id,$colndx)">&nbsp;$sum_count&nbsp;</a>)
                            . qq (</td>);
                }
                else {
                    $xhtml .= qq (<td></td>);
                }
            }
        }
        else
        {
            if ( $cell->abbreviate )
            {
                $sum_count = &Common::Util::abbreviate_number( $sum_count );
            }

            $css = $cell->css || "std_button_up";
            $style = $cell->style;
            
            if ( $style ) {
                $xhtml = qq (<td class="$css" style="$style">&nbsp;$sum_count&nbsp;</td>);
            } else {
                $xhtml = qq (<td class="$css">&nbsp;$sum_count&nbsp;</td>);
            }
        }
    }
    else
    {
        $xhtml .= qq (<td></td>);
    }
    
    return $xhtml;
}


sub rna_cell_prev
{
    # Niels Larsen, March 2004.

    # Displays the content of a rna "cell" of the table of taxonomy groups
    # and data columns. 

    my ( $node,         # Node structure
         $colndx,       # Column index position
         $valndx,       # Extra rows index position
         ) = @_;

    # Returns an xhtml string.
 
    my ( $xhtml, $value, $sum_count, $count, $style, $status, $links, $link, 
         $key, $cell, $node_id, $expanded, $abbreviate, $css, $class, $values,
         $cgi_url );

    $node_id = &Taxonomy::Nodes::get_id( $node );
    
    $cell = $node->{"cells"}->[ $colndx ];

    $sum_count = $cell->{"sum_count"};
    
    $style = $cell->{"style"} || "";
    $expanded = $cell->{"expanded"} || "";
    $abbreviate = $cell->{"abbreviate"} || "";
    $css = $cell->{"css"} || "";

    if ( exists $cell->{"values"} ) {
        $values = $cell->{"values"};
    } else {
        $values = [];
    }        

    $cgi_url = $Common::Config::cgi_url;

    if ( defined $sum_count )
    {
        if ( $sum_count <= 300 )
        {
            if ( &Taxonomy::Nodes::is_leaf( $node ) or $valndx > 0 )
            {
                if ( @{ $values } and $valndx < @{ $values } )
                {
                    $link = qq (<a href="javascript:rna_report('$values->[ $valndx ]','$cgi_url')">)
                          . qq (<img border="0" src="$Common::Config::img_url/report.gif" alt="RNA molecules" /></a>);

                    $xhtml .= qq (<td class="bullet_link">&nbsp;$link&nbsp;</td>);
                }
                else {
                    $xhtml .= qq (<td></td>);
                }
            }
            else
            {
                if ( $expanded ) {
                    $xhtml .= qq (<td class="green_button_down">);
                } else {
                    $xhtml .= qq (<td class="green_button_up">);
                }

                if ( @{ $values } )
                {
                    $link = qq (<a href="javascript:rna_report('$values->[ $valndx ]','$cgi_url')">)
                          . qq (<img border="0" src="$Common::Config::img_url/report.gif" alt="RNA molecules" /></a>);

                    $xhtml .= $link;
                }
                
                if ( $expanded ) {
                    $xhtml .= qq (<a href="javascript:collapse_node($node_id,$colndx)">&nbsp;$sum_count&nbsp;</a></td>);
                } else {
                    $xhtml .= qq (<a href="javascript:expand_node($node_id,$colndx)">&nbsp;$sum_count&nbsp;</a></td>);
                }
            }
        }
        else
        {
            if ( $abbreviate ) {
                $sum_count = &Common::Util::abbreviate_number( $sum_count );
            }

            $class = $css || "std_button_up";
            
            if ( $style ) {
                $xhtml = qq (<td class="$class" style="$style">&nbsp;$sum_count&nbsp;</td>);
            } else {
                $xhtml = qq (<td class="$class">&nbsp;$sum_count&nbsp;</td>);
            }
        }
    }
    else
    {
        $xhtml .= qq (<td></td>);
    }
    
    return $xhtml;
}
