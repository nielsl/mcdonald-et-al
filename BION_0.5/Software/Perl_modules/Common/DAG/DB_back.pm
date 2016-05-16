package Common::DAG::DB;        #  -*- perl -*-

# Functions that reach into a directed acyclic graph database to get 
# something, typically a set of nodes. The nodes have the following 
# minimal structure,
# 
#             "id" => Node ID
#     "parent_ids" => List of immediate parent node ID's
#    "parent_rels" => List of immediate parent node relations ('%' or '<')
#   "children_ids" => List of children node ID's
#  "children_rels" => List of children node relations ('%' or '<')
# 
# The Common::DAG::Nodes module is for memory manipulation of these
# nodes. The Common::DAG::Schema file lists the tables and fields 
# that a minimal DAG database must have. 

use strict;
use warnings;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 $id_name

                 &get_children
                 &get_id_of_name
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

1;

__END__

# >>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get_children
{
    # Niels Larsen, October 2004.

    # For a given node or node id, fetches all child nodes. 
    # The routine produces a set of nodes with optional fields
    # included. 

    my ( $dbh,      # Database handle
         $node,     # Starting node or node id
         $table,    # Table(s) with node information
         $edges,    # Table with edges 
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 
    
    if ( not $select ) {
        $select = "$id_name,children_ids,name";
    }

    my ( $parent_id, $sql, $ids, $nodes, $p_nodes );

    if ( ref $node ) {
        $parent_id = $node->{ $id_name };
    } else {
        $parent_id = $node;
    }

    if ( not $table ) {
        &error( qq (The name of a nodes table must be given) );
    }

    if ( not $edges ) {
        &error( qq (The name of an edges table must be given) );
    }

    $sql = qq (select sql_cache $edges.$id_name from $edges where parent_id = $parent_id and dist <= 1);
    $sql .= qq ( and $where) if $where;

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );
    $ids = &Common::DAG::Nodes::get_ids_all( $nodes );

    &dump( $sql );

    $nodes = &Common::DAG::DB::get_nodes( $dbh, $ids, $table, $edges, $select, $where );

    return wantarray ? %{ $nodes } : $nodes;
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

    $sql = qq (select sql_cache name from $tables where $id_name = "$id");

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

    $sql = qq (select sql_cache $id_name from $tables where name = "$name");

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

sub get_node
{
    # Niels Larsen, October 2004.

    # Returns a single node given by its id. The fields returned depend 
    # on the select argument. The where expression is used to qualify the 
    # query if ids are not unique. 

    my ( $dbh,      # Database handle
         $id,       # Node id 
         $table,    # Table(s) with node information
         $edges,    # Table with edges 
         $select,   # Field string - OPTIONAL
         $where,    # Qualifier string - OPTIONAL
         ) = @_;
    
    # Returns a node hash.

    my ( $nodes, $node );

    $nodes = &Common::DAG::DB::get_nodes( $dbh, [ $id ], $table, $edges, $select, $where );

    $node = ( values %{ $nodes } )[0];

    return wantarray ? %{ $node } : $node;
}

sub get_nodes
{
    # Niels Larsen, October 2004.

    # Retrieves the set of nodes that have the ids in a given list.
    # The fields returned depend on the select argument; default is 
    # "id,parent_ids,name". The where expression is used to qualify
    # the query if ids are not unique. 

    my ( $dbh,      # Database handle
         $ids,      # ID list
         $table,    # Table(s) with node information
         $edges,    # Table with edges 
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;

    # Returns a hash.

    if ( not $table ) {
        &error( qq (The name of a nodes table must be given) );
    }

    if ( not $edges ) {
        &error( qq (The name of an edges table must be given) );
    }

    if ( not $select ) {
        $select = "$id_name,parent_ids,name";
    }

    my ( $sql, $nodes, $node, %select, $children_ids, $parent_ids, $dist,
         $idstr, $pair, $rel );

    %select = map { $_ => 1 } split /\s*,\s*/, $select;
    
    $children_ids = $select{"children_ids"} || "";
    $parent_ids = $select{"parent_ids"} || "";
    $rel = $select{"rel"} || "";

    delete $select{"children_ids"};
    delete $select{"parent_ids"};
    delete $select{"rel"};
    delete $select{"dist"};
    delete $select{"depth"};
    delete $select{"parent_id"};

    $select = join ",", keys %select;
    $idstr = join ",", @{ $ids };

    if ( $where ) {
        $sql = qq (select $select from $table where $edges.$id_name in ( $idstr ) and $where);
    } else {
        $sql = qq (select $select from $table where $edges.$id_name in ( $idstr ));
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    if ( $children_ids )
    {
        $sql = qq (select $edges.parent_id,$edges.$id_name from $edges where)
             . qq ( $edges.parent_id in ($idstr) and $edges.dist = 1);

        foreach $pair ( &Common::DB::query_array( $dbh, $sql ) )
        {
            push @{ $nodes->{ $pair->[0] }->{"children_ids"} }, $pair->[1];
        }
    }

    if ( $parent_ids )
    {
        if ( $rel )
        {
            $sql = qq (select $edges.$id_name,$edges.parent_id,$edges.rel from $edges where)
                 . qq ( $edges.$id_name in ($idstr) and $edges.dist = 1);

            foreach $pair ( &Common::DB::query_array( $dbh, $sql ) )
            {
                push @{ $nodes->{ $pair->[0] }->{"parent_ids"} }, $pair->[1];
                push @{ $nodes->{ $pair->[0] }->{"parent_rels"} }, $pair->[2];
            }
        }
        else
        {
            $sql = qq (select $edges.$id_name,$edges.parent_id from $edges where)
                 . qq ( $edges.$id_name in ($idstr) and $edges.dist = 1);
            
            foreach $pair ( &Common::DB::query_array( $dbh, $sql ) )
            {
                push @{ $nodes->{ $pair->[0] }->{"parent_ids"} }, $pair->[1];
            }
        }
    }

    wantarray ? return %{ $nodes } : return $nodes;
}

sub get_nodes_all
{
    # Niels Larsen, October 2004.

    # Returns all nodes from a given name and edges table. The fields
    # returned depend on the select argument. The where expression is 
    # used to qualify the query if ids are not unique. 

    my ( $dbh,      # Database handle
         $table,    # Table(s) with node information
         $edges,    # Table with edges 
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;
    
    # Returns a hash.
    
    if ( not $table ) {
        &error( qq (The name of a nodes table must be given) );
    }
    
    if ( not $edges ) {
        &error( qq (The name of an edges table must be given) );
    }
    
    if ( not $select ) {
        $select = "$id_name,parent_ids,name";
    }

    my ( $sql, $nodes, $node, %select, $children_ids, $parent_ids, $dist, $depth,
         @pairs, $pair, $root_node, $count, $rel );

    %select = map { $_ => 1 } split /\s*,\s*/, $select;
    
    $children_ids = $select{"children_ids"} || "";
    $parent_ids = $select{"parent_ids"} || "";
    $rel = $select{"rel"} || "";

    delete $select{"children_ids"};
    delete $select{"parent_ids"};
    delete $select{"rel"};
    delete $select{"dist"};
    delete $select{"depth"};
    delete $select{"parent_id"};

    $select = join ",", keys %select;

    if ( $where ) {
        $sql = qq (select sql_cache $select from $table where $where);
    } else {
        $sql = qq (select sql_cache $select from $table);
    }
    
    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    if ( $parent_ids )
    {
        $sql = qq (select distinct sql_cache $id_name,parent_id from $edges where dist = 1);
        @pairs = &Common::DB::query_array( $dbh, $sql );

        foreach $pair ( @pairs )
        {
            if ( exists $nodes->{ $pair->[0] } ) {
                push @{ $nodes->{ $pair->[0] }->{"parent_ids"} }, $pair->[1];
            } else {
                &error( qq (Node ID does not exist -> "$pair->[0]") );
            }
        }
    }

    if ( $children_ids )
    {
        $root_node = &Common::DAG::Nodes::get_node_root( $nodes );
        $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );
    }

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
         $table,    # Table(s) to fetch from 
         $edges,    # Edges table
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         $include,  # Include boolean - OPTIONAL, default 1
         ) = @_;

    # Returns a nodes hash. 
    
    if ( not $table ) {
        &error( qq (The name of a nodes table must be given) );
    }

    if ( not $edges ) {
        &error( qq (The name of an edges table must be given) );
    }

    if ( not $select ) {
        $select = "$id_name,parent_ids,name";
    }

    my ( $sql, $nodes, @ids );

    $sql = qq (select sql_cache parent_id from $edges where $id_name = $id);

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    if ( $include ) {
        push @ids, $id;
    }

    $nodes = &Common::DAG::DB::get_nodes( $dbh, \@ids, $table, $edges, $select, $where );

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
         $table,   # Table(s) to fetch from 
         $edges,   # Edges table
         $select,  # Output fields - OPTIONAL
         $where,   # Where expression - OPTIONAL
         ) = @_;
    
    # Returns a nodes hash.

    if ( not $table ) {
        &error( qq (The name of an existing table must be given) );
        exit;
    }

    if ( not $edges ) {
        &error( qq (The name of an edges table must be given) );
        exit;
    }

    if ( not $select ) {
        $select = "$id_name,parent_ids,name";
    }

    my ( $parents, $p_nodes, $all_nodes, $sql, @ids, $id, $idstr, $p_id, $p_node );

    if ( ref $nodes eq "HASH" ) {
        $idstr = join ",", &Common::DAG::Nodes::get_ids_all( $nodes );
    } elsif ( ref $nodes eq "ARRAY" ) {
        $idstr = join ",", @{ $nodes };
    } else {
        &error( qq (Input nodes must be a nodes hash or list of ids) );
    }        

    $sql = qq (select distinct parent_id from $edges where $id_name in ($idstr));
    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    $p_nodes = &Common::DAG::DB::get_nodes( $dbh, \@ids, $table, $edges, $select, $where );

#    $all_nodes = &Common::DAG::Nodes::merge_nodes( $p_nodes, $nodes );

    

#     # First create a nodes hash that include all parents that lead to the root,
#     # along all possible paths. For each of these nodes, set a "footprint" that
#     # tells which child node (the incoming ones) it is a parent to. The smallest
#     # subtree that covers all incoming nodes can then be found by starting at 
#     # the root and looking down in the tree for the node where ich has no 

#     $parents = {};

#     foreach $id ( keys %{ $nodes } )
#     {
#         $p_nodes = &Common::DAG::DB::get_parents( $dbh, $id, $table, $edges, $select, $where );

#         foreach $p_id ( keys %{ $p_nodes } )
#         {
#             $p_node = $p_nodes->{ $p_id };

#             if ( not exists $parents->{ $p_id } ) {
#                 $parents->{ $p_id } = &Storable::dclone( $p_node );
#             }

#             $parents->{ $p_id }->{"temp"}->{ $id } = 1;
#         }
#     }
    

    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_statistics
{
    # Niels Larsen, October 2004.

    # Fetches some or all pre-computed statistics for a given set of 
    # node ids. 

    my ( $dbh,        # Database handle
         $table,      # Statistics table name
         $select,     # List of field names - OPTIONAL
         $ids,        # List of ids - OPTIONAL
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

    if ( defined $ids )
    {
        $sql .= " where $id_name in ( " . (join ",", @{ $ids }) . " )";
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_xrefs
{
    # Niels Larsen, October 2004.

    # Fetches some or all pre-computed cross-references for a 
    # given set of node ids. 

    my ( $dbh,        # Database handle
         $table,      # Cross-refs table name
         $select,     # List of field names - OPTIONAL
         $where,      # Where expression - OPTIONAL
         $ids,        # List of ids - OPTIONAL
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
            $sql .= " and $id_name in ( " . (join ",", @{ $ids }) . " )";
        } else {
            $sql .= " where $id_name in ( " . (join ",", @{ $ids }) . " )";
        }
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_subtree
{
    # Niels Larsen, October 2004.

    # For a given node or node id, fetches all nodes that make up the 
    # subtree that starts at the node. The subtree is either the complete
    # tree or the where expression limits its size somehow. A flag determines
    # if the starting node is included or not. 

    my ( $dbh,      # Database handle
         $node,     # Starting node or node id
         $table,    # Table(s) with node information
         $edges,    # Table with edges 
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         $include,  # Include given node boolean - OPTIONAL, default true
         ) = @_;

    # Returns a nodes hash. 
    
    if ( not $select ) {
        $select = "$id_name,parent_ids,name";
    }

    $include = 1 if not defined $include;

    my ( $parent_id, $sql, $ids, $nodes, $p_nodes );

    if ( ref $node ) {
        $parent_id = $node->{ $id_name };
    } else {
        $parent_id = $node;
    }

    if ( not $table ) {
        &error( qq (The name of a nodes table must be given) );
    }

    if ( not $edges ) {
        &error( qq (The name of an edges table must be given) );
    }

    if ( $where ) {
        $sql = qq (select sql_cache $edges.$id_name from $edges where parent_id = $parent_id and $where);
    } else {
        $sql = qq (select sql_cache $edges.$id_name from $edges where parent_id = $parent_id);
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name );
    $ids = &Common::DAG::Nodes::get_ids_all( $nodes );

    $nodes = &Common::DAG::DB::get_nodes( $dbh, $ids, $table, $edges, $select, $where );

    if ( $include )
    {
        $p_nodes = &Common::DAG::DB::get_nodes( $dbh, [ $parent_id ], $table, $edges, $select, 
                                                "$edges.$id_name = $parent_id" );

        $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );
    }

    return wantarray ? %{ $nodes } : $nodes;
}

sub query_ids
{
    # Niels Larsen, October 2004.
    
    # Runs a query on the sub-hierarchy given by its topmost node id 
    # and returns the ids of the nodes that match. The optional where
    # expression will filter the match. 

    my ( $dbh,      # Database handle
         $id,       # Starting node id
         $tables,   # Table(s) with node information
         $where,    # Query expression - OPTIONAL
         ) = @_;
    
    # Returns an array of ids.
    
    my ( $sql, @nodes );

    if ( $where ) {
        $sql = qq (select sql_cache $id_name from $tables where parent_id = $id and $where);
    } else {
        $sql = qq (select sql_cache $id_name from $tables where parent_id = $id);
    }

    @nodes = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    
    if ( @nodes ) {
        return wantarray ? @nodes : \@nodes;
    } else {
        return wantarray ? () : [];
    }            
}

1;

__END__


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
 
