package Anatomy::DB;        #  -*- perl -*-

# Accessor routines for the anatomy viewer. This library in turn uses
# the Common::DAG::DB module which is generic for DAG viewers.
#
# The table names used here could have been written into each routine
# since they are all specific to one viewer; but, there will be more
# than one anatomy ontology (human, mouse, plant, .. ) for which we 
# want different data tables but the same code. So the viewer sets 
# the table names in this module as first thing it does. 
#
# The Common::DAG::Nodes module is for memory manipulation of the 
# nodes. The Common::DAG::Schema file lists the tables and fields 
# that a minimal DAG database must have.

use strict;
use warnings;

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 $db_prefix
                 $id_name
                 $def_table
                 $edges_table
                 $synonyms_table
                 $xrefs_table
                 $stats_table

                 &expand_node
                 &focus_node
                 &get_children
                 &get_fly_entry
                 &get_plant_entry
                 &get_id_of_name
                 &get_ids_subtree
                 &get_name_of_id
                 &get_node
                 &get_nodes
                 &get_nodes_all
                 &get_nodes_parents
                 &get_parents
                 &get_xrefs
                 &get_statistics
                 &open_node
                 &text_search
                 );

use Common::DAG::DB;
use Common::DAG::Nodes;
use Common::DB;
use Common::Messages;

our ( $db_prefix, $id_name, $def_table, $edges_table, $synonyms_table,
      $xrefs_table, $stats_table );

our $sql_cache = "sql_cache";

# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get_children
{
    # Niels Larsen, October 2004.

    # Retrieves the immediate children nodes, one level down, for a 
    # given node id. Each node includes id, name, leaf flag and 
    # relation id. 

    my ( $dbh,    # Database handle
         $nid,    # Node id
         ) = @_;

    # Returns a node hash.

    my ( $nodes, $tables, $select );

    $select = "$edges_table.$id_name,$edges_table.leaf,$edges_table.$id_name,$def_table.name";

    $nodes = &Common::DAG::DB::get_children( $dbh, $nid, $select, $def_table, $edges_table );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_fly_entry
{
    # Niels Larsen, October 2004.

    # Returns a hash structure with all information about a given term id.

    my ( $dbh,      # Database handle
         $id,       # Term id
         ) = @_;

    # Returns a hash.

    my ( $entry, $sql, @matches, $match, $p_nodes, $p_node, $terms,
         $c_nodes, $c_node );

    if ( not defined $id ) {
        &error( qq (Input entry ID is undefined) );
        exit;
    }

    $entry->{ $id_name } = $id;

    # -------- definitions table,

    $sql = qq (select name,deftext,comment from $def_table where $id_name = $id);

    ( $entry->{"name"},
      $entry->{"description"},
      $entry->{"comment"} ) = @{ &Common::DB::query_array( $dbh, $sql )->[0] };

    # -------- edges table,

    $entry->{"parents"} = [];

    @matches = ();

    $p_nodes = &Anatomy::DB::get_parents( $dbh, $id );

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $p_nodes ) )
    {
        $sql = qq (select flyo_terms_tsum from flyo_stats where $id_name = $id);
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

    $c_nodes = &Anatomy::DB::get_children( $dbh, $id );

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $c_nodes ) )
    {
        $sql = qq (select flyo_terms_tsum from flyo_stats where $id_name = $id);
        $terms = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        $c_node = $c_nodes->{ $id };
        push @matches, [ $id, $c_node->{"name"}, $terms ];
    }
    
    foreach $match ( sort { $a->[1] cmp $b->[1] } @matches )
    {
        push @{ $entry->{"children"} }, {
            $id_name => $match->[0],
            "name" => $match->[1],
            "terms_total" => $match->[2],
        };
    }

    # -------- synonyms table,

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
        
    # -------- cross-references table,

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
    
