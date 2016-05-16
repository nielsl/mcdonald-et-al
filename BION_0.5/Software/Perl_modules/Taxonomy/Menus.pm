package Taxonomy::Menus;     #  -*- perl -*-

# Menu options and functions specific to the taxonomy viewer. 
# Some of the functions write into the users area.

use strict;
use warnings FATAL => qw ( all );

use Storable;
use IO::File;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Users;

use base qw ( Common::Menus Common::Option );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Generates different types of menu structures, and has routines to access
# and manipulate them. Object module. Inherits from Common::Menus.

# control_menu
# data_menu
# results_menu
# selections_menu
# uploads_menu

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub control_menu
{
    # Niels Larsen, October 2006.
    
    # Creates a control menu with basic options that do not depend on the data
    # shown. 

    my ( $class,
         $sid,        # Session id
         $wwwpath,
         ) = @_;

    # Returns a menu object.

    my ( $menu, $options, $option, $inputdb );

    push @{ $options },
    {
        "title" => "IDs with reports",
        "tiptext" => "ID for each organism and taxon - click to get small report.",
        "helptext" => "Inserts a column with ID's that when clicked shows a small organism report.",
        "coltext" => "ID",
        "objtype" => "col_stats",
        "datatype" => "orgs_taxa",
        "request" => "add_ids_column",
    },{
        "title" => "Node counts",
        "tiptext" => "The number of organisms within a given taxon.",
        "helptext" => "Inserts a column with numbers of organisms within each group.",
        "coltext" => "Orgs",
        "objtype" => "col_stats",
        "datatype" => "orgs_taxa",
        "request" => "add_node_counts_column",
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    push @{ $options },
    {
        "title" => "Taxa (none marked)",
        "tiptext" => "Checkboxes, unchecked, for organisms and/or taxonomy groups.",
        "helptext" => "A column of un-checked checkboxes will appear for each taxon. By pressing"
            . " the save button, selections can be saved under a given name. The selections"
            . " made this way will be usable on other pages.",
        "coltext" => "X",
        "objtype" => "checkboxes_unchecked",
        "datatype" => "save_orgs_taxa",
        "request" => "add_unchecked_column",
    },{
        "title" => "Taxa (all marked)",
        "tiptext" => "Checkboxes, checked, for organisms and/or taxonomy groups.",
        "helptext" => "A column of checked checkboxes will appear for each taxon. By pressing"
            . " the save button, selections can be saved under a given name. The selections"
            . " made this way will be usable on other pages.",
        "coltext" => "X",
        "objtype" => "checkboxes_checked",
        "datatype" => "save_orgs_taxa",
        "request" => "add_checked_column",
    };

    # >>>>>>>>>>>>>>>>>>>>>>> DELETE COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    push @{ $options },
    {
        "title" => "Columns (none marked)",
        "tiptext" => "Checkboxes, unchecked, for taxonomy display columns.",
        "helptext" => "A row of unchecked checkboxes will appear above the column titles. By pressing"
            . " the [Delete columns] button, selected columns are removed.",
        "coltext" => "X",
        "objtype" => "checkboxes_unchecked",
        "datatype" => "delete_column",
        "request" => "add_unchecked_row",
    },{
        "title" => "Columns (all marked)",
        "tiptext" => "Checkboxes, checked, for taxonomy display columns.",
        "helptext" => "A row of checked checkboxes will appear above the column titles. By pressing"
            . " the [Delete columns] button, selected columns are removed.",
        "coltext" => "X",
        "objtype" => "checkboxes_checked",
        "datatype" => "delete_column",
        "request" => "add_checked_row",
    };

    $inputdb = ( split "/", $wwwpath )[-1];

    foreach $option ( @{ $options } )
    {
        $option->{"viewer"} = "orgs_viewer";
        $option->{"name"} = "tax_control_menu";
        $option->{"style"} = "menu_item";
        $option->{"inputdb"} = $inputdb;
        $option->{"helptext"} //= "";
    }

    $menu = Common::Menu->new( "options" => $options );

    $menu->title( "Control Menu" );
    $menu->name( "tax_control_menu" );

    $menu->session_id( $sid ) if defined $sid;

    $class = ( ref $class ) || $class;
    bless $menu, $class;    

    return $menu;
}

sub data_menu
{
    # Niels Larsen, October 2005.
    
    # Reads the data menu from file cache in the user session
    # directory. If that doesnt exist it is created from a yaml 
    # file template. 

    my ( $class,      # Class name
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $menu, $options );

    $menu = $class->SUPER::read_menu( "tax_data_menu" );

    $menu->title( "System Data Menu" );
    $menu->name( "tax_data_menu" );
    $menu->session_id( $sid );

    $class = ( ref $class ) || $class;
    bless $menu, $class;    

    return $menu;
}

sub results_menu
{
    # Niels Larsen, December 2005.
    
    # Collects the results that are ready to be displayed. 

    my ( $class,
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $menu, $option );

    $menu = $class->SUPER::results_menu( $sid );

    foreach $option ( $menu->options )
    {
        $option->objtype( "col_sims" );
    }

    $menu->name( "tax_results_menu" );

    $class = ( ref $class ) || $class;
    bless $menu, $class;
    
    return $menu;
}

sub selections_menu
{
    # Niels Larsen, October 2005.
    
    # Reads the selections menu from the user session directory.

    my ( $class,      # Class name
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    $menu = $class->SUPER::selections_menu( $sid );

    $menu->name( "tax_selections_menu" );

    $menu->prune_expr( '$_->datatype eq "orgs_taxa"' );
        
    $class = ( ref $class ) || $class;
    bless $menu, $class;
    
    return $menu;
}

sub uploads_menu
{
    # Niels Larsen, October 2005.
    
    # Reads the uploads menu from the user session directory.

    my ( $class,
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    $menu = $class->SUPER::uploads_menu( $sid );

    $menu->prune_expr( '$_->datatype eq "orgs_taxa"' );
        
    $class = ( ref $class ) || $class;
    bless $menu, $class;
    
    return $menu;
}

sub user_menu
{
    # Niels Larsen, January 2006.

    # Creates a menu of user selections and/or results, if any.
    # Its does this by invoking the selections and results menus
    # and merges them. 

    my ( $class,     
         $sid,       # Session id
         ) = @_;

    # Returns a menu object.    

    my ( $menu, $options, $option );

    foreach $option ( $class->selections_menu( $sid )->options )
    {
        $option->cid( $option->id );
        $option->delete( "id" );
        $option->request( "restore_selection" );
        
        push @{ $options }, $option;
    }

    foreach $option ( $class->results_menu( $sid )->options )
    {
        $option->jid( $option->id );
        $option->delete( "id" );
        $option->request( "add_user_sims_column" );
        
        push @{ $options }, $option;
    }

    $menu = $class->new( "options" => $options );
    $menu->session_id( $sid );

    $menu->name( "tax_user_menu" );
    $menu->objtype( "clipboard" );
    $menu->title( "User Menu" );

    return $menu;
}

sub new_selection
{
    # Niels Larsen, November 2005.

    # Creates a selection option. All tax_row_* keys in the given state
    # are used to fill in values. 

    my ( $class,
         $state,     # State hash
         ) = @_;

    # Returns a hash.

    my ( $option );

    $option = Common::Option->new();

    $option->objtype( "selection" );
    $option->datatype( $state->{"tax_info_type"} || "orgs_taxa" );
    $option->title( $state->{"tax_info_menu"} || "" );
    $option->coltext( $state->{"tax_info_col"} || "" );
    $option->tiptext( $state->{"tax_info_tip"} || "" );
    $option->values( $state->{"tax_row_ids"} || [] );
    $option->count( scalar @{ $state->{"tax_row_ids"} } );
    $option->request( "restore_selection" );

    return $option;
}

1;

__END__

sub new_selection
{
    # Niels Larsen, February 2004.

    # Creates a list of column info hashes from the parameters that comes 
    # from the web form. If fields are missing it makes them up,
    # except the go_col_id field which is created when these new hashes 
    # are added to the existing ones. 

    my ( $dbh,       # Database handle
         $state,     # State hash
         ) = @_;

    # Returns an array.

    require Taxonomy::DB;

    my ( $type, $key, $menu, $col, $tip, $ids, $id, $node, @name, $name,
         $info, $i, $select );
    
    $type = defined $state->{"tax_info_type"} ? $state->{"tax_info_type"} : "taxonomy";
    $key = defined $state->{"tax_info_key"} ? $state->{"tax_info_key"} : "";
    $menu = defined $state->{"tax_info_menu"} ? $state->{"tax_info_menu"} : "";
    $col = defined $state->{"tax_info_col"} ? $state->{"tax_info_col"} : "";
    $tip = defined $state->{"tax_info_tip"} ? $state->{"tax_info_tip"} : "Selects one or more organisms or groups.";
    $ids = defined $state->{"tax_info_ids"} ? $state->{"tax_info_ids"} : [];
    $id = defined $state->{"tax_info_index"} ? $state->{"tax_info_index"} : "";

    if ( not $key ) {
        &error( qq (Key must be given) );
    }
    
    if ( scalar @{ $ids } == 1 )
    {
        $select = qq (tax_id,name);
        $node = &Taxonomy::DB::get_node( $dbh, $ids->[0], $select );
        
        $name = $node->{"name"};
        $name = &Common::Names::format_display_name( $name );
        
        $menu = $name if not $menu;
        
        if ( not $col )
        {
            @name = split " ", $name;
            
            if ( scalar @name > 1 ) {
                $col = ( substr $name[0], 0, 1 ) ."." . ( substr $name[1], 0, 1 ) .".";
            } else {
                $col = ( substr $name[0], 0, 3 );
            }
        }
    }
    else
    {
        $menu = "Selected Organisms" if not $menu;
        $col = "Tax" if not $col;
    }
    
    if ( $key eq "go_terms_tsum" ) {
        $tip = qq (The total number of GO terms that connect to $menu. There may be duplicates.);
    } elsif ( $key eq "go_terms_usum" ) {
        $tip = qq (The number of GO terms that connect to $menu, without duplicates.);
    }
    
    $info = 
    {
        "type" => $type,
        "key" => $key,
        "text" => $menu,
        "col" => $col,
        "tip" => $tip,
        "ids" => $ids,
    };

    if ( not $info ) {
        &error( qq (Column hash could not be generated from state information) );
        exit;
    }

    return wantarray ? %{ $info } : $info;
}

sub create_selections_items
{
    # Niels Larsen, August 2005.

    # Reads the selections from file cache in the user session directory, 
    # takes the organism and function parts, and adds dividers. The 
    # resulting structure is a list suited for menu display. 

    my ( $sid,        # Session id
         ) = @_;

    # Returns a list. 

    my ( $file, $items, @items, $item, %items, %ok_types, @ok_types, $type );

    $file = "$Common::Config::ses_dir/$sid/selections";

    $ok_types{"organisms"} = { "title" => "Organisms", "css" => "blue_menu_divider" };
    $ok_types{"functions"} = { "title" => "Functions", "css" => "orange_menu_divider" };

    @ok_types = ( "organisms", "functions" );

    if ( -r $file )
    {
        $items = &Common::File::eval_file( $file );

        foreach $item ( @{ $items } )
        {
            $type = $item->{"type"};

            if ( exists $ok_types{ $type } ) 
            {
                $item->{"menu"} = "tax_selections_menu";

                push @{ $items{ $type } }, &Storable::dclone( $item );
            }
        }

        foreach $type ( @ok_types )
        {
            if ( exists $items{ $type } )
            {
                push @items, 
                {
                    "id" => "",
                    "type" => "",
                    "key" => "",
                    "text" => $ok_types{ $type }->{"title"},
                    "col" => "",
                    "tip" => "",
                    "class" => $ok_types{ $type }->{"css"},
                    "ids" => [],
                }, 
                @{ $items{ $type } };
            }
        }
    }
    
    if ( @items ) {
        return wantarray ? @items : \@items;
    } else {
        return;
    }
}
