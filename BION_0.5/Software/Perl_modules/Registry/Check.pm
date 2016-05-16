package Registry::Check;            # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Routines that check the validity of the registry information, such
# as referring to data or items that do not exist.

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 check_all
                 check_datasets
                 check_features
                 check_formats
                 check_methods
                 check_modules
                 check_parameters
                 check_projects
                 check_schemas
                 check_types
                 check_viewers
                 get_accessors
                 get_filters
                 module_exists
                 routine_exists
                 software_locations
);

use Common::Config;
use Common::Messages;

use Registry::Get;
use Registry::Schema;
use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_all
{
    # Niels Larsen, May 2008.

    # Calls registry methods and accessors to ensure they work, that 
    # ids are valid and consistent, etc. Returns a list of messages
    # if there are problems, otherwise nothing.

    my ( $class,
        ) = @_;

    # Returns a list or nothing. 

    my ( @msgs, @allmsgs, @tuples, $tuple, $method, $msg );

    @tuples = (
        [ "Checking AUTOLOAD accessors", "get_accessors" ],
        [ "Checking software locations", "software_locations" ],
        [ "Checking method accessors", "get_filters" ],
        [ "Checking formats", "check_formats" ],
        [ "Checking schemas", "check_schemas" ],
        [ "Checking types", "check_types" ],
        [ "Checking features", "check_features" ],
        [ "Checking datasets", "check_datasets" ],
        [ "Checking projects", "check_projects" ],
        [ "Checking parameters", "check_parameters" ],
        [ "Checking schemas", "check_schemas" ],
        [ "Checking methods", "check_methods" ],
        [ "Checking viewers", "check_viewers" ],
        );

    foreach $tuple ( @tuples )
    {
        ( $msg, $method ) = @{ $tuple };

        &echo( "   $msg ... " );

        @msgs = Registry::Check->$method();

        if ( @msgs )
        {
            push @allmsgs, @msgs;

            if ( grep { $_->[0] =~ /error/i } @msgs ) {
                &echo_red( "error\n" ); 
            } elsif ( grep { $_->[0] =~ /warning/i } @msgs ) {
                &echo_yellow( "warning\n" ); 
            }
        }
        else {
            &echo_green( "ok\n" ); 
        }
    }

    if ( @allmsgs ) {
        return wantarray ? @allmsgs : \@allmsgs;
    } else {
        return;
    }
}

sub check_datasets
{
    my ( $class,
        ) = @_;

    my ( %type_ids, %fmt_ids, %proj_ids, $obj, $name, $list, $str, @msgs, $export );

    %type_ids = map { $_, 1 } Registry::Get->type_ids();
    %fmt_ids = map { $_, 1 } Registry::Get->format_ids();
    %proj_ids = map { $_, 1 } Registry::Get->project_ids();

    foreach $obj ( Registry::Get->datasets->options )
    {
        $name = $obj->name;
        
        # Data directory,

        if ( $str = $obj->datapath and not -d "$Common::Config::dat_dir/$str" ) {
            push @msgs, [ "Warning", qq (Dataset $name: missing install directory -> "$str") ];
        }

        # Type,

        if ( $str = $obj->datatype )
        {
            if ( not exists $type_ids{ $str } ) {
                push @msgs, ["Error", qq (Dataset $name: datatype "$str" does not exist.) ];
            }
        }

        # Format,

        if ( $str = $obj->format )
        {
            if ( not exists $fmt_ids{ $str } ) {
                push @msgs, ["Error", qq (Dataset $name: format "$str" does not exist.) ];
            }
        }

        # Owner,

        if ( $str = $obj->owner )
        {
            if ( not exists $proj_ids{ $str } ) {
                push @msgs, ["Error", qq (Dataset $name: owner project "$str" does not exist.) ];
            }
        }

        # Exports,

        if ( $obj->exports )
        {
            foreach $export ( @{ $obj->exports->options } )
            {
                # Datatype,

                if ( $str = $export->datatype ) 
                {
                    if ( not exists $type_ids{ $str } ) {
                        push @msgs, ["Error", qq (Dataset $name (export): datatype "$str" does not exist.) ];
                    }
                }
                else {
                    push @msgs, ["Error", qq (Dataset $name (export): datatype missing.) ];
                }

                # Format,

                if ( $str = $export->format ) 
                {
                    if ( $str = $export->format and not exists $fmt_ids{ $str } ) {
                        push @msgs, ["Error", qq (Dataset $name (export): format "$str" does not exist.) ];
                    }
                }
                else {
                    push @msgs, ["Error", qq (Dataset $name (export): format missing.) ];
                }
            }
        }
    }

#         @list = Registry::Match->compatible_datasets( $datasets, $method );

#         if ( not @list ) {
#             push @msgs, [ "Warning", qq (No dataset compatible with the "). $method->name .qq (" method.) ];
#         }

#         @list = Registry::Match->matching_datasets( $datasets, $method );

# #        if ( not @list ) {
# #            push @msgs, [ "Warning", qq (No dataset completely satisfies the "). $method->name .qq (" method.) ];
# #        }

#     }

    return @msgs;
}

