package Seq::Demul;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Sequence demultiplexing related routines.
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @EXPORT_OK );
require Exporter;

use Time::Duration qw ( duration );
use Fcntl qw( :flock SEEK_SET SEEK_CUR SEEK_END );

@EXPORT_OK = qw (
                 &combine_fr_files
                 &create_bar_dict
                 &demul
                 &demul_args
                 &demul_pairs
                 &demul_primer_bars
                 &demul_bar
                 &demul_bar_args
                 &demul_bar_code
                 &demul_single
                 &init_bar_stats
                 &init_demul_stats
                 &init_join_stats
                 &join_pairs
                 &join_pairs_args
                 &list_file_pairs
                 &match_forward
                 &match_forward_alter
                 &match_primer_bars
                 &match_reverse
                 &match_reverse_alter
                 &open_handles
                 &pair_seq_lists
                 &score_primer_pairs
                 &score_primer_singles
                 &write_demul_stats
                 &write_join_stats
);

use Common::Config;
use Common::Messages;

use Registry::Args;
use Bio::Patscan;

use Seq::Common;
use Seq::IO;

use Recipe::IO;
use Recipe::Stats;

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Out_prefix, $Nobar_key, $Nofit_key, $Noqal_key, $Nopri_key, $Nopar_key,
     $Noori_key, $Nofrb_key, @Mis_keys, %Mis_keys, $Max_int );

$Out_prefix = "BION";

$Nopri_key = "NO_PRIMER";
$Noori_key = "NO_PRIMER_MATES";
$Nobar_key = "NO_BARCODE";
$Nofit_key = "NO_BARCODE_ROOM";
$Noqal_key = "NO_BARCODE_QUALITY";
$Nofrb_key = "NO_BARCODE_MATCH";
$Nopar_key = "NO_PAIRED_TOTAL";

@Mis_keys = (
    [ $Nopri_key, "Primers do not match" ],
    [ $Noori_key, "Primers match same direction" ],
    [ $Nofit_key, "Primer too close to start" ],
    [ $Nobar_key, "Barcodes do not match" ],
    [ $Noqal_key, "Barcodes with low quality" ],
    [ $Nofrb_key, "Barcodes not corresponding" ],
    [ $Nopar_key, "Total unpaired reads" ],
    );

%Mis_keys = map { $_->[0] => $_->[1] } @Mis_keys;

$Max_int = 2 ** 30;

# 121020_I631_FCC186GACXX_L7_SZAXPI015420-144+1_1.fq.gz  check.txt         read_me.txt
# 121020_I631_FCC186GACXX_L7_SZAXPI015420-144+1_2.fq.gz  raw_data.md5.txt

# Optifish_1_40_06_12_11_pylorus_TTAGGC_L003_R1_001.fastq.gz  Optifish_1_40_06_12_11_pylorus_TTAGGC_L003_R2_001.fastq.gz
# Optifish_1_40_06_12_11_pylorus_TTAGGC_L003_R1_002.fastq.gz  Optifish_1_40_06_12_11_pylorus_TTAGGC_L003_R2_002.fastq.gz

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub combine_fr_files
{
    # Niels Larsen, January 2012.
    
    # Appends .F and .R files for the barcodes in the given dictionary and names
    # the new files .FR. If there are only an .F or .R file for a given barcode,
    # where the dictionary says there should be two mates, then that is an error. 
    # The given dictionary is made by &Seq::Demul::create_bar_dict. Returns the
    # number of combined files.

    my ( $dict,   # Dictionary hash
        ) = @_;

    # Returns nothing.

    my ( $tag, $info, $file1, $file2, $count, %done, $path1, $mate );

    $count = 1;

    foreach $tag ( keys %{ $dict } )
    {
        $info = $dict->{ $tag };
        
        if ( $file1 = $info->file and $mate = $info->barmate )
        {
            $file2 = $dict->{ $mate }->file;

            next if $done{ $file1 } or $done{ $file2 };

            &Common::File::append_files( $file1, $file2 );
            &Common::File::delete_file( $file2 );

            $path1 = &Common::Names::strip_suffix( $file1 ) .".FR";

            &Common::File::rename_file( $file1, $path1 );

            $done{ $file1 } = 1;
            $done{ $file2 } = 1;

            $count += 1;
        }
    }

    return $count;
}

