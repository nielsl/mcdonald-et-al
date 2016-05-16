package Registry::Get;            # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that pull out single or multiple items from the registry.
# Some are declared explicitliy and some are dynamic with AUTOLOAD. For
# listing and filtering, see the Registry::List module. 
#
# Inherits from Common::Menu. See also the Registry::List module, with
# functions that return tables and does some logic on top of the simple
# get operations in here. 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# _get_file_item
# _get_file_items
# _get_file_item_ids
# _get_item
# _get_items
# _get_item_ids
# _get_software
# _objectify
# analysis_software
# analysis_cmdlines
# data_fields
# datasets_type
# datatypes_to_formats
# installs_data
# installs_software
# method_input_formats
# method_input_types
# methods_iformats_to_formats
# method_max
# method_min
# objectify_datasets
# objectify_methods
# objectify_viewers
# organism_data
# perl_modules
# python_modules
# project_dbs
# project_dbs_local
# remote_data
# software_fields
# supported_input_types
# supported_input_types_methods
# supported_input_types_viewers
# system_software
# type_fields
# utilities_software
# viewer_min
# viewer_prefs

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use Common::Config;
use Common::Messages;

use Registry::Option;

use base qw ( Common::Menu );

our ( %Auto_get_setters, %Auto_functions );

# >>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD ACCESSORS <<<<<<<<<<<<<<<<<<<<<<<<

# Simple getters and setters,

%Auto_get_setters = map { $_, 1 } qw (
                                      module datadir description citation
                                      inputdb param_key param_values
                                      );

# Dynamically created methods that get registry items. Keys are the 
# method names. Example usage:
#
# Single dataset:  $db = Registry::Get->dataset("uthscsa"); 
#
# All datasets: $dbs = Registry::Get->datasets;
# Selected datasets: $dbs = Registry::Get->datasets( ["uthscsa","bion"] );
#
# All dataset ids: $ids = Registry::Get->dataset_ids;
# 
# Same for features, formats, types, etc. When adding new methods,
# please keep singular and plural names (reads better, and the 
# Registry::Check::check_all routine depends on it).

%Auto_functions = (
    "sinstall" =>     [ "_get_item",          "Software::Registry::Options" ],
    "sinstalls" =>    [ "_get_items",         "Software::Registry::Options" ],
    "sinstall_ids" => [ "_get_item_ids",      "Software::Registry::Options" ],
    "software" =>     [ "_get_item",          "Software::Registry::Packages" ],
    "softwares" =>    [ "_get_items",         "Software::Registry::Packages" ],
    "software_ids" => [ "_get_item_ids",      "Software::Registry::Packages" ],
    "project" =>      [ "_get_file_item",     "Projects", ["datasets","datasets_other","hide_methods","dbnames"] ],
    "projects" =>     [ "_get_file_items",    "Projects" ],
    "project_ids" =>  [ "_get_file_item_ids", "Projects" ],
    "dataset" =>      [ "_get_item",          "Data::Registry::Datasets" ],
    "datasets" =>     [ "_get_items",         "Data::Registry::Datasets" ],
    "dataset_ids" =>  [ "_get_item_ids",      "Data::Registry::Datasets" ],
    "feature" =>      [ "_get_item",          "Data::Registry::Features" ],
    "features" =>     [ "_get_items",         "Data::Registry::Features" ],
    "feature_ids" =>  [ "_get_item_ids",      "Data::Registry::Features" ],
    "format" =>       [ "_get_item",          "Data::Registry::Formats" ],
    "formats" =>      [ "_get_items",         "Data::Registry::Formats" ],
    "format_ids" =>   [ "_get_item_ids",      "Data::Registry::Formats" ],
    "schema" =>       [ "_get_item",          "Data::Registry::Schemas" ],
    "schemas" =>      [ "_get_items",         "Data::Registry::Schemas" ],
    "schema_ids" =>   [ "_get_item_ids",      "Data::Registry::Schemas" ],
    "type" =>         [ "_get_item",          "Data::Registry::Types" ],
    "types" =>        [ "_get_items",         "Data::Registry::Types" ],
    "type_ids" =>     [ "_get_item_ids",      "Data::Registry::Types" ],
    "command" =>      [ "_get_item",          "Software::Registry::Commands" ],
    "commands" =>     [ "_get_items",         "Software::Registry::Commands" ],
    "command_ids" =>  [ "_get_item_ids",      "Software::Registry::Commands" ],
    "method" =>       [ "_get_item",          "Software::Registry::Methods" ],
    "methods" =>      [ "_get_items",         "Software::Registry::Methods" ],
    "method_ids" =>   [ "_get_item_ids",      "Software::Registry::Methods" ],
    "param" =>        [ "_get_item",          "Software::Registry::Params" ],
    "params" =>       [ "_get_items",         "Software::Registry::Params" ],
    "param_ids" =>    [ "_get_item_ids",      "Software::Registry::Params" ],
    "viewer" =>       [ "_get_item",          "Software::Registry::Viewers" ],
    "viewers" =>      [ "_get_items",         "Software::Registry::Viewers" ],
    "viewer_ids" =>   [ "_get_item_ids",      "Software::Registry::Viewers" ],
    );