sub check_features
{
    my ( $class,
        ) = @_;

    my ( %type_ids, %viewer_ids, $obj, $obj2, $name, @msgs, $str, $list );

    %type_ids = map { $_, 1 } Registry::Get->type_ids();
    %viewer_ids = map { $_, 1 } Registry::Get->viewer_ids();

    foreach $obj ( Registry::Get->features->options ) 
    {
        $name = $obj->name;

        # Types,

        if ( $list = $obj->dbtypes )
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $type_ids{ $str } ) {
                    push @msgs, ["Error", qq (Feature $name: datatype "$str" does not exist.) ];
                }
            }
        }

        # Viewers,

        if ( $list = $obj->viewers )
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $viewer_ids{ $str } ) {
                    push @msgs, ["Error", qq (Feature $name: viewer "$str" does not exist.) ];
                }
            }
        }

#         if ( $obj2 = $obj->imports )
#         {
#             if ( $str = $obj2->routine and 
#                 not Registry::Check->routine_exists( { "routine" => $str, "fatal" => 0 } ) ) {
#                 push @msgs, ["Error", qq (Feature $name: routine "$str" does not exist.) ];
#             }
#         }
    }

    return @msgs;
}

sub check_formats
{
    my ( $class,
        ) = @_;

    my ( %type_ids, $obj, $name, @msgs, $str, $list );

    %type_ids = map { $_, 1 } Registry::Get->type_ids();

    foreach $obj ( Registry::Get->formats->options ) 
    {
        $name = $obj->name;

        # Types,

        if ( $list = $obj->datatypes )
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $type_ids{ $str } ) {
                    push @msgs, ["Error", qq (Format $name: datatype "$str" does not exist.) ];
                }
            }
        }
    }

    return @msgs;
}

