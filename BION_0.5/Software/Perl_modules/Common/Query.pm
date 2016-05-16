package Common::Query;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# This whole module is rudimentary and just started. 
#
# Contains functions that manage queries, and has dependency maps for 
# methods and viewers. These maps describe the inputs and outputs that 
# each method or viewer are able to consume and produce.
#
# datatype_to_formats
# method_to_inputs
# method_to_searchdbs
# input_to_methods
# inputdb_to_methods
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use Common::Config;
use Common::Messages;
use Common::File;

use base qw ( Common::Menus );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub datatype_to_formats
{
    # Niels Larsen, January 2006.

    # Returns a list of formats that a given datatype can come with. Wrong 
    # datatype names give fatal errors and prints a list of accepted ones. 

    my ( $class,            # Class name
         $name,             # Datatype name
         ) = @_;

    my ( $datatype, $names, $text );

    $datatype = $class->datatype_menu()->match_option( "name" => $name );

    if ( $datatype )
    {
        $names = $datatype->formats;
    }
    else
    {
        $name = "" if not defined $name;
        $text = join ", ", map { $_->name } $class->datatype_menu->options;
        $text = qq (Wrong looking datatype -> "$name".\nAccepted ones are "$text");

        &Common::Messages::error( $text );
    }

    if ( @{ $names } ) {
        return wantarray ? @{ $names } : $names;
    } else {
        return;
    }
}

    
sub method_to_inputs
{
    # Niels Larsen, November 2005.

    # Returns a list of inputs that a given method can work with. Wrong 
    # input names give fatal errors and prints a list of accepted ones. 

    my ( $class,            # Class name
         $name,             # Method name
         ) = @_;

    # Returns a list. 

    my ( $method, $names, $text );

    $method = $class->methods_menu_all()->match_option( "name" => $name );

    if ( $method )
    {
        $names = $method->inputs;
    }
    else
    {
        $name = "" if not defined $name;
        $text = join ", ", map { $_->name } $class->datatype_menu->options;
        $text = qq (Wrong looking input name -> "$name".\nAccepted ones are "$text");

        &Common::Messages::error( $text );
    }

    if ( @{ $names } ) {
        return wantarray ? @{ $names } : $names;
    } else {
        return;
    }
}

sub method_to_searchdbs
{
    # Niels Larsen, November 2005.

    # Returns a list of the server databases that a given method can work 
    # with. Wrong database names give fatal errors and prints a list of 
    # accepted ones. 

    my ( $class,            # Class name
         $name,             # Method name
         ) = @_;

    # Returns a list. 

    my ( $method, $names, $text );

    &dump( $class->methods_menu_all() );
    $method = $class->methods_menu_all()->match_option( "name" => $name );

    &dump( $method );

    if ( $method )
    {
        $names = $method->searchdbs;
    }
    else
    {
        $name = "" if not defined $name;
        $text = join ", ", map { $_->name } $class->methods_menu_all->options;
        $text = qq (Wrong looking method name -> "$name".\nAccepted ones are "$text");
        &Common::Messages::error( $text );
    }

    if ( @{ $names } ) {
        return wantarray ? @{ $names } : $names;
    } else {
        return;
    }
}

sub input_to_methods
{
    # Niels Larsen, November 2005.

    # Returns a list of names of methods that accept a given input, given
    # by its name. Wrong input names give fatal errors and prints a list 
    # of accepted ones. 

    my ( $class,           # Class name
         $name,            # Input name
         ) = @_;

    # Returns a list. 

    my ( $input, $text, $option, @names );

    $input = $class->datatype_menu()->match_option( "name" => $name );

    if ( not $input )
    {
        $name = "" if not defined $name;
        $text = join ", ", map { $_->name } $class->datatype_menu->options;
        $text = qq (Wrong looking input name -> "$name".\nAccepted ones are "$text");

        &Common::Messages::error( $text );
    }
    
    foreach $option ( $class->methods_menu_all()->options )
    {
        if ( grep { $_ eq $name } @{ $option->inputs } )
        {
            push @names, $option->name;
        }
    }

    if ( @names ) {
        return wantarray ? @names : \@names;
    } else {
        return;
    }
}

sub inputdb_to_methods
{
    # Niels Larsen, November 2005.

    # Returns a list of method names that can work with a given server 
    # database name. Wrong database names give fatal errors and prints 
    # list of accepted ones.

    my ( $class,           # Class name
         $name,            # Database name
         ) = @_;

    # Returns a list. 

    my ( $inputdb, $text, $methods_menu, $option, @names );

    $inputdb = $class->searchdbs_menu()->match_option( "name" => $name );

    if ( not $inputdb )
    {
        $name = "" if not defined $name;
        $text = join ", ", map { $_->name } $class->searchdbs_menu->options;
        $text = qq (Wrong looking database name -> "$name".\nAccepted ones are "$text");

        &Common::Messages::error( $text );
    }        

    $methods_menu = $class->methods_menu_all();

    foreach $option ( $methods_menu->options )
    {
        if ( grep { $_ eq $name } @{ $option->searchdbs } )
        {
            push @names, $option->name;
        }
    }

    if ( @names ) {
        return wantarray ? @names : \@names;
    } else {
        return;
    }
}

1;


__END__
