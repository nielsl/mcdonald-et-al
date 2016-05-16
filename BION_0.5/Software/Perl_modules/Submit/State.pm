package Submit::State;     #  -*- perl -*-

# Functions specific to user checking and administration. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &default_state
                 &merge_cgi_with_viewer_state
                 &merge_param_values
                 &param_tuples
                 &restore_method
                 &restore_state
                 &save_method_params
                 &save_state
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::States;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub default_state
{
    # Niels Larsen, November 2005.

    # Defines default settings for each page or viewer. These defaults
    # are used when new users are created. 

    # Returns a hash.

    my ( $state );

    $state = {
        "request" => "",
        "version" => 1,
        "upload_datatype" => "",
        "upload_format" => "",
        "upload_coltext" => "",
        "upload_title" => "",
        "upload_page_title" => "",
        "upload_submit_label" => "",
        "job_id" => undef,
        "clipboard_id" => undef,
        "clipboard_method" => undef,
        "clip_params_keys" => [],
        "clip_params_values" => [],
    };

    return wantarray ? %{ $state } : $state;
}

sub merge_cgi_with_viewer_state
{
    # Niels Larsen, November 2005.

    # Updates the state hash with new values of its keys, if any,
    # from a given CGI.pm object. If there is no request in $cgi and
    # the navigation menu is given, then a default is set. 

    my ( $cgi,           # CGI.pm object
         $sid,           # Session id
         ) = @_;

    # Returns a hash.

    my ( $state, $def_state, $sub_menu, $option, $keyname, $valname );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }
    
    $state = &Submit::State::restore_state( $sid );
    $def_state = &Submit::State::default_state();

    $state = &Common::States::merge_cgi_with_viewer_state( $cgi, $sid, $state, $def_state );

    $keyname = "mc_query_keys";
    $valname = "mc_query_values";

    if ( $state->{ $keyname } and @{ $state->{ $keyname } } and
         $state->{ $valname } and @{ $state->{ $valname } } )
    {
        $state->{"mc_params"} = &Submit::Viewer::params_to_tuples( $state->{ $keyname }, $state->{ $valname } );
        delete $state->{ $keyname };
        delete $state->{ $valname };
    }

    return $state;
}

sub merge_param_values
{
    # Niels Larsen, April 2007.

    # Accepts a method (or method name) plus a list of parameter tuples
    # and sets the corresponding values in the method parameter structure.
    # The updated method structure is returned.

    my ( $method,       # Method name or object
         $hash,         # Hash of plain key/value
         ) = @_;

    # Returns a method object.

    my ( $value, $opt, $type );

    if ( not ref $method ) {
        $method = Registry::Get->method_max( $method );
    }

    foreach $type ( qw ( pre_params params post_params ) )
    {
        if ( $method->$type )
        {
            foreach $opt ( $method->$type->values->options )
            {
                if ( defined ( $value = $hash->{ $opt->name } ) )
                {
                    $opt->value( $value );
                }
            }
        }
    }
            
    return $method;
}

sub param_tuples
{
    # Niels Larsen, April 2007.

    # Returns the parameters of a given method in the simplest form:
    # a list of [ key, value ]. 

    my ( $method,       # Method name or object
         $args,         # Arguments hash - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $params, $key, $value, $menu, @tuples );

#     $method = Registry::Get->method_max( $method )
    if ( ref $method ) {
        $params = $method->params;
    } else {
        $params = Registry::Get->method_max( $method )->params;
    }

    if ( $menu = $params->values )
    {
        if ( $args ) {
            push @tuples, map { [ $_->name, $_->value ] } @{ $menu->match_options( %{ $args } ) };
        } else {
            push @tuples, map { [ $_->name, $_->value ] } @{ $menu->options };
        }
    }

    return wantarray ? @tuples : \@tuples;
}

sub restore_method
{
    # Niels Larsen, June 2007.

    # Fetches parameter information for a given method and session id.

    my ( $sid,           # Session id
         $method,        # Method name
         $cliprow,       # Clipboard row
         ) = @_;

    # Returns a hash.

    my ( $params, $params_file );

    &error( qq (Method ID not given) ) if not $method;

    if ( $cliprow->params )
    {
        $params = $cliprow->params;
    }
    else
    {
        $params_file = "$Common::Config::ses_dir/$sid/Methods/$method.params";
        $method = Registry::Get->method_max( $method );

        if ( -r $params_file )
        {
            $params = &Common::File::eval_file( $params_file );
        }
#        else
#        {
#            $params = { map { $_->[0], $_->[1] } &Submit::State::param_tuples( $method ) };
#        }
    }
    
    $method = &Submit::State::merge_param_values( $method, $params );
    
    return $method;
}
  
sub restore_state
{
    # Niels Larsen, October 2004.

    # Fetches state information of a given type for a given user. The
    # state is a hash wish keys and values that for example a given viewer
    # knows how to handle. If the state from file has a lower version 
    # number than the current defaults then the defaults are used and
    # they overwrite the saved state.

    my ( $sid,     # User ID 
         $defs,    # State defaults - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $defaults, $file, $dir, $state );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $defs ) {
        $defs = &Submit::State::default_state();
    }

    $file = "$Common::Config::ses_dir/$sid/clipboard".".state";

    if ( -r $file )
    {
        $state = &Common::File::retrieve_file( $file );

        if ( not $state or $state->{"version"} != $defs->{"version"} )
        {
            $state = $defs;
            &Common::File::store_file( $file, $state );
        }
    }
    elsif ( -d "$Common::Config::ses_dir/$sid" ) 
    {
        $dir = &File::Basename::dirname( $file );

        &Common::File::create_dir_if_not_exists( $dir );

        $state = $defs;
        &Submit::State::save_state( $sid, $state );
    }
    else {
        &error( qq (Directory does not exist -> "$Common::Config::ses_dir/$sid") );
    }
    
    return wantarray ? %{ $state } : $state;
}

sub save_method_params
{
    # Niels Larsen, April 2007.

    # Saves the given parameter structure the file
    # 
    # $Common::Config::ses_dir/Methods/$method_name.params
    # 
    # The directory is created if needed and the old file overwritten 
    # if it exists. The name of the file created is returned.

    my ( $name,      # Method name, e.g. "blastn"
         $path,      # Save path 
         $struct,    # Parameters structure
         ) = @_;

    # Returns a string.

    my ( $dir, $file );

    &error( qq (Method name is not given) ) if not $name;
    &error( qq (Path is not given) ) if not $path;
    &error( qq (Parameters structure is not given) ) if not $struct;

    $dir = "$Common::Config::ses_dir/$path";
    &Common::File::create_dir_if_not_exists( $dir );

    $file = "$dir/$name.params";
    &Common::File::delete_file_if_exists( $file );
    
    &Common::File::dump_file( $file, $struct );

    return $file;
}

sub save_state
{
    # Niels Larsen, October 2004.

    # Writes a given state hash to file under a given user directory.

    my ( $sid,     # User ID 
         $state,   # State hash
         ) = @_;

    # Returns a hash.

    my ( $file, $dir );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $state ) {
        &error( qq (State data hash is not given) );
    }

    $file = "$Common::Config::ses_dir/$sid/clipboard".".state";

    $dir = &File::Basename::dirname( $file );

    if ( -d $dir ) {
        &Common::File::store_file( $file, $state );
    } else {
        &error( qq (Directory does not exist -> "$dir") );
    }

    return;
}


1;

__END__
