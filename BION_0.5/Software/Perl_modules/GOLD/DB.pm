package GOLD::DB;        #  -*- perl -*-

# Functions that reach into a database to get or put GOLD data.

use strict;
use warnings;

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &get_entry
                 );

use Common::DB;
use Common::Messages;


# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get_entry
{
    # Niels Larsen, August 2003.

    # Given a taxonomy ID, returns a memory structure from the 
    # database similar to the one that they parser generates.

    my ( $dbh,     # Database handle
         $id,      # Record ID
         ) = @_;

    my ( $sql, $entry, $webdata );

    $sql = qq (select * from gold_main where id = '$id');
    $entry = &Common::DB::query_hash( $dbh, $sql, "id" )->{ $id };

    $sql = qq (select name,link,type,email from gold_web where id = '$id');
    $entry->{"webdata"} = &Common::DB::query_array( $dbh, $sql );

    return $entry;
}

1;


__END__