sub check_methods
{
    my ( $class,
        ) = @_;

    my ( %fmt_ids, %type_ids, %param_ids, $method, $name, $field,
         $id, $params, $param, $key, $value, %tuples, $tuple, %opts, $tuples,
         $param_name, $type, $format, $slot, @msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Checks every field in the methods that refer to something else,
    # including the parameters,

    %fmt_ids = map { $_, 1 } Registry::Get->format_ids;
    %type_ids = map { $_, 1 } Registry::Get->type_ids;
    %param_ids = map { $_->name, 1 } Registry::Get->params->options;

    foreach $method ( Registry::Get->methods->options )
    {
        $name = $method->name;

        # Input and output types and formats,

        foreach $field ( qw ( inputs outputs ) )
        {
            foreach $slot ( $method->$field->options )
            {
                foreach $type ( @{ $slot->types } ) 
                {
                    if ( not exists $type_ids{ $type } ) {
                        push @msgs, [ "Error", qq (Method $name: $field type "$type" does not exist.) ];
                    }
                }

                foreach $format ( @{ $slot->formats } )
                {
                    if ( not $fmt_ids{ $format } ) {
                        push @msgs, [ "Error", qq (Method $name: $field format "$format" does not exist.) ];
                    }
                }
            }
        }

        # Parameters. Check that all fields are defined and that the option
        # keys are defined in Params.pm,

        $params = $method->params;
        next if not defined $params;

        foreach $key ( keys %{ $params } )
        {
            $value = $params->$key;            # just test fields 
        }

        $param_name = $params->name;

        if ( $params->values )
        {
            $tuples = $params->values->options;
            
            if ( $param_ids{ $param_name } )
            {
                %opts = map { $_->name, 1 } Registry::Get->param( $param_name )->values->options;
                
                foreach $tuple ( @{ $tuples } )
                {
                    if ( not exists $opts{ $tuple->[0] } ) {
                        push @msgs, [ "Error", qq (Method $name: parameter field "$tuple->[0]" in $param_name does not exist.) ];
                    }
                }
            }
        }

        # Check cross-mapping of method and parameters,

#        $value = Registry::Get->method_max( $method->name );
    }

    return @msgs;
}

sub check_modules
{
    # Niels Larsen, January 2010.

    # Loads all modules starting at a given directory to check for compile
    # errors. 

    my ( $class,
         $dir,   # Directory - OPTIONAL, default base perl module directory
         $silent,
        ) = @_;

    my ( @mods, $mod, @bad_mods );

    require Common::File;   

    @mods = &Common::File::list_modules( $dir );

    @mods = map { $_ =~ s|^$Common::Config::plm_dir/||; $_ } @mods;
    @mods = map { $_ =~ s|/|::|g; $_ } @mods;
    @mods = map { $_ =~ s|\.pm$||; $_ } @mods;

    @mods = grep { $_ !~ /Not_working/i } @mods;

    require Common::Config;
    require Common::Messages;

    foreach $mod ( @mods )
    {
        &echo( "Loading $mod ... " ) unless $silent;

        {
            local $SIG{__DIE__} = undef;
            eval "require $mod";
        }

        if ( $@ ) {
            &echo( "ERROR: $@\n" ) unless $silent;
            push @bad_mods, $mod;
        } else {
            &echo_green( "ok\n" ) unless $silent;
        }
    }

    if ( @bad_mods ) {
        return wantarray ? @bad_mods : \@bad_mods;
    }

    return;
}

sub check_parameters
{
    my ( $class,
         $msgs,
        ) = @_;

    my ( $module, %datatypes, %types, $param, $param_name, $key, $opts, 
         $opt, $opt_name, $key2, $value, @msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>> METHOD PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<

    # This tries all parameter accessors and checks the values of 
    # type and datatype fields,

    %datatypes = map { $_, 1 } qw ( integer real boolean string );
    %types = map { $_, 1 } qw ( pre_analysis analysis post_analysis );

    foreach $param ( Registry::Get->params->options )
    {
        $param_name = $param->name;

        foreach $key ( keys %{ $param } )
        {
            $opts = $param->$key;

            if ( $key eq "values" )
            {
                foreach $opt ( $opts->options )
                {
                    $opt_name = $opt->name;

                    foreach $key2 ( keys %{ $opt } )
                    {
                        $value = $opt->{ $key2 };

                        if ( $key2 eq "type" and not $types{ $value } ) {
                            push @msgs, [ "Error", qq (Wrong looking type for "($param_name) $opt_name" -> "$value") ];
                        }

                        if ( $key2 eq "datatype" and not $datatypes{ $value } ) {
                            push @msgs, [ "Error", qq (Wrong looking datatype for "($param_name) $opt_name" -> "$value") ];
                        }
                    }
                }
            }
        }
    }

    return @msgs;
}

sub check_projects
{
    my ( $class,
        ) = @_;

    my ( %data_ids, %method_ids, %viewer_ids, $obj, $opt, $menu, $name, @msgs, $str, $list, @opts );

    %data_ids = map { $_, 1 } Registry::Get->dataset_ids();
    %method_ids = map { $_, 1 } Registry::Get->method_ids();
    %viewer_ids = map { $_, 1 } Registry::Get->viewer_ids();
    
    foreach $obj ( Registry::Get->projects->options ) 
    {
        $name = $obj->name;

        # Datasets,

        if ( $list = $obj->datasets )
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $data_ids{ $str } ) {
                    push @msgs, ["Error", qq (Project $name: dataset "$str" does not exist.) ];
                }
            }
        }
        
        if ( $list = $obj->datasets_other )
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $data_ids{ $str } ) {
                    push @msgs, ["Error", qq (Project $name: (other) dataset "$str" does not exist.) ];
                }
            }
        }

        if ( $menu = $obj->navigation ) 
        {
            if ( (ref $menu) =~ /::Option$/ ) {
                @opts = $menu;
            } else {
                @opts = @{ $menu->options };
            }

            foreach $opt ( @opts )
            {
                if ( $list = $opt->dbnames )
                {
                    foreach $str ( @{ $list } )
                    {
                        if ( not exists $data_ids{ $str } ) {
                            push @msgs, ["Error", qq (Project $name: (navigation) dataset "$str" does not exist.) ];
                        }
                    }
                }
            }
        }                    
                
        # Viewers,

        if ( $obj->defaults and $str = $obj->defaults->def_viewer )
        {
            if ( not $viewer_ids{ $str } ) {
                push @msgs, ["Error", qq (Project $name: viewer "$str" does not exist.) ];
            }
        }

        # Methods,

        if ( $list = $obj->hide_methods )
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $method_ids{ $str } ) {
                    push @msgs, ["Error", qq (Project $name: (hide) method "$str" does not exist.) ];
                }
            }
        }
    }

    return @msgs;
}

