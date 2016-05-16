package Ali::Create;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Functions that create alignments. NOT FINISHED.

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Stone;
use Boulder::Stream;
use List::Util;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &align_seq_stream
                 &align_seq_stream_field
                 &alis_from_sims_files
                 &aliseq_from_sim_forward
                 &append_flanks
                 append_stream_fields
                 create_ali_from_sims
                 &create_gap_mask_from_sims
                 &create_state_files
                 &create_seq_stream
                 &create_summary_hash
                 &find_gap_mask_length_from_sims
                 &insert_gaps_between_matches_forward
                 &insert_gaps_within_matches_forward
                 merge_fasta_into_stream
                 &save_job_results
                 &seq_diff_check
                 &set_stream_labels
                 &set_summary_info
                 sort_sims_by_organism
                 sort_sims_by_score
                 &sum_columns
                 write_fasta_from_stream
                 );

use Common::Config;
use Common::Messages;

use Registry::Args;
use Registry::Get;

use Common::File;

use Sims::Common;
use Sims::Run;
use Seq::Run;
use Seq::Common;

use DNA::Import;
use DNA::IO;
use RNA::IO;
use Protein::IO;

use Ali::State;
use Ali::Import;
use Ali::Feature;
use Ali::Menus;
use Ali::DB;

use Install::Data;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub align_seq_stream
{
    # Niels Larsen, May 2008.

    # Replaces the stream match sequences with aligned versions. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $align_method, $s_file, $o_file, $rows );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( sfile dbtype align_method flank_left flank_right ) ], 
        });

    $s_file = $args->sfile;
    $o_file = "$s_file.tmp";
    $align_method = $args->align_method;

    if ( $align_method =~ /^stacked_/ )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>> ORIGINAL MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Assemble alignment by simply stacking the original matches so
        # they align against the query; this works for any method, including
        # blast and pattern matches. 

        # Match-regions. Maps all subject sequences to the query, using the 
        # coordinates found by the similarity tool. Updates the stream file with 
        # a Seq field, where un-gapped sequence is replaced with gapped versions
        # that line up,
    
        $rows = Ali::Create->create_ali_from_sims(
            {
                "sfile" => $s_file,
                "ofile" => $o_file,
                "dbtype" => $args->dbtype,
            });

        &Common::File::delete_file( $s_file );
        &Common::File::rename_file( $o_file, $s_file );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FLANKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $align_method eq "stacked_align" )
        {
            # Align the flank regions and merge them with match regions by "sliding"
            # so no common gaps can be removed without destroying the alignment,

            if ( $rows > 1 and $args->flank_left )
            {
                Ali::Create->align_seq_stream_field(
                    {
                        "sfield" => "Seq_flank_left",
                        "sfile" => $s_file,
                        "ofile" => $o_file,
                        "method" => "muscle",
                    });
                
                &Common::File::delete_file( $s_file );
                &Common::File::rename_file( $o_file, $s_file );
            }        
            
            if ( $rows > 1 and $args->flank_right )
            {
                Ali::Create->align_seq_stream_field(
                    {
                        "sfield" => "Seq_flank_right",
                        "sfile" => $s_file,
                        "ofile" => $o_file,
                        "method" => "muscle",
                    });
                
                &Common::File::delete_file( $s_file );
                &Common::File::rename_file( $o_file, $s_file );
            }        
            
            # Merge flanks and sequences, if any,
            
            Ali::Create->append_stream_fields(
                {
                    "ifields" => [ "Seq_flank_left", "Seq", "Seq_flank_right" ],
                    "ofield" => "Seq",
                    "sfile" => $s_file,
                    "ofile" => $o_file,
                });
            
            &Common::File::delete_file( $s_file );
            &Common::File::rename_file( $o_file, $s_file );
        }
        elsif ( $align_method eq "stacked_append" )
        {
            # Do not align flank sequences, but merely attach them to the match 
            # regions left and right, so they become continuous,

            Ali::Create->append_flanks(
                {
                    "sfile" => $s_file,
                    "ofile" => $o_file,
                    "flank_left" => $args->flank_left,
                    "flank_right" => $args->flank_right,
                });

            &Common::File::delete_file( $s_file );
            &Common::File::rename_file( $o_file, $s_file );
        }
        else {
            &error( qq (Wrong looking flank method -> "$align_method") );
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> REALIGN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Ignore the original matches made by the search routine and realign the
        # sequences. First merge unaligned match and flank sequences,

        $rows = Ali::Create->append_stream_fields(
            {
                "ifields" => [ "Seq_flank_left", "Seq", "Seq_flank_right" ],
                "ofield" => "Seq",
                "sfile" => $s_file,
                "ofile" => $o_file,
            });

        &Common::File::delete_file( $s_file );
        &Common::File::rename_file( $o_file, $s_file );

        # Then align the merged sequences, 

        if ( $rows > 1 )
        {
            Ali::Create->align_seq_stream_field(
                {
                    "sfield" => "Seq",
                    "sfile" => $s_file,
                    "ofile" => $o_file,
                    "method" => $align_method,
                });
            
            &Common::File::delete_file( $s_file );
            &Common::File::rename_file( $o_file, $s_file );
        }
    }

    return;
}

sub align_seq_stream_field
{
    # Niels Larsen, April 2008.

    # Invokes Sims::Run::run_$method on the given stream file, and creates the 
    # given stream output file. Temporary fasta files are used and deleted. 

    my ( $class,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $s_file, $s_field, $o_file, $tmp_file, $ali_file, $method );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( sfile sfield ofile method ) ],
            "HR:0" => [ qw ( params ) ],
        });

    # This aligns the sequences using some external method, like muscle.
    # So first write a fasta file, which most programs understand, from 
    # the stream,

    $s_file = $args->sfile;
    $s_field = $args->sfield;
    $o_file = $args->ofile;
    $method = $args->method;
    
    $tmp_file = "$s_file.seq.fasta";
    $ali_file = "$s_file.ali.fasta";
    
    Ali::Create->write_fasta_from_stream(
        {
            "head_field" => "Index",
            "data_field" => $s_field,
            "sfile" => $s_file,
            "ofile" => $tmp_file,
        }, $msgs );
    
    # Then run the alignment program, and delete temporary sequence file,
    
    {
        no strict "refs";
        
        &{ "Seq::Run::run_$method" }(
            {
                "ifile" => $tmp_file,
                "ofile" => $ali_file,
                "params" => {},
            }, $msgs );
    }

    &Common::File::delete_file( $tmp_file );
    
    # Fold the aligned sequences back into the stream, and delete fasta
    # alignment,
    
    Ali::Create->merge_fasta_into_stream(
        {
            "head_field" => "Index",
            "data_field" => $s_field,
            "ifile" => $ali_file,
            "istream" => $s_file,
            "ostream" => $o_file,
        }, $msgs );
    
    &Common::File::delete_file( $ali_file );

    return;
}

