package Pat::Menus;     #  -*- perl -*-

# Menu options and functions specific to sequence.

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use Common::Util;

use base qw ( Common::Menus Common::Query );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub datatype_menu
{
    # Niels Larsen, December 2006.
    
    # Creates a menu of the datatypes that the alignment viewer 
    # understands. 

    my ( $class,
         ) = @_;

    # Returns a menu object.

    my ( $menu, $option, $text );

    $menu = $class->SUPER::datatype_menu();

    $menu->name( "pat_datatype_menu" );

    $menu->prune_expr( '$_->name =~ /_pat$/' );

    $class = ( ref $class ) || $class;
    bless $menu, $class;    

    return $menu;
}

sub formats_menu
{
    # Niels Larsen, January 2005.
    
    # Creates a menu of the formats that the alignment viewer 
    # understands. 

    my ( $class,
         $datatype,
         ) = @_;

    # Returns a menu object.

    my ( $menu, $names, $options, $option, $datatypes, @names );

    $menu = $class->SUPER::formats_menu();

    $menu->name( "pat_formats_menu" );

    if ( $datatype )
    {
        $names = $class->datatype_to_formats( $datatype );
    }
    else
    {
        $datatypes = $class->datatype_menu();

        foreach $option ( $datatypes->options ) {
            push @names, @{ $option->formats };
        }
        
        $names = &Common::Util::uniqify( \@names );
    }

    $menu->match_options( "name" => $names );

    $class = ( ref $class ) || $class;
    bless $menu, $class;    

    return $menu;
}

1;

__END__
