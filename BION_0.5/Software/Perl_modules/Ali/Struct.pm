package Ali::Struct;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

our ( @Functions );

@Functions = (
    [ "is_covar_hash",         "" ],
    [ "is_pair_hash",          "" ],
    [ "is_pair_hash_ag",       "" ],
    [ "is_pair_hash_gu",       "" ],
    [ "is_pair_hash_gu_ag",    "" ],
    [ "is_pair_hash_wc",       "" ],
    [ "is_uncovar_hash",       "" ],
    [ "score_column_covar",    "" ],
    [ "score_pairing_covar",   "" ],
    [ "sum_covar_scores",      "" ],
    [ "two_bit_codes",         "" ],
    );
    
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub is_covar_hash
{
    # Niels Larsen, April 2005.

    # Creates a hash that tells if both bases of two base pairs are different. 

    # Returns a hash.

    my ( @bases, $base1, $base2, $base3, $base4, %hash );

    @bases = qw ( A U G C a u g c );

    foreach $base1 ( @bases )
    {
        foreach $base2 ( @bases )
        {
            foreach $base3 ( @bases )
            {
                foreach $base4 ( @bases )
                {
                    if ( uc $base1 ne uc $base3 and
                         uc $base2 ne uc $base4 )
                    {
                        $hash{ $base1 }{ $base2 }{ $base3 }{ $base4 } = 1;
                    }
                }
            }
        }
    }

    return wantarray ? %hash : \%hash;
}

sub is_pair_hash
{
    # Niels Larsen, April 2005.

    # Returns a hash that tells if two RNA bases pair. The keys of the
    # hash are determined by two given strings of bases that specify 
    # allowed bases on one side of the pairing and of the other. 

    my ( $bases1,         # Bases string - OPTIONAL, default "AAUTGC"
         $bases2,         # Bases string - OPTIONAL, default "UTAACG"
         ) = @_;

    # Returns a hash.

    my ( $hash, @bases1, @bases2, $i );

    $bases1 = "AAUTGC" if not defined $bases1;
    $bases2 = "UTAACG" if not defined $bases2;

    $bases1 = (uc $bases1) . (lc $bases1) . (uc $bases1) . (lc $bases1);
    $bases2 = (uc $bases2) . (lc $bases2) . (lc $bases2) . (uc $bases2);

    for ( $i = 0; $i < length $bases1; $i++ )
    {
        $hash->{ substr $bases1, $i, 1 }->{ substr $bases2, $i, 1 } = 1;
    }

    return wantarray ? %{ $hash } : $hash;
}

sub is_pair_hash_ag
{
    # Niels Larsen, April 2005.

    # Returns a hash that tells if two RNA bases pair. Watson-Crick
    # pairs and A-G pairs are considered pairs, the rest not.

    # Returns a hash.

    return &Ali::Struct::is_pair_hash( "AAUTGCGA",
                                       "UTAACGAG" );
}

sub is_pair_hash_gu
{
    # Niels Larsen, April 2005.

    # Returns a hash that tells if two RNA bases pair. Watson-Crick
    # pairs and G-U pairs are considered pairs, the rest not.

    # Returns a hash.

    return &Ali::Struct::is_pair_hash( "AAUTGCGGUT",
                                       "UTAACGUTGG" );
}

sub is_pair_hash_gu_ag
{
    # Niels Larsen, April 2005.

    # Returns a hash that tells if two RNA bases pair. Watson-Crick
    # pairs, G-U and A-G pairs are considered pairs, the rest not.

    # Returns a hash.

    return &Ali::Struct::is_pair_hash( "AAUTGCGGUTAG",
                                       "UTAACGUTGGGA" );
}

sub is_pair_hash_wc
{
    # Niels Larsen, April 2005.

    # Returns a hash that tells if two RNA bases pair. Watson-Crick
    # pairs are considered pairs, the rest not.

    # Returns a hash.

    return &Ali::Struct::is_pair_hash( "AAUTGC",
                                       "UTAACG" );
}

