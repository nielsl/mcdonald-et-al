package Common::Storage;     #  -*- perl -*-

# Functions that retrieve or list files locally or on the network:
# the URI determines where to look and which protocol to use. These
# are the routines you should program with, rather than the protocol
# specific ones. The aim of these routines is the support several
# protocols and be simple to use. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use URI;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_sizes
                 &append_file
                 &append_ghosts
                 &both_lists
                 &copy_file
                 &copy_files
                 &delete_file
                 &delete_ghosts
                 &diff_files
                 &diff_lists
                 &fetch_files_curl
                 &fetch_files_wget
                 &fetch_file
                 &ghost_file
                 &index_table
                 &list_all
                 &list_dirs
                 &list_files
                 &list_ghosts
                 &list_links
                 &nodup_list
                 &predict_space
                 &read_file
                 &write_file
                 &write_ghosts
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::File;
use Common::FTP;
use Common::HTTP;
use Common::Names;
use Common::OS;
use Common::DBM;

use Registry::Paths;
use Net::OpenSSH;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_sizes
{
    # Niels Larsen, April 2003.

    # Returns the total number of bytes for the files in a list 
    # generated with the list functions in this module.

    my ( $list,    # File list 
         ) = @_;

    # Returns an integer. 

    my ( $elem, $total );

    $total = 0;

    foreach $elem ( @{ $list } )
    {
        $total += $elem->{"size"};
    }

    return $total;
}

sub append_file
{
    my ( $file,
         $sref,
         $user,
         $pass,
         ) = @_;
    
    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    if ( &Common::Names::is_local_uri( $file ) )
    {
        &Common::File::append_file( $file, $sref );
    }
    elsif ( &Common::Names::is_ftp_uri( $file ) )
    {
        &Common::FTP::append_file( $file, $sref, $user, $pass );
    }
    
    return;
}   

