package Registry::Register;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Methods that register, unregister and list items installed.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use Registry::Get;

use Common::Config;
use Common::Messages;

use base qw ( Common::Menu );

my $Adm_dir = $Common::Config::adm_inst_dir;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# _register
# _registered
# _unregister
# _unregistered
# _all_registered
# delete_entries_list
# delete_timestamp
# get_timestamp
# is_registered_option
# needs_import
# read_entries
# read_entries_list
# set_timestamp
# type_to_file
# unregistered
# write_decorations_list
# write_entries
# write_entries_list
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our %Auto_functions = (
    "registered_analyses" =>       [ "_registered",  "registered_analyses" ],
    "registered_perl_modules" =>   [ "_registered",  "registered_perl_modules" ],
    "registered_python_modules" => [ "_registered",  "registered_python_modules" ],
    "registered_utilities" =>      [ "_registered",  "registered_utilities" ],
    "registered_syssoft" =>        [ "_registered",  "registered_syssoft" ],
    "registered_datasets" =>       [ "_registered",  "registered_datasets" ],
    "registered_projects" =>       [ "_registered",  "registered_projects" ],
    "registered_soft_installs" =>  [ "_registered",  "registered_soft_installs" ],

    "unregistered_analyses" =>       [ "_unregistered",  "registered_analyses",       "analysis_software" ],
    "unregistered_perl_modules" =>   [ "_unregistered",  "registered_perl_modules",   "perl_modules" ],
    "unregistered_python_modules" => [ "_unregistered",  "registered_python_modules", "python_modules" ],
    "unregistered_utilities" =>      [ "_unregistered",  "registered_utilities",      "utilities_software" ],
    "unregistered_syssoft" =>        [ "_unregistered",  "registered_syssoft",        "system_software" ],
    "unregistered_datasets" =>       [ "_unregistered",  "registered_datasets",       "datasets" ],
    "unregistered_projects" =>       [ "_unregistered",  "registered_projects",       "projects" ],
    "unregistered_soft_installs" =>  [ "_unregistered",  "registered_soft_installs",  "sinstalls" ],

    "register_analyses" =>         [ "_register",  "registered_analyses" ],
    "register_perl_modules" =>     [ "_register",  "registered_perl_modules" ],
    "register_python_modules" =>   [ "_register",  "registered_python_modules" ],
    "register_utilities" =>        [ "_register",  "registered_utilities" ],
    "register_syssoft" =>          [ "_register",  "registered_syssoft" ],
    "register_datasets" =>         [ "_register",  "registered_datasets" ],
    "register_projects" =>         [ "_register",  "registered_projects" ],
    "register_soft_installs" =>    [ "_register",  "registered_soft_installs" ],

    "unregister_analyses" =>       [ "_unregister",  "registered_analyses" ],
    "unregister_perl_modules" =>   [ "_unregister",  "registered_perl_modules" ],
    "unregister_python_modules" => [ "_unregister",  "registered_python_modules" ],
    "unregister_utilities" =>      [ "_unregister",  "registered_utilities" ],
    "unregister_syssoft" =>        [ "_unregister",  "registered_syssoft" ],
    "unregister_datasets" =>       [ "_unregister",  "registered_datasets" ],
    "unregister_projects" =>       [ "_unregister",  "registered_projects" ],
    "unregister_soft_installs" =>  [ "_unregister",  "registered_soft_installs" ],
    );

sub AUTOLOAD
{
    # Niels Larsen, April 2009.

    # Dispatches calls to functions not explicitly defined in this module. If the
    # method is a key in the %Auto_functions, calls are made to the functions in 
    # that hash.
    
    my ( $self,
         $names,
         ) = @_;

    # Returns scalar or hash.

    our $AUTOLOAD;

    my ( $routine, $method, $getmethod, $file, %args );
    
    $AUTOLOAD =~ /::(\w+)$/ and $method = $1;

    if ( $Auto_functions{ $method } )
    {
        ( $routine, $file, $getmethod ) = @{ $Auto_functions{ $method } };

        %args = (
            "file" => $file,
            );

        if ( $getmethod ) {
            $args{"method"} = $getmethod;
        }

        return $self->$routine( $names, \%args );
    }
    elsif ( $method ne "DESTROY" )
    {
        $method = "SUPER::$method";
        
        no strict "refs";
        return eval { $self->$method( $names ) };
    }
    
    return;
}

