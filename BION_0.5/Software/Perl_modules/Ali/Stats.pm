package Ali::Stats;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Module that does statistics, consenses, matrices, and such.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use feature "state";
use Fcntl qw ( SEEK_SET SEEK_CUR SEEK_END );

use Storable qw ( dclone );
use File::Basename;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Names;
use Common::Types;

use Registry::Args;
use Registry::Check;

use Ali::Common;
use Ali::IO;
use Ali::Storage;

use Seq::Args;
use Seq::IO;
use Seq::Stats;

our ( @Functions );

@Functions = (
    [ "col_stats",               "Column statistics from alignment object" ],
    [ "col_stats_pdl",           "Column statistics from a single-alignment PDL file" ],
    [ "col_stats_qual",          "Column statistics from alignment object with qualities" ],
    [ "encode_stats",            "Converts character counts to statistics" ],
    [ "process_args",            "Checks arguments and exits if error" ],
    [ "qual_dict",               "Creates hash with quality character keys and percent values" ],
    [ "splice_stats",            "Remove positions with too few residues" ],
    [ "stats_indices",           "Creates hash that maps sequence characters to indices" ],
    );
    
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub col_stats
{
    # Niels Larsen, May 2011.
    
    # Returns column statistics for a given alignment. No filtering is done.
    # The alignment must have the fields seqs, sids and datatype set, and its
    # sequence row strings must have the exact same length. It uses substr,
    # but doing it all in C would be much faster. An object is returned with 
    # these keys,
    # 
    #  col_stats          2d statistics (cols x 8)
    #  col_count          Number of alignment columns
    #  row_count          Number of alignment rows
    #  seq_count          Number of sequences (adds up seq_count=nn info)

    my ( $ali,         # Alignment object, handle or file
         ) = @_;

    # Returns object.

    my ( $seqs, $seq_counts, $maxcol, $maxrow, $stats, $col_stat, @col_stats,
         $row, $col, $colstr, $hist, $info, $totcol, $totrow, $seq_total,
         $seq_type );

    $seq_type = $ali->datatype;
    
    $seqs = $ali->{"seqs"};
    $info = $ali->{"info"};

    $totcol = length $seqs->[0];
    $maxcol = $totcol - 1;

    $totrow = scalar @{ $seqs };
    $maxrow = $totrow - 1;

    state $indices = &Ali::Stats::stats_indices( $seq_type );
    state $stat_size = &Common::Types::is_protein( $seq_type ) ? 24 : 8;

    # Initialize sequence counts and sequence total; they are used below to 
    # increment column counts with,

    if ( defined $info )
    {
        for ( $row = 0; $row <= $#{ $info }; $row ++ )
        {
            if ( $info->[$row] =~ /seq_count=(\d+)/ ) {
                $seq_counts->[$row] = $1;
            } else {
                $seq_counts->[$row] = 1;
            }
        }

        $seq_total = &List::Util::sum( @{ $seq_counts } );
    }
    else
    {
        $seq_counts = [ (1) x $totrow ];
        $seq_total = $totrow;
    }

    # Go through the alignment column by column, adding up the sequence and gap
    # counts for each row in a given column,

    for ( $col = 0; $col <= $maxcol; $col ++ )
    {
        $col_stat = [ ( 0 ) x $stat_size ];
        
        for ( $row = 0; $row <= $maxrow; $row ++ )
        {
            $col_stat->[ $indices->{ substr $seqs->[$row], $col, 1 } ] += $seq_counts->[$row];
        }

        push @col_stats, $col_stat;
    }

    $stats = bless {
        "col_stats" => \@col_stats,
        "seq_count" => $seq_total,
        "row_count" => $totrow,
        "col_count" => $totcol,
    };

    return wantarray ? %{ $stats } : $stats;
}

sub col_stats_pdl
{
    # Niels Larsen, September 2010.

    # Creates column statistics from a PDL alignment file. It does not read the 
    # entire alignment into memory, but reconnects to it while accumulating 
    # the statistics. Use this if there is a really large file. Quite slow
    # routine, maybe there is a better PDL way.

    my ( $path,         # Alignment file path prefix
         $args,
         ) = @_;

    # Returns a 2D PDL array. 

    my ( $defs, $maxcol, $maxrow, $counts, $ones, $pdl, $rowincr, $begrow, 
         $endrow, $row, $col, $stats, $ali, $ali_id, $seq_type );

    $defs = {
        "seq_type" => "dna_seq",
        "seq_min" => 1,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    # Create character counts, folded into a small vector below,

    $ali = &Ali::IO::connect_pdl( $path );
    
    if ( not ( $seq_type = $args->seq_type ) ) {
        $seq_type = $ali->datatype;
    }
    
    $maxrow = $ali->max_row;
    $maxcol = $ali->max_col;
    
    return if $args->seq_min > ( $maxrow + 1 );

    $counts = PDL->zeroes( 128, $maxcol + 1 );
    $ones = PDL->ones( $maxcol + 1 );

    $begrow = 0;    
    $rowincr = &List::Util::max( 1, 100_000_000 / ( $maxcol + 1 ) );

    while ( $begrow <= $maxrow )
    {
        $endrow = &List::Util::min( $maxrow, $begrow + $rowincr - 1 );

        foreach $row ( $begrow .. $endrow )
        {
            $pdl = $ali->seqs->slice( ":,($row)" )->sever;
            &PDL::Primitive::indadd( $ones, $pdl, $counts );
        }

        $begrow = $endrow + 1;

        $ali = &Ali::IO::connect_pdl( $path );
    }

    # Convert character counts to statistics vector format where U, u, T are
    # the same, etc, 

    $stats = bless {
        "ali_id" => $ali->sid,
        "ali_stats" => &Ali::Stats::encode_stats( $counts, $seq_type ),
        "seq_count" => $maxrow + 1,
    };

    return wantarray ? %{ $stats } : $stats;
}

sub col_stats_qual
{
    # Niels Larsen, May 2011.
    
    # Returns column statistics for a given alignment. The alignment must have 
    # the fields seqs, sids and datatype set, and its sequence row strings must 
    # have the exact same length. No filtering is done, but only the residues 
    # with quality over a given threshold are counted. It uses substr, but doing 
    # it all in C would be much faster. An object is returned with these keys,
    # 
    #  col_stats          2d statistics (cols x 8)
    #  col_count          Number of alignment columns
    #  row_count          Number of alignment rows
    #  seq_count          Number of sequences (adds up seq_count=nn info)

    my ( $ali,         # Alignment object
         $minqual,     # Quality percent minimum
         $qualtype,
         ) = @_;

    # Returns object.

    my ( $seqs, $seq_counts, $maxcol, $maxrow, $stats, $col_stat, @col_stats,
         $row, $col, $colstr, $hist, $info, $totcol, $totrow, $seq_total,
         $seq_type, $seq_quals, $sgaps, $qual_stat, $qual_ch,
         $seq_ch, $qual_pct, $seq_ndx, @qual_counts, $qual_count );

    $seq_type = $ali->datatype;
    
    $seqs = $ali->{"seqs"};
    $info = $ali->{"info"};

    $totcol = length $seqs->[0];
    $maxcol = $totcol - 1;

    $totrow = scalar @{ $seqs };
    $maxrow = $totrow - 1;

    state $indices = &Ali::Stats::stats_indices( $seq_type );
    state $qual_dict = &Ali::Stats::qual_dict( $qualtype );

    state $stat_size = &Common::Types::is_protein( $seq_type ) ? 24 : 8;
    state $max_seq_ndx = $stat_size - 4;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a list of 1) sequence counts by using the seq_total= field in the
    # sequence id headers, and 2) a list of sequence quality strings, also 
    # fetched from the headers,
    
    if ( defined $info )
    {
        for ( $row = 0; $row <= $#{ $info }; $row ++ )
        {
            if ( $info->[$row] =~ /seq_count=(\d+)/ ) {
                $seq_counts->[$row] = $1;
            } else {
                $seq_counts->[$row] = 1;
            }

            if ( $info->[$row] =~ /seq_quals=(\S+)/ ) {
                $seq_quals->[$row] = $1;
            } 
            else {
                &error( qq (No "seq_quals" key in the header line -> "$info->[$row]") );
            }
        }

        $seq_total = &List::Util::sum( @{ $seq_counts } );
    }
    else {
        &error( qq (No info field) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ALIGN QUALITIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # There are always the same number of quality characters as there are 
    # sequence characters. So we can align them to the 'gapped' sequence by 
    # simply inserting the gaps into the quality string in the right places,

    for ( $row = 0; $row <= $maxrow; $row ++ )
    {
        $sgaps = &Seq::Common::locate_sgaps( \$seqs->[$row] );
        $seq_quals->[$row] = ${ &Seq::Common::add_chars_str( \$seq_quals->[$row], $sgaps ) };
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sum up character and gap counts in @col_stats, which is a list of tuples
    # that each have totals for each column. Also sum up for each column the 
    # number of residues above a certain quality,

    @qual_counts = ();
    
    for ( $col = 0; $col <= $maxcol; $col ++ )
    {
        $col_stat = [ ( 0 ) x $stat_size ];
        $qual_count = 0;
        
        for ( $row = 0; $row <= $maxrow; $row ++ )
        {
            # Column tuples,

            $seq_ch = substr $seqs->[$row], $col, 1;
            $seq_ndx = $indices->{ $seq_ch };

            $col_stat->[ $seq_ndx ] += $seq_counts->[$row];

            # If at a non-gap character, then get the corresponding quality 
            # character, convert it to percentage, check against the required,
            # and if good enough add the sequence totals,

            if ( $seq_ndx <= $max_seq_ndx )
            {
                $qual_pct = $qual_dict->{ substr $seq_quals->[$row], $col, 1 };

                if ( $qual_pct >= $minqual )
                {
                    $qual_count += $seq_counts->[$row];
                }
            }
        }

        push @col_stats, $col_stat;
        push @qual_counts, $qual_count;
    }

    $stats = bless {
        "col_stats" => \@col_stats,
        "qual_counts" => \@qual_counts,
        "seq_count" => $seq_total,
        "row_count" => $totrow,
        "col_count" => $totcol,
    };

    return wantarray ? %{ $stats } : $stats;
}

sub encode_stats
{
    # Niels Larsen, September 2010.

    # Converts a 2D ascii character count PDL to more compact PDL with space 
    # only for sequence alphabet plus the three types of gaps ( -, ., ~ ).

    my ( $counts,   # Character counts vector
         $type,     # Datatype
        ) = @_;

    # Returns a 2D statistics piddle.

    my ( $stats, $dim, $ndx, $subref );

    $subref = sub
    {
        # Converts an ascii character count vector for a single column to 
        # a more compact PDL with space only for sequence alphabet plus 
        # the three types of gaps ( -, ., ~ ).

        my ( $count,
             $type,
            ) = @_;

        my ( $pdl );

        &error( qq (Type is undefined) ) if not defined $type;
        
        if ( &Common::Types::is_dna_or_rna( $type ) )
        {
            $pdl = PDL->new([
                $count->at( 65 ) + $count->at( 97 ),    # A,a   = 0
                $count->at( 71 ) + $count->at( 103 ),   # G,g   = 1
                $count->at( 67 ) + $count->at( 99 ),    # C,c   = 2
                $count->at( 84 ) + $count->at( 116 )    # T,t   = 3
              + $count->at( 85 ) + $count->at( 117 ),   # U,u  
                $count->at( 78 ) + $count->at( 110 ),   # N,n   = 4
                $count->at( 45 ),                       # -     = 5
                $count->at( 46 ),                       # .     = 6
                $count->at( 126 ),                      # ~     = 7
            ]);
        }
        elsif ( &Common::Types::is_protein( $type ) )
        {
            $pdl = PDL->new([
                $count->at( 71 ) + $count->at( 103 ),   # G,g   = 0
                $count->at( 80 ) + $count->at( 112 ),   # P,p   = 1
                $count->at( 65 ) + $count->at( 97 ),    # A,a   = 2
                $count->at( 86 ) + $count->at( 118 ),   # V,v   = 3
                $count->at( 76 ) + $count->at( 108 ),   # L,l   = 4
                $count->at( 73 ) + $count->at( 105 ),   # I,i   = 5
                $count->at( 77 ) + $count->at( 109 ),   # M,m   = 6
                $count->at( 83 ) + $count->at( 115 ),   # S,s   = 7
                $count->at( 84 ) + $count->at( 116 ),   # T,t   = 8
                $count->at( 78 ) + $count->at( 110 ),   # N,n   = 9
                $count->at( 81 ) + $count->at( 113 ),   # Q,q   = 10
                $count->at( 68 ) + $count->at( 100 ),   # D,d   = 11
                $count->at( 69 ) + $count->at( 101 ),   # E,e   = 12
                $count->at( 67 ) + $count->at( 99 ),    # C,c   = 13
                $count->at( 85 ) + $count->at( 117 ),   # U,u   = 14
                $count->at( 70 ) + $count->at( 102 ),   # F,f   = 15
                $count->at( 89 ) + $count->at( 121 ),   # Y,y   = 16
                $count->at( 87 ) + $count->at( 119 ),   # W,w   = 17
                $count->at( 75 ) + $count->at( 107 ),   # K,k   = 18
                $count->at( 82 ) + $count->at( 114 ),   # R,r   = 19
                $count->at( 72 ) + $count->at( 104 ),   # H,h   = 20
                $count->at( 45 ),                       # -
                $count->at( 46 ),                       # .
                $count->at( 126 ),                      # ~
             ]);
        } else {
            &error( qq (Wrong looking type -> "$type") );
        }
        
        return $pdl;
    };

    $dim = ( $counts->dims )[1];

    $stats = PDL->zeroes( $dim, length &Ali::Common::alphabet_stats( $type) );

    for ( $ndx = 0; $ndx <= $dim - 1; $ndx++ )
    {
        $stats->slice( "($ndx),:" ) .= $subref->( $counts->slice(":,($ndx)"), $type );
    }

    return $stats;
}

sub qual_dict
{
    # Niels Larsen, May 2011.

    # Creates a hash that converts quality characters to accuracies between zero
    # and 100 with a given encoding. For example, in the Illumina 1.3 encoding, 
    # the character "Z" would be converted to 99.75. 

    my ( $type,     # Quality type 
        ) = @_;

    # Returns hash.

    my ( $quals, $ord, $ch, $enc );

    $enc = &Seq::Common::qual_config( $type );
    
    foreach $ord ( $enc->{"min"} ... $enc->{"max"} ) 
    {
        $ch = chr $ord;
        $quals->{ $ch } = &Seq::Common::qualch_to_qual( $ch, $enc ) * 100;
    }
    
    return wantarray ? %{ $quals } : $quals;
}
    
sub splice_stats
{
    # Niels Larsen, May 2011.

    # Remove positions with too few residues from the sequence and quality
    # column arrays. 

    my ( $stats,        # Statistics object
         $resmin,       # Minimum residue/total ratio
        ) = @_;

    my ( $col_stats, @ndcs, $i, $stat, $seq_count );

    $col_stats = $stats->{"col_stats"};
    $seq_count = $stats->{"seq_count"};

    @ndcs = ();
    
    for ( $i = 0; $i <= $#{ $col_stats }; $i ++ )
    {
        $stat = $col_stats->[$i];
        
        if ( &List::Util::sum( @{ $stat }[ 0 .. $#{ $stat } - 3 ] ) / $seq_count >= $resmin ) {
            push @ndcs, $i;
        }
    }
    
    $stats->{"col_stats"} = [ @{ $col_stats }[ @ndcs ] ];
    
    if ( $stats->{"qual_counts"} ) {
        $stats->{"qual_counts"} = [ @{ $stats->{"qual_counts"} }[ @ndcs ] ];
    }
    
    return $stats;
}
    
sub stats_indices
{
    # Niels Larsen, May 2011.

    # Creates a hash where keys are characters and values are indices for
    # column statistics counts. DNA/RNA use the first five slots for counts
    # of A, G, C, T and N, proteins use indices 0-20. For both, the last 
    # three are used for indels, incomplete data and end-of-data (- . ~).

    my ( $type,        # Sequence data type
        ) = @_;

    # Returns hash.

    my ( $ndcs, $ch, $ord, $def_ndx );

    if ( &Common::Types::is_dna_or_rna( $type ) )
    {
        $ndcs = {
            "A" => 0,
            "G" => 1,
            "C" => 2,
            "T" => 3,
            "N" => 4,
            "-" => 5,
            "." => 6,
            "~" => 7,
        };

        $def_ndx = 5;
    }
    else 
    {
        $ndcs = {
            "G" => 0,
            "P" => 1,
            "A" => 2,
            "V" => 3,
            "L" => 4,
            "I" => 5,
            "M" => 6,
            "S" => 7,
            "T" => 8,
            "N" => 9,
            "Q" => 10,
            "D" => 11,
            "E" => 12,
            "C" => 13,
            "U" => 14,
            "F" => 15,
            "Y" => 16,
            "W" => 17,
            "K" => 18,
            "R" => 19,
            "H" => 20,
            "-" => 21,
            "." => 22,
            "~" => 23,
        };

        $def_ndx = 21;
    }

    # Fill in lower-case equivalents,

    map { $ndcs->{ lc $_ } = $ndcs->{ $_ } } keys %{ $ndcs };

    # Give all other characters the same slot as "-" has,

    foreach $ord ( 32 ... 126 ) 
    {
        $ch = chr $ord;
        $ndcs->{ $ch } = $def_ndx if not defined $ndcs->{ $ch };
    }

    return wantarray ? %{ $ndcs } : $ndcs;
}
    
1;

__END__

# sub row_stats
# {
#     # Niels Larsen, September 2010.

#     # Creates row statistics from an alignment object. Statistics is a 2D 
#     # piddle with as many columns as there are rows in the alignment; the 
#     # number of rows are 4 for DNA/RNA and 20 for protein. The values are the 
#     # number of times a character occurs in a given column. Upper/lower case 
#     # and T/U differences are folded into one count. See also filter_stats
#     # which can trim and reduce the statistics piddle. 

#     my ( $ali,        # Alignment object
#          ) = @_;

#     # Returns a 2D PDL array. 

#     my ( $stats, $col, $pdl, $maxrow, $maxcol, $ones, $counts, $type );

#     $maxrow = $ali->max_row;
#     $maxcol = $ali->max_col;
    
#     # First add character counts, row by row, to a 128 x maxcol matrix,

#     $counts = PDL->zeroes( 128, $maxrow + 1 );
#     $ones = PDL->ones( $maxrow + 1 );
    
#     for ( $col = 0; $col <= $maxcol; $col++ )
#     {
#         $pdl = $ali->seqs->slice( "($col),:" );
#         &PDL::Primitive::indadd( $ones, $pdl, $counts );
#     }

#     # Then convert those counts to a statistics vector format where upper 
#     # and lower case, and U, u, T, t are the same, 

#     $stats = &Ali::Stats::encode_stats( $counts, $ali->datatype );

#     return $stats;
# }

# sub counts_acceptable
# {
#     # Niels Larsen, May 2011. 

#     # Tests a given list of residue counts against minimum requirements for 
#     # 1) residue content out of a given total, 2) conservation among residues.

#     my ( $counts,
#          $conf,
#         ) = @_;
    
#     my ( $res_mfreq, $res_sum, $res_counts );

#     $res_counts = [ @{ $counts }[ 0 .. $#{ $counts } - 3 ] ];   # Skip 3 gap-slots

#     $res_sum = &List::Util::sum( @{ $res_counts } );   # Sum of residues
    
#     return if $res_sum == 0;
    
#     $res_mfreq = ( sort { $b <=> $a } @{ $res_counts } )[0];   # Most frequent 
    
#     # This says: if the number of non-gap characters of a column is at least
#     # the required, and the most frequent residue is as least as abundant as
#     # required, then return 1 otherwise 0,
    
#     if ( ( $res_sum / $conf->{"seq_count"} >= $conf->{"res_min"} ) and 
#          ( $res_mfreq / $res_sum >= $conf->{"cons_min"} ) )
#     {
#         return 1;
#     } else {
#         return 0;
#     }
# }

# sub filter_columns
# {
#     my ( $stats,
#          $restot,
#          $resmin,
#         ) = @_;

#     $stats = [ 
#         grep { &List::Util::sum( @{ $_ }[ 0 .. $#{ $_ } - 3 ] ) / $restot >= $resmin } @{ $stats }
#                 ];

#     return wantarray ? %{ $stats } : $stats;
# }

# sub trim_stats
# {
#     # Niels Larsen, September 2010.

#     # Trims the leading and/or trailing ends of column counts vector by its
#     # numbers: if given minimum percent non-gaps and residue conservation is 
#     # not met, then begin/end positions are changed. Returned is a sub-list
#     # in the same format as given.

#     my ( $stats,    # List of column counts
#          $total,    # Sequence counts total
#          $args,     # Arguments hash or object
#         ) = @_;

#     # Returns a list.
    
#     my ( $is_ok, $maxrow, $maxcol, $resmin, $consmin, $begpos, $endpos, $pos,
#          $sub_stats, $conf );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> COLLECT INDICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $conf = {
#         "seq_count" => $total,
#         "res_min" => $args->{"res_min"},
#         "cons_min" => $args->{"cons_min"},
#     };

#     $begpos = 0;
#     $endpos = $#{ $stats };

#     # Skip low-quality columns at beginnings,

#     if ( $args->trim_beg )
#     {
#         while ( $begpos <= $endpos and 
#                 not &Ali::Stats::counts_acceptable( $stats->[$begpos], $conf ) )
#         {
#             $begpos += 1;
#         }
#     }
    
#     # Skip low-quality columns at ends,

#     if ( $args->trim_end )
#     {
#         while ( $endpos >= $begpos and
#                 not &Ali::Stats::counts_acceptable( $stats->[$endpos], $conf ) )
#         {
#             $endpos -= 1;
#         }
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE SUB-LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     $sub_stats = [ @{ $stats }[ $begpos .. $endpos ] ];

#     return $sub_stats;
# }
