package Ali::Patterns;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions that relate to patterns somehow.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use List::Util;

use Common::Config;
use Common::Messages;

use Ali::Import;
use Ali::Common;
use Ali::Struct;

use RNA::Import;
use Seq::Common;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_pattern
                 &create_pattern_file
                 &create_pattern_files
                 &create_pattern_list
                 &create_pattern_patscan
                 &create_pattern_rnafold
                 &default_params
                 &default_params_list
                 &get_mispairs
                 &get_pairing_counts
                 &get_pairing_lengths
                 &get_column_base_distrib
                 &get_span_length_distrib
                 );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONSTANTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use constant PROP_BEG1 => 0;
use constant PROP_END1 => 1;
use constant PROP_BEG2 => 2;
use constant PROP_END2 => 3;
use constant PROP_TYPE => 4;
use constant PROP_ID => 5;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_pattern
{
    # Niels Larsen, July 2010.
    
    # Attempts to derive a pattern or consensus from an alignment.
    # It creates "pins" where there are conserved columns or pairings
    # and connects these with "rubberbands". 
    # 
    # WARNING: the routine is unfinished and in flux. 

    my ( $ali,        # File name or alignment structure 
         $args,       # Arguments hash - OPTIONAL
         $msgs,       # Warning messages - OPTIONAL
         ) = @_;

    # Returns a string.
    
    my ( $pats, $text );

    if ( not ref $ali ) {
        $ali = &Ali::Import::read( $ali, $args->{"format"} );
    }

    $pats = &Ali::Patterns::create_pattern_list( $ali, $args, $msgs );

    $text = &Ali::Patterns::create_pattern_patscan( $pats );

    return $text;
}

