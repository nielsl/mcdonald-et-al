package Taxonomy::DB;        #  -*- perl -*-

# Functions that reach into a database to get or put a taxonomy 
# set of nodes.

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &build_taxonomy
                 &database_exists
                 &delete_entries
                 &expand_go_node
                 &expand_rna_node
                 &expand_tax_node
                 &get_entry
                 &get_go_stats
                 &get_id_of_name
                 &get_ids_all
                 &get_ids_subtree
                 &get_name_of_id
                 &get_names
                 &get_node
                 &get_nodes
                 &get_nodes_parents
                 &get_numeric_id
                 &get_parents
                 &get_rna_stats
                 &get_subtree
                 &get_stats
                 &get_tax_stats_user
                 &ids_from_name
                 &open_node
                 );

use Common::Config;
use Common::Messages;

use Common::DB;

use Taxonomy::DB_nodes;
use Taxonomy::Schema;

our $id_name_def = "tax_id";
our $select_def = "tax_id,parent_id,name,depth,nmin,nmax";
our $tables_def = "tax_nodes";
#our $sql_no_cache = "sql_no_cache";
 our $sql_no_cache = "";

our ( $t0, $t1, $time );

# >>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub build_taxonomy
{
    # Niels Larsen, August 2003.

    # Builds a nodes hash from a set of IDs, by querying the database.
    # Children IDs (if any) are added to each node. 

    # TODO - this works only for ncbi but should work for any

    my ( $dbh,     # Database handle
         $select,  # List of output fields - OPTIONAL
         ) = @_;

    # Returns a nodes hash.

    my ( $tables, $where, $nodes );

    if ( not $select ) {
        $select = "tax_id,parent_id,nmin,nmax";
    }
    
    $tables = $tables_def;
    $where = qq (name_type = "scientific name");
    
    $nodes = &Taxonomy::DB_nodes::get_subtree( $dbh, 1, $tables, $select, $where );
    
    &Taxonomy::Nodes::set_ids_children_all( $nodes );
    
    wantarray ? return %{ $nodes } : return $nodes;
}

sub database_exists
{
    # Niels Larsen, August 2005.

    # Returns true if all taxonomy related tables exist, otherwise
    # false. 

    my ( $dbh,       # Database handle
         ) = @_;

    # Returns 1 or nothing. 

    my ( $table );

    foreach $table ( Taxonomy::Schema->get->table_names )
    {
        if ( not &Common::DB::table_exists( $dbh, $table ) )
        {
            return;
        }
    }

    return 1;
}

sub delete_entries
{
    # Niels Larsen, October 2006.
    
    # Deletes a set of entries from the database, given by their data source
    # name (e.g. "NCBI"). 

    my ( $dbh,        # Database handle
         $source,     # Data source
         ) = @_;

    # Returns an integer.

    my ( $schema, $sql, $table, $count );

    if ( not defined $source ) {
        &error( qq (Data source is not defined) );
        exit;
    }

    $schema = Taxonomy::Schema->get;
    $count = 0;

    foreach $table ( $schema->table_names )
    {
        if ( &Common::DB::table_exists( $dbh, $table ) )
        {
            $sql = qq (delete from $table where inputdb = '$source');
            
            $count += &Common::DB::request( $dbh, $sql );
        }
    }
    
    return $count;
}

sub expand_go_node
{
    # Niels Larsen, October 2003.

    # Replaces the subtree starting at a given node with the minimal
    # subtree that spans the nodes that have a certain organism 
    # related attribute set.
    
    my ( $dbh,       # Database handle
         $ids,       # Selected GO id list
         $root_id,   # Starting node id 
         ) = @_;

    # Returns an updated nodes hash.

    my ( $go_ids, $go_id, $node_id, $all_nodes, $nodes, $stats, 
         $all_ids, $id );

    require GO::DB;

    $go_ids = [];
    
    foreach $go_id ( @{ $ids } ) 
    {
        push @{ $go_ids }, &GO::DB::get_ids_subtree( $dbh, $go_id );
        push @{ $go_ids }, $go_id;
    }
    
    $go_ids = &Common::Util::uniqify( $go_ids );

    $stats = &Taxonomy::DB::get_go_stats( $dbh, $go_ids, $root_id );

    $all_ids = &Taxonomy::Nodes::get_ids_all( $stats );
    $all_nodes = &Taxonomy::DB::get_nodes( $dbh, $all_ids );

    foreach $node_id ( @{ $all_ids } )
    {
        $nodes->{ $node_id } = $all_nodes->{ $node_id };
    }

    return wantarray ? %{ $nodes } : $nodes;
}