sub alis_from_sims_files
{
    # Niels Larsen, April 2007.

    # Processes all similarity (.sims) files in a given directory, and creates
    # a corresponding set of alignment files (.pdl, .info), and states for the
    # viewers (.state, .state.first). Features and tooltip texts are loaded to 
    # a user-database as part of creating the alignments. The routine is not 
    # specific to a particular method or datatype, but uses the supplied 
    # "align_method" to create alignments from them. There are strict argument
    # requirements, see the code.

    my ( $sims_files,
         $args,        # Arguments, a Common::Option object
         $msgs,        # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $sims_file, $post_params, $cache_file, $query_id, @gaps, $ali_file,
         $stream_file, $sims, $counts, $ft_load, $ft_menu, $dbh, $seq_count, $ft_count, 
         $q_seq, $q_file, $id1, $ft_names, $db_type, $routine, $method, $pps,
         $maxrow );
    
    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( sid res_dir tab_dir dbname dbtype dbpath ) ], 
            "HR:1" => [ qw ( post_params ) ],
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>> FETCH SEQUENCES IF NEEDED <<<<<<<<<<<<<<<<<<<<<

    if ( not @{ $sims_files } )
    {
        $sims_files = &Common::File::list_files( $args->res_dir, '.sims$' );
        $sims_files = [ map { $_->{"path"} } @{ $sims_files } ];
    }

    if ( not $args->dbname eq "clipboard" and 
         not Registry::Get->dataset( $args->dbname )->is_local_db )
    {
        Sims::Import->import_seqs_missing_files( $sims_files, $args->dbtype );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SIMS FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $pps = $args->post_params;

    foreach $sims_file ( @{ $sims_files } )
    {
        $sims = &Common::File::eval_file( $sims_file );

        # >>>>>>>>>>>>>>>>>>>>>>> SET ORGANISM ID ETC <<<<<<<<<<<<<<<<<<<<<<<<<

        # Use NCBI Entrez to add taxid, title, label and orgname fields to 
        # each similarity object; for now, this can only be done for non-local
        # databases (TODO),
    
        if ( not $args->dbpath )
        {
            $cache_file = &Common::Names::replace_suffix( $sims_file, ".sim_info" );
            $sims = &Ali::Create::set_summary_info( $sims, $args->dbtype, $cache_file, $msgs );
        }

        # >>>>>>>>>>>>>>>>>>>>> READ QUERY SEQUENCE IF ANY <<<<<<<<<<<<<<<<<<<<<<<<

        $q_file = &Common::Names::replace_suffix( $sims_file, ".fasta" );
        
        if ( $pps->{"with_query_seq"} ) {
            $q_seq = bless &Seq::IO::read_seq_first( $q_file ), "Seq::Common";
        } else {
            undef $q_seq;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>> CONDENSE SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Combines match fragments in places where it can be done without
#     # stretching the alignment too much. The "locs2" fields are set to
#     # strings like '[[8,100],[117,200]]' or '[[200,117],[100,8]]', 
#     # which gives the coordinates of these matches,
    
#     if ( 0 ) # $pps->{"with_condense"} )
#     {
#         @sims = &Sims::Common::condense(
#             \@sims, {
#                 "dbtype" => $dbtype,
#                 "reflen" => scalar @gaps,
#             });
#     }
    
        # >>>>>>>>>>>>>>>>>>>>>>>>>> SORT SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<<

        if ( $pps->{"sort_sims"} )
        {
            $routine = "sort_sims_". $pps->{"sort_sims"};
            $sims = Ali::Create->$routine( $sims );
        }
        
        # >>>>>>>>>>>>>>>>>>>> CREATE SEQUENCE STREAM FILE <<<<<<<<<<<<<<<<<<<<

        # Convert matching regions, and regions in between, to a stream file 
        # of unaligned sequence, with optional flanks. Sequences are fetched
        # from local or remote archives and complemented if ncessary to line up
        # with the query. If there is a query sequence (query could also be a
        # pattern etc), then that becomes the first in the stream,

        $stream_file = &Common::Names::replace_suffix( $sims_file, ".stream" );

        if ( not -r $stream_file )
        {
            &Ali::Create::create_seq_stream(
                 $sims, $q_seq, {
                     "dbtype" => $args->dbtype,
                     "dbpath" => $args->dbpath,
                     "ofile" => $stream_file,
                     "flank_left" => $pps->{"flank_left"},
                     "flank_right" => $pps->{"flank_right"},
                 });
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>> ALIGN SEQUENCE MATCHES <<<<<<<<<<<<<<<<<<<<<<

        # Adds gaps to the stream sequence matches. The gap insertion is done
        # either by an external program such as muscle, or by routines in this
        # module that maps the original blast matches against the query,

        &Ali::Create::align_seq_stream(
            {
                "sfile" => $stream_file,
                "dbtype" => $args->dbtype,
                "align_method" => $pps->{"align_method"},
                "flank_left" => $pps->{"flank_left"},
                "flank_right" => $pps->{"flank_right"},
            }, $msgs );
    
        # >>>>>>>>>>>>>>>>>>>>>>> ADD SIDS TO STREAM <<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Creates new version of the stream file (for now),
        
        &Ali::Create::set_stream_labels(
            {
                "sfile" => $stream_file,
                "ofile" => "$stream_file.tmp",
            });
        
        &Common::File::delete_file( $stream_file );
        &Common::File::rename_file( "$stream_file.tmp", $stream_file );

        # >>>>>>>>>>>>>>>>>>>>>>>> IMPORT ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<

         $query_id = $sims->[0]->id1;
        $db_type = &Common::Types::seq_to_ali( $args->dbtype );

        $ft_names = [ "ali_sid_text" ];
        
        if ( $pps->{"align_method"} and 
             $pps->{"align_method"} !~ /^blastalign$/ )
        {
            push @{ $ft_names }, "ali_sim_match";
        }

        push @{ $ft_names }, Common::Menus->datatype_features( $db_type )->options_names;

        &Install::Data::import_alignment(
            {
                "source" => $args->dbname,
                "title" => $query_id,
                "label" => "",
                "ifile" => $stream_file,
                "iformat" => "stream",
                "itype" => $db_type,
                "opath" => &Common::Names::strip_suffix( $sims_file ),
                "tab_dir" => $args->tab_dir,
                "ft_names" => $ft_names,
                "db_name" => $args->sid,
            }, $msgs );

        # >>>>>>>>>>>>>>>>>>>>> SPECIAL STATE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<

        # This section creates a menu of features, where there is at least
        # one occurrence - users will not see feature options without hits
        # (alternatively one could grey those out, but not all browsers 
        # support CSS in pulldown menus yet). 

         &Ali::Create::create_state_files(
             {
                 "ali_file" => &Common::Names::replace_suffix( $sims_file, ".pdl" ),
                 "state_file" => &Common::Names::replace_suffix( $sims_file, ".state" ),
                 "query_len" => scalar @gaps,
                "with_query_seq" => $pps->{"with_query_seq"},
             }, $msgs );
        
#        &Common::File::delete_file_if_exists( $sims_file );
#        &Common::File::delete_file_if_exists( $stream_file );
    }
    
    return $seq_count;
}

sub aliseq_from_sim_forward
{
    # Niels Larsen, January 2007.

    # Given an unaligned string and a gap recipe, creates a string with 
    # gaps inserted,

    my ( $obj,           # Stream sequence entry
         $gaps,          # Gap list
         $msgs,          # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a string.

    my ( $ali_str, $seq_max2, $locs1, $locs2, $beg1, $beg2, $end1, $end2, 
         $count, $sub_str, $i_max, $i, $gap_list, $sub_seq, $info, $len2,
         $llocs2, $loc, $lmatch_off, $col_sum, $seq_beg2, $seq_end2, 
         $flank, $hit_max2, $hit_end2, $seq2, $seq_beg1, $seq_end1 );

    $ali_str = "";

    $locs1 = eval $obj->Sim_locs1->name;
    $locs2 = eval $obj->Sim_locs2->name;

    if ( $locs2->[0]->[0] > 0 ) {
        $locs2 = &Seq::Common::decrement_locs( $locs2, $locs2->[0]->[0] );
    }

    $seq2 = $obj->Seq->name;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LEFT FLANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This prepends the given number of unaligned residues to the left of 
    # the matches, and sets the sequence index of the left-most residue 
    # that is visible in the alignment; both are returned below,

    $seq_beg1 = $locs1->[0]->[0];

    if ( $seq_beg1 > 0 )
    {
        $col_sum = &Ali::Create::sum_columns( $gaps, 0, $seq_beg1-1 );
        $ali_str .= "-" x $col_sum;
    }
    
    # >>>>>>>>>>>>>>>>>>>>> WITHIN AND BETWEEN MATCHES <<<<<<<<<<<<<<<<<<<

    $i_max = $#{ $locs2 };

    for ( $i = 0; $i <= $i_max; $i++ )
    {
        # Within matches,

        ( $beg1, $end1 ) = @{ $locs1->[$i] };
        ( $beg2, $end2 ) = @{ $locs2->[$i] };

        $sub_seq = substr $seq2, $beg2, $end2 - $beg2 + 1;   # Matching subject sub-sequence

        $gap_list = [ @{ $gaps }[ $beg1 .. $end1 ] ];        # Gap list of same length or longer

        $ali_str .= &Ali::Create::insert_gaps_within_matches_forward( $sub_seq, $gap_list, "-" );
        
        # Between matches,

        if ( $i < $i_max )
        {
            $beg1 = $end1 + 1;                          # one past last match
            $end1 = $locs1->[$i+1]->[0] - 1;            # one less than next match

            $beg2 = $end2 + 1;                          # one past last match
            $end2 = $locs2->[$i+1]->[0] - 1;            # one less than next match

            if ( $beg2 <= $end2 ) {
                $sub_seq = substr $seq2, $beg2, $end2 - $beg2 + 1;
            } else {
                $sub_seq = "";
            }

            $col_sum = &Ali::Create::sum_columns( $gaps, $beg1, $end1 );
            
            $ali_str .= &Ali::Create::insert_gaps_between_matches_forward( $sub_seq, $col_sum, "-" );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> RIGHT FLANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This appends the given number of unaligned residues to the right of 
    # the matches, and sets the sequence index of the right-most residue 
    # that is visible in the alignment; both are returned below,

    $seq_end1 = $locs1->[-1]->[1];

    if ( $seq_end1 < $#{ $gaps } )
    {
        $col_sum = &Ali::Create::sum_columns( $gaps, $seq_end1, $#{ $gaps }-1 );
        $ali_str .= "-" x $col_sum;
    }

    return $ali_str;
}

sub append_flanks
{
    # Niels Larsen, June 2008.

    # Adds unaligned flank sequences to the aligned matches. 

    my ( $class,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $s_file, $o_file, $obj, $seq, $gaplen, $len_diff, $max_left, 
         $max_right, $sfh, $newgaps, $gap_expr );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( sfile ofile flank_left flank_right ) ], 
            "HR:0" => [ qw ( post_params ) ],
        });

    $s_file = $args->sfile;
    $o_file = $args->ofile;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> READ <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sfh = Boulder::Stream->new( -in => $s_file );

    $max_left = 0;
    $max_right = 0;
    $gap_expr = '[~.-]*';

    while ( $obj = $sfh->get )
    {
        $seq = $obj->Seq;
        
        if ( $seq =~ /^($gap_expr)/ ) {
            $gaplen = length $1;
        } else {
            $gaplen = 0;
        }

        $len_diff = (length $obj->Seq_flank_left) - $gaplen;

        if ( $len_diff > $max_left ) {
            $max_left = $len_diff;
        }

        if ( $seq =~ /($gap_expr)$/ ) {
            $gaplen = length $1;
        } else {
            $gaplen = 0;
        }

        $len_diff = (length $obj->Seq_flank_right) - $gaplen;

        if ( $len_diff > $max_right ) {
            $max_right = $len_diff;
        }
    }

    undef $sfh;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sfh = Boulder::Stream->new( -in => $s_file, -out => $o_file );

    while ( $obj = $sfh->get )
    {
        $seq = $obj->Seq;
        
        if ( $seq =~ /^($gap_expr)/ ) {
            $newgaps = ( length $1 ) + $max_left;
        } else {
            $newgaps = $max_left;
        }

        $newgaps -= length $obj->Seq_flank_left;

        $seq =~ s/^$gap_expr//;
        $seq = ("-" x $newgaps) . $obj->Seq_flank_left . $seq;

        if ( $seq =~ /($gap_expr)$/ ) {
            $newgaps = ( length $1 ) + $max_right;
        } else {
            $newgaps = $max_right;
        }

        $newgaps -= length $obj->Seq_flank_right;

        $seq =~ s/$gap_expr$//;
        $seq = $seq . $obj->Seq_flank_right . ("-" x $newgaps);

        $obj->replace( "Seq" => $seq );

        $sfh->put( $obj );
    }
    
    undef $sfh;
    
    return;
}

sub create_ali_from_sims
{
    # Niels Larsen, January 2007.

    # Writes an alignment from a query sequence and a list of similarities
    # between that and any remote or local database entries. It is written 
    # as a "stream" with the suffix .stream appended to the added. 
    # the suffix ".fasta_ali" appended to the given prefix. Similarities 
    # are returned with the extra field "llocs2" which are like "locs2" 
    # but local coordinates.

    my ( $class,
         $args,             # Arguments hash
         $msgs,             # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $sifile, $dbtype, $sofile, $sfh, $obj, $s_id, $q_len, $s_ali,
         $s_type, @sims, @gaps, $count );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( sfile dbtype ofile ) ],
    });

    $sifile = $args->sfile;
    $dbtype = $args->dbtype;
    $sofile = $args->ofile;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> READ STREAM FIRST TIME <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # We must read the stream twice to know 1) how much padding to add to the flank 
    # ends so everything lines up, and 2) we must make allowance for various gap 
    # lengths in different places, to make sure everything lines up within the 
    # matching regions. This section does both those things. 

    $sfh = Boulder::Stream->new( -in => $sifile );
    
    while ( $obj = $sfh->get )
    {
        if ( $obj->Type eq "subject" )
        {
            # Make list of similarity objects needed below, 

            push @sims, Sims::Common->new(
                "id2" => $obj->ID,
                "frame1" => $obj->Seq_frame1,
                "frame2" => $obj->Seq_frame2,
                "locs1" => $obj->Sim_locs1,
                "locs2" => $obj->Sim_locs2,
                );
        }
        elsif ( $obj->Type eq "query" )
        {
            $q_len = $obj->Seq_len;
        }
        else {
            $s_id = $obj->ID;
            $s_type = $obj->Type;
            &error( qq (Wrong looking stream type ($s_id) -> "$s_type") );
        }
    }

    undef $sfh;

    # If there is a query sequence, use that, otherwise infer,

    if ( defined $q_len ) {
        @gaps = &Ali::Create::create_gap_mask_from_sims( \@sims, $q_len );
    } else {
        @gaps = (0) x &Ali::Create::find_gap_mask_length_from_sims( \@sims );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> READ STREAM SECOND TIME <<<<<<<<<<<<<<<<<<<<<<<<<<

    $sfh = Boulder::Stream->new( -in => $sifile, -out => $sofile );
    $count = 0;

    while ( $obj = $sfh->get )
    {
        # Given an unaligned string and a gap recipe, creates a string with 
        # gaps inserted,

        if ( $obj->Type eq "query" ) {
            $s_ali = &Ali::Create::insert_gaps_within_matches_forward( $obj->Seq->name, \@gaps, "-" );
        } else {
            $s_ali = &Ali::Create::aliseq_from_sim_forward( $obj, \@gaps, $msgs );
        }

        # Sequence comparison check, gives fatal error if gapped sequence 
        # does not perfectly match the original ungapped version,

        &Ali::Create::seq_diff_check( $s_ali, $obj->Seq->name, $dbtype );

        $obj->replace( "Seq" => $s_ali );

        $sfh->put( $obj );

        $count += 1;
    }

    undef $sfh;

    return $count;
}

sub create_gap_mask_from_sims
{
    # Niels Larsen, January 2007.

    # Creates a list of integers with the same number of elements as the length
    # of the given sequence string. Each element means "maximum number of gaps at
    # this position that would accomodate all sequences so they still align".
    # the sequence residue with the same index in a parallel sequence list". The
    # list could be 
    # 
    # .. 0,1,0,0,3,

    my ( $sims,        # List of similarities
         $length,
         ) = @_;

    # Returns a list.

    my ( $sim, $locs1, $locs2, $end1, $beg1, $beg2, $end2, $cols1, $cols2, 
         $i, @gaps, $coldiff, $maxend1 );

    @gaps = (0) x $length;

    foreach $sim ( @{ $sims } )
    {
        if ( $sim->frame1 > 0 )
        {
            $locs1 = $sim->locs1;
            $locs2 = $sim->locs2;

            if ( $sim->frame2 < 0 )
            {
                $locs1 = &Seq::Common::reverse_locs( $locs1 );
                $locs2 = &Seq::Common::complement_locs( $locs2, $locs2->[-1]->[1] + 1 );
            }

            for ( $i = 0; $i < $#{ $locs1 }; $i++ )
            {
                $beg1 = $locs1->[$i]->[1] + 1;
                $end1 = $locs1->[$i+1]->[0] - 1;

                $cols1 = &Ali::Create::sum_columns( \@gaps, $beg1, $end1 );

                $beg2 = $locs2->[$i]->[1] + 1;
                $end2 = $locs2->[$i+1]->[0] - 1;

                $cols2 = $end2 - $beg2 + 1;

                if ( $cols2 > $cols1 )
                {
                    $gaps[ $beg1-1 ] += $cols2 - $cols1;
                }
            }                
        }
        else {
            &error( qq (Sequence 1 in negative frame: ). $sim->frame1 );
        }
    }

    return wantarray ? @gaps : \@gaps;
}

sub create_state_files
{
    # Niels Larsen, March 2008.

    # Writes state files with a window that includes the search results. IMPROVE.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns nothing. 

    my ( $ali, $beg_pos, $end_pos, $width, $beg_col, $beg_row, $state, $subali );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ali_file state_file with_query_seq ) ],
        "S:0" => [ qw ( query_len ) ],
    });

    # Try to create a reasonable viewport based on the size of the 
    # matching region,

    $ali = &Ali::IO::connect_pdl( $args->ali_file );

    if ( $args->with_query_seq )
    {
        $beg_pos = $ali->seq_to_ali_pos( 0, 0 );
        $end_pos = $ali->seq_to_ali_pos( 0, ($args->query_len) - 1 );
    } 
    else 
    {
        $beg_pos = 0;
        $end_pos = $ali->max_col;
    }
    
    $width = int ( ( $end_pos - $beg_pos + 1 ) * 2.0 );
    $beg_col = &List::Util::max( 0, $beg_pos - int ( $width * 0.25 ) );
    $beg_row = 0;
    
    $state = &Ali::State::default_state();
    
    $state->{"ali_start_width"} = $width;
    $state = $ali->_fit_data_to_image( $state );        
    delete $state->{"ali_start_width"};

    $subali = $ali->subali_down( $beg_col || 0, $beg_row || 0, $state );
    
    $state->{"ali_colstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_cols->list ] );
    $state->{"ali_rowstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_rows->list ] );
    
    $state->{"ali_sid_left_indent"} = "left";        # Left-align short ids
    $state->{"ali_display_type"} = "characters";     # Show characters 
    
    $state->{"ali_title"} = $subali->title;
    
    &Common::File::store_file( $args->state_file, $state );
    &Common::File::store_file( $args->state_file .".first", $state );
    
    undef $ali;
    undef $subali;
    undef $state;

    return;
}
        
sub create_seq_stream
{
    # Niels Larsen, April 2008.

    # Creates a stream file from a list of similarities, adding flanks if wanted. 
    # Sequences on the opposite strand are complemented, ready to be aligned with 
    # a routine that inserts gaps (either by realigning or by following a recipe).
    # The stream object has these fields,
    # 
    #   Index            non-negative integer
    #   ID               string, no whitespace
    #   Label            string, whitespace ok
    #   TaxId            string, no whitespace
    #   Title            string, whitespace is ok
    #   OrgName          string, whitespace is ok
    #   Type             string, "query" or "subject"
    #   Seq              string, a DNA, RNA or protein string
    #   Seq_flank_left   string, a DNA, RNA or protein string
    #   Seq_flank_right  string, a DNA, RNA or protein string
    #   Score            positive number
    #   Seq_beg          positive integer
    #   Seq_end          positive integer
    #   Seq_len          positive integer
    #   Seq_frame1       positive integer, always 1 for now (subject sequences are flipped)
    #   Seq_frame2       1 or -1, for positive or opposite strand
    #   Sim_locs1        list of [m,n] where m <= n 
    #   Sim_locs2        list of [m,n] where m <= n; when Seq_frame2 is -1, then the 
    #                    numberings are in the coordinates of the complemented sequence. 
    #   Sim_rows         list of [m,n] where m <= n
    # 
    # The number of objects in the stream is returned. 

    my ( $sims,                # List of similarities
         $q_seq,               # Query sequence object
         $args,                # Arguments hash
         $msgs,                # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns integer. 

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ofile dbtype dbpath ) ],
        "S:0" => [ qw ( flank_left flank_right ) ],
    });

    my ( $o_file, $db_type, $db_path, $o_fh, $irow, $q_len, $stone, $s_orig, $flank,
         $module, $s_bio, $s_match, $s_beg, $s_end, $s_len, $indexed, $sim, 
         $s_id, $s_left, $s_right, $beg, $end );

    $db_type = $args->dbtype;
    $db_path = $args->dbpath;
    $o_file = $args->ofile;

    $o_fh = Boulder::Stream->newFh( -out => $o_file );
    $irow = 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PUT QUERY SEQ FIRST <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $q_seq ) 
    {
        $stone = Stone->new(
            "Index" => $irow,
            "ID" => $q_seq->id,
            "Label" => $q_seq->id,
            "Title" => "Submitted query sequence",
            "OrgName" => "",
            "Seq" => $q_seq->seq_string,
            "Seq_flank_left" => "",
            "Seq_flank_right" => "",
            "Type" => "query",
            "Seq_frame1" => 1,
            "Seq_frame2" => 1,
            "Seq_len" => $q_seq->seq_len,
            "Seq_beg" => 0,
            "Seq_end" => $q_seq->seq_len - 1,
            "Sim_rows" => &Common::Util::stringify( [[ $irow, $irow ]] ),
            );
        
        $o_fh->print( $stone );
        $irow += 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $module = &Common::Types::type_to_mol( $db_type ) ."::IO";

    if ( $db_path eq "" or -d $db_path )
    {
        $indexed = 0;
        $db_path = "";
    }
    else
    {
        if ( not -r "$db_path.bp_index" )
        {
            Seq::Import->write_fasta_db( 
                {
                    "i_file" => $db_path,
                    "o_prefix" => $db_path,
                }, $msgs );
        }

        $indexed = 1;
        $db_path = &Common::Names::strip_suffix( $db_path );
    }

    foreach $sim ( @{ $sims } )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FETCH SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Get the full-length sequence from local or remote archive, as a bioperl
        # object,

        $s_id = $sim->id2;

        if ( $indexed )        {
            $s_bio = $module->get_seq_indexed( $s_id, { "dbfile" => $db_path, "fatal" => 0 } );
        } else {
            $s_bio = $module->get_seq( $s_id, { "header" => 1, "dbtype" => $db_type, "fatal" => 0 } );
        };

        if ( not defined $s_bio ) {
            &warning( qq (Could not get sequence for id -> "$s_id") );
        }

        # >>>>>>>>>>>>>>>>>>>>>> FLIP SEQUENCE AND LOCATIONS <<<<<<<<<<<<<<<<<<<<<

        # All match sequences must be aligned to the query. Here the match sequence
        # and the corresponding match locations and frame codes are complemented,

        $s_len = $s_bio->seq_len;

        if ( $sim->frame1 >= 0 )
        {
            if ( $sim->frame2 >= 0 ) {
                $s_orig = $s_bio->seq;
            }
            else {
                $sim->locs2( &Seq::Common::complement_locs( $sim->locs2, $s_len ) );
                $s_orig = $s_bio->revcom->seq;
            }
        }
        elsif ( $sim->frame2 > 0 )
        {
            $s_orig = $s_bio->revcom->seq;

            $sim->locs1( &Seq::Common::complement_locs( $sim->locs1, $q_len ) );
            $sim->locs2( &Seq::Common::complement_locs( $sim->locs2, $s_len ) );

            $sim->frame1( 1 );
            $sim->frame2( -1 );
        }
        else {
            &error( qq (Both frame1 and frame2 are negative, programming error) );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> MATCH REGION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        ( $s_beg, $s_end ) = ( $sim->locs2->[0]->[0], $sim->locs2->[-1]->[1] );
        $s_match = substr $s_orig, $s_beg, $s_end-$s_beg+1;

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LEFT FLANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Increment $s_end so it becomes the index of the last base in the flank 
        # sequence, 

        $flank = $args->flank_left || 0;

        if ( $flank > 0 and $s_beg > 0 )
        {
            $end = $s_beg - 1;
            $beg = &List::Util::max( 0, $s_beg - $flank );

            $s_left = substr $s_orig, $beg, $end-$beg+1;
            $s_beg = $beg;
        }
        else {
            $s_left = "";
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RIGHT FLANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Increment $s_end so it becomes the index of the last base in the flank 
        # sequence, 

        $flank = $args->flank_right || 0;

        if ( $flank > 0 and $s_end < $s_len-1 )
        {
            $beg = $s_end + 1;
            $end = &List::Util::min( $s_len-1, $s_end + $flank );

            $s_right = substr $s_orig, $beg, $end-$beg+1;
            $s_end = $end;
        }
        else {
            $s_right = "";
        }
                
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # The stream format below is the beginning of "streams". Other methods 
        # may read this stream and change one or more fields, such as align the 
        # sequences. There are routines to write raw format from a stream, e.g.
        # Ali::Import::write_pdl_from_stream.

        $stone = Stone->new(
            "Type" => "subject",
            "Index" => $irow,
            "ID" => $s_id,
            "Label" => $sim->label || "",
            "TaxId" => $sim->taxid || "",
            "Title" => $sim->title || "",
            "OrgName" => $sim->orgname || "",
            "Seq_flank_left" => $s_left,
            "Seq" => $s_match,
            "Seq_flank_right" => $s_right,
            "Score" => $sim->score,
            "Seq_beg" => $s_beg,
            "Seq_end" => $s_end,
            "Seq_len" => $s_len,
            "Seq_frame1" => $sim->frame1,
            "Seq_frame2" => $sim->frame2,
            "Sim_locs1" => &Common::Util::stringify( $sim->locs1 ),
            "Sim_locs2" => &Common::Util::stringify( $sim->locs2 ),,
            "Sim_rows" => &Common::Util::stringify( [[ $irow, $irow ]] ),
            );

        $o_fh->print( $stone );

        $irow += 1;
    }

    undef $o_fh;

    return $irow;
}

sub create_summary_hash
{
    # Niels Larsen, August 2007.

    # From a list of GI numbers,

    my ( $gis,           # List of GI numbers
         $dbtype,        # Data type
         $ofile,
        ) = @_;

    # Returns a list.

    my ( $i_stream, $o_stream, @sim_stones, %sim_info, $sim_stone, @gis,
         @sim_ids, @tax_stones, %tax_stones, $tax_stone, $stone, %counts, 
         $org_str, $org_sid, $seq_desc, @tax_ids, $id, $item, $attrib,
         $name, %tax_info, $sim_info, $tax_id, $info, $msgs, $msgstr );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE HASH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create %sim_info with taxonomy id, description line, accession number
    # and GI number from NCBI, fetched with Entrez. Also create %tax_info
    # with scientific organism name string. We use those below to look up
    # values to put into the stream.

    if ( $gis and @{ $gis } )
    {
        $msgs = [];

        @gis = &Common::Util::uniqify( $gis );
        
        @sim_stones = &Common::Entrez::fetch_summaries( \@gis, {
            "db" => "sequences",
            "dbtype" => $dbtype,
            "idtype" => "gi",
            "oformat" => "stream",
            "debug" => &Common::Names::replace_suffix( $ofile, ".ids_xml" ),
        }, $msgs );

        if ( @{ $msgs } ) {
            $msgstr = &echo_messages( $msgs );
            &warning( $msgstr );
        }

        foreach $stone ( @sim_stones )
        {
            $id = $stone->Id;
            
            foreach $item ( $stone->Item )
            {
                if ( $attrib = $item->attributes and $name = $attrib->{"Name"} )
                {
                    if ( $name =~ /^TaxId|Title|Caption|Gi$/ )
                    {
                        $sim_info{ $id }{ $name } = $item->name;
                        push @tax_ids, $item->name if $name eq "TaxId";
                    }
                }
            }
        }
        
        @tax_ids = &Common::Util::uniqify( \@tax_ids );

        # Sometimes taxonomy ids of 0 are returned, which is invalid, so filter
        # those away,

        @tax_ids = grep { $_ > 0 } @tax_ids;

        @tax_stones = &Common::Entrez::fetch_summaries( \@tax_ids, {
            "db" => "taxonomy",
            "dbtype" => "orgs_tax",
            "idtype" => "tax",
            "oformat" => "stream",
            "debug" => &Common::Names::replace_suffix( $ofile, ".tax_xml" ),
        }, $msgs );

        # Problem: errors turns out to be quite common in the xml output, 
        # typically a tax id is not found, even though it is part of other
        # records. So we dont warn anymore, but tolerate.

#         if ( @{ $msgs } ) {
#             $msgstr = &echo_messages( $msgs );
#             &warning( $msgstr );
#         }

        foreach $stone ( @tax_stones )
        {
            $id = $stone->Id;

            foreach $item ( $stone->Item )
            {
                if ( $attrib = $item->attributes and 
                     $name = $attrib->{"Name"} and $name eq "ScientificName" ) 
                {
                    $tax_info{ $id }{ $name } = $item->name;
                }
            }
        }

        foreach $id ( keys %sim_info )
        {
            $info = $sim_info{ $id };

            if ( $info->{"TaxId"} ) {
                $info->{"OrgName"} = $tax_info{ $info->{"TaxId"} }->{"ScientificName"};
            } else {
                $info->{"OrgName"} = "";
            }
        }
    }
    else {
        %sim_info = ();
    }

    return wantarray ? %sim_info : \%sim_info;
}

sub find_gap_mask_length_from_sims
{
    my ( $sims,
        ) = @_;

    my ( $length, $sim );

    $length = 0;
    
    foreach $sim ( @{ $sims } )
    {
        if ( $sim->frame1 > 0 )
        {
            $length = &List::Util::max( $length, $sim->end1 );
        }
        else {
            &error( qq (Sequence 1 in negative frame: ). $sim->frame1 );
        }
    }
    
    $length += 1;

    return $length;
}

sub insert_gaps_between_matches_forward
{
    # Niels Larsen, February 2007
    
    # Inserts gap characters between matches:
    # 
    # aaa--ggggg          aaaggggg           query sequence
    # 00200000       or   00200000           gap list recipe
    # aaattggggg          aaa--ggg           subject sequence
    # 
    # The number 2 is the length of the void in which to accomodate the 
    # subject sequence: maybe there are no unaligned bases, then 2 gaps
    # will be added to the sequence; or if 1 base, then only one gap, and
    # so on. The number always means number of positions to be inserted 
    # in the sequence AFTER its own index position. The routine attempts
    # to put gaps in the middle of the vacant region where possible. 

    my ( $seq,             # Sequence string
         $cols,            # Column width
         $gapch,           # Gap character
         ) = @_;

    # Returns a string.

    my ( $beg_str, $end_str, $gap_str, $ali_seq );

    $gapch = "-" if not defined $gapch;
    
    ( $beg_str, $end_str ) = &Common::Util::break_string_in_half( $seq );

    $gap_str = $gapch x ( $cols - length $seq );

    $ali_seq = "$beg_str$gap_str$end_str";

    return $ali_seq;
}

sub insert_gaps_within_matches_forward
{
    # Niels Larsen, February 2007
    
    # Inserts gap characters BETWEEN all characters in a string, like so:
    # 
    # aggtctaa       without gaps inserted
    # 10200101       gap list recipe
    # a-gg--tct-aa   with gaps inserted
    # 
    # Notice no gap after the final character, that is handled by the routine
    # that does gap insertion between matches. 

    my ( $seq,             # Sequence string
         $gaps,            # Gap list
         $gapch,           # Gap character
         ) = @_;

    # Returns a string.

    my ( $seq_len, $gap_len, $i, $j, $ali_seq );

    $seq_len = length $seq;
    $gap_len = scalar @{ $gaps };

    $ali_seq = "";

    for ( $i = 0; $i <= $seq_len - 2; $i++ )
    {
        $ali_seq .= substr $seq, $i, 1;
        
        if ( $gaps->[$i] > 0 ) 
        {
            $ali_seq .= $gapch x $gaps->[$i];
        }
    }

    $ali_seq .= substr $seq, $seq_len-1, 1;

    if ( $gap_len > $seq_len )
    {
        $ali_seq .= $gapch x ( $gap_len - $seq_len );
    }

    return $ali_seq;
}

sub merge_fasta_into_stream
{
    # Niels Larsen, April 2008.

    # Reads through a stream file and replaces a given sequence field 
    # alternatives in a given fasta file. Entries in the stream where
    # no fasta record exists is set to gaps. The entries in the fasta 
    # file and the stream must have the same order. 

    my ( $class,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $tmp, $ifh, $sfh, $i, $obj, $aseq, $seqstr, $alen, $head_field,
         $data_field );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( head_field data_field ifile istream ostream ) ], 
        });

    # Open three files,

    $sfh = Boulder::Stream->new( -in => $args->istream, -out => $args->ostream );
    $ifh = &Common::File::get_read_handle( $args->ifile );

    # Get first sequence and its length (assume same length for all),

    $aseq = bless &Seq::IO::read_seq_fasta( $ifh ), "Seq::Common";
    $alen = $aseq->seq_len;   # Aligment length

    # When stream and fasta ids are read, the next fasta entry is read.
    # 

    $head_field = $args->head_field;
    $data_field = $args->data_field;

    while ( $obj = $sfh->get )
    {
        if ( defined $aseq and $aseq->id eq $obj->$head_field ) 
        {
            $obj->replace( $data_field => $aseq->seq );
            $aseq = bless &Seq::IO::read_seq_fasta( $ifh ), "Seq::Common";
        }
        else
        {
            $seqstr = $obj->$data_field || "";

            if ( length $seqstr < $alen )
            {
                $obj->replace( $data_field => $seqstr . ("-" x ( $alen - length $seqstr ) ) );
            }
        }

        $sfh->put( $obj );
    }

    $ifh->close;
    undef $sfh;

    return;
}

