package Taxonomy::Stats;     #  -*- perl -*-

# Functions that create and maintain taxonomy statistics. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_sim_stats
                 &create_stats
                 &load_stats
                 &update_all
                 &update_dna
                 &update_ssu_rna
                 &update_nodes
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::File;
use Common::DB;
use Common::Util;

use Taxonomy::DB;
use Taxonomy::Nodes;
use Taxonomy::Schema;


# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# sub create_sim_stats
# {
#     # Niels Larsen, December 2005.

#     # Maps a given list of similarities (of the form defined by the 
#     # user_sims schema) to the taxonomy. The output is a table of 
#     # mappings as defined by the tax_stats schema. 

#     my ( $jid,         # Job id
#          $sims,        # Similarities table
#          $inputdb,    # Server database 
#          $datatype,    # Data type, e.g. "orgs_taxa", "rna_seq", "prot_seq" .. 
#          ) = @_;

#     # Returns a list. 

#     my ( $dbh, $nodes, $pcts, $sql, $tuple, $rna_id, $tax_id, $node, 
#          $pct, $idstr, $subref, $stats, $count, $schema, 
#          $ent_ndx, $val_ndx );

#     # Get all taxonomy nodes,

#     $dbh = &Common::DB::connect();

#     $nodes = &Taxonomy::DB::get_nodes_all( $dbh, "tax_id,parent_id" );
#     $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes, 1 );

#     # Get [ rna_id, tax_id ] tuples and set the "maxpct" key on all 
#     # nodes with similarity,

#     $schema = &Common::Schema::relational()->{"user_sims"};
#     $ent_ndx = &Common::Schema::field_index( $schema, "ent_id" );
#     $val_ndx = &Common::Schema::field_index( $schema, "value" );

#     $pcts = { map { $_->[$ent_ndx], $_->[$val_ndx] } @{ $sims } };
#     $idstr = join ",", map { $_->[$ent_ndx] } @{ $sims };

#     $sql = qq (select distinct tax_id,rna_id from rna_organism where rna_id in ( $idstr) );

#     foreach $tuple ( @{ &Common::DB::query_array( $dbh, $sql ) } )
#     {
#         ( $tax_id, $rna_id ) = @{ $tuple };

#         if ( $pct = $pcts->{ $rna_id } )
#         {
#             $node = $nodes->{ $tax_id };

#             if ( defined $node->{"maxpct"} ) {
#                 $node->{"maxpct"} = $pct if $pct > $node->{"maxpct"};
#             } else {
#                 $node->{"maxpct"} = $pct;
#             }
#         }
#         else {
#             &error( qq (Molecule id without percentage -> "$rna_id") );
#             exit;
#         }
#     }

#     $count = keys %{ $pcts };

#     # Accumulate max-percentages from the tree leaves towards the root node,

#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $maxpct, $p_node );
        
#         # This conditional is necessary because NCBI frequently posts nodes
#         # with no parent and they will not fix it; they say it is not an error. 
        
#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             if ( exists $nodes->{ $nid }->{"maxpct"} )
#             {
#                 $p_node = $nodes->{ $p_id };
#                 $maxpct = $nodes->{ $nid }->{"maxpct"};
                
#                 if ( exists $p_node->{"maxpct"} ) {
#                     $nodes->{ $p_id }->{"maxpct"} = $maxpct if $maxpct > $p_node->{"maxpct"};
#                 } else {
#                     $nodes->{ $p_id }->{"maxpct"} = $maxpct;
#                 }
#             }
#         }
#     };

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref );

#     # Create tax_stats table,

#     $stats = [];

#     foreach $tax_id ( &Taxonomy::Nodes::get_ids_all( $nodes ) )
#     {
#         $node = $nodes->{ $tax_id };

#         if ( exists $node->{"maxpct"} )
#         {
#             push @{ $stats }, [ $tax_id, $jid, $inputdb, $datatype, $node->{"maxpct"}, "" ];
#         }
#     }

#     &Common::DB::disconnect( $dbh );

#     return wantarray ? @{ $stats } : $stats;
# }

sub create_stats
{
    # Niels Larsen, November 2005.

    # This routine is written 
    # Updates counts across the given taxonomy tree (all in ram). A query 
    # is given, which is an sql string that will be executed for each tree
    # leaf and the result, a count, is attached to the tree. The counts are
    # then summed up, so that nodes deep in the tree are assigned the sums
    # of the counts in the subtrees they span. Finally all values are put
    # in a list of [ tax_id, value, sum, "" ] which is returned. 

    my ( $dbh,             # Database handle
         $nodes,           # Nodes tree 
         $query,           # SQL query string
         ) = @_;

    # Returns a list. 
    
    my ( $tax_id, @values, $argref, $subref, @stats, $sql, $node, $value, 
         $sum, $idstr );

    # >>>>>>>>>>>>>>>>>>>>>>>>> SET LEAF VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $tax_id ( keys %{ $nodes } )
    {
        $nodes->{ $tax_id }->{"sum"} = 0;
        delete $nodes->{ $tax_id }->{"ids"};

        $sql = $query;
        $sql =~ s/TAX_ID/$tax_id/;
        
        $value = &Common::DB::query_array( $dbh, $sql )->[0]->[0] || 0;

        $nodes->{ $tax_id }->{"value"} = $value;
    }

    # >>>>>>>>>>>>>>>>>>>>>>> SUM PARENT NODE VALUES <<<<<<<<<<<<<<<<<<<<<<

    $subref = sub
    {
        my ( $nodes, $nid ) = @_;
        my ( $p_id, $value, $sum );

        # It is necessary to check if nodes actually have parents, because NCBI 
        # frequently posts nodes with no parent and will not fix it; they say 
        # it is not an error. Geez.
        
        if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
        {
            $nodes->{ $nid }->{"sum"} += $nodes->{ $nid }->{"value"};
            $nodes->{ $p_id }->{"sum"} += $nodes->{ $nid }->{"sum"};
        }
    };

    $argref = [];
    &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CREATE FLAT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $node ( &Taxonomy::Nodes::get_nodes_all( $nodes ) )
    {
        $tax_id = &Taxonomy::Nodes::get_id( $node );

        $value = &Taxonomy::Nodes::get_key( $node, "value" );
        $sum = &Taxonomy::Nodes::get_key( $node, "sum" );

        if ( $sum > 0 )
        {
            push @stats, [ $tax_id, $value || 0, $sum, "" ];
        }
    }
    
    return wantarray ? @stats : \@stats;
}

