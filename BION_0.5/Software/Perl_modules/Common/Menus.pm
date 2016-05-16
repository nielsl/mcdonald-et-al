package Common::Menus;     #  -*- perl -*-

# Functions that return lists of data, types, users, etc, all things that
# reflect the system. The lists are in the form of menus with items, and 
# the are operated on by the functions in the Common::Menu module. They
# can be used on web-page, but are often used by processing routines as 
# maps. The items can come from file, database or are hardcoded in the 
# Registry::Get module.

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Types;
use Common::Batch;

use base qw ( Registry::Get Registry::Register );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Generates different types of menu structures, and has routines to access
# and manipulate them. Object module. 

# clipboard_menu
# dataset_features
# dataset_methods
# datatype_features
# datatype_menu
# formats_menu
# registered_datasets_menu
# jobs_menu
# navigation_menu
# navigation_menu_analysis
# project_data
# project_methods
# results_menu
# selections_menu
# uploads_menu
# viewer_features

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Def_viewer_style = "beige_menu";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub clipboard_menu
{
    # Niels Larsen, November 2005.
    
    # Reads the clipboard menu from file cache in the user session
    # directory, if it exists.

    my ( $class,      # Class or object name
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $file, $menu, $id, $opt );

    $file = "$Common::Config::ses_dir/$sid/clipboard_menu";

    if ( -r $file ) {
        $menu = &Common::File::retrieve_file( $file );
    } else {
        $menu = $class->new();
    }
    
    $menu->session_id( $sid );

    $menu->name( "clipboard_menu" );
    $menu->objtype( "clipboard" );
    $menu->title( "Clipboard Menu" );

    $menu->onchange( "javascript:handle_menu(this.form.selections_menu,'handle_clipboard_menu')" );
    $menu->css( "grey_menu" );

    return $menu;
}

sub dataset_features
{
    # Niels Larsen, April 2008.

    # Returns a menu of the features that map to the given dataset: all the  
    # features listed for the datasets datatype, minus those that may be 
    # declared by the dataset as unwanted (the $db->exports->skip_features
    # list).

    my ( $class,
         $db,             # Dataset name or object
        ) = @_;

    # Returns a menu object. 

    my ( $menu, $list, $skip, %skip );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }
    
    $list = Registry::Get->type( $db->datatype )->features;

    if ( $db->imports and $skip = $db->imports->skip_features )
    {
        %skip = map { $_, 1 } @{ $skip };
        $list = [ grep { not exists $skip{ $_ } } @{ $list } ];
    }

    $menu = Registry::Get->features( $list );

    $menu->name( "features_menu" );
    $menu->title( "Features Menu" );
    $menu->css( $Def_viewer_style );

    return $menu;
}

sub dataset_methods
{
    # Niels Larsen, April 2008.
    
    # Returns methods that works with the given dataset and its exported types and
    # formats. If a list of methods is given, then candidate methods are taken from 
    # that list instead of just any method. A menu structure is returned.

    my ( $class,
         $db,              # Dataset name or object
         $mets,            # List of method names or objects - OPTIONAL 
        ) = @_;

    # Returns a menu object.

    my ( $menu, %filter, @opts );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }
    
    if ( not $mets ) {
        $mets = Registry::Get->methods()->options_names;
    }

    @opts = Registry::Match->compatible_methods( $mets, [ $db ] );

    $menu = Registry::Get->new(
        "name" => "methods_menu",
        "title" => "Methods Menu",
        "css" => $Def_viewer_style,
        "options" => \@opts,
        );
                                
    return $menu;
}

sub datatype_features
{
    # Niels Larsen, April 2008.

    # Returns a menu of the features that are declared in the registry by the 
    # given datatype.

    my ( $class,
         $type,             # Datatype object or name
        ) = @_;

    # Returns a menu object. 

    my ( $menu );

    if ( not ref $type ) {
        $type = Registry::Get->type( $type );
    }

    $menu = Registry::Get->features( $type->features );

    $menu->name( "features_menu" );
    $menu->title( "Features Menu" );
    $menu->css( $Def_viewer_style );

    return $menu;
}

