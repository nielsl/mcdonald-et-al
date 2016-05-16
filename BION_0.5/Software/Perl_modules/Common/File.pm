package Common::File;     #  -*- perl -*-

# A collection of routines that abstract common file and directory
# operations. There are now libraries at CPAN that do some of the same
# (but there were not when this was written). 
# 
# Do not use recent perl features here, the module is used before perl 
# installation. Also do not include modules from this package other than
# Common::Config and Common::Messages, as this module is used before the
# others are installed.

use strict;
use warnings FATAL => qw ( all );

use Cwd;
use Data::Dumper;
use File::Basename;
use File::Path;
use File::Copy;
use File::Find;
use Fcntl qw(:DEFAULT :mode :flock);
use IO::File;
use IO::Handle;
use Storable qw (store retrieve);
use Tie::File;
use List::Util;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &access_error
                 &append_file
                 &append_files
                 &append_suffix
                 &append_yaml
                 &build_link_map
                 &change_dir
                 &change_ghost_paths
                 &change_paths
                 &check_corruptions
                 &check_file_ascii
                 &check_files
                 &close_handle
                 &close_handles
                 &copy_file
                 &count_files
                 &count_bytes
                 &count_content
                 &count_lines
                 &count_words
                 &create_dir
                 &create_dir_if_not_exists
                 &create_link
                 &create_link_if_not_exists
                 &create_links_relative
                 &create_path_relative
                 &create_workdir
                 &delete_dir_if_empty
                 &delete_dir_path_if_empty
                 &delete_dirs_if_empty
                 &delete_dir_tree
                 &delete_dir_tree_if_exists
                 &delete_file
                 &delete_file_if_empty
                 &delete_file_if_exists
                 &delete_files
                 &delete_files_if_exist
                 &delete_links_all
                 &delete_links_relative
                 &delete_links_stale
                 &delete_workdir
                 &dir_path
                 &dump_file
                 &eval_file
                 &format_yaml
                 &full_exec_path
                 &full_file_path
                 &full_file_paths
                 &get_append_handle
                 &get_exe_path
                 &get_handle
                 &get_read_handle
                 &get_read_tie
                 &get_read_write_handle
                 &get_read_write_tie
                 &get_tie
                 &get_write_handle
                 &get_mtime
                 &get_newest_file
                 &get_newest_file_epoch
                 &get_record_separator
                 &get_stats
                 &get_type
                 &ghost_file
                 &guess_os
                 &gunzip_file
                 &gzip_file
                 &gzip_is_intact
                 &is_ascii
                 &is_compressed
                 &is_compressed_bzip2
                 &is_compressed_gzip
                 &is_compressed_zip
                 &is_dos
                 &is_handle
                 &is_link
                 &is_mac
                 &is_newer_than
                 &is_regular
                 &is_stale_link
                 &is_unix
                 &line_ends
                 &list_all
                 &list_directories
                 &list_fastas
                 &list_files
                 &list_files_and_links
                 &list_files_find
                 &list_files_shell
                 &list_files_tree
                 &list_ghosts
                 &list_infos
                 &list_links
                 &list_modules
                 &list_pats
                 &list_pdls
                 &read_file
                 &read_first_line
                 &read_ids
                 &read_lines
                 &read_keyboard
                 &read_stdin
                 &read_yaml
                 &rename_file
                 &resolve_links
                 &retrieve_file
                 &save_stdin
                 &seek_file
                 &store_file
                 &sysopen
                 &sysread_file
                 &touch_file
                 &truncate_file
                 &unpack_archive
                 &unpack_archive_inplace
                 &unzip_files_single
                 &write_file
                 &write_yaml
                 &zip_files_single
                 );

use Common::Config;
use Common::Messages;

use Common::Util;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub access_error
{
    # Niels Larsen, March 2005.

    # Checks if a given file or directory has a given set of permissions.
    # The permissions are given by a string like "drx". The second argument
    # determines if the routine should trigger a fatal error or return 
    # error messages.

    my ( $input,      # List, file or directory path
         $perms,      # Permissions string
         $fatal,      # Fatal error flag - OPTIONAL, on
         ) = @_;

    # Returns 1 or nothing.

    my ( $perm, %perms, %msgs, %neg_msgs, @errs, @paths, $path, $negate );

    $fatal = 1 if not defined $fatal;

    %msgs = (
        "e" => "File does not exist",
        "r" => "File is not readable",
        "w" => "File is not writable",
        "f" => "File is not a plain file",
        "d" => "File is not a directory",
        "l" => "File is not a link",
        "s" => "File is not empty",
        );

    %neg_msgs = (
        "e" => "File exists",
        "r" => "File is readable",
        "w" => "File is writable",
        "f" => "File is a plain file",
        "d" => "File is a directory",
        "l" => "File is a link",
        "s" => "File is empty",
        );

    if ( ref $input ) {
        @paths = @{ $input };
    } else {
        @paths = $input;
    }

    $negate = 1 if $perms =~ s/!//g;

    %perms = map { $_, 1 } split "", $perms;

    if ( $negate )
    {
        foreach $path ( @paths )
        {
            if ( $perms{"e"} and -e $path )
            {
                push @errs, ["ERROR", qq ($neg_msgs{"e"} -> "$path") ];
            }
            else
            {
                foreach $perm ( keys %perms )
                {
                    next if $perm eq "e";
                    
                    if ( eval qq (-$perm "$path" ) )
                    {
                        if ( exists $neg_msgs{ $perm } ) {
                            push @errs, ["ERROR", qq ($neg_msgs{ $perm } -> "$path") ];
                        } else {
                            &Common::Messages::error( qq (Negate-permission "$perm" not set for -> "$path") );
                        }
                    }
                }
            }
        }
    }
    else
    {
        foreach $path ( @paths )
        {
            if ( $perms{"e"} and not -e $path )
            {
                push @errs, ["ERROR", qq ($msgs{"e"} -> "$path") ];
            }
            else
            {
                foreach $perm ( keys %perms )
                {
                    next if $perm eq "e";
                    
                    if ( not eval qq (-$perm "$path" ) )
                    {
                        if ( exists $msgs{ $perm } ) {
                            push @errs, ["ERROR", qq ($msgs{ $perm } -> "$path") ];
                        } else {
                            &Common::Messages::error( qq (Permission "$perm" not set for -> "$path") );
                        }
                    }
                }
            }
        }
    }
    
    if ( @errs )
    {
        if ( $fatal and not defined wantarray ) {
            &echo_messages( \@errs );
            exit;
        }
        else {
            return wantarray ? @errs : \@errs;
        }
    }
    else {
        return;
    }
}

sub append_file
{
    # Niels Larsen, March 2003.

    # Appends memory content to a file. It is up to the caller
    # to make sure there are newlines etc. Content can be a string or
    # a tring reference. The write mode can be ">" (overwrite) or ">>"
    # (append).

    my ( $file,    # File path
         $sref,    # Input string, string-reference or list-reference
         ) = @_;

    # Returns nothing.

    my ( $ref );

    if ( not $sref ) {
        &Common::Messages::error( qq (\$sref has zero size.) );
    }

    if ( not open FILE, ">> $file" ) {
        &Common::Messages::error( qq(Could not append-open file -> "$file") );
    }

    if ( not ref $sref )
    {
        if ( not print FILE $sref ) {
            &Common::Messages::error( qq(Could not append to "$file") );
        }
    }
    elsif ( ref $sref eq "SCALAR" )
    {
        if ( not print FILE ${ $sref } ) {
            &Common::Messages::error( qq(Could not append to "$file") );
        }
    } 
    elsif ( ref $sref eq "ARRAY" )
    {
        if ( not print FILE @{ $sref } ) {
            &Common::Messages::error( qq (Could not append to "$file") );
        }
    } 
    else
    {
        $ref = ref $sref;
        &Common::Messages::error( qq(
Type $ref is not recognized as input reference. Please supply
either a string or a string reference.
) );
    }

    if ( not close FILE, $file ) {
        &Common::Messages::error( qq(Could not close append-opened file -> "$file") );
    }

    return;
}

sub append_files
{
    # Niels Larsen, July 2003.

    # Appends the content of file2 to file1

    my ( $file1,       # File being appended to
         $file2,       # File being appended
         ) = @_;

    # Returns nothing.

    my ( $fh1, $fh2, $line );

    $fh1 = &Common::File::get_append_handle( $file1 );
    $fh2 = &Common::File::get_read_handle( $file2 );

    while ( defined ( $line = <$fh2> ) )
    {
        $fh1->print( $line );
    }

    &Common::File::close_handle( $fh1 );
    &Common::File::close_handle( $fh2 );

    return;
}

sub append_suffix
{
    # Niels Larsen, July 2009.

    # Appends to a given path one of the suffices in a given list
    # that makes the combined path match an existing file.

    my ( $path,
         $sufs,
        ) = @_;
    
    my ( $suf, $sufstr );

    foreach $suf ( @{ $sufs } )
    {
        if ( -r "$path$suf" ) 
        {
            return "$path$suf";
        }
    }

    $sufstr = join ",", @{ $sufs };
    &Common::Messages::error( qq (No file found for $path\{$sufstr\}) );
    
    return;
}

sub append_yaml
{
    # Niels Larsen, April 2011.

    # Appends a given structure to a given YAML file in YAML format. 

    my ( $file,       # File path
         $struct,     # Memory structure
         ) = @_;

    # Returns nothing.

    my ( $yaml );

    require YAML::XS;

    $yaml = &YAML::XS::Dump( $struct );
    &Common::File::append_file( $file, $yaml );

    return;
}
    
sub build_link_map
{
    # Niels Larsen, May 2009.

    # Builds a ( link-file => real-file ) hash for a given directory and its
    # subdirectories. 

    my ( $dir,             # Directory top node
         $clean,           # Delete state links or not - OPTIONAL, default 0
        ) = @_;

    # Returns a hash.
    
    my ( %map, $subref );

    $clean = 0 if not defined $clean;

    $subref = sub 
    {
        my ( $name, $path, $file );
        
        $name = $_;
        $path = $File::Find::name;

        if ( -l $path )
        {
            $file = readlink $path;
            $file = &Cwd::abs_path( $file );

            if ( defined $file and -e $file )
            {
                $map{ $path } = $file;
            }
            elsif ( $clean ) {
                unlink $path or warn qq (Could not delete "$path");
            }
        }

        return;
    };

    &File::Find::find( $subref, $dir );

    return wantarray ? %map : \%map;
}

sub check_corruptions
{
    my ( $files,
         $silent,
         ) = @_;

    my ( $count, $file, @bad_files );

    $silent = 0 if not defined $silent;
    local $Common::Messages::silent = $silent;

    &Common::Messages::echo( qq (   Checking for file corruption ... ) );
        
    foreach $file ( @{ $files } )
    {
        if ( not &Common::File::gzip_is_intact( $file->{'path'} ) )
        {
            push @bad_files, $file;
        }
    }
    
    $count = scalar @bad_files;

    if ( $count == 0 ) {
        &Common::Messages::echo_green( "looks ok\n" );
    }
    else
    {
        &echo_yellow( "$count bad files\n"  );
        
        foreach $file ( @bad_files ) 
        {
            &echo( " * " );
            &echo_yellow( "BAD" );
            &echo( " -> ".$file->{"path"}."\n" );
        }
    }

    return wantarray ? @bad_files : \@bad_files;
}

sub change_dir
{
    my ( $dir,
        ) = @_;

    if ( -d $dir )
    {
        if ( chdir $dir ) {
            return 1;
        } else {
            &error( qq (Could not change directory to "$dir") );
        }
    }
    elsif ( not -e $dir ) {
        &error( qq (Path does not exist -> "$dir") );
    } else {
        &error( qq (Path is not a directory -> "$dir") );
    }

    return;
}

sub change_ghost_paths
{
    my ( $dir,
         $newdir,
        ) = @_;

    my ( @ghosts, $file );

    @ghosts = &Common::File::list_ghosts( $dir );

    @ghosts = &Common::File::change_paths( \@ghosts, $newdir );

    &Common::File::delete_file_if_exists( "$dir/GHOST_FILES" );
    &Common::File::dump_file( "$dir/GHOST_FILES", \@ghosts );

    return;
}

