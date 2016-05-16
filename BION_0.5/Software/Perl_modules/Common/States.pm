package Common::States;     #  -*- perl -*-

# Functions specific to the handling of states. We keep viewer-specific 
# state and a global-state that is not specific to any viewer. The latter
# contains, for example, which viewer should be invoked and what its input
# is. In some cases, like alignments, we keep state for each alignment. A
# state is a hash with a dozen or so keys and values. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &default_states
                 &delete_job_status
                 &make_hash
                 &merge_cgi_with_sys_state
                 &merge_cgi_with_viewer_state
                 &merge_tuples
                 &restore_job_status
                 &restore_method_params
                 &restore_viewer_features
                 &restore_viewer_prefs
                 &restore_state
                 &restore_sys_state
                 &save_job_status
                 &save_method_params
                 &save_state
                 &save_sys_state
                 &save_viewer_features
                 &save_viewer_prefs
                 &set_navigation_visit
                 );

use Common::Config;
use Common::Messages;

use Registry::Args;
use Registry::Get;

use Common::File;
use Common::Util;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub default_states
{
    # Niels Larsen, October 2007.

    # Defines default system settings, such as session id etc. If a 
    # project is given, defaults from that project is filled in.

    my ( $proj,           # Project object - OPTIONAL
        ) = @_;  

    # Returns a hash.

    my ( $states, $defs, $hide, %hide );

    $states = 
    {
        "system" => {
            "version" => 2,
            "projpath" => "",
            "description" => {},
            "is_help_page" => 0,
            "logged_in" => 0,
            "sys_menu_1" => "",
            "sys_menu_2" => "",
            "sys_menu_3" => "",
            "menu_click" => "",
            "menu_visits" => {},
            "menu_selections_id" => 0,
            "uploads_menu" => 0,
            "viewer" => "",
            "inputdb" => "",
            "request" => "",
            "password" => "",
            "form_name" => "",
            "session_id" => "",
            "username" => "",
            "jobs_running" => 0,
            "with_header_bar" => 1,
            "with_footer_bar" => 1,
            "with_menu_bar" => 1,
            "with_home_link" => 1,
            "with_results" => 0,
            "with_nav_analysis" => 1,
            "with_nav_login" => 1,
            "multipart_form" => 0,
        },

        "info" => {
            "info_request" => "summary",
            "version" => 1,
        },
    };
 
    if ( defined $proj )
    {
        $defs = $proj->defaults;

        $states->{"system"}->{"sys_menu_1"} = $defs->{"def_menu_1"};
        $states->{"system"}->{"sys_menu_2"} = $defs->{"def_menu_2"};
        $states->{"system"}->{"sys_menu_3"} = $defs->{"def_menu_3"};

        $states->{"system"}->{"projpath"} = $proj->projpath;

        $states->{"system"}->{"description"} = $proj->description;

        if ( $hide = $proj->hide_navigation )
        {
            $hide = [ $hide ] if not ref $hide;
            %hide = map { $_, 1 } @{ $hide };

            if ( $hide{"analysis"} ) {
                $states->{"system"}->{"with_nav_analysis"} = 0;
            }
        }
    }

    return wantarray ? %{ $states } : $states;
}

sub delete_job_status
{
    # Niels Larsen, December 2007.

    my ( $sid, 
         ) = @_;

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/JOB_STATUS";

    if ( -r $file )
    {
        &Common::File::delete_file( $file );
        return 1;
    }
    else {
        return;
    }
}