sub get_plant_entry
{
    # Niels Larsen, October 2004.

    # Returns a hash structure with all information about a given term id.

    my ( $dbh,      # Database handle
         $id,       # Term id
         ) = @_;

    # Returns a hash.

    my ( $entry, $sql, @matches, $match, $p_nodes, $p_node, $terms,
         $c_nodes, $c_node );

    if ( not defined $id ) {
        &error( qq (Input entry ID is undefined) );
        exit;
    }

    $entry->{ $id_name } = $id;

    # -------- definitions table,

    $sql = qq (select name,deftext,comment from $def_table where $id_name = $id);

    ( $entry->{"name"},
      $entry->{"description"},
      $entry->{"comment"} ) = @{ &Common::DB::query_array( $dbh, $sql )->[0] };

    # -------- edges table,

    $entry->{"parents"} = [];

    @matches = ();

    $p_nodes = &Anatomy::DB::get_parents( $dbh, $id );

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $p_nodes ) )
    {
        $sql = qq (select po_terms_tsum from po_stats where $id_name = $id);
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

    $c_nodes = &Anatomy::DB::get_children( $dbh, $id );

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $c_nodes ) )
    {
        $sql = qq (select po_terms_tsum from po_stats where $id_name = $id);
        $terms = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        $c_node = $c_nodes->{ $id };
        push @matches, [ $id, $c_node->{"name"}, $terms ];
    }
    
    foreach $match ( sort { $a->[1] cmp $b->[1] } @matches )
    {
        push @{ $entry->{"children"} }, {
            $id_name => $match->[0],
            "name" => $match->[1],
            "terms_total" => $match->[2],
        };
    }

    # -------- synonyms table,

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
        
    # -------- cross-references table,

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

sub get_ids_subtree
{
    # Niels Larsen, October 2004.

    # Returns the ids of the subtree starting at a given parent id.
    # The parent id is not included in the output list. 

    my ( $dbh,   # Database handle
         $pid,   # Node id
         ) = @_;

    # Returns an array.

    my ( @ids );

    @ids = &Common::DAG::DB::get_ids_subtree( $dbh, $pid, $edges_table );

    return wantarray ? @ids : \@ids;
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

    my ( $dbh,        # Database handle
         $id,         # Node id
         $add_cids,   # Add children ids - OPTIONAL (default on) 
         $add_pids,   # Add parents ids - OPTIONAL (default on) 
         ) = @_;

    # Returns a nodes hash.

    my ( $node, $select );

    $select = "$def_table.$id_name,$def_table.name";

    $node = &Anatomy::DB::get_nodes( $dbh, [ $id ], $select, $def_table, 
                                     $edges_table )->{ $id };

    return wantarray ? %{ $node } : $node;
}