sub _register
{
    # Niels Larsen, April 2009.

    # Add one or more names to a given registry file. Only names are added that
    # are not there already, and a list of those added is returned. 

    my ( $class,
         $names,        # Item name or names
         $args,         # Arguments hash
         ) = @_;

    # Returns a list or nothing. 

    my ( @regnames, %regnames, @add, $name, $file );

    if ( $names ) {
        $names = [ $names ] if not ref $names;
    } else {
        &error( qq (No register names given) );
    }

    @regnames = Registry::Register->_registered( undef, $args );
    %regnames = map { $_, 1 } @regnames;
    
    foreach $name ( @{ $names } )
    {
        if ( not exists $regnames{ $name } )
        {
            push @add, $name;
            $regnames{ $name } = 1;
        }
    }

    if ( @add )
    {
        $file = "$Common::Config::adm_inst_dir/". $args->{"file"};

        push @regnames, @add;

        @regnames = map { "$_\n" } @regnames;

        require Common::File;

        &Common::File::delete_file_if_exists( $file );
        &Common::File::write_file( $file, \@regnames );

        return wantarray ? @add : \@add;
    }
    else {
        return;
    }
}

sub _registered
{
    # Niels Larsen, April 2009.

    # If no names are given, then a list of all registered names is returned.
    # If a name, or a list of names, are given, then the registered ones of 
    # these are returned. 

    my ( $class,
         $names,     # Name or list of names - OPTIONAL
         $args,      # Arguments hash
        ) = @_;

    # Returns a list.

    my ( $method, $file, @regnames, %regnames, $name, @errs, $regname );

    $file = $args->{"file"};

    require Common::File;

    $file = "$Common::Config::adm_inst_dir/$file";

    if ( @errs = &Common::File::access_error( $file, "er", 0 ) ) {
        return;
    }

    @regnames = split "\n", ${ &Common::File::read_file( $file ) };

    if ( $names )
    {
        %regnames = map { lc $_, $_ } @regnames;

        if ( not ref $names ) {
            $names = [ $names ];
        }
        
        @regnames = ();

        foreach $name ( @{ $names } )
        {
            if ( $regname = $regnames{ lc $name } ) {
                push @regnames, $regname;
            }
        }
    }

    if ( @regnames ) {
        return wantarray ? @regnames : \@regnames;
    } else {
        return;
    }
}

sub _unregister
{
    # Niels Larsen, April 2009.

    # Removes one or more names from a given registry file. A list of 
    # names removed is returned. If all names are removed, the registry
    # file is deleted.

    my ( $class,
         $names,        # Option name
         $args,         # Arguments hash
         ) = @_;

    # Returns a list or nothing. 

    my ( @regnames, %regnames, %remove, @remove, $name, $file );

    if ( $names ) {
        $names = [ $names ] if not ref $names;
    } else {
        &error( qq (No unregister names given) );
    }

    @regnames = Registry::Register->_registered( undef, $args );
    %regnames = map { $_, 1 } @regnames;
    
    foreach $name ( @{ $names } )
    {
        if ( exists $regnames{ $name } )
        {
            push @remove, $name;
        }
    }

    if ( @remove )
    {
        %remove = map { $_, 1 } @remove;
        @regnames = grep { not exists $remove{ $_ } } @regnames;

        require Common::File;

        $file = "$Common::Config::adm_inst_dir/". $args->{"file"};

        if ( @regnames )
        {
            @regnames = map { "$_\n" } @regnames;

            &Common::File::delete_file_if_exists( $file );
            &Common::File::write_file( $file, \@regnames );
        }
        else {
            &Common::File::delete_file( $file );
        }

        return wantarray ? @remove : \@remove;
    }
    else {
        return;
    }
}

sub _unregistered
{
    # Niels Larsen, April 2009.
    
    # If no names are given, a list of all unregistered packages are returned.
    # If names are given, only the unregistered out of those are returned.

    my ( $class,
         $names,    # A name or list of names - OPTIONAL
         $args,     # Argument hash
        ) = @_;

    # Returns a list.

    my ( $method, %regnames, @unregnames, @names, $name );

    if ( $names ) 
    {
        if ( not ref $names ) {
            $names = [ $names ];
        }

        @names = @{ $names };
    }
    else
    {
        $method = $args->{"method"};
        @names = map { $_->name } Registry::Get->$method->options;
    }

    %regnames = map { lc $_, 1 } Registry::Register->_registered( undef, $args );

    foreach $name ( @names )
    {
        if ( not exists $regnames{ lc $name } ) {
            push @unregnames, $name;
        }
    }

    if ( @unregnames ) {
        return wantarray ? @unregnames : \@unregnames;
    } else {
        return;
    }
}

