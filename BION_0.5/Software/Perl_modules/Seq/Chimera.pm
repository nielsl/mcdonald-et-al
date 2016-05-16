package Seq::Chimera;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that do chimeric sequence handling. Only works well for two-fragment 
# ones, but many three-fragment variants score high too. Better handling of 
# those can be done if needed of course. For method description, see
# 
#  seq_chimera --help 
#
# which displays text from Seq::Help. 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( *AUTOLOAD );

use Config;
use Time::Duration qw ( duration );
use POSIX ":sys_wait_h";
use File::Basename;
use Fcntl qw ( LOCK_SH LOCK_EX LOCK_UN );

use Data::MessagePack;
use Statistics::Histogram;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &check_files
                 &check_files_args
                 &check_files_parallel
                 &check_files_single
                 &check_seqs
                 &close_io
                 &create_db_map
                 &create_debug_hist
                 &create_query_map
                 &debug_db_map
                 &debug_query_map
                 &init_buffers
                 &init_stats
                 &is_db_map_cached
                 &io_files
                 &read_db_map
                 &set_pack_long
                 &sort_tables
                 &write_db_map
                 &write_seqs
                 &write_stats_all
                 &write_stats_file
                 &write_stats_sum
                 &write_table

                 &create_stat_C
                 &measure_difs_left_C
                 &measure_difs_right_C
                  );

use Common::Config;
use Common::Messages;
use Common::File;
use Common::Util_C;

use Registry::Args;

use Seq::IO;
use Seq::Oligos;
use Seq::Stats;

use Recipe::IO;
use Recipe::Steps;
use Recipe::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Max_int, $Q_max_seqlen, $DB_max_seqlen, %Suffixes );

$Max_int = 2 ** 30;

$Q_max_seqlen = 10_000;    # Current maximum is 65536, which can be lifted
$DB_max_seqlen = 10_000;    # Current maximum is 65536, which can be lifted

# Output files are named <input-file> + these strings,

%Suffixes = (
    "cache" => ".chimrank",          # Reference data cache
    "table" => ".chimtab",           # Table with scores and breakpoints
    "chim" => ".chim",               # Chimera sequences 
    "nochim" => ".nochim",           # Non-chimera sequences
    "histo" => ".chist",             # Score distribution histogram
    "stats" => ".stats",             # Chimera counts 
    "chimd" => ".chim.debug",        # Debug output for chimeras
    "nochimd" => ".nochim.debug",    # Debug output for non-chimeras
);

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INLINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my $inline_dir;

BEGIN
{
    $inline_dir = &Common::Config::create_inline_dir("Seq/Chimera");
    $ENV{"PERL_INLINE_DIRECTORY"} = $inline_dir;
}

use Inline C => 'DATA', "DIRECTORY" => $inline_dir, "CCFLAGS" => "-g -std=c99";

