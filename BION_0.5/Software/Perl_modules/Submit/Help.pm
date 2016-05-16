package Submit::Help;     #  -*- perl -*-

# Help texts for submission pages. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &pager
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Widgets;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub pager
{
    # Niels Larsen, July 2009.

    # Writes general help for the clipboard related pages. 

    my ( $request,
         ) = @_;

    # Returns a string. 

    my ( $xhtml, $title, $arrow, $body, $routine );

    if ( not defined $request ) {
        &error( qq (No request given) );
    }

    if ( $request =~ /^help_([a-z]+)$/ )
    {
        $routine = "Submit::Help::section_$1";
    
        no strict "refs";
        ( $title, $body ) = &{ $routine };
    }
    else {
        &error( qq (Wrong looking request -> "$request") );
    }

    $xhtml = &Common::Widgets::help_page( $body, $title );

    return $xhtml;
}

1;


__END__
