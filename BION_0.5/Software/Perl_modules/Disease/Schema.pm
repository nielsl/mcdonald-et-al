package Disease::Schema;     #  -*- perl -*-

# Perlified schema definition for disease database.

use strict;
use warnings;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &relational
                  );

use Common::DAG::Schema;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub relational
{
    # Niels Larsen, October 2004.

    # Creates a hash where keys are table names and values are lists of 
    # [ field name, datatype, index specification ] where the index 
    # specification is optional. NOTE: if you change these names and 
    # fields then you must also update the routine that tablifies an 
    # entry hash (look in &Disease::Import::tablify_entry). 

    # Returns a hash.

    my ( $schema );

    $Common::DAG::Schema::def_table = "do_def";
    $Common::DAG::Schema::edges_table = "do_edges";
    $Common::DAG::Schema::synonyms_table = "do_synonyms";
    $Common::DAG::Schema::xrefs_table = "do_xrefs";
    $Common::DAG::Schema::stats_table = "do_stats";
    $Common::DAG::Schema::db_prefix = "do";
    $Common::DAG::Schema::id_name = "do_id";
    
    $schema = &Common::DAG::Schema::relational();

    return $schema;
}

1;

__END__