sub load_stats
{
    # Niels Larsen, November 2005.

    # Writes a statistics file to scratch area and loads it into database.
    # Existing statistics of the given source and type are deleted. The 
    # temp file is deleted, and directory if it is empty. The number of 
    # records loaded is returned. 

    my ( $dbh,         # Database handle
         $inputdb,    # Server database ("ncbi", "rRNA_18S_500", etc)
         $datatype,    # Data type ("rna_seq", "orgs_taxa", etc)
         $stats,       # Statistics made by create_stats
         ) = @_;

    # Returns nothing.

    my ( $tmp_dir, $column, $tmp_file, $db_table, $sql, $count, $db_tableO );

    # Add three left columns to the table,

    $column = [ ( $datatype ) x scalar @{ $stats } ];
    $column = &Storable::dclone( $column );
    &Common::Tables::splice_column( $stats, 1, 0, $column );

    $column = [ ( $inputdb ) x scalar @{ $stats } ];
    $column = &Storable::dclone( $column );
    &Common::Tables::splice_column( $stats, 1, 0, $column );

    $column = [ ( 0 ) x scalar @{ $stats } ];
    $column = &Storable::dclone( $column );
    &Common::Tables::splice_column( $stats, 1, 0, $column );

    # Names,

    $db_table = "tax_stats";

    $tmp_dir = "$Common::Config::tmp_dir/Taxonomy";
    $tmp_file = "$tmp_dir/$db_table.tab";

    # Create scratch directory and table if not exist. If table does exist,
    # remove existing records of the same type,

    &Common::File::create_dir_if_not_exists( $tmp_dir );
    &Common::File::delete_file_if_exists( $tmp_file );

    &Common::Tables::write_tab_table( $tmp_file, $stats );

    if ( &Common::DB::table_exists( $dbh, $db_table ) )
    {
        $sql = qq (delete from $db_table where inputdb = '$inputdb' and datatype = '$datatype');
        &Common::DB::request( $dbh, $sql );
    }
    else
    {
        $db_tableO = Taxonomy::Schema->get->table( $db_table );
        &Common::DB::create_table( $dbh, $db_tableO );
    }

    # Load,

    &Common::DB::load_table( $dbh, $tmp_file, $db_table );

    # Remove temp files,

    &Common::File::delete_file( $tmp_file );
    &Common::File::delete_dir_if_empty( $tmp_dir );

    return scalar @{ $stats };
}

