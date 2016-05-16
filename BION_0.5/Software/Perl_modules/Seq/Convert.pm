package Seq::Convert;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Sequence conversion related routines.
#
# convert_seqs
# convert_seqs_args
# convert_seqs_code
# divide_chunks_fasta
# divide_seqs_fasta
# rarefy
# rarefy_args
# write_rarefy_stats
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use Common::Config;
use Common::Messages;
use Common::Util;

use Registry::Paths;

use Seq::IO;
use Seq::List;
use Seq::Args;
use Seq::Stats;

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( %Formats, @Formats );

$Formats{"sff"}{"fastq"} = 1;
$Formats{"fastq"}{"fasta"} = 1;
$Formats{"fasta_wrapped"}{"fasta"} = 1;

@Formats = qw ( fasta fastq sff fasta_wrapped );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub convert_seqs
{
    # Niels Larsen, October 2009.
    
    # Converts from one sequence format to another. The read and write routines
    # from Seq::IO and so the supported formats are those for which there exists
    # &Seq::IO::read_seq_(inputformat) and Seq::IO::write_seq_(outputformat)
    # routines.

    my ( $args,             # Arguments hash
         $msgs,             # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns nothing.

    my ( $defs, $ifh, $ofh, $seq_count, $ifile, $code, $ofile, %seen,
         $iname, $oname, $conf, $clobber, $seqs, $seq, $replace, $iformat, 
         $oformat, $tmp_file, $io, $odir );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifiles" => [],
        "iformat" => undef,
        "oformat" => "fasta",
        "osuffix" => undef,
        "odir" => undef,
        "ofile" => undef,
        "readbuf" => 1000,
        "hdrinfo" => 0,
        "noinfo" => 0,
        "replace" => 0,
        "clobber" => 0,
        "comp" => 0,
        "numids" => 0,
        "degap" => 0,
        "dedup" => 0,
        "upper" => 0,
        "lower" => 0,
        "t2u" => 0,
        "u2t" => 0,
        "qualsub" => 0,
        "stats" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Convert::convert_seqs_args( $args );

    $Common::Messages::silent = $conf->silent;
    
    $clobber = $conf->clobber;
    $replace = $conf->replace;

    &echo_bold( qq (\nConverting:\n) );

    foreach $io ( @{ $conf->{"io"} } )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $ifile = $io->ifile;
        $ofile = $io->ofile;

        $iformat = $io->iformat;
        $oformat = $io->oformat;

        $odir = &File::Basename::dirname( $ofile );
        &Common::File::create_dir_if_not_exists( $odir );

        &Common::File::delete_file_if_exists( $ofile ) if $clobber;

        $iname = &File::Basename::basename( $ifile );

        if ( $iformat eq "sff" and $oformat eq "fastq" )
        {
            &echo("   Converting $iname ... ");
            &Common::OS::run3_command("sff2fastq -n $ifile -o $ofile");
            &echo_done("done\n");
        }
        else
        {
            if ( $iformat eq "sff" )
            {
                &echo("   Creating scratch file ... ");
                
                $tmp_file = Registry::Paths->new_temp_path("seq_convert");
                &Common::OS::run3_command("sff2fastq -n $ifile -o $tmp_file");

                $ifh = &Common::File::get_read_handle( $tmp_file );
                $iformat = "fastq";

                &echo_done("done\n");
            }
            else {
                $ifh = &Common::File::get_read_handle( $ifile );
            }                
            
            &echo("   Converting $iname ... ");

            &Common::File::delete_file_if_exists( $ofile ) if defined $ofile and $clobber;
            $ofh = &Common::File::get_write_handle( $ofile );
            
            $code = &Seq::Convert::convert_seqs_code( 
                {
                    "iformat" => $iformat,
                    "oformat" => $oformat,
                    "readbuf" => $conf->readbuf,
                    "hdrinfo" => $conf->hdrinfo,
                    "noinfo" => $conf->noinfo,
                    "comp" => $conf->comp,
                    "numids" => $conf->numids,
                    "degap" => $conf->degap,
                    "dedup" => $conf->dedup,
                    "upper" => $conf->upper,
                    "lower" => $conf->lower,
                    "t2u" => $conf->t2u,
                    "u2t" => $conf->u2t,
                    "qualsub" => $conf->qualsub,
                });

            eval $code;
            
            if ( $@ ) {
                &error( $@, "EVAL ERROR" );
            }
            
            $ifh->close;
            $ofh->close;

            if ( $replace )
            {
                &Common::File::delete_file( $ifile );
                &Common::File::rename_file( $ofile, $ifile );
            }

            &echo_done( "$seq_count seq[s]\n" );

            if ( $tmp_file )
            {
                &echo("   Deleting scratch file ... ");
                &Common::File::delete_file( $tmp_file );
                &echo_done("done\n");
            }
        }
    }

    &echo_bold( "Finished\n\n" );

    return;
}

