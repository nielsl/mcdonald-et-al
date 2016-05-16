package Common::DAG::DB;        #  -*- perl -*-

# Generic functions that reach into a directed acyclic graph database
# to get something, typically a set of nodes. The nodes have the 
# following minimal structure,
# 
#             "id" => Node ID
#     "parent_ids" => List of immediate parent node ID's
#    "parent_rels" => List of immediate parent node relations ('%' or '<')
#   "children_ids" => List of children node ID's
#  "children_rels" => List of children node relations ('%' or '<')
# 
# These functions should be called by viewer specific functions where
# table names and select statements are set. Thus each viewer calls 
# its own functions that in turn call these. This extra "layer" helps
# maintenance and means we can change database without touching the 
# viewer code.
# 
# The Common::DAG::Nodes module is for memory manipulation of these
# nodes. The Common::DAG::Schema file lists the tables and fields 
# that a minimal DAG database must have.
# 
# No defaults are provided by these functions and missing arguments
# are considered fatal errors, except for a few optional ones.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 $id_name

                 &add_children_ids
                 &add_edge_info
                 &get_children
                 &get_id_of_name
                 &get_ids_subtree
                 &get_name_of_id
                 &get_node
                 &get_nodes
                 &get_nodes_all
                 &get_parents
                 &get_nodes_parents
                 &get_statistics
                 &get_subtree
                 &get_xrefs
                 &query_ids
                 );

use Common::DAG::Nodes;
use Common::DB;
use Common::Messages;

our $id_name;
our $sql_cache = "sql_cache"; 

# >>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_children_ids
{
    # Niels Larsen, October 2004.

    # Adds children ids to a given set of nodes. If a list of ids is 
    # given, then only the nodes in the list are added children to. 

    my ( $dbh,       # Database handle
         $nodes,     # Nodes hash
         $edges,     # Edges table name
         $ids,       # List of ids - OPTIONAL 
         ) = @_;

    # Returns an updated nodes hash. 

    my ( $pair, $sql, $idstr );

    if ( $ids and @{ $ids } )
    {
        $idstr = join ",", @{ $ids };

        $sql = qq (select $sql_cache $edges.parent_id,$edges.$id_name from $edges where)
             . qq ( $edges.parent_id in ($idstr) and $edges.dist = 1);
    }
    else
    {
        $sql = qq (select $sql_cache $edges.parent_id,$edges.$id_name from $edges)
             . qq ( where $edges.dist = 1);
    }

    foreach $pair ( &Common::DB::query_array( $dbh, $sql ) )
    {
        push @{ $nodes->{ $pair->[0] }->{"children_ids"} }, $pair->[1];
    }

    wantarray ? return %{ $nodes } : return $nodes;
}

