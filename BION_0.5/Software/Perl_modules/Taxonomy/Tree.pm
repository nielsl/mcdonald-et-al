package Taxonomy::Tree;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that work with the tree structure used in Taxonomy::Profile.
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( *AUTOLOAD );

use List::Util;
use Tie::IxHash;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &count_columns
                 &count_leaves
                 &count_nodes
                 &delete_node
                 &filter_tree
                 &filter_min
                 &filter_regex
                 &filter_sum
                 &list_leaves
                 &list_nodes
                 &list_parents
                 &load_new_nodes
                 &load_new_parents
                 &max_depth
                 &print_taxa
                 &prune_level
                 &set_child_ids
                 &traverse_head
                 &traverse_tail
);

use Common::Config;
use Common::Messages;

use Common::Util_C;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> TREE STRUCTURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# A tree is a hash of nodes. A node is a list, its structure described below.
# Hash keys are node ids, which can be any string or integer. Nodes have 
# multiple children but only one parent. There are currently two additional 
# keys,
#
# col_headers => [ list of column header titles ]
# col_reads  => [ list of column input read totals ]
# 

our $Root_id = "tax_0";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> NODE STRUCTURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Nodes are lists like this one,
#
# node id => [ OTU name, parent id, node id, [ children ids ], OTU scores, .. ]
# 
# The indices into this value list is set by these constants, which are used
# in the code for readability,

use constant OTU_NAME => 0;      # Comes from storage, don't change
use constant PARENT_ID => 1;     # Comes from storage, don't change
use constant NODE_ID => 2;
use constant CHILD_IDS => 3;
use constant NODE_SUM => 4;
use constant DEPTH => 5;
use constant SIM_SCORES => 6;

# These constants can be changed and more added, but OTU_NAME and PARENT_ID 
# must remain 0 and 1, because they are pulled from a DBM storage and used with
# no change (the storage is created by Install::Import::index_table_table).
#
# The SIM_SCORES slot is a packed string that appears as a float array in the
# C routines that sum the scores. This is the top node of the tree,

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( %Tax_depths );

tie %Tax_depths, "Tie::IxHash";

