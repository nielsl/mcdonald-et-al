package GO::Viewer;     #  -*- perl -*-

# Gene ontology specific viewer and related functions. The main 
# subroutine is the main one, follow the code from there. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use English;
use List::Util;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &action_buttons
                 &add_checkbox_column
                 &add_checkbox_row
                 &add_expression_column
                 &add_ids_column
                 &add_link_column
                 &add_statistics_column
                 &add_taxonomy_column
                 &clear_col_buttons
                 &clear_row_buttons
                 &clear_user_input
                 &close_node
                 &check_column_selections
                 &create_columns
                 &create_display
                 &default_display
                 &delete_columns
                 &expand_node
                 &focus_node
                 &format_page
                 &handle_popup_windows
                 &handle_text_search
                 &main
                 &open_node
                 &restore_display
                 &save_display
                 &save_selection
                 &set_col_button
                 &set_col_styles
                 &set_col_checkbox_values
                 &set_row_checkbox_values
                 &tax_differences
                 &text_search
                 &update_menu_state
                  );

use GO::DB_nodes;
use GO::DB;
use GO::Help;
use GO::State;
use GO::Widgets;
use GO::Menus;
use GO::Display;

use Common::DB;
use Common::File;
use Common::Util;
use Common::Widgets;
use Common::Config;
use Common::Messages;
use Common::Users;
use Common::Menus;
use Common::Names;
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
    
    if ( $state->{"go_save_terms_button"} )
    {
        $xhtml .= qq (<td valign="middle">)
                   . &Common::Widgets::save_selection_button( $sid, "go", "Save terms", '#ffffcc','#cc6633')
                   . "</td>";
        $flag = 1;
    }

    if ( $state->{"go_delete_terms_button"} and defined $state->{"go_selections_menu"} )
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

sub add_checkbox_row
{
    # Niels Larsen, February 2004.
    
    # Sets the "checked" key in all column elements, default 0. This will 
    # cause a row with checkboxes to appear on the page just above the column
    # headers. 

    my ( $display,       # Display structure
         $request,       # Menu options index 
         $value,         # Whether checkboxes are checked - OPTIONAL, default 1
         ) = @_;

    # Returns an updated display structure. 

    my ( $elem, $menu, $info );
    
    foreach $info ( &GO::Menus::control_items() )
    {
        if ( $info->{"request"} eq $request ) 
        {
            $menu = $info->{"text"};
            last;
        }
    }

    if ( not $menu ) 
    {
        &error( qq (Request not found in control menu -> "$request") );
        exit;
    }

    # --------- Defaults,

    if ( defined $value ) {
        $value = 1;
    } else {
        $value = 0;
    }

    foreach $elem ( @{ $display->{"headers"} } )
    {
        $elem->{"checked"} = $value;
    }

    return wantarray ? %{ $display } : $display;
}    

sub add_expression_column
{
    # Niels Larsen, April 2004.
    
    # Adds a expression data statistics column to the left of the tree.
    # If no insert position is given its done immediately next to the tree. 

    my ( $dbh,           # Database handle
         $display,       # Display structure
         $optndx,        # Menu index of option to add 
         $colndx,        # Column index where to insert - OPTIONAL
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $headers, $nodes, $index, $node_ids, $node_id, @match,
         $options, $option, $type, $key, $stats );

    if ( not defined $optndx ) 
    {
        &error( qq (No statistics option index given) );
        exit;
    }

    $headers = $display->{"headers"};
    $nodes = $display->{"nodes"};

    require Expr::Menus;
    $option = &Expr::Menus::expr_selections_items()->[ $optndx ];

    $type = $option->{"type"};    # "expression"
    $key = $option->{"key"};      # the experiment id 

    # If there is already a column with the given experiment then we 
    # dont overwrite it but just return. If not then we set the index
    # to the column just after the last so a column will be added,

    if ( @match = grep { $_->{"type"} eq $type and $_->{"key"} eq $key } @{ $headers } )
    {
        if ( scalar @match == 1 ) {
            return wantarray ? %{ $display } : $display;
        } else {
            &error( qq (More than one checkbox column found) );
            exit;
        }
    }
    else {
        $index = scalar @{ $headers };
    }

    # --------- Get ids of nodes to update,

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    # --------- Set column element,
    
    $headers->[ $index ] = &Storable::dclone( $option );
    
    # --------- Get column statistic,

    $stats = &Expr::DB::get_statistics( $dbh, $node_ids, "go_id,$key" );
    
    # --------- Set values, status and style for nodes,
    
    foreach $node_id ( @{ $node_ids } )
    {
        if ( exists $stats->{ $node_id } ) {
            $nodes->{ $node_id }->{"column_values"}->[ $index ] = $stats->{ $node_id }->{ $key };
        } else {
            $nodes->{ $node_id }->{"column_values"}->[ $index ] = undef;
        }
        
        $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
    }

    $display->{"nodes"} = $nodes;
    $display->{"headers"} = $headers;
    
    return wantarray ? %{ $display } : $display;
}

sub clear_col_buttons
{
    # Niels Larsen, January 2005.

    # Clears the state for column button flags. 

    my ( $state,     # State hash
          ) = @_;

    # Returns a hash.
    
    $state->{"go_delete_cols_button"} = 0;

    return $state;
}

sub clear_row_buttons
{
    # Niels Larsen, January 2005.

    # Clears the state for row button flags. 

    my ( $state,     # State hash
          ) = @_;

    # Returns a hash.
    
    $state->{"go_save_terms_button"} = 0;
    
    return $state;
}

sub clear_user_input
{
    # Niels Larsen, February 2005.

    # Sets the state values that come directly from user input fields
    # to nothing. 

    my ( $state,     # State hash
         ) = @_;

    # Returns a hash.

    $state->{"request"} = "";

    $state->{"go_control_menu"} = "";
    $state->{"go_data_menu"} = "";
    $state->{"go_click_id"} = "";
    $state->{"go_col_index"} = "";
    $state->{"go_col_ids"} = [];
    $state->{"go_row_ids"} = [];

    $state->{"go_info_type"} = "";
    $state->{"go_info_key"} = "";
    $state->{"go_info_menu"} = "";
    $state->{"go_info_col"} = "";
    $state->{"go_info_index"} = "";
    $state->{"go_info_ids"} = [];

    return $state;
}

sub close_node
{
    # Niels Larsen, February 2005.

    # Does not fetch anything from the database but simply amputates
    # the nodes in memory,

    my ( $display,        # Display structure
         $root_id,        # Top node of deleted tree
         $click_id,       # Subtree top node ID
         ) = @_;

    # Returns an updated display.

    my ( $nodes, $node, $headers, $i );

    $headers = &GO::Display::get_headers_ref( $display );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $nodes = &Common::DAG::Nodes::delete_subtree( $nodes, $root_id, $click_id, 1 );

    for ( $i = 0; $i <= $#{ $headers }; $i++ )
    {
        $node = &Common::DAG::Nodes::get_node( $nodes, $click_id );
        delete $node->{"cells"}->[$i]->{"expanded"};    # TODO
    }
    
    $display = &GO::Display::attach_nodes( $display, $nodes );

    return $display;
}

sub expand_node
{
    # Niels Larsen, January 2005.

    # Let a column button do the expansion of nodes, so only nodes 
    # are visible that have some values in this column. 
    
    my ( $dbh,          # Database handle
         $sid,          # Session id
         $display,      # Display structure
         $state,        # State hash
         ) = @_;
    
    # Returns an updated display structure.

    my ( $headers, $header, $new_nodes, $c_ids, $c_rels, $nodes, $id, $cell,
         $ids, $click_node, $index, $root_id, $click_id );

    $index = $state->{"go_col_index"};
    $root_id = $state->{"go_root_id"};
    $click_id = $state->{"go_click_id"};

    $headers = &GO::Display::get_headers_ref( $display );
    $header = &GO::Display::get_header( $display, $index );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $click_node = &Common::DAG::Nodes::get_node( $nodes, $click_id );

    if ( $header->{"type"} eq "functions" )
    {
        $new_nodes = &GO::DB::expand_go_node( $dbh, $click_id, 9999 );
    }
    elsif ( $header->{"type"} eq "organisms" )
    {
        $new_nodes = &GO::DB::expand_tax_node( $dbh, $header->{"ids"}, $click_id );
    }
    
    $new_nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $new_nodes );
    $new_nodes = &Common::DAG::Nodes::set_ids_children_all( $new_nodes );
    
    $nodes = &Common::DAG::Nodes::delete_subtree( $nodes, $root_id, $click_id, 1 );
    
    $c_ids = &Common::DAG::Nodes::get_ids_children( $new_nodes->{ $click_id } );
    &Common::DAG::Nodes::set_ids_children( $nodes->{ $click_id }, $c_ids );
    
    $c_rels = &Common::DAG::Nodes::get_rels_children( $new_nodes->{ $click_id } );
    &Common::DAG::Nodes::set_rels_children( $nodes->{ $click_id }, $c_rels );
    
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $new_nodes );

    # TODO - remove direct access in the following,

    foreach $id ( @{ &Common::DAG::Nodes::get_ids_subtree( $nodes, $click_id ) } )
    {
        $nodes->{ $id }->{"cells"}->[$index]->{"expanded"} = 1;
    }

    foreach $cell ( @{ $click_node->{"cells"} } ) 
    {
        $cell->{"expanded"} = 0;
    }

    $click_node->{"cells"}->[$index]->{"expanded"} = 1;
    
    $display = &GO::Display::attach_nodes( $display, $nodes );
    $display = &GO::Viewer::create_columns( $dbh, $sid, $display, $click_id );
    
    return $display;
}

