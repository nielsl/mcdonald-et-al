package DNA::Import;     #  -*- perl -*-

# DNA database import specific functions. 
#
# NOTE: contains much code from earlier, when an SQL based EMBL
# install was attempted. Current one is EMBOSS based. Please dont
# delete the earlier, may revive it.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &import_embl_split
                 &import_file_split
                 &import_genbank_split
                 &import_seqs_missing
                 &list_seqs_missing
                );


use Common::Config;
use Common::Messages;
use Common::Entrez;

use Registry::Args;
use Seq::Import;

our $EMBL_id = "dna_seq_embl_local";
our $Genbank_id = "dna_seq_genbank_local";

our $Size_max = 200_000;
our $Dir_levels = 2;

# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<

sub import_embl_split
{
    # Niels Larsen, July 2007.

    my ( $class,
         $args,
        ) = @_;

    my ( $conf, $msgs, $db );

    $args = &Registry::Args::check( $args, { 
        "S:2" => [ qw ( keepsrc inplace ) ],
    });

    $conf = {
        "dbname" => $EMBL_id,
#        "dbformat" => "embl",
        "size_max" => $Size_max,
        "dir_levels" => $Dir_levels,
        "extract_ids" => "DNA::EMBL::Import::extract_ids",
        "split_entry" => "DNA::EMBL::Import::split_entry",
        "keep_src" => $args->keepsrc,
        "fourbit" => 1,
        "inplace" => $args->inplace,
        "register" => 1,
    };

    $conf = Common::Obj->new( $conf );
    $msgs = [];

    require DNA::EMBL::Import;

    &Seq::Import::split_dbflat( $conf, $msgs );

    return;
}

sub import_genbank_split
{
    # Niels Larsen, July 2007.

    my ( $class,
         $args,
        ) = @_;

    my ( $conf, $msgs );

    $args = &Registry::Args::check( $args, { 
        "S:1" => [ qw ( keepsrc inplace ) ],
    });

    $conf = {
        "dbname" => $Genbank_id,
#        "dbformat" => "genbank",
        "size_max" => $Size_max,
        "dir_levels" => $Dir_levels,
        "extract_ids" => "DNA::GenBank::Import::extract_ids",
        "split_entry" => "DNA::GenBank::Import::split_entry",
        "keep_src" => $args->keepsrc,
        "fourbit" => 1,
        "inplace" => $args->inplace,
        "register" => 1,
    };

    $conf = Common::Obj->new( $conf );
    $msgs = [];

    require DNA::GenBank::Import;

    &Seq::Import::split_dbflat( $conf, $msgs );

    return;
}

sub import_seqs_missing
{
    # Niels Larsen, July 2007.

    my ( $class,
         $pairs,
         $msgs,
        ) = @_;

    my ( @pairs );

    require DNA::EMBL::Import;

    @pairs = Seq::Import->import_seqs_missing( $pairs, {
        "dbname" => $EMBL_id,
        "dbformat" => "embl",
        "size_max" => $Size_max,
        "dir_levels" => $Dir_levels,
        "extract_ids" => "DNA::EMBL::Import::extract_ids",
        "split_entry" => "DNA::EMBL::Import::split_entry",
        "fourbit" => 1,
    }, $msgs );

    return wantarray ? @pairs : \@pairs;
}

1;

__END__

# sub import_embl_index
# {
#     # EMBOSS takes too long time to index - abandoned .. 
#     my ( $db,
#         ) = @_;

#     my ( $label, $args, $msgs );

#     # Create emboss indices; this means making sure the emboss.defaults 
#     # contains configuration for this database,

#     $label = $db->label;

#     $args = {
#         "dbname" => $db->name,
#         "dbtype" => "N",
#         "dbformat" => "embl",
#         "src_dir" => $db->datapath_full ."/Downloads",
#         "ins_dir" => $db->datapath_full ."/Installs",
#         "files" => "*.dat",
#         "fields" => "id acc sv des key org",
#         "comment" => "$label installation by Genome Office",
#     };

#     $args = Common::Obj->new( $args );
#     $msgs = [];

#     &Seq::Import::index_dbflat( $db, $args, $msgs );

#     return;
# }





# {
#     local $SIG{__DIE__};
#     require Bio::SeqIO;
# }

# use vars qw ( @ISA @EXPORT_OK );
# require Exporter; @ISA = qw ( Exporter );

# @EXPORT_OK = qw (
#                  &add_seq_filling
#                  &add_seq_flanks
#                  &derive_fields
#                  &format_tables
#                  &ft_key_ids
#                  &ft_qual_ids
#                  &log_errors
#                  &load_embl_release
#                  &load_embl_updates
#                  &parse_location
#                  &split_genbank_file
#                  &table_options
#                  &tablify_embl_flatfile
#                  &verify_fields
#                  );

# use base qw ( DNA::IO );

# use DNA::Schema;
# use DNA::EMBL::Import;

# use Common::Config;
# use Common::File;
# use Common::DB;
# use Common::Storage;
# use Common::Logs;
# use Common::Messages;
# use Common::Table;

# # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# sub add_seq_flanks
# {
#     # Niels Larsen, January 2007.

#     # Prepends and/or appends flank sequences to each sequence in a given 
#     # fasta file and writes the result to a given fasta output file. 

#     my ( $i_file,           # Input file
#          $o_file,           # Output file
#          $locs,             # List of locations
#          $params,           # Parameters - OPTIONAL
#          $msgs,             # Error messages - OPTIONAL
#          ) = @_;

#     # Returns nothing. 

#     my ( %def_params, $i_fh, $o_fh, $seq, $entry, $ndx, $gbseq, $msg, $loc,
#          $seq_id, $loc_id, @m_lens, @l_lens, @r_lens, $ft_beg, $ft_end,
#          $gbseq_len, $bases5, $bases3, $beg, $end, $gbseq5, $gbseq3, 
#          $seq_str, $gap_str, $l_maxlen, $r_maxlen );

#     %def_params = ( "bases_left" => 2000, "bases_right" => 2000 );

#     if ( defined $params ) {
#         $params = { %def_params, %{ $params } };
#     } else {
#         $params = \%def_params;
#     }

#     # >>>>>>>>>>>>>>>>>>>>> ADD UNPADDED FLANKS <<<<<<<<<<<<<<<<<<<<<<<<<

#     # Write output fasta file that contains flank sequences. In the next
#     # section padding gaps are optionally added.

#     $i_fh = &Common::File::get_read_handle( $i_file );
#     $o_fh = &Common::File::get_write_handle( $o_file );

#     $ndx = 0;

#     $bases5 = $params->{"bases_left"};
#     $bases3 = $params->{"bases_right"};

#     while ( defined ( $seq = &DNA::IO::read_seq_fasta( $i_fh ) ) )
#     {
#         # Skip if locator with no id, that means "no flanks please",

#         $loc = $locs->[$ndx++];
#         $loc_id = $loc->id;

#         $seq_id = $seq->id;
#         $seq_str = $seq->seq_string;

#         if ( not defined $loc_id )
#         {
#             $o_fh->print( ">$seq_id\n$seq_str\n" );

#             push @l_lens, 0;                        # used below
#             push @m_lens, $seq->seq_len;             # used below
#             push @r_lens, 0;                        # used below
            
#             next;
#         }

#         # Error if mismatch between file id and list id,

#         if ( $seq_id ne $loc_id )
#         {
#             $msg = qq (Sequence id is "$seq_id" but locator id is "$loc_id");
#             &error( $msg );
#         }

#         # Get entire genbank entry from local cache,

#         $entry = Seq::IO->read_genbank_entry( $seq_id,
#                                               {
#                                                   "format" => "bioperl",
#                                                   "source" => "local",
#                                               });
        
#         # Write file where flank sequences are added. No gap fillers are added,
#         # to make the ends align, but this is optionally done in the next section.
        
#         # Some retired records, while rare, come back from bioperl with the 
#         # sequence "N", we must skip those,
        
#         $gbseq = $entry->next_seq->seq;
#         $gbseq_len = length $gbseq;

#         $ft_beg = $loc->beg;
#         $ft_end = $loc->end;

#         if ( $gbseq and $gbseq_len > 1 and $ft_beg < $gbseq_len and $ft_end < $gbseq_len ) 
#         {
#             if ( $ft_beg < $ft_end )
#             {
#                 $beg = &List::Util::max( 0, $ft_beg - $bases5 );

#                 $gbseq5 = lc substr $gbseq, $beg, $ft_beg - $beg;
                
#                 $end = &List::Util::min( $gbseq_len - 1, $ft_end + $bases3 );
#                 $gbseq3 = lc substr $gbseq, $ft_end+1, $end - $ft_end;
#             }
#             else 
#             {
#                 $end = &List::Util::min( $gbseq_len - 1, $ft_beg + $bases5 );
#                 $gbseq5 = substr $gbseq, $ft_beg+1, $end - $ft_beg;
#                 $gbseq5 = lc ${ &Seq::Common::complement_str( \$gbseq5 ) };
                
#                 $beg = &List::Util::max( 0, $ft_beg - $bases3 );
#                 $gbseq3 = substr $gbseq, $beg, $ft_beg - $beg;
#                 $gbseq3 = lc ${ &Seq::Common::complement_str( \$gbseq3 ) };
#             }

#             $o_fh->print( ">$seq_id\n$gbseq5". $seq->seq_string ."$gbseq3\n" );
#         }
#         else {
#             $o_fh->print( ">$seq_id\n". $seq->seq_string ."\n" );
#         }

#         push @l_lens, (length $gbseq5) || 0;         # used below
#         push @m_lens, $seq->seq_len;                  # used below
#         push @r_lens, (length $gbseq3) || 0;         # used below
#     }

