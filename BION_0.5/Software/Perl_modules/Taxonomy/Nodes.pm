package Taxonomy::Nodes;        #  -*- perl -*-

# Routines that manipulate a node hierarchy. A hierarchy is represented
# as a hash of hashes, where each hash have a minimum of the following 
# mandatory keys and values,
#
#             "id" => Node ID
#      "parent_id" => Immediate parent node ID
#   "children_ids" => List of children node ID's
#
# We call such a hash a node. Keys like "name" and "type" are often
# used in addition, but that is up to the application that uses this 
# library. It is used by the web display and the statistics updates. 

use strict;
# use warnings FATAL => qw ( all );
use warnings;

use Storable qw ( store retrieve dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_child_id
                 &add_node
                 &clip_tree
                 &copy_node
                 &delete_label
                 &delete_label_tree
                 &delete_label_subtree
                 &delete_subtree
                 &get_alt_name
                 &get_children
                 &get_id
                 &get_ids_all
                 &get_ids_subtree
                 &get_id_parent
                 &get_ids_children
                 &get_ids_subtree_label
                 &get_key
                 &get_name
                 &get_node
                 &get_node_root
                 &get_nodes_all
                 &get_nodes_parent
                 &get_nodes_parents
                 &get_nodes_without_parent
                 &get_type
                 &is_leaf
                 &merge_nodes
                 &new_node
                 &reset_label_list
                 &set_id
                 &set_parent_id
                 &set_ids_children
                 &set_ids_children_all
                 &set_label
                 &set_label_list
                 &set_label_tree
                 &set_label_subtree
                 &set_name
                 &set_type
                 &set_depth_tree
                 &tree_traverse_head
                 &tree_traverse_tail
                 );

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $id_name_def = "tax_id";

sub new_node
{
    # Niels Larsen, October 2003.

    # Initializes a node.

    # Returns a node hash.

    return
    { 
        $id_name_def => "",
        "parent_id" => "",
        "children_ids" => [],
    }
}

