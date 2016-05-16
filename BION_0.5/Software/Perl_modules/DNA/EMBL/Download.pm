package DNA::EMBL::Download;        # -*- perl -*- 

# OUTDATED.
# Routines that are specific to the EMBL updating process. They
# manage the retrieval and integration of EMBL entries from EBI,
# their primary sources. 

use strict;
use warnings;

use Storable qw ( dclone );
use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_release_lock
                 &create_updates_lock
                 &download_entry
                 &download_entry_soap
                 &download_entry_bioperl
                 &download_release
                 &download_updates
                 &get_local_release_version
                 &get_remote_release_version
                 &list_local_release_files
                 &list_remote_release_files
                 &list_local_updates_files
                 &list_remote_updates_files
                 &release_is_locked
                 &remove_release_lock
                 &remove_updates_lock
                 &updates_are_locked
                 );

use DNA::EMBL::Import;
use Seq::Common;

use Common::Storage;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_release_lock
{
    # Niels Larsen, July 2003.

    # Creates a EMBL/Download/Release directory under the updating 
    # directory. The existence of this directory means data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::log_dir/EMBL/Download/Release" );

    return;
}

sub create_updates_lock
{
    # Niels Larsen, July 2003.

    # Creates a EMBL/Download/Updates directory under the updating 
    # directory. The existence of this directory means data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::log_dir/EMBL/Download/Updates" );

    return;
}

sub download_embl_entry_soap
{
    # Niels Larsen, November 2006.
    
    # Returns en EMBL entry given by its id and puts it in the given 
    # directory as "$id.embl". WARNING: the EBI soap interface is not
    # of quality, it requires huge amounts of memory on the client with
    # a big entry (1.2 gb for a 40 mb file), help messages dont match 
    # reality and everything about it has a sloppy feel. Therefore this
    # routine should probably not be used. But it had to be written to
    # find out. 

    my ( $id,           # EMBL id
         $dir,          # Output directory
         $msgs,         # Error messages
         ) = @_;

    # Returns a hash or a list.

    my ( $soap, $result, $fh, $line );

    if ( not $id ) {
        &error( qq (No id given) );
    }

    if ( not $dir ) {
        &error( qq (No output directory given) );
    } elsif ( not -d $dir ) {
        &error( qq (Directory does not exist -> "$dir") );
    }

    &Common::Config::set_internet_addresses;

    $soap = new SOAP::Lite( uri => 'WSDbfetch', proxy => $Common::Config::embl_dbfetch );

    $result = $soap->call( "fetchData" => "EMBL:$id", "embl", "raw" );

    if ( $result->fault )
    {
        push @{ $msgs }, [ "Error", qq (Could not fetch sequence "$id" from EBI.\n)
                                      ."Code: ". $result->faultcode ."\n"
                                      ."String: ". $result->faultstring ."\n" ];

        return;
    }
    else
    {
        $fh = &Common::File::get_write_handle( "$dir/$id.embl" );

        foreach $line ( @{ $result->result } )
        {
            $fh->print( "$line\n" );
        }

        $fh->close;

        return "$dir/$id.embl";
    }
}

# sub download_entry_soap_old
# {
#     # Niels Larsen, August 2005. 
    
#     # Returns en EMBL entry given by its id. If the second optional argument 
#     # is true it is returned as a parsed hash, otherwise a list of lines. If
#     # a very large entry is requested the routine may fail. TODO

#     my ( $id,           # EMBL id
#          $parse,        # Boolean - OPTIONAL, default 0
#          ) = @_;

#     # Returns a hash or a list.

#     use SOAP::Lite on_fault => sub 
#     { 
#         my( $soap, $res ) = @_;
#         eval { die (ref $res) ? $res->faultdetail : $soap->transport->status };
#         return (ref $res) ? $res : new SOAP::SOM;
#     };

#     my ( $entry, $soap, $result );

#     &Common::Config::set_internet_addresses;

#     $soap = new SOAP::Lite( uri => 'urn:Dbfetch', proxy => $Common::Config::embl_dbfetch );

#     $result = $soap->call( "fetchDataFile" => "EMBL:$id", "embl", "raw" );
    