sub append_stream_fields
{
    # Niels Larsen, May 2008.

    # 

    my ( $class,
         $args,
         $msgs,
        ) = @_;

    my ( $sfh, $obj, @fields, $ofield, $field, $str, $count );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( ofield sfile ofile ) ],
            "AR:1" => [ qw ( ifields ) ],
        });

    $sfh = Boulder::Stream->new( -in => $args->sfile, -out => $args->ofile );

    @fields = @{ $args->ifields };
    $ofield = $args->ofield;

    $count = 0;

    while ( $obj = $sfh->get )
    {
        $str = "";

        foreach $field ( @fields )
        {
            if ( defined $obj->$field )
            {
                $str .= lc $obj->$field;
#                $obj->delete( $field );
            }
        }

        $obj->replace( $ofield => $str );

        $sfh->put( $obj );

        $count += 1;
    }        

    undef $sfh;

    return $count;
}

sub save_job_results
{
    # Niels Larsen, January 2008. 

    # Constructs the menu that lists the results, as a YAML file named 
    # results_menu.yaml in the given job directory. 

    my ( $args,         
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( @files, $file, $opt, @opts, $menu, $ali, $hits, $name, $job_dir, 
         $job_id );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( job_dir job_id ) ],
    });

    $job_dir = $args->job_dir;
    $job_id = $args->job_id;

    @files = &Ali::IO::list_alis_pdl( $job_dir );

    foreach $file ( map { $_->{"path"} } @files )
    {
        # Get the file name and strip suffix - thats the id used,

        $name = File::Basename::basename( $file ); 
        $name = &Common::Names::strip_suffix( $name );

        $opt = Common::Option->new( "id" => $name );
    
        $ali = &Ali::IO::connect_pdl( $file );

        $hits = $ali->max_row + 1;

        $opt->sid( $ali->sid );
        $opt->title( $ali->title ." ($hits)" );
        $opt->datatype( $ali->datatype );
        $opt->jid( $job_id );

        $opt->input( "Analyses/$job_id/$name" );
   
        push @opts, &Storable::dclone( $opt );

        undef $ali;
    }

    @opts = sort { $a->id <=> $b->id } @opts;

    $menu = Common::Menu->new( "id" => $job_id, "name" => "result_views" );
    
    $menu->options( \@opts );
    
    $file = "$job_dir/results_menu.yaml";

    &Common::File::write_yaml( $file, $menu );

    return $menu;
}

