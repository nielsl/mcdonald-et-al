package Taxonomy::Viewer;     #  -*- perl -*-

# Taxonomy specific viewer and related functions. The main
# subroutine is the main one, follow the code from there. We aim to 
# have all xhtml generating code in Taxonomy::Widgets module. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_checkbox_column
                    &add_checkbox_row
                    &add_go_column
                 &create_ids_column
                    &add_link_column
                 &create_statistics_column
                 &create_user_sims_column
                 &create_columns
                 &create_columns_highlight
                 &clear_row_buttons
                 &clear_user_input
                 &close_data
                 &close_node
                 &create_display_from_ids
                 &default_display
                 &expand_node
                 &expand_data
                 &focus_node
                 &handle_popup_windows
                 &handle_text_search
                 &main
                 &open_node
                 &print_seqs
                 &recover_sub
                 &save_selection
                 &set_col_checkbox_values
                 &set_row_button_state
                 &set_row_checkbox_values
                 &update_menu_state
                 );

use Common::Config;
use Common::Messages;

use Common::DB;
use Common::File;
use Common::Util;
use Common::Types;

use Taxonomy::DB_nodes;
use Taxonomy::Nodes;
use Taxonomy::DB;
use Taxonomy::State;
use Taxonomy::Widgets;
use Taxonomy::Menus;
use Taxonomy::Display;

our ( $t0, $t1, $time );
our $Proj_site_dir;

# 1;

# __END__

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_checkbox_column
{
    # Niels Larsen, February 2004.
    
    # Adds a column of checkboxes immediately to the left of the tree.

    my ( $head,          # New header object
         $nodes,         # Nodes hash
         $checked,       # Whether checkboxes are checked - OPTIONAL, default 1
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $hash, $column, $ids );

    if ( defined $root_id ) {
        $ids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Taxonomy::Nodes::get_ids_all( $nodes );
    }

    $hash = Taxonomy::Display->new_checkbox_column( $ids, $checked );

    $column = $head->clone;

    $column->values( $hash );

    return $column;
}

sub create_ids_column
{
    # Niels Larsen, April 2004.
    
    # Adds a column of ids to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $head,          # Header object 
         $nodes,         # Nodes hash
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $ids, $column );

    if ( defined $root_id ) {
        $ids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Taxonomy::Nodes::get_ids_all( $nodes );
    }

    $column = $head->clone;
    $column->values( Taxonomy::Display->new_id_column( $ids ) );

    return $column;
}

sub create_link_column
{
    # Niels Larsen, March 2004.

    # Adds a column of link buttons. Depending on the "type" and "key"
    # values of the cells, the links may lead to different browsers. 

    my ( $header,      # Header object
         $ids,
         $root_id,     # Starting node id - OPTIONAL
         ) = @_;

    my ( $hash );

    $hash = &Taxonomy::Display->new_go_link_column( $ids );

    $header->values( $hash );

    return $header;
}

sub create_statistics_column
{
    # Niels Larsen, February 2004.
    
    # Adds a statistics column to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $dbh,           # Database handle
         $head,          # Header object
         $nodes,         # Nodes hash 
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $columns, $id, $tax_stats, $rna_stats, $column, $values, $data_ids,
         $data_id, $data_stats, $probe, $inputdb, $datatype, $ids, 
         $cell, $js_func );

    if ( defined $root_id ) {
        $ids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Taxonomy::Nodes::get_ids_all( $nodes );
    }

    $column = $head->clone;
    $column->objtype( "col_stats" );
    $column->values( undef );

    $inputdb = $head->inputdb;
    $datatype = $head->datatype;

    $js_func = $datatype ."_report";   # This function must exist in viewer Javascript file

    if ( $datatype eq "orgs_taxa" )
    {
        $tax_stats = &Taxonomy::DB::get_stats( $dbh, $ids, $inputdb, $datatype ) || {};

        $column = Taxonomy::Display->set_column_cells( $column, $tax_stats );
#        $column = &Taxonomy::Display::set_column_bgramp( $column, "sum_count", "#cccccc", "#ffffff", $root_id );
        
        $values = $column->values;
        
        foreach $id ( keys %{ $values } )
        {
            $cell = $values->{ $id };
            $cell->request( qq ($js_func('$id','/$Proj_site_dir') ) );
            $cell->css( "blue_button" );
        }
    }
    else
    {
        $tax_stats = &Taxonomy::DB::get_stats( $dbh, $ids, $inputdb, $datatype ) || {};

        $column = Taxonomy::Display->set_column_cells( $column, $tax_stats );
#        $column = &Taxonomy::Display::set_column_bgramp( $column, "sum_count", "#cccccc", "#ffffff", $root_id );

        $values = $column->values;

        foreach $id ( keys %{ $values } )
        {
            $cell = $values->{ $id };
            
            if ( $data_ids = $cell->data_ids and scalar @{ $data_ids } == 1 )
            {
                $cell->request( qq ($js_func('$data_ids->[0]','/$Proj_site_dir') ) );
                $cell->data_ids( [] );
            }
            else {
                $cell->request( qq ($js_func('$id','/$Proj_site_dir') ) );
            }

            $cell->css( "green_button" );
        }
    }

    return $column;
}

sub create_user_sims_column
{
    # Niels Larsen, December 2005.
    
    # Adds a statistics column to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $sid,           # Database handle
         $head,          # Column header
         $nodes,         # Nodes hash
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $dbh, $ids, $column, $tax_stats, $datatypes, $searchdbs,
         $data_title, $db_tiptext, $user_title, $tiptext, $job_id );

    require Submit::Batch;
    
    if ( defined $root_id ) {
        $ids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Taxonomy::Nodes::get_ids_all( $nodes );
    }

    $head->objtype( "col_sims" );

    $datatypes = Common::Menus->datatype_menu();
    $searchdbs = Common::Menus->searchdbs_menu();

    $data_title = $datatypes->match_option( "name" => $head->datatype )->title;
    $db_tiptext = $searchdbs->match_option( "name" => $head->inputdb )->tiptext;

    $user_title = $head->title;
    $job_id = $head->jid;

    $tiptext = qq (\\'$user_title\\' data ($data_title) run against all $db_tiptext (job $job_id).);

    $head->tiptext( $tiptext );

    $dbh = &Common::DB::connect_user( $sid );

    $tax_stats = &Taxonomy::DB::get_tax_stats_user( $dbh, $head->jid, $ids );

    &Common::DB::disconnect( $dbh );

    # Set column cells and add the column to the display,

    $column = Taxonomy::Display->set_column_cells( $head, $tax_stats );

    return $column;
}

sub create_columns
{
    # Niels Larsen, October 2005.

    # Given a menu of column items, fetches the corresponding data values and 
    # adds them as values to each item. If a root id is given, starts at that
    # node instead of the top node. Returned is an copy of the given menu, but
    # with values attached. 

    my ( $dbh,        # Database handle
         $sid,
         $menu,       # Menu object
         $nodes,      # Nodes hash
         $root_id,    # Root id - OPTIONAL
         ) = @_;

    # Returns an updated display structure.

    my ( $columns, $column );

    $columns = $menu->clone;

    foreach $column ( @{ $columns->options } )
    {
        $column = &Taxonomy::Viewer::create_column( $dbh, $sid, $column, $nodes, $root_id );
    }

    return $columns;
}

sub clear_col_buttons
{
    # Niels Larsen, January 2005.

    # Clears the state for column button flags. 

    my ( $state,     # State hash
          ) = @_;

    # Returns a hash.
    
    $state->{"tax_delete_cols_button"} = 0;

    return $state;
}

sub clear_row_buttons
{
    # Niels Larsen, January 2005.

    # Clears the state for row button flags. 

    my ( $state,     # State hash
          ) = @_;

    # Returns a hash.
    
    $state->{"tax_save_taxa_button"} = 0;
    $state->{"tax_rna_seqs_button"} = 0;
    
    return $state;
}

sub clear_user_input
{
    # Niels Larsen, February 2005.

    # Sets the state values that come directly from user input fields
    # to nothing. 

    my ( $display,   # Display structure
         $state,     # State hash
         ) = @_;

    # Returns a hash.

    my ( @check_ids, %node_ids, $check_id );

    $state->{"request"} = "";

    $state->{"tax_control_menu"} = "";
    $state->{"tax_data_menu"} = "";
    $state->{"tax_click_id"} = "";
    $state->{"tax_col_index"} = "";
    $state->{"tax_col_ids"} = [];
    
#     %node_ids = map { $_, 1 } &Taxonomy::Nodes::get_ids_all( $display->nodes );

#     foreach $check_id ( @{ $state->{"tax_row_ids"} } )
#     {
#         if ( exists $node_ids{ $check_id } )
#         {
# #            push @check_ids, $check_id;
#         }
#     }
    
#     $state->{"tax_row_ids"} = \@check_ids;

    $state->{"tax_row_ids"} = [];

    $state->{"tax_info_type"} = "";
    $state->{"tax_info_key"} = "";
    $state->{"tax_info_menu"} = "";
    $state->{"tax_info_col"} = "";
    $state->{"tax_info_index"} = "";
    $state->{"tax_info_ids"} = [];

    $state->{"is_help_page"} = 0;
    $state->{"is_popup_page"} = 0;
    
    return $state;
}

