package GO::Nodes;        #  -*- perl -*-

# This module supports memory manipulation of "directed acyclic graphs"
# in support of the Gene Ontology data. These graphs are hierarchies except
# that a given node can have multiple parents. One may talk about "subtrees",
# since the graph is acyclic one can "flatten" it by adding the required 
# duplications. Like hierarchies they are implemented as a hash of hashes,
# but each node have at least these keys and values, 
#
#             "id" => Node ID
#     "parent_ids" => List of immediate parent node ID's
#    "parent_rels" => List of immediate parent node relations ('%' or '<')
#   "children_ids" => List of children node ID's
#  "children_rels" => List of children node relations ('%' or '<')
#
# We call such a hash a node. Keys like "name" and "type" are often used 
# in addition, but that is up to the application that uses this library. 
#
# If you need to handle this type of graph for other than GO, the best way
# is to make a copy of this module and update the routines. You may not 
# need for example the parent and children relations. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( store retrieve dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &new_node

                 &is_leaf

                 &get_alt_name
                 &get_id
                 &get_id_root
                 &get_ids_all
                 &get_ids_parents
                 &get_ids_parents_all
                 &get_ids_children
                 &get_ids_subtree
                 &get_ids_subtree_total
                 &get_ids_subtree_unique
                 &get_ids_subtree_label
                 &get_key
                 &get_rels_children
                 &get_rels_parents
                 &get_name
                 &get_node
                 &get_node_root
                 &get_nodes_all
                 &get_nodes_list
                 &get_nodes_ancestor
                 &get_parents
                 &get_parents_all
                 &get_children
                 &get_children_list
                 &get_subtree
                 &get_label
                 &get_name
                 &get_type

                 &add_child_id
                 &add_node

                 &set_id
                 &set_node
                 &set_node_col_value
                 &set_node_col_status
                 &set_name
                 &set_type
                 &set_ids_parents
                 &set_ids_children
                 &set_ids_children_all
                 &set_ids_children_subtree
                 &set_label
                 &set_label_all
                 &set_label_subtree
                 &set_labels
                 &set_labels_list
                 &set_depth_all
                 &set_rels_children
                 &set_rels_parents

                 &delete_id_parent
                 &delete_ids_child_orphan
                 &delete_ids_parent_orphan
                 &delete_label
                 &delete_label_all
                 &delete_label_subtree
                 &delete_node
                 &delete_subtree

                 &copy_node
                 &merge_node
                 &merge_nodes

                 &traverse_head
                 &traverse_tail
                 );

use Common::Messages;


# >>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub new_node
{
    # Niels Larsen, October 2003.

    # Initializes a node.

    my ( $id,       # Node id - OPTIONAL
         $p_ids,    # Parent node ids - OPTIONAL
         $c_ids,    # Children node ids - OPTIONAL
         $p_rels,   # Parent relations - OPTIONAL
         $c_rels,   # Children relations - OPTIONAL
         ) = @_;

    # Returns a node hash.
    
    my ( $node );

    $node = { 
        "go_id" => defined $id ? $id : undef,
        "parent_ids" => &Storable::dclone( $p_ids ) || [],
        "children_ids" => &Storable::dclone( $c_ids ) || [],
        "parent_rels" => &Storable::dclone( $p_rels ) || [],
        "children_rels" => &Storable::dclone( $c_rels ) || [],
    };

    return $node;
}

sub is_leaf
{
    # Niels Larsen, February 2004.

    # Tests if a given node is a leaf in the tree or not. 

    my ( $node,
         ) = @_;

    # Returns 1 or nothing.

    if ( defined $node->{"leaf"} )
    {
        if ( $node->{"leaf"} ) {
            return 1;
        } else {
            return;
        }
    }
    else
    {
        &error( qq (Node is missing the "leaf" key, cannot test if node is a leaf without it.) );
        exit;
    }
}

sub get_alt_name
{
    # Niels Larsen, January 2005.

    # Returns the attribute "alt_name" of a node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    if ( exists $node->{"alt_name"} ) {
        return $node->{"alt_name"};
    } else {
        return;
    }
}

sub get_id
{
    # Niels Larsen, October 2003.

    # Returns the ID of a given node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    return $node->{"go_id"};
}

sub get_id_root
{
    # Niels Larsen, October 2003.

    # Returns the id of the root node in a given nodes hash. Parent
    # ids must be set. 

    my ( $nodes,     # Nodes hash
         $id,        # Seed id - OPTIONAL
         ) = @_;

    # Returns a scalar. 

    if ( not defined $id ) {
        $id = each %{ $nodes };
    }

    my ( $node );

    $node = $nodes->{ $id };

    while ( $node->{"parent_ids"} and @{ $node->{"parent_ids"} } )
    {
        $id = $node->{"parent_ids"}->[0];
        $node = $nodes->{ $id };
    }

    return $id;
}

sub get_ids_all
{
    # Niels Larsen, October 2003.

    # Returns all ids for a given nodes hash.

    my ( $nodes,     # Node hash
         ) = @_;

    # Returns a scalar. 

    my ( @ids );

    @ids = keys %{ $nodes };

    return wantarray ? @ids : \@ids;
}

sub get_ids_parents
{
    # Niels Larsen, October 2003.

    # Returns the ids of the immediate parents of a given node.

    my ( $node,     # Node hash
         ) = @_;
    
    # Returns an array. 

    my ( @ids );

    if ( $node->{"parent_ids"} ) {
        @ids = @{ $node->{"parent_ids"} };
    } else {
        @ids = ();
    }

    return wantarray ? @ids : \@ids;
}

