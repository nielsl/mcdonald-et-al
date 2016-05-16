package Common::Download;     #  -*- perl -*-

# Download related routines. They print messages by default, but these 
# can be switched off by setting $Common::Config::silent to 1.

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use Filesys::Df;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &_download_file
                 &download_file
                 &download_files
                 &_estimate_disk_space
                 &_missing_files
                 );

use Common::Config;
use Common::Messages;

use Common::Storage;
use Common::OS;

use Registry::Get;
use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub download_file
{
    # Niels Larsen, April 2010.

    # Downloads a given remote path to a given local file path. The directory
    # part of the local file path must exist. Multiple downloads into the same 
    # directory may create chaos; this is prevented by writing a file named 
    # "DOWNLOADING" into the directory before copying starts, and deleting it 
    # when done. Returns 1 on success, 0 on failure.

    my ( $r_path,      # Remote file file
         $l_path,      # Local file path
         $force,       # Overwrites old file if exists - OPTIONAL (0)
         $silent,      # Suppresses messages - OPTIONAL (0)
        ) = @_;

    # Returns 1 or 0.

    my ( $r_name, $busy_file, $tmp_path, $l_dir, $l_name );

    $force //= 0;
    $silent //= 0;

    $r_name = &File::Basename::basename( $r_path );
    $l_name = &File::Basename::basename( $l_path );
    $l_dir = &File::Basename::dirname( $l_path );

    if ( not $force and -e $l_path ) {
        &error( qq (Local file exists -> "$l_path") );
    }

    $silent or &echo( qq (   Downloading "$r_path" ... ) );

    $busy_file = "$l_dir/DOWNLOADING";
    &Common::File::write_file( $busy_file, "$r_path\n" );
    
    $tmp_path = "$l_dir/$r_name". ".new";
    $l_path = "$l_dir/$r_name";
    
    &Common::File::delete_file_if_exists( $tmp_path );

    {
        local $Common::Messages::silent = 1;
        &Common::Storage::copy_file( $r_path, $tmp_path );
    }
    
    if ( $force ) {
        &Common::File::delete_file_if_exists( $l_path );
    }
    
    if ( not rename $tmp_path, $l_path ) {
        &error( qq (Could not rename "$tmp_path" to "$l_path") );
    }
    
    &Common::File::delete_file( $busy_file );
    
    $silent or &echo_green( "done\n" );
    
    return 1;   
}
    
