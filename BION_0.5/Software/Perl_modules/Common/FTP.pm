package Common::FTP;     #  -*- perl -*-

# FTP routines. Most of these are old and should be updated .. 

use strict;
use warnings FATAL => qw ( all );

use Net::FTP;
use LWP;
use File::Listing;
use File::Basename;
use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &delete_file
                 &download_file
                 &list_all
                 &list_path
                 &read_file
                 &upload_file
                 &write_file
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Names;

use Registry::Paths;

$ENV{"FTP_PASSIVE"} = 1;     # Prevents hangs at certain firewalls

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub delete_file
{
    # Niels Larsen, March 2003.
    
    # Deletes a remote FTP file.

    my ( $ruri,    # Remote file URI
         $user,    # Remote login name - OPTIONAL
         $pass,    # Remote password - OPTIONAL
         ) = @_;

    require Common::Logs;

    my ( $uri, $host, $path, $ftp, $dest_dir, $dest_file, $message, 
         $code, $error_type, @segments );

    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    $error_type = "FTP DELETE ERROR";
    
    $uri = URI->new( $ruri );
    
    $host = $uri->host_port();
    @segments = $uri->path_segments();
    
    $dest_file = pop @segments;

    if ( not $dest_file )
    {
        &Common::Messages::error( qq (
The remote file specification

 "$ruri"

does not contain a file name. The system does not at this time
support remote directory arguments.), $error_type );
    }
        
    $dest_dir = join "/", @segments[ 1 ... $#segments ];

    $ftp = Net::FTP->new( $host, Debug => 0 );
    
    if ( $@ )
    {
        $message = "Could not create FTP session";
        &Common::Messages::error( qq (
$message
Server says: $@
), $error_type );
    }
    
    $ftp->login( $user, $pass );
    
    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Messages::error( qq (
Could not log in with user "$user" and password "$pass".
Server says (code $code): $message), $error_type );
    }
    
    $ftp->authorize();

    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Logs::warning( { "MESSAGE" => qq (
Could not authorize through firewall.
Server says (code $code): $message) }, $error_type );
    }

    $ftp->cwd( $dest_dir );

    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Messages::error( qq (
Could not change directory to "$dest_dir".
Server says (code $code): $message), $error_type );
    }

    if ( not $ftp->delete( $dest_file ) )
    {
        $message = qq (
The system was unable to delete the file 

 "$ruri"

This could be due to network trouble, but likely the reason
is permission problems. 
);
        &Common::Messages::error( $message, $error_type );
    }
    
    if ( not $ftp->quit ) {
        &Common::Messages::error( qq (Could not log out from "$host"), $error_type );
    }

    return;
}

sub download_file
{
    # Niels Larsen, April 2003.
    
    # Downloads a remote ftp file to a local file. The local file may not 
    # exist and its parent directory must. Each step of the download is 
    # checked and logged. This is of course necessary due to the 
    # unpredictability of the network and sites that may change without 
    # us knowing it. TODO: firewall handling. 
    
    my ( $ruri,      # Remote FTP file URI 
         $luri,      # Local file path (URI is ok)
         $user,      # [ Remote login user name ]
         $pass,      # [ Remote login password ]
         ) = @_;
    
    # Returns nothing.

    my ( $ldir, $lname, $error, $error_type, $failures,
         $ua, $req, $res, @stats, $stat, $mode, $success );

    $error_type = "FTP DOWNLOAD ERROR";

    # Check the local file. It must be a non-existing file in a writable
    # directory, everything else is fatal error.

    $error = "";
    
    if ( &Common::File::is_regular( $luri ) )
    {
        $error = qq (the latter file exists);
    }
    else
    {
        if ( -d $luri ) {
            $error = qq (the latter file is a directory);
        } elsif ( -e $luri ) {
            $error = qq (the latter file is not a regular file);
        }

        if ( not -e $luri )
        {
            $ldir = &File::Basename::dirname( $luri );
            $lname = &File::Basename::basename( $luri );

            if ( not -d $ldir ) {
                $error = qq (the directory part of the latter does not exist);
            } elsif ( not -w $ldir ) {
                $error = qq (the directory part of the latter is not writable);
            }
        }
    }

    if ( $error )
    {
        &Common::Messages::error( qq (
The system will not download the remote file

 "$ruri"  to
 "$luri"

because $error. 

We insist on full file paths and try to catch all errors at 
this level. This may seem inflexible, but we want to catch 
any error as early and as close to their cause as possible. 
), $error_type );
    }

    # Check that the remote URI is well formed. No other checking is 
    # done, we just see if the download went okay - and if not we show
    # the message from the remote server. 
 
    if ( not &Common::Names::is_ftp_uri( $ruri ) )
    {
        &Common::Messages::error( qq (
The remote location 

 "$ruri"

does not look like an FTP file URI. Please make sure the format 
is right. See for example the URI:: module on search.cpan.org.
), $error_type );
    }
    
    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    $failures = 0;
    $success = 0;

    while ( not $success and $failures < 3 )
    {
        if ( $failures > 0 ) {
            &echo( "   Trying again ... " );
        }

        $req = HTTP::Request->new( GET => $ruri );
    
        if ( $user ne "anonymous" ) {
            $req->authorization_basic( $user, $pass );
        }
        
        $ua = LWP::UserAgent->new();
        
        $res = $ua->request( $req, $luri );
        
        if ( $res->is_success )
        {
            $success += 1;
        }
        else 
        {
            &warning( "\n". $res->message .".\n Will wait one minute and try again.\n" );
            $failures += 1;
            sleep 60;
        }
    }

    if ( $failures >= 3 )
    {
        &Common::Messages::error( qq (Giving up, because of 3 consecutive failures)
                                 .qq ( separated by 1 minute.) );
    }

    return;
}

