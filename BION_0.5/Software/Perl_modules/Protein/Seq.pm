package Protein::Seq;     #  -*- perl -*-

# Protein specific sequence routines. UNFINISHED.

use strict;
use warnings FATAL => qw ( all );

use base qw ( Seq::Common Seq::IO Seq::Import );

use Common::Config;
use Common::Messages;

# Class methods:
# 
# new
# valid_chars
#
# Instance methods:
#

# >>>>>>>>>>>>>>>>>>>>>>>>>> CLASS METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# sub new
# {
#     # Niels Larsen, June 2005.

#     # Not needed .. for testing

#     my ( $class,
#          %args,
#          ) = @_;

#     my ( $self );
    
#     $self = $class->SUPER::new( %args );

#     $class = (ref $class) || $class; bless $self, $class;

#     return $self;
# }

# sub valid_chars
# {
#     # Niels Larsen, July 2005.

#     # Returns a 1D piddle of valid IUB base characters for Protein

#     # Returns a PDL object.

#     return "GAVLISTDNEQCUMFYWKRHPgavlistdneqcumfywkrhp";
# }

# >>>>>>>>>>>>>>>>>>>>>>>>>>> INSTANCE METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

1;


__END__

