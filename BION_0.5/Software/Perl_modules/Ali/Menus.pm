package Ali::Menus;     #  -*- perl -*-

# Menu options and functions specific to the alignment viewer. 
# Some of the functions write into the users area.

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use Common::Util;
use Ali::DB;

use base qw ( Common::Menus Common::Menu );

our $Viewer_name = "array_viewer";

# bookmarks_menu
# control_menu
# downloads_menu
# features_selected_default
# features_tuples_default
# features_existing
# inputdb_menu
# datatype_menu
# formats_menu
# print_menu
# set_selected_default
# uploads_menu
# user_menu

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub bookmarks_menu
{
    # Niels Larsen, October 2007.
    
    # Reads the bookmarks menu from the user session directory.

    my ( $class,
         $sid,        # Session id
         ) = @_;

    # Returns a menu object.

    my ( $menu, $file );

    if ( -r ( $file = "$Common::Config::ses_dir/$sid/ali_bookmarks_menu" ) )
    {
        $menu = &Common::File::retrieve_file( $file );
    }
    else
    {
        $menu = Common::Menu->new();
        $menu->name( "ali_bookmarks_menu" );
        $menu->title( "Bookmarks" );
    }

    $menu->session_id( $sid );

    $class = ( ref $class ) || $class;
    bless $menu, $class;
    
    return $menu;
}

sub control_menu
{
    # Niels Larsen, May 2007.
    
    # Creates the main control menu. It is hard-coded since it has only a 
    # few options that wont change very often, and there should be no data
    # dependent options in it.

    my ( $class,      # Package name
         $sid,        # Session id 
         ) = @_;

    # Returns a menu object.

    my ( $url, $prefs_url, $fts_url, $down_url, $print_url,
         $menu, @opts, $opts, $opt, @divs );

    $url = qq ($Common::Config::cgi_url/index.cgi?viewer=$Viewer_name;)
         . qq (session_id=$sid);

    $prefs_url = qq ($url;request=ali_prefs_panel);
    $fts_url = qq ($url;request=ali_features_panel);
    $down_url = qq ($url;request=ali_downloads_panel);
    $print_url = qq ($url;request=ali_print_panel);

    push @{ $opts },
    {
        "title" => "Settings",
        "id" => "javascript:popup_window('$prefs_url',600,550)",
        "datatype" => "config_opt",
        "helptext" => "Sets the image dimensions, turns on/off labels and numbers,"
            ." toggles collapse mode, border, and sets zoom percentage. This can be done for"
            ." the current dataset only, or saved as default.",
    },{
        "title" => "Highlights",
        "id" => "javascript:popup_window('$fts_url',600,500)",
        "datatype" => "config_opt",
        "helptext" => "Turns on/off the highlights that apply to the datasets of the"
            ." current type. Settings can be saved for the current dataset only, or as default.",
#     },{
#         "title" => "Data",
#         "id" => "javascript:popup_window('$down_url',550,350)",
#         "datatype" => "export_opt",
#         "helptext" => "Downloads fasta-formatted sequences - aligned or unaligned - for either the"
#             ." whole dataset, or the visible part only.",
#     },{
#         "title" => "Image",
#         "id" => "javascript:popup_window('$print_url',550,400)",
#         "datatype" => "export_opt",
#         "helptext" => "Downloads a PNG or GIF formatted image of the visible alignment. This is"
#             ." better than taking a screen-shot because there are more pixels, but it should really"
#             ." be SVG and PDF (todo).",
    };

    foreach $opt ( @{ $opts } )
    {
        $opt->{"viewer"} = $Viewer_name;
        $opt->{"selectable"} = 1;
    }

    @opts = map { Common::Option->new( %{ $_ } ) } @{ $opts };

    $menu = Common::Menu->new( "name" => "ali_control_menu",
                               "title" => "&nbsp;Controls" );

    $menu->options( \@opts );

    @divs = (
        [ "config_opt", "Configure", "grey_menu_divider" ],
        [ "export_opt", "Export", "grey_menu_divider" ],
        );

    $menu->add_dividers( \@divs );

    return $menu;
}