#     &Common::File::close_handle( $i_fh );
#     &Common::File::close_handle( $o_fh );

#     # >>>>>>>>>>>>>>>>>>>>>> ADD FLANKS IF REQUESTED <<<<<<<<<<<<<<<<<<<<<

#     # These are simply gaps that are inserted to preserve alignment of the 
#     # input sequences, and to avoid ragged ends.

#     if ( $bases5 or $bases3 )
#     {
#         $i_fh = &Common::File::get_read_handle( $o_file );
#         $o_fh = &Common::File::get_write_handle( "$o_file.tmp" );

#         $ndx = 0;

#         $l_maxlen = &List::Util::max( @l_lens );
#         $r_maxlen = &List::Util::max( @r_lens );

#         while ( defined ( $seq = &DNA::IO::read_seq_fasta( $i_fh ) ) )
#         {
#             $seq_id = $seq->id;
#             $seq_str = $seq->seq_string;
            
#             if ( $bases5 )
#             {
#                 $gap_str = "~" x ( $l_maxlen - $l_lens[$ndx] );
#                 $seq_str = $gap_str . $seq_str;
#             }

#             if ( $bases3 )
#             {
#                 $gap_str = "~" x ( $r_maxlen - $r_lens[$ndx] );
#                 $seq_str .= $gap_str;
#             }

#             $ndx += 1;

#             $o_fh->print( ">$seq_id\n$seq_str\n" );
#         }

#         &Common::File::close_handle( $i_fh );
#         &Common::File::close_handle( $o_fh );

#         &Common::File::delete_file( $o_file );
#         &Common::File::copy_file( "$o_file.tmp", $o_file );
#         &Common::File::delete_file( "$o_file.tmp" );
#     }

#     return;
# }

# sub derive_fields
# {
#     # Niels Larsen, July 2003.

#     # Computes fields whose value can be derived from other entry fields.

#     my ( $entry,   # Entry from the parser
#          $errors,  # Error list 
#          ) = @_;

#     # >>>>>>>>>>>>>>>>>>>> COMPUTE GC-PERCENTAGE <<<<<<<<<<<<<<<<<<<<<<<

#     my ( $mol, $gc, $ft_key, $fts, $ft, $loc );

#     $mol = $entry->{"molecule"};
#     $gc = $mol->{"g"} + $mol->{"c"};

#     if ( $gc + $gc + $mol->{"a"} + $mol->{"t"} > 0 )
#     {
#         $mol->{"gc_pct"} = sprintf "%.2f", 100 * $gc / ( $gc + $mol->{"a"} + $mol->{"t"} );
#     }
#     else
#     {
#         push @{ $errors }, &Common::Logs::format_error( qq ($entry->{"id"}: no A, C, G or T in sequence) );
#     }

#     # >>>>>>>>>>>>>>>>>> PARSE FEATURE LOCATIONS <<<<<<<<<<<<<<<<<<<<<<<

#     if ( exists $entry->{"features"} )
#     {
#         foreach $ft_key ( keys %{ $entry->{"features"} } )
#         {
#             $fts = $entry->{"features"}->{ $ft_key };

#             foreach $ft ( @{ $fts } )
#             {
#                 $loc = &DNA::Import::parse_location( $ft->{"location"}->[0], 0, $errors );                
#                 @{ $ft->{"location"} } = grep { not exists $_->[3] } @{ $loc };
#             }
#         }
#     }

#     # >>>>>>>>>>>>>>>>> ASSIGN TAXONOMY IDS TO MISSING <<<<<<<<<<<<<<<<<
    
#     # Many entries have a classification yet no taxonomy ID. Here we try
#     # to assign one; when we cannot, return an error. We need taxonomy ids
#     # to project onto the taxonomy viewer. 


#     return;
# }

# sub format_tables
# {
#     # Niels Larsen, July 2003.

#     # Creates a hash of table lines in formats similar to that of the 
#     # the database-ready table files. Parts of an entry is unique or 
#     # close to it, e.g. entry ids and description; other fields use the
#     # same text for many entries, especially authors and titles and 
#     # feature qualifiers and values. So we use normalized tables for 
#     # this information: for example titles are given an id which is 
#     # then used in the reference table; when building the database we
#     # must then check if a given title already has an id or should be
#     # given a new one. This added complexity is what this routine 
#     # handles. 

#     my ( $dbh,          # Database handle
#          $entry,        # Entry hash
#          $tab_delta,    # New data for normalized files (dynamic)
#          $tab_ids,      # Id dictionary (dynamic)
#          $key_ids,      # Feature id dictionary (static)
#          $qual_ids,     # Qualifier id dictionary (static)
#          $errors,       # Error list 
#          ) = @_;

#     # Returns a hash of arrays. 

#     $key_ids = &DNA::Import::ft_key_ids if not $key_ids;
#     $qual_ids = &DNA::Import::ft_qual_ids if not $qual_ids;

#     my ( $c, $u, $c_date, $u_date, $org, $keywords, $mol, $acc, $ent_id,
#          $tab_rows, $ft_key_id, %dbids, $db, $id, $cache, %tax_ids,
#          $ft_key, $fts, $ft, $ft_id, $range, $qual, $qual_id, $vals, $val, 
#          $val_qm, $val_id, $ref_no, $ref, $cit, $aut_id, $lit_id, $tit_id,
#          $month, $mon_to_num, @ids );

#     # >>>>>>>>>>>>>>>>>>>>> FORMAT ENTRY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<

#     $ent_id = $entry->{"id"};

#     $mon_to_num =
#     { 
#         "JAN" => "01",
#         "FEB" => "02",
#         "MAR" => "03",
#         "APR" => "04",
#         "MAY" => "05",
#         "JUN" => "06",
#         "JUL" => "07",
#         "AUG" => "08",
#         "SEP" => "09",
#         "OCT" => "10",
#         "NOV" => "11",
#         "DEC" => "12",
#     };

#     $c = $entry->{"created"};
#     $u = $entry->{"updated"};

#     $month = $mon_to_num->{ $c->{"month"} };
#     $c_date = qq ($c->{"year"}-$month-$c->{"day"}) || "";

#     $month = $mon_to_num->{ $u->{"month"} };
#     $u_date = qq ($u->{"year"}-$month-$u->{"day"}) || "";

#     foreach $org ( @{ $entry->{"organisms"} } )
#     {
#         $keywords = join "; ", @{ $entry->{"keywords"} };

#         push @{ $tab_rows->{"entry"} },
#             qq ($ent_id\t$entry->{'division'}\t)
#           . qq ($c_date\t$u_date\t$entry->{'description'}\t$keywords\n);
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>> FORMAT ORGANELLE TABLE <<<<<<<<<<<<<<<<<<<<<<<
    
#     foreach $org ( @{ $entry->{"organisms"} } )
#     {
#         if ( exists $org->{"organelle"} )
#         {
#             push @{ $tab_rows->{"organelle"} }, qq ($org->{"tax_id"}\t$ent_id\t$org->{"organelle"}\n);
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>> FORMAT MOLECULE TABLE <<<<<<<<<<<<<<<<<<<<<<<<<
    
#     $mol = $entry->{"molecule"};

#     push @{ $tab_rows->{"molecule"} }, 
#           qq ($ent_id\t$mol->{'type'}\t$mol->{'length'}\t)
#         . qq ($mol->{'a'}\t$mol->{'g'}\t$mol->{'c'}\t$mol->{'t'}\t$mol->{'other'}\t)
#         . qq ($mol->{'gc_pct'}\n);

#     # >>>>>>>>>>>>>>>>>>>>> FORMAT ACCESSION TABLE <<<<<<<<<<<<<<<<<<<<<<<<
    
#     foreach $acc ( @{ $entry->{"accessions"} } )
#     {
#         push @{ $tab_rows->{"accession"} }, qq ($ent_id\t$acc\n);
#     }

#     # >>>>>>>>>>>>>>>>>>>>>> FORMAT FEATURE TABLES <<<<<<<<<<<<<<<<<<<<<<<<

#     foreach $ft_key ( keys %{ $entry->{"features"} } )
#     {
#         $fts = $entry->{"features"}->{ $ft_key };

#         if ( exists $key_ids->{ $ft_key } ) {
#             $ft_key_id = $key_ids->{ $ft_key };
#         } else {
#             $ft_key_id = 0;
#         }

#         foreach $ft ( @{ $fts } )
#         {
#             %dbids = ();
#             $ft_id = ++$tab_ids->{"ft_locations"};

#             foreach $range ( @{ $ft->{"location"} } )
#             {
#                 push @{ $tab_rows->{"ft_locations"} }, qq ($ent_id\t$ft_id\t$ft_key_id\t$range->[0]\t$range->[1]\t$range->[2]\n);
#             }

#             delete $ft->{"location"};
#             delete $ft->{"translation"};

#             foreach $qual ( keys %{ $ft } )
#             {
#                 $qual_id = $qual_ids->{ $qual } || 0;

#                 if ( not $qual_id )
#                 {
#                     push @{ $errors }, &Common::Logs::format_error( qq (Entry $ent_id: feature qualifier not recognized -> "$qual") );
#                     next;
#                 }

#                 $vals = $ft->{ $qual };

#                 if ( $qual eq "db_xref" )
#                 {
#                     foreach $val ( @{ $vals } )
#                     {
#                         if ( $val =~ /^([^ ]+):([^ ]+)$/ )
#                         {
#                             $db = $1;
#                             $id = $2;
                            
