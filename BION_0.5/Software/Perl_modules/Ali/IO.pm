package Ali::IO;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# TODO: Move functions in Ali::Import/Export in here. Then try to 
# eliminate Ali::Import and Ali::Export.
#
# Basic alignment IO routines for different formats. The Ali::Storage is 
# also IO, but at a higher level. 
#
# The native format is a binary memory-mapped file as mapfraw in PDL
# (Perl Data Language, http://pdl.perl.org) uses, called "raw" below.
# The "read" routine reads the whole file into RAM, but the much faster
# "connect" delays the reading until a function needs it. Either way 
# the $ali is treated the same, PDL handles it. 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;

use vars qw ( *AUTOLOAD );

use List::Util;

use base qw ( Ali::Common );

use Common::Config;
use Common::Messages;

use Registry::Args;

use Common::File;
use Common::Names;
use Common::Types;
use Common::Table;

use Seq::Stats;
use Seq::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINE NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# ali_exists
# connect_pdl                   Returns $ali memory-mapped to PDL raw file
# count_alis
# detect_file
# detect_files
# detect_format
# list_alis_pdl
# measure_alipdl
# measure_alipdl_fasta
# measure_alipdl_fasta_like
# measure_alipdl_uclust
# read_pdl                      Reads PDL format into $ali, in memory
# write_pdl                     Writes $ali into PDL raw format
# write_into_pdl                Writes type, title etc to *.info file

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub ali_exists
{
    # Niels Larsen, March 2006.

    # Returns true if a given alignment path exists on file. The given
    # path is a prefix and existence of files with .info and .pdl appended
    # are checked. 

    my ( $path
         ) = @_;

    # Returns 1 or nothing.

    if ( $path and -r "$path.pdl" and -r "$path.info" )
    {
        return 1;
    }
    else {
        return;
    }
}

sub connect_pdl
{
    # Niels Larsen, June 2005.

    # Creates an alignment object which is connected to a memory-mapped 
    # file, i.e. it is not loaded into memory. But when you use it as 
    # if it was, needed parts will be loaded. This is the routine to 
    # use when the alignment is large and just a small piece is needed.
    # It is also many times faster than "Ali::Common->read", as
    # it delays the reading until really needed. 

    my ( $path,        # Input file prefix or path
         $args,        # Parameters - OPTIONAL
         ) = @_;

    # Returns an alignment object. 

    my ( $ali, $prefix, $module, $type );

    $path = &Common::Names::strip_suffix( $path, '\.pdl$' );

    $args->{"copy"} = 0;
    $args->{"with_sids"} //= 1;
    $args->{"with_nums"} //= 1;

    $ali = &Ali::IO::read_pdl( $path, $args );

    return $ali;
}

