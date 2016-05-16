package Registry::List;            # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions that list and format registry content for reading. For each
# of the list_* functions there is a corresponding script that merely 
# invokes. 
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Tables;
use Common::Admin;

use Registry::Args;
use Registry::Get;
use Registry::Register;

# create_and_print_table
# create_table_from_menu
# list_args
# list_commands
# list_datasets
# list_features
# list_methods
# list_modperl_modules
# list_projects
# list_software
# list_types
# show_item

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_and_print_table
{
    my ( $class,
         $args,
        ) = @_;

    my ( $routine, @table, $msgs, $filter, $list_args );

    $args = &Registry::Args::check( 
        $args,
        {
            "S:1" => [ qw ( routine def_fields ) ],
            "S:0" => [ qw ( def_types def_sort ) ],
        });

    $routine = $args->routine;

    $args = &Common::Config::get_commandline(
        {
            "fields:s" => $args->def_fields,
            "types:s" => $args->def_types,
            "sort:s" => $args->def_sort,
            "installed!" => 0,
            "uninstalled!" => 0,
            "header!" => 1,
            "colsep:s" => "   ",
            "indent:s" => 2,
        });

    if ( $args->installed ) {
        $filter = "installed";
    } elsif ( $args->uninstalled ) {
        $filter = "uninstalled";
    } else {
        $filter = "";
    }

    {
        no strict "refs";

        $list_args = &Registry::Args::check(
            {
                "types" => [ split /\s*,\s*/, $args->types ],
                "fields" => $args->fields,
                "sort" => $args->sort,
                "filter" => $filter,
            },{
                "AR:0" => [ qw ( types ) ],
                "S:1" => [ qw ( fields sort filter ) ], 
            });

        @table = Registry::List->$routine( $list_args, $msgs );
    }
    
    if ( $msgs )
    {
        &echo_messages( $msgs );
        exit;
    }

    print "\n";

    Common::Tables->render_list(
        \@table,
        {
            "fields" => $args->fields,
            "header" => $args->header,
            "colsep" => $args->colsep,
            "indent" => $args->indent,
        });

    print "\n\n";

    return;
}

sub create_table_from_menu
{
    my ( $class,
         $menu,
         $args,
        ) = @_;

    my ( $opt, @row, $field, @fields, $val, @table );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( fields ) ],
        "S:0" => [ qw ( sort filter ) ],
        "AR:0" => [ qw ( types ) ],
    });

    @fields = split /\s*,\s*/, $args->fields;

    # Optional sort,

    if ( defined $args->sort )
    {
        $field = $args->sort;

        if ( not grep /^$field$/, @fields ) {
            $field = $fields[0];
        }
        
        $menu->sort_options( $field );
    }

    # Create table,

    foreach $opt ( $menu->options )
    {
        @row = ();

        foreach $field ( @fields )
        {
            if ( $field =~ /^([A-Za-z]+)\->([A-Za-z]+)$/ ) {
                $val = $opt->$1->$2 || "";
            } else {
                $val = $opt->$field || "";
            }

            if ( ref $val ) {
                push @row, join ", ", @{ $val };
            } else {
                push @row, $val;
            }
        }

        push @table, [ @row ];
    }

    return wantarray ? @table : \@table;
}

sub list_args
{
    # Niels Larsen, April 2008.

    # Prints or returns a table of argument requirements. 

    my ( $class,
         $reqs,
         $types,
        ) = @_;

    # Returns nothing.

    my ( %types, %conds, @table, $key, $type, $cond, $list, $elem );

    %types = map { $_->[0], $_->[2] } @{ $types };

    %conds = (
        0 => "optional",
        1 => "required",
        2 => "required with value",
        );

    foreach $key ( keys %{ $reqs } )
    {
        ( $type, $cond ) = split ":", $key;

        $list = $reqs->{ $key };
        $list = [ $list ] if not ref $list;

        foreach $elem ( @{ $list } )
        {
            push @table, [ $key, $elem, $types{ $type }, $conds{ $cond } ];
        }
    }

    @table = sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @table;

    print "\n";

    Common::Tables->render_list(
        \@table,
        {
            "fields" => "Code,Key,Type,Condition",
            "header" => 1,
            "colsep" => "   ",
            "indent" => 2,
        });

    print "\n\n";

    return;
}

sub list_commands
{
    # Niels Larsen, May 2009.

    # Lists commands. 

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, $names, @fields, $opt, @row, @table, $field );

    $args = &Registry::Args::check(
        $args,
        {
            "AR:0" => [ qw ( types ) ],
            "S:1" => [ qw ( fields sort ) ],
        });

    # Get all types, 

    $menu = Registry::Get->commands;

    # Filter,

    $menu->match_options( "datatype" => $args->types );

    # Create table,

    @table = Registry::List->create_table_from_menu( $menu, $args );

    return wantarray ? @table : \@table;
}

sub list_datasets
{
    # Niels Larsen, April 2008.

    # Lists datasets given by a list of field keys. If "installed" and
    # "uninstalled" are given as filter keys, the returned table will 
    # include only installed/uninstalled datasets. The output is sorted
    # on the given optional field.

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, $names, @table );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( fields sort filter ) ],
        });
    
    # Get all datasets, 

    $menu = Registry::Get->datasets;

    # Filter by either installed or uninstalled data,

    if ( $args->filter eq "installed" )
    {
        $names = Registry::Register->registered_datasets;
    } 
    elsif ( $args->filter eq "uninstalled" )
    {
        $names = Registry::Register->unregistered_datasets;
    }

    if ( $names )
    {
        $menu->match_options( "name" => $names );
    }

    # Create table,

    @table = Registry::List->create_table_from_menu( $menu, $args );

    return wantarray ? @table : \@table;
}