sub expand_tax_node
{
    # Niels Larsen, March 2004.

    # Returns all nodes in the subtree starting at a given node with
    # counts added for the statistics key given. 
    
    my ( $dbh,       # Database handle
         $inputdb,
         $datatype,
         $root_id,   # Starting node or node id 
         ) = @_;

    # Returns an updated nodes hash. 

    my ( $all_nodes, $all_ids, $stats, $nodes, $node_id );

    $all_nodes = &Taxonomy::DB::get_subtree( $dbh, $root_id, 99999 );
    $all_ids = &Taxonomy::Nodes::get_ids_all( $all_nodes );

    $stats = &Taxonomy::DB::get_stats( $dbh, $all_ids, $inputdb, $datatype );

    foreach $node_id ( &Taxonomy::Nodes::get_ids_all( $stats ) )
    {
        $nodes->{ $node_id } = $all_nodes->{ $node_id };
    }

    if ( $nodes ) {
        return wantarray ? %{ $nodes } : $nodes;
    } else {
        return;
    }
}

sub get_entry
{
    # Niels Larsen, January 2005.

    # Builds a hash structure with all the information about a given 
    # taxonomy id that the system supports. 
    
    my ( $dbh,      # Database handle
         $nid,      # Node id
         ) = @_;

    # Returns a hash.

    my ( $entry, $node, $nodes, $p_nodes, $p_node, $select, $where, 
         $ids, $id, $p_id, $stats, $orig_node );

    if ( not defined $nid ) {
        &error( qq (Input entry ID is undefined) );
    }

    $select = "*";
    $where = "name_type = 'scientific name'";

    $node = &Taxonomy::DB_nodes::get_node( $dbh, $nid, $tables_def, $select, $where );
    $orig_node = &Taxonomy::Nodes::copy_node( $node );

    # ------ Set classification,

    push @{ $entry->{"classification"} }, [ "Taxonomy ID", $nid ];

    if ( $node->{"rank"} and $node->{"rank"} !~ /^\s*no rank\s*$/i ) {
        push @{ $entry->{"classification"} }, [ "Rank", $node->{"rank"} ];
    } else {
        push @{ $entry->{"classification"} }, [ "Rank", "" ];
    }

    push @{ $entry->{"classification"} }, [ "Division name", $node->{"div_name"} ];
    push @{ $entry->{"classification"} }, [ "Division code", $node->{"div_code"} ];
    push @{ $entry->{"classification"} }, [ "EMBL code", $node->{"embl_code"} ];

    # ------ Set names,
    
    $entry->{"names"} = &Taxonomy::DB::get_names( $dbh, $nid );
    $entry->{"name"} = $entry->{"names"}->[0]->[1];  # Scientific name

    # ------ Set genetic codes,

    push @{ $entry->{"genetic"} }, [ "Genetic code", $node->{"gc_id"} ];

    if ( $node->{"mgc_id"} ) {
        push @{ $entry->{"genetic"} }, [ "Mito. genetic code", $node->{"mgc_id"} ];
    }

    # Add DNA stuff here

    # ------ Set parents,

    $p_nodes = &Taxonomy::DB::get_parents( $dbh, $nid );
    $p_id = $node->{"parent_id"};

    while ( $p_nodes->{ $p_id } )
    {
        push @{ $entry->{"parents"} }, [ $p_id, $node->{"name"} ];

        $node = &Taxonomy::DB_nodes::get_node( $dbh, $p_id, $tables_def, $select, $where );
        $p_id = $node->{"parent_id"};
    }
    
    # ------ Set children,

    $nodes = &Taxonomy::DB::get_subtree( $dbh, $nid, 1 );
    delete $nodes->{ $nid };

    $entry->{"children"} = [];

    foreach $node ( values %{ $nodes } )
    {
        push @{ $entry->{"children"} }, [ $node->{"tax_id"}, $node->{"name"} ];
    }

    # ------ Set organism count,

    if ( &Taxonomy::Nodes::is_leaf( $orig_node ) )
    {
        $entry->{"organisms"} = 0;
    } 
    else
    {
        $stats = &Taxonomy::DB::get_stats( $dbh, [ $nid ], "orgs_taxa_ncbi", "orgs_taxa" );
        $entry->{"organisms"} = $stats->{ $nid }->{"sum_count"};
    }

    return $entry;
}

