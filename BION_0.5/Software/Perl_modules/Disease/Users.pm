package Disease::Users;     #  -*- perl -*-

# Functions specific to user checking and administration. 

use strict;
use warnings;

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &default_state
                 &restore_state
                 &save_state
                 &add_selection
                 &delete_selection
                 &new_selection
                 );

use Common::Users;
use Common::File;
use Common::Config;
use Common::Messages;
use Common::Names;

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
        "do_click_id" => "",
        "do_col_index" => undef,
        "do_col_ids" => [],
        "do_css_class" => "disease",
        "do_info_index" => undef,
        "do_info_key" => "",
        "do_info_menu" => "",
        "do_info_ids" => [],
        "do_info_tip" => "",
        "do_info_col" => "",
        "do_info_type" => "",
        "do_parents_menu" => [],
        "do_root_id" => 1,
        "do_report_id" => undef,
        "do_root_name" => "Medical Disorder or Disease",
        "do_row_ids" => [],
        "do_search_id" => 1,
        "do_search_text" => "",
        "do_search_target" => "titles",
        "do_search_type" => "partial_words",
        "do_terms_title" => "",
        "do_delete_cols_button" => 0,
        "do_delete_rows_button" => 0,
        "do_compare_cols_button" => 0,
        "do_cols_checkboxes" => 0,
        "do_save_rows_button" => 0,
        "do_with_form" => 1,
        "do_hide_widget" => "",
        "do_show_widget" => "",
        "do_control_menu" => undef,
        "do_data_menu" => undef,
        "do_statistics_menu" => undef,
        "do_selections_menu" => undef,
    };

    return wantarray ? %{ $state } : $state;
}

sub add_selection
{
    # Niels Larsen, October 2004.

    # Add one information hash to saved selections under a 
    # users directory. If no index is given, the hash is 
    # appended.

    my ( $sid,      # Session id
         $info,     # Information hash
         $index,    # Insert offset - OPTIONAL (default last)
         ) = @_;

    # Returns the resulting list. 

    my ( $list, $file );

    $file = "do_selections";
    
    $list = &Common::Users::savings_add( $sid, $file, $info, $index );

    return wantarray ? @{ $list } : $list;
}

sub delete_selection
{
    # Niels Larsen, October 2004. 
    
    # Deletes a selection from the selections file under a 
    # given user area. If no index is given, the last selection is 
    # deleted. 

    my ( $sid,      # Session id
         $index,    # Index - OPTIONAL
         ) = @_;

    # Returns resulting list or nothing if empty.

    my ( $file, $list );

    $file = "do_selections";

    $list = &Common::Users::savings_delete( $sid, $file, $index );

    if ( $list ) {
        return wantarray ? @{ $list } : $list;
    } else {
        return;
    }

    return;
}

sub new_selection
{
    # Niels Larsen, October 2004.

    # Creates an information hash from the state keys that start with 
    # "do_info_". If keys are missing defaults are added. 

    my ( $dbh,       # Database handle
         $state,     # State hash
         ) = @_;

    # Returns an array.

    my ( $type, $key, $menu, $col, $tip, $ids, $node, @name, $name,
         $info, $i, $select, $id );
    
    $type = defined $state->{"do_info_type"} ? $state->{"do_info_type"} : "do";
    $key = defined $state->{"do_info_key"} ? $state->{"do_info_key"} : "";
    $menu = defined $state->{"do_info_menu"} ? $state->{"do_info_menu"} : "";
    $col = defined $state->{"do_info_col"} ? $state->{"do_info_col"} : "";
    $tip = defined $state->{"do_info_tip"} ? $state->{"do_info_tip"} : "Selects one or more categories.";
    $ids = defined $state->{"do_info_ids"} ? $state->{"do_info_ids"} : [];
    $id = defined $state->{"do_info_index"} ? $state->{"do_info_index"} : "";

    if ( not $key ) {
        &error( qq (Disease info key must be given) );
        exit;
    }
    
    if ( scalar @{ $ids } == 1 )
    {
        $select = qq (do_def.do_id,do_def.name);
        $node = &Disease::DB::get_node( $dbh, $ids->[0], $select );
        
        $name = $node->{"name"};
        $name = &Common::Names::format_display_name( $name );
        
        $menu = $name if not $menu;
        
        if ( not $col )
        {
            @name = split " ", $name;
            
            if ( scalar @name > 1 ) {
                $col = ( substr $name[0], 0, 1 ) ."." . ( substr $name[1], 0, 1 ) .".";
            } else {
                $col = ( substr $name[0], 0, 3 ) .".";
            }
        }
    }
    else
    {
        $menu = "Selected Disease terms" if not $menu;
        $col = "Disease" if not $col;
    }
    
    if ( $key eq "do_terms_tsum" or $key eq "do_terms_usum" ) {
        $tip = qq (The number of categories under the $menu category.);
    } 
    
    $info = 
    {
        "type" => $type,
        "key" => $key,
        "menu" => $menu,
        "col" => $col,
        "tip" => $tip,
        "ids" => $ids,
    };
    
    if ( not $info ) 
    {
        &error( qq (Info hash could not be generated from state information) );
        exit;
    }
        
    return wantarray ? %{ $info } : $info;
}

sub save_selections
{
    # Niels Larsen, October 2004.

    # Saves a given selection list of a given type in a given 
    # users area. 

    my ( $sid,     # User id
         $list,    # List of selections
         ) = @_;

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/do_selections";

    &Common::File::dump_file( $file, $list );
    
    return;
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

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $defs ) {
        $defs = &Disease::Users::default_state();
    }

    my ( $defaults, $file, $state );

    $file = "$Common::Config::ses_dir/$sid/do_state";

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
        $state = $defs;
        &Common::File::dump_file( $file, $state );
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
         $state,   # State hash
         ) = @_;

    # Returns a hash.

    my ( $file );

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $state ) {
        &error( qq (State data hash is not given) );
    }

    $file = "$Common::Config::ses_dir/$sid/do_state";

    if ( -d "$Common::Config::ses_dir/$sid" ) {
        &Common::File::dump_file( $file, $state );
    } else {
        &error( qq (Directory does not exist -> "$Common::Config::ses_dir/$sid") );
    }
    
    return;
}


1;

__END__
