package Common::Users;     #  -*- perl -*-

# Functions that somehow have to do with users. Everything from 
# validating passwords to writing saved selections under each 
# users directory. 

use strict;
use warnings FATAL => qw ( all );

use CGI;

use Data::Dumper;
use Storable qw ( dclone );
use File::Copy;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &bad_password
                 &bad_username
                 &browser_is_css_capable
                 &browser_is_menu_capable
                 &delete_old_tmp_sessions
                 &delete_session
                 &get_client_info
                 &get_client_newline
                 &get_client_os
                 &get_cgi_password
                 &get_cgi_username
                 &get_session
                 &login
                 &new_session
                 &savings_add
                 &savings_delete
                 &savings_read
                 &savings_save
                 );

use Common::Config;
use Common::Messages;

use Common::DB;
use Common::File;
use Common::Accounts;
use Common::Menus;
use Common::Widgets;
use Common::States;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub bad_password
{
    # Niels Larsen, March 2003

    # Returns an error string if a password does not pass
    # the most basic quality check. Otherwise nothing. 

    my ( $password,   # Password candidate
         ) = @_;

    # Returns a string or nothing.
    
    my ( $error );

    require Data::Password;
    
    $Data::Password::DICTIONARY = 4;
    $Data::Password::FOLLOWING = 4;
    $Data::Password::MINLEN = 6;
    $Data::Password::MAXLEN = 10;
    $Data::Password::GROUPS = 1;
    
    $error = &Data::Password::IsBadPassword( $password );
    
    if ( $error ) {
        return "Password " . lc $error;
    } else {
        return;
    }
}

sub bad_username
{
    # Niels Larsen, March 2003

    # Returns an error string if a user name does not consist of between 
    # six and ten alphabetic characters - plus underscore. Otherwise nothing. 

    my ( $username,   # User candidate
         ) = @_;

    # Returns a string or nothing.

    my ( $error, $chars );

    $username =~ s/^\s*//;
    $username =~ s/\s*$//;

    $chars = $username;

    if ( length $username < 5 ) 
    {
        $error = qq (User name should be at least five characters long \(and)
               . qq ( at most ten characters.\));
    }
    elsif ( length $username > 10 ) 
    {
        $error = qq (User name should be at most ten characters long \(and)
               . qq ( at least six characters.\));
    }
    elsif ( $username =~ /[^A-Za-z-]/ )
    {
        $chars =~ s/[A-Za-z-]//g;
        $error = qq (User name contains the characters <tt>'$chars'</tt> - it should)
               . qq ( consist of alphabetic characters and <tt>'-'</tt> (dash) only.);
    }
#    elsif ( $username =~ /^([a-z]|-)+$/ )
#    {
#        $error = qq (User name contains only lower case characters - it should)
#               . qq ( contain at least one upper case character.);
#    }
#    elsif ( $username =~ /^([A-Z]|-)+$/ )
#    {
#        $error = qq (User name contains only upper case characters - it should)
#               . qq ( contain at least one lower case character.);
#    }

    if ( $error ) {
        return $error;
    } else {
        return;
    }
}

sub browser_is_menu_capable
{
    # Niels Larsen, June 2003.

    # Checks if the browser can display the popup menus that come
    # with the system. NOTE: incomplete; have to test and add several
    # OS/browser combinations. 

    my ( $info,    # Info hash from &get_client_info routine
         ) = @_;

    # Returns 0 or 1.

    return 0;

    $info = &Common::Users::get_client_info() if not $info;

    my $capable = 0;

    if ( $info->{"os_name"} =~ /^Unix|Linux$/ )
    {
        if ( $info->{"name"} eq "Netscape" and $info->{"version"} >= 5.0 )
        {
            $capable = 1;
        }
    }
    elsif ( $info->{"os_name"} eq "Mac" )
    {
#        if ( $info->{"name"} eq "Netscape" and $info->{"version"} >= 5.0 )
#        {
#            $capable = 1;
#        }
    }
    elsif ( $info->{"os_name"} =~ /^Win/ )
    {
        if ( $info->{"name"} eq "Netscape" and $info->{"version"} >= 5.0 or
             $info->{"name"} eq "MSIE"     and $info->{"version"} >= 5.5 )
        {
            $capable = 1;
        }
    }

    return $capable;
}

