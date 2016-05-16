package Seq::Import;                # -*- perl -*-

# Imports sequences to native form, reformatting etc.
# TODO: BADLY needs cleaning and improvement

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;
use Data::Dumper;
use LWP::Simple;
use Tie::File;
use IO::Compress::Gzip qw( :all );
use Bit::Vector;

use Common::Config;
use Common::Messages;

use Registry::Get;
use Registry::Args;
use Registry::Paths;
use Common::Obj;

use base qw ( Seq::Common Seq::Features Sims::Common );

use Common::File;
use Common::OS;
use Common::Entrez;
use Common::DBM;

use Seq::IO;
use Seq::Storage;

local $| = 1;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Class methods that read, write and index sequences. 
#
# add_filling_from_sims
# download_seqs
# download_seqs_missing
# emboss_config_text
# enable_new_version
# extract_embl_ids
# extract_genbank_ids
# get_cache_dir
# import_seqs_missing
# import_dbflat
# import_dbflat_config
# import_keys
# index_dbflat_files
# installed_files
# list_seqs_missing
# list_split_dirs
# next_dbflat_entry
# split_dbflat_files
# update_emboss_config
# write_emboss_index
# write_fasta_db_bioperl
# write_fasta_from_sims
# write_fasta_from_phylip

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_filling_from_sims
{
    # Niels Larsen, January 2007.

    # Substitutes gaps in a fasta file of aligned sequences with as 
    # much of the original sequence as will fit. To know which sequence
    # to insert a locator list is given: each element is a feature 
    # object that points to the location(s) in the original genbank 
    # record. The list is updated after the filling has happened and
    # is returned. 

    my ( $i_file,           # Input file
         $o_file,           # Output file
         $sims,             # List of similarities
         $params,           # Parameters - OPTIONAL
         $msgs,             # Error messages - OPTIONAL
         ) = @_;

    # Returns nothing. 

    my ( %def_params, $i_fh, $o_fh, $seq, $entry, $ndx, $gbseq, $msg, $sim,
         $seq_id, $loc_id, $loc_beg, $loc_end, $gbseq_len, $beg, $end, %sims,
         $gbseq5, $gbseq3, $seq_str, $gap_str_l, $gap_str_r, %skip_ids,
         $seq_str_l, $seq_str_r );

    $i_fh = &Common::File::get_read_handle( $i_file );
    $o_fh = &Common::File::get_write_handle( $o_file );

    foreach $sim ( @{ $sims } )
    {
        $sims{ $sim->id2 } = $sim;
    }

    if ( $params->{"skip_ids"} ) {
        %skip_ids = map { $_, 1 } @{ $params->{"skip_ids"} };
    }

    $ndx = 0;

    while ( defined ( $seq = bless &Seq::IO::read_seq_fasta( $i_fh ), "Seq::Common" ) )
    {
        $seq_id = $seq->id;
        $seq_str = $seq->seq;

        # Skip if locator with no id, that means "no filling please",
        
        if ( $skip_ids{ $seq_id } )
        {
            if ( $seq_str =~ /^(-+)/ )
            {
                $gap_str_l = "~" x length $1;
                $seq_str =~ s/^-+/$gap_str_l/;
            }
            
            if ( $seq_str =~ /(-+)$/ )
            {
                $gap_str_r = "~" x length $1;
                $seq_str =~ s/-+$/$gap_str_r/;
            }
            
            $o_fh->print( ">$seq_id\n$seq_str\n" );
            next;
        }
        else 
        {
            $loc_id = $seq_id;
            $sim = $sims{ $loc_id };
        }

        # Error if name mismatch,

        if ( not $sim ) {
            &error( qq (Sequence id without similaity -> "$loc_id") );
        }

        # Get entire genbank entry from local cache,

        $entry = Seq::IO->read_genbank_entry( $seq_id,
                                              {
                                                  "format" => "bioperl",
                                                  "source" => "local",
                                                  "datatype" => $params->{"datatype"},
                                              });

        $gbseq = $entry->next_seq->seq;
        $gbseq_len = length $gbseq;

        # Some retired records, while rare, come back from bioperl with the 
        # sequence "N", we must skip those,
        
        $loc_beg = $sim->beg2;
        $loc_end = $sim->end2;

        if ( $seq_str =~ s/^([^A-Za-z]+)// ) {
            $gap_str_l = $1;
        } else {
            $gap_str_l = "";
        }
        
        if ( $seq_str =~ s/([^A-Za-z]+)$// ) {
            $gap_str_r = $1;
        } else {
            $gap_str_r = "";
        }
        
        if ( $gbseq and $gbseq_len > 1 and $loc_beg < $gbseq_len and $loc_end < $gbseq_len ) 
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>> FORWARD MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $loc_beg < $loc_end )
            {
                # Left (upstream),

                if ( $gap_str_l and $loc_beg > 0 ) 
                {
                    $beg = &Common::Util::max( 0, $loc_beg - (length $gap_str_l) );
                    $seq_str_l = lc substr $gbseq, $beg, $loc_beg - $beg;
                }
                else {
                    $seq_str_l = "";
                }
                
                # Right (downstream),

                if ( $gap_str_r and $loc_end < $gbseq_len )
                {
                    $end = &Common::Util::min( $gbseq_len - 1, $loc_end + (length $gap_str_r) );
                    $seq_str_r = lc substr $gbseq, $loc_end+1, $end - $loc_end;
                }
                else {
                    $seq_str_r = "";
                }
            }

            # >>>>>>>>>>>>>>>>>>>>>>>>>>>> REVERSE MATCHES <<<<<<<<<<<<<<<<<<<<<<<<

            else 
            {
                # Left (downstream),

                if ( $gap_str_l and $loc_end > 0 )
                {
                    $end = &Common::Util::min( $gbseq_len - 1, $loc_beg + (length $gap_str_l) );
                    $gbseq5 = substr $gbseq, $loc_beg+1, $end - $loc_beg;
                    $seq_str_l = ${ &Seq::Common::complement_str( \$gbseq5 ) };
                }
                else {
                    $seq_str_l = "";
                }

                # Right (upstream),

                if ( $gap_str_r and $loc_beg < $gbseq_len )
                {
                    $beg = &Common::Util::max( 0, $loc_beg - (length $gap_str_r) );
                    $gbseq3 = substr $gbseq, $beg, $loc_beg - $beg;
                    $seq_str_r = ${ &Seq::Common::complement_str( \$gbseq3 ) };
                }
                else {
                    $seq_str_r = "";
                }
            }

            if ( length $gap_str_l > length $seq_str_l ) {
                $seq_str_l = "~" x ( (length $gap_str_l) - (length $seq_str_l) ) . $seq_str_l;
            }
            
            if ( length $gap_str_r > length $seq_str_r ) {
                $seq_str_r = $seq_str_r . "~" x ( (length $gap_str_r) - (length $seq_str_r) );
            }
        }
        else
        {
            $seq_str_l = "~" x ( length $gap_str_l );
            $seq_str_r = "~" x ( length $gap_str_r );
        }

        if ( $seq_str =~ /[a-z]/ )
        {
            $seq_str_l = lc $seq_str_l if $seq_str_l;
            $seq_str_r = lc $seq_str_r if $seq_str_r;
        }
        else 
        {
            $seq_str_l = uc $seq_str_l if $seq_str_l;
            $seq_str_r = uc $seq_str_r if $seq_str_r;
        }            

        $o_fh->print( ">$seq_id\n$seq_str_l$seq_str$seq_str_r\n" );
    }

    &Common::File::close_handle( $i_fh );
    &Common::File::close_handle( $o_fh );

    return $sims;
}

sub download_seqs
{
    # Niels Larsen, July 2007.

    my ( $class,
         $pairs,
         $args,
         $msgs,
        ) = @_;

    my ( @pairs );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( dbtype outfile ) ],
    });

    @pairs = &Common::Entrez::fetch_seqs_file( $pairs, {
        "dbtype" => $args->dbtype,
        "outfile" => $args->outfile,
    }, $msgs );

    return wantarray ? @pairs : \@pairs;
}

