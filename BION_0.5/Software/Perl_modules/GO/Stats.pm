package GO::Stats;     #  -*- perl -*-

# Function statistics functions. 

use strict;
use warnings;

use Storable;
use IO::File;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &update
                 &update_go
                 &update_go_genes
                 &update_go_orgs
                 &schema_column_index
                 &create_lock
                 &delete_lock
                 &is_locked
                  );

use GO::DB;
use GO::Nodes;
use GO::Schema;

use Common::Config;
# use Common::Schema;
use Common::Messages;
use Common::Tables;
use Common::File;
use Common::DB;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub update
{
    # Niels Larsen, October 2003.

    # Updates the GO statistics database. It can update one type of 
    # statistics at a time, or all at once. The type of statistic is 
    # given as keys of a hash (the first argument).

    my ( $wants,       # Wanted statistics types
         $readonly,    # Readonly toggle
         ) = @_;

    # Returns nothing.

    my ( $key, $schema, $nodes, $dbh, $sql, $stats, $db_file, 
         $db_table, $id, $row, $i );

    $db_file = "$Common::Config::tmp_dir/GO/stats.tab";
    $db_table = "go_stats";
    
    $dbh = &Common::DB::connect();

    # --------- Set every option to 1 if "all" given,

    if ( $wants->{"all"} ) {
        $wants = { map { $_, 1 } keys %{ $wants } };
    }

    # --------- Fetch all GO nodes,

    &echo( qq (   Fetching GO nodes ... ) );

    $nodes = &GO::DB::get_nodes_all( $dbh );
    $nodes = &GO::Nodes::set_ids_children_all( $nodes );

    &echo_green( "done\n" );
    
    # --------- Recreate statistics hash if skeleton changed,

    if ( $wants->{"all"} or $wants->{"go"} )
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

    # --------- Update GO skeleton statistics,

    if ( $wants->{"go"} )
    {
        &echo( qq (   Adding ontology node counts ... ) );

        $stats = &GO::Stats::update_go( $nodes, $stats, $readonly );

        &echo_green( "done\n" );
    }

    # --------- Update gene association statistics, 
    
    if ( $wants->{"genes"} )
    {
        &echo( qq (   Adding gene counts (10-20 minutes) ... ) );

        $stats = &GO::Stats::update_go_genes( $dbh, $nodes, $stats, $readonly );

        &echo_green( "done\n" );
    }

    # --------- Update gene association organism statistics, 
    
    if ( $wants->{"orgs"} )
    {
        &echo( qq (   Adding gene organism counts ... ) );

        $stats = &GO::Stats::update_go_orgs( $dbh, $nodes, $stats, $readonly );

        &echo_green( "done\n" );
    }

    # --------- Save to file, load updated statistics, clean up,

    &echo( qq (   Loading statistics into database ... ) );
    
    &Common::File::create_dir_if_not_exists( "$Common::Config::tmp_dir/GO" );
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
    
    $schema = &GO::Schema::relational()->{"go_stats"};

    &Common::DB::create_table( $dbh, $db_table, $schema );
        
    &Common::DB::load_table( $dbh, $db_file, $db_table );

    &Common::File::delete_dir_if_empty( "$Common::Config::tmp_dir/GO" );

    &Common::DB::disconnect( $dbh );

    &echo_green( "done\n" );

    return;
}