%Tax_depths = (
    "r__" => 1,
    "k__" => 2,
    "p__" => 3,
    "c__" => 4,
    "o__" => 5,
    "f__" => 6,
    "g__" => 7,
    "s__" => 8,
    "n__" => 9,
    "+__" => 9,
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub count_columns
{
    # Niels Larsen, December 2012. 

    # Returns the number of value columns in a given tree. 

    my ( $tree,    # Nodes hash
        ) = @_;

    # Returns integer. 

    my ( @cols, $colnum );

    if ( ref $tree->{ $Root_id }->[SIM_SCORES] )
    {
        $colnum = scalar @{ $tree->{ $Root_id }->[SIM_SCORES] };
    }
    else 
    {
        @cols = unpack "f*", $tree->{ $Root_id }->[SIM_SCORES];
        $colnum = scalar @cols;
    }

    return $colnum;
}

sub count_leaves
{
    # Niels Larsen, May 2013.

    # Returns the number of nodes in the given tree that have no children. 

    my ( $tree,
        ) = @_;

    my ( $count );

    $count = grep { not @{ $_->[CHILD_IDS] } } values %{ $tree };

    return $count;
}

sub count_nodes
{
    # Niels Larsen, December 2012.

    # Returns the number of nodes in a given tree, starting at the given
    # node.

    my ( $tree,    # Nodes hash
         $nid,     # Starting id - OPTIONAL, default $Root_id
        ) = @_;

    # Returns integer. 

    my ( $subref, $argref, $count );

    $nid //= $Root_id;

    $subref = sub {};

    $count = &Taxonomy::Tree::traverse_tail( $tree, $nid, $subref );

    $count -= 1;    # Do not include root

    return $count;
}

sub delete_subtree
{
    # Niels Larsen, December 2012.

    # The subtree originating at a given node is deleted. The top node 
    # is deleted as well.

    my ( $nodes,   # Nodes hash
         $nid,     # Starting node ID
         $keep,
         ) = @_;

    # Returns nothing, but modifies the nodes. 

    my ( $subref, $argref, $cid, $pid );

    $keep //= 0;

    $subref = sub
    {
        my ( $nodes, $nid ) = @_;

        delete $nodes->{ $nid };
        
        return;
    };

    # Delete the subtrees that start at child nodes,
    
    foreach $cid ( @{ $nodes->{ $nid }->[CHILD_IDS] } )
    {
        &Taxonomy::Tree::traverse_tail( $nodes, $cid, $subref );
    }

    if ( $keep )
    {
        $nodes->{ $nid }->[CHILD_IDS] = [];
    }
    else
    {
        if ( defined ( $pid = $nodes->{ $nid }->[PARENT_ID] )
             and exists $nodes->{ $pid } )
        {
            @{ $nodes->{ $pid }->[CHILD_IDS] } = grep { $_ ne $nid } @{ $nodes->{ $pid }->[CHILD_IDS] };
        }

        delete $nodes->{ $nid };
    }

    return $nodes;
}

sub delete_node
{
    # Niels Larsen, December 2012. 

    my ( $nodes,
         $nid,
        ) = @_;

    my ( $node, $pid );

    # $node = &Storable::dclone( $nodes->{ $nid } );

    if ( $pid = $nodes->{ $nid }->[PARENT_ID] )
    {
        @{ $nodes->{ $pid }->[CHILD_IDS] } = grep { $_ ne $nid } @{ $nodes->{ $pid }->[CHILD_IDS] };
        
        delete $nodes->{ $nid };
    }

    return $nodes;
}

sub filter_tree
{
    # Niels Larsen, December 2012. 

    # A helper routine that reduces a given tree so that only the subtree is 
    # left that exactly spans nodes that satisfy a given callback routine that
    # tests each node. This routine is called with the given optional arguments
    # and it must 1) return 1 if the test succeeds and nothing otherwise, 2) 
    # have the tree as its first argument and 3) have a starting node id as 
    # its third argument. This filter_tree function can be used to build 
    # specific filter functions with simple arguments, see filter_min for
    # example. Returns the numbe of nodes in the resulting tree.

    my ( $nodes,     # Hash of nodes
         $rootid,    # Starting node id
         $subref,    # Routine reference
         $argref,    # Routine argument list
        ) = @_;

    # Returns integer.

    my ( $count, $nid, %keep, @keep, $kid, $pid, $routine );

    # >>>>>>>>>>>>>>>>>>>>>>>>> MARK MATCHING NODES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a { node-id => 1 } hash called %keep for all the nodes where the 
    # callback returns 1,

    $routine = sub 
    {
        my ( $nodes, $nid, $subref, @args ) = @_;

        my $count = 0;

        if ( $subref->( $nodes, $nid, @args ) )
        {
            $keep{ $nodes->{ $nid }->[NODE_ID] } = 1;
            $count = 1;
        }

        return $count;
    };
    
    &Taxonomy::Tree::traverse_tail( $nodes, $rootid, $routine, [ $subref, @{ $argref } ] );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MARK PARENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Add all parents to %keep so they will not be deleted below,

    @keep = keys %keep;

    foreach $kid ( @keep )
    {
        $nid = $kid;

        while ( exists $nodes->{ $nid } )
        {
            $keep{ $nid } = 1;

            if ( defined ( $pid = $nodes->{ $nid }->[PARENT_ID] ) ) {
                $nid = $pid;
            } else {
                last;
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE NODES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Delete all nodes that should not be kept,

    $routine = sub 
    {
        my ( $nodes, $nid, $keep ) = @_;
        
        if ( not $keep->{ $nid } ) {
            delete $nodes->{ $nid };
        }

        return;
    };

    &Taxonomy::Tree::traverse_tail( $nodes, $rootid, $routine, [ \%keep ] );

    # >>>>>>>>>>>>>>>>>>>>>>> REMOVE ABSENT CHILDREN <<<<<<<<<<<<<<<<<<<<<<<<<<

    $routine = sub
    {
        my ( $nodes,
             $nid,
            ) = @_;
        
        @{ $nodes->{ $nid }->[CHILD_IDS] } = 
            grep { exists $nodes->{ $_ } } @{ $nodes->{ $nid }->[CHILD_IDS] };
        
        return;
    };
    
    &Taxonomy::Tree::traverse_tail( $nodes, $rootid, $routine, [] );

    # Return the number of nodes left,

    $count = &Taxonomy::Tree::count_nodes( $nodes );

    return $count;
}

sub filter_min
{
    # Niels Larsen, December 2012. 

    # Reduces the tree so that only rows containing a score higher than a given
    # threshold are kept. 

    my ( $tree,      # Hash of nodes
         $minval,    # Minimum value
        ) = @_;

    # Returns nothing.

    my ( $colnum, $subref, $argref, $count );

    # Define function that checks the maximum value at the current node and 
    # returns 1 if at least the minimum,

    $subref = sub
    {
        my ( $nodes, $nid, $minval, $colnum ) = @_;
        
        if ( &Common::Util_C::max_value_float( $nodes->{ $nid }->[SIM_SCORES], $colnum ) >= $minval ) {
            return 1;
        }
        
        return;
    };

    # Submit this callback to the generic filter routine,

    $colnum = &Taxonomy::Tree::count_columns( $tree );
    $argref = [ $minval, $colnum ];
    
    $count = &Taxonomy::Tree::filter_tree( $tree, $Root_id, $subref, $argref );

    return $count;
}

sub filter_regex
{
    # Niels Larsen, December 2012. 

    # Reduces the tree so that only rows that match a given regular expression
    # are kept. 

    my ( $tree,      # Hash of nodes
         $regex,     # Regular expression
        ) = @_;

    # Returns nothing.

    my ( $subref, $argref, $count );

    # Define function that checks the maximum value at the current node and 
    # returns 1 if at least the minimum,

    $subref = sub
    {
        my ( $nodes, $nid, $regex ) = @_;
        
        if ( $nodes->{ $nid }->[OTU_NAME] =~ /$regex/i ) {
            return 1;
        }
        
        return;
    };

    # Submit this callback to the generic filter routine,

    $argref = [ $regex ];   
    $count = &Taxonomy::Tree::filter_tree( $tree, $Root_id, $subref, $argref );

    return $count;
}

sub filter_sum
{
    # Niels Larsen, December 2012. 

    # Reduces the tree so that only rows with a score sum higher than a given
    # threshold are kept. 

    my ( $tree,      # Hash of nodes
         $minsum,    # Minimum sum
        ) = @_;

    # Returns nothing.

    my ( $colnum, $subref, $argref, $count );

    # Define function that checks the maximum value at the current node and 
    # returns 1 if at least the minimum,

    $subref = sub
    {
        my ( $nodes, $nid, $minsum, $colnum ) = @_;
        
        if ( &Common::Util_C::sum_array_float( $nodes->{ $nid }->[SIM_SCORES], $colnum ) >= $minsum ) {
            return 1;
        }
        
        return;
    };

    # Submit this callback to the generic filter routine,

    $colnum = &Taxonomy::Tree::count_columns( $tree );
    $argref = [ $minsum, $colnum ];
    
    $count = &Taxonomy::Tree::filter_tree( $tree, $Root_id, $subref, $argref );

    return $count;
}

sub list_leaves
{
    # Niels Larsen, June 2013.

    # Returns a list of all leaf ids in the given tree, starting at the 
    # given node. A leaf is a node without child ids.

    my ( $tree,    # Nodes hash
         $nid,     # Starting id - OPTIONAL, default $Root_id
        ) = @_;

    # Returns a list. 

    my ( $subref, @ids );

    $nid //= $Root_id;

    $subref = sub
    {
        my ( $nodes, $nid ) = @_;

        if ( not @{ $nodes->{ $nid }->[CHILD_IDS] } )
        {
            push @ids, $nid;
        }

        return;
    };
    
    &Taxonomy::Tree::traverse_tail( $tree, $nid, $subref );

    return wantarray ? @ids : \@ids;
}

sub list_nodes
{
    # Niels Larsen, June 2013.

    # Returns the number of internal nodes in a given tree, starting at 
    # the given node.

    my ( $tree,    # Nodes hash
         $nid,     # Starting id - OPTIONAL, default $Root_id
        ) = @_;

    # Returns a list. 

    my ( $subref, @ids );

    $nid //= $Root_id;

    $subref = sub
    {
        my ( $nodes, $nid ) = @_;

        if ( @{ $nodes->{ $nid }->[CHILD_IDS] } )
        {
            push @ids, $nid;
        }

        return;
    };
    
    &Taxonomy::Tree::traverse_tail( $tree, $nid, $subref );

    return wantarray ? @ids : \@ids;
}

sub list_parents
{
    # Niels Larsen, June 2013.

    # Returns a list of all leaf immediate parent ids in the given tree,
    # starting at the given node. A leaf is a node without child ids.

    my ( $tree,    # Nodes hash
         $nid,     # Starting id - OPTIONAL, default $Root_id
        ) = @_;

    # Returns a list. 

    my ( $subref, %ids );

    $nid //= $Root_id;

    $subref = sub
    {
        my ( $nodes, $nid ) = @_;

        if ( not @{ $nodes->{ $nid }->[CHILD_IDS] } )
        {
            $ids{ $nodes->{ $nid }->[PARENT_ID] } = 1;
        }

        return;
    };
    
    &Taxonomy::Tree::traverse_tail( $tree, $nid, $subref );

    return wantarray ? keys %ids : [ keys %ids ];
}

sub load_new_nodes
{
    # Niels Larsen, November 2012. 

    # Helper function that adds nodes from a DBM key/value storage to a given
    # tree if missing. The missing are pulled from the store, including all 
    # parents. See the tree structure description at the top of this file.

    my ( $dbh,      # Open storage handle
         $ids,      # Taxonomy node id list
         $tree,     # Tree structure
        ) = @_;

    # Returns a hash.

    my ( $mis_ids, @new_ids, $nodes, $node_id, $parent_id );

    # >>>>>>>>>>>>>>>>>>>>>>>>> GET MISSING NODES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First pull missing nodes out of the storage, then below children ids are
    # added,

    @new_ids = ();
    $mis_ids = &Storable::dclone( $ids );

    while ( @{ $mis_ids } = grep { not exists $tree->{ $_ } } @{ $mis_ids } )
    {
        $nodes = &Common::DBM::get_struct_bulk( $dbh, $mis_ids );

        push @new_ids, @{ $mis_ids };

        $mis_ids = [];

        foreach $node_id ( keys %{ $nodes } )
        {
            $tree->{ $node_id } = &Storable::dclone( $nodes->{ $node_id } );
            $tree->{ $node_id }->[NODE_ID] = $node_id;
            $tree->{ $node_id }->[CHILD_IDS] = [];

            $parent_id = $nodes->{ $node_id }->[PARENT_ID];

            if ( defined $parent_id ) {
                push @{ $mis_ids }, $parent_id;
            }
        }
        
        $mis_ids = &Common::Util::uniqify( $mis_ids );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>> CONNECT NEW NODES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Add children ids,

    if ( @new_ids )
    {
        &Taxonomy::Tree::set_child_ids( $tree, \@new_ids );
    }

    return wantarray ? @new_ids : \@new_ids;
}

sub load_new_parents
{
    # Niels Larsen, January 2013. 

    # Adds nodes to a tree by pulling them from storage. Sets only parents,
    # not children, and does not add score vectors. The input $tree is 
    # changing and the number of nodes added is returned. 

    my ( $dbh,      # DBM handle
         $nids,     # Node ids
         $tree,     # Tree structure
        ) = @_;

    # Returns an integer.

    my ( @nids, $nodes, $nid, $node, $pid, $count );

    @nids = grep { not exists $tree->{ $_ } } @{ $nids };

    $count = 0;

    while ( @nids )
    {
        $nodes = &Common::DBM::get_struct_bulk( $dbh, \@nids );
        
        while ( ( $nid, $node ) = each %{ $nodes } )
        {
            if ( $node->[OTU_NAME] =~ /^(.__)/ )
            {
                $node->[NODE_ID] = $nid;
                $node->[DEPTH] = $Tax_depths{ $1 };
            }
            else {
                &error( qq (Wrong looking OTU name -> "$node->[OTU_NAME]") );
            }

            $tree->{ $nid } = &Storable::dclone( $node );
            
            $count += 1;
        }

        @nids = &Common::Util::uniqify([ grep { defined $_ } map { $_->[PARENT_ID] } values %{ $nodes } ]);
        @nids = grep { not exists $tree->{ $_ } } @nids;
    }

    return $count;
}

sub max_depth
{
    my ( $tree,
        ) = @_;

    my ( $node, $max );

    $max = 0;

    foreach $node ( values %{ $tree } )
    {
        if ( $node->[DEPTH] > $max )
        {
            $max = $node->[DEPTH];
        }
    }

    return $max;
}

sub print_taxa
{
    my ( $tree,
        ) = @_;

    my ( $subref );
    
    $subref = sub 
    {
        my ( $tree, $nid ) = @_;
        
        my ( $str, $pid, $oid );
 
        $str = $tree->{ $nid }->[OTU_NAME];

        $oid = $nid;
        
        while ( defined ( $pid = $tree->{ $nid }->[PARENT_ID] ) )
        {
            $str = $tree->{ $pid }->[OTU_NAME] ."; $str";
            $nid = $pid;
        }
        
        &dump( $oid ."\t". $str );

        return;
    };
    
    &Taxonomy::Tree::traverse_tail( $tree, $Root_id, $subref );
    
    return;
}

sub prune_level
{
    # Niels Larsen, December 2012. 

    # Clips the branches of a tree to a certain taxonomy level, like order, 
    # family, species - see the %Tax_levels hash at the top of this module.
    # Column values are summed up for the sub-trees that are clipped. The 
    # given tree is modified and the number of nodes in the pruned tree is 
    # returned. 

    my ( $tree,      # Nodes hash
         $level,     # Level name
        ) = @_;

    # Returns integer.

    my ( $count, $subref, $argref );

    $subref = sub 
    {
        my ( $nodes, $nid, $level ) = @_;
        
        my ( $cid, $sums, $node );

        $node = $nodes->{ $nid };

        if ( $node->[OTU_NAME] =~ /^$level/ )
        {
            $sums = &Taxonomy::Tree::sum_subtree( $nodes, $nid );

            $node->[SIM_SCORES] = $sums;

            foreach $cid ( @{ $node->[CHILD_IDS] } )
            {
                &Taxonomy::Tree::delete_subtree( $nodes, $cid );
            }

            $node->[CHILD_IDS] = [];
        }
        
        return;
    };

    $count = &Taxonomy::Tree::count_nodes( $tree );

    $argref = [ $level ];
    &Taxonomy::Tree::traverse_head( $tree, $Root_id, $subref, $argref );

    $count = &Taxonomy::Tree::count_nodes( $tree );

    return $count;
}

sub set_child_ids
{
    # Niels Larsen, January 2013.
    
    # 
    my ( $tree,
         $nids,
        ) = @_;

    my ( $node_id, $parent_id );

    foreach $node_id ( @{ $nids } )
    {
        if ( defined ( $parent_id = $tree->{ $node_id }->[PARENT_ID] ) )
        {
            if ( exists $tree->{ $parent_id } )
            {
                if ( not grep { $_ eq $node_id } @{ $tree->{ $parent_id }->[CHILD_IDS] } ) {
                    push @{ $tree->{ $parent_id }->[CHILD_IDS] }, $node_id;
                }
            }
            else {
                push @{ $tree->{ $parent_id }->[CHILD_IDS] }, $node_id;
            }                    
        }
    }
    
    return;
}

sub sum_parents_tree
{
    # Niels Larsen, December 2012. 

    # Accumulates scores from the leaves of the tree toward the basis, so that
    # all node values become cumulative. Modifies the given tree.

    my ( $tree,        # Hash of nodes
         $nid,         # Starting node id
        ) = @_;

    # Returns nothing.

    my ( $cid, $sums, $coltot );

    $nid //= $Root_id;

    $sums = $tree->{ $nid }->[SIM_SCORES];
    $coltot = scalar @{ $tree->{"col_headers"} };

    foreach $cid ( @{ $tree->{ $nid }->[CHILD_IDS] } )
    {
        if ( @{ $tree->{ $cid }->[CHILD_IDS] } )
        {
            &Taxonomy::Tree::sum_parents_tree( $tree, $cid );
        }

        &Common::Util_C::add_arrays_float( $sums, $tree->{ $cid }->[SIM_SCORES], $coltot );
    }

    $tree->{ $nid }->[SIM_SCORES] = $sums;

    return;
}

sub sum_subtree
{
    # Niels Larsen, December 2012. 

    # Returns a packed string with accumulated score values across a subtree, the 
    # starting node included. If a string is given, then that is added to.

    my ( $tree,      # Nodes hash
         $nid,       # Starting node id
         $sums,      # Sums string - OPTIONAL
        ) = @_;

    # Returns a string.

    my ( $subref, $argref, $colnum );

    $subref = sub 
    {
        my ( $tree, $nid, $sumref, $colnum ) = @_;

        &Common::Util_C::add_arrays_float( ${ $sumref }, $tree->{ $nid }->[SIM_SCORES], $colnum );
    };
    
    $colnum = &Taxonomy::Tree::count_columns( $tree );

    if ( not $sums ) {
        $sums = pack "f*", (0) x $colnum;
    }

    $argref = [ \$sums, $colnum ];

    &Taxonomy::Tree::traverse_head( $tree, $nid, $subref, $argref );

    return $sums;
}

sub traverse_head
{
    # Niels Larsen, December 2012.

    # Runs a given subroutine with given arguments for each node in a subtree,
    # starting with a given node ID. The routine is run before diving into 
    # sub-nodes. The subroutine and its arguments are defined outside this 
    # function and are passed as references so they can be modified. The 
    # first two arguments must be node hash and node id, then the rest. The 
    # argument list may be empty.
    
    my ( $nodes,      # Nodes hash
         $nid,        # Starting node ID
         $subref,     # Subroutine reference
         $argref,     # Reference to subroutine arguments
         ) = @_;

    # Returns a reference to the tree (perhaps modified) after traversal.

    my ( $cid, $count );

    $subref->( $nodes, $nid, @{ $argref } );

    $count = 1;
    
    foreach $cid ( @{ $nodes->{ $nid }->[CHILD_IDS] } )
    {
        if ( exists $nodes->{ $cid } )
        {
            $count += &Taxonomy::Tree::traverse_head( $nodes, $cid, $subref, $argref );
        }
        else {
            &error( qq ("Child node does not exist -> "$cid") );
        }
    }

    return $count;
}

sub traverse_tail
{
    # Niels Larsen, December 2012.

    # Runs a given subroutine with given arguments for each node in a subtree,
    # starting with a given node ID. The routine is run after diving into the
    # sub-nodes, i.e. the traversal is depth-first. Subroutine and its arguments 
    # are defined outside this function and are passed as references so they 
    # can be modified. The first two arguments must be node hash and node id, 
    # then the rest. The argument list may be empty.

    my ( $nodes,      # Tree nodes hash
         $nid,        # Starting node ID
         $subref,     # Subroutine reference
         $argref,     # Reference to subroutine arguments - OPTIONAL
         ) = @_;

    # Returns a reference to the tree (perhaps modified) after traversal.

    my ( $count, $cid );

    $count = 0;

    foreach $cid ( @{ $nodes->{ $nid }->[CHILD_IDS] } )
    {
        if ( exists $nodes->{ $cid } )
        {
            $count += &Taxonomy::Tree::traverse_tail( $nodes, $cid, $subref, $argref );
        }
    }

    $subref->( $nodes, $nid, @{ $argref } );

    $count += 1;
    
    return $count;
}

1;

__END__

# sub create_span_tree
# {
#     # Niels Larsen, January 2013. 
    
#     # Builds a memory tree structure of the minimal tree that spans and 
#     # includes the given node ids. If another memory tree is given, then 
#     # the nodes are copied from there instead of read from disk.

#     my ( $nids,        # List of node ids
#          $nodes,       # Existing nodes to copy from - OPTIONAL
#         ) = @_;

#     # Returns a hash.

#     my ( $dbh, $subref, $tree, @nids, $node, $nid, $pid );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> GET NODES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Get the nodes that span the given node id list, with all parents,

#     @nids = @{ $nids };

#     while ( @nids )
#     {
#         foreach $nid ( @nids )
#         {
#             if ( not $node = $nodes->{ $nid } ) {
#                 &error( qq (Node is not in cache -> "$nid") );
#             }

#             $tree->{ $nid }->[NODE_ID] = $nid;
#             $tree->{ $nid }->[PARENT_ID] = $node->[PARENT_ID];
#             $tree->{ $nid }->[OTU_NAME] = $node->[OTU_NAME];
#         }

#         @nids = &Common::Util::uniqify([ grep { defined $_ } map { $_->[1] } values %{ $nodes } ]);
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> CONNECT NODES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Add children lists for each node,

#     foreach $nid ( keys %{ $tree } )
#     {
#         if ( defined ( $pid = $tree->{ $nid }->[PARENT_ID] ) )
#         {
#             if ( defined $tree->{ $pid }->[CHILD_IDS] ) {
#                 push @{ $tree->{ $pid }->[CHILD_IDS] }, $nid;
#             } else {
#                 $tree->{ $pid }->[CHILD_IDS] = [ $nid ];
#             }
#         }
#     }
    
#     return wantarray ? %{ $tree } : $tree;
# }
