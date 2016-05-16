package Install::Software;     #  -*- perl -*-

# Installation related functions. They install everything, except perl
# which is done by a separate no-dependency script. 
#
# The two main routines called by the installer/uninstaller scripts are
# 
# install_software
# uninstall_software
# 
# The dispatch all software and data install options including downloads. 
#
# NOTE: there are many "require" statements in here, because the module
# is used at times where not all perl modules have been installed. If
# changed, installation will break (but there could be another module
# of course).

use strict;
use warnings FATAL => qw ( all );

use Cwd qw ( getcwd cwd abs_path );
use Sys::Hostname;
use File::Find;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_default_args
                 &ask_for_port_number
                 &build_link_map
                 &check_compilers
                 &check_install
                 &check_packages
                 &confirm_menu
                 &create_apache_config_file
                 &create_env_links
                 &create_install_dirs
                 &create_install_links
                 &create_proj_links
                 &create_missing_softdirs
                 &create_mysql5_config_file
                 &default_args
                 &delete_from_apache_config
                 &delete_install_links
                 &delete_install_dirs_if_empty
                 &delete_sources
                 &download_blast
                 &edit_files
                 &expand_tokens
                 &get_args
                 &install_analyses
                 &install_apache
                 &install_cluster
                 &install_mysql
                 &install_package
                 &install_perl_module
                 &install_perl_module_nodeps
                 &install_perl_modules
                 &install_python_module
                 &install_python_modules
                 &install_software
                 &install_utilities
                 &list_install_dirs
                 &list_software
                 &run_configure
                 &run_install
                 &run_make
                 &run_test
                 &uninstall_analyses
                 &uninstall_package
                 &uninstall_perl
                 &uninstall_post_mysql
                 &uninstall_pre_apache
                 &uninstall_pre_mysql
                 &uninstall_software
                 &uninstall_utilities
                 );

use Common::Config;
use Common::Messages;

use Common::Util;
use Common::Names;

use Registry::Get;
use Registry::Option;
use Registry::Register;
use Registry::List;
use Registry::Check;

use Install::Config;

local $| = 1;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_default_args
{
    # Niels Larsen, March 2009.

    # Pads the given parameters will defaults. 

    my ( $args,
        ) = @_;

    my ( $defs );

    $defs = &Install::Software::default_args();

    if ( not ref $args ) {
        $args = { "name" => $args };
    }

    $args = &Storable::dclone( $args );
    $args = &Common::Util::merge_params( $args, $defs );

    return wantarray ? %{ $args } : $args;
}

sub ask_for_port_number
{
    # Niels Larsen, February 2009.

    # Prompts the user for a port number. If more than a given number of seconds
    # passes, then a given default is chosen. 

    my ( $args,   
        ) = @_;

    # Returns integer. 

    my ( $port, $def_port, $min_port, $max_port, $max_wait, $prompt );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( def_port min_port max_port max_wait ) ]
        } );
    
    $def_port = $args->def_port;
    $min_port = $args->min_port;
    $max_port = $args->max_port;
    $max_wait = $args->max_wait;

  ASK_FOR_PORT:

    &echo_yellow( "\n" );
    &echo_yellow( "   A four-digit (non-secure) port number may be entered below.\n" );
    &echo_yellow( "   If none given within 10 seconds, port $def_port is used:\n" );
    &echo_yellow( "\n" );

    $prompt = &echo( "   Port number [$def_port] -> " );
    $prompt .= &echo( $port ) if defined $port;

    $port = &Common::File::read_keyboard( $max_wait, $prompt );

    if ( $port ) 
    {
        if ( $port < $min_port or $port > $max_port ) 
        {
            &echo( "\n" );
            &echo_red( "   ERROR" );
            &echo( ": Please enter a number in the range $min_port - $max_port\n" );

            undef $port;
            goto ASK_FOR_PORT;
        }
        else
        {
            &echo( "   Using port $port ... " );
            &echo_green( "ok\n\n" );
        }
    }
    else
    {
        $port = $def_port;
        &echo( "   Using port $port ... " );
        &echo_green( "ok\n\n" );
    }

    return $port;
}

sub build_link_map
{
    # Niels Larsen, May 2009

    # Creates a ( link-file => real-file ) hash for all install directories
    # and their subdirectories. The argument removes stale links (default off).

    my ( $bool,     # Deletes stale links - OPTIONAL, default off 
        ) = @_;
    
    # Returns a hash.

    my ( $map, $hash, $dir, $path );

    $bool = 0 if not defined $bool;
    $map = {};

    foreach $dir ( &Install::Software::list_install_dirs() )
    {
        $path = "$Common::Config::soft_dir/$dir";

        if ( -d $path )
        {
            $hash = &Common::File::build_link_map( $path, $bool );
            $map = { %{ $map }, %{ $hash } };
        }
    }

    return wantarray ? %{ $map } : $map;
}

sub check_compilers
{
    # Niels Larsen, January 2012. 

    # Checks for needed compilers and exits with messages if any are
    # missing. 

    my ( $msgs,
        ) = @_;

    # Returns nothing.

    my ( @msgs );

    if ( not `which gcc` and not `which cc` ) 
    {
        push @msgs, ["ERROR", qq (No C compiler found, please install one) ];
    }

    if ( not `which g++` and not `which c++` ) {
        push @msgs, ["ERROR", qq (No C++ compiler found, please install one) ];
    }

    # if ( not `which f77` and not `which gfortran` and not `which f95` ) {
    #    push @msgs, ["ERROR", qq (No Fortran compiler found, please install one) ];
    # }

    &append_or_exit( \@msgs );

    return;
}

sub check_install
{
    # Niels Larsen, April 2009.

    # Just checks if a given software name is installed and prints 
    # messages accordingly.

    my ( $name,     # Registry software name
        ) = @_;

    # Returns 1 or nothing.

    my ( $opt, $inst_name );

    $opt = Registry::Get->software( $name );
    $inst_name = $opt->inst_name;

    &echo( "   Is $inst_name installed ... " );

    if ( Registry::Register->is_registered_software( $name ) )
    {
        &echo_green( "yes\n" );

        if ( $name eq "mysql" )
        {
            require Common::Admin;
            
            if ( not &Common::Admin::mysql_is_running ) {
                &warning( "$inst_name is installed but not running" );
            }
        }

        return 1;
    }
    else {
        &echo_yellow( "NO " );
        &echo_info( "done later\n" );
    }

    return 0;
}

sub check_packages
{
    # Niels Larsen, April 2009.

    # Checks that a given list of installs are all found in the registry. 
    # Errors are returned if a list is given, otherwise printed. 

    my ( $type,     # Type of package, e.g. "perl_modules"
         $pkgs,     # Package list
         $msgs,     # Error list - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( %all, $field, $pkg, @msgs );

    %all = map { $_->name, 1 } Registry::Get->$type()->options;

    foreach $pkg ( @{ $pkgs } )
    {
        if ( not exists $all{ $pkg } ) {
            push @msgs, ["ERROR", qq (Wrong looking package name -> "$pkg") ];
        }
    }
    
    if ( @msgs )
    {
        push @msgs, [" Help", qq (The --list option shows package names) ];

        if ( $msgs and @{ $msgs } ) {
            push @{ $msgs }, @msgs;
            return;
        } else {
            &echo_messages( \@msgs, { "linewid" => 60, "linech" => "-" } );
            exit;
        }
    }

    return wantarray ? @{ $pkgs } : $pkgs;
}

sub confirm_menu
{
    my ( $names,
         $type,
         $title,
        ) = @_;

    my ( $name, $text, $prompt, $str );

    if ( $type eq "install" )
    {
        $prompt = "WILL INSTALL";
        $str = "installed";
    }
    elsif ( $type eq "uninstall" )
    {
        $prompt = "WILL UNINSTALL";
        $str = "uninstalled";
    }
    else {
        &error( qq (Wrong looking type -> "$type") );
    }

    if ( $title ) {
        &echo_bold( $title );
    } 

    foreach $name ( @{ $names } )
    {
        &echo( "   " );
        &echo_green( "$prompt" );
        &echo( "-> $name\n" );
    }
    
    $text = qq (
Are these the options to be $str? If not, please
press ctrl-C now to exit.

Otherwise the procedure will start in 10 seconds ... );

    &echo( $text );
    sleep 10;
    
    &echo_green( "gone\n" );

    return;
}

sub create_apache_config_file
{
    # Niels Larsen, August 2008.

    # Creates an Apache configuration file from the original template. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $conf, $content, $adm_dir, $log_dir, $orig_dir, $dest_dir, $file,
         $mode, $name );

    $mode = $args->{"mode"} // "modperl";
    $name = $args->{"instname"} // "Apache";

    require Common::File;
    require Install::Profile;

    $orig_dir = "$Common::Config::pki_dir/$name/conf/original";
    $dest_dir = "$Common::Config::pki_dir/$name/conf";
    $adm_dir = "$Common::Config::adm_dir/$name";
    $log_dir = "$Common::Config::log_dir/$name";

    $file = "httpd.conf";

    $content = &Install::Profile::apache_config_text(
        {
            "template" => "$orig_dir/$file",
            "log_dir" => $log_dir,
            "mode" => $mode,
            "port" => $args->{"port"},
            "home" => $args->{"home"},
            "dirs" => $args->{"dirs"},
        });

    &Common::File::delete_file_if_exists( "$dest_dir/$file" );
    &Common::File::write_file( "$dest_dir/$file", $content );

    &Common::File::create_dir_if_not_exists( $adm_dir );
    &Common::File::delete_file_if_exists( "$adm_dir/$file" );
    &Common::File::create_link( "$dest_dir/$file", "$adm_dir/$file" );

    return;
}

sub create_env_links
{
    my ( $shell, $set_file, $unset_file, $sys_dir, $reg_dir );

#    $shell = $ENV{"SHELL"};
#
#    if ( $shell =~ m|/bash$| )
#    {
#        # Bourne shell,
        
        $set_file = "set_env.sh";
        $unset_file = "unset_env.sh";
#    }
#    elsif ( $shell =~ m|/tcsh$| )
#    {
#        # Tcsh,
#        
#        $set_file = "set_env.csh";
#        $unset_file = "unset_env.csh";
#    }
#    else {
#        &echo( qq (Wrong looking shell string -> "$shell") );
#    }

    $sys_dir = $Common::Config::sys_dir;
    $reg_dir = $Common::Config::shell_dir;

    # Erase and set links,

    &Common::File::delete_file_if_exists( "$sys_dir/set_env" );
    &Common::File::create_link( "$reg_dir/$set_file", "$sys_dir/set_env" );
    
    &Common::File::delete_file_if_exists( "$sys_dir/unset_env" );
    &Common::File::create_link( "$reg_dir/$unset_file", "$sys_dir/unset_env" );

    return;
}

sub create_proj_links
{
    # Niels Larsen, October 2010.

    # If a project file is among the project templates but is not in the projects
    # directory, then this routine creates the missing links. Returns the number of
    # links made.

    # Returns integer.

    my ( $proj_dir, $tmpl_dir, $name, $count );

    $proj_dir = $Common::Config::conf_proj_dir;
    $tmpl_dir = $Common::Config::conf_projd_dir;

    foreach $name ( grep /^[a-z]+$/, map { $_->{"name"} } @{ &Common::File::list_files( $tmpl_dir ) } )
    {
        if ( not -e "$proj_dir/$name" ) {
            &Common::File::create_link( "$tmpl_dir/$name", "$proj_dir/$name" );
            $count += 1;
        }
    }
    
    return $count;
}

sub create_install_dirs
{
    # Niels Larsen, April 2009.

    # Creates the standard "man", "bin" etc directories starting at
    # a given root path.

    my ( $path,    # Starting path
        ) = @_;

    # Returns nothing.

    my ( @dirs, $dir );

    if ( $path ) {
        &Common::File::create_dir_if_not_exists( $path );
    } else {
        &error( qq (No prefix path given) );
    }

    @dirs = &Install::Software::list_install_dirs();

    foreach $dir ( @dirs )
    {
        &Common::File::create_dir_if_not_exists( "$path/$dir" );
    }

    return;
}

sub create_install_links
{
    # Niels Larsen, March 2005.

    # Creates installation links in the Software directory that point to the 
    # bin, include, etc directories of a given installed package. This makes
    # them visible in a single directory which can then be included in PATH.

    my ( $pkg,
         ) = @_;

    # Returns nothing.

    require Common::File;

    my ( $inst_dir, $dir, $path, $i, $errs, $count );

    if ( not ref $pkg ) {
        $pkg = Registry::Get->software( $pkg );
    }

    $inst_dir = $pkg->inst_dir;
    $count = 0;

    # Link to individual package install directories,

    foreach $dir ( "bin", "sbin", "include", "lib", "info", "share", "man", "cat" )
    {
        $path = "$inst_dir/$dir";

        if ( not $errs = &Common::File::access_error( $path, "edrx", 0 ) )
        {
            # A file called "dir" with useless output from 'info' sometimes 
            # appears on Mac OS X during 'make install'. To avoid name clash,
            # we delete it,

            &Common::File::delete_file_if_exists( "$path/dir" );

            $count += &Common::File::create_links_relative( $path, "$Common::Config::soft_dir/$dir", 1 );
        }
    }
    
    return $count;
}

