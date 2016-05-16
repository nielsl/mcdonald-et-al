package Ali::Features;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;
use List::Util;

use Common::Config;
use Common::Messages;

use Common::Util;

{
    local $SIG{__DIE__};

    require Bio::Seq;
    require Bio::SeqIO;
    require Bio::DB::GenBank;
    require Bio::Index::Fasta;
    require Bio::Index::EMBL;
    require Bio::Index::Swissprot;
    require Bio::Index::GenBank;
    require Bio::Index::Abstract;
}

use base qw ( Ali::Feature );

use Seq::Run;

use Ali::Stats;
use Ali::Struct;

use RNA::Import;
use RNA;       # The Vienna package

# create_features_sims
# create_features_helix_covar
# create_features_mirna_hairpin
# create_features_mirna_mature
# create_features_mirna_patterns
# create_features_mirna_precursor
# create_features_pairs_covar
# create_features_rna_pairs
# create_features_rfam_sid_text
# create_features_sid_text
# create_features_seq_cons
# create_seq_file_if_missing
# overlap

# Feature areas constants (TODO ),

use constant FT_COLBEG => 0;
use constant FT_COLEND => 1;
use constant FT_ROWBEG => 2;
use constant FT_ROWEND => 3;
use constant FT_TITLE => 4;
use constant FT_DESCR => 5;
use constant FT_STYLES => 6;
use constant FT_SPOTS => 7;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_features_sims
{
    # Niels Larsen, February 2007.

    # Returns a list features created from a given list of similarities.
    
    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list.

    my ( $ft_desc, $ft_id, $ft_file, $ali_id, $ali_type, $fts, $ft_type, $ft_source,
         $ft_method, $sid, @areas, $area, $sim, @fts, $ft, $sids, $irow, $loc, 
         $seq_beg, $seq_end, $sim_beg, $sim_end, $i, $j, $stream, $sim_locs, 
         $begrow, $endrow, $forward, $ali );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    $ali_id = $ali->sid;
    $ali_type = $ali->datatype;

    $ft_type = $ft_desc->name;
    $ft_source = $ft_desc->source;

    if ( $ft_file ) {
        $stream = Boulder::Stream->newFh( -in => $ft_file );
    } else {
        &error( qq (No similarity features file path in feature description) );
    }

    $irow = 0;

    while ( $sim = <$stream> )
    {
        $seq_beg = $sim->Seq_beg || 0;
        $seq_end = $sim->Seq_end;

        if ( not defined $seq_end or $seq_beg < $seq_end ) {
            $forward = 1;
        } else {
            $forward = 0;
        }

        if ( $sim_locs = $sim->Sim_locs2 )
        {
            $ft = Ali::Feature->new();
        
            $ft->ali_id( $ali_id );
            $ft->ali_type( $ali_type );
            $ft->id( $ft_id );
            $ft->type( $ft_type );
            $ft->source( $ft_source );
            $ft->score( $sim->Score );
            $ft->stats( "" );

            # NOTE: this beg/end row thing isnt handled well, may need to be 
            # better about feature rows .. 

            ( $begrow, $endrow ) = @{ ( eval $sim->Sim_rows )[0]->[0] };

            @areas = ();

            foreach $loc ( @{ eval $sim_locs } )
            {
                ( $area->[FT_ROWBEG], $area->[FT_ROWEND] ) = ( $begrow, $endrow );

                if ( $forward )
                {
                    $sim_beg = $loc->[0] - $seq_beg;
                    $sim_end = $loc->[1] - $seq_beg;
                }
                else
                {
                    $sim_beg = $seq_beg - $loc->[0];
                    $sim_end = $seq_beg - $loc->[1];
                }

                $area->[FT_COLBEG] = $ali->seq_to_ali_pos( $begrow, $sim_beg );
                $area->[FT_COLEND] = $ali->seq_to_ali_pos( $begrow, $sim_end );

                $area->[FT_TITLE] = "Match region";
#                $area->[FT_DESCR] = qq ($ft_method hit \(score ) .$sim->Score. qq (\));
                $area->[FT_DESCR] = qq (Score ) .$sim->Score;
                
                push @areas, [ @{ $area } ];
            }
            
            $ft->areas( &Storable::dclone( \@areas ) );

            push @fts, $ft;
            
            $ft_id += 1;
        }
    }

    undef $ali;
    undef $stream;

    return wantarray ? @fts : \@fts;
}

