package Disease::Stats;     #  -*- perl -*-

# Function statistics functions. 

use strict;
use warnings;

use Storable;
use IO::File;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &update
                 &update_disease
                 &create_lock
                 &delete_lock
                 &is_locked
                  );

use Disease::DB;
use Disease::Schema;

use Common::DAG::DB;
use Common::DAG::Nodes;
use Common::Config;
use Common::Messages;
use Common::Tables;
use Common::File;
use Common::DB;


# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub update
{
    # Niels Larsen, October 2004.

    # Updates the disease statistics database table. The type of 
    # statistic is given as keys of a hash (the first argument).

    my ( $wants,       # Wanted statistics types
         $readonly,    # Readonly toggle
         ) = @_;

    # Returns nothing.

    my ( $key, $schema, $nodes, $dbh, $sql, $stats, $db_file, 
         $db_table, $id, $row, $i );

    $db_file = "$Common::Config::tmp_dir/Disease/stats.tab";
    $db_table = "do_stats";
    
    $dbh = &Common::DB::connect();

    $Disease::DB::db_prefix = "do";
    $Disease::DB::id_name = "do_id";
    $Disease::DB::def_table = "do_def";
    $Disease::DB::edges_table = "do_edges";
    $Disease::DB::synonyms_table = "do_synonyms";
    $Disease::DB::xrefs_table = "do_xrefs";
    $Disease::DB::stats_table = "do_stats";

    $Disease::Schema::db_prefix = "do";
    $Disease::Schema::id_name = "do_id";
    $Disease::Schema::def_table = "do_def";
    $Disease::Schema::edges_table = "do_edges";
    $Disease::Schema::synonyms_table = "do_synonyms";
    $Disease::Schema::xrefs_table = "do_xrefs";
    $Disease::Schema::stats_table = "do_stats";

    $Common::DAG::DB::id_name = "do_id";
    $Common::DAG::Nodes::id_name = "do_id";

    # --------- Set every option to 1 if "all" given,

    if ( $wants->{"all"} ) {
        $wants = { map { $_, 1 } keys %{ $wants } };
    }

    # --------- Fetch all disease nodes,

    &echo( qq (   Fetching all nodes ... ) );

    $nodes = &Disease::DB::get_nodes_all( $dbh );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    &echo_green( "done\n" );

    # --------- Recreate statistics hash if skeleton changed,

    if ( $wants->{"all"} or $wants->{"do"} )
    {
        $stats = [];
        
            foreach $id ( sort { $a <=> $b } keys %{ $nodes } )
        {
            push @{ $stats }, [ $id ];
        }
    }
    else
    {
        &echo( qq (   Fetching existing statistics ... ) );
        
        if ( &Common::DB::table_exists( $dbh, $db_table ) )
        {
            $sql = qq (select * from $db_table);
            $stats = &Common::DB::query_array( $dbh, $sql );
        }
        else {
            $stats = [];
        }
        
        if ( @{ $stats } ) {
            &echo_green( "done\n" );
        } else {
            &echo_green( "none\n" );
        }
    }

    # --------- Update skeleton statistics,

    if ( $wants->{"do"} )
    {
        &echo( qq (   Adding ontology node counts ... ) );

        $stats = &Disease::Stats::update_disease( $nodes, $stats, $readonly );

        &echo_green( "done\n" );
    }

    # --------- Save to file, load updated statistics, clean up,

    &echo( qq (   Loading statistics into database ... ) );
    
    &Common::File::create_dir_if_not_exists( "$Common::Config::tmp_dir/Disease" );
    &Common::File::delete_file_if_exists( $db_file );
    
    foreach $row ( @{ $stats } )
    {
        for ( $i = 0; $i < @{ $row }; $i++ ) {
            $row->[ $i ] = 0 if not defined $row->[ $i ];
        }
    }
    
    &Common::Tables::write_tab_table( $db_file, $stats );

    if ( &Common::DB::table_exists( $dbh, $db_table ) ) {
        &Common::DB::delete_table( $dbh, $db_table );
    }
    
    $schema = &Disease::Schema::relational;

    &Common::DB::create_table( $dbh, $db_table, $schema->{"do_stats"} );
        
    &Common::DB::load_table( $dbh, $db_file, $db_table );

    &Common::File::delete_dir_if_empty( "$Common::Config::tmp_dir/Disease" );

    &Common::DB::disconnect( $dbh );

    &echo_green( "done\n" );

    return;
}

sub update_disease
{
    # Niels Larsen, October 2004.

    # Updates disease ontology statistics with the number of node "leaves"
    # under each category. If the statistics table does not exist it is 
    # created.

    my ( $nodes,       # Nodes hash
         $stats,       # Statistics table
         $readonly,    # Readonly flag
         ) = @_;

    # Returns nothing. 

    my ( @ids, $id, $col_ndx, $col_name, $schema, $i, $row, $id_ndx, 
         $root_id, $hash );

    $root_id = &Common::DAG::Nodes::get_id_root( $nodes );

    # The following calculates counts for nodes repeatedly and is 
    # wasteful, but it finishes quickly anyway,

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        $hash = &Common::DAG::Nodes::get_ids_subtree_unique( $nodes, $id );

        $nodes->{ $id }->{"do_terms_usum"} = (scalar keys %{ $hash });
        $nodes->{ $id }->{"do_terms_tsum"} = &Common::DAG::Nodes::get_ids_subtree_total( $nodes, $id, 0 );
    }

    $schema = &Disease::Schema::relational;
    $id_ndx = &Common::DAG::Schema::field_index( $schema, "do_stats", "do_id" );

    foreach $col_name ( "do_terms_usum", "do_terms_tsum" )
    {
        $col_ndx = &Common::DAG::Schema::field_index( $schema, "do_stats", $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }
    
    return wantarray ? @{ $stats } : $stats;
}

sub create_lock
{
    # Niels Larsen, October 2004.

    # Creates a Disease/Import subdirectory under the configured scratch
    # directory. The existence of this directory means disease data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::tmp_dir/Disease/Stats" );

    return;
}

sub remove_lock
{
    # Niels Larsen, October 2004.
    
    # Deletes a Disease/Import subdirectory from the configured scratch
    # directory. Errors are thrown if the directory is not empty or if
    # it could not be deleted. 

    # Returns nothing. 

    my $lock_dir = "$Common::Config::tmp_dir/Disease/Stats";

    if ( @{ &Common::File::list_files( $lock_dir ) } )
    {
        &error( qq (Directory is not empty -> "$lock_dir") );
    }
    elsif ( not rmdir $lock_dir )
    {
        &error( qq (Could not remove lock directory "$lock_dir") );
    }

    return;
}

sub is_locked 
{
    # Niels Larsen, October 2004.

    # Checks if there is an Disease/Import subdirectory under the scratch
    # directory of the system. 

    # Returns nothing.

    my $lock_dir = "$Common::Config::tmp_dir/Disease/Stats";

    if ( -e $lock_dir ) {
        return 1;
    } else {
        return;
    }
}

1;


__END__
