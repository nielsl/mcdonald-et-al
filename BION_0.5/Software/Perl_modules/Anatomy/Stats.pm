package Anatomy::Stats;     #  -*- perl -*-

# Function statistics functions. 

use strict;
use warnings;

use Storable;
use IO::File;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &update_all
                 &update_fly
                 &update_mouse
                 &update_plant
                 &create_lock
                 &delete_lock
                 &is_locked
                  );

use Anatomy::DB;
use Anatomy::Schema;

use Common::DAG::DB;
use Common::DAG::Nodes;
use Common::Config;
use Common::Messages;
use Common::Tables;
use Common::File;
use Common::DB;


# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub update_all
{
    # Niels Larsen, October 2004.

    # Dispatches the calculation and loading of statistics for each 
    # anatomy. Each anatomy have their own database table names, which
    # get set from each routine. 
    
    my ( $wants,           # Wanted anatomy types
         $cl_readonly,     # Prints messages but does not load
         $cl_force,        # Reloads files even though database is newer
         $cl_keep,         # Avoids deleting database ready tables
         ) = @_;

    # Returns nothing.

    if ( $wants->{"all"} )
    {
        $wants->{"fly"} = 1;
        $wants->{"mouse"} = 1;
        $wants->{"moused"} = 1;
        $wants->{"plant"} = 1;
    }

    if ( $wants->{"fly"} ) 
    {
        &Anatomy::Stats::update_fly( $cl_readonly, $cl_force, $cl_keep );
    }

    if ( $wants->{"mouse"} ) 
    {
        &Anatomy::Stats::update_mouse( $cl_readonly, $cl_force, $cl_keep );
    }

    if ( $wants->{"moused"} ) 
    {
        &Anatomy::Stats::update_moused( $cl_readonly, $cl_force, $cl_keep );
    }

    if ( $wants->{"plant"} ) 
    {
        &Anatomy::Stats::update_plant( $cl_readonly, $cl_force, $cl_keep );
    }

    return;
}

sub update_fly
{
    # Niels Larsen, October 2004.

    # Updates the fly anatomy statistics database table. The type of 
    # statistic is given as keys of a hash (the first argument).

    my ( $wants,       # Wanted statistics types
         $readonly,    # Readonly toggle
         ) = @_;

    # Returns nothing.

    my ( $key, $schema, $nodes, $dbh, $sql, $stats, $db_file, 
         $id, $row, $i, $tab_dir, $col_ndx, $col_name, $id_ndx, $hash );

    $tab_dir = "$Common::Config::dat_dir/Anatomy/Database_tables";
    
    $dbh = &Common::DB::connect();

    $Anatomy::Schema::db_prefix = "flyo";
    $Anatomy::Schema::id_name = "flyo_id";
    $Anatomy::Schema::def_table = "flyo_def";
    $Anatomy::Schema::edges_table = "flyo_edges";
    $Anatomy::Schema::synonyms_table = "flyo_synonyms";
    $Anatomy::Schema::xrefs_table = "flyo_xrefs";
    $Anatomy::Schema::stats_table = "flyo_stats";

    $Anatomy::DB::db_prefix = "flyo";
    $Anatomy::DB::id_name = "flyo_id";
    $Anatomy::DB::def_table = "flyo_def";
    $Anatomy::DB::edges_table = "flyo_edges";
    $Anatomy::DB::synonyms_table = "flyo_synonyms";
    $Anatomy::DB::xrefs_table = "flyo_xrefs";
    $Anatomy::DB::stats_table = "flyo_stats";

    $Common::DAG::DB::id_name = "flyo_id";
    
    # --------- Fetch all nodes,

    &echo( qq (   Fetching fly nodes ... ) );

    $nodes = &Anatomy::DB::get_nodes_all( $dbh );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    &echo_green( "done\n" );

    # --------- Recreate statistics hash if skeleton changed,

    &echo( qq (   Adding fly node counts ... ) );

    $schema = &Anatomy::Schema::relational();

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        $hash = &Common::DAG::Nodes::get_ids_subtree_unique( $nodes, $id );

        $nodes->{ $id }->{"flyo_terms_usum"} = (scalar keys %{ $hash });
        $nodes->{ $id }->{"flyo_terms_tsum"} = &Common::DAG::Nodes::get_ids_subtree_total( $nodes, $id, 0 );
    }

    $schema = &Anatomy::Schema::relational();
    $id_ndx = &Common::DAG::Schema::field_index( $schema, "flyo_stats", "flyo_id" );

    foreach $id ( sort { $a <=> $b } &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        push @{ $stats }, [ $id ];
    }

    foreach $col_name ( "flyo_terms_usum", "flyo_terms_tsum" )
    {
        $col_ndx = &Common::DAG::Schema::field_index( $schema, "flyo_stats", $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }
 
    &echo_green( "done\n" );

    # --------- Save to file, load updated statistics, clean up,

    &echo( qq (   Loading fly statistics ... ) );
    
    &Common::File::create_dir_if_not_exists( $tab_dir );
    &Common::File::delete_file_if_exists( "$tab_dir/flyo_stats.tab" );
    
    foreach $row ( @{ $stats } )
    {
        for ( $i = 0; $i < @{ $row }; $i++ )
        {
            $row->[ $i ] = 0 if not defined $row->[ $i ];
        }
    }
    
    &Common::Tables::write_tab_table( "$tab_dir/flyo_stats.tab", $stats );

    if ( &Common::DB::table_exists( $dbh, "flyo_stats" ) ) {
        &Common::DB::delete_table( $dbh, "flyo_stats" );
    }
    
    &Common::DB::create_table( $dbh, "flyo_stats", $schema->{"flyo_stats"} );
        
    &Common::DB::load_table( $dbh, "$tab_dir/flyo_stats.tab", "flyo_stats" );

    &Common::File::delete_dir_if_empty( $tab_dir );

    &Common::DB::disconnect( $dbh );

    &echo_green( "done\n" );

    return;
}

