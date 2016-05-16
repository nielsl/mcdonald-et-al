package Common::Config;   # -*- perl -*- 

# Routines to read configuration files and set perl configuration variables.
# This module is called early during installation, so be careful with adding
# non-core modules here - or "require" such modules within the routines.

use strict; 
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_inline_dir
                 &env_variables
                 &load_hash
                 &set_config_variables
                 &set_env_variable
                 &set_env_variables
                 &set_perl_paths
                 &set_perl5lib_min
                 &format_conf
                 &format_conf_struct
                 &get_code_dirs
                 &get_commandline
                 &get_contacts
                 &get_modules
                 &get_signature
                 &load_list
                 &load_project
                 &parse_config_general
                 &read_config
                 &read_config_general
                 &set_contacts
                 &unset_env_variable
                 &unset_env_variables
                 &unset_perl_paths
                 &write_config_general
                 &write_config_simple
                 );

our $Run_secs;

# >>>>>>>>>>>>>>>>>> INITIALIZE SYSTEM SETTINGS <<<<<<<<<<<<<<<<<<<<

BEGIN
{
    # This section sets environment variables and Perl variables. 
    # This module should therefore be included first in scripts and 
    # other modules. 

    use Data::Dumper;

    sub default_contacts
    {
        my $contacts;

        $contacts = 
        {
            "first_name" => "Niels",
            "last_name" => "Larsen",
            "title" => "Computer biologist, PhD",
            "e_mail" => "niels\@genomics.dk",
            "skype" => "niels_larsen_denmark",
            "mobile" => "+45-3091-5426",
            "telefax" => "",
            "web_home" => "http://genomics.dk",
            "department" => "",
            "company" => "Danish Genome Institute",
            "institution" => "",
            "street" => "Skt\. Lucas Kirkeplads 8",
            "postal_code" => "DK-8000",
            "city" => "Aarhus C",
            "state" => "",
            "country" => "Denmark",
            "time_zone" => "GMT\+1",
        };

        return $contacts;
    }

    sub set_default_config_variables
    {
        $Common::Config::sys_name = "Jrs system";

        $Common::Config::cgi_url = "";
        $Common::Config::css_url = "http://niels-laptop:8001/Software/CSS";
        $Common::Config::jvs_url = "http://niels-laptop:8001/Software/Javascript";
        $Common::Config::font_url = "http://niels-laptop:8001/Software/Fonts";
        $Common::Config::img_url = "http://niels-laptop:8001/Software/Images";

        $Common::Config::with_console_messages = 1;
        $Common::Config::with_errors_dumped = 0;
        $Common::Config::with_contact_info = 1;
        $Common::Config::with_stack_trace = 1;
        $Common::Config::with_warnings = 1;
        $Common::Config::silent = 1;
    }

    sub create_inline_dir
    {
        # Creates an "Inline_C" directory in the directory where this
        # module is located, if it does not exist already, and then puts
        # the compiled C code (source at bottom of this module) there,

        my ( $path,
            ) = @_;

        my $dir;

        require File::Path;

        $dir = $Common::Config::plm_dir ."/Inline_C";
        
        if ( $path ) {
            $dir .= "/$path";
        }

        if ( not -e $dir and not &File::Path::mkpath( $dir ) ) {
            die qq (ERROR: could not create Inline_C directory -> "$dir"\n);
        }

        return $dir;
    }

    sub env_variables
    {
        # Niels Larsen, August 2006.
        
        # Returns a hash of environment variables that the system needs. They
        # can be added to or subtracted from %ENV with the set_env_variables
        # and unset_env_variables routines.
        
        # Returns a hash.
        
        my ( $vars );
        
        # Different names for same things of course,
        
        return
        {
            "BION_HOME" => [ $Common::Config::sys_dir ],
            "TMPDIR" => [ $Common::Config::tmp_dir ],
            "PATH" =>  [
                $Common::Config::bin_dir,
                $Common::Config::sbin_dir,
                $Common::Config::pls_dir,
                $Common::Config::plsa_dir,
                $Common::Config::plsi_dir,
                ],
           "LD_LIBRARY_PATH" => [ $Common::Config::lib_dir ],
           "LDFLAGS" => [ "-L$Common::Config::lib_dir" ],
           "C_INCLUDE_PATH" => [ $Common::Config::inc_dir ],
           "CPLUS_INCLUDE_PATH" => [ $Common::Config::inc_dir ],
           "CPATH" => [ "-I$Common::Config::inc_dir" ],
           "CFLAGS" => [ "-I$Common::Config::inc_dir" ],
           "CPPFLAGS" => [ "-I$Common::Config::inc_dir" ],
           "MANPATH" => [ $Common::Config::man_dir ],
           "LC_ALL" => "C",
           "CURSES_LIBRARY" => [ $Common::Config::lib_dir ],
           "CURSES_INCLUDE_PATH" => [ $Common::Config::inc_dir ],
        }
    }

    sub has_bion_env 
    {
        my ( $home_dir );
        
        if ( $home_dir = $ENV{"BION_HOME"} )
        {
            $Common::Config::sys_dir = $home_dir;

            return $home_dir;
        }

        return;
    }

    sub load_hash
    {
        # Niels Larsen, March 2005.
        
        # Loads a configuration file of keys and values into a hash.
        # All lines that do not start with "#" are examined and if 
        # a given line has a format like 
        # 
        # key = some text
        # 
        # then they will be loaded. Everything else will be silently
        # ignored. 
        
        my ( $file,     # File path
            ) = @_;
        
        # Returns a hash.
        
        my ( $recsep, $content, $line, $config, $key, $val );
        
        if ( not open FILE, $file ) {
            die qq (Could not read-open file -> "$file");
        }
        
        $recsep = $/;
        undef $/;
        
        $content = <FILE>;
        
        if ( not close FILE, $file ) {
            die qq (Could not close read-opened file -> "$file");
        }
        
        $/ = $recsep;
        
        foreach $line ( split "\n", $content )
        {
            if ( $line =~ /^\s*(\w+)\s*=\s*(.+)\s*$/ )
            {
                $key = $1;
                $val = $2;
                $val =~ s/\s*$//;
                
                if ( exists $config->{ $key } )
                {
                    die qq (Duplicate key -> "$key");
                }
                else {
                    $config->{ $key } = $val;
                }
            }
        }
        
        return wantarray ? %{ $config } : $config;
    }

    sub set_config_variables
    {
        # Niels Larsen, March 2005.
        
        # Sets the key/value pairs in a file as variable names in the 
        # Common::Config name space. If a key looks like something_dir a 
        # something_url variable will also be created.
        
        # Returns nothing.
        
        my ( $key, $hash, $value, $sys_dir );
        
        if ( $sys_dir = &Common::Config::has_bion_env() )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>> LOAD FROM FILE <<<<<<<<<<<<<<<<<<<<<<<<<

            $hash = &Common::Config::load_hash( "$sys_dir/Config/Profile/system_paths" );
            
            {
                no strict 'refs';
                no warnings;
                
                foreach $key ( keys %{ $hash } )
                {
                    $value = $hash->{ $key };
                    
                    if ( $key =~ /_dir|_file$/ ) {
                        ${ "Common::Config::$key" } = "$sys_dir/$value";
                    } elsif ( $key =~ /_url$/ and $value and $value !~ /:\/\// ) {
                        ${ "Common::Config::$key" } = "/$value";
                    } else {
                        ${ "Common::Config::$key" } = $value;
                    }
                }
            }
        }
        else {
            &Common::Config::set_default_config_variables();
        }

        return;
    }

    sub set_config_variables_local
    {
        # Niels Larsen, October 2010.

        # Checks the server configuration directory for local settings and writes
        # these into the Common::Config name space. In other words this routine 
        # may override variables set by &set_config_variables above.

        my ( $name, $file, $hash, %conf );

        foreach $name ( qw ( apache mysql ) )
        {
            if ( -r ( $file = "$Common::Config::conf_serv_dir/$name" ) )
            {
                $hash = &Common::Config::load_hash( $file );
                map { $conf{ $_ } = $hash->{ $_ } } ( keys %{ $hash } );
            }
        }

        foreach $name ( keys %conf )
        {
            no strict 'refs';
            no warnings;
                
            ${ "Common::Config::$name" } = $conf{ $name };
        }

        return wantarray ? %conf : \%conf;
    }

    sub set_env_variable
    {
        # Niels Larsen, May 2009.
        
        # Adds the given key and value(s) in $ENV, but only if the value(s)
        # are not there already. Returns nothing, but updates %ENV.
        
        my ( $name,
             $list, 
            ) = @_;
        
        # Returns nothing.
            
        my ( @paths, %paths, $path, $count, $sepch );

        $list = [ $list ] if not ref $list;
        
        if ( exists $ENV{ $name } ) {
            @paths = split ":", $ENV{ $name };
            %paths = map { $_, 1 } @paths;
        } else {
            @paths = ();
            %paths = ();
        }
        
        $count = 0;
        
        foreach $path ( @{ $list } )
        {
            if ( not exists $paths{ $path } ) 
            {
                unshift @paths, $path;
                $count += 1;
            }
        }
        
        if ( $count > 0 )
        {
            if ( $list->[0] =~ /^\-/ ) {
                $sepch = " ";
            } else {
                $sepch = ":";
            }

            $ENV{ $name } = join $sepch, @paths;
        }
        
        return;
    };

    sub set_env_variables
    {
        # Niels Larsen, May 2009.

        # Add paths to %ENV that are needed for installation and running. Doing
        # this here, in a shell independent way, saves the trouble of maintaining 
        # files for different shells. Returns nothing, but updates %ENV.

        # Returns nothing. 

        my ( $name, $vars );

        $vars = &Common::Config::env_variables();

        foreach $name ( keys %{ $vars } )
        {
            if ( $name eq "TMPDIR" ) 
            {
                $ENV{"TMPDIR"} = $Common::Config::tmp_dir; #  if not $ENV{"TMPDIR"};
            }
            else {
                &Common::Config::set_env_variable( $name, $vars->{ $name } );
            }
        }

        # $PERL5LIB,

        $ENV{"PERL5LIB"} = join ":", @INC;

        return;
    }

    sub set_perl_paths
    {
        # Niels Larsen, May 2009.

        # Add our custom locations to @INC, so loading of perl modules will work. 
        # Module writers put them in many places under a given PREFIX, thus the 
        # number of paths added by this routine. Paths are only added if they are
        # missing. Returns nothing, but updates the global @INC.

        my ( $modi_dir, $version, $major, $minor, $path, @paths, $dir, %inc, 
             $str, $perl );

        # General paths to add to @INC,

        @paths = (
            $Common::Config::sys_dir,
            "$Common::Config::pemi_dir/lib/perl5",
            );
        
        # Architecture specific paths,
        
        $str = `perl -V:archname`; 
        chomp $str;
        
        if ( $str =~ /^archname='([^\']+)';$/ )
        {
            push @paths, "$Common::Config::pemi_dir/lib/perl5/$1";
        }
        else {
            die qq (Wrong looking architecture string -> "$str");
        }
        
        # Add to @INC but only if missing,

        %inc = map { $_, 1 } @INC;

        foreach $path ( @paths )
        {
            if ( not exists $inc{ $path } )
            {
                push @INC, $path;
            }
        }
        
        return;
    }

    &Common::Config::set_config_variables();

    if ( &Common::Config::has_bion_env() )
    {
        &Common::Config::set_perl_paths();
        &Common::Config::set_env_variables();

        &Common::Config::set_config_variables_local();
    }
}

