package GO::Schema;     #  -*- perl -*-

# Perlified schema definition for GO database.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &relational
                 );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub relational
{
    # Niels Larsen, October 2003.

    # Creates a hash where keys are table names and values are lists of 
    # [ field name, datatype, index specification ] where the index 
    # specification is optional. 

    # Returns a hash. 

    my $schema = 
    {
        "go_def" => [
                     [ "go_id", "mediumint not null", "index go_id_ndx (go_id)" ],
                     [ "name", "varchar(255) not null", "index name_ndx (name,go_id)" ],
                     [ "deftext", "text not null", "index deftext_ndx (deftext(255))" ],
                     [ "comment", "text not null", "index comment_ndx (comment(255))" ],
                     ],

        "go_def_ref" => [
                         [ "go_id", "mediumint not null", "index go_id_ndx (go_id)" ],
                         [ "db", "varchar(255) not null", "index db_ndx (db,go_id)" ],
                         [ "name", "varchar(255) not null", "index name_ndx (name,go_id)" ],
                         ],
        
        "go_edges" => [
                       [ "go_id", "mediumint not null", "index go_id_ndx (go_id,parent_id)" ],
                       [ "parent_id", "mediumint not null", "index parent_id_ndx (parent_id,go_id)" ],
                       [ "dist", "tinyint not null", "index dist_ndx (dist,go_id)" ],
                       [ "depth", "tinyint not null", "index depth_ndx (depth,go_id)" ],
                       [ "leaf", "tinyint not null", "index leaf_ndx (leaf,go_id)" ],
                       [ "rel", "char(1) not null", "index rel_ndx (rel,go_id)" ],
                       ],
        
        "go_synonyms" => [
                          [ "go_id", "mediumint not null", "index go_id_ndx (go_id)" ],
                          [ "name", "varchar(255) not null", "index name_ndx (name,go_id)" ],
                          [ "syn", "varchar(255) not null", "index syn_ndx (syn,go_id)" ],
                          [ "rel", "varchar(255) not null", "index rel_ndx (rel,go_id)" ],
                          ],
        
        "go_external" => [
                          [ "go_id", "mediumint not null", "index go_id_ndx (go_id)" ],
                          [ "ext_db", "varchar(255) not null", "index ext_db_ndx (ext_db,go_id)" ],
                          [ "ext_id", "varchar(255) not null", "index ext_id_ndx (ext_id,go_id)" ],
                          [ "ext_name", "varchar(255) not null", "index ext_name_ndx (ext_name,go_id)" ],
                          ],

        "go_genes" => [
                       [ "db", "varchar(50) not null", "index db_ndx (db)" ],
                       [ "db_id", "varchar(50) not null", "index db_id_ndx (db_id)" ],
                       [ "gen_id", "mediumint not null", "index get_id_ndx (gen_id)" ],
                       [ "db_name", "varchar(255) not null", "" ],
                       [ "db_symbol", "varchar(50) not null", "index db_symbol_ndx (db_symbol)" ],
                       [ "modifier", "varchar(255) not null", "" ],
                       [ "evidence", "char(3) not null", "" ],
                       [ "aspect", "char(1) not null", "" ],
                       [ "db_type", "varchar(255) not null", "" ],
                       [ "date", "date not null", "" ],
                       [ "db_assn", "varchar(255) not null", "" ],
                       ],

        "go_genes_ref" => [
                           [ "db", "varchar(255) not null", "index db_ndx (db)" ],
                           [ "db_id", "varchar(255) not null", "index db_id_ndx (db_id)" ],
                           [ "gen_id", "mediumint not null", "index gen_id_ndx (gen_id)" ],
                           ],

        "go_genes_tax" => [
                           [ "go_id", "mediumint not null", "index go_id_ndx (go_id,tax_id)" ],
                           [ "gen_id", "mediumint not null", "index gen_id_ndx (gen_id)" ],
                           [ "tax_id", "mediumint not null", "index tax_id_ndx (tax_id,go_id)" ],
                           [ "tax_id_use", "mediumint not null", "" ],
                           ],

#        "go_genes_from" => [
#                            [ "db", "varchar(255) not null", "index db_ndx (db)" ],
#                            [ "db_id", "varchar(255) not null", "index db_id_ndx (db_id)" ],
#                            [ "db_from", "varchar(255) not null", "index db_from_ndx (db_from)" ],
#                            ],
        
        "go_genes_synonyms" => [ 
                                 [ "gen_id", "mediumint not null", "index gen_id_ndx (gen_id)" ],
                                 [ "db_syn", "varchar(255) not null", "index db_syn_ndx (db_syn)" ],
                                 ],

        "go_stats" => [
                       [ "go_id", "int not null", "index go_id_ndx (go_id)" ],
                       [ "go_terms_tsum", "int unsigned not null default 0" ],
                       [ "go_terms_usum", "int unsigned not null default 0" ],
                       [ "go_genes_node", "int unsigned not null default 0" ],
                       [ "go_genes_tsum", "int unsigned not null default 0" ],
                       [ "go_genes_usum", "int unsigned not null default 0" ],
                       [ "go_orgs_usum", "int unsigned not null default 0" ],
                       ],
    };
    
    return $schema;
}

1;

__END__
