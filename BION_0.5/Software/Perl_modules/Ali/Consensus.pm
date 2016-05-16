package Ali::Consensus;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that have to do with alignment consensus.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use feature "state";
use Fcntl qw ( SEEK_SET SEEK_CUR SEEK_END );

use Time::Duration qw ( duration );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Names;
use Common::Types;
use Common::DBM;

use Registry::Args;

use Ali::Common;
use Ali::Storage;
use Ali::Stats;

use Recipe::IO;
use Recipe::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our ( @Functions );

@Functions = (
    [ "consenses",               "Consenses from multiple files" ],
    [ "consenses_args",          "Checks arguments and returns config hash" ],
    [ "consenses_file",          "Consenses from a single file" ],
    [ "create_consensus",        "Create a consensus string from column statistics" ],
    [ "write_consenses_fasta",   "Writes consenses from statistics in fasta format" ],
    [ "write_consenses_table",   "Writes consenses from statistics in table format" ],
    [ "write_stats_file",        "Writes statistics to file" ],
    [ "write_stats_sum",         "Writes summary statistics" ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub consenses
{
    # Niels Larsen, September 2010.

    # Writes consenses from multiple files in different formats.

    my ( $args,       # Arguments hash
	) = @_;

    # Returns nothing.
    
    my ( $defs, $silent, $i, %args, $oname, $stats, $stat, $ifile, $conf, 
         $count, $iname, @ofiles, $oformat, $ofile, $routine, $iformat,
         $cons_list, $counts_in, $seq_count, $sfile, $clobber, $recipe,
         $time_start, $method, $indexed );

    local $Common::Messages::silent;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "ifile" => undef,
	"seqtype" => "dna",
        "qualtype" => "Illumina_1.8",
        "ofasta" => undef,
        "ofastq" => undef,
        "otable" => undef,
        "osuffix" => undef,
        "ostats" => undef,
        "method" => "most_frequent",
        "minseqs" => 1,
        "minres" => 5,
        "minqual" => 99.9,
        "mincons" => 0,
        "minqcons" => 20,
        "ambcover" => 90,
        "trimbeg" => 1,
        "trimend" => 1,
        "maxfail" => 5,
        "maxqfail" => 5,
        "minlen" => 15,
        "clobber" => 0,
        "silent" => 0,
    };

    # Check arguments and exit if errors,

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Ali::Consensus::consenses_args( $args );

    $Common::Messages::silent = $args->silent;

    $clobber = $args->clobber;

    $time_start = &Common::Messages::time_start();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nCreating consenses:\n) );
    
    $ifile = $conf->ifile;
    $sfile = $conf->ostats;
    
    $iformat = &Ali::IO::detect_format( $ifile );
    $iname = &File::Basename::basename( $ifile );

    # >>>>>>>>>>>>>>>>>>>>>>> INDEX ALIGNMENT FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( not &Ali::Storage::is_indexed( $ifile, { "keys" => ["ali_ents","seq_ents"] } ) )
    {
        &echo( qq (   Indexing $iname ... ) );
        
        &Ali::Storage::create_indices(
             {
                 "ifiles" => [ $ifile ],
                 "seqents" => 1,
                 "seqstrs" => 0,
                 "silent" => 1,
                 "clobber" => 1,
             });
        
        &echo_done( "done\n" );

        $indexed = 1;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>> COUNT INPUT ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<

    if ( $sfile )
    {
        &echo( qq (   Counting $iname ... ) );
        $counts_in = &Ali::IO::count_alis( $ifile );

        if ( defined ( $seq_count = $counts_in->{"seq_count_orig"} ) )
        {
            $counts_in->{"seq_count"} = $seq_count;
            delete $counts_in->{"seq_count_orig"};
        }
        
        &echo_done( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>> CALCULATE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Returns a list of column statistics hashes:
    #
    #  ali_id             Alignment id
    #  col_stats          2d statistics (columns x alphabet size + 3)
    #  col_count          Number of alignment columns
    #  row_count          Number of alignment rows
    #  seq_count          Number of sequences (adds up seq_count=nn info)
    
    &echo( "   Calculating consenses ... ");
    
    $cons_list = &Ali::Consensus::consenses_file(
        $ifile,
        {
            "seq_type" => $conf->seqtype,
            "qual_type" => $conf->qualtype,
            "seq_min" => $conf->minseqs,
            "ali_format" => $iformat,
            "stat_file" => $sfile,
            "method" => $conf->method,
            "res_pct_min" => $conf->minres,
            "qual_pct_min" => $conf->minqual,
            "cons_pct_min" => $conf->mincons,
            "qcons_pct_min" => $conf->minqcons,
            "iub_pct_min" => $conf->ambcover,
            "trim_beg" => $conf->trimbeg,
            "trim_end" => $conf->trimend,
            "fail_pct_max" => $conf->maxfail,
            "qfail_pct_max" => $conf->maxqfail,
            "cons_len_min" => $conf->minlen,
        });
    
    $count = scalar @{ $cons_list };
    
    if ( $count == 0 ) {
        &echo_yellow("none\n");
    } else {
        &echo_done("$count\n");
    }

    # >>>>>>>>>>>>>>>>>>>> DELETE INDEX IF CREATED ABOVE <<<<<<<<<<<<<<<<<<<<<<

    # if ( $indexed ) 
    # {
    #     &echo("   Deleting alignment index ... ");
    #     &Common::File::delete_file_if_exists( $ifile . $Ali::Storage::Index_suffix );
    #     &echo_done("done\n");
    # }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE CONSENSES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( defined $cons_list and @{ $cons_list } )
    {
        # Write the strings in different formats,

        if ( $ofile = $conf->ofasta )
        {
            $oname = &File::Basename::basename( $ofile );
            &echo( "   Writing $oname ... " );
            
            &Common::File::delete_file_if_exists( $ofile ) if $clobber;
            &Ali::Consensus::write_consenses_fasta( $cons_list, $ofile );
            
            &echo_green("done\n");
        }

        if ( $ofile = $conf->otable )
        {
            $oname = &File::Basename::basename( $ofile );
            &echo( "   Writing $oname ... " );
            
            &Common::File::delete_file_if_exists( $ofile ) if $clobber;
            &Ali::Consensus::write_consenses_table( $cons_list, $ofile );
            
            &echo_green("done\n");
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $sfile )
    {
        &echo( qq (   Writing statistics ... ) );

        $stats = {
            "name" => defined $recipe ? $recipe->{"name"} : "alignment-consensus",
            "title" => defined $recipe ? $recipe->{"title"} : "Alignment consenses",
            "ifile" => $ifile,
            "clu_in" => $counts_in->{"ali_count"},
            "seq_in" => $counts_in->{"seq_count"},
            "clu_out" => scalar @{ $cons_list },
            "seq_out" => &List::Util::sum( map { $_->{"seq_count"} } @{ $cons_list } ),
            "seconds" => time() - $time_start,
            "finished" => &Common::Util::epoch_to_time_string(),
        };

        $method = $conf->method;

        if ( $method eq "most_frequent" ) {
            $stats->{"method"} = "Most frequent residue";
        } elsif ( $method eq "least_ambiguous" ) {
            $stats->{"method"} = "Most conserved ambiguity";
        } elsif ( $method eq "most_frequent_any" ) {
            $stats->{"method"} = "Most frequent character";
        } else {
            &error( qq (Unknown method -> "$method") );
        }

        $stats->{"params"} = [
            {
                "title" => "Minimum sequences in cluster",
                "value" => $conf->{"minseqs"},
            },{
                "title" => "Minimum non-gaps in columns",
                "value" => $conf->{"minres"} ."%",
            },{
                "title" => "Minimum base quality",
                "value" => $conf->{"minqual"} ."%",
            },{
                "title" => "Minimum conservation in columns",
                "value" => $conf->{"mincons"} ."%",
            },{
                "title" => "Minimum good quality in columns",
                "value" => $conf->{"minqcons"} ."%",
            },{
                "title" => "Maximum columns sequence fail",
                "value" => $conf->{"maxfail"} ."%",
            },{
                "title" => "Maximum columns quality fail",
                "value" => $conf->{"maxqfail"} ."%",
            },{
                "title" => "Trim consensus start",
                "value" => $conf->{"trimbeg"} ? "yes" : "no",
            },{
                "title" => "Trim consensus end",
                "value" => $conf->{"trimend"} ? "yes" : "no",
            },{
                "title" => "Minimum consensus length",
                "value" => $conf->{"minlen"},
            }];

        if ( $method eq "least_ambiguous" )
        {
            push @{ $stats->{"params"} }, {
                "title" => "Minimum ambiguity coverage",
                "value" => $conf->{"ambcover"} ."%",
            };
        }
        
        if ( $conf->ofasta ) {
            push @{ $stats->{"ofiles"} }, { "title" => "Fasta output", "value" => $conf->ofasta };
        }

        if ( $conf->otable ) {
            push @{ $stats->{"ofiles"} }, { "title" => "Table output", "value" => $conf->otable };
        }

        &Ali::Consensus::write_stats_file( $sfile, $stats );
        
        &echo_done( "done\n" );
    }
    
    &echo("   Time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );
    
    &echo_bold("Finished\n\n") unless $silent;

    return;
}

sub consenses_args
{
    # Niels Larsen, September 2010.

    # Checks arguments and returns a hash with settings that the routines need.
    # If errors these are printed and the routine exits. 

    my ( $args,      # Arguments hash
         $msgs,      # Outgoing messages
	) = @_;

    # Returns object.

    my ( @msgs, @ofiles, %params, $param, @valid, @values, $value, $key, $ifile,
         $oformat, $ofile, @iformats, $format, $conf, $stat_file );

    @msgs = ();

    # Input file must be readable,

    if ( $args->ifile ) {
	$conf->{"ifile"} = &Common::File::check_files([ $args->ifile ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", "No input file given"];
    }

    # Input sequence type must be valid,
    
    $conf->{"seqtype"} = &Seq::Args::canonical_type( $args->seqtype, \@msgs );

    # Input quality type must be valid,

    $conf->{"qualtype"} = &Seq::Args::check_qualtype( $args->qualtype, \@msgs );

    # Input format,
    
    @iformats = qw ( uclust fasta );
    $ifile = $args->ifile;

    $format = &Ali::IO::detect_format( $ifile );
        
    if ( not $format ~~ @iformats ) {
        push @msgs, ["ERROR", qq (Format "$format" not supported -> "$ifile") ];
    }
    
    &append_or_exit( \@msgs );

    # Parameters that take single options,

    %params = (
        "method" => [ qw ( most_frequent most_frequent_any least_ambiguous ) ],
        );

    foreach $param ( keys %params )
    {
        @valid = @{ $params{ $param } };
        @values = split /\s*,\s*/, ( $args->$param // "" );

        if ( @values )
        {
            foreach $value ( @values )
            {
                if ( not grep { $_ eq $value } @valid )
                {
                    push @msgs, ["ERROR", qq (Wrong looking $param -> "$value". Choices are:) ],
                                ["", '"'. ( join '", "', @valid ) .'"' ];
                }
            }
        }
        else {
            push @msgs, ["ERROR", "No $param value is given" ];
        }

        $conf->{ $param } = $args->$param;
    }

    &append_or_exit( \@msgs, $msgs );

    # Check all percentages are within range,

    foreach $key ( qw ( minres minqual mincons minqcons ambcover maxfail maxqfail ) )
    {
        if ( defined $args->$key ) {
            $conf->{ $key } = &Registry::Args::check_number( $args->$key, 0, 100, \@msgs );
        }
    }

    # Check minseqs and other open ended numbers,

    if ( defined $args->minseqs ) {
        $conf->{"minseqs"} = &Registry::Args::check_number( $args->minseqs, 1, undef, \@msgs );
    }

    if ( defined $args->minlen ) {
        $conf->{"minlen"} = &Registry::Args::check_number( $args->minlen, 1, undef, \@msgs );
    }

    # Output files,

    if ( defined $args->ofasta )
    {
        if ( $args->ofasta ) {
            $conf->{"ofasta"} = $args->ofasta;
        } else {
            $conf->{"ofasta"} = $args->ifile .".confa";
        }

        push @ofiles, $conf->{"ofasta"};
    }
    else {
        $conf->{"ofasta"} = undef;
    }
    
    if ( defined $args->ofastq )
    {
        if ( $args->ofastq ) {
            $conf->{"ofastq"} = $args->ofastq;
        } else {
            $conf->{"ofastq"} = $args->ifile .".confq";
        }

        push @ofiles, $conf->{"ofastq"};
    }
    else {
        $conf->{"ofastq"} = undef;
    }
    
    if ( defined $args->otable )
    {
        if ( $args->otable ) {
            $conf->{"otable"} = $args->otable;
        } else {
            $conf->{"otable"} = $args->ifile .".contab";
        }

        push @ofiles, $conf->{"otable"};
    }
    else {
        $conf->{"otable"} = undef;
    }

    if ( @ofiles )
    {
        if ( not $args->clobber ) {
            &Common::File::check_files( \@ofiles, "!e", \@msgs );
        }
    }
    else {
        push @msgs, ["ERROR", qq (No output files given, use --ofasta and/or --otable) ];
    }
    
    # Statistics files,

    if ( defined ( $stat_file = $args->ostats ) )
    {
        if ( $args->ostats ) {
            $conf->{"ostats"} = $args->ostats;
        } else {
            $conf->{"ostats"} = $args->ifile .".stats";
        }
    }
    else {
        $conf->{"ostats"} = undef;
    }

    # Print errors and exit if any,

    &append_or_exit( \@msgs, $msgs );

    $conf->{"trimbeg"} = $args->trimbeg;
    $conf->{"trimend"} = $args->trimend;

    return bless $conf;
}

sub create_consensus
{
    # Niels Larsen, September 2010.

    # Creates a list of 3-element tuples where elements are:
    # 
    # Index 0: consensus character
    # Index 1: 1 or 0, depending whether sequence criteria are met or not
    # Index 2: 1 or 0, depending whether quality criteria are met or not 
    # 
    # These masks are then use to trim and filter the consensus in separate 
    # steps, and to make outputs from.

    my ( $stats,        # Statistics list of lists
         $args,         # Arguments hash
         $msgs,         # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a string. 

    my ( $res_max_ndx, $stat, @cons, $seq_type, $method, $ndx_str, $res_rat,
         $ndcs, $vals, $cons, $res_ndx, $res_sum, $iub_ratio, $col, $cons_rat,
         $badch, $okch, $flag, $seq_total, $col_stats, $ndx_mfreq, $res_mfreq,
         $iub_min, $qual_min, $qual_counts, $i, $qual_rat, $res_sum_qual );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CONVENIENCE VARIABLES <<<<<<<<<<<<<<<<<<<<<<<<
    
    $col_stats = $stats->{"col_stats"};

    if ( not @{ $col_stats } ) {
        return wantarray ? () : [];
    }

    $seq_type = $args->seq_type;
    $method = $args->method;
    $res_rat = $args->res_rat;
    $qual_rat = $args->qual_rat;
    $qual_min = $args->qual_min;
    $cons_rat = $args->cons_rat;
    $iub_min = $args->iub_min;
        
    $res_max_ndx = scalar @{ $col_stats->[0] } - 4; # Three last indices are gap characters
    @cons = ();
    
    state $alphabet = [ split "", &Ali::Common::alphabet_stats( $seq_type ) ];
    state $iub_hash = &Seq::Common::iub_codes_num( $seq_type );

    if ( $method eq "most_frequent_any" )
    {
        # >>>>>>>>>>>>>>>>>>>>>> MOST FREQUENT CHARACTER <<<<<<<<<<<<<<<<<<<<<<

        # This simply uses the most frequent character whatever that is, gaps
        # included.

        foreach $stat ( @{ $col_stats } )
        {
            if ( &List::Util::sum( $stat ) > 0 ) {
                $flag = 1;
            } else {
                $flag = 0;
            }

            push @cons, [ $alphabet->[ &Common::Util::max_list_index( $stat ) ], $flag ];
        }
    }
    elsif ( $method eq "most_frequent" )
    {
        # >>>>>>>>>>>>>>>>>>>>> MOST FREQUENT BASE/RESIDUE <<<<<<<<<<<<<<<<<<<<

        # As the above, except the consensus only has a '-' where there are no
        # residues. If there are one or more residues, then the most frequent 
        # of these are used.

        $seq_total = $stats->{"seq_count"};

        foreach $col ( @{ $col_stats } )
        {
            $stat = [ @{ $col }[ 0 .. $res_max_ndx ] ];

            $res_sum = &List::Util::sum( @{ $stat } );

            $ndx_mfreq = ( sort { $stat->[$a] <=> $stat->[$b] } ( 0 .. $#{ $stat } ) )[-1];
            $res_mfreq = $stat->[$ndx_mfreq];   # Most frequent character

            if ( $res_sum > 0 and
                 ( $res_sum / $seq_total >= $res_rat ) and 
                 ( $res_mfreq / $res_sum >= $cons_rat ) )
            {
                $flag = 1;
            } else {
                $flag = 0;
            }

            push @cons, [ $alphabet->[ $ndx_mfreq ], $flag ];
        }
    }
    elsif ( $method eq "least_ambiguous" )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>> WITH IUB CODES <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # This works only for DNA/RNA and folds bases into ambiguity codes. It
        # works as "most_frequent_seq", but it keeps making the base code more
        # ambiguous until "iub_pct_min" of the bases are covered. 

        if ( &Common::Types::is_protein( $seq_type ) ) {
            &error( qq (The "least_ambiguous" consensus mode can only be used with DNA/RNA alignments) );
        }
        
        foreach $col ( @{ $col_stats } )
        {
            $stat = [ @{ $col }[ 0 .. $res_max_ndx ] ];   # Residue counts
            $res_sum = &List::Util::sum( @{ $stat } );    # Residue count sum

            if ( $res_sum > 0 ) 
            {
                $vals = [ sort { $a <=> $b } @{ $stat } ];
                $ndcs = [ sort { $stat->[$a] <=> $stat->[$b] } ( 0 .. $#{ $stat } ) ];

                $ndx_str = $ndcs->[$res_max_ndx];
                $res_ndx = $res_max_ndx - 1;
                
                $cons = $vals->[$res_max_ndx];
                
                while ( $res_ndx >= 0 and $cons < ( $res_sum * $iub_min ) )
                {
                    $cons += $vals->[$res_ndx];
                    $ndx_str .= $ndcs->[$res_ndx];
                    
                    $res_ndx -= 1;
                }

                push @cons, [ $iub_hash->{"$ndx_str"}, 1 ];
            }
            else {
                push @cons, [ "N", 0 ];
            }
        }
    }
    else {
        &error( qq (Wrong looking consensus mode -> "$method"\n)
               .qq (Choices are: most_frequent_any, most_frequent_seq, least_ambiguous_seq) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> QUALITY MASK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Set mask flags to 1 where the number of high-quality residues satisfies 
    # the minimum, 0 otherwise,

    if ( $qual_counts = $stats->{"qual_counts"} and defined $qual_min )
    {
        for ( $i = 0; $i <= $#{ $qual_counts }; $i ++ )
        {
            # Count all residues,
            
            $res_sum = &List::Util::sum( @{ $col_stats->[$i] }[ 0 .. $res_max_ndx ] );

            if ( $res_sum )
            {
                # Get high-quality residue count,

                $res_sum_qual = $qual_counts->[$i];
                
                # If the ratio between quality and total residues is as required, 
                # set to 1, otherwise 0,
                
                $cons[$i]->[2] = ( $res_sum_qual / $res_sum >= $qual_rat ) ? 1 : 0;
            } 
            else {
                $cons[$i]->[2] = 0;
            }
        }
    }

    return wantarray ? @cons : \@cons;
}

sub consenses_file
{
    # Niels Larsen, April 2011. 

    # Creates column statistics for indexed alignment files. 
    
    my ( $file,         # Uclust alignments file path
         $args,         # Arguments hash
        ) = @_;

    # Returns list.

    my ( $defs, @stats, $cursor, $seq_count, $conf, $seq_type, $seq_min, $fhs, 
         $ali_handle, $ndx_handle, $byt_pos, $ali_str, $str_len, $ali, $cons, 
         $qual_pct_min, $parse_routine, $col_stats, $ali_format, $cons_args, 
         $cons_str, $ali_id, $ali_where, $trim_args, $trim_flag, $stat_args,
         $stats_routine, $stats, $res_rat, $cons_mask, $cons_mask_str, $qual_mask,
         $len_min, $bad_max, $cons_len, $bad_count, $qual_mask_str, $trim_beg, 
         $trim_end, $cons_badpct, $stat, $i, @ndcs, $fail_max, $failq_max, 
         $fail_count, $failq_count, $consq_badpct, $consarr, $stat_file,
         $qual_type );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "seq_type" => "dna_seq",
        "qual_type" => undef,
        "seq_min" => 1,
        "ali_format" => undef,
        "method" => undef,
        "stat_file" => undef,
        "res_pct_min" => undef,
        "qual_pct_min" => undef,
        "cons_pct_min" => undef,
        "qcons_pct_min" => undef,
        "iub_pct_min" => undef,
        "trim_beg" => undef,
        "trim_end" => undef,
        "fail_pct_max" => undef,
        "qfail_pct_max" => undef,
        "cons_len_min" => undef,
    };
    
    $conf = &Registry::Args::create( $args, $defs );

    $seq_min = $conf->seq_min;
    $seq_type = $conf->seq_type;
    $qual_type = $conf->qual_type;
    $ali_format = $conf->ali_format;
    $res_rat = $conf->res_pct_min / 100;
    $len_min = $conf->cons_len_min;
    $fail_max = $conf->fail_pct_max;
    $failq_max = $conf->qfail_pct_max;
    $trim_beg = $conf->trim_beg;
    $trim_end = $conf->trim_end;
    $stat_file = $conf->stat_file;

    if ( not &Ali::Storage::is_indexed( $file ) ) {
        &error( qq (Alignment file not indexed -> "$file") );
    }

    $cons_args = {
        "seq_type" => $seq_type,
        "qual_type" => $qual_type,
        "method" => $conf->method,
        "res_rat" => $conf->res_pct_min / 100,
        "cons_rat" => $conf->cons_pct_min / 100,
        "qual_rat" => $conf->qcons_pct_min / 100,
        "iub_min" => $conf->iub_pct_min / 100,
    };

    if ( defined ( $qual_pct_min = $conf->qual_pct_min ) ) {
        $cons_args->{"qual_min"} = $conf->qual_pct_min / 100;
    } else {
        $cons_args->{"qual_min"} = undef;
    }

    bless $cons_args;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SET ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $ali_format eq "uclust" ) {
        $parse_routine = "Ali::Common::parse_uclust";
    } elsif ( $ali_format eq "fasta" ) {
        $parse_routine = "Ali::Common::parse_fasta";
    } else {
        &error( qq (Programmer must add format -> "$ali_format") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> COUNT COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get all offsets first,

    $fhs = &Ali::Storage::get_handles( $file );

    $ali_handle = $fhs->ali_handle;
    $ndx_handle = $fhs->ndx_handle;
    
    $cursor = $ndx_handle->cursor;
    $cursor->jump();

    while ( ( $ali_id, $ali_where ) = $cursor->get( 1 ) )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>> GET ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Skip config key and sequence keys .. this isnt robust,

        next if $ali_id =~ /__|:/;

        # Fetch alignment string,

        ( $byt_pos, $str_len ) = split "\t", $ali_where;
        
        seek( $ali_handle, $byt_pos, SEEK_SET );
        read( $ali_handle, $ali_str, $str_len );

        # Parse alignment string,

        no strict "refs";

        $ali = $parse_routine->( \$ali_str );

        $ali->datatype( $seq_type );

        # >>>>>>>>>>>>>>>>>>>>>>>> CREATE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<

        # Create statistics hash with these keys,
        # 
        #  col_stats          2d statistics (coluns x alphabet size + 3)
        #  col_count          Number of alignment columns
        #  row_count          Number of alignment rows
        #  seq_count          Number of sequences

        $ali = &Ali::Common::add_padding( $ali );

        if ( $ali->{"info"} and $ali->{"info"}->[0] =~ /seq_quals=/ ) {
            $stats_routine = "Ali::Stats::col_stats_qual";
        } else {
            $stats_routine = "Ali::Stats::col_stats";
        }

        $stats = &{ $stats_routine }( $ali, $qual_pct_min, $qual_type );

        undef $ali;

        # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE CONSENSUS <<<<<<<<<<<<<<<<<<<<<<<<<<

        $seq_count = $stats->seq_count;

        if ( $seq_count >= $seq_min )
        {
            # Delete columns where there are too few residues, whether they
            # are at the ends or in the middle,

            $stats = &Ali::Stats::splice_stats( $stats, $res_rat );
                
            # Create a list of consensus characters and a parallel mask-list 
            # of numbers with these meanings,
            # 
            #   0 = is bad in some other way (should be reflected in the output)
            #   1 = good to keep
            # 

            $consarr = &Ali::Consensus::create_consensus( $stats, $cons_args );

            # >>>>>>>>>>>>>>>>>>>>>>>>>> TRIM ENDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( @{ $consarr } and $trim_beg )
            {
                if ( scalar @{ $consarr->[0] } > 2 ) {
                    while ( @{ $consarr } and ( $consarr->[0]->[1] == 0 or $consarr->[0]->[2] == 0 ) ) { shift @{ $consarr } };
                } else {
                    while ( @{ $consarr } and $consarr->[0]->[1] == 0 ) { shift @{ $consarr } };
                }                    
            }
    
            if ( @{ $consarr } and $trim_end )
            {
                if ( scalar @{ $consarr->[0] } > 2 ) {
                    while ( @{ $consarr } and ( $consarr->[-1]->[1] == 0 or $consarr->[-1]->[2] == 0 ) ) { pop @{ $consarr } };
                } else {
                    while ( @{ $consarr } and $consarr->[-1]->[1] == 0 ) { pop @{ $consarr } };
                }
            }
            
            # >>>>>>>>>>>>>>>>>>>>>>>>> MAKE STRINGS <<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( @{ $consarr } )
            {
                $cons_len = scalar @{ $consarr };
                
                $cons = [ map { $_->[0] // 0 } @{ $consarr } ];
                $cons_mask = [ map { $_->[1] } @{ $consarr } ];

                $fail_count = scalar grep { $_ == 0 } @{ $cons_mask };
                $cons_badpct = 100 * $fail_count / $cons_len;

                $cons_str = join "", @{ $cons };

                $cons_mask_str = join "", @{ $cons_mask };
                $cons_mask_str =~ tr/01/X-/;

                if ( scalar @{ $consarr->[0] } > 2 )
                {
                    $qual_mask = [ map { $_->[2] } @{ $consarr } ];

                    $failq_count = scalar grep { $_ == 0 } @{ $qual_mask };
                    $consq_badpct = 100 * $failq_count / $cons_len;

                    $qual_mask_str = join "", @{ $qual_mask };
                    $qual_mask_str =~ tr/01/o-/;
                }
                else
                {
                    $qual_mask_str = "";
                    $consq_badpct = 0;
                }
                
                # >>>>>>>>>>>>>>>>>>>>> USE CONSTRAINTS <<<<<<<<<<<<<<<<<<<<<<<

                if ( $cons_badpct <= $fail_max and 
                     $consq_badpct <= $failq_max and
                     $cons_len >= $len_min )
                {
                    push @stats, bless {
                        "ali_id" => $ali_id,
                        "cons_str" => $cons_str,
                        "cons_mask" => $cons_mask_str,
                        "qual_mask" => $qual_mask_str,
                        "seq_count" => $stats->seq_count,
                        "row_count" => $stats->row_count,
                        "col_count" => $stats->col_count,
                    };
                }
            }
        }
    }

    &Ali::Storage::close_handles( $fhs );

    return wantarray ? @stats : \@stats;
}

sub write_consenses_fasta
{
    # Niels Larsen, September 2010.

    # Writes a list of [ id, consensus string, sequence count ] to file in 
    # fasta format. 
    
    my ( $cons,         # Consensus list
         $ofile,        # Output file
        ) = @_;

    # Returns nothing.

    my ( $ofh, $con, $seq );

    $ofh = &Common::File::get_write_handle( $ofile );

    if ( $cons->[0]->qual_mask )
    {
        foreach $con ( @{ $cons } )
        {
            $seq = Seq::Common->new(
                {
                    "id" => $con->ali_id,
                    "info" => Seq::Info->new({ "seq_count" => $con->seq_count, 
                                               "seq_mask" => $con->cons_mask,
                                               "qual_mask" => $con->qual_mask }),
                    "seq" => $con->cons_str,
                });
            
            &Seq::IO::write_seq_fasta( $ofh, $seq );
        }
    }
    else
    {
        foreach $con ( @{ $cons } )
        {
            $seq = Seq::Common->new(
                {
                    "id" => $con->ali_id,
                    "info" => Seq::Info->new({ "seq_count" => $con->seq_count, 
                                               "seq_mask" => $con->cons_mask }),
                    "seq" => $con->cons_str,
                });
            
            &Seq::IO::write_seq_fasta( $ofh, $seq );
        }
    }
        
    $ofh->close;
    
    return;
}

sub write_consenses_table
{
    # Niels Larsen, September 2010.

    # Writes a list of [ id, consensus string, sequence count ] to file in 
    # table format. 
    
    my ( $cons,         # Consensus list
         $ofile,        # Output file
        ) = @_;

    # Returns nothing.

    my ( $ofh, $con, @row );

    $ofh = &Common::File::get_write_handle( $ofile );

    if ( $cons->[0]->qual_mask )
    {
        foreach $con ( @{ $cons } )
        {
            @row = ( $con->ali_id, $con->seq_count, $con->cons_str, $con->cons_mask, $con->qual_mask );
            $ofh->print( (join "\t", @row) ."\n" );
        }
    }
    else
    {
        foreach $con ( @{ $cons } )
        {
            @row = ( $con->ali_id, $con->seq_count, $con->cons_str, $con->cons_mask );
            $ofh->print( (join "\t", @row) ."\n" );
        }
    }
    
    $ofh->close;
    
    return;
}

sub write_stats_file
{
    # Niels Larsen, February 2012. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $fh, $text, $time, $clu, $seq, $clu_pct, $seq_pct, $file, $fstr, 
         $istr, $item, $title, $value, $clu_dif, $seq_dif, $secs );

    $time = &Time::Duration::duration( $stats->{"seconds"} );
    $secs = $stats->{"seconds"};

    $fstr = "";
    $istr = "";

    # >>>>>>>>>>>>>>>>>>>>>>>> FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $file ( @{ $stats->{"ofiles"} } )
    {
        $title = $file->{"title"};
        $value = &File::Basename::basename( $file->{"value"} );
        
        $fstr .= qq (      file = $title\t$value\n);
    }

    foreach $item ( @{ $stats->{"params"} } )
    {
        $title = $item->{"title"};
        $value = $item->{"value"};
        
        $istr .= qq (         item = $title: $value\n);
    }

    chomp $fstr;
    chomp $istr;

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
$fstr
      date = $stats->{"finished"}
      time = $time
      secs = $secs
      hrow = Method\t$stats->{"method"}
      <menu>
         title = Parameters
$istr
      </menu>
   </header>

   <table>
      title = Input clusters and output consenses counts
      colh = Clusters\t&Delta;\t&Delta; %\tSeqs\t&Delta;\t&Delta; %
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Input alignments first,

    $clu = $stats->{"clu_in"};
    $seq = $stats->{"seq_in"};

    $text .= qq (      trow = $clu\t\t\t$seq\t\t\n);

    # Then output consenses,

    $clu = $stats->{"clu_out"};
    $seq = $stats->{"seq_out"};
    
    $clu_dif = $stats->{"clu_in"} - $stats->{"clu_out"};
    $seq_dif = $stats->{"seq_in"} - $stats->{"seq_out"};

    $clu_pct = sprintf "%.2f", 100 * ( 1 - $stats->{"clu_out"} / $stats->{"clu_in"} );
    $seq_pct = sprintf "%.2f", 100 * ( 1 - $stats->{"seq_out"} / $stats->{"seq_in"} );
    
    $text .= qq (      trow = $clu\t-$clu_dif\t-$clu_pct\t$seq\t-$seq_dif\t$seq_pct\n);
    
    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_stats_sum
{
    # Niels Larsen, October 2012. 

    # Reads the content of the given list of statistics files and generates a 
    # summary table. The input files were written by write_stats_file above. The 
    # output file has a tagged format understood by Recipe::Stats::html_body. A
    # string is returned in list context, otherwise it is written to the given 
    # file or STDOUT. 

    my ( $files,       # Input statistics files
         $sfile,       # Output file
        ) = @_;

    # Returns a string or nothing.
    
    my ( $stats, $text, $file, $rows, $secs, @row, @table, $in_clus, $time,
         $seq_pct, $str, $row, $ofile, $params, $items, $in_reads, $out_seqs,
         $out_reads, @dates, $date );

    # Create table array by reading all the given statistics files and getting
    # values from them,

    @table = ();
    $secs = 0;

    foreach $file ( @{ $files } )
    {
        $stats = &Recipe::IO::read_stats( $file )->[0];

        $rows = $stats->{"headers"}->[0]->{"rows"};

        $ofile = $rows->[0]->{"value"};
        $secs += $rows->[3]->{"value"};

        $rows = $stats->{"tables"}->[0]->{"rows"};
        
        @row = split "\t", $rows->[0]->{"value"};
        ( $in_clus, $in_reads ) = @row[0,3];

        @row = split "\t", $rows->[1]->{"value"};
        ( $out_seqs, $out_reads ) = @row[0,3];

        $in_clus =~ s/,//g;
        $in_reads =~ s/,//g;
        $out_seqs =~ s/,//g;
        $out_reads =~ s/,//g;

        push @table, [ "file=$ofile", $in_reads, $in_clus, 
                       $out_seqs, 100 * ( $in_clus - $out_seqs ) / $in_clus, $out_reads,
        ];
    }

    # Sort descending by input sequences, 

    @table = sort { $b->[2] <=> $a->[2] } @table;
    
    # Calculate totals,

    $in_reads = &List::Util::sum( map { $_->[1] } @table );
    $in_clus = &List::Util::sum( map { $_->[2] } @table );
    $out_seqs = &List::Util::sum( map { $_->[3] } @table );
    $seq_pct = "-". sprintf "%.1f", 100 * ( $in_clus - $out_seqs ) / $in_clus;
    $out_reads = &List::Util::sum( map { $_->[5] } @table );

    # Re-read any of the stats files, to get parameters and settings that are the
    # same for all files,

    $stats = bless &Recipe::IO::read_stats( $files->[0] )->[0];

    $time = &Time::Duration::duration( $secs );
    $date = &Recipe::Stats::head_type( $stats, "date" );
    
    $params = &Recipe::Stats::head_menu( $stats, "Parameters" );

    # Format table,

    $items = "";
    map { $items .= qq (           item = $_\n) } @{ $params };
    chomp $items;

    $text = qq (
<stats>
   title = $stats->{"title"}
   <header>
       hrow = Total input clusters\t$in_clus
       hrow = Total output consenses\t$out_seqs ($seq_pct%)
       hrow = Total input reads\t$in_reads
       hrow = Total output reads\t$out_reads
       <menu>
           title = Parameters
$items
       </menu>
       date = $date
       secs = $secs
       time = $time 
   </header>  
   <table>
      title = Input clusters and output consenses and reads counts
      colh = Output consenses\tIn-reads\tIn-clus\tOut-cons\t&Delta; %\tOut-reads
);
    
    foreach $row ( @table )
    {
        $row->[1] //= 0;
        $row->[2] //= 0;
        $row->[3] //= 0;
        $row->[4] = "-". sprintf "%.1f", $row->[4];
        $row->[5] //= 0;

        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }

    $text .= qq (   </table>\n</stats>\n\n);

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

1;

__END__
