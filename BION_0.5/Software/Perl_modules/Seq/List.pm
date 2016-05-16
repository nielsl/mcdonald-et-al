package Seq::List;                # -*- perl -*-

# /*
#
# DESCRIPTION
#
# Routines that take a list (or two) of sequences, and then filter, transform,
# extract from or makes statistics from them. They use Seq::Common which has 
# routines that work on single sequences.
#
# The list routines are typically used with file filters, like cleaning flows,
# that read a set of sequences into memory, does something, and writes them. 
# Calls to these routines can easily be combined into larger routines: if a 
# list routine returns an an empty list, then the next list routine will do
# nothing.
#
# */

use strict;
use warnings FATAL => qw ( all );

use feature "state";

use Common::Messages;

use Bio::Patscan;
use Seq::Common;

our @Functions = (
    [ "add_qual_to_info",            "" ],
    [ "change_complement",           "Translates and reverses list of sequences" ],
    [ "change_to_dna",               "Changes Uu to Tt for a list of sequences" ],
    [ "change_to_lowercase",         "Changes a list of sequences to lowercase" ],
    [ "change_to_rna",               "Changes Tt to Uu for a list of sequences" ],
    [ "change_to_uppercase",         "Changes a list of sequences to uppercase" ],
    [ "change_by_quality",           "Changes bases based on quality" ],
    [ "clip_pat_beg",                "" ],
    [ "clip_pat_end",                "" ],
    [ "delete_gaps",                 "Delete non-alphabetic characters - TODO: handle qualities" ],
    [ "delete_info",                 "" ],
    [ "filter_gc",                   "" ],
    [ "filter_id_length_max",        "" ],
    [ "filter_id_length_min",        "" ],
    [ "filter_id_length_range",      "" ],
    [ "filter_id_match",             "" ],
    [ "filter_id_non",               "" ],
    [ "filter_id_regexp",            "" ],
    [ "filter_is_dna",               "" ],
    [ "filter_info_regexp",          "" ],
    [ "filter_length_max",           "" ],
    [ "filter_length_min",           "" ],
    [ "filter_length_range",         "" ],
    [ "filter_patf_locs",            "" ],
    [ "filter_patf_seqs",            "" ],
    [ "filter_patf_seqs_sub",        "" ],
    [ "filter_patf_seqs_non",        "" ],
    [ "filter_patr_locs",            "" ],
    [ "filter_patr_seqs",            "" ],
    [ "filter_patr_seqs_sub",        "" ],
    [ "filter_patr_seqs_non",        "" ],
    [ "filter_qual",                 "" ],
    [ "insert_breaks",               "" ],
    [ "join_seq_pairs",              "" ],
    [ "pair_seq_lists",              "" ],
    [ "split_left",                  "Returns the leftmost n% of sequences" ],
    [ "split_right",                 "Returns the rightmost n% of sequences" ],
    [ "sum_gc",                      "" ],
    [ "sum_length",                  "" ],
    [ "trim_qual_beg",               "" ],
    [ "trim_qual_end",               "" ],
    [ "trim_seq_beg",                "" ],
    [ "trim_seq_end",                "" ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Seq_buf, $Qual_buf );

$Seq_buf = " " x 10_000;
$Qual_buf = " " x 10_000;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_qual_to_info
{
    my ( $seqs,
        ) = @_;

    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        if ( $seq->{"info"} ) {
            $seq->{"info"} .= qq (; seq_quals=$seq->{"qual"});
        } else {
            $seq->{"info"} .= qq (seq_quals=$seq->{"qual"});
        }
    }

    return $seqs;
}
    
sub change_complement
{
    my ( $seqs,
        ) = @_;

    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        &Seq::Common::complement( $seq );
    }

    return $seqs;
}

