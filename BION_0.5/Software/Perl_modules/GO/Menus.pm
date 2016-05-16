package GO::Menus;     #  -*- perl -*-

# Menu options and functions that have to do with the GO viewer.
# Some of the functions read and write into the users area.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_selection
                 &create_column_items
                 &create_control_items
                 &create_data_items
                 &create_selections_items
                 &delete_selection
                 &new_selection
                 &save_selections
                 &selections_items
                  );

use Common::Config;
use Common::Messages;
use Common::File;
use Common::Users;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_selection
{
    # Niels Larsen, February 2004.

    # Add one information hash to saved GO selections under a 
    # users directory. 

    my ( $sid,      # Session id
         $info,     # Information hash
         $index,    # Insert offset, OPTIONAL
         ) = @_;

    # Returns the resulting list. 

    my ( $list, $file );

    $file = "go_selections";
    
    $list = &Common::Users::savings_add( $sid, $file, $info, $index );

    return wantarray ? @{ $list } : $list;
}

sub create_column_items
{
    # Niels Larsen, September 2005.

    # Reads the control menu from file cache in the user session
    # directory. If that doesnt exist it is created from the yaml 
    # file template in WWW-root/(project)/go_columns. 

    my ( $sid,        # Session id
         ) = @_;

    # Returns a list. 

    my ( $ses_dir, $site_dir, $template, $cache, $items, $item );

    $ses_dir = "$Common::Config::ses_dir/$sid";
    $cache = "$ses_dir/go_columns";

    if ( not -r $cache )
    {
        $site_dir = $Common::Config::site_dir;
        $template = "$Common::Config::www_dir/$site_dir/go_columns.yaml";

        $items = &Common::File::read_yaml( $template );

        &Common::File::store_file( $cache, $items );
    }

    $items = &Common::File::retrieve_file( $cache );
    
    foreach $item ( @{ $items } )
    {
        $item->{"tip"} .= qq ( Click on this header to delete the column.);
        $item->{"menu"} = "go_data_menu";
    }
    
    @{ $items } = &Common::Menus::set_items_ids( $items );
    
    return $items;
}

sub create_control_items
{
    # Niels Larsen, September 2005.

    # Reads the control menu from file cache in the user session
    # directory. If that doesnt exist it is created from the yaml 
    # file template in WWW-root/(project)/go_control_menu. 

    my ( $sid,        # Session id
         ) = @_;

    # Returns a list. 

    my ( $ses_dir, $site_dir, $template, $cache, $items, $item );

    $ses_dir = "$Common::Config::ses_dir/$sid";
    $cache = "$ses_dir/go_control_menu";

    if ( not -r $cache )
    {
        $site_dir = $Common::Config::site_dir;
        $template = "$Common::Config::www_dir/$site_dir/go_control_menu.yaml";

        $items = &Common::File::read_yaml( $template );

        &Common::File::store_file( $cache, $items );
    }

    $items = &Common::File::retrieve_file( $cache );
    
    foreach $item ( @{ $items } )
    {
        $item->{"tip"} .= qq ( Click on this header to delete the column.);
        $item->{"menu"} = "go_control_menu";
    }
    
    @{ $items } = &Common::Menus::set_items_ids( $items );
    
    return $items;
}