sub downloads_menu
{
    # Niels Larsen, May 2007.

    # Creates a menu structure for the download data menu.

    my ( $class,
         $ali_name,
         ) = @_;
    
    # Returns a Registry menu object.

    my ( $source, @opts, $opt, $menu );

    $source = $ali_name;
    $source .= ".fasta" if $source !~ /\.fasta$/i;

    @opts = ({
        "name" => "ali_download_data",
        "value" => 0,
        "title" => "Download data", 
        "description" => qq (Chooses type of download data.),
        "datatype" => "boolean",
        "choices" => [{
            "name" => "visible_ali",
            "title" => "screen alignment"
        },{
            "name" => "all_ali",
            "title" => "whole alignment"
        },{
            "name" => "visible_seqs",
            "title" => "screen un-aligned sequences"
        },{
            "name" => "all_seqs",
            "title" => "all un-aligned sequences"
        }],
    },{
        "name" => "ali_download_format",
        "title" => "Download format",
        "value" => "fasta",
        "description" => qq (Fasta format is currently the only choice.),
        "datatype" => "text",
        "selectable" => 0,
    },{
        "name" => "ali_download_file",
        "title" => "File name",
        "value" => $source,
        "description" => qq (This is our suggested name for the file that will come to your machine.)
                       . qq ( This name may be changed here, and there will be another chance when)
                       . qq ( the download popup window appears.),
        "datatype" => "text",
    });

    $menu = Registry::Get->_objectify( \@opts, 1);

    foreach $opt ( $menu->options )
    {
        $opt->visible(1);
        $opt->selectable(1) if not defined $opt->selectable;
    }

    return $menu;
}

sub features_selected_default
{
    # Niels Larsen, April 2008.

    # Sets the default options selected. 

    my ( $class,
         $menu,
         $datatype,
        ) = @_;

    my ( %names, @names, @tmp, @select );

    @names = @{ $menu->options_names };
    @select = ();

    if ( @tmp = grep /^ali_sim_match$/, @names )
    {
        @select = @tmp;
    }
    elsif ( &Common::Types::is_rna( $datatype ) )
    {
        if ( @tmp = grep /^ali_rna_pairs/, @names )
        {
            @select = @tmp;
        }
    }
    
    if ( not @select ) {
        @select = "ali_seq_cons";
    }


    $menu = $menu->select_options( \@select, "name" );

    return $menu;
}

sub features_tuples_default
{
    my ( $class,
         $args,
        ) = @_;

    my ( $db, $tuples, $fts );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( dbname ) ],
    });

    $db = Registry::Get->dataset( $args->dbname );

    if ( $fts = Common::Menus->dataset_features( $db ) )
    {
        $tuples = [ map { [ $_->name, $_->selected ? 1 : 0 ] } @{ $fts->options } ];
    }
    else {
        $tuples = [];
    }

    return $tuples;
}

