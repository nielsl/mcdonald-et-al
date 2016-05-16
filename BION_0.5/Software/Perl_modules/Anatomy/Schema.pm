package Anatomy::Schema;     #  -*- perl -*-

# Perlified schema definition for disease database.

use strict;
use warnings;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 $db_prefix
                 $id_name
                 $def_table
                 $edges_table
                 $synonyms_table
                 $xrefs_table
                 $stats_table

                 &relational
                  );

use Common::DAG::Schema;

our ( $def_table, $edges_table, $synonyms_table, $xrefs_table,
      $stats_table, $db_prefix, $id_name );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub relational
{
    # Niels Larsen, October 2004.

    # Creates a hash where keys are table names and values are lists of 
    # [ field name, datatype, index specification ] where the index 
    # specification is optional. NOTE: if you change these names and 
    # fields then you must also update the routine that tablifies an 
    # entry hash (look in &Anatomy::Import::tablify_entry). 

    # Returns a hash.

    my ( $schema );

    $Common::DAG::Schema::db_prefix = $db_prefix;
    $Common::DAG::Schema::id_name = $id_name;
    $Common::DAG::Schema::def_table = $def_table;
    $Common::DAG::Schema::edges_table = $edges_table;
    $Common::DAG::Schema::synonyms_table = $synonyms_table;
    $Common::DAG::Schema::xrefs_table = $xrefs_table;
    $Common::DAG::Schema::stats_table = $stats_table;

    $schema = &Common::DAG::Schema::relational();

    return $schema;
}

1;

__END__