sub close_data
{
    # Niels Larsen, November 2005.

    # Does not fetch anything from the database but simply amputates
    # the data nodes in memory.

    my ( $display,      # Display structure
         $col_ndx,      # Column index
         $node_id,      # Node of deleted data
         ) = @_;

    # Returns an updated display.

    my ( $column, $cell );

    $column = $display->columns->get_option( $col_ndx );
    $cell = $column->values->{ $node_id };

    $cell->values( [] );
    $cell->expanded_data( 0 );

    return $display;
}

sub close_node
{
    # Niels Larsen, January 2005.

    # Does not fetch anything from the database but simply amputates
    # the nodes in memory,

    my ( $display,      # Display structure
         $root_id,      # Top node of deleted tree
         ) = @_;

    # Returns an updated display.

    my ( $nodes, $node, $columns, $column, $cell );

    $columns = $display->columns;

    $nodes = $display->nodes;
    $nodes = &Taxonomy::Nodes::delete_subtree( $nodes, $root_id, 1 );

    foreach $column ( $columns->options )
    {
        if ( defined ( $cell = $column->values->{ $root_id } ) )
        {
            $cell->expanded( 0 );
        }
    }
    
    $display->nodes( $nodes );

    return $display;
}

sub create_column
{
    # Niels Larsen, October 2005.

    # Given a menu option, gets its request and adds the corresponding data 
    # values. A column is a menu option object with the "values" field set to
    # a hash of cells. Each cell in turn is an option object. If a root id is
    # given, starts at that node instead of the top node.

    my ( $dbh,        # Database handle
         $sid,        # Session id
         $option,     # Menu option
         $nodes,
         $root_id,    # Root id - OPTIONAL
         ) = @_;

    # Returns an updated display structure.

    my ( $hash, $column, $request, $index, $ids );

    if ( defined $root_id ) {
        $ids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $ids = &Taxonomy::Nodes::get_ids_all( $nodes );
    }

    $request = $option->request;

    if ( $request eq "add_unchecked_column" )
    {
        $column = &Taxonomy::Viewer::create_checkbox_column( $option, $nodes, undef, $root_id );
    }
    elsif ( $request eq "add_checked_column" )
    {
        $column = &Taxonomy::Viewer::create_checkbox_column( $option, $nodes, "checked", $root_id );
    }
    elsif ( $request eq "add_ids_column" )
    {
        $column = &Taxonomy::Viewer::create_ids_column( $option, $nodes, $root_id );
    }
    elsif ( $request eq "add_node_counts_column" or $request eq "add_statistics_column" )
    {
        $column = &Taxonomy::Viewer::create_statistics_column( $dbh, $option, $nodes, $root_id );
    }
    elsif ( $request eq "add_user_sims_column" )
    {
        $column = &Taxonomy::Viewer::create_user_sims_column( $sid, $option, $nodes, $root_id );
    }
#    elsif ( $request eq "add_link_column" )
#    {
#        $column = &Taxonomy::Viewer::create_link_column( $option, $ids, $root_id );
#    }
#         elsif ( $request eq "restore_terms_selection" or $request eq "add_go_column" )
#         {
#             $column = &Taxonomy::Viewer::create_go_column( $dbh, $sid, $display, $option, $index, $root_id );
#         }
    elsif ( $request ne "restore_selection" )
    {
        &error( qq (Wrong looking request -> "$request") );
    }

#    $column = $option->clone;
#    $column->values( $hash );
    
    return $column;
}

sub create_display_from_ids
{
    # Niels Larsen, January 2005.

    # Builds a display from a list of ids. This involves finding the parents
    # necessary to connect the nodes and attaching the columns specified.

    my ( $dbh,        # Database handle
         $sid,        # Session id
         $ids,        # List of ids
         $menu,       # Column headers List of column items to attach
         $root_id,    # Starting node id
         $fill,
         ) = @_;

    # Returns a hash.
    
    my ( $select, $leaves, $nodes, $p_nodes, $root_node, $display, 
         $title, $alt_title, $columns );

    $fill = 1 if not defined $fill;
    
    $select = "tax_nodes.tax_id,parent_id,depth,name,name_type,nmin,nmax";
    $leaves = &Taxonomy::DB::get_nodes( $dbh, $ids, $select );

    if ( $leaves )
    {
        $display = Taxonomy::Display->new( "title" => "Taxonomy Display" );

        # Create nodes,

        if ( $fill ) 
        {
            $nodes = &Taxonomy::DB::open_node( $dbh, $root_id, 1 );
            $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $leaves, 1 );
        }
        else {
            $nodes = $leaves;
        }
        
        $p_nodes = &Taxonomy::DB::get_nodes_parents( $dbh, $nodes );
        $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $p_nodes );
        
        $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes );

        $root_node = &Taxonomy::Nodes::get_node_root( $nodes, $root_id );

        if ( not $root_node or not %{ $root_node } )
        {
            $root_node = &Taxonomy::Nodes::get_node_root( $nodes );
            $root_id = &Taxonomy::Nodes::get_id( $root_node );
        }

        # Set title, 

        $title = &Taxonomy::Nodes::get_name( $root_node);
        $title = &Common::Names::format_display_name( $title );

        $display->title( $title );

        $alt_title = &Taxonomy::Nodes::get_alt_name( $root_node );
        
        if ( $alt_title ) {
            $display->alt_title( $alt_title );
        } else {
            $display->alt_title( "" );
        }
        
        $nodes = &Taxonomy::DB_nodes::add_common_names( $dbh, $root_node, $nodes );

        $display->nodes( $nodes );

        # Create columns,

        $columns = &Taxonomy::Viewer::create_columns( $dbh, $sid, $menu, $nodes, $root_id );

        $display->columns( $columns );

        # Initialize column buttons,
        
        $display->column_buttons( Taxonomy::Menus->new( "title" => "Column Buttons" ) );

        return $display;
    }
    else {
        &error( qq (No nodes found.) );
    }

    return;
}

sub default_display
{
    # Niels Larsen, February 2005.

    # Generates a default display: a one-level deep show of the bacterial
    # families with the total organism counts attached as columns.

    my ( $dbh,         # Database handle
         $wwwpath,
         $sid,         # Session id
         $nid,         # Root node id
         ) = @_;

    # Returns a display structure.

    my ( $root_id, $depth, $nodes, $p_nodes, $root_node, $columns, $file,
         $display, $menu, $title, $alt_title, $option );

    # Defaults, 

    if ( defined $nid ) {
        $root_id = $nid;
    } else {
        $root_id = 2;   # Bacteria
    }

    $depth = 1;

    # Initialize,

    $display = Taxonomy::Display->new( "title" => "Taxonomy Display" );
    $display->session_id( $sid );

    # Create nodes,

    $nodes = &Taxonomy::DB::open_node( $dbh, $root_id, $depth );

    $p_nodes = &Taxonomy::DB::get_parents( $dbh, $root_id );
    $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $p_nodes, 1 );
    
    $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes );
    
    $root_node = &Taxonomy::Nodes::get_node( $nodes, $root_id );
    $nodes = &Taxonomy::DB_nodes::add_common_names( $dbh, $root_node, $nodes );

    $display->nodes( $nodes );

    # Set title,

    $title = &Taxonomy::Nodes::get_name( $root_node);
    $title = &Common::Names::format_display_name( $title );

    $display->title( $title );

    $alt_title = &Taxonomy::Nodes::get_alt_name( $root_node );

    if ( $alt_title ) {
        $display->alt_title( $alt_title );
    } else {
        $display->alt_title( "" );
    }        

    # Create data columns. As default, add organism counts only.

    $menu = Taxonomy::Menus->control_menu( $sid, $wwwpath );
    $option = $menu->match_option( "request" => "add_node_counts_column" );
    $menu->options( [ $option ] );

    $columns = &Taxonomy::Viewer::create_columns( $dbh, $sid, $menu, $nodes, $root_id );

    $display->columns( $columns );

    # Initialize column buttons,

    $display->column_buttons( Taxonomy::Menus->new( "title" => "Column Buttons" ) );

    return $display;
}

sub expand_data
{
    # Niels Larsen, November 2005.
    
    # Expands a leaf to a list of data attached to it: if there are data
    # attached to a node, the statistics database will have a list of ids.
    # This routine fishes those out and creates the display structure so 
    # the rendering will show it. 
    
    my ( $dbh,          # Database 
         $display,      # Display object
         $index,        # Column index of the cell clicked
         $node_id,      # Node or "row" id of the cell clicked
         ) = @_;

    # Returns an updated display.

    my ( $nodes, $columns, $datatype, $table, $sql, @tuples,
         $tuple, $idstr, $id, $stats, $cell, $column, $inputdb, @cells );

    $nodes = $display->nodes;
    
    $columns = $display->columns;

    # Clear all previous expansions and set expand button to up,

    foreach $column ( $display->columns->options )
    {
        if ( $cell = $column->values->{ $node_id } )
        {
            $cell->values( [] );
            $cell->expanded_data( 0 );
        }
    }
    
    $column = $display->columns->get_option( $index );

    $inputdb = $column->inputdb;
    $datatype = $column->datatype;

    $cell = $column->values->{ $node_id };
    $cell->expanded_data( 1 );

    if ( $datatype eq "rna_seq" )
    {
        $table = "rna_origin";
        $id = "rna_id";
    }
    else {
        &error( qq (Wrong looking datatype -> "$datatype") );
    }

    $stats = &Taxonomy::DB::get_stats( $dbh, [ $node_id ], $inputdb, $datatype ) || {};
    $idstr = join ",", @{ $stats->{ $node_id }->{"data_ids"} };

    $sql = qq (select $id,src_de from $table where $id in ( $idstr ));

    @tuples = &Common::DB::query_array( $dbh, $sql );

    foreach $tuple ( sort { $a->[1] cmp $b->[1] } @tuples )
    {
        $cell = Taxonomy::Cells->new();
        $cell->datatype( $datatype );
        $cell->title( $tuple->[1] );
        $cell->request( "$datatype"."_report('$tuple->[0]','/$Proj_site_dir')" );
        
        push @cells, $cell;
    }

    $column->values->{ $node_id }->values( \@cells );

    return $display;
}    