sub is_uncovar_hash
{
    # Niels Larsen, April 2005.

    # Creates a hash that tells if two base pairs are different. 
    
    # Returns a hash.

    my ( @bases, $base1, $base2, $base3, $base4, 
         $b1, $b2, $b3, $b4, %hash );

    @bases = qw ( A U G C a u g c );

    foreach $base1 ( @bases )
    {
        $b1 = uc $base1;

        foreach $base2 ( @bases )
        {
            $b2 = uc $base2;

            foreach $base3 ( @bases )
            {
                $b3 = uc $base3;

                foreach $base4 ( @bases )
                {
                    $b4 = uc $base4;

                    if ( ( $b1 ne $b3 and $b2 eq $b4 ) or ( $b1 eq $b3 and $b2 ne $b4 ) )
                    {
                        if ( not ( $b1 eq "G" and $b2 eq "C" and $b3 eq "G" and $b4 eq "U" ) and
                             not ( $b1 eq "G" and $b2 eq "U" and $b3 eq "G" and $b4 eq "C" ) and
                             not ( $b1 eq "C" and $b2 eq "G" and $b3 eq "U" and $b4 eq "G" ) and 
                             not ( $b1 eq "U" and $b2 eq "G" and $b3 eq "C" and $b4 eq "G" ) )
                        {
                            $hash{ $base1 }{ $base2 }{ $base3 }{ $base4 } = 1;
                        }
                    }
                }
            }
        }
    }

    return wantarray ? %hash : \%hash;
}

