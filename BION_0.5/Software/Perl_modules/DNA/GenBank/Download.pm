package DNA::GenBank::Download;        # -*- perl -*- 

# Routines that are specific to the GenBank updating process. They
# manage the retrieval and integration of GenBank entries from NCBI,
# their primary sources. 

use strict;
use warnings;
use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &download_release
                 &download_updates

                 &list_local_release_files
                 &list_remote_release_files
                 &list_local_updates_files
                 &list_remote_updates_files

                 &get_local_release_version
                 &get_remote_release_version

                 &create_release_lock
                 &delete_release_lock
                 &release_is_locked

                 &create_updates_lock
                 &delete_updates_lock
                 &updates_are_locked
                 );

use Shell; 
use Common::Storage;
use Data::Dumper;

use Common::Messages;
use Common::Config;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub download_release
{
    # Niels Larsen, March 2003.
    
    # This routine downloads all GenBank release files at NCBI
    # to the local server. If a release is found locally with 
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
         @r_release, @l_extra, $uris,
         $r_size, %l_release, $l_file, $r_version, $message, @missing_files,
         $error_type, $file, $count, $l_version, @l_updates, $download_count,
         $l_count, $r_count, $r_file, @l_missing, $l_path, $r_path );

    $error_type = "GENBANK DOWNLOAD ERROR";

    $uris = &Common::Config::get_internet_addresses();
    
    # >>>>>>>>>>>>>>> CREATE DIRECTORY IF NOT EXISTS <<<<<<<<<<<<<<<<<

    # Second argument prevents error if directory exists,

    &Common::File::create_dir( $Common::Config::gb_rel_dir, 0 );
    &Common::File::create_dir( $Common::Config::gb_upd_dir, 0 );

    # >>>>>>>>>>>>>>>>> CHECK LOCAL FILES ARE CURRENT <<<<<<<<<<<<<<<<

    &echo( "   Is our release version current ... " );
    
    @l_release = &Common::Storage::list_files( $Common::Config::gb_rel_dir );
    @r_release = &Common::Storage::list_files( $uris->{"genbank_release"} );
    
    @l_updates = &Common::Storage::list_files( $Common::Config::gb_upd_dir );

    # >>>>>>>>>>>>>>>>>>>>> VERSION CHECK <<<<<<<<<<<<<<<<<<<<<<<<
    
    # Action below depends on whether there is a later version at
    # the remote site, so we check this first,

    $l_version = &DNA::GenBank::Download::get_local_release_version;
    $r_version = &DNA::GenBank::Download::get_remote_release_version;
    
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
We have GenBank release version $l_version locally, but only release 
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
        &echo( "   GenBank release appears up to date ... " );
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
        # This means we need to update the entire local GenBank sources.
        # Below we will erase the outdated local release and download 
        # the entire new release, but first we must check if there is
        # enough space. And if there is not enough space, we leave 
        # the existing local release untouched.

        $space_free = &Common::Storage::predict_space( \@r_release, $Common::Config::gb_rel_dir );
        $space_free += &Common::Storage::add_sizes( \@l_updates );
    }
    else
    {
        # This means we have the same version locally as the current remote 
        # one. In this case we will not delete the updates and need not to 
        # add their sizes.
        
        $space_free = &Common::Storage::predict_space( \@r_release, $Common::Config::gb_rel_dir );
    }

    $fill_pct = &Common::OS::disk_full_pct( $Common::Config::gb_rel_dir, $space_free );
    $fill_pct_f = sprintf "%.1f", $fill_pct;

    if ( $fill_pct > 99 )
    {
        &echo_red( "NO\n" );
        
        $message = qq (
Downloading a new GenBank release would fill the disk to $fill_pct_f%
capacity. Please look for things to delete on this partition,
or add more disk capacity if you must. 
);
        $Common::Config::with_stack_trace = 0;
        $Common::Config::with_comment = 0;
        &error( $message, $error_type );
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
Downloading a new GenBank release would fill the disk to $fill_pct_f 
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
            $l_file = $Common::Config::gb_rel_dir . "/" . $r_file->{"name"};
            
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
        $l_path = $Common::Config::gb_rel_dir . "/" . $r_file->{"name"};
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

        @r_release = &DNA::GenBank::Download::list_remote_release_files;
        @l_release = &DNA::GenBank::Download::list_local_release_files;
        
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
    
    # Downloads GenBank update files that are missing locally or have
    # a different size.

    my ( $readonly,
          ) = @_;

    # Returns the number of files downloaded. 
    
    my ( $count, $l_file, $r_file, $download_count,
         $space_free, $space_needed, $space_after, $space_total,
         $space_free_c, $space_needed_c, $space_after_c, $space_total_c,
         @l_updates, @r_updates, @l_missing, @l_extra, %l_updates, @l_files, @l_delete,
         $r_name, $r_size, $fill_pct, $fill_pct_f, $message, $error_type, $l_path, $r_path,
         );

    $error_type = "GENBANK DOWNLOAD ERROR";

    # >>>>>>>>>>>>>>> CREATE DIRECTORY IF NOT EXISTS <<<<<<<<<<<<<<<<<

    # Second argument prevents error if directory exists,

    &Common::File::create_dir( $Common::Config::gb_upd_dir, 0 );

    # >>>>>>>>>>>>>>>>>> CHECK LOCAL VS REMOTE FILES <<<<<<<<<<<<<<<<<<<<

    &echo( "   Are there new updates ... " );
    
    @l_updates = &DNA::GenBank::Download::list_local_updates_files;
    @r_updates = &DNA::GenBank::Download::list_remote_updates_files;

    @l_missing = &Common::Storage::diff_lists( \@r_updates, \@l_updates, [ "name", "size" ] );
    
    if ( @l_missing ) {
        &echo_green( "yes\n" );
    } else {
        &echo_green( "no\n" );
    }

    &echo( "   Is there a clean download area ... " );
    
    @l_files = &Common::Storage::list_files( $Common::Config::gb_upd_dir );
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
    
    if ( not @l_missing ) {
        return;
    }

    # >>>>>>>>>>>>>>>>>>>> ESTIMATE DISK SPACE <<<<<<<<<<<<<<<<<<<<<<<<

    # Before downloading, see if there would be enough space,
   
    if ( $readonly ) {
        &echo( "   Would there be enough disk space ... " );
    } else {
        &echo( "   Will there be enough disk space ... " );
    }

    $space_free = &Common::Storage::predict_space( \@r_updates, $Common::Config::gb_upd_dir );

    $fill_pct = &Common::OS::disk_full_pct( $Common::Config::gb_upd_dir, $space_free );
    $fill_pct_f = sprintf "%.1f", $fill_pct;

    if ( $fill_pct > 99 )
    {
        &echo_red( "NO\n" );
        
        $message = qq (
Downloading GenBank updates would fill the disk to $fill_pct_f% capacity. 
Please look for things to delete on this partition, or add more 
disk capacity if you must. 
);
        &error( $message, $error_type );
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
Downloading GenBank updates would fill the disk to $fill_pct_f% capacity. 
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
        $l_path = $Common::Config::gb_upd_dir . "/" . $r_file->{"name"};
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

        @l_updates = &DNA::GenBank::Download::list_local_updates_files;
        @r_updates = &DNA::GenBank::Download::list_remote_updates_files;

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

sub list_local_release_files
{
    # Niels Larsen, March 2003.

    # Lists the file names and attributes of the local Genbank release
    # version. If none are found an empty list is returned. 
    
    # Returns a list.

    my ( $files );
    
    $files = &Common::Storage::list_files( $Common::Config::gb_rel_dir );

    return wantarray ? @{ $files } : $files;
}

sub list_remote_release_files
{
    # Niels Larsen, March 2003.

    # Lists the file names and attributes of the current GenBank
    # release at NCBI. If none are found an empty list is returned. 

    # Returns a list.

    my ( $files, $uris );

    $uris = &Common::Config::get_internet_addresses();

    $files = &Common::Storage::list_files( $uris->{"genbank_release"} );

    return wantarray ? @{ $files } : $files;
}

sub list_local_updates_files
{
    # Niels Larsen, March 2003.

    # Lists the names and attributes of the local GenBank update 
    # files. If none are found an empty list is returned. 

    # Returns a list.

    my ( $files );
    
    $files = &Common::Storage::list_files( $Common::Config::gb_upd_dir );

    $files = [ grep { $_->{"name"} =~ /nc\d+\.flat/ } @{ $files } ];
    
    return wantarray ? @{ $files } : $files;
}

sub list_remote_updates_files
{
    # Niels Larsen, March 2003.

    # Lists the names and attributes of the daily update files for 
    # GenBank at NCBI since last major release. If none are found 
    # an empty list is returned. 

    # Returns a list.

    my ( $files, $uris );
    
    $uris = &Common::Config::get_internet_addresses();

    $files = &Common::Storage::list_files( $uris->{"genbank_release"} );

    $files = [ grep { $_->{"name"} =~ /nc\d+\.flat/ } @{ $files } ];

    return wantarray ? @{ $files } : $files;
}

sub get_local_release_version
{
    # Niels Larsen, April 2003.
    
    # Determines the main release version installed locally.
    
    # Returns an integer.

    my ( @files, $count, $content, $version );

    @files = grep { $_ =~ /README.genbank$/ } map { $_->{"path"} }
                    &Common::Storage::list_files( $Common::Config::gb_rel_dir );
    
    $count = scalar @files;
    
    if ( $count == 1 )
    {
        $content = ${ &Common::Storage::read_file( $files[0] ) };

        if ( $content =~ /GenBank Flat File Release (\d+)\./ )
        {
            $version = $1;
        } 
        else {
            &error( qq (Could not find release version number in the file\n"$files[0]") );
        }
    }
    elsif ( $count == 0 ) {
        $version = 0;
    }
    else {
        &error( qq (Found $count release version files\n) );
    }

    return int $version;
}

sub get_remote_release_version
{
    # Niels Larsen, April 2003. 

    # Logs into Genbank's ftp site, looks for the version of the latest 
    # main release and returns the version number. 

    # Returns an integer. 

    my ( @files, $count, $content, $version, $uris );

    $uris = &Common::Config::get_internet_addresses();

    @files = grep { $_ =~ /README.genbank$/ } map { $_->{"path"} }
                    &Common::Storage::list_files( $uris->{"genbank_release"} );
    
    $count = scalar @files;
    
    if ( $count == 1 )
    {
        $content = ${ &Common::Storage::read_file( $files[0] ) };

        if ( $content =~ /GenBank Flat File Release (\d+)\./ )
        {
            $version = $1;
        } 
        else {
            &error( qq (Could not find release version number in the file\n"$files[0]") );
        }
    }
    else {
        &error( qq(Found $count release version files\n) );
    }

    return int $version;
}

sub create_release_lock
{
    # Niels Larsen, July 2003.

    # Creates a GenBank/Download/Release directory under the updating 
    # directory. The existence of this directory means data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::log_dir/GenBank/Download/Release" );

    return;
}

sub release_is_locked 
{
    # Niels Larsen, July 2003.

    # Checks if there is a GenBank/Download/Release directory under the 
    # updating directory of the system. 

    # Returns nothing.

    my $dir = "$Common::Config::log_dir/GenBank/Download/Release";

    if ( -e $dir ) {
        return 1;
    } else {
        return;
    }
}

sub remove_release_lock
{
    # Niels Larsen, July 2003.
    
    # Deletes a GenBank/Download/Release directory from the updating directory. 
    # Errors are thrown if the directory is not empty or if it could not be
    # deleted. 
    
    # Returns nothing. 

    my ( $dir );

    $dir = "$Common::Config::log_dir/GenBank/Download/Release";

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
        foreach $dir ( "$Common::Config::log_dir/GenBank/Download",
                       "$Common::Config::log_dir/GenBank",
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

sub create_updates_lock
{
    # Niels Larsen, July 2003.

    # Creates a GenBank/Download/Updates directory under the updating 
    # directory. The existence of this directory means data are being 
    # loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::log_dir/GenBank/Download/Updates" );

    return;
}

sub updates_are_locked 
{
    # Niels Larsen, July 2003.

    # Checks if there is a GenBank/Download/Updates directory under 
    # the updating directory of the system. 

    # Returns nothing.

    my $dir = "$Common::Config::log_dir/GenBank/Download/Updates";

    if ( -e $dir ) {
        return 1;
    } else {
        return;
    }
}

sub remove_updates_lock
{
    # Niels Larsen, July 2003.
    
    # Deletes a GenBank/Download/Updates directory from the updating directory. 
    # Errors are thrown if the directory is not empty or if it could not be
    # deleted. 
    
    # Returns nothing. 

    my ( $dir );

    $dir = "$Common::Config::log_dir/GenBank/Download/Updates";

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
        foreach $dir ( "$Common::Config::log_dir/GenBank/Download",
                       "$Common::Config::log_dir/GenBank",
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

1;
