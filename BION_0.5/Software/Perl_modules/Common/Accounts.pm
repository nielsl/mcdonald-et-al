package Common::Accounts;     #  -*- perl -*-

# Functions specific to managing user logins. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_user
                 &all_fields
                 &connect_db
                 &delete_user
                 &get_session_id
                 &get_user_name
                 &list_users
                 &mandatory_fields
                 );

use Common::Config;
use Common::Messages;

use Common::DB;
use Common::File;
use Common::Config;
use Common::Users;
use Common::Admin;

use Registry::Schema;

our $Schema_name = "users";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_user
{
    # Niels Larsen, March 2004.

    # Adds a user to the registry, initializes a session and returns 
    # its session ID. If the user registry does not exist, it gets 
    # created. 

    my ( $info,       # Key / value hash
         $msgs,     # Error list
         ) = @_;

    # Returns a string and updates $msgs if errors.

    my ( $sid, $sql, $dbh, $session, @values, $field, $table, 
         $info_str, $tables, $tab_name, $schema );
    
    foreach $field ( &Common::Accounts::mandatory_fields() )
    {
        if ( not $info->{ $field } )
        {
            $field = &Common::Names::format_display_name( $field );
            push @{ $msgs }, qq (Missing mandatory field: "$field");
        }
    }

    return if @{ $msgs };

    if ( not &Common::Admin::mysql_is_running )
    {
        &echo( "\n" );
        &Common::Admin::start_mysql();
    }

    if ( not &Common::Admin::mysql_is_running ) {
        &Common::Messages::error( qq (MySQL is not running) );
    }

    if ( &Common::Accounts::get_session_id( $info->{"username"}, undef, $info->{"project"} ) )
    {
        push @{ $msgs }, qq (Username "$info->{'username'}" exists);
    }
    else
    {
        $dbh = &Common::Accounts::connect_db();

        $session = &Common::Users::new_session( "$Common::Config::ses_dir/Accounts" );
        
        if ( not $session )
        {
            &Common::DB::disconnect( $dbh );
            push @{ $msgs }, qq (Could not create new session);
            return;
        }
        
        $sid = $session->id;
        $info->{"session_id"} = $sid;

        $schema = Registry::Schema->get( $Schema_name );

        foreach $table ( $schema->tables )
        {
            @values = ();

            foreach $field ( map { $_->[0] } $table->columns )
            {
                push @values, $info->{ $field } || "";
            }
            
            $info_str = '"'. (join qq (", "), @values) .'"';
            $tab_name = $table->name;

            $sql = qq (insert into $tab_name values ( $info_str ) );
            
            &Common::DB::request( $dbh, $sql );
        }

        &Common::DB::disconnect( $dbh );
    }
    
    if ( @{ $msgs } ) {
        return;
    } else {
        return "Accounts/$sid";
    }
}

sub all_fields
{
    # Niels Larsen, March 2004.

    # Lists all fields in the user account database. 

    # Returns a list.

    my ( $table, @fields, $field );

    foreach $table ( Registry::Schema->get( $Schema_name )->tables )
    {
        foreach $field ( map { $_->[0] } $table->columns )
        {
            push @fields, $field;
        }
    }

#    @fields = sort @fields;

    return wantarray ? @fields : \@fields;
}

sub connect_db
{
    # Niels Larsen, May 2005.

    # Returns a handle to the user accounts database. The database 
    # is created if it does not exist. 

    # Returns a scalar. 

    my ( $schema, $db_name, $dbh, $table, $columns );

    $schema = Registry::Schema->get( $Schema_name );
    $db_name = $schema->datadir;

    if ( not &Common::DB::database_exists( $db_name ) )
    {
        &Common::DB::create_database( $db_name );
        sleep 1;
    }

    $dbh = &Common::DB::connect( $db_name );

    foreach $table ( $schema->tables )
    {
        if ( not &Common::DB::table_exists( $dbh, $table->name ) )
        {
            &Common::DB::create_table( $dbh, $table );
        }
    }

    return $dbh;
}