sub create_missing_softdirs
{
    # Niels Larsen, April 2009.

    # Creates top-level installation directories.

    my ( $fatal,        # Error flag - OPTIONAL, default 0
         ) = @_;

    # Returns nothing.

    require Common::File;

    my ( $inst_dir, $dir, $i );

    $fatal = 0 if not defined $fatal;

    foreach $dir ( $Common::Config::pki_dir,
                   $Common::Config::adm_dir,
                   $Common::Config::logi_dir,
                   $Common::Config::tmp_dir,
                   $Common::Config::ses_dir )
    {
        if ( $fatal ) {
            &Common::File::create_dir( $dir );
        } else {
            &Common::File::create_dir_if_not_exists( $dir );
        }
    }

    # Install directories,
    
    &Install::Software::create_install_dirs( $Common::Config::soft_dir );

    return;
}

sub create_mysql5_config_file
{
    # Niels Larsen, August 2008.

    # Creates a MySQL configuration file from the original template. 

    my ( $inst_name,
         $port,
        ) = @_;

    # Returns nothing.

    my ( $content, $adm_dir, $etc_dir, $file );

    require Common::File;
    require Install::Profile;

    $file = "my.cnf";
    
    $etc_dir = "$Common::Config::pki_dir/$inst_name/etc";
    $adm_dir = "$Common::Config::adm_dir/$inst_name";

    $content = &Install::Profile::mysql5_config_text( $inst_name, $port );

    # Location that fits version 5,

    &Common::File::create_dir_if_not_exists( $etc_dir );
    &Common::File::delete_file_if_exists( "$etc_dir/$file" );
    &Common::File::write_file( "$etc_dir/$file", $content );

    # Link from administration directory to real file,

    &Common::File::create_dir_if_not_exists( $adm_dir );
    &Common::File::delete_links_stale( $adm_dir );
    &Common::File::delete_file_if_exists( "$adm_dir/$file" );
    &Common::File::create_link( "$etc_dir/$file", "$adm_dir/$file" );    

    return;
}

sub default_args
{
    # Niels Larsen, March 2009.

    # Returns a hash of default installation settings and values.

    # Returns a hash.

    my ( $defs );

    $defs = {
        # Package registry name,
        "name" => undef,

        # Paths, 
        "src_dir" => undef,
        "inst_dir" => undef,

        # Ports,
        "apache_port" => undef,
        "mysql_port" => undef,
        
        # Pre-install options,
        "edit_files" => {},
        "edit_files_post_config" => {},

        # General switches,
        "all" => 0,
        "existing_only" => 0,
        "force" => 0,
        "download" => 1,
        "source" => 0,
        "verbose" => 0,
        "silent" => 0,
        "indent" => undef,
        "log_file" => undef,
        "debug" => 0,
        "print_header" => 1,

        # Environment options,
        "with_local_bin_path" => 1,
        "with_local_tmp_dir" => 1,
        "with_no_perl5lib" => 0,
        "with_no_die_handler" => 0,
        "unset_env_vars" => "",

        # Configuration options,
        "with_configure" => 1,
        "configure_prepend" => undef,
        "configure_command" => undef,
        "configure_dir" => undef,
        "configure_params" => "",
        "run_autogen" => 0,

        # Make/compile options,
        "with_make" => 1,
        "make_command" => undef,
        "make_dir" => undef,
        "make_target" => undef,

        # Test options,
        "with_test" => 0,
        "test_dir" => undef,
        "test_command" => undef,

        # Install options,
        "with_install" => 1,
        "install_pre_command" => undef,
        "install_pre_function" => undef,
        "install_pre_condition" => undef,
        "install_command" => undef,
        "install_dir" => undef,
        "install_bins" => [],
        "install_docs" => [],
        "install_libs" => [],
        "install_data" => [],
        "install_post_function" => undef,
        "install_post_command" => undef,
        "delete_source_dir" => 1,

        # Uninstall options,
        "uninstall_pre_command" => undef,
        "uninstall_pre_function" => undef,
        "uninstall_pre_condition" => undef,
        "uninstall_post_command" => undef,
        "uninstall_post_function" => undef,
        };

    return wantarray ? %{ $defs } : $defs;
}

sub delete_from_apache_config
{
    # Niels Larsen, November 2007.

    # Removes a section from the given Apache configuration file (httpd.conf)
    # that loads mod_perl in PerlRun mode. 

    my ( $file,    # Absolute httpd.conf path
        ) = @_;

    # Returns nothing. 

    require Common::File;

    my ( $content, $section );

    $section = "$Common::Config::sys_name section";

    $content = ${ &Common::File::read_file( $file ) };
    $content =~ s/\s+\# \-+ $section begin.+$section end\n\n//si;

    &Common::File::delete_file( $file );
    &Common::File::write_file( $file, \$content );

    return;
}

sub delete_install_dirs_if_empty
{
    # Niels Larsen, October 2007.

    # Removes empty install directories and returns the number of deletions.

    # Returns an integer. 

    my ( @dirs, $dir, $count );

    $count = 0;

    # Directories included in paths,

    @dirs = &Install::Software::list_install_dirs();

    foreach $dir ( reverse @dirs )
    {
        if ( -e "$Common::Config::soft_dir/$dir" ) {
            $count += &Common::File::delete_dirs_if_empty( "$Common::Config::soft_dir/$dir" );
        }
    }

    # Main directories, 
        
    foreach $dir ( $Common::Config::pki_dir,
                   $Common::Config::adm_dir,
                   $Common::Config::log_dir,
                   $Common::Config::tmp_dir,
                   $Common::Config::ses_dir,
                   $Common::Config::logi_dir,
        )
    {
        if ( -e $dir ) {
            $count += &Common::File::delete_dirs_if_empty( $dir );
        }
    }
    
    return $count;
}

sub delete_install_links
{
    # Niels Larsen, May 2009.

    # Deletes all links that point into a given directory somewhere. 
    # Returns the number of links deleted. 

    my ( $dir,     # Install directory
         $map,     # Link map - OPTIONAL
        ) = @_;

    # Returns integer. 

    my ( $count, $link, $file );

    if ( not $map ) {
        $map = &Install::Software::build_link_map( 1 );
    }

    $count = 0;

    foreach $link ( keys %{ $map } )
    {
        $file = $map->{ $link };

        if ( $file =~ /^$dir/ ) 
        {
            &Common::File::delete_file( $link );
            delete $map->{ $link };

            $count += 1;
        }
    }

    return $count;
}

sub delete_sources
{
    my ( $names,
        ) = @_;

    my ( @paths, $path, @suffixes );

    @paths = map { $_->src_dir } Registry::Get->softwares( $names )->options;

    @suffixes = &Common::Names::archive_suffixes();

    foreach $path ( @paths )
    {
        &Common::File::delete_dir_tree_if_exists( $path );
            
        $path = &Common::File::append_suffix( $path, \@suffixes );
        &Common::File::delete_file_if_exists( $path );
    }

    return;
}

sub download_blast
{
    # Niels Larsen, December 2006.

    # Downloads Finds out which system and machine runs the package and returns 
    # the corresponding blast download

    my ( $pkg,         # Blast package registry name
         ) = @_;

    # Returns nothing.

    require Common::Storage;
    require Common::OS;

    my ( $src_name, $prefix, $version, $kernel, $machine, $r_dir, $r_file );
    
    &echo( "   Copying package from NCBI ... " );

    if ( not ref $pkg ) {
        $pkg = Registry::Get->software( $pkg );
    }

    $src_name = $pkg->src_name;

    if ( $src_name =~ /^([a-z]+)-(\d+\.\d+\.\d+)$/ )
    {
        $prefix = $1;
        $version = $2;
    }
    else {
        &error( qq (Wrong looking program name -> "$src_name") );
    }

    $r_dir = $pkg->url;

    if ( &Common::OS::is_linux() )
    {
        $machine = &Common::OS::get_machine_name;

        if ( $machine =~ /^i(4|5|6)86$/ ) {
            $r_file = "$prefix-$version-ia32-linux.tar.gz";
        } elsif ( $machine eq "x86_64" ) {
            $r_file = "$prefix-$version-x64-linux.tar.gz";
        } else {
            &error( qq (Wrong looking machine name -> "$machine") );
        }
    }
    elsif ( &Common::OS::is_mac_osx )
    {
        $machine = &Common::OS::get_machine_name;

        if ( $machine =~ /^i(3|4|5|6)86$/ ) {
            $r_file = "$prefix-$version-universal-macosx.tar.gz";
        } else {
            $r_file = "$prefix-$version-universal-macosx.tar.gz";
        }
    }
    else {
        $kernel = &Common::OS::get_kernel_name();
        &error( qq (Unrecognized kernel name -> "$kernel") );
    }

    &Common::File::delete_file_if_exists( "$Common::Config::ans_dir/$src_name.tar.gz" );
    &Common::Storage::copy_file( "$r_dir/$r_file", "$Common::Config::ans_dir/$src_name.tar.gz" );

    &echo_green( "done\n" );
    
    return;
}

sub edit_files
{
    # Niels Larsen, April 2009.

    # Does the specified substitutions on the given files. See the config_analyses
    # routine.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $cur_dir, $dir, $file, $edits, $edit, $content, $perm, $inst_dir, $count,
         $eval_str );

    $cur_dir = &Cwd::getcwd();

    $dir = $args->src_dir;

    if ( %{ $args->edit_files } ) {
        $edits = $args->edit_files;
    } elsif ( %{ $args->edit_files_post_config } ) {
        $edits = $args->edit_files_post_config;
    } else {
        &error( qq (Both edit_files and edit_files_post_config empty) );
    }

    $inst_dir = $args->inst_dir;

    if ( not chdir $dir ) {
        &error( qq (Could not change to directory -> "$dir") );
    }

    foreach $file ( keys %{ $edits } )
    {
        $perm = ( lstat $file )[2];
        $content = ${ &Common::File::read_file( $file ) };
        
        foreach $edit ( @{ $edits->{ $file } } )
        {
            if ( not defined $edit->[2] or eval $edit->[2] )
            {
                $edit->[1] = &Install::Software::expand_tokens( $edit->[1], $args );

                $count = ( eval "\$content =~ s|$edit->[0]|$edit->[1]|sg" );
                
                if ( ( not defined $count or $count == 0 ) and not defined $edit->[2] ) {
                    &error( 
                         qq (No edits were made in "$file" - pattern error?\n)
                         . qq ($edit->[0] -> $edit->[1]) );
                }
                
                if ( not $content ) {
                    &error( qq (Content string empty after eval) );
                }
            }
        }

        &Common::File::delete_file( $file );
        &Common::File::write_file( $file, \$content );
        
        if ( not chmod $perm, $file ) {
            &error( qq (Could not set permission $perm on file "$file") );
        }
    }

    if ( not chdir $cur_dir ) {
        &error( qq (Could not change back to directory -> "$cur_dir") );
    }

    return;
}

sub expand_tokens
{
    # Niels Larsen, April 2009.

    # Expands strings like "__SRC_DIR__" to real paths. Returns an updated
    # string. 

    my ( $str,
         $args,
        ) = @_;

    # Returns a string. 

    my ( $src_dir, $inst_dir, $src_name, $inst_name );

    $src_dir = $args->src_dir;
    $inst_dir = $args->inst_dir;

    $src_name = &File::Basename::basename( $src_dir );
    $inst_name = &File::Basename::basename( $inst_dir );

    $str =~ s/__SRC_DIR__/$src_dir/g;
    $str =~ s/__SRC_NAME__/$src_name/g;
    $str =~ s/__INST_DIR__/$inst_dir/g;
    $str =~ s/__INST_NAME__/$inst_name/g;

    $str =~ s/__BIN_DIR__/$Common::Config::bin_dir/g;
    $str =~ s/__LIB_DIR__/$Common::Config::lib_dir/g;
    $str =~ s/__INC_DIR__/$Common::Config::inc_dir/g;
    $str =~ s/__PEMI_DIR__/$Common::Config::pemi_dir/g;
    
    return $str;
}

sub get_args
{
    # Niels Larsen, March 2009.

    # If a hash of arguments are given, its keys and value types are first 
    # checked, then defaults added where keys are missing or undefined. If 
    # a key is given that is not in the defaults hash, then that is a fatal
    # error. If no hash is given, the default parameters are returned. A 
    # Registry::Args object is returned. 

    my ( $args,     # Arguments hash
        ) = @_;

    # Returns an object.

    my ( $defs, $keys, $key, $val, $ref );

    $defs = &Install::Software::default_args();

    foreach $key ( keys %{ $defs } )
    {
        $val = $defs->{ $key };

        if ( $ref = ref $val )
        {
            if ( $ref eq "ARRAY" ) {
                push @{ $keys->{"AR:0"} }, $key;
            } elsif ( $ref eq "HASH" ) {
                push @{ $keys->{"HR:0"} }, $key;
            } else {
                &error( qq (Wrong looking reference -> "$ref") );
            }
        }
        else {
            push @{ $keys->{"S:0"} }, $key;
        }
    }

    if ( $args )
    {
        $args = &Install::Software::add_default_args( $args );
        $args = &Registry::Args::check( $args, $keys );
    }
    else
    {
        $args = &Registry::Args::check( $defs, $keys );
    }

    return $args;
}