sub create_features_helix_covar
{
    # Niels Larsen, March 2006.

    # Creates a list of covariation score features for whole pairings, and 
    # done pairmask by pairmask. The feature types are (helix|pseudo)_covar_(5|3).
    
    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list. 
    
    my ( $ft_desc, $ft_id, $ft_file, $score, $descr, $begrow, $endrow, $ft_tpl, 
         $ft_type, $min_score, $is_cov, $is_uncov, $pairmask, $pairings, $scores, 
         $beg5, $end5, $beg3, $end3, @fts, $ft, $pairing, $name, $pairtype, $string, 
         $rows, $area, $ali );
    
    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    if ( not $ali->pairmasks )
    {
        undef $ali;
        return wantarray ? () : [];
    }
    
    $ft_type = $ft_desc->name;
    $min_score = $ft_desc->imports->min_score;

    $is_cov = &Ali::Struct::is_covar_hash();
    $is_uncov = &Ali::Struct::is_uncovar_hash();
    
    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali->sid,
                                "ali_type" => $ali->datatype,
                                "source" => $ft_desc->source,
                                );

    foreach $pairmask ( @{ $ali->pairmasks } )
    {
        ( $begrow, $endrow, $string ) = @{ $pairmask };
        
        $pairings = &RNA::Import::parse_pairmask( $string, $msgs );
        $rows = [ $begrow .. $endrow ];

        foreach $pairing ( @{ $pairings } )
        {
            $pairtype = $pairing->[4];
            
            if ( $pairtype eq "helix" ) {
                $name = qq (helix $pairing->[5]);
            } else {
                $pairtype = "pseudo";
                $name = qq (pseudoknot pairing "$pairing->[5]");
            }
            
            $scores = &Ali::Struct::score_pairing_covar( $ali, $pairing, $rows, $is_cov, $is_uncov, 1 );
            $score = sprintf "%.2f", &Ali::Struct::sum_covar_scores( $scores );

            next if $score < $min_score;
            
            $beg5 = $pairing->[0] + 1;
            $end5 = $pairing->[1] + 1;
            $beg3 = $pairing->[2] + 1;
            $end3 = $pairing->[3] + 1;
            
            # Upstream half,
            
            $ft = $ft_tpl;

            $ft->id( $ft_id );
            $ft->type( $ft_type ."_". $pairtype ."_5" );
            $ft->score( $score );

            $area->[FT_COLBEG] = $pairing->[0];
            $area->[FT_COLEND] = $pairing->[1];
            $area->[FT_ROWBEG] = $begrow;
            $area->[FT_ROWEND] = $endrow;

            $area->[FT_TITLE] = (ucfirst $name) . ", 5-side";

            $descr = qq (Covariation score $score between this half (alignment positions $beg5-$end5))
                   . qq ( and downstream positions $beg3-$end3.);

            $area->[FT_DESCR] = $descr;

            $ft->areas( [ $area ] );
            
            push @fts, &Storable::dclone( $ft );

            # Downstream half,

            $ft = $ft_tpl;

            $ft->id( $ft_id );
            $ft->type( $ft_type ."_". $pairtype ."_3" );
            $ft->score( $score );

            $area->[FT_COLBEG] = $pairing->[2];
            $area->[FT_COLEND] = $pairing->[3];
            $area->[FT_ROWBEG] = $begrow;
            $area->[FT_ROWEND] = $endrow;

            $area->[FT_TITLE] = (ucfirst $name) . ", 3-side";
            
            $descr = qq (Covariation score $score between this half (alignment positions $beg3-$end3))
                   . qq ( and upstream positions $beg5-$end5.);
            
            $area->[FT_DESCR] = $descr;

            $ft->areas( [ $area ] );
            
            push @fts, &Storable::dclone( $ft );

            $ft_id += 1;
        }
    }

    undef $ali;

    return wantarray ? @fts : \@fts;
}

sub create_features_mirna_hairpin
{
    # Niels Larsen, August 2006.

    # For a given alignment, creates a list of features that mark where there
    # there are small straight hairpin candidates. RNALfold is run against the 
    # sequences of the given alignment and resulting features are returned if 
    # any. RNALfold can return matches that are contained in others, then only
    # those with lowest delta-g are kept. There are are number of options set 
    # that modify the way hairpin candidates are gathered, see the code and 
    # change them there if needed. 

    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns list.

    my ( $ft_desc, $ft_id, $ft_file, $ali,
         $ali_id, $seq_file, $file, $ft_tpl, $seq_fts, $seq_ft, $fold_args,
         $ft, @seq_fts, @fts, $ft_new, $overlaps, $descr, $spots, $area,
         $deltag, $seq_id, $seq, $subseq, $beg, $end, $count, $shift, $ldiff,
         %pats, $prefix, $mask, $loop, $len5, $len3, @mask, $score, $list,
         $colors, $color, $styles, $pairs, $pair, $areas, $type, $min_score,
         $max_score, $index, @scores );
    
    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    $ali_id = $ali->sid;

    $seq_file = &Common::Names::strip_suffix( $ali->file ) .".fasta";
    Ali::Features->create_seq_file_if_missing( $ali->file, $seq_file );

    $fold_args = {
        "max_asymmetry" => undef,
        "max_pair_length" => 100,
        "max_delta_g" => -20,
        "energy_temperature" => 37,
        "with_dangling_ends" => 0,       # can be 0, 1, 2, 3 - see man page
        "with_lone_pairs" => 0,
        "with_gu_pairs" => 1,
        "with_gu_pairs_at_ends" => 0,
        "with_ag_pairs" => 0,
        "with_branches" => 0,
        "with_contained" => 0,
        "with_overlaps" => 0,
    };

    @seq_fts = &Seq::Run::run_rnalfold( $seq_file, $fold_args );

    # >>>>>>>>>>>>>>>>>>>>> CONVERT TO ALIGNMENT FEATURES <<<<<<<<<<<<<<<<<<<

    # Here we make the alignment features the routine return,

    $type = $ft_desc->name;

    @scores = map { $_->score } @seq_fts;

    $min_score = &List::Util::min( @scores );

    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali_id,
                                "ali_type" => $ali->datatype,
                                "type" => $type,
                                "source" => $ft_desc->source,
                                );
    
    foreach $seq_ft ( @seq_fts )
    {
        $ft = $ft_tpl;
        
        $ft->id( $ft_id );
        $ft->score( $seq_ft->score );
        
        $beg = $seq_ft->beg;
        $end = $seq_ft->end;
        
        ( $beg, $end ) = ( $end, $beg ) if $end < $beg;

        # Make "spots" (explain),

        $pairs = &RNA::Import::parse_pairmask( $seq_ft->mask, $msgs );

        $spots = [];
        $seq_id = $seq_ft->id * 1;   # Force number conversion

        foreach $pair ( sort { $a->[0] <=> $b->[0] } @{ $pairs } )
        {
            push @{ $spots }, [ $ali->seq_to_ali_pos( $seq_id, $pair->[0] + $beg ),
                                $ali->seq_to_ali_pos( $seq_id, $pair->[1] + $beg ),
                                $seq_id, $seq_id ];

            push @{ $spots }, [ $ali->seq_to_ali_pos( $seq_id, $pair->[2] + $beg ),
                                $ali->seq_to_ali_pos( $seq_id, $pair->[3] + $beg ),
                                $seq_id, $seq_id ];
        }

        $area->[FT_COLBEG] = $ali->seq_to_ali_pos( $seq_id, $beg );
        $area->[FT_COLEND] = $ali->seq_to_ali_pos( $seq_id, $end );
        
        ( $area->[FT_ROWBEG], $area->[FT_ROWEND] ) = ( $seq_id, $seq_id );

        {
            local $Data::Dumper::Indent = 0;     # avoids whitespace
            local $Data::Dumper::Terse = 1;      # no variable name

            $area->[FT_SPOTS] = Dumper( $spots );
        }

        # Title and description,

        $score = sprintf "%.1f", abs $ft->score;

        $area->[FT_TITLE] = ucfirst "Hairpin (-$score)";
        $area->[FT_DESCR] = qq (Short hairpin folding found by RNALfold (delta-G -$score));

        # Styles,

        $index = int ( $score - $min_score ) * 2;

#        if ( $index > $#{ $colors } ) {
#            $color = $colors->[-1];
#        } else {
#            $color = $colors->[ $index ];
#        }

#        $area->[FT_STYLES] = qq ({ "bgcolor" => "$color", "bgtrans" => $styles->{"bgtrans"} });

        $ft->areas( [ $area ] );

        push @fts, &Storable::dclone( $ft );

        $ft_id += 1;
    }

    undef $ali;

    return wantarray ? @fts : \@fts; 
}