sub browser_is_css_capable
{
    # Niels Larsen, June 2003.

    # Checks if the browser can display the style sheet features used
    # by the system. NOTE: incomplete; have to test and add several
    # OS/browser combinations. 

    my ( $info,     # Info hash from &get_client_info routine
         ) = @_;

    # Returns 0 or 1.

    return 1;

    $info = &Common::Users::get_client_info() if not $info;

    my $capable = 0;

    if ( $info->{"os_name"} =~ /^Unix|Linux$/ )
    {
        if ( $info->{"name"} eq "Netscape" and $info->{"version"} >= 5.0 )
        {
            $capable = 1;
        }
    }
    elsif ( $info->{"os_name"} eq "Mac" )
    {
        if ( $info->{"name"} eq "Netscape" and $info->{"version"} >= 5.0 or
             $info->{"name"} eq "MSIE"     and $info->{"version"} >= 5.1 )
        {
            $capable = 1;
        }
    }
    elsif ( $info->{"os_name"} =~ /^Win/ )
    {
        if ( $info->{"name"} eq "Netscape" and $info->{"version"} >= 5.0 or
             $info->{"name"} eq "MSIE"     and $info->{"version"} >= 5.0 )
        {
            $capable = 1;
        }
    }

    return $capable;
}

sub delete_old_tmp_sessions
{
    # Niels Larsen, October 2005.

    # Deletes the sessions in the Temporary directory where last access 
    # is older than a given number of hours (default 24). Returns the 
    # number of sessions deleted.

    my ( $hours,      # Max age in hours
         ) = @_;

    # Returns an integer.

    my ( $secs, $ses_dir, $dir, $count, $session, $maxsecs, $epoch );

    $hours = 24 if not defined $hours;
    $maxsecs = int $hours * 3600;

    $ses_dir = "$Common::Config::ses_dir/Temporary";
    $epoch = &Common::Util::time_string_to_epoch();

    $count = 0;

    foreach $dir ( &Common::File::list_directories( $ses_dir ) )
    {
        if ( $session = &Common::Users::get_session( "Temporary/". $dir->{"name"} ) )
        {
            $secs = $session->param("last_access");
            
            if ( defined $secs and ( $epoch - $secs ) > $maxsecs ) 
            {
                &Common::Users::delete_session( "Temporary/". $session->id );
                $count += 1;
            }
        }
    }

    &Common::File::delete_links_stale( "$Common::Config::dbs_dir" );

    return $count;
}

sub delete_session
{
    # Niels Larsen, October 2003.

    # Deletes all session information for a given session id 
    # except user registration information. 

    my ( $sid,           # Session id
         ) = @_;

    # Returns 1 for success, nothing for failure. 

    my ( $ses_dir, $link );

    if ( not $sid ) {
        &Common::Messages::error( qq (Session not defined) );
    }

    $link = $sid;
    $link =~ s/\//_/;

    if ( -l "$Common::Config::dbs_dir/$link" ) {
        &Common::File::delete_file( "$Common::Config::dbs_dir/$link" );
    }

    $ses_dir = "$Common::Config::ses_dir/$sid";

    if ( -e $ses_dir ) {
        &Common::File::delete_dir_tree( $ses_dir );
#    } else {
#        &warning( qq (Session directory does not exist -> "$ses_dir"), "DELETE SESSION" );
    }

    if ( not -e $ses_dir ) {
        return 1;
    } else {
        return;
    }
}

sub get_client_info
{
    # Niels Larsen, June 2003.

    # Fetches via the CGI object information from the browser client. 
    # NOTE: uses the CPAN module HTTP::BrowserDetect which is not up
    # to date - we must decide to use this, or not, or maintain it. 

    # Returns a hash.

    my ( $info, $browser );

    require HTTP::BrowserDetect;

    $browser = new HTTP::BrowserDetect;

    $info->{"name"} = $browser->browser_string || "";
    $info->{"version"} = $browser->version || "";
    $info->{"major_version"} = $browser->major || "";
    $info->{"minor_version"} = $browser->minor || "";
    $info->{"beta_version"} = $browser->beta || "";
    $info->{"os_name"} = $browser->os_string || "";
    $info->{"user_agent"} = $browser->user_agent || "";
    
    return wantarray ? %{ $info } : $info;
}