sub update_mouse
{
    # Niels Larsen, October 2004.

    # Updates the mouse anatomy statistics database table. The type of 
    # statistic is given as keys of a hash (the first argument).

    my ( $wants,       # Wanted statistics types
         $readonly,    # Readonly toggle
         ) = @_;

    # Returns nothing.

    my ( $key, $schema, $nodes, $dbh, $sql, $stats, $db_file, 
         $id, $row, $i, $tab_dir, $col_ndx, $col_name, $id_ndx, $hash );

    $tab_dir = "$Common::Config::dat_dir/Anatomy/Database_tables";
    
    $dbh = &Common::DB::connect();

    $Anatomy::Schema::db_prefix = "mao";
    $Anatomy::Schema::id_name = "mao_id";
    $Anatomy::Schema::def_table = "mao_def";
    $Anatomy::Schema::edges_table = "mao_edges";
    $Anatomy::Schema::synonyms_table = "mao_synonyms";
    $Anatomy::Schema::xrefs_table = "mao_xrefs";
    $Anatomy::Schema::stats_table = "mao_stats";

    $Anatomy::DB::db_prefix = "mao";
    $Anatomy::DB::id_name = "mao_id";
    $Anatomy::DB::def_table = "mao_def";
    $Anatomy::DB::edges_table = "mao_edges";
    $Anatomy::DB::synonyms_table = "mao_synonyms";
    $Anatomy::DB::xrefs_table = "mao_xrefs";
    $Anatomy::DB::stats_table = "mao_stats";

    $Common::DAG::DB::id_name = "mao_id";
    
    # --------- Fetch all nodes,

    &echo( qq (   Fetching mouse nodes ... ) );

    $nodes = &Anatomy::DB::get_nodes_all( $dbh );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    &echo_green( "done\n" );

    # --------- Recreate statistics hash if skeleton changed,

    &echo( qq (   Adding mouse node counts ... ) );

    $schema = &Anatomy::Schema::relational();

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        $hash = &Common::DAG::Nodes::get_ids_subtree_unique( $nodes, $id );

        $nodes->{ $id }->{"mao_terms_usum"} = (scalar keys %{ $hash });
        $nodes->{ $id }->{"mao_terms_tsum"} = &Common::DAG::Nodes::get_ids_subtree_total( $nodes, $id, 0 );
    }

    $schema = &Anatomy::Schema::relational();
    $id_ndx = &Common::DAG::Schema::field_index( $schema, "mao_stats", "mao_id" );

    foreach $id ( sort { $a <=> $b } &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        push @{ $stats }, [ $id ];
    }

    foreach $col_name ( "mao_terms_usum", "mao_terms_tsum" )
    {
        $col_ndx = &Common::DAG::Schema::field_index( $schema, "mao_stats", $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }
 
    &echo_green( "done\n" );

    # --------- Save to file, load updated statistics, clean up,

    &echo( qq (   Loading mouse statistics ... ) );
    
    &Common::File::create_dir_if_not_exists( $tab_dir );
    &Common::File::delete_file_if_exists( "$tab_dir/mao_stats.tab" );
    
    foreach $row ( @{ $stats } )
    {
        for ( $i = 0; $i < @{ $row }; $i++ )
        {
            $row->[ $i ] = 0 if not defined $row->[ $i ];
        }
    }
    
    &Common::Tables::write_tab_table( "$tab_dir/mao_stats.tab", $stats );

    if ( &Common::DB::table_exists( $dbh, "mao_stats" ) ) {
        &Common::DB::delete_table( $dbh, "mao_stats" );
    }
    
    &Common::DB::create_table( $dbh, "mao_stats", $schema->{"mao_stats"} );
        
    &Common::DB::load_table( $dbh, "$tab_dir/mao_stats.tab", "mao_stats" );

    &Common::File::delete_dir_if_empty( $tab_dir );

    &Common::DB::disconnect( $dbh );

    &echo_green( "done\n" );

    return;
}

