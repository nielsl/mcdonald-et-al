package Seq::Download;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Registry::Args;
use Registry::Get;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Download;

use Install::Data;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub download_databank
{
    # Niels Larsen, June 2007.

    # Downloads to local disk what is missing of the latest databank 
    # release, and daily updates. It can be run periodically to keep 
    # the local collection up to date. 
    #
    # If there is a new release, then this release and its daily update
    # files are shadow directory - Downloads_new, with a Daily directory
    # within. The import routine will then see then, and start creating
    # Installs_new, also with Daily inside. 
    # 
    # If there is no new release but one or more daily updates, then 
    # these are not copied to a shadow directory, but to Downloads/Daily.
    # The import routine will then see these new files and work them 
    # into Installs/Daily, the online version. 

    my ( $class,
         $args,          # Arguments and switches
         ) = @_;

    # Returns an integer.

    my ( @r_files, $count, $l_version, $r_version, $msg, $i, $src_dir,
         $answer, $label, $routine, $db, $prompt );

    $args = &Registry::Args::check(
        $args, {
            "S:1" => [ qw ( dbname inplace version version_local list_release ) ],
            "S:0" => [ qw ( list_daily ) ],
        });

    $db = Registry::Get->dataset( $args->dbname );

    $count = 0;

    &echo( "   Is our release version current ... " );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DETERMINE VERSIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    {
        no strict 'refs';
        local $Common::Messages::silent = 1;

        $routine = $args->version;
        $r_version = $routine->( $db );
        
        $routine = $args->version_local;
        $l_version = $routine->( $db );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PREPARE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not defined $l_version or $l_version < $r_version )
    {
        if ( $args->inplace ) {
            $src_dir = $db->datapath_full ."/Downloads";
        } else {
            $src_dir = $db->datapath_full ."/Downloads_new";
        }

        if ( defined $l_version )
        {
            &echo_yellow( "no\n" );

            # Prompt first,

            &echo_yellow( "   Local version is $l_version, remote is $r_version\n\n" );

            $prompt = &echo( "   Ok to download and install new version? [yes] " );
            $answer = &Common::File::read_keyboard( 10, $prompt );
            $answer = "yes" if not $answer;

            &echo( " - " );

            if ( $answer =~ /^yes$/i ) {
                &echo_green( "ok, will do\n\n" );
            } else {
                &echo( "ok, will not\n\n" );
            }

            # Optional deletion of existing,

            if ( $args->inplace )
            {
                &echo( qq (   Deleting current installation ... ) );

                &Install::Data::uninstall_dataset( $db,
                   {
                       "dirs" => [ qw ( Downloads Installs ) ],
                       "clean" => 0,
                   } );
                
                &echo_green( "done\n" );
            }
        }
        else { 
            &echo_yellow( "not installed\n" );
        }
    }
    else
    {
        if ( $l_version > $r_version )
        {
            $label = $db->label;

            $msg = qq (
The local $label version is $l_version, higher than the
released version $r_version. This should of course not happen
and probably indicates a data or software problem.);
            &error( $msg );
        }

        &echo_green( "yes\n" );
        $src_dir = $db->datapath_full ."/Downloads";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DOWNLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    {
        no strict "refs";

        $routine = $args->list_release;

        if ( $routine )
        {
            @r_files = $routine->( $db );
        }
        else {
            &error( qq (No release listing routine) );
        }

        &Common::File::create_dir_if_not_exists( $src_dir );

        $count += &Common::Download::download_files( \@r_files, $src_dir );

        # Daily files, optional,

        $routine = $args->list_daily;

        if ( $routine )
        {
            @r_files = $routine->( $db );

            if ( @r_files )
            {
                &Common::File::create_dir_if_not_exists( "$src_dir/Daily" );
                
                $count += &Common::Download::download_files( \@r_files, "$src_dir/Daily" );
            }
        }
    }

    return $count;
}

1;

__END__