#                             if ( $db eq "taxon" )
#                             {
#                                 $tax_ids{ $id } = 1;
#                             }
#                             else
#                             {
#                                 if ( not $dbids{ "$db$id" } )
#                                 {
#                                     push @{ $tab_rows->{"db_xref"} }, qq ($ft_id\t$1\t$2\n);
#                                     $dbids{ "$db$id" } = 1;
#                                 }
#                             }
#                         } 
#                         else {
#                             push @{ $errors }, &Common::Logs::format_error( qq (Entry $ent_id: database reference looks wrong -> "$val") );
#                         }
#                     }
#                 }
#                 elsif ( $qual eq "protein_id" )
#                 {
#                     push @{ $tab_rows->{"protein_id"} }, qq ($ft_id\t$vals->[0]\n);
#                 }
#                 else
#                 {
#                     foreach $val ( @{ $vals } )
#                     {
#                         next if $val !~ /\w/;

#                         $val =~ s/\'/\\\'/g;

#                         if ( exists $tab_delta->{"ft_values"}->{ $val } )
#                         {
#                             $val_id = $tab_delta->{"ft_values"}->{ $val };
#                         }
#                         elsif ( @ids = @{ &Common::DB::query_array( $dbh, "select val_id,val from dna_ft_values where val = '$val'" ) } )
#                         {
#                             $val_id = $ids[0]->[0];
#                         }
#                         else
#                         {
#                             $val_id = ++$tab_ids->{"ft_values"};
#                             $tab_delta->{"ft_values"}->{ $val } = $val_id;
#                         }

#                         push @{ $tab_rows->{"ft_qualifiers"} }, qq ($ft_id\t$qual_id\t$val_id\n);
#                     }
#                 }
#             }
#         }
#     }

#     foreach $id ( keys %tax_ids )
#     {
#         push @{ $tab_rows->{"organism"} }, qq ($id\t$ent_id\n);
#     }

#     # >>>>>>>>>>>>>>>>>>>>>> FORMAT REFERENCE TABLES <<<<<<<<<<<<<<<<<<<<<<<<

#     foreach $ref_no ( keys %{ $entry->{"references"} } )
#     {
#         $ref = $entry->{"references"}->{ $ref_no };

#         $aut_id = $lit_id = $tit_id = 0;

#         # ------- Authors,

#         $val = $ref->{"authors"};
#         $val =~ s/[\'\"]//g;
#         $val =~ s/\"/\\\"/g;

#         if ( $val )
#         {
#             if ( exists $tab_delta->{"authors"}->{ $val } )
#             {
#                 $aut_id = $tab_delta->{"authors"}->{ $val };
#             }
#             elsif ( @ids = @{ &Common::DB::query_array( $dbh, "select aut_id,text from dna_authors where text = '$val'" ) } )
#             {
#                 $aut_id = $ids[0]->[0];
#             }
#             else
#             {
#                 $aut_id = ++$tab_ids->{"authors"};
#                 $tab_delta->{"authors"}->{ $val } = $aut_id;
#             }
#         }
#         else {
#             $aut_id = 0;
#         }

#         # ------- Literature,

#         $val = $ref->{"literature"};
#         $val =~ s/[\'\"]//g;
#         $val =~ s/\"/\\\"/g;

#         if ( $val )
#         {
#             if ( exists $tab_delta->{"literature"}->{ $val } )
#             {
#                 $lit_id = $tab_delta->{"literature"}->{ $val };
#             }
#             elsif ( @ids = @{ &Common::DB::query_array( $dbh, "select lit_id,text from dna_literature where text = '$val'" ) } )
#             {
#                 $lit_id = $ids[0]->[0];
#             }
#             else
#             {
#                 $lit_id = ++$tab_ids->{"literature"};
#                 $tab_delta->{"literature"}->{ $val } = $lit_id;
#             }
#         }
#         else {
#             $lit_id = 0;
#         }

#         # ------- Title,

#         $val = $ref->{"title"};
#         $val =~ s/\'/\\\'/g;
#         $val =~ s/\"/\\\"/g;

#         if ( $val )
#         {
#             if ( exists $tab_delta->{"title"}->{ $val } )
#             {
#                 $tit_id = $tab_delta->{"title"}->{ $val };
#             }
#             elsif ( @ids = &Common::DB::query_array( $dbh, "select tit_id,text from dna_title where text = '$val'" ) )
#             {
#                 $tit_id = $ids[0]->[0];
#             }
#             else
#             {
#                 $tit_id = ++$tab_ids->{"title"};
#                 $tab_delta->{"title"}->{ $val } = $tit_id;
#             }
#         }
#         else {
#             $tit_id = 0;
#         }

#         foreach $cit ( @{ $ref->{"citations"} } )
#         {
#             push @{ $tab_rows->{"citation"} }, qq ($ent_id\t$cit->{"name"}\t$cit->{"id"}\n);
#         }

#         push @{ $tab_rows->{"reference"} }, qq ($ent_id\t$ref_no\t$aut_id\t$lit_id\t$tit_id\n);
#     }

#     return $tab_rows;
# }

# sub ft_key_ids
# {
#     # Niels Larsen, July 2003.

#     # Defines a dictionary of feature keys where values are integers between 1 
#     # and 255. This is done in an attempt to reduce the size of the big feature
#     # table. The valid feature keys are listed in the files
#     # 
#     #  1) ftp://ftp.ebi.ac.uk/pub/databases/embl/release/ftable.txt
#     #  2) http://www.ebi.ac.uk/embl/Documentation/FT_definitions/feature_table.html
#     # 
#     # The numbers below are grouped in ranges that reflect their relationship
#     # mostly according to the feature key relationship tree (see URI 2 above). 
#     # The numbers start at a round number for a category and continue up. The 
#     # categories and number ranges are,
#     # 
#     # difference    10 -> 19
#     # binding       20 -> 29
#     # recombination 30 -> 39
#     # signal        50 -> 99
#     # misc_RNA      100 -> 199
#     # ig_related    200 -> 219
#     # repeat        220 -> 229
#     # structure     230 -> 239
#     # 
#     # This makes it possible to write functions that returns all entries that
#     # have promoter features etc. The routine is written to save space in the 
#     # database tables by converting text keys to numbers. The groups and 
#     # comments are taken from URI 1 above.

#     # Returns a hash.

#     my $ids =
#     {
#         # Biological source related,

#                  "source" => 1,   # Biological source of the specified span of sequence

#         # Difference related,

#         "misc_difference" => 10,  # Miscellaneous difference feature also used to describe variability that arises as a result of genetic manipulation (e.g. site directed mutagenesis).
#                "conflict" => 11,  # Independent determinations differ
#                  "unsure" => 12,  # Authors are unsure about the sequence in this region
#            "old_sequence" => 13,  # Presented sequence revises a previous version
#               "variation" => 14,  # Alleles, RFLP\'s,and other naturally occuring mutations and polymorphisms 
#           "modified_base" => 15,  # The indicated base is a modified nucleotide

#         # Binding related,

#            "misc_binding" => 20,  # Miscellaneous binding site
#             "primer_bind" => 21,  # Non-covalent primer binding site
#            "protein_bind" => 22,  # Non-covalent protein binding site on DNA or RNA
#                     "STS" => 23,  # Sequence Tagged Site

#         # Recombination related,

#             "misc_recomb" => 30,  # Miscellaneous recombination feature
#                    "iDNA" => 31,  # Intervening DNA eliminated by recombination

#         # Signal related,
        
#             "misc_signal" => 50,  # Miscellaneous signal
#                "promoter" => 51,  # A region involved in transcription initiation
#             "CAAT_signal" => 52,  # 'CAAT box' in eukaryotic promoters
#               "GC_signal" => 53,  # 'GC box' in eukaryotic promoters
#             "TATA_signal" => 54,  # 'TATA box' in eukaryotic promoters
#              "-10_signal" => 55,  # 'Pribnow box' in prokaryotic promoters
#              "-35_signal" => 56,  # '-35 box' in prokaryotic promoters
#                     "RBS" => 57,  # Ribosome binding site
#            "polyA_signal" => 58,  # Signal for cleavage & polyadenylation
#                "enhancer" => 59,  # Cis-acting enhancer of promoter function
#              "attenuator" => 60,  # Sequence related to transcription termination
#              "rep_origin" => 61,  # Replication origin for duplex DNA
#              "terminator" => 62,  # Sequence causing transcription termination

#         # RNA features not otherwise covered (including where genes are),

#                "misc_RNA" => 100, # Miscellaneous transcript feature not defined by other RNA keys
#         "prim_transcript" => 101, # Primary (unprocessed) transcript
#           "precursor_RNA" => 102, # Any RNA species that is not yet the mature RNA product
#                    "mRNA" => 103, # Messenger RNA
#                 "5\'clip" => 104, # 5'-most region of a precursor transcript removed in processing
#                 "3\'clip" => 105, # 3'-most region of a precursor transcript removed in processinga
#                  "5\'UTR" => 106, # 5' untranslated region (leader)
#                  "3\'UTR" => 107, # 3' untranslated region (trailer)
#                    "exon" => 108, # Region that codes for part of spliced mRNA
#                     "CDS" => 109, # Sequence coding for amino acids in protein (includes stop codon)
#             "sig_peptide" => 110, # Signal peptide coding region
#         "transit_peptide" => 111, # Transit peptide coding region
#             "mat_peptide" => 112, # Mature peptide coding region (does not include stop codon)
#                  "intron" => 113, # Transcribed region excised by mRNA splicing
#              "polyA_site" => 114, # Site at which polyadenine is added to mRNA
#                    "rRNA" => 115, # Ribosomal RNA
#                    "tRNA" => 116, # Transfer RNA
#                   "scRNA" => 117, # Small cytoplasmic RNA
#                   "snRNA" => 118, # Small nuclear RNA
#                  "snoRNA" => 119, # Small nucleolar RNA
                 
