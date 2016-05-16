package Disease::DB;        #  -*- perl -*-

# Database accessor routines for the Disease viewer. Most of the routines 
# simply invoke similarly named routines from the Common::DAG::DB module, 
# but with fewer arguments. 

use strict;
use warnings;

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &get_children
                 &get_entry
                 &get_ids_subtree
                 &get_id_of_name
                 &get_name_of_id
                 &get_node
                 &get_nodes
                 &get_nodes_all
                 &get_nodes_parents
                 &get_parents
                 &get_xrefs
                 &get_statistics
                 &get_tree_ids
                 &get_subtree

                 &open_node
                 &focus_node
                 &expand_do_node
                 &expand_tax_node

                 &text_search
                 );

use Common::DAG::Schema;
use Common::DAG::DB;
use Common::DAG::Nodes;
use Common::DB;
use Common::Messages;

1; 
__END__

# >>>>>>>>>>>>>>>>>>>>>>>> SET GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $def_table = "do_def";
our $edges_table = "do_edges";
our $synonyms_table = "do_synonyms";
our $xrefs_table = "do_xrefs";
our $stats_table = "do_stats";
our $id_name = "do_id";

our $select_def = "$def_table.$id_name,parent_ids,name,leaf,rel";

$Common::DAG::Schema::db_prefix = "do";
$Common::DAG::Schema::def_table = $def_table;
$Common::DAG::Schema::edges_table = $edges_table;
$Common::DAG::Schema::synonyms_table = $synonyms_table;
$Common::DAG::Schema::xrefs_table = $xrefs_table;
$Common::DAG::Schema::stats_table = $stats_table;
$Common::DAG::Schema::id_name = $id_name;

$Common::DAG::DB::id_name = $id_name;
$Common::DAG::Nodes::id_name = $id_name;

our $sql_no_cache = ""; # sql_no_cache";

# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get_children
{
    # Niels Larsen, October 2004.

    my ( $dbh,
         $id,
         ) = @_;

    my ( $nodes, $tables, $select );

    $tables = "$edges_table natural join $def_table";
    $select = "$edges_table.$id_name,name";

    $nodes = &Common::DAG::DB::get_children( $dbh, $id, $tables, $edges_table, $select );

    return wantarray ? %{ $nodes } : $nodes;
}    

sub get_entry
{
    # Niels Larsen, October 2004.

    # Returns a hash structure with all the information about a given 
    # term id that the system supports. 

    my ( $dbh,      # Database handle
         $id,       # Entry id
         ) = @_;

    # Returns a hash.

    if ( not defined $id ) {
        &error( qq (Input entry ID is undefined) );
        exit;
    }

    my ( $entry, $sql, @matches, $match, $p_nodes, $p_node, $terms,
         $c_nodes, $c_node );

    $entry->{ $id_name } = $id;

    # -------- do_def table,

    $sql = qq (select name,deftext,comment from $def_table where $id_name = $id);

    ( $entry->{"name"},
      $entry->{"description"},
      $entry->{"comment"} ) = @{ &Common::DB::query_array( $dbh, $sql )->[0] };

    # -------- do_edges table,

    $entry->{"parents"} = [];

    @matches = ();

    $p_nodes = &Disease::DB::get_parents( $dbh, $id );

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $p_nodes ) )
    {
        $sql = qq (select do_terms_tsum from do_stats where $id_name = $id);
        $terms = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        $p_node = $p_nodes->{ $id };
        push @matches, [ $id, $p_node->{"name"}, $terms ];
    }
    
    foreach $match ( sort { $a->[2] <=> $b->[2] } @matches )
    {
        push @{ $entry->{"parents"} }, {
            $id_name => $match->[0],
            "name" => $match->[1],
            "terms_total" => $match->[2],
        };
    }

    $entry->{"children"} = [];

    @matches = ();

    $c_nodes = &Disease::DB::get_children( $dbh, $id );

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $p_nodes ) )
    {
        $sql = qq (select do_terms_tsum from do_stats where $id_name = $id);
        $terms = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        $c_node = $c_nodes->{ $id };
        push @matches, [ $id, $c_node->{"name"}, $terms ];
    }
    
    foreach $match ( sort { $a->[2] <=> $b->[2] } @matches )
    {
        push @{ $entry->{"children"} }, {
            $id_name => $match->[0],
            "name" => $match->[1],
            "terms_total" => $match->[2],
        };
    }

    # -------- do_synonyms table,

    $entry->{"synonyms"} = [];

    $sql = qq (select distinct syn,rel from $synonyms_table where $id_name = $id);
    @matches = @{ &Common::DB::query_array( $dbh, $sql ) };
    
    foreach $match ( @matches )
    {
        push @{ $entry->{"synonyms"} }, {
            "synonym" => $match->[0],
            "relation" => $match->[1],
        };
    }
        
    # -------- do_xrefs table,

    $entry->{"references"} = [];

    $sql = qq (select distinct db,name from $xrefs_table where $id_name = $id);
    @matches = @{ &Common::DB::query_array( $dbh, $sql ) };
    
    foreach $match ( @matches )
    {
        push @{ $entry->{"references"} }, { 
            "db_name" => $match->[0],
            "db_id" => $match->[1],
        };
    }

    return $entry;
}
    