sub count_alis
{
    # Niels Larsen, May 2011.

    # Counts alignments and sequences. In non-void context a hash is 
    # returned with these keys,
    #
    # ali_count               Number of alignments
    # seq_count               Number of sequences
    # seq_count_orig          Number or original sequences
    # 
    # The last count takes seq_count=nnn values from the header if 
    # present. In void that same information is printed to the console.

    my ( $file,
        ) = @_;

    # Returns hash or nothing.

    my ( $info, $stats, $format, $hdr_regex, $fh, $line, %seqs, @table, 
         $code, $has_counts, $seq_count_orig );

    $info = &Ali::IO::detect_file( $file );

    $format = $info->ali_format;
    $has_counts = $info->seq_counts;

    if ( $format =~ /^fasta|fasta_wrapped|uclust$/ )
    {
        if ( $format eq "uclust" )
        {
            if ( $has_counts ) {
                $hdr_regex = '(\d+)\|[^\|]+\|([^\n]+)';
            } else {
                $hdr_regex = '(\d+)';
            }                
        }
        else
        {
            if ( $has_counts ) {
                $hdr_regex = '([^:\s]+):([^\n]+)';
            } else {
                $hdr_regex = '([^:\s]+)';
            }                
        }
    }
    else {
        &error( qq (Unsupported format -> "$format") );
    }

    if ( $has_counts )
    {
        $code = q (
    while ( defined ( $line = <$fh> ) )
    {
        if ( $line =~ /^>/ and $line =~ /^>$hdr_regex/o )
        {
            $seqs{ $1 } += 1;
            $2 =~ /seq_count=(\d+)/ and $seq_count_orig += $1;
        }
    }
);
    }
    else
    {
        $code = q (
    while ( defined ( $line = <$fh> ) )
    {
        if ( $line =~ /^>/ and $line =~ /^>$hdr_regex/o )
        {
            $seqs{ $1 } += 1;
        }
    }
);
    }        

    $fh = &Common::File::get_read_handle( $file );

    eval $code;

    &Common::File::close_handle( $fh );

    $stats->{"ali_count"} = keys %seqs;
    $stats->{"seq_count"} = &List::Util::sum( values %seqs );
    $stats->{"seq_count_orig"} = $has_counts ? $seq_count_orig : undef;

    bless $stats;

    if ( not defined wantarray )
    {
        @table = (
            [ " Alignments:", &Common::Util::commify_number( $stats->{"ali_count"} ) ],
            [ "  Sequences:", &Common::Util::commify_number( $stats->{"seq_count"} ) ],
            );

        if ( $has_counts )
        {
            push @table, [ "   Original:", &Common::Util::commify_number( $stats->{"seq_count_orig"} ) ];
        }

        print "\n";
        print &Common::Tables::render_ascii( \@table );
        print "\n\n";
    }

    return wantarray ? %{ $stats } : $stats;
}