sub create_features_mirna_mature
{
    # Niels Larsen, April 2006.

    # Blasts all mature miRNA sequences against the sequences in the 
    # given alignment and returns a list of features from those matches.
    # The ft_desc argument should contain a "mirbase" path, the complete
    # path to the mature sequences in miRBase, in fasta format.

    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list.

    my ( $ft_desc, $ft_id, $ft_file, $ali,
         $q_file, $s_file, $params, $ft_tpl, $ft, @fts, $beg, $end, %ranges, 
         $ranges, $ndx, $count, $key, $range, @overlaps, $area, $idstr,
         $m8_file, $fh, $line, $hits, $id, $pct, $row, $i, $j, $forward );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    $q_file = Registry::Get->dataset( "rna_seq_mirbase" )->datapath_full ."/Installs/mature.fasta";
    $s_file = &Common::Names::strip_suffix( $ali->file ) .".fasta";

    Ali::Features->create_seq_file_if_missing( $ali->file, $s_file );

    if ( not -r $q_file ) {
        &error( qq (Mir sequences not found -> "$q_file") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> RUN BLAST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $params->{"-p"} = "blastn";
    $params->{"-m"} = 8;
    $params->{"-e"} = 0.001;
    $params->{"-b"} = 9999999;

    &Seq::Storage::index_blastn( $s_file );
    
    $m8_file =  &Common::Names::strip_suffix( $ali->file ) .".blast_m8";
    
    &Seq::Run::run_blast_local({
        "ifile" => $q_file,
        "dbfile" => $s_file,
        "dbtype" => "dna_seq",
        "ofile" => $m8_file,
        "params" => $params,
    });
    
    &Seq::Storage::delete_index( $s_file, "blastn" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> MARK MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Since there are many similar miRNA sequences their matches will 
    # overlap a lot. So we do not keep and paint each of them, but just 
    # keep track of where they cluster. Specifically, for each match the
    # lowest minimum and highest maximum are kept, and a counter,

    $fh = &Common::File::get_read_handle( $m8_file );
    
    while ( defined ( $line = <$fh> ) )
    {
        chomp $line;
        @{ $row } = split "\t", $line;

        ( $id, $ndx, $pct, $beg, $end ) = 
            ( $row->[0], $row->[1], $row->[2], $row->[8]-1, $row->[9]-1 );

        if ( $beg < $end ) {
            ( $i, $j ) = ( $beg, $end );
            $forward = 1;  
        } else {
            ( $i, $j ) = ( $end, $beg );
            $forward = 0;
        }

        if ( exists $ranges{ $ndx } )
        {
            @overlaps = grep { &Common::Util::ranges_overlap( $_->[0], $_->[1], $i, $j ) } @{ $ranges{ $ndx } };

            if ( @overlaps )
            {
                foreach $range ( @overlaps )
                {
                    $range->[0] = &Common::Util::min( $range->[0], $i );
                    $range->[1] = &Common::Util::max( $range->[1], $j );
                    
                    push @{ $range->[2] }, [ $id, $pct, $forward ];
                }
            }
            else {
                push @{ $ranges{ $ndx } }, [ $i, $j, [[ $id, $pct, $forward ]] ];
            }
        }
        else {
            push @{ $ranges{ $ndx } }, [ $i, $j, [[ $id, $pct, $forward ]] ];
        }
    }

    &Common::File::close_handle( $fh );
    &Common::File::delete_file( $m8_file );

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE FEATURE LIST <<<<<<<<<<<<<<<<<<<<<

    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali->sid,
                                "ali_type" => $ali->datatype,
                                "type" => $ft_desc->name,
                                "source" => $ft_desc->source,
                                );
    
    while ( ( $ndx, $ranges ) = each %ranges )
    {
        foreach $range ( @{ $ranges } )
        {
            $ft = $ft_tpl;
            $ft->id( $ft_id );
        
            ( $beg, $end, $hits ) = @{ $range };

            $area->[FT_COLBEG] = $ali->seq_to_ali_pos( $ndx, $beg );
            $area->[FT_COLEND] = $ali->seq_to_ali_pos( $ndx, $end );

            $area->[FT_ROWBEG] = $ndx;
            $area->[FT_ROWEND] = $ndx;
            
            $count = scalar @{ $hits };

            $beg += 1;
            $end += 1;
            
            if ( $count == 1 )
            {
                $id = $hits->[0]->[0];
                $forward = $hits->[0]->[2];

                if ( $forward ) {
                    $area->[FT_TITLE] = "Mature miRNA";
                    $area->[FT_DESCR] = qq (A single miRBase entry ($id) matches this region (from $beg to $end).);
                } else {
                    $area->[FT_TITLE] = "Mature miRNA (reverse)";
                    $area->[FT_DESCR] = qq (The complement of a single miRBase entry ($id) matches this region (from $end to $beg).);
                }                    
            }
            else
            {
                $hits = [ sort { $b->[1] <=> $a->[1] } @{ $hits } ];
                $area->[FT_TITLE] = "Mature miRNAs ($count)";

                if ( $count <= 3 ) 
                {
                    $idstr = join ", ", map { $_->[0]."/".$_[1]."%" } @{ $hits };
                    $area->[FT_DESCR] = qq ($count miRBase entries ($idstr) match this region (from $beg to $end).);
                }
                else 
                {
                    $idstr = join ", ", map { $_->[0]."/".$_->[1]."%" } @{ $hits }[0..2];
                    $count -= 3;
                    $area->[FT_DESCR] = qq (3 miRBase entries ($idstr, and $count more) match this region (from $beg to $end).);
                }

                $i = grep { $_->[2] > 0 } @{ $hits };
                $j = scalar @{ $hits } - $i;

                if ( $i > 0 ) {
                    if ( $j == 0 ) {
                        $area->[FT_DESCR] .= qq ( All are forward matches.);
                    } else {
                        $area->[FT_DESCR] .= qq ( $i are forward matches.)
                    }
                }

                if ( $j > 0 ) {
                    if ( $i == 0 ) {
                        $area->[FT_DESCR] .= qq ( All are reverse matches.);
                    } else {
                        $area->[FT_DESCR] .= qq ( $j are reverse matches.)
                    }
                }
            }

            $ft->areas( [ $area ] );
        
            push @fts, &Storable::dclone( $ft );
            
            $ft_id += 1;
        }
    }
    
    undef $ali;

    return wantarray ? @fts : \@fts; 
}

sub create_features_mirna_patterns
{
    # Niels Larsen, May 2006.

    # Scans all precursor pattern files against the sequences of the given
    # alignment and returns the resulting features if any. When matches overlap
    # only the strongest one is used, but its description mentions how many 
    # other miRNA matches overlap. RNAFold is used to determine the "strength"
    # of a match.

    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns list.

    my ( $ft_desc, $ft_id, $ft_file, $ali,
         $ali_id, $pat_files, $s_file, $file, $ft_tpl, $seq_fts, $seq_ft, 
         $ft, @seq_fts, @fts, $ft_new, $overlaps, $descr, $spots, $area,
         $seq_id, $seq, $subseq, $beg, $end, $count, $shift, $ldiff,
         %pats, $prefix, $mask, $loop, $len5, $len3, @mask, $score, $list,
         $colors, $color, $styles, $pairs, $pair, $areas, $type, $min_score,
         $molecule, @scores, $index, $info, $delta_g, $pat_dir );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    $ali_id = $ali->sid;

    $s_file = &Common::Names::strip_suffix( $ali->file ) .".fasta";
    Ali::Features->create_seq_file_if_missing( $ali->file, $s_file );

    $pat_dir = Registry::Get->dataset( "rna_ali_rfam" )->datapath_full ."/Patterns";

    $min_score = $ft_desc->imports->min_score || 0;

    # >>>>>>>>>>>>>>>>>>>>>> GET SEQUENCE FEATURES <<<<<<<<<<<<<<<<<<<<<<<<<

    # Run all pattern files in the given directory against the sequences
    # in the given alignment, using scan_for_matches. Set the "file" field
    # to the file prefix of the pattern that matched,

    $pat_files = &Common::File::list_files( $pat_dir, '.patscan$' );

    foreach $file ( @{ $pat_files } )
    {
        if ( $seq_fts = Seq::Run->run_patscan_files( $s_file, $file->{"path"}, 1 ) )
        {
            foreach $seq_ft ( @{ $seq_fts } )
            {
                $prefix = $file->{"name"};
                $prefix =~ s/\.\S+//;
                $seq_ft->molecule( $prefix );

                push @seq_fts, $seq_ft;
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>> SCORE FEATURES WITH RNAFOLD <<<<<<<<<<<<<<<<<<<<<

    # Use RNAfold to score each scan_for_matches hit. We tell RNAfold only
    # to look for hairpin-like foldings by giving it a ">>>>>>>><<<<<<<<"
    # mask. To create that mask we need to know where the helices are etc,
    # so we read in native pattern files from which the scan_for_matches 
    # versions were made. Finally weaker matches that overlap strong ones
    # are removed from the list, but count is kept how many did overlap.

    # Read in native pattern files, 

    $pat_files = &Common::File::list_files( $pat_dir, '.pattern$' );

    foreach $file ( @{ $pat_files } )
    {
        $prefix = $file->{"name"};
        $prefix =~ s/\.\S+//;

        $pats{ $prefix } = &Common::File::eval_file( $file->{"path"} );
    }

    # Create mask and run RNAfold,

    {
        local $RNA::fold_constrained = 1;

        foreach $seq_ft ( @seq_fts )
        {
            $beg = $seq_ft->beg;
            $end = $seq_ft->end;
            $seq = $seq_ft->seq;   # Hits from patscan like "AG GG ATCT CC A ATGG"
            
            ( $beg, $end ) = ( $end, $beg ) if $end < $beg;
            
            $mask = &Ali::Patterns::create_hairpin_fold_template( $pats{ $seq_ft->molecule }, $seq );

            $seq =~ s/ //g;
            ( $mask, $delta_g ) = RNA::fold( $seq, $mask );
        
            if ( $mask =~ /[()]/ )
            {
#                $ldiff = &RNA::Import::stem_length_difference( $mask, $msgs );
#                $score = $delta_g + abs $ldiff;
                $score = abs $delta_g;

                if ( $score > $min_score )
                {
                    $seq_ft->score( $score );
                    $seq_ft->mask( $mask );

                    $info = $seq_ft->info;
                    $info->{"delta_g"} = $delta_g;
                    $seq_ft->info( $info );
                }
                else {
                    undef $seq_ft;
                }
            }
            else {
                undef $seq_ft;
            }
        }
    }

    @seq_fts = grep { defined $_ } @seq_fts;

    # Remove features that overlap higher scoring ones, but keep count of 
    # how many were eliminated for each high-scoring feature,

    @seq_fts = Seq::Features->filter( \@seq_fts, "overlap" );

    # >>>>>>>>>>>>>>>>>>>>> CONVERT TO ALIGNMENT FEATURES <<<<<<<<<<<<<<<<<<<

    # Here we make the alignment features the routine return,

    $type = $ft_desc->name;
#    $styles = eval $ft_desc->style;

    @scores = map { $_->score } @seq_fts;

    $min_score = &List::Util::min( @scores );

#    $colors = &Common::Util::color_ramp( $styles->{"bgcolor"}->[0],
#                                         $styles->{"bgcolor"}->[1], 40 );

    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali_id,
                                "ali_type" => $ali->datatype,
                                "type" => $type,
                                "source" => $ft_desc->source,
                                );
    
    foreach $seq_ft ( @seq_fts )
    {
        $ft = $ft_tpl;
        
        $ft->id( $ft_id );
        $ft->score( $seq_ft->score );
        
        $beg = $seq_ft->beg;
        $end = $seq_ft->end;
        
        ( $beg, $end ) = ( $end, $beg ) if $end < $beg;

        # Make "spots" (explain),

        $pairs = &RNA::Import::parse_pairmask( $seq_ft->mask, $msgs );

        $spots = [];
        $seq_id = $seq_ft->id * 1;   # Force number conversion

        foreach $pair ( sort { $a->[0] <=> $b->[0] } @{ $pairs } )
        {
            push @{ $spots }, [ $ali->seq_to_ali_pos( $seq_id, $pair->[0] + $beg ),
                                $ali->seq_to_ali_pos( $seq_id, $pair->[1] + $beg ),
                                $seq_id, $seq_id ];

            push @{ $spots }, [ $ali->seq_to_ali_pos( $seq_id, $pair->[2] + $beg ),
                                $ali->seq_to_ali_pos( $seq_id, $pair->[3] + $beg ),
                                $seq_id, $seq_id ];
        }

        $area->[FT_COLBEG] = $ali->seq_to_ali_pos( $seq_id, $beg );
        $area->[FT_COLEND] = $ali->seq_to_ali_pos( $seq_id, $end );
        
        ( $area->[FT_ROWBEG], $area->[FT_ROWEND] ) = ( $seq_id, $seq_id );

        {
            local $Data::Dumper::Indent = 0;     # avoids whitespace
            local $Data::Dumper::Terse = 1;      # no variable name

            $area->[FT_SPOTS] = Dumper( $spots );
        }

        # Title and description,

        $molecule = $seq_ft->molecule;
        $score = sprintf "%.1f", abs $ft->score;

        $area->[FT_TITLE] = ucfirst "$molecule like folding";
        $descr = ucfirst qq (One match with score $score);

        $list = $seq_ft->info;
        $list = $list->{"overlap"};
        
        if ( $list )
        {
            $count = scalar @{ $list };

            if ( $count == 1 ) {
                $descr .= qq (, and a weaker one with $list->[0],);
            } else {
                $descr .= qq (, and $count weaker ones,);
            }
        }
        
        $descr .= " with folding patterns derived Rfam precursor alignments.";

        $area->[FT_DESCR] = $descr;

        # Styles,

        $index = int ( $score - $min_score ) * 2;

#         if ( $index > $#{ $colors } ) {
#             $color = $colors->[-1];
#         } else {
#             $color = $colors->[ $index ];
#         }

#         $area->[FT_STYLES] = qq ({ "bgcolor" => "$color", "bgtrans" => $styles->{"bgtrans"} });

        $ft->areas( [ $area ] );

        push @fts, &Storable::dclone( $ft );

        $ft_id += 1;
    }

    undef $ali;

    return wantarray ? @fts : \@fts; 
}

sub create_features_pairs_covar
{
    # Niels Larsen, March 2006.

    # Creates a list of covariation score features for whole pairings, and 
    # done pairmask by pairmask. The feature types are pair_covar_(5|3).
    
    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list. 
    
    my ( $ft_desc, $ft_id, $ali,
         $score, $ali_id, $descr, $rows, $begrow, $endrow, $ft_tpl,
         $is_cov, $is_uncov, $pairmask, $pairings, $name, $ft_type, $area5, $area3,
         $min_score, $scores, @fts, $ft, $i, $j, $col5, $col3, $string, $pairing );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    if ( not $ali->pairmasks )
    {
        undef $ali;
        return wantarray ? () : [];
    }
    
    $ft_type = $ft_desc->name;
    $min_score = $ft_desc->imports->min_score;

    $is_cov = &Ali::Struct::is_covar_hash();
    $is_uncov = &Ali::Struct::is_uncovar_hash();
    
    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali->sid,
                                "ali_type" => $ali->datatype,
                                "source" => $ft_desc->source,
                                );

    foreach $pairmask ( @{ $ali->pairmasks } )
    {
        ( $begrow, $endrow, $string ) = @{ $pairmask };

        $pairings = &RNA::Import::parse_pairmask( $string, $msgs );
        $rows = [ $begrow .. $endrow ];

        foreach $pairing ( @{ $pairings } )
        {
            $name = qq (helix $pairing->[5]);

            $scores = &Ali::Struct::score_pairing_covar( $ali, $pairing, $rows, $is_cov, $is_uncov, 1 );

            $j = 0;
            $col3 = $pairing->[3];

            for ( $col5 = $pairing->[0]; $col5 <= $pairing->[1]; $col5++ )
            {
                $score = sprintf "%.2f", $scores->[$j];

                next if $score < $min_score;

                $ft = $ft_tpl;

                $ft->id( $ft_id );
                $ft->type( $ft_type );
                $ft->score( $score );

                # Upstream and downstream bases,

                ( $area5->[FT_COLBEG], $area5->[FT_COLEND] ) = ( $col5, $col5 );
                ( $area5->[FT_ROWBEG], $area5->[FT_ROWEND] ) = ( $begrow, $endrow );

                $area5->[FT_TITLE] = (ucfirst $name) . ", 5-side";
                $area5->[FT_DESCR] = qq (Covariation score $score between this column (position $col5))
                                   . qq ( and its downstream counterpart ($col3).);

                ( $area3->[FT_COLBEG], $area3->[FT_COLEND] ) = ( $col3, $col3 );
                ( $area3->[FT_ROWBEG], $area3->[FT_ROWEND] ) = ( $begrow, $endrow );

                $area3->[FT_TITLE] = (ucfirst $name) . ", 3-side";
                $area3->[FT_DESCR] = qq (Covariation score $score between this column (position $col3))
                                   . qq ( and its upstream counterpart ($col5).);

                $ft->areas( [ $area5, $area3 ] );

                push @fts, &Storable::dclone( $ft );

                $j += 1;
                $col3 -= 1;

                $ft_id += 1;
            }

            $i += 1;
        }
    }

    undef $ali;

    return wantarray ? @fts : \@fts;
}

sub create_features_rna_pairs
{
    # Niels Larsen, March 2006.

    # Returns a list of RNA pairing features, with feature ids starting at given id. 
    # The alignment's pairing mask string is parsed and consecutive pairs are found.
    # A small set of pairing background colors are cycled through

    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list. 

    my ( $ft_desc, $ft_id, $ft_file, $ali,
         $pairmask, $begrow, $endrow, $string, $colors, $colndx, $maxndx, $pairings, 
         $pairing, $pairtype, $color, $name, $beg5, $end5, $beg3, $end3, $descr, 
         @fts, $ft, $ft_tpl, $ft_type );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    if ( not $ali->pairmasks )
    {
        undef $ali;
        return wantarray ? () : [];
    }
    
    $ft_type = $ft_desc->name;

    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali->sid,
                                "ali_type" => $ali->datatype,
                                "source" => $ft_desc->source,
                                );

    foreach $pairmask ( @{ $ali->pairmasks } )
    {
        ( $begrow, $endrow, $string ) = @{ $pairmask };
        
        $colors = &Common::Util::web_colors( 0, 102, 51 );
        $colndx = 0;
        $maxndx = $#{ $colors };
        
        # Each element of $pairings is [ beg5, end5, beg3, end3, type, number ]

        $pairings = &RNA::Import::parse_pairmask( $string, $msgs );
        
        foreach $pairing ( sort { $a->[0] <=> $b->[0] } @{ $pairings } )
        {
            $pairtype = $pairing->[4];

            $colndx = 0 if $colndx > $maxndx;
            $color = $colors->[$colndx];
            
            if ( $pairtype eq "helix" ) {
                $name = qq (pairing $pairing->[5]);
            } elsif ( $pairtype eq "pseudo" ) {
                $name = qq (pseudoknot pairing "$pairing->[5]");
            }
            
            $beg5 = $pairing->[0] + 1;
            $end5 = $pairing->[1] + 1;
            $beg3 = $pairing->[2] + 1;
            $end3 = $pairing->[3] + 1;
            
            $ft = &Storable::dclone( $ft_tpl );

            $ft->id( $ft_id );
            $ft->type( $ft_type ."_". $pairtype );

            # Upstream half and downstream half,

            $ft->areas( [
                         [
                          $pairing->[0], $pairing->[1], $begrow, $endrow,
                          (ucfirst $name) . ", 5-side",
                          qq (Upstream half \(alignment positions $beg5-$end5\) of $name.)
                        . qq ( Pairs with downstream positions $beg3-$end3.),
                          qq ({ "bgcolor" => "$color" }) 
                         ],
                         [
                          $pairing->[2], $pairing->[3], $begrow, $endrow,
                          (ucfirst $name) . ", 3-side",
                          qq (Downstream half \(alignment positions $beg3-$end3\) of $name.)
                        . qq ( Pairs with upstream positions $beg5-$end5.),
                          qq ({ "bgcolor" => "$color" }),
                         ]
                         ] );

            $colndx += 1;

            push @fts, $ft;

            $ft_id += 1;
        }
    }

    undef $ali;

    return wantarray ? @fts : \@fts;
}

sub create_features_rfam_sid_text
{
    # Niels Larsen, April 2006.

    # Returns a list of label-text features made from Rfam labels that look like
    # "AJ057347/2545-5959" or "EMBL ID/beg-end". They are used as tooltips when
    # mouse is moved over the text labels. 

    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list. 

    my ( $ft_desc, $ft_id, $ft_file, $ali,
         $ft_tpl, $sids, $sid, $embl_ids, $cache_dir, $title, $bases5, $bases3, 
         $pos_str, $descr, $row, $embl_id, $bioperlO, $org, $genus, $species, $ft,
         @fts, $cols, $ft_locs, $ft_beg, $ft_end, $ft_type, $max_col, $area );
    
    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ft_type = $ft_desc->name;

    $cache_dir = $Common::Config::dna_seq_cache_dir;

    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali->sid,
                                "ali_type" => $ali->datatype,
                                "type" => "sid_text",
                                "source" => "Rfam",
                                );

    $ft_locs = $ali->ft_locs;
    $title = ucfirst $ali->sid;

    $bases5 = $ali->orig_colbeg;
    $bases3 = $ali->max_col - $ali->orig_colend;

    $max_col = $ali->max_col;

    for ( $row = 0; $row <= $ali->max_row; $row++ )
    {
        $sid = ${ $ali->sids->slice( ":,$row:$row" )->get_dataref };
        $sid =~ s/^\s*(\S+)\s*$/$1/;

        # Get sequence info from EMBL and compose tooltip text from that,
        
        ( $embl_id, $ft_beg, $ft_end ) = &Common::Names::parse_loc_str( $ft_locs->[$row] );

        $bioperlO = &Common::File::retrieve_file( "$cache_dir/$embl_id" );
        
        if ( defined ( $org = $bioperlO->species ) ) {
            $genus = $org->genus || "";
            $species = $org->species || "";
        } else {
            $genus = "?";
            $species = "?";
        }

        # Create short-id features, to be used for tooltip display etc; see also
        # below, where column and row ranges are added (cannot do this until flanking
        # regions have been added), 

        $ft = $ft_tpl;

        $ft->id( $ft_id );

        $pos_str = &Common::Util::commify_number( $ft_beg+1 ) ." -> ".
                   &Common::Util::commify_number( $ft_end+1 );
        
        if ( $ft_beg > $ft_end ) {
            $pos_str .= ", complemented";
        }

        $descr = qq ($title precursor from $genus $species, from EMBL entry $embl_id ($pos_str),)
               . qq ( with flanks added (-$bases5/+$bases3).);

        ( $area->[FT_COLBEG], $area->[FT_COLEND] ) = ( 0, $max_col );
        ( $area->[FT_ROWBEG], $area->[FT_ROWEND] ) = ( $row, $row );

        $area->[FT_TITLE] = "$title, $sid";
        $area->[FT_DESCR] = ucfirst $descr;

        $ft->areas( [ $area ] );

        push @fts, &Storable::dclone( $ft );

        $ft_id += 1;
    }

    undef $ali;

    return wantarray ? @fts : \@fts;
}

sub create_features_sid_text
{
    # Niels Larsen, April 2006.

    # Returns a list of label-text features made from Rfam labels that look like
    # "AJ057347/2545-5959" or "EMBL ID/beg-end". They are used as tooltips when
    # mouse is moved over the text labels. 

    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list. 

    my ( $ft_desc, $ft_id, $ft_file, $ali,
         $ali_id, $ali_type, $max_col, $ft_type, $ft_source, $ft_method,
         $stream, $sim, $irow, $text, @fts, $ft, $area );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;
    $ft_file = $args->ft_file;

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    if ( $ft_file )
    {
        $stream = Boulder::Stream->newFh( -in => $ft_file );
    }
    else {
        return wantarray ? @fts : \@fts;
#        &error( qq (No file path in feature description) );
    }

    $ali_id = $ali->sid;           # TODO - used elsewhere as session_id - fix
    $ali_type = $ali->datatype;
    $max_col = $ali->max_col;

    $ft_type = $ft_desc->name;
    $ft_source = $ft_desc->source;
    $ft_method = $ft_desc->method;

    $irow = 0;

    while ( $sim = <$stream> )
    {
        if ( $text = $sim->Title )
        {
            $ft = Ali::Feature->new();

            $ft->ali_id( $ali_id );
            $ft->ali_type( $ali_type );
            $ft->id( $ft_id );
            $ft->type( $ft_type );
            $ft->source( $ft_source );
            $ft->score( "" );
            $ft->stats( "" );

            ( $area->[FT_COLBEG], $area->[FT_COLEND] ) = ( 0, $max_col );
            ( $area->[FT_ROWBEG], $area->[FT_ROWEND] ) = ( $irow, $irow );

            $area->[FT_TITLE] = $sim->Label || $sim->ID;
            $area->[FT_DESCR] = ucfirst $text;

            $ft->areas( [ $area ] );

            push @fts, &Storable::dclone( $ft );
            
            $ft_id += 1;
        }
        
        $irow += 1;
    }

    undef $stream;
    undef $ali;

    return wantarray ? @fts : \@fts;
}

sub create_features_seq_cons
{
    # Niels Larsen, March 2006.

    # Returns a list of sequence conservation features, one per column, with 
    # feature ids starting at given id. The score is the conservation percentage 
    # of the most frequent base/residue. Indels are included in the total when
    # calculating percentage, but missing data are not. 

    my ( $class,
         $args,          # Arguments hash
         $msgs,          # Outgoing messages list
         ) = @_;

    # Returns a list. 

    my ( $ft_desc, $ft_id, $ft_file, $max_col, $ali,
         $stats, $stat_chars, $col, $stat, $max, $char, $empty_rows, $tot_rows, 
         $score, $max_row, @fts, $ft, $ft_tpl, $ft_type, $min_score );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( ft_desc ) ],
        "S:1" => [ qw ( ali_file ft_id ft_file ) ],
    });

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    $stats = &Ali::Stats::col_stats_pdl( 
        $args->ali_file,
        {
            "seq_type" => $ali->datatype,
        }
        )->ali_stats;

    $max_row = $ali->max_row;
    $max_col = $ali->max_col; 

    $stat_chars = [ split "", $ali->alphabet_stats ];

    $tot_rows = $max_row + 1;

    $ft_desc = $args->ft_desc;
    $ft_id = $args->ft_id;

    $min_score = $ft_desc->imports->min_score;

    $ft_tpl = Ali::Feature->new(
                                "ali_id" => $ali->sid,
                                "ali_type" => $ali->datatype,
                                "type" => $ft_desc->name,
                                "source" => $ft_desc->source,
                                );
    undef $ali;

    foreach $col ( 0 .. $max_col )
    {
        $stat = $stats->slice("($col),:");

        $max = $stat->slice("0:-3")->max;
        $char = $stat_chars->[ &PDL::Primitive::which( $stat == $max )->at(0) ];
        
        $empty_rows = $stat->at(-1); #  + $stat->at(-2);

        if ( $tot_rows == $empty_rows ) {
            $score = 0;
        } else {
            $score = sprintf "%.1f", 100 * $max / $tot_rows;
#            $score = sprintf "%.1f", 100 * $max / ( $tot_rows - $empty_rows );
        }

        if ( $score >= $min_score )
        {
            $ft = &Storable::dclone( $ft_tpl );
            $ft->id( $ft_id );

            $ft->score( $score );
            $ft->stats( "[". (join ",", $stat->list) ."]" );

            $ft->areas( [
                         [
                          $col, $col, 0, $max_row,
                          "Seq. conservation",
                          qq ($score\% conservation ($char) at alignment position ). ($col+1) .".",
                          ]
                         ] );

            push @fts, $ft;

            $ft_id += 1;
        }
    }

    return wantarray ? @fts : \@fts;
}