sub update_all
{
    # Niels Larsen, September 2003.

    # Updates the taxonomy organism counts in the database.

    my ( $cl_data,     # Command line data arguments
         $cl_args,     # Command line switches arguments
         ) = @_;

    # Returns nothing.

    my ( $dbh, $tax_dir, $silent, $nodes, $stats, $count, $readonly );

    $readonly = $cl_args->{"readonly"};

    if ( not $readonly ) {
        $dbh = &Common::DB::connect();
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS EACH TAXONOMY <<<<<<<<<<<<<<<<<<<<<<<<<<
     
    foreach $tax_dir ( keys %{ $cl_data } )
    {
        if ( $cl_data->{ $tax_dir } or $cl_data->{"all"} )
        {
            &echo( qq (   Updating $tax_dir node statistics ... ) );

            if ( $readonly ) {
                &echo_green( "skipped\n" );
            }
            else
            {
                {
                    local $Common::Messages::silent = 1;
                
                    $nodes = &Taxonomy::DB::build_taxonomy( $dbh, "tax_id,parent_id,nmin,nmax" );
                    
                    $stats = &Taxonomy::Stats::update_nodes( $dbh, $nodes );
                    $count = &Taxonomy::Stats::load_stats( $dbh, $tax_dir, "orgs_taxa", $stats );
                }

                $count = &Common::Util::commify_number( $count );
                &echo_green( "$count nodes\n" );
            }
        }
    }

    if ( not $readonly ) {
        &Common::DB::disconnect( $dbh );
    }

    return;
}

# sub update_dna
# {
#     # Niels Larsen, September 2003.

#     # Updates each node in the taxonomy with 
#     # 
#     #    Number of organisms that have DNA
#     #    Number of organism DNA entries 
#     #    Total number of bases
#     #    G+C percentage
#     #    Number of ESTs
#     #    Number of Protein genes (CDS)
#     #    Number of RNAs 
#     #    Number of other features
#     #
#     # The update is done on the tax_stats database table. 

#     my ( $dbh,         # Database handle
#          $nodes,       # Nodes hash
#          $stats,       # Statistics table
#          $readonly,    # Readonly flag
#          ) = @_;

#     # Returns nothing. 

#     my ( @ids, $col_ndx, $i, $j, $col, $row, $tax_id, $subref, $argref, $sql,
#          $idstr, $entry, $stats_schema, $length, $a, $g, $c, $t, $type,
#          $type_tsum, $p_id, $tax_id_ndx, $terse, $indent );

#     $stats_schema = &Taxonomy::Schema::relational()->{"tax_stats"};

#     # >>>>>>>>>>>>>>>>>>> ORGANISMS, ENTRIES AND BASES <<<<<<<<<<<<<<<<<<<<<

#     # First set the values as they are given by the DNA database,

#     foreach $tax_id ( keys %{ $nodes } )
#     {
#         $sql = qq (select ent_id,tax_id from dna_organism where tax_id = '$tax_id');
#         @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
        
#         if ( @ids )
#         {
#             $nodes->{ $tax_id }->{"dna_orgs_node"} = 1;
#             $nodes->{ $tax_id }->{"dna_entries_node"} = scalar @ids;
            
#             $a = $g = $c = $t = 0;
                
#             $i = 0;
#             $j = 9999;

#             while ( $i <= $#ids )
#             {
#                 $j = $#ids if $j > $#ids;
                
#                 $idstr = "'". (join "','", @ids[ $i .. $j ] ) . "'";
#                 $sql = qq (select a,g,c,t from dna_molecule where ent_id in ($idstr));
            
#                 foreach $entry ( &Common::DB::query_array( $dbh, $sql ) )
#                 {
#                     $a += $entry->[0];
#                     $g += $entry->[1];
#                     $c += $entry->[2];
#                     $t += $entry->[3];
#                 }
                
#                 $i += 10000;
#                 $j += 10000;
#             }

#             $nodes->{ $tax_id }->{"dna_bases_node"} = $a + $g + $c + $t;
#             $nodes->{ $tax_id }->{"dna_gc_distrib_node"} = [ $a, $g, $c, $t ];
#         }
#         else
#         {
#             $nodes->{ $tax_id }->{"dna_orgs_node"} = 0;
#             $nodes->{ $tax_id }->{"dna_entries_node"} = 0;
#             $nodes->{ $tax_id }->{"dna_bases_node"} = 0;
#         }
#     }

#     $tax_id_ndx = &Common::Schema::field_index( $stats_schema, "tax_id" );

#     foreach $type ( "dna_orgs_node", "dna_entries_node", "dna_bases_node" )
#     {
#         $col_ndx = &Common::Schema::field_index( $stats_schema, $type );
        
#         foreach $row ( @{ $stats } )
#         {
#             $tax_id = $row->[ $tax_id_ndx ];
#             $row->[ $col_ndx ] = $nodes->{ $tax_id }->{ $type } || 0;
#         }
#     }

#     # -------- The total number of organisms with DNA in a given subtree,
    
#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $node_count, $sum_count );

#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             $node_count = $nodes->{ $nid }->{"dna_orgs_node"} || 0;
#             $nodes->{ $nid }->{"dna_orgs_tsum"} += $node_count;

#             $sum_count = $nodes->{ $nid }->{"dna_orgs_tsum"} || 0;
#             $nodes->{ $p_id }->{"dna_orgs_tsum"} += $sum_count;
#         }
#     };

#     $argref = [];

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "dna_orgs_tsum" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $nodes->{ $tax_id }->{"dna_orgs_tsum"} || 0;
#     }
    
#     # -------- The total number of entries in a given subtree,
    
#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $node_count, $sum_count );

#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             $node_count = $nodes->{ $nid }->{"dna_entries_node"} || 0;
#             $nodes->{ $nid }->{"dna_entries_tsum"} += $node_count;

#             $sum_count = $nodes->{ $nid }->{"dna_entries_tsum"} || 0;
#             $nodes->{ $p_id }->{"dna_entries_tsum"} += $sum_count;
#         }
#     };

#     $argref = [];

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "dna_entries_tsum" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $nodes->{ $tax_id }->{"dna_entries_tsum"} || 0;
#     }
    
#     # -------- The total number of DNA bases in a given subtree,
    
#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $node_count, $sum_count );

#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             $node_count = $nodes->{ $nid }->{"dna_bases_node"} || 0;
#             $nodes->{ $nid }->{"dna_bases_tsum"} += $node_count;

#             $sum_count = $nodes->{ $nid }->{"dna_bases_tsum"} || 0;
#             $nodes->{ $p_id }->{"dna_bases_tsum"} += $sum_count;
#         }
#     };

#     $argref = [];

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "dna_bases_tsum" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $nodes->{ $tax_id }->{"dna_bases_tsum"} || 0;
#     }
    
#     # --------- G+C distribution, 

#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $counts, $gc, $pct, $distrib, $p_node, $i );

#         if ( $counts = $nodes->{ $nid }->{"dna_gc_distrib_node"} )
#         {
#             $gc = $counts->[1] + $counts->[2];
#             $pct = 100 * $gc / ( $gc + $counts->[0] + $counts->[3] );

#             $nodes->{ $nid }->{"dna_gc_distrib_node"} = $pct;
#         }

#         # This if is necessary because NCBI frequently posts nodes with no 
#         # parent and they will not fix it; they say it is not an error. 
        
#          if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#          {
#              if ( $distrib = $nodes->{ $nid }->{"dna_gc_distrib_tsum"} )
#              {
#                  $p_node = $nodes->{ $p_id };
                
#                 if ( not $p_node->{"dna_gc_distrib_tsum"} ) {
#                     $p_node->{"dna_gc_distrib_tsum"} = [ (0) x 20 ];
#                 }

#                  for ( $i = 0; $i <= $#{ $distrib }; $i++ ) {
#                      $p_node->{"dna_gc_distrib_tsum"}->[$i] += $distrib->[$i];
#                  }

#                 if ( $pct = $nodes->{ $nid }->{"dna_gc_distrib_node"} ) {
#                     $nodes->{ $nid }->{"dna_gc_distrib_tsum"}->[ int $pct/5 ]++;
#                 }
#              }
#             elsif ( $nodes->{ $nid }->{"dna_gc_distrib_node"} )
#             {
#                  $p_node = $nodes->{ $p_id };
                
#                 if ( not $p_node->{"dna_gc_distrib_tsum"} ) {
#                     $p_node->{"dna_gc_distrib_tsum"} = [ (0) x 20 ];
#                 }
                
#                 $p_node->{"dna_gc_distrib_tsum"}->[ int $pct/5 ]++;
#             }
#          }
#     };

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref );

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "dna_gc_distrib_node" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = sprintf "%.1f", $nodes->{ $tax_id }->{"dna_gc_distrib_node"} || 0;
#     }

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "dna_gc_distrib_tsum" );