sub get_nodes
{
    # Niels Larsen, October 2004.

    # Fetches all nodes for a given set of node ids. 

    my ( $dbh,        # Database handle
         $ids,        # List of ids
         $add_cids,   # Add children ids - OPTIONAL (default on) 
         $add_pids,   # Add parents ids - OPTIONAL (default on) 
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $table, $select );

    $add_cids = 1 if not defined $add_cids;
    $add_pids = 1 if not defined $add_pids;

    $select = "$def_table.$id_name,$def_table.name";
    $table = $def_table;

    $nodes = &Common::DAG::DB::get_nodes( $dbh, $ids, $select, $table, $edges_table );

    if ( $add_cids ) {
        $nodes = &Common::DAG::DB::add_children_ids( $dbh, $nodes, $edges_table, $ids );
    }

    if ( $add_pids ) {
        $nodes = &Common::DAG::DB::add_parent_ids( $dbh, $nodes, $edges_table, $ids );
    }

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_all
{
    # Niels Larsen, October 2004.

    # Fetches all nodes, with 'leaf' and 'rel' keys included. 

    my ( $dbh,        # Database handle
         $add_cids,   # Add children ids - OPTIONAL (default on) 
         $add_pids,   # Add parents ids - OPTIONAL (default on) 
         ) = @_;
    
    # Returns a hash of hashes.
    
    my ( $nodes, $table, $select, $ids );

    $add_cids = 1 if not defined $add_cids;
    $add_pids = 1 if not defined $add_pids;

    $select = "$def_table.$id_name,$def_table.name";
    $table = $def_table;

    $nodes = &Common::DAG::DB::get_nodes_all( $dbh, $select, $table, $edges_table );

    if ( $add_cids ) {
        $nodes = &Common::DAG::DB::add_children_ids( $dbh, $nodes, $edges_table );
    }
    
    if ( $add_pids ) {
        $nodes = &Common::DAG::DB::add_parent_ids( $dbh, $nodes, $edges_table );
    }

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_parents
{
    # Niels Larsen, October 2004.

    # Fetches all parent nodes of one or more given nodes. 

    my ( $dbh,        # Database handle
         $nodes,      # Starting nodes or ids 
         $add_cids,   # Add children ids - OPTIONAL (default on) 
         $add_pids,   # Add parents ids - OPTIONAL (default on) 
         ) = @_;

    # Returns a nodes hash. 

    my ( $p_nodes, $table, $select, @ids );

    $add_cids = 1 if not defined $add_cids;
    $add_pids = 1 if not defined $add_pids;

    $select = "$def_table.$id_name,$def_table.name";
    $table = $def_table;

    $p_nodes = &Common::DAG::DB::get_nodes_parents( $dbh, $nodes, $select, $table, $edges_table );

    @ids = &Common::DAG::Nodes::get_ids_all( $p_nodes );

    if ( $add_cids ) {
        $p_nodes = &Common::DAG::DB::add_children_ids( $dbh, $p_nodes, $edges_table, \@ids );
    }
    
    if ( $add_pids ) {
        $p_nodes = &Common::DAG::DB::add_parent_ids( $dbh, $p_nodes, $edges_table, \@ids );
    }
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_parents
{
    # Niels Larsen, October 2004.

    # Fetches all parent nodes of a given node. 

    my ( $dbh,      # Database handle
         $id,       # Starting node or id 
         ) = @_;

    # Returns a nodes hash. 

    my ( $p_nodes, $table, $select );

    if ( ref $id ) { 
        $id = $id->{ $id_name };
    }

    $select = "$def_table.$id_name,$def_table.name";
    $table = $def_table;

    $p_nodes = &Common::DAG::DB::get_parents( $dbh, $id, $table, $edges_table, $select );
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_xrefs
{
    # Niels Larsen, October 2004.

    # Returns a hash structure where key is id and value is a database
    # cross-reference. It can be used to marge into a nodes hash.

    my ( $dbh,   # Database handle
         $db,    # Cross-reference database, e.g. ICD9
         $ids,   # Node ids - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $nodes, $select, $where );

    $select = "$xrefs_table.$id_name,$xrefs_table.name";
    $where = "$xrefs_table.db = '$db'";

    $nodes = &Common::DAG::DB::get_xrefs( $dbh, $select, $xrefs_table, $where, $ids );
    
    return wantarray ? %{ $nodes } : $nodes;
}

sub get_statistics
{
    # Niels Larsen, October 2004.

    # Fetches some or all pre-computed statistics for a given set of 
    # node ids. 

    my ( $dbh,        # Database handle
         $key,        # Statistics key
         $ids,        # List of ids - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $select, $table, $nodes );

    $select = "$stats_table.$id_name,$stats_table.$key";

    $nodes = &Common::DAG::DB::get_statistics( $dbh, $select, 
                                               $stats_table, $ids );

    return wantarray ? %{ $nodes } : $nodes;
}

sub open_node
{
    # Niels Larsen, October 2004.

    # Returns the nodes for the subtree starting at a given node, down 
    # to a given depth. If a node has less than a given number of children,
    # the routine will keep expanding it until the number is exceeded or 
    # until there are leaves only.

    my ( $dbh,      # Database handle
         $nid,      # Starting node id 
         $depth,    # How many levels to open - OPTIONAL, default 1
         $min,      # Minimum number of nodes to show - OPTIONAL
         ) = @_;

    # Returns a nodes hash.

    my ( $select, $table, $nodes, $node, $count, $last_count, @ids );

    $depth ||= 1;   # zero makes no sense
    $min ||= 3;     # zero makes no sense
    
    $select = "$def_table.$id_name,$def_table.name";
    $table = $def_table;

    $nodes = &Common::DAG::DB::get_subtree( $dbh, $nid, $select, $table, $edges_table, $depth );

    if ( defined $min )
    {
        $count = scalar @{ &Common::DAG::Nodes::get_ids_all( $nodes ) };
        
        # It is tedious to click 5 levels down just to find a single leaf.
        # So if there is only one child node we open the nodes further until
        # either 1) more than one children appear or 2) we reach a leaf. 
        
        $last_count = $count - 1;

        while ( $count <= $min and $count > $last_count )
        {
            $last_count = $count;
            
            $nodes = &Common::DAG::DB::get_subtree( $dbh, $nid, $select, $table, $edges_table, ++$depth );
            $count = scalar @{ &Common::DAG::Nodes::get_ids_all( $nodes ) };
        }
    }

    @ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    $nodes = &Common::DAG::DB::add_parent_ids( $dbh, $nodes, $edges_table, \@ids );

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

    my ( $select, $table, $nodes, $depth, @ids );

    $select = "$def_table.$id_name,$def_table.name";
    $table = $def_table;
    $depth = 99999;

    $nodes = &Common::DAG::DB::get_subtree( $dbh, $nid, $select, $table, $edges_table, $depth );

    @ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    $nodes = &Common::DAG::DB::add_parent_ids( $dbh, $nodes, $edges_table, \@ids );

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

    $root_node = &Anatomy::DB::get_node( $dbh, $root_id );

    # ---------- prepare search type strings,
    
    if ( $search_type eq "whole_words" )
    {
        $match_name = qq ( match ($def_table.name) against ('$search_text'));
        $match_syn = qq ( match ($synonyms_table.syn) against ('$search_text'));
        $match_desc = qq ( match ($def_table.deftext) against ('$search_text'));
        $match_ref = qq ( match ($xrefs_table.name) against ('$search_text'));
    }
    elsif ( $search_type eq "name_beginnings" )
    {
        $match_name = qq ( $def_table.name like '$search_text%');
        $match_syn = qq ( $synonyms_table.syn like '$search_text%');
        $match_desc = qq ( $def_table.deftext like '$search_text%');
        $match_ref = qq ( $xrefs_table.name like '$search_text%');
    }
    elsif ( $search_type eq "partial_words" )
    {
        $match_name = qq ( $def_table.name like '%$search_text%');
        $match_syn = qq ( $synonyms_table.syn like '%$search_text%');
        $match_desc = qq ( $def_table.deftext like '%$search_text%');
        $match_ref = qq ( $xrefs_table.name like '%$search_text%');
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
        $tables = qq ($edges_table natural join $xrefs_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_ref);
        @ref_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } @ref_ids;
        @ids = keys %ids;
    }
    elsif ( $search_target eq "titles" )
    {
        $tables = qq ($edges_table natural join $def_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } @tit_ids;
        @ids = keys %ids;
    }
    elsif ( $search_target eq "titles_synonyms" )
    {
        $tables = qq ($edges_table natural join $def_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq ($edges_table natural join $synonyms_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_syn);
        @syn_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } ( @tit_ids, @syn_ids );
        @ids = keys %ids;
    }
    elsif ( $search_target eq "descriptions" )
    {
        $tables = qq ($edges_table natural join $def_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_desc);
        @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    }        
    elsif ( $search_target eq "everything" )
    {
        $tables = qq ($edges_table natural join $def_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_name);
        @tit_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq ($edges_table natural join $xrefs_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_ref);
        @ref_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq ($edges_table natural join $synonyms_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_syn);
        @syn_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $tables = qq ($edges_table natural join $def_table);
        $sql = qq (select $edges_table.$id_name from $tables where $edges_table.parent_id = $root_id and $match_desc);
        @desc_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        %ids = map { $_, 1 } ( @tit_ids, @ref_ids, @syn_ids, @desc_ids );
        @ids = keys %ids;
    }
    else {
        &error( qq (Unknown search target -> "$search_target") );
    }

    return wantarray ? @ids : \@ids;
}

1;

__END__


sub get_tree_ids
{
    # Niels Larsen, October 2004.

    # Returns all nodes that correspond to a given list of ids, plus 
    # all their parents.  TODO - improve

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
         $depth,    # How many levels to open - OPTIONAL (default all)
         $select,   # Output fields - OPTIONAL (default id,name)
         ) = @_;

    # Returns a node hash.

    my ( $nodes, $table );

    $depth = 999999 if not defined $depth;
    $select = "$def_table.$id_name,$def_table.name" if not defined $select;
    $table = $def_table;

    $nodes = &Common::DAG::DB::get_subtree( $dbh, $id, $select, $table, $edges_table,
                                            $depth, undef, 1 );

    return wantarray ? %{ $nodes } : $nodes;
}