sub convert_seqs_args
{
    # Niels Larsen, February 2010.

    # Checks and expands the match routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %conf, $suffix, $ifile, $iformat, $ofile, $oformat, $seqch, 
         $minqual, $maxqual, $qualtype, @list, $str, $stats, $osuffix, $odir );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>> FILES AND FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Do input files exist,

    &Common::File::check_files( $args->ifiles, "efr", \@msgs );
    &append_or_exit( \@msgs, $msgs );

    # Is output format okay,

    $oformat = $args->oformat;

    &Seq::Args::check_name( $oformat, \@Formats, "output format", \@msgs );
    &append_or_exit( \@msgs, $msgs );

    $osuffix = $args->osuffix;

    # Create a list of input/output files and their formats, 

    foreach $ifile ( @{ $args->ifiles } )
    {
        $stats = bless &Seq::IO::detect_file( $ifile );

        if ( not ( $iformat = $args->iformat ) ) {
            $iformat = $stats->seq_format;
        }
        
        &Seq::Args::check_name( $iformat, \@Formats, "input format", \@msgs );

        if ( not ( $odir = $args->odir ) ) {
            $odir = &File::Basename::dirname( $ifile );
        }
        
        if ( not ( $ofile = $args->ofile ) )
        {
            $ofile = $odir ."/". &File::Basename::basename( $ifile );
            $ofile .= $osuffix // "." . $oformat;
        }

        if ( $iformat eq $oformat ) {
            push @msgs, ["ERROR", qq (Input format ($iformat) matches output format ($oformat) -> "$ifile") ];
        } elsif ( not $Formats{ $iformat }{ $oformat } ) {
            push @msgs, ["ERROR", qq (Input format ($iformat) cannot be converted to $oformat format -> "$ifile") ];
        }            
        
        push @{ $conf{"io"} }, bless {
            "ifile" => $ifile,
            "ofile" => $ofile,
            "iformat" => $iformat,
            "oformat" => $oformat,
        };
    }
    
    &append_or_exit( \@msgs, $msgs );

    # Check that output files do not exist, unless clobber is set,

    if ( not $args->clobber )
    {
        &Common::File::check_files([ map { $_->ofile } @{ $conf{"io"} } ], "!e", \@msgs );
        &append_or_exit( \@msgs, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> QUALITY SUBSTITUTION <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $str = $args->qualsub )
    {
        ( $seqch, $minqual, $maxqual, $qualtype ) = split /\s*,\s*/, $str;

        if ( not defined $seqch or not defined $minqual or 
             not defined $maxqual or not defined $qualtype )
        {
            push @msgs, ["ERROR", qq (Wrong looking format -> "$str") ];
            push @msgs, ["INFO", qq (It should be like this: "N,0,100,Illumina_1.3") ];
            push @msgs, ["INFO", "" ];
            push @msgs, ["INFO", qq (Allowed quality encodings are:) ];

            map { push @msgs, ["INFO", $_] } &Seq::Common::qual_config_names();
        }

        &append_or_exit( \@msgs, $msgs );
        
        if ( length $seqch != 1 ) {
            push @msgs, ["ERROR", qq (The substitution character must be a single printable character) ];
        }

        &Registry::Args::check_number( $minqual, 0, 100, \@msgs );
        &Registry::Args::check_number( $maxqual, 0, 100, \@msgs );

        &Seq::Args::check_qualtype( $qualtype, \@msgs );
        
        &append_or_exit( \@msgs, $msgs );

        $conf{"qualsub"} =
        {
            "seqch" => $seqch,
            "minch" => &Seq::Common::qual_to_qualch( $minqual/100, $qualtype ),
            "maxch" => &Seq::Common::qual_to_qualch( $maxqual/100, $qualtype ),
        };
    }
    else {
        $conf{"qualsub"} = undef;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf{"readbuf"} = $args->readbuf;
    $conf{"hdrinfo"} = $args->hdrinfo;
    $conf{"noinfo"} = $args->noinfo;
    $conf{"replace"} = $args->replace;
    $conf{"clobber"} = $args->clobber;
    $conf{"comp"} = $args->comp;
    $conf{"numids"} = $args->numids;
    $conf{"degap"} = $args->degap;
    $conf{"dedup"} = $args->dedup;
    $conf{"upper"} = $args->upper;
    $conf{"lower"} = $args->lower;
    $conf{"t2u"} = $args->t2u;
    $conf{"u2t"} = $args->u2t;
    $conf{"stats"} = $args->stats;
    $conf{"silent"} = $args->silent;

    bless \%conf;

    return wantarray ? %conf : \%conf;
}

sub divide_chunks_fasta
{
    # Niels Larsen, March 2009.

    # Splits the entries in the given input fasta file(s) equally into the given 
    # named output fasta files, so there are approximately the same amount of 
    # sequence in each. This is used to split data between machines for example.
    # Returns the total number of entries written.

    my ( $ipaths,      # Input paths
         $opaths,      # Output paths
        ) = @_;

    # Returns integer.

    my ( @ipaths, @opaths, $ipath, $opath, @lens, $totlen, $maxlen, $sumlen, $seq, 
         $ifh, $ofh, $i, $dir, $ocount );
    
    @ipaths = @{ $ipaths };
    @opaths = @{ $opaths };

    $totlen = 0;
    
    foreach $ipath ( @ipaths )
    {
        @lens = map { $_->[1] } &Seq::Stats::measure_fasta_list( $ipath );
        $totlen += &Common::Util::sum( \@lens );
    }
    
    $sumlen = 0;
    $ocount = 0;
    
    for ( $i = 0; $i <= $#opaths; $i++ )
    {
        $opath = $opaths[$i];
        
        $dir = File::Basename::dirname( $opath );
        &Common::File::create_dir_if_not_exists( $dir );

        $ofh = &Common::File::get_write_handle( $opath );
        
        $maxlen = int ( ($i+1) * $totlen / scalar @opaths );
        
        if ( not defined $ifh ) {
            $ifh = &Common::File::get_read_handle( shift @ipaths );
        }
        
        while ( $sumlen < $maxlen )
        {
            if ( $seq = bless &Seq::IO::read_seq_fasta( $ifh ), "Seq::Common" )
            {
                $sumlen += $seq->seq_len;
                &Seq::IO::write_seq_fasta( $ofh, $seq );
                $ocount += 1;
            }
            else 
            {
                $ifh->close;
                $ifh = &Common::File::get_read_handle( shift @ipaths );
            }
        }                    
        
        $ofh->close;
    }
    
    $ifh->close if defined $ifh;
    
    return $ocount;
}
    
sub convert_seqs_code
{
    # Niels Larsen, October 2009.

    # Returns a string with code that when eval'ed reads and writes from input 
    # to output handles. 

    my ( $args,
        ) = @_;

    # Returns string.

    my ( $iformat, $oformat, $read_sub, $write_sub, $type_str, $code, $id, 
         $i, $readbuf, $chs );

    $iformat = $args->{"iformat"};
    $oformat = $args->{"oformat"};
    $readbuf = $args->{"readbuf"};

    $read_sub = "Seq::IO::read_seqs_$iformat";
    $write_sub = "Seq::IO::write_seqs_$oformat";

    $code = qq (

    \$seq_count = 0;
);

    if ( $args->{"dedup"} )
    {
        $code .= q (
    %seen = ();
);
    }
     
    $code .= qq (
    while ( \$seqs = &$read_sub( \$ifh, $readbuf ) )
    {);
    
    if ( $args->{"comp"} ) 
    {
        $code .= q (
        &Seq::List::change_complement( $seqs ););
    }

    if ( $args->{"numids"} )
    {
        $code .= q (
        $i = $seq_count;
        $seqs = [ map { $_->{"id"} = ++$i; $_ } @{ $seqs } ];);
    }

    if ( $args->{"degap"} )
    {
        $code .= q (
        &Seq::List::delete_gaps( $seqs ););        
    }

    if ( $args->{"upper"} )
    {
        $code .= q (
        &Seq::List::change_to_uppercase( $seqs ););
    }

    if ( $args->{"lower"} )
    {
        $code .= q (
        &Seq::List::change_to_lowercase( $seqs ););
    }

    if ( $args->{"t2u"} )
    {
        $code .= q (
        &Seq::List::change_to_rna( $seqs ););
    }

    if ( $args->{"u2t"} )
    {
        $code .= q (
        &Seq::List::change_to_dna( $seqs ););
    }

    if ( $chs = $args->{"qualsub"} )
    {
        $code .= qq (
        &Seq::List::change_by_quality( \$seqs, '$chs->{"seqch"}', '$chs->{"minch"}', '$chs->{"maxch"}' ););
    }
    
    if ( $args->{"hdrinfo"} )
    {
        $code .= q (
        &Seq::List::add_qual_to_info( $seqs ););
    }

    if ( $args->{"noinfo"} )
    {
        $code .= q (
        &Seq::List::delete_info( $seqs ););
    }

    if ( $args->{"dedup"} )
    {
        $code .= q (
        @{ $seqs } = grep { not $seen{ $_->{"id"} } and $seen{ $_->{"id"} } = 1 } @{ $seqs };
);
    }
    
    $code .= qq (
        \$seq_count += &$write_sub( \$ofh, \$seqs ););

    $code .= qq (\n    }\n);

    return $code;
}

sub divide_seqs_fasta
{
    # Niels Larsen, November 2007.

    # TODO - inefficient, use seq_convert

    # Reads a given file of fasta entries and writes each entry to a separate
    # file. The names of the single-entry files are that of the "parent" with 
    # ".n" appended, where n starts at 1. An optional write-path can be given.
    # Returns the number of entries processed. 

    my ( $ifile,    # Input file
         $opath,    # Output path - OPTIONAL
         $suffix,   # Suffix string - OPTIONAL
        ) = @_;

    # Returns integer. 

    my ( $i_fh, $seq, $i, @ofiles, $ofile );

    $i_fh = &Common::File::get_read_handle( $ifile );

    $opath = $ifile if not defined $opath;
    $i = 0;

    while ( $seq = &Seq::IO::read_seq_fasta( $i_fh ) )
    {
        $ofile = $opath .".". $i++;
        $ofile .= $suffix if defined $suffix;
        
        &Common::File::delete_file_if_exists( $ofile );
        &Seq::IO::write_seqs_fasta( $ofile, [ $seq ] );

        push @ofiles, $ofile;
    }

    $i_fh->close;

    return wantarray ? @ofiles : \@ofiles;
}

sub rarefy
{
    # Niels Larsen, March 2013.
    
    # Reads a set of files and writes a new set that has the same number 
    # of sequences in all files. That number is that of the smallest of 
    # any input file above a given minimum, which defaults to one. Files
    # with less than the given minimum are not written. The output files
    # take the same format as the input files, but get a given name 
    # suffix and can be directed to a given output directory. Returns
    # nothing.

    my ( $args,             # Arguments hash
        ) = @_;
    
    # Returns nothing.

    my ( $recipe, $defs, $conf, $counts, $count, $ndcs, $maxval, $minseq,
         $i, $minval, $file, $clobber, $ifh, $ofh, $read_sub, $write_sub,
         $seqs, $files, $readbuf, $ifile, $ofile, $format, $total, $mask,
         $seqs2, $time_start, $seconds, $stats, $stat, @counts, $maxseq );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "seqfiles" => [],
        "minseq" => undef,
        "maxseq" => undef,
        "suffix" => ".rare",
        "readbuf" => 10_000,
        "outdir" => undef,
        "stats" => undef,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Convert::rarefy_args( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $minseq = $conf->minseq;
    $maxseq = $conf->maxseq;
    $files = $conf->files;
    $clobber = $conf->clobber;
    $readbuf = $conf->readbuf;

    $Common::Messages::silent = $args->silent;

    $stats->{"name"} = "sequence-rarefy";
    $stats->{"title"} = "Sequence rarefaction";

    $stats->{"params"} = [
        {
            "title" => "Minimum reads required",
            "value" => $conf->minseq,
        }];

    &echo_bold( qq (\nSequence rarefaction:\n) );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> COUNT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Counting input files ... ");

    $counts = &Seq::Stats::count_seq_files(
        {
            "ifiles" => [ map { $_->{"ifile"} } @{ $files } ],
            "silent" => 1,
        });

    $count = scalar @{ $counts };
    &echo_done("$count\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> DELETE OLD OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $clobber )
    {
        &echo("   Deleting old outputs ... ");

        $count = 0;

        foreach $file ( @{ $files } ) {
            $count += &Common::File::delete_file_if_exists( $file->{"ofile"} );
        }

        &echo_done("$count\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FIND MAXIMUM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Finding common maximum ... ");

    @counts = ();

    for ( $i = 0; $i <= $#{ $counts }; $i += 1 )
    {
        if ( ( $count = $counts->[$i]->seq_count ) >= $minseq )
        {
            if ( defined $maxseq ) {
                $count = &List::Util::min( $maxseq, $count );
            }

            push @counts, $count;
        }
        
        $files->[$i]->{"count"} = $counts->[$i]->seq_count;
    }

    if ( @counts )
    {
        $minval = &List::Util::min( @counts );

        push @{ $stats->{"params"} }, {
            "title" => "Minimum reads per file",
            "value" => $minval,
        },{
            "title" => "Maximum reads per file",
            "value" => $maxseq,
        };
    }
    else 
    {
        $maxval = &List::Util::max( map { $_->seq_count } @{ $counts } );

        $minseq = &Common::Util::commify_number( $minseq );
        $maxval = &Common::Util::commify_number( $maxval );

        &echo("\n");
        &echo_messages([["ERROR", qq (All sequence files have less then $minseq sequences) ],
                        ["INFO", qq (The highest sequence count in any file is $maxval) ]]);
        exit;
    }

    &echo_done("$minval\n");

    &echo("   Output files to write ... ");

    $count = scalar @counts;

    &echo_done("$count\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $time_start = &Common::Messages::time_start();

    foreach $file ( @{ $files } )
    {
        $total = $file->{"count"};

        $stat = [
            &File::Basename::basename( $file->{"ifile"} ),
            $file->{"count"} 
            ];
        
        if ( $total >= $minseq )
        {
            $ifile = $file->{"ifile"};
            $ofile = $file->{"ofile"};
            $format = $file->{"format"};
            
            &echo("   Writing $ofile ... ");
            
            $ifh = &Common::File::get_read_handle( $ifile );
            $ofh = &Common::File::get_write_handle( $ofile );
            
            $read_sub = &Seq::IO::get_read_routine( $ifile, $format );
            $write_sub = &Seq::IO::get_write_routine( $format );
            
            # This is a list of evenly spaced 1's among 0's, so that the number of
            # 1's equal $minval. Then below the sequences are selected where this
            # mask is 1.
            
            $mask = &Common::Util::mask_pool_even( $total, $minval );
            
            $count = 0;
            
            {
                no strict "refs";
                
                while ( $seqs = $read_sub->( $ifh, $readbuf ) )
                {
                    $seqs2 = [];
                    
                    for ( $i = 0; $i <= $#{ $seqs }; $i += 1 )
                    {
                        push @{ $seqs2 }, $seqs->[$i] if $mask->[$i];
                    }
                    
                    $seqs = $seqs2;
                    
                    splice @{ $mask }, 0, scalar @{ $seqs };
                    
                    $count += $write_sub->( $ofh, $seqs );
                }
            }
            
            &Common::File::close_handle( $ofh );
            &Common::File::close_handle( $ifh );

            push @{ $stat }, &File::Basename::basename( $ofile ), $count;

            &echo_done("$count\n");
        }
        else 
        {
            push @{ $stat }, "", 0;
        }
        
        push @{ $stats->{"table"} }, &Storable::dclone( $stat );
    }

    $seconds = &time_elapsed() - $time_start;
    
    $stats->{"seconds"} = $seconds;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();
    
    &Common::File::delete_file_if_exists( $conf->statfile ) if $clobber;
    &Seq::Convert::write_rarefy_stats( $conf->statfile, bless $stats );

    &echo("   Run time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );

    &echo_bold( qq (Finished\n\n) );

    return;
}

sub rarefy_args
{
    # Niels Larsen, March 2013.

    # Checks and expands arguments to a configuration hash that suits the 
    # rarefy routine. It is checked here that files exist etc, and fatal 
    # error messages are printed to STDERR. 

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns a hash.

    my ( $files, $file, $format, @msgs, $conf, $outdir, $clobber, $ofile,
         $suffix, $name );

    if ( $files = $args->seqfiles and @{ $files } )
    {
	&Common::File::check_files( $files, "efr", \@msgs );
        &append_or_exit( \@msgs );

        foreach $file ( @{ $files } )
        {
            if ( -s $file )
            {
                $format = &Seq::IO::detect_format( $file, \@msgs );
                
                push @{ $conf->{"files"} }, {
                    "ifile" => $file,
                    "format" => $format,
                };
            }
        }
    }
    else {
        push @msgs, ["ERROR", qq (Input sequence files must be given) ];
    }
    
    &append_or_exit( \@msgs, $msgs );

    if ( not ( $conf->{"minseq"} = $args->minseq ) ) {
        push @msgs, ["ERROR", qq (A minimum sequence number must be given) ];
    }

    &append_or_exit( \@msgs, $msgs );

    if ( $conf->{"maxseq"} = $args->maxseq ) {
        &Registry::Args::check_number( $conf->{"maxseq"}, $conf->{"minseq"}, undef, \@msgs );
    }        

    &append_or_exit( \@msgs, $msgs );

    $conf->{"suffix"} = $args->suffix;
    $conf->{"suffix"} = ".". $conf->{"suffix"} if $conf->{"suffix"} !~ /^\./;
    
    $conf->{"readbuf"} = $args->readbuf;
    $conf->{"clobber"} = $args->clobber;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Output directory. It must exist if given, unless clobber is on (then it
    # will be created by the caller),

    if ( $outdir = $args->outdir )
    {
        if ( not $conf->{"clobber"} )
        {
            if ( not -d $outdir ) {
                push @msgs, ["ERROR", qq (Output directory does not exist -> "$outdir") ];
                push @msgs, ["INFO", qq (It will be created with --clobber) ];
            }
        }

        $conf->{"outdir"} = $outdir;
    }
    else {
        $conf->{"outdir"} = "";
    }

    &append_or_exit( \@msgs, $msgs );

    # Output sequence files. If output directory given, replace the directory
    # part of the input files with that. Then all the suffix to all files. 
    # Then, unless clobber, check that these files do not exist,

    $outdir = $conf->{"outdir"};
    $clobber = $conf->{"clobber"};
    $suffix = $conf->{"suffix"};

    foreach $file ( @{ $conf->{"files"} } )
    {
        $file->{"ofile"} = &Common::Names::set_path( $file->{"ifile"}, $suffix, $outdir );
    }

    if ( not $clobber ) {
        &Common::File::check_files([ map { $_->{"ofile"} } @{ $conf->{"files"} } ], "!e", \@msgs );
    }

    # Statistics file,

    $name = &File::Basename::basename( $0 );

    if ( $args->stats ) {
        $conf->{"statfile"} = $args->stats;
    } elsif ( $outdir ) {
        $conf->{"statfile"} = "$outdir/$name.stats";
    } else {
        $conf->{"statfile"} = "$name.stats";
    }

    if ( $conf->{"statfile"} and not $clobber ) {
        &Common::File::check_files([ $conf->{"statfile"}], "!e", \@msgs );
    }
    
    if ( @msgs ) {
        push @msgs, ["INFO", qq (The --clobber option overwrites existing files) ];
    }

    &append_or_exit( \@msgs, $msgs );

    bless $conf;
    
    return wantarray ? %{ $conf } : $conf;
}

sub write_rarefy_stats
{
    # Niels Larsen, March 2013. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $time, $i_total, $o_total, $row, $str, $file, $param_str, 
         @row, $totstr, $values, $item, $title, $value );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETER MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $param_str = "";

    foreach $item ( @{ $stats->{"params"} } )
    {
        $title = $item->{"title"};
        $value = $item->{"value"};
        
        $param_str .= qq (         item = $title: $value\n);
    }

    chomp $param_str;
    
    $time = &Time::Duration::duration( $stats->{"seconds"} );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ASSEMBLE HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $values = $stats->{"table"};

    $i_total = grep { $_->[0] ne "" } @{ $values };
    $o_total = grep { $_->[2] ne "" } @{ $values };

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
      hrow = Inputs\t$i_total files
      hrow = Outputs\t$o_total files
      <menu>
         title = Parameters
$param_str
      </menu>
      date = $stats->{"finished"}
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> COUNTS TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text .= qq (
   <table>
      colh = Input files\tReads\tOutput files\tReads\tPct
);

    foreach $row ( sort { $b->[1] <=> $a->[1] } @{ $values } )
    {
        @row = "file=". $row->[0];

        push @row, &Common::Util::commify_number( $row->[1] );

        if ( $row->[2] eq "" )
        {
            push @row, "", "", "";
        }
        else
        {
            push @row, "file=". $row->[2];
            push @row, &Common::Util::commify_number( $row->[3] );
            push @row, sprintf "%.2f", 100 * $row->[3] / $row->[1];
        }
        
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