sub download_files
{
    # Niels Larsen, April 2005.

    # Downloads a given list of remote files into a given local directory. If 
    # the given list is a directory, all regular files in this directory (no
    # directories or links) are downloaded. With the readonly options messages
    # are printed but no files are downloaded. With the force option, local
    # files with the same name as the remote files are deleted first. The 
    # routine checks if there are enough disk space for the download. All 
    # messages from the routine can be turned off by setting 
    # $Config::Messages::silent to 1.

    my ( $r_files,     # Remote files or directory
         $l_dir,       # Local directory
         $readonly,    # No download, only messages
         $force,       # Deletes local files with same name
         $keys,        # List of keys e.g. [ "name", "size" ]
         ) = @_;

    # Returns nothing. 

    my ( $uris, @l_files, @l_missing, @l_extra, $l_file, $r_file, $l_disk,
         $delete_l_dir, $space_free, $fill_pct, $fill_pct_f, $count,
         $l_path, $r_path, $r_name, %r_files, $tmp_path );

    $readonly = 0 if not defined $readonly;
    $force = 0 if not defined $force;
    $keys ||= [ "name", "size" ];

    $l_dir = &Common::File::resolve_links( $l_dir, 1 );

    if ( not $readonly ) {
        &Common::File::create_dir_if_not_exists( $l_dir );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST REMOTE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Remote files can be given as a list or as a directory (from which all
    # files are then used),

    if ( defined $r_files )
    {
        if ( ref $r_files )
        {
            if ( (scalar @{ $r_files }) == 0 ) {
                &error( qq (The given remote file list is empty) );
            }
        }
        else
        {
            &echo( "   Listing remote files ... " );
            
            $r_files = &Common::Storage::list_files( $r_files );

            &echo_green( "found ". scalar @{ $r_files } );

            if ( (scalar @{ $r_files }) == 0 ) {
                &error( qq (No files in the given directory -> "$r_files") );
            }
        }
    }
    else {
        &error( qq (No remote file list or directory given) );
    }

    # >>>>>>>>>>>>>>>>>> COMPARING LOCAL AND REMOTE FILES <<<<<<<<<<<<<<<<<<<<<

    # Find which files are missing locally, by name and size,

    @l_missing = &Common::Download::_missing_files( $r_files, $l_dir, $keys );

    # >>>>>>>>>>>>>>>>>>>>>> CHECK EXTRA LOCAL FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Is download area clean ... " );
   
    @l_files = &Common::Storage::list_files( $l_dir );

    @l_extra = &Common::Storage::diff_lists( \@l_files, $r_files, [ "name" ] );
    @l_extra = grep { $_->{"name"} !~ /^TIME_STAMP|GHOST_FILES$/ } @l_extra;
    
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
    
    # >>>>>>>>>>>>>>>>>>>>>>> CHECK WE HAVE ENOUGH SPACE <<<<<<<<<<<<<<<<<<<<<<<<

    &Common::Download::_estimate_disk_space( $r_files, $l_dir, $readonly );

    # >>>>>>>>>>>>>>>>>>> DELETE LOCAL RELEASE FILES <<<<<<<<<<<<<<<<<<<<

    &echo( qq (   How many local files have wrong size ... ) );
    
    $count = 0;
    
    foreach $r_file ( @l_missing )
    {
        $l_file = "$l_dir/" . $r_file->{"name"};
        
        if ( -e $l_file )
        {
            &Common::Storage::delete_file( $l_file ) if not $readonly;
            $count++;
        }
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

    # Copy the files,

    $count = 0;

    foreach $r_file ( @l_missing )
    {
        $r_path = $r_file->{"path"};
        $r_name = &File::Basename::basename( $r_path );

        $l_path = $l_dir ."/$r_name";

        &echo( qq (   Downloading "$r_path" ... ) );

        if ( $readonly ) 
        {
            &echo_green( "skipped\n" );
        }
        else
        {
            if ( &Common::Download::download_file( $r_path, $l_path, $force, 1 ) )
            {
                $count += 1;
                &echo_green( "done\n" );
            }
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>> VERIFY DOWNLOAD IF POSSIBLE <<<<<<<<<<<<<<<<<<<<<<<

    # Check that local file sizes match the remote ones. However when files are
    # served by Apache or by a CMS, then exact sizes often cannot be gotten, so
    # we skip in that case.
    
    if ( not $readonly and not grep { $_->{"path"} =~ /^http:/ } @{ $r_files } )
    {
        &echo("   Do all file names and sizes match ... " );

        @l_files =&Common::Storage::list_files( $l_dir );
        push @l_files, &Common::File::list_ghosts( $l_dir );

        @l_missing = &Common::Storage::diff_lists( $r_files, \@l_files, $keys );

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

    return $count;
}

sub _estimate_disk_space
{
    # Niels Larsen, May 2009.

    # Checks if a list of remote files will fit on the local disk that belongs
    # to the local directory given. Returns the expected fill-percentage of the
    # disk and aborts/warns if over/close to full. 

    my ( $r_files,
         $l_dir,
         $readonly,
        ) = @_;

    # Return a number.

    require Common::Logs;

    my ( $fill_pct, $fill_pct_f, $msg, $space_free );

    if ( $readonly ) {
        &echo( "   Would there be space ... " );
    } else {
        &echo( "   Will there be space ... " );
    }

    $space_free = &Common::Storage::predict_space( $r_files, $l_dir );

    $fill_pct = &Common::OS::disk_full_pct( $l_dir, $space_free );
    $fill_pct_f = sprintf "%.1f", $fill_pct;

    if ( $fill_pct > 99 )
    {
        &echo_red( "NO\n" );
        
        $msg = qq (
Downloading a new release would fill the disk to $fill_pct_f%
capacity. Please look for things to delete on this partition,
or add more disk capacity if you must. 
);
        &error( $msg );
    }
    elsif ( $fill_pct > 95 )
    {
        &echo_yellow( "barely" );

        if ( $readonly ) {
            &echo( ", would be $fill_pct_f% full\n", 0 );
        } else {
            &echo( ", will be $fill_pct_f% full\n", 0 );
        }            
        
        $msg = qq (
Downloading a new release would fill the disk to $fill_pct_f%
capacity. Please make more disk space available soon. 
);
        &Common::Logs::warning( { "MESSAGE" => $msg } );
    }
    else
    {
        &echo_green( "yes" );

        if ( $readonly ) {
            &echo( ", would be $fill_pct_f% full\n", 0 );
        } else {
            &echo( ", will be $fill_pct_f% full\n", 0 );
        }            
    }
    
    return $fill_pct;
}
         
sub _missing_files
{
    # Niels Larsen, May 2009.

    # 
    my ( $r_files,
         $l_dir,
         $keys,
        ) = @_;

    my ( @l_files, %r_files, $count, $msg, @l_missing );

    if ( -d $l_dir )
    {
        &echo( "   How many local files to update ... " );

        @l_files = &Common::Storage::list_files( $l_dir );
        push @l_files, &Common::File::list_ghosts( $l_dir );
        
        %r_files = map { $_->{"name"}, 1 } @{ $r_files };
        
        $count = 0;
        map { $count += 1 if $r_files{ $_->{"name"} } } @l_files;

        if ( @l_files and $count == 0 )
        {
            $msg = qq (
Local and remote files have all different names.
This is usually a sign that the URL has changed.
Please check. If URL is ok, then make this message
go away by deleting all local files.
);
            &error( $msg );
        }

        @l_missing = &Common::Storage::diff_lists( $r_files, \@l_files, $keys );

        if ( @l_missing )
        {
            if ( scalar @l_missing > 0 )
            {
                $count = scalar @l_missing;
                &echo_green( "$count\n" );
            }
            else {
                &error( qq (Remote release directory appears empty. This cannot be.) );
            }
        }
        else {
            &echo_green( "none\n" );
        }
    }
    else
    {
        &echo( "   All remote files will be fetched ... " );
        @l_missing = @{ $r_files };
        &echo_green( (scalar @l_missing) ." \n" );
    }

    return wantarray ? @l_missing : \@l_missing;
}

1;

__END__


# sub _download_file
# {
#     # Niels Larsen, May 2009.

#     # Does the act of downloading a given file to a given directory. 
#     # The old file, if it exists, is only overwritten if the download
#     # went well. Returns 1 if success, 0 if not. 

#     my ( $r_file,     # Remote file object
#          $l_dir,      # Local directory path
#          $readonly,
#         ) = @_;

#     my ( $r_path, $r_name, $busy_file, $tmp_path, $l_path, $count );

#     $r_path = $r_file->{"path"};
#     $r_name = $r_file->{"name"};

#     &echo( qq (   Downloading "$r_path" ... ) );

#     $count = 0;

#     if ( $readonly )
#     {
#         &echo_yellow( "skipped\n" );
#     }
#     else
#     {
#         $busy_file = "$l_dir/DOWNLOADING";
#         &Common::File::write_file( $busy_file, "$r_path\n" );

#         $tmp_path = "$l_dir/$r_name". ".new";
#         $l_path = "$l_dir/$r_name";
        
#         &Common::File::delete_file_if_exists( $tmp_path );
        
#         &Common::Storage::copy_files( $r_path, $tmp_path );

#         &Common::File::delete_file_if_exists( $l_path );
        
#         if ( not rename $tmp_path, $l_path ) {
#             &error( qq (Could not rename "$tmp_path" to "$l_path") );
#         }

#         $count += 1;
        
#         &Common::File::delete_file( $busy_file );

#         &echo_green( "done\n" );
#     }
    
#     return $count;
# }
    
# sub download_files
# {
#     # Niels Larsen, July 2011.

#     # Downloads remote files to a local directory. First argument is a list
#     # of paths, perhaps with wildcards. The second argument is either a path,
#     # which is then considered a directory, or it is a list which has the 
#     # same number of paths as the input list. By default only files with 
#     # different size or newer remote date are copied, but the 'force' option 
#     # copies all. FTP, SSH and HTTP are supported, and error messages are 
#     # either fatal or returned. Returns the number of files downloaded.

#     my ( $rget,      # Remote path list or path
#          $lput,      # Local path list or path
#          $args,      # Arguments hash - OPTIONAL
#          $msgs,      # Outgoing messages - OPTIONAL
#         ) = @_;

#     # Returns integer.

#     my ( $defs, $uris, @l_files, @l_missing, @l_extra, $l_file, $r_file, $l_disk,
#          $delete_l_dir, $space_free, $fill_pct, $fill_pct_f, $count,
#          $l_path, $r_path, $r_name, %r_files, $tmp_path );

#     $defs = {
#         "user" => undef,
#         "pass" => undef,
#         "depth" => 1,
#         "readonly" => 0,
#         "force" => 0,
# 	"silent" => 0,
#         "clobber" => 0,
#     };

#     $args = &Registry::Args::create( $args, $defs );

#     $readonly = 0 if not defined $readonly;
#     $force = 0 if not defined $force;
#     $keys ||= [ "name", "size" ];

#     $l_dir = &Common::File::resolve_links( $l_dir, 1 );

#     if ( not $readonly ) {
#         &Common::File::create_dir_if_not_exists( $l_dir );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST REMOTE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Remote files can be given as a list or as a directory (from which all
#     # files are then used),

#     if ( defined $r_files )
#     {
#         if ( ref $r_files )
#         {
#             if ( (scalar @{ $r_files }) == 0 ) {
#                 &error( qq (The given remote file list is empty) );
#             }
#         }
#         else
#         {
#             &echo( "   Listing remote files ... " );
            
#             $r_files = &Common::Storage::list_files( $r_files );

#             &echo_green( "found ". scalar @{ $r_files } );

#             if ( (scalar @{ $r_files }) == 0 ) {
#                 &error( qq (No files in the given directory -> "$r_files") );
#             }
#         }
#     }
#     else {
#         &error( qq (No remote file list or directory given) );
#     }

#     # >>>>>>>>>>>>>>>>>> COMPARING LOCAL AND REMOTE FILES <<<<<<<<<<<<<<<<<<<<<

#     # Find which files are missing locally, by name and size,

#     @l_missing = &Common::Download::_missing_files( $r_files, $l_dir, $keys );

#     # >>>>>>>>>>>>>>>>>>>>>> CHECK EXTRA LOCAL FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo( "   Is download area clean ... " );
   
#     @l_files = &Common::Storage::list_files( $l_dir );

#     @l_extra = &Common::Storage::diff_lists( \@l_files, $r_files, [ "name" ] );
#     @l_extra = grep { $_->{"name"} !~ /^TIME_STAMP|GHOST_FILES$/ } @l_extra;
    
#     if ( @l_extra )
#     {
#         &echo_yellow( "NO\n" );
        
#         foreach $l_file ( @l_extra )
#         {
#             &echo_yellow( " * " );
#             &echo( qq (Please delete: "$l_file->{'path'}"\n) );
#         }
#     }
#     else {
#         &echo_green( "yes\n" );
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>>>> CHECK WE HAVE ENOUGH SPACE <<<<<<<<<<<<<<<<<<<<<<<<

#     &Common::Download::_estimate_disk_space( $r_files, $l_dir, $readonly );

#     # >>>>>>>>>>>>>>>>>>> DELETE LOCAL RELEASE FILES <<<<<<<<<<<<<<<<<<<<

#     &echo( qq (   How many local files have wrong size ... ) );
    
#     $count = 0;
    
#     foreach $r_file ( @l_missing )
#     {
#         $l_file = "$l_dir/" . $r_file->{"name"};
        
#         if ( -e $l_file )
#         {
#             &Common::Storage::delete_file( $l_file ) if not $readonly;
#             $count++;
#         }
#     }
    
#     if ( $count > 0 )
#     {
#         if ( $readonly ) {
#             &echo_green( "$count found\n");
#         } else { 
#             &echo_green( "$count, deleted\n");
#         }
#     }
#     else {
#         &echo_green( "none\n" );
#     }

#     # >>>>>>>>>>>>>>>>>>> DOWNLOAD THE FILES <<<<<<<<<<<<<<<<<<<<<<<

#     # Copy the files,

#     $count = 0;

#     foreach $r_file ( @l_missing )
#     {
#         $r_path = $r_file->{"path"};
#         $r_name = &File::Basename::basename( $r_path );

#         $l_path = $l_dir ."/$r_name";

#         &echo( qq (   Downloading "$r_path" ... ) );

#         if ( $readonly ) 
#         {
#             &echo_green( "skipped\n" );
#         }
#         else
#         {
#             if ( &Common::Download::download_file( $r_path, $l_path, $force, 1 ) )
#             {
#                 $count += 1;
#                 &echo_green( "done\n" );
#             }
#         }
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>> VERIFY DOWNLOAD IF POSSIBLE <<<<<<<<<<<<<<<<<<<<<<<

#     # Check that local file sizes match the remote ones. However when files are
#     # served by Apache or by a CMS, then exact sizes often cannot be gotten, so
#     # we skip in that case.
    
#     if ( not $readonly and not grep { $_->{"path"} =~ /^http:/ } @{ $r_files } )
#     {
#         &echo("   Do all file names and sizes match ... " );

#         @l_files =&Common::Storage::list_files( $l_dir );
#         push @l_files, &Common::File::list_ghosts( $l_dir );

#         @l_missing = &Common::Storage::diff_lists( $r_files, \@l_files, $keys );

#         if ( @l_missing )
#         {
#             $count = scalar @l_missing;
#             &echo_red( "NO" );
#             &echo( ", $count missing\n" );
#         }
#         else {
#             &echo_green( "yes\n" );
#         }
#     }

#     return $count;
# }