#     $terse = $Data::Dumper::Terse;
#     $indent = $Data::Dumper::Indent;

#     $Data::Dumper::Terse = 1;
#     $Data::Dumper::Indent = 0;

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];

#         if ( $nodes->{ $tax_id }->{"dna_gc_distrib_tsum"} ) {
#             $row->[ $col_ndx ] = Dumper( $nodes->{ $tax_id }->{"dna_gc_distrib_tsum"} );
#         } else {
#             $row->[ $col_ndx ] = "";
#         }
#     }

#     $Data::Dumper::Terse = $terse;
#     $Data::Dumper::Indent = $indent;

#     return wantarray ? @{ $stats } : $stats;
# }

# sub update_ssu_rna
# {
#     # Niels Larsen, November 2005.

#     # Updates different SSU RNA related counts. 

#     my ( $dbh, 
#          $nodes,
#          ) = @_;

#     # Returns nothing. 

#     my ( $datatype, $query, $count, $stats, $minlen, $root );

#     # Below, TAX_ID is a placeholder that gets replaced by a real taxonomy
#     # id in the .

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> ORGANISM COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     foreach $minlen ( 0, 500, 1250 )
#     {
#         &echo( qq (   Organisms with SSU RNA >= $minlen ... ) );

#         if ( $minlen == 0 ) {
#             $query = qq (select distinct 1 from rna_organism where tax_id = TAX_ID);
#         } else {
#             $query = qq (select distinct 1 from rna_molecule where tax_id = TAX_ID)
#                    . qq ( and length >= $minlen);
#         }
            
#         $stats = &Taxonomy::Stats::create_stats( $dbh, $nodes, $query );
#         &Taxonomy::Stats::load_stats( $dbh, "rRNA_18S_$minlen", "orgs_taxa", $stats );

#         $root = &Taxonomy::Nodes::get_node_root( $nodes );
#         $count = $root->{"sum"} || 0 + $root->{"value"} || 0;
#         $count = &Common::Util::commify_number( $count );

#         &echo_green( "$count\n" );
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     foreach $minlen ( 0, 500, 1250 )
#     {
#         &echo( qq (   Number of SSU RNAs >= $minlen ... ) );
        
#         if ( $minlen == 0 ) {
#             $query = qq (select count(distinct rna_id) from rna_organism where)
#                    . qq ( tax_id = TAX_ID);
#         } else {
#             $query = qq (select count(distinct rna_id) from rna_molecule)
#                    . qq ( where tax_id = TAX_ID and length >= $minlen);
#         }
            
#         $stats = &Taxonomy::Stats::create_stats( $dbh, $nodes, $query );
#         &Taxonomy::Stats::load_stats( $dbh, "rRNA_18S_$minlen", "rna_seq", $stats );
        
#         $root = &Taxonomy::Nodes::get_node_root( $nodes );
#         $count = $root->{"sum"} || 0 + $root->{"value"} || 0;
#         $count = &Common::Util::commify_number( $count );

#         &echo_green( "$count\n" );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BASE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     &echo( qq (   SSU RNA bases total ... ) );
    
#     $query = qq (select sum(length) from rna_molecule where tax_id = TAX_ID);

#     $stats = &Taxonomy::Stats::create_stats( $dbh, $nodes, $query );
#     &Taxonomy::Stats::load_stats( $dbh, "rRNA_18S_0", "rna_bases", $stats );

#     $root = &Taxonomy::Nodes::get_node_root( $nodes );
#     $count = $root->{"sum"} || 0 + $root->{"value"} || 0;
#     $count = &Common::Util::commify_number( $count );

#     &echo_green( "$count\n" );

#     return;
# }

sub update_nodes
{
    # Niels Larsen, November 2005.

    # Updates taxonomy statistics with the number of organisms under
    # each node and returns a list of lists that in format matches the 
    # schema. 

    my ( $dbh,         # Database handle
         $nodes,       # Nodes hash
         ) = @_;

    # Returns nothing. 

    my ( $tax_id, $value, $node, $sum, @stats, $subref, $argref );

    $subref = sub
    {
        my ( $nodes, $nid ) = @_;
        my ( $p_id );

        if ( &Taxonomy::Nodes::is_leaf( $nodes->{ $nid } ) )
        {
            $nodes->{ $nid }->{"value"} = 1;
            $nodes->{ $nid }->{"sum"} = 1;
        }
        else {
            $nodes->{ $nid }->{"value"} = 0;
        }
        
        if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
        {
            $nodes->{ $p_id }->{"sum"} += $nodes->{ $nid }->{"sum"};
        }
    };
    
    $argref = [];
    
    &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

    foreach $node ( &Taxonomy::Nodes::get_nodes_all( $nodes ) )
    {
        $tax_id = &Taxonomy::Nodes::get_id( $node );

        $value = &Taxonomy::Nodes::get_key( $node, "value" );
        $sum = &Taxonomy::Nodes::get_key( $node, "sum" );

        if ( $sum or $value )
        {
            push @stats, [ $tax_id, $value || 0, $sum || 0, "" ];
        }
    }

    return wantarray ? @stats : \@stats;
}

1;


__END__