sub create_pattern_file
{
    # Niels Larsen, March 2006.

    # Creates scan_for_matches pattern files from the alignment files found
    # in a given directory. The files get the same name as the alignments, 
    # but with .pattern as suffix. Returns the number of alignments processed.

    my ( $a_file,         # Alignment file
         $p_file,         # Pattern file
         $args,              
         $msgs,             # Messages returned - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( $ali, $file, $text, @warnings, $warning, $pats );

    $ali = &Ali::IO::connect_pdl( $a_file );
    $ali = &Ali::Common::de_pdlify( $ali );

    $pats = &Ali::Patterns::create_pattern_list( $ali, $args, \@warnings );

    if ( @warnings )
    {
        foreach $warning ( @warnings )
        {
            push @{ $msgs }, [ "Warning", qq (In $file->{"name"}: $warning) ];
        }
        
        @warnings = ();
    }
    
    $text = &Ali::Patterns::create_pattern_patscan( $pats );

    if ( not $args->{"readonly"} )
    {
        &Common::File::delete_file_if_exists( $p_file );
        &Common::File::write_file( $p_file, $text );
    }

    return;
}

sub create_pattern_files
{
    # Niels Larsen, March 2006.

    # Creates scan_for_matches pattern files from the alignment files in a
    # given list. The pattern files are written in scan_for_matches format
    # (suffix .patscan) and RNAFold constraint format (suffix .rnafold) and
    # put in a given directory. Returns the number of alignments processed.

    my ( $a_files,         # Alignment file list
         $o_dir,           # Pattern output directory
         $args,            # Pattern match settings 
         $msgs,            # Messages returned - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $a_file, $o_file, $ali, $pats, @msgs, $msg, $patscan,
         $rnafold, $name );

    &Common::File::create_dir_if_not_exists( $o_dir );

    foreach $a_file ( @{ $a_files } )
    {
        &echo( qq (   Extracting from $a_file->{'name'} to ... ) );

        if ( $args->{"format"} eq "pdl" )
        {
            $ali = &Ali::IO::connect_pdl( $a_file->{"path"} );
            $ali = &Ali::Common::de_pdlify( $ali );
        }
        else
        {
            $ali = &Ali::Import::read( $a_file->{"path"}, $args->{"format"} );
        }
    
        # Create a list of hashes with pattern descriptions, 

        $pats = &Ali::Patterns::create_pattern_list( $ali, $args, \@msgs );
        
        if ( @msgs )
        {
            foreach $msg ( @msgs )
            {
                push @{ $msgs }, [ "Warning", qq (In $a_file->{"name"}: $msg) ];
            }
            
            @msgs = ();
        }

        # Cast pattern descriptions into text that scan_for_matches 
        # uses as input, and as an RNAfold contraints line,

        $patscan = &Ali::Patterns::create_pattern_patscan( $pats );

        # Write to files,

        if ( not $args->{"readonly"} )
        {
            $name = $a_file->{"name"};
            $name =~ s/\.[^.]+$//;

            $o_file = "$o_dir/$name.pattern";

            &Common::File::delete_file_if_exists( $o_file );
            &Common::File::dump_file( $o_file, $pats );

            $o_file = "$o_dir/$name.patscan";

            &Common::File::delete_file_if_exists( $o_file );
            &Common::File::write_file( $o_file, $patscan );
        }

        &echo_green( qq ($name.patscan\n) );
    }
    
    return;
}

sub create_pattern_list
{
    # Niels Larsen, May 2005.

    # Attempts to derive a scan_for_matches pattern from an un-pdlified alignment.
    # It creates "pins" where there are conserved columns or pairings and connects 
    # these with "rubberbands". A number of switches and settings are given in 
    # $args - TODO: explain these.   IN FLUX

    my ( $ali,        # Alignment object
         $args,       # Arguments hash - OPTIONAL
         $msgs,      # Warning messages - OPTIONAL
         ) = @_;

    # Returns a string.

    my ( $pair_rule, @weights, $base1, $base2, $prop, $i, $j, $unit, $pair_tot,
         $colmax, $rowmax, $is_base, $params, $freqs, $freq, @pats, $len, @cols,
         $beg1, $end1, $beg2, $end2, @mask, $lengths, $sum, $file, $factor,
         @freqs, $pat, $text, $stats, $mispairs, @text, $comment, @matrix, @pcts,
         %pcts, $min_seqs, $base, $bases, $tuple, @lengths, $length, $count,
         $minlen, $maxlen, $rows, $id, %pair_units, $date, $col, $signature, $pair,
         $iub_codes, @list, $pct, $mis, $ins, $del, $minsum, $row, $maxsum, $def_params,
         $avglen, $max_sum, @weight, $string, $weight, @pair_rule, $pair_mis,
         %pair_rule, $pair_ok, $uneven_rows, $pairs_total, $mispairs_total, $diff,
         $colend, $is_pair, @masks, $seq, $pairs, $len5, $len3, $alilen, $ali_sids,
         $pat5, $pat3, $min, $max, $ins_seqs, $del_seqs, $mis_seqs, $seqs, $ali_seqs,
         %quals, @quals, @seq5, @seq3, $type, $qual, $min_seqs_2, $ali_masks, $mask,
         $is_rna_base, $is_dna_base );

    # >>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $is_pair = &Ali::Struct::is_pair_hash_gu();
    $is_base = &Seq::Common::alphabet_hash("nuc");
    $iub_codes = &Seq::Common::iub_codes_chars( $ali->datatype );

    $args = {} if not defined $args;

    $ali_sids = $ali->sids;
    $ali_seqs = $ali->seqs;
    $ali_masks = $ali->pairmasks;

    $def_params = &Ali::Patterns::default_params();
    $params = &Common::Util::merge_params( $def_params, $args );

    $alilen = &List::Util::max( map { length $_ } @{ $ali_seqs } );

    if ( $args->{"cols"} )
    {
        @cols = ( eval $args->{"cols"} );
        @cols = map { $_ - 1 } @cols;

        @mask = ( 1 ) x $alilen;

        foreach $col ( @cols ) {
            $mask[ $col ] = 0;
        }
    }
    else {
        @cols = ( 0 .. $alilen-1 );
        @mask = ( 0 ) x $alilen;
    }

    $colmax = $#mask;
    $rowmax = $#{ $ali_seqs };
    $rows = $rowmax + 1;

    $mask = $ali_masks->[0]->[2];

    $pairs = &RNA::Import::parse_pairmask( $mask, $msgs );

    $min_seqs = $params->{"min_seqs"} * $rows / 100;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PAIRINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If a property list is given, look at the pairing elements of it and
    # get statistics from the alignment positions, and make pairing rules,

    if ( $pairs )
    {
        $id = 1;

        foreach $prop ( sort { $a->[PROP_BEG1] <=> $b->[PROP_BEG1] } @{ $pairs } )
        {
            if ( $prop->[PROP_TYPE] =~ /^helix|pseudo$/ )
            {
                $beg1 = $prop->[PROP_BEG1];
                $end1 = $prop->[PROP_END1];
                $beg2 = $prop->[PROP_BEG2];
                $end2 = $prop->[PROP_END2];

                # Skip if any part of the pairing is outside selected region,

                if ( grep { $_ == 1 } @mask[ $beg1..$end1 ] or 
                     grep { $_ == 1 } @mask[ $beg2..$end2 ] )
                {
                    next;
                }

                # Initialize information for the two pattern elements that make
                # up the pairing. Below we will add more information and then
                # push each onto a list,

                $pat5 = 
                {
                    "id" => $id,
                    "type" => $prop->[PROP_TYPE],
                    "side" => "5",
                    "beg1" => $beg1,
                    "end1" => $end1,
                    "beg2" => $beg2,
                    "end2" => $end2,
                };

                $pat3 = 
                {
                    "id" => $id,
                    "type" => $prop->[PROP_TYPE],
                    "side" => "3",
                    "beg1" => $beg2,
                    "end1" => $end2,
                    "beg2" => $beg1,
                    "end2" => $end1,
                };

                # >>>>>>>>>>>>>>>>>>>>> GET LENGTH DIVERSITY <<<<<<<<<<<<<<<<<<<<<

                # Add length information. We do this to accomodate pairings of 
                # different length. But if we accomodate all observed lengths there
                # will be many patterns like p1=0...9 ~p1, which will match too 
                # much. So below we try to extract the lengths that will accomodate
                # most sequences. By "most" we mean $params->{"min_seqs"} pct
                # of them. 

                if ( $params->{"use_observed"} ) 
                {
                    $lengths = &Ali::Patterns::get_pairing_lengths( $ali_seqs, $beg1, $end1, $beg2, $end2, $is_base );
                    $length = $lengths->[0];
                
                    $minlen = &List::Util::min( $length->[0], $length->[1] );
                    $maxlen = &List::Util::max( $length->[0], $length->[1] );
                    
                    $seqs = scalar @{ $length->[2] };
                    
                    $i = 1;
                    
                    while ( $i <= $#{ $lengths } and $seqs < $min_seqs )
                    {
                        $length = $lengths->[$i];
                        
                        $min = &List::Util::min( $length->[0], $length->[1] );
                        $max = &List::Util::min( $length->[0], $length->[1] );
                        
                        $minlen = &List::Util::min( $min, $minlen );
                        $maxlen = &List::Util::max( $max, $maxlen );
                        
                        $seqs += scalar @{ $length->[2] };
                        $i += 1;
                    }
                    
                    $minlen -= ($maxlen - $minlen) * $params->{"len_relax"} / 2 / 100;
                    $minlen = &List::Util::max( 0, $minlen );
                    
                    $maxlen += ($maxlen - $minlen) * $params->{"len_relax"} / 2 / 100;
                }
                else
                {
                    $minlen = $end1 - $beg1 + 1;
                    $maxlen = $minlen;

                    $minlen -= $minlen * $params->{"len_relax"} / 2 / 100;
                    $maxlen += $maxlen * $params->{"len_relax"} / 2 / 100;
                }
                
                if ( $maxlen > $minlen * ( 100 + $params->{"max_relax"} ) / 100 )
                {
                    $avglen = ( $maxlen + $minlen ) / 2;
                    
                    $minlen = $avglen - $avglen * $params->{"max_relax"} / 100 / 2;
                    $maxlen = $avglen + $avglen * $params->{"max_relax"} / 100 / 2;
                }

                $pat5->{"minlen"} = $pat3->{"minlen"} = $minlen;
                $pat5->{"maxlen"} = $pat3->{"maxlen"} = $maxlen;
                
                # >>>>>>>>>>>>>>>>>>>>>>>>>> PAIRING STRICTNESS <<<<<<<<<<<<<<<<<<<<<<<

                $avglen = ( $maxlen + $minlen ) / 2;

                if ( $params->{"use_observed"} ) 
                {
                    # Find the number of mismatches, insertions and deletions needed to 
                    # accomodate most of the sequences. As with the length diversity above
                    # we either use a simple set value, or we accomodate the observed 
                    # mismatches, insertions and deletions.
                    
                    %quals = ();
                    @quals = ();

                    for ( $i = 0; $i <= $#{ $ali_seqs }; $i++ )
                    {
                        $row = [ split "", $ali_seqs->[$i] ];
                        
                        @seq5 = grep { $is_base->{ $_ } } @{ $row }[ $beg1 .. $end1 ];
                        @seq3 = grep { $is_base->{ $_ } } @{ $row }[ $beg2 .. $end2 ];
                        
                        $len5 = scalar @seq5;
                        $len3 = scalar @seq3;
                        
                        if ( $len5 > $len3 ) {
                            $quals{"del"}{ $len5-$len3 } += 1;
                        } elsif ( $len3 > $len5 ) {
                            $quals{"ins"}{ $len3-$len5 } += 1; 
                        } else {
                            $mis = &Ali::Patterns::get_mispairs( \@seq5, \@seq3, $is_pair );
                            $quals{"mis"}{ $mis } += 1;
                        }
                    }
                    
                    foreach $type ( "mis", "del", "ins" ) 
                    {
                        foreach $count ( keys %{ $quals{ $type } } )
                        {
                            push @quals, [ $type, $count, $quals{ $type }{ $count } ];
                        }
                    }
                    
                    @quals = sort { $a->[1] <=> $b->[1] } @quals;
                    
                    $sum = 0;
                    $ins = 0;
                    $del = 0;
                    $mis = 0;
                    
                    foreach $qual ( @quals )
                    {
                        $type = $qual->[0];
                        $count = $qual->[1];
                        $seqs = $qual->[2];
                        
                        if ( $type eq "mis" ) {
                            $mis = $count;
                        } elsif ( $type eq "ins" ) {
                            $ins = $count;
                        } elsif ( $type eq "del" ) {
                            $del = $count;
                        }
                        
                        $sum += $seqs;
                        
                        last if $sum > $min_seqs;
                    }

                    # If mis, ins, del are really low, then increase them up to their
                    # default thresholds (which themselves should be low). This wont 
                    # affect short helices but will allow a minimal number of mismatches,
                    # insertions and deletions in long helices.
                    
                    $mis = &List::Util::max( $mis, $avglen * $params->{"mis_relax"} / 100 );
                    $ins = &List::Util::max( $ins, $avglen * $params->{"ins_relax"} / 100 );
                    $del = &List::Util::max( $del, $avglen * $params->{"del_relax"} / 100 );
                }
                else
                {
                    $mis = $avglen * $params->{"mis_relax"} / 100;
                    $ins = $avglen * $params->{"ins_relax"} / 100;
                    $del = $avglen * $params->{"del_relax"} / 100;
                }

                # If there is a poor helix that needs many (mis,ins,del) then cap
                # their sum,

                $sum = $mis + $ins + $del;
                $maxsum = $avglen * $params->{"max_relax"} / 100;

                if ( $sum > $maxsum )
                {
                    $factor = $maxsum / $sum;

                    $mis *= $factor;
                    $ins *= $factor;
                    $del *= $factor;
                }

                $pat5->{"mis"} = $pat3->{"mis"} = $mis;
                $pat5->{"ins"} = $pat3->{"ins"} = $ins;
                $pat5->{"del"} = $pat3->{"del"} = $del;

                # >>>>>>>>>>>>>>>>>>>>>>>>> MAKE PAIRING RULES <<<<<<<<<<<<<<<<<<<<<<<<

                # Pairs are included in the rule so most of the sequences are included.
                # The cutoff is when there is only (100 - "min_seqs") percent sequences
                # left, or less. TODO: make switch to one can get individual rules for 
                # each pair. 

                if ( not $params->{"split_pair_rules"} )
                {
                    $stats = &Ali::Patterns::get_pairing_counts( $ali_seqs, $beg1, $end1, $beg2, $end2 );
                    $stats = [ grep { $is_base->{ $_->[0] } and $is_base->{ $_->[1] } } @{ $stats } ];

                    $pair_mis = 0;
                    $pair_tot = 0;
                    $pair_ok = 0;
                    
                    foreach $pair ( @{ $stats } )
                    {
                        $base1 = $pair->[0];
                        $base2 = $pair->[1];
                        $count = $pair->[2];

                        $pair_tot += $count;
                        
                        if ( $is_pair->{ $base1 }->{ $base2 } )
                        {
                            $pair_ok += $count;
                            $pair = undef;
                        }
                        else {
                            $pair_mis += $count;
                        }
                    }

                    @{ $stats } = grep { defined $_ } @{ $stats };

                    @pair_rule = qw ( AU GC GU );

                    if ( $stats and @{ $stats } )
                    {
                        foreach $pair ( @{ $stats } )
                        {
                            $base1 = $pair->[0];
                            $base2 = $pair->[1];
                            $count = $pair->[2];
                            
                            if ( 100 * ( $pair_ok + $count ) / $pair_tot <= ( 100 - $params->{"mis_relax"} ) )
                            {
                                push @pair_rule, uc $base1.$base2;
                                $pair_ok += $count;
                            }
                            else {
                                last;
                            }
                        }
                    }
                    
                    %pair_rule = map { $_, 1 } @pair_rule;
                    
                    foreach $pair ( keys %pair_rule )
                    {
                        ( $base1, $base2 ) = split "", $pair;
                        
                        if ( not exists $pair_rule{ $base2.$base1 } )
                        {
                            push @pair_rule, $base2.$base1;
                        }
                    }
                    
                    @pair_rule = sort @pair_rule;
                }

                $pat5->{"pair_rule"} = \@pair_rule;
                $pat3->{"pair_rule"} = \@pair_rule;

                # >>>>>>>>>>>>>>>>>>>>>> CREATE PATTERN ELEMENT INFO <<<<<<<<<<<<<<<<<<<<<<

                $len = $end1 - $beg1 + 1;

                push @pats, &Storable::dclone( $pat5 );
                push @pats, &Storable::dclone( $pat3 );

                @mask[ $beg1 .. $end1 ] = ( 1 ) x $len;
                @mask[ $beg2 .. $end2 ] = ( 1 ) x $len;
                
                $id += 1;
            }
        }
    }

    @pats = sort { $a->{"beg1"} <=> $b->{"beg1"} } @pats;

    # >>>>>>>>>>>>>>>>>>> HIGHLY CONSERVED COLUMNS <<<<<<<<<<<<<<<<<<<<

    # In this section we find all stretches of columns that are more 
    # than "min_seqs" percent conserved, and are not in pairings 
    # covered above. 

    $col = 0;

    while ( $col <= $colmax )
    {
        if ( not $mask[$col] )
        {
            # First store the base distributions of all consecutive highly
            # conserved columns that we have not looked at before,

            $freqs = &Ali::Patterns::get_column_base_distrib( $ali_seqs, $col, $is_base );

            $seqs = $freqs->[0]->[1] || 0;

            @freqs = ();
            $beg1 = $col;

            while ( $seqs >= $min_seqs )
            {
                push @freqs, &Storable::dclone( $freqs );
                
                $mask[$col] = 1;
                $col += 1;
                
                last if $col > $colmax or $mask[$col];
                
                $freqs = &Ali::Patterns::get_column_base_distrib( $ali_seqs, $col, $is_base );
                $seqs = $freqs->[0]->[1] || 0;
            }                    
            
            if ( @freqs )
            {
                # Below we compose a sequence of IUB codes that accomodate at least 
                # "min_seqs" percent of the bases in each column. Note that this does
                # not mean the sequence will match "min_seqs" of all sequences, but 
                # then we use the relaxation parameters,
                
                $pat =
                {
                    "type" => "cons_high",
                    "beg1" => $beg1,
                    "end1" => $col - 1,
                };

                $min_seqs_2 = $min_seqs + ( $rows - $min_seqs ) / 2;

                foreach $freq ( @freqs )
                {
                    $seqs = 0;
                    $bases = "";

                    foreach $tuple ( @{ $freq } )
                    {
                        $base = $tuple->[0];
                        $count = $tuple->[1];
                        
                        if ( $seqs < $min_seqs_2 ) {
                            $bases .= $base;
                        } else {
                            last;
                        }
            
                        $seqs += $count;
                    }

                    if ( defined $iub_codes->{ $bases } ) {
                        $pat->{"bases"} .= $iub_codes->{ $bases };
                    } else {
                        &error( qq (Wrong looking bases -> "$bases") );
                        exit;
                    }
                }

                # Add mismatches, but no insertions and deletions (we are in a highly
                # conserved region where usually these dont occur),

                $avglen = scalar @freqs;

                $pat->{"mis"} = int $avglen * $params->{"mis_relax"} / 100;
                $pat->{"ins"} = 0;
                $pat->{"del"} = 0;
                
                push @pats, &Storable::dclone( $pat );
            }
        }
        
        $col += 1;
    }

    @pats = sort { $a->{"beg1"} <=> $b->{"beg1"} } @pats;

    # >>>>>>>>>>>>>>>>>>>> LOW CONSERVATION COLUMNS <<<<<<<<<<<<<<<<<<<

    # Look at the columns that have not yet been included and find all
    # stretches of columns that are medium conserved,

    $col = 0;

    while ( $col <= $colmax )
    {
        if ( not $mask[$col] )
        {
            $beg1 = $col;
            
            while ( $col <= $colmax and not $mask[$col] )
            {
                $mask[$col] = 1;
                $col += 1;
            }                 

            $end1 = $col - 1;

            $lengths = &Ali::Patterns::get_span_length_distrib( $ali_seqs, $beg1, $end1, $is_base );

            if ( $lengths and $lengths->[0]->[0] > 0 )
            {
                $pat =
                {
                    "type" => "cons_low",
                    "beg1" => $beg1,
                    "end1" => $col - 1,
                };

                $minlen = $lengths->[0]->[0];
                $maxlen = $minlen;

                for ( $i = 1; $i <= $#{ $lengths }; $i++ )
                {
                    $length = $lengths->[$i]->[0];
                    
                    if ( $length < $minlen ) {
                        $minlen = $length;
                    }
                    
                    if ( $length > $maxlen ) {
                        $maxlen = $length;
                    }
                }

                
                $minlen -= int ( $minlen * $params->{"len_relax"} / 2 / 100 );
                $maxlen += int ( $maxlen * $params->{"len_relax"} / 2 / 100 );

                $pat->{"minlen"} = $minlen;
                $pat->{"maxlen"} = $maxlen;

                push @pats, &Storable::dclone( $pat );
            }
        }
        
        $col += 1;
    }

    @pats = sort { $a->{"beg1"} <=> $b->{"beg1"} } @pats;

    # >>>>>>>>>>>>>>>>>>>>>>> TRIM PATTERN ENDS <<<<<<<<<<<<<<<<<<<<<<<

    # Remove low-conservation elements from ends, since they will only
    # slow the search,

    if ( not $params->{"low_cons_ends"} )
    {
        while ( $pats[0]->{"type"} eq "cons_low" )
        {
            shift @pats;
        }
        
        while ( $pats[-1]->{"type"} eq "cons_low" ) 
        {
            pop @pats;
        }
    }

    if ( not $params->{"unpaired_ends"} )
    {
        while ( $pats[0]->{"type"} ne "helix" ) 
        {
            shift @pats;
        }
        
        while ( $pats[-1]->{"type"} ne "helix" ) 
        {
            pop @pats;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>> NUMBER ALL PATTERN UNITS <<<<<<<<<<<<<<<<<<<

    $unit = 0;

    foreach $pat ( @pats )
    {
        if ( $pat->{"type"} =~ /^helix|pairing$/ )
        {
            if ( $pat->{"side"} eq "5" )
            {
                $pat->{"unit"} = ++$unit;
                $pair_units{ $pat->{"id"} } = $pat->{"unit"};
            }
            else {
                $pat->{"unit"} = $pair_units{ $pat->{"id"} };
            }
        }
        else {
            $pat->{"unit"} = ++$unit;
        }
    }

    return wantarray ? @pats : \@pats;
}

sub create_hairpin_fold_template
{
    # Niels Larsen, June 2006.

    # Creates an RNAfold mask from a list of pattern elements and a string
    # of sub-sequences as they come out of scan_for_matches. The pattern 
    # elements are produced by &Ali::Patterns::create_pattern_list, and 
    # the string should look like so: "AG GG ATCT CC A ATGG". The center
    # of the (first) loop is found and everything the left and right of 
    # that center is filled with "<" and ">" characters. The output may
    # look like so: ">>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<". 

    my ( $pats,       # List of pattern hashes
         $seqs,       # String of space-separated sub-sequences
         ) = @_;

    # Returns a string. 

    my ( $pat, $seq, $str, $len, $i, $j, $cpos, $end1, $beg2 );

    if ( not ref $seqs eq "ARRAY" ) {
        $seqs = [ split / /, $seqs ];
    }

    if ( scalar @{ $seqs } ne scalar @{ $pats } )
    {
        $i = scalar @{ $pats };
        $j = scalar @{ $seqs };

        &error( qq (The number of pattern elements are $i, but there are $j subsequences) );
        exit;
    }

    $str = "";
    $len = 0;

    for ( $i = 0; $i <= $#{ $pats }; $i++ )
    {
        $pat = $pats->[$i];
        $seq = $seqs->[$i];

        $len += length $seq;

        if ( $pat->{"type"} eq "helix" )
        {
            if ( $pat->{"beg1"} < $pat->{"beg2"} ) {
                $end1 = $len;
            } elsif ( not defined $beg2 ) {
                $beg2 = $len;
            }
        }
    }

    $cpos = $end1 + int ( ( $beg2 - $end1 ) / 2 );

    $str = "<" x $cpos;
    $str .= ">" x ( $len - $cpos );

    if ( $str ) {
        return $str;
    } else {
        return;
    }
}

sub create_pattern_patscan
{
    # Niels Larsen, June 2005.

    # Formats the list of pattern hashes to a text that scan_for_matches
    # uses as input. 

    my ( $pats,       # List of pattern elements
         ) = @_;

    # Returns a string. 

    my ( $unit, $pat, $pair_rule, @text, $beg1, $end1, $beg2, $end2, 
         $comment, @list, $signature, $date, $text, $len, $rcount );


    # >>>>>>>>>>>>>>>>>>>>> WRITE PATTERN TEXT <<<<<<<<<<<<<<<<<<<<<<<<

    # We now use the statistics collected from the alignment to make
    # pattern units that reasonably describe the sequences in it. 

    @text = ();
    $rcount = 0;

    foreach $pat ( @{ $pats } )
    {
        if ( $pat->{"type"} =~ /^pairing|helix$/ and $pat->{"side"} eq "5" )
        {
            $unit = $pat->{"unit"};
            $rcount += 1;

            $pair_rule = "r$rcount={". (join ",", @{ $pat->{"pair_rule"} }) ."}";

            push @text, [ "", "", $pair_rule, "  % Pairing rule" ];
        }
    }

    push @text, [ "", "", "", "" ];
    $rcount = 0;

    foreach $pat ( @{ $pats } )
    {
        $beg1 = $pat->{"beg1"};
        $end1 = $pat->{"end1"};
        $beg2 = $pat->{"beg2"};
        $end2 = $pat->{"end2"};

        $len = $end1 - $beg1 + 1;
        $unit = $pat->{"unit"};

        if ( $pat->{"type"} =~ /^pairing|helix$/ )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>> PAIRINGS <<<<<<<<<<<<<<<<<<<<<<<<

            if ( $pat->{"side"} eq "5" )
            {
                $comment = "Pairing \(5\'\) ";
                $comment .= ($beg1+1) ."-". ($end1+1) ."/". ($beg2+1) ."-". ($end2+1);

                $pat->{"minlen"} = &Common::Util::ceil( $pat->{"minlen"} );
                $pat->{"maxlen"} = int $pat->{"maxlen"};

                push @text, [ "p$unit", "=", qq ($pat->{"minlen"}...$pat->{"maxlen"}), "  \% $comment" ];
            }
            elsif ( $pat->{"side"} eq "3" )
            {
                $comment = "Pairing \(3\'\) ";
                $comment .= ($beg1+1) ."-". ($end1+1) ."/". ($beg2+1) ."-". ($end2+1);

                $rcount += 1;

                if ( grep { $_ >= 1 } ( $pat->{"mis"}, $pat->{"del"}, $pat->{"ins"} ) )
                {
                    $pat->{"mis"} = int $pat->{"mis"};
                    $pat->{"ins"} = int $pat->{"ins"};
                    $pat->{"del"} = int $pat->{"del"};

                    push @text, [ "", "", qq (r$rcount~p$unit\[$pat->{"mis"},$pat->{"del"},$pat->{"ins"}\]), "  \% $comment" ];
                }
                elsif ( grep { $_ >= 0.5 } ( $pat->{"mis"}, $pat->{"del"}, $pat->{"ins"} ) )
                {
                    @list = ();
                    
                    push @list, qq (r$rcount~p$unit\[1,0,0\]) if $pat->{"mis"} >= 0.5;
                    push @list, qq (r$rcount~p$unit\[0,1,0\]) if $pat->{"del"} >= 0.5;
                    push @list, qq (r$rcount~p$unit\[0,0,1\]) if $pat->{"ins"} >= 0.5;
                    
                    if ( scalar @list == 1 ) {
                        push @text, [ "", "", $list[0], "  \% $comment" ];
                    } elsif ( scalar @list == 2 ) {
                        push @text, [ "", "", "( $list[0] | $list[1] )", "  \% $comment" ];
                    } else {
                        push @text, [ "", "", "( $list[0] | ( $list[1] | $list[2] ) )", "  \% $comment" ];
                    }
                }
                else
                {
                    push @text, [ "", "", qq (r$rcount~p$unit\[0,0,0\]), "  \% $comment" ];
                }
            }
        }
        elsif ( $pat->{"type"} eq "cons_high" )
        {
            # >>>>>>>>>>>>>>>>>>>>>> HIGH CONSERVATION <<<<<<<<<<<<<<<<<<<

            $comment = "   ". ($beg1+1) ."-". ($end1+1);

            if ( $pat->{"mis"} == 0 and $pat->{"del"} == 0 and $pat->{"ins"} == 0 ) {
                push @text, [ "p$unit", "=", $pat->{"bases"}, "  \% $comment" ];
            } else {
                push @text, [ "p$unit", "=", qq ($pat->{"bases"}\[$pat->{"mis"},$pat->{"del"},$pat->{"ins"}\]), "  \% $comment" ];
            }
        }
        elsif ( $pat->{"type"} eq "cons_low" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>> RUBBER BANDS <<<<<<<<<<<<<<<<<<<<<<

            # Create "any" pattern,

            $comment = "   ". ($beg1+1) ."-". ($end1+1);
            push @text, [ "p$unit", "=", qq ($pat->{"minlen"}...$pat->{"maxlen"}), "  \% $comment" ];
        }
        else {
            &error( qq (Wrong looking pairing type -> "$pat->{'type'}") );
            exit;
        }
    }

    $signature = &Common::Config::get_signature();
    $date = &Common::Util::epoch_to_time_string();

    $text = qq (%
% AUTO-GENERATED PATTERN for scan_for_matches
%
% Author: a perl routine written by $signature 
%
% Date: $date
%
% Scan_for_matches (patscan), written by Ross Overbeek, is a good
% pattern matcher and this file can be used as its input:
%
% scan_for_matches this.file < sequences.fasta
%
);

    $text .= &Common::Tables::render_ascii( \@text );

    $text .= qq (

% The lines above form a "chain" of pattern units, that are moved
% along the DNA/RNA sequence. For the pattern to match, every unit
% (p1, p2, and so on) must match. There are three different units,
%
% 1. Rubber bands, like 7...10. This means any 7, 8, 9 or 10 bases
%    will match. These cover the most variable regions. 
%
% 2. Consensus patterns, like {(78,14,7,0),(64,0,0,28)} > 121. This
%    pattern gives score for A, C, G and T(U) respectively. The idea
%    is that we can say that stretch of bases must match reasonably
%    well to the consensus patterns observed. 
%
% 3. Pairings, like p2=4...5 and further down perhaps r1~p2[1,0,0].
%    This means there has to be a pairing of 4 or 5 bases, with one
%    mismatch allowed. 
%
% but scan_for_matches understands many more. For a much better 
% explanation, please see
% 
% http://www-unix.mcs.anl.gov/compbio/PatScan/HTML
%
);

    return $text;
}

# sub create_hairpin_mask
# {
#     # Niels Larsen, June 2006.

#     # Formats the list of pattern hashes to a string that RNAfold uses
#     # to constrain its folding. The second argument is a string of matched 
#     # sub-sequences as it comes from scan_for_matches, like so: 
#     # "AG GG ATCT CC A ATGG". 

#     my ( $pats,       # List of pattern hashes
#          $seqs,       # String of space-separated sub-sequences
#          ) = @_;

#     # Returns a string. 

#     my ( $pat, $seq, $str, $len, $i, $j );

#     if ( not ref $seqs eq "ARRAY" ) {
#         $seqs = [ split / /, $seqs ];
#     }

#     if ( scalar @{ $seqs } ne scalar @{ $pats } )
#     {
#         $i = scalar @{ $pats };
#         $j = scalar @{ $seqs };

#         &error( qq (The number of pattern elements are $i, but there are $j subsequences) );
#         exit;
#     }

#     $str = "";

#     for ( $i = 0; $i <= $#{ $pats }; $i++ )
#     {
#         $pat = $pats->[$i];
#         $seq = $seqs->[$i];

#         if ( $pat->{"type"} eq "helix" )
#         {
#             if ( $pat->{"beg1"} < $pat->{"beg2"} ) {
#                 $str .= "<" x length $seq;
#             } else {
#                 $str .= ">" x length $seq;
#             }
#         }
#         elsif ( $seq ) {
#             $str .= "x" x length $seq;
#         }
#     }
    
#     if ( $str ) {
#         return $str;
#     } else {
#         return;
#     }
# }

sub default_params
{
    my ( $defs );

    $defs = { map { $_->[0] => $_->[1] } &Ali::Patterns::default_params_list() };

    return wantarray ? %{ $defs } : $defs;
}

sub default_params_list
{
    my ( @list );

    @list = (
        [ "min_seqs", 90, "pct sequences that must match" ],
        [ "len_relax", 30, "pct extra length allowance" ],
        [ "mis_relax", 20, "pct extra mismatch allowance" ],
        [ "ins_relax", 10, "pct extra insertion allowance" ],
        [ "del_relax", 10, "pct extra deletion allowance" ],
        [ "max_relax", 40, "pct max relax sum (mis+ins+del)" ],
        [ "use_observed", 1, "use actual topology" ],
        [ "split_pair_rules", 0, "one rule per pair or not" ],
        [ "low_cons_ends", 0, "include variable pattern ends" ],
        [ "unpaired_ends", 0, "include unpaired pattern ends" ],
        );

    return wantarray ? @list : \@list;
}

sub get_mispairs
{
    my ( $seq5,
         $seq3,
         $is_pair,
         ) = @_;

    my ( $base, $i, $mispairs );

    if ( not $is_pair ) {
        $is_pair = &Ali::Struct::is_pair_hash_gu();
    }
    
    $i = $#{ $seq3 };
    $mispairs = 0;

    foreach $base ( @{ $seq5 } )
    {
        $mispairs += 1 if not $is_pair->{ $base }->{ $seq3->[$i] };
        $i--;
    }

    return $mispairs;
}

sub get_pairing_counts
{
    # Niels Larsen, May 2005.

    # Given an alignment and two pairing ranges, returns a list of pairs and
    # the number of times they occur, e.g. [ "A", "U", 56 ]. All pairing 
    # positions are summed up. 

    my ( $ali,        # Alignment
         $beg5,       # 5' begin position 
         $end5,       # 5' end position
         $beg3,       # 3' begin position
         $end3,       # 3' begin position
         ) = @_;

    # Returns a hash.

    my ( $len5, $len3, $row, $col5, $col3, $seq, $ch5, $ch3, %pairs, @pairs );

    if ( $end5 - $beg5 != $end3 - $beg3 ) 
    {
        $len5 = $end5 - $beg5;
        $len3 = $end3 - $beg3;

        &error( qq (Upstream range is $len5 long, but downstream is $len3) );
        exit;
    }

    $col3 = $end3;

    %pairs = ();

    for ( $col5 = $beg5; $col5 <= $end5; $col5++ )
    {
        for ( $row = 0; $row <= $#{ $ali }; $row++ )
        {
            $seq = [ split "", $ali->[$row] ];
            
            $ch5 = $seq->[$col5];
            $ch3 = $seq->[$col3];
            
            $pairs{ uc $ch5.$ch3 }++;
        }

        $col3 -= 1;
    }

    @pairs = sort { $b->[2] <=> $a->[2] } map { [ (split "", $_), $pairs{ $_ } ] } keys %pairs;

    return wantarray ? @pairs : \@pairs;
}

sub get_pairing_lengths
{
    # Niels Larsen, May 2005.

    # Given an alignment and two pairing ranges, returns a length 
    # distribution of the potential pairings. This distribution is 
    # a list of [ no. 5-bases, no. 3-bases, list of indices ]. It
    # is sorted so the sequences with the most common lengths are
    # are the top, as element 0 of the list. 

    my ( $seqs,         # Aligned sequences
         $beg5,         # 5' begin position 
         $end5,         # 5' end position
         $beg3,         # 3' begin position
         $end3,         # 3' begin position
         $is_base,      # Hash of valid bases - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $len5, $len3, $row, $seq, @lengths, %lengths, $key );

    if ( $end5 - $beg5 != $end3 - $beg3 ) 
    {
        $len5 = $end5 - $beg5;
        $len3 = $end3 - $beg3;

        &error( qq (Upstream range is $len5 long, but downstream is $len3) );
        exit;
    }

    if ( not $is_base )
    {
        $is_base = &Seq::Common::alphabet_hash("nuc");
    }

    for ( $row = 0; $row <= $#{ $seqs }; $row++ )
    {
        $seq = [ split "", $seqs->[$row] ];
        
        $len5 = scalar grep { $is_base->{ $_ } } @{ $seq }[ $beg5 .. $end5 ];
        $len3 = scalar grep { $is_base->{ $_ } } @{ $seq }[ $beg3 .. $end3 ];

        push @{ $lengths{ $len5 ."_". $len3 } }, $row;
    }

    foreach $key ( keys %lengths )
    {
        ( $len5, $len3 ) = split "_", $key;

        push @lengths, [ $len5, $len3, $lengths{ $key } ];
    }

    @lengths = sort { scalar @{ $b->[2] } <=> scalar @{ $a->[2] } } @lengths;

    return wantarray ? @lengths : \@lengths;
}

sub get_column_base_distrib
{
    # Niels Larsen, May 2005.

    # Creates a list of bases and their counts for a given column.
    # The elements of the list are like [ 'A', 6 ], etc. The elements
    # sorted in descending order, lower case are folded into upper
    # case, and T's are converted to U's.
    
    my ( $seqs,         # Alignment
         $pos,          # Column index position
         $is_base,      # Hash of valid bases - OPTIONAL
         ) = @_;

    # Returns a list. 

    my ( $row, %freqs, @freqs, $base );

    if ( not $is_base )
    {
        $is_base = &Seq::Common::alphabet_hash("nuc");
    }

    foreach $row ( @{ $seqs } )
    {
        $base = substr $row, $pos, 1;

        if ( $is_base->{ $base } and $base !~ /^N$/i )
        {
            $freqs{ uc $base }++;
        }
    }

    if ( %freqs )
    {
        if ( exists $freqs{"T"} )
        {
            $freqs{"U"} += $freqs{"T"};
        }
        
        foreach $base ( keys %freqs )
        {
            push @freqs, [ $base, $freqs{ $base } ];
        }

        @freqs = sort { $b->[1] <=> $a->[1] } @freqs;
    }
    else
    {
        @freqs = ();
    }

    return wantarray ? @freqs : \@freqs;
}

sub get_span_length_distrib
{
    # Niels Larsen, May 2005.

    # Creates a list of sub-sequence lengths and their frequency of 
    # occurrence. The list elements are [ length, count ]. 
    
    my ( $seqs,         # Aligned sequences
         $beg,          # Column start position
         $end,          # Column end position
         $is_base,      # Hash of valid bases - OPTIONAL
         ) = @_;

    # Returns a list. 

    my ( $row, $seq, $i, @freqs, $count, %freqs );

    if ( not $is_base )
    {
        $is_base = &Seq::Common::alphabet_hash("nuc");
    }

    foreach $row ( @{ $seqs } )
    {
        $seq = [ split "", $row ];

        $count = 0;

        for ( $i = $beg; $i <= $end; $i++ )
        {
            if ( $is_base->{ $seq->[$i] } )
            {
                $count += 1;
            }
        }

        $freqs{ $count }++;
    }

    foreach $count ( keys %freqs )
    {
        push @freqs, [ $count, $freqs{ $count } ];
    }

    @freqs = sort { $b->[1] <=> $a->[1] } @freqs;

    return wantarray ? @freqs : \@freqs;
}

1;

__END__