sub update_moused
{
    # Niels Larsen, October 2004.

    # Updates the mouse anatomy statistics database table. The type of 
    # statistic is given as keys of a hash (the first argument).

    my ( $wants,       # Wanted statistics types
         $readonly,    # Readonly toggle
         ) = @_;

    # Returns nothing.

    my ( $key, $schema, $nodes, $dbh, $sql, $stats, $db_file, 
         $id, $row, $i, $tab_dir, $col_ndx, $col_name, $id_ndx, $hash );

    $tab_dir = "$Common::Config::dat_dir/Anatomy/Database_tables";
    
    $dbh = &Common::DB::connect();

    $Anatomy::Schema::db_prefix = "mado";
    $Anatomy::Schema::id_name = "mado_id";
    $Anatomy::Schema::def_table = "mado_def";
    $Anatomy::Schema::edges_table = "mado_edges";
    $Anatomy::Schema::synonyms_table = "mado_synonyms";
    $Anatomy::Schema::xrefs_table = "mado_xrefs";
    $Anatomy::Schema::stats_table = "mado_stats";

    $Anatomy::DB::db_prefix = "mado";
    $Anatomy::DB::id_name = "mado_id";
    $Anatomy::DB::def_table = "mado_def";
    $Anatomy::DB::edges_table = "mado_edges";
    $Anatomy::DB::synonyms_table = "mado_synonyms";
    $Anatomy::DB::xrefs_table = "mado_xrefs";
    $Anatomy::DB::stats_table = "mado_stats";

    $Common::DAG::DB::id_name = "mado_id";
    
    # --------- Fetch all nodes,

    &echo( qq (   Fetching mouse embryo nodes ... ) );

    $nodes = &Anatomy::DB::get_nodes_all( $dbh );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    &echo_green( "done\n" );

    # --------- Recreate statistics hash if skeleton changed,

    &echo( qq (   Adding mouse embryo node counts ... ) );

    $schema = &Anatomy::Schema::relational();

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        $hash = &Common::DAG::Nodes::get_ids_subtree_unique( $nodes, $id );

        $nodes->{ $id }->{"mado_terms_usum"} = (scalar keys %{ $hash });
        $nodes->{ $id }->{"mado_terms_tsum"} = &Common::DAG::Nodes::get_ids_subtree_total( $nodes, $id, 0 );
    }

    $schema = &Anatomy::Schema::relational();
    $id_ndx = &Common::DAG::Schema::field_index( $schema, "mado_stats", "mado_id" );

    foreach $id ( sort { $a <=> $b } &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        push @{ $stats }, [ $id ];
    }

    foreach $col_name ( "mado_terms_usum", "mado_terms_tsum" )
    {
        $col_ndx = &Common::DAG::Schema::field_index( $schema, "mado_stats", $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }
 
    &echo_green( "done\n" );

    # --------- Save to file, load updated statistics, clean up,

    &echo( qq (   Loading mouse embryo statistics ... ) );
    
    &Common::File::create_dir_if_not_exists( $tab_dir );
    &Common::File::delete_file_if_exists( "$tab_dir/mado_stats.tab" );
    
    foreach $row ( @{ $stats } )
    {
        for ( $i = 0; $i < @{ $row }; $i++ )
        {
            $row->[ $i ] = 0 if not defined $row->[ $i ];
        }
    }
    
    &Common::Tables::write_tab_table( "$tab_dir/mado_stats.tab", $stats );

    if ( &Common::DB::table_exists( $dbh, "mado_stats" ) ) {
        &Common::DB::delete_table( $dbh, "mado_stats" );
    }
    
    &Common::DB::create_table( $dbh, "mado_stats", $schema->{"mado_stats"} );
        
    &Common::DB::load_table( $dbh, "$tab_dir/mado_stats.tab", "mado_stats" );

    &Common::File::delete_dir_if_empty( $tab_dir );

    &Common::DB::disconnect( $dbh );

    &echo_green( "done\n" );

    return;
}

