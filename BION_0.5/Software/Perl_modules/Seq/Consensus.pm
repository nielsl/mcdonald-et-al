package Seq::Consensus;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that work with consenses sequences in some way.
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( *AUTOLOAD );
use Data::MessagePack;

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &cluster_table
                 &cluster_table_args
                 &create_pool
                 &create_pool_args
                 &create_pool_fasta
                 &create_scale_dict
                 &create_table
                 &create_table_args
                 &create_table_store
                 &init_map_stats
                 &match_pool
                 &match_pool_args
                 &match_pool_exact
                 &match_pool_sim
                 &sort_paths
                 &table_stats
                 &write_clu_pool
                 &write_clu_stats 
                 &write_map_stats 
);

use Common::Config;
use Common::Messages;
use Common::Table;
use Common::Tables;

use Registry::Args;
use Registry::Paths;

use Seq::IO;
use Seq::Args;
use Seq::Storage;
use Seq::Match;
use Seq::Cluster;

use Ali::Storage;
use Ali::Consensus;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub cluster_table
{
    # Niels Larsen, December 2011. 
    
    # Compacts the output table made with seq_pool_map, by clustering the 
    # sequences while adding up the counts. Ambiguity codes are inserted by 
    # default to indicate mismatches when clustered by less than 100%.

    my ( $args,
        ) = @_;

    # Returns nothing. 

    my ( $defs, $conf, $seq, $tmp_dir, $sfh, $id, $dbh, $seq_file, $stats,
         $tab_store, $i_table, $o_table, $ali_file, $ali, $afh, $bad_ids, 
         @msgs, $ofh, $count, $clobber, $total, $mpack, $col_hdrs, $row, $col, 
         @sums, $sum, $rows, $recipe, @table, $in_stats, $out_stats, 
         $time_start, @col_hdrs, $table, @col_tots );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "itable" => undef,
        "method" => "ambig",
        "minlen" => 15,
        "minseqs" => 1,
        "minsim" => 95,
        "minres" => 0,
        "ambcover" => 90,
        "otable" => undef,
        "osuffix" => ".clu",
        "ofasta" => undef,
        "ostats" => undef,
        "sort" => 1,
        "clobber" => 0,
        "silent" => 0,
        "clean" => 1,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Consensus::cluster_table_args( $args );

    $i_table = $conf->itable;
    $o_table = $conf->otable;

    $tmp_dir = "$i_table.workdir";

    $Common::Messages::silent = $args->silent;
    $clobber = $args->clobber;

    &Common::File::delete_dir_tree_if_exists( $tmp_dir );
    &Common::File::create_dir_if_not_exists( $tmp_dir );

    $time_start = &Common::Messages::time_start();

    &echo_bold( "\nClustering match table:\n" );

    # # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ INPUT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # &echo("   Reading input table ... ");

    # $i_table = &Common::Table::read_table( $conf->itable );
    # $count = $i_table->row_count;

    # &echo_done("$count\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> INPUT TABLE STATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $conf->ostats )
    {
        &echo("   Summing input totals ... ");
        $in_stats = &Seq::Consensus::table_stats( $i_table );
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLUSTERING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Clustering sequences ... ");

    $seq_file = "$tmp_dir/cons.fasta";
    $ali_file = "$tmp_dir/cons.fasta.cluali";
    
    &Seq::IO::write_table_seqs( $i_table, $seq_file );

    &Seq::Cluster::cluster(
        bless {
            "recipe" => undef,
            "iseqs" => $seq_file,
            "ofasta" => undef,
            "oalign" => $ali_file,
            "cluprog" => "uclust",
            "minsim" => $conf->minsim,
            "minsize" => 1,
            "clobber" => 0,
            "silent" => 1,
        });

    &Common::File::delete_file( $seq_file );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> CONSENSUS EXTRACTION <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Extracting consenses ... ");

    &Ali::Consensus::consenses(
        bless {
            "recipe" => undef,
            "ifile" => $ali_file,
            "seqtype" => "dna",
            "ofasta" => "$ali_file.fasta",
            "method" => $conf->method,
            "minlen" => $conf->minlen,
            "minseqs" => $conf->minseqs,
            "minres" => $conf->minres,
            "ambcover" => $conf->ambcover,
            "trimbeg" => 0,
            "trimend" => 0,
            "silent" => 1,
        });

    &echo_done("done\n");

    # # >>>>>>>>>>>>>>>>>>>>>>>>>> TABLE STORE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Index consensus table ... ");

    $tab_store = "$tmp_dir/cons.table.fetch";
    
    &Seq::Consensus::create_table_store( $i_table, $tab_store, ["ID","Total","Totpct","Sequence"] );
    
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Summing up counts ... ");

    $seq_file = "$ali_file.fasta";

    $sfh = &Common::File::get_read_handle( $seq_file );
    $afh = &Ali::Storage::get_handles( $ali_file, { "access" => "read" } );
    $dbh = &Common::DBM::read_open( $tab_store );

    $mpack = Data::MessagePack->new();

    $bad_ids = [];
    @table = ();

    while ( $seq = &Seq::IO::read_seq_fasta( $sfh ) )
    {
        $ali = &Ali::Storage::fetch_aliseq( $afh, $seq->{"id"}, $bad_ids, \@msgs );
        $ali = &Ali::Common::parse_uclust( $ali );

        @sums = ();
        $rows = &Common::DBM::get_bulk( $dbh, $ali->sids );

        foreach $id ( keys %{ $rows } )
        {
            $row = $mpack->unpack( $rows->{ $id } );
            
            for ( $col = 0; $col <= $#{ $row }; $col++ )
            {
                $sums[$col] += $row->[$col];
            }
        }

        $total = &Seq::Common::parse_info( $seq )->seq_count;
        
        push @table, [ $seq->{"id"}, @sums, $total, $seq->{"seq"} ];
    }
    
    &Common::DBM::close( $dbh );
    &Ali::Storage::close_handles( $afh );
    &Common::File::close_handle( $sfh );

    $count = scalar @table;
    &echo_done("$count rows\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Writing output table ... ");

    # Sort by totals,

    @table = sort { $b->[-2] <=> $a->[-2] } @table;
    
    # Add cumulative percentages,

    $sum = &List::Util::sum( map { $_->[-2] } @table );
    $total = 0;

    foreach $row ( @table )
    {
        $total += $row->[-2];
        splice @{ $row }, -1, 0, sprintf "%.3f", 100 * $total / $sum;
    }

    # Write,

    $col_hdrs = &Common::File::read_lines( $i_table, 1 )->[0];
    chomp $col_hdrs;

    @col_hdrs = split "\t", $col_hdrs;
    $col_hdrs[0] =~ s/^#//;
    splice @col_hdrs, -1, 0, "Totpct" unless grep { $_ eq "Totpct" } @col_hdrs;

    $table = &Common::Table::new( \@table, {"col_headers" => \@col_hdrs });

    # Add column totals, 

    @col_hdrs = grep { $_ !~ /^\s*(ID|Sequence|Totpct)\s*$/ } @col_hdrs;

    @col_tots = &Common::Table::sum_cols( $table, [ @col_hdrs ] );
    @col_tots = map { int $_ } @col_tots;

    unshift @{ $table->values }, [ "#", @col_tots, "", "Column totals" ];

    &Common::Table::write_table( $table, $o_table, {"clobber" => $clobber});

    &echo_done("$count rows\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FASTA CONSENSES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $conf->ofasta )
    {
        &echo("   Writing sequences ... ");

        $ofh = &Common::File::get_write_handle( $conf->ofasta, "clobber" => $clobber );

        foreach $row ( @table )
        {
            $ofh->print(">$row->[0]\n$row->[-1]\n");
        }

        &Common::File::close_handle( $ofh );
        
        &echo_done("$count\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT TABLE STATS <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $conf->ostats )
    {
        &echo("   Summing output statistics ... ");
        $out_stats = &Seq::Consensus::table_stats( $o_table );
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLEANING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->clean )
    {
        &echo("   Removing temporary files ... ");
        &Common::File::delete_dir_tree_if_exists( $tmp_dir );
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->ostats )
    {
        &echo("   Writing statistics ... ");

        $stats->{"name"} = $recipe->{"name"} // "consensus-table-clustering";
        $stats->{"title"} = $recipe->{"title"} // "Consensus table clustering";
        
        $stats->{"itable"} = &File::Basename::basename( $conf->itable );
        $stats->{"otable"} = &File::Basename::basename( $conf->otable );
        $stats->{"ofasta"} = &File::Basename::basename( $conf->ofasta );
        
        $stats->{"method"} = $conf->method;
        
        $stats->{"params"} = [
            {
                "title" => "Minimum consensus similarity",
                "value" => $conf->minsim,
            },{
                "title" => "Minimum consensus length",
                "value" => $conf->minlen,
            },{
                "title" => "Minimum reads across samples",
                "value" => $conf->minseqs,
            },{
                "title" => "Minimum residues per column",
                "value" => $conf->minres,
            },{
                "title" => "Minimum ambiguity coverage",
                "value" => $conf->ambcover,
            }];
    
        $stats->{"seqs_in"} = $in_stats->{"seqs"};
        $stats->{"origs_in"} = $in_stats->{"origs"};
        $stats->{"seqs_out"} = $out_stats->{"seqs"};
        $stats->{"origs_out"} = $out_stats->{"origs"};
        
        $stats->{"seconds"} = time() - $time_start;
        $stats->{"finished"} = &Common::Util::epoch_to_time_string();
    
        &Seq::Consensus::write_clu_stats( $args->ostats, $stats );

        &echo_done("done\n");
    }

    &echo_bold( "Finished\n\n" );

    return;
}
    
sub cluster_table_args
{
    # Niels Larsen, December 2011. 

    my ( $args,
        ) = @_;

    my ( @msgs, $method, %args );

    # Input files must be readable,

    if ( defined $args->itable ) {
	$args{"itable"} = ( &Common::File::check_files( [ $args->itable ], "efr", \@msgs ) )[0];
    } else {
        push @msgs, ["ERROR", qq (No input table file given) ];
    }

    $method = $args->method // "least_ambiguous";

    if ( $method =~ /^most_frequent|least_ambiguous$/i )
    {
        $args{"method"} = lc $method;
    }
    else {
        push @msgs, ["ERROR", qq (Wrong looking method -> "$method", must be "least_ambiguous" or "most_frequent") ];
    }
    
    # Input read count and lengths, check values,

    $args{"minlen"} = &Registry::Args::check_number( $args->minlen, 15, undef, \@msgs );
    $args{"minseqs"} = &Registry::Args::check_number( $args->minseqs, 0, undef, \@msgs );
    $args{"minsim"} = &Registry::Args::check_number( $args->minsim, 50, 100, \@msgs );
    $args{"minres"} = &Registry::Args::check_number( $args->minres, 0, 100, \@msgs );
    $args{"ambcover"} = &Registry::Args::check_number( $args->ambcover, 0, 100, \@msgs );

    # Table output, use suffix if no explicit file name given,

    if ( $args->otable )
    {
        &Common::File::check_files( [ $args->otable ], "!e", \@msgs ) if not $args->clobber;
        $args{"otable"} = $args->otable;
    }
    elsif ( $args->osuffix ) 
    {
        $args{"otable"} = $args->itable . $args->osuffix;
        &Common::File::check_files( [ $args{"otable"} ], "!e", \@msgs ) if not $args->clobber;
    }
    else {
        push @msgs, ["ERROR", qq (No output table file given) ];
    }

    $args{"ofasta"} = $args->ofasta;

    if ( defined $args->ofasta )
    {
        if ( not $args{"ofasta"} = $args->ofasta ) {
            $args{"ofasta"} = $args->itable . $args->osuffix .".fasta";
        }
    }

    $args{"ostats"} = $args->ostats;
    
    &append_or_exit( \@msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}

sub create_pool
{
    # Niels Larsen, November 2011.

    # Pools and uniqifies consensus sequences from a given set of consensus 
    # files (generated by the ali_consensus program) and write this set to a
    # fasta file. By default all input consenses are included, but a minimum 
    # cluster size can be imposed. It is also controllable how unique the 
    # output sequences should be. Also the ids from a separate fasta file 
    # may be used to label sequences in the extract that are highly similar.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $o_args, $tmp_file, $pool_file, $counts, $pool_args,
         $recipe, $stats, $omin_sim, $time_start, $method );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "ifiles" => [],
        "iminsiz" => 1,
        "iminlen" => 20,
        "method" => "exact",
        "ominsiz" => 2,
        "ominlen" => 20,
        "ominsim" => 100,
        "ominres" => 5,
        "ofasta" => undef,
        "otable" => undef,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Consensus::create_pool_args( $args );

    $method = $conf->method;

    local $Common::Messages::silent = $args->silent;

    $time_start = &Common::Messages::time_start();

    &echo_bold( "\nCreating consensus pool:\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> APPEND INPUTS TO ONE <<<<<<<<<<<<<<<<<<<<<<<<<

    # Gather all consensus sequences from the given files, optionally filtered
    # by minimum cluster size,

    $pool_file = Registry::Paths->new_temp_path( "consenses" );
    $pool_args = {"minsiz" => $conf->iminsiz, "minlen" => $conf->iminlen };
    
    &echo("   Pooling consensus files ... ");
    $counts = &Seq::Consensus::create_pool_fasta( $conf->ifiles, $pool_file, $pool_args );
    &echo_done("done\n");

    $stats->{"seqs_in"} = $counts->{"seqs_in"};
    $stats->{"origs_in"} = $counts->{"origs_in"};
    $stats->{"seqs_pool"} = $counts->{"seqs_out"};
    $stats->{"origs_pool"} = $counts->{"origs_out"};
    
    # >>>>>>>>>>>>>>>>>>>>>>>> COLLAPSE APPENDED INPUTS <<<<<<<<<<<<<<<<<<<<<<<
    
    # Use clustering or simple dereplication,

    if ( $method eq "similar" )
    {
        $omin_sim = $conf->ominsim;

        &echo("   Clustering all with $omin_sim% ... ");
        
        &Seq::Cluster::cluster(
             bless {
                 "recipe" => undef,
                 "iseqs" => $pool_file,
                 "oalign" => "$pool_file.cluali",
                 "cluprog" => "uclust",
                 "maxram" => "80%",
                 "minsim" => $omin_sim,
                 "minsize" => 1,
                 "cluargs" => "--gapopen 10I/0E --gapext 10I/0E",
                 "clobber" => 0,
                 "silent" => 1,
                 "verbose" => 0,
             });
        
        &echo_green( "done\n" );

        &echo("   Extracting new consenses ... ");
        
        &Ali::Consensus::consenses(
             bless {
                 "recipe" => undef,
                 "ifile" => "$pool_file.cluali",
                 "ofasta" => "$pool_file.cluali.fasta",
                 "method" => "most_frequent",
                 "trimbeg" => 0,
                 "trimend" => 0,
                 "minseqs" => 1,
                 "minres" => $conf->ominres,
                 "minlen" => $conf->ominlen,
                 "silent" => 1,
             });
        
        &Common::File::delete_file( "$pool_file.cluali" );
        &Common::File::delete_file_if_exists( "$pool_file.cluali.fetch" );
        
        $tmp_file = "$pool_file.cluali.fasta";

        &echo_done("done\n");
    }
    else
    {
        &echo("   De-replicating all sequences ... ");
        
        &Seq::Storage::create_indices(
             {
                 "ifiles" => [ $pool_file ],
                 "progtype" => "derep",
                 "outfmt" => "fasta",
                 "outsuf" => ".fasta",
                 "stats" => undef,
                 "count" => 1,
                 "silent" => 1,
             });
        
        $tmp_file = "$pool_file.derep.fasta";

        &Common::File::delete_file( "$pool_file.derep" );
        
        &echo_done("done\n");
    };

    &Common::File::delete_file( $pool_file );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Write outputs with sequential numbers as ids while counting sequences and
    # original reads,

    $o_args = { "minsiz" => $conf->ominsiz, "minlen" => $conf->ominlen, "clobber" => $args->clobber };
    
    if ( $conf->ofasta )
    {
        &echo("   Writing fasta pool ... ");

        $o_args->{"code"} = q ($seq->{"id"} = ++$seq_id; &Seq::IO::write_seq_fasta( $ofh, $seq ););
        $counts = &Seq::Consensus::write_clu_pool( $tmp_file, $conf->ofasta, $o_args );

        &echo_done( "$counts->{'seqs_out'} seqs / $counts->{'origs_out'} reads\n" );
    }

    if ( $conf->otable )
    {
        &echo("   Writing table pool ... ");

        $o_args->{"code"} = q ($ofh->print( ++$seq_id ."\t$siz\t". $seq->{"seq"} ."\n" ));
        $counts = &Seq::Consensus::write_clu_pool( $tmp_file, $conf->otable, $o_args );

        &echo_done( "$counts->{'seqs_out'} seqs / $counts->{'origs_out'} reads\n" );
    }

    &Common::File::delete_file( $tmp_file );

    $stats->{"seqs_clu"} = $counts->{"seqs_in"};
    $stats->{"origs_clu"} = $counts->{"origs_in"};
    $stats->{"seqs_out"} = $counts->{"seqs_out"};
    $stats->{"origs_out"} = $counts->{"origs_out"};

    $stats->{"seconds"} = time() - $time_start;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();
    
    &echo("   Time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );
    
    &echo_bold( "Finished\n\n" );

    return wantarray ? %{ $stats } : $stats;
}

sub create_pool_args
{
    # Niels Larsen, November 2011.

    # Checks and expands the dictionary routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, $method, $arg );

    @msgs = ();

    # Input files must be readable,

    if ( defined $args->ifiles and @{ $args->ifiles } ) {
	$args{"ifiles"} = &Common::File::check_files( $args->ifiles, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No fasta input files are given) ];
    }

    # Input read count and lengths, check values,

    $args{"iminsiz"} = &Registry::Args::check_number( $args->iminsiz, 1, undef, \@msgs );
    $args{"iminlen"} = &Registry::Args::check_number( $args->iminlen, 1, undef, \@msgs );

    # Method must be "similar" or "exact",

    $method = $args->method // "exact";

    if ( $method =~ /^similar|exact$/i ) {
        $args{"method"} = lc $method;
    } else {
        push @msgs, ["ERROR", qq (Wrong looking method -> "$method", must be "similar" or "exact") ];
    }

    # Output numeric settings, check they are within range,

    $args{"ominsiz"} = &Registry::Args::check_number( $args->ominsiz, 1, undef, \@msgs );
    $args{"ominlen"} = &Registry::Args::check_number( $args->ominlen, 10, undef, \@msgs );
    $args{"ominsim"} = &Registry::Args::check_number( $args->ominsim, 80, 100, \@msgs );
    $args{"ominres"} = &Registry::Args::check_number( $args->ominres, 0, 100, \@msgs );
    
    # Make sure these output settings are no less than the input settings,

    $args{"ominsiz"} = &List::Util::max( $args{"iminsiz"}, $args{"ominsiz"} );
    $args{"ominlen"} = &List::Util::max( $args{"iminlen"}, $args{"ominlen"} );

    # Either table or fasta output must be asked for,

    if ( not defined $args->ofasta and not defined $args->otable )
    {
        push @msgs, ["ERROR", qq (Either fasta or table output must be asked for, or both.) ];
        &append_or_exit( \@msgs );
    }

    # Given output files may not exist unless clobber,

    foreach $arg ( qw ( ofasta otable ) )
    {
        if ( $args->$arg ) {
            &Common::File::check_files( [ $args->$arg ], "!e", \@msgs ) if not $args->clobber;
        }

        $args{ $arg } = $args->$arg;
    }
    
    &append_or_exit( \@msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}

sub create_pool_fasta
{
    # Niels Larsen, March 2012. 

    # Writes a pool of fasta files into a single file while filtering for length
    # and original read counts. Sequences will have new number-ids to remove id
    # redundancy. 

    my ( $ifiles,
         $ofile,
         $args,
        ) = @_;

    my ( $min_siz, $min_len, $ofh, $seq_id, $ifile, $seqs_in, $origs_in,
         $seqs_out, $origs_out, $seq, $i, $ifh, $counts  );
    
    $min_siz = $args->{"minsiz"};
    $min_len = $args->{"minlen"};

    $ofh = &Common::File::get_write_handle( $ofile );

    $seq_id = 0;

    $seqs_in = 0;
    $origs_in = 0;
    $seqs_out = 0;
    $origs_out = 0;

    foreach $ifile ( @{ $ifiles } )
    {
        $ifh = &Common::File::get_read_handle( $ifile );
        
        while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
        {
            $seqs_in += 1;

            if ( $seq->{"info"} =~ /seq_count=(\d+)/ )
            {
                $i = $1;
                $origs_in += $i;
                
                if ( $i >= $min_siz and length $seq->{"seq"} >= $min_len )
                {
                    $seq->{"id"} = ++$seq_id;
                    $seq->{"info"} = "seq_count=$i";
                    
                    &Seq::IO::write_seq_fasta( $ofh, $seq );
                    
                    $seqs_out += 1;
                    $origs_out += $i;
                }
            }
            else
            {
                $seq->{"id"} = ++$seq_id;
                &Seq::IO::write_seq_fasta( $ofh, $seq );

                $seqs_out += 1;
            }
        }

        &Common::File::close_handle( $ifh );
    }

    &Common::File::close_handle( $ofh );
    
    return {
        "seqs_in" => $seqs_in,
        "seqs_out" => $seqs_out,
        "origs_in" => $origs_in,
        "origs_out" => $origs_out,
    };
}

sub create_scale_dict
{
    # Niels Larsen, November 2011.

    # Creates a hash where key is file path and value is a scale factor. The
    # factor for a given file is the number of times its original read totals
    # is greater than the average between all files. So for below-average 
    # counts the factor will be less than 1, and vice versa. 

    my ( $files,      # List of input dataset files
        ) = @_;
    
    # Returns hash.

    my ( $file, @counts, $avg, %dict, $i );

    foreach $file ( @{ $files } )
    {
        push @counts, &Seq::Stats::count_seq_file( $file )->{"seq_count_orig"};
    }

    $avg = &List::Util::sum( @counts ) / ( scalar @counts );

    for ( $i = 0; $i <= $#{ $files }; $i++ )
    {
        $dict{ $files->[$i] } = $counts[$i] / $avg;
    }

    return wantarray ? %dict : \%dict;
}
    
sub create_table
{
    # Niels Larsen, January 2012. 

    # Creates a table map from a set of consensus files with read counts. A
    # pool is first made which is the union of all sequences, and each file 
    # is mapped against this pool. A table map has one sequence per row, the
    # values are original read counts and each column corresponds to an input
    # file. Read counts are summed up and can be scaled, so the total number
    # of reads for each file are the same. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $recipe, $pool_file, $clu_stats, $map_stats, $stats,
         $time_start, $key, $method, $work_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "ifiles" => [],
        "otable" => undef,
        "ostats" => undef,
        "pmethod" => "exact",
        "iminsiz" => 1,
        "iminlen" => 20,
        "pminsiz" => 1,
        "pminlen" => 20,
        "pminsim" => 100,
        "pminres" => 5,
        "mmethod" => "exact", 
        "mminsiz" => 2,
        "mminlen" => 20,
        "mminsim" => 95,
        "mminres" => 5,
        "scale" => 1,
        "colids" => undef,
        "colfile" => undef,
        "colpat" => undef,
        "clobber" => 0,
        "silent" => 0,
        "verbose" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Consensus::create_table_args( $args );

    local $Common::Messages::silent = $args->silent;    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo_bold("\nConsensus table:\n");

    &echo("   Initializing statistics ... ");
    $stats = &Seq::Consensus::init_map_stats( $recipe, $conf );
    &echo_done("done\n");

    $time_start = &Common::Messages::time_start();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE POOL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Pooling sequences ... ");

    $work_dir = &Common::File::create_workdir( $conf->otable );
    $pool_file = "$work_dir/". &File::Basename::basename( $0 ) .".fasta";

    $clu_stats = &Seq::Consensus::create_pool( 
        bless {
            "recipe" => undef,
            "ifiles" => $conf->ifiles,
            "method" => $conf->pmethod,
            "iminsiz" => $conf->iminsiz,
            "iminlen" => $conf->iminlen,
            "ominsiz" => $conf->pminsiz,
            "ominlen" => $conf->pminlen,
            "ominsim" => $conf->pminsim,
            "ominres" => $conf->pminres,
            "ofasta" => $pool_file,
            "clobber" => $args->clobber,
            "silent" => 1,
        });

    foreach $key ( keys %{ $clu_stats } )
    {
        $stats->{ $key } = $clu_stats->{ $key };
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> MATCH WITH POOL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( -s $pool_file )
    {
        &echo_done("done\n");
        &echo("   Mapping against pool ... ");

        $map_stats = &Seq::Consensus::match_pool( 
             bless {
                 "recipe" => undef,
                 "ifiles" => $conf->ifiles,
                 "pool" => $pool_file,
                 "method" => $conf->mmethod,
                 "simpct" => $conf->mminsim,
                 "scale" => $conf->scale,
                 "colids" => $conf->colids,
                 "colpat" => $conf->colpat,
                 "colfile" => $conf->colfile,
                 "otable" => $conf->otable,
                 "clobber" => $args->clobber,
                 "silent" => 1,
                 "verbose" => 0,
             });

        &Common::File::delete_file( "$pool_file.fetch" );
        &echo_done("done\n");
    }
    else {
        &echo_red("NONE\n");
    }

    &Common::File::delete_workdir( $work_dir );

    $stats->{"seconds"} = time() - $time_start;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->ostats )
    {
        &echo("   Writing statistics ... ");
        &Seq::Consensus::write_map_stats( $args->ostats, $stats );
        &echo_done("done\n");
    }

    &echo("   Time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );
    
    &echo_bold("Finished\n\n");

    return;
}

sub create_table_args
{
    # Niels Larsen, January 2012.

    # Checks and expands the match routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, $file, $dir, @files, $count, @ids, $id, $colids, $colpat, 
         $i, $j, @lines, $method, $basename, $tags, $title );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CHECK INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->ifiles )
    {
        if ( @{ $args->ifiles } ) {
            $args{"ifiles"} = &Common::File::check_files( $args->ifiles, "efr", \@msgs );
        } else {
            $args{"ifiles"} = &Seq::Args::expand_file_paths( $args->ifiles, \@msgs );
        }
    }
    else {
        push @msgs, ["ERROR", qq (No fasta sequence files are given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> MAKE COLUMN LABELS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # There are three ways to specify table column titles:
    #
    # 1. Give a file of ids, in barcode file format. These ids will be use to 
    #    sort the file names with. The ID, F-Tag and R-tag columns that match 
    #    file names best are used. This option makes the columns appear in the
    #    same order as the ids in the file. 
    # 
    # 2. Give ids on the command line. This merely attaches ids to each file.
    #    Number of IDs and files must match and column order is not changed.
    # 
    # 3. Give a pattern. This pattern must match all file names and the sub-
    #    pattern within parantheses is used for column id. Column order is not
    #    changed. 

    @ids = ();

    $colids = $args->colids;
    $colpat = $args->colpat;

    if ( $args->colfile )
    {
        # Change order 

        $tags = &Seq::IO::read_table_tags( $args->colfile );
        
        foreach $title ( @Seq::IO::Bar_titles )
        {
            if ( grep { exists $_->{ $title } } @{ $tags } ) {
                @ids = map { $_->{ $title } } @{ $tags };
            } else {
                next;
            }

            @msgs = ();

            if ( @files = &Seq::Consensus::sort_paths( $args{"ifiles"}, \@ids, \@msgs ) )
            {
                $args{"ifiles"} = \@files;
                last;
            }
        }
    }
    elsif ( $colids or $colpat )
    {
        # No change of order
        
        if ( $colids and $colpat ) 
        {
            push @msgs, ["ERROR", qq (Pattern and ID list are mutually exclusive arguments) ];
        }
        elsif ( $colids )
        {
            @ids = split /\s*,\s*/, $colids;
        }
        elsif ( $colpat )
        {
            for ( $i = 0; $i <= $#{ $args{"ifiles"} }; $i++ )
            {
                $basename = &File::Basename::basename( $args{"ifiles"}->[$i] );

                if ( $basename =~ /$colpat/ ) {
                    $ids[$i] = $1;
                }
            }
        }
    }

    if ( @ids )
    {
        if ( $i = grep { not defined $_ } @ids ) {
            push @msgs, ["ERROR", qq (Not all column labels are set, $i missing) ];
        } else {
            @ids = &Common::Util::uniqify( \@ids );
        }
    }
    else
    {
        @ids = ( 1 ... scalar @{ $args{"ifiles"} } );

        # push @msgs, ["ERROR", qq (No column ids given by names or expression) ];
        # push @msgs, ["INFO", qq (Define ids with --colids or --colpat options) ];
    }

    &append_or_exit( \@msgs );

    if ( ( $i = scalar @ids ) == ( $j = scalar @{ $args{"ifiles"} } ) )
    {
        $args{"headers"} = \@ids;
    }
    else
    {
        if ( $colids ) {
            push @msgs, ["ERROR", qq (There are $j consensus files, but $i unique IDs given) ];
        } elsif ( $colpat ) {
            push @msgs, ["ERROR", qq (There are $j consensus files, but pattern "$colpat" uniquely matches $i) ];
        } else {
            push @msgs, ["ERROR", qq (There are $j consensus files, but $i only unique file prefixes) ];
            push @msgs, ["INFO", qq (This can be fixed by using --colpat) ];            
        }
    }

    $args{"colids"} = $args->colids;
    $args{"colpat"} = $args->colpat;
    $args{"colfile"} = $args->colfile;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CHECK METHOD NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $method = $args->pmethod // "exact";

    if ( $method =~ /^similar|exact$/i ) {
        $args{"pmethod"} = lc $method;
    } else {
        push @msgs, ["ERROR", qq (Wrong looking pool method -> "$method", must be "similar" or "exact") ];
    }
    
    $method = $args->mmethod // "exact";

    if ( $method =~ /^similar|exact$/i ) {
        $args{"mmethod"} = lc $method;
    } else {
        push @msgs, ["ERROR", qq (Wrong looking map method -> "$method", must be "similar" or "exact") ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args{"iminsiz"} = &Registry::Args::check_number( $args->iminsiz, 1, undef, \@msgs );
    $args{"pminsiz"} = &Registry::Args::check_number( $args->pminsiz, 1, undef, \@msgs );

    $args{"iminlen"} = &Registry::Args::check_number( $args->iminlen, 15, undef, \@msgs );
    $args{"pminlen"} = &Registry::Args::check_number( $args->pminlen, 15, undef, \@msgs );

    $args{"pminsim"} = &Registry::Args::check_number( $args->pminsim, 80, 100, \@msgs );
    $args{"mminsim"} = &Registry::Args::check_number( $args->mminsim, 80, 100, \@msgs );

    $args{"pminres"} = &Registry::Args::check_number( $args->pminres, 0, 100, \@msgs );
    $args{"mminres"} = &Registry::Args::check_number( $args->mminres, 0, 100, \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Output table file,

    if ( $args->otable ) {
        &Common::File::check_files( [ $args->otable ], "!e", \@msgs ) if not $args->clobber;
    } else {
        push @msgs, ["ERROR", qq (No output table given) ];
    }

    if ( $args->ostats ) {
        &Common::File::check_files( [ $args->ostats ], "!e", \@msgs ) if not $args->clobber;
    }
    
    &append_or_exit( \@msgs );

    $args{"scale"} = $args->scale;
    $args{"otable"} = $args->otable;

    bless \%args;

    return wantarray ? %args : \%args;
}

sub create_table_store
{
    # Niels Larsen, February 2012. 

    # Creates a key/value storage where rows are values and keys are a given
    # column ID or number. Keys should be unique. Returns the number of values
    # saved.

    my ( $itab,    # Input table
         $odbm,    # Output DBM file
         $skip,    # Columns not to write
        ) = @_;

    # Returns integer. 

    my ( $ifh, $dbh, $mpack, @line, $line, $ndx, $i, @ndcs, %skip, @cols );

    $ifh = &Common::File::get_read_handle( $itab );
    $dbh = &Common::DBM::write_open( $odbm );

    $line = <$ifh>;
    chomp $line;

    @line = split "\t", $line;
    $line[0] =~ s/#\s*//;
    
    %skip = map { $_, 1 } @{ $skip };

    @ndcs = &Common::Table::names_to_indices( [ grep { not $skip{ $_ } } @line ], \@line );

    $ndx = &Common::Table::names_to_indices( ["ID"], \@line )->[0];

    $mpack = Data::MessagePack->new();

    $i = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        next if $line =~ /^#/;

        $line =~ s/\n$//;
        @line = split "\t", $line;

        &Common::DBM::put( $dbh, $line[$ndx], $mpack->pack( [ @line[ @ndcs ] ] ) );

        $i += 1;
    }

    &Common::File::close_handle( $ifh );
    &Common::DBM::close( $dbh );

    return $i;
}

sub init_map_stats
{
    # Niels Larsen, March 2013.

    my ( $recipe,
         $args,
        ) = @_;

    my ( $stats, $method );

    $stats->{"name"} = $recipe->{"name"} // "consensus-table";
    $stats->{"title"} = $recipe->{"title"} // "Consensus table";

    $stats->{"ifiles"} = [ map { &File::Basename::basename( $_ ) } @{ $args->ifiles } ];
    $stats->{"otable"} = $args->otable;

    $method = $args->pmethod;

    if ( $method eq "similar" ) {
        $stats->{"pool_method"} = "Similarity clustering";
    } elsif ( $method eq "exact" ) {
        $stats->{"pool_method"} = "Simple dereplication";
    } else {
        &error( qq (Unknown method -> "$method") );
    }
    
    $stats->{"pool_params"} = [
        {
            "title" => "Minimum input consensus length",
            "value" => $args->iminlen,
        },{
            "title" => "Minimum input consensus reads",
            "value" => $args->iminsiz,
        },{
            "title" => "Minimum pool consensus length",
            "value" => $args->pminlen,
        },{
            "title" => "Minimum pool consensus reads",
            "value" => $args->pminsiz,
        }];
    
    if ( $method eq "similar" )
    {
        push @{ $stats->{"pool_params"} },
        {
            "title" => "Minimum pooling similarity",
            "value" => $args->pminsim ."%",
        },{
            "title" => "Minimum bases in columns",
            "value" => $args->pminres ."%",
        };
    }
    
    $method = $args->mmethod;

    if ( $method eq "similar" ) {
        $stats->{"map_method"} = "Similarity mapping";
    } elsif ( $method eq "exact" ) {
        $stats->{"map_method"} = "Exact matching";
    } else {
        &error( qq (Unknown method -> "$method") );
    }

    $stats->{"map_params"} = [
        {
            "title" => "Scaling to similar totals",
            "value" => $args->scale ? "yes" : "no",
        }];
    
    if ( $method eq "similar" )
    {
        push @{ $stats->{"map_params"} }, {
            "title" => "Minimum mapping similarity",
            "value" => $args->mminsim ."%",
        };
    }

    return $stats;
}

sub match_pool
{
    # Niels Larsen, November 2011.

    # Matches a given fasta file against a set of consensus fasta files and 
    # makes a table of matches. The table rows are query sequences and their 
    # IDs, and there is one column per given consensus file. The table values 
    # are the original reads that match each sequence. Scaling is done, so 
    # differences in the total number of reads in each sample is averaged out. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $clobber, $count, $t_file, $i, $j, $q_file, $method, 
         $t_files, $sfh, $seq, @q_ids, $basename, $sum_tot, $o_file, $verbose,
         $ind1, $ind2, $numstr, @tab_vals, $factor, $col_hdrs, $scale, $sim_pct,
         $sums, $scale_dict, @q_seqs, $q_keys, $key, $col, $row, $ofh, $recipe,
         @col_hdrs, $table, @col_tots, @row_tots );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "ifiles" => [],
        "pool" => undef,
        "otable" => undef,
        "method" => "exact",
        "simpct" => 95,
        "scale" => 1,
        "colids" => undef,
        "colpat" => undef,
        "colfile" => undef,
        "clobber" => 0,
        "silent" => 0,
        "verbose" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Consensus::match_pool_args( $args );

    $q_file = $conf->pool;
    $t_files = $conf->ifiles;
    $o_file = $conf->otable;

    $col_hdrs = $conf->headers;
    $method = $conf->method;
    $sim_pct = $conf->simpct;
    $scale = $conf->scale;

    $clobber = $args->clobber;
    $verbose = $args->verbose;

    $ind1 = 3;
    $ind2 = 6;

    local $Common::Messages::silent = $args->silent;

    &echo_bold( "\nCreating table:\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> INDEX POOL FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not &Seq::Storage::is_indexed( $q_file ) )
    {
        $basename = &File::Basename::basename( $q_file );
        &echo( "Indexing $q_file ... ", $ind1 );
        
        &Seq::Storage::create_indices(
            {
                "ifiles" => [ $q_file ],
                "silent" => 1,
            });
        
        &echo_done("done\n");
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ ALL QUERY IDS <<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "Initializing output ... ", $ind1 );

    $sfh = &Common::File::get_read_handle( $q_file );

    while ( $seq = &Seq::IO::read_seq_fasta( $sfh ) )
    {
        push @q_ids, $seq->{"id"}; 
        push @q_seqs, $seq->{"seq"};
    }

    &Common::File::close_handle( $sfh );

    if ( $method eq "exact" ) {
        $q_keys = \@q_seqs;
    } else {
        $q_keys = \@q_ids;
    }

    &echo_done( ( scalar @q_ids )." rows\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL SCALING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $scale )
    {
        &echo("Creating scaling dictionary ... ", $ind1 );
        $scale_dict = &Seq::Consensus::create_scale_dict( $t_files );
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MATCH LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @tab_vals = ();

    for ( $col = 0; $col <= $#{ $t_files }; $col++ )
    {
        $t_file = $t_files->[$col];

        $basename = &File::Basename::basename( $t_file );
        &echo( "Matching $basename ... ", $ind1 );

        &echo( "\n" ) if $verbose;

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> MATCHING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $method eq "exact" )
        {
            &echo( "Finding exact matches ... ", $ind2 ) if $verbose;

            $sums = &Seq::Consensus::match_pool_exact(
                bless {
                    "query_keys" => $q_keys,
                    "target_file" => $t_file,
                    "verbose" => $verbose,
                });
        }
        else
        {
            &echo( "Matching with simscan ... ", $ind2 ) if $verbose;

            $sums = &Seq::Consensus::match_pool_sim(
                bless {
                    "query_file" => $q_file,
                    "target_file" => $t_file,
                    "sim_pct" => $sim_pct,
                    "verbose" => $verbose,
                });
        }

        &echo_green( "done\n" ) if $verbose;

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SCALING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $scale )
        {
            &echo( "Scaling by number of reads ... ", $ind2 ) if $verbose;

            $factor = $scale_dict->{ $t_file };

            # map { $sums->{ $_ } = ( sprintf "%.3f", $sums->{ $_ } / $factor ) } keys %{ $sums };
            map { $sums->{ $_ } = ( $sums->{ $_ } / $factor ) } keys %{ $sums };

            &echo_green( "done\n" ) if $verbose;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SAVING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        for ( $row = 0; $row <= $#{ $q_keys }; $row++ )
        {
            $tab_vals[$row]->[$col] = $sums->{ $q_keys->[$row] } // 0;
        }

        $sum_tot = int &List::Util::sum( values %{ $sums } );

        $numstr = &Common::Util::commify_number( $sum_tot // 0 );
        &echo_green( "$numstr total\n", $verbose ? $ind1 : 0 );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $o_file )
    {
        $basename = &File::Basename::basename( $o_file );
        &Common::File::delete_file_if_exists( $o_file ) if $clobber;
    }
    else {
        $basename = "STDOUT";
    }

    &echo( "Writing to $basename ... ", $ind1 );

    # Make table headers, 

    @col_hdrs = ( "ID", @{ $col_hdrs }, "Total", "Sequence" );

    # Make table values,

    for ( $row = 0; $row <= $#{ $q_keys }; $row++ )
    {
        $row_tots[$row] = &List::Util::sum( @{ $tab_vals[$row] } );
    }
    
    for ( $row = 0; $row <= $#{ $q_keys }; $row++ )
    {
        unshift @{ $tab_vals[$row] }, $q_ids[$row];
        push @{ $tab_vals[$row] }, $row_tots[$row], $q_seqs[$row];
    }

    # Create table, sort by totals (descending default),

    $table = &Common::Table::new( \@tab_vals, {"col_headers" => \@col_hdrs });
    $table = &Common::Table::sort_rows( $table, "Total" );

    # Add column totals as an extra row following the headers,

    @col_tots = &Common::Table::sum_cols( $table, [ @{ $col_hdrs }, "Total" ] );
    # @col_tots = map { int $_ } @col_tots;

    unshift @{ $table->values }, [ "#", @col_tots, "Column totals" ];
    
    $table->values( &Common::Tables::format_decimals( $table->values, "%.0f" ) );

    # Write table to file,

    &Common::Table::write_table( $table, $o_file, {"clobber" => $clobber});

    &echo_done( (scalar @q_ids) ." rows\n" );

    &echo_bold( "Finished\n\n" );

    return;
}

sub match_pool_args
{
    # Niels Larsen, November 2011.

    # Checks and expands the match routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, $file, $dir, @files, $count, @ids, $id, $colids, $colpat, 
         $i, $j, @lines, $method, $basename, $title, $tags );

    # Input files must be readable,

    if ( defined $args->pool ) {
        $args{"pool"} = ( &Common::File::check_files( [ $args->pool ], "efr", \@msgs ) )[0];
    } else {
        push @msgs, ["ERROR", qq (No fasta pool file is given) ];
    }

    &append_or_exit( \@msgs );

    # Get input files, perhaps a file with or without labels,

    if ( defined $args->ifiles )
    {
        # if ( -r $args->ifiles )
        # {
        #     @lines = &Common::File::read_lines( $args->ifiles );
        #     @lines = grep /\w/, @lines;
        #     chomp @lines;

        #     for ( $i = 0; $i <= $#lines; $i++ ) 
        #     {
        #         ( $args{"ifiles"}->[$i], $ids[$i] ) = split " ", $lines[$i];
        #     }
        # }
        # else {

        $args{"ifiles"} = &Seq::Args::expand_file_paths( $args->ifiles, \@msgs );
    }
    else {
        push @msgs, ["ERROR", qq (No fasta target files are given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> MAKE COLUMN LABELS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # There are three ways to specify table column titles:
    #
    # 1. Give a file of ids, in barcode file format. These ids will be use to 
    #    sort the file names with. The ID, F-Tag and R-tag columns that match 
    #    file names best are used. This option makes the columns appear in the
    #    same order as the ids in the file. 
    # 
    # 2. Give ids on the command line. This merely attaches ids to each file.
    #    Number of IDs and files must match and column order is not changed.
    # 
    # 3. Give a pattern. This pattern must match all file names and the sub-
    #    pattern within parantheses is used for column id. Column order is not
    #    changed. 

    @ids = ();

    $colids = $args->colids;
    $colpat = $args->colpat;

    if ( $args->colfile )
    {
        # Change order 

        $tags = &Seq::IO::read_table_tags( $args->colfile );
        
        foreach $title ( @Seq::IO::Bar_titles )
        {
            if ( grep { exists $_->{ $title } } @{ $tags } ) {
                @ids = map { $_->{ $title } } @{ $tags };
            } else {
                next;
            }

            @msgs = ();

            if ( @files = &Seq::Consensus::sort_paths( $args{"ifiles"}, \@ids, \@msgs ) )
            {
                $args{"ifiles"} = \@files;
                last;
            }
        }
    }
    elsif ( $colids or $colpat )
    {
        if ( $colids and $colpat ) 
        {
            push @msgs, ["ERROR", qq (Pattern and ID list are mutually exclusive arguments) ];
        }
        elsif ( $colids )
        {
            @ids = split /\s*,\s*/, $colids;
        }
        elsif ( $colpat )
        {
            for ( $i = 0; $i <= $#{ $args{"ifiles"} }; $i++ )
            {
                if ( not defined $ids[$i] )
                {
                    $basename = &File::Basename::basename( $args{"ifiles"}->[$i] );

                    if ( $basename =~ /$colpat/ ) {
                        $ids[$i] = $1;
                    }
                }
            }
        }
    }
    else 
    {
        @ids = ( 1 ... scalar @{ $args{"ifiles"} } );

        # for ( $i = 0; $i <= $#{ $args{"ifiles"} }; $i++ )
        # {
        #     if ( not defined $ids[$i] )
        #     {
        #         $basename = &File::Basename::basename( $args{"ifiles"}->[$i] );

        #         if ( $basename =~ /^([^.]+)/ ) {
        #             $ids[$i] = $1;
        #         }
        #     }
        # }
    }

    if ( @ids )
    {
        if ( $i = grep { not defined $_ } @ids ) {
            push @msgs, ["ERROR", qq (Not all column labels are set, $i missing) ];
        } else {
            @ids = &Common::Util::uniqify( \@ids );
        }
    }
    else {
        push @msgs, ["ERROR", qq (No column ids given by names or expression) ];
        push @msgs, ["INFO", qq (Define ids with --colids, --colpat or with the --tfiles option) ];
    }
    
    &append_or_exit( \@msgs );

    if ( ( $i = scalar @ids ) == ( $j = scalar @{ $args{"ifiles"} } ) )
    {
        $args{"headers"} = \@ids;
    }
    else
    {
        if ( $colids ) {
            push @msgs, ["ERROR", qq (There are $j consensus files, but $i unique IDs given) ];
        } elsif ( $colpat ) {
            push @msgs, ["ERROR", qq (There are $j consensus files, but pattern "$colpat" uniquely matches $i) ];
        } else {
            push @msgs, ["ERROR", qq (There are $j consensus files, but $i only unique file prefixes) ];
            push @msgs, ["INFO", qq (This can be fixed by using --colpat) ];            
        }
    }

    &append_or_exit( \@msgs );

    # Method must be "similar" or "exact",

    $method = $args->method // "exact";

    if ( $method =~ /^similar|exact$/i ) {
        $args{"method"} = lc $method;
    } else {
        push @msgs, ["ERROR", qq (Wrong looking method -> "$method", must be "similar" or "exact") ];
    }

    &append_or_exit( \@msgs );
    
    # Match percentage,

    $args{"simpct"} = &Registry::Args::check_number( $args->simpct, 80, 100, \@msgs );

    # Output table file,

    if ( $args->otable ) {
        &Common::File::check_files( [ $args->otable ], "!e", \@msgs ) if not $args->clobber;
    }
    
    &append_or_exit( \@msgs );

    $args{"scale"} = $args->scale;
    $args{"otable"} = $args->otable;

    bless \%args;

    return wantarray ? %args : \%args;
}

sub match_pool_exact
{
    # Niels Larsen, November 2011. 

    # Helper routine that matches query sequences against target sequences
    # by exact identity. Returns a hash where key is query sequence and 
    # value is the number of original reads.

    my ( $args,
        ) = @_;

    # Returns hash.

    my ( $q_keys, $t_file, %sums, $sum, $key, $val, $dbh, $params );

    local $Common::Messages::silent;

    $Common::Messages::silent = 1 unless $args->verbose;
    
    $q_keys = $args->query_keys;
    $t_file = $args->target_file;

    # >>>>>>>>>>>>>>>>>>>>>>>> INDEX TARGET FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not &Seq::Storage::is_indexed( $t_file, "derep_seq" ) )
    {
        &Seq::Storage::create_indices(
            {
                "ifiles" => [ $t_file ],
                "progtype" => "derep",
                "silent" => 1,
                "clobber" => 1,
            });
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>> SUM ORIGINAL COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
 
    ( $dbh, $params ) = &Common::DBM::read_tie( "$t_file.derep" );

    foreach $key ( @{ $q_keys } )
    {
        $val = &Common::DBM::get( $dbh, $key, 0 );
        
        if ( $val )
        {
            if ( $val =~ /^(\d+)\t/ ) {
                $sums{ $key } = $1;
            } else {
                &error( qq (Wrong looking derep DBM value -> "$val") );
            }
        }
        else {
            $sums{ $key } = 0;
        }
    }

    &Common::DBM::untie( $dbh, $params );

    return wantarray ? %sums : \%sums;
}

sub match_pool_sim
{
    # Niels Larsen, November 2011. 

    # Helper routine that matches query sequences against target sequences
    # by similarity. Returns a hash where key is query id and value is the 
    # number of original reads. This number comes from summing the reads
    # for those consenses that match better than a given percentage. This
    # may be bad in some situations, and good in others. 

    my ( $args,
        ) = @_;

    # Returns hash.

    my ( $q_file, $t_file, $ind6, $sim_pct, $sim_val, $basename, $prog_args,
         $tmp_file, $matches, $match, %matches, %sums, $sum, $key, $sfh, 
         @seqs );

    local $Common::Messages::silent;

    $Common::Messages::silent = 1 unless $args->verbose;
    
    $q_file = $args->query_file;
    $t_file = $args->target_file;

    $sim_pct = $args->sim_pct;
    $sim_val = $sim_pct / 100;

    $ind6 = 6;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN SIMSCAN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $prog_args =
        "--minslen 15"
        ." --mdom"
        ." --mrep"
        ." --ksize 9"
        ." --minlen 14"
        ." --kthresh 250"
        ." --gcap 0"
        ." --gep 0"
        ." --gap_period 1"
        ." --res_per_qry 50"
        ." --outmode TABX";
    
    $tmp_file = Registry::Paths->new_temp_path( "nsimscan" );
    
    &Seq::Match::match_single(
        {
            "prog" => "nsimscan",
            "args" => $prog_args,
            "ifile" => $q_file,
            "dbfiles" => [ $t_file ],
            "ofile" => $tmp_file,
            "silent" => 1,
        });
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>> DISTILL BEST MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo( "Distilling best matches ... ", $ind6 );    

    $matches = &Common::Table::read_table( $tmp_file, { "cols" => [ qw ( Q_id S_id al_len mism trg_len ) ] } )->values;
    
    &Common::File::delete_file( $tmp_file );
    
    # Use all matches that have may have indels but no mismatches, and that
    # match across nearly the whole target sequence,
    
    @{ $matches } = grep { $_->[3] == 0 and $_->[2] / $_->[4] >= $sim_val } @{ $matches };
    
    # Put the matches into a hash with query id as key and matching target ids
    # as values,
    
    %matches = ();
    
    foreach $match ( @{ $matches } )
    {
        push @{ $matches{ $match->[0] } }, $match->[1];
    }

    &echo_done("done\n");
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> INDEX DB-FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Index the db file by ids if not done already,

    if ( not &Seq::Storage::is_indexed( $t_file, "fetch_varpos" ) )
    {
        $basename = &File::Basename::basename( $t_file );
        &echo( "Indexing $basename ... ", $ind6 );
        
        &Seq::Storage::create_indices(
            {
                "ifiles" => [ $t_file ],
                "progtype" => "fetch",
                "silent" => 1,
            });
        
        &echo_done("done\n");
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>> SUM ORIGINAL COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # For each query id, sum up the number of original sequences that it 
    # matches. This is done by getting the matching consensus sequences
    # and then adding up the "seq_count" values.
    
    &echo( "Summing up cluster sizes ... ", $ind6 );
    
    $sfh = &Seq::Storage::get_handles( $t_file );
    
    foreach $key ( keys %matches )
    {
        $sum = 0;

        @seqs = &Seq::Storage::fetch_seqs(
            $sfh, 
            {
                "locs" => $matches{ $key },
                "return" => 1,
                "silent" => 1,
            });
        
        map { $sum += $_->parse_info->seq_count } @seqs;
        
        $sums{ $key } = $sum;
    }
    
    &Seq::Storage::close_handles( $sfh );

    return wantarray ? %sums : \%sums;
}

sub sort_paths
{
    # Niels Larsen, June 2012.

    # Sorts a list of file paths by a list of matching strings or patterns. 
    # The order of the paths becomes that of the strings, and each string 
    # must match only one path. The reordered list of paths is returned. 

    my ( $paths,    # List of paths
         $pats,     # List of patterns
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $i, $j, @paths, $pat, @hits, @msgs );

    # Check the lists are equally long,

    # TODO: handle empty file properly

    if ( ( $i = scalar @{ $paths } ) != ( $j = scalar @{ $pats } ) )
    {
        push @msgs, ["ERROR", qq ($i input files but $j column names) ];
        &append_or_exit( \@msgs );
    }
    
    foreach $pat ( @{ $pats } )
    {
        if ( @hits = grep { $_ =~ /$pat\./ } @{ $paths } )
        {
            if ( ( $i = scalar @hits ) == 1 ) 
            {
                push @paths, $hits[0];
            }
            else {
                push @msgs, ["ERROR", qq ("$pat" matches $i paths, should match only one) ];
            }
        }
        else {
            push @msgs, ["ERROR", qq ("$pat" does not match any path) ];
        }
    }
    
    if ( not @msgs )
    {
        return wantarray ? @paths : \@paths;
    }
    else {
        &append_or_exit( \@msgs, $msgs );
    }

    return;
}

sub table_stats
{
    # Niels Larsen, March 2012.

    # Returns the number of consenses and total reads (across all samples)
    # for all consenses. Returns a hash with those two values.

    my ( $file,    # File name
        ) = @_;

    # Returns a hash. 

    my ( $fh, $line, $ndx, %stats, $seqs, $origs );

    $fh = &Common::File::get_read_handle( $file );

    $ndx = &Common::Table::names_to_indices( ["Total"], [ split "\t", ( $line = <$fh> ) ] )->[0];

    $seqs = 0;
    $origs = 0;

    while ( defined ( $line = <$fh> ) )
    {
        next if $line =~ /^#/;

        $seqs += 1;

        chomp $line;
        
        $origs += ( split "\t", $line )[$ndx];
    }

    &Common::File::close_handle( $fh );

    %stats = ( "seqs" => $seqs, "origs" => $origs );

    return wantarray ? %stats : \%stats;
}

sub table_stats_mem
{
    # Niels Larsen, March 2012. 

    # Returns the number of consenses and total reads (across all samples)
    # for all consenses. Returns a hash with those two values.

    my ( $table,    # Table object
        ) = @_;

    # Returns a hash.

    my ( $col, %stats);

    $col = &Common::Table::get_col( $table, "Total" );

    %stats = (
        "seqs" => scalar @{ $col },
        "origs" => &List::Util::sum( @{ $col } ),
        );

    return wantarray ? %stats : \%stats;
}

sub write_clu_pool
{
    # Niels Larsen, March 2012. 

    # Writes a given fasta file into a fasta file, while filtering by read count and 
    # sequence length. Returns input and output counts of sequences and original
    # reads, as a hash.

    my ( $ifile,   # Input fasta
         $ofile,   # Output fasta
         $args,    # Arguments hash
        ) = @_;

    # Returns a hash.

    my ( $ifh, $ofh, $seqs_in, $origs_in, $seqs_out, $origs_out, $seq_id, $seq,
         $siz, $len, $min_siz, $min_len, $func );

    $min_siz = $args->{"minsiz"};
    $min_len = $args->{"minlen"};

    $func = eval "sub { ". $args->{"code"} ." }";

    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( $ofile, "clobber" => $args->{"clobber"} );

    $seqs_in = 0;
    $origs_in = 0;
    $seqs_out = 0;
    $origs_out = 0;

    $seq_id = 0;
    
    while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
    {
        $siz = &Seq::Common::info_field( $seq, "seq_count");
        $len = &Seq::Common::seq_len( $seq );

        $seqs_in += 1;
        $origs_in += $siz;

        if ( $siz >= $min_siz and $len >= $min_len )
        {
            $func->();
            
            $seqs_out += 1;
            $origs_out += $siz;
        }
    }
        
    &Common::File::close_handle( $ofh );
    &Common::File::close_handle( $ifh );
    
    return {
        "seqs_in" => $seqs_in,
        "origs_in" => $origs_in,
        "seqs_out" => $seqs_out,
        "origs_out" => $origs_out,
    };
}

sub write_clu_stats
{
    # Niels Larsen, March 2012. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to the given
    # file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $fh, $text, $secs, $seqs, $origs, $sdif, $odif, $spct, $opct, $file,
         $params, $itable, $otable, $ofasta );

    $secs = sprintf "%.1f", $stats->{"seconds"};
    
    # >>>>>>>>>>>>>>>>>>>>>>>> FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $params = "";
    map { $params .= qq (         item = $_->{"title"}: $_->{"value"}\n) } @{ $stats->{"params"} };
    chomp $params;

    $itable = &File::Basename::basename( $stats->{"itable"} );
    $otable = &File::Basename::basename( $stats->{"otable"} );
    $ofasta = &File::Basename::basename( $stats->{"ofasta"} ) if $stats->{"ofasta"};

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
      file = Input table\t$itable
      file = Output table\t$otable
);

    if ( $ofasta ) {
        $text .= "      file = Output fasta\t$ofasta\n";
    }

    $text .= qq (      hrow = Consensus method\t$stats->{"method"}
      <menu>
         title = Parameters
$params
      </menu>
      date = $stats->{"finished"}
      time = $secs seconds
   </header>

   <table>
      title = Consensus sequence and reads statistics 
      colh = \tConsenses\t&Delta;\t&Delta; %\tReads\t&Delta;\t&Delta; %
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Input table,

    $seqs = $stats->{"seqs_in"};
    $origs = $stats->{"origs_in"};

    $text .= qq (      trow = Input table\t$seqs\t\t\t$origs\t\t\n);

    # Output table,

    $seqs = $stats->{"seqs_out"};
    $origs = $stats->{"origs_out"};

    $sdif = $stats->{"seqs_in"} - $stats->{"seqs_out"};
    $odif = $stats->{"origs_in"} - $stats->{"origs_out"};

    $spct = sprintf "%.2f", 100 * ( 1 - $stats->{"seqs_out"} / $stats->{"seqs_in"} );
    $opct = sprintf "%.2f", 100 * ( 1 - $stats->{"origs_out"} / $stats->{"origs_in"} );

    $text .= qq (      trow = Output table\t$seqs\t-$sdif\t-$spct\t$origs\t-$odif\t-$opct\n);

    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else 
    {
        $fh = &Common::File::get_append_handle( $sfile );
        $fh->print( $text );
        &Common::File::close_handle( $fh );
    }

    return;
}

sub write_map_stats
{
    # Niels Larsen, March 2012. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to the given
    # file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $fh, $text, $secs, $seqs, $origs, $sdif, $odif, $spct, $opct, $file,
         $title, $value, $clu_dif, $seq_dif, $f_menu, $p_params, $m_params,
         $otable );

    $secs = sprintf "%.1f", $stats->{"seconds"};
    
    # >>>>>>>>>>>>>>>>>>>>>>>> FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $f_menu = "";
    map { $f_menu .= qq (         item = $_\n) } @{ $stats->{"ifiles"} };
    chomp $f_menu;

    $p_params = "";
    map { $p_params .= qq (         item = $_->{"title"}: $_->{"value"}\n) } @{ $stats->{"pool_params"} };
    chomp $p_params;
    
    $m_params = "";
    map { $m_params .= qq (         item = $_->{"title"}: $_->{"value"}\n) } @{ $stats->{"map_params"} };
    chomp $m_params;

    $otable = &File::Basename::basename( $stats->{"otable"} );

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
      <menu>
         title = Input files
$f_menu
      </menu>
      file = Output table\t$otable
      hrow = Pool method\t$stats->{"pool_method"}
      <menu>
         title = Pool parameters
$p_params
      </menu>
      hrow = Map method\t$stats->{"map_method"}
      <menu>
         title = Map parameters
$m_params
      </menu>
      date = $stats->{"finished"}
      time = $secs seconds
   </header>

   <table>
      title = Consensus sequence and reads statistics
      colh = \tConsenses\t&Delta;\t&Delta; %\tReads\t&Delta;\t&Delta; %
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Input consensus files,

    $seqs = $stats->{"seqs_in"};
    $origs = $stats->{"origs_in"};

    $text .= qq (      trow = Input files\t$seqs\t\t\t$origs\t\t\n);

    # Pooled consensus files,

    $seqs = $stats->{"seqs_pool"};
    $origs = $stats->{"origs_pool"};

    $sdif = $stats->{"seqs_in"} - $stats->{"seqs_pool"};
    $odif = $stats->{"origs_in"} - $stats->{"origs_pool"};

    $spct = sprintf "%.2f", 100 * ( 1 - $stats->{"seqs_pool"} / $stats->{"seqs_in"} );
    $opct = sprintf "%.2f", 100 * ( 1 - $stats->{"origs_pool"} / $stats->{"origs_in"} );

    $text .= qq (      trow = Pooled files\t$seqs\t-$sdif\t-$spct\t$origs\t-$odif\t-$opct\n);

    # Clustered pool,

    $seqs = $stats->{"seqs_clu"};
    $origs = $stats->{"origs_clu"};

    $sdif = $stats->{"seqs_pool"} - $stats->{"seqs_clu"};
    $odif = $stats->{"origs_pool"} - $stats->{"origs_clu"};

    $spct = sprintf "%.2f", 100 * ( 1 - $stats->{"seqs_clu"} / $stats->{"seqs_pool"} );
    $opct = sprintf "%.2f", 100 * ( 1 - $stats->{"origs_clu"} / $stats->{"origs_pool"} );

    $text .= qq (      trow = Clustered pool\t$seqs\t-$sdif\t-$spct\t$origs\t-$odif\t-$opct\n);

    # Output table,

    $seqs = $stats->{"seqs_out"};
    $origs = $stats->{"origs_out"};

    $sdif = $stats->{"seqs_clu"} - $stats->{"seqs_out"};
    $odif = $stats->{"origs_clu"} - $stats->{"origs_out"};

    $spct = sprintf "%.2f", 100 * ( 1 - $stats->{"seqs_out"} / $stats->{"seqs_clu"} );
    $opct = sprintf "%.2f", 100 * ( 1 - $stats->{"origs_out"} / $stats->{"origs_clu"} );

    $text .= qq (      trow = Output table\t$seqs\t-$sdif\t-$spct\t$origs\t-$odif\t-$opct\n);

    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else 
    {
        $fh = &Common::File::get_append_handle( $sfile );
        $fh->print( $text );
        &Common::File::close_handle( $fh );
    }

    return;
}

1;

__END__

# sub read_patfile
# {
#     my ( $file,
#         ) = @_;

#     my ( $fh, $line, $dict, $name, $args );

#     $fh = &Common::File::get_read_handle( $file );

#     while ( defined ( $line = <$fh> ) )
#     {
#         if ( $line =~ /^\s*--(\S+)\s+(\S+)/ )
#         {
#             $args->{ $1 } = $2;
#         }
#         elsif ( $line =~ /^>(\S+)/ )
#         {
#             $name = $1;
#         }
#         elsif ( $line =~ /\w/ and $line !~ /^#/ )
#         {
#             chomp $line;
#             push @{ $dict->{ $name } }, $line;
#         }
#     }

#     &Common::File::close_handle( $fh );

#     return ( $dict, $args );
# }

    # >>>>>>>>>>>>>>>>>>>>>>>>> RELABEL DICTIONARY IDS <<<<<<<<<<<<<<<<<<<<<<<<

    # if ( $conf->labels ) 
    # {
    #     &echo( "Matching known sequences ... ", $ind1 );

    #     $tmp_file = Registry::Paths->new_temp_path( "nsimscan" );

    #     $simscan_args =
    #         "--minslen 15"
    #         ." --mdom"
    #         ." --mrep"
    #         ." --ksize 11"
    #         ." --minlen 14"
    #         ." --kthresh 100"
    #         ." --gcap 0"
    #         ." --gep 0"
    #         ." --gap_period 1"
    #         ." --res_per_qry 100"
    #         ." --approx"
    #         ." --outmode TABX";
        
    #     &Seq::Match::match_single(
    #         {
    #             "prog" => "nsimscan",
    #             "args" => $simscan_args,
    #             "ifile" => $conf->labels,
    #             "dbfiles" => [ $ofile ],
    #             "ofile" => $tmp_file,
    #             "silent" => 1,
    #         });
        
    #     $tmp_table = &Common::Table::read_table( $tmp_file, { "cols" => [ qw ( Q_id S_id p_inden ) ] } );
    #     %known = map { $_->[1], $_ } @{ $tmp_table->values };

    #     $tmp_file = Registry::Paths->new_temp_path( "nsimscan" );

    #     $ifh = &Common::File::get_read_handle( $ofile );
    #     $ofh = &Common::File::get_write_handle( $tmp_file );

    #     $count = 0;

    #     while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
    #     {
    #         if ( $tuple = $known{ $seq->id } and $tuple->[2] >= 90 )
    #         {
    #             $seq->id( $tuple->[0] );
                
    #             if ( not $seen{ $tuple->[0] } )
    #             {
    #                 &Seq::IO::write_seq_fasta( $ofh, $seq );
    #                 $seen{ $tuple->[0] } = 1;
    #                 $count += 1;
    #             }
    #         }
    #         else
    #         {
    #             &Seq::IO::write_seq_fasta( $ofh, $seq );
    #             $count += 1;
    #         }
    #     }
        
    #     $ifh->close;
    #     $ofh->close;

    #     &Common::File::delete_file( $ofile );
    #     &Common::File::rename_file( $tmp_file, $ofile );

    #     &echo_green( &Common::Util::commify_number( $count // 0 ) ." total \n" );
    # }

# sub query_match_table
# {
#     # Niels Larsen, November 2011.

#     # UNFINISHED. 

#     my ( $args,
#         ) = @_;

#     my ( $defs, %args, $clobber, @header, $table, $maxcol, $minval, $ndx, @table );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $defs = 
#     {
#         "ifile" => undef,
#         "ofile" => undef,
#         "minval" => 1,
#         "minfold" => 10,
#         "from" => undef,
#         "to" => undef,
#         "sortvals" => undef,
#         "sortseqs" => undef,
#         "clobber" => 0,
#         "silent" => 0,
#     };

#     $args = &Registry::Args::create( $args, $defs );
#     %args = &Seq::Consensus::query_match_table_args( $args );

#     $clobber = $args->clobber;

#     $table = &Common::Table::read_table( $args{"ifile"} );
#     @header = @{ $table->col_headers };
#     @table = @{ $table->values };

#     $maxcol = $#{ $table->[0] };

#     if ( $minval = $args{"minval"} )
#     {
#         @table = grep { &List::Util::max( @{ $_ }[ 2 ... $maxcol ] ) >= $minval } @table;
#     }

#     if ( $ndx = $args{"sortvals_ndx"} )
#     {
#         @table = sort { $b->[$ndx] <=> $a->[$ndx] } @table;
#     }

#     if ( $args->sortseqs )
#     {
#         @table = sort { $b->[1] cmp $a->[1] } @table;
#     }

#     &Common::File::delete_file_if_exists( $args{"ofile"} ) if $clobber;
    
#     unshift @table, @header;
#     &Common::Tables::write_tab_table( $args{"ofile"}, \@table );

#     return;
# }

# sub query_match_table_args
# {
#     # Niels Larsen, November 2011.

#     # Checks and expands the query routine parameters and does one of 
#     # two: 1) if there are errors, these are printed in void context and
#     # pushed onto a given message list in non-void context, 2) if no 
#     # errors, returns a hash of expanded arguments.

#     my ( $args,      # Arguments
# 	) = @_;

#     # Returns hash or nothing.

#     my ( @msgs, %args, $file, $dir, @fields, $count, $fh, $line, @list, $subref );

#     @msgs = ();

#     $subref = sub
#     {
#         my ( $fldstr, $fields, $max, $msgs ) = @_;

#         my ( @str, $str, @list, $i, %fields );

#         if ( @str = &Registry::Args::split_string( $fldstr ) )
#         {
#             $i = 0;
#             %fields = map { $_, ++$i } @{ $fields };

#             foreach $str ( @str )
#             {
#                 if ( exists $fields{ $str } )
#                 {
#                     push @list, $fields{ $str };
#                 }
#                 else {
#                     push @{ $msgs }, ["ERROR", qq (Wrong looking field name -> "$str") ];
#                 }
#             }
#         }

#         if ( defined $max and ( $count = scalar @list ) > $max ) {
#             push @{ $msgs }, ["ERROR", qq ($fldstr contains $count names, there may only be $max) ];
#         }

#         return \@list;
#     };

#     # Input file must be readable,

#     if ( defined $args->ifile ) {
# 	$args{"ifile"} = ( &Common::File::check_files( [ $args->ifile ], "efr", \@msgs ) )[0];        
#     } else {
#         push @msgs, ["ERROR", qq (No table input file is given) ];
#     }
    
#     if ( defined $args->minval ) {
# 	$args{"minval"} = &Registry::Args::check_number( $args->minval, 1, undef, \@msgs );
#     }

#     if ( defined $args->minfold ) {
# 	$args{"minfold"} = &Registry::Args::check_number( $args->minfold, 1, undef, \@msgs );
#     }

#     if ( $file = $args{"ifile"} )
#     {
#         $fh = &Common::File::get_read_handle( $file );
        
#         $line = <$fh>; 
#         chomp $line;

#         @fields = split "\t", $line;
#         @fields = @fields[ 1 ... $#fields ];

#         if ( defined $args->from ) {
#             $args{"from_ndx"} = @{ $subref->( $args->from, \@fields, 1, \@msgs ) }[0];
#         }

#         if ( defined $args->to ) {
#             $args{"to_ndx"} = @{ $subref->( $args->to, \@fields, 1, \@msgs ) }[0];
#         }

#         if ( defined $args->sortvals ) {
#             $args{"sortvals_ndx"} = @{ $subref->( $args->sortvals, \@fields, 1, \@msgs ) }[0];
#         }

#         $fh->close;
#     }

#     if ( $args->ofile )
#     {
#         &Common::File::check_files( [ $args->ofile ], "!e", \@msgs ) if not $args->clobber;
#         $args{"ofile"} = $args->ofile;
#     } else {
#         push @msgs, ["ERROR", qq (No table output file given) ];
#     }
    
#     &append_or_exit( \@msgs );
    
#     return wantarray ? %args : \%args;
# }