sub update_all
{
    # Niels Larsen, September 2003.

    # Updates the taxonomy statistics in the database. It can update 
    # one type of statistics at a time, or all at once. The type of 
    # statistic is given as keys of a hash (the first argument).

    my ( $wants,       # Wanted statistics types
         $readonly,    # Readonly toggle
         ) = @_;

    # Returns nothing.

    my ( $key, $schema, $nodes, $dbh, $query, $stats, $db_file, $db_table,
         @tax_ids, $tax_id, $row, $i, $inputdb, $objtype, $datatype, $count,
         $evstr );

    $db_file = "$Common::Config::tmp_dir/Taxonomy/stats.tab";
    $db_table = "tax_stats";
    
    $dbh = &Common::DB::connect();

    # --------- Set every option to 1 if "all" given,

    if ( $wants->{"all"} ) {
        $wants = { map { $_, 1 } keys %{ $wants } };
    }
    
    # --------- Get all taxonomy nodes into memory,

    &echo( qq (   Fetching taxonomy skeleton ... ) );

    $nodes = &Taxonomy::DB::build_taxonomy( $dbh, "tax_id,parent_id,nmin,nmax" );

    &echo_green( "done\n" );

    # --------- Update one or more types of statistics,
    
    if ( $wants->{"taxonomy"} )
    {
        &echo( qq (   Taxonomy nodes total ... ) );

        $stats = &Taxonomy::Stats::update_nodes( $dbh, $nodes );
        $count = &Taxonomy::Stats::load_stats( $dbh, "NCBI", "orgs_taxa", $stats );

        $count = &Common::Util::commify_number( $count );
        &echo_green( "$count\n" );
    }

    if ( $wants->{"dna"} )
    {
        &echo( qq (   DNA related counts (patience) ... ) );
        &Taxonomy::Stats::update_dna( $dbh, $nodes, $stats, $readonly );
        &echo_green( "done\n" );
    }

    if ( $wants->{"ssu_rna"} )
    {
        &Taxonomy::Stats::update_ssu_rna( $dbh, $nodes );
    }

    if ( $wants->{"protein"} )
    {
        &echo( qq (   SEED protein counts (patience) ... ) );
        &Taxonomy::Stats::update_fig( $dbh, $nodes, $stats, $readonly );
        &echo_green( "done\n" );
    }

    if ( $wants->{"go"} )
    {
        &echo( qq (   GO term counts (patience) ... ) );
        &Taxonomy::Stats::update_go( $dbh, $nodes, $stats, $readonly );
        &echo_green( "done\n" );
    }

    if ( $wants->{"gold"} )
    {
        &echo( qq (   GOLD organism counts ... ) );
        &Taxonomy::Stats::update_gold( $dbh, $nodes, $stats, $readonly );
        &echo_green( "done\n" );
    }

    # --------- Save to file, load updated statistics, clean up,

    &Common::DB::disconnect( $dbh );

    return;
}

# sub create_sim_stats_distrib
# {
#     # Niels Larsen, December 2005.

#     # Maps a given list of similarities (of the form defined by the 
#     # user_sims schema) to the taxonomy. The output is a table of 
#     # mappings as defined by the tax_stats schema. 

#     my ( $udbh,        # User database handle
#          $jid,
#          $sims,        # Similarities table
#          $objtype,     
#          $datatype,     # Molecule type, "rna", "protein", "dna"
#          ) = @_;

#     # Returns a list. 

#     my ( $dbh, $nodes, $pcts, $sql, $tuple, $rna_id, $tax_id, $node, 
#          $pct, $idstr, $i, $subref, $stats, $dist, $str, $max, $minpct,
#          $distlen, $inputdb, $distrib );
    
#     # Include PDL. This is tricky: like bioperl, PDL relies on 
#     # warnings and doesnt catch them all. This package in turn 
#     # converts warnings into fatals, because there should never
#     # be an unhandled warning. So we must suspend this idea 
#     # while PDL loads:

#     {
#         local $SIG{__DIE__};
    
#         require PDL;
#     }

#     # Get all taxonomy nodes,

#     $dbh = &Common::DB::connect();

#     $nodes = &Taxonomy::DB::get_nodes_all( $dbh, "tax_id,parent_id" );
#     $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes, 1 );

#     # Attach similarity distributions like [ 0,0,0,12,5,0, .. ] to the 
#     # leaves where a molecule matches,
    
#     $pcts = { map { $_->[2], $_->[3] } @{ $sims } };
#     $idstr = "'". (join "','", map { $_->[2] } @{ $sims }) ."'";

#     $sql = qq (select tax_id,rna_id from rna_organism where rna_id in ( $idstr) );

#     foreach $tuple ( @{ &Common::DB::query_array( $dbh, $sql ) } )
#     {
#         ( $tax_id, $rna_id ) = @{ $tuple };

#         if ( $pct = $pcts->{ $rna_id } )
#         {
#             $node = $nodes->{ $tax_id };
#             $node->{"distrib"} = PDL->zeroes( 100 ) if not defined $node->{"distrib"};
                
#             $node->{"distrib"}->slice( (int $pct) - 1 ) += 1;
#         }
#         else {
#             &error( qq (Molecule id without percentage -> "$rna_id") );
#             exit;
#         }
#     }

#     # Accumulate similarity distributions at all parents,

#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $pct, $distrib, $p_node, $i );
        
#         # This conditional is necessary because NCBI frequently posts nodes
#         # with no parent and they will not fix it; they say it is not an error. 
        
#          if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#          {
#              $distrib = $nodes->{ $nid }->{"distrib"};

#              if ( defined $distrib )
#              {
#                  $p_node = $nodes->{ $p_id };
#                  $p_node->{"distrib"} = PDL->zeroes( 100 ) if not defined $node->{"distrib"};

#                  $p_node->{"distrib"} = $p_node->{"distrib"} + $distrib;
#              }
#          }
#     };

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref );

