package Common::Cluster;     #  -*- perl -*-

# Routines that manage files and jobs on a set of machines through SSH.
# Configuration: see the routines that start with "config_".

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use Cwd;
use Errno;
use Net::OpenSSH;
use File::Listing;

use Common::OS;
use Common::File;
use Common::Util;
use Common::Tables;
use Common::Admin;

use Registry::Args;
use Registry::Check;

use Seq::Convert;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &account_strings
                 &accts_file
                 &analysis_methods
                 &analysis_packages
                 &ask_for_passwords
                 &check_install_routines
                 &check_package_names
                 &check_program_inputs
                 &close_handles
                 &close_slaves
                 &combine_files
                 &commands_master
                 &commands_slave
                 &config_key_paths
                 &config_master_paths
                 &config_slave_paths
                 &copy
                 &create_keys
                 &create_log_handles
                 &create_slave_tree
                 &delete_log_dir
                 &delete_files
                 &display_connect_errors
                 &display_outputs_ascii
                 &documentation
                 &echo_messages
                 &format_deletes_ascii
                 &format_jobs_list_ascii
                 &format_jobs_stopped_ascii
                 &format_listing_ascii
                 &format_outputs_ascii
                 &format_split_ascii
                 &format_systems_ascii
                 &get_files
                 &handle_messages
                 &install_package
                 &install_packages
                 &install_sys_code
                 &install_sys_full
                 &list_stderrs
                 &list_stdout
                 &open_slaves
                 &open_ssh_connections
                 &put_files
                 &read_slaves_config
                 &run_command
                 &run_program
                 &slave_accounts
                 &slave_capacities
                 &slave_files
                 &slave_jobs
                 &slave_loads
                 &slave_nodes
                 &split_by_content
                 &split_by_size
                 &stop_jobs
                 &system_packages
                 &wait_for_finish
);

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# This is temporary. Better to check the slaves and see what they have.

our $Put_method = "scp_put";
our $Get_method = "scp_get";

# $Net::OpenSSH::debug = -1;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub account_strings
{
    # Niels Larsen, February 2009.

    # Gets the account names from a [[ acct name, ssh object ], ... ] structure.
    # Returns a list of account names.

    my ( $sshs,
        ) = @_;

    # Returns a list.

    my ( @accts );

    @accts = map { $_->[0] } @{ $sshs };

    return wantarray ? @accts : \@accts;
}

sub accts_file
{
    # Niels Larsen, January 2009.

    # Returns the full path of the default accounts file on the master machine.

    # Returns a string.

    return &Common::Cluster::config_master_paths->{"accts_file"};
}

sub analysis_methods
{
    my ( $class,
        ) = @_;

    my ( $method, @table );
    
    foreach $method ( Registry::Get->methods()->options  )
    {
        if ( $method->cmdline )
        {
            push @table, [ $method->name, $method->description ];
        }
    }

    return wantarray ? @table : \@table;
}

sub analysis_packages
{
    # Niels Larsen, January 2009.
    
    # Returns a list of [ program, one-line explanation ] of supported
    # analysis programs. 

    # Returns a list.

    my ( $method, %cmds, $pkg, @table );

    foreach $method ( Registry::Get->methods()->options )
    {
        if ( $method->cmdline ) {
            $cmds{ $method->name } = $method->cmdline;
        }
    }

    foreach $pkg ( Registry::Get->analysis_software()->options )
    {
        if ( $pkg->methods ) 
        {
            foreach $method ( @{ $pkg->methods } )
            {
                if ( exists $cmds{ $method } )
                {
                    push @table, [ $pkg->name, $pkg->title ];
                    last;
                }
            }
        }
    }

    return wantarray ? @table : \@table;
}

sub ask_for_passwords
{
    # Niels Larsen, February 2009.

    # Asks the console for passwords for those of the given accounts that 
    # have not been given a password before. The passwords entered by the 
    # user are added to each account hash. An updated accounts list is 
    # returned. 

    my ( $accts,
        ) = @_;

    # Returns a list.

    my ( $key_dir, $password, $acct, $acct_str, %done, $prompt );

    local $Common::Messages::silent = 0;

    $key_dir = &Common::Cluster::config_master_paths->{"key_dir"};

    &Common::File::create_dir_if_not_exists( $key_dir );

    %done = map { $_->{"name"}, 1 } @{ &Common::File::list_files( $key_dir ) };

    foreach $acct ( @{ $accts } )
    {
        $acct_str = $acct->{"user"} ."@". $acct->{"host"};

       if ( not $acct->{"password"} and not $done{ $acct_str } )
       { 
         ASK_FOR_PASSWORD:
           
           $prompt = &echo( "      Enter password for $acct_str: " );
           
           $acct->{"password"} = &Common::File::read_keyboard( 3600, $prompt, 0 );
           &echo( "\n" );

           if ( not $acct->{"password"} )
           {
               goto ASK_FOR_PASSWORD;
           }
       }
    }

    return wantarray ? @{ $accts } : $accts;
}

sub check_install_routines
{
    # Niels Larsen, January 2009.

    # Checks that installation routines exist for each package name in a 
    # given list. If a package is called "simscan" then the routine
    # Common::Cluster::install_simscan must exist. If not then error 
    # messages are returned.

    my ( $pkgs,    # List of package names
        ) = @_;
    
    # Returns a list.

    my ( $pkg, @msgs );

    @msgs = ();

    foreach $pkg ( @{ $pkgs } )
    {
        if ( not Registry::Check->routine_exists(
                 {
                     "routine" => __PACKAGE__ ."::install_". $pkg,
                     "fatal" => 0,
                 }) )
        {
            push @msgs, ["ERROR", qq (Wrong looking package: "$pkg") ];
        }            
    }
     
    if ( @msgs ) {
        return wantarray ? @msgs : \@msgs;
    } else {
        return
    }
}

sub check_package_names
{
    my ( $pkgs,
        ) = @_;

    my ( %known, $pkg, @msgs );

    if ( $pkgs and @{ $pkgs } ) 
    {
        %known = map { uc $_->[0], 1 } (
            &Common::Cluster::system_packages(),
            &Common::Cluster::analysis_packages(),
        );

        foreach $pkg ( @{ $pkgs } )
        {
            if ( not $known{ uc $pkg } ) {
                push @msgs, ["Error", qq (Wrong looking package -> "$pkg") ];
            }
        }
    }
    else {
        push @msgs, ["Error", qq (No packages given) ];
    }

    if ( @msgs )
    {
        if ( defined wantarray ) {
            return wantarray ? @msgs : \@msgs;
        } else {
            &echo_messages( \@msgs );
            exit;
        }
    }

    return;
}
    