#         # Immunoglobulin related,

#                "C_region" => 201, # Constant region of immunoglobulin light and heavy chain, and T-cell receptor alpha, beta and gamma chains
#               "D-segment" => 202, # Diversity segment of immunoglobulin heavy chain and T-cell receptor beta-chain
#               "J_segment" => 203, # Joining segment of immunoglobulin light and heavy chains, and T-cell receptor alpha, beta and gamma-chains
#                "N_region" => 204, # Extra nucleotides inserted betwen rearranged immunoglobulin segments
#                "S_region" => 205, # Switch region of immunoglobulin heavy chains
#                "V_region" => 206, # Variable region of immunoglobulin light and heavy chains, and T-cell receptor alpha, beta, and gamma chains.
#               "V_segment" => 207, # Variable segment of immunoglobulin light and heavy chains, and T-cell receptor alpha, beta and gamma chains

#         # Repeat related, 

#           "repeat_region" => 220, # Sequence containing repeated subsequences
#             "repeat_unit" => 221, # One repeated unit of a repeat_region
#                     "LTR" => 222, # Long terminal repeat
#               "satellite" => 223, # Satellite repeated sequence

    
#            "misc_feature" => 1,   # Region of biological significance that cannot be described by any other feature

#          "misc_structure" => 230, # Miscellaneous DNA or RNA structure
#               "stem_loop" => 231, # Hair-pin loop structure in DNA or RNA 
#                  "D-loop" => 232, # Displacement loop

#              };

#     wantarray ? return %{ $ids } : $ids;
# }

# sub ft_qual_ids
# {
#     # Niels Larsen, July 2003.

#     # Defines a dictionary of feature qualifiers where values are integers between
#     # 1 and 255. This is done in an attempt to reduce the size of the big feature
#     # table. The valid feature qualifiers are listed in the files
#     # 
#     #  1) ftp://ftp.ebi.ac.uk/pub/databases/embl/release/ftable.txt
#     #  2) http://www.ebi.ac.uk/embl/Documentation/FT_definitions/feature_table.html

#     # Returns a hash.

#     my $ids = 
#     {
#                       "allele" => 2,   # Name of the allele for given gene.
#                    "anticodon" => 4,   # Location of the anticodon of tRNA and the amino acid for which it codes
#                 "bound_moiety" => 6,   # Moiety bound
#                    "cell_line" => 8,   # Cell line from which the sequence was obtained
#                    "cell_type" => 10,  # Cell type from which the sequence was obtained
#                   "chromosome" => 12,  # Chromosome from which the sequence was obtained
#                     "citation" => 14,  # Reference to a citation providing the claim of or evidence for a feature
#                        "clone" => 16,  # Clone from which the sequence was obtained
#                    "clone_lib" => 18,  # Clone library from which the sequence was obtained
#                        "codon" => 20,  # Specifies a codon that is different from any found in the reference genetic code
#                  "codon_start" => 22,  # Indicates the reading frame of a protein coding region
#                  "cons_splice" => 24,  # Identifies intron splice sites that do not conform to the 5'-GT ... AG-3' splice site consensus
#                      "country" => 25,
#                     "cultivar" => 26,  # Variety of plant from which the sequence was obtained 
#                      "db_xref" => 28,  # Cross-reference to an external database
#                    "dev_stage" => 30,  # Developmental stage of source organism
#                    "direction" => 32,  # Direction of DNA replication
#                    "EC_number" => 34,  # Enzyme Commission number for the enzyme product of the sequence
#         "environmental_sample" => 36,  # Environmental sample with no reliable identification of the source organism
#                     "evidence" => 38,  # Value indicating the nature of supporting evidence
#                    "exception" => 40,  # Indicates that the amino acid or RNA sequence will not translate or agree with the DNA according to standard biological rules
#                        "focus" => 41,  
#                    "frequency" => 42,  # Frequency of the occurrence of a feature
#                     "function" => 44,  # Function attributed to a sequence
#                         "gene" => 46,  # Symbol of the gene corrresponding to a sequence region
#                     "germline" => 48,  # Immunoglobulin unrearranged DNA
#                    "haplotype" => 50,  # Haplotype of organism from which sequence was obtained
#                "insertion_seq" => 52,  # Insertion sequence element from which sequence was obtained
#                      "isolate" => 54,  # Individual isolate from which sequence was obtained
#             "isolation_source" => 56,  # Physical, environmental and/or geographical source of the biological sample from which the sequence was derived 
#                        "label" => 58,  # A label used to permanently identify a feature
#                 "macronuclear" => 60,  # Macronuclear DNA
#                     "mod_base" => 62,  # Abbreviation for a modified nucleotide base
#                     "mol_type" => 64,  # Records biological state (in vivo molecule type) of the sequence
#                     "lab_host" => 66,  # Laboratory host used to propagate the organism from which sequence was obtained
#                    "locus_tag" => 68,  # For assignment of systematic tags for tracking purposes
#                          "map" => 70,  # Genomic map position of feature
#                         "note" => 72,  # Any comment or additional information
#                       "number" => 74,  # A number indicating the order of genetic elements (e.g., exons or introns) in the 5' to 3' direction
#                    "organelle" => 76,  # Organelle type from which the sequence was obtained 
#                     "organism" => 78,  # Name of organism that provide the sequenced genetic material
#                      "partial" => 80,  # Partial regions - phased out from 15-DEC-2002
#               "PCR_conditions" => 82,  # PCR reaction conditions and components
#                  "pop_variant" => 84,  # Population variant from which sequence was obtained
#                    "phenotype" => 86,  # Phenotype conferred by the feature
#                      "plasmid" => 88,  # Name of plasmid from which sequence was obtained
#                      "product" => 90,  # Name of a product encoded by the sequence
#                     "proviral" => 92,  # Viral sequence integrated into another organism's genome
#                       "pseudo" => 94,  # Indicates that this feature is a non-functional version of the element named by the feature key
#                   "rearranged" => 96,  # Immunoglobulin rearranged DNA
#                      "replace" => 98,  # Indicates that the sequence identified by a feature's intervals is replaced by the sequence shown in "text"
#                   "rpt_family" => 100, # Type of repeated sequence; 'Alu' or 'Kpn,' for example
#                     "rpt_type" => 102, # Organization of repeated sequence
#                     "rpt_unit" => 104, # Identity of repeat unit that constitutes a repeat_region
#                      "segment" => 106, # Name or number of a viral or phage segment      
#                     "serotype" => 108, # Serotype from which sequence was obtained
#                      "serovar" => 110, # Serovar from which sequence was obtained
#                          "sex" => 112, # Sex of organism from which sequence was obtained
#                "sequenced_mol" => 114, # Molecule from which sequence was obtained
#                "specific_host" => 116, # Natural host from which sequence was obtained
#             "specimen_voucher" => 117,
#                "std_name" => 118, # Accepted standard name for this feature
#                       "strain" => 120, # Strain from which sequence was obtained
#                    "sub_clone" => 122, # Sub-clone from which sequence was obtained
#                  "sub_species" => 124, # Sub-species name of organism from which sequence was obtained
#                   "sub_strain" => 126, # Sub-strain from which sequence was obtained
#                   "tissue_lib" => 128, # Tissue library from which sequence was obtained
#                  "tissue_type" => 130, # Tissue type from which sequence was obtained
#                   "transgenic" => 132, # Identifies source feature of host organism which was the recipient of transgenic DNA
#                  "translation" => 134, # Automatically generated one-letter abbreviated amino acid sequence
#                "transl_except" => 136, # Translational exception: single codon, the translation of which does not conform to the reference genetic code
#                 "transl_table" => 138, # Genetic code table
#                   "transposon" => 140, # Transposable element from which sequence was obtained
#                       "usedin" => 142, # Indicates that feature is used in a compound feature in another entry
#                      "variety" => 144, # Variety from which sequence was obtained
#                       "virion" => 146, # Viral genomic sequence as it is encapsidated, as distinguished from its proviral form (integrated in a host cell's chromosome.
#                   };

#     wantarray ? return %{ $ids } : $ids;
# }

# sub log_errors
# {
#     # Niels Larsen, July 2003.
    
#     # Appends a given list of messages to an ERRORS file in the 
#     # DNA/Import subdirectory. 

#     my ( $errors,   # Error messages
#          ) = @_;

#     # Returns nothing.

#     my ( $error, $log_dir, $log_file );

#     $log_dir = "$Common::Config::log_dir/DNA/Import";
#     $log_file = "$log_dir/ERRORS";

#     &Common::File::create_dir( $log_dir, 0 );

#     if ( open LOG, ">> $log_file" )
#     {
#         foreach $error ( @{ $errors } )        {
#             print LOG ( join "\t", @{ $error } ) . "\n";
#         }

#         close LOG;
#     }
#     else {
#         &error( qq (Could not append-open "$log_file") );
#     }

#     return;
# }

# sub load_embl_release
# {
#     # Niels Larsen, June 2003.

#     # Loads a set of EMBL release files into a database. First the database 
#     # tables are initialized, if they have not been. Then each release
#     # file is parsed and saved into a small set of database-ready temporary 
#     # files which are then loaded - unless the "readonly" flag is given. The
#     # release files are deleted, but their names and sizes are kept; if the
#     # "keep" flag is given however, then the release files are not deleted.
#     # The loading may be interrupted, but unlike the network procedures the
#     # loading will not be automatically restarted. 
    
#     my ( $readonly,
#          $restart,    # Whether to load only files not yet loaded
#          $keepfile,   # Whether to keep original files from being deleted
#          ) = @_;

#     # Returns nothing.