sub add_edge_info
{
    # Niels Larsen, October 2004.

    my ( $dbh,      # Database handle
         $nodes,    # Nodes hash
         $edges,    # Table(s) with edge information
         $ids,      # List of ids - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $sql, $elem, $id, $select, $idstr );

    $select = "$edges.$id_name,$edges.leaf,$edges.rel";

    if ( $ids and @{ $ids } )
    {
        $idstr = join ",", @{ $ids };
        $sql = qq (select $sql_cache $select from $edges where $edges.$id_name in ( $idstr));
    }
    else {
        $sql = qq (select $sql_cache $select from $edges);
    }
    
    foreach $elem ( &Common::DB::query_array( $dbh, $sql ) )
    {
        $id = $elem->[0];

        if ( exists $nodes->{ $id } )
        {
            $nodes->{ $id }->{"leaf"} = $elem->[1];
            $nodes->{ $id }->{"rel"} = $elem->[2];
        }
    }

    wantarray ? return %{ $nodes } : return $nodes;
}    

sub add_parent_ids
{
    # Niels Larsen, October 2004.

    # Adds parent ids to a given set of nodes. If a list of ids is 
    # given, then only the nodes in the list are added parent ids to. 

    my ( $dbh,       # Database handle
         $nodes,     # Nodes hash
         $edges,     # Edges table name
         $nids,      # List of node ids - OPTIONAL 
#         $pids,      # List of parent node ids - OPTIONAL 
         ) = @_;

    # Returns an updated nodes hash.

    my ( $sql, $pair, $idstr, %pids, $select );

    $select = qq ($edges.$id_name,$edges.parent_id,$edges.rel);

    if ( $nids and @{ $nids } )
    {
        $idstr = join ",", @{ $nids };

        $sql = qq (select $sql_cache $select from $edges where) 
             . qq ( $edges.$id_name in ($idstr) and $edges.dist = 1);
    }
    else
    {
        $sql = qq (select $sql_cache $select from $edges)
             . qq ( where $edges.dist = 1);
    }        

#    %pids = map { $_, 1 } @{ $pids };

    foreach $pair ( &Common::DB::query_array( $dbh, $sql ) )
    {
        push @{ $nodes->{ $pair->[0] }->{"parent_ids"} }, $pair->[1];
        push @{ $nodes->{ $pair->[0] }->{"parent_rels"} }, $pair->[2];
    }

    wantarray ? return %{ $nodes } : return $nodes;
}

sub check_sql_args
{
    # Niels Larsen, October 2004.

    # Prints error messages and stops program if select and tables
    # arguments not defined or are empty. This is just a convenience
    # function. 

    my ( $select,
         $tables,
         ) = @_;

    if ( not $select ) {
        &error( qq (Missing select statement) );
        exit;
    }

    if ( not $tables ) {
        &error( qq (Missing table or table list) );
        exit;
    }
    
    return;
}
 
sub get_children
{
    # Niels Larsen, October 2004.

    # For a given node or node id, fetches child nodes one level down.
    # The select argument determines which fields from names and edges
    # tables are included. 

    my ( $dbh,      # Database handle
         $pid,      # Starting node id
         $select,   # Field string 
         $table,    # Table with node information
         $edges,    # Table with edges 
         ) = @_;

    # Returns a nodes hash. 
    
    my ( $parent_id, $sql, @ids, $nodes, $p_nodes, $idstr );

    $sql = qq (select $sql_cache $select from $table natural join $edges)
         . qq ( where dist <= 1 and parent_id = $pid);

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );
    
    return wantarray ? %{ $nodes } : $nodes;
}
    
sub get_id_of_name
{
    # Niels Larsen, October 2004.

    # Returns a node id given a node name and a table. 

    my ( $dbh,       # Database handle
         $name,      # Node name
         $tables,    # Tables string
         ) = @_;

    # Returns an integer. 

    my ( $sql, $nodes, @ids, $count );

    $sql = qq (select $sql_cache $id_name from $tables where name = "$name");

    # We use query_hash because the id may not be unique,

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    @ids = keys %{ $nodes };
    
    if ( scalar @ids == 1 ) 
    {
        return $ids[0];
    }
    else
    {
        $count = scalar @ids;
        &error( qq (There should be 1 node with the name "$name", but found $count) );
    }
}

sub get_ids_subtree
{
    # Niels Larsen, October 2004.
    
    # Runs a query on the sub-hierarchy given by its topmost node id 
    # and returns the ids of the nodes that match. The optional where
    # expression will filter the match. 

    my ( $dbh,      # Database handle
         $pid,      # Starting node id
         $tables,   # Table(s) with node information
         $where,    # Query expression - OPTIONAL
         ) = @_;
    
    # Returns an array of ids.
    
    my ( $sql, @nodes );

    $sql = qq (select $sql_cache $id_name from $tables where parent_id = $pid);
    $sql .= qq ( and $where) if $where;

    @nodes = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    
    if ( @nodes ) {
        return wantarray ? @nodes : \@nodes;
    } else {
        return wantarray ? () : [];
    }            
}

sub get_name_of_id
{
    # Niels Larsen, October 2004.

    # Returns the name of a node given by its id and table. 

    my ( $dbh,       # Database handle
         $id,        # Node id
         $tables,    # Tables string
         ) = @_;

    # Returns an integer. 

    my ( $sql, $nodes, @names, $count );

    $sql = qq (select $sql_cache name from $tables where $id_name = "$id");

    # We use query_hash because the id may not be unique,

    $nodes = &Common::DB::query_hash( $dbh, $sql, "name" );

    @names = keys %{ $nodes };
    
    if ( scalar @names == 1 ) 
    {
        return $names[0];
    }
    else
    {
        $count = scalar @names;
        &error( qq (There should be 1 node with the id "$id", but found $count) );
    }
}