sub datatype_menu
{
    # Niels Larsen, October 2005.

    # Creates a menu of all datatypes known to the system. 

    my ( $class,       # Class name
         $name,        # Name of menu - OPTIONAL
         $style,       # Style of menu - OPTIONAL
         ) =  @_;

    # Returns a menu object.

    my ( $opts, $opt, $menu );

    $opts = $class->types->options;

    foreach $opt ( @{ $opts } )
    {
        $opt->objtype("datatype");
    }

    $menu = $class->new( "options" => $opts );

    $menu->name( $name || "datatype_menu" );
    $menu->title( "Datatype Menu" );
    $menu->objtype( "datatypes" );
    $menu->css( $style || $Def_viewer_style );

    $class = ( ref $class ) || $class;
    bless $menu, $class;
    
    return $menu;
}

sub formats_menu
{
    # Niels Larsen, October 2005.

    # Creates a menu of all formats known to the system, with lists of 
    # the datatypes they may hold. 

    my ( $class,       # Class name
         $name,        # Name of menu - OPTIONAL
         $style,       # Style of menu - OPTIONAL
         ) =  @_;

    # Returns a menu object.

    my ( $opts, $opt, $menu );

    $opts = $class->formats->options;

    foreach $opt ( @{ $opts } )
    {
        $opt->objtype("format");
    }

    $menu = $class->new( "options" => $opts );

    $menu->name( $name || "formats_menu" );
    $menu->title( "Formats Menu" );
    $menu->objtype( "formats" );
    $menu->css( $style || $Def_viewer_style );

    $class = ( ref $class ) || $class;
    bless $menu, $class;
    
    return $menu;
}

sub registered_datasets_menu
{
    # Niels Larsen, March 2008.

    # Reads the "installed_data" file in the Admin directory and returns
    # a menu with option objects. 

    # Returns a Common::Menu object.

    my ( $list, $menu );

    $list = Registry::Register->registered_datasets;

    $menu = Registry::Get->datasets;
    $menu->match_options( "name" => $list );

    $menu->title( "Data installed" );
    $menu->name( "registered_datasets" );

    return $menu;
}

