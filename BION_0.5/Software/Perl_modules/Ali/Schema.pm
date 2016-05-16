package Ali::Schema;     #  -*- perl -*-

# 
# 

use base "Registry::Schema";

sub get
{
    my ( $class,
         ) = @_;

    return bless $class->SUPER::get( "ali" ), __PACKAGE__;
}

1;

__END__
