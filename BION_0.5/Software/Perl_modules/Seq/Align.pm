package Seq::Align;     #  -*- perl -*-

# Routines that are related to sequence alignment and matching.

use strict;
use warnings FATAL => qw ( all );

use base qw (Exporter);

our @EXPORT_OK = qw (
                     &add_gaps_to_string
                     &align_pairs
                     &align_pairs_fasta
                     &align_pairs_table
                     &align_two_nuc_seqs
                     &align_two_prot_seqs
                     &align_two_seqs
                     &check_matches
                     &clip_match
                     &clip_match_beg
                     &clip_match_end
                     &clip_matches_beg
                     &clip_matches_end
                     &create_matches
                     &create_sim
                     &get_range_locs
                     &interpolate_position
                     &is_match
                     &measure_similarity
                     &process_args
                     &score_match
                     &select_matches
                     &seq_identity_check
                     &stringify_matches
                     &trans_position
                     );

use Data::Dumper;
use Storable qw ( dclone );
use List::Util;
use Time::HiRes;

use Common::Config;
use Common::Messages;
use Common::File;

use Registry::Args;

use Seq::Common;
use Seq::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBAL CONSTANTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use constant Q_BEG => 0;
use constant Q_END => 1;
use constant S_BEG => 2;
use constant S_END => 3;
use constant LENGTH => 4;
use constant SCORE => 5;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_gaps_to_string
{
    # Niels Larsen, October 2010.

    # Creates a copy of the input string but with gaps added at the locations
    # given in the gaps argument. The g_end argument is a switch that turns on
    # or off adding gaps (if any) to the last position in the input string. 
    # Returns the number of gaps added. 

    my ( $i_str,    # Input string
         $gaps,     # Gap locations
         $o_str,    # Output string
         $g_end,    # Add last gap or not, default on
        ) = @_;

    # Returns integer. 

    my ( $i_str_pos, $str_len, $loc, $gap_pos, $gap_len, $gap_ch, $gap_sum,
         $max_pos );

    $g_end //= 1;

    $gap_sum = 0;
    $i_str_pos = 0;

    # First pairs of sub-sequence, then a gap,
    
    $max_pos = ( length ${ $i_str } ) - 1;

    foreach $loc ( @{ $gaps } )
    {
        ( $gap_pos, $gap_len, $gap_ch ) = @{ $loc };

        # Sequence up to and including the position where gap starts,

        $str_len = $gap_pos - $i_str_pos + 1;
        ${ $o_str } .= substr ${ $i_str }, $i_str_pos, $str_len; 

        # Add gaps,

        ${ $o_str } .= $gap_ch x $gap_len unless ( $gap_pos == $max_pos and not $g_end );

        # Advance sequence position,

        $i_str_pos = $gap_pos + 1;

        # Increment gap count,
        
        $gap_sum += $gap_len;
    }
    
    # Finally add whatever sequence follows, if any, the last gap in the region,
    
    if ( $i_str_pos <= $max_pos )
    {
        $str_len = $max_pos - $i_str_pos + 1;
        ${ $o_str } .= substr ${ $i_str }, $i_str_pos, $str_len;
    }

    return $gap_sum;
}

sub align_pairs
{
    # Niels Larsen, October 2010.

    # Wrapper routine for invoking pairwise sequence alignment. Input can be 
    #
    # 1. A table with rows of the form "id1<tab>seq1<tab>id2<tab>seq2". Each 
    # seq1 will be aligned with each seq2 and output will be in the same 
    # format.
    # 
    # 2. A fasta file where sequences without gaps will be aligned against the
    # last gap-containing sequence template that precedes it. The output is 
    # also fasta, where gaps have been inserted (but not in the template).
    # 
    # Output format can be either "table", "fasta" or "human".

    my ( $args,
        ) = @_;

    my ( $defs, %args, $conf, $iformat, $count, $routine, $params );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "itable" => undef,
        "ifasta" => undef,
        "ofile" => undef,
        "seqtype" => "nuc",
        "score" => 1,
        "gaps" => 1,
        "stretch" => 0,
        "collapse" => 0,
        "debug" => 0,
        "seqcheck" => 1,
        "clobber" => 0,
	"silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    %args = &Seq::Align::process_args( $args );

    $conf = bless \%args, "Registry::Args";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> VARIABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    local $Common::Messages::silent;
    $Common::Messages::silent = $args->silent;
    
    $iformat = $conf->iformat;

    $params = {
        "ifile" => $conf->ifile,
        "ofile" => $conf->ofile,
        "oformat" => $conf->oformat,
        "seqtype" => $conf->seqtype,
        "gaps" => $args->gaps,
        "stretch" => $args->stretch,
        "collapse" => $args->collapse,
        "seqcheck" => $args->seqcheck,
        "score" => $conf->score,
        "silent" => $args->silent,
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nPairwise alignment:\n) );

    if ( $args->ofile and $args->clobber ) {
        &Common::File::delete_file_if_exists( $args->ofile );
    }

    if ( $iformat eq "table" )
    {
        $count = &Seq::Align::align_pairs_table( $params );
    }
    elsif ( $iformat eq "fasta" )
    {
        $count = &Seq::Align::align_pairs_fasta( $params );
    }
    else {
        &error( qq (Bad input format -> "$iformat") );
    }

    &echo_bold( qq (Finished\n\n) );    
    
    return;
}