#     if ( $result->fault )
#     {
#         &error( qq (Could not fetch sequence "$id" from EBI. Error: \n)
#                                   . $result->faultcode ." ". $result->faultstring ."\n" );
#         exit;
#     }
#     elsif ( $parse )
#     {
#         $entry = &DNA::EMBL::Import::parse_entry( $result->result );
#     }
#     else {
#         $entry = $result->result;
#     }

#     return $entry;
# }

sub download_entry_bioperl
{
    my ( $id,
         $msgs,
         ) = @_;

    my ( $embl, $entry, $id2, $ebi_msg );

    require Bio::DB::EMBL;

    $embl = new Bio::DB::EMBL();
    &dump( $embl );
    &dump( $id );

    $entry = $embl->get_Seq_by_acc( $id );

    &dump( $entry );

    if ( $entry )
    {
        if ( $entry->primary_seq->desc =~ /replaced by +([^ ]+)/i ) 
        {
            $id2 = $1;
            $ebi_msg = $entry->primary_seq->desc;
            
            $entry = $embl->get_Seq_by_acc( $id2 );
            
            push @{ $msgs }, [ "Warning", "EMBL entry $id not found. EBI message: $ebi_msg" ];
        }
    }
    else {
        push @{ $msgs }, [ "Error", "EMBL entry $id not found." ];
    }    

    if ( defined $entry ) {
        return $entry;
    } else {
        return;
    }
}


#   # this also returns a Seq object :
#   $seq2 = $gb->get_Seq_by_acc('AF303112');

#   # this returns a SeqIO object, which can be used to get a Seq object :
#   $seqio = $gb->get_Stream_by_id(["J00522","AF303112","2981014"]);
#   $seq3 = $seqio->next_seq;


# sub download_entry_file
# {
#     # Niels Larsen, August 2005. 
    
#     # Writes an EMBL entry given by its id to a specified file. As opposed to 
#     # DNA::EMBL::Download::download_entry this routine will handle very big 
#     # entries. The output is the EMBL text report format as served by EMBL.

#     my ( $id,           # EMBL id
#          $file,         # Output file
#          ) = @_;

#     # Returns a hash or a list.

#     use SOAP::Lite on_fault => sub 
#     { 
#         my( $soap, $res ) = @_;
#         eval { die ref $res ? $res->faultdetail : $soap->transport->status };
#         return ref $res ? $res : new SOAP::SOM;
#     };

#     my ( $entry, $soap, $result );

#     &Common::Config::set_internet_addresses;

#     $soap = new SOAP::Lite( uri => 'urn:Dbfetch', proxy => $Common::Config::embl_dbfetch );

#     $result = $soap->call( "fetchData" => "EMBL:$id", "embl", "raw" );
    
#     if ( $result->fault )
#     {
#         &error( qq (Could not fetch sequence "$id" from EBI. Error: \n)
#                                   . $result->faultcode ." ". $result->faultstring ."\n" );
#         exit;
#     }
#     elsif ( $parse )
#     {
#         $entry = &DNA::EMBL::Import::parse_entry( $result->result );
#     }
#     else {
#         $entry = $result->result;
#     }

#     return $entry;
# }