sub check_program_inputs
{
    # Niels Larsen, February 2009.

    # Creates error messages if program inputs do not exist etc. Returns 
    # or prints messages depending on context.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns a list or nothing.

    my ( $prog, @msgs, $prog_path, $cmdline, $output, $datasets, $params, @progs );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( program inputs ) ], 
            "S:0" => [ qw ( params datasets ) ], 
        });

    # Check the given program are amond the supported ones,

    $prog = $args->program;

    if ( defined $prog )
    {
        @progs = &Common::Cluster::analysis_methods();

        if ( not grep { $_->[0] eq $prog } @progs )
        {
            push @msgs, ["ERROR", qq (Wrong looking program name: "$prog") ];
            push @msgs, "";
            push @msgs, ["Help", "Supported programs are:"];

            push @msgs, map { ["Help", qq ($_->[0]: $_->[1]) ] } @progs;
        }
    }
    else    {
        push @msgs, ["ERROR", qq (Program name not given) ];
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    # Check input file given and is readable,

    if ( not defined $args->inputs ) {
        push @msgs, ["ERROR", qq (No input file(s) given) ];
    } 

    # Check output file given,

#     $output = $args->output;

#     if ( not $output ) {
#         push @msgs, ["ERROR", qq (No output file given) ];
#     } elsif ( -e $output ) {
#         push @msgs, ["ERROR", qq (Output exists: "$output") ];
#     }

    $datasets = $args->datasets;
    $cmdline = Registry::Get->method( $prog )->cmdline;
    
    if ( $cmdline =~ /__DATASET__/ )
    {
        if ( not defined $datasets ) {
            push @msgs, ["ERROR", qq (Dataset path not given) ];
        }
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    return;
}
    
sub close_handles
{
    # Niels Larsen, February 2009. 

    # Closes file handles in a hash of hashes of handles. This is 
    # used for closing IO connections to slave hosts.

    my ( $fhs,
        ) = @_;

    # Returns nothing.

    my ( $acct, $h_fhs, $type );

    foreach $acct ( keys %{ $fhs } )
    {
        $h_fhs = $fhs->{ $acct };

        foreach $type ( keys %{ $h_fhs } )
        {
            $h_fhs->{ $type }->close;
        }
    }

    return;
}

sub close_slaves
{
    # Niels Larsen, March 2009.

    # Removes the master's public key from the slave's authorized keys file,
    # thereby terminating password-less logins. They are reopened with the 
    # open_slaves function.

    my ( $sshs,
         $args,
         $msgs,
        ) = @_;
    
    # Returns nothing. 

    my ( $def_args, $timeout, $silent, $key_path, $key, $command, $tmp_file, 
         $acct, $acct_log, $key_dir, @accts, @msgs );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( acctfile acctexpr silent timeout ) ],
        });

    # Get arguments with defaults mixed in,

    $def_args = {
        "acctfile" => &Common::Cluster::accts_file,
        "acctexpr" => undef,
        "silent" => 0,
        "timeout" => 5,
    };

    $args = &Common::Util::merge_params( &Storable::dclone( $args // {} ), $def_args );

    $timeout = $args->timeout;
    $silent = $args->silent;

    local $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nClosing slaves:\n) );

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile,
                "acctexpr" => $args->acctexpr,
                "timeout" => $timeout,
                "silent" => $silent,
            });
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNAUTHORIZE KEY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Remove the master's public key from the slave's ~/.ssh/authorized_keys file,

    $key_path = &Common::Cluster::config_key_paths->{"public"};

    $key = ${ &Common::File::read_file( $key_path ) }; 
    $key = ( split " ", $key )[1];

    $command = qq (cd .ssh && perl -e "`grep -v "$key" authorized_keys > authorized_keys.tmp`");
    $command .= qq ( && rm -f authorized_keys && mv authorized_keys.tmp authorized_keys);

    &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Removing access keys",
            "command" => $command,
            "timeout" => $timeout,
            "nolog" => 1,
            "silent" => $silent,
            "cdfirst" => 0,
            "setenv" => 0,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ACTIVATE PROMPTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Re-activating prompts ... ) );

    $key_dir = &Common::Cluster::config_master_paths->{"key_dir"};

    foreach $acct ( &Common::Cluster::account_strings( $sshs ) )
    {
        $acct_log = "$key_dir/$acct";
        
        if ( -e $acct_log ) {
            &Common::OS::run_command_backtick( qq (rm -f $acct_log) );
        }
    }
    
    &echo_green( "done\n" );

    &echo_bold( qq (Finished\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DISPLAY INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    @accts = &Common::Cluster::read_slaves_config( $args->acctfile, $args->acctexpr );

    push @msgs, "Password-less logins now disabled on all slave nodes";
    
    if ( grep { $_->{"password"} } @accts )
    {
        push @msgs, (
            "",
            "Consider removing passwords from the configuration file:",
            $args->acctfile,
        );
    }

    @msgs = map { ["Info", $_] } @msgs;
    
    if ( $msgs ) {
        push @{ $msgs }, @msgs;
    } else {
        &echo( "\n" );
        &echo_messages( \@msgs );
    }

    return;
}

sub combine_files
{
    # Niels Larsen, February 2009.

    # Combines all files in a list of directories to a single given file, according
    # to format. Many files can be appended, but for example vertical sections of 
    # alignments need special routines. This is used when merging outputs of from 
    # the slaves into a single output. Returns the number of files appended. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns an integer. 

    my ( $dir, @files, $file, @list, $display, $silent, $format );

    $args = &Registry::Args::check(
        $args,
        {
            "AR:1" => [ qw ( from ) ],
            "S:1" => [ qw ( to format ) ], 
            "S:0" => [ qw ( message silent ) ], 
        });

    $display = $args->message // "";
    $silent = $args->silent;
    $format = $args->format;

    local $Common::Messages::silent = $silent;

    &echo( qq (   $display ... ) );
    
    foreach $dir ( @{ $args->from } )
    {
        @list = &Common::File::list_files( $dir );

        if ( @list )
        {
            push @files, map { $_->{"path"} } @list;
        }
    }

    foreach $file ( @files )
    {
        if ( $format eq "appendable" ) {
            &Common::File::append_files( $args->to, $file );
        } else {
            &Common::Messages::error( qq (Unsupported combine format -> "$format") );
        }
    }

    &echo_green( "done\n" );

    return scalar @files;
}

sub commands_master
{
    # Niels Larsen, March 2009.

    # Lists available master commands and checks they are present. Returns a 
    # list of [ name, title ]. 

    # Returns a list.

    my ( $cmds, $cmd, @msgs, $dir );

    $cmds = [
        [ "clu_doc", "Prints documentation messages" ],
        [ "clu_open", "Creates password-less SSH access" ],
        [ "clu_close", "Closes password-less SSH access" ],
        [ "clu_install", "Installs select applications" ],
        [ "clu_slaves", "Lists machine capacities" ],
        [ "clu_do", "Runs a given command" ],
        [ "clu_put", "Copies files to slaves" ],
        [ "clu_get", "Copies files from slaves" ],
        [ "clu_start", "Submits or runs a job" ],
        [ "clu_jobs", "Lists jobs and their status" ],
        [ "clu_stop", "Stops running jobs" ],
        [ "clu_dir", "Lists files and directories" ],
        [ "clu_delete", "Deletes files and directories" ],
        ];

    $dir = $Common::Config::pls_dir;

    foreach $cmd ( @{ $cmds } )
    {
        if ( not -x "$dir/$cmd->[0]" ) {
            push @msgs, ["ERROR", "$cmd->[0] is not executable"];
        }
    }

    if ( @msgs ) {
        &echo_messages( \@msgs );
        exit;
    } else {
        return wantarray ? @{ $cmds } : $cmds;
    }

    return;
}
        
sub commands_slave
{
    # Niels Larsen, March 2009.

    # Lists available slave commands and checks they are present. Returns 
    # a list of [ name, title ]. 

    my ( $dir,
        ) = @_;

    # Returns a list.

    my ( $cmds, $cmd, @msgs );

    $cmds = [
        [ "sclu_run", "Runs a given program" ],
        [ "sclu_jobs", "Prints information about jobs" ],
        [ "sclu_capacity", "Prints machine capacities" ],
        [ "sclu_load", "Prints current machine load" ],
        [ "sclu_stop", "Stops all given job processes" ],
        ];

    $dir = $Common::Config::pls_dir;

    foreach $cmd ( @{ $cmds } )
    {
        if ( not -x "$dir/$cmd->[0]" ) {
            push @msgs, ["ERROR", "$cmd->[0] is not executable"];
        }
    }

    if ( @msgs ) {
        &echo_messages( \@msgs );
        exit;
    } else {
        return wantarray ? @{ $cmds } : $cmds;
    }

    return;
}

sub config_key_paths
{
    # Niels Larsen, January 2009.

    # Returns a hash with keys "public" and "private". The values are
    # absolute paths to the corresponding SSH key files. 

    # Returns a hash.

    my ( %keys );

    %keys = (
        "public" => "$ENV{'HOME'}/.ssh/id_rsa.pub",
        "private" => "$ENV{'HOME'}/.ssh/id_rsa",
        );

    return wantarray ? %keys : \%keys;
}

sub config_master_paths
{
    # Niels Larsen, January 2009.

    # Returns a hash of absolute local (master) file paths.

    # Returns a hash.

    my ( %paths );

    %paths = (
        "tmp_dir" => $Common::Config::tmp_dir,
        "pks_dir" => $Common::Config::pks_dir,
        "ans_dir" => $Common::Config::ans_dir,
        "util_dir" => $Common::Config::uts_dir,
        "log_dir" => $Common::Config::log_dir,
        "key_dir" => "$Common::Config::log_dir/Cluster_nodes",
        "reg_dir" => $Common::Config::conf_clu_dir,
        "accts_file" => "$Common::Config::conf_clu_dir/Cluster.config",
        );

    return wantarray ? %paths : \%paths;
}

sub config_slave_paths
{
    # Niels Larsen, January 2009.
    
    # Returns a hash with remote (slave) directory paths that are relative
    # to the sandbox base directory: ~/Cluster_node.

    # Returns a hash. 

    my ( %paths );

    %paths = (
        "base_dir" => "Cluster_node",

        "reg_dir" => "Registry",
        "doc_dir" => "Documentation",
        "log_dir" => "Logs",
        "dat_dir" => "Datasets",
        "tmp_dir" => "Scratch",
        "job_dir" => "Jobs",
        "soft_dir" => "Software",

        "bin_dir" => "Software/bin",
        "lib_dir" => "Software/lib",
        );

    return wantarray ? %paths : \%paths;
}

sub copy
{
    # Niels Larsen, January 2009.

    # Copies a list of files and/or directories from one place to another. The copying 
    # happens in parallel and it is unpredictable which copy with finish first. 

    my ( $sshs,          # SSH connections - OPTIONAL
         $args,          # Arguments hash - 
         $msgs,          # Outgoing messages list
        ) = @_;

    # Returns nothing.

    my ( $def_args, $ssh, @accts, $acct, %w_errs, $r_outs, $r_errs, $log_dir, $silent,
         %l_errs, $fhs, $job_id, %pids, $display, $method, $opts, $to_path, $r_pwds,
         $to_dir, @to_dir, $timeout, $tuple, @from, %from, %to, $from_max, $i,
         $base_dir, $cdfirst );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args = &Registry::Args::check(
        $args,
        { 
            "AR:1" => [ qw ( from ) ],
            "S:1" => [ qw ( to method ) ],
            "S:0" => [ qw ( message recursive async overwrite acctfile acctexpr
                            job_id silent timeout nolog cdfirst ) ], 
        });

    # Get arguments with defaults mixed in,

    $def_args = {
        "from" => [],
        "to" => "",
        "async" => 1,
        "overwrite" => 0,
        "silent" => 1,
        "timeout" => undef,
        "nolog" => 0,
        "cdfirst" => 1,   # IMPORTANT
    };

    $args = &Common::Util::merge_params( &Storable::dclone( $args ), $def_args );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CONVENIENCE VARIABLES <<<<<<<<<<<<<<<<<<<<<<<<<<

    $base_dir = &Common::Cluster::config_slave_paths->{"base_dir"};

    $method = $args->method;
    $display = $args->message // "";
    $timeout = $args->timeout // 5;
    $silent = $args->silent;
    $cdfirst = $args->cdfirst;

    $job_id = $args->job_id // &Common::Util::epoch_to_time_string() .".$method";

    local $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<

    if ( not $sshs ) 
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "silent" => $silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Optionally delete destination tree. The rsync command will synchronize with 
    # the --overwrite option, but scp will not and deletion must then be done 
    # explicitly, use with caution of course .. 

    if ( $args->overwrite )
    {
        ( undef ) = &Common::Cluster::delete_files(
             $sshs,
             {
                 "message" => "Deleting existing",
                 "paths" => [ $args->to ],
                 "recursive" => 1,
                 "force" => 1,
                 "format" => "ascii",    # TODO
                 "silent" => $silent,
             });
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE DIRECTORY <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $method =~ /_put$/ ) 
    {
        # When copying to slave machines: copying single files creates single 
        # files at the destination; if multiple files the to-path will be taken
        # as a directory in which these files should be put. If to-path ends 
        # with a "/", then destination directories are created even for single 
        # files. Any path is ok, directories will be created on the slaves as
        # needed. Also, put the to-paths into a %to hash.

        $from_max = 0;

        foreach $acct ( keys %from )
        {
            $from_max = &Common::Util::max( $from_max, scalar @{ $from{ $acct } } );
        }

        if ( $from_max > 1 or $args->to =~ m|/$| )
        {
            $to_dir = $args->to;
        }
        else
        {
            @to_dir = split "/", $args->to;

            if ( scalar @to_dir > 1 ) {
                $to_dir = join "/", @to_dir[ 0 .. $#to_dir - 1 ];
            }
        }
        
        if ( $to_dir )
        {
            &Common::Cluster::run_command(
                 $sshs,
                 {
                     "message" => "Creating directory",
                     "command" => "mkdir -p $to_dir",
                     "job_id" => $job_id,
                     "timeout" => $timeout,
                     "nolog" => 0,
                     "silent" => $silent,
                     "cdfirst" => $cdfirst,
                     "setenv" => 0,
                 });
        }

        foreach $acct ( @accts )
        {
            push @{ $from{ $acct } }, @{ $args->from };

            if ( $cdfirst ) {
                $to{ $acct } = "$base_dir/". $args->to;
            } else {
                $to{ $acct } = $args->to;
            }
        }
    }
    elsif ( $method =~ /_get$/ )
    {
        foreach $acct ( @accts )
        {
            # Prepend sandbox directory,

            if ( $cdfirst ) {
                $from{ $acct } = [ map { "$base_dir/$_" } @{ $args->from } ];
            } else {
                $from{ $acct } = &Storable::dclone( $args->from );
            }

            # When copying from slave machines, put files under one directory for 
            # each machine, and create those directories,
            
            $to_path = $args->to ."/$acct";
            &Common::File::create_dir_if_not_exists( $to_path );

            $to{ $acct } = $to_path;
        }
    }
    else {
        &Common::Messages::error( qq (Wrong looking method name -> "$method") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COPY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo( qq (   $display ... ) );

    $opts = {
        "recursive" => $args->recursive // 1,
        "silent" => $silent,
        "async" => $args->async,
#        "timeout" => $timeout,
        "glob" => 1,
        "copy_attrs" => 1,
    };

    # Create handles,

    $log_dir = &Common::Cluster::config_master_paths->{"log_dir"} . "/$job_id";
    
    $fhs = &Common::Cluster::create_log_handles( $log_dir, \@accts );

    %l_errs = ();

    foreach $tuple ( @{ $sshs } )
    {
        ( $acct, $ssh ) = @{ $tuple };

        # Set STDOUT and STDERR file handles,

        $opts->{"stdout_fh"} = $fhs->{ $acct }->{"stdout"};
        $opts->{"stderr_fh"} = $fhs->{ $acct }->{"stderr"};

        # Initiate copies,

#         &dump( "------------------------------------" );
#         &dump( $acct );
#         &dump( $ssh );
#         &dump( $method );
#         &dump( $opts );
#        &dump( $from{ $acct } );
#        &dump( $to{ $acct } );

        if ( not $pids{ $acct } = $ssh->$method( $opts, @{ $from{ $acct } }, $to{ $acct } ) )
        {
            push @{ $l_errs{ $acct } }, [ "ERROR", $acct, qq (Could not initiate $method connection) ];
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> HANDLE LOCAL ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Handle local errors. If any we stop and do not look at other errors, but close
    # file handles, 

    if ( %l_errs ) 
    {
        &Common::Cluster::close_handles( $fhs );

        if ( defined wantarray )
        {
            if ( wantarray ) {
                return ( (), \%l_errs, $job_id );
            } else {
                return $job_id;
            }
        }
        else {

            $Common::Messages::silent = 0;
            &Common::Cluster::show_messages( \%l_errs, 2, 1 );
            exit;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> WAIT FOR FINISH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Wait until all slave processes finished. Wait-errors usually are accompanied by
    # remote errors, so we pool them below,

    %w_errs = &Common::Cluster::wait_for_finish( \%pids );

    # Close stdout/stderr files,

    &Common::Cluster::close_handles( $fhs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> HANDLE REMOTE ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $r_outs = &Common::Cluster::list_stdouts( $job_id );
    $r_errs = &Common::Cluster::list_stderrs( $job_id, \%w_errs );
    
    &Common::Cluster::delete_log_dir( $job_id ) if $args->nolog;

    if ( defined wantarray )
    {
        &echo_green( "done\n" );

        return ( $r_outs, $r_errs, $job_id );
    }
    else
    {
        if ( $r_errs )
        {
            $Common::Messages::silent = 0;
            &Common::Cluster::show_messages( $r_errs, 2, 1 );
            exit;
        }
        else {
            &echo_green( "done\n" );
        }
    }

    return;
}

sub create_keys
{
    # Niels Larsen, January 2009.

    # Creates new public and private keys on the master machine. Existing
    # key files are deleted.

    # Returns nothing.

    my ( $pub_key, $priv_key );

    $priv_key = &Common::Cluster::config_key_paths->{"private"};
    $pub_key = &Common::Cluster::config_key_paths->{"public"};

    &Common::File::delete_file_if_exists( $priv_key );
    &Common::File::delete_file_if_exists( $pub_key );

    &Common::OS::run_command_backtick( "ssh-keygen -t rsa -N '' -P '' -q -f $priv_key" );

    return;
}

sub create_log_handles
{
    # Niels Larsen, January 2009.

    # Creates stderr, stdout and pids io handles in the given directory
    # and for the given accounts.

    my ( $dir,
         $accts,
        ) = @_;

    # Returns a hash.

    my ( $out_dir, $err_dir, $pid_dir, $acct, $fhs );
    
    $out_dir = "$dir/stdouts";
    $err_dir = "$dir/stderrs";
    $pid_dir = "$dir/pids";

    &Common::File::create_dir_if_not_exists( $out_dir );
    &Common::File::create_dir_if_not_exists( $err_dir );
    &Common::File::create_dir_if_not_exists( $pid_dir );

    foreach $acct ( @{ $accts } )
    {
        $fhs->{ $acct }->{"stdout"} = &Common::File::get_append_handle( "$out_dir/$acct" );
        $fhs->{ $acct }->{"stderr"} = &Common::File::get_append_handle( "$err_dir/$acct" );
        $fhs->{ $acct }->{"pid"} = &Common::File::get_append_handle( "$pid_dir/$acct" );
    }

    return $fhs;
}

sub delete_log_dir
{
    # Niels Larsen, January 2009.

    # Deletes the log directory tree for a given job id. Returns the 
    # number of files deleted.

    my ( $job_id,
        ) = @_;

    # Returns an integer. 

    my ( $log_dir, $count );

    $log_dir = &Common::Cluster::config_master_paths->{"log_dir"} ."/$job_id";

    if ( -e $log_dir ) {
        $count = &Common::File::delete_dir_tree( $log_dir );
    }

    return $count;
}

sub delete_files
{
    # Niels Larsen, January 2009.

    # Deletes files that match a given path, perhaps recursively. Returns a 
    # hash of messages if called in non-void context.

    my ( $sshs,          # SSH connections - OPTIONAL
         $args,          # Arguments hash
        ) = @_;

    # Returns a hash or nothing. 
 
    my ( $command, $dir, $outs, $errs, $job_id, $list, $msgs, $display,
         $silent, @accts, $timeout, $path, @commands );

    $args = &Registry::Args::check(
        $args,
        { 
            "AR:1" => [ qw ( paths ) ],
            "S:0" => [ qw ( acctfile acctexpr recursive message format force silent timeout ) ], 
        });

    $display = $args->message || "";
    $silent = $args->silent;
    $timeout = $args->timeout;

    local $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<    

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "message" => "Opening connections",
                "timeout" => $timeout,
                "silent" => $silent,
            });
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE DELETE COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @commands = ();

    foreach $path ( @{ $args->paths } )
    {
        $command = "rm -v";

        if ( $args->force ) {
            $command .= " -f";
        }

        if ( $args->recursive ) {
            $command .= " -R";
        }

        $dir = $path // "";
        $dir =~ s|/$||;
        
        if ( $dir ) {
            $command .= " $dir";
        } else {
            &Common::Messages::error( qq (No directory given) );
        }

        push @commands, $command;
    }

    $command = join " && ", @commands;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This function will cd into the sandbox directory first,

    ( $outs, $errs, $job_id ) = &Common::Cluster::run_command(
        $sshs,
        {
            "message" => $args->message,
            "command" => $command,
            "nolog" => 1,
            "timeout" => $timeout,
            "silent" => $silent,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Convert directory listing outputs to a table with errors mixed in,

    @accts = &Common::Cluster::account_strings( $sshs );
    $list = &Common::Cluster::format_deletes_ascii( \@accts, $outs, $errs );

    if ( defined wantarray )
    {
        if ( $list ) {
            return wantarray ? @{ $list } : $list;
        } else {
            return;
        }
    }
    elsif ( $args->format )
    {
        if ( $args->format eq "ascii" )
        {
            &Common::Cluster::display_outputs_ascii(
                 $list,
                 $errs,
                 {
                     "align" => "right,left",
                     "ifnone" => "No files deleted",
                 });
        }
        else {
            &Common::Messages::error( qq (Wrong looking format) );
        }
    }        

    return;
}

sub display_connect_errors
{
    # Niels Larsen, March 2009.

    # Display connection error messages, with explanatory help.

    my ( $errs,      # Error list
         $file,      # Configuration file
         $flag,      # Exit flag
        ) = @_;

    # Exits or returns nothing.

    my ( @msgs );

    $flag //= 1;
    $file //= &Common::Cluster::accts_file();

    @msgs = split "\n",
qq (There were connection problems. Perhaps the timeout should be 
increased, or perhaps there is a password mistake, or maybe an 
incorrect account in the machines file:

$file
);
    $Common::Messages::silent = 0;

    @msgs = map { ["Advice", $_] } @msgs;

    unshift @msgs, "";
    unshift @msgs, @{ $errs };
    
    &echo( "\n" );
    &echo_messages( \@msgs );
    &echo( "\n" );

    exit if $flag;
    
    return;
}

sub display_outputs_ascii
{
    # Niels Larsen, February 2009.
    
    # Creates a screen listing for a given list of messages and errors. 
    # Prints to STDOUT and returns nothing. 

    my ( $list,
         $errs,
         $args,
        ) = @_;

    # Returns nothing. 

    $args = &Registry::Args::check(
        $args,
        {
            "S:0" => [ qw ( headers align indent colsep ifnone ) ], 
        });

    my ( $opts, %args, $ifnone );

    %args = ();

    $args{"indent"} = $args->indent // 2;
    $args{"colsep"} = $args->colsep // "  ";
    
    if ( $args->headers )
    {
        $args{"header"} = 1;
        $args{"fields"} = $args->headers;
    }
    else {
        $args{"header"} = 0;
    }

    if ( $args->align ) {
        $args{"align"} = $args->align;
    }

    if ( $list and @{ $list } )
    {
        print "\n";

        print Common::Tables->render_list( $list, \%args );
        
        if ( $errs ) {
            print "\n";
        } else {
            print "\n\n";
        }
    }
    
    if ( $errs )
    {
        $Common::Messages::silent = 0;
        &Common::Cluster::show_messages( $errs, 1, 1 );
        exit;
    }

    if ( (not $list or not @{ $list }) and $ifnone = $args->ifnone )
    {
        print "\n  $ifnone\n\n";
        exit;
    }

    return;
}

sub documentation
{
    # Niels Larsen, February 2009.

    # Prints help and lists of commands, programs and packages.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $conf_path, $title, $text, $table, $base_dir, $reg_dir, 
         $plm_dir );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:0" => [ qw ( overview install safety data jobs commands methods packages methow credits ) ], 
        });

    $text = "";
    $base_dir = &Common::Cluster::config_slave_paths()->{"base_dir"};

    $reg_dir = $Common::Config::soft_reg_dir;
    $plm_dir = $Common::Config::plm_dir;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OVERVIEW <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->overview )
    {
        $title = &echo_info( "Overview" );        
        $text .= qq (
$title

This package provides an easy way to run applications on a collection 
of SSH-accessible Unix-like computers. No system administrator access 
is needed, only regular accounts. The package comes with a number of 
freely available RNA analysis programs. Users of this package should be
aware of its security implications (see --safety). 

Cluster setup is done with one single command, which starts a parallel
compilation on all nodes. The cluster is controlled by a single machine,
this one, that acts as master. Commands are given on the command line 
for job launch, file listing and transfer, etc. Commands affect slaves
collectively, for example clu_dir returns directory listings for all 
slaves. During job launch files are split and distributed to the slaves, 
and results gathered and combined. For a job to complete, all slave jobs
must be finished (thus for optimal throughput machines of roughly similar
capacity should be chosen, but see --todo). 

An alternative overall strategy would have been to let slaves pull data 
from the master as they run dry, so that fast slaves are not waiting for 
slow slaves. But that only works for data that can be streamed (like 
sequence entries), it would put strain on the network for large datasets
and makes frequent reruns less convenient. 
);
    }
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALLATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->install )
    {
        $title = &echo_info( "Installation" );
        $conf_path = &Common::Cluster::accts_file();

        $text .= qq (
$title

Both master and slave machines must be Unix-like machines (Linux, BSD,
Mac OSX, and the like) equipped with C and C++ compilers, have the Bourne 
shell (or better) installed, and run an SSH server. Microsoft systems 
lack certain features and will not work. 

Step 1. To set up the slaves, add accounts to this file,

$conf_path

When installing, the easiest is to include passwords in the above file,
which says how.

Step 2. Enter the command 

clu_install sys_full

and wait up to half an hour. During this time many packages are compiled
that ensure a consistent environment. Some package may fail to compile on
some system - please report this. 

Step 3. Remove passwords from the configuration file, but we recommend 
keeping a copy of the password-file in a safe place. 

Files can now be copied back and forth and jobs launched. Commands for 
file listing, copying, job launch, etc, all operate in within a "sandbox",
the ~/$base_dir directory on the given account. Commands are listed 
with clu_doc --commands.
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SANDBOX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->safety )
    {
        $title = &echo_info( "Safety" );
        
        $text .= qq (
$title

Creating password-less logins from a single "master" machine to perhaps 
many other "slave" machines means the master can potentially do a lot of 
damage. It would be quite easy to construct a command that erases all files
on all accounts in the cluster, for example. But if the master user is 
trusted with the passwords we assume that user will not intentionally do 
harm. However this package tries to protect from accidental damage, by 
running commands within a "sandbox" directory tree.

The master user (you) is responsible for not letting the passwords fall 
into the hands of others. This can be prevented with good normal practices,

1. Let the configuration file keep its user-only read mode.
2. Do not keep passwords in the configuration file after clu_open is run.
3. When not using the cluster for a period of time, use clu_close.
4. Make sure the account with this package installed has a good password.

In summary, knowing passwords means you are trusted and do not do willful
damage. The trouble only starts when others learn the passwords, so please
try prevent that by protecting the passwords. If you find the protection 
against accidental damage is lacking, please let us know.
);
}

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->data )
    {
        $title = &echo_info( "Moving Data" );        
        $text .= qq (
$title

Simply copy them to and from the slaves with clu_put and clu_get (see their
usage messages). Within the "sandbox" directory (~/$base_dir), where
all commands operate, any data directory may be created. But we recommend 
staying within "Datasets" and then organize data in sub-directories there. 
Likewise on the master side, pick any directory, but it is good to be 
organized - mess is much easier to prevent than to fix. 

Input data may be split, either by content (e.g. sequences in a file) or 
files (e.g. 1/10 of input files on each of 10 machines). A format must be
given, because the splitting is format dependent. To add formats, see the
Common::Cluster::split_by_content routine.

Results may be combined into a single file, or not (see the clu_get usage 
text). If kept separate the destination must be a non-existing directory,
which will then contain data from each slave in separate sub-directories.
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> JOBS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->jobs )
    {
        $title = &echo_info( "Jobs" );

        $text .= qq (
$title

Jobs are run, in the background or not, with clu_start. They are followed 
with clu_jobs and stopped with clu_stop. Jobs are named by the date/time 
they were started, e.g. 18-FEB-2009-21:33:09. These IDs are also sub-
directories to the Jobs directory on each slave, as can be observed with 
the clu_dir command. 

Usage example. Say we have a set of Solexa reads that should be compared 
with the human genome, as part of a virus project. To simplify this example 
we use just two slave accounts. To gain advantage of the cluster, should we 
then divide the Solexa data set (the "query" data in Blast terms) among the 
machines, or divide the "subject" human genome? we choose the latter, since 
the "nsimscan" program handles larger query sets well. To copy the Solexa 
reads to all slaves,

clu_put solexa.fasta Datasets/Virus/ 

Without the last "/" no Virus directory would be created, rather the data 
would be put into the file "Virus". Now the human genome, which we split by 
file size, i.e. each slave will receive the combination of files that add 
up to about the same total sizes. 

clu_put Human/*.fasta Datasets/Genomes/Human/ --split size 

A more fine-grained way of splitting would be --split content, which writes
new files in which approximately equal amounts of data are placed. To check
if all data arrived okay, 

clu_dir Datasets/Virus
clu_dir Datasets/Genomes/Human

To submit a job,

clu_start --program nsimscan \\
          --inputs Datasets/Virus/solexa.fasta  \\
          --datasets "Datasets/Genomes/Human/*.fasta" \\
          --outputs solhum.simscan --combine --background

where "\\" is just a continuation sign (the whole command should be on one 
line of course), and the quotes prevent the master from expanding the file 
expression to a list of master file names. The outputs are copied back to 
the master machine (to solhum.simscan in the current directory). A job ID 
will be printed and the job will run in the background. The ID is the time 
where the job was started, and can be used to check if the job is running,

clu_jobs 08-MAR-2009-10:55:31

To stop a job, 

clu_stop 08-MAR-2009-10:55:31
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> COMMANDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->commands )
    {
        $title = &echo_info( "Commands" );

        $table = &Common::Cluster::commands_master();
        $table = [ map { [ &echo_green( $_->[0] ), $_->[1] ] } @{ $table } ];
            
        $table = Common::Tables->render_list( $table,
               { "align" => "right,left", "indent" => 2, "colsep" => "  " });
        
        $text .= qq (
$title\n
All commands print help messages when invoked without arguments.\n
$table
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->methods )
    {
        $title = &echo_info( "Methods" );

        $table = &Common::Cluster::analysis_methods();
        $table = [ map { [ &echo_green( $_->[0] ), $_->[1] ] } @{ $table } ];

        $table = Common::Tables->render_list( $table,
               { "align" => "right,left", "indent" => 3, "colsep" => "  " });
        
        $text .= qq (
$title\n
These programs can be run on the slave machines.\n
$table
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PACKAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->packages )
    {
        $title = &echo_info( "Packages" );

        $table = &Common::Cluster::analysis_packages();
        $table = [ map { [ &echo_green( $_->[0] ), $_->[1] ] } @{ $table } ];

        $table = Common::Tables->render_list( $table,
               { "align" => "right,left", "indent" => 3, "colsep" => "  " });
        
        $text .= qq (
$title\n
These packages can be installed on the slave machines.\n
$table
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> ADDING METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->methow )
    {
        $title = &echo_info( "Adding Methods" );

        $text .= qq (
$title

UNFINISHED - will be expanded once the steps wont improve anymore.

1. First declare the installation package in the analysis section of 
   $reg_dir/Packages.pm

2. Declare any/all methods in the package in 
   $reg_dir/Methods.pm

3. Install the software package, still on the master machine. This is 
   done by functions in the software installation module,
   $plm_dir/Install/Software.pm

   These functions will handle GNU style compilations with variations,
   and there may no work needed. If the package compilation is unusual,
   look in the Install::Software::config_soft_anal function. Once the 
   package can be installed with the install_analysis script, go to next
   step.

4. Update all slaves with new code. This is done with

   clu_install sys_code

5. Make it work on the slave machines. This is easy, because there is 
   no setup difference between master and slave; for a given package 
   name as listed by clu_doc packages,

   clu_install package

(6). If the new package uses new formats, then a split and combine 
   routine must also be written. See these functions,
   Common::Cluster::split_by_content
   Common::Cluster::combine_files

You are welcome to extend our software, but doing so creates a version
that is different from ours. To avoid that your extensions are deleted 
as part of updates, please send your work to us so we can make it part
of the distribution and have others benefit too.

Should this package be used by more than a few, then we promise to put
it in a version control system.
);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREDITS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->credits )
    {
        $title = &echo_info( "CLULESS package" );
        $text .= qq (
$title

Author: Niels Larsen
Copyright: \(C\) 2009 Niels Larsen. 
License: GNU public license v3

Credits: Danish Genome Institute and Aarhus University; Unpublished.
         It is built with Perl and the fine Net::OpenSSH Perl module by 
         Salvador Fandino Garcia. The package also builds on the many 
         freely available tools provided by Free Software Foundation.
);
        $title = &echo_info( "Simscan" );
        $text .= qq (
$title

Authors: Denis Kaznadzey, Vlad Novichkov and Victor Joukov
Copyright: \(C\) 1998-2009 Denis Kaznadzey, Vlad Novichkov, Victor Joukov
License: GNU public license v3
);
        $title = &echo_info( "Patscan" );
        $text .= qq (
$title

Authors: Ross Overbeek and Morgan Price
License: Public domain.
Citation: DeSouza, M., Larsen, N. and Overbeek, R. (1997) Trends Genet. 
          Dec; 13(12):497-8.
);
    }

    $text =~ s/\n/\n /gs;
    print "$text\n";

    return;
}

sub show_messages
{
    # Niels Larsen, January 2009.

    # Creates error messages for all nodes from a given hash where keys are 
    # user:machine strings. The values are lists of three element messages:
    # [ Type, node, text ]. If called in void context are printed to STDERR
    # in tabulated form, otherwise returned. 

    my ( $msgs,      # Messages hash
         $begsp,
         $endsp,
        ) = @_;

    # Returns a string or nothing.

    my ( $acct, @rows, $row, $str );

    foreach $acct ( keys %{ $msgs } )
    {
        foreach $row ( @{ $msgs->{ $acct } } )
        {
            push @rows, [
                " ",
                &Common::Messages::colorize_key( $row->[0] ),
                $row->[1],
                "->",
                $row->[2]
            ];
        }
    }

    $str = "";

    if ( $begsp ) {
        $str .= &echo( "\n" x $begsp );
    }

    $str .= ( join "\n", &Common::Tables::render_ascii( \@rows ) ) ."\n";

    if ( $endsp ) {
        $str .= &echo( "\n" x $endsp );
    }

    if ( defined wantarray ) {
        return $str;
    } else {
        print STDERR $str;
    }

    return;
}

sub format_deletes_ascii
{
    # Niels Larsen, February 2009.
    
    # Formats delete log outputs. Returns a list of summary messages,
    # with account added as the first field.

    my ( $accts,
         $outs,
        ) = @_;

    # Returns a list.

    my ( $okstr, $warnstr, $acct, $count, $countstr, @output, @table );

    local $Common::Messages::silent = 0;

    $okstr = &echo_green( "OK" );
    $warnstr = &echo_yellow( "Warning" );

    foreach $acct ( @{ $accts } )
    {
        if ( $outs->{ $acct } )
        {
            @output = split "\n", $outs->{ $acct };
            $count = scalar @output;
            $countstr = &Common::Util::commify_number( $count );

            if ( $count > 1 ) {
                push @table, [ $acct, "$okstr - $countstr files and/or directories deleted" ];
            } elsif ( $count > 0 ) {
                push @table, [ $acct, "$okstr - $countstr file/directory deleted" ];
            } else {
                push @table, [ $acct, "$warnstr - No files or directories deleted" ];
            }
        }
    }

    if ( @table ) {
        return wantarray ? @table : \@table;
    } else {
        return;
    }
}

sub format_jobs_list_ascii
{
    # Niels Larsen, February 2009.

    # Formats jobs listing. Returns a list of fields with account added
    # as the first one.

    my ( $accts,
         $outs,
        ) = @_;

    # Returns a list.

    my ( $acct, @lines, @table, $line );

    foreach $acct ( @{ $accts } )
    {
        if ( $outs->{ $acct } )
        {
            @lines = split "\n", $outs->{ $acct };

            foreach $line ( @lines )
            {
                chomp $line;
                push @table, [ $acct, split "\t", $line ];
            }
        }
    }

    if ( @table ) {
        return wantarray ? @table : \@table;
    } else {
        return;
    }
}

sub format_jobs_stopped_ascii
{
    # Niels Larsen, February 2009.
    
    # Formats stopped jobs outputs. Returns a list of summary messages,
    # with account added as the first field.

    my ( $accts,
         $outs,
        ) = @_;

    # Returns a list.

    my ( $okstr, $warnstr, $errstr, $acct, $count, @output, @table,
         $status, $message, $line );

    local $Common::Messages::silent = 0;

    $okstr = &echo_green( "OK" );
    $warnstr = &echo_yellow( "Warning" );
    $errstr = &echo_red( "ERROR" );

    foreach $acct ( @{ $accts } )
    {
        if ( $outs->{ $acct } )
        {
            @output = split "\n", $outs->{ $acct };

            foreach $line ( @output )
            {
                ( $status, $message ) = split "\t", $line;

                if ( $status eq "OK" ) {
                    push @table, [ $acct, "$okstr - $message" ];
                } elsif ( $status eq "Error" ) {
                    push @table, [ $acct, "$errstr - $message" ];
                } elsif ( $status eq "Warning" ) {
                    push @table, [ $acct, "$warnstr - $message" ];
                } else {
                    &Common::Messages::error( qq (Wrong looking status -> "$status") );
                }
            }
        }
    }

    if ( @table ) {
        return wantarray ? @table : \@table;
    } else {
        return;
    }
}

sub format_listing_ascii
{
    # Niels Larsen, February 2009.

    # Converts native directory listings to lines of [ account, size, path ].

    my ( $accts,
         $outs,
         $args,
        ) = @_;

    # Returns a list.

    my ( $format, $acct, $list, @table, $row, $path, $dir, $size, $with_dirs, 
         $with_files );

    $with_dirs = $args->{"dirs"};
    $with_files = $args->{"files"};

    foreach $acct ( @{ $accts } )
    {
        if ( $outs->{ $acct } )
        {
            $list = &File::Listing::parse_dir( $outs->{ $acct } );
            
            if ( $list and @{ $list } )
            {
                foreach $row ( @{ $list } )
                {
                    $path = $row->[0];
                    $path =~ s/^\.?\/?//;
                    
                    if ( $row->[1] eq "f" and $with_files )
                    {
                        if ( defined $row->[2] ) {
                            $size = &Common::Util::commify_number( $row->[2] );
                        } else {
                            $size = "";
                        }
                        
                        push @table, [ $acct, $size, $path ];
                    }
                    elsif ( $row->[1] eq "d" and $with_dirs )
                    {
                        push @table, [ $acct, "---", $path ];
                    }
                    elsif ( $row->[1] =~ /^l\s+(.+)$/ )
                    {
                        push @table, [ $acct, $row->[2], "$path -> $1" ];
                    }
                }
            }
            else {
                push @table, [ $acct, "---", "" ];
            }
        }
    }

    if ( @table ) {
        return wantarray ? @table : \@table;
    } else {
        return;
    }
}

sub format_outputs_ascii
{
    # Niels Larsen, February 2009.

    # Converts outputs to lines of [ account, output line ].

    my ( $accts,
         $outs,
        ) = @_;

    # Returns a list.

    my ( $acct, @lines, $line, @table );

    foreach $acct ( @{ $accts } )
    {
        if ( $outs->{ $acct } )
        {
            @lines = split "\n", $outs->{ $acct };

            foreach $line ( @lines )
            {
                chomp $line;
                push @table, [ $acct, $line ];
            }

            push @table, [ "", "" ];
        }
    }

    pop @table;   # Remove last separation row

    if ( @table )
    {
        return wantarray ? @table : \@table;
    }
    else {
        return;
    }
}

sub format_split_ascii
{
    # Niels Larsen, February 2009.

    # Creates a list from an output hash by simple splitting.

    my ( $accts,     # Account list
         $outs,      # Outputs hash
        ) = @_;

    # Returns a list.

    my ( $acct, @table, @lines, $line );

    foreach $acct ( @{ $accts } )
    {
        if ( $outs->{ $acct } )
        {
            chomp $outs->{ $acct };
            @lines = split "\n", $outs->{ $acct };

            foreach $line ( @lines )
            {
                push @table, [ $acct, split "\t", $line ];
            }
        }
    }

    if ( @table ) {
        return wantarray ? @table : \@table;
    } else {
        return;
    }
}

sub get_files
{
    # Niels Larsen, February 2009.

    # Copies files from a given directory/file on the slaves to a directory 
    # on the master. 

    my ( $sshs,
         $args,
         $msgs,
        ) = @_;

    my ( $def_args, $l_path, @msgs, $job_id, @dirs, $silent, @accts,
         $r_basedir, $format );

    local $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> GET ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args = &Registry::Args::check(
        $args,
        {
            "AR:1" => [ qw ( from ) ],
            "S:1" => [ qw ( to ) ], 
            "S:0" => [ qw ( combine format recursive verify delete acctfile acctexpr ),
                       qw ( timeout silent nolog ) ],
        });

    $silent = $args->silent;
    $format = $args->format // "appendable";

    $def_args = {
        "combine" => 0,
        "recursive" => 1,
        "format" => undef,
        "verify" => 0,
        "delete" => 0,
        "silent" => 0,
        "nolog" => 1,
    };
    
    $args = &Common::Util::merge_params( &Storable::dclone( $args ), $def_args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERROR HANDLING <<<<<<<<<<<<<<<<<<<<<<<<<<<<
 
    if ( not $args->from or not @{ $args->from } ) {
        push @msgs, ["ERROR", qq (From-path(s) not given) ];
    }

    if ( not $args->to ) {
        push @msgs, ["ERROR", qq (To-path not given) ];
    }

    $l_path = &Cwd::abs_path( $args->to );

    if ( $l_path and -e $l_path ) {
        push @msgs, ["ERROR", qq (Output path exists: "$l_path") ];
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    local $Common::Messages::silent = $args->silent;
    
    &echo_bold( qq (\nGetting files:\n) );

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "timeout" => $args->timeout,
                "silent" => $args->silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COPY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $job_id = &Common::Util::epoch_to_time_string() .".$Get_method";

    if ( $args->combine ) {
        $l_path = &Common::Cluster::config_master_paths->{"tmp_dir"} ."/". $job_id;
    }

    $r_basedir = &Common::Cluster::config_slave_paths()->{"base_dir"};

    &Common::Cluster::copy(
        $sshs,
        {
            "message" => "Copying from slaves",
            "from" => $args->from,
            "to" => $l_path,
            "recursive" => $args->recursive,
            "method" => $Get_method,
            "job_id" => $job_id,
            "acctfile" => $args->acctfile,
            "acctexpr" => $args->acctexpr,
            "silent" => $silent,
            "nolog" => $args->nolog,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>> COMBINE AND DELETE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->combine )
    {
        @dirs = map { "$l_path/$_" } @accts;
        
        &Common::Cluster::combine_files(
            {
                "message" => "Combining files",
                "format" => $format,
                "from" => \@dirs,
                "to" => $args->to,
                "silent" => $silent,
            });

        if ( $args->delete )
        {
            &echo( qq (   Deleting scratch files ... ) );
            &Common::File::delete_dir_tree( $l_path );
            &echo_green( "done\n" );
        }
    }

    &echo_bold( qq (Finished\n) );
    
    return;
}

sub handle_messages
{
    # Niels Larsen, March 2009.

    # Shortens a common message handling practise: if an existing error list
    # is given to a routine, append to it, otherwise display it and exit. If
    # no errors it will do nothing.

    my ( $new,      # Messages
         $old,      # Old message list
         $retval,   # Value to return if there are messages - OPTIONAL, default 1
        ) = @_;

    # Returns a given value, or nothing or exits.

    $retval //= 1;

    if ( defined $new and @{ $new } )
    {
        if ( defined $old ) {
            push @{ $old }, @{ $new };
            return $retval;
        } else {
            $Common::Messages::silent = 0;
            &echo_messages( $new );
            exit;
        }
    }
    
    return;
}         

sub install_package
{
    # Niels Larsen, January 2009.

    # Copies a given programs sources to the slaves, then compiles, optionally tests, 
    # installs and optionally checks it. 

    my ( $sshs,
         $args,
        ) = @_;

    # Returns nothing.

    my ( $pkg, $command, $comp_errs );

    $args = &Registry::Args::check(
        $args,
        {
            "AR:0" => [ qw ( checks ) ],
            "S:0" => [ qw ( package force silent timeout ) ], 
        });

    $pkg = $args->package;

    $command = qq (install_analyses $pkg);
    
    if ( $args->force ) {
        $command .= " --force";
    }

    $command .= " --silent";

    ( undef, $comp_errs ) = &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Installing $pkg",
            "command" => $command,
            "timeout" => $args->timeout,
            "silent" => $args->silent,
        });

    if ( $comp_errs )
    {
        $Common::Messages::silent = 0;
        &Common::Cluster::show_messages( $comp_errs, 2, 1 );
        exit;
    }

#     if ( $args->checks )
#     {
#         # Checks. Some programs has warnings that go into stderr file and Net::OpenSSH 
#         # status check doesnt seem to work with $ssh->spawn. So here we check if the 
#         # software was actually compiled and working and then show only error messages
#         # if not,
        
#         $check_errs = &Common::Cluster::run_checks(
#             $sshs,
#             {
#                 "message" => "Verifying programs",
#                 "tests" => $args->checks,
#                 "timeout" => $timeout,
#                 "silent" => $silent,
#             });
        
#         if ( $check_errs )
#         {
#             $Common::Messages::silent = 0;
            
#             if ( $comp_errs ) {
#                 &Common::Cluster::show_messages( $comp_errs, 1, 1 );
#             } else {
#                 &Common::Cluster::show_messages( $check_errs, 1, 1 );
#             }            
            
#             exit;
#         }
#     }
    
    return;
}

sub install_packages
{
    # Niels Larsen, August 2009.

    my ( $args,
         $msgs,
        ) = @_;

    my ( $def_args, @pkgs, $pkg, @msgs, @accts, $sshs, $ssh,
         $count, $timeout, $silent, $base_dir, $command );

    $args = &Registry::Args::check(
        $args,
        {
            "AR:1" => [ qw ( packages ) ],
            "S:1" => [ qw ( acctfile acctexpr timeout force silent ) ],
        });
    
    # Merge in defaults, 

    $def_args = {
        "packages" => undef,
        "acctfile" => &Common::Cluster::accts_file,
        "acctexpr" => undef,
        "timeout" => 5,
        "force" => 0,
        "silent" => 0,
    };

    $args = &Common::Util::merge_params( &Storable::dclone( $args // {} ), $def_args );

    @pkgs = @{ $args->packages };
    $timeout = $args->timeout;
    $silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK PACKAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::Cluster::check_package_names( $args->packages );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OPEN SLAVES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    local $Common::Messages::silent = $args->silent;

    &echo_bold( qq (\nCreating slave nodes:\n) );

    $sshs = &Common::Cluster::open_ssh_connections(
        {
            "message" => "Opening connections",
            "acctfile" => $args->acctfile,
            "acctexpr" => $args->acctexpr,
            "force" => $args->force,
            "timeout" => $timeout,
            "silent" => $silent,
        });

    &echo( qq (   Ensuring keyless logins ... ) );

    $count = &Common::Cluster::open_slaves(
        $sshs,
        {
            "timeout" => $timeout,
            "silent" => 1,
        });
    
    if ( $count == 0 ) {
        &echo_green( "all ok\n" );
    } else {
        &echo_green( "$count added\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> REOPEN CONNECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<

    $sshs = &Common::Cluster::open_ssh_connections(
        {
            "acctfile" => $args->acctfile,
            "acctexpr" => $args->acctexpr,
            "force" => 1,
            "timeout" => $timeout,
            "silent" => 1,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL SYSTEM <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( grep { $_ =~ /^sys_full/i } @pkgs ) 
    {
        &Common::Cluster::install_sys_full( $sshs, $args );
    }
    elsif ( grep { $_ =~ /^sys_code/i } @pkgs ) 
    {
        &Common::Cluster::install_sys_code( $sshs, $args );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL PACKAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @pkgs = grep { $_ !~ /^sys_/ } @pkgs;

    if ( @pkgs )
    {
        foreach $pkg ( @pkgs )
        {
            &echo( qq (   Installing package $pkg ... ) );
            
            &Common::Cluster::install_package( 
                 $sshs,
                 {
                     "package" => $pkg,
                     "force" => $args->force,
                     "silent" => 1,
                     "timeout" => $args->timeout,
                 });
            
            &echo_green( "done\n" );
        }
    }
    
    &echo_bold( qq (Finished\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DISPLAY INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    @accts = &Common::Cluster::read_slaves_config( $args->acctfile, $args->acctexpr );

    push @msgs, "Perhaps now copy datasets to the slave machines with clu_put";
    push @msgs, "See available commands with clu_doc --commands";
    
    if ( grep { $_->{"password"} } @accts )
    {
        push @msgs, (
            "",
            "Consider removing passwords from the configuration file:",
            $args->acctfile,
        );
    }

    @msgs = map { ["Info", $_] } @msgs;
    
    if ( $msgs ) {
        push @{ $msgs }, @msgs;
    } else {
        &echo( "\n" );
        &echo_messages( \@msgs );
    }

    return;
}

sub install_sys_code
{
    # Niels Larsen, August 2009.
    
    # Creates a snapshot of the script code, registry files etc, copies a small tar 
    # file to all slaves and unpacks it there. No compilation is done and is quick.
    # Do this routinely for code updates.

    my ( $sshs,
         $args,
        ) = @_;

    # Returns nothing.

    my ( $master_tar, $slave_tar, $timeout, $silent, $command );

    $silent = $args->silent;
    $timeout = $args->timeout;

    &echo( qq (   Creating code snapshot ... ) );
        
    $master_tar = &Common::Admin::create_distribution(
        {
            "distrib" => "code",
            "homedir" => 0,
            "outdir" => $Common::Config::tmp_dir,
            "silent" => 1,
        });
    
    $slave_tar = &File::Basename::basename( $master_tar );
    
    &echo_green( "done\n" );
    
    &Common::Cluster::copy(
        $sshs,
        {
            "message" => "Copying shapshot archive",
            "method" => $Put_method,
            "overwrite" => 0,
            "from" => [ $master_tar ],
            "to" => "",
            "async" => 1,
            "nolog" => 1,
            "silent" => $silent,
            "timeout" => $timeout, 
        });

    &Common::File::delete_file( $master_tar );

    $command = "( zcat < $slave_tar | tar -x ) && rm -f $slave_tar";

    &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Unpacking code snapshot",
            "command" => $command,
            "timeout" => $timeout,
            "nolog" => 0,
            "silent" => $silent,
            "setenv" => 0,
        });

    return;
}

sub install_sys_full
{
    # Niels Larsen, August 2009.

    # Creates a "cluster edition" of BION, copies the tar file to all slaves
    # and installs it there. This takes up to half hour.

    my ( $sshs,
         $args,
        ) = @_;

    # Returns nothing.

    my ( $base_dir, $master_tar, $slave_tar, $timeout, $silent, 
         $command, $s_paths, @s_paths );

    $base_dir = &Common::Cluster::config_slave_paths->{"base_dir"};
    $silent = $args->silent;
    $timeout = $args->timeout;

    &echo( qq (   Creating slave distribution ... ) );
        
    $master_tar = &Common::Admin::create_distribution(
        {
            "distrib" => "cluster",
            "homedir" => 0,
            "outdir" => $Common::Config::tmp_dir,
            "silent" => 1,
        });
    
    $slave_tar = &File::Basename::basename( $master_tar );
    
    &echo_green( "done\n" );
    
    $command = 'for path in `ls -1 | grep -v Data | grep -v Jobs`; do rm -Rf "$path"; done';

    &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Deleting previous install",
            "command" => $command,
            "timeout" => $timeout,
            "nolog" => 0,
            "silent" => $silent,
            "setenv" => 0,
        });
    
    &Common::Cluster::copy(
        $sshs,
        {
            "message" => "Copying distribution file",
            "method" => $Put_method,
            "overwrite" => 0,
            "from" => [ $master_tar ],
            "to" => "/",
            "async" => 1,
            "nolog" => 1,
            "silent" => $silent,
            "timeout" => $timeout,
        });
    
    &Common::File::delete_file( $master_tar );

    $command = "( zcat < $slave_tar | tar -x ) && rm -f $slave_tar";
    
    &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Unpacking distribution",
            "command" => $command,
            "timeout" => $timeout,
            "nolog" => 0,
            "silent" => $silent,
            "setenv" => 0,
        });
    
    &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Installing (10-30 minutes)",
            "command" => "./install_software utilities --silent --noconfirm",
            "timeout" => $timeout,
            "nolog" => 0,
            "silent" => $silent,
            "setenv" => 0,
        });
    
    return;
}
    
sub list_stderrs
{
    # Niels Larsen, January 2009.

    # Reads a directory of outputs from slaves and returns a hash where keys
    # are accounts and values are the stderr text made by that account (if any).
    # A second error hash can be used to fill in undefined values if given.

    my ( $jid,    # Job ID
         $errs,   # Error hash - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( $dir, $acct, @lines, %r_errs );

    $dir = &Common::Cluster::config_master_paths->{"log_dir"} ."/$jid/stderrs";

    foreach $acct ( map { $_->{"name"} } @{ &Common::File::list_files( $dir ) } )
    {
        if ( -s "$dir/$acct" )
        {
            @lines = split "\n", ${ &Common::File::read_file( "$dir/$acct" ) };
            
            push @{ $r_errs{ $acct } }, map { [ "ERROR", $acct, $_ ] } @lines;
        }
    }

    if ( defined $errs )
    {
        foreach $acct ( keys %{ $errs } )
        {
            if ( not defined $r_errs{ $acct } )
            {
                $r_errs{ $acct } = $errs->{ $acct };
            }
        }
    }

    if ( %r_errs ) {
        return wantarray ? %r_errs : \%r_errs;
    } else {
        return;
    }
}

sub list_stdouts
{
    # Niels Larsen, January 2009.

    # Reads a directory of outputs from slaves and returns a hash where keys
    # are accounts and values are the stdout text made by that account (if any).

    my ( $jid,    # Job ID
        ) = @_;

    # Returns a hash.

    my ( $dir, $acct, %outs );

    $dir = &Common::Cluster::config_master_paths->{"log_dir"} ."/$jid/stdouts";

    foreach $acct ( map { $_->{"name"} } @{ &Common::File::list_files( $dir ) } )
    {
        if ( -s "$dir/$acct" )
        {
            $outs{ $acct } = ${ &Common::File::read_file( "$dir/$acct" ) };
        }
    }

    if ( %outs ) {
        return wantarray ? %outs : \%outs;
    } else {
        return;
    }
}

sub open_slaves
{
    # Niels Larsen, January 2009.

    # Initializes cluster nodes listed in the given file of machine and user
    # names. First, public SSH keys are copied to each node (and generated on 
    # the master machine if missing); the script will prompt for passwords for 
    # each node only this first time. Second, the "Cluster_node" file hierarchy
    # will be copied to each node. A delete option deletes files on the nodes 
    # that are not on the master (within "Cluster_node"), without the option 
    # the old files remain. Command line arguments,
    # 
    #   --nodelist   Node list file name (OPTIONAL, default accounts.list)
    #     --delete   To delete old files (OPTIONAL, default no)
    # 
    # Lines in the node list file must look like this,
    #
    # genomics.dk niels
    # 192.38.47.171 rnadk

    my ( $sshs,         # Hash of Net::OpenSSH objects - OPTIONAL
         $args,         # Arguments hash
         $msgs,         # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $ssh, @sshs, @accts, $acct, $host, $user, $ldir, $dir_path, %msgs,
         $pub_key, $tmp_file, $command, $silent, @msgs, $errs, $file, $def_args,
         $timeout, $acct_log, $tmp_path, $key_dir );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:0" => [ qw ( acctfile acctexpr force silent timeout ) ], 
        });

    # Get arguments with defaults mixed in,

    $def_args = {
        "acctfile" => &Common::Cluster::accts_file,
        "acctexpr" => undef,
        "force" => 1,
        "silent" => 0,
        "timeout" => 5,
    };

    $args = &Common::Util::merge_params( &Storable::dclone( $args // {} ), $def_args );
    
    $silent = $args->silent;
    $timeout = $args->timeout;

    local $Common::Messages::silent = $silent;

    &echo_bold( qq (\nOpening slaves:\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile,
                "acctexpr" => $args->acctexpr,
                "force" => $args->force,
                "timeout" => $timeout,
                "silent" => $silent,
            });
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE SSH PUBLIC KEY <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo( qq (   Checking master keys ... ) );
    
    if ( not -r &Common::Cluster::config_key_paths->{"private"} or 
         not -r &Common::Cluster::config_key_paths->{"public"} )
    {
        &Common::Cluster::create_keys();
        &echo_green( qq (created\n) );
    }
    else {
        &echo_green( qq (looks ok\n) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> COPY PUBLIC SSH KEYS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $pub_key = &Common::Cluster::config_key_paths->{"public"};
    $tmp_file = &Common::Cluster::config_slave_paths->{"base_dir"} .".pub_key";
    
    &Common::Cluster::copy(
        $sshs,
        {
            "from" => [ $pub_key ],
            "to" => $tmp_file,
            "method" => $Put_method,
            "async" => 1,
            "recursive" => 0,
            "timeout" => $timeout,
            "nolog" => 1,
            "message" => "Copying SSH keys",
            "silent" => $silent,
            "cdfirst" => 0,
        });
    
    # Append to and uniqify ~/.ssh/authorized_keys,

    $command = qq (mkdir -p .ssh && cd .ssh && cat ../$tmp_file >> authorized_keys);
    $command .= qq ( && cat authorized_keys | uniq | sort > authorized_keys.sorted);
    $command .= qq ( && rm authorized_keys && mv authorized_keys.sorted authorized_keys);
    $command .= qq ( && rm ../$tmp_file);

    &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Installing SSH keys",
            "command" => $command,
            "timeout" => $timeout,
            "nolog" => 1,
            "silent" => $silent,
            "cdfirst" => 0,
            "setenv" => 0,
        });
  
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TEST MODULES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         &echo( "   Testing scripts and modules ... " );
        
#         &Common::Cluster::run_command(
#             $sshs,
#             {
#                 "command" => &Common::Cluster::config_slave_paths->{"bin_dir"} ."/test_modules",
#                 "timeout" => $timeout,
#                 "nolog" => 1,
#                 "silent" => 1,
#             });

#         &echo_green( "ok\n" );
#     }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PREVENT PROMPTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $key_dir = &Common::Cluster::config_master_paths->{"key_dir"};
    
    foreach $acct ( &Common::Cluster::account_strings( $sshs ) )
    {
        $acct_log = "$key_dir/$acct";
        
        if ( not -e $acct_log ) {
            &Common::OS::run_command_backtick( qq (touch $acct_log) );
        }
    }

    &echo_bold( qq (Finished\n) );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DISPLAY INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    @accts = &Common::Cluster::read_slaves_config( $args->acctfile, $args->acctexpr );

    push @msgs, "Password-less logins now enabled on all slave nodes";
    push @msgs, "See security implications with 'clu_doc --safety'";
    push @msgs, "See available commands with 'clu_doc --commands'";
    
    if ( grep { $_->{"password"} } @accts )
    {
        push @msgs, (
            "",
            "Consider removing passwords from the configuration file:",
            $args->acctfile,
        );
    }

    @msgs = map { ["Info", $_] } @msgs;
    
    if ( $msgs ) {
        push @{ $msgs }, @msgs;
    } else {
        &echo( "\n" );
        &echo_messages( \@msgs );
    }

    return scalar @{ $sshs };
}

sub open_ssh_connections
{
    # Niels Larsen, January 2009.

    # Returns a hash of SSH connections made by the Net::OpenSSH package. The keys 
    # are the machine names or IP numbers from the given nodes file. If a defined 
    # $msgs list is given, errors will be appended to that list and be non-fatal;
    # if not, they will be printed and be fatal. 

    my ( $args,           # Arguments - OPTIONAL
         $msgs,           # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns a hash.

    my ( $def_args, @accts, $acct, $acct_str, $user, %msgs, $ssh, %opts,
         $count, $display, @msgs, $key_log, $file, $silent, @errs, $timeout, 
         @sshs, $expr, $key_dir );

    $args = &Registry::Args::check(
        $args,
        {
            "S:0" => [ qw ( acctfile acctexpr message force timeout silent ) ], 
        });

    # Get arguments with defaults mixed in,

    $def_args = {
        "async" => 1,
        "timeout" => 5,
        "message" => "",
        "force" => 1,
        "silent" => 1,
    };

    $args = &Common::Util::merge_params( &Storable::dclone( $args // {} ), $def_args );

    $display = $args->message // "";
    $file = $args->acctfile // &Common::Cluster::accts_file();
    $expr = $args->acctexpr;
    $silent = $args->silent;
    $timeout = $args->timeout;

    $timeout = undef if $timeout <= 0;

    local $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK CONFIG FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &Common::File::access_error( $file, "er" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ ACCOUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @accts = &Common::Cluster::read_slaves_config( $file, $expr );

    if ( not $args->force )
    {
        $key_dir = &Common::Cluster::config_master_paths->{"key_dir"};
        @accts = grep { not -e $key_dir ."/". $_->{"user"} ."@". $_->{"host"} } @accts;
    }

    @accts = &Common::Cluster::ask_for_passwords( \@accts );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @accts ) {
        &echo( qq (   $display ... ) );
    }

    # Create and return a sshs hash,

    %opts = (
        "async" => 1,
        "timeout" => $timeout,
        "master_opts" => [ "-q", "-o", "StrictHostKeyChecking=no" ],
        );
    
    %msgs = ();

    foreach $acct ( @accts )
    {
        $opts{"user"} = $acct->{"user"};

        if ( $acct->{"password"} ) {
            $opts{"password"} = $acct->{"password"};
        } else {
            delete $opts{"password"};
        }

        $ssh = Net::OpenSSH->new( $acct->{"host"}, %opts );

        $acct_str = $acct->{"user"} ."@". $acct->{"host"};

        if ( $ssh->error )
        {
            push @{ $msgs{ $acct_str } }, [ "ERROR", qq ($acct_str: "). $ssh->error .qq (") ];
        }
        else
        {
            push @sshs, [ $acct_str, $ssh ];
        }
    }

    if ( @accts )
    {
        $count = &Common::Util::commify_number( scalar @sshs );
        &echo_green( $count );
        
        if ( %msgs )
        {
            $count = &Common::Util::commify_number( scalar ( keys %msgs ) );
            &echo( ", " );
            &echo_red( "$count failed" );
        }
        
        &echo( "\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( %msgs )
    {
        @msgs = ();
        @errs = ();

        foreach $acct_str ( sort keys %msgs ) {
            push @errs, @{ $msgs{ $acct_str } };
        }

        if ( $msgs ) {
            push @{ $msgs }, @errs;
        } else {
            &Common::Cluster::display_connect_errors( \@errs, $file, "exit");
        }
    }

    return wantarray ? @sshs : \@sshs;
}

sub put_files
{
    # Niels Larsen, February 2009.

    # Copies the given files to all machines. 

    my ( $sshs,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing. 

    my ( $def_args, $from, @msgs, $silent, @from, %opts, $path, @accts, 
         $time_str, @files, $base_dir, @tmp );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> GET ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args = &Registry::Args::check(
        $args,
        {
            "AR:1" => [ qw ( from ) ],
            "S:1" => [ qw ( to ) ], 
            "S:0" => [ qw ( acctfile acctexpr recursive silent split format verify delete timeout ) ], 
        });

    $silent = $args->silent;

    $def_args = {
        "acctfile" => &Common::Cluster::accts_file(),
        "acctexpr" => undef,
        "recursive" => 0,
        "create" => 0,
    };

    $args = &Common::Util::merge_params( &Storable::dclone( $args ), $def_args );
    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $args->from or not @{ $args->from } ) {
        push @msgs, ["ERROR", qq (No from-path given) ];
    }

    if ( not defined $args->to ) {
        push @msgs, ["ERROR", qq (No to-path given) ];
    } elsif ( $args->to =~ m|[*&\[\]()\$\\?+;<>]| ) {
        push @msgs, ["ERROR", qq (No meta-characters allowed in to-path: ). $args->to ];
    }

    if ( $args->split and $args->split ne "size" and $args->split ne "content" ) {
        push @msgs, ["ERROR", qq (Split should be either "size" or "content") ];
    }

    if ( $args->split ) 
    {
        if ( $args->split eq "content" and not defined $args->format ) {
            push @msgs, ["ERROR", qq (Split by content requires the format argument) ];
        } elsif ( $args->format and $args->split ne "content" ) {
            push @msgs, ["ERROR", qq (Format requires the split by content argument) ];
        }            
    }
    elsif ( $args->format ) {
        push @msgs, ["ERROR", qq (Format requires the split by content argument) ];
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    # >>>>>>>>>>>>>>>>>>>>>>>>> EXPAND LOCAL PATHS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Expand from-paths perhaps with wild-cards in them to a list of file paths,

    foreach $path ( @{ $args->from } )
    {
        @tmp = &Common::File::list_files_find( $path, \@msgs );

        if ( @tmp ) {
            push @files, @tmp;
        } else {
            push @msgs, ["ERROR", qq (Empty file list for -> "$path") ];
        }
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "timeout" => $args->timeout,
                "silent" => $args->silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SPLIT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Split by file sizes or content. In each case the logic tries to make the
    # "buckets" as equally sized as possible. We do not take machine capacities
    # into account, but could; that would be application dependent, since some 
    # are disk-speed limited, others depend mostly on CPU speed or RAM size. 

    if ( $args->split )
    {
        if ( $args->split eq "size" )
        {
            @from = &Common::Cluster::split_by_size(
                \@files,
                {
                    "accounts" => \@accts,
                },
                \@msgs );
        }
        elsif ( $args->split eq "content" )
        {
            $time_str = &Common::Util::epoch_to_time_string() .".$Put_method";

            @from = &Common::Cluster::split_by_content(
                \@files,
                {
                    "accounts" => \@accts,
                    "format" => $args->format,
                    "outdir" => &Common::Cluster::config_master_paths->{"tmp_dir"} ."/$time_str",
                },
                \@msgs );
        }
    }
    else {
        @from = @files;
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COPY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    %opts = (
        "from" => \@from,
        "to" => $args->to,
        "recursive" => $args->recursive,
        "method" => $Put_method,
        "message" => "Copying files to slaves",
        "nolog" => 1,
        "timeout" => $args->timeout,
        "silent" => $silent,
        );

    &Common::Cluster::copy( $sshs, \%opts );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> VERIFY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->delete and 
         $args->split and $args->split eq "content" )
    {
        &echo( qq (   Deleting local split-files ... ) );        

        &Common::File::delete_dir_tree( &Common::Cluster::config_master_paths->{"tmp_dir"} ."/$time_str" );

        &echo_green( "done\n" );
    }

    return;
}

sub read_slaves_config
{
    # Niels Larsen, January 2009.
    
    # Parses the given file with machine names and other account information
    # and returns a list of "user:machine" strings. The second argument is a 
    # list which if given will contain possibly error messages, but if not 
    # given errors will be printed and the program will exit.

    my ( $file,            # Full file path
         $expr,            # Match expression - OPTIONAL
         $msgs,            # Outgoing list of messages - OPTIONAL
        ) = @_;

    # Returns a list.
    
    my ( @lines, $line, @accts, @msgs, $fh );

    $file //= &Common::Cluster::accts_file();

    if ( -r $file )
    {
        $fh = &Common::File::get_read_handle( $file );

        while ( $line = <$fh> )
        {
            chomp $line;

            next if $line =~ /^#/;
            next if $line !~ /\w/;

            if ( $expr and $line !~ /$expr/ ) {
                next;
            }
            
            if ( $line =~ /^\s*([^:@]+):?([^@]+)?@([^:]+):?(\d+)?\s*$/ )
            {
                push @accts, {
                    "user" => $1,
                    "password" => $2 // "",
                    "host" => $3,
                    "port" => $4 // "",
                    "line" => $line,
                };
            }
            else {
                &Common::Messages::error( qq (Wrong looking line -> "$line") );
            }
        }

        $fh->close;

        if ( not @accts ) {
            push @msgs, [ "ERROR", qq (No slave accounts found in -> "$file") ];
        }
    }
    else {
        push @msgs, [ "ERROR", qq (Configuration file not found -> "$file") ];
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    return wantarray ? @accts : \@accts;
}

sub run_command
{
    # Niels Larsen, January 2009.

    # Runs a given command on all given SSH connections and waits until they have all
    # finished. If there are local side errors (e.g. cannot connect) the remote commands 
    # are abandoned and local side error messages generated. If no local errors, remote
    # outputs and errors are saved in the Jobs directory under a given job id, appended to 
    # stdout and stderr files for each slave. If the routine is called in list context 
    # a list of ( stdout, stderr, job id ) will be returned; stdout is a hash where the
    # account is key and output value, stderr is a list of [ "ERROR", account, message ].
    # If called in scalar context only a job id will be returned, so output collection 
    # can be deferred till later. If called in void context errors are printed to STDERR
    # and the routine exits. 
    
    my ( $sshs,     # SSH connections hash
         $args,     # Arguments hash
        ) = @_;

    # Returns a string.

    my ( $job_id, $job_dir, @accts, $acct, $pid, $command, %l_errs, %w_errs, $fhs,
         $fhs_all, $ssh, $display, %pids, $r_outs, $r_errs, $log_dir, $silent, $list,
         $background, $tuple, $timeout, $base_dir, $cdfirst, $setenv );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:2" => [ qw ( command ) ], 
            "S:0" => [ qw ( message job_id acctfile acctexpr nolog silent background cdfirst setenv timeout ) ], 
        });

    $command = $args->command;
    $display = $args->message || "";
    $job_id = $args->job_id // &Common::Util::epoch_to_time_string() .".run";
    $silent = $args->silent;
    $timeout = $args->timeout;
    $cdfirst = $args->cdfirst // 1;   # IMPORTANT: default must be to cd into sandbox
    $setenv = $args->setenv // 1;

    $background = $args->background // 0;

    local $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $sshs ) 
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "message" => "Opening connections",
                "timeout" => $timeout,
                "silent" => $silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SPAWN PARALLEL PROCESSES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   $display ... ) );

    if ( not $background )
    {
        # Open stdout/stdin files in append mode,

        $log_dir = &Common::Cluster::config_master_paths->{"log_dir"} . "/$job_id";
        $fhs = &Common::Cluster::create_log_handles( $log_dir, \@accts );
    }

    # IMPORTANT: the following changes directory into the cluster node directory. This
    # makes it impossible to erase outside this directory by mistake. The '&&' between
    # commands ensure that the command will not run if cd fails or environment could 
    # not be created.

    $base_dir = &Common::Cluster::config_slave_paths->{"base_dir"};

    $command = "( $command )";

    if ( $setenv ) {
        $command = qq (eval "`cat set_env`" && $command);
    }

    if ( $cdfirst ) {
        $command = "cd $base_dir && $command";
    }

    $command = qq (sh -c 'mkdir -p $base_dir && $command');

    # Launch. Local SSH process ids are collected and waited on (reaped) below,

    foreach $tuple ( @{ $sshs } )
    {
        
        ( $acct, $ssh ) = @{ $tuple };
        
        if ( $background )
        {
            if ( not $pids{ $acct } = $ssh->spawn(
                     {
                         "stdout_discard" => 1,
                         "stderr_discard" => 1,
                     }, $command ) )
            {
                push @{ $l_errs{ $acct } }, [ "ERROR", $acct, qq (Could not spawn process) ];
            }
        }
        else
        {
            if ( not $pids{ $acct } = $ssh->spawn(
                     {
                         "stdout_fh" => $fhs->{ $acct }->{"stdout"},
                         "stderr_fh" => $fhs->{ $acct }->{"stderr"},
                     }, $command ) )
            {
                push @{ $l_errs{ $acct } }, [ "ERROR", $acct, qq (Could not spawn process) ];
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOCAL ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Handle local errors. If any we stop and do not look at remote errors, but close
    # file handles, 

    if ( %l_errs ) 
    {
        if ( not $background )
        {
            &Common::Cluster::close_handles( $fhs );
            &Common::Cluster::delete_log_dir( $job_id ) if $args->nolog;
        }

        if ( defined wantarray )
        {
            if ( wantarray ) {
                return ( (), \%l_errs, $job_id );
            } else {
                return $job_id;
            }
        }
        else {
            $Common::Messages::silent = 0;
            &Common::Cluster::show_messages( \%l_errs, 1, 1 );
            exit;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> WAIT FOR FINISH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Wait until all slave processes finished. Wait-errors usually are accompanied by
    # remote errors, so we pool them below,

    if ( $background ) {
        sleep 1;
    } else {
        %w_errs = &Common::Cluster::wait_for_finish( \%pids );
    }

    if ( %w_errs ) {
        &echo_red( "failed\n" );
    } else {
        &echo_green( "done\n" );
    }

    # Close stdout/stderr files,

    if ( $background ) {
        return;
    } else {
        &Common::Cluster::close_handles( $fhs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> HANDLE REMOTE ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $background )
    {
        $r_outs = undef;
        $r_errs = undef;
    }
    else
    {
        $r_outs = &Common::Cluster::list_stdouts( $job_id );
        $r_errs = &Common::Cluster::list_stderrs( $job_id, \%w_errs );
        
        &Common::Cluster::delete_log_dir( $job_id ) if $args->nolog;
    }

    if ( defined wantarray )
    {
        return ( $r_outs, $r_errs, $job_id );
    }
    else
    {
        if ( $r_outs ) {
            $list = &Common::Cluster::format_outputs_ascii( \@accts, $r_outs );
        }
        
        &Common::Cluster::display_outputs_ascii(
            $list,
            $r_errs,
            {
                "align" => "right,left",
            });
    }

    return;
}

sub run_program
{
    # Niels Larsen, February 2009.

    # Runs a given program on all slaves, with given local inputs, local outputs 
    # and remote datasets. 

    my ( $sshs,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $program, @msgs, $prog_path, $input, $output, $dataset, $params, $cmd,
         $pre_cmd, $post_cmd, $command, @accts, $timeout, $job_in, $errs, $outs,
         $job_id, $job_dir, $silent, $bin_dir, $base_dir, @from_dir, $from_dir,
         $job_dir_l, $prog_line );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( program inputs ) ], 
            "S:0" => [ qw ( params datasets background ), 
                       qw ( acctfile acctexpr timeout silent checkargs format ) ], 
        });

    $program = $args->program;
    $silent = $args->silent;
    $timeout = $args->timeout;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK LOCAL INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @msgs = ();
    
    if ( $args->checkargs )
    {
        &Common::Cluster::check_program_inputs( 
             {
                 "program" => $args->program,
                 "inputs" => $args->inputs,
                 "datasets" => $args->datasets,
                 "params" => $args->params,
             }, \@msgs );
        
        &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    local $Common::Messages::silent = $silent;

    &echo_bold( qq (\nStarting $program:\n) );
    
    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "timeout" => $timeout,
                "silent" => $silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check that the given dataset(s) exist on all slaves and that no more files
    # are given than what the given program can handle,

    # TODO

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE JOB DIRECTORY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $job_id = &Common::Util::epoch_to_time_string();
    $job_dir = &Common::Cluster::config_slave_paths->{"job_dir"} ."/$job_id";

    &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Creating job directory",
            "command" => "mkdir -p $job_dir",
            "job_id" => $job_id,
            "timeout" => $timeout,
            "nolog" => 1,
            "silent" => $silent,
        });
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> COMPOSE COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Substitute method name with real program name,

    $prog_line = Registry::Get->method( $program )->cmdline;
    
    if ( $prog_line =~ /^\s*([^_]+)/ )
    {
        $program = $1;
        $program =~ s/\s*$//;
    }
    else {
        &Common::Messages::error( qq (Wrong looking command line -> "$prog_line") );
    }
    
    $bin_dir = &Common::Cluster::config_slave_paths->{"bin_dir"};

    # General command line (see sclu_run, where these arguments are converted
    # to application specific command lines),
    
    $cmd = qq (sclu_run --program ). "$bin_dir/$program";

    if ( $args->params ) {
        $cmd .= qq ( --parameters "). $args->params .qq (");
    }

    $cmd .= qq ( --input "). $args->inputs .qq (");

    if ( $args->datasets ) {
        $cmd .= qq ( --dataset "). $args->datasets .qq (");
    }

    $cmd .= qq ( --output $job_dir/output);
    $cmd .= qq ( --pidfile $job_dir/pid);
    $cmd .= qq ( --begfile $job_dir/begsecs);
    $cmd .= qq ( --endfile $job_dir/endsecs);

    if ( $args->background ) {
        $cmd .= qq ( --background);
    }

    # Log the start and end times, and the program being run (used for monitoring
    # jobs),

    $pre_cmd = "echo $program > $job_dir/program";

    $job_in = &Common::Cluster::config_slave_paths()->{"job_dir"}. "/$job_id";

    if ( $args->background )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN IN BACKGROUND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Errors are sent to a file and no outputs retrieved,

        $command = qq ($pre_cmd && nice -n 19 $cmd 2> $job_dir/errors);

        &Common::Cluster::run_command( 
             $sshs,
             {
                 "message" => "Submitting $program job",
                 "command" => $command,
                 "job_id" => $job_id,
                 "acctfile" => $args->acctfile,
                 "acctexpr" => $args->acctexpr,
                 "silent" => $silent,
                 "background" => 1,
                 "nolog" => 0,
             });

        &echo( "   " );
        &echo_info( "Progress" );
        &echo( " -> " );
        &echo( qq ( clu_jobs $job_id\n) );

        &echo( "   " );
        &echo_info( "Outputs" );
        &echo( " -> " );
        &echo( qq ( clu_dir $job_in/output\n) );
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN INTERACTIVELY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Errors go to stderr and will appear on users screen. Outputs are copied back
        # into a local tree, then combined and if all goes well, the local tree is 
        # deleted,

        $command = qq ($pre_cmd && $cmd);

        &Common::Cluster::run_command(
             $sshs,
             {
                 "message" => "Running $program program",
                 "command" => $command,
                 "job_id" => $job_id,
                 "acctfile" => $args->acctfile,
                 "acctexpr" => $args->acctexpr,
                 "silent" => $silent,
                 "background" => 0,
                 "nolog" => 1,
             });

        &echo( "   " );
        &echo_info( "Output" );
        &echo( " -> " );
        &echo( qq ( clu_dir $job_in/output\n) );
    }

    return;
}

sub slave_accounts
{
    # Niels Larsen, February 2009.

    # Simply lists the accounts. 

    my ( $args,
        ) = @_;

    # Returns a list or nothing.

    my ( $file, $list );

    $args = &Registry::Args::check(
        $args,
        {
            "S:0" => [ qw ( acctfile acctexpr format ) ], 
        });

    $file = $args->acctfile // &Common::Cluster::accts_file();

    $list = &Common::Cluster::read_slaves_config( $file, $args->acctexpr );

    if ( defined wantarray )
    {
        if ( $list )
        {
            $list = [ map { $_->{"line"} } @{ $list } ];
            return wantarray ? @{ $list } : $list;
        }
        else {
            return;
        }
    }
    elsif ( $args->format eq "ascii" )
    {
        $list = [ map { [ $_->{"line"} ] } @{ $list } ];

        &echo( "\n" );
        &echo( Common::Tables->render_list( $list, { "indent" => 2 } ) );
        &echo( "\n\n" );
    }
    else {
        &Common::Messages::error( qq (Wrong looking format) );
    }

    return;
}
    
sub slave_capacities
{
    # Niels Larsen, January 2009.

    # Lists slave system capacities.

    my ( $sshs,
         $args,
         $msgs,
        ) = @_;
    
    # Returns a list or nothing.

    my ( $command, $bin_dir, $outs, $errs, $list, $silent, $format, @accts );

    $args = &Registry::Args::check(
        $args,
        {
            "S:0" => [ qw ( acctfile acctexpr format silent timeout ) ], 
        });

    $silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<    

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "timeout" => $args->timeout,
                "silent" => $silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $bin_dir = &Common::Cluster::config_slave_paths->{"bin_dir"};

    ( $outs, $errs, undef ) = &Common::Cluster::run_command(
        $sshs,
        {
            "command" => "sclu_capacity $bin_dir",
            "nolog" => 1,
            "silent" => $silent,
        });
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $list = &Common::Cluster::format_split_ascii( \@accts, $outs );

    if ( defined wantarray )
    {
        return wantarray ? @{ $list } : $list;
    }
    elsif ( $args->format eq "ascii" )
    {
        &Common::Cluster::display_outputs_ascii(
             $list,
             $errs,
             {
                 "headers" => "Account,System,CPU Ghz,Cores,RAM Gb,Free space Gb",
                 "align" => "right,right,right,right,right,right",
             });
    }
    else {
        $format = $args->format;
        &Common::Messages::error( qq (Unsupported format -> "$format") );
    }

    return;
}

sub slave_files
{
    # Niels Larsen, January 2009.

    # Lists files in various given directories. Prints a list of outputs and 
    # errors if in void context, otherwise returns them.

    my ( $sshs,
         $args,
         $msgs,
        ) = @_;

    # Returns a list or nothing, depending on context.

    my ( $dir, $command, $outs, $errs, $job_id, $list, $acct, @msgs, $display,
         $silent, @accts, $format, $timeout );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:0" => [ qw ( path acctfile acctexpr recursive dirs files format timeout silent ) ], 
        });

    $timeout = $args->timeout;

    if ( not $args->dirs and not $args->files ) {
        push @msgs, ["ERROR", qq (Please specify --dirs and/or --files) ];
    }

    &Common::Cluster::handle_messages( \@msgs, $msgs ) and return;

    $silent = $args->silent;
    local $Common::Messages::silent = $silent;

    &echo_bold( qq (\nListing files:\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<    

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "acctfile" => $args->acctfile,
                "acctexpr" => $args->acctexpr,
                "message" => "Opening connections",
                "timeout" => $timeout,
                "silent" => $silent,
            } );
    }

    
    @accts = &Common::Cluster::account_strings( $sshs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE LS COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $command = "ls -lF";

    if ( $args->recursive ) {
        $command .= "R";
    }
    
    if ( $dir = $args->path )
    {
        $dir =~ s|/$||;
        $command .= " $dir";
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    ( $outs, $errs, $job_id ) = &Common::Cluster::run_command(
        $sshs,
        {
            "message" => "Listing files",
            "command" => $command,
            "nolog" => 1,
            "timeout" => $timeout,
            "silent" => $silent,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Convert directory listing outputs to a table with errors mixed in,

    $list = &Common::Cluster::format_listing_ascii(
        \@accts,
        $outs,
        {
            "dirs" => $args->dirs,
            "files" => $args->files,
        });

    &echo_bold( qq (done\n) );
   
    if ( defined wantarray )
    {
        return ( $list, $errs );
    }
    elsif ( $args->format eq "ascii" )
    {
        &Common::Cluster::display_outputs_ascii(
            $list,
            $errs,
            {
                 "headers" => "Account,Bytes,File",
                 "align" => "right,right,left",
                 "ifnone" => "  No files",
             });
    }
    else {
        $format = $args->format;
        &Common::Messages::error( qq (Unsupported format -> "$format") );
    }        

    return;
}

sub slave_jobs
{
    # Niels Larsen, February 2009.

    # Lists jobs and their status.

    my ( $sshs,
         $args,
        ) = @_;

    # Returns a list or nothing, depending on context.

    my ( $command, $job_dir, $outs, $errs, $job_id, $list, $silent, $format,
         %fields, $fields, $stat_expr, @stat_expr, $headers, $align, $arg, $stat_col, 
         $job_expr, $job_col, @accts, $prog_expr, $prog_col, $ifnone );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( running stopped done ) ],
            "S:0" => [ qw ( jobids acctfile acctexpr program format silent timeout ) ], 
        });

    $silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    %fields = (
        "jobid" => "Job ID",
        "status" => "Status",
        "program" => "Program",
        "outsize" => "Outsize",
        "time" => "Time",
        "cpu" => "CPU",
        "pcpu" => "CPU%",
        "pmem" => "MEM%",
        "swap" => "Swap",
        );

    foreach $arg ( qw ( running stopped done ) )
    {
        if ( $args->$arg ) {
            push @stat_expr, $arg;
        }
    }
    
    $stat_expr = join "|", @stat_expr;

    if ( $args->jobids ) {
        $job_expr = join "|", split ",", $args->jobids;
    } else { 
        $job_expr = "";
    }

    $prog_expr = $args->program;

    $fields = "jobid,status,program,outsize,time,cpu,pcpu,pmem,swap";
    $align = "right,right,right,right,right,right,right,right,right";

    $stat_col = 1;
    $job_col = 0;
    $prog_col = 2;

    # >>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<    

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "timeout" => $args->timeout,
                "silent" => $silent,
            });
    }
    
    @accts = &Common::Cluster::account_strings( $sshs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $job_dir = &Common::Cluster::config_slave_paths->{"job_dir"};

    ( $outs, $errs, $job_id ) = &Common::Cluster::run_command(
        $sshs,
        {
            "command" => "sclu_jobs $job_dir",
            "nolog" => 1,
            "silent" => $silent,
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Convert directory listing outputs to a table with errors mixed in,

    $list = &Common::Cluster::format_jobs_list_ascii( \@accts, $outs, $errs );

    if ( $stat_expr ) {
        $list = [ grep { $_->[$stat_col+1] =~ /$stat_expr/i } @{ $list } ];
    }

    if ( $job_expr ) {
        $list = [ grep { $_->[$job_col+1] =~ /$job_expr/i } @{ $list } ];
    }

    if ( $prog_expr ) {
        $list = [ grep { $_->[$prog_col+1] =~ /$prog_expr/i } @{ $list } ];
    }

    if ( defined wantarray )
    {
        return ( $list, $errs );
    }
    elsif ( $args->format eq "ascii" )
    {
        $headers = join ",", map { $fields{ $_ } } split ",", $fields;
        $ifnone = "";

        if ( @stat_expr ) {
            $ifnone .= (join " or ", @stat_expr);
        }

        if ( $prog_expr ) {
            $ifnone .= " $prog_expr";
        }

        if ( $ifnone ) {
            $ifnone = "No $ifnone jobs";
        } else {
            $ifnone = "No jobs";
        }

        &Common::Cluster::display_outputs_ascii(
            $list,
            $errs,
            {
                "headers" => "Account,$headers",
                "align" => "left,$align",
                "ifnone" => $ifnone,
            });
    }
    else {
        $format = $args->format;
        &Common::Messages::error( qq (Unsupported format -> "$format") );
    }

    return;
}

sub slave_loads
{
    # Niels Larsen, January 2009.

    # Lists slave system loads.

    my ( $sshs,
         $args,
         $msgs,
        ) = @_;

    # Returns a list or nothing, depending on context.

    my ( $command, $bin_dir, $outs, $errs, $list, $silent, $format, @accts );

    $args = &Registry::Args::check(
        $args,
        {
            "S:0" => [ qw ( acctfile acctexpr format silent timeout ) ], 
        });

    $silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<    

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "timeout" => $args->timeout,
                "silent" => $silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $bin_dir = &Common::Cluster::config_slave_paths->{"bin_dir"};
    
    ( $outs, $errs, undef ) = &Common::Cluster::run_command(
        $sshs,
        {
            "command" => "sclu_load",
            "nolog" => 1,
            "silent" => $silent,
        });
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $list = &Common::Cluster::format_split_ascii( \@accts, $outs );

    if ( defined wantarray )
    {
        return wantarray ? @{ $list } : $list;
    }
    elsif ( $args->format eq "ascii" )
    {
        &Common::Cluster::display_outputs_ascii(
             $list,
             $errs,
             {
                 "headers" => "Account,System,User,CPU%,RAM%,Swap,Time,Program",
                 "align" => "right,right,right,right,right,right,right,left",
             });
    }
    else {
        $format = $args->format;
        &Common::Messages::error( qq (Unsupported format -> "$format") );
    }

    return;
}

sub slave_nodes
{
    my ( $sshs,
         $args,
        ) = @_;

    my ( $timeout, $silent, @msgs );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( capacities loads list acctfile acctexpr silent timeout ) ],
        });

    if ( $args->list )
    {
        &Common::Cluster::slave_accounts(
             {
                 "acctfile" => $args->acctfile,
                 "acctexpr" => $args->acctexpr,
                 "format" => "ascii",
             });
    }
    elsif ( $args->capacities )
    {
        local $Common::Messages::silent = $args->silent;
    
        &echo_bold( qq (\nSlave capacities:\n) );
        
        &Common::Cluster::slave_capacities(
             $sshs,
             { 
                 "acctfile" => $args->acctfile,
                 "acctexpr" => $args->acctexpr,
                 "timeout" => $args->timeout,
                 "silent" => $args->silent,
                 "format" => "ascii",
             });
        
        &echo_bold( qq (done\n\n) );
    }
    elsif ( $args->loads )
    {
        local $Common::Messages::silent = $args->silent;
    
        &echo_bold( qq (\nSlave loads:\n) );
        
        &Common::Cluster::slave_loads(
             $sshs,
             { 
                 "acctfile" => $args->acctfile,
                 "acctexpr" => $args->acctexpr,
                 "timeout" => $args->timeout,
                 "silent" => $args->silent,
                 "format" => "ascii",
             });
        
        &echo_bold( qq (done\n\n) );
    }
    else {
        @msgs = ["ERROR", qq (Either --capacities or --loads should be given) ];
    }

    if ( @msgs )
    {
        $Common::Messages::silent = 0;
        &echo_messages( \@msgs );
        exit;
    }

    return;
}

sub split_by_content
{
    # Niels Larsen, March 2009.

    # Groups the given file paths for each slave account according to content.
    # For example, if a list of sequence files are given in fasta format, then
    # the files are divided into about equal chunks for each machine. A list of 
    # [ account name, file path, file size ] is returned.

    my ( $paths,    # File path list
         $args,     # Arguments
         $msgs,     # Outgoing messages
        ) = @_;

    # Returns a list.

    require Seq::Convert;

    my ( $format, @opaths, @from );

    $args = &Registry::Args::check(
        $args,
        {
            "AR:1" => [ qw ( accounts ) ], 
            "S:1" => [ qw ( format outdir ) ],
        });

    $format = $args->format;

    @from = map { [ $_, $args->outdir ."/$_/split.part" ] } @{ $args->accounts };
    @opaths = map { $_->[1] } @from;

    if ( $args->format eq "fasta" )
    {
        &Seq::Convert::divide_chunks_fasta( $paths, \@opaths );
    }
    else {
        &Common::Messages::error( qq (Wrong looking format -> "$format") );
    }

    return wantarray ? @from : \@from;
}

sub split_by_size
{
    # Niels Larsen, March 2009.

    # Groups the given file paths for each slave account according to size. 
    # The files are grouped so the size difference between each account is 
    # minimal. A list of [ account name, file path, file size ] is returned.
    
    my ( $paths,    # File path list
         $args,     # Arguments
         $msgs,     # Outgoing messages
        ) = @_;

    # Returns a list.

    my ( @accts, $i, $j, @msgs, $msg, $bins, $path, @tuples, @groups, @outlst );

    $args = &Registry::Args::check(
        $args,
        {
            "AR:1" => [ qw ( accounts ) ], 
        });

    @accts = @{ $args->accounts };

    if ( ( $i = scalar @{ $paths } ) < ( $j = scalar @accts ) )
    {
        $msg = ["ERROR", qq (Only $i files given, but $j accounts) ];
        &Common::Cluster::handle_messages( [ $msg ], $msgs ) and return;
    }

    @tuples = map { [ $_, -s $_ ] } @{ $paths };

    @groups = &Common::Util::group_number_tuples( \@tuples, scalar @accts );

    if ( @groups == scalar @accts )
    {
        for ( $i = 0; $i <= $#groups; $i++ )
        {
            push @outlst, map { [ $accts[$i], $_->[0], $_->[1] ] } @{ $groups[$i] };
        }
    }
    else
    {
        $i = scalar @groups;
        $j = scalar @accts;

        $msg = ["ERROR", qq (There are $i groups but $j accounts) ];
        &Common::Cluster::handle_messages( [ $msg ], $msgs ) and return;
    }

    return wantarray ? @outlst : \@outlst;
}

sub stop_jobs
{
    # Niels Larsen, February 2009.

    # Stops the given job ids. 

    my ( $sshs,
         $args,
        ) = @_;

    # Returns nothing.

    my ( $silent, $timeout, $job_id, $outs, $errs, $command, $bin_dir, $job_dir,
         $delete, $list, @accts, $elem, $status );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( jobids ) ],
            "S:0" => [ qw ( acctfile acctexpr timeout silent delete message ) ], 
        });

    $silent = $args->silent;
    $timeout = $args->timeout;
    $delete = $args->delete;

    local $Common::Messages::silent = $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>> OPEN CONNECTIONS IF NOT GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<    

    if ( not $sshs )
    {
        $sshs = &Common::Cluster::open_ssh_connections(
            {
                "message" => "Opening connections",
                "acctfile" => $args->acctfile, 
                "acctexpr" => $args->acctexpr, 
                "timeout" => $timeout,
                "silent" => $silent,
            });
    }

    @accts = &Common::Cluster::account_strings( $sshs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $bin_dir = &Common::Cluster::config_slave_paths->{"bin_dir"};
    $job_dir = &Common::Cluster::config_slave_paths->{"job_dir"};

    foreach $job_id ( split ",", $args->jobids )
    {
        if ( $args->delete ) {
            $command = qq (sclu_stop $job_dir/$job_id 1);
        } else {
            $command = qq (sclu_stop $job_dir/$job_id);
        }

        ( $outs, $errs, undef ) = &Common::Cluster::run_command(
            $sshs,
            {
                "message" => "Stopping $job_id",
                "command" => $command,
                "nolog" => 1,
                "timeout" => $timeout,
                "silent" => $silent,
            });

        $list = &Common::Cluster::format_jobs_stopped_ascii( \@accts, $outs );

        &Common::Cluster::display_outputs_ascii(
            $list,
            $errs,
            {
                "align" => "right,left",
            });
    }
    
    return;
}

sub system_packages
{
    # Niels Larsen, March 2009.

    # Returns a list of [ package, one-line description ] of available
    # installable system packages.

    # Returns a list.

    my ( @pkgs, $pkg, @table );

    @table = (
        [ "sys_full", "System install, everything included" ],
        [ "sys_code", "System install, our small code only" ],
        );

    return wantarray ? @table : \@table;
}

sub wait_for_finish
{
    # Niels Larsen, January 2009.

    # Waits for all processes in a given hash of processes to finish. The 
    # account (e.g. user:machine) are hash keys, and pids values. Returns 
    # a list of errors and/or warnings if any, otherwise nothing.

    my ( $pids,          # Pid hash
        ) = @_;

    # Returns a list or nothing. 

    my ( $acct, %pids, $pid, $err, %msgs );

    foreach $acct ( keys %{ $pids } )
    {
        $pid = $pids->{ $acct };

        if ( waitpid( $pid, 0 ) > 0 )
        {
            $err = ( $? >> 8 );
            
            if ( $err ) {
                push @{ $msgs{ $acct } }, [ "ERROR", $acct, qq (Process $pid failed -> "$err" ) ];
            }
        }
        else {
            no strict;
            redo if ($! == EINTR);
            push @{ $msgs{ $acct } }, [ "Warning", $acct, qq (Waiting for process $pid failed -> "$!") ];
        }
    }

    if ( %msgs ) {
        return wantarray ? %msgs : \%msgs;
    } else {
        return;
    }

    return;
}

1;

__END__

# sub run_checks
# {
#     # Niels Larsen, January 2009.

#     # Runs a list of given commands and runs them while checking if there are errors.
#     # The list could be [ "nsimscan --help" ] for example. Errors are returned or 
#     # printed depending on context.

#     my ( $sshs,          # Hash of connections
#          $args,          # Arguments hash
#         ) = @_;

#     # Returns a list or nothing.

#     my ( $bin_dir, $user, $acct, $homedir, %errors, $cmd, $display, $ok_count,
#          $bad_count, $job_id, $r_pwds, $r_errs, $outs, $errs, $silent, @accts );

#     $args = &Registry::Args::check(
#         $args,
#         {
#             "AR:1" => [ qw ( tests ) ],
#             "S:0" => [ qw ( message job_id silent timeout ) ], 
#         });

#     $display = $args->message // "";
#     $silent = $args->silent;
#     $job_id = $args->job_id // &Common::Util::epoch_to_time_string() .".check";
    
#     local $Common::Messages::silent = $silent;

#     &echo( qq (   $display ... ) );

#     # Run the tests,
    
#     $bin_dir = &Common::Cluster::config_slave_paths->{"bin_dir"};
#     $ok_count = 0;
#     $bad_count = 0;

#     @accts = &Common::Cluster::account_strings( $sshs );
    
#     foreach $cmd ( @{ $args->tests } )
#     {
#         ( $outs, $errs ) = &Common::Cluster::run_command(
#             $sshs,
#             {
#                 "command" => "$bin_dir/$cmd",
#                 "job_id" => $job_id ."-temp",
#                 "nolog" => 1,
#                 "silent" => 1,
#             });

#         foreach $acct ( @accts )
#         {
#             if ( $errs->{ $acct } )
#             {
#                 push @{ $errors{ $acct } }, @{ $errs->{ $acct } };
#                 $bad_count += 1;
#             }
#             else {
#                 $ok_count += 1;
#             }
#         }
#     }

#     if ( $ok_count > 0 ) {
#         &echo_green( qq ($ok_count ok) );
#     }
    
#     if ( $bad_count > 0 )
#     {
#         &echo( ", " ) if $ok_count > 0;
#         &echo_red( qq ($bad_count failed) );
#     }
    
#     &echo( "\n" );

#     if ( %errors )
#     {
#         if ( defined wantarray ) {
#             return wantarray ? %errors : \%errors;
#         }
#         else
#         {
#             $Common::Messages::silent = 0;
#             &Common::Cluster::show_messages( \%errors, 1, 1 );
#             exit;
#         }
#     }
#     else {
#         return;
#     }
# }
