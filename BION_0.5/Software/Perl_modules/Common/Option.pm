package Common::Option;                # -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;
use Common::Util;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Menus, display columns, table listings, etc, consist of items that 
# describe relations between data, methods and viewers. The mandatory
# getter/setter methods and their values are:

# >>>>>>>>>>>>>>>>>>>>>>>> SIMPLE GETTERS AND SETTERS <<<<<<<<<<<<<<<<<<<<<

# To add a simple "getter" or "setter" method, just add its name to the
# following list. The AUTOLOAD function below will then generate the 
# corresponding method, which will double as getter and setter. They 
# can also be specified the normal way of course.

our @Auto_get_setters = qw
    (
     id sid cid jid pid objtype type datapath datadir
     datatype datatypes formats format value values submit checkbox
     routine min_score max_score min_pix_per_col min_pix_per_row
     ifiles ifile itypes iformat itype otypes selectable dbname dbfile dbtype 
     input inputs ofile opath output outputs oformat method methods_menu 
     results_menu inputdb dirpath source display 
     searchdbs serverdbs serverdb viewer viewers input_type page
     image href css style bgcolor fgcolor ft_type timeout
     name label title coltext tiptext helptext text userfile request status
     sys_request is_active date count sub_time command keywords
     beg_time end_time message job titles default menu_1 menu_2
     src_name inst_name url program pre_params params post_params
     job_dir res_dir db_dir tab_dir ali_dir seq_dir pat_dir
     i_file
     );

our %Auto_get_setters = map { $_, 1 } @Auto_get_setters;

sub AUTOLOAD
{
    # Niels Larsen, September 2005.
    
    my ( $self,
         $value,
         ) = @_;

    our $AUTOLOAD;

    my ( $field );
    
    if ( not ref $self ) {
        &Common::Messages::error( qq (AUTOLOAD argument is not an object -> "$self" ) );
    }
    
    $AUTOLOAD =~ /::(\w+)$/ and $field = $1;

    if ( $Auto_get_setters{ $field } )
    {
        if ( defined $value ) {
            return $self->{ $field } = $value;
        } else {
            return $self->{ $field };
        }

#           } elsif ( exists $self->{ $field } ) {
#               return $self->{ $field };
#           } else {
#             &Common::Messages::error( qq (Option field does not exist -> "$field") );
#         }
    }
    elsif ( $AUTOLOAD !~ /DESTROY$/ ) {
        &Common::Messages::error( qq (Undefined method called -> "$AUTOLOAD") );
    }

    return;
}

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

# >>>>>>>>>>>>>>>>>>>>>>>>>> CLASS METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<

sub clone
{
    # Niels Larsen, October 2005.

    # Copies an option object to a new one.

    my ( $self,           # Menu option object
         ) = @_;

    # Returns a menu option object.

    my ( $copy );

    $copy = &Storable::dclone( $self );

    return $copy;
}

sub delete
{
    # Niels Larsen, January 2006.
    
    # Deletes a given key and its value. 

    my ( $self,         # Menu option object
         $key,          # Key 
         ) = @_;

    # Returns a menu option object.

    delete $self->{ $key };

    return $self;
}

sub is_menu
{
    my ( $self,
         ) = @_;

    my ( $ref );
    
    $ref = ref $self;

    if ( $ref =~ /::Menus$/ )
    {
        return 1;
    }

    return;
}

sub is_option
{
    my ( $self,
         ) = @_;

    my ( $ref );

    $ref = ref $self;

    if ( $ref =~ /::Option$/ )
    {
        return 1;
    }

    return;
}

sub selected
{
    # Niels Larsen, October 2005.

    # Sets or gets the selection flag of a given option. 

    my ( $self,       # Option object
         $value,      # Value
         ) = @_;

    # Returns 1 or nothing. 

    if ( defined $value )
    {
        $self->{"selected"} = $value;
        return $self;
    }
    else
    {
        if ( defined $self->{"selected"} ) {
            return $self->{"selected"};
        } else {
            return;
        }
    }
}