sub get_node
{
    # Niels Larsen, October 2004.

    # Returns a single node given by its id. The fields returned depend 
    # on the select argument. The where expression is used to qualify the 
    # query if ids are not unique. 

    my ( $dbh,      # Database handle
         $id,       # Node id 
         $select,   # Field string
         $table,    # Table with node information
         $edges,    # Table with edges 
         $where,    # Qualifier string - OPTIONAL
         ) = @_;
    
    # Returns a node hash.

    my ( $nodes, $node );

    $nodes = &Common::DAG::DB::get_nodes( $dbh, [ $id ], $select, $table, $edges );

    $node = ( values %{ $nodes } )[0];

    return wantarray ? %{ $node } : $node;
}

sub get_nodes
{
    # Niels Larsen, October 2004.

    # Retrieves a set of nodes given by a list of ids. Only the node name
    # table is searched and the fields returned depend on the select argument.
    # The optional where expression is used to qualify the query. If you want
    # more information added to the nodes, use the add functions. 

    my ( $dbh,      # Database handle
         $ids,      # ID list
         $select,   # Field string 
         $table,    # Table(s) with node information
         $edges,    # Table(s) with edge information
         ) = @_;

    # Returns a hash.

    my ( $sql, $nodes, $idstr );

    $idstr = join ",", @{ $ids };
    $sql = qq (select $sql_cache $select from $table where $table.$id_name in ( $idstr ));

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    $nodes = &Common::DAG::DB::add_edge_info( $dbh, $nodes, $edges, $ids );

    wantarray ? return %{ $nodes } : return $nodes;
}

sub get_nodes_all
{
    # Niels Larsen, October 2004.

    # Retrieves all nodes. The fields returned depend on the select 
    # argument and the optional where expression is used to qualify 
    # the query. 

    my ( $dbh,      # Database handle
         $select,   # Field string 
         $table,    # Table(s) with node information
         $edges,    # Table(s) with edge information
         ) = @_;

    # Returns a hash.

    my ( $sql, $nodes, $elem, $id );

    $sql = qq (select $sql_cache $select from $table);

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    $nodes = &Common::DAG::DB::add_edge_info( $dbh, $nodes, $edges );

    wantarray ? return %{ $nodes } : return $nodes;
}