sub are_all_registered
{
    # Niels Larsen, May 2009.

    # Returns 1 if all packages of a given data type are registered,
    # nothing otherwise.

    my ( $class,
         $type,         # Datatype
        ) = @_;

    # Returns 1 or nothing.

    my ( $menu, @all, $file, %regs, $name, $count );

    $menu = Registry::Get->softwares();
    $menu->match_options( "datatype" => $type );

    @all = $menu->options_names;

    $file = Registry::Register->type_to_file( $type );

    %regs = map { $_, 1 } Registry::Register->_registered( undef, { "file" => $file } );

    $count = 0;

    foreach $name ( @all )
    {
        if ( not exists $regs{ $name } )
        {
            $count += 1;
        }
    }

    if ( $count ) {
        return;
    } else {
        return 1;
    }
}

sub delete_entries_list
{
    # Niels Larsen, October 2006.

    # Removes the file "entries.yaml" in the given directory, if 
    # it exists.

    my ( $class,
         $dir,
         ) = @_;

    # Returns nothing.
    
    return &Common::File::delete_file_if_exists( "$dir/entries.yaml" );
}

sub delete_timestamp
{
    # Niels Larsen, October 2006.

    # Removes the file "TIME_STAMP" in the directory that corresponds to 
    # a given data path, if the file exists.

    my ( $class,
         $dir,
         ) = @_;

    # Returns nothing.
    
    return &Common::File::delete_file_if_exists( "$dir/TIME_STAMP" );
}

sub get_timestamp
{
    # Niels Larsen, October 2006.

    # Returns the time written into the file "TIME_STAMP" in the directory
    # that corresponds to a given data path. The time is returned as epoch
    # seconds. It is a fatal error if the file is missing.

    my ( $class,
         $dir,       # Data directory
         ) = @_;

    # Returns an integer.

    my ( $file, $timestr, $secs );

    $file = "$dir/TIME_STAMP";

    if ( -e $file )
    {
        $timestr = ${ &Common::File::read_file( $file ) };

        $timestr =~ s/^\s*//;
        $timestr =~ s/\s*$//;

        $secs = &Common::Util::time_string_to_epoch( $timestr );
    }
    else {
        &error( qq (No TIME_STAMP file found in "$dir") );
    }

    return $secs;
}

sub is_registered_option
{
    # Niels Larsen, November 2007.

    # Checks if a given install option is installed. 

    my ( $class,
         $opt,
        ) = @_;

    my ( %soft_opts, %data_opts, $installed, $name );

    $installed = 1;

    %soft_opts = map { $_->name, $_ } @{ Registry::Get->installs_software->options };
    %data_opts = map { $_->name, $_ } @{ Registry::Get->installs_data->options };

    if ( $opt eq "software" )
    {
        foreach $name ( keys %soft_opts )
        {
            if ( not Registry::Register->registered_options( $name ) )
            {
                $installed = 0;
                last;
            }
        }
    }
    elsif ( $opt eq "data" )
    {
        foreach $name ( keys %data_opts )
        {
            if ( not Registry::Register->registered_datasets( $name ) )
            {
                $installed = 0;
                last;
            }
        }
    }
    elsif ( $soft_opts{ $opt } )
    {
        if ( not Registry::Register->registered_syssoft( $opt ) ) {
            $installed = 0;
        }
    }
    elsif ( $data_opts{ $opt } )
    {
        if ( not Registry::Register->registered_datasets( $opt ) ) {
            $installed = 0;
        }
    }
    else {
        &error( qq (Wrong looking option -> "$opt") );
    }

    return $installed;
}
        
sub is_registered_software
{
    # Niels Larsen, April 2009.

    my ( $class,
         $name,      # Software package name
        ) = @_;

    # Returns a list.

    my ( $pkg, $file, %regnames, @errs );

    $pkg = Registry::Get->software( $name );

    $file = Registry::Register->type_to_file( $pkg->datatype );

    require Common::File;

    $file = "$Common::Config::adm_inst_dir/$file";

    if ( not @errs = &Common::File::access_error( $file, "er", 0 ) )
    {
        %regnames = map { lc $_, 1 } split ' ', ${ &Common::File::read_file( $file ) };

        if ( exists $regnames{ lc $name } )
        {
            return 1;
        }
    }

    return;
}