sub seq_diff_check
{
    # Niels Larsen, January 2007.

    # Checks that two sequences are the same, where one may contain gaps and the 
    # other - the reference sequence - may not. This is merely a safety routine.
    # If the two are different, they are put into an alignment routine that prints
    # debug information and then makes a fatal error. 

    my ( $aliseq,           # Stone to be written
         $refseq,          # Unaligned sequence string
         $seqtype,
         ) = @_;

    # Returns nothing.

    my ( $list, $routine, $str );

    $aliseq =~ s/[^A-Za-z]//g;

    if ( not &Common::Types::is_protein( $seqtype ) )
    {
        $aliseq =~ s/u/t/g;
        $refseq =~ s/u/t/g;
    }

    if ( $aliseq ne $refseq )
    {
        $routine = &Common::Types::type_to_mol( $seqtype ) . "::Ali::align_two_seqs";
    
        {
            no strict "refs";
            $list = $routine->( \$aliseq, \$refseq );
        }

        $str .= &dump( $list );
        $str .= &dump( "Before: $refseq" );
        $str .= &dump( " After: $aliseq" );
        
        &error( qq (Sequence comparison check failed: $str ) );
    }

    return;
}

sub set_stream_labels
{
    # Niels Larsen, May 2007.

    # Adds an organism abbreviation (Label) and a description line (Title)
    # for use as display labels, like alignment short ids and tooltips.
    # Takes a stream file as input and creates new version of it via a 
    # temporary file.

    my ( $args,
         $msgs,
         ) = @_;

    # Returns nothing.

    my ( $sfh, %counts, $org_sid, $seq_desc, $id, $org_id, $org_name,
         $info, $obj );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( sfile ofile ) ],
        });

    # >>>>>>>>>>>>>>>>>>>>>>>> MODIFY STREAM <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Add the fields "Title" and "Label" to the stream: title contains the 
    # description line from the record, label is an organism name abbreviation.
    # Similar abbreviations are appended numbers, e.g. Lac.lac.(2) and so on.

    $sfh = Boulder::Stream->new( -in => $args->sfile, -out => $args->ofile );

    %counts = ();

    while ( $obj = $sfh->get )
    {
        $id = $obj->ID;

        if ( ( $org_name = $obj->OrgName ) )
        {
            if ( defined $org_name ) {
                $org_sid = &Common::Names::create_org_id( $org_name, \%counts );
            } else {
                $org_sid = "";
            }
        }
        elsif ( $obj->Title ) {
            $org_sid = "?";
        } else {
            $org_sid = $id;
        }

        if ( $obj->Type eq "query" ) {
            $obj->replace( "Label" => $id );
        } else {
            $obj->replace( "Label" => $org_sid );
        }

        if ( $seq_desc = $obj->Title )
        {
            $seq_desc .= " ($id"; 

            if ( $obj->TaxId ) {
                $seq_desc .= ", tax. id ". $obj->TaxId;
            }

            $seq_desc .= ")";
            $seq_desc =~ s/\'//g;
        }
        else {
            $seq_desc = "Unknown organism, accession number $id";
        }                

        $obj->replace( "Title" => "$seq_desc." );

        $sfh->put( $obj );
    }
    
    undef %counts;

    return;
}