sub change_to_dna
{
    # Niels Larsen, November 2009.

    # Substitutes all RNA characters to DNA characters. Returns an 
    # updated sequence object.

    my ( $seqs,
        ) = @_;

    # Returns hash or object. 
    
    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        $seq->{"seq"} =~ tr/Uu/Tt/;
        $seq->{"type"} = "dna";
    }

    return $seqs;
}

sub change_to_lowercase
{
    # Niels Larsen, December 2011.

    # Converts a list of sequences to lowercase. Returns a list of 
    # updated objects.

    my ( $seqs,
        ) = @_;

    # Returns hash or object.

    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        $seq->{"seq"} =~ tr/A-Z/a-z/;
    }

    return $seqs;
}

sub change_to_rna
{
    # Niels Larsen, November 2009.

    # Substitutes all DNA characters to RNA characters. Returns a 
    # list of updated sequence objects.

    my ( $seqs,
        ) = @_;

    # Returns hash or object. 
    
    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        $seq->{"seq"} =~ tr/Tt/Uu/;
        $seq->{"type"} = "rna";
    }

    return $seqs;
}

sub change_to_uppercase
{
    # Niels Larsen, December 2011.

    # Converts a list of sequences to uppercase.

    my ( $seqs,
        ) = @_;

    # Returns hash or object.

    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        $seq->{"seq"} =~ tr/a-z/A-Z/;
    }
    
    return $seqs;
}

sub change_by_quality
{
    # Niels Larsen, January 2012.

    # Substitutes bases in a given quality range with the given
    # base character. For example "substitute all low quality bases
    # by N" is typical. Returns updated list.

    my ( $seqs,
         $seqch,
         $minch,
         $maxch,
        ) = @_;

    # Returns a list.

    my ( $seq, $count );

    foreach $seq ( @{ $seqs } )
    {
        $count = &Seq::Common::change_by_quality_C(
            $seq->{"seq"},
            $seq->{"qual"},
            $seqch,
            $minch,
            $maxch,
            length $seq->{"seq"},
            );
    }

    return $seqs;
}

sub clip_pat_beg
{
    # Niels Larsen, July 2011. 

    # Returns the sequence that follows a match, optionally including the 
    # match. The match must occur within the given distance from the beginning.
    # If no match, the input sequence is returned unchanged. Returns an updated
    # sequence list.

    my ( $seqs,   # Sequence list 
         $pstr,   # Pattern string 
         $dist,   # How far into the sequence the pattern may go
         $incl,   # Switch to include match or not
        ) = @_;

    # Returns a list.

    my ( $seq, $pos, $locs, $len, $hitend );

    if ( not defined $pstr ) {
        &error( qq (A clip-pattern string must be given) );
    }

    &Bio::Patscan::compile_pattern( $pstr, 0 );

    if ( $incl )
    {
        foreach $seq ( @{ $seqs } )
        {
            if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} ) and @{ $locs } )
            {
                # If the match end position is not further down the sequence than
                # dist, then cut out the sequence from the start of the match,

                $hitend = $locs->[-1]->[-1]->[0] + $locs->[-1]->[-1]->[1];

                if ( $hitend <= $dist )
                {
                    $pos = $locs->[0]->[0]->[0];
                    $len = ( length $seq->{"seq"} ) - $pos;

                    &Seq::Common::sub_seq_clobber( $seq, [[ $pos, $len ]] );
                }
            }
        }
    }
    else
    {
        foreach $seq ( @{ $seqs } )
        {
            if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} ) and @{ $locs } )
            {
                # If the match end position is not further down the sequence than
                # dist, then cut out the sequence from the end of the match,

                $hitend = $locs->[-1]->[-1]->[0] + $locs->[-1]->[-1]->[1];
                
                if ( $hitend <= $dist )
                {
                    $len = ( length $seq->{"seq"} ) - $hitend;
                    &Seq::Common::sub_seq_clobber( $seq, [[ $hitend, $len ]] );
                }
            }
        }
    }        

    return $seqs;
}