#     # Create tax_stats table,

#     $stats = [];

#     $inputdb = &Taxonomy::DB::get_numeric_id( $dbh, "tax_src_dbs", "EMBL" );
#     $objtype = &Taxonomy::DB::get_numeric_id( $dbh, "tax_obj_types", $objtype );
#     $datatype = &Taxonomy::DB::get_numeric_id( $dbh, "tax_data_types", $datatype );

#     foreach $tax_id ( &Taxonomy::Nodes::get_ids_all( $nodes ) )
#     {
#         $node = $nodes->{ $tax_id };
        
#         if ( exists $node->{"distrib"} )
#         {
#             $distrib = $node->{"distrib"};

#             $max = ( which $distrib )->at( -1 );

#             push @{ $stats }, [ $tax_id, $jid, $inputdb, $objtype, $datatype, $max, "", "" ];
#         }
#     }

#     &Common::DB::disconnect( $dbh );

#     return wantarray ? @{ $stats } : $stats;
# }

sub create_lock
{
    # Niels Larsen, July 2003.

    # Creates a Taxonomy/Import subdirectory under the configured scratch
    # directory. The existence of this directory means EMBL data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::tmp_dir/Taxonomy/Stats" );

    return;
}

sub remove_lock
{
    # Niels Larsen, July 2003.
    
    # Deletes a Taxonomy/Import subdirectory from the configured scratch
    # directory. Errors are thrown if the directory is not empty or if
    # it could not be deleted. 

    # Returns nothing. 

    my $lock_dir = "$Common::Config::tmp_dir/Taxonomy/Stats";

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
    # Niels Larsen, July 2003.

    # Checks if there is an Taxonomy/Import subdirectory under the scratch
    # directory of the system. 

    # Returns nothing.

    my $lock_dir = "$Common::Config::tmp_dir/Taxonomy/Stats";

    if ( -e $lock_dir ) {
        return 1;
    } else {
        return;
    }
}

# sub update_go
# {
#     # Niels Larsen, January 2004.

#     # Updates taxonomy statistics with 1) the number of GO terms that 
#     # have been assigned to a given organism, 2) the number of unique
#     # go terms for all organisms under the subtree that starts at a 
#     # given taxonomy id and 3) the total number of terms for a given
#     # subtree.

#     my ( $dbh,         # Database handle
#          $nodes,       # Nodes hash
#          $stats,       # Statistics table
#          $readonly,    # Readonly flag
#          ) = @_;

#     # Returns nothing. 

#     my ( @goids, @taxids, $col_ndx, $row, $tax_id_ndx, $subref, $argref, $sql, 
#          $tax_id, $stats_schema, $type, $tax_str );

#     $stats_schema = &Taxonomy::Schema::relational()->{"tax_stats"};

#     # ------ Number of GO terms assigned to a node,

#     foreach $tax_id ( keys %{ $nodes } )
#     {
#         $sql = qq (select distinct go_id from go_genes_tax where tax_id = $tax_id);
#         @goids = &Common::DB::query_array( $dbh, $sql );
        
#         if ( @goids )
#         {
#             $nodes->{ $tax_id }->{"go_terms_node"} = scalar @goids;
#             $nodes->{ $tax_id }->{"go_orgs_node"} = 1;
#         }
#         else
#         {
#             $nodes->{ $tax_id }->{"go_terms_node"} = 0;
#             $nodes->{ $tax_id }->{"go_orgs_node"} = 0;
#         }
#     }

#     # ------ Number of unique GO terms for each node,

#     foreach $tax_id ( keys %{ $nodes } )
#     {
#         if ( &Taxonomy::Nodes::is_leaf( $nodes->{ $tax_id } ) )
#         {
#             @taxids = ( $tax_id );
#         }
#         else
#         {
#             @taxids = &Taxonomy::Nodes::get_ids_subtree( $nodes, $tax_id );
#             push @taxids, $tax_id;
#         }

#         $tax_str = join ",", @taxids;
#         $sql = qq (select distinct go_id from go_genes_tax where tax_id in ( $tax_str ));

#         @goids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

#         if ( @goids ) {
#             $nodes->{ $tax_id }->{"go_terms_usum"} = scalar @goids;
#         } else {
#             $nodes->{ $tax_id }->{"go_terms_usum"} = 0;
#         }
#     }        

#     # ------ The total number of GO terms and organisms for a given subtree,

#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $count, $sum_count );

#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             $count = $nodes->{ $nid }->{"go_terms_node"} || 0;
#             $nodes->{ $nid }->{"go_terms_tsum"} += $count;

#             $sum_count = $nodes->{ $nid }->{"go_terms_tsum"} || 0;
#             $nodes->{ $p_id }->{"go_terms_tsum"} += $sum_count;

#             $count = $nodes->{ $nid }->{"go_orgs_node"} || 0;
#             $nodes->{ $nid }->{"go_orgs_tsum"} += $count;

#             $sum_count = $nodes->{ $nid }->{"go_orgs_tsum"} || 0;
#             $nodes->{ $p_id }->{"go_orgs_tsum"} += $sum_count;
#         }
#     };

#     $argref = [];

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

#     # ------ Insert the numbers in memory copy of statistics table,

#     $tax_id_ndx = &Common::Schema::field_index( $stats_schema, "tax_id" );

#     foreach $type ( "go_orgs_node", "go_orgs_tsum", "go_terms_node", "go_terms_usum", "go_terms_tsum" )
#     {
#         $col_ndx = &Common::Schema::field_index( $stats_schema, $type );

#         foreach $row ( @{ $stats } )
#         {
#             $tax_id = $row->[ $tax_id_ndx ];
#             $row->[ $col_ndx ] = $nodes->{ $tax_id }->{ $type } || 0;
#         }
#     }