#     my ( @load_files, @db_tables, @file_tables, $flatfile_fh, $message, $entry, $parse_subs,
#          $tab_fhs, $fh, $tab_rows, $table, $file, $rows, @fs_files, @db_files, $reload_file,
#          $errors, $db_name, $dbh, $schema, $count, $file_count, $path, $name, $del_id,
#          $fasta_offset, $fasta_seq, $seq_fh, $dat_dir, $tab_ids, @loading_files, @delete_ids,
#          $delete_ids, $ok_count, $bad_count, $hash, $key, $val, $column, $hashes, $byte_end,
#          $sql, $table_db, $count_str, $table_options, $src_dir, $tab_dir );

#     $db_name = $Common::Config::proj_name;
#     $src_dir = "$Common::Config::embl_dir/Release";
#     $tab_dir = "$Common::Config::embl_dir/Database_tables";
#     $dat_dir = "$Common::Config::dat_dir/$db_name";

#     $schema = DNA::Schema->get;

#     @db_tables = $schema->table_names;

#     if ( $readonly )
#     {
#         foreach $table ( @db_tables ) {
#             &Common::File::delete_file_if_exists( "$dat_dir/$table.tab" );
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>> ERASE DATABASE IF NOT RESTART <<<<<<<<<<<<<<<<<<<<<
    
#     # Restart is the option that continues filling of the database, 
#     # without deleting the database,
    
#     else
#     {
# #        &DNA::Import::create_lock();
        
#         if ( not $restart )
#         {
#             if ( &Common::DB::database_exists( $db_name ) )
#             {
#                 &echo( qq (   Removing entire DNA database ... ) );
                
#                 &Common::File::delete_file_if_exists( "$dat_dir/DNA.fasta" );
                
#                 $dbh = &Common::DB::connect( $db_name );
                
#                 foreach $table ( @db_tables )
#                 {
#                     &Common::File::delete_file_if_exists( "$dat_dir/$table.tab" );
                    
#                     if ( &Common::DB::table_exists( $dbh, $table ) ) {
#                         &Common::DB::delete_table( $dbh, $table );
#                     }
#                 }
                
#                 foreach $table ( "dna_files_loaded", "dna_files_being_loaded" )
#                 {
#                     if ( &Common::DB::table_exists( $dbh, $table ) ) {
#                         &Common::DB::delete_table( $dbh, $table );
#                     }
#                 }

#                 &Common::DB::disconnect( $dbh );
#                 &echo_green( "done\n" );
#             }
#         }

#         # >>>>>>>>>>>>>>>>> MAKE SURE DATABASE EXISTS AND CONNECT <<<<<<<<<<<<<<<<
        
#         if ( not &Common::DB::database_exists( $db_name ) )
#         {
#             &echo( qq (   Initializing new DNA database ... ) );
            
#             &Common::DB::create_database( $db_name );
#             sleep 1;
            
#             &echo_green( "done\n" );
#         }
        
#         $dbh = &Common::DB::connect( $db_name );    
        
#         # >>>>>>>>>>>>>>>>>>>>>> CREATE TABLES IF NOT EXIST <<<<<<<<<<<<<<<<<<<<<<<
        
#         &echo( qq (   Have all DNA tables been set up ... ) );
        
#         $count = 0;
#         $table_options = &DNA::Import::table_options;
        
#         foreach $table ( $schema->tables )
#         {
#             if ( not &Common::DB::table_exists( $dbh, $table->name ) )
#             {
#                 if ( exists $table_options->{ $table->name } ) {
#                     &Common::DB::create_table( $dbh, $table, $table_options->{ $table->name } );
#                 } else {
#                     &Common::DB::create_table( $dbh, $table );
#                 }
                    
#                 $count++;
#             }
#         }
        
#         if ( $count > 0 ) { 
#             &echo_green( "no, $count created\n" );
#         } else { 
#             &echo_green( "yes\n" );
#         }
#     }        

#     # >>>>>>>>>>>>>>>>>>>>> MAKE LIST OF FILES TO LOAD <<<<<<<<<<<<<<<<<<<<<<<<

#     if ( not $readonly and $restart )
#     {
#         &echo( qq (   Are there unloaded files ... ) );

#         @fs_files = sort { $a->{"name"} cmp $b->{"name"} } grep { $_->{"name"} =~ /\.dat\.gz$/ } 
#                     &Common::File::list_files( $src_dir );

#         @fs_files = grep { $_->{"name"} !~ /^est/ } @fs_files;

#         @db_files = &DNA::DB::list_files( $dbh, "EMBL RELEASE", "dna_files_loaded" );

#         @load_files = &Common::Storage::diff_lists( \@fs_files, \@db_files, [ "name", "size" ] );

#         $count = scalar @load_files;

#         if ( $count == 0 ) {
#             &echo_green( "no, all done\n" );
#         } else {
#             &echo_green( "yes, $count\n" );
#         }
#     }
#     else
#     {
#         &echo( qq (   Are there flatfiles to load ... ) );
        
#         @load_files = sort { $a->{"name"} cmp $b->{"name"} } grep { $_->{"name"} =~ /\.dat\.gz$/ } 
#                       &Common::File::list_files( $src_dir );

#         @load_files = grep { $_->{"name"} !~ /^est/ } @load_files;

#         $count = scalar @load_files;

#         if ( $count == 0 ) {
#             &echo_yellow( "NO\n" );
#         } else {
#             &echo_green( "yes, $count\n" );
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>> REMOVE ENTRIES FROM INCOMPLETE LOAD <<<<<<<<<<<<<<<<<<

#     if ( not $readonly and $restart )
#     {
#         if ( @loading_files = @{ &DNA::DB::list_files( $dbh, "EMBL RELEASE", "dna_files_being_loaded" ) } )
#         {
#             # ------- delete any .tab files left over,

#             &echo( qq (   Are there .tab files left over ... ) );

#             $count = 0;

#             foreach $table ( @db_tables )
#             {
#                 if ( -e "$dat_dir/$table.tab" )
#                 {
#                     &Common::File::delete_file( "$dat_dir/$table.tab" );
#                     $count++;
#                 }
#             }

#             if ( $count == 0 ) {
#                 &echo_green( "no\n" );
#             } else {
#                 &echo_green( "yes, $count deleted\n" );
#             }

#             # ------- delete all database information for all ids from the 
#             #         file that was being loaded,

#             $name = $loading_files[0]->{"name"};
#             $path = $loading_files[0]->{"path"};

#             &echo( qq (   Removing incomplete entries ... ) );
            
#             @delete_ids = &DNA::EMBL::Import::get_ids( $path );

#             $delete_ids = scalar @delete_ids;

#             $count = &DNA::DB::delete_entries( $dbh, \@delete_ids );

#             if ( $count == 0 ) {
#                 &echo_green( "none found\n" );
#             } else {
#                 &echo_green( "done\n" );
#             }

# #             if ( $count > 0 ) 
# #             {
# #                 &echo( qq (   Defragmenting indices ... ) );
                
# #                 foreach $table ( @db_tables ) {
# #                     print "de-fragmenting $table\n";
# #                     &Common::DB::request( $dbh, "optimize table $table" );
# #                 }
                
# #                 &echo_green( "done\n" );
# #             }

#             if ( $count )
#             {
#                 &echo( qq (   Deleting sequences from "$name" ... ) );

#                 $sql = qq (select max(byte_end) from dna_seq_index);
#                 $byte_end = &Common::DB::query_array( $dbh, $sql )->[0]->[0];
            
#                 &Common::File::truncate_file( "$dat_dir/DNA.fasta", $byte_end+1 );

#                 &echo_green( "done\n" );
#             }

#              &DNA::DB::delete_file_info( $dbh, $name, "EMBL RELEASE", "dna_files_being_loaded" );
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>>> INITIALIZE HELPER ID VALUES <<<<<<<<<<<<<<<<<<<<<<<

#     if ( not $readonly )
#     {
#         # A few normalized tables contain ID's that are managed in perl. Here we
#         # initialize their values,
        
#         if ( $restart )
#         {
#             $tab_ids->{"authors"} = &Common::DB::query_array( $dbh, "select max(aut_id) from dna_authors" )->[0]->[0] || 0;
#             $tab_ids->{"literature"} = &Common::DB::query_array( $dbh, "select max(lit_id) from dna_literature" )->[0]->[0] || 0;
#             $tab_ids->{"title"} = &Common::DB::query_array( $dbh, "select max(tit_id) from dna_title" )->[0]->[0] || 0;
#             $tab_ids->{"ft_locations"} = &Common::DB::query_array( $dbh, "select max(ft_id) from dna_ft_locations" )->[0]->[0] || 0;
#             $tab_ids->{"ft_values"} = &Common::DB::query_array( $dbh, "select max(val_id) from dna_ft_values" )->[0]->[0] || 0;
#         }
#         else
#         {
#             $tab_ids->{"authors"} = 0;
#             $tab_ids->{"literature"} = 0;
#             $tab_ids->{"title"} = 0;
#             $tab_ids->{"ft_locations"} = 0;
#             $tab_ids->{"ft_values"} = 0;
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>>> LOAD EACH FILE INTO DATABASE <<<<<<<<<<<<<<<<<<<<<<<

#     # For each flatfile we create a set of tables according to $schema. When they
#     # are create loaded and deleted for each flatfile 
#     # library,

#     foreach $file ( @load_files )
#     {
#         if ( $file->{"name"} =~ /^test/ or 
#              $file->{"name"} =~ /^est_/ )
#         {
#             next;
#         }

#         if ( not &Common::File::gzip_is_intact( $file->{'path'} ) )
#         {
#             &echo( qq (   Compression of "$file->{'name'}" corrupted ... ) );
#             &echo_yellow( "skipped\n" );
#             next;
#         }

