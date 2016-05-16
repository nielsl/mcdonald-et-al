package RNA::Schema;     #  -*- perl -*-

use base "Registry::Schema";

sub get
{
    my ( $class,
         ) = @_;

    return bless $class->SUPER::get( "rna_seq" ), __PACKAGE__;
}

1;

__END__