# use constant IS_MODPERL => $ENV{"MOD_PERL"};

# if (IS_MODPERL) {
#     tie *STDOUT, 'Apache';
# } else {
#     open (STDOUT, ">-");
# }

select STDERR; $| = 1;         # make unbuffered
select STDOUT; $| = 1;         # make unbuffered

# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub format_conf_struct
{
    # Niels Larsen, January 2010.

    # Formats a Config::General string from a given data structure.

    my ( $ref,
         $tag,
        ) = @_;

    # Returns a hash. 

    my ( $string );

    if ( not ref $ref eq "HASH" ) {
        &Common::Messages::error( qq (The given structure must be a hash reference) );
    }

    require Config::General;

    if ( defined $tag ) {
        $string = &Config::General::SaveConfigString( { $tag => $ref } );
    } else {
        $string = &Config::General::SaveConfigString( $ref );
    }        

    return $string;
}

sub get_code_dirs
{
    # Niels Larsen, March 2005.

    # Returns a list of the code directories in the Config/code_dirs file. 

    # Returns a hash.

    my ( @dirs, $sys_dir );

    if ( $Common::Config::sys_dir )
    {
        @dirs = (
            $Common::Config::recp_dir,
            $Common::Config::dat_reg_dir,
            $Common::Config::soft_reg_dir,
            $Common::Config::adm_inst_dir,
            $Common::Config::conf_cont_dir,
            $Common::Config::shell_dir,
            $Common::Config::conf_clu_dir,
            $Common::Config::conf_prof_dir,
            $Common::Config::conf_proj_dir,
            # $Common::Config::css_dir,
            # $Common::Config::jvs_dir,
            $Common::Config::plm_dir,
            $Common::Config::pls_dir,
            $Common::Config::www_dir,
#            $Common::Config::adm_dir,
            $Common::Config::doc_dir,
            );
    }
    else {
        die "BION_HOME is not defined";
    }

    return wantarray ? @dirs : \@dirs;
}

