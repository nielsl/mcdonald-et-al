package Ali::Convert;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Alignment conversion related routines.
#
# convert_ali
# convert_ali_args
# convert_code
# get_ref_seq
# input_formats
# output_formats
# parse_loc_str
# scols_to_acols
# slice_ali
# slice_ali_args
# slice_code
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Time::Duration qw ( duration );

use Common::Config;
use Common::Messages;

use Ali::IO;
use Ali::Import;

use Seq::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub convert_ali
{
    # Niels Larsen, January 2011.
    
    # Converts from one alignment format to another. The read and write routines
    # from Ali::IO and so the supported formats are those for which there exists
    # Ali::IO::read_(inputformat) and Ali::IO::write_(outputformat) routines.

    my ( $args,             # Arguments hash
         $msgs,             # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns nothing.

    my ( $defs, $ifh, $ofh, $ali_count, $ifile, $ofile, $code, $single,
         $iname, $oname, %args, $clobber, $ifiles, $ofiles, $i, $deleted,
         $otmp, $ali, $seq, $conf );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifile" => undef,
        "iformat" => undef,
        "oformat" => "fasta",
        "ofile" => undef,
        "osuffix" => undef,
        "clobber" => 0,
        "degap" => 0,
        "numids" => 0,
        "upper" => 0,
        "lower" => 0,
        "t2u" => 0,
        "u2t" => 0,
        "stats" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Ali::Convert::convert_ali_args( $args );

    &dump( $conf );
    exit;


    # $Common::Messages::silent = $args->silent;

    # $single = $args->single;
    # $clobber = $args->clobber;

    # &echo_bold( qq (\nConverting:\n) );

    # $ifh = &Common::File::get_read_handle( $conf->ifile );
            
    # $ofile = $conf->ofile;

    # $oname = &File::Basename::basename( $ofile );
    # &echo( qq (   Writing $oname ... ) );

    # $otmp = &File::Basename::dirname( $ofile ) ."/.$oname";
    # &Common::File::delete_file_if_exists( $otmp );

    # $ofh = &Common::File::get_write_handle();

    # $read_sub = "Ali::IO::read_seqs_". $conf->iformat;
    # $convert_sub = eval &Ali::Convert::convert_code( $conf );
    # $write_sub = "Ali::IO::write_seqs_". $conf->oformat;
    
    # {
    #     no strict "refs";

    #     while ( $seqs = &{ $read_sub }( $ifh, $readbuf ) )
    #     {
    #         $counts->{"seqs_in"} += scalar @{ $seqs };

    #         $seqs = $filter_sub->( $seqs, $locs );

    #         &{ $write_sub }( $ofh, $seqs );

    #         $counts->{"seqs_out"} += scalar @{ $seqs };
    #     }
    # }
 

    # eval $code;
            
    # if ( $@ ) {
    #     &error( $@, "EVAL ERROR" );
    # }
    
    # $ifh->close;
    # $ofh->close;
    
    # &echo_done( "$ali_count alignment[s]\n" );

    # &echo_bold( "Finished\n\n" );

    # return;
}

sub convert_code
{
    # Niels Larsen, March 2011.

    # Returns a string with code that when eval'ed reads and writes
    # from input to output handles. 

    my ( $args,
        ) = @_;

    # Returns string.

    my ( $read_sub, $write_sub, $type_str, $code );
    
    $read_sub = "read_". $args->{"iformat"} ."_entry";
    $write_sub = "write_". $args->{"oformat"} ."_entry";
    $write_sub =~ s/1$//;

    $code = qq (

    while ( \$ali = &Ali::Import::$read_sub( \$ifh ) )
    {);

    if ( $args->{"numids"} )
    {
        $code .= q (
        $seq->{"id"} = $seq_count;);
    }

    if ( $args->{"upper"} )
    {
        $code .= q (
        &Seq::Common::uppercase( $seq ););
    }

    if ( $args->{"lower"} )
    {
        $code .= q (
        &Seq::Common::lowercase( $seq ););
    }

    if ( $args->{"t2u"} )
    {
        $code .= q (
        &Seq::Common::to_rna( $seq ););
    }

    if ( $args->{"u2t"} )
    {
        $code .= q (
        &Seq::Common::to_dna( $seq ););
    }

    $code .= qq (

        &Seq::IO::$write_sub( \$ofh, \$seq );

        \$ali_count += 1;
}
    );

    return $code;
}

sub convert_ali_args
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

    my ( @msgs, %args, $suffix );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->ifile ) {
	$args{"ifile"} = &Common::File::check_files([ $args->ifile ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", qq (Input file must be given) ];
    }
    
    if ( $args->osuffix and not $args->ofile ) {
        $args{"ofile"} = $args->ifile . $args->osuffix;
    } elsif ( $args->ofile ) {
        $args{"ofile"} = $args->ofile;
    } else {
        push @msgs, ["ERROR", qq (Either output file or suffix must be given) ];
    }

    $args{"iformat"} = &Seq::IO::detect_format( $args->ifile, \@msgs );

    &Common::File::check_files([ $args{"ofile"} ], "!e", \@msgs ) if not $args->clobber;

    $args{"oformat"} = &Seq::Args::check_name( $args->oformat, [ qw (fasta pdl) ], "output format", \@msgs );

    &append_or_exit( \@msgs, $msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}

sub input_formats
{
    my ( @list );

    @list = qw ( stockholm uclust afasta pdl );

    return wantarray ? @list : ( join ", ", @list );
}

sub output_formats
{
    my ( @list );

    @list = qw ( afastas pdl );

    return wantarray ? @list : ( join ", ", @list );
}

sub parse_loc_str
{
    # Niels Larsen, March 2012. 

    # Parses a string of the form '100-200,300-600' into 
    # 
    # [[99,101],[299,301]]
    #
    # where 1-based numbers become 0-based and ranges are converted to 
    # [ begin,length ] pairs. If an error list is given, then parse errors 
    # go there, otherwise fatal error. 
    
    my ( $str,
         $msgs,
        ) = @_;

    # Returns list.

    my ( $loc, @locs, @msgs );

    foreach $loc ( split /\s*,\s*/, $str, -1 )
    {
        if ( $loc =~ /^\s*(\d+)\s*-\s*(\d+)\s*$/o )
        {
            push @locs, [ $1 - 1, $2 - $1 + 1 ];
        }
        else {
            push @msgs, ["ERROR", qq (Wrong looking locator string -> "$loc") ];
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @locs : \@locs;
}

sub get_ref_seq
{
    # Niels Larsen, March 2012. 

    # Returns the first sequence whose id exactly matches the given id. 
    # The given alignment file is read until there is a match, error if 
    # no match.

    my ( $args,   # Arguments hash
         $msgs,   # Output error messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $fh, $seqs, $seq, @msgs, $routine, $readbuf, $seqid );
    
    $routine = "Seq::IO::read_seqs_". $args->{"format"};
    $readbuf = $args->{"readbuf"};
    $seqid = $args->{"seqid"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GET ID MATCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get the first sequence with an ID that exactly matches,
    
    if ( not ref ( $fh = $args->{"file"} ) ) {
        $fh = &Common::File::get_read_handle( $args->{"file"} );
    }

    {
        no strict "refs";

        while ( $seqs = &{ $routine }( $fh, $readbuf ) )
        {
            $seqs = &Seq::List::filter_id_match( $seqs, { $seqid => 1 } );
            
            if ( @{ $seqs } )
            {
                $seq = $seqs->[0];
                last;
            }
        }
    }
    
    &Common::File::close_handle( $fh ) unless ref $args->{"file"};

    if ( not $seq )
    {
        push @msgs, ["ERROR", qq (Reference sequence ID not found -> "$seqid") ];
        push @msgs, ["INFO", qq (It must exactly match one of the IDs in the given file) ];

        &echo("\n");
        &append_or_exit( \@msgs, $msgs );        
    }

    return $seq;
}

sub scols_to_acols
{
    # Niels Larsen, March 2012. 

    # Converts positions in a given reference sequence to alignment 
    # positions. The given alignment file is read until a sequence is 
    # reached with exact ID match, if not found it is an error. 

    my ( $seq, 
         $slocs,
         $msgs,
        ) = @_;

    my ( $sid, @alocs, $sloc, $sbeg, $send, $slen, $abeg, $aend, @msgs, 
         $seqstr );
    
    # Convert to alignment numbers, and return a list of locators in the same
    # format as the given one,

    $seqstr = $seq->{"seq"};

    foreach $sloc ( @{ $slocs } )
    {
        ( $sbeg, $slen ) = @{ $sloc };

        #&dump("sbeg = $sbeg");
        #&dump("slen = $slen");

        $abeg = &Seq::Common::spos_to_apos( $seq, $sbeg );
        $aend = &Seq::Common::spos_to_apos( $seq, $sbeg + $slen - 1 );

        #&dump("abeg = $abeg");
        #&dump("aend = $aend");

        if ( defined $abeg and defined $aend )
        {
            push @alocs, [ $abeg, $aend - $abeg + 1 ];
        }
        else 
        {
            if ( not defined $abeg ) {
                push @msgs, ["ERROR", qq (Begin position is off the end -> ) . ($sbeg + 1) ];
            }

            if ( not defined $aend ) {
                push @msgs, ["ERROR", qq (End position is off the end -> ) . ($sbeg + $slen) ];
            }
        }
    }

    if ( @msgs )
    {
        &echo("\n");
        &append_or_exit( \@msgs, $msgs );
    }

    return wantarray ? @alocs : \@alocs;
}
         
sub slice_ali
{
    # Niels Larsen, March 2012.
    
    # Extracts column ranges from a given fasta formatted alignment file. Ranges 
    # can be given by alignment indices or by sequence numbers if a reference
    # ID is given.

    my ( $args,             # Arguments hash
         $msgs,             # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns nothing.

    my ( $defs, $ifh, $ofh, $locs, $conf, $clobber, $readbuf, $seqs, $format,
         $ref_seq, $read_sub, $write_sub, $time_start, $counts, $sum, @msgs,
         $filter_sub, $minres, $sub_seqs );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifile" => undef,
        "ofile" => undef,
        "osuffix" => undef,
        "alicols" => undef,
        "seqcols" => undef,
        "seqid" => undef,
        "minres" => undef,
        "cover" => 1,
        "readbuf" => 1000,
        "degap" => 0,
        "upper" => 0,
        "lower" => 0,
        "t2u" => 0,
        "u2t" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Ali::Convert::slice_ali_args( $args );

    $Common::Messages::silent = $args->silent;

    $readbuf = $conf->readbuf;
    $format = $conf->format;

    &echo_bold( qq (\nSub-alignment:\n) );

    # >>>>>>>>>>>>>>>>>>>>>>> IF SEQUENCE COLUMNS ONLY <<<<<<<<<<<<<<<<<<<<<<<<

    # If only sequence positions and a reference id given, then these must be
    # converted to alignment positions. 

    if ( not $locs = $conf->alicols )
    {
        &echo("   Finding ". $conf->seqid ." ... ");

        $ref_seq = &Ali::Convert::get_ref_seq(
            {
                "file" => $conf->ifile,
                "readbuf" => $readbuf,
                "seqid" => $conf->seqid,
                "format" => $format,
            });

        &echo_done("found\n");

        &echo("   Getting column numbers ... ");

        $locs = &Ali::Convert::scols_to_acols( $ref_seq, $conf->seqcols );
        $conf->alicols( $locs );

        &echo_done("done\n");
    }

    $sum = &List::Util::sum( map { $_->[1] } @{ $locs } );
    &echo("   Alignment columns ... "); &echo_done( "$sum\n" );
    
    if ( ( $minres = $conf->minres ) > $sum )
    {
        push @msgs, ["ERROR", qq (Number of required residues ($minres) exceeds number of alignment columns ($sum)) ];
        &echo("\n");
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>> READ AND FILTER AND WRITE <<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Getting sub-sequences ... ");

    $read_sub = "Seq::IO::read_seqs_$format";

    $filter_sub = eval &Ali::Convert::slice_code( $conf );
    if ( $@ ) { &error( $@ ) };

    $format =~ s/_wrapped//;
    $write_sub = "Seq::IO::write_seqs_$format";

    $time_start = &Common::Messages::time_start();

    $ifh = &Common::File::get_read_handle( $conf->ifile );

    &Common::File::delete_file_if_exists( $conf->ofile ) if $conf->ofile and $args->clobber;
    
    if ( $conf->append ) {
        $ofh = &Common::File::get_append_handle( $conf->ofile );
    } else {
        $ofh = &Common::File::get_write_handle( $conf->ofile );
    }

    {
        no strict "refs";

        while ( $seqs = &Seq::IO::read_seqs_fasta_wrapped( $ifh, $readbuf ) )
        {
            $counts->{"seqs_in"} += scalar @{ $seqs };

            $sub_seqs = $filter_sub->( $seqs, $locs );

            &{ $write_sub }( $ofh, $sub_seqs );

            $counts->{"seqs_out"} += scalar @{ $sub_seqs };
        }
    }

    &Common::File::close_handle( $ofh );
    &Common::File::close_handle( $ifh );

    &echo_done("done\n");

    &echo("   Sequences read: "); &echo_done( $counts->{"seqs_in"} ."\n" );
    &echo("   Sequences written: "); 

    if ( $counts->{"seqs_out"} > 0 ) {
        &echo_done( $counts->{"seqs_out"} ."\n" );
    } else {
        &echo_red("NONE\n");
        &Common::File::delete_file_if_exists( $conf->ofile ) if $conf->ofile;
    }

    &echo("   Time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );

    &echo_bold( qq (Finished\n\n) );

    return;
}

sub slice_ali_args
{
    # Niels Larsen, March 2012. 

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, $suffix, $pct, $cols );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->ifile ) {
	$args{"ifile"} = &Common::File::check_files([ $args->ifile ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", qq (Input file must be given) ];
    }

    $args{"ofile"} = undef;

    if ( $args->osuffix and not $args->ofile ) {
        $args{"ofile"} = $args->ifile . $args->osuffix;
    } elsif ( $args->ofile ) {
        $args{"ofile"} = $args->ofile;
    }

    &append_or_exit( \@msgs, $msgs );

    $args{"format"} = &Seq::IO::detect_format( $args->ifile, \@msgs );

    if ( $args{"ofile"} ) {
        &Common::File::check_files([ $args{"ofile"} ], "!e", \@msgs ) if not $args->clobber and not $args->append;
    }

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RANGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->alicols ) {
        $args{"alicols"} = &Ali::Convert::parse_loc_str( $args->alicols, \@msgs );
    } else {
        $args{"alicols"} = undef;
    }

    if ( $args->seqcols )
    {
        $args{"seqcols"} = &Ali::Convert::parse_loc_str( $args->seqcols, \@msgs );

        if ( grep { $_->[1] < 0 } @{ $args{"seqcols"} } ) {
            push @msgs, ["ERROR", qq (All end positions must be higher than start positions) ];
        }
        
        if ( not $args{"seqid"} = $args->seqid ) {
            push @msgs, ["ERROR", qq (A reference sequence ID must be given) ];
        }
    }
    else {
        $args{"seqcols"} = undef;
    }
    
    if ( not $args{"alicols"} and not $args{"seqcols"} ) {
        push @msgs, ["ERROR", qq (Either alignment or sequence positions must be given) ];
    }

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> NUMBERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->minres ) {
        $args{"minres"} = &Registry::Args::check_number( $args->minres, 1, undef, \@msgs );
    } else {
        $args{"minres"} = 1;
    }

    if ( $cols = $args{"seqcols"} ) {
        $args{"minres"} = &List::Util::min( $args{"minres"}, $cols->[-1]->[0] + $cols->[-1]->[1] - $cols->[0]->[0] );
    }

    $args{"readbuf"} = &Registry::Args::check_number( $args->readbuf, 1, undef, \@msgs );

    $args{"cover"} = $args->cover;
    $args{"degap"} = $args->degap;
    $args{"upper"} = $args->upper;
    $args{"lower"} = $args->lower;
    $args{"t2u"} = $args->t2u;
    $args{"u2t"} = $args->u2t;
    $args{"append"} = $args->append;

    bless \%args;

    return wantarray ? %args : \%args;
}

sub slice_code
{
    # Niels Larsen, March 2012.

    # Creates code text for a routine that includes steps that depend
    # on the argument switches. 

    my ( $conf,   # Argument hash
        ) = @_;

    # Returns a string.

    my ( $minres, $code, $regex );

    $conf //= {};

    $minres = $conf->{"minres"};
    
    $code = q (
sub
{ 
    my ( $seqs,
         $locs,
        ) = @_;

    my ( $beglen, $endpos, $oseqs, $oseq, $seq );
);

    # Create substrings. In "cover" mode there must be characters on both 
    # sides of the excised strings,

    if ( $conf->{"cover"} )
    {
        $code .= q (
    $beglen = $locs->[0]->[0];
    $endpos = $locs->[-1]->[0] + $locs->[-1]->[1];

    $oseqs = [];

    foreach $seq ( @{ $seqs } )
    {
        if ( ( substr $seq->{"seq"}, 0, $beglen ) =~ /[A-Za-z]/o and 
             ( substr $seq->{"seq"}, $endpos ) =~ /[A-Za-z]/o )
        {
             push @{ $oseqs }, &Seq::Common::sub_seq( $seq, $locs );
        }
    }
);
    }
    else
    {
        $code .= q (
    $oseqs = [ map { &Seq::Common::sub_seq( $_, $locs ) } @{ $seqs } ];
);
    }

    if ( $conf->{"degap"} )
    {
        $code .= qq (
    \$oseqs = &Seq::List::delete_gaps( \$oseqs );
);
    }

    if ( $conf->{"minres"} )
    {
        if ( $conf->{"degap"} ) {
            $code .= qq (
    \$oseqs = [ grep { length \$_->{"seq"} >= $minres } \@{ \$oseqs } ];
);
        } else {
            $code .= qq (
    \$oseqs = [ grep { \$_->{"seq"} =~ tr/[A-Za-z]/[A-Za-z]/ >= $minres } \@{ \$oseqs } ];
);
        }
    }

    if ( $conf->{"upper"} ) 
    {
        $code .= q (
    $oseqs = &Seq::List::change_to_uppercase( $oseqs );
);
    }

    if ( $conf->{"lower"} ) 
    {
        $code .= q (
    $oseqs = &Seq::List::change_to_lowercase( $oseqs );
);
    }

    if ( $conf->{"t2u"} ) 
    {
        $code .= q (
    $oseqs = &Seq::List::change_to_rna( $oseqs );
);
    }

    if ( $conf->{"u2t"} ) 
    {
        $code .= q (
    $oseqs = &Seq::List::change_to_dna( $oseqs );
);
    }

    if ( $regex = $conf->{"annot"} )
    {
        $code .= qq (
    \$oseqs = [ grep { \$_->{"info"} =~ /$regex/ } \@{ \$oseqs } ];
);
    }

    $code .= q (
);

    $code .= q (
    return $oseqs;
}
);

    return $code;
}

1;

__END__
