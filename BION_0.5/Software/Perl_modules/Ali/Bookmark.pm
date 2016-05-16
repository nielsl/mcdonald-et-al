package Ali::Bookmark;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Simple field getters/setters
# ----------------------------
#
# As setters they return an alignment object, as getters whatever the
# item is. All are instance methods. Most are created by the AUTOLOAD
# function below, some are written explicitly. To add a simple getter
# or setter, edit the list below. 

our @Auto_get_setters = qw
    (
     id inputdb project title coltext
     );

our %Auto_get_setters = map { $_, 1 } @Auto_get_setters;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use File::Basename;

use Common::Config;
use Common::Messages;

our $Viewer_name = "array_viewer";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub AUTOLOAD
{
    # Niels Larsen, September 2005.
    
    my ( $self,
         $value,
         ) = @_;

    our $AUTOLOAD;

    my ( $method );
    
    if ( not ref $self ) {
        $self = __PACKAGE__->new();
    }
        
    $AUTOLOAD =~ /::(\w+)$/ and $method = $1;
    
    if ( $Auto_get_setters{ $method } )
    {
        if ( defined $value ) {
             return $self->{ $method } = $value;
         } else {
             return $self->{ $method };
         }
    }
    elsif ( $AUTOLOAD !~ /DESTROY$/ ) {
        &error( qq (Undefined method called -> "$AUTOLOAD") );
    }

    return;
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub new
{
    my ( $class,
         %args,
        ) = @_;

    my ( $self, $key );

    $self = {};

    $class = ( ref $class ) || $class;
    bless $self, $class;
    
    foreach $key ( keys %args )
    {
        if ( $Auto_get_setters{ $key } ) {
            $self->{ $key } = $args{ $key };
        } else {
            &error( qq (Wrong looking key -> "$key") );
        }
    }

    return $self;
}

sub cols
{
    my ( $self,
         $cols,
        ) = @_;

    if ( $cols )
    {
        $self->{"cols"} = &Common::Util::integers_to_eval_str( $cols );
        return $self;
    }
    else {
        $cols = [ eval $self->{"cols"} ];
        return wantarray ? @{ $cols } : $cols;
    }

    return;
}

sub rows
{
    my ( $self,
         $rows,
        ) = @_;

    if ( $rows )
    {
        $self->{"rows"} = &Common::Util::integers_to_eval_str( $rows );
        return $self;
    }
    else {
        $rows = [ eval $self->{"rows"} ];
        return wantarray ? @{ $rows } : $rows;
    }

    return;
}



1;

__END__

sub default_state
{
    # Niels Larsen, October 2004.

    # Defines default settings for each page or viewer. These defaults
    # are used when new users are created. 

    # Returns a hash.

    my ( $state, $viewer );

    use Ali::Common;

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

    $viewer = Registry::Get->viewer( $Viewer_name );
    $state->{"ali_prefs"} = { map { $_->[0], $_->[1] } $viewer->params->values->options };

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
         $input,       # Input data path
         ) = @_;

    # Returns a hash.

    my ( $state, $def_state, $key, $value );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }
    
    if ( not $input ) {
        &error( qq (No input data is given) );
    }
    
    $state = &Ali::State::restore_state( $sid, $input );

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
         $defs,       # State defaults - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $state, $file, $dir, $prefs, $key );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $input ) {
        &error( qq (Alignment name not given) );
    }

    if ( not $defs ) {
        $defs = &Ali::State::default_state();
    }

    $file = "$Common::Config::ses_dir/$sid/$input".".state";

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