sub list_all
{
    # Niels Larsen, March 2003.
    
    # Lists all files and directories in a given directory. 

    my ( $ruri,      # FTP directory URI
         $user,      # Login user name - OPTIONAL
         $pass,      # Login password - OPTIONAL
         $errors,    # Errors list - OPTIONAL
         ) = @_;
    
    # Returns list. 

    my ( $error_type, $ua, $req, $res, @stats, $stat, $mode, $name,
         $code, $message, $count_str );

    $error_type = "FTP LISTING ERROR";

    if ( not &Common::Names::is_ftp_uri( $ruri ) )
    {
        &Common::Messages::error( qq (
The remote directory path 

 "$ruri"

does not look like an FTP directory URI. Please make sure the format 
is right. See for example the URI:: module on search.cpan.org.
), $error_type);
    }

    &echo( qq (   Listing remote files ... ) );

    $ruri =~ s/\/$//;          
    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    $req = HTTP::Request->new( GET => $ruri );
    
    if ( $user ne "anonymous" ) {
        $req->authorization_basic( $user, $pass );
    }

    $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.5) Gecko/20060719 Firefox/1.5.0.5' );
    $ua->timeout( 300 );

    $res = $ua->request( $req );

    if ( $res->is_success )
    {
        foreach $stat ( &File::Listing::parse_dir( $res->content ) )
        {
            $name = $stat->[0];

            push @stats, 
            {
                "path" => "$ruri/$name",
                "name" => $name,
                "dir" => $ruri,
                "type" => $stat->[1],
                "size" => defined $stat->[2] ? $stat->[2] * 1 : undef,
                "mtime" => $stat->[3] * 1,
                "perm" => sprintf "%04o", $stat->[4] & 07777,
            };
        }

        $count_str = &Common::Util::commify_number( scalar @stats );
        &echo_green( "$count_str\n" );

        return wantarray ? @stats : \@stats;
    }
    elsif ( $res->is_error )
    {
        $code = $res->code;
        $message = $res->message;
        
        if ( defined $errors and ref $errors eq "ARRAY" ) {
            push @{ $errors }, [ $code, $message ];
        } else {
            &Common::Messages::error( $res->status_line );
        }
    }

    return;
}

sub list_path
{
    # Niels Larsen, July 2011.

    my ( $path,
         $user,
         $pass,
        ) = @_;

    my ( $uri, $ftp, $scheme, $host, @list );

    $user ||= "anonymous";
    $pass ||= "anonymous@";

    $uri = URI->new( $path )->canonical;

    if ( $scheme = $uri->scheme ne "ftp" ) {
        &error( qq (Not an FTP path -> "$scheme") );
    }

    if ( not $ftp = Net::FTP->new( $host = $uri->host_port, Debug => 0 ) ) {
        &error( qq (Cannot ftp-connect to -> "$host") );
    }

    if ( not $ftp->login( $user, $pass ) ) {
        &error( qq (Could not log into $host with user = $user and password = $pass) );
    }

    @list = $ftp->ls( "-l ". $uri->path );

    if ( not $ftp->quit ) {
        &error( qq (Could not log out from "$host") );
    }

    @list = map { $uri->path( $_ ); $uri->as_string } @list;
    
    return wantarray ? @list : \@list;
}