sub clip_pat_end
{
    # Niels Larsen, July 2011. 

    # Returns the sequence that precedes a match, optionally including the 
    # match. The match must occur within the given distance from the end. If 
    # no match, the input sequence is returned unchanged. Returns an updated
    # sequence list.

    my ( $seqs,   # Sequence list 
         $pstr,   # Pattern string 
         $dist,   # Max distance into the 
         $incl,   # Switch to include match or not
        ) = @_;

    # Returns a list.

    my ( $seq, $pos, $locs );

    if ( not defined $pstr ) {
        &error( qq (A clip-pattern string must be given) );
    }

    &Bio::Patscan::compile_pattern( $pstr, 0 );

    if ( $incl )
    {
        # With the match sequence,

        foreach $seq ( @{ $seqs } )
        {
            if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} ) and @{ $locs } )
            {
                # If sequence length minus the match start position is not
                # longer than dist, then cut out the sequence from the start,
                # including the match itself,

                if ( ( length $seq->{"seq"} ) - $locs->[0]->[0]->[0] <= $dist )
                {
                    $pos = $locs->[0]->[-1]->[0] + $locs->[0]->[-1]->[1];
                    &Seq::Common::sub_seq_clobber( $seq, [[ 0, $pos ]] );
                }
            }
        }
    }
    else
    {
        # Without the match sequence,

        foreach $seq ( @{ $seqs } )
        {
            if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} ) and @{ $locs } )
            {
                # If sequence length minus the match start position is not
                # longer than dist, then cut out the sequence from the start,
                # excluding the match itself,

                if ( ( length $seq->{"seq"} ) - $locs->[0]->[0]->[0] <= $dist )
                {
                    &Seq::Common::sub_seq_clobber( $seq, [[ 0, $locs->[0]->[0]->[0] ]] );
                }
            }
        }
    }

    return $seqs;
}

sub delete_gaps
{
    my ( $seqs,
        ) = @_;

    my ( $seq );
    
    foreach $seq ( @{ $seqs } )
    {
        # $len = &Seq::List::copy_nongaps_C( $seq->{"seq"}, 0, length $seq->{"seq"} );
        # $seq->{"seq"} = substr $seq->{"seq"}, 0, $len;

        $seq->{"seq"} =~ tr/\.\-\~//d;
    }

    return $seqs;
}

sub delete_info
{
    my ( $seqs,
        ) = @_;

    my ( $seq );
    
    foreach $seq ( @{ $seqs } )
    {
        delete $seq->{"info"};
    }

    return $seqs;
}

sub filter_gc
{
    my ( $seqs,
         $mingc,
         $maxgc,
        ) = @_;

    my ( $seq, @seqs, $gc, $at, $gc_rat );

    foreach $seq ( @{ $seqs } )
    {
        $gc = $seq->{"seq"} =~ tr/GgCc/GgCc/;
        $at = $seq->{"seq"} =~ tr/AaTtUu/AaTtUu/;

        $gc_rat = $gc / ( $gc + $at );

        if ( $gc_rat >= $mingc and $gc_rat <= $maxgc )
        {
            push @seqs, $seq;
        }
    }
    
    return \@seqs;
}
         
sub filter_id_length_max
{
    my ( $seqs,
         $maxlen,
        ) = @_;

    $seqs = [ grep { ( length $_->{"id"} ) <= $maxlen } @{ $seqs } ];

    return $seqs;
}

sub filter_id_length_min
{
    my ( $seqs,
         $minlen,
        ) = @_;

    $seqs = [ grep { ( length $_->{"id"} ) >= $minlen } @{ $seqs } ];

    return $seqs;
}

sub filter_id_length_range
{
    my ( $seqs,
         $minlen,
         $maxlen,
        ) = @_;

    my ( $len );

    $seqs = [ grep { $len = length $_->{"id"}; $len >= $minlen and $len <= $maxlen } @{ $seqs } ];

    return $seqs;
}

