package Common::Logs;     #  -*- perl -*-

# Functions that log things. Needs work. Old.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &format_error
                 &log_error
                 &set_install_log
                 &unset_install_log
                 &log_warning
                 );
                 
use Common::Config;
use Common::Messages;

use Common::Util;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub format_error
{
    # Niels Larsen, July 2003.

    # Creates of fields that could for example be counted or appended 
    # to a log file.

    my ( $text,    # Text message
         $type,    # Error category - OPTIONAL
         ) = @_;

    # Returns an array. 

    $text =~ s/\n/ /g;

    if ( not $type )
    {
        if ( $Common::Config::sys_name ) {
            $type = uc $Common::Config::sys_name . " ERROR";
        } else {
            $type = "SYSTEM ERROR";
        }
    }

    my ( $time_str, $script_pkg, $script_file, $script_line, $error );

    $time_str = &Common::Util::epoch_to_time_string();
    
    ( $script_pkg, $script_file, $script_line ) = caller;
    
    $error = [ $time_str, $script_pkg, $script_file, $script_line, $type, $text ];
    
    return $error;
}

sub log_error
{
    # Niels Larsen, March 2003.

    # Adds one line to the system errors log file. Fields .. TODO: file locking

    my ( $error,    # Error hash
         ) = @_;

    # Returns nothing.

    if ( $Common::Config::with_error_log and $Common::Config::log_dir )
    {
        my ( $timestr, $logfile, $message, $title, $trace );
        
        $timestr = &Common::Util::epoch_to_time_string();
        $message = $error->{"MESSAGE"} ||= "";
        $title = $error->{"TITLE"} ||= "ERROR";
        
        if ( $error->{"STACK_TRACE"} )
        {
            $trace = Dumper( $error->{"STACK_TRACE"} );
            $trace =~ s/\n//g;
            $trace =~ s/ //g;
        }
        else {
            $trace = "";
        }
        
        $message =~ s/\s*\n\s*/\\n/g;
        
        $logfile = "$Common::Config::log_dir/SYSTEM_ERRORS";

        if ( not open LOG, ">> $logfile" ) {
            &Common::Messages::error( qq(Could not append-open system error log file -> "$logfile") );
        }
        
        if ( not print LOG "$title\t$timestr\t$0\t$message\t$trace\n" ) {
            &Common::Messages::error( qq(Could not append-write to error log file -> "$logfile") );
        }
        
        if ( not close LOG ) {
            &Common::Messages::error( qq(Could not close append-opened error log file -> "$logfile") );
        }
    }
    
    return;
}

sub set_install_log
{
    # Niels Larsen, August 2006.

    # Adds a small informational hash to the 

    my ( $path,
         $done,
         ) = @_;

    my ( $name, $dir, $file, $info, $time );

    $path = "$Common::Config::log_dir/Install/$path";
    
    ( $name, $dir ) = &File::Basename::fileparse( $path );
    
    &Common::File::create_dir_if_not_exists( $dir );

    if ( -r $path )
    {
        $info = &Common::File::eval_file( $path );
        $info = [ grep { $_->{"name"} ne $name or
                         $_->{"done"} ne $done } @{ $info } ];
    }
    else {
        $info = [];
    }

    $time = &Common::Util::epoch_to_time_string();

    push @{ $info }, {
        "name" => $name,
        "time" => $time,
        "done" => $done,
    };

    &Common::File::dump_file( $path, $info );

    return;
}

sub unset_install_log
{
    # Niels Larsen, August 2006.

    # Adds a small informational hash to the 

    my ( $dir,
         $name,
         $done,
         ) = @_;

    my ( $file, $info );

    $file = "$dir/$name";

    if ( -r $file )
    {
        $info = &Common::File::eval_file( $file );

        $info = [ grep { $_->{"name"} ne $name or
                         $_->{"done"} ne $done } @{ $info } ];

        if ( @{ $info } ) {
            &Common::File::dump_file( $file, $info );
        } else {
            &Common::File::delete_file( $file );
        }
    }

    return;
}

sub log_warning
{
    # Niels Larsen, March 2003.

    # Adds one line to the system warnings log file. Fields .. TODO

    my ( $warning,    # Warning hash
         ) = @_;

    # Returns nothing. 

    if ( $Common::Config::with_warning_log and $Common::Config::log_dir )
    {
        my ( $timestr, $logfile, $message, $title );

        $timestr = &Common::Util::epoch_to_time_string();
        $message = $warning->{"MESSAGE"} //= "";
        $title = $warning->{"TITLE"} //= "WARNING";
        
        $message =~ s/\s*\n\s*/\\n/g;
        
        $logfile = "$Common::Config::log_dir/SYSTEM_WARNINGS";

        if ( not open LOG, ">> $logfile" ) {
            &Common::Messages::error( qq(Could not append-open system warnings log file -> "$logfile") );
        }
        
        if ( not print LOG "$title\t$timestr\t$0\t$message\n" ) {
            &Common::Messages::error( qq(Could not append-write to warnings log file -> "$logfile") );
        }
        
        if ( not close LOG ) {
            &Common::Messages::error( qq(Could not close append-opened warnings log file -> "$logfile") );
        }
    }
    
    return;
}

1;

__END__
