package GO::DB;        #  -*- perl -*-

# Database accessor routines for the GO viewer. Most of the routines 
# simply invoke similarly named routines from the GO::DB_nodes module, 
# but with fewer mandatory arguments. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &database_exists
                 &expand_go_node
                 &expand_tax_node
                 &get_entry
                 &get_go_stats
                 &get_id_of_name
                 &get_ids_subtree
                 &get_ids_tax
                 &get_ids_tax_deep
                 &get_name_of_id
                 &get_node
                 &get_nodes
                 &get_nodes_all
                 &get_nodes_parents
                 &get_parents
                 &get_subtree
                 &get_tax_stats
                 &get_tree_ids
                 &open_node
                 );

use GO::DB_nodes;
use Common::DAG::Nodes;
use GO::Schema;

use Common::DB;
use Common::Messages;

#our $go_tables = "go_edges natural join go_def";
#our $go_select = "go_def.id,parent_ids,name,leaf,rel";

our $id_name_def = "go_id";
our $select_def = "go_def.go_id,parent_ids,name,leaf,rel,depth";
our $sql_no_cache = ""; # sql_no_cache";

our ( $t0, $t1, $time );

# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub database_exists
{
    # Niels Larsen, August 2005.

    # Returns true if all go related tables exist, otherwise
    # false. 

    my ( $dbh,       # Database handle
         ) = @_;

    # Returns 1 or nothing. 

    my ( $table );

    foreach $table ( keys %{ &GO::Schema::relational() } )
    {
        if ( not &Common::DB::table_exists( $dbh, $table ) )
        {
            return;
        }
    }

    return 1;
}

sub expand_go_node
{
    # Niels Larsen, October 2003.

    # Replaces the subtree starting at a given node with the minimal
    # subtree that spans the nodes that have a certain attribute set.
    
    my ( $dbh,      # Database handle
         $nid,      # Starting node id 
         $key,      # Column key 
         ) = @_;

    # Returns an updated nodes hash. 

    my ( $select, $tables, $where, $nodes );

    $tables = "go_edges natural join go_def";
    $select = "$select_def,children_ids";

    $where = "$key > 0 and go_edges.parent_id = $nid";

    $nodes = &GO::DB_nodes::get_subtree( $dbh, $nid, $tables, "go_edges", $select, $where );

    return wantarray ? %{ $nodes } : $nodes;
}