sub set_summary_info
{
    # Niels Larsen, August 2007.

    # Adds taxid, title, label and orgname fields to a list of similarity objects.
    # The information is fetched from NCBI using Entrez. If a "cache file" is given,
    # the information is not fetched from NCBI, but read from that file; and that 
    # file will be written if it does not exist.

    my ( $sims,          # List of similarities
         $dbtype,        # Datatype
         $cfile,         # Cache file - OPTIONAL
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $ids, $sim, $hash, $info, $gi );

    if ( defined $cfile and -r $cfile )
    {
        $hash = &Common::File::eval_file( $cfile );
    }
    else
    {
        $ids = [ map { $_->gi2 } @{ $sims } ];
        $hash = &Ali::Create::create_summary_hash( $ids, $dbtype, $cfile );

        if ( defined $cfile ) {
            &Common::File::dump_file( $cfile, $hash );
        }
    }

    foreach $sim ( @{ $sims } )
    {
        $gi = $sim->gi2;

        if ( exists $hash->{ $gi } )
        {
            $info = $hash->{ $sim->gi2 };

            $sim->taxid( $info->{"TaxId"} );
            $sim->title( $info->{"Title"} );
            $sim->label( $info->{"Caption"} );
            $sim->orgname( $info->{"OrgName"} );
        }
        else {
            push @{ $msgs }, [ "Error", qq (No summary information for GI -> "$gi") ];
        }
    }

    return wantarray ? @{ $sims } : $sims;
}