sub install_analyses
{
    # Niels Larsen, March 2005.

    # Installs the list of given analysis packages. Returns the number of 
    # packages installed.

    my ( $pkgs,     # List of packages - OPTIONAL
         $args,     # Install options hash - OPTIONAL
         $msgs,     # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns integer.

    my ( @pkgs, $name, %filter, $count, $conf, @list );

    if ( defined $pkgs and not ref $pkgs ) {
        $pkgs = [ $pkgs ];
    }

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ qw ( all force existing_only verbose silent list print_header indent download debug ) ],
        } );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND EXIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of modules and exit,

    if ( $args->list )
    {
        &Install::Software::list_software( "soft_anal", "uninstalled", $args->all );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET MODULE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all package names,

    if ( not $args->all and $pkgs and @{ $pkgs } ) {
        @list = &Install::Software::check_packages("analysis_software", $pkgs );
    } else {
        @list = Registry::Get->analysis_software()->options_names;
    }

    # With these names, get corresponding registry objects. If the "existing 
    # only" option is on, then missing packages are silently ignored; this is 
    # useful when distributing subsets of the software,

    @pkgs = Registry::Get->analysis_software(
        \@list,
        {
            "existing_only" => $args->existing_only,
        })->options;

    # Unless --force, show only uninstalled packages,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->unregistered_analyses();
        @pkgs = grep { $filter{ $_->name } } @pkgs;
    }

    return 0 if not @pkgs;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->print_header and not $args->silent ) 
    {
        &echo( "\n" );
        &echo_bold( "Installing Analyses:\n" );
    }

    $count = 0;

    $conf = {
        "force" => $args->force,
        "verbose" => $args->verbose,
        "silent" => $args->silent,
        "debug" => $args->debug,
        "download" => $args->download,
        "print_header" => 0,
    };

    foreach $name ( map { $_->name } @pkgs )
    {
        &Install::Software::install_package( $name, $conf, $msgs );
        
        $count += 1;
    }

    if ( $args->print_header and not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Register analyses install option if all analysis packages registered,

    if ( Registry::Register->are_all_registered( "soft_anal" ) )
    {
        Registry::Register->register_soft_installs( "analyses" );
    }

    return $count;
}