sub download_release
{
    # Niels Larsen, March 2003.
    
    # This routine downloads all EMBL release files at EBI to 
    # the local server. If a release is found locally with 
    # an up-to-date version number, then only missing files
    # are downloaded or files with a different size. So if 
    # the download was interrupted in the middle of a file
    # (usually out of many), only that file is downloaded 
    # again. If a release is found locally with an outdated 
    # version number, then if we have the local disk space for
    # it, the entire local source directory is deleted and a 
    # new one created. A 'lock file' is placed so that other
    # programs will not start while downloading is going on.
    # Returns the number of files downloaded. 

    my ( $readonly,
          ) = @_;

    # Returns an integer. 

    my ( $space_free, $fill_pct, $fill_pct_f, $r_name, @l_release, 
         @r_release, @l_extra, $uris, $src_dir,
         $r_size, %l_release, $l_file, $r_version, $message, @missing_files,
         $error_type, $file, $count, $l_version, @l_updates, $download_count,
         $l_count, $r_count, $r_file, @l_missing, $l_path, $r_path );

    $error_type = "EMBL DOWNLOAD ERROR";
    $src_dir = "$Common::Config::embl_dir/Release";
    
    # >>>>>>>>>>>>>>> CREATE DIRECTORY IF NOT EXISTS <<<<<<<<<<<<<<<<<

    # Second argument prevents error if directory exists,

    &Common::File::create_dir( $src_dir, 0 );

    # >>>>>>>>>>>>>>>>> CHECK LOCAL FILES ARE CURRENT <<<<<<<<<<<<<<<<

    &echo( "   Is our release version current ... " );
    
    $uris = &Common::Config::get_internet_addresses();
    
    @l_release = &Common::Storage::list_files( $src_dir );
    @r_release = &Common::Storage::list_files( $uris->{"embl_release"} );

    if ( -d "$Common::Config::embl_dir/Updates" ) {
        @l_updates = &Common::Storage::list_files( "$Common::Config::embl_dir/Updates" );
    } else {
        @l_updates = ();
    }

    # >>>>>>>>>>>>>>>>>>>>> VERSION CHECK <<<<<<<<<<<<<<<<<<<<<<<<
    
    # Action below depends on whether there is a later version at
    # the remote site, so we check this first,

    $l_version = &DNA::EMBL::Download::get_local_release_version;
    $r_version = &DNA::EMBL::Download::get_remote_release_version;
    
    if ( $l_version eq $r_version )
    {
         &echo_green( "yes\n" );
    }
    elsif ( $l_version < $r_version )
    {
        &echo_yellow( "NO\n" );
    }
    else
    {
        $message = "
We have EMBL release version $l_version locally, but only release 
$r_version at the provider site. This should of course never happen
and probably indicates a data or software problem.";

        &error( $message, $error_type );
        exit;
    }

    # >>>>>>>>>>>>>>> MAKE LIST OF FILES TO DOWNLOAD <<<<<<<<<<<<<<

    # If we got same version, find the files on the remote server
    # that we dont have locally or that differ in size. This way, 
    # if a transfter went wrong or was interrupted, it can resume. 
    # If release numbers are different, then we delete all local 
    # files AND updates and download everything (see below),

    if ( $l_version == $r_version )
    {
        &echo("   Are we missing files locally ... " );

        @l_missing = &Common::Storage::diff_lists( \@r_release, \@l_release, [ "name", "size" ] );
        
        if ( @l_missing )
        {
            $count = scalar @l_missing;
            &echo_green( "yes, $count\n" );
        }
        else {
            &echo_green( "no\n" );
        }
    }
    else
    {
        &echo("   Locating files to download ... " );

        @l_missing = @r_release;

        if ( scalar @l_missing > 0 )
        {
            $count = scalar @l_missing;
            &echo_green( "found $count\n" );
        }
        else {
            &error( qq (Remote release directory appears empty. This cannot be.) );
            exit;
        }
    }
    
    # There should not be files in the local directory that are not 
    # on the remote directory (for same release, that is). But if there
    # are we print warnings .. 

    if ( $l_version == $r_version )
    {
        &echo( "   Is there a clean download area ... " );
        
        @l_extra = &Common::Storage::diff_lists( \@l_release, \@r_release, [ "name" ] );
        
        if ( @l_extra )
        {
            &echo_yellow( "NO\n" );
            
            foreach $l_file ( @l_extra )
            {
                &echo_yellow( " * " );
                &echo( qq (Please delete: "$l_file->{'path'}"\n) );
            }
        }
        else {
            &echo_green( "yes\n" );
        }
    }

    if ( not @l_missing )
    {
        &echo( "   EMBL release appears up to date ... " );
        &echo_green( "good\n" );

        return;
    }

    # >>>>>>>>>>>>>>>>>>>> ESTIMATE DISK SPACE <<<<<<<<<<<<<<<<<<<<<<<<

    # Before downloading, see if there would be enough space,

    if ( $readonly ) {
        &echo( "   Would there be enough disk space ... " );
    } else {
        &echo( "   Will there be enough disk space ... " );
    }
    
    if ( $l_version < $r_version )
    {
        # This means we need to update the entire local EMBL sources.
        # Below we will erase the outdated local release and download 
        # the entire new release, but first we must check if there is
        # enough space. And if there is not enough space, we leave 
        # the existing local release untouched.

        $space_free = &Common::Storage::predict_space( \@r_release, $src_dir );
        $space_free += &Common::Storage::add_sizes( \@l_updates );
    }
    else
    {
        # This means we have the same version locally as the current remote 
        # one. In this case we will not delete the updates and need not to 
        # add their sizes.
        
        $space_free = &Common::Storage::predict_space( \@r_release, $src_dir );
    }

    $fill_pct = &Common::OS::disk_full_pct( $src_dir, $space_free );
    $fill_pct_f = sprintf "%.1f", $fill_pct;

    if ( $fill_pct > 99 )
    {
        &echo_red( "NO\n" );
        
        $message = qq (
Downloading a new EMBL release would fill the disk to $fill_pct_f%
capacity. Please look for things to delete on this partition,
or add more disk capacity if you must. 
);
        $Common::Config::with_stack_trace = 0;
        &error( $message, $error_type );
        exit;
    }
    elsif ( $fill_pct > 95 )
    {
        &echo_yellow( "barely" );

        if ( $readonly ) {
            &echo( ", would be $fill_pct_f% full\n" );
        } else {
            &echo( ", will be $fill_pct_f% full\n" );
        }            
        
        $message = qq (
Downloading a new EMBL release would fill the disk to $fill_pct_f 
capacity. Please make more disk space available soon. 
);
        &Common::Logs::warning( { "MESSAGE" => $message } );
    }
    else
    {
        &echo_green( "yes" );

        if ( $readonly ) {
            &echo( ", would be $fill_pct_f% full\n" );
        } else {
            &echo( ", will be $fill_pct_f% full\n" );
        }            
    }
    
    # >>>>>>>>>>>>>>>> DELETE LOCAL RELEASE FILES <<<<<<<<<<<<<<<<<
        
    &echo( qq (   How many release files should be deleted ... ) );
    
    $count = 0;
    
    if ( $l_version < $r_version )
    {
        foreach $l_file ( @l_release )
        {
            &Common::Storage::delete_file( $l_file->{"path"} ) if not $readonly;
            $count++;
        }
    }
    else
    {
        foreach $r_file ( @l_missing )
        {
            $l_file = $src_dir . "/" . $r_file->{"name"};
            
            if ( -e $l_file )
            {
                &Common::Storage::delete_file( $l_file ) if not $readonly;
                $count++;
            }
        }
    }
    
    if ( $count > 0 )
    {
        if ( $readonly ) {
            &echo_green( "$count\n");
        } else { 
            &echo_green( "$count, done\n");
        }
    }
    else {
        &echo_green( "none\n" );
    }

    # >>>>>>>>>>>>>>>> DELETE LOCAL UPDATES FILES <<<<<<<<<<<<<<<<<
    
    # Only delete updates if we are going to download a new 
    # release,

    if ( $l_version < $r_version )
    {
        &echo( qq (   How many update files to delete ... ) );
    
        $count = 0;

        foreach $l_file ( @l_updates )
        {
            &Common::Storage::delete_file( $l_file->{"path"} ) if not $readonly;
            $count++;
        }
    
        if ( $count > 0 )
        {
            if ( $readonly ) {
                &echo_green( "$count found\n");
            } else { 
                &echo_green( "$count deleted\n");
            }
        }
        else {
            &echo_green( "none\n" );
        }
    }

    # >>>>>>>>>>>>>>>>>>> DOWNLOAD THE FILES <<<<<<<<<<<<<<<<<<<<<<<
    
    $download_count = 0;
    
    foreach $r_file ( @l_missing )
    {
        $l_path = $src_dir . "/" . $r_file->{"name"};
        $r_path = $r_file->{"path"};

        &echo( qq (   Downloading "$r_path" ... ) );

        if ( $readonly ) 
        {
            &echo_green( "not done\n" );
        }
        else
        {
            &Common::Storage::copy_file( $r_path, $l_path );
            &echo_green( "done\n" );
        }
        
        $download_count++;
    }

    # >>>>>>>>>>>>>>>>>>> VERIFY THE DOWNLOAD <<<<<<<<<<<<<<<<<<<<<<

    if ( not $readonly )
    {
        &echo("   Do all file names and sizes match ... " );

        @r_release = &DNA::EMBL::Download::list_remote_release_files;
        @l_release = &DNA::EMBL::Download::list_local_release_files;
        
        @missing_files = &Common::Storage::diff_lists( \@r_release, \@l_release, [ "name", "size" ] );
        
        if ( @missing_files )
        {
            $count = scalar @missing_files;
            &echo_red( "NO" );
            &echo( ", $count missing\n" );
        }
        else {
            &echo_green( "yes\n" );
        }
    }
}

