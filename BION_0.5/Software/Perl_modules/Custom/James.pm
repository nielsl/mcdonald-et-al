package Custom::James;     #  -*- perl -*-

# Routines written only as part of a collaboration with James McDonald at 
# Bangor university in Wales. 
# 
# A sample was sequenced by two methods, PCR and shotgun based (RT). The 
# RT data has much more diversity and the routines in here are related to
# that, see explanations under each routine.

use strict;
use warnings FATAL => qw ( all );

use base qw (Exporter);
use feature "state";

our @EXPORT_OK = qw (
                     &primer_mismatch_taxonomy
                     );

use Storable qw ( dclone );
use List::Util;
use Time::HiRes;

use Common::Config;
use Common::Messages;
use Common::File;

use Registry::Args;

use Bio::Patscan;

use Seq::Common;
use Seq::IO;
use Seq::Simrank;

use Ali::Convert;
use Install::Import;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use constant Q_BEG => 0;
use constant Q_END => 1;
use constant DB_BEG => 2;
use constant DB_END => 3;
use constant LENGTH => 4;
use constant SCORE => 5;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use vars qw ( *AUTOLOAD );

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub primer_mismatch_taxonomy
{
    # Niels Larsen, November 2012. 

    # A sample was sequenced by both PCR and a modified shotgun approach (RT).
    # The RT data showed much more diversity, and we wondered if that could 
    # be due to the primers missing certain groups. To find that out, we make
    # a taxonomic overview of how well the primer sites fit: align the query 
    # sequences against the best-matching database sequences, and if that 
    # alignment includes the forward and/or reverse primer site, the number 
    # of mismatches, insertions and deletions are measured and saved. Those 
    # numbers are mapped to a taxonomy and numers + taxonomy are saved 
    # as a table. In more detail, the steps done are, in sequence:
    # 
    # * Find the reference sequence in the alignment that we know the primer
    #   matches well with.
    #
    # * Use that reference sequence to determine alignment coordinates of the
    #   primer match. We can then get the coordinates in any sequence where 
    #   primers are supposed to match (assuming the alignment is right).
    #
    # * Create a list of pairs of [ query id, [ best matching db ids ] ],
    #   reading from the simrank match file. That tells which sequences must
    #   be aligned.
    #
    # * For all the best matching db ids, create a lookup dictionary of 
    #   forward and reverse primer matches in sequence numbering. Then we 
    #   know which db-sequence regions to check for overlap with.
    #
    # * Extract a table of taxonomy strings from the RDP genbank distribution
    #   file. Index it with Kyoto Cabinet, so we can pull out strings at
    #   random.
    #
    # * Align each query sequence with its best matching db sequence(s).
    #
    # * If this alignment completely overlaps either forward or reverse primer
    #   locations, then measure the number of mismatches, insertions and 
    #   deletions.
    #
    # * Pull out the taxonomy strings for the best-matching db sequences.
    #
    # * Write a taxonomy table with these columns from left to right, where
    #   F- and R- means forward and reverse primer,
    # 
    #   F-mdi   Number of primer mismatches, deletions and insertions
    #   F-mis   Number of primers with m+d+i > 0
    #   F-ovl   Number of sequences that overlap forward primer region
    #   R-mdi   - same for reverse -
    #   R-mis   - same for reverse - 
    #   R-ovl   - same for reverse - 
    #   Alis    Number of sequences that align with closest DB hit
    #   DB hits Number of sequences that match the DB with simrank
    #   Taxonomy string
    # 
    # For more detail, see the code. 
    
    my ( $args,
        ) = @_;

    my ( $defs, $ref_mol, $mol_conf, $prefix, $suffix, $fh, $line, @db_sims, 
         $db_id, $db_sims, $ref_id, $ref_file, $ref_aseq, $ref_seq, $best_pct,
         $ref_max, $bact_ali, $ref_pos, $i, $j, $hits_cache, $sims, $seqs, 
         $db_ppos, $fwd_abeg, $fwd_aend, $rev_abeg, $rev_aend, $aseqs, $aseq,
         $seq, $db_prim, $prim_cache, $fwd_pat, $db_hits, %db_ids, $key,
         $rev_pat, $pat, $locs, $orient, $patstr, $q_id, $hit_beg, $hit_end,
         $file, @files, $out_dir, $tax_table, $tax_index, $src_newest, 
         @bads, $count, $seq_file, $dbh, $ali, $db_seq, $ppos, $sbeg, $send,
         $fwdmdi, $revmdi, $astr, $gaps, $substr, $subgaps, @table,
         $abeg, $aend, $params, %fwd_prim, %rev_prim, $fwd_alen, $rev_alen,
         $fwd_seq, $rev_seq, $beg_seq, $end_seq, $row, $th, $hits, $alis,
         $fwdovl, $revovl, $table );

    $defs = {
        "ref_id" => undef,
        "q_file" => "q.fq",
        "db_file" => "db.fa",
        "sim_file" => "tax.sims",
        "fwd_primer" => "GCCTAACACATGCAAGTC",
        "rev_primer" => "CCAGCAGCCGCGGTAAT",
        "silent" => 0,
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    &echo_bold("\nPrimer mismatch taxonomy:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ref_mol = "SSU";
    $mol_conf = $Taxonomy::Config::DBs{"RDP"}{ $ref_mol };
    $out_dir = $mol_conf->out_dir;

    $src_newest = &Common::File::get_newest_file( $mol_conf->src_dir )->{"path"};

    $prefix = $mol_conf->prefix;
    $suffix = $mol_conf->dbm_suffix;

    $bact_ali = $mol_conf->src_dir ."/release10_30_bact_aligned.fa.gz";
    $seq_file = $mol_conf->src_dir ."/release10_30_unaligned.gb.gz";

    $ref_id = $mol_conf->bact_id;
    $ref_file = "$out_dir/$prefix$ref_mol". "_$ref_id" . $mol_conf->ref_suffix;

    $tax_table = "$out_dir/$prefix$ref_mol". $mol_conf->tab_suffix;
    $tax_index = "$tax_table$suffix";

    $prim_cache = "db_prim.cache";
    $hits_cache = "db_hits.cache";

    # These are oriented so both match the database sequences in forward 
    # direction,

    $fwd_pat = $args->fwd_primer ."[1,0,0]";
    $rev_pat = $args->rev_primer ."[1,0,0]";

    # >>>>>>>>>>>>>>>>>>>>>> FIND REFERENCE SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<

    # There were no Archaeal matches, so we ignore Archaea. Read through the 
    # alignment and get the sequence, or get from cache if exists, then delete
    # the gaps,

    &echo("   Finding bacterial reference ... ");

    if ( -r $ref_file )
    {
        $ref_aseq = &Seq::IO::read_seqs_file( $ref_file )->[0];
    }
    else
    {
        $ref_aseq = &Ali::Convert::get_ref_seq(
            {
                "file" => $bact_ali,
                "readbuf" => 100,
                "seqid" => $ref_id,
                "format" => "fasta_wrapped",
            });
        
        &Seq::IO::write_seqs_file( $ref_file, [ $ref_aseq ], "fasta" );
    }

    $ref_seq = &Seq::Common::delete_gaps( &Storable::dclone( $ref_aseq ) );
    $ref_max = ( length $ref_seq->{"seq"} ) - 1;

    &echo_done("$ref_id, length ". ($ref_max + 1) ."\n");

    # >>>>>>>>>>>>>>>>>> DETERMINE ALIGNMENT COORDINATES <<<<<<<<<<<<<<<<<<<<<<

    &echo("   Forward alignment range ... ");

    &Bio::Patscan::compile_pattern( $fwd_pat, 0 );
    
    if ( $locs = &Bio::Patscan::match_forward( $ref_seq->{"seq"} ) and @{ $locs } )
    {
        $ref_pos->{"fwd"}->{"sbeg"} = $locs->[0]->[0]->[0];
        $ref_pos->{"fwd"}->{"send"} = $ref_pos->{"fwd"}->{"sbeg"} + $locs->[-1]->[-1]->[1] - 1;

        $ref_pos->{"fwd"}->{"abeg"} = &Seq::Common::spos_to_apos( $ref_aseq, $ref_pos->{"fwd"}->{"sbeg"} );
        $ref_pos->{"fwd"}->{"aend"} = &Seq::Common::spos_to_apos( $ref_aseq, $ref_pos->{"fwd"}->{"send"} );
    }
    else {
        &error( qq (No reference match with forward pattern -> "$fwd_pat") );
    }
    
    $i = $ref_pos->{"fwd"}->{"abeg"};
    $j = $ref_pos->{"fwd"}->{"aend"};

    &echo_done("$i -> $j\n");

    &echo("   Reverse alignment range ... ");

    &Bio::Patscan::compile_pattern( $rev_pat, 0 );
    
    if ( $locs = &Bio::Patscan::match_forward( $ref_seq->{"seq"} ) and @{ $locs } )
    {
        $ref_pos->{"rev"}->{"sbeg"} = $locs->[0]->[0]->[0];
        $ref_pos->{"rev"}->{"send"} = $ref_pos->{"rev"}->{"sbeg"} + $locs->[-1]->[-1]->[1] - 1;

        $ref_pos->{"rev"}->{"abeg"} = &Seq::Common::spos_to_apos( $ref_aseq, $ref_pos->{"rev"}->{"sbeg"} );
        $ref_pos->{"rev"}->{"aend"} = &Seq::Common::spos_to_apos( $ref_aseq, $ref_pos->{"rev"}->{"send"} );
    }
    else {
        &error( qq (No reference match with reverse pattern -> "$rev_pat") );
    }
    
    $i = $ref_pos->{"rev"}->{"abeg"};
    $j = $ref_pos->{"rev"}->{"aend"};

    &echo_done("$i -> $j\n");

    &echo("   Forward sequence range ... ");

    $i = $ref_pos->{"fwd"}->{"sbeg"};
    $j = $ref_pos->{"fwd"}->{"send"};

    &echo_done("$i -> $j\n");

    &echo("   Reverse sequence range ... ");

    $i = $ref_pos->{"rev"}->{"sbeg"};
    $j = $ref_pos->{"rev"}->{"send"};

    &echo_done("$i -> $j\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CREATE DB_HITS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a map of forward and reverse primer positions for every database 
    # with the highest scores,

    if ( -r $hits_cache )
    {
        &echo("   Getting pairs from cache ... ");
        $db_hits = &Common::File::retrieve_file( $hits_cache );
    }
    else
    {
        &echo("   Reading pairs from simrank table ... ");

        $fh = &Common::File::get_read_handle( $args->sim_file );
        
        while ( defined ( $line = <$fh> ) )
        {
            ( $q_id, undef, $sims ) = &Seq::Simrank::parse_sim_line( $line );

            $q_id =~ s/RT__SPLIT__//;

            if ( $sims )
            {
                $best_pct = $sims->[0]->[1];

                # $db_hits->{ $q_id } = [ grep { $_->[1] == $best_pct } @{ $sims } ];
                $db_hits->{ $q_id } = [ @{ $sims->[0] } ];
            }
        }
        
        &Common::File::close_handle( $fh );

        &Common::File::store_file( $hits_cache, $db_hits );
    }

    $i = keys %{ $db_hits };
    &echo_done( "$i\n" );

    # &dump( $db_hits );
    # exit;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE DB_PPOS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    %db_ids = map { $_, 1 } &Common::Util::uniqify([ map { $_->[0] } values %{ $db_hits } ]);

    if ( -r $prim_cache )
    {
        &echo("   Getting primer positions ... ");
        $db_ppos = &Common::File::retrieve_file( $prim_cache );
    }
    else
    {
        &echo("   Reading primer positions ... ");
        $fh = &Common::File::get_read_handle( $bact_ali );

        $fwd_abeg = $ref_pos->{"fwd"}->{"abeg"};
        $fwd_aend = $ref_pos->{"fwd"}->{"aend"};
        
        $rev_abeg = $ref_pos->{"rev"}->{"abeg"};
        $rev_aend = $ref_pos->{"rev"}->{"aend"};

        $fwd_alen = $fwd_aend - $fwd_abeg + 1;
        $rev_alen = $rev_aend - $rev_abeg + 1;
        
        while ( $aseqs = &Seq::IO::read_seqs_fasta_wrapped( $fh, 100 ) )
        {
            foreach $aseq ( @{ $aseqs } )
            {
                if ( $db_id = $aseq->{"id"} and $db_ids{ $db_id } )
                {
                    $db_ppos->{ $db_id }->{"fwd"}->{"beg"} = &Seq::Common::apos_to_spos( $aseq, $fwd_abeg );
                    $db_ppos->{ $db_id }->{"fwd"}->{"end"} = &Seq::Common::apos_to_spos( $aseq, $fwd_aend );

                    $db_ppos->{ $db_id }->{"rev"}->{"beg"} = &Seq::Common::apos_to_spos( $aseq, $rev_abeg );
                    $db_ppos->{ $db_id }->{"rev"}->{"end"} = &Seq::Common::apos_to_spos( $aseq, $rev_aend );
                }

                $beg_seq = substr $aseq->{"seq"}, 0, $fwd_abeg;
                
                if ( $beg_seq =~ /[A-Za-z]/ )
                {
                    $fwd_seq = substr $aseq->{"seq"}, $fwd_abeg, $fwd_alen;
                    $fwd_seq =~ s/[^A-Za-z]//g;
                    $fwd_seq = uc $fwd_seq;
                    $fwd_prim{ $fwd_seq } += 1;
                }

                $end_seq = substr $aseq->{"seq"}, $rev_aend + 1;

                if ( $end_seq =~ /[A-Za-z]/ )
                {
                    $rev_seq = substr $aseq->{"seq"}, $rev_abeg, $rev_alen;
                    $rev_seq =~ s/[^A-Za-z]//g;
                    $rev_seq = uc $rev_seq;
                    $rev_prim{ $rev_seq } += 1;
                }
            }
        }

        &Common::File::close_handle( $fh );

        &Common::File::store_file( $prim_cache, $db_ppos );

        $file = "fwd_prim.tab";
        &Common::File::delete_file_if_exists( $file );
        $fh = &Common::File::get_write_handle( $file );

        @table = sort { $b->[1] <=> $a->[1] } map {[ $_, $fwd_prim{ $_ } ]} keys %fwd_prim;
        
        foreach $row ( @table ) {
            $fh->print( ( join "\t", @{ $row } )."\n" );
        }

        &Common::File::close_handle( $fh );

        $file = "rev_prim.tab";
        &Common::File::delete_file_if_exists( $file );
        $fh = &Common::File::get_write_handle( $file );

        @table = sort { $b->[1] <=> $a->[1] } map {[ $_, $rev_prim{ $_ } ]} keys %rev_prim;

        foreach $row ( @table ) {
            $fh->print( ( join "\t", @{ $row } )."\n" );
        }

        &Common::File::close_handle( $fh );
    }

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a table with key/value store of taxonomy string with organism name for each
    # sequence. Below we use this as source of taxonomy strings.

    &echo("   Is taxonomy table up to date ... ");

    if ( -r $tax_table and not &Common::File::is_newer_than( $src_newest, $tax_table ) )
    {
        &echo_done("yes\n");
    }
    else
    {
        &echo_done("no\n");
        &echo("   Creating taxonomy table ... ");
        
        &Common::File::delete_file_if_exists( $tax_table );
        &Common::File::delete_file_if_exists( "$tax_table.bad_names" );

        $count = &Install::Import::tablify_taxa_rdp({
            "seqfile" => $seq_file,
            "tabfile" => $tax_table,
            "readbuf" => 1000,
        }, \@bads );
        
        if ( @bads ) {
            &Common::File::write_file("$tax_table.bad_names", \@bads );
        }

        &echo_done("$count rows\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a key/value store of taxonomy string with organism name for each
    # sequence. Below we use this as source of taxonomy strings.

    if ( not -r $tax_index or &Common::File::is_newer_than( $src_newest, $tax_index ) )
    {
        &echo("   Indexing taxonomy table ... ");
        
        &Common::Storage::index_table(
             $tax_table, 
             {
                 "keycol" => 0,         # DB sequence id
                 "valcol" => 4,         # Taxonomy string with org name
                 "suffix" => $suffix,   # Kyoto cabinet file suffix
             });
        
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> ALIGN QUERY SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Aligning primer regions ... ");

    # Read query and most-similar db sequences, align them, and create a table
    # with mis-matches, insertion and deletion scores for the primer area(s),

    $fh = &Common::File::get_read_handle( $args->q_file );
    $dbh = &Seq::Storage::get_handles( $args->db_file );
    $th = &Common::DBM::read_open( $tax_index );

    @table = ();
    $count = 0;

    $params = { "seedmin" => 20, "max_score" => 0.0001 };

    while ( $seqs = &Seq::IO::read_seqs_fastq( $fh, 100 ) )
    {
        foreach $seq ( @{ $seqs } )
        {
            $q_id = $seq->{"id"};

            if ( $db_hits->{ $q_id } )
            {
                # If there was a match, get the first matching sequence,

                $db_id = $db_hits->{ $q_id }->[0];

                $db_seq = &Seq::Storage::fetch_seqs( $dbh, {"locs" => [ $db_id ], "return" => 1, "silent" => 1 })->[0];

                # Align query vs db sequence; if there is no alignment in the forward
                # direction, try the reverse,

                $ali = &Seq::Align::align_two_nuc_seqs( \$seq->{"seq"}, \$db_seq->{"seq"}, undef, $params );

                if ( not @{ $ali } )
                {
                    $seq = &Seq::Common::complement( $seq );
                    $ali = &Seq::Align::align_two_nuc_seqs( \$seq->{"seq"}, \$db_seq->{"seq"}, undef, $params );
                }
                
                if ( @{ $ali } )
                {
                    $alis = 1;

                    # If the alignment fully includes the forward primer region, then measure
                    # the mismatch total in that region and push it to a table,

                    $gaps = 0;

                    $sbeg = $db_ppos->{ $db_id }->{"fwd"}->{"beg"};
                    $send = $db_ppos->{ $db_id }->{"fwd"}->{"end"};

                    if ( defined $sbeg and $sbeg >= $ali->[0]->[DB_BEG] and 
                         defined $send and $send <= $ali->[-1]->[DB_END] )
                    {
                        ( undef, $gaps, $astr ) = &Seq::Align::stringify_matches( $ali, \$seq->{"seq"}, \$db_seq->{"seq"} );

                        $abeg = &Seq::Common::spos_to_apos({ "seq" => ${ $astr } }, $sbeg );
                        $aend = &Seq::Common::spos_to_apos({ "seq" => ${ $astr } }, $send );

                        $subgaps = substr ${ $gaps }, $abeg, $aend - $abeg + 1;
                        $fwdmdi = $subgaps =~ tr/ / /;

                        $fwdovl = 1;
                    }
                    else {
                        $fwdmdi = 0;
                        $fwdovl = 0;
                    }
                    
                    $sbeg = $db_ppos->{ $db_id }->{"rev"}->{"beg"};
                    $send = $db_ppos->{ $db_id }->{"rev"}->{"end"};

                    if ( defined $sbeg and $sbeg >= $ali->[0]->[DB_BEG] and 
                         defined $send and $send <= $ali->[-1]->[DB_END] )
                    {
                        if ( not $gaps ) {
                            ( undef, $gaps, $astr ) = &Seq::Align::stringify_matches( $ali, \$seq->{"seq"}, \$db_seq->{"seq"} );
                        }

                        $abeg = &Seq::Common::spos_to_apos({ "seq" => ${ $astr } }, $sbeg );
                        $aend = &Seq::Common::spos_to_apos({ "seq" => ${ $astr } }, $send );

                        $subgaps = substr ${ $gaps }, $abeg, $aend - $abeg + 1;
                        $revmdi = $subgaps =~ tr/ / /;

                        $revovl = 1;
                    }
                    else {
                        $revmdi = 0;
                        $revovl = 0;
                    }
                }
                else {
                    $alis = 0;
                }

                push @table, [ $fwdmdi, ( $fwdmdi > 0 ? 1 : 0 ), $fwdovl, 
                               $revmdi, ( $revmdi > 0 ? 1 : 0 ), $revovl, 
                               $alis, 1, &Common::DBM::get( $th, $db_id ) ];
            }

            $count += 1;

            if ( $count % 1000 == 0 )
            {
                &echo("\n      ... done ");
                &echo_done("$count");
            }
        }
    }

  END:

    &Seq::Storage::close_handles( $dbh );
    &Common::File::close_handle( $fh );
    &Common::DBM::close( $th );

    &echo_done("\n   done\n");

    &echo("   Saving results table ... ");

    $table = &Common::Table::new( 
        [ @table ],
        {
            "col_headers" => ["F-mdi", "F-mis", "F-ovl", "R-mdi", "R-mis", "R-ovl", "Alis", "DB hits", "Taxonomy groups" ],
        });

    $file = "primers.tax";

    &Common::File::delete_file_if_exists( $file );
    &Common::Table::write_table( $table, $file );

    &echo_done("done\n");

    # # >>>>>>>>>>>>>>>>>>>>>>>> INDEX ALL SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # push @files, $args->q_file if not &Seq::Storage::is_indexed( $args->q_file );
    # push @files, $args->db_file if not &Seq::Storage::is_indexed( $args->db_file );

    # if ( @files )
    # {
    #     &echo("   Indexing sequence files ... ");

    #     &Seq::Storage::create_indices(
    #          {
    #              "ifiles" => \@files,
    #              "progtype" => "fetch",
    #              "stats" => 0,
    #              "silent" => 1,
    #          });

    #     &echo_done("done\n");
    # }


    &echo_bold("Finished\n\n");

    return;
}

1;

__END__