sub install_apache
{
    # Niels Larsen, March 2005.

    # Installs the apache version 2 www-server, edits the apache configuration 
    # scripts and launches the server. During install the user is asked for a 
    # port number; if no answer in 10 seconds, port 8080 is used. The port
    # number is returned. 

    my ( $name,      # Package name
         $args,      # Install parameters hash
         ) = @_;

    # Returns an integer.

    require Common::Admin;
    require Common::File;
    require Common::OS;
    require Term::ReadKey;

    my ( @pkgs, $pkg, $inst_name, $src_name, @loglines, $cur_dir, $soft_dir, 
         $def_port, $port, $command, $content, $conf_dir, $inst_dir, $adm_dir,
         $log_dir, $bin_dir, $link_name, $module, $www_dir, $file, @edits, 
         $edit, $params, $path, $src_dir, $args2 );

    # Check arguments and fill in defaults, 

    $args = &Install::Software::get_args( $args );    

    # Get package object,

    $pkg = Registry::Get->software( $name );

    $src_name = $pkg->src_name;
    $inst_name = $pkg->inst_name;

    # Print message,

    if ( not $args->silent )
    {
        &echo_bold( qq (\nInstalling $inst_name ($src_name):\n) );
    }

    # Set short-names,

    $conf_dir = "$Common::Config::pki_dir/$inst_name/conf";
    $inst_dir = "$Common::Config::pki_dir/$inst_name";
    $src_dir = "$Common::Config::pks_dir/$src_name";
    $adm_dir = "$Common::Config::adm_dir/$inst_name";
    $log_dir = "$Common::Config::log_dir/$inst_name";
    $bin_dir = $Common::Config::bin_dir;    

    $args->src_dir( $src_dir );
    $args->inst_dir( $inst_dir );
    $args->log_file( "$Common::Config::logi_dir/$inst_name.log" );

    # Delete log file if it exists,

    &Common::File::delete_file_if_exists( $args->log_file );

    # Ask for port number if not given, 

    if ( not $port = $args->apache_port ) 
    {
        $port = &Install::Software::ask_for_port_number(
            { 
                "def_port" => $Common::Config::http_port,
                "min_port" => 1024,
                "max_port" => 9999,
                "max_wait" => 10,
            });
    }

    {
        local $Common::Messages::silent;

        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        # Uninstall old version if force,
        
        if ( $args->force ) 
        {
            &echo( "   Un-installing previous install ... " );
            {
                $args2 = &Storable::dclone( $args );
                
                $args2->silent( 1 );
                &Install::Software::uninstall_package( $name, $args2 );
            }
            &echo_green( "done\n" );
        }
        
        # OpenSSL,
        
        if ( not Registry::Register->registered_utilities( "openssl" ) or $args->force )
        {
            $args2 = &Storable::dclone( $args );
            
            $args2->with_local_tmp_dir( 0 );
            $args2->verbose( 0 );
            $args2->print_header( 0 );
            
            &Install::Software::install_package( "openssl", $args2 );
        }
        
        # Unpacking,
        
        &echo( "   Unpacking compressed tar file ... " );
        &Common::File::unpack_archive_inplace( "$Common::Config::pks_dir/$src_name.tar.gz" );
        &echo_green( "done\n" );
        
        # Create missing install directories,
        
        &echo( "   Creating missing directories ... " );
        &Install::Software::create_missing_softdirs();
        &echo_green( "done\n" );
        
        # Configure, 
        
        &echo( "   Running GNU configure ... " );
        
        $params = "--with-mpm=prefork --with-included-apr --enable-deflate"
                 ." --enable-mods-shared=all --with-z=$Common::Config::lib_dir"
                 ." --with-expat=builtin";

        $args->configure_params( $params );
        
        &Install::Software::run_configure( $args );
        
        &echo_green( "done\n" );
        
        # Silence a bug on Mac,
        
        if ( &Common::OS::is_mac_osx() )
        {
            $file = "$Common::Config::pks_dir/$src_name/srclib/apr/include/apr.h";
            
            $content = ${ &Common::File::read_file( $file ) };
            $content =~ s|\n#define APR_HAS_SENDFILE\s+1|\n#define APR_HAS_SENDFILE          0|s;

            &Common::File::delete_file( $file );
            &Common::File::write_file( $file, $content );
        }
        
        # Build,
        
        &echo( "   Compiling (takes minutes) ... " );
        &Install::Software::run_make( $args );
        &echo_green( "done\n" );
        
        # Test,
        
        &echo( "   Testing ... " );
        &Install::Software::run_test( $args );
        &echo_green( "done\n" );
        
        # Install,
        
        $path = join "/", ( split "/", $inst_dir )[ -2 .. -1 ];
        &echo( "   Installing in $path ... " );
        &Install::Software::run_install( $args );
        &echo_green( "done\n" );
        
        # Set relative links,
        
        &echo( "   Setting relative links ... " );
        &Install::Software::create_install_links( $pkg );
        &echo_green( "done\n" );
        
        # Create document root if it doesnt exist,
        
        $www_dir = $Common::Config::www_dir;
        
        if ( not -d $www_dir )
        {
            &echo( "   Creating Document Root ... " );
            &Common::File::create_dir( $www_dir );
            &echo_green( "done\n" );
        }
        
        # Create "Sessions" and "Software" links in document root directory,
        
        &Common::File::create_dir_if_not_exists( $Common::Config::ses_dir );
        
        &Common::File::delete_file_if_exists( "$www_dir/Sessions" );
        &Common::File::create_link( $Common::Config::ses_dir, "$www_dir/Sessions" );
        
        &Common::File::delete_file_if_exists( "$www_dir/Software" );
        &Common::File::create_link( $Common::Config::soft_dir, "$www_dir/Software" );
        
        # Install mod_perl perl module,
        
        &Install::Software::install_perl_modules( "mod_perl", { "force" => 1 } );
        
        # Register Apache package,
        
        &echo( "   Registering package ... " );
        Registry::Register->register_syssoft( $name );
        &echo_green( "done\n" );
        
        Registry::Register->register_soft_installs( $name );
        
        # Delete source directory,
        
        &echo( "   Deleting source directory ... " );
        &Common::File::delete_dir_tree( $src_dir );
        &echo_green( "done\n" );

        # Write port to config file if not exists,

#        if ( not -e "$Common::Config::conf_serv_dir/apache" )
#        {
            
        
        # Starting apache also writes a mod_perl httpd.conf file,
        
        &Common::Admin::start_apache({ "mode" => "modperl", "port" => $port, "headers" => 0 });
    }

    if ( not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    return $port;
}

sub install_cluster
{
    # Niels Larsen, March 2009.

    # Installs what is needed for a cluster-only setup. 

    # Returns nothing. 

    my ( $conf_file, $reg_dir, $text, @list );

    require Common::Cluster;

    $conf_file = &Common::Cluster::accts_file();
    $reg_dir = &Common::Cluster::config_master_paths->{"reg_dir"};
    
    if ( not -e $conf_file ) {
        &Common::File::copy_file( "$conf_file.template", $conf_file );
    }
    
    system("chmod 600 $conf_file") == 0 or
        &error( qq (Could not set 600 mode on $conf_file) );
    
    system("chmod 700 $reg_dir") == 0 or
        &error( qq (Could not set 700 mode on $reg_dir) );
    
#    &echo( "\n" );
#    &Install::Software::install_env();
#    &echo( "\n" );

    $text = 
qq (Define slave machines in the configuration file 

$conf_file

Then log out and back in. When back in, run "clu_doc" to see
minimal documentation, or run "clu_open all" to set up slave 
machines with secure SSH-based connections.
);

    @list = map { [ "Next", $_ ] } split "\n", $text;
    
    &echo( "\n" );
    &echo_messages( \@list, { "linech" => "-", "linewid" => 70 } );
    
    return;
}

# sub install_mothur
# {
#     my ( $name,
#          $args,
#         ) = @_;

#     my ( $pkg, $src_name, $inst_name, $src_dir, $inst_dir, $logi_dir, $checksub,
#          $regsub, $str );

#     # Create registry package object,

#     $pkg = Registry::Get->software( $name );

#     $src_name = $pkg->src_name;
#     $inst_name = $pkg->inst_name;

#     # Print main message,

#     if ( not $args->silent )
#     {
#         $str = "Installing $inst_name";

#         if ( lc $src_name ne lc $inst_name ) {
#             $str .= " ($src_name)";
#         }
        
#         if ( $args->print_header ) {
#             &echo_bold( "\n$str:" );
#         } else {
#             &echo( "   $str ... " );
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT MAKEFILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $src_dir = "$Common::Config::ans_dir/$src_name";
#     $inst_dir = "$Common::Config::ani_dir/$inst_name";
#     $logi_dir = $Common::Config::logi_anal_dir;
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $checksub = "unregistered_$regtype";
#     $regsub = "register_$regtype";
        
#     if ( Registry::Register->$checksub( $name ) )
#     {
#         &echo( "   Adding to registry ... " );
#         Registry::Register->$regsub( $name );
#         &echo_green( "done\n" );
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE SOURCE DIR <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     if ( $args->delete_source_dir and -e $src_dir ) 
#     {
#         &echo( "   Deleting source directory ... " );
#         &Common::File::delete_dir_tree( $src_dir );
#         &echo_green( "done\n" );
#     }
    
#     &echo("");

#     &dump( $name );
#     &dump( $args );

#     return;
# }

sub install_mysql
{
    # Niels Larsen, March 2005.

    # Installs mysql. Full user rights are granted (Config/Profile/system_paths
    # lists the user and password) and the server is stopped (if running)
    # and then launched.

    my ( $name,      # Package name
         $args,      # Install parameters hash
         ) = @_;

    # Returns nothing.

    require Common::Admin;
    require Common::File;
    require Common::OS;
    require Common::DB;
    require Term::ReadKey;

    require Registry::Schema;

    my ( $pkg, $inst_name, $src_name, $login, $inst_dir, $text, $module,
         $def_port, $port, $command, $content, $conf_dir, $params, $hostname,
         $dbh, $string, $src_dir, $path, $args2, @errors, $conf, $err_file,
         $table, $sql, $log_dir, $log_file, $adm_dir, $bin_dir, @stdout, @output,
         $dat_dir, $dir, $stdout, $stderr );

    # Get configuration hash,
    
    eval qq (\$conf = Install::Config::soft_sys("$name") || {});
    
    # Check arguments and fill in defaults, 

    $args = &Install::Software::get_args( { %{ $conf }, %{ $args || {} } } );

    # Set names and make sure main directories exist, 

    $pkg = Registry::Get->software( $name );

    $src_name = $pkg->src_name;
    $inst_name = $pkg->inst_name;

    # Print message,

    if ( not $args->silent ) {
        &echo_bold( qq (\nInstalling $inst_name ($src_name):\n) );
    }

    # Set short-names, 

    $bin_dir = $Common::Config::bin_dir;
    $src_dir = "$Common::Config::pks_dir/$src_name";
    $inst_dir = "$Common::Config::pki_dir/$inst_name";
    $adm_dir = "$Common::Config::adm_dir/$inst_name";
    $log_dir = "$Common::Config::log_dir/$inst_name";
    $dat_dir = "$Common::Config::dat_dir/$inst_name";

    $args->src_dir( $src_dir );
    $args->inst_dir( $inst_dir );
    $args->log_file( "$Common::Config::logi_dir/$inst_name.log" );

    # Delete log file if it exists,

    &Common::File::delete_file_if_exists( $args->log_file );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PORT NUMBER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Ask for port number if not given,

    if ( not $port = $args->mysql_port ) 
    {
        local $Common::Messages::silent = 0;

        $port = &Install::Software::ask_for_port_number(
            { 
                "def_port" => $Common::Config::db_port,
                "min_port" => 1024,
                "max_port" => 9999,
                "max_wait" => 10,
            });
    }

    {
        local $Common::Messages::silent;

        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> UNINSTALL OLD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->force ) 
        {
            &echo( "   Un-installing previous install ... " );
            {
                $args2 = &Storable::dclone( $args );
                
                $args2->silent( 1 );
                &Install::Software::uninstall_package( $name, $args2 );
            }
            &echo_green( "done\n" );
        }
    
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNPACK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
        &echo( "   Unpacking compressed tar file ... " );
        &Common::File::unpack_archive_inplace( "$Common::Config::pks_dir/$src_name.tar.gz" );
        &echo_green( "done\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT CONFIG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # There is a 'skip-federated' statement in the supplied config files that 
        # makes server refuse to start,
        
        if ( %{ $args->edit_files } )
        {
            &echo( "   Editing config files ... " );
            &Install::Software::edit_files( $args );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE DIRS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Creating missing directories ... " );
        &Install::Software::create_missing_softdirs();
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> MODIFY ENVIRONMENT <<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Change the environment to become a minimal one with mysql-needed things
        # added. A local copy ensures it will revert back to what it what after
        # this install is done.

        local %ENV = %ENV;
        &Common::Config::unset_env_variables();

        $ENV{"CC"} = "gcc";
        $ENV{"CFLAGS"} = "-O3";
        $ENV{"CXX"} = "gcc";
        $ENV{"CXXFLAGS"} = "-O3 -felide-constructors -fno-exceptions -fno-rtti";
        $ENV{"MYSQL_HOME"} = $inst_dir;

        &Common::Config::set_env_variable( "LDFLAGS", [ "-L$Common::Config::lib_dir" ] );
        &Common::Config::set_env_variable( "PATH", [ $Common::Config::bin_dir ] );
        &Common::Config::set_env_variable( "CURSES_LIBRARY", [ $Common::Config::lib_dir ] );
        &Common::Config::set_env_variable( "CURSES_INCLUDE_PATH", [ $Common::Config::inc_dir ] );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIGURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Running GNU configure ... " );

        # This is for 5.5.* only, where also other things break:
        # &Common::OS::run3_command("$src_dir/BUILD/autorun.sh", undef, \$stdout, \$stderr );
        
        $params = "";
        $params .= " --prefix=$inst_dir";
        $params .= " --localstatedir=$dat_dir/mysql";
        $params .= " --with-unix-socket-path=$Common::Config::db_sock_file";

        if ( &Common::OS::is_mac_osx() ) {
            $params .= " --enable-assembler=no";
        } else {
            $params .= " --enable-assembler";
        }
        
        $params .= " --enable-local-infile";
        $params .= " --enable-thread-safe-client";
#        $params .= " --disable-shared";
#        $params .= " --without-plugin-innobase";
        $params .= " --with-plugins=myisam";
        $params .= " --with-pthread";
#        $params .= " --with-raid";
        $params .= " --without-debug";
#        $params .= " --with-mysqld-ldflags=-all-static";  # Version 5
        
        $args->configure_params( $params );

        &Install::Software::run_configure( $args );
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Compiling (takes minutes) ... " );
        &Install::Software::run_make( $args );
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Stop server if running, 

        if ( &Common::Admin::mysql_is_running() ) {
            &Common::Admin::stop_mysql({ "headers" => 0 });
        }

        $path = join "/", ( split "/", $inst_dir )[ -2 .. -1 ];
        &echo( "   Installing in $path ... " );
        &Install::Software::run_install( $args );
        &echo_green( "done\n" );

        # Reset environment,
        
        &Common::Config::set_env_variables();
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET LINKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Setting relative links ... " );

        &Install::Software::create_install_links( $pkg );

        &Common::File::delete_file_if_exists( "$bin_dir/mysql.server" );
        &Common::File::create_link( "$inst_dir/share/mysql/mysql.server", "$bin_dir/mysql.server" );
        
        &Common::File::delete_file_if_exists( "$bin_dir/mysqld" );
        &Common::File::create_link( "$inst_dir/libexec/mysqld", "$bin_dir/mysqld" );
        
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE CONFIGURATION <<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Creating server configuration ... " );
        &Install::Software::create_mysql5_config_file( $inst_name, $port );
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOG DIR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Creating log directory ... " );
        &Common::File::create_dir_if_not_exists( "$Common::Config::log_dir/$inst_name" );
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>> INITIALIZE DATA DIRECTORY <<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Initializing server files ... " );
        
        &Common::File::create_dir_if_not_exists( $dat_dir );

        $hostname = &Sys::Hostname::hostname();

        $command = "$bin_dir/mysql_install_db --no-defaults";
#        $command = "$bin_dir/mysql_install_db";
        $command .= " --datadir=$dat_dir --basedir=$inst_dir";

        if ( &Common::OS::is_mac_osx() )
        {
            $command .= " --lower_case_table_names=2";          # Mac OS X wants that
            $command .= " --log-bin=$hostname-bin";             # Another Mac complaint silenced
        }

        @stdout = &Common::OS::run_command( $command );
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> START SERVER <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Can we launch the server ... " );

        $err_file = &Common::Admin::start_mysql( { "headers" => 0, "stopold" => 0, "silent" => 1 } );

        &Common::OS::run_command( "$bin_dir/mysqladmin -u root variables", undef, \@errors );

        if ( -r ( $log_file = "$log_dir/mysql_errors.log" ) )
        {
            $text = ${ &Common::File::read_file( $log_file ) };
            
            if ( $text =~ /ready for connection/s ) {
                &echo_green( "yes, running\n" );
            } else { 
                &echo_red( "NO\n" );
                &echo_red( "   Errors in $err_file\n" );
                &error( "Initial MySQL server launch failed" );
            }
        }
        else {
            &error( qq (Log file missing -> "$log_dir/mysql_errors.log") );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> ADMINISTRATOR PASSWORD <<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Setting administrator password ... " );
        
        $command = "$bin_dir/mysqladmin --user=root password $Common::Config::db_root_pass";
        &Common::OS::run_command( $command );
        
        sleep 1;
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> USER RIGHTS <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Giving user mysql access rights ... " );
        
        foreach $hostname ( "localhost", &Sys::Hostname::hostname() )
        {
            $sql = "GRANT ALL PRIVILEGES ON *.* TO '$Common::Config::db_user'\@'$hostname' IDENTIFIED BY ";
            $sql .= "'$Common::Config::db_pass' WITH GRANT OPTION;";
            
            $command = "$bin_dir/mysql --user=root --password=$Common::Config::db_root_pass --execute=\"$sql\"";
            &Common::OS::run_command( $command );
            sleep 1;
        }

        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL PERL MODULE <<<<<<<<<<<<<<<<<<<<<<<
        
        &Install::Software::install_perl_modules( "DBD-mysql", { "force" => 1 } );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK PERL ACCESS <<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Can we retrieve from Perl ... " );
        $dbh = &Common::DB::connect( $name );

        @output = &Common::DB::query_array( $dbh, "SELECT Host,Db,User FROM db" );

        &Common::DB::disconnect( $dbh );
        &echo_green( "yes\n" );
        
        &echo( "   Can we store from Perl ... " );
        
        &Common::DB::create_database_if_not_exists( "make_test" );
        $dbh = &Common::DB::connect("make_test");
        
        $table = Registry::Schema->get("system")->table("db_test");

        &Common::DB::create_table( $dbh, $table );
        &Common::DB::add_row( $dbh, $table->name, [ 1, 2 ] );
        &Common::DB::delete_table( $dbh, $table->name );
        
        &Common::DB::delete_database( $dbh, "make_test" );
        
        &Common::DB::disconnect( $dbh );
        &echo_green( "yes\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Registering package ... " );
        Registry::Register->register_syssoft( $name );
        &echo_green( "done\n" );

        Registry::Register->register_soft_installs( $name );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLEAN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Deleting source directory ... " );
        &Common::File::delete_dir_tree( $src_dir );            
        &echo_green( "done\n" );
    }

    if ( not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    return $port;
}

sub install_package
{
    # Niels Larsen, April 2009.

    # Installs a package. There are a number of configurations and switches, 
    # but having package installation in a single routine is preferable to 
    # duplicated code. 

    my ( $name,        # Package name
         $args,        # Install options hash - OPTIONAL
         ) = @_;

    # Returns nothing. 

    require Common::File;
    require Common::OS;

    my ( $pkg, $src_name, $inst_name, $src_dir, $bool, $count, $code,
         $path, $inst_dir, $datatype, $routine, $logi_dir, $cmd, $checksub,
         $regsub, $regtype, $str, $conf );

    &Common::Messages::block_public_calls( __PACKAGE__ );

    # Create registry package object,

    $pkg = Registry::Get->software( $name );

    $src_name = $pkg->src_name;
    $inst_name = $pkg->inst_name;
    $datatype = $pkg->datatype;

    # Get configuration hash,
    
    $routine = qq (Install::Config::$datatype( "$name" ));
    eval "\$conf = $routine || {}";

    &error( $@ ) if $@;
    
    # Check arguments and fill in defaults, 

    $args = &Install::Software::get_args( { %{ $conf }, %{ $args || {} } } );

    # Print main message,

    if ( not $args->silent )
    {
        $str = "Installing $inst_name";

        if ( lc $src_name ne lc $inst_name ) {
            $str .= " ($src_name)";
        }

        if ( $args->print_header ) {
            &echo_bold( "\n$str:" );
        } else {
            &echo( "   $str ... " );
        }
    }

    # Modify environment. Some packages wont compile when we add our bin
    # to the path, no idea why. So we save them here and restore at the 
    # end of this routine,

    local %ENV = %ENV;

    if ( not $args->with_local_bin_path ) {
        $ENV{"PATH"} =~ s|$Common::Config::soft_dir/bin:||g;
    }

    if ( $args->with_local_tmp_dir ) {
        $ENV{"TMPDIR"} = $Common::Config::tmp_dir;
    }

    # Set source, install and log directories,
    
    if ( $datatype eq "soft_sys" )
    {
        $src_dir = "$Common::Config::pks_dir/$src_name";
        $inst_dir = "$Common::Config::pki_dir/$inst_name";
        $logi_dir = $Common::Config::logi_dir;
        $regtype = "syssoft";
    }
    elsif ( $datatype eq "soft_anal" )
    {
        $src_dir = "$Common::Config::ans_dir/$src_name";
        $inst_dir = "$Common::Config::ani_dir/$inst_name";
        $logi_dir = $Common::Config::logi_anal_dir;
        $regtype = "analyses";
    }
    elsif ( $datatype eq "soft_util" )
    {
        $src_dir = "$Common::Config::uts_dir/$src_name";
        $inst_dir = "$Common::Config::uti_dir/$inst_name";
        $logi_dir = $Common::Config::logi_util_dir;
        $regtype = "utilities";
    }
    else {
        &error( qq (Wrong looking package datatype -> "$datatype") );
    }

    $args->src_dir( $src_dir );
    $args->inst_dir( $inst_dir );

    # Set install log file name, delete if exists and create directory if missing,

    $args->log_file( "$logi_dir/". $pkg->inst_name .".log" );
    
    &Common::File::delete_file_if_exists( $args->log_file );
    &Common::File::create_dir_if_not_exists( $logi_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    {
        # Control screen display settings, made local so they revert back,

        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;

        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        if ( defined $args->indent ) {
            $Common::Messages::indent_plain = $args->indent;
        } else {
            $Common::Messages::indent_plain = 3;
        }
        
        &echo( "\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>> PRE-CONDITION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $args->download and $routine = $args->install_pre_condition )
        {
            eval "\$bool = $routine";

            &error( $@ ) if $@;

            if ( not $bool ) 
            {
                if ( not $args->silent ) { 
                    &echo_yellow( "skipped\n" );
                }

                return;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->download and $routine = $args->install_pre_command )
        {
            &echo( qq (   Running pre-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->install_pre_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->download and $routine = $args->install_pre_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNPACK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Here we assume the directory created is named as the archive minus 
        # its compressed file suffix; sometimes it is necessary to fix this by
        # untarring, renaming and retarring,

        &echo( "   Unpacking source archive ... " );
        $path = &Common::File::append_suffix( $src_dir, [ qw ( .tar.gz .tgz .tar.bz2 .zip ) ] );
        &Common::File::unpack_archive_inplace( $path );
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( %{ $args->edit_files } )
        {
            &echo( "   Editing files ... " );
            &Install::Software::edit_files( $args );
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIGURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->with_configure )
        {
            &echo( "   Configuring (patience) ... " );
            &Install::Software::run_configure( $args );
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( %{ $args->edit_files_post_config } )
        {
            &echo( "   Editing files ... " );
            &Install::Software::edit_files( $args );
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BUILD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->with_make )
        {
            &echo( "   Compiling (may take minutes) ... " );
            &Install::Software::run_make( $args );
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TEST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->with_test )
        {
            &echo( "   Testing (patience) ... " );
            &Install::Software::run_test( $args );
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> REMOVE OLD <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->force )
        {
            &echo( "   Removing previous install ... " );
            {
                &Install::Software::uninstall_package( $name, { %{ $args }, "silent" => 1, "delete_source_dir" => 0 } );
            }
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &Install::Software::create_install_dirs( $inst_dir );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->with_install ) 
        {
            $path = join "/", ( split "/", $inst_dir )[ -2 .. -1 ];
            &echo( "   Installing in $path ... " );
            &Install::Software::run_install( $args );        
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LINKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Setting relative links ... " );
        $count = &Install::Software::create_install_links( $pkg );

        if ( $count > 0 ) {
            &echo_green( &Common::Util::commify_number( $count ) ."\n" );
        } else {
            &echo_yellow( "NONE\n" );
        }            
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> POST FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_post_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> POST COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->install_post_command )
        {
            &echo( qq (   Running post-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->install_post_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }        
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $checksub = "unregistered_$regtype";
        $regsub = "register_$regtype";
        
        if ( Registry::Register->$checksub( $name ) )
        {
            &echo( "   Adding to registry ... " );
            Registry::Register->$regsub( $name );
            &echo_green( "done\n" );
        }

        # Make checks,
        
        # TODO 
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE SOURCE DIR <<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->delete_source_dir and -e $src_dir ) 
        {
            &echo( "   Deleting source directory ... " );
            &Common::File::delete_dir_tree( $src_dir );
            &echo_green( "done\n" );
        }

        &echo("");
    }

    if ( not $args->silent )
    {
        if ( $args->print_header ) {
            &echo_bold( "Finished\n" );
        } else {
            &echo_green( "done\n" );
        }
    }

    return 1;
}

sub install_perl_module
{
    # Niels Larsen, April 2009.

    # Installs a perl module. There are a number of configurations and switches, 
    # but having package installation in a single routine is preferable to 
    # duplicated code. 
    
    my ( $name,       # Module name
         $args,       # Install options hash - OPTIONAL
         ) = @_;

    # Returns nothing.

    require Common::File;
    require Common::OS;

    my ( $datatype, $src_dir, $cmd, $options, $pkg, $src_name, $inst_name, $conf, 
         $inst_dir, $perl5lib, $errsub, $routine, $bool );

    # &dump( \@INC );
    # &dump([ split ":", $ENV{"PERL5LIB"} ]);

    &Common::Messages::block_public_calls( __PACKAGE__ );

    # Create registry object from name,

    $pkg = Registry::Get->perl_modules( $name );

    $src_name = $pkg->src_name;
    $inst_name = $pkg->inst_name;
    $datatype = $pkg->datatype;

    $src_dir = "$Common::Config::pems_dir/$src_name";
    $inst_dir = "$Common::Config::pemi_dir/$inst_name";

    # Get configuration hash,
    
    $routine = qq (Install::Config::$datatype( "$name" ));
    eval "\$conf = $routine || {}";

    # Check arguments and fill in defaults, 

    $args = &Install::Software::get_args( { %{ $conf }, %{ $args || {} } } );

    if ( not $args->silent ) {
        &echo( qq (   Installing $src_name ... ) );
    }

    # Set source and install directories,
    
    $args->src_dir( $src_dir );
    $args->inst_dir( $inst_dir );
    
    # Set install log file name, delete if exists and create directory if missing,

    $args->log_file( "$Common::Config::logi_pems_dir/$src_name" );
    
    &Common::File::delete_file_if_exists( $args->log_file );
    &Common::File::create_dir_if_not_exists( $Common::Config::logi_pems_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>> PRE-CONDITION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_pre_condition )
        {
            { 
                local $Common::Messages::silent = 1;
                eval "\$bool = $routine";
            }

            if ( not $bool and not $args->force ) 
            {
                if ( not $args->silent ) { 
                    &echo_yellow( "delayed\n" );
                }

                return;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> DISPLAY SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<

        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;
        
        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }

        if ( defined $args->indent ) {
            $Common::Messages::indent_plain = $args->indent;
        } else {
            $Common::Messages::indent_plain = 3;
        }

        &echo( "\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_pre_command )
        {
            &echo( qq (   Running pre-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->install_pre_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_pre_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNPACK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Unpacking source archive ... " );
        &Common::File::unpack_archive_inplace( "$src_dir.tar.gz" );
        &echo_green( "done\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( %{ $args->edit_files } )
        {
            &echo( "   Editing files ... " );
            &Install::Software::edit_files( $args );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> SET ENVIRONMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Some modules, like PDL, does not want PERL5LIB set when installing,

        local %ENV = %ENV;

        if ( $args->with_no_perl5lib ) 
        {
            $perl5lib = $ENV{"PERL5LIB"};
            delete $ENV{"PERL5LIB"};
        }

        # Some modules, like PDL and BioPerl, rely on capturing errors during
        # install, which would trigger our error handler. We undefine it then,

        local $SIG{__DIE__};

        if ( $args->with_no_die_handler )
        {
            $errsub = $SIG{__DIE__};
            $SIG{__DIE__} = sub { return };
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIGURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->with_configure )
        {
            &echo( "   Configuring ... " );
            &Install::Software::run_configure( $args );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TEST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->with_test )
        {
            &echo( "   Testing ... " );
            &Install::Software::run_test( $args );
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BUILD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $args->with_make )
        {
            &echo( "   Building ... " );
            &Install::Software::run_make( $args );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> REVERT ENVIRONMENT <<<<<<<<<<<<<<<<<<<<<<<

        # Reset PERL5LIB is deleted,

        if ( $perl5lib ) {
            $ENV{"PERL5LIB"} = $perl5lib;
        }

        # Reset error handler if deleted,

        if ( $errsub ) {
            $SIG{__DIE__} = $errsub;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $args->with_install )
        {
            &echo( "   Installing ... " );
            &Install::Software::run_install( $args );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> POST COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->install_post_command )
        {
            &echo( qq (   Running post-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->install_post_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }        
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> POST-FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_post_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Registering ... " );
        Registry::Register->register_perl_modules( $name );
        &echo_green( "done\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE SOURCE DIR <<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->delete_source_dir ) 
        {
            &echo( "   Deleting sources ... " );
            &Common::File::delete_dir_tree( $src_dir );
            &echo_green( "done\n" );
        }
        
        &echo("");
    }

    if ( not $args->silent )
    {
        # Should really check if module can be loaded
#         eval {
#             local $SIG{__DIE__} = undef;
#             require Lingua::Stem::Snowball;
#         };

        &echo_green( "done\n" );
    }

    return;
}

sub install_perl_module_nodeps
{
    # Niels Larsen, November 2007.

    my ( $name,    # Module name
        ) = @_;

    # Returns nothing.

    require Common::File;

    my ( $module, $orig_dir, $dir, $options );

    $orig_dir = &Cwd::getcwd();

    $module = Registry::Get->perl_modules( $name )->src_name;

    &echo( "   Installing $module ... " );

    $dir = "$Common::Config::pems_dir";

    if ( not chdir $dir ) {
        &error( qq (Could not change to directory -> "$dir") );
    }

    &Common::File::delete_dir_tree_if_exists( "$dir/$module" );

    system( "tar -xzf $dir/$module.tar.gz > /dev/null" );

    if ( not chdir $module ) {
        &error( qq (Could not change to directory -> "$dir/$module") );
    }

    system( "perl Makefile.PL INSTALL_BASE=$Common::Config::pemi_dir > /dev/null " );
    system( "make > /dev/null" );
    system( "make install > /dev/null" );

    chdir $orig_dir;

    &Common::File::delete_dir_tree( "$dir/$module" );

    Registry::Register->register_perl_modules( $name );

    &echo_green( "done\n" );

    return;
}

sub install_perl_modules
{
    # Niels Larsen, April 2009.

    # Installs perl modules, either those in a given list, or if no list, all 
    # those that remain to be installed. Most modules install the standard way,
    # but some have deviations and exceptions which this function handles. The
    # number of installed modules is returned. 

    my ( $pkgs,     # List of modules
         $args,     # Argument hash - OPTIONAL
         $msgs,     # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns integer.

    my ( @names, $pkg, %filter, $count, $field, @list, $name, $filter, $regexp,
         @table, @names_nodeps );

    if ( defined $pkgs and not ref $pkgs ) {
        $pkgs = [ $pkgs ];
    }

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ qw ( all force existing_only verbose silent list print_header download debug ) ],
        } );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND EXIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of modules and exit,

    if ( $args->list )
    {
        &Install::Software::list_software( "soft_perl_module", "uninstalled", $args->all );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET MODULE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all package names,

    if ( not $args->all and $pkgs and @{ $pkgs } ) {
        @list = &Install::Software::check_packages("perl_modules", $pkgs );
    } else {
        @list = Registry::Get->perl_modules()->options_names;
    }

    # With these names, get corresponding registry objects. If the "existing 
    # only" option is on, then missing modules are silently ignored; this is 
    # useful when distributing subsets of the software,

    @names = map { $_->name } Registry::Get->perl_modules(
        \@list,
        {
            "existing_only" => $args->existing_only,
        })->options;
    
    # Unless --force, filter away installed packages,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->unregistered_perl_modules();
        @names = grep { $filter{ $_ } } @names;
    }

    # Return if nothing to install,

    return if not @names;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->print_header and not $args->silent ) 
    {
        &echo( "\n" );
        &echo_bold( "Installing Perl modules:\n" );
    }

    &Common::File::create_dir_if_not_exists( $Common::Config::logi_pems_dir );
    &Common::File::create_dir_if_not_exists( $Common::Config::tmp_dir );

    $count = 0;

    # Separate modules that need be installed early, and do those first,

    $regexp = "Shell|IPC-Run3|Data-Table|Config-General|Proc-Reliable";

    @names_nodeps = grep { $_ =~ /^$regexp$/ } @names;
    @names = grep { $_ !~ /^$regexp$/ } @names;

    foreach $name ( @names_nodeps )
    {
        &Install::Software::install_perl_module_nodeps( $name );
        $count += 1;
    }

    # Then the rest,

    foreach $name ( @names )
    {
        &Install::Software::install_perl_module(
            $name,
            {
                "force" => $args->force,
                "verbose" => $args->verbose,
                "silent" => $args->silent,
                "debug" => $args->debug,
                "print_header" => 0,
            },
            $msgs );
    
        $count += 1;
    }

    if ( $args->print_header and not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    # Register perl modules option if all modules registered,

    if ( Registry::Register->are_all_registered( "soft_perl_module" ) )
    {
        Registry::Register->register_syssoft( "perl_modules" );
        Registry::Register->register_soft_installs( "perl" );
    }

    return $count;
}

sub install_python_module
{
    # Niels Larsen, November 2010.

    # Installs a python module. There are a number of configurations and 
    # switches,  but having package installation in a single routine is good.
    
    my ( $name,       # Module name
         $args,       # Install options hash - OPTIONAL
         ) = @_;

    # Returns nothing.

    require Common::File;
    require Common::OS;

    my ( $datatype, $src_dir, $cmd, $options, $pkg, $src_name, $inst_name, $conf, 
         $inst_dir, $perl5lib, $errsub, $routine, $bool );

    &Common::Messages::block_public_calls( __PACKAGE__ );

    # Create registry object from name,

    $pkg = Registry::Get->python_modules( $name );

    $src_name = $pkg->src_name;
    $inst_name = $pkg->inst_name;
    $datatype = $pkg->datatype;

    $src_dir = "$Common::Config::pyms_dir/$src_name";
    $inst_dir = "$Common::Config::pymi_dir/$inst_name";

    # Get configuration hash,
    
    $routine = qq (Install::Config::$datatype( "$name" ));
    eval "\$conf = $routine || {}";

    &error( $@ ) if $@;

    # Check arguments and fill in defaults, 
    
    $args = &Install::Software::get_args( { %{ $conf }, %{ $args || {} } } );

    if ( not $args->silent ) {
        &echo( qq (   Installing $src_name ... ) );
    }

    # Set source and install directories,
    
    $args->src_dir( $src_dir );
    $args->inst_dir( $inst_dir );
    
    # Set install log file name, delete if exists and create directory if missing,

    $args->log_file( "$Common::Config::logi_pyms_dir/$src_name" );
    
    &Common::File::delete_file_if_exists( $args->log_file );
    &Common::File::create_dir_if_not_exists( $Common::Config::logi_pyms_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>> PRE-CONDITION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_pre_condition )
        {
            { 
                local $Common::Messages::silent = 1;
                eval "\$bool = $routine";

                &error( $@ ) if $@;
            }

            if ( not $bool and not $args->force ) 
            {
                if ( not $args->silent ) { 
                    &echo_yellow( "delayed\n" );
                }

                return;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> DISPLAY SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<

        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;
        
        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }

        if ( defined $args->indent ) {
            $Common::Messages::indent_plain = $args->indent;
        } else {
            $Common::Messages::indent_plain = 3;
        }

        &echo( "\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_pre_command )
        {
            &echo( qq (   Running pre-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->install_pre_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_pre_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNPACK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Unpacking source archive ... " );
        &Common::File::unpack_archive_inplace( "$src_dir.tar.gz" );
        &echo_green( "done\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( %{ $args->edit_files } )
        {
            &echo( "   Editing files ... " );
            &Install::Software::edit_files( $args );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $args->with_install )
        {
            &echo( "   Installing ... " );
            &Install::Software::run_install( $args );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> POST COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->install_post_command )
        {
            &echo( qq (   Running post-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->install_post_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }        
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> POST-FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $routine = $args->install_post_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Registering ... " );
        Registry::Register->register_python_modules( $name );
        &echo_green( "done\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE SOURCE DIR <<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->delete_source_dir ) 
        {
            &echo( "   Deleting sources ... " );
            &Common::File::delete_dir_tree( $src_dir );
            &echo_green( "done\n" );
        }
        
        &echo("");
    }

    if ( not $args->silent )
    {
        # Should really check if module can be loaded
#         eval {
#             local $SIG{__DIE__} = undef;
#             require Lingua::Stem::Snowball;
#         };

        &echo_green( "done\n" );
    }

    return;
}

sub install_python_modules
{
    # Niels Larsen, November 2010.

    # Installs python modules, either those in a given list, or if no list, all 
    # those that remain to be installed. Most modules install the standard way,
    # but some have deviations and exceptions which this function handles. The
    # number of installed modules is returned. 

    my ( $pkgs,     # List of modules
         $args,     # Argument hash - OPTIONAL
         $msgs,     # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns integer.

    my ( @names, $pkg, %filter, $count, $field, @list, $name, $filter, $regexp,
         @table, @names_nodeps );

    if ( defined $pkgs and not ref $pkgs ) {
        $pkgs = [ $pkgs ];
    }

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ qw ( all force existing_only verbose silent list print_header download debug ) ],
        } );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND EXIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of modules and exit,

    if ( $args->list )
    {
        &Install::Software::list_software( "soft_python_module", "uninstalled", $args->all );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET MODULE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all package names,

    if ( not $args->all and $pkgs and @{ $pkgs } ) {
        @list = &Install::Software::check_packages("python_modules", $pkgs );
    } else {
        @list = Registry::Get->python_modules()->options_names;
    }

    # With these names, get corresponding registry objects. If the "existing 
    # only" option is on, then missing modules are silently ignored; this is 
    # useful when distributing subsets of the software,

    @names = map { $_->name } Registry::Get->python_modules(
        \@list,
        {
            "existing_only" => $args->existing_only,
        })->options;
    
    # Unless --force, filter away installed packages,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->unregistered_python_modules();
        @names = grep { $filter{ $_ } } @names;
    }

    # Return if nothing to install,

    return if not @names;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->print_header and not $args->silent ) 
    {
        &echo( "\n" );
        &echo_bold( "Installing Python modules:\n" );
    }

    &Common::File::create_dir_if_not_exists( $Common::Config::logi_pyms_dir );
    &Common::File::create_dir_if_not_exists( $Common::Config::tmp_dir );

    $count = 0;

    foreach $name ( @names )
    {
        &Install::Software::install_python_module(
            $name,
            {
                "force" => $args->force,
                "verbose" => $args->verbose,
                "silent" => $args->silent,
                "debug" => $args->debug,
                "print_header" => 0,
            },
            $msgs );
    
        $count += 1;
    }

    if ( $args->print_header and not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    # Register python modules option if all modules registered,

    if ( Registry::Register->are_all_registered( "soft_python_module" ) )
    {
        Registry::Register->register_syssoft( "python_modules" );
    }

    return $count;
}

sub install_software
{
    # Niels Larsen, September 2006.
    
    # Installs the software options, by invoking different routines.

    my ( $opts,
         $args,
        ) = @_;

    # Returns integer or nothing. 

    my ( $def_args, $args2, $opt, $count, $routine, $mysql_port, $apache_port,
         @names, $name, %filter, $title, $sys_dir, $reg_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>> GET AND CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<

    $def_args =  {
        "apache_port" => undef, # $Common::Config::http_port,
        "mysql_port" => undef, # $Common::Config::db_port,
        "all" => 0,
        "force" => 0,
        "download" => 1,
        "indent" => undef,
        "existing_only" => 1,
        "verbose" => 0,
        "silent" => 0,
        "debug" => 0,
        "confirm" => 1,
        "print_header" => 1,
    };

    $args = &Common::Util::merge_params( $args, $def_args );

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ keys %{ $def_args } ],
        } );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK COMPILERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Need C, C++ and Fortran, which do not come with this package (maybe they
    # should),

    &Install::Software::check_compilers();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GET SOFTWARE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check if the given package names match those in the registry. If --all or
    # no projects given, get them all,

    if ( $args->all )
    {
        @names = Registry::Get->installs_software()->options_names;
    }
    elsif ( $opts and @{ $opts } )
    {
        @names = &Install::Software::check_packages( "installs_software", $opts );
    }
    else {
        &error( qq (No options given) );
    }
    
    # Filter unless force,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->unregistered_soft_installs();
        @names = grep { $filter{ $_ } } @names;
    }

    # Subtract perl, which should already have been installed,

    if ( not $args->force )
    {
        @names = grep { $_ ne "perl" } @names;
    }

    # Return if nothing to install,

    return if not @names;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIRM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->confirm )
    {
        $title = "\n$Common::Config::sys_name Software Installation\n\n";
        &Install::Software::confirm_menu( \@names, "install", $title );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CREATE DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create missing top-level installation directories,

    &Install::Software::create_missing_softdirs();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Dispatch installation to routines,

    $count = 0;

    foreach $name ( @names )
    {
        $args2 = &Storable::dclone( $args );

        delete $args2->{"confirm"};

        if ( $name eq "mysql" )
        {
            $args2->verbose( 1 );

            $mysql_port = &Install::Software::install_mysql( $name, $args2 );
            $count += 1;
        }
        elsif ( $name eq "apache" )
        {
            $args2->verbose( 1 );

            $apache_port = &Install::Software::install_apache( $name, $args2 );
            $count += 1;
        }
        elsif ( $name =~ /^utilities|analyses$/ )
        {
            delete $args2->{"mysql_port"};
            delete $args2->{"apache_port"};
            
            $routine = "Install::Software::install_$name";

            no strict "refs";
            $count += &{ $routine }( undef, $args2 );
        }
        else
        {
            $args2->verbose( 1 );
            $args2->indent( 0 );

            &Install::Software::install_package( $name, $args2 );
            $count += 1;
        }

        # Register,

        Registry::Register->register_soft_installs( $name );
    }

    # Load all modules with C-code to compile the C,

    &echo_bold("Completing installation:\n");

    &echo("   Loading modules with C-code ... ");

    require Common::Util_C;
    require Seq::Simrank;
    require Seq::Test;
    require Seq::Chimera;
    require DNA::Map;

    &echo_done("done\n");
    
    # Create set_env and unset_env links,
 
    &echo("   Creating shortcut links ... ");

    &Install::Software::create_env_links();

    # Create project links so the top home page works,

    &Install::Software::create_proj_links();

    &echo_bold("Finished\n");

    return ( $count, $apache_port, $mysql_port );
}

sub install_utilities
{
    # Niels Larsen, March 2005.

    # Installs the software declared as analysis software in the register.

    my ( $pkgs,     # List of packages
         $args,     # Install options hash
         $msgs,     # Outgoing messages
         ) = @_;

    # Returns nothing.

    my ( @pkgs, $name, %filter, $count, $conf, @list, $path );

    if ( defined $pkgs and not ref $pkgs ) {
        $pkgs = [ $pkgs ];
    }

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ qw ( all force existing_only verbose silent list print_header indent download debug ) ],
        } );

    if ( $args->silent ) {
        $Common::Messages::silent = 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND EXIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of modules and exit,

    if ( $args->list )
    {
        &Install::Software::list_software( "soft_util", "uninstalled", $args->all );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET MODULE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all package names,

    if ( not $args->all and $pkgs and @{ $pkgs } ) {
        @list = &Install::Software::check_packages("utilities_software", $pkgs );
    } else {
        @list = Registry::Get->utilities_software()->options_names;
    }

    # With these names, get corresponding registry objects. If the "existing 
    # only" option is on, then missing modules are silently ignored; this is 
    # useful when distributing subsets of the software,

    @pkgs = Registry::Get->utilities_software(
        \@list,
        {
            "existing_only" => $args->existing_only,
        })->options;

    # Unless --force, remove filter away installed packages,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->unregistered_utilities();
        @pkgs = grep { $filter{ $_->name } } @pkgs;
    }

    return 0 if not @pkgs;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> VMSTAT BANDAID <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Some utilities, like parallel, depend on vm_stat which is called vmstat
    # on some systems. This makes a link,
    
    $path = `which vmstat`;
    $path =~ s/\s+//g;

    if ( $path ) {
        &Common::File::create_link_if_not_exists( $path, "$Common::Config::bin_dir/vm_stat" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->print_header and not $args->silent ) 
    {
        &echo( "\n" );
        &echo_bold( "Installing Utilities:\n" );
    }

    &Common::File::create_dir_if_not_exists( $Common::Config::logi_util_dir );

    $count = 0;
    
    foreach $name ( map { $_->name } @pkgs )
    {
        &Install::Software::install_package(
            $name,
            {
                "force" => $args->force,
                "verbose" => $args->verbose,
                "silent" => $args->silent,
                "debug" => $args->debug,
                "print_header" => 0,
            },
            $msgs );
        
        $count += 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Register analyses install option if all analysis packages registered,

    if ( Registry::Register->are_all_registered( "soft_util" ) )
    {
        Registry::Register->register_soft_installs( "utilities" );
    }

    if ( $args->print_header and not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    return $count;
}

sub list_install_dirs
{
    # Niels Larsen, April 2009.

    # Returns a list of normal Unix install directories, like this:
    # ( bin sbin include ... )

    # Returns a list.

    my ( @list );

    @list = qw ( bin sbin include lib man cat info share data doc );

    push @list, map { "man/man$_" } ( 1 ... 8 );
    push @list, map { "cat/cat$_" } ( 1 ... 8 );

    return wantarray ? @list : \@list;
}

sub list_software
{
    # Niels Larsen, April 2009.

    # Lists software of a given type, installed or uninstalled. 

    my ( $type,        # Software type, e.g. "soft_util"
         $filter,      # Filter name, e.g. "uninstalled"
         $force,       # List all, OPTIONAL - default off
        ) = @_;

    # Returns nothing.

    my ( @table, $args, $status, $msgs );

    if ( $force ) {
        $filter = "";
    } elsif ( $filter !~ /^installed|uninstalled$/ ) {
        &error( qq (Wrong looking filter -> "$filter" ) );
    }
    
    $args = &Registry::Args::check(
        {
            "types" => [ $type ],
            "fields" => "name,src_name,title",
            "filter" => $filter,
            "sort" => 1,
        },{
            "AR:1" => [ "types" ],
            "S:1" => [ "fields", "filter", "sort" ],
        });

    @table = Registry::List->list_software( $args, $msgs );

    if ( @table )
    {
        print "\n";
        
        Common::Tables->render_list(
            \@table,
            {
                "fields" => $args->fields,
                "header" => 1, 
                "colsep" => "  ",
                "indent" => 3,
            });
        
        print "\n\n";
    }
    elsif ( $filter )
    {
        if ( $filter eq "installed" ) {
            $status = "uninstalled";
        } elsif ( $filter eq "uninstalled" ) {
            $status = "installed";
        } 

        &echo_messages(
             [["OK", qq (All packages are $status) ]],
             { "linewid" => 60, "linech" => "-" } );
    }

    return;
}

sub run_configure
{
    # Niels Larsen, March 2008.

    # Configures a package.

    my ( $args,          # Parameters and flags - OPTIONAL
         ) = @_;

    # Returns a list.

    require Common::File;
    require Common::OS;

    my ( $orig_dir, $src_dir, $inst_dir, $dir, $cmd, $params, $env_var );

    # Unset environment variables if requested; some programs wont compile
    # unless this is done,

    local %ENV = %ENV;

    if ( $args->unset_env_vars ) 
    {
        foreach $env_var ( split /\s*,\s*/, $args->unset_env_vars ) {
            delete $ENV{ $env_var };
        }
    }

    $orig_dir = &Cwd::getcwd();
    
    $src_dir = $args->src_dir;
    $inst_dir = $args->inst_dir;

    # Set directory where configuration happens, 

    if ( $dir = $args->configure_dir ) {
        $dir = &Install::Software::expand_tokens( $dir, $args );
    } else {
        $dir = $src_dir;
    }

    if ( not chdir $dir ) {
        &error( qq (Could not change to directory -> "$dir") );
    }

    &Common::File::delete_file_if_exists( "config.cache" );
    
    # Run autogen.sh if requested,

    if ( $args->run_autogen )
    {
        &Common::OS::run_command( "./autogen.sh", { "log_file" => $args->log_file } );
    }

    # Set default and given parameters, then run,

    if ( $args->configure_command )
    {
        $cmd = $args->configure_command;
    }
    elsif ( -r "Build.PL" )
    {
        $cmd = "perl Build.PL --install_base $Common::Config::pemi_dir";
    }
    elsif ( -r "Makefile.PL" )
    {
        $cmd = "perl Makefile.PL INSTALL_BASE=$Common::Config::pemi_dir";
    }        
    else
    {
        if ( -f "config" ) {
            $cmd = "./config";
        } else {
            $cmd = "./configure";
        }

        $cmd .= " --prefix=$inst_dir";
    }

    if ( $args->configure_prepend ) {
        $cmd = $args->configure_prepend ." $cmd";
    }
    
    if ( defined $args->configure_params ) {
        $cmd .= " ". $args->configure_params;
    }

    if ( $args->debug ) {
        &dump( $cmd );
    }

    $cmd = &Install::Software::expand_tokens( $cmd, $args );

    &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );

    chdir $orig_dir;

    return;
}

sub run_install
{
    # Niels Larsen, March 2005.

    # Does the install part of overall installation. 

    my ( $args,         # Arguments hash
         ) = @_;

    # Returns a list.

    require Common::File;
    require Common::OS;
    
    my ( $cmd, $cur_dir, $src_dir, $inst_dir, $dir, $file, $path, @files, 
         $name, @types, $tuple, $dest_dir, $field );
    
    # Convenience variables,

    $src_dir = $args->src_dir;
    $inst_dir = $args->inst_dir;

    # Expand install directory path,

    $cur_dir = &Cwd::getcwd();

    if ( $dir = $args->install_dir ) {
        $dir = &Install::Software::expand_tokens( $dir, $args );
    } else {
        $dir = $src_dir;
    }
    
    # Change to directory,
    
    if ( not chdir $dir ) {
        &error( qq (Could not change to directory -> "$dir") );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $cmd = $args->install_command ) 
    {
        # If explicit command given,

        $cmd = &Install::Software::expand_tokens( $cmd, $args );

        &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
    }
    elsif ( -r "Build.PL" )
    {
        # If there is a Build file (perl modules),

        &Common::OS::run_command( "./Build install", { "log_file" => $args->log_file } );
    }
    elsif ( -r "setup.py" ) 
    {
        &Common::OS::run_command( "python setup.py install --prefix=$inst_dir", { "log_file" => $args->log_file } );
    }
    else
    {
        # If recipe given for copying files in place (from source area to install
        # area), then use that; otherwise "make install",

        if ( @{ $args->install_bins } or 
             @{ $args->install_libs } or
             @{ $args->install_data } or
             @{ $args->install_docs } )
        {
            @types = (
                [ "install_bins", "bin" ],
                [ "install_libs", "lib" ],
                [ "install_data", "data" ],
                [ "install_docs", "doc" ],
                );
            
            require File::Copy::Recursive;

            foreach $tuple ( @types )
            {
                ( $field, $dest_dir ) = @{ $tuple };
                
                if ( $args->$field )
                {
                    foreach $path ( @{ $args->$field } )
                    {
                        if ( -d $path ) {
                            &File::Copy::Recursive::dircopy( $path, "$inst_dir/$path" );
                        } else {
                            &File::Copy::Recursive::fcopy( $path, "$inst_dir/$dest_dir" );
                        }
                    }
                }
            }
        }
        else {
            &Common::OS::run_command( "make install", { "log_file" => $args->log_file } );
        }
    }

    # Back to original directory,

    chdir $cur_dir;

    return;
}

sub run_make
{
    # Niels Larsen, March 2005.

    # Runs GNU make with a given target (e.g. "test", "clean") and 
    # returns the output as an array of lines. The output consists 
    # of STDOUT lines, followed by STDERR lines. If STDERR contains
    # evidence of trouble, this routine exists and shows the 
    # trouble.

    my ( $args,         # arguments - OPTIONAL
         ) = @_;

    # Returns a list.

    require Common::File;
    require Common::OS;
    
    my ( $target, $cmd, $cur_dir, $src_dir, $inst_dir, @stdout, 
         @stderr, $dir, @errlines, @loglines, $log_file, $env_var );
    
    # Convenience variables,

    $src_dir = $args->src_dir;
    $inst_dir = $args->inst_dir;
    $target = $args->make_target || "";

    # Unset environment variables if requested; some programs wont compile
    # unless this is done,

    local %ENV = %ENV;

    if ( $args->unset_env_vars ) 
    {
        foreach $env_var ( split /\s*,\s*/, $args->unset_env_vars ) {
            delete $ENV{ $env_var };
        }
    }
    
    # Remember current directory,

    $cur_dir = &Cwd::getcwd();

    # Set directory where make happens, 

    if ( $dir = $args->make_dir ) {
        $dir = &Install::Software::expand_tokens( $dir, $args );
    } else {
        $dir = $src_dir;
    }

    if ( not chdir $dir ) {
        &error( qq (Could not change to directory -> "$dir") );
    }

    # Set command and run,

    if ( $args->make_command ) 
    {
        $cmd = $args->make_command;
        $cmd = &Install::Software::expand_tokens( $cmd, $args );
    }
    elsif ( $target )
    {
        $cmd = "CFLAGS=\"-fPIC\"; make $target";
    }
    elsif ( -r "Build.PL" )
    {
        $cmd = "./Build";
    }
    else {
        $cmd = "CFLAGS=\"-fPIC\"; make";
    }

    if ( $args->debug ) {
        &dump( $cmd );
    }

    &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );

    # ? 

    if ( $target eq "distclean" )
    {
        &Common::OS::run_command( "make clean", { "log_file" => $args->log_file } );
    }

    # Back to original directory,

    chdir $cur_dir;

    return;
}

sub run_test
{
    # Niels Larsen, March 2005.

    # Testing .. 

    my ( $args,         # Arguments hash
         ) = @_;

    # Returns a list.

    require Common::File;
    require Common::OS;
    
    my ( $target, $cmd, $cur_dir, $src_dir, $inst_dir, @stdout, 
         @stderr, $dir, @errlines, @loglines, $log_file );
    
    # Convenience variables,

    $src_dir = $args->src_dir;
    $inst_dir = $args->inst_dir;

    # Remember current directory,

    $cur_dir = &Cwd::getcwd();

    # Set directory where make happens, 

    if ( $dir = $args->test_dir ) {
        $dir = &Install::Software::expand_tokens( $dir, $args );
    } else {
        $dir = $src_dir;
    }

    if ( not chdir $dir ) {
        &error( qq (Could not change to directory -> "$dir") );
    }

    # Set command and run,

    if ( $cmd = $args->test_command ) 
    {
        $cmd = &Install::Software::expand_tokens( $cmd, $args );
    }
    elsif ( -r "Build.PL" )
    {
        $cmd = "./Build test";
    }
    else {
        $cmd = "CFLAGS=\"-fPIC\"; make test";
    }

    if ( $args->debug ) {
        &dump( $cmd );
    }

    &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );

    # Back to original directory,

    chdir $cur_dir;

    return;
}

sub uninstall_analyses
{
    # Niels Larsen, April 2009.

    # Uninstalls the list of given analysis packages. Returns the number of 
    # packages uninstalled.

    my ( $pkgs,     # List of packages - OPTIONAL
         $args,     # Install options hash - OPTIONAL
         $msgs,     # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns integer.

    my ( @pkgs, @list, %filter, $count, $name, $conf );

    if ( defined $pkgs and not ref $pkgs ) {
        $pkgs = [ $pkgs ];
    }

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ qw ( all force source existing_only verbose silent list print_header indent ) ],
        } );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND EXIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of modules and exit,

    if ( $args->list )
    {
        &Install::Software::list_software( "soft_anal", "installed", $args->all );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET MODULE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all package names,

    if ( not $args->all and $pkgs and @{ $pkgs } ) {
        @list = &Install::Software::check_packages("analysis_software", $pkgs );
    } else {
        @list = Registry::Get->analysis_software()->options_names;
    }

    # With these names, get corresponding registry objects. If the "existing 
    # only" option is on, then missing packages are silently ignored; this is 
    # useful when distributing subsets of the software,

    @pkgs = Registry::Get->analysis_software(
        \@list,
        {
            "existing_only" => $args->existing_only,
        })->options;

    # Unless --force, show only installed packages,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->registered_analyses();
        @pkgs = grep { $filter{ $_->name } } @pkgs;
    }

    return 0 if not @pkgs;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNINSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->print_header and not $args->silent ) 
    {
        &echo( "\n" );
        &echo_bold( "Uninstalling Analyses:\n" );
    }

    $count = 0;

    foreach $name ( map { $_->name } @pkgs )
    {
        &Install::Software::uninstall_package(
            $name,
            {
                "force" => $args->force,
                "source" => $args->source,
                "verbose" => $args->verbose,
                "silent" => $args->silent,
                "print_header" => 0,
            },
            $msgs );
        
        $count += 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> UNREGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    Registry::Register->unregister_soft_installs( "analyses" );

    if ( $args->print_header and not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    return $count;
}
    
sub uninstall_package
{
    # Niels Larsen, April 2009.

    # Uninstalls a given package.

    my ( $name,
         $args,
         $msgs,
         ) = @_;

    # Returns nothing. 

    require Common::File;
    require Common::OS;

    my ( $dir, $src_dir, $inst_dir, $logi_dir, $src_name, $inst_name, 
         $pkg, $soft_dir, $subdir, $datatype, $regtype, $checksub, $presub,
         $postsub, $unregsub, $log_file, $adm_dir, $log_dir, $logi_file, 
         $str, $cmd, $routine, $conf, $src_tar, @suffixes );

    &Common::Messages::block_public_calls( __PACKAGE__ );

    # Create registry package object,

    $pkg = Registry::Get->software( $name );

    $src_name = $pkg->src_name;
    $inst_name = $pkg->inst_name;

    $datatype = $pkg->datatype;

    # Get configuration hash,
    
    $routine = qq (Install::Config::$datatype( "$name" ));
    eval "\$conf = $routine || {}";

    &error( $@ ) if $@;
    
    # Check arguments and fill in defaults, 
    
    $args = &Install::Software::get_args( { %{ $conf }, %{ $args || {} } } );

    # Print message,

    if ( not $args->silent )
    {
        $str = "Uninstalling $inst_name";

        if ( lc $src_name ne lc $inst_name ) {
            $str .= " ($src_name)";
        }
        
        if ( $args->print_header ) {
            &echo_bold( "\n$str:" );
        } else {
            &echo( "   $str ... " );
        }
    }

    # Set source and install directories,
    
    if ( $datatype eq "soft_sys" )
    {
        $src_dir = "$Common::Config::pks_dir/$src_name";
        $inst_dir = "$Common::Config::pki_dir/$inst_name";
        $adm_dir = "$Common::Config::adm_dir/$inst_name";
        $logi_dir = $Common::Config::logi_dir;
        $log_dir = $Common::Config::log_dir;
        $regtype = "syssoft";
    }
    elsif ( $datatype eq "soft_anal" )
    {
        $src_dir = "$Common::Config::ans_dir/$src_name";
        $inst_dir = "$Common::Config::ani_dir/$inst_name";
        $logi_dir = $Common::Config::logi_anal_dir;
        $regtype = "analyses";
    }
    elsif ( $datatype eq "soft_util" )
    {
        $src_dir = "$Common::Config::uts_dir/$src_name";
        $inst_dir = "$Common::Config::uti_dir/$inst_name";
        $logi_dir = $Common::Config::logi_util_dir;
        $regtype = "utilities";
    }
    else {
        &error( qq (Wrong looking package datatype -> "$datatype") );
    }

    $args->src_dir( $src_dir );
    $args->inst_dir( $inst_dir );

    {
        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;
        
        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        if ( defined $args->indent ) {
            $Common::Messages::indent_plain = $args->indent;
        } else {
            $Common::Messages::indent_plain = 3;
        }

        &echo( "\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( defined $args->uninstall_pre_command )
        {
            &echo( qq (   Running pre-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->uninstall_pre_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRE-FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $routine = $args->uninstall_pre_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGISTRY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        $checksub = "registered_$regtype";
        $unregsub = "unregister_$regtype";
        
        if ( Registry::Register->$checksub( $name ) )
        {
            &echo( "   Deleting from registry ... " );
            Registry::Register->$unregsub( $name );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LINKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( "   Deleting install links ... " );
        &Install::Software::delete_install_links( $inst_dir );

        $soft_dir = $Common::Config::soft_dir;
        
        foreach $dir ( &Install::Software::list_install_dirs() )
        {
            foreach $subdir ( $inst_name, lc $inst_name )
            {
                if ( -d "$soft_dir/$dir/$subdir" ) {
                    &Common::File::delete_dir_tree( "$soft_dir/$dir/$subdir" );
                }
            }
        }
        
        &echo_green( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>> LOG DIRECTORY <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $log_dir and -d "$log_dir/$inst_name" )
        {
            &echo( "   Deleting runtime logs ... " );
            &Common::File::delete_dir_tree( "$log_dir/$inst_name" );
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>> ADMIN DIRECTORY <<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( defined $adm_dir )
        {
            &echo( "   Deleting administration files ... " );

            if ( -e $adm_dir ) {
                &Common::File::delete_dir_tree( $adm_dir );
                &echo_green( "done\n" );
            } else {
                &echo_green( "none\n" );
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> INSTALL DIRECTORY <<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( -r $inst_dir )
        {
            &echo( "   Deleting installation directory ... " );
            
            &Common::File::delete_dir_tree( $inst_dir );
            &Common::File::delete_dir_if_empty( $Common::Config::pki_dir );
            
            &echo_green( "done\n" );
        }
        else
        {
            &echo( "   No install directory found ... " );
            &echo_green( "ok\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SOURCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $args->delete_source_dir and -e $src_dir )
        {
            &echo( "   Deleting source directory ... " );
            &Common::File::delete_dir_tree( $src_dir );
            &echo_green( "done\n" );
        }
        
        if ( $args->source ) 
        {
            &echo( "   Deleting source package ... " );
            &Common::File::delete_dir_tree_if_exists( $src_dir );

            @suffixes = &Common::Names::archive_suffixes();

            $src_tar = &Common::File::append_suffix( $src_dir, \@suffixes );
            &Common::File::delete_file_if_exists( $src_tar );
            
            &echo_green( "done\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL LOG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        $logi_file = "$logi_dir/". $inst_name .".log";

        if ( -e $logi_file )
        {
            &echo( "   Deleting install log ... " );
            &Common::File::delete_file( $logi_file );
            &echo_green( "done\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> POST-FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $routine = $args->uninstall_post_function )
        {
            $routine = &Install::Software::expand_tokens( $routine, $args );
            eval $routine;

            &error( $@ ) if $@;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> POST-COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( defined $args->uninstall_post_command )
        {
            &echo( qq (   Running post-command ... ) );
            
            $cmd = &Install::Software::expand_tokens( $args->uninstall_post_command, $args );
            &Common::OS::run_command( $cmd, { "log_file" => $args->log_file } );
            
            &echo_green( "done\n" );
        }

        &echo("");
    }
    
    if ( not $args->silent )
    {
        if ( $args->print_header ) {
            &echo_bold( "Finished\n" );
        } else {
            &echo_green( "done\n" );
        }
    }

    return 1;
}

sub uninstall_perl_modules
{
    # Niels Larsen, May 2009.

    # Uninstalls all perl modules. There is no reliable mechanism to uninstall
    # single modules, and they are specific for the perl version. 

    # Returns nothing. 

    require Common::File;
    require Common::Admin;

    my ( $pkg, $src_name, $inst_name );

    &echo( qq (   Uninstalling Perl modules ... ) );

    &Install::Software::delete_install_links( $Common::Config::pemi_dir );
    &Common::File::delete_dir_tree_if_exists( $Common::Config::pemi_dir );

    &Common::File::delete_dir_tree_if_exists( $Common::Config::logi_pems_dir );

    &Common::File::delete_file_if_exists( "$Common::Config::adm_inst_dir/registered_perl_modules" );

    if ( Registry::Register->registered_syssoft( "perl_modules" ) ) {
        Registry::Register->unregister_syssoft( "perl_modules" );
    }

    &echo_green( "done\n" );

    return;
}

sub uninstall_pre_apache
{
    # Niels Larsen, May 2009.

    # Stops Apache, uninstalls OpenSSL, unregisters mod_perl, and deletes Software 
    # and Sesssion links in WWW docroot. The routine is a callback function called 
    # by &Install::Software::uninstall_package.

    # Returns nothing. 

    require Common::Admin;
    require Common::File;

    # Stop apache server,

    &Common::Admin::stop_apache({ "headers" => 0 });

    # Uninstall OpenSSL,

    &Install::Software::uninstall_utilities( "openssl", { "print_header" => 0 } );

    # Unregister mod_perl,

    Registry::Register->unregister_perl_modules( "mod_perl" );

    # Clean document root, but dont touch the directories,

    &echo( "   Deleting Docroot links ... " );
    
    &Common::File::delete_file_if_exists( "$Common::Config::www_dir/Software" );
    &Common::File::delete_file_if_exists( "$Common::Config::www_dir/Sessions" );
    
    &Common::File::delete_dir_if_empty( $Common::Config::www_dir );
    
    &echo_green( "done\n" );

    return;
}

sub uninstall_pre_mysql
{
    # Niels Larsen, May 2009.

    # Reverses the steps on the install_mysql routine while printing
    # messages. 

    # Returns nothing. 

    require Common::Admin;
    require Common::File;

    my ( $dbs_dir, $dir, $file );

    # Stop server if it runs, prints messages,
        
    &Common::Admin::stop_mysql({ "headers" => 0 });

    # Delete server directory,
    
    &echo( "   Deleting initialization data ... " );
    
    $dbs_dir = $Common::Config::dbs_dir;

    &Common::File::delete_dir_tree_if_exists( "$dbs_dir/mysql" );
    &Common::File::delete_dir_tree_if_exists( "$dbs_dir/test" );

    if ( -e $dbs_dir )
    {
        foreach $file ( &Common::File::list_files( $dbs_dir, '^(maria|mysql)[-_]' ) ) {
            &Common::File::delete_file( $file->{"path"} );
        }
    }

    &echo_green( "done\n" );

    return;
};

sub uninstall_post_mysql
{
    &Common::File::delete_file_if_exists( "$Common::Config::bin_dir/mysql.server" );
        
    return;
};

sub uninstall_software
{
    # Niels Larsen, September 2006.
    
    # Unnstalls the software options, by dispatching to different routines.

    my ( $opts,
         $args,
        ) = @_;

    # Returns integer or nothing. 

    my ( $def_args, $args2, $count, $routine, $mysql_port, $apache_port,
         @installs, %filter, @names, $name, $title );

    # >>>>>>>>>>>>>>>>>>>>>>>> GET AND CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<

    $def_args =  {
        "all" => 0,
        "force" => 0,
        "source" => 0,
        "confirm" => 1,
        "verbose" => 0,
        "silent" => 0,
        "indent" => undef,
        "print_header" => 1,
    };

    $args = &Common::Util::merge_params( $args, $def_args );

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ keys %{ $def_args } ],
        } );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GET SOFTWARE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check if the given package names match those in the registry. If --all or
    # no projects given, get them all,

    if ( $args->all )
    {
        @names = reverse Registry::Get->installs_software()->options_names;
    }
    elsif ( $opts and @{ $opts } )
    {
        @names = &Install::Software::check_packages( "installs_software", $opts );
    }
    else {
        &error( qq (No options given) );
    }

    # Filter unless force,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->registered_soft_installs();
        @names = grep { $filter{ $_ } } @names;
    }

    # Return if nothing to install,

    return if not @names;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIRM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->confirm )
    {
        $title = "\n$Common::Config::sys_name Software Uninstallation\n\n";
        &Install::Software::confirm_menu( \@names, "uninstall", $title );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STOP QUEUES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    require Common::Batch;
    require Common::Admin;

    if ( &Common::Batch::queue_is_running() )
    {
        &echo( "\n" );
        &Common::Admin::stop_queue();
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNINSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Order options so perl uninstallation is done last if given,

    if ( grep { $_ eq "perl" } @names )
    {
        @names = grep { $_ ne "perl" } @names;
        push @names, "perl";
    }

    # Dispatch installation to routines,

    $count = 0;

    foreach $name ( @names )
    {
        $args2 = &Storable::dclone( $args );
        delete $args2->{"confirm"};

        if ( $name =~ /^utilities|analyses$/ )
        {
            $routine = "Install::Software::uninstall_$name";

            no strict "refs";
            $count += &{ $routine }( undef, $args2 );
        }
        elsif ( $name eq "perl" )
        {
            # If everything else has been uninstalled, then delete empty directories
            # first. Could also just be done after each option, but some packages 
            # require empty directories to work. 
            
            @installs = grep { $_ ne "perl" } Registry::Register->registered_soft_installs();

            if ( not @installs )
            {
                if ( not $args->silent )
                {
                    &echo_bold( "\nCleaning:\n" );
                    &echo( "   Removing empty directories ... " );
                }
                
                $count = &Install::Software::delete_install_dirs_if_empty();
                
                if ( not $args->silent )
                {
                    &echo_done( "$count\n" );                    
                    &echo_bold( "Finished\n" );            
                }
            }

            $args2->verbose( 1 );
            $args2->indent( 0 );

            &Install::Software::uninstall_package( $name, $args2 );
            $count += 1;

            Registry::Register->unregister_syssoft( "perl" );
            Registry::Register->unregister_syssoft( "perl_modules" );
        }
        else
        {
            $args2->verbose( 1 );
            $args2->indent( 0 );

            &Install::Software::uninstall_package( $name, $args2 );
            $count += 1;
        }

        # Unregister,

        if ( Registry::Register->registered_soft_installs( $name ) ) {
            Registry::Register->unregister_soft_installs( $name );
        }
    }

    return ( $count, $apache_port, $mysql_port );
}

sub uninstall_utilities
{
    # Niels Larsen, May 2009.

    # Uninstalls the list of given utility packages. Returns the number of 
    # packages uninstalled.

    my ( $pkgs,     # List of packages - OPTIONAL
         $args,     # Install options hash - OPTIONAL
         $msgs,     # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns integer.

    my ( @pkgs, @list, %filter, $count, $name, $conf );

    if ( defined $pkgs and not ref $pkgs ) {
        $pkgs = [ $pkgs ];
    }

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ qw ( all force source existing_only verbose silent list print_header indent ) ],
        } );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND EXIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of modules and exit,

    if ( $args->list )
    {
        &Install::Software::list_software( "soft_util", "installed", $args->all );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET MODULE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all package names,

    if ( not $args->all and $pkgs and @{ $pkgs } ) {
        @list = &Install::Software::check_packages("utilities_software", $pkgs );
    } else {
        @list = Registry::Get->utilities_software()->options_names;
    }

    # With these names, get corresponding registry objects. If the "existing 
    # only" option is on, then missing packages are silently ignored; this is 
    # useful when distributing subsets of the software,

    @pkgs = Registry::Get->utilities_software(
        \@list,
        {
            "existing_only" => $args->existing_only,
        })->options;

    # Unless --force, show only installed packages,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->registered_utilities();
        @pkgs = grep { $filter{ $_->name } } @pkgs;
    }

    return 0 if not @pkgs;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNINSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->print_header and not $args->silent ) 
    {
        &echo( "\n" );
        &echo_bold( "Uninstalling Utilities:\n" );
    }

    $count = 0;

    foreach $name ( map { $_->name } @pkgs )
    {
        &Install::Software::uninstall_package(
            $name,
            {
                "force" => $args->force,
                "source" => $args->source,
                "verbose" => $args->verbose,
                "silent" => $args->silent,
                "print_header" => 0,
            },
            $msgs );
        
        $count += 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNREGISTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    Registry::Register->unregister_soft_installs( "utilities" );

    if ( $args->print_header and not $args->silent ) {
        &echo_bold( "Finished\n" );
    }

    return $count;
}

1;

__END__

# sub create_recipe_links
# {
#     # Niels Larsen, October 2010.

#     # If a project file is among the project templates but is not in the projects
#     # directory, then this routine creates the missing links. Returns the number of
#     # links made.

#     # Returns integer.

#     my ( $recp_dir, $tmpl_dir, $name, $count );

#     $recp_dir = $Common::Config::recp_dir;
#     $tmpl_dir = $Common::Config::recpd_dir;

#     foreach $name ( grep /^[a-z]+$/, map { $_->{"name"} } @{ &Common::File::list_files( $tmpl_dir ) } )
#     {
#         if ( not -e "$recp_dir/$name" ) {
#             &Common::File::create_link( "$tmpl_dir/$name", "$recp_dir/$name" );
#             $count += 1;
#         }
#     }
    
#     return $count;
# }