sub read_file
{
    # Niels Larsen, March 2003.
    
    my ( $file,      # FTP file URI
         $user,      # Login user name - OPTIONAL
         $pass,      # Login password - OPTIONAL
         ) = @_;
    
    # Returns string reference.

    my $error_type = "FTP DOWNLOAD ERROR";

    if ( not &Common::Names::is_ftp_uri( $file ) )
    {
        &Common::Messages::error( qq (
The path 

"$file"

does not look an FTP URI. Please make sure the format 
is right. See for example the URI:: module on search.cpan.org.
), $error_type );
    }

    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    my ( $ua, $req, $res, @stats, $stat, $mode );

    $req = HTTP::Request->new( GET => $file );

    if ( $user ne "anonymous" ) {
        $req->authorization_basic( $user, $pass );
    }

    $ua = LWP::UserAgent->new;
    $res = $ua->request( $req );

    if ($res->is_success)
    {
        return \$res->content;
    }
    else
    {
        &Common::Messages::error( $res->message, $error_type );
    }
}

sub upload_file
{
    # Niels Larsen, April 2003.
    
    # Uploads a local file to a remote file. The remote file may not exist 
    # and its parent directory must. Each step of the upload is checked and 
    # either errors and/or warnings are displayed and/or logged. This is of
    # course necessary due to the unpredictability of the network and sites
    # that may change without us knowing it. TODO: firewall handling. 
    
    my ( $luri,    # Local file path (URI is ok)
         $ruri,    # Remote file or directory path URI
         $user,    # Remote login name - OPTIONAL
         $pass,    # Remote password - OPTIONAL
         ) = @_;

    require Common::Logs;

    my ( $uri, $host, $path, $ftp, $dest_dir, $dest_file, $error, $error_type,
         $code, @segments, $title, $message );

    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    $error_type = "FTP UPLOAD ERROR";

    # First make sure the local file is a regular file, fatal error if not,

    if ( -d $luri ) {
        $error = qq (is a directory);
    } elsif ( not -e $luri ) {
        $error = qq (does not exist);
    } elsif ( not &Common::File::is_regular( $luri ) ) {
        $error = qq (is not a regular file);
    }

    if ( $error ) 
    {
        &Common::Messages::error( qq (
The system will not upload the file
                                     
 "$luri"  to
 "$ruri"
                                     
because the former $error.

We insist on full file paths and try to catch all errors at 
this level. This may seem inflexible, but we want to catch 
any error as early and as close to their cause as possible. 
), $error_type );
    }

    # Then look at the remote URI,

    if ( not &Common::Names::is_ftp_uri( $ruri ) )
    {
        &Common::Messages::error( qq (
The remote location 

 "$ruri"

does not look like an FTP file URI. Please make sure the format 
is right. See for example the URI:: module on search.cpan.org.
), $error_type );
    }
    
    $uri = URI->new( $ruri );

    $host = $uri->host_port();
    @segments = $uri->path_segments();

    $dest_file = pop @segments;

    if ( not $dest_file )
    {
        &Common::Messages::error( qq (
The remote file specification

 "$ruri"

does not contain a file name. The system does not at this time
support remote directory arguments.), $error_type );
    }
        
    $dest_dir = join "/", @segments[ 1 ... $#segments ];

    $ftp = Net::FTP->new( $host, Debug => 0 );
    
    if ( $@ )
    {
        $message = "Could not create FTP session";
        &Common::Messages::error( qq (
$message
Server says: $@
), $error_type );
    }
    
    $ftp->login( $user, $pass );
    
    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Messages::error( qq (
Could not log in with user "$user" and password "$pass".
Server says (code $code): $message), $error_type );
    }
    
    $ftp->authorize();

    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Logs::warning( { "MESSAGE" => qq (
Could not authorize through firewall.
Server says (code $code): $message) }, $error_type );
    }

    $ftp->cwd( $dest_dir );

    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Messages::error( qq (
Could not change directory to "$dest_dir".
Server says (code $code): $message), $error_type );
    }

    $ftp->binary();

    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Messages::error( qq (
Could not set binary transfer mode.
Server says (code $code): $message), $error_type );
    }

    $ftp->put( $luri, $dest_file );

    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Messages::error(qq (
The system was unable to upload the file 

 "$luri"  to 
 "$ruri"

Remote server says (code $code): $message
), $error_type );
    }

    $ftp->quit;

    if ( not $ftp->ok )
    {
        $message = $ftp->message;
        $code = $ftp->code;
        &Common::Messages::error(qq (
The system was unable to disconnect from the server.
Server says (code $code): $message
), $error_type );
    }

    return;
}

sub write_file
{
    # Niels Larsen, April 2003.

    # find better way than this crap. 

    my ( $file,      # Remote FTP URI 
         $sref,      # Input string, string-reference or list-reference
         $user,
         $pass,
         ) = @_;

    my ( $temp );

    $temp = Registry::Paths->new_temp_path();

    &Common::File::write_file( $temp, $sref );
    
    &Common::FTP::upload_file( $temp, $file, $user, $pass );

    &Common::File::delete_file( $temp );

}

1;

__END__
