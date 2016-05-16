package Taxonomy::Cells;          # -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use Common::Util;

use base qw ( Common::Option );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# 
# Inherits all methods from Common::Option
#
# expanded
# abbreviate
# is_cell

our @Methods = qw ( href img expanded expanded_data abbreviate is_cell sum );

# >>>>>>>>>>>>>>>>>>>>>>>> SIMPLE GETTERS AND SETTERS <<<<<<<<<<<<<<<<<<<<<

sub href
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"href"} = $value;
        return $self;
    }
    else {
        return $self->{"href"};
    }
}

sub img
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"img"} = $value;
        return $self;
    }
    else {
        return $self->{"img"};
    }
}

sub is_cell
{
    my ( $self,
         ) = @_;

    my ( $type );
    
    $type = ref $self;

    if ( $type =~ /::Cell$/ )
    {
        return 1;
    }

    return;
}

sub new
{
    my ( $class,
         %args,
         ) = @_;

    my ( $self, $key, $valid );

    $valid = { map { $_, 1 } @Methods, @Common::Option::Auto_get_setters };

    $self = {};
    
    foreach $key ( keys %args )
    {
        if ( $valid->{ $key } )
        {
            $self->{ $key } = $args{ $key };
        }
        else {
            &error( qq (Wrong looking key -> "$key") );
            exit;
        }
    }

    $class = ( ref $class ) || $class;
    bless $self, $class;

    return $self;
}

sub sum
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"sum"} = $value;
        return $self;
    }
    else {
        return $self->{"sum"};
    }
}

sub sum_count
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"sum_count"} = $value;
        return $self;
    }
    else {
        return $self->{"sum_count"};
    }
}

sub data_ids
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"data_ids"} = $value;
        return $self;
    }
    else {
        return $self->{"data_ids"};
    }
}

sub expanded
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"expanded"} = $value;
        return $self;
    }
    else {
        return $self->{"expanded"};
    }
}

sub expanded_data
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"expanded_data"} = $value;
        return $self;
    }
    else {
        return $self->{"expanded_data"};
    }
}

sub abbreviate
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        $self->{"abbreviate"} = $value;
        return $self;
    }
    else {
        return $self->{"abbreviate"};
    }
}

1;

__END__