sub create_seq_file_if_missing
{
    my ( $class,
         $afile,
         $ofile,
         $msgs,
        ) = @_;

    if ( not -r $ofile )
    {
        Ali::Export->write_fasta_from_pdl(
            {
                "afile" => $afile,
                "ofile" => $ofile,
                "append" => 0, 
                "with_ali_ids" => 0, 
                "with_index_sids" => 1,
                "with_gaps" => 0,
                "with_masks" => 0,
            }, $msgs );
    }
    
    return;
}

sub overlap
{
    my ( $self,
         $ft,
         ) = @_;

    if ( &Common::Util::rectangles_overlap( $self->colbeg, $self->rowbeg, $self->colend, $self->rowend,
                                            $ft->colbeg, $ft->rowbeg, $ft->colend, $ft->rowend ) )
    {
        return 1;
    }
    else {
        return;
    }
}

1;

__END__


# sub create_features_mirna_precursor
# {
#     # Niels Larsen, August 2006.

#     # For a given alignment, creates a list of features that mark 
#     # where each miRNA precursor is located in the alignment. 

#     my ( $self,          # Alignment
#          $ft_id,         # Starting feature id
#          $ft_desc,          # Arguments hash
#          $msgs,          # Errors or warnings - OPTIONAL
#          ) = @_;

