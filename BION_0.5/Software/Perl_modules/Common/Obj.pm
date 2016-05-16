package Common::Obj;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Basic object manipulation routines.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

sub new
{
    # Niels Larsen, May 2007.

    # Returns an object that with the given hash keys and values as 
    # methods - all other methods than those given will fail. The 
    # AUTOLOAD routine in this module makes this work. It is used in
    # routines that use argument hashes with many fields.

    my ( $class,      # Class name
         $args,       # Hash of arguments
         ) = @_;

    # Returns an object.

    my ( $self );

    $args = {} if not defined $args;

    $self = $args;

    return bless $self, $class;
}

sub AUTOLOAD
{
    # Niels Larsen, May 2007.

    # Creates get/setter methods for the keys in the hash given if missing. 
    # Attempts to use other methods later will trigger a crash with trace-back.

    my ( $self,         # Object hash
         ) = @_;

    # Returns nothing.

    our $AUTOLOAD;

    my ( $field, $pkg, $code, $str );

#    caller eq __PACKAGE__ or &error( qq (May only be called from within ). __PACKAGE__ );

    return if $AUTOLOAD =~ /::DESTROY$/;

    $field = $AUTOLOAD;
    $field =~ s/.*::// ;

    $pkg = ref $self;

    $code = eval qq
    {
        package $pkg;
        
        sub $field
        {
            my \$self = shift;
            
            if ( exists \$self->{ "$field" } )
            {
                \@_ ? \$self->{ "$field" } = shift : \$self->{ "$field" };
            }
            else
            {
                my \$str = join qq (", "), sort ( CORE::keys %{ \$self } );
                &Common::Messages::error( qq (Unknown accessor: "$field".\n) 
                                        . qq (Allowed accessors: "\$str".) );
                exit -1;
            }
        }
    };
    
    if ( $@ ) {
        &Common::Messages::error( "Unknown method $AUTOLOAD : $@" );
    }
    
    goto &{ $AUTOLOAD };
    
    return;
};

sub add_field
{
    # Niels Larsen, November 2009.
    
    # Adds a new field to an existing object, optionally with the given value.
    # Returns the updated object.

    my ( $self,
         $field,      # Field name
         $value,      # Field value - OPTIONAL
        ) = @_;

    # Returns object.

    $self->{ $field } = $value;

    return $self;
}

sub delete_field
{
    # Niels Larsen, November 2009.
    
    # Deletes a field with the given name. No error if the field does not 
    # exist. Returns an updated object.

    my ( $self,
         $key,
        ) = @_;

    # Returns object.

    if ( defined $key ) {
        delete $self->{ $key };
    } else {
        &Common::Messages::error("No delete key given");
    }

    return $self;
}

sub merge_args
{
    my ( $class,
         $defs,
         $args,
        ) = @_;

    if ( $args ) {
        $args = { %{ $defs }, %{ $args } };
    } else {
        $args = $defs;
    }

    return $args;
}

1;

__END__
