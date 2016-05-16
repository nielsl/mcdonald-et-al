package Query::MC::State;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# MiRConnect specific status and state related routines.
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Functions specific to user checking and administration. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &default_state
                 );

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub default_state
{
    # Niels Larsen, November 2005.

    # Defines default settings for each page or viewer. These defaults
    # are used when new users are created. 

    my ( $dataset,    # Dataset id - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( $state );

    $state = {
        "dataset" => $dataset,
        "request" => "",
        "version" => 1,
        "params" => [
            [ "mirna_single", 'Select miRNA' ],
            [ "mirna_family", '' ],
            [ "method", 'spcc' ],
            [ "target", 'genes' ],
            [ "correlation", 'positive' ],
            [ "maxtablen", 1000 ],
            [ "mirna_names", '' ],
            [ "genid_names", '' ],
            [ "annot_filter", '' ],
        ],
        "query_keys" => [],
        "query_values" => [],
        "download_keys" => [],    
        "download_values" => [],
    };

    return wantarray ? %{ $state } : $state;
}

1;

__END__
