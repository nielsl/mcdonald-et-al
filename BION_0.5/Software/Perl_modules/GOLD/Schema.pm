package GOLD::Schema;     #  -*- perl -*-

# Perlified schema definitions for the GOLD dataset.

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
    # Niels Larsen, August 2006.

    # Creates a hash where keys are table names and values are lists of 
    # [ field name, datatype, index specification ] where the index 
    # specification is optional. 

    # Returns a hash. 

    my $schema = 
    {
        "gold_main" => [
                        [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id)" ],
                        [ "tax_id_auto", "mediumint unsigned not null", "index tax_id_auto_ndx (tax_id_auto)" ],
                        [ "domain", "varchar(255) not null", "index domain_ndx (domain,tax_id)" ],
                        [ "id", "mediumint unsigned not null", "index id_ndx (id,tax_id)" ],
                        [ "genus", "varchar(255) not null", "index genus_ndx (genus,tax_id)" ],
                        [ "species", "varchar(255) not null", "index species_ndx (species,tax_id)" ],
                        [ "strain", "varchar(255) not null", "index strain_ndx (strain,tax_id)" ],
                        [ "chromosome", "varchar(255) not null", "index chromosome_ndx (chromosome,tax_id)" ],
                        [ "status", "varchar(255) not null", "index status_ndx (status,tax_id)" ],
                        [ "size", "bigint not null", "index size (size,tax_id)" ],
                        [ "unit", "varchar(255) not null", "index unit_ndx (unit,tax_id)" ],
                        [ "date", "date not null", "index date_ndx (date,tax_id)" ],
                        [ "webpage", "varchar(255) not null", "index webpage_ndx (webpage,tax_id)" ],
                        [ "statrep", "varchar(255) not null", "index statrep_ndx (statrep,tax_id)" ],
                        [ "phylogeny", "varchar(255) not null", "index phylogeny_ndx (phylogeny,tax_id)" ],
                        [ "maplnk", "varchar(255) not null", "index maplnk_ndx (maplnk,tax_id)" ],
                        [ "norfs", "varchar(255) not null", "index norfs_ndx (norfs,tax_id)" ],
                        [ "pub_journal", "varchar(255) not null", "index pub_journal_ndx (pub_journal,tax_id)" ],
                        [ "pub_vol", "varchar(255) not null", "index pub_vol_ndx (pub_vol,tax_id)" ],
                        [ "pub_lnk", "varchar(255) not null", "index pub_lnk_ndx (pub_lnk,tax_id)" ],
                        [ "type", "varchar(255) not null", "index type_ndx (pub_journal,tax_id)" ],
                        ],

        "gold_web" => [
                       [ "id", "mediumint unsigned not null", "index id_ndx (id)" ],
                       [ "name", "varchar(255) not null", "index name_ndx (name,id)" ],
                       [ "link", "varchar(255) not null", "index link_ndx (link,id)" ],
                       [ "type", "varchar(255) not null", "index type_ndx (type,id)" ],
                       [ "email", "varchar(255) not null", "index email_ndx (email,id)" ],
                       ],
    };
    
    return wantarray ? @{ $schema } : $schema;
}

1;

__END__