sub filter_id_match
{
    my ( $seqs,
         $ids,
        ) = @_;

    $seqs = [ grep { exists $ids->{ $_->{"id"} } } @{ $seqs } ];
    
    return $seqs;
}
    
sub filter_id_non
{
    my ( $seqs,
         $ids,
        ) = @_;

    $seqs = [ grep { not exists $ids->{ $_->{"id"} } } @{ $seqs } ];
    
    return $seqs;
}
    
sub filter_id_regexp
{
    my ( $seqs,
         $regexp,
        ) = @_;

    $seqs = [ grep { $_->{"id"} =~ /$regexp/ } @{ $seqs } ];
    
    return $seqs;
}
    
sub filter_id_regexp_non
{
    my ( $seqs,
         $regexp,
        ) = @_;

    $seqs = [ grep { $_->{"id"} !~ /$regexp/i } @{ $seqs } ];
    
    return $seqs;
}
    
sub filter_info_regexp
{
    my ( $seqs,
         $regexp,
        ) = @_;

    $seqs = [ grep { $_->{"info"} =~ /$regexp/i } @{ $seqs } ];
    
    return $seqs;
}

sub filter_is_dna
{
    my ( $seqs,
         $rat,
        ) = @_;

    $rat //= 0.9;

    $seqs = [ grep { ( $_->{"seq"} =~ tr/AGCTNagctn/AGCTNagctn/ ) / length $_->{"seq"} >= $rat } @{ $seqs } ];
    
    return $seqs;
}

sub filter_is_not_dna
{
    my ( $seqs,
         $rat,
        ) = @_;

    $rat //= 0.9;

    $seqs = [ grep { ( $_->{"seq"} =~ tr/AGCTNagctn/AGCTNagctn/ ) / length $_->{"seq"} < $rat } @{ $seqs } ];
    
    return $seqs;
}

sub filter_length_max
{
    my ( $seqs,
         $maxlen,
        ) = @_;

    $seqs = [ grep { ( length $_->{"seq"} ) <= $maxlen } @{ $seqs } ];

    return $seqs;
}

sub filter_length_min
{
    my ( $seqs,
         $minlen,
        ) = @_;

    $seqs = [ grep { ( length $_->{"seq"} ) >= $minlen } @{ $seqs } ];

    return $seqs;
}

sub filter_length_range
{
    my ( $seqs,
         $minlen,
         $maxlen,
        ) = @_;

    my ( $len );

    $seqs = [ grep { $len = length $_->{"seq"}; $len >= $minlen and $len <= $maxlen } @{ $seqs } ];

    return $seqs;
}

sub filter_patf_locs
{
    # Niels Larsen, December 2011. 

    # Returns the locators where matches to a pattern are in the forward 
    # direction. Input sequences are not changed.

    my ( $seqs,
         $args,
        ) = @_;

    # Returns a list.

    my ( $seq, @locs, $locs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    foreach $seq ( @{ $seqs } )
    {
        if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} ) and @{ $locs } )
        {
            push @locs, $locs;
        }
    }

    return \@locs;
}

sub filter_patf_seqs
{
    # Niels Larsen, December 2011. 

    # Returns the sequences that match a pattern in the forward direction.

    my ( $seqs,
         $args,
        ) = @_;

    # Returns a list.

    my ( $seq, @seqs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    foreach $seq ( @{ $seqs } )
    {
        if ( @{ &Bio::Patscan::match_forward( $seq->{"seq"} ) } )
        {
            push @seqs, $seq;
        }
    }

    return \@seqs;
}

sub filter_patf_seqs_sub
{
    # Niels Larsen, December 2011. 

    # Returns part of the sequences that match a pattern in the forward 
    # direction.

    my ( $seqs,
         $args,
        ) = @_;

    # Returns a list. 

    my ( $seq, $locs, $ndcs, @seqs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    $ndcs = $args->{"get_ndcs"};

    foreach $seq ( @{ $seqs } )
    {
        if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} )->[0] and @{ $locs } )
        {
            push @seqs, &Seq::Common::sub_seq_clobber( $seq, [ @{ $locs }[ @{ $ndcs } ] ] );
        }
    }

    return \@seqs;
}