sub create_bar_dict
{
    # Niels Larsen, February 2013. 

    # Reads a one- or two-column barcode table and creates a hash where 
    # barcodes are keys and values are hashes with information about them.
    # The hashes have these keys and values,
    # 
    #  "title" => title string
    #  "file" => file path
    #  "barcode" => sequence string
    #  "barmate" => sequence string for the opposite direction (optional)
    #  "orient" => forward or reverse
    # 
    # If there is no title in the barcode file, title is set to the forward
    # or the reverse absent that. The title is used for file names. If there
    # are both forward and reverse barcodes, the file suffix is ".FR", if 
    # forward only ".F" and reverse only ".R".

    my ( $file,         # Barcode file
         $args,         # Arguments hash
         $msgs,         # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( %dict, @msgs, $bar, $bars, $outdir, $outpre, $title, $base, 
         $fpath, $rpath, $merge, $suffix );
    
    $outdir = $args->outdir // "";
    $outpre = $args->outpre // "";
    $merge = $args->merge // 1;
    $suffix = $args->suffix;
    
    $outdir =~ s/ //g;
    $outdir =~ s/\/$//;

    $base = "$outdir/";
    $base .= "$outpre." if $outpre ne "";
                    
    # Read tags,

    $bars = &Seq::IO::read_table_tags( $file, \@msgs );

    &append_or_exit( \@msgs, $msgs );
        
    foreach $bar ( @{ $bars } )
    {
        $title = $bar->{"ID"} // $bar->{"F-tag"} // $bar->{"R-tag"};

        $fpath = $base . $title;
        $rpath = $base . $title;

        # >>>>>>>>>>>>>>>>>>>>>> FORWARD AND REVERSE <<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $bar->{"F-tag"} and $bar->{"R-tag"} ) 
        {
            if ( $merge ) {
                $fpath .= ".FR";
                $rpath .= ".FR";
            } else {
                $fpath .= ".F";
                $rpath .= ".R";
            }

            $dict{"F"}{ $bar->{"F-tag"} } = bless { 
                "title" => $title,
                "file" => $fpath . $suffix,
                "barcode" => $bar->{"F-tag"},
                "barmate" => $bar->{"R-tag"},
                "orient" => "F",
            };
            
            $dict{"R"}{ $bar->{"R-tag"} } = bless { 
                "title" => $title,
                "file" => $rpath . $suffix,
                "barcode" => $bar->{"R-tag"},
                "barmate" => $bar->{"F-tag"},
                "orient" => "R",
            };
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> FORWARD ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $bar->{"F-tag"} )
        {
            $fpath .= ".F";

            $dict{"F"}{ $bar->{"F-tag"} } = bless { 
                "title" => $title,
                "file" => $fpath . $suffix,
                "barcode" => $bar->{"F-tag"},
                "orient" => "F",
            };
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> REVERSE ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $bar->{"R-tag"} )
        {
            $rpath .= ".R";

            $dict{"R"}{ $bar->{"R-tag"} } = bless { 
                "title" => $title,
                "file" => $rpath . $suffix,
                "barcode" => $bar->{"R-tag"},
                "orient" => "R",
            };
        }
        else {
            &dump( $bar );
            &error( qq (Neither forward or reverse barcode present) );
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? %dict : \%dict;
}

sub demul
{
    # Niels Larsen, February 2013.
    
    # The main demultiplex routine. Splits sequences into separate files by 
    # barcodes only, by using a primer pattern as anchor in addition, and can
    # handle paired reads. The sub-sequence upstream of a primer match is used
    # to decide which of the given barcodes there is, if any. Barcodes of 
    # multiple lengths are allowed. From outside this module, call this 
    # routine only. Returns nothing.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $count, $total, $barseq, $time_start, $seconds, 
         $hitpct, $mispct, $recipe, $stats, $statfile, $outdir, $bardict, 
         $key, $file, @ifhs, $ori, $dict, $misdict, $primers, $seq_files );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "steps" => [],
        "recipe" => undef,
        "format" => undef,
        "seqfiles" => [],
        "barfile" => undef,
        "prifile" => undef,
        "pairfile" => undef,
        "files1" => undef,
        "files2" => undef,
        "singles" => 0,
        "barbeg" => 2,
        "bargap" => 0,
        "barqual" => 99.5,
        "qualtype" => "Sanger",
        "merge" => 1,
        "failed" => 1,
        "readbuf" => 10_000,
        "outdir" => undef,
        "outpre" => undef, # $Out_prefix,
        "stats" => undef,
        "dryrun" => 0,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Demul::demul_args( $args );

    $Common::Messages::silent = $args->silent;

    &echo_bold( qq (\nDe-multiplexing:\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $seq_files = $conf->seqfiles )
    {
        &echo("   Listing sequence files ... ");

        $count = scalar @{ $seq_files };
        
        if ( ref $seq_files->[0] ) 
        {
            $conf->merge( 0 );
            &echo_done("$count pairs\n");
        }
        else {
            &echo_done("$count\n");
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> BARCODES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Reading barcode file ... ");

    $bardict = &Seq::Demul::create_bar_dict(
        $conf->barfile,
        bless {
            "outdir" => $conf->outdir,
            "outpre" => $conf->outpre,
            "merge" => $conf->merge,
            "suffix" => ".demul",
        });

    # If either forward or reverse barcodes are missing, copy those of the 
    # other, 

    if ( not $bardict->{"F"} ) {
        $bardict->{"F"} = &Storable::dclone( $bardict->{"R"} );
    } elsif ( not $bardict->{"R"} ) {
        $bardict->{"R"} = &Storable::dclone( $bardict->{"F"} );
    }

    &echo_done( "done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PRIMERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Reading primer file ... ");
    $primers = &Seq::IO::read_primer_conf( $conf->prifile );
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Initializing statistics ... ");
    $stats = &Seq::Demul::init_demul_stats( $recipe, $conf );
    &echo_done("done\n");

    $time_start = &time_start();

    if ( $seq_files and ref $seq_files->[0] )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>> PAIRED READS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $stats = &Seq::Demul::demul_pairs(
            bless {
                "seqfiles" => $seq_files,
                "seqformat" => $conf->format,
                "primers" => $primers,
                "bardict" => $bardict,
                "bargap" => $conf->bargap,
                "misdict" => $conf->misdict,
                "singles" => $conf->singles,
                "minch" => $conf->minch,
                "stats" => $stats,
                "failed" => $conf->failed,
                "dryrun" => $conf->dryrun,
                "readbuf" => $conf->readbuf,
                "outdir" => $conf->outdir,
                "clobber" => $conf->clobber,
             });
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>> UN-PAIRED READS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $stats = &Seq::Demul::demul_single(
            bless {
                "seqfiles" => $seq_files,
                "seqformat" => $conf->format,
                "primers" => $primers,
                "bardict" => $bardict,
                "bargap" => $conf->bargap,
                "misdict" => $conf->misdict,
                "minch" => $conf->minch,
                "stats" => $stats,
                "failed" => $conf->failed,
                "dryrun" => $conf->dryrun,
                "readbuf" => $conf->readbuf,
                "outdir" => $conf->outdir,
                "clobber" => $conf->clobber,
             });
    }

    &echo_green("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Writing statistics ... ");

    # Add file names to statistics. Delete their directory part, all is kept
    # in the same directory,

    $outdir = $conf->outdir;

    foreach $ori ( keys %{ $bardict } )
    {
        foreach $barseq ( keys %{ $bardict->{ $ori } } )
        {
            $file = $bardict->{ $ori }->{ $barseq }->file;
            $file =~ s/^$outdir\/?//g;

            $stats->{"hits"}->{ $ori }->{ $barseq }->{"file"} = $file;
            $stats->{"hits"}->{ $ori }->{ $barseq }->{"count"} //= 0;
        }
    }

    if ( $conf->failed )
    {
        $misdict = $conf->misdict;
        
        foreach $key ( keys %{ $misdict } )
        {
            $file = $misdict->{ $key }->file;
            $file =~ s/^$outdir\/?//g;
            
            $stats->{"misses"}->{ $key }->{"file"} = $file;
            $stats->{"misses"}->{ $key }->{"count"} //= 0;
        }
    }
    else {
        $stats->{"misses"} = undef;
    }

    $seconds = &time_elapsed() - $time_start;

    $stats->{"seconds"} = $seconds;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    &Common::File::delete_file_if_exists( $conf->statfile ) if $conf->clobber;
    &Seq::Demul::write_demul_stats( $conf->statfile, bless $stats );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CONSOLE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $total = $stats->{"iseqs"} // 0;

    # Input,

    &echo( "   Input sequence count ... " );
    &echo_done( "$total\n" );

    # Matches,

    &echo( "   De-multiplexed total ... " );

    $count = 0;

    foreach $ori ( keys %{ $stats->{"hits"} } )
    {
        $dict = $stats->{"hits"}->{ $ori };
        $count += &List::Util::sum( map { $_->{"count"} } values %{ $dict } );
    }

    if ( $total ) {
        $hitpct = sprintf "%.2f", 100 * $count / $total;
    } else {
        $hitpct = "0.00";
    }

    &echo_done( $count ." ($hitpct%)\n" );

    # No primers,

    if ( $count = $stats->{"misses"}->{ $Nopri_key }->{"count"} )
    {
        if ( $total ) {
            $mispct = sprintf "%.2f", 100 * $count / $total;
        } else {
            $mispct = "0.00";
        }

        &echo( "   Primer non-matches ... " );
        &echo_done( $count ." ($mispct%)\n" );
    }

    # Low quality barcode,

    if ( $count = $stats->{"misses"}->{ $Noqal_key }->{"count"} )
    {
        if ( $total ) {
            $mispct = sprintf "%.2f", 100 * $count / $total;
        } else {
            $mispct = "0.00";
        }

        &echo( "   Barcode low quality ... " );
        &echo_done( $count ." ($mispct%)\n" );
    }

    # No barcode match,

    if ( $count = $stats->{"misses"}->{ $Nobar_key }->{"count"} )
    {
        if ( $total ) {
            $mispct = sprintf "%.2f", 100 * $count / $total;
        } else {
            $mispct = "0.00";
        }

        &echo( "   Barcode no matches ... " );
        &echo_done( $count ." ($mispct%)\n" );
    }

    # No room for barcode,

    if ( $count = $stats->{"misses"}->{ $Nofit_key }->{"count"} )
    {
        if ( $total ) {
            $mispct = sprintf "%.2f", 100 * $count / $total;
        } else {
            $mispct = "0.00";
        }

        &echo( "   Barcode past start ... " );
        &echo_done( $count ." ($mispct%)\n" );
    }

    &echo("   Run-time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );

    &echo_bold( "Finished\n\n" );

    return;
}

sub demul_args
{
    # Niels Larsen, February 2013.

    # Checks and expands the de-multiplex script arguments to a configuration
    # hash that suits the routines. It is checked here that files exist etc,
    # and fatal error messages are printed to STDERR. 

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $files, $file, $dir, $bardict, @files, $conf, $basename,
         $key, $text, $qual_enc, $primers, $expr1, $expr2, $suffix, $outpre );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BARCODES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file = $args->barfile )
    {
	&Common::File::check_files([ $file ], "efr", \@msgs );
        $conf->{"barfile"} = $file;
    }
    else {
        push @msgs, ["ERROR", "No input barcode file given." ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PRIMERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file = $args->prifile )
    {
	&Common::File::check_files([ $file ], "efr", \@msgs );
        $conf->{"prifile"} = $file;

        if ( $args->pairfile )
        {
            $primers = &Seq::IO::read_primer_conf( $file );

            if ( scalar @{ $primers } != 2 ) {
                push @msgs, ["ERROR", qq (Paired end reads must have two primers) ];
            }
        }
    } 
    else {
        $conf->{"prifile"} = undef;
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file = $args->pairfile )
    {
        # Two column table of file names, 

        $files = &Seq::IO::read_pairs_table( $file );

	&Common::File::check_files([ map { $_->[0], $_->[1] } @{ $files } ], "efr", \@msgs );

        &append_or_exit( \@msgs );

        $conf->{"seqfiles"} = $files;
        $conf->{"format"} = &Seq::IO::detect_format( $files->[0]->[0], \@msgs );

        &append_or_exit( \@msgs );
    }
    elsif ( $args->files1 or $args->files2 )
    {
        # Two file listing shell expressions, 

        if ( ( $expr1 = $args->files1 ) and ( $expr2 = $args->files2 ) ) {
            $files = &Seq::IO::read_pairs_expr( $expr1, $expr2, 1, \@msgs );
        } elsif ( $expr1 ) {
            push @msgs, ["ERROR", qq (Pair 2 file expression missing) ];
        } else {
            push @msgs, ["ERROR", qq (Pair 1 file expression missing) ];
        }

        &append_or_exit( \@msgs );

        $conf->{"seqfiles"} = $files;
        $conf->{"format"} = &Seq::IO::detect_format( $files->[0]->[0], \@msgs );

        &append_or_exit( \@msgs );
    }
    elsif ( $files = $args->seqfiles and @{ $files } )
    {
	&Common::File::check_files( $files, "efr", \@msgs );
        &append_or_exit( \@msgs );

        $conf->{"seqfiles"} = $files;
        $conf->{"format"} = &Seq::IO::detect_format( $files->[0], \@msgs );
    }
    elsif ( -t STDIN )
    {
        if ( $file = $args->pairfile ) {
            &Common::File::check_files([ $file ], "efr", \@msgs );
        } else {
            push @msgs, ["ERROR", "No input sequence file or pair file given." ];
        }
        
        $conf->{"seqfiles"} = undef;
    }
    elsif ( not $args->format )
    {
        push @msgs, ["ERROR", qq (Input format must be given with data from STDIN) ];
    }
    else {
        $conf->{"seqfiles"} = $args->seqfiles;
        $conf->{"format"} = $args->format;
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf->{"barbeg"} = &Registry::Args::check_number( $args->barbeg, 1, 10, \@msgs );
    $conf->{"barbeg"} -= 1;

    if ( $conf->{"barqual"} = $args->barqual )
    {
        $conf->{"barqual"} =~ s/\%//g;
        $conf->{"barqual"} = &Registry::Args::check_number( $conf->{"barqual"}, 90, 100, \@msgs );

        $qual_enc = &Seq::Common::qual_config( $args->qualtype, \@msgs );
        $conf->{"minch"} = &Seq::Common::qual_to_qualch( $conf->{"barqual"} / 100, $qual_enc );
    }
    else {
        $conf->{"minch"} = undef;
    }

    $conf->{"qualtype"} = $args->qualtype;
    $conf->{"singles"} = $args->singles;
    $conf->{"failed"} = $args->failed;

    $conf->{"clobber"} = $args->clobber;
    $conf->{"dryrun"} = $args->dryrun;

    $conf->{"readbuf"} = &Registry::Args::check_number( $args->readbuf, 1, undef, \@msgs );
    $conf->{"bargap"} = &Registry::Args::check_number( $args->bargap, 0, 3, \@msgs );

    $conf->{"merge"} = $args->merge;

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check directory,
    
    if ( $dir = $args->outdir )
    {
        if ( $args->clobber ) {
            &Common::File::create_dir_if_not_exists( $dir );
        }
        elsif ( not -d $dir ) {
            push @msgs, ["ERROR", qq (Output directory does not exist -> "$dir") ];
        }
        
        $conf->{"outdir"} = $dir;
    } 
    else {
        push @msgs, ["ERROR", qq (Output directory must be given, but can be ".") ];
    }

    # Output prefix must always be given,

    if ( not ( $outpre = $args->outpre ) ) {
        $outpre = "";
        # push @msgs, ["ERROR", qq (Output file prefix must be given) ];
    }

    $conf->{"outpre"} = $outpre;

    &append_or_exit( \@msgs );

    # Check barcode output files,
    
    $bardict = &Seq::Demul::create_bar_dict(
        $args->barfile,
        bless {
            "outpre" => $outpre,
            "outdir" => $args->outdir,
            "merge" => $args->merge,
            "suffix" => ".demul",
        });
    
    if ( not $args->clobber )
    {
        @files = &Common::Util::uniqify([ map { $_->file } map { values %{ $_ } } values %{ $bardict } ]);        
        &Common::File::check_files( \@files, "!e", \@msgs );
    }

    # Create and check mis-match dictionary and files,

    if ( $outpre ) {
        map { $conf->{"misdict"}->{ $_ } = bless { "file" => $conf->{"outdir"} ."/$outpre". ".$_" } } keys %Mis_keys;
    } else {
        map { $conf->{"misdict"}->{ $_ } = bless { "file" => $conf->{"outdir"} ."/$_" } } keys %Mis_keys;
    }

    &Common::File::check_files([ map { $_->file } values %{ $conf->{"misdict"} } ],
                               "!e", \@msgs ) unless $args->clobber;

    # Check statistics file,

    $suffix = &File::Basename::basename( $0 );

    if ( $args->stats ) {
        $conf->{"statfile"} = $args->stats;
    } else {
        $conf->{"statfile"} = ($args->outdir//".") ."/". &File::Basename::basename( $0 ) .".stats";
    }

    &Common::File::check_files([ $conf->{"statfile"}], "!e", \@msgs ) unless $args->clobber;

    if ( @msgs ) {
        push @msgs, ["INFO", qq (The --clobber option overwrites existing files) ];
    }

    &append_or_exit( \@msgs );

    bless $conf;
    
    return wantarray ? %{ $conf } : $conf;
}

sub demul_primer_bars
{
    # Niels Larsen, February 2013.

    # Creates a hash where keys are barcode sequences and values are lists
    # of sequence entries. Among keys are also the global NO_* constants 
    # defined at the top of this module. 

    my ( $seqs,
         $args,
        ) = @_;

    # Returns a hash.

    my ( $pris, $i, $count, $hits );

    $pris = $args->{"primers"};

    for ( $i = 0; $i <= $#{ $pris }; $i += 1 )
    {
        $count = &Seq::Demul::match_primer_bars(
            $seqs,
            {
                "primer" => $pris->[$i],
                "barlens" => $args->{"barlens"},
                "bardict" => $args->{"bardict"},
                "bargap" => $args->{"bargap"} // 0,
                "minch" => $args->{"minch"},
            });

        map { push @{ $hits->{ $_->{"barkey"} } }, $_ } @{ $seqs };
    }

    return $hits;
}

sub demul_bar
{
    # Niels Larsen, December 2011.

    # Splits sequences into separate file by looking for tag matches. Looks 
    # exact match at the start of the sequences up to a given distance. It is
    # a fast naive way, using the primer as anchor is better but slower. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $bardict, $ofhs, $count, @msgs, $read_routine, $misfile,
         $write_routine, $ifh, $barseq, $i, $format, $seqs, $hits, $stats,
         $maxpos, $pos, $readbuf, $barlen, $dryrun, $time_start, $seconds, 
         $seqs_code, $seqs_routine, $seqfile, $clobber, @barseqs, @barfiles,
         $out_total, $hitpct, $mispct, $params, $key, $val, $recipe, $statfile,
         $basename, $outdir, $file, $mfh, $barfile, $prefix, $outpre );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "barfile" => undef,
        "seqfile" => undef,
        "seqfmt" => undef,
        "maxdist" => undef,
        "readbuf" => 1000,
        "outdir" => undef,
        "outpre" => $Out_prefix,
        "misfile" => undef,
        "stats" => undef,
        "append" => 0,
        "dryrun" => 0,
        "clobber" => 0,
        "append" => 0,
        "silent" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE CONFIG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check and expand all arguments into a config hash that contains settings
    # the routines want,

    $conf = &Seq::Demul::demul_bar_args( $args );

    $maxpos = $conf->maxpos;
    $seqfile = $conf->seqfile;
    $misfile = $conf->misfile;
    $statfile = $conf->statfile;
    $barfile = $conf->barfile;
    $outdir = $conf->outdir;

    $readbuf = $args->readbuf;
    $clobber = $args->clobber;
    $dryrun = $args->dryrun;
    $outpre = $args->outpre;

    $Common::Messages::silent = $args->silent;

    &echo_bold( qq (\nTag de-multiplexing:\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> READING TAGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Reading tags file ... ");
    
    $bardict = $conf->{"dict"};

    @barseqs = keys %{ $bardict };
    @barfiles = values %{ $bardict };

    $count = scalar @barseqs;
    &echo_done("$count tags\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $dryrun )
    {
        &echo("   Opening output files ... ");
        
        $ofhs = &Seq::Demul::open_handles( $bardict, $args, \@msgs );

        $count = keys %{ $ofhs };
        &echo_done("$count handles\n");
        
        if ( $misfile )
        {
            &echo("   Opening mismatch file ... ");
            
            &Common::File::delete_file_if_exists( $misfile ) if $clobber;
            
            if ( $args->append ) {
                $mfh = &Common::File::get_append_handle( $misfile );
            } else {
                $mfh = &Common::File::get_write_handle( $misfile );
            }
            
            &echo_done("done\n");
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Creating de-multiplex code ... ");
    
    $barlen = length $barseqs[0];

    $seqs_code = &Seq::Demul::demul_bar_code(
        {
            "maxpos" => $maxpos,
            "barlen" => $barlen,
            "misfile" => $misfile,
        });

    $seqs_routine = eval $seqs_code;

    if ( $@ ) {
        &error( $@ )
    };    

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE STATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Demul::init_bar_stats( $conf );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $dryrun ) {
        &echo("   De-multiplexing (dryrun) ... ");
    } else {
        &echo("   De-multiplexing by tag ... ");
    }

    $time_start = &Common::Messages::time_start();

    $ifh = &Common::File::get_read_handle( $seqfile );
    $ifh->blocking( 1 );

    $format = $conf->{"format"};

    $read_routine = "Seq::IO::read_seqs_$format";
    $write_routine = "Seq::IO::write_seqs_$format";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    no strict "refs";

    while ( $seqs = $read_routine->( $ifh, $readbuf ) )
    {
        # Increment input count,

        $stats->{"iseqs"} += scalar @{ $seqs };
        
        # Run splitting code on a list of sequences,

        $hits = $seqs_routine->( $seqs, $bardict );

        # Write outputs on open file handles,

        if ( not $dryrun )
        {
            foreach $barseq ( @barseqs )
            {
                if ( $hits->{ $barseq } )
                {
                    $write_routine->( $ofhs->{ $barseq }, $hits->{ $barseq } );
                }
            }

            if ( $misfile and $hits->{ $Nobar_key } )
            {
                $write_routine->( $mfh, $hits->{ $Nobar_key } );
            }
        }

        # Update output counts,
        
        foreach $barseq ( keys %{ $hits } )
        {
            $stats->{"hits"}->{ $barseq }->{"count"} += scalar @{ $hits->{ $barseq } };
        }
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handles( $ofhs ) unless $dryrun;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Add file names to statistics,

    map { $stats->{"hits"}->{ $_ }->{"file"} = $bardict->{ $_ } } @barseqs;

    if ( defined $outdir ) {
        map { $stats->{"hits"}->{ $_ }->{"file"} =~ s|^$outdir/|| } @barseqs;
    }

    if ( $misfile )
    {
        $misfile =~ s|^$outdir/||;
        $stats->{"hits"}->{ $Nobar_key }->{"file"} = $misfile;
    }
    
    $seconds = &time_elapsed() - $time_start;

    $stats->{"seconds"} = $seconds;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    &echo_green("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> APPEND REVERSE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->append )
    {
        &echo("   Combining .R and .F files ... ");
        &Seq::Demul::combine_fr_files( [ values %{ $bardict } ] );
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> DELETE EMPTY FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # &echo("   Deleting empty files ... ");

    # foreach $file ( values %{ $bardict } )
    # {
    #     &Common::File::delete_file_if_empty( $file );
    #     $count += 1;
    # }

    # &echo_done("$count\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::File::delete_file_if_exists( $statfile ) if $clobber;

    &echo("   Saving statistics ... ");
    &Seq::Demul::write_demul_stats( $statfile, bless $stats );
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> COPY BAR FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Saving barcode file ... ");

    $prefix = "$outdir/$outpre";

    &Common::File::delete_file_if_exists( "$prefix.barcodes.txt" ) if $clobber;
    &Common::File::copy_file( $barfile, "$prefix.barcodes.txt" );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CONSOLE RECEIPT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Input sequence count ... " );
    &echo_done( $stats->{"iseqs"} ."\n" );

    $count = &List::Util::sum(
        grep { defined $_ and $_ ne $Nobar_key } 
        map { $stats->{"hits"}->{ $_ }->{"count"} } @barseqs ) // 0;

    $hitpct = sprintf "%.2f", 100 * $count / $stats->{"iseqs"};

    &echo( "   Match sequence count ... " );
    &echo_done( $count ." ($hitpct%)\n" );

    if ( $count = $stats->{"hits"}->{ $Nobar_key }->{"count"} )
    {
        $mispct = sprintf "%.2f", 100 * $count / $stats->{"iseqs"};
        &echo( "   No-match sequence count ... " );
        &echo_done( $count ." ($mispct%)\n" );
    }

    &echo("   Run time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );

    &echo_bold( "Finished\n\n" );

    return;
}

sub demul_bar_args
{
    # Niels Larsen, October 2011.

    # Checks and expands the match routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $bardict, $format, @files, $seqfile, $barfile, $conf,
         $basename, $statfile );

    @msgs = ();

    $format = $args->seqfmt;
    $seqfile = $args->seqfile;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Sequence,

    if ( $seqfile = $args->seqfile )
    {
	&Common::File::check_files([ $seqfile ], "efr", \@msgs );
        &append_or_exit( \@msgs );

        $format = &Seq::IO::detect_format( $seqfile, \@msgs );
    }
    elsif ( -t STDIN )
    {
        push @msgs, ["ERROR", "No input sequence file given." ];
    }
    elsif ( not $format )
    {
        push @msgs, ["ERROR", qq (Input format must be given with data from STDIN) ];
    }

    $conf->{"seqfile"} = $seqfile;
    $conf->{"format"} = $format;

    # Tags,

    $barfile = $args->barfile;

    if ( defined ( $conf->{"barfile"} = $barfile ) ) {
	&Common::File::check_files([ $barfile ], "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", "No input barcode file given." ];
    }

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check directory,
    
    if ( defined ( $conf->{"outdir"} = $args->outdir ) )
    {
        if ( $args->clobber ) {
            &Common::File::create_dir_if_not_exists( $args->outdir );
        }
        elsif ( not -d $conf->{"outdir"} ) {
            push @msgs, ["ERROR", qq (Output directory does not exist -> "$conf->{'outdir'}") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (Output directory must be given, but can be ".") ];
    }

    # Output prefix must be given if no file name (i.e. input from STDIN),

    if ( not $seqfile and not $args->outpre )
    {
        push @msgs, ["ERROR", qq (Output file prefix must be given for piped input) ];
    }

    &append_or_exit( \@msgs );

    # Create mismatch file name,
    
    if ( $args->misfile ) {
        $conf->{"misfile"} = $conf->{"outdir"} ."/". $args->outpre . ".demul-bar.FAILED";
    } else {
        $conf->{"misfile"} = undef;
    }

    # Create tag hash, needed to check file names,
    
    $bardict = &Seq::Demul::create_bar_dict(
        {
            "barfile" => $args->barfile,
            "seqfile" => $args->seqfile,
            "outpre" => $args->outpre,
            "outdir" => $args->outdir,
            "outbar" => $args->outbar,
        });
    
    $conf->{"dict"} = $bardict;

    # Check all output files,

    if ( not $args->append and not $args->clobber )
    {
        push @files, values %{ $bardict };
        push @files, $conf->{"misfile"} if $conf->{"misfile"};
        
        &Common::File::check_files( \@files, "!e", \@msgs );
    }

    # Check statistics file,
    
    if ( $args->stats ) {
        $conf->{"statfile"} = $args->stats;
    } else {
        $conf->{"statfile"} = ($args->outdir//".") ."/seq_demul.stats";
    }

    &Common::File::check_files([ $conf->{"statfile"}], "!e", \@msgs ) unless $args->clobber;

    # --append and --barnames are mutually exclusive,

    $conf->{"append"} = $args->append;
    # $conf->{"outbar"} = $args->barnames;

    &append_or_exit( \@msgs, $msgs );

    # Set maxdist default to 1 if not given,

    if ( defined $args->maxdist and $args->maxdist >= 0 ) {
        $conf->{"maxpos"} = $args->maxdist;
    } else {
        $conf->{"maxpos"} = 1;
    }

    bless $conf;

    return wantarray ? %{ $conf } : $conf;
}

sub demul_bar_code
{
    # Niels Larsen, December 2011.
    
    # Builds code that filters and/or extracts from lists of sequences,
    # in response to pattern config files. When there are conditionals
    # this is often the better way, though less readable.

    my ( $args,
        ) = @_;

    # Returns string.

    my ( $barlen, $maxpos, $code, $misfile );

    $barlen = $args->{"barlen"};
    $maxpos = $args->{"maxpos"};
    $misfile = $args->{"misfile"};

    $code = qq (
sub
{
    my ( \$seqs,
         \$dict,
         ) = \@_;

    my ( \$match, \$pos, \$seq, \$barseq, \$hits, \$begpos );
);

    $code .= qq (
    foreach \$seq ( \@{ \$seqs } )
    {
);

    if ( $misfile ) {
        $code .= qq (        \$match = 0;\n\n);
    }
     
    $code .= qq (        for ( \$pos = 0; \$pos <= $maxpos; \$pos++ )
        {
            \$barseq = substr \$seq->{"seq"}, \$pos, $barlen;
               
            if ( \$dict->{ \$barseq } )
            {
                \$begpos = \$pos + $barlen;

                \$seq->{"seq"} = substr \$seq->{"seq"}, \$begpos;
                \$seq->{"qual"} = substr \$seq->{"qual"}, \$begpos;

                push \@{ \$hits->{ \$barseq } }, \$seq;

);

    if ( $misfile ) {
        $code .= qq (                \$match = 1;\n);
    }

    $code .= qq (                last;\n            }\n        }\n);

    if ( $misfile )
    {
        $code .= qq (
        if ( not \$match ) {
            push \@{ \$hits->{ $Nobar_key } }, \$seq;
        }\n);
    }

    $code .= qq (    }\n\n    return \$hits;\n}\n);

    return $code;
}

sub demul_pairs
{
    # Niels Larsen, February 2013.

    # Reads files in forward/reverse pairs and matches the forward primer and 
    # its barcodes against the forward reads, and the reverse primer against 
    # the reverse reads. When both primers/barcodes match, output goes to .FR
    # files, otherwise to .F or .R files. 

    my ( $args,
        ) = @_;
    
    my ( $pairfile, $stats, $dryrun, $readbuf, $bardict, @barlens, $pair,
         $seq_files, $primers, $read_seqs, $write_seqs, $i, $j, $barkey,
         $f_file, $r_file, $f_ifh, $r_ifh, $f_tot, $r_tot, $f_seqs, $r_seqs,
         $format, $f_bars, $r_bars, $key, $val, $f_prim, $r_prim, $f_lens,
         $r_lens, $bargap, $minch, $f_hit, $r_hit, $bar_fhs, $outdir, $clobber,
         $mis_fhs, $misdict, $count, $prifile, $file, $hits, $fr_bars, $ori,
         $f_seq, $r_seq, $barseq, $seq, $singles, $miss, $sing, $fr_oris,
         $sin_fhs, $failed
        );
    
    $seq_files = $args->seqfiles;
    $format = $args->seqformat;
    $primers = $args->primers;
    $bardict = $args->bardict;
    $stats = $args->stats;
    $dryrun = $args->dryrun;
    $readbuf = $args->readbuf;
    $bargap = $args->bargap;
    $misdict = $args->misdict;
    $singles = $args->singles;
    $failed = $args->failed;
    $minch = $args->minch;
    $outdir = $args->outdir;
    $clobber = $args->clobber;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Configuring internals ... ");

    # Set forward, reverse and forward+reverse lookup hash for mate checking,

    $f_bars = $bardict->{"F"};
    $r_bars = $bardict->{"R"};

    foreach $barseq ( keys %{ $bardict->{"F"} } ) {
        $fr_bars->{ $barseq }->{ $f_bars->{ $barseq }->{"barmate"} } = 1;
    }

    foreach $barseq ( keys %{ $bardict->{"R"} } ) {
        $fr_bars->{ $barseq }->{ $r_bars->{ $barseq }->{"barmate"} } = 1;
    }

    # Lengths sorted in descending order are used for getting substrings in 
    # front of primers that are checked as barcodes,

    $f_lens = [ &Common::Util::uniqify([ map { length $_ } keys %{ $f_bars } ]) ];
    $r_lens = [ &Common::Util::uniqify([ map { length $_ } keys %{ $r_bars } ]) ];

    $f_lens = [ sort { $b <=> $a } @{ $f_lens } ];
    $r_lens = [ sort { $b <=> $a } @{ $r_lens } ];

    $f_prim = $primers->[0];
    $r_prim = $primers->[1];

    $fr_oris->{"F"}->{"R"} = 1;
    $fr_oris->{"R"}->{"F"} = 1;

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $dryrun )
    {
        &echo("   Opening output files ... ");
        
        ( $bar_fhs, $count ) = &Seq::Demul::open_bar_handles( $bardict, bless {
            "outdir" => $outdir, "clobber" => $clobber, "suffix" => "" },
            );
        
        &echo_done("$count\n");

        if ( not $singles and $failed )
        {
            &echo("   Opening singles files ... ");

            ( $sin_fhs, $count ) = &Seq::Demul::open_bar_handles( $bardict, bless {
                "outdir" => $outdir, "clobber" => $clobber, "suffix" => ".$Nopar_key" },
            );
        
            &echo_done("$count\n");
        }

        if ( $failed )
        {
            &echo("   Opening mis-match files ... ");
            
            $mis_fhs = &Seq::Demul::open_handles( $misdict, bless {
                     "outdir" => $outdir, "clobber" => $clobber, "suffix" => "" } );
            
            $count = keys %{ $mis_fhs };
            &echo_done("$count\n");
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS READS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $dryrun ) {
        &echo("   Reading paired reads ... ");
    } else {
        &echo("   Processing paired reads ... ");
    }

    $read_seqs = "Seq::IO::read_seqs_". $format;
    $write_seqs = "Seq::IO::write_seqs_". $format;

    $stats->{"type"} = "pairs";

    no strict "refs";

    foreach $pair ( @{ $seq_files } )
    {
        ( $f_file, $r_file ) = @{ $pair };

        $f_ifh = &Common::File::get_read_handle( $f_file );
        $r_ifh = &Common::File::get_read_handle( $r_file );

        $f_tot = 0;
        $r_tot = 0;

        # Read the same number of sequences from both F and R files,

        while ( $f_seqs = $read_seqs->( $f_ifh, $readbuf ) )
        {
            $r_seqs = $read_seqs->( $r_ifh, $readbuf );

            map { $_->{"info"} .= "seq_num=". ++$f_tot } @{ $f_seqs };
            map { $_->{"info"} .= "seq_num=". ++$r_tot } @{ $r_seqs };

            # The match_primer_bars sections below do not alter sequences but 
            # set two fields,
            # 
            # match: set to 0, F or R for no match, forward and reverse match
            #        respectively.
            #
            # barkey: set to the barcode sequence or to one of the keys set 
            #         at the top of this module, depending on the problem.
            # 
            # >>>>>>>>>>>>>>>>>>>>>> MATE 1 SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<
            
            # Try the forward primer and barcodes on the F sequence, 

            &Seq::Demul::match_primer_bars(
                $f_seqs,
                {
                    "primer" => $f_prim,
                    "barlens" => $f_lens,
                    "bardict" => $f_bars,
                    "orient" => "F",
                    "bargap" => $bargap,
                    "minch" => $minch,
                });

            # Then the reverse primer, while skipping those that matched above,

            &Seq::Demul::match_primer_bars(
                $f_seqs,
                {
                    "primer" => $r_prim,
                    "barlens" => $r_lens,
                    "bardict" => $r_bars,
                    "orient" => "R",
                    "bargap" => $bargap,
                    "minch" => $minch,
                });

            # Sequences with the "match" field undefined did not match the 
            # primer, and so they get a special key to indicate that,

            foreach $seq ( @{ $f_seqs } )
            {
                if ( not defined $seq->{"match"} ) 
                {
                    $seq->{"match"} = 0;
                    $seq->{"barkey"} = $Nopri_key;
                }
            }
            
            # >>>>>>>>>>>>>>>>>>>>>>> MATE 2 SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<

            # This section is identical to the previous, except here the R 
            # sequences are matched,

            &Seq::Demul::match_primer_bars(
                $r_seqs,
                {
                    "primer" => $f_prim,
                    "barlens" => $f_lens,
                    "bardict" => $f_bars,
                    "orient" => "F",
                    "bargap" => $bargap,
                    "minch" => $minch,
                });

            &Seq::Demul::match_primer_bars(
                $r_seqs,
                {
                    "primer" => $r_prim,
                    "barlens" => $r_lens,
                    "bardict" => $r_bars,
                    "orient" => "R",
                    "bargap" => $bargap,
                    "minch" => $minch,                    
                });

            foreach $seq ( @{ $r_seqs } )
            {
                if ( not defined $seq->{"match"} ) 
                {
                    $seq->{"match"} = 0;
                    $seq->{"barkey"} = $Nopri_key;
                }
            }
            
            # >>>>>>>>>>>>>>>>>>>>> MAKE RESULT HASHES <<<<<<<<<<<<<<<<<<<<<<<<

            # All sequences now have the "match" field set to 1 if they match 
            # a barcode, and to 0 if not. But sometimes only sequences should 
            # be written where both the forward and reverse read matches; this
            # is controlled by the $single argument: if on, all that match are 
            # written; if off, only pairs are written.

            $hits = {};
            $sing = {};
            $miss = {};

            if ( $singles )
            {
                # >>>>>>>>>>>>>>>>>> INCLUDE SINGLES <<<<<<<<<<<<<<<<<<<<<<<<<<
                
                # Pairs + singlets. That means we can put every sequence that 
                # matched a barcode/primer on $hits, which is written out. On
                # $miss goes those that do not match barcode/primer,

                foreach $seq ( @{ $f_seqs }, @{ $r_seqs } )
                {
                    if ( $ori = $seq->{"match"} ) {
                        push @{ $hits->{ $ori }->{ $seq->{"barkey"} } }, $seq;
                    } else {
                        push @{ $miss->{ $seq->{"barkey"} } }, $seq;
                    }
                }
            }
            else
            {
                # Pairs only. If there is match in both directions put
                # both sequences on $hits. Those where only one direction 
                # matches are put on $sing if they match, otherwise $miss,
                
                for ( $i = 0; $i <= $#{ $f_seqs }; $i += 1 )
                {
                    $f_seq = $f_seqs->[$i];
                    $r_seq = $r_seqs->[$i];
                    
                    if ( $f_seq->{"match"} and $r_seq->{"match"} )
                    {
                        # If both reads match both primer and barcode, still things
                        # can be wrong: 1) the primers match in the same direction
                        # and 2) the matching barcodes do not correspond. Below reads
                        # are pushed onto $hits if primers are opposite and barcodes
                        # correspond. Otherwise put counts on $miss and $sing,

                        if ( $fr_oris->{ $f_seq->{"match"} }->{ $r_seq->{"match"} } )
                        {
                            if ( $fr_bars->{ $f_seq->{"barkey"} }->{ $r_seq->{"barkey"} } )
                            {
                                push @{ $hits->{ $f_seq->{"match"} }->{ $f_seq->{"barkey"} } }, $f_seq;
                                push @{ $hits->{ $r_seq->{"match"} }->{ $r_seq->{"barkey"} } }, $r_seq;
                            }
                            else
                            {
                                push @{ $miss->{ $Nofrb_key } }, $f_seq;
                                push @{ $miss->{ $Nofrb_key } }, $r_seq;
                            }
                        }
                        else 
                        {
                            push @{ $miss->{ $Noori_key } }, $f_seq;
                            push @{ $miss->{ $Noori_key } }, $r_seq;
                        }
                    }
                    else
                    {
                        # No F/R mates. If the "match" field is "F" or "R" then both 
                        # barcode and primer matched, if not then it is "0". If non-
                        # zero, put the sequence on a singles hash. If zero it failed 
                        # primer or barcode matching,

                        if ( $ori = $f_seq->{"match"} ) {
                            push @{ $sing->{ $ori }->{ $f_seq->{"barkey"} } }, $f_seq;
                        } else {
                            push @{ $miss->{ $f_seq->{"barkey"} } }, $f_seq;
                        }

                        if ( $ori = $r_seq->{"match"} ) {
                            push @{ $sing->{ $ori }->{ $r_seq->{"barkey"} } }, $r_seq;
                        } else {
                            push @{ $miss->{ $r_seq->{"barkey"} } }, $r_seq;
                        }
                    }
                }
            }

            # >>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( not $dryrun )
            {
                # Write primer+barcode matches,
                
                foreach $ori ( keys %{ $hits } )
                {
                    foreach $barseq ( keys %{ $hits->{ $ori } } )
                    {
                        $write_seqs->( $bar_fhs->{ $ori }->{ $barseq }, $hits->{ $ori }->{ $barseq } );
                        $bar_fhs->{ $ori }->{ $barseq }->flush;
                    }
                }

                if ( $failed )
                {
                    # Write failed reads of different kinds,
                
                    if ( not $singles )
                    {
                        foreach $ori ( keys %{ $sing } )
                        {
                            foreach $barseq ( keys %{ $sing->{ $ori } } )
                            {
                                $write_seqs->( $sin_fhs->{ $ori }->{ $barseq }, $sing->{ $ori }->{ $barseq } );
                                $sin_fhs->{ $ori }->{ $barseq }->flush;
                            }
                        }
                    }
                    
                    foreach $key ( keys %{ $miss } )
                    {
                        $write_seqs->( $mis_fhs->{ $key }, $miss->{ $key } );
                        $mis_fhs->{ $key }->flush;
                    }
                }
            }

            # >>>>>>>>>>>>>>>>>>>>>>>> SAVE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
            
            foreach $ori ( keys %{ $hits } )
            {
                foreach $barseq ( keys %{ $hits->{ $ori } } )
                {
                    $stats->{"hits"}->{ $ori }->{ $barseq }->{"count"} += scalar @{ $hits->{ $ori }->{ $barseq } };
                }
            }

            foreach $ori ( keys %{ $sing } )
            {
                foreach $barseq ( keys %{ $sing->{ $ori } } )
                {
                    $stats->{"singles"}->{ $ori }->{ $barseq }->{"count"} += scalar @{ $sing->{ $ori }->{ $barseq } };
                    $stats->{"misses"}->{ $Nopar_key }->{"count"} += scalar @{ $sing->{ $ori }->{ $barseq } };
                }
            }

            foreach $key ( keys %{ $miss } )
            {
                $stats->{"misses"}->{ $key }->{"count"} += scalar @{ $miss->{ $key } };
            }
        }

        $stats->{"iseqs"} += $f_tot + $r_tot;
        $stats->{"failed"} = $failed;
        
        if ( $f_tot != $r_tot ) {
            &error("$f_tot sequences in $f_file, but\n$r_tot sequences in $r_file");
        }

        &Common::File::close_handle( $f_ifh );
        &Common::File::close_handle( $r_ifh );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CLOSE HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $dryrun )
    {
        foreach $ori ( keys %{ $bar_fhs } )
        {
            &Common::File::close_handles( $bar_fhs->{ $ori } );

            if ( $failed ) {
                &Common::File::close_handles( $sin_fhs->{ $ori } ) if exists $sin_fhs->{ $ori };
            }
        }
    }

    return $stats;
}

sub demul_single
{
    # Niels Larsen, February 2013. 

    # Demultiplexes single reads, not pairs. This is a helper function to 
    # demul, which is the one to call. Returns nothing.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $stats, $dryrun, $primers, $bardict, $seqfiles, @barlens, @hits,
         @ifhs, $ifh, $seqfile, $read_seqs, $write_seqs, $seqs, $hits, 
         $barseq, $bar_fhs, $mis_fhs, $count, $key, $readbuf, $i, $bargap, 
         $minch, $format, $prifile, $outdir, $clobber, $primer, $ori, 
         $misdict, $miss, $seq, $failed );
    
    $seqfiles = $args->seqfiles;
    $format = $args->seqformat;
    $primers = $args->primers;
    $stats = $args->stats;
    $readbuf = $args->readbuf;
    $bardict = $args->bardict;
    $bargap = $args->bargap // 0;
    $misdict = $args->misdict;
    $minch = $args->minch;
    $failed = $args->failed;
    $dryrun = $args->dryrun;
    $outdir = $args->outdir;
    $clobber = $args->clobber;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL PRIMERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $primers } )
    {
        foreach $primer ( @{ $primers } )
        {
            if ( $primer->{"orient"} eq "F" ) {
                $primer->{"bardict"} = $bardict->{"F"};
            } elsif ( $primer->{"orient"} eq "R" ) {
                $primer->{"bardict"} = $bardict->{"R"};
            } else {
                &error( qq (Wrong looking orientation -> "$primer->{'orient'}". Must be "F" or "R") );
            }

            @barlens = &Common::Util::uniqify([ map { length $_ } keys %{ $bardict->{ $primer->{"orient"} } } ]);
            @barlens = sort { $b <=> $a } @barlens;
        
            $primer->{"barlens"} = &Storable::dclone( \@barlens );
        }
    }
    else {
        &error("Not implemented");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET INPUT HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $seqfiles and @{ $seqfiles } )
    {
        &echo("   Opening input files ... ");

        foreach $seqfile ( @{ $seqfiles } )
        {
            push @ifhs, &Common::File::get_read_handle( $seqfile );
            $ifhs[-1]->blocking( 1 );
        }

        &echo_done( (scalar @ifhs) ."\n" );
    }
    else
    {
        &echo("   Opening STDIN as input ... ");

        push @ifhs, &Common::File::get_read_handle();    # STDIN
        $ifhs[-1]->blocking( 1 );

        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> GET OUTPUT HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $dryrun )
    {
        &echo("   Opening output files ... ");            
        
        ( $bar_fhs, $count ) = &Seq::Demul::open_bar_handles( $bardict, bless {
            "outdir" => $outdir, "clobber" => $clobber, "suffix" => "" });
        
        &echo_done("$count\n");

        if ( $failed )
        {
            &echo("   Opening mis-match files ... ");
            
            $mis_fhs = &Seq::Demul::open_handles( $misdict, bless {
                "outdir" => $outdir, "clobber" => $clobber, "suffix" => "" } );
            
            $count = keys %{ $mis_fhs };
            &echo_done("$count\n");
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS READS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    no strict "refs";

    if ( $dryrun ) {
        &echo("   Reading single reads ... ");
    } else {
        &echo("   Processing single reads ... ");
    }

    $read_seqs = "Seq::IO::read_seqs_". $format;
    $write_seqs = "Seq::IO::write_seqs_". $format;

    $stats->{"type"} = "single";

    foreach $ifh ( @ifhs )
    {
        while ( $seqs = $read_seqs->( $ifh, $readbuf ) )
        {
            $stats->{"iseqs"} += scalar @{ $seqs };
            
            # >>>>>>>>>>>>>>>>>>>> MAKE SEQUENCE HASHES <<<<<<<<<<<<<<<<<<<<<<<

            # The following routine creates a hash, $hits, where keys are 
            # barcodes values are lists of corresponding sequence entries. 
            # Among the keys are also the global NO_* constants defined at
            # the top of this module.

            $hits = {};
            $miss = {};

            for ( $i = 0; $i <= $#{ $primers }; $i += 1 )
            {
                $primer = $primers->[$i];
                $ori = $primer->{"orient"};
                
                &Seq::Demul::match_primer_bars(
                    $seqs,
                    {
                        "primer" => $primer,
                        "barlens" => $primer->{"barlens"},
                        "bardict" => $primer->{"bardict"},
                        "orient" => $ori,
                        "bargap" => $bargap,
                        "minch" => $minch,
                    });

                # Put all primer-matching sequences into a list. Some also 
                # match a barcode, some not,
                
                if ( $failed )
                {
                    foreach $seq ( @{ $seqs } )
                    {
                        if ( defined $seq->{"match"} )
                        {
                            if ( $seq->{"match"} ) {
                                push @{ $hits->{ $ori }->{ $seq->{"barkey"} } }, $seq;
                            } else {
                                push @{ $miss->{ $seq->{"barkey"} } }, $seq;
                            }
                        }
                    }
                }
                else
                {
                    foreach $seq ( @{ $seqs } )
                    {
                        if ( $seq->{"match"} ) {
                            push @{ $hits->{ $ori }->{ $seq->{"barkey"} } }, $seq;
                        }
                    }
                }
                            
                # Shorten the list of remaining sequences to try,

                $seqs = [ grep { not defined $_->{"match"} } @{ $seqs } ];
            }

            # >>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( not $dryrun )
            {
                # Write primer+barcode matches,

                foreach $ori ( keys %{ $hits } )
                {
                    foreach $barseq ( keys %{ $hits->{ $ori } } )
                    {
                        $write_seqs->( $bar_fhs->{ $ori }->{ $barseq }, $hits->{ $ori }->{ $barseq } );
                        $bar_fhs->{ $ori }->{ $barseq }->flush;
                    }
                }
                
                if ( $failed )
                {
                    # Only primer mis-matching sequences are now in $seqs,
                    
                    $miss->{ $Nopri_key } = [ grep { not defined $_->{"match"} } @{ $seqs } ];
            
                    # Write failed of different kinds,
                    
                    foreach $key ( keys %{ $miss } )
                    {
                        $write_seqs->( $mis_fhs->{ $key }, $miss->{ $key } );
                        $mis_fhs->{ $key }->flush;
                    }
                }
            }

            # >>>>>>>>>>>>>>>>>>>>>> WRITE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<
            
            foreach $ori ( keys %{ $hits } )
            {
                foreach $barseq ( keys %{ $hits->{ $ori } } )
                {
                    $stats->{"hits"}->{ $ori }->{ $barseq }->{"count"} += scalar @{ $hits->{ $ori }->{ $barseq } };
                }
            }

            foreach $key ( keys %{ $miss } )
            {
                $stats->{"misses"}->{ $key }->{"count"} += scalar @{ $miss->{ $key } };
            }
        }
        
        &Common::File::close_handle( $ifh );
    }

    if ( not $dryrun )
    {
        &Common::File::close_handles( $bar_fhs->{"F"} ) if defined $bar_fhs->{"F"};
        &Common::File::close_handles( $bar_fhs->{"R"} ) if defined $bar_fhs->{"R"};
        &Common::File::close_handles( $mis_fhs ) if $failed;
    }

    return $stats;
}

sub init_bar_stats
{
    # Niels Larsen, January 2013.
    
    # Initializes a statistics hash that write_demul_stats writes to file.

    my ( $conf,
        ) = @_;

    # Returns a hash.

    my ( $stats );

    $stats->{"name"} = "sequence-demultiplex-barcode";
    $stats->{"title"} = "Barcode de-multiplexing";

    $stats->{"ifiles"} = [
        {
            "title" => "Sequence file",
            "value" => $conf->seqfile ? &Common::File::full_file_path( $conf->seqfile ) : "Piped input",
        },{
            "type" => "html",
            "title" => "Barcode file",
            "value" => $conf->barfile,
        }];

    $stats->{"odir"} = {
        "title" => "Output directory",
        "value" => &Common::File::full_file_path( $conf->outdir ),
    };

    $stats->{"params"} = [
        {
            "title" => "Positions matched",
            "value" => $conf->{"maxpos"} + 1,
        },{
            "title" => "Pool forward/reverse",
            "value" => $conf->append ? "yes" : "no",
        },{
            "title" => "Include barcode sequence in names",
            "value" => $conf->outbar ? "yes" : "no",
        },{
            "title" => "Write non-matches to file",
            "value" => $conf->misfile ? "yes" : "no",
        }];


    return $stats;
}

sub init_demul_stats
{
    # Niels Larsen, January 2013.
    
    # Initializes a statistics hash that write_demul_stats writes to file.

    my ( $recipe,
         $conf,
        ) = @_;

    # Returns a hash.

    my ( $prifile, $barfile, $outpre, $prefix, $clobber, 
         $seqfiles, $stats, $outdir );

    $seqfiles = $conf->seqfiles;

    $prifile = $conf->prifile;
    $barfile = $conf->barfile;
    $outdir = $conf->outdir;
    $outpre = $conf->outpre;
    $clobber = $conf->clobber;

    $stats->{"name"} = "sequence-demultiplex";
    $stats->{"title"} = "Sequence de-multiplexing";

    # $prifile = &Common::File::full_file_path( $prifile );
    # $barfile = &Common::File::full_file_path( $barfile );

    # $prefix = &Common::File::full_file_path( $outdir );
    $prefix = $outdir ."/";

    &Common::File::delete_file_if_exists( $prefix ."barcodes.txt" ) if $clobber;
    &Common::File::copy_file( $barfile, $prefix ."barcodes.txt" );
 
    &Common::File::delete_file_if_exists( $prefix ."primers.txt" ) if $clobber;
    &Common::File::copy_file( $prifile, $prefix ."primers.txt" );

    $prifile = $prefix ."primers.txt";
    $barfile = $prefix ."barcodes.txt";

    if ( ref $seqfiles->[0] )
    {
        # Paired files,

        $stats->{"ifiles"} = [
            {
                "title" => "Paired files 1",
                "value" => [ map { $_->[0] } @{ $seqfiles } ],
            },{
                "title" => "Paired files 2",
                "value" => [ map { $_->[1] } @{ $seqfiles } ],
            }];
    }
    else 
    {
        # Unpaired or none,

        if ( ref $seqfiles ) {
            $seqfiles = [ map { &Common::File::full_file_path( $_ ) } @{ $seqfiles } ];
        } else {
            $seqfiles = "Piped input";
        }
        
        $stats->{"ifiles"} = [
            {
                "title" => "Sequence files",
                "value" => $seqfiles,
            }];
    }

    push @{ $stats->{"ifiles"} }, {
        "type" => "html",
        "title" => "Primer file",
        "value" => $prifile,
    },{
        "type" => "html",
        "title" => "Barcode file",
        "value" => $barfile,
    };

    $stats->{"outdir"} = {
        "title" => "Directory",
        "value" => $outdir,
    };
    
    $stats->{"params"} = [
        {
            "title" => "Barcode/primer spacing max",
            "value" => $conf->bargap,
        },{
            "title" => "Barcode quality minimum",
            "value" => $conf->barqual,
        },{
            "title" => "Barcode quality encoding",
            "value" => $conf->qualtype,
        },{
            "title" => "Pool forward/reverse reads",
            "value" => $conf->merge ? "yes" : "no",
        }];

    return $stats;
}

sub init_join_stats
{
    # Niels Larsen, March 2013. 

    # Initializes a statistics hash that is written to file.

    my ( $conf,
        ) = @_;

    # Returns a hash.

    my ( $pairs, $outpre, $prefix, $clobber, 
         $stats, $outdir, $maxbeg );

    $stats->{"name"} = "sequence-join-pairs";
    $stats->{"title"} = "Joining pair mates";

    $pairs = $conf->{"pairfiles"};

    $stats->{"params"} = [
        {
            "title" => "Minimum similarity",
            "value" => $conf->minsim . "%",
        },{
            "title" => "Minimum overlap length",
            "value" => $conf->minovl,
        },{
            "title" => "Include non-overlaps",
            "value" => $conf->misses ? "yes" : "no",
        },{
            "title" => "Delete input files",
            "value" => $conf->delete ? "yes" : "no",
        }];

    return $stats;
}

sub join_pairs
{
    # Niels Larsen, March 2013. 

    # Joins sequence pair mates, usually the next step for paired-end 
    # reads after de-multiplexing. Input files are sets of forward and 
    # reverse reads, in separate files, and outputs are half as many 
    # new files, with joined sequences in them. The join allows no 
    # gaps, only mismatches, and the highest quality base will prevail
    # in the output. When there are no overlap matches, the two reads
    # are concatenated.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $recipe, $defs, $conf, $pair, $f_file, $r_file, $f_fh, $r_fh,
         $readbuf, $f_seqs, $r_seqs, $fr_seqs, $minsim, $minovl, 
         $fr_fh, $joinsuf, $fr_file, $clobber, $read_sub, $write_sub,
         $misses, $delete, $time_start, $seconds, $stats, $f_seqs_p,
         $r_seqs_p, $f_total, $r_total, $fr_total, $fr_joined,
         $diff_msg );

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "format" => undef,
        "seqfiles" => [],
        "fwdsuf" => ".F",
        "revsuf" => ".R",
        "joinsuf" => ".join",
        "minsim" => 80,
        "minovl" => 20,
        "misses" => 0,
        "delete" => 0,
        "stats" => undef,
        "outdir" => undef,
        "readbuf" => 10_000,
        "dryrun" => 0,
        "clobber" => 0,
	"silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );    
    $conf = &Seq::Demul::join_pairs_args( $args );
    
    $Common::Messages::silent = $args->silent;

    &echo_bold("\nJoining pairs:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Initializing statistics ... ");
    $stats = &Seq::Demul::init_join_stats( $conf );
    &echo_done("done\n");

    $minsim = $conf->minsim;
    $minovl = $conf->minovl;
    $misses = $conf->misses;
    $delete = $conf->delete;
    $readbuf = $conf->readbuf;
    $clobber = $conf->clobber;

    $read_sub = &Seq::IO::get_read_routine( $conf->pairfiles->[0], $conf->format );
    $write_sub = &Seq::IO::get_write_routine( $conf->format );

    $time_start = &time_start();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> READ PAIRS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read from each pair of mate files and write to a single output file for
    # each pair. 

    foreach $pair ( @{ $conf->pairfiles } )
    {
        ( $f_file, $r_file, $fr_file ) = @{ $pair };

        $diff_msg = qq (The input file pairs\n\n  $f_file\n  $r_file\n\n)
            .qq (do not contain the same number of sequences. This typically\n)
            .qq (happens when de-multiplexing was not run in pair-mode, with\n)
            .qq (a pair-file.);
    
        &echo("   Writing ". &File::Basename::basename( $fr_file ) ." ... ");
        
        $f_fh = &Common::File::get_read_handle( $f_file );
        $r_fh = &Common::File::get_read_handle( $r_file );

        if ( $clobber ) {
            &Common::File::delete_file_if_exists( $fr_file );
        }

        $fr_fh = &Common::File::get_write_handle( $fr_file );

        $f_total = 0;
        $r_total = 0;
        $fr_total = 0;
        $fr_joined = 0;

        # Read single pairs, write joined,

        {
            no strict "refs";

            while ( $f_seqs = $read_sub->( $f_fh, $readbuf ) )
            {
                $r_seqs = $read_sub->( $r_fh, $readbuf );

                if ( defined $f_seqs ) {
                    $f_total += scalar @{ $f_seqs };
                } else {
                    &error( $diff_msg );
                }

                if ( defined $r_seqs ) {
                    $r_total += scalar @{ $r_seqs };
                } else {
                    &error( $diff_msg );
                }

                if ( $f_seqs->[0]->{"info"} =~ /seq_num/ )
                {
                    ( $f_seqs_p, $r_seqs_p ) = &Seq::List::pair_seq_lists( $f_seqs, $r_seqs );

                    $f_seqs = $f_seqs_p;
                    $r_seqs = $r_seqs_p;
                }

                $fr_seqs = &Seq::List::join_seq_pairs( $f_seqs, $r_seqs, $minsim, $minovl, $misses, 1 );

                $fr_total += scalar @{ $fr_seqs };
                $fr_joined += grep { $_->{"info"} =~ /seq_break=-1/ } @{ $fr_seqs };
                
                $write_sub->( $fr_fh, $fr_seqs );
            }
        }

        &Common::File::close_handle( $fr_fh );

        &Common::File::close_handle( $f_fh );
        &Common::File::close_handle( $r_fh );

        # Optional deletion of inputs,

        if ( $delete )
        {
            &Common::File::delete_file( $f_file );
            &Common::File::delete_file( $r_file );
        }

        # Save counts,

        push @{ $stats->{"table"} }, [
            &File::Basename::basename( $fr_file ),
            $f_total,
            $r_total,
            $fr_total,
            $fr_joined,
        ];

        &echo_done("$fr_joined / $fr_total\n");
    }

    $seconds = &time_elapsed() - $time_start;

    &echo("   Run-time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );

    $stats->{"seconds"} = $seconds;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    &Common::File::delete_file_if_exists( $conf->statfile ) if $clobber;
    &Seq::Demul::write_join_stats( $conf->statfile, bless $stats );

    &echo_bold("Finished\n\n");

    return;
}

sub join_pairs_args
{
    # Niels Larsen, March 2013.

    # Checks and expands the join pairs script arguments to a configuration
    # hash that suits the routines. It is checked here that files exist etc,
    # and fatal error messages are printed to STDERR. 

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $files, $file, $outdir, $conf, $fwdsuf, $revsuf, $joinsuf,
         $pair );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $files = $args->seqfiles and @{ $files } )
    { 
	&Common::File::check_files( $files, "efr", \@msgs );
        &append_or_exit( \@msgs );
        
        $conf->{"pairfiles"} = 
            &Seq::Demul::list_file_pairs( $files, $args->fwdsuf, $args->revsuf, @msgs );

        if ( not ( $conf->{"format"} = $args->format ) ) {
            $conf->{"format"} = &Seq::IO::detect_format( $files->[0], \@msgs );
        }
    }
    else {
        push @msgs, ["ERROR", qq (Input paired files must be given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf->{"fwdsuf"} = $args->fwdsuf;
    $conf->{"revsuf"} = $args->revsuf;

    $conf->{"minsim"} = $args->minsim;
    $conf->{"minovl"} = $args->minovl;
    $conf->{"misses"} = $args->misses;
    $conf->{"delete"} = $args->delete;

    $conf->{"clobber"} = $args->clobber;
    $conf->{"dryrun"} = $args->dryrun;

    $conf->{"readbuf"} = &Registry::Args::check_number( $args->readbuf, 1, undef, \@msgs );

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check directory,
    
    if ( $outdir = $args->outdir )
    {
        if ( $args->clobber ) {
            &Common::File::create_dir_if_not_exists( $outdir );
        }
        elsif ( not -d $outdir ) {
            push @msgs, ["ERROR", qq (Output directory does not exist -> "$outdir") ];
        }
        
        $conf->{"outdir"} = $outdir;
    } 
    else {
        push @msgs, ["ERROR", qq (Output directory must be given, but can be ".") ];
    }

    &append_or_exit( \@msgs );

    # Check the files to be created do not exist,
        
    $joinsuf = $args->joinsuf;
    
    $files = [];
    
    foreach $pair ( @{ $conf->{"pairfiles"} } ) 
    {
        $file = &File::Basename::basename( $pair->[0] );
        $file = &Common::Names::strip_suffix ( $file );
        $file = "$outdir/$file". $joinsuf;
        
        push @{ $files }, $file;
        
        $pair->[2] = $file;
    }

    if ( not $args->clobber ) {
        &Common::File::check_files( $files, "!e", \@msgs );
    }

    # Check statistics file,

    if ( $args->stats ) {
        $conf->{"statfile"} = $args->stats;
    } else {
        $conf->{"statfile"} = ($args->outdir//".") ."/seq_join_pairs.stats";
    }

    &Common::File::check_files([ $conf->{"statfile"}], "!e", \@msgs ) unless $args->clobber;

    if ( @msgs ) {
        push @msgs, ["INFO", qq (The --clobber option overwrites existing files) ];
    }

    &append_or_exit( \@msgs );

    bless $conf;
    
    return wantarray ? %{ $conf } : $conf;
}

sub list_file_pairs
{
    # Niels Larsen, March 2013.

    # Creates a list of pairs from the given list of files. All files must 
    # match the given forward or reverse suffix. Returns a list of
    # [ forward-file, reverse file ] tuples. 
    
    my ( $files,
         $fsuf,
         $rsuf,
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $file, %dict, $prefix, @msgs, @pairs );

    foreach $file ( @{ $files } )
    {
        if ( $file =~ /^(.+)$fsuf$/ or $file =~ /^(.+)$fsuf\./ ) {
            $dict{ $1 }->[0] = $file;
        } elsif ( $file =~ /^(.+)$rsuf$/ or $file =~ /^(.+)$rsuf\./ ) {
            $dict{ $1 }->[1] = $file;
        } else {
            push @msgs, ["ERROR", qq (File does not match "$fsuf" or "$rsuf" -> $file) ];
        }
    }

    foreach $prefix ( keys %dict )
    {
        if ( not defined $dict{ $prefix }->[0] ) {
            push @msgs, ["ERROR", qq (Forward file missing for "$prefix*") ];
        } elsif ( not defined $dict{ $prefix }->[1] ) {
            push @msgs, ["ERROR", qq (Reverse file missing for "$prefix*") ];
        } else {
            push @pairs, $dict{ $prefix };
        }
    }

    &append_or_exit( \@msgs, $msgs );
    
    return wantarray ? @pairs : \@pairs;
}

sub match_forward
{
    # Niels Larsen, April 2012. 

    # Helper routine that matches a pattern against a list of sequences in the
    # forward direction. Input is a sequence 
    # list, a single pattern hash, and a tag length. Output is a list 
    # of [ barcode, sequence object ]. The input list is not 
    # altered.

    my ( $seqs,   # Sequence list
         $ndcs,   # Sub-sequence indices
         $tlen,   # Tag length
         $gori,   # Complement the get-sequence - OPTIONAL, default off
        ) = @_;

    # Returns a list.

    my ( $iseq, $seq, $locs, $begpos, @hits );

    $gori //= "forward";

    for ( $iseq = 0; $iseq <= $#{ $seqs }; $iseq++ )
    {
        $seq = $seqs->[$iseq];
        
        if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} )->[0] and @{ $locs } )
        {
            if ( ( $begpos = $locs->[0]->[0] ) >= $tlen )
            {
                push @hits, [
                    ( substr $seq->{"seq"}, $begpos-$tlen, $tlen ),
                    &Seq::Common::sub_seq( $seq, [ @{ $locs }[ @{ $ndcs } ] ] )
                ];
            }
        }
    }

    if ( $gori eq "reverse" ) {
        map { &Seq::Common::complement( $_->[1] ) } @hits;
    }

    return wantarray ? @hits : \@hits;
}

sub match_forward_alter
{
    # Niels Larsen, April 2012. 

    # Helper routine that does forward matching, with altering of the 
    # input list. Input is a sequence list, a single pattern hash, and 
    # a tag length. Output is a list of matched sequences. 

    my ( $seqs,   # Sequence list
         $ndcs,   # Sub-sequence indices
         $gori,   # Complement the get-sequence - OPTIONAL, default off
         $minch,  # Minimum quality character - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $seq, $locs, $begpos, @hits );

    $gori //= "forward";
    
    foreach $seq ( @{ $seqs } )
    {
        if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} )->[0] and @{ $locs } )
        {
            &Seq::Common::sub_seq_clobber( $seq, [ @{ $locs }[ @{ $ndcs } ] ] );

            $seq->{"primer_beg"} = $locs->[0]->[0];

            # if ( $gori ) {
        }
    }

    # @{ $seqs } = grep { defined $_ } @{ $seqs };

    if ( $gori eq "reverse" ) {
        map { &Seq::Common::complement( $_->[1] ) } @hits;
    }

    return wantarray ? @hits : \@hits;
}

sub match_primer_bars
{
    # Niels Larsen, February 2013.

    # Matches a list of sequences with one primer and a choice of barcodes. 
    # Sequences that match the primer has the field "match" set to either 0,
    # "F" or "R", otherwise undefined. The field "barkey" is either a barcode
    # or an error code: if "match" is "F" or "R", then "barkey" is barcode.
    # If "match" is 0, then "barkey" is either $Nobar_key (no barcode found),
    # $Noqal_key (barcode has too low a quality) or $Nofit_key (there is no 
    # room for barcode between primer and read start). The caller must then
    # separate the sequences by testing the "match" field. This routine can 
    # be used both for single and paired reads. The input sequence list is 
    # not shrunk, but "match" and "barkey" fields are added. Returns the 
    # number of matches with both primer and barcode.

    my ( $seqs,      # Sequence list
         $args,      # Arguments hash
        ) = @_;

    # Returns integer.

    my ( $primer, @ndcs, $comp, $iseq, $barlens, $bardict, $maxgap, $minch, 
         $orient, $seq, $locs, $pribeg, $gap, $barlen, $barseq, $hits, 
         $stop );

    $primer = $args->{"primer"};          # primer info hash
    $barlens = $args->{"barlens"};        # sorted barcode lengths
    $bardict = $args->{"bardict"};        # hash with barcode keys
    $maxgap = $args->{"bargap"};          # max. primer / barcode spacing
    $minch = $args->{"minch"};            # min. required quality character
    $orient = $args->{"orient"};          # F or R to indicate direction
    
    # Pre-compile a pattern, this is how patscan wants it,

    &Bio::Patscan::compile_pattern( $primer->{"pattern-string"}, 0 );
    
    # Indices that are used to get the right sub-hits,

    @ndcs = @{ $primer->{"get-elements"} };

    # Set complement flag, 

    if ( $primer->{"get-orient"} eq "reverse" ) {
        $comp = 1;
    } else {
        $comp = 0;
    }

    $hits = 0;

    foreach $seq ( @{ $seqs } )
    {
        # Skip previous matches,

        next if defined $seq->{"match"};

        # >>>>>>>>>>>>>>>>>>>>>>>>>> PRIMER MATCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} )->[0] and @{ $locs } )
        {
            $pribeg = $locs->[0]->[0];
            
            if ( $barlens->[-1] > $pribeg )
            {
                # >>>>>>>>>>>>>>>>>> BARCODE TOO LONG <<<<<<<<<<<<<<<<<<<<<<<<<

                # The primer matches, but there are fewer upstream bases than
                # required for even the shortest barcode. Push these sequence 
                # onto a special key,
                
                $seq->{"match"} = 0;
                $seq->{"barkey"} = $Nofit_key;
            }
            else 
            {
                # >>>>>>>>>>>>>>>>>> LOOK FOR BARCODES <<<<<<<<<<<<<<<<<<<<<<<<

                for ( $gap = 0; $gap <= $maxgap; $gap += 1 )
                {
                    $stop = 0;

                    # Check the longest barcode first, then shorter ones.

                    foreach $barlen ( @{ $barlens } )
                    {
                        # Skip if barcode is too short when current spacing 
                        # between primer and barcode is considered,

                        next if $barlen > $pribeg - $gap;

                        # Get the barcode and check if it is one recognized by
                        # the dictionary. If there is one or more low quality 
                        # bases in the barcode, push the sequence entry to its
                        # special key. If not, push it under its respective 
                        # barcode, complemented or not,

                        $barseq = substr $seq->{"seq"}, $pribeg - $barlen - $gap, $barlen;
                        
                        if ( exists $bardict->{ $barseq } )
                        {
                            if ( $minch and &Seq::Common::count_quals_min_C( $barseq, 0, $barlen, $minch ) < $barlen )
                            {
                                $seq->{"match"} = 0;
                                $seq->{"barkey"} = $Noqal_key;
                            }
                            else
                            {
                                &Seq::Common::sub_seq_clobber( $seq, [ @{ $locs }[ @ndcs ] ] );
                                &Seq::Common::complement( $seq ) if $comp;

                                $seq->{"match"} = $orient;
                                $seq->{"barkey"} = $barseq;

                                $hits += 1;
                            }
                            
                            $stop = 1;
                            last;     # Stop looking if there is match
                        }
                    }
                    
                    last if $stop;    # Stop looking if there is match
                }
                
                # No sub-sequence found that matches a barcode in the dictionary,
                
                if ( not $stop )
                {
                    $seq->{"match"} = 0;
                    $seq->{"barkey"} = $Nobar_key;
                }
            }
        }
    }

    return $hits;
}

sub match_reverse
{
    # Helper routine that matches against the complements of the given 
    # sequences. Input is a sequence list, a single pattern hash, and a 
    # tag length. Output is a list 
    # of [ barcode, sequence object ]. The input list is not 
    # altered.

    my ( $seqs,   # Sequence list
         $ndcs,   # Sub-sequence indices
         $tlen,   # Tag length
         $gori,   # Complement the get-sequence
        ) = @_;

    # Returns a list.

    my ( $iseq, $seq, $cseq, $locs, $begpos, @hits );

    $gori //= "forward";

    for ( $iseq = 0; $iseq <= $#{ $seqs }; $iseq++ )
    {
        $cseq = &Seq::Common::complement( $seqs->[$iseq] );
        
        if ( $locs = &Bio::Patscan::match_forward( $cseq->{"seq"} )->[0] and @{ $locs } )
        {
            if ( ( $begpos = $locs->[0]->[0] ) >= $tlen )
            {
                push @hits, [
                    ( substr $cseq->{"seq"}, $begpos-$tlen, $tlen ),
                    &Seq::Common::sub_seq( $cseq, [ @{ $locs }[ @{ $ndcs } ] ] )
                ];
            }
        }
    }
    
    if ( $gori eq "reverse" ) {
        map { &Seq::Common::complement( $_->[1] ) } @hits;
    }

    return wantarray ? @hits : \@hits;
}

sub match_reverse_alter
{
    # Niels Larsen, April 2012. 

    # Helper routine that does reverse matching, with altering of the 
    # input list. Input is a sequence list, a single pattern hash, and 
    # a tag length. Output is a list of unmatched sequences. 

    my ( $seqs,   # Sequence list
         $ndcs,   # Pattern hash
         $gori,   # Complement the get-sequence
        ) = @_;

    # Returns a list.

    my ( @get_ndcs, $iseq, $seq, $locs, $begpos, @hits, @seq_ndcs );

    $gori //= "forward";

    for ( $iseq = 0; $iseq <= $#{ $seqs }; $iseq++ )
    {
        $seq = $seqs->[$iseq];
        
        if ( $locs = &Bio::Patscan::match_reverse_alt( $seq->{"seq"} )->[0] and @{ $locs } )
        {
            $seq->{"qual"} = reverse $seq->{"qual"} if $seq->{"qual"};
            
            push @hits, [
                ( substr $seq->{"seq"}, 0, $locs->[0]->[0] ),
                &Seq::Common::sub_seq_clobber( $seq, [ @{ $locs }[ @{ $ndcs } ] ] )
            ];
            
            undef $seqs->[$iseq];
        }
    }
    
    if ( $gori eq "reverse" ) {
        map { &Seq::Common::complement( $_->[1] ) } @hits;
    }

    @{ $seqs } = grep { defined $_ } @{ $seqs };
    
    return wantarray ? @hits : \@hits;
}

sub open_bar_handles
{
    # Niels Larsen, February 2013. 

    # Gets an orientation => barcode => file name hash and makes and returns
    # an orientation => barcode => file handle hash. The arguments can have 
    # an "outdir" and "clobber" option. 

    my ( $dict,     # Barcode dictionary
         $args,     # Arguments hash
        ) = @_;

    # Returns a hash.

    my ( $ori, $barseq, $count, $fhs, $suffix );

    $suffix = $args->suffix // "";

    if ( $args->clobber )
    {
        foreach $ori ( "F", "R" )
        {
            if ( exists $dict->{ $ori } )
            {
                foreach $barseq ( keys %{ $dict->{ $ori } } )
                {
                    &Common::File::delete_file_if_exists(
                         $dict->{ $ori }->{ $barseq }->file . $suffix );
                }
            }
        }
    }
    
    $count = 0;
    
    foreach $ori ( "F", "R" )
    {
        if ( exists $dict->{ $ori } )
        {
            $fhs->{ $ori } = &Seq::Demul::open_handles( $dict->{ $ori }, bless {
                "outdir" => $args->outdir, "clobber" => 0, "suffix" => $suffix } );
            
            $count += keys %{ $fhs->{ $ori } };
        }
    }

    return ( $fhs, $count );
}

sub open_handles
{
    # Niels Larsen, December 2011. 

    # Gets a barcode => filename hash and makes a barcode => filehandle hash.
    # All file handles are append-handles. The arguments can have an "outdir"
    # and "clobber" option. Returns a barcode => filehandle hash.

    my ( $dict,   # Barcode => file names hash
         $args,   # Arguments hash
        ) = @_;

    # Returns a hash.

    my ( $fhs, $tag, $file, $suffix );

    $suffix = $args->suffix // "";

    if ( $args->outdir ) {
        &Common::File::create_dir_if_not_exists( $args->outdir );
    }

    if ( $args->clobber )
    {
        foreach $tag ( keys %{ $dict } )
        {
            $file = $dict->{ $tag }->file . $suffix;
            &Common::File::delete_file_if_exists( $file );
        }
    }

    foreach $tag ( keys %{ $dict } )
    {
        $file = $dict->{ $tag }->file . $suffix;
        $fhs->{ $tag } = &Common::File::get_append_handle( $file );
    }

    return $fhs;
}

sub write_demul_stats
{
    # Niels Larsen, February 2012. 

    # Writes a Config::General formatted file with tags that are understood 
    # by Recipe::Stats::html_body. Composes a string that is either returned
    # (if defined wantarray) or written to file. 

    my ( $sfile,    # Output file
         $stats,    # Statistics hash
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $time, $itotal, $row, $str, $mulpct, $file, $file_str, 
         $param_str, $item, $title, $value, $type, $size, $table, @vals, 
         $hdrs, $ftot, $rtot, @totrow, $multot, $menu, $count, $pct, 
         $omiss, $key, @barvals, @barhdrs, $ori, $i, $barseq, $stat, $singles,
         $stot, @tothdrs, $tot, @ndcs, @mishdrs, $name, $singtot, $secs );

    $itotal = $stats->{"iseqs"} // 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLIFY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get a title and values array from the statistics hash,

    $singles = $stats->{"singles"};

    foreach $ori ( "F", "R" )
    {
        if ( exists $stats->{"hits"}->{ $ori } )
        {
            push @barhdrs, "$ori-files", "$ori-barcode", "$ori-count", "$ori-pct";

            if ( exists $singles->{ $ori } )
            {
                push @barhdrs, "$ori-nopair";
            }
            
            $i = 0;

            foreach $barseq ( sort keys %{ $stats->{"hits"}->{ $ori } } )
            {
                $stat = $stats->{"hits"}->{ $ori }->{ $barseq };

                $file = $stat->{"file"};
                $count = $stat->{"count"} // 0;

                if ( $itotal ) {
                    $pct = 100 * $count / $itotal;
                } else {
                    $pct = 0;
                }

                if ( $barvals[$i] ) {
                    push @{ $barvals[$i] }, $file, $barseq, $count, $pct;
                } else {
                    $barvals[$i] = [ $file, $barseq, $count, $pct ];
                }

                if ( $singles->{ $ori } )
                {
                    $count = $singles->{ $ori }->{ $barseq }->{"count"} // 0;
                    push @{ $barvals[$i] }, $count;
                }

                $i += 1;
            }
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $multot = 0;

    if ( keys %{ $singles } ) 
    {
        if ( scalar @{ $barvals[0] } > 5 ) {
            map { $multot += $_->[2] + $_->[7] } @barvals;
        } else {
            map { $multot += $_->[2] } @barvals;
        }
    }
    else
    {
        if ( scalar @{ $barvals[0] } > 4 ) {
            map { $multot += $_->[2] + $_->[6] } @barvals;
        } else {
            map { $multot += $_->[2] } @barvals;
        }
    }

    if ( $itotal ) {
        $mulpct = sprintf "%.2f", 100 * $multot / $itotal;
    } else {
        $mulpct = "0.00";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ASSEMBLE HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $file_str = &Seq::Stats::format_files( $stats->{"ifiles"} );
    $param_str = &Seq::Stats::format_params( $stats->{"params"} );

    $secs = $stats->{"seconds"};
    $time = &Time::Duration::duration( $secs );

    $itotal = $stats->{"iseqs"} // 0;

    $text = qq (
<stats>

   title = $stats->{"title"} 
   name = $stats->{"name"}

   <header>
$file_str
      hrow = Total input reads\t$itotal
      hrow = Total output reads\t$multot ($mulpct%)
);

    $text .= qq ($param_str
      date = $stats->{"finished"}
      secs = $secs
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PROBLEMS TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $omiss = $stats->{"misses"} )
    {
        $text .= qq (
   <table>
      title = Reads that did not de-multiplex
      colh = Problem type\tReads\tPct.\tProblem reads file
);

        foreach $row ( @Mis_keys )
        {
            ( $key, $str ) = @{ $row };
            
            if ( $stats->{"type"} ne "pairs" ) {
                next if $key eq $Noori_key or $key eq $Nopar_key;
            }
            
            
            $size = -s $stats->{"outdir"}->{"value"} ."/". $omiss->{ $key }->{"file"};
            $count = $omiss->{ $key }->{"count"} // 0;
            
            if ( $itotal ) {
                $pct = sprintf "%.2f", 100 * $count / $itotal;
            } else {
                $pct = "0.00";
            }
            
            if ( $size )
            {
                $name = &File::Basename::basename( $omiss->{ $key }->{"file"} ); 

                $size = &Common::Util::abbreviate_number( $size );
                $text .= qq (      trow = $str\t$count\t$pct\thtml=$name ($size):$name\n);
            }
            else {
                $text .= qq (      trow = $str\t$count\t$pct\t\n);
            }            
        }
        
        $text .= qq (   </table>\n);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> BARCODES TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $hdrs = join "\t", @barhdrs;

    $text .= qq (
   <table>
      title = De-multiplex counts by barcode
      colh = $hdrs
);

    $rtot = 0;
    $stot = 0;

    @ndcs = grep /files$/, @barhdrs;
    @ndcs = &Common::Table::names_to_indices( \@ndcs, \@barhdrs );

    foreach $row ( sort { $b->[2] <=> $a->[2] } @barvals )
    {
        $row->[2] //= 0;
        $row->[3] = sprintf "%.2f", $row->[3] // 0;
        
        if ( keys %{ $singles } )
        {
            if ( scalar @{ $row } > 5 )
            {
                $row->[5] //= 0;
                
                $rtot += $row->[7] // 0;
                $stot += $row->[9] // 0;

                $row->[7] //= 0;
                $row->[8] = sprintf "%.2f", $row->[8] // 0;
                $row->[9] //= 0;
            }
        }
        else
        {
            if ( scalar @{ $row } > 4 )
            {
                $row->[4] //= 0;
                
                $rtot += $row->[6] // 0;

                $row->[6] //= 0;
                $row->[7] = sprintf "%.2f", $row->[7] // 0;
            }
        }

        foreach $i ( @ndcs ) {
            $row->[$i] = "file=$row->[$i]";
        }

        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }
        
    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_join_stats
{
    # Niels Larsen, March 2013. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $time, $f_total, $r_total, $fr_total, $fr_joined, $secs,
         $join_pct, $row, $str, $file, $param_str, $item, @row, $values );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> ASSEMBLE HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $param_str = &Seq::Stats::format_params( $stats->{"params"} );

    $secs = $stats->{"seconds"};
    $time = &Time::Duration::duration( $secs );

    $values = $stats->{"table"};

    $f_total = &List::Util::sum( map { $_->[1] } @{ $values } );
    $r_total = &List::Util::sum( map { $_->[2] } @{ $values } );
    $fr_total = &List::Util::sum( map { $_->[3] } @{ $values } );
    $fr_joined = &List::Util::sum( map { $_->[4] } @{ $values } );

    $join_pct = sprintf "%.2f", 100 * $fr_joined / $fr_total;

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
      hrow = Forward input reads\t$f_total
      hrow = Reverse input reads\t$r_total
      hrow = Input read pairs\t$fr_total
      hrow = Joined read pairs\t$fr_joined ($join_pct%)
$param_str
      date = $stats->{"finished"}
      secs = $secs
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> COUNTS TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text .= qq (
   <table>
      title = Join statistics per file
      colh = Joined files\tF-reads\tR-reads\tFR-both\tJoined\tJoined %
);

    foreach $row ( sort { $b->[1] <=> $a->[1] } @{ $values } )
    {
        @row = @{ $row }[ 0 ... 4 ];

        if ( $row->[4] == 0 ) {
            push @row, sprintf "%.2f", 0;
        } else {
            push @row, sprintf "%.2f", 100 * $row->[4] / $row->[3];
        }
        
        $row[0] = "file=$row[0]";

        $str = join "\t", @row;
        $text .= qq (      trow = $str\n);
    }

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

1;

__END__


    # # >>>>>>>>>>>>>>>>>>>>>>>>> INDEX INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # foreach $file ( $args{"ifile1"}, $args{"ifile2"} )
    # {
    #     if ( not &Seq::Storage::is_indexed( $file ) )
    #     {
    #         &echo("   Indexing fastq sequences ... ");
            
    #         &Seq::Storage::create_indices(
    #              {
    #                  "ifiles" => [ $file ],
    #                  "progtype" => "fetch",
    #                  "count" => 1,
    #                  "clobber" => 1,
    #                  "silent" => 1,
    #              });
            
    #         $count = &Seq::Storage::get_index_config( $file . $Seq::Storage::Index_suffix )->seq_count;
    #         &echo_done("$count\n");
    #     }
    # }
# sub create_pat_dict
# {
#     # Niels Larsen, April 2012. 

#     # Reads a table of primer pairs and creates a list of primer pairs. The table
#     # format is sequence<tab>orient<tab>id. The output is a list of hashes, one 
#     # for each primer pair, with these keys and values,
#     #
#     # primer_name => Primer title
#     # forward_pattern => barcode / forward primer / mature sequence 
#     # reverse_pattern => barcode / reverse primer / mature sequence
#     # forward_primer => forward primer
#     # reverse_primer => reverse primer
#     # get_subpats => Sub-sequences to cut out

#     my ( $args,
#          $msgs,
#         ) = @_;

#     # Returns a hash.

#     my ( @pris, @pats, $pri, %dict, $orient, $outdir, $priname, $priseq, 
#          $pristr, @msgs, $i, $pat, $indels, $prikey, $patkey, $patstr,
#          @dict );

#     # Read table primers,

#     @pris = &Seq::IO::read_table_primers( $args->{"prifile"}, \@msgs );
#     &append_or_exit( \@msgs );

#     &dump( \@pris );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PHYLO PRIMERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     foreach $pri ( @pris )
#     {
#         $orient = $pri->{"Orient"};
#         $priseq = $pri->{"Seq"};
#         $priname = $pri->{"ID"};

#         $priname =~ s/\W/ /g;
#         $priname =~ s/\s+/ /g; 
#         $priname =~ s/ /_/g; 
        
#         $dict{ $priname }{"primer_name"} = $priname;

#         if ( $orient =~ /^(forward|reverse)$/ ) {
#             push @{ $dict{ $priname }{ $orient ."_primer"} }, $priseq;
#         } else {
#             push @msgs, ["ERROR", qq (Wrong looking orientation in $args->{"prifile"} -> "$orient")];
#         }
#     }

#     &dump( \%dict );

#     &append_or_exit( \@msgs );
    
#     exit;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     @dict = sort { $a->{"primer_name"} cmp $b->{"primer_name"} } values %dict;
    
#     &dump( \@dict );
#     exit;
#     return wantarray ? @dict : \@dict;
# }