#         if ( $readonly ) {
#             &echo( qq (   Parsing "$file->{'name'}" entries ... ) );
#         } else {
#             &echo( qq (   Importing "$file->{'name'}" entries ... ) );
#         }

#         # ------- Register file information in the database,

#         if ( not $readonly ) {
#             &DNA::DB::add_file_info( $dbh, $file, "EMBL RELEASE", "dna_files_being_loaded" );
#         }
        
#         ( $ok_count, $bad_count ) = &DNA::Import::tablify_embl_flatfile( $file->{"path"}, $tab_ids,
#                                                                          $readonly, $keepfile );

#         # ------ Load and erase each .tab file,
        
#         if ( not $readonly )
#         {
#             foreach $table ( @db_tables )
#             {
#                 if ( -e "$tab_dir/$table.tab" )        {
#                     &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
#                 }

#                 &Common::File::delete_file( "$tab_dir/$table.tab" );
#             }

#             if ( -e "$dat_dir/DNA.fasta" ) {
#                 &Common::File::append_files( "$dat_dir/DNA.fasta", "$tab_dir/DNA.fasta" );
#             } else {
#                 &Common::File::copy_file( "$tab_dir/DNA.fasta", "$dat_dir/DNA.fasta" );
#             }

#             &Common::File::delete_file( "$tab_dir/DNA.fasta" );
#             &Common::File::delete_dir_if_empty( $tab_dir );

#             if ( not $keepfile ) {
#                 &Common::Storage::ghost_file( $file->{"path"} );
#             }
            
#             &DNA::DB::add_file_info( $dbh, $file, "EMBL RELEASE", "dna_files_loaded" );
#             &DNA::DB::delete_file_info( $dbh, $file->{"name"}, "EMBL RELEASE", "dna_files_being_loaded" );
#         }

#         if ( $bad_count )
#         {
#             $count = &Common::Util::commify_number( $ok_count );
#             &echo_green( "$count ok" );
            
#             $count = &Common::Util::commify_number( $bad_count );
#             &echo( ", " );
#             &echo_yellow( "$count bad" );
#         }
#         else
#         {
#             $count = &Common::Util::commify_number( $ok_count );
#             &echo_green( "all $count ok" );
#         }
        
#         &echo( "\n" );
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>>>> CREATE FULLTEXT INDICES <<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     if ( not $readonly )
#     {
#         # Create remaining indices,

# #        &echo( &Common::Util::epoch_to_time_string() . "\n" );
# #        &echo( qq (   Text-indexing descriptions ... ) );
# #        &Common::DB::request( $dbh, "create fulltext index description_fndx on dna_entry (description)" );
# #        &echo_green( "done\n" );        

# #         &echo( &Common::Util::epoch_to_time_string() . "\n" );
# #         &echo( qq (   Text-indexing keywords ... ) );
# #         &Common::DB::request( $dbh, "create fulltext index keywords_fndx on dna_entry (keywords)" );
# #         &echo_green( "done\n" );        

# #         &echo( &Common::Util::epoch_to_time_string() . "\n" );
# #         &echo( qq (   Text-indexing feature values ... ) );
# #         &Common::DB::request( $dbh, "create fulltext index val_fndx on dna_ft_values (val)" );
# #         &echo_green( "done\n" );        
        
# #         &echo( &Common::Util::epoch_to_time_string() . "\n" );
# #         &echo( qq (   Text-indexing literature ... ) );
# #         &Common::DB::request( $dbh, "create fulltext index text_fndx on dna_literature (text)" );
# #         &echo_green( "done\n" );        
        
# #         &echo( &Common::Util::epoch_to_time_string() . "\n" );
# #         &echo( qq (   Text-indexing titles ... ) );
# #         &Common::DB::request( $dbh, "create fulltext index text_fndx on dna_title (text)" );        
# #         &echo_green( "done\n" );        

# #         &echo( &Common::Util::epoch_to_time_string() . "\n" );        
# #         &echo( qq (   Text-indexing authors ... ) );
# #         &Common::DB::request( $dbh, "create fulltext index text_fndx on dna_authors (text)" );
# #         &echo_green( "done\n" );        

#         # Disconnect and remove locks,

#         &Common::DB::delete_table_if_exists( $dbh, "dna_files_being_loaded" );

#         &Common::DB::disconnect( $dbh );
#     }

#     return;
# }

# sub load_embl_updates
# {
#     # Niels Larsen, May 2004.

#     # Loads a set of EMBL update files into a database. 

#     my ( $readonly,      # Whether to load data or just parse
#          $restart,       # Whether to load only files not yet loaded
#          $keepfile,      # Whether to keep original files from being deleted
#          ) = @_;

#     my ( @load_files, @db_tables, @file_tables, $flatfile_fh, $message, $entry, $parse_subs,
#          $tab_fhs, $fh, $tab_rows, $table, $file, $rows, @fs_files, @db_files, $reload_file,
#          $errors, $db_name, $dbh, $schema, $count, $file_count, $path, $name, $del_id,
#          $fasta_offset, $fasta_seq, $seq_fh, $dat_dir, $tab_ids, @loading_files, @delete_ids,
#          $delete_ids, $ok_count, $bad_count, $hash, $key, $val, $column, $hashes, $byte_end,
#          $sql, $table_db, $count_str, $table_options, @errors, $error, $src_dir, $tab_dir,
#          $content, $acc_ids, $ent_ids, $old_count, $new_count, $tot_count );

#     $db_name = $Common::Config::proj_name;
#     $dat_dir = "$Common::Config::dat_dir/$db_name";
#     $src_dir = "$Common::Config::embl_dir/Updates";
#     $tab_dir = "$Common::Config::embl_dir/Database_tables";

#     # >>>>>>>>>>>>>>>>>>>> CHECK DATABASE AND TABLES EXIST <<<<<<<<<<<<<<<<<
    
#     if ( not $readonly )
#     {
#         &echo( qq (   Checking database and tables exist ... ) );

#         if ( &Common::DB::database_exists() )
#         {
#             $schema = DNA::Schema->get;
            
#             @db_tables = $schema->table_names;

#             $dbh = &Common::DB::connect();
            
#             foreach $table ( @db_tables )
#             {
#                 &Common::File::delete_file_if_exists( "$dat_dir/$table.tab" );

#                 if ( not &Common::DB::table_exists( $dbh, $table ) )
#                 {
#                     &echo( "\n" );
#                     &error( qq (Database table does not exist -> "$table") );
#                     exit;
#                 }
#             }

#             &echo_green( "ok\n" );
#         }
#         else
#         {
#             &echo( "\n" );
#             &error( qq (Database does not exist -> "$db_name") );
#             exit;
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>> MAKE LIST OF FILES TO LOAD <<<<<<<<<<<<<<<<<<<<<

#     if ( $readonly )
#     {
#         &echo( qq (   Are there flatfiles to load ... ) );

#         @load_files = sort { $a->{"name"} cmp $b->{"name"} } grep { $_->{"name"} =~ /\.dat\.gz$/ } 
#                       &Common::File::list_files( $src_dir );

#         $count = scalar @load_files;

#         if ( $count == 0 ) {
#             &echo_yellow( "NO\n" );
#         } else {
#             &echo_green( "yes, $count\n" );
#         }
#     }
#     else
#     {
#         &echo( qq (   Are there unloaded files ... ) );

#         @fs_files = sort { $a->{"name"} cmp $b->{"name"} } grep { $_->{"name"} =~ /\.dat\.gz$/ } 
#                     &Common::File::list_files( $src_dir );

#         @db_files = &DNA::DB::list_files( $dbh, "EMBL UPDATES", "dna_files_loaded" );

#         @load_files = &Common::Storage::diff_lists( \@fs_files, \@db_files, [ "name", "size" ] );

#         $count = scalar @load_files;

#         if ( $count == 0 ) {
#             &echo_green( "no, all done\n" );
#         } else {
#             &echo_green( "yes, $count\n" );
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOAD EACH FILE <<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     # Initialize internal ids that connect database tables,

#     if ( not $readonly )
#     {
#         $tab_ids->{"authors"} = &Common::DB::query_array( $dbh, "select max(aut_id) from dna_authors" )->[0]->[0] || 0;
#         $tab_ids->{"literature"} = &Common::DB::query_array( $dbh, "select max(lit_id) from dna_literature" )->[0]->[0] || 0;
#         $tab_ids->{"title"} = &Common::DB::query_array( $dbh, "select max(tit_id) from dna_title" )->[0]->[0] || 0;
#         $tab_ids->{"ft_locations"} = &Common::DB::query_array( $dbh, "select max(ft_id) from dna_ft_locations" )->[0]->[0] || 0;
#         $tab_ids->{"ft_values"} = &Common::DB::query_array( $dbh, "select max(val_id) from dna_ft_values" )->[0]->[0] || 0;
#     }

#     # For each daily update file: create tables that are ready to load into
#     # database; delete older versions of entries in updates; "append" the 
#     # tables to the database. The old-version sequences are not removed but
#     # made inaccessible. 

#     foreach $file ( @load_files )
#     {
# #        next if $file->{"name"} !~ /^r78u048/;

#         if ( &Common::File::gzip_is_intact( $file->{'path'} ) )
#         {
#             if ( $readonly ) {
#                 &echo( qq (   Parsing "$file->{'name'}" entries ... ) );
#             } else {
#                 &echo( qq (   Importing "$file->{'name'}" entries ... ) );
#             }
#         }
#         else
#         {
#             &echo( qq (   Compression of "$file->{'name'}" corrupted ... ) );
#             &echo_yellow( "skipped\n" );
#             next;
#         }
        
#         # >>>>>>>>>>>>>>>>>>>>>> MAKE DATABASE TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<