sub download_updates
{
    # Niels Larsen, March 2003.
    
    # Downloads update files since the last EMBL release at EBI
    # that are missing locally or have a different size.

    my ( $readonly,
          ) = @_;

    # Returns the number of files downloaded. 
    
    my ( $count, $l_file, $r_file, $download_count, $src_dir,
         $space_free, $space_needed, $space_after, $space_total,
         $space_free_c, $space_needed_c, $space_after_c, $space_total_c,
         @l_updates, @r_updates, @l_missing, @l_extra, %l_updates, @l_files, @l_delete,
         $r_name, $r_size, $fill_pct, $fill_pct_f, $message, $error_type, $l_path, $r_path,
         );

    $error_type = "EMBL DOWNLOAD ERROR";
    $src_dir = "$Common::Config::embl_dir/Updates";

    # >>>>>>>>>>>>>>> CREATE DIRECTORY IF NOT EXISTS <<<<<<<<<<<<<<<<<

    # Second argument prevents error if directory exists,

    &Common::File::create_dir( $src_dir, 0 );

    # >>>>>>>>>>>>>>>>> CHECK LOCAL FILES ARE CURRENT <<<<<<<<<<<<<<<<

    &echo( "   Are there new updates ... " );
    
    @l_updates = &DNA::EMBL::Download::list_local_updates_files;
    @r_updates = &DNA::EMBL::Download::list_remote_updates_files;

    @l_missing = &Common::Storage::diff_lists( \@r_updates, \@l_updates, [ "name", "size" ] );
    
    if ( @l_missing )
    {
        $count = scalar @l_missing;
        &echo_green( "yes, $count\n" );
    }
    else {
        &echo_green( "no\n" );
    }

    &echo( "   Is there a clean download area ... " );
    
    @l_files = &Common::Storage::list_files( $src_dir );
    @l_extra = &Common::Storage::diff_lists( \@l_files, \@r_updates, [ "name" ] );

    if ( @l_extra )
    {
        &echo_yellow( "NO\n" );
        
        foreach $l_file ( @l_extra )
        {
            &echo_yellow( " * " );
            &echo( qq (Please delete: "$l_file->{'path'}"\n) );
        }
    }
    else {
        &echo_green( "yes\n" );
    }
    
    if ( not @l_missing )
    {
        return;
    }

    # >>>>>>>>>>>>>>>>>>>> ESTIMATE DISK SPACE <<<<<<<<<<<<<<<<<<<<<<<<

    # Before downloading, see if there would be enough space,
   
    if ( $readonly ) {
        &echo( "   Would there be enough disk space ... " );
    } else {
        &echo( "   Will there be enough disk space ... " );
    }

    $space_free = &Common::Storage::predict_space( \@r_updates, $src_dir );

    $fill_pct = &Common::OS::disk_full_pct( $src_dir, $space_free );
    $fill_pct_f = sprintf "%.1f", $fill_pct;

    if ( $fill_pct > 99 )
    {
        &echo_red( "NO\n" );
        
        $message = qq (
Downloading EMBL updates would fill the disk to $fill_pct_f capacity. 
Please look for things to delete on this partition, or add more 
disk capacity if you must. 
);
        &error( $message, $error_type );
        exit;
    }
    elsif ( $fill_pct > 95 )
    {
        &echo_yellow( "barely" );

        if ( $readonly ) {
            &echo( ", would be $fill_pct_f% full\n" );
        } else {
            &echo( ", will be $fill_pct_f% full\n" );
        }            
        
        $message = qq (
Downloading EMBL updates would fill the disk to $fill_pct_f capacity. 
Please make more disk space available soon. 
);
        &Common::Logs::warning( { "MESSAGE" => $message } );
    }
    else
    {
        &echo_green( "yes" );

        if ( $readonly ) {
            &echo( ", would be $fill_pct_f% full\n" );
        } else {
            &echo( ", will be $fill_pct_f% full\n" );
        }            
    }
    
    # >>>>>>>>>>>>>>>> DELETE LOCAL UPDATES FILES <<<<<<<<<<<<<<<<<
        
    &echo( qq (   How many update files should be deleted ... ) );

    @l_delete = &Common::Storage::both_lists( \@l_updates, \@l_missing, [ "name" ] );
    $count = 0;

    foreach $l_file ( @l_delete )
    {
        &Common::Storage::delete_file( $l_file->{"path"} ) if not $readonly;
        $count++;
    }
    
    if ( $count > 0 )
    {
        if ( $readonly ) {
            &echo_green( "$count found\n");
        } else { 
            &echo_green( "$count, deleted\n");
        }
    }
    else {
        &echo_green( "none\n" );
    }

    # >>>>>>>>>>>>>>>>>>> DOWNLOAD THE FILES <<<<<<<<<<<<<<<<<<<<<<<
    
    $download_count = 0;
    
    foreach $r_file ( @l_missing )
    {
        $l_path = $src_dir . "/" . $r_file->{"name"};
        $r_path = $r_file->{"path"};

        &echo( qq (   Downloading "$r_path" ... ) );

        if ( $readonly ) 
        {
            &echo_green( "not done\n" );
        }
        else
        {
            &Common::Storage::copy_file( $r_path, $l_path );
            &echo_green( "done\n" );
        }
        
        $download_count++;
    }

    # >>>>>>>>>>>>>>>>>>> VERIFY THE DOWNLOAD <<<<<<<<<<<<<<<<<<<<<<

    if ( not $readonly )
    {
        &echo("   Do all file names and sizes match ... " );

        @l_updates = &DNA::EMBL::Download::list_local_updates_files;
        @r_updates = &DNA::EMBL::Download::list_remote_updates_files;

        @l_missing = &Common::Storage::diff_lists( \@r_updates, \@l_updates, [ "name", "size" ] );
        
        if ( @l_missing )
        {
            $count = scalar @l_missing;
            &echo_red( "NO" );
            &echo( ", $count missing\n" );
        }
        else {
            &echo_green( "yes\n" );
        }
    }
}

