package Common::OS;     #  -*- perl -*-

# Functions that somehow interact with the operating system. Please
# use "conservative" perl, since this module may be loaded before the
# bundled perl is installed. 

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use English;
use Fcntl;
use POSIX;
use Symbol;
use IO::Socket;

@EXPORT_OK = qw (
                 &cpus_and_cores
                 &disk_full_pct
                 &disk_space_free
                 &disk_space_total
                 &disk_space_unit
                 &get_cores
                 &get_cpus
                 &get_host
                 &get_kernel_name
                 &get_login
                 &get_machine_name
                 &get_max_files_open
                 &is_64bit
                 &is_executable
                 &is_linux
                 &is_mac_osx
                 &ram_avail
                 &ram_free
                 &ram_total
                 &run3_command
                 &run_command
                 &run_command_backtick
                 &run_command_modperl
                 &run_command_parallel
                 &run_command_reliable
                 &run_command_single
                 );

use Common::Config;
use Common::Messages;

use Common::Util;
use Common::File;

use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> BION DEPENDENCY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# The &error function is exported from the Common::Messages module if 
# if part of Genome Office, i.e. if the shell environment BION_HOME 
# is set. If not, the &error function uses plain confess,

BEGIN
{
    if ( $ENV{"BION_HOME"} ) {
        eval qq(use Common::Messages);
    } else {
        eval qq(use Carp; sub error { confess("Error: ". (shift) ."\n") });
    }
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub cpus_and_cores
{
    # Niels Larsen, September 2012.

    # Returns the number of CPUs and cores as a two-element list. Uses GNU
    # parallel, but there are likely better ways.

    # Returns a list. 

    my ( $cpus, $cores );

    local %ENV = %ENV;
    &Common::Config::set_perl5lib_min();
    
    &Common::OS::run3_command( "parallel --number-of-cores", undef, \$cores );
    $cores =~ s/\s//g;

    &Common::OS::run3_command( "parallel --number-of-cpus", undef, \$cpus );
    $cpus =~ s/\s//g;
    
    return ( $cpus, $cores );
}
    
sub disk_full_pct
{
    # Niels Larsen, April 2003.

    # Returns the fill-percentage of the disk or disk-partition that 
    # a given directory path belongs to. 

    my ( $dir,     # Directory path
         $free,    # Free bytes - OPTIONAL
         ) = @_;

    # Returns a number.

    my ( $total );

    if ( not defined $free ) {
        $free = &Common::OS::disk_space_free( $dir );
    }

    $total = &Common::OS::disk_space_total( $dir );

    return 100 * ( $total - $free ) / $total;
}

sub disk_space_free
{
    # Niels Larsen, March 2003.

    # Accepts a directory and returns the amount of free diskspace
    # for the associated partition. The amount can be returned in bytes
    # (the default), kilobytes, megabytes, gigabytes or petabytes. 

    my ( $dir,   # Directory path
         $mod,   # Modifier, "K", "M", "G", "P" - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( $df, $space, $message );

    $dir = &Common::File::resolve_links( $dir );

    require Filesys::DfPortable;

    $df = &Filesys::DfPortable::dfportable( $dir );
    
    $space = $df->{"bavail"}; # in bytes, not blocks

    if ( not $space )
    {
        $message = qq (
Disk space lookup returned zero bytes. This is very unlikely
to be true and probably means a lookup failure. There is little
you can do about this as user other than report the problem.);

        &Common::Messages::error( $message );
    }

    $space = &Common::OS::disk_space_unit( $space, $mod );

    return $space;
}

sub disk_space_total
{
    # Niels Larsen, March 2003.

    # Returns the amount of free diskspace for the partition associated
    # with a given directory. The amount can be returned in bytes 
    # (default), kilobytes, megabytes, gigabytes or petabytes. 

    my ( $dir,   # Directory path
         $mod,   # Modifier, "K", "M", "G", "P" - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( $df, $space, $message );

    require Filesys::Df;

    $df = &Filesys::Df::df( $dir, 1024 );
    $space = $df->{"user_blocks"} * 1024;      # blocks -> bytes 

    if ( not $space )
    {
        $message = qq (
Disk space lookup returned zero bytes. This is very unlikely
to be true and probably means a lookup failure. There is little
you can do about this as user other than report the problem.);

        &Common::Messages::error( $message );
    }

    $space = &Common::OS::disk_space_unit( $space, $mod );

    return $space;
}

sub disk_space_unit
{
    # Niels Larsen, March 2003.

    # Divides a given number of bytes with an integer that corresponds
    # to the second "modifier" argument. For example, a modifier "M"
    # would divide the number by 1,000,000. 

    my ( $space,   # Integer
         $modif,   # Modifier, "K", "M", "G", "P" - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( $message );

    $modif ||= "";
    
    if ( $modif eq "K" ) {
        $space = int ( $space / 1000 );
    } elsif ( $modif eq "M" ) {
        $space = int ( $space / 1000000 );
    } elsif ( $modif eq "G" ) {
        $space = int ( $space / 1000000000 );
    } elsif ( $modif eq "P" ) {
        $space = int ( $space / 1000000000000 );
    }
    elsif ( $modif =~ /\w/ )
    {
        $message = qq (Wrong looking modifier -> "$modif", should be "K", "M", "G", "P" or nothing);
        &Common::Messages::error( $message );
    }
    
    return $space;    
}

sub get_cores
{
    # Niels Larsen, April 2013. 

    my ( $logdir,
        ) = @_;

    my ( $cores );

    $cores = &Common::OS::run_command_single(
        "parallel --number-of-cores",
        bless { "logdir" => $logdir, "fatal" => 0 },
        );

    $cores =~ s/\s+//g;

    return $cores;
}

sub get_cpus
{
    # Niels Larsen, April 2013. 

    my ( $logdir,
        ) = @_;

    my ( $cores );

    $cores = &Common::OS::run_command_single(
        "parallel --number-of-cpus",
        bless { "logdir" => $logdir, "fatal" => 0 },
        );

    $cores =~ s/\s+//g;

    return $cores;
}

sub get_host
{
    # Niels Larsen, March 2005.

    # Gets user name or shows fatal message. 

    # Returns a string.

    require Sys::Hostname::Long;

    my ( $host );

#    $host = &Sys::Hostname::Long::hostname_long();   # TODO: gives error
    $host = &Sys::Hostname::Long::hostname();

    if ( not defined $host )
    {
        &Common::Messages::error( "Could not get host name" );
    }

    return $host;
}

sub get_kernel_name
{
    # Niels Larsen, April 2005.

    # Returns a string, like "Linux", that tells the operating
    # system.

    my ( $str );

    $str = &Common::OS::run_command( "uname -s" );
    chomp $str;

    return $str;
}

sub get_login
{
    # Niels Larsen, March 2005.

    # Gets user name or shows fatal message. 

    # Returns a string.

    my ( $login );

    $login = getlogin || getpwuid($<) || `whoami` || undef;

    if ( not defined $login )
    {
        &Common::Messages::error( "Could not get login" );
    }

    return $login;
}

sub get_machine_name
{
    # Niels Larsen, April 2005.

    # Returns a string, like "i686", that tells the machine type.

    my ( $str );

    $str = &Common::OS::run_command( "uname -m" );
    chomp $str;

    return $str;
}

sub get_max_files_open
{
    # Niels Larsen, June 2007.

    # Returns a number that is the maximum number of open files 
    # per process.

    my ( $str, $dir );

    $dir = &Cwd::getcwd();
    
    if ( not defined $dir ) {
        chdir "/tmp";
    }

    $str = &Common::OS::run_command( 'bash -c "ulimit -n"' );
    chomp $str;

    return $str;
}

sub is_64bit
{
    # Niels Larsen, January 2012. 

    # Returns true if the hardware is 64 bit, otherwise nothing.
    # TODO: improve.

    my ( $m );

    $m = &Common::OS::get_machine_name;
    
    if ( $m =~ /x86_64/i or $m =~ /ia64/i )
    {
        return 1;
    }

    return;
}

sub is_executable
{
    # Niels Larsen, May 2011. 

    my ( $prog,
         $msgs,
        ) = @_;

    my ( $path, $stderr, $msg );
    
    $path = "";
    $stderr = "";

    &Common::OS::run3_command( "which $prog", undef, \$path, \$stderr, 0 );

    if ( $stderr )
    {
        $msg = qq (Program is not in the PATH -> "$prog");

        if ( $msgs ) {
            push @{ $msgs }, ["ERROR", $msg ];
        } else {
            &error( $msg );
        }
    }
    else
    {
        chomp $path;
        
        if ( not -x $path )
        {
            $msg = qq (Program is not executable -> "$path");

            if ( $msgs ) {
                push @{ $msgs }, ["ERROR", $msg ];
            } else {
                &error( $msg );
            }
        }
    }
    
    if ( $path ) {
        return $path;
    }
       
    return;
}

sub is_linux
{
    if ( &Common::OS::get_kernel_name() eq "Linux" ) {
        return 1;
    } else {
        return;
    }
}

sub is_mac_osx
{
    if ( &Common::OS::get_kernel_name() eq "Darwin" ) {
        return 1;
    } else {
        return;
    }
}

sub ram_avail
{
    # Niels Larsen, March 2010.

    # Returns ram available for programs. It is calculated as total ram 
    # minus 500 mb for the system.

    return &ram_total() - 500_000_000;
}

sub ram_free
{
    # Niels Larsen, March 2010.

    # Returns free ram in bytes.

    # Returns integer.

    require Sys::MemInfo;
    return &Sys::MemInfo::freemem();
}

sub ram_total
{
    # Niels Larsen, March 2010.

    # Returns total ram in bytes.

    # Returns integer. 

    require Sys::MemInfo;
    return &Sys::MemInfo::totalmem();
}

sub run3_command
{
    # Niels Larsen, December 2009.

    # Runs IPC::Run3::run3 but also checks arguments, errors, and unusual
    # return codes. The input, output and error arguments are like those 
    # run3 wants: they can be file names, file handles, strings, lists or
    # undefined (see IPC::Run3::run3 description). If $fatal is true, then
    # problems causes a crash with a message, otherwise the error message 
    # is appended to the error argument (if defined). Returns 1 on success 
    # and nothing on failure, so by setting $fatal to 0 the function may 
    # be used to check something.

    my ( $cmd,     # Command
         $iref,    # Input reference - OPTIONAL, default callers STDIN
         $oref,    # Output reference - OPTIONAL, default callers STDOUT
         $eref,    # Error reference - OPTIONAL, default callers STDERR
         $fatal,   # Crash flag - OPTIONAL, default 1
        ) = @_;

    # Returns 1 or nothing.

    my ( $str, $cherr, $syserr, $stderr, $ok_code, $prog, $loc_eref,
         $append_error, $cmdstr );

    $fatal = 1 if not defined $fatal;

    local %ENV = %ENV;

    $ENV{"NOTERM"} = 1;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENT VALIDATION <<<<<<<<<<<<<<<<<<<<<<<<<<

    # First argument mandatory, 

    if ( not $cmd ) {
        &Common::Messages::error( qq (Command not given) );
    }
    
    # Input and output may be anything but an empty string (run3 fails with
    # a perl message, does not check),

    $str = "is the empty string - must be string, string or list reference, file handle, or undefined";

    if ( defined $iref and not $iref ) {
        &Common::Messages::error( qq (Input $str) );
    }

    if ( defined $oref and not $oref ) {
        &Common::Messages::error( qq (Output $str) );
    }

    if ( defined $eref and not $eref ) {
        &Common::Messages::error( qq (Error $str) );
    }

    # If input is a file, check that it is readable,

    if ( defined $iref and not ref $iref and not -r $iref ) {
        &Common::Messages::error( qq (Input file is not readable -> "$iref") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    {
        # Run3::run3 can die (where it should with an error code) if 1) an empty
        # string is passed as either of the arguments, 2) an input file is missing,
        # 3) if warnings are escalated to fatal. So we switch die handler off and
        # eval the call. TODO - duplicate temporarily STDERR as attempt to catch 
        # the die message.

        local $SIG{__DIE__} = undef;    # To avoid warnings in run3 
        local $SIG{INT} = &Common::Messages::set_interrupt_handler();

        $stderr = "";

        require IPC::Run3;

        eval
        {
            $cmd =~ s/\"/\'/g;
            $cmd = qq (bash -O extglob -c \"$cmd\");

            IPC::Run3::run3( $cmd, $iref, $oref, \$stderr, { "return_if_system_error" => 1 } );

            $cherr = $?;
            $syserr = $!;
        };

        $cherr = 0 if not defined $cherr;

        # This is to compensate for a bug in IPC::Run3, where a temporary file
        # deleted without checking if it was created (line 208, that module has
        # many bugs that do not get fixed),

        if ( $@ and $@ !~ /BION\/Scratch/ )
        {
            $cherr = -1;
            $syserr = "IPC::Run3::run3 died from unhandled error - check input exists\n";
            $syserr .= "The eval error was: $@";
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RETURN STATUS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Return codes from programs are most often zero on success, something else on 
    # failure. But neither success or failure codes are standardized and they vary
    # a lot, people say. And POSIX only requires zero for success, and leaves the
    # rest up to authors. Selkov Jr thinks the best way is to see if the least 
    # significant bit is zero, and if it is not, then look at stderr. To make that
    # work, exceptions to that rule have to be recorded for a few unfortunate 
    # commands and programs. 

    # Routine that appends a string to one of the output arguments, whatever form
    # they may have,

    $append_error = sub
    {
        my ( $ref, $str ) = @_;
        
        my ( $type );
        
        if ( $type = ref $ref )
        {
            if ( $type eq "ARRAY" ) {
                push @{ $ref }, $str;
            } elsif ( $type =~ /File|Handle/i ) {
                $ref->print( $str );
            } elsif ( $type eq "SCALAR" ) {
                ${ $ref } .= $str;
            } else {
                &Common::Messages::error( qq (Wrong looking reference type -> "$type") );
            }
        }
        elsif ( defined $ref ) {
            $ref .= $str;
        } else {
            print STDERR $str;
        }
        
        return $ref;
    };

    # Routine that tests command and error code, and returns 1 if ok,

    $ok_code = sub
    {
        my ( $cmd, $code ) = @_;

        $prog = ref $cmd ? $cmd->[0] : $cmd;

        return 1 if $code == 0;
        return 1 if $code == 256 and $prog =~ /^grep|diff|diff3|cmp|comm$/;
        return 1 if $code == 65280 and $prog =~ /patscan/;

        return;
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ERROR HANDLING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $cmdstr = ref $cmd ? (join " ", @{ $cmd }) : $cmd;

    if ( $ok_code->( $cmd, $cherr ) )
    {
        # Success, append errors if any,

        if ( $stderr ne "" )
        {
#            if ( &Common::Messages::is_run_by_console() ) {
#                $eref = $append_error->( $eref, "Error returned by $cmdstr: $stderr" );
#            } else {
                $eref = $append_error->( $eref, $stderr );
#            }                
        }

        return 1;
    }
    else
    {
        # Failure, 

        if ( $cherr == -1 )
        {
            $str = qq (Failed to run "$cmdstr"\nSystem says "$syserr");
        }
        elsif ( $stderr ne "" )
        {
#            $str = "Error returned by '$cmdstr':\n$stderr";
            $str = "$stderr";
        }
        elsif ( $syserr ne "" ) 
        {
#            $str = "System error from '$cmdstr':\n$syserr";
            $str = "$syserr";
        }
        elsif ( $cherr & 127 )
        {
            $str = sprintf "Child died with signal %d, %s coredump\n", 
            ($cherr & 127), ($cherr & 128) ? 'with' : 'without';
        }
        else {
            $str = "Child exited with value $cherr";
        }

        if ( $fatal ) {
            &Common::Messages::error( $str );
        } else {
#            $eref = $append_error->( $eref, "Error returned by $cmdstr: $str" );
#            $eref = $append_error->( $eref, &Common::Messages::error( $str, 0 ) );
            $eref = $append_error->( $eref, $str );
        }
    }

    return;
}

sub run_command
{
    # Niels Larsen, May 2008.

    # Runs a given command. 

    my ( $cmd,      # Command to be run
         $args,     # Hash of parameters
         $errs,     # List of error lines - OPTIONAL
        ) = @_;

    my ( @stdout, $stdout );

    if ( &Common::Messages::is_run_by_web_server_modperl )
    {
        # Mod_perl assigns STDOUT to apache client, which means it cannot be 
        # captured from these commands; so this one "borrows" STDOUT by creating
        # a new one that goes away when done and then STDOUT reverts to the old,

        $stdout = &Common::OS::run_command_modperl( $cmd, undef, $errs );
    }
    else
    {
        $stdout = &Common::OS::run_command_reliable( $cmd, $args, $errs );
#        @stdout = &Common::OS::run_command_backtick( $cmd, $args, $errs );
    }

    if ( defined wantarray )
    {
        if ( wantarray ) 
        {
            @stdout = split "\n", $stdout;
            return  wantarray ? @stdout : \@stdout;
        } 
        else {
            return $stdout;
        }
    }

    return;
}

sub run_command_backtick
{
    # Niels Larsen, March 2009.

    my ( $command,    # Command to be run
         $params,
         $errlist,
        ) = @_;

    # Returns a list.

    my ( @output, @errors, $file, $fh, $output );

    local $| = 1;

    if ( ref $command ) {
        $command = join " ", @{ $command };
    }

    {
        local $SIG{__DIE__} = "";
        local $SIG{__WARN__} = "";

        @output = `$command 2>&1`;
    }

    if ( $? )
    {
        chomp @output;

        if ( defined $errlist )
        {
            push @{ $errlist }, map { ["ERROR", $_] } @output;
            @errors = @output;
            @output = ();
        }
        else {
            &Common::Messages::error( join "\n", @output );
        }
    }

    if ( $file = $params->{"log_file"} )
    {
        &Common::File::create_dir_if_not_exists( &File::Basename::dirname( $file ) );

        $fh = &Common::File::get_append_handle( $file );

        $fh->print( "\n----------- Output from $command:\n\n" );

        if ( @errors ) {
            $fh->print( join "\n", map { " *** ERROR: $_" } @errors );
            $fh->print( "\n" );
        }

        if ( @output ) {
            $fh->print( join "\n", @output );
            $fh->print( "\n" );
        }

        $fh->close;
    }

    return wantarray ? @output : \@output;
}

sub run_command_modperl
{
    # Niels Larsen, August 2008.

    # Mod_perl assigns STDOUT to the web client, which means it cannot be 
    # captured from these commands. This routine creates a new STDOUT that
    # goes away when done and then STDOUT reverts to the old.
    
    my ( $cmd,      # Command, string or list
         $args,     # Hash of arguments - OPTIONAL
         $errs,     # List of error lines - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $out_str, $out_fh, @stdout, @stderr );

    if ( ref $cmd ) {
        $cmd = join " ", @{ $cmd };
    }

    # Create new STDOUT assigned to a string, and print to it,
    
    {
        $out_str = "";
        
        $out_fh = Symbol::gensym();
        open $out_fh, '>', \$out_str or die "Can't open stdout to string: $!";
        
        local $| = 1;
        
        local *STDOUT = $out_fh;
        
        print `$cmd 2>&1`; 
        
        close $out_fh;
    }

    # If list context return list, otherwise a string,

    if ( $out_str )
    {
        if ( defined wantarray )
        {
            if ( wantarray ) 
            {
                @stdout = split "\n", $out_str;
                return  wantarray ? @stdout : \@stdout;
            } 
            else {
                return $out_str;
            }
        }
    }
    else {
        return;
    }
}

sub run_command_parallel
{
    # Niels Larsen, January 2012. 

    # Run a given command in parallel using GNU parallel. Optionally runs at lowest 
    # priority, always halts if there are errors, creates logs in the given scratch
    # directory. The STDOUT output is returned as a string reference, but outputs 
    # are usually sent to files. It works by creating the commands as a list, then
    # write those to a file and then feed that file to GNU parallel.

    my ( $cmd,
         $args,
        ) = @_;

    # Returns a string.

    my ( @commands, $stdout, $stderr, $log_dir, $log_file, $cmd_file, $fh, 
         $time_str, @msgs, $log_gnup, @stderr, @lines, $i );

    $log_dir = $args->{"logdir"};

    $cmd_file = "$log_dir/run-commands";
    $log_file = "$log_dir/run-commands.log";
    $log_gnup = "$log_dir/gnu-parallel.log";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE LOG FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Write all commands to a log file before they are run, so we can go back
    # and rerun if something went wrong. Its a two-column table with rows that 
    # are either start-time <tab> parallel-command-and-file, or just empty 
    # first column and second column is one of the commands to be run in 
    # parallel,

    @commands = map { "\t$_" } &Common::File::read_lines( $cmd_file );

    $time_str = &Common::Util::epoch_to_time_string();
    unshift @commands, "$time_str\t$cmd\n";

    &Common::File::write_file( $log_file, \@commands, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    {
        # Unset most of our perl paths so GNU parallel can run.
        # This is likely our mistake, not GNU parallels. Our 
        # environment are handled in a messy way, improve some
        # day,

        local %ENV = %ENV;
        &Common::Config::set_perl5lib_min();

        if ( $args->{"env"} )
        {
            $cmd = ( join "; ", map {"export $_='$args->{'env'}->{ $_ }'"} keys %{ $args->{"env"} } ) ."; $cmd";
        }

        {
            no warnings;
            &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr, 0 );
        }
    }

    # Crash with traceback message if something wrong and $fatal is on,

    if ( $stderr and ( $args->{"fatal"} // 1 ) )
    {
        @stderr = split "\n", $stderr;

        for ( $i = 0; $i <= $#stderr; $i += 1 ) 
        {
            if ( $stderr[$i] =~ /this job failed/i )
            {
                splice @stderr, $i;
                last;
            }
        }

        @lines = &Common::File::read_lines( $log_gnup );
        shift @lines;

        $cmd = pop @lines;

        if ( $cmd )
        {
            if ( $cmd =~ / -c (.+)$/ ) {
                $cmd = $1;
            }
            
            $cmd =~ s/\\//g;
            $cmd =~ s/ --silent//g;

            push @stderr, "GNU parallel says this command failed:\n";
            push @stderr, "$cmd\n";
            push @stderr, "For more detail perhaps, try run it by cut/paste on the command line.";
            push @stderr, "Log files are in $log_dir\n";
        }

        $stderr = join "\n", @stderr;
        
        &error( $stderr );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> APPEND LOGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # &Common::File::append_files( $log_all, $log_file );

    return \$stdout;
}

sub run_command_reliable
{
    # Niels Larsen, August 2008.

    # Runs a command using the Proc::Reliable module which separates stdout, stderr, 
    # status and a message. Stdout is returned, and the routine crashes with 
    # an error message if there is a problem. However if a list is given, then stderr
    # lines are added to the list instead; this allows the calling routine to handle
    # the error instead or to continue when an error is perhaps harmless.

    my ( $cmd,     # Command, string or list
         $args,    # Hash of parameters
         $errs,    # List of error lines - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $int_sub, $def_args, $proc, $errmsg, $stdout, $stderr, $status, 
         $msg, $file, @stdout, $fh, $cmd_str );

    # >>>>>>>>>>>>>>>>>>>>>>>> GET AND CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<

    $def_args = {
        "debug" => 0,
        "num_tries" => 3,
        "time_per_try" => 3600,
        "maxtime" => 3600,
        "stdout_cb" => undef,
        "stderr_cb" => undef,
        "want_single_list" => 0,
        "log_file" => undef,
    };

    $args = &Common::Util::merge_params( $args, $def_args );

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ keys %{ $def_args } ],
        } );

    if ( defined $errs ) {
        $args->want_single_list( 0 );
    }

    if ( ref $cmd ) {
        $cmd_str = join " ", @{ $cmd };
    } else {
        $cmd_str = $cmd;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $int_sub = $SIG{INT};

    {
        local %SIG;
        require Proc::Reliable;
    
        $SIG{INT} = $int_sub; 

        Proc::Reliable::debug( $args->debug );
        
        $proc = Proc::Reliable->new();
        
        $proc->num_tries( $args->num_tries ); 
        $proc->time_per_try( $args->time_per_try );
        $proc->maxtime( $args->maxtime );
        $proc->want_single_list( $args->want_single_list );
        $proc->allow_shell( 0 );
        
        ( $stdout, $stderr, $status, $msg ) = $proc->run( $cmd );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT LOGGING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file = $args->log_file )
    {
        &Common::File::create_dir_if_not_exists( &File::Basename::dirname( $file ) );

        $fh = &Common::File::get_append_handle( $file );

        $fh->print( "\n----------- Output from $cmd_str:\n\n" );        $fh->print( $stdout ) if $stdout;
        
        $fh->close;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $status = ( $status >> 8 );

    if ( $status )
    {
        if ( defined $errs )
        {
            push @{ $errs }, "*** STDERR: ". ($stderr||"") ."\n";
            push @{ $errs }, "*** Status: $status\n";
            push @{ $errs }, "*** Message: ". ($msg || "") ."\n";
        }
        else
        {
            $errmsg = qq (From the command "$cmd_str"\n\n);

            $errmsg .= "*** STDERR: ". ( $stderr || "" ) ."\n";
            $errmsg .= "*** Status: $status\n";
            $errmsg .= "*** Message: ". ($msg || "") ."\n\n";

            if ( $args->log_file ) {
                $errmsg .= qq (Details in -> "$file"\n);
            }

            &Common::Messages::error( $errmsg );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RETURN OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined wantarray )
    {
        if ( wantarray ) 
        {
            @stdout = split "\n", $stdout;
            @stdout = map { "$_\n" } @stdout;

            return  wantarray ? @stdout : \@stdout;
        } 
        else {
            return $stdout;
        }
    }

    return;
}

sub run_command_single
{
    # Niels Larsen, January 2012. 
    
    # Runs a single command. Before the command is run, checks input 
    # files if given and writes the command to a log file in the given 
    # scratch directory. 

    my ( $cmd,
         $args,
        ) = @_;

    # Returns a string.

    my ( $log_dir, $stdout, $stderr, $fh, $log_file, $time_str );

    $log_dir = $args->{"logdir"};

    $log_file = "$log_dir/run-commands.log";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE LOG FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Write command to log file before it is run, to see what went wrong if
    # there is a crash,
    
    $time_str = &Common::Util::epoch_to_time_string();
    &Common::File::write_file( $log_file, "$time_str\t$cmd\n", 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Run with altered PERL5LIB path,

    {
        # Unset most of our perl paths so GNU parallel can run. This is 
        # likely our mistake. Our environment are handled in a messy way,
        # improve some day,

        local %ENV = %ENV;
        &Common::Config::set_perl5lib_min();

        if ( $args->{"env"} )
        {
            $cmd = ( join "; ", map {"export $_='$args->{'env'}->{ $_ }'"} keys %{ $args->{"env"} } ) ."; $cmd";
        }

        no warnings;

        &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr );
    }
    
    # Crash with traceback message if something wrong and $fatal is on,

    if ( $stderr and ( $args->{"fatal"} // 1 ) )
    {
        $stderr = join "\n", grep { $_ !~ /\/bin\/parallel/s } split "\n", $stderr;
        &error( $stderr ) if $stderr;
    }

    return $stdout;
}

1;

__END__


# sub run_command_safe
# {
#     # Niels Larsen, August 2008.

#     # Runs a system command using the Proc::SafeExec module, which separates stdout,
#     # stderr, status and a message. Stdout is returned, and the routine crashes with 
#     # an error message if there is a problem. However if a list is given, then stderr
#     # lines are added to the list instead; this allows the calling routine to handle
#     # the error instead or to continue when an error is perhaps harmless.

#     my ( $cmd,    # Command to be run
#          $params,     # Hash of parameters
#          $errs,    # List of error lines - OPTIONAL
#         ) = @_;

#     # Returns a list.

#     my ( %def_params, $proc, $stdout, $stderr, $status, $cmd_str, $out_fh,
#          $fh, $line, $out_file, $err_file, @stdout, @stderr, $subref, @command );

#     require Proc::SafeExec;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# #     %def_params = (
# #         "debug" => 0,
# #         "want_single_list" => 1,
# #         "log_file" => undef,
# #     );

# #     if ( defined $params ) {
# #         $params = { %def_params, %{ $params } };
# #     } else {
# #         $params = \%def_params;
# #     }

#     if ( not ref $cmd ) {
#         $cmd = [ split " ", $cmd ];
#     }

#     {
#         $out_file = &Common::Names::new_temp_path("stdout");
        
#         $out_fh = Symbol::gensym();
        
#         open $out_fh, '>$out_file' or die "Can't open $out_file: $!";
#         local *STDOUT = $out_fh;
        
#         open OUT, ">", $out_file or die "$out_file:  $!\n";
        
#         $proc = new Proc::SafeExec(
#             {
#                 "exec" => $cmd,
#                 "debug" => 0, # $params->{"debug"},
#                 "stdout" => \*OUT,
#                 "stderr" => "new",
#             });

#         $proc->wait();
#         close OUT;
        
#         close $out_fh;
#     }

#     $status = $proc->exit_status() >> 8;

# #    &dump( $out_file );
#     $stdout = ${ &Common::File::read_file( $out_file ) };

#     if ( $stdout ) {
#         @stdout = split "\n", $stdout;
#     }

# #    print "Exit status:  $status   end of status\n";

# #    $status = $proc->exit_status();
# #    $status = $status >> 8;

# #    &dump( "$status" );
# #    &dump( $! );
# #    &dump( $? );
# #    &dump( $@ );
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
# #    &dump( "$EXTENDED_OS_ERROR" );
    
# #     &dump( "\$! -> $!" );
# #     &dump( "\$? -> ", $? );
# #     &dump( "\$? >> 8 -> ", $? >> 8 );
# #     &dump( "\$? & 127 -> ", $? & 127 );
    
# #    $status = $status >> 8;   # Exit codes as from fork and exec
# #    &dump( "$status" );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> READ OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# #     $fh = $proc->stdout();

# #     if ( defined $fh )
# #     {
# #         while ( defined ( $line = <$fh> ) )
# #         {
# #             push @stdout, $line;
# #         }
        
# #         $fh->close;
# #     }

# #     $fh = $proc->stderr();

# #     if ( defined $fh ) 
# #     {
# #         while ( defined ( $line = <$fh> ) )
# #         {
# #             push @stderr, $line;
# #         }

# #         $fh->close;
# #     }

# #    &dump( \@stderr );
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> HANDLE ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# #     if ( defined $errs )
# #     {
# #         @{ $errs } = @stderr;
# #     }
# #     else {
# #         exit;
# #     }

#     return  wantarray ? @stdout : \@stdout;
# }

# sub run_command_simple
# {
#     # Niels Larsen, August 2008.

#     # Runs a system command using the Proc::Simple module, which separates stdout,
#     # stderr, status and a message. Stdout is returned, and the routine crashes with 
#     # an error message if there is a problem. However if a list is given, then stderr
#     # lines are added to the list instead; this allows the calling routine to handle
#     # the error instead or to continue when an error is perhaps harmless.

#     my ( $cmd,    # Command to be run
#          $params,     # Hash of parameters
#          $errs,    # List of error lines - OPTIONAL
#         ) = @_;

#     # Returns a list.

#     my ( %def_params, $proc, $stdout, $stderr, $status, $cmd_str,
#          $out_file, $err_file, @stdout, @stderr, $out_fh, 
#          $oldout, $stdout_fh, $stdout_old, @command );

#     require Proc::Simple;
#     require Proc::SafeExec;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     %def_params = (
# #        "debug" => 1,
# #        "num_tries" => 3,
# #        "time_per_try" => 3600,
# #        "maxtime" => 3600,
#         "want_single_list" => 1,
#         "log_file" => undef,
#     );

#     if ( defined $params ) {
#         $params = { %def_params, %{ $params } };
#     } else {
#         $params = \%def_params;
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>> SET STDOUT AND STDERR <<<<<<<<<<<<<<<<<<<<<<<<<

#     $out_file = &Common::Names::new_temp_path("stdout");
#     $err_file = &Common::Names::new_temp_path("stderr");
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# #    $stdout_fh = IO::String->new( $stdout );
# #    $stdout_old = select( $stdout_fh );

# #     if ( $ENV{"MOD_PERL"} ) {
# #         tie *STDOUT, 'Apache2';
# #     } else {
# #         open (STDOUT, ">-");
# #     }

# #    &dump( $stdout );

# #    $proc = Proc::Simple->new();

# #    Proc::Simple::debug( $params->{"debug"} );

# #    $proc->redirect_output( \$stdout, $err_file );

# #    local *STDOUT = Symbol::gensym;

# #
# #    my $nullfh = Symbol::gensym;
# #    open $nullfh, '>/dev/null' or die "Can't open /dev/null: $!";
# #    local *STDOUT = $nullfh;

# #    if ( ref $cmd ) {
# #        $status = $proc->start( @{ $cmd } );
# #    } else {
# #        $status = $proc->start( split " ", $cmd );
# #    }

# #    close STDOUT;

#     if ( ref $cmd ) {
#         @command = @{ $cmd };
#     } else {
#         @command = split " ", $cmd;
#     }

#     open $stdout_old, ">&STDOUT" or die "Can't dup STDOUT: $!";

# #    open $stdout_old, ">&STDOUT" or die "Can't dup STDOUT: $!";

#     open STDOUT, '>-' or die "Count not write-open $out_file";
#     select STDOUT; $| = 1;        # make unbuffered

#     ($stdout, $?) = Proc::SafeExec::backtick( @command );

#     &dump( $stdout );
#     &dump( $? );
# #    system( @command );

#     close STDOUT;

#     open STDOUT, ">&", $stdout_old or die "Can't dup \$stdout_old: $!";

# #    close STDOUT;
# #    open STDOUT, ">&", $stdout_old or die "Can't dup \$stdout_old: $!";


# #    $status = $proc->wait();

# #    select( $stdout_old ) if defined $stdout_old;

# #    close $nullfh;


#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> READ OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# #    $stdout = ${ &Common::File::read_file( $out_file ) };
# #    &Common::File::delete_file_if_exists( $out_file );

# #    $stderr = ${ &Common::File::read_file( $err_file ) };
# #   &Common::File::delete_file_if_exists( $err_file );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     if ( ref $cmd )
#     {
#         if ( ref $cmd eq "ARRAY" ) {
#             $cmd_str = join " ", @{ $cmd };
#         } else {
#             &Common::Messages::error( qq (Command must be list or string) );
#         }
#     }
#     else {
#         $cmd_str = $cmd;
#     }

# #     if ( $file = $params->{"log_file"} )
# #     {
# #         &Common::File::create_dir_if_not_exists( &File::Basename::dirname( $file ) );

# #         $fh = &Common::File::get_append_handle( $file );

# #         $fh->print( "\n----------- Output from $cmd_str:\n\n" );        
# #         $fh->close;
# #     }
# #     else
# #     {
# #         # TODO fix this splitting
# #         @stdout = split "\n", $stdout;
# #         @stdout = map { "$_\n" } @stdout;
# #     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> HANDLE ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# #     $status = $status >> 8;   # Exit codes as from fork and exec

# #         &dump( "bad command" );

#      if ( $stderr )
#      {

# #         if ( defined $errs )
# #         {
# # #            push @{ $errs }, "*** STDERR: ". ($stderr||"") ."\n";
# #             push @{ $errs }, "*** Status: $status\n";
# #             push @{ $errs }, "*** Message: ". ($msg || "") ."\n";
# #         }
# #         else
# #         {
# #             $errmsg = qq (From the command "$cmd_str"\n\n);

# # #            $errmsg .= "*** STDERR: ". ( $stderr || "" ) ."\n";
# #             $errmsg .= "*** Status: $status\n";
# #             $errmsg .= "*** Message: ". ($msg || "") ."\n\n";

# #             if ( $params->{"log_file"} ) {
# #                 $errmsg .= qq (Details in -> "$file"\n);
# #             }

#              &Common::Messages::error( $stderr );
# #         }
#      }
    
#     if ( $stdout ) {
#         @stdout = split "\n", $stdout;
#     }

#     return  wantarray ? @stdout : \@stdout;
# }