sub get_node
{
    # Niels Larsen, October 2003.

    # Returns a node reference from a given structure with a given id.

    my ( $nodes,
         $id,
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

sub set_node
{
    # Niels Larsen, October 2003.

    # Sets a given node in a given nodes hash. This means the
    # node gets overwritten if it exists already.
    
    my ( $nodes,    # Nodes hash
         $node,     # Child node
         ) = @_;

    # Returns an updated nodes hash.

    $nodes->{ $node->{ $id_name_def } } = $node;

    return $nodes;
}

sub is_leaf
{
    # Niels Larsen, February 2004.

    # Tests if a given node is a leaf in the tree or not. 

    my ( $node,
         ) = @_;

    # Returns 1 or nothing.

    if ( $node->{"nmin"} == $node->{"nmax"} - 1 ) {
        return 1;
    } else {
        return;
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
    # Niels Larsen, May 2003.

    # Returns the ID of a node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    return $node->{ $id_name_def };
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

sub get_ids_subtree
{
    # Niels Larsen, May 2003.

    # Creates a list of IDs of all nodes within the subtree starting
    # at a given node, but excluding the starting node. 

    my ( $nodes,     # Nodes 
         $nid,       # Subtree root node id
         $include,   # Whether to include root node         
         ) = @_;

    # Returns a list.

    my ( @ids, $id );

    @ids = &Taxonomy::Nodes::get_ids_children( $nodes->{ $nid } );

    foreach $id ( @ids )
    {
        push @ids, &Taxonomy::Nodes::get_ids_children( $nodes->{ $id } );
    }
    
    if ( $include ) {
        unshift @ids, $nid;
    }

    return wantarray ? return @ids : \@ids;
}

sub get_id_parent
{
    # Niels Larsen, May 2003.

    # Returns the parent ID of a node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    return $node->{"parent_id"};
}

sub get_children
{
    # Niels Larsen, May 2003.

    # Returns the children nodes of a given node, if any. 

    my ( $nodes,   # Nodes hash
         $nid,     # Starting node ID
         ) = @_;

    # Returns a list.

    my ( $id, @children );
    
    foreach $id ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        push @children, $nodes->{ $id };
    }

    return wantarray ? @children : \@children;
}

sub get_ids_children
{
    # Niels Larsen, May 2003.

    # Returns the children IDs of a node, if any.

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

sub get_type
{
    # Niels Larsen, October 2003.

    # Returns the attribute "type" of a node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    if ( exists $node->{"type"} ) {
        return $node->{"type"};
    } else {
        return;
    }
}

sub get_name
{
    # Niels Larsen, October 2003.

    # Returns the attribute "name" of a node.

    my ( $node,     # Node hash
         ) = @_;

    # Returns a scalar. 

    if ( exists $node->{"name"} ) {
        return $node->{"name"};
    } else {
        return;
    }
}

sub add_child_id
{
    # Niels Larsen, August 2001

    # Adds a child ID to the node of a given node. 

    my ( $node,    # Nodes hash
         $nid,     # Node ID
         ) = @_;

    # Returns nothing, but updates the nodes hash.

    push @{ $node->{"children_ids"} }, $nid;

    return $node;
}

sub set_id
{
    # Niels Larsen, October 2003.

    # Sets the id of a node. 

    my ( $node,
         $id,
         ) = @_;

    # Returns a node reference.

    $node->{ $id_name_def } = $id;

    return $node;
}

sub set_parent_id
{
    # Niels Larsen, October 2003.

    # Sets the parent id of a node. 

    my ( $node,
         $p_id,
         ) = @_;

    # Returns a node reference.

    $node->{"parent_id"} = $p_id;

    return $node;
}

sub set_ids_children
{
    # Niels Larsen, October 2003.

    # Sets the children ids of a node. 

    my ( $node,
         $ids,
         ) = @_;

    # Returns a node reference.

    $node->{"children_ids"} = &Storable::dclone( $ids );

    return $node;
}

sub set_ids_children_all
{
    # Niels Larsen, May 2003.

    # Using the existing parent IDs, create a list of children IDs 
    # for each node in a given set of nodes. 

    my ( $nodes,    # Nodes hash
         $warn,
         ) = @_;

    # Returns updated nodes hash. 

    $warn = 1 if not defined $warn;

    my ( $node, @ids, $id, $parent_id );

    @ids = keys %{ $nodes };

    foreach $id ( @ids )
    {
        $nodes->{ $id }->{"children_ids"} = [];
    }
    
    foreach $id ( @ids )
    {
        $node = $nodes->{ $id };
        
        if ( $node->{ $id_name_def } == 1 )
        {
            $node->{"parent_id"} = 0;
        }
        else
        {
            $parent_id = $node->{"parent_id"};
            
            if ( $id == $parent_id ) 
            {
                &warning( qq (Node "$id" has same parent node ID) );
            }
            elsif ( not exists $nodes->{ $parent_id } ) 
            {
                if ( $warn ) {
                    &warning( qq (Node "$id" has non-existing parent node ("$parent_id") ) );
                }
            }            
            else
            {
                push @{ $nodes->{ $parent_id }->{"children_ids"} }, $id;
            }
        }
    }

    return $nodes;
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

sub set_label_list
{
    # Niels Larsen, October 2003.

    # Sets a given attribute for nodes in a given tree which
    # are included in a given list. 

    my ( $nodes,    # Nodes hash
         $ids,      # Node ids to set attribute
         $key,      # Attribute key
         $value,    # Attribute value
         ) = @_;

    # Returns a node reference.

    my ( $id );

    foreach $id ( @{ $ids } )
    {
        if ( exists $nodes->{ $id } ) {
            $nodes->{ $id }->{ $key } = $value;
        }
    }

    return $nodes;
}

sub reset_label_list
{
    # Niels Larsen, October 2003.

    # For every node in a given tree, sets an attribute if the 
    # node is in a given list. If not in the list, deletes the 
    # attribute. 

    my ( $nodes,    # Nodes hash
         $ids,      # Node ids to set attribute
         $key,      # Attribute key
         $value,    # Attribute value
         ) = @_;

    # Returns a node reference.

    my ( %ids, $id );

    %ids = map { $_, 1 } @{ $ids };

    foreach $id ( keys %{ $nodes } )
    {
        if ( exists $ids{ $id } ) {
            $nodes->{ $id }->{ $key } = $value;
        } else {
            delete $nodes->{ $id }->{ $key };
        }
    }

    return $nodes;
}

sub set_label_tree 
{
    # Niels Larsen, October 2003.

    # Sets a given attribute for all nodes in a given tree.

    my ( $nodes,    # Nodes hash
         $key,      # Attribute key
         $value,    # Attribute value
         ) = @_;

    # Returns a node reference.

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

    # Sets a given attribute for all nodes in a given tree.

    my ( $nodes,    # Nodes hash
         $nid,      # Node id 
         $key,      # Attribute key
         $value,    # Attribute value
         ) = @_;

    # Returns a node reference.

    my ( $cid );

    $nodes->{ $nid }->{ $key } = $value;
    
    foreach $cid ( &Taxonomy::Nodes::get_ids_children( $nodes, $nid ) )
    {
        &Taxonomy::Nodes::set_label_tree( $nodes, $key, $cid );
    }

    return $nodes;
}

sub set_name
{
    # Niels Larsen, October 2003.

    # Sets the name attribute of a node. 

    my ( $node,
         $value,
         ) = @_;

    # Returns a node reference.

    $node->{"name"} = $value;

    return $node;
}

sub set_type
{
    # Niels Larsen, October 2003.

    # Sets the type attribute of a node. 

    my ( $node,
         $value,
         ) = @_;

    # Returns a node reference.

    $node->{"type"} = $value;

    return $node;
}

sub set_depth_tree
{
    # Niels Larsen, April 2003.

    # Sets the depth attribute for every node in a node hash. Children 
    # will have an integer one higher than their parent. The values start
    # at zero, but you may also pass a third argument to start the depths
    # off with. 
    
    my ( $nodes,      # Nodes hash
         $nid,        # Starting ID
         $depth,      # Current depth level - OPTIONAL, default 0
         ) = @_;
    
    # Returns nothing. 

    my ( $child_id );
    
    $depth = 0 if not defined $depth;

    &Taxonomy::Nodes::set_label( $nodes->{ $nid }, "depth", $depth );

    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &Taxonomy::Nodes::set_depth_tree( $nodes, $child_id, $depth+1 );
    }

    return;
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

sub delete_label_tree
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
    
    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $nodes, $nid ) )
    {
        &Taxonomy::Nodes::delete_label_tree( $nodes, $child_id, $key );
    }

    return $nodes;
}

sub delete_subtree
{
    # Niels Larsen, May 2003.

    # The subtree originating at a given node is deleted. If the 
    # third argument is false, the given node itself is deleted too.

    my ( $nodes,   # Nodes hash
         $nid,     # Starting node ID
         $keep,    # Whether to keep starting node 
         ) = @_;

    # Returns nothing, but modifies the nodes. 

    $keep = 1 if not defined $keep;

    my ( $subref, $argref, $id, $parent_id, $parent_node );

    $subref = sub 
    {
        my ( $nodes, $nid ) = @_;

        delete $nodes->{ $nid };
    };

    $argref = [];

    foreach $id ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &Taxonomy::Nodes::tree_traverse_tail( $nodes, $id, $subref, $argref );
    }

    delete $nodes->{ $nid }->{"children_ids"};
    
    if ( not $keep ) {
        &Taxonomy::Nodes::delete_node( $nodes, $nid );
    }

    return $nodes;
}

