package Install::Import;     #  -*- perl -*-

# Routines that do dataset specific installation things. The Download 
# module does dataset specific download things.

use strict;
use warnings FATAL => qw ( all );

use English;
use Time::Local;
use Storable qw ( dclone );
use List::Util;
use Compress::LZ4;
use Data::MessagePack;
use feature "state";

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &cluster_exports
                 &create_green_seqs
                 &create_green_seqs_args
                 &create_green_seqs_wrap
                 &create_rdp_sub_seqs
                 &create_rdp_sub_seqs_args
                 &create_rdp_sub_seqs_wrap
                 &create_signature_dbm
                 &create_silva_sub_seqs
                 &create_silva_sub_seqs_args
                 &create_silva_sub_seqs_wrap
                 &print_mask_map
                 &derep_exports
                 &derep_sub_seqs
                 &import_genomes_ebi
                 &index_tax_table
                 &load_oli_counts
                 &open_export_handles
                 &parse_green_header
                 &parse_green_taxstr
                 &parse_rdp_taxstr
                 &parse_silva_taxstr
                 &parse_silva_taxstr_euk
                 &parse_silva_taxstr_prok
                 &read_write_template
                 &set_rdp_exports
                 &set_silva_exports
                 &tablify_green_taxa
                 &tablify_rdp_taxa
                 &tablify_silva_taxa
                 &uninstall_genomes_ebi
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::DBM;
use Common::Names;
use Common::Storage;

use Install::Profile;
use Install::Download;

use Seq::Align;
use Seq::Storage;
use Seq::Cluster;
use Seq::Oligos;
use Seq::IO;

use Ali::Convert;

use Taxonomy::Config;
use Taxonomy::Tree;

use Recipe::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Tax_divs, $Root_id );

use constant KINGDOM => 0;
use constant PHYLUM => 1;
use constant CLASS => 2;
use constant ORDER => 3;
use constant FAMILY => 4;
use constant GENUS => 5;
use constant SPECIES => 6;
 
$Tax_divs->{ 0 } = "k__";
$Tax_divs->{ 1 } = "p__";
$Tax_divs->{ 2 } = "c__";
$Tax_divs->{ 3 } = "o__";
$Tax_divs->{ 4 } = "f__";
$Tax_divs->{ 5 } = "g__";
$Tax_divs->{ 6 } = "s__";

# Nodes are small lists of info and these constants are indices to those 
# lists. 

use constant OTU_NAME => Taxonomy::Tree::OTU_NAME;      # Dont change
use constant PARENT_ID => Taxonomy::Tree::PARENT_ID;    # Dont change
use constant NODE_ID => Taxonomy::Tree::NODE_ID;        # Dont change
use constant CHILD_IDS => Taxonomy::Tree::CHILD_IDS;    # Dont change

use constant MAKE_MASK => 0;
use constant SEQ_TOTAL => 1;
use constant GRP_TOTAL => 2;
use constant OLI_SUMS => 3;
use constant OLI_MASK => 3;

$Root_id = $Taxonomy::Tree::Root_id;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub cluster_exports
{
    # Niels Larsen, February 2013.

    # Helper function that creates clustered versions of all slice files, 
    # good for chimera checks. Returns the number of files processed.
    
    my ( $exports,
         $args,
        ) = @_;

    my ( $odir, $count, $file, $minsim, $file2 );

    $odir = $args->{"outdir"};
    $minsim = $args->{"minsim"} // 99;

    $count = 0;

    foreach $file ( sort keys %{ $exports } )
    {
        next if $file =~ /all\./;
        next if $file =~ /minlen_/;
        next if $file =~ /\-T\.rna_seq/;
        next if $file =~ /\-S\.rna_seq/;
        
        &echo("   $minsim% clustering $file ... ");
        
        &Seq::Cluster::cluster(
            {
                "iseqs" => "$odir/$file",
                "oalign" => "$odir/$file.ali",
                "ofasta" => "$odir/$file.seeds",
                "minsim" => $minsim,
                "minsize" => 1,
                "cluprog" => "uclust",
                "silent" => 1,
                "clobber" => 1,
            });
        
        $file2 =  $file;
        $file2 =~ s/\.rna_seq/-C$minsim\.rna_seq/;
        
        &Common::File::delete_file_if_exists("$odir/$file2");
        &Common::File::rename_file( "$odir/$file.seeds", "$odir/$file2" );
        
        &Common::File::count_lines( "$odir/$file2", 1 );
        
        &Common::File::delete_file_if_exists( "$odir/$file.ali" );
        &Common::File::delete_file_if_exists( "$odir/$file.ali.fetch" );
        &Common::File::delete_file_if_exists( "$odir/$file.seeds.small" );
        
        &echo_done("done\n");

        $count += 1;
    }

    return $count;
}

