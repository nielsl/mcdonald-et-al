package Seq::Info;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Module that defines get/setters of sequence annotation.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;
use Tie::IxHash;

use Common::Config;
use Common::Messages;

use base qw ( Common::Obj );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our @Methods = (
    [ "parse_header",        "Parses the header field and creates info hash" ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOADED ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my %Auto_get_setters = map { $_, 1 } qw 
    (
     mol_name org_name org_taxon db_ids clu_num seq_count gb_acc
     seq_quals seq_id seq_mask qual_mask orig_id orig_coords ali_num
     ncbi_taxid definition
    );

sub AUTOLOAD
{
    # Niels Larsen, March 2007.

    my ( $self,
         $value,
         ) = @_;

    my ( $method, $id );

    our $AUTOLOAD =~ /::(\w+)$/ and $method = $1;

    if ( $Auto_get_setters{ $method } )
    {
        if ( defined $value )
        {
              return $self->{ $method } = $value;
        }
        elsif ( exists $self->{ $method } )
        {
              return $self->{ $method };
          }
        else {
            return;
        }
    }
    elsif ( $method ne "DESTROY")
    {
        $method = "SUPER::$method";
        
        no strict "refs";
        return eval { $self->$method( $value ) };
    }

    return;
}

sub stringify
{
    # Niels Larsen, May 2010.
    
    # Converts an info object to a string, which is returned. The string 
    # is of this type: "key=val; key=val; key=val". Does the opposite of
    # the objectify routine. Remembers the original string order. 

    my ( $obj,   # Seq::Info object or hash
        ) = @_;

    # Returns string.

    my ( @str, $key, $val );

    foreach $key ( keys %{ $obj } )
    {
        if ( $Auto_get_setters{ $key } ) {
            $val = $obj->{ $key };
        } else {
            &error( qq (Wrong looking key: "$key") );
        }
        
        if ( ref $val eq "ARRAY" ) {
            push @str, "$key=". ${ &Seq::Common::format_loc_str( $val ) };
        } else {
            push @str, "$key=$val";
        }
    }
    
    return join "; ", @str;
}

sub new
{
    my ( $class,
         $hash,
        ) = @_;

    $hash //= {};

    bless $hash, $class;

    return $hash;
}

sub objectify
{
    # Niels Larsen, May 2010.

    # Converts an info string to a Seq::Info object. The input string is 
    # of this type: "key=val; key=val .. ". Does the opposite of the stringify
    # routine. Remembers the string order. 

    my ( $str,    # Info string
         $bless,
        ) = @_;

    # Returns object.

    my ( %hash, $pair, $obj, $key, $val );

    $bless //= 1;

#     tie %hash, "Tie::IxHash";   why was this added .. ?

    foreach $pair ( split "; ", $str )
    {
        if ( $pair =~ /^([^=]+)=(.*)$/ )
        {
            ( $key, $val ) = ( $1, $2 );

            if ( $Auto_get_setters{ $key } ) {
                $hash{ $key } = $val;
            } else {
                &error( qq (Wrong looking key: "$key") );
            }
        }
        else {
            &error( qq (Wrong looking info string: "$str") );
        }
    }

    if ( $bless ) {
        $obj = Seq::Info->new( \%hash );
    } else {
        $obj = \%hash;
    }

    return $obj;
}

sub parse_header
{
    # Niels Larsen, October 2010.

    # Parses the given text string according to a given expression and sets the 
    # given info fields. Returns a Seq::Info object.

    my ( $header,
         $regex,
         $fields,
        ) = @_;

    # Returns Seq::Info object.

    my ( $hash );

    if ( $hash = &Common::Util::parse_string( $header, $regex, $fields ) )
    {
        return Seq::Info->new( $hash );
    }

    return;
}

1;

__END__
