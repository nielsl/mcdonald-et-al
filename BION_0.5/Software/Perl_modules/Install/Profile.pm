package Install::Profile;            # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Methods that have to do with the profile of a project: navigation
# menus, shell configuration, etc.
#
# apache_config_text
# create_install_config
# create_nav_menu
# create_nav_menu_ali
# create_nav_menu_rfam
# create_profile
# create_regentries_menu
# _create_site_navigation_recurse
# create_site_navigation
# delete_site_navigation
# mysql5_config_text
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;
use Common::Types;

use Registry::Get;
use Registry::Register;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub apache_config_text
{
    # Niels Larsen, August 2008.

    # Replaces a number of fields in the default Apache httpd.conf configuration file
    # and adds sections at the end depending on CGI or mod_perl mode. Port, documentroot,
    # options and log file paths etc are set, and extra sections are added depending 
    # on CGI or modperl mode. 

    my ( $args,    # Arguments hash
        ) = @_;

    # Returns string.

    my ( $template, $content, @edits, $edit, $port, $log_dir, $mode, $section, $module, 
         @list, $dir_text, $perl5lib, $user, $group, $home, $dirs );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( template log_dir mode port home dirs ) ]
        } );

    $template = $args->template;
    $log_dir = $args->log_dir;
    $mode = $args->mode;
    $port = $args->port;
    $home = $args->home;
    $dirs = $args->dirs;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK HTTPD USER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # The httpd server user and group names must exist in /etc/passwd and /etc/group,
    # or else it will not launch. The defaults are daemon and daemon, but if absent 
    # we edit the template with either "nobody" or "apache", or crash if none of 
    # those users exist.
    
    ( $user, $group ) = &Install::Profile::get_httpd_user();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ TEMPLATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( -r $template ) {
        $content = ${ &Common::File::read_file( $template ) };
    } else {
        &error( qq (Apache configuration file template missing -> "$template") );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT CONTENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @edits = (
        [ qq (#\\s*\n\\s*AllowOverride None), qq (#\n\n    AllowOverride AuthConfig) ],
        [ qq (\nUser daemon), qq (\nUser $user) ],
        [ qq (\nGroup daemon), qq (\nGroup $group) ],
        [ qq (\nListen 80), qq (\nListen $port) ],
        [ qq (\nDocumentRoot "[^\"]+"), qq (\nDocumentRoot "$home") ],
        [ qq (\n<Directory "[^\"]+">), qq (\n<Directory "$home">), ],
        [ qq (\n\\s*DirectoryIndex [^\n]+), qq (\n    DirectoryIndex index.html index.cgi) ],
        [ qq (\n\\s*\#\\s*AddHandler cgi-script \.cgi), qq (\n    AddHandler cgi-script \.cgi \.php) ],
        [ qq (\n\\s*LoadModule deflate_module), qq (\n# LoadModule deflate_module) ],
        [ qq (\n\\s*ErrorLog "logs/error_log"), qq (\nErrorLog "$log_dir/error_log") ],
        [ qq (\n\\s*CustomLog "logs/access_log"), qq (\n    CustomLog "$log_dir/access_log") ],
        [ qq (\n\\s*#\\s*ErrorDocument 404 [^\n]+), qq (\nErrorDocument 404 "/index.cgi") ],
        );

    if ( $dirs ) {
        push @edits, [ qq (\n\\s+Options Indexes FollowSymLinks\\s*\n), qq (\n    Options Indexes SymLinksifOwnerMatch ExecCGI\n) ];
    } else {
        push @edits, [ qq (\n\\s+Options Indexes FollowSymLinks\\s*\n), qq (\n    Options SymLinksifOwnerMatch ExecCGI\n) ];
    }        
    
    foreach $edit ( @edits )
    {
        if ( $content !~ s/$edit->[0]/$edit->[1]/ ) {
            &error( qq (Failed match in httpd.conf -> "$edit->[0]") );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ADD SECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $section = "$Common::Config::sys_name section";

    $perl5lib = join ":", @INC;

    $content .= qq (

# ------------ $section begin

# Set Apache variables that should appear in %ENV,

SetEnv BION_HOME "$Common::Config::sys_dir"
SetEnv PERL5LIB "$perl5lib"
SetEnv TERM "dumb"

# Enable URL rewrite 
# NEEDS FIXING
#RewriteEngine On
#RewriteRule ^/?(Software|Sessions)/(.*)\$ /\$1/\$2  [S=2]
#RewriteRule ^/?([^/]+)\$ /\$1/index.cgi?
#RewriteRule ^/?([^/]+)/?(.*)\$ /\$2;index.cgi?project=\$1;\$2
);

    if ( $mode eq "modperl" )
    {
        $content .= qq (
# Set mod_perl variables that should appear in %ENV,

PerlSetEnv BION_HOME "$Common::Config::sys_dir"
PerlSetEnv PERL5LIB "$perl5lib"
PerlSetEnv TERM "dumb"

# Enable compression,

# AddOutputFilterByType DEFLATE text/html image/png text/plain text/xml

# Load mod_perl module dynamically,

LoadModule perl_module modules/mod_perl.so

# Load all Perl modules,

);
        @list = Registry::List->list_modperl_modules();
        
        foreach $module ( @list )
        {
            $module =~ s/\.pm$//;
            $module =~ s/\//::/g;
            
            $content .= qq (PerlModule $module\n);
        }
        
        $dir_text = join "|", map { $_->projpath } Registry::Get->projects->options;

        $content .= qq (
# Define locations. When new projects are defined and Apache restarted,
# this location will update to include that project - in other words, 
# Apache must be restarted when new projects defined,

PerlModule ModPerl::PerlRunPrefork

AliasMatch /($dir_text) "$Common::Config::www_dir/\$1/index.cgi"

<LocationMatch "/$dir_text">
    SetHandler perl-script
    PerlResponseHandler ModPerl::PerlRunPrefork
    PerlOptions +ParseHeaders
    Options SymLinksifOwnerMatch ExecCGI
</LocationMatch>
);
    }
    
    $content .= qq (
# ------------ $section end

);

    return $content;
}

sub create_install_config
{
    # Niels Larsen, June 2009.

    # Creates a configuration object with settings and paths that install
    # routines need. TODO: The "owner" field can be set to a project name or a 
    # session id; if the latter, paths are set that point to that users 
    # file tree and database. 

    my ( $db,
         $args,
        ) = @_;

    my ( $datadir, $hash, $db_name, $conf, $key );

    if ( $args ) {
        $hash = &Storable::dclone( $args );
    }

    $datadir = "$Common::Config::dat_dir/". $db->datapath;

    $hash->{"source"} = $db->name;
    $hash->{"datatype"} = $db->datatype;
    $hash->{"dat_dir"} = $datadir;
    $hash->{"src_dir"} = "$datadir/Sources";
    $hash->{"tab_dir"} = "$datadir/Database_tables";
    $hash->{"tmp_dir"} = "$datadir/Scratch";
    $hash->{"ins_dir"} = "$datadir/Installs";
    $hash->{"pat_dir"} = "$datadir/Patterns";

    # Set database name,

    if ( $db->owner =~ /\// ) {   # is session id
        
    }
    else {
        $hash->{"database"} = $db->name;
    }

    # Create object,

    $conf = Registry::Args->new( $hash );
    
    return $conf;
}

sub create_nav_menu
{
    # Niels Larsen, October 2006.

    # Looks at the installed data for a given list of registry 
    # database ids and creates a menu structure that reflects these. 

    my ( $class,
         $opt,            # ID list
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a menu object. 

    my ( $menu, $db, $ents, $ent, $id, $file, $viewers );

    $menu = Registry::Get->new( "name" => $opt->name, "label" => $opt->label ); 

    # Read entries from each installed database, set required fields,
    # and append them,

    $id = 0;

    foreach $db ( @{ Registry::Get->datasets( $opt->dbnames )->options } )
    {
        if ( Registry::Register->registered_datasets( $db->name ) )
        {
            $ents = Registry::Register->read_entries_list( $db->datapath_full, 0 );

            if ( $ents and @{ $ents } )
            {
                $viewers = Registry::Get->viewers()->options;

                foreach $ent ( @{ $ents } )
                {
                    if ( Registry::Match->compatible_viewers( $viewers, [ $ent ] ) )
                    {
                        $ent = Common::Option->new( %{ $ent } );

                        $ent->id( ++$id );
                        $ent->inputdb( $db->name );
                        $ent->dirpath( $db->name );

                        $ent->is_active(1);                        

                        $menu->append_option( $ent );
                    }
                }
            }
            else 
            {
                $ent = Common::Option->new( "name" => $db->name, 
                                            "label" => $db->label );
                
                $ent->id( ++$id );
                $ent->inputdb( $db->name );
                $ent->dirpath( $db->name );

                $ent->is_active(0);
                
                $menu->append_option( $ent );
            }
        }
    }

    return $menu;
}

sub create_nav_menu_ali
{
    # Niels Larsen, October 2006.

    # Looks at the installed alignment data for a given list of registry 
    # database ids and creates a menu structure that reflects these. 

    my ( $class,
         $opt,           # ID list
         ) = @_;

    # Returns a menu object. 

    my ( $menu, $db, $ents, $ent, $id, $ali, $rows, $viewers );

    require Ali::IO;

    $menu = Registry::Get->new( "name" => $opt->name, "label" => $opt->label ); 

    # Read entries from each installed database, set required fields,
    # and append them,

    $id = 0;

    foreach $db ( Registry::Get->datasets( $opt->dbnames )->options )
    {
        $viewers = Registry::Get->viewers()->options;
        
        $ents = Registry::Register->read_entries_list( $db->datapath_full, 0 );
        $ents = [ grep { $_->{"datatype"} eq $db->datatype } @{ $ents } ];

        foreach $ent ( @{ $ents } )
        {
            next if not Registry::Match->compatible_viewers( $viewers, [ $ent ] );

            $ent = Common::Option->new( %{ $ent } );
            $ent->id( ++$id );

            $ent->inputdb( $db->name .":". $ent->name );
            $ent->dirpath( $db->datapath ."/Installs/". $ent->name .".". $ent->datatype );

            $ent->is_active(1);

            if ( not $ent->label and &Common::Types::is_alignment( $ent->datatype ) )
            {
                $ali = &Ali::IO::connect_pdl( $Common::Config::dat_dir ."/". $ent->dirpath );
                $rows = $ali->max_row + 1;
                undef $ali;
                
                if ( $ent->title ) {
                    $ent->label( $ent->title ." ($rows)" );
                } else {
                    $ent->label( $ent->name ." ($rows)" );
                }
            }
            
            $menu->append_option( $ent );
        }
    }

    return $menu;
}

sub create_nav_menu_rfam
{
    # Niels Larsen, October 2006.

    # Creates navigation menus by crudely dividing the family names into
    # alphabetic groups. Completely specific to Rfam. It is an attempt to make
    # navigation possible by building menus by name. Returns a list of menus. 

    my ( $class,
         $datopt,            # Registry ids 
         ) = @_;

    # Returns a list.

    my ( @dbs, $db, $entries, @names, @names1, @names2, @groups, $name, 
         @opts_2, @opts_3, $opt_2, $num1, $num2, $menu_1, $menu_2, $menu_3, 
         $profile, $opt, $grpname, $dirpath, $ali, $rows, @opts_1, $id, $i,
         $viewers, @entries, $entry );

    require Ali::IO;

    if ( scalar @{ $datopt->dbnames } == 1 )
    {
        $db = Registry::Get->dataset( $datopt->dbnames->[0] );
    }
    else {
        &error( qq (The number of Rfam options should be 1) );
    } 

    $id = 0;

    # Divide the families into crude alphabetic sub-groups, 

    @groups = qw ( 5-C E-H IRES mir I-P Q-R sno U S-Y );
    
    @opts_2 = map { Common::Option->new( "name" => $_ ) } @groups;
    @opts_2 = map { $_->label( " ". $_->name ." " ); $_ } @opts_2;
    @opts_2 = map { $_->method( "array_viewer" ); $_ } @opts_2;
    
    # List all families, 

    $viewers = Registry::Get->viewers()->options;
    
    $entries = Registry::Register->read_entries_list( $db->datapath_full, 1 );
    
    foreach $entry ( @{ $entries } )
    {
        if ( Registry::Match->compatible_viewers( $viewers, [ $entry ] ) ) {
            push @entries, $entry;
        }
    }

    $entries = [ grep { $_->{"datatype"} eq $db->datatype } @entries ];
    $entries = Registry::Get->new( "options" => $entries );
    
    # Make two pools of names,
    
    @names1 = grep { $_ =~ /^(IRES|mir|sno|U\d)/i } map { $_->{"name"} } @{ $entries->options };
    @names2 = grep { $_ !~ /^(IRES|mir|sno|U\d)/i } map { $_->{"name"} } @{ $entries->options };

    for ( $i = 0; $i <= $#opts_2; $i++ )
    {
        $opt_2 = $opts_2[$i];
        $grpname = $opt_2->name;
        
        # Grep for the names that belong to a group,
        
        if ( $grpname =~ /^[A-Za-z]+$/ ) {
            @names = grep { $_ =~ /^$grpname/ix } @names1;
        } else {
            @names = grep { $_ =~ /^[$grpname]/ix } @names2;
        }
        
        # Attempt to sort "mir123" etc by the numbers (123),
        
        if ( $grpname =~ /^mir|U\d/i )
        {
            @names = sort { $a =~ /(\d+)/ and $num1 = $1;
                            $b =~ /(\d+)/ and $num2 = $1;
                            $num1 <=> $num2 } @names;
        } else {
            @names = sort { uc $a cmp uc $b } @names;
        }

        $menu_3 = Registry::Get->new( "name" => $grpname, "label" => " $grpname " );
        
#        @opts_3 = ();
        
        foreach $name ( @names )
        {
            $dirpath = $db->datapath ."/Installs/$name.". $db->datatype;
            
            $ali = &Ali::IO::connect_pdl( "$Common::Config::dat_dir/$dirpath" );
            $rows = $ali->max_row + 1;
            undef $ali;
            
            $opt = Registry::Option->new( "name" => $name );
            
            $opt->label( "$name (". &Common::Util::commify_number( $rows ) .")" );
            $opt->datatype( $db->datatype );

            $opt->id( ++$id );
            $opt->inputdb( $db->name .":$name" );
            $opt->dirpath( $dirpath );

            $opt->method( "array_viewer" );
            
            $menu_3->append_option( &Storable::dclone( $opt ) );
        }

        $opts_2[$i] = &Storable::dclone( $menu_3 );

        $opts_2[$i]->{"inputdb"} = ( $menu_3->options )[0]->inputdb;
        $opts_2[$i]->{"dirpath"} = ( $menu_3->options )[0]->dirpath;
        $opts_2[$i]->{"method"} = "array_viewer";

        $opts_2[$i]->is_active( 1 );
    }
    
    $menu_2 = Registry::Get->new( "name" => $datopt->name,
                                  "label" => $datopt->label,
                                  "options" => \@opts_2 );
    return $menu_2;
}

sub create_profile
{
    # Niels Larsen, April 2007.

    # Creates a directory of files that define navigation menus: when 
    # user clicks for a sub-menu, the options in the corresponding 
    # sub-directory are read. The routine contains dataset-specific
    # calls because of big differences in the datasets. 

    my ( $class,
         $proj,     # Project registry object or name
         ) = @_;

    # Returns nothing.

    my ( $nav_menu, $nav_opts, $opt, $db_names, $sub_menu, 
         $pls_dir, $reg_dir, $www_dir, $proj_dir, $viewer );

    # >>>>>>>>>>>>>>>>>>>>>>>>> MAKE NAVIGATION <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Directories and files define the menus.

    $nav_menu = Registry::Get->new();

    if ( not ref $proj ) {
        $proj = Registry::Get->project( $proj );
    }

    $nav_opts = $proj->navigation;

    if ( &Common::Option::is_option( $nav_opts ) ) {
        $nav_opts = [ $nav_opts ];
    } else {
        $nav_opts = $nav_opts->options;
    }

    $viewer = $proj->defaults->def_viewer;

    # Create navigation menu, with viewer set,

    foreach $opt ( @{ $nav_opts } )
    {
        if ( not ref ( $db_names = $opt->dbnames ) ) {
            $opt->dbnames( [ $db_names ] );
        }

        if ( $opt->name =~ /expr/ )
        {
            $sub_menu = Install::Profile->create_nav_menu( $opt );
            map { $_->method( $viewer ) } $sub_menu->options;
        }            
        elsif ( $opt->name =~ /orgs/ )
        {
            $sub_menu = Install::Profile->create_nav_menu( $opt );
            map { $_->method( "orgs_viewer" ) } $sub_menu->options;
        }
        elsif ( $opt->name =~ /func/ )
        {
            $sub_menu = Install::Profile->create_nav_menu( $opt );
            map { $_->method( "funcs_viewer" ) } $sub_menu->options;
        }
        elsif ( $opt->name =~ /rfam/ )
        {
            $sub_menu = Install::Profile->create_nav_menu_rfam( $opt );
        }
        else
        {
            $sub_menu = Install::Profile->create_nav_menu_ali( $opt );

            map { $_->method( "array_viewer" ) } $sub_menu->options;
        }
        
        $sub_menu->is_active( 1 );
        $nav_menu->append_option( $sub_menu );
    }

    Install::Profile->delete_site_navigation( $proj->projpath );
    Install::Profile->create_site_navigation( $proj, $nav_menu );
    Install::Profile->create_regentries_menu( $proj );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SET LINKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set link to CGI script. There is only one CGI script, index.cgi, 
    # which lives in the perl scripts directory, but each subproject 
    # should link to it,

    $www_dir = $Common::Config::www_dir;
    $proj_dir = "$Common::Config::www_dir/". $proj->projpath;
    $reg_dir = $Common::Config::conf_proj_dir;
    $pls_dir = $Common::Config::pls_dir;

    &Common::File::delete_file_if_exists( "$www_dir/index.cgi" );
    &Common::File::create_link( "$pls_dir/index.cgi", "$www_dir/index.cgi" );

    &Common::File::delete_file_if_exists( "$proj_dir/index.cgi" );
    &Common::File::create_link( "$pls_dir/index.cgi", "$proj_dir/index.cgi" );

    &Common::File::delete_file_if_exists( "$proj_dir/site_profile.txt" );
    &Common::File::create_link( "$reg_dir/". $proj->name, "$proj_dir/site_profile.txt" );

    return;
}

sub create_regentries_menu
{
    # Niels Larsen, December 2006.

    # Creates a menu file with all the installed data for a given subproject.
    # It does this by looking through the installation hiearchy and reading 
    # the "regentries.yaml" files that the install_data routine puts in 
    # each data directory. 

    my ( $class,
         $proj,         # Project definition from registry
         ) = @_;

    # Returns nothing. 

    my ( %opts, @opts, @names, $name, $db, $ents, $ent, $menu, $file, $ent_name, $ent_type );

    if ( $proj->datasets )
    {
        if ( ref $proj->datasets ) {
            push @names, @{ $proj->datasets };
        } else {
            push @names, $proj->datasets;
        }
    }

    if ( $proj->datasets_other )
    {
        if ( ref $proj->datasets_other ) {
            push @names, @{ $proj->datasets_other };
        } else {
            push @names, $proj->datasets_other;
        }
    }

    %opts = ();

    foreach $name ( @names )
    {
        if ( Registry::Register->registered_datasets( $name ) )
        {
            $db = Registry::Get->dataset( $name );
            $ents = Registry::Register->read_entries_list( $db->datapath_full, 0 );

            if ( $db->is_local_db and defined $ents and @{ $ents } )
            {
                foreach $ent ( @{ $ents } )
                {
                    $ent_name = $db->name .":". $ent->name;
                    $ent_type = $ent->datatype;

                    if ( exists $opts{ $ent_name }{ $ent_type } )
                    {
                        push @{ $opts{ $ent_name }{ $ent_type }->formats }, $ent->format;
                    }
                    else 
                    {
                        $opts{ $ent_name }{ $ent_type } = 
                            Registry::Option->new(
                                "name" => $db->name .":". $ent->name,
                                "title" => $ent->title,
                                "datatype" => $ent->datatype,
                                "formats" => [ $ent->format ],
                                "datadir" => $db->datadir || "",
                            );
                    }
                }
            }

            # Is there ever any need for this?
#             else
#             {
#                 $opts{ $ent_name }{ $ent_type } = 
#                     Registry::Option->new(
#                         "name" => $db->name,
#                         "title" => $db->title,
#                         "datatype" => $db->datatype,
#                         "formats" => [ $db->format ],
#                         "datadir" => $db->datadir || "",
#                     );
#             }
        }
    }

    @opts = ();

    foreach $ent_name ( keys %opts )
    {
        foreach $ent_type ( keys %{ $opts{ $ent_name } } )
        {
            push @opts, $opts{ $ent_name }{ $ent_type };
        }
    }

    if ( @opts )
    {
        $menu = Common::Menu->new( "options" => \@opts );
        
        if ( defined wantarray )
        {
            return $menu;
        }
        else {
            $file = "$Common::Config::www_dir/". $proj->projpath ."/regentries_menu.yaml";
            &Common::File::write_yaml( $file, $menu );
        }
    }

    return;
}

sub _create_site_navigation_recurse
{
    # Niels Larsen, December 2006.
    
    # Creates a file tree version of a given navigation menu tree. 

    my ( $dir,                    # Starting directory path
         $nav_menu,               # Menu structure
         $depth,                  # 
        ) = @_;
    
    my ( $menu, $obj, $opt, $path, $nav_file, $opts_file, $opts, $id, 
         @opts, $prefix, %dbs );
    
    $depth = 0 if not defined $depth;

    # Get starting id and existing options, if any, so we can add to those,
        
    $nav_file = "$dir/navigation_menu";

    if ( -e "$nav_file.yaml" )
    {
        $menu = &Common::File::read_yaml( "$nav_file.yaml" );
        $id = ( $menu->options )[-1]->id;
    }
    else {
        $menu = Registry::Get->new(); 
        $id = 0;
    }
    
    @opts = $menu->options;
    
    if ( not @{ $nav_menu->options } ) {
        &dump( $nav_menu );
        &error( "Menu ". $nav_menu->name ." has no options - are all datasets installed?" );
    }
    
    %dbs = map { $_->name, $_ } Registry::Get->datasets();
    
    foreach $obj ( $nav_menu->options )
    {
        $opt = Registry::Option->new(
            "id" => ++$id,
            "name" => $obj->name,
            "label" => $obj->label,
            "method" => $obj->{"method"} || "",
            "inputdb" => $obj->{"inputdb"} || "",
            "dirpath" => $obj->{"dirpath"} || "",
            "title" => $obj->title || "",
            "is_active" => $obj->is_active || 0,
            "selected" => $obj->selected || 0,
            );

        if ( ( ref $obj ) =~ /::Get$/ )
        {
            $path = $obj->name;
            
            &Common::File::create_dir_if_not_exists( "$dir/$path" );
            Install::Profile::_create_site_navigation_recurse( "$dir/$path", $obj, $depth+1 );
        }
        else
        {
            if ( $depth > 0 ) {
                $opt->datatype( $obj->datatype );
            }

            foreach $prefix ( "controls", "decorations" )
            {
                $opts_file = "$Common::Config::dat_dir/". $opt->inputdb ."/$prefix.dump";
                
                if ( -r $opts_file )
                {
                    $opts = &Common::File::eval_file( $opts_file );
                    $path = $opt->name;
                    &Common::File::create_dir_if_not_exists( "$dir/$path" );                
                    &Common::File::write_yaml( "$dir/$path/$prefix.yaml", $opts );
                }
            }
        }
        
        @opts = grep { $_->name ne $opt->name } @opts;
        push @opts, $opt;
        
    }
    
    $opts[0]->default( 1 );
    
    $menu->options( \@opts );
    
    &Common::File::write_yaml( "$nav_file.yaml", $menu );
    
    return;
};

sub create_site_navigation
{
    # Niels Larsen, October 2006.

    # Writes several navigation menus and files into WWW-root. IN FLUX

    my ( $class,
         $proj,
         $nav_menu,
         ) = @_;

    # Returns nothing.

    my ( $site_dir, $text, @opts );

    # >>>>>>>>>>>>>>>>>>>>>>>> WRITE SITE NAVIGATION <<<<<<<<<<<<<<<<<<<<<<

    # Create site directory,

    $site_dir = "$Common::Config::www_dir/". $proj->projpath;
    &Common::File::create_dir_if_not_exists( $site_dir );
    
    Install::Profile::_create_site_navigation_recurse( $site_dir, $nav_menu );

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE SITE PROFILE <<<<<<<<<<<<<<<<<<<<<<<<

#     if ( not -e "$site_dir/site_profile.txt" )
#     {
#         $text = Install::Profile->site_profile_text( $proj );

#         &Common::File::write_file( "$site_dir/site_profile.txt", $text );
#     }

    return;
}

sub delete_site_navigation
{
    # Niels Larsen, October 2006.

    # Removes a given site or site subdirectory. This involves deleting the 
    # directory (but not the profile description, unless with the force options),
    # and removing the subdirectory from the parent navigation menu (if any).
    # If the path does not exist, the routine quietly does nothing. 

    my ( $class,
         $path,       # Path like "RRNA/organisms"
         $force,      # Force flag
         ) = @_;
    
    # Returns nothing. 

    my ( $text, $dir, @path, $file, $menu, @opts );

    $force = 0 if not defined $force;

    $dir = "$Common::Config::www_dir/$path";
    &Common::File::delete_dir_tree_if_exists( $dir );

    @path = split "/", $path;
    $path = join "/", @path[ 0 .. $#path - 1 ];
    $file = "$Common::Config::www_dir/$path/navigation_menu";

    if ( -r "$file.yaml" )
    {
        $menu = Registry::Get->read_menu( $file );
        @opts = grep { $_->name !~ $path[-1] } $menu->options;
        
        $menu->options( \@opts );
        
        &Common::File::write_yaml( "$file.yaml", $menu );
    }
    
    return;
}

sub get_httpd_user
{
    my ( $name, @lines, $file, $user, $group );

    if ( -r "/etc/passwd" and -r "/etc/group" )
    {
        @lines = split "\n", ${ &Common::File::read_file( "/etc/passwd" ) };

        foreach $name ( "daemon", "apache", "nobody" )
        {
            if ( grep /^$name\W/, @lines ) {
                $user = $name;
                last;
            }
        }

        @lines = split "\n", ${ &Common::File::read_file( "/etc/group" ) };

        foreach $name ( "daemon", "apache", "nobody" )
        {
            if ( grep /^$name\W/, @lines ) {
                $group = $name;
                last;
            }
        }
    }

    $user = "daemon" if not defined $user;
    $group = "daemon" if not defined $group;
    
    return ( $user, $group );
}

sub mysql5_config_text
{
    # Niels Larsen, March 2005.

    # Returns the content for the mysql configuration file, which the
    # mysql install routine writes. 

    my ( $inst_name,       # Installation directory name
         $port_num,        # Port number
         ) = @_;

    # Returns a string. 

    my ( $content, $hostname );

    $hostname = &Sys::Hostname::hostname();

    $content = qq (#
# This file is written by the installation procedure. Changes made 
# here will disappear if mysql is re-installed. 

# MySQL run-time options

\[client\]

port = $port_num
socket = $Common::Config::db_sock_file

\[mysqld\]

port = $port_num
socket = $Common::Config::db_sock_file
pid-file = $Common::Config::db_pid_file

tmpdir = $Common::Config::tmp_dir
datadir = $Common::Config::dat_dir/$inst_name
basedir = $Common::Config::pki_dir/$inst_name

skip-external-locking
skip-networking

ft_min_word_len=3
ft_stopword_file=\"\"

key_buffer = 256M
bulk_insert_buffer_size = 256M
max_allowed_packet = 32M
table_cache = 512
read_buffer_size = 128M
sort_buffer_size = 128M
read_rnd_buffer_size = 128M
myisam_sort_buffer_size = 256M
thread_cache_size = 8
thread_concurrency = 8

query_cache_limit = 15M
query_cache_size = 256M
query_cache_type = 1

slow_query_log = 1
slow_query_log_file = $Common::Config::log_dir/$inst_name/mysql_slow.log

general_log = 0
general_log_file = $Common::Config::log_dir/$inst_name/mysql.log

server-id = 1

[mysql]
no-auto-rehash

[isamchk]

key_buffer = 256M
sort_buffer_size = 256M
read_buffer = 32M
write_buffer = 32M

[myisamchk]

key_buffer = 256M
sort_buffer_size = 256M
read_buffer = 32M
write_buffer = 32M

[mysqldump]

quick
max_allowed_packet = 16M

    );

    return $content;
}

1;

__END__
