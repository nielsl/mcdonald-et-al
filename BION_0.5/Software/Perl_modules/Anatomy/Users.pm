package Anatomy::Users;     #  -*- perl -*-

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

    my ( $db,        # Database prefix
         ) = @_;

    # Returns a hash.

    my ( $state );

    $state = {
        "version" => 1,
        "request" => "",
        "ana_click_id" => "",
        "ana_col_index" => undef,
        "ana_col_ids" => [],
        "ana_css_class" => "anatomy",
        "ana_info_index" => undef,
        "ana_info_key" => "",
        "ana_info_menu" => "",
        "ana_info_ids" => [],
        "ana_info_tip" => "",
        "ana_info_col" => "",
        "ana_info_type" => "",
        "ana_parents_menu" => [],
        "ana_root_id" => undef,
        "ana_report_id" => undef,
        "ana_root_name" => "", 
        "ana_row_ids" => [],
        "ana_search_id" => 1,
        "ana_search_text" => "",
        "ana_search_target" => "titles",
        "ana_search_type" => "partial_words",
        "ana_terms_title" => "",
        "ana_delete_cols_button" => 0,
        "ana_delete_rows_button" => 0,
        "ana_compare_cols_button" => 0,
        "ana_cols_checkboxes" => 0,
        "ana_save_rows_button" => 0,
        "ana_with_form" => 1,
        "ana_hide_widget" => "",
        "ana_show_widget" => "",
        "ana_control_menu" => undef,
        "ana_data_menu" => undef,
        "ana_statistics_menu" => undef,
        "ana_selections_menu" => undef,
    };

    if ( $db eq "po" )
    {
        $state->{"ana_root_id"} = 9075;
        $state->{"ana_root_name"} = "Plant anatomy";
    } 
    elsif ( $db eq "flyo" )
    {
        $state->{"ana_root_id"} = 1;
        $state->{"ana_root_name"} = "Drosophila anatomy";
    } 
    elsif ( $db eq "mao" )
    {
        $state->{"ana_root_id"} = 2405;
        $state->{"ana_root_name"} = "Mouse anatomy";
    } 
    elsif ( $db eq "mado" )
    {
        $state->{"ana_root_id"} = 1;
        $state->{"ana_root_name"} = "Mouse anatomy (embryo)";
    } 
    else
    {
        &error( qq (Unrecognized database prefix -> "$db") );
        exit;
    }

    return wantarray ? %{ $state } : $state;
}

sub add_selection
{
    # Niels Larsen, October 2004.

    # Add one information hash to saved selections under a 
    # users directory. If no index is given, the hash is 
    # appended.

    my ( $sid,      # Session id
         $db,       # Database prefix
         $info,     # Information hash
         $index,    # Insert offset - OPTIONAL (default last)
         ) = @_;

    # Returns the resulting list. 

    my ( $list, $file );

    $file = $db."_selections";
    
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
         $db,       # Database prefix
         $index,    # Index - OPTIONAL
         ) = @_;

    # Returns resulting list or nothing if empty.

    my ( $file, $list );

    $file = $db."_selections";

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
    # $db."_info_*". If keys are missing defaults are added. 

    my ( $dbh,       # Database handle
         $db,        # Database prefix
         $state,     # State hash
         ) = @_;

    # Returns an array.

    my ( $type, $key, $menu, $col, $tip, $ids, $node, @name, $name,
         $i, $select, $id, $selection );
    
    $type = defined $state->{"ana_info_type"} ? $state->{"ana_info_type"} : $db;
    $key = defined $state->{"ana_info_key"} ? $state->{"ana_info_key"} : "";
    $menu = defined $state->{"ana_info_menu"} ? $state->{"ana_info_menu"} : "";
    $col = defined $state->{"ana_info_col"} ? $state->{"ana_info_col"} : "";
    $tip = defined $state->{"ana_info_tip"} ? $state->{"ana_info_tip"} : "Selects one or more categories.";
    $ids = defined $state->{"ana_info_ids"} ? $state->{"ana_info_ids"} : [];
    $id = defined $state->{"ana_info_index"} ? $state->{"ana_info_index"} : "";

    if ( not $key ) {
        &error( qq (Anatomy info key must be given) );
        exit;
    }
    
    if ( scalar @{ $ids } == 1 )
    {
        $select = qq ($db."_def".$db."_id,".$db."_def.name");
        $node = &Anatomy::DB::get_node( $dbh, $ids->[0], $select );
        
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
        $menu = "Selected Anatomy terms" if not $menu;
        $col = "Anatomy" if not $col;
    }
    
    if ( $key eq $db."_terms_tsum" or $key eq $db."_terms_usum" ) {
        $tip = qq (The number of categories under the $menu category.);
    } 
    
    $selection = 
    {
        "type" => $type,
        "key" => $key,
        "menu" => $menu,
        "col" => $col,
        "tip" => $tip,
        "ids" => $ids,
    };
    
    if ( not $selection ) 
    {
        &error( qq (Selection info hash could not be made from state information) );
        exit;
    }
        
    return wantarray ? %{ $selection } : $selection;
}

sub save_selections
{
    # Niels Larsen, October 2004.

    # Saves a given selection list of a given type in a given 
    # users area. 

    my ( $sid,     # User id
         $db,      # Database prefix
         $list,    # List of selections
         ) = @_;

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/".$db."_selections";

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
         $db,      # Database prefix, e.g. "po"
         $defs,    # State defaults
         ) = @_;

    # Returns a hash.

    if ( not $sid ) {
        &error( qq (Session ID is not given) );
    }

    if ( not $defs ) {
        $defs = &Anatomy::Users::default_state( $db );
    }

    my ( $defaults, $file, $state );

    $file = "$Common::Config::ses_dir/$sid/".$db.".state";

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
         $db,      # Database prefix
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

    $file = "$Common::Config::ses_dir/$sid/".$db.".state";

    if ( -d "$Common::Config::ses_dir/$sid" ) {
        &Common::File::dump_file( $file, $state );
    } else {
        &error( qq (Directory does not exist -> "$Common::Config::ses_dir/$sid") );
    }
    
    return;
}


1;

__END__