sub detect_file
{
    # Niels Larsen, March 2011.

    # Returns a hash with file path and size, id length, sequence format, 
    # record separator and header lead string. 

    my ( $file,    # Sequence file or handle
         $buflen,  # Buffer length - OPTIONAL, default 500
        ) = @_;

    # Returns a hash.

    my ( $stats, $buffer, $fh, @msgs, $format, $rec_sep, $hdr_str, 
         $id_len );

    $buflen //= 500;

    if ( ref $file ) {
        $fh = $file;
    } else {
        $fh = &Common::File::get_read_handle( $file );
    }
    
    read $fh, $buffer, $buflen;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> STOCKHOLM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $buffer =~ /^#\s+STOCKHOLM/ )
    {
        $format = "stockholm";
        $rec_sep = "\n//";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UCLUST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
    elsif ( $buffer =~ /^>\d+\|(\*|[0-9\.]+%)\|/ )
    {
        $format = "uclust";
        $rec_sep = "\n>";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    elsif ( $buffer =~ /^>/ )
    {
        if ( $buffer =~ /\n[^>]+\n[^>]+/ ) {
            $format = "fasta_wrapped";
        } else {
            $format = "fasta";
        }

        $rec_sep = "\n>";
    }
    else {
        &Common::File::close_handle( $fh ) if not ref $file;
        &error( qq (Unrecognized format -> "$buffer") );
    }
    
    &Common::File::close_handle( $fh ) if not ref $file;

    $stats = bless {
        "file_path" => $file,
        "file_size" => -s $file,
        "seq_counts" => $buffer =~ /seq_count=(\d+)/ ? 1 : 0,
        "ali_format" => $format,
        "rec_sep" => $rec_sep,
    };

    return wantarray ? %{ $stats } : $stats;
}

sub detect_files
{
    my ( $files,
        ) = @_;

    my ( $file, @stats );

    foreach $file ( @{ $files } )
    {
        push @stats, { &Ali::IO::detect_file( $file ) };
    }

    return wantarray ? @stats : \@stats;
}

sub detect_format
{
    # Niels Larsen, December 2011. 

    # Returns the format of a given alignment file. 

    my ( $file,
        ) = @_;

    return &Ali::IO::detect_file( $file )->ali_format;
}

sub list_alis_pdl
{
    # Niels Larsen, February 2007.

    # Lists the alignment files in a given directory.

    my ( $dir,           # Directory
         $expr,
         ) = @_;

    # Returns a list.

    my ( @files );

    if ( -d $dir ) {
        @files = &Common::File::list_pdls( $dir, $expr );
    } else {
        @files = ();
    }

    return wantarray ? @files : \@files;
}

sub measure_alipdl
{
    # Niels Larsen, April 2011. 

    # Counts the number of alignments and sequences in a given file. Creates 
    # list of objects, one for each alignment, with these keys and values,
    # 
    #  ali_id        Alignment id
    #  sid_cols      Length of the longest sequence id 
    #  dat_rows      Number of sequences
    #  dat_cols      Number of alignment columns
    #  beg_cols      Length of highest begin-number string
    #  end_cols      Length of highest end-number string
    # 
    # The formats access lengths . It is done by 
    # getting the number of lines with 'wc', then dividing by two or
    # four; wc is faster than the quickest perl way.

    my ( $file,
         $args,
        ) = @_;

    # Returns integer.

    my ( $defs, $format, $seq_min, $fh, $counts );

    $defs = {
        "format" => undef,
        "ignore" => [ "Pairingmask" ],
        "seq_min" => 2,
        "sid_regexp" => undef,
        "sid_fields" => undef,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    $seq_min = $args->seq_min;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GUESS FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not ( $format = $args->format ) )
    {
        $format = &Ali::IO::detect_format( $file );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $fh = &Common::File::get_read_handle( $file );

    if ( $format eq "uclust" )
    {
        $counts = &Ali::IO::measure_alipdl_uclust(
            $file,
            { 
                "seq_min" => $seq_min,
            });
    }
    elsif ( $format eq "fasta_wrapped" )
    {
        $counts = &Ali::IO::measure_alipdl_fasta(
            $file,
            {
                "seq_min" => $seq_min,
                "wrapped" => 1,
            });
    }
    elsif ( $format eq "fasta" )
    {
        $counts = &Ali::IO::measure_alipdl_fasta(
            $file,
            {
                "seq_min" => $seq_min,
                "wrapped" => 0,
            });
    }
    # elsif ( $format eq "stockholm" )
    # {
    #     $counts = &Ali::IO::measure_stockholm(
    #         $file,
    #         {
    #             "seq_min" => $seq_min,
    #         });
    # }
    else
    {
        &Common::File::close_handle( $fh );
        &error( qq (Unrecognized format -> "$format") );
    }

    &Common::File::close_handle( $fh );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    
#    $ali_total = scalar @{ $counts };
#    $seq_total = &List::Util::sum( map { $_->[1] } @{ $counts } );
#    $avg_idlen = &List::Util::sum( map { length $_->[0] } @{ $counts } ) / $ali_total;

#    $stats = {
#        "ali_num" => $ali_total,
#        "seq_num" => $seq_total,
#        "seq_idlen" => int $avg_idlen + 1,
#    };

    return wantarray ? @{ $counts } : $counts;
}

sub measure_alipdl_fasta
{
    # Niels Larsen, April 2011.

    # Creates a list of objects, one for each alignment, with keys for id and
    # dimensions. See &Ali::IO::measure_fasta_like for more. A minimum number
    # of sequences per alignment may be set, so smaller alignments are skipped. 

    my ( $file,       # Input fasta file name or handle
         $args,       # Arguments and switches
         ) = @_;

    # Returns a list.

    my ( $defs, $format, $counts, $wrapped );

    $defs = {
        "seq_min" => 2,
        "hdr_regexp" => '([^:]+):?(\S*)',
        "hdr_fields" => { "ali_id" => '$1', "seq_id" => '$2' },
        "wrapped" => undef,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    
    # Check to see if its single-line sequences, or they are wrapped; then 
    # collect info for all entries,

    if ( not defined ( $wrapped = $args->wrapped ) )
    {
        $format = &Ali::IO::detect_format( $file );

        if ( $format =~ /wrapped/ ) {
            $wrapped = 1;
        } else {
            $wrapped = 0;
        }
    }

    $counts = &Ali::IO::measure_alipdl_fasta_like(
        $file,
        {
            "seq_min" => $args->seq_min,
            "hdr_regexp" => $args->hdr_regexp,
            "hdr_fields" => $args->hdr_fields,
            "wrapped" => $wrapped,
        });

    return wantarray ? @{ $counts } : $counts;
}

sub measure_alipdl_fasta_like
{
    # Niels Larsen, September 2010.

    # Creates a list of objects, one for each alignment, with ids and dimensions.

    my ( $file,       # File path
         $args,       # Arguments 
        ) = @_;

    # Returns a list.
    
    my ( $defs, $seq, $fh, $ali_id, $seq_id, $ali_id_last, $seq_count, $seq_len,
         $seq_min, $sid_len, @counts, $routine, $hdr_exp, $hdr_fields, $hdr_vals );

    $defs = {
        "seq_min" => 2,
        "hdr_regexp" => undef,
        "hdr_fields" => {},
        "wrapped" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    $seq_min = $args->seq_min;
    $hdr_exp = $args->hdr_regexp;
    $hdr_fields = $args->hdr_fields;

    if ( $args->wrapped ) {
        $routine = "Seq::IO::read_seq_fasta_wrapped";
    } else {
        $routine = "Seq::IO::read_seq_fasta";
    }        

    no strict "refs";

    $fh = &Common::File::get_read_handle( $file );

    $ali_id_last = 0;
    $seq_count = 0;
    $seq_len = 0;
    $sid_len = 0;

    while ( $seq = &{ $routine }( $fh ) )
    {
        if ( $hdr_vals = &Common::Util::parse_string( $seq->{"id"}, $hdr_exp, $hdr_fields ) )
        {
            $ali_id = $hdr_vals->{"ali_id"} // "";
            $seq_id = $hdr_vals->{"seq_id"} // "";

            if ( $seq_id ne "") {
                $sid_len = &Common::Util::max( length $seq_id, $sid_len );
            } else {
                $sid_len = &Common::Util::max( length $ali_id, $sid_len );
            }

            if ( $ali_id ne $ali_id_last )
            {
                if ( $seq_count >= $seq_min )
                {
                    push @counts, bless
                    {
                        "ali_id" => $ali_id_last,
                        "sid_cols" => $sid_len,
                        "dat_rows" => $seq_count,
                        "dat_cols" => $seq_len,
                        "beg_cols" => 1,
                        "end_cols" => length ( sprintf "%i", $seq_len ),
                    };
                }
                
                $ali_id_last = $ali_id;

                $seq_count = 0;
                $seq_len = 0;
            }

            $seq_count += 1;
            $seq_len = &Common::Util::max( $seq_len, length $seq->{"seq"} );
        }
        else {
            &error( qq (Wrong looking header line -> ). $seq->{"id"} );
        }
        
    }

    if ( $seq_count >= $seq_min )
    {
        push @counts, bless
        {
            "ali_id" => $ali_id_last,
            "sid_cols" => $sid_len,
            "dat_rows" => $seq_count,
            "dat_cols" => $seq_len,
            "beg_cols" => 1,
            "end_cols" => length ( sprintf "%i", $seq_len ),
        };
    }

    &Common::File::close_handle( $fh );

    &dump( \@counts );
    return wantarray ? @counts : \@counts;
}

sub measure_alipdl_uclust
{
    # Niels Larsen, April 2011.

    # Creates a list of objects, one for each alignment, with keys for id and
    # dimensions. See &Ali::IO::measure_fasta_like for more. A minimum number
    # of sequences per alignment may be set, so smaller alignments are skipped. 

    my ( $file,       # File path
         $args,       # Arguments 
        ) = @_;

    # Returns a list.
    
    my ( $defs, $counts );

    $defs = {
        "seq_min" => 2,
        "hdr_regexp" => undef,
        "hdr_fields" => {},
        "wrapped" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    $counts = &Ali::IO::measure_alipdl_fasta_like(
        $file, 
        {
            "seq_min" => $args->seq_min // 2,
            "hdr_regexp" => '(\d+)\|[^\|]+\|(\S+)',
            "wrapped" => 0,
        });

    return wantarray ? @{ $counts } : $counts;
}

sub read_pdl
{
    # Niels Larsen, June 2005.
    
    # Returns an Ali::Common object, given an input file in raw format.
    # The object is optionally loaded into memory (default) or file bound.
    # Changes made to the memory alignment will not affect the alignment 
    # on file.

    my ( $path,         # Input path prefix
         $args,
         ) = @_;

    # Returns an alignment object. 

    my ( $ali, $info, $pdl, $maxcol, $key, $pdl_file, $beg_col, $end_col );

    $pdl_file = "$path.pdl";

    if ( -r $pdl_file )
    {
        # Each alignment has a raw PDL memory mapped file and a file with 
        # bookkeeping information,

        $info = &Common::File::retrieve_file( "$path.info" );

        $pdl = PDL->mapfraw( $pdl_file, $info->{"pdl_header"} );

        $beg_col = 0;

        # In the PDL file, some fields are optional, but the "meta" info 
        # tells which are there,

        if ( $info->{"sid_cols"} )            # Short-ids
        {
            if ( $args->{"with_sids"} ) 
            {
                $end_col = $beg_col + $info->{"sid_cols"} - 1;
                $ali->{"sids"} = $pdl->slice( "$beg_col:$end_col,:" );
            }

            $beg_col += $info->{"sid_cols"};
        }

        if ( $info->{"beg_cols"} )            # Begin-numbers
        {
            if ( $args->{"with_nums"} )
            {
                $end_col = $beg_col + $info->{"beg_cols"} - 1;
                $ali->{"begs"} = $pdl->slice( "$beg_col:$end_col,:" );
            }

            $beg_col += $info->{"beg_cols"};
        }

        if ( $info->{"end_cols"} )            # End-numbers 
        {
            if ( $args->{"with_nums"} )
            {
                $end_col = $beg_col + $info->{"end_cols"} - 1;
                $ali->{"ends"} = $pdl->slice( "$beg_col:$end_col,:" );
            }

            $beg_col += $info->{"end_cols"};
        }

        # Add bookkeeping info to alignment object, 

        $maxcol = $info->{"pdl_header"}->{"Dims"}->[0] - 1;
        $ali->{"seqs"} = $pdl->slice( "$beg_col:$maxcol,:" );

        foreach $key ( keys %{ $info } )
        {
            if ( $key ne "pdl_header" and $key ne "ignore" ) {
                $ali->{ $key } = $info->{ $key } || "";
            }
        }

        # Initialize object,

        $ali = Ali::Common->new( %{ $ali }, "file" => $pdl_file );
    }
    else {
        &error( qq (File is not readable -> "$pdl_file") );
    }

    return $ali;
}

sub write_pdl
{
    # Niels Larsen, June 2005.

    # Writes a given alignment to native "raw" format. This input alignment
    # may be in physical memory or be file-bound (which is done with 
    # the "Ali::Common->connect" routine). Returns the number of 
    # entries written. 

    my ( $ali,
         $opath,
         $args,
         ) = @_;

    # Returns an integer. 
    
    my ( $ofh, $rows, $row, $sid, $seq, $beg, $end, $file );

    $file = "$opath.pdl";

    ( undef, $rows ) = $ali->sids->dims;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ofh = &Common::File::get_write_handle( $file );
    binmode $ofh;

    for ( $row = 0; $row < $rows; $row++ )
    {
        $sid = $ali->sid_string( $row );
        $seq = $ali->seq_string( $row );
        $beg = $ali->beg_string( $row );
        $end = $ali->end_string( $row );

        $seq =~ s/~/ /g;

        $ofh->print( $sid . $beg . $end . $seq );
    }

    &Common::File::close_handle( $ofh );

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE "META" INFO <<<<<<<<<<<<<<<<<<<<<<<<<

    &Ali::IO::write_into_pdl( $ali, $opath );

    return $rows;
}

sub write_into_pdl
{
    # Niels Larsen, September 2005.

    # Writes all "meta" fields of an alignment object to a given separate
    # file. These fields include all but the short-ids and sequences. 

    my ( $ali,
         $opath,   # Output file path prefix
         $info,
         ) = @_;

    my ( $sid_cols, $dat_cols, $sid_rows, $seq_rows, $hash, 
         $key, %valid_keys, $beg_cols, $end_cols, $dat_rows );

    if ( not $info )
    {
        if ( not ref $ali ) {
            &error( qq (Must be called as instance method, or info hash given) );
        }

        ( $sid_cols, $sid_rows ) = $ali->sids->dims;

        if ( defined $ali->begs ) {
            ( $beg_cols, undef ) = $ali->begs->dims;
        } else {
            $beg_cols = 0;
        }

        if ( defined $ali->ends ) {
            ( $end_cols, undef ) = $ali->ends->dims;
        } else {
            $end_cols = 0;
        }

        ( $dat_cols, $seq_rows ) = $ali->seqs->dims;

        if ( $sid_rows == $seq_rows ) {
            $dat_rows = $seq_rows;
        } else {
            &error( qq (There are $sid_rows label rows, but $seq_rows data rows.) );
        }

        $info = {
            "sid_cols" => $sid_cols,
            "beg_cols" => $beg_cols,
            "end_cols" => $end_cols,
            "dat_cols" => $dat_cols,
            "dat_rows" => $dat_rows,
            "datatype" => $ali->datatype,
            "sid" => $ali->sid,
            "source" => $ali->source,
            "title" => $ali->title,
        };

        if ( $ali->pairmasks ) {
            $info->{"pairmasks"} = $ali->pairmasks;
        }
    }

    $hash->{"pdl_header"} = { 
        "Type" => "byte",
        "NDims" => 2, 
        "Dims" => [ $info->{"sid_cols"} + 
                    $info->{"beg_cols"} +
                    $info->{"end_cols"} +
                    $info->{"dat_cols"}, $info->{"dat_rows"} ],
    };

    %valid_keys = map { $_, 1 } @Ali::Common::Fields;

    foreach $key ( keys %{ $info } )
    {
        if ( $key !~ /^sids|begs|ends|seqs$/ and $valid_keys{ $key } ) {
            $hash->{ $key } = $info->{ $key };
        }
    }

    &Common::File::store_file( "$opath.info", $hash );

    return;
}

1;

__END__


    # # Filter out pairing mask entries,

    # @counts = grep { $_->[0] !~ /^Pairingmask/i } @counts;
    
    # if ( $args->{"ignore"} )
    # {
    #     $regexp = $args->{"ignore"};
    #     @counts = grep { $_->[0] !~ /$regexp/i } @counts;
    # }

    # $dat_cols = &List::Util::max( map { $_->[1] } @counts );
    # $dat_rows = scalar @counts;

    # if ( $args->{"split_sids"} )
    # {
    #     @splits = ();
    #     $regexp = $args->{"split_sids"};

    #     foreach $row ( @counts )
    #     {
    #         if ( $row->[0] =~ /$regexp/ ) {
    #             push @splits, [ $1, $2, $3 ];
    #         } else {
    #             push @splits, [ $row->[0], 0, 0 ];
    #         }
    #     }

    #     $sid_cols = &List::Util::max( map { length $_->[0] } @splits );
    #     $end_cols = &List::Util::max( map { length $_->[2] } @splits );
    #     $beg_cols = $end_cols;
    # }
    # else 
    # {
    #     $sid_cols = &List::Util::max( map { length $_->[0] } @counts );
    #     $end_cols = length $dat_cols;
    #     $beg_cols = $end_cols;
    # }

    # %counts = (
    #     "sid_cols" => $sid_cols,
    #     "dat_cols" => $dat_cols,
    #     "dat_rows" => $dat_rows,
    #     "beg_cols" => $beg_cols,
    #     "end_cols" => $end_cols,
    #     );