#     return wantarray ? @{ $stats } : $stats;
# }     

# sub update_gold
# {
#     # Niels Larsen, August 2003.

#     # Updates taxonomy statistics with 1) the number of GOLD-listed organisms
#     # under each node, 2) the GOLD-id of the organisms that have the same 
#     # taxonomy id as a given GOLD-organism. We could have normalized this out,
#     # but as time goes the saving gets smaller. 

#     my ( $dbh,         # Database handle
#          $nodes,       # Nodes hash
#          $stats,       # Node hashes 
#          $readonly,    # Readonly flag
#          ) = @_;

#     # Returns nothing. 

#     my ( $gold, @ids, $id, $col_ndx, $col_name, $i, $col, $row, $tax_id_ndx,
#          $subref, $argref, $sql, $gold_hash, $gold_stats, 
#          $entry, $tax_id, $tax_schema, $stats_schema );

#     $stats_schema = &Taxonomy::Schema::relational()->{"tax_stats"};

#     # --------- Attach number of GOLD projects that map to each taxonomy node,

#     $sql = qq (select * from gold_main);
#     $gold_hash = &Common::DB::query_hash( $dbh, $sql, "id" );

#     # Create hash that gives the number of gold organisms for every 
#     # taxonomy id, and those that are complete and published,

#     foreach $id ( keys %{ $gold_hash } )
#     {
#         $entry = $gold_hash->{ $id };
#         $tax_id = $entry->{"tax_id_auto"};

#         $gold_stats->{ $tax_id }->{"gold_orgs_node"}++;

#         if ( $entry->{"status"} =~ /^\s*complete\s*/i ) {
#             $gold_stats->{ $tax_id }->{"gold_orgs_cpub_node"}++;
#         }
#     }

#     # --------- Transfer these numbers to taxonomy nodes (needed below),

#     foreach $tax_id ( keys %{ $nodes } )
#     {
#         $nodes->{ $tax_id }->{"gold_orgs_node"} = $gold_stats->{ $tax_id }->{"gold_orgs_node"} || 0;
#         $nodes->{ $tax_id }->{"gold_orgs_cpub_node"} = $gold_stats->{ $tax_id }->{"gold_orgs_cpub_node"} || 0;
#     }

#     # --------- Add these numbers to memory copy of database-ready table,

#     $tax_id_ndx = &Common::Schema::field_index( $stats_schema, "tax_id" );
#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs_node" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $gold_stats->{ $tax_id }->{ "gold_orgs_node" } || 0;
#     }

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs_cpub_node" );
        
#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $gold_stats->{ $tax_id }->{ "gold_orgs_cpub_node" } || 0;
#     }
    
#     # --------- Sum up tree node counts,

#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $count, $sum_count );

#         # It is necessary to check if nodes actually have parents, because NCBI 
#         # frequently posts nodes with no parent and will not fix it; they say 
#         # it is not an error. Geez.
        
#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             $count = $nodes->{ $nid }->{"gold_orgs_node"} || 0;
#             $nodes->{ $nid }->{"gold_orgs_tsum"} += $count;

#             $sum_count = $nodes->{ $nid }->{"gold_orgs_tsum"} || 0;
#             $nodes->{ $p_id }->{"gold_orgs_tsum"} += $sum_count;

#             $count = $nodes->{ $nid }->{"gold_orgs_cpub_node"} || 0;
#             $nodes->{ $nid }->{"gold_orgs_cpub_tsum"} += $count;

#             $sum_count = $nodes->{ $nid }->{"gold_orgs_cpub_tsum"} || 0;            
#             $nodes->{ $p_id }->{"gold_orgs_cpub_tsum"} += $sum_count;
#         }
#     };

#     $argref = [];

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

#     # ---------- Add numbers to memory copy of database-ready table,

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs_tsum" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $nodes->{ $tax_id }->{"gold_orgs_tsum"} || 0;
#     }

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs_cpub_tsum" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $nodes->{ $tax_id }->{"gold_orgs_cpub_tsum"} || 0;
#     }

#     return wantarray ? @{ $stats } : $stats;
# }

# sub update_gold
# {
#     # Niels Larsen, August 2003.

#     # Updates taxonomy statistics with 1) the number of GOLD-listed organisms
#     # under each node, 2) the GOLD-id of the organisms that have the same 
#     # taxonomy id as a given GOLD-organism. We could have normalized this out,
#     # but as time goes the saving gets smaller. 

#     my ( $dbh,         # Database handle
#          $nodes,       # Nodes hash
#          $stats,       # Node hashes 
#          $readonly,    # Readonly flag
#          ) = @_;

#     # Returns nothing. 

#     my ( $gold, @ids, $id, $col_ndx, $col_name, $i, $col, $row, $tax_id_ndx,
#          $subref, $argref, $sql, $gold_hash, $gold_stats, 
#          $entry, $tax_id, $tax_schema, $stats_schema );

#     $stats_schema = &Taxonomy::Schema::relational()->{"tax_stats"};

#     # --------- Attach number of GOLD projects that map to each taxonomy node,

#     $sql = qq (select * from gold_main);
#     $gold_hash = &Common::DB::query_hash( $dbh, $sql, "tax_id" );

#     # Create hash that gives the number of gold organisms for every 
#     # taxonomy id,

#     foreach $id ( keys %{ $gold_hash } )
#     {
#         $entry = $gold_hash->{ $id };
#         $tax_id = $entry->{"tax_id_auto"};

#         $gold_stats->{ $tax_id }->{"gold_orgs"}++;

#         if ( $entry->{"status"} =~ /^\s*complete\s*/i ) {
#             $gold_stats->{ $tax_id }->{"gold_orgs_cpub"}++;
#         }
#     }