sub get_go_stats
{
    # Niels Larsen, March 2004.

    # Creates a very minimal taxonomy tree: only the "count" and sum_count
    # keys are set and only nodes are included that connect to a given set
    # of GO ids. An optional starting node may be given; this makes the 
    # routine much faster if the given node is small, but slower if it is 
    # among the top-most in the taxonomy tree. 

    my ( $dbh,         # Database handle
         $go_ids,      # GO id list - OPTIONAL, default all
         $root_id,     # Starting node id - OPTIONAL
         ) = @_;

    # Returns a nodes hash.

    my ( $nodes, $p_nodes, $subref, $argref, $root_node, $array,
         $select, $id, $sql, $go_str, $tax_ids, $tax_str, $p_idstr, $go_p_str,
         %ids, @ids, @p_ids, @tax_ids, %go_ids );

    $go_str = join ",", @{ $go_ids };

    if ( $root_id )
    {
        # After trying many things the way below seems to work best: 
        # create a temporary file with the smallest set of ids, then
        # do a natural join between that and the go_genes_tax table. 
        # This table can be reduced 3 times in size which will help.

        @tax_ids = &Taxonomy::DB::get_ids_subtree( $dbh, $root_id );

        $tax_str = join ",", @tax_ids;
        $go_str = join ",", @{ $go_ids };

        if ( scalar @{ $go_ids } < scalar @tax_ids )
        {
            $sql = qq (create temporary table go_temp (go_id int not null, index go_id_ndx (go_id)))
                 . qq ( select distinct go_id from go_edges where go_id in ( $go_str ));

            &Common::DB::request( $dbh, $sql );

            $sql = qq (select distinct tax_id from go_genes_tax natural join go_temp)
                 . qq ( where tax_id in ( $tax_str ));

            $tax_ids = [ map { $_->[0] } &Common::DB::query_array( $dbh, $sql ) ];

            $sql = qq (drop table go_temp);
            &Common::DB::request( $dbh, $sql );
        }
        else
        {
            $sql = qq (create temporary table tax_temp (tax_id int not null, index tax_id_ndx (tax_id)))
                 . qq ( select tax_id from tax_nodes where tax_id in ( $tax_str ));

            &Common::DB::request( $dbh, $sql );

            $sql = qq (select distinct tax_temp.tax_id from tax_temp natural join go_genes_tax where go_id in ( $go_str ));
            $tax_ids = [ map { $_->[0] } &Common::DB::query_array( $dbh, $sql ) ];

            $sql = qq (drop table tax_temp);
            &Common::DB::request( $dbh, $sql );
        }            
    }
    else
    {
        &error( qq (No root id is given) );
        exit;
    }        

    if ( @{ $tax_ids } )
    {
        $nodes = &Taxonomy::DB::get_nodes( $dbh, $tax_ids, "tax_id,parent_id,nmin,nmax" );

        $p_nodes = &Taxonomy::DB::get_nodes_parents( $dbh, $nodes, "tax_id,parent_id,nmin,nmax" );

        $nodes = &Taxonomy::Nodes::merge_nodes( $nodes, $p_nodes );

        $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes, 0 );

        &Taxonomy::Nodes::delete_label_tree( $nodes, "nmin" );
        &Taxonomy::Nodes::delete_label_tree( $nodes, "nmax" );

        # Set leaf counts,
        
        foreach $id ( @{ $tax_ids } )
        {
            $nodes->{ $id }->{"count"} = 1;
        }

        # Sum up counts,

        $subref = sub
        {
            my ( $nodes, $nid ) = @_;
            my ( $p_id, $count, $sum_count );

            if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
            {
                $count = $nodes->{ $nid }->{"count"} || 0;
                $nodes->{ $nid }->{"sum_count"} += $count;
                
                $sum_count = $nodes->{ $nid }->{"sum_count"} || 0;
                $nodes->{ $p_id }->{"sum_count"} += $sum_count;
            }
        };

        $argref = [];
        
        &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );        

        return wantarray ? %{ $nodes } : $nodes;
    }
    else {
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

    return &Taxonomy::DB_nodes::get_id_of_name( $dbh, $name, $tables_def );
}

sub get_ids_all
{
    # Niels Larsen, February 2005.

    # Simply retrieves all taxonomy ids as a list.

    my ( $dbh,
         ) = @_;

    # Returns a list.

    my ( $sql, $ids );
    
    $sql = qq (select distinct tax_id from tax_nodes);

    $ids = [ map { $_->[0] } &Common::DB::query_array( $dbh, $sql ) ];
    
    return wantarray ? @{ $ids } : $ids;
}

sub get_ids_subtree
{
    # Niels Larsen, February 2004.

    # Returns a list of ids in a subtree given by its top node
    # or node id. 

    my ( $dbh,     # Database handle
         $node,    # Starting node or node id
         ) = @_;

    # Returns an array.

    my ( $nmin, $nmax, $sql, $ids );

    if ( not ref $node ) {
        $node = &Taxonomy::DB::get_node( $dbh, $node );
    }

    $nmin = $node->{"nmin"};
    $nmax = $node->{"nmax"};

    $sql = qq (select distinct tax_id from tax_nodes where nmin between $nmin and $nmax);
    
    $ids = [ map { $_->[0] } &Common::DB::query_array( $dbh, $sql ) ];
    
    return wantarray ? @{ $ids } : $ids;
}

sub get_name_of_id
{
    # Niels Larsen, October 2003.

    # Returns a node name given a node id. 

    my ( $dbh,       # Database handle
         $id,        # Node id
         ) = @_;

    # Returns an integer. 

    return &Taxonomy::DB_nodes::get_name_of_id( $dbh, $id, $tables_def );
}

sub get_names
{
    # Niels Larsen, January 2005.

    # Returns a list of [ name type, name ] for a given node id.

    my ( $dbh,      # Database handle
         $nid,      # Node id
         ) = @_;

    # Returns a list.

    my ( $sql, $list, $elem, @names );

    $sql = "select name_type, name from tax_nodes where tax_id = $nid";
    $list = &Common::DB::query_array( $dbh, $sql );

    foreach $elem ( @{ $list } )
    {
        if ( $elem->[0] eq "scientific name" ) {
            unshift @names, [ $elem->[0], $elem->[1] ];
        } else {
            push @names, [ $elem->[0], $elem->[1] ];
        }
    }

    return wantarray ? @names : \@names;
}
    