sub add_ids_column
{
    # Niels Larsen, April 2004.
    
    # Adds a column of ids to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $display,       # Display structurea
         $header,        # Header hash
         $index,         # Column index where to insert - OPTIONAL
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $headers, $nodes, $ids, $column, $probe );

    $headers = &GO::Display::get_headers_ref( $display );

    if ( not defined $index )
    {
        $probe = { "type" => $header->{"type"}, "key" => $header->{"key"} };

        if ( &GO::Display::exists_header( $headers, $probe ) ) {
            return $display;
        } else {            
            $index = scalar @{ $headers };
        }
    }

    # ------ Get ids of nodes to update,

    $nodes = &GO::Display::get_nodes_ref( $display );

    if ( defined $root_id ) {
        $ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    # ------ Create new column,

    $column = &GO::Display::new_id_column( $ids );

    # ------ Add column to display,

    $display = &GO::Display::set_header( $display, $header, $index );
    $display = &GO::Display::set_column( $display, $column, $index );

    return $display;
}
    
sub add_link_column
{
    # Niels Larsen, March 2004.

    # Adds a column of link buttons. Depending on the "type" and "key"
    # values of the cells, the links may lead to different browsers. 

    my ( $display,     # Display structure
         $header,      # Header hash 
         $index,       # Column insertion position
         $root_id,     # Starting node id
         ) = @_;

    my ( $headers, $nodes, $ids, $probe, $column );

    $headers = &GO::Display::get_headers_ref( $display );

    if ( not defined $index )
    {
        $probe = { "type" => $header->{"type"}, "key" => $header->{"key"} };

        if ( &GO::Display::exists_header( $headers, $probe ) ) {
            return $display;
        } else {            
            $index = scalar @{ $headers };
        }
    }

    # --------- Get ids of nodes to update,

    $nodes = &GO::Display::get_nodes_ref( $display );

    if ( defined $root_id ) {
        $ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    # --------- Create column and add keys,

    $column = &GO::Display::new_tax_link_column( $ids );
    $column = &GO::Display::set_col_attribs( $column, "type", $header->{"type"} );
    $column = &GO::Display::set_col_attribs( $column, "key", $header->{"key"} );

    $display = &GO::Display::set_header( $display, $header, $index );
    $display = &GO::Display::set_column( $display, $column, $index );

    return $display;
}

sub add_checkbox_column
{
    # Niels Larsen, February 2004.
    
    # Adds a column of checkboxes immediately to the left of the tree.

    my ( $display,       # Display structure
         $header,        # Title hash
         $checked,       # Whether checkboxes are checked - OPTIONAL, default 1
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $headers, $probe, $nodes, $i, $ids, $id, $index, $column );

    # --------- Determine insertion position,

    # If there is already a checkbox column then we set $index to that
    # position so that column will be overwritten. If not then we set
    # it to the column just after the last so a column will be added,

    $headers = &GO::Display::get_headers_ref( $display );
    
    for ( $i = 0; $i <= $#{ $headers }; $i++ )
    {
        $probe = &GO::Display::get_header( $display, $i );

        if ( &GO::Display::is_select_item( $probe ) )
        {
            $index = $i;
            last;
        }
    }

    $index = scalar @{ $headers } if not defined $index;

    $display = &GO::Display::set_header( $display, $header, $index );

    # --------- Get ids of nodes to update,

    $nodes = &GO::Display::get_nodes_ref( $display );

    if ( defined $root_id ) {
        $ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }
    
    $column = &GO::Display::new_checkbox_column( $ids, $checked );
    $column = &GO::Display::set_col_attribs( $column, "type", $header->{"type"} );
    $column = &GO::Display::set_col_attribs( $column, "key", $header->{"key"} );

    # --------- Add new column,

    $display = &GO::Display::set_header( $display, $header, $index );
    $display = &GO::Display::set_column( $display, $column, $index );

    return $display;
}

sub add_statistics_column
{
    # Niels Larsen, February 2004.
    
    # Adds a statistics column to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $dbh,           # Database handle
         $display,       # Display structure
         $header,        # Header hash
         $index,         # Column index where to insert - OPTIONAL
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $headers, $nodes, $ids, $id, $stats, $column, 
         $probe, $type, $key );

    $headers = &GO::Display::get_headers_ref( $display );

    $type = $header->{"type"};
    $key = $header->{"key"};

    if ( not defined $index )
    {
        $probe = { "type" => $type, "key" => $key };

        if ( &GO::Display::exists_header( $headers, $probe ) ) {
            return $display;
        } else {            
            $index = scalar @{ $headers };
        }
    }
    
    # --------- Get ids of nodes to update,

    $nodes = &GO::Display::get_nodes_ref( $display );

    if ( defined $root_id ) {
        $ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    # --------- Get statistics column and add keys,

    $stats = &GO::DB::get_go_stats( $dbh, $ids, $key );

    $column = &GO::Display::get_column( $display, $index );
    $column = &GO::Display::set_col_stats( $column, $stats );

    $column = &GO::Display::set_col_attribs( $column, "css", "std_button_up" );
    $column = &GO::Display::set_col_attribs( $column, "type", $header->{"type"} );
    $column = &GO::Display::set_col_attribs( $column, "key", $header->{"key"} );
    $column = &GO::Display::set_col_attribs( $column, "abbreviate", 1 );

    # --------- Add column to display,

    $display = &GO::Display::set_header( $display, $header, $index );
    $display = &GO::Display::set_column( $display, $column, $index );

    return $display;
}

sub add_taxonomy_column
{
    # Niels Larsen, February 2004.
    
    # Adds a column of organism statistics to the left of the tree. If 
    # no insert position is given its done immediately next to the tree. 

    my ( $dbh,           # Database handle
         $sid,           # Session id
         $display,       # Display structure
         $item,          # Menu index or option to add 
         $index,         # Column index where to insert - OPTIONAL
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $headers, $nodes, $node_ids, $node_id, @match, $count, $column,
         $idstr, $items, $sum_count, $sum_ids, $stats, $tax_ids,
         $tax_id, $sql, $ids, @tax_ids, $root_node );

    require Taxonomy::Menus;
    require Taxonomy::DB;

    $headers = &GO::Display::get_headers_ref( $display );
    $nodes = &GO::Display::get_nodes_ref( $display );

    # If there is already a column of the given type and key then we 
    # dont overwrite it but just return. If not then we set the index
    # to the column just after the last so a column will be added,

    $idstr = join ",", @{ $item->{"ids"} };

    if ( not defined $index )
    {
        if ( @match = grep { $_->{"type"} eq $item->{"type"} and 
                                 ( join ",", @{ $_->{"ids"} } ) eq $idstr } @{ $headers } )
        {
            if ( scalar @match == 1 ) {
                return $display;
            } else {
                &error( qq (More than one checkbox column found) );
                exit;
            }
        }
        else {
            $index = scalar @{ $headers };
        }
    }

    # --------- Expand taxonomy ids to a unique set,

    foreach $tax_id ( @{ $item->{"ids"} } )
    {
          push @{ $tax_ids }, &Taxonomy::DB::get_ids_subtree( $dbh, $tax_id );
    }
    
    $tax_ids = &Common::Util::uniqify( $tax_ids );    

    # --------- Get ids of nodes to update and the statistics,

    if ( defined $root_id )
    {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id );
        $stats = &GO::DB::get_tax_stats( $dbh, $tax_ids, $root_id );
    }
    else
    {
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
        $stats = &GO::DB::get_tax_stats( $dbh, $tax_ids );
    }

    # --------- Get statistics column and add keys,
    
    $column = &GO::Display::new_stats_column( $node_ids );

    $column = &GO::Display::get_column( $display, $index );
    $column = &GO::Display::set_col_stats( $column, $stats );
    $column = &GO::Display::set_col_bgramp( $column, "sum_count", "#cccccc", "#ffffff", $root_id );

    $column = &GO::Display::set_col_attribs( $column, "css", "std_button_up" );
    $column = &GO::Display::set_col_attribs( $column, "type", $item->{"type"} );
    $column = &GO::Display::set_col_attribs( $column, "key", $item->{"key"} );
    $column = &GO::Display::set_col_attribs( $column, "abbreviate", 1 );

    # --------- Add column to display,

    $display = &GO::Display::set_header( $display, $item, $index );
    $display = &GO::Display::set_column( $display, $column, $index );

    return $display;
}    



#     # --------- Set column element,

#     delete $item->{"class"};
#     delete $item->{"request"};

#     $item->{"id"} = "";
    
#     $headers->[ $index ] = &Storable::dclone( $item );

#     # --------- Set values, status and style for nodes,
    
#     foreach $node_id ( @{ $node_ids } )
#     {
#         if ( exists $stats->{ $node_id } )
#         {
#             $count = $stats->{ $node_id }->{"count"} || 0;
            
#             $sum_ids = &Common::DAG::Nodes::get_ids_subtree_label( $stats, $node_id, "count" );
#             $sum_ids = &Common::Util::uniqify( $sum_ids );
#             $sum_count = scalar @{ $sum_ids };
            
#             $nodes->{ $node_id }->{"column_values"}->[ $index ] = [ $count, $sum_count ];
#         }
#         else {
#             $nodes->{ $node_id }->{"column_values"}->[ $index ] = [ undef, undef ];
#         }
        
#         $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
#     }
    
#     return wantarray ? %{ $display } : $display;
# }    

#         $root_node = &Common::DAG::Nodes::get_node_root( $nodes );
#         $root_id = &Common::DAG::Nodes::get_id( $root_node );


sub check_column_selections
{
    # Niels Larsen, February 2004.

    # Returns nothing if two or more columns of same type have been
    # selected. Otherwise a printable message string is returned. 

    my ( $display,
         $ids,
         ) = @_;

    # Returns a string or nothing.

    my ( $message, @cols, %types, $types, $i );

    if ( scalar @{ $ids } < 2 )
    {
        $message = [ "Error", "Please select at least two columns" ];
    }
    else
    {
        foreach $i ( @{ $ids } ) {
            push @cols, $display->{"headers"}->[ $i ];
        }

        %types = map { $_->{"type"}, 1 } @cols;
        $types = scalar ( keys %types );

        if ( $types > 1 )
        {
            $message = [ "Error", "Please select columns of the same type" ];
        }
    }

    if ( $message ) {
        return $message;
    } else {
        return;
    }
}

sub create_columns
{
    # Niels Larsen, February 2004.

    # Given a ist of column items, fetches the corresponding data values and 
    # adds them to the display structure. If a root id is given, starts at that
    # node instead of the top node. The column items have the same keys as the 
    # menu items (see GO::Menus module), including "request". The routine 
    # looks at this key and invokes the routine to deal with each type of 
    # request. The requests are defined in the menus (GO::Menus) and in
    # a couple of Javascript submission functions. 

    my ( $dbh,        # Database handle
         $sid,        # Session id
         $display,    # Display structure
         $root_id,    # Root id - OPTIONAL
         ) = @_;

    # Returns an updated display structure.

    my ( $headers, $header, $request, $index );

    $headers = &GO::Display::get_headers_ref( $display );

    $index = 0;
    
    foreach $header ( @{ $headers } )
    {
        $request = $header->{"request"};

        if ( $request eq "add_unchecked_column" )
        {
            $display = &GO::Viewer::add_checkbox_column( $display, $header, undef, $root_id );
        }
        elsif ( $request eq "add_checked_column" )
        {
            $display = &GO::Viewer::add_checkbox_column( $display, $header, "checked", $root_id );
        }
        elsif ( $request eq "add_ids_column" )
        {
            $display = &GO::Viewer::add_ids_column( $display, $header, $index, $root_id );
        }
        elsif ( $request eq "add_statistics_column" )
        {
            $display = &GO::Viewer::add_statistics_column( $dbh, $display, $header, $index, $root_id );
        }
        elsif ( $request eq "add_link_column" )
        {
            $display = &GO::Viewer::add_link_column( $display, $index, $root_id );
        }
        elsif ( $request eq "restore_orgs_selection" )
        {
            $display = &GO::Viewer::add_tax_column( $dbh, $sid, $display, $header, $index, $root_id );
        }
        elsif ( $request ne "restore_terms_selection" )
        {
            &error( qq (Wrong looking request -> "$request") );
            exit;
        }

        $index += 1;
    }

    return wantarray ? %{ $display } : $display;
}    

sub create_display
{
    # Niels Larsen, February 2004.

    # Given a selection, creates display nodes that span the ids given
    # by the selection. We do not change the column part of the display,
    # but create column information. 

    my ( $dbh,       # Database handle
         $sid,       # Session id
         $ids,       # List of ids
         $headers,   # List of column items to attach
         ) = @_;

    # Returns a nodes hash.

    my ( $nodes, $p_nodes, $root_node, $col, $index, $display );

    # Build node skeleton,

    $nodes = &GO::DB::get_nodes( $dbh, $ids );
    $p_nodes = &GO::DB::get_nodes_parents( $dbh, $nodes );
    
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    $display = {};
    $display = &GO::Display::attach_nodes( $display, &Storable::dclone( $nodes ) );
    $display = &GO::Display::attach_headers( $display, $headers );

    $display = &GO::Viewer::create_columns( $dbh, $sid, $display );

    return $display;
}

sub default_display
{
    # Niels Larsen, February 2005.

    # Generates a default display: a one-level deep show of the bacterial
    # families with the total organism counts attached as columns.

    my ( $dbh,         # Database handle
         $sid,         # Session id
         $headers,     # Header list - OPTIONAL
         ) = @_;

    # Returns a display structure.

    my ( $root_id, $depth, $nodes, $p_nodes, $root_node, $display );

    if ( not defined $headers ) {
        $headers = &GO::Menus::create_column_items( $sid );
    }

    $root_id = 3674;
    $depth = 1;

    $nodes = &GO::DB::open_node( $dbh, $root_id, $depth );

    $p_nodes = &GO::DB::get_parents( $dbh, $root_id );
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes, 1 );
    
    $nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $nodes );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );
    
    $display = &GO::Display::attach_nodes( {}, $nodes );
    $display = &GO::Display::attach_headers( $display, $headers );    
    
    $display = &GO::Viewer::create_columns( $dbh, $sid, $display, $root_id );
    
    return $display;
}