sub change_paths
{
    my ( $files,
         $newdir,
        ) = @_;

    my ( $file );

    foreach $file ( @{ $files } )
    {
        $file->{"dir"} = $newdir;
        $file->{"path"} = "$newdir/". $file->{"name"};
    }

    return wantarray ? @{ $files } : $files;
}

sub check_file_ascii
{
    # Niels Larsen, October 2005.

    # Checks a given file for its type using the GNU "file" tool. It
    # will return an error message if it is not "ascii".

    my ( $file,        # File name
         $errmsg,      # Short error string - OPTIONAL
         $typmsg,      # Error message text - OPTIONAL
         ) = @_;

    # Returns a list or nothing.

    my ( @msgs, $type );

    $errmsg = qq (Not a regular text file -> "$file") if not defined $errmsg;
    $typmsg = qq (File appears to be of type "$type" -> "$file"\n)
        . qq ( We can only take plain-text (ascii) files, please)
        . qq ( try create one. Note: a Microsoft-Word file will not work )
        . qq ( - it is "binary" and its format is secret and unreadable )
        . qq ( to all but the Microsoft company and its closed programs.) if not defined $typmsg;

    if ( not &Common::File::is_ascii( $file ) )
    {
        $type = &Common::File::get_type( $file );

        if ( defined $type )
        {
            @msgs = [ "Error", $typmsg ];
        }
        else {
            &Common::Messages::error( $typmsg );
        }
    }

    if ( @msgs ) {
        return wantarray ? @msgs : \@msgs;
    } else {
        return;
    }
}

sub check_files
{
    # Niels Larsen, February 2010.

    # Checks that the given files have the given permissions. Those that 
    # do are returned, error messages are returned for the rest. If no 
    # message list is given, the errors will be printed and the routine
    # exits.

    my ( $files,    # File path list
	 $perms,    # Permissions string (see the access_error routine)
	 $msgs,     # Outgoing messages list
	) = @_;

    # Returns a list.

    my ( @files, $file, @msgs, @errs );

    $files = [ $files ] if not ref $files;

    foreach $file ( @{ $files } )
    {
	if ( @errs = &Common::File::access_error( $file, $perms ) ) {
	    push @msgs, @errs;
	} else { 
	    push @files, $file;
	}	    
    }

    if ( @msgs )
    {
	if ( $msgs ) {
	    push @{ $msgs }, @msgs;
	} else {
	    &echo_messages( \@msgs );
	    exit;
	}
    }

    return wantarray ? @files : \@files;
}

sub close_handle
{
    # Niels Larsen, June 2003.
    
    # Closes a file handle and dies on failure. 

    my ( $fh,     # File handle
         ) = @_;

    # Returns nothing.

    if ( not $fh->close )
    {
        undef $fh; 
    }

    return 1;
}

sub close_handles
{
    my ( $fhs,
         ) = @_;

    my ( $fh );

    foreach $fh ( keys %{ $fhs } )
    {
        &Common::File::close_handle( $fhs->{ $fh } );
    }

    return;
}

sub copy_file
{
    my ( $file,
         $dest,
         $force,
         ) = @_;

    if ( $force ) {
        &Common::File::delete_file_if_exists( $dest );
    }

    if ( not &Common::File::is_regular( $file ) )
    {
        &Common::Messages::error( qq (
The file

"$file"

is not a regular file. This either means it does not exist, is a
directory, a link, or some other special file. Please report this.

) );
    }

    if ( -e $dest )
    {
        &Common::Messages::error( qq (
The copy destination file

"$dest"

already exists. This means there is a problem with the file management
somewhere. Please report this.

) );
    }
    
    if ( not &File::Copy::copy( $file, $dest ) )
    {
        &Common::Messages::error( qq (
The system was unable to copy the file

  "$file"  to
  "$dest"
 
) );
    }
    
    return;
}

sub count_files
{
    # Niels Larsen, October 2006.

    # Returns the number of files in a given directory tree. The
    # second argument is a file test operator, so for example "-d"
    # will count the directories. 

    my ( $dir,        # Directory
         $test,       # Test operator - OPTIONAL, default "-f"
         ) = @_;

    # Returns an integer.

    my ( $count, $subref );

    $test ||= "-f";
    $count = 0;

    $subref = sub
    {
        $count += 1 if eval "$test '$File::Find::name'";
    };

    &File::Find::find( $subref, $dir );

    return $count;
}

sub count_content
{
    # Niels Larsen, February 2010.

    # Counts the number of lines in a given file. Returns a three element
    # list: ( lines, words, bytes ).

    my ( $file,
         $cmd,
	) = @_;

    # Returns a list.

    my ( $out, $err, @out );
    
    $cmd = "wc" if not defined $cmd;

    if ( -r $file )
    {
        if ( &Common::File::is_compressed( $file ) ) {
            &Common::OS::run3_command( "zcat $file | $cmd", undef, \$out, \$err );
        } else {
            &Common::OS::run3_command( $cmd, $file, \$out, \$err );
        }
    }
    else {
	&Common::Messages::error(qq (File is not readable -> "$file") );
    }

    chomp $out;
    @out = split " ", $out;

    if ( scalar @out > 1 ) {
        return wantarray ? @out : \@out;
    }

    return $out[0];
}

sub count_bytes
{
    # Niels Larsen, April 2010.

    # Counts the number of bytes in a given file.

    my ( $file,
	) = @_;

    # Returns integer.

    return &Common::File::count_content( $file, "wc --bytes" );
}

sub count_lines
{
    # Niels Larsen, April 2010.

    # Counts the number of lines in a given file.

    my ( $file,
         $save,
	) = @_;

    # Returns integer.

    my ( $count, $cfile );

    $cfile = "$file.count";

    if ( -r $cfile and &Common::File::is_newer_than( $cfile, $file ) )
    {
        $count = ${ &Common::File::read_file( $cfile ) };
        $count =~ s/\s+//g;
    }
    else
    {
        $count = &Common::File::count_content( $file, "wc --lines" );

        if ( $save )
        {
            &Common::File::delete_file_if_exists( $cfile );
            &Common::File::write_file( $cfile, "$count\n" );
        }
    }

    return $count;
}

sub count_words
{
    # Niels Larsen, April 2010.

    # Counts the number of words in a given file.

    my ( $file,
	) = @_;

    # Returns integer.

    return &Common::File::count_content( $file, "wc --words" );
}

sub create_dir
{
    # Niels Larsen, April 2003.

    # Creates a directory if it does not exist. If the directory exists
    # and the second argument is true, an error is thrown. If it exists
    # but is not a directory, this also means fatal error. The directory
    # should be an absolute path. 

    my ( $path,    # Full directory path
         $bool,    # Whether to raise error with existing directory
         ) = @_; 

    # Returns nothing. 
    
    $bool = 1 if not defined $bool;

    my $error_type = "FILE CREATE ERROR";

    if ( -e $path )
    {
        if ( -d $path )
        {
            if ( $bool ) {
                &Common::Messages::error( qq (Directory exists -> "$path"), $error_type );
            }
        }
        else {
            &Common::Messages::error( qq (Exists, is not directory -> "$path"), $error_type );
        }
    }
    else
    {
        if ( not mkpath $path )        {
            &Common::Messages::error( qq (Could not create directory -> "$path"), $error_type );
        }
    }

    return;
}

sub create_dir_if_not_exists
{
    # Niels Larsen, April 2003.

    # Creates a directory if it does not exist. The directory should
    # be an absolute path.

    my ( $path,    # Full directory path
         ) = @_; 

    # Returns nothing. 

    my ( $type, $count );

    $type = "FILE SYSTEM ERROR";
    $count = 0;

    if ( not -e $path and not -l $path )
    {
        if ( mkpath $path ) {
            $count = 1;
        } else {
            &Common::Messages::error( qq (Could not create directory -> "$path"), $type );
        }
    }

    return $count;
}