sub make_hash
{
    # Niels Larsen, July 2007.

    # From two lists of keys and values, simply returns a hash with the 
    # corresponding key/value pairs set. It is used for example with web
    # forms, where one param value may hold the keys, and another the 
    # values. 

    my ( $keys,        # key list 
         $values,      # value list
         ) = @_;

    # Returns a hash. 

    my ( $k, $v, $i, %hash );

    if ( not defined $keys ) {
        &Common::Messages::error( qq (No keys given) );
    }        

    if ( not defined $values ) {
        &Common::Messages::error( qq (No values given) );
    }        

    if ( ( $k = scalar @{ $keys } ) != ( $v = scalar @{ $values } ) )
    {
        &Common::Messages::error( qq (There are $k keys but $v values) );
    }

    for ( $i = 0; $i <= $#{ $keys }; $i++ )
    {
        $hash{ $keys->[$i] } = $values->[$i];
    }

    return wantarray ? %hash : \%hash;
}    

sub merge_cgi_with_sys_state
{
    # Niels Larsen, October 2005.

    # Updates the system state with CGI values. They are copied under the
    # same key names, except "sys_request" is remapped to "request". 

    my ( $cgi,        # CGI.pm object
         $sid,        # Session ID
         $proj,       # Project
         ) = @_;

    # Returns a hash.

    my ( $state, $key, $value, $nav_click, $visits, $visits_1 );

    if ( not $cgi ) {
        &Common::Messages::error( qq (No CGI.pm object given) );
    }
    
    if ( not $sid ) {
        &Common::Messages::error( qq (No session ID given) );
    }

    $state = &Common::States::restore_sys_state( $sid, $proj );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CAPTURE CGI VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Copy cgi values to the system state hash. Only take those that are set
    # and that share keys with the state hash. Keys that start with "menu_n"
    # are caught in a special hash and used below; the state key "request" is
    # taken from "sys_request" because "request" may be used by viewers too,

    foreach $key ( $cgi->param )
    {
        if ( defined ( $value = $cgi->param( $key ) ) )
        {
            if ( $key =~ /^menu_(\d)$/ )
            {
                $state->{"sys_menu_$1"} = $value;
                $state->{"menu_click"} = "$key:$value";
            }
            elsif ( $key eq "sys_request" )
            {
                $state->{"request"} = $value;
            }
            elsif ( exists $state->{ $key } )
            {
                $state->{ $key } = $value;
            }
        }
    }

    # Session id may be overwritten above, so reset it here,

    $state->{"session_id"} = $sid;

    return $state;
}

sub merge_cgi_with_viewer_state
{
    # Niels Larsen, October 2005.

    # Merge the CGI parameters that are keys in the given state hash:
    # CGI values override, state values are used otherwise, but if 
    # missing they are filled in with defaults.

    my ( $cgi,           # CGI.pm object
         $sid,           # Session id
         $state,         # State hash
         $def_state,     # Default state hash
         ) = @_;

    # Returns an updated state hash.

    my ( $key, @values );

    if ( not $cgi ) {
        &Common::Messages::error( qq (No CGI object given) );
    }
    
    if ( not $sid ) {
        &Common::Messages::error( qq (No Session ID given) );
    }
    
    if ( not $state ) {
        &Common::Messages::error( qq (No state hash given) );
    }
    
    if ( not $def_state ) {
        &Common::Messages::error( qq (No default state hash given) );
    }

    foreach $key ( $cgi->param )
    {
        if ( exists $def_state->{ $key } )
        {
            @values = $cgi->param( $key );

            if ( ref $def_state->{ $key } )
            {
                $state->{ $key } = dclone \@values;
            }
            else
            {
                if ( @values and defined $values[0] )
                {
                    $state->{ $key } = $values[0];
                }
            }
        }
    }

    return $state;
}

sub restore_job_status
{
    my ( $sid, 
         ) = @_;

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/JOB_STATUS";

    if ( -r $file )
    {
        return ${ &Common::File::read_file( $file ) };
    }
    else {
        return;
    }
}

sub restore_viewer_features
{
    # Niels Larsen, April 2007.

    # Returns a features preferences hash from 
    # 
    # $Common::Config::ses_dir/Viewers/$viewer_name.features
    # 
    # if that file exists, otherwise builds one from registry information.

    my ( $args,      # Viewer name, e.g. "array_viewer"
         ) = @_;
    
    # Returns a hash reference.

    my ( $name, $sid, $type, $file, $hash );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer sid datatype ) ],
    });

    $name = $args->viewer;
    $sid = $args->sid;
    $type = $args->datatype;

    if ( $sid and -r ( $file = "$Common::Config::ses_dir/$sid/Viewers/$name.features") )
    {        
        $hash = &Common::File::eval_file( $file )->{ $type };
    }
    else {
        $hash = {};
    }

    return $hash;
}

sub restore_viewer_prefs
{
    # Niels Larsen, April 2007.

    # Fetches a preferences hash from 
    # 
    # $Common::Config::ses_dir/Viewers/$viewer_name.prefs
    # 
    # if that file exists, otherwise builds a structure using registry
    # defaults.

    my ( $args,      # Viewer or method object
         ) = @_;
    
    # Returns a hash reference.

    my ( $name, $sid, $file, $hash, $viewer );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer ) ],
        "S:0" => [ qw ( sid ) ],
    });

    $name = $args->viewer;
    $sid = $args->sid;

    if ( $sid and -r ( $file = "$Common::Config::ses_dir/$sid/Viewers/$name.prefs") )
    {        
        $hash = &Common::File::eval_file( $file );
    }
    else {
        $hash = Registry::Get->viewer_prefs( $name );
    }

    return $hash;
}

sub restore_sys_state
{
    my ( $sid,
         $proj,
        ) = @_;

    return &Common::States::restore_state( "system", $sid, $proj );
}
    
