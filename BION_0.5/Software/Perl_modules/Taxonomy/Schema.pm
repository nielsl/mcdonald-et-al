package Taxonomy::Schema;     #  -*- perl -*-

# 
# 

use base "Registry::Schema";

sub get
{
    my ( $class,
         ) = @_;

    return bless $class->SUPER::get( "orgs_taxa" ), __PACKAGE__;
}

1;

__END__