sub score_column_covar
{
    # Niels Larsen, April 2005.

    # Returns a ratio between 0 and 1 that reflects the degree of basepair 
    # double-shifts versus single-shifts. NEEDS REWRITE - exploit PDL or C
    # for speed. 

    my ( $chars1,     # List of characters
         $chars2,     # List of characters
         $is_cov,     
         $is_uncov,
         ) = @_;

    # Returns a number. 

    my ( $len1, $len2, $i, $j, $bases1, $bases2, $base1, $base2, $base3, 
         $base4, %sums1, %sums2, $cov_count, $uncov_count, $score, @bases1, 
         @bases2, $ratio1, $ratio2, %pair_sums, @pair_sums, @temp1, @temp2,
         $tmp );

    $is_cov = &Ali::Struct::is_covar_hash if not defined $is_cov;
    $is_uncov = &Ali::Struct::is_uncovar_hash if not defined $is_uncov;

    # This deletes all pairs that dont have two characters (where one is 
    # a gap for example),

    $bases1 = $chars1->where( ($chars2 > 64) & ($chars1 > 64) );
    $bases2 = $chars2->where( ($chars1 > 64) & ($chars2 > 64) );

    # Convert to upper case, to save time below. Works because of PDL's 
    # "threading" and "dataflow" mechanisms.

    ${ $bases1->get_dataref } = uc ${ $bases1->get_dataref };
    ${ $bases2->get_dataref } = uc ${ $bases2->get_dataref };

    @bases1 = split "", ${ $bases1->get_dataref };
    @bases2 = split "", ${ $bases2->get_dataref };

#    if ( defined ( $tmp = $bases1->where( ($bases1 >= 97) & ($bases1 <= 122) ) ) ) {
#        $tmp -= 32;
#    }

#    if ( defined ( $tmp = $bases2->where( ($bases2 >= 97) & ($bases2 <= 122) ) ) ) {
#        $tmp -= 32;
#    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> EXPECTED RATIO <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Calculate the number of expected covariations and non-covariations
    # one would expect with the given base distributions, 

    map { $sums1{ $_ }++ } @bases1;
    map { $sums2{ $_ }++ } @bases2;

    foreach $base1 ( keys %sums1 )
    {
        foreach $base2 ( keys %sums2 )
        {
            push @pair_sums, [ $base1, $base2, $sums1{ $base1 } * $sums2{ $base2 } ];
        }
    }

    @pair_sums = sort { $b->[2] <=> $a->[2] } @pair_sums;

    $cov_count = 0;
    $uncov_count = 0;

    # Compare each pair to all other pairs once. The count of the least
    # frequent pair in each comparison is added to the covariance and 
    # non-covariance counts respectively,

    for ( $i = 0; $i < $#pair_sums; $i++ )
    {
        for ( $j = $i + 1; $j <= $#pair_sums; $j++ )
        {
            $base1 = $pair_sums[$i]->[0];
            $base2 = $pair_sums[$i]->[1];
            $base3 = $pair_sums[$j]->[0];
            $base4 = $pair_sums[$j]->[1];

            if ( $is_cov->{ $base1 }->{ $base2 }->{ $base3 }->{ $base4 } )
            {
                $cov_count += $pair_sums[$j]->[2];
            }
            elsif ( $is_uncov->{ $base1 }->{ $base2 }->{ $base3 }->{ $base4 } )
            {
                $uncov_count += $pair_sums[$j]->[2];
            }
        }
    }

    if ( $cov_count == 0 ) {
        $ratio1 = 0;
    } elsif ( $uncov_count == 0 ) {
        $ratio1 = 1;
    }
    else
    {
        $ratio1 = $cov_count / ( $cov_count + $uncov_count );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OBSERVED RATIO <<<<<<<<<<<<<<<<<<<<<<<<

    @pair_sums =  ();

    # Find the number of covariations and non-covariations observed. 
    # Create a list of [ base1, base2, count ] sorted in descending order.
    # Regard G-U as G-C and vice versa,

    for ( $i = 0; $i <= $#bases1; $i++ )
    {
        $base1 = uc $bases1[$i];
        $base2 = uc $bases2[$i];

        $pair_sums{ $base1 }{ $base2 } += 1;
    }

    foreach $base1 ( keys %pair_sums )
    {
        foreach $base2 ( keys %{ $pair_sums{ $base1 } } )
        {
            push @pair_sums, [ $base1, $base2, $pair_sums{ $base1 }{ $base2 } ];
        }
    }

    @pair_sums = sort { $b->[2] <=> $a->[2] } @pair_sums;

    # Compare each pair to all other pairs once. The count of the least
    # frequent pair in each comparison is added to the covariance and 
    # non-covariance counts respectively,

    $cov_count = 0;
    $uncov_count = 0;

    for ( $i = 0; $i < $#pair_sums; $i++ )
    {
        for ( $j = $i + 1; $j <= $#pair_sums; $j++ )
        {
            $base1 = $pair_sums[$i]->[0];
            $base2 = $pair_sums[$i]->[1];
            $base3 = $pair_sums[$j]->[0];
            $base4 = $pair_sums[$j]->[1];

            if ( $is_cov->{ $base1 }->{ $base2 }->{ $base3 }->{ $base4 } )
            {
                $cov_count += $pair_sums[$j]->[2];
            }
            elsif ( $is_uncov->{ $base1 }->{ $base2 }->{ $base3 }->{ $base4 } )
            {
                $uncov_count += $pair_sums[$j]->[2];
            }
        }
    }

    if ( $cov_count == 0 ) {
        $ratio2 = 0;
    } elsif ( $uncov_count == 0 ) {
        $ratio2 = 1;
    }
    else
    {
        $ratio2 = $cov_count / ( $cov_count + $uncov_count );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CREATE SCORE <<<<<<<<<<<<<<<<<<<<<<<<<

    # Let the score be the difference between observed and expected
    # covariance ratios. A difference of 0.33 or better looks great, so 
    # to create a reasonable spread between 0 and 1 we multiply by 
    # 3,

    if ( $ratio2 > $ratio1 )
    {
        $score = $ratio2 - $ratio1;
        $score *= 2;
        $score = 1.0 if $score > 1;
    }
    else {
        $score = 0;
    }

    return $score;
}

sub sum_covar_scores
{
    my ( $scores,
         ) = @_;

    my ( $score );

    $score = 1 - $scores->[0];

    map { $score *= 1 - $_ } @{ $scores }[ 1 .. $#{ $scores } ];
        
    return 1 - $score;
}

sub score_pairing_covar
{
    # Niels Larsen, January 2006.

    # Creates a covariation score for a given pairing. Each column pair in 
    # the pairing is scored separately and then the scores are simply multiplied
    # to give the result score. A list of scores is returned. 

    my ( $ali,         # Alignment
         $pair,        # [ beg5, end5, beg3, end3 ]
         $rows,        # Row list or PDL - OPTIONAL, default all
         $is_cov,      # Covariation hash - OPTIONAL
         $is_uncov,    # Non-covariation hash - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $i, $j, $coli, $colj, $seqs, @scores, $score );

    if ( not defined $rows ) {
        $rows = [ 0 .. $ali->max_col ];
    }

    if ( not defined $is_cov ) {
        $is_cov = &Ali::Struct::is_covar_hash();
    }

    if ( not defined $is_uncov ) {
        $is_uncov = &Ali::Struct::is_uncovar_hash();
    }

    $i = $pair->[0];
    $j = $pair->[3];
    
    $seqs = $ali->seqs;

    $coli = $seqs->dice( [ $i ], $rows );
    $colj = $seqs->dice( [ $j ], $rows );

    @scores = &Ali::Struct::score_column_covar( $coli, $colj, $is_cov, $is_uncov );

    $i += 1;
    $j -= 1;

    while ( $i <= $pair->[1] )
    {
        $coli = $seqs->dice( [ $i ], $rows );
        $colj = $seqs->dice( [ $j ], $rows );

        push @scores, &Ali::Struct::score_column_covar( $coli, $colj, $is_cov, $is_uncov );

        $i += 1;
        $j -= 1;
    }

    return wantarray ? @scores : \@scores;
}

1;

__END__