sub download_seqs_missing
{
    # Niels Larsen July 2007.

    # Downloads and installs the entries in a given list if accession 
    # numbers that are missing locally. 

    my ( $class,
         $pairs,
         $args,
         $msgs,
        ) = @_;

    my ( @pairs, $db, @gis );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( dbname dbformat dir_levels outfile ) ],
    });

    @pairs = Seq::Import->list_seqs_missing( $pairs, {
        "dbname" => $args->dbname,
        "dir_levels" => $args->dir_levels,
    });

    if ( @pairs ) 
    {
        $db = Registry::Get->dataset( $args->dbname );
        @gis = map { $_->[1] } @pairs;

        &Common::Entrez::fetch_seqs_file( \@gis, {
            "dbtype" => $db->datatype,
            "outfile" => $args->outfile,
        });
    }

    if ( @pairs ) {
        return wantarray ? @pairs : \@pairs;
    } else {
        return;
    }
}

sub emboss_config_text
{
    my ( $args,
        ) = @_;

    my ( $db_name, $db_type, $db_format, $seq_dir, $ndx_dir, 
         $files, $fields, $comment, $text );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( dbname dbtype dbformat seq_dir ndx_dir files fields comment ) ],
    });

    $db_name = $args->dbname;
    $db_type = $args->dbtype;
    $db_format = $args->dbformat;
    $seq_dir = $args->seq_dir;
    $ndx_dir = $args->ndx_dir;
    $files = $args->files;
    $fields = $args->fields;
    $comment = $args->comment;
    
    $text = qq (RES $db_name [
  type: Index
  idlen:  15
  acclen: 15
  svlen:  15
  keylen: 15
  deslen: 15
  orglen: 15
]

DB $db_name [
   type: $db_type
   format: $db_format
   method: emboss
   dir: $seq_dir
   indexdirectory: $ndx_dir
   file: $files
   fields: "$fields"
   comment: "$comment"
]);

    return $text;
}

sub enable_new_version
{
    # Niels Larsen, September 2007.

    my ( $src_dir,
         $ins_dir,
        ) = @_;

    my ( $content );

    if ( -d $src_dir ."_new" ) {
        &Common::File::change_ghost_paths( $src_dir ."_new", $src_dir );
    }

    if ( -d $src_dir ."_new/Daily" ) {
        &Common::File::change_ghost_paths( $src_dir ."_new/Daily", $src_dir ."/Daily" );
    }

    # Change file paths in INSTALLED file,

    $content = ${ &Common::File::read_file( $ins_dir ."_new/INSTALLED" ) };
    $content =~ s/\/Downloads_new\//\/Downloads\//gs;
    
    &Common::File::delete_file( $ins_dir ."_new/INSTALLED" );
    &Common::File::write_file( $ins_dir ."_new/INSTALLED", $content );

    if ( -e $ins_dir ."_new/Daily" ) 
    {
        $content = ${ &Common::File::read_file( $ins_dir ."_new/Daily/INSTALLED" ) };
        $content =~ s/\/Downloads_new\//\/Downloads\//gs;
    
        &Common::File::delete_file( $ins_dir ."_new/Daily/INSTALLED" );
        &Common::File::write_file( $ins_dir ."_new/Daily/INSTALLED", $content );
    }
        
    # Swap new directories in place of old,
    
    if ( -e $ins_dir ) {
        rename $ins_dir, $ins_dir ."_old";
    }
    
    rename $ins_dir ."_new", $ins_dir;
    
    if ( -e $src_dir ) {
        rename $src_dir, $src_dir ."_old";
    }
    
    rename $src_dir ."_new", $src_dir;

    # Delete previous source and install directories,
    
    if ( -e $ins_dir ."_old" ) {
        &Common::File::delete_dir_tree( $ins_dir ."_old" );
    }

    if ( -e $src_dir ."_old" ) {
        &Common::File::delete_dir_tree( $src_dir ."_old" );
    }

    return;
}

sub get_cache_dir
{
    # Niels Larsen, January 2007.

    # Returns the cache directory (full path13) that corresponds to the
    # type of the given database id.

    my ( $type,
         ) = @_;

    # Returns a string. 

    my ( $path, $dir );

    $path = Registry::Get->type( $type )->path;

    $dir = "$Common::Config::dat_dir/$path/Cache";

    return $dir;
}

sub import_seqs_missing
{
    my ( $class,
         $pairs,
         $args,
         $msgs,
        ) = @_;

    my ( @pairs, $path, $i_fh, $o_fh, $seq, $file, $ins_dir, $db, $db_path,
         $format, $count );

    {
        local $SIG{__DIE__};
        require Bio::SeqIO;
    }

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( dbname dbformat size_max dir_levels
                        fourbit extract_ids split_entry ) ],
    });

    # Fetch from NCBI,

    $path = Registry::Paths->new_temp_path();

    @pairs = Seq::Import->download_seqs_missing( $pairs, {
        "dbname" => $args->dbname,
        "dbformat" => $args->dbformat,
        "dir_levels" => $args->dir_levels,
        "outfile" => $path,
    }, $msgs );

    if ( @pairs )
    {
        # Convert from Genbank to requested format,

        $format = $args->dbformat;

        if ( $format ne "genbank" )
        {
            $i_fh = Bio::SeqIO->new( -file => $path, -format => "genbank" );
            $o_fh = Bio::SeqIO->new( -file => "> $path.$format", -format => $format );
            
            while ( $seq = $i_fh->next_seq )
            {
                $o_fh->write_seq( $seq );
            }
            
            $i_fh->close;
            $o_fh->close;
            
            &Common::File::delete_file( $path );
            &Common::File::rename_file( "$path.$format", $path );
        }

        # Split entries into directory structure,
        
        $file = &Common::File::get_stats( $path );
        $db_path = Registry::Get->dataset( $args->dbname )->datapath_full;
        
        if ( -r "$db_path/Installs_new" ) {
            $ins_dir = "$db_path/Installs_new";
        } else {
            $ins_dir = "$db_path/Installs";
        }
        
        &Seq::Import::split_dbflat_files( [ $file ], {
            "ins_dir" => $ins_dir,
            "size_max" => $args->size_max,
            "keep_src" => 1,
            "dir_levels" => $args->dir_levels,
            "fourbit" => $args->fourbit,
            "extract_ids" => $args->extract_ids,
            "split_entry" => $args->split_entry,
            "register" => 0,
        }, $msgs );

    }

    &Common::File::delete_file_if_exists( $path );

    if ( @pairs ) {
        return wantarray ? @pairs : \@pairs;
    } else {
        return;
    }
}

sub import_keys
{
    # Niels Larsen, February 2010.

    # Reads a table file and stores the lines in the key/value
    # store. The first column is the key, the rest the value.

    my ( $ifile,
         $ofile,
         $bnum,
        ) = @_;

    my ( $dbh, $count, $ifh, $line );

#    use Time::HiRes;
#    my $start = [ &Time::HiRes::gettimeofday() ]; 

    $ifh = &Common::File::get_read_handle( $ifile );

    $dbh = &Common::DBM::write_open( $ofile, "bnum" => $bnum );

    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ /^([^\t]+)\t(.+)$/ ) {
            &Common::DBM::put( $dbh, $1, $2 );
        } else {
            &error( qq (Wrong looking line -> "$line") );
        }

        $count += 1;
    }

    $ifh->close;

#    my $stop = [ &Time::HiRes::gettimeofday() ]; 
#    my $diff = &Time::HiRes::tv_interval( $start, $stop );

#    &dump( $diff );

    return $count;
}
 