sub get_ids_parents_all
{
    # Niels Larsen, October 2003.

    # Creates a list of Ids of all nodes of all parents of a given 
    # starting node all the way to the root. 

    my ( $nodes,   # Nodes 
         $nid,     # Starting node
         ) = @_;

    # Returns a list.

    my ( @ids, $parents );

    $parents = &GO::Nodes::get_parents_all( $nodes, $nid );

    @ids = keys %{ $parents };

    return wantarray ? return @ids : \@ids;
}

sub get_ids_children
{
    # Niels Larsen, October 2003.

    # Returns the children Ids of a node, if any.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a list.

    my ( @ids );
    
    if ( exists $node->{"children_ids"} and @{ $node->{"children_ids"} } )
    {
        @ids = @{ $node->{"children_ids"} };
        return wantarray ? @ids : \@ids;
    }
    else
    {
        return;
    }
}

sub get_key
{
    # Niels Larsen, October 2003.

    # Retrieves a scalar nodes attribute, which may be a reference.

    my ( $node,     # Node reference
         $key,      # Name of key
         ) = @_;

    # Returns a scalar or nothing.

    if ( exists $node->{ $key } ) {
        return $node->{ $key };
    } else {
        return;
    }
}

sub get_rels_children
{
    # Niels Larsen, December 2003.

    # Returns the children relations of a node, if any.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a list.

    my ( @rels );
    
    if ( exists $node->{"children_rels"} and @{ $node->{"children_rels"} } )
    {
        @rels = @{ $node->{"children_rels"} };
        return wantarray ? @rels : \@rels;
    }
    else
    {
        return;
    }
}

sub get_rels_parents
{
    # Niels Larsen, December 2003.

    # Returns the children relations of a node, if any.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a list.

    my ( @rels );
    
    if ( exists $node->{"parent_rels"} and @{ $node->{"parent_rels"} } )
    {
        @rels = @{ $node->{"parent_rels"} };
        return wantarray ? @rels : \@rels;
    }
    else
    {
        return;
    }
}

sub get_ids_subtree
{
    # Niels Larsen, December 2003.

    # Creates a list of IDs of all nodes within the subtree starting at a 
    # given node. By default the root node is included. 

    my ( $nodes,     # Nodes 
         $nid,       # Subtree root node id
         $include,   # Whether to include root node
         ) = @_;

    # Returns a list.

    $include = 1 if not defined $include;

    my ( @temp_ids, @ids, $id );

    @ids = &GO::Nodes::get_ids_children( $nodes->{ $nid } );

    foreach $id ( @ids )
    {
        push @ids, &GO::Nodes::get_ids_children( $nodes->{ $id } );
    }
    
    if ( $include ) {
        unshift @ids, $nid;
    }
    
    return wantarray ? return @ids : \@ids;
}

sub get_ids_subtree_total
{
    # Niels Larsen, October 2003.

    # Counts the number of ids in the sub-graph starting at a given node. 

    my ( $nodes,     # Nodes 
         $nid,       # Subtree root node id
         $count,     # Node count
         ) = @_;

    # Returns a list.

    my ( @ids, $id );

    @ids = &GO::Nodes::get_ids_children( $nodes->{ $nid } );

    $count += scalar @ids;
    
    foreach $id ( @ids )
    {
        $count = &GO::Nodes::get_ids_subtree_total( $nodes, $id, $count );
    }
    
    return $count;
}

sub get_ids_subtree_unique
{
    # Niels Larsen, October 2003.

    # Creates a hash where keys are the ids of all nodes within the 
    # subtree starting at a given node. If a node has been encountered
    # already it is skipped.

    my ( $nodes,   # Nodes 
         $nid,     # Subtree root node id
         $nids,    # Hash of ids
         ) = @_;

    # Returns a hash.

    $nids = {} if not defined $nids;

    my ( $id );

    foreach $id ( &GO::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        if ( not exists $nids->{ $id } )
        {
            $nids->{ $id } = 1;
            $nids = &GO::Nodes::get_ids_subtree_unique( $nodes, $id, $nids );
        }
    }
    
    return wantarray ? return %{ $nids } : $nids;
}

sub get_ids_subtree_label
{
    # Niels Larsen, February 2004.

    # Creates a list of IDs of all nodes within the subtree starting at a 
    # given node. By default the root node is included. 

    my ( $nodes,     # Nodes 
         $nid,       # Subtree root node id
         $label,     # Label key
         ) = @_;

    # Returns a list.

    my ( $subref, $argref, @ids );

    $subref = sub
    {
        my ( $nodes, $nid, $label, $ids ) = @_;

        if ( $nodes->{ $nid }->{ $label } )
        {
            push @{ $ids }, $nid;
        }
    };
    
    $argref = [ $label, \@ids ];
    
    &Taxonomy::Nodes::tree_traverse_tail( $nodes, $nid, $subref, $argref );

    return wantarray ? return @ids : \@ids;
}

sub get_ids_label_all
{
    # Niels Larsen, October 2003.

    # Creates a list of all node ids where a given attribute
    # is set. If a value is given then the nodes must have that 
    # value to be included, otherwise the existense of the key
    # is enough.

    my ( $nodes,     # Node reference
         $key,       # Name of key
         $value,     # Label value - OPTIONAL
         ) = @_;

    my ( $id, $node, @ids );

    if ( $value )
    {
        foreach $id ( keys %{ $nodes } )
        {
            $node = $nodes->{ $id };

            if ( $node->{ $key } and $node->{ $key} eq $value ) {
                push @ids, $node->{"go_id"};
            }
        }
    }
    else
    {
        foreach $id ( keys %{ $nodes } )
        {
            $node = $nodes->{ $id };

            if ( exists $node->{ $key } ) {
                push @ids, $node->{"go_id"};
            }
        }
    }

    return wantarray ? @ids : \@ids;
}