sub expand_tax_node
{
    # Niels Larsen, March 2004.

    # Replaces the subtree starting at a given node with the minimal
    # subtree that spans the nodes that have a certain organism 
    # related attribute set.
    
    my ( $dbh,          # Database handle
         $ids,          # Organism id list
         $root_id,      # Starting node id 
         ) = @_;

    # Returns an updated nodes hash.

    require Taxonomy::DB;

    my ( $tax_ids, $tax_id, $node_id, $all_ids, $all_nodes, $nodes, 
         $stats, $id );

    $tax_ids = [];

    foreach $tax_id ( @{ $ids } ) 
    {
        push @{ $tax_ids }, &Taxonomy::DB::get_ids_subtree( $dbh, $tax_id );
        push @{ $tax_ids }, $tax_id;
    }
    
    $tax_ids = &Common::Util::uniqify( $tax_ids );    

    $stats = &GO::DB::get_tax_stats( $dbh, $tax_ids, $root_id );

    $all_ids = &Common::DAG::Nodes::get_ids_all( $stats );
    $all_nodes = &GO::DB::get_nodes( $dbh, $all_ids );

    foreach $node_id ( @{ $all_ids } )
    {
        $nodes->{ $node_id } = $all_nodes->{ $node_id };
    }

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_entry
{
    # Niels Larsen, December 2003.

    # Returns a hash structure with all the information about a given 
    # term id that the system supports. 

    my ( $dbh,      # Database handle
         $id,       # Entry id
         ) = @_;

    # Returns a hash.

    if ( not defined $id ) {
        &error( qq (Input entry ID is undefined) );
    }

    my ( $entry, $sql, @matches, $match, $p_nodes, $p_node, $terms );

    $entry->{ $id_name_def } = $id;

    # -------- go_def table,

    $sql = qq (select name,deftext,comment from go_def where $id_name_def = $id);

    ( $entry->{"name"},
      $entry->{"description"},
      $entry->{"comment"} ) = @{ &Common::DB::query_array( $dbh, $sql )->[0] };

    # -------- go_synonyms table,

    $entry->{"synonyms"} = [];

    $sql = qq (select distinct syn,rel from go_synonyms where $id_name_def = $id);
    @matches = @{ &Common::DB::query_array( $dbh, $sql ) };
    
    foreach $match ( @matches )
    {
        push @{ $entry->{"synonyms"} }, {
            "synonym" => $match->[0],
            "relation" => $match->[1],
        };
    }
        
    # -------- go_def_ref table,

    $entry->{"reference"} = [];

    $sql = qq (select distinct db,name from go_def_ref where $id_name_def = $id);
    @matches = @{ &Common::DB::query_array( $dbh, $sql ) };
    
    foreach $match ( @matches )
    {
        push @{ $entry->{"reference"} }, { 
            "db_name" => $match->[0],
            "db_id" => $match->[1],
        };
    }

    # -------- go_stats table,

    $sql = qq (select go_terms_usum,go_terms_tsum from go_stats where $id_name_def = $id);
    @matches = @{ &Common::DB::query_array( $dbh, $sql ) };
    
    ( $entry->{"terms_unique"},
      $entry->{"terms_total"} ) = @{ &Common::DB::query_array( $dbh, $sql )->[0] };

    # -------- go_external table,

    $entry->{"external"} = [];

    $sql = qq (select ext_db,ext_id,ext_name from go_external where $id_name_def = $id);
    @matches = @{ &Common::DB::query_array( $dbh, $sql ) };
    
    foreach $match ( @matches )
    {
        push @{ $entry->{"external"} }, {
            "ext_db" => $match->[0],
            "ext_id" => $match->[1],
            "ext_name" => $match->[2],
        };
    }
    
    # -------- go_edges table,

    $entry->{"parents"} = [];

    @matches = ();

    $p_nodes = &GO::DB::get_parents( $dbh, $id );

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $p_nodes ) )
    {
        $sql = qq (select go_terms_tsum from go_stats where $id_name_def = $id);
        $terms = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        $p_node = $p_nodes->{ $id };
        push @matches, [ $id, $p_node->{"name"}, $terms || 0];
    }

    foreach $match ( sort { $a->[2] <=> $b->[2] } @matches )
    {
        push @{ $entry->{"parents"} }, {
            $id_name_def => $match->[0],
            "name" => $match->[1],
            "terms_total" => $match->[2],
        };
    }

    return $entry;
}
    
sub get_go_stats
{
    # Niels Larsen, February 2005.

    # Creates a very minimal GO tree: only the "count" and "sum_count"
    # keys are set and only nodes are included where the statistics count 
    # of a given type is greater then zero. 
    
    my ( $dbh,           # Database handle
         $ids,           # GO statistics ids
         $key,           # GO statistics key
         ) = @_;

    # Returns a nodes hash.

    my ( $idstr, $id, $sql, $count, $sum_count, $match, $key_node, $key_sum, 
         $stats );

    $idstr = join ",", @{ $ids };

    if ( $key eq "go_terms_tsum" or $key eq "go_terms_usum" or $key eq "go_orgs_usum" )
    {
#        $sql = qq (select go_id,$key from go_stats where $key > 0 and go_id in ( $idstr ));
        $sql = qq (select go_id,$key from go_stats where go_id in ( $idstr ));

        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $id, $sum_count ) = @{ $match };

            $stats->{ $id }->{"count"} = 1;                
            $stats->{ $id }->{"sum_count"} = $sum_count;
        }
    }
    else
    {
        $key_sum = $key;
        $key =~ s/_tsum|_usum|_node$//;
        $key_node = $key ."_node";
        
#        $sql = qq (select go_id,$key_node,$key_sum from go_stats where $key_sum > 0 and go_id in ( $idstr ));
        $sql = qq (select go_id,$key_node,$key_sum from go_stats where go_id in ( $idstr ));
        
        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $id, $count, $sum_count ) = @{ $match };
            
            $stats->{ $id }->{"count"} = $count || undef;
            $stats->{ $id }->{"sum_count"} = $sum_count;
        }
    }

    if ( $stats ) {
        return wantarray ? %{ $stats } : $stats;
    } else {
        return;
    }
}