sub delete_user
{
    # Niels Larsen, May 2003.

    # Removes a user from the registry, deletes the session and returns 
    # the ID of the deleted session.

    my ( $username,    # User name
         $password,    # Password 
         $project,     # Project
         $msgs,        # Error list
         ) = @_;

    # Returns a string. 

    my ( $error_type, $dbh, $sql, $sid, $user_id, $session, $user_dbh );
    
    $error_type = "DELETE USER ERROR";
    
    if ( not $username ) {
        &Common::Messages::error( "No user name given", $error_type );
    } elsif ( not $password ) {
        &Common::Messages::error( "No password given", $error_type );
    } elsif ( not $project ) {
        &Common::Messages::error( "No project given", $error_type );
    } 

    if ( not &Common::Admin::mysql_is_running )
    {
        &echo( "\n" );
        &Common::Admin::start_mysql();
    }

    if ( not &Common::Admin::mysql_is_running ) {
        &Common::Messages::error( qq (MySQL is not running) );
    }

    if ( $sid = &Common::Accounts::get_session_id( $username, $password, $project ) )
    {
        $dbh = &Common::Accounts::connect_db();

        # Delete session directory under Accounts,

        &Common::Users::delete_session( "Accounts/$sid" );

#         if ( not &Common::Users::delete_session( "Accounts/$sid" ) )
#         {
#             push @{ $msgs }, qq (Could not delete session -> "$sid");
#             return;
#         }

        &Common::File::delete_file_if_exists( "$Common::Config::ses_dir/$sid" );

        # Delete user database if exists,

#        if ( &Common::DB::database_exists( $sid ) )
#        {
#            $user_dbh = &Common::DB::connect( $sid );
#            &Common::DB::delete_database( $user_dbh, $

        &Common::File::delete_file_if_exists( "$Common::Config::dat_dir/$sid" );

        # Delete user name from accounts database,

        $sql = qq (select user_id from accounts where username = "$username" and password = "$password" and project = "$project");
        $user_id = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        if ( defined $user_id )
        {
            $sql = qq (delete from accounts where user_id = $user_id);
            &Common::DB::request( $dbh, $sql );

            $sql = qq (delete from info where user_id = $user_id);
            &Common::DB::request( $dbh, $sql );
        }
        else
        {
            &Common::DB::disconnect( $dbh );
            push @{ $msgs }, qq (Username "$username", password "$password" does not exist for project "$project");
            return;
        }

        &Common::DB::disconnect( $dbh );

        return 1;
    }
    else
    {
        push @{ $msgs }, qq (Username "$username", password "$password" does not exist for project "$project");
        return;
    }
}

sub get_session_id
{
    # Niels Larsen, May 2003. 

    # Runs a query on the users database to see if a given user
    # with a given password is registered. If yes, return the 
    # corresponding session ID; if not, return nothing. 

    my ( $username,        # User name
         $password,        # Password - OPTIONAL
         $project,         # Project id - OPTIONAL
         ) = @_;

    # Returns scalar or nothing.

    my ( $dbh, $sql, @users );

    $dbh = &Common::Accounts::connect_db();

    $sql = qq (select username,password,session_id from accounts where username = "$username");

    if ( $password ) {
        $sql .= qq ( and password = "$password");
    } 
    
    if ( $project ) {
        $sql .= qq ( and project = "$project");
    } 
    
    @users = &Common::DB::query_array( $dbh, $sql );

    &Common::DB::disconnect( $dbh );

    if ( @users ) 
    {
        if ( scalar @users == 1 )
        {
            return $users[0]->[2];
        }
        else {
            &Common::Messages::error( qq (More than one user "$username" with password "$password") );
        }
    }

    return;
}

sub get_user_name
{
    # Niels Larsen, December 2005.

    # Returns the user name that goes with a given session id. 

    my ( $sid,             # Session id
         ) = @_;

    # Returns string.

    my ( $sql, $dbh, @users, $md5 );

    $dbh = &Common::Accounts::connect_db();
    
    $md5 = ( split "/", $sid )[-1];

    $sql = qq (select username from accounts where session_id = "$md5");

    @users = &Common::DB::query_array( $dbh, $sql );

    &Common::DB::disconnect( $dbh );

    if ( @users ) 
    {
        if ( scalar @users == 1 )
        {
            return $users[0]->[0];
        }
        else {
            &Common::Messages::error( qq (More than one user with session id "$sid") );
        }
    }

    return;
}

sub list_users
{
    # Niels Larsen, March 2005.

    # Returns a table of user information. 

    my ( $dbh,      # Database handle - OPTIONAL
         $fields,   # Fields list 
         ) = @_;

    my ( $sql, $select, @table, $disconnect );

    if ( not &Common::Admin::mysql_is_running )
    {
        &echo( "\n" );
        &Common::Admin::start_mysql();
    }

    if ( not &Common::Admin::mysql_is_running ) {
        &Common::Messages::error( qq (MySQL is not running) );
    }

    if ( not $dbh ) 
    {
        $dbh = &Common::Accounts::connect_db();
        $disconnect = 1;
    }

    $select = join ",", @{ $fields };
    $sql = qq (select $select from accounts,info where accounts.user_id = info.user_id);

    @table = &Common::DB::query_array( $dbh, $sql );

    &Common::DB::disconnect( $dbh ) if $disconnect;

    return wantarray ? @table : \@table;
}

sub mandatory_fields
{
    # Niels Larsen, March 2004.

    # Creates a list of mandatory user account fields.

    # Returns a list.

    my @fields = (
        "first_name",
        "last_name",
        "username",
        "password",
        "project",
        );

    return wantarray ? @fields : \@fields;
}

1;

__END__