sub delete_columns
{
    # Niels Larsen, February 2004.

    # Deletes columns with the indices identical to the given list. 

    my ( $display,       # Display structure
         $indices,       # Column index or indices 
         $root_id,       # Starting node id - OPTIONAL, default top node
         ) = @_;

    # Returns nothing, but updates headers and nodes.

    my ( $nodes, $node_ids, $node_id, %indices, @values, @status, $values,
         $status, $i, $headers, $index );

    if ( not ref $indices ) {
        $indices = [ $indices ];
    }

    $headers = $display->{"headers"};    
    $nodes = $display->{"nodes"};    

    %indices = map { $_*1, 1 } @{ $indices };

    if ( not $root_id )
    {
        $headers = &Common::Menus::delete_items( $headers, $indices );
    }

    # If a starting node id given, use only the nodes in the subtree that
    # starts at that node. If not, set it to the root node and use all 
    # nodes,

    $nodes = $display->{"nodes"};    

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $root_id = &Common::DAG::Nodes::get_node_root( $nodes );
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    foreach $node_id ( @{ $node_ids } )
    {
        @values = ();
        @status = ();

        $values = $nodes->{ $node_id }->{"column_values"};
        $status = $nodes->{ $node_id }->{"column_status"};

        for ( $i = 0; $i <= $#{ $display->{"headers"} }; $i++ )
        {
            if ( not exists $indices{ $i } )
            {
                push @values, $values->[ $i ];
                push @status, $status->[ $i ];
            }
        }

        $nodes->{ $node_id }->{"column_values"} = &Storable::dclone( \@values );
        $nodes->{ $node_id }->{"column_status"} = &Storable::dclone( \@status );
    }
    
    $display->{"headers"} = $headers;
    $display->{"nodes"} = $nodes;

    return wantarray ? %{ $display } : $display;
}

sub focus_node
{
    # Niels Larsen, February 2005.

    # Zooms in on a clicked node by fetching new nodes from database
    # plus deleting everything not belonging to the new root. Preserves
    # the columns that have been selected. 

    my ( $dbh,           # Database handle
         $sid,           # Session id
         $state,         # State hash
         $display,       # Display structure
         ) = @_;

    # Returns an updated display.

    my ( $nodes, $p_nodes, $depth, $root_id );

    $nodes = &GO::Display::get_nodes_ref( $display );

    if ( $state->{"go_root_id"} ) {
        $depth = $nodes->{ $state->{"go_root_id"} }->{"depth"};
    } else {
        &error( "Depth is un-defined" );
    }   

#    &dump( $nodes );
    if ( $state->{"go_click_id"} ) {
#        &dump( $nodes->{ $state->{"go_click_id"} } );
        $root_id = $nodes->{ $state->{"go_click_id"} }->{"go_id"};
    } else {
        &error( "Click id is un-defined" );
    }   

    $nodes = &GO::DB::open_node( $dbh, $root_id, $depth );

    $p_nodes = &GO::DB::get_parents( $dbh, $root_id );
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes, 1 );
    
    $nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $nodes );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );
    
    $display = &GO::Display::attach_nodes( $display, $nodes );

    $display = &GO::Viewer::create_columns( $dbh, $sid, $display, $root_id );

    return $display;
}

