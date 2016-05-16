package Taxonomy::State;     #  -*- perl -*-

# Functions specific to user checking and administration. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &merge_cgi_with_viewer_state
                 &default_state
                 &restore_state
                 &save_state
                 );

use Common::Config;
use Common::Messages;

use Common::States;
use Common::File;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub merge_cgi_with_viewer_state
{
    my ( $cgi, 
         $sid,
         $input,
         ) = @_;

    my ( $state, $def_state );

    &error( qq (Session ID is not given) ) if not $sid;
    &error( qq (No input is given) ) if not $input;
    
    $state = &Taxonomy::State::restore_state( $sid, $input );
    $def_state = &Taxonomy::State::default_state( $input );

    $state = &Common::States::merge_cgi_with_viewer_state( $cgi, $sid, $state, $def_state );
    
    $state->{"inputdb"} = $input;

    return $state;
}

sub default_state
{
    # Niels Larsen, October 2004.

    # Defines default settings for each page or viewer. These defaults
    # are used when new users are created. 

    # Returns a hash.

    my ( $state );

    $state = {
        "version" => 3,
        "request" => "",
        "tax_click_id" => "",
        "tax_col_ids" => [],
        "tax_col_key" => "",
        "tax_col_index" => undef,
        "tax_css_class" => "orgs_viewer",
        "tax_has_results" => "",
        "tax_has_selections" => "",
        "tax_has_uploads" => "",
        "tax_info_index" => undef,
        "tax_info_key" => "",
        "tax_info_menu" => "",
        "tax_info_ids" => [],
        "tax_info_tip" => "",
        "tax_info_col" => "",
        "tax_info_type" => "",
        "tax_orgs_menu" => "",
        "tax_orgs_title" => "",
        "tax_orgs_key" => "",
        "tax_parents_menu" => [],
        "tax_report_id" => undef,
        "tax_root_id" => 2,
        "tax_root_name" => "Bacteria",
        "tax_row_ids" => [],
        "tax_search_id" => 2,
        "tax_search_target" => "scientific_names",
        "tax_search_text" => "",
        "tax_search_type" => "partial_words",
        "tax_inputdb" => "",
        "tax_with_footer" => 0,
        "tax_with_header" => 0,
        "tax_with_col_checkboxes" => 0,
        "tax_hide_widget" => "",
        "tax_show_widget" => "",
        "tax_control_menu" => undef,
        "tax_control_menu_open" => 1,
        "tax_data_menu" => undef,
        "tax_user_menu" => undef,
        "tax_selections_menu" => undef,
        "tax_uploads_menu" => undef,
        "tax_www_dir" => "",
        "tax_viewer_name" => "orgs_viewer",
        "go_selections_menu" => undef,
        "go_selections_menu_open" => 0,
        "go_info_type" => undef,
        "go_info_key" => undef,
        "go_info_ids" => [],
    };

    return wantarray ? %{ $state } : $state;
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

    my ( $defaults, $file, $dir, $state );

    &error( qq (Session ID is not given) ) if not $sid;
    &error( qq (Taxonomy name not given) ) if not $input;

    if ( not $defs ) {
        $defs = &Taxonomy::State::default_state();
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
    elsif ( -d "$Common::Config::ses_dir/$sid" ) 
    {
        $dir = &File::Basename::dirname( $file );

        &Common::File::create_dir_if_not_exists( $dir );

        $state = $defs;
        &Taxonomy::State::save_state( $sid, $input, $state );
    }
    else {
        &error( qq (Directory does not exist -> "$Common::Config::ses_dir/$sid") );
    }
    
    return wantarray ? %{ $state } : $state;
}

sub save_state
{
    # Niels Larsen, October 2004.

    # Writes a given state hash to file under a given user directory.

    my ( $sid,     # User ID 
         $input,   # Taxonomy name
         $state,   # State hash
         ) = @_;

    # Returns a hash.

    my ( $file, $dir );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $input ) {
        &error( qq (Taxonomy name not given) );
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