#         if ( not $readonly ) {
#             &DNA::DB::add_file_info( $dbh, $file, "EMBL UPDATES", "dna_files_being_loaded" );
#         }

#         ( $ok_count, $bad_count ) = &DNA::Import::tablify_embl_flatfile( $file->{"path"}, $tab_ids,
#                                                                          $readonly, $keepfile );
        
#         if ( not $readonly )
#         {
#             # >>>>>>>>>>>>>>>>>>>>> DELETE OBSOLETE ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<

#             $table = &Common::Table::read_table( "$tab_dir/dna_accession.tab", { "format" => "tsv" } );
        
#             $acc_ids = "\"". (join "\",\"", map { $_->[1] } @{ $table->values }) ."\"";
#             $tot_count = scalar @{ $table->values };
            
#             $sql = qq (select distinct ent_id from dna_accession where accession in ( $acc_ids ) );
#             $ent_ids = &Common::DB::query_array( $dbh, $sql );
            
#             if ( @{ $ent_ids } )
#             {
#                 &DNA::DB::delete_entries( $dbh, $ent_ids );
#                 $old_count = scalar @{ $ent_ids };
#             }
#             else {
#                 $old_count = 0;
#             }

#             $new_count = $tot_count - $old_count;

#             # >>>>>>>>>>>>>>>>>>>>>>> LOAD DATABASE TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<
        
#             foreach $table ( @db_tables )
#             {
#                 if ( -e "$tab_dir/$table.tab" )        {
#                     &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
#                 }

#                 &Common::File::delete_file( "$tab_dir/$table.tab" );
#             }

#             if ( -e "$dat_dir/DNA.fasta" ) {
#                 &Common::File::append_files( "$dat_dir/DNA.fasta", "$tab_dir/DNA.fasta" );
#             } else {
#                 &Common::File::copy_file( "$tab_dir/DNA.fasta", "$dat_dir/DNA.fasta" );
#             }

#             &Common::File::delete_file( "$tab_dir/DNA.fasta" );
#             &Common::File::delete_dir_if_empty( $tab_dir );

#             if ( not $keepfile ) {
#                 &Common::Storage::ghost_file( $file->{"path"} );
#             }

#             &DNA::DB::add_file_info( $dbh, $file, "EMBL UPDATES", "dna_files_loaded" );
#             &DNA::DB::delete_file_info( $dbh, $file->{"name"}, "EMBL UPDATES", "dna_files_being_loaded" );

#             $count = &Common::Util::commify_number( $new_count );
#             &echo_green( "$count new" );
            
#             if ( $old_count > 0 ) 
#             { 
#                 $count = &Common::Util::commify_number( $old_count );
#                 &echo_green( ", $count updated" );
#             }
            
#             &echo( "\n" );
#         }
#         else
#         {
#             if ( $bad_count )
#             {
#                 $count = &Common::Util::commify_number( $ok_count );
#                 &echo_green( "$count ok" );
                
#                 $count = &Common::Util::commify_number( $bad_count );
#                 &echo( ", " );
#                 &echo_yellow( "$count bad" );
#             }
#             else
#             {
#                 $count = &Common::Util::commify_number( $ok_count );
#                 &echo_green( "all $count ok" );
#             }

#             &echo( "\n" );            
#         }
#     }

#     if ( not $readonly ) 
#     {
#         &Common::DB::disconnect( $dbh );
#     }

#     return;
# }
    
# sub parse_location
# {
#     # Niels Larsen, July 2003.

#     # Parses an EMBL/GenBank/DDBJ feature location string and returns a 
#     # list of [ beg, end, strand ] locations. The strand is 1 for the plus
#     # strand, -1 for the minus strand. Begin and end numbers are in the 
#     # numbering of the entry and 'beg' is always smaller than 'end'. By
#     # default begin and end intervals (e.g. '(23.45)' or '(23^45)') are
#     # preserved, but this can be switched off by setting the second 
#     # argument to false. Then the lowest and highest positions are used 
#     # respectively.

#     my ( $locstr,   # Location string
#          $fuzzy,    # Preserves begin/end intervals
#          $errors,   # Error list 
#          ) = @_;

#     # Returns a list. 
    
#     no warnings "recursion";     # Because recursion depth may exceed limit

#     $fuzzy = 1 if not defined $fuzzy;

#     my ( @triples, $triple, $operator, $pos_expr, $beg_expr, $end_expr, 
#          $range_expr, $int_expr, $sid,
#          $lp_pos, $rp_pos, $ch, $lp_tot, $rp_tot, $pos, $beg, $end );

#     $beg_expr = '\d+|\(\d+[\.\^]\d+\)';
#     $end_expr = $beg_expr;
#     $int_expr = '\((\d+)[\.\^](\d+)\)';
#     $pos_expr = '<?(\d+)>?';

#     $range_expr = '(?:([^:]+):)?[><]?('.$beg_expr.')[><]?[\.\^]\.?[><]?('.$end_expr.')[><]?';

#     if ( $locstr =~ /^(join|complement|order)/ )
#     {
#         $operator = $1;

#         $lp_pos = index $locstr, "(";
#         $rp_pos = $lp_pos;

#         $lp_tot = 1;
#         $rp_tot = 0;

#         while ( $rp_tot < $lp_tot ) 
#         {
#             $rp_pos++;
#             $ch = substr $locstr, $rp_pos, 1;

#             if ( $ch eq "(" ) {
#                 $lp_tot++;
#             } elsif ( $ch eq ")" ) {
#                 $rp_tot++;
#             }
#         }

#         push @triples, &DNA::Import::parse_location( (substr $locstr, $lp_pos+1, $rp_pos-$lp_pos-1), $fuzzy );

#         if ( $operator eq "complement" )
#         {
#             foreach $triple ( @triples )
#             {
#                 $triple->[2] = -$triple->[2];
#             }
#         }

#         if ( $rp_pos+1 < length $locstr )
#         {
#             push @triples, &DNA::Import::parse_location( substr $locstr, $rp_pos+2, $fuzzy );
#         }
#     }
#     elsif ( ($pos = index $locstr, ",") > 0 )
#     {
#         push @triples, &DNA::Import::parse_location( (substr $locstr, 0, $pos), $fuzzy );
#         push @triples, &DNA::Import::parse_location( (substr $locstr, $pos+1), $fuzzy );
#     }
#     elsif ( $locstr =~ /^$range_expr$/ )
#     {
#         $sid = $1;
#         $beg = $2; 
#         $end = $3;

#         if ( not $fuzzy )
#         {
#             $beg = $1 if $beg =~ /^\((\d+)[\.\^](\d+)\)$/;
#             $end = $2 if $end =~ /^\((\d+)[\.\^](\d+)\)$/;
#         }

#         if ( $sid ) {
#             push @triples, [ $beg, $end, 1, $sid ];
#         } else {
#             push @triples, [ $beg, $end, 1 ];
#         }            
#     }
#     elsif ( $locstr =~ /^$int_expr$/ )
#     {
#         push @triples, [ $1, $2, 1 ];
#     }
#     elsif ( $locstr =~ /^$pos_expr$/ )
#     {
#         push @triples, [ $1, $1, 1 ];
#     }
#     else
#     {
#         push @{ $errors }, &Common::Logs::format_error( qq (Locstr: Could not parse "$locstr") );
#     }

#     return wantarray ? @triples : \@triples;
# }

# sub table_options
# {
#     my $options = 
#     {
#         "dna_ft_qualifiers" => "avg_row_length = 9 max_rows = 500000000",
#         "dna_entry" => "avg_row_length = 200 max_rows = 100000000",
#         "dna_citation" => "avg_row_length = 30 max_rows = 100000000",
#         "dna_reference" => "avg_row_length = 20 max_rows = 100000000",
#         "dna_locations" => "avg_row_length = 22 max_rows = 100000000",
#     };

#     return $options;
# }
        
# sub tablify_embl_flatfile
# {
#     # Niels Larsen, July 2003.

#     # Parses a given EMBL flat file and creates rows that are appended
#     # to a set of database-ready table files in the given directory.

#     my ( $flatfile,
#          $tab_ids,
#          $readonly,
#          $keepfile,
#          ) = @_;

#     # Returns nothing. 

#     $keepfile = 1 if not defined $keepfile;
    
#     my ( $db_name, $parse_subs, @tab_names, $tab_name, $tables, $errors,
#          $flatfile_fh, $entry, $rows, $dbs, $dat_dir, $cache, $fh, $text, $id,
#          $ok_count, $bad_count, $format_subs, @tables_db, $tab_rows, $dbh,
#          $ft_key_ids, $ft_qual_ids, $seq_fh_pos, $byte_beg, $byte_end,
#          $tab_delta, $schema, $tab_fhs, $seq_fh, $table, $tab_dir );

#     $db_name = $Common::Config::proj_name;
#     $dat_dir = "$Common::Config::dat_dir/$db_name";
#     $tab_dir = "$Common::Config::embl_dir/Database_tables";

#     $schema = DNA::Schema->get;

#     # ---------------- Define parse and format routines, 