sub get_id_of_name
{
    # Niels Larsen, October 2003.

    # Returns a node id given a node name. 

    my ( $dbh,       # Database handle
         $name,      # Node name
         ) = @_;

    # Returns an integer. 

    return &GO::DB_nodes::get_id_of_name( $dbh, $name, "go_def" );
}

sub get_ids_subtree
{
    # Niels Larsen, February 2004.

    # Returns the ids of the subtree starting at a given root id.
    # The root id is not included in the output list. 

    my ( $dbh,
         $nid,
         ) = @_;

    my ( $sql, @go_ids );

    $sql = qq (select $sql_no_cache distinct $id_name_def from go_edges where parent_id = $nid);

    @go_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    return wantarray ? @go_ids : \@go_ids;
}
    
sub get_ids_tax
{
    # Niels Larsen, February 2004.

    # Returns a non-redundant list of ids of GO terms that connect directly
    # to one or more given taxonomy ids. The connection is made by the gene
    # association tables. 

    my ( $dbh,         # Database handle
         $tax_ids,     # Taxonomy id or ids
         $root_id,     # GO root id - OPTIONAL
         ) = @_;

    # Returns an array.

    my ( $tax_idstr, $go_idstr, $sql, @go_ids, $go_ids );

    if ( ref $tax_ids ) {
        $tax_idstr = join ",", @{ $tax_ids };
    } else {
        $tax_idstr = $tax_ids;
    }

    if ( $root_id )
    {
        $go_ids = &GO::DB::get_ids_subtree( $dbh, $root_id );
        push @{ $go_ids }, $root_id;

        $go_idstr = join ",", @{ $go_ids };

        $sql = qq (select distinct go_id from go_genes_tax where go_id in ( $go_idstr ) and tax_id in ( $tax_idstr ));
    }
    else
    {
        $sql = qq (select distinct go_id from go_genes_tax where tax_id in ( $tax_idstr ));
    }

    @go_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    return wantarray ? @go_ids : \@go_ids;
}    

sub get_ids_tax_deep
{
    # Niels Larsen, January 2004.

    # Returns a list of taxonomy ids for a given list of GO ids.
    # The connection is made by the gene association tables. Each
    # GO id in the list is expanded with all GO ids included in 
    # the subtree of that id. If you dont want this use the 
    # get_tax_ids routine. NOTE: I tried to get the ids in one 
    # statement with a natural join, but that was slower.

    my ( $dbh,      # Database handle
         $ids,      # GO id or ids
         ) = @_;

    # Returns an array.

    my ( $idstr, $sql, @go_ids, @tax_ids, $nodes, $count );

    if ( ref $ids ) {
        $idstr = join ",", @{ $ids };
    } else {
        $idstr = $ids;
    }

    $sql = qq (select distinct $id_name_def from go_edges where parent_id in ( $idstr ));

    @go_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    $idstr = "$idstr";

    if ( @go_ids ) {
        $idstr .= "," . (join ",", @go_ids);
    }

    $sql = qq (select distinct tax_id from go_genes_tax where $id_name_def in ( $idstr ));

    @tax_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    return wantarray ? @tax_ids : \@tax_ids;
}    

sub get_name_of_id
{
    # Niels Larsen, October 2003.

    # Returns a node name given a node id. 

    my ( $dbh,       # Database handle
         $id,        # Node id
         ) = @_;

    # Returns an integer. 

    return &GO::DB_nodes::get_name_of_id( $dbh, $id, "go_def" );
}

