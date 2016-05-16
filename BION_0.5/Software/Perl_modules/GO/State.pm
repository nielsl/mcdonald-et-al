package GO::State;     #  -*- perl -*-

# Functions specific to user checking and administration. 

use strict;
use warnings;

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &default_state
                 &merge_cgi_with_viewer_state
                 &restore_state
                 &save_state
                 );

use Common::File;
use Common::Config;
use Common::Messages;
use Common::States;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub default_state
{
    # Niels Larsen, October 2004.

    # Defines default settings for each page or viewer. These defaults
    # are used when new users are created. 

    # Returns a hash.

    my ( $state );

    $state = {
        "version" => 1,
        "request" => "",
        "go_click_id" => "",
        "go_col_index" => undef,
        "go_col_ids" => [],
        "go_css_class" => "function",
        "go_info_index" => undef,
        "go_info_key" => "",
        "go_info_menu" => "",
        "go_info_ids" => [],
        "go_info_tip" => "",
        "go_info_col" => "",
        "go_info_type" => "",
        "go_parents_menu" => [],
        "go_root_id" => 3674,
        "go_report_id" => undef,
        "go_root_name" => "molecular_function",
        "go_row_ids" => [],
        "go_search_id" => 3674,
        "go_search_text" => "",
        "go_search_target" => "titles",
        "go_search_type" => "partial_words",
        "go_terms_title" => "",
        "go_delete_cols_button" => 0,
        "go_delete_rows_button" => 0,
        "go_compare_cols_button" => 0,
        "go_cols_checkboxes" => 0,
        "go_save_rows_button" => 0,
        "go_with_form" => 1,
        "go_hide_widget" => "",
        "go_show_widget" => "",
        "go_control_menu" => undef,
        "go_data_menu" => undef,
        "go_selections_menu" => undef,
#        "tax_selections_menu" => undef,
#        "tax_selections_menu_open" => 0,
#        "tax_info_type" => undef,
#        "tax_info_key" => undef,
#        "tax_info_ids" => [],
    };

    return wantarray ? %{ $state } : $state;
}

sub merge_cgi_with_viewer_state
{
    my ( $cgi, 
         $sid,
         $input,
         ) = @_;

    my ( $state, $def_state );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }
    
    if ( not $input ) {
        &error( qq (No input is given) );
    }
    
    $state = &GO::State::restore_state( $sid, $input );
    $def_state = &GO::State::default_state();

    $state = &Common::States::merge_cgi_with_viewer_state( $cgi, $sid, $state, $def_state );

    return $state;
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
         $input,
         $defs,    # State defaults - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $defaults, $file, $state, $dir );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $input ) {
        &error( qq (Function name not given) );
    }

    if ( not $defs ) {
        $defs = &GO::State::default_state();
    }

    $file = "$Common::Config::ses_dir/$sid/$input". ".state";

    if ( -r $file )
    {
        $state = &Common::File::eval_file( $file );

        if ( not $state or $state->{"version"} != $defs->{"version"} )
        {
            $state = $defs;
            &Common::File::dump_file( $file, $state );
        }
    }
    elsif ( -d "$Common::Config::ses_dir/$sid" ) 
    {
        $dir = &File::Basename::dirname( $file );

        &Common::File::create_dir_if_not_exists( $dir );

        $state = $defs;
        &GO::State::save_state( $sid, $input, $state );
    }
    else
    {
        &error( qq (Directory does not exist -> "$Common::Config::ses_dir/$sid") );
    }
    
    return wantarray ? %{ $state } : $state;
}

sub save_state
{
    # Niels Larsen, October 2004.

    # Writes a given state hash to file under a given user directory.

    my ( $sid,     # User ID 
         $input,
         $state,   # State hash
         ) = @_;

    # Returns a hash.

    my ( $file, $dir );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $input ) {
        &error( qq (Function name not given) );
    }

    if ( not $state ) {
        &error( qq (State data hash is not given) );
    }

    $file = "$Common::Config::ses_dir/$sid/$input" .".state";

    $dir = &File::Basename::dirname( $file );

    if ( -d $dir ) {
        &Common::File::dump_file( $file, $state );
    } else {
        &error( qq (Directory does not exist -> "$dir") );
    }
    
    return;
}


1;

__END__