sub update_plant
{
    # Niels Larsen, October 2004.

    # Updates the plant anatomy statistics database table. The type of 
    # statistic is given as keys of a hash (the first argument).

    my ( $wants,       # Wanted statistics types
         $readonly,    # Readonly toggle
         ) = @_;

    # Returns nothing.

    my ( $key, $schema, $nodes, $dbh, $sql, $stats, $db_file, 
         $db_table, $id, $row, $i, $tab_dir, $col_ndx, $col_name,
         $id_ndx, $hash );

    $tab_dir = "$Common::Config::dat_dir/Anatomy/Database_tables";
    $db_table = "po_stats";
    
    $dbh = &Common::DB::connect();

    $Anatomy::Schema::db_prefix = "po";
    $Anatomy::Schema::id_name = "po_id";
    $Anatomy::Schema::def_table = "po_def";
    $Anatomy::Schema::edges_table = "po_edges";
    $Anatomy::Schema::synonyms_table = "po_synonyms";
    $Anatomy::Schema::xrefs_table = "po_xrefs";
    $Anatomy::Schema::stats_table = "po_stats";

    $Anatomy::DB::db_prefix = "po";
    $Anatomy::DB::id_name = "po_id";
    $Anatomy::DB::def_table = "po_def";
    $Anatomy::DB::edges_table = "po_edges";
    $Anatomy::DB::synonyms_table = "po_synonyms";
    $Anatomy::DB::xrefs_table = "po_xrefs";
    $Anatomy::DB::stats_table = "po_stats";

    $Common::DAG::DB::id_name = "po_id";
    
    
    # --------- Fetch all nodes,

    &echo( qq (   Fetching plant nodes ... ) );

    $nodes = &Anatomy::DB::get_nodes_all( $dbh );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    &echo_green( "done\n" );

    # --------- Recreate statistics hash if skeleton changed,

    &echo( qq (   Adding plant node counts ... ) );

    $schema = &Anatomy::Schema::relational();

    foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        $hash = &Common::DAG::Nodes::get_ids_subtree_unique( $nodes, $id );

        $nodes->{ $id }->{"po_terms_usum"} = (scalar keys %{ $hash });
        $nodes->{ $id }->{"po_terms_tsum"} = &Common::DAG::Nodes::get_ids_subtree_total( $nodes, $id, 0 );
    }

    $schema = &Anatomy::Schema::relational();
    $id_ndx = &Common::DAG::Schema::field_index( $schema, "po_stats", "po_id" );

    foreach $id ( sort { $a <=> $b } &Common::DAG::Nodes::get_ids_all( $nodes ) )
    {
        push @{ $stats }, [ $id ];
    }

    foreach $col_name ( "po_terms_usum", "po_terms_tsum" )
    {
        $col_ndx = &Common::DAG::Schema::field_index( $schema, "po_stats", $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }
 
    &echo_green( "done\n" );

    # --------- Save to file, load updated statistics, clean up,

    &echo( qq (   Loading plant statistics ... ) );
    
    &Common::File::create_dir_if_not_exists( $tab_dir );
    &Common::File::delete_file_if_exists( "$tab_dir/po_stats.tab" );
    
    foreach $row ( @{ $stats } )
    {
        for ( $i = 0; $i < @{ $row }; $i++ )
        {
            $row->[ $i ] = 0 if not defined $row->[ $i ];
        }
    }
    
    &Common::Tables::write_tab_table( "$tab_dir/po_stats.tab", $stats );

    if ( &Common::DB::table_exists( $dbh, "po_stats" ) ) {
        &Common::DB::delete_table( $dbh, "po_stats" );
    }
    
    &Common::DB::create_table( $dbh, "po_stats", $schema->{"po_stats"} );
        
    &Common::DB::load_table( $dbh, "$tab_dir/po_stats.tab", "po_stats" );

    &Common::File::delete_dir_if_empty( $tab_dir );

    &Common::DB::disconnect( $dbh );

    &echo_green( "done\n" );

    return;
}

sub create_lock
{
    # Niels Larsen, October 2004.

    # Creates a Anatomy/Stats subdirectory under the configured scratch
    # directory. The existence of this directory means disease data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::tmp_dir/Anatomy/Stats" );

    return;
}

sub remove_lock
{
    # Niels Larsen, October 2004.
    
    # Deletes a Anatomy/Stats subdirectory from the configured scratch
    # directory. Errors are thrown if the directory is not empty or if
    # it could not be deleted. 

    # Returns nothing. 

    my $lock_dir = "$Common::Config::tmp_dir/Anatomy/Stats";

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

    # Checks if there is an Anatomy/Stats subdirectory under the scratch
    # directory of the system. 

    # Returns nothing.

    my $lock_dir = "$Common::Config::tmp_dir/Anatomy/Stats";

    if ( -e $lock_dir ) {
        return 1;
    } else {
        return;
    }
}

1;


__END__
