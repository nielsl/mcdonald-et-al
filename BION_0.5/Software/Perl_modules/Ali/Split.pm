package Ali::Split;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that convert sequences or are related to such.
#
# formats
# process_args
# split_alis
# split_fasta
# split_fasta_like
# split_stockholm
# split_stockholm_like
# split_uclust
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use Ali::IO;
use Seq::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub formats
{
    # Niels Larsen, January 2011.
    
    # Returns a list of supported split formats, as a list in list context 
    # and a comma-string in scalar context.

    # Returns a list or string.

    my ( @list );

    @list = qw ( stockholm uclust fasta );

    return wantarray ? @list : join ", ", @list;
}

sub process_args
{
    # Niels Larsen, January 2011.

    # Checks and expands the match routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, @formats, @ids, $idstr );

    @msgs = ();

    # Input files must be readable,

    if ( defined $args->files and @{ $args->files } ) {
	$args{"ifiles"} = &Common::File::check_files( $args->files, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No input alignment files given) ];
    }

    # Format,

    @formats = &Ali::Split::formats();

    $args{"iformat"} = &Seq::Args::check_name( $args->format, \@formats, "input format", \@msgs );
    $args{"oformat"} = $args{"iformat"};

    # Minimum and maximum size,

    $args{"minsize"} = &Registry::Args::check_number( $args->minsize, 1, undef, \@msgs );

    if ( defined $args->maxsize ) {
        $args{"maxsize"} = &Registry::Args::check_number( $args->maxsize, 1, undef, \@msgs );
    } else {
        $args{"maxsize"} = undef;
    }

    # Output directory,

    if ( defined $args->odir ) {
        &Common::File::check_files( [ $args->odir ], "d", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (An output directory must be given) ];
    }

    # Output suffix,

    if ( defined $args->osuffix ) {
        $args{"osuffix"} = $args->osuffix;
    } else {
        $args{"osuffix"} = $args{"oformat"};
    }

    # Skip ids,

    if ( defined ( $idstr = $args->skipids ) )
    {
        if ( -r $idstr ) {
            @ids = &Common::File::read_ids( $idstr );
        } else {
            @ids = split /\s*[, ]\s*/, $idstr;
        }

        @ids = grep /\w/, @ids;

        $args{"skipids"} = \@ids;
    }
    
    if ( @msgs ) {
        &append_or_exit( \@msgs, $msgs );
    }
    
    return wantarray ? %args : \%args;
}

sub split_alis
{
    # Niels Larsen, January 2011.
    
    # Splits one or more alignments into single-alignment files while keeping 
    # the format. The split routines are from Ali::IO and the supported formats
    # are those for which there exists Ali::IO->split_(inputformat) routines.

    my ( $args,             # Arguments hash
         $msgs,             # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns nothing.

    my ( $defs, $routine, %args, $ifile, $iname, $i, @paths, 
         $format, $suffix, $count, $str );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "files" => [],
        "format" => undef,
        "odir" => undef,
        "osuffix" => undef,
        "minsize" => 1,
        "maxsize" => undef,
        "skipids" => undef,
        "numids" => 0,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    %args = &Ali::Split::process_args( $args );

    $Common::Messages::silent = $args->silent;

    $format = $args{"oformat"};

    $suffix = $args{"osuffix"};
    $suffix = ".$suffix" if $args{"osuffix"} =~ /^\w/;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nSplitting $format:\n) );

    $routine = "Ali::Split::split_$format";

    for ( $i = 0; $i <= $#{ $args{"ifiles"} }; $i++ )
    {
        $ifile = $args{"ifiles"}->[$i];

        $iname = &File::Basename::basename( $ifile );
        &echo( qq (   Splitting $iname ... ) );

        no strict "refs";

        @paths = &{ $routine }(
            $ifile,
            {
                "odir" => $args->odir,
                "osuffix" => $suffix,
                "minsize" => $args->minsize,
                "maxsize" => $args->maxsize,
                "skipids" => $args{"skipids"},
                "clobber" => $args->clobber,
            },
            $msgs );
        
        $count = scalar @paths;
        $str = &Common::Util::commify_number( $count );

        if ( $count > 1 ) {
            $str = "$count outputs";
        } elsif ( $count == 0 ) {
            $str = "no outputs";
        } else {
            $str = "1 output";
        }

        &echo_green( "$str\n" );
    }
    
    &echo_bold( "Finished\n\n" );

    return;
}

