package Ali::Feature;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# The coordinates of an alignment feature can be an arbitrary set of 
# columns and/or rows in an alignment. We represent s positions
# a list of column and row ranges
#
# [ [ [colbeg,colend], .. ], [ [rowbeg,rowend], .. ] ]
#
# where all numbers are 0-based alignment numbers. The feature is 
# thus located where these ranges intersect, and the numbers must 
# be updated if the alignment changes. Then a feature has a name
# type, etc to identify it, so when it is pulled from permanent 
# storage it is represented as an object. UNFINISHED, IN FLUX

# Simple field getters/setters
# ----------------------------
#
# As setters they return an alignment object, as getters whatever the
# item is. All are instance methods. Most are created by the AUTOLOAD
# function below, some are written explicitly. To add a simple getter
# or setter, edit the list below. 

our @Auto_get_setters = qw
    (
     id sid ali_id ali_type type project source 
     score stats title colbeg colend rowbeg rowend
     areas paint cols rows
     );

our %Auto_get_setters = map { $_, 1 } @Auto_get_setters;

# >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;
use Common::Util;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub AUTOLOAD
{
    # Niels Larsen, September 2005.
    
    # Defines a number of simple getter and setter methods, as defined by the 
    # %methods hash in the code. It is an alternative to writing them explicitly
    # which saves space. It is taken from page 130 in "Learning Perl Objects,
    # References & Modules" by Randal L. Schwartz, by O'Reilly, and modified a
    # bit.

    # Returns nothing but installs methods into the name space of this package.

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

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub new
{
    my ( $class,
         %args,
         ) = @_;

    my ( $self, $key, $valid );

    $valid = { map { $_, 1 } @Auto_get_setters };
    $self = {};
    
    foreach $key ( keys %args )
    {
        if ( $valid->{ $key } )
        {
            $self->{ $key } = $args{ $key };
        }
        else {
            &error( qq (Wrong looking key -> "$key") );
        }
    }

    $class = ( ref $class ) || $class;
    bless $self, $class;

    return $self;
}

1;

__END__