sub check_schemas
{
    my ( $class,
        ) = @_;

    my ( %type_ids, $obj, $name, @msgs, $str, $list, $table );

    %type_ids = map { $_, 1 } Registry::Get->type_ids();

    foreach $obj ( Registry::Get->schemas->options ) 
    {
        $name = $obj->name;

        # Types,

        if ( $list = $obj->datatypes )
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $type_ids{ $str } ) {
                    push @msgs, ["Error", qq (Schema $name: datatype "$str" does not exist.) ];
                }
            }
        }

        # Columns,

        foreach $table ( @{ $obj->tables->options } )
        {
            $str = $table->name;

            if ( not $table->columns ) {
                push @msgs, [ "Error", qq (Schema table $name,$str: no columns.) ];
            }
        }
    }

    return @msgs;
}

sub check_types
{
    my ( $class,
        ) = @_;

    my ( $types, %scm_ids, %fmt_ids, %ft_ids, $type, $name, @msgs, $str, $list, $count );

    %scm_ids = map { $_, 1 } Registry::Get->schema_ids();
    %fmt_ids = map { $_, 1 } Registry::Get->format_ids();
    %ft_ids = map { $_, 1 } Registry::Get->feature_ids();

    foreach $type ( Registry::Get->types->options ) 
    {
        $name = $type->name;

        # Schema,

        if ( $str = $type->schema and not exists $scm_ids{ $str } )
        {
            push @msgs, ["Error", qq (Type $name: schema name "$str" does not exist.) ];
        }

        # Module path,

        if ( $str = $type->module ) 
        {
            if ( not -d "$Common::Config::plm_dir/$str" ) {
                push @msgs, ["Error", qq (Type $name: module directory "$str" not found.) ];
            }
        }

        # Format,

        if ( $list = $type->formats ) 
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $fmt_ids{ $str } ) {
                    push @msgs, ["Error", qq (Type $name: format name "$str" does not exist.) ];
                }
            }
        }

        # Features,

        if ( $list = $type->features ) 
        {
            foreach $str ( @{ $list } )
            {
                if ( not exists $ft_ids{ $str } ) {
                    push @msgs, ["Error", qq (Type $name: feature name "$str" does not exist.) ];
                }
            }
        }
    }

    return @msgs;
}