sub get_ids_subtree
{
    # Niels Larsen, October 2004.

    # Returns the ids of the subtree starting at a given root id.
    # The root id is not included in the output list. 

    my ( $dbh,   # Database handle
         $nid,   # Node id
         ) = @_;

    # Returns an array.

    my ( $sql, @do_ids );

    $sql = qq (select $sql_no_cache distinct $id_name from $edges_table where parent_id = $nid);

    @do_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    return wantarray ? @do_ids : \@do_ids;
}
    
sub get_id_of_name
{
    # Niels Larsen, October 2004.

    # Returns a node id given a node name. 

    my ( $dbh,       # Database handle
         $name,      # Node name
         ) = @_;

    # Returns an integer. 

    return &Common::DAG::DB::get_id_of_name( $dbh, $name, $def_table );
}

sub get_name_of_id
{
    # Niels Larsen, October 2004.

    # Returns a node name given a node id. 

    my ( $dbh,       # Database handle
         $id,        # Node id
         ) = @_;

    # Returns an integer. 

    return &Common::DAG::DB::get_name_of_id( $dbh, $id, $def_table );
}

sub get_node
{
    # Niels Larsen, October 2004.

    # Returns a single node with a given id.

    my ( $dbh,       # Database handle
         $id,        # Node id
         $select,    # List of field names - OPTIONAL 
         ) = @_;

    # Returns a nodes hash.

    my ( $node, $tables );

    $tables = "$edges_table natural join $def_table";
    $select = $select_def if not $select;

    $node = &Common::DAG::DB::get_node( $dbh, $id, $tables, $edges_table, $select );

    return wantarray ? %{ $node } : $node;
}