sub create_data_items
{
    # Niels Larsen, September 2005.

    # Reads the data menu from file cache in the user session
    # directory and adds options if something has been selected 
    # or uploaded. If the data menu cache doesnt exist in the 
    # user session area then it is created from the yaml file 
    # template in WWW-root/(project)/go_data_menu. 

    my ( $sid,        # Session id
         ) = @_;

    # Returns a list. 

    my ( $site_dir, $ses_dir, $template, $cache, $items, $item, 
         $group, @items );

    # >>>>>>>>>>>>>>>>>>> GET STATIC OPTIONS <<<<<<<<<<<<<<<<<<<<<<<<

    # These are the menu options that are always there, 

    $ses_dir = "$Common::Config::ses_dir/$sid";
    $cache = "$ses_dir/go_data_menu";

    if ( not -r $cache )
    {
        $site_dir = $Common::Config::site_dir;
        $template = "$Common::Config::www_dir/$site_dir/go_data_menu.yaml";

        $items = &Common::File::read_yaml( $template );
        &Common::File::store_file( $cache, $items );
    }

    $items = &Common::File::retrieve_file( $cache );

    # >>>>>>>>>>>>>>>>>>>> ADD DYNAMIC OPTIONS <<<<<<<<<<<<<<<<<<<<<<<

    # RNA uploads,

#     if ( -d "$ses_dir/Uploads/RNA" )
#     {
#         push @{ $items }, 
#         {
#             "type" => "uploads",
#             "key" => "rna",
#             "request" => "show_uploads_menu",
#             "text" => "Uploaded sequence",
#             "col" => "",
#             "tip" => "",
#             "class" => "menu_item",
#         };
#     }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> FLATTEN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $group ( "organisms", "dna", "rna", "functions", "protein" )
    {
        if ( exists $items->{ $group } )
        {
            foreach $item ( @{ $items->{ $group } } )
            {
                $item->{"type"} = $group;
                push @items, $item;
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>> ADD IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $item ( @items )
    {
        $item->{"menu"} = "go_data_menu";
        
        if ( $item->{"tip"} ) {
            $item->{"tip"} .= " Click this title to delete the column.";
        }
    }

    @items = &Common::Menus::set_items_ids( \@items );

    return wantarray ? @items : \@items;
}

sub create_selections_items
{
    # Niels Larsen, September 2005.

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
                $item->{"menu"} = "go_selections_menu";

                if ( $item->{"tip"} ) {
                    $item->{"tip"} .= " Click this title to delete the column.";
                }
                
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

sub delete_selection
{
    # Niels Larsen, February 2004. 
    
    # Deletes a selection from the GO selections file under a 
    # given user area. If no index is given, the last selection is 
    # deleted. 

    my ( $sid,      # Session id
         $index,    # Index - OPTIONAL
         ) = @_;

    # Returns resulting list or nothing if empty.

    my ( $file, $list );

    $file = "go_selections";

    $list = &Common::Users::savings_delete( $sid, $file, $index );

    if ( $list ) {
        return wantarray ? @{ $list } : $list;
    } else {
        return;
    }

    return;
}

sub new_item
{
    # Niels Larsen, February 2004.

    # Creates a functions item hash. All go_row_* keys in the given state
    # are used to fill in values. 

    my ( $state,     # State hash
         ) = @_;

    # Returns a hash.

    my ( $item );

    $item =
    {
        "type" => "functions",
        "key" => "selection",
        "text" => "",
        "col" => "",
        "tip" => "",
        "ids" => [],
    };

    if ( $state->{"go_info_type"} ) {
        $item->{"type"} = $state->{"go_info_type"};
    }

    if ( $state->{"go_info_key"} ) {
        $item->{"key"} = $state->{"go_info_key"};
    }

    if ( $state->{"go_info_menu"} ) {
        $item->{"text"} = $state->{"go_info_menu"};
    }

    if ( $state->{"go_info_col"} ) {
        $item->{"col"} = $state->{"go_info_col"};
    }

    if ( $state->{"go_info_tip"} ) {
        $item->{"tip"} = $state->{"go_info_tip"};
    }

    if ( $state->{"go_row_ids"} and @{ $state->{"go_row_ids"} } ) {
        $item->{"ids"} = $state->{"go_row_ids"};
    }

    return wantarray ? %{ $item } : $item;
}

sub new_selection
{
    # Niels Larsen, February 2004.

    # Creates an information hash from the state keys that start with 
    # "go_info_". If keys are missing some defaults are added, others 
    # c

    my ( $dbh,       # Database handle
         $state,     # State hash
         ) = @_;

    # Returns an array.

    my ( $type, $key, $menu, $col, $tip, $ids, $node, @name, $name,
         $info, $i, $select, $id );
    
    $type = defined $state->{"go_info_type"} ? $state->{"go_info_type"} : "go";
    $key = defined $state->{"go_info_key"} ? $state->{"go_info_key"} : "";
    $menu = defined $state->{"go_info_menu"} ? $state->{"go_info_menu"} : "";
    $col = defined $state->{"go_info_col"} ? $state->{"go_info_col"} : "";
    $tip = defined $state->{"go_info_tip"} ? $state->{"go_info_tip"} : "Selects one or more categories.";
    $ids = defined $state->{"go_info_ids"} ? $state->{"go_info_ids"} : [];
    $id = defined $state->{"go_info_index"} ? $state->{"go_info_index"} : "";

    if ( not $key ) {
        &error( qq (GO info key must be given) );
        exit;
    }
    
#         if ( not @{ $ids } ) 
#         {
#             &error( qq (No GO term ids) );
#             exit;
#         }
        
    if ( scalar @{ $ids } == 1 )
    {
        require GO::DB;
        
        $select = qq (go_def.go_id,go_def.name);
        $node = &GO::DB::get_node( $dbh, $ids->[0], $select );
        
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
        $menu = "Selected GO terms" if not $menu;
        $col = "GO" if not $col;
    }
    
    if ( $key eq "go_terms_tsum" or $key eq "go_terms_usum" ) {
        $tip = qq (The number of organisms that have genes annotated under the $menu category.);
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
    
    if ( not $info ) 
    {
        &error( qq (Info hash could not be generated from state information) );
        exit;
    }
        
    return wantarray ? %{ $info } : $info;
}

sub save_selections
{
    # Niels Larsen, October 2003.

    # Saves a given selection list of a given type in a given 
    # users area. 

    my ( $sid,     # User id
         $list,    # List of selections
         ) = @_;

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/go_selections";

    &Common::File::dump_file( $file, $list );
    
    return;
}

sub selections_items
{
    # Niels Larsen, February 2004.

    # Reads the selections from file into a list of hashes 
    # with keys "title" (value is string) and "ids" (value is 
    # array of ids). 

    my ( $sid,    # User id
         ) = @_;

    # Returns an array. 

    my ( $file, $items, $item );

    if ( not $sid ) {
        &error( qq (User ID is not given) );
    }

    $file = "$Common::Config::ses_dir/$sid/go_selections";

    if ( -r $file )
    {
        $items = &Common::File::eval_file( $file );
    }
    else
    {
        $items = 
            [{
                "col" => "O.d.",
                "text" => "Oocyte differentiation",
                "tip" => "The process by which an immature germ cell becomes a mature female gamete.",
                "ids" => [ 9994 ],
            }];
    }

    foreach $item ( @{ $items } )
    {
        $item->{"type"} = "functions";
        $item->{"key"} = "";
        $item->{"menu"} = "go_selections_menu";
        $item->{"request"} = "restore_terms_selection";
    }

    $items = &Common::Menus::set_items_ids( $items );

    return wantarray ? @{ $items } : $items;
}

1;

__END__