sub features_existing
{
    # Niels Larsen, April 2008.

    # Returns a feature menu with features that the given alignment has, and that 
    # the user should see (some are invisible "pseudo-features"). A menu object 
    # structure is returned. 

    my ( $dbh,          # DB handle
         $args,         # Arguments hash
         $msgs,         # Outgoing messages
        ) = @_;

    # Returns a menu object. 

    my ( $sid, $viewer, $ali_id, $ali_type, @names, $name, @list, $menu, $key, 
         $option, $opt, @opts, $ft_hash );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( sid viewer ali_id ali_type ) ],
    });

    $sid = $args->sid;
    $viewer = $args->viewer;
    $ali_id = $args->ali_id;
    $ali_type = $args->ali_type;

    @names = &Ali::DB::list_features( $dbh, $ali_id );

    # HACK: currently there are two pairing features, ali_rna_pairs_helix and 
    # ali_rna_pairs_pseudo, but the display wants only one -- TODO

    foreach $name ( @names )
    {
        if ( $name =~ /^ali_rna_pairs/ ) {
            $name = "ali_rna_pairs";
        }
    }

    # Add features that are not pre-calculated and that match the datatype,

    $menu = Registry::Get->features();

    foreach $opt ( $menu->match_options( "dbtypes" => $ali_type ) )
    {
        if ( not $opt->imports->routine ) {
            push @names, $opt->name;
        }
    }

    $menu = Registry::Get->features( \@names );

    # Remap the features menu into a simper one,

    foreach $option ( @{ $menu->options } )
    {
        $opt = Common::Option->new( "id" => $option->id,
                                    "name" => $option->name,
                                    "title" => $option->title,
                                    "selected" => 0,
                                    "request" => "highlight_". $option->name,
                                    "routine" => $option->imports->routine,
                                    );

        foreach $key ( qw ( min_score max_score 
                            min_pix_per_row min_pix_per_col ) )
        {
            if ( defined $option->display->$key ) {
                $opt->$key( $option->display->$key );
            }
        }

        push @opts, &Storable::dclone( $opt );
    }

    $menu = Common::Menu->new( "name" => "ali_features_menu",
                               "title" => "&nbsp;Highlights",
                               "options" => \@opts );

    # Set either saved selections or guessed defaults,

    $ft_hash = &Common::States::restore_viewer_features(
        {
            "viewer" => $viewer,
            "sid" => $sid,
            "datatype" => $ali_type,
        });

    if ( $ft_hash and %{ $ft_hash } )
    {
        foreach $opt ( @{ $menu->options } )
        {
            if ( $ft_hash->{ $opt->name } ) {
                $opt->selected( 1 );
            }
        }
    }
    else {
        $menu = Ali::Menus->features_selected_default( $menu, $ali_type );
    }

    return $menu;
}

sub inputdb_menu
{
    # Niels Larsen, October 2005.
    
    # Creates a menu of the datatypes that the alignment viewer 
    # understands. 

    my ( $class,      # Package name
         $sid,        # Session id - OPTIONAL
         $file,
         ) = @_;

    # Returns a menu object.

    my ( $menu, $opt, $text );

    $menu = $class->SUPER::read_menu( $file );

    $menu->name( "ali_inputdb_menu" );
    $menu->title( "Alignments" );

    foreach $opt ( $menu->options ) {
        $opt->title( $opt->label );
    }

    $menu->session_id( $sid );

    $class = ( ref $class ) || $class;
    bless $menu, $class;

    return $menu;
}

sub datatype_menu
{
    # Niels Larsen, October 2005.
    
    # Creates a menu of the datatypes that the alignment viewer 
    # understands. 

    my ( $class,
         ) = @_;

    # Returns a menu object.

    my ( $menu, $opt, $text );

    $menu = $class->SUPER::datatype_menu();

    $menu->name( "ali_datatype_menu" );

    $menu->prune_expr( '$_->name =~ /_ali$/' );

    $class = ( ref $class ) || $class;
    bless $menu, $class;    

    return $menu;
}

sub formats_menu
{
    # Niels Larsen, January 2005.
    
    # Creates a menu of the formats that the alignment viewer 
    # understands. 

    my ( $class,
         $datatype,
         ) = @_;

    # Returns a menu object.

    my ( $menu, $names, $opts, $opt, $datatypes, @names );

    $menu = $class->SUPER::formats_menu();

    $menu->name( "ali_formats_menu" );

    if ( $datatype )
    {
        $names = $class->datatype_to_formats( $datatype );
    }
    else
    {
        $datatypes = $class->datatype_menu();

        foreach $opt ( $datatypes->options ) {
            push @names, @{ $opt->formats };
        }
        
        $names = &Common::Util::uniqify( \@names );
    }

    $menu->match_options( "name" => $names );

    $class = ( ref $class ) || $class;
    bless $menu, $class;    

    return $menu;
}