sub get_node
{
    # Niels Larsen, October 2003.

    # Returns a node reference from a given structure with a given id.

    my ( $nodes,      # Nodes hash
         $id,         # Node id
         ) = @_;

    # Returns a node hash.

    my ( $node );

    if ( $node = $nodes->{ $id } )
    {
        return $node;
    }
    else {
        &error( qq (Node id does not exist -> "$id") );
        exit;
    }
}

sub get_node_root
{
    # Niels Larsen, October 2003.

    # Returns the root node in a given nodes hash. Parent ids
    # must be set. 

    my ( $nodes,     # Nodes hash
         $id,        # Seed id - OPTIONAL
         ) = @_;

    # Returns a scalar. 

    if ( not defined $id ) {
        $id = ( keys %{ $nodes } )[0];
    }

    my ( $node );

    $node = $nodes->{ $id };

    while ( $node->{"parent_ids"} and @{ $node->{"parent_ids"} } )
    {
        $id = $node->{"parent_ids"}->[0];
        $node = $nodes->{ $id };
    }

    return $node;
}

sub get_nodes_all
{
    # Niels Larsen, January 2005.

    # Returns all nodes as an unsorted list of node hashes. 

    my ( $nodes,
         ) = @_;

    # Returns a list. 

    my ( @nodes );

    @nodes = values %{ $nodes };

    return wantarray ? @nodes : \@nodes;
}
    
sub get_nodes_list
{
    # Niels Larsen, October 2003.

    # Returns all nodes of a given nodes hash as a list of nodes.

    my ( $nodes,    # Nodes hash
         ) = @_;

    # Returns an array. 

    my ( @nodes, $id );

    foreach $id ( keys %{ $nodes } )
    {
        push @nodes, $nodes->{ $id };
    }

    return wantarray ? @nodes : \@nodes;
}

sub get_nodes_ancestor
{
    # Niels Larsen, October 2003.

    # Returns the top node of the smallest subtree that exactly spans 
    # all nodes in a given list of node ids. Both "parent_ids" and 
    # "children_ids" have to be set for the routine to work. 

    my ( $nodes,    # Nodes hash
         $ids,      # List of ids
         ) = @_;
    
    # Returns a node hash.

    my ( $id, $parents, $p_hash, $node, $p_id, %ids, $count, @p_ids, 
         @span_ids, $root_id, $top_id );

    foreach $id ( @{ $ids } )
    {
        $parents = &GO::Nodes::get_parents_all( $nodes, $nodes->{ $id } );

        foreach $p_id ( keys %{ $parents } )
        {
            $p_hash->{ $p_id }->{ $id } = 1;
        }
    }

    %ids = map { $_, 1 } @{ $ids };
    $count = keys %ids;

    $p_id = &GO::Nodes::get_id_root( $nodes );

    while ( scalar keys %{ $p_hash->{ $p_id } } == $count )
    {
        @p_ids = ();

        foreach $id ( @{ $nodes->{ $p_id }->{"children_ids"} } )
        {
            if ( scalar keys %{ $p_hash->{ $id } } == $count ) {
                push @p_ids, $id;
            }
        }

        if ( scalar @p_ids == 1 ) {
            $p_id = $p_ids[0];
        } else {
            $top_id = $p_id;
            last;
        }
    }
    
    return $nodes->{ $top_id };
}

sub get_parents
{
    # Niels Larsen, October 2003.

    # Returns a hash with the immediate parents of a given node, as taken
    # from a given nodes hash. 

    my ( $nodes,     # Nodes hash
         $node,      # Node or node id
         ) = @_;

    # Returns an array.

    if ( not ref $node ) {
        $node = $nodes->{ $node };
    }

    my ( $id, $parents );

    foreach $id ( @{ $node->{"parent_ids"} } )
    {
        if ( exists $nodes->{ $id } ) {
            $parents->{ $id } = $nodes->{ $id };
        } else {
            $parents = {};
        }
    }
    
    return wantarray ? %{ $parents } : $parents;
}

sub get_parents_all
{
    # Niels Larsen, October 2003.

    # Returns a hash with all parents of a given node, as taken from 
    # a given nodes hash. The logic starts at a given node and works 
    # its way toward the top; however parents which have already been
    # registered are skipped. 

    my ( $nodes,      # Nodes hash
         $node,       # Node or node id
         $parents,    # Parents hash - OPTIONAL
         ) = @_;

    # Returns a nodes hash.

    $node = $nodes->{ $node } if not ref $node;

    my ( $p_nodes, $p_nodes2, $p_id );

    $p_nodes = &GO::Nodes::get_parents( $nodes, $node );

    foreach $p_id ( keys %{ $p_nodes } )
    {
        if ( not exists $parents->{ $p_id } )
        {
            $parents->{ $p_id } = $p_nodes->{ $p_id };

            $p_nodes2 = &GO::Nodes::get_parents_all( $nodes, $nodes->{ $p_id }, $parents );
            $parents = { %{ $parents }, %{ $p_nodes2 } };
        }
    }
    
    return wantarray ? %{ $parents } : $parents;
}
 
sub get_children
{
    # Niels Larsen, October 2003.

    # Returns, as a nodes hash, the children nodes of a given node. 
    # An empty hash is returned if there are no children.

    my ( $nodes,   # Nodes hash
         $nid,     # Starting node ID
         ) = @_;

    # Returns a hash.

    my ( $id, %children );
    
    %children = ();

    foreach $id ( &GO::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        $children{ $id } = $nodes->{ $id };
    }

    return wantarray ? %children : \%children;
}