sub sort_sims_by_organism
{
    # Niels Larsen, August 2007.

    # Sorts similarities by taxonomy id, and where they are equal,
    # by score. Returns an updated list.

    my ( $class,
         $sims,
        ) = @_;

    # Returns a list.

    my ( $sim, @sims, %sims, $taxid );

    foreach $sim ( sort { $b->score <=> $a->score } @{ $sims } )
    {
        push @{ $sims{ $sim->{"taxid"} } }, $sim;
    }

    foreach $taxid ( sort { $a <=> $b } keys %sims )
    {
        push @sims, @{ $sims{ $taxid } };
    }
    
    return wantarray ? @sims : \@sims;
}

sub sort_sims_by_score
{
    # Niels Larsen, August 2007.

    # Sorts similarities by score. Returns an updated list.

    my ( $class,
         $sims,
        ) = @_;

    # Returns a list.

    my ( $sim, @sims, %sims );

    @sims = sort { $b->score <=> $a->score } @{ $sims };
    
    return wantarray ? @sims : \@sims;
}

sub sum_columns
{
    # Niels Larsen, January 2008.

    # Sums the number of columns coded by the gap list over a given range:
    # the range length plus the total number of gaps at each position. 

    my ( $gaps,       # Gap list
         $beg,        # Start index - OPTIONAL, default 0
         $end,        # End index - OPTIONAL, default max index
        ) = @_;

    # Returns integer. 

    my ( $sum );

    $beg //= 0;
    $end //= $#{ $gaps };

    $sum = &List::Util::sum( @{ $gaps }[ $beg-1 .. $end ] ) + $end - $beg + 1;

    return $sum;
}