sub get_node
{
    # Niels Larsen, August 2003.

    # Returns a single taxonomy node with a given id.

    my ( $dbh,       # Database handle
         $id,        # ID
         $select,    # List of field names - OPTIONAL 
         $where,     # Where expression - OPTIONAL         
         ) = @_;

    # Returns a nodes hash.

    my ( $node );

    $select = $select_def if not $select;
    $where = qq (name_type = 'scientific name') if not defined $where;

    $node = &Taxonomy::DB_nodes::get_node( $dbh, $id, $tables_def, $select, $where );

    return wantarray ? %{ $node } : $node;
}

sub get_nodes
{
    # Niels Larsen, August 2003.

    # Builds taxonomy nodes from a given set of ID's. 

    my ( $dbh,        # Database handle
         $ids,        # List of ids
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes );

    $select = $select_def if not $select;

    $nodes = &Taxonomy::DB_nodes::get_nodes( $dbh, $ids, $tables_def, $select, "name_type = 'scientific name'" );
    
    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_all
{
    # Niels Larsen, February 2005.

    # Builds all taxonomy nodes.

    my ( $dbh,        # Database handle
         $select,     # List of field names - OPTIONAL
         ) = @_;

    # Returns a hash of hashes.

    my ( $nodes, $sql );

    $select = $select_def if not $select;

    $sql = qq (select $select from $tables_def);

    $nodes = &Common::DB::query_hash( $dbh, $sql, $id_name_def );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_nodes_parents
{
    # Niels Larsen, February 2004.

    # Fetches all parent nodes of one or more given nodes. 

    my ( $dbh,       # Database handle
         $nodes,     # Starting nodes or ids 
         $select,    # List of field names - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 

    my ( $p_nodes, $tables, $where );

    $tables = $tables_def;
    $select = $select_def if not $select;
    $where = "name_type = 'scientific name'";

    $p_nodes = &Taxonomy::DB_nodes::get_nodes_parents( $dbh, $nodes, $tables, $select, $where );
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_numeric_id
{
    # Niels Larsen, November 2005.

    # Translates a readable string id to an integer, and registers
    # the correspondence in a given database table if that has not
    # been done already. 

    my ( $dbh,
         $table,
         $title,
         ) = @_;

    # Returns an integer. 

    my ( $schema, $sql, @matches, $max_id, $id, $tableO );

    if ( not &Common::DB::table_exists( $dbh, $table ) )
    {
        $tableO = Taxonomy::Schema->get->table( $table );
        &Common::DB::create_table( $dbh, $tableO );
    }        

    $sql = qq (select * from $table where title = '$title');

    @matches = &Common::DB::query_array( $dbh, $sql );

    if ( scalar @matches == 1 )
    {
        $id = $matches[0]->[0];
    }
    elsif ( scalar @matches == 0 )
    {
        $sql = qq (select max(id) from $table);
        $max_id = &Common::DB::query_array( $dbh, $sql )->[0]->[0] || 0;

        &Common::DB::add_row( $dbh, $table, [ $max_id + 1, "'$title'" ] );

        $id = $max_id + 1;
    }
    else {
        &error( qq (More than one row in $table with title -> "$title") );
    }

    return $id;
}

sub get_parents
{
    # Niels Larsen, May 2003.

    # Fetches all parent nodes of a given node. 

    my ( $dbh,      # Database handle
         $node,     # Starting node or id 
         $select,   # List of field names - OPTIONAL
         ) = @_;

    # Returns a nodes hash. 
    
    my ( $p_nodes, $query );

    $select = $select_def if not $select;

    $p_nodes = &Taxonomy::DB_nodes::get_parents( $dbh, $node, 
                                                 $tables_def, $select,
                                                 "name_type = 'scientific name'" );
    
    return wantarray ? %{ $p_nodes } : $p_nodes;
}

sub get_rna_stats
{
    # Niels Larsen, February 2005.

    # Creates a very minimal taxonomy tree: only the "count" and "sum_count"
    # keys are set and only nodes are included where the statistics count 
    # of a given type is greater then zero. 
    
    my ( $dbh,           # Database handle
         $ids,           # Taxonomy node ids
         $key,           # RNA column key
         ) = @_;

    # Returns a nodes hash.

    my ( $sql, $idstr, $match, $tax_id, $rna_id, $stats, $length );

    $idstr = join ",", @{ $ids };

    if ( $key eq "rna_mols_tsum" )
    {
        $sql = qq (select distinct tax_id,rna_id from rna_organism where tax_id in ( $idstr ));
        
        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $tax_id, $rna_id ) = @{ $match };
            push @{ $stats->{ $tax_id }->{"values"} }, $rna_id;
        }        
    }
    elsif ( $key eq "rna_bases_tsum" )
    {
        $sql = qq (select tax_id,length from rna_organism natural join rna_molecule where tax_id in ( $idstr ));

        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $tax_id, $length ) = @{ $match };
            push @{ $stats->{ $tax_id }->{"values"} }, $length;
        }
    }
    else {
        &error( qq (Wrong looking key -> "$key") );
        exit;
    }

    return $stats;
}

