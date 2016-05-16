package Data::Registry::Formats;            # -*- perl -*-

# Descriptions of all formats known to the system. 

use strict;
use warnings FATAL => qw ( all );

my @descriptions =
    ({
        "title" => "Fasta format",
        "name" => "fasta_wrapped",
        "dbtypes" => [ "rna_seq", "dna_seq", "prot_seq" ],
    },{
        "title" => "Fasta oneline",
        "name" => "fasta",
        "dbtypes" => [ "rna_seq", "dna_seq", "prot_seq" ],
    },{
        "title" => "Stockholm format",
        "name" => "stockholm",
        "dbtypes" => [ "rna_ali" ],
    },{
        "title" => "Column format",
        "name" => "col",
        "dbtypes" =>  [ "rna_seq", "dna_seq", "prot_seq", "rna_ali", "dna_ali", "prot_ali" ],
    },{
        "title" => "PatScan format",
        "name" => "patscan",
        "dbtypes" => [ "rna_pat", "dna_pat", "prot_pat" ],
    },{
        "title" => "Native PDL format",
        "name" => "pdl",
    },{
        "title" => "OBO format",
        "name" => "obo",
    },{
        "title" => "NCBI taxonomy",
        "name" => "ncbi_tax",
    },{
        "title" => "EMBL format",
        "name" => "embl",
    },{
        "title" => "GenBank format",
        "name" => "genbank",
    },{
        "title" => "GreenGenes taxonomy",
        "name" => "greengenes_tax",
    },{
        "title" => "Blast DB format",
        "name" => "blastn",
        "dbtypes" => [ "dna_seq", "rna_seq" ],
    },{
        "title" => "Blast DB format",
        "name" => "blastp",
        "dbtypes" => [ "prot_seq" ],
    },{
        "title" => "Simrank DB format",
        "name" => "simrank",
        "dbtypes" => [ "dna_seq", "rna_seq" ],
    },{
        "title" => "Simrank table",
        "name" => "simrank_table",
    },{
        "title" => "Tab-separated table",
        "name" => "tab_table",
    },{
        "title" => "Comma-separated table",
        "name" => "comma_table",
    },{
        "title" => "Simscan table",
        "name" => "simscan_table",
    },{
        "title" => "Blast output table",
        "name" => "blast_table",
    },{
        "title" => "Database table",
        "name" => "db_table",
    },{
        "title" => "Blast output text",
        "name" => "blast_text",
    },{
        "title" => "Blast output XML",
        "name" => "blast_xml",
    },{
        "title" => "Text XML",
        "name" => "text_xml",
    });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    return wantarray ? @descriptions : \@descriptions ;
}    
    
1;

__END__

#     },{
#         "title" => "Fast-ali format",
#         "name" => "fastali",
#         "dbtypes" => [ "rna_ali", "dna_ali", "prot_ali" ],