sub get_client_newline
{
    # Niels Larsen, January 2005.

    # Returns the newline that the browser client OS uses, "\n" for
    # unix, "\r" for Mac and "\r\n" for Windows.

    # Returns a string.

    my ( $os_type, $nl );

    $os_type = &Common::Users::get_client_os();
    
    if ( $os_type eq "windows" ) {
        $nl = "\r\n";
    } elsif ( $os_type eq "mac" ) {
        $nl = "\r";
    } else {
        $nl = "\n";
    }
    
    return $nl;
}

sub get_client_os
{
    # Niels Larsen, January 2005.

    # Returns the client operating system from the browser, either
    # "windows", "mac" or "unix".

    # Returns a string.

    my ( $info, $browser, $os );

    require HTTP::BrowserDetect;

    $browser = new HTTP::BrowserDetect;

    if ( $browser->windows ) {
        $os = "windows";
    } elsif ( $browser->mac ) {
        $os = "mac";
    } elsif ( $browser->unix ) {
        $os = "unix";
    }
    else 
    {
        &Common::Messages::error( qq (Unknown operating system -> "$os") );
    }
    
    return $os;
}

sub get_cgi_password
{
    # Niels Larsen, March 2003
    
    # Fetches cleartext pass from a submitted CGI form. 

    my ( $cgi,     # CGI.pm object - OPTIONAL
         ) = @_;

    # Returns string. 

    my $string;

    if ( $cgi ) {
        $string = $cgi->param('password');
    } else {
        $string = ( new CGI )->param('password');
    }

    $string ||= "";

    return $string;
}

sub get_cgi_username
{
    # Niels Larsen, March 2003
    
    # Fetches user name from a submitted CGI form. 

    my ( $cgi,     # CGI.pm object - OPTIONAL
         ) = @_;

    # Returns string. 

    my $string;

    if ( $cgi ) {
        $string = $cgi->param('username');
    } else {
        $string = ( new CGI )->param('username');
    }

    $string ||= "";

    return $string;
}

sub get_session
{
    # Niels Larsen, May 2003. 
    
    # Given a session ID, returns the corresponding session object. 
    # But only if a session exists with that ID.

    my ( $sid,
         ) = @_;

    # Returns session object or nothing. 

    my ( $error_type, $count, $session, @sessions, $sql, $ses_dir );

    $error_type = "GET SESSION ERROR";

    if ( not $sid ) {
        &Common::Messages::error( qq (No session ID is given), $error_type );
    }

    $ses_dir = "$Common::Config::ses_dir/$sid";

    if ( -r "$ses_dir/session" )
    {
        require CGI::Session;
        require CGI::Session::Driver::file;

        $CGI::Session::IP_MATCH = 0;
        $CGI::Session::Driver::file::FileName = 'session';

        $session = new CGI::Session( "driver:File", $sid, { Directory => $ses_dir } );

        if ( $session ) {
            return $session;
        } else {
            &Common::Messages::error( qq (Could not fetch session "$sid"), $error_type );
        }
    }
#    else {
#        &Common::Messages::error( qq (Session does not exist -> "$sid"), $error_type );
#    }

    return;
}        