sub append_ghosts
{
    # Niels Larsen, July 2003.

    # Appends a file property hash to a list of other such "ghost files". 
    # A ghost file does not exist but its name and properties are given 
    # in the file ".ghost_file_list" in the given directory.

    my ( $duri,      # Directory location (URI or absolute path)
         $file,      # File hash to be added
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;

    # Returns nothing. 

    $user ||= "anonymous";
    $pass ||= "anonymous";

    my ( $files, %names );

    $files = &Common::Storage::list_ghosts( $duri, $user, $pass, $errors );
    
    %names = map { $_->{"name"}, 1 } @{ $files };

    if ( exists $names{ $file->{"name"} } )
    {
        &error( qq (The file "$file->{'name'}" exists, could not add it.),
                    "GHOSTS FILE ERROR" );
    }
    else {
        push @{ $files }, $file;
    } 
    
    &Common::Storage::write_ghosts( $duri, $files, $user, $pass, $errors );

    return;
}

sub both_lists
{
    # Niels Larsen, April 2003.
    
    # For each file hash in a list (first argument), checks if that file 
    # is also in another list (second argument). The match criterion is 
    # that all keys in a given list (third argument) have the same value.
    # The routine returns a list of file hashes in list context and the
    # number of "identical" files in scalar context.

    my ( $files1,     # Files list
         $files2,     # Files list
         $keys,       # List of keys, e.g. [ "name", "size" ] - OPTIONAL
         ) = @_;
    
    # Returns a list or an integer. 
    
    $keys = [ "name" ] if not $keys;
    
    my ( %files2, $file1, $file2, $name1, $key, @both, $same );
    
    %files2 = map { $_->{"name"} => $_ } @{ $files2 };
    
    foreach $file1 ( @{ $files1 } )
    {
        $name1 = $file1->{"name"};
        
        if ( exists $files2{ $name1 } )
        {
            $file2 = $files2{ $name1 };
            $same = 1;
            
            foreach $key ( @{ $keys } )
            {
                if ( $file1->{ $key } ne $file2->{ $key } )
                {
                    $same = 0;
                    last;
                }
            }
            
            if ( $same ) {
                push @both, dclone $file1;
            }
        }
    }
    
    return wantarray ? @both : \@both;
}

sub copy_file
{
    # Niels Larsen, April 2010.
    # UNFINISHED

    # Copies a single file from location 1 to location 2, where each can
    # be either local or remote. The URI protocols supported are file, 
    # http, ftp, scp, sftp and local file names are valid too. 

    my ( $loc1,     # File URI or path, source file
         $loc2,     # File URI or path, destination file or directory
         $args,     # Configuration switches - OPTIONAL
         $msgs,     # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $uri1, $uri2, $fh, $dir, $conf, $tmp_dir, $dst_dir, $tmp_path,
         $src_name );
    
    require File::Fetch;

    $conf->{"user"} = $args->{"user"} // "";
    $conf->{"pass"} = $args->{"pass"} // "";
    $conf->{"timeout"} = $args->{"timeout"} // 15;
    $conf->{"create"} = $args->{"create"} // 0;
    $conf->{"debug"} = $args->{"debug"} // 0;

    $uri1 = URI->new( $loc1 )->canonical;
    $uri2 = URI->new( $loc2 )->canonical;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> REMOTE SOURCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $uri1->scheme and $uri1->scheme =~ /^rsync|sftp|scp|ftp|http$/ )
    {
        if ( not defined $uri2->scheme or $uri2->scheme eq "file" ) 
        {
            $dst_dir = &File::Basename::dirname( $loc2 );
            
            if ( $conf->{"create"} ) {
                &Common::File::create_dir_if_not_exists( $dst_dir );
            }
            
            # >>>>>>>>>>>>>>>>>>> LOCAL DESTINATION <<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $uri1->scheme and $uri1->scheme =~ /^sftp|scp$/ )  
            {
                &error( "SSH based copying not implemented yet" );
            }
            else
            {
                # First copy to a temporary directory,

                $tmp_dir = "$loc2.download";
                
                local $File::Fetch::WARN = 0;
                
                $fh = File::Fetch->new( "uri" => $loc1 );
                $fh->fetch( "to" => $tmp_dir );
                
                if ( $fh->error ) {
                    &Common::File::delete_dir_tree_if_exists( $tmp_dir );
                    &error( $fh->error );
                }
            }
                
            # Then move download into place,
            
            $src_name = &File::Basename::basename( $loc1 );
            
            if ( -d $loc2 ) {
                &Common::File::rename_file( "$tmp_dir/$src_name", "$loc2/$src_name" );
            } else {
                &Common::File::rename_file( "$tmp_dir/$src_name", $loc2 );
            }

            &Common::File::delete_dir_tree( $tmp_dir );
        }
        else {
            &error( "Remote <-> remote copying not yet implemented" );
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LOCAL SOURCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    else
    {
        if ( defined $uri2->scheme and $uri2->scheme =~ /^ftp|http|rsync|sftp|scp$/ )
        {
            &error( "Local -> remote copying not yet implemented" );
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>> LOCAL DESTINATION <<<<<<<<<<<<<<<<<<<<<<<<<<<

            &Common::File::copy_file( $loc1, $loc2 );
        }
    }

    return;
}

sub copy_file_old
{
    # Niels Larsen, April 2003.

    # Copies a single file to a destination. 

    my ( $uri1,     # File URI or path, source
         $uri2,     # File URI or path, destination
         $user,     # Destination host login user name - OPTIONAL
         $pass,     # Destination host login password - OPTIONAL
         ) = @_;

    # Returns nothing.

    $user ||= "anonymous";
    $pass ||= "anonymous";

    if ( &Common::Names::is_local_uri( $uri1 ) )
    {
        if ( &Common::Names::is_local_uri( $uri2 ) )
        {
            &Common::File::copy_file( $uri1, $uri2 );
        }
        elsif ( &Common::Names::is_ftp_uri( $uri2 ) )
        {
            &Common::FTP::upload_file( $uri1, $uri2, $user, $pass );
        }
        else
        {
            &error( qq (The system could not copy\n\n"$uri1"  to
"$uri2"\n\nbecause the second file path does not look like a local file or an ftp file.), "FORMAT ERROR" );
            exit;
        }
    }
    elsif ( &Common::Names::is_ftp_uri( $uri1 ) )
    {
        if ( &Common::Names::is_local_uri( $uri2 ) ) 
        {
            &Common::FTP::download_file( $uri1, $uri2, $user, $pass );
        }
        else 
        {
            &error( qq (The system could not copy\n\n"$uri1"  to
"$uri2"\n\nbecause the second file path does not look like a local file.), "FORMAT ERROR" );
            exit;
        }
    }
    elsif ( &Common::Names::is_http_uri( $uri1 ) )
    {
        if ( &Common::Names::is_local_uri( $uri2 ) ) 
        {
            &Common::HTTP::download_file( $uri1, $uri2 );
        }
        else 
        {
            &error( qq (The system could not copy\n\n"$uri1"  to
"$uri2"\n\nbecause the second file path does not look like a local file.), "FORMAT ERROR" );
            exit;
        }
    } 

    return;
}

sub copy_files
{
    # Niels Larsen, April 2010. UNFINISHED

    # Copies files from one remote or local location to another remote or local
    # location. The from-URI may contain shell-like wildcard characters ('*', 
    # '[]' and '?'). Valid URI types are files (both file:// and plain local 
    # paths), http, ftp, scp and sftp. Passwords are used if given. Ideally 
    # all file copy requests should use this routine. 

    my ( $loc1,      # From-URI or path
         $loc2,      # To-URI directory path
         $args,      # Configuration switches - OPTIONAL
         $msgs,      # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $uri1, $uri2, @copied );
    
    $uri1 = URI->new( $loc1 );
    $uri2 = URI->new( $loc2 );

    if ( defined $uri1->scheme and $uri1->scheme =~ /^rsync|sftp|scp|ftp|http|https$/ )
    {
        if ( not defined $uri2->scheme or $uri2->scheme eq "file" ) 
        {
            # >>>>>>>>>>>>>>>>>>>>>> REMOTE -> LOCAL <<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $uri1->scheme and $uri1->scheme =~ /^sftp|scp$/ )  
            {
                # Secure download,

                &error( "Secure download not implemented yet" );
            }
            else
            {
                # Insecure download,
                
                @copied = &Common::Storage::fetch_files_curl( $loc1, $loc2, $args, $msgs );
            }
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>>> REMOTE -> REMOTE <<<<<<<<<<<<<<<<<<<<<<<<<

            &error( "Remote <-> remote copying not yet implemented" );
        }
    }
    else
    {
        if ( defined $uri2->scheme and $uri2->scheme =~ /^ftp|http|rsync|sftp|scp$/ )
        {
            # >>>>>>>>>>>>>>>>>>>>>> LOCAL -> REMOTE <<<<<<<<<<<<<<<<<<<<<<<<<<

            &error( "Upload not yet implemented" );
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>>> LOCAL -> LOCAL <<<<<<<<<<<<<<<<<<<<<<<<<<<

            &Common::File::copy_file( $loc1, $loc2 );
        }
    }

    return wantarray ? @copied : \@copied;
}

sub delete_file
{
    my ( $furi,    # Remote file URI
         $user,    # Remote login name - OPTIONAL
         $pass,    # Remote password - OPTIONAL
         ) = @_;
    
    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    if ( &Common::Names::is_local_uri( $furi ) )
    {
        &Common::File::delete_file( $furi );
    }
    elsif ( &Common::Names::is_ftp_uri( $furi ) )
    {
        &Common::FTP::delete_file( $furi, $user, $pass );
    }
    
    return;
}    

sub delete_ghosts
{
    # Niels Larsen, July 2003.

    # Deletes all ghosts files with the given name from the ghost 
    # file registry file in a given directory, local or remote. 
    
    my ( $duri,      # Directory location (URI or absolute path)
         $name,      # File hashes to be written
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;
    
    # Returns nothing.

    my ( @files );

    $user ||= "anonymous";
    $pass ||= "anonymous";

    @files = grep { $_->{"name"} ne $name }  @{ &Common::Storage::list_ghosts( $duri, $user, $pass, $errors ) };

    &Common::Storage::write_ghosts( $duri, \@files, $user, $pass );

    return;
}

sub diff_files
{
    # Niels Larsen, April 2003.

    # For each regular file in a given directory (first argument), checks 
    # if that file is absent or has different attributes in another given
    # directory (second argument). By different we mean that one or more 
    # of the given attribute keys (third argument) have different values.
    # The routine returns a list of files with the differences in list 
    # context, the number of differences in scalar context.

    my ( $duri1,     # Directory URI, one
         $duri2,     # Directory URI, the other
         $keys,      # List of keys, e.g. [ "name", "size" ] - OPTIONAL
         $user,      # User login name - OPTIONAL
         $pass,      # User password - OPTIONAL
         ) = @_;
    
    # Returns a list or an integer. 

    $keys = [ "name" ] if not $keys;

    my ( @files1, @files2, @diff_files );

    @files1 = &Common::Storage::list_files( $duri1, $user, $pass );
    @files2 = &Common::Storage::list_files( $duri2, $user, $pass );

    @diff_files = &Common::Storage::diff_lists( \@files1, \@files2, $keys );

    return wantarray ? @diff_files : scalar @diff_files;
}

sub diff_lists
{
    # Niels Larsen, April 2003.

    # Compares two lists of files and returns those in list 1 that are 
    # missing or different from the similarly named ones in list 2. By 
    # different we mean that one or more of the given attributes (third 
    # argument) have different values. The attributes may be inexact, by
    # saying "size:6000" which means the files are considered similar 
    # if their size difference is 6000 bytes or less. If just "size" is
    # given they must match exactly. The routine returns a list of file 
    # hashes with the differences if in list context and the number of 
    # differences if in scalar context.

    my ( $files1,     # Files list
         $files2,     # Files list
         $keys,       # List of keys, e.g. [ "name", "size" ] - OPTIONAL
         ) = @_;
    
    # Returns a list or an integer. 
    
    my ( %files2, @keys, $file1, $file2, $name1, $key, $prefix, $delta,
         @diff_files, $different );
    
    $keys ||= [ "name" ];

    foreach $key ( @{ $keys } )
    {
        if ( $key =~ /^([A-Za-z]+):(-?\d+)$/ ) {
            push @keys, [ $1, $2 ];
        } elsif ( $key =~ /^([A-Za-z]+)$/ ) {
            push @keys, [ $1, 0 ];
        } else {
            &error( qq (Wrong looking key -> "$key") );
        }
    }

    %files2 = map { $_->{"name"} => $_ } @{ $files2 };

    foreach $file1 ( @{ $files1 } )
    {
        $name1 = $file1->{"name"};

        if ( exists $files2{ $name1 } )
        {
            $file2 = $files2{ $name1 };

            $different = 0;

            foreach $key ( @keys )
            {
                ( $prefix, $delta ) = @{ $key };

                if ( $prefix eq "mtime" ) {
                    $different = 1 if $file1->{"mtime"} > $file2->{"mtime"} + $delta;
                } elsif ( $prefix eq "size" ) {
                    $different = 1 if abs ( $file1->{"size"} - $file2->{"size"} ) > $delta;
                } else {
                    $different = 1 if $file1->{ $prefix } ne $file2->{ $prefix };
                }
            }

            if ( $different ) {
                push @diff_files, dclone $file1;
            }
        }
        else {
            push @diff_files, dclone $file1;
        }
    }
    
    return wantarray ? @diff_files : \@diff_files;
}

sub fetch_files_curl
{
    # Niels Larsen, May 2010.

    # Copies files from a remote location to a local destination, using curl.
    # Certain wildcards are allowed, see http://curl.haxx.se/docs/manpage.html.
    # A list of expanded [ from, to ] locations is returned.

    my ( $loc1,    # Remote path
         $loc2,    # Local path
         $args,    # Arguments - OPTIONAL
         $msgs,    # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $def_conf, $conf, $log_file, @log, $line, $cmd, $stdout, $stderr, 
         @copied, @msgs, @errors, $err_num, $err_msg );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $def_conf = {
        "user" => undef,
        "password" => undef,
        "timeout" => 15,
        "fail" => 1,
        "listonly" => 0,
        "tries" => 10,
    };
        
    $conf = &Registry::Args::create( $args, $def_conf );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $cmd = "curl '$loc1' -o '$loc2' ";
    
    $cmd .= " --user ". $conf->user if defined $conf->user;
    $cmd .= " --passw ". $conf->password if defined $conf->password;
    $cmd .= " --connect-timeout ". $conf->timeout if defined $conf->timeout;
    $cmd .= " --fail" if $conf->fail;
    $cmd .= " --list-only" if $conf->listonly;
    $cmd .= " --retry ". $conf->tries if defined $conf->tries;
    $cmd .= " --silent";
    $cmd .= " --show-error";
    
    $log_file = Registry::Paths->new_temp_path( "curl_log" );
    $cmd .= " --stderr $log_file";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stdout = "";
    $stderr = "";

    &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr, 0 );

    if ( $stderr ) {
        &error( $stderr );
    }

    @log = split /\r|\n/, ${ &Common::File::read_file( $log_file ) };

    &Common::File::delete_file( $log_file );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CURL ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # When wildcards are used, the format is of a certain type, and "not found"
    # errors should be ignored, because with multiple wildcards curl tries all 
    # combinations including wrong ones. So this assumes wildcards,

    foreach $line ( @log )
    {
        if ( $line =~ /^\[\d+\/\d+]: (\S+) --> (\S+)/ )
        {
            push @copied, [ $1, $2 ];
        }
        elsif ( $line =~ /^curl: \((\d+)\) (.+)/ )
        {
            $err_num = $1;
            $err_msg = $2;

            pop @copied;

            if ( $err_num != 22 and $err_msg !~ /550$/ ) {
                push @errors, "($err_num): $err_msg";
            }
        }
    }

    # If no [ from, to ] paths, that means a single from/to location was given 
    # and then "not found" error matters,

    if ( not @copied )
    {
        @errors = grep { $_ =~ /^curl: \(\d+\)/ } @log;

        if ( @errors ) {
            @errors = map { $_ =~ /^curl: \((\d+)\) (.+)/; "($1): $2" } @errors;
        } else {
            push @copied, [ $loc1, $loc2 ];
        }
    }
    
    if ( @errors or $stderr )
    {
        if ( @errors ) {
            push @msgs, map { ["ERROR", $_ ] } @errors;
        }

        if ( $stderr ) {
            push @msgs, map { ["ERROR", $_ ] } split /\n|\r/, $stderr;
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @copied : \@copied;
}

sub fetch_files_wget
{
    # Niels Larsen, May 2010.

    # Copies files from a remote location to a local destination, using wget.
    # The advantage of wget over curl is recursive ability, so use this routine
    # when a whole site should be fetched. Limited wildcards are allowed: 
    # ‘*’, ‘?’, ‘[’ or ‘]’, see 
    # http://www.gnu.org/software/wget/manual/html_node/index.html
    # A list of expanded [ from, to ] locations is returned.

    my ( $loc1,    # Remote path
         $loc2,    # Local path
         $args,    # Arguments - OPTIONAL
         $msgs,    # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $def_conf, @locs, $uri1, $uri2, $fh, $dir, $conf, $tmp_log, @lines,
         $line, $tmp_path, $cmd, $count, @count, $stdout, $stderr, @copied,
         @msgs, $dir_path, @errors );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $def_conf = {
        "recursive" => 0,
        "depth" => 9999,
        "clobber" => 1,
        "user" => undef,
        "password" => undef,
        "timeout" => 15,
        "tries" => 1,
    };
    
    $conf = &Registry::Args::create( $args, $def_conf );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $uri1 = URI->new( $loc1 );
    $uri2 = URI->new( $loc2 );
    
    $cmd = "wget $loc1 --no-host-directories";
    
    $cmd .= " --directory-prefix $loc2";
    $cmd .= " --user ". $conf->user if defined $conf->user;
    $cmd .= " --password ". $conf->password if defined $conf->password;
    $cmd .= " --timeout ". $conf->timeout if defined $conf->timeout;
    $cmd .= " --tries ". $conf->tries if defined $conf->tries;
    $cmd .= " --timestamping";
    $cmd .= " --quiet";
    
    if ( $conf->recursive )
    {
        $cmd .= " --recursive";
        $cmd .= " --level ". $conf->depth;
    }
    
    @count = $uri1->path =~ m|/|g;
    
    if ( @count ) {
        $cmd .= " --cut-dirs ". ( scalar @count - 1 );
    }
    
    $tmp_log = Registry::Paths->new_temp_path( "wget_log" );
    $cmd .= " --no-verbose --output-file $tmp_log";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stdout = "";
    $stderr = "";

    &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr, 0 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERRORS AND LOG <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Handle errors and log. Not all errors go to stderr, some wget prints
    # to the log. 
    
    @lines = split "\n", ${ &Common::File::read_file( $tmp_log ) };
    @lines = grep { $_ and $_ !~ /^(FINISHED|Downloaded:) / } @lines;

    foreach $line ( @lines )
    {
        if ( $line =~ /URL: (\S+) \[\d+\] -> "(\S+)"/ ) {
            push @copied, [ $1, $2 ];
        } else {
            push @errors, $line;
        }
    }

    if ( @errors or $stderr )
    {
        push @msgs, @errors if @errors;
        push @msgs, $stderr if $stderr;
        
        if ( defined $msgs ) {
            push @{ $msgs }, @msgs;
        } else {
            &error( \@msgs );
        }
    }
    
    &Common::File::delete_file( $tmp_log );

    return wantarray ? @copied : \@copied;
}

sub ghost_file
{
    # Niels Larsen, May 2003.

    # Deletes a file but adds its properties to a ghost file
    # list in the same directory as the file resides in. 

    my ( $furi,      # File location (URI or absolute path)
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $ghost_file_list );

    $user ||= "anonymous";
    $pass ||= "anonymous";

    $ghost_file_list = ".ghost_file_list";

    if ( &Common::Names::is_local_uri( $furi ) )
    {
        &Common::File::ghost_file( $furi, $ghost_file_list );
    }
    elsif ( &Common::Names::is_ftp_uri( $furi ) )
    {
        &Common::FTP::ghost_file( $furi, $ghost_file_list, $user, $pass );
    }
    else
    {
        &error( qq (
The file

"$furi" 

does not look like an absolute file name or an ftp uri. 
Please expand the path or make sure the format is right.), "FORMAT ERROR" );
        exit;
    }

    return;
}

sub index_table
{
    # Niels Larsen, September 2012. 

    # Creats a DBM key-value storage from a given table. Key-column and value-column
    # can be chosen and Kyoto Cabinet is being used as storage (see Common::DBM). A
    # number of parameters keys can be given,
    #
    # keycol    Key column (0)
    # valcol    Value column (1)
    # suffix    DBM file suffix (.dbm)
    # bufsiz    Memory buffer (10_000)
    # fldsep    Field separator (\t)
    # 
    # The DBM file path is the input path with the given suffix appended.

    my ( $file,    # Input file 
         $args,    # Arguments hash
        ) = @_;

    my ( $ndx_size, $mem_map, $page_cache, $buckets, $ifh, $ofh, %buf, $count,
         $line, $key, $val, $keycol, $valcol, $suffix, $bufsiz, $fldsep );

    $keycol = $args->{"keycol"} // 0;
    $valcol = $args->{"valcol"} // 1;
    $suffix = $args->{"suffix"} // ".dbm";
    $bufsiz = $args->{"bufsiz"} // 10_000;
    $fldsep = $args->{"fldsep"} // "\t";

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

    $ifh = &Common::File::get_read_handle( $file );

    $ofh = &Common::DBM::write_open( "$file$suffix", "bnum" => $buckets, 
                                     "msiz" => $mem_map, "pccap" => $page_cache  );

    %buf = ();
    $count = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        next if $line =~ /^#/;

        chomp $line;

        ( $key, $val ) = ( split $fldsep, $line )[ $keycol, $valcol ];

        $buf{ $key } = $val;

        $count += 1;

        if ( $count >= $bufsiz )
        {
            &Common::DBM::put_bulk( $ofh, \%buf );

            %buf = ();
            $count = 0;
        }
    }
    
    if ( %buf ) {
        &Common::DBM::put_bulk( $ofh, \%buf );
    }

    &Common::DBM::close( $ofh );

    &Common::File::close_handle( $ofh );
    &Common::File::close_handle( $ifh );

    return "$file$suffix";
}

sub list_all
{
    # Niels Larsen, July 2003.

    # Lists all files and directories in a given directory,
    # remote or local.

    my ( $duri,      # Directory location (URI or absolute path)
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;

    # Returns a list.

    $user ||= "anonymous";
    $pass ||= "anonymous";

    my ( $files, $html );

    if ( &Common::Names::is_local_uri( $duri ) )
    {
        $files = &Common::File::list_files( $duri );
    }
    elsif ( &Common::Names::is_ftp_uri( $duri ) )
    {
        $files = &Common::FTP::list_all( $duri, $user, $pass, $errors );
    }
    elsif ( &Common::Names::is_http_uri( $duri ) )
    {
        $html = &Common::HTTP::get_html_page( $duri );

        if ( $html =~ />Index of /i )
        {
            $files = &Common::HTTP::parse_apache_listing( $duri );
        }
        else {
            &error( qq (HTML page, but not an Apache directory listing) );
        }
    }
    else
    {
        &error( qq (
The path 

"$duri" 

does not look like an absolute directory path or an ftp uri. 
Please expand the path or make sure the format is right.), "FORMAT ERROR" );
        exit;
    }

    if ( defined $files ) {
        return wantarray ? @{ $files } : $files;
    }

    return;
}

sub list_dirs
{
    # Niels Larsen, July 2003.

    # Lists all directories in a given directory, remote or local.

    my ( $duri,      # Directory location (URI or absolute path)
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;

    # Returns a list.

    $user ||= "anonymous";
    $pass ||= "anonymous";

    my ( @dirs, $dirs );

    $dirs = &Common::Storage::list_all( $duri, $user, $pass, $errors );

    if ( defined $dirs )
    {        
        @{ $dirs } = grep { $_->{"type"} eq "d" and $_->{"name"} !~ /^\./ } @{ $dirs };

        return wantarray ? @{ $dirs } : $dirs;
    }
    else {
        return;
    }
}

sub list_files
{
    # Niels Larsen, July 2003.

    # Lists all files in a given directory, remote or local.

    my ( $furi,      # Directory location (URI or absolute path)
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;

    # Returns a list.

    $user ||= "anonymous";
    $pass ||= "anonymous";

    my ( $files );
    
    $files = &Common::Storage::list_all( $furi, $user, $pass, $errors );

    if ( defined $files )
    {
        @{ $files } = grep { $_->{"type"} eq "f" and $_->{"name"} !~ /^\./ } @{ $files };

        wantarray ? return @{ $files } : $files;
    }
    else {
        return;
    }
}

sub list_ghosts
{
    # Niels Larsen, July 2003.

    # Lists all "ghost" files in a given directory, remote or local.
    # A ghost file does not exist but its name and properties are 
    # given in the file ".ghost_file_list" in the given directory.

    my ( $duri,      # Directory location (URI or absolute path)
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;

    # Returns a list.

    $user ||= "anonymous";
    $pass ||= "anonymous";

    my ( $files );

    if ( &Common::Names::is_local_uri( $duri ) )
    {
        $files = &Common::File::list_ghosts( $duri );
    }
    elsif ( &Common::Names::is_ftp_uri( $duri ) )
    {
        &Common::sys_error( qq (Procedure is not implemented) );
    }
    else
    {
        &error( qq (
The path 

"$duri" 

does not look like an absolute directory path or an ftp uri. 
Please expand the path or make sure the format is right.), "FORMAT ERROR" );
        exit;
    }

    if ( defined $files ) {
        return wantarray ? %{ $files } : $files;
    } else {
        return;
    }
}

sub list_links
{
    # Niels Larsen, July 2003.

    # Lists all link files in a given directory, remote or local.

    my ( $luri,      # Directory location (URI or absolute path)
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;

    # Returns a list.

    $user ||= "anonymous";
    $pass ||= "anonymous";

    my ( $links );
    
    $links = &Common::Storage::list_all( $luri, $user, $pass, $errors );
    
    if ( defined $links )
    {
        @{ $links } = grep { $_->{"type"} eq "l" and $_->{"name"} !~ /^\./ } @{ $links };
        
        wantarray ? return @{ $links } : $links;
    }
    else {
        return;
    }
}

sub nodup_list
{
    # Niels Larsen, April 2003.
    
    # Removes redundant elements in a given list of file info hashes. 
    # The second argument is a list of keys whose value must be the 
    # same for two elements to be considered the same. 

    my ( $files,     # Files list
         $keys,      # List of keys, e.g. [ "name", "size" ] - OPTIONAL
         ) = @_;
    
    # Returns a list or an integer. 
    
    $keys = [ "name" ] if not $keys;
    
    my ( $keystr, @files, $file, %files );

    foreach $file ( @{ $files } )
    {
        $keystr = join ".", map { $file->{ $_ } } @{ $keys };

        if ( not exists $files{ $keystr } )
        {
            push @files, $file;
            $files{ $keystr } = &Storable::dclone( $file );
        }
    }

    return wantarray ? @files : \@files;
}

sub predict_space
{
    # Niels Larsen, April 2003.

    # Checks if there would be enough disk space left after having
    # copied a given list of files into a given directory. Takes into
    # account existing files with same names. Returns the number of 
    # free bytes that should be left on the partition after the copy.

    my ( $files,      # File list 
         $dir,        # Directory path
         ) = @_;

    # Returns a number.

    my ( $gone_files, $got_files, $free_now, $free_after );

    $got_files = &Common::Storage::list_files( $dir );
    $gone_files = &Common::Storage::both_lists( $files, $got_files );

    $free_now = &Common::OS::disk_space_free( $dir );

    $free_after = $free_now
                - &Common::Storage::add_sizes( $files )
                + &Common::Storage::add_sizes( $gone_files );

    return $free_after;
}

sub read_file
{
    my ( $furi,     # File URI or path, source
         $user,     # Source host login user name
         $pass,     # Source host login password
         ) = @_;
    
    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    my ( $str_ref );
    
    if ( &Common::Names::is_local_uri( $furi ) )
    {
        $str_ref = &Common::File::read_file( $furi );
    }
    elsif ( &Common::Names::is_ftp_uri( $furi ) )
    {
        $str_ref = &Common::FTP::read_file( $furi, $user, $pass );
    }

    return $str_ref;
}

sub write_file
{
    my ( $furi,
         $sref,
         $user,
         $pass,
         ) = @_;
    
    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    if ( &Common::Names::is_local_uri( $furi ) )
    {
        &Common::File::write_file( $furi, $sref );
    }
    elsif ( &Common::Names::is_ftp_uri( $furi ) )
    {
        &Common::FTP::write_file( $furi, $sref, $user, $pass );
    }
    
    return;
}   

sub write_ghosts
{
    # Niels Larsen, July 2003.

    # Appends a file property hash to the file ".ghost_file_list" in the
    # given directory. A ghost file does not exist, only its name and 
    # properties exist. 
    
    my ( $duri,      # Directory location (URI or absolute path)
         $files,     # File hashes to be written
         $user,      # User name - OPTIONAL
         $pass,      # Password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;

    # Returns nothing.

    $user ||= "anonymous";
    $pass ||= "anonymous";

    my ( %names, $ghost_file_list, $file_count, $name_count );

    %names = map { $_->{"name"}, 1 } @{ $files };

    $name_count = scalar keys %names;
    $file_count = scalar @{ $files };
    
    if ( $name_count != $file_count )
    {
        &error( qq (
$name_count ghosts file names but $file_count files. 
This means there are two files with same names.),
                               "GHOSTS FILE ERROR" );
    }

    $ghost_file_list = ".ghost_file_list";

    if ( &Common::Names::is_local_uri( $duri ) )
    {
        &Common::File::dump_file( "$duri/$ghost_file_list", $files );
    }
    elsif ( &Common::Names::is_ftp_uri( $duri ) )
    {
#        &Common::FTP::write_ghosts( "$duri/$ghost_file_list", $files, $user, $pass );
        &Common::sys_error( qq (Procedure is not implemented) );
    }
    else
    {
        &error( qq (
The path 

"$duri" 

does not look like an absolute directory path or an ftp uri. 
Please expand the path or make sure the format is right.), "FORMAT ERROR" );
        exit;
    }

    return;
}

1;

__END__
