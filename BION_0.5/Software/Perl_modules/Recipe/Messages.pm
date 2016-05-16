package Recipe::Messages;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &error
);

use Common::Messages;
use Common::Tables;

our $Linwid = 74;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub oops
{
    # Niels Larsen, March 2013.

    # Writes an error message to the console and exists in void context,
    # returns the messages in non-void. The accepted $args keys are,
    # 
    # oops    Error message to be shown, newlines create multiple lines
    # list    List of places that triggered the error (optional)
    # help    Message with helpful hints, newlines create multiple lines
    #
    # If second argument is true, default on, a support message is shown
    # last.

    my ( $args,       # Arguments hash
         $supp,       # Show support text or not - OPTIONAL, default on
        ) = @_;

    # Returns string or nothing.

    my ( $lines, $line, $text, @lines, $info, $name, $skype, $phone, $email,
         $high, $row );

    $supp //= 0;

    $text = "-" x $Linwid ."\n";

    if ( $lines = $args->{"oops"} ) 
    {
        $lines = [ split "\n", $lines ] if not ref $lines;
        $text .= "\n";

        foreach $line ( @{ $lines } )
        {
            $text .= "  ". &echo_red_info(" OOPS ") ."  $line\n";
        }
    }
    
    if ( $args->{"list"} )
    {
        foreach $row ( @{ $args->{"list"} } )
        {
            $row = [ "", $row ] if not ref $row;
            $row = [ "", $row->[0] ] if not scalar @{ $row } > 1;
        }

        $text .= "\n";
        $text .= &Common::Tables::render_ascii_usage( $args->{"list"}, { "indent" => $args->{"indent"} // 4 } );
    }

    if ( $lines = $args->{"help"} )
    {
        $lines = [ split "\n", $lines ] if not ref $lines;
        $text .= "\n";

        foreach $line ( @{ $lines } )
        {
            $text .= "  ". &echo_info(" HELP ") ."  $line\n";
        }
    }

    if ( $supp ) {
        $text .= &Common::Messages::support_string();
    }

    $text .= "\n". "-" x $Linwid ."\n";

    if ( defined wantarray )
    {
        return $text;
    }
    else
    {
        &echo( $text );

        if ( -t STDIN ) {
            exit -1;
        } else {
            die;
        }
    }
    
    return;
}
    
1;

__END__

# sub save_errors
# {
#     # Niels Larsen, January 2010.

#     # Saves an error message in a file, in Config::General format. 
#     # The file includes method, perhaps an id etc. 

#     my ( $errs,    # List of messages
#          $args,    # Arguments 
#         ) = @_;

#     # Returns nothing.

#     my ( $method, @errs, $id, $file );

#     if ( defined ( $method = $args->method ) )
#     {
#         @errs = map { { "method" => $method, 
#                         "message" => $_->[1], } } @{ $errs };
#     } else {
#         @errs = map { $_->[1] } @{ $errs };
#     }

#     if ( defined ( $id = $args->id ) ) {
#         @errs = map { $_->{"id"} = $id; $_ } @errs;
#     }

#     &Common::Config::write_config_general( $Error_file, \@errs, "error" );

#     return;
# }

# sub show_errors
# {
#     # Niels Larsen, January 2010.

#     # Displays error messages and exits with -1.

#     my ( $errs,    # List of text strings
#         ) = @_;

#     # Returns nothing. 

#     my ( $max, @errs );

#     $max = &List::Util::max( map { length $_->[1] } @{ $errs } );
#     @errs = map { [ " ERROR", $_->[1] ] } @{ $errs };
    
#     &echo_messages( \@errs, { "linewid" => $max + 15, "linech" => "-" } );
#     exit -1;

#     return;
# }
    
# our $Error_file = "$Common::Config::tmp_dir/". __PACKAGE__ .".error";

