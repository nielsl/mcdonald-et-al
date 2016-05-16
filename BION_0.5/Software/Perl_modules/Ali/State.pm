package Ali::State;     #  -*- perl -*-

# Functions specific to array_viewer state and its upkeep.

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use File::Basename;

@EXPORT_OK = qw (
                 &default_state
                 &merge_cgi_with_viewer_state
                 &restore_state
                 &save_state
                 &split_dataloc
                 );

use Common::Config;
use Common::Messages;

use Common::States;
use Common::File;
use Common::Util;

use Ali::Common;

our $Viewer_name = "array_viewer";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub default_state
{
    # Niels Larsen, October 2004.

    # Defines default settings for each page or viewer. These defaults
    # are used when new users are created. 

    my ( $sid,
        ) = @_;

    # Returns a hash.

    my ( $state );

    $state = {
        %{ &Ali::Common::default_params() },
        "request" => "",
        "ali_control_menu" => undef,
        "ali_control_menu_open" => 0,
        "ali_download_keys" => [],
        "ali_download_values" => [],
        "ali_features_keys" => [],
        "ali_features_values" => [],
        "ali_features_menu" => undef,
        "ali_features_menu_open" => 0,
        "ali_prefs_keys" => [],
        "ali_prefs_values" => [],
        "ali_print_keys" => [],
        "ali_print_values" => [],
        "ali_inputdb_menu" => undef,
        "ali_inputdb_menu_open" => 0,
        "ali_user_menu" => undef,
        "ali_user_menu_open" => 0,
        "ali_sid_left_indent" => "right",
        "ali_sid_right_indent" => "left",
        "ali_zoom_pct" => undef,
    };

    $state->{"ali_prefs"} = &Common::States::restore_viewer_prefs(
        {
            "viewer" => $Viewer_name,
            "sid" => $sid,
        });
        
    return wantarray ? %{ $state } : $state;
}

sub merge_cgi_with_viewer_state
{
    # Niels Larsen, November 2006.
    
    # Copies the values of the cgi arguments that are known to the alignment 
    # into a state hash and returns this hash. If a state hash was previously
    # saved under the given session id, then that is used as template, otherwise
    # the default is used. 

    my ( $cgi,         # CGI.pm object
         $sid,         # Session id
         $input,       # Input data path identifier
        ) = @_;

    # Returns a hash.

    my ( $state, $def_state, $key, $value, $dat_path, $name, $file, $db );

    &error( qq (Session ID is not given) ) if not $sid;
    &error( qq (No input data is given) ) if not $input;
    
    ( $name, $file ) = &Ali::State::split_dataloc( $input );

    $db = Registry::Get->dataset( $name );
    $dat_path = $db->datapath ."/Installs/$file.". $db->datatype;

    $state = &Ali::State::restore_state( $sid, $dat_path );

    $state->{"ali_dat_path"} = $dat_path;
    $state->{"inputdb"} = $input;

    $def_state = &Ali::State::default_state();

    $state = &Common::States::merge_cgi_with_viewer_state( $cgi, $sid, $state, $def_state );

    foreach $key ( "ali_zoom_pct" )
    {
        if ( defined ( $value = $cgi->param( $key ) ) )
        {
            $state->{"ali_prefs"}->{ $key } = $value;
        }
    }

    return $state;
}

sub restore_state
{
    # Niels Larsen, August 2005.

    # Fetches state information of a given type for a given user. The
    # state is a hash wish keys and values that for example a given viewer
    # knows how to handle. If the state from file has a lower version 
    # number than the current defaults then the defaults are used and
    # they overwrite the saved state.

    my ( $sid,        # Session ID 
         $input,      # Alignment prefix path
         $suffix,     # File path suffix - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $defs, $state, $file, $dir, $prefs, $key );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $input ) {
        &error( qq (Alignment name not given) );
    }

    $defs = &Ali::State::default_state( $sid );

    $file = "$Common::Config::ses_dir/$sid/$input".".state";
    $file .= "$suffix" if defined $suffix;

    if ( -r $file )
    {
        $state = &Common::File::retrieve_file( $file );

        if ( not $state or $state->{"version"} != $defs->{"version"} )
        {
            $state = $defs;
            &Common::File::store_file( $file, $state );
        }
    }
    else
    {
        $dir = &File::Basename::dirname( $file );
        &Common::File::create_dir_if_not_exists( $dir );

        $state = $defs;

        &Ali::State::save_state( $sid, $input, $state );
    }

    return wantarray ? %{ $state } : $state;
}

sub save_state
{
    # Niels Larsen, October 2004.

    # Writes a given state hash to file under a given user directory.

    my ( $sid,     # User ID 
         $input,   # Alignment name
         $state,   # State hash
         $suffix,  # Suffix appended to name - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $file, $dir );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $input ) {
        &error( qq (Alignment name not given) );
    }

    if ( not $state ) {
        &error( qq (State data hash is not given) );
    }

    $file = "$Common::Config::ses_dir/$sid/$input".".state";
    $file .= "$suffix" if defined $suffix;

    $dir = &File::Basename::dirname( $file );

    if ( -d $dir ) {
        &Common::File::store_file( $file, $state );
    } else {
        &error( qq (Directory does not exist -> "$dir") );
    }
    
    return;
}

sub split_dataloc
{
    my ( $loc,
        ) = @_;

    my ( $name, $file );

    if ( $loc =~ /^([^:\.]+):([^:\.]+)$/ ) 
    {
        ( $name, $file ) = ( $1, $2 );
    }
    else {
        &error( qq (Wrong looking data locator string -> "$loc") );
    }

    return ( $name, $file );
}

1;

__END__