#     # Returns list.

#     my ( $q_file, $s_file, $type, $params, $table, $row, $ft_tpl, 
#          $ft, @fts, $beg, $end, $ndx, $count, $abeg, $aend, $styles, 
#          $q_fh, $s_fh, $q_seq, $s_seq, $q_seqO, $s_seqO, $ali_id, $area,
#          $pre_id );

#     $ali_id = $self->sid;
#     $s_file = $ft_desc->seq_dir ."/$ali_id.fasta";

#     $pre_id = $ali_id;
#     $pre_id =~ s/_flank$/_pre/;
#     $q_file = $ft_desc->seq_dir ."/$pre_id.fasta";

#     $type = $ft_desc->name;
#     $styles = $ft_desc->style;

#     $q_fh = &Common::File::get_read_handle( $q_file );
#     $s_fh = &Common::File::get_read_handle( $s_file );
    
#     # Create feature list,

#     $ft_tpl = Ali::Feature->new(
#                                 "ali_id" => $ali_id,
#                                 "ali_type" => $self->datatype,
#                                 "type" => $type,
#                                 "source" => $ft_desc->source,
#                                 );
    
#     $ndx = 0;

#     while ( $q_seqO = &Seq::IO::read_seq_fasta( $q_fh ) )
#     {
#         $s_seqO = &Seq::IO::read_seq_fasta( $s_fh );