sub get_subtree
{
    # Niels Larsen, May 2003.

    # For a given node id, fetches all nodes that make up the subtree
    # that starts at the node, the given node included. 

    my ( $dbh,      # Database handle
         $node,     # Node or id of starting node
         $depth,    # The number of levels to include - OPTIONAL, default 1
         $select,   # Output fields - OPTIONAL
         ) = @_;

    # Returns a node hash.

    if ( not ref $node ) {
        $node = &Taxonomy::DB::get_node( $dbh, $node );
    }

    $depth ||= 99999;   # zero makes no sense

    my ( $nodes, $tables, $where );

    $select = "tax_nodes.tax_id,parent_id,depth,name,nmin,nmax" if not defined $select;
    $tables = "tax_nodes";
    $where = "name_type = 'scientific name'";

    $nodes = &Taxonomy::DB_nodes::get_subtree( $dbh, $node, $tables, $select, $where, $depth );

    return wantarray ? %{ $nodes } : $nodes;
}

sub get_stats_ids
{
    # Niels Larsen, November 2005.

    # Creates a hash where taxonomy id's are key, and a list of other
    # database id are value. 
    
    my ( $dbh,           # Database handle
         $tax_ids,       # Taxonomy statistics ids
         $inputdb,
         $datatype,
         ) = @_;

    # Returns a nodes hash.

    my ( $idstr, $id, $table, $sql, $count, $sum_count, $match, $tax_id, $stats );

    $idstr = join ",", @{ $tax_ids };

    $id = $datatype ."_id";
    $table = $datatype ."_organism";

    $sql = qq (select tax_stats.tax_id,$id from tax_stats natural join $table where )
         . qq (tax_stats.tax_id in ( $idstr ) and inputdb = '$inputdb' and )
         . qq (datatype = '$datatype');

    foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
    {
        ( $tax_id, $id ) = @{ $match };
        
        push @{ $stats->{ $tax_id } }, $id;
    }

    if ( $stats ) {
        return wantarray ? %{ $stats } : $stats;
    } else {
        return;
    }
}

sub get_stats
{
    # Niels Larsen, November 2005.

    # Creates a very minimal taxonomy tree: only the "count" and "sum_count"
    # keys are set and only nodes are included where the statistics count 
    # of a given type is greater then zero. 
    
    my ( $dbh,           # Database handle
         $tax_ids,       # Taxonomy statistics ids
         $inputdb,      # Server database, e.g. "ncbi", "rRNA_18S_0" 
         $datatype,      # Data type, e.g. "organisms", "molecules", "residues"
         ) = @_;

    # Returns a nodes hash.

    my ( $sql, $match, $count, $sum_count, $stats, $tax_id, $idstr );

    $idstr = join ",", @{ $tax_ids };

    $sql = qq (select tax_id,value,sum from tax_stats where tax_id in ( $idstr ))
         . qq ( and inputdb = '$inputdb' and datatype = '$datatype');

    foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
    {
        ( $tax_id, $count, $sum_count, $idstr ) = @{ $match };
        
        $stats->{ $tax_id }->{"count"} = $count;
        $stats->{ $tax_id }->{"sum_count"} = $sum_count;

        if ( $idstr ) {
            $stats->{ $tax_id }->{"data_ids"} = [ eval "$idstr" ];
        }
    }
    
    if ( $stats ) {
        return wantarray ? %{ $stats } : $stats;
    } else {
        return;
    }
}

sub get_tax_stats_user
{
    # Niels Larsen, December 2005.

    # 
    my ( $dbh,
         $jobid,
         $taxids,
         ) = @_;

    my ( $sql, $stats, $idstr, $match, $tax_id, $maxpct );

    $idstr = join ",", @{ $taxids };

    $sql = qq (select tax_id, value from tax_stats where job_id = $jobid and tax_id in ( $idstr ));
    $stats = {};

    foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
    {
        ( $tax_id, $maxpct ) = @{ $match };
        
        $stats->{ $tax_id }->{"value"} = $maxpct;
    }        

    return wantarray ? %{ $stats } : $stats;
}    

