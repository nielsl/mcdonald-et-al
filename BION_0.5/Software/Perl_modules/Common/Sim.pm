package Common::Sim;                # -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# >>>>>>>>>>>>>>>>>>>>>>>> SIMPLE GETTERS AND SETTERS <<<<<<<<<<<<<<<<<<<<<

# To add a simple "getter" or "setter" method, just add its name to the
# following list. The AUTOLOAD function below will then generate the 
# corresponding method, which will double as getter and setter. They 
# can also be specified the normal way of course.

our @Auto_get_setters = qw 
    (
     id1 id2 beg1 beg2 end1 end2 score
     );

our %Auto_get_setters = map { $_, 1 } @Auto_get_setters;

sub AUTOLOAD
{
    # Niels Larsen, September 2005.
    
    # Defines a number of simple getter and setter methods, as defined by the 
    # %methods hash in the code. It is an alternative to writing them explicitly
    # which saves space. It is taken from page 130 in "Learning Perl Objects,
    # References & Modules" by Randal L. Schwartz, by O'Reilly, and modified a
    # bit.

    # Returns nothing but installs methods into the name space of this package.

    my ( %methods, $method );

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
        &Common::Messages::error( qq (Undefined method called -> "$AUTOLOAD") );
    }
}

# >>>>>>>>>>>>>>>>>>>>>>>>>> CLASS METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<

sub new
{
    my ( $class,
         %args,
         ) = @_;

    my ( $self, $key, $valid );

    $valid = { map { $_, 1 } ( "selected", @Auto_get_setters ) };

    $self = {};
    
    foreach $key ( keys %args )
    {
        if ( $valid->{ $key } )
        {
            $self->{ $key } = $args{ $key };
        }
        else {
            &Common::Messages::error( qq (Wrong looking key -> "$key") );
        }
    }

    $class = ( ref $class ) || $class;
    bless $self, $class;

    return $self;
}

1;

__END__