sub format_page
{
    # Niels Larsen, January 2005.

    # Composes the page. At the top there is a title plus a row of opened or
    # closed menus, then an optional row of buttons (depends on previous 
    # choices), then the display itself. If a list of messages is given,
    # a panel is shown across the screen with the message. 
   
    my ( $dbh, 
         $sid,            # Session id
         $display,        # Display structure
         $state,          # State hash
         $messages,       # List of messages - OPTIONAL
         ) = @_;

    # Returns an xhtml string.

    my ( $xhtml, $root_id );

    $xhtml = "";

    # At the top of the page there is a row with widgets and pullout 
    # menus, then follows the hierarchy,

    $xhtml .= &GO::Widgets::menu_row( $sid, $display, $state );

    # ------ Display message(s) if any,

    if ( $messages and @{ $messages } )
    {
        $xhtml .= qq (<table><tr><td height="10">&nbsp;</td></tr></table>\n);
        $xhtml .= "\n". &Common::Widgets::message_box( $messages ) ."\n";
    }

    # -------- Optional save and delete button

    $xhtml .= &GO::Viewer::action_buttons( $sid, $state, $display );

    # Each skeleton row is a table row,

    $xhtml .= qq (\n<table border="0" cellspacing="0" cellpadding="0">\n);

    # ------ Optional row with column checkboxes,
    
    $xhtml .= &GO::Widgets::checkbox_row( $display );

    # ------ Optional row with column headers and parents menu,

    $xhtml .= &GO::Widgets::col_headers( $dbh, $display, $state );

    # ------ Display children only if at the root,

    $root_id = $state->{"go_root_id"};

    $xhtml .= &GO::Widgets::display_rows( $sid, $display, $state, $root_id, "%", 0 );
    
    $xhtml .= qq (</table>\n);
    $xhtml .= qq (<table><tr><td height="15">&nbsp;</td></tr></table>\n);

    # ------ Initialize hidden variables,

    # They are needed by the javascript functions in taxonomy.js,

    $xhtml .= qq (
<input type="hidden" name="viewer" value="" />
<input type="hidden" name="page" value="" />
<input type="hidden" name="request" value="" />
<input type="hidden" name="go_click_id" value="" />
<input type="hidden" name="go_info_type" value="" />
<input type="hidden" name="go_info_key" value="" />
<input type="hidden" name="go_info_tip" value="" />
<input type="hidden" name="go_info_col" value="" />
<input type="hidden" name="go_info_menu" value="" />
<input type="hidden" name="go_info_index" value="" />
<input type="hidden" name="go_col_index" value="" />
<input type="hidden" name="go_info_ids" value="" />
<input type="hidden" name="go_col_ids" value="" />
<input type="hidden" name="go_row_ids" value="" />
<input type="hidden" name="go_show_widget" value="" />
<input type="hidden" name="go_hide_widget" value="" />
<input type="hidden" name="tax_info_type" value="" />
<input type="hidden" name="tax_info_key" value="" />
<input type="hidden" name="tax_info_tip" value="" />
<input type="hidden" name="tax_info_ids" value="" />
<input type="hidden" name="tax_request" value="" />
);

    return $xhtml;
}

sub handle_popup_windows
{
    # Niels Larsen, January 2005.

    # Generates popup window xhtml for the help window, the text search
    # window and the save selections window. 

    my ( $dbh,        # Database handle
         $sid,        # Session id
         $state,      # State hash
         $request,    # Request string
         ) = @_;

    # Returns an xhtml string.

    my ( $xhtml, $entry, $types, $title, $nodes, $p_nodes );

    if ( $request eq "help" )
    {
        require GO::Help;

        $xhtml = &GO::Help::general();
            
        $state->{"is_help_page"} = 1;
        $state->{"title"} = "GO Help Page";
    }
    elsif ( $request eq "search_window" )
    {
        $xhtml = &GO::Widgets::search_window( $sid );

        $state->{"is_popup_page"} = 1;
        $state->{"title"} = "GO Search Page";
    }
    elsif ( $request eq "save_selection_window" )
    {
        $xhtml = &GO::Widgets::selection_window( $sid );

        $state->{"is_popup_page"} = 1;
        $state->{"title"} = "GO Save Selection Page";
    }
    elsif ( $request eq "go_report" )
    {
        $entry = &GO::DB::get_entry( $dbh, $state->{"go_report_id"} );
    
        $xhtml = &GO::Widgets::go_report( $sid, $entry );
        
        $state->{"is_popup_page"} = 1;
        $state->{"title"} = "GO Report Page";
    }

    return $xhtml;
}
    
sub handle_text_search
{
    # Niels Larsen, January 2005.

    # Searches the database for matches, starting at the chosen root node.
    # The subtree that exactly spans the matches are used for display. 
    
    my ( $messages,      # List of message tuples
         $dbh,           # Database handle
         $sid,           # Session id
         $display,       # Display structure
         $state,         # State hash
         ) = @_;

    # Returns updated display or adds to messages.

    my ( $root_id, $text, $type, $target, $ids, $count, $count_str, $headers );

    $root_id = $state->{"go_root_id"};
    $text = $state->{"go_search_text"} || "";
    $type = $state->{"go_search_type"};
    $target = $state->{"go_search_target"};

    if ( $text =~ /\w/ ) 
    {
        if ( $target eq "ids" ) {
            $ids = &GO::DB_nodes::match_ids( $dbh, $text, $root_id );
        } else {
            $ids = &GO::DB_nodes::match_text( $dbh, $text, $target, $type, $root_id );
        }

        if ( $ids )
        {
            $count = scalar @{ $ids };
            $count_str = &Common::Util::commify_number( $count );
            
            if ( $count <= 1000 )
            {
                $headers = &GO::Display::get_headers_ref( $display );
                $display = &GO::Viewer::create_display( $dbh, $sid, $ids, $headers );
                
                if ( $target eq "ids" ) {
                    $display = &GO::Display::boldify_ids( $display, $ids, $root_id );
                } else {
                    $display = &GO::Display::boldify_names( $display, $text, $target, $root_id );
                }

                if ( $count == 1 ) {
                    push @{ $messages }, [ "Results", "1 match" ];
                } else {
                    push @{ $messages }, [ "Results", "$count_str matches" ];
                }
            }
            else 
            {
                $text = "There were $count_str matches. That is too many; we set an"
                    . " arbitrary maximum of 1,000 in order to not overload the server."
                    . " If you cannot refine the search criterion, try click on a smaller"
                    . " organism group and search within that.";
                
                push @{ $messages }, [ "Error", $text ];
            }
        }
        else {
            push @{ $messages }, [ "Results", "No matches" ];
        }
    }
    else {
        push @{ $messages }, [ "Error", "Please enter a search word." ];
    }
        
    return $display;
}

            


#             $match_nodes = &GO::Viewer::text_search( $dbh, $state );

#             if ( $match_nodes )
#             {
#                 $display->{"nodes"} = $match_nodes;
                
#                 $display->{"headers"} = [];
#                 $display = &GO::Viewer::create_columns( $dbh, $sid, $display, $state->{"go_root_id"} );
                
#                 &GO::Viewer::save_display( $sid, $display );
                
#                 $root_node = $display->{"nodes"}->{ $state->{"go_root_id"} };
#                 $state->{"go_root_name"} = $root_node->{"name"};
                
#                 $count = scalar @{ &Common::DAG::Nodes::get_ids_all( $match_nodes ) };
#                 push @{ $messages }, [ "Results", "$count matches" ];
#             }
#             else {
#                 push @{ $messages }, [ "Results", "No matches" ];
#             }

#             $state->{"go_click_id"} = "";
#             $state->{"go_terms_title"} = "";