sub login
{
    # Niels Larsen, December 2005.

    # Responds to various requests about how to enter the system. It handles
    # creating accounts, display of registration page, and all normal requests
    # go through here too. The routine gets a session and returns a session id.
    
    my ( $cgi,            # CGI.pm object
         $proj,           # Project object
         $sid,            # Session ID - OPTIONAL
         $username,       # User name - OPTIONAL
         $password,       # Password - OPTIONAL
         ) = @_;

    # Returns session object if called non-void context.
    
    my ( $session, @errors, $error, $xhtml, $request, $state, $acc_sid,
         $login_sid, $account, @messages, $epoch, $nav_menu );

    if ( not $cgi ) {
        $cgi = new CGI;
    }

    if ( not $sid ) {
        $sid = $cgi->param('session_id') || "";
    } 

    $Common::Config::session_id = $sid;

    $request = $cgi->param("sys_request") || "";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> NEW ACCOUNT <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # We get here after the button is pressed on the registration page.
    # There will be a session id submitted, but that is just ignored (the
    # login requests will remove old inactive sessions and we need it if
    # user decides not to log in but continue as anonymous.

    if ( $request =~ /^create_account$/i )
    {
        $cgi->delete("sys_request");
        
        $account->{"first_name"} = $cgi->param("first_name") || "";
        $account->{"last_name"} = $cgi->param("last_name") || "";
        $account->{"username"} = $cgi->param("username") || "";
        $account->{"password"} = $cgi->param("password") || "";
        $account->{"project"} = $proj->name;
        
        $state = &Common::States::default_states( $proj )->{"system"};
        $state->{"logged_in"} = 0;
        
        $acc_sid = &Common::Accounts::add_user( $account, \@errors ); 
       
        if ( @errors )
        {
            foreach $error ( @errors )
            {
                push @messages, [ "Error", $error ];
            }
             
            $xhtml = &Common::Widgets::register_page( $sid, $account, \@messages );
            
            $state->{"with_menu_bar"} = 1;
            $state->{"menu_click"} = "menu_1:login";

            &Common::Widgets::show_page(
                {
                    "body" => $xhtml,
                    "sys_state" => $state,
                    "project" => $proj,
                });

            exit 0;
        }
        elsif ( $acc_sid )
        {
            $sid = $acc_sid;
            $session = &Common::Users::get_session( $sid );
            
            $state->{"sys_request"} = "";
            $state->{"logged_in"} = 1;                
            
            &Common::States::save_sys_state( $acc_sid, $state );
        }
        else {
            &Common::Messages::error( qq (Account could not be added - no session id) );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> REGISTRATION PAGE <<<<<<<<<<<<<<<<<<<<<<<

    # Displays a page that asks user for first and last names, and a user
    # name and password,

    elsif ( $request =~ /^register_page$/i )
    {
        $cgi->delete("sys_request");
        
        if ( not $sid ) 
        {
            $session = &Common::Users::new_session( "$Common::Config::ses_dir/Temporary" );
            $sid = $session->id;
        }
        
        $xhtml = &Common::Widgets::register_page( $sid );
        
        $state = &Common::States::restore_sys_state( $sid, $proj );
        
        $state->{"with_menu_bar"} = 1;
        $state->{"menu_click"} = "menu_1:login";

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $state,
                "project" => $proj,
            });

        exit 0;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOGIN PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    elsif ( $request =~ /^login_page$/i )
    {
        $cgi->delete("sys_request");

        $xhtml = &Common::Widgets::login_page( $sid );

        $state = &Common::States::restore_sys_state( $sid, $proj );

        $state->{"with_menu_bar"} = 1;
        $state->{"menu_click"} = "menu_1:login";

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $state,
                "project" => $proj,
            });

        exit 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOGIN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    elsif ( $request =~ /^enter$/i )
    {
        $cgi->delete("sys_request");
        
        $username = $cgi->param('username') || "" if not $username;
        $password = $cgi->param('password') || "" if not $password;
        
        if ( $login_sid = &Common::Accounts::get_session_id( $username, $password, $proj->name ) )
        {
            $login_sid = "Accounts/$login_sid";
            
            $session = &Common::Users::get_session( $login_sid );
            
            $state = &Common::States::restore_sys_state( $login_sid, $proj );
            $state->{"request"} = "";
            $state->{"logged_in"} = 1;
            $state->{"username"} = $username;

            &Common::States::save_sys_state( $login_sid, $state );
            
            if ( $sid ne $login_sid ) { 
                &Common::Users::delete_session( $sid );
            }
        }
        else
        {
            push @errors, [ "Error", qq (Could not log in. Perhaps it is a typing error, then)
                            . qq ( please try again. If not, please create yourself an) 
                            . qq ( account with the button below.) ];
            
            $xhtml = &Common::Widgets::login_page( $sid, \@errors, $username );
            
            $state = &Common::States::restore_sys_state( $sid, $proj );
            
            $state->{"with_menu_bar"} = 1;
            $state->{"menu_click"} = "menu_1:login";

            &Common::Widgets::show_page(
                {
                    "body" => $xhtml,
                    "sys_state" => $state,
                    "project" => $proj,
                });
            
            exit 0;
        }
        
        # Delete all temporary sessions where last access is older than 24 hours,
        
        &Common::Users::delete_old_tmp_sessions( 24 );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOGOUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request =~ /^logout$/i )
    {
        if ( $sid and -d "$Common::Config::ses_dir/$sid" )
        {
            $state = &Common::States::restore_sys_state( $sid, $proj );
            
            $state->{"request"} = "";
            $state->{"logged_in"} = 0;
            $state->{"username"} = "";
            
            $state->{"session_id"} = "";
            
            &Common::States::save_sys_state( $sid, $state );
        }

        $xhtml = &Common::Widgets::login_page( $sid, undef, $username );
        $session = &Common::Users::new_session( "$Common::Config::ses_dir/Temporary" );
        
        $state->{"with_menu_bar"} = 1;
        $state->{"menu_click"} = "menu_1:login";

        &Common::Widgets::show_page( 
            {
                "body" => $xhtml,
#                "session_id" => $session->param("session_dir"),
                "sys_state" => $state,
                "project" => $proj,
                "window_target" => "main",
            });

        exit 0;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> ALL OTHER REQUESTS <<<<<<<<<<<<<<<<<<<<<<<<<

    # When user clicks on viewer pages then there is no "sys_request" and we
    # get to here,
    
    elsif ( $sid ) {
        $session = &Common::Users::get_session( $sid );
    } else {
        $session = &Common::Users::new_session( "$Common::Config::ses_dir/Temporary" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SET ACCESS TIME ETC <<<<<<<<<<<<<<<<<<<<<<<

    if ( $session )
    {
        $epoch = &Common::Util::time_string_to_epoch();
        
        $session->param( "last_access", $epoch );
        $session->flush;
        
        $sid = $session->param("session_dir");
        
        return $sid;
    }
    else {
        &Common::Messages::error( qq (Could not fetch a session) );
    }
    
    return;
}

sub new_session
{
    # Niels Larsen, May 2003.
    
    # Creates a new CGI::Session object. 

    my ( $ses_dir,
         $quotas,
         $login,
         ) = @_;

    # Returns a session object.

    my ( $session, $sid );

    $login = 0 if not defined $login;

    if ( not defined $ses_dir ) {
        &Common::Messages::error( qq (No session directory given) );
    }

    &Common::File::create_dir_if_not_exists( $ses_dir );

    require CGI::Session;
    require CGI::Session::Driver::file;
    
    $CGI::Session::IP_MATCH = 0;
    $CGI::Session::Driver::file::FileName = '%s/session';

    if ( $session = new CGI::Session( "driver:File", undef, { Directory => $ses_dir } ) )
    {
        $sid = $session->id;

        &Common::File::create_dir( "$ses_dir/$sid" );

        if ( $login ) {
            $session->param( "logged_in", 1 );
        } else {
            $session->param( "logged_in", 0 );
        }

        if ( $ses_dir =~ /Temporary$/ ) {
            $session->param( "session_dir", "Temporary/$sid" );
        } elsif ( $ses_dir =~ /Accounts$/ ) {
            $session->param( "session_dir", "Accounts/$sid" );
        } else {
            &Common::Messages::error( qq (Wrong-looking session directory -> "$ses_dir") );
        }

        if ( $quotas ) {
            $session->param( "quotas", $quotas );
        }
        
        if ( not &Common::Messages::is_run_by_web_server ) {
            $session->remote_addr( "127.0.0.1" );
        }

        $session->expires( 0 );
        $session->flush;
    }
    else {
        &Common::Messages::error( qq (Could not create new session), "CREATE SESSION ERROR" );
    }

    if ( $session ) {
        return $session;
    } else {
        return;
    }
}

sub savings_add
{
    # Niels Larsen, February 2004.

    # Saves a hash that describes a piece of information to a given 
    # file under a given user directory. It is appended to the file
    # by default, but an index can be given where it will be inserted.
    # The resulting list is returned.

    my ( $sid,       # Session id
         $file,      # File name
         $info,      # Information hash
         $index,     # Insertion index
         ) = @_;

    # Returns a list of hashes. 

    if ( not $sid ) {
        &Common::Messages::error( qq (User ID is not given) );
    }

    if ( not $file ) {
        &Common::Messages::error( qq (File is not given) );
    }

    if ( not $info ) {
        &Common::Messages::error( qq (Information hash is not given) );
    }

    my ( $list, $length );

    if ( -r "$Common::Config::ses_dir/$sid/$file" )
    {
        $list = &Common::Users::savings_read( $sid, $file );

        if ( defined $index )
        {
            if ( $index > scalar @{ $list } )
            {
                $length = scalar @{ $list };
                &Common::Messages::error( qq (Header insert position ($index) should be $length or less) );
            }
            elsif ( $index < 0 ) 
            {
                &Common::Messages::error( qq (Header insert position ($index) should be higher than zero) );
            }
            
            splice @{ $list }, $index, 0, dclone $info;
        }
        else {
            push @{ $list }, $info;
        }
    }
    else {
        $list = [ &Storable::dclone( $info ) ];
    }

    $list = &Common::Menus::set_items_ids( $list );

    &Common::Users::savings_save( $sid, $file, $list );

    return wantarray ? @{ $list } : $list;
}

sub savings_delete
{
    # Niels Larsen, February 2004.

    # Deletes a single information hash from a file in a given users
    # directory. The last one is deleted if no index is given. If after
    # the deletion the list is empty then the file itself is deleted.

    my ( $sid,       # Session id
         $file,      # File name
         $index,     # Deletion index - OPTIONAL
         ) = @_;

    # Returns a shorter list of hashes. 

    my ( $length, $list, $path );

    $list = &Common::Users::savings_read( $sid, $file );

    if ( defined $index )
    {
        if ( $index > $#{ $list } )
        {
            $length = $#{ $list };
            &Common::Messages::error( qq (Delete position ($index) should be $length or less) );
        }
        elsif ( $index < 0 ) 
        {
            &Common::Messages::error( qq (Delete position ($index) should be higher than zero) );
        }
        
        splice @{ $list }, $index, 1;
    }
    else {
        pop @{ $list };
    }

    if ( scalar @{ $list } > 0 )
    {
        &Common::Users::savings_save( $sid, $file, $list );

        return wantarray ? @{ $list } : $list;
    }
    else
    {
        $path = "$Common::Config::ses_dir/$sid/$file";
        &Common::File::delete_file( $path );

        return;
    }
}

sub savings_read
{
    # Niels Larsen, February 2004.

    # Reads a given file of saved information hashes into memory.

    my ( $sid,       # Session id
         $file,      # File name
         ) = @_;

    # Returns a list of hashes. 

    if ( not $sid ) {
        &Common::Messages::error( qq (User ID is not given) );
    }

    if ( not $file ) {
        &Common::Messages::error( qq (Savings file is not given) );
    }

    my ( $list, $path );

    $path = "$Common::Config::ses_dir/$sid/$file";

    if ( -r $path )
    {
        $list = &Common::File::eval_file( $path );
        $list = &Common::Menus::set_items_ids( $list );

        if ( not $list or not @{ $list } ) {
            &Common::Messages::error( qq (Empty savings file found) );
        }
    }
    else {
        &Common::Messages::error( qq (Could not read from file -> "$sid/$file") );
    }

    return wantarray ? @{ $list } : $list;
}

sub savings_save
{
    # Niels Larsen, February 2004.

    # Saves a given list of information hashes in a given file
    # under a given user directory. 

    my ( $sid,     # Session id
         $file,    # Savings file
         $list,    # Information hashes
         ) = @_;

    # Returns nothing.

    if ( not $sid ) {
        &Common::Messages::error( qq (User ID is not given) );
    }

    if ( not $file ) {
        &Common::Messages::error( qq (Savings file is not given) );
    }

    if ( not $list ) {
        &Common::Messages::error( qq (Savings list is not given) );
    }

    my ( $path, $ref );

    $path = "$Common::Config::ses_dir/$sid/$file";

    if ( $list )
    {
        if ( ref $list )
        {
            if ( ref $list eq "ARRAY" )
            {
                if ( @{ $list } )
                {
                    $list = &Common::Menus::set_items_ids( $list );
                    &Common::File::dump_file( $path, $list );
                }
                else {
                    &Common::Messages::error( qq (Savings list is empty) );
                }                    
            }
            else {
                $ref = ref $list;
                &Common::Messages::error( qq (List should be an ARRAY reference, it is -> "$ref") );
            }
        }
        else {
            &Common::Messages::error( qq (List should be an ARRAY reference, it is a scalar) );
        }
    }
    else {
        &Common::Messages::error( qq (No savings list is given) );
    }

    return;
}

1;

__END__