sub ids_from_name
{
    # Niels Larsen, August 2003.

    # The routine makes a list of taxonomy ids that match a given
    # organism name string. The list usually has one element, but 
    # the match is by no means safe - it depends what you feed the
    # routine. 

    my ( $dbh,    # Database handle
         $name,   # Organism name string
         ) = @_;

    # Returns a list.

    $name =~ s/\W+$//;
    $name .= " ";

    my ( $sql, @name, $matches, $ids, $nodes, $beg_count, $length,
         $count, @matches, $word, $word1, $word2, @ids, %ids, @words,
         $match );

    # If empty,

    if ( $name !~ /\w/ ) {
        return wantarray ? () : [];
    }

    # >>>>>>>>>>>>>>>>>>>>>> EXACT MATCH <<<<<<<<<<<<<<<<<<<<<<<<<

    $name =~ s/\'/\\\'/g;
    $name =~ s/&apos;/\\\'/g;

    $sql = qq (select $id_name_def,rank,name from $tables_def where name = '$name');
    $matches = &Common::DB::query_array( $dbh, $sql );

    if ( scalar @{ $matches } == 1 )
    {
        $ids = [ $matches->[0]->[0] ];
        return wantarray ? @{ $ids } : $ids;
    }

    # >>>>>>>>>>>>>>>>>>>>>> GENUS MATCH <<<<<<<<<<<<<<<<<<<<<<<<<

    # Substitute metacharacters, 

    $name =~ s/\'//g;
#    $name =~ s/,//g;
    $name =~ s/[\\\=\-\[\]\(\)]/ /g;
    $name =~ s/^\s//;
    $name =~ s/\s$//;

    # Ignore 'sp' and leading 'And',

    @name = grep { $_ !~ /\.$/ } split /[ ,]/, $name;
    @name = grep { $_ !~ /^sp$/ } @name;

    if ( @name and $name[0] =~ /^and$/i ) {
        shift @name;
    }

    if ( not @name ) {
        return wantarray ? () : [];
    }

    $word1 = shift @name;    # Usually genus
    
    # Often garbage can be recognized by what it starts with,

    if ( $word1 =~ /^..?$/ or $word1 =~ /^\d+$/ or $word1 =~ /^[A-Z]+$/ ) {
        return wantarray ? () : [];
    }

    # If we get a species or variety with absolute match, use it. 
    # Examples would be "rat" or "swine" and so on.

    $sql = qq (select $id_name_def,rank,name from $tables_def where name = '$word1' )
         . qq (and ( rank like 'species%' or rank like '%species' or rank = 'tribe' or rank = 'varietas' ));

    $matches = &Common::DB::query_array( $dbh, $sql );

    # If that didnt work, relax the matching and get a longer list,

    if ( not @{ $matches } )
    {
        $sql = qq (select $id_name_def,rank,name from $tables_def where name like '$word1%');
        $matches = &Common::DB::query_array( $dbh, $sql );
    }

    # If that got a single match, use it. If none, give up,

    if ( @{ $matches } == 1 ) 
    {
        $ids = [ $matches->[0]->[0] ];
        return wantarray ? @{ $ids } : $ids;
    }
    elsif ( not @{ $matches } )
    {
        return wantarray ? () : [];
    }

    # Remove the matching substrings from the list of matching names,

#    foreach $match ( @{ $matches } )
#    {
#        @words = split " ", $match->[2];
#        shift @words;
#        $match->[2] = join " ", @words;
#    }

#    print Dumper( $matches );
    # >>>>>>>>>>>>>>>>>> SPECIES MATCH <<<<<<<<<<<<<<<<<<<<<<<<<

#    print Dumper( \@name );
#    print "$word1\n";

    # Use matches with genus followed by species if any,

    if ( $word2 = shift @name )
    {
        $word2 = quotemeta $word2;
        
        if ( @matches = grep { $_->[2] =~ /^$word1 +$word2\b/i } @{ $matches } )
        {
            $matches = dclone \@matches;

#            foreach $match ( @{ $matches } )
#            {
#                @words = split " ", $match->[2];
#                shift @words;
#                $match->[2] = join " ", @words;
#            }
        }
        elsif ( @matches = grep { $_->[2] =~ /$word2/i } @{ $matches } )
        {
            $matches = dclone \@matches;
        }
        else
        {
            $matches = [ grep { $_->[2] =~ /^$word1 *$/i } @{ $matches } ];
        }
    }
    elsif ( @matches = grep { $_->[2] =~ /^$word1 *$/i } @{ $matches } )
    {
        $matches = dclone \@matches;
    }
        
    if ( @{ $matches } == 1 ) 
    {
        $ids = [ $matches->[0]->[0] ];
        return wantarray ? @{ $ids } : $ids;
    }
    elsif ( not @{ $matches } )
    {
        return wantarray ? () : [];
    }

    if ( @name )
    {
        # If there are words left, see if we can reduce the number of 
        # matches by using them,
        
        $beg_count = scalar @{ $matches };
        $count = $beg_count;
        
        foreach $word ( @name )
        {
            $word = quotemeta $word;

            if ( $word =~ /^([A-Z]{3,})(\d{3,})$/ and
                 @matches = grep { $_->[2] =~ /\b$1\s+$2/ix } @{ $matches } 
                 and scalar @matches < $count )
            {
                $matches = dclone \@matches;
                $count = scalar @{ $matches };
            }
            elsif ( @matches = grep { $_->[2] =~ /\b$word/ix } @{ $matches } 
                    and scalar @matches < $count )
            {
                $matches = dclone \@matches;
                $count = scalar @{ $matches };
            }
        }
    }
    elsif ( $word2 )
    {
        # Otherwise use the names that matches just genus and
        # species, if any,
        
        @matches = grep { $_->[2] =~ /^$word1 +$word2 *$/i } @{ $matches };
        
        if ( @matches and scalar @matches < scalar @{ $matches } ) {
            $matches = dclone \@matches;
        }
    }

    # >>>>>>>>>>>>>>>>>> DESPERATION POINT <<<<<<<<<<<<<<<<<<<<<<<<

    # If multiple matches, keep the species or varieties if present,

    if ( scalar @{ $matches } > 1 )
    {
        if ( @matches = grep { $_->[1] =~ /species|varietas|tribe/i } @{ $matches } ) {
            $matches = dclone \@matches;
        }
    }

    # If the rest of the words above did not shorten the list, use
    # the shorter of the species-or-better alternatives,

#    print Dumper( \@name );
#    print Dumper( $matches );
#    if ( scalar @{ $matches } > 1 and $beg_count and $count and $beg_count == $count )
    if ( @{ $matches } > 1 )
    {
        @matches = sort { length $a->[2] <=> length $b->[2] } @{ $matches };
        $length = length $matches[0]->[2];

        @{ $matches } = grep { $length == length $_->[2] } @matches;
    }

    # >>>>>>>>>>>>>>>>> REMOVE DUPLICATE IDS <<<<<<<<<<<<<<<<<<<<<<<

    if ( scalar @{ $matches } > 1 )
    {
        $ids = [ map { $_->[0] } @{ $matches } ];
        $ids = { map { $_ => 1 } @{ $ids } };
        $ids = [ keys %{ $ids } ];
    }
    elsif ( scalar @{ $matches } == 1 )
    {
        $ids = [ map { $_->[0] } @{ $matches } ];
    }
    else
    {
        $ids = [];
    }

    return wantarray ? @{ $ids } : $ids;
}