sub AUTOLOAD
{
    # Niels Larsen, March 2007.

    # Dispatches calls to functions not explicitly defined in this module. If the
    # method is a key in the %Auto_get_setters, a simple get/set function is called.
    # Next, if key in %Auto_functions, slightly more complex retrievals are made:
    # calls are made to _get_items, _get_time or _get_item_ids.
    
    my ( $self,
         $value,
         $args,
         ) = @_;

    # Returns scalar or hash.

    our $AUTOLOAD;

    my ( $method, $module, $keys, $key, $routine, %args );
    
    $AUTOLOAD =~ /::(\w+)$/ and $method = $1;

    if ( $Auto_get_setters{ $method } )
    {
        if ( defined $value ) {
             return $self->{ $method } = $value;
         } else {
             return $self->{ $method };
         }
    }
    elsif ( $Auto_functions{ $method } )
    {
        ( $routine, $module, $keys ) = @{ $Auto_functions{ $method } };

        %args = (
            "method" => $method,
            "module" => $module,
            );

        if ( $keys ) {
            $args{"keys"} = $keys;
        }

        if ( $args )
        {
            foreach $key ( keys %{ $args } ) {
                $args{ $key } = $args->{ $key };
            }
        }

        return $self->$routine( $value, \%args );
    }
    elsif ( $method ne "DESTROY" )
    {
        $method = "SUPER::$method";
        
        no strict "refs";
        return eval { $self->$method( $value ) };
    }
    
    return;
}

sub new
{
    my ( $class,
         %args,
         ) = @_;

    my ( $self, $key );

    $self = {};
    
    bless $self, ( ref $class ) || $class;

    foreach $key ( keys %args )
    {
        if ( $Auto_get_setters{ $key } ) {
            $self->{ $key } = $args{ $key };
        } else {
            $self->$key( $args{ $key } );
        }
    }

    return $self;
}

