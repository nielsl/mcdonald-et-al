package Submit::Menus;     #  -*- perl -*-

# Menu options and functions specific to the submission viewer. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use IO::File;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Users;

use Registry::Get;

use base qw ( Common::Menus Common::Option );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Generates different types of menu structures, and has routines to access
# and manipulate them. Object module. Inherits from Common::Menus.
#
# append_results_menu
# clipboard_options
# job_results
# mc_downloads_menu
# mc_query_menu
# prune_results_menu
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub append_results_menu
{
    # Niels Larsen, May 2008.

    # Appends the options of a job menu in a given directory to the results
    # menu in the given directory. If in void context, writes the new longer
    # version overwriting the old, otherwise just returns the new one. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns menu object or nothing. 

    my ( $sid, $dir, $res_path, $job_path, $res_menu, $job_menu );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ses_id job_dir ) ],
    });

    $sid = $args->ses_id;
    $dir = $args->job_dir;

    $res_path = "$Common::Config::ses_dir/$sid/results_menu";
    $job_path = "$dir/results_menu";

    if ( not $res_menu = Common::Menu->read_menu( $res_path, 0 ) )
    {
        $res_menu = Common::Menu->new;
        $res_menu->name( "ali_user_menu" );
        $res_menu->title( "User Menu" );
        $res_menu->session_id( $sid );
        $res_menu->objtype( "clipboard" );    
    };

    $job_menu = Common::Menu->read_menu( $job_path );

    $res_menu->append_options( [ $job_menu->options ] );

    if ( defined wantarray ) {
        return $res_menu;
    } else {
        &Common::File::write_yaml( "$res_path.yaml", $res_menu ); 
    }

    return;
}

sub clipboard_options
{
    # Niels Larsen, June 2007.

    # Creates a list of options that can be put into the pulldown menus. This
    # means finding out which database formats the upload supports, since 
    # databases are not made at upload-time, but at run-time, to not slow the
    # upload. So we take all the methods that accept the upload format as input
    # and makes a list of 

    my ( $sid,
        ) = @_;

    my ( @opts, $opt, %methods, $method, $formats, %formats, @rows );

    @opts = Common::Menus->clipboard_menu( $sid )->options;

    foreach $opt ( @opts )
    {
        push @rows, Registry::Option->new(
            "method" => $opt->method || "",
            "cid" => $opt->id,
            "name" => $opt->id,
            "title" => $opt->title,
            "label" => $opt->coltext,
            "dbname" => "clipboard",
            "formats" => $opt->formats,
            "datatype" => $opt->datatype,
            );
    }

    return wantarray ? @rows : \@rows;
}

sub job_results
{
    # Niels Larsen, February 2007.

    # Returns a menu of views for a given session and job number. Its used
    # on the results page.

    my ( $class,
         $sid,          # Session id
         $jobid,        # Job number
         ) = @_;

    # Returns a menu object.
    
    my ( $menu, $file, @opts, $opt, $i, $datatype, $viewer, $inputdb );
    
    $file = "$Common::Config::ses_dir/$sid/Analyses/$jobid/results_menu";

    if ( -r "$file.yaml" )
    {
        $menu = $class->SUPER::read_menu( $file );

        foreach $opt ( $menu->options )
        {
            $datatype = $opt->datatype;

            if ( &Common::Types::is_alignment( $datatype ) ) {
                $viewer = "array_viewer";
            } else {
                &error( qq (Un-implemented viewer datatype -> "$datatype") );
            }

#            $inputdb = &Common::Names::strip_suffix( $opt->input );
            $inputdb = $opt->input;

            $opt->title( $opt->title );
            $opt->id( qq (viewer='$viewer';inputdb='$inputdb';) );
        }
        
        $menu->name( "results_menu_". $jobid );
        $menu->session_id( $sid );

        $class = ( ref $class ) || $class;
        bless $menu, $class;
        
        return $menu;
    }
    else {
        return;
    }
}

sub prune_results_menu
{
    # Niels Larsen, April 2008.

    # Reads the results menu (results_menu.yaml) for a given user, removes
    # entries with the given job ids. If in void context, writes the shorter 
    # version overwriting the old, otherwise just returns the shorter one. 

    my ( $class,
         $sid,                # Session id
         $jids,               # Job ids
        ) = @_;

    # Returns menu object or nothing.

    my ( $file, $menu );

    $file = "$Common::Config::ses_dir/$sid/results_menu.yaml";

    if ( -r $file )
    {
        $menu = &Common::File::read_yaml( $file );
        $menu->prune_field( "jid", $jids );

        if ( defined wantarray ) 
        {
            return $menu;
        }
        else
        {
            &Common::File::delete_file( $file );
            &Common::File::write_yaml( $file, $menu );
            return;
        }
    }
    
    return;
}

1;

__END__

   