sub get_commandline
{
    # Niels Larsen, April 2008.

    # Invokes Getopt::Long using a hash of defaults. The values of this 
    # hash can be any string and the keys should be one of 
    # 
    # param=s
    # param:s
    # param!
    #
    # Returns a hash with values set from the command line. 
    
    my ( $defs,
        ) = @_;

    # Returns a hash.

    my ( %args, $args, $key );

    require Getopt::Long;
    require Registry::Args;

    foreach $key ( keys %{ $defs } )
    {
        if ( $key =~ /(.+?)([!:=][siof]*)$/ )
        {
            $args->{ $1 } = $defs->{ $key };
            $args{ $key } = \$args->{ $1 };
        }
        else {
            &Common::Messages::error( qq (Wrong looking key -> "$key".) );
        }
    }

    local $SIG{__DIE__};
    $SIG{__DIE__} = "";

    # local $SIG{__WARN__};
    # $SIG{__WARN__} = "";
    
    if ( not &Getopt::Long::GetOptions( %args ) )
    {
        exit -1;
    }

    $args = &Registry::Args::check( 
        $args,
        { 
            "S:1" => [ keys %{ $args } ],
        });

    return wantarray ? %{ $args } : $args;
}

sub get_contacts
{
    # Niels Larsen, March 2005.

    # Returns a hash with the key/value pairs in the 
    # Config/contacts file. 

    # Returns a hash.

    my ( $hash, $file );

    if ( &Common::Config::has_bion_env() )
    {
        if ( -r ( $file = "$Common::Config::conf_cont_dir/admin_contacts" ) ) {
            $hash = &Common::Config::load_hash( $file );
        } else {
            $hash = &Common::Config::load_hash( "$Common::Config::soft_reg_dir/provider_contacts" );
        }
    }
    else {
        $hash = &Common::Config::default_contacts();
    }

    bless $hash;

    return wantarray ? %{ $hash } : $hash;
}

