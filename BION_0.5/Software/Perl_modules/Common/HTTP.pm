package Common::HTTP;     #  -*- perl -*-

# Primitives for HTTP network operations. 

use strict;
use warnings FATAL => qw ( all );

use LWP::UserAgent;
use HTTP::Request::Common;
use File::Listing;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &download_file
                 &get_html_page
                 &get_html_links
                 &parse_apache_listing
                 &submit_form
                 );

use Common::Config;
use Common::Messages;

use Common::Names;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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

    my ( $ldir, $lname, $error, $error_type );

    $error_type = "HTTP DOWNLOAD ERROR";

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
 
    if ( not &Common::Names::is_http_uri( $ruri ) )
    {
        &Common::Messages::error( qq (
The remote location 

 "$ruri"

does not look like an HTTP file URI. Please make sure the format 
is right. See for example the URI:: module on search.cpan.org.
), $error_type );
    }

    &echo( qq (   Fetching "$ruri" ... ) );
    
    $user ||= "anonymous";
    $pass ||= "anonymous";
    
    my ( $ua, $req, $res, @stats, $stat, $mode );

    $req = HTTP::Request->new( GET => $ruri );
    
    if ( $user ne "anonymous" ) {
        $req->authorization_basic( $user, $pass );
    }

    $ua = LWP::UserAgent->new();

    $res = $ua->request( $req, $luri );

    if ( $res->is_success ) {
        &echo_green( "done\n" );
    } else {
        &Common::Messages::error( $res->message, $error_type );
    }

    return 1;
}