sub read_entries
{
    my ( $class,
         $dir,
        ) = @_;

    my ( @list, $file );

    foreach $file ( &Common::File::list_files( $dir, '\.yaml$' ) )
    {
        push @list, &Common::File::read_yaml( $file->{"path"} );
    }

    if ( @list ) {
        @list = Registry::Get->_objectify( \@list )->options;
    } else {
        &error( qq (No .yaml files found in directory -> "$dir") );
    }

    return wantarray ? @list : \@list;
}

sub read_entries_list
{
    # Niels Larsen, March 2008.

    my ( $class,
         $path,
         $fatal,
         ) = @_;

    my ( $list );

    if ( -d $path ) {
        $path .= "/regentries.yaml";
    } elsif ( not -r $path ) {
        $fatal ? &error( qq (No directory or file -> "$path") ) : return;
    }

    if ( $fatal )
    {
        $list = &Common::File::read_yaml( $path );

        if ( not $list or not @{ $list } ) {
            &error( qq (Entries list is empty -> "$path") );
        }
    }
    elsif ( -r $path )
    {
        $list = &Common::File::read_yaml( $path );
    }

    if ( $list and @{ $list } ) {
        $list = Registry::Get->_objectify( $list )->options;
    }

    return $list;
}

sub registered
{
    my ( $class,
         $types,
        ) = @_;

    my ( @names, $type, $file );

    if ( not ref $types ) {
        $types = [ $types ];
    }

    foreach $type ( @{ $types } )
    {
        $file = Registry::Register->type_to_file( $type );

        push @names, Registry::Register->_registered( undef, { "file" => $file } );
    }

    return wantarray ? @names : \@names;
}

sub type_to_file
{
    my ( $class,
         $type,
        ) = @_;
    
    my ( %files, $file );

    %files = (
        "soft_sys" => "registered_syssoft",
        "soft_util" => "registered_utilities",
        "soft_anal" => "registered_analyses",
        "soft_perl_module" => "registered_perl_modules",
        "soft_python_module" => "registered_python_modules",
        "soft_ruby_module" => "registered_ruby_modules",
        );

    if ( $file = $files{ $type } ) {
        return $file;
    } else {
        &error( qq (Wrong looking type -> "$type") );
    }
    
    return;
}

sub unregistered
{
    my ( $class,
         $types,
         $method,
        ) = @_;

    my ( @names, $type, $file );

    if ( not ref $types ) {
        $types = [ $types ];
    }

    foreach $type ( @{ $types } )
    {
        $file = Registry::Register->type_to_file( $type );

        push @names, Registry::Register->_unregistered( undef,
                                                      {
                                                          "file" => $file,
                                                          "method" => $method,
                                                      } );
    }

    return wantarray ? @names : \@names;
}
        
sub set_timestamp
{
    # Niels Larsen, October 2006.

    # Writes the current time into the file "TIME_STAMP" in the directory
    # that corresponds to a given data path. If the file exists it is 
    # overwritten. 

    my ( $class,
         $dir,        # Data directory
         ) = @_;

    # Returns nothing.

    my ( $file, $timestr, $fh, $secs );

    $file = "$dir/TIME_STAMP";

    &Common::File::delete_file_if_exists( $file );

    $timestr = &Common::Util::epoch_to_time_string();

    &Common::File::write_file( $file, "$timestr\n" );

    return;
}

sub write_decorations_list
{
    # Niels Larsen, October 2006.

    my ( $class,
         $list,
         $path,
         ) = @_;

    if ( -d $path ) {
        $path .= "/decorations.yaml";
    }; 
        
    Registry::Register->write_entries_list( $list, $path );

    return;
}

sub write_entries_list
{
    # Niels Larsen, October 2006.

    my ( $class,
         $ents,
         $path,
         ) = @_;

    my ( $list );

    require Data::Structure::Util;

    if ( -d $path ) {
        $path .= "/regentries.yaml";
    }
    
    $list = &Storable::dclone( $ents );
    $list = &Data::Structure::Util::unbless( $list );
    
    &Common::File::write_yaml( $path, [ $list ] );

    return;
}

1;

__END__

    
# sub write_entries
# {
#     # Niels Larsen, September 2008.

#     my ( $class,
#          $entries,
#          $dir,
#          ) = @_;

#     my ( $path, $struct, $entry );

#     require Data::Structure::Util;

#     foreach $entry ( @{ $entries } )
#     {
#         $path = $dir ."/". $entry->name .".yaml";

#         $struct = &Storable::dclone( $entry );
#         $struct = &Data::Structure::Util::unbless( $struct );

#         &Common::File::write_yaml( $path, $struct );
#     }

#     return;
# }