sub get_signature
{
    # Niels Larsen, March 2005.

    # Returns a author/contact string to be shown in programs. 

    # Returns a string.

    my ( $str, $contacts );

    $contacts = &Common::Config::get_contacts();

    $str = "";
    $str .= $contacts->{"first_name"} ." ";
    $str .= $contacts->{"last_name"} .", ";
    $str .= $contacts->{"e_mail"};

    return $str;
}
    
sub load_list
{
    # Niels Larsen, March 2005.

    # Returns a list of all non-empty lines in a given file that do not start 
    # with "#". Starting and trailing blanks are removed. 

    my ( $file,    # File path
         ) = @_;

    # Returns a list.

    require Common::File;

    my ( @list, $content, $line );

    $content = ${ &Common::File::read_file( $file ) };

    foreach $line ( split "\n", $content )
    {
        if ( $line =~ /\w/ and $line !~ /^\#/ )
        {
            $line =~ s/^\s*//;
            $line =~ s/\s*$//;

            push @list, $line;
        }
    }

    return wantarray ? @list : \@list;
}

sub load_project
{
    # Niels Larsen, March 2008.

    # Returns a project structure from the registry by reading the file 
    # site_profile.txt in the WWW document root. 

    my ( $dir,       # Project directory, e.g. "RRNA" or "rrna"
         ) = @_;

    # Returns nothing. 

    require Common::File;
    require Cwd;

    my ( $hash, $proj, $key, $site_dir, $link_file, $txt_file, $bin_file );

    if ( not $dir ) {
        &Common::Messages::error( qq (No project directory given.) );
    }
    
    $site_dir = "$Common::Config::www_dir/$dir";

    if ( -l ( $link_file = "$site_dir/site_profile.txt" ) )
    {
        $txt_file = &Cwd::abs_path( $link_file );

        if ( not defined $txt_file ) {
            &Common::Messages::error( qq (Broken link -> "$link_file") );
        } elsif ( not -r $txt_file ) {
            &Common::Messages::error( qq (Config file not readable -> "$txt_file") );
        }
    }
    else {
        &Common::Messages::error( qq (Link file does not exist -> "$link_file") );
    }

    $bin_file = "$site_dir/site_profile.bin";
    
    if ( -r $bin_file and -M $bin_file <= -M $txt_file )
    {
        # If binary file present and no older than text file, read
        # it, but check for eval errors (can happen with software 
        # upgrade or something),
        
        eval
        { 
            local $SIG{__DIE__} = undef;
            local $SIG{__WARN__} = undef;
            
            $proj = &Common::File::retrieve_file( $bin_file );
        };
    }
        
    if ( $@ or not -r $bin_file or -M $bin_file > -M $txt_file )
    {
        # If binary could not be read, or if text file is younger,
        # recreate the profile and store it, so edits in the text 
        # file has immediate effect,
        
        require Registry::Get;
        require Install::Profile;
        
        $proj = Registry::Get->project( lc $dir );
        
#            Install::Profile->create_profile( $proj );
        &Common::File::store_file( $bin_file, $proj );
    }
    
    return $proj;
}

sub parse_config_general
{
    # Niels Larsen, January 2010.

    # Parses a Config::General formatted string. A hash is returned. 

    my ( $string,
        ) = @_;

    # Returns a hash. 

    my ( %conf );

    require Config::General;

    %conf = new Config::General( "-String" => $string )->getall;

    return wantarray ? %conf : \%conf;
}

sub read_config_general
{
    # Niels Larsen, January 2010.

    # Reads or Config::General formatted file, or parses a similarly 
    # formatted string. A hash is returned. 

    my ( $file,
        ) = @_;

    # Returns a hash. 

    my ( %conf, $conf );

    if ( -r $file )
    {
        require Config::General;
        require Tie::IxHash;
        
        $conf = new Config::General(
            -ConfigFile => $file,
            -InterPolateVars => 0,
            -SplitPolicy => "custom",
            -SplitDelimiter => ' *= *',
            -CComments => 0,
            -Tie => "Tie::IxHash",
            );

        tie %conf, "Tie::IxHash";

        %conf = $conf->getall;
    }
    else {
        &Common::Messages::error( qq (Config file is not readable -> "$file") );
    }

    return wantarray ? %conf : \%conf;
}
    
sub set_contacts
{
    # Niels Larsen, March 2005.

    # Sets the key/value pairs in the Config/contacts file as 
    # variable names in the Common::Contact name space. 
    
    # Returns nothing. 

    my ( $hash, $key );

    $hash = &Common::Config::get_contacts();

    no strict 'refs';

    foreach $key ( keys %{ $hash } )
    {
        ${ "Common::Contact::$key" } = $hash->{ $key };
    }

    return;
}

sub format_conf
{
    my ( $text,
         %args,
        ) = @_;

    my ( @text, $comments, $indent, $blanks );

    $comments = $args{"comments"} // 1;
    $indent = $args{"indent"} // 0;

    @text = split "\n", $text;

    if ( $indent )
    {
        $blanks = " " x $indent;
        @text = map { "$blanks$_" } @text;
    }

    if ( not $comments ) {
        @text = grep { $_ =~ /\w/ and $_ !~ /^\s*#/ } @text;
    }

    $text = ( join "\n", @text ) ."\n";

    return $text;
}

sub set_perl5lib_min
{
    # Niels Larsen, January 2012. 
    
    # Sets $ENV{"PERL5LIB"} to the minimum. TODO: PERL5LIB and INC are badly
    # treated throughout and this is just bandaid. 
    
    my ( @paths, $str );
    
    # General paths to add to @INC,
    
    @paths = (
        $Common::Config::sys_dir,
        $Common::Config::plm_dir,
        $Common::Config::soft_dir,
        "$Common::Config::pemi_dir/lib/perl5",
        );
    
    # Architecture specific paths,
    
    $str = `perl -V:archname`; 
    chomp $str;
    
    if ( $str =~ /^archname='([^\']+)';$/ )
    {
        push @paths, "$Common::Config::pemi_dir/lib/perl5/$1";
    }
    else {
        die qq (Wrong looking architecture string -> "$str");
    }

    $ENV{"PERL5LIB"} = join ":", @paths;

    return;
}

sub unset_env_variable
{
    # Niels Larsen, May 2009.

    # Subtracts the given list of paths from the named %ENV.

    my ( $name,
         $list,
         ) = @_;

    # Returns nothing.

    my ( @paths, %list, $sepch );

    if ( exists $ENV{ $name } )
    {
        if ( $ENV{ $name } =~ /^\-/ ) {
            $sepch = " ";
        } else {
            $sepch = ":";
        }

        $list = [ $list ] if not ref $list;

        @paths = split $sepch, $ENV{ $name };
        %list = map { $_, 1 } @{ $list };

        @paths = grep { not exists $list{ $_ } } @paths;

        if ( @paths ) {
            $ENV{ $name } = join $sepch, @paths;
        } else {
            delete $ENV{ $name };
        }
    }

    return;
}

sub unset_env_variables
{
    # Niels Larsen, April 2005.

    # Subtracts BION related variables from %ENV.

    # Returns nothing.

    my ( $env, $key );

    $env = &Common::Config::env_variables();

    foreach $key ( keys %{ $env } )
    {
        &Common::Config::unset_env_variable( $key, $env->{ $key } );
    }

    &Common::Config::unset_env_variable( "PERL5LIB", \@INC );

    return;
}

# sub unset_perl_paths
# {
#     # Niels Larsen, January 2012.
    
#     # Add our custom locations to @INC, so loading of perl modules will work. 
#     # Module writers put them in many places under a given PREFIX, thus the 
#     # number of paths added by this routine. Paths are only added if they are
#     # missing. Returns nothing, but updates the global @INC.
    
#     my ( @perl5lib, $modi_dir, $version, $major, $minor, $path, @paths, $dir, %inc, 
#          $str, $perl );
    
#     # General paths to add to @INC,
    
#     @perl5lib = split ":", $ENV{"PERL5LIB"};

#     @paths = (
#         $Common::Config::sys_dir,
#         "$Common::Config::pemi_dir/lib/perl5",
#         );
    
#     # Architecture specific paths,
    
#     $str = `perl -V:archname`; 
#     chomp $str;
    
#     if ( $str =~ /^archname='([^\']+)';$/ )
#     {
#         push @paths, "$Common::Config::pemi_dir/lib/perl5/$1";
#     }
#     else {
#         die qq (Wrong looking architecture string -> "$str");
#     }
    
#     # Add to @INC but only if missing,
    
#     %inc = map { $_, 1 } @INC;
    
#     foreach $path ( @paths )
#     {
#         if ( not exists $inc{ $path } )
#         {
#             push @INC, $path;
#         }
#     }
    
#     return;
# }

sub write_config_general
{
    # Niels Larsen, January 2010.

    # Writes a Config::General formatted file. 

    my ( $file,
         $ref,
         $tag,
        ) = @_;

    # Returns a hash. 

    my ( %conf );

    require Config::General;

    if ( defined $tag ) {
        &Config::General::SaveConfig( $file, { $tag => $ref } );
    } else {
        &Config::General::SaveConfig( $file, $ref );
    }

    return;
}

1;

__END__

# sub set_env_variables
# {
#     # Niels Larsen, April 2005.

#     # Adds BION related variable settings to %ENV. 

#     # Returns nothing.

#     my ( $env, $key );

#     $env = &Common::Config::env_variables();

#     foreach $key ( keys %{ $env } )
#     {
#         &Common::Config::set_env_variable( $key, $env->{ $key } );
#     }

#     return;
# }

# sub set_env_variable
# {
#     # Niels Larsen, August 2006.

#     # Adds the given key and value in $ENV, but only if the value is 
#     # not there already. If the value is a list, each element is added
#     # if it is not there already; if it is a scalar then that becomes 
#     # the new value (overwrites). 
    
#     my ( $key,
#          $value,
#          ) = @_;

#     # Returns nothing.

#     my ( $elem );

#     if ( ref $value eq "ARRAY" )
#     {
#         foreach $elem ( @{ $value } )
#         {
#             if ( exists $ENV{ $key } and $ENV{ $key } !~ /$elem/ )
#             {
#                 if ( $elem =~ /^\-/ ) {
# #                    $ENV{ $key } .= " $elem";  # flags
#                     $ENV{ $key } = "$elem $ENV{ $key }";  # flags
#                 } else {
# #                    $ENV{ $key } .= ":$elem";  # paths
#                     $ENV{ $key } = "$elem:$ENV{ $key }";  # paths
#                 }
#             }
#             elsif ( not exists $ENV{ $key } ) {
#                 $ENV{ $key } = $elem;
#             }
#         }
#     }
#     elsif ( not ref $value )
#     {
#         $ENV{ $key } = $value;
#     }
#     else {
#         &Common::Messages::error( qq (\$value should be either plain string or list) );
#     }

#     return;
# }
