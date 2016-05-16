package Seq::Stats;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Sequence statistics related routines. UNFINISHED.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

use vars qw ( *AUTOLOAD );

@EXPORT_OK = qw (
                 &colstats
                 &check_seq_file
                 &check_seq_files
                 &check_seq_files_args
                 &count_seq_file
                 &count_seq_file_orig
                 &count_seq_files
                 &count_seq_files_args
                 &count_seq_list
                 &create_stats_classify
                 &format_counts
                 &format_files
                 &format_histogram
                 &format_params
                 &hist_seq_file
                 &hist_seq_files
                 &hist_seq_files_args
                 &measure_fasta
                 &measure_fasta_list
                 &plot_hist_text
                 &update_stats_clusters
);

use POSIX;

use Math::GSL;
use Math::GSL::Histogram qw /:all/;

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Table;
use Common::Names;

use Registry::Args;

use Seq::Common;
use Seq::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub colstats
{
    # Niels Larsen, January 2010. 

    # Input is a list of sequence-strings, that may or may not be 
    # aligned. Output a list of column statistics for this "alignment".
    # See Seq::Common::seq_stats for format.

    my ( $strs,         # List of strings
         $begcol,       # Starting column
         $type,         # Sequence type
        ) = @_;

    # Returns a list.
         
    my ( $colpos, $colstr, $seq, $i, @maxcols, @stats );

    $colpos = $begcol;
    @maxcols = map { (length $_) - 1 } @{ $strs };

    while ( 1 )
    {
        $colstr = "";

        for ( $i = 0; $i <= $#{ $strs }; $i++ )
        {
            if ( $colpos <= $maxcols[$i] ) {
                $colstr .= substr $strs->[$i], $colpos, 1;
            }
        }

        if ( $colstr )
        {
            $seq = Seq::Common->new({ "id" => "dummy", "seq" => $colstr, "type" => $type }, 0 );
            push @stats, [ $seq->seq_stats ];
            
            $colpos += 1;
        }
        else {
            last;
        }
    }

    return wantarray ? @stats : \@stats;
}

sub check_seq_file
{
    # Niels Larsen, March 2013. 

    # Counts the number of sequence entries in a given file in the fastest 
    # way. For some formats it is done by getting the number of lines with
    # 'wc --lines', then dividing by e.g. two or four. For other formats,
    # we grep with certain expressions, like "^>" for wrapped fasta format.

    my ( $file,      # Input file name
         $args,
        ) = @_;

    # Returns a hash.

    my ( $format, $reader, $counts, $fh, $seqs, $seq_count, $err_count,
         $readbuf, $print, $writer, $write );

    if ( not -e $file or -s $file == 0 )
    {
        $counts->{"seq_count"} = 0;
        $counts->{"err_count"} = 0;

        bless $counts;

        return wantarray ? %{ $counts } : $counts;
    }

    $format = &Seq::IO::detect_file( $file )->{"format"};
    $reader = &Seq::IO::get_read_routine( $file, $format ) ."_check";

    $readbuf = $args->readbuf;
    $write = $args->print;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $fh = &Common::File::get_read_handle( $file );

    {
        no strict "refs";

        while ( $seqs = $reader->( $fh, $readbuf ) )
        {
            $seq_count = scalar @{ $seqs };
            $err_count = grep { $_->{"info"} =~ /seq_error=1/ } @{ $seqs };

            if ( $write )
            {
                if ( @{ $seqs } = grep { $_->{"info"} =~ /seq_error=1/ } @{ $seqs } ) {
                    &dump( $seqs );
                }
            }

            $counts->{"seq_count"} += $seq_count;
            $counts->{"err_count"} += $err_count;
        }
    }

    &Common::File::close_handle( $fh );

    bless $counts;

    return wantarray ? %{ $counts } : $counts;
}

sub check_seq_files
{
    # Niels Larsen, March 2013. 

    # Accepts multiple files and returns a list of hashes with sequence 
    # counts.

    my ( $args,
        ) = @_;

    # Returns a list.

    my ( $defs, $conf, @counts, $counts, $name, $seqs, $errs, $str, 
         $ifile, $ofile, $lines, $readbuf );

    $defs = {
        "ifiles" => [],
        "table" => undef,
        "dumps" => 0,
        "titles" => 1,
        "totals" => 1,
        "indent" => 2,
        "readbuf" => 1000,
        "clobber" => 0,
        "silent" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Stats::check_seq_files_args( $args );

    $readbuf = $conf->readbuf;

    local $Common::Messages::silent = $conf->silent;

    &echo_bold("\nChecking files:\n");

    foreach $ifile ( @{ $conf->ifiles } )
    {
        $name = &File::Basename::basename( $ifile );
        &echo("   Counting $name ... ");
        
        $counts = &Seq::Stats::check_seq_file(
            $ifile,
            bless { "readbuf" => $conf->readbuf, "print" => $conf->dumps },
            );
        
        $seqs = $counts->{"seq_count"};
        $errs = $counts->{"err_count"};
        
        $counts->{"seq_file"} = $ifile;
        
        push @counts, bless $counts;
        
        $str = $seqs;
        $str .= " / $errs" if $errs;
        
        &echo_done("$str\n");
    }
    
    if ( not defined wantarray )
    {
        $ofile = $conf->table;
        
        if ( $ofile ) {
            &echo("   Writing $ofile ... ");
        } else {
            &echo("   Writing to STDOUT ... ");
        }

        $lines = &Seq::Stats::format_errors( \@counts, $conf );
        
        &Common::File::delete_file_if_exists( $conf->table ) if $conf->clobber;
        &Common::File::write_file( $conf->table, [ map { $_."\n" } @{ $lines } ]);
    
        &echo_done("done\n");
    }

    &echo_bold("Finished\n\n");

    return wantarray ? @counts : \@counts;
}

sub check_seq_files_args
{
    # Niels Larsen, September 2012.

    # Checks input arguments and adds defaults. 

    my ( $args,
        ) = @_;

    my ( @msgs, @files, $suffix, $conf );

    # Inputs,

    $conf->{"ifiles"} = $args->ifiles;

    if ( $args->ifiles ) {
	&Common::File::check_files( $args->ifiles, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", "No input sequence files given"];
    }

    &append_or_exit( \@msgs );

    # Parameters,

    $conf->{"readbuf"} = $args->readbuf;
    &Registry::Args::check_number( $args->readbuf, 1, undef, \@msgs );

    $conf->{"titles"} = $args->titles;
    $conf->{"totals"} = $args->totals;

    &append_or_exit( \@msgs );

    # Outputs,

    $conf->{"table"} = $args->table;

    if ( $args->table and not $args->clobber ) {
	&Common::File::check_files([ $args->table ], "!e", \@msgs );
    }

    &append_or_exit( \@msgs );

    $conf->{"dumps"} = $args->dumps;
    $conf->{"clobber"} = $args->clobber;
    $conf->{"indent"} = $args->indent;
    $conf->{"silent"} = $args->silent;

    $conf = bless $conf;

    return wantarray ? %{ $conf } : $conf;
}

sub count_seq_file
{
    # Niels Larsen, January 2011. 

    # Counts the number of sequence entries in a given file in the fastest 
    # way. For some formats it is done by getting the number of lines with
    # 'wc --lines', then dividing by e.g. two or four. For other formats,
    # we grep with certain expressions, like "^>" for wrapped fasta format.

    my ( $file,   # Input file name
        ) = @_;

    # Returns a hash.

    my ( $format, $lines, $line, $stats, $counts, $count, $fh, $routine, 
         $seqs, $len, $lensum );

    if ( not -e $file or -s $file == 0 )
    {
        $counts->{"seq_count"} = 0;
        $counts->{"seq_count_orig"} = 0;

        bless $counts;

        return wantarray ? %{ $counts } : $counts;
    }

    $stats = &Seq::IO::detect_file( $file );

    $format = $stats->{"seq_format"};

    if ( $stats->{"has_counts"} ) 
    {
        # >>>>>>>>>>>>>>>>>>>>>> SEQUENCE + READS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $counts = &Seq::Stats::count_seq_file_orig( $file );
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $format =~ /^(fasta|fastq)$/ )
        {
            $lines = &Common::File::count_lines( $file );

            if ( $format eq "fasta" ) {
                $count = $lines / 2;
            } elsif ( $format eq "fastq" ) {
                $count = $lines / 4;
            } else {
                &error( qq (Must add format -> "$format") );
            }
            
            $counts->{"seq_count"} = $count // 0;
            $counts->{"seq_count_orig"} = $counts->{"seq_count"};
        }
        else
        {
            $fh = &Common::File::get_read_handle( $file );
            $count = 0;

            if ( $format eq "fasta_wrapped" )
            {
                while ( defined ( $line = <$fh> ) )
                {
                    $count += 1 if $line =~ /^>/o;
                }
            }
            elsif ( $format eq "genbank" or $format eq "embl" )
            {
                while ( defined ( $line = <$fh> ) )
                {
                    $count += 1 if $line =~ m|^//|o;
                }
            }
            else
            {
                &Common::File::close_handle( $fh );
                &error( qq (Must add format -> "$format") );
            }
            
            &Common::File::close_handle( $fh );
            
            $counts->{"seq_count"} = $count // 0;
            $counts->{"seq_count_orig"} = $counts->{"seq_count"};
        }
    }

    bless $counts;

    return wantarray ? %{ $counts } : $counts;
}

sub count_seq_file_orig
{
    # Niels Larsen, May 2011. 

    # Counts the number of sequence entries in a given file, plus the number
    # in the header lines given as 'seq_count=nnn'. These two numbers are 
    # returned as a hash with the keys "seq_count" and "seq_count_orig".

    my ( $file,
         $format,
        ) = @_;

    # Returns integer.

    my ( $line, $count, $count_orig, $stats, $fh );

    if ( not defined $format ) {
        $format = &Seq::IO::detect_format( $file );
    }

    $fh = &Common::File::get_read_handle( $file );
    
    if ( $format =~ /^fasta|fasta_wrapped|uclust$/ )
    {
        while ( defined ( $line = <$fh> ) )
        {
            if ( $line =~ /^>/o )
            {
                $count += 1;
                $count_orig += $1 if $line =~ /seq_count=(\d+)/;
            }
        }
    }
    elsif ( $format eq "fastq" )
    {
        while ( defined ( $line = <$fh> ) )
        {
            if ( $line =~ /^\+/o )
            {
                $count += 1;
                $count_orig += $1 if $line =~ /seq_count=(\d+)/;
            }
        }
    }
    else {
        &error( qq (Must add format -> "$format") );
    }        

    &Common::File::close_handle( $fh );

    $stats = { "seq_count" => $count, "seq_count_orig" => $count_orig };
    
    return wantarray ? %{ $stats } : $stats;
}

sub count_seq_files
{
    # Niels Larsen, November 2011. 

    # Accepts multiple files and returns a list of hashes with sequence 
    # counts.

    my ( $args,
        ) = @_;

    # Returns a list.

    my ( $defs, $conf, @counts, $counts, $name, $seqs, $reads, $str, 
         $ifile, $ofile, $lines );

    $defs = {
        "ifiles" => [],
        "table" => undef,
        "titles" => 1,
        "totals" => 1,
        "indent" => 2,
        "readbuf" => 1000,
        "clobber" => 0,
        "silent" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Stats::count_seq_files_args( $args );

    local $Common::Messages::silent = $conf->silent;

    &echo_bold("\nCounting files:\n");

    foreach $ifile ( @{ $conf->ifiles } )
    {
        $name = &File::Basename::basename( $ifile );
        &echo("   Counting $name ... ");
        
        $counts = &Seq::Stats::count_seq_file( $ifile );
        
        $seqs = $counts->{"seq_count"};
        $reads = $counts->{"seq_count_orig"};
        
        $counts->{"seq_count_orig"} //= $seqs;
        $counts->{"seq_file"} = $ifile;
        
        push @counts, bless $counts;
        
        $str = $seqs;
        $str .= " / $reads" if $reads and $reads != $seqs;
        
        &echo_done("$str\n");
    }
    
    if ( not defined wantarray )
    {
        $ofile = $conf->table;
        
        if ( $ofile ) {
            &echo("   Writing $ofile ... ");
        } else {
            &echo("   Writing to STDOUT ... ");
        }

        $lines = &Seq::Stats::format_counts( \@counts, $conf );

        &Common::File::delete_file_if_exists( $conf->table ) if $conf->clobber;
        &Common::File::write_file( $conf->table, [ map { $_."\n" } @{ $lines } ]);
    
        &echo_done("done\n");
    }

    &echo_bold("Finished\n\n");

    return wantarray ? @counts : \@counts;
}

sub count_seq_files_args
{
    # Niels Larsen, September 2012.

    # Checks input arguments and adds defaults. 

    my ( $args,
        ) = @_;

    my ( @msgs, @files, $suffix, $conf );

    # Inputs,

    $conf->{"ifiles"} = $args->ifiles;

    if ( $args->ifiles ) {
	&Common::File::check_files( $args->ifiles, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", "No input sequence files given"];
    }

    &append_or_exit( \@msgs );

    # Parameters,

    $conf->{"readbuf"} = $args->readbuf;
    &Registry::Args::check_number( $args->readbuf, 1, undef, \@msgs );

    $conf->{"titles"} = $args->titles;
    $conf->{"totals"} = $args->totals;

    &append_or_exit( \@msgs );

    # Outputs,

    $conf->{"table"} = $args->table;

    if ( $args->table and not $args->clobber ) {
	&Common::File::check_files([ $args->table ], "!e", \@msgs );
    }

    &append_or_exit( \@msgs );

    $conf->{"clobber"} = $args->clobber;
    $conf->{"indent"} = $args->indent;
    $conf->{"silent"} = $args->silent;

    $conf = bless $conf;

    return wantarray ? %{ $conf } : $conf;
}

sub count_seq_list
{
    my ( $seqs,
        ) = @_;

    my ( $stats, $count, $seq );

    $stats->{"seq_count"} = scalar @{ $seqs };

    if ( $seqs->[0]->{"info"} and $seqs->[0]->{"info"} =~ /seq_count/ )
    {
        $count = 0;
        
        foreach $seq ( @{ $seqs } )
        {
            $count += $1 if $seq->{"info"} =~ /seq_count=(\d+)/;
        }

        $stats->{"seq_count_orig"} = $count;
    }
    else {
        $stats->{"seq_count_orig"} = $stats->{"seq_count"};
    }

    return wantarray ? %{ $stats } : $stats;
}
    
sub create_stats_classify
{
    # Niels Larsen, May 2011.

    # Creates a YAML file with counts in void context and returns a
    # perl structure in non-void context. The given file may contain several
    # "documents", which here means statistics tables with titles, type, 
    # values, etc. The routine updates the last document by appending to its 
    # table. Table headers are added only if there is no table. The 
    # formatting routines (see Workflow::Stats) know how to display the list 
    # of YAML documents.

    my ( $file,        # YAML file
         $stats,       # Statistics object 
        ) = @_;

    # Returns a hash.

    my ( @stats, $stat, $cla_count, $seq_count, $in_file, $dat_label,
         $out_file, $step_type, $flow_title, $cla_count_pct, $seq_count_pct, 
         $cla_total, $seq_total, $stat_rows, $row, $recp_title, $recp_author );

    # >>>>>>>>>>>>>>>>>>>>>>>>> FROM ENVIRONMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set variables to appear in the table; if given as arguments that takes 
    # precedence, second environment variables, and finally fallback defaults.
    # The environment is used for getting values set in recipes rather than
    # given to the programs. 

    $in_file = $stats->input_file || $ENV{"BION_STEP_INPUT"};
    $out_file = $stats->output_file || $ENV{"BION_STEP_OUTPUT"};

    $flow_title = $stats->{"flow_title"} || $ENV{"BION_FLOW_TITLE"} || "Classification";
    $recp_title = $stats->{"recipe_title"} || $ENV{"BION_RECIPE_TITLE"} || "Recipe run";
    $recp_author = $stats->{"recipe_author"} || $ENV{"BION_RECIPE_AUTHOR"} || &Common::Config::get_contacts()->{"email"};

    $step_type = $stats->{"step_type"} || "seq_classify";

    $stat_rows = $stats->stat_rows;

    if ( not $stat_rows or not @{ $stat_rows } ) {
        &error( qq (No statistics counts given) );
    }

    $cla_total = &List::Util::sum( map { $_->cla_count } @{ $stat_rows } );
    $seq_total = $stats->seq_total;    
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ ALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( -r $file ) {
        @stats = &Common::File::read_yaml( $file );
        $stat = &Storable::dclone( $stats[-1]->[-1] );
    } else {
        @stats = ();
        $stat = {};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> ADD HEADER DEPENDING <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Only add header if no statistics exist or this type of statistics is 
    # different from the previous,

    if ( not %{ $stat } or $stat->{"type"} ne $step_type )
    {
        $stat = undef;

        $stat->{"table"}->{"col_headers"} = [
            "Dataset", "Matches", "&nbsp;%&nbsp;", "Seqs", "&nbsp;%&nbsp;", 
            ];
    
        $stat->{"table"}->{"values"} = [[
            "", $cla_total, "", $seq_total, "",
            ]];
    
        $stat->{"table"}->{"row_headers"} = [];
    
        $stat->{"type"} = $step_type;
        $stat->{"title"} = $flow_title;
    }
    else {
        pop @{ $stats[-1] };
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILES AND TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $in_file and not $stat->{"input_file"} ) {
        $stat->{"input_file"} = $in_file;
    }

    if ( $out_file ) {
        $stat->{"output_file"} = $out_file;
    }

    $stat->{"recipe_title"} = $recp_title;
    $stat->{"recipe_author"} = $recp_author;
    $stat->{"stat_date"} = &Common::Util::time_string_to_epoch();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ADD ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Add table data rows given to the routine,

    foreach $row ( @{ $stat_rows } )
    {
        $dat_label = $row->dat_label || "";
        $cla_count = $row->cla_count || 0;
        $seq_count = $row->seq_count || 0;

        if ( $cla_total > 0 ) {
            $cla_count_pct = ( sprintf "%.1f", 100 * $cla_count / $cla_total );
        } else {
            $cla_count_pct = 0;
        }

        if ( $seq_total > 0 ) {
            $seq_count_pct = ( sprintf "%.1f", 100 * $seq_count / $seq_total );
        } else {
            $seq_count_pct = 0;
        }
        
        push @{ $stat->{"table"}->{"values"} }, [
            $dat_label,
            $cla_count,
            $cla_count_pct,
            $seq_count,
            $seq_count_pct,
        ];
    }

    # Add another row with the un-classified,

    $seq_count = $seq_total - &List::Util::sum( map { $_->seq_count } @{ $stat_rows } );

    push @{ $stat->{"table"}->{"values"} }, [ "Un-classified", "&nbsp;", "&nbsp;", $seq_count, $seq_count_pct ];

    if ( @stats ) {
        push @{ $stats[-1] }, $stat;
    } else {
        @stats = [ $stat ];
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OR RETURN <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Return updated list in non-void context, update file in void,

    if ( defined wantarray ) {
        return wantarray ? @stats : \@stats;
    } else {
        &Common::File::write_yaml( $file, \@stats );
    }

    return;
}

sub format_files
{
    my ( $files,
        ) = @_;

    my ( $str, $file, $type, $title, $menu, $value );

    $str = "";

    foreach $file ( @{ $files } )
    {
        $type = $file->{"type"} // "file";
        $title = $file->{"title"};

        if ( ref $file->{"value"} eq "ARRAY" )
        {
            $menu = "      <menu>\n";
            $menu .= "         title = $title\n";

            if ( @{ $file->{"value"} } )
            {
                foreach $file ( @{ $file->{"value"} } )
                {
                    $file = &File::Basename::basename( $file );
                    $menu .= qq (         item = $file\n);
                }
            }
            else {
                $menu .= qq (          item = Piped input\n);
            }
            
            $menu .= "      </menu>\n";

            $str .= $menu;
        }
        else
        {
            $value = &File::Basename::basename( $file->{"value"} );
            $str .= qq (      $type = $title\t$value\n);
        }
    }

    chomp $str;

    return $str;
}

sub format_histogram
{
    # Niels Larsen, September 2012. 
    
    # Creates a list of histogram lines with bins and values, meant as input for
    # plotting. Lines that start with "#" has derived data in key = value form.
    # The rest of the lines have bin-begin, bin-end, sequence count and maybe 
    # read count as fourth column, separated by single blanks.

    my ( $args,
        ) = @_;

    my ( $seqs, $reads, $fh, @lines, $min_bin, $max_bin, $bin, $s, $r,
         $beg, $end );

    $seqs = $args->seqhist;

    # Set bin bounds,

    $min_bin = 0;
    $max_bin = &Math::GSL::Histogram::gsl_histogram_bins( $seqs ) - 1;

    # Trim leading and trailing slots with zero values,

    if ( $args->trim )
    {
        while ( $min_bin <= $max_bin and 
                ( $s = &Math::GSL::Histogram::gsl_histogram_get( $seqs, $min_bin ) ) == 0 )
        {
            $min_bin += 1;
        }

        while ( $max_bin >= $min_bin and 
                ( $s = &Math::GSL::Histogram::gsl_histogram_get( $seqs, $max_bin ) ) == 0 )
        {
            $max_bin -= 1;
        }
    }

    # With read counts, 

    if ( $reads = $args->readhist )
    {
        for ( $bin = $min_bin; $bin <= $max_bin; $bin++ )
        {
            ( undef, $beg, $end ) = &Math::GSL::Histogram::gsl_histogram_get_range( $seqs, $bin );

            $s = &Math::GSL::Histogram::gsl_histogram_get( $seqs, $bin );
            $r = &Math::GSL::Histogram::gsl_histogram_get( $reads, $bin );
            
            $beg = int $beg;
            $end = int $end;

            push @lines, "$beg $end $s $r";
        }
    }

    # Without just sequence counts,

    else
    {
        for ( $bin = $min_bin; $bin <= $max_bin; $bin++ )
        {
            ( undef, $beg, $end ) = &Math::GSL::Histogram::gsl_histogram_get_range( $seqs, $bin );
            
            $s = &Math::GSL::Histogram::gsl_histogram_get( $seqs, $bin );
            
            $beg = int $beg;
            $end = int $end;

            push @lines, "$beg $end $s";
        }
    }

    # Put stats at the top,

    if ( $reads )
    {
        unshift @lines, ( 
            "# read_max = ". &Math::GSL::Histogram::gsl_histogram_max_val( $reads ),
            "# read_sum = ". &Math::GSL::Histogram::gsl_histogram_sum( $reads ),
            "# read_mean = ". &Math::GSL::Histogram::gsl_histogram_mean( $reads ),
            "# read_sigma = ". &Math::GSL::Histogram::gsl_histogram_sigma( $reads ),
        );
    }
    
    unshift @lines, ( 
        "# type = ". $args->type,
        "# bins = ". ( $max_bin - $min_bin + 1 ),
        "# seq_max = ". &Math::GSL::Histogram::gsl_histogram_max_val( $seqs ),
        "# seq_sum = ". &Math::GSL::Histogram::gsl_histogram_sum( $seqs ),
        "# seq_mean = ". &Math::GSL::Histogram::gsl_histogram_mean( $seqs ),
        "# seq_sigma = ". &Math::GSL::Histogram::gsl_histogram_sigma( $seqs ),
    );

    return wantarray ? @lines : \@lines;
}

sub format_counts
{
    my ( $counts,
         $args,
        ) = @_;

    my ( $head, $count, $total, $total_orig, @lines );
    
    if ( $args->titles ) {
        push @lines, "Seqs\tReads\tFile";
    }

    $total = 0;
    $total_orig = 0;
    
    foreach $count ( @{ $counts } )
    {
        $total += $count->seq_count;
        $total_orig += $count->seq_count_orig;

        push @lines, ( join "\t", ( 
            $count->seq_count,
            $count->seq_count_orig,
            $count->seq_file ) );
    }

    if ( $args->totals ) {
        push @lines, "$total\t$total_orig\tTotal";
    }

    return wantarray ? @lines : \@lines;
}

sub format_errors
{
    my ( $counts,
         $args,
        ) = @_;

    my ( $head, $count, $seq_total, $err_total, @lines );
    
    if ( $args->titles ) {
        push @lines, "Seqs\tErrors\tFile";
    }

    $seq_total = 0;
    $err_total = 0;
    
    foreach $count ( @{ $counts } )
    {
        $seq_total += $count->seq_count;
        $err_total += $count->err_count;

        push @lines, ( join "\t", ( 
            $count->seq_count,
            $count->err_count,
            $count->seq_file ) );
    }

    if ( $args->totals ) {
        push @lines, "$seq_total\t$err_total\tTotal";
    }

    return wantarray ? @lines : \@lines;
}

sub format_params
{
    my ( $params,
        ) = @_;

    my ( $str, $item, $title, $value );

    $str = qq (      <menu>
         title = Parameters
);

    foreach $item ( @{ $params } )
    {
        $title = $item->{"title"};
        $value = $item->{"value"};
        
        $str .= qq (         item = $title: $value\n);
    }

    $str .= qq (      </menu>);
    
    return $str;
}

sub hist_seq_file
{
    # Niels Larsen, September 2012. 

    # Creates a sequence length histogram from the given file, and a reads 
    # histogram if there are read counts in the file. The file is read with 
    # Seq::IO. Returns two Math::GSL::histogram objects. 

    my ( $file,
         $args,
        ) = @_;

    # Returns two element list.

    my ( $reader, $fh, $seqs, $s_hist, $r_hist, $has_counts, @lens, 
         $len, $i );

    $s_hist = &Math::GSL::Histogram::gsl_histogram_alloc( $args->histlen );
    &Math::GSL::Histogram::gsl_histogram_set_ranges_uniform( $s_hist, $args->histmin, $args->histmax + 1 );

    if ( &Seq::IO::detect_file( $file )->{"has_counts"} )
    {
        $r_hist = &Math::GSL::Histogram::gsl_histogram_alloc( $args->histlen );
        &Math::GSL::Histogram::gsl_histogram_set_ranges_uniform( $r_hist, $args->histmin, $args->histmax + 1 );

        $has_counts = 1;
    }

    $reader = &Seq::IO::get_read_routine( $file );
    $fh = &Common::File::get_read_handle( $file );

    {
        no strict "refs";

        while ( $seqs = $reader->( $fh, $args->readbuf ) )
        {
            @lens = map { length $_->{"seq"} } @{ $seqs };

            foreach $len ( @lens ) 
            {
                &Math::GSL::Histogram::gsl_histogram_increment( $s_hist, $len );
            }

            if ( $has_counts )
            {
                for ( $i = 0; $i <= $#{ $seqs }; $i++ )
                {
                    if ( $seqs->[$i]->{"info"} =~ /seq_count=(\d+)/ ) {
                        &Math::GSL::Histogram::gsl_histogram_accumulate( $r_hist, $lens[$i], $1 );
                    }
                }
            }
        }
    }

    &Common::File::close_handle( $fh );

    return ( $s_hist, $r_hist );
}

sub hist_seq_files
{
    # Niels Larsen, September 2012.

    # Accepts multiple files and writes either a total histogram or one for each
    # file. 

    my ( $args,
        ) = @_;

    # Returns a list.

    my ( $defs, $conf, $lines, $name, $seq_hist, $read_hist, $ifiles, $ifile,
         $ofiles, $ofile, $clobber, $i, $seq_tot, $read_tot, $has_counts, $plot );

    $defs = {
        "ifiles" => [],
        "all" => undef,
        "hsuf" => undef,
        "hlen" => 100,
        "hmin" => 1,
        "hmax" => 5000,
        "step" => 10,
        "trim" => 1,
        "plot" => 1,
        "readbuf" => 1000,
        "clobber" => 0,
        "silent" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Stats::hist_seq_files_args( $args );

    local $Common::Messages::silent = $conf->silent;

    $ifiles = $conf->ifiles;
    $clobber = $conf->clobber;
    $plot = $conf->plot;

    &echo_bold("\nLength histogram:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>> TOTAL HISTOGRAM <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
    # Add histograms for each file and write only a cumulative one,
    
    if ( $conf->all )
    {
        $seq_tot = &Math::GSL::Histogram::gsl_histogram_alloc( $conf->hlen );
        &Math::GSL::Histogram::gsl_histogram_set_ranges_uniform( $seq_tot, $conf->hmin, $conf->hmax + 1 );

        $read_tot = &Math::GSL::Histogram::gsl_histogram_alloc( $conf->hlen );
        &Math::GSL::Histogram::gsl_histogram_set_ranges_uniform( $read_tot, $args->hmin, $args->hmax + 1 );

        foreach $ifile ( @{ $ifiles } )
        {
            $name = &File::Basename::basename( $ifile );
            &echo("   Adding $name ... ");
            
            ( $seq_hist, $read_hist ) = &Seq::Stats::hist_seq_file(
                $ifile,
                bless {
                    "readbuf" => $conf->readbuf,
                    "histlen" => $conf->hlen,
                    "histmin" => $conf->hmin,
                    "histmax" => $conf->hmax,
                });
            
            &Math::GSL::Histogram::gsl_histogram_add( $seq_tot, $seq_hist );

            if ( $read_hist )
            {
                &Math::GSL::Histogram::gsl_histogram_add( $read_tot, $read_hist );
                $has_counts = 1;
            }

            &Math::GSL::Histogram::gsl_histogram_free( $seq_hist );
            &Math::GSL::Histogram::gsl_histogram_free( $read_hist );

            &echo_done("done\n");
        }

        $lines = &Seq::Stats::format_histogram(
            bless {
                "type" => "seq-length",
                "seqhist" => $seq_tot,
                "readhist" => ( $has_counts ? $read_tot : undef ),
                "trim" => $conf->trim,
            });

        $ofile = $conf->hist;

        if ( $plot ) {
            $lines = &Seq::Stats::plot_hist_text( $lines );
        }

        &Common::File::delete_file_if_exists( $ofile ) if $ofile and $clobber;
        &Common::File::write_file( $ofile, [ map { " ". $_ ."\n" } @{ $lines } ]);
            
        &Math::GSL::Histogram::gsl_histogram_free( $seq_tot );
        &Math::GSL::Histogram::gsl_histogram_free( $read_tot );
    }

    # >>>>>>>>>>>>>>>>>>>> INDIVIDUAL HISTOGRAMS <<<<<<<<<<<<<<<<<<<<<<<<<<

    else
    {
        $ofiles = $conf->hist;

        for ( $i = 0; $i <= $#{ $ifiles }; $i++ )
        {
            $ifile = $ifiles->[$i];
            $ofile = $ofiles->[$i];

            if ( $ofile )
            {
                $name = &File::Basename::basename( $ofile );
                &echo("   Writing $name ... ");
            }
            
            ( $seq_hist, $read_hist ) = &Seq::Stats::hist_seq_file(
                $ifile,
                bless {
                    "readbuf" => $conf->readbuf,
                    "histlen" => $conf->hlen,
                    "histmin" => $conf->hmin,
                    "histmax" => $conf->hmax,
                });

            $lines = &Seq::Stats::format_histogram( bless {
                "type" => "seq-length",
                "seqhist" => $seq_hist,
                "readhist" => $read_hist,
                "trim" => $conf->trim,
                });

            if ( $ofile and $clobber ) {
                &Common::File::delete_file_if_exists( $ofile );
            }

            if ( $plot ) {
                $lines = &Seq::Stats::plot_hist_text( $lines );
            }

            &Common::File::write_file( $ofile, [ map { " ". $_ ."\n" } @{ $lines } ]);
            
            &Math::GSL::Histogram::gsl_histogram_free( $seq_hist );
            &Math::GSL::Histogram::gsl_histogram_free( $read_hist );
            
            &echo_done("done\n");
        }
    }            

    &echo_bold("Finished\n\n");

    return;
}

sub hist_seq_files_args
{
    # Niels Larsen, September 2012.

    # Checks input arguments and adds defaults. Returns a configuration
    # object.

    my ( $args,
        ) = @_;

    # Returns object.

    my ( @msgs, @files, $suffix, $conf );

    # Inputs,

    $conf->{"ifiles"} = $args->ifiles;

    if ( $args->ifiles ) {
	&Common::File::check_files( $args->ifiles, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", "No input sequence files given"];
    }

    &append_or_exit( \@msgs );

    # Parameters,

    $conf->{"readbuf"} = $args->readbuf;
    $conf->{"hmin"} = $args->hmin;
    $conf->{"hmax"} = $args->hmax;
    $conf->{"step"} = $args->step;

    &Registry::Args::check_number( $args->readbuf, 1, undef, \@msgs );
    &Registry::Args::check_number( $args->hmin, 1, undef, \@msgs );
    &Registry::Args::check_number( $args->hmax, $args->hmin, undef, \@msgs );
    &Registry::Args::check_number( $args->step, 1, undef, \@msgs );

    &append_or_exit( \@msgs );

    $conf->{"hlen"} = int ( ( $conf->{"hmax"} - $conf->{"hmin"} + 1 ) / $conf->{"step"} );
    $conf->{"all"} = undef;

    # Outputs,

    if ( defined $args->all )
    {
        if ( $args->all ) {
            &Common::File::check_files([ $args->all ], "!e", \@msgs ) unless $args->clobber;
        }

        $conf->{"all"} = 1;
        $conf->{"hist"} = undef;
    }
    elsif ( $suffix = $args->hsuf )
    {
        @files = map { $_ . $suffix } @{ $args->ifiles };
        
        &Common::File::check_files( \@files, "!e", \@msgs ) unless $args->clobber;
        $conf->{"hist"} = \@files;
    }
    else {
        $conf->{"hist"} = [];
    }

    &append_or_exit( \@msgs );

    $conf->{"trim"} = $args->trim;
    $conf->{"plot"} = $args->plot;
    $conf->{"clobber"} = $args->clobber;
    $conf->{"silent"} = $args->silent;

    $conf = bless $conf;

    return wantarray ? %{ $conf } : $conf;
}

sub measure_fasta
{
    # Niels Larsen, September 2010.

    # Returns a two element list with the number of sequences, and the maximum
    # sequence length. 

    my ( $file,       # Input fasta file name or handle
         ) = @_;

    my ( $fh, $seq_count, $seq_len_max, $seq );

    $fh = &Common::File::get_read_handle( $file );

    $seq_count = 0;
    $seq_len_max = 0;

    while ( $seq = &Seq::IO::read_seq_fasta( $fh ) )
    {
        $seq_count += 1;
        $seq_len_max = &List::Util::max( $seq_len_max, &Seq::Common::seq_len( $seq ) );
    }
    
    &Common::File::close_handle( $fh );

    return ( $seq_count, $seq_len_max );
}

sub measure_fasta_list
{
    # Niels Larsen, September 2006.

    # Creates a list of [ id, length ] of the sequences in a given fasta file. 
    # If there are non-sequence entries they get counted too.

    my ( $file,       # Input fasta file name or handle
         ) = @_;

    my ( $fh, @counts, $seq );

    $fh = &Common::File::get_read_handle( $file );

    while ( $seq = &Seq::IO::read_seq_fasta( $fh ) )
    {
        push @counts, [ $seq->{"id"}, &Seq::Common::seq_len( $seq ) ];
    }
    
    &Common::File::close_handle( $fh );

    return wantarray ? @counts : \@counts;
}

sub plot_hist_text
{
    # Niels Larsen, September 2012. 

    # Creates a human readable histogram from the format generated by the
    # Seq::Stats::format_histogram routine. Input is a list of lines and output
    # is a new list of lines with horizontal bars scaled logarithmically to 
    # about 70 characters wide. 

    my ( $lines,
         $width,
        ) = @_;

    # Returns a list.

    my ( @lines, $i, $imax, %conf, @vals, $scale, $begwid, $endwid, $val,
         $valwid, $exp );

    $width //= 80;
    $exp = 0.6;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $i = 0;

    while ( $lines->[$i] =~ /^#/ )
    {
        if ( $lines->[$i] =~ /^#\s*(\S+)\s*=\s*(\S+)$/ )
        {
            $conf{ $1 } = $2;
        }
        else {
            &error( qq (Wrong looking header line -> "$lines->[$i]") );
        }

        $i += 1;
    }
    
    $imax = $#{ $lines };

    while ( $i <= $imax )
    {
        push @vals, [ split " ", $lines->[$i] ];
        $i += 1;
    }

    $begwid = &List::Util::max( map { length "$_" } map { $_->[0] } @vals );
    $endwid = &List::Util::max( map { length "$_" } map { $_->[1] } @vals );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $valwid = &List::Util::max( map { length "$_" } map { $_->[2] } @vals );

    # Header,

    push @lines, "";
    push @lines, "Sequence length distribution";
    push @lines, "----------------------------";
    push @lines, "";
    push @lines, " Total: ". &Common::Util::commify_number( $conf{"seq_sum"} );
    push @lines, "  Mean: ". sprintf "%.0f", $conf{"seq_mean"};
    push @lines, "";
    
    $scale = $width / $conf{"seq_max"} ** $exp;

    foreach $val ( @vals )
    {
        push @lines,
            ( sprintf "%$begwid.0f", $val->[0] ) ." - ". 
            ( sprintf "%$endwid.0f", $val->[1] ) ." | ".
            ( sprintf "%$valwid.0f", $val->[2] ) ." | ".
            ( "#" x ( $scale * $val->[2] ** $exp ) );
    }

    push @lines, "";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $conf{"read_sum"} )
    {
        $valwid = &List::Util::max( map { length "$_" } map { $_->[3] } @vals );

        # Header,
        
        push @lines, "";
        push @lines, "Read length distribution";
        push @lines, "------------------------";
        push @lines, "";
        push @lines, " Total: ". &Common::Util::commify_number( $conf{"read_sum"} );
        push @lines, "  Mean: ". sprintf "%.0f", $conf{"read_mean"};
        push @lines, "";
        
        $scale = $width / $conf{"read_max"} ** $exp;
        
        foreach $val ( @vals )
        {
            push @lines,
                ( sprintf "%$begwid.0f", $val->[0] ) ." - ". 
                ( sprintf "%$endwid.0f", $val->[1] ) ." | ".
                ( sprintf "%$valwid.0f", $val->[3] ) ." | ".
                ( "#" x ( $scale * $val->[3] ** $exp ) );
        }
    }

    push @lines, "";

    return wantarray ? @lines : \@lines;
}
    
sub update_stats_clusters
{
    # Niels Larsen, April 2011.

    # Updates a YAML file with counts in void context and returns the 
    # updated perl structure in non-void context. The given file may 
    # contain several "documents", which here means statistics tables 
    # with titles, type, values, etc. The routine updates the last document
    # by appending to its table. Table headers are added only if there 
    # is no table. The formatting routines (see Workflow::Stats) know 
    # how to display the list of YAML documents.

    my ( $file,        # YAML file
         $stats,       # Statistics object 
        ) = @_;

    # Returns a hash.

    my ( @stats, $stat, $clu_in, $seq_in, $clu_out, $seq_out, $in_file, 
         $out_file, $step_type, $step_title, $flow_title, $clu_out_pct,
         $seq_out_pct, $recp_title, $recp_author );

    # >>>>>>>>>>>>>>>>>>>>>>>>> FROM ENVIRONMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set variables to appear in the table; if given as arguments that takes 
    # precedence, second environment variables, and finally fallback defaults.
    # The environment is used for getting values set in recipes rather than
    # given to the programs. 

    $in_file = $stats->input_file || $ENV{"BION_STEP_INPUT"};
    $out_file = $stats->output_file || $ENV{"BION_STEP_OUTPUT"};

    $flow_title = $stats->{"flow_title"} || $ENV{"BION_FLOW_TITLE"} || "Clustering";
    $recp_title = $stats->{"recipe_title"} || $ENV{"BION_RECIPE_TITLE"} || "Recipe run";
    $recp_author = $stats->{"recipe_author"} || $ENV{"BION_RECIPE_AUTHOR"} || &Common::Config::get_contacts()->{"email"};

    $step_type = $stats->{"step_type"} || "seq_cluster";
    $step_title = $stats->{"step_title"} || $ENV{"BION_STEP_TITLE"} || "Sequence clustering";

    $clu_in = $stats->clu_in || 0;
    $seq_in = $stats->seq_in || 0;
    
    $clu_out = $stats->clu_out || 0;
    $seq_out = $stats->seq_out || 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ ALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( -r $file ) {
        @stats = &Common::File::read_yaml( $file );
        $stat = &Storable::dclone( $stats[-1]->[-1] );
    } else {
        @stats = ();
        $stat = {};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> ADD HEADER DEPENDING <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Only add header if no statistics exist or this type of statistics is 
    # different from the previous,

    if ( not %{ $stat } or $stat->{"type"} ne $step_type )
    {
        $stat = undef;

        $stat->{"table"}->{"col_headers"} = [
            "Method", "Clusters", "&Delta;", "&Delta; %", "Seqs", "&Delta;", "&Delta; %", 
            ];
    
        $stat->{"table"}->{"values"} = [[
            "", $clu_in, "", "", $seq_in, "", "",
            ]];
    
        $stat->{"table"}->{"row_headers"} = [];
    
        $stat->{"type"} = $step_type;
        $stat->{"title"} = $flow_title;
    }
    else {
        pop @{ $stats[-1] };
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILES AND TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $in_file and not $stat->{"input_file"} ) {
        $stat->{"input_file"} = $in_file;
    }

    if ( $out_file ) {
        $stat->{"output_file"} = $out_file;
    }

    $stat->{"recipe_title"} = $recp_title;
    $stat->{"recipe_author"} = $recp_author;
    $stat->{"stat_date"} = &Common::Util::time_string_to_epoch();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ADD ONE ROW <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Add table data rows given to the routine,

    if ( $clu_in == 0 ) {
        $clu_out_pct = "100.0";
    } else {
        $clu_out_pct = ( sprintf "%.1f", 100 * ( $clu_out - $clu_in ) / $clu_in );
    }
        
    if ( $seq_in == 0 ) {
        $seq_out_pct = "100.0";
    } else {
        $seq_out_pct = ( sprintf "%.1f", 100 * ( $seq_out - $seq_in ) / $seq_in );
    }
        
    push @{ $stat->{"table"}->{"values"} }, [
        $step_title,
        $clu_out,
        $clu_out - $clu_in, 
        $clu_out_pct,
        $seq_out,
        $seq_out - $seq_in, 
        $seq_out_pct,
    ];

    if ( @stats ) {
        push @{ $stats[-1] }, $stat;
    } else {
        @stats = [ $stat ];
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OR RETURN <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Return updated list in non-void context, update file in void,

    if ( defined wantarray ) {
        return wantarray ? @stats : \@stats;
    } else {
        &Common::File::write_yaml( $file, \@stats );
    }

    return;
}

1;

__END__