sub split_fasta
{
    # Niels Larsen, January 2011.

    # Splits a given multi-fasta alignment file into single-alignment files
    # in a given directory. These new files are named "id+suffix" where suffix 
    # is ".fasta by default. No checking of existing output is done. As 
    # options, only alignments with more than a given number are written, 
    # and a list of IDs to avoid can also be given. Returns a list of 
    # output paths written.

    my ( $file,        # Input file
         $args,        # Arguments hash
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $defs );

    $defs = {
        "odir" => undef,
        "osuffix" => ".fasta",
        "minsize" => 1,
        "maxsize" => undef,
        "skipids" => [],
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    return &Ali::Split::split_fasta_like(
        $file, 
        {
            "odir" => $args->odir,
            "idexpr" => '>([^ ]+)',
            "osuffix" => $args->osuffix,
            "minsize" => $args->minsize,
            "maxsize" => $args->maxsize,
            "skipids" => $args->skipids,
            "clobber" => $args->clobber,
        }, 
        $msgs );
}

sub split_fasta_like
{
    # Niels Larsen, January 2011.

    # Splits a given fasta-like alignment file into single-alignment files in 
    # a given directory. These new files are named "id+suffix" where suffix 
    # must be given. Also given is a header regex, used to check for misreads
    # and format problems. No checking of existing output is done. As options,
    # only alignments with more than a given number are written, and a list 
    # of IDs to avoid can also be given. Returns a list of output paths written.

    my ( $file,        # Input file
         $args,        # Arguments hash
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.
    
    my ( $defs, $ali_id_old, $ali_id, $ifh, $minsize, $odir, $hdr_line, 
         $seq_line, $count, $osuffix, $clobber, $ofile, @msgs, @paths, $ofh, 
         %skipids, %ofiles, %counts, $regexp, $maxsize );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "odir" => undef,
        "idexpr" => undef,
        "osuffix" => ".cluali",
        "minsize" => 1,
        "maxsize" => undef,
        "skipids" => [],
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $odir = $args->odir;
    $regexp = $args->idexpr;
    $minsize = $args->minsize;
    $maxsize = $args->maxsize;
    $osuffix = $args->osuffix;
    $clobber = $args->clobber;
    
    %skipids = ();
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SKIP BY NAME <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Create a hash of the ids given by the user that are to be skipped,

    if ( @{ $args->skipids } )
    {
        map { $skipids{ $_ } = 1 } @{ $args->skipids };
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SKIP BY SIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Find ids of alignments that have too few or too many rows, by reading 
    # through it and get counts, and then adding ids to %skipids,
    
    if ( $minsize > 1 or defined $maxsize )
    {
        $ifh = &Common::File::get_read_handle( $file );

        while ( defined ( $hdr_line = <$ifh> ) )
        {
            if ( $hdr_line =~ /^$regexp/o )
            {
                $counts{ $1 } += 1;
                $seq_line = <$ifh>;
            }
            else {
                chomp $hdr_line;
                &error( qq (Wrong looking line -> "$hdr_line") );
            }
        }

        $ifh->close;
    }

    if ( $minsize > 1 ) 
    {
        foreach $ali_id ( keys %counts )
        {
            $skipids{ $ali_id } = 1 if $counts{ $ali_id } < $minsize;
        }
    }

    if ( defined $maxsize ) 
    {
        foreach $ali_id ( keys %counts )
        {
            $skipids{ $ali_id } = 1 if $counts{ $ali_id } > $maxsize;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> EXISTING FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a hash of existing output files to check against (faster than 
    # checking each time),

    %ofiles = map { $_->{"path"}, 1 } @{ &Common::File::list_files( $odir ) };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SPLIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read the uclust alignment format while skipping ids if any to be skipped,

    $ali_id_old = "";
    
    $ifh = &Common::File::get_read_handle( $file );

    while ( defined ( $hdr_line = <$ifh> ) )
    {
        # Read sequence line,
        
        $seq_line = <$ifh>;

        # Check header line format,
            
        if ( $hdr_line =~ /^$regexp/o )
        {
            $ali_id = $1;
            
            # Keep skipping ids up to the next header line that should not be 
            # skipped,

            while ( $skipids{ $ali_id } )
            {
                $hdr_line = <$ifh>;
                $seq_line = <$ifh>;
                
                goto END if not defined $seq_line;
                
                if ( $hdr_line =~ /^$regexp/ )
                {
                    $ali_id = $1;
                }
                else {
                    chomp $hdr_line;
                    &error( qq (Wrong looking line -> "$hdr_line") );
                }
            }

            # If newly read ID is new, then reopen output handle to a new file,
            # and set the new ID to the current one,

            if ( $ali_id ne $ali_id_old )
            {
                $ofh->close if defined $ofh;
                $ofile = "$odir/$ali_id$osuffix";
                
                if ( exists $ofiles{ $ofile } and not $clobber )
                {
                    &append_or_exit(
                         [
                          ["ERROR", qq (Output exists -> "$ofile") ],
                          ["ERROR", qq (Incompletely written. The --clobber option overwrites.) ],
                         ], undef, "newlines" => 1,
                        );
                }
                elsif ( not $skipids{ $ali_id } )
                {
                    $ofh = &Common::File::get_write_handle( $ofile, "clobber" => $clobber );
                    push @paths, $ofile;
                }
                
                $ali_id_old = $ali_id;
            }
            
            # Write output,
            
            $ofh->print( $hdr_line );
            $ofh->print( $seq_line );
        }
        else {
            chomp $hdr_line;
            &error( qq (Wrong looking line -> "$hdr_line") );
        }
    }

  END:
    
    $ifh->close;
    $ofh->close if defined $ofh;

    return wantarray ? @paths : \@paths;
}

sub split_stockholm
{
    # Niels Larsen, January 2011.

    # Splits a given stockholm formatted alignment file into single-alignment
    # files in a given directory. Returns a list of output paths.

    my ( $file,        # Input file
         $args,        # Arguments hash
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $defs, @paths );

    $defs = {
        "odir" => undef,
        "osuffix" => undef,
        "minsize" => 1,
        "maxsize" => undef,
        "skipids" => [],
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    @paths = &Ali::Split::split_stockholm_like(
        $file,
        {
            "odir" => $args->odir,
            "osuffix" => $args->osuffix,
            "idexpr" => '^#=GF ID\s+(\S+)',
            "minsize" => $args->minsize,
            "maxsize" => $args->maxsize,
            "skipids" => $args->skipids,
            "clobber" => $args->clobber,
        }, $msgs );

    return wantarray ? @paths : \@paths;
}

sub split_stockholm_like
{
    # Niels Larsen, January 2011.
    
    # Splits a given stockholm formatted alignment file into single-alignment
    # files in a given directory. These new files are named "id+suffix" where
    # suffix is ".stockholm by default. No checking of existing output is done.
    # As options, only alignments with at least the given number of rows are 
    # written, and a list of IDs to avoid can also be given. Returns a list of 
    # output paths written.

    my ( $file,        # Input file
         $args,        # Arguments hash
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $defs, $ifh, @lines, $line, $regexp, $odir, @ofiles, $suffix, 
         $ofile, $ofh, %skipids, $id, $ali_id, $clobber, @msgs, $minsize, $maxsize,
         %ofiles, %counts );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "odir" => undef,
        "osuffix" => undef,
        "minsize" => 1,
        "maxsize" => undef,
        "idexpr" => undef,
        "skipids" => [],
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $odir = $args->odir;
    $suffix = $args->osuffix;
    $regexp = $args->idexpr;
    $minsize = $args->minsize;
    $maxsize = $args->maxsize;
    $clobber = $args->clobber;

    %skipids = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SKIP BY NAME <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a hash of the ids given by the user that are to be skipped,

    if ( $args->skipids )
    {
        map { $skipids{ $_ } = 1 } @{ $args->skipids };
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SKIP BY SIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Find ids of alignments that have too few or too many rows, by reading 
    # through it and get counts, and then adding ids to %skipids,
    
    if ( $minsize > 1 or defined $maxsize )
    {
        $ifh = &Common::File::get_read_handle( $file );
        
        while ( defined ( $line = <$ifh> ) )
        {
            if ( $line =~ /^# STOCKHOLM/ ) {
                $ali_id = undef;
            } elsif ( $line =~ /^$regexp/o ) {
                $ali_id = $1;
            } elsif ( $line =~ /^#=GF +SQ +(\d+)/o ) {
                $counts{ $ali_id } = $1;
            }
        }

        $ifh->close;
    }

    if ( $minsize > 1 )
    {
        foreach $ali_id ( keys %counts ) {
            $skipids{ $ali_id } = 1 if $counts{ $ali_id } < $minsize;
        }
    }

    if ( defined $maxsize ) 
    {
        foreach $ali_id ( keys %counts ) {
            $skipids{ $ali_id } = 1 if $counts{ $ali_id } > $maxsize;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> EXISTING FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a hash of existing output files to check against (faster than 
    # checking each time),

    %ofiles = map { $_->{"path"}, 1 } @{ &Common::File::list_files( $odir ) };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SPLIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read the alignment while skipping ids if any,

    $ifh = &Common::File::get_read_handle( $file );

    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ /^# STOCKHOLM/ )
        {
            @lines = ( $line );

            while ( defined ( $line = <$ifh> ) and $line !~ /$regexp/ )
            {
                push @lines, $line;
            }

            if ( $line =~ /$regexp/ ) 
            {
                $id = $1;

                if ( $skipids{ $id } )
                {
                    while ( defined ( $line = <$ifh> ) and $line !~ /^\/\// ) {};
                }
                else
                {
                    $ofile = "$odir/$id$suffix";

                    if ( $clobber or not -e $ofile ) 
                    {
                        $ofh = &Common::File::get_write_handle( $ofile, "clobber" => $clobber );
                        
                        $ofh->print( @lines, $line );
                        
                        while ( defined ( $line = <$ifh> ) and $line !~ /^\/\// )
                        {
                            $ofh->print( $line );
                        }
                        
                        $ofh->print( $line );
                        $ofh->close;
                        
                        push @ofiles, $ofile;
                    }
                    else {
                        push @msgs, ["ERROR", qq (Output exists -> "$ofile") ];
                    }
                }
            }
            else {
                &error( qq (ID expression did not match entry) );
            }

        }
    }

    $ifh->close;

    &append_or_exit( \@msgs, $msgs, "newlines" => 1 );

    return wantarray ? @ofiles : \@ofiles;    
}

sub split_uclust
{
    # Niels Larsen, January 2011.

    # Splits a given uclust alignment file into single-alignment files in 
    # a given directory. These new files are named "id+suffix" where suffix 
    # is ".cluali by default. No checking of existing output is done. As 
    # options, only alignments with at least a given number of rows are 
    # written, and a list of IDs to avoid can also be given. Returns a 
    # list of output paths written.

    my ( $file,        # Input file
         $args,        # Arguments hash
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $defs );

    $defs = {
        "odir" => undef,
        "osuffix" => ".cluali",
        "minsize" => 1,
        "skipids" => [],
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    return &Ali::Split::split_fasta_like(
        $file, 
        {
            "odir" => $args->odir,
            "idexpr" => '>(\d+)\|[^\|]+\|(.+)',
            "osuffix" => $args->osuffix,
            "minsize" => $args->minsize,
            "skipids" => $args->skipids,
            "clobber" => $args->clobber,
        }, 
        $msgs );
}

1;

__END__