sub list_features
{
    # Niels Larsen, April 2008.

    # Lists features given by a list of field keys. The output is sorted
    # on the given optional field.

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, @table );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( fields sort ) ],
        });
    
    # Get all types, 

    $menu = Registry::Get->features;

    # Create table,

    @table = Registry::List->create_table_from_menu( $menu, $args );

    return wantarray ? @table : \@table;
}

sub list_methods
{
    # Niels Larsen, April 2008.

    # Lists projects. The output is sorted on the given optional field.

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, $names, @fields, $opt, @row, @table, $field, $val );

    # Get all methods,

    $menu = Registry::Get->methods;

    @table = Registry::List->create_table_from_menu( $menu, $args );

    return wantarray ? @table : \@table;
}

sub list_modperl_modules
{
    my ( $class,
        ) = @_;

    # Niels Larsen, August 2008.

    # Lists modules that should be included in the mod_perl section 
    # of the Apache configuration. We skip those known not to work,
    # and all download and import related modules. 

    # Returns a list. 

    my ( @list );

    @list = @{ Common::Admin->code_list(
                   {
                       "scripts" => 0,
                       "modules" => 1,
                       "numbers" => 0,
                       "dirs" => 0,
                       "total" => 0,
                       "expr" => "",
                       "format" => "dump",
                   }) };
    
    @list = map { $_->[1] } @list;

    # Filter unwanteds,

    @list = grep { $_ !~ /(^Not_working)|Simrank/ } @list;   # TODO compilation problems
    @list = grep { $_ !~ /(Download|Import)\.pm$/ } @list;
    @list = grep { $_ !~ /Old_code/ } @list;
    @list = grep { $_ !~ /Patscan/ } @list;

    # Add non-system perl modules,

    unshift @list, qw (        RNA.pm        );

    # Put config and messages on top,

    @list = grep { $_ !~ /^Common\/(Config|Messages)\.pm$/ } @list;
    unshift @list, qw ( Common/Config.pm Common/Messages.pm );

    # PDL emits warnings and errors during load, which will crash the 
    # rest of the loading (they eval and test for error afterwards and
    # think thats okay). So the easiest way to avoid that PDL loading 
    # triggers our error handler is to load it first,
    
    unshift @list, qw ( PDL/Lite.pm PDL/Char.pm PDL/IO/FastRaw.pm PDL/IO/FlexRaw.pm );

    return wantarray ? @list : \@list;
}

sub list_projects
{
    # Niels Larsen, April 2008.

    # Lists projects. The output is sorted on the given optional field.

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, $fields, @table );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( fields sort filter ) ],
        });
    
    # Get all projects, 

    $menu = Registry::Get->projects;

    $fields = $args->fields;
    $fields =~ s/title/description->title/;
    $args->fields( $fields );

    # Create table,

    @table = Registry::List->create_table_from_menu( $menu, $args );

    return wantarray ? @table : \@table;
}

sub list_software
{
    # Niels Larsen, April 2009.

    # Lists software given by a list of field keys. If "installed" and
    # "uninstalled" are given as filter keys, the returned table will 
    # include only installed/uninstalled software. The output is sorted
    # on the given optional field.

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, $names, @table );
    
    $args = &Registry::Args::check(
        $args,
        {
            "AR:0" => [ qw ( types ) ],
            "S:1" => [ qw ( fields sort filter ) ],
        });
    
    # Get all software, 

    $menu = Registry::Get->softwares;

    # Filter by either installed or uninstalled,

    if ( $args->filter eq "installed" )
    {
        $names = Registry::Register->registered( $args->types );
    } 
    elsif ( $args->filter eq "uninstalled" )
    {
        $names = Registry::Register->unregistered( $args->types, "softwares" );
    }

    if ( $names )
    {
        $menu->match_options( "name" => $names );
    }

    if ( $args->types and @{ $args->types } ) {
        $menu->match_options( "datatype" => $args->types );
    }

    # Create table,

    @table = Registry::List->create_table_from_menu( $menu, $args );

    return wantarray ? @table : \@table;
}

sub list_types
{
    # Niels Larsen, April 2008.

    # Lists types given by a list of field keys. The output is sorted
    # on the given optional field.

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, $names, @fields, $opt, @row, @table, $field );

    # Get all types, 

    $menu = Registry::Get->types;
    $menu->prune_expr( '$_->name !~ /^soft_/' );

    # Create table,

    @table = Registry::List->create_table_from_menu( $menu, $args );

    return wantarray ? @table : \@table;
}

sub show_item
{
    # Niels Larsen, April 2008.

    # Lists projects. The output is sorted on the given optional field.

    my ( $class,
         $args,          # Argument hash
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns list or list reference. 

    my ( $menu, $text, $type, $names, @fields, $opt, @row, @table, $field );

    require Data::Structure::Util;

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( type name format ) ],
    });

    return "Does not work yet\n";

    $type = $args->type;

    # Get the item,

    $menu = Registry::Get->$type( $args->name );

    $menu = &Data::Structure::Util::unbless( $menu );

#    if ( $args->format eq "YAML" )
#    {


    # Create table,

    return $text;
}

1;

__END__