sub get_html_links
{
    # Niels Larsen, December 2005.

    # Returns the links from the page at a given url. It is very
    # primitive and unfinished, and may not even work in many 
    # cases. 

    my ( $r_dir,
         ) = @_;

    # Returns a list. 

    my ( $html, $line, @list );

    $html = &Common::HTTP::get_html_page( $r_dir );

    if ( not $html ) {
        &Common::Messages::error( qq (Could not get from -> "$r_dir") );
    }

    while ( $html =~ /<a href=\"([^\"]+)\"/igs )
    {
        push @list, $1;
    }

    return wantarray ? @list : \@list;
}

sub get_html_page
{
    # Niels Larsen, July 2003.

    my ( $url,
         $errors,
         ) = @_;

    my ( $agent, $request, $response, $html, @errors );

    $agent = new LWP::UserAgent;
    $agent->timeout( 900 );

    $request  = HTTP::Request->new ( GET => $url );

    $response = $agent->request( $request );

    if ( $response->is_success ) 
    {
        $html = $response->content;
        
        if ( $html ) {
            return $html;
        } else {
            push @errors, qq (Success, but no HTML returned\n);
        }
    }
    else {
        push @errors, qq (URL: $url);
        push @errors, "Code ". $response->code .": ". $response->message;
    }

    if ( defined $errors ) {
        push @{ $errors }, @errors;
    } else {
        &Common::Messages::error( \@errors );
    }

    return;
}

sub parse_apache_listing
{
    # Niels Larsen, December 2005.

    # Parses an Apache server directory listing. Very primitive, 
    # unfinished. Returns a list of [ file, epoch, size-string ].

    my ( $r_dir,
         ) = @_;

    # Returns a list. 

    my ( $html, $regexp, $line, @files, $name, $date, $time, $size, 
         $secs, $type );

    $html = &Common::HTTP::get_html_page( $r_dir );

    if ( $html =~ /<table/ ) {
        $regexp = '<td><a href=\"([^\"]+)\">\S+</a></td><td align="right">(\S+)\s+(\S+)\s*</td><td align="right">\s*([^<]+)';
    } else {
        $regexp = '<a href=\"([^\"]+)\">\S+<\/a>\s*(\S+)\s*(\S+)\s*(\S+)\s*$';
    }

    foreach $line ( split "\n", $html )
    {
        if ( $line =~ /$regexp/i )
        {
            $name = $1;
            $date = $2;
            $time = $3;
            $size = $4;

            $secs = &Common::Util::time_string_to_epoch( uc "$date-$time:00" );

            $size =~ s/B//i;
            $size =~ s/K$/000/i;
            $size =~ s/M$/000000/i;
            $size =~ s/G$/000000000/i;

            if ( $size =~ /\./ ) 
            {
                $size =~ s/\.//;
                $size /= 10;
            }

            if ( $name =~ m|/$| )
            {
                $type = "d";
                $name =~ s|/$||;
            }
            else {
                $type = "f";
            }

            push @files,
            {
                "name" => $name,
                "path" => "$r_dir/$name",
                "type" => $type,
                "uid" => undef,
                "gid" => undef,
                "size" => $size,
                "mtime" => $secs,
                "perm" => 0644,
            };
        }
    }

    return wantarray ? @files : \@files;
}

1;

__END__

# sub submit_form
# {
#     # Niels Larsen, January 2009.

#     my ( $args,
#          $msgs,
#          ) = @_;

#     my ( $agent, $request, $response, $html );

#     $args = &Registry::Args::check(
#         $args,
#         { 
#             "S:1" => [ qw ( url timeout method ) ],
#             "AR:1" => [ qw ( fields ) ],
#         });

#     $agent = new LWP::UserAgent;
#     $agent->timeout( $args->timeout // 900 );

#     $request  = HTTP::Request->new ( $method => $args->url );

#     $response = $agent->request( $request );

#     if ( $response->is_success ) 
#     {
#         $html = $response->content;
        
#         if ( $html ) {
#             return $html;
#         } else {
#             push @{ $errors }, qq (ERROR: success, but no HTML returned\n);
#         }
#     }
#     else {
#         push @{ $errors }, qq (ERROR: LWP error -> $response->code: $response->message\n);
#     }

#     return;
# }

# sub list_all
# {
#     # Niels Larsen, December 2003.
    
#     # Lists all files and directories in a given directory. 

#     my ( $ruri,      # HTTP directory URI
#          $user,      # Login user name - OPTIONAL
#          $pass,      # Login password - OPTIONAL
#          $errors,    # Errors list - OPTIONAL
#          ) = @_;
    
#     # Returns list. 

#     my ( $error_type, $ua, $req, $res, @stats, $stat, $mode, $name,
#          $code, $message );

#     $error_type = "HTTP LISTING ERROR";
#     $errors = [] if not $errors;

#     if ( not &Common::Names::is_http_uri( $ruri ) )
#     {
#         &Common::Messages::error( qq (
# The remote directory path 

#  "$ruri"

# does not look like an HTTP directory URI. Please make sure the format 
# is right. See for example the URI:: module on search.cpan.org.
# ), $error_type);
#     }

#     $ruri =~ s/\/$//;          
#     $user ||= "anonymous";
#     $pass ||= "anonymous";
    
#     $req = HTTP::Request->new( GET => $ruri );

#     if ( $user ne "anonymous" ) {
#         $req->authorization_basic( $user, $pass );
#     }

#     $ua = LWP::UserAgent->new;
#     $ua->timeout( 30 );

#     $res = $ua->request( $req );

#     if ( $res->is_success )
#     {
# #        &dump( $res->decoded_content );

#         foreach $stat ( &File::Listing::parse_dir( $res->content ) )
#         {
#             $name = $stat->[0];

#             push @stats, 
#             {
#                 "path" => "$ruri/$name",
#                 "name" => $name,
#                 "dir" => $ruri,
#                 "type" => $stat->[1],
#                 "size" => defined $stat->[2] ? $stat->[2] * 1 : undef,
#                 "mtime" => $stat->[3] * 1,
#                 "perm" => sprintf "%04o", $stat->[4] & 07777,
#             };
#         }

#         return wantarray ? @stats : \@stats;
#     }
#     elsif ( $res->is_error )
#     {
#         $code = $res->code;
#         $message = $res->message;

#         push @{ $errors }, [ $code, $message ];
        
#         print $res->status_line; print "\n";
#     }

#     return;
# }

# 1;

# __END__
