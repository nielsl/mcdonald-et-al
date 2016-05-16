package Doc::Viewer;       # -*- perl -*- 

# Module with functions that somehow have to do with documentation. 

use Exporter ();
@ISA = (Exporter);

@EXPORT_OK = qw (
                 widgets
                 widgets_howto
                 );

use Common::Widgets();

sub widgets
{
    # Niels Larsen, February 2003

    # Displays a page that shows the help texts that are embedded in 
    # the Widgets.pm module. 

    # Returns string.
}

# sub widgets_howto
# {
#     my ( $type,
#          ) = @_;

#     $type = uc $type;

#     my ( $title, 
#     if ( $type eq "TABLES" )
#     {
        


#     }
# }


1;

__END__