sub create_link
{
    # Niels Larsen, March 2005.

    # Creates a relative link between two given file paths. The given 
    # paths need not be absolute. 

    my ( $file,      # The actual file 
         $link,      # The link file to be created
         $fatal,     # Error flag - OPTIONAL, default on
         ) = @_;

    # Returns nothing. 

    my ( @file_path, @link_path, $file_path, $link_path );

    $fatal = 1 if not defined $fatal;

    $file_path = &Cwd::abs_path( $file ) || $file;
    $link_path = &Cwd::abs_path( $link ) || $link;

    @file_path = split "/", $file_path;
    @link_path = split "/", $link_path;

    while ( @file_path and $file_path[0] eq $link_path[0] ) 
    {
        shift @file_path;
        shift @link_path;
    }
    
    $file_path = ( "../" x $#link_path ) . join "/", @file_path;

    if ( (not symlink $file_path, $link_path) and $fatal )
    {
        if ( -e $link_path ) {
            &Common::Messages::error( qq (Link file exists -> "$link_path") );
        } else {
            &Common::Messages::error( qq (Could not create link from "$link_path" to "$file_path") );
        }
    }

    return;
}

sub create_link_if_not_exists
{
    my ( $file,
         $link,
         $fatal,
         ) = @_;

    if ( not -l $link ) 
    {
        &Common::File::create_link( $file, $link, $fatal );
    }

    return;
}

sub create_links_relative
{
    # Niels Larsen, March 2005.

    # Creates a link-mirror of a given directory tree. If the mirror exists more
    # links are added into it. All files are mirrored, except relative links. If 
    # the third argument is true (default false) a fatal error happens if a given 
    # link exists, otherwise it will be overwritten. Both given directories may 
    # be absolute or relative paths, but if relative it must be relative to the 
    # current default directory.

    my ( $real_dir,      # Top node of tree with real files
         $link_dir,      # Top node of tree with link files
         $force,         # Force creation of new link if one exists - OPTIONAL
         ) = @_;

    # Returns integer. 

    my ( $real_path, $link_path, $file, $subref, $count );

    $force = 0 if not defined $force;

    $real_path = &Cwd::abs_path( $real_dir );
    $link_path = &Cwd::abs_path( $link_dir );

    if ( $real_path eq $link_path ) {
        &Common::Messages::error( qq (Real- and link-paths are identical -> "$real_path") );
    }

    &Common::File::access_error( $real_path, "edrx" );
    &Common::File::create_dir_if_not_exists( $link_path );

    $count = 0;

    $subref = sub
    {
        my ( $path );

        $path = $File::Find::name;

        if ( $path ne $real_path )
        {
            $path =~ s|$real_path/||;

            if ( -d "$real_path/$path" )
            {
                if ( not -d "$link_path/$path" ) {
                    &Common::File::create_dir( "$link_path/$path" );
                }
            }
            else
            {
                if ( -e "$link_path/$path" )
                {
                    if ( $force ) {
                        &Common::File::delete_file( "$link_path/$path" );
                    } else {
                        &Common::Messages::error( qq (Link file exists -> "$link_path/$path") );
                    }
                }

                &Common::File::create_link( "$real_path/$path", "$link_path/$path" );
                $count += 1;
            }
        }
    };
    
    &File::Find::find( $subref, $real_path );

    return $count;
}

sub create_path_relative
{
    # Niels Larsen, October 2012.

    # Returns the shortest possible relative file path of the 
    # path given, relative to the current directory. Or if a 
    # directory is given, relative to that. 

    my ( $path,
         $dir,
        ) = @_;

    # Returns a string.

    my ( @abs_path, $abs_path, $cur_dir, $rel_path, @dir_path );
    
    $abs_path = &Common::File::full_file_path( $path );

    if ( not -e $abs_path ) {
        &error( qq (Path does not exist -> "$path") );
    }

    $cur_dir = &Cwd::getcwd();

    if ( $dir ) {
        &Common::File::change_dir( $dir );
    } else {
        $dir = $cur_dir;
    }

    @dir_path = split "/", &Common::File::full_file_path( $dir );
    @abs_path = split "/", $abs_path;

    shift @dir_path;
    shift @abs_path;

    while ( @dir_path and $abs_path[0] eq $dir_path[0] ) 
    {
        shift @dir_path;
        shift @abs_path;
    }

    $rel_path = ( "../" x scalar @dir_path ) . join "/", @abs_path;

    if ( defined $cur_dir ) {
        &Common::File::change_dir( $cur_dir );
    }

    return $rel_path;
}

sub create_workdir
{
    # Niels Larsen, March 2013.

    # Creates a scratch directory. The given directory path must end with 
    # ".workdir", it may not exist and its parent directory must be writable.
    # The path can be made with &Common::File::create_workdir_path. Returns 
    # nothing.

    my ( $dir,          # Directory path - OPTIONAL, default scratch directory
         $suf,          # Directory suffix - OPTIONAL, default process number
        ) = @_;

    my ( $pdir );

    $suf = $$ if not defined $suf;

    $dir = &Common::File::create_workdir_path( $dir, $suf );

    if ( -e $dir ) {
        &error( qq (Work directory exists -> "$dir") );
    } elsif ( not -w ( $pdir = &File::Basename::dirname( $dir ) ) ) {
        &error( qq (Work directory parent path not writable -> "$pdir") );
    } elsif ( $dir !~ /\.workdir$/ ) {
        &error( qq (Wrong looking work directory -> "$dir"\n)
               .qq (It must end with ".workdir") );
    }

    &Common::File::create_dir( $dir );

    return $dir;
}

sub create_workdir_path
{
    # Niels Larsen, March 2013.

    # Creates a scratch directory path string that ends with ".workdir".
    # A prefix path is given, which can be either a directory or a file, 
    # or else the default scratch directory is chosen followed by the 
    # basename of $0. If a second argument is given, then that is 
    # inserted between the path and ".workdir" - it could be the process 
    # number for example. No read/write/exists checks are done and the 
    # work directory is not created, but &Common::File::create_workdir 
    # does that. Returns the work-dir path as a string.

    my ( $path,          # File or directory path - OPTIONAL
         $suf,           # Delete existing - OPTIONAL, default 0
        ) = @_;

    # Returns string.
    
    my ( $dir );

    if ( defined $path ) {
        $dir = $path;
    } else {
        $dir = $Common::Config::tmp_dir ."/". &File::Basename::basename( $0 );
    }

    $suf = $$ if not defined $suf;

    $suf =~ s/^\W+//;
    $dir .= ".$suf";

    $dir .= ".workdir";

    return $dir;
}

sub delete_dir_if_empty
{
    # Niels Larsen, May 2003.

    # Deletes a given directory if it is empty.

    my ( $path,    # Directory path
         ) = @_;

    # Returns nothing. 

    my ( $done, @files );

    if ( -d $path )
    {
        if ( @files = &Common::File::list_all( $path ) )
        {
            $done = 0;
        }
        else
        {
            if ( rmdir $path ) {
                $done = 1;
            } else {
                &Common::Messages::error( qq (Could not delete "$path"), "DELETE DIR ERROR" );
            }
        }
    }
    else {
        $done = 0;
    }

    return $done;
}

sub delete_dir_path_if_empty
{
    # Niels Larsen, October 2006.
    
    # Works its way up through a given directory path and deletes each directory
    # if it is empty. Returns the number of empty directories deleted. 

    my ( $path,    # Directory path
         ) = @_;

    # Returns an integer.

    my ( $continue, @path, $count, @files );

    $continue = 1;
    $count = 0;

    @path = split "/", $path;

    while ( $continue ) 
    {
        $path = join "/", @path;

        if ( $path )
        {
            if ( -e $path )
            {
                @files = &Common::File::list_all( $path );
                
                if ( @files )
                {
                    $continue = 0;
                }
                else
                {
                    if ( not rmdir $path ) {
                        &Common::Messages::error( qq (Could not delete "$path"), "DELETE DIR ERROR" );
                    }
                    
                    pop @path;
                    
                    $count += 1;
                }
            }
            else {
                pop @path;
            }
        }
        else {
            $continue = 0;
        }
    }

    return $count;
}

sub delete_dirs_if_empty
{
    # Niels Larsen, April 2005.

    # Removes all empty directories in a given directory tree. The 
    # given directory is removed itself if empty. 

    my ( $path,         # Directory path
         ) = @_;

    # Returns nothing. 

    my ( $file, $subref, $count, $sum );

    $path = &Cwd::abs_path( $path );

    $count = 0;
    $sum = 0;

    $subref = sub 
    {
        my ( $path );

        $path = $File::Find::name;
        chomp $path;

        if ( -e $path and -d $path )
        {
            $count += &Common::File::delete_dir_if_empty( $path );
        }
    };

    {
        no warnings;
        &File::Find::find( $subref, $path );
    }

    while ( $count > 0 ) 
    {
        $sum += $count;
        $count = 0;

        no warnings;
        &File::Find::find( $subref, $path );
    }

    $sum += &Common::File::delete_dir_if_empty( $path );

    return $sum;
}

sub delete_dir_tree
{
    # Niels Larsen, May 2003.

    # Deletes the directory tree starting at a given path, which
    # must be a directory. Returns the number of files deleted,
    # directories included.

    my ( $path,    # Directory path
         ) = @_;

    # Returns a number. 

    my ( $count );

    $count = &File::Path::rmtree( $path );

    if ( not $count )
    {
        &Common::Messages::error( qq (Could not delete "$path"), "DELETE DIR ERROR" );
    }

    return $count;
}

sub delete_dir_tree_if_exists
{
    # Niels Larsen, May 2003.

    # Deletes the directory tree starting at a given path, which
    # must be a directory. 

    my ( $path,    # Directory path
         ) = @_;

    # Returns nothing. 
    
    my ( $count );

    if ( -e $path )
    {
        $count = &Common::File::delete_dir_tree( $path );
    }
    else {
        $count = 0;
    }

    return $count;
}

sub delete_file
{
    # Niels Larsen, March 2003.
    
    # Deletes a file. It is an error if it does not exist. 

    my ( $file,    # File path
         ) = @_;

    # Returns nothing.
    
    if ( not unlink $file )
    {
        &Common::Messages::error( qq (
The system is unable to delete the file 

 "$file"

) );
    }

    return 1;
}

sub delete_files
{
    # Niels Larsen, March 2003.
    
    # Deletes a list of files. It is an error if one of them do not exist. 

    my ( $files,    # File paths
         ) = @_;

    # Returns nothing.

    my ( $count );

    $count = 0;

    map { $count += &Common::File::delete_file( $_ ) } @{ $files };

    return $count;
}

sub delete_files_if_exist
{
    # Niels Larsen, April 2012. 

    my ( $files,
        ) = @_;

    my ( $count, $file );

    foreach $file ( @{ $files } )
    {
        $count += &Common::File::delete_file_if_exists( $file );
    }

    return $count;
}

sub delete_file_if_empty
{
    # Niels Larsen, February 2008.
    
    # Deletes a file if it is empty. 

    my ( $file,    # File path
         $msgs,
         ) = @_;

    # Returns 1 or 0.

    my ( $count );

    if ( -e $file and not -s $file ) {
        $count = &Common::File::delete_file( $file );
    } else {
        $count = 0;
    }

    return $count;
}

sub delete_file_if_exists
{
    # Niels Larsen, March 2003.
    
    # Deletes a file if it exists. 

    my ( $file,    # File path
         $msgs,
         ) = @_;

    # Returns 1 or 0.

    my ( $count, $stats );

    $stats = &Common::File::get_stats( $file );

    if ( $stats )
    {
        if ( unlink $file ) {
            $count = 1;
        } else {
            &Common::Messages::error( qq (Could not delete -> "$file") );
        }
    } 
    else {
        $count = 0;
    }

    return $count;
}

sub delete_link_if_exists
{
    # Niels Larsen, November 2007.
    
    # Deletes a link if it exists. 

    my ( $file,    # File path
         $msgs,
         ) = @_;

    # Returns 1 or 0.

    my ( $count );

    if ( -l $file )
    {
        if ( unlink $file ) {
            $count = 1;
        } else {
            &Common::Messages::error( qq (Could not delete -> "$file") );
        }
    } 
    else {
        $count = 0;
    }

    return $count;
}

sub delete_links_relative
{
    # Niels Larsen, October 2007.

    # Given a directory tree of real files, and a directory tree of corresponding 
    # link files (they can be made by create_links_relative), removes the links that
    # point into the real-tree. The two trees must have the same exact topology. 
    # Empty subdirectories and stale links are removed. If either top directory 
    # nodes does not exist, nothing is done. The number of deletions is returned. 

    my ( $real_dir,     # Directory that links point into
         $link_dir,     # Where the links are
         ) = @_;

    # Returns integer.

    my ( $count, $subref, $cwd );

    $real_dir = &Cwd::abs_path( $real_dir );
    $link_dir = &Cwd::abs_path( $link_dir );

    # Define subroutine to use recursively below,
    
    $subref = sub
    {
        my ( $cwd, $real_path, $link_path, $sub_path, %real_paths, %link_paths, $real, $link );
        
        $real_path = $File::Find::name;
        
        if ( -d $real_path )
        {
            $sub_path = $real_path;
            $sub_path =~ s|$real_dir||;
            
            $link_path = "$link_dir$sub_path";
            
            if ( -d $link_path )
            {
                $cwd = getcwd();
                chdir $link_path;
                
                %real_paths = map { $_->{"path"}, 1 } &Common::File::list_all( $real_path );

                if ( %real_paths )
                {
                    %link_paths = map { $_->{"path"}, 1 } &Common::File::list_links( $link_path );

                    foreach $link ( keys %link_paths )
                    {
                        $real = readlink $link;
                        
                        if ( defined $real )
                        {
                            $real = &Cwd::abs_path( $real );
                            
                            if ( defined $real and (exists $real_paths{ $real } or not -e $real) )
                            {
                                $count += &Common::File::delete_file( $link );
                            }
                        }
                    }
                }

                chdir $cwd;

                &Common::File::delete_dir_if_empty( $link_path );
            }
        }
    };

    # Run it,

    $count = 0;

    if ( $link_dir and -d $link_dir and $real_dir and -d $real_dir )
    {
        &File::Find::find( $subref, $real_dir );
        &Common::File::delete_dir_if_empty( $link_dir );
    }

    return $count; 
}

sub delete_links_all
{
    # Niels Larsen, October 2007.

    # Removes all links in a given directory, including stale ones. If the 
    # directory does not exist nothing is done. The number of deletions is 
    # returned. 

    my ( $dir,     # Directory with links 
         ) = @_;

    # Returns integer.

    my ( $file, $count );

    $count = 0;

    if ( -d $dir )
    {
        foreach $file ( @{ &Common::File::list_links( $dir ) } )
        {
            &Common::File::delete_file( "$dir/$file->{'name'}" );
            $count += 1;
        }
    }

    return $count;
}

sub delete_links_stale
{
    # Niels Larsen, March 2005.

    # Removes all stale links in a given directory. If the directory does not 
    # exist, nothing is done. The number of deletions is returned. 

    my ( $dir,       # Directory with links
         ) = @_;

    # Returns integer.

    my ( $cwd, @links, $link, $path, $count );

    $count = 0;

    if ( -d $dir )
    {
        $cwd = getcwd();
        chdir $dir;
        
        @links = &Common::File::list_links( $dir );
        
        foreach $link ( @links )
        {
            $path = readlink $link->{"path"};
            $path = &Cwd::abs_path( $path );
            
            if ( not defined $path or not -e $path ) 
            {
                &Common::File::delete_file( $link->{"path"} );
                $count += 1;
            }
        }

        chdir $cwd;
    }

    return $count;
}

sub delete_workdir
{
    # Niels Larsen, March 2013.

    # Deletes a work directory and all its content if it exists. To guard
    # against deleting unintended directories, the given path must end with
    # ".workdir", or else an error. Returns the number of files and 
    # directories deleted.

    my ( $dir,         # Work dir
        ) = @_;

    # Returns integer.

    if ( not defined $dir ) {
        &error( qq (Work directory path not given) );
    } elsif ( not -e $dir ) {
        &error( qq (Work directory path does not exist -> "$dir") );
    } elsif ( not -w $dir ) {
        &error( qq (Work directory path not deletable -> "$dir") );
    } elsif ( $dir !~ /\.workdir$/ ) {
        &error( qq (Wrong looking work directory -> "$dir"\n)
               .qq (It must end with ".workdir") );
    }

    return &Common::File::delete_dir_tree( $dir );
}

sub dir_path
{
    # Niels Larsen, April 2013.

    # Returns the directory portion, or part of it, of a file path.
    # The level argument is used to return parts of the directory path:
    # 
    # Positive: the n first sub-directories are included
    # Negative: the -n last sub-directories are included
    # Zero: no sub-directories included
    # Undefined: the whole directory path is returned.
    
    my ( $file,
         $level,
        ) = @_;

    # Returns a string.

    my ( $dir, @dir, $maxlevel );

    $dir = &File::Basename::dirname( $file );

    if ( $level )
    {
        @dir = split "/", $dir;

        $maxlevel = scalar @dir;
        $level = $maxlevel if $level > $maxlevel;

        if ( $level >= - $maxlevel )
        {
            if ( $level > 0 ) {
                $dir = join "/", @dir[ 0 ... $level - 1];
            } else {
                $dir = join "/", @dir[ $maxlevel + $level ... $maxlevel - 1];
            }
        }
    }

    return $dir;
}

sub dump_file
{
    # Niels Larsen, May 2003.

    # Writes a data structure to file using Data::Dumper. 

    my ( $path,      # File path
         $struct,    # Data structure
         $clobber,   # Deletes existing file - OPTIONAL, default 0
         ) = @_;

    # Returns nothing. 

    my ( $fh );

    if ( not $struct ) {
        &Common::Messages::error( qq (No data given) );
    }

    if ( $clobber ) {
        &Common::File::delete_file_if_exists( $path );
    }

    $fh = &Common::File::get_write_handle( $path );

    $Data::Dumper::Terse = 1;     # avoids variable names
    $Data::Dumper::Indent = 1;    # mild indentation
    
    $fh->print( Data::Dumper::Dumper( $struct ) );

    &Common::File::close_handle( $fh );

    return;
}

sub eval_file
{
    # Niels Larsen, May 2003. 

    # Eval's the content of a file made with dump_file routine (which
    # uses Data::Dumper) and creates a memory structure. 

    my ( $path,    # File path
         $fatal,   # Whether to die if error - OPTIONAL, default 1
         ) = @_;

    # Returns a scalar, array or hash depending on file content and 
    # the context. 

    my ( $content, $ref );

    $fatal = 1 if not defined $fatal;

#    if ( &Common::File::is_ascii( $path ) )
#    {
        $content = &Common::File::read_file( $path );
        
        if ( $ref = eval ${ $content } )
        {
            return $ref;
        }
        elsif ( $fatal ) {
            &Common::Messages::error( qq (Could not eval file "$path"), "EVAL ERROR" );
        }
#     }
#     else {
#         $ref = &Common::File::retrieve_file( $path );
#         &Common::File::delete_file( $path );
#         &Common::File::dump_file( $path, $ref );

#         return $ref;
#     }
    
    return;
}

sub format_yaml
{
    my ( $struct,
        ) = @_;

    my ( $str );

    require YAML::XS;
    require Data::Structure::Util;

    $str = &YAML::XS::Dump( &Data::Structure::Util::unbless( $struct ) );

    return \$str;
}

sub full_exec_path
{
    # Niels Larsen, December 2010.

    # If the given program or command is in the shell path and executable,
    # then its full path is returned, otherwise nothing. 

    my ( $cmd,         # Command or program name
        ) = @_;

    # Returns string or nothing.

    my ( $stdout, $stderr, $path );

    if ( $cmd =~ /\s/ ) {
        &error( qq (Command name contains blanks -> "$cmd") );
    }

    &Common::OS::run3_command( "which $cmd", undef, \$stdout, \$stderr, 0 );

    $path = $stdout;
    $path =~ s/\s//g;

    return $path if -x $path;

    return;
}

sub full_file_path
{
    # Niels Larsen, March 2003.

    # Expands an incomplete file or directory path to an absolute name.
    # The path may contain '~', '.' and '..'. The idea is taken from
    # "Perl Cookbook", page 231 by O'Reilly Associates.

    my ( $path,    # Incomplete path
         $dir,     # Base directory - OPTIONAL
         ) = @_;

    # Returns string.

    my ( $full_path, @messages, @add_path, $name, $dir_path, $suffix, $part );

    if ( not defined $path )
    {
        return "";
    }
    elsif ( $path =~ /^\~/ )
    {
        $full_path = $path;
        
        $full_path =~ s{ ^ ~ ( [^/]* ) }
        { $1 ? (getpwnam($1))[7]
              : ( $ENV{"HOME"} || $ENV{"LOGDIR"} || (getpwuid($>))[7] )
        }ex;
    }
    elsif ( $path =~ /^\// )
    {
        $full_path = $path;
    }
    else
    {
        if ( defined $dir ) {
            @add_path = split "/", $dir;
        } elsif ( &Cwd::cwd() ) {
            @add_path = split "/", &Cwd::cwd();
        } else {
            @add_path = ();
        }

        ( $name, $dir_path, $suffix ) = &File::Basename::fileparse( $path, '\.\d+' );

        foreach $part ( split "/", $dir_path )
        {
            next if $part eq ".";

            if ( $part eq ".." )
            {
                pop @add_path;
            }
            elsif ( $part =~ /^\S+$/ )
            {
                push @add_path, $part;
            }
        }
        
        if ( @add_path ) {
            $full_path = (join "/", @add_path) . "/$name";
        } else {
            $full_path = $name;
        }

        $full_path .= $suffix if defined $suffix;
    }

    return $full_path;
}

sub full_file_paths
{
    # Niels Larsen, September 2010.

    # Converts a list of unexpanded file paths to a list of full paths.
    # The input list may contain wildcards to be expanded by the shell,
    # and the paths may be relative. 

    my ( $paths,
         $msgs,
         $full,
        ) = @_;

    # Returns a list.

    my ( @paths, $path, $stdout, $stderr, $msg );

    $msgs = [] if not defined $msgs;
    $full = 1 if not defined $full;

    @paths = &Common::File::list_files_shell( $paths, $msgs );

    if ( $full ) {
        @paths = map { &Common::File::full_file_path( $_ ) } @paths;
    }

    if ( @paths ) {
        return wantarray ? @paths : \@paths;
    } 

    return;
}
        
sub get_append_handle
{
    # Niels Larsen, September 2006.

    # Returns an appendonly filehandle. Takes optional "compression" and 
    # "clobber" arguments, both off by default.

    my ( $file,   # Absolute file path
         %args,   # Modifying arguments
        ) = @_;

    # Returns a file handle. 

    %args = (
        %args, 
        "exclusive" => 0,
        "appendonly" => 1, "readonly" => 0, 
        "writeonly" => 0, "readwrite" => 0 );
    
    return &Common::File::get_handle( $file || ">-", %args );
}

sub get_exe_path
{
    # Niels Larsen, January 2010. 
    
    # Checks if a given string is an executable file in the shell $PATH.
    # If it is, the full path is returned, otherwise nothing.

    my ( $str,     # String
        ) = @_;

    # Returns string or nothing. 

    my ( $dirs, $dir );

    $dirs = [ split ":", $ENV{"PATH"} ];

    foreach $dir ( @{ $dirs } )
    {
        return "$dir/$str" if -x "$dir/$str";
    }

    return;
}
        
sub get_handle
{
    # Niels Larsen, September 2006.

    # Returns a read, write, append or readwrite handle to a given file, 
    # depending on the flags given,
    # 
    # readonly => 1
    # appendonly => 0
    # writeonly => 0
    # readwrite => 0
    # exclusive => 0
    #
    # Two modifying arguments can be given,
    #
    # clobber => 0            works with writeonly and readwrite
    # compressed => 0,        works with readonly, writeonly and appendonly
    # 

    my ( $file,   # Absolute or relative file path
         %args,   # Modifying arguments
         ) = @_;

    # Returns a file handle. 

    my ( $bin_dir, $mode, $text, $fh, $suffix, $utils, $util, $redirect,
         $path );

    if ( not defined $file ) {
        &Common::Messages::error( qq (\$file not defined) );
    } elsif ( $file eq "" ) {
        &Common::Messages::error( qq (No \$file given (is empty string)) );
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> STDIN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file eq "-" or $file eq "STDIN" )
    {
        $fh = new IO::Handle;

        if ( not open $fh, "-" ) {
            &Common::Messages::error( qq (Could not open STDIN") );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> STDOUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $file eq ">-" or $file eq "STDOUT" )
    {
        $fh = new IO::Handle;

        if ( not open $fh, ">-" ) {
            &Common::Messages::error( qq (Could not open STDOUT") );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> COMPRESSED FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Compressed files can be read, written and appended to via compression
    # programs and pipes. But I dont know how to make that work with Fcntl 
    # flags .. so here we compose expressions like "zcat $file |" and pass
    # those on to IO::File (which then passes them on to regular open). 

    elsif ( &Common::File::is_compressed( $file ) or $args{"compressed"} )
    {
        if ( $file !~ /^\// ) {
            $file = &Common::File::full_file_path( $file );
        }

        $utils->{"gz"} = [ "zcat", "gzip" ];
        $utils->{"bz2"} = [ "bzcat", "bzip2" ];
        $utils->{"tgz"} = [ "tar -O -xzf" ];
        $utils->{"tar.gz"} = [ "tar -O -xzf" ];
        $utils->{"zip"} = [ "unzip -p" ];
        
        foreach $util ( map { @{ $_ } } values %{ $utils } )
        {
            $util = ( split " ", $util )[0];

            if ( not ( $path = `which $util` ) ) {
                &error( qq (`which \$util` returned empty) );
            }

            chomp $path;
            $path = (readlink $util) || $path;

            $path =~ s/\s*$//;

            if ( not -x $path ) {
                &Common::Messages::error( qq (Program is not executable -> "$path") );
            }
        }

        if ( $file =~ /\.(gz)$/ ) {
            $suffix = $1;
        } elsif ( $file =~ /\.(bz2)$/ ) {
            $suffix = $1;
        } elsif ( $file =~ /\.(tgz)$/ or $file =~ /\.(tar\.gz)$/ ) {
            $suffix = $1;
        } elsif ( $file =~ /\.(zip)$/ ) {
            $suffix = $1;
        } else {
            &Common::Messages::error( qq (Unrecognized compressed file suffix -> "$file") );
        }
        
        if ( $args{"readonly"} )
        {
            if ( -r $file )
            {
                $mode = $utils->{ $suffix }->[0] . " $file |";
                $text = "read";
            }
            else {
                &Common::Messages::error( qq (File is not readable -> "$file") );
            }
        }
        else 
        {
            if ( not $args{"clobber"} )
            {
                if ( ($args{"writeonly"} or $args{"readwrite"}) and -e $file ) {
                    &Common::Messages::error( qq (File exists -> "$file") );
                }
            }

            if ( $args{"writeonly"} )
            {
                $redirect = ">";
                $text = "write";
            }
            elsif ( $args{"appendonly"} )
            {
                $redirect = ">>";
                $text = "append";
            }
            else {
                &Common::Messages::error( qq (In compressed mode only "readonly", "writeonly",)
                                        . qq ( and "appendonly" are possible.) );
            }

            if ( $utils->{ $suffix }->[1] ) {
                $mode = "| ". $utils->{ $suffix }->[1] ." $redirect $file";
            } else {
                &error( qq (Write not supported for $suffix) );
            }
        }

        $fh = new IO::File;

        if ( not $fh->open( $mode ) ) {
            &Common::Messages::error( qq (Could not $text-open "$file") );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> REGULAR FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Open with Fcntl flags, which allow better control and less checks than 
    # above. 

    else
    {
        if ( $args{"readonly"} )
        {
            $mode = O_RDONLY;
            $text = "read";
        }
        elsif ( $args{"appendonly"} )
        {
            $mode = O_WRONLY|O_APPEND|O_CREAT;
            $text = "append";
        }
        elsif ( $args{"writeonly"} )
        {
            &Common::File::delete_file( $file ) if $args{"clobber"} and -e $file;

            $mode = O_WRONLY|O_CREAT;
            $text = "write";
        }
        elsif ( $args{"readwrite"} )
        {
            &Common::File::delete_file( $file ) if $args{"clobber"} and -e $file;

            $mode = O_RDWR|O_CREAT;
            $text = "readwrite";
        }
        else {
            &Common::Messages::error( qq (No open mode given.) );
        }

        if ( $file !~ /^\// ) {
            $file = &Common::File::full_file_path( $file );
        }

        if ( $fh = IO::File->new( $file, $mode ) )
        {
            if ( $args{"exclusive"} ) {
                flock $fh, LOCK_EX;
            }
        }
        else {
            &Common::Messages::error( qq (Could not $text-open file -> "$file") );
        }
    }

    return $fh;
}

sub get_read_handle
{
    # Niels Larsen, September 2006.

    # Returns a readonly filehandle. Takes optional "compression" and 
    # "clobber" arguments, both off by default.

    my ( $file,   # Absolute file path
         %args,   # Modifying arguments
         ) = @_;

    # Returns a file handle. 

    %args = (
        %args, 
        "exclusive" => 0,
        "appendonly" => 0, "readonly" => 1, 
        "writeonly" => 0, "readwrite" => 0 );
    
    $file = &Common::File::full_file_path( $file );

    return &Common::File::get_handle( $file || "-", %args );
}

sub get_read_tie
{
    # Niels Larsen, October 2009.

    # Read-only ties a given data structure to a given file. Accepts 
    # all "Tie::File" arguments except mode. Returns a "Tie::File" 
    # object. 

    my ( $ref,      # List or hash
         $file,     # File path
         %args,     # Tie::File arguments
        ) = @_;

    # Returns a "Tie::File" object. 

    %args = ( %args, 
              "readonly" => 1, "readwrite" => 0 );

    return &Common::File::get_tie( $ref, $file || "-", %args );
}

sub get_read_write_handle
{
    # Niels Larsen, September 2006.

    # Returns a read/write filehandle. Takes an optional "clobber" 
    # argument, off by default.

    my ( $file,   # Absolute file path
         %args,   # Modifying arguments
         ) = @_;

    # Returns a file handle. 

    %args = ( %args, 
              "appendonly" => 0, "readonly" => 0, 
              "writeonly" => 0, "readwrite" => 1 );

    if ( not $file ) {
        &Common::Messages::error( qq (No file name given) );
    }

    return &Common::File::get_handle( $file, %args );
}

sub get_read_write_tie
{
    # Niels Larsen, October 2009.

    # Read-write ties a given data structure to a given file. Accepts 
    # all "Tie::File" arguments except mode. Returns a "Tie::File" 
    # object. 

    my ( $ref,      # List or hash
         $file,     # File path
         %args,     # Tie::File arguments
        ) = @_;

    # Returns a "Tie::File" object. 

    %args = ( %args, 
              "readonly" => 0, "readwrite" => 1 );

    return &Common::File::get_tie( $ref, $file || "-", %args );
}

sub get_tie
{
    # Niels Larsen, October 2009.

    # Returns a read or read/write "Tie::File" object that maps a given file 
    # or file handle to a given data structure. 
    # 
    # readonly => 1
    # readwrite => 0
    #
    # One modifying argument can be given,
    #
    # clobber => 0            works with writeonly and readwrite
    # 

    my ( $ref,    # Data structure
         $file,   # Absolute file path
         %args,   # Modifying arguments
         ) = @_;

    # Returns a file handle. 
    
    my ( $type, $obj, $mode, $clobber );

    # Check arguments, 

    $type = ref $ref;

    if ( $type eq "ARRAY" ) {
        require "Tie::File";
    } else {
        &Common::Messages::error( qq (Unsupported data type -> "$type") );
    }

#    &Common::Messages::require_module( $module );

    if ( not defined $file ) {
        &Common::Messages::error( qq (\$file not defined) );
    } elsif ( not $file ) {
        &Common::Messages::error( qq (No \$file given (is empty string)) );
    }

    # Set modes and get file handles,

    delete $args{"mode"};

    $clobber = $args{"clobber"};

    if ( $args{"readonly"} )
    {
        $mode = O_RDONLY;

        $file = &Common::File::get_read_handle( $file ) if not ref $file;
    }
    elsif ( $args{"readwrite"} )
    {
        $mode = O_RDWR|O_CREAT;

        $file = &Common::File::get_read_write_handle( $file, "clobber" => $clobber || 0 ) if not ref $file;
    }
    else {
        &Common::Messages::error( qq (Missing access argument, should be "readonly" or "readwrite".) );
    }

    delete $args{"readonly"};
    delete $args{"readwrite"};
    delete $args{"clobber"};

    if ( $type eq "ARRAY" )
    {
        if ( %args ) {
            $obj = tie @{ $ref }, "Tie::File", $file, "mode" => $mode, %args;
        } else {
            $obj = tie @{ $ref }, "Tie::File", $file, "mode" => $mode;
        }
    }
    else {
        &Common::Messages::error( qq (Unsupported data type -> "$type") );
    }    

    return $obj;
}

sub get_write_handle
{
    # Niels Larsen, September 2006.

    # Returns a writeonly filehandle. Takes optional "compression" and 
    # "clobber" arguments, both off by default.

    my ( $file,   # Absolute file path
         %args,   # Modifying arguments
         ) = @_;

    # Returns a file handle. 

    %args = (
        %args, 
        "exclusive" => 1,
        "appendonly" => 0, "readonly" => 0,
        "writeonly" => 1, "readwrite" => 0 );

    return &Common::File::get_handle( $file || ">-", %args );
}

sub get_mtime
{
    # Niels Larsen, August 2006.

    # Returns the number of seconds since last modification of a given file.

    my ( $file,     # Input file path
         ) = @_;

    # Returns a string or nothing.

    return &Common::File::get_stats( $file )->{"mtime"};
}
    
sub get_newest_file
{
    # Niels Larsen, January 2004.

    # Returns the file in a given directory which is most recent. 
    # The file is a hash structure like that produced by the list_all
    # routine in this module. 

    my ( $dirs,      # Directory path or list of paths
         $expr,      # Name filter expression, OPTIONAL
         $bool,      # Whether to match or not match
         ) = @_;

    # Returns a hash.

    $bool = 1 if not defined $bool;

    my ( @files, $dir );

    if ( ref $dirs eq "ARRAY" )
    {
        foreach $dir ( @{ $dirs } ) {
            push @files, &Common::File::list_files( $dir );
        }
    }
    elsif ( not ref $dirs )
    {
        @files = &Common::File::list_files( $dirs );
    }
    else {
        &Common::Messages::error( qq (Directory should be a string or array reference) );
    }
    
    if ( $expr )
    {
        if ( $bool ) {
            @files = grep { $_->{"name"} =~ /$expr/ } @files;
        } else {
            @files = grep { $_->{"name"} !~ /$expr/ } @files;
        }            
    }

    @files = sort { $a->{"mtime"} <=> $b->{"mtime"} } @files;

    if ( @files ) {
        return $files[-1];
    } else {
        return;
    }
}
        
sub get_newest_file_epoch
{
    # Niels Larsen, January 2004.

    # Returns the epoch time of last modification of the most 
    # recent file in a given directory. If there are no files
    # zero is returned. 

    my ( $dirs,      # Directory path or list of paths
         $expr,      # Name filter expression, OPTIONAL
         $bool,      # Whether to match or not match
         ) = @_;

    # Returns an integer.

    my ( $file );

    $file = &Common::File::get_newest_file( $dirs, $expr, $bool );

    if ( $file ) {
        return $file->{"mtime"};
    } else {
        return 0;
    }
}

sub get_record_separator
{
    # Niels Larsen, October 2008.

    # Returns the record separator used in a given file.

    my ( $file,
        ) = @_;

    # Returns a string.

    my ( $sep, $ends );

    $ends = &Common::File::line_ends();

    if ( &Common::File::is_dos( $file ) ) {
        $sep = $ends->{"dos"};
    } elsif ( &Common::File::is_mac( $file ) ) {
        $sep = $ends->{"mac"};
    } else {
        $sep = $ends->{"unix"};
    }

    return $sep;
}

sub get_stats
{
    # Niels Larsen, May 2003.

    # Returns the most commonly used information about a file, like permission,
    # size etc. 

    my ( $path,   # Absolute file path
         ) = @_;

    # Returns a hash.

    my ( @stats, $mode, $type );

    if ( @stats = lstat $path )
    {
        $mode = $stats[2];
        
        if ( S_ISLNK $mode ) {
            $type = "l";
        } elsif ( S_ISDIR $mode ) {
            $type = "d";
        } elsif ( S_ISREG $mode ) {
            $type = "f";
        } else {
            $type = "?";
        }
        
        return 
        {
            "path" => $path,
            "name" => &File::Basename::basename( $path ),
            "dir" => &File::Basename::dirname( $path ),
            "type" => $type,
            "uid" => $stats[4] * 1,
            "gid" => $stats[5] * 1,
            "size" => defined $stats[7] ? $stats[7] * 1 : undef,
            "mtime" => $stats[8] * 1,
            "perm" => sprintf "%04o", $mode & 07777,
        };
    }
    else {
        return;
    }
}
    
sub get_type
{
    # Niels Larsen, January 2005.

    # Given a file, returns the message string from the GNU file 
    # program, or nothing if the file is not readable or is empty.

    my ( $file,     # Input file path
         ) = @_;

    # Returns a string or nothing.

    require Common::OS;

    my ( $line, $tmp_path );

    if ( -s $file and -r $file )
    {
        $line = ( &Common::OS::run_command_backtick( "file $file" ) )[0];

        if ( $line =~ /: ([^\n]+)/ ) {
            return $1;
        } else {
            &Common::Messages::error( qq (Wrong looking line -> "$line") );
        }
    }
    else {
        return;
    }
}
    
sub ghost_file
{
    # Niels Larsen, May 2003.

    # Deletes a file but adds its properties to a ghost file
    # list in the same directory as the file resides in. 

    my ( $path,         # File path 
         ) = @_;

    # Returns nothing.

    my ( $name, $dir, $files, $file, $ghosts, %ghosts );

    if ( -e $path ) 
    {
        $dir = &File::Basename::dirname( $path );
        $ghosts = &Common::File::list_ghosts( $dir );
        %ghosts = map { $_->{"name"}, 1 } @{ $ghosts };

        $file = &Common::File::get_stats( $path );

        if ( exists $ghosts{ $file->{"name"} } )
        {
            &Common::Messages::error( qq (The file "$file->{'name'}" exists, could not add it.) );
        }
        else {
            push @{ $ghosts }, $file;
        } 
        
        &Common::File::dump_file( "$dir/GHOST_FILES", $ghosts );
        &Common::File::delete_file( $path );
    }
    else {
        &Common::Messages::error( qq (Could not find the file\n$path), "GHOST FILE ERROR" );
    }
    
    return;
}

sub gzip_file
{
    # Niels Larsen, March 2007.

    # Runs GNU gzip on a given file and exits with message if something
    # wrong. 

    my ( $ifile,         # Input file
         $ofile,         # Output file - OPTIONAL
         ) = @_;

    # Returns nothing. 

    require Common::OS;

    my ( @stdout );
    
    if ( defined $ofile ) {
        @stdout = &Common::OS::run_command( "gzip -c $ifile > $ofile" );
    } else {
        @stdout = &Common::OS::run_command( "gzip $ifile" );
    }

    return;
}

sub guess_os
{
    # Niels Larsen, October 2009.

    # Reads fragments of a given file to see which kind of line ends
    # it contains. If "\r\n" dominates, then the string "dos" is returned,
    # if "\r" then "mac", otherwise "unix".

    my ( $file,           # File path
        ) = @_;

    # Returns a string.

    my ( $size, $len, $readon, $beg, $end, $fhs, $r_count, $n_count,
         $str, $stats, $ostype );

    $file = &Common::File::resolve_links( $file );

    $stats = &Common::File::get_stats( $file );

    if ( $stats ) {
        $size = $stats->{"size"};
    } else {
        &Common::Messages::error( qq (File not found -> "$file") );
    }

    $len = &List::Util::min( $size, 1000 );

    $readon = 1;
    $beg = 0;
    $end = $len - 1;
    $fhs = {};          # File handle hash so reopens are avoided

    $r_count = 0;
    $n_count = 0;

    while ( $readon )
    {
        $str = &Common::File::sysread_file( $file, $beg, $end );

        $r_count += $str =~ tr/\r/\r/;
        $n_count += $str =~ tr/\n/\n/;

        if ( $r_count > $n_count * 5 ) 
        {
            $ostype = "mac";
            $readon = 0;
        }
        elsif ( $n_count > $r_count * 5 )
        {
            $ostype = "unix";
            $readon = 0;
        }
        elsif ( $r_count > 0 and $n_count > 0 and 
                abs ( $r_count - $n_count ) < ( $r_count + $n_count ) / 5 )
        {
            $ostype = "dos";
            $readon = 0;
        }
        else
        {
            $beg += $len;
            $end += $len;
            
            if ( $beg >= $size ) {
                $readon = 0;
            } elsif ( $end >= $size ) {
                $end = $size - 1;
            }
        }
    }

    return $ostype;
}

sub gunzip_file
{
    # Niels Larsen, March 2007.

    # Runs GNU gunzip on a given file and exits with message if something
    # wrong. 

    my ( $ifile,         # Input file
         $ofile,         # Output file - OPTIONAL
         ) = @_;

    # Returns nothing. 

    require Common::OS;

    my ( @stdout );

    if ( defined $ofile ) {
        @stdout = &Common::OS::run_command( "gunzip -c $ifile > $ofile" );
    } else {
        @stdout = &Common::OS::run_command( "gunzip $ifile" );
    }

    return;
}

sub gzip_is_intact
{
    # Niels Larsen, September 2003.

    # Tests integrety of a given gzip'ed file. 

    my ( $file,    # Input file path
         ) = @_;

    # Returns 1 on success, nothing on failure. 

    my ( $error );

#    if ( $error = `zcat $file 2>&1 1>/dev/null` ) {
    if ( $error = `gzip -t $file` ) {
        return;
    } else {
        return 1;
    }
}

sub is_ascii
{
    # Niels Larsen, January 2005.

    # Check file type. There are perl modules for this (File::MMagic among 
    # others) but the best is the GNU file program. If the string "ASCII"
    # occurs case-insensitively in the message from file, and it has a 
    # non-zero size, then we say its an ascii file, otherwhile not.

    my ( $file,     # Input file path
         ) = @_;

    # Returns 1 or nothing.

    my ( $type );

    $type = &Common::File::get_type( $file );

    if ( $type and $type =~ /ASCII/i ) {
        return 1;
    }

    return;
}

sub is_compressed
{
    # Niels Larsen, January 2012. 

    # Returns 1 if the string returned by 'file -L' contains the 
    # word "compressed", otherwise nothing. 

    my ( $file,
        ) = @_;

    my ( $str, $out, $err );

    require Common::OS;

    return if not -r $file;

    &Common::OS::run3_command("file -L $file", undef, \$str, \$err );

    #if ( not defined $str )
    #{
    #    &error( qq (Returns undef: "file -L $file") );
    #}
    #elsif ( $str =~ /No such file or directory/ )
    #{
    #    &error( qq (Returns "No such file or directory": `file -L $file`) );
    #}        

    # &dump( $str );

    return 1 if defined $str and $str =~ /compressed|Zip archive/;

    return;
}

sub is_compressed_bzip2
{
    # Niels Larsen, March 2012. 

    # Returns 1 if the string returned by 'file -L' contains the 
    # word "bzip2 compressed", otherwise nothing. 

    my ( $file,
        ) = @_;

    my ( $str );

    $str = `file -L $file`;

    return 1 if $str =~ /bzip2 compressed/;

    return;
}

sub is_compressed_gzip
{
    # Niels Larsen, March 2012. 

    # Returns 1 if the string returned by 'file -L' contains the 
    # word "gzip compressed", otherwise nothing. 

    my ( $file,
        ) = @_;

    my ( $str );

    $str = `file -L $file`;

    return 1 if $str =~ /gzip compressed/;

    return;
}

sub is_compressed_zip
{
    # Niels Larsen, March 2012. 

    # Returns 1 if the string returned by 'file -L' contains the 
    # word "Zip archive", otherwise nothing. 

    my ( $file,
        ) = @_;

    my ( $str );

    $str = `file -L $file`;

    return 1 if $str =~ /Zip archive/;

    return;
}

sub is_dos
{
    # Niels Larsen, October 2005.

    # Tells if a given file name has Microsoft line-ends. 

    my ( $file,      # Input file path
         ) = @_;

    # Returns 1 or nothing.

    my ( $type );

    $type = &Common::File::guess_os( $file );

    if ( $type eq "dos" ) {
        return 1;
    }

    return;
}

sub is_handle
{
    # Niels Larsen, January 2007.

    # Returns 1 if the given argument is a file handle, otherwise nothing.

    my ( $file,
         ) = @_;

    # Returns 1 or nothing.

    if ( ref $file )
    {
        if ( ref $file eq "IO::File" ) {
            return 1;
        } else {
            &Common::Messages::error( qq (Wrong looking reference -> "$file") );
        }
    }
    
    return;
}

sub is_link
{
    my ( $file,          # File hash
         ) = @_;

    if ( not ref $file ) {
        $file = &Common::File::get_stats( $file );
    }

    if ( $file->{"type"} eq "l" )
    {
        return 1;
    }
    else {
        return;
    }
}

sub is_mac
{
    # Niels Larsen, August 2009.

    # Tells if a given file name has Apple line-ends. 

    my ( $file,      # Input file path
         ) = @_;

    # Returns 1 or nothing.

    my ( $type );

    $type = &Common::File::guess_os( $file );

    if ( $type eq "mac" ) {
        return 1;
    }

    return;
}

sub is_newer_than
{
    # Niels Larsen, April 2006.
    
    # Compares file dates: returns 1 if the modification date of file path 1
    # is more recent than that of file path 2, otherwise nothing. The two 
    # arguments may also be file lists (of hashes made by the listing routines
    # in this module), and then the newest dates among them is used. 

    my ( $file1,        # File path or list reference
         $file2,        # File path or list reference
         ) = @_;

    # Returns 1 or nothing. 

    my ( @max_days, $file, @days, $epoch );

    $epoch = &Common::Util::time_string_to_epoch();

    foreach $file ( $file1, $file2 )
    {
        if ( $file )
        {
            if ( ref $file )
            {
                @days = map { -M $_->{"path"} } @{ $file };
                
                if ( @days ) {
                    push @max_days, &List::Util::max( @days );
                } else {
                    push @max_days, 99999;    # about 100 years
                }
            }
            elsif ( -r $file )
            {
                push @max_days, -M $file;
            }
            else {
                &Common::Messages::error( qq (File does not exist -> "$file") );
            }
        }
        else {
            &Common::Messages::error( qq (Empty argument.) );
        }
    }

    if ( $max_days[0] < $max_days[1] ) {
        return 1;
    } else {
        return;
    }
}

sub is_regular
{
    # Niels Larsen, April 2003.

    # Checks if the given file is a regular file, i.e. it exists and is 
    # not a directory, link, block device etc. The routine returns the 
    # file mode (which is never zero) from stat if a regular file, 
    # otherwise nothing. 

    my ( $file,    # Given absolute file path
         ) = @_;

    # Returns an integer. 

    my $mode = ( stat( $file ) )[2];

    if ( S_ISREG $mode ) {
        return $mode;
    } else {
        return;
    }
}

sub is_stale_link
{
    my ( $link,
        ) = @_;

    if ( -l $link )
    {
        return 1;
    }

    return;
}

sub is_unix
{
    # Niels Larsen, August 2009.

    # Tells if a given file name has Unix line-ends. 

    my ( $file,      # Input file path
         ) = @_;

    # Returns 1 or nothing.

    my ( $type );

    $type = &Common::File::guess_os( $file );

    if ( $type eq "unix" ) {
        return 1;
    }

    return;
}

sub line_ends
{
    my ( %ends );

    %ends = (
        "mac" => "\r",
        "dos" => "\r\n",
        "win" => "\r\n",
        "unix" => "\n",
        );

    return wantarray ? %ends : \%ends;
}

sub list_all 
{
    # Niels Larsen, April 2003.

    # Lists files of any type in a given directory, with attributes. 
    # The returned list is a list of hashes where the keys are,
    # 
    # "name"      file name without directory
    # "path"      file name with directory prepended
    # "type"      d (directory), f (regular file), l (link) or ? (unknown)
    # "uid"       user id (a number)
    # "gid"       group id (a number)
    # "size"      byte size
    # "mtime"     epoch time of last modification
    # "perm"      string like 0755 etc 

    my ( $dir,    # Absolute directory path
         $expr,
         $msgs,
         ) = @_;
    
    # Returns a list.

    my ( @stats, $name, @stat, $mode, $type, $perm, $msg );

    @stats = ();

    if ( -e $dir )
    {
        if ( not -d $dir ) 
        {
            &Common::Messages::error( qq (
The path

 "$dir"

does not look like an absolute directory path. Please 
expand the path or make sure the format is right. 
) );
        }
        elsif ( not opendir DIR, $dir ) {
            &Common::Messages::error( qq (Could not read-open directory -> "$dir") );
        }

        while ( defined ( $name = readdir DIR ) )
        {
            chomp $name;

            if ( $name !~ /^\.\.?$/ ) {
                push @stats, &Common::File::get_stats( "$dir/$name" );
            }
        }

        if ( not closedir DIR ) {
            &Common::Messages::error( qq (Could not close read-opened directory -> "$dir") );
        }

        if ( defined $expr ) 
        {
            @stats = grep { $_->{"name"} =~ /$expr/x } @stats;
        }
    
        return wantarray ? @stats : \@stats;
    }
    else
    {
        $msg = qq (Directory does not exist -> "$dir");

        if ( defined $msgs ) {
            push @{ $msgs }, [ "Error", $msg ];
        } else {
            &Common::Messages::error( $msg );
        }
    }

    return;
}

sub list_directories
{
    # Niels Larsen, April 2003.

    my ( $dir,
         $expr,
         $msgs,
         ) = @_;

    # Returns a list. 

    my ( $dirs );
    
    $dirs = &Common::File::list_all( $dir, $expr, $msgs );

    @{ $dirs } = grep { $_->{"type"} eq "d" and $_->{"name"} !~ /^\./ } @{ $dirs };
    
    return wantarray ? @{ $dirs } : $dirs;
}

sub list_fastas
{
    # Niels Larsen, December 2006.

    # Lists the files where the name ends with ".fasta". 

    my ( $dir,           # Directory
         $expr,
         ) = @_;

    # Returns a list.

    my ( @files );

    @files = &Common::File::list_files( $dir, '\.fasta$' );

    if ( defined $expr ) {
        @files = grep { $_->{"name"} =~ /$expr/ } @files;
    }
    
    return wantarray ? @files : \@files;
}
    
sub list_files
{
    # Niels Larsen, April 2003.

    my ( $dir,
         $expr,
         $msgs,
         ) = @_;

    # Returns a list. 

    my ( $files );

    $files = &Common::File::list_all( $dir, $expr, $msgs );

    @{ $files } = grep { $_->{"type"} eq "f" and $_->{"name"} !~ /^\./ } @{ $files };

    return wantarray ? @{ $files } : $files;
}

sub list_files_find
{
    # Niels Larsen, February 2009.

    # Lists the files that match the given path expression. The path 
    # is expanded to all non-empty regular files. If a directory is given 
    # all regular non-empty files therein are returned. Returns a list of 
    # unambiguous paths that are relative to the current working directory.
    # TODO: use the File::Find module.

    my ( $path,   # Path expression
         $msgs,   # Outgoing messages
        ) = @_;

    # Returns a list.

    my ( @path, @files, $file, $expr, $dir, @msgs );

    $expr = &File::Basename::basename( $path );
    $dir = &File::Basename::dirname( $path );

    if ( -e $path )
    {
        if ( -f $path )
        {
            push @files, $path;
        }
        elsif ( -d $path )
        {
            @files = `find $path -print 2>&1`;
            
            if ( $? ) {
                push @msgs, [ "ERROR", "@files $!" ];
            }
        }
        else {
            push @{ $msgs }, [ "ERROR", qq (Not a regular file or directory: "$path") ];
        }
    }
    else
    {
        @files = `find $dir -name "$expr" -print 2>&1`;

        if ( $? ) {
            push @msgs, [ "ERROR", "@files $!" ];
        }
    }

    chomp @files;

    if ( @files )
    {
        @files = grep { -f $_ and -s $_ } @files;
    }
    else {
        push @{ $msgs }, [ "ERROR", qq (File(s) not found -> "$path") ];
    }

    if ( @msgs )
    {
        if ( $msgs )
        {
            push @{ $msgs }, @msgs;
            return;
        }
        else {
            &echo_messages( \@msgs );
            exit;
        }
    }

    return wantarray ? @files : \@files;
}

sub list_files_and_links
{
    # Niels Larsen, October 2007.

    my ( $dir,
         $expr,
         $msgs,
         ) = @_;

    # Returns a list. 

    my ( $files );

    $files = &Common::File::list_all( $dir, $expr, $msgs );

    @{ $files } = grep { ( $_->{"type"} eq "f" or $_->{"type"} eq "l" ) 
                             and $_->{"name"} !~ /^\./ } @{ $files };

    return wantarray ? @{ $files } : $files;
}

sub list_files_shell
{
    # Niels Larsen, March 2013. 

    my ( $paths,
         $msgs,
        ) = @_;

    my ( $path, $stdout, $stderr, @paths, $msg );

    if ( not $paths ) {
        &error( qq (No file paths given) );
    }

    $paths = [ $paths ] if not ref $paths;

    require Common::OS;

    foreach $path ( @{ $paths } )
    {
        $stdout = "";
        $stderr = "";
        
        if ( -d $path ) 
        {
            $path =~ s/\/$//;
            $path .= "/*";
        }

        &Common::OS::run3_command("ls -1 -d $path", undef, \$stdout, \$stderr, 0 );
        
        if ( $stderr ) 
        {
            $msg = ["ERROR", qq (No files "ls -1 -d $path") ];
            
            if ( $msgs ) {
                push @{ $msgs }, $msg;
            } else {
                &Common::Messages::error( $msg->[1] );
            }
        }
        elsif ( $stdout )
        {
            push @paths, split " ", $stdout;
        }
    }

    return wantarray ? @paths : \@paths;
}

sub list_files_tree
{
    # Niels Larsen, March 2013.

    # Lists the given directory recursively, with file sizes by
    # default. Returns text output. 

    my ( $dir,
         $opts,
        ) = @_;

    # Returns a string.
    
    my ( $stdout, $stderr );

    $opts //= "-snf --noreport";

    require Common::OS;

    &Common::OS::run3_command("tree $opts $dir", undef, \$stdout, \$stderr );

    if ( $stderr ) {
        &error( $stderr );
    }

    return $stdout;
}

sub list_ghosts
{
    # Niels Larsen, April 2003. 

    my ( $path,
         ) = @_;

    my ( $files );

    $files = [];

    if ( -e "$path/GHOST_FILES" )
    {
        $files = eval ${ &Common::File::read_file( "$path/GHOST_FILES" ) };
    }

    wantarray ? return @{ $files } : return $files;
}

sub list_infos
{
    # Niels Larsen, December 2006.

    # Lists the files where the name ends with ".info". 

    my ( $dir,           # Directory
         $expr,
         $msgs,
         ) = @_;

    # Returns a list.

    my ( @files );

    @files = &Common::File::list_files( $dir, '\.info$', $msgs );

    if ( defined $expr ) {
        @files = grep { $_->{"name"} =~ /$expr/ } @files;
    }
    
    return wantarray ? @files : \@files;
}

sub list_links
{
    # Niels Larsen, March 2005.

    my ( $dir,
         $expr,
         $msgs,
         ) = @_;
    
    # Returns a list.

    my ( $files );

    $files = &Common::File::list_all( $dir, $expr, $msgs );
    
    @{ $files } = grep { $_->{"type"} eq "l" and $_->{"name"} !~ /^\./ } @{ $files };
    
    wantarray ? return @{ $files } : $files;
}

sub list_modules
{
    # Niels Larsen, January 2010.

    # Creates a list of all perl modules starting recursively at a given directory.

    my ( $dir,    # Starting directory - OPTIONAL, default base module directory
        ) = @_;

    my ( @files );

    $dir = $Common::Config::plm_dir if not defined $dir;

    @files = &Common::File::list_files_find( $dir );
    @files = grep { $_ =~ /\.pm$/ } @files;

    return wantarray ? @files : \@files;
}

sub list_pats
{
    # Niels Larsen, December 2006.

    # Lists the files where the name ends with ".pat". 

    my ( $dir,           # Directory
         $expr,
         $msgs,
         ) = @_;

    # Returns a list.

    my ( @files );

    @files = &Common::File::list_files( $dir, '\.pat$', $msgs );

    if ( defined $expr ) {
        @files = grep { $_->{"name"} =~ /$expr/ } @files;
    }
    
    return wantarray ? @files : \@files;
}
    
sub list_pdls
{
    # Niels Larsen, December 2006.

    # Lists the files where the name ends with ".pdl". Note that a ".info"
    # file always accompanies the ".pdl" file.

    my ( $dir,           # Directory
         $expr,
         $msgs,
         ) = @_;

    # Returns a list.

    my ( @files );

    @files = &Common::File::list_all( $dir, '\.pdl$', $msgs );

    if ( defined $expr ) {
        @files = grep { $_->{"name"} =~ /$expr/ } @files;
    }
    
    return wantarray ? @files : \@files;
}

sub read_file
{
    # Niels Larsen, March 2003.

    # Reads the content of a file into a string and returns a 
    # reference to that string. 

    my ( $file,    # Absolute file path
         ) = @_;

    # Returns string. 

    my ( $fh, $content );

    $fh = &Common::File::get_read_handle( $file );

    {
        local $/ = undef;
    
        $content = <$fh>;

        # Make Unix line ends,

        $content =~ s/\r\n/\n/g;
        $content =~ s/\r/\n/g;
    }

    &Common::File::close_handle( $fh );
    
    return \$content;
}

sub read_ids
{
    my ( $file,
        ) = @_;

    my ( $fh, $line, @ids );

    $fh = &Common::File::get_read_handle( $file );

    while ( defined ( $line = <$fh> ) )
    {
        chomp $line;
        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        
        push @ids, $line;
    }

    &Common::File::close_handle( $fh );

    return wantarray ? @ids : \@ids;
}
    
sub read_lines
{
    # Niels Larsen, December 2011.

    # Reads the first n lines from a file. If no number given,
    # all lines are read. Returns a list of lines. 

    my ( $file,
         $num,
        ) = @_;

    # Returns a list.

    my ( $fh, $line, @lines, $i );

    $fh = &Common::File::get_read_handle( $file );

    @lines = ();
    $i = 0;

    if ( defined $num )
    {
        while ( $i < $num and defined ( $line = <$fh> ) )
        {
            push @lines, $line;
            $i += 1;
        }
    }
    else 
    {
        while ( defined ( $line = <$fh> ) )
        {
            push @lines, $line;
        }
    }

    &Common::File::close_handle( $fh );

    return wantarray ? @lines : \@lines;
}
    
sub read_keyboard
{
    # Niels Larsen, March 2005.

    # Reads one line from STDIN with a given timeout in seconds, or fractions 
    # of seconds. A prompt string and an echo flag may be given. Accidential
    # control-key sequences are ignored, but delete and backspace works. A
    # string is returned. 

    my ( $timeout,       # Seconds
         $prompt,        # Prompt string
         $echo,          # True or false
         ) = @_;

    # Returns a string. 

    my ( $word, $char, $ch );

    $prompt = "" if not defined $prompt;
    $echo = 1 if not defined $echo;

    require Term::ReadKey;

    &Term::ReadKey::ReadMode( "raw" );

    $word = "";
    $timeout = 1 if $timeout < 1;

  PROMPT: 

    print STDERR $prompt;
    $word = "";
    
    while ( 1 )
    {
        # Read one character,

        $char = &Term::ReadKey::ReadKey( $timeout );

        # Get characters entered faster than a human would be able to. This 
        # should catch multi-character control sequences,

        while ( $ch = &Term::ReadKey::ReadKey( 0.01 ) )
        {
            $char .= $ch;
        }

        if ( defined $char and length $char > 1 ) 
        {
            # Start over, which blanks out the string,

            print STDERR "Control-key ignored, start again\n";
            goto PROMPT;
        }
        elsif ( defined $char ) 
        {
            if ( ord $char > 32 and ord $char < 127 )
            { 
                # Normal characters, 

                $word .= $char;
                &echo( $char ) if $echo;
            }
            elsif ( ord $char == 8 or ord $char == 127 )
            {
                # Backspace and deletes,

                substr( $word, (length $word) - 1 ) = "";
            }
            elsif ( $char eq "\n" or $char eq "\r" )
            {
                last;
            }
            else
            {
                if ( $char ne "\n" and $char ne "\r" ) {
                    print STDERR "Control-key ignored, start again\n";
                }

                goto PROMPT;
            }
        }
        else {
            last;
        }
    }

    &Term::ReadKey::ReadMode( "normal" );

    return $word;
}

sub read_stdin
{
    my ( $ifh, $line, @lines );

    $ifh = &Common::File::get_read_handle();
#    $ifh->blocking( 0 );
        
    while ( defined ( $line = <$ifh> ) )
    {
        chomp $line;
        push @lines, $line;
    }
    
    $ifh->close;

    return wantarray ? @lines : \@lines;
}
    
sub read_yaml
{
    my ( $file,
         ) = @_;

    require YAML::XS;

    if ( -r $file ) {

        return &YAML::XS::LoadFile( $file );
    }
    elsif ( not -e $file ) {
        &Common::Messages::error( qq (File does not exist -> "$file") );
    } else {
        &Common::Messages::error( qq (File is not readable -> "$file") );
    }

    return;
}

sub rename_file
{
    my ( $file1,
         $file2,
        ) = @_;

    if ( not rename $file1, $file2 ) {
        &Common::Messages::error( qq (Could not rename "$file1" to "$file2"\nSystem message: $!) );
    }

    return;
}

sub resolve_links
{
    # Niels Larsen, May 2009.

    # Follows a given link path until a real file is found or there is a
    # dead end. Returns the full path of the real file, or nothing.
    
    my ( $link,
         $fatal,
        ) = @_;

    # Returns a string or nothing.
 
    my ( $path, $pwd, $orig_dir );

    $fatal = 0 if not defined $fatal;

    if ( not -l $link )
    {
        return &Cwd::abs_path( $link );
    }

    $orig_dir = &Cwd::getcwd;

    while ( $path = readlink $link )
    {
        chdir &File::Basename::dirname( $link );
        $path = &Cwd::abs_path( $path );
        
        if ( -e $path )
        {
            if ( -l $path ) {
                $link = $path;
            } else {
                last;
            }
        }
        elsif ( $fatal ) 
        {
            &Common::Messages::error( qq (Dead link -> "$link") );
        }
        else 
        {
            $path = undef;
            last;
        }
    }

    chdir $orig_dir;

    return $path;
}

sub retrieve_file
{
    # Niels Larsen, May 2003.

    # Retrieves from file a data structure saved with Storable::store

    my ( $path,    # File path
         ) = @_;

    # Returns a hash.
    
    my ( $struct );

    if ( -r $path )
    {
#         if ( &Common::File::is_ascii( $path ) )
#         {
#             $struct = &Common::File::eval_file( $path );
#             &Common::File::delete_file( $path );
#             &Common::File::store_file( $path, $struct );
#         }
#         else {
            $struct = &Storable::retrieve( $path );
#        }
    }
    else {
        &Common::Messages::error( qq (Could not load the file "$path"), "RETRIEVE FILE ERROR" );
    }

    wantarray ? return %{ $struct } : return $struct;
}

sub save_stdin
{
    # Niels Larsen, March 2010.

    # Writes STDIN line by line to the given file. Returns the number of lines.

    my ( $file,       # File path
        ) = @_;

    # Returns integer. 

    my ( $fh, $line, $count );

    $fh = &Common::File::get_write_handle( $file );
    $count = 0;

    while ( defined ( $line = <STDIN> ) )
    {
        $fh->print( $line );
        $count += 1;
    }
    
    $fh->close;

    return $count;
}
    
sub seek_file
{
    # Niels Larsen, March 2003.
    
    # Extracts a region from a file, given a file name (an
    # absolute path) and 0-based begin and end positions.

    my ( $file,      # File path or handle
         $beg,       # Byte start position - OPTIONAL, start of file
         $len,       # Length - OPTIONAL, default rest of file
         ) = @_;

    # Returns string. 

    my ( $close_handle, $str, $handle );

    if ( ref $file )
    {
        $handle = $file;
    }
    else
    {
        $handle = new IO::Handle;
        sysopen $handle, $file, 0;

        $close_handle = 1;
    }

    sysseek( $handle, $beg, 0 );
    sysread( $handle, $str, $len );

    $handle->close if $close_handle; 

    return \$str;
}

sub store_file
{
    # Niels Larsen, May 2003.

    # Writes a data structure to file using Storable::store.

    my ( $path, 
         $struct,
         ) = @_;

    # Returns nothing. 

    if ( not $struct ) {
        &Common::Messages::error( qq (No data given) );
    }

    if ( not &Storable::store( $struct, $path ) ) {
        &Common::Messages::error( qq (Could not save to the file "$path"), "STORABLE::STORE ERROR");
    }

    return;
}

sub sysopen_file
{
    # Niels Larsen, February 2010.

    my ( $file,
	 $mode,
	 $perms,
	) = @_;

    my ( $fh );

    $mode = 0 if not defined $mode;

    $fh = new IO::Handle;

    if ( not ( sysopen $fh, $file, $mode ) ) {
	&Common::Messages::error( qq (Could not sysopen file -> "$file") );
    }

    return $fh;
}

sub sysread_file
{
    # Niels Larsen, March 2003.
    
    # Extracts a region from a file, given a file name (an
    # absolute path) and 0-based begin and end positions.

    my ( $file,      # File path
         $beg_pos,   # Byte start position - OPTIONAL
         $end_pos,   # Byte end position - OPTIONAL
         $handles,   # Hash of file handles - OPTIONAL
         ) = @_;

    # Returns string. 

    my ( $handle, $str, $error );

    if ( $handles )
    {
        if ( exists $handles->{ $file } )
        {
            $handle = $handles->{ $file };
        }
        else
        {
            $handle = new IO::Handle;
            sysopen $handle, $file, 0;
            $handles->{ $file } = $handle;
        }

        sysseek( $handle, $beg_pos, 0 );
        sysread( $handle, $str, $end_pos-$beg_pos+1 );
    }
    else
    {
        $handle = new IO::Handle;
        sysopen $handle, $file, 0;

        sysseek( $handle, $beg_pos, 0 );
        sysread( $handle, $str, $end_pos-$beg_pos+1 );

        $handle->close;
    }

    if ( $error ) {
        &Common::Messages::error( qq (Sys_read error -> "$error") );
    } else {
        return $str;
    }
}

sub touch_file
{
    # Niels Larsen, December 2010.

    # Append-opens a file and closes it again immediately.

    my ( $file,
        ) = @_;

    my ( $fh );

    if ( $fh = &Common::File::get_append_handle( $file ) )
    {
        &Common::File::close_handle( $fh );
    }

    return;
}

sub truncate_file
{
    # Niels Larsen, September 2003.

    # Truncates a given file so that everything after a given 
    # byte position is deleted. 

    my ( $file,    # File path
         $fpos,    # File position
         ) = @_;

    # Returns nothing. 

    my ( $fh );
    
    $fh = &Common::File::get_append_handle( $file );
    
    if ( truncate $fh, $fpos )
    {
        &Common::File::close_handle( $fh );
    }
    else
    {
        &Common::File::close_handle( $fh );
        &Common::Messages::error( qq (Truncation to position "$fpos" failed on the file "$file") );
    }

    return;
}   

sub unpack_archive
{
    # Niels Larsen, April 2009.

    # Unpacks the given file archive in the current directory.

    my ( $file,
         $errors,
         ) = @_;

    # Returns nothing. 

    require Common::OS;

    if ( $file =~ /\.tar$/ ) 
    {
        &Common::OS::run_command_backtick( "tar -xf $file", undef, $errors );
    }
    elsif ( $file =~ /\.tar\.gz|\.tgz$/ )
    {
        # Keep <, silences a bug on mac
        &Common::OS::run_command_backtick( "zcat < $file | tar -x", undef, $errors );
    }
    elsif ( $file =~ /\.zip$/ ) 
    {
        &Common::OS::run_command_backtick( "unzip $file", undef, $errors );
    }
    elsif ( $file =~ /\.bz2$/ )
    {
        &Common::OS::run_command_backtick( "tar -xjf $file", undef, $errors );
#        &Common::OS::run_command_backtick( "bzcat < $file | tar -x", undef, $errors );
    }
    else {
        &Common::Messages::error( qq (Wrong looking archive path -> "$file") );
    }

    return;
}

sub unpack_archive_inplace
{
    # Niels Larsen, August 2006.

    # Unpacks the given file archive in the directory where the file is. 

    my ( $file,
         ) = @_;

    # Returns nothing. 

    my ( @stderr, $orig_dir, $dir );

    $orig_dir = &Cwd::getcwd();
    $dir = &File::Basename::dirname( $file );
    
    if ( not chdir $dir ) {
         &Common::Messages::error( qq (Could not change to directory -> "$dir") );
    }

    &Common::File::unpack_archive( $file, \@stderr );

    chdir $orig_dir;

    if ( @stderr ) {
        @stderr = map { $_->[1] } @stderr;
        &Common::Messages::error( \@stderr );
    }

    return;
}

sub unzip_files_single
{
    # Niels Larsen, March 2013.

    # Creates an original file for each of the given zip files, and optionally
    # deletes the zip file(s). The unzipping is done in parallel. Returns the 
    # number of files unzipped. 

    my ( $files,     # File path list
         $cores,     # Number of cores to use - OPTIONAL, default all available
         $delete,    # Delete originals - OPTIONAL, default 1
        ) = @_;

    # Returns integer.

    my ( $ok, $stdout, $stderr, $filstr, $cmd );

    $files = [ $files ] if not ref $files;
    $delete = 1 if not defined $delete;

    $filstr = join " ", @{ $files };

    $stdout = "";
    $stderr = "";

    $cmd = "ls -1 $filstr | parallel";
    $cmd .= " -P $cores" if $cores;
    $cmd .= " 'unzip -j -o -u -q -d {//} {}'";

    {
        local %ENV = %ENV;
        &Common::Config::set_perl5lib_min();

        no warnings;
        $ok = &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr, 0 );
    }
    
    if ( not $ok or $stdout or $stderr )
    {
        $stdout =~ s/^\s*//;
        $stdout =~ s/\s*$//;
        
        $stderr =~ s/^\s*//;
        $stderr =~ s/\s*$//;
        
        &error( qq (Problem with this unzip command:\n)
                .qq (STDOUT: $stdout\n)
                .qq (STDERR: $stderr\n)
                .qq (COMMAND: $cmd\n)
            );
    }

    if ( $delete ) {
        &Common::File::delete_files( $files );
    }

    return scalar @{ $files };
}

sub write_file
{
    # Niels Larsen, March 2003.
    
    # Writes content to a file, with no change. It is up to the caller
    # to make sure there are newlines etc. Content can be a string or
    # a string reference. The write mode can be ">" (overwrite) or ">>" 
    # (append). 
    
    my ( $file,      # File path
         $sref,      # Input string, string-reference or list-reference
         $clob,      # Deletes existing file - OPTIONAL, default 0
         ) = @_;

    # Returns nothing.

    my ( $fh );

    if ( not $sref ) {
        &Common::Messages::error( qq (\$sref has zero size.) );
    }

    if ( $clob ) {
        &Common::File::delete_file_if_exists( $file );
    }

    $fh = &Common::File::get_write_handle( $file );
    
    if ( not ref $sref )
    {
        if ( not print $fh $sref ) {
            &Common::Messages::error( qq (Could not write to "$file") );
        }
    }
    elsif ( ref $sref eq "SCALAR" )
    {
        if ( not print $fh ${ $sref } ) {
            &Common::Messages::error( qq (Could not write to "$file") );
        }
    } 
    elsif ( ref $sref eq "ARRAY" )
    {
        if ( not print $fh @{ $sref } ) {
            &Common::Messages::error( qq (Could not write to "$file") );
        }
    } 
    else
    {
        my $ref = ref $sref;
        &Common::Messages::error( qq(
Type $ref is not recognized as input reference. Please supply 
either a string or a string reference. 
                                    ) );
    }

    &Common::File::close_handle( $fh );

    return;
}

sub write_yaml
{
    # Niels Larsen, April 2011.

    # Writes YAML from a given structure to file or STDOUT. 

    my ( $file,      # File path or handle
         $struct,    # Structure
         $clobber,   # Overwrite flag - OPTIONAL, default false
         ) = @_;

    # Returns nothing.

    my ( $str );

    require YAML::XS;

    $clobber = 0 if not defined $clobber;

    if ( $clobber and defined $file ) {
        &Common::File::delete_file_if_exists( $file );
    }

    if ( ref $struct and ref $struct eq "ARRAY" ) {
        &YAML::XS::DumpFile( $file, @{ $struct } );
    } else {
        &YAML::XS::DumpFile( $file, $struct );
    }

    return;
}

sub zip_files_single
{
    # Niels Larsen, March 2013.

    # Creates a zip file for each of the given files, and optionally deletes 
    # the original. The zip is done in parallel. Returns the number of zipped
    # files.

    my ( $files,     # File path list
         $cores,     # Number of cores to use - OPTIONAL, default all available
         $delete,    # Delete originals - OPTIONAL, default 1
        ) = @_;

    # Returns integer.
    
    my ( $ok, $stdout, $stderr, $filstr, $cmd );

    $files = [ $files ] if not ref $files;
    $delete = 1 if not defined $delete;

    $filstr = join " ", @{ $files };

    $stdout = "";
    $stderr = "";

    $cmd = "ls -1 $filstr | parallel";
    $cmd .= " -P $cores" if $cores;
    $cmd .= " zip -o -q {}.zip {}";

    {
        local %ENV = %ENV;
        &Common::Config::set_perl5lib_min();
        
        no warnings;
        $ok = &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr, 0 );
    }
    
    if ( not $ok or $stdout or $stderr )
    {
        $stdout =~ s/^\s*//;
        $stdout =~ s/\s*$//;
        
        $stderr =~ s/^\s*//;
        $stderr =~ s/\s*$//;
        
        &error( qq (Problem with this zip command:\n)
                .qq (STDOUT: $stdout\n)
                .qq (STDERR: $stderr\n)
                .qq (COMMAND: $cmd\n)
            );
    }

    if ( $delete ) {
        &Common::File::delete_files( $files );
    }

    return scalar @{ $files };
}

1;

__END__

# sub append_file_lock
# {
#     # Niels Larsen, March 2003.
    
#     # Appends memory content to a file while getting exclusive write 
#     # access. It is up to the caller to make sure there are newlines 
#     # etc. Content can be a string or a tring reference. The write 
#     # mode can be ">" (overwrite) or ">>" (append). If the routine 
#     # fails to get exclusive write access, then 0 is returned and 
#     # nothing is appended; if it does complete, then 1 is returned.
#     # This makes it possible to call the function again later.

#     my ( $file,    # File path or handle
#          $sref,    # Input string, string-reference or list-reference
#          ) = @_;

#     # Returns nothing.

#     my ( $ref );
    
#     if ( not $sref ) {
#         &Common::Messages::error( qq (\$sref has zero size.) );
#     }
    
#     if ( ref $file ) 
#     {




#         if ( not open FILE, ">> $file" ) {
#             &Common::Messages::error( qq(Could not append-open file -> "$file") );
#         }
#     }
    
#     if ( not ref $sref )
#     {
#         if ( not print FILE $sref ) {
#             &Common::Messages::error( qq(Could not append to "$file") );
#         }
#     }
#     elsif ( ref $sref eq "SCALAR" )
#     {
#         if ( not print FILE ${ $sref } ) {
#             &Common::Messages::error( qq(Could not append to "$file") );
#         }
#     } 
#     else
#     {
#         $ref = ref $sref;
#         &Common::Messages::error( qq(
# Type $ref is not recognized as input reference. Please supply 
# either a string or a string reference. 
# ) );
#     }

#     if ( not close FILE, $file ) {
#         &Common::Messages::error( qq(Could not close append-opened file -> "$file") );
#     }

#     return;
# }


# sub basic_write_file {
#     my($file,$list) = @_;
#     my($i,$rc);

# #    use Fcntl qw /:flock/;

#     if (!open(TMP,">$file"))
#     {
#         warn "failed to write-open $file\n";
#         return 0;
#     }
# #    elsif ( not flock TABLE, LOCK_EX )
# #    {
# #        warn qq (ERROR: failed to get exclusive write-access to $file\n);
# #        return 0;
# #    }

#     $rc = 1;
#     for ($i=0; $rc && ($i <= $#{$list}); $i++)
#     {
#         $rc = (print TMP $list->[$i]);
#         if (! $rc)
#         {
#             warn "FAILED on a print to $file\n";
#         }
#     }

# #    if ( not ( flock TMP, LOCK_UN ) or 
# #         not ( close TMP ) )
# #    {
# #        warn qq (ERROR: could not close write-access to "$file"\n);
# #    }

#     close TMP;

#     if ($rc) { system "chmod 777 $file"; }
#     return $rc;
# }
