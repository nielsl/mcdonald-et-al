package Seq::Patterns;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions that relate to patterns somehow.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use List::Util;
use Config::General;

use Common::Config;
use Common::Messages;

use Seq::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# patscan_to_locs
# patscan_to_locs_file

sub patscan_to_locs
{
    # Niels Larsen, January 2010.

    # Converts patscan output to a memory list of [ id, +/-, locators ].
    # The patscan output can be given either as list, a file handle or a 
    # file name. 

    my ( $from,
         $args,
        ) = @_;

    # Returns a two-element list reference or nothing.

    my ( $readbuf, $strflag, $seqflag, $lines, $i, $line, $id, $beg, $end, 
         @subseqs, $pos, @locs, $len, $subseq, $strand, @output, $elem );

    $readbuf = $args->{"readbuf"} // 10_000;
    $strflag = $args->{"strflag"} // 0;
    $seqflag = $args->{"seqflag"} // 0;

    if ( ref $from )
    {
        if ( ref $from eq "ARRAY" )
        {
            $lines = $from;
        }
        else
        {
            $i = 1;

            while ( $i <= $readbuf and defined ( $line = <$from> ) )
            {
                push @{ $lines }, $line;

                $line = <$from>;
                push @{ $lines }, $line;

                $i += 1;
            }
        }
    }
    else {
        $lines = &Common::File::read_lines( $from );
    }
    
    for ( $i = 0; $i <= $#{ $lines }; $i++ )
    {
        $line = $lines->[ $i ];

        chomp $line; 

        if ( $line =~ /^>(.+):\[(\d+),(\d+)\]$/ )
        {
            ( $id, $beg, $end ) = ( $1, $2-1, $3-1 );

            $line = $lines->[ ++$i ];
            $line =~ s/\s$//;

            # Pattern elements are strings (which can be empty) followed by a 
            # blank. Anchoring to end-of-sequence with $ seems to be a pattern
            # element too. Patscan indicates matches on the opposite strand by
            # listing the end position before the start; here we set a strand 
            # but keep increasing numbers that always refer to the given 
            # sequence,

            @subseqs = ();

            while ( $line =~ /(\S+)? /og )
            {
                push @subseqs, $1;
            }

            if ( $beg <= $end )
            {
                $pos = $beg;
                $strand = "+";
            }
            else 
            {
                $pos = $end;
                @subseqs = reverse @subseqs;
                $strand = "-";
            }

            # Create locator list as [ pos, len ] or undef,
            
            @locs = ();

            foreach $subseq ( @subseqs )
            {
                if ( $subseq )
                {
                    $len = length $subseq;
                    
                    push @locs, [ $pos, $len, $strand ];
                    $pos += $len;
                }
                else {
                    push @locs, undef;
                }
            }

            if ( $seqflag ) {
                push @output, [ $id, $strand, &Storable::dclone( \@locs ), &Storable::dclone( \@subseqs ) ];
            } else {
                push @output, [ $id, $strand, &Storable::dclone( \@locs ) ];
            }
        }
        else {
            &error( qq (Wrong looking line -> "$line") );
        }
    }

    if ( $strflag ) 
    {
        foreach $elem ( @output ) {
            $elem->[2] = ${ &Seq::Common::format_loc_str( $elem->[2] ) };
        }
    }

    return wantarray ? @output : \@output;
}

sub patscan_to_locs_file
{
    # Niels Larsen, October 2011. 
    
    # Same as patscan_to_locs, but uses input and output files instead of 
    # memory.

    my ( $args,
        ) = @_;

    my ( $ifile, $ofile, $strflag, $seqflag, $clobber, $ifh, $ofh, $i, $imax,
         $locs, $loc, $line, @lines, @locs );

    $| = 1;

    $ifile = $args->{"ifile"};
    $ofile = $args->{"ofile"};
    $strflag = $args->{"strings"} // 0;
    $seqflag = $args->{"withseq"} // 0;
    $clobber = $args->{"clobber"} // 0;
    
    $imax = 10_000;

    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( $ofile, "clobber" => $clobber );

    while ( 1 )
    {
        @lines = ();
        $i = 0;    

        while ( defined ( $line = <$ifh> ) )
        {
            push @lines, $line;
            
            $line = <$ifh>;
            push @lines, $line;

            $i += 1;

            last if $i >= $imax;
        }

        last if not @lines;

        $locs = &Seq::Patterns::patscan_to_locs( \@lines, {"strflag" => $strflag, "seqflag" => $seqflag });
        
        if ( $ofile )
        {
            @locs = &Seq::Common::format_locators( $locs );
            map { $ofh->print( "$_\n" ) } @locs;
        }
        else {
            push @locs, @{ $locs };
        }
    }

    &Common::File::close_handle( $ofh );
    &Common::File::close_handle( $ifh );
    
    if ( not $ofile ) {
        return wantarray ? @locs : \@locs;
    }

    return;
}

1;

__END__

# sub patscan_to_locs
# {
#     # Niels Larsen, January 2010.

#     # Converts patscan output to a list of [ id, strand, locators ].

#     my ( $lines,
#          $strflag,
#          $seqflag,
#         ) = @_;

#     # Returns a two-element list reference or nothing.

#     my ( $i, $line, $id, $beg, $end, @subseqs, $pos, @locs, $len, $subseq, 
#          $strand, @output, $elem );

#     $strflag //= 0;
#     $seqflag //= 0;

#     for ( $i = 0; $i <= $#{ $lines }; $i++ )
#     {
#         $line = $lines->[ $i ];

#         chomp $line; 

#         if ( $line =~ /^>(.+):\[(\d+),(\d+)\]$/ )
#         {
#             ( $id, $beg, $end ) = ( $1, $2-1, $3-1 );

#             $line = $lines->[ ++$i ];
#             $line =~ s/\s$//;

#             # Pattern elements are strings (which can be empty) followed by a 
#             # blank. Anchoring to end-of-sequence with $ seems to be a pattern
#             # element too. Patscan indicates matches on the opposite strand by
#             # listing the end position before the start; here we set a strand 
#             # but keep increasing numbers that always refer to the given 
#             # sequence,

#             @subseqs = ();

#             while ( $line =~ /(\S+)? /og )
#             {
#                 push @subseqs, $1;
#             }

#             &dump( \@subseqs );

#             if ( $beg <= $end )
#             {
#                 $pos = $beg;
#                 $strand = "+";
#             }
#             else 
#             {
#                 $pos = $end;
#                 @subseqs = reverse @subseqs;
#                 $strand = "-";
#             }

#             # Create locator list as [ pos, len ] or undef,
            
#             @locs = ();

#             foreach $subseq ( @subseqs )
#             {
#                 if ( $subseq )
#                 {
#                     $len = length $subseq;
                    
#                     push @locs, [ $pos, $len, $strand ];
#                     $pos += $len;
#                 }
#                 else {
#                     push @locs, undef;
#                 }
#             }

#             if ( $seqflag ) {
#                 push @output, [ $id, $strand, &Storable::dclone( \@locs ), &Storable::dclone( \@subseqs ) ];
#             } else {
#                 push @output, [ $id, $strand, &Storable::dclone( \@locs ) ];
#             }
#         }
#         else {
#             &error( qq (Wrong looking line -> "$line") );
#         }
#     }

#     &dump( \@output );
#     if ( $strflag ) 
#     {
#         foreach $elem ( @output ) {
#             $elem->[2] = ${ &Seq::Common::format_loc_str( $elem->[2] ) };
#         }
#     }

#     return wantarray ? @output : \@output;
# }

# sub create_patlib
# {
#     # Niels Larsen, October 2011.

#     my ( $args,
#         ) = @_;

#     my ( $prifile, $tagfile, $outfile, $pats, $name, $pat, $patstr, $tags,
#          $tag, %pats, $text, $fetch, $fh, $tagseq, $elems, $tagmis, %patlib,
#          %options );

#     # Read pattern file and get file arguments,

#     $prifile = $args->{"prifile"};
#     $tagfile = $args->{"tagfile"};
#     $tagmis = $args->{"tagmis"} // 0;
#     $outfile = $args->{"outfile"};

#     $pats = &Seq::IO::read_primer_patterns( $prifile );

#     $name = $pats->{"name"};

#     if ( $pats->{"fwd"} )
#     {
#         $pat = {};

#         $patstr = $pats->{"fwd"}->{"patstr"};
        
#         $pat->{"name"} = $name;
#         $pat->{"title"} = "$name (F)";
#         $pat->{"patstr"} = $patstr;
#         $pat->{"elems"} = scalar ( split " ", $patstr );
#         $pat->{"fetch"} = $pats->{"fwd"}->{"fetch"} // [];

#         $pats{"fwd"} = &Storable::dclone( $pat );
#     }

#     if ( $pats->{"rev"} )
#     {
#         $pat = {};
#         $patstr = $pats->{"rev"}->{"patstr"};

#         $pat->{"name"} = $name;
#         $pat->{"title"} = "$name (R)";
#         $pat->{"patstr"} = $patstr;
#         $pat->{"elems"} = scalar ( split " ", $patstr );
#         $pat->{"fetch"} = $pats->{"rev"}->{"fetch"} // [];
        
#         $pats{"rev"} = &Storable::dclone( $pat );
#     }

#     $text = "";

#     if ( $tagfile )
#     {
#         $tags = &Seq::IO::read_tag_table( $tagfile );

#         if ( $pats{"fwd"} )
#         {
#             foreach $tag ( @{ $tags } )
#             {
#                 if ( not $tagseq = $tag->{"ftag"} ) {
#                     $tagseq = $tag->{"rseq"};
#                 }

#                 $name = $tag->{"id"} // $tagseq;

#                 if ( $tagmis > 0 ) {
#                     $tagseq .= "[$tagmis,0,0]";
#                 }

#                 $patstr = $tagseq ." ". $pats{"fwd"}->{"patstr"};
#                 $fetch = join ",", map { $_ + 1 } @{ $pats{"fwd"}->{"fetch"} };
#                 $elems = $pats{"fwd"}->{"elems"} + 1;
                
#                 $text .= qq (
# <$name>
#      name = $name
#      orient = forward
#      title = $name (F)
#      patstr = $patstr
#      elems = $elems
#      fetch = $fetch
# </$name>
# );
#             }
#         }

#         if ( $pats{"rev"} )
#         {
#             foreach $tag ( @{ $tags } )
#             {
#                 if ( not $tagseq = $tag->{"rtag"} ) {
#                     $tagseq = $tag->{"ftag"};
#                 }

#                 $name = $tag->{"id"} // $tagseq;

#                 if ( $tagmis > 0 ) {
#                     $tagseq .= "[$tagmis,0,0]";
#                 }
                
#                 $patstr = $tagseq ." ". $pats{"rev"}->{"patstr"};
#                 $fetch = join ",", map { $_ + 1 } @{ $pats{"rev"}->{"fetch"} };
#                 $elems = $pats{"rev"}->{"elems"} + 1;
                
#                 $text .= qq (
# <$name>
#      name = $name
#      orient = reverse
#      title = $name (R)
#      patstr = $patstr
#      elems = $elems
#      fetch = $fetch
# </$name>
# );
#             }
#         }
#     }
#     else
#     {
#         if ( $pats{"fwd"} )
#         {
#             $pat = $pats{"fwd"};
#             $fetch = join ",", @{ $pats{"fwd"}->{"fetch"} };

#             $text .= qq (
# <$pat->{"name"}>
#      name = $pat->{"name"}
#      orient = forward
#      title = $pat->{"name"} (F)
#      patstr = $pat->{"patstr"}
#      elems = $pat->{"elems"}
#      fetch = $fetch
# </$pat->{"name"}>
# );
#         }

#         if ( $pats{"rev"} )
#         {
#             $pat = $pats{"rev"};
#             $fetch = join ",", @{ $pats{"rev"}->{"fetch"} };

#             $text .= qq (
# <$pat->{"name"}>
#      name = $pat->{"name"}
#      orient = reverse
#      title = $pat->{"name"} (R)
#      patstr = $pat->{"patstr"}
#      elems = $pat->{"elems"}
#      fetch = $fetch
# </$pat->{"name"}>
# );
#         }
#     }

#     $text .= "\n";

#     if ( $outfile )
#     {
#         &Common::File::write_file( $outfile, $text );
#     }
#     elsif ( defined wantarray )
#     {
#         %patlib = new Config::General( "-String" => $text )->getall;

#         return wantarray ? %patlib : \%patlib;
#     }
#     else {
#         print STDOUT $text;
#     }

#     return;
# }