sub index_dbflat_files
{
    # Niels Larsen, February 2010.

    # TODO explain
    
    my ( $paths,
         $conf,
        ) = @_;

    # Returns a 2-element list.

    my ( $ifh, $ofh, $hdr_ref, $entry_ref, $seq_ref, $id, $version, 
         $extract_ids, $split_entry, $src_str, $f_count, $e_count, $ins_dir,
         $hdr_fh, $seq_fh, $hdr_key_fh, $seq_key_fh, $seq_beg, 
         $hdr_beg, $hdr_len, $count, $seq_case, $path, $src_dir );

    $extract_ids = $conf->extract_ids;
    $split_entry = $conf->split_entry;

    $src_dir = $conf->src_dir;
    $ins_dir = $conf->ins_dir;

    &Common::File::create_dir_if_not_exists( $conf->ins_dir );

    $hdr_fh = &Common::File::get_append_handle( "$ins_dir/HDRS.text" );
    $seq_fh = &Common::File::get_append_handle( "$ins_dir/SEQS.fasta" );

    $hdr_key_fh = &Common::File::get_append_handle( "$ins_dir/HDRS.keys" );
    
    $hdr_beg = $hdr_fh->tell;
    $seq_beg = $seq_fh->tell;

    $f_count = 0;
    $e_count = 0;

    $seq_case = $conf->seqcase;

    if ( $seq_case and $seq_case ne "upper" and $seq_case ne "lower" ) {
        &error( qq (Wrong looking case switch -> "$seq_case") );
    }

    foreach $path ( sort @{ $paths } )
    {
        &Common::File::write_file( "$ins_dir/INSTALLING", "$path\n" );

        &echo( "   Importing $path ... " );

        $ifh = &Common::File::get_read_handle( "$src_dir/$path" );

        $count = 0;

        while ( $entry_ref = Seq::Import->next_dbflat_entry( $ifh ) )
        {
            {
                no strict "refs";

                ( $hdr_ref, $seq_ref ) = $split_entry->( $entry_ref );

                ( $id, $version ) = $extract_ids->( $hdr_ref );
            }

            # Set case if requested,

            if ( $seq_case )
            {
                if ( $seq_case eq "upper" ) {
                    ${ $seq_ref } = uc ${ $seq_ref };
                } else {
                    ${ $seq_ref } = lc ${ $seq_ref };
                }
            }

            # Headers with annotation,

            $hdr_fh->print( "${ $hdr_ref }\n" );
            $hdr_len = length ${ $hdr_ref };
            
            $hdr_key_fh->print( "$id.$version\t$hdr_beg\t$hdr_len\n" );
            $hdr_beg += $hdr_len + 1;

            # Sequences in fasta format,

            $id = "$id.$version";
            $seq_fh->print( ">$id\n${ $seq_ref }\n" );

            $count += 1;
        }

        $ifh->close;
        &echo_green( &Common::Util::commify_number( "$count\n" ) );

        $f_count += 1;
        $e_count += $count;

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &Common::File::delete_file( "$ins_dir/INSTALLING" );

        # Append full file path to "INSTALLED"; then if program is interrupted, it
        # knows the last distribution file that did not get completely installed. 

        if ( $conf->register ) {
            &Seq::Import::installed_files( $ins_dir, $path );
        }
    }

    $hdr_fh->close;
    $seq_fh->close;

    $hdr_key_fh->close;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Indexing all sequences ... ) );

    &Seq::Storage::create_indices(
        {
            "ifiles" => [ "$ins_dir/SEQS.fasta" ],
            "silent" => 1,
        });

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOAD IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Loading header lookup keys ... ) );

    $count = &Seq::Import::import_keys( "$ins_dir/HDRS.keys", "$ins_dir/HDRS.text.dbm", $e_count );
    &Common::File::delete_file( "$ins_dir/HDRS.keys" );

    &echo_green( &Common::Util::commify_number( $count ) ."\n" );

    return ( $f_count, $e_count );
}

sub installed_files
{
    # Niels Larsen, July 2007.

    # Returns a list of installed files, or if a file is given, updates
    # the list. 

    my ( $dir,
         $path,
         ) = @_;

    my ( @files, $fh );
    
    if ( $path ) 
    {
        $fh = &Common::File::get_append_handle( "$dir/INSTALLED" );
        $fh->print( "$path\n" );
        $fh->close;
    }
    elsif ( -r "$dir/INSTALLED" )
    {
        @files = split "\n", ${ &Common::File::read_file( "$dir/INSTALLED" ) };
        @files = map { $_ =~ s/^\s*//; $_ =~ s/\s*$//; $_ } @files;
        @files = grep { defined $_ } @files;
    }        

    return wantarray ? @files : \@files;
}

sub list_seqs_missing
{
    my ( $class,
         $pairs,
         $args,
         $msgs,
        ) = @_;

    my ( @pairs, $pair, $db, $db_type, $db_path, $dir_levels );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( dbname dir_levels ) ],
    });

    $db = Registry::Get->dataset( $args->dbname );
    
    $db_type = $db->datatype;
    $db_path = $db->datapath_full;
    $dir_levels = $args->dir_levels;

    foreach $pair ( @{ $pairs } )
    {
        if ( not Seq::IO->get_seq_split( $pair->[0], {
            "dbtype" => $db_type,
            "dbpath" => $db_path,
            "dir_levels" => $dir_levels,
            "checkonly" => 1,
            "fatal" => 0,
            }, $msgs ) )
        {
            push @pairs, $pair;
        }
    }

    return wantarray ? @pairs : \@pairs;
}