sub get_node
{
    # Niels Larsen, October 2003.

    # Returns a single node with a given id.

    my ( $dbh,       # Database handle
         $id,        # Node id
         $select,    # List of field names - OPTIONAL 
         ) = @_;

    # Returns a nodes hash.

    my ( $node, $tables );

    $tables = "go_edges natural join go_def";
    $select = $select_def if not $select;

    $node = &GO::DB_nodes::get_node( $dbh, $id, $tables, "go_edges", $select );

    return wantarray ? %{ $node } : $node;
}

sub get_nodes
{
    # Niels Larsen, October 2003.

    # Fetches all nodes for a given set of node ids. 

    my ( $dbh,        # Database handle
         $ids,        # List of ids
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $tables );

    $tables = "go_edges natural join go_def";
    $select = $select_def if not $select;

    $nodes = &GO::DB_nodes::get_nodes( $dbh, $ids, $tables, "go_edges", $select );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_all
{
    # Niels Larsen, October 2003.

    # Fetches all nodes. 

    my ( $dbh,        # Database handle
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $tables );

    $tables = "go_edges natural join go_def";
    $select = $select_def if not $select;

    $nodes = &GO::DB_nodes::get_nodes_all( $dbh, $tables, "go_edges", $select );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_parents
{
    # Niels Larsen, December 2003.

    # Fetches all parent nodes of one or more given nodes. 

    my ( $dbh,      # Database handle
         $nodes,    # Starting nodes or ids 
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 

    my ( $p_nodes, $tables );

    $tables = "go_edges natural join go_def";
    $select = $select_def if not $select;

    $p_nodes = &GO::DB_nodes::get_nodes_parents( $dbh, $nodes, $tables, "go_edges", $select );
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_parents
{
    # Niels Larsen, October 2003.

    # Fetches all parent nodes of a given node. 

    my ( $dbh,      # Database handle
         $id,       # Starting node or id 
         $select,   # List of field names - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 

    my ( $p_nodes, $tables );

    if ( ref $id ) { 
        $id = $id->{"id"};
    }

    $tables = "go_edges natural join go_def";
    $select = $select_def if not $select;

    $p_nodes = &GO::DB_nodes::get_parents( $dbh, $id, $tables, "go_edges", $select );
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_subtree
{
    # Niels Larsen, October 2003.

    # For a given node id, fetches all nodes that make up the subtree
    # that starts at the node, the given node included. 

    my ( $dbh,      # Database handle
         $id,       # Node or id of starting node
         $select,   # Output fields  
         ) = @_;

    # Returns a node hash.

    my ( $nodes, $tables );

    $select = $select_def if not $select;
    $tables = "go_def natural join go_edges";

    $nodes = &GO::DB_nodes::get_subtree( $dbh, $id, $tables, "go_edges", $select );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_tax_stats
{
    # Niels Larsen, February 2004.

    # Creates a set of nodes where one or more given organisms connect
    # the GO tree. An optional starting node may be given; this makes
    # the routine much faster if the subtree under the given node is 
    # small, but slower if it is among the top-most in the GO tree. 

    my ( $dbh,         # Database handle
         $tax_ids,     # Organism id list - OPTIONAL, default all
         $root_id,     # Starting node id - OPTIONAL
         ) = @_;

    # Returns a nodes hash.

    my ( $nodes, $p_nodes, $subref, $argref, $root_node, $array,
         $select, $id, $sql, $go_str, $tax_str, $p_idstr, $go_p_str,
         %ids, @ids, @p_ids, $pair, $nmin, $nmax, $go_ids, @pairs, %skip_ids );

    $tax_str = join ",", @{ $tax_ids };

    if ( $root_id )
    {
        # Dont touch this unless you know what youre doing .. a join
        # here would be much slower. 

        $sql = qq (select $sql_no_cache distinct go_id from go_edges where parent_id = $root_id );
        @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        push @ids, $root_id;

        $sql = qq (select $sql_no_cache distinct go_id from go_genes_tax where tax_id in ( $tax_str ));
        
        %ids = map { $_->[0], 1 } &Common::DB::query_array( $dbh, $sql );
        
        $go_ids = [];

        foreach $id ( @ids ) {
            push @{ $go_ids }, $id if $ids{ $id };
        }
    }
    else
    {
        &error( qq (Root id is not given) );
        exit;
    }        
    
    if ( @{ $go_ids } )
    {
        # Get all parent ids under the given $root_id,
        
        $go_str = join ",", @{ $go_ids };
        $sql = qq (select $sql_no_cache distinct parent_id from go_edges where go_id in ($go_str));
        @p_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $sql = qq (select $sql_no_cache distinct parent_id from go_edges where go_id = $root_id);
        %skip_ids = map { $_->[0], 1 } &Common::DB::query_array( $dbh, $sql );
        
        @p_ids = grep { not $skip_ids{ $_ } } @p_ids;

        # Get the go_id,parent_id pairs of all ids,
        
        $go_str = join ",", @{ $go_ids };

        if ( @p_ids ) {
            $go_str .= ",". (join ",", @p_ids);
        }

        $sql = qq (select $sql_no_cache go_id,parent_id from go_edges where go_id in ($go_str));

        @pairs = &Common::DB::query_array( $dbh, $sql );

        foreach $pair ( @pairs )
        {
            push @{ $nodes->{ $pair->[0] }->{"parent_ids"} }, $pair->[1];
        }
        
        # Delete parent orphans,

        $nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $nodes );

        # Set all children,

        $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes, 0 );

        # Set leaf counts,
        
        foreach $id ( @{ $go_ids } )
        {
            $nodes->{ $id }->{"count"} = 1;
        }
        
        return wantarray ? %{ $nodes } : $nodes;
    }
    else {
        return;
    }
}

sub get_tree_ids
{
    # Niels Larsen, January 2004.

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

    $nodes = &GO::DB::get_nodes( $dbh, $ids, $select );
    $p_nodes = &GO::DB::get_nodes_parents( $dbh, $ids, $select );

    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );

    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    return wantarray ? %{ $nodes } : $nodes;
}

sub open_node
{
    # Niels Larsen, October 2003.

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
    
    my ( $select, $tables, $edges, $where, $p_nodes, $nodes, $node, 
         $count, $last_count );

    $tables = "go_edges natural join go_def";
    $select = $select_def;
    $edges = "go_edges";
    $where = "go_edges.parent_id = $nid and dist <= $depth";

    $nodes = &GO::DB_nodes::get_subtree( $dbh, $nid, $tables, $edges, $select, $where );

    if ( defined $min )
    {
        $count = scalar @{ &Common::DAG::Nodes::get_ids_all( $nodes ) };
        
        # It is tedious to click 5 levels down just to find a single leaf.
        # So if there is only one child node we open the nodes further until
        # either 1) more than one children appear or 2) we reach a leaf. 
        
        if ( $count <= $min )
        {
            $last_count = $count - 1;
            
            while ( $count > $last_count and $count <= $min )
            {
                $last_count = $count;

                $where = "go_edges.parent_id = $nid and dist <= " . ++$depth;
                $nodes = &GO::DB_nodes::get_subtree( $dbh, $nid, $tables, $edges, $select, $where );
                
                $count = scalar @{ &Common::DAG::Nodes::get_ids_all( $nodes ) };
            }
        }
    }
    
    return wantarray ? %{ $nodes } : $nodes;
}

1;

__END__


sub get_statistics
{
    # Niels Larsen, February 2004.

    # Fetches some or all pre-computed statistics for a given set of 
    # node ids. 

    my ( $dbh,        # Database handle
         $ids,        # List of ids - OPTIONAL
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $sql );

    $sql = qq (select);

    if ( defined $select ) {
        $sql .= " $select";
    } else {
        $sql .= " *";
    }

    $sql .= " from go_stats";

    if ( defined $ids )
    {
        $sql .= " where go_id in ( " . (join ",", @{ $ids }) . " )";
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, "go_id" );

    return wantarray ? %{ $nodes } : $nodes;
}
