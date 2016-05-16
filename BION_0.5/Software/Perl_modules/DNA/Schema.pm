package DNA::Schema;     #  -*- perl -*-

use base "Registry::Schema";

sub get
{
    my ( $class,
         ) = @_;

    return bless $class->SUPER::get( "dna_seq" ), __PACKAGE__;
}

1;

__END__