sub list_split_dirs
{
    my ( $dir,
         $levels,
         $msgs,
        ) = @_;

    my ( @list, $cmd );

    $cmd = "$Common::Config::bin_dir/tree -f -L $levels -i -d --noreport $dir";

    @list = &Common::OS::run_command( $cmd, undef, $msgs );
    chomp @list;

    if ( scalar @list == 1 and $list[0] =~ /\[error / )
    {
        if ( defined $msgs ) {
            push @{ $msgs }, $list[0];
        } else {
            &error( $list[0] );
        }
    }

    @list = map { $_ =~ s/$dir//; $_ } @list;

    @list = grep { $levels == $_ =~ tr /\//\// } @list;
    @list = map { $_ =~ s/^\///; $_ } @list;

    return wantarray ? @list : \@list;
}
    
sub next_dbflat_entry
{
    my ( $class,
         $fh,
        ) = @_;

    my ( $chunk );

    local $/ = "\n//\n";

    if ( defined ( $chunk = <$fh> ) and $chunk =~ /\w/ )
    {
#        if ( substr $chunk, 0, 5 ne "LOCUS" ) 
#        {
#            $chunk =~ s/^.*\nLOCUS/LOCUS/so;
#        }

        return \$chunk;
    }
    else { 
        return;
    }
}

sub import_dbflat
{
    # Niels Larsen, February 2010.

    # Converts a given collection of sequence databank flatfiles to either
    # 
    # 1. As a speed efficient store, with fasta-formatted sequence files 
    #    and annotations in header and table files. This is the default.
    # 
    # 2. As a space efficient collection of small compressed files and 
    #    directories. Access is slow, but of course faster than from a 
    #    remote source. Usually this option is bad, but it will save a lot
    #    of space for entire EMBL or Genbank, and sometimes access speed 
    #    is not important. 
    #
    # These options exist,
    # 
    # keepsrc    If on keeps downloaded sources (on)
    # inplace    Overwrites previous files to save space (off)
    # split      Selects between the two above modes (off)

    my ( $db,             # Dataset name or object
         $args,           # Arguments hash - OPTIONAL
         $msgs,           # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns a 2-element list.

    my ( $defs, $db_path, $src_dir, $ins_dir, $f_count, $e_count, 
         $i, $j, $new_version, $conf, @src_files, @ins_files, 
         $count, $module, @src_paths, @ins_paths, @new_paths );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIGURATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create configuration with settings that are dataset specific, see the 
    # routine,

    $defs = {
        "keepsrc" => 1,
        "inplace" => 0,
        "split" => 0,
    };

    $conf = &Seq::Import::import_dbflat_config( $db, $args, $defs );

    $module = $conf->extract_ids;
    $module =~ s/::[^:]+$//;

    &Common::Messages::require_module( $module );

    $module = $conf->split_entry;
    $module =~ s/::[^:]+$//;

    &Common::Messages::require_module( $module );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SET DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set source and install directories: if new data downloaded then install
    # in a shadow directory and swap when finished (done below),

    $db_path = Registry::Get->dataset( $conf->dbname )->datapath_full;

    if ( -r "$db_path/Downloads_new" )
    {
        $src_dir = "$db_path/Downloads_new";
        $ins_dir = "$db_path/Installs_new";

        $new_version = 1;
    }
    else 
    {
        $src_dir = "$db_path/Downloads";
        $ins_dir = "$db_path/Installs";

        $new_version = 0;
    }

    $conf->add_field( "src_dir", $src_dir );
    $conf->add_field( "ins_dir", $ins_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>> IMPORT RELEASE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<

    $f_count = 0;     # file count
    $e_count = 0;     # entry count

    # If there are real files in download area, import them and "ghost" them,
    # which means remembering their names and sizes in the file "GHOST_FILES",

    &echo("   Are there new release downloads  ... ");

    if ( -d $src_dir )
    {
        @src_files = &Common::File::list_files( $src_dir, '\.gz$' );
        @src_paths = map { $_ =~ s/^$src_dir\///; $_ } map { $_->{"path"} } @src_files;
        
        @ins_paths = &Seq::Import::installed_files( $ins_dir );
        @new_paths = &Common::Util::diff_lists( \@src_paths, \@ins_paths );

        if ( ( $count = scalar @new_paths ) > 0 )
        {
            &echo_green("yes, $count\n");

            if ( $conf->split ) {
                ( $i, $j ) = &Seq::Import::split_dbflat_files( \@new_paths, $conf );
            } else {
                ( $i, $j ) = &Seq::Import::index_dbflat_files( \@new_paths, $conf );
            }                
            
            $f_count += $i;
            $e_count += $j;
        }
        else {
            &echo_green("no\n");
        }
    }
    else {
        &echo_green("no\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>> IMPORT DAILY FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Same as for release above, but in the /Daily subdirectory,

    &echo("   Are there new daily downloads ... ");

    if ( -d $src_dir and -d "$src_dir/Daily" )
    {
        @src_files = &Common::File::list_files( "$src_dir/Daily", '\.gz$' );
        @src_paths = map { $_ =~ s/^$src_dir\///; $_ } map { $_->{"path"} } @src_files;

        @ins_paths = &Seq::Import::installed_files( $ins_dir );
        @new_paths = &Common::Util::diff_lists( \@src_paths, \@ins_paths );

        if ( ( $count = scalar @new_paths ) > 0 )
        {
            &echo_green("yes, $count\n");

            if ( $conf->split ) {
                ( $i, $j ) = &Seq::Import::split_dbflat_files( \@new_paths, $conf );
            } else {
                ( $i, $j ) = &Seq::Import::index_dbflat_files( \@new_paths, $conf );
            }                
            
            $f_count += $i;
            $e_count += $j;
        }
        else {
            &echo_green("no\n");
        }
    }
    else {
        &echo_green("no\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SHADOW VERSION <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If new version, move shadow database into place and delete old,
        
    if ( $new_version and 
         not $conf->inplace and 
         not -e "$ins_dir/INSTALLING" and 
         not -e "$src_dir/DOWNLOADING" )
    {
        &echo( qq (   Swapping new version in place ... ) );
        &Seq::Import::enable_new_version( "$db_path/Downloads", "$db_path/Installs" );
        &echo_green("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $e_count > 0 )
    {
        &echo("   Registering ". $conf->dbname ." ... ");
        Registry::Register->register_datasets( $conf->dbname );
        &echo_green("done\n");
    }

    return ( $f_count, $e_count );
}

sub import_dbflat_config
{
    # Niels Larsen, February 2010.

    # Accepts a databank name and returns a configuration hash for its import
    # by the import_dbflat routine. 

    my ( $db,            # Dataset id or object
         $args,          # Arguments hash
         $defs,
        ) = @_;

    # Returns a hash.

    my ( $conf, $db_name );

    $args = &Registry::Args::create( $args, $defs );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }

    $db_name = $db->name;

    $conf = {
        "dbname" => $db_name,
        "keep_src" => $args->keepsrc,
        "inplace" => $args->inplace,
        "split" => $args->split,
        "seqcase" => "upper",
        "register" => 1,
    };

    if ( $args->split )
    {
        if ( $db->datatype eq "prot_seq" )
        {
            $conf->{"size_max"} = 100_000;
            $conf->{"dir_levels"} = 2;
            $conf->{"fourbit"} = 0;
        }
        else
        {
            $conf->{"size_max"} = 200_000;
            $conf->{"dir_levels"} = 2;
            $conf->{"fourbit"} = 1;
        };
    }
    
    if ( $db_name eq "prot_seq_refseq" )
    {
        $conf->{"extract_ids"} = "DNA::GenBank::Import::extract_ids";
        $conf->{"split_entry"} = "DNA::GenBank::Import::split_entry";
    } 
    elsif ( $db_name eq "prot_seq_uniprot" ) 
    {
        $conf->{"extract_ids"} = "Protein::Uniprot::Import::extract_ids";
        $conf->{"split_entry"} = "Protein::Uniprot::Import::split_entry";
    }        
    elsif ( $db_name eq "dna_seq_embl_local" ) 
    {
        $conf->{"extract_ids"} = "DNA::EMBL::Import::extract_ids";
        $conf->{"split_entry"} = "DNA::EMBL::Import::split_entry";
    }
    elsif ( $db_name eq "dna_seq_genbank_local" )
    {
        $conf->{"extract_ids"} = "DNA::GenBank::Import::extract_ids";
        $conf->{"split_entry"} = "DNA::GenBank::Import::split_entry";
    }
    else {
        &error( qq (Wrong looking dataset name -> "$db_name") );
    }

    $conf = Common::Obj->new( $conf );

    return $conf;
}

sub split_dbflat_files
{
    # Niels Larsen, June 2007.

    # Imports a given list of genbank flatfiles into a given directory. Each
    # entry is placed in a directory named as the first few digits of its GI
    # number. There it is appended to compressed files a few megabytes in 
    # size, and its GI, version and ID is appended as a line to a flat list.
    # Entries can then be retrieved with a "grep" plus zcat into seqret from 
    # the EMBOSS package. The average access time is 0.05 seconds or so, much
    # slower than indexing with EMBOSS dbxflat, but no need to have the files
    # uncompressed. Returns a list of ( file count, entries count ).
    
    my ( $files,         # File list
         $args,          # Arguments hash
        ) = @_;

    # Returns a two-element list.

    my ( $file, $ifile, $ifh, $ofh, $ofh_hdr, $ofh_seq, $id, $sv, $dir, $fname_file, 
         $fname, $entry_file, $entry_ref, $f_count, $e_count, $dir_path, $four_bit,
         %open_fhs, @open_fhs, %out_fnames, $ins_dir, $byt_beg, $split_entry_sub,
         %out_sizes, $open_max, $size_max, $dir_levels, $i_max, $oldest_dir, $i, $line,
         @lines, $count, $key, $src_str, $extract_ids_sub, $md5, $level, $beg, $compressed,
         @dirs, @to_print, %fnames, @fnames, $cmd, $orig_dir, $i_beg, $seq_len, $seq_suffix,
         $i_end, $hdr_ref, $seq_ref, $ifh_lookup, $ofh_lookup, $lookup_file, @line,
         $dir_old, @lookup_list, $str, $gzip, $sort, $bin_str, $hdr_suffix, $seq_case,
         $basename );

    $args = &Registry::Args::check(
        $args, {
            "S:1" => [ qw ( ins_dir size_max keep_src dir_levels 
                            fourbit extract_ids split_entry ) ],
            "S:0" => [ qw ( dbname register src_dir inplace seqcase ) ],
        });

    $ins_dir = $args->ins_dir;

    $size_max = $args->size_max;
    $dir_levels = $args->dir_levels;

#    $orig_dir = `pwd`; # &Cwd::getcwd();
#    &error( "Dir is $orig_dir" );

    $open_max = int ( ( &Common::OS::get_max_files_open() - 50 ) / 2 );

    $extract_ids_sub = $args->extract_ids;
    $split_entry_sub = $args->split_entry;
    $four_bit = $args->fourbit;
    $seq_case = $args->seqcase || "lower";

    use constant HDR => 0;
    use constant SEQ => 1;

    $lookup_file = "$ins_dir/LOOKUP_LISTS";

    if ( $four_bit ) {
        $seq_suffix = "bin";
    } else {
        $seq_suffix = "fa";
    }

    $hdr_suffix = "hdr";

    # >>>>>>>>>>>>>>>>>>>>>>> REMOVE EARLIER JUNK <<<<<<<<<<<<<<<<<<<<<<<<<

    # If the program was interrupted, ran out of disk space etc, then 
    # uncompressed entry files are likely scattered in many directories,
    # but only stemming from the last distribution flat-file that was 
    # incompletely processed. Here we recover the ids from that file,
    # visit its directories and delete,

    if ( -e "$ins_dir/INSTALLING" )
    {
        &echo( qq (   Deleting incompletely installed files ... ) );
        $count = 0;

        $ifile = $files->[0]->{"path"};
        $compressed = &Common::Names::is_compressed( $ifile ) ? 1 : 0;
        $ifh = &Common::File::get_read_handle( $ifile, "compressed" => $compressed );

        while ( $entry_ref = Seq::Import->next_dbflat_entry( $ifh ) )
        {
            {
                no strict "refs";
                ( $id, $sv ) = $extract_ids_sub->( $entry_ref );
            }

            @dirs = &Seq::IO::split_id( $id, $dir_levels + 1 );
            
            $dir = join "/", @dirs[ 0 .. $#dirs-1 ];
            $dir_path = "$ins_dir/$dir";

            if ( -d "$ins_dir/$dir" )
            {
                foreach $file ( &Common::File::list_files( "$ins_dir/$dir", '^\d+$' ) )
                {
                    &Common::File::delete_file( "$ins_dir/$dir/". $file->{"name"} .".$hdr_suffix" );
                    &Common::File::delete_file( "$ins_dir/$dir/". $file->{"name"} .".$seq_suffix" );
                    $count += 1;
                }
            }
        }

        if ( -r $lookup_file ) {
            &Common::File::delete_file( $lookup_file );
        } 

        $ifh->close;

        if ( $count > 0 ) {
            &echo_green( &Common::Util::commify_number( "$count\n" ) );
        } else {
            &echo_green( "none\n" );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FOR EACH FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $f_count = 0;      # file count
    $e_count = 0;      # entry count

    &Common::File::create_dir_if_not_exists( $ins_dir );

    &Common::File::delete_file_if_exists( $lookup_file );
    &Common::File::delete_file_if_exists( "$lookup_file.sorted" );

    foreach $file ( @{ $files } )
    {
        &Common::File::write_file( "$ins_dir/INSTALLING", $file->{"path"} ."\n" );

        &echo( "   Importing $file->{'name'} ... " );

        $ifile = $file->{"path"};
        $compressed = &Common::Names::is_compressed( $ifile ) ? 1 : 0;
        $ifh = &Common::File::get_read_handle( $ifile, "compressed" => $compressed );

        $ofh_lookup = &Common::File::get_append_handle( $lookup_file );

        %open_fhs = ();
        @open_fhs = ();
        %out_fnames = ();
        %out_sizes = ();

        # >>>>>>>>>>>>>>>>>>>>>>>>>> FOR EACH ENTRY <<<<<<<<<<<<<<<<<<<<<<<<<<

        while ( $entry_ref = Seq::Import->next_dbflat_entry( $ifh ) )
        {
            {
                no strict "refs";

                ( $hdr_ref, $seq_ref ) = $split_entry_sub->( $entry_ref );
                undef $entry_ref;

                ( $id, $sv ) = $extract_ids_sub->( $hdr_ref );

                $sv = 1 if not $sv;
            }

            # >>>>>>>>>>>>>>>>>>>>>>>> MAKE DIRECTORY <<<<<<<<<<<<<<<<<<<<<<<<

            # Use the ID, example: the entry with ID "BAAB012132845" will be 
            # put in the directory "BAAB0/1213",

            @dirs = &Seq::IO::split_id( $id, $dir_levels + 1 );
            
            $dir = join "/", @dirs[ 0 .. $#dirs-1 ];
            $dir_path = "$ins_dir/$dir";

            # >>>>>>>>>>>>>>>>>>>>>>> GET ENTRY FILE NAME <<<<<<<<<<<<<<<<<<<<<

            # ID's are put in files named 1.gz, 2.gz, 3.gz etc. If a LOOKUP_LIST
            # file exists, get it from there, otherwise set $fname to 1,

            if ( exists $out_fnames{ $dir } )
            {
                $fname = $out_fnames{ $dir };
            }
            else
            {
                if ( -r "$dir_path/LOOKUP_LIST" )
                {
                    tie @lines, 'Tie::File', "$dir_path/LOOKUP_LIST";
                    $fname = ( split " ", $lines[-1] )[1];
                    $fname = &Common::Names::strip_suffix( $fname ) + 1;
                }
                else
                {
                    &Common::File::create_dir_if_not_exists( $dir_path );
                    $fname = 1;
                }

                $out_fnames{ $dir } = $fname;
            }

            # >>>>>>>>>>>>>>>>>>>>>>> CACHE FILE HANDLES <<<<<<<<<<<<<<<<<<<<<<

            # To reduce opens/closings of files, leave as many files open as 
            # the system permits and keep them in %open_fhs. When their number
            # reaches the maximum, close the oldest one,
            
            if ( not exists $open_fhs{ $dir } )
            {
                if ( scalar @open_fhs >= $open_max )
                {
                    $oldest_dir = shift @open_fhs;

                    $open_fhs{ $oldest_dir }->[HDR]->close;
                    $open_fhs{ $oldest_dir }->[SEQ]->close;
                    
                    delete $open_fhs{ $oldest_dir };
                }
                
                $open_fhs{ $dir }->[HDR] = &Common::File::get_append_handle( "$dir_path/$fname.$hdr_suffix" );
                $open_fhs{ $dir }->[SEQ] = &Common::File::get_append_handle( "$dir_path/$fname.$seq_suffix" );

                push @open_fhs, $dir;
            }
            
            # If this file has already reached it max size, close its handle,
            # increment file name by 1, reset size cache,
            
            if ( exists $out_sizes{ $dir }->[HDR] and $out_sizes{ $dir }->[HDR] > $size_max )
            {
                $out_sizes{ $dir }->[HDR] = 0;
                $out_sizes{ $dir }->[SEQ] = 0;

                $fname += 1;

                $open_fhs{ $dir }->[HDR]->close;
                $open_fhs{ $dir }->[SEQ]->close;

                delete $open_fhs{ $dir };

                $open_fhs{ $dir }->[HDR] = &Common::File::get_append_handle( "$dir_path/$fname.$hdr_suffix" );
                $open_fhs{ $dir }->[SEQ] = &Common::File::get_append_handle( "$dir_path/$fname.$seq_suffix" );

                $out_fnames{ $dir } = $fname;
            }
            
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PRINT ENTRY <<<<<<<<<<<<<<<<<<<<<<<<<<

            # Print sequence, either as concatenated four-bit strings, or as 
            # normal 1-byte fasta files,

            if ( $four_bit )
            {
                &Seq::Common::to_hex( $seq_ref );

                $bin_str = Bit::Vector->new_Hex( 4 * length ${ $seq_ref }, ${ $seq_ref } )->Block_Read;
                $open_fhs{ $dir }->[SEQ]->print( $bin_str );

                $byt_beg = $out_sizes{ $dir }->[SEQ] || 0; 
                $out_sizes{ $dir }->[SEQ] = $byt_beg + length $bin_str;
            }
            else
            {
                $byt_beg = ( $out_sizes{ $dir }->[SEQ] || 0 ) + (length $id) + (length $sv) + 3;

                if ( $seq_case eq "upper" ) {
                    ${ $seq_ref } = uc ${ $seq_ref };
                }

                $open_fhs{ $dir }->[SEQ]->print( ">$id.$sv\n". ${ $seq_ref } ."\n" );
                $out_sizes{ $dir }->[SEQ] = $byt_beg + (length ${ $seq_ref }) + 1;
            }

            # Print header, uncompressed,

            $open_fhs{ $dir }->[HDR]->print( ${ $hdr_ref } ."//\n" );
            $out_sizes{ $dir }->[HDR] += length ${ $hdr_ref };

            # Print to single lookup list; below its content is split and 
            # reformatted and then written to the directories with the sequence 
            # and headers in them,

            $seq_len = length ${ $seq_ref };
            $ofh_lookup->print( "$dir\t$id.$sv\t$fname\t$byt_beg\t$seq_len\n" );
                
            undef $hdr_ref;
            undef $seq_ref;
            
            $e_count += 1;
        }

        # Make sure inputs and outputs are flushed,

        foreach $dir ( keys %open_fhs )
        {
            $open_fhs{ $dir }->[HDR]->close;
            $open_fhs{ $dir }->[SEQ]->close;
        }        

        $ifh->close;
        $ofh_lookup->close;

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SPLIT AND COMPRESS <<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Sort the list of entries, read through the file and write the lines
        # to each their directory,
        
        $orig_dir = &Cwd::getcwd();

        $gzip = "$Common::Config::bin_dir/gzip -1 ";
        $sort = "$Common::Config::bin_dir/sort ";

        &Common::OS::run_command( "$sort $lookup_file > $lookup_file.sorted" );
        &Common::File::delete_file( $lookup_file );
        &Common::File::rename_file( "$lookup_file.sorted", $lookup_file );

        @lookup_list = ();
        %fnames = ();

        $ifh_lookup = &Common::File::get_read_handle( $lookup_file );

        $dir_old = "";

        while ( defined ( $line = <$ifh_lookup> ) )
        {
            @line = split " ", $line;
            $dir = $line[0];
            $fname = $line[2];

            $dir_old = $dir if not $dir_old;

            if ( $dir ne $dir_old )
            {
                chdir "$ins_dir/$dir_old";

                @lookup_list = sort { $a->[1] <=> $b->[1] or $a->[2] <=> $b->[2] } @lookup_list;
                @lookup_list = map { $_->[1] .= ".$seq_suffix"; $_ } @lookup_list;
                @lookup_list = map { (join "\t", @{ $_ }) ."\n" } @lookup_list;
                
                &Common::File::append_file( "LOOKUP_LIST", \@lookup_list );
                @lookup_list = ();

                @fnames = map { "$_.$hdr_suffix" } sort { $a <=> $b } ( keys %fnames );

                &Common::OS::run_command( $gzip . join " ", @fnames );
                %fnames = ();
                
                $dir_old = $dir;
            }

            $fnames{ $fname } = 1;
            
            push @lookup_list, [ @line[ 1 .. $#line ] ];
        }

        $ifh_lookup->close;
        &Common::File::delete_file( $lookup_file );

        if ( @lookup_list )
        {
            chdir "$ins_dir/$dir";

            @lookup_list = sort { $a->[1] <=> $b->[1] or $a->[2] <=> $b->[2] } @lookup_list;
            @lookup_list = map { $_->[1] .= ".$seq_suffix"; $_ } @lookup_list;
            @lookup_list = map { (join "\t", @{ $_ }) ."\n" } @lookup_list;
            
            &Common::File::append_file( "LOOKUP_LIST", \@lookup_list );

            @fnames = map { "$_.$hdr_suffix" } sort { $a <=> $b } ( keys %fnames );
            &Common::OS::run_command( $gzip . join " ", @fnames );
        }

        chdir $orig_dir;

        # >>>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL SOURCE DELETION <<<<<<<<<<<<<<<<<<<<<<<

        # To keep space consumption low, delete the distribution sources, but keep
        # a list of their names, dates and sizes, which are used to compare against
        # the remote files,

        if ( not $args->keep_src ) {
            &Common::File::ghost_file( $file->{"path"} );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &Common::File::delete_file( "$ins_dir/INSTALLING" );

        # Append full file path to "INSTALLED"; then if program is interrupted, it
        # knows the last distribution file that did not get completely installed. 

        if ( $args->register ) {
            &Seq::Import::installed_files( $ins_dir, $file );
        }

        $f_count += 1;

        &echo_green( "done\n" );
    }

    return ( $f_count, $e_count );
}

sub update_emboss_config
{
    # Niels Larsen, June 2007.

    # Registers a given database with EMBOSS, by adding its description
    # to emboss.defaults (in the EMBOSS install area).

    my ( $args,
        ) = @_;

    my ( $dir, $file, $db_name, $content, $text );

    $dir = Registry::Get->software("emboss")->inst_name;

    $file = "$Common::Config::pki_dir/$dir/share/EMBOSS/emboss.default";
    $db_name = $args->dbname;

    if ( -r $file ) 
    {
        $content = ${ &Common::File::read_file( $file ) };
    }
    elsif ( -r "$file.template" ) 
    {
        $content = ${ &Common::File::read_file( "$file.template" ) };
    }
    else {
        &error( qq (File not readable -> "$file") );
    }

    if ( $content =~ /RES\s+$db_name/ ) {
        $content =~ s/RES\s+$db_name\s+\[[^\]]+\]\n//s;
    }

    if ( $content =~ /DB\s+$db_name/ ) {
        $content =~ s/DB\s+$db_name\s+\[[^\]]+\]\n//s;
    }

    $text = &Seq::Import::emboss_config_text(
        {
            "dbname" => $args->dbname,
            "dbtype" => $args->dbtype,
            "dbformat" => $args->dbformat,
            "seq_dir" => $args->ins_dir,
            "ndx_dir" => $args->ins_dir,
            "files" => $args->files,
            "fields" => $args->fields,
            "comment" => $args->comment,
        });
    
    $content .= "$text\n";

    &Common::File::write_file( $file, $content );

    return $file;
}

sub write_emboss_index
{
    # Niels Larsen, April 2007.

    # Uses dbxflat from the EMBOSS package to to index a set of sequence 
    # files. 

    my ( $args,
         ) = @_;

    # Returns 1 or 0.

    my ( $prog, $format, @formats, $expr, $str, $cmdline, $msgs );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( dbname dbtype dbformat seq_dir ndx_dir files fields comment ) ],
    });

    $cmdline = "$Common::Config::bin_dir/dbxflat";

    $cmdline .= " -dbname ". $args->dbname;
    $cmdline .= " -dbresource ". $args->dbname;
    $cmdline .= " -idformat ". $args->dbformat;
    $cmdline .= " -filenames ". $args->files;
    $cmdline .= " -directory ". $args->seq_dir;
    $cmdline .= " -indexoutdir ". $args->ndx_dir;
    $cmdline .= " -fields ". ( join ",", split " ", $args->fields );

    $cmdline .= " -date ". &Common::Util::current_date_emboss;
    $cmdline .= " -release 1.0";

    $msgs = [];
    &Common::OS::run_command( $cmdline, undef, $msgs );

    return $cmdline;
}
    
sub write_fasta_db_bioperl
{
    # Niels Larsen, April 2007.

    # Uses BioPerl to index a given local sequence file. 
    # TODO: remove this routine

    my ( $class,
         $args,           # Arguments hash
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns 1 or 0.

    my ( $i_file, $i_format, $format, $index, $module, $str, 
         @i_formats, $o_file, $clobber );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ "i_file", "o_prefix" ],
        "S:0" => [ "clobber", "i_format" ],
    });

    $i_file = $args->i_file;
    $i_format = $args->i_format || "fasta";

    if ( defined $args->o_prefix ) {
        $o_file = &Common::Names::strip_suffix( $args->o_prefix ) .".bp_index";
    } else {
        $o_file = &Common::Names::strip_suffix( $i_file ) .".bp_index";
    }

    $clobber = $args->clobber || 0;

    # Formats allowed,

    @i_formats = qw ( Fasta EMBL Swissprot GenBank );
    $format = ( grep /^$i_format$/i, @i_formats )[0];

    if ( not $format )
    {
        $str = join qq (", "), @i_formats;
        &error( qq (Wrong looking input format (i_format) -> "$i_format"\n) 
                                . qq (Choices: "$str".) );
    }

    no strict "refs";
    
    $module = "Bio::Index::$format";
    eval "require $module";
    
    if ( $clobber ) {
        &Common::File::delete_file_if_exists( $o_file );
    }
    
    if ( -e $o_file )
    {
        if ( $msgs ) {
            push @{ $msgs }, [ "Warning", qq (Index exists -> "$o_file") ];
        } else {
            &error( qq (Index exists -> "$o_file") );
        }
    }
    else
    {
        $index = $module->new( $o_file, 'WRITE');
        $index->make_index( $i_file );
    }

    return $o_file;
}

sub write_fasta_from_sims
{
    # Niels Larsen, December 2006.

    # Writes fasta formatted sequences from the db positions in the given
    # list of similarities. It gets the files from the local cache.

    my ( $sims,          # List of similarities
         $o_file,        # Output file
         $args,          # Switches
         ) = @_;

    # 

    my ( $i_close, $o_close, $entry, $sim, $tuple, $id, $seq, $subseqs, 
         $beg, $end );
    
    if ( not ref $o_file )
    {
        if ( $args->{"append"} ) {
            $o_file = &Common::File::get_append_handle( $o_file );
        } else {
            $o_file = &Common::File::get_write_handle( $o_file );
        }

        $o_close = 1;
    }        

    foreach $sim ( @{ $sims } )
    {
        $id = $sim->id2;

        $entry = Seq::IO->read_genbank_entry( $id,
                                              {
                                                  "datatype" => $args->{"datatype"},
                                                  "format" => "bioperl",
                                                  "source" => "local",
                                              });
        
        $seq = $entry->next_seq->seq;
        $subseqs = "";
        
        foreach $tuple ( @{ $sim->locs2 } )
        {
            ( $beg, $end ) = @{ $tuple };
            $subseqs .= substr $seq, $beg, $end-$beg+1;
        }

        $o_file->print( ">$id\n$subseqs\n" );
    }
    
    if ( $o_close ) {
        &Common::File::close_handle( $o_file );
    }

    return;
}

sub write_fasta_from_phylip
{
    # Niels Larsen, April 2008.

    # Writes a fasta file from the given phylip formatted file.

    my ( $class,
         $ifile,
         $ofile,
        ) = @_;

    my ( $ifh, $ofh, $line, $id, $seq );

    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( $ofile );

    $line = <$ifh>;

    while ( defined ( $line = <$ifh> ) )
    {
        chomp $line;

        if ( $line =~ /^(.+)\s+([^ ]+)$/ )
        {
            ( $id, $seq ) = ( $1, $2 );

            $ofh->print( ">$id\n$seq\n" );
        }
        else {
            &error( qq (Wrong looking phylip sequence line -> "$line") );
        }
    }

    $ifh->close;
    $ofh->close;

    return;
}
    
1;

__END__

# sub write_fasta_db
# {
#     # Niels Larsen, April 2010.

#     # Indexes a fasta sequence file. It simply wraps the indexing routine
#     # with a the calling interface wanted by the install module. 

#     my ( $class,
#          $args,           # Arguments hash
#          $msgs,           # Outgoing messages - OPTIONAL
#          ) = @_;

#     # Returns 1 or 0.

#     my ( $i_file, @files );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ "i_file", "o_prefix" ],
#         "S:0" => [ "clobber", "i_format", "datatype" ],
#     });

#     $i_file = $args->i_file;

#     @files = &Seq::Storage::create_index(
#         { 
#             "ifile" => $args->i_file, 
#             "ofile" => $args->o_prefix,
#             "clobber" => $args->clobber || 0,
#         });

#     if ( @files ) {
#         return $files[0];
#     } else {
#         return;
#     }
# }

# sub create_fasta_index
# {
#     # Niels Larsen, June 2005.

#     # Creates a list of [ index, id, beg, end, non ] where index is the entry
#     # number in the file starting at zero, id is the first word in the fasta 
#     # header, beg and end are the byte positions where the sequence starts and
#     # ends in the fasta file (also zero-based), and non is the count of non-bases.

#     my ( $class, 
#          $file,          # Input fasta file
#          $type,          # Data type - OPTIONAL
#          ) = @_;

#     # Returns a list.

#     my ( $fh, $seqO, $seq_str, $seq_count, $seq_len, $byte_beg, $byte_end, 
#          $fh_pos, $seq_codes, $bad_count, $bad_pct, @index, $id, $valid_chars,
#          $module );

#     if ( $type )
#     {
#         $module = Registry::Get->type( $type )->module ."::Seq";
#         $valid_chars = $module->valid_chars();
#     }
#     else {
#         $valid_chars = $class->valid_chars();
#     }

#     $fh = &Common::File::get_read_handle( $file );

#     $fh_pos = 0;
#     $seq_count = 0;

#     while ( $seqO = &Seq::IO::read_seq_fasta( $fh ) )
#     {
#         $id = $seqO->id;
#         $seq_str = $seqO->seq_string;
#         $seq_len = $seqO->seq_len;

#         $bad_count = ( $seq_str =~ s/[^$valid_chars]// ) || 0;

#         $bad_pct = 100.0 * ( $bad_count / $seq_len );
        
#         $byte_beg = $fh_pos + (length $id) + 3;
#         $byte_end = $byte_beg + $seq_len - 1;

#         push @index, [ $id, $seq_count, $byte_beg, $byte_end, $bad_count, $bad_pct ];

#         $seq_count += 1;
#         $fh_pos = $byte_end + 1;
#     }

#     &Common::File::close_handle( $fh );

#     return wantarray ? @index : \@index;
# }

# sub write_fasta_index
# {
#     # Niels Larsen, June 2005.

#     # Writes a fasta index to "$file.index". If no index is given then
#     # one is generated. 

#     my ( $class,
#          $ifile,
#          $index,      # Index structure - OPTIONAL
#          $type,
#          ) = @_;

#     my ( $ofile );

#     if ( not defined $index )
#     {
#         $index = $class->create_fasta_index( $ifile, $type );
#     }

#     $ofile = &File::Basename::dirname( $ifile ) ."/"
#            . &File::Basename::basename( $ifile ) .".index";

#     &Common::File::store_file( $ofile, $index );

#     return $ofile;
# }

# sub write_blastn_db
# {
#     # Niels Larsen, July 2004.

#     # Indexes a given fasta DNA/RNA file for blast search using formatdb. 
#     # The index files will be "$o_prefix.{nhr,nin,nsq}", or if not given,
#     # the suffixes will be appended to the input file prefix.

#     my ( $class,
#          $args,
#          $msgs,          # Outgoing message list - OPTIONAL
#          ) = @_;
    
#     # Returns nothing. 

#     my ( $i_file, $o_prefix, @command, $command, $program, @suffices, $pswitch );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => "i_file",
#         "S:0" => [ qw ( o_prefix clobber datatype ) ],
#     });

#     $i_file = $args->i_file;
#     $o_prefix = $args->o_prefix;

#     if ( not defined $o_prefix ) {
#         $o_prefix = &Common::Names::strip_suffix( $i_file );
#     }

#     $program = "$Common::Config::bin_dir/formatdb";

#     @suffices = qw ( nhr nin nsq );
#     $pswitch = "F";

#     if ( $args->clobber ) {
#         map { &Common::File::delete_file_if_exists( "$o_prefix.$_" ); } @suffices;
#     }
    
#     @command = ( $program, "-p", "$pswitch", "-i", $i_file, "-n", $o_prefix, "-l", "$o_prefix.log" );
#     $command = join " ", @command;

#     if ( system( @command ) != 0 )
#     {
#         $command = join " ", @command;

#         &error( qq (Command failed -> "$command") );
#     }
    
#     &Common::File::delete_file_if_exists( "$o_prefix.log" );

#     return;
# }

# sub write_blastp_db
# {
#     # Niels Larsen, July 2004.

#     # Indexes a given fasta protein file for blast search using formatdb. 
#     # The index files will be "$o_prefix.{phr,pin,psq}", or if not given,
#     # the suffixes will be appended to the input file prefix.

#     my ( $class,
#          $args,
#          $msgs,
#          ) = @_;
    
#     # Returns nothing. 

#     my ( $i_file, $o_prefix, @command, $command, $program, @suffices, $pswitch );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => "i_file",
#         "S:0" => [ qw ( o_prefix clobber datatype ) ],
#     });

#     $i_file = $args->i_file;
#     $o_prefix = $args->o_prefix;

#     if ( not defined $o_prefix ) {
#         $o_prefix = &Common::Names::strip_suffix( $i_file );
#     }

#     $program = "$Common::Config::bin_dir/formatdb";

#     @suffices = qw ( phr pin psq );
#     $pswitch = "T";
    
#     if ( $args->clobber ) {
#         map { &Common::File::delete_file_if_exists( "$o_prefix.$_" ); } @suffices;
#     }
    
#     @command = ( $program, "-p", "$pswitch", "-i", $i_file, "-n", $o_prefix, "-l", "$o_prefix.log" );
#     $command = join " ", @command;

#     if ( system( @command ) != 0 )
#     {
#         $command = join " ", @command;
#         &error( qq (Command failed -> "$command") );
#     }
    
#     &Common::File::delete_file_if_exists( "$o_prefix.log" );

#     return;
# }

# sub split_genbank_file
# {
#     # Niels Larsen, January 2007.

#     # Splits a given file of concatenated genbank entries into individual
#     # files that are named after the VERSION id in each entry. A output 
#     # directory must be given. Returns the ids from the split entries.

#     my ( $i_file,             # Input file
#          $o_dir,              # Output directory
#          $args,               # Arguments to get_handle - OPTIONAL
#          ) = @_;

#     # Returns a list.

#     my ( $ifh, $ofh, $line, @lines, @ids, $o_file, $acc, $gistr, $gi );

#     $ifh = &Common::File::get_read_handle( $i_file );

#     while ( defined ( $line = <$ifh> ) )
#     {
#         if ( $line =~ /^LOCUS / )
#         {
#             @lines = $line;
#             $acc = undef;
#             $gi = undef;

#             while ( defined ( $line = <$ifh> ) and $line !~ /^\/\// )
#             {
#                 if ( $line =~ /^VERSION   / )
#                 {
#                     ( undef, $acc, $gistr ) = ( split " ", $line );

#                     if ( $gistr =~ /^GI:(\d+)$/ ) {
#                         $gi = $1;
#                     } else {
#                         &error( qq (Wrong looking GI string -> "$gistr") );
#                     }

#                     if ( $acc and $gi ) {
#                         push @ids, [ $acc, $gi ];
#                     }
#                 }

#                 push @lines, $line;
#             }

#             push @lines, $line;

#             if ( defined $acc and defined $gi )
#             {
#                 if ( $args->{"gi_file_names"} ) {
#                     $o_file = "$o_dir/$gi";
#                 } else {
#                     $o_file = "$o_dir/$acc";
#                 }
                    
#                 $o_file .= ".gz" if $args->{"compressed"};

#                 $ofh = &Common::File::get_write_handle( $o_file, %{ $args } );
                
#                 $ofh->print( @lines );
#                 &Common::File::close_handle( $ofh );
#             }
#             else {
#                 &Comon::Messages::error( qq (No accession or GI number found) );
#             }
#         }
#     }

#     return wantarray ? @ids : \@ids;
# }

# sub index_dbflat_emboss
# {
#     # Niels Larsen, June 2007.

#     # Returns the number of files and entries processed as a 2-element list.

#     my ( $db,             # Dataset object
#          $args,           # Arguments object
#          $msgs,           # Outgoing messages - OPTIONAL
#         ) = @_;
    
#     # Returns a 2-element list.

#     my ( $src_dir, $ins_dir, @files, $f_count, $e_count, $i, $j, $new_version, 
#          $src_str, $args_c, $cmdline, $text, $file, $ofile );

#     $f_count = 0;     # file count
#     $e_count = 0;     # entry count

#     # Set source and install directories: if new data downloaded then install
#     # in a shadow directory and swap when finished (done below),

#     if ( -r $args->src_dir ."_new" )
#     {
#         $src_dir = $args->src_dir ."_new";
#         $ins_dir = $args->ins_dir ."_new";

#         $new_version = 1;
#     }
#     else 
#     {
#         $src_dir = $args->src_dir;
#         $ins_dir = $args->ins_dir;

#         $new_version = 0;
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>> RELEASE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # If there are real files in download area, import them and "ghost" them,
#     # which means remembering their names and sizes in the file "GHOST_FILES",

#     $src_str = ( split "/", $src_dir )[-1];
#     &echo("   Is there a new release in $src_str ... ");

#     if ( -d $src_dir and
#          @files = &Common::File::list_files( $src_dir, '\.gz$' ) )
#     {
#         &echo_green("yes, ". (scalar @files) . " files\n");

#         &Common::File::create_dir_if_not_exists( $ins_dir );

#         foreach $file ( @files )
#         {
#             &echo("   De-compressing ". $file->{"name"} ." ... ");

#             $ofile = $file->{'name'};
#             $ofile =~ s/\.gz$//;
#             $ofile = "$ins_dir/$ofile";

#             &Common::File::gunzip_file( $file->{"path"}, $ofile );
#             &Common::File::ghost_file( $file->{"path"} );

#             &echo_green( "done\n" );
#         }

#         &Seq::Import::update_emboss_config( $args );
        
#         $cmdline = "$Common::Config::bin_dir/dbxflat";

#         $cmdline .= " -dbname ". $args->dbname;
#         $cmdline .= " -dbresource ". $args->dbname;
#         $cmdline .= " -idformat ". $args->dbformat;
#         $cmdline .= " -filenames ". $args->files;
#         $cmdline .= " -directory ". $ins_dir;
#         $cmdline .= " -indexoutdir ". $ins_dir;
#         $cmdline .= " -fields ". ( join ",", split " ", $args->fields );
#         $cmdline .= " -date ". &Common::Util::current_date_emboss;
#         $cmdline .= " -release 1.0";

#         $msgs = [];
#         &Common::OS::run_command( $cmdline, undef, $msgs );
        
#         $f_count = scalar @files;
#         $e_count = 0;
#     }
#     else {
#         &echo_green("no\n");
#     }

# #     # >>>>>>>>>>>>>>>>>>>>>>>>>> DAILY FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# #     # Same as for release, but in /Daily subdirectory,

# #     $src_str = ( split "/", $src_dir )[-2..-1];
# #     &echo("   Are there pending daily files in $src_str ... ");

# #     if ( -d $src_dir and -d "$src_dir/Daily" and
# #          @files = &Common::File::list_files( "$src_dir/Daily", '\.gz$' ) )
# #     {
# #         &echo_green("yes, ". (scalar @files) . "\n");

# #         $args_c = &Storable::dclone( $args );
# #         $args_c->ins_dir( "$ins_dir/Daily" );

# #         ( $i, $j ) = &Seq::Import::split_dbflat_files( \@files, $args_c );
        
# #         $f_count += $i;
# #         $e_count += $j;
# #     }
# #     else {
# #         &echo_green("no\n");
# #     }


# #     return;


# #     &Seq::Import::write_emboss_index( $conf );
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> SHADOW VERSION <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # If new version, move shadow database into place and delete old,
        
#     if ( $new_version )
#     {
#         &Seq::Import::enable_new_version( $args->src_dir, $args->ins_dir );
#     }

#     return ( $f_count, 0 );
# }