sub get_local_release_version
{
    # Niels Larsen, March 2003.
    
    # Determines the main release version installed locally.
    
    # Returns an integer. 

    my ( $ldir, @files, $version, $count );
    
    @files = grep { $_ =~ /^Release_/ } map { $_->{"name"} } 
                 &Common::Storage::list_files( $Common::Config::embl_dir ."/Release" );

    $count = scalar @files;

    if ( $count == 1 )
    {
        if ( $files[0] =~ /^Release_(\d+)$/ ) {
            $version = $1;
        } else {
            &error( qq(Local release file looks wrong -> "$files[0]") );
            exit;
        }
    }
    elsif ( $count == 0 )
    {
        $version = 0;
    }
    else
    {
        &error( qq(Expect one but found $count release files\n) );
        exit;
    }

    return int $version;
}

sub get_remote_release_version
{
    # Niels Larsen, March 2003. 

    # Logs into EMBL's ftp site, looks for the version of
    # the latest main release and returns the version number.
    # TODO: add logging, better error checking.  

    # Returns an integer. 

    my ( @files, $count, $version, $uris );

    $uris = &Common::Config::get_internet_addresses();

    @files = grep { $_ =~ /^Release_/ } map { $_->{"name"} }
                &Common::Storage::list_files( $uris->{"embl_release"} );

    $count = scalar @files;
    
    if ( $count == 1 )
    {
        if ( $files[0] =~ /^Release_(\d+)$/ ) {
             $version = $1;
        } else {
            &error( qq(Release file looks wrong -> "$files[0]") );
            exit;
        }
    }
    elsif ( $count == 0 )
    {
        $version = 0;
    }
    else
    {
        &error( qq(Expect one but found $count release files\n) );
        exit;
    }

    return int $version;
}

