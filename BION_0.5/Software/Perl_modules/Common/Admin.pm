package Common::Admin;     #  -*- perl -*-

# Functions specific to managing user logins. 

use strict;
use warnings FATAL => qw ( all );

use English;

use File::Find;
use File::Basename;
use Data::Dumper;
use Sys::Hostname;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_paths
                 &add_paths_cluster
                 &apache_is_running
                 &apache_port
                 &append_pkg_suffices
                 &child_process_ids
                 &code_clean
                 &code_grep
                 &code_list
                 &create_distribution
                 &create_down_files
                 &create_paths
                 &data_clean
                 &delete_down_files
                 &_dirs_clean
                 &_dirs_grep
                 &_dirs_list
                 &kill_processes
                 &list_processes
                 &list_process_ids
                 &mysql_is_running
                 &offline_page
                 &servers_all_running
                 &start_apache
                 &start_mysql
                 &start_queue
                 &start_servers
                 &stop_apache
                 &stop_mysql
                 &stop_queue
                 &stop_servers
                 &used_modules
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Tables;

use Registry::Args;
use Registry::Get;
use Registry::List;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_paths
{
    # Niels Larsen, March 2009.

    # Adds the paths that BION needs for regular installs. Returns a list 
    # of paths.

    my ( $type,      # Distribution type
         $paths,     # List of paths to append to - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( @paths, $dir, @names );

    push @paths, (
        $Common::Config::pls_dir,
        "$Common::Config::www_dir/index.cgi",
        "$Common::Config::www_dir/robots.txt",
        $Common::Config::doc_dir,
    );

    $dir = $Common::Config::sys_dir;

    push @paths, map { "$dir/". $_->{"name"} } &Common::File::list_all( $dir, 'README.*' );

    # CSS directory: get files that end with ".css",
    
    $dir = $Common::Config::css_dir;
    
    push @paths, map { "$dir/". $_->{"name"} } &Common::File::list_files( $dir, '.css$' );
    
    # Fonts directory: get files that end with ".ttf",
    
    $dir = $Common::Config::font_dir;
    
    push @paths, map { "$dir/". $_->{"name"} } &Common::File::list_files( $dir, '.ttf$' );
    
    # Images directory: get all .svg, .png and .gif files,
    
    $dir = $Common::Config::img_dir;
    
    push @paths, map { "$dir/". $_->{"name"} } &Common::File::list_files( $dir, '.png$|.gif$|.svg$' );
    
    # Javascript directory: get files that end with ".js", and the "cross-browser"
    # directory tree,
    
    $dir = $Common::Config::jvs_dir;
    
    push @paths, map { "$dir/". $_->{"name"} } &Common::File::list_files( $dir, '.js$' );
    push @paths, "$dir/cross-browser.com";

    # Projects directory,

    push @paths, (
        "$Common::Config::conf_dir/README",
        "$Common::Config::conf_proj_dir/README",
        $Common::Config::conf_projd_dir,
        $Common::Config::recp_dir,
    );

    if ( $type eq "soft" )
    {
        # Include all the large packages, database etc,

        @names = map { $_->src_name } Registry::Get->system_software()->options;
        push @paths, &Common::Admin::append_pkg_suffices( \@names, $Common::Config::pks_dir );

        @names = map { $_->src_name } Registry::Get->utilities_software()->options;
        push @paths, &Common::Admin::append_pkg_suffices( \@names, $Common::Config::uts_dir );

        @names = map { $_->src_name } Registry::Get->perl_modules()->options;
        push @paths, &Common::Admin::append_pkg_suffices( \@names, $Common::Config::pems_dir );

        @names = map { $_->src_name } Registry::Get->python_modules()->options;
        push @paths, &Common::Admin::append_pkg_suffices( \@names, $Common::Config::pyms_dir );

        @names = map { $_->src_name } Registry::Get->analysis_software()->options;
        @names = grep { $_ !~ /^blast-|netblast-/i } @names;        
        push @paths, &Common::Admin::append_pkg_suffices( \@names, $Common::Config::ans_dir );
    }

    if ( defined $paths ) {
        push @{ $paths }, @paths;
    }

    return wantarray ? @{ $paths } : $paths;
}

sub add_paths_cluster
{
    # Niels Larsen, March 2009.

    # Returns a list of the paths that are specific for the limited 
    # cluster distribution.

    my ( $paths,    # Paths that will be appended to - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( @paths, @list, @names, %filter, $dir, @modules );

    require Common::Cluster;

    # Code grep, clean etc,

    @list = map { $_->{"path"} } grep { $_->{"name"} =~ /^(code_|create_)/ }
           &Common::File::list_files( "$Common::Config::pls_dir/Admin" );

    @list = grep { $_ !~ /_list$/ } @list;
    push @paths, @list;

    # Installation, all scripts,

    push @paths, $Common::Config::plsi_dir;

    # Documentation,

    push @paths, (
        "$Common::Config::sys_dir/README.cluster",
        "$Common::Config::doc_dir/Cluster",
    );
    
    # Master and slave commands,

    @list = map { $_->[0] } &Common::Cluster::commands_master();
    push @paths, map { "$Common::Config::pls_dir/$_" } @list;

    @list = map { $_->[0] } &Common::Cluster::commands_slave();
    push @paths, map { "$Common::Config::pls_dir/$_" } @list;

    # Perl,

    @list = map { $_->src_name } Registry::Get->system_software()->options;
    @list = grep { $_ =~ /^perl/ } @list;
    push @paths, map { "$Common::Config::pks_dir/$_.tar.gz" } @list;
    
    # Some perl modules,

    @list = map { $_->src_name } Registry::Get->perl_modules()->options;
    @list = grep { $_ !~ /^PDL-/ } @list;
    push @paths, &Common::Admin::append_pkg_suffices( \@list, $Common::Config::pems_dir );

    # Some utilities,

    @list = map { $_->src_name } Registry::Get->utilities_software()->options;
    @list = grep { $_ !~ /^(gsl|db-|openssl-)/ } @list;
    push @paths, &Common::Admin::append_pkg_suffices( \@list, $Common::Config::uts_dir );

    # Some analysis modules,

    @list = map { $_->src_name } Registry::Get->analysis_software()->options;
    @list = grep { $_ !~ /^blast-|netblast-/i } @list;
    push @paths, &Common::Admin::append_pkg_suffices( \@list, $Common::Config::ans_dir );

    if ( defined $paths ) {
        push @{ $paths }, @paths;
    }

    return wantarray ? @{ $paths } : $paths;
}

sub apache_is_running
{
    # Niels Larsen, March 2005.

    # Lists the processes and sees if the "httpd" belonging to this 
    # installation is running as the current user. Returns true it is, 
    # otherwise nothing.

    # Returns 1 or nothing.

    my ( @pids );

#    if ( Registry::Register->registered_data_installs("apache") )
#    {
        @pids = &Common::Admin::list_process_ids( "httpd" );
#    }
#     else
#     {
#         &echo_messages( [[ "Error", "Apache WWW server is not installed" ]] );
#         &echo( "\n" );
#         exit;
#     }

    if ( @pids ) {
        return 1;
    } else {
        return;
    }
}

sub apache_port
{
    my ( $text );

    $text = ${ &Common::File::read_file( "$Common::Config::adm_dir/Apache/httpd.conf" ) };

    if ( $text =~ /\n\s*Listen\s+(\d+)/ ) {
        return $1;
    } else {
        &Common::Messages::error( qq (Could not read Apache port from httpd.conf) );
    }

    return;
}

sub append_pkg_suffices
{
    my ( $names,
         $dir,
        ) = @_;

    my ( $name, $path, @paths );

    foreach $name ( @{ $names } )
    {
        if ( $dir ) {
            $path = "$dir/$name";
        } else {
            $path = $name;
        }
        
        push @paths, &Common::File::append_suffix( $path, [ qw ( .tar.gz .tgz .tar.bz2 .zip ) ] );
    }

    return wantarray ? @paths : \@paths;
}

sub child_process_ids
{
    # Niels Larsen, February 2009.

    # Finds all children of a given process id. Returns a list of 
    # children process ids.

    my ( $pid,
        ) = @_;

    # Returns a list.

    my ( $os_name, $cmd, @lines, $line, $cpid, $ppid, @pids );

    while ( @lines = `ps ax -o pid,ppid | grep $pid\$` )
    {
        foreach $line ( @lines )
        {
            next if $line !~ /^\s*\d/;

            chomp $line;
            ( $cpid, $ppid ) = split " ", $line;
            
            if ( $ppid == $pid )
            {
                push @pids, $cpid;
                push @pids, &Common::Admin::child_process_ids( $cpid );
            }
        }

	if ( defined $cpid ) {
	    $pid = $cpid;
	} else {
	    last;
	}
    }

    return wantarray ? @pids : \@pids;
}

sub code_clean
{
    # Niels Larsen, March 2005.

    # For a given list of directories, deletes all regular files that do 
    # not start and end with a word-character. 

    my ( $dirs,      # Directory names
         ) = @_;

    # Returns nothing.

    if ( not defined $dirs ) {
        $dirs = &Common::Config::get_code_dirs();
    }

    &Common::Admin::_dirs_clean( $dirs );

    return;
}

sub code_grep
{
    # Niels Larsen, November 2007.

    # For a given list of directories, searches all given directories for 
    # a given expression string. 

    my ( $expr,      # Perl regexp 
         $dirs,      # Directory names
         ) = @_;

    # Returns nothing.

    my ( @dirs );

    if ( not defined $dirs ) {
        $dirs = &Common::Config::get_code_dirs();
    }

    @dirs = grep { -d $_ } @{ $dirs };

    &Common::Admin::_dirs_grep( $expr, \@dirs );

    return;
}

sub code_list
{
    # Niels Larsen, August 2008.

    # Returns a listing of code files in different ways. UNFINISHED

    my ( $class,      # 
         $args,       # Arguments hash or object
         ) = @_;

    # Returns nothing.

    my ( @dirs, $expr, @list, $elem, $subs, $lines, $size,
         $content, @list2, @rows, %row, $fields, $output, $dir,
         @output );

    if ( ref $args eq "HASH" )
    {
        $args = &Registry::Args::check(
            $args,
            { "S:1" => [ qw ( modules scripts numbers dirs total expr format ) ] } );
    }

    # List perl modules and/or scripts recursively. Returned are 
    # lists of [ input dir, subdirectory path ] so that the full
    # path is made by combining the two,

    if ( $args->modules )
    {
        $dir = $Common::Config::plm_dir;
        @list = &Common::Admin::_dir_list( '.pm$', $dir );

        @list = map { $_ =~ s|^$dir/||; $_ } @list;
        push @output, map { { "dir" => $dir, "module" => $_ } } @list;
    }

    if ( $args->scripts )
    {
        $dir = $Common::Config::pls_dir;
        @list = &Common::Admin::_dir_list( '', $dir );

        @list = map { $_ =~ s|^$dir/||; $_ } @list;
        push @output, map { { "dir" => $dir, "module" => $_ } } @list;
    }
    
    # Filter by expression,

    if ( $args->expr )
    {
        $expr = $args->expr;
        @output = grep { $_->{"module"} =~ /$expr/xio } @output;
    }

    # Add file, routine (explicitly declared) and line numbers,

    if ( $args->numbers )
    {
        foreach $elem ( @output )
        {
            $content = ${ &Common::File::read_file( $elem->{"dir"} ."/". $elem->{"module"} ) };
            
            $elem->{"files"} = 1;
            $elem->{"routines"} = () = $content =~ m|\nsub |gs;
            $elem->{"lines"} = () = $content =~ m|\n|gs;
            $elem->{"size"} = length $content;
        }
    }

    # If total option, collapse list to single element, elsif directory
    # collapse to top-level directories,

    %row = ( 
        "dir" => "",
        "module" => "",
        "files" => 0,
        "routines" => 0,
        "lines" => 0,
        "size" => 0,
        );

    if ( $args->total )
    {
        foreach $elem ( @output )
        {
            map { $row{ $_ } += $elem->{ $_ } } qw ( files routines lines size );
        }

        @output = \%row;
    }
    elsif ( $args->dirs )
    {
        &Common::Messages::error( qq (Directory option not working yet) );
    }

    # Convert to table,
    
    foreach $elem ( @output )
    {
        $elem = [ map { $elem->{ $_ } } qw ( dir module files routines lines size ) ];
    }

    # Format output,

    if ( $args->format eq "dump" )
    {
        $output = \@output;
    }
    elsif ( $args->format eq "text" )
    {
        $output = Common::Tables->print_table_ascii(
            \@output,
            {
                "fields" => "dir,module,files,routines,lines,size",
                "header" => 1,
                "colsep" => "  ",
                "indent" => 2,
            });
    }
    elsif ( $args->format eq "xhtml" )
    {
        &Common::Messages::error( qq (XHTML output option not working yet) );
    }
    else {
        &Common::Messages::error( qq (Wrong looking format option -> "). $args->format .qq (") );
    }

    if ( defined wantarray ) {
        return $output;
    } else {
        print $output;
    }

    return;
}

sub create_distribution
{
    # Niels Larsen, March 2008.

    # Creates BION_{suffix}.tar.gz files with all source code needed to compile
    # and install the system. Source paths are constructed from configuration files
    # (in Config) as much as possible, allowing installed packages that are not
    # included. Other paths are hardcoded files and directories in this routine.
    # So changes not covered by the configuration files must be edited in this
    # routine. Returns the name of the tar file created.

    my ( $args,        # Command line argument hash
         $headers,     # To print bold headers or not - OPTIONAL, default on
         ) = @_;

    # Returns string. 

    require Common::Tables;
    require Common::OS;

    my ( @paths, $paths, $path, $base_dir, $orig_dir, $out_dir, $out_file,
         $dir, @errors, $command, @names, $name, $paths_file, $dist_type, 
         $type, $inst_file, $msg, %dist_types, $home_dir );

    $args = &Registry::Args::check(
        $args,
        {
            "S:2" => [ qw ( distrib ) ],
            "S:0" => [ qw ( outdir quiet homedir ) ],
        });

    %dist_types = map { $_, 1 } qw ( code soft cluster );
    $dist_type = $args->distrib;
    $home_dir = $args->homedir // 1;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK TYPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not exists $dist_types{ $dist_type } )
    {
        $msg = qq (Wrong looking distribution type -> "$dist_type");
        &echo_messages( [["ERROR", $msg ]] );
        exit;
    }

    local $Common::Messages::silent = $args->quiet;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> START <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $out_dir = $args->outdir || &Cwd::getcwd();
    $headers = 1 if not defined $headers;

    if ( $headers )
    {
        if ( $dist_type eq "code" ) {
            &echo_bold( "\nCreating scripts archive:\n" );
        } else {
            &echo_bold( "\nCreating $dist_type distribution:\n" );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>> CLEAN CODE DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Cleaning directories ... " );

    {
        local $Common::Messages::silent = 1;
        &Common::Admin::code_clean();
    }

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ACCUMULATE PATHS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # An array is filled with paths and then written to file. This file is 
    # then given to tar to read from. 

    &echo( "   Selecting source files ... " );    

    # First the harcoded paths - all files within directories are included, 
    # so keep those clean,

    push @paths, (
        "$Common::Config::sys_dir/LICENSE",
        "$Common::Config::sys_dir/install_software",    # gets just the link
        $Common::Config::plm_dir,                       # all our perl modules
    );

    # Registry parts,

    push @paths, (
        "$Common::Config::adm_inst_dir/README",
        "$Common::Config::conf_clu_dir/Cluster.config.template",
        $Common::Config::soft_reg_dir,     # Software registry
        $Common::Config::dat_reg_dir,      # Data registry
        $Common::Config::conf_prof_dir,    # Profile directory
        $Common::Config::conf_cont_dir,    # Contacts config directory        
        $Common::Config::shell_dir,        # Shell scripts
        $Common::Config::doc_dir,          # Documentation
    );

    # Add paths that are specific to a distribution,

    if ( $dist_type eq "cluster" ) {
        @paths = &Common::Admin::add_paths_cluster( \@paths );
    } else {
        @paths = &Common::Admin::add_paths( $dist_type, \@paths );
    }

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE TYPE FILE <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Write file if "amputated" distribution,

    $inst_file = "$Common::Config::adm_inst_dir/install_type";

    if ( $dist_type !~ /^code|soft$/i ) 
    {
        &Common::File::write_file( $inst_file, $dist_type );

        push @paths, $inst_file;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK ALL PATHS EXIST <<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Is everything there ... " );

    foreach $path ( @paths )
    {
        if ( not -r $path ) {
            push @errors, qq (Missing source -> "$path");
        }
    }

    if ( @errors )
    {
        &echo_red( "NO\n" );
        &Common::Messages::error( \@errors );
    }
    else {
        &echo_green( "yes\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MODIFY PATHS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Strip paths of their base directory; if the home_dir switch is on, 

    $base_dir = $Common::Config::sys_dir;

    # If home_dir the tar file will create the 
    if ( $home_dir ) {
        $base_dir =~ s|/([^/]+)$||;
    }

    @paths = map { $_ =~ s/$base_dir\///; [ $_ ] } @paths;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> TAR FILE FROM PATHS <<<<<<<<<<<<<<<<<<<<<<<<

    # Set output file name,

    $out_file = "$out_dir/BION_$dist_type.tar.gz";

    &echo( "   Creating $out_file ... " );

    # Write paths to file,

    &Common::File::create_dir_if_not_exists( $Common::Config::tmp_dir );
    $paths_file = "$Common::Config::tmp_dir/distribution_paths.$$";

    &Common::Tables::write_tab_table( $paths_file, \@paths );

    # Run tar command,

    $orig_dir = &Cwd::getcwd();

    chdir $base_dir;

    $command = "tar --files-from $paths_file --exclude='*Inline_C*' --exclude='*Old_code*' -czf $out_file";

#    `$command`;
    &Common::OS::run_command_backtick( $command );
    
    chdir $orig_dir;

    &Common::File::delete_file( $paths_file );
    &Common::File::delete_file_if_exists( $inst_file );

    &echo_green( "done\n" );

    &echo_bold( "Finished\n\n" ) if $headers;
    
    return $out_file;
}

sub create_down_files
{
    my ( $args,
        ) = @_;

    my ( $proj, $file, $dir, $message, $xhtml, $count );

    if ( $args and $args->message ) {
        $message = $args->message;
    } elsif ( $file ) {
        $message = ${ &Common::File::read_file( $args->file ) };
    } else {
        $message = qq ( Temporarily off-line for maintenance.);
    }

    $count = 0;

    foreach $proj ( Registry::Get->projects->options )
    {
        $dir = "$Common::Config::www_dir/". $proj->projpath;

        if ( -d $dir )
        {
            $xhtml = &Common::Admin::offline_page( $proj, $message );
            &Common::File::delete_file_if_exists( "$dir/sys_message.html" );
            &Common::File::write_file( "$dir/sys_message.html", $xhtml );

            $count++;
        }
    }
    
    return $count;
}

sub data_clean
{
    # Niels Larsen, March 2005.

    my ( $dirs,      # Directory names
         ) = @_;

    # Returns nothing.

    if ( not defined $dirs ) {
        $dirs = [ $Common::Config::dat_dir ];
    }

    &Common::Admin::_dirs_clean( $dirs );

    return;
}

sub delete_down_files
{
    my ( $proj, $dir, $count );

    $count = 0;

    foreach $proj ( Registry::Get->projects->options )
    {
        $dir = "$Common::Config::www_dir/". $proj->projpath;

        if ( -r "$dir/sys_message.html" )
        {
            &Common::File::delete_file( "$dir/sys_message.html" );
            $count++;
        }
    }
    
    return $count;
}

sub _dirs_clean
{
    my ( $dirs,
         ) = @_;

    my ( $subref );

    @{ $dirs } = grep { -e $_ } @{ $dirs };

    $subref = sub {

        my $file = $File::Find::name;

#        if ( -f $_ and not -l $_ and $_ !~ /^\w.*\w$/ )
        if ( not -d $_ and $_ !~ /^\w.*\w$/ )
        {
            if ( unlink $file ) {
                &echo_green( "Deleted" );
            } else {
                &echo_red( "DELETE FAILED" );
            }
            
            &echo( " -> $file\n" );
        }
    };

    &File::Find::find( $subref, @{ $dirs } );

    return;
}

sub _dirs_grep
{
    my ( $expr,
         $dirs,
        ) = @_;

    my ( @matches, $subref, $output );

    $subref = sub 
    {
        my ( $name, $path, $line_num, $line, $sw_dir, $sw_dir_q, 
             @l_dir, $l_path, $col1, $col2 );
        
        $name = $_;
        $path = $File::Find::name;

        return if -l $path or not -f $path or $path =~ /Inline_/i;
        
        $line_num = 0;
        
        foreach $sw_dir ( @{ $dirs } )
        {
            $sw_dir_q = quotemeta $sw_dir;
            
            if ( $path =~ /^$sw_dir_q/ )
            {
                @l_dir = split "/", $POSTMATCH;
                shift @l_dir; pop @l_dir;
                
                if ( @l_dir ) {
                    $l_path = ( join "/", @l_dir ) . "/$name";
                } else {
                    $l_path = "$name";
                }
                
                last;
            }
        }
        
        open FILE, "< $path" or &Common::Messages::error( qq (Could not read-open file "$path") );
        
        while ( defined ( $line = <FILE> ) )
        {
            $line_num++;
            
            if ( $line =~ /$expr/i )
            {
                $line = $PREMATCH . &echo_info( $MATCH ) . $POSTMATCH;
                chomp $line;
                
                $col1 = { 
                    "value" => "$l_path, $line_num: ",
                    "align" => "right",
                    "color" => "bold",
                };
                
                $col2 = { 
                    "value" => $line,
                    "align" => "left",
                };
                
                push @matches, [ $col1, $col2 ];
            }
       }
       
        close FILE;
    };

    &File::Find::find( $subref, @{ $dirs } );

    if ( @matches )
    {
        $output = &Common::Tables::render_ascii( \@matches );
        &echo( "$output\n" );
    }
    
    return;
}

sub _dir_list
{
    # Niels Larsen, August 2008.

    # Lists perl code file statistics in different ways and formats.

    my ( $expr,
         $dir,
        ) = @_;

    # Returns an XHTML string or a list of lists.

    my ( @paths, $subref );

    $subref = sub 
    {
        my ( $name, $path );
        
        $name = $_;
        $path = $File::Find::name;

        if ( -l $path or not -f $path or $path !~ /$expr/ )
        {
            return;
        }
        
        push @paths, $path;
        return;
    };

    &File::Find::find( $subref, $dir );

    return wantarray ? @paths : \@paths;
}
    
sub kill_processes
{
    # Niels Larsen, August 2006.
    
    # Stops a list of processes given by their ids. All children are
    # deleted as well. Returns the number of processes killed. 

    my ( $pids,         # Process ids
         $errors,       # Error list - OPTIONAL
         ) = @_;

    # Returns an integer.

    require Proc::Killfam;

    my ( $pid, $count, $killed );

    $killed = 0;

    foreach $pid ( @{ $pids } )
    {
        $count = &Proc::Killfam::killfam( 9, $pid );

        if ( $count ) {
            $killed += $count;
        } else {
            push @{ $errors }, qq (Process $pid was not killed);
        }
    }

    return $killed;
}

sub list_processes
{
    # Niels Larsen, August 2006.

    # Returns a list of Proc::ProcessTable objects owned by the current
    # user id ($<). If a program name like "httpd" is given, or part of 
    # it, then the list is filtered with that expression.

    my ( $expr,      # Regular expression - OPTIONAL
         ) = @_;

    # Returns a list.


    my ( $procs, $proc, @table, @list, $list, $table );

    require Proc::ProcessTable;

    @table = @{ new Proc::ProcessTable->table };

    @table = grep { $_->uid == $< } @table;   # Current user id only

    if ( @table and defined $expr ) {
        @table = grep { $_->cmndline =~ /($Common::Config::soft_dir|$Common::Config::pls_dir)[^ ]+$expr/i } @table;
    }

    return wantarray ? @table : \@table;
}

sub list_process_ids
{
    # Niels Larsen, August 2006.

    # Returns a list of ids of processes owned by the current user id ($<).
    # If a program name like "httpd" is given, or part of it, then the list
    # is filtered with that expression.

    my ( $expr,      # Regular expression - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( @ids );

    @ids = map { $_->pid } &Common::Admin::list_processes( $expr );

    return wantarray ? @ids : \@ids;
}

sub mysql_is_running
{
    # Niels Larsen, December 2005.

    # Sees if MySQL is in the process table. 

    # Returns 1 or nothing.

    my ( @pids );

#    if ( Registry::Register->registered_data_installs("mysql") )
#    {
          @pids = &Common::Admin::list_process_ids( "mysql" );
#    }
#     else
#     {
#         &echo_messages( [[ "Error", "MySQL database server is not installed" ]] );
#         &echo( "\n" );
#         exit;
#     }

    if ( @pids ) {
        return 1;
    } else {
        return;
    }

    return;
}

sub servers_all_running
{
    require Common::Batch;
    
    if ( &Common::Admin::apache_is_running() and
         &Common::Admin::mysql_is_running() and 
         &Common::Batch::queue_is_running() )
    {
        return 1;
    }

    return;
}

sub offline_page
{
    # Niels Larsen, October 2006.

    # Reads the text in "WWW-root/site_is_down", adds contact information
    # and returns the result.

    my ( $proj,
         $comment,      # Comment - OPTIONAL
         ) = @_;

    # Returns a string.

    require Common::Widgets;

    my ( $timestr, $xhtml, $msg, $msg_xhtml, $title_xhtml, $contact_xhtml );

    $comment ||= "";

    $timestr = &Common::Util::epoch_to_time_string();

    $msg = [[ "Info", qq (At $timestr (GMT+1) the site was temporarily closed.<p>$comment</p>) ]];
    $msg_xhtml = &Common::Widgets::message_box( $msg );

    $title_xhtml = &Common::Widgets::title_box( "Temporarily Closed", "title_box" );

    $xhtml = qq (
<html>
<head>
   <meta name="author" content="Danish Genome Institute" />
   <link rel="stylesheet" type="text/css" href="$Common::Config::css_url/common.css" />
</head>
<body>
);

    $xhtml .= &Common::Widgets::header_bar( { "title" => $proj->description->title } );
    
    $contact_xhtml = &Common::Messages::format_contacts_for_browser();

    $xhtml .= qq (
<table cellspacing="30">
   <tr><td>$title_xhtml</td></tr>
</table>

<table><tr><td height="20">&nbsp;</td><tr></table>

<table cellspacing="0">
   <tr><td width="30">&nbsp;</td><td>$msg_xhtml</td></tr>
</table>

<table><tr><td height="30">&nbsp;</td><tr></table>

<table cellspacing="30">
   <tr><td>$contact_xhtml</td></tr>
</table>

<table><tr><td height="20">&nbsp;</td><tr></table>
);

    $xhtml .= &Common::Widgets::footer_bar();

    $xhtml .= qq (</body></html>\n);
    
    return $xhtml;
}

sub start_apache
{
    # Niels Larsen, March 2005.

    # Launches apache, waits for a second and checks that the launched
    # server is running. Messages are printed unless the silent option 
    # is given. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    require Proc::Simple;
    require Install::Software;

    my ( $proc, $err_file, $err_str, $headers, $stopold, $modperl, $home, 
         $dirs, $conf_file, $mode, $port, $newconf, $count, $pkg );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:0" => [ qw ( headers stopold newconf mode port dirs home ) ], 
        });

    # Set variables,

    $headers = defined $args->headers ? $args->headers : 1;
    $stopold = defined $args->stopold ? $args->stopold : 1;
    $newconf = defined $args->newconf ? $args->newconf : 1;

    $mode = defined $args->mode ? $args->mode : "modperl";
    $port = defined $args->port ? $args->port : $Common::Config::http_port;
    $home = defined $args->home ? $args->home : $Common::Config::www_dir;
    $dirs = $args->dirs // 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE LOG DIR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $pkg = Registry::Get->software("apache");

    &Common::File::create_dir_if_not_exists( "$Common::Config::log_dir/". $pkg->inst_name );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK MODE AND PORT <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $mode !~ /^modperl|cgi$/ ) {
        &Common::Messages::error( qq (Wrong looking configuration type -> "$mode") );
    }

    if ( $port !~ /^\d+/ ) {
        &Common::Messages::error( qq (Apache port is not an integer -> "$port") );
    } elsif ( $port < 1024 or $port > 9999 ) {
        &Common::Messages::error( qq (Apache port is not between 1024 and 9999 -> "$port") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> STOP FIRST BY DEFAULT <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stopold )
    {
        if ( &Common::Admin::apache_is_running() ) 
        {
            &Common::Admin::stop_apache( {"headers" => $headers} );
            &echo( "\n" ) if $headers;
        }
    }

    &echo_bold( "Starting Apache:\n" ) if $headers;

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE NEW HTTPD.CONF <<<<<<<<<<<<<<<<<<<<<<<<<<

    # This reads, edits and saves a httpd.conf file from the original template,

    if ( $newconf )
    {
        &echo( "   Creating server configuration ... " );

        &Install::Software::create_apache_config_file(
             {
                 "instname" => "Apache",
                 "mode" => $mode,
                 "port" => $port,
                 "home" => $home,
                 "dirs" => $dirs,
             });

        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LAUNCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Starting with apachectl ... " );

    $proc = new Proc::Simple;
    $err_file = "$Common::Config::log_dir/Apache/apache_start.errors";

    $proc->redirect_output ( $err_file, $err_file );

    $proc->start( "$Common::Config::bin_dir/apachectl start" );
    sleep 3;    # Waits until modules loaded

    $proc->kill;

    if ( -s $err_file ) {
        $err_str = ${ &Common::File::read_file( $err_file ) };
    } else {
        $err_str = "";
    }

    if ( $err_str ) {
        &echo_yellow( "WARNING\n" );
        &echo_yellow( "   Look in the file $err_file\n" );
    } else {
        &Common::File::delete_file_if_exists( $err_file );
        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK IF RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stopold )
    {
        $err_file = "$Common::Config::log_dir/Apache/error_log";

        &echo( "   Is the server running ... " );
        
        if ( &Common::Admin::apache_is_running() ) {
            &echo_green( "yes\n" );
        } else {
            &echo_red( "NO, LAUNCH FAILED\n" );
            &echo_red( "   Look at the end of the file $err_file\n" );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE DOWN FILES <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Admin::servers_all_running ) 
    {
        &echo( "   Deleting down-messages ... " );
        $count = &Common::Admin::delete_down_files();
        &echo_green( "$count\n" );
    }

    &echo_bold( "Done\n" ) if $headers;

    return;
}        

sub start_mysql
{
    # Niels Larsen, March 2005.

    # Launches mysql server, waits for a second and checks that the launched
    # server is running. Messages are printed unless the silent option 
    # is given. 

    my ( $args,
         ) = @_;

    # Returns nothing.

    require Proc::Simple;
    require Install::Software;

    local $Common::Messages::silent;

    my ( $proc, $err_file, $err_str, $pid_file, $cnf_file, $failed,
         $command, $headers, $stopold, $port, $inst_name, $count );

    $args = &Registry::Args::check(
        $args || {},
        { 
            "S:0" => [ qw ( stopold headers port silent ) ], 
        });

    $headers = defined $args->headers ? $args->headers : 1;
    $stopold = defined $args->stopold ? $args->stopold : 1;
    $port = defined $args->port ? $args->port : $Common::Config::db_port;

    $inst_name = Registry::Get->software("mysql")->inst_name;

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>> STOP FIRST BY DEFAULT <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stopold )
    {
        if ( &Common::Admin::mysql_is_running() ) 
        {
            &Common::Admin::stop_mysql( {"headers" => $args->headers} );
            &echo( "\n" ) if $headers;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LAUNCH AS MYSQL WANTS <<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( "Starting $inst_name:\n" ) if $headers;

    # Write configuration file,
        
    &echo( "   Creating server configuration ... " );
    &Install::Software::create_mysql5_config_file( $inst_name, $port );
    &echo_green( "done\n" );

    # Starting,

    &echo( "   Starting with mysqld_safe ... " );

    $err_file = "$Common::Config::log_dir/$inst_name/mysql_errors.log";
    &Common::File::delete_file_if_exists( $err_file );

    # MySQL bug: pid-file is already in my.cnf, but needs to be here
    # here too. But only on Redhat 9 .. so far.

    $command = "$Common::Config::bin_dir/mysqld_safe";
    $command .= " --defaults-file=$Common::Config::adm_dir/$inst_name/my.cnf";
    $command .= " --ledir=$Common::Config::bin_dir";
    $command .= " --log-error=$err_file";

    $proc = new Proc::Simple;
    $proc->redirect_output( "/dev/null", "/dev/null" );

    $proc->start( $command );
    sleep 1;

    $proc->kill;

    if ( -s $err_file ) {
        $err_str = ${ &Common::File::read_file( $err_file ) };
    } else {
        $err_str = "";
    }

    if ( not $err_str
         or $err_str =~ /mysqld: ready for connections/s 
         or $err_str !~ /\[ERROR\]/i )
    {
        &echo_green( "done\n" );
        $failed = 0;
    } else {
        &echo_red( "FAILED\n" );
        $failed = 1;
    }
    
    if ( $err_str =~ /\[ERROR\]/i ) {
        &echo_red( "   Errors in $err_file\n" );
    } elsif ( $err_str =~ /\[Warning\]/i ) {
        &echo_yellow( "   Warnings in $err_file\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK IF RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stopold )
    {
        &echo( "   Is the server running ... " ); 
        
        if ( &Common::Admin::mysql_is_running() )
        {
            &echo_green( "yes\n" );
        }
        else {
            &echo_red( "NO, LAUNCH FAILED\n" );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE DOWN FILES <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Admin::servers_all_running ) 
    {
        &echo( "   Deleting down-messages ... " );
        $count = &Common::Admin::delete_down_files();
        &echo_green( "$count\n" );
    }

    &echo_bold( "Done\n" ) if $headers;
    
    return $err_file;
}

sub start_queue
{
    # Niels Larsen, August 2006.

    # Starts the batch queue as a background process. A process
    # ID is saved in the Batch directory, so the corresponding 
    # stop_queue routine can stop it safely. If the queue runs
    # after one second then 1 is returned otherwise 0. 

    my ( $args,
         ) = @_;

    # Returns boolean. 
    
    require Proc::Simple;
    require Common::Batch;

    my ( $proc, $pid, $status, $message, $queue, $err_file, $err_str,
         $stopold, $headers, $count );

    if ( $args )
    {
        $args = &Registry::Args::check(
            $args, 
            { 
                "S:0" => [ qw ( stopold headers ) ], 
            });
        
        $headers = defined $args->headers ? $args->headers : 1;
        $stopold = defined $args->stopold ? $args->stopold : 1;
    }
    else
    {
        $headers = 1;
        $stopold = 1;
    }
    
    $queue = $Common::Batch::Def_queue;

    # >>>>>>>>>>>>>>>>>>>>>>>>> STOP QUEUE IF RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Batch::queue_is_running( $queue ) or 
         &Common::Batch::queue_is_started( $queue ) )
    {
        &Common::Admin::stop_queue( {"headers" => $headers} );
        &echo( "\n" ) if $headers;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> MYSQL MUST RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( "Starting batch queue:\n" ) if $headers;

    # Return if MySQL does not run,

    &echo( "   Is database running ... " );

    if ( &Common::Admin::mysql_is_running() )
    {
        require Common::DB;
        &Common::DB::create_database_if_not_exists( $Common::Config::db_master );

        &Common::Batch::create_queue_if_not_exists( undef, $queue );
        &echo_green( "yes\n" );
    }
    else {
        &echo_red( "NO\n" );
        &echo( "   " );
        &echo_info( "Please run 'start_mysql' or 'start_servers'\n" );
        &echo_bold( "Done\n" ) if $headers;
        return;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STARTING QUEUE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Starting the queue ... ) );

    $err_file = "$Common::Config::log_dir/Batch/batch_start.errors";

    $proc = Proc::Simple->new();
    $proc->redirect_output( ">/dev/null", $err_file );

    $proc->start( \&Common::Batch::daemon, "$queue" );

    if ( -s $err_file ) {
        $err_str = ${ &Common::File::read_file( $err_file ) };
    } else {
        $err_str = "";
    }

    if ( $err_str ) {
        &echo_red( "WARNING\n" );
        &echo_yellow( "   Look in the file $err_file\n" );
    } else {
        &Common::File::delete_file_if_exists( $err_file );
        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK IF RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Is queue running ... ) );

    sleep 1;
    $pid = $proc->pid;
    
    if ( $proc->poll() )
    {
        &Common::File::write_file( "$Common::Config::bat_dir/$queue.pid", "$pid\n" );
        &echo_green( "yes\n" );
    } 
    else {
        &echo_red( "NO\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE DOWN FILES <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Admin::servers_all_running ) 
    {
        &echo( "   Deleting down-messages ... " );
        $count = &Common::Admin::delete_down_files();
        &echo_green( "$count\n" );
    }

    &echo_bold( "Done\n" ) if $headers;

    return;
}

sub start_servers
{
    # Niels Larsen, August 2008.

    # Starts all servers: Apache web server, MySQL database, and a
    # batch queue. Before each server is started it is checked if 
    # it is running and shut down first if it does. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    # Apache,

    &Common::Admin::start_apache(
        {
            "mode" => $args->apache_mode,
            "port" => $args->apache_port,
        });

    &echo("\n");

    # MySQL,

    &Common::Admin::start_mysql(
        {
            "port" => $args->mysql_port,
        });

    &echo("\n");

    # Batch queue, 

    &Common::Admin::start_queue();

    &echo("\n");

    return;
}

sub stop_apache
{
    # Niels Larsen, March 2005.

    # Does all it can to stop the apache server that has been launched by 
    # this package: first apachectl is used, which normally should do all
    # that is needed; but to make sure, all running processes are killed 
    # the hard way, and the pid file is removed if it still exists. 
    # Finally waits a second and checks server is not running anymore.
    
    my ( $args,
         ) = @_;

    # Returns nothing. 

    require Proc::Simple;

    my ( @stderr, $apachectl, $running, $proc, $err_file, $file, $hostname,
         $err_str, $count, $killed, $bin_dir, @pids, $headers );

    if ( $args )
    {
        $args = &Registry::Args::check(
            $args,
            { 
                "S:0" => [ qw ( headers file message halt ) ], 
            });

        $headers = $args->headers;
    } 

    $headers = 1 if not defined $headers;

    &echo_bold( "Stopping Apache:\n" ) if $headers;

    # >>>>>>>>>>>>>>>>>>>>>>> WRITING DOWNTIME FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Admin::servers_all_running )
    {
        &echo( "   Writing down-messages ... " );
        $count = &Common::Admin::create_down_files( $args );
        &echo_green( "$count\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> STOPPING PROPERLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Is the server running ... " );
    
    if ( &Common::Admin::apache_is_running() ) {
        $running = 1;
        &echo_green( "yes\n" );
    } else {
        $running = 0;
        &echo_green( "no\n" );
    }        

    if ( $running )
    {
        &echo( "   Stopping with apachectl ... " );

        $apachectl = "$Common::Config::bin_dir/apachectl";

        if ( -x $apachectl )
        {
            $proc = new Proc::Simple;
            $err_file = "$Common::Config::log_dir/Apache/apache_stop.errors";
            
            $proc->redirect_output( ">/dev/null", $err_file );
            
            if ( $proc->start( "$apachectl stop" ) )
            {
                sleep 2;
                $proc->kill;

                if ( -s $err_file ) {
                    $err_str = ${ &Common::File::read_file( $err_file ) };
                } else {
                    $err_str = "";
                }
                
                if ( $err_str ) {
                    &echo_yellow( "WARNING\n" );
                    &echo_yellow( "   Look in the file $err_file\n" );
                } else {
                    &Common::File::delete_file_if_exists( $err_file );
                    &echo_green( "done\n" );
                }
            } 
            else {
                &echo_red( "ERROR\n" );
                &echo_yellow( "   $apachectl could not be run.\n" );
            }
        }
        else {
            &echo_red( "ERROR\n" );
            &echo_yellow( "   $apachectl does not exist.\n" );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CLEAN REMNANTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $running )
    {
        &echo( "   Looking for zombie processes ... " );

        @pids = &Common::Admin::list_process_ids( "httpd" );
        
        if ( @pids ) 
        {
            $count = scalar @pids;
            $killed = &Common::Admin::kill_processes( \@pids );
            
            &echo_green( "$count found, $killed reaped\n" );
        }
        else {
            &echo_green( "none\n" );
        }
    }

    $file = "$Common::Config::pki_dir/Apache/logs/httpd.pid";

    if ( -e $file )
    {
        &echo( "   Deleting PID file ... " );
        &Common::File::delete_file( $file );
        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK IF STILL RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $running )
    {
        &echo( "   Is the server still running ... " );
        sleep 1;

        if ( &Common::Admin::apache_is_running() ) {
            &echo_red( "YES, HALT FAILED\n" );
        } else {
            &echo_green( "no\n" );
        }
    }

    &echo_bold( "Done\n" ) if $headers;

    return;
}        

sub stop_mysql
{
    # Niels Larsen, March 2005.

    # Does all it can to stop the mysql server that has been launched by 
    # this package: first mysqladmin is used, which normally should do all
    # that is needed; but to make sure, all running processes are killed 
    # the hard way, and pid and lock files removed if they still exist.
    # Finally waits a second and checks server is not running anymore.

    my ( $args,
         ) = @_;

    # Returns nothing. 

    require Proc::Simple;

    my ( $proc, $err_file, $password, $err_str, @stderr, $bin_dir,
         @pids, $file, $count, $killed, $running, $mysqladmin,
         $headers, $inst_name, $sock_file, $pid_file );

    if ( $args )
    {
        $args = &Registry::Args::check(
            $args,
            { 
                "S:0" => [ qw ( headers file message halt ) ], 
            });
        
        $headers = defined $args->headers ? $args->headers : 1;
    }
    else {
        $headers = 1;
    }

    $inst_name = Registry::Get->software("mysql")->inst_name;
    $sock_file = "$Common::Config::db_sock_file";
    $pid_file = "$Common::Config::db_pid_file";

    &echo_bold( "Stopping $inst_name:\n" ) if $headers;

    # >>>>>>>>>>>>>>>>>>>>>>> WRITING DOWNTIME FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Admin::servers_all_running )
    {
        &echo( "   Writing down-messages ... " );
        $count = &Common::Admin::create_down_files( $args );
        &echo_green( "$count\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> STOPPING PROPERLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Is the server running ... " );
    
    if ( &Common::Admin::mysql_is_running() ) {
        $running = 1;
        &echo_green( "yes\n" );
    } else {
        $running = 0;
        &echo_green( "no\n" );
    }        

    if ( $running )
    {
        @stderr = ();

        $mysqladmin = "$Common::Config::bin_dir/mysqladmin";
        $mysqladmin = &Common::File::resolve_links( $mysqladmin );

        $password = $Common::Config::db_root_pass;

        &echo( "   Stopping with mysqladmin ... " );

        if ( -x $mysqladmin )
        {
            $proc = new Proc::Simple;
            $err_file = "$Common::Config::log_dir/$inst_name/mysql_stop.errors";
            
            $proc->redirect_output( "/dev/null", $err_file );
            
            if ( $proc->start( "$mysqladmin --user=root --password=$password flush-tables shutdown --socket=$sock_file" ) )
            {
                sleep 2;
                $proc->kill;

                if ( -s $err_file ) {
                    $err_str = ${ &Common::File::read_file( $err_file ) };
                } else {
                    $err_str = "";
                }
                
                if ( $err_str ) {
                    &echo_yellow( "WARNING\n" );
                    &echo_yellow( "   Look in the file $err_file\n" );
                } else {
                    &Common::File::delete_file_if_exists( $err_file );
                    &echo_green( "done\n" );
                }
            } 
            else {
                &echo_red( "ERROR\n" );
                &echo_yellow( "   $mysqladmin could not be run.\n" );
            }
        }
        else {
            &echo_red( "ERROR\n" );
            &echo( "   $mysqladmin does not exist.\n" );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CLEAN REMNANTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $running )
    {
        &echo( "   Looking for zombie processes ... " );

        @pids = &Common::Admin::list_process_ids( "mysql" );
        
        if ( @pids ) 
        {
            $count = scalar @pids;
            $killed = &Common::Admin::kill_processes( \@pids );
            
            &echo_green( "$count found, $killed reaped\n" );
        }
        else {
            &echo_green( "none\n" );
        }
    }

    if ( -e $sock_file )
    {
        &echo( "   Deleting socket file ... " );
        &Common::File::delete_file( $sock_file );
        &echo_green( "done\n" );
    }


    if ( -e $pid_file )
    {
        &echo( "   Deleting PID file ... " );
        &Common::File::delete_file( $pid_file );
        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK IF STILL RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $running )
    {
        &echo( "   Is the server still running ... " );
        sleep 1;

        if ( &Common::Admin::mysql_is_running() ) {
            &echo_red( "YES, HALT FAILED\n" );
        } else {
            &echo_green( "no\n" );
        }
    }

    &echo_bold( "Done\n" ) if $headers;

    return;
}        

sub stop_queue
{
    # Niels Larsen, August 2006.

    # Stops the running batch queue. A process ID is looked for 
    # in the Batch directory and the corresponding process is 
    # then stopped. If the queue still runs after one second 
    # then 0 is returned otherwise 1. 

    my ( $args, 
         ) = @_;

    # Returns boolean. 

    require Common::Batch;
    
    my ( $queue, $pid, $count, $running, $headers );

    if ( $args )
    {
        $args = &Registry::Args::check(
            $args,
            { 
                "S:0" => [ qw ( headers file message halt ) ], 
            });
        
        $headers = defined $args->headers ? $args->headers : 1;
    }
    else {
        $headers = 1;
    }

    $queue = $Common::Batch::Def_queue;
    
    &echo_bold( "Stopping batch queue:\n" ) if $headers;

    # >>>>>>>>>>>>>>>>>>>>>> WRITING DOWNTIME FILES <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Admin::servers_all_running )
    {
        &echo( "   Writing down-messages ... " );
        $count = &Common::Admin::create_down_files( $args );
        &echo_green( "$count\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> IS DATABASE RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<<

    # TODO MAYBE: a running job is now left to continue. Instead it should
    # be killed and relaunched. Or, the queue should not be stoppable when
    # a job is running. 

    &echo( "   Is database running ... " );
        
    if ( &Common::Admin::mysql_is_running() ) {
        &echo_green( "yes\n" );
    } else {
        &echo_green( "no\n" );
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> IS QUEUE RUNNING <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo( "   Is queue running ... " );

    if ( &Common::Batch::queue_is_running( $queue ) ) {
        &echo_green( "yes\n" );
        $running = 1;
    } else {
        &echo_green( "no\n" );
        $running = 0;
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> STOP QUEUE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $running )
    {
        &echo( qq (   Stopping the queue ... ) );
        
        $pid = &Common::Batch::read_pid( $queue );
        
        $count = kill 9 => $pid;
        sleep 1;
        
        if ( $count > 0 )
        {
            &echo_green( "done\n" );
        }
        else {
            &echo_red( "FAILED\n" );
        }                
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLEAN DEBRIS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::Batch::delete_queue_pid_if_exists( $queue );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK IF STILL RUNNING <<<<<<<<<<<<<<<<<<<<<<

    if ( $running )
    {
        &echo( "   Is queue still running ... " );
        sleep 1;

        if ( &Common::Batch::queue_is_running( $queue ) or
             &Common::Batch::queue_is_started( $queue ) )
        {
            &echo_red( "YES, HALT FAILED\n" );
        }
        else {
            &echo_green( "no\n" );
        }
    }

    &echo_bold( "Done\n" ) if $headers;

    return;
}

sub stop_servers
{
    # Niels Larsen, August 2008.

    # Starts all servers: Apache web server, MySQL database, and a
    # batch queue, if they run.
    
    my ( $args,
        ) = @_;

    # Returns nothing.

    # Batch queue,

    &Common::Admin::stop_queue( $args );
    &echo( "\n" );

    # MySQL,

    &Common::Admin::stop_mysql( $args );
    &echo( "\n" );

    # Apache,

    if ( $args->halt )
    {
        &Common::Admin::stop_apache();
        &echo( "\n" );
    }

    return;
}

sub used_modules
{
    # Niels Larsen, February 2009.

    # Returns a list of modules that are 'use'd in a list of given files.

    my ( $files,
        ) = @_;

    # Returns a list.

    my ( $file, @lines, $line, @modules, $module );

    foreach $file ( @{ $files } )
    {
        @lines = split "\n", ${ &Common::File::read_file( $file ) };

        foreach $line ( @lines )
        {
            if ( $line =~ /^use (.+);\s*$/ )
            {
                $module = $1;

                if ( $module !~ /^strict|warning/ ) {
                    push @modules, $module;
                }
            }
        }
    }

    return wantarray ? @modules : \@modules;
}
              
1;

__END__

# sub code_split
# {
#     # Niels Larsen, October 2007.

#     # Auto-splits all Perl source code modules into a tree of individual
#     # files that Perl's autoloader knows how to use. Files that end with 
#     # ".pm" are split if they contain these two kinds of lines,
#     # 
#     # use AutoLoader 'AUTOLOAD';
#     # __END__   # AUTOLOAD
#     # 
#     # For "safety" he splitting is done on a copy of the source tree; 
#     # then if all all files were split without error, the copy is put 
#     # in place of the original. Options are "keep" (keeps original in a 
#     # Perl_modules_back directory) and "readonly" which does nothing but
#     # print the number of files that would be edited. 

#     my ( $args,      # Argument hash
#         ) = @_;

#     # Returns an integer.

#     my ( $pm_dir, $pm_dir_temp, $pm_dir_orig, $subref, $counter, $counter_str,
#          $readonly );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ qw ( keep readonly ) ],
#     });

#     require AutoSplit;
#     require Proc::Reliable;

#     Proc::Reliable::debug( 0 );

#     $pm_dir = $Common::Config::plm_dir;
#     $pm_dir_temp = $Common::Config::plm_dir ."_temp";
#     $pm_dir_orig = $Common::Config::plm_dir ."_orig";

#     if ( -e $pm_dir_temp ) {
#         &Common::Messages::error( qq (Work directory exists -> "$pm_dir_temp") );
#     }
    
#     if ( -e $pm_dir_orig ) {
#         &Common::Messages::error( qq (Backup directory exists -> "$pm_dir_orig") );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> MAKE COPY <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo( "   Making working copy ... " );

#     &File::Copy::Recursive::dircopy( $pm_dir, $pm_dir_temp );

#     &echo_green( "done\n" );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SPLIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $readonly = $args->readonly;
#     $counter = 0;

#     $subref = sub 
#     {
#         my ( $file, $path, $content, $proc, $command, $errors );

#         $file = $_;
#         $path = $File::Find::name;

#         if ( &Common::Names::is_perl_module( $path ) )
#         {
#             $content = ${ &Common::File::read_file( $path ) };

#             if ( $content =~ /\n# *use +AutoLoader( +'AUTOLOAD')?; *\n/sg and
#                  $content =~ /1;\s+# *__END__ +# *AUTOLOAD *\n/sg )
#             {
#                 $content =~ s/\n# *(use +AutoLoader( +'AUTOLOAD')?;) *\n/\n$1\n/sg;
#                 $content =~ s/#? +1;\s+# *(__END__ +# *AUTOLOAD) *\n/1;\n\n$1\n/sg;

#                 if ( not $readonly ) 
#                 {
#                     &Common::File::delete_file( $path );
#                     &Common::File::write_file( $path, $content );

#                     # This is the only was I could find to avoid messages coming to 
#                     # stdout and still have errors caught .. 

#                     $command = qq (perl -e 'use AutoSplit; autosplit( "$path", "$pm_dir_temp/auto", 0, 1, 1)' );

#                     &Common::OS::run_command( $command );
#                 }

#                 $counter += 1;
#             }
#         }

#         return;
#     };

#     &echo( "   Processing files ... " );

#     &Common::File::create_dir_if_not_exists( "$pm_dir_temp/auto" );
#     &File::Find::find( $subref, $pm_dir_temp );

#     if ( $counter > 0 ) {
#         $counter_str = &Common::Util::commify_number( $counter );
#         &echo_green( "$counter_str\n" );
#     } else {
#         &echo_green( "none\n" );
#     }        

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ACTIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo( "   Making backup copy ... " );
    
#     if ( rename $pm_dir, $pm_dir_orig ) {
#         &echo_green( "done\n" );
#     } else {
#         &Common::Messages::error( qq (Could not create backup directory -> "$pm_dir_orig") );
#     }
    
#     &echo( "   Moving new version in ... " );

#     if ( rename $pm_dir_temp, $pm_dir ) {
#         &echo_green( "done\n" );
#     } else {
#         &Common::Messages::error( qq (Could not move code copy to -> "$pm_dir") );
#     }

#     if ( not $args->keep )
#     {
#         &echo( "   Deleting backup copy ... " );
#         &Common::File::delete_dir_tree( $pm_dir_orig );
#         &echo_green( "done\n" );
#     }
    
#     return $counter;
# }

# sub code_unsplit
# {
#     # Niels Larsen, October 2007.

#     # Removes individual autoload files if any, and comments out lines
#     # in the perl module files that invoke the autoloader. This is 
#     # useful for turning "production" code into modules where edits 
#     # have immediate effect. 
#     # 
#     # Files that end with ".pm" are edited if they contain these two 
#     # kinds of lines,
#     # 
#     # use AutoLoader 'AUTOLOAD';
#     # 
#     # 1;
#     # __END__   # AUTOLOAD
#     # 
#     # For "safety" a copy of the source tree is made; if all all files 
#     # edited without error, then that copy is put in place of the 
#     # original. 

#     my ( $args,      # Argument hash
#         ) = @_;

#     # Returns an integer.

#     my ( $pm_dir, $pm_dir_temp, $pm_dir_orig, $pm_dir_auto, $subref, 
#          $counter, $counter_str, $readonly );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ qw ( keep readonly ) ],
#     });

#     $pm_dir = $Common::Config::plm_dir;

#     $pm_dir_temp = $pm_dir ."_temp";
#     $pm_dir_auto = $pm_dir_temp ."/auto";
#     $pm_dir_orig = $pm_dir ."_orig";

#     if ( -e $pm_dir_temp ) {
#         &Common::Messages::error( qq (Work directory exists -> "$pm_dir_temp") );
#     }
    
#     if ( -e $pm_dir_orig ) {
#         &Common::Messages::error( qq (Backup directory exists -> "$pm_dir_orig") );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> MAKE COPY <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo( "   Making working copy ... " );

#     &File::Copy::Recursive::dircopy( $pm_dir, $pm_dir_temp );

#     &echo_green( "done\n" );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> UNSPLIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $readonly = $args->readonly;
#     $counter = 0;

#     $subref = sub 
#     {
#         my ( $file, $path, $content );

#         $file = $_;
#         $path = $File::Find::name;

#         if ( &Common::Names::is_perl_module( $path ) )
#         {
#             $content = ${ &Common::File::read_file( $path ) };

#             if ( $content =~ /\nuse +AutoLoader( +'AUTOLOAD')?; *\n/sg and
#                  $content =~ /\n1;\s+__END__ *# *AUTOLOAD *\n/sg )
#             {
#                 $content =~ s/\n(use +AutoLoader( +'AUTOLOAD')?;) *\n/\n# $1\n/sg;
#                 $content =~ s/\n(1;)\s+(__END__ *# *AUTOLOAD) *\n/\n# $1\n# $2\n/sg;

#                 if ( not $readonly ) 
#                 {
#                     &Common::File::delete_file( $path );
#                     &Common::File::write_file( $path, $content );
#                 }

#                 $counter += 1;
#             }
#         }

#         return;
#     };

#     &echo( "   Processing files ... " );

#     &File::Find::find( $subref, $pm_dir_temp );

#     if ( $counter > 0 ) {
#         $counter_str = &Common::Util::commify_number( $counter );
#         &echo_green( "$counter_str\n" );
#     } else {
#         &echo_green( "none\n" );
#     }

#     if ( -e $pm_dir_auto )
#     {
#         &echo( "   Deleting auto files ... " );
#         $counter = &Common::File::delete_dir_tree( $pm_dir_auto );
        
#         if ( $counter > 0 ) {
#             $counter_str = &Common::Util::commify_number( $counter );
#             &echo_green( "$counter_str\n" );
#         } else {
#             &echo_green( "none\n" );
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ACTIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &echo( "   Making backup copy ... " );
    
#     if ( rename $pm_dir, $pm_dir_orig ) {
#         &echo_green( "done\n" );
#     } else {
#         &Common::Messages::error( qq (Could not create backup directory -> "$pm_dir_orig") );
#     }
    
#     &echo( "   Moving new version in ... " );

#     if ( rename $pm_dir_temp, $pm_dir ) {
#         &echo_green( "done\n" );
#     } else {
#         &Common::Messages::error( qq (Could not move code copy to -> "$pm_dir") );
#     }

#     if ( not $args->keep )
#     {
#         &echo( "   Deleting backup copy ... " );
#         &Common::File::delete_dir_tree( $pm_dir_orig );
#         &echo_green( "done\n" );
#     }
    
#     return $counter;
# }