sub align_pairs_fasta
{
    # Niels Larsen, October 2010.

    # Processes a fasta file where all sequences without gaps will be aligned
    # against the last gap-containing sequence template that precedes it. The 
    # output is also fasta by default, but can be changed. The templates are 
    # never changed.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns integer.

    my ( $defs, $ifh, $ofh, $routine, $line, $idstr1, $idstr2, $seq, $count,
         $oformat, $score, $matches, $olines, $type, $tpl_seq, $seq_check, 
         $tpl_id, $tmp_seq, $seq_id, $ids_len, $ali, $gaps, $tpl_str_ref, 
         $gap_str_ref, $seq_str_ref, $tpl_gaps, $stretch, $is_match );

    $defs = {
        "ifile" => undef,
        "ofile" => undef,
        "oformat" => undef,
        "seqtype" => undef,
        "seqcheck" => 1,
        "gaps" => 1,
        "stretch" => 0,
        "collapse" => 0,
        "score" => 1,
        "silent" => 1,
    };

    $args = &Registry::Args::create( $args, $defs );

    local $Common::Messages::silent;
    $Common::Messages::silent = $args->silent;
    
    $oformat = $args->oformat;
    $score = $args->score;
    $seq_check = $args->seqcheck;
    $gaps = $args->gaps;
    $stretch = $args->stretch;

    if ( $args->seqtype =~ /^nuc|rna|dna$/i )
    {
        $routine = "Seq::Align::align_two_nuc_seqs";
        $is_match = &Seq::Common::match_hash_nuc();
    }
    else
    {
        $routine = "Seq::Align::align_two_prot_seqs";
        $is_match = &Seq::Common::match_hash_prot();
    }

    $ifh = &Common::File::get_read_handle( $args->ifile );
    $ofh = &Common::File::get_write_handle( $args->ofile );

    $count = 0;

    while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
    {
        # >>>>>>>>>>>>>>>>>>>>>>> SEQUENCE WITH GAPS <<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $seq->count_gaps > 0 )
        {
            $tpl_seq = $seq;

            if ( $oformat eq "fasta" ) {
                $ofh->print( ">". $tpl_seq->id ."\n". $tpl_seq->seq ."\n" );
            }

            # If template gaps asked for, extract gaps from template sequence
            # and put them into a gaps field. If no template gaps, delete them
            # irreversibly,

            if ( $gaps ) {
                $tpl_seq->splice_gaps;
            } else {
                $tpl_seq->delete_gaps;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>> SEQUENCE WITHOUT GAPS <<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( defined $tpl_seq )
        {
            ( $idstr1, $idstr2 ) = ( $seq->id, $tpl_seq->id );

            &echo( qq (   $idstr1 versus $idstr2 ... ) );

            # Always remove gaps from unaligned sequence,

            $seq->delete_gaps;

            # Align,

            {
#                my $start = [ &Time::HiRes::gettimeofday() ]; 

                no strict "refs";
                $matches = &{ $routine }( \$tpl_seq->seq, \$seq->seq, undef, { "max_score" => $score } );

#                my $stop = [ &Time::HiRes::gettimeofday() ]; 
#                my $diff = &Time::HiRes::tv_interval( $start, $stop );

#                &dump( $diff );
            }

            # Create gapped strings,

            ( $tpl_str_ref, $gap_str_ref, $seq_str_ref ) = 
                &Seq::Align::stringify_matches( $matches, \$tpl_seq->seq, \$seq->seq, $is_match, $tpl_seq->gaps );

            # Check sequence identity,

            if ( $seq_check )
            {
                &Seq::Align::seq_identity_check( $tpl_seq, $tpl_str_ref );
                &Seq::Align::seq_identity_check( $seq, $seq_str_ref );
            }

            # Use original template if not "stretch",

            if ( not $stretch )
            {
                $tmp_seq = &Storable::dclone( $tpl_seq );
                $tmp_seq->embed_gaps if $gaps;
                
                $tpl_str_ref = \$tmp_seq->seq;
            }

            # Print out,

            if ( $oformat eq "fasta" )
            {
                $ofh->print( ">". $seq->id ."\n". ${ $seq_str_ref } ."\n" );
            }
            elsif ( $oformat eq "debug" )
            {
                ( $tpl_id, $seq_id ) = ( $tpl_seq->id, $seq->id );
                
                $ids_len = &List::Util::max( length $tpl_id, length $seq_id );

                $ofh->print( "\n" );
                $ofh->print( ( sprintf "%$ids_len"."s", $tpl_id ) ." ${ $tpl_str_ref }\n" );
                $ofh->print( " " x $ids_len ." ${ $gap_str_ref }\n" );
                $ofh->print( ( sprintf "%$ids_len"."s", $seq_id ) ." ${ $seq_str_ref }\n" );
                $ofh->print( "\n" );
            }
            else {
                &error( qq (Wrong looking output format -> "$oformat") );
            }
                
            &echo_green( "done\n" );
        }
        else {
            &error( qq (No template found - does the file begin with an unaligned sequence?) );
        }
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    return $count;
}

sub align_pairs_table
{
    # Niels Larsen, August 2010.

    # Aligns pairs of sequences given as a table with these rows:
    # id1<tab>seq1<tab>id2<tab>seq2
    # and writes them to file or STDOUT in the same form, but with the 
    # sequences globally aligned. Returns the number of table rows 
    # processed. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns integer.

    my ( $defs, $ifh, $ofh, $routine, $line, $tpl_id, $tpl_str, $seq_id, $seq_str,
         $tpl, $seq, $tpl_str_ref, $gap_str_ref, $seq_str_ref, $count, $oformat, 
         $score, $matches, $seq_check, $gaps, $stretch, $tmp_seq, $ids_len,
         $is_match );

    $defs = {
        "ifile" => undef,
        "ofile" => undef,
        "oformat" => undef,
        "seqtype" => "nuc",
        "seqcheck" => 1,
        "gaps" => 0,
        "stretch" => 0,
        "collapse" => 0,
        "score" => 1,
        "silent" => 1,
    };

    $args = &Registry::Args::create( $args, $defs );

    local $Common::Messages::silent;
    $Common::Messages::silent = $args->silent;
    
    $oformat = $args->oformat;
    $score = $args->score;
    $seq_check = $args->seqcheck;
    $gaps = $args->gaps;
    $stretch = $args->stretch;

    if ( $args->seqtype =~ /^nuc|rna|dna$/i )
    {
        $routine = "Seq::Align::align_two_nuc_seqs";
        $is_match = &Seq::Common::match_hash_nuc();
    }
    else
    {
        $routine = "Seq::Align::align_two_prot_seqs";
        $is_match = &Seq::Common::match_hash_prot();
    }

    $ifh = &Common::File::get_read_handle( $args->ifile );
    $ofh = &Common::File::get_write_handle( $args->ofile );

    $count = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$/ )
        {
            ( $tpl_id, $tpl_str, $seq_id, $seq_str ) = ( $1, $2, $3, $4 );

            # &dump("$tpl_id, $tpl_str, $seq_id, $seq_str");

            $tpl = Seq::Common->new({ "id" => $tpl_id, "seq" => $tpl_str });
            $seq = Seq::Common->new({ "id" => $seq_id, "seq" => $seq_str });
            
            # &dump( $gaps );

            if ( $gaps ) {
                $tpl->splice_gaps;
            } else {
                $tpl->delete_gaps;
            }

            &echo( qq (   $seq_id versus $tpl_id ... ) );

            # Align,

            {
                no strict "refs";
                $matches = &{ $routine }( \$tpl_str, \$seq_str, undef, { "max_score" => $score } );
            }

            # Create gapped strings,

            ( $tpl_str_ref, $gap_str_ref, $seq_str_ref ) = 
                &Seq::Align::stringify_matches( $matches, \$tpl_str, \$seq_str, $is_match, $tpl->gaps );

            # Check sequence identity,

            if ( $seq_check )
            {
                &Seq::Align::seq_identity_check( $tpl, $tpl_str_ref );
                &Seq::Align::seq_identity_check( $seq, $seq_str_ref );
            }

            # Use original template if not "stretch",

            if ( not $stretch )
            {
                $tmp_seq = &Storable::dclone( $tpl );
                $tmp_seq->embed_gaps if $gaps;
                
                $tpl_str_ref = \$tmp_seq->seq;
            }

            # Print out,

            if ( $oformat eq "table" )
            {
                $ofh->print( "$tpl_id\t${ $tpl_str_ref }\t$seq_id\t${ $seq_str_ref }\n" );
            }
            elsif ( $oformat eq "debug" )
            {
                ( $tpl_id, $seq_id ) = ( $tpl->id, $seq->id );
                
                $ids_len = &List::Util::max( length $tpl_id, length $seq_id );

                $ofh->print( "\n" );
                $ofh->print( ( sprintf "%$ids_len"."s", $tpl_id ) ." ${ $tpl_str_ref }\n" );
                $ofh->print( " " x $ids_len ." ${ $gap_str_ref }\n" );
                $ofh->print( ( sprintf "%$ids_len"."s", $seq_id ) ." ${ $seq_str_ref }\n" );
                $ofh->print( "\n" );
            }
            else {
                &error( qq (Wrong looking output format -> "$oformat") );
            }
                
            &echo_green( "done\n" );
        }
        else {
            &error( qq (Wrong looking line -> "$line") );
        }

        $count += 1;
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    return $count;
}

sub align_two_nuc_seqs
{
    # Niels Larsen, February 2007.

    # Aligns two dna/rna sequences and returns a list of coordinates of where
    # they match. The work is done by Seq::Align::align_two_seqs, this
    # routine just defines default parameters and a callback function that
    # calculates the probability for a single character match.

    my ( $q_seq,      # Query sequence reference - OPTIONAL
         $s_seq,      # Subject sequence reference - OPTIONAL
         $matches,    # List of matching fragments - OPTIONAL
         $params,     # Parameters hash - OPTIONAL
         $is_match,   # Match matrix - OPTIONAL
         $q_min,      # Query sequence start position - OPTIONAL 
         $q_max,      # Query sequence end position - OPTIONAL
         $s_min,      # Subject sequence start position - OPTIONAL
         $s_max,      # Subject sequence end position - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $results, $subref, $seq1, $seq2 );

    $params ||= {};

    $params = { 
        "seedmin" => 50,
        "max_score" => 1,
        %{ $params },
        "alphabet_size" => 4,
    };

    # if ( not defined $is_match ) {
    # $is_match = &Seq::Common::match_hash_nuc();
    # }

    $subref = sub
    {
        my ( $len,
             $seq, 
             $beg, 
             $end,
             ) = @_;
        
        my ( $p, $seqlen, $subseq, %chars, $i, $ch );
        
        # Get the probability of a match from the sequence composition 
        # and raise that to the power of the length. 
        
        if ( defined ${ $seq } )
        {
            $subseq = substr ${ $seq }, $beg, $end-$beg+1;
            $seqlen = length $subseq;
            
            undef %chars; 
            
            for ( $i = 0; $i < $seqlen; $i++ )
            {
                $chars{ substr $subseq, $i, 1 }++;
            }
            
            $p = 0;
            
            foreach $ch ( qw ( a c g t u ) )
            {
                $p += ( $chars{ $ch } / $seqlen ) ** 2 if $chars{ $ch };
            }
        }
        else {
            $p = 0.25;
        }
        
        return $p;
    };

    if ( defined $q_seq and defined $s_seq )
    {
        if ( ref $q_seq ) {
            $seq1 = lc ${ $q_seq };
        } else {
            $seq1 = lc $q_seq;
        }
        
        if ( ref $s_seq ) {
            $seq2 = lc ${ $s_seq };
        } else {
            $seq2 = lc $s_seq;
        }
        
        $results = &Seq::Align::align_two_seqs( $subref, \$seq1, \$seq2, 
                                                $matches, $params, $is_match, 
                                                $q_min, $q_max, $s_min, $s_max );
    }
    else
    {
        $results = &Seq::Align::align_two_seqs( $subref, undef, undef, 
                                                $matches, $params, $is_match, 
                                                $q_min, $q_max, $s_min, $s_max );
    }        

    return wantarray ? @{ $results } : $results;
}

sub align_two_prot_seqs
{
    # Niels Larsen, February 2007.

    # Aligns two protein sequences and returns a list of coordinates of where
    # they match. The work is done by Seq::Align::align_two_seqs, this
    # routine just defines default parameters and a callback function that
    # calculates the probability for a single character match.

    my ( $q_seq,      # Query sequence reference - OPTIONAL
         $s_seq,      # Subject sequence reference - OPTIONAL
         $matches,    # List of matching fragments - OPTIONAL
         $params,     # Parameters hash - OPTIONAL
         $is_match,   # Match matrix - OPTIONAL
         $q_min,      # Query sequence start position - OPTIONAL 
         $q_max,      # Query sequence end position - OPTIONAL
         $s_min,      # Subject sequence start position - OPTIONAL
         $s_max,      # Subject sequence end position - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $results, $subref, $seq1, $seq2 );

    $params ||= {};

    $params = { 
        "seedmin" => 10,
        "max_score" => 1,
        %{ $params },
        "alphabet_size" => 20,
    };

    # if ( not defined $is_match ) {
    #     $is_match = &Seq::Common::match_hash_prot();
    # }

    $subref = sub 
    {
        my ( $len,
             $seq, 
             $beg, 
             $end,
             ) = @_;
        
        my ( $p, $seqlen, $subseq, %chars, $i, $ch );
        
        # Get the probability of a match from the sequence composition
        # and raise that to the power of the length. 
        
        if ( defined ${ $seq } )
        {
            $subseq = substr ${ $seq }, $beg, $end-$beg+1;
            $seqlen = length $subseq;
            
            undef %chars;
            
            for ( $i = 0; $i < $seqlen; $i++ )
            {
                $chars{ substr $subseq, $i, 1 }++;
            }
            
            $p = 0;
            
            foreach $ch ( qw ( g a v l i s t d n e q c u m f y w k r h p ) )
            {
                $p += ( $chars{ $ch } / $seqlen ) ** 2 if $chars{ $ch };
            }
        }
        else {
            $p = 0.05;
        }
        
        return $p;
    };

    if ( defined $q_seq and defined $s_seq )
    {
        if ( ref $q_seq ) {
            $seq1 = lc ${ $q_seq };
        } else {
            $seq1 = lc $q_seq;
        }
        
        if ( ref $s_seq ) {
            $seq2 = lc ${ $s_seq };
        } else {
            $seq2 = lc $s_seq;
        }
        
        $results = &Seq::Align::align_two_seqs( $subref, \$seq1, \$seq2, 
                                                $matches, $params, $is_match, 
                                                $q_min, $q_max, $s_min, $s_max );
    }
    else 
    {
        $results = &Seq::Align::align_two_seqs( $subref, undef, undef, 
                                                $matches, $params, $is_match, 
                                                $q_min, $q_max, $s_min, $s_max );
    }        

    return wantarray ? @{ $results } : $results;
}

sub align_two_seqs
{
    # Niels Larsen, August 2004 ->.       UNOPTIMIZED PROTOTYPE

    # BUG july 2012: inefficiency when match matrix given. To fix: add better
    # initial digestion of sequence, and reuse C routines from Simrank.pm. For
    # now the match matrix in align_two_{nuc,prot}_seqs is commented out.

    # Aligns two sequences or a list of input matches. Give it two references
    # to all-lowercase 1-2 megabyte dna sequence strings (q_seq and s_seq) and
    # it will return a list of [ q_beg, q_end, s_beg, s_end, length, score ]
    # sorted by q_beg, in perhaps one minute. The result is a global alignment 
    # where the best matches are chosen and other good ones are ignored, meaning
    # the routine will accept sequences with repeats. For the sequence mode to 
    # be interactive, feed it kilobytes instead of megabytes. If no sequences 
    # are given, a list of [ q_beg, q_end, s_beg, s_end, length ] matches must 
    # be given, and the q_min, q_max, s_min and s_max arguments must then be 
    # given as well. In this "list-only mode" then alignment happens in a 
    # fraction of a second for hundreds of matches, for thousands it still takes
    # less than a second. If both sequences and matches are given, the routine 
    # uses the matches first and then tries to resolve intervening areas by 
    # sequence. In this "sequence+list mode" the q_min, q_max, s_min and s_max
    # arguments are not needed and the run-time depends on the data (but is 
    # usually much shorter than in "sequence-only" mode.)

    my ( $subref,
         $q_seq,      # Query sequence reference - OPTIONAL
         $s_seq,      # Subject sequence reference - OPTIONAL
         $matches,    # List of matching fragments - OPTIONAL
         $params,     # Parameters hash - OPTIONAL
         $is_match,   # Match matrix - OPTIONAL
         $q_min,      # Query sequence start position - OPTIONAL 
         $q_max,      # Query sequence end position - OPTIONAL
         $s_min,      # Subject sequence start position - OPTIONAL
         $s_max,      # Subject sequence end position - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $i, %s_begs, $q_pos, $s_pos, $q_beg, $s_beg, $q_end, $s_end,
         $match, @chain, $count, $q_try, $s_try, @long_matches, $dummy,
         @lock_matches, $best_match, $w_len, $q_word, %skip, $lock_match,
         $q_dim, $s_dim, $subseq, $matseq, @matches, @overlaps, $overlap, $elem,
         $match_in_area, $area, @l_matches, @r_matches );

    # &dump( $q_seq );
    # &dump( $s_seq );

    $params ||= {};

    $params = { 
        "seedmin" => 50,
        "alphabet_size" => 4,
        "max_score" => 1,
        %{ $params }
    };

    # &dump( $params );

    $matches = [] if not defined $matches;

    if ( not defined $q_min or not defined $s_min )
    {
        $q_min = 0;
        $s_min = 0;
    }

    if ( not defined $q_max or not defined $s_max )
    {
        if ( defined $q_seq and defined $s_seq ) 
        {
            $q_max = (length ${ $q_seq }) - 1 if not defined $q_max;
            $s_max = (length ${ $s_seq }) - 1 if not defined $s_max;
        }
        else
        {
            $q_max = &List::Util::max( map { $_->[1] } @{ $matches } );
            $s_max = &List::Util::max( map { $_->[3] } @{ $matches } );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> MATCHES GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # This section processes match candidates if given. We distinguish two 
    # kinds of matches below: those that are so long that they would never 
    # occur by chance, and then the shorter ones. We take the best of the 
    # long ones and make that part of the result, add the second best that 
    # doesnt overlap or "cross", and so on. The shorter matches are sorted 
    # by quality and the pieces in between aligned. If no matches are given,
    # a set gets generated and this routine is called on them.

    if ( @{ $matches } )
    {
        # &dump("------------- MATCHES ----------- ");

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> TRIM MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Incoming matches may not be completely embedded in the search area,
        # in which case we cannot include them in an alignment. Here we trim
        # such matches so they will all be looked at, either by length or 
        # score,

        @matches = &Seq::Align::select_matches( $matches, $q_min, $q_max, $s_min, $s_max );

        # >>>>>>>>>>>>>>>>>>>>>>> VERY LONG MATCHES ONLY <<<<<<<<<<<<<<<<<<<<<<

        # See if there are matches that are 1) very long, 2) that dont "cross" 
        # and 3) that dont overlap. If there are such compatible matches, accept
        # them for the final alignment and recurse into the spaces that separate
        # them,
        
        if ( @long_matches = grep { $_->[LENGTH] >= $params->{"seedmin"} } @matches )
        {
            # Sort by length and accept the longest,
            
            @long_matches = sort { $b->[LENGTH] <=> $a->[LENGTH] } @long_matches;
            @lock_matches = shift @long_matches;

            # Add the remaining good matches that dont "cross", that is where
            # both q_beg and s_beg are higher than the previous match element
            # in the sorted list. If two matches overlap, trim the shorter one
            # so they dont,
            
            foreach $match ( @long_matches )
            {
                if ( $match->[Q_BEG] < $lock_matches[0]->[Q_BEG] and 
                     $match->[S_BEG] < $lock_matches[0]->[S_BEG] )
                {
                    if ( $match = &Seq::Align::clip_match_end( $lock_matches[0]->[Q_BEG] - 1,
                                                                $lock_matches[0]->[S_BEG] - 1, $match ) )
                    {
                        unshift @lock_matches, $match;
                    }
                }
                elsif ( $match->[Q_END] > $lock_matches[-1]->[Q_END] and 
                        $match->[S_END] > $lock_matches[-1]->[S_END] )
                {
                    if ( $match = &Seq::Align::clip_match_beg( $lock_matches[-1]->[Q_END] + 1,
                                                                $lock_matches[-1]->[S_END] + 1, $match ) )
                    {
                        push @lock_matches, $match;
                    }
                }
                else
                {
                    for ( $i = 1; $i <= $#lock_matches; $i++ )
                    {
                        $area->[Q_BEG] = $lock_matches[$i-1]->[Q_END] + 1;
                        $area->[S_BEG] = $lock_matches[$i-1]->[S_END] + 1;
                        $area->[Q_END] = $lock_matches[$i]->[Q_BEG] - 1;
                        $area->[S_END] = $lock_matches[$i]->[S_BEG] - 1;

                        if ( $area->[Q_BEG] <= $area->[Q_END] and $area->[S_BEG] <= $area->[S_END] )
                        {
                            if ( $match_in_area = &Seq::Align::clip_match( $area, $match ) )
                            {
                                splice @lock_matches, $i, 0, &Storable::dclone( $match_in_area );
                                last;
                            }
                        }
                    }
                }
            }
            
            @lock_matches = sort { $a->[Q_BEG] <=> $b->[Q_BEG] } @lock_matches;

            # Align the pieces preceding the matches we just accepted,

            $q_beg = $q_min;
            $s_beg = $s_min;
            
            foreach $match ( @lock_matches )
            {
                # Add match to results chain,

                push @chain, $match;

                # Align the matches that fall within new search region and that has
                # a decent score,
                
                if ( $match->[Q_BEG] > $q_beg and $match->[S_BEG] > $s_beg )
                {
                    @l_matches = &Seq::Align::select_matches( \@matches, 
                                                               $q_beg, $match->[Q_BEG]-1, 
                                                               $s_beg, $match->[S_BEG]-1 );
                    
                    push @chain, &Seq::Align::align_two_seqs( $subref,
                                                              $q_seq, $s_seq, 
                                                              \@l_matches, $params, $is_match,
                                                              $q_beg, $match->[Q_BEG]-1,
                                                              $s_beg, $match->[S_BEG]-1 );
                }
                
                $q_beg = $match->[Q_END]+1;
                $s_beg = $match->[S_END]+1;
            }

            # Align the matches following the last match that we locked above,

            if ( $q_beg <= $q_max and $s_beg <= $s_max )
            {
                @r_matches = &Seq::Align::select_matches( \@matches, $q_beg, $q_max, $s_beg, $s_max );

                push @chain, &Seq::Align::align_two_seqs( $subref,
                                                          $q_seq, $s_seq, 
                                                          \@r_matches, $params, $is_match,
                                                          $q_beg, $q_max, $s_beg, $s_max );
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>> SHORTER MATCHES ONLY <<<<<<<<<<<<<<<<<<<<<<<

        # The shorter matches are first scored according to the dimensions of 
        # the current search space, proximity to the diagonals and start/end
        # of previous matches (all heuristic done in the score_match function). 
        # Then the highest scoring match is chosen and those on its right and
        # left are re-submitted. 

        else
        {
            foreach $match ( @matches )
            {
                $match->[SCORE] = &Seq::Align::score_match( $subref, $params, $match, $q_seq, $q_min, $q_max, $s_min, $s_max );
            }

            @matches = grep { $_->[SCORE] <= $params->{"max_score"} } @matches;

            if ( @matches )
            {
                # Find the match with lowest (best) score,
            
                $best_match = ( sort { $a->[SCORE] <=> $b->[SCORE] } @matches )[0];
            
                if ( $best_match->[SCORE] <= $params->{"max_score"} )
                {
                    # Add best match to results,
                    
                    push @chain, $best_match;

                    # Align decent matches in search space preceding best match,
                    
                    if ( $best_match->[Q_BEG] > $q_min and $best_match->[S_BEG] > $s_min )
                    {
                        @l_matches = &Seq::Align::select_matches( \@matches, 
                                                                   $q_min, $best_match->[Q_BEG]-1, 
                                                                   $s_min, $best_match->[S_BEG]-1 );
 
#                        &dump( "    old: $q_min, $q_max, $s_min, $s_max" );
#                        &dump( "beg new: $q_min, ".($best_match->[Q_BEG]-1).", $s_min, ".($best_match->[S_BEG]-1) );
                        
                        
                        push @chain, &Seq::Align::align_two_seqs( $subref,
                                                                  $q_seq, $s_seq, 
                                                                  \@l_matches, $params, $is_match,
                                                                  $q_min, $best_match->[Q_BEG]-1, 
                                                                  $s_min, $best_match->[S_BEG]-1 );
                    }
                    
                    # Align decent matches in search space following best match,
                    
                    if ( $best_match->[Q_END] < $q_max and $best_match->[S_END] < $s_max )
                    {
                        @r_matches = &Seq::Align::select_matches( \@matches, 
                                                                   $best_match->[Q_END]+1, $q_max,  
                                                                   $best_match->[S_END]+1, $s_max );
                        
#                        &dump( "    old: $q_min, $q_max, $s_min, $s_max" );
#                        &dump( "end new: ". ($best_match->[Q_END]+1) ." $q_max, ". ($best_match->[Q_END]+1).", $s_max" );

                        push @chain, &Seq::Align::align_two_seqs( $subref,
                                                                  $q_seq, $s_seq, 
                                                                  \@r_matches, $params, $is_match,
                                                                  $best_match->[Q_END]+1, $q_max, 
                                                                  $best_match->[S_END]+1, $s_max );
                    }
                }
                else {
                    return wantarray ? () : [];
                }
            }
        }
    }
    elsif ( $q_seq and $s_seq )
    {
        # &dump("------------- STRINGS, NO MATCHES ----------- ");

        # >>>>>>>>>>>>>>>>>>>>>>> NO MATCHES GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # No matches means we must generate them. So here we find all perfect 
        # matches between the two given sequences that are longer then a certain
        # minimum length. The matches are extended as much as possible. The 
        # minimum match length is decided by looking at the length of the 
        # sequences given. With matches found, invoke this routine on them 
        # (returning to one of the sections above.) 
        
        # Set word length so match with a given word only occurs about once in
        # a given search space,

        $count = 1;
        $w_len = 0;

        $q_dim = $q_max - $q_min + 1;
        $s_dim = $s_max - $s_min + 1;

        while ( $params->{"alphabet_size"} ** $w_len <= $count )
        {
            $count = ( $q_dim - $w_len ) * ( $s_dim - $w_len );
            
            # &dump( $count );
            last if $count == 0;
            
            $w_len++;
        }

        # &dump( $w_len );

        $w_len -= 1 if $w_len > 1;
        # &dump( $w_len );

        if ( $is_match )
        {
            # &dump( $is_match );
            # &dump( "is match begin" );

            # >>>>>>>>>>>>>>>>>>> MATCH MATRIX GIVEN <<<<<<<<<<<<<<<<<<<<<<

            # This allows whatever matches a given matrix (hash of hashes)
            # allows, including base pairs,

            for ( $s_pos = $s_min; $s_pos <= $s_max - $w_len + 1; $s_pos++ )
            {
                $subseq = substr ${ $s_seq }, $s_pos, $w_len;

                # &dump("subseq = $subseq" );

                foreach $matseq ( &Seq::Align::create_matches( $subseq, $is_match ) )
                {
                    push @{ $s_begs{ $matseq } }, $s_pos;
                }
            }

            # Look up each word along the query sequence, pause at each subject sequence
            # match and extend the match as long as possible. Put the positions involved
            # in the extension into lookup hash (%skip) to avoid redundant matches,
            
            for ( $q_beg = $q_min; $q_beg <= $q_max - $w_len + 1; $q_beg++ )
            {
                $q_word = substr ${ $q_seq }, $q_beg, $w_len;

                if ( exists $s_begs{ $q_word } )
                {
                    foreach $s_beg ( @{ $s_begs{ $q_word } } )
                    {
                        $q_end = $q_beg + $w_len;
                        $s_end = $s_beg + $w_len;
                        
                        next if grep { not ( $s_end <= $_->[0] or $s_beg > $_->[1] ) } @{ $skip{ $q_beg } };
                        
                        while ( $q_end <= $q_max and $s_end <= $s_max and
                                $is_match->{ substr ${ $q_seq }, $q_end, 1 }->{ substr ${ $s_seq }, $s_end, 1 } )
                        {
                            $q_end++;
                            $s_end++;
                        }
                        
                        $q_end--;
                        $s_end--;
                        
                        foreach $q_pos ( $q_beg .. $q_end )
                        {
                            push @{ $skip{ $q_pos } }, [ $s_beg, $s_end ];
                        }
                        
                        push @matches, [ $q_beg, $q_end, $s_beg, $s_end, $q_end-$q_beg+1 ];
                    }
                }
                
                delete $skip{ $q_beg };
            }

            # &dump( "is match end" );
        }
        else
        {
            # &dump( "is not match" );

            # >>>>>>>>>>>>>>>>>>> NO MATCH MATRIX GIVEN <<<<<<<<<<<<<<<<<<<

            # Revert to plain character matching. Put each every subject 
            # sequence word into a lookup hash: the word is key, the value 
            # is a list of positions where it occurs,

            for ( $s_pos = $s_min; $s_pos <= $s_max - $w_len + 1; $s_pos++ )
            {
                push @{ $s_begs{ substr ${ $s_seq }, $s_pos, $w_len } }, $s_pos;
            }
            
            # Look up each word along the query sequence, pause at each subject sequence
            # match and extend the match as long as possible. Put the positions involved
            # in the extension into lookup hash (%skip) to avoid redundant matches,
            
            for ( $q_beg = $q_min; $q_beg <= $q_max - $w_len + 1; $q_beg++ )
            {
                $q_word = substr ${ $q_seq }, $q_beg, $w_len;
                
                if ( exists $s_begs{ $q_word } )
                {
                    foreach $s_beg ( @{ $s_begs{ $q_word } } )
                    {
                        $q_end = $q_beg + $w_len;
                        $s_end = $s_beg + $w_len;
                        
                        next if grep { not ( $s_end <= $_->[0] or $s_beg > $_->[1] ) } @{ $skip{ $q_beg } };
                        
                        while ( $q_end <= $q_max and $s_end <= $s_max and
                                (substr ${ $q_seq }, $q_end, 1) eq (substr ${ $s_seq }, $s_end, 1) )
                        {
                            $q_end++;
                            $s_end++;
                        }
                        
                        $q_end--;
                        $s_end--;
                        
                        foreach $q_pos ( $q_beg .. $q_end )
                        {
                            push @{ $skip{ $q_pos } }, [ $s_beg, $s_end ];
                        }
                        
                        push @matches, [ $q_beg, $q_end, $s_beg, $s_end, $q_end-$q_beg+1 ];
                    }
                }
                
                delete $skip{ $q_beg };
            }
        }

        undef %s_begs;

        if ( @matches )
        {
            push @chain, &Seq::Align::align_two_seqs( $subref,
                                                      $q_seq, $s_seq, 
                                                      \@matches, $params, $is_match,
                                                      $q_min, $q_max, $s_min, $s_max );
        }
        else {
            return wantarray ? () : [];
        }
    }
    else {
        return wantarray ? () : [];
    }
    
    @chain = sort { $a->[Q_BEG] <=> $b->[Q_BEG] } @chain;
    
    return wantarray ? @chain : \@chain;
}

sub check_matches
{
    my ( $matches,
         $q_seq,
         $s_seq,
         $q_aseq,
         $s_aseq,
         ) = @_;

    my ( $match, $q_diff, $s_diff, $q_subseq, $s_subseq, $i, $j, $match_prev,
         @errors, $seq, $len1, $len2 );

    # Check that ends are always higher than begins,

    for ( $i = 0; $i <= $#{ $matches }; $i++ )
    {
        $match = $matches->[$i];

        if ( $match->[Q_END] < $match->[Q_BEG] ) {
            push @errors, qq (ERROR, match $i: Q_END ($match->[Q_END]) < Q_BEG ($match->[Q_BEG]) \n);
        }

        if ( $match->[S_END] < $match->[S_BEG] ) {
            push @errors, qq (ERROR, match $i: S_END ($match->[S_END]) < S_BEG ($match->[S_BEG])\n);
        }
    }

    # Check that all Q and S ranges are equally long,

    for ( $i = 0; $i <= $#{ $matches }; $i++ )
    {
        $match = $matches->[$i];

        $q_diff = $match->[Q_END] - $match->[Q_BEG];
        $s_diff = $match->[S_END] - $match->[S_BEG];

        if ( $q_diff != $s_diff )
        {
            push @errors, qq (ERROR, match $i: Q length is $q_diff, but S length is $s_diff\n);
            push @errors, qq (       $match->[Q_BEG]-$match->[Q_END] / $match->[S_END]-$match->[S_BEG]\n);         
        }
    }

    # Check that matches agree with sequence,

    if ( $q_seq and $s_seq )
    {
        for ( $i = 0; $i <= $#{ $matches }; $i++ )
        {
            $match = $matches->[$i];

            $q_subseq = substr ${ $q_seq }, $match->[Q_BEG], $match->[LENGTH];
            $s_subseq = substr ${ $s_seq }, $match->[S_BEG], $match->[LENGTH];
            
            if ( $q_subseq ne $s_subseq )
            {
                push @errors, qq (ERROR, match $i: sequences are different\n);
            }
        }
    }

    # Check for overlapping matches,

    $j = 0;
    $match_prev = $matches->[$j];

    for ( $i = 1; $i <= $#{ $matches }; $i++ )
    {
        $match = $matches->[$i];

        if ( ( $match_prev->[Q_END] < $match->[Q_BEG] or $match->[Q_END] < $match_prev->[Q_BEG] )
             and not ( $match_prev->[S_END] < $match->[S_BEG] or $match->[S_END] < $match_prev->[S_BEG] ) )
        {
            push @errors, qq (ERROR: match $i overlaps with match $j\n);
#            push @errors, Dumper( $match );
#            push @errors, Dumper( $match_prev );
        }

        $match_prev = $match;
        $j += 1;
    }

    # Check that input and output sequences are the same when gaps
    # are removed from output sequence,

    if ( $q_seq and $s_seq and $q_aseq and $s_aseq )
    {
        $seq = ${ $q_aseq };
        $seq =~ s/-//g;
        
        if ( $seq ne ${ $q_seq } )
        {
            $len1 = length ${ $q_seq };
            $len2 = length $seq;
            push @errors, qq (ERROR: input and output Q sequences differ\n);
            push @errors, qq (       input Q length $len1, output length $len2\n);
        }
        
        $seq = ${ $s_aseq };
        $seq =~ s/-//g;
        
        if ( $seq ne ${ $s_seq } )
        {
            $len1 = length ${ $s_seq };
            $len2 = length $seq;
            push @errors, qq (ERROR: input and output S sequences differ\n);
            push @errors, qq (       input S length $len1, output length $len2\n);
        }
    }

    if ( @errors ) {
        return wantarray ? @errors : \@errors;
    } else {
        return;
    }
}   

sub clip_match
{
    # Niels Larsen, November 2004.

    # Clips a given match so its ends are within a given area.
    # If the match is outside the area nothing is returned.

    my ( $area,       # Area 
         $match,      # Match to be clipped
         ) = @_;

    # Returns an array or nothing. 

    my ( $clip );

    if ( $match->[Q_END] < $area->[Q_BEG] or $match->[S_END] < $area->[S_BEG] or
         $match->[Q_BEG] > $area->[Q_END] or $match->[S_BEG] > $area->[S_END] )
    {
        return;
    }
    else
    {
        $clip = &List::Util::max( $area->[Q_BEG] - $match->[Q_BEG], $area->[S_BEG] - $match->[S_BEG] );

        if ( $clip > 0 )
        {
            $match->[Q_BEG] += $clip;
            $match->[S_BEG] += $clip;
            $match->[LENGTH] -= $clip;
        }

        $clip = &List::Util::max( $match->[Q_END] - $area->[Q_END], $match->[S_END] - $area->[S_END] );
        
        if ( $clip > 0 )
        {
            $match->[Q_END] -= $clip;
            $match->[S_END] -= $clip;
            $match->[LENGTH] -= $clip;
        }
    }

    return $match;
}
    
sub clip_match_beg
{
    my ( $q_min,
         $s_min,
         $match,
         ) = @_;

    my ( $matches );

    $matches = &Seq::Align::clip_matches_beg( $q_min, $s_min, [ $match ] );

    if ( $matches ) {
        return $matches->[0];
    } else {
        return;
    }
}

sub clip_match_end
{
    my ( $q_max,
         $s_max,
         $match,
         ) = @_;

    my ( $matches );

    $matches = &Seq::Align::clip_matches_end( $q_max, $s_max, [ $match ] );

    if ( $matches ) {
        return $matches->[0];
    } else {
        return;
    }
}

sub clip_matches_beg
{
    # Niels Larsen, December 2004.

    # Given a list of matches, returns only those matches with ends
    # that are >= given q and s minimum values. The begins of such 
    # matches are clipped so they are no lower than the given minimum 
    # values. 

    my ( $q_min,     # Q clip value
         $s_min,     # S clip value
         $matches,   # Match list
         ) = @_;

    # Returns a list.

    my ( @matches, $match, $clip );

    foreach $match ( @{ $matches } )
    {
        if ( $match->[Q_END] >= $q_min and $match->[S_END] >= $s_min )
        {
            $clip = &List::Util::max( $q_min - $match->[Q_BEG], $s_min - $match->[S_BEG] );
            
            if ( $clip > 0 )
            {
                $match->[Q_BEG] += $clip;
                $match->[S_BEG] += $clip;
                $match->[LENGTH] -= $clip;
            }
            
            push @matches, $match;
        }
    }

    if ( @matches ) {
        return wantarray ? @matches : \@matches;
    } else {
        return;
    }
}

sub clip_matches_end
{
    # Niels Larsen, December 2004.

    # Given a list of matches, returns only those matches with begins
    # that are <= given q and s maximum values. The ends of such 
    # matches are clipped so they dont exceed the given maximum
    # values. 

    my ( $q_max,     # Q clip value
         $s_max,     # S clip value
         $matches,   # Match list
         ) = @_;

    # Returns a list.
    
    my ( @matches, $match, $clip );

    foreach $match ( @{ $matches } )
    {
        if ( $match->[Q_BEG] <= $q_max and $match->[S_BEG] <= $s_max )
        {
            $clip = &List::Util::max( $match->[Q_END] - $q_max, $match->[S_END] - $s_max );
    
            if ( $clip > 0 )
            {
                $match->[Q_END] -= $clip;
                $match->[S_END] -= $clip;
                $match->[LENGTH] -= $clip;
            }

            push @matches, $match;
        }
    }
    
    if ( @matches ) {
        return wantarray ? @matches : \@matches;
    } else {
        return;
    }
}

sub create_matches
{
    # Niels Larsen, June 2005. 

    # Creates a list of sequences that match a given sequence, 
    # according to a given identity matrix. Use only for short
    # sequences or it will eat the memory.  
    # 
    # UNFINISHED: inefficient hack

    my ( $seq,
         $match, 
         ) = @_;
         
    # Returns a list.

    my ( @seq, @matches, @list, $base1, $base2 );

    @seq = split "", $seq;

    foreach $base2 ( keys %{ $match->{ $seq[0] } } )
    {
        push @matches, $base2;
    }

    shift @seq;

    foreach $base1 ( @seq )
    {
        @list = ();

        foreach $base2 ( keys %{ $match->{ $base1 } } )
        {
            push @list, map { $_ . $base2 } @matches;
        }

        @matches = @list;
    }

    return wantarray ? @matches : \@matches;
}

sub create_sim
{
    # Niels Larsen, May 2013.

    # Calculates similarity from a given list of aligned fragments. Only 
    # mismatches/indels between aligned fragments are included, the ends 
    # are ignored. The value returned is between 0 and 1.

    my ( $ali,
        ) = @_;

    # Returns a number.

    my ( $i, $mis, $sim, $lensum, $missum );

    $lensum = 0;
    $missum = 0;

    for ( $i = 0; $i < $#{ $ali }; $i += 1 )
    {
        $lensum += $ali->[$i]->[Q_END] - $ali->[$i]->[Q_BEG] + 1;
        
        $mis = &List::Util::min( 
            $ali->[$i+1]->[Q_BEG] - $ali->[$i]->[Q_END] - 1,
            $ali->[$i+1]->[S_BEG] - $ali->[$i]->[S_END] - 1,
            );
        
        $mis = 1 if $mis == 0;

        $missum += $mis;
    }

    $lensum += $ali->[-1]->[Q_END] - $ali->[-1]->[Q_BEG] + 1;

    $sim = 1.0 - $missum / ( $lensum + $missum );

    return $sim;
}

sub get_range_locs
{
    my ( $locs,
         $beg,
         $end,
        ) = @_;

    my ( $beg_ndx, $end_ndx, $list );

    if ( $beg <= $end )
    {
        $beg_ndx = &Common::Util::bsearch_num_ceil( [ map { $_->[0] } @{ $locs } ], $beg );
        $end_ndx = &Common::Util::bsearch_num_floor( [ map { $_->[0] } @{ $locs } ], $end );

        if ( defined $beg_ndx and defined $end_ndx 
             and $beg_ndx <= $end_ndx )
        {
            $list = &Storable::dclone( [ @{ $locs }[ $beg_ndx ... $end_ndx ] ] );
        }
        else {
            return;
        }
    }
    else {
        &error( qq (Programming error: \$beg > \$end: $beg > $end) );
    }
    
    return wantarray ? @{ $list } : $list;
}

sub interpolate_position
{
    # Niels Larsen, July 2012. 

    #   |||---  |||
    #   |||-----|||
    #   |||---  |||

    my ( $pos1,
         $beg1,
         $end1,
         $beg2,
         $end2,
        ) = @_;

    my ( $len1, $len2, $pos2, $ratio, $lendif, $begpos2, $endpos2 );

    $len1 = $end1 - $beg1 + 1;
    $len2 = $end2 - $beg2 + 1;

    $ratio = $len2 / $len1;
    $pos2 = $beg2 + ( $pos1 - $beg1 ) * $ratio;

    $lendif = abs ( $len2 - $len1 );

    $begpos2 = int ( $pos2 - $lendif / 2 );
    $endpos2 = int ( $pos2 + $lendif / 2 );
    
    $begpos2 = &List::Util::max( $beg2, $begpos2 );
    $endpos2 = &List::Util::min( $end2, $endpos2 );

    return [ $begpos2, $endpos2 ];
}

sub is_match
{
    my ( $seq1,
         $seq2,
         $hash,
         ) = @_;

    my ( @seq1, @seq2, $ch1, $ch2, $i, $match );

    $match = 1;

    for ( $i = 0; $i <= $#seq1; $i++ )
    {
        if ( $hash->{ $seq1[$i] }->{ $seq2[$i] } )
        {
            $match = 0;
            last;
        }
    }

    if ( $match ) { 
        return 1;
    } else {
        return;
    }
}

sub process_args
{
    # Niels Larsen, March 2010.

    # Checks and expands the cluster routine parameters and does one of two: 
    # 1) if there are errors, these are printed in void context and pushed onto 
    # a given message list in non-void context, 2) if no errors, returns a hash 
    # of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, $format, $type );

    @msgs = ();

    # Input files,

    if ( $args->itable )
    {
	$args{"ifile"} = @{ &Common::File::check_files( [ $args->itable ], "efr", \@msgs ) }[0];
        $args{"iformat"} = "table";
        $args{"oformat"} = "table";

        if ( $args->ifasta ) {
            push @msgs, ["ERROR", qq (Table and fasta input cannot be mixed) ];
        }
    }
    elsif ( $args->ifasta )
    {
	$args{"ifile"} = @{ &Common::File::check_files( [ $args->ifasta ], "efr", \@msgs ) }[0];
        $args{"iformat"} = "fasta";
        $args{"oformat"} = "fasta";

        if ( $args->itable ) {
            push @msgs, ["ERROR", qq (Table and fasta input cannot be mixed) ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (Either table or fasta input file must be given) ];
    }

    # Input format,

    if ( $format = $args->debug )
    {
        $args{"oformat"} = "debug";
    }

    # Output file, can be STDOUT,

    if ( $args->ofile and not $args->clobber ) {
        $args{"ofile"} = @{ &Common::File::check_files( [ $args->ofile ], "!e", \@msgs ) }[0];
    } else {
        $args{"ofile"} = $args->ofile;
    }
    
    # Sequence type,

    if ( $type = $args->seqtype )
    {
        if ( $type =~ /^nuc|rna|dna$/i ) {
            $args{"seqtype"} = "nuc";
        } elsif ( $type =~ /^protein$/i ) {
            $args{"seqtype"} = "prot";
        } else {
            push @msgs, ["ERROR", qq (Wrong looking sequence type -> "$type". Choices are: nuc or protein) ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (No sequence type given. Choices are: nuc or protein) ];
    }

    # Score,

    $args{"score"} = &Registry::Args::check_number( $args->score, 0, undef, \@msgs );

    &Common::Messages::append_or_exit( \@msgs );

    return wantarray ? %args : \%args;
}

sub score_match
{
    # Niels Larsen, June 2004.
    
    # Creates a crude "heuristic" attempt of telling how likely it is that a 
    # given match occurs by chance in a given search space. If sequences are
    # given their composition is taken into account. The scoring punishes 
    # distance from diagonal(s) and distance from previous match(es). Scores
    # range from zero and up, and lower is better. 

    my ( $subref,
         $params,
         $match,   # Match array
         $q_seq,   # Either q_seq or s_seq
         $q_min,   # Lower bound search area (query sequence)
         $q_max,   # Upper bound search area (query sequence)
         $s_min,   # Lower bound search area (subject sequence)
         $s_max,   # Upper bound search area (subject sequence)
         ) = @_;
    
    # Returns a positive number. 
    
    my ( $q_beg, $s_beg, $q_end, $s_end, $q_dim, $s_dim, $seq, $pos,
         $q_delta_beg, $s_delta_beg, $q_delta_end, $s_delta_end, $i,
         $dist_beg_max, $dist_end_max, $as, $gs, $ts, $cs, $pmatch,
         $score, $moves, $dist_beg, $dist_end, $seqlen, %chars, $delta,
         $delta_max, $dim_diff, $mat_diff, $q_beg_diff, $s_beg_diff,
         $q_end_diff, $s_end_diff );
    
    $q_beg = $match->[Q_BEG];
    $q_end = $match->[Q_END];
    $s_beg = $match->[S_BEG];
    $s_end = $match->[S_END];

    $q_end_diff = $q_max - $q_end;
    $s_end_diff = $s_max - $s_end;
    $q_beg_diff = $q_beg - $q_min;
    $s_beg_diff = $s_beg - $s_min;

    # >>>>>>>>>>>>>>>>>>>>>>>>> LENGTH BASED SCORE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Make initial score that takes length and sequence composition in account,

    $pmatch = $subref->( $match->[LENGTH], $q_seq, $q_beg, $q_end );

    $score = $pmatch ** ( $q_end - $q_beg + 1 ); 

#    # Punish by difference in height and width of search space,
    
#    $q_dim = $q_max - $q_min + 1;
#    $s_dim = $s_max - $s_min + 1;
    
#    if ( $q_dim != $s_dim ) {
#        $score *= abs ( $q_dim - $s_dim ) ** 2; 
#    }

#    if ( $q_beg == 90 ) {
#        print STDERR "LENGTH: q_beg, q_end, s_beg, s_end, score: $q_beg, $q_end, $s_beg, $s_end, $score\n";
#        print STDERR "        q_min, q_max, s_min, s_max: $q_min, $q_max, $s_min, $s_max\n";
#    }
#    print STDERR "     match->[LENGTH], mat, dim, score, max_score: $match->[LENGTH], $mat_diff, $dim_diff, $score, $params->{'max_score'}\n";

    return $score if $score > $params->{"max_score"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OFF DIAGONAL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $score *= &List::Util::min( abs ( $q_beg_diff - $s_beg_diff ), abs ( $q_end_diff - $s_end_diff ) ) ** 2;

    return $score if $score > $params->{"max_score"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CORNER PROXIMITY <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If a match is near a corner of the search space, then tolerate
    # weaker matches than if in the middle, where it would need to 
    # be stronger. 

    $dist_beg_max = &List::Util::max( $q_beg_diff, $s_beg_diff );
    $dist_end_max = &List::Util::max( $q_end_diff, $s_end_diff );

    $score *= ( &List::Util::min( $dist_beg_max, $dist_end_max ) + 1 ) ** 2.5;

#    if ( $q_beg == 90 ) {
#        print STDERR "CORNER: q_beg, q_end, s_beg, s_end, score: $q_beg, $q_end, $s_beg, $s_end, $score\n";
#    }

    return $score if $score > $params->{"max_score"};

    # >>>>>>>>>>>>>>>>>>>>>>>> PUNISH WRONG STRETCHING <<<<<<<<<<<<<<<<<<<<<<<<

    # The degree to which the longer of the two sequences are stretched is 
    # punished here,

    $dim_diff = abs ( ( $q_max - $q_min ) - ( $s_max - $s_min ) ) + 1;

    $mat_diff = abs ( ( $q_end_diff - $s_end_diff )
                    - ( $q_beg_diff - $s_beg_diff ) ) + 1;

    if ( $mat_diff > $dim_diff )
    {
        $score *= ( 20 * ( $mat_diff - $dim_diff ) ) * 5;
    }

#    if ( $q_beg == 90 ) {
#        print STDERR "STRETCH: q_beg, q_end, s_beg, s_end, score: $q_beg, $q_end, $s_beg, $s_end, $score\n";
#    }

    if ( $score < 0 ) {
        print STDERR "q_min, q_max, s_min, s_max: $q_min, $q_max, $s_min, $s_max\n";
        die qq (Score <= 0 -> $score);
    }

    return $score;
}

sub select_matches
{
    # Niels Larsen, November 2004.

    # Finds the matches that fall within an area given by q_min,
    # q_max, s_min and s_max coordinates. The matches may not be
    # completely contained in the area, it is enough that one of 
    # their ends reach into the area. This is because neighbor 
    # matches frequently overlap as they are all expanded as 
    # far as possible. 
    
    my ( $matches,     # Match list
         $q_min,       # Lower q bound
         $q_max,       # Upper q bound
         $s_min,       # Lower s bound 
         $s_max,       # Upper s bound
         ) = @_;

    my ( @matches, $match, $q_end, $s_end, $clip );

    # Get all matches that overlap with the area,

    foreach $match ( @{ $matches } )
    {
        if ( not ( $match->[Q_END] < $q_min or $match->[Q_BEG] > $q_max ) and
             not ( $match->[S_END] < $s_min or $match->[S_BEG] > $s_max ) )
        {
            push @matches, &Storable::dclone( $match );
        }
    }

    # Update the matches so they dont stick out of the area,

    @matches = &Seq::Align::clip_matches_beg( $q_min, $s_min, \@matches );
    @matches = &Seq::Align::clip_matches_end( $q_max, $s_max, \@matches );

    if ( @matches ) {
        return wantarray ? @matches : \@matches;
    } else {
        return;
    }
}

sub seq_identity_check
{
    # Niels Larsen, October 2010. 

    # Crashes if the given aligned version of a given unaligned sequence
    # is any different.

    my ( $seq,      # Original unaligned sequence object
         $aref,     # Aligned sequence string reference
        ) = @_;

    # Returns nothing.

    my ( $aseq, $id );

    $aseq = Seq::Common->new({ "id" => $seq->id, "seq" => ${ $aref } });

    $aseq->delete_gaps;

    if ( $seq->seq ne $aseq->seq )
    {
        $id = $seq->id;
        &error( qq (Sequence is different before and after alignment -> "$id".\n)
               .qq (This is a bug that may not happen, please do not use the program until fixed.) );
    }
    
    return;
}

sub stringify_matches
{
    # Niels Larsen, August 2004 + October 2010.

    # Formats the match list into strings with gaps embedded. Input is a chain
    # of matches (that the alignment routine emits) sorted by start positions, query
    # and subject unaligned sequence string references. Output is a list of three 
    # strings ( q aligned seq string ref, s aligned seq string ref, gap string ref).
    # There are two modes, one where gaps in the query seqs are transferred to the 
    # subject, and one where they are ignored; if q_gaps are given, then they are 
    # are transferred. The gap string has "|" and " " characters to indicate match
    # and non-match. For post-processing purposes, this routine is much less useful
    # than the match list.

    my ( $chain,    # Sorted list of matches
         $q_seq,    # Unaligned query sequence string reference
         $s_seq,    # Unaligned subject sequence string reference 
         $is_match, # Identity matrix hash
         $q_gaps,   # Query sequence gap locators - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $q_aseq, $s_aseq, $match, $q_beg, $q_end, $s_beg, $s_end, $max_diff, 
         $q_diff, $s_diff, $g_astr, $len, $q_str, $s_str, $q_ref, $q_len, 
         $s_len, $ndx, $ndx_max, $gap_len, $locs, $loc, $q_pos, $s_pos, 
         $gap_sum, $gap_ch, $max_len, $len_diff, $sub_str, $sub_gaps,
         $q_sum, $s_sum, $with_gaps, $gap_add );

    if ( $q_gaps and not ref $q_gaps )
    {
        $q_gaps = &Seq::Common::gapstr_to_gaplocs( $q_gaps );
        $with_gaps = 1;
    }
    else {
        $with_gaps = 0;
    }

    # Gap character used for alignment; the original gap characters are 
    # preserved, 

    $gap_ch = "-";
    
    # The strings being built by this routine,

    $q_aseq = "";         # Aligned query sequence string
    $s_aseq = "";         # Aligned subject sequence string
    $g_astr = "";         # Gap string (only printed in debug mode)

    # Sort the chain of matches by start positions,

    $chain = [ sort { $a->[Q_BEG] <=> $b->[Q_BEG] } @{ $chain } ];
    $ndx_max = $#{ $chain };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> IF NO MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Gaps go after sequence, so the whole sequence appear left justified,

    if ( not defined $chain or not @{ $chain } )
    {
        # First whole sequence,

        if ( $with_gaps ) {
            $gap_sum = &Seq::Align::add_gaps_to_string( $q_seq, $q_gaps, \$q_aseq );
        } else {
            $q_aseq = ${ $q_seq };
            $gap_sum = 0;
        }

        $g_astr = "";
        $s_aseq = ${ $s_seq };

        # Then all gaps,

        $q_len = ( length ${ $q_seq } ) + $gap_sum;
        $s_len = ( length ${ $s_seq } );
            
        $max_len = &List::Util::max( $q_len, $s_len );
        
        if ( $max_len > 1 )
        {
            $q_aseq .= "-" x ( $max_len - $q_len );
            $s_aseq .= "-" x ( $max_len - $s_len );
        }
        
        return ( \$q_aseq, \$g_astr, \$s_aseq );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> INITIAL UNALIGNED REGION <<<<<<<<<<<<<<<<<<<<<<<

    ( $q_beg, $q_end ) = ( 0, $chain->[0]->[Q_BEG] - 1 );
    ( $s_beg, $s_end ) = ( 0, $chain->[0]->[S_BEG] - 1 );

    $q_len = $q_end - $q_beg + 1;
    $s_len = $s_end - $s_beg + 1;

    # Get total number of q sequence + q gaps before the first match,

    if ( $q_beg <= $q_end ) {
        $q_sum = $q_len;
    } else {
        $q_sum = 0;
    }

    if ( $with_gaps )
    {
        $sub_gaps = &Seq::Align::get_range_locs( $q_gaps, -1, $q_end );
        map { $q_sum += $_->[1] } @{ $sub_gaps };
    }

    # Get total number of s sequence before the first match,
    
    if ( $s_beg <= $s_end ) {
        $s_sum = $s_len;
    } else {
        $s_sum = 0;
    }

    # Based on the above sum difference, first add needed gaps, so sequence 
    # becomes right-justified,

    if ( $q_sum > $s_sum ) {
        $s_aseq .= $gap_ch x ( $q_sum - $s_sum );
    } elsif ( $s_sum > $q_sum ) {
        $q_aseq .= $gap_ch x ( $s_sum - $q_sum );
    }
    
    # Add original q sequence + gaps, or just q sequence,

    if ( $with_gaps )
    {
        $sub_gaps = &Seq::Align::get_range_locs( $q_gaps, -1, $q_end );
        $sub_gaps = [ map { $_->[0] -= $q_beg; $_ } @{ $sub_gaps } ];
        
        $sub_str = substr ${ $q_seq }, $q_beg, $q_len;
        &Seq::Align::add_gaps_to_string( \$sub_str, $sub_gaps, \$q_aseq );
    }
    else {
        $q_aseq .= substr ${ $q_seq }, $q_beg, $q_len;
    }
    
    # Add s sequence, no gaps,
    
    $s_aseq .= substr ${ $s_seq }, $s_beg, $s_len;
        
    $g_astr .= " " x &List::Util::max( $q_sum, $s_sum );

    # >>>>>>>>>>>>>>>>>>>>>>> MATCH + UNMATCHED DOWNSTREAM <<<<<<<<<<<<<<<<<<<<

    for ( $ndx = 0; $ndx <= $ndx_max; $ndx++ )
    {
        # Shorthand variables,

        $match = $chain->[$ndx];

        ( $q_beg, $q_end ) = ( $match->[Q_BEG], $match->[Q_END] );
        ( $s_beg, $s_end ) = ( $match->[S_BEG], $match->[S_END] );

        $len = $q_end - $q_beg + 1;

        # >>>>>>>>>>>>>>>>>>>>>>>>>> MATCHING REGION <<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $with_gaps )
        {
            # Propagate gaps from q sequence into q, s and gap strings. Gaps
            # following the last position in the match are included for the 
            # query sequence, but not for the gap string and the subject, as
            # the new unaligned sequence that follows should be left justified,

            $sub_gaps = &Seq::Align::get_range_locs( $q_gaps, $q_beg, $q_end );
            $sub_gaps = [ map { $_->[0] -= $q_beg; $_ } @{ $sub_gaps } ];
            
            $sub_str = substr ${ $q_seq }, $q_beg, $len;
            &Seq::Align::add_gaps_to_string( \$sub_str, $sub_gaps, \$q_aseq );

            $sub_str = substr ${ $s_seq }, $s_beg, $len;
            &Seq::Align::add_gaps_to_string( \$sub_str, $sub_gaps, \$s_aseq, 0 );

            $sub_str = "|" x $len;
            $sub_gaps = [ map { $_->[2] = " "; $_ } @{ $sub_gaps } ];
            &Seq::Align::add_gaps_to_string( \$sub_str, $sub_gaps, \$g_astr, 0 );
        }
        else
        {
            # Copy ungapped sequences,

            $q_aseq .= substr ${ $q_seq }, $q_beg, $len;
            $g_astr .= "|" x $len;
            $s_aseq .= substr ${ $s_seq }, $s_beg, $len;
        }

        # >>>>>>>>>>>>>>>>>>>>>> DOWNSTREAM NO-MATCH REGION <<<<<<<<<<<<<<<<<<<

        # This handles the regions following a match, including the last one. 
        # First set q and s sequence begin and end positions, and sequence length,

        ( $q_beg, $s_beg ) = ( $chain->[$ndx]->[Q_END] + 1, $chain->[$ndx]->[S_END] + 1 );

        if ( $ndx < $ndx_max ) {
            ( $q_end, $s_end ) = ( $chain->[$ndx+1]->[Q_BEG] - 1, $chain->[$ndx+1]->[S_BEG] - 1 );
        } else {
            ( $q_end, $s_end ) = ( ( length ${ $q_seq } ) - 1, ( length ${ $s_seq } ) - 1 );
        }

        $q_len = $q_end - $q_beg + 1;   # q sequence length in region
        $s_len = $s_end - $s_beg + 1;   # s sequence length in region

        # These sums mean "number of sequence + gaps in region" which decides how
        # much gap-padding is added below,

        $q_sum = 0;
        $s_sum = 0;
        
        # First query sequence,

        if ( $with_gaps )
        {
            # Add gap at last match position to the sum,

            if ( $locs = &Seq::Align::get_range_locs( $q_gaps, $q_beg - 1, $q_beg - 1 ) ) {
                $q_sum += $locs->[0]->[1];
            }

            # If there are characters in the region, add them, and update sum,

            if ( $q_beg <= $q_end )
            {
                $sub_str = substr ${ $q_seq }, $q_beg, $q_len;
                $sub_gaps = &Seq::Align::get_range_locs( $q_gaps, $q_beg, $q_end );
                $sub_gaps = [ map { $_->[0] -= $q_beg; $_ } @{ $sub_gaps } ];
            
                $q_sum += $q_len;
                $q_sum += &Seq::Align::add_gaps_to_string( \$sub_str, $sub_gaps, \$q_aseq );
            }
        }
        else
        {
            # Just add sequence,

            $q_aseq .= substr ${ $q_seq }, $q_beg, $q_len;
            $q_sum += $q_len;
        }

        # Then subject sequence: if same number of residues in q and s, then insert them
        # as in a match region, otherwise leave unaligned and pad to the end,

        if ( $with_gaps and $q_len == $s_len and $ndx < $ndx_max and $q_len > 0 )
        {
            # Roughly as with match regions above, q first, then s,

            $sub_gaps = &Seq::Align::get_range_locs( $q_gaps, $q_beg - 1, $q_end );
            $sub_gaps = [ map { $_->[0] -= $q_beg; $_ } @{ $sub_gaps } ];
            
            $sub_str = substr ${ $s_seq }, $s_beg, $s_len;
            &Seq::Align::add_gaps_to_string( \$sub_str, $sub_gaps, \$s_aseq );

            $sub_str = "";
            $s_pos = $s_beg;

            for ( $q_pos = $q_beg; $q_pos <= $q_end; $q_pos += 1 )
            {
                if ( $is_match->{ substr ${ $q_seq }, $q_pos, 1 }->{ substr ${ $s_seq }, $s_pos, 1 } ) {
                    $sub_str .= ":";
                } else {
                    $sub_str .= " ";
                }

                $s_pos += 1;
            }

            $sub_gaps = [ map { $_->[2] = " "; $_ } @{ $sub_gaps } ];
            &Seq::Align::add_gaps_to_string( \$sub_str, $sub_gaps, \$g_astr );
        }
        else
        {
            if ( $s_beg <= $s_end )
            {
                $s_aseq .= substr ${ $s_seq }, $s_beg, $s_len;
                $s_sum += $s_len;
            }
            
            # If q gaps + sequence is longer than s, pad s, and vice versa,
            
            if ( $q_sum > $s_sum )
            {
                $s_aseq .= $gap_ch x ( $q_sum - $s_sum );
            }
            elsif ( $s_sum > $q_sum )
            {
                $q_aseq .= $gap_ch x ( $s_sum - $q_sum );
            }
            
            # Add blanks to gap string,
            
            $g_astr .= " " x &List::Util::max( $q_sum, $s_sum );
        }
    }

    return ( \$q_aseq, \$g_astr, \$s_aseq );
}

sub trans_position
{
    # Niels Larsen, July 2012. 

    # Maps a sequence coordinate in ungapped sequence 1 onto ungapped sequence 
    # 2, by aligning the two. A two element tuple [ beg, end ] is returned or
    # undef if no mapping could be done. 

    my ( $pos1,    # Sequence 1 position
         $seq1,    # Sequence 1 hash
         $seq2,    # Sequence 2 hash
         $ali,     # Alignment of 1 and 2 - OPTIONAL
        ) = @_;

    # Returns integer or list.

    my ( $seg, $astr1, $gaps, $astr2, $matrix, $str1, $str2, $len1,
         $maxpos1, $maxpos2, $off1, $endpos1, $endpos2, $match );

    $str1 = $seq1->{"seq"};
    $str2 = $seq2->{"seq"};

    $maxpos1 = ( length $str1 ) - 1;
    $maxpos2 = ( length $str2 ) - 1;
    
    if ( $pos1 > $maxpos1 ) {
        &error( qq (Given sequence position $pos1, but maximum is $maxpos1) );
    }

    if ( not $ali ) {
        $ali = &Seq::Align::align_two_nuc_seqs( \$str1, \$str2, undef, { "max_score" => 1 } );
        # ( $astr1, $gaps, $astr2 ) = &Seq::Align::stringify_matches( $ali, \$str1, \$str2 );

        #&dump( $astr1 );
        #&dump( $gaps );
        #&dump( $astr2 );
    }

    if ( @{ $ali } )
    {
        $match = $ali->[-1];

        if ( $pos1 > $match->[Q_END] )
        {
            if ( $match->[S_END] < $maxpos2 )
            {
                return &Seq::Align::interpolate_position( 
                    $pos1, 
                    $match->[Q_END] + 1, $maxpos1, 
                    $match->[S_END] + 1, $maxpos2 );
            }
            else {
                return;
            }
        }
        else
        {
            $endpos1 = -1;
            $endpos2 = -1;

            foreach $match ( @{ $ali } ) 
            {
                if ( $pos1 < $match->[Q_BEG] )
                {
                    if ( $match->[S_BEG] > $endpos2 + 1 )
                    {
                        return &Seq::Align::interpolate_position( 
                            $pos1, 
                            $endpos1 + 1, $match->[Q_BEG] - 1, 
                            $endpos2 + 1, $match->[S_BEG] - 1 );
                    } 
                    else {
                        return;
                    }
                }
                elsif ( $pos1 >= $match->[Q_BEG] and $pos1 <= $match->[Q_END] ) 
                {
                    $off1 = $pos1 - $match->[Q_BEG];

                    return [ $match->[S_BEG] + $off1, $match->[S_BEG] + $off1 ];
                }

                $endpos1 = $match->[Q_END];
                $endpos2 = $match->[S_END];
            }
        }
    }
    else {
        return [ 0, $maxpos2 ];
    }
    
    return;
}

1;

__END__

    # June 9, 2007: The following looks generally wrong, better
    # improve. 

#     # Add penalty if the match is towards the narrow end of the
#     # search space,

#     if ( ($q_max - $q_min) <= ($s_max - $s_min) )
#     {
#         if ( $q_delta_beg > $s_delta_beg )
#         {
#             $score *= 2 * ( $q_delta_beg - $s_delta_beg ) ** 4;
#         }
#         elsif ( $q_delta_end > $s_delta_end )
#         {
#             $score *= 2 * ( $q_delta_end - $s_delta_end ) ** 4;
#         }
#     }
#     else
#     {
#         if ( $s_delta_beg > $q_delta_beg )
#         {
#             $score *= 2 * ( $s_delta_beg - $q_delta_beg ) ** 4;
#         }
#         elsif ( $s_delta_end > $q_delta_end )
#         {
#             $score *= 2 * ( $s_delta_end - $q_delta_end ) ** 4;
#         }        
#     }
