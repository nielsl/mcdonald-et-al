package RNA::Import;     #  -*- perl -*-

# Routines that import RNA sequences and alignments and other RNA related
# data. The import includes reading different formats, writing annotation 
# to tables and loading of RNA database. It supplies the driving routines
# to the import_rna script. 

use strict;
use warnings FATAL => qw ( all );

use Cwd;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &check_arguments
                 &import_mir_pre_alis
                 &import_mir_flanks
                 &import_seqs_missing
                 &import_ssu_embl
                 &import_ssu_ludwig
                 &import_ssu_rdp
                 &parse_pairmask
                 &parse_pairmask_generic
                 &parse_pairmask_zwieb
                 &stem_length_difference
                 &stem_position_shift
                 );

{
    local $SIG{__DIE__} = undef;
    require Bio::SeqIO;
}

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;
use Common::DB;
use Common::Names;

use Registry::Get;

use Seq::Import;
use RNA::DB;
use Ali::DB;

use Seq::IO;

use Ali::Patterns;
use Ali::Import;
use Ali::IO;
use Ali::Common;

use Taxonomy::DB;
use Taxonomy::Stats;

use Registry::Register;

use base qw ( Ali::Import );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_arguments
{
    # Niels Larsen, December 2004.    UNFINISHED

    # Validates the arguments needed by the import_rna routine. 
    # If errors found, program stops here. 

    my ( $cl_args,    # Command line argument hash
         ) = @_;

    # Returns a hash. 

    # >>>>>>>>>>>>>>>>>>>>> CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<

    my ( @errors, $error, $dir );

    # The tables input directory: if given, expand to absolute path 
    # and check that its readable. If given without argument set it 
    # to default location according to type,

    if ( $cl_args->{"tables"} )
    {
        $cl_args->{"tables"} = &Cwd::abs_path( $cl_args->{"tables"} );        

        if ( not -r $cl_args->{"tables"} ) {
            push @errors, qq (Tables directory not found -> "$cl_args->{'tables'}");
        }
    }
    elsif ( defined $cl_args->{"tables"} )
    {
        $cl_args->{"tables"} = qq ($Common::Config::rna_dir/$cl_args->{"type"}/Outputs);
    }

    # If no input directories or files given, complain,

    if ( not $cl_args->{"tables"} and not $cl_args->{"gff"} )
    {
        push @errors, qq (No GFF file or table directory given);
    }

    # Print errors if any and exit,

    if ( @errors )
    {
        foreach $error ( @errors )
        {
            &echo_red( "ERROR: ");
            &echo( "$error\n" );
        }
        
        exit;
    }
    else {
        wantarray ? return %{ $cl_args } : return $cl_args;
    }
}