sub match
{
    # Niels Larsen, October 2005.

    # Returns true if all the keys and values in a given hash also occur
    # in the given option hash. If not, nothing is returned. 

    my ( $self,        # Option object
         @args,        # Matching hash
         ) = @_;

    # Returns 1 or nothing.

    my ( $i, $key, $value, $count );

    if ( not @args ) {
        &Common::Messages::error( qq (No match arguments given.) );
    }

    $count = 0;

    for ( $i = 0; $i <= $#args; $i += 2 )
    {
        $key = $args[$i];
        $value = $args[$i+1];

        if ( $key eq "expr" )
        {
            $_ = $self;
            $count += 1 if eval $value;
        } 
        elsif ( $self->$key eq $value )
        {
            $count += 1;
        }
    }

    if ( $count == scalar @args / 2 ) {
        return 1;
    } else {
        return;
    }
}

sub mismatch
{
    # Niels Larsen, October 2005.

    # Returns true if one or more of the keys and values in a given hash 
    # do not occur in the given option hash. If they do, nothing is 
    # returned. 

    my ( $self,        # Option object
         $hash,        # Matching hash
         ) = @_;

    # Returns 1 or nothing.

    my ( $key, $value );

    foreach $key ( keys %{ $hash } )
    {
        $value = $hash->{ $key };

        if ( $self->{ $key } ne $value )
        {
            return 1;
        }
    }

    return;
}

sub matches
{
    # Niels Larsen, October 2005.

    # Returns a list of options that satisfy given exact match criteria:
    # The second argument is a list of key value pairs, where the key 
    # must be one of the methods known by the objects that are in the 
    # options list. The value is a string, with one exception: if the 
    # key is "id", then a list of ids are allowed; then all options that
    # match either of the ids will be included. Between the key/value
    # pairs there is an implicit "and". The following call
    # 
    # $options = $menu->match_options( "id" => [2,3], "bgcolor" => "#666666" );
    #
    # means "get all options with id 2 or 3, and with background color
    # set to "#666666".

    my ( $self,    # Option object
         @args,    # Key/value pairs
         ) = @_;

    # Returns a list. 

    my ( $arg_key, $arg_value, $data_value, %ids, $expr, $field, $oper, $val );

#    &dump( $self );
#    &dump( \@args );

    if ( @args ) 
    {
        if ( scalar @args % 2 == 0 )
        {
            if ( grep { not defined $_ } @args ) {
                &dump( \@args );
                &Common::Messages::error( qq (Argument has undefined element(s)) );
            }
        }
        else {
            &Common::Messages::error( qq (Uneven number of arguments.) );
        }
    } 
    else {
        &Common::Messages::error( qq (No arguments.) );
    }

    while ( @args )
    {
        $arg_key = shift @args;
        $arg_value = shift @args;

        if ( $arg_key eq "expr" )
        {
            ( $field, $oper, $val ) = split " ", $arg_value;
            $expr = '$self->'.$field." $oper $val";

            return if not eval $expr;
        }
        else
        {
            $arg_value = [ $arg_value ] if not ref $arg_value;

            $data_value = $self->$arg_key;

            if ( not ref $data_value )
            {
                $data_value = [ $data_value ];
            }
            elsif ( ref $data_value ne "ARRAY" ) {
                &Common::Messages::error( qq (The value of "$arg_key" should be either a list or a simple scalar.) );
            }
            
            %ids = map { $_, 1 } @{ $arg_value };
            
            return if not grep { defined $_ and $ids{ $_ } } @{ $data_value };
        }
    }

    return 1;
}

1;

__END__

# sub date
# {
#     my ( $self,
#          $date,
#          ) = @_;

#     if ( defined $date )
#     {
#         $self->{"date"} = $date;
#         return $self;
#     }
#     elsif ( exists $self->{"date"} )
#     {
#         return $self->{"date"};
#     }
#     else 
#     {
#         $self->{"date"} = &Common::Util::time_string_to_epoch();
#         return $self->{"date"};
#     }
# }
