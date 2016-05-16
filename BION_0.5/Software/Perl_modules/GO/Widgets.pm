package GO::Widgets;     #  -*- perl -*-

# GO related widgets that produce strings of xhtml. They typically
# define strings, styles and images and then invoke the generic 
# equivalent. It is okay to use arguments that are data structures,
# whereas in Common::Widgets the arguments should be simple. 

use strict;
use warnings FATAL => qw ( all );

use POSIX;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &checkbox_cell
                 &checkbox_row
                 &col_headers
                 &control_icon
                 &control_menu
                 &data_icon
                 &data_menu
                 &display_rows
                 &display_col_row
                 &display_node_row
                 &go_report
                 &id_cell
                 &menu_row
                 &parents_menu
                 &report_title
                 &search_window
                 &selection_window
                 &selections_icon
                 &selections_menu
                 &stats_cell
                 &tax_cell
                 &tax_link_cell
                 );

use GO::Menus;

use Common::Config;
use Common::Widgets;
use Common::Messages;
use Common::Names;
use Common::Util;
use Common::DB;
use Common::Menus;
use Common::DAG::Nodes;

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

    my ( @cols, $xhtml, $index, $flag );

    $xhtml = qq (<table cellpadding="0" cellspacing="0" height="50"><tr>);
    
    if ( $state->{"go_save_rows_button"} )
    {
        $xhtml .= qq (<td valign="middle">)
                   . &Common::Widgets::save_selection_button( $sid, "go", "Save terms", '#ffffcc','#cc6633')
                   . "</td>";
        $flag = 1;
    }

    if ( $state->{"go_delete_rows_button"} and defined $state->{"go_selections_menu"} )
    {
         $index = $state->{"go_selections_menu"};
        
         $xhtml .= qq (<td valign="middle">)
                   . &Common::Widgets::delete_selection_button( $sid, $index, '#ffffcc','#cc6633' ) 
                    . "</td>";
         $flag = 1;
    }

    if ( $state->{"go_delete_cols_button"} )
    {
        $xhtml .= qq (<td valign="middle">)
                   . &Common::Widgets::delete_columns_button( $sid, '#ffffcc','#cc6633' ) 
                   . "</td>";

        $flag = 1;
    }

    if ( $state->{"go_compare_cols_button"} )
    {
         if ( @cols = grep { $_->{"type"} eq "taxonomy" } @{ $display->{"headers"} } 
              and scalar @cols >= 2 )
         {
             $xhtml .= qq (<td valign="middle">)
                    . &Common::Widgets::differences_button( $sid, "taxonomy", '#ffffcc','#336699' ) 
                    . "</td>";
         }

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

    if ( $cell->{"value"} ) {
        $xhtml .= qq (<td>&nbsp;<input type="checkbox" name="go_row_ids" value="$id" class="checkbox" checked />&nbsp;</td>);
    } else {
        $xhtml .= qq (<td>&nbsp;<input type="checkbox" name="go_row_ids" value="$id" class="checkbox" />&nbsp;</td>);
    }
    
    return $xhtml;
}