sub get_parents
{
    # Niels Larsen, October 2004.

    # Fetches all parent nodes starting at a given node or node id. If the 
    # last (include) argument is true the given node is included, otherwise
    # not. The fields returned depend on the select argument; default is 
    # "id,parent_ids,name". The routine works by first recursively following 
    # all parents to the top node. 

    my ( $dbh,      # Database handle
         $id,       # Starting node id
         $table,    # Table with node names 
         $edges,    # Edges table
         $select,   # Field string - OPTIONAL
         $include,  # Include boolean - OPTIONAL, default 1
         ) = @_;

    # Returns a nodes hash. 
    
    my ( $sql, $nodes, @ids );

    $sql = qq (select $sql_cache $edges.parent_id from $edges where $edges.$id_name = $id);

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    if ( $include ) {
        push @ids, $id;
    }

    $nodes = &Common::DAG::DB::get_nodes( $dbh, \@ids, $select, $table, $edges );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_parents
{
    # Niels Larsen, October 2004.

    # From a given set of nodes, finds the set of parent nodes that together
    # with the nodes makes up the minimal subtree that includes the given 
    # nodes. In other words the routine finds the nodes that when merged with
    # the given nodes comprise a complete tree starting at a single node. 

    my ( $dbh,     # Database handle
         $nodes,   # Nodes (or ids of nodes) we want all parents of
         $select,  # Output fields 
         $table,   # Table with node names 
         $edges,   # Edges table
         $where,   # Where expression - OPTIONAL
         ) = @_;
    
    # Returns a nodes hash.

    my ( $p_nodes, $sql, @ids, $idstr );

    if ( ref $nodes eq "HASH" ) {
        $idstr = join ",", &Common::DAG::Nodes::get_ids_all( $nodes );
    } elsif ( ref $nodes eq "ARRAY" ) {
        $idstr = join ",", @{ $nodes };
    } else {
        &error( qq (Input nodes must be a nodes hash or list of ids) );
    }        

    $sql = qq (select $sql_cache distinct $edges.parent_id from $edges where $edges.$id_name in ($idstr));
    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    $p_nodes = &Common::DAG::DB::get_nodes( $dbh, \@ids, $select, $table, $edges );

    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_statistics
{
    # Niels Larsen, October 2004.

    # Fetches some or all pre-computed statistics for a given set of 
    # node ids. 

    my ( $dbh,           # Database handle
         $select,        # String of field names
         $table,         # Statistics table 
         $ids,           # List of ids - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $sql );

    if ( defined $select ) {
        $sql = "select $select";
    } else {
        $sql = "select *";
    }

    $sql .= " from $table";

    if ( defined $ids )
    {
        $sql .= " where $table.$id_name in ( " . (join ",", @{ $ids }) . " )";
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_subtree
{
    # Niels Larsen, October 2004.

    # For a given node or node id, fetches all nodes that make up the 
    # subtree that starts at the node. The subtree is either the complete
    # tree or one limited by the where expression. A flag determines
    # if the starting node is included or not. 

    my ( $dbh,      # Database handle
         $pid,      # Starting parent node id
         $select,   # Field string 
         $table,    # Table with node names
         $edges,    # Table with edges 
         $depth,    # The number of levels to include
         $where,    # Where expression - OPTIONAL
         $include,  # Include given node boolean - OPTIONAL, default true
         ) = @_;

    # Returns a nodes hash. 
    
    $include = 1 if not defined $include;

    my ( $sql, @ids, $nodes, $p_nodes );

    $sql = qq (select $sql_cache $edges.$id_name from $edges)
         . qq ( where $edges.parent_id = $pid and $edges.dist <= $depth);

    $sql .= qq ( and $where) if $where;

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    push @ids, $pid if $include;

    $nodes = &Common::DAG::DB::get_nodes( $dbh, \@ids, $select, $table, $edges );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_xrefs
{
    # Niels Larsen, October 2004.

    # Fetches some or all pre-computed cross-references for a 
    # given set of node ids. 

    my ( $dbh,          # Database handle
         $select,       # String of field names
         $table,        # Cross-refs table name
         $where,        # Where expression - OPTIONAL
         $ids,          # List of ids - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $sql );

    $sql = qq (select);

    if ( defined $select ) {
        $sql .= " $select";
    } else {
        $sql .= " *";
    }

    $sql .= " from $table";

    if ( defined $where )
    {
        $sql .= " where $where";
    }

    if ( defined $ids )
    {
        if ( defined $where ) {
            $sql .= " and $table.$id_name in ( " . (join ",", @{ $ids }) . " )";
        } else {
            $sql .= " where $table.$id_name in ( " . (join ",", @{ $ids }) . " )";
        }
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    return wantarray ? %{ $nodes } : $nodes;
}

1;



__END__

# GARBAGE CAN - but dont delete yet 


sub get_parents_ids
{
    # Niels Larsen, October 2003.

    # Given a node id, creates a hash of all its parents. Each key is the 
    # parent id and the values have the form [ hops, relation ] where hops
    # are the number of position moves from a given node to the parent; for
    # two immediate neighbors hops would be 1, with one node between 2 and 
    # so on. Relation is either "%" or "<" which symbolizes "is a" and 
    # "part of" relationship respectively. To create the, the routine 
    # travels the edges hash made by the parse_ontology routine. 

    my ( $dbh,     # Database handle
         $id,      # Node id
         $edges,   # Edges table
         ) = @_;

    # Returns an array.

    my ( $sql, $nodes, $p_nodes, $p_id );

    $sql = qq (select sql_cache parent_id,id from $edges where id = $id and dist = 1);
    $nodes = &Common::DB::query_hash( $dbh, $sql, "parent_id" );

    foreach $p_id ( keys %{ $nodes } )
    {
        if ( $p_nodes = &Common::DAG::DB::get_parents_ids( $dbh, $p_id, $edges ) )
        {
            $nodes = { %{ $nodes }, %{ $p_nodes } };
        }
    }
    
    return wantarray ? %{ $nodes } : $nodes;
}
 
