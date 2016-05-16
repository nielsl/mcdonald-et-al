package Registry::Schema;            # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Accessors for schemas. The module uses Registry::Get for fetching
# the data structures, but is a small set of convenience functions
# for getting schemas, their tables, their columns and names of 
# these. 
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use base qw ( Registry::Get );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get
{
    # Niels Larsen, April 2007.

    # Returns a schema if a name is given, or a menu of schemas if a 
    # list is given.

    my ( $class,          # Class name
         $arg,            # Schema name or list of names
         ) = @_;

    # Returns an object.

    my ( $obj );

    if ( defined $arg )
    {
        if ( not ref $arg )
        {
            $obj = $class->schema( $arg );
        }
        elsif ( ref $arg eq "ARRAY" ) 
        {
            $obj = $class->schemas( $arg );
        }
        else {
            &error( qq (Schema argument must be either a name or list of names.) );
        }
    }
    else {
        &error( qq (No schema name or name list given.) );
    }

    bless $obj, $class;

    return $obj;
}

sub get_all
{
    # Niels Larsen, April 2007.

    # Returns a menu of all schemas defined.

    my ( $class,        # Class name
         ) = @_;

    # Returns a menu.

    return $class->get( [ $class->get_names ] );
}

sub get_list
{
    # Niels Larsen, April 2007.

    # Returns a list of schemas for given name, list of names.

    my ( $class,          # Class name
         $arg,            # Schema name or list of names
         ) = @_;

    # Returns a list.

    return $class->get( $arg )->options;
}

sub get_names
{
    # Niels Larsen, April 2007.

    # Returns a list of all schema names.

    my ( $class,          # Class name
         ) = @_;

    # Returns a list.

    my ( @list );

    @list = $class->schema_ids;

    return wantarray ? @list : \@list;
}

sub table_menu
{
    # Niels Larsen, March 2007.

    # Returns a menu of all tables of a given schema.

    my ( $self,       # Schema
         ) = @_;

    # Returns an object.

    my ( $obj, $class );

    $obj = $self->{"tables"};

    $class = ref $self ? ref $self : $self;

    return bless $obj, $class;
}

sub table_names
{
    # Niels Larsen, April 2007.

    # Returns a list of table names of a given schema.

    my ( $self,      # Schema
         ) = @_;

    # Returns a list.

    my ( $table, @list );

    foreach $table ( $self->tables )
    {
        push @list, $table->name;
    }

    return wantarray ? @list : \@list;
}

sub tables
{
    # Niels Larsen, March 2007.

    # Creates a list of all tables of a given schema.

    my ( $self,         # Schema
         ) = @_;

    # Returns a list.

    my ( @list, $elem, $class );

    $class = ref $self ? ref $self : $self;

    foreach $elem ( $self->{"tables"}->options )
    {
        push @list, bless $elem, $class;
    }

    return wantarray ? @list : \@list;
}

sub table
{
    # Niels Larsen, April 2007.

    # Returns a table given by its name, from a given schema.

    my ( $self,         # Schema
         $name,         # Table name
         ) = @_;

    # Returns an object.

    my ( $obj, $class, $msg );

    if ( defined $name )
    {
        $class = ref $self ? ref $self : $self;

        $obj = $self->table_menu->match_option( "name" => $name );

        if ( defined $obj )
        {
            return bless $obj, $class;
        }
        else
        {
            $msg = join qq (", "), @{ $self->table_names };
            &error( qq (Wrong looking table name -> "$name".\nOptions: "$msg") );
        }
    }
    else {
        &error( qq (No table name given.) );
    }
    
    return;
}

sub columns
{
    # Niels Larsen, April 2007.
    
    # Returns a list of columns of a given table.

    my ( $self,        # Table
         ) = @_;

    # Returns a list.

    return $self->{"columns"}->options;
}

sub column
{
    # Niels Larsen, April 2007.

    # Returns a named column for a given table. A column is a tuple like 
    # [ 'ft_type', 'varchar(255) not null', 'index type_ndx (ft_type,ft_id)' ]
    # currently SQL for a relational database, but that could change.

    my ( $self,      # Table
         $name,      # Column name
         ) = @_;

    # Returns a list.

    my ( $col, $msg );

    if ( defined $name )
    {
        foreach $col ( $self->columns )
        {
            if ( $col->[0] eq $name )
            {
                return wantarray ? @{ $col } : $col;
            }
        }

        $msg = join qq (", "), map { $_->[0] } @{ $self->columns };
        &error( qq (Wrong looking column name -> "$name".\nOptions: "$msg") );
    }
    else {
        &error( qq (No column name argument given.) );
    }

    return;
}

sub column_index
{
    # Niels Larsen, April 2007.

    # Returns the index of a given column name for a given table.
    # For example, if a column named "id" is at the first position
    # then 0 is returned.

    my ( $self,         # Table
         $name,         # Column name
         ) = @_;

    # Returns an integer.

    my ( @columns, $i, $msg );

    if ( defined $name )
    {
        @columns = $self->columns;

        for ( $i = 0; $i <= $#columns; $i++ )
        {
            return $i if $columns[$i]->[0] eq $name;
        }

        $msg = join qq (", "), map { $_->[0] } @{ $self->columns };
        &error( qq (Wrong looking column name -> "$name".\nOptions: "$msg") );
    }
    else {
        &error( qq (No column name argument given.) );
    }

    return;
}

sub column_names
{
    # Niels Larsen, April 2007.

    # Returns a list of column names for a given table.

    my ( $self,           # Table
         ) = @_;

    # Returns a list.

    my ( @names );

    @names = map { $_->[0] } $self->columns;

    return wantarray ? @names : \@names;
}

1;

__END__