sub write_fasta_from_stream
{
    # Niels Larsen, May 2008.

    # Writes a simple fasta file from a stream. The fasta header has just the 
    # indices of the objects in the stream.

    my ( $class,
         $args,         # Stream input file
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $sfh, $ofh, $obj, $head_field, $data_field );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( head_field data_field sfile ofile ) ],
        });
    
    $sfh = Boulder::Stream->new( -in => $args->sfile );
    $ofh = &Common::File::get_write_handle( $args->ofile );

    $head_field = $args->head_field;
    $data_field = $args->data_field;

    while ( $obj = $sfh->get )
    {
        if ( $obj->$data_field )
        {
            $ofh->print( ">". $obj->$head_field . "\n". $obj->$data_field ."\n" );
        }
    }

    $ofh->close;
    undef $sfh;

    return;
}

1;

__END__

# subseq_from_sim_forward
# {
#     # Niels Larsen, April 2008.

#     # Extracts a sub-sequence from a larger sequence, using the numbering in a 
#     # given similarity object. Flanks are added if "flank_left" or "flank_right"
#     # are positive. Returns ( sub-string, begin position on original, end position
#     # on original).

#     my ( $sim,           # Similarity object
#          $args,          # Parameters
#          ) = @_;

#     # Returns a list.

#     my ( $sub_seq, $seq_max2, $locs2, $beg2, $end2, $seq_beg2, $seq_end2, 
#          $flank, $seq2 );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ qw ( seq ) ],
#     });

#     $sub_seq = "";

#     $locs2 = $sim->locs2;
#     $seq2 = $args->seq;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LEFT FLANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Prepend the given number of unaligned residues to the left of 
#     # the matches, and set the original sequence number (seq_beg2) of 
#     # the left-most residue in the extracted sub-sequence,

#     $seq_beg2 = $locs2->[0]->[0];

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> MATCH REGION <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Add the sequence from the first match till the last,

#     $beg2 = $locs2->[0]->[0];
#     $end2 = $locs2->[-1]->[1];

#     $sub_seq .= substr $seq2, $beg2, $end2-$beg2+1;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> RIGHT FLANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Append the given number of unaligned residues to the right of 
#     # the matches, and set the original sequence number (seq_end2) of 
#     # the right-most residue in the extracted sub-sequence,