sub list_local_release_files
{
    # Niels Larsen, March 2003.

    # Lists the file names and attributes of the local EMBL release
    # version. If none are found an empty list is returned. 
    
    # Returns a list.

    my ( $files );
    
    $files = &Common::Storage::list_files( $Common::Config::embl_dir ."/Release" );

    return wantarray ? @{ $files } : $files;
}

sub list_remote_release_files
{
    # Niels Larsen, March 2003.

    # Lists the file names and attributes of the current EMBL 
    # release at EBI. If none are found an empty list is returned. 

    # Returns a list.

    my ( $files, $uris );
    
    $uris = &Common::Config::get_internet_addresses();
    $files = &Common::Storage::list_files( $uris->{"embl_release"} );

    return wantarray ? @{ $files } : $files;
}

sub list_local_updates_files
{
    # Niels Larsen, March 2003.

    # Lists the names and attributes of the local EMBL update files. 
    # If none are found an empty list is returned. 

    # Returns a list.

    my ( $files );
    
    $files = &Common::Storage::list_files( $Common::Config::embl_dir ."/Updates" );

    $files = [ grep { $_->{"name"} =~ /u\d{3,3}\.dat/ } @{ $files } ];
    
    return wantarray ? @{ $files } : $files;
}

sub list_remote_updates_files
{
    # Niels Larsen, March 2003.

    # Lists the names and attributes of the daily update files for 
    # EMBL at EBI since last major release. If none are found an
    # empty list is returned. 

    # Returns a list.

    my ( $files, $uris );
    
    $uris = &Common::Config::get_internet_addresses();
    $files = &Common::Storage::list_files( $uris->{"embl_updates"} );

    $files = [ grep { $_->{"name"} =~ /u\d{3,3}\.dat/ } @{ $files } ];

    return wantarray ? @{ $files } : $files;
}

