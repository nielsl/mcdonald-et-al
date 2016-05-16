package Expr::Profile;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions that create and compare expression profiles.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use DBI;
use IO::File;
use Math::GSL::Statistics;
use Tie::IxHash; 
use YAML::XS;
use Data::Structure::Util;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_profile
                 &create_profiles
                 &load_classify_hash
                 &process_profile_args
                 &process_scale_args
                 &scale_file
                 &scale_files
                 &sum_file_column
                );

use Common::Config;
use Common::Messages;
use Common::File;
use Common::Tables;
use Common::Names;
use Common::DBM;

use Registry::Args;
use Registry::Paths;

use Expr::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our ( $Sum_header_wgt, $Sum_header, $Dat_header, $Gen_header );

$Dat_header = "Dataset";
$Gen_header = "Annotation";
$Sum_header = "Sum";
$Sum_header_wgt = "Sum-wgt";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_profile
{
    # Niels Larsen, March 2010.

    # A profile lists, as a minimum, genes by name or annotation and then an 
    # expression value. This routine takes a classification file made by 
    # seq_classify and creates a table with these fields,
    #
    # Sum-wgt         Weighted expression value
    # Sum             Un-weighted expression value
    # Matches         Number of consenses with best match against this gene
    # Max %           Percentage of best match
    # Dataset         Dataset name
    # Annotation      Gene name
    #
    # The number of original reads are used as expression values and weighted 
    # sums are calculated.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $cla_file, $exp_file, $cla_hash, $db, $matches, $p_best, @table, 
         $match, $name, $clobber, $ann, $exp_sum, $i, $stats, $exp_sum_wgt, 
         $seq_sum, $pct_best, $with_ids, @row, @titles, $out_table, 
         $stat_file, $stat_conf, $ann_clu, $mis_clu );

    local $Common::Messages::indent_plain;
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS AND VARIABLES <<<<<<<<<<<<<<<<<<<<<<<<<

    $args = &Registry::Args::create( $args );
    
    $cla_file = $args->itable;
    $exp_file = $args->etable;
    $stat_file = $args->ostats;
    $stat_conf = $args->statconf;

    $Common::Messages::silent = $args->silent;

    $clobber = $args->clobber;
    $with_ids = $args->withids;

    if ( not $Common::Messages::silent ) {
	$Common::Messages::indent_plain = 6;
	&echo( "\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>> COLLECT MATCHES BY FUNCTION <<<<<<<<<<<<<<<<<<<<<<

    # Loads a classification output into a hash, where keys and values are
    #
    #  { dataset }{ annotation }->[[ query id, sim pct, match len, non-matches ],...]
    # 
    # Below this hash has its values changed and expanded.

    &echo( "Loading classifications ... " );
    $cla_hash = &Expr::Profile::load_classify_hash( $cla_file );
    &echo_green( "done\n" );

    &echo( "Calculating statistics ... " );

    foreach $db ( keys %{ $cla_hash } )
    {
        foreach $ann ( keys %{ $cla_hash->{ $db } } )
        {
            if ( $ann =~ /^Unknown_\d+$/ ) {
                $stats->{"mis_clusters"} += 1;
            } else {
                $stats->{"ann_count"} += 1;
                $stats->{"ann_clusters"} += scalar @{ $cla_hash->{ $db }->{ $ann } };
            }
        }
    }

    $ann_clu = $stats->{"ann_clusters"} // 0;
    $mis_clu = $stats->{"mis_clusters"} // 0;

    $stats->{"clu_count"} = $ann_clu + $mis_clu;
    
    &echo_green( "done\n" );

    &echo( "    Matching clusters: ", 9 );
    &echo_done( "$ann_clu\n" );
    
    &echo( "Non-matching clusters: ", 9 );
    &echo_done( "$mis_clu\n" );
    
    &echo( "  Annotations matched: ", 9 );
    &echo_done( "$stats->{'ann_count'}\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE INDICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # These are indices in the expression profile tables, just to make the code
    # below easier to read,

    use constant CNT_NDX => 0;        # Sequence counts
    use constant ID_NDX => 1;         # Sequence id
    use constant PCT_NDX => 2;        # Similarity pct 
    use constant LEN_NDX => 3;        # Match length
    use constant MIS_NDX => 4;        # Non-matches (mismatches + indels)
    use constant PRB_NDX => 5;        # P-value 
    use constant SUW_NDX => 6;        # Weighted sums
    use constant SUM_NDX => 7;        # Un-weighted sums

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE QUALITY RATIOS <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Calculate how likely each match is, given their lengths and number of 
    # non-matches. Then sort them so the lowest p-value is first. Then take 
    # the ratios between the best p-value and the others in turn. These ratios
    # are then used (next section) to weigh the original read counts. 

    &echo( "Setting match weights ... " );

    foreach $db ( keys %{ $cla_hash } )
    {
        foreach $ann ( keys %{ $cla_hash->{ $db } } )
        {
            $matches = $cla_hash->{ $db }{ $ann };

            if ( $ann =~ /^Unknown_\d+$/ )
            {
                # These did not match anything,

                $matches->[0]->[PCT_NDX] = undef;
                $matches->[0]->[PRB_NDX] = 1;
            }
            else
            {
                # To weigh down less good matches, calculate a p-value,

                foreach $match ( @{ $matches } )
                {
                    $match->[PRB_NDX] = &Common::Util::p_bin_selection(
                        $match->[LEN_NDX]-$match->[MIS_NDX], $match->[LEN_NDX], 0.25 );
                }
                
                # Sort by p-value, smallest first,

                @{ $matches } = sort { $a->[PRB_NDX] <=> $b->[PRB_NDX] } @{ $matches };

                # Convert to ratios against best p-value; these are used 
                # below to scale the cluster sizes with before they are 
                # summed up,

                $p_best = $matches->[0]->[PRB_NDX];

                for ( $i = 0; $i <= $#{ $matches }; $i++ )
                {
                    $matches->[$i]->[PRB_NDX] = $p_best / $matches->[$i]->[PRB_NDX];
                }
            }
        }
    }

    &echo_green( "done\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>>> CREATE EXPRESSION TABLE <<<<<<<<<<<<<<<<<<<<<<<<<

    # A given short read may match differently annotated genes equally well or 
    # nearly so. And a given annotation may be matched by different short reads.
    # Here we assign original read counts to different reference genes using 
    # ratios from above. Both weighted and unweighted sums are kept. 

    &echo( "Adding cluster sizes ... " );

    foreach $db ( keys %{ $cla_hash } )
    {
        foreach $ann ( keys %{ $cla_hash->{ $db } } )
        {
            $matches = $cla_hash->{ $db }{ $ann };
            
            foreach $match ( @{ $matches } )
            {
                # Multiply read count with the weight calculated above,

                $match->[SUW_NDX] = $match->[CNT_NDX] * $match->[PRB_NDX];

                # Save un-weighted cluster size for comparison,

                $match->[SUM_NDX] = $match->[CNT_NDX];
            }

            # Sum weighted and un-weighted cluster sizes,

            $exp_sum_wgt = &List::Util::sum( map { $_->[SUW_NDX] } @{ $matches } );
            $exp_sum = &List::Util::sum( map { $_->[SUM_NDX] } @{ $matches } );

            # The number of sequences with this annotation,

            $seq_sum = scalar @{ $matches };

            # Percentage of best hit,

            if ( $ann =~ /^Unknown_\d+$/ ) {
                $pct_best = "";
            } else {
                $pct_best = $matches->[0]->[PCT_NDX];
            }

            # Create row, optionally with sequence ids as last column (this can
            # get very large),

            @row = ( int $exp_sum_wgt, $exp_sum, $seq_sum, $pct_best, $db, $ann );

            if ( $with_ids )
            {
                push @row, join ",", map { $_->[ID_NDX] } @{ $matches };
            } 

            push @table, &Storable::dclone( \@row );
        }
    }

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SORT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("Sorting expression table ... ");

    @table = sort { $b->[0] <=> $a->[0] } @table;

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $clobber ) {
        &Common::File::delete_file_if_exists( $exp_file );
    }

    &echo( "Writing expression table ... " );

    @titles = ( $Sum_header_wgt, $Sum_header, "Matches", "Max %", $Dat_header, $Gen_header );

    if ( $with_ids ) {
        push @titles, "Seq IDs";
    }

    $out_table = &Common::Table::new(
        \@table,
        {
            "col_headers" => \@titles,
        });

    &Common::Table::write_table( $out_table, $exp_file );

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> UPDATE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stat_file )
    {
        $name = &File::Basename::basename( $stat_file );

        if ( -r $stat_file ) {
            &echo( "Updating $name ... " );
        } else {
            &echo( "Creating $name ... " );
        }

        &Expr::Stats::create_stats(
             {
                 "itables" => [ $exp_file ],
                 "config" => $stat_conf,
                 "stats" => $stat_file,
                 "ilabel" => &Common::File::full_file_path( $cla_file ),
                 "olabel" => &Common::File::full_file_path( $exp_file ),
                 "silent" => 1,
             });

        &echo_done( "done\n" );
    }

    return;
}

sub create_profiles
{
    # Niels Larsen, May 2010.

    # Produces a profile table from each of the given classification tables.
    # Sequence files must exist with the same name as the classification files,
    # but without the .cla suffix. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $silent, $silent2, $i, $j, $cla_tables, $exp_tables, 
         $indent, $name, $seq_files, $table, @max_sums, @table, $max_sum, 
         $tmp_file, @header, $grand_avg, $ratio, $values, $exp_file, 
         $stat_file, $new_stats );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "itables" => [],
        "otable" => undef,
        "osuffix" => ".expr",
        "stats" => undef,
        "newstats" => undef,
        "statconf" => undef,
        "withids" => 0,
	"silent" => 0,
	"verbose" => 0,
	"clobber" => 0,
        "help" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Expr::Profile::process_profile_args( $args );
    
    $new_stats = $args->newstats;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $silent = $args->silent )
    {
        $Common::Messages::silent = $silent;
        $silent2 = $silent;        
    }
    else {
	$silent2 = $args->verbose ? 0 : 1;
    }

    $indent = $args->verbose ? 3 : 0;
    
    &echo_bold( qq (\nCreate expression profile:\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> EXPRESSION FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $cla_tables = $conf->itables;
    $exp_tables = $conf->otables;

    for ( $i = 0; $i <= $#{ $cla_tables }; $i++ )
    {
        # Create profile,

        $name = &File::Basename::basename( $exp_tables->[$i] );
        &echo( "   Creating $name ... " );
        
        $stat_file = $conf->ostats->[$i];

        if ( defined $new_stats and defined $stat_file ) {
            &Common::File::delete_file_if_exists( $stat_file );
        }
        
        &Expr::Profile::create_profile(
            {
                "itable" => $cla_tables->[$i],
                "etable" => $exp_tables->[$i],
                "ostats" => $stat_file,
                "statconf" => $conf->statconf,
                "withids" => $args->withids,
                "silent" => $silent2,
                "verbose" => $args->verbose,
                "clobber" => $args->clobber,
                "indent" => $indent,
            });
        
        &echo_green( "done\n", $indent );
    }

    &echo_bold("Done\n\n");

    return;
}

sub load_classify_hash
{
    # Niels Larsen, May 2010.

    # Loads a classification output into a hash, where keys and values are
    #  { dataset }{ annotation }->[[ query id, sim pct ],...]

    my ( $file,            # File path 
        ) = @_;

    # Returns a hash.

    my ( $fh, @line, $line, %table, $mis_count, $cnt_ndx, $id_ndx, $sim_ndx,
         $len_ndx, $mis_ndx, $gap_ndx, $db_ndx, $ann_ndx );

    $fh = &Common::File::get_read_handle( $file );
    
    # Get table indices from header; these header names must match with 
    # those written by the Seq::Classify::write_cla_table routine,

    $line = <$fh>;
    $line =~ s/^\s*#\s*//;
    chomp $line;

    ( $cnt_ndx, $id_ndx, $sim_ndx, $len_ndx, $mis_ndx, $gap_ndx, $db_ndx, $ann_ndx ) = 
        &Common::Table::names_to_indices(
            [ qw (Q-count Q-ID Sim% M-len Mism Gaps T-DB T-annotation ) ], 
            [ split "\t", $line ],
        );

    $mis_count = 0;

    while ( defined ( $line = <$fh> ) )
    {
        chomp $line;
        @line = split "\t", $line;

        if ( $line[$sim_ndx] )
        {
            push @{ $table{ $line[$db_ndx] }{ $line[$ann_ndx] } }, 
            [ $line[$cnt_ndx], $line[$id_ndx], $line[$sim_ndx], $line[$len_ndx], $line[$mis_ndx] + $line[$gap_ndx] ];
        }
        else
        {
            push @{ $table{"Nomatch"}{ "Unknown_". ++$mis_count } }, 
            [ $line[$cnt_ndx], $line[$id_ndx], undef, undef, undef ];
        }
    }

    &Common::File::close_handle( $fh );

    return wantarray ? %table : \%table;
}

sub process_profile_args
{
    # Niels Larsen, March 2010.

    # Checks and expands the classify routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $isuffix, $conf, @files, $file, $path, $name, $type, $stats_file );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->itables and @{ $args->itables } ) {
	$conf->{"itables"} = &Common::File::check_files( $args->itables, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No input classification tables given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->otable ) {
        $conf->{"otables"} = [ $args->otable ];
    } else {
        $conf->{"otables"} = [ map { $_. $args->osuffix } @{ $args->itables } ];
    }

    if ( not $args->clobber ) {
        &Common::File::check_files( $conf->{"otables"}, "!e", \@msgs );
    }

    &append_or_exit( \@msgs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->newstats or defined $args->stats )
    {
        $stats_file = $args->newstats || $args->stats;

        if ( scalar @{ $args->itables } == 1 and $stats_file ) {
            $conf->{"ostats"} = [ $stats_file ];
        } else {
            $conf->{"ostats"} = [ map { $_ . ".stats" } @{ $args->itables } ];
        }
        
        if ( $file = $args->statconf )
        {
            if ( -r $file ) {
                $conf->{"statconf"} = $file;
            } else {
                push @msgs, ["ERROR", qq (Configuration file not readable -> "$file") ];
            }
        }
        else {
            push @msgs, ["ERROR", qq (No configuration file given) ];
        }
    }
    else {
        $conf->{"ostats"} = [];
        $conf->{"statconf"} = undef;
    }

    &append_or_exit( \@msgs, $msgs );

    bless $conf;

    return wantarray ? %{ $conf } : $conf;
}

sub process_scale_args
{
    # Niels Larsen, March 2010.

    # Checks and expands the classify routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $isuffix, $conf, @files, $file, $path, $name, $type, $regexp,
         $filter );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->itables and @{ $args->itables } ) {
	$conf->{"itables"} = &Common::File::check_files( $args->itables, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No input expression files given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WHICH NUMBERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->weighted ) {
        $conf->{"sum_hdr"} = $Sum_header_wgt;
    } else {
        $conf->{"sum_hdr"} = $Sum_header;
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->otable ) {
        $conf->{"otables"} = [ $args->otable ];
    } else {
        $conf->{"otables"} = [ map { $_. $args->osuffix } @{ $args->itables } ];
    }

    if ( not $args->clobber ) {
        &Common::File::check_files( $conf->{"otables"}, "!e", \@msgs );
    }

    &append_or_exit( \@msgs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $filter ( qw ( dbfilter molfilter ) )
    {
        if ( $regexp = $args->$filter )
        {
            eval { "" =~ /$regexp/ };

            if ( $@ ) {
                push @msgs, ["ERROR", qq (Wrong looking expression -> "$regexp") ];
            } else {
                $conf->{ $filter } = $regexp;
            }
        }
        else {
            $conf->{ $filter } = undef;
        }
    }

    if ( @msgs )
    {
        $msgs[-1][1] .= "\n";
        push @msgs, ["INFO", qq (This program uses Perl-style regular expressions, here is a) ];
        push @msgs, ["INFO", qq (guide: http://www.zytrax.com/tech/web/regex.htm\n) ];
        push @msgs, ["TIP", qq (Enclose expressions in single quotes) ];
    }
    
    &append_or_exit( \@msgs, $msgs );

    bless $conf;

    return wantarray ? %{ $conf } : $conf;
}

sub scale_file
{
    # Niels Larsen, May 2011.

    my ( $ifile,
         $ofile,
         $ratio,
        ) = @_;

    my ( $table, $name, $i, $vals, $ndcs, $ndx );

    $table = &Common::Table::read_table( $ifile );
    
    $ndcs = &Common::Table::names_to_indices( [ qw (Sum-wgt Sum ) ], $table->col_headers );
    $vals = $table->values;

    foreach $ndx ( @{ $ndcs } )
    {
        for ( $i = 0; $i <= $#{ $vals }; $i++ )
        {
            $vals->[$i]->[$ndx] = int ( $vals->[$i]->[$ndx] * $ratio );
        }
    }
    
    $table->values( $vals );

    if ( defined wantarray ) {
        return $table;
    }

    &Common::Table::write_table( $table, $ofile );

    return;
}

sub scale_files
{
    # Niels Larsen, May 2011.

    my ( $args,
        ) = @_;

    my ( $defs, $conf, $itables, $i, @sums, $grand_avg, $ifile, $clobber,
         $name, $ratio, $sum, @msgs, $otables, $ofile );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "itables" => [],
        "otable" => undef,
	"dbfilter" => undef,
	"molfilter" => undef,
        "weighted" => 1,
        "osuffix" => ".sca",
	"silent" => 0,
	"clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Expr::Profile::process_scale_args( $args );

    $itables = $conf->itables;
    $otables = $conf->otables;

    $clobber = $args->clobber;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SCALING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nScaling:\n) );

    # Find the average of all expression sums,
    
    &echo( "   Calculating scale factor ... " );
    
    for ( $i = 0; $i <= $#{ $itables }; $i++ )
    {
        $ifile = $itables->[$i];

        $sum = &Expr::Profile::sum_file_column( $ifile, $conf );
        
        if ( $sum > 0 ) {
            push @sums, $sum;
        } else {
            push @msgs, ["ERROR", qq (No filter matches in -> "$ifile") ];
        }
    }

    if ( @msgs ) {
        &echo( "\n" );
        &append_or_exit( \@msgs );
    }

    $grand_avg = &List::Util::sum( @sums ) / scalar @sums;
    
    &echo_green( "done\n" );

    # Use this average to scale all counts,
    
    for ( $i = 0; $i <= $#{ $itables }; $i++ )
    {
        $ifile = $itables->[$i];
        $ofile = $otables->[$i];
        
        $name = &File::Basename::basename( $ofile );
        &echo( "   Writing $name ... " );
        
        $ratio = $grand_avg / $sums[$i];

        if ( $clobber ) {
            &Common::File::delete_file_if_exists( $ofile );
        }
        
        &Expr::Profile::scale_file( $ifile, $ofile, $ratio );
        
        &echo_green( "done\n" );
    }

    &echo_bold( "Finished\n\n" );
    
    return;
}

sub sum_file_column
{
    # Niels Larsen, June 2010.

    # Sums the values in a given table on a given column index. If a filter 
    # is given, then only rows are included that match these fields.
   
    my ( $file,         # Table file
         $conf,         # Configuration
        ) = @_;

    # Returns integer. 

    my ( $sum, $sumndx, $datndx, $namndx, $regexp, $table, $values );

    $table = &Common::Table::read_table( $file );
    
    ( $sumndx, $datndx, $namndx ) = 
        @{ &Common::Table::names_to_indices(
                [ $conf->sum_hdr, $Dat_header, $Gen_header ],
                $table->col_headers ) };

    $values = $table->values;

    if ( $regexp = $conf->dbfilter )
    {
        $values = [ grep { $_->[$datndx] =~ /$regexp/ } @{ $values } ];
    }

    if ( $regexp = $conf->molfilter )
    {
        $values = [ grep { $_->[$namndx] =~ /$regexp/ } @{ $values } ];
    }

    if ( @{ $values } ) {
        $sum = &List::Util::sum( map { $_->[$sumndx] } @{ $values } );
    } else {
        $sum = 0;
    }
    
    return $sum;
}

1;

__END__