sub clip_tree
{
    # Niels Larsen, November 2006.

    # 

    my ( $nodes,
         $expr,
         ) = @_;

    # Returns a hash.

    my ( $id, $node );

    while ( ( $id, $node ) = each %{ $nodes } )
    {
        &dump( "$node->{'name'} - $expr" );
        if ( $node->{"name"} =~ /$expr/i )
        {
            &dump( "delete -> $id" );
            &Taxonomy::Nodes::delete_subtree( $nodes, $id );
        }
    }

    return $nodes;
}

sub copy_node
{
    # Niels Larsen, October 2003.

    # Makes a copy of a given node.

    my ( $node,
         ) = @_;

    return &Storable::dclone( $node );
}

sub merge_nodes
{
    # Niels Larsen, May 2003.

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
    
sub get_nodes
{
    # Niels Larsen, October 2003.

    # Returns all nodes of a given nodes hash as a list of nodes
    # sorted by id.

    my ( $nodes,
         ) = @_;

    # Returns an array. 

    my ( @nodes, $id );

    foreach $id ( sort { $a <=> $b } keys %{ $nodes } )
    {
        push @nodes, $nodes->{ $id };
    }

    return wantarray ? @nodes : \@nodes;
}

sub get_node_root
{
    # Niels Larsen, February 2004.

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

    while ( $node->{"parent_id"} )
    {
        $id = $node->{"parent_id"};
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
    
sub get_nodes_parent
{
    # Niels Larsen, August 2003.

    # Returns the top node of the smallest subtree that exactly spans 
    # all nodes in a given list of node ids. 

    my ( $ids,      # List of ids
         $nodes,    # Nodes hash
         ) = @_;
    
    # Returns a node hash.

    my ( %ids, $id, $node, $p_id, $p_nodes, $p_node, @children );

    $p_nodes = {};

    foreach $id ( @{ $ids } )
    {
        $p_nodes->{ $id } = &Storable::dclone( $nodes->{ $id } );

        $p_id = &Taxonomy::Nodes::get_id_parent( $nodes->{ $id } );
                
        while ( $p_id and not exists $p_nodes->{ $p_id } )
        {
            $p_node = $nodes->{ $p_id };
            $p_nodes->{ $p_id } = &Storable::dclone( $p_node );
            $p_id = &Taxonomy::Nodes::get_id_parent( $p_node );
        }
    }

    $p_nodes = &Taxonomy::Nodes::set_ids_children_all( $p_nodes );

    $p_node = $p_nodes->{ 1 };
    $p_id = $p_node->{ $id_name_def };
    
    @children = &Taxonomy::Nodes::get_children( $p_nodes, 1 );

    %ids = map { $_, 1 } @{ $ids };

    while ( not $ids{ $p_id } and @children and scalar @children < 2 ) 
    {
        $p_node = $p_nodes->{ $children[0]->{ $id_name_def } };
        $p_id = $p_node->{ $id_name_def };

        @children = &Taxonomy::Nodes::get_children( $p_nodes, $p_node->{ $id_name_def } );
    }

    return $p_node;
}

sub get_nodes_parents
{
    # Niels Larsen, January 2004.

    # Returns a hash with the immediate parents of a given node, 
    # as taken from a given nodes hash. 

    my ( $nodes,     # Nodes hash
         $node,      # Node or node id
         $bool,      # Whether to include the given node
         ) = @_;

    # Returns an array.

    if ( not ref $node ) {
        $node = $nodes->{ $node };
    }

    $bool = 0 if not defined $bool;

    my ( $p_nodes, $p_node );

    if ( $bool ) {
        $p_nodes->{ $node->{ $id_name_def } } = &Storable::dclone( $node );
    }

    while ( $node->{"parent_id"} )
    {
        $p_node = $nodes->{ $node->{"parent_id"} };
        $p_nodes->{ $p_node->{ $id_name_def } } = &Storable::dclone( $p_node );

        $node = $p_node;
    }
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_nodes_without_parent
{
    # Niels Larsen, October 2003.

    # Returns a list of nodes where the parent id points to 
    # a node that does not exist in a given nodes hash.

    my ( $nodes,
         ) = @_;

    # Returns a list of node references.

    my ( $id, @nodes, $node );

    foreach $id ( keys %{ $nodes } )
    {
        $node = $nodes->{ $id };
        
        if ( not exists $nodes->{ $node->{"parent_id"} } )
        {
            push @nodes, $node;
        }
    }

    return wantarray ? @nodes : \@nodes;
}

sub tree_traverse_tail
{
    # Niels Larsen, May 2003.

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
         $argref,     # Reference to subroutine arguments
         ) = @_;

    # Returns a reference to the tree (perhaps modified) after traversal.

    my ( $child_id );

    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &Taxonomy::Nodes::tree_traverse_tail( $nodes, $child_id, $subref, $argref );
    }

    $subref->( $nodes, $nid, @{ $argref } );
    
    return;
}

sub tree_traverse_head
{
    # Niels Larsen, April 2003.

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
         $argref,     # Reference to subroutine arguments
         ) = @_;

    # Returns a reference to the tree (perhaps modified) after traversal.

    my ( $child_id );

    $subref->( $nodes, $nid, @{ $argref } );

    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        &Taxonomy::Nodes::tree_traverse_head( $nodes, $child_id, $subref, $argref );
    }

    return;
}