#         $q_seq = $q_seqO->seq_string;
#         $q_seq = lc $q_seq;
#         $q_seq =~ s/u/t/g;

#         $s_seq = $s_seqO->seq_string;
#         $s_seq = lc $s_seq;
#         $s_seq =~ s/u/t/g;

#         $beg = index $s_seq, $q_seq;

#         if ( $beg == -1 ) {
#             &error( "Precursor string not found" );
#         }

#         $end = $beg + (length $q_seq) - 1;
        
#         $ft = $ft_tpl;
#         $ft->id( $ft_id );
        
#         $area->[FT_COLBEG] = $self->seq_to_ali_pos( $ndx, $beg );
#         $area->[FT_COLEND] = $self->seq_to_ali_pos( $ndx, $end );

#         if ( $beg > $end )
#         {
#             ( $area->[FT_COLEND], $area->[FT_COLBEG] )
#                 = ( $area->[FT_COLBEG], $area->[FT_COLEND] );
#         }

#         $area->[FT_ROWBEG] = $ndx;
#         $area->[FT_ROWEND] = $ndx;
        
#         $area->[FT_TITLE] = "$ali_id precursor";
#         $area->[FT_DESCR] = qq (Precursor sequence ($beg-$end in this alignment).);
            
#         $area->[FT_STYLES] = $styles;

#         $ft->areas( [ $area ] );
        
#         push @fts, &Storable::dclone( $ft );
            
#         $ft_id += 1;
#         $ndx += 1;
#     }

#     return wantarray ? @fts : \@fts;
# }