sub control_icon
{
    # Niels Larsen, February 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the GO control menu. 

    # Returns an xhtml string. 

    my ( $icon, $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $icon = "$Common::Config::img_url/sys_menu.gif";

    $key = "go_control_menu";

    $title = "Control menu";

    $text = qq (Shows a menu with options for selections, column deletions and other actions.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#cc6633";

    $xhtml = &Common::Widgets::control_icon( $icon, $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub control_menu
{
    # Niels Larsen, February 2004.

    # Generates a menu where the user can activate select columns etc. 

    my ( $ids,              # Columns being displayed
         $button,           # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    my ( $items, $item, $key, $text, $fgcolor, $bgcolor, $xhtml, 
         $icon_xhtml, $title, $action );

    $button = 1 if not defined $button;

    $items = &GO::Menus::control_items();
    $items = &Common::Widgets::show_items_selected( $items, $ids );

    $action = "javascript:handle_menu(this.form.go_control_menu,'handle_go_control_menu')";

    $xhtml = &Common::Widgets::select_menu( "go_control_menu", $items, $items->[0]->{"id"}, 
                                            "grey_menu", $action );
    
    if ( $button )
    {
        $key = "go_control_menu";
        
        $title = "Close control menu";
        
        $text = qq (Iconifies the control menu.);
        
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

sub data_icon
{
    # Niels Larsen, April 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the GO data menu. 

    # Returns an xhtml string. 

    my ( $icon, $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $icon = "$Common::Config::img_url/sys_data_book.png";

    $key = "go_data_menu";

    $title = "Data menu";

    $text = qq (Shows a menu with data that can be added to the tree view.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#cc6633";

    $xhtml = &Common::Widgets::data_icon( $icon, $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub data_menu
{
    # Niels Larsen, April 2004.

    # Generates a menu with names of GO statistics options. When a menu option 
    # is chosen the "go_data_menu" parameter is set to the value of the 
    # index of the menu option: the first returns 0, the next 1 and so on. By
    # default a cancel button is attached. 

    my ( $sid,         # Session id 
         $headers,     # Columns being displayed - OPTIONAL
         $button,      # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    my ( $groups, $items, $item, $icon_xhtml, $key, $title, $text, $ids,
         $fgcolor, $bgcolor, $xhtml, $action );
    
    $button = 1 if not defined $button;

    if ( @{ $items } = grep { $_->{"menu"} eq "go_data_menu" } @{ $headers } )
    {
        $ids = [ map { $_->{"id"} } @{ $items } ];
    }
    else {
        $ids = [];
    }
    
    $groups = [ "functions", "protein", "organisms", "genes" ];

    $items = &GO::Menus::data_items( $sid, $groups );
    $items = &Common::Widgets::show_items_selected( $items, $ids );
    
    foreach $item ( @{ $items } )
    {
        if ( $item->{"key"} eq "selections" or $item->{"key"} eq "uploads" )
        {
            $item->{"text"} .= qq (&nbsp;&nbsp;&nbsp;&rsaquo;&rsaquo;&rsaquo;);
        }
    }

    $action = "javascript:handle_menu(this.form.go_data_menu,'handle_go_data_menu')";
    
    $xhtml = &Common::Widgets::select_menu( "go_data_menu", $items, $items->[0]->{"id"}, 
                                            "grey_menu", $action );

    if ( $button )
    {
        $key = "go_data_menu";
        
        $title = "Close data menu";
        
        $text = qq (Iconifies the data menu.);

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

sub display_rows
{
    # Niels Larsen, August 2003.
    
    # Starting at the top node, follows the node children and creates xhtml for 
    # each taxon, including columns that have been selected. The nodes are indented
    # to relect hierarchy depth. For each taxon the children are sorted by display
    # name. 

    my ( $sid,      # User or session id
         $display,  # Display structure
         $state,    # State hash
         $nid,      # Starting node id
         $nrel,     # Node relation
         $indent,   # Starting indentation level - OPTIONAL 
         ) = @_;

    # Returns a list. 

    my ( $xhtml, $child, $nodes, $node, $cid, $valndx, $valndx_max, $cell, $values,
         @cids, @rels, %rels, $i, $rel );

    $indent = 0 if not defined $indent;

    $nodes = &GO::Display::get_nodes_ref( $display );
    $node = &Common::DAG::Nodes::get_node( $nodes, $nid );

    $valndx = 0;

    $xhtml = "<tr>". &GO::Widgets::display_col_row( $node, $nrel, $valndx )
           . "<td>". &GO::Widgets::display_node_row( $node, $valndx, $indent ) ."</td>"
           . "</tr>\n";

    $valndx_max = $valndx;

    if ( $node->{"cells"} )
    {
        foreach $cell ( @{ $node->{"cells"} } )
        {
            $values = $cell->{"values"} || [];
            $valndx_max = &Common::Util::max( $#{ $values }, $valndx_max );
        }
    }

    if ( $valndx_max > 0 )
    {
        for ( $valndx = 1; $valndx <= $valndx_max; $valndx++ )
        {
            $xhtml .= "<tr>". &GO::Widgets::display_col_row( $node, $nrel, $valndx )
                   . "<td>". &GO::Widgets::display_node_row( $node, $valndx, $indent ) ."</td>"
                   . "</tr>\n";
        }
    }

    $indent += 1;

    @cids = &Common::DAG::Nodes::get_ids_children( $node );
    @rels = &Common::DAG::Nodes::get_rels_children( $node );

    for ( $i = 0; $i < @cids; $i++ )
    {
        $rels{ $cids[$i] } = $rels[$i];
    }

    foreach $child ( sort { $a->{"name"} cmp $b->{"name"} }
                     &Common::DAG::Nodes::get_children_list( $nodes, $nid ) )
    {
        $cid = &Common::DAG::Nodes::get_id( $child );
        $rel = $rels{ $cid };

        $xhtml .= &GO::Widgets::display_rows( $sid, $display, $state, $cid, $rel, $indent );
    }

    return $xhtml;
}

sub display_col_row
{
    # Niels Larsen, February 2005.

    # Creates xhtml for the column cells of a given node. Depending 
    # on the types of the column cells of the node, this routine will
    # invoke different functions to paint them.

    my ( $node,         # Node hash
         $nrel,         # Node relation
         $valndx,
         ) = @_;

    # Returns an xhtml string.

    my ( $cell, $colndx, $type, $key, $abr_flag, $css_flag, $exp_flag, $xhtml, $link,
         $node_id );

    $node_id = &Common::DAG::Nodes::get_id( $node );

    $colndx = 0;
    $xhtml = "";

    foreach $cell ( @{ $node->{"cells"} } )
    {
        $type = $cell->{"type"};
        $key = $cell->{"key"};

        if ( &GO::Display::is_select_item( $cell ) )
        {
            $xhtml .= &GO::Widgets::checkbox_cell( $cell, $node_id, $valndx );
        }
        elsif ( $type eq "functions" )
        {
            if ( $key eq "go_id" )
            {
                $xhtml .= &GO::Widgets::id_cell( $node_id, $nrel, $valndx );
            }
            else
            {
                if ( $key =~ /_tsum|_usum$/ )        {
                    $exp_flag = 1;
                } else {
                    $exp_flag = 0;
                }
                
                $xhtml .= &GO::Widgets::stats_cell( $node, $colndx, $valndx, "orange_button", $exp_flag );
            }
        }
        elsif ( $type eq "dna" or $type eq "genes" )
        {
            $exp_flag = 0;
            $xhtml .= &GO::Widgets::stats_cell( $node, $colndx, $valndx, "grey_button", $exp_flag );
        }
        elsif ( $type eq "organisms" )
        {
            if ( $key eq "tax_link" )
            {
                $xhtml .= &GO::Widgets::tax_link_cell( $node_id, $valndx );
            }
            else
            {
                $xhtml .= &GO::Widgets::stats_cell( $node, $colndx, $valndx, "blue_button", 1 );
            }
        }
        else
        {
            &error( qq (Wrong looking column type -> "$type") );
            exit;
        }

        $colndx += 1;
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

    $node_id = &Common::DAG::Nodes::get_id( $node );

    if ( &Common::DAG::Nodes::is_leaf( $node ) ) {
        $leaf_node = 1;
    } else {
        $leaf_node = 0;
    }

    if ( &Common::DAG::Nodes::get_ids_children( $node ) ) {
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

    $text = &Common::DAG::Nodes::get_key( $node, "text" );
    $name = &Common::DAG::Nodes::get_name( $node );

    if ( $text ) {
        $text = &Common::Names::format_display_name( $text );
    } elsif ( $name ) {
        $text = &Common::Names::format_display_name( $name );
    } else {
        &error( qq (Node "$node_id" has no name or text to display) );
    }

    $alt_name = &Common::DAG::Nodes::get_key( $node, "alt_name" );

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

sub checkbox_row
{
    # Niels Larsen, February 2004.

    # Displays the row of column-checkboxes. This row can include
    # one or more headers for projection columns. 

    my ( $display,     # Display structure
         ) = @_;

    # Returns an xhtml string.

    my ( $headers, $key, $title, $text, $xhtml, $i, $style, 
         $type, $value, $icon_xhtml, $fgcolor, $bgcolor, $request );

    if ( grep { exists $_->{"checked"} } @{ $display->{"headers"} } )
    {
        $headers = $display->{"headers"};

        $xhtml = "";

        $key = "go_col_checkboxes";
        $title = "Delete checkboxes";
        $text = "Deletes the row of column checkboxes";

        $style = "std_col_checkbox";        
        $fgcolor ||= "#ffffcc";
        $bgcolor ||= "#cc6633";

        $icon_xhtml = &Common::Widgets::cancel_icon( $key, $title, $text, $fgcolor, $bgcolor );
        
        for ( $i = 0; $i <= $#{ $headers }; $i++ )
        {
            $type = $headers->[ $i ]->{"type"};
            $value = $headers->[ $i ]->{"checked"};

            if ( $type eq "checkbox" )
            {
                $xhtml .= qq (<td class="$style">$icon_xhtml</td>);
            }
            else
            {
                if ( $value ) {
                    $xhtml .= qq (<td class="$style"><input name="go_col_ids" type="checkbox" value="$i" checked></td>);
                } else {
                    $xhtml .= qq (<td class="$style"><input name="go_col_ids" type="checkbox" value="$i"></td>);
                }
            }
        }

        if ( not grep { $_->{"type"} eq "checkbox" } @{ $headers } )
        {
            $xhtml .= qq (<td><table><tr><td valign="middle" align="center" width="25">$icon_xhtml</td></tr></table></td>);
        }

        return $xhtml;
    }
    else {
        return "";
    }
}

sub col_headers
{
    # Niels Larsen, December 2003.

    # Displays the header row for the GO graph. This row can include
    # one or more headers for projection columns, and always includes
    # a pull-down menu with the parent nodes of the current view. 

    my ( $dbh,
         $display,    # Display structure
         $state,      # State hash
         ) = @_;

    # Returns a string.

    my ( $xhtml, $title, $key, $root_node, $text, $args, $link, $tip, $i,
         $col, $type, $len, $style, $headers, $nodes, $img );

    $headers = $display->{"headers"};
    $nodes = $display->{"nodes"};

    $root_node = $nodes->{ $state->{"go_root_id"} };

    # -------- Optional columns for statistics etc,

    for ( $i = 0; $i <= $#{ $headers }; $i++ )
    {
        $col = $headers->[ $i ];

        $key = $col->{"key"};
        $title = $col->{"col"};
        $len = length $title;

        $text = $col->{"text"} || "";
        $tip = $col->{"tip"} || "";
        $type = $col->{"type"} || "";

        # Set header and tooltip styles,
        
        if ( $type eq "functions" or &GO::Display::is_select_item( $col ) )
        {
            $style = "go_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'#ffffcc',BGCOLOR,'#cc6633',BORDER,3);
        }
        elsif ( $type eq "genomes" or $type eq "dna" or $type eq "genes" )
        {
            $style = "std_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'#FFFFCC',BGCOLOR,'#666666',BORDER,3);
        }
        elsif ( $type eq "organisms" )
        {
            $style = "tax_col_title";
            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$text',FGCOLOR,'#FFFFCC',BGCOLOR,'#336699',BORDER,3);
        }
        else {
            &error( qq (Wrong looking column type -> "$type") );
            exit;
        }

        # Set link,

        if ( $key =~ /link$/ or &GO::Display::is_select_item( $col ) )
        {
            $img = qq (<img src="$Common::Config::img_url/sys_cancel_half.gif" border="0" alt="Cancel button" />);
            $link = qq (<a style="color: #ffffff" href="javascript:delete_column($i)">$img</a>);
        }
        else
        {
            if ( $len <= 2 ) {
                $title = "&nbsp;&nbsp;&nbsp;$title&nbsp;&nbsp;&nbsp;";
            } elsif ( $len <= 3 ) {
                $title = "&nbsp;&nbsp;$title&nbsp;&nbsp;";
            } elsif ( $len <= 4 ) {
                $title = "&nbsp;$title&nbsp;";
            } else {
                &error( qq (Column title longer than 4 characters -> "$title") );
                exit;
            }

            $link = qq (<a style="color: #ffffff" href="javascript:delete_column($i)">$title</a>);
        }
        
        # Add table element,

        $xhtml .= qq (<td class="$style" onmouseover="return overlib('$tip',$args)" onmouseout="return nd();">$link</td>);
    }

    # -------- Select menu that shows parent nodes,

    if ( $root_node->{"parent_ids"} and @{ $root_node->{"parent_ids"} } )
    {
        $xhtml .= "<td>". &GO::Widgets::parents_menu( $dbh, $nodes, $state->{"go_root_id"},
                                                      "go_parents_menu", 1 ) ."</td>";
    }
    
    if ( $xhtml ) {
        return qq (<tr>$xhtml</tr>\n);
    } else {
        return;
    }
}

sub go_report
{
    # Niels Larsen, December 2003.

    # Produces a report page for a single GO entry. 

    my ( $sid,       # Session id 
         $entry,     # GO entry
         ) = @_;

    # Returns a string. 

    my ( $dbh, $xhtml, $title, @matches, $linkstr, $str, $pubstr, $statstr,
         $width, $img, $elem, $text, $menu, @options, $menus, $key );

    $width = 20;
    
    $xhtml = &GO::Widgets::report_title( "Gene Ontology Entry" );

    $xhtml .= qq (<table cellpadding="0" cellspacing="0">\n);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text = &Common::Names::format_display_name( $entry->{"name"} );

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="go_report_title"><tr><td>Description</td></tr></table></td></tr>
<tr><td width="$width"></td><td class="go_report_key">Name</td><td class="go_report_value">$text</td><td width="$width"></td></tr>
);

    foreach $elem ( @{ $entry->{"synonyms"} } )
    {
        $text = &Common::Names::format_display_name( $elem->{"synonym"} );

        $xhtml .= qq (<tr><td width="$width"></td><td class="go_report_key">Synonym</td>)
                . qq (<td class="go_report_value">$text ($elem->{"relation"} synonym)</td><td width="$width"></td></tr>\n);
    }

    if ( $entry->{"description"} )
    {
        $xhtml .= qq (<tr><td width="$width"></td><td class="go_report_key">Description</td>)
                . qq (<td class="go_report_value">$entry->{"description"}</td><td width="$width"></td></tr>);
    }

    if ( $entry->{"comment"} )
    {
        $xhtml .= qq (<tr><td width="$width"></td><td class="go_report_key">Comment</td>)
                . qq (<td class="go_report_value">$entry->{"comment"}</td><td width="$width"></td></tr>);
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> REFERENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text = sprintf "%07i", $entry->{"go_id"};

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="go_report_title"><tr><td>References</td></tr></table></td></tr>
<tr><td width="$width"></td><td class="go_report_key">ID</td><td class="go_report_value">$text</td><td width="$width"></td></tr>
);

    foreach $elem ( sort { $a->{"db_name"} cmp $b->{"db_name"} } @{ $entry->{"reference"} } )
    {
        $xhtml .= qq (<tr><td width="$width"></td><td class="go_report_key">$elem->{"db_name"}</td>)
                . qq (<td class="go_report_value">$elem->{"db_id"}</td><td width="$width"></td></tr>\n);
    }

    foreach $elem ( sort { $a->{"terms_total"} <=> $b->{"terms_total"} } @{ $entry->{"parents"} } )
    {
         $text = &Common::Names::format_display_name( $elem->{"name"} );
         $text .= qq ( (ID $elem->{"go_id"}));
        
         push @options,
        {
            "id" => $elem->{"go_id"}, 
            "text" => $text,
            "class" => "menu_item",
        };
    }
    
    if ( @options )
    {
        unshift @options, 
        {
            "id" => "",
            "text" => "Total ". scalar @options, 
            "class" => "beige_menu",
        };

        $menu = &Common::Widgets::select_menu( "go_parents_menu",      # Element name
                                               \@options,              # List of tuples
                                               $options[0]->{"id"},    # Selected option
                                               "beige_menu",           # Style class 
                                               );
        
        $xhtml .= qq (<tr><td width="$width"></td><td class="go_report_key">Parents</td>)
                . qq (<td class="go_report_value" style="padding-top: 0px; padding-bottom: 0px;)
                . qq (padding-left: 1px;">$menu</td><td width="$width"></td></tr>\n);
    }
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $entry->{"terms_total"} )
    {
        $text = &Common::Util::commify_number( $entry->{"terms_total"} ) . " total";
        $text .= "; " . &Common::Util::commify_number( $entry->{"terms_unique"} ) . " unique.";

        $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="go_report_title"><tr><td>Statistics</td></tr></table></td><td width="$width"></td></tr>
<tr><td width="$width"></td><td class="go_report_key">Terms</td><td class="go_report_value">$text</td><td width="$width"></td></tr>
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> EXTERNAL TERMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $entry->{"external"} } )
    {
        $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="go_report_title"><tr><td>Related non-GO Terms</td></tr></table></td><td width="$width"></td></tr>
);

        foreach $elem ( @{ $entry->{"external"} } )
        {
            $text = qq ($elem->{"ext_name"} (ID $elem->{"ext_id"}));

            push @{ $menus->{ $elem->{"ext_db"} } },
            {
                "id" => $elem->{"ext_id"}, 
                "text" => $text,
                "class" => "menu_item",
            };
        }
        
        foreach $key ( sort keys %{ $menus } )
        {
            @options = @{ $menus->{ $key } };

            unshift @options, 
            {
                "id" => "",
                "text" => "Total ". scalar @options, 
                "class" => "beige_menu",
            };

            $menu = &Common::Widgets::select_menu( "go_parents_menu",                # Element name
                                                   \@options,                        # List of hashes
                                                   $options[0]->{"id"},              # Selected option
                                                   "beige_menu",                      # Style class 
                                                   );
    
            $xhtml .= qq (<tr><td width="$width"></td><td class="go_report_key">$key</td>)
                    . qq (<td class="go_report_value" style="padding-top: 0px; padding-bottom: 0px;)
                    . qq (padding-left: 1px;">$menu</td><td width="$width"></td></tr>\n);
        }
    }


    $xhtml .= "</table>\n";

    $xhtml .= qq (<table width="100%"><tr height="60"><td align="right" valign="bottom">
 <div class="go_report_author">Data from the <strong>Gene Ontology Project</strong></div>
 </td></tr></table>\n);

    return $xhtml;
}

sub id_cell
{
    # Niels Larsen, February 2004.

    # Creates the content of an id column cell. It includes the link 
    # that open up a small GO report, currently without the session id.

    my ( $nid,      # Node id
         $nrel,     # Node relation
         $col_ndx,  # Column index 
         ) = @_;

    # Returns a string. 

    my ( $text, $link, $xhtml );

    $text = sprintf "%07i", $nid;

    if ( $nrel and $nrel eq "%" )    # is-a relation
    {
        $link = qq (<a style="font-weight: normal" href="javascript:go_report('$nid')">&nbsp;$text&nbsp;</a>);
        $xhtml = qq (<td class="light_grey_button_up">$link</td>);
    }
    elsif ( $nrel and $nrel eq "<" )    # part-of relation
    {
        $link = qq (<a style="font-weight: normal" href="javascript:go_report('$nid')">&nbsp;$text&nbsp;</a>);
        $xhtml = qq (<td class="orange_button_up">$link</td>);
    }
    else 
    {
        $link = qq (<a href="javascript:go_report('$nid')">&nbsp;$text&nbsp;</a>);
        $xhtml = qq (<td class="std_button_up">$link</td>);
    }

    return $xhtml;
}

sub menu_row
{
    # Niels Larsen, February 2004.

    # Composes the top row on the page with title and icons. 

    my ( $sid,           # Session ID
         $display,       # Display structure
         $state,         # State hash
         ) = @_;
    
    # Returns an array. 

    my ( $headers, $nodes, $node, $name, $alt_name, $titles, $ids,
         $title, $root_node, @l_widgets, @r_widgets, $xhtml, $items, $item );

    $headers = &GO::Display::get_headers_ref( $display );
    $nodes = &GO::Display::get_nodes_ref( $display );

    # ------ Title box,

    $node = &Common::DAG::Nodes::get_node( $nodes, $state->{"go_root_id"} );

    $name = &Common::DAG::Nodes::get_name( $node );
    $alt_name = &Common::DAG::Nodes::get_alt_name( $node );

    $title = &Common::Names::format_display_name( $name );
    
    if ( $alt_name and length $name <= 30 ) {
        $title .= " ($alt_name)";
    }

    push @l_widgets, &Common::Widgets::title_box( $title, "go_title" );

    # ------ Control menu,

    if ( $state->{"go_control_menu_open"} )
    {
        $ids = [ map { $_->{"id"} } grep { $_->{"menu"} eq "go_control_menu" } @{ $headers } ];
        
        if ( grep { exists $_->{"checked"} and $_->{"checked"} == 1 } @{ $headers } )
        {
            $items = &GO::Menus::control_items();
            $item = ( grep { $_->{"request"} eq "add_checked_row" } @{ $items } )[0];
            push @{ $ids }, $item->{"id"};
        }
        elsif ( grep { exists $_->{"checked"} and $_->{"checked"} == 0 } @{ $headers } )
        {
            $items = &GO::Menus::control_items();
            $item = ( grep { $_->{"request"} eq "add_unchecked_row" } @{ $items } )[0];
            push @{ $ids }, $item->{"id"};
        }

        push @l_widgets, &GO::Widgets::control_menu( $ids );
    }
    else {
        push @l_widgets, &GO::Widgets::control_icon();
    }
    
    # ------ Data menu,

    if ( $state->{"go_data_menu_open"} ) {
        push @l_widgets, &GO::Widgets::data_menu( $sid, $headers );
    } else {
        push @l_widgets, &GO::Widgets::data_icon();
    }
    
    # ------ Terms save/restore menu,

    if ( -r "$Common::Config::ses_dir/$sid/go_selections" ) 
    {
        if ( $state->{"go_selections_menu_open"} ) {
            push @l_widgets, &GO::Widgets::selections_menu( $sid, $state->{"go_terms_title"} );
        }
    }
    
    # ------ Optional organism restore menu,

    if ( -r "$Common::Config::ses_dir/$sid/tax_selections" ) 
    {
        if ( $state->{"tax_selections_menu_open"} )
        {
            require Taxonomy::Widgets;

            $titles = [ map { $_->{"text"} } @{ $headers } ];
            push @l_widgets, &Taxonomy::Widgets::selections_menu( $sid, $titles );
        }
    }

    # ------ Expression data menu,

    if ( $state->{"go_expression_menu_open"} )
    {
        require Expr::Widgets;

        push @l_widgets, &Expr::Widgets::expr_selections_menu( $sid, $headers );
    }
    
    # ------ Search icon,

    push @r_widgets, &Common::Widgets::search_icon( "go", 350, 550, $sid, "#cc6633" );

    # ------ Help button,

    push @r_widgets, &Common::Widgets::help_icon( "go", "", 700, 600, $sid, "#cc6633" );

    # ------ Put everything together as a single row,

    $xhtml = qq (<table><tr><td height="10">&nbsp;</td></tr></table>\n);
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, \@r_widgets );

    return $xhtml;
}

sub parents_menu
{
    # Niels Larsen, December 2003.

    # Generates a pull-down menu where all parents to the current root (as
    # specified by the given state hash) are listed. The parents options
    # are sorted by the number of associated terms.

    my ( $dbh,     # Database handle
         $nodes,   # Nodes hash
         $root_id, # Root node id
         $title,   # Input field name
         $head,    # Add header with count - OPTIONAL, default off
         ) = @_;

    # Returns an xhtml string.

    $title ||= "go_parents_menu";

    my ( $root_node, $name, $p_nodes, $id, $node, $xhtml, @items, 
         @menu_ids, $stats, $count );

    $root_node = &Common::DAG::Nodes::get_node( $nodes, $root_id );
    
    $name = &Common::DAG::Nodes::get_name( $root_node );
    $name = &Common::Names::format_display_name( $name );

    $p_nodes = &Common::DAG::Nodes::get_parents_all( $nodes, $root_node );

    @menu_ids = &Common::DAG::Nodes::get_ids_all( $p_nodes );

    $stats = &GO::DB::get_go_stats( $dbh, [ @menu_ids, $root_id ], "go_terms_tsum" );

    foreach $id ( @menu_ids )
    {
        $node = &Common::DAG::Nodes::get_node( $p_nodes, $id );
        $name = &Common::DAG::Nodes::get_name( $node );
        $name = &Common::Names::format_display_name( $name );
        
        push @items,
        {
            "id" => $id,
            "text" => $name,
            "sum" => $stats->{ $id }->{"sum_count"},
            "class" => "menu_item",
        };
    }

    @items = sort { $a->{"sum"} <=> $b->{"sum"} } @items;

    $count = scalar @items;

    if ( $head )
    {
        unshift @items,
        {
            "id" => "",
            "text" => $count > 1 ? "$count parents" : "$count parent",
            "class" => "grey_menu",
        };
    }
    else 
    {
        $name = &Common::DAG::Nodes::get_name( $root_node );
        $name = &Common::Names::format_display_name( $name );
        
        unshift @items,
        { 
            "id" => $root_id,
            "text" => $name,
            "class" => "grey_menu",
            "sum" => 0,
        };
    }
    
    $xhtml = &Common::Widgets::select_menu( $title,                 # Element name
                                            \@items,              # List of tuples
                                            $items[0]->{"id"},    # Selected item
                                            "grey_menu",            # Style class 
                                            "javascript:handle_parents_menu(this.form.go_parents_menu)" );
    
    return $xhtml;
}

sub report_title
{
    # Niels Larsen, December 2003.
    
    # Creates a small bar with a close button. It is to be used
    # in report windows.

    my ( $text,     # Title text
         ) = @_;

    # Reports an xhtml string.

    my ( $xhtml, $close );

    $close = qq (<img src="$Common::Config::img_url/sys_cancel.gif" border="0" alt="Cancel button" />);

    $xhtml = qq (
<table cellpadding="4" cellspacing="0" width="100%"><tr>
     <td align="left" class="go_report_title_l" width="98%">$text</td>
     <td align="right" class="go_report_title_r" width="1%"><a href="javascript:window.close()">$close</a></td>
</tr></table>

);

    return $xhtml;
}

sub search_window
{
    # Niels Larsen, December 2003.

    # Creates a search page with title bar, close button and a form that 
    # specifies what to search against and how. 

    my ( $sid,   # Session id 
         ) = @_;

    # Returns a string. 

    my ( $state, $title, $title_bar, $xhtml, $dbh, $nodes, $p_nodes,
         $name, $search_text, $search_titles_menu, $root_id,
         $search_target, @target_items, $search_target_menu,
         $search_type, @type_items, $search_type_menu );

    $dbh = &Common::DB::connect();

    # -------- Get state from file,

    $state = &GO::State::restore_state( $sid );

    # -------- Title,

    $name = &GO::DB::get_name_of_id( $dbh, $state->{"go_root_id"} );
    $name = &Common::Names::format_display_name( $name );

    $title = qq (Search "$name");
    $title_bar = &Common::Widgets::popup_bar( $title, "form_bar_text", "form_bar_close" );

    # -------- Initialize search box,

    $search_text = $state->{"go_search_text"} || "";

    $search_text =~ s/^\s*//;
    $search_text =~ s/\s*$//;

    # -------- Search titles,

    $nodes = &GO::DB::get_nodes( $dbh, [ $state->{"go_root_id"} ] );
    $p_nodes = &GO::DB::get_parents( $dbh, $state->{"go_root_id"} );

    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );

    $search_titles_menu = &GO::Widgets::parents_menu( $dbh, $nodes, $state->{"go_root_id"},
                                                      "go_search_id", 0 );

    &Common::DB::disconnect( $dbh );

    # -------- Target select menu,

    $search_target = $state->{"go_search_target"};

    @target_items = &Common::Menus::tuples_to_items([
                                                     [ "ids", "ids" ],
                                                     [ "titles", "titles" ],
                                                     [ "descriptions", "descriptions" ],
                                                     [ "everything", "everything" ],
                                                     ]
                                                    );
    
    $search_target_menu = &Common::Widgets::select_menu( "go_search_target",
                                                         \@target_items,
                                                         $search_target,
                                                         "grey_menu" );
    # -------- Type select menu,

    $search_type = $state->{"go_search_type"};

    @type_items = &Common::Menus::tuples_to_items([
                                                   [ "partial_words", "partial words" ],
                                                   [ "name_beginnings", "name beginnings" ],
                                                   [ "whole_words", "whole words only" ],
                                                   ],
                                                  );

    $search_type_menu = &Common::Widgets::select_menu( "go_search_type",
                                                       \@type_items,
                                                       $search_type,
                                                       "grey_menu" );

    # -------- Page html,

    $xhtml = qq (

<table cellpadding="0" cellspacing="0" width="100%">
<tr><td>
$title_bar
</td></tr>

<tr><td>
<div id="form_content">
<p>
The content in the search box below is used to search against the 
<strong>$name</strong> category or one of its parents. It is possible 
to search against ids, titles 
(with synonyms), the more verbose descriptions or everything at the 
same time. Matches may occur in the middle of names but can be limited
to whole words only, in which case your search word should have three
characters or more. The matching is done case-independently.
</p>
<form name="search_window" target="viewer" action="" method="post">

<input type="hidden" name="session_id" value="$sid" />

<div id="search_box">
<table cellspacing="5">
<tr height="25">
   <td align="right">Search</td>
   <td colspan="3">$search_titles_menu</td>
</tr>
<tr height="25">
   <td align="right">for</td>
   <td colspan="3"><input type="text" size="50" name="go_search_text" value=" $search_text" /></td>
</tr>
<tr height="25">
   <td align="right">against</td>
   <td>$search_target_menu</td>
   <td align="right">while matching</td>
   <td>$search_type_menu</td>
</tr>
<tr>
   <td></td>
   <td height="60"><input type="submit" name="request" value="Search" class="grey_button" /></td>
</tr>
</table>
</div>

</form>
</div>
</td></tr></table>

<script language="JavaScript">

   document.search_window.go_search_text.focus();

</script>
);

    return $xhtml;
}

sub selection_window
{
    # Niels Larsen, February 2004.

    # Creates a save selection page with title bar, close button and a 
    # form that accepts a menu title and a column header for the selection.

    my ( $sid,   # Session id 
         ) = @_;

    # Returns a string. 

    my ( $state, $title, $title_bar, $xhtml );

    # -------- Get state from file,

    $state = &GO::State::restore_state( $sid );

    # -------- Title,

    $title = qq (Save Selection);
    $title_bar = &Common::Widgets::popup_bar( $title, "form_bar_text", "form_bar_close" );

    # -------- Page html,

    $xhtml = qq (

<table cellpadding="0" cellspacing="0" width="100%">
<tr><td>
$title_bar
</td></tr>

<tr><td>
<div id="form_content">
<p>
Saved selections appear by their title in menus and as "projection columns" 
on different pages. Below you can enter the name that should appear in the 
menu and a short abbreviation to be used as column title. 
</p>
<form target="viewer" name="selection_window" action="" method="post">

<input type="hidden" name="page" value="go" />
<input type="hidden" name="viewer" value="go" />
<input type="hidden" name="session_id" value="$sid" />
<input type="hidden" name="request" value="save_terms" />
<input type="hidden" name="go_info_key" value="go_terms_usum" />

<div id="search_box">
<table cellspacing="5">
<tr height="25">
   <td align="right">Menu title&nbsp;&raquo;</td>
   <td colspan="3"><input type="text" size="25" maxlength="25" name="go_info_menu" value="">
</tr>
<tr height="25">
   <td align="right">Column header&nbsp;&raquo;</td>
   <td colspan="3"><input type="text" size="4" maxlength="4" name="go_info_col" value="" /></td>
</tr>
<tr>
   <td></td>
   <td height="60"><input type="submit" value="Save" class="grey_button" /></td>
</tr>
</table>
</div>

</form>
</div>
</td></tr></table>

<script language="JavaScript">

   document.selection_window.go_info_menu.focus();

   opener.document.main.request.value = "";
   opener.document.main.submit();

</script>
);

    return $xhtml;
}

sub selections_icon
{
    # Niels Larsen, February 2004.
    
    # Returns a javascript link that submits the page with a signal to the 
    # server it should show the GO statistics menu. 

    # Returns an xhtml string. 

    my ( $icon, $key, $title, $text, $fgcolor, $bgcolor, $xhtml );

    $icon = "$Common::Config::img_url/sys_folder_red.gif";

    $key = "go_selections_menu";

    $title = "Function selections menu";

    $text = qq (Shows a menu with user selected sets of GO terms or GO term groups.);

    $fgcolor ||= "#ffffcc";
    $bgcolor ||= "#cc6633";

    $xhtml = &Common::Widgets::selections_icon( $icon, $key, $title, $text, $fgcolor, $bgcolor );
    
    return $xhtml;
}

sub selections_menu
{
    # Niels Larsen, December 2003.

    # Generates a menu with select and save options that allow the user
    # to save named sets of functions or function groups to be used later.
    # If sets have been saved, their names appear in the menu. If a set 
    # is chosen, the display becomes the subtree that exactly spans the 
    # subset. 

    my ( $sid,       # Session id
         $titles,    # Titles of items to highlight as selected - OPTIONAL
         $button,    # When true shows cancel button - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    my ( $items, $menu, $key, $text, $fgcolor, $bgcolor, $ids, %titles,
         $xhtml, $icon_xhtml, $idstr, $item, $title, $action );

    $titles = [ $titles ] if not ref $titles;

    $button = 1 if not defined $button;

    $items = &GO::Menus::selections_items( $sid );

    if ( @{ $items } )
    {
        %titles = map { $_, 1 } @{ $titles };
        $ids = [ map { $_->{"id"} } grep { exists $titles{ $_->{"text"} } } @{ $items } ];
    }
    else {
        return;
    }

    $items = &Common::Widgets::show_items_selected( $items, $ids || [] );

    unshift @{ $items },
    {
        "id" => "",
        "type" => "",
        "key" => "",
        "text" => "Function Selections",
        "col" => "",
        "tip" => "",
        "class" => "blue_menu_divider",
        "ids" => [],
    };

    $action = "javascript:handle_menu(this.form.go_selections_menu,'restore_terms_selection')";

    $xhtml = &Common::Widgets::select_menu( "go_selections_menu", $items,
                                            $items->[0]->{"id"}, "grey_menu", $action );
    
    if ( $button )
    {
        $key = "go_selections_menu";
        
        $title = "Close selections menu";
        
        $text = qq (Removes the menu with selected sets of GO terms.);
        
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

sub stats_cell
{
    # Niels Larsen, March 2004.

    # Displays the content of a "cell" of the table of taxonomy groups
    # and data columns. Three flags determine how the cell is shown: 
    # with numbers abbreviated or not, to include backgroud highlight
    # or not, and whether to put an expansion button or not. 

    my ( $node,        # Node structure
         $colndx,      # Column index position
         $valndx,
         $button,      # Button style - OPTIONAL, default "blue_button"
         $exp_flag,    # Expand button flag - OPTIONAL, default 0
         ) = @_;

    # Returns an xhtml string.

    my ( $xhtml, $count, $sum_count, $style, $status, $links, $link, 
         $class, $key, $cell, $node_id, $expanded, $abbreviate, $css );

    return "<td></td>" if $valndx > 0;

    $button = "orange_button" if not defined $button;
    
    $exp_flag = 0 if not defined $exp_flag;

    $node_id = &Common::DAG::Nodes::get_id( $node );
    
    $cell = $node->{"cells"}->[ $colndx ];

    $count = $cell->{"count"};
    $sum_count = $cell->{"sum_count"};
    
    $style = $cell->{"style"} || "";
    $expanded = $cell->{"expanded"} || "";
    $key = $cell->{"key"} || "";
    $abbreviate = $cell->{"abbreviate"} || "";
    $css = $cell->{"css"} || "";

    if ( defined $sum_count )
    {
        if ( $exp_flag and $sum_count <= 300 )
        {
            $link = qq (<a href="javascript:go_report('$node_id')">)
                  . qq (<img border="0" src="$Common::Config::img_url/report.gif" alt="Terms" /></a>);
            
            $links = "";
                    
            if ( &Common::DAG::Nodes::is_leaf( $node ) )
            {
                if ( defined $count )
                {
                    foreach ( 1 .. $count ) { $links .= $link; }
                    
                    $xhtml .= qq (<td class="bullet_link">&nbsp;$links&nbsp;</td>);
                }
                else {
                    $xhtml .= qq (<td></td>);
                }
            }
            else
            {
                if ( $expanded )
                {
                    $class = $button ."_down";
                    $xhtml .= qq (<td class="$class">);
                }
                else
                {
                    $class = $button ."_up";
                    $xhtml .= qq (<td class="$class">);
                }

                if ( $key !~ "go_terms" )
                {
                    if ( defined $count and $count > 0 )
                    {
                        foreach ( 1 .. $count ) {
                            $links .= $link;
                        }
                        
                        $xhtml .= $links;
                    }
                }
                
                if ( $expanded ) {
                    $xhtml .= qq (<a href="javascript:collapse_node($node_id,$colndx)">&nbsp;$sum_count&nbsp;</a></td>);
                } else {
                    $xhtml .= qq (<a href="javascript:expand_node($node_id,$colndx)">&nbsp;$sum_count&nbsp;</a></td>);
                }
            }
        }
        elsif ( $css ) 
        {
            if ( $abbreviate ) {
                $sum_count = &Common::Util::abbreviate_number( $sum_count );
            }
            
            if ( $sum_count ne "0" )
            {
                if ( $style ) {
                    $xhtml = qq (<td class="$css" style="$style">$sum_count&nbsp;</td>);
                } else {
                    $xhtml = qq (<td class="$css">$sum_count&nbsp;</td>);
                }
            }
            else {
                $xhtml = qq (<td></td>);
            }
        }
        else
        {
            if ( $abbreviate ) {
                $sum_count = &Common::Util::abbreviate_number( $sum_count );
            }
            
            if ( $sum_count ne "0" )
            {
                if ( $style ) {
                    $xhtml = qq (<td style="$style">&nbsp;$sum_count&nbsp;</td>);
                } else {
                    $xhtml = qq (<td class="std_button_up">&nbsp;$sum_count&nbsp;</td>);
                }
            }
            else {
                $xhtml = qq (<td></td>);
            }
        }                    
    }
    else
    {
        $xhtml .= qq (<td></td>);
    }
    
    return $xhtml;
}

sub tax_link_cell
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
    
    $link = qq (<a class="bullet_link" href="javascript:tax_projection('go_terms_usum',$id)">)
          . qq (<img src="$Common::Config::img_url/tax_bullet.gif" border="0" alt="Taxonomy link" /></a>);

    $xhtml .= qq (<td class="bullet_link">$link</td>);
    
    return $xhtml;
}

1;

__END__