sub get_children_list
{
    # Niels Larsen, October 2003.

    # Returns, as an array, the children nodes of a given node. The 
    # empty list is returned if there are no children.

    my ( $nodes,   # Nodes hash
         $nid,     # Starting node ID
         ) = @_;

    # Returns a list.

    my ( $id, @children );
    
    @children = ();

    foreach $id ( &GO::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        if ( exists $nodes->{ $id } ) {
            push @children, $nodes->{ $id };
        } else {
            &error( qq (Child node "$id" does not exist.) );
            exit;
        }
    }

    return wantarray ? @children : \@children;
}

sub get_subtree 
{
    # Niels Larsen, October 2003.

    # Creates a hash of all nodes within the subtree starting at a 
    # given node. The third boolean argument says if the starting 
    # node should be included or not. 

    my ( $nodes,   # Nodes 
         $nid,     # Subtree root node id
         $bool,    # Whether to include originating node
         ) = @_;

    # Returns a list.

    $bool = 0 if not defined $bool;

    my ( %children, %children2, $child_id );

    %children = &GO::Nodes::get_children( $nodes, $nid );

    foreach $child_id ( keys %children )
    {
        %children2 = &GO::Nodes::get_subtree( $nodes, $child_id, 0 );
        %children = ( %children, %children2 );
    }

    if ( $bool ) {
        $children{ $nid } = $nodes->{ $nid };
    }

    return wantarray ? return %children : \%children;
}

sub get_label 
{
    # Niels Larsen, October 2003.

    # Retrieves the value for a given key from a given node. 
    # The value may be a reference.

    my ( $node,     # Node reference
         $key,      # Name of key
         ) = @_;

    # Returns a scalar or nothing.

    if ( exists $node->{ $key } ) {
        return $node->{ $key };
    } else {
        return;
    }
}

sub get_name
{
    # Niels Larsen, October 2003.

    # Returns the value of the key "name" of a node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    if ( exists $node->{"name"} ) {
        return $node->{"name"};
    } else {
        return;
    }
}

sub get_type
{
    # Niels Larsen, October 2003.

    # Returns the value of the key "type" of a node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    if ( exists $node->{"type"} ) {
        return $node->{"type"};
    } else {
        return;
    }
}

sub add_child_id
{
    # Niels Larsen, October 2003

    # Adds a child ID to the node of a given node. 

    my ( $node,    # Node hash
         $nid,     # Node ID
         ) = @_;

    # Returns a node reference.

    push @{ $node->{"children_ids"} }, $nid;

    return $node;
}