sub get_nodes
{
    # Niels Larsen, October 2004.

    # Fetches all nodes for a given set of node ids. 

    my ( $dbh,        # Database handle
         $ids,        # List of ids
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $tables );

    $tables = "$edges_table natural join $def_table";
    $select = $select_def if not $select;

    $nodes = &Common::DAG::DB::get_nodes( $dbh, $ids, $tables, $edges_table, $select );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_all
{
    # Niels Larsen, October 2004.

    # Fetches all nodes. 

    my ( $dbh,        # Database handle
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $tables );

    $tables = "$edges_table natural join $def_table";
    $select = $select_def if not $select;

    $nodes = &Common::DAG::DB::get_nodes_all( $dbh, $tables, $edges_table, $select );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_parents
{
    # Niels Larsen, October 2004.

    # Fetches all parent nodes of one or more given nodes. 

    my ( $dbh,      # Database handle
         $nodes,    # Starting nodes or ids 
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 

    my ( $p_nodes, $tables );

    $tables = "$edges_table natural join $def_table";
    $select = $select_def if not $select;

    $p_nodes = &Common::DAG::DB::get_nodes_parents( $dbh, $nodes, $tables, $edges_table, $select );
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_parents
{
    # Niels Larsen, October 2004.

    # Fetches all parent nodes of a given node. 

    my ( $dbh,      # Database handle
         $id,       # Starting node or id 
         $select,   # List of field names - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 

    my ( $p_nodes, $tables );

    if ( ref $id ) { 
        $id = $id->{ $id_name };
    }

    $tables = "$edges_table natural join $def_table";
    $select = $select_def if not $select;

    $p_nodes = &Common::DAG::DB::get_parents( $dbh, $id, $tables, $edges_table, $select );
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_xrefs
{
    # Niels Larsen, October 2004.

    # Returns a hash structure where key is id and value is 
    # a database cross-reference. 

    my ( $dbh,   # Database handle
         $db,    # Cross-reference database, e.g. ICD9
         $ids,   # Node ids - OPTIONAL
         ) = @_;
   
    my ( $nodes );

    $nodes = &Common::DAG::DB::get_xrefs( $dbh, "do_xrefs", "do_id,name", "db = '$db'", $ids );
    
    return wantarray ? %{ $nodes } : $nodes;
}

sub get_tree_ids
{
    # Niels Larsen, October 2004.

    # Returns all nodes that correspond to a given list of ids, plus 
    # all their parents. 

    my ( $dbh,      # Database handle
         $ids,      # Node ids
         $select,   # Output fields  
         ) = @_;

    # Returns a node hash.

    my ( $idstr, $nodes, $p_nodes );

    if ( ref $ids eq "ARRAY" ) {
        $idstr = join ",", @{ $ids };
    } elsif ( ref $ids eq "SCALAR" ) {
        $idstr = $ids;
    } else {
        &error( qq (The \$ids variable should be either a string with )
                                . qq (comma-separated ids or a list of ids) );
        exit;
    }

    $nodes = &Common::DAG::DB::get_nodes( $dbh, $ids, $select );
    $p_nodes = &Common::DAG::DB::get_nodes_parents( $dbh, $ids, $select );

    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_subtree
{
    # Niels Larsen, October 2004.

    # For a given node id, fetches all nodes that make up the subtree
    # that starts at the node, the given node included. 

    my ( $dbh,      # Database handle
         $id,       # Node or id of starting node
         $select,   # Output fields  
         ) = @_;

    # Returns a node hash.

    my ( $nodes, $tables );

    $select = $select_def if not $select;
    $tables = "$def_table natural join $edges_table";

    $nodes = &Common::DAG::DB::get_subtree( $dbh, $id, $tables, $edges_table, $select );

    return wantarray ? %{ $nodes } : $nodes;
}

sub open_node
{
    # Niels Larsen, October 2004.

    # Returns the nodes that comprise the subtree starting at a given 
    # node and down to a given depth. If a node has less than a given
    # number of children, the routine will keep expanding it until the
    # number is exceeded or until there are leaves only.

    my ( $dbh,      # Database handle
         $nid,      # Starting node id 
         $depth,    # How many levels to open - OPTIONAL, default 1
         $min,      # Minimum number of nodes to show - OPTIONAL
         ) = @_;

    # Returns a nodes hash.

    $depth ||= 1;   # zero makes no sense
    $min ||= 3;     # zero makes no sense
    
    my ( $tables, $nodes, $node, $count, $last_count );

    $tables = "$def_table natural join $edges_table";

    $nodes = &Common::DAG::DB::get_subtree( $dbh, $nid, $tables, $edges_table, $select_def,
                                            "$edges_table.parent_id = $nid and dist <= $depth" );

    if ( defined $min )
    {
        $count = scalar @{ &Common::DAG::Nodes::get_ids_all( $nodes ) };
        
        # It is tedious to click 5 levels down just to find a single leaf.
        # So if there is only one child node we open the nodes further until
        # either 1) more than one children appear or 2) we reach a leaf. 
        
        if ( $count <= $min )
        {
            $last_count = $count;
            
            while ( $count <= $last_count + 1 )
            {
                $nodes = &Common::DAG::DB::get_subtree( $dbh, $nid, $tables, $edges_table, $select_def,
                                                        "do_edges.parent_id = $nid and dist <= " . ++$depth );
                
                $last_count = $count;
                $count = scalar @{ &Common::DAG::Nodes::get_ids_all( $nodes ) };
            }
        }
    }
    
    return wantarray ? %{ $nodes } : $nodes;
}

sub expand_node
{
    # Niels Larsen, October 2004.

    # Replaces the subtree starting at a given node with the minimal
    # subtree that spans the nodes that have a certain attribute set.
    
    my ( $dbh,      # Database handle
         $nid,      # Starting node id 
         $key,      # Column key 
         ) = @_;

    # Returns an updated nodes hash. 

    my ( $select, $tables, $where, $nodes );

    $tables = "$edges_table natural join $def_table";
    $select = "$select_def,children_ids";
    $where = "$key > 0 and do_edges.parent_id = $nid";

    $nodes = &Common::DAG::DB::get_subtree( $dbh, $nid, $tables, $edges_table, $select, $where );

    return wantarray ? %{ $nodes } : $nodes;
}

sub text_search
{
    # Niels Larsen, October 2004.

    # Searches the name fields of a given subtree. The search includes either
    # titles (with synonyms), descriptions, external names or all text. The 
    # routine creates a nodes hash that spans all the matches and starts at the 
    # current root node. The empty nodes are included down to one level below
    # the starting node, so one can see which nodes did not match.

    my ( $dbh,            # Database handle
         $root_id,        # Root id
         $search_text,    # Search text
         $search_type,    # Search type
         $search_target,  # Search target
         ) = @_;

    # Returns a nodes hash.

    my ( $root_node, $p_nodes, $nodes, $node, $sql, $id, @desc_ids,
         @ids, @tit_ids, @syn_ids, %ids, $tables, $select, $match_name,
         $match_syn, $match_desc, $match_ref, $match_nodes, @ref_ids );

    $root_node = &Disease::DB::get_node( $dbh, $root_id );

    # ---------- prepare search type strings,
    
    if ( $search_type eq "whole_words" )
    {
        $match_name = qq ( match(do_def.name) against ('$search_text'));
        $match_syn = qq ( match(do_synonyms.syn) against ('$search_text'));
        $match_desc = qq ( match(do_def.deftext) against ('$search_text'));
        $match_ref = qq ( do_xrefs.name like '$search_text');
    }
    elsif ( $search_type eq "name_beginnings" )
    {
        $match_name = qq ( do_def.name like '$search_text%');
        $match_syn = qq ( do_synonyms.syn like '$search_text%');
        $match_desc = qq ( do_def.deftext like '$search_text%');
        $match_ref = qq ( do_xrefs.name like '$search_text%');
    }
    elsif ( $search_type eq "partial_words" )
    {
        $match_name = qq ( do_def.name like '%$search_text%');
        $match_syn = qq ( do_synonyms.syn like '%$search_text%');
        $match_desc = qq ( do_def.deftext like '%$search_text%');
        $match_ref = qq ( do_xrefs.name like '%$search_text%');
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
    elsif ( $search_target eq "icd9" )
    {
        $tables = qq (do_edges natural join do_xrefs);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_ref);
        @ref_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } @ref_ids;
        @ids = keys %ids;
    }
    elsif ( $search_target eq "titles" )
    {
        $tables = qq (do_edges natural join do_def);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } @tit_ids;
        @ids = keys %ids;
    }
    elsif ( $search_target eq "titles_synonyms" )
    {
        $tables = qq (do_edges natural join do_def);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq (do_edges natural join do_synonyms);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_syn);
        @syn_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } ( @tit_ids, @syn_ids );
        @ids = keys %ids;
    }
    elsif ( $search_target eq "descriptions" )
    {
        $tables = qq (do_edges natural join do_def);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_desc);
        @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    }        
    elsif ( $search_target eq "everything" )
    {
        $tables = qq (do_edges natural join do_def);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq (do_edges natural join do_synonyms);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_syn);
        @syn_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq (do_edges natural join do_def);
        $sql = qq (select do_edges.$id_name from $tables where do_edges.parent_id = $root_id and $match_desc);
        @desc_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } ( @tit_ids, @syn_ids, @desc_ids );
        @ids = keys %ids;
    }
    else {
        &error( qq (Unknown search target -> "$search_target") );
    }

    return wantarray ? @ids : \@ids;
}

1;

__END__