sub expand_node
{
    # Niels Larsen, January 2005.

    # Adds new nodes and new column cells to the display. The user presses
    # one of the linked cells, then a fully expanded subtree is inserted at 
    # that node, including new cells for the currently visible columns. The
    # cells in the clicked column will look depressed. 
    
    my ( $dbh,          # Database handle
         $sid,          # Session id
         $display,      # Display structure
         $index,        # Index of column to expand
         $root_id,      # Starting node id
         ) = @_;

    # Returns an updated display structure.

    my ( $nodes, $root_node, $new_nodes, $columns, $datatype, $i, 
         $ids, $id, $stats, $cell, $new_columns, $column, $inputdb );

    $nodes = $display->nodes;
    
    $column = $display->columns->get_option( $index );

    $datatype = $column->datatype;
    $inputdb = $column->inputdb;

    # Add new nodes,
    
    if ( $datatype eq "orgs_taxa" or $datatype =~ /_seq$/ )
    {
        $new_nodes = &Taxonomy::DB::expand_tax_node( $dbh, $inputdb, $datatype, $root_id );
    }
#    elsif ( $datatype eq "functions" )
#    {
#        $new_nodes = &Taxonomy::DB::expand_go_node( $dbh, $item->{"ids"}, $root_id );
#    }
    else
    {
        &error( qq (Unrecognized column type -> "$datatype") );
    }

    $nodes = &Taxonomy::Nodes::delete_subtree( $nodes, $root_id, 1 );
        
    $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $new_nodes );
    $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes );
    
    $root_node = &Taxonomy::Nodes::get_node( $nodes, $root_id );
    $nodes = &Taxonomy::DB_nodes::add_common_names( $dbh, $root_node, $nodes );

#    $ids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
#    
#    if ( $datatype eq "rna" )
#    {
#        $stats = &Taxonomy::DB::get_rna_stats( $dbh, $ids, $objtype );
#        
#        foreach $id ( @{ $ids } )
#        {
#            $nodes->{ $id }->{"cells"}->[$index]->{"values"} = $stats->{ $id }->{"values"} || [];
#        }
#    }

    $display->nodes( $nodes );

    # Add new cells to existing columns,

    $new_columns = &Taxonomy::Viewer::create_columns( $dbh, $sid, $display->columns, $nodes, $root_id );

    $column = $new_columns->get_option( $index );

    foreach $cell ( values %{ $column->values } )
    {
        $cell->expanded( 1 );
    }

    $display->merge_columns( $new_columns );

    # Return updated display,
    
    return $display;
}