sub add_node
{
    # Niels Larsen, February 2004.

    # Adds a given node to a given node hash. The parents given by 
    # the new node will have the node's id added to their children.
    # The children will similarly have the node's id added to their
    # list of parents. 

    my ( $nodes,    # Existing nodes hash
         $node,     # New node
         ) = @_;

    # Returns an updated nodes hash.

    my ( $node_id, $p_id, $c_id, $i );

    # First set parents of the children and their relations,

    $node_id = &GO::Nodes::get_id( $node );

    for ( $i = 0; $i <= $#{ $node->{"children_ids"} }; $i++ )
    {
        $c_id = $node->{"children_ids"}->[ $i ];

        if ( exists $nodes->{ $c_id } )
        {
            push @{ $nodes->{ $c_id }->{"parent_ids"} }, $node_id;
            push @{ $nodes->{ $c_id }->{"parent_rels"} }, $node->{"children_rels"}->[ $i ];
        }
    }

    # Then set the children of the parents and their relations,
    
    for ( $i = 0; $i <= $#{ $node->{"parent_ids"} }; $i++ )
    {
        $p_id = $node->{"parent_ids"}->[ $i ];
        
        if ( exists $nodes->{ $p_id } )
        {
            push @{ $nodes->{ $p_id }->{"children_ids"} }, $node_id;
            push @{ $nodes->{ $c_id }->{"children_rels"} }, $node->{"parent_rels"}->[ $i ];
        }
    }        
            
    return $nodes;
}

sub set_id
{
    # Niels Larsen, October 2003.

    # Sets the id of a node. 

    my ( $node,     # Node hash
         $id,       # Node id
         ) = @_;

    # Returns a node reference.

    $node->{"go_id"} = $id;

    return $node;
}

sub set_label 
{
    # Niels Larsen, October 2003.

    # Sets a node attribute. 

    my ( $node,     # Node reference
         $key,      # Attribute key
         $value,    # Attribute value
         ) = @_;

    # Returns a node reference.

    $node->{ $key } = $value;

    return $node;
}

sub set_node
{
    # Niels Larsen, October 2003.

    # Sets a given node in a given nodes hash. This means the
    # node gets overwritten if it exists already.
    
    my ( $nodes,    # Nodes hash
         $node,     # Child node
         ) = @_;

    # Returns an updated nodes hash.

    $nodes->{ $node->{"go_id"} } = &Storable::dclone( $node );

    return $nodes;
}

sub set_node_col_status
{
    # Niels Larsen, February 2004.

    my ( $node,
         $index,
         $value,
         ) = @_;

    $node->{"column_status"}->[ $index ] = $value;

    return $node;
}

sub set_node_col_value
{
    # Niels Larsen, February 2004.

    my ( $node,
         $index,
         $value,
         ) = @_;

    $node->{"column_value"}->[ $index ] = $value;

    return $node;
}

sub set_name
{
    # Niels Larsen, October 2003.

    # Sets the name attribute of a node. 

    my ( $node,     # Node hash
         $value,    # Name value
         ) = @_;

    # Returns a node reference.

    return &GO::Nodes::set_label( $node, "name", $value );
}

sub set_type
{
    # Niels Larsen, October 2003.

    # Sets the type attribute of a node. 

    my ( $node,      # Node hash
         $value,     # Type value
         ) = @_;

    # Returns a node reference.

    return &GO::Nodes::set_label( $node, "type", $value );
}

sub set_ids_parents
{
    # Niels Larsen, October 2003.

    # Sets the parent ids of a node. 

    my ( $node,     # Node hash
         $ids,      # Parent ids
         ) = @_;

    # Returns a node reference.

    $node->{"parent_ids"} = &Storable::dclone( $ids );

    return $node;
}

sub set_ids_children
{
    # Niels Larsen, October 2003.

    # Sets the children ids of a node. 

    my ( $node,     # Node hash
         $ids,      # Children ids
         ) = @_;

    # Returns a node reference.

    $node->{"children_ids"} = &Storable::dclone( $ids );

    return $node;
}

sub set_rels_children
{
    # Niels Larsen, October 2003.

    # Sets the children relation codes of a given node. 

    my ( $node,     # Node hash
         $rels,     # Parent relation codes
         ) = @_;

    # Returns a node reference.

    $node->{"children_rels"} = &Storable::dclone( $rels );

    return $node;
}

sub set_rels_parents
{
    # Niels Larsen, October 2003.

    # Sets the parent relation codes of a given node. 

    my ( $node,     # Node hash
         $rels,     # Parent relation codes
         ) = @_;

    # Returns a node reference.

    $node->{"parent_rels"} = &Storable::dclone( $rels );

    return $node;
}

sub set_ids_children_all
{
    # Niels Larsen, October 2003.

    # Using the existing parent ids, create a list of children ids 
    # for each node in a given set of nodes. Any existing children
    # ids are erased.

    my ( $nodes,    # Nodes hash
         $setrel,   # Whether to set relations - OPTIONAL, default on
         $warn,     # Whether to display warnings - OPTIONAL, default on
         ) = @_;

    # Returns updated nodes hash. 

    $setrel = 1 if not defined $setrel;
    $warn = 1 if not defined $warn;

    my ( @ids, $node, $id, $p_id, $i, $p_ids, $rel );

    @ids = keys %{ $nodes };

    foreach $id ( @ids )
    {
        $nodes->{ $id }->{"children_ids"} = [];
        $nodes->{ $id }->{"children_rels"} = [];
    }
    
    foreach $id ( @ids )
    {
        $node = $nodes->{ $id };
        $p_ids = $node->{"parent_ids"};
        
        next if not defined $p_ids;

        foreach ( $i = 0; $i < @{ $p_ids }; $i++ )
        {
            $p_id = $p_ids->[ $i ];

            if ( $id == $p_id ) 
            {
                &warning( qq (Node "$id" has same parent node ID) );
            }
            elsif ( not exists $nodes->{ $p_id } ) 
            {
                if ( $warn ) {
                    &warning( qq (Node "$id" has non-existing parent node ("$p_id") ) );
                    die;
                }
            }
            else
            {
                push @{ $nodes->{ $p_id }->{"children_ids"} }, $id;

                if ( $setrel )
                {
                    $rel = $node->{"parent_rels"}->[ $i ];
                    push @{ $nodes->{ $p_id }->{"children_rels"} }, $rel;
                }
            }
        }
    }

    return $nodes;
}

sub set_ids_children_subtree
{
    # Niels Larsen, December 2003.

    # Uses the parent ids (which must exist) to create a list of children
    # for all nodes that are within the subtree that starts at a given node
    # id. Any existing children ids within the subtree are deleted. 

    my ( $nodes,    # Nodes hash
         $nid,      # Node id
         $warn,     # Whether to display warnings - OPTIONAL, default on
         ) = @_;

    # Returns updated nodes hash. 

    $warn = 1 if not defined $warn;

    my ( $node, $id, $p_id, $sub_ids, $i, $p_ids, $rel );

    $sub_ids = &GO::Nodes::get_ids_subtree_unique( $nodes, $nid );

    foreach $id ( keys %{ $sub_ids } )
    {
        $nodes->{ $id }->{"children_ids"} = [];
        $nodes->{ $id }->{"children_rels"} = [];
    }
    
    foreach $id ( keys %{ $sub_ids } )
    {
        $node = $nodes->{ $id };
        $p_ids = $node->{"parent_ids"};
        
        for ( $i = 0; $i <= $#{ $p_ids }; $i++ )
        {
            $p_id = $p_ids->[ $i ];

            if ( $id == $p_id ) 
            {
                &warning( qq (Node "$id" has same parent node ID) );
            }
            elsif ( exists $sub_ids->{ $p_id } ) 
            {
                $rel = $node->{"parent_rels"}->[ $i ];

                push @{ $nodes->{ $p_id }->{"children_ids"} }, $id;
                push @{ $nodes->{ $p_id }->{"children_rels"} }, $rel;
            }
        }
    }

    return $nodes;
}

sub set_labels
{
    # Niels Larsen, October 2003.

    # Sets a given attribute for all nodes with ids included in a 
    # given list. If the fifth argument is set to true, nodes not 
    # in the list will have their attributes deleted. 

    my ( $nodes,    # Nodes hash
         $ids,      # Node ids to set attribute
         $key,      # Attribute key
         $value,    # Attribute value
         $remove,   # Whether to delete keys not in list
         ) = @_;

    # Returns a nodes hash. 

    my ( %ids, $id );

    if ( $remove )
    {
        %ids = map { $_, 1 } @{ $ids };

        foreach $id ( keys %{ $nodes } )
        {
            if ( exists $ids{ $id } ) {
                $nodes->{ $id }->{ $key } = $value;
            } else {
                delete $nodes->{ $id }->{ $key };
            }
        }
    }
    else
    {
        foreach $id ( @{ $ids } )
        {
            if ( exists $nodes->{ $id } ) {
                $nodes->{ $id }->{ $key } = $value;
            } else {
                &error( qq (Node id does not exist -> "$id") );
            }
        }
    }        

    return $nodes;
}
    
sub set_label_all
{
    # Niels Larsen, October 2003.

    # Sets a given attribute for all nodes in a given set of nodes.

    my ( $nodes,    # Nodes hash
         $key,      # Attribute key
         $value,    # Attribute value
         ) = @_;
    
    # Returns a nodes hash.
    
    my ( $id );

    foreach $id ( keys %{ $nodes } )
    {
        $nodes->{ $id }->{ $key } = $value;
    }

    return $nodes;
}

sub set_label_subtree 
{
    # Niels Larsen, October 2003.

    # Sets a given attribute for all nodes in a subtree starting at 
    # a given node.

    my ( $nodes,    # Nodes hash
         $nid,      # Node id 
         $key,      # Attribute key
         $value,    # Attribute value
         ) = @_;

    # Returns a node reference.

    my ( $child_id );

    $nodes->{ $nid }->{ $key } = $value;
    
    foreach $child_id ( &GO::Nodes::get_ids_children( $nodes->{ $nid  } ) )
    {
        &GO::Nodes::set_label_all( $nodes, $key, $child_id );
    }

    return $nodes;
}

sub set_labels_list
{
    # Niels Larsen, December 2003.

    # For every node in a given tree, sets an attribute if the 
    # node is in a given list. If not in the list, deletes the 
    # attribute. 

    my ( $nodes,    # Nodes hash
         $ids,      # Node ids to set attribute
         $key,      # Attribute key
         $value,    # Attribute value
         $delete,   # Deletes key from ids not in list
         ) = @_;

    # Returns a node reference.

    $delete = 0 if not defined $delete;

    my ( %ids, $id );

    %ids = map { $_, 1 } @{ $ids };

    foreach $id ( keys %{ $nodes } )
    {
        if ( exists $ids{ $id } ) {
            $nodes->{ $id }->{ $key } = $value;
        } elsif ( $delete ) {
            delete $nodes->{ $id }->{ $key };
        }
    }

    return $nodes;
}

sub set_depth_all
{
    # Niels Larsen, October 2003.

    # Sets the depth attribute for every node in a node hash. Children 
    # will have an integer one higher than their parent. The values start
    # at zero, but you may also pass a third argument to start the depths
    # off with. 
    
    my ( $nodes,      # Nodes hash
         $nid,        # Starting ID - OPTIONAL, default root node
         $depth,      # Current depth level - OPTIONAL, default 0
         ) = @_;
    
    # Returns nothing. 

    my ( $child_id );

    if ( not defined $nid ) {
        $nid = &GO::Nodes::get_id_root( $nodes );
    }

    $depth = 0 if not defined $depth;

    &GO::Nodes::set_label( $nodes->{ $nid }, "depth", $depth );

    foreach $child_id ( &GO::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &GO::Nodes::set_depth_tree( $nodes, $child_id, $depth+1 );
    }

    return;
}

sub delete_ids_child_orphan
{
    # Niels Larsen, February 2004.

    # For every node in a given nodes hash, removes all children ids for
    # which there is no existing node. 

    my ( $nodes,   # Nodes hash
         ) = @_;

    # Returns updated nodes hash.

    my ( $id, $c_id, $node, $i, @c_ids, @c_rels );
    
    foreach $id ( keys %{ $nodes } )
    {
        $node = $nodes->{ $id };

        $i = 0;
        @c_ids = ();
        @c_rels = ();
        
        foreach $c_id ( @{ $node->{"children_ids"} } )
        {
            if ( exists $nodes->{ $c_id } )
            {
                push @c_ids, $c_id;
                push @c_rels, $node->{"children_rels"}->[ $i ];
            }
            
            $i++;
        }
                        
        $node->{"children_ids"} = &Storable::dclone( \@c_ids );
        $node->{"children_rels"} = &Storable::dclone( \@c_rels );
    }

    return $nodes;
}

sub delete_ids_parent_orphan
{
    # Niels Larsen, December 2003.

    # For every node in a given nodes hash, removes all parent ids for
    # which there is no existing node. This is necessary because in a 
    # graph nodes can have parents that are not in the display graph. 

    my ( $nodes,   # Nodes hash
         ) = @_;

    # Returns updated nodes hash.

    my ( $id, $p_id, $node, $i, @p_ids, @p_rels );
    
    foreach $id ( keys %{ $nodes } )
    {
        $node = $nodes->{ $id };

        $i = 0;
        @p_ids = ();
        @p_rels = ();
        
        foreach $p_id ( @{ $node->{"parent_ids"} } )
        {
            if ( exists $nodes->{ $p_id } )
            {
                push @p_ids, $p_id;
                push @p_rels, $node->{"parent_rels"}->[ $i ];
            }
            
            $i++;
        }
                        
        $node->{"parent_ids"} = &Storable::dclone( \@p_ids );
        $node->{"parent_rels"} = &Storable::dclone( \@p_rels );
    }

    return $nodes;
}

sub delete_label
{
    # Niels Larsen, October 2003.

    # Deletes a given attribute from a given node.

    my ( $node,   # Node hash
         $key,    # Attribute key
         ) = @_;

    # Returns nothing.

    delete $node->{ $key };

    return;
}

sub delete_label_all
{
    # Niels Larsen, October 2003. 

    # Deletes a given attribute from every node in a given nodes hash.

    my ( $nodes,     # Nodes hash
         $key,       # Attribute key
         ) = @_;

    # Returns an updated nodes hash. 

    my ( $id );

    foreach $id ( keys %{ $nodes } )
    {
        delete $nodes->{ $id }->{ $key };
    }
    
    return $nodes;
}

sub delete_label_subtree
{
    # Niels Larsen, October 2003. 

    # Deletes a given attribute from nodes in a given nodes hash
    # that are within the subtree that has its root at the given 
    # node id. 

    my ( $nodes,     # Nodes hash
         $nid,       # Node id
         $key,       # Attribute key
         ) = @_;

    # Returns an updated nodes hash. 

    my ( $child_id );

    delete $nodes->{ $nid }->{ $key };
    
    foreach $child_id ( &GO::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &GO::Nodes::delete_label_all( $nodes, $child_id, $key );
    }

    return $nodes;
}

sub delete_node
{
    # Niels Larsen, December 2003.

    # Deletes a node of a given id from a given nodes hash, with update 
    # of children and parent ids and relations. This is the inverse of the
    # add_node routine, except the ids and relations are appended. A boolean
    # tells the routine to also delete all references to it in the children
    # lists of its parents. 

    my ( $nodes,    # Nodes hash
         $nid,      # ID of node to be deleted
         $bool,     # Boolean
         ) = @_;

    # Returns an updated nodes hash. 
    
    $bool = 1 if not defined $bool;

    my ( $p_node, $p_id, $c_node, $c_id, $i );

    if ( $bool )
    {
        # First set parents of the children and their relations,

        foreach $c_id ( @{ $nodes->{ $nid }->{"children_ids"} } )
        {
            if ( exists $nodes->{ $c_id } )
            {
                $c_node = $nodes->{ $c_id };

                for ( $i = 0; $i <= $#{ $c_node->{"parent_ids"} }; $i++ )
                {
                    if ( $c_node->{"parent_ids"}->[ $i ] == $nid )
                    {
                        splice @{ $c_node->{"parent_ids"} }, $i, 1;
                        splice @{ $c_node->{"parent_rels"} }, $i, 1;
                    }
                }
            }
            else {
                &error( qq (Node "$nid" has non-existing child node ("$c_id") ) );
                exit;
            }
        }



        foreach $p_id ( @{ $nodes->{ $nid }->{"parent_ids"} } )
        {
            if ( exists $nodes->{ $p_id } )
            {
                $p_node = $nodes->{ $p_id };

                for ( $i = 0; $i <= $#{ $p_node->{"children_ids"} }; $i++ )
                {
                    if ( $p_node->{"children_ids"}->[ $i ] == $nid )
                    {
                        splice @{ $p_node->{"children_ids"} }, $i, 1;

# Sometimes _rels are not in sync with _ids. The "children_rels" are
# not yet used, and this is a temporary fix. 

                        splice @{ $p_node->{"children_rels"} }, $i, 1;
                    }
                }
            }
            else {
                &error( qq (Node "$nid" has non-existing parent node ("$p_id") ) );
                exit;
            }
        }
    }
        
    delete $nodes->{ $nid };

    return $nodes;
}

sub delete_subtree
{
    # Niels Larsen, October 2003.

    # The subtree originating at a given node is deleted, except for the 
    # nodes that have parents outside the subtree. If the third argument 
    # is false, the given node itself is deleted too.

    my ( $nodes,   # Nodes hash
         $nid,     # Starting node ID
         $keep,    # Whether to keep starting node 
         ) = @_;

    # Returns a modified nodes hash.
    
    $keep = 1 if not defined $keep;

#    $nodes = &GO::Nodes::delete_ids_parent_orphan( $nodes );    

    my ( $sub_ids, $all_ids, $keep_ids, $id );

    $sub_ids = { map { $_, 1 } &GO::Nodes::get_ids_subtree( $nodes, $nid ) };
    $all_ids = { map { $_, 1 } &GO::Nodes::get_ids_all( $nodes ) };

    $keep_ids = { map { $_, 1 } grep { not exists $sub_ids->{ $_ } } keys %{ $all_ids } };

    if ( $keep ) {
        delete $sub_ids->{ $nid };
    }

    foreach $id ( keys %{ $sub_ids } )
    {
        if ( not grep { $keep_ids->{ $_ } } @{ $nodes->{ $id }->{"parent_ids"} } )
        {
            &GO::Nodes::delete_node( $nodes, $id, 1 );
        }
    }

#    $nodes = &GO::Nodes::delete_ids_parent_orphan( $nodes );    

    return $nodes;
}

sub copy_node
{
    # Niels Larsen, October 2003.

    # Makes a copy of a given node.

    my ( $node,    # Node hash
         ) = @_;

    # Returns a node hash.

    return &Storable::dclone( $node );
}

sub merge_node
{
    # Niels Larsen, October 2003.

    # Creates a node that has all keys in either of two given nodes. The
    # values are that of the first given node (no overwrite), but if the 
    # "clobber" argument is set the values from the second given node 
    # is used. 
    
    my ( $node1,     # Node hash
         $node2,     # Node hash
         $clobber,   # Boolean 
         ) = @_;

    # Returns a nodes hash.

    $clobber = 0 if not defined $clobber;
    
    my ( $new_node, $key );

    $new_node = &GO::Nodes::copy_node( $node1 );

    if ( $clobber )
    {
        foreach $key ( keys %{ $node2 } )
        {
            $new_node->{ $key } = $node2->{ $key };
        }
    }
    else 
    {
        foreach $key ( keys %{ $node2 } )
        {
            if ( not exists $new_node->{ $key } ) {
                $new_node->{ $key } = $node2->{ $key };
            }
        }
    }

    return $new_node;
}

sub merge_nodes
{
    # Niels Larsen, October 2003.

    # Adds to nodes1 all nodes in nodes2 that do not exist in nodes1.
    # The number of nodes in nodes2 that exist in nodes1 is returned.
    # If the third argument is true, the nodes in nodes2 are written
    # to nodes1 whether or not they exist there. 

    my ( $nodes1,    # Nodes that are added to
         $nodes2,    # Nodes to be added
         $clobber,   # Overwrite flag
         ) = @_;

    # Returns an integer. 

    $clobber = 0 if not defined $clobber;

    my ( $id1, $id2 );

    if ( $clobber )
    {
        foreach $id2 ( keys %{ $nodes2 } ) {
            $nodes1->{ $id2 } = &Storable::dclone( $nodes2->{ $id2 } );
        }
    }
    else
    {
        foreach $id2 ( keys %{ $nodes2 } )
        {
            if ( not exists $nodes1->{ $id2 } ) {
                $nodes1->{ $id2 } = &Storable::dclone( $nodes2->{ $id2 } );
            }
        }
    }

    return $nodes1;
}

sub traverse_tail
{
    # Niels Larsen, October 2003.

    # Does an action for each node in a subtree, given by its top node
    # ID. The action is done AFTER recursing to nodes with no children,
    # i.e. the traversal is depth-first. The action is defined outside 
    # this function and passed in as a subroutine reference plus a 
    # reference to an argument list. The subroutine is invoked with node
    # ID and node hash as first two arguments, then follows your list. 
    # So dont include node ID and node hash in this list. Your argument 
    # list may be empty. 

    my ( $nodes,      # Nodes hash
         $nid,        # Starting node ID
         $subref,     # Subroutine reference
         $argref,     # Reference to your subroutine arguments
         ) = @_;

    # Returns a reference to the tree (perhaps modified) after traversal.

    my ( $child_id );
    
    foreach $child_id ( &GO::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &GO::Nodes::traverse_tail( $nodes, $child_id, $subref, $argref );
    }

    $subref->( $nodes, $nid, @{ $argref } );
    
    return;
}

sub traverse_head
{
    # Niels Larsen, October 2003.

    # Does an action for each node in a subtree, given by its top node
    # ID. The action is done BEFORE recursing furher into the tree. The
    # action is defined outside this function and passed in as a subroutine 
    # reference plus a reference to an argument list. The subroutine is 
    # invoked with node ID and node hash as first two arguments, then 
    # follows your list. So dont include node ID and node hash in this 
    # list. Your argument list may be empty. 

    my ( $nodes,      # Nodes hash
         $nid,        # Starting node ID
         $subref,     # Subroutine reference
         $argref,     # Reference to your subroutine arguments
         ) = @_;

    # Returns a reference to the tree (perhaps modified) after traversal.

    my ( $child_id );

    $subref->( $nodes, $nid, @{ $argref } );

    foreach $child_id ( &GO::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &GO::Nodes::tree_traverse_head( $nodes, $child_id, $subref, $argref );
    }

    return;
}

1;

__END__

sub delete_id_parent
{
    # Niels Larsen, December 2003.

    # Deletes a given parent id from a given node and the corresponding
    # child id from its parent node.

    my ( $nodes,    # Nodes hash
         $id,       # Node id
         $p_id,     # Parent id
         ) = @_;

    # Returns an updated nodes hash.

    my ( $node );

    $nodes->{ $id }->{"parent_ids"} = [ grep { $_ != $p_id } @{ $nodes->{ $id }->{"parent_ids"} } ];

    $nodes->{ $p_id }->{"children_ids"} = [ grep { $_ != $id } @{ $nodes->{ $p_id }->{"children_ids"} } ];
    
    return $nodes;
}

sub delete_ids_outside_set
{
    # Niels Larsen, December 2003.

    # For a given list of nodes, removes all parent ids that point to nodes 
    # outside a given list of ids. Also, children ids that refer to such 
    # nodes are deleted. 

    my ( $nodes,     # Nodes hash
         $setids,    # Node ids
         ) = @_;

    # Returns updated nodes hash.

    my ( $id, $p_id, %setids );

    %setids = map { $_, 1 } @{ $setids };

    foreach $id ( @{ $setids } )
    {
        foreach $p_id ( @{ $nodes->{ $id }->{"parent_ids"} } )
        {
            if ( not exists $setids{ $p_id } ) 
            {
                $nodes = &GO::Nodes::delete_id_parent( $nodes, $id, $p_id );
            }
        }
    }

    return $nodes;
}

sub get_nodes_without_parent
{
    # Niels Larsen, October 2003.

    # Returns a list of nodes where the parent ids point to 
    # a node that does not exist in a given nodes hash.

    my ( $nodes,
         ) = @_;

    # Returns a list of node references.

    my ( $id, @nodes, $node );

    foreach $id ( keys %{ $nodes } )
    {
        $node = $nodes->{ $id };
        
        if ( not exists $nodes->{ $node->{"parent_ids"} } )
        {
            push @nodes, $node;
        }
    }

    return wantarray ? @nodes : \@nodes;
}
