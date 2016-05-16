package Taxonomy::DB_nodes;        #  -*- perl -*-

# Functions that reach into a database to get a set of nodes. This
# is the module that contains the SQL statements, and we try to keep
# all of them in here. The hierarchy nodes have the following minimal
# structure,
# 
#

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_common_names
                 &close_node
                 &focus_node
                 &get_name_of_id
                 &get_id_of_name
                 &get_node
                 &get_nodes
                 &get_parents
                 &get_nodes_parents
                 &get_subtree
                 &match_ids
                 &match_text
                 &query
                 );

use Common::Config;
use Common::Messages;

use Common::DB;
use Taxonomy::Nodes;

our $id_name_def = "tax_id";
our $select_def = "tax_id,parent_id,name,depth,nmin,nmax";


# >>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_common_names
{
    # Niels Larsen, August 2003.

    # Adds common name as "alt_name" field to the given nodes. 
    # The default is to set the "alt_name" field only if it is
    # not set already. 

    my ( $dbh,        # Database handle
         $root,       # Starting node
         $nodes,      # Nodes hash
         $clobber,    # Whether to overwrite - OPTIONAL, default 0
         ) = @_;

    # Returns an updated nodes hash.

    my ( $sql, $nmin, $nmax, @matches, $match, $node );

    $clobber = 0 if not defined $clobber;

    $nmin = $root->{"nmin"};
    $nmax = $root->{"nmax"};

    $sql = qq (select tax_id,name from tax_nodes where nmin between $nmin and $nmax)
         . qq ( and (name_type = "common name" or name_type = "genbank common name") );

    @matches = &Common::DB::query_array( $dbh, $sql );
    
    if ( $clobber )
    {
        foreach $match ( @matches )
        {
            $node = $nodes->{ $match->[0] };
            $node->{"alt_name"} = $match->[1];
        }
    }
    else
    {
        foreach $match ( @matches )
        {
            $node = $nodes->{ $match->[0] };
            $node->{"alt_name"} = $match->[1] if not exists $node->{"alt_name"};
        }
    }

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_name_of_id
{
    # Niels Larsen, January 2004.

    # Returns the name of a node given by its id and table. 

    my ( $dbh,       # Database handle
         $id,        # Node id
         $tables,    # Tables string
         ) = @_;

    # Returns an integer. 

    die if not defined $id;
    my ( $sql, $nodes, @names, $count );

    $sql = qq (select sql_cache name from $tables where $id_name_def = "$id" and name_type = "scientific name");

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
    # Niels Larsen, May 2003.

    # Returns a node id given a node name and a table. 

    my ( $dbh,       # Database handle
         $name,      # Node name
         $tables,    # Tables string
         $select,    # Select string
         ) = @_;

    # Returns an integer.

    $select ||= $id_name_def;

    my ( $sql, $nodes, @ids, $ids );

    $sql = qq (select sql_cache $select from $tables where name = "$name");

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name_def );
    @ids = keys %{ $nodes };
    
    if ( scalar @ids == 1 ) 
    {
        return $ids[0];
    }
    else
    {
        $ids = scalar @ids;
        &error( qq (There should be 1 node with the name "$name", but found $ids) );
    }
}

sub get_node
{
    # Niels Larsen, May 2003.

    # Returns a single node from a given ID and a given table. The
    # fields returned depend on the select argument; default is 
    # "\$id_name_def,parent_id,name,depth,nmin,nmax". The where 
    # expression is used to qualify the query if ids are not unique. 

    my ( $dbh,      # Database handle
         $id,       # Node id 
         $tables,   # Table to fetch from
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;

    # Returns a node hash.

    if ( not $tables ) {
        &error( qq (The name of an existing table must be given) );
    }

    if ( not $select ) {
        $select = "$id_name_def,parent_id,name,depth,nmin,nmax";
    }

    my ( $sql, $nodes, $node );

    if ( $where ) {
        $sql = qq (select sql_cache $select from $tables where $id_name_def = $id and $where);
    } else {
        $sql = qq (select sql_cache $select from $tables where $id_name_def = $id);
    }
        
    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name_def );

    $node = $nodes->{ $id };

    wantarray ? return %{ $node } : return $node;
}