sub release_is_locked 
{
    # Niels Larsen, July 2003.

    # Checks if there is a EMBL/Download/Release directory under the 
    # updating directory of the system. 

    # Returns nothing.

    my $dir = "$Common::Config::log_dir/EMBL/Download/Release";

    if ( -e $dir ) {
        return 1;
    } else {
        return;
    }
}

sub remove_release_lock
{
    # Niels Larsen, July 2003.
    
    # Deletes a EMBL/Download/Release directory from the updating directory. 
    # Errors are thrown if the directory is not empty or if it could not be
    # deleted. 
    
    # Returns nothing. 

    my ( $dir );

    $dir = "$Common::Config::log_dir/EMBL/Download/Release";

    if ( @{ &Common::File::list_all( $dir ) } )
    {
        &error( qq (Directory is not empty -> "$dir") );
    }
    elsif ( not rmdir $dir )
    {
        &error( qq (Could not remove lock directory "$dir") );
    }
    else 
    {
        foreach $dir ( "$Common::Config::log_dir/EMBL/Download",
                       "$Common::Config::log_dir/EMBL",
                       "$Common::Config::log_dir" )
        {
            if ( not @{ &Common::File::list_all( $dir ) } ) {
                if ( not rmdir $dir ) {
                    &error( qq (Could not remove lock directory "$dir") );
                }
            }
        }
    }

    return;
}

sub remove_updates_lock
{
    # Niels Larsen, July 2003.
    
    # Deletes a EMBL/Download/Updates directory from the updating directory. 
    # Errors are thrown if the directory is not empty or if it could not be
    # deleted. 
    
    # Returns nothing. 

    my ( $dir );

    $dir = "$Common::Config::log_dir/EMBL/Download/Updates";

    if ( @{ &Common::File::list_all( $dir ) } )
    {
        &error( qq (Directory is not empty -> "$dir") );
    }
    elsif ( not rmdir $dir )
    {
        &error( qq (Could not remove lock directory "$dir") );
    }
    else 
    {
        foreach $dir ( "$Common::Config::log_dir/EMBL/Download",
                       "$Common::Config::log_dir/EMBL",
                       "$Common::Config::log_dir" )
        {
            if ( not @{ &Common::File::list_all( $dir ) } ) {
                if ( not rmdir $dir ) {
                    &error( qq (Could not remove lock directory "$dir") );
                }
            }
        }
    }

    return;
}

sub updates_are_locked 
{
    # Niels Larsen, July 2003.

    # Checks if there is a EMBL/Download/Updates directory under the 
    # updating directory of the system. 

    # Returns nothing.

    my $dir = "$Common::Config::log_dir/EMBL/Download/Updates";

    if ( -e $dir ) {
        return 1;
    } else {
        return;
    }
}

1;