sub main
{
    # Niels Larsen, October 2003 and on.

    # The user interface of a gene ontology graph. The routine first 
    # fetches a session hash where CGI arguments have been saved and 
    # padded with defaults. The routine looks in the session to see 
    # what action to take and updates the display. The display data
    # are kept as a hash where keys are node ids and values are the 
    # fields one would like to see painted on the tree. There are two
    # kinds of queries: overlays, where the current display tree 
    # topology is not changed and searches where the tree becomes 
    # the minimal subtree that exactly spans the results. This 
    # routine returns XHTML as a string. 

    my ( $sid,          # Session id 
         $state,
         ) = @_;

    # Returns a string.
    
    my ( @xhtml, $root_node, $child, $root_id, $dbh, $nodes,
         $p_nodes, $title_text, $hdr_list, %col_keys, $items, $opt_key,
         $request, $message, $sel, $ids, $id, $menu, $options,
         $xhtml, $add_count, $display, $col, $index, $headers, $cols, 
         $infos, $info, $sels, @cols, $opt_index, $i, $type, $item,
         $menu_requests, $state_key, $state_val, $match_nodes, $count,
         @message_list, @messages, $click_id, $page );

    # >>>>>>>>>>>>>>>>>>>>> CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<

    # There must be both a session and a page given. The page is
    # needed because the same viewer will be used for hierarchies
    # from different sources. 

    if ( not $sid ) {
        &error( qq (No session/user ID given) );
    }

    if ( not $state ) {
        &error( qq (Input not defined) );
    }

#     if ( $page )
#     {
#         if ( $page =~ /^go$/i ) {
#             $page = "go";
#         } else {
#             &error( qq (Wrong looking page -> "$page") );
#             exit;
#         }
#     }
#     else {
#         &error( qq (Page not defined) );
#         exit;
#     }        

    # >>>>>>>>>>>>>>>>>>>>>>> LOAD STATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # We store a state hash on file where the CGI parameters, if any, 
    # have been merged in. This state contains instructions to this
    # viewer about what should be shown, if menus are open etc.

    if ( not defined $state ) {
        $state = &GO::State::restore_state( $sid );
    }

    &dump( $state );

    # Add information to state about viewer and page, so the rendering
    # routine (&Common::Widgets::show_page) knows which style sheets to use,

    $state->{"page"} = $page;
    $state->{"viewer"} = "go";
    
    # Set defaults,

    $state->{"request"} ||= "";

    if ( not $state->{"go_click_id"} ) {
        $state->{"go_click_id"} = $state->{"go_root_id"};
    } 

    # >>>>>>>>>>>>>>>>>>>>>>> LOAD DISPLAY <<<<<<<<<<<<<<<<<<<<<<<<<

    # We store the display as a hash with three main keys: "headers",
    # "nodes" and "checkbox_row". The first contains information about
    # the column headers the second holds everything that is node specific
    # and the third remembers column checkboxes. If no display stored, 
    # a default one is created,

    $dbh = &Common::DB::connect();

    $display = &GO::Viewer::restore_display( $dbh, $sid, $state );

    &GO::Viewer::set_row_checkbox_values( $display, $state->{"go_row_ids"} );
    &GO::Viewer::set_col_checkbox_values( $display, $state->{"go_col_ids"} );

    # >>>>>>>>>>>>>>>>>> GET REQUESTS FROM MENUS <<<<<<<<<<<<<<<<<<<<<<<

    # When a menu item is chosen by the user, a key/value pair gets 
    # submitted: menu name/item index. Menus can contain items where
    # different actions are required. Below these are assigned,

    if ( $state->{"request"} eq "handle_go_control_menu" )
    {
        $items = &GO::Menus::control_items();
        $item = &Common::Menus::get_item( $items, $state->{"go_control_menu"} );

        $state->{"request"} = &Common::Menus::get_item_value( $item, "request" );
    }
    elsif ( $state->{"request"} eq "handle_go_data_menu" )
    {
        $items = &GO::Menus::data_items( $sid );
        $item = &Common::Menus::get_item( $items, $state->{"go_data_menu"} );

        $state->{"request"} = &Common::Menus::get_item_value( $item, "request" );
    }

    # >>>>>>>>>>>>>>>>>>>>>> EXECUTE REQUESTS <<<<<<<<<<<<<<<<<<<<<<<<

    # This very long if-then-else tests on the incoming request and acts
    # on it. Some user actions require changes in the tree topology, some 
    # just what is being superimposed on it, or other actions. Currently
    # only one request is allowed at a time, but that would be easy to 
    # change. 

    $request = $state->{"request"};

    if ( $request )
    {
#        $state->{"go_root_name"} = &GO::DB::get_name_of_id( $dbh, $state->{"go_root_id"} );
        $root_id = $state->{"go_click_id"};

#        &dump( $state->{"go_root_id"} );
#        &dump( $state->{"go_click_id"} );
        
        # >>>>>>>>>>>>>>>>>>>>> NORMAL EDITING UPDATES <<<<<<<<<<<<<<<<<<<<<<<<

        # This includes open, close, focusing on sub-categories and different
        # types of expanding by the column pushbuttons,
        
        if ( $request eq "open_node" )
        {
            $display = &GO::Viewer::open_node( $dbh, $sid, $state, $display );
            $display = &GO::Display::set_col_styles( $display, $state->{"go_root_id"} );
        }

        elsif ( $request eq "focus_node" )
        {
            $display = &GO::Viewer::focus_node( $dbh, $sid, $state, $display );
            $display = &GO::Display::set_col_styles( $display, $state->{"go_click_id"} );

#            $root_node = &Common::DAG::Nodes::get_node( $display->{"nodes"}, $click_id );
#            $state->{"go_root_name"} = &Common::DAG::Nodes::get_name( $root_node );

            $state->{"go_root_id"} = $state->{"go_click_id"};
        }

        elsif ( $request eq "close_node" or $request eq "collapse_node" )
        {
            $display = &GO::Viewer::close_node( $display, $state->{"go_root_id"}, $state->{"go_click_id"} );
        }

        elsif ( $request eq "expand_node" )
        {
            $display = &GO::Viewer::expand_node( $dbh, $sid, $display, $state );
            $display = &GO::Display::set_col_styles( $display, $state->{"go_click_id"} );
        }

        # >>>>>>>>>>>>>>>>>>>> MAIN MENUS OPEN STATE <<<<<<<<<<<<<<<<<<<<<<<<

        # We get here when the user clicks to open or close a menu. This 
        # section sets state flags that the display routines understand
        # later,

        elsif ( $request =~ /^show.*menu$/ or $request =~ /hide.*menu$/ )
        {
            $state = &GO::Viewer::update_menu_state( $state, $request );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>> POPUP WINDOWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        elsif ( $request eq "help" or $request eq "search_window" or 
                $request eq "save_selection_window" or $request eq "go_report" )
        {
            $xhtml = &GO::Viewer::handle_popup_windows( $dbh, $sid, $state, $request );

            $state = &GO::Viewer::clear_user_input( $state );
            &GO::State::save_state( $sid, $state );

            &Common::Widgets::show_page( $xhtml, $sid, $state );

            &Common::DB::disconnect( $dbh );
            exit 0;
        }

        # >>>>>>>>>>>>>>>>>>> ADD CHECKBOX COLUMN AND ROW <<<<<<<<<<<<<<<<<<<

        # Here we attach lists to the display structure that the rendering
        # routines below knows how to handle. The $opt_index is the index of
        # each menu item selected, where the menu items come from 
        # GO::Menus::control_items
        
        elsif ( $request eq "add_unchecked_column" )
        {
            $items = &GO::Menus::control_items();
            $item = &Common::Menus::get_item( $items, $state->{"go_control_menu"} );

            $display = &GO::Viewer::add_checkbox_column( $display, $item );
            $state = &GO::Viewer::set_row_button( $state, $item );
        }
        elsif ( $request eq "add_checked_column" ) 
        {
            $items = &GO::Menus::control_items();
            $item = &Common::Menus::get_item( $items, $state->{"go_control_menu"} );

            $display = &GO::Viewer::add_checkbox_column( $display, $item, "checked" );
            $state = &GO::Viewer::set_row_button( $state, $item );
        }
        elsif ( $request eq "add_unchecked_row" ) 
        {
            $headers = &GO::Display::get_headers_ref( $display );

            if ( @{ $headers } ) 
            {
                $display = &GO::Viewer::add_checkbox_row( $display, $request );
                $state = &GO::Viewer::set_col_button( $state, $item );
            }
        }
        elsif ( $request eq "add_checked_row" ) 
        {
            $headers = &GO::Display::get_headers_ref( $display );

            if ( @{ $headers } ) 
            {
                $display = &GO::Viewer::add_checkbox_row( $display, $request, "checked" );
                $state = &GO::Viewer::set_col_button( $state, $item );
            }
        }
        elsif ( $request eq "add_compare_row" ) 
        {
            $display = &GO::Viewer::add_checkbox_row( $display, $request );

            &GO::Viewer::set_row_checkbox_values( $display, $state->{"go_row_ids"} );
            &GO::Viewer::save_display( $sid, $display );

            $state->{"go_compare_cols_button"} = 1;
            $state->{"go_cols_checkboxes"} = 1;
        }

        # >>>>>>>>>>>>>>>>>>>>>> DELETE CHECKBOX ROW <<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "hide_go_col_checkboxes" )
        {
            foreach $col ( @{ $display->{"headers"} } )
            {
                delete $col->{"checked"};
            }

            $state = &GO::Viewer::clear_col_buttons( $state );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> ADD ID COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_ids_column" )
        {
            $items = &GO::Menus::data_items( $sid );
            $item = &Common::Menus::get_item( $items, $state->{"go_data_menu"} );

            $display = &GO::Viewer::add_ids_column( $display, $item, undef, $root_id );
        }

        # >>>>>>>>>>>>>>>>>>>>> ADD STATISTICS COLUMN(S) <<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_statistics_column" )
        {
            $items = &GO::Menus::data_items( $sid );
            $item = &Common::Menus::get_item( $items, $state->{"go_data_menu"} );

            $display = &GO::Viewer::add_statistics_column( $dbh, $display, $item, undef, $root_id );
            $display = &GO::Display::set_col_styles( $display, $root_id );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> DELETE A COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_column" )
        {
            $item = &GO::Display::get_header( $display, $state->{"go_col_index"} );

            &GO::Display::delete_column( $display, $state->{"go_col_index"} );

            if ( &GO::Display::is_select_item( $item ) ) {
                $state = &GO::Viewer::clear_row_buttons( $state );
            }

            if ( not @{ &GO::Display::get_headers_ref( $display ) } ) {
                $state->{"tax_delete_cols_button"} = 0;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>> DELETE SELECTED COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_columns" )
        {
            &GO::Display::delete_columns( $display, $state->{"go_col_ids"} );
            
            if ( not grep { &GO::Display::is_select_item( $_ ) } @{ $display->{"headers"} } ) {
                $state = &GO::Viewer::clear_row_buttons( $state );
            }

            if ( not @{ &GO::Display::get_headers_ref( $display ) } ) {
                $state->{"go_delete_cols_button"} = 0;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>> ADD EXPRESSION COLUMN(S) <<<<<<<<<<<<<<<<<<<<<<<

#         elsif ( $request eq "add_expression_column" )
#         {
#             $opt_index = $state->{"expr_selections_menu"};
#             $display = &GO::Viewer::add_expression_column( $dbh, $display, $opt_index, $root_id );

#             $state->{"expr_selections_menu"} = undef;

#             &GO::Viewer::set_row_checkbox_values( $display, $state->{"go_row_ids"} );
#             &GO::Viewer::set_col_checkbox_values( $display, $state->{"go_col_ids"}, 1 );

#             &GO::Viewer::save_display( $sid, $display );
#         }

        # >>>>>>>>>>>>>>>>>>>>>>> SAVE TERMS SELECTION <<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "save_terms" )
        {
            $item = &GO::Menus::new_item( $state );
            $info->{"ids"} = $state->{"go_row_ids"};

            @messages = &GO::Viewer::save_selection( $sid, $item );

            push @message_list, @messages if @messages;
        }

        # >>>>>>>>>>>>>>>>>>>>>> ADD SAVED TAXONOMY COLUMN <<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "restore_orgs_selection" )
        {
            require Taxonomy::Menus;

            $items = &Taxonomy::Menus::selections_items( $sid );
            $item = &Common::Menus::get_item( $items, $state->{"tax_selections_menu"} );

            $display = &GO::Viewer::add_taxonomy_column( $dbh, $sid, $display, $item, undef, $root_id );
            $display = &GO::Display::set_col_styles( $display, $state->{"go_root_id"} );
        }

        # >>>>>>>>>>>>>>>>>>>>>> ADD TAXONOMY PROJECTION <<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_tax_column" )
        {
            require Taxonomy::Menus;

            $item = &Taxonomy::Menus::new_selection( $dbh, $state );
            $item->{"id"} = 0;

            $display = &GO::Viewer::add_taxonomy_column( $dbh, $sid, $display, $info, undef, $root_id );
            $display = &GO::Display::set_col_styles( $display, $state->{"go_root_id"} );
        }

        # >>>>>>>>>>>>>>>>>>> ADD TAXONOMY LINKS COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_link_column" )
        {
            $items = &GO::Menus::data_items( $sid );
            $item = &Common::Menus::get_item( $items, $state->{"go_data_menu"} );

            $display = &GO::Viewer::add_link_column( $display, $item, undef, $root_id );
        }

        # >>>>>>>>>>>>>>>>>>>>>> DELETE TERMS SELECTION <<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_terms" )
        {
            $index = $state->{"go_info_index"};
            $items = &GO::Display::get_headers_ref( $display );

            $sels = &GO::Menus::delete_selection( $sid, $index );

            if ( $sels )
            {
                $index-- if $index > $#{ $sels };
                $sel = $sels->[ $index ];

                $display = &GO::Viewer::create_display( $dbh, $sid, $sel->{"ids"}, $items );

                $root_node = &Common::DAG::Nodes::get_nodes_ancestor( $display->{"nodes"}, $sel->{"ids"} );
                $state->{"go_root_id"} = &Common::DAG::Nodes::get_id( $root_node );

                $state->{"go_delete_rows_button"} = 1;
                $state->{"go_selections_menu"} = $index;
                $state->{"go_terms_title"} = $sel->{"text"};
            }
            else
            {
                $display = &GO::Viewer::default_display( $dbh, $sid, $items );
                
                $state = &GO::Viewer::clear_col_buttons( $state );
                $state = &GO::Viewer::clear_row_buttons( $state );

                $state->{"go_selections_menu_open"} = 0;
            }
        }

        # >>>>>>>>>>>>>>> RECONSTRUCT DISPLAY FROM SAVED IDS <<<<<<<<<<<<<<<<<

        elsif ( $request eq "restore_terms_selection" )
        {
            $index = $state->{"go_selections_menu"};
            $items = &GO::Display::get_headers_ref( $display );

            $display = &GO::Viewer::create_display( $dbh, $sid, $sel->{"ids"}, $items );

            $sel = &GO::Menus::selections_items( $sid )->[ $index ];
            $root_node = &Common::DAG::Nodes::get_nodes_ancestor( $display->{"nodes"}, $sel->{"ids"} );

            $state->{"go_root_id"} = &Common::DAG::Nodes::get_id( $root_node );
            $state->{"go_delete_rows_button"} = 1;
            $state->{"go_selections_menu"} = $index;
            $state->{"go_terms_title"} = $sel->{"text"};
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> TEXT SEARCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request =~ /^Search$/i )
        {
            # Searches the name field with a word entered by the user,

            $state->{"go_root_id"} = $state->{"go_search_id"};

            $display = &GO::Viewer::handle_text_search( \@message_list, $dbh, $sid, $display, $state );
            $display = &GO::Display::set_col_styles( $display, $state->{"go_root_id"} );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>> SHOW DIFFERENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "compare_columns" )
        {
            $message = &GO::Viewer::check_column_selections( $display, $state->{"go_col_ids"} );

            if ( $message ) {
                push @message_list, $message;
            }
            else 
            {
                $type = $display->{"headers"}->[ $state->{"go_col_ids"}->[0] ]->{"type"};
                
                if ( $type eq "taxonomy" )
                {
                    require Taxonomy::DB;
                    $display = &GO::Viewer::tax_differences( $dbh, $sid, $display, $state );
                }
                else {
                    push @message_list, [ "Error", "Cannot show differences between statistics" ];
                }

                if ( not @{ $display->{"nodes"}->{ $state->{"go_root_id"} }->{"children_ids"} } )
                {
                    push @message_list, [ "Result", "No differences" ];
                }

                &GO::Viewer::save_display( $sid, $display );
            }

            &GO::Viewer::set_col_checkbox_values( $display, $state->{"go_col_ids"}, 1 );
        }

        # >>>>>>>>>>>>>>>>>>>>> ERROR IF WRONG REQUEST <<<<<<<<<<<<<<<<<<<<<<<<

        else
        {
            &error( qq (Wrong looking request -> "$request") );
            exit;
        }

        $state = &GO::Viewer::clear_user_input( $state );

        &GO::State::save_state( $sid, $state );
         &GO::Viewer::save_display( $sid, $display );
#        &dump( $display );
    }

    # >>>>>>>>>>>>>>>>>>>>>>> LAYOUT THE PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # At the top of the page there is a row with widgets and pullout 
    # menus, then follows the skeleton,

    $xhtml = &GO::Viewer::format_page( $dbh, $sid, $display, $state, \@message_list );

    &Common::DB::disconnect( $dbh );

    return $xhtml;
}

sub open_node
{
    # Niels Larsen, February 2005.

    # Opens the node that is clicked on, by digging into the database. 
    # Fills in values for the new rows for whatever columns have been
    # selected. 

    my ( $dbh,         # Database handle
         $sid,         # Session id
         $state,       # State hash
         $display,     # Display structure
         ) = @_;

    # Returns an updated display structure.

    my ( $new_nodes, $nodes, $depth, $p_ids, $p_rels, $root_id, $click_id );

    $nodes = &GO::Display::get_nodes_ref( $display );

    if ( $state->{"go_root_id"} )
    {
        $depth = $nodes->{ $state->{"go_root_id"} }->{"depth"};
        $root_id = $state->{"go_root_id"};
    }
    else {
        &error( "Depth is un-defined" );
        exit;
    }   

    if ( $state->{"go_click_id"} ) {
        $click_id = $nodes->{ $state->{"go_click_id"} }->{"go_id"};
    } else {
        &error( "Click id is un-defined" );
    }   

    $new_nodes = &GO::DB::open_node( $dbh, $click_id, $depth, 1 );
    $new_nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $new_nodes );
    $new_nodes = &Common::DAG::Nodes::set_ids_children_all( $new_nodes );

    $p_ids = &Common::DAG::Nodes::get_ids_parents( $nodes->{ $click_id } );
    &Common::DAG::Nodes::set_ids_parents( $new_nodes->{ $click_id }, $p_ids );
    
    $p_rels = &Common::DAG::Nodes::get_rels_parents( $nodes->{ $click_id } );
    &Common::DAG::Nodes::set_rels_parents( $new_nodes->{ $click_id }, $p_rels );

    $nodes = &Common::DAG::Nodes::delete_subtree( $nodes, $root_id, $click_id, 1 );
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $new_nodes, 1 );

    $display = &GO::Display::attach_nodes( $display, &Storable::dclone( $nodes ) );

    $display = &GO::Viewer::create_columns( $dbh, $sid, $display, $click_id );
    
    return $display;
}

sub restore_display
{
    # Niels Larsen, October 2003.

    # Restores the display tree as a nodes hash fron the file go_display
    # under the user's directory. If this file does not exist then it is
    # created with the default display tree. There are three main keys in 
    # the display structure: "nodes" and "headers".

    my ( $dbh,         # Database handle
         $sid,         # Session ID
         $state,       # State hash
         ) = @_;

    # Returns a hash. 

    my ( $file, $display, $items );

    $file = "$Common::Config::ses_dir/$sid/go_display";

    if ( -r $file )
    {
        # Get diplay previously saved,

        $display = &Common::File::retrieve_file( $file );
    }
    else
    {
        # Create default display,

        &dump( $dbh );
        &dump( $sid );
        $display = &GO::Viewer::default_display( $dbh, $sid );
        $display = &GO::Display::set_col_styles( $display, $state->{"go_root_id"} );

        &Common::File::store_file( $file, $display );

        # Save default GO selections,

        $items = &GO::Menus::selections_items( $sid );
        &GO::Menus::save_selections( $sid, $items );

        # Save default Taxonomy selections,

        require Taxonomy::Menus;

        $items = &Taxonomy::Menus::create_selections_items( $sid );
        &Taxonomy::Menus::save_selections( $sid, $items );
    }

    return wantarray ? %{ $display } : $display;
}

sub save_display
{
    # Niels Larsen, February 2004.

    # Saves the display to the file go_display under the user's directory. 

    my ( $sid,        # Session ID
         $display,    # Display structure
         ) = @_;

    # Returns nothing. 

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/go_display";

    &Common::File::store_file( $file, $display );
#    &Common::File::dump_file( $file, $display );

    return;
}

sub save_selection 
{
    # Niels Larsen, February 2004.

    # Saves an informational hash to a file under the users area. 
    # A text message is returned that tells if the saving went ok.
    
    my ( $sid,     # Session id
         $item,    # Information hash
         $index,   # Insertion index - OPTIONAL
         ) = @_;

    # Returns a string. 

    my ( $list, $len, @messages );

    if ( not defined $item ) 
    {
        &error( qq (No info hash is given) );
        exit;
    }
    
    if ( not $item->{"ids"} or not @{ $item->{"ids"} } ) {
        push @messages, [ "Error", "Please make a selection" ];
    }

    if ( not $item->{"text"} ) {
        push @messages, [ "Error", "Please specify a menu title" ];
    }

    if ( not $item->{"col"} ) {
        push @messages, [ "Error", "Please specify a column title" ];
    }

    if ( not @messages )
    {
        $list = &GO::Menus::add_selection( $sid, $item, $index );
        push @messages, [ "Success", "Selection is saved, and will appear in the function "
                                    ."selections menu (invoked from the Data Menu)." ];
    }

    if ( @messages ) {
        return wantarray ? @messages : \@messages;
    } else { 
        return;
    }
}

sub set_col_button
{
    # Niels Larsen, January 2005.

    # Flips the state settings so the "Delete columns" button is shown.

    my ( $state,      # State hash
         $item,       # Item hash
         ) = @_;

    # Returns an update state.

    my ( $type );

    &GO::Viewer::clear_col_buttons( $state );

    $type = &Common::Menus::get_item_value( $item, "type" );

    $state->{"go_delete_cols_button"} = 1;

    return $state;
}

sub set_col_checkbox_values
{
    # Niels Larsen, February 2004.

    # If there is a checkbox row in the given display, sets the values
    # for each column in a given list of ids and unsets the rest. 

    my ( $display,   # Display hash
         $ids,       # List of node ids
         $value,     # Value to set
         ) = @_;

    # Returns an updated display. 

    $value = 0 if not defined $value;

    my ( $id, $col, %ids, $i );

    %ids = map { $_, 1 } @{ $ids };
    
    for ( $i = 0; $i <= $#{ $display->{"headers"} }; $i++ )
    {
        $col = $display->{"headers"}->[ $i ];
        
        if ( $ids{ $i } ) {
            $col->{"checked"} = $value;
        }
    }
    
    return wantarray ? %{ $display } : $display;
}    

sub set_row_button
{
    # Niels Larsen, January 2005.

    my ( $state,
         $item,
         ) = @_;

    my ( $type );

    &GO::Viewer::clear_row_buttons( $state );

    $type = &Common::Menus::get_item_value( $item, "type" );

    if ( $type eq "save" ) {
        $state->{"go_save_terms_button"} = 1;
    }

    return $state;
}

sub set_row_checkbox_values
{
    # Niels Larsen, February 2004.

    # If there is a checkbox column in the given display, sets the values
    # at the nodes in a given list of ids and unsets the rest. 

    my ( $display,   # Display hash
         $ids,       # List of node ids
         ) = @_;

    # Returns an updated display. 

    my ( $i, $col, %ids, $id, $nodes );

    $nodes = $display->{"nodes"};

    for ( $i = 0; $i <= $#{ $display->{"headers"} }; $i++ )
    {
        $col = $display->{"headers"}->[ $i ];
        
        if ( $col->{"type"} eq "checkbox" )
        {
            %ids = map { $_, 1 } @{ $ids };

            foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
            {
                if ( exists $ids{ $id } ) {
                    $nodes->{ $id }->{"column_values"}->[ $i ] = 1;
                } else {
                    $nodes->{ $id }->{"column_values"}->[ $i ] = 0;
                }
            }
        }
    }

    $display->{"nodes"} = $nodes;   # not necessary 

    return wantarray ? %{ $display } : $display;
}    

sub tax_differences
{
    # Niels Larsen, February 2004.

    # Creates a display that includes only the differences between select
    # columns. 

    my ( $dbh,
         $sid,
         $display,
         $state,
         ) = @_;

    # Returns an updated display.

    my ( $col_ids, $col_id, $col, $tax_ids, $tax_id, $tax_str, $sql, $node_ids, $root_id, 
         $all_ids, $diff_ids, $node_id, $nodes, $p_nodes, $headers );

    $root_id = $state->{"go_root_id"};
    $col_ids = $state->{"go_col_ids"};

    foreach $col_id ( @{ $col_ids } )
    {
        $col = $display->{"headers"}->[ $col_id ];

        $tax_ids = [];

        foreach $tax_id ( @{ $col->{"ids"} } )
        {
            push @{ $tax_ids }, &Taxonomy::DB::get_ids_subtree( $dbh, $tax_id );
        }

        $tax_ids = &Common::Util::uniqify( $tax_ids );
        $tax_str = join ",", @{ $tax_ids };

        $sql = qq (select distinct go_edges.go_id from go_edges natural join go_genes_tax)
             . qq ( where go_edges.parent_id = $root_id and tax_id in ( $tax_str ));

        $node_ids->[ $col_id ] = { map { $_->[0], 1 } &Common::DB::query_array( $dbh, $sql ) };
        
        push @{ $all_ids }, keys %{ $node_ids->[ $col_id ] };
    }

    $all_ids = &Common::Util::uniqify( $all_ids );
    $diff_ids = [ $root_id ];

    foreach $node_id ( @{ $all_ids } )
    {
        foreach $col_id ( @{ $col_ids } )
        {
            if ( not $node_ids->[ $col_id ]->{ $node_id } )
            {
                push @{ $diff_ids }, $node_id;
                last;
            }
        }
    }

    $diff_ids = &Common::Util::uniqify( $diff_ids );
    $nodes = &GO::DB::get_nodes( $dbh, $diff_ids );

    $p_nodes = &GO::DB::get_nodes_parents( $dbh, $nodes );
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    $display->{"nodes"} = $nodes;

    $headers = &Storable::dclone( $display->{"headers"} );
    $display->{"headers"} = [];

    $display = &GO::Viewer::create_columns( $dbh, $sid, $display, $root_id );

    foreach $node_id ( &Common::DAG::Nodes::get_ids_all( $nodes ), $root_id )
    {
        foreach $col_id ( @{ $col_ids } )
        {
            &Common::DAG::Nodes::set_node_col_status( $nodes->{ $node_id }, $col_id, "expanded" );
        }
    }

    return wantarray ? %{ $display } : $display;    
}    

sub text_search
{
    # Niels Larsen, December 2003.

    # Searches the name fields of a given subtree. The search includes either
    # titles (with synonyms), descriptions, external names or all text. The 
    # routine creates a nodes hash that spans all the matches and starts at the 
    # current root node. The empty nodes are included down to one level below
    # the starting node, so one can see which nodes did not match.

    my ( $dbh,      # Database handle
         $state,    # State hash
         ) = @_;

    # Returns a nodes hash.

    my ( $root_id, $root_node, $p_nodes, $nodes, $node, $sql, $id, @desc_ids,
         @ids, @tit_ids, @syn_ids, %ids, $tables, $select, $search_target,
         $search_text, $search_type, $match_name, $match_syn, $match_desc,
         $match_nodes, $id_name_def );

    $id_name_def = "go_id";

    $root_id = $state->{"go_root_id"};

    $search_text = $state->{"go_search_text"};
    $search_type = $state->{"go_search_type"};
    $search_target = $state->{"go_search_target"};

    $root_node = &GO::DB::get_node( $dbh, $root_id );

    if ( $search_target ne "ids" )
    {
        $search_text =~ s/^\s*//;
        $search_text =~ s/\s*$//;
        $search_text = quotemeta $search_text;
    }

    # ---------- prepare search type strings,
    
    if ( $search_type eq "whole_words" )
    {
        $match_name = qq ( match(go_def.name) against ('$search_text'));
        $match_syn = qq ( match(go_synonyms.syn) against ('$search_text'));
        $match_desc = qq ( match(go_def.deftext) against ('$search_text'));
    }
    elsif ( $search_type eq "name_beginnings" )
    {
        $match_name = qq ( go_def.name like '$search_text%');
        $match_syn = qq ( go_synonyms.syn like '$search_text%');
        $match_desc = qq ( go_def.deftext like '$search_text%');
    }
    elsif ( $search_type eq "partial_words" )
    {
        $match_name = qq ( go_def.name like '%$search_text%');
        $match_syn = qq ( go_synonyms.syn like '%$search_text%');
        $match_desc = qq ( go_def.deftext like '%$search_text%');
    }
    else {
        &error( qq (Unknown search type -> "$search_type") );
    }

    # ---------- do the different kinds of searches,

    if ( $search_target eq "ids" )
    {
        @ids = split /[\s,;]+/, $search_text;
        @ids = grep { $_ =~ /^\d+$/ } @ids;
    }
    elsif ( $search_target eq "titles" )
    {
        $tables = qq (go_edges natural join go_def);
        $sql = qq (select go_edges.$id_name_def from $tables where go_edges.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq (go_edges natural join go_synonyms);
        $sql = qq (select go_edges.$id_name_def from $tables where go_edges.parent_id = $root_id and $match_syn);
        @syn_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } ( @tit_ids, @syn_ids );
        @ids = keys %ids;
    }
    elsif ( $search_target eq "descriptions" )
    {
        $tables = qq (go_edges natural join go_def);
        $sql = qq (select go_edges.$id_name_def from $tables where go_edges.parent_id = $root_id and $match_desc);
        @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    }        
    elsif ( $search_target eq "everything" )
    {
        $tables = qq (go_edges natural join go_def);
        $sql = qq (select go_edges.$id_name_def from $tables where go_edges.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq (go_edges natural join go_synonyms);
        $sql = qq (select go_edges.$id_name_def from $tables where go_edges.parent_id = $root_id and $match_syn);
        @syn_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq (go_edges natural join go_def);
        $sql = qq (select go_edges.$id_name_def from $tables where go_edges.parent_id = $root_id and $match_desc);
        @desc_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } ( @tit_ids, @syn_ids, @desc_ids );
        @ids = keys %ids;
    }
    else {
        &error( qq (Unknown search target -> "$search_target") );
    }

    if ( @ids )
    {
        $match_nodes = &GO::DB::get_nodes( $dbh, \@ids );

        if ( $search_target eq "ids" )
        {
            foreach $id ( @ids )
            {
                $node = $match_nodes->{ $id };
                $node->{"name"} = qq (<strong>$node->{"name"}</strong>);
            }
        }
        else
        {
            foreach $id ( @ids )
            {
                $node = $match_nodes->{ $id };
                
                if ( $node->{"name"} =~ /$search_text/i ) {
                    $node->{"name"} = $PREMATCH ."<strong>$MATCH</strong>". $POSTMATCH;
                }
            }
        }
    }

    $nodes = &GO::DB::open_node( $dbh, $root_id, 1 );
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $match_nodes, 1 );

    $p_nodes = &GO::DB::get_nodes_parents( $dbh, $nodes );
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );

    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    if ( $search_target eq "ids" )
    {
        $root_node = &Common::DAG::Nodes::get_nodes_ancestor( $nodes, \@ids );
        $state->{"go_root_id"} = &Common::DAG::Nodes::get_id( $root_node );
    }
    
    return wantarray ? %{ $nodes } : $nodes;
}

sub update_menu_state
{
    # Niels Larsen, January 2005.

    # Sets a state flags about "openness" of a menu. For example,
    # if the user clicks to open the data menu the state key 
    # "tax_data_menu_open" will be set to 1. Then the display
    # routine will show the menu as open. Returns an updated
    # state hash. 

    my ( $state,      # States hash
         $request,    # Request string
         ) = @_;

    # Returns a hash. 

    my ( $requests, $key, $val );

    # This section updates state flags for which menus should be shown.
    # The setting of checkboxes is done in order to preserve checkbox
    # changes since last time they were saved. The hash below is done 
    # to avoid many similar if-then-elses. 
    
    $requests->{"show_go_control_menu"} = [ "go_control_menu_open", 1 ];
    $requests->{"hide_go_control_menu"} = [ "go_control_menu_open", 0 ];
    $requests->{"show_go_data_menu"} = [ "go_data_menu_open", 1 ];
    $requests->{"hide_go_data_menu"} = [ "go_data_menu_open", 0 ];
    $requests->{"show_go_selections_menu"} = [ "go_selections_menu_open", 1 ];
    $requests->{"hide_go_selections_menu"} = [ "go_selections_menu_open", 0 ];
    $requests->{"show_tax_selections_menu"} = [ "tax_selections_menu_open", 1 ];
    $requests->{"hide_tax_selections_menu"} = [ "tax_selections_menu_open", 0 ];
    $requests->{"show_uploads_menu"} = [ "uploads_menu_open", 1 ];
    $requests->{"hide_uploads_menu"} = [ "uploads_menu_open", 0 ];
    
    if ( exists $requests->{ $request } )
    {
        $key = $requests->{ $request }->[0];
        $val = $requests->{ $request }->[1];
        
        $state->{ $key } = $val;
    }

    return wantarray ? %{ $state } : $state;
}

1;

__END__


sub restore_display_prev
{
    # Niels Larsen, October 2003.

    # Restores the display tree as a nodes hash fron the file go_display
    # under the user's directory. If this file does not exist then it is
    # created with the default display tree. There are three main keys in 
    # the display structure: "nodes" and "headers".

    my ( $dbh,         # Database handle
         $sid,         # Session ID
         $state,       # State hash
         ) = @_;

    # Returns a hash. 

    my ( $file, $nodes, $parent_nodes, $cols, $col, $root_id, $depth, 
         $display, $list, $items );

    $file = "$Common::Config::ses_dir/$sid/go_display";

    if ( -r $file )
    {
        # Get diplay previously saved,

        $display = &Common::File::retrieve_file( $file );
#        $display = &Common::File::eval_file( $file );
    }
    else
    {
        # Create default display,

        $items = &GO::Menus::data_items( $sid );
        $items = &Common::Menus::get_items( $items, "functions", "go_terms_usum" );

        $root_id = $state->{"go_root_id"};
        $depth = 1;
        
        $nodes = &GO::DB::open_node( $dbh, $root_id, $depth );

        $parent_nodes = &GO::DB::get_parents( $dbh, $root_id );
        $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $parent_nodes, 1 );

        $nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $nodes );
        $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

        $display->{"nodes"} = $nodes;
        $display = &GO::Viewer::create_columns( $dbh, $sid, $display, $items, $root_id );

        &Common::File::store_file( $file, $display );
#        &Common::File::dump_file( $file, $display );

        # Save default GO selections,

        $list = &GO::Menus::selections_items( $sid );
        &GO::Menus::save_selections( $sid, $list );

        # Save default Taxonomy selections,

        require Taxonomy::Menus;

        $list = &Taxonomy::Menus::selections_items( $sid );
        &Taxonomy::Menus::save_selections( $sid, $list );
    }

    return wantarray ? %{ $display } : $display;
}

sub add_checkbox_column_prev
{
    # Niels Larsen, February 2004.
    
    # Adds a column of checkboxes immediately to the left of the tree.
    # TODO - remove bad hardcoded $options indices

    my ( $dbh,           # Database handle
         $display,       # Display structure
         $checked,       # Whether checkboxes are checked - OPTIONAL, default 1
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $headers, $nodes, $index, $i, $node_ids, $node_id, @match, $options, $col );

    $headers = $display->{"headers"};
    $nodes = $display->{"nodes"};

    # --------- Defaults,

    if ( defined $checked ) {
        $checked = 1;
    } else {
        $checked = 0;
    }

    # If there is already a checkbox column then we set $index to that
    # position so that column will be overwritten. If not then we set
    # it to the column just after the last so a column will be added,

    $index = scalar @{ $headers };

    for ( $i = 0; $i <= $#{ $headers }; $i++ )
    {
        $col = $headers->[ $i ];

        if ( $col->{"type"} eq "checkbox" )
        {
            $index = $i;
            last;
        }
    }

    # --------- Get ids of nodes to update,

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }
    
    # --------- Set column title,
    
    $options = &GO::Menus::control_items();
        
    if ( $checked ) {
        $headers->[ $index ] = &Storable::dclone( $options->[ 3 ] );
    } else {
        $headers->[ $index ] = &Storable::dclone( $options->[ 2 ] );
    }        
    
    # --------- Set values, status and style for nodes,
    
    foreach $node_id ( @{ $node_ids } )
    {
        $nodes->{ $node_id }->{"column_values"}->[ $index ] = $checked;
        $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
    }
    
    $display->{"headers"} = $headers;
    $display->{"nodes"} = $nodes;

    return wantarray ? %{ $display } : $display;
}    

sub add_statistics_column_prev
{
    # Niels Larsen, February 2004.
    
    # Adds a statistics column to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $dbh,           # Database handle
         $sid,           # Session id
         $display,       # Display structure
         $item,          # Item hash
         $index,         # Column index where to insert - OPTIONAL
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $headers, $nodes, $node_ids, $node_id, @items, $type, $key, $stats );

    $headers = $display->{"headers"};
    $nodes = $display->{"nodes"};

    $type = $item->{"type"};
    $key = $item->{"key"};

    # If there is already a column of the given type and key then we 
    # dont overwrite it but just return. If not then we set the index
    # to the column just after the last so a column will be added,

    if ( @items = &Common::Menus::get_items( $headers, $type, $key ) )
    {
        if ( scalar @items == 1 ) {
            return wantarray ? %{ $display } : $display;
        } else {
            &error( qq (More than one column found of type "$type" and key "$key") );
            exit;
        }
    }
    elsif ( not defined $index )
    {
        $index = scalar @{ $headers };
    }

    # --------- Get ids of nodes to update,

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    # --------- Set column element,
    
    delete $item->{"class"};

    $headers->[ $index ] = &Storable::dclone( $item );
    
    # --------- Get column statistic,

    $stats = &GO::DB::get_statistics( $dbh, $node_ids, "go_id,$key" );
    
    # --------- Set values, status and style for nodes,
    
    foreach $node_id ( @{ $node_ids } )
    {
        if ( exists $stats->{ $node_id } ) {
            $nodes->{ $node_id }->{"column_values"}->[ $index ] = $stats->{ $node_id }->{ $key };
        } else {
            $nodes->{ $node_id }->{"column_values"}->[ $index ] = undef;
        }
        
        $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
    }

    $display->{"nodes"} = $nodes;
    $display->{"headers"} = $headers;
    
    return wantarray ? %{ $display } : $display;
}