sub restore_state
{
    # Niels Larsen, October 2004.

    # Fetches state information of a given type for a given user. The
    # state is a hash wish keys and values that for example a given viewer
    # knows how to handle. If the state from file has a lower version 
    # number than the current defaults then the defaults are used and
    # they overwrite the saved state.

    my ( $type,    # Type, "system", "upload", etc.
         $sid,     # Session ID 
         $proj,
         ) = @_;

    # Returns a hash.

    my ( $defaults, $file, $dir, $site_dir, $state, $defs, $key );

    &Common::Messages::error( qq (Session ID is not given) ) if not $sid;
    &Common::Messages::error( qq (State type is not given) ) if not $type;

    $dir = "$Common::Config::ses_dir/$sid";
    $file = "$dir/$type" .".state";

    $defs = &Common::States::default_states( $proj )->{ $type };

    if ( -r $file )
    {
        if ( -s $file )
        {
            $state = &Common::File::eval_file( $file );
#            $state = &Common::File::retrieve_file( $file );

            foreach $key ( keys %{ $defs } )
            {
                if ( not exists $state->{ $key } ) {
                    $state->{ $key } = $defs->{ $key };
                }
            }
        }
        else {
            $state = $defs;
        }

        if ( not $state or $state->{"version"} != $defs->{"version"} )
        {
            $state = $defs;
            &Common::File::dump_file( $file, $state );
#            &Common::File::store_file( $file, $state );
        }
    }
    elsif ( -d $dir ) 
    {
        $state = $defs;

        &Common::File::dump_file( $file, $state );
#        &Common::File::store_file( $file, $state );
    }
    else {
        &Common::Messages::error( qq (Directory does not exist -> "$Common::Config::ses_dir/$sid") );
    }

#    $state->{"session_id"} = $sid;

    
    return wantarray ? %{ $state } : $state;
}

sub save_job_status
{
    # Niels Larsen, April 2006.

    # Loads the general state for a given session id, sets "jobs_icon"
    # to the given value, and saves the state back. 

    my ( $sid,
         $status,
         ) = @_;

    # Returns a string.
    
    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/JOB_STATUS";

    &Common::File::delete_file_if_exists( $file );
    &Common::File::write_file( $file, $status );

    return $file;
}
 
sub save_state
{
    # Niels Larsen, October 2004.

    # Writes a given state hash to file under a given user directory.

    my ( $type,    # Type, e.g. "taxonomy", "function", etc.
         $sid,     # Session ID 
         $state,   # State hash
         ) = @_;

    # Returns a hash.

    my ( $file, $dir );

    if ( not $sid ) {
        &Common::Messages::error( qq (Session ID is not given) );
    }

    if ( not $type ) {
        &Common::Messages::error( qq (State type is not given) );
    }
    
    if ( not $state ) {
        &Common::Messages::error( qq (State data hash is not given) );
    }

    $dir = "$Common::Config::ses_dir/$sid";

    $state->{"session_id"} = $sid;

    if ( -d $dir ) {
#        &Common::File::store_file( "$dir/$type" .".state", $state );
        &Common::File::dump_file( "$dir/$type" .".state", $state );
    } else {
        &Common::Messages::error( qq (Directory does not exist -> "$dir") );
    }
    
    return;
}

sub save_sys_state
{
    my ( $sid,
         $state,
        ) = @_;

    return &Common::States::save_state( "system", $sid, $state );
}
    
sub save_viewer_features
{
    my ( $name,
         $sid,
         $hash,
         $type,
         ) = @_;

    my ( $dir, $file, $struct );

    $dir = "$Common::Config::ses_dir/$sid/Viewers";
    &Common::File::create_dir_if_not_exists( $dir );

    $file = "$dir/$name.features";

    if ( -r $file )
    {
        $struct = &Common::File::eval_file( $file );
        &Common::File::delete_file( $file );
    }
    else {
        $struct = {};
    }
    
    $struct->{ $type } = $hash;
    &Common::File::dump_file( $file, $struct );

    return $file;
}

sub save_viewer_prefs
{
    # Niels Larsen, April 2007.

    # Saves the given preferences structure the file
    # 
    # $Common::Config::ses_dir/Viewers/$viewer_name.prefs
    # 
    # The directory is created if needed and the old file overwritten 
    # if it exists. The name of the file created is returned.

    my ( $name,      # Viewer name, e.g. "array_viewer"
         $sid,       # Session ID 
         $struct,    # Preferences structure
         $suffix,    # File suffix - OPTIONAL
         ) = @_;

    # Returns a string.

    my ( $dir, $file );

    &Common::Messages::error( qq (Viewer name is not given) ) if not $name;
    &Common::Messages::error( qq (Session ID is not given) ) if not $sid;
    &Common::Messages::error( qq (Preferences structure is not given) ) if not $struct;

    $suffix ||= ".prefs";

    $dir = "$Common::Config::ses_dir/$sid/Viewers";
    &Common::File::create_dir_if_not_exists( $dir );

    $file = "$dir/$name$suffix";
    &Common::File::delete_file_if_exists( $file );
    
    &Common::File::dump_file( $file, $struct );

    return $file;
}

sub set_navigation_visit
{
    # Niels Larsen, November 2006.

    # Puts the last visited menu bar options and input into the system state
    # under the key "menu_visits".

    my ( $state,           # System state hash
         ) = @_;

    # Returns a hash.

    $state->{"menu_visits"}->{ $state->{"sys_menu_1"} }->[0] = $state->{"sys_menu_2"};

    if ( $state->{"inputdb"} )
    {
        $state->{"menu_visits"}->{ $state->{"sys_menu_1"} }->[1]->{ $state->{"sys_menu_2"} } = $state->{"inputdb"};
    }

    return $state;
}

1;

__END__