sub open_node
{
    # Niels Larsen, October 2003.

    # Returns the nodes that comprise the subtree starting at a given 
    # node and down to a given depth. If a node has less than a given
    # number of children, the routine will keep expanding it until the
    # number is exceeded or until there are leaves only.

    my ( $dbh,      # Database handle
         $root_id,  # Starting node id 
         $depth,    # How many levels to open - OPTIONAL, default 1
         $min,      # Minimum number of nodes to show - OPTIONAL
         ) = @_;

    # Returns a nodes hash.

    my ( $max, $nodes, $node, $count, $id, $del_id );

    $depth ||= 1;   # zero makes no sense
    $min ||= 3;     # zero makes no sense

    $max = 30;

    $nodes = &Taxonomy::DB::get_subtree( $dbh, $root_id, $depth );

    if ( defined $min )
    {
        $count = scalar @{ &Taxonomy::Nodes::get_ids_all( $nodes ) };
        
        # It is tedious to click 5 levels down just to find a single leaf.
        # So if there is only one child node we open the nodes further until
        # either 1) more than one children appear or 2) we reach a leaf. 
        
        if ( $count <= $min )
        {
            while ( $count < $min and $depth < $min and
                    grep { $_->{"nmax"} > $_->{"nmin"} + 1 } values %{ $nodes } )
            {
                $nodes = &Taxonomy::DB::get_subtree( $dbh, $root_id, $depth );
                $count = scalar @{ &Taxonomy::Nodes::get_ids_all( $nodes ) };
                
                $depth++;
            }
        }
    }

    # Delete nodes that have "Environmental samples" as their parent unless
    # clicked on explicitly .. Genbank is stuffing lots of these unclassified
    # entries everywhere that make long lists that fill up the browser .. bah

    $count = scalar @{ &Taxonomy::Nodes::get_ids_all( $nodes ) };
    
    if ( $count > $max )
    {
        foreach $node ( grep { $_->{"name"} =~ /^Environmental samples/i } 
                        &Taxonomy::Nodes::get_nodes_all( $nodes ) )
        {
            $del_id = $node->{"tax_id"};
            next if $del_id == $root_id;

            foreach $id ( &Taxonomy::Nodes::get_ids_all( $nodes ) )
            {
                if ( $nodes->{ $id }->{"parent_id"} == $del_id )
                {
                    delete $nodes->{ $id };
                }
            }
        }
    }
    
    return wantarray ? %{ $nodes } : $nodes;
}


1;

__END__

