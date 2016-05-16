package Common::Options;     #  -*- perl -*-

# This module works as a catalog of all supported menu options, across
# all viewers. A routine is defined for each menu that returns all the 
# options that are supported by a given viewer. When defining subprojects,
# we filter those away that dont apply.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &build_viewer_feature_options
                 &build_viewer_prefs_options
                 );

use Common::Config;
use Common::Messages;
use Common::States;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub build_viewer_feature_options
{
    # Niels Larsen, May 2007.

    # Builds a menu structure of the features/highlights that the viewer can
    # show and that are registered with the current project. Those relevant 
    # to the current dataset are shown changable, the with only their values.
    # The structure, plus settings for form values and looks, are sent to a
    # generic report page routine and rendered. The argument hash should 
    # have the "viewer", "sid" and "dataset" keys set. Returns a list of 
    # option objects.

    my ( $args,       # Arguments object
         ) = @_;

    # Returns a list.

    my ( $viewer, $usr_hash, $name, $menu, %lookup, $ft, @opts, %opt, $datatype );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( viewer datatype ) ],
        "S:0" => [ qw ( sid ) ],
        "O:2" => "features",
    });

    $menu = $args->features;

    # Get a hash of all features that the user has saved as defaults, or 
    # else just take the keys from the given menu,

    $usr_hash = &Common::States::restore_viewer_features(
        {
            "viewer" => $args->viewer,
            "sid" => $args->sid,
            "datatype" => $args->datatype,
        });

    if ( not defined $usr_hash or not %{ $usr_hash } )
    {
        $usr_hash = { map { $_->name, $_->selected } @{ $menu->options } };
    }
    
    # Create list of options with title, description, etc, suitable for 
    # display in the popup panels. Where values exist in the user hash 
    # set it, otherwise to zero,

    %lookup = map { $_->name, $_ } Registry::Get->features->options;

    foreach $ft ( @{ $menu->options } )
    {
        $name = $ft->name;
        $ft = $lookup{ $name };

        if ( ( $datatype = $ft->datatype ) eq "boolean" )
        {
            %opt = (
                    "name" => $name,
                    "title" => $ft->title,
                    "description" => $ft->description,
                    "datatype" => $ft->datatype,
                    "visible" => 1,
                    );
            
            $opt{"choices"} = $ft->choices;

            if ( exists $usr_hash->{ $name } )
            {
                $opt{"selectable"} = 1;
                $opt{"value"} = $usr_hash->{ $name };
            }
            else
            {
                $opt{"selectable"} = 0;
                $opt{"value"} = 0;
            }
        }
        else {
            &Common::Messages::error( qq (Wrong looking datatype -> "$datatype") );
        }

        push @opts, Registry::Option->new( %opt );
    }

    return wantarray ? @opts : \@opts;    
}

sub build_viewer_prefs_options
{
    # Niels Larsen, May 2007.

    # Converts a given preferences hash to a menu of options with titles, 
    # descriptions, etc, from the Registry. All parameters that the given 
    # viewer supports are included, and if some of those are not keys in 
    # the given preferences hash, zeros are used as value; this could 
    # happen when adding new parameters to viewers. Returned is a list 
    # of options.

    my ( $args,       # Arguments hash
         ) = @_;

    # Returns a list.

    my ( $viewer, $prefs, $params_all, %lookup, $tuple, %opt, @opts,  
         $value, $param );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer ) ],
        "HR:1" => "prefs",
    });

    $prefs = $args->prefs;
    $viewer = Registry::Get->viewer( $args->viewer );

    $params_all = Registry::Get->param( $viewer->params->name )->values;
    %lookup = map { $_->name, $_ } @{ $params_all->options };

    foreach $tuple ( @{ $viewer->params->values->options } )
    {
        $param = $lookup{ $tuple->[0] };

        %opt = (
                "name" => $param->name,
                "value" => $prefs->{ $param->name } || 0,
                "title" => $param->title,
                "description" => $param->description,
                "datatype" => $param->datatype,
                "selectable" => $param->selectable,
                "visible" => $param->visible,
                );

        if ( $param->datatype eq "boolean" )
        {
            $opt{"choices"} = $param->choices;
        }

        push @opts, Registry::Option->new( %opt );
    }

    return wantarray ? @opts : \@opts;    
}


__END__