sub print_menu
{
    # Niels Larsen, May 2007.

    # Creates a menu structure for the download image panel.

    my ( $class,
         $ali_name,
         ) = @_;

    # Returns a menu object.

    my ( @opts, $opt, $menu );

    @opts = ({
        "name" => "ali_print_format",
        "value" => 0,
        "title" => "Image format", 
        "description" => qq (Choice between three bitmap formats. There are no vector)
                       . qq ( format such as SVG yet, due to lack of free tools)
                       . qq ( that preserve transparancy.\)),
        "datatype" => "boolean",
        "choices" => [{
            "name" => "png",
            "title" => "PNG",
#         },{
#             "name" => "svg",
#             "title" => "SVG",
        },{
            "name" => "gif",
            "title" => "GIF"
        }],
    },{
        "name" => "ali_print_dpi",
        "title" => "Enlargement",
        "value" => 2,
        "description" => qq (Bitmap images look ragged when printed because printers have many)
                       . qq ( more dots than screens. This option paints the screen content on)
                       . qq ( a larger image and thereby more detail is preserved when the)
                       . qq ( printer, or a graphics tool, scales it down again. Hopefully.),
        "datatype" => "boolean",
        "choices" => [{
            "name" => "1.2",
            "title" => "20%",
        },{
            "name" => "1.5",
            "title" => "50%",
        },{
            "name" => "2",
            "title" => "100%",
        },{
            "name" => "3",
            "title" => "200%",
        },{
            "name" => "6",
            "title" => "500%",
        },{
            "name" => "11",
            "title" => "1000%",
        }],
        "selectable" => 0,
    },{
        "name" => "ali_print_file",
        "title" => "File prefix",
        "value" => $ali_name,
        "description" => qq (The file coming to your machine will be the name given here appended)
                       . qq ( with the format chosen above. Spaces in the name are converted to)
                       . qq ( underscores.),
        "datatype" => "text",
#     },{
#         "name" => "ali_print_title",
#         "title" => "Image title",
#         "value" => "",
#         "description" => qq (An optional title can be given here, which will be printed in the)
#                        . qq ( image margin. Perhaps useful as annotation of image content.),
#         "datatype" => "text",
    });

    $menu = Registry::Get->_objectify( \@opts, 1);

    foreach $opt ( $menu->options )
    {
        $opt->visible(1);
        $opt->selectable(1) if not defined $opt->selectable;
    }

    return $menu;
}

sub user_menu
{
    # Niels Larsen, April 2008.

    # Creates a menu of user selections and/or results, if any.
    # Its does this by invoking the selections and results menus
    # and merges them. 

    my ( $class,     
         $sid,       # Session id
         ) = @_;

    # Returns a menu object.    

    my ( $menu, @opts, $opt, $prefix, $id, $data );

    # Alignment upload items, if any,

    $menu = $class->SUPER::uploads_menu( $sid );
    $menu->prune_expr( '$_->dataset->datatype =~ /_ali$/' );

    $id = 0;

    foreach $opt ( $menu->options )
    {
        $data = $opt->dataset;

        push @opts, Common::Option->new( 
            "id" => ++$id,
            "jid" => "",
            "title" => $data->title,
            "input" => $opt->input,
            "datatype" => $data->datatype,
            );
    }

    # Results if eny,

    $prefix = "$Common::Config::ses_dir/$sid/results_menu";

    if ( -r "$prefix.yaml" )
    {
        $menu = Common::Menu->read_menu( $prefix );
        $menu->prune_expr( '$_->dataset->datatype =~ /_ali$/' );

        foreach $opt ( $menu->options )
        {
            push @opts, Common::Option->new( 
                "id" => ++$id,
                "jid" => $opt->jid,
                "title" => $opt->title,
                "input" => $opt->input,
                "datatype" => $opt->datatype,
                );
        }
    }

    $menu = $class->new( "options" => \@opts );

    $menu->name( "ali_user_menu" );
    $menu->title( "User Menu" );
    $menu->session_id( $sid );
    $menu->objtype( "clipboard" );    

    return $menu;
}