sub get_nodes
{
    # Niels Larsen, May 2003.

    # Returns a set of nodes from a given list of node ids and a given 
    # table. The fields returned depend on the select argument; default 
    # is "id,parent_id,name,depth,nmin,nmax".

    my ( $dbh,      # Database handle
         $ids,      # ID list
         $tables,   # Table to fetch from 
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;

    # Returns a hash.

    if ( not $tables ) {
        &error( qq (The name of an existing table must be given) );
    }

    if ( not $select ) {
        $select = $select_def;
    }

    my ( $idstr, $sql, $nodes );

    $idstr = join ",", @{ $ids };
    
    if ( $where ) {
        $sql = qq (select sql_cache $select from $tables where $id_name_def in ( $idstr ) and $where);
    } else {
        $sql = qq (select sql_cache $select from $tables where $id_name_def in ( $idstr ));
    }
    
    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name_def );

    wantarray ? return %{ $nodes } : return $nodes;
}

sub get_parents
{
    # Niels Larsen, May 2003.

    # Fetches all parent nodes in a given table starting at a given 
    # node or node id, but not including it. The fields returned 
    # depend on the select argument; default is 
    # "id,parent_id,name,depth,nmin,nmax".

    my ( $dbh,      # Database handle
         $node,     # Starting node or node id
         $tables,   # Table(s) to fetch from 
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 
    
    if ( not $tables ) {
        &error( qq (The name of an existing table must be given) );
    }

    if ( not $select ) {
        $select = $select_def;
    }

    my ( $p_id, $sql, $p_nodes );

    if ( not ref $node )
    {
        if ( $where ) {
            $sql = qq (select sql_cache $select from $tables where $id_name_def = $node and $where);
        } else {
            $sql = qq (select sql_cache $select from $tables where $id_name_def = $node);
        }
            
        $node = &Common::DB::query_hash( $dbh, $sql, $id_name_def )->{ $node };
    }

    $p_id = $node->{"parent_id"};

    # We use a loop that runs multiple queries each of which gets the 
    # immediate parent. This is much faster than doing it in one go by 
    # asking for the nodes with smaller nmin and larger nmax.

    while ( $p_id > 0 )
    {
        $sql = qq (select sql_cache $select from $tables where $id_name_def = $p_id and name_type = 'scientific name');

        if ( $where ) {
            $sql .= qq (and $where);
        }            

        $p_nodes->{ $p_id } = &Common::DB::query_hash( $dbh, $sql, $id_name_def )->{ $p_id };

        $p_id = $p_nodes->{ $p_id }->{"parent_id"};
    }
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_nodes_parents
{
    # Niels Larsen, May 2003.

    # From a given set of nodes, finds the set of parent nodes that together
    # with the nodes makes up the minimal subtree that includes the given 
    # nodes. In other words the routine finds the nodes that when merged with
    # the given nodes comprise a complete tree starting at a single node. 

    my ( $dbh,     # Database handle
         $nodes,   # Nodes we want all parents of
         $tables,  # Table(s) to fetch from 
         $select,  # Output fields - OPTIONAL
         $where,   # Where expression - OPTIONAL
         ) = @_;
    
    # Returns a nodes hash.

    if ( not $tables ) {
        &error( qq (The name of an existing table must be given) );
    }

    if ( not $select ) {
        $select = $select_def;
    }

    my ( $id, $node, $nmin, $nmax, $sql1, $sql2, $sql, $p_nodes, $depth, 
         $p_node, $p_id, $root_nodes );

    $id = ( keys %{ $nodes } )[0];    # Any random node as seed

    $nmin = $nodes->{ $id }->{"nmin"};
    $nmax = $nodes->{ $id }->{"nmax"};

    foreach $node ( values %{ $nodes } )
    {
        $nmin = $node->{"nmin"} if $nmin > $node->{"nmin"};
        $nmax = $node->{"nmax"} if $nmax < $node->{"nmax"};
    }

    $sql1 = qq (select sql_cache $select from $tables where);

    if ( $where ) {
        $sql2 = qq (and $where);
    } else {
        $sql2 = "";
    }

    foreach $id ( keys %{ $nodes } )
    {
        $node = $nodes->{ $id };
        $p_id = $node->{"parent_id"};
        
        while ( $p_id and 
                not exists $p_nodes->{ $p_id } and 
                not exists $nodes->{ $p_id } )
#                and ( $node->{"nmin"} > $nmin or $node->{"nmax"} < $nmax ) )
        {
            $sql = qq ($sql1 $id_name_def = $p_id $sql2);
            
            $p_node = &Common::DB::query_hash( $dbh, $sql, $id_name_def )->{ $p_id };
            
            $p_nodes->{ $p_id } = &Storable::dclone ( $p_node );
            $p_id = $p_node->{"parent_id"};
            
            $node = $p_node;
        }
    }

    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_subtree
{
    # Niels Larsen, May 2003.

    # For a given node or node id, fetches all nodes that make up the 
    # subtree that starts at the node, the given node included.

    my ( $dbh,      # Database handle
         $node,     # Starting node or node id
         $tables,   # Table(s) to fetch from 
         $select,   # Field string - OPTIONAL
         $where,    # Where expression - OPTIONAL
         $levels,   # The number of levels to include - OPTIONAL, default all
         ) = @_;

    # Returns a nodes hash. 
    
    if ( not $tables ) {
        &error( qq (The name of an existing table must be given) );
    }

    if ( $select and $select !~ /depth/ ) {
        $select .= ",depth";
    } elsif ( not $select ) {
        $select = $select_def;
    }

    my ( $nmin, $nmax, $sql, $nodes, $depth );

    if ( not ref $node )
    {
        $sql = qq (select $select from $tables where $id_name_def = $node);
        $node = &Common::DB::query_hash( $dbh, $sql, $id_name_def )->{ $node };
    }

    $nmin = $node->{"nmin"};
    $nmax = $node->{"nmax"};
    $depth = $node->{"depth"};

    $sql = qq (select $select from $tables where nmin between $nmin and $nmax);

    if ( defined $where ) {
        $sql .= qq ( and $where);
    }

    if ( defined $levels ) {
        $sql .= qq ( and depth <= ) . ( $depth + $levels );
    }        
    
    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name_def );

    return wantarray ? %{ $nodes } : $nodes;
}

sub close_node
{
    # Niels Larsen, May 2003.

    # Deletes in memory the subtree originating at a given node by
    # simply invoking Taxonomy::Nodes::delete_subtree.

    my ( $nodes,    # Nodes hash
         $id,       # Node ID
         ) = @_;

    # Returns nothing, but modifies the nodes structure. 

    $nodes = &Taxonomy::Nodes::delete_subtree( $nodes, $id );
    
    return wantarray ? %{ $nodes } : $nodes;
}

sub focus_node
{
    # Niels Larsen, May 2003.
    
    # Creates a hierarchy starting at a given node. It is like open_node
    # except it keeps expanding the hierarchy until there are 10 or more
    # nodes in it, it possible. This is essentially a "zoom" function. 

    my ( $dbh,      # Database handle
         $node,     # Starting node or node id 
         $depth,    # How deep down into the tree to open
         $tables,   # Table(s) to fetch from 
         $select,   # Output fields - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;

    my ( $root_id, $nodes, $node_id, $count, $count_2 );
    
    if ( ref $node ) {
        $root_id = &Taxonomy::Nodes::get_id( $node );
    } else { 
        $root_id = $node;
    }

    $nodes = &Taxonomy::DB_nodes::open_node( $dbh, $root_id, $depth,
                                        {}, $tables, $select, $where );

    $count = scalar keys %{ $nodes };

    if ( $count < 8 )
    {
        foreach $node_id ( keys %{ $nodes } )
        {
            $node = $nodes->{ $node_id };
            $depth = $node->{"depth"} if $depth < $node->{"depth"};
        }

        $depth -= $nodes->{ $root_id }->{"depth"};
        $count_2 = $count + 1;

        while ( $count_2 < 8 and $count < $count_2 )
        {
            $count = $count_2;
            
            $depth++;
            $nodes = &Taxonomy::DB_nodes::open_node( $dbh, $root_id, $depth,
                                                {}, $tables, $select, $where );
            
            $count_2 = scalar keys %{ $nodes };
        }
    }

    return $nodes;
}

sub match_ids
{
    # Niels Larsen, January 2005.

    # Given a search string of ids, returns a list of ids that are
    # within the subtree given by a root id. 

    my ( $dbh,      # Database handle
         $text,     # Search text
         $root_id,  # Starting id for search
         ) = @_;

    # Returns a hash.

    my ( $tables, $select, $root_node, $nmin, $nmax, $sql, 
         @match_ids, @ids, $idstr );

    $tables = "tax_nodes";
    $select = "tax_nodes.tax_id,parent_id,depth,name,name_type,nmin,nmax";

    $root_node = &Taxonomy::DB_nodes::get_node( $dbh, $root_id, $tables, $select );

    $nmin = $root_node->{"nmin"}; 
    $nmax = $root_node->{"nmax"}; 
    
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;

    $sql = qq (select distinct tax_id from $tables where nmin between $nmin and $nmax);

    @ids = split /[\s,;]+/, $text;
    $idstr = join ",", grep { $_ =~ /^\d+$/ } @ids;
    
    if ( $idstr ) 
    {
        $sql .= qq ( and tax_id in ( $idstr ));
        @match_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    }

    if ( @match_ids ) {
        return wantarray ? @match_ids : \@match_ids;
    } else {
        return;
    }
}

sub match_text
{
    # Niels Larsen, August 2003.

    # Searches the name fields of a given part of the hierarchy with a 
    # given text. Different "targets" can be specified: "scientific_names",
    # "common_names", "synonyms" or "ids". Searches can be of different 
    # "types": "whole_words", "name_beginnings" or "partial_words". The
    # final argument limits the search to the hiearchy that starts at that
    # id. The results are returned as a list of node ids of nodes that 
    # match; they can then be combined with other kinds of queries. 
    # Nothing is returned if there are no matches. 

    my ( $dbh,      # Database handle
         $text,     # Search text
         $target,   # Search target
         $type,     # Search type
         $root_id,  # Starting id for search
         ) = @_;

    # Returns a hash.

    my ( $root_node, $nodes, $node, $nmin, $nmax, $sql, 
         @match_ids, $idstr, $sql_add, $match, $hit, $tables, $select );

    $tables = "tax_nodes";
    $select = "tax_nodes.tax_id,parent_id,depth,name,name_type,nmin,nmax";

    $root_node = &Taxonomy::DB_nodes::get_node( $dbh, $root_id, $tables, $select );

    $nmin = $root_node->{"nmin"}; 
    $nmax = $root_node->{"nmax"}; 
    
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;

    $sql = qq (select distinct tax_id from $tables where nmin between $nmin and $nmax);

    if ( $target eq "scientific_names" )
    {
        $sql_add = qq (name_type = 'scientific name');
    }
    elsif ( $target eq "common_names" )
    {
        $sql_add = qq ((name_type = 'common name' or name_type = "genbank common name"));
    }
    elsif ( $target eq "synonyms" )
    {
        $sql_add = qq ((name_type = 'synonym' or name_type = "genbank synonym" or name_type = "equivalent name"));
    }
    else {
        $sql_add = "";
    }
    
    if ( $sql_add ) {
        $sql .= qq ( and $sql_add);
    }
    
    $text = quotemeta $text;
    
    if ( $type eq "whole_words" ) {
        $sql .= qq ( and match(name) against ('$text'));
    } elsif ( $type eq "name_beginnings" ) {
        $sql .= qq ( and name like '$text%');
    } elsif ( $type eq "partial_words" ) {
        $sql .= qq ( and name like '%$text%');
    } else {
        &error( qq (Unknown search type -> "$type") );
        exit;
    }
    
    @match_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    if ( @match_ids )
    {
        return wantarray ? @match_ids : \@match_ids;
    }
    else {
        return;
    }
}

sub query
{
    # Niels Larsen, May 2003.

    # Runs a query on a sub-hierarchy given by its topmost node ID and
    # returns the set of nodes that match. The result is just a set of
    # nodes somewhere within the given sub-hierarchy, they are not 
    # connected into a tree that spans exactly the result set. 

    my ( $dbh,      # Database handle
         $node,     # Starting node
         $depth,    # Depth cutoff 
         $tables,   # Table(s) to query
         $select,   # Output fields
         $where,    # Query expression - OPTIONAL
         ) = @_;
    
    # Returns a hash.
    
    my ( $sql, $hash, @ids, $ids, $id, $nmin, $nmax, $nodes );

#    if ( not ref $node )
#    {
#        $sql = qq (select distinct sql_cache $select from $tables where $id_name_def = $node);
#        $node = &Common::DB::query_hash( $dbh, $sql, "id" )->{ $node };
#    }

    $sql = qq (select sql_cache $select from $tables where);

    if ( defined $depth )
    {
        $depth += $node->{"depth"}; 
        $sql .= qq ( depth <= $depth and);
    }
    
    $nmin = $node->{"nmin"}; 
    $nmax = $node->{"nmax"}; 
    
    $sql .= qq ( nmin between $nmin and $nmax);
    
    if ( $where ) {
        $sql .= qq ( and $where );
    }
    
    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name_def );
    
    if ( $nodes and %{ $nodes } ) {
        return wantarray ? %{ $nodes } : $nodes;
    } else {
        return wantarray ? () : {};
    }            
}

1;

__END__

sub open_node
{
    # Niels Larsen, May 2003.

    # Replaces the subtree starting at a given node with the minimal
    # subtree that exactly spans the result of a database query. So
    # depending on what queries come in it will work as a "collapse"
    # or "search" function too. 

    my ( $dbh,      # Database handle
         $node,     # Starting node or node id 
         $depth,    # How deep down into the tree to search
         $nodes,    # Nodes hash
         $tables,   # Table(s) to fetch from 
         $select,   # Output fields - OPTIONAL
         $where,    # Where expression - OPTIONAL
         ) = @_;

    # Returns nothing, but modifies the nodes structure.
    
    my ( $open_nodes, $open_parents, $root_id, $id, $sql, $count, $last_count );

    if ( ref $node ) {
        $root_id = &Taxonomy::Nodes::get_id( $node );
    } else { 
        $root_id = $node;
        $node = &Taxonomy::DB_nodes::get_node( $dbh, $node, $tables, $select, $where );
    }

    $open_nodes = &Taxonomy::DB_nodes::query( $dbh,
                                         $node,
                                         $depth,
                                         $tables,
                                         $select,
                                         $where );

    $count = scalar keys %{ $open_nodes };

    # It is tedious to click 5 levels down just to find a single leaf.
    # So if there is only one child node we open the nodes further until
    # either 1) more than one children appear or 2) we reach a leaf. 
    
    if ( $count <= 2 )
    {
         $last_count = $count;
        
         while ( $count <= $last_count + 1 and 
                 not grep { $_->{"nmin"} == $_->{"nmax"} - 1 } values %{ $open_nodes } )
         {
             $open_nodes = &Taxonomy::DB_nodes::query( $dbh,
                                                 $node,
                                                 $depth,
                                                 $tables,
                                                 $select,
                                                 $where );
            
             $last_count = $count;
             $count = scalar keys %{ $open_nodes };
            
             $depth++;
         }
    }
    
    # Set children ids,

    $open_nodes = &Taxonomy::Nodes::set_ids_children_all( $open_nodes, 0 );

    # Finally delete old subtree and add the new one,

    if ( $nodes and %{ $nodes } ) {
        &Taxonomy::Nodes::delete_subtree( $nodes, $root_id );
    }

    $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $open_nodes, 1 );

    return wantarray ? %{ $nodes } : $nodes;
}
