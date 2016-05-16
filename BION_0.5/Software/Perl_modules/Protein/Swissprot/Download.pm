package Protein::Swissprot::Download;        # -*- perl -*- 

# Routines that are specific to the Swissprot updating process. 
# They manage the retrieval of Swissprot entries from Expasy.

use strict;
use warnings;

use Storable qw ( dclone );
use Shell; 

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &download_release

                 &log_error

                 &create_lock
                 &remove_lock
                 &is_locked
                 );

use Common::Storage;
use Common::Messages;
use Common::Config;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub download_release
{
    # Niels Larsen, March 2003.
    
    # Downloads Swissprot release files. It simply copies all files 
    # from a configured directory location (sp_tr_nrdb) that have 
    # different dates, names and sizes. 

    my ( $readonly,
          ) = @_;

    # Returns an integer. 

    my ( $space_free, $fill_pct, $fill_pct_f, $r_name, @l_release, 
         @r_release, @l_extra, $uris,
         $r_size, %l_release, $l_file, $r_version, $message, @missing_files,
         $error_type, $file, $count, $l_version, @l_updates, $download_count,
         $l_count, $r_count, $r_file, @l_missing, $l_path, $r_path );

    $error_type = "SWISSPROT DOWNLOAD ERROR";
    
    # Second argument prevents error if directory exists,

    &Common::File::create_dir( $Common::Config::swissprot_rel_dir, 0 );

    $uris = &Common::Config::get_internet_addresses();

    @l_release = &Common::Storage::list_files( $Common::Config::swissprot_rel_dir );
    @r_release = &Common::Storage::list_files( $uris->{"swissprot_release"} );

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

    if ( not @l_missing )
    {
        &echo( "   Swissprot release appears up to date ... " );
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
    
    $space_free = &Common::Storage::predict_space( \@r_release, $Common::Config::swissprot_rel_dir );
    $space_free += &Common::Storage::add_sizes( \@l_release );

    $fill_pct = &Common::OS::disk_full_pct( $Common::Config::swissprot_rel_dir, $space_free );
    $fill_pct_f = sprintf "%.1f", $fill_pct;

    if ( $fill_pct > 99 )
    {
        &echo_red( "NO\n" );
        
        $message = qq (
Downloading a new Swissprot release would fill the disk to $fill_pct_f%
capacity. Please look for things to delete on this partition,
or add more disk capacity if you must. 
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
Downloading a new Swissprot release would fill the disk to $fill_pct_f 
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
    
    foreach $r_file ( @l_missing )
    {
        $l_file = $Common::Config::swissprot_rel_dir . "/" . $r_file->{"name"};
        
        if ( -e $l_file )
        {
            &Common::Storage::delete_file( $l_file ) if not $readonly;
            $count++;
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

    # >>>>>>>>>>>>>>>>>>> DOWNLOAD THE FILES <<<<<<<<<<<<<<<<<<<<<<<
    
    $download_count = 0;
    
    foreach $r_file ( @l_missing )
    {
        $l_path = $Common::Config::swissprot_rel_dir . "/" . $r_file->{"name"};
        $r_path = $r_file->{"path"};

        &echo( qq (   Downloading "$r_file->{'name'}" ... ) );

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

        @r_release = &Common::Storage::list_files( $uris->{"swissprot_release"} );
        @l_release = &Common::Storage::list_files( $Common::Config::swissprot_rel_dir );

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

sub log_error
{
    # Niels Larsen, July 2003.
    
    # Appends a given message to an ERRORS file in the Swissprot/Download
    # sub-directory under the configured general log directory. 

    my ( $text,   # Error message
         $type,   # Error category - OPTIONAL
         ) = @_;

    # Returns nothing.

    $text =~ s/\n/ /g;
    $type = "SWISSPROT DOWNLOAD ERROR" if not $type;

    my ( $time_str, $script_pkg, $script_file, $script_line, $log_dir, $log_file );

    $time_str = &Common::Util::epoch_to_time_string();
    
    ( $script_pkg, $script_file, $script_line ) = caller;
    
    $log_dir = "$Common::Config::log_dir/Swissprot/Download";
    $log_file = "$log_dir/ERRORS";

    &Common::File::create_dir( $log_dir, 0 );

    if ( open LOG, ">> $log_file" )
    {
        print LOG "$time_str\t$script_pkg\t$script_file\t$script_line\t$type\t$text\n";
        close LOG;
    }
    else {
        &error( qq (Could not append-open "$log_file") );
    }

    return;
}
    
sub create_lock
{
    # Niels Larsen, July 2003.

    # Creates a Swissprot/Download subdirectory under the configured scratch
    # directory. The existence of this directory means Swissprot files are
    # being downloaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::log_dir/Swissprot/Download" );

    return;
}

sub remove_lock
{
    # Niels Larsen, July 2003.
    
    # Deletes a Swissprot/Download subdirectory from the configured scratch
    # directory. Errors are thrown if the directory is not empty or if
    # it could not be deleted. 

    # Returns nothing. 

    my ( $dir );

    $dir = "$Common::Config::log_dir/Swissprot/Download";

    if ( -e $dir ) {
        &Common::File::delete_dir_tree( $dir );
    }

    $dir = "$Common::Config::log_dir/Swissprot";

    if ( -e $dir and not @{ &Common::File::list_files( $dir ) } and not rmdir $dir )
    {
        &error( qq (Could not remove lock directory "$dir") );
    }
        
    return;
}

sub is_locked 
{
    # Niels Larsen, July 2003.

    # Checks if there is a Swissprot/Download subdirectory under the scratch
    # directory of the system. 

    # Returns nothing.

    my $lock_dir = "$Common::Config::log_dir/Swissprot/Download";

    if ( -e $lock_dir ) {
        return 1;
    } else {
        return;
    }
}

1;