sub update_go
{
    # Niels Larsen, October 2003.

    # Updates gene ontology statistics with the number of node "leaves"
    # under each category. If the statistics table does not exist it is 
    # created.

    my ( $nodes,       # Nodes hash
         $stats,       # Statistics table
         $readonly,    # Readonly flag
         ) = @_;

    # Returns nothing. 

    my ( @ids, $id, $col_ndx, $col_name, $schema, $i, $row, $id_ndx, 
         $root_id, $hash );

    $root_id = &GO::Nodes::get_id_root( $nodes );

    # The following calculates counts for nodes repeatedly and is 
    # wasteful, but it finishes quickly anyway,

    foreach $id ( &GO::Nodes::get_ids_all( $nodes ) )
    {
        $hash = &GO::Nodes::get_ids_subtree_unique( $nodes, $id );

        $nodes->{ $id }->{"go_terms_usum"} = (scalar keys %{ $hash });
        $nodes->{ $id }->{"go_terms_tsum"} = &GO::Nodes::get_ids_subtree_total( $nodes, $id, 0 );
    }

    $schema = &GO::Schema::relational()->{"go_stats"};
    $id_ndx = &Common::Schema::field_index( $schema, "go_id" );

    foreach $col_name ( "go_terms_usum", "go_terms_tsum" )
    {
        $col_ndx = &Common::Schema::field_index( $schema, $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }

    return wantarray ? @{ $stats } : $stats;
}

sub update_go_genes
{
    # Niels Larsen, January 2004.

    # Updates gene ontology statistics with the number of associated 
    # gene products under each category.

    my ( $dbh,         # Database handle
         $nodes,       # Nodes hash
         $stats,       # Statistics table
         $readonly,    # Readonly flag
         ) = @_;
    
    # Returns nothing. 
    
    my ( @ids, $id, $p_id, $col_ndx, $col_name, $schema, $i, $row, $id_ndx, 
         $root_id, $hash, $idstr, $sql, $count, $p_nodes );

    $root_id = &GO::Nodes::get_id_root( $nodes );

    # Attach gene associations for each GO node,

    foreach $id ( &GO::Nodes::get_ids_all( $nodes ) )
    {
        $sql = qq (select count(go_id) from go_genes_tax where go_id = $id);
        $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        $nodes->{ $id }->{"go_genes_node"} = $count;

        $hash = &GO::Nodes::get_ids_subtree_unique( $nodes, $id );
        $hash->{ $id } = 1;

        if ( %{ $hash } )
        {
            $idstr = join ",", keys %{ $hash };
            $sql = qq (select count(distinct gen_id) from go_genes_tax where go_id in ( $idstr ));

            $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];
            $nodes->{ $id }->{"go_genes_usum"} = $count;
        }
        else
        {
            $nodes->{ $id }->{"go_genes_usum"} = 0;
        }
    }

    # Sum up the go_genes_tsum statistics. We do this by incrementing the 
    # parents counts for each node,

    foreach $id ( &GO::Nodes::get_ids_all( $nodes ) )
    {
        if ( defined $nodes->{ $id }->{"go_genes_tsum"} ) {
            $nodes->{ $id }->{"go_genes_tsum"} += $nodes->{ $id }->{"go_genes_node"};
        } else {
            $nodes->{ $id }->{"go_genes_tsum"} = $nodes->{ $id }->{"go_genes_node"};
        }            

        $p_nodes = &GO::Nodes::get_parents_all( $nodes, $id );

         foreach $p_id ( keys %{ $p_nodes } )
         {
            if ( defined $nodes->{ $p_id }->{"go_genes_tsum"} ) {
                $nodes->{ $p_id }->{"go_genes_tsum"} += $nodes->{ $id }->{"go_genes_node"};
            } else {
                $nodes->{ $p_id }->{"go_genes_tsum"} = $nodes->{ $id }->{"go_genes_node"};
            }
         }
    }

    $schema = &GO::Schema::relational()->{"go_stats"};
    $id_ndx = &Common::Schema::field_index( $schema, "go_id" );

    foreach $col_name ( "go_genes_node", "go_genes_tsum", "go_genes_usum" )
    {
        $col_ndx = &Common::Schema::field_index( $schema, $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }

    return wantarray ? @{ $stats } : $stats;
}

sub update_go_orgs
{
    # Niels Larsen, January 2004.

    # Updates gene ontology statistics with the number of unique organisms
    # for which there are associated gene products under a given category.

    my ( $dbh,         # Database handle
         $nodes,       # Nodes hash
         $stats,       # Statistics table
         $readonly,    # Readonly flag
         ) = @_;
    
    # Returns nothing. 
    
    my ( @ids, $id, $p_id, $col_ndx, $col_name, $schema, $i, $row, $id_ndx, 
         $root_id, $hash, $idstr, $sql, $count, $p_nodes );

    $root_id = &GO::Nodes::get_id_root( $nodes );

    # Attach gene associations for each GO node,

    foreach $id ( &GO::Nodes::get_ids_all( $nodes ) )
    {
        $hash = &GO::Nodes::get_ids_subtree_unique( $nodes, $id );
        $hash->{ $id } = 1;

        if ( %{ $hash } )
        {
            $idstr = join ",", keys %{ $hash };
            $sql = qq (select count(distinct tax_id) from go_genes_tax where go_id in ( $idstr ));

            $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];
            $nodes->{ $id }->{"go_orgs_usum"} = $count;
        }
        else
        {
            $nodes->{ $id }->{"go_orgs_usum"} = 0;
        }            
    }

    $schema = &GO::Schema::relational()->{"go_stats"};
    $id_ndx = &Common::Schema::field_index( $schema, "go_id" );

    foreach $col_name ( "go_orgs_usum" )
    {
        $col_ndx = &Common::Schema::field_index( $schema, $col_name );

        foreach $row ( @{ $stats } )
        {
            $id = $row->[ $id_ndx ];
            $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
        }
    }

    return wantarray ? @{ $stats } : $stats;
}

