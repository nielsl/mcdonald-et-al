package Registry::Paths;            # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Methods that return full file or directory paths

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

our $Tmp_dir;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub new_temp_path
{
    # Niels Larsen, August 2008.

    # Returns a path to a file in the Scratch directory that does 
    # not exist. 

    my ( $class,
         $prefix,
        ) = @_;

    my ( $path, $time, $version, $tmp_dir );

    $time = &Common::Util::epoch_to_time_string();

    $tmp_dir = $Registry::Paths::Tmp_dir // $Common::Config::tmp_dir;

    if ( $prefix ) {
        $path = "$tmp_dir/$prefix.$time.$$";
    } else {
        $path = "$tmp_dir/$time.$$";
    }
        
    if ( -e $path )
    {
        $version = 1;

        while ( -e "$path.$version" ) {
            $version += 1;
        }

        $path .= ".$version";
    }

    return $path;
}

1;

__END__