#     # Transfer the numbers to taxonomy nodes (needed below),

#     foreach $tax_id ( keys %{ $nodes } )
#     {
#         $nodes->{ $tax_id }->{"gold_orgs"} = $gold_stats->{ $tax_id }->{"gold_orgs"} || 0;
#         $nodes->{ $tax_id }->{"gold_orgs_cpub"} = $gold_stats->{ $tax_id }->{"gold_orgs_cpub"} || 0;
#     }

#     $tax_id_ndx = &Common::Schema::field_index( $stats_schema, "tax_id" );

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs" );
        
#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $gold_stats->{ $tax_id }->{ "gold_orgs" } || 0;
#     }

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs_cpub" );
        
#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $gold_stats->{ $tax_id }->{ "gold_orgs_cpub" } || 0;
#     }
    
#     # --------- Sum up tree node counts,

#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id );

#         # It is necessary to check if nodes actually have parents, because NCBI 
#         # frequently posts nodes with no parent and will not fix it; they say 
#         # it is not an error. Geez.
        
#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             if ( $nodes->{ $nid }->{"gold_orgs"} ) {
#                 $nodes->{ $p_id }->{"gold_orgs_node"} += $nodes->{ $nid }->{"gold_orgs"} || 0;
#             }
            
#             if ( $nodes->{ $nid }->{"gold_orgs_cpub"} ) {
#                 $nodes->{ $p_id }->{"gold_orgs_cpub_node"} += $nodes->{ $nid }->{"gold_orgs_cpub"} || 0;
#             }
            
#             $nodes->{ $p_id }->{"gold_orgs_node"} += $nodes->{ $nid }->{"gold_orgs_node"} || 0;
#             $nodes->{ $p_id }->{"gold_orgs_cpub_node"} += $nodes->{ $nid }->{"gold_orgs_cpub_node"} || 0;
#         }
#     };

#     $argref = [];

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs_node" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $nodes->{ $tax_id }->{"gold_orgs_node"} || 0;
#     }

#     $col_ndx = &Common::Schema::field_index( $stats_schema, "gold_orgs_cpub_node" );

#     foreach $row ( @{ $stats } )
#     {
#         $tax_id = $row->[ $tax_id_ndx ];
#         $row->[ $col_ndx ] = $nodes->{ $tax_id }->{"gold_orgs_cpub_node"} || 0;
#     }

#     return wantarray ? @{ $stats } : $stats;
# }     


# sub update_fig
# {
#     # Niels Larsen, August 2003.

#     # Updates taxonomy statistics with 1) the number of organisms that have 
#     # fig proteins, 2) the total number of orfs. 

#     my ( $dbh,         # Database handle
#          $nodes,       # Nodes hash
#          $stats,       # Statistics table
#          $readonly,    # Readonly flag
#          ) = @_;

#     # Returns nothing. 

#     my ( @ids, $col_ndx, $row, $tax_id_ndx, $subref, $argref, $sql, 
#          $tax_id, $stats_schema, $type,  );

#     $stats_schema = &Taxonomy::Schema::relational()->{"tax_stats"};

#     # ------ Query number of organisms and proteins for each node,

#     foreach $tax_id ( keys %{ $nodes } )
#     {
#         $sql = qq (select id,tax_ids from fig_annotation where tax_id = $tax_id);
#         @ids = &Common::DB::query_array( $dbh, $sql );
        
#         if ( @ids )
#         {
#             $nodes->{ $tax_id }->{"fig_orgs_node"} = $ids[0]->[1];
#             $nodes->{ $tax_id }->{"fig_prots_node"} = scalar @ids;
#         }
#         else
#         {
#             $nodes->{ $tax_id }->{"fig_orgs_node"} = 0;
#             $nodes->{ $tax_id }->{"fig_prots_node"} = 0;
#         }
#     }

#     # ------ Add sums for parent nodes to the nodes,

#     $subref = sub
#     {
#         my ( $nodes, $nid ) = @_;
#         my ( $p_id, $count, $sum_count );

#         # It is necessary to check if nodes actually have parents, because NCBI 
#         # frequently posts nodes with no parent and will not fix it; they say 
#         # it is not an error. Geez.
        
#         if ( $p_id = $nodes->{ $nid }->{"parent_id"} )
#         {
#             $count = $nodes->{ $nid }->{"fig_orgs_node"} || 0;
#             $nodes->{ $nid }->{"fig_orgs_tsum"} += $count;

#             $sum_count = $nodes->{ $nid }->{"fig_orgs_tsum"} || 0;
#             $nodes->{ $p_id }->{"fig_orgs_tsum"} += $sum_count;

#             $count = $nodes->{ $nid }->{"fig_prots_node"} || 0;
#             $nodes->{ $nid }->{"fig_prots_tsum"} += $count;

#             $sum_count = $nodes->{ $nid }->{"fig_prots_tsum"} || 0;
#             $nodes->{ $p_id }->{"fig_prots_tsum"} += $sum_count;
#         }
#     };

#     $argref = [];

#     &Taxonomy::Nodes::tree_traverse_tail( $nodes, 1, $subref, $argref );

#     # ------ Insert the numbers in memory copy of statistics table,

#     $tax_id_ndx = &Common::Schema::field_index( $stats_schema, "tax_id" );

#     foreach $type ( "fig_orgs_node", "fig_orgs_tsum", "fig_prots_node", "fig_prots_tsum" )
#     {
#         $col_ndx = &Common::Schema::field_index( $stats_schema, $type );

#         foreach $row ( @{ $stats } )
#         {
#             $tax_id = $row->[ $tax_id_ndx ];
#             $row->[ $col_ndx ] = $nodes->{ $tax_id }->{ $type } || 0;
#         }
#     }

#     return wantarray ? @{ $stats } : $stats;
# }