Inline->init;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_files
{
    # Niels Larsen, August 2012. 

    # Measures di-meric chimera potential of DNA/RNA gene sequences. Inputs
    # are one or more query files and a reference dataset. It was developed 
    # for PCR amplified 16S rRNA, but should work for other molecules. The 
    # method does not align sequences and is quite fast, see --help. The 
    # method does not align sequences. The reference sequences are converted 
    # to a read-only map that is held in RAM. On multi-core machines, each 
    # core will run an input file and will re-use that reference map. For 
    # each input file a score table and a chimera and non-chimera file are 
    # written, in the same format as the inputs. Returns nothing.
    
    my ( $seqs,    # Query file name
         $args,    # Arguments hash 
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $run_start, $chi_tot, $nochi_tot, $pct, 
         $nochi_pct, $db_map, $seq_total, $stats, $time_start, $seconds, 
         $recipe, $cpus, $cores, $counts );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "qseqs" => undef,
        "wordlen" => 8,
        "steplen" => 4,
        "minsco" => 30,
        "minfrag" => 80,
        "denovo" => 0,
        "cores" => undef,
        "minlen" => 1,
        "maxlen" => $Q_max_seqlen,
        "degap" => 0,
        "seqbuf" => 2000,
        "dbname" => undef,
        "dbfile" => undef,
        "dbminlen" => 1,
        "dbmaxlen" => $DB_max_seqlen,
        "dbdegap" => 0,
        "dbseqbuf" => 5000,
        "outdir" => undef,
        "chist" => undef,
        "stats" => undef,
        "debug" => 0,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $args->qseqs( $seqs );
    $conf = &Seq::Chimera::check_files_args( $args, $defs );

    $Common::Messages::silent = $args->silent;
    $run_start = time();

    &echo_bold("\nChimera checking:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> DETERMINE CORES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get cores if not given,

    if ( not defined ( $cores = $conf->cores ) )
    {
        &echo("   Checking hardware ... ");

        ( $cpus, $cores ) = &Common::OS::cpus_and_cores();
        $conf->cores( $cores );
                
        &echo_done("$cpus cpu[s], $cores core[s]\n");
    }

    # >>>>>>>>>>>>>>>>>>>> BUILD OR LOAD REFERENCE MAP <<<<<<<<<<<<<<<<<<<<<<<<
    
    # The reference data map cache is loaded if up to date, otherwise built
    # and written,

    if ( &Seq::Chimera::is_db_map_cached( $conf->dbfile, $conf->wordlen ) )
    {
        &echo("   Loading reference map ... ");
        
        $db_map = &Seq::Chimera::read_db_map( $conf->dbfile );

        &echo_done("done\n");
    }
    else
    {
        &echo("   Building reference map ... ");
        
        $db_map = &Seq::Chimera::create_db_map(
            $conf->dbfile,
            bless {
                "format" => $conf->dbformat,
                "wordlen" => $conf->wordlen,
                "minlen" => $conf->dbminlen,
                "dbmaxlen" => $conf->dbmaxlen,
                "seqbuf" => $conf->dbseqbuf,
                "degap" => $conf->dbdegap,
                "wconly" => 1,
            });
        
        &Seq::Chimera::write_db_map( $conf->dbfile, $db_map );
        
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> RUN THE CHECK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $time_start = &time_start();
    $stats = &Seq::Chimera::init_stats( $conf );

    &echo("   Checking for chimeras ... ");

    if ( $cores > 1 ) {
        &Seq::Chimera::check_files_parallel( $db_map, $conf );
    } else {
        &Seq::Chimera::check_files_single( $db_map, $conf );
    }

    undef $db_map;

    &echo_done("done\n");

    $stats->{"seconds"} = &time_elapsed() - $time_start;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    # >>>>>>>>>>>>>>>>>>>>>>>> SORT OUTPUT TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Sorting output tables ... ");

    &Seq::Chimera::sort_tables( $conf );

    &echo_done("done\n");
    
    # # >>>>>>>>>>>>>>>>>>>>>>> WRITING HISTOGRAM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # if ( @scores )
    # {
    #     # To prevent crash with single element,

    #     unshift @scores, 0 if scalar @scores == 1;

    #     &echo("   Writing score histogram ... ");
        
    #     $fh = &Common::File::get_write_handle( $conf->chist );
    #     $fh->print( &Statistics::Histogram::get_histogram( \@scores, 1000, 1 ) );
    #     &Common::File::close_handle( $fh );
        
    #     &echo_done("   done\n");
    # }

    # # >>>>>>>>>>>>>>>>>>>>>>>>> MAKE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Creating statistics files ... ");

    $counts = &Seq::Chimera::write_stats_all( $stats, $conf );
    
    $chi_tot = &List::Util::sum( map { $_->{"chi_seqs"} } values %{ $counts } );
    $nochi_tot = &List::Util::sum( map { $_->{"nochi_seqs"} } values %{ $counts } );

    $seq_total = $chi_tot + $nochi_tot;

    &echo_done("done\n");
    
    # # >>>>>>>>>>>>>>>>>>>>>>>>>> SCREEN MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Chimeras found: ");
    $pct = sprintf "%.2f", 100 * $chi_tot / $seq_total;
    &echo_done("$chi_tot ($pct%)\n");

    &echo("   Non-chimeras: ");
    $pct = sprintf "%.2f", 100 * $nochi_tot / $seq_total;
    &echo_done("$nochi_tot ($pct%)\n");
    
    &echo("   Run time: ");
    &echo_info( &Time::Duration::duration( time() - $run_start ) ."\n" );    

    &echo_bold("Finished\n\n");

    return ( $chi_tot, $nochi_tot );
}

sub check_files_args
{
    # Niels Larsen, August 2012.

    # Validates arguments and returns error and info messages if something 
    # is wrong.

    my ( $args,    # Command line argument hash
         ) = @_;

    # Returns a hash. 

    my ( $format, @msgs, $wordlen, $name, %args, $dir, $str, @files, $file,
         $suffixes, $suffix, $count, $outdir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $wordlen = $args->wordlen;

    if ( $wordlen ) {
        $args{"wordlen"} = &Registry::Args::check_number( $wordlen, 6, 13, \@msgs );
    } else {
        push @msgs, [ "ERROR", qq (Word length must be given - 8 to 10 is often best) ];
    }        

    &append_or_exit( \@msgs );

    $args{"steplen"} = &Registry::Args::check_number( $args->steplen, 1, $wordlen, \@msgs );
    $args{"minsco"} = &Registry::Args::check_number( $args->minsco, 0, undef, \@msgs );
    $args{"minfrag"} = &Registry::Args::check_number( $args->minfrag, 1, undef, \@msgs );

    $args{"denovo"} = $args->denovo;
    $args{"cores"} = $args->cores;
    
    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> QUERY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args{"qseqs"} = $args->qseqs;

    if ( @{ $args{"qseqs"} } )
    {
        &Common::File::check_files( $args{"qseqs"}, "r", \@msgs );
        &append_or_exit( \@msgs );

        $args{"qseqs"} = [ grep { -s $_ } @{ $args{"qseqs"} } ];

        foreach $file ( @{ $args{"qseqs"} } )
        {
            $format = &Seq::IO::detect_format( $file, \@msgs );
        
            if ( $format and $format !~ /^fastq|fasta|fasta_wrapped$/ ) {
                push @msgs, ["ERROR", qq (Wrong looking query file format -> "$format") ];
            }
        }

        if ( @msgs ) {
            push @msgs, ["INFO", qq (Supported formats are: fasta, fastq, fasta_wrapped) ];
        }
    }
    elsif ( -t STDIN )
    {
        push @msgs, ["ERROR", qq (Query sequence must be specified or piped) ];
    }
    elsif ( not $args{"format"} )
    {
        push @msgs, ["ERROR", qq (Query sequence input format must be given for piped input) ];
    }
    
    &append_or_exit( \@msgs );

    $args{"minlen"} = &Registry::Args::check_number( $args->minlen, 1, $Q_max_seqlen, \@msgs );
    $args{"maxlen"} = &Registry::Args::check_number( $args->maxlen, $args{"minlen"}, $Q_max_seqlen, \@msgs );

    $args{"degap"} = $args->degap;
    $args{"seqbuf"} = $args->seqbuf;

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $name = $args->dbname )
    {
        if ( not $args{"dbfile"} = $Taxonomy::Config::DB_files{ $name } )
        {
            push @msgs, ["ERROR", qq (Wrong looking dataset name -> "$name") ];
            push @msgs, ["INFO", qq (Choices are one of:) ];
            
            map { push @msgs, ["INFO", $_ ] } @Taxonomy::Config::DB_names;
        }

        &append_or_exit( \@msgs );
    }
    else {
        $args{"dbfile"} = $args->dbfile;
    }

    if ( $file = $args{"dbfile"} )
    {
        &Common::File::check_files([ $file ], "r", \@msgs );
        
        if ( -r $file )
        {
            $format = &Seq::IO::detect_format( $file, \@msgs );

            if ( $format =~ /^fastq|fasta|fasta_wrapped$/ ) 
            {
                $args{"dbformat"} = $format;
            }
            else {
                push @msgs, ["ERROR", qq (Wrong looking $file file format -> "$format") ];
                push @msgs, ["INFO", qq (Supported formats are: fasta, fastq) ];
            }
        }
    }
    else {
        push @msgs, [ "ERROR", qq (Dataset file(s) must be specified) ];
    }

    &append_or_exit( \@msgs );

    $args{"dbminlen"} = &Registry::Args::check_number( $args->dbminlen, 1, $DB_max_seqlen, \@msgs );
    $args{"dbmaxlen"} = &Registry::Args::check_number( $args->dbmaxlen, $args{"dbminlen"}, $DB_max_seqlen, \@msgs );

    $args{"dbdegap"} = $args->dbdegap;
    $args{"dbseqbuf"} = $args->dbseqbuf;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $outdir = $args->outdir;
    $args{"outdir"} = $outdir;

    $suffixes = &Storable::dclone( \%Suffixes );
    
    if ( not $args{"debug"} )
    {
        delete $suffixes->{"chimd"};
        delete $suffixes->{"nochimd"};
    }
    
    @files = ();
    
    foreach $file ( @{ $args{"qseqs"} } )
    {
        $dir = &File::Basename::dirname( $file );
        $name = &File::Basename::basename( $file );
        
        if ( $name =~ /^([^\.]+)\./ or $name =~ /\.([^\.]+)\./ ) {
            $name = $1;
        } else {
            &error( qq (Wrong looking file -> "$file") );
        }
        
        $dir = $outdir if $outdir;
        
        foreach $suffix ( values %{ $suffixes } )
        {
            push @files, "$dir/$name$suffix";
        }
    }

    # $args{"opaths"} = \@files;

    if ( not $args->clobber )
    {
        &Common::File::check_files( \@files, "!e", \@msgs );

        if ( ( $count = scalar @msgs ) > 20 )
        {
            @msgs = ["ERROR", qq (There are $count existing output files) ];
            push @msgs, ["INFO", qq (Delete these or overwrite with --clobber) ];
        }

        &append_or_exit( \@msgs );
    }

    $args{"debug"} = $args->debug;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SWITCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args{"clobber"} = $args->clobber;
    $args{"silent"} = $args->silent;
    
    bless \%args;

    return wantarray ? %args : \%args;
}

sub check_files_parallel
{
    # Niels Larsen, October 2012. 

    # Runs chimera checking on multiple cores, by creating child processes.
    # A loop processes one file at a time by incrementally reading lists of
    # sequences. Each list is then given its own process that is started on 
    # a CPU core whenever one if free. Output depends on when a core is done,
    # which is unpredictable, and thus the output sequences order may be 
    # different from the input order. The number of cores is user settings,
    # but defaults to all available.

    my ( $db_map,
         $conf,
        ) = @_;

    # Returns nothing.

    my ( $q_file, $stats, $cpus, $cores, $core, $qf_ndx, $qf_max, @q_files,
         @pids, $pid, $done, $io, $reader, $writer, $bufs, $min_sco, 
         $read_args, $wordlen, $steplen, $clobber, $debug, $tab_file,
         $tmp_file, $seqs, $outdir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Settings for the query sequence reader,
    
    $read_args = bless {
        "wordlen" => $conf->wordlen,  # Oligo length
        "steplen" => $conf->steplen,  # Step length
        "degap" => $conf->degap,      # Remove gaps or not
        "minlen" => $conf->minlen,    # Minimum sequence length
        "maxlen" => $conf->maxlen,    # Maximum sequence length
        "filter" => undef,            # Annotation string filter expression
        "readbuf" => $conf->seqbuf,   # Seqs to read at a time
    };

    # Get read/write buffers,

    $bufs = &Seq::Chimera::init_buffers( $conf->maxlen, $db_map->{"stot"} );

    @q_files = @{ $conf->qseqs };
    
    # Sort input by descending size,

    @q_files = sort { -s $b <=> -s $a } @q_files;

    # Set variables,

    $qf_ndx = -1;
    $qf_max = $#q_files;
    
    $min_sco = $conf->minsco;
    $outdir = $conf->outdir;
    $clobber = $conf->clobber;
    $debug = $conf->debug;
    $cores = $conf->cores;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CHILD PROCESSES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $done = 0;

    while ( not $done )
    {
        # Check all cores in turn for running jobs and launch new ones when their
        # processes exit: @pids keeps the ids of running processes, and checking
        # these processes every 2 seconds will discover if they are done. If so,
        # more sequences are read and a new child process is launched. The files 
        # are done one at a time by incrementing the $qf_ndx file list index.
        
        for ( $core = 0; $core < $cores; $core++ )
        {
            # If no file has yet been opened, do it, and increment file list index,
            
            if ( not $io )
            {
                # Open the first input and outputs, and read from the input,

                $io = &Seq::Chimera::io_files( $q_files[ ++$qf_ndx ], $outdir, $clobber, $debug );
                $io->{"ifh"} = &Common::File::get_read_handle( $io->{"ifile"}, "exclusive" => 1 );

                select $io->{"ifh"}; $| = 1;

                $read_args->{"format"} = $io->{"format"};
            }

            # If nothing running on the core yet, or a running child process is 
            # finished, then fork a new one and store its id,
            
            if ( not $pids[ $core ] or waitpid( $pids[ $core ], WNOHANG ) > 0 )
            {
                $seqs = &Seq::IO::read_seqs_filter( $io->{"ifh"}, $read_args );
                
                # If there are no more data on the current file handle, then close 
                # it and open a handle on the next file in @q_files,

                if ( not $seqs and $qf_ndx < $qf_max )
                {
                    # Close current input and output files, open the next input and
                    # outputs, and read from the input,

                    &Common::File::close_handle( $io->{"ifh"} );

                    $io = &Seq::Chimera::io_files( $q_files[ ++$qf_ndx ], $outdir, $clobber, $debug );
                    $io->{"ifh"} = &Common::File::get_read_handle( $io->{"ifile"}, "exclusive" => 1 );

                    select $io->{"ifh"}; $| = 1;
                    
                    $read_args->{"format"} = $io->{"format"};

                    $seqs = &Seq::IO::read_seqs_filter( $io->{"ifh"}, $read_args );
                }
                
                # >>>>>>>>>>>>>>>>>>>> STOP IF NO SEQUENCE <<<<<<<<<<<<<<<<<<<<

                # If no sequence from the last file, then all is done,

                if ( not $seqs )
                {
                    $done = 1;
                    last;
                }

                # >>>>>>>>>>>>>>>>>>>>>>> FORK CHILDREN <<<<<<<<<<<<<<<<<<<<<<<

                $pid = fork();
                    
                if ( $pid > 0 ) 
                {
                    # Save the new child's process id in the @pids list,
                    
                    $pids[ $core ] = $pid;
                }
                elsif ( $pid == 0 )
                {
                    # Compare maps, write chimera and non-chimera sequences, and
                    # a score table,
                    
                    $stats = &Seq::Chimera::check_seqs( $seqs, $db_map, $bufs, $conf, $io );

                    # Lock file handles. No need to unlock, as child modifications do
                    # not affect the parent process,

                    &Seq::Chimera::write_seqs(
                        bless {
                            "seqs" => $seqs,
                            "stats" => $stats,
                            "minsco" => $min_sco,
                            "chim" => $io->{"chim"},
                            "nochim" => $io->{"nochim"},
                            "writer" => $io->{"writer"},
                        });

                    &Seq::Chimera::write_table(
                        bless {
                            "seqs" => $seqs,
                            "stats" => $stats,
                            "table" => $io->{"table"},
                        });

                    exit 0;
                }
                else {
                    &error("Fork failed");
                }
            }
        }

        sleep 2;
    }

    &Common::File::close_handle( $io->{"ifh"} );

    # Wait for completion of all processes,

    do { $pid = waitpid( -1, 0 ) } while $pid > 0;

    return;
}

sub check_files_single
{
    # Niels Larsen, October 2012. 

    # Runs chimera checking on a single core, without child processes. This 
    # is good for debugging and takes slightly less memory when there is only
    # one core. 

    my ( $db_map,       # Reference oligo map
         $conf,         # Configuration hash
        ) = @_;

    # Returns nothing.

    my ( $q_file, $q_fh, $stats, $io, $bufs, $min_sco, $read_args, $clobber,
         $outdir, $debug, $seqs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Settings for the query sequence reader,
    
    $read_args = bless {
        "wordlen" => $conf->wordlen,  # Oligo length
        "steplen" => $conf->steplen,  # Step length
        "degap" => $conf->degap,      # Remove gaps or not
        "minlen" => $conf->minlen,    # Minimum sequence length
        "maxlen" => $conf->maxlen,    # Maximum sequence length
        "filter" => undef,            # Annotation string filter expression
        "readbuf" => $conf->seqbuf,   # Seqs to read at a time
    };

    # Read/write buffers,

    $bufs = &Seq::Chimera::init_buffers( $conf->maxlen, $db_map->{"stot"} );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $min_sco = $conf->minsco;
    $clobber = $conf->clobber;
    $debug = $conf->debug;
    $outdir = $conf->outdir;

    foreach $q_file ( @{ $conf->qseqs } )
    {
        $io = &Seq::Chimera::io_files( $q_file, $outdir, $clobber, $debug );
        
        $read_args->{"format"} = $io->{"format"};
        $q_fh = &Common::File::get_read_handle( $io->{"ifile"} );

        while ( $seqs = &Seq::IO::read_seqs_filter( $q_fh, $read_args ) )
        {
            # Compare maps, write chimera and non-chimera sequences, and
            # a score table,
            
            $stats = &Seq::Chimera::check_seqs( $seqs, $db_map, $bufs, $conf, $io );
                    
            &Seq::Chimera::write_seqs(
                bless {
                    "seqs" => $seqs,
                    "stats" => $stats,
                    "minsco" => $min_sco,
                    "chim" => $io->{"chim"},
                    "nochim" => $io->{"nochim"},
                    "writer" => $io->{"writer"},
                });
            
            &Seq::Chimera::write_table(
                bless {
                    "seqs" => $seqs,
                    "stats" => $stats,
                    "table" => $io->{"table"},
                });
        }

        &Common::File::close_handle( $q_fh );
    }
    
    return;
}

sub check_seqs
{
    # Niels Larsen, October 2012. 

    # Compares a list of query sequences against a reference dataset map. A 
    # list of statistics hashes is returned, one for each sequence.

    my ( $q_seqs,    # Query sequences
         $db_map,    # Reference map 
         $bufs,      # Read/write buffers
         $conf,      # Config object
         $io,        # IO file
        ) = @_;
    
    # Returns nothing.

    my ( $wordlen, $q_olis, $q_begs, @q_sums, $q_sum, $q_ndx, $q_tot, $db_ndcs,
         $db_begs, $db_lens, $db_stot, $db_hits, $left_ids, $left_tot, $rigt_ids, 
         $rigt_tot, $max_len, $i, $j, $debug, $steplen, @q_stats, $min_sco, 
         $q_stat, $hist, $db_sids, $offset, @left_ids, @left_tot, @rigt_ids, 
         @rigt_tot, $q_map, $q_seq, $left_sum, $rigt_sum, $int_stats, 
         $float_stats, $left_max, $rigt_max, $min_ndcs, $min_sums, @q_begs,
         $q_beg, $min_frag, $l_pack, @q_hists, @list, $ofh );
    
    # Variables,
    
    $wordlen = $conf->wordlen;
    $steplen = $conf->steplen;
    $min_frag = int ( $conf->minfrag / $steplen );
    $min_sco = $conf->minsco;    
    $debug = $conf->debug;

    $offset = int ( $wordlen / $steplen ) + 1;
    
    # Query map,
    
    $q_tot = scalar @{ $q_seqs };
    
    $q_map = &Seq::Chimera::create_query_map( $q_seqs, bless {
        "wordlen" => $wordlen,
        "steplen" => $steplen,
    });
    
    $q_olis = $q_map->{"olis"};                    # Runs of numeric oligos

    $l_pack = &Seq::Chimera::set_pack_long();
    
    @q_begs = unpack $l_pack ."*", ${ $q_map->{"begs"} };  # Oligo run starts    
    @q_sums = unpack "V*", ${ $q_map->{"sums"} };  # Oligo totals per sequence

    # Reference dataset map,
        
    $db_sids = $db_map->{"sids"};     # Sequence ids
    $db_ndcs = $db_map->{"ndcs"};     # Runs of sequence indices, for all oligos
    $db_begs = $db_map->{"begs"};     # Start offsets into ndcs for each oligo
    $db_lens = $db_map->{"lens"};     # Sequence totals for each oligo
    $db_stot = $db_map->{"stot"};     # Number of sequences read
    
    # Output and scratch arrays written used by C routines,
    
    $left_ids = $bufs->{"left_ids"};
    $left_tot = $bufs->{"left_tot"};
    $left_max = $bufs->{"left_max"};
    $rigt_ids = $bufs->{"rigt_ids"};
    $rigt_tot = $bufs->{"rigt_tot"};
    $rigt_max = $bufs->{"rigt_max"};
    $min_ndcs = $bufs->{"min_ndcs"};
    $min_sums = $bufs->{"min_sums"};
    $int_stats = $bufs->{"int_stats"};
    $float_stats = $bufs->{"float_stats"};
    $db_hits = $bufs->{"db_hits"};

    # Statistics,

    @q_stats = ();
    @q_hists = ();
    
    # >>>>>>>>>>>>>>>>>>>>>>> CHECK EACH SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<

    for ( $q_ndx = 0; $q_ndx < $q_tot; $q_ndx += 1 )
    {
        $q_beg = $q_begs[ $q_ndx ];
        $q_sum = $q_sums[ $q_ndx ];
        $q_seq = $q_seqs->[ $q_ndx ];

        # Move a breakpoint from left to right while keeping track of the 
        # reference id with the highest number of matching oligos, and that
        # number itself. The best-matching reference ID is in $left_ids for
        # each position in the query, and the corresponding number of oligos
        # in $left_tot,

        $left_sum = &Seq::Chimera::measure_difs_left_C(
            ${ $q_olis }, $q_beg, $q_sum, 
            ${ $db_ndcs }, ${ $db_begs }, ${ $db_lens }, $db_stot, ${ $db_hits },
            ${ $left_ids }, ${ $left_tot }, $offset );
        
        # Same, except from right to left,
        
        $rigt_sum = &Seq::Chimera::measure_difs_right_C(
            ${ $q_olis }, $q_beg, $q_sum, 
            ${ $db_ndcs }, ${ $db_begs }, ${ $db_lens }, $db_stot, ${ $db_hits },
            ${ $rigt_ids }, ${ $rigt_tot }, $offset );

        if ( $left_sum != $rigt_sum )
        {
            &error( qq (The left-lists have $left_sum elements, but the right-lists\n)
                   .qq ( have $rigt_sum. This is a programming error) );
        }

        # Distill breakpoint, scores and fragment ids from the difference 
        # lists,

        &Seq::Chimera::create_stat_C(
            $wordlen, $steplen, $left_sum, $min_frag,
            ${ $left_ids }, ${ $left_tot }, ${ $rigt_ids }, ${ $rigt_tot },
            ${ $min_sums }, ${ $min_ndcs }, ${ $left_max }, ${ $rigt_max },
            ${ $int_stats }, ${ $float_stats } );

        ( $q_stat->{"join_ndx"}, $q_stat->{"join_pos"}, 
          $q_stat->{"left_id"}, $q_stat->{"rigt_id"},
          $q_stat->{"edge_beg_ndx"}, $q_stat->{"edge_end_ndx"},
          $q_stat->{"score"},
        ) = unpack "V*", ${ $int_stats };
        
        ( $q_stat->{"left_sim"}, $q_stat->{"rigt_sim"},
          $q_stat->{"left_off"}, $q_stat->{"rigt_off"},
        ) = unpack "f*", ${ $float_stats };

        $q_stat->{"q_id"} = $q_seq->{"id"};
        $q_stat->{"q_len"} = length $q_seq->{"seq"};
        
        # Get reference dataset for each fragment,
        
        $q_stat->{"left_ref"} = $db_sids->[ $q_stat->{"left_id"} ];
        $q_stat->{"rigt_ref"} = $db_sids->[ $q_stat->{"rigt_id"} ];

        push @q_stats, &Storable::dclone( $q_stat );

        # >>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $debug )
        {
            push @q_hists, [ $q_stat->{"score"}, [ &Seq::Chimera::create_debug_hist(
                bless {
                    "q_sum" => $q_sum,
                    "q_seq" => $q_seq,
                    "left_tot" => [ unpack "V$left_sum", ${ $left_tot } ],
                    "rigt_tot" => [ unpack "V$rigt_sum", ${ $rigt_tot } ],
                    "step_len" => $steplen,
                    "word_len" => $wordlen,
                    "stat" => $q_stat,
                }) ] ];
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $debug )
    {
        if ( @list = grep { $_->[0] >= $min_sco } @q_hists )
        {
            $ofh = &Common::File::get_append_handle( $io->{"chimd"}, "exclusive" => 1 );

            foreach $hist ( @list )
            {
                $ofh->print( map { $_ ."\n" } @{ $hist->[1] } );
            }

            &Common::File::close_handle( $ofh );
        }
        
        if ( @list = grep { $_->[0] < $min_sco } @q_hists )
        {
            $ofh = &Common::File::get_append_handle( $io->{"nochimd"}, "exclusive" => 1 );

            foreach $hist ( @list )
            {
                $ofh->print( map { $_ ."\n" } @{ $hist->[1] } );
            }

            &Common::File::close_handle( $ofh );
        }
    }

    return \@q_stats;
}

sub close_io
{
    # Niels Larsen, October 2012. 

    # Closes all open handles in a given IO object.

    my ( $io,
        ) = @_;

    my ( $key );

    foreach $key ( keys %{ $io } )
    {
        if ( ref $io->{ $key } )
        {
            &Common::File::close_handle( $io->{ $key } );

            delete $io->{ $key };
        }
    }

    return $io;
}

sub create_db_map
{ 
    # Niels Larsen, February 2012.

    # Builds an oligo map from a sequence file, as the chimera checker wants
    # it. The map has three C arrays, two integers and a perl id list:
    #
    # 1 ndcs: concatenated runs of sequence indices, one stretch per oligo
    # 2 begs: indices into ndcs where each run starts
    # 3 lens: the number of ndcs elements for each oligo
    # 4 stot: total number of sequences
    # 5 wlen: oligo (word) length
    # 6 sids: sequence ids perl list
    # 
    # The three arrays 1, 2 and 3 are packed strings that map to C arrays used 
    # by the routines in this module. They have these datatypes,
    #
    # ndcs: 4 bytes (unsigned int)
    # begs: 4/8 bytes (unsigned long, 8 bytes if C compiler supports it)
    # lens: 2 bytes (unsigned short) 
    #
    # The ram usage is about 5-6 times the sequence file size. The keys for the
    # input argument switches are,
    # 
    # degap: remove gaps or not
    # minlen: minimum sequence length
    # maxlen: maximum sequence length
    # wconly: skip non-canonical bases or not
    # filter: annotation string filter expression
    # format: sequence format (whatever Seq::IO supports)
    # readlen: sequences to read at a time
    # wordlen:  oligo word length
    # 
    # Output is a hash with references to 1-6 above, with the listed names as 
    # keys. 

    my ( $file,     # Sequence file name
         $args,     # Hash of arguments
        ) = @_;

    # Returns a hash.

    my ( $wordlen, $seq_num, $oli_dim, $oli_seen, $run_begs, $fh, $seqs,
         $run_lens, $seq_ndcs, $run_beg, $count, $oli, $tmp_begs, $seq, 
         $run_end, $oli_sums, $sum, @seq_ids, $oli_zero, $max_len, $reader,
         $read_args, $l_size );

    $read_args = bless {
        "wordlen" => $args->wordlen,  # Oligo length
        "degap" => $args->degap,      # Remove gaps or not
        "minlen" => $args->minlen,    # Minimum sequence length
        "filter" => undef,            # Annotation string filter expression
        "format" => $args->format,    # Whatever Seq::IO supports
        "readbuf" => $args->seqbuf,   # Seqs to read at a time
        };

    $max_len = $args->dbmaxlen // $DB_max_seqlen;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET DIMENSIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read through the file and count oligos for each sequence. 

    $fh = &Common::File::get_read_handle( $file );
    
    # For each oligo, find how many sequences have it. This the same as the 
    # lengths of each sequence id run,    
        
    $wordlen = $args->wordlen;
    $oli_dim = 4 ** $wordlen;           # DNA/RNA only
    
    $run_lens = &Common::Util_C::new_array( $oli_dim, "uint" );

    $oli_seen = "\0" x $oli_dim;
    $oli_zero = &Common::Util_C::new_array( $max_len, "uint" );

    if ( $args->wconly )
    {
        while ( $seqs = &Seq::IO::read_seqs_filter( $fh, $read_args ) )
        {
            foreach $seq ( @{ $seqs } )
            {
                $sum = &Seq::Oligos::count_olis_wc(
                    $seq->{"seq"}, length $seq->{"seq"},
                    ${ $run_lens }, $wordlen, $oli_seen, ${ $oli_zero } );
            }
        }
    }
    else
    {
        while ( $seqs = &Seq::IO::read_seqs_filter( $fh, $read_args ) )
        {
            foreach $seq ( @{ $seqs } )
            {
                $sum = &Seq::Oligos::count_olis(
                    $seq->{"seq"}, length $seq->{"seq"},
                    ${ $run_lens }, $wordlen, $oli_seen, ${ $oli_zero } );
            }
        }
    }

    &Common::File::close_handle( $fh );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE MAP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $fh = &Common::File::get_read_handle( $file );
    
    # Create run_begs: for each oligo the positions in $seq_ndcs below where 
    # run starts. This needs to be as large as the machine allows, and there 
    # must be the same number of bytes used in perl and C. So ask C how many
    # bytes a long is, and then allocate accordingly,

    $l_size = &Common::Util_C::size_of_long();
    
    if ( $l_size == 4 ) {
        $run_begs = &Common::Util_C::new_array( $oli_dim, "uint" );
    } elsif ( $l_size == 8 ) {
        $run_begs = &Common::Util_C::new_array( $oli_dim, "uquad" );
    } else {
        &error( qq (Unsupported long-int byte size -> "$l_size") );
    }
    
    $run_end = &Seq::Oligos::init_run_offs( ${ $run_lens }, ${ $run_begs }, $oli_dim );

    # Fill run_ids with sequence ids. The $seq_ndcs array is populated with 
    # the sequence numbers while offsets in $tmp_begs are moved forward,

    $seq_ndcs = &Common::Util_C::new_array( $run_end, "uint" );

    $tmp_begs = ${ $run_begs };
    $seq_num = 0;
    
    $oli_seen = "\0" x $oli_dim;
    $oli_zero = &Common::Util_C::new_array( $max_len, "uint" );

    @seq_ids = ();

    if ( $args->wconly )
    {
        while ( $seqs = &Seq::IO::read_seqs_filter( $fh, $read_args ) )
        {
            foreach $seq ( @{ $seqs } )
            {
                &Seq::Oligos::create_ndcs_wc(
                     $seq->{"seq"}, length $seq->{"seq"},
                     $seq_num, ${ $seq_ndcs }, $tmp_begs,
                     $wordlen, $oli_seen, ${ $oli_zero } );
                
                $seq_num += 1;
            }

            push @seq_ids, map { $_->{"id"} } @{ $seqs };
        }
    }
    else
    {
        while ( $seqs = &Seq::IO::read_seqs_filter( $fh, $read_args ) )
        {
            foreach $seq ( @{ $seqs } )
            {
                &Seq::Oligos::create_ndcs(
                     $seq->{"seq"}, length $seq->{"seq"},
                     $seq_num, ${ $seq_ndcs }, $tmp_begs,
                     $wordlen, $oli_seen, ${ $oli_zero } );
                
                $seq_num += 1;
            }

            push @seq_ids, map { $_->{"id"} } @{ $seqs };
        }
    }

    &Common::File::close_handle( $fh );

    return {
        "ndcs" => $seq_ndcs,
        "begs" => $run_begs,
        "lens" => $run_lens,
        "sids" => \@seq_ids,
        "stot" => $seq_num,
        "wlen" => $wordlen,
    };
}

sub create_debug_hist
{
    # Niels Larsen, August 2012. 

    # Makes a text histogram with horizontal bars for left- and right-fragment 
    # dissimilarities. For debug mostly. Prints in void context, otherwise 
    # returns a list.

    my ( $args,
        ) = @_;

    # Returns list or nothing.

    my ( $ltot, $rtot, @hist, $i, $line, $step, $word, $incr,
         $lid_max, $rid_max, $seq, $stat, %annot, $scale, $wid,
         $beg_ndx, $beg_txt, $join_ndx, $join_txt, $end_ndx,
         $end_txt, $txt );

    $ltot = $args->left_tot;
    $rtot = $args->rigt_tot;

    $step = $args->step_len;
    $word = $args->word_len;
    $seq = $args->q_seq;
    $stat = $args->stat;

    $incr = int ( $word / $step );

    %annot = (
        $stat->{"edge_beg_ndx"} => "  <-- valley begin",
        $stat->{"join_ndx"} => "  <-- join pos",
        $stat->{"edge_end_ndx"} => "  <-- valley end",
        );

    push @hist, $seq->{"id"};
    push @hist, ( "-" x length $seq->{"id"} ), "";

    push @hist, " Word length: $word";
    push @hist, " Step length: $step", "";
    push @hist, " Break point: $stat->{'join_pos'}"; 
    push @hist, "     Left ID: ". $stat->{"left_ref"};
    push @hist, "    Right ID: ". $stat->{"rigt_ref"};
    push @hist, "   Left skew: ". $stat->{"left_off"};
    push @hist, "  Right skew: ". $stat->{"rigt_off"};

    if ( $seq->{"info"} and $seq->{"info"} =~ /seq_count=(\d+)/ ) {
        push @hist, " Query reads: ". $1;
    }

    push @hist, "       Score: $stat->{'score'}", "";

    $wid = length sprintf "%s", $step * scalar @{ $ltot };
    
    push @hist, ( sprintf "%$wid"."s", "  Pos" )."  Minimum mismatch at hypothetical join";
    push @hist, ( sprintf "%$wid"."s", "-----" )."  -------------------------------------", "";

    for ( $i = 0; $i <= $#{ $ltot }; $i++ )
    {
        $line = "  ". ( sprintf "%$wid"."s", $i * $step );
        # $line .= "  ". "l" x ( 1.5 * $ltot->[$i] / $incr );
        # $line .= "R" x ( 1.5 * $rtot->[$i] / $incr );
        $line .= "  ". "l" x $ltot->[$i];
        $line .= "R" x $rtot->[$i];

        if ( $txt = $annot{ $i } ) {
            $line .= $txt;
        }
        
        push @hist, $line;
    }

    push @hist, "";

    if ( defined wantarray )
    {
        return wantarray ? @hist : \@hist;
    }
    else {
        print "\n";
        map { print "$_\n" } @hist;
    }

    return;
}

sub create_query_map
{
    # Niels Larsen, August 2012.

    # Digests sequences into an oligo map. The map is a hash of three packed
    # strings that are used as arrays as C-routines,
    #
    # olis         Numeric oligos
    # begs         Offsets into olis for each sequence
    # sums         The number of oligos for each sequence
    #
    # Input is a sequence list and an arguments hash that must have "wordlen"
    # and "steplen" keys set. The sequences may not have gaps but can have a
    # mixture of upper/lower case and T/U are treated the same too. Returns
    # a hash with the three string references.

    my ( $seqs,       # Sequence list
         $args,       # Arguments hash
        ) = @_;

    # Returns hash.

    my ( $seq, $wordlen, $olinum, $olis, $ondx, $begs, $sums, $map,
         $steplen, $olisum, $ondx_new, $l_size, $l_pack, @begs, @sums );

    # Allocate string to hold the oligos. For a given sequence the number of
    # possible oligos is the number of possible steps through it,

    $wordlen = $args->{"wordlen"};
    $steplen = $args->{"steplen"};

    $olinum = &List::Util::sum( map
        {
            ( ( ( length $_->{"seq"} ) - $wordlen ) / $steplen ) + 1
        } @{ $seqs } );

    $olis = &Common::Util_C::new_array( $olinum, "uint" );

    # Oligofy, $olis is being written to by the C-routine,

    $ondx = 0;

    @begs = ();
    @sums = ();

    foreach $seq ( @{ $seqs } )
    {
        $ondx_new = &Seq::Oligos::create_olis(
            $seq->{"seq"}, length $seq->{"seq"}, $wordlen, $steplen, ${ $olis }, $ondx );

        push @begs, $ondx;
        push @sums, $ondx_new - $ondx;

        $ondx = $ondx_new;
    }

    $l_pack = &Seq::Chimera::set_pack_long();

    $begs = pack $l_pack ."*", @begs;
    $sums = pack "V*", @sums;

    $map->{"olis"} = $olis;
    $map->{"begs"} = \$begs;
    $map->{"sums"} = \$sums;

    return $map;
}

sub debug_db_map
{
    # Niels Larsen, March 2012. 

    # Prints the sequence indices map in readable form for debugging.
    # Use only with small datasets. 

    my ( $map,
        ) = @_;

    # Returns nothing.

    my ( $oli, $id, @ndcs, @begs, @lens, @sums, @tmp, $ndcs, $l_pack );

    print "\n";
    print "\$Config{'u16size'} = $Config{'u16size'}\n";
    print "\$Config{'u32size'} = $Config{'u32size'}\n";
    print "\$Config{'u64size'} = $Config{'u64size'}\n";
    print "Bytes for int in C: ". &Common::Util_C::size_of_int() ."\n";
    print "Bytes for long in C: ". &Common::Util_C::size_of_long() ."\n";

    print "\nOlinum\tSeq total\tSeq list\n";    

    $l_pack = &Seq::Chimera::set_pack_long();

    @begs = unpack $l_pack ."*", ${ $map->{"begs"} };
    @ndcs = unpack "V*", ${ $map->{"ndcs"} };
    @lens = unpack "V*", ${ $map->{"lens"} };

    for ( $oli = 0; $oli < 4 ** $map->{"wlen"}; $oli += 1 )
    {
        if ( $lens[$oli] > 0 )
        {
            @tmp = @ndcs[ $begs[$oli] ... $begs[$oli] + $lens[$oli] - 1 ];
            $ndcs = scalar @tmp;
            
            print "$oli\t$ndcs\t". (join ",", @tmp) ."\n";
        }
    }

    print "\n";

    return 1;
}

sub debug_query_map
{
    # Niels Larsen, March 2012. 

    # Prints the query oligo map in readable form for debugging. Use only 
    # with small inputs. 

    my ( $map,
        ) = @_;

    # Returns nothing.

    my ( $i, $sids, @olis, @begs, @sums, @tmp, $olis, $l_pack );

    print "\n";
    print "\$Config{'u16size'} = $Config{'u16size'}\n";
    print "\$Config{'u32size'} = $Config{'u32size'}\n";
    print "\$Config{'u64size'} = $Config{'u64size'}\n";
    print "Bytes for int in C: ". &Common::Util_C::size_of_int() ."\n";
    print "Bytes for long in C: ". &Common::Util_C::size_of_long() ."\n";

    print "\nSeq #\tOligo total\tUnique olinum\n";

    $l_pack = &Seq::Chimera::set_pack_long();

    @begs = unpack $l_pack ."*", ${ $map->{"begs"} };
    @sums = unpack "V*", ${ $map->{"sums"} };
    @olis = unpack "V*", ${ $map->{"olis"} };

    for ( $i = 0; $i < scalar @begs; $i += 1 )
    {
        @tmp = @olis[ $begs[$i] ... $begs[$i] + $sums[$i] - 1 ];
        $olis = scalar @tmp;
        
        print "$i\t$olis\t". (join ",", @tmp) ."\n";
    }

    print "\n";
    
    return 1;
}

sub init_buffers
{
    # Niels Larsen, October 2012. 

    # Creates a set of strings that are used as buffers by the C-routines.
    # A hash of string references is returned.

    my ( $max_len,     # Query max sequence length
         $db_stot,     # Number of reference sequences
        ) = @_;

    # Returns a hash.

    my ( $bufs );

    $bufs->{"left_ids"} = &Common::Util_C::new_array( $max_len, "uint" );
    $bufs->{"left_tot"} = &Common::Util_C::new_array( $max_len, "uint" );
    $bufs->{"left_max"} = &Common::Util_C::new_array( $max_len, "uint" );
    
    $bufs->{"rigt_ids"} = &Common::Util_C::new_array( $max_len, "uint" );
    $bufs->{"rigt_tot"} = &Common::Util_C::new_array( $max_len, "uint" );
    $bufs->{"rigt_max"} = &Common::Util_C::new_array( $max_len, "uint" );
    
    $bufs->{"min_ndcs"} = &Common::Util_C::new_array( $max_len, "uint" );
    $bufs->{"min_sums"} = &Common::Util_C::new_array( $max_len, "uint" );

    $bufs->{"db_hits"} = &Common::Util_C::new_array( $db_stot, "uint" );

    $bufs->{"int_stats"} = &Common::Util_C::new_array( 13, "uint" );
    $bufs->{"float_stats"} = &Common::Util_C::new_array( 4, "float" );
    
    return $bufs;
}

sub init_stats
{
    # Niels Larsen, October 2012. 

    # Initializes the stats hash with all keys/values that do not depend on 
    # input sequence files. 

    my ( $conf,   # Config object
        ) = @_;

    my ( $stats );

    $stats->{"name"} = "sequence-chimera-filter";
    $stats->{"title"} = "Chimera sequence filtering";

    $stats->{"dbfile"} = { "title" => "Reference dataset", "value" => $conf->dbfile };

    $stats->{"params"} = [
        {
            "title" => "Oligo word length",
            "value" => $conf->wordlen,
        },{
            "title" => "Oligo step length",
            "value" => $conf->steplen,
        },{
            "title" => "Minimum chimera score",
            "value" => $conf->minsco,
        },{
            "title" => "Minimum fragment length",
            "value" => $conf->minfrag,
        },{
            "title" => "Remove sequence gaps",
            "value" => $conf->degap ? "yes" : "no",
        },{
            "title" => "Sequence read buffer",
            "value" => $conf->seqbuf ? "yes" : "no",
        },{
            "title" => "Remove reference gaps",
            "value" => $conf->dbdegap ? "yes" : "no",
        },{
            "title" => "Reference read buffer",
            "value" => $conf->dbseqbuf ? "yes" : "no",
        },{
            "title" => "CPU cores used",
            "value" => $conf->cores,
        }];

    return $stats;
}

sub is_db_map_cached
{
    # Niels Larsen, August 2012. 

    # Returns 1 if there is an up to date cache version of the given reference
    # file, otherwise nothing.

    my ( $file,
         $wlen,
        ) = @_;

    # Returns 1 or nothing.
    
    my ( $map_file, $fh, $wlen_map, $buffer );

    $map_file = $file . $Suffixes{"cache"};

    if ( -r $map_file and 
         &Common::File::is_newer_than( $map_file, $file ) )
    {
        $fh = &Common::File::get_read_handle( $map_file );
        read $fh, $buffer, 20;
        &Common::File::close_handle( $fh );

        $wlen_map = $buffer * 1;

        return 1 if $wlen == $wlen_map;
    }

    return;
}

sub io_files
{
    # Niels Larsen, October 2012. 

    # Creates input handle and output file names, and sets read and write 
    # routine names. Returns a hash with these keys:
    #
    # reader
    # writer
    # ifh
    # chim
    # nochim
    # table
    # chimd
    # nochimd

    my ( $ifile,           # Input file path
         $outdir,
         $clobber,         # Delete existing output or not - OPTIONAL, default 0
         $debug,           # Write debug output or not - OPTIONAL, default 0
        ) = @_;

    # Returns a hash.

    my ( $io, $ofile, $suffix, $format, $dir, $name );
    
    $clobber //= 0;
    $debug //= 0;

    # Input,

    $format = &Seq::IO::detect_format( $ifile );

    $io->{"format"} = $format;
    $io->{"ifile"} = $ifile;

    $name = &File::Basename::basename( $ifile );

    if ( $name =~ /^([^\.]+)\./ or $name =~ /\.([^\.]+)\./ ) {
        $name = $1;
    } else {
        &error( qq (Wrong looking file -> "$ifile") );
    }
    
    $dir = &File::Basename::basename( $ifile );
    $dir = $outdir if defined $outdir;
    
    # Output,

    $io->{"writer"} = &Seq::IO::get_write_routine( $format );

    foreach $suffix ( qw ( chim nochim table ) )
    {
        $ofile = "$dir/$name". $Suffixes{ $suffix };

        if ( $clobber ) {
            &Common::File::delete_file_if_exists( $ofile );
        }

        $io->{ $suffix } = $ofile;
    }

    if ( $debug )
    {
        foreach $suffix ( qw ( chimd nochimd ) )
        {
            $ofile = "$dir/$name". $Suffixes{ $suffix };

            &Common::File::delete_file_if_exists( $ofile );
            $io->{ $suffix } = $ofile;
        }
    }

    return $io;
}
    
sub read_db_map
{
    # Niels Larsen, August 2012.

    # Reads an oligo map written with write_db_map in this module. This
    # works as a cache and save a few seconds or minutes if the file is big.

    my ( $file,
        ) = @_;

    # Returns a hash.

    my ( $map_file, $ndcs_len, $begs_len, $lens_len, $sums_len, $fh, $buffer,
         $map, $seq_num, $word_len );

    $map_file = $file . $Suffixes{"cache"};

    $fh = &Common::File::get_read_handle( $map_file );

    read $fh, $buffer, 100;

    $word_len = ( substr $buffer, 0, 20 ) * 1;
    $ndcs_len = ( substr $buffer, 20, 20 ) * 1;
    $begs_len = ( substr $buffer, 40, 20 ) * 1;
    $lens_len = ( substr $buffer, 60, 20 ) * 1;
    $seq_num = ( substr $buffer, 80, 20 ) * 1;

    read $fh, ${ $map->{"ndcs"} }, $ndcs_len;
    read $fh, ${ $map->{"begs"} }, $begs_len;
    read $fh, ${ $map->{"lens"} }, $lens_len;

    read $fh, $map->{"sids"}, $Max_int;
    $map->{"sids"} = Data::MessagePack->unpack( $map->{"sids"} );

    $map->{"wlen"} = $word_len;
    $map->{"stot"} = $seq_num;

    &Common::File::close_handle( $fh );

    return $map;
}

sub set_pack_long
{
    # Niels Larsen, February 2013.

    # Returns the pack size for long values according to C. It is used for
    # the float arrays being passed to C. V is used for size 4, Q for 8.

    # Returns a character. 

    my ( $size, $pack_ch );

    $size = &Common::Util_C::size_of_long();
    
    if ( $size == 4 ) {
        $pack_ch = "V";
    } elsif ( $size == 8 ) {
        $pack_ch = "Q";
    } else {
        &error( qq (Unsupported long-int byte size -> "$size") );
    }

    return $pack_ch;
}

sub sort_tables
{
    # Niels Larsen, October 2012. 

    # Sorts all existing output tables by score in descending order.
    # Returns the number of files sorted.

    my ( $conf,   # Config object
        ) = @_;
    
    # Returns integer.

    my ( $q_file, $tab_file, $tmp_file, $count );

    $count = 0;

    foreach $q_file ( @{ $conf->qseqs } )
    {
        $tab_file = $q_file . $Suffixes{"table"};
        
        if ( -s $tab_file )
        {
            $tmp_file = "$tab_file.tmp";
            
            &Common::OS::run3_command("sort -r -n -k 3  -f $tab_file > $tmp_file");
            
            &Common::File::delete_file( $tab_file );
            &Common::File::rename_file( $tmp_file, $tab_file );

            $count += 1;
        }
    }

    return $count;
}

sub write_db_map
{
    # Niels Larsen, August 2012. 

    # Writes a given oligo map to cache file, from which it can be reloaded
    # quickly. Returns nothing.

    my ( $file,     # Output file
         $map,      # Oligo map
        ) = @_;

    # Returns nothing.

    my ( $map_file, $ndcs_len, $begs_len, $lens_len, $sums_len, $seq_num,
         $fh, $word_len );

    $map_file = $file . $Suffixes{"cache"};

    &Common::File::delete_file_if_exists( $map_file );

    $fh = &Common::File::get_write_handle( $map_file );

    $word_len = sprintf "%20s", $map->{"wlen"};
    $ndcs_len = sprintf "%20s", length ${ $map->{"ndcs"} };
    $begs_len = sprintf "%20s", length ${ $map->{"begs"} };
    $lens_len = sprintf "%20s", length ${ $map->{"lens"} };
    $seq_num = sprintf "%20s", $map->{"stot"};

    $fh->print( $word_len . $ndcs_len . $begs_len . $lens_len . $seq_num );

    $fh->print( ${ $map->{"ndcs"} } );
    $fh->print( ${ $map->{"begs"} } );
    $fh->print( ${ $map->{"lens"} } );

    $fh->print( Data::MessagePack->pack( $map->{"sids"} ) );

    &Common::File::close_handle( $fh );

    return;
}

sub write_seqs
{
    # Niels Larsen, August 2012. 

    # Streams a list of sequences into two files, one with chimera scores below 
    # a minimum, and the other above. Chimera scores and break points are added
    # in the comment fields in the chimera file. The info field in the sequence
    # list is changed in this routine. Returns chimeric and non-chimeric counts
    # as a two element list.

    my ( $args,
        ) = @_;

    # Returns two-element list.

    my ( $i, $j, $seqs, $seq, $stats, $stat, @c_seqs, @nc_seqs, $minsco,
         $writer, $ofh );

    $seqs = $args->seqs;
    $stats = $args->stats;
    $minsco = $args->minsco;
    
    if ( ( $i = scalar @{ $seqs } ) != ( $j = scalar @{ $stats } ) )
    {
        &error( qq ($i sequences but $j corresponding counts.\n)
               .qq (This is a programming error) );
    }

    # Create two lists of sequence references, add score and breakpoints to 
    # chimera candidates,

    for ( $i = 0; $i <= $#{ $seqs }; $i++ )
    {
        $seq = $seqs->[$i];
        $stat = $stats->[$i];

        if ( $stat->{"score"} >= $minsco )
        {
            if ( $seq->{"info"} ) {
                $seq->{"info"} .= ";";
            } else {
                $seq->{"info"} = "";
            }
            
            $seq->{"info"} .= " chi_score=$stat->{'score'}; chi_break=$stat->{'join_pos'}";
            
            push @c_seqs, $seq;
        }
        else
        {
            $seq->{"info"} .= " chi_score=$stat->{'score'}";

            push @nc_seqs, $seq;
        }
    }

    # Write to two files,

    $writer = $args->writer;

    if ( @c_seqs )
    {
        no strict "refs";

        $ofh = &Common::File::get_append_handle( $args->chim, "exclusive" => 1 );

        $writer->( $ofh, \@c_seqs );
        $ofh->flush;

        &Common::File::close_handle( $ofh );
    }
    
    if ( @nc_seqs )
    {
        no strict "refs";

        $ofh = &Common::File::get_append_handle( $args->nochim, "exclusive" => 1 );

        $writer->( $ofh, \@nc_seqs );
        $ofh->flush;

        &Common::File::close_handle( $ofh );
    }
    
    return ( scalar @c_seqs, scalar @nc_seqs );
}

sub write_stats_all
{
    # Niels Larsen, October 2012. 

    # Writes one statistics file per input file. Nothing is returned.

    my ( $stats,
         $conf,
        ) = @_;

    # Returns nothing. 

    my ( $ifile, $opath, $stat_file, %counts, $dir, $name, $outdir );

    $outdir = $conf->outdir;

    # Loop through all input files and write stats files,
    
    foreach $ifile ( @{ $conf->qseqs } )
    {
        $stats->{"qfile"} = { "title" => "Input file", "value" => $ifile };

        $dir = &File::Basename::dirname( $ifile );
        $name = &File::Basename::basename( $ifile );

        if ( $name =~ /^([^\.]+)\./ or $name =~ /\.([^\.]+)\./ ) {
            $name = $1;
        } else {
            &error( qq (Wrong looking file -> "$ifile") );
        }
        
        $dir = $outdir if $outdir;
        $opath = "$dir/$name";
        
        $stats->{"chim"} = { "title" => "Chimeric sequences", "value" => $opath . $Suffixes{"chim"} };
        $stats->{"nochim"} = { "title" => "Non-chimeric sequences", "value" => $opath . $Suffixes{"nochim"} };
        $stats->{"chimtab"} = { "title" => "Chimera-score table", "value" => $opath . $Suffixes{"table"} };
        
        if ( $conf->debug )
        {
            $stats->{"chim_d"} = { "title" => "Chimeric debug output", "value" => $opath . $Suffixes{"chimd"} };
            $stats->{"nochim_d"} = { "title" => "Non-chimeric debug output", "value" => $opath . $Suffixes{"nochimd"} };
        }
        
        $stats->{"in_counts"} = &Seq::Stats::count_seq_file( $ifile );
        $stats->{"chi_counts"} = &Seq::Stats::count_seq_file( $opath . $Suffixes{"chim"} );
        $stats->{"nochi_counts"} = &Seq::Stats::count_seq_file( $opath . $Suffixes{"nochim"} );

        $stat_file = $opath . $Suffixes{"stats"};
        &Common::File::delete_file_if_exists( $stat_file );

        &Seq::Chimera::write_stats_file( $opath . $Suffixes{"stats"}, bless $stats );

        $counts{ $name }->{"chi_seqs"} += $stats->{"chi_counts"}->{"seq_count"};
        $counts{ $name }->{"chi_reads"} += $stats->{"chi_counts"}->{"seq_count_orig"};
        $counts{ $name }->{"nochi_seqs"} += $stats->{"nochi_counts"}->{"seq_count"};
        $counts{ $name }->{"nochi_reads"} += $stats->{"nochi_counts"}->{"seq_count_orig"};
    }
    
    return wantarray ? %counts : \%counts;
}

sub write_stats_file
{
    # Niels Larsen, September 2012. 

    # Creates a Config::General formatted string with tags that are understood 
    # by Recipe::Stats::html_body. Writes the string to the given file in void
    # context, otherwise returns it. 

    my ( $sfile,     # Stats file
         $stats,     # Stats content
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $title, $value, $time, $iseq, $iread, $oseq, $oread, 
         $seqdif, $readif, $seqpct, $readpct, $istr, $pstr, $file,
         $elem, $key, $secs, $date );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $title = $stats->qfile->{"title"};
    $value = $stats->qfile->{"value"};

    $istr = qq (      file = $title\t$value\n);

    $title = $stats->dbfile->{"title"};
    $value = &File::Basename::basename( $stats->dbfile->{"value"} );
    
    $istr .= qq (      hrow = $title\t$value\n);

    chomp $istr;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $pstr = "";

    foreach $elem ( @{ $stats->{"params"} } ) {
        $pstr .= qq (         item = $elem->{"title"}: $elem->{"value"}\n);
    }

    chomp $pstr;

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
$istr
      <menu>
         title = Parameters
$pstr
      </menu>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $key ( qw ( chim nochim chimtab chist chim_d nochim_d ) )
    {
        next if not exists $stats->{ $key };

        $title = $stats->{ $key }->{"title"};
        $value = &File::Basename::basename( $stats->{ $key }->{"value"} );

        $text .= qq (      file = $title\t$value\n);
    }

    $time = &Time::Duration::duration( $stats->{"seconds"} );
    $secs = $stats->{"seconds"};
    $date = $stats->{"finished"};

    $text .= qq (      secs = $secs
      date = $date
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Inputs,

    $iseq = $stats->in_counts->{"seq_count"};
    $iread = $stats->in_counts->{"seq_count_orig"};

    $text .= qq (
   <table>
      title = Chimera sequence and reads statistics
      colh = Type\tSeqs\t&Delta; %\tReads\t&Delta; %
      trow = Input counts\t$iseq\t\t$iread\t
);

    # Chimeras,

    $oseq = $stats->chi_counts->{"seq_count"};
    $oread = $stats->chi_counts->{"seq_count_orig"};

    if ( $iseq == 0 ) {
        $seqpct = sprintf "%.1f", 0;
    } else {
        $seqpct = sprintf "%.1f", 100 * $oseq / $iseq;
    }
    
    if ( $iread == 0 ) {
        $readpct = sprintf "%.1f", 0;
    } else {
        $readpct = sprintf "%.1f", 100 * $oread / $iread;
    }
    
    $text .= qq (      trow = Chimeras\t$oseq\t$seqpct\t$oread\t$readpct\n);
    
    # Non-chimeras,

    $oseq = $stats->nochi_counts->{"seq_count"};
    $oread = $stats->nochi_counts->{"seq_count_orig"};

    if ( $iseq == 0 ) {
        $seqpct = sprintf "%.1f", 0;
    } else {
        $seqpct = sprintf "%.1f", 100 * $oseq / $iseq;
    }
    
    if ( $iread == 0 ) {
        $readpct = sprintf "%.1f", 0;
    } else {
        $readpct = sprintf "%.1f", 100 * $oread / $iread;
    }
    
    $text .= qq (      trow = Non-chimeras\t$oseq\t$seqpct\t$oread\t$readpct\n);
    $text .= qq (   </table>\n\n);
    
    $text .= qq (</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
};

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
    
    my ( $stats, $text, $file, $rows, $secs, @row, @table, $in_seq, $time,
         $in_res, $sdif, $rdif, $chi_seq, $chi_res, $seq_pct, $res_pct, $str,
         $row, $chi_file, $nochi_file, $db_file, $params, $items, $dir,
         $prefix, @dates, $date );

    # Create table array by reading all the given statistics files and getting
    # values from them,

    @table = ();

    foreach $file ( @{ $files } )
    {
        $stats = &Recipe::IO::read_stats( $file )->[0];

        $rows = $stats->{"headers"}->[0]->{"rows"};
        $chi_file = &File::Basename::basename( $rows->[3]->{"value"} );
        $nochi_file = &File::Basename::basename( $rows->[4]->{"value"} );

        $rows = $stats->{"tables"}->[0]->{"rows"};
        
        @row = split "\t", $rows->[0]->{"value"};
        ( $in_seq, $in_res ) = @row[1,3];

        @row = split "\t", $rows->[1]->{"value"};
        ( $chi_seq, $chi_res ) = @row[1,3];

        $chi_seq =~ s/,//g;
        $chi_res =~ s/,//g;

        $prefix = &Common::Names::strip_suffix( $nochi_file );

        push @table, [ "file=$nochi_file",
                       $in_seq, $chi_seq, 100 * $chi_seq / $in_seq,
                       $in_res, $chi_res, 100 * $chi_res / $in_res,
                       qq (html=Files:$prefix.stats.html),
        ];
    }

    # Sort descending by input sequences, 

    @table = sort { $b->[1] <=> $a->[1] } @table;
    
    # Calculate totals,

    $in_seq = &List::Util::sum( map { $_->[1] } @table );
    $chi_seq = &List::Util::sum( map { $_->[2] } @table );
    $seq_pct = sprintf "%.1f", 100 * $chi_seq / $in_seq;

    $in_res = &List::Util::sum( map { $_->[4] } @table );
    $chi_res = &List::Util::sum( map { $_->[5] } @table );
    $res_pct = sprintf "%.1f", 100 * $chi_res / $in_res;
    
    $stats = bless &Recipe::IO::read_stats( $files->[0] )->[0];

    $time = &Recipe::Stats::head_type( $stats, "time" );
    $date = &Recipe::Stats::head_type( $stats, "date" );
    $secs = &Recipe::Stats::head_type( $stats, "secs" );

    $rows = $stats->{"headers"}->[0]->{"rows"};
    
    $db_file = $rows->[1]->{"value"};
    $params = $rows->[2];

    # Format table,

    $items = "";
    map { $items .= qq (           item = $_->{"value"}\n) } @{ $params->{"items"} };
    chomp $items;

    $text = qq (
<stats>
   title = $stats->{"title"}
   <header>
       <menu>
           title = $params->{"title"}
$items
       </menu>
       file = Reference datafile\t$db_file
       hrow = Total input counts\t$in_seq entries, $in_res reads
       hrow = Total chimera counts\t$chi_seq entries ($seq_pct%), $chi_res reads ($res_pct%)
       date = $date
       secs = $secs
       time = $time
   </header>  
   <table>
      title = Chimera sequence and reads statistics
      colh = Output files\tIn-seqs\tChimeras\t&Delta; %\tIn-reads\tChimeras\t&Delta; %\tFiles
);
    
    foreach $row ( @table )
    {
        $row->[1] //= 0;
        $row->[2] //= 0;
        $row->[3] = sprintf "%.1f", $row->[3];
        $row->[4] //= 0;
        $row->[5] //= 0;
        $row->[6] = sprintf "%.1f", $row->[6];

        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }

    $text .= qq (   </table>\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_table
{
    # Niels Larsen, August 2012. 

    # From a list of sequences + a parallel list of counts, writes a tab
    # separated table with these columns,
    # 
    # Query sequence id
    # Query sequence length
    # Chimera score
    # Chimera break point position
    # Left fragment oligo similarity pct
    # Right fragment oligo similarity pct
    # Best matching left fragment reference id
    # Best matching right fragment reference id
    # Taxonomy string for best left fragment match (todo)
    # Taxonomy string for best right fragment match (todo)
    
    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $seqs, $seq, $i, $j, $fh, $stats, $stat, $line );

    $seqs = $args->seqs;
    $stats = $args->stats;

    if ( ( $i = scalar @{ $seqs } ) != ( scalar @{ $stats } ) )
    {
        &error( qq (There are $i sequences but $j counts.\n)
               .qq (This is a programming error) );
    }

    $fh = &Common::File::get_append_handle( $args->table, "exclusive" => 1 );

    for ( $i = 0; $i <= $#{ $seqs }; $i++ )
    {
        $stat = $stats->[$i];

        $line = join "\t", (
            $stat->{"q_id"}, $stat->{"q_len"},
            $stat->{"score"}, $stat->{"join_pos"}, 
            ( sprintf "%.2f", $stat->{"left_sim"} ),
            ( sprintf "%.2f", $stat->{"rigt_sim"} ),
            $stat->{"left_ref"}, $stat->{"rigt_ref"} );

        $fh->print( $line ."\n" );
    }

    $fh->flush;

    &Common::File::close_handle( $fh );

    return;
}

1;

__DATA__

__C__

/*
  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
*/

/*
  Function to get the C value (a pointer usually) of a Perl scalar
*/

static void* get_ptr( SV* obj ) { return SvPVX( obj ); }

/*
  Oligo number encoding scheme. Only 128 elements are needed, but rare base 
  errors do occur, where characters > 128 sneak in. They should be caught 
  earlier, not here.
*/

# define JOIN_NDX         0
# define JOIN_POS         1
# define LEFT_ID          2
# define RIGT_ID          3
# define EDGE_BEG_NDX     4
# define EDGE_END_NDX     5
# define SCORE            6

# define LEFT_SIM         0
# define RIGT_SIM         1
# define LEFT_OFF         2
# define RIGT_OFF         3

/*
  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  All functions below use Perl strings as arrays, no mallocs. They do not use 
  the Perl stack, which is slow with Inline. No C-structures either, just 
  simple 1-D arrays. 

*/

void create_stat_C(
    unsigned int wordlen, unsigned int steplen, unsigned int listlen, unsigned int minfrag,
    SV* left_ids_sv, SV* left_tot_sv, SV* rigt_ids_sv, SV* rigt_tot_sv,
    SV* min_sums_sv, SV* min_ndcs_sv, SV* left_max_sv, SV* rigt_max_sv,
    SV* int_stats_sv, SV* float_stats_sv )
{
    /*
      Niels Larsen, October 2012. 
      
      Looks for a "valley" as described with '--help method' and returns counts
      in the int_stats and float_stats arrays. The '# define' statements above 
      define array indices that are referred to below. Perl parses these two 
      arrays (strings in perl) converts them into a hash. 

      NOTE: might have been a mistake to write this in C, as it is really not 
      the bottleneck with big datasets. 
    */

    unsigned int* left_ids = get_ptr( left_ids_sv );
    unsigned int* left_tot = get_ptr( left_tot_sv );
    unsigned int* rigt_ids = get_ptr( rigt_ids_sv );
    unsigned int* rigt_tot = get_ptr( rigt_tot_sv );

    unsigned int* min_ndcs = get_ptr( min_ndcs_sv );
    unsigned int* min_sums = get_ptr( min_sums_sv );
    unsigned int* left_max = get_ptr( left_max_sv );
    unsigned int* rigt_max = get_ptr( rigt_max_sv );

    unsigned int* int_stats = get_ptr( int_stats_sv );
    float* float_stats = get_ptr( float_stats_sv );

    unsigned int min_sum, sum, max_sum, ndx, join_ndx, gain_ndx;
    unsigned int beg_ndx, end_ndx, diff_val;
    int i;

    float expected, height, bottom, gain;

    /*
      >>>>>>>>>>>>>>>>>>>>>>>>>> FIND VALLEY BOTTOM <<<<<<<<<<<<<<<<<<<<<<<<<<<

      Look for "valleys" where cumulative fragment dissimilarities for both
      fragments are at minimum. If that minimum spans several positions then 
      take the middle one,

    */

    min_sum = left_tot[0] + rigt_tot[0];

    min_ndcs[0] = 0;
    min_sums[0] = min_sum;

    ndx = 0;

    for ( i = 1; i < listlen; i++ )
    {
        sum = left_tot[i] + rigt_tot[i];

        if ( sum < min_sum )
        {
            min_sum = sum;
            
            min_ndcs[0] = i;
            min_sums[0] = min_sum;

            ndx = 0;
        }
        else if ( sum == min_sum )
        {
            ndx += 1;

            min_ndcs[ndx] = i;
            min_sums[ndx] = min_sum;
        }
    }

    if ( ndx > 0 ) {
        join_ndx = (unsigned int)( ( min_ndcs[ndx] + min_ndcs[0] ) / 2 );
    } else {
        join_ndx = min_ndcs[0];
    }

    int_stats[JOIN_NDX] = join_ndx;
    int_stats[JOIN_POS] = join_ndx * steplen + (unsigned int)( wordlen / 2 );

    int_stats[LEFT_ID] = left_ids[ join_ndx ];
    int_stats[RIGT_ID] = rigt_ids[ join_ndx ];

    /*
      >>>>>>>>>>>>>>>>>>>>>>>>>> VALLEY BEGIN EDGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

      Find the index of the starting edge of the valley. Look from the bottom 
      towards the beginning and find the maximum value,
    */

    beg_ndx = join_ndx;
    max_sum = rigt_tot[ join_ndx ];

    for ( i = join_ndx - 1; i >= 0; i-- )
    {
        sum = left_tot[i] + rigt_tot[i];

        if ( sum > max_sum )
        {
            beg_ndx = i;
            max_sum = sum;
        }
    }

    int_stats[EDGE_BEG_NDX] = beg_ndx;

    /*
      >>>>>>>>>>>>>>>>>>>>>>>>>>>> VALLEY END EDGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

      Find the index of the ending edge of the valley. Look from the bottom 
      towards the end and find the maximum value,
    */

    end_ndx = join_ndx;
    max_sum = left_tot[ join_ndx ];

    for ( i = join_ndx + 1; i < listlen; i++ )
    {
        sum = left_tot[i] + rigt_tot[i];

        if ( sum > max_sum )
        {
            end_ndx = i;
            max_sum = sum;
        }
    }

    int_stats[EDGE_END_NDX] = end_ndx;

    /*
      >>>>>>>>>>>>>>>>>>>>>>> FRAGMENT SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<<<<<

      Calculate approximate length percentages for each fragment
    */

    float_stats[LEFT_SIM] = 100 - 100 * (float)left_tot[ join_ndx-1 ] / ( join_ndx + 1 );
    float_stats[RIGT_SIM] = 100 - 100 * (float)rigt_tot[ join_ndx+1 ] / ( listlen - join_ndx + 1 );

    /* 
       >>>>>>>>>>>>>>>>>>>>>>>>> CHIMERA SCORING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    */

    /*
      LEFT_OFF reflects how much the cumulative dissimilarity has grown beyond
      the expected when seen from the break point towards the sequence start. 
    */

    diff_val = rigt_tot[ beg_ndx ] - rigt_tot[ end_ndx ];
    gain_ndx = join_ndx + (unsigned int)( ( end_ndx - join_ndx ) / 4 );

    expected = rigt_tot[ end_ndx ] + diff_val * ( end_ndx - join_ndx ) / ( end_ndx - beg_ndx + 1 );

    if ( rigt_tot[ gain_ndx ] == 0 ) {
        float_stats[LEFT_OFF] = expected;
    } else {
        float_stats[LEFT_OFF] = expected / rigt_tot[ gain_ndx ];
    }

    /*
      RIGT_OFF. Same as LEFT_OFF but for the downstream fragment.
    */

    diff_val = left_tot[ end_ndx ] - left_tot[ beg_ndx ];
    gain_ndx = join_ndx - (unsigned int)( ( join_ndx - beg_ndx ) / 4 );

    expected = left_tot[ beg_ndx ] + diff_val * ( join_ndx - beg_ndx ) / ( end_ndx - beg_ndx + 1 );

    if ( left_tot[ gain_ndx ] == 0 ) {
        float_stats[RIGT_OFF] = expected;
    } else {
        float_stats[RIGT_OFF] = expected / left_tot[ gain_ndx ];
    }

    /*
      SCORE

      Simply multiply the biases for each fragment. Multiplying by step length
      makes the score step length neutral. Dividing by 2 is arbitrary and may 
      go away. Set score to zero if the smallest fragment is shorter than 
      required.
    */

    int_stats[SCORE] = (unsigned int)( steplen * float_stats[LEFT_OFF] * float_stats[RIGT_OFF] / 2 );

    if ( ( minfrag > ( join_ndx + 1 ) ) || 
         ( minfrag > ( listlen - join_ndx ) ) )
    {
        int_stats[SCORE] = 0;
    }

    return;
}

unsigned int measure_difs_left_C(
    SV* q_olis_sv, int q_beg, unsigned int q_sum,
    SV* db_ndcs_sv, SV* db_begs_sv, SV* db_lens_sv, unsigned int db_stot, SV* db_hits_sv,
    SV* max_ndx_sv, SV* max_tot_sv, unsigned int offset )
{
    /*
      Niels Larsen, August 2012. 
      
      Creates a vector of highest similarites and their db-ids, from left to 
      right. Input is an oligofied query sequence and a reference dataset map.
      Outputs are 1) an array of sums of oligos that match and 2) an array of
      reference ids. 

      Inputs, read-only
      -----------------

      q_olis: array of integer oligo ids for all query sequences.
      q_begs: array of starting positions in q_olis for each query sequence.
      q_sums: array of oligo counts for each query sequence. When one of those
              counts are added to the corresponding begin offset in q_olis, 
              then that points to the end in q_olis.

      db_ndcs: array of sequence indices for all oligos
      db_begs: array of offsets into db_ndcs for each oligo
      db_lens: array of sequence totals for each oligo

      Scratch buffer
      --------------

      db_hits: array of matching oligos for each reference sequence

      Outputs, write-only
      -------------------

      max_ndx: array of highest matching id for fragment
      max_tot: array of highest matching oligo count for fragment

      NOTE: this routine is done in the simplest way. Might instead use
      heap insert/delete and save maybe 50%. Example,
      http://www.indiastudychannel.com/resources/13040-C-Program-for-insertion-deletion-heap.aspx
      But it is not a clear bottleneck, so keep the simple way.
    */

    unsigned int* q_olis = get_ptr( q_olis_sv );
    
    unsigned int* db_ndcs = get_ptr( db_ndcs_sv );
    unsigned long* db_begs = get_ptr( db_begs_sv );
    unsigned int* db_lens = get_ptr( db_lens_sv );

    unsigned int* db_hits = get_ptr( db_hits_sv );
    unsigned int* max_ndx = get_ptr( max_ndx_sv );
    unsigned int* max_tot = get_ptr( max_tot_sv );

    int q_off, q_ndx, q_tot, i, beg_ndx, beg_tot;
    unsigned int q_oli;
    unsigned int db_ndx, db_len, hit_max_ndx, hit_max;
    unsigned long db_beg, db_off;
    unsigned int* hit;

    memset( db_hits, 0, sizeof(int) * db_stot );

    q_ndx = offset;
    q_tot = 1;

    hit_max = 0;
    hit_max_ndx = 0;

    for ( q_off = q_beg; q_off < q_beg + q_sum; q_off++ )
    {
        q_oli = q_olis[q_off];
        db_len = db_lens[q_oli];

        if ( db_len > 0 )
        {
            // db_beg = db_begs[q_oli];

            for ( db_off = db_begs[q_oli]; db_off < db_begs[q_oli] + db_len; db_off++ )
            {
                hit = &( db_hits[ db_ndcs[db_off] ] );

                *hit += 1; 

                if ( *hit > hit_max )
                {
                    hit_max = *hit;
                    hit_max_ndx = db_ndcs[db_off];
                }

                /*

                db_ndx = db_ndcs[db_off];
                db_hits[ db_ndx ]++;

                if ( db_hits[ db_ndx ] > hit_max )
                {
                    hit_max = db_hits[ db_ndx ];
                    hit_max_ndx = db_ndx;
                }
                */
            }
        }

        max_ndx[q_ndx] = hit_max_ndx;
        max_tot[q_ndx] = q_tot - hit_max;

        q_ndx++;
        q_tot++;
    }

    beg_ndx = max_ndx[offset];
    beg_tot = max_tot[offset];

    for ( i = 0; i < offset; i++ )
    {
        max_ndx[i] = beg_ndx;
        max_tot[i] = beg_tot;
    }

    return q_ndx;
}

unsigned int measure_difs_right_C(
    SV* q_olis_sv, int q_beg, unsigned int q_sum,
    SV* db_ndcs_sv, SV* db_begs_sv, SV* db_lens_sv, unsigned int db_stot, SV* db_hits_sv,
    SV* max_ndx_sv, SV* max_tot_sv, unsigned int offset )
{
    /*
      Niels Larsen, August 2012. 
      
      Creates a vector of highest similarites and their db-ids, from right to 
      left. Input is an oligofied query sequence and a reference dataset map.
      Outputs are 1) an array of sums of oligos that match and 2) an array of
      reference ids. See --help method.

      Inputs, read-only
      -----------------

      q_olis: array of integer oligo ids for all query sequences.
      q_begs: array of starting positions in q_olis for each query sequence.
      q_sums: array of oligo counts for each query sequence. When one of those
              counts are added to the corresponding begin offset in q_olis, 
              then that points to the end in q_olis.

      db_ndcs: array of sequence indices for all oligos
      db_begs: array of offsets into db_ndcs for each oligo
      db_lens: array of sequence totals for each oligo

      Scratch buffer
      --------------

      db_hits: array of matching oligos for each reference sequence

      Outputs, write-only
      -------------------

      max_ndx: array of highest matching id for fragment
      max_tot: array of highest matching oligo count for fragment

      NOTE: this routine is done in the simplest way. Might instead use
      heap insert/delete and save maybe 50%. Example,
      http://www.indiastudychannel.com/resources/13040-C-Program-for-insertion-deletion-heap.aspx
      But it is not a clear bottleneck, so keep the simple way.
    */

    unsigned int* q_olis = get_ptr( q_olis_sv );
    
    unsigned int* db_ndcs = get_ptr( db_ndcs_sv );
    unsigned long* db_begs = get_ptr( db_begs_sv );
    unsigned int* db_lens = get_ptr( db_lens_sv );

    unsigned int* db_hits = get_ptr( db_hits_sv );
    unsigned int* max_ndx = get_ptr( max_ndx_sv );
    unsigned int* max_tot = get_ptr( max_tot_sv );

    unsigned int q_oli, q_ndx, q_tot;
    int q_off, q_end, i, end_ndx, end_tot;

    unsigned long db_off, db_beg;
    unsigned int db_ndx, db_len, hit_max_ndx, hit_max;
    unsigned int* hit;

    memset( db_hits, 0, sizeof(int) * db_stot );

    hit_max = 0;
    hit_max_ndx = 0;

    q_end = q_beg + q_sum - 1;
    q_ndx = q_sum - 1;
    q_tot = 1;

    for ( q_off = q_end; q_off >= q_beg; q_off-- )
    {
        q_oli = q_olis[q_off];
        db_len = db_lens[q_oli];

        if ( db_len > 0 )
        {
            // db_beg = db_begs[q_oli];
            
            for ( db_off = db_begs[q_oli]; db_off < db_begs[q_oli] + db_len; db_off++ )
            {
                hit = &( db_hits[ db_ndcs[db_off] ] );

                *hit += 1; 

                if ( *hit > hit_max )
                {
                    hit_max = *hit;
                    hit_max_ndx = db_ndcs[db_off];
                }

                /*
                db_ndx = db_ndcs[db_off];
                db_hits[ db_ndx ]++;
                
                if ( db_hits[ db_ndx ] > hit_max )
                {
                    hit_max = db_hits[ db_ndx ];
                    hit_max_ndx = db_ndx;
                }
                */
            }
        }
        
        max_ndx[q_ndx] = hit_max_ndx;
        max_tot[q_ndx] = q_tot - hit_max;
        
        q_ndx--;
        q_tot++;
    }

    end_ndx = max_ndx[q_sum-1];
    end_tot = max_tot[q_sum-1];

    for ( i = q_sum; i < q_sum + offset; i++ )
    {
        max_ndx[i] = end_ndx;
        max_tot[i] = end_tot;
    }

    return q_sum + offset;
}

__END__

void ptr_test()
{
    int arr[] = { 1,2,4,8,16,32,64,128 };
    int *ptr;
    int i;
    
    i = 0;
    ptr = &arr[1];

    while ( i < 8 )
    {
        printf("value = %d\n", *( ptr++ ) );
        i++;
    }

    return;
}

#include <stdlib.h>
#include <string.h>

typedef unsigned short int uint16_t;
typedef unsigned int uint32_t;

#if __WORDSIZE == 32
typedef unsigned long long uint64_t;
#endif

/* see more in /usr/include/stdint.h */

    # >>>>>>>>>>>>>>>>>>>> INDEX REFERENCE IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<<<<

    # if ( not &Seq::Storage::is_indexed( $db_file ) )
    # {
    #     &echo("   Indexing reference set ... ");
    #     &Seq::Storage::create_indices({ "ifiles" => [ $db_file ], "silent" => 1 });        
    #     &echo_done("done\n");
    # }

    # if ( not &Taxonomy::Profile::is_indexed( $db_tax, $db_xtax ) )
    # {
    #     &echo("   Indexing taxonomy table ... ");
    #     &Common::Storage::index_table( $db_tax );
    #     &echo_done("done\n");
    # }
    
# my $Tax_table = "SSU_taxonomy.table";
    # $db_tax =  $conf->dbtax;
    # $db_xtax = "$db_tax.dbm";

    # $args{"dbfile"} = &Common::File::full_file_path( $args{"dbfile"} );

    # # Taxonomy,

    # $dir = &File::Basename::dirname( $args{"dbfile"} );
    
    # if ( -s "$dir/SSU_taxonomy.table" ) {
    #     $args{"dbtax"} = "$dir/$Tax_table";
    # } else {
    #     push @msgs, ["ERROR", qq (No $Tax_table in $dir) ];
    # }