sub focus_node
{
    # Niels Larsen, January 2005.

    # Zooms in on a clicked node by fetching new nodes from database
    # plus deleting everything not belonging to the new root. Preserves
    # the columns that have been selected. 

    my ( $dbh,           # Database handle
         $sid,           # Session id
         $display,       # Display structure
         $root_id,       # Starting node id
         ) = @_;

    # Returns an updated display.

    my ( $nodes, $node, $title, $alt_title, $p_nodes, $columns, $root_node );

    $nodes = &Taxonomy::DB::open_node( $dbh, $root_id, 1, 8 );

    $p_nodes = &Taxonomy::DB::get_parents( $dbh, $root_id );
    $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $p_nodes, 1 );

    $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes );

    $node = &Taxonomy::Nodes::get_node( $nodes, $root_id );
    $nodes = &Taxonomy::DB_nodes::add_common_names( $dbh, $node, $nodes );

    $display->nodes( $nodes );

    # Set title,

    $root_node = &Taxonomy::Nodes::get_node( $nodes, $root_id );

    $title = &Taxonomy::Nodes::get_name( $root_node);
    $title = &Common::Names::format_display_name( $title );

    $display->title( $title );

    $alt_title = &Taxonomy::Nodes::get_alt_name( $root_node );

    if ( $alt_title )
    {
        $alt_title = &Common::Names::format_display_name( $alt_title );
        $display->alt_title( $alt_title );
    }
    else {
        $display->alt_title( "" );
    }        

    # Set columns,

    $columns = &Taxonomy::Viewer::create_columns( $dbh, $sid, $display->columns, $nodes, $root_id );

    $display->columns( $columns );

    return $display;
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

    my ( $xhtml, $entry, $types, $title, $nodes, $p_nodes, $msgs );

    if ( $request eq "help" )
    {
        require Taxonomy::Help;
        $xhtml = &Taxonomy::Help::pager( "main" );
        
        $state->{"is_help_page"} = 1;
        $state->{"title"} = "Organisms Help Page";
    }
    elsif ( $request eq "search_window" )
    {
        $title = &Taxonomy::DB::get_name_of_id( $dbh, $state->{"tax_root_id"} );

        $nodes = &Taxonomy::DB::get_nodes( $dbh, [ $state->{"tax_root_id"} ] );
        $p_nodes = &Taxonomy::DB::get_parents( $dbh, $state->{"tax_root_id"} );
        $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $p_nodes );

        $xhtml = &Taxonomy::Widgets::search_window( $sid, $state, $title, $nodes );

        $state->{"is_popup_page"} = 1;
        $state->{"title"} = "Taxonomy Search Page";
    }
    elsif ( $request eq "save_selection_window" )
    {
        $xhtml = &Taxonomy::Widgets::save_taxa_window( $sid, $state );
        
        $state->{"is_popup_page"} = 1;
        $state->{"title"} = "Save Selected Taxa Page";
    }
    elsif ( $request eq "orgs_taxa_report" )
    {
        $entry = &Taxonomy::DB::get_entry( $dbh, $state->{"tax_report_id"} );

        $xhtml = &Taxonomy::Widgets::orgs_taxa_report( $sid, $entry );
        
        $state->{"is_popup_page"} = 1;
        $state->{"title"} = "Taxonomy Report Page";
    }
    elsif ( $request eq "rna_seq_report" )
    {
        require RNA::DB;
        
        $entry = &RNA::DB::get_entry( $dbh, $state->{"tax_report_id"} );
        $types = &RNA::DB::get_types( $dbh );

        $xhtml = &Taxonomy::Widgets::rna_seq_report( $sid, $entry, $types );
        
        $state->{"is_popup_page"} = 1;
        $state->{"title"} = "Taxonomy Report Page";
    }
    else {
        &error( qq (Wrong looking popup-window request -> "$request") );
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

    my ( $root_id, $text, $type, $target, $ids, $count, $count_str, $title );

    $root_id = $state->{"tax_root_id"};
    $text = $state->{"tax_search_text"} || "";
    $type = $state->{"tax_search_type"};
    $target = $state->{"tax_search_target"};

    if ( $text =~ /\w/ ) 
    {
        if ( $target eq "ids" ) {
            $ids = &Taxonomy::DB_nodes::match_ids( $dbh, $text, $root_id );
        } else {
            $ids = &Taxonomy::DB_nodes::match_text( $dbh, $text, $target, $type, $root_id );
        }

        if ( $ids )
        {
            $count = scalar @{ $ids };
            $count_str = &Common::Util::commify_number( $count );
            
            if ( $count <= 1000 )
            {
                $title = $display->title;

                $display = &Taxonomy::Viewer::create_display_from_ids( $dbh, $sid, $ids, $display->columns, $root_id );

                $display->title( $title );
                $display->session_id( $sid );

                if ( $target eq "ids" ) {
                    $display->boldify_ids( $ids, $root_id );
                } else {
                    $display->boldify_names( $text, $target, $root_id );
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

sub main
{
    # Niels Larsen, 2003 and on.

    # The user interface of a taxonomy tree. The routine first dives
    # into a session hash where CGI arguments have been saved and 
    # padded with defaults. The routine looks in the session to see 
    # what action to take, updates the hierarchy and displays the 
    # result. The display tree is maintained as a hash where keys are
    # node ids and values are the fields one would like to see painted
    # on the tree. There are two kinds of queries: overlays, where 
    # the current display tree topology is not changed and searches
    # where the tree becomes the minimal subtree that exactly spans
    # the results. This routine returns XHTML as a string. 

    my ( $args,
         $msgs,
         ) = @_;

    # Returns a string.
    
    my ( $sid, $state, $sys_state, $proj,
         $root_node, $root_id, $dbh, $index, $option, $xhtml, @message_list,
         @messages, $display, $display_file, $col, $control_menu, $data_menu, 
         $ids, $id, $click_id, $column, $head, $string, $user_menu, $objtype,
         $inputdb, $format, $request, $menu_file, $datpath, $wwwpath );

    $args = &Registry::Args::check( $args, {
        "HR:1" => [ qw ( sys_state viewer_state ) ],
        "O:1" => [ qw ( project ) ],
    });

    $proj = $args->project;
    $sys_state = $args->sys_state;
    $state = $args->viewer_state;

    $sid = $sys_state->{"session_id"};
    
    $Proj_site_dir = $proj->projpath;
    $Taxonomy::Widgets::Proj_site_dir = $Proj_site_dir;

    # >>>>>>>>>>>>>>>>>>>>> ARGUMENT CHECK <<<<<<<<<<<<<<<<<<<<<<<<

    # There must be both a session id and an input string (the 
    # viewer can be used for hierarchies from different sources).

    $datpath = $state->{"inputdb"};
    $wwwpath = $state->{"tax_www_path"};

    &error( qq (Taxonomy directory path not defined) ) if not $datpath;
    &error( qq (WWW taxonomy site path not defined) ) if not $wwwpath;

    # >>>>>>>>>>>>>>>>>> ERROR RECOVERY FUNCTION <<<<<<<<<<<<<<<<<<<

    # The function defined here will be run in the event of a fatal
    # error. That gives the user a chance to at least start over if 
    # a program error happens. Next thing to do is to report this
    # automatically and perhaps keep versions 1 step back (slowing
    # the responses). 

    $Common::Config::recover_sub = &Taxonomy::Viewer::recover_sub( $sid, $state );

    # >>>>>>>>>>>>>>>>>>>>>>>> LOAD STATE <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # We store a state hash on file where the CGI parameters, if any, 
    # have been merged in. This state contains instructions to this
    # viewer about what should be shown, if menus are open etc.
    
    if ( not defined $state ) {        
        $state = &Taxonomy::State::restore_state( $sid, $datpath );
    }

    $request = $state->{"request"} ||= "";

    # >>>>>>>>>>>>>>>>>>>>>>> LOAD DISPLAY <<<<<<<<<<<<<<<<<<<<<<<<<

    $dbh = &Common::DB::connect( $state->{"inputdb"} );

    # We store the display as a hash with three main keys: "headers",
    # "nodes" and "checkbox_row". The first contains information about
    # the column headers the second holds everything that is node specific
    # and the third remembers column checkboxes. If no display stored, 
    # a default one is created,

    $display_file = "$Common::Config::ses_dir/$sid/$datpath"."_display";

    if ( -r $display_file )
    {
        $display = &Common::File::retrieve_file( $display_file );
    }
    else
    {
        $root_id = 2;  # Bacteria in NCBI
        $display = &Taxonomy::Viewer::default_display( $dbh, $wwwpath, $sid, $root_id );
        &Common::File::store_file( $display_file, $display );
    }

    # Apply checked status to all visible nodes, 
    
    &Taxonomy::Viewer::set_row_checkbox_values( $display, $state->{"tax_row_ids"} );
    &Taxonomy::Viewer::set_col_checkbox_values( $display, $state->{"tax_col_ids"} );

    # >>>>>>>>>>>>>>>>>> GET REQUESTS FROM MENUS <<<<<<<<<<<<<<<<<<<<<<<

    # When a menu item is chosen by the user, the name of the menu 
    # gets submitted as cgi parameter, and its value is the id of the
    # chosen option. 

    if ( $request eq "handle_tax_control_menu" )
    {
        $control_menu = Taxonomy::Menus->control_menu( $sid, $wwwpath );

        $id = $state->{"tax_control_menu"};
        $option = $control_menu->match_option( "id" => $id );

        if ( $option->inputdb ) {
            $state->{"tax_inputdb"} = $option->inputdb;
        }

        $request = $option->request;
    }
    elsif ( $request eq "handle_tax_data_menu" )
    {
        $data_menu = Taxonomy::Menus->data_menu( $sid );
        $id = $state->{"tax_data_menu"};

        $request = $data_menu->match_option( "id" => $id )->request;
    }
    elsif ( $request eq "handle_tax_user_menu" )
    {
        $user_menu = Taxonomy::Menus->user_menu( $sid );
        $option = $user_menu->match_option( "id" => $state->{"tax_user_menu"} );
        $request = $option->request;
    }

    # >>>>>>>>>>>>>>>>>>>>>> EXECUTE REQUESTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Some user actions require changes in the tree topology, some 
    # just what is being superimposed on it, or other actions. This
    # section tests the "request" key and acts on it. 

#     foreach $column ( $display->columns->options )
#     {
#         my $objtype = $column->objtype || "";
#         my $datatype = $column->datatype || "";
#         my $inputdb = $column->inputdb || "";
#         $id = $column->id || "";

#         &dump( "id, objtype, datatype, inputdb = $id, $objtype, $datatype, $inputdb" );
#     }

    if ( $request )
    {
        $root_id = $state->{"tax_root_id"};

        if ( not defined $state->{"tax_click_id"} ) {
            $state->{"tax_click_id"} = $root_id;
        } 

        # >>>>>>>>>>>>>>>>>>> MENUS OPEN / CLOSE REQUESTS <<<<<<<<<<<<<<<<<<<<

        # We get here when the user clicks to open or close a menu. This 
        # section sets state flags that the display routines understand
        # later,

        if ( $request =~ /^show.*menu$/ or $request =~ /hide.*menu$/ )
        {
            $state = &Taxonomy::Viewer::update_menu_state( $state, $request );
        }

        # >>>>>>>>>>>>>>>>>>>>> NORMAL EDITING REQUESTS <<<<<<<<<<<<<<<<<<<<<<<

        # This includes open, close, focusing on sub-categories and different
        # types of expanding by the column pushbuttons,
        
        elsif ( $request eq "open_node" )
        {
            $display = &Taxonomy::Viewer::open_node( $dbh, $sid, $display, $state->{"tax_click_id"} );
        }

        elsif ( $request eq "focus_node" )
        {
            $display = &Taxonomy::Viewer::focus_node( $dbh, $sid, $display, $state->{"tax_click_id"} );
            $state->{"tax_root_id"} = $state->{"tax_click_id"};
        }

        elsif ( $request eq "close_node" or $request eq "collapse_node" )
        {
            $display = &Taxonomy::Viewer::close_node( $display, $state->{"tax_click_id"} );
        }

        elsif ( $request eq "expand_node" )
        {
            $index = $state->{"tax_col_index"};
            $click_id = $state->{"tax_click_id"};
            
            $display = &Taxonomy::Viewer::expand_node( $dbh, $sid, $display, $index, $click_id );
        }

        elsif ( $request eq "close_data" )
        {
            $index = $state->{"tax_col_index"};
            $click_id = $state->{"tax_click_id"};

            $display = &Taxonomy::Viewer::close_data( $display, $index, $click_id );
        }

        elsif ( $request eq "expand_data" )
        {
            $index = $state->{"tax_col_index"};
            $click_id = $state->{"tax_click_id"};
            
            $display = &Taxonomy::Viewer::expand_data( $dbh, $display, $index, $click_id );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>> POPUP WINDOWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "help" or $request eq "search_window" or 
                $request eq "save_selection_window" or $request eq "orgs_taxa_report" or
                $request eq "rna_seq_report" )
        {
            my $sys_state;
            
            if ( $request eq "help" ) {
                $sys_state->{"is_help_page"} = 1;
            } else {
                $sys_state->{"is_popup_page"} = 1;
            }
            
            $sys_state->{"viewer"} = $state->{"tax_viewer_name"};
            $sys_state->{"session_id"} = $sid;

            $xhtml = &Taxonomy::Viewer::handle_popup_windows( $dbh, $sid, $state, $request );

            &Common::Widgets::show_page(
                {
                    "body" => $xhtml,
                    "sys_state" => $sys_state, 
                    "project" => $proj,
                });
            
            $state = &Taxonomy::Viewer::clear_user_input( $display, $state );
            &Taxonomy::State::save_state( $sid, $datpath, $state );

            &Common::DB::disconnect( $dbh );
            exit 0;
        }

        # >>>>>>>>>>>>>>>>>>>>> ADD TAXA CHECKBOXES <<<<<<<<<<<<<<<<<<<<<<<<<<

        # Inserts a column of checkboxes so the user can select taxa,
        
        elsif ( $request eq "add_unchecked_column" or $request eq "add_checked_column" ) 
        {
            $head = $control_menu->match_option( "id" => $state->{"tax_control_menu"} );
            $objtype = $head->objtype;

            if ( $objtype eq "checkboxes_checked" )
            {
                $column = &Taxonomy::Viewer::create_checkbox_column( $head, $display->nodes, 1, $root_id );
                $state->{"tax_row_ids"} = [];
            }
            elsif ( $objtype eq "checkboxes_unchecked" ) {
                $column = &Taxonomy::Viewer::create_checkbox_column( $head, $display->nodes, 0, $root_id );
            } else {
                &error( qq (Wrong looking objtype -> "$objtype") );
            }

            $index = $display->columns->match_option_index( "expr" => '$_->objtype =~ /^checkboxes_/' );
            $display->add_column( $column, $index );

            $state = &Taxonomy::Viewer::set_row_button_state( $state, $head );
        }

        # >>>>>>>>>>>>>>>>>>>> ADD COLUMN CHECKBOXES <<<<<<<<<<<<<<<<<<<<<<<<<

        # Adds an extra row of checkboxes just above the column headers, so
        # it is easier to delete select columns in one go,

        elsif ( $request eq "add_checked_row" )
        {
            if ( @{ $display->columns->options } )
            {
                $id = $state->{"tax_control_menu"};

                $option = Taxonomy::Menus->control_menu( $sid, $wwwpath )->match_option( "id" => $id );
                $option->selected( 1 );

                $display->column_buttons->options( [] );

                foreach $head ( $display->columns->options )
                {
                    $display->column_buttons->append_option( $option );
                }
            }
        }
        elsif ( $request eq "add_unchecked_row" ) 
        {
            if ( @{ $display->columns->options } )
            {
                $id = $state->{"tax_control_menu"};

                $option = Taxonomy::Menus->control_menu( $sid, $wwwpath )->match_option( "id" => $id );
                $option->selected( 0 );

                $display->column_buttons->options( [] );

                foreach $head ( $display->columns->options )
                {
                    $display->column_buttons->append_option( $option );
                }
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> ADD ID COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_ids_column" )
        {
            $head = $control_menu->match_option( "request" => $request );

            $column = &Taxonomy::Viewer::create_ids_column( $head, $display->nodes, $root_id );

            $display->add_column( $column );
        }

        # >>>>>>>>>>>>>>>>>>>>> ADD NODE COUNTS COLUMN <<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_node_counts_column" )
        {
            $head = $control_menu->match_option( "request" => $request );

            $column = &Taxonomy::Viewer::create_statistics_column( $dbh, $head, $display->nodes, $root_id );

            $display->add_column( $column );
        }

        # >>>>>>>>>>>>>>>>>>>>> ADD STATISTICS COLUMN <<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_statistics_column" )
        {
            $head = $data_menu->match_option( "id" => $state->{"tax_data_menu"} );

            $column = &Taxonomy::Viewer::create_statistics_column( $dbh, $head, $display->nodes, $root_id );

            $display->add_column( $column );
        }

        # >>>>>>>>>>>>>>>>>>> ADD USER SIMILARITY COLUMN <<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_user_sims_column" )
        { 
            $head = $user_menu->match_option( "id" => $state->{"tax_user_menu"} );
            $head->request( $request );
            $head->name( "tax_user_menu" );

            $column = &Taxonomy::Viewer::create_user_sims_column( $sid, $head, $display->nodes, $root_id );
            
            $display->add_column( $column );
         }

        # >>>>>>>>>>>>>>>>>>>> DELETE COLUMN CHECKBOXES <<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "hide_tax_col_checkboxes" )
        {
            $display->column_buttons->options( [] );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> DELETE A COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_column" )
        {
            $display->delete_column( $state->{"tax_col_index"} );
        }

        # >>>>>>>>>>>>>>>>>>>>> DELETE SELECTED COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_columns" )
        {
            $display->delete_columns( $state->{"tax_col_ids"} );
        }
        
#         # >>>>>>>>>>>>>>>>>>>>>>>> DOWNLOAD SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
#         elsif ( $request eq "download_seqs" )
#         {
#             # This is point of no return, so must save state,

#             $state = &Taxonomy::Viewer::clear_user_input( $display, $state );
#             &Taxonomy::State::save_state( $sid, $datpath, $state );

#             $inputdb = $state->{"tax_inputdb"};
#             $format = "fasta";

#             @messages = &Taxonomy::Viewer::seqs_to_client( $dbh, $display, $inputdb, $format );

#             if ( @messages ) {
#                 push @message_list, @messages if @messages;
#             } else {
#                 &Common::DB::disconnect( $dbh );
#                 exit;
#             }
#         }

        # >>>>>>>>>>>>>>>>>>>>> SAVE ORGANISMS SELECTION <<<<<<<<<<<<<<<<<<<<<<<<
        
        elsif ( $request eq "save_orgs" )
        {
            $option = Taxonomy::Menus->new_selection( $state );
            $option->value( $state->{"tax_root_id"} );

            @messages = &Taxonomy::Viewer::save_selection( $sid, $option, $state );

            push @message_list, @messages if @messages;
        }

        elsif ( $request eq "restore_selection" )
        {
            # >>>>>>>>>>>>>>> RECONSTRUCT DISPLAY FROM SAVED IDS <<<<<<<<<<<<<<<<<
            
            $option = $user_menu->match_option( "id" => $state->{"tax_user_menu"} );

            if ( $option->datatype eq "orgs_taxa" )
            {
                $ids = $option->values;
                $display = &Taxonomy::Viewer::create_display_from_ids( $dbh, $sid, $ids, 
                                                                       $display->columns, $root_id, 0 );

                $root_node = &Taxonomy::Nodes::get_nodes_parent( $ids, $display->nodes );

                $state->{"tax_root_id"} = &Taxonomy::Nodes::get_id( $root_node );

                $display->session_id( $sid );

                $display->title( $option->title );
                $display->alt_title( "" );
            }
            else
            {
                $string = $option->datatype;
                &error( qq (Wrong looking datatype -> "$string") );
            }


#             $index = $state->{"tax_selections_menu"};
#             $sel = &Common::Menus::read_selections( $sid )->[ $index ];

#             if ( $sel->{"type"} eq "orgs_taxa" )
#             {
#                 $display->{"nodes"} = {};
#                 $display = &Taxonomy::Viewer::rebuild_display( $dbh, $sid, $state, $display, $sel->{"ids"} );

#                 $root_node = &Taxonomy::Nodes::get_node( $display->{"nodes"}, $state->{"tax_root_id"} );
#                 &Taxonomy::Nodes::set_name( $root_node, $sel->{"text"} );
                
#                 $state->{"tax_delete_taxa_button"} = 1;
#                 $state->{"tax_selections_menu"} = $index;
#             }
#             elsif ( $sel->{"type"} eq "functions" )
#             {


#             elsif ( $sel->{"type"} eq "functions" )
#             {
#                 # >>>>>>>>>>>>>>>>>>>>>>> ADD A SAVED GO COLUMN <<<<<<<<<<<<<<<<<<<<<<<

#                 $display = &Taxonomy::Viewer::add_go_column( $dbh, $sid, $display, $sel, undef, $root_id );
#                 $display = &Taxonomy::Display::set_col_styles( $display, $state->{"tax_root_id"} );
                
#                 $state->{"go_selections_menu"} = "";
#             }
        }

#         # >>>>>>>>>>>>>>>>>>>>>>>>> ADD GO PROJECTION <<<<<<<<<<<<<<<<<<<<<<<<

#         elsif ( $request eq "add_go_column" )
#         {
#             require GO::Menus;
            
#             $item = &GO::Menus::new_selection( $dbh, $state );
#             $item->{"id"} = 0;

#             $display = &Taxonomy::Viewer::add_go_column( $dbh, $sid, $display, $item, undef, $root_id );
#             $display = &Taxonomy::Display::set_col_styles( $display, $state->{"tax_root_id"} );
#         }

#         # >>>>>>>>>>>>>>>>>>>>>>>> ADD GO LINKS COLUMN <<<<<<<<<<<<<<<<<<<<<<<

#         elsif ( $request eq "add_link_column" )
#         {
#             $menu = &Taxonomy::Menus::create_data_items( $sid );
#             $item = &Common::Menus::get_item( $menu, $state->{"tax_data_menu"} );

#             $display = &Taxonomy::Viewer::add_link_column( $display, $item, undef, $root_id );
#         }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> TEXT SEARCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Searches the database for matches, starting at the chosen root node.
        # The subtree that exactly spans the matches are used for display. 

        elsif ( $request =~ /^search$/i )
        {
            $state->{"tax_root_id"} = $state->{"tax_search_id"};

            $display = &Taxonomy::Viewer::handle_text_search( \@message_list, $dbh, $sid, $display, $state );
        }

        # >>>>>>>>>>>>>>>>>>>>> ERROR IF WRONG REQUEST <<<<<<<<<<<<<<<<<<<<<<<<

        else {
            &error( qq (Wrong looking request -> "$request") );
        }
        
        # Clear fields in state that corresponds to the input form, so that
        # the request is not repeated with a reload,
    
        $state = &Taxonomy::Viewer::clear_user_input( $display, $state );

        &Common::File::store_file( $display_file, $display );
    }
    
    # Save state and display in files,
    
    &Taxonomy::State::save_state( $sid, $datpath, $state );
    
    # >>>>>>>>>>>>>>>>>>>>> ADD CELL HIGHLIGHT <<<<<<<<<<<<<<<<<<<<<<

    $display->highlight_sims_columns();
    $display->highlight_stats_columns();

    &Common::DB::disconnect( $dbh );

    # >>>>>>>>>>>>>>>>>>>>>> LAY OUT THE PAGE <<<<<<<<<<<<<<<<<<<<<<<

    $xhtml = &Taxonomy::Widgets::format_page( $sid, $display, $state, \@message_list );

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
         $display,     # Display structure
         $root_id,     # Starting node id
         ) = @_;

    # Returns an updated display structure.

    my ( $new_nodes, $nodes, $node, $p_nodes, $new_columns, $columns );

    $nodes = $display->nodes;

    $new_nodes = &Taxonomy::DB::open_node( $dbh, $root_id, 1, 3 );

    $nodes = &Taxonomy::Nodes::delete_subtree( $nodes, $root_id, 1 );
    
    $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $new_nodes, 1 );
    
    $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes );
    
    $node = &Taxonomy::Nodes::get_node( $nodes, $root_id );
    $nodes = &Taxonomy::DB_nodes::add_common_names( $dbh, $node, $nodes );

    $display->nodes( $nodes );

    $new_columns = &Taxonomy::Viewer::create_columns( $dbh, $sid, $display->columns, $nodes, $root_id );
    
    $display->merge_columns( $new_columns, $root_id );

    return $display;
}

sub seqs_to_client
{
    # Niels Larsen, January 2005.

    # TODO: unfinished. Different databases dont work, and ugliness. 

    # Returns a given set of RNA sequences to the browser. The user
    # selects taxa (subtrees) in the taxonomy; this routine then pulls
    # all RNAs that belong to the organisms in this subtree and prints
    # them to STDOUT in fasta format. The CGI header type is set to 
    # attachment, the default file name "RNA_seqs.fasta" is suggested
    # and there is a maximum of 10,000 sequences. 

    my ( $dbh,        # Database handle
         $display,    # Display structure
         $inputdb,   # Server database 
         $format,     # Sequence format - OPTIONAL, default "fasta"
         ) = @_;

    # Returns a string (error) or nothing (prints to STDOUT)

    my ( $cgi, $tax_idstr, @mol_ids, $module, $sql, $id, $org, $seq,
         $ids, $count, $nl, @messages, $length, $column, $searchdbs,
         $datatype, $org_sub, $seq_sub, $maxseqs, $maxseqstr, @tax_ids );

    $format = "fasta" if not defined $format;

    require Common::Users;

    $maxseqs = 10000;
    $maxseqstr = &Common::Util::commify_number( $maxseqs );

    # >>>>>>>>>>>>>>>>>>>>> GET CHECKED TAXON IDS <<<<<<<<<<<<<<<<<<<<<<<<

    $ids = $display->ids_selected;

    if ( not @{ $ids } )
    {
        @messages = [ "Error", "No taxa were seleced, please select at least one."
                      ." Please note that we set a maximum of $maxseqstr sequences per "
                      ." download. If more is needed, please try get them one large "
                      ." taxon at a time, or contact us. To see how many sequences are "
                      ." associated with each taxon, open the data menu above and select "
                      ." the corresponding counts." ];

        return wantarray ? @messages : \@messages;
    }

    # >>>>>>>>>>>>>>>>>>>>>>> EXPAND TAXON IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get all the ids of nodes in the subtrees clicked,

    foreach $id ( @{ $ids } )
    {
        push @tax_ids, &Taxonomy::DB::get_ids_subtree( $dbh, $id );
    }

    $tax_idstr = join ",", &Common::Util::uniqify( \@tax_ids );
    
    # >>>>>>>>>>>>>>>>>>>>>>> GET MOLECULE IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $inputdb =~ /_(\d+)$/;
    $length = $1;

    $searchdbs = Taxonomy::Menus->searchdbs_menu();
    $datatype = $searchdbs->match_option( "name" => $inputdb )->datatype;

    if ( &Common::Types::is_rna( $datatype ) )
    {
        $module = "RNA::DB";
        $sql = qq (select rna_id from rna_molecule where tax_id in ($tax_idstr) and length >= $length);
    }
    else {
        &error( qq (Wrong looking datatype -> "$datatype") );
    }

    eval "require $module";

    @mol_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    $count = scalar @mol_ids;

    if ( $count > $maxseqs )
    {
        $count = &Common::Util::commify_number( $count );
        @messages = [ "Error", "A total of $count sequences were selected. That is too"
                      ." many; we set a maximum of $maxseqstr per download because of server"
                      ." load. If you need more, please try get them one large taxon at"
                      ." a time. To see how many sequences are associated with each taxon,"
                      ." open the data menu above and select the corresponding counts." ];

        return wantarray ? @messages : \@messages;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> SEND TO CLIENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Find out about client newline, set header and print to STDOUT,
    # TODO: more formats.

    $nl = &Common::Users::get_client_newline();

    $cgi = new CGI;

    print $cgi->header( -type => "$datatype/$format", 
                        -attachment => "$inputdb.$format",
                        -expires => "+10y" );

    {
        no strict "refs";

        $org_sub = $module ."::get_organism";
        $seq_sub = $module ."::get_sequence";
        
        foreach $id ( @mol_ids )
        {
            $org = &{ $org_sub }( $dbh, $id );
            $seq = &{ $seq_sub }( $dbh, $id );
            
            print qq (>$org->{"name"}; NCBI Taxonomy ID: $org->{"tax_id"}$nl$seq$nl);
        }
    }

    return;
}

sub recover_sub
{
    # Niels Larsen, December 2005.

    # Returns a subroutine that moves the state and display files to dated 
    # versions, for later debugging. The subroutine returned should be called
    # by error handling routines and should return the viewer state. 

    my ( $sid,           # Session id
         $state,         # State hash
         ) =  @_;

    # Returns a subroutine reference. 

    my ( $subref, $datpath );

    $datpath = $state->{"inputdb"};

    $subref = sub 
    {
        require Common::File;
        require Common::Util;

        my ( $timestr, $state_file, $display_file, $saved_state, $display );

        $timestr = &Common::Util::epoch_to_time_string();

        $state_file = "$Common::Config::ses_dir/$sid/$datpath".".state";
        $display_file = "$Common::Config::ses_dir/$sid/$datpath"."_display";

        if ( -e $state_file )
        {
            $saved_state = &Common::File::retrieve_file( $state_file );
            &Common::File::store_file( "$state_file.error.$timestr", $saved_state );
            &Common::File::delete_file( $state_file );
        }

        if ( -e $display_file )
        {
            $display = &Common::File::retrieve_file( $display_file );
            &Common::File::store_file( "$display_file.error.$timestr", $display );
            &Common::File::delete_file( $display_file );
        }

        return $state;
    };
    
    return $subref;
}

sub save_selection 
{
    # Niels Larsen, November 2005.

    # Appends a selection option to the clipboard file under the users 
    # area. Error and success messages are generated to indicate if the 
    # the saving went ok or if there are missing information etc.
    
    my ( $sid,       # Session id
         $option,    # Option object
         $state,     # State hash
         ) = @_;

    # Returns a string. 

    my ( $menu, $name, $title, $count, $string, @messages );

    if ( not defined $option ) {
        &error( qq (No selection is given) );
    }
    
    if ( not $option->values or not @{ $option->values } ) {
        push @messages, [ "Error", "Please make a selection with the checkboxes." ];
    }

    if ( $option->title )
    {
        $menu = Common::Menus->clipboard_menu( $sid );

        $option->name( $menu->name );

        $name = $menu->name;
        $title = $option->title;

        if ( @{ $menu->match_options( "name" => $name, "title" => $title ) } )
        {
            push @messages, [ "Error", qq (The exact menu title "$title" has been
used for another selection before. Please try another one, lower- and upper case 
are regarded different.) ];
        }        
    }
    else {
        push @messages, [ "Error", "Please specify a menu title." ];
    }

    if ( not $option->coltext ) {
        push @messages, [ "Error", "Please specify a column title." ];
    }

    if ( not @messages )
    {
        $option->date( &Common::Util::time_string_to_epoch() );
        $count = scalar @{ $option->values };

        if ( $count == 1 ) {
            $string = "1 taxon"; 
        } else {
            $string = "$count taxa";
        }

        $menu->append_option( $option, 1 );
        $menu->write( $sid );

        $state->{"tax_has_selections"} = 1;
        
        push @messages, [ "Success", qq (
The selection, with $string, is saved. It is now in the User Menu above and on the 
the clipboard page (see under Analyze -&gt; Clipboard in the main menubar above),
where it can be deleted.) ];
    }

    if ( @messages ) {
        return wantarray ? @messages : \@messages;
    } else { 
        return;
    }
}

sub set_col_checkbox_values
{
    # Niels Larsen, November 2005.

    # TODO - broken, ids can be ambiguous

    # If there is a checkbox row in the given display, sets the values
    # for each column in a given list of ids and unsets the rest. 

    my ( $display,   # Display hash
         $ids,       # List of column ids
         $value,     # Value to set
         ) = @_;

    # Returns an updated display. 

    $value = 0 if not defined $value;

    my ( @options, $option, %ids );

    if ( @options = @{ $display->column_buttons->options } )
    {
        %ids = map { $_, 1 } @{ $ids };
    
        foreach $option ( @options )
        {
            if ( $ids{ $option->id } ) {
                $option->selected( $value );
            }
        }

        $display->column_buttons->options( \@options ); 
    }
    
    return $display;
}

sub set_row_button_state
{
    # Niels Larsen, January 2005.

    my ( $state,
         $item,
         ) = @_;

    my ( $datatype, $objtype );

    $state = &Taxonomy::Viewer::clear_row_buttons( $state );

    $datatype = $item->datatype;
    $objtype = $item->objtype;

    if ( $objtype =~ /^checkbox/ )
    {
        if ( $datatype eq "orgs_taxa" ) {
            $state->{"tax_save_taxa_button"} = 1;
        } elsif ( $datatype =~ /^download/ ) {
            $state->{"tax_rna_seqs_button"} = 1;
        }
    }
    else {
        &error( qq (Unrecognized object type -> "$objtype") );
    }

    return $state;
}

sub set_row_checkbox_values
{
    # Niels Larsen, November 2005.

    # If there is a checkbox column in the given display, sets the values
    # at the nodes in a given list of ids and unsets the rest. 

    my ( $display,   # Display hash
         $ids,       # List of node ids
         ) = @_;

    # Returns an updated display. 

    my ( $option, $cells, %ids, $id, $index );

    if ( defined ( $index = $display->columns->checkbox_option_index ) )
    {
        $option = $display->columns->checkbox_option;
        $cells = $option->values;

        %ids = map { $_, 1 } @{ $ids };

        foreach $id ( keys %{ $cells } )
        {
            if ( exists $ids{ $id } ) {
                $cells->{ $id }->selected( 1 );
            } else {
                $cells->{ $id }->selected( 0 );
            }
        }

        $option->values( $cells );
        $display->columns->replace_option_index( $option, $index );
    }

    return $display;
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
    
    $requests->{"show_tax_control_menu"} = [ "tax_control_menu_open", 1 ];
    $requests->{"hide_tax_control_menu"} = [ "tax_control_menu_open", 0 ];
    $requests->{"show_tax_data_menu"} = [ "tax_data_menu_open", 1 ];
    $requests->{"hide_tax_data_menu"} = [ "tax_data_menu_open", 0 ];
    $requests->{"show_go_selections_menu"} = [ "go_selections_menu_open", 1 ];
    $requests->{"hide_go_selections_menu"} = [ "go_selections_menu_open", 0 ];
    $requests->{"show_tax_selections_menu"} = [ "tax_selections_menu_open", 1 ];
    $requests->{"hide_tax_selections_menu"} = [ "tax_selections_menu_open", 0 ];
    $requests->{"show_tax_user_menu"} = [ "tax_user_menu_open", 1 ];
    $requests->{"hide_tax_user_menu"} = [ "tax_user_menu_open", 0 ];
    
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



#             elsif ( $key eq "gold_orgs_tsum" ) 
#             {
#                 if ( $node->{ $key } )
#                 {
#                     $links = "";
                    
#                     if ( $node->{"gold_orgs_node"} or $node->{"gold_orgs_cpub_node"} )
#                     {
#                         foreach $tuple ( @{ $node->{"gold_status"} } )
#                         {
#                             $id = $tuple->[0];
#                             $status = $tuple->[1];
                            
#                             if ( $status =~ /^complete$/i ) {
#                                 $img = qq (<img src="$Common::Config::img_url/gold_complete.gif" border="0" alt="Complete" />);
#                             } else {
#                                 $img = qq (<img src="$Common::Config::img_url/gold_incomplete.gif" border="0" alt="Incomplete" />);
#                             }
                            
#                             $url = qq ($Common::Config::cgi_url/index.cgi?session_id=$sid;page=gold_report;report_id=$id);
#                             $links .= qq (<a href="javascript:open_window('popup','$url',600,700)">$img</a>);
#                         }
#                     }
                    
#                     if ( $leaf_node or $node->{"gold_orgs_node"} == $node->{ $key } )
#                     {
#                         $xhtml .= qq (<td class="bullet_link">&nbsp;$links&nbsp;</td>);
#                     }
#                     else
#                     {
#                         $count = $node->{ $key };
                        
#                         if ( defined $count and $count <= 500 )
#                         {
#                             if ( $node->{ $key ."_expanded"} ) {
#                                 $xhtml .= qq (<td class="gold_button_down">);
#                             } else {
#                                 $xhtml .= qq (<td class="gold_button_up">);
#                             }
                            
#                             if ( $links ) {
#                                 $xhtml .= $links;
#                             }
                            
#                             if ( $node->{ $key ."_expanded"} ) {
#                                 $xhtml .= qq (&nbsp;<a href="javascript:collapse_node($node_id,'$key')">&nbsp;$count&nbsp;</a></td>);
#                             } else {
#                                 $xhtml .= qq (&nbsp;<a href="javascript:expand_node($node_id,'$key')">&nbsp;$count&nbsp;</a></td>);
#                             }
#                         }
#                         else
#                         {
#                             $xhtml .= qq (<td class="std_button_up">);
                            
#                             if ( defined $node->{"gold_orgs_node"} and $node->{"gold_orgs_node"} > 0 ) {
#                                 $count += $node->{"gold_orgs_node"};
#                             }
                            
#                             $xhtml .= qq (&nbsp;$count&nbsp;</td>);
#                         }
#                     }
#                 }
#                 else
#                 {
#                     $xhtml .= qq (<td></td>);
#                 }
#             }
            
#     if ( $key =~ /^gold_/ )
#     {
#         $stats = &Taxonomy::DB::get_stats( $dbh, $node_ids, $key );
        
#         # --------- Set values, status and style for nodes,

#         foreach $node_id ( @{ $node_ids } )
#         {
#             if ( exists $stats->{ $node_id } )
#             {
#                 $node = $stats->{ $node_id };

#                 $nodes->{ $node_id }->{"column_values"}->[ $index ] = [ $node->{"count"},
#                                                                         $node->{"sum_count"},
#                                                                         $node->{"pub_count"},
#                                                                         $node->{"pub_sum_count"} ];
#             }
#             else {
#                 $nodes->{ $node_id }->{"column_values"}->[ $index ] = [ undef, undef, undef, undef ];
#             }
            
#             $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
#         }
#     }
#     else
#     {


# sub gold_report
# {
#     # Niels Larsen, August 2003.

#     # Produces a report page for a single GOLD entry. 

#     my ( $session,   # CGI::Session object
#          $id,        # GOLD entry id
#          ) = @_;

#     # Returns a string. 

#     my ( $dbh, $entry, $sql, $xhtml, $title, @matches, $linkstr, $str, $pubstr, $statstr,
#          $width, $img );

#     $width = 20;

#     $dbh = &Common::DB::connect( $Common::Config::proj_name );
#     $entry = &GOLD::DB::get_entry( $dbh, $id );
#     &Common::DB::disconnect( $dbh );

#     $xhtml = &Common::Widgets::gold_title( "Genomes OnLine Database report" );

#     $xhtml .= qq (<table cellpadding="0" cellspacing="0">\n);

#     # >>>>>>>>>>>>>>>>>>>>>>>> ORGANISM <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $xhtml .= qq (
# <tr height="15"><td></td></tr>
# <tr><td colspan="3"><table class="gold_title"><tr><td>Organism Information</td></tr></table></td></tr>

# <tr><td width="$width"></td><td class="gold_key">Genus</td><td class="gold_value">&nbsp;$entry->{"genus"}</td></tr>
# <tr><td width="$width"></td><td class="gold_key">Species</td><td class="gold_value">&nbsp;$entry->{"species"}</td></tr>
# <tr><td width="$width"></td><td class="gold_key">Strain</td><td class="gold_value">&nbsp;$entry->{"strain"}</td></tr>
# <tr><td width="$width"></td><td class="gold_key">Taxonomy ID</td><td class="gold_value">&nbsp;$entry->{"tax_id_auto"}</td></tr>
# );

#     if ( $entry->{"chromosome"} ) {
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Taxonomy ID</td><td class="gold_value">&nbsp;$entry->{"tax_id_auto"}</td></tr>\n);
#     }

#     @matches = grep { $_->[2] eq "INF" } @{ $entry->{"webdata"} };
    
#     if ( @matches )
#     {
#         $linkstr = join ",&nbsp;", map { qq (<a href="$_->[1]">$_->[0]</a>) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Links</td><td class="gold_value">&nbsp;$linkstr</td></tr>\n);
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     if ( $entry->{"size"} =~ /[1-9]/ ) {
#         $entry->{"size"} = &Common::Util::commify_number( $entry->{"size"} );
#     } else {
#         $entry->{"size"} = "";
#     }

#     $entry->{"norfs"} = &Common::Util::commify_number( $entry->{"norfs"} );
    
#     if ( $entry->{"status"} =~ /^complete$/i ) {
#         $img = qq (<img src="$Common::Config::img_url/gold_complete.gif" border="0">);
#         $statstr = qq ($img&nbsp;&nbsp;<font color="green"><strong>&nbsp;$entry->{"status"}</strong></font>);
#     } else {
#         $img = qq (<img src="$Common::Config::img_url/gold_incomplete.gif" border="0">);
#         $statstr = qq ($img&nbsp;&nbsp;<strong>&nbsp;$entry->{"status"}</strong>);
#     }

#     if ( $entry->{"statrep"} ) {
#         $statstr .= qq (, <a href="$entry->{'statrep'}">status report</a>);
#     }
    
#     $pubstr = "";
    
#     if ( $entry->{"pub_journal"} ) {
#         $pubstr .= $entry->{"pub_journal"};
#     }
    
#     if ( $entry->{"pub_vol"} ) {
#         $pubstr .= " " . $entry->{"pub_vol"};
#     }
    
#     $xhtml .= qq (
# <tr><td colspan="3"><table class="gold_title"><tr><td>Source Data</td></tr></table></td></tr>

# <tr><td width="$width"></td><td class="gold_key">Status</td><td class="gold_value">&nbsp;$statstr</td></tr>
# <tr><td width="$width"></td><td class="gold_key">Sequence type</td><td class="gold_value">&nbsp;$entry->{"type"}</td></tr>
# <tr><td width="$width"></td><td class="gold_key">DNA size</td><td class="gold_value">&nbsp;$entry->{"size"}</td></tr>
# <tr><td width="$width"></td><td class="gold_key">ORFs</td><td class="gold_value">&nbsp;$entry->{"norfs"}</td></tr>
# <tr><td width="$width"></td><td class="gold_key">Publication</td><td class="gold_value">&nbsp;$pubstr</td></tr>
# );

#     @matches = ();

#     if ( $entry->{"pub_lnk"} ) {
#         push @matches, [ "Abstract", $entry->{"pub_lnk"} ];
#     }

#     if ( $entry->{"maplnk"} ) {
#         push @matches, [ "Gene Table", $entry->{"maplnk"} ];
#     }

#     if ( @matches )
#     {
#         $linkstr = join ",&nbsp;", map { qq (<a href="$_->[1]">$_->[0]</a>) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Publication links</td><td class="gold_value">&nbsp;$linkstr</td></tr>\n);
#     }

#     @matches = grep { $_->[2] eq "DAT" or $_->[2] eq "ANLY" } @{ $entry->{"webdata"} };

#     if ( @matches )
#     {
#         $linkstr = join ",&nbsp;", map { qq (<a href="$_->[1]">$_->[0]</a>) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Analysis links</td><td class="gold_value">&nbsp;$linkstr</td></tr>\n);
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>> DATA SOURCE <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     $xhtml .= qq (
# <tr><td colspan="3"><table class="gold_title"><tr><td>Institutions and Funding</td></tr></table></td></tr>
# );

#     @matches = grep { $_->[2] eq "INST" } @{ $entry->{"webdata"} };

#     if ( @matches )
#     {
#         $str = join ",&nbsp;", map { qq (<a href="$_->[1]">$_->[0]</a>) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Institutions</td><td class="gold_value">&nbsp;$str</td></tr>\n);
#     }
#     else {
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Institutions</td><td>&nbsp;</td></tr>\n);
#     }

#     @matches = grep { $_->[2] eq "FUND" } @{ $entry->{"webdata"} };

#     if ( @matches )
#     {
#         $str = join ",&nbsp;", map { qq (<a href="$_->[1]">$_->[0]</a>) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Funding</td><td class="gold_value">&nbsp;$str</td></tr>\n);
#     }
#     else {
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Funding</td><td>&nbsp;</td></tr>\n);
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> CONTACT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     @matches = grep { $_->[2] eq "CONT" } @{ $entry->{"webdata"} };

#     if ( @matches )
#     {
#         $xhtml .= qq (
# <tr><td colspan="3"><table class="gold_title"><tr><td>Contact Information</td></tr></table></td></tr>
# );
#         $str = join ",&nbsp;", map { qq ($_->[0]) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Name</td><td class="gold_value">&nbsp;$str</td></tr>\n);

#         $str = join ",&nbsp;", map { qq ($_->[3]) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">E-address</td><td class="gold_value">&nbsp;$str</td></tr>);

#         $str = join ",&nbsp;", map { qq (<a href="$_->[1]">$_->[1]</a>) } @matches;
#         $xhtml .= qq (<tr><td width="$width"></td><td class="gold_key">Home Page</td><td class="gold_value">&nbsp;$str</td></tr>);
#     }

#     $xhtml .= qq (\n</table>\n);

#     $xhtml .= qq (<table width="100%"><tr height="60"><td align="right" valign="bottom">
# <div class="gold_author">data maintained by <strong>Nikos Kyrpides</strong> at Integrated Genomics Inc.</div>
# </td></tr></table>\n);

#     return $xhtml;
# }


# sub add_checkbox_row
# {
#     # TODO - looks wrong 

#     # Niels Larsen, February 2004.
    
#     # Sets the "checked" key in all column elements, default 0. This will 
#     # cause a row with checkboxes to appear on the page just above the column
#     # headers. 

#     my ( $sid,
#          $display,       # Display structure
#          $request,       # Menu options index 
#          $value,         # Whether checkboxes are checked - OPTIONAL, default 1
#          ) = @_;

#     # Returns an updated display structure. 

#     my ( $elem, $menu, $item );
    
#     foreach $item ( @{ &Taxonomy::Menus::create_control_items( $sid ) } )
#     {
#         if ( $item->{"request"} eq $request ) 
#         {
#             $menu = $item->{"text"};
#             last;
#         }
#     }

#     if ( not defined $menu ) {
#         &error( qq (Request not found in control menu -> "$request") );
#     }
    
#     # --------- Defaults,

#     if ( defined $value ) {
#         $value = 1;
#     } else {
#         $value = 0;
#     }

#     foreach $elem ( @{ $display->{"headers"} } )
#     {
#         $elem->{"checked"} = $value;
#     }

#     return wantarray ? %{ $display } : $display;
# }    

# sub add_go_column
# {
#     # TODO broken

#     # Niels Larsen, February 2004.
    
#     # Adds a column of GO statistics to the left of the tree. If no 
#     # insert position is given its done immediately next to the tree. 

#     my ( $dbh,           # Database handle
#          $sid,           # Session id
#          $display,       # Display structure
#          $item,          # Menu index or option to add 
#          $index,         # Column index where to insert - OPTIONAL
#          $root_id,       # Root node id - OPTIONAL
#          ) = @_;

#     # Returns an updated display structure. 

#     my ( $columns, $nodes, $node_ids, $node_id, @match, $count, 
#          $idstr, $options, $sum_count, $sum_ids, $stats, $go_ids, $column,
#          $go_id, $ids );

#     require GO::Menus;
#     require GO::DB;

#     $columns = $display->columns;
#     $nodes = $display->nodes;

#     # If there is already a column of the given type and key then we 
#     # dont overwrite it but just return. If not then we set the index
#     # to the column just after the last so a column will be added,

#     $idstr = join ",", @{ $item->{"ids"} };
    
#     if ( not defined $index )
#     {
#         if ( @match = grep { $_->{"type"} eq $item->{"type"} and 
#                                  ( join ",", @{ $_->{"ids"} } ) eq $idstr } @{ $columns } )
#         {
#             if ( scalar @match == 1 ) {
#                 return $display;
#             } else {
#                 &error( qq (More than one checkbox column found) );
#             }
#         }
#         else {
#             $index = scalar @{ $columns };
#         }
#     }

#     # --------- Expand GO ids to a unique set,

#     foreach $go_id ( @{ $item->{"ids"} } )
#     {
#           push @{ $go_ids }, &GO::DB::get_ids_subtree( $dbh, $go_id );
#         push @{ $go_ids }, $go_id;
#     }

#     $go_ids = &Common::Util::uniqify( $go_ids );

#     # --------- Get ids of nodes to update and the statistics,

#     if ( defined $root_id )
#     {
#         $node_ids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
#         $stats = &Taxonomy::DB::get_go_stats( $dbh, $go_ids, $root_id );
#     }
#     else
#     {
#         $node_ids = &Taxonomy::Nodes::get_ids_all( $nodes );
#         $stats = &Taxonomy::DB::get_go_stats( $dbh, $go_ids );
#     }

#     # --------- Get statistics column and add keys,
    
#     $column = &Taxonomy::Display::new_stats_column( $node_ids );

#     $column = &Taxonomy::Display::get_column( $display, $index );
#     $column = &Taxonomy::Display::set_column_cells( $column, $stats );
# #    $column = &Taxonomy::Display::set_column_bgramp( $column, "sum_count", "#cccccc", "#ffffff", $root_id );

#     $column = &Taxonomy::Display::set_col_attribs( $column, "css", "std_button_up" );
#     $column = &Taxonomy::Display::set_col_attribs( $column, "type", $item->{"type"} );
#     $column = &Taxonomy::Display::set_col_attribs( $column, "key", $item->{"key"} );
#     $column = &Taxonomy::Display::set_col_attribs( $column, "abbreviate", 1 );

#     # --------- Add column to display,

#     $display = &Taxonomy::Display::set_header( $display, $item, $index );
#     $display = &Taxonomy::Display::set_column( $display, $column, $index );

#     return $display;
# }    

# sub set_row_checkbox_values
# {
#     # Niels Larsen, February 2004.

#     # If there is a checkbox column in the given display, sets the values
#     # at the nodes in a given list of ids and unsets the rest. 

#     my ( $display,   # Display hash
#          $ids,       # List of node ids
#          ) = @_;

#     # Returns an updated display. 

#     my ( $columns, $header, %ids, $id, $nodes, $index );

#     $index = 0;
#     $columns = $display->columns;

#     foreach $header ( $columns->options )
#     {
#         last if &Taxonomy::Display::is_select_item( $header );
#         $index += 1;
#     }

#     if ( $index <= $columns->options_count - 1 )
#     {
#         $header = $columns->[$index];

#         %ids = map { $_, 1 } @{ $ids };
        
#         $nodes = $display->{"nodes"};
        
#         foreach $id ( &Taxonomy::Nodes::get_ids_all( $nodes ) )
#         {
#             if ( exists $ids{ $id } ) {
#                 $nodes->{ $id }->{"column_values"}->[ $index ] = 1;
#             } else {
#                 $nodes->{ $id }->{"column_values"}->[ $index ] = 0;
#             }
#         }
        
#         $display->{"nodes"} = $nodes;   # not necessary 
#     }

#     return wantarray ? %{ $display } : $display;
# }    