sub check_viewers
{
    my ( $class,
        ) = @_;

    my ( %fmt_ids, %type_ids, %param_ids, $method, $name, $field,
         $id, $params, $param, $key, $value, %tuples, $tuple, %opts, $tuples,
         $param_name, $type, $format, $slot, @msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Checks every field in the methods that refer to something else,
    # including the parameters,

    %fmt_ids = map { $_, 1 } Registry::Get->format_ids;
    %type_ids = map { $_, 1 } Registry::Get->type_ids;
    %param_ids = map { $_->name, 1 } Registry::Get->params->options;

    foreach $method ( Registry::Get->viewers->options )
    {
        $name = $method->name;

        # Input types and formats,

        foreach $slot ( $method->inputs->options )
        {
            foreach $type ( @{ $slot->types } ) 
            {
                if ( not exists $type_ids{ $type } ) {
                    push @msgs, [ "Error", qq (Method $name: input type "$type" does not exist.) ];
                }
            }

            foreach $format ( @{ $slot->formats } )
            {
                if ( not $fmt_ids{ $format } ) {
                    push @msgs, [ "Error", qq (Method $name: input format "$format" does not exist.) ];
                }
            }
        }

        # Parameters. Check that all fields are defined and that the option
        # keys are defined in Params.pm,

        $params = $method->params;
        next if not defined $params;

        foreach $key ( keys %{ $params } )
        {
            $value = $params->$key;            # just test fields 
        }

        $param_name = $params->name;

        if ( $params->values )
        {
            $tuples = $params->values->options;
            
            if ( $param_ids{ $param_name } )
            {
                %opts = map { $_->name, 1 } Registry::Get->param( $param_name )->values->options;
                
                foreach $tuple ( @{ $tuples } )
                {
                    if ( not exists $opts{ $tuple->[0] } ) {
                        push @msgs, [ "Error", qq (Method $name: parameter field "$tuple->[0]" in $param_name does not exist.) ];
                    }
                }
            }
        }
    }

    return @msgs;
}

# sub method_filters
# {
#     my ( $class,
#         ) = @_;

#     my ( $dataset, $methods, @list, @msgs );

#     &echo( qq (   Testing method filters ... ) );

#     $methods = Registry::Get->methods()->options;

#     foreach $dataset ( Registry::Get->datasets->options )
#     {
#         @list = Registry::Match->compatible_methods( $methods, $dataset );

#         if ( not @list ) {
#             push @msgs, [ "Warning", qq (No method compatible with dataset -> "). $dataset->name .qq (") ];
#         }
        
#         @list = Registry::Match->matching_methods( $methods, $dataset );

# #        if ( not @list ) {
# #            push @msgs, [ "Warning", qq (No method completely satisfied by -> "). $dataset->name .qq (") ];
# #        }
#     }

#     &echo_green( "ok\n" ); 

#     if ( @msgs ) {
#         return wantarray ? @msgs : \@msgs;
#     } else {
#         return;
#     }
# }

sub get_accessors
{
    # Niels Larsen, October 2008.

    # Checks that all registry objects can be fetched by the AUTOLOAD routines 
    # defined in Registry::Get. All errors are fatal. Other routines check that 
    # these objects have the right fields and that they properly refer to each
    # other. 

    my ( $class,
        ) = @_;

    my ( $key, $value, $method, $ids, $menu, $count, @msgs );

    foreach $key ( keys %Registry::Get::Auto_functions )
    {
        next if $key =~ /_ids$/;
        next if $key =~ /s$/;

        $value = $Registry::Get::Auto_functions{ $key };

        no strict "refs";

        $method = $key ."_ids";
        $ids = Registry::Get->$method();

        $method = $key ."s";
        $menu = Registry::Get->$method( $ids );
    }

    return @msgs;
}

sub get_filters
{
    my ( $class,
        ) = @_;

    my ( $module, $method, $menu, @msgs );

    # A set of declared methods that do filtering on the above and that 
    # take no arguments,

    $module = "Registry::Get";

    foreach $method ( qw ( analysis_software installs_data 
                           installs_software organism_data perl_modules
                           remote_data system_software utilities_software ) )
    {
        $menu = $module->$method();

        if ( $menu->options_count == 0 ) {
            push @msgs, [ "Error", qq (Empty menu -> "$method") ];
        }
    }

    return @msgs;
}

sub software_locations
{
    # Niels Larsen, May 2008.

    # Check that all software have correct datatypes and exist under 
    # the registered names and paths. Returns a list of messages if 
    # problems, otherwise nothing.

    my ( $class,
        ) = @_;

    # Returns a list or nothing.

    my ( %paths, $menu, $opt, $datatype, $dir, $src_name, @msgs );
    
    %paths = (
              "soft_sys" => $Common::Config::pks_dir,
              "soft_perl_module" => $Common::Config::pems_dir,
              "soft_util" => $Common::Config::uts_dir,
              "soft_anal" => $Common::Config::ans_dir,
              );

    $menu = Registry::Get->softwares;

    foreach $opt ( $menu->options )
    {
        $datatype = $opt->datatype;

        next if $opt->src_name =~ /blast/i;

        if ( $dir = $paths{ $datatype } )
        {
            $src_name = $opt->src_name;

            if ( not -d "$dir/$src_name" and 
                 not -e "$dir/$src_name.tar.gz" and
                 not -e "$dir/$src_name.tgz" ) 
            {
                push @msgs, [ "Error", qq (Source package does not exist -> "$dir/$src_name") ];
            }
        }
        else {
            push @msgs, [ "Error", qq (Wrong looking data type -> "$datatype") ];
        }
    }

    return @msgs;
}

sub module_exists
{
    # Niels Larsen, June 2009.

    # Checks that a given module exists.

    my ( $class,
         $module,
        ) = @_;

    if ( eval "$module" ) {
        return 1;
    }

    return;
}
    
sub routine_exists
{
    # Niels Larsen, April 2008.

    # Checks that a given routine name exists in the given named module.
    # If the second argument is given, errors are returned otherwise a 
    # crash will happen. 

    my ( $class,
         $args,        # Argument hash
         $msgs,        # Outgoing messages
        ) = @_;

    # Returns nothing. 

    my ( $module, $routine, $routine_path, $msg, $found, $fatal );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( routine ) ], 
            "S:0" => "fatal",
        });

    if ( $args->routine =~ /^(.+)::(.+)+$/ )
    {
        $module = $1;
        $routine = $2; 
    }
    else {
        &error( "Wrong looking routine path -> \"". $args->routine ."\"" );
    }

    $fatal = defined $args->fatal ? $args->fatal : 1;
    
    $routine_path = "\$". $module . qq (::{"$routine"});

    local $SIG{__DIE__} = undef;

    if ( eval "require $module" )
    {
        if ( eval $routine_path )
        {
            $found = 1;
        }
        else
        {
            $routine_path = $module."::".$routine;
            $msg = qq (Missing routine: "$routine_path");
            
            if ( defined $msgs ) {
                push @{ $msgs }, [ "ERROR", $msg ];
            } elsif ( $fatal ) {
                &error( qq (Missing routine -> "$routine_path") );
            }
            
            $found = 0;
        }
    }
    else {
        $found = 0;
    }
    
    return $found;
}

1;

__END__
