package Seq::Classify;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that classify sequences. Scripts should use the classify routine, 
# not the others. The process_args routine can be used to see if the classify
# arguments given are right, before running.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Time::HiRes;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &classify
                 &classify_single
                 &create_cla_file
                 &distill_sim_rows
                 &noclassify
                 &process_args
                 &process_config
                 &sim_from_m8_row
                 &write_cla_table
);

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;
use Common::DBM;
use Common::Table;

use Registry::Args;

use Seq::Match;
use Seq::IO;
use Seq::Info;
use Seq::Args;

our ( %Config );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub classify
{
    # Niels Larsen, February 2010.

    # Compares a query set of sequences against a user defined set of files or 
    # reference datasets, using the nsimscan or psimscan software. These datasets
    # may contain functionally similar or dissimilar sequences. The program is 
    # first run with low stringency and the best matches are kept for each 
    # function annotation. Output is a table with one or more rows per query 
    # sequence, where each row contains
    # 
    # input sequence multiplicity
    # input sequence id
    # input sequence length
    # dataset name
    # dataset sequence id
    # similarity percentage
    # number of organism hits for same molecule
    # free-text comment
    # 
    # If a query has no matches, the table row will contain the first two fields
    # field, and the rest will be empty. This is the routine that should be called
    # by scripts.

    my ( $args,
	) = @_;

    # Returns nothing.
    
    my ( $defs, $silent, $in_files, $i, $out_files, %args, $label, $clobber,
         $name, $indent, $silent2, $count, $type, $in_file, $conf, $verbose,
         $stat_files, $new_stats, $hits, $nohits );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifiles" => [],
        "config" => "",
        "ofile" => "",
        "osuffix" => ".cla",
        "stats" => undef,
        "newstats" => undef,
	"minsim" => undef,
	"maxrat" => undef,
	"maxout" => undef,
	"silent" => 0,
	"verbose" => 0,
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    
    # Does error and value checking and creates a full set of arguments for 
    # each dataset, so it is easier to call the routines below,

    $conf = &Seq::Classify::process_args( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COMPARE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Convenience variables,

    $in_files = $conf->ifiles;
    $out_files = $conf->ofiles;
    $stat_files = $conf->ostats;

    $label = $conf->label || "Sequence classification";

    $Common::Messages::silent = $args->silent;

    if ( $silent ) {
        $silent2 = $Common::Messages::silent;
    } else {
	$silent2 = $args->verbose ? 0 : 1;
    }

    $new_stats = $args->newstats;

    $indent = $args->verbose ? 3 : 0;
    $verbose = $args->verbose;
    $clobber = $args->clobber;
    
    &echo_bold( qq (\n$label:\n) );

    if ( $in_files and scalar @{ $in_files } > 1 )
    {
        # >>>>>>>>>>>>>>>>>>>>>> MULTIPLE QUERY FILES <<<<<<<<<<<<<<<<<<<<<<<<<
        
        for ( $i = 0; $i <= $#{ $in_files }; $i++ )
        {
            $name = &File::Basename::basename( $in_files->[$i] );
            &echo( "   Processing $name ... " );

            if ( defined $new_stats ) {
                &Common::File::delete_file_if_exists( $stat_files->[$i] );
            }

            no strict "refs";

            ( $hits, $nohits ) = &Seq::Classify::classify_single(
                {
                    "ifile" => $in_files->[$i],
                    "itype" => $conf->itype,
                    "ofile" => $out_files->[$i],
                    "stats" => $stat_files->[$i],
                    "title" => $conf->label,
                    "datasets" => $conf->datasets,
                    "silent" => $silent2,
                    "verbose" => $args->verbose,
                    "clobber" => $clobber,
                    "indent" => $indent,
                });

            &echo_done( "$hits hit[s], $nohits miss[es]\n", $indent );
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>> SINGLE QUERY FILE OR STREAM <<<<<<<<<<<<<<<<<<<<

        if ( $in_files and @{ $in_files } ) {
            $name = &File::Basename::basename( $in_files->[0] );
        } else {
            $name = "STDIN";
        }

        &echo( "   Processing $name ... " );

        if ( $name eq "STDIN" )
        {
            # Drain stdin,

            $in_file = Registry::Paths->new_temp_path( "classify.in" );
            &Common::File::save_stdin( $in_file );
        }
        else {
            $in_file = $in_files->[0];
        }

        if ( defined $new_stats ) {
            &Common::File::delete_file_if_exists( $stat_files->[0] );
        }

        no strict "refs";
        
        ( $hits, $nohits ) = &Seq::Classify::classify_single(
            {
                "ifile" => $in_file,
                "itype" => $conf->itype,
                "ofile" => $out_files->[0],
                "stats" => $stat_files->[0],
                "title" => $conf->label,
                "datasets" => $conf->datasets,
                "silent" => $silent2,
                "verbose" => $args->verbose,
                "clobber" => $clobber,
                "indent" => $indent,
            });
        
        &echo_done( "$hits hit[s], $nohits miss[es]\n", $indent );
    }        

    &echo_bold("Done\n\n");

    return;
}

sub classify_single
{
    # Niels Larsen, March 2010.

    # Matches a single sequence file against a list of datasets, in succession:
    # the sequences that do not match a given dataset are tried with the next,
    # and so on. The output is a table where all input sequences are listed
    # with their matches. Returns the total number of matching sequences.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns integer. 
    
    my ( @dbs, $db, $db_file_id, $db_file_label, $db_file_path, $silent, $db_file,
         $seq_file_orig, $sim_file, $seq_file, $cla_file, $tmp_file, $clobber,
         $dbm_file, $count, $id_file, $name, @ids, $id, $ofh, $dbh, $list,
         %dbs, $run_count, $cla_count, $seq_count, $matches, $db_mol, $seq_fh, 
         $seq, $tmp_dir, $query_ids, $mol_names, @seq_counts, %seq_counts,
         $seq_total, $stat_file, @stats, $stat, $hits, $nohits,
         $sim_count, $sim_total );
    
    local $Common::Messages::indent_plain;
    local $Common::Messages::silent;

    $args = &Registry::Args::create( $args );

    @dbs = @{ $args->datasets };

    $Common::Messages::silent = $args->silent;
    $clobber = $args->clobber;
    
    if ( not $silent ) {
	$Common::Messages::indent_plain = $args->indent + 3;
	&echo("\n");
    }

    $seq_file_orig = $args->ifile;
    $stat_file = $args->stats;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIATE QUERY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $tmp_dir = $Common::Config::tmp_dir ."/seq_classify.$$";
    &Common::File::create_dir( $tmp_dir );

    # As first input, create a link in the scratch area to the original file,

    $seq_file = "$tmp_dir/classify.seqs";
    &Common::File::create_link( $seq_file_orig, $seq_file );

    # Get multiplicity counts from the query input file,

    &echo( qq (Reading query sequence counts ... ) );

    $seq_fh = &Common::File::get_read_handle( $seq_file );

    while ( $seq = bless &Seq::IO::read_seq_fasta( $seq_fh ), "Seq::Common" )
    {
        push @seq_counts, [ $seq->id, $seq->parse_info->seq_count || 1 ];
    }

    &Common::File::close_handle( $seq_fh );

    %seq_counts = map { $_->[0], $_->[1] } @seq_counts;
    $seq_total = &List::Util::sum( map { $_->[1] } @seq_counts );

    &echo_done( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>> MATCH AGAINST DATASET FILES <<<<<<<<<<<<<<<<<<<<<

    # Match against the files in the order given, one by one, and only sequences
    # with no hits are matched against the next the in the order. 

    $dbm_file = "$tmp_dir/classify.fetch";

    $run_count = 0;
    $sim_count = 0;
    $sim_total = 0;

    foreach $db ( @dbs )
    {
        $cla_count = 0;
        $seq_count = 0;

        foreach $db_file ( @{ $db->{"files"} } )
        {
            $db_file_id = $db_file->{"name"};
            $db_file_path = $db_file->{"path"};
            $db_file_label = $db_file->{"label"};
            
            # >>>>>>>>>>>>>>>>>>>>> ISOLATE NON-MATCHES <<<<<<<<<<<<<<<<<<<<<<<
            
            # This is only done after the match below has been run at least once.
            # Isolate all entries that did not match,

            if ( $run_count > 0 and $sim_count > 0 )
            {
                &echo("   Distilling non-hits ... ");

                if ( -s $cla_file )
                {
                    $id_file = "$tmp_dir/classify.ids";
                    &Common::OS::run3_command( "cut -f 1 $cla_file | uniq", undef, $id_file );
                    &Common::File::delete_file_if_exists( $cla_file );
                    
                    $tmp_file = "$tmp_dir/classify.seqs.tmp";
                    $count = &Seq::IO::select_seqs_fasta( $seq_file, undef, $id_file, $tmp_file );
                    
                    &Common::File::delete_file( $id_file );
                    
                    &Common::File::delete_file( $seq_file );
                    &Common::File::rename_file( $tmp_file, $seq_file );
                    
                    if ( $count >= 1 ) {
                        &echo_done( "$count\n");
                    } else {
                        &echo_done( "none\n" );
                        last;
                    }
                }
                else {
                    &echo_done( "none\n" );
                    last;
                }
            }

            # >>>>>>>>>>>>>>>>>>>>>>>>>> RUN MATCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            # Match query entries against the given file,

            &echo( qq (Matching "$db_file_label" ... ) );
            
            $sim_file = "$tmp_dir/classify.tab";

            &Seq::Match::match(
                {
                    "ifiles" => [ $seq_file ],
                    "itype" => $args->itype,
                    "dbs" => $db_file_path,
                    "osingle" => $sim_file,
                    "prog" => $db->{"prog"},
                    "args" => ( join " ", @{ $db->{"prog_args"} } ),
                    "tgtann" => 1,
                    "silent" => 1,
                    "clobber" => 1,
                });

            $sim_count = &Common::File::count_lines( $sim_file );
            $sim_total += $sim_count;
            
            if ( not $silent ) {
                &echo_done("$sim_count hit[s]\n");
            }

            if ( $sim_count > 0 )
            {
                # >>>>>>>>>>>>>>>>>>>>>>> DISTILL MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<
                
                &echo("   Distilling matches ... ");
                
                $cla_file = "$tmp_dir/classify.out";
                &Common::File::delete_file_if_exists( $cla_file );
                
                ( $query_ids, $mol_names ) = &Seq::Classify::create_cla_file(
                    bless {
                        "simfile" => $sim_file,         # Simscan similarities, M8 format
                        "clafile" => $cla_file,         # Classification table for this run
                        "cladbm" => $dbm_file,          # Key/value store for results of all runs
                        "tgtname" => $db_file_label,
                        "minsim" => $db->min_sim,
                        "maxrat" => $db->max_rat,
                        "ignore" => $db->no_match,
                        "trans" => $db->trans,
                    });

                foreach $id ( @{ $query_ids } )
                {
                    if ( $seq_counts{ $id } ) {
                        $seq_count += $seq_counts{ $id };
                    }
                }

                $cla_count += ( scalar @{ $mol_names } ) || 0;

                &echo_done( "done\n" );
            }
            
            &Common::File::delete_file( $sim_file );
            
            $run_count += 1;
        }

        if ( $stat_file )
        {
            push @stats, bless {
                "dat_label" => $db_file_label,
                "cla_count" => $cla_count || 0,
                "seq_count" => $seq_count || 0,
            };
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create output with the same order as the input. This is done by getting
    # ids from the input, and then pulling corresponding result table elements
    # out of the random-access storage created above,

    if ( $sim_total > 0 )
    {
        if ( $args->ofile ) 
        {
            $name = &File::Basename::basename( $args->ofile );
            &echo( "Writing $name ... " );
            
            &Common::File::delete_file_if_exists( $args->ofile ) if $clobber;
        }
        
        ( $hits, $nohits ) = &Seq::Classify::write_cla_table(
            bless {
                "seq_counts" => \@seq_counts,
                "dbm_file" => $dbm_file,
                "cla_file" => $args->ofile,
            });
        
        if ( $args->ofile ) {
            &echo_done( "$hits hit[s], $nohits miss[es]\n", 0 );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stat_file )
    {
        $name = &File::Basename::basename( $stat_file );
        &echo("   Writing $name ... ");
 
        &Seq::Stats::create_stats_classify(
            $stat_file,
            bless {
                "input_file" => &Common::File::full_file_path( $args->ifile ),
                "output_file" => &Common::File::full_file_path( $args->ofile ),
                "flow_title" => $args->title,
                "stat_rows" => \@stats,
                "seq_total" => $seq_total,
            }, "Seq::Stats" );
    
        &echo_done("done\n");
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> DELETE TEMPORARY FILES <<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "Deleting scratch files ... " );

    &Seq::Storage::delete_indices(
        {
            "paths" => [ $seq_file ],
            "silent" => 1,
        });
    
    &Common::File::delete_file( $seq_file );
    
    &Common::File::delete_file_if_exists( $cla_file ) if defined $cla_file;
    &Common::File::delete_file_if_exists( $dbm_file ) if defined $dbm_file;

    &Common::File::delete_dir_if_empty( $tmp_dir );

    &echo_done( "done\n", 0 );

    return ( $hits // 0, $nohits // 0 );
}

sub create_cla_file
{
    # Niels Larsen, February 2010.

    # Creates a classification table with these fields,
    # 
    #   0: Query id
    #   1: Similarity percent
    #   2: Match length
    #   3: Number of mismatches
    #   4: Number of gaps 
    #   5: Query length 
    #   6: Target length 
    #   7: Target id 
    #   8: Molecule annotation string
    #
    # See the routine distill_sim_rows for how this is done. 

    my ( $args,
	) = @_;

    # Returns nothing.

    my ( $defs, $sim_fh, $cla_fh, $line, @tab_rows, @line, $id, $row,
	 @out_rows, $tgt_name, $min_sim, $max_rat, $odbm, $dbh, $ignore,
         $trans, $tgt_mol, $sim_file, $cla_file, $cla_dbm, $cla_dbh, 
         $process_rows, @query_ids, @mol_names );
    
    $sim_file = $args->simfile;
    $cla_file = $args->clafile;
    $cla_dbm = $args->cladbm;
    $min_sim = $args->minsim;
    $tgt_name = $args->tgtname;
    $max_rat = $args->maxrat;
    $ignore = $args->ignore;
    $trans = $args->trans;

    # Loop through table, isolate and filter matches for each query,
    
    $sim_fh = &Common::File::get_read_handle( $sim_file );
    $cla_fh = &Common::File::get_write_handle( $cla_file );
    $cla_dbh = &Common::DBM::write_open( $cla_dbm );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> LOCAL ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $process_rows = sub
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>> ADD DATASET NAME <<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Insert target database name at third-last column position,

        @out_rows = map { splice @{ $_ }, -2, 0, $tgt_name; $_ } @out_rows;

        # >>>>>>>>>>>>>>>>>>>>>>>> SAVE IDS AND NAMES <<<<<<<<<<<<<<<<<<<<<<<<<

        # These are returned, needed for statistics-making outside this routine,

        push @query_ids, map { $_->[0] } @out_rows;
        push @mol_names, map { $_->[-1] } @out_rows;
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # 1. Write rows to sequential file
        # 2. Write rows to key/value store (needed for final output routine later)

        $id = $out_rows[0]->[0];
        @out_rows = map { join "\t", @{ $_ } } @out_rows;
        
        map { $cla_fh->print( "$_\n" ) } @out_rows;

        &Common::DBM::put_struct( $cla_dbh, $id, \@out_rows );
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> READ TABLE FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $line = <$sim_fh>;    # Skip comment line

    # The following unclean piece reads lines with same query id from a simscan
    # or blast m8 table, submits those lines to a routine that simplifies and 
    # collapses organismal instances of the same molecule to one, and finally 
    # writes the result into a key/value store for later. 

    while ( defined ( $line = <$sim_fh> ) )
    {
        chomp $line;
        @line = split "\t", $line;
        
        if ( @tab_rows )
        {
            if ( $line[0] eq $tab_rows[0]->[0] )
            {
                # Add lines to be distilled,

                push @tab_rows, [ @line ];
            }
            else
            {
                # Distill matches,
                
                @out_rows = &Seq::Classify::distill_sim_rows(
                    \@tab_rows,
                    bless {
                        "tgt_mol" => $tgt_mol,
                        "min_sim" => $min_sim,
                        "max_rat" => $max_rat,
                        "ignore" => $ignore,
                        "trans" => $trans,
                    });

                # Create output(s),

                $process_rows->() if @out_rows;

                # Reset table rows to be distilled,

                @tab_rows = [ @line ];
            }
        }
        else {
            @tab_rows = [ @line ];
        }
    }

    # Distill matches for last query ID in file,

    @out_rows = &Seq::Classify::distill_sim_rows(
        \@tab_rows,
        bless {
            "tgt_mol" => $tgt_mol,
            "min_sim" => $min_sim,
            "max_rat" => $max_rat,
            "ignore" => $ignore,
            "trans" => $trans,
        });

    $process_rows->() if @out_rows;

    $sim_fh->close;
    $cla_fh->close;

    &Common::DBM::close( $cla_dbh );

    @query_ids = @{ &Common::Util::uniqify( \@query_ids ) };
    @mol_names = @{ &Common::Util::uniqify( \@mol_names ) };

    return ( \@query_ids, \@mol_names );
}

sub distill_sim_rows
{
    # Niels Larsen, February 2010.

    # The input is a list of matches for a given query id. The matches are 
    # given as an M8 blast table to which annotation string has been added 
    # as an extra last column:
    # 
    #   0: Query id
    #   1: Target id
    #   2: Percent identity
    #   3: Match (alignment) length
    #   4: Number of mismatches
    #   5: Number of opened gaps
    #   6: Match start on query
    #   7: Match end on query 
    #   8: Match start on target
    #   9: Match end on target
    #  10: E-value probability score
    #  11: Smith-Waterman score
    #  12: Molecule annotation string
    # 
    # The output has this reduced form,
    # 
    #   0: Query id
    #   1: Similarity percent
    #   2: Match length
    #   3: Number of mismatches
    #   4: Number of gaps 
    #   5: Query length 
    #   6: Target length 
    #   7: Target id 
    #   8: Molecule annotation string
    # 
    # Two filter criteria are used: minimum absolute percent similarity and
    # maximum difference between the best match and all others. Similarity 
    # percent is recalculated as "100 times the number of matches, divided 
    # by length of the shorter sequence". Then, multiple hits with the 
    # same annotation are condensed into one, the one that is least likely
    # to occur by chance. Finally the rows are sorted by similarity percent,
    # then query length.

    my ( $tab_rows,
         $args,
	) = @_;

    # Returns a list.
    
    my ( @matches, $match, $best_match, $score, $minlen, $simpct, %matches,
         @out_rows, $i, $ann, $mol_name, $min_sim, $annskip, $anntrans, 
         $max_rat, $tgt_mol, $mat_len, $row, $mat_num, $p_lowest, $ratio,
        );

    $min_sim = $args->min_sim;          # Min similarity percent
    $max_rat = $args->max_rat;          # Max p-value ratio between best and the rest
    $annskip = $args->ignore;           # List of annotation expressions to ignore - OPTIONAL
    $anntrans = $args->trans;           # Hash of function names => canonical name - OPTIONAL
    $tgt_mol = $args->tgt_mol;          # Dataset molecule name - OPTIONAL

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE FILTERED LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a list with matches over the given similarity percent minimum,

    @matches = ();

    for ( $i = 0; $i <= $#{ $tab_rows }; $i++ )
    {
        $row = $tab_rows->[$i];

	$simpct = &Seq::Classify::sim_from_m8_row( $row );
        
        if ( $simpct >= $min_sim )
        {
            $mol_name = $row->[12] // $tgt_mol // "";

            if ( $mol_name and exists $anntrans->{ $mol_name } ) {
                $mol_name = $anntrans->{ $mol_name };
            }

            if ( $mol_name and not &Common::Util::match_regexps( $mol_name, $annskip ) )
            {
                push @matches, {
                    "query_id" => $row->[0],
                    "query_len" => $row->[7] - $row->[6] + 1,
                    "target_id" => $row->[1],
                    "target_len" => $row->[9] - $row->[8] + 1,
                    "sim_pct" => $simpct,
                    "match_len" => $row->[3],
                    "mis_count" => $row->[4],
                    "gap_count" => $row->[5],
                    "mol_name" => $mol_name,
                };
            }
        }
    }

    return if not @matches;

    # >>>>>>>>>>>>>>>>>>>>>>>> FILTER BY PROBABILITY <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Add a p_value key, sort and cut off those that are max_rat more probable
    # to occur by chance,

    foreach $match ( @matches )
    {
        $mat_len = $match->{"match_len"};
        $mat_num = $mat_len - $match->{"mis_count"} - $match->{"gap_count"};

        $match->{"p_value"} = &Common::Util::p_bin_selection( $mat_num, $mat_len, 0.25 );
    }        
                
    @matches = sort { $a->{"p_value"} <=> $b->{"p_value"} } @matches;

    $p_lowest = $matches[0]->{"p_value"};

    for ( $i = 0; $i <= $#matches; $i++ )
    {
        $ratio = $matches[$i]->{"p_value"} / $p_lowest;
        
        if ( $ratio > $max_rat )
        {
            splice @matches, $i;
            last;
        }
    }

    return if not @matches;

    # >>>>>>>>>>>>>>>>>>>>> UNIQIFY TARGET ANNOTATIONS <<<<<<<<<<<<<<<<<<<<<<<<

    # Condense the rows so there is only one representative of each target 
    # molecule. Multiple representatives could for example be due to multiple 
    # organisms. The least likely match (by p_value from above) is taken, no
    # matter its length or match percent. It is debatable how this is best 
    # done. 

    %matches = ();

    foreach $match ( @matches )
    {
        push @{ $matches{ $match->{"mol_name"} } }, $match;
    }

    foreach $mol_name ( keys %matches )
    {
	@{ $matches{"mol_name"} } = sort { $a->{"p_value"} <=> $b->{"p_value"} } @{ $matches{ $mol_name } };
	
	$best_match = $matches{ $mol_name }->[0];

	push @out_rows,	[ 
	    $best_match->{"query_id"},     #  0
	    $best_match->{"sim_pct"},      #  1 
            $best_match->{"match_len"},    #  2 
            $best_match->{"mis_count"},    #  3
            $best_match->{"gap_count"},    #  4
	    $best_match->{"query_len"},    #  5
            $best_match->{"target_len"},   #  6
            $best_match->{"target_id"},    #  7
	    $mol_name,                     #  8
	];
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SORT ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sort the output rows by similarity, then query length,

    @out_rows = sort {
        $b->[1] <=> $a->[1] or $b->[5] <=> $a->[5]
    } @out_rows;

    if ( @out_rows ) {
	return wantarray ? @out_rows : \@out_rows;
    }
    
    return;
};

sub noclassify
{
    # Niels Larsen, August 2011.

    # Creates a fasta file with sequences that do not anything in a given
    # classification file. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $ifh, @line, @ids, $line, $count );

    local $Common::Messages::silent;

    $defs = {
        "clafile" => "",
        "seqfile" => "",
        "outfile" => "",
	"silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $Common::Messages::silent = $args->silent;

    &echo_bold("\nNo-match sequences:\n");

    &echo("   Finding no-match ids ... ");

    $ifh = &Common::File::get_read_handle( $args->clafile );

    while ( defined ( $line = <$ifh> ) )
    {
        @line = split "\t", $line;
        push @ids, $line[0] if $line[1] eq "";
    }

    &Common::File::close_handle( $ifh );

    &echo_done("done\n");
    
    &echo("   Writing sequences ... ");

    &Common::File::delete_file_if_exists( $args->outfile );

    $count = &Seq::IO::select_seqs_fasta( $args->seqfile, \@ids, undef, $args->outfile );

    &echo_done("done\n");
    
    &echo_bold("Finished\n\n");

    return $count;
}

sub process_args
{
    # Niels Larsen, February 2010.

    # Checks and expands the classify routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( $conf, @msgs, $config, $tuple, $usr_name, $field, $min, $max,
         $stats_file, $def );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIG FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->config ) {
        &Common::File::check_files( [ $args->config ], "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No configuration file given.) ];
        push @msgs, ["Tip", qq (See --help config for an example.) ];
    }

    &append_or_exit( \@msgs );
    
    $conf = &Common::Config::read_config_general( $args->config );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->ifiles and @{ $args->ifiles } ) {
	$conf->{"ifiles"} = &Common::File::check_files( $args->ifiles, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No input files given) ];
    }

    &append_or_exit( \@msgs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $tuple ( ["minsim", "min_sim", 70, 100, 90 ],
                     ["maxrat", "max_rat", 1, undef, 1000 ],
                     ["maxout", "max_out", 1, undef, 10 ] )
    {
        ( $usr_name, $field, $min, $max, $def ) = @{ $tuple };
        
        if ( defined $args->$usr_name ) {
            $conf->{ $field } = &Registry::Args::check_number( $args->$usr_name, $min, $max, \@msgs );
        } else {
            $conf->{ $field } //= $def;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->ofile and scalar @{ $conf->{"ifiles"} } == 1 ) {
        $conf->{"ofiles"} = [ $args->ofile ];
    } else {
        $conf->{"ofiles"} = [ map { $_. $args->osuffix } @{ $args->ifiles } ];
    }
    
    if ( not $args->clobber ) {
        &Common::File::check_files( $conf->{"ofiles"}, "!e", \@msgs );
    }

    &append_or_exit( \@msgs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->newstats or defined $args->stats )
    {
        $stats_file = $args->newstats || $args->stats;

        if ( scalar @{ $args->ifiles } == 1 and $stats_file ) {
            $conf->{"ostats"} = [ $stats_file ];
        } else {
            $conf->{"ostats"} = [ map { $_ . ".stats" } @{ $args->ifiles } ];
        }
    }
    else {
        $conf->{"ostats"} = [];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> EXPAND CONFIG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check and expand data files, programs and settings in the config file,
    # so that each dataset comparison is ready to go,

    $conf = &Seq::Classify::process_config( $conf, \@msgs );

    &append_or_exit( \@msgs );
    
    bless $conf;
    
    return wantarray ? %{ $conf } : $conf;
}

sub process_config
{
    # Niels Larsen, May 2011.

    # Reads and validates a configuration file. 

    my ( $conf,
         $msgs,
        ) = @_;

    my ( @msgs, $prog, $prog_args, $prog_path, $value, $dbs, $conf_trans,
         $db, $i, $arg, %prog_args, %db_prog_args, @prog_args, $db_trans, 
         $err, $seq_type );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This section checks the configuration hash in a few ways (not all).

    # General program name, only one allowed,

    if ( $prog = $conf->{"program"} )
    {
        if ( ref $prog ) {
            push @msgs, ["ERROR", qq (Only one program allowed in configuration) ];
        } else {
            &Common::OS::is_executable( $prog, \@msgs );
            $prog_path = $prog;
        }
    }
    else {
        push @msgs, ["ERROR", qq (No program field given in the configuration) ];
    }

    # Program arguments,

    if ( $prog_args = $conf->{"program_arguments"} )
    {
        $prog_args = [ $prog_args ] if not ref $prog_args;
    }
    else {
        push @msgs, ["ERROR", qq (No program_arguments field given in the configuration) ];
    }

    # No-match annotations,

    if ( $value = $conf->{"no_match"} and not ref $value )
    {
        $conf->{"no_match"} = [ $value ];
    }
    
    # Sequence type,
    
    if ( $seq_type = $conf->{"seq_type"} )
    {
        if ( &Common::Types::is_dna( $seq_type ) ) {
            $conf->{"itype"} = "dna_seq";
        } elsif ( &Common::Types::is_rna( $seq_type ) ) {
            $conf->{"itype"} = "rna_seq";
        } elsif ( &Common::Types::is_protein( $seq_type ) ) {
            $conf->{"itype"} = "rna_seq";
        } else {
            push @msgs, ["ERROR", qq (Wrong looking input sequence type. Choices: rna_seq, dna_seq, prot_seq) ];
        }            
    }
    else {
        push @msgs, ["ERROR", qq (Input sequence type not given. Choices: rna_seq, dna_seq, prot_seq) ];
    }

    # Datasets,
    
    if ( $dbs = $conf->{"datasets"} )
    {
        $dbs = [ $dbs ] if not ref $dbs eq "ARRAY";
        
        for ( $i = 0; $i <= $#{ $dbs }; $i ++ )
        {
            $db = $dbs->[$i];

            if ( not ( $value = $db->{"label"} ) ) {
                push @msgs, ["ERROR", qq (Dataset number $i has no label field in the configuration) ];
            }

            if ( not ( $value = $db->{"source"} ) ) {
                push @msgs, ["ERROR", qq (Dataset number $i has no source field in the configuration) ];
            }
            
            if ( $value = $db->{"no_match"} and not ref $value ) {
                $db->{"no_match"} = [ $value ];
            }

            if ( not $value = $db->{"mol_name"} ) {
                $db->{"mol_name"} = "";
            }
        }

        $conf->{"datasets"} = $dbs;
    }
    else {
        push @msgs, ["ERROR", qq (No datasets field given in the configuration) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CASCADE SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Copy general settings into each db hash where missing. If the user gives
    # a setting for a dataset, then that overrides the general ones. Dataset 
    # source names with wild-cards are expanded into file names for local 
    # datasets. 

    if ( $conf->{"trans_file"} )
    {
        $conf_trans = &Common::Table::read_table( $conf->{"trans_file"}, { "has_col_headers"=> 0 })->values;
        $conf_trans = { map { $_->[0], $_->[1] } @{ $conf_trans } };
    }
    else {
        $conf_trans = {};
    }

    foreach $db ( @{ $conf->{"datasets"} } )
    {
        # Convert local datasets to actual files,
        
        $db->{"files"} = [ map { {"name" => $_->[0], "path" => $_->[1] } }
                           @{ &Seq::Args::expand_paths( $db->{"source"}, \@msgs ) } ];
        
        map { $_->{"label"} = $db->{"label"} } @{ $db->{"files"} };

        # Set prog key to what was given with the dataset or to the general 
        # setting if any,

        if ( $db->{"program"} )
        {
            $db->{"prog"} = $db->{"program"};
            delete $db->{"program"};
        }
        elsif ( $prog_path ) {
            $db->{"prog"} = $prog_path;
        }

        if ( $db->{"program_arguments"} )
        {
            if ( ref ( $value = $db->{"program_arguments"} ) ) {
                $db->{"prog_args"} = $value;
            } else {
                $db->{"prog_args"} = [ $value ];
            }

            delete $db->{"program_arguments"};
        }
        
        # Merge program arguments into each dataset, but only if the program is 
        # the same as the overall one, and overall arguments are given,

        if ( $db->{"prog"} eq $prog_path and $prog_args )
        {
            %db_prog_args = ();
            @prog_args = ();

            foreach $arg ( @{ $db->{"prog_args"} } ) {
                $arg =~ /^(\S+) *(\S*)$/ and ( $db_prog_args{ $1 } = $2 // "" );
            }

            foreach $arg ( @{ $prog_args } ) {
                $arg =~ /^(\S+) *(\S*)$/ and push @prog_args, [ $1, $2 // "" ];
            }
            
            # Override user and set to M8, 

            @prog_args = grep { $_->[0] !~ /^--(om|omode|outmode)$/i } @prog_args;
            push @prog_args, ["--outmode", "M8"];

            foreach $arg ( @prog_args )
            {
                if ( exists $db_prog_args{ $arg->[0] } ) {
                    $arg->[1] = $db_prog_args{ $arg->[0] };
                }

                if ( $arg->[1] eq "" ) {
                    $arg = $arg->[0];
                } else {
                    $arg = $arg->[0] ." ". $arg->[1];
                }
            }
            
            $db->{"prog_args"} = &Storable::dclone( \@prog_args );
        }

        # Annotation expressions to ignore: simply add the overall ones to each
        # database, but remove duplicates,
        
        if ( $conf->{"no_match"} ) {
            push @{ $db->{"no_match"} }, @{ $conf->{"no_match"} };
        }

        # Annotation translations: simply add the overall ones to each database, 
        # but remove duplicates,
        
        if ( $db->{"trans_file"} )
        {
            $db_trans = &Common::Table::read_table( $db->{"trans_file"}, { "has_col_headers" => 0 })->values;
            $db_trans = { map { $_->[0], $_->[1] } @{ $db_trans } };

            $db->{"trans"} = { %{ $conf_trans }, %{ $db_trans } };
            delete $db->{"trans_file"};
        }
        else {
            $db->{"trans"} = { %{ $conf_trans } };
        }
        
        if ( $db->{"no_match"} and @{ $db->{"no_match"} } ) {
            $db->{"no_match"} = &Common::Util::uniqify( $db->{"no_match"} );
        } else {
            $db->{"no_match"} = [];
        }

        # Filtration settings,

        foreach $arg ( qw ( min_sim max_rat max_out ) )
        {
            if ( not exists $db->{ $arg } ) {
                $db->{ $arg } = $conf->{ $arg };
            }
        }
    }

    delete $conf->{"program"};
    delete $conf->{"program_arguments"};
    delete $conf->{"no_match"};
    delete $conf->{"min_sim"};
    delete $conf->{"max_rat"};
    delete $conf->{"max_out"};
    delete $conf->{"seq_type"};

    map { bless $_ } @{ $conf->{"datasets"} };

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? %{ $conf } : $conf;
}

sub sim_from_m8_row
{
    # Niels Larsen, July 2011.

    # Creates a similarity percentage from a given M8 table row. In 
    # M8 table format we can use these columns directory,
    #
    #   0 = Query ID
    #   1 = Target ID
    #   3 = Alignment length
    #   4 = Number of mismatches
    #   5 = Number of gaps
    # 
    # but there are no query and target lengths, so we must calculate 
    # those from start and end positions,
    #
    #   6: Match start on query
    #   7: Match end on query 
    #   8: Match start on target
    #   9: Match end on target

    my ( $row,
        ) = @_;

    my ( $minlen, $matches, $sim );

    if ( not ref $row ) {
        chomp $row;
        $row = [ split "\t", $row ];
    }

    $minlen = &List::Util::min( $row->[7] - $row->[6], $row->[9] - $row->[8] ) + 1;
    $matches = $row->[3] - $row->[5] - $row->[4];

    $sim = sprintf "%.2f", (100 * $matches / $minlen);

    return $sim;
}
    
sub write_cla_table
{
    # Niels Larsen, May 2011.

    # Writes a tab-separated classification table with these columns:
    # 
    #   Q-count            Query multiplicity count
    #   Q-ID               Query sequence id
    #   Sim%               Similarity percent
    #   M-len              Match length
    #   Mism               Number of mismatches
    #   Gaps               Number of indels and gaps
    #   Q-len              Query sequence length
    #   T-len              Target sequence length
    #   T-DB               Target dataset name
    #   T-ID               Target sequence id
    #   T-annotation       Target sequence function annotation
    # 
    # The first table line has the above headers. The query sequences
    # have the same order as in the original query file. 

    my ( $args,
        ) = @_;

    my ( $dbm_file, $cla_file, $ids, $id, $dbh, $ofh, $list,
         $hits, $nohits, $seq_fh, $seq, $id_tuples, $tuple );

    $id_tuples = $args->seq_counts;
    $dbm_file = $args->dbm_file;
    $cla_file = $args->cla_file;

    # Write output table,

    $dbh = &Common::DBM::read_open( $dbm_file );
    $ofh = &Common::File::get_write_handle( $cla_file );

    $ofh->print("# Q-count\tQ-ID\tSim%\tM-len\tMism\tGaps\tQ-len\tT-len\tT-DB\tT-ID\tT-annotation\n");

    $hits = 0;
    $nohits = 0;
    
    foreach $tuple ( @{ $id_tuples } )
    {
	if ( $list = &Common::DBM::get_struct( $dbh, $tuple->[0], 0 ) )
	{
	    map { $ofh->print( "$tuple->[1]\t$_\n" ) } @{ $list };
            $hits += 1;
	}
	else {
	    $ofh->print( "$tuple->[1]\t$tuple->[0]\t\t\t\t\t\t\t\t\t\n" );
            $nohits += 1;
	}
    }

    &Common::DBM::close( $dbh );
    &Common::File::close_handle( $ofh );

    return ( $hits, $nohits );
}
    
1;

__END__