sub create_green_seqs
{
    # Niels Larsen, September 2012. 

    # Splits greengenes sequence file into taxonomy and sequences. No sub-
    # sequences are written, as Greengenes does not distribute alignments yet.

    my ( $db,       # Dataset name or object
         $args,     # Arguments hash
        ) = @_;

    my ( $defs, $conf, $src_newest, $ref_mol, $mol_conf, $prefix, $suffix,
         $seq_suffix, $tax_table, $tax_index, $odir, $count, $taxa, $gbacc,
         @bads, $header, $text, $run_start, $seq_file, @ofiles, $read_buf,
         $idir, $ifile, $reader, $ifh, $ofh, $seqs, $tax_ids, $seq_id, 
         $line, $tids_str, $acc, $tax_str );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "indir" => undef,
        "outdir" => undef,
        "recipe" => undef,
        "readbuf" => 1000,
        "clobber" => 0,
        "silent" => 0,
        "header" => 1,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    $conf = &Install::Import::create_green_seqs_args( $db, $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Configuring internal settings ... ");

    $src_newest = &Common::File::get_newest_file( $conf->indir )->{"path"};
    
    $idir = $conf->indir;
    $odir = $conf->outdir;

    $ref_mol = "SSU";
    $mol_conf = $Taxonomy::Config::DBs{"Green"}{ $ref_mol };

    $prefix = $mol_conf->prefix;
    $suffix = $mol_conf->dbm_suffix;

    $seq_suffix = $mol_conf->seq_suffix;

    $tax_table = "$odir/$prefix$ref_mol". $mol_conf->tab_suffix;
    $tax_index = "$tax_table$suffix";

    $seq_file = "$odir/$prefix$ref_mol"."_all". $mol_conf->seq_suffix;

    $run_start = time();
    $read_buf = $conf->readbuf;

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> HELP MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold("\nGreengenes installation:\n") if $header;

    $text = qq (
      Sequences and taxonomy strings are now being written to files 
      and indexed. Taxonomy strings are verified and converted to a 
      database neutral format. See the installation directory

      $odir

);
    &echo_yellow( $text );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Is sequence file current ... ");
    
    if ( -r $seq_file and not &Common::File::is_newer_than( $src_newest, $seq_file ) )
    {
        &echo_done("yes\n");
    }
    else
    {
        &echo_done("no\n");
        &echo("   Writing sequence file ... ");
        
        $ifile = &Common::File::list_files( $idir, '.fasta.gz' )->[0]->{"path"};

        $reader = &Seq::IO::get_read_routine( $ifile );
        $ifh = &Common::File::get_read_handle( $ifile );

        &Common::File::delete_file_if_exists( $seq_file );
        $ofh = &Common::File::get_write_handle( $seq_file );

        $count = 0;

        no strict "refs";

        while ( $seqs = $reader->( $ifh, $read_buf ) )
        {
            use strict "refs";

            map { delete $_->{"info"} } @{ $seqs };

            &Seq::IO::write_seqs_fasta( $ofh, $seqs );

            $count += scalar @{ $seqs };
        }

        &Common::File::close_handle( $ofh );
        &Common::File::close_handle( $ifh );

        &echo_done("$count rows\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a table with key/value store of taxonomy string with organism name 
    # for each sequence. Below we use this as source of taxonomy strings.

    &echo("   Is taxonomy table current ... ");

    if ( -r $tax_table and not &Common::File::is_newer_than( $src_newest, $tax_table ) )
    {
        &echo_done("yes\n");
    }
    else
    {
        &echo_done("no\n");

        # >>>>>>>>>>>>>>>>>>>>>>> CREATE TAXA HASH <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo("   Reading taxonomic groups ... ");

        $ifh = &Common::File::get_read_handle( $conf->tax_file );

        while ( defined ( $line = <$ifh> ) )
        {
            chomp $line;
            ( $seq_id, $tax_str ) = split "\t", $line;

            $taxa->{ $seq_id } = $tax_str;
        }

        &Common::File::close_handle( $ifh );

        $count = keys %{ $taxa };
        &echo_done("$count\n");

        # >>>>>>>>>>>>>>>>>>>>>>> CREATE GB ACC HASH <<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo("   Reading Genbank accessions ... ");

        $ifh = &Common::File::get_read_handle( $conf->gb_file );

        while ( defined ( $line = <$ifh> ) )
        {
            chomp $line;
            ( $seq_id, $acc ) = split "\t", $line;

            $gbacc->{ $seq_id } = $acc;
        }
        
        $count = keys %{ $gbacc };
        &Common::File::close_handle( $ifh );

        &echo_done("$count\n");

        # >>>>>>>>>>>>>>>>>>>>>>> WRITE TAXA TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo("   Creating taxonomy table ... ");
        
        &Common::File::delete_file_if_exists( $tax_table );
        &Common::File::delete_file_if_exists( "$tax_table.bad_names" );

        $count = &Install::Import::tablify_green_taxa({
            "seqfile" => $conf->seq_file,
            "taxa" => $taxa,
            "gbacc" => $gbacc,
            "tabfile" => $tax_table,
            "readbuf" => 1000,
        }, \@bads );
        
        if ( @bads ) {
            &Common::File::write_file("$tax_table.bad_names", [ map { $_ ."\n" } @bads ] );
        }

        &echo_done("$count rows\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a key/value store of taxonomy string with organism name for each
    # sequence. Below we use this as source of taxonomy strings.

    if ( not -r $tax_index or &Common::File::is_newer_than( $src_newest, $tax_index ) )
    {
        &echo("   Indexing taxonomy table ... ");
        
        &Install::Import::index_tax_table(
             $tax_table, 
             {
                 "keycol" => 0,         # Sequence id
                 "valcol" => 4,         # Taxonomy string with org name
                 "suffix" => $suffix,   # Kyoto cabinet file suffix
             });
        
        &echo_done("done\n");
    }

    if ( $header )
    {
        &echo("   Time: ");
        &echo_info( &Time::Duration::duration( time() - $run_start ) ."\n" );
    }

    &echo_bold("\nFinished\n\n") if $header;

    @ofiles = &Common::File::list_files( $odir, '.fasta$' );

    return ( scalar @ofiles, undef );

    return;
}

sub create_green_seqs_args
{
    # Niels Larsen, June 2012.

    # Creates a config object from the script input arguments. 

    my ( $db,
         $args,
        ) = @_;

    # Returns object.

    my ( @msgs, %args, @ofiles, $indir, @ifiles, $key, $val, $prefix, $suffix );

    $db = Registry::Get->dataset( $db );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args{"indir"} = $args->indir )
    {
        $indir = $args{"indir"};
        &Common::File::check_files( [ $indir ], "d", \@msgs );
    }
    else {
        $indir = $db->datapath_full ."/Sources";
    }

    if ( @ifiles = &Common::File::full_file_paths( ["$indir/gg_*.fasta.gz"] ) ) {
        $args{"seq_file"} = $ifiles[0];
    } else {
        push @msgs, ["ERROR", qq (Input sequence file not found -> "$indir/gg_*.fasta.gz") ];
    }
    
    if ( @ifiles = &Common::File::full_file_paths( ["$indir/gg_*_taxonomy.txt.gz"] ) ) {
        $args{"tax_file"} = $ifiles[0];
    } else {
        push @msgs, ["ERROR", qq (Input taxonomy file not found -> "$indir/gg_*_taxonomy.txt.gz") ];
    }
    
    if ( @ifiles = &Common::File::full_file_paths( ["$indir/gg_*_genbank.map.gz"] ) ) {
        $args{"gb_file"} = $ifiles[0];
    } else {
        push @msgs, ["ERROR", qq (Input Genbank acc number file not found -> "$indir/gg_*_genbank.map.gz") ];
    }
    
    $args{"indir"} = $indir;

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Directory,

    if ( not $args{"outdir"} ) {
        $args{"outdir"} = $db->datapath_full ."/Installs";
    }

    # Switches,

    $args{"readbuf"} = $args->readbuf;
    $args{"clobber"} = $args->clobber;
    $args{"header"} = $args->header;

    bless \%args;

    return wantarray ? %args : \%args;
}

sub create_green_seqs_wrap
{
    # Niels Larsen, September 2012. 

    my ( $db,
         $args,
        ) = @_;

    return &Install::Import::create_green_seqs(
        $db->name,
        {
            "indir" => $args->src_dir,
            "outdir" => $args->ins_dir,
            "readbuf" => 1000,
            "derep" => 1,
            "silent" => ( not $args->verbose ),
            "header" => 0,
        });
}

sub create_rdp_sub_seqs
{
    # Niels Larsen, July 2012. 

    # Produces files with unaligned sequences from the variable domains often
    # used for classification, with the RDP distribution files as input. To
    # add default regions, edit Taxonomy::Config::subseq_template. 
    # 
    # RDP does not include taxonomies in the aligned files and has separate 
    # bacterial and archaeal alignments. To get bacteria + archaea with the 
    # taxonomies in the same files, this routine has to do a number of steps. 
    # If RDP improves this routine will shrink.

    my ( $db,       # Dataset name or object
         $args,     # Arguments hash
        ) = @_;

    # Returns two-element list.

    my ( $defs, $conf, $odir, $text, $arch_seq, $bact_seq, $file, $exports,
         $arch_id, $bact_id, $ali_file, $header, $readbuf, $seqs, $seq, 
         $ref_ali, $bact_aseq, $arch_aseq, $name, $beg, $end, $rcp_file, 
         $bact_max, $arch_max, $tax_table, $count, $tax_index, $dbh, $ofhs,
         $ali_len, $path, $ali, $ali_fh, $ali_seqs, $fh, $reader, $format,
         $export, $counts, $run_start, $src_newest, @ofiles, $key, $val, 
         @bads, $rcp, $clobber, $step, $ref_mol, $prefix, $suffix, $minlen,
         $tax_ids, $arch_file, $bact_file, $mol_conf, $seq_suffix, $silent,
         $i, $j, $dup_id, $nmax, $file2, $tax_dbh, $seq_ids, $seq_id,
         $seq_desc, $spe_ids, $spe_desc );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "recipe" => undef,
        "indir" => undef,
        "outdir" => undef,
        "readbuf" => 1000,
        "derep" => 1,
        "cluster" => 1,
        "nmax" => undef,
        "clobber" => 0,
        "silent" => 0,
        "header" => 1,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    $conf = &Install::Import::create_rdp_sub_seqs_args( $db, $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Convenience settings used below. See Taxonomy::Config where %RDP is set,

    $silent = $args->silent;
    $Common::Messages::silent = $silent;

    &echo("   Configuring internal settings ... ");
    
    $odir = $conf->outdir;
    $readbuf = $conf->readbuf;
    $header = $conf->header;
    $rcp_file = $conf->recipe;
    $clobber = $conf->clobber;

    $src_newest = &Common::File::get_newest_file( $conf->indir )->{"path"};

    $ref_mol = "SSU";
    $mol_conf = $Taxonomy::Config::DBs{"RDP"}{ $ref_mol };

    $prefix = $mol_conf->prefix;
    $suffix = $mol_conf->dbm_suffix;

    $tax_table = "$odir/$prefix$ref_mol". $mol_conf->tab_suffix;
    $tax_index = "$tax_table$suffix";

    $arch_id = $mol_conf->arch_id;
    $arch_file = "$odir/$prefix$ref_mol". "_$arch_id". $mol_conf->ref_suffix;

    $bact_id = $mol_conf->bact_id;
    $bact_file = "$odir/$prefix$ref_mol". "_$bact_id" . $mol_conf->ref_suffix;    
    
    &Common::File::create_dir_if_not_exists( $conf->outdir );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> INFO MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold("\nWriting RDP sub-sequences:\n") if $header;

    $text = qq (
      Datasets with sub-sequences that cover popular amplicons are 
      now being written to separate files. The ranges written are 
      defined in the easy-to-edit text file

      $rcp_file

      New alignment "slices" can be added to this file with a text
      editor, and when the installation is rerun, new slices will 
      be generated. The install may take up to an hour, three large
      compressed files are read, but this step has to be done only 
      when there is a new RDP release or a new sequence region is 
      needed.

);
    &echo_yellow( $text );

    $run_start = time();

    # >>>>>>>>>>>>>>>>>>>>>>> READ / WRITE RECIPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If there is a slicing recipe, use it. If not, write the default,

    $rcp = &Install::Import::read_write_template(
        $rcp_file, 
        bless {
            "refdb" => "RDP",
            "refmol" => $ref_mol,
            "clobber" => $clobber,
            "silent" => $silent,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a table with key/value store of taxonomy string with organism name
    # for each sequence. Below we use this as source of taxonomy strings.

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

        $count = &Install::Import::tablify_rdp_taxa({
            "seqfile" => $conf->seqs_tax,
            "tabfile" => $tax_table,
            "readbuf" => 1000,
        }, \@bads );
        
        if ( @bads ) {
            &Common::File::write_file("$tax_table.bad_names", [ map { $_ ."\n" } @bads ] );
        }

        &echo_done("$count rows\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a key/value store of taxonomy string with organism name for each
    # sequence. Below we use this as source of taxonomy strings.

    if ( not -r $tax_index or &Common::File::is_newer_than( $src_newest, $tax_index ) )
    {
        &echo("   Indexing taxonomy table ... ");
        
        &Install::Import::index_tax_table(
             $tax_table, 
             {
                 "keycol" => 0,         # Sequence id
                 "valcol" => 4,         # Taxonomy string with org name
                 "suffix" => $suffix,   # Kyoto cabinet file suffix
             });
        
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>> FIND ARCHEAL REFERENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If it is cached get it, otherwise read through the alignment and get the 
    # sequence and delete its gaps,

    if ( -r $arch_file )
    {
        &echo("   Reading archeal reference ... ");
        $arch_aseq = &Seq::IO::read_seqs_file( $arch_file )->[0];
    }
    else
    {
        &echo("   Finding archeal reference ... ");
        $arch_aseq = &Ali::Convert::get_ref_seq(
            {
                "file" => $conf->arch_ali,
                "readbuf" => $readbuf,
                "seqid" => $arch_id,
                "format" => "fasta_wrapped",
            });
        
        &Seq::IO::write_seqs_file( $arch_file, [ $arch_aseq ], "fasta" );
    }

    $arch_seq = &Seq::Common::delete_gaps( &Storable::dclone( $arch_aseq ) );
    $arch_max = ( length $arch_seq->{"seq"} ) - 1;

    &echo_done("$arch_id, length ". ($arch_max + 1) ."\n");

    # >>>>>>>>>>>>>>>>>>>>>> FIND BACTERIAL REFERENCE <<<<<<<<<<<<<<<<<<<<<<<<<

    # If it is cached get it, otherwise read through the alignment and get the 
    # sequence and delete its gaps,

    if ( -r $bact_file )
    {
        &echo("   Reading bacterial reference ... ");    
        $bact_aseq = &Seq::IO::read_seqs_file( $bact_file )->[0];
    }
    else
    {
        &echo("   Finding bacterial reference ... ");
        $bact_aseq = &Ali::Convert::get_ref_seq(
            {
                "file" => $conf->bact_ali,
                "readbuf" => $readbuf,
                "seqid" => $bact_id,
                "format" => "fasta_wrapped",
            });
        
        &Seq::IO::write_seqs_file( $bact_file, [ $bact_aseq ], "fasta" );
    }

    $bact_seq = &Seq::Common::delete_gaps( &Storable::dclone( $bact_aseq ) );
    $bact_max = ( length $bact_seq->{"seq"} ) - 1;

    &echo_done("$bact_id, length ". ($bact_max + 1) ."\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> ALIGN REFERENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Aligning reference sequences ... ");

    $ref_ali = &Seq::Align::align_two_nuc_seqs( \$bact_seq->{"seq"}, \$arch_seq->{"seq"} );

    foreach $step ( @{ $rcp->{"steps"} } )
    {
        next if not $step->{"region"};

        $step->{"bact-beg"} = $step->{"ref-beg"};
        $step->{"bact-end"} = $step->{"ref-end"};

        delete $step->{"ref-beg"};
        delete $step->{"ref-end"};

        $step->{"arch-beg"} = &Seq::Align::trans_position( $step->{"bact-beg"}, $bact_seq, $arch_seq )->[0];
        $step->{"arch-end"} = &Seq::Align::trans_position( $step->{"bact-end"}, $bact_seq, $arch_seq )->[1];
    }

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>> CONVERT TO ALIGNMENT POSITIONS <<<<<<<<<<<<<<<<<<<<<<

    # Translate bacterial and archaeal domain sequence positions to alignment
    # positions. An extra number of bases are added to each end,

    &echo("   Convert to alignment positions ... ");

    foreach $step ( @{ $rcp->{"steps"} } )
    {
        next if not $step->{"region"};

        $step->{"bact-beg"} = &Seq::Common::spos_to_apos( $bact_aseq, $step->{"bact-beg"} );
        $step->{"bact-end"} = &Seq::Common::spos_to_apos( $bact_aseq, $step->{"bact-end"} );
        $step->{"bact-len"} = $step->{"bact-end"} - $step->{"bact-beg"} + 1;
        
        $step->{"arch-beg"} = &Seq::Common::spos_to_apos( $arch_aseq, $step->{"arch-beg"} );
        $step->{"arch-end"} = &Seq::Common::spos_to_apos( $arch_aseq, $step->{"arch-end"} );
        $step->{"arch-len"} = $step->{"arch-end"} - $step->{"arch-beg"} + 1;
    }

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>> CREATE EXPORT POSITIONS <<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Configuring alignment exports ... ");
    
    $exports = &Install::Import::set_rdp_exports( $rcp );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> OPEN OUTPUT HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get taxonomy-read and sequence write-append handles,

    $ofhs = &Install::Import::open_export_handles( $exports, $odir );

    $tax_dbh = &Common::DBM::read_open("$tax_table$suffix");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # For each input file: slurp a number aligned sequences; for each output file, 
    # extract the right region from the aligned sequences; put the otu number of 
    # that sequence in the header.

    $nmax = $conf->nmax;

    foreach $ali ( "arch_ali", "bact_ali" )
    {
        &echo("   Writing $ali domain slices ... ");   

        $ali_file = $conf->$ali;

        $reader = &Seq::IO::get_read_routine( $ali_file );
        $ali_fh = &Common::File::get_read_handle( $ali_file );

        no strict "refs";

        while ( $ali_seqs = $reader->( $ali_fh, $readbuf ) )
        {
            # Skip the archaeal reference,

            if ( $ali eq "arch_ali" ) {
                $ali_seqs = [ grep { $_->{"id"} ne $arch_id } @{ $ali_seqs } ];
            }

            # Add sequence description and species name from DBM storage, used
            # for type-strain and species name filtering below,

            $seq_ids = [ map { $_->{"id"} } @{ $ali_seqs } ];
            $seq_desc = &Common::DBM::get_struct_bulk( $tax_dbh, $seq_ids );

            foreach $seq ( @{ $ali_seqs } ) {
                $seq->{"pid"} = $seq_desc->{ $seq->{"id"} }->[1];
            }

            $spe_ids = [ map { $_->{"pid"} } @{ $ali_seqs } ];
            $spe_ids = &Common::Util::uniqify( $spe_ids );

            $spe_desc = &Common::DBM::get_struct_bulk( $tax_dbh, $spe_ids );

            foreach $seq ( @{ $ali_seqs } )
            {
                $seq->{"info"} = 
                    "seq_desc=". $spe_desc->{ $seq->{"pid"} }->[0] ."; "
                               . $seq_desc->{ $seq->{"id"} }->[0];
            }

            # Aligned sequences all have same lengths,

            $ali_len = length $ali_seqs->[0]->{"seq"};

            # Process and write to all files opened in previous section,

            foreach $file ( keys %{ $ofhs } )
            {
                $export = $exports->{ $file };

                # If $ali was set in the previous section then slices are cut, 
                # otherwise use whole sequence,

                if ( ref $export->{ $ali } ) {
                    $seqs = $export->{"routine"}->( $ali_seqs, [ $export->{ $ali } ] );
                } else {
                    $seqs = $export->{"routine"}->( $ali_seqs, [[ 0, $ali_len ]] );
                }

                if ( $seqs and @{ $seqs } )
                {
                    # Optionally skip sequences with many N's,
                    
                    if ( defined $nmax ) {
                        $seqs = [ grep { $_->{"seq"} =~ tr/N/N/ < $nmax } @{ $seqs } ];
                    }
                    
                    # Delete annotation fields,
                    
                    # map { delete $_->{"info"} } @{ $seqs };

                    if ( @{ $seqs } ) {
                        &Seq::IO::write_seqs_fasta( $ofhs->{ $file }, $seqs );
                    }
                }

                undef $seqs;
            }
            
            undef $ali_seqs;
        }

        &Common::File::close_handle( $ali_fh );

        &echo_done("done\n");
    }

    map { &Common::File::close_handle( $_ ) } values %{ $ofhs };
    &Common::DBM::close( $tax_dbh );

    # >>>>>>>>>>>>>>>>>>>>>>> OPTIONAL DEREPLICATION <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Remove exact duplicates. This significantly reduces the file size, makes
    # outputs less verbose and improves the run time,

    if ( $conf->derep )
    {
        &Install::Import::derep_exports(
             $exports,
             {
                 "outdir" => $odir,
                 "taxtab" => $tax_table,
                 "taxsuf" => $suffix,
             });
    }
 
    # >>>>>>>>>>>>>>>>>>>> OPTIONAL CHIMERA CLUSTERING <<<<<<<<<<<<<<<<<<<<<<<<

    # Create smaller 99% clustered files for chimera checking, all sequences 
    # do not have to be there for that,

    if ( $conf->cluster )
    {
        &Install::Import::cluster_exports(
             $exports,
             {
                 "outdir" => $odir,
                 "minsim" => 99,
             });
    }
 
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FOOTERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $header )
    {
        &echo("   Time: ");
        &echo_info( &Time::Duration::duration( time() - $run_start ) ."\n" );
    }

    @ofiles = &Common::File::list_files( $odir, '.fasta$' );

    &echo_bold("\nFinished\n\n") if $header;

    return ( scalar @ofiles, undef );
}

sub create_rdp_sub_seqs_args
{
    # Niels Larsen, June 2012.

    # Creates a config object from the script input arguments. 

    my ( $db,
         $args,
        ) = @_;

    # Returns object.

    my ( @msgs, %args, @ofiles, $indir, @ifiles, $key, $val, $prefix, $suffix );

    $db = Registry::Get->dataset( $db );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args{"indir"} = $args->indir )
    {
        $indir = $args{"indir"};
        &Common::File::check_files( [ $indir ], "d", \@msgs );
    }
    else {
        $indir = $db->datapath_full ."/Sources";
    }

    if ( @ifiles = &Common::File::list_files( $indir, 'arch_aligned.fa.gz$' ) ) {
        $args{"arch_ali"} = $ifiles[0]->{"path"};
    } else {
        push @msgs, ["ERROR", qq (Input file not found -> "$indir/*arch_aligned.fa.gz") ];
    }
    
    if ( @ifiles = &Common::File::list_files( $indir, 'bact_aligned.fa.gz$' ) ) {
        $args{"bact_ali"} = $ifiles[0]->{"path"};
    } else {
        push @msgs, ["ERROR", qq (Input file not found -> "$indir/*bact_aligned.fa.gz") ];
    }
    
    if ( @ifiles = &Common::File::list_files( $indir, 'unaligned.gb.gz$' ) ) {
        $args{"seqs_tax"} = $ifiles[0]->{"path"};
    } else {
        push @msgs, ["ERROR", qq (Input file not found -> "$indir/*unaligned.gb.gz") ];
    }
    
    $args{"indir"} = $indir;

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Directory,

    if ( not $args{"outdir"} ) {
        $args{"outdir"} = $db->datapath_full ."/Installs";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RECIPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args{"recipe"} = $args->recipe;

    if ( not $args{"recipe"} ) {
        $args{"recipe"} = &File::Basename::dirname( $args{"outdir"} ) ."/RDP_regions.template";
    }
    
    # Switches,

    $args{"readbuf"} = $args->readbuf;
    $args{"nmax"} = $args->nmax;
    $args{"derep"} = $args->derep;
    $args{"cluster"} = $args->cluster;
    $args{"clobber"} = $args->clobber;
    $args{"header"} = $args->header;

    bless \%args;

    return wantarray ? %args : \%args;
}

sub create_rdp_sub_seqs_wrap
{
    # Niels Larsen, August 2012. 

    my ( $db,
         $args,
        ) = @_;

    return &Install::Import::create_rdp_sub_seqs(
        $db->name,
        {
            "indir" => $args->src_dir,
            "outdir" => $args->ins_dir,
            "readbuf" => 1000,
            "derep" => 1,
            "cluster" => 1,
            "nmax" => 10,
            "silent" => ( not $args->verbose ),
            "header" => 0,
        });
}

sub create_signature_dbm
{
    # Niels Larsen, May 2013.

    # Reads a file of sequences and their taxonomic positions, and writes a 
    # key/value storage with oligos that are unique, both sequences and 
    # taxonomic groups. The output is an oligo "roadmap" that can guide (or 
    # maybe replace) assignment of similarities to taxa. The storage written
    # is a key/value store where keys are unique taxonomy ids and values are
    # arrays of signature oligos to check for, formatted as string-arrays.
    # 
    # Implementation. The routine is long, because temporary storage is used
    # in order not to flood the RAM. Oligos are coded as integers, e.g. for 
    # 7-mers their values range from 0 to 4 ** 7 - 1. Oligos are used as 
    # indices to arrays that can hold counts of each oligo as well as masks.
    # Processing a sequence file and its taxonomy is done in these steps:
    #
    # 1. Make oligo counts for all immediate sequence parents
    # 2. Convert these counts to conservation masks
    # 3. Use masks to compute unique-masks for the whole tree
    # 4. Convert masks to oligo lists

    my ( $args,
        ) = @_;

    my ( $defs, $conf, $seq_fh, $tax_dbh, $oli_dbh, $seqs, $reader, $readbuf,
         $tree, $id, $seq, $wordlen, $node, $p_node, $olidim, $seqcons, 
         $grpcons, $tmp_dbh, $nodes, $p_id, $clobber, %save, $count,
         $params, %n_ids, @p_ids, %p_ids, $seqmin, $total, %next_ids, $n_ids,
         $p_nodes, $masks, $oliref, $uintbuf, $zeroes, $uintmask, $buckets,
         $seq_ids, $node_ids, $ids, $subref, $argref, $i, $j, $len, $i_max );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "seq_file" => undef,
        "tax_file" => undef,
        "oli_file" => undef,
        "tmp_file" => undef,
        "wordlen" => 7,
        "seqcons" => 95,
        "grpcons" => 95,
        "readbuf" => 1000,
        "clobber" => 1,
        "silent" => 0,
        "debug" => 0,
    };
    
    $conf = &Registry::Args::create( $args, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $Common::Messages::silent = $conf->silent;

    $wordlen = $conf->wordlen;
    $olidim = 4 ** $wordlen;
    $seqcons = $conf->seqcons / 100;
    $grpcons = $conf->grpcons / 100;
    $readbuf = $conf->readbuf;
    $clobber = $conf->clobber;

    $zeroes = ${ &Common::Util_C::new_array( $olidim, "uint" ) };
    $uintbuf = ${ &Common::Util_C::new_array( $olidim, "uint" ) };
    $uintmask = ${ &Common::Util_C::new_array( $olidim, "uint" ) };

    $reader = &Seq::IO::get_read_routine( $conf->seq_file );

    &echo("   Counting sequence file ... ");
    $buckets = &Seq::Stats::count_seq_file( $conf->seq_file )->{"seq_count"};
    &echo_done("done\n");

    # $buckets *= 0.12;
    $buckets = int $buckets;

    $params = {
        "apow" => 256,                # Alignment power
        "fpow" => 10,                 # Free block pool
        "bnum" => $buckets,           # Bucket number
        "msiz" => 512_000_000,        # Memory map size
        "pccap" => 512_000_000,       # Page cache
        "opts" => "l",                # Index type
    };
    
    # >>>>>>>>>>>>>>>>>>>>>>> STORE OLIGO COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This section stores oligo counts for sequence parents in the taxonomy. 
    # Keys are taxonomy ids and values are stringified tree nodes. Each node 
    # has the number of sequences (index SEQ_TOTAL) and a vector with totals 
    # for all oligos (index OLI_SUMS). The oligo totals are a compressed and 
    # stringified integer array where oligos are index, i.e. with as many slots 
    # as there are oligos. For word length 7 for example, oligo numbers range 
    # from 0 to 4 ** 7 - 1. 

    $seq_fh = &Common::File::get_read_handle( $conf->seq_file );
    $tax_dbh = &Common::DBM::read_open( $conf->tax_file );

    &Common::File::delete_file_if_exists( $conf->tmp_file );
    $tmp_dbh = &Common::DBM::write_open( $conf->tmp_file, "params" => $params );

    &echo("   Sequence parent counts ... ");
    
    %p_ids = ();
    $count = 0;

    {
        no strict "refs";

        while ( $seqs = $reader->( $seq_fh, $readbuf ) )
        {
            $count += scalar @{ $seqs };
            &dump( $count );

            # >>>>>>>>>>>>>>>>>>>> LOAD MINIMAL SUBTREE <<<<<<<<<<<<<<<<<<<<<<<

            # Load a taxonomy tree that spans all the sequences just read,
            
            $tree = {};
            $seq_ids = [ map { $_->{"id"} } @{ $seqs } ];

            &Taxonomy::Tree::load_new_nodes( $tax_dbh, $seq_ids, $tree );

            # >>>>>>>>>>>>>>>>>>>>>>>> LOAD COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            # Load the counts for all nodes and parents to the current batch 
            # of sequences, uncompress or initialize,
            
            $node_ids = &Taxonomy::Tree::list_parents( $tree );
            $nodes = &Common::DBM::get_struct_bulk( $tmp_dbh, $node_ids, 0 );

            foreach $id ( @{ $node_ids } )
            {
                if ( exists $nodes->{ $id } ) {
                    $nodes->{ $id }->[OLI_SUMS] = &Compress::LZ4::uncompress( $nodes->{ $id }->[OLI_SUMS] );
                } else {
                    $nodes->{ $id }->[OLI_SUMS] = $zeroes;
                }
            }

            # >>>>>>>>>>>>>>>>>>>>>> NODE OLIGO COUNTS <<<<<<<<<<<<<<<<<<<<<<<<

            # Create oligo counts for all sequences read and add them to the 
            # parents counts. Do not store the counts for sequences, they are 
            # redone in the next section.

            foreach $seq ( @{ $seqs } )
            {
                $id = $seq->{"id"};

                # Convert sequence to oligo catalog in $uintmask,

                &Seq::Oligos::seq_to_mask( \$seq->{"seq"}, $wordlen, \$uintmask );

                $nodes->{ $id }->[SEQ_TOTAL] = 1;
                $nodes->{ $id }->[OLI_SUMS] = $uintmask;

                # Update oligo sums of the sequence parent and increment the
                # sequence count of same,

                $p_id = $tree->{ $id }->[PARENT_ID];

                &Common::Util_C::add_arrays_uint_uint( $nodes->{ $p_id }->[OLI_SUMS], $uintmask, $olidim );

                $nodes->{ $p_id }->[SEQ_TOTAL] += 1;
                $nodes->{ $p_id }->[MAKE_MASK] = 1;

                push @{ $p_ids{ $p_id } }, $id;
            }

            # >>>>>>>>>>>>>>>>>>>>>>>>> SAVE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

            foreach $node ( values %{ $nodes } )
            {
                $node->[OLI_SUMS] = &Compress::LZ4::compress( $node->[OLI_SUMS] );
            }

            &Common::DBM::put_struct_bulk( $tmp_dbh, $nodes );
        }
    }

    # $node = &Common::DBM::get_struct( $tmp_dbh, "AAIF01000035.1339.2847" );
    # &dump( $node );

    &Common::File::close_handle( $seq_fh );

    &Common::DBM::close( $tax_dbh );
    &Common::DBM::close( $tmp_dbh );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> LOAD BACKBONE TREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Load into memory the entire backbone tree of nodes, but without sequence
    # leaves and without masks,

    &echo("   Loading backbone tree ... ");

    $tax_dbh = &Common::DBM::read_open( $conf->tax_file );

    $tree = {};
    
    &Taxonomy::Tree::load_new_nodes( $tax_dbh, [ keys %p_ids ], $tree );
    
    &Common::DBM::close( $tax_dbh );

    # Add sequence child_ids,

    # foreach $node ( values %{ $tree } )
    # {
    #     if ( $p_ids{ $node->[NODE_ID] } ) {
    #         @{ $node->[CHILD_IDS] } = @{ $p_ids{ $node->[NODE_ID] } };
    #     }
    # }

    &echo_done("done\n");

    # &dump( $tree );

    #while (1) {1};
    #exit;

    # >>>>>>>>>>>>>>>>>>>>>> STORE CONSERVATION MASKS <<<<<<<<<<<<<<<<<<<<<<<<<

    # For each group a mask is stored which tells the oligos that are conserved
    # among most/all of the sequences within. It does this by navigating, using
    # file storage, $tree from the leaves and up: conserved oligos are carried 
    # upwards in the tree to the root. The method does not depend on sequence 
    # counts within groups, only the number of groups are used.

    $subref = sub
    {
        my ( $tree,
             $nid,
            ) = @_;

        my ( $pnode, $node, $pid, $seqmin, $total );

        return if $nid eq $Root_id;

        # Load the current node,

        if ( $node = &Common::DBM::get_struct( $tmp_dbh, $nid, 0 ) ) {
            $node->[OLI_SUMS] = &Compress::LZ4::uncompress( $node->[OLI_SUMS] );
        } else {
            $node->[SEQ_TOTAL] = 0;
            $node->[OLI_SUMS] = $zeroes;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> COUNTS TO MASK <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # In the last section the MAKE_MASK flag was set when counts were 
        # updated. Here counts are converted to a mask and MAKE_MASK unset,

        if ( $node->[MAKE_MASK] )
        {
            $total = scalar @{ $tree->{ $nid }->[CHILD_IDS] };

            if ( $total == 0 ) {
                $total = $node->[SEQ_TOTAL];
            }
            
            $seqmin = &List::Util::max( 1, $grpcons * $total );

            &Seq::Oligos::counts_to_mask( \$node->[OLI_SUMS], \$uintbuf, $seqmin );
            $node->[OLI_MASK] = $uintbuf;

            undef $node->[MAKE_MASK];
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> INCREMENT PARENT <<<<<<<<<<<<<<<<<<<<<<<<<<

        # Increment counts one level up by the mask for the current node. For
        # example if a given oligo is in 5 sister groups, then the parent count
        # will be 5,

        if ( defined ( $pid = $tree->{ $nid }->[PARENT_ID] ) )
        {
            if ( $pnode = &Common::DBM::get_struct( $tmp_dbh, $pid, 0 ) ) {
                $pnode->[OLI_SUMS] = &Compress::LZ4::uncompress( $pnode->[OLI_SUMS] );
            } else {
                $pnode->[SEQ_TOTAL] = 0;
                $pnode->[OLI_SUMS] = $zeroes;
            }
            
            &Common::Util_C::add_arrays_uint_uint( $pnode->[OLI_SUMS], $node->[OLI_MASK], $olidim );
            
            $pnode->[SEQ_TOTAL] += $node->[SEQ_TOTAL];
            $pnode->[MAKE_MASK] = 1;

            $pnode->[OLI_SUMS] = &Compress::LZ4::compress( $pnode->[OLI_SUMS] );
            &Common::DBM::put_struct( $tmp_dbh, $pid, $pnode );
        }

        # Save current node,

        $node->[OLI_MASK] = &Compress::LZ4::compress( $node->[OLI_MASK] );
        &Common::DBM::put_struct( $tmp_dbh, $nid, $node );
        
        return;
    };

    &echo("   Store group-conserved masks ... ");

    $tmp_dbh = &Common::DBM::write_open( $conf->tmp_file, "params" => $params );
    $argref = [];
    
    &Taxonomy::Tree::traverse_tail( $tree, $Root_id, $subref, $argref );

    &Common::DBM::close( $tmp_dbh );

    &echo_done("done\n");

    &echo("   Printing conserved map ... ");
    &Install::Import::print_mask_map( $conf, $tree, \%p_ids, $conf->oli_file .".cons" );
    &echo_done("done\n");
    
    # >>>>>>>>>>>>>>>>>>>>> STORE GROUP-UNIQUE MASKS <<<<<<<<<<<<<<<<<<<<<<<<<<

    $subref = sub
    {
        my ( $tree,
             $nid,
            ) = @_;

        my ( $nodes, $ids, $id, @masks );
        
        $ids = $tree->{ $nid }->[CHILD_IDS];
        $nodes = &Common::DBM::get_struct_bulk( $tmp_dbh, $ids );

        foreach $id ( @{ $ids } )
        {
            push @masks, &Compress::LZ4::uncompress( $nodes->{ $id }->[OLI_MASK] );
        }

        &Seq::Oligos::uniq_masks( \@masks, \$uintbuf );

        for ( $i = 0; $i <= $#{ $ids }; $i += 1 )
        {
            $nodes->{ $ids->[$i] }->[OLI_MASK] = &Compress::LZ4::compress( $masks[$i] );
        }

        &Common::DBM::put_struct_bulk( $tmp_dbh, $nodes );
        
        return;
    };

    &echo("   Store group-unique masks ... ");

    $tmp_dbh = &Common::DBM::write_open( $conf->tmp_file, "params" => $params );
    $argref = [];
    
    &Taxonomy::Tree::traverse_head( $tree, $Root_id, $subref, $argref );

    &Common::DBM::close( $tmp_dbh );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>> STORE SEQUENCE-UNIQUE MASKS <<<<<<<<<<<<<<<<<<<<<<<

    # Navigate tree 

    $subref = sub 
    {
        my ( $tree,
             $nid,
             $pids,
            ) = @_;

        my ( $nodes, $ids, $id, @masks, $mask, $olis, $zeroes );
        
        if ( $ids = $pids->{ $nid } )
        {
            $nodes = &Common::DBM::get_struct_bulk( $tmp_dbh, $ids );

            foreach $id ( @{ $ids } )
            {
                push @masks, &Compress::LZ4::uncompress( $nodes->{ $id }->[OLI_MASK] );
            }

            &Seq::Oligos::uniq_masks( \@masks, \$uintbuf );
            
            # if ( $nid eq "tax_338" )
            # {
            #     foreach $mask ( @masks )
            #     {
            #         # $zeroes = ${ &Common::Util_C::new_array( $olidim, "uint" ) };
            #         $olis = ${ &Seq::Oligos::olis_from_mask( \$mask, \$uintbuf ) };
            #         # &dump([ scalar unpack "V*", $olis ]);
            #         &dump([ scalar grep { $_ > 0 } unpack "V*", $mask ]);
            #         &dump( length $olis );
            #     }
            # }
            
            for ( $i = 0; $i <= $#{ $ids }; $i += 1 )
            {
                $nodes->{ $ids->[$i] }->[OLI_MASK] = &Compress::LZ4::compress( $masks[$i] );
            }
            
            &Common::DBM::put_struct_bulk( $tmp_dbh, $nodes );
        }
        
        return;
    };

    &echo("   Store sequence-unique masks ... ");

    $tmp_dbh = &Common::DBM::write_open( $conf->tmp_file, "params" => $params );
    $argref = [ \%p_ids ];
    
    &Taxonomy::Tree::traverse_head( $tree, $Root_id, $subref, $argref );

    &Common::DBM::close( $tmp_dbh );

    &echo_done("done\n");

    &echo("   Printing unique map ... ");
    &Install::Import::print_mask_map( $conf, $tree, \%p_ids, $conf->oli_file .".uniq" );
    &echo_done("done\n");
    
    exit;

    # >>>>>>>>>>>>>>>>>>>>>>>> SAVE SEQUENCE OLIGOS <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # This section subtracts sequence parent node masks from sequence masks and
    # stores the oligos left over. That way sequences only have the oligos that
    # are variable between them within their parent group. The sequences are 
    # re-read while the oligo storage is updated, a small penalty to pay.

    $seq_fh = &Common::File::get_read_handle( $conf->seq_file );
    $tax_dbh = &Common::DBM::read_open( $conf->tax_file );

    $tmp_dbh = &Common::DBM::read_open( $conf->tmp_file );
    $oli_dbh = &Common::DBM::write_open( $conf->oli_file, "params" => $params );

    &echo("   Sequence signatures ... ");

    {
        no strict "refs";

        while ( $seqs = $reader->( $seq_fh, $readbuf ) )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>> LOAD TREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            # Create a taxonomy tree with the node oligo sums created above.
            # The tree spans the sequences just read, but only has counts for 
            # the nodes, not the sequences. Below sequence counts are made.

            $tree = {};
            $ids = [ map { $_->{"id"} } @{ $seqs } ];
            
            &Taxonomy::Tree::load_new_nodes( $tax_dbh, $ids, $tree );

            $ids = &Taxonomy::Tree::list_nodes( $tree );
            $nodes = &Common::DBM::get_struct_bulk( $tmp_dbh, $ids );

            foreach $node ( values %{ $nodes } ) {
                $tree->{ $node->[NODE_ID] }->[OLI_MASK] = &Compress::LZ4::uncompress( $node->[OLI_MASK] );
            }

            %save = ();

            foreach $seq ( @{ $seqs } )
            {
                $node = $tree->{ $seq->{"id"} };
                $p_node = $tree->{ $node->[PARENT_ID] };

                # Create oligo mask for the sequence and subtract the parent
                # mask from it,

                &Seq::Oligos::seq_to_mask( \$seq->{"seq"}, $wordlen, \$uintmask );
                &Seq::Oligos::mask_operation( \$uintmask, \$p_node->[OLI_MASK], \$uintmask, "del" );

                # Get the oligos from the resulting mask and add remember it,
                
                $oliref = &Seq::Oligos::olis_from_mask( \$uintmask, \$uintbuf );
                $save{ $node->[NODE_ID] } = ${ $oliref };
            }

            &Common::DBM::put_struct_bulk( $oli_dbh, \%save );
        }
    }

    &echo_done("done\n");

    #my $val = &Common::DBM::get_struct( $oli_dbh, "tax_225" );
    
    &Common::DBM::close( $tmp_dbh );
    &Common::DBM::close( $tax_dbh );
    &Common::DBM::close( $oli_dbh );

    if ( $conf->debug )
    {
        &echo("   Signature debug map ... ");
        # &Install::Import::print_mask_map( $conf );
        &echo_done("done\n");
    }

    return;
}

sub create_silva_sub_seqs
{
    # Niels Larsen, February 2013. 

    # From the Silva SSU and LSU distribution alignments, produces files with
    # unaligned sequences from the variable domains typically used for 
    # classification. Primer coordinates are configured in Taxonomy::Config.

    my ( $db,       # Dataset name or object
         $args,     # Arguments hash
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $idir, $odir, $text, $ali_file, $header, @msgs, 
         $readbuf, $seqs, $seq, $count, $ofhs, $ali_len, $exports, 
         $ali_fh, $ali_seqs, $export, $run_start, @ofiles, $silent, $rcp,
         $rcp_file, $clobber, $src_newest, $ref_mol, $mol_conf, $prefix,
         $suffix, $seq_suffix, $tax_table, $tax_index, @bads, $ref_id,
         $ref_file, $ref_aseq, $ref_seq, $ref_max, $step, $tax_dbh, $seq_ids,
         $seq_desc, $spe_ids, $spe_desc, $file, $nmax
        );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "recipe" => undef,
        "refmol" => undef,
        "indir" => undef,
        "outdir" => undef,
        "readbuf" => 1000,
        "derep" => 1,
        "cluster" => 1,
        "nmax" => undef,
        "clobber" => 0,
        "silent" => 0,
        "header" => 1,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    $conf = &Install::Import::create_silva_sub_seqs_args( $db, $args );

    $silent = $args->silent;
    $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Configuring internal settings ... ");

    $idir = $conf->indir;
    $odir = $conf->outdir;
    $readbuf = $conf->readbuf;
    $header = $conf->header;
    $rcp_file = $conf->recipe;
    $clobber = $conf->clobber;
    $nmax = $conf->nmax;
    $ref_mol = $conf->refmol;

    $src_newest = &Common::File::get_newest_file( $conf->indir )->{"path"};

    $mol_conf = $Taxonomy::Config::DBs{"Silva"}{ $ref_mol };

    $prefix = $mol_conf->prefix;
    $suffix = $mol_conf->dbm_suffix;

    $ali_file = $conf->ali_file;

    $tax_table = "$odir/$prefix$ref_mol". $mol_conf->tab_suffix;
    $tax_index = "$tax_table$suffix";

    $ref_id = $mol_conf->ref_id;
    $ref_file = "$odir/$prefix$ref_mol". "_$ref_id". $mol_conf->ref_suffix;

    &Common::File::create_dir_if_not_exists( $conf->outdir ) if $conf->clobber;

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> HELP MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold("\nWriting Silva slices:\n") if $header;

    $text = qq (
      Datasets with sub-sequences that cover popular amplicons are 
      now being written to separate files. The ranges written are 
      defined in the easy-to-edit text file

      $rcp_file

      New alignment "slices" can be added to this file with a text
      editor, and when the installation is rerun, new slices will 
      be generated. The install may take up to an hour, two large
      compressed files are read, but this step has to be done only 
      when there is a new Silva release or a new sequence region 
      is needed.

);

    &echo_yellow( $text );

    $run_start = time();
    
    # >>>>>>>>>>>>>>>>>>>>>>> READ / WRITE RECIPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If there is a slicing recipe, use it. If not, write the default,

    $rcp = &Install::Import::read_write_template(
        $rcp_file, 
        bless {
            "refdb" => "Silva",
            "refmol" => $ref_mol,
            "clobber" => $clobber,
            "silent" => $silent,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a table with key/value store of taxonomy string with organism name
    # for each sequence. Below we use this as source of taxonomy strings.

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

        $count = &Install::Import::tablify_silva_taxa({
            "seqfile" => $ali_file,
            "tabfile" => $tax_table,
            "readbuf" => 1000,
        }, \@bads );
        
        if ( @bads ) {
            &Common::File::write_file("$tax_table.bad_names", [ map { $_ ."\n" } @bads ] );
        }

        &echo_done("$count rows\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a key/value store of taxonomy string with organism name for each
    # sequence. Below we use this as source of taxonomy strings.

    if ( not -r $tax_index or &Common::File::is_newer_than( $src_newest, $tax_index ) )
    {
        &echo("   Indexing taxonomy table ... ");
        
        &Install::Import::index_tax_table(
             $tax_table, 
             {
                 "keycol" => 0,         # Sequence id
                 "valcol" => 2,         # Taxonomy string with org name
                 "suffix" => $suffix,   # Kyoto cabinet file suffix
             });
        
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SSU REFERENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( -r $ref_file )
    {
        &echo("   Reading $ref_mol reference sequence ... ");
        $ref_aseq = &Seq::IO::read_seqs_file( $ref_file )->[0];
    }
    else
    {
        &echo("   Finding $ref_mol reference sequence ... ");
        $ref_aseq = &Ali::Convert::get_ref_seq(
            {
                "file" => $ali_file,
                "readbuf" => $readbuf,
                "seqid" => $ref_id,
                "format" => "fasta_wrapped",
            });
        
        &Seq::IO::write_seqs_file( $ref_file, [ $ref_aseq ], "fasta" );
    }

    $ref_seq = &Seq::Common::delete_gaps( &Storable::dclone( $ref_aseq ) );
    $ref_max = ( length $ref_seq->{"seq"} ) - 1;

    &echo_done("$ref_id, length ". ($ref_max + 1) ."\n");

    # >>>>>>>>>>>>>>>>>>> CONVERT TO ALIGNMENT POSITIONS <<<<<<<<<<<<<<<<<<<<<<

    # Translate bacterial and archaeal domain sequence positions to alignment
    # positions. An extra number of bases are added to each end,

    &echo("   Convert to alignment positions ... ");

    foreach $step ( @{ $rcp->{"steps"} } )
    {
        next if not $step->{"region"};

        $step->{"ref-beg"} = &Seq::Common::spos_to_apos( $ref_aseq, $step->{"ref-beg"} );
        $step->{"ref-end"} = &Seq::Common::spos_to_apos( $ref_aseq, $step->{"ref-end"} );
        $step->{"ref-len"} = $step->{"ref-end"} - $step->{"ref-beg"} + 1;
    }
    
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>> CREATE EXPORT POSITIONS <<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Configuring alignment exports ... ");
    
    $exports = &Install::Import::set_silva_exports( $rcp );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>> OPENING OUTPUT HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get taxonomy-read and sequence write-append handles,

    $ofhs = &Install::Import::open_export_handles( $exports, $odir );

    $tax_dbh = &Common::DBM::read_open("$tax_table$suffix");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE SSU FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ali_fh = &Common::File::get_read_handle( $ali_file );

    &echo("   Writing $ref_mol domain slices ... ");   

    while ( $ali_seqs = &Seq::IO::read_seqs_fasta_wrapped( $ali_fh, $readbuf ) )
    {
        # Strip out eukaryotes for now,

        # $ali_seqs = [ grep { $_->{"info"} !~ /^Eukaryota/ } @{ $ali_seqs } ];
        # next if not @{ $ali_seqs };

        # Add sequence description and species name from DBM storage, used
        # for type-strain and species name filtering below,
        
        $seq_ids = [ map { $_->{"id"} } @{ $ali_seqs } ];
        $seq_desc = &Common::DBM::get_struct_bulk( $tax_dbh, $seq_ids );

        foreach $seq ( @{ $ali_seqs } ) {
            $seq->{"pid"} = $seq_desc->{ $seq->{"id"} }->[1];
        }
        
        $spe_ids = [ map { $_->{"pid"} } @{ $ali_seqs } ];
        $spe_ids = &Common::Util::uniqify( $spe_ids );

        $spe_desc = &Common::DBM::get_struct_bulk( $tax_dbh, $spe_ids );
        
        foreach $seq ( @{ $ali_seqs } )
        {
            $seq->{"info"} = 
                "seq_desc=". $spe_desc->{ $seq->{"pid"} }->[0] ."; "
                . $seq_desc->{ $seq->{"id"} }->[0];
        }

        # Aligned sequences all have same lengths,
        
        $ali_len = length $ali_seqs->[0]->{"seq"};

        foreach $file ( keys %{ $ofhs } )
        {
            $export = $exports->{ $file };
            
            # If $ali was set in the previous section then slices are cut, 
            # otherwise use whole sequence,
            
            if ( $export->{"range"} ) {
                $seqs = $export->{"routine"}->( $ali_seqs, [ $export->{"range"} ] );
            } else {
                $seqs = $export->{"routine"}->( $ali_seqs, [[ 0, $ali_len ]] );
            }

            if ( $seqs and @{ $seqs } )
            {
                # Optionally skip sequences with many N's,
                
                if ( defined $nmax ) {
                    $seqs = [ grep { $_->{"seq"} =~ tr/N/N/ < $nmax } @{ $seqs } ];
                }
                
                # Write fasta format,
                    
                if ( @{ $seqs } ) {
                    &Seq::IO::write_seqs_fasta( $ofhs->{ $file }, $seqs );
                }
            }
        }
    }
    
    &Common::File::close_handle( $ali_fh );
    map { &Common::File::close_handle( $_ ) } values %{ $ofhs };

    &Common::DBM::close( $tax_dbh );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>> OPTIONAL DEREPLICATION <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Remove exact duplicates. This significantly reduces the file size, makes
    # outputs less verbose and improves the run time,

    if ( $conf->derep )
    {
        &Install::Import::derep_exports(
             $exports,
             {
                 "outdir" => $odir,
                 "taxtab" => $tax_table,
                 "taxsuf" => $suffix,
             });
    }
 
    # >>>>>>>>>>>>>>>>>>>> OPTIONAL CHIMERA CLUSTERING <<<<<<<<<<<<<<<<<<<<<<<<

    # Create smaller 99% clustered files for chimera checking, all sequences 
    # do not have to be there for that,

    if ( $conf->cluster )
    {
        &Install::Import::cluster_exports(
             $exports,
             {
                 "outdir" => $odir,
                 "minsim" => 99,
             });
    }
 
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FOOTERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $header )
    {
        &echo("   Time: ");
        &echo_info( &Time::Duration::duration( time() - $run_start ) ."\n" );
    }

    @ofiles = &Common::File::list_files( $odir, "$suffix\$" );
    
    &echo_bold("\nFinished\n\n") if $header;

    return ( scalar @ofiles, undef );
}

sub create_silva_sub_seqs_args
{
    # Niels Larsen, June 2012.

    # Creates a config object from the script input arguments. 

    my ( $db,
         $args,
        ) = @_;

    # Returns object.

    my ( @msgs, %args, @ofiles, $indir, @ifiles, $key, $val, $ssu_file,
         $lsu_file, $ref_mol );

    $db = Registry::Get->dataset( $db );

    # >>>>>>>>>>>>>>>>>>>>>>>>> REFERENCE MOLECULE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $ref_mol = $args->refmol )
    {
        if ( $ref_mol !~ /^SSU|LSU$/ ) {
            push @msgs, ["ERROR", qq (Wrong looking reference molecule -> "$ref_mol") ];
            push @msgs, ["INFO", qq (It must be either "SSU" or "LSU") ];
        }
    }
    else
    {
        push @msgs, ["ERROR", qq (No reference molecule given) ];
        push @msgs, ["INFO", qq (It must be either "SSU" or "LSU") ];
        &append_or_exit( \@msgs );
    }

    $args{"refmol"} = $ref_mol;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args{"indir"} = $args->indir )
    {
        $indir = $args{"indir"};
        &Common::File::check_files( [ $indir ], "d", \@msgs );
    }
    else {
        $indir = $db->datapath_full ."/Sources";
    }

    if ( @ifiles = &Common::File::list_files( $indir, 'SSURef_' ) ) {
        $ssu_file = $ifiles[0]->{"path"};
    } else {
        push @msgs, ["ERROR", qq (Input file not found -> "$indir/SSURef_*") ];
    }
    
    if ( @ifiles = &Common::File::list_files( $indir, 'LSURef_' ) ) {
        $lsu_file = $ifiles[0]->{"path"};
    } else {
        push @msgs, ["ERROR", qq (Input file not found -> "$indir/LSURef_*") ];
    }

    if ( $args->refmol eq "LSU" ) {
        $args{"ali_file"} = $lsu_file;
    } else {
        $args{"ali_file"} = $ssu_file;
    }
    
    $args{"indir"} = $indir;

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Directory,

    if ( not $args{"outdir"} ) {
        $args{"outdir"} = $db->datapath_full ."/Installs";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RECIPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args{"recipe"} = $args->recipe;

    if ( not $args{"recipe"} ) {
        $args{"recipe"} = &File::Basename::dirname( $args{"outdir"} ) ."/Silva_regions.template";
    }

    &append_or_exit( \@msgs );
    
    # IDs, switches and settings,

    $args{"readbuf"} = $args->readbuf;
    $args{"nmax"} = $args->nmax;
    $args{"derep"} = $args->derep;
    $args{"cluster"} = $args->cluster;
    $args{"clobber"} = $args->clobber;
    $args{"header"} = $args->header;

    bless \%args;

    return wantarray ? %args : \%args;
}

sub create_silva_sub_seqs_wrap
{
    # Niels Larsen, February 2013. 

    # TODO: call this twice, once for SSU and once for LSU

    my ( $db,
         $args,
        ) = @_;

    return &Install::Import::create_silva_sub_seqs(
        $db->name,
        {
            "refmol" => "SSU",
            "indir" => $args->src_dir,
            "outdir" => $args->ins_dir,
            "readbuf" => 1000,
            "derep" => 1,
            "cluster" => 1,
            "nmax" => 10,
            "silent" => ( not $args->verbose ),
            "header" => 0,
        });
}

sub derep_exports
{
    # Niels Larsen, February 2013.

    # Helper function that dereplicates all the exported slices except type
    # and species ones. Returns the number of processed files. 

    my ( $exports,
         $args,
        ) = @_;

    my ( $odir, $taxtab, $dbmsuf, $dup_id, $count, $file, $i, $j );

    $odir = $args->{"outdir"};
    $taxtab = $args->{"taxtab"};
    $dbmsuf = $args->{"taxsuf"};

    $dup_id = 0;
    $count = 0;
    
    foreach $file ( sort keys %{ $exports } )
    {
        next if $file =~ /all\./;
        next if $file =~ /minlen_/;
        next if $file =~ /\-T\.rna_seq/;
        next if $file =~ /\-S\.rna_seq/;
        
        &echo("   Dereplicating $file ... ");
        
        ( $i, $j, $dup_id ) = &Install::Import::derep_sub_seqs(
            {
                "seq_file" => "$odir/$file",
                "tax_dbm" => "$taxtab$dbmsuf",
                "dup_id" => $dup_id,
            });
        
        &Common::File::count_lines( "$odir/$file", 1 );
        
        &echo_done("$i -> $j\n");

        $count += 1;
    }
    
    return $count;
}

sub derep_sub_seqs
{
    # Niels Larsen, December 2012.

    # Writes a dereplicated sequence file and updates the corresponding taxonomy
    # DBM storage: all identical sequences that have the same taxonomic parent 
    # are written only once; collapsed sequences are erased from the DBM storage
    # and a new entry for the collapsed sequence is added. The name of this new 
    # entry is generated and its taxonomic parent is the same as those it 
    # replaces. Returns [ input seq count, output seq count ].

    my ( $args,
        ) = @_;
    
    # Returns two element list.

    my ( $seq_file, $tax_dbm, $out_file, $format, $readbuf, $ifile, $ofile,
         $ifh, $ofh, $dbh, $read_sub, $seq_tax, $tax_seq, $seq_id, $tax_id,
         $id_list, $tax_val, $write_sub, $iseqs, $seq, @out_seqs, @seq_ids,
         $seq_count, $dup_id, $tax_save, $ndxsuf, $in_count, $out_count );
    
    $seq_file = $args->{"seq_file"};
    $tax_dbm = $args->{"tax_dbm"};
    $out_file = $args->{"out_file"};
    $dup_id = $args->{"dup_id"};
    $readbuf = $args->{"readbuf"} // 1000;

    $format = "fasta";
    $ndxsuf = ".derep";

    $ifile = "$seq_file.derep.$format";

    if ( $out_file ) {
        $ofile = $out_file;
    } else {
        $ofile = "$ifile.tmp";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DEREPLICATE ALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First collapse all identical sequences into one and write a fasta file 
    # with the collapsed ids in the header. The output file get new integer ids
    # for all sequences, but that is fixed below. Output goes to 
    # "$seq_file.derep.fasta",

    &Seq::Storage::create_indices(
        {
            "ifiles" => [ $seq_file ],
            "progtype" => "derep",
            "outfmt" => $format,
            "ndxsuf" => $ndxsuf,
            "outsuf" => ".$format",
            "outids" => 1,
            "count" => 1,
            "clobber" => 1,
            "silent" => 1,
        });

    &Common::File::delete_file("$seq_file$ndxsuf");
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> EXPAND DEREP FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # After the above, the problem is that the collapsed sequences may belong 
    # to different taxa. To fix that, we rewrite the file to include identical
    # sequences when they are from different taxa. 

    &Common::File::delete_file_if_exists( $ofile );
    
    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( $ofile );

    $dbh = &Common::DBM::write_open( $tax_dbm );
    
    $read_sub = &Seq::IO::get_read_routine( $ifile, $format );
    $write_sub = &Seq::IO::get_write_routine( $format );

    no strict "refs";

    $in_count = 0;
    $out_count = 0;

    while ( $iseqs = &{ $read_sub }( $ifh, $readbuf ) )
    {
        @out_seqs = ();
        $tax_save = {};

        foreach $seq ( @{ $iseqs } )
        {
            # Get sequence count and original ids (always inserted above),

            if ( $seq->{"info"} =~ /seq_count=(\d+)/ ) {
                $seq_count = $1;
                $in_count += $seq_count;
            } else {
                &error( qq (Entry has no sequence count -> $seq->{"id"}) );
            }                

            if ( $seq->{"info"} =~ /seq_ids=(.+)/ ) {
                @seq_ids = split " ", $1;
            } else {
                &error( qq (Entry has no sequence ids -> $seq->{"id"}) );
            }

            if ( $seq_count > 1 )
            {
                # >>>>>>>>>>>>>>>>>>> DUPLICATED SEQUENCE <<<<<<<<<<<<<<<<<<<<<

                # A sequence occurs more than once, but maybe within more than
                # one species too - and if so, we keep one representative for 
                # each species (or higher). To do that, first put the sequence
                # ids into a hash where keys are taxonomy ids, called $tax_seq,

                $seq_tax = &Common::DBM::get_struct_bulk( $dbh, \@seq_ids );
                $tax_seq = {};

                while ( ( $seq_id, $tax_val ) = each %{ $seq_tax } )
                {
                    $seq_id =~ s/^seq_//;
                    push @{ $tax_seq->{ $tax_val->[1] } }, $seq_id;
                }

                # Then for each taxon, write the duplicated once,

                foreach $tax_id ( keys %{ $tax_seq } )
                {
                    if ( ( $seq_count = scalar @{ $tax_seq->{ $tax_id } } ) > 1 )
                    {
                        # Duplicate sequence within the same taxon. Create a new
                        # unique ID and put the duplicate count and original IDs
                        # in the header,

                        $dup_id += 1;

                        push @out_seqs, {
                            "id" => "duplicate_". $dup_id,
                            "seq" => $seq->{"seq"},
                            "info" => "seq_count=$seq_count seq_ids=" . join " ", @{ $tax_seq->{ $tax_id } },
                        };

                        # Create new taxonomy records to be saved below,

                        if ( exists $tax_save->{ "duplicate_$dup_id" } ) {
                            &error( qq (Sequence id exists -> "duplicate_$dup_id") );
                        } else {
                            $tax_save->{"duplicate_$dup_id"} = [ "n__$seq_count duplicate sequences", $tax_id ];
                        }
                    }
                    else
                    {
                        # If only one sequence per taxon, save it using the 
                        # original id,

                        push @out_seqs, {
                            "id" => $tax_seq->{ $tax_id }->[0], 
                            "seq" => $seq->{"seq"},
                            "info" => "seq_count=1",
                        };
                    }
                }
            }
            else 
            {
                # >>>>>>>>>>>>>>>>>>>>>>> SINGLETON <<<<<<<<<<<<<<<<<<<<<<<<<<<

                # No change, save with original id,

                push @out_seqs, {
                    "id" => $seq_ids[0],
                    "seq" => $seq->{"seq"},
                    "info" => "seq_count=1",
                };
            }
        }

        # Write the same format as the input,

        &{ $write_sub }( $ofh, \@out_seqs );

        $out_count += scalar @out_seqs;

        # Save taxonomy tuples for the sequence duplicates,

        if ( %{ $tax_save } ) {
            &Common::DBM::put_struct_bulk( $dbh, $tax_save );
        }
    }        

    &Common::DBM::close( $dbh );

    &Common::File::close_handle( $ofh );
    &Common::File::close_handle( $ifh );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL REPLACE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $out_file )
    {
        &Common::File::delete_file( $seq_file );
        &Common::File::rename_file( $ofile, $seq_file );
    }

    &Common::File::delete_file( $ifile );

    if ( wantarray ) {
        return ( $in_count, $out_count, $dup_id );
    } else {
        return [ $in_count, $out_count, $dup_id ];
    }
}

sub import_genomes_ebi
{
    # Niels Larsen, August 2010.

    # Loops through the source genomes and installs those that have a more recent
    # timestamp. The import_sequences routine is reused. Returns a two element 
    # list: ( number of installed genomes, 0 ). Use the install_data routine
    # in functions.

    my ( $db,         # Dataset
         $conf,       # Configuration, directories etc
         $msgs,       # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a two-element list.

    my ( $ebi_file, @ebi_list, $ebi, $tax_id, $dir, $tax_conf, $src_dir,
         $ins_dir, $silent, $org_name, $org_count, $io_list, $file_count,
         $count, %done );

    $silent = $conf->silent;

    # Get list of source entries,

    $ebi_file = $conf->dat_dir ."/". $db->name .".yaml";
    @ebi_list = map { bless $_, "Common::Obj" } @{ &Common::File::read_yaml( $ebi_file ) };

    # See if a given genome needs be updated,

    $org_count = 0;
    $file_count = 0;

    foreach $ebi ( @ebi_list )
    {
        $tax_conf = &Storable::dclone( $conf );
        $tax_id = $ebi->org_taxid;

        next if $done{ $tax_id };
        
        foreach $dir ( grep { $_ =~ /_dir$/ } ( keys %{ $tax_conf } ) ) {
            $tax_conf->{ $dir } .= "/$tax_id";
        }

        ( $src_dir, $ins_dir ) = ( $tax_conf->src_dir, $tax_conf->ins_dir );

        if ( &Install::Data::needs_import( $src_dir, $ins_dir ) or $tax_conf->force )
        {
            $org_name = ${ &Common::File::read_file( "$src_dir/ORGANISM" ) };
            chomp $org_name;
            
            &echo( "   $org_name (tax. id $tax_id) ... " ) unless $silent;

            &Common::File::create_dir_if_not_exists( $ins_dir );
            &Common::File::delete_file_if_exists( "$ins_dir/ORGANISM" );
            &Common::File::copy_file( "$src_dir/ORGANISM", "$ins_dir/ORGANISM" );

            $tax_conf->silent( 1 );
            $tax_conf->force( 1 );
            
            &Common::File::create_dir_if_not_exists( $ins_dir );
            ( $io_list, undef ) = &Install::Data::import_sequences( $db, $tax_conf, $msgs );

            $done{ $tax_id } = 1;
            
            $count = scalar @{ $io_list };

            $file_count += $count;
            $org_count += 1;

            Registry::Register->set_timestamp( $ins_dir );

            if ( $count > 1 ) {
                &echo_green( "$count files\n" ) unless $silent;
            } else {
                &echo_green( "1 file\n" );
            }
        }
    }

    return ( $file_count, 0 );
}

sub index_tax_table
{
    # Niels Larsen, October 2012. 

    # Reads a table and creates a DBM file the path of which is returned. 
    # These keys and values are saved,
    #
    # tax_<integer> =>  [ taxonomy name string, parent node id ]
    # <seq_id>      =>  [ sequence definition text, parent node id ]
    # 
    # The purpose of this structure is to support mapping similarity values 
    # to a taxonomy.

    my ( $file,     # Table file name
         $args,     # Arguments hash - OPTIONAL
        ) = @_;

    # Returns two-element list.

    my ( $defs, $keycol, $valcol, $ndx_size, $mem_map, $page_cache, $buckets,
         $ifh, $dbh, %dbm_buf, $count, $line, $key, $val, $fldsep, $seq_id, 
         $tax_id, $tax_map, $suffix, $tax_str, $tax_line, @taxa, $i, $bufsiz,
         $par_id, $list, @tax_str, $total );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "keycol" => 0,
        "valcol" => 4,
        "suffix" => ".dbm",
        "bufsiz" => 1_000,
        "fldsep" => "\t",
        "clobber" => 0,
    };
         
    $args = &Registry::Args::create( $args, $defs );
    
    $keycol = $args->keycol;
    $valcol = $args->valcol;
    $suffix = $args->suffix;
    $bufsiz = $args->bufsiz;
    $fldsep = $args->fldsep;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIGURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This says "if page cache will fit into ram, then give Kyoto big page 
    # cache. If not, the it is better to set a high memory map",
    
    if ( -e $file ) {
        $ndx_size = ( -s $file ) * 1.5;    # Usually less than 1.5 x input
    } else {
        &error( qq (File does not exist -> "$file") );
    }

    $mem_map = 128_000_000;
    $page_cache = 128_000_000;

    if ( $ndx_size + $mem_map < &Common::OS::ram_avail() ) {
        $page_cache = $ndx_size;
    } else {
        $mem_map = $ndx_size;
    }
    
    $buckets = &Common::File::count_lines( $file ) * 1.5;

    # >>>>>>>>>>>>>>>>>>>>>>>>> MAP TAXONOMY PARENTS <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Make a taxonomic parent map with keys and values like this,
    #
    # taxonomy-string => [ id, parent id ]
    
    $ifh = &Common::File::get_read_handle( $file );

    $dbh = &Common::DBM::write_open( "$file$suffix", "bnum" => $buckets, 
                                     "msiz" => $mem_map, "pccap" => $page_cache  );
    $count = 0;
    $total = 0;
    $tax_id = 0;

    %dbm_buf = ();
    $tax_map->{"r__Root"} = [ "tax_0", undef ];

    while ( defined ( $line = <$ifh> ) )
    {
        next if $line =~ /^#/;
        chomp $line;

        # Get sequence id and taxonomy string from table line,

        ( $seq_id, $tax_line ) = ( split $fldsep, $line )[ $keycol, $valcol ];

        # Replace blank OTUs with "Unclassified",

        $tax_line =~ s/__;/__Unclassified;/g;

        # Create a taxonomy string => [ node id, parent id ] hash. The table 
        # taxonomy string includes a sequence name that is skipped for this 
        # hash, but is used below,

        @taxa = split "; ", $tax_line;

        $tax_str = "";
        $par_id = "tax_0";            # Parent id
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> TAXA ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        for ( $i = 0; $i < $#taxa; $i ++ )
        {
            if ( $tax_str ) {
                $tax_str .= "; ". $taxa[$i];
            } else {
                $tax_str = $taxa[$i];
            }

            if ( exists $tax_map->{ $tax_str } )
            {
                $par_id = $tax_map->{ $tax_str }->[0];
            }
            else
            {
                $tax_map->{ $tax_str } = [ "tax_". ++$tax_id, $par_id ];
                $par_id = "tax_". $tax_id;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCES ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Grow a sequence id -> [ name string, parent id ] hash. The parent id
        # is the last parent id from above,

        $dbm_buf{ $seq_id } = [ $taxa[-1], $par_id ];

        $count += 1;

        # Save the hash to DBM storage periodically, them empty it,

        if ( $count >= $bufsiz )
        {
            &Common::DBM::put_struct_bulk( $dbh, \%dbm_buf );
            %dbm_buf = ();

            $total += $count;
            $count = 0;
        }
    }

    # Flush any remaining buffer,

    if ( %dbm_buf )
    {
        &Common::DBM::put_struct_bulk( $dbh, \%dbm_buf );
        $total += keys %dbm_buf;

        %dbm_buf = ();
    }

    # >>>>>>>>>>>>>>>>>>>>> INVERT TAXONOMY DICTIONARY <<<<<<<<<<<<<<<<<<<<<<<<
    
    # Create a node id => [ taxon name string, parent id ] hash from $tax_map 
    # above and save to a DBM file. Also get a list of node ids that is saved 
    # below.

    while ( 1 )
    {
        %dbm_buf = ();
        $count = 0;

        while ( ( $tax_str, $list ) = each %{ $tax_map } and $count < $bufsiz )
        {
            ( $tax_id, $par_id ) = @{ $list };

            @tax_str = split "; ", $tax_str;
            
            $dbm_buf{ $tax_id } = [ $tax_str[-1], $par_id ];
            $count += 1;

            delete $tax_map->{ $tax_str };
        }

        if ( $count > 0 )
        {
            &Common::DBM::put_struct_bulk( $dbh, \%dbm_buf );
            
            $total += $count;
            $count = 0;
        } 
        else {
            last;
        }
    }

    # Close handles,
    
    &Common::DBM::close( $dbh );

    &Common::File::close_handle( $dbh );
    &Common::File::close_handle( $ifh );

    return "$file$suffix";
}

sub load_oli_counts
{
    my ( $dbh,
         $tree,
         $nulls,
        ) = @_;

    my ( $ids, $id, $tree2 );
         
    $ids = &Taxonomy::Tree::list_nodes( $tree );            

    $tree2 = &Common::DBM::get_struct_bulk( $dbh, $ids, 0 );
    
    foreach $id ( @{ $ids } )
    {
        if ( exists $tree2->{ $id } ) 
        {
            $tree->{ $id } = $tree2->{ $id };
            $tree->{ $id }->[OLI_SUMS] = &Compress::LZ4::uncompress( $tree->{ $id }->[OLI_SUMS] );
        }
        else
        {
            $tree->{ $id }->[SEQ_TOTAL] = 0;
            $tree->{ $id }->[OLI_SUMS] = $nulls;
        }            
    }
    
    return;
}

sub open_export_handles
{
    # Niels Larsen, February 2013.

    # Opens output file handles corresponding to the files in the given 
    # exports hash. Optionally deletes existing files. Returns a hash of
    # file handles.

    my ( $exports,       # Exports hash
         $odir,          # Output directory
         $clobber,       # Delete existing files - OPTIONAL, default 1
        ) = @_;

    # Returns a hash.

    my ( $count, $file, $ofhs );

    $clobber //= 1;

    if ( $clobber )
    {
        &echo("   Deleting old output files ... ");
        
        $count = 0;
        
        foreach $file ( sort keys %{ $exports } )
        {
            $count += &Common::File::delete_file_if_exists("$odir/$file");
        }
        
        &echo_done("$count\n");
    }

    &echo("   Getting all file handles ... ");

    foreach $file ( sort keys %{ $exports } )
    {
        $ofhs->{ $file } = &Common::File::get_write_handle("$odir/$file");
    }

    $count = keys %{ $exports };

    &echo_done("$count\n");

    return wantarray ? %{ $ofhs } : $ofhs;
}
    
sub parse_green_header
{
    # Niels Larsen, September 2012.

    # Parses a header string from the Greengenes fasta formatted sequence 
    # distribution file into a hash with these keys,
    # 
    # gb_acc             Genbank accession number
    # org_name           Organism name string
    # org_taxon          Organism taxonomy string
    # org_otu            Organism OTU number
    #
    # The format with the k__ etc placeholders is kept as "native" in 
    # downstream analyses.

    my ( $hdr,     # Header string
         $msgs,    # Output parse error messages - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( $info, $msg );

    if ( $hdr =~ /^(\S+)\s+(.+?)\s+(k__.+);\s*otu_(\d+)/ )
    {
        $info = {
            "gb_acc" => $1,
            "org_name" => $2,
            "gg_otu" => $4,
        };

        $info->{"org_taxon"} = &Install::Import::parse_green_taxstr( $3, $2 );

        $info->{"org_name"} =~ s/;\s*//g;

        return wantarray ? %{ $info } : $info;
    } 
    else
    {
        $msg = qq (Wrong looking Greengenes header -> "$hdr");

        if ( defined $msgs ) {
            push @{ $msgs }, ["ERROR", $msg ];
        } else {
            &error( $msg );
        }
    }

    return;
}

sub parse_green_taxstr
{
    # Niels Larsen, September 2012.

    # Converts a Greengenes taxonomy string to Kingdom, Phylum, Class, Order, 
    # Family and Genus groupings. They are almost like that already, but with
    # a few inconsistencies. One significant edit is done: when there s__ 
    # species slot is empty, but there is a species name in the organism name,
    # then that species is put in parantheses, 's__(name)' to indicate that 
    # its the authors opinion, not Greengenes'. Returns a new string being
    # used by the taxonomy routines. 

    my ( $str,        # Taxonomy string
         $name,       # Organism name string
        ) = @_;

    # Returns string.

    my ( %groups, $group, $genus, $species );

    foreach $group ( split /;\s*/, $str )
    {
        next if $group eq "Unclassified";
        
        if ( $group =~ /^([kpcofgs])__(.*)$/ )
        {
            $groups{ $1 } = $2 // "";
        }
        elsif ( $group eq "Crocosphaera" )   # Format problem
        {
            $groups{"g"} = $group;
        }
        elsif ( $group ne "HTCC" )           # Format problem
        {
            &error( qq (Wrong looking taxonomy group -> "$group") );
        }
    }

    if ( ( $genus = $groups{"g"} ) and not $groups{"s"} and $name =~ /^$genus\s+(\S+)/ )
    {
        $species = $1;

        if ( $species !~ /^(sp|str|cf)\.?$/ ) {
            $groups{"s"} = "$genus ($species)";
        }
    }
    
    $str = join "; ", map { $_ ."__". ( $groups{ $_ } // "" ) } qw ( k p c o f g s );
    
    return $str;
}
    
sub parse_rdp_taxstr
{
    # Niels Larsen, September 2012.

    # Converts an RDP taxonomy and definition string to kingdom, phylum, 
    # class, order, family, genus, species and description groupings. It
    # is a hodge-podge that reflects RDP annotation inconsistencies. The
    # purpose of the routine is to create fixed levels where species etc
    # always occur at the same depth. Returns a string where names are 
    # prefixed with k__, p__, etc, as required by the taxonomy routines.

    my ( $itax,        # Input taxonomy string
         $desc,        # Input description string
        ) = @_;

    # Returns string.
    
    my ( @otax, $otax, $i, $genus, $species );

    # Trip trailing period and blanks, 

    $itax =~ s/\s*\.\s*$//;
    $desc =~ s/\.\s*$//;

    if ( $itax =~ /^Root; ((?:Bacteria|Archaea|Eu[ck]aryotes).*)$/i )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>> PRUNE TAXONOMY <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        @otax = split /;\s*/, $1;

        # Remove start/end quotes and incertae_sedis,,

        @otax = map { $_ =~ s/"//g; $_ } @otax;

        # Remove _incertae_sedis from ends,

        @otax = map { $_ =~ s/_incertae_sedis$//; $_ } @otax;

        # Remove sub-class,

        if ( $#otax >= FAMILY and $otax[FAMILY] =~ /ales$/ )
        {
            splice @otax, ORDER, 1;
        }

        # Remove sub-order,

        if ( $#otax >= FAMILY and $otax[FAMILY] =~ /ineae$/ )
        {
            splice @otax, FAMILY, 1;
        }

        # Blank out group names up to genus that have "unclassified" in them,
        
        if ( $#otax >= GENUS ) {
            map { $otax[$_] = "" if $otax[$_] =~ /unclassified/i } ( KINGDOM ... GENUS );
        } else {
            map { $otax[$_] = "" if $otax[$_] =~ /unclassified/i } ( KINGDOM ... $#otax );
        }

        # Make blanks '-' in order,

        if ( $#otax >= ORDER )
        {
            $otax[ORDER] =~ s/ /-/g;
        }

        # Remove "Incertae_Sedis" from family and make blanks '-',

        if ( $#otax >= FAMILY )
        {
            if ( $otax[FAMILY] =~ /(.+)(Incertae\s+Sedis.*)/i ) {
                $otax[FAMILY] = $1;
            }

            $otax[FAMILY] =~ s/ /-/g;
        }

        # Remove "sensu stricto" from genus and make blanks '-',

        if ( $#otax >= GENUS )
        {
            if ( $otax[GENUS] =~ /(.+)\s*sensu\s+stricto.*/ ) {
                $otax[GENUS] = $1;
            }

            $otax[GENUS] =~ s/ /-/g;            
        }

        # Check for the right number of elements,

        if ( $#otax > GENUS )
        {
            unshift @otax, "Output:";
            chomp $itax;
            unshift @otax, "Input: $itax";
            unshift @otax, "Too many taxon divisions\n";
            &error( \@otax );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>> FILL GENUS AND SPECIES <<<<<<<<<<<<<<<<<<<<<<

        # This section sets the genus and species slots (g__ and s__ prefixes)
        # by comparing the description string with the taxonomy string. First
        # genera and species to ignore,

        state $g_skip = {
            "Cloning" => 1,
            "Arctic" => 1,
            "Antarctic" => 1,
        };

        state $s_skip = {
            "archaeon" => 1,
            "algae" => 1,
            "symbiont" => 1,
            "secondary" => 1,
            "type" => 1,
            "vector" => 1,
            "culture" => 1,
            "enrichment" => 1,
            "bacterium" => 1,
            "bacteriuum" => 1,
            "baterium" => 1,
            "gen." => 1,
            "genomosp." => 1,
            "genomsp." => 1,
            "genosp." => 1,
            "n." => 1,
            "str." => 1,
            "sp." => 1,
            "sp" => 1,
            "sea" => 1,
            "seawater" => 1,
        };

        $desc =~ s/\s+cf\.\s*/ /;
        $desc =~ s/\s+aff\.\s*/ /;

        # If description looks like 'Genus species' then use this information 
        # to fill slots,

        if ( $desc =~ /^([A-Z][a-z]+)\s+([a-z\-\.]+)/ )
        {
            $genus = $1;
            $species = $2;

            $genus = "" if $g_skip->{ $genus };
            $species = "" if $s_skip->{ $species };

            if ( $#otax >= FAMILY )
            {
                # Only if family is set does genus + species make sense,

                if ( $otax[GENUS] )
                {
                    # Genus in taxonomy string. If it matches the one from 
                    # description, shrink description. If not, keep it and 
                    # leave description as is,

                    $otax[GENUS] = "" if $g_skip->{ $otax[GENUS] };

                    if ( $otax[GENUS] =~ /$genus/ )
                    {
                        $otax[GENUS] = $genus;
                        $desc =~ s/$genus//g;

                        if ( $#otax < SPECIES )
                        {
                            $otax[SPECIES] = $species;
                            $desc =~ s/$species//;
                        }
                    }
                }
                else
                {
                    # Genus not in taxonomy string. Use whatever useful names
                    # in the description.
                    
                    if ( grep /$genus/, @otax[ KINGDOM .. FAMILY ] ) {
                        $otax[GENUS] = "";
                    } else {
                        $otax[GENUS] = $genus;
                    }

                    $desc =~ s/$genus//;

                    if ( $otax[SPECIES] ) 
                    {
                        &error( qq (Species but no genus: $itax) );
                    }
                    else 
                    {
                        $otax[SPECIES] = $species;
                        $desc =~ s/$species//;
                    }
                }
            }
        }

        # Important: there may not be semicolons in the description,

        $desc =~ s/;//g;
        $desc = join " ", grep { $_ ne "" } split " ", $desc;

        # >>>>>>>>>>>>>>>>>>>>>> GENERATE OUTPUT STRING <<<<<<<<<<<<<<<<<<<<<<<

        # Append empty slots so that all levels up to species are defined,

        if ( ( $i = $#otax ) < SPECIES )
        {
            push @otax, ("") x ( SPECIES - $i );
        }

        # Add placeholders,

        for ( $i = 0; $i <= $#otax; $i++ )
        {
            $otax[$i] = $Tax_divs->{ $i } . $otax[$i];
        }

        $otax = join "; ", @otax;
        $otax .= "; +__$desc";
    }
    elsif ( $itax =~ /^Root; unclassified/i )
    {
        $otax = "k__; p__; c__; o__; f__; g__; s__";
    }
    else {
        &error( qq (Does not start with "Root;" -> "$itax") );
    }

    return $otax;
}

sub parse_silva_taxstr
{
    # Niels Larsen, February 2013.

    # Converts a Silva prokaryote taxonomy string to kingdom, phylum, class, order,
    # family, genus, species and description groupings. The routine is a hodge-podge
    # tries to overcome annotation inconsistencies. Its purpose is to create fixed 
    # levels where species etc always occur at the same depth without removing
    # information. Returns a string where names are prefixed with k__, p__, etc,
    # as required by various taxonomy routines. 

    my ( $itax,        # Input taxonomy string
        ) = @_;

    # Returns string.
    
    my ( $otax );

    if ( $itax =~ /^(?:Bacteria|Archaea).*\s*$/i )
    {
        $otax = &Install::Import::parse_silva_taxstr_prok( $itax );
    }
    elsif ( $itax =~ /^Eu[ck]aryota;/i )
    {
        $otax = &Install::Import::parse_silva_taxstr_euk( $itax );
    }
    else {
        &error( qq (Wrong looking kingdom -> "$itax") );
    }

    return $otax;
}

sub parse_silva_taxstr_euk
{
    # Niels Larsen, March 2013.

    # Converts a Silva eukaryte taxonomy string to fixed level bacterial-style 
    # kingdom, phylum, class, order, family, genus, species and description 
    # groupings. It discards many other higher level groupings in order to make
    # it fit. The purpose of the routine is to create levels where species etc 
    # always occur at the same depth. Returns a string where names are prefixed
    # with k__, p__, etc, as required by various taxonomy routines. 

    my ( $itax,        # Input taxonomy string
        ) = @_;

    # Returns string.
    
    my ( @otax, $otax, $i, $desc, $imax, $genus, $species, $rest );

    state $g_skip = {
        "Cloning" => 1,
    };
    
    state $s_skip = {
        "uncultured" => 1,
        "sp." => 1,
        "cf." => 1,
    };

    $desc = "";

    if ( $itax =~ /^(Eu[ck]aryota.*?)\s*$/i )
    {
        $otax = $1;

        # Remove all single quotes and brackets,
        
        $otax =~ s/\'//g;
        $otax =~ s/\[//g;
        $otax =~ s/\]//g;
        
        # Remove text following an '(' that is not matched by ')',
        
        if ( $otax =~ /\(/ and $otax !~ /\)/ )
        {
            $otax =~ /\(/;
            $otax = $PREMATCH;
        }
        
        # Split by semi-colons 
        
        @otax = split /;\s*/, $otax;

        # Discard "SAR",

        @otax = grep { $_ ne "SAR" } @otax;

        # Discard all higher groups or add blanks, so the result is always 6 levels,

        if ( $#otax > GENUS )
        {
            splice @otax, 1, 1;

            if ( $#otax > GENUS ) {
                splice @otax, 1, $#otax - GENUS;
            }
        }
        elsif ( ( $i = $#otax ) < GENUS )
        {
            push @otax, ("") x ( GENUS - $i );
        }
            
        # Blank out all other slots where "Incertae" occurs

        for ( $i = 0; $i <= $#otax; $i++ )
        {
            if ( $otax[$i] =~ /Incertae/ ) {
                $otax[$i] = "";
            }
        }

        # Remove 'cf.' everywhere,

        map { $_ =~ s/cf\.\s+// } @otax;

        # Get genus and species,

        if ( $otax[GENUS] =~ /^([A-Z][a-z]+)\s+([a-z\-\.]+)\s*(.*)$/ )
        {
            # Looks like 'Genus species' name. If there is a species field, delete the 
            # first word if it matches genus,
            
            $genus = $1;
            $species = $2;
            $rest = $3 // "";
            
            $genus = "" if $g_skip->{ $genus };
            $species = "" if $s_skip->{ $species };
            
            $otax[GENUS] = $genus if not $otax[GENUS];
            
            if ( $otax[GENUS] =~ /$genus/ )
            {
                $otax[GENUS] = $genus;
                $otax[SPECIES] = $species;
                $desc .= $rest ." ";
            }
            else 
            {
                $desc .= $otax[SPECIES] ." ";
                $otax[SPECIES] = "";
            }
        }
        else
        {
            # No 'Genus species' name. Append all in genus and species fields
            # to the description and clear those fields,
            
            if ( $otax[GENUS] )
            {
                $desc .= $otax[GENUS] ." ";
                $otax[GENUS] = "";
            }

            if ( $otax[SPECIES] )
            {
                $desc .= $otax[SPECIES] ." ";
                $otax[SPECIES] = "";
            }
        }                
        
        $desc =~ s/^\s*\(\s*//;
        $desc =~ s/\s*\)\s*$//;

        # >>>>>>>>>>>>>>>>>>>>>> GENERATE OUTPUT STRING <<<<<<<<<<<<<<<<<<<<<<<

        # Append empty slots so that all levels up to species are defined,

        if ( ( $i = $#otax ) < SPECIES )
        {
            push @otax, ("") x ( SPECIES - $i );
        }
        elsif ( $#otax > SPECIES )
        {
            &error( \@otax );
        }

        # Add placeholders,

        for ( $i = 0; $i <= $#otax; $i++ )
        {
            $otax[$i] = $Tax_divs->{ $i } . $otax[$i];
        }

        $otax = join "; ", @otax;

        # Important: there must not be semicolons in the description,

        $desc =~ s/;/ /g;
        $desc = join " ", grep { $_ ne "" } split " ", $desc;
        
        $otax .= "; +__$desc";
    }
    else {
        &error( qq (Does not start with Eucaryota or Eukaryota -> "$itax") );
    }

    return $otax;
}

sub parse_silva_taxstr_prok
{
    # Niels Larsen, February 2013.

    # Converts a Silva taxonomy string to kingdom, phylum, class, order, family,
    # genus, species and description groupings. It is a hodge-podge that reflects
    # annotation inconsistencies. The purpose of the routine is to create fixed 
    # levels where species etc always occur at the same depth without removing
    # information. Returns a string where names are prefixed with k__, p__, etc,
    # as required by the taxonomy routines. 

    my ( $itax,        # Input taxonomy string
        ) = @_;

    # Returns string.
    
    my ( @otax, $otax, $i, $desc, $imax, $genus, $species, $rest );

    $desc = "";

    if ( $itax =~ /^((?:Bacteria|Archaea).*)\s*$/i )
    {
        $otax = $1;

        # >>>>>>>>>>>>>>>>>>>>>>>>> PRUNE TAXONOMY <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Remove all single quotes and brackets,
        
        $otax =~ s/\'//g;
        $otax =~ s/\[//g;
        $otax =~ s/\]//g;

        # Remove text following an '(' that is not matched by ')',

        if ( $otax =~ /\(/ and $otax !~ /\)/ )
        {
            $otax =~ /\(/;
            $otax = $PREMATCH;
        }
        
        # Split by semi-colons,

        @otax = split /;\s*/, $otax;

        # Remove sub-classes,

        if ( $#otax >= FAMILY and $otax[FAMILY] =~ /ales$/ and $otax[FAMILY] !~ /uncult/i )
        {
            splice @otax, ORDER, 1;
        }
        
        # Remove sub-orders,

        if ( $#otax >= GENUS and $otax[FAMILY] =~ /ineae$/ and $otax[GENUS] !~ /uncult/i )
        {
            splice @otax, FAMILY, 1;
        }

        # If chloroplast, move last field with host to description and yank the rest,

        if ( $#otax >= ORDER and $otax[CLASS] =~ /Chloroplast/i )
        {
            $desc .= "host: $otax[ORDER]";
            splice @otax, ORDER;
        }

        # If phytoplasma, move last field with host to description and yank the rest,

        if ( $#otax >= FAMILY and $otax[ORDER] =~ /Phytoplasma/i )
        {
            $desc .= "host: $otax[FAMILY]";
            splice @otax, FAMILY;
        }

        # Replace "Incertae Sedis" in the genus slot with either the paranthesized 
        # name in the species slot or nothing,

        if ( $#otax >= GENUS and $otax[GENUS] =~ /Incertae\s+Sedis/ )
        {
            if ( $#otax >= SPECIES )
            {
                if ( $otax[SPECIES] =~ /^([A-Z][a-z]{3,})/ ) {
                    $otax[GENUS] = "($1)";
                } else {
                    $otax[GENUS] = "";
                }
            }
            else {
                $otax[GENUS] = "";
            }
        }

        # Blank out all other slots where "Incertae" occurs

        for ( $i = 0; $i <= $#otax; $i++ )
        {
            if ( $otax[$i] =~ /Incertae/ ) {
                $otax[$i] = "";
            }
        }

        # Delete Candidatus in all but description,

        for ( $i = 0; $i <= $#otax; $i++ )
        {
            $otax[$i] =~ s/\s*Candidatus\s*//;

            last if $i == SPECIES;
        }

        # Blank out slots up until genus where uncultured, unidentified, or 
        # unclassified occurs,

        if ( $#otax < GENUS ) {
            $imax = $#otax;
        } else {
            $imax = GENUS;
        }

        for ( $i = 0; $i <= $imax; $i++ )
        {
            if ( $otax[$i] =~ /^[a-z]/ or
                 $otax[$i] =~ / / or
                 $otax[$i] =~ /un(cult|identified|classified)/ ) 
            {
                $desc .= ( join " ", @otax[ $i .. $imax ] ) ." ";
                splice @otax, $i;

                last;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>> SET MISSING FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<

        # This section sets the genus and species slots (g__ and s__ prefixes).
        # The species part of the taxonomy string may contain both genus and
        # species name, and culture collection etc. First genera and species 
        # to ignore,

        state $g_skip = {
            "Cloning" => 1,
            "Arctic" => 1,
            "Antarctic" => 1,
        };

        state $s_skip = {
            "archaeon" => 1,
            "algae" => 1,
            "symbiont" => 1,
            "secondary" => 1,
            "type" => 1,
            "vector" => 1,
            "culture" => 1,
            "enrichment" => 1,
            "bacterium" => 1,
            "bacteriuum" => 1,
            "baterium" => 1,
            "gen." => 1,
            "genomosp." => 1,
            "genomsp." => 1,
            "genosp." => 1,
            "n." => 1,
            "str." => 1,
            "sp." => 1,
            "sp" => 1,
            "sea" => 1,
            "seawater" => 1,
        };

        if ( $#otax >= SPECIES and $otax[SPECIES] ne "" ) 
        {
            $otax[SPECIES] =~ s/\s+cf\.\s*/ /;
            $otax[SPECIES] =~ s/\s+aff\.\s*/ /;
            
            if ( $otax[SPECIES] =~ /^([A-Z][a-z]+)\s+([a-z\-\.]+)\s*(.*)$/ )
            {
                # Looks like 'Genus species' name. If there is a species field, delete the first word if it 
                # matches genus,

                $genus = $1;
                $species = $2;
                $rest = $3 // "";

                $genus = "" if $g_skip->{ $genus };
                $species = "" if $s_skip->{ $species };

                $otax[GENUS] = $genus if not $otax[GENUS];

                if ( $otax[GENUS] =~ /$genus/ )
                {
                    $otax[GENUS] = $genus;
                    $otax[SPECIES] = $species;
                    $desc .= $rest ." ";
                }
                else 
                {
                    $desc .= $otax[SPECIES] ." ";
                    $otax[SPECIES] = "";
                }
            }
            else
            {
                # No 'Genus species' name. Append all to the description and
                # clear the species field,

                $desc .= $otax[SPECIES] ." ";
                $otax[SPECIES] = "";
            }

            $otax[SPECIES] = "" if $otax[SPECIES] =~ /^sp\.?$/i;
        }

        # >>>>>>>>>>>>>>>>>>>>>> GENERATE OUTPUT STRING <<<<<<<<<<<<<<<<<<<<<<<

        # Append empty slots so that all levels up to species are defined,

        if ( ( $i = $#otax ) < SPECIES )
        {
            push @otax, ("") x ( SPECIES - $i );
        }
        elsif ( $#otax > SPECIES )
        {
            &error( \@otax );
        }

        # Add placeholders,

        for ( $i = 0; $i <= $#otax; $i++ )
        {
            $otax[$i] = $Tax_divs->{ $i } . $otax[$i];
        }

        $otax = join "; ", @otax;

        # Important: there must not be semicolons in the description,

        $desc =~ s/;/ /g;
        $desc = join " ", grep { $_ ne "" } split " ", $desc;
        
        $otax .= "; +__$desc";
    }
    else { 
        &error( qq (Does not start with Bacteria or Archaea -> "$itax") );
    }

    return $otax;
}

sub read_write_template
{
    # Niels Larsen, August 2012. 

    # Reads a sub-sequence alignment-slicing template. Or if none exists,
    # writes the default to the dataset home and returns that. 

    my ( $file,       # Input/output file
         $args,       # Arguments hash
        ) = @_;

    # Returns recipe object.

    my ( $clobber, $silent, $conf, $ref_mol, $ref_db, $name, $rcp, $text );
    
    if ( not $conf = $Taxonomy::Config::DBs{ $args->refdb }{ $args->refmol } )
    {
        $ref_db = $args->refdb;
        $ref_mol = $args->refmol;

        &error( qq ("$ref_mol" settings not found for the "$ref_db" dataset in \$Taxonomy::Config::DBs) );
    }
    
    $clobber = $args->clobber // 0;
    $silent = $args->silent // 0;

    $name = &File::Basename::basename( $file );

    if ( $file and -s $file )
    {
        &echo("   Reading $name ... ");
        $rcp = &Recipe::IO::read_recipe( $file );
    }
    else
    {
        &echo("   Writing $name ... ");

        $text = &Taxonomy::Config::subseq_template( $conf );

        &Common::File::delete_file_if_exists( $file ) if $clobber;
        &Common::File::write_file( $file, $text );

        $rcp = &Recipe::IO::read_recipe( $file );
    }

    $rcp = &Taxonomy::Config::edit_subseq_template( $rcp, $conf );

    &echo_done("done\n");

    return $rcp;
}

sub conserved_mask
{
    my ( $masks,
         $cons,
         $buf,
        ) = @_;

    return;
}

sub set_rdp_exports
{
    # Niels Larsen, February 2013.

    # Configures which RDP species, type strains and whole collections files 
    # to write. Also sets compiled export routines. Just a helper routine. 

    my ( $rcp,       # Template
        ) = @_;

    # Returns a hash. 

    my ( $exports, $step, $file, $minlen );

    $exports = {};

    foreach $step ( @{ $rcp->{"steps"} } )
    {
        $file = &File::Basename::basename( $step->{"out-file"} );

        $minlen = $step->{"minimum-length"} // 20;

        if ( $file =~ /\d+\-\d+\./ )
        {
            $exports->{ $file }->{"arch_ali"} = [ $step->{"arch-beg"}, $step->{"arch-len"} ];
            $exports->{ $file }->{"bact_ali"} = [ $step->{"bact-beg"}, $step->{"bact-len"} ];

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                { 
                    "minres" => $minlen, "cover" => 1, "degap" => 1, "upper" => 1,
                });

            $file =~ s/\.rna_seq/-T\.rna_seq/;

            $exports->{ $file }->{"arch_ali"} = [ $step->{"arch-beg"}, $step->{"arch-len"} ];
            $exports->{ $file }->{"bact_ali"} = [ $step->{"bact-beg"}, $step->{"bact-len"} ];

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                { 
                    "minres" => $minlen, "cover" => 1, "degap" => 1, "upper" => 1, "annot" => '\(T\)|(type strain)',
                });

            $file =~ s/-T\.rna_seq/-S\.rna_seq/;

            $exports->{ $file }->{"arch_ali"} = [ $step->{"arch-beg"}, $step->{"arch-len"} ];
            $exports->{ $file }->{"bact_ali"} = [ $step->{"bact-beg"}, $step->{"bact-len"} ];

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                { 
                    "minres" => $minlen, "cover" => 1, "degap" => 1, "upper" => 1, "annot" => 's__[a-z]',
                });
        }
        elsif ( $file =~ /minlen_(\d+)/ )
        {
            $minlen = $1;

            $exports->{ $file }->{"arch_ali"} = undef;
            $exports->{ $file }->{"bact_ali"} = undef;

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                {
                    "minres" => $minlen, "cover" => 0, "degap" => 1, "upper" => 1, 
                });

            $file =~ s/\.rna_seq/-T\.rna_seq/;

            $exports->{ $file }->{"arch_ali"} = undef;
            $exports->{ $file }->{"bact_ali"} = undef;

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                {
                    "minres" => $minlen, "cover" => 0, "degap" => 1, "upper" => 1, "annot" => '\(T\)|(type strain)',
                });

            $file =~ s/-T\.rna_seq/-S\.rna_seq/;

            $exports->{ $file }->{"arch_ali"} = undef;
            $exports->{ $file }->{"bact_ali"} = undef;

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                {
                    "minres" => $minlen, "cover" => 0, "degap" => 1, "upper" => 1, "annot" => 's__[a-z]',
                });
        }
        elsif ( $file =~ /_all\./ )
        {
            $exports->{ $file }->{"arch_ali"} = undef;
            $exports->{ $file }->{"bact_ali"} = undef;
            
            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                {
                    "minres" => 1, "cover" => 0, "degap" => 1, "upper" => 1,
                });

            $file =~ s/\.rna_seq/-T\.rna_seq/;

            $exports->{ $file }->{"arch_ali"} = undef;
            $exports->{ $file }->{"bact_ali"} = undef;

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                {
                    "minres" => 1, "cover" => 0, "degap" => 1, "upper" => 1, "annot" => '\(T\)|(type strain)',
                });

            $file =~ s/-T\.rna_seq/-S\.rna_seq/;

            $exports->{ $file }->{"arch_ali"} = undef;
            $exports->{ $file }->{"bact_ali"} = undef;

            $exports->{ $file }->{"routine"} = eval &Ali::Convert::slice_code(
                {
                    "minres" => 1, "cover" => 0, "degap" => 1, "upper" => 1, "annot" => 's__[a-z]',
                });
        }
        else {
            &error( qq (Wrong looking file name -> "$file") );
        }
    }

    return wantarray ? %{ $exports } : $exports;
}

sub set_silva_exports
{
    # Niels Larsen, February 2013.

    # Configures which Silva species, type strains and whole collections 
    # files to write. Also sets compiled export routines. Just a helper 
    # routine. 

    my ( $rcp,       # Template
        ) = @_;

    # Returns a hash. 

    my ( $exports, $step, $file, $minres, %def_args );

    $exports = {};
    
    %def_args = ( "minres" => 20, "cover" => 1, "degap" => 1, "upper" => 1, "u2t" => 1 );

    foreach $step ( @{ $rcp->{"steps"} } )
    {
        $file = &File::Basename::basename( $step->{"out-file"} );

        $minres = $step->{"minimum-length"} // 20;

        if ( $file =~ /\d+\-\d+\./ )
        {
            # Alignment slices, full and species-only,
            
            $exports->{ $file }->{"range"} = [ $step->{"ref-beg"}, $step->{"ref-len"} ];

            $exports->{ $file }->{"routine"} = 
                eval &Ali::Convert::slice_code( \%def_args );
            
            $file =~ s/\.rna_seq/-S\.rna_seq/;

            $exports->{ $file }->{"range"} = [ $step->{"ref-beg"}, $step->{"ref-len"} ];

            $exports->{ $file }->{"routine"} = 
                eval &Ali::Convert::slice_code({ %def_args, "annot" => 's__[a-z]', "minres" => $minres });
        }
        elsif ( $file =~ /minlen_(\d+)/ )
        {
            # Length filtered, full and species-only,

            $minres = $1;

            $exports->{ $file }->{"range"} = undef;

            $exports->{ $file }->{"routine"} = 
                eval &Ali::Convert::slice_code({ %def_args, "minres" => $minres, "cover" => 0 });

            $file =~ s/\.rna_seq/-S\.rna_seq/;

            $exports->{ $file }->{"range"} = undef;

            $exports->{ $file }->{"routine"} = 
                eval &Ali::Convert::slice_code({ %def_args, "minres" => $minres, "cover" => 0, "annot" => 's__[a-z]' });
        }
        elsif ( $file =~ /_all\./ )
        {
            # Full length, all sequences and species-only,

            $exports->{ $file }->{"range"} = undef;
            
            $exports->{ $file }->{"routine"} =
                eval &Ali::Convert::slice_code({ %def_args, "cover" => 0 });

            $file =~ s/\.rna_seq/-S\.rna_seq/;

            $exports->{ $file }->{"range"} = undef;

            $exports->{ $file }->{"routine"} = 
                eval &Ali::Convert::slice_code({ %def_args, "cover" => 0, "annot" => 's__[a-z]' });
        }
        else {
            &error( qq (Wrong looking file name -> "$file") );
        }
    }

    return wantarray ? %{ $exports } : $exports;
}

sub tablify_green_taxa
{
    # Niels Larsen, September 2012. 

    # Writes a table from the Greengenes fasta formatted unaligned sequence
    # distribution file and taxonomy tables. The columns are,
    # 
    # Sequence ID
    # OTU running number
    # OTU Greengenes number  (empty for now)
    # Genbank accession
    # Organism taxonomy with organism name
    # Organism name, free format
    # 
    # The k__, p__ etc prefixes are kept, as they provide anchor points used
    # in taxonomy mapping of similarities. RDP taxonomy strings are converted
    # to this form too, inconsistencies allowing.

    my ( $args,
         $bads,
        ) = @_;

    # Returns a list. 

    my ( $defs, $seqs, $seq, $readbuf, $tab_fh, $seq_fh, $otu, $reader,
         @rows, $count, $info, $seq_id, $taxa, $gbacc, $acc, $tax_str );

    $defs = {
        "readbuf" => 10_000,
        "seqfile" => undef,
        "taxa" => {},
        "gbacc" => {},
        "tabfile" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );
    $bads //= [];

    $reader = &Seq::IO::get_read_routine( $args->seqfile );
    $readbuf = $args->readbuf;

    $taxa = $args->taxa;
    $gbacc = $args->gbacc;
    
    $seq_fh = &Common::File::get_read_handle( $args->seqfile );
    $tab_fh = &Common::File::get_write_handle( $args->tabfile );

    $otu = 0;

    $tab_fh->print("# seq_id\totu\tgg_otu\tgb_acc\torg_taxon\torg_name\n");

    no strict "refs";
            
    while ( $seqs = $reader->( $seq_fh, $readbuf ) )
    {
        use strict "refs";

        @rows = ();
        
        foreach $seq ( @{ $seqs } )
        {
            $otu += 1;

            $seq_id = $seq->{"id"};

            if ( not $tax_str = $taxa->{ $seq_id } ) {
                &error( qq (No taxonomy string for "$seq_id") );
            }

            if ( not $acc = $gbacc->{ $seq_id } ) {
                &error( qq (No Genbank accession for "$seq_id") );
            }

            push @rows, ( join "\t",
                          ( $seq->{"id"},
                            $otu,
                            "",
                            $acc // "",
                            $tax_str ."; n__Genbank: $acc",
                            "No Greengenes description. Genbank: $acc",
                          ) ) ."\n";
        }
        
        $tab_fh->print( @rows );
        
        $count += scalar @rows;
    }

    &Common::File::close_handle( $tab_fh );
    &Common::File::close_handle( $seq_fh );
    
    return $count;
}

sub tablify_rdp_taxa
{
    # Niels Larsen, September 2012. 

    # Writes a table from the RDP genbank formatted unaligned sequence file.
    # The columns are,
    # 
    # Sequence ID           
    # OTU number            (Running integer from 1)
    # NCBI Taxonomy ID
    # Genbank accession
    # Organism taxonomy
    # Some description
    # 
    # The first two words of the organism name is called genus and species 
    # even though the organism name format is very inconsistent. It will be 
    # too much manual work to make them consistent; we can hope RDP sees it
    # as a curational issue that should be fixed.

    my ( $args,
         $bads,
        ) = @_;

    # Returns a list. 

    my ( $defs, $seqs, $seq, $readbuf, $ofh, $ifh, $otu, $reader, @rows, 
         $genus, $species, $rest, $count, $info, $tax_str );

    $defs = {
        "readbuf" => 1000,
        "seqfile" => undef,
        "tabfile" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );
    $bads //= [];

    $reader = &Seq::IO::get_read_routine( $args->seqfile );
    $readbuf = $args->readbuf;
    
    $ifh = &Common::File::get_read_handle( $args->seqfile );
    $ofh = &Common::File::get_write_handle( $args->tabfile );

    $otu = 0;

    $ofh->print("# seq_id\totu\tncbi_taxid\tgb_acc\torg_taxon\torg_def\n");

    no strict "refs";
            
    while ( $seqs = $reader->( $ifh, $readbuf ) )
    {
        use strict "refs";

        @rows = ();
        
        foreach $seq ( @{ $seqs } )
        {
            $otu += 1;
            $info = $seq->{"info"};

            # Create a "k__; p__; c__; o__; f__; g__; s__; +__" style taxonomy string,

            $tax_str = &Install::Import::parse_rdp_taxstr(
                $info->{"org_taxon"},
                $info->{"definition"},
                );

            # Add row,

            # exit if $info->{"definition"} =~ /Y0018/;
            
            push @rows, ( join "\t", ( $seq->{"id"}, $otu, $info->{"ncbi_taxid"} // "",
                                       $info->{"gb_acc"} // "", $tax_str // "",
                                       $info->{"definition"} // "" ) ) ."\n";
        }
        
        $ofh->print( @rows );
        
        $count += scalar @rows;
    }

    &Common::File::close_handle( $ofh );
    &Common::File::close_handle( $ifh );
    
    return $count;
}

sub tablify_silva_taxa
{
    # Niels Larsen, February 2013. 

    # Writes a table from the Silva alignment files. The columns are,
    # 
    # Sequence ID           
    # OTU number            (Running integer from 1)
    # Organism taxonomy
    # Some description
    # 
    # The first two words of the organism name is called genus and species 
    # even though the organism name format is very inconsistent. It will be 
    # too much manual work to make them consistent; we can hope Silva sees
    # it as a curational issue that should be fixed.

    my ( $args,
         $bads,
        ) = @_;

    # Returns a list. 

    my ( $defs, $seqs, $seq, $readbuf, $ofh, $ifh, $otu, $reader, @rows, 
         $count, $tax_str, $def_str );

    $defs = {
        "readbuf" => 1000,
        "seqfile" => undef,
        "tabfile" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );
    $bads //= [];

    $reader = &Seq::IO::get_read_routine( $args->seqfile );

    $readbuf = $args->readbuf;
    
    $ifh = &Common::File::get_read_handle( $args->seqfile );
    $ofh = &Common::File::get_write_handle( $args->tabfile );

    $otu = 0;

    $ofh->print("# seq_id\totu\torg_taxon\torg_def\n");

    no strict "refs";
            
    while ( $seqs = $reader->( $ifh, $readbuf ) )
    {
        use strict "refs";

        @rows = ();
        
        foreach $seq ( @{ $seqs } )
        {
            $otu += 1;
            
            # Create a "k__; p__; c__; o__; f__; g__; s__" style taxonomy string,

            $tax_str = &Install::Import::parse_silva_taxstr( $seq->{"info"} );

            if ( $tax_str )
            {
                $def_str = ( split "; ", $tax_str )[-1];
                
                # Add row,
                
                push @rows, ( join "\t", ( $seq->{"id"}, $otu, $tax_str // "", $def_str // "" ) ) ."\n";
            } 
            # 
            # Will return empty for eukaryotes for now, so took this out
            # else {
            #     push @{ $bads }, $seq->{"id"};
            # }
        }
        
        $ofh->print( @rows );
        
        $count += scalar @rows;
    }

    &Common::File::close_handle( $ofh );
    &Common::File::close_handle( $ifh );
    
    return $count;
}

sub uninstall_genomes_ebi
{
    # Niels Larsen, August 2010.

    # Uninstalls a given set of genomes from EBI. 

    my ( $db, 
         $args,
         $msgs,
        ) = @_;
    
    my ( $ebi_yaml, $ebi_table, @ebi_list, $ebi, %done, $ins_dir, $src_dir,
         $silent, $count, $conf, $tax_id, $org_name, $done, $ebi_file, $url,
         $ebi_text, $count_all );

    $silent = $args->silent;

    &echo( "   Uninstalling ". $db->title ." ... " ) unless $silent;

    $conf = &Install::Profile::create_install_config( $db );
    
    {
        local $Common::Messages::silent;
        
        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        if ( defined $args->indent ) {
            $Common::Messages::indent_plain = $args->indent;
        } else {
            $Common::Messages::indent_plain = 3;
        }

        &echo( "\n" );

        # Get organism list, remotely if missing,

        $ebi_yaml = $conf->dat_dir ."/". $db->name .".yaml";
        $ebi_table = &Common::Names::replace_suffix( $ebi_yaml, ".table" );

        if ( -r $ebi_yaml )
        {        
            &echo( qq (   Reading EBI descriptions list ... ) );
            @ebi_list = @{ &Common::File::read_yaml( $ebi_yaml ) };
            &echo_green_number( scalar @ebi_list );
        }
        elsif ( $args->force or $args->download ) 
        {
            &echo( qq (   Downloading EBI descriptions list ... ) );

            $ebi_file = $conf->dat_dir ."/". $db->name .".table";
            &Common::File::delete_file_if_exists( $ebi_file );

            $url = $db->downloads->baseurl;
            $url = &Common::Names::replace_suffix( $url, ".details.txt" );
        
            &Common::Storage::fetch_files_curl( $url, $ebi_file );
        
            $ebi_text = ${ &Common::File::read_file( $ebi_file ) };
            @ebi_list = &Install::Download::parse_ebi_genomes_list( $ebi_text );

            &Common::File::delete_file( $ebi_file );
            &Common::File::write_yaml( $ebi_yaml, [ \@ebi_list ] );

            &echo_green_number( scalar @ebi_list );
        } 
        else
        {
            &echo( qq (   No EBI descriptions list ... ) );
            @ebi_list = ();
            &echo_green( "ok\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> GENOME BY GENOME <<<<<<<<<<<<<<<<<<<<<<<<<<

        $count_all = 0;

        foreach $ebi ( @ebi_list )
        {
            bless $ebi, "Common::Obj";

            $tax_id = $ebi->org_taxid;

            $src_dir = $conf->src_dir ."/$tax_id";
            $ins_dir = $conf->ins_dir ."/$tax_id";

            next if $done{ $tax_id };
            
            if ( $args->download ) {
                &echo( "   Deleting ". $ebi->description ." ... " );
            } else {
                &echo( "   Uninstalling ". $ebi->description ." ... " );
            }
            
            $count = 0;
            
            if ( -r $ins_dir ) {
                $count += &Common::File::delete_dir_tree( $ins_dir );
            }
            
            if ( $args->download and -r $src_dir ) {
                $count += &Common::File::delete_dir_tree( $src_dir );
            }
            
            $done{ $tax_id } = 1;
            $count_all += 1 if $count > 0;

            if ( $count > 0 ) {
                &echo_green( "$count files\n" );
            } else {
                &echo_yellow( "none\n" );
            }
        }
        
        # Delete EBI list,

        if ( $args->download )
        {
            &Common::File::delete_file_if_exists( $ebi_yaml );
            &Common::File::delete_file_if_exists( $ebi_table );
        }

        # Delete main directories if empty,

        &Common::File::delete_dir_if_empty( $conf->ins_dir );
        &Common::File::delete_dir_if_empty( $conf->src_dir );
        &Common::File::delete_dir_if_empty( $conf->dat_dir );

        # Unregister,

        if ( $args->install )
        {
            &echo( qq (   Unregistering ... ) );
            $done = Registry::Register->unregister_datasets( $db->name );
            
            if ( $done ) {
                &echo_green( "done\n" );
            } else {
                &echo_yellow( "not registered\n" );
            }
        }

        &echo("");
    }

    if ( $count_all > 0 ) {
        &echo_green( "$count_all\n" ) unless $silent;    
    } else {
        &echo_yellow( "none\n" ) unless $silent;    
    }

    return ( $count, 0 );
}

sub print_mask_map
{
    # Niels Larsen, June 2013. 

    # Prints a signature table with four columns: number of sequences, number 
    # of signature oligos, node/sequence id and taxonomic group name. It is 
    # sorted by taxonomy group name and all sequences and higher groups are 
    # included, but only once. The purpose is debugging only. 

    my ( $conf,    # Configuration hash
         $tree,
         $sids,
         $ofile,
        ) = @_;

    # Returns nothing.
    
    my ( $formatter, $ofh, $buffer, $printer, $dbh );

    # >>>>>>>>>>>>>>>>>>>>>> TAXONOMY FORMAT ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<

    $formatter = sub
    {
        my ( $tree,
             $nid,
             $sid,
            ) = @_;
        
        my ( $str, $pid );
        
        $str = $tree->{ $nid }->[OTU_NAME];
        
        while ( defined ( $pid = $tree->{ $nid }->[PARENT_ID] ) )
        {
            $str = $tree->{ $pid }->[OTU_NAME] ."; $str";
            $nid = $pid;
        }

        $str .= "; $sid" if $sid;
        
        return $str;
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OPEN HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::File::delete_file_if_exists( $ofile );
    $ofh = &Common::File::get_write_handle( $ofile );

    $buffer = ${ &Common::Util_C::new_array( 4 ** $conf->wordlen, "uint" ) };

    $printer = sub
    {
        my ( $tree,
             $nid,
             $sids,
            ) = @_;

        my ( $node, $nodes, $seqtot, $oliref, $olitot, $taxstr, $sid );

        $node = &Common::DBM::get_struct( $dbh, $nid );
        $node->[OLI_MASK] = &Compress::LZ4::uncompress( $node->[OLI_MASK] );

        $seqtot = $node->[SEQ_TOTAL];

        $oliref = &Seq::Oligos::olis_from_mask( \$node->[OLI_MASK], \$buffer );
        $olitot = ( length ${ $oliref } ) / 4;

        $taxstr = $formatter->( $tree, $nid );
        $ofh->print("$seqtot\t$olitot\t$nid\t$taxstr\n");

        if ( $sids->{ $nid } )
        {
            $nodes = &Common::DBM::get_struct_bulk( $dbh, $sids->{ $nid } );

            map { $_->[OLI_MASK] = &Compress::LZ4::uncompress( $_->[OLI_MASK] ) } values %{ $nodes };

            # if ( $nid eq "tax_338" ) {
            #    &dump( $nodes );
            # }

            foreach $sid ( keys %{ $nodes } )
            {
                $node = $nodes->{ $sid };
                
                $oliref = &Seq::Oligos::olis_from_mask( \$node->[OLI_MASK], \$buffer );
                $olitot = ( length ${ $oliref } ) / 4;

                $taxstr = $formatter->( $tree, $nid, $sid );
                $ofh->print("1\t$olitot\t$nid\t$taxstr\n");
            }
        }
    };

    $dbh = &Common::DBM::read_open( $conf->tmp_file );

    &Taxonomy::Tree::traverse_tail( $tree, $Root_id, $printer, [ $sids ] );
    
    &Common::File::close_handle( $ofh );
    &Common::DBM::close( $dbh );

    # Sort the file,

    &Common::OS::run3_command("sort -k 4 -f $ofile > $ofile.tmp");
    &Common::File::rename_file( "$ofile.tmp", $ofile );

    return;
}

sub debug_tax
{
    my ( $tmp_dbh,
         $consrat,
         $olidim,
         $taxid1,
         $taxid2,
        ) = @_;
    
    my ( $n1, $n2, $p1, $p2, $n_mref, $p_mref, $o_mref, $o_olis, $olis );

    $n1 = &Common::DBM::get_struct( $tmp_dbh, $taxid1 );
    $n2 = &Common::DBM::get_struct( $tmp_dbh, $taxid2 );
    $p1 = &Common::DBM::get_struct( $tmp_dbh, $n1->[PARENT_ID] );
    $p2 = &Common::DBM::get_struct( $tmp_dbh, $n2->[PARENT_ID] );

    $n1->[OLI_SUMS] = &Compress::LZ4::uncompress( $n1->[OLI_SUMS] );
    $n2->[OLI_SUMS] = &Compress::LZ4::uncompress( $n2->[OLI_SUMS] );
    $p1->[OLI_SUMS] = &Compress::LZ4::uncompress( $p1->[OLI_SUMS] );
    $p2->[OLI_SUMS] = &Compress::LZ4::uncompress( $p2->[OLI_SUMS] );
    
    $n_mref = &Common::Util_C::new_array( $olidim, "char" );
    $p_mref = &Common::Util_C::new_array( $olidim, "char" );
    $o_mref = &Common::Util_C::new_array( $olidim, "char" );
    $o_olis = &Common::Util_C::new_array( $olidim, "uint" );

    $olis = &Install::Import::get_node_olis( $n1, $consrat, $n_mref, $n2, $p_mref, $o_mref, $o_olis );

    # $n_mref = &Common::Util_C::new_array( $olidim, "char" );
    # $p_mref = &Common::Util_C::new_array( $olidim, "char" );
    # $o_mref = &Common::Util_C::new_array( $olidim, "char" );
    # $o_olis = &Common::Util_C::new_array( $olidim, "uint" );

    # $olis = &Install::Import::get_node_olis( $n2, $consrat, $n_mref, $p2, $p_mref, $o_mref, $o_olis );
    # &dump( scalar ( unpack "V*", $olis ) );

    return;
}

sub format_taxon
{
    my ( $tree,
         $nid,
        ) = @_;

    my ( $str, $pid );
    
    $str = $tree->{ $nid }->[OTU_NAME];

    while ( defined ( $pid = $tree->{ $nid }->[PARENT_ID] ) )
    {
        $str = $tree->{ $pid }->[OTU_NAME] ."; $str";
        $nid = $pid;
    }
    
    return $str;
}

1;

__END__

    # # TEST

    # my @test_ids = keys %p_ids;

    # $tax_dbh = &Common::DBM::read_open( $conf->tax_file );
    # # $tmp_dbh = &Common::DBM::read_open( $tmp_file );

    # # &dump( \@test_ids );

    # $tree = {};
    # &Taxonomy::Tree::load_new_nodes( $tax_dbh, \@test_ids, $tree );

    # # $nodes = &Common::DBM::get_struct_bulk( $tmp_dbh, \@test_ids );
    
    # # &dump( scalar keys %{ $nodes } );
    # # foreach $node ( values %{ $nodes } ) {
    # #     $tree->{ $node->[NODE_ID] }->[OLI_MASK] = $node->[OLI_MASK];
    # # }

    # &Common::DBM::close( $tax_dbh );
    # # &Common::DBM::close( $tmp_dbh );

    # while (1) {};
    
    # # >>>>>>>>>>>>>>>>>>>> ADD HIGHER NODES TO STORAGE <<<<<<<<<<<<<<<<<<<<<<<<

    # # Convert the counts storage made above to a mask storage. Tree nodes with
    # # counts are read and masks set 1's where the oligo counts are near the 
    # # sequence total. 

    # &echo("   Node signature oligos ... ");

    # $tmp_dbh = &Common::DBM::write_open( $conf->tmp_file );

    # &Common::File::delete_file_if_exists( $conf->oli_file ) if $clobber;
    # $oli_dbh = &Common::DBM::write_open( $conf->oli_file, "params" => $params );

    # while ( %p_ids )
    # {
    #     %next_ids = ();

    #     # >>>>>>>>>>>>>>>>>>>>>>>>> LOAD PARENT NODES <<<<<<<<<<<<<<<<<<<<<<<<<

    #     $p_nodes = &Common::DBM::get_struct_bulk( $tmp_dbh, [ keys %p_ids ], 0 );

    #     foreach $p_node ( values %{ $p_nodes } )
    #     {
    #         $p_node->[OLI_MASK] = &Compress::LZ4::uncompress( $p_node->[OLI_MASK] );
    #     }

    #     foreach $p_node ( values %{ $p_nodes } )
    #     {
    #         # >>>>>>>>>>>>>>>>>>>>>> LOAD CHILD NODES <<<<<<<<<<<<<<<<<<<<<<<<<

    #         $nodes = &Common::DBM::get_struct_bulk( $tmp_dbh, $p_node->[CHILD_IDS] );

    #         foreach $node ( values %{ $nodes } )
    #         {
    #             $node->[OLI_MASK] = &Compress::LZ4::uncompress( $node->[OLI_MASK] );
    #             # $p_node->[SEQ_TOTAL] += $node->[SEQ_TOTAL];
    #         }

    #         if ( scalar @{ $p_node->[CHILD_IDS] } > 1 )
    #         {
    #             # >>>>>>>>>>>>>>>>>>>> MULTIPLE CHILDREN <<<<<<<<<<<<<<<<<<<<<<

    #             # Create list of masks from sister nodes and create a mask
    #             # ($uintmask) with oligos that are conserved among them,

    #             $masks = [ map { $_->[OLI_MASK] } values %{ $nodes } ];

    #             &Common::Util_C::set_mem( $uintbuf, length $uintbuf );
    #             &Seq::Oligos::mask_conservation( $masks, $grpcons, \$uintmask, \$uintbuf, "uint" );

    #             # Overwrite or set the parent mask,

    #             $p_node->[OLI_MASK] = $uintmask;

    #             # Finally subtract the parent mask from each child mask, so 
    #             # only non-conserved oligos remain in the children,

    #             foreach $node ( values %{ $nodes } )
    #             {
    #                 # 1's present in the second argument are used to unset those
    #                 # in first argument. The result is written to the third 
    #                 # argument,

    #                 &Seq::Oligos::mask_operation( \$node->[OLI_MASK], \$p_node->[OLI_MASK], \$node->[OLI_MASK], "del" );
    #             }

    #             # Compress and store the child nodes back,

    #             foreach $node ( values %{ $nodes } )
    #             {
    #                 $node->[OLI_MASK] = &Compress::LZ4::compress( $node->[OLI_MASK] );
    #             }
                
    #             &Common::DBM::put_struct_bulk( $tmp_dbh, $nodes );
    #         }
    #         else
    #         {
    #             # >>>>>>>>>>>>>>>>>>>>>> SINGLE CHILD <<<<<<<<<<<<<<<<<<<<<<<<<
                
    #             # Parent inherits mask from the child node, unchanged. (TODO: 
    #             # find conservation at a higher level)

    #             $p_node->[OLI_MASK] = $nodes->{ $p_node->[CHILD_IDS]->[0] }->[OLI_MASK];
    #         }

    #         # >>>>>>>>>>>>>>>>>>>>>>>>> SAVE OLIGOS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    #         %save = ();
            
    #         foreach $node ( values %{ $nodes } )
    #         {
    #             $oliref = &Seq::Oligos::olis_from_mask( \$node->[OLI_MASK], \$uintbuf );
    #             $save{ $node->[NODE_ID] } = ${ $oliref };
    #         }

    #         &Common::DBM::put_struct_bulk( $oli_dbh, \%save );
                
    #         # Save parent ids for next round,

    #         if ( defined $p_node->[PARENT_ID] ) {
    #             push @{ $next_ids{ $p_node->[PARENT_ID] } }, $p_node->[NODE_ID];
    #         }
    #     }

    #     # >>>>>>>>>>>>>>>>>>>>>>>> SAVE PARENT NODES <<<<<<<<<<<<<<<<<<<<<<<<<<

    #     foreach $p_node ( values %{ $p_nodes } ) {
    #         $p_node->[OLI_MASK] = &Compress::LZ4::compress( $p_node->[OLI_MASK] );
    #     }
                
    #     &Common::DBM::put_struct_bulk( $tmp_dbh, $p_nodes );

    #     %p_ids = %next_ids;
    # }

    # &Common::DBM::close( $oli_dbh );
    # &Common::DBM::close( $tmp_dbh );

    # &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SUMMING ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # $sum_sub = sub
    # {
    #     # Set counts and totals for the remaining higher level tree nodes, by 
    #     # accumulating those set above for immediate leaf parents. When done, the
    #     # oligo sum string (OLI_SUMS) for a given node will hold totals for all 
    #     # sequences in the subtree that the node spans. The total number of 
    #     # sequences (SEQ_TOTAL) is also saved. The SEQ_TOTAL at the root node 
    #     # will be the number of sequences in the file read above.
        
    #     my ( $tree, $nid, $nulref, $olidim ) = @_;

    #     my ( $node, $p_node );

    #     $node = $tree->{ $nid };

    #     if ( @{ $node->[CHILD_IDS] } and defined $node->[PARENT_ID] )
    #     {
    #         $p_node = $tree->{ $node->[PARENT_ID] };

    #         if ( exists $p_node->[OLI_SUMS] ) {
    #             &Common::Util_C::add_arrays_uint( $p_node->[OLI_SUMS], $node->[OLI_SUMS], $olidim );
    #         } else {
    #             $p_node->[OLI_SUMS] = $node->[OLI_SUMS];
    #         }

    #         $p_node->[SEQ_TOTAL] += $node->[SEQ_TOTAL] // 0;
    #     }
    # };
    
    # $sum_args = [ \$nullmap, $olidim ];
    
    # # Counting files,

    # &echo("   Counting output files ... " );

    # $counts = &Seq::Stats::count_seq_files({ "files" => [ map { "$odir/$_" } keys %{ $exports } ] });
    # &echo_done("done\n");
    
    # foreach $count ( @{ $counts } )
    # {
    #     push @list, [ &Common::Util::commify_number( $count->{"seq_count"} ),
    #                   &Common::Util::commify_number( $count->{"seq_length_average"} ),
    #                   $count->{"seq_file"} ];
    # }

    # $table = &Common::Table::new( \@list, {"col_headers" => ["Sequences", "Length", "File path"] });
    # &dump( $table );

    # print Common::Tables->render_list( $table, {"header" => 1, "align" => 1, "fields" => join ",", @{ $table->col_headers } } );
    

# sub find_silva_ref_aseq
# {
#     my ( $args,
#         ) = @_;

#     my ( $path, $id, $fh, $file, $aseq );

#     $path = $args->odir ."/". $args->seqid;

#     if ( -r $path )
#     {
#         $aseq = &Common::File::retrieve_file( $path );
#     }
#     else
#     {
#         $fh = new IO::File;
#         $file = $args->ifile;

#         if ( not $fh->open("tar -xzOf $file |") ) {
#             &Common::Messages::error( qq (Could not tar-read-open "$file") );
#         }

#         $aseq = &Ali::Convert::get_ref_seq(
#             {
#                 "file" => $fh,
#                 "readbuf" => $args->readbuf,
#                 "seqid" => $args->seqid,
#                 "format" => "fasta_wrapped",
#             });
        
#         &Common::File::close_handle( $fh );
#         &Common::File::store_file( $path, $aseq );
#     }
    
#     return $aseq;
# }
    
# sub create_green_seqs_old
# {
#     # Niels Larsen, September 2012. 

#     # Splits greengenes sequence file into taxonomy and sequences. No sub-
#     # sequences are written, as Greengenes does not distribute alignments yet.

#     my ( $db,       # Dataset name or object
#          $args,     # Arguments hash
#         ) = @_;

#     my ( $defs, $conf, $src_newest, $ref_mol, $mol_conf, $prefix, $suffix,
#          $seq_suffix, $tax_table, $tax_index, $odir, $count,
#          @bads, $header, $text, $run_start, $seq_file, @ofiles, $read_buf,
#          $idir, $ifile, $reader, $ifh, $ofh, $seqs, $tax_ids,
#          $tids_str );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $defs = {
#         "indir" => undef,
#         "outdir" => undef,
#         "recipe" => undef,
#         "readbuf" => 1000,
#         "clobber" => 0,
#         "silent" => 0,
#         "header" => 1,
#     };
    
#     $args = &Registry::Args::create( $args, $defs );
#     $conf = &Install::Import::create_green_seqs_args( $db, $args );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo("   Configuring internal settings ... ");

#     $src_newest = &Common::File::get_newest_file( $conf->indir )->{"path"};
    
#     $idir = $conf->indir;
#     $odir = $conf->outdir;

#     $ref_mol = "SSU";
#     $mol_conf = $Taxonomy::Config::DBs{"Green"}{ $ref_mol };

#     $prefix = $mol_conf->prefix;
#     $suffix = $mol_conf->dbm_suffix;

#     $seq_suffix = $mol_conf->seq_suffix;

#     $tax_table = "$odir/$prefix$ref_mol". $mol_conf->tab_suffix;
#     $tax_index = "$tax_table$suffix";

#     $seq_file = "$odir/$prefix$ref_mol"."_all". $mol_conf->seq_suffix;

#     $run_start = time();
#     $read_buf = $conf->readbuf;

#     &echo_done("done\n");

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> HELP MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo_bold("\nGreengenes installation:\n") if $header;

#     $text = qq (
#       Sequences and taxonomy strings are now being written to files 
#       and indexed. Taxonomy strings are verified and converted to a 
#       database neutral format. See the installation directory

#       $odir

# );
#     &echo_yellow( $text );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo("   Is sequence file current ... ");
    
#     if ( -r $seq_file and not &Common::File::is_newer_than( $src_newest, $seq_file ) )
#     {
#         &echo_done("yes\n");
#     }
#     else
#     {
#         &echo_done("no\n");
#         &echo("   Writing sequence file ... ");
        
#         $ifile = &Common::File::list_files( $idir, '.fasta.gz' )->[0]->{"path"};

#         $reader = &Seq::IO::get_read_routine( $ifile );
#         $ifh = &Common::File::get_read_handle( $ifile );

#         &Common::File::delete_file_if_exists( $seq_file );
#         $ofh = &Common::File::get_write_handle( $seq_file );

#         $count = 0;

#         no strict "refs";

#         while ( $seqs = $reader->( $ifh, $read_buf ) )
#         {
#             use strict "refs";

#             map { delete $_->{"info"} } @{ $seqs };

#             &Seq::IO::write_seqs_fasta( $ofh, $seqs );

#             $count += scalar @{ $seqs };
#         }

#         &Common::File::close_handle( $ofh );
#         &Common::File::close_handle( $ifh );

#         &echo_done("$count rows\n");
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Create a table with key/value store of taxonomy string with organism name 
#     # for each sequence. Below we use this as source of taxonomy strings.

#     &echo("   Is taxonomy table current ... ");

#     if ( -r $tax_table and not &Common::File::is_newer_than( $src_newest, $tax_table ) )
#     {
#         &echo_done("yes\n");
#     }
#     else
#     {
#         &echo_done("no\n");
#         &echo("   Creating taxonomy table ... ");
        
#         &Common::File::delete_file_if_exists( $tax_table );
#         &Common::File::delete_file_if_exists( "$tax_table.bad_names" );

#         $count = &Install::Import::tablify_taxa_green({
#             "seqfile" => $conf->seq_file,
#             "tabfile" => $tax_table,
#             "readbuf" => 1000,
#         }, \@bads );
        
#         if ( @bads ) {
#             &Common::File::write_file("$tax_table.bad_names", \@bads );
#         }

#         &echo_done("$count rows\n");
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>> TAXONOMY TABLE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Create a key/value store of taxonomy string with organism name for each
#     # sequence. Below we use this as source of taxonomy strings.

#     if ( not -r $tax_index or &Common::File::is_newer_than( $src_newest, $tax_index ) )
#     {
#         &echo("   Indexing taxonomy table ... ");
        
#         &Install::Import::index_tax_table(
#              $tax_table, 
#              {
#                  "keycol" => 0,         # Sequence id
#                  "valcol" => 4,         # Taxonomy string with org name
#                  "suffix" => $suffix,   # Kyoto cabinet file suffix
#              });
        
#         &echo_done("done\n");
#     }

#     if ( $header )
#     {
#         &echo("   Time: ");
#         &echo_info( &Time::Duration::duration( time() - $run_start ) ."\n" );
#     }

#     &echo_bold("\nFinished\n\n") if $header;

#     @ofiles = &Common::File::list_files( $odir, '.fasta$' );

#     return ( scalar @ofiles, undef );

#     return;
# }

# sub create_green_seqs_args_old
# {
#     # Niels Larsen, June 2012.

#     # Creates a config object from the script input arguments. 

#     my ( $db,
#          $args,
#         ) = @_;

#     # Returns object.

#     my ( @msgs, %args, @ofiles, $indir, @ifiles, $key, $val, $prefix, $suffix );

#     $db = Registry::Get->dataset( $db );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     if ( $args{"indir"} = $args->indir )
#     {
#         $indir = $args{"indir"};
#         &Common::File::check_files( [ $indir ], "d", \@msgs );
#     }
#     else {
#         $indir = $db->datapath_full ."/Sources";
#     }

#     if ( @ifiles = &Common::File::full_file_paths( ["$indir/*unaligned.fasta.gz"] ) ) {
#         $args{"seq_file"} = $ifiles[0];
#     } else {
#         push @msgs, ["ERROR", qq (Input sequence file not found -> "$indir/*.fasta.gz") ];
#     }
    
#     #if ( @ifiles = &Common::File::full_file_paths( ["$indir/gg_*.fasta.gz"] ) ) {
#     #    $args{"seq_file"} = $ifiles[0];
#     #} else {
#     #    push @msgs, ["ERROR", qq (Input sequence file not found -> "$indir/gg_*.fasta.gz") ];
#     #}
    
#     # if ( @ifiles = &Common::File::full_file_paths( ["$indir/gg_*_taxonomy.txt.gz"] ) ) {
#     #     $args{"tax_file"} = $ifiles[0];
#     # } else {
#     #     push @msgs, ["ERROR", qq (Input taxonomy file not found -> "$indir/gg_*_taxonomy.txt.gz") ];
#     # }
    
#     $args{"indir"} = $indir;

#     &append_or_exit( \@msgs );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Directory,

#     if ( not $args{"outdir"} ) {
#         $args{"outdir"} = $db->datapath_full ."/Installs";
#     }

#     # Switches,

#     $args{"readbuf"} = $args->readbuf;
#     $args{"clobber"} = $args->clobber;
#     $args{"header"} = $args->header;

#     bless \%args;

#     return wantarray ? %args : \%args;
# }

# sub tablify_taxa_green_old
# {
#     # Niels Larsen, September 2012. 

#     # Writes a table from the Greengenes fasta formatted unaligned sequence
#     # distribution file and taxonomy tables. The columns are,
#     # 
#     # Sequence ID
#     # OTU running number
#     # OTU Greengenes number  (empty for now)
#     # Genbank accession
#     # Organism taxonomy with organism name
#     # Organism name, free format
#     # 
#     # The k__, p__ etc prefixes are kept, as they provide anchor points used
#     # in taxonomy mapping of similarities. RDP taxonomy strings are converted
#     # to this form too, inconsistencies allowing.

#     my ( $args,
#          $bads,
#         ) = @_;

#     # Returns a list. 

#     my ( $defs, $seqs, $seq, $readbuf, $ofh, $ifh, $otu, $reader, @rows, 
#          $count, $info );

#     $defs = {
#         "readbuf" => 10_000,
#         "seqfile" => undef,
#         "taxfile" => undef,
#         "tabfile" => undef,
#     };

#     $args = &Registry::Args::create( $args, $defs );
#     $bads //= [];

#     $reader = &Seq::IO::get_read_routine( $args->seqfile );
#     $readbuf = $args->readbuf;
    
#     $ifh = &Common::File::get_read_handle( $args->seqfile );
#     $ofh = &Common::File::get_write_handle( $args->tabfile );

#     $otu = 0;

#     $ofh->print("# seq_id\totu\tgg_otu\tgb_acc\torg_taxon\torg_name\n");

#     no strict "refs";
            
#     while ( $seqs = $reader->( $ifh, $readbuf ) )
#     {
#         use strict "refs";

#         @rows = ();
        
#         foreach $seq ( @{ $seqs } )
#         {
#             $otu += 1;
            
#             $info = &Install::Import::parse_green_header( $seq->{"info"} );

#             if ( $info )
#             {
#                 push @rows, ( join "\t",
#                               ( $seq->{"id"},
#                                 $otu,
#                                 $info->{"gg_otu"}, 
#                                 $info->{"gb_acc"} // "",
#                                 $info->{"org_taxon"} ."; n__". ( $info->{"org_name"} // "" ),
#                                 $info->{"org_name"} // "",
#                               ) ) ."\n";
#             }
#             else {
#                 push @{ $bads }, $seq->{"id"} ."\t". $seq->{"info"} ."\n";
#             }
#         }
        
#         $ofh->print( @rows );
        
#         $count += scalar @rows;
#     }

#     &Common::File::close_handle( $ofh );
#     &Common::File::close_handle( $ifh );
    
#     return $count;
# }
