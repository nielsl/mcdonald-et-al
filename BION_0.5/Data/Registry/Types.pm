package Data::Registry::Types;            # -*- perl -*-

# Returns a list of the data types that the system understands.

use strict;
use warnings FATAL => qw ( all );

my @descriptions =
    ({
        # >>>>>>>>>>>>>>>>>>>>>>>> DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "title" => "Organism taxa",
        "name" => "orgs_taxa",
        "module" => "Taxonomy",
        "schema" => "orgs_taxa",
        "formats" => [],
     },{
         "title" => "Functions",
         "name" => "go_func",
         "module" => "GO",
         "schema" => "funcs",
         "formats" => [],
     },{
         "title" => "miRNA/mRNA co-expression",
         "name" => "expr_mirconnect",
         "module" => "Expr",
         "schema" => "expr_mirconnect",
         "formats" => [],
     },{
         "title" => "RNA sequences",
         "name" => "rna_seq", 
         "module" => "RNA",
         "schema" => "rna_seq",
         "formats" => [ "fasta" ],
     },{
         "title" => "RNA alignment",
         "name" => "rna_ali",
         "module" => "RNA",
         "schema" => "ali",
         "formats" => [ "pdl", "fasta", "stockholm" ],
         "features" => [ 
             "ali_nuc_color_dots",
             "ali_seq_cons",
             "ali_rna_pairs",
             "ali_pairs_covar",
             ],
     },{
         "title" => "RNA pattern",
         "name" => "rna_pat",
         "module" => "RNA",
         "formats" => [ "patscan" ],
     },{
         "title" => "Protein sequences",
         "name" => "prot_seq",
         "module" => "Protein",
         "formats" => [ "fasta" ],
     },{
         "title" => "Protein alignment",
         "name" => "prot_ali",
         "module" => "Protein",
         "schema" => "ali",
         "formats" => [ "pdl", "fasta" ],
         "features" => [
             "ali_prot_color_dots",
             "ali_seq_cons",
             "ali_prot_hydro",
             ],
     },{
         "title" => "Protein pattern",
         "name" => "prot_pat",
         "module" => "Protein",
         "formats" => [ "patscan" ],
     },{
         "title" => "DNA sequences",
         "name" => "dna_seq",
         "module" => "DNA",
         "schema" => "dna_seq",
         "formats" => [ "fasta" ],
     },{
         "title" => "Genomes",
         "name" => "dna_geno",
         "module" => "DNA",
         "schema" => "dna_seq",
         "formats" => [ "fasta" ],
     },{
         "title" => "DNA alignment",
         "name" => "dna_ali",
         "module" => "DNA",
         "schema" => "ali",
         "formats" => [ "pdl", "fasta" ],
         "features" => [
             "ali_nuc_color_dots",
             "ali_seq_cons",
             "ali_rna_pairs",
             "ali_pairs_covar",
             ],
     },{
         "title" => "DNA pattern",
         "name" => "dna_pat", 
         "module" => "DNA",
         "formats" => [ "patscan" ],
     },{
         "title" => "Simrank matches",
         "name" => "matches_simrank",
         "module" => "",
         "formats" => [ "simrank_table" ],
     },{
         "title" => "Simscan matches",
         "name" => "matches_simscan",
         "module" => "",
         "formats" => [ "simscan_table" ],
     },{
         "title" => "Blast matches",
         "name" => "matches_blast",
         "module" => "",
         "formats" => [ "blast_text", "blast_xml" ],
     },{
         "title" => "Word list",
         "name" => "words_list",
         "module" => "Words",
         "formats" => [ "comma_table" ],
     },{
         "title" => "Word text corpus",
         "name" => "words_text",
         "module" => "Words",
         "formats" => [ "text_xml" ],
     },{
         
         # >>>>>>>>>>>>>>>>>>>>>>>> SOFTWARE <<<<<<<<<<<<<<<<<<<<<<<<<

         "title" => "System software",
         "name" => "soft_sys", 
#        "src_path" => "Software/Package_sources",
#        "inst_path" => "Software/Package_installs",
     },{
         "title" => "Perl modules",
         "name" => "soft_perl_module",
#        "src_path" => "Software/Package_sources/Perl_modules",
#        "inst_path" => "",
     },{
         "title" => "Basic utilities",
         "name" => "soft_util", 
#        "src_path" => "Software/Package_sources/Utilities",
#        "inst_path" => "Software/Package_installs/Utilities",
     },{
         "title" => "Analysis software",
         "name" => "soft_anal", 
#        "src_path" => "Software/Package_sources",
#        "inst_path" => "Software/Package_installs",
     });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    return wantarray ? @descriptions : \@descriptions ;
}    
    
1;

__END__