# sub ali_mirna_menu
# {
#     # Niels Larsen, August 2005.

#     # Returns the content of the data menu. 

#     # Returns an array. 

#     my ( $src_path, @ali_files, $file, $ali, $options, $option, $title, $name );

#     require Ali::IO;
    
#     $src_path = "RNAs/miRBase/Alignments/Flanks";

#     @ali_files = Common::File::list_files( "$Common::Config::dat_dir/$src_path", '^[^.]+$' );
#     @ali_files = sort { $a->{"name"} cmp $b->{"name"} } @ali_files;

#     foreach $file ( @ali_files )
#     {
#         $ali = &Ali::IO::connect_pdl( $file->{"path"} );

#         $title = ( split " ", $ali->title )[0];

#         push @{ $options },
#         {
#             "input" => "$src_path/" . $file->{"name"},
#             "title" => $title,
#             "datatype" => "rna_ali",
#         };

#         undef $ali;
#     }

#     foreach $option ( @{ $options } )
#     {
#         $option->{"viewer"} = "array_viewer";
#         $option->{"request"} = "";
#     }

#     return wantarray ? @{ $options } : $options;
# }

# sub tax_data_menu
# {
#     # Niels Larsen, January 2005.

#     # Returns a hash of items for the data menu. 

#     # Returns a hash.

#     my ( $options, $option );

#     # >>>>>>>>>>>>>>>>>>>>>>>>> ORGANISMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     push @{ $options },
#     {
#         "coltext" => "ID",
#         "title" => "Show IDs",
#         "tiptext" => "ID for each organism and taxon - click to get small report.",
#         "inputdb" => "ncbi",
#         "datatype" => "orgs_taxa",
#         "request" => "add_ids_column",
#     },{
#         "coltext" => "Orgs",
#         "title" => "Total",
#         "tiptext" => "The number of organisms within a given taxon.",
#         "inputdb" => "ncbi",
#         "datatype" => "orgs_taxa",
#         "request" => "add_statistics_column",
#         "default" => 1,
#     },{
#         "coltext" => "Orgs",
#         "inputdb" => "rRNA_18S_0",
#         "datatype" => "orgs_taxa",
#         "request" => "add_statistics_column",
#     },{
#         "coltext" => "Orgs",
#         "inputdb" => "rRNA_18S_500",
#         "datatype" => "orgs_taxa",
#         "request" => "add_statistics_column",
#     },{
#         "coltext" => "Orgs",
#         "inputdb" => "rRNA_18S_1250",
#         "datatype" => "orgs_taxa",
#         "request" => "add_statistics_column",
#     };
         
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RNA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     push @{ $options },
#     {
#         "coltext" => "SSU",
#         "title" => "SSU seqs, any length",
#         "tiptext" => "The number of unaligned SSU RNA sequence(s) assigned within a given taxon.",
#         "inputdb" => "rRNA_18S_0",
#         "datatype" => "rna_seq",
#         "request" => "add_statistics_column",
#     },{
#         "coltext" => "SSU",
#         "title" => "SSU seqs, >= 500",
#         "tiptext" => "The number of unaligned SSU RNA sequence(s) assigned within a given taxon, of length 500 or more.",
#         "inputdb" => "rRNA_18S_500",
#         "datatype" => "rna_seq",
#         "request" => "add_statistics_column",
#         "default" => 1,
#     },{
#         "coltext" => "SSU",
#         "title" => "SSU seqs, >= 1250",
#         "tiptext" => "The number of unaligned SSU RNA sequence(s) assigned within a given taxon, of length 1250 or more.",
#         "inputdb" => "rRNA_18S_1250",
#         "datatype" => "rna_seq",
#         "request" => "add_statistics_column",
#     },{
#         "coltext" => "SSU",
#         "title" => "SSU bases, all",
#         "tiptext" => "The number of unaligned SSU RNA bases determined for organisms within a given taxon.",
#         "inputdb" => "rRNA_18S_0",
#         "datatype" => "rna_bases",
#         "request" => "add_statistics_column",
#     };
            
#     foreach $option ( @{ $options } )
#     {
#         $option->{"name"} = "tax_data_menu";
#         $option->{"objtype"} = "col_stats";
#         $option->{"viewer"} = "taxonomy";
#         $option->{"css"} = "menu_item";
#     }

#     return wantarray ? @{ $options } : $options;
# }

1;

__END__