sub set_subtree_ids
{
    # Niels Larsen, May 2003.

    # Assigns two numbers to each node, as keys "nmin" and "nmax":
    # The left ID is the smallest ID in the subtree that starts at the 
    # node and the right ID is the highest. This makes it easy to get 
    # any subtree with SQL. 

    my ( $nodes,     # Nodes hash
         $nid,       # Node ID
         $count,    
         ) = @_;

    # Returns updated nodes hash. 

    my ( $child_id );

    $nodes->{ $nid }->{"nmin"} = ++$count;

    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $nid } ) )
    {
        $count = &Taxonomy::Nodes::set_subtree_ids( $nodes, $child_id, $count );
    }

    $nodes->{ $nid }->{"nmax"} = ++$count;

    return $count;
}

1;

__END__

# sub get_ids_subtree_label
# {
#     # Niels Larsen, October 2003.

#     # Creates a list of all node ids where a given attribute
#     # is set. If a value is given then the nodes must have that 
#     # value to be included, otherwise the existense of the key
#     # is enough.

#     my ( $nodes,     # Node reference
#          $key,       # Name of key
#          $value,     # Label value - OPTIONAL
#          ) = @_;

#     # Returns an array.

#     my ( $id, $node, @ids );

#     if ( $value )
#     {
#         foreach $id ( keys %{ $nodes } )
#         {
#             $node = $nodes->{ $id };

#             if ( $node->{ $key } and $node->{ $key} eq $value ) {
#                 push @ids, $node->{ $id_name_def };
#             }
#         }
#     }
#     else
#     {
#         foreach $id ( keys %{ $nodes } )
#         {
#             $node = $nodes->{ $id };

#             if ( exists $node->{ $key } ) {
#                 push @ids, $node->{ $id_name_def };
#             }
#         }
#     }

#     return wantarray ? @ids : \@ids;
# }