sub get_stats
{
    # Niels Larsen, March 2004.

    # Creates a very minimal taxonomy tree: only the "count" and "sum_count"
    # keys are set and only nodes are included where the statistics count 
    # of a given type is greater then zero. 
    
    my ( $dbh,           # Database handle
         $tax_ids,       # Taxonomy statistics ids
         $inputdb,
         $objtype,           # Taxonomy statistics key
         ) = @_;

    # Returns a nodes hash.

    my ( $idstr, $tax_id, $sql, $count, $sum_count, $pub_count, $rna_id, $length,
         $pub_sum_count, $match, $type_node, $type_sum, $stats, $pct, $distrib );

    $idstr = join ",", @{ $tax_ids };






    if ( $objtype eq "tax_orgs_tsum" )
    {
        $sql = qq (select tax_id,sum from tax_stats where sum > 0 and tax_id in ( $idstr ));
        
        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $tax_id, $sum_count ) = @{ $match };

            $stats->{ $tax_id }->{"count"} = 1;                
            $stats->{ $tax_id }->{"sum_count"} = $sum_count;
        }        
    }
    elsif ( $objtype eq "rna_mols_tsum" )
    {
        $sql = qq (select distinct tax_id,rna_id from rna_organism where tax_id in ( $idstr ));
        
        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $tax_id, $rna_id ) = @{ $match };
            push @{ $stats->{ $tax_id }->{"values"} }, $rna_id;
        }        
    }
    elsif ( $type eq "rna_bases_tsum" )
    {
        $sql = qq (select tax_id,length from rna_organism natural join rna_molecule where tax_id in ( $idstr ));

        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $tax_id, $length ) = @{ $match };
            push @{ $stats->{ $tax_id }->{"values"} }, $length;
        }
    }
    elsif ( $type eq "dna_gc_distrib_tsum" )
    {
        $sql = qq (select tax_id,dna_gc_distrib_node,$type from tax_stats where tax_id in ( $idstr ));
        
        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $tax_id, $count, $sum_count ) = @{ $match };

            $stats->{ $tax_id }->{"count"} = $count || undef;
            $stats->{ $tax_id }->{"sum_count"} = $sum_count;
        }
    }
    elsif ( $type eq "gold_orgs_tsum" )
    {
        $sql = qq (select tax_id,gold_orgs_node,$type,gold_orgs_cpub_node,gold_orgs_cpub_tsum from tax_stats where tax_id in ( $idstr ));

        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            $tax_id = $match->[0];

            ( undef, 
              $stats->{ $tax_id }->{"count"},
              $stats->{ $tax_id }->{"sum_count"},
              $stats->{ $tax_id }->{"pub_count"},
              $stats->{ $tax_id }->{"pub_sum_count"} ) = @{ $match };
        }
    }
    else
    {
#        $type_sum = $type;
#        $type =~ s/_tsum|_usum|_node$//;
#        $type_node = $type ."_node";
        
        $sql = qq (select tax_id,value,sum from tax_stats where inputdb = '$inputdb' and sum > 0 and tax_id in ( $idstr ));
    
        foreach $match ( &Common::DB::query_array( $dbh, $sql ) )
        {
            ( $tax_id, $count, $sum_count ) = @{ $match };

            $stats->{ $tax_id }->{"count"} = $count || undef;
            $stats->{ $tax_id }->{"sum_count"} = $sum_count;
        }
    }

    if ( $stats ) {
        return wantarray ? %{ $stats } : $stats;
    } else {
        return;
    }
}


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

    $sql .= " from tax_stats";

    if ( defined $ids )
    {
        $sql .= " where tax_id in ( " . (join ",", @{ $ids }) . " )";
    }

    $nodes = &Common::DB::query_hash( $dbh, $sql, "tax_id" );

    return wantarray ? %{ $nodes } : $nodes;
}
    

sub get_ids_go
{
    # Niels Larsen, January 2004.

    # Returns a non-redundant list of taxonomy ids that connect 
    # directly to one or more given GO ids. The connection is made
    # by the gene association tables. 

    my ( $dbh,      # Database handle
         $ids,      # GO id or ids
         ) = @_;

    # Returns an array.

    my ( $idstr, $sql, @tax_ids );

    if ( ref $ids ) {
        $idstr = join ",", @{ $ids };
    } else {
        $idstr = $ids;
    }

    $sql = qq (select distinct tax_id from go_genes_tax where go_id in ( $idstr ));

    @tax_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };
    
    return wantarray ? @tax_ids : \@tax_ids;
}    




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

    foreach $id ( &GO::Nodes::get_ids_all( $p_nodes ) )
    {
        $sql = qq (select go_terms_tsum from go_stats where $id_name_def = $id);
        $terms = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        $p_node = $p_nodes->{ $id };
        push @matches, [ $id, $p_node->{"name"}, $terms ];
    }
    
    foreach $match ( sort { $a->[2] <=> $b->[2] } @matches )
    {
        push @{ $entry->{"parents"} }, {
            $id_name_def => $match->[0],
            "name" => $match->[1],
            "terms_total" => $match->[2],
        };
    }






sub expand_rna_node
{
    # Niels Larsen, February 2005.

    # Returns the subtree of nodes that have RNAs attached.
    
    my ( $dbh,       # Database handle
         $key,       # Taxonomy statistics key
         $root_id,   # Starting node or node id 
         ) = @_;

    # Returns an updated nodes hash. 

    my ( $all_nodes, $all_ids, $rna_ids, $stats, $nodes, $node_id );

    require RNA::DB;

    $all_ids = &Taxonomy::DB::get_ids_subtree( $dbh, $root_id );
    $stats = &Taxonomy::DB::get_rna_stats( $dbh, $all_ids, $key );

    $rna_ids = &Taxonomy::Nodes::get_ids_all( $stats );
    $nodes = &Taxonomy::DB::get_nodes( $dbh, $rna_ids );

    foreach $node_id ( @{ $rna_ids } )
    {
        $nodes->{ $node_id } = $nodes->{ $node_id };

#        if ( $stats->{ $node_id }->{"count"} ) 
    }

    if ( $nodes ) {
        return wantarray ? %{ $nodes } : $nodes;
    } else {
        return;
    }
}
