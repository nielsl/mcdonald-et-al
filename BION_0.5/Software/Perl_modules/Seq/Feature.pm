package Seq::Feature;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Primitives that create sequence features and give access to them. 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use Data::Dumper;

our @Auto_get_setters = qw 
    (
     db id beg end info mask molecule pos rel score seq type
     );

our %Auto_get_setters = map { $_, 1 } @Auto_get_setters;

sub AUTOLOAD
{
    # Niels Larsen, January 2007.
    
    # Defines a number of simple getter and setter methods, as defined in
    # the %Get_setters hash above. Returns nothing but defines methods 
    # into the name space of this package.

    my ( $method );

    our $AUTOLOAD;

    if ( $AUTOLOAD =~ /::(\w+)$/ and $Auto_get_setters{ $1 } )
    {
        $method = $1;
        
        {
            no strict 'refs';

            *{ $AUTOLOAD } = sub {

                if ( defined $_[1] ) {
                    $_[0]->{ $method } = $_[1];
                } else {
                    $_[0]->{ $method };
                }
            }
        }

        goto &{ $AUTOLOAD };
    }
    elsif ( $AUTOLOAD !~ /DESTROY$/ )
    {
        &error( qq (Undefined method called -> "$AUTOLOAD") );
    }

    return;
}

sub eval_field
{
    # Niels Larsen, January 2007.

    # Accepts a list of position ranges, converts it to a Data::Dumper 
    # string (one long line) and adds it as under the "locs" key. If
    # no argument given, returns an "eval'ed" version of the string. 

    my ( $self,        # Feature
         $key,         # Key string
         $value,       # Data structure or scalar
         ) = @_;

    # Returns object or structure.

    if ( defined $key ) 
    {
        if ( defined $value ) 
        {
            {
                local $Data::Dumper::Terse = 1;     # avoids variable names
                local $Data::Dumper::Indent = 0;    # no indentation
                
                $self->{ $key } = Dumper( $value );
            }
            
            return $self;
        }
        else {
            return eval $self->{ $key };
        }
    }
    else {
        &error( qq (No key given) );
    }
}

sub locs
{
    # Niels Larsen, January 2007.

    # Sets or gets the "locs" field to any data. Data::Dumper is used to 
    # ascify when set and eval is used when get.

    my ( $self, 
         $locs,
         ) = @_;

    # Returns object or structure.

    return $self->eval_field( "locs", $locs );
}

sub llocs
{
    # Niels Larsen, January 2007.

    # Sets or gets the "locs" field to any data. Data::Dumper is used to 
    # ascify when set and eval is used when get.

    my ( $self, 
         $locs,
         ) = @_;

    # Returns object or structure.

    return $self->eval_field( "llocs", $locs );
}

sub new
{
    # Niels Larsen, November 2006.

    # Creates new feature objects. Checks that keys are valid.

    my ( $class,
         %args,           # "key" => "value" arguments
         ) = @_;

    # Returns feature object.

    my ( $self, $key, %valid );

    if ( %args )
    {
        foreach $key ( keys %args )
        {
            if ( $Auto_get_setters{ $key } )
            {
                $self->{ $key } = $args{ $key };
            }
            else {
                &error( qq (Cannot be used with "new" -> "$key". ) );
            }
        }
    }
    else {
        $self = {};
    }

    $class = (ref $class) || $class;

    bless $self, $class;
    
    return $self;
}

sub overlap
{
    my ( $self,
         $ft,
         ) = @_;

    my ( $beg1, $end1, $beg2, $end2 );

    $beg1 = $self->beg;
    $end1 = $self->end;

    $beg2 = $ft->beg;
    $end2 = $ft->end;

    ( $beg1, $end1 ) = ( $end1, $beg1 ) if $end1 < $beg1;
    ( $beg2, $end2 ) = ( $end2, $beg2 ) if $end2 < $beg2;

    if ( &Common::Util::ranges_overlap( $beg1, $end1, $beg2, $end2 ) )
    {
        return 1;
    }
    else {
        return;
    }
}

sub within
{
    # Niels Larsen, June 2006.

    # Returns true if the sequence feature end point positions of feature 1
    # lie within feature 2's positions. 
    
    my ( $self,         # Feature 1 
         $ft,           # Feature 2
         ) = @_;

    # Returns 1 or nothing.

    my ( $beg1, $end1, $beg2, $end2 );

    $beg1 = $self->beg;
    $end1 = $self->end;

    $beg2 = $ft->beg;
    $end2 = $ft->end;

    ( $beg1, $end1 ) = ( $end1, $beg1 ) if $end1 < $beg1;
    ( $beg2, $end2 ) = ( $end2, $beg2 ) if $end2 < $beg2;

    if ( &Common::Util::range_within( $beg1, $end1, $beg2, $end2 ) )
    {
        return 1;
    }
    else {
        return;
    }
}

1;

__END__