1;

__END__

# sub features_menu_state
# {
#     # Niels Larsen, May 2007.

#     # If a feature hash comes with the given alignment, then use those keys
#     # to build a features menu with. If not, take those covered by both the 
#     # datatype of the given data and the current project. 

#     my ( $class,
#          $ali,
#          $sid,
#          $proj,
#          ) = @_;

#     # Returns a menu object.

#     my ( $tuples, $ft_hash );

#     if ( $ali->source eq "Upload" )
#     {
#         $tuples = Ali::Menus->features_tuples_default(
#             {
#                 "project" => $proj,
#                 "datatype" => $ali->datatype,
#             });
#     }
#     else {
#         $tuples = Ali::Menus->features_tuples_dataset( $ali->source );
#     }
    
#     $ft_hash = &Common::States::restore_viewer_features({
#         "viewer" => $Viewer_name,
#         "sid" => $sid,
#         "datatype" => $ali->datatype,
#     });
    
#     if ( $ft_hash and %{ $ft_hash } ) {
#         $tuples = Ali::Menus->features_tuples_set_selected( $tuples, $ft_hash );
#     } else {
#         $tuples = Ali::Menus->features_tuples_set_selected( $tuples, $ali->ft_options );
#     }

#     return Ali::Menus->features_menu( $tuples );
# }

# sub features_tuples_dataset
# {
#     my ( $class,
#          $data,
#          ) = @_;

#     my ( $tuples );
    
#     $tuples =  [ map { [ $_->name, $_->selected ? 1 : 0 ] }
#                  Common::Menus->dataset_features( $data )->options ];

#     return $tuples;
# }

# sub features_tuples_set_selected
# {
#     # Transfers the select-status of the given hash to the given list 
#     # of tuples, without changing the list content or length otherwise.

#     my ( $class,
#          $tuples,
#          $hash,
#          ) = @_;

#     my ( $tuple );

#     foreach $tuple ( @{ $tuples } )
#     {
#         if ( exists $hash->{ $tuple->[0] } )
#         {
#             $tuple->[1] = $hash->{ $tuple->[0] };
#         }
#     }

#     return $tuples;
# }

# #     }

# #     $def_hash = &Common::States::restore_viewer_features( $args );

# #     foreach $data_opt ( @{ $data_opts } ) {
# #         $data_opt->selected( $def_hash->{ $data_opt->name } );
# #     }


# sub features_menu_old
# {
#     # Niels Larsen, May 2007.

#     my ( $class,
#          $tuples,
#          ) = @_;
    
#     # Returns a menu object.

#     my ( @keys, $key, $value, $reg_opts, $reg_opt, $opt,
#          $i, @opts, $menu );

#     @keys = map { $_->[0] } @{ $tuples };
#     $reg_opts = { map { $_->name, $_ } Registry::Get->features( \@keys )->options };

#     for ( $i = 0; $i <= $#keys; $i++ )
#     {
#         ( $key, $value ) = @{ $tuples->[$i] };

#         $reg_opt = $reg_opts->{ $key };

#         $opt = Common::Option->new( "id" => $reg_opt->id,
#                                     "name" => $reg_opt->name,
#                                     "title" => $reg_opt->title,
#                                     "selected" => $value,
#                                     "request" => "highlight_". $reg_opt->name,
#                                     "routine" => $reg_opt->routine,
#                                     );

#         foreach $key ( qw ( min_score max_score 
#                             min_pix_per_row min_pix_per_col ) )
#         {
#             if ( defined $reg_opt->$key ) {
#                 $opt->$key( $reg_opt->$key );
#             }
#         }

#         push @opts, &Storable::dclone( $opt );
#     }
    
#     $menu = Common::Menu->new( "name" => "ali_features_menu",
#                                "title" => "&nbsp;Highlights",
#                                "options" => \@opts );

#     return $menu;
# }
