package Query::State;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# State related routines that are not project specific. The project specific
# routines are in sub-modules (sub-directories).
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_viewer_state
                 &default_state
                 &params_to_tuples
                 &restore_state
                 &save_state
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::States;

use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_viewer_state
{
    # Niels Larsen, March 2011.

    # Creates a viewer state that is up to date with CGI values. If a state
    # has been saved previously, then CGI values are merged into that. If not,
    # then a given default state is used. 

    my ( $args,
         $msgs,
         ) = @_;

    # Returns a hash.

    my ( $cgi, $sid, $dataset, $state, $def_state, $sub_menu, $option, 
         $keyname, $valname, $func );

    # Arguments,

    $args = &Registry::Args::check(
        $args,
        {
            "O:2" => [ "cgi" ],
            "S:2" => [ "sid", "dataset", "defstate" ],
        });
    
    $cgi = $args->cgi;
    $sid = $args->sid;
    $dataset = $args->dataset;
    $func = $args->defstate;
    
    # Restore state,

    $state = &Query::State::restore_state( 
        {
            "sid" => $sid,
            "dataset" => $dataset,
            "func" => $func,
        });

    # Get default state,

    {
        no strict "refs";
        $def_state = &{ $func }( $dataset );
    }

    $state = &Common::States::merge_cgi_with_viewer_state( $cgi, $sid, $state, $def_state );

    $keyname = "query_keys";
    $valname = "query_values";

    if ( $state->{ $keyname } and @{ $state->{ $keyname } } and
         $state->{ $valname } and @{ $state->{ $valname } } )
    {
        $state->{"params"} = &Query::State::params_to_tuples( $state->{ $keyname }, $state->{ $valname } );

        delete $state->{ $keyname };
        delete $state->{ $valname };
    }

    return $state;
}

sub default_state
{
    # Niels Larsen, November 2005.

    # Defines default settings for each page or viewer. These defaults
    # are used when new users are created. 

    my ( $dataset,
        ) = @_;

    # Returns a hash.

    my ( $state );

    $state = {
        "dataset" => $dataset,
        "request" => "",
        "version" => 1,
        "upload_datatype" => "",
        "upload_format" => "",
        "upload_coltext" => "",
        "upload_title" => "",
        "upload_page_title" => "",
        "upload_submit_label" => "",
        "params" => [],
        "query_keys" => [],
        "query_values" => [],
        "download_keys" => [],    
        "download_values" => [],
    };

    return wantarray ? %{ $state } : $state;
}

sub params_to_tuples
{
    my ( $keys,
         $vals,
        ) = @_;

    my ( $i, $j, @tuples );

    if ( ( $i = scalar @{ $keys } ) != ( $j = scalar @{ $vals } ) ) {
        &error( qq ($i keys, but $j values) );
    }

    for ( $i = 0; $i <= $#{ $vals }; $i++ )
    {
        push @tuples, [ $keys->[$i], $vals->[$i] ];
    }

    return wantarray ? @tuples : \@tuples;
}

sub restore_state
{
    # Niels Larsen, March 2011.

    # Fetches state information of a given type for a given user. The
    # state is a hash wish keys and values that for example a given viewer
    # knows how to handle. If the state from file has a lower version 
    # number than the current defaults then the defaults are used and
    # they overwrite the saved state.

    my ( $args,     # Arguments hash
         ) = @_;

    # Returns a hash.

    my ( $sid, $dataset, $func, $def_state, $file, $dir, $state );

    # Arguments, 

    $args = &Registry::Args::check(
        $args,
        {
            "S:2" => [ "sid", "dataset", "func" ],
        });
    
    $sid = $args->sid;
    $dataset = $args->dataset;
    $func = $args->func;

    # Get default state,

    {
        no strict "refs";
        $def_state = &{ $func }( $dataset );
    }

    # State file is specific to session and dataset,

    $file = "$Common::Config::ses_dir/$sid/$dataset".".state";

    if ( -r $file )
    {
        # If state file exists, is non-empty and version number is current,
        # then use it. Otherwise use the default state,

        $state = &Common::File::retrieve_file( $file );

        if ( not $state or $state->{"version"} != $def_state->{"version"} )
        {
            $state = $def_state;
            &Common::File::store_file( $file, $state );
        }
    }
    elsif ( -d "$Common::Config::ses_dir/$sid" ) 
    {
        # If session directory exists but no state file, then save the 
        # default,

        $state = $def_state;
        &Query::State::save_state( $sid, $state );
    }
    else {
        &error( qq (Session directory does not exist -> "$Common::Config::ses_dir/$sid") );
    }
    
    return wantarray ? %{ $state } : $state;
}

sub save_state
{
    # Niels Larsen, March 2011.

    # Writes a given state hash to file under a given session directory.

    my ( $sid,     # User ID 
         $state,   # State hash
         ) = @_;

    # Returns a hash.

    my ( $state_file, $state_dir );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $state ) {
        &error( qq (State data hash is not given) );
    }
    
    $state_dir = "$Common::Config::ses_dir/$sid";

    if ( -d $state_dir )
    {
        $state_file = "$state_dir/". $state->{"dataset"} .".state";

        &Common::File::store_file( $state_file, $state );
    }
    else {
        &error( qq (State directory does not exist -> "$state_dir") );
    }

    return;
}

1;

__END__