sub _get_file_item
{
    # Niels Larsen, March 2008.

    # Reads a configuration file from the Registry, from the given 
    # subdirectory. 

    my ( $class,           # Package name
         $file,
         $args,
         $msgs,            # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a Common::Option object.

    my ( $method, $subdir, $tolist, $item, $msg, $dpath, $fpath, $key );

    $method = $args->{"method"};
    $subdir = $args->{"module"};
    $tolist = { map { $_, 1 } @{ $args->{"keys"} } };

    $dpath = $Common::Config::conf_dir ."/$subdir";

    if ( -d $dpath )
    {
        $fpath = "$dpath/$file";

        if ( -r $fpath )
        {
            require Config::General;

            $item = { new Config::General( $fpath )->getall };
            $item = $class->_objectify( $item, 1, $tolist );
            
            $item->name( $file );
        }
        else
        {
            $msg =  qq (Item not found in $subdir -> "$file"\n\n) 
                  . qq (To receive a list of possibilities, run\n)
                  . $class ."->". $method ."_ids()\n";
            
            if ( defined $msgs ) {
                push @{ $msgs }, [ "Error", $msg ];
            } else {
                &error( $msg, "REGISTRY ERROR" );
            }
        }
    }
    else {
        &error( qq ($subdir not readable -> "$dpath") );
    }

    return $item;
}

sub _get_file_items
{
    # Niels Larsen, April 2009.

    my ( $class,          # Package name
         $names,
         $args,
         $msgs,           # Message list
         ) = @_;

    # Returns a list of Common::Option objects.

    my ( $method, $module, @opts, $name, $menu, $type );

    $method = $args->{"method"};
    $module = $args->{"module"};

    if ( defined $names ) {
        $names = [ $names ] if not ref $names;
    } else {
        $names = $class->_get_file_item_ids();
    }

    $method =~ s/s$//;
    $type = lc $module;
    $menu = $class->new( "name" => $type ."_menu" );
    
    $menu->title( ucfirst $type ." menu" );

    foreach $name ( @{ $names } )
    {
        push @opts, $class->$method( $name );
    }

    $menu->options( \@opts );

    return $menu;
}

sub _get_file_item_ids
{
    # Niels Larsen, November 2006.

    # Lists all Registry configuration files in a given subdirectory
    # and returns a list of their names. 

    my ( $class, 
         ) = @_;

    # Returns a list of strings.
    
    my ( $dpath, @names );
    
    $dpath = $Common::Config::conf_proj_dir;

    if ( -d $dpath )
    {
        require Common::File;

        @names = map { $_->{"name"} } 
                 grep { $_->{"name"} =~ /^[a-z]+$/ }
                 &Common::File::list_all( $dpath );
    }
    else {
        &error( qq (No project files found in -> "$dpath") );
    }

    return wantarray ? @names : \@names;
}

sub _get_item
{
    # Niels Larsen, March 2007.

    # A helper function for the accessors defined by %Auto_functions.
    # It returns a single registry item given its unique name and a 
    # routine name. 

    my ( $class,
         $name,
         $args,     # Arguments hash
         $msgs,     # Outgoing messages 
         ) = @_;

    # Returns a Registry::Option object.

    my ( $method, $module, $item, $items, $msg, $sub_name );

    $method = $args->{"method"};
    $module = $args->{"module"};

    if ( ref $name ) {
        &error( qq (The given name should be a string) );
    }

    if ( defined $module )
    {
        no strict "refs";

        # Load module,

        eval "require $module";

        # Create list and filter below,

        $sub_name = $module ."::descriptions";
        $items = $sub_name->();
    }
    else {
        &error( qq (No $method given) );
    }

    if ( defined $name )
    {
        if ( not $item = (grep { $_->{"name"} eq $name } @{ $items })[0] )
        {
            $msg = qq (Item not found in $module -> "$name"\n\n) 
                 . qq (To receive a list of possibilities, run\n)
                 . $class ."->". $method ."_ids()\n";
            
            if ( defined $msgs ) {
                push @{ $msgs }, [ "Error", $msg ];
            } else {
                &error( $msg, "REGISTRY ERROR" );
            }
        }

        $item = $class->_objectify( $item, 1 );
    }
    else {
        &error( qq (No id given), "REGISTRY ERROR" );
    }

    return $item;
}

sub _get_items
{
    # Niels Larsen, November 2006.

    # This is purely a helper function for the other get_* functions.
    # It returns a list of registry items given their unique names and
    # a routine name. The routine name is used to invoke the right 
    # subroutine (different types of info is in different routines)

    my ( $class,          # Package name
         $items,          # List of items
         $args,           # Argument hash - OPTIONAL
         $msgs,           # Outgoing message list - OPTIONAL
         ) = @_;

    # Returns a list of Registry::Option objects.

    my ( $module, $method, $all_items, %lookup, @opts, $name, 
         $msg, $menu, $type, $item, $opt, $sub_name );

    no strict "refs";

    $method = $args->{"method"};
    $module = $args->{"module"};

    # Load module,

    eval "require $module";

    # Create list and then filter,

    $sub_name = $module ."::descriptions";
    $all_items = $sub_name->();

    $all_items = $class->_objectify( $all_items, 1 );

    %lookup = map { $_->name, $_ } @{ $all_items->options };

    if ( defined $items )
    {
        if ( ref $items eq "ARRAY" )
        {
            if ( @{ $items } ) 
            {
                $items = [ map { Registry::Option->new( "name" => $_ ) } @{ $items } ];
                $items = $class->new( "options" => $items );
            }
            else {
                &error( qq (Empty $method list given) );
            }
        };
    }
    else {
        $items = $all_items;
    }

    foreach $item ( @{ $items->options } )
    {
        if ( $opt = $lookup{ $item->name } )
        {
            $opt->selected( $item->selected );
            push @opts, $opt;
        }
        else
        {
            $name = $item->name;

            $msg = qq (Item not found in $module -> "$name"\n\n) 
                 . qq (To receive a list of possibilities, run\n)
                 ."   $class->$method"."_ids()\n";
            
            if ( defined $msgs ) {
                push @{ $msgs }, [ "Error", $msg ];
            } else {
                &error( $msg, "REGISTRY ERROR" );
            }
        }
    }

    $type = lc $module;
    $menu = $class->new( "name" => $type ."_menu" );

    $menu->title( ucfirst $type ." menu" );
    $menu->options( \@opts );

    return $menu;
}

sub _get_item_ids
{
    # Niels Larsen, November 2006.

    # This is purely a helper function for the other get_* functions.
    # It returns a list of registry item names given a routine name. 
    # The routine name is used to invoke the right subroutine 
    # (different types of info is in different routines)

    my ( $class,           # Package 
         undef,
         $args,
         ) = @_;

    # Returns a list of strings.
    
    my ( $module, $items, @names, $sub_name );

    $module = $args->{"module"};
    $items = $args->{"value"};

    # Load module,

    eval "require $module";

    if ( defined $items )
    {
        @names = map { $_->{"name"} } @{ $items };
    }
    else
    {
        no strict "refs";

        $sub_name = $module ."::descriptions";
        $items = $sub_name->();
        
        @names = map { $_->{"name"} } @{ $items };
    }

    return wantarray ? @names : \@names;
}

sub _get_software
{
    # Niels Larsen, September 2006.

    # Creates a menu of software packages that the system knows about.

    my ( $class,       
         $pkgs,      # Package or list of packages - OPTIONAL
         $args,      # Arguments hash - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $menu, $srcdir, $datatype, $filter, %pkgs, @opts, $file, $opt,
         $single );

    $datatype = $args->{"datatype"};
    $srcdir = $args->{"srcdir"};

    # Create menu of given packages or all if no packages given,

    if ( $pkgs ) 
    {
        if ( not ref $pkgs ) 
        {
            $pkgs = [ $pkgs ];
            $single = 1;
        }

        $menu = $class->softwares( $pkgs );
    }
    else {
        $menu = $class->softwares();
    }

    $menu->match_options( "expr" => 'datatype eq "'. $datatype .'"' );

    # Filter if an expression is given,

    if ( $filter = $args->{"filter"} )
    {
        @opts = grep { $_->name =~ /$filter/i } @{ $menu->options };
        $menu->options( [ @opts ] );
    }

    # Filter so only those that exist are included (different 
    # distributions are made),

    if ( $args->{"existing_only"} )
    {
        @opts = ();

        foreach $opt ( @{ $menu->options } )
        {
            $file = "$srcdir/". $opt->src_name .".tar.gz";

            if ( $opt->url or -e $file ) {
                push @opts, $opt;
            }
        }

        $menu->options( [ @opts ] );
    }

    if ( not @{ $menu->options } ) {
        &error( qq (No packages found) );
    }

    if ( $single ) {
        return $menu->options->[0];
    } else {
        return $menu;
    }
}

sub _objectify
{
    # Niels Larsen, March 2007.
    
    # Recursively converts a hash/array/... data structure to an 
    # equivalent menu/options/... data structure. 

    my ( $class,          
         $opts,           # List of options
         $id,             # Option id
         $keys,
         ) = @_;

    # Returns an option or a menu object.

    my ( $menu, @opts, $opt, $elem, $key, $value, $ref_count );

    if ( ref $opts eq "ARRAY" )
    {
        $id = 0;
        $ref_count = 0;

        foreach $elem ( @{ $opts } )
        {
            if ( ref $elem )
            {
                push @opts, $class->_objectify( $elem, ++ $id, $keys );
                $ref_count += 1;
            }
            else {
                push @opts, $elem;
            }
        }

        if ( $ref_count > 0 ) {
            $menu = $class->new( "options" => \@opts );
        } else {
            return \@opts;
        }

        return $menu;
    }
    elsif ( ref $opts eq "HASH" )
    {
        $opt = Registry::Option->new();
        
        foreach $key ( keys %{ $opts } )
        {
            $value = $opts->{ $key };

            if ( ref $value ) {
                $opt->$key( $class->_objectify( $value, 0, $keys ) );
            } elsif ( $keys->{ $key } ) {
                $opt->$key( [$value] );
            } else {
                $opt->$key( $value );
            }
        }

        $opt->id( $id );

        return $opt;
    }
    else {
        &error( qq (Bug: routine input is a scalar -> "$opts") );
    }

    return;
}

sub analysis_software
{
    # Niels Larsen, April 2009.

    # Creates a menu of analysis packages that the system knows about.

    my ( $class,       
         $pkgs,      # Package or list of packages - OPTIONAL
         $args,      # Arguments hash - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    if ( not defined $args ) {
        $args = {};
    }

    $menu = Registry::Get->_get_software(
        $pkgs,
        { 
            %{ $args },
            "datatype" => "soft_anal",
            "srcdir" => $Common::Config::ans_dir,
        });

    return $menu;
}

sub data_fields
{
    my ( $opt, %counts, $field, @fields );

    foreach $opt ( Registry::Get->datasets->options )
    {
        foreach $field ( keys %{ $opt } )
        {
            if ( not ref $opt->{ $field } ) {
                $counts{ $field } += 1;
            }
        }
    }

    @fields = sort keys %counts;
    @fields = grep { $_ !~ /^blast|css/ } @fields;

    return wantarray ? @fields : \@fields;
}

sub dataset_types
{
    # Niels Larsen, June 2009.

    # Returns the list of datatypes found in a given list of datasets.

    my ( $class,
         $datlist,
        ) = @_;

    my ( @types, @datobjs, $dat, $exp );

    if ( not ref $datlist ) {
        $datlist = [ $datlist ];
    }

    @datobjs = Registry::Get->objectify_datasets( $datlist );

    foreach $dat ( @datobjs )
    {
        push @types, $dat->datatype;

        if ( $exp = $dat->exports )
        {
            push @types, map { $_->datatype } @{ $exp->options };
        }
    }

    @types = &Common::Util::uniqify( \@types );

    return wantarray ? @types : \@types;
}

sub type_datasets
{
    # Niels Larsen, February 2010.

    # Returns a list of datasets for a given type.

    my ( $class,
         $type,
        ) = @_;

    my ( $menu );

    $menu = $class->datasets();
    $menu->match_options( "expr" => "datatype =~ /^$type/" );

    if ( $menu->options ) {
        return $menu;
    }

    return;
}

sub datatypes_to_formats
{
    # Niels Larsen, October 2008.

    # Creates a list of formats for every datatype in a given list. The formats 
    # are taken from a given list of methods.
    
    my ( $class,
         $dtypes,        # Data types list 
         $methods,       # Method list, names or objects - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( @methods, $method, $input, $map, $dtype, $ftype );
    
    if ( $methods ) {
        @methods = Registry::Get->objectify_methods( $methods );
    } else {
        @methods = Registry::Get->methods();
    }

    $map = {};

    foreach $method ( @methods )
    {
        foreach $input ( $method->inputs->options ) 
        {
            foreach $dtype ( @{ $dtypes } )
            {
                if ( $input->matches( "types" => [ $dtype ] ) )
                {
                    if ( $input->iformats ) {
                        push @{ $map->{ $dtype }->{"iformats"} }, @{ $input->iformats };
                    }
                    
                    push @{ $map->{ $dtype }->{"formats"} }, @{ $input->formats };
                }
            }
        }
    }
        
    foreach $dtype ( keys %{ $map } )
    {
        $map->{ $dtype }->{"formats"} = &Common::Util::uniqify( $map->{ $dtype }->{"formats"} );

        if ( $map->{ $dtype }->{"iformats"} ) {
            $map->{ $dtype }->{"iformats"} = &Common::Util::uniqify( $map->{ $dtype }->{"iformats"} );
        }
    }

    return wantarray ? %{ $map } : $map;
}
                
sub installs_data
{
    # Niels Larsen, March 2007.

    # Returns a menu of dataset install options. It is used only during 
    # installation.

    my ( $class,       # Package name
         ) = @_;

    # Returns a menu structure.

    my ( $menu, @opts, $opt, $projs, $proj );

    $menu = Registry::Get->new();

    $menu->name("data_installs_menu");
    $menu->title( "Data installs" );

    $projs = $class->projects->options;

    foreach $proj ( @{ $projs } )
    {
        push @opts, Registry::Option->new( "name" => $proj->name, 
                                           "title" => $proj->description->title );
    }

    $menu->options( \@opts );

    return $menu;
}

sub installs_software
{
    # Niels Larsen, March 2007.

    # Returns a menu of software install options. It is used only during 
    # installation.

    my ( $class,       # Package name
         ) = @_;

    # Returns a menu structure.

    my ( $menu, $opts );

    $menu = $class->sinstalls;

    $menu->name("software_installs_menu");
    $menu->title( "Software installs" );

    $menu->options( $opts );

    return $menu;
}

sub method_input_formats
{
    # Niels Larsen, October 2008.

    # Returns a list of all different formats used by a list of given 
    # methods.

    my ( $class,
         $methods,      # Method list
        ) = @_;

    # Returns a list.

    my ( @names, $method, $input );

    foreach $method ( Registry::Get->objectify_methods( $methods ) )
    {
        foreach $input ( @{ $method->inputs->options } )
        {
            push @names, @{ $input->formats };
        }
    }

    @names = &Common::Util::uniqify( \@names );

    return wantarray ? @names : \@names;
}

sub method_input_types
{
    # Niels Larsen, October 2008.

    # Returns a list of all different input types used by a list of given 
    # methods.

    my ( $class,
         $methods,      # Method list
        ) = @_;

    # Returns a list.

    my ( @names, $method, $input );

    foreach $method ( Registry::Get->objectify_methods( $methods ) )
    {
        foreach $input ( @{ $method->inputs->options } )
        {
            push @names, @{ $input->types };
        }
    }

    @names = &Common::Util::uniqify( \@names );

    return wantarray ? @names : \@names;
}

sub datatype_to_formats
{
    my ( $class,
         $methods,
        ) = @_;

    my ( @methods, $method, $input, $i2f, $type );

    @methods = Registry::Get->objectify_methods( $methods );

     foreach $method ( @methods )
     {
         foreach $input ( $method->inputs->options )
         {
             if ( $input->iformats )
             {
                 foreach $type ( @{ $input->types } )
                 {
                     push @{ $i2f->{ $type } }, @{ $input->formats };
                 }
             }
         }
     }

    # Uniqify,

    foreach $type ( keys %{ $i2f } )
    {
        @{ $i2f->{ $type } } = &Common::Util::uniqify( $i2f->{ $type } );
    }

    return wantarray ? %{ $i2f } : $i2f;
}

sub datatype_to_iformats
{
    my ( $class,
         $methods,
        ) = @_;

    my ( @methods, $method, $input, $i2f, $field, $type );

    @methods = Registry::Get->objectify_methods( $methods );

     foreach $method ( @methods )
     {
         foreach $input ( $method->inputs->options )
         {
             if ( $input->iformats ) {
                 $field = "iformats";
             } else {
                 $field = "formats";
             }

             foreach $type ( @{ $input->types } )
             {
                 push @{ $i2f->{ $type } }, @{ $input->$field };
             }
         }
     }

    # Uniqify,

    foreach $type ( keys %{ $i2f } )
    {
        @{ $i2f->{ $type } } = &Common::Util::uniqify( $i2f->{ $type } );
    }

    return wantarray ? %{ $i2f } : $i2f;
}

sub iformats_to_formats
{
    # Niels Larsen, June 2009.

    # Creates a hash where keys are import formats of a given method input, and 
    # the values are lists of formats. For example if the simrank and blast methods
    # were given as argument, the returned hash would be
    # 
    # { "fasta" => [ "simrank", "blastn" ] }
    #
    # where "simrank" and "blastn" are formats defined in the registry.
    
    my ( $class,
         $methods,      # Method list, names or objects 
         $types,        # Types list, names - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( @methods, $method, $input, $i2f, $map, $iformats, $iformat, $format );

    @methods = Registry::Get->objectify_methods( $methods );
    
#     foreach $method ( @methods )
#     {
#         foreach $input ( $method->inputs->options )
#         {
#             if ( $iformats = $input->iformats )
#             {
#                 foreach $iformat ( @{ $iformats } )
#                 {
#                     foreach $format ( @{ $input-formats } )
#                     {
#                         if ( $format ne $iformat ) {
#                             push @{ $i2f->{ $iformat } }, $format;
#                         }
#                     }
#                 }
#             }
#             else 
#             {
                
                

#             $iformats = $input->iformats || $input->formats || {};

#             if ( not $types or $input->matches( "types" => $types ) )
#             {
#                 foreach $iformat ( @{ $iformats } )
#                 {
#                     foreach $format ( @{ $input->formats } )
#                     {
#                         push @{ $map->{ $iformat } }, $format;
#                     }
#                 }
#             }
#         }
#     }

    # Uniqify,

    foreach $iformat ( keys %{ $map } )
    {
        if ( scalar @{ $map->{ $iformat } } > 1 ) {
            @{ $map->{ $iformat } } = &Common::Util::uniqify( $map->{ $iformat } );
        }
    }

    return wantarray ? %{ $map } : $map;
}

sub method_max
{
    # Niels Larsen, April 2008.

    # Attaches full parameter values from Software::Registry::Params, required
    # by user user interfaces. It includes menu names, tooltips etc. 

    my ( $class,      # Package name
         $method,     # Method name or structure
         ) = @_;

    # Returns a method structure.

    my ( $param_type, $params, %params_all, $opt, @names, %values, $params_full );

    if ( not ref $method ) {
        $method = Registry::Get->method( $method );
    }

    %params_all = map { $_->name, $_ } Registry::Get->params->options;

    foreach $param_type ( "pre_params", "params", "post_params" )
    {
        if ( exists $method->{ $param_type } )
        {
            $params = $method->$param_type;

            @names = map { $_->[0] } @{ $params->values->options };
            
            $params_full = $params_all{ $params->name }; # &Storable::dclone( $params_all{ $params->name } );
            $params_full->values->match_options( "name" => \@names );
            $params_full->values->sort_options_list( "name", \@names );

            %values = map { $_->[0], $_->[1] } @{ $params->values->options };

            foreach $opt ( $params_full->values->options )
            {
                $opt->value( $values{ $opt->name } );
            }

            $method->$param_type( &Storable::dclone( $params_full ) );
        }
    }

    return $method;
}

sub method_min 
{
    my ( $class,
         $method,
        ) = @_;

    my ( $key, $method_min );

    if ( not ref $method ) {
        $method = Registry::Get->method( $method );
    }
    
    foreach $key ( qw ( name title inputs outputs ) )
    {
        $method_min->{ $key } = $method->$key;
    }

    bless $method_min, ref $method;

    return $method_min;
}

sub objectify_datasets
{
    # Niels Larsen, September 2008.

    # Makes sure a given list of dataset names or objects are all 
    # converted to objects. Order is not preserved.

    my ( $class,          
         $datasets,            # List of dataset names or objects
        ) = @_;

    # Returns a list.

    my ( $dataset, @datasets, @names );

    $datasets = [ $datasets ] if not ref $datasets eq "ARRAY";

    foreach $dataset ( @{ $datasets } )
    {
        if ( not ref $dataset )
        {
            push @names, $dataset;
        } 
        else
        {
            if ( (ref $dataset) !~ /^Registry::/ )
            {
                bless $dataset, "Registry::Option";
            }

            push @datasets, $dataset;
        }
    }

    if ( @names ) {
        push @datasets, Registry::Get->datasets( \@names )->options;
    }

    return wantarray ? @datasets : \@datasets;
}

sub _objectify_methods
{
    # Niels Larsen, September 2008.

    # Makes sure a given list of method names or objects are all 
    # converted to objects. 

    my ( $class,          
         $list,            # List of method names or objects
         $type,            # "viewers" or "methods"
        ) = @_;

    # Returns a list.

    my ( $elem, @objs, @names );

    $list = [ $list ] if not ref $list eq "ARRAY";

    foreach $elem ( @{ $list } )
    {
        if ( not ref $elem )
        {
            push @names, $elem;
        } 
        else
        {
            if ( (ref $elem) !~ /^Registry::/ )
            {
                bless $elem, "Registry::Option";
            }

            push @objs, $elem;
        }
    }

    if ( @names ) {
        push @objs, Registry::Get->$type( \@names )->options;
    }

    return wantarray ? @objs : \@objs;
}

sub objectify_methods
{
    # Niels Larsen, September 2008.

    # Makes sure a given list of method names or objects are all 
    # converted to objects. 

    my ( $class,          
         $list,            # List of names or objects
        ) = @_;

    # Returns a list.

    my ( @objs );

    @objs = Registry::Get->_objectify_methods( $list, "methods" );
    
    return wantarray ? @objs : \@objs;
}

sub objectify_viewers
{
    # Niels Larsen, September 2008.

    # Makes sure a given list of viewer names or objects are all 
    # converted to objects. 

    my ( $class,          
         $list,            # List of names or objects
        ) = @_;

    # Returns a list.

    my ( @objs );

    @objs = Registry::Get->_objectify_methods( $list, "viewers" );
    
    return wantarray ? @objs : \@objs;
}

sub organism_data
{
    # Niels Larsen, October 2006.

    # Returns a menu of organism related data.

    my ( $class,       # Package name
         ) = @_;

    # Returns a menu structure.

    my ( $menu );

    $menu = $class->datasets();
    $menu->match_options( "expr" => 'datatype =~ /^orgs_/' );

    return $menu;
}

sub perl_modules
{
    # Niels Larsen, April 2009.

    # Creates a menu of non-standard perl modules that the system needs.

    my ( $class,       
         $pkgs,      # Package or list of packages - OPTIONAL
         $args,      # Arguments hash - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    if ( not defined $args ) {
        $args = {};
    }

    $menu = Registry::Get->_get_software(
        $pkgs,
        { 
            %{ $args },
            "datatype" => "soft_perl_module",
            "srcdir" => $Common::Config::pems_dir,
        });

    return $menu;
}

sub python_modules
{
    # Niels Larsen, November 2010.

    # Creates a menu of non-standard python modules that the system needs.

    my ( $class,       
         $pkgs,      # Package or list of packages - OPTIONAL
         $args,      # Arguments hash - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    if ( not defined $args ) {
        $args = {};
    }

    $menu = Registry::Get->_get_software(
        $pkgs,
        { 
            %{ $args },
            "datatype" => "soft_python_module",
            "srcdir" => $Common::Config::pems_dir,
        });

    return $menu;
}

sub project_dbs
{
    # Niels Larsen, April 2007.

    # Returns a menu of all datasets referred to by a project.

    my ( $class,      # Package name
         $name,       # Project name
         ) = @_;

    # Returns a menu structure.
     
    my ( $proj, $opt, @opts, $menu, @ids );

    $proj = $class->project( $name );

    if ( $proj->datasets )
    {
        if ( ref $proj->datasets ) {
            push @ids, @{ $proj->datasets };
        } else {
            push @ids, $proj->datasets;
        }

#         if ( ref $proj->datasets_other ) {
#             push @ids, @{ $proj->datasets_other };
#         } else {
#             push @ids, $proj->datasets_other;
#         }
    }
    else {
        &error( qq (No datasets found for project -> "$name") );
    }
    
    @ids = &Common::Util::uniqify( \@ids );

    @opts = $class->datasets( \@ids )->options;

    $menu = $class->new( "title" => "Project Data", "options" => \@opts );

#    $menu->match_options( "owner" => $name );

    return $menu;
}

sub project_dbs_local
{
    # Returns a menu of all local datasets referred to by a project.

    my ( $class,      # Package name
         $name,       # Project name
         ) = @_;

    # Returns a menu structure.
     
    my ( $menu );

    $menu = $class->project_dbs( $name );

    $menu->options( [ grep { $_->is_local_db } $menu->options ] );

    return $menu;
}

sub remote_data
{
    # Niels Larsen, January 2007.

    # A menu of datasets that are not installable locally. They are 
    # simply filtered from _all_data_packages by looking for no value
    # for the "datadir" key.

    my ( $class,        # Package name
         ) = @_;

    # Returns a menu structure.

    my ( $menu );

    $menu = $class->datasets();
    $menu->prune_expr( 'not $_->datadir' );

    return $menu;
}

sub seq_data
{
    # Niels Larsen, October 2006.

    # Returns a menu of datasets with the DNA datatype.

    my ( $class,        # Package name
         $names,        # Name ids - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $menu, %names, @opts );

    $menu = $class->datasets();
    $menu->match_options( "expr" => 'datatype =~ /_seq$/' );

    if ( $names )
    {
        %names = map { $_, 1 } @{ $names };
        @opts = grep { $names{ $_->name } } @{ $menu->options };
        $menu->options( \@opts );
    }

    return $menu;
}

sub software_fields
{
    my ( $opt, %counts, $field, @fields );

    foreach $opt ( Registry::Get->softwares->options )
    {
        foreach $field ( keys %{ $opt } )
        {
            $counts{ $field } += 1;
        }
    }

    @fields = sort keys %counts;
    @fields = grep { $_ !~ /^id|method$/ } @fields;

    return wantarray ? @fields : \@fields;
}

sub supported_input_types
{
    my ( $class,
         $list,
         ) = @_;

    my ( $item, $type, @types, $input );

    $list = [ qw ( methods viewers ) ] if not defined $list;

    foreach $type ( @{ $list } )
    {
        foreach $item ( Registry::Get->$type->options )
        {
            foreach $input ( $item->inputs->options )
            {
                push @types, @{ $input->types };
            }
        }
    }

    @types = sort &Common::Util::uniqify( \@types );

    return wantarray ? @types : \@types;
}    
 
sub supported_input_types_methods
{
    return Registry::Get->supported_input_types( ["methods"] );
}

sub supported_input_types_viewers
{
    return Registry::Get->supported_input_types( ["viewers"] );
}

sub system_software
{
    # Niels Larsen, April 2009.

    # Creates a menu of core packages that the system needs.

    my ( $class,       
         $pkgs,      # Package or list of packages - OPTIONAL
         $args,      # Arguments hash - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    if ( not defined $args ) {
        $args = {};
    }

    $menu = Registry::Get->_get_software(
        $pkgs,
        { 
            %{ $args },
            "datatype" => "soft_sys",
            "srcdir" => $Common::Config::pks_dir,
        });

    return $menu;
}

sub type_fields
{
    my ( $opt, %counts, $field, @fields );

    foreach $opt ( Registry::Get->types->options )
    {
        foreach $field ( keys %{ $opt } )
        {
            $counts{ $field } += 1;
        }
    }

    @fields = sort keys %counts;

    return wantarray ? @fields : \@fields;
}

sub utilities_software
{
    # Niels Larsen, April 2009.

    # Creates a menu of utility packages that the system needs.

    my ( $class,       
         $pkgs,      # Package or list of packages - OPTIONAL
         $args,      # Arguments hash - OPTIONAL
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    if ( not defined $args ) {
        $args = {};
    }

    $menu = Registry::Get->_get_software(
        $pkgs,
        { 
            %{ $args },
            "datatype" => "soft_util",
            "srcdir" => $Common::Config::uts_dir,
        });

    return $menu;
}

sub viewer_min 
{
    my ( $class,
         $method,
        ) = @_;

    my ( $key, $method_min );

    if ( not ref $method ) {
        $method = Registry::Get->viewer( $method );
    }
    
    foreach $key ( qw ( name title inputs ) )
    {
        $method_min->{ $key } = $method->$key;
    }

    bless $method_min, ref $method;

    return $method_min;
}

sub viewer_prefs
{
    my ( $class,
         $viewer,
        ) = @_;

    my ( $prefs );

    $prefs = Registry::Get->viewer( $viewer )->params->values->options;
    $prefs = { map { $_->[0], $_->[1] } @{ $prefs } };
    
    return $prefs;
}

1;

__END__

# sub viewer_full
# {
#     # Niels Larsen, May 2007.

#     # TODO: Not clear if viewers should be handled as methods. Meanwhile this.

#     my ( $class,
#          $name,
#          $tuples,
#          ) = @_;

#     my ( $viewer );
    
#     $viewer = $class->_method_max( $class->viewer( $name ), $tuples );

#     return $viewer;
# }

# sub supported_method_inputs
# {
#     my ( $opt, @types );

#     foreach $opt ( Registry::Get->methods->options )
#     {
#         push @types, @{ $opt->itypes };
#     }

#     @types = sort &Common::Util::uniqify( \@types );

#     return wantarray ? @types : \@types;
# }
# sub project_schema_names
# {
#     # Returns a menu of all schema names declared in a project.

#     my ( $class,      # Package name
#          $name,       # Project name
#          ) = @_;

#     # Returns a menu structure.
     
#     my ( $db, %names, @names );

#     foreach $db ( $class->project_dbs_local( $name )->options )
#     {
#         $names{ $class->type( $db->datatype )->schema } ++;
#     }

#     @names = sort keys %names;

#     return wantarray ? @names : \@names;
# }

# sub dna_data
# {
#     # Niels Larsen, October 2006.

#     # Returns a menu of datasets with the DNA datatype.

#     my ( $class,        # Package name
#          ) = @_;

#     # Returns a list.

#     my ( $menu );

#     $menu = $class->datasets();
#     $menu->match_options( "expr" => 'datatype =~ /^dna_/' );

#     return $menu;
# }

# sub protein_data
# {
#     # Niels Larsen, October 2006.

#     # Creates a menu of protein related data sets, their internet locations,
#     # download and install directories, etc. 

#     my ( $class,       # Package name
#          ) = @_;

#     # Returns a menu structure.

#     my ( $menu );

#     $menu = $class->datasets();
#     $menu->match_options( "expr" => 'datatype =~ /^prot_/' );

#     return $menu;
# }

# sub rna_data
# {
#     # Niels Larsen, October 2006.

#     # Creates a menu of RNA related data sets, their internet locations,
#     # download and install directories, etc. 

#     my ( $class,       # Package name
#          ) = @_;

#     # Returns a menu structure.

#     my ( $menu );

#     $menu = $class->datasets();
#     $menu->match_options( "expr" => 'datatype =~ /^rna_/' );

#     return $menu;
# }