sub schema_column_index
{
    # Niels Larsen, October 2003.

    # Simply returns the column index of a given field name in a
    # given schema.

    my ( $schema,    # Schema array
         $name,      # Field name
         ) = @_;

    # Returns an integer. 

    my ( $ndx, $i, $str );

    $ndx = undef;
    
    for ( $i = 0; $i < @{ $schema }; $i++ )
    {
        $str = $schema->[ $i ]->[0];
        $ndx = $i if $name =~ /^$str$/i;
    }

    if ( defined $ndx ) {
        return $ndx;
    } else {
        return;
    }
}

sub create_lock
{
    # Niels Larsen, October 2003.

    # Creates a GO/Import subdirectory under the configured scratch
    # directory. The existence of this directory means GO data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::tmp_dir/GO/Stats" );

    return;
}

sub remove_lock
{
    # Niels Larsen, October 2003.
    
    # Deletes a GO/Import subdirectory from the configured scratch
    # directory. Errors are thrown if the directory is not empty or if
    # it could not be deleted. 

    # Returns nothing. 

    my $lock_dir = "$Common::Config::tmp_dir/GO/Stats";

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
    # Niels Larsen, October 2003.

    # Checks if there is an GO/Import subdirectory under the scratch
    # directory of the system. 

    # Returns nothing.

    my $lock_dir = "$Common::Config::tmp_dir/GO/Stats";

    if ( -e $lock_dir ) {
        return 1;
    } else {
        return;
    }
}

1;


__END__


# sub update_go_orgs
# {
#     # Niels Larsen, January 2004.

#     # Updates gene ontology statistics with the number of unique organisms
#     # for which there are associated gene products under a given category.

#     my ( $dbh,         # Database handle
#          $nodes,       # Nodes hash
#          $stats,       # Statistics table
#          $readonly,    # Readonly flag
#          ) = @_;
    
#     # Returns nothing. 
    
#     my ( @ids, $id, $p_id, $col_ndx, $col_name, $schema, $i, $row, $id_ndx, 
#          $root_id, $hash, $idstr, $sql, $count, $p_nodes );

#     $root_id = &GO::Nodes::get_id_root( $nodes );

#     # Attach gene associations for each GO node,

#     foreach $id ( &GO::Nodes::get_ids_all( $nodes ) )
#     {
#         $sql = qq (select count(distinct tax_id) from go_genes where id = $id);
#         $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

#         $nodes->{ $id }->{"orgs"} = $count;
#     }

#     # Sum up the statistics. We do this by incrementing the parents counts
#     # for each node,

#     foreach $id ( &GO::Nodes::get_ids_all( $nodes ) )
#     {
#         if ( defined $nodes->{ $id }->{"orgs_total"} ) {
#             $nodes->{ $id }->{"orgs_total"} += $nodes->{ $id }->{"orgs"};
#         } else {
#             $nodes->{ $id }->{"orgs_total"} = $nodes->{ $id }->{"orgs"};
#         }            

#         $p_nodes = &GO::Nodes::get_parents_all( $nodes, $id );

#          foreach $p_id ( keys %{ $p_nodes } )
#          {
#             if ( defined $nodes->{ $p_id }->{"orgs_total"} ) {
#                 $nodes->{ $p_id }->{"orgs_total"} += $nodes->{ $id }->{"orgs"};
#             } else {
#                 $nodes->{ $p_id }->{"orgs_total"} = $nodes->{ $id }->{"orgs"};
#             }
#          }
#     }

#     $schema = &GO::Schema::relational()->{"go_stats"};
#     $id_ndx = &Common::Schema::field_index( $schema, "id" );

#     foreach $col_name ( "orgs", "orgs_total" )
#     {
#         $col_ndx = &Common::Schema::field_index( $schema, $col_name );

#         foreach $row ( @{ $stats } )
#         {
#             $id = $row->[ $id_ndx ];
#             $row->[ $col_ndx ] = $nodes->{ $id }->{ $col_name };
#         }
#     }

#     return wantarray ? @{ $stats } : $stats;
# }