sub import_mir_pre_alis
{
    # Niels Larsen, April 2006.

    # Reads a Stockholm formatted file of mir-entries and writes a directory 
    # of PDL formatted alignments. Sets datatype, converts sequence to RNA 
    # and shortens title. Returns the number of alignment files written.

    my ( $src_file,         # Stockholm file
         $dst_dir,          # Alignment directory 
         $readonly,         # Readonly flag
         $msgs,             # Messages - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( $src_fh, $ft_types, $ali, $title, $ofile, $count );

    $src_fh = &Common::File::get_read_handle( $src_file );

    $count = 0;

    if ( not $readonly )
    {
        &Common::File::create_dir_if_not_exists( $dst_dir );
    }

    while ( defined ( $ali = Ali::Import->read_stockholm_entry( $src_fh ) ) )
    {
        $ali->datatype( "rna_ali" );
        $ali->file( "$dst_dir/". $ali->sid ."_pre.pdl" );
        $ali->sid( $ali->sid ."_pre" );
        
        $ali = &Ali::Common::to_rna( $ali );
        $ali = &Ali::Common::replace_char( $ali );
        $ali = &Ali::Common::pdlify( $ali );
        
        # Shorten title so it doesnt push menus too much to the right,

        $title = $ali->title;
            
        if ( $title =~ /microRNA\s*precursor(\s*family)?/i ) {
            $title =~ s/\s*microRNA\s*precursor(\s*family)?\s*//i;
        } else {
            push @{ $msgs }, [ "Warning", qq (Unusual title -> "$title") ];
        }
        
        $ali->title( "$title family" );
        
        if ( not $readonly ) 
        {
            $ali->write( &Common::Names::strip_suffix( $ali->file ) );
            $count += 1;
        }
    }

    &Common::File::close_handle( $src_fh );

    return $count;
}

sub import_mir_flanks
{
    # Niels Larsen, September 2005.

    # Extracts miRNA from Rfam sources, adds genomic neighborhoods, extracts
    # common patterns from alignments and loads a number of features. Each step
    # is done only when needed, as judged from file dates.

    my ( $regdb,       # Registry item
         $args,        # Arguments and settings
         $msgs,        # Message list
         ) = @_;

    # Returns integer.

    my ( $entries, $flank_width, $main_dir, $down_dir, $tab_dir, $tmp_dir, 
         $ins_dir, $db, $rfam_dir, $src_dir, $src_file, $params, $path, 
         $seq_dir, $readonly, $mirbase_dir, @src_files, @dst_files, $count,
         $counter, $dst_dir, $dst_file, @new_files, $newest_file, @entries,
         @seq_ids, $name, $prefix, $ft_menu );

    require Bio::Seq::RichSeq;
    require Bio::Species;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $flank_width = 2000;

    $main_dir = $args->{"dat_dir"};
    $down_dir = $args->{"src_dir"};
    $tab_dir = $args->{"tab_dir"};
    $tmp_dir = $args->{"tmp_dir"};
    $ins_dir = $args->{"ins_dir"};

    $db = Registry::Get->dataset( "dna_seq_cache" ); 
    $Common::Config::dna_seq_cache_dir = "$Common::Config::dat_dir/". $db->datapath;

    $db = Registry::Get->dataset( "rna_ali_rfam" );
    $rfam_dir = "$Common::Config::dat_dir/". $db->datapath;

    $path = Registry::menu->type("rna_seq")->path ."/". $regdb->datadir;
    $seq_dir = "$Common::Config::dat_dir/$path/Installs";

    $counter = 0;
    $msgs = [];

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE SOURCE FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Extract all alignments with IDs "mir-*" from the Rfam source file and put 
    # the entries under the miRBase sources,

    $src_file = "$rfam_dir/Downloads/Rfam.full.gz";
    $dst_file = "$down_dir/Rfam_alis.stockholm";

    if ( not -r $src_file )
    {
        &error( qq (Rfam source file is not found. Please)
                                . qq ( download Rfam with the download_rna script.) );
    }
    
    if ( not -r $dst_file or &Common::File::is_newer_than( $src_file, $dst_file ) )
    {
        &echo( qq (   Extracting mir-entries from Rfam ... ) );
        
        &Ali::Import::copy_stockholm_entries( $src_file, $dst_file, [ "mir-.+" ] );
        &echo_green( "done\n" );
        
        $counter += 1;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE PRECURSORS IN PDL <<<<<<<<<<<<<<<<<<<<<<<<

    # If the miRNA alignment source file is newer than any of the PDL files,
    # recreate all corresponding alignments,

    $src_file = "$down_dir/Rfam_alis.stockholm";
    $dst_dir = $ins_dir;

    &Common::File::create_dir_if_not_exists( $dst_dir ) if not $readonly;

    @dst_files = &Common::File::list_files( $dst_dir, '_pre\.pdl$' );

    if ( @dst_files ) {
        $newest_file = &Common::File::get_newest_file( $dst_dir )->{"path"};
    } else {
        $newest_file = "";
    }
    
    if ( not $newest_file or &Common::File::is_newer_than( $src_file, $newest_file ) )
    {
        &echo( qq (   Writing precursor PDL alignments ... ) );

        $count = &RNA::Import::import_mir_pre_alis( $src_file, $dst_dir, $readonly, $msgs );
        &echo_green( "done\n" );

        $counter += $count || 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE PRECURSORS IN FASTA <<<<<<<<<<<<<<<<<<<<<<
    
    # Saves sequence-only versions (with suffix ".fasta") of the precursor 
    # alignments in a directory defined above,
    
    $dst_dir = $seq_dir;
    @src_files = &Common::File::list_files( $ins_dir, '_pre\.pdl$' );

    &Common::File::create_dir_if_not_exists( $dst_dir );

    @dst_files = &Common::File::list_files( $dst_dir, '_pre\.fasta$' );

    if ( @src_files = &Ali::Import::needs_update( \@src_files, \@dst_files ) )
    {
        &echo( qq (   Writing precursor fasta sequences ... ) );
        
        Ali::Import->write_fasta_seq_files( \@src_files, $dst_dir, $msgs );
        &echo_green( "done\n" );

        $counter += scalar @src_files;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE PRECURSOR PATTERNS <<<<<<<<<<<<<<<<<<<<<<<<<

    # Extracts a scan_for_matches pattern from each precursor file and saves these
    # in a pattern directory defined above,

    @src_files = &Common::File::list_files( $ins_dir, '_pre\.pdl$' );
    @dst_files = &Common::File::list_files( $ins_dir, '_pre\.pattern$' );
    
    $dst_dir = $ins_dir;

    if ( @src_files = &Ali::Import::needs_update( \@src_files, \@dst_files ) )
    {
        &echo( qq (   Creating precursor patscan patterns ... ) );
        
        $params = 
        {
            "format" => "fasta",
            "min_seqs" => 90,
            "len_relax" => 30,
            "mis_relax" => 20,
            "ins_relax" => 10,
            "del_relax" => 10,
            "max_relax" => 40,
            "use_observed" => 1,
            "split_pair_rules" => 0,
            "low_cons_ends" => 0,
            "unpaired_ends" => 0,
            "readonly" => $readonly,
        };
        
        &Ali::Patterns::create_pattern_files( \@src_files, $dst_dir, $params, $msgs );

        &echo_green( "done\n" );

        $counter += scalar @src_files;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE EMBL ENTRY CACHE <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Fetch from NCBI all entries referred to by the alignments and save them in a
    # cache directory, 
    
    &echo( qq (   Updating sequence cache (patience) ... ) );

#    $dst_dir = $Common::Config::dna_seq_cache_dir;
#    &Common::File::create_dir_if_not_exists( $dst_dir );

    @src_files = &Common::File::list_files( $ins_dir, '_pre\.pdl$' );

    @seq_ids = Ali::Import->read_seq_ids( \@src_files );
    @seq_ids = map { $_ =~ s/\/.*$//; $_ } @seq_ids;

#    &dump( "before accs_to_gis" );
#    @seq_ids = &Common::Entrez::accs_to_gis( \@seq_ids, "dna_seq", $msgs );

#    &Common::File::dump_file( "$Common::Config::tmp_dir/seq_ids.dump", \@seq_ids );
#    &dump( \@seq_ids );
#    &dump( "after accs_to_gis" );

    @seq_ids = @{ &Common::File::eval_file( "$Common::Config::tmp_dir/seq_ids.dump" ) };
    $count = &Seq::Import::update_seq_cache( \@seq_ids, "dna_seq", $msgs );
    &dump( "after seq_cache" );

    if ( $count > 0 ) {
        &echo_green( "$count downloaded\n" );
    } else {
        &echo_green( "up to date\n" );
    }        

    $counter += $count || 0;

    # >>>>>>>>>>>>>>>>>>>>>> WRITE PRECURSOR + FLANK ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<

    # Writes alignments of precursors + genome flank regions added from EMBL,

    @src_files = &Common::File::list_files( $ins_dir, '_pre\.pdl$' );
    @dst_files = &Common::File::list_files( $ins_dir, '_flank\.pdl$' );

    $dst_dir = $ins_dir;
    
    if ( @new_files = &Ali::Import::needs_update( \@src_files, \@dst_files, '_(pre|flank)\.pdl$' ) )
    {
        &echo( qq (   Writing genomic flank alignments (patience) ... ) );

        $count = Ali::Import->write_rfam_genome_flanks( \@new_files, $dst_dir, 
                                                        $flank_width, $msgs );
        &echo_green( "done\n" );
        
        $counter += $count || 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>> WRITE PRECURSOR + FLANK SEQUENCES <<<<<<<<<<<<<<<<<<<<<
        
    # Saves sequence-only versions (with suffix ".fasta") of the precursor+flanks
    # alignments, 

    $dst_dir = $seq_dir;

    @src_files = &Common::File::list_files( $ins_dir, '_flank\.pdl$' );
    @dst_files = &Common::File::list_files( $dst_dir, '_flank\.fasta$' );

    if ( @new_files = &Ali::Import::needs_update( \@src_files, \@dst_files ) )
    {
        &echo( qq (   Writing genomic flank fasta sequences ... ) );

        $count = Ali::Import->write_fasta_seq_files( \@new_files, $dst_dir, $msgs );
        &echo_green( "done\n" );

        $counter += $count || 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE AND LOAD GENERIC FEATURES <<<<<<<<<<<<<<<<<<<<<

    # Update features if feature table files are missing or outdated,

    &Common::File::create_dir_if_not_exists( $tab_dir ) if not $readonly;

    @src_files = &Common::File::list_files( $ins_dir, '_flank\.pdl$' );
    @dst_files = &Common::File::list_files( $tab_dir );

    if ( @src_files = &Ali::Import::needs_update( \@src_files, \@dst_files ) )
    {
        &echo( qq (   Creating database features ... ) );

        $ft_menu = Registry::Get->features([
#                                              "ali_sid_text",
#                                              "ali_seq_cons",
#                                              "ali_rna_pairs",
#                                              "ali_pairs_covar",
#                                              "seq_pattern",
#                                              "seq_precursor",
#                                              "seq_mature",
                                              "seq_rnafold",
                                              ]);

        $ft_menu->set_options( "ali_rna_pairs", "title", "Precursor pairings" );

        $ft_menu->set_options( "seq_pattern", "title", "Precursor patterns" );
        $ft_menu->set_options( "seq_pattern", "ali_dir", $ins_dir );
        $ft_menu->set_options( "seq_pattern", "seq_dir", $seq_dir );
        $ft_menu->set_options( "seq_pattern", "routine", "create_features_mirna_patterns" );
        
        $ft_menu->set_options( "seq_precursor", "ali_dir", $ins_dir );
        $ft_menu->set_options( "seq_precursor", "seq_dir", $seq_dir );
        $ft_menu->set_options( "seq_precursor", "routine", "create_features_mirna_precursor" );
        
        $ft_menu->set_options( "seq_mature", "i_file", "$main_dir/Downloads/mature.fa" );
        $ft_menu->set_options( "seq_mature", "seq_dir", $seq_dir );
        $ft_menu->set_options( "seq_mature", "routine", "create_features_mirna_mature" );
        
        $ft_menu->set_options( "seq_rnafold", "title", "Hairpin potential" );
        $ft_menu->set_options( "seq_rnafold", "seq_dir", $seq_dir );
        $ft_menu->set_options( "seq_rnafold", "routine", "create_features_mirna_hairpin" );
        
        $ft_menu->set_options( "seq_mature", "selected", 1 );
        $ft_menu->set_options( "ali_rna_pairs", "selected", 1 );

#       @src_files = grep { $_->{"name"} eq "mir-1" } @src_files;

        $args->{"ft_menu"} = $ft_menu;

        $args->{"ft_source"} = $args->{"source"};
        $args->{"ali_source"} = $args->{"source"};
        
        &Ali::Import::import_features_alis( \@src_files, $args, $msgs );
    
        &echo_green( "done\n" );

        $counter += $count || 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $db = Registry::Get->dataset( "rna_ali_mir_flanks" );

    @dst_files = &Common::File::list_files( $ins_dir, '_flank\.pdl$' );
    $path = Registry::menu->type("rna_ali")->path ."/". $regdb->datadir;

    foreach $dst_file ( @dst_files )
    {
        $prefix = &Common::Names::strip_suffix( $dst_file->{"name" } );

        push @entries, {
            "name" => $prefix, 
            "title" => $prefix,
            "datatype" => "rna_ali",
            "datapath" => $path,
            "formats" => [ "pdl" ],
        };
    }

    Registry::Register->write_entries_list( \@entries, $main_dir );
    
    return $counter || 0;
}

sub import_ssu_ludwig
{
    # Niels Larsen, January 2006.

    # Reads the Ludwig/ARB RNA alignment(s) and creates alignment(s) 
    # in "raw" format.

    my ( $i_dir,       # Input directory
         $o_dir,       # Output directory
         $readonly,    # Command line arguments and settings
         $msgs,
         ) = @_;

    # Returns nothing. 

    my ( $files, $args, $src_dir, $ali_dir );

    $args->{"datatype"} = "rna_ali";
    $args->{"prefixes"} = [ "SSU_Ludwig" ];
    $args->{"titles"} = [ "Ludwig / ARB" ];
    $args->{"colbeg"} = 1000;
    $args->{"colend"} = 43300;

    $args->{"ft_menu"} = Registry::Get->features([
                                                    "ali_seq_cons",
                                                    ]);
    $src_dir = "$i_dir/Downloads";
    $ali_dir = "$o_dir/Alignments";

    $files = &Ali::Import::import_fasta_alis( $src_dir, $ali_dir, $args );

    # Connect to each alignment created and update feature database,

    $args->{"tab_dir"} = "$i_dir/Database_tables";
    $args->{"source"} = "Ludwig";

    &Ali::Import::import_features_alis( $files, $args );

    return scalar @{ $files };
}

sub import_ssu_rdp
{
    # Niels Larsen, January 2006.

    # Reads the RDP RNA alignment(s) and creates alignment(s) in "raw" format.

    my ( $i_dir,       # Input directory
         $o_dir,       # Output directory
         $msgs,
         $readonly,    # Command line arguments and settings
         ) = @_;

    # Returns nothing. 

    my ( $files, $args, $src_dir, $ali_dir );

    $args->{"datatype"} = "rna_ali";
    $args->{"prefixes"} = [ "SSU_RDP" ];
    $args->{"titles"} = [ "RDP" ];

    $args->{"ft_menu"} = Registry::Get->features([
                                                    "ali_seq_cons",
                                                    ]);
    $src_dir = "$i_dir/Downloads";
    $ali_dir = "$o_dir/Alignments";

    $files = &Ali::Import::import_fasta_alis( $src_dir, $ali_dir, $args );

    # Connect to each alignment created and update feature database,

    $args->{"tab_dir"} = "$i_dir/Database_tables";
    $args->{"source"} = "RDP";

    &Ali::Import::import_features_alis( $files, $args );

    return scalar @{ $files };
}

sub import_seqs_missing
{
    my ( $class,
         $pairs,
         $msgs,
        ) = @_;

    my ( @pairs );

    require DNA::Import;

#     &dump( $pairs );

    @pairs = DNA::Import->import_seqs_missing( $pairs, $msgs );

    return wantarray ? @pairs : \@pairs;
}    

sub import_ssu_embl
{
    # Niels Larsen, November 2005.

    # Builds from sources blast binaries and loads a given set of data 
    # tables into database. 

    my ( $db,
         $args,        # Arguments and settings
         $msgs,        # Message list
         ) = @_;

    # First load database tables,

    my ( $dbh, $file, $type, $count, $minlen, $src_files, $src_file, $src_fh, 
         $src_dir, $tab_fh, $tab_files, $tab_file, $seq, $fh_50, $fh_500, $fh_1250,
         $length, @files, $sim_args, $prefix, $ins_dir, $tab_dir, $nodes, $line );

    $src_dir = $args->{"src_dir"};
    $ins_dir = $args->{"ins_dir"};
    $tab_dir = $args->{"tab_dir"};

    $type = "rRNA_18S";

    # >>>>>>>>>>>>>>>>>>>>>>>> TAXONOMY MUST EXIST <<<<<<<<<<<<<<<<<<<<<<<<<

    $dbh = &Common::DB::connect();
    
    if ( not &Taxonomy::DB::database_exists( $dbh ) )
    {
        &Common::DB::disconnect( $dbh );
        &error( qq (Taxonomy database does not exist) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>> DATABASE ANNOTATIONS <<<<<<<<<<<<<<<<<<<<<<<<<

    # Unpack downloaded table files into table directory,

    &echo( qq (   Unpacking SSU RNA annotation sources ... ) );

    $src_files = &Common::File::list_files( $src_dir, '.tab.gz' );

    foreach $src_file ( @{ $src_files } )
    {
        $src_fh = &Common::File::get_read_handle( "$src_dir/". $src_file->{"name"} );

        $tab_file = "$tab_dir/". $src_file->{"name"};
        $tab_file =~ s/\.gz$//;

        $tab_fh = &Common::File::get_write_handle( $tab_file );

        $tab_fh->print( $line ) while ( $line = <$src_fh> );
        
        &Common::File::close_handle( $src_fh );
        &Common::File::close_handle( $tab_fh );
    }

    &echo_green( "done\n" );

    # Then load them into database,

    &echo( qq (   Loading annotations to database ... ) );
    
    $args->{"type"} = $type;

    $args->{"delete"} = 0;
    $args->{"replace"} = 1;
    $args->{"source"} = "EMBL";

    &RNA::DB::load_tables( $dbh, $args );
    
    &echo_green( "done\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE FASTA FILES <<<<<<<<<<<<<<<<<<<<<<<<<<

    # The download includes a single file with all sequences; here three 
    # files are written with different lengths, 

    &echo( qq (   Writing fasta sequences ... ) );

    $type = "rRNA_18S";
    
    $src_fh = &Common::File::get_read_handle( "$src_dir/all_seqs.fasta.gz" );

    $fh_50 = &Common::File::get_write_handle( "$ins_dir/$type"."_50.fasta" );
    $fh_500 = &Common::File::get_write_handle( "$ins_dir/$type"."_500.fasta" );
    $fh_1250 = &Common::File::get_write_handle( "$ins_dir/$type"."_1250.fasta" );

    while ( $seq = bless &Seq::IO::read_seq_fasta( $src_fh ), "Seq::Common" )
    {
        $length = $seq->seq_len;

        &Seq::IO::write_seq_fasta( $fh_50, $seq ) if $length > 50;
        &Seq::IO::write_seq_fasta( $fh_500, $seq ) if $length > 500;
        &Seq::IO::write_seq_fasta( $fh_1250, $seq ) if $length > 1250;
    }

    &Common::File::close_handle( $src_fh );

    &Common::File::close_handle( $fh_50 );
    &Common::File::close_handle( $fh_500 );
    &Common::File::close_handle( $fh_1250 );

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILES FOR BLAST <<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Building blast indices ... ) );
    
    @files = &Common::File::list_fastas( $ins_dir );

    foreach $file ( @files )
    {
        $prefix = $file->{"path"};
        $prefix =~ s/\.fasta$//;

        &Seq::IO::index_blastn( $file->{"path"}, $prefix );
    }

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>> TAXONOMY STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<

    $nodes = &Taxonomy::DB::build_taxonomy( $dbh );

    &Taxonomy::Stats::update_ssu_rna( $dbh, $nodes );
    
    &Common::DB::disconnect( $dbh );
    
    return scalar @files;
}

sub parse_pairmask
{
    # Niels Larsen, March 2006.

    # Parses a given pairmask string/list/pdl into a list of beginnings and 
    # ends of each consecutive stretch of paired bases. Each list element is
    # [ beg5, end5, beg3, end3, type, number ], where type is "helix" or 
    # "pseudo" and number is the number inferred or read from the mask. Three
    # different mask styles are currently recognized, more can be added. 

    my ( $mask,
         $msgs,
         ) = @_;

    # Returns a list.

    my ( $gap_count, $ch_total, $ch_count, $helix, $pseudo, $pairings );

    $gap_count = ($mask =~ tr/-//) + ($mask =~ tr/~//) + ($mask =~ tr/.//);
    $ch_total = ( length $mask ) - $gap_count;

    # If no characters,

    if ( $ch_total == 0 )
    {
        $pairings = [];
    }

    # Ebbe style, with mostly parantheses/brackets,
        
    elsif ( ( $ch_count = ($mask =~ tr/()[]//) ) > 0.7 * $ch_total )
    {
        $helix->[0] = [ "(" ];
        $helix->[1] = [ ")" ];
        
        $pseudo->[0] = [ "[" ];
        $pseudo->[1] = [ "]" ];

        $pairings = &RNA::Import::parse_pairmask_generic( $mask, $helix, $pseudo, $msgs );
    }

    # Rfam style, with mostly '>>>' and letters,
        
    elsif ( ( $ch_count = ($mask =~ tr/><A-Za-z//) ) > 0.7 * $ch_total )
    {
        $helix->[0] = [ "<" ];
        $helix->[1] = [ ">" ];
        
        $pseudo->[0] = [ "A" .. "Z" ];
        $pseudo->[1] = [ "a" .. "z" ];
        
        $pairings = &RNA::Import::parse_pairmask_generic( $mask, $helix, $pseudo, $msgs );
    }

    # Zwieb style, with mostly numbers + characters,
        
    elsif ( ( $ch_count = ($mask =~ tr/0-9A-Za-z//) ) > 0.7 * $ch_total )
    {            
        $pairings = &RNA::Import::parse_pairmask_zwieb( $mask, $msgs );
    }
    else {
        &error( qq (Unrecognized pairing mask type.) );
    }
    
    return wantarray ? @{ $pairings } : $pairings;
}

sub parse_pairmask_generic
{
    # Niels Larsen, March 2006.

    # Converts a given pairing mask string/list/pdl to a list of pairings where 
    # begins and ends are alignment numbers. The input should contain nested 
    # characters to indicate pairings, like this (example from Rfam):
    # 
    # ...<<<<..<<..AA....>>>>>>..aa...
    # 
    # However the characters used can be different. 

    my ( $mask,        # Mask list
         $chars1,
         $chars2,
         $errors,      # Error message list - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( @mask, @props, $find_stem_ends, $find_stems, $string, $find_pairings,
         @unused, %unused );

    # Allow different input mask data types,

    if ( ref $mask )
    {
        if ( ref $mask eq "PDL::Char" ) {
            @mask = split "", ${ $mask->get_dataref };
        } else {
            @mask = @{ $mask };
        }
    } else {
        @mask = split "", $mask;
    }

    # Strategy: locate terminal loops; record the coordinates of the stems
    # that delimit them; delete this stem from the mask; repeat until no more
    # terminal loops. This of course gets inefficient for large structures,
    # but they wont be that large. It may take a second or two for rrna.

    $find_stem_ends = sub 
    {
        # Creates @ends, a list of [ beg, end ] where beg and end are the mask
        # index positions of the distal end of the base helices of the terminal
        # stems. Returns a list.

        my ( $mask, $ch5, $ch3 ) = @_;

        my ( $last_ch, $last_pos, $i, $ch, @ends );

        $last_ch = "";
        $last_pos = 0;
        
        for ( $i = 0; $i <= $#mask; $i++ )
        {
            $ch = $mask[$i];
            
            if ( $ch eq $ch3 )
            {
                if ( $last_ch eq $ch5 )
                {
                    push @ends, [ $last_pos, $i ];
                }
                
                $last_ch = $ch;
            }
            elsif ( $ch eq $ch5 )
            {
                $last_ch = $ch;
                $last_pos = $i;
            }
        }

        return wantarray ? @ends : \@ends;
    };

    $find_stems = sub
    {
        # Creates @stems, a list of [ beg5, end5, beg3, end3 ] where beg5 and end5
        # are beginnings and ends of the 5' side of the pairing, beg3 and end3 the
        # downstream side. The mask characters of each recorded stem are deleted.

        my ( $mask, $ends, $ch5, $ch3 ) = @_;

        my ( $i, $j, @stems, $end );

        foreach $end ( @{ $ends } )
        {
            $i = $end->[0];
            $j = $end->[1];

            while ( $mask[$i] eq $ch5 and $mask[$j] eq $ch3 )
            {
                $mask->[$i] = "";
                $mask->[$j] = "";

                $i -= 1;
                $j += 1;
            }

            push @stems, [ $i+1, $end->[0], $end->[1], $j-1 ];
        }

        return wantarray ? @stems : \@stems;
    };

    $find_pairings = sub
    {
        # Creates a list of [ 

        my ( $mask, $chars, $type ) = @_;

        my ( $ndx, $maxndx, $ch5, $ch3, $ends, $stems, $stem, $pairnum, @props );

        $ndx = 0;
        $maxndx = $#{ $chars->[0] };

        $ch5 = $chars->[0]->[$ndx];
        $ch3 = $chars->[1]->[$ndx];

        $ends = &{ $find_stem_ends }( $mask, $ch5, $ch3 );
        $pairnum = 1;

        while ( @{ $ends } )
        {
            $ndx += 1;
            $ndx = 0 if $ndx > $maxndx;
            
            $ch5 = $chars->[0]->[$ndx];
            $ch3 = $chars->[1]->[$ndx];

            @{ $stems } = &{ $find_stems }( $mask, $ends, $ch5, $ch3 );

            foreach $stem ( @{ $stems } )
            {
                #                 beg1        end1        beg2        end2
                push @props, [ $stem->[0], $stem->[1], $stem->[2], $stem->[3], $type, $pairnum ];
            
                $pairnum += 1;
            }

            $ends = &{ $find_stem_ends }( $mask, $ch5, $ch3 );
        }

        return wantarray ? @props : \@props;
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HELIX PAIRINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    push @props, &{ $find_pairings }( \@mask, $chars1, "helix" );
    push @props, &{ $find_pairings }( \@mask, $chars2, "pseudo" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @unused = grep /^\.$/, @mask;
    @unused = grep /[^\.\-\~]/, @unused;

    if ( @unused )
    {
        %unused = map { $_, 1 } @unused;
        $string = quotemeta join "", keys %unused;
        push @{ $errors }, [ "Warning", qq (Unrecognized mask characters -> "$string") ];
    }
    
    return wantarray ? @props : \@props;
}

sub parse_pairmask_zwieb
{
    # Niels Larsen, April 2005.

    # Converts a given SRPdb-type pairing mask string to a list of 
    # [ beg1, end1, beg2, end2, description text ] where begins and ends 
    # are alignment numbers. A simple stem-loop in SRPdb looks like this,
    # 
    # "...1111..AA....1111..aa..."
    # 
    # where the first run of 1's marks the 5' side of a pairing, the 
    # second run the 3' side. 

    my ( $mask,        # Mask string
         $msgs,        # Error message list - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( @mask, %mask, @props, $i, $ch, $prop, $imax, $beg1, $end1,
         $beg2, $end2, $count, $cols, $type, $num, $msg );

    # Strategy: locate terminal loops; record the coordinates of the stems
    # that delimit them; delete this stem from the mask; repeat until no more
    # terminal loops. This of course gets inefficient for large structures,
    # but they wont be that large. It may take a second or two for rrna.

    if ( ref $mask )
    {
        if ( ref $mask eq "PDL::Char" ) {
            @mask = split "", ${ $mask->get_dataref };
        } else {
            @mask = @{ $mask };
        }
    } else {
        @mask = split "", $mask;
    }

    for ( $i = 0; $i <= $#mask; $i++ )
    {
        if ( $mask[ $i ] =~ /^[0-9A-Za-z]$/ )
        {
            $ch = $mask[ $i ];
            push @{ $mask{ $ch } }, $i;
        }
    }

    foreach $ch ( keys %mask )
    {
        $count = scalar @{ $mask{ $ch } };

        if ( $count % 2 == 0 )
        {
            $cols = $mask{ $ch };
         
            while ( @{ $cols } )
            {
                $beg1 = $cols->[0];
                $end2 = $cols->[-1];
                $end1 = $beg1;
                $beg2 = $end2;
                
                while ( exists $cols->[1] and
                        $cols->[0] == $cols->[1] - 1 and
                        $cols->[-1] == $cols->[-2] + 1 )
                {
                    $end1 += 1;
                    $beg2 -= 1;
                    
                    shift @{ $cols };
                    pop @{ $cols };
                }
                
                if ( $beg2 - $end1 >= 3 )
                {
                    # Zwieb uses 1-9 and A-Z to mark helices, and lower case for
                    # for pseudoknots. So 6th element is a number or character,

                    if ( $ch =~ /^\d$/ ) {
                        push @props, [ $beg1, $end1, $beg2, $end2, "helix", ( ord $ch ) - 48 ];
                    } elsif ( $ch =~ /^[A-Z]$/ ) {
                        push @props, [ $beg1, $end1, $beg2, $end2, "helix", ( ord $ch ) - 55 ];
                    } else {
                        push @props, [ $beg1, $end1, $beg2, $end2, "pseudo", $ch ];
                    }
                }
                
                shift @{ $cols };
                pop @{ $cols };
            }
        }
        else
        {
            $msg = qq (Uneven number of symbols ('$ch') in pairing mask, pairing skipped.);
            
            if ( defined $msgs ) {
                push @{ $msgs }, [ "Warning", $msg ];
            } else {
                &error( $msg );
            }
        }
    }

    return wantarray ? @props : \@props;
}

sub stem_length_difference
{
    # Niels Larsen, June 2006.

    # Returns the length difference between the two strands of the proximal 
    # pairing in a given RNAfold mask. 

    my ( $mask,    # Mask string
         $msgs,    # Message list
         ) = @_;

    # Returns an integer.

    my ( @pairs5, @pairs3, $beg5, $end5, $beg3, $end3, $i, $j, $diff );
    
    @pairs5 = &RNA::Import::parse_pairmask( $mask, $msgs );

    @pairs5 = sort { $a->[0] <=> $b->[0] } @pairs5;
    @pairs3 = sort { $a->[2] <=> $b->[2] } @pairs5;

    # Find the lengths of the 5' side and 3' side of the proximal pairing
    # extended until it branches. We would like to measure the difference 
    # between 1) and 2),
    # 
    # 1)  '...((((((....(((...)))....))))))...'    (same lengths)
    # 2)  '...((((((.......(((...))).))))))...'    (different lengths)

    $beg5 = $pairs5[0]->[0];
    $end3 = $pairs3[-1]->[3];

    $i = 0;
    $j = $#pairs3;

    while ( $i <= $#pairs5 and $pairs5[$i]->[0] eq $pairs3[$j]->[0] )
    {
        $end5 = $pairs5[$i]->[1];
        $beg3 = $pairs3[$j]->[2];

        $i += 1;
        $j -= 1;        
    }

    $diff = ( $end5 - $beg5 - $end3 + $beg3 ) + 1;
    
    return $diff;
}

sub stem_position_shift
{
    # Niels Larsen, June 2006.

    # Returns the position difference between the two strands of the 
    # proximal pairing in a given RNAfold mask. This is a very crude
    # measure of how asymmetric the pairing is within the mask.

    my ( $mask,    # Mask string
         $msgs,    # Message list
         ) = @_;

    # Returns an integer.

    my ( @pairs5, @pairs3, $beg5, $end5, $beg3, $end3, $i, $j, $shift );
    
    @pairs5 = &RNA::Import::parse_pairmask( $mask, $msgs );

    @pairs5 = sort { $a->[0] <=> $b->[0] } @pairs5;
    @pairs3 = sort { $a->[2] <=> $b->[2] } @pairs5;

    # Find by how much the loop center is off the middle of the overall 
    # pairing mask. We want to score the difference between 1) and 2):
    # 
    # 1)  '....((((((..(((......)))..))))))....'   (no overall shift)
    # 2)  '.((((((..(((......)))..)))))).......'   (pairing shifted)
    
    $beg5 = $pairs5[0]->[0];
    $end3 = $pairs3[-1]->[3];

    $i = 0;
    $j = $#pairs3;

    while ( $i <= $#pairs5 and $pairs5[$i]->[0] eq $pairs3[$j]->[0] )
    {
        $end5 = $pairs5[$i]->[1];
        $beg3 = $pairs3[$j]->[2];

        $i += 1;
        $j -= 1;        
    }

    $shift = ( $end5 - ( (length $mask) - 1 - $beg3 ) ) + 1;
    
    return $shift;
}

1;

__END__ 

# sub write_blast_dbs
# {
#     # Niels Larsen, December 2006.

#     # Writes blast files for each of the given fasta sequence input files
#     # and saves the resulting index files in the given output directory.

#     my ( $i_files,         # Alignment input files
#          $o_dir,           # Sequence output directory path
#          $msgs,            # Messages returned - OPTIONAL
#          ) = @_;

#     # Returns an integer. 

#     my ( $i_file );

#     &Common::File::create_dir_if_not_exists( $o_dir );
    
#     foreach $i_file ( @{ $i_files } )
#     {
#         &RNA::Import::write_blast_db( $i_file->{"path"} );
#     }

#     return scalar @{ $i_files };
# }

# sub write_blast_db
# {
#     # Niels Larsen, July 2004.

#     # Indexes a given fasta "subject" DNA/RNA file for blast search, 
#     # using formatdb. The file must be given by its full file path. 
#     # The .nhr, .nin and .nsq indices are placed in the given directory,
#     # or in the same directory as the subject file if omitted. 

#     my ( $infile,      # Input file path, fasta format
#          $outpre,      # Output index prefix file path - OPTIONAL
#          ) = @_;
    
#     # Returns nothing. 

#     my ( @command, $command, $program, $dirname );

#     if ( not $outpre ) {
#         $outpre = &Common::Names::strip_suffix( $infile );
#     }

#     $program = "$Common::Config::bin_dir/formatdb";

#     &Common::File::delete_file_if_exists( "$outpre.nhr" );
#     &Common::File::delete_file_if_exists( "$outpre.nin" );
#     &Common::File::delete_file_if_exists( "$outpre.nsq" );
    
#     @command = ( $program, "-p", "F", "-i", $infile, "-n", $outpre, "-l", "$outpre.log" );
#     $command = join " ", @command;

#     if ( system( @command ) != 0 )
#     {
#         $command = join " ", @command;
#         &error( qq (Command failed -> "$command") );
#     }
    
#     &Common::File::delete_file_if_exists( "$outpre.log" );

#     return;
# }


    # >>>>>>>>>>>>>>>>>>>>>>> LOAD DATABASE TABLES <<<<<<<<<<<<<<<<<<<<<<<

#    return $count;
# }
#         &Common::File::close_handle( $src_fh );
#         &Common::File::close_handles( $tab_fhs );

#         &Ali::Import::load_tabfiles( $dbh, $db );

#         &Common::DB::disconnect( $dbh );
#    }


#    $schema = &Ali::Schema::relational();

#    $dbh = &Common::DB::connect();
#    $readonly = $cl_args->{"readonly"};

#     # >>>>>>>>>>>>>>>>>>>>>>>> TRIM DATABASE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Remove old records depending on arguments, 

#     $cl_args->{"source"} = "Rfam";

#     &Ali::Import::trim_database( $dbh, $cl_args );

#     # >>>>>>>>>>>>>>>>>>>>>>> GET IO HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $src_fh = &Common::File::get_read_handle( $src_file );

#     if ( not $readonly )
#     {
#         &echo( "   Deleting old temporary files ... " );
    
#         $count = &Common::Import::delete_tabfiles( $tab_dir, $schema );
        
#         if ( $count > 0 ) {
#             &echo_green( "$count gone\n" );
#         } else {
#             &echo_green( "none\n" );
#         }

#         &Common::File::create_dir_if_not_exists( $tab_dir );
#         $tab_fhs = &Common::Import::create_tabfile_handles( $tab_dir, $schema, ">>" );
#         $count = 0;

#         # >>>>>>>>>>>>>>>>>>>>>> DELETE OLD ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<<

#         &echo( "   Deleting old Rfam alignments ... " );

#         $count = &Common::File::delete_dir_tree_if_exists( $ali_dir );
#         &Common::File::create_dir_if_not_exists( $ali_dir );
        
#         $count = ( $count - 1 ) / 2;
#         &echo_green( "$count gone\n" );
#     }

    # >>>>>>>>>>>>>>>>>>>>>>> WRITE ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<

#         $dbh = &Common::DB::connect();

#         # Get alignment and feature id to increment below,
        
#         $ali_id = ( &Common::DB::highest_id( $dbh, "ali_annotation", "ali_id" ) || 0 ) + 1;
#         $ft_id = ( &Common::DB::highest_id( $dbh, "ali_annotation", "ali_id" ) || 0 ) + 1;

#     foreach $measure ( @{ $measures } )
#     {
#         # Read one stockholm-entry into aligment object,

#         $sidlen = $measure->[1];
#         $seqlen = $measure->[2];

#         $ali = RNA::Ali->read_stockholm_entry( $src_fh, $sidlen, $seqlen );

#         # Add fields,

#         $ali->id( $ali_id );
#         $ali->source( "Rfam" );

#         # Write alignment object to alignment directory in PDL raw format,

#         if ( not $readonly ) 
#         {
#             $ali->write( "$ali_dir/".$ali->sid );
#         }

#         # Get pairings,

#         $pairs = &RNA::Import::parse_pairmask_rfam( $ali->pairmask, $errors );

#         $features = &RNA::Import::create_pair_features( $ali, $pairs, $ft_id );
#         $ali->features( $features );

#         if ( not $readonly )
#         {
#             &Ali::Import::append_tabfiles( $tab_fhs, $ali );
#         }

#         $ali_id += 1;
#         $ft_id = $features->[-1]->id + 1;

#         $count += 1;
#     }

#    if ( $readonly ) 
#    {
#        &echo_green( "$count found\n" );
#    }
#    else
#    {
#        &echo_green( "$count written\n" );

#         &Common::File::close_handle( $src_fh );
#         &Common::File::close_handles( $tab_fhs );

#         &Ali::Import::load_tabfiles( $dbh, $cl_args );

#         &Common::DB::disconnect( $dbh );
#    }


# sub log_errors
# {
#     # Niels Larsen, December 2004.
    
#     # Appends a given list of messages to an ERRORS file in the 
#     # RNA/Import subdirectory. 

#     my ( $errors,   # Error messages
#          ) = @_;

#     # Returns nothing.

#     my ( $error, $log_dir, $log_file );

#     $log_dir = "$Common::Config::log_dir/RNA/Import";
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


# sub belgian_ssu_to_fasta
# {
#     # Niels Larsen, December 2004.            UNFINISHED

#     # Converts the files created by RNA::Download::download_ssu_rnas
#     # (from the Belgian rRNA database, http://www.psb.ugent.be/rRNA)
#     # to 1) a file of ids + names, 2) fasta formatted sequence file
#     # and 3) a file of byte offsets that can be used for retrieval.
#     # Returns the number of sequences processed. 

#     my ( $ids_file,      # Input ids file
#          $seqs_file,     # Input sequences file
#          $prefix,        # Prefix for output files
#          ) = @_;
    
#     # Returns an integer.

#     my ( $ids_fh, $seqs_fh, $info_fh, $fasta_fh, $index_fh, $count,
#          $line, $seq, $seqlen, $nobases, $sid, $key, $value, $tax, $org,
#          $pct, $fh_pos, $byte_beg, $byte_end );

#     $ids_fh = &Common::File::get_read_handle( $ids_file );
#     $seqs_fh = &Common::File::get_read_handle( $seqs_file );
#     $info_fh = &Common::File::get_write_handle( "$prefix.info" );
#     $fasta_fh = &Common::File::get_write_handle( "$prefix.fasta" );
#     $index_fh = &Common::File::get_write_handle( "$prefix.index" );

#     $count = 0;
#     $fh_pos = 0;
    
#     while ( defined ( $line = <$ids_fh> ) )
#     {
#         chomp $line; 

#         $seq = "";
#         $sid = $line;
#         $org = "";
#         $tax = "";

#         while ( defined ( $line = <$seqs_fh> ) and $line !~ /^\/\// )
#         {
#             chomp $line;

#             if ( $line =~ /^([a-z0-9]{3,3}):(.*)$/ )
#             {
#                 $key = $1;
#                 $value = $2;
                
#                 if ( $key eq "ta1" ) {
#                     $tax = $value;
#                 } elsif ( $key eq "seq" ) {
#                     $org = $value;
#                 }
#             }
#             else {
#                 $seq .= $line;
#             }
#         }

#         $seq = uc $seq;
#         $seq =~ s/[^AUGCRYWSMKVHBD]//g;

#         $seqlen = length $seq;

#         $nobases = $seq =~ tr/Oo//d;

#         $pct = 100.0 * ( ( $seqlen - $nobases ) / $seqlen );
        
#         $info_fh->print( "$sid\t$org\t$tax\t$pct\t$seqlen\n" );
#         $fasta_fh->print( ">$sid\n$seq\n" );

#         $byte_beg = $fh_pos + (length $sid) + 3;
#         $byte_end = $byte_beg + $seqlen - $nobases - 1;

#         $index_fh->print( "$sid\t$byte_beg\t$byte_end\n" );

#         $fh_pos = $byte_end + 1;
#         $count += 1;
#     }
    
#     &Common::File::close_handle( $ids_fh );
#     &Common::File::close_handle( $seqs_fh );
#     &Common::File::close_handle( $info_fh );
#     &Common::File::close_handle( $fasta_fh );
#     &Common::File::close_handle( $index_fh );

#     return $count;
# }


# sub update_dna_seq_cache
# {
#     # Niels Larsen, April 2006.

#     # 

#     my ( $src_files,
#          $dst_dir,
#          $msgs,
#          ) = @_;

#     my ( $file, $ali, $sids, $row, $sid, $embl_id, $embl_file, $seqIO, 
#          $count, $dst_file );

#     foreach $file ( @{ $src_files } )
#     {
#         $ali = &Ali::IO::connect_pdl( $file->{"path"} );
#         $ali = &Ali::Common::de_pdlify( $ali );

#         $sids = $ali->sids;

#         for ( $row = 0; $row <= $#{ $sids }; $row++ )
#         {
#             $sid = $sids->[$row];

#             if ( $sid =~ /^(.+)\/(\d+)-(\d+)$/ )
#             {
#                 $embl_id = $1;
#                 $embl_id =~ s/\.\d*$//;
#             }
#             else {
#                 push @{ $msgs }, [ "Error", qq (Wrong looking label -> "$sid") ];
#             }

#             $dst_file = "$dst_dir/$embl_id";

#             if ( not -r $dst_file )
#             {
#                 &Common::File::delete_file_if_exists( "$dst_file.embl" );

#                 $embl_file = &DNA::EMBL::Download::download_embl_entry_soap( $embl_id, $dst_dir, $msgs );

#                 if ( $embl_file )
#                 {
#                     $seqIO = Bio::SeqIO->new( -file => "< $embl_file", -format => "embl" );

#                     &Common::File::store_file( $dst_file, $seqIO->next_seq );
#                     $count += 1;

#                     &Common::File::delete_file( $embl_file );
#                 }
#             }
#         }

#         undef $ali;
#     }

#     return $count;
# }