sub filter_patf_seqs_non
{
    # Niels Larsen, December 2011. 

    # Returnns the sequences that do not match a pattern in the forward 
    # direction.

    my ( $seqs,
         $args,
        ) = @_;
    
    # Returns a list.

    my ( $seq, @seqs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    foreach $seq ( @{ $seqs } )
    {
        if ( not @{ &Bio::Patscan::match_forward( $seq->{"seq"} ) } )
        {
            push @seqs, $seq;
        }
    }

    return \@seqs;
}

sub filter_patr_locs
{
    # Niels Larsen, January 2012. 

    # Returns the locators where matches to a pattern are in the reverse
    # direction. NOTE: input sequences are changed to the complement, and
    # the locator positions refer to that complemented version. 

    my ( $seqs,
         $args,
        ) = @_;
    
    # Returns a list.

    my ( $seq, @locs, $locs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    foreach $seq ( @{ $seqs } )
    {
        if ( $locs = &Bio::Patscan::match_reverse_alt( $seq->{"seq"} ) and @{ $locs } )
        {
            $seq->{"qual"} = reverse $seq->{"qual"};

            push @locs, $locs;
        }
    }

    return \@locs;
}

sub filter_patr_seqs
{
    # Niels Larsen, December 2011. 

    # Returnns the sequences that match a pattern in the reverse direction.
    # NOTE: the input sequences are complemented, i.e. the input is changed.

    my ( $seqs,
         $args,
        ) = @_;
    
    # Returns a list.

    my ( $seq, @seqs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    foreach $seq ( @{ $seqs } )
    {
        if ( @{ &Bio::Patscan::match_reverse_alt( $seq->{"seq"} ) } )
        {
            $seq->{"qual"} = reverse $seq->{"qual"};

            push @seqs, $seq;
        }
    }

    return \@seqs;
}

sub filter_patr_seqs_sub
{
    # Niels Larsen, December 2011. 

    # Returns part of the sequences that match a pattern in the reverse
    # direction. NOTE: the input sequences are complemented, i.e. the input
    # is changed.


    my ( $seqs,
         $args,
        ) = @_;

    # Returns a list. 

    my ( $seq, $locs, @seqs, $ndcs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    $ndcs = $args->{"get_ndcs"};

    foreach $seq ( @{ $seqs } )
    {
        if ( $locs = &Bio::Patscan::match_reverse_alt( $seq->{"seq"} )->[0] and @{ $locs } )
        {
            $seq->{"qual"} = reverse $seq->{"qual"};

            push @seqs, &Seq::Common::sub_seq_clobber( $seq, [ @{ $locs }[ @{ $ndcs } ] ] );
        }
    }

    return \@seqs;
}

sub filter_patr_seqs_non
{
    # Niels Larsen, December 2011. 

    # Returnns the sequences that do not match a pattern in the reverse
    # direction.

    my ( $seqs,
         $args,
        ) = @_;
    
    # Returns a list.

    my ( $seq, @seqs );

    &Bio::Patscan::compile_pattern( $args->{"pat_string"}, $args->{"protein"} );

    foreach $seq ( @{ $seqs } )
    {
        if ( not @{ &Pat::Patscan::match_reverse( $seq->{"seq"} ) } )
        {
            push @seqs, $seq;
        }
    }

    return \@seqs;
}

sub filter_qual
{
    my ( $seqs,
         $minch,     
         $maxch,
         $minpct,
         $maxpct,
        ) = @_;

    my ( $pct );

    $seqs = [ grep { $pct = &Seq::Common::qual_pct( $_, $minch, $maxch );
                     $pct >= $minpct and $pct <= $maxpct } @{ $seqs } ];
    
    return $seqs;
}

sub insert_breaks
{
    # Niels Larsen, May 2013.

    # Helper function that inserts a single break character (blank by default)
    # into sequences with the seq_break info field set. If seq_break is 100 for
    # example, then the blank is inserted between the 100th and 101st character.
    # If the seq_break field is -1 then no insertion. Returns an updated list.

    my ( $seqs,   # List of sequences
         $char,   # Sequence character to insert
         $qual,   # Quality character to insert - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $seq, $pos );

    foreach $seq ( @{ $seqs } )
    {
        if ( $seq->{"info"} and $seq->{"info"} =~ /seq_break=(\d+)/ )
        {
            substr $seq->{"seq"}, $1, 0, $char;
        }
    }
    
    if ( defined $qual )
    {
        foreach $seq ( @{ $seqs } )
        {
            if ( $seq->{"info"} and $seq->{"info"} =~ /seq_break=(\d+)/ )
            {
                substr $seq->{"qual"}, $1, 0, $qual;
            }
        }
    }

    return $seqs;
}

sub join_seq_pairs
{
    # Niels Larsen, February 2013.

    # Creates joined sequences out of two lists of pair-mates. Input is two 
    # equally long lists of sequences of forward and reverse reads, output 
    # is a single list. When sequences overlap the joined sequence gets the
    # the best quality bases (and corresponding quality values) from either
    # source. The info fields of overlapping sequences include the 
    # "seq_break=-1" statement. Non-overlapping seqeuences have their source
    # sequence and quality strings concatenated and the seq_break value is
    # then set to the starting offset of the second sequence. A minimum 
    # match percent and 
    # minimum match length can be given, but no indels are allowed. The ids
    # of the output sequences are those of the forward makes but with the 
    # reverse id given in the info fields with the key r_seq_id. Returns a
    # list of sequence hashes. 

    my ( $seqs1,        # List of forward mates 
         $seqs2,        # List of reverse mates
         $mpct,         # Minimum match percent - OPTIONAL, default 80
         $mmin,         # Minimum match length - OPTIONAL, default 10
         $miss,         # Include non-matches - OPTIONAL, default 1
         $both,         # Try both 1/2 and 2/1 - OPTIONAL, default 0
        ) = @_;

    # Returns a list.

    my ( $mrat, $i, $j, $pos1, $pos2, $seq1, $seq2, @seqs, $len );

    if ( ( $i = scalar @{ $seqs1 } ) != ( $j = scalar @{ $seqs2 } ) ) {
        &error( qq ($i sequences in \$seqs1 but $j in \$seqs2) );
    }
    
    $mpct //= 80;
    $mmin //= 15;
    $miss //= 1;
    $both //= 0;

    $mrat = 1 - $mpct / 100;

    for ( $i = 0; $i <= $#{ $seqs1 }; $i += 1 )
    {
        $seq1 = $seqs1->[$i];
        $seq2 = $seqs2->[$i];

        # Test for overlap. A non-negative value of $pos1 indicates the index
        # in $seq1 where there is a match. If -1 there is no match,

        $pos1 = &Seq::Common::find_overlap_end_C(
            $seq1->{"seq"}, $seq2->{"seq"},
            length $seq1->{"seq"}, $mrat, $mmin );

        if ( $pos1 > -1 )
        {
            # Overlap. Join the sequences into a new and longer sequence, 
            # where the best qualities and their bases are taken from each.

            $len = &Seq::Common::join_seq_pairs_C(
                $seq1->{"seq"}, $seq1->{"qual"}, $pos1, 
                $seq2->{"seq"}, $seq2->{"qual"}, 
                $Seq_buf, $Qual_buf );

            push @seqs, {
                "id" => $seq1->{"id"},
                "seq" => ( substr $Seq_buf, 0, $len ),
                "qual" => ( substr $Qual_buf, 0, $len ),
                "info" => qq (seq_break=-1 seq_mate_id=$seq2->{"id"}),
            };
        }
        elsif ( $both )
        {
            $pos2 = &Seq::Common::find_overlap_end_C(
                $seq2->{"seq"}, $seq1->{"seq"},
                length $seq2->{"seq"}, $mrat, $mmin );

            if ( $pos2 > -1 )
            {
                # Overlap. Join the sequences into a new and longer sequence, 
                # where the best qualities and their bases are taken from each.
                
                $len = &Seq::Common::join_seq_pairs_C(
                    $seq2->{"seq"}, $seq2->{"qual"}, $pos2, 
                    $seq1->{"seq"}, $seq1->{"qual"}, 
                    $Seq_buf, $Qual_buf );
                
                push @seqs, {
                    "id" => $seq2->{"id"},
                    "seq" => ( substr $Seq_buf, 0, $len ),
                    "qual" => ( substr $Qual_buf, 0, $len ),
                    "info" => qq (seq_break=-1 seq_mate_id=$seq1->{"id"}),
                };
            }
            elsif ( $miss )
            {
                # No overlap. Concatenate the sequences and put a seq_break= 
                # statement into the info field that gives the starting offset 
                # of the reverse sequence and quality. 
                
                push @seqs, {
                    "id" => $seq1->{"id"},
                    "seq" => $seq1->{"seq"} . $seq2->{"seq"},
                    "qual" => $seq1->{"qual"} . $seq2->{"qual"},
                    "info" => qq (seq_break=) . length $seq1->{"seq"} ." seq_mate_id=$seq2->{'id'}",
                };
            }
        }
        elsif ( $miss )
        {
            # No overlap. Concatenate the sequences and put a seq_break= 
            # statement into the info field that gives the starting offset 
            # of the reverse sequence and quality. 

            push @seqs, {
                "id" => $seq1->{"id"},
                "seq" => $seq1->{"seq"} . $seq2->{"seq"},
                "qual" => $seq1->{"qual"} . $seq2->{"qual"},
                "info" => qq (seq_break=) . length $seq1->{"seq"} ." seq_mate_id=$seq2->{'id'}",
            };
        }
    }

    return wantarray ? @seqs : \@seqs;
}

sub pair_seq_lists
{
    # Niels Larsen, March 2013.

    # Extracts pairs from two lists of sequence by their seq_num info
    # field. The seq_num field is a running number set by the caller and
    # outputs are two new equally long lists where each sequence has its
    # mate in the same index of the other list. No copies are made, the
    # output has references to the input sequences. Returns a two 
    # element list. 

    my ( $seqs1,
         $seqs2,
        ) = @_;

    # Returns a two element list.

    my ( $ndx1, $ndx2, $num1, $num2, @seqs1, @seqs2, $i, $j );

    $ndx1 = 0;
    $ndx2 = 0;
    
    while ( 1 )
    {
        if ( $seqs1->[$ndx1]->{"info"} =~ /seq_num=(\d+)/ ) {
            $num1 = $1;
        } else {
            &dump( $seqs1->[$ndx1] );
            &error( qq (No \$seqs1 seq_num info field) );
        }
        
        if ( $seqs2->[$ndx2]->{"info"} =~ /seq_num=(\d+)/ ) {
            $num2 = $1;
        } else {
            &dump( $seqs2->[$ndx2] );
            &error( qq (No \$seqs2 seq_num info field) );
        }
        
        if ( $num1 == $num2 )
        {
            push @seqs1, $seqs1->[$ndx1];
            push @seqs2, $seqs2->[$ndx2];
            
            $ndx1 += 1;
            $ndx2 += 1;
        }
        elsif ( $num1 < $num2 )
        {
            $ndx1 += 1;
        }
        elsif ( $num1 > $num2 )
        {
            $ndx2 += 1;
        }

        last if $ndx1 > $#{ $seqs1 } or $ndx2 > $#{ $seqs2 };
    }

    if ( ( $i = scalar @seqs1 ) != ( $j = scalar @seqs2 ) ) {
        &error( qq (\@seqs1 is $i long, but \@seqs2 is $j long. Programming error) );
    }

    return ( \@seqs1, \@seqs2 );
}

sub split_left
{
    my ( $seqs,
         $rat
        ) = @_;

    my ( @seqs, $seq, $len );

    foreach $seq ( @{ $seqs } )
    {
        $len = int ( length $seq->{"seq"} ) * $rat;

        push @seqs, &Seq::Common::sub_seq( $seq, [[ 0, $len ]] );
    }

    return \@seqs;
}

sub split_right
{
    my ( $seqs,
         $rat
        ) = @_;

    my ( @seqs, $seq, $len );

    $rat = 1 - $rat;

    foreach $seq ( @{ $seqs } )
    {
        $len = int ( length $seq->{"seq"} ) * $rat;
        
        push @seqs, &Seq::Common::sub_seq( $seq, [[ $len ]] );
    }

    return \@seqs;
}

sub sum_gc
{
    my ( $seqs,
        ) = @_;

    my ( $sum );

    $sum = 0;

    map { $sum += $_->{"seq"} =~ tr/GgCc/GgCc/ } @{ $seqs };

    return $sum;
}

sub sum_length
{
    my ( $seqs,
        ) = @_;

    my ( $sum );

    $sum = 0;

    map { $sum += length $_->{"seq"} } @{ $seqs };

    return $sum;
}

sub trim_qual_beg
{
    my ( $seqs,
         $cmin,
         $wlen,
         $whit,
        ) = @_;

    my ( $seq );

    $seqs = [ grep { &Seq::Common::trim_beg_qual( $_, $cmin, $wlen, $whit ) } @{ $seqs } ];

    return $seqs;
}

sub trim_qual_end
{
    my ( $seqs,
         $cmin,
         $wlen,
         $whit,
        ) = @_;

    my ( $seq );

    $seqs = [ grep { &Seq::Common::trim_end_qual( $_, $cmin, $wlen, $whit ) } @{ $seqs } ];

    return $seqs;
}

sub trim_seq_beg
{
    my ( $seqs,
         $pstr,
         $dist,
         $mpct,
         $mmin,
        ) = @_;

    my ( $seq, $mrat, $pos );

    if ( not defined $pstr ) {
        &error( qq (A trim-sequence string must be given) );
    }

    $pstr = uc $pstr;
    $mrat = 1 - $mpct / 100;

    @{ $seqs } = map
    {
        $pos = &Seq::Common::find_overlap_beg_C( $_->{"seq"}, $pstr, $dist, $mrat, $mmin );
        
        if ( $pos >= 0 ) {
            &Seq::Common::trim_beg_len( $_, $pos + 1 );
        }
        
        $_;
    } @{ $seqs };

    return $seqs;
}

sub trim_seq_end
{
    my ( $seqs,
         $pstr,
         $dist,
         $mpct,
         $mmin,
        ) = @_;

    my ( $seq, $mrat, $pos, $len );

    if ( not defined $pstr ) {
        &error( qq (A trim-sequence string must be given) );
    }
    
    $pstr = uc $pstr;
    $mrat = 1 - $mpct / 100;

    @{ $seqs } = map
    {
        $pos = &Seq::Common::find_overlap_end_C( $_->{"seq"}, $pstr, $dist, $mrat, $mmin );
        
        if ( $pos != -1 and $pos < ( $len = length $_->{"seq"} ) ) {
            &Seq::Common::trim_end_len( $_, $len - $pos );
        }
        
        $_;
    } @{ $seqs };

    return $seqs;
}

1;

__END__