sub jobs_menu
{
    # Niels Larsen, December 2005.
    
    # Builds a menu structure from the batch queue table and returns it.
    # If a session id is given, only jobs for that id is included. 

    my ( $class,      # Class or object name
         $sid,        # Session id - OPTIONAL
         $fields,     # List of fields - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $jobs, $menu, $opts, $opt, $job, $i, $field, $value );

    if ( not defined $fields )
    {
        $fields = [ "id", "cid", "pid", "title", "coltext", "method", "input_type", 
                    "serverdb", "status", "sub_time", "beg_time", "end_time", 
                    "message" ];
    }

    # Name etc,

    $menu = $class->new();

    $menu->name( "jobs_menu" );
    $menu->title( "Batch Jobs" );
    $menu->css( "grey_menu" );

    $menu->session_id( $sid ) if defined $sid;

    # Options,

    $jobs = &Common::Batch::list_queue( $sid, $fields, "batch_queue" );

    foreach $job ( @{ $jobs } )
    {
        $opt = Common::Option->new();

        for ( $i = 0; $i <= $#{ $fields }; $i++ )
        {
            $field = $fields->[$i];
            $value = $job->[$i];

            $opt->$field( $value );
        }

        $opt->objtype("job");

        push @{ $opts }, $opt;
    }

    $menu->options( $opts );

    return $menu;
}

sub navigation_menu
{
    # Niels Larsen, October 2005. 

    # TODO: this is a tricky and rather messy routine written at a time where 
    # where were no portable Javascript libraries, or good MVC frameworks like 
    # like Perl Dancer. It can be done much simpler now.
    # 
    # Uses the state to create a navigation menu structure that the display can 
    # render. The project specific submenus are read from files in subdirectories,
    # as CMS systems do. Global submenus like "Upload", "Analysis", "Login" etc 
    # are hardcoded. The routine returns a navigation menu, but also makes sure
    # the keys "menu_1", "menu_2" and "menu_3" are always set in the system state. 
    # 
    # Data structure
    # --------------
    # It is a menu object, as created by Common::Menu->new, with a list of 
    # options. Each option can be of Common::Option or Common::Menu type, in 
    # which case there is a submenu. The rendering routines know how to navigate
    # that structure. 
    # 
    # Tabbed browsing
    # ---------------
    # This routine keeps track of which menu_1/menu_2/menu_3 options have been 
    # visited and fills them in unless given explicitly. The effect is that the
    # user can "flip-flop" between different menu_1 options and see data that 
    # were chosen with menu_2 or menu_3. 

    my ( $class,       # Class name
         $site,        # Site name like "RNA"
         $state,       # System state hash
         ) = @_;

    # Returns a Common::Menu object.

    my ( $visits, $sid, $visits_1, $menu_1, $menu_2, $id_1, $id_2, 
         $dir_1, $dir_2, $dir_3, %hash, $hash, @opts_1, @opts_2,
         $opt_1, $opt_2, $opt_3, 
         $i, $j, $nav_click );

    if ( not $site ) {
        &Common::Messages::error( qq (No project directory given) );
    }

    if ( not $state ) {
        &Common::Messages::error( qq (No state given) );
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> REMEMBER VISITS <<<<<<<<<<<<<<<<<<<<<<<<<<<<< 

    $visits = $state->{"menu_visits"};

    $nav_click = { split ":", $state->{"menu_click"} || "" };

    if ( $nav_click->{"menu_1"} )
    {
        # If menu_1 selected then record it and use the menu_2 and menu_3 that 
        # were followed previously, if any, otherwise leave blank and they will
        # be generated below,

        $state->{"sys_menu_1"} = $nav_click->{"menu_1"};

        if ( $visits->{ $state->{"sys_menu_1"} } )
        {
            $visits_1 = $visits->{ $state->{"sys_menu_1"} };
            $state->{"sys_menu_2"} = $visits_1->[0];

            if ( exists $visits_1->[1] and 
                 exists $visits_1->[1]->{ $state->{"sys_menu_2"} } ) {
                $state->{"inputdb"} = $visits_1->[1]->{ $state->{"sys_menu_2"} };
            } else {
                $state->{"inputdb"} = "";
            }
        }
        else {
            $state->{"sys_menu_2"} = "";
            $state->{"inputdb"} = "";
        }
    }
    elsif ( $nav_click->{"menu_2"} )
    {
        # If menu_2 selected then record it and use the menu_3 that was used 
        # previously, if any, otherwise leave blank and it will be generated 
        # below. When getting here, we know sys_menu_1 is set,

        $state->{"sys_menu_2"} = $nav_click->{"menu_2"};
        $visits_1 = $visits->{ $state->{"sys_menu_1"} };
        
        if ( exists $visits_1->[1] and 
             exists $visits_1->[1]->{ $state->{"sys_menu_2"} } ) {
            $state->{"inputdb"} = $visits_1->[1]->{ $state->{"sys_menu_2"} };
        } else {
            $state->{"inputdb"} = "";
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TOP MENU BAR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # From left data that are project specific and read from file,

    $sid = $state->{"session_id"};

    $dir_1 = "$Common::Config::www_dir/$site";

    $menu_1 = $class->read_menu( "$dir_1/navigation_menu" );

    if ( $state->{"with_nav_analysis"} )
    {
        # Then hardcoded analysis options,
        
        if ( $state->{"sys_menu_1"} eq "analyses" ) {
            $opt_1 = Common::Menus->navigation_menu_analysis( $sid, $state );
        } else {
            $opt_1 = Common::Option->new( "name" => "analyses", "label" => "Analyze", "is_active" => 1 );
        }
        
        $menu_1->append_option( $opt_1, 1 );
    }

    # Then login / logout,

    if ( $state->{"logged_in"} ) {
        $opt_1 = Common::Option->new( "label" => "Logout", "name" => "logout", "sys_request" => "logout" );
    } else {
        $opt_1 = Common::Option->new( "label" => "Login", "name" => "login", "sys_request" => "login_page" );
    }
    
    $opt_1->is_active( 1 );
    $opt_1->fgcolor( "" );
    $opt_1->bgcolor( "" );

    $menu_1->append_option( $opt_1, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SECOND MENU BAR <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # See if there is a subdirectory,

    $dir_2 = "$dir_1/$state->{'sys_menu_1'}";

    if ( -d $dir_2 )
    {
        $menu_2 = $class->read_menu( "$dir_2/navigation_menu" );

        $opt_1 = $menu_1->match_option( "name" => $state->{"sys_menu_1"} );

        $menu_2->id( $opt_1->id );
        $menu_2->name( $opt_1->name );
        $menu_2->label( $opt_1->label );
        
        $menu_1->replace_option( $menu_2, $opt_1->id );

        if ( not $state->{"sys_menu_2"} )
        {
            $opt_2 = $menu_2->match_option( "selected" => 1 ) || ( $menu_2->options )[0];
            $state->{"sys_menu_2"} = $opt_2->name;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET VIEWER FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $nav_click->{"menu_1"} or $nav_click->{"menu_2"} 
         or not $state->{"viewer"} or not $state->{"inputdb"} )
    {
        $opt_1 = $menu_1->match_option( "name" => $state->{"sys_menu_1"} );

        if ( not defined $opt_1 ) {
            &Common::Messages::error( qq (No match in menu_1 for -> "$state->{'sys_menu_1'}") );
        }

        if ( &Common::Types::is_menu( $opt_1 ) )
        {
            $opt_2 = $opt_1->match_option( "name" => $state->{"sys_menu_2"} );
            
            if ( not $opt_2 ) {
                $opt_2 = ( $opt_1->options )[0];# match_option_index( 0 );
            }

            $state->{"viewer"} = $opt_2->method || "";
            $state->{"inputdb"} ||= $opt_2->inputdb || "";
            $state->{"request"} = $opt_2->request || "";
        }
        else
        {
            $state->{"viewer"} = $opt_1->method || "";
            $state->{"inputdb"} ||= $opt_1->inputdb || "";
            $state->{"request"} = $opt_1->request || "";
        }
    }

    return $menu_1;
}

sub navigation_menu_analysis
{
    # Niels Larsen, June 2007.

    # Returns the analysis navigation menu, where submenus appear when there
    # is results etc. 

    my ( $class,
         $sid,          # Session id 
         $state,        # State hash
         ) = @_;

    # Returns a menu object. 

    my ( $id, @opts, $menu );

    $id = 0;
    
    @opts = {
        "label" => "Upload",
        "name" => "upload",
        "method" => "submit_viewer",
        "request" => "upload_page",
        "id" => ++$id,
    };

    if ( -r "$Common::Config::ses_dir/$sid/clipboard_menu" )
    {
        push @opts, ({
            "label" => "Clipboard",
            "name" => "clipboard",
            "method" => "submit_viewer",
            "request" => "show_clipboard_page",
            "id" => ++$id,
        },{
            "label" => "Launch",
            "name" => "submit",
            "method" => "submit_viewer",
            "request" => "show_launch_page",
            "id" => ++$id,
        });
    }
    
    if ( $state->{"with_results"} )
    {
        push @opts, {
            "label" => "Results",
            "name" => "results",
            "method" => "submit_viewer",
            "request" => "show_results_page",
            "id" => ++$id,
        };
    }
    elsif ( not $state->{"sys_menu_2"} or $state->{"sys_menu_2"} eq "results" )
    {
        $state->{"sys_menu_2"} = "upload";
    }
    
    @opts = map { Common::Option->new( %{ $_ },
                                       "fgcolor" => "",
                                       "bgcolor" => "",
                                       "is_active" => 1,
                                       "sys_request" => "",
                                       "inputdb" => "" ) } @opts;
    
    $menu = $class->new( "name" => "analyses",
                         "label" => "Analyze",
                         "title" => "Analyses submenu options" );
    
    $menu->options( \@opts );
    
    return $menu;
}
    
sub project_data
{
    # Niels Larsen, April 2008.

    # Returns a menu of all installed data, and declared 
    # as "datasets" or "datasets_other" under a given project. It reads the 
    # installed data (from the searchdbs_menu file in the WWW home directory),
    # or gets them from the registry if that does not exist. It also ignores 
    # the datasets that are not declared. This means data will "disappear" 
    # from view if they are not installed, or if they are not declared, ie.
    # one can hide data from view by just commenting them out in the register.

    my ( $class,            # Class name
         $proj,             # Subproject object or name
         ) = @_;

    # Returns a menu object.

    my ( $data, @db_names, $db, @opts, $path );

    if ( not ref $proj ) {
        $proj = Registry::Get->project( $proj );
    }

    # Read all installed datasets,

    $path = "$Common::Config::www_dir/". $proj->projpath ."/regentries_menu";
    $data = $class->read_menu( $path, 0 );

#     # If none, take those from project description,

#     if ( not $data or not @{ $data->options } )
#     {
#         $data = $class->new();
#         @opts = ();

#         foreach $db ( Registry::Get->datasets( $proj->datasets )->options )
#         {
#             push @opts, Registry::Option->new(
#                 "owner" => $proj->name,
#                 "name" => $db->name,
#                 "title" => $db->title,
#                 "datatype" => $db->datatype,
#                 "format" => $db->format,
#                 "datadir" => $db->datadir || "",
#                 );
#         }
        
#         $data->append_options( \@opts );
#     }

    # Add data declared as "datasets_other", ie data owned by other projects,

    if ( $proj->datasets_other and @db_names = @{ $proj->datasets_other } ) 
    {
        @opts = ();

        foreach $db ( Registry::Get->datasets( \@db_names )->options )
        {
             push @opts, Registry::Option->new(
                 "owner" => $proj->name,
                 "name" => $db->name,
                 "title" => $db->title,
                 "datatype" => $db->datatype,
                 "formats" => [ $db->format ],
                 "datadir" => $db->datadir || "",
                 );
        }
              
        $data->append_options( \@opts );
    }

    $data->name( "searchdbs_menu" );
    $data->title( "Data Menu" );
    $data->css( $Def_viewer_style );
    
    $class = ( ref $class ) || $class;
    bless $data, $class;

    return $data;
}

sub project_methods
{
    # Niels Larsen, April 2008.

    # Returns a menu of all methods that can work with the data defined 
    # by the given project, minus those that the project explicitly does 
    # not want (the hide_methods list). If a second optional data menu 
    # is given then the data options are taken from that rather than 
    # pulled from the registry. 

    my ( $class,       # Class name
         $proj,        # Project name or object
         ) = @_;

    # Returns a menu object.

    my ( $data, $meths, $skip, @meths, %skip, @opts, $datobjs );
    
    if ( not ref $proj ) {
        $proj = Registry::Get->project( $proj );
    }

    # Get all methods, minus the unwanted ones defined in the project,

    $meths = Registry::Get->methods();

    if ( $skip = $proj->hide_methods )
    {
        $skip = [ $skip ] if not ref $skip;
        %skip = map { $_, 1 } @{ $skip };
        
        @opts = grep { not exists $skip{ $_->name } } @{ $meths->options };
        $meths->options( &Storable::dclone( \@opts ) );
    }
    
    # Filter methods by the datasets defined in the project,
    
    $data = $proj->datasets;
    
    if ( $proj->datasets_other ) {
        push @{ $data }, @{ $proj->datasets_other };
    }
    
    $datobjs = Registry::Get->objectify_datasets( $data );

    @meths = Registry::Match->compatible_methods_exclude( [ $meths->options ], $datobjs );

    $meths->options( \@meths );

    $meths->name( "methods_menu" );
    $meths->title( "Methods Menu" );
    $meths->css( $Def_viewer_style );

#    $class = ( ref $class ) || $class;
#    bless $data, $class;

    return $meths; 
}

sub results_menu
{
    # Niels Larsen, December 2005.
    
    # Builds a menu structure from the completed jobs in the batch 
    # queue table and returns it. If a session id is given, only 
    # jobs for that id is included. 

    my ( $class,      # Class or object name
         $sid,        # Session id - OPTIONAL
         $fields,     # List of fields - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $menu, @options, $opt, $field, $job );

    $menu = $class->jobs_menu( $sid, $fields );

    $menu->name( "results_menu" );
    $menu->title( "Results Menu" );

    foreach $job ( @{ $menu->options } )
    {
        if ( $job->status eq "completed" )
        {
            $opt = Common::Option->new();

            foreach $field ( "serverdb", "method", "id", "cid", "title", "coltext", "datatype" )
            {
                $opt->$field( $job->$field );
            }

            push @options, $opt;
        }
    }

    $menu->options( \@options );

    return $menu;
}

sub selections_menu
{
    # Niels Larsen, October 2005.
    
    # Reads the selections menu from file cache in the user session
    # directory, if it exists.

    my ( $class,      # Class or object name
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    $menu = $class->clipboard_menu( $sid );

    $menu->prune_expr( '$_->objtype eq "selection"' );

    $menu->name( "selections_menu" );
    $menu->title( "Selections Menu" );
    $menu->objtype( "selections" );

    $menu->css( "grey_menu" );
    $menu->onchange( "javascript:handle_menu(this.form.uploads_menu,'handle_selections_menu')" );

    $menu->session_id( $sid );

    return $menu;
}

sub uploads_menu
{
    # Niels Larsen, October 2005.
    
    # Reads the uploads menu from file cache in the user session
    # directory, if it exists.

    my ( $class,      # Class or object name
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    $menu = $class->clipboard_menu( $sid );

    $menu->prune_expr( '$_->objtype eq "upload"' );

    $menu->name( "uploads_menu" );
    $menu->title( "Uploads Menu" );
    $menu->objtype( "uploads" );

    $menu->css( "grey_menu" );
    $menu->onchange( "javascript:handle_menu(this.form.uploads_menu,'handle_uploads_menu')" );

    $menu->session_id( $sid );

    return $menu;
}

sub viewer_features
{
    # Niels Larsen, May 2008.

    # Returns a menu of features for a given viewer. If a datatype is also
    # given, the dbtypes field is used to filter the options. 

    my ( $class,
         $viewer,      # Viewer name
         $datatype,    # Data type - OPTIONAL
        ) = @_;

    # Returns a menu.

    my ( $menu, %filter );

    $menu = Registry::Get->features;

    %filter = ( "viewers" => $viewer );

    if ( defined $datatype ) {
        $filter{"dbtypes"} = [ $datatype ];
    }

    $menu->match_options( %filter, "selectable" => 1 );

    $menu->name( "features_menu" );
    $menu->title( "Features Menu" );
    $menu->css( $Def_viewer_style );
    
    return $menu;
}

1;

__END__

# sub viewers_menu
# {
#     # Niels Larsen, December 2005.
    
#     # Returns a menu of the viewers that the system offers, with input 
#     # types given for each. To get the viewer for a given context, 
#     # filter this menu.

#     my ( $class,        # Class name
#          $style,        # CSS style - OPTIONAL
#          ) = @_;

#     # Returns a menu object.

#     my ( $menu, $opts, $opt );

#     $opts = &Common::Types::viewers();

#     foreach $opt ( @{ $opts } )
#     {
#         $opt->{"objtype"} = "viewer";
#     }

#     $menu = $class->new( "options" => $opts );

#     $menu->name( "viewers_menu" );
#     $menu->css( $style || "beige_menu" );

#     $class = ( ref $class ) || $class;
#     bless $menu, $class;
    
#     return $menu;
# }

# sub datatype_methods
# {
#     # Niels Larsen, April 2008.

#     # Returns a menu of the methods where the database input types (dbitypes
#     # field) overlap with the given type. 

#     my ( $class,
#          $type,             # Datatype object or name
#         ) = @_;

#     # Returns a menu object. 

#     my ( $menu );

#     if ( not ref $type ) {
#         $type = Registry::Get->type( $type );
#     }

#     $menu = Registry::Get->methods();
#     $menu->match_options( "dbitypes" => [ $type->name ] );

#     $menu->name( "methods_menu" );
#     $menu->title( "Methods Menu" );
#     $menu->css( $Def_viewer_style );

#     return $menu;
# }