#     $parse_subs = 
#     {
#         "R" => \&DNA::EMBL::Import::get_references,
#         "organisms" => \&DNA::EMBL::Import::get_organisms,
#         "RN" => "",
#         "  " => \&DNA::EMBL::Import::get_sequence,
#         "FT" => \&DNA::EMBL::Import::get_features,
#         "ID" => \&DNA::EMBL::Import::get_ID,
#         "AC" => \&DNA::EMBL::Import::get_AC,
#         "SV" => \&DNA::EMBL::Import::get_SV,
#         "DT" => \&DNA::EMBL::Import::get_DT,
#         "DE" => \&DNA::EMBL::Import::get_DE,
#         "KW" => \&DNA::EMBL::Import::get_KW,
#         "OS" => \&DNA::EMBL::Import::get_OS,
#         "OC" => \&DNA::EMBL::Import::get_OC,
#         "OG" => \&DNA::EMBL::Import::get_OG,
#         "RA" => \&DNA::EMBL::Import::get_RA,
#         "RC" => \&DNA::EMBL::Import::get_RC,
#         "RT" => \&DNA::EMBL::Import::get_RT,
#         "RP" => \&DNA::EMBL::Import::get_RP,
#         "RX" => \&DNA::EMBL::Import::get_RX,
#         "RL" => \&DNA::EMBL::Import::get_RL,
#         "DR" => \&DNA::EMBL::Import::get_DR,
#         "SQ" => \&DNA::EMBL::Import::get_SQ,    
#         "CC" => \&DNA::EMBL::Import::get_CC,
#     };

#     # ------- Initialize file handles and variables,
    
#     $ft_key_ids = &DNA::Import::ft_key_ids;
#     $ft_qual_ids = &DNA::Import::ft_qual_ids;

#     $flatfile_fh = &Common::File::get_read_handle( $flatfile );

#     if ( not $readonly )
#     {
#         &Common::File::create_dir_if_not_exists( $tab_dir );

#         foreach $table ( $schema->tables )
#         {
#             $tab_fhs->{ $table->name } = &Common::File::get_write_handle( "$tab_dir/". $table->name .".tab" );
#         }

#         if ( -e "$dat_dir/DNA.fasta" )
#         {
#             $seq_fh = &Common::File::get_read_handle( "$dat_dir/DNA.fasta" );

#             seek $seq_fh, 0, 2;
#             $seq_fh_pos = tell $seq_fh;

#             &Common::File::close_handle( $seq_fh );
#         }
#         else {
#             $seq_fh_pos = 0;
#         }

#         $seq_fh = &Common::File::get_append_handle( "$tab_dir/DNA.fasta" );

#         $dbh = &Common::DB::connect( $db_name );
#     }
    
#     $ok_count = 0;
#     $bad_count = 0;
#     $errors = [];
#     $tab_rows = {};
#     $tab_delta = {};

#     # ------- Parse and tablify entries,
    
#     while ( $entry = &DNA::EMBL::Import::parse_entry_file( $flatfile_fh, $parse_subs, $errors ) )
#     {
#         # The entry is now parsed into a memory structure that resembles the
#         # databank format, ie it is "entry centric". 

#         # Process the parsed structure slightly, derive a few fields
#         # (like GC percentage), 

#         &DNA::Import::derive_fields( $entry, $errors );
        
#         # Verify that the most important mandatory fields are present,
        
#         &DNA::Import::verify_fields( $entry, $errors );
        
#         @{ $errors } ? $bad_count++ : $ok_count++;
        
#         if ( @{ $errors } )
#         {
#             &DNA::Import::log_errors( $errors );        
#         }
#         elsif ( not $readonly )
#         {
#             $tab_rows = &DNA::Import::format_tables( $dbh, $entry, $tab_delta, $tab_ids, 
#                                                      $ft_key_ids, $ft_qual_ids, $errors );
            
#             $byte_beg = $seq_fh_pos + (length $entry->{"id"}) + 3;
#             $byte_end = $byte_beg + (length $entry->{"molecule"}->{"sequence"}) - 1;

#             $seq_fh_pos = $byte_end + 1;
            
#             push @{ $tab_rows->{"seq_index"} }, qq ($entry->{"id"}\t$byte_beg\t$byte_end\n);
            
#             foreach $tab_name ( keys %{ $tab_rows } )
#             {
#                 if ( exists $tab_rows->{ $tab_name } )
#                 {
#                     $tab_fhs->{ "dna_$tab_name" }->print( @{ $tab_rows->{ $tab_name } } );
#                 }
#             }
            
#             $tab_rows = {};

#             $seq_fh->print( qq (>$entry->{'id'}\n$entry->{'molecule'}->{'sequence'}\n) );
#         }
        
#         $errors = [];
#     }

#     # ------- Close database connection and file handles,

#     if ( not $readonly )
#     {
#         &Common::DB::disconnect( $dbh );
        
#         &Common::File::close_handle( $flatfile_fh );
        
#         foreach $table ( $schema->table_names ) {
#             &Common::File::close_handle( $tab_fhs->{ $table } );
#         }
        
#         &Common::File::close_handle( $seq_fh );
#     }

#     # ------- Dump hash of highly redundant field values. This is 
#     #         done to save space. 

#     if ( not $readonly )
#     {
#         foreach $tab_name ( keys %{ $tab_delta } )
#         {
#             $cache = $tab_delta->{ $tab_name };
#             $fh = &Common::File::get_write_handle( "$tab_dir/dna_$tab_name.tab" );
            
#             while ( ( $text, $id ) = each %{ $cache } )
#             {
#                 $fh->print( "$id\t$text\n" );
#             }
            
#             &Common::File::close_handle( $fh );        
#         }
#     }
    
#     return ( $ok_count, $bad_count );
# }

# sub verify_fields
# {
#     # Niels Larsen, July 2003.

#     # Checks that all mandatory fields are present in a given 
#     # entry. The entry is not modified. VERY INCOMPLETE.

#     my ( $entry,    # Entry from the parser
#          $errors,   # Error list
#          ) = @_;

#     # Return a hash.

#     my ( $key, $ft, $ent_id, $mol );

#     # -------------- Are all required fields present,

#     if ( exists $entry->{"id"} ) {
#         $ent_id = $entry->{"id"};
#     } else {
#         push @{ $errors }, &Common::Logs::format_error( qq (No ID/LOCUS found) );
#         $ent_id = "UNKNOWN";
#     }

#     foreach $key ( "accessions", "keywords", "created", "updated", "description", "version",
#                    "organisms", "references", "molecule", "division" )
#     {
#         if ( not exists $entry->{ $key } )
#         {
#             push @{ $errors }, &Common::Logs::format_error( qq (No "$key" field in entry "$ent_id") );
#         }
#     }

#     # -------------- Do all features have locations,

#     if ( exists $entry->{"features"} )
#     {
#         foreach $key ( keys %{ $entry->{"features"} } ) 
#         {
#             foreach $ft ( @{ $entry->{"features"}->{ $key } } )
#             {
#                 if ( not exists $ft->{"location"} )
#                 {
#                     push @{ $errors }, &Common::Logs::format_error( qq (Missing location in feature "$key" in entry "$entry->{'id'}"\n) );
#                 }
#             }
#         }
#     }

#     # -------------- Do all entries have sequence counts, (no, some dont)

#     $mol = $entry->{"molecule"};

#     if ( not ( $mol->{"c"} > 0 or $mol->{"g"} > 0 or $mol->{"a"} > 0 or $mol->{"t"} > 0 ) )
#     {
#         push @{ $errors }, &Common::Logs::format_error( qq ($ent_id: all base counts are zero\n) );
#     }

#     return $entry;
# }

# 1;


# __END__

#     # >>>>>>>>>>>>>>>>>>>>>>> LOAD TABLES INTO DATABASE <<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     if ( not $readonly )
#     {
#         # Create remaining indices,

#         &echo( qq (   Re-indexing "entry" table ... ) );

#         &Common::DB::request( $dbh, "drop index description_ndx on entry" );
#         &Common::DB::request( $dbh, "drop index keywords_ndx on entry" );
#         &Common::DB::request( $dbh, "create fulltext index description_ndx on entry (description)" );
#         &Common::DB::request( $dbh, "create fulltext index keywords_ndx on entry (keywords)" );
        
#         &echo_green( "done\n" );        
#         &echo( &Common::Util::epoch_to_time_string() . "\n" );

#         &echo( qq (   Re-indexing "ft_values" table ... ) );

#         &Common::DB::request( $dbh, "drop index val_ndx on ft_values" );
#         &Common::DB::request( $dbh, "create fulltext index val_ndx_ndx on ft_values (val)" );
        
#         &echo_green( "done\n" );        
#         &echo( &Common::Util::epoch_to_time_string() . "\n" );
        
#         &echo( qq (   Re-indexing "literature" table ... ) );

#         &Common::DB::request( $dbh, "drop index text_ndx on literature" );
#         &Common::DB::request( $dbh, "create fulltext index text_ndx on literature (text)" );
        
#         &echo_green( "done\n" );        
#         &echo( &Common::Util::epoch_to_time_string() . "\n" );
        
#         &echo( qq (   Re-indexing "title" table ... ) );

#         &Common::DB::request( $dbh, "drop index text_ndx on title" );
#         &Common::DB::request( $dbh, "create fulltext index text_ndx on title (text)" );
        
#         &echo_green( "done\n" );        
#         &echo( &Common::Util::epoch_to_time_string() . "\n" );
        
#         &echo( qq (   Re-indexing "authors" table ... ) );

#         &Common::DB::request( $dbh, "drop index text_ndx on authors" );
#         &Common::DB::request( $dbh, "create fulltext index text_ndx on authors (text)" );
        
#         &echo_green( "done\n" );        
#         &echo( &Common::Util::epoch_to_time_string() . "\n" );
        

# sub format_seq_index
# {
#     my ( $entry,
#          ) = @_;
    
#     my ( $row, $beg, $end );
    
#     $beg = $entry->{"molecule"}->{"fasta_offset"} + (length $entry->{"id"}) + 2;
#     $end = $beg + (length $entry->{"molecule"}->{"sequence"}) - 1;

#     $row = qq ($entry->{"id"}\t$beg\t$end\n);

#     return [ $row ];
# }