# #    $flank = $args->flank_right || 0;

#     $seq_end2 = $locs2->[-1]->[1];
# #    $seq_max2 = (length $seq2) - 1;

# #     if ( $flank > 0 and $seq_end2 < $seq_max2 )
# #     {
# #         $beg2 = $seq_end2 + 1;
# #         $end2 = &Common::Util::min( $seq_max2, $seq_end2 + $flank );

# #         $sub_seq .= substr $seq2, $beg2, $end2-$beg2+1;
# #         $seq_end2 = $end2;
# #     }

#     # Return the sub-sequence string, and the original sequence numbers
#     # of where the sub-sequence starts and ends,

#     return ( $sub_seq, $seq_beg2, $seq_end2 );
# }

# sub update_clipboard_menu
# {
#     my ( $args,
#          $msgs,
#         ) = @_;

#     my ( $res_menu, $res_opt, $clip_menu, @clip_opts );

#     $res_menu = Common::Menu->read_menu( $args->res_dir ."/results_menu" );

#     foreach $res_opt ( $res_menu->options )
#     {
#         push @clip_opts, Common::Option->new(
#             "jid" => $args->jid,
#             "coltext" => "",
#             "count" => $res_opt->id,
#             "input" => $res_opt->input,
#             "date" => &Common::Util::time_string_to_epoch(),
#             "userfile" => "",
#             "format" => "pdl",
#             "objtype" => "result",
#             "title" => $args->title ." (". $res_opt->id .")",
#             "datatype" => $res_opt->datatype,
#             );
#     }

#     $clip_menu = Common::Menus->clipboard_menu( $args->sid );

#     $clip_menu->append_options( \@clip_opts );
    
#     $clip_menu->write( $args->sid );
    
#     return;
# }

# sub _insert_gaps_after_matches
# {
#     # Niels Larsen, February 2007
    
#     # Left-justifies the characters in a string by inserting trailing
#     # gaps. The given gap character is used, otherwise "-". 

#     my ( $seq,             # Sequence string
#          $gaps,            # Gap list
#          $gapch,           # Gap character
#          ) = @_;

#     # Returns a string.

#     my ( $seq_len, $gap_len, $gap_sum, $gap_str, $out_str, $sub_seq,
#          $col_sum );

#     $gapch = "-" if not defined $gapch;

#     $seq_len = length $seq;
#     $gap_len = scalar @{ $gaps };

#     $gap_sum = &Common::Util::sum( [ @{ $gaps }[ 0 .. $gap_len - 1 ] ] );
#     $col_sum = $gap_sum + $gap_len - 1;

#     if ( $seq_len <= $col_sum )
#     {
#         $gap_str = $gapch x ( $col_sum - $seq_len );
#         $sub_seq = $seq;
#     }
#     else
#     {
#         $gap_str = "";
#         $sub_seq = substr $seq, 0, $col_sum;
#     }

#     $out_str = "$sub_seq$gap_str";

#     return $out_str;
# }

# sub _insert_gaps_before_matches
# {
#     # Niels Larsen, February 2007
    
#     # Inserts gaps before the characters in a string. The gaps 
#     # are the character given ("-" if none) and the gaps are the
#     # summed numbers in a given list minus the length of the 
#     # sequence. 

#     my ( $seq,             # Sequence string
#          $gaps,            # Gap list
#          $gapch,           # Gap character
#          ) = @_;

#     # Returns a string.

#     my ( $seq_len, $gap_len, $gap_sum, $col_sum, $gap_str, $ali_seq, $sub_seq );

#     $gapch = "-" if not defined $gapch;

#     $seq_len = length $seq;
#     $gap_len = scalar @{ $gaps };

#     $gap_sum = &Common::Util::sum( [ @{ $gaps }[ 0 .. $gap_len-1 ] ] );
#     $col_sum = $gap_sum + $gap_len;

#     if ( $seq_len <= $col_sum )
#     {
#         $gap_str = $gapch x ( $col_sum - $seq_len );
#         $sub_seq = $seq;
#     }
#     else
#     {
#         $gap_str = "";
#         $sub_seq = substr $seq, $seq_len-$col_sum, $col_sum;
#     }

#     $ali_seq = "$gap_str$sub_seq";

#     return $ali_seq;
# }


# sub insert_gap_flank_padding
# {
#     # Niels Larsen, February 2007.

#     # Pads a "ragged" alignment with gaps, so both beginnings and ends line up, the
#     # result being equally long lines that exactly accomodate the longest sequence.
#     # This is the last step in creating the alignment: a 

#     my ( $file,            # Input and output file
#          $gaps,
#          ) = @_;

#     # Returns nothing.

#     my ( $i_fh, $row, @begs, @ends, $q_locs, $s_locs, $q_beg, $s_beg, $q_cols, 
#          $s_cols, $q_max, $q_end, $s_end, $o_fh, $a_seq, $begs_max, $ends_max,
#          $i, $end_str, $beg_str, $gap_len, $ali_str, $is_reverse );

#     # Create list of 

#     $i_fh = Boulder::Stream->newFh( -in => $file );
   
#     while ( $row = <$i_fh> )
#     {
#         if ( $row->Type eq "query" )
#         {
#             push @begs, 0;
#             push @ends, 0;
#         }
#         else
#         {
#             $q_locs = eval $row->Sim_locs1;
#             $s_locs = eval $row->Sim_locs2;

#             # Before sequence start,

#             $q_beg = $q_locs->[0]->[0];

#             if ( $q_beg > 0 ) {
#                 $q_cols = $q_beg + &Common::Util::sum( [ @{ $gaps }[ 0 .. $q_beg-1 ] ] );
#             } else {
#                 $q_cols = 0;
#             }

#             $s_cols = $s_locs->[0]->[0] - $row->Seq_beg;

#             push @begs, &Common::Util::max( 0, $s_cols - $q_cols );  

#             # After sequence end,
            
#             $q_max = $#{ $gaps };

#             $q_end = $q_locs->[-1]->[1];
#             $q_cols = $q_max - $q_end + &Common::Util::sum( [ @{ $gaps }[ $q_end .. $q_max ] ] );

#             $s_cols = $s_locs->[0]->[0] - $row->Seq_end;

#             push @ends, &Common::Util::max( 0, $s_cols - $q_cols );  
#         }
#     }

#     undef $i_fh;

#     $begs_max = &List::Util::max( @begs );
#     $ends_max = &List::Util::max( @ends );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSERT PADDING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Rewrite stream file,    

#     $i_fh = Boulder::Stream->newFh( -in => $file );
#     $o_fh = Boulder::Stream->newFh( -out => "$file.tmp" );

#     $i = 0;

#     while ( $row = <$i_fh> )
#     {
#         $ali_str = $row->Seq;

#         # Left,

#         $gap_len = $begs_max - $begs[$i];

#         if ( $row->Seq_beg > 0 ) {
#             $beg_str = "." x $gap_len;
#         } else {
#             $beg_str = "~" x $gap_len;
#         }

#         # Right,

#         $gap_len = $ends_max - $ends[$i];

#         if ( $row->Seq_end < $row->Seq_len - 1 ) {
#             $end_str = "." x $gap_len;
#         } else {
#             $end_str = "~" x $gap_len;
#         }

#         $row->replace( "Seq" => "$beg_str$ali_str$end_str" );

#         $o_fh->print( $row );

#         $i += 1;
#     }
    
#     undef $i_fh;
#     undef $o_fh;

#     &Common::File::delete_file( $file );

#     if ( not rename "$file.tmp", $file ) {
#         &error( qq (Could not rename "$file.tmp" to "$file".) );
#     }

#     return;
# }
