package Data::Registry::Datasets;            # -*- perl -*-

# A list of all data packages that the system knows how to handle, whether
# installed or not. The packages defined here have ids that should not be 
# changed. Rules for adding new entries: dont omit any of the keys; if a 
# database is remote, set "datadir" to "" - routines use this to find out
# if a database is local or not; the "datatype" must be one of those in 
# the _all_data_types routine. 

# More non-working datasets after __END__ 

use strict;
use warnings FATAL => qw ( all );

my @descriptions = 
    ({
        # >>>>>>>>>>>>>>>>>>>>>>>>>> ORGANISMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        "name" => "orgs_taxa_ncbi",
        "label" => "NCBI",
        "title" => "NCBI taxonomy",
        "tiptext" => "General organism taxonomy curated by NCBI",
        "datapath" => "Organisms/Taxonomy/NCBI",
        "datatype" => "orgs_taxa",
        "format" => "ncbi_tax",
        "owner" => "bion",
        "downloads" => {
            "baseurl" => "ftp://ftp.ncbi.nih.gov/pub/taxonomy",
            "compare" => "name,size:100000,mtime:86400",
            "files" => [
                { "remote" => "taxdump.tar.gz" },
                { "remote" => "taxdump_readme.txt" },
            ],
        },
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>> EXPRESSION DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<
         
         "name" => "expr_mirconnect_q",
         "label" => "miRConnect-Q",
         "title" => "miRConnect-Q",
         "tiptext" => "miRConnect-Q: miRNA vs Genes expression data",
         "datapath" => "Expression/miRConnect-Q",
         "datatype" => "expr_mirconnect",
         "format" => "db_table",
         "owner" => "mirconnect",
         "downloads" => {
             "baseurl" => "ftp://genomics.dk/pub/miRConnect-Q",
         },
     },{
         "name" => "expr_mirconnect_l",
         "label" => "miRConnect-L",
         "title" => "miRConnect-L",
         "tiptext" => "miRConnect-L: miRNA vs Genes expression data",
         "datapath" => "Expression/miRConnect-L",
         "datatype" => "expr_mirconnect",
         "format" => "db_table",
         "owner" => "mirconnect",
         "downloads" => {
             "baseurl" => "ftp://genomics.dk/pub/miRConnect-L",
         },
     },{
         "name" => "expr_mirconnect_kirc",
         "label" => "miRConnect-KIRC",
         "title" => "miRConnect-KIRC",
         "tiptext" => "miRConnect-L: miRNA vs Genes expression data",
         "datapath" => "Expression/miRConnect-KIRC",
         "datatype" => "expr_mirconnect",
         "format" => "db_table",
         "owner" => "mirconnect",
         "downloads" => {
             "baseurl" => "ftp://genomics.dk/pub/miRConnect-KIRC",
         },
     },{
         "name" => "expr_mirconnect_gbm",
         "label" => "miRConnect-GBM",
         "title" => "miRConnect-GBM",
         "tiptext" => "miRConnect-GBM: miRNA vs Genes expression data",
         "datapath" => "Expression/miRConnect-GBM",
         "datatype" => "expr_mirconnect",
         "format" => "db_table",
         "owner" => "mirconnect",
         "downloads" => {
             "baseurl" => "ftp://genomics.dk/pub/miRConnect-GBM",
         },
     },{
         "name" => "expr_mirconnect_ovca",
         "label" => "miRConnect-OvCa",
         "title" => "miRConnect-OvCa",
         "tiptext" => "miRConnect-OvCa: miRNA vs Genes expression data",
         "datapath" => "Expression/miRConnect-OvCa",
         "datatype" => "expr_mirconnect",
         "format" => "db_table",
         "owner" => "mirconnect",
         "downloads" => {
             "baseurl" => "ftp://genomics.dk/pub/miRConnect-OvCa",
         },
     # },{
     #     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
         
     #     "name" => "funcs_go",
     #     "label" => "GO",
     #     "title" => "GO Functions",
     #     "tiptext" => "The Gene Ontology functions and components",
     #     "datapath" => "Functions/Ontology/GO",
     #     "datatype" => "go_func",
     #     "format" => "",
     #     "owner" => "bion",
     #     "downloads" => {
     #         "baseurl" => "ftp://ftp.geneontology.org/pub/go",
     #     }
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> GENOME DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<
        
         "name" => "pig_genome",
         "label" => "Pig genome",
         "title" => "Pig Genome",
         "tiptext" => "Pig Genome DNA downloaded from NCBI",
         "datapath" => "DNAs/Pig_genome",
         "datatype" => "dna_seq",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "ftp://ftp.ncbi.nih.gov/genomes/Sus_scrofa",
             "files" => [
                 {
                     "remote" => 'CHR_[01-18]/ssc_ref_Sscrofa10_chr[1-18].fa.gz',
                     "local" => "chr_#2.fasta.gz",
                 },{
                     "remote" => 'CHR_{MT,Un,X,Y}/ssc_ref_Sscrofa10_chr{MT,Un,X,Y}.fa.gz',
                     "local" => "chr_#1.fasta.gz",
                 }],
         }
     },{
         "name" => "human_genome",
         "label" => "Human genome",
         "title" => "Human Genome at NCBI",
         "tiptext" => "Human Genome DNA downloaded from NCBI",
         "datapath" => "DNAs/Human_genome",
         "datatype" => "dna_seq",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "ftp://ftp.ncbi.nih.gov/genomes/H_sapiens",
             "files" => [
                 {
                     "remote" => 'CHR_[01-22]/hs_alt_HuRef_chr[1-22].fa.gz',
                     "local" => "chr_#2.fasta.gz",
                 },{
                     "remote" => 'CHR_{MT,Un,X,Y}/hs_alt_HuRef_chr{MT,Un,X,Y}.fa.gz',
                     "local" => "chr_#2.fasta.gz",
                 }],
         }
     },{
         "name" => "mouse_genome",
         "label" => "Mouse genome",
         "title" => "Mouse Genome at NCBI",
         "tiptext" => "Mouse Genome DNA downloaded from NCBI",
         "datapath" => "DNAs/Mouse_genome",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "ftp://ftp.ncbi.nih.gov/genomes/M_musculus",
             "files" => [
                 {
                     "remote" => 'CHR_[01-19]/mm_ref_MGSCv*_chr[1-19].fa.gz',
                     "local" => "chr_#2.fa.gz",
                 },{
                     "remote" => 'CHR_{MT,Un,X,Y}/mm_ref_MGSCv*_chr{MT,Un,X,Y}.fa.gz',
                     "local" => "chr_#2.fa.gz",
                 }],
         }
     },{           
         "name" => "ebi_genomes_archaea",
         "label" => "EBI-Arch",
         "title" => "EBI Archaeal Genomes",
         "tiptext" => "Archaeal genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/archaea.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_archaealvirus",
         "label" => "EBI-A-Vir",
         "title" => "EBI Archaeal Virus Genomes",
         "tiptext" => "Archaeal virus genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/archaealvirus.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_bacteria",
         "label" => "EBI-Bact",
         "title" => "EBI Bacterial Genomes",
         "tiptext" => "Bacterial genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/bacteria.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_eukaryota",
         "label" => "EBI-Euks",
         "title" => "EBI Eukaryotic Genomes",
         "tiptext" => "Eukaryotic genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/eukaryota.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_organelle",
         "label" => "EBI-Orgnl",
         "title" => "EBI Organelle Genomes",
         "tiptext" => "Organelle genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/organelle.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_phage",
         "label" => "EBI-Phage",
         "title" => "EBI Phage Genomes",
         "tiptext" => "Phage genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/phage.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_plasmid",
         "label" => "EBI-Plas",
         "title" => "EBI Plasmid Genomes",
         "tiptext" => "Plasmid genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/plasmid.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_viroid",
         "label" => "EBI-Viroid",
         "title" => "EBI Viroid Genomes",
         "tiptext" => "Viroid genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/viroid.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     },{        
         "name" => "ebi_genomes_virus",
         "label" => "EBI-Virus",
         "title" => "EBI Virus Genomes",
         "tiptext" => "Virus genomes downloaded from EBI",
         "datapath" => "DNAs/EBI_genomes",
         "datatype" => "dna_geno",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "http://www.ebi.ac.uk/genomes/virus.html",
             "routine" => "Install::Download::ebi_genomes",
         },
         "imports" => {
             "hdr_regexp" => '^ENA\|([^\|]+)',
         }
     # },{        

     #     # >>>>>>>>>>>>>>>>>>>>>>>>>>> DNA SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

     #     "name" => "dna_seq_embl_local",
     #     "label" => "EMBL",
     #     "title" => "EMBL DNA",
     #     "tiptext" => "The EMBL DNA library, local mirror",
     #     "datapath" => "DNAs/EMBL",
     #     "datatype" => "dna_seq",
     #     "format" => "embl",
     #     "owner" => "bion",
     #     "downloads" => {
     #         "baseurl" => "ftp://ftp.ebi.ac.uk/pub/databases/embl",
     #     }
     # },{        
     #     "name" => "dna_seq_genbank",
     #     "label" => "GenBank",
     #     "title" => "NCBI DNA",
     #     "tiptext" => "The NCBI GenBank DNA library",
     #     "datapath" => "",
     #     "datatype" => "dna_seq",
     #     "format" => "blastn",
     #     "blastdbs" => "nr est gss sts htgs pat wgs",
     #     "owner" => "bion",
     },{

         # >>>>>>>>>>>>>>>>>>>>>>>>>>> RNA SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
         
         "name" => "rna_seq_mirbase",
         "label" => "miRBase",
         "title" => "miRNA sequences",
         "tiptext" => "miRNA sequences, compiled by Sam Griffith Jones",        
         "datapath" => "RNAs/miRBase",
         "format" => "fasta",
         "datatype" => "rna_seq",
         "owner" => "rnaport",
         "downloads" => {
             "baseurl" => "ftp://mirbase.org/pub/mirbase/CURRENT",
             "depth" => 2,
         },
         "imports" => {
             "files" => [
                 {
                     "title" => "miRNA precursors",
                     "infile" => "hairpin.fa.gz",
                     "outfile" => "precursors.fasta",
                     "hdr_regexp" => '^(\S+)\s+(\S+)\s+(.+)\s+(\S+) stem[- ]loop\s*$',
                 },{
                     "title" => "Mature miRNAs",
                     "infile" => "mature.fa.gz",
                     "outfile" => "mature.fasta",
                     "hdr_regexp" => '^(\S+)\s+(\S+)\s+(.+)\s+(\S+)$',
#                     "divide_regex" => '^([a-z0-9]+)-',
#                     "divide_files" => 'mature.$1.rna_seq.fasta',
                 },
             ],
             "hdr_fields" => {
                 "seq_id" => '$1',
                 "db_ids" => '$2',
                 "org_name" => '$3',
                 "mol_name" => '$4',
             },
         },
     },{
         "name" => "rna_seq_frnadb",
         "label" => "fRNAdb",
         "title" => "ncRNA sequences",
         "tiptext" => "Non-coding RNA sequences, compiled by T. Kin et al, Japan",        
         "datapath" => "RNAs/fRNAdb",
         "format" => "fasta",
         "datatype" => "rna_seq",
         "owner" => "rnaport",
         "downloads" => {
             "baseurl" => "http://www.ncrna.org/frnadb/files",
             "files" => [
                 { "remote" => "sequence.zip" },
                 ],
         },
         "imports" => {
             "files" => [
                 {
                     "infile" => "sequence.fasta",
                     "outfile" => "sequence.fasta",
                     "title" => "ncRNA sequences",
                 },
             ],
             "hdr_regexp" => '^([^\|]+)\|([^\|]*)\|(.*)$',
             "hdr_fields" => {
                 "seq_id" => '$1',
                 "db_ids" => '$2',
                 "mol_name" => '$3',
             },             
         },
     # },{
     #     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RNA ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<<<<<

     #     "name" => "rna_ali_srpdb",
     #     "label" => "SRPDB",
     #     "title" => "SRP RNA",
     #     "tiptext" => "SRP RNA alignment, by Christian Zwieb et al.",
     #     "datapath" => "RNAs/SRPDB",
     #     "datatype" => "rna_ali",
     #     "format" => "fasta",
     #     "owner" => "uthscsa",
     #     "downloads" => {
     #         "baseurl" => "http://rnp.uthscsa.edu/rnp/SRPDB",
     #         "files" => [
     #             { "remote" => "rna/alignment/fasta/srprna_ali.fasta" },
     #         ],
     #     },
     #     "imports" => {
     #         "files" => [
     #             {
     #                 "infile" => "srprna_ali.fasta",
     #                 "name" => "srprna",
     #                 "label" => "RNA",
     #                 "title" => "SRP RNA",
     #             },
     #         ],
     #     },
     #     "exports" => [
     #         { "datatype" => "rna_seq", "format" => "fasta", "merge" => 1 }
     #         ],
     # },{
     #     "name" => "rna_ali_tmrdb",
     #     "label" => "tmRDB",
     #     "title" => "tmRNP RNA",
     #     "tiptext" => "tmRNP RNA alignment, by Christian Zwieb et al.",
     #     "datapath" => "RNAs/tmRDB",
     #     "datatype" => "rna_ali", 
     #     "format" => "fasta",
     #     "owner" => "uthscsa",
     #     "downloads" => {
     #         "baseurl" => "http://rnp.uthscsa.edu/rnp/tmRDB",
     #         "files" => [
     #             { "remote" => "rna/alignment/fasta/tmrna_ali.fasta" },
     #         ],
     #     },
     #     "imports" => {
     #         "files" => [
     #             {
     #                 "infile" => "tmrna_ali.fasta",
     #                 "name" => "tmrna",
     #                 "label" => "RNA",
     #                 "title" => "tmRNA",
     #             },
     #         ],
     #     },
     #     "exports" => [
     #         { "datatype" => "rna_seq", "format" => "fasta", "merge" => 0 }
     #         ],
     # },{
     #     "name" => "rna_ali_telomdb",
     #     "label" => "telomDB",
     #     "title" => "Telomerase RNA",
     #     "tiptext" => "Telomerase RNA alignment, by Christian Zwieb et al.",
     #     "datapath" => "RNAs/telomDB",
     #     "datatype" => "rna_ali",
     #     "format" => "fasta",
     #     "owner" => "uthscsa",
     #     "downloads" => {
     #         "baseurl" => "http://rnp.uthscsa.edu/rnp/telomDB",
     #         "files" => [
     #             { "remote" => "rna/alignment/fasta/TR_ali.fasta" },
     #         ],
     #     },
     #     "imports" => {
     #         "files" => [
     #             {
     #                 "infile" => "TR_ali.fasta",
     #                 "name" => "telomrna",
     #                 "label" => "RNA",
     #                 "title" => "Telomerase RNA",
     #             },
     #         ],
     #     },
     #     "exports" => [
     #         { "datatype" => "rna_seq", "format" => "fasta", "merge" => 0 }
     #         ],
     },{
         "name" => "rna_ali_rfam",
         "label" => "Rfam",
         "title" => "Rfam alignments",
         "tiptext" => "RNA alignments, by the Sanger Institute",
         "datapath" => "RNAs/Rfam",
         "datatype" => "rna_ali",
         "format" => "stockholm",
         "owner" => "rnaport",
         "downloads" => {
             "baseurl" => "ftp://ftp.sanger.ac.uk/pub/databases/Rfam/CURRENT",
             "depth" => 1,
             "post_commands" => [
                 "ln -s -f __SRC_DIR__/Rfam.full.gz __SRC_DIR__/Rfam.stockholm.gz ",
             ],
         },
         "imports" => {
             "split_src" => 1,
             "params" => {
                 "skip_ids" => [ "SSU_rRNA_5", "5_8S_rRNA", "tRNA" ],
                 "split_sids" => '^(.+)/(\d+)-(\d+)$',
             },
         },
         "exports" => [
             { "datatype" => "rna_seq", "format" => "fasta", "merge" => 1 }
             ],
     },{
         "name" => "rna_seq_green",
         "label" => "GreenGenes",
         "title" => "SSU RNA",
         "tiptext" => "SSU RNA alignment, by the GreenGenes project",        
         "datapath" => "RNAs/Greengenes",
         "datatype" => "rna_seq",
         "format" => "fasta",
         "owner" => "rrna",
         "downloads" => {
             "baseurl" => "http://greengenes.secondgenome.com/downloads/database/12_10",
             "files" => [
                 {
                     "remote" => "gg_12_10_taxonomy.txt.gz",
                     "local" => "gg_12_10_taxonomy.txt.gz",
                 },
                 {
                     "remote" => "gg_12_10_genbank.map.gz",
                     "local" => "gg_12_10_genbank.map.gz",
                 },
                 {
                     "remote" => "gg_12_10.fasta.gz",
                     "local" => "gg_12_10.fasta.gz",
                 },
                 ],
             #"post_commands" => [
             #    "gunzip __SRC_DIR__/*.gz",
             #],
         },
         "imports" => {
             "routine" => "Install::Import::create_green_seqs_wrap",
             # "files" => [
             #     {
             #         "in_regexp" => "sequences_16S_all_gg_2011_1_unaligned.fasta",
             #         "outfile" => "SSU_ALL.rna_seq.fasta",
             #         "label" => "SSU seqs",
             #         "title" => "SSU sequences",
             #     }],
             # "hdr_regexp" => '^([^ ]+)\s+\S+\s+(.+)$',
             # "hdr_fields" => {
             #     "seq_id" => '$1',
             #     "org_taxon" => '$2',
             # },
         },
     },{
         "name" => "rna_seq_rdp",
         "label" => "RDP",
         "title" => "SSU RNA sequences",
         "tiptext" => "SSU RNA classification sequences, by the RDP project",        
         "datapath" => "RNAs/RDP",
         "datatype" => "rna_seq",
         "format" => "fasta",
         "owner" => "rnaport",
         "downloads" => {
             "baseurl" => "http://rdp.cme.msu.edu/misc/resources.jsp",
             "files" => [
                 { "remote" => 'release\d+_\d+_unaligned.gb' },
                 { "remote" => 'release\d+_\d+_arch_aligned.fa.gz' },
                 { "remote" => 'release\d+_\d+_bact_aligned.fa.gz' },
                 ],
             #"post_commands" => [
             #    "seq_convert __SRC_DIR__/*.gb.gz --oformat fasta --osuffix .fasta",
             #],
         },
         "imports" => {
             "routine" => "Install::Import::create_rdp_sub_seqs_wrap",
             # "files" => [
             #     {
             #         "in_regexp" => 'release\d+_\d+_unaligned.gb.gz.fasta', 
             #         "outfile" => "SSU_ALL.rna_seq.fasta",
             #         "title" => "SSU all sequences",
             #         "hdr_fields" => { "mol_name" => "SSU RNA" },
             #     }],
             # "hdr_regexp" => '^([^ ]+).+?org_taxon=(.+)$',
             # "hdr_fields" => {
             #     "seq_id" => '$1',
             #     "org_taxon" => '$2',
             # },
             #"post_commands" => [
             #    "export_datasets rdp --silent --clobber",
             #],
         },
     },{
         "name" => "rna_seq_silva",
         "label" => "Silva",
         "title" => "SSU + LSU RNA sequences",
         "tiptext" => "SSU and LSU RNA classification sequences, by the Silva project",        
         "datapath" => "RNAs/Silva",
         "datatype" => "rna_seq",
         "format" => "fasta",
         "owner" => "rnaport",
         "downloads" => {
             "baseurl" => "http://www.arb-silva.de/no_cache/download/archive/current/Exports",
             "files" => [
                 # { "remote" => 'SSURef_\d+_tax_silva_trunc' },
                 # { "remote" => 'LSURef_\d+_tax_silva_trunc' },
                 { "remote" => 'SSURef_\d+_tax_silva_full_align_trunc' },
                 { "remote" => 'LSURef_\d+_tax_silva_full_align_trunc' },
                 ],
         },
         "imports" => {
             "routine" => "Install::Import::create_silva_sub_seqs_wrap",
         },
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RNA PATTERNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
         
         "name" => "rna_pat_mirna",
         "label" => "MirPat",
         "title" => "miRNA Patterns",
         "tiptext" => "Patterns auto-extracted from the miRNA alignments in Rfam",
         "datapath" => "RNAs/MirPat",
         "datatype" => "rna_pat",
         "format" => "patscan",
         "owner" => "rnaport",
         "downloads" => {
             "baseurl" => "ftp://genomics.dk/pub/mir-patterns",
         },
     },{
         
         # >>>>>>>>>>>>>>>>>>>>>>>>> PROTEIN SEQUENCE DATA <<<<<<<<<<<<<<<<<<<<<<<
         
         "name" => "prot_seq_refseq",
         "label" => "RefSeq",
         "title" => "RefSeq proteins",
         "tiptext" => "The NCBI RefSeq protein sequence library, local install",
         "datapath" => "Proteins/Refseq",
         "datatype" => "prot_seq",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "ftp://ftp.ncbi.nih.gov/refseq",
         },
#            "url" => "ftp://genomics.dk/pub/refseq-small",
#            "url" => "ftp://genomics.dk/pub/refseq-medium",
     },{
         "name" => "prot_seq_uniprot",
         "label" => "UniProt",
         "title" => "UniProt proteins",
         "tiptext" => "The UniProt protein sequence library, local install",
         "datapath" => "Proteins/UniProt",
         "datatype" => "prot_seq",
         "format" => "fasta",
         "owner" => "bion",
         "downloads" => {
             "baseurl" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release",
         },
     },{
         "name" => "prot_seq_ncbi",
         "label" => "GenPept",
         "title" => "NCBI proteins",
         "tiptext" => "The combined NCBI protein libraries",
         "blastdbs" => "nr",
         "datatype" => "prot_seq",
         "format" => "",
         "format" => "blastp",
         "owner" => "bion",
     # },{
     #     # >>>>>>>>>>>>>>>>>>>>>>>>>> PROTEIN ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<
         
     #     "name" => "prot_ali_srpdb",
     #     "label" => "SRP",
     #     "title" => "SRP proteins",
     #     "tiptext" => "SRP protein alignments, by Christian Zwieb et al.",
     #     "datapath" => "Proteins/SRPDB",
     #     "datatype" => "prot_ali",
     #     "format" => "fasta",
     #     "owner" => "uthscsa",
     #     "downloads" => {
     #         "baseurl" => "http://rnp.uthscsa.edu/rnp/SRPDB/protein",
     #         "files" => [
     #             {
     #                 "remote" => 'srp{9,14,19,21,54,68,72}/alignment/fasta/srp{9,14,19,21,54,68,72}_ali.fasta',
     #                 "local" => "srp#2_ali.fasta",
     #             }, 
     #             { "remote" => 'cpsrp43/alignment/fasta/cpsrp43_ali.fasta' },
     #             { "remote" => 'flhf/alignment/fasta/flhf_ali.fasta' },
     #             { "remote" => 'sralpha/alignment/fasta/sra_ali.fasta' },
     #             { "remote" => 'srbeta/alignment/fasta/srb_ali.fasta' },
     #             ],
     #     },
     #     "imports" => {
     #         "files" => [
     #             { "infile" => "srp9_ali.fasta", "name" => "srp9", "label" => " 9 ", "title" => "SRP 9" },
     #             { "infile" => "srp14_ali.fasta", "name" => "srp14", "label" => " 14 ", "title" => "SRP 14" },
     #             { "infile" => "srp19_ali.fasta", "name" => "srp19", "label" => " 19 ", "title" => "SRP 19" },
     #             { "infile" => "srp21_ali.fasta", "name" => "srp21", "label" => " 21 ", "title" => "SRP 21" },
     #             { "infile" => "srp54_ali.fasta", "name" => "srp54", "label" => " 54 ", "title" => "SRP 54" },
     #             { "infile" => "srp68_ali.fasta", "name" => "srp68", "label" => " 68 ", "title" => "SRP 68" },
     #             { "infile" => "srp72_ali.fasta", "name" => "srp72", "label" => " 72 ", "title" => "SRP 72" },
     #             { "infile" => "cpsrp43_ali.fasta", "name" => "cpsrp43", "label" => " CP 43 ", "title" => "cp SRP 43" },
     #             { "infile" => "flhf_ali.fasta", "name" => "flhf", "label" => " Flhf ", "title" => "Flhf" },
     #             { "infile" => "sra_ali.fasta", "name" => "sra", "label" => " SRa ", "title" => "SR alpha" },
     #             { "infile" => "srb_ali.fasta", "name" => "srb", "label" => " SRb ", "title" => "SR beta" },
     #         ],
     #     },
     #     "exports" => [
     #         { "datatype" => "prot_seq", "format" => "fasta", "merge" => 1 }
     #         ],
     # },{
     #     "name" => "prot_ali_tmrdb",
     #     "label" => "tmRNP",
     #     "title" => "tmRNP proteins",
     #     "tiptext" => "tmRNP protein alignments, by Christian Zwieb et al.",
     #     "datapath" => "Proteins/tmRDB",
     #     "datatype" => "prot_ali",
     #     "format" => "fasta",
     #     "owner" => "uthscsa",
     #     "downloads" => {
     #         "baseurl" => "http://rnp.uthscsa.edu/rnp/tmRDB",
     #         "files" => [
     #             { "remote" => 'peptide/alignment/fasta/peptide_ali.fasta' },
     #             { "remote" => 'protein/smpb/alignment/fasta/smpb_ali.fasta' },
     #             { "remote" => 'protein/rps1/alignment/fasta/rps1_ali.fasta' },
     #             { "remote" => 'protein/alatrsyn/alignment/fasta/alatrsyn_ali.fasta' },
     #             { "remote" => 'protein/eftu/alignment/fasta/eftu_ali.fasta' },
     #         ],                 
     #     },
     #     "imports" => {
     #         "files" => [
     #             { "infile" => "peptide_ali.fasta", "name" => "peptide", "label" => "Tag-pep", "title" => "Tag peptides" },
     #             { "infile" => "smpb_ali.fasta", "name" => "smpb", "label" => "SmpB", "title" => "SmpB" },
     #             { "infile" => "rps1_ali.fasta", "name" => "rps1", "label" => "S1", "title" => "rProtein S1" },
     #             { "infile" => "alatrsyn_ali.fasta", "name" => "alatrsyn", "label" => "Ala-tRNA-S", "title" => "Ala-tRNA Synthetase" },
     #             { "infile" => "eftu_ali.fasta", "name" => "eftu", "label" => "EFTu", "title" => "EFTu" },
     #             ],
     #     },
     #     "exports" => [
     #         { "datatype" => "prot_seq", "format" => "fasta", "merge" => 1 }
     #         ],
#      },{
#          "name" => "word_edict",
#          "label" => "Edict",
#          "title" => "Edict net dictionary",
#          "tiptext" => "Extracts from the WordNet lexical database",
#          "datapath" => "Edict",
#          "datatype" => "words_list",
#          "format" => "comma_table",
#          "owner" => "communico",
#          "downloads" => {
#              "url" => "ftp://genomics.dk/pub/CommuniCo/Edict",
#          },
#      },{
#          "name" => "word_wikipedia",
#          "label" => "Wikipedia",
#          "title" => "Wikipedia net encyclopedia",
#          "tiptext" => "The Wikipedia online encyclopedia, english version",
#          "datapath" => "Wikipedia",
#          "datatype" => "words_text",
#          "format" => "text_xml",
#          "owner" => "communico",
#          "downloads" => {
#              "url" => "ftp://genomics.dk/pub/CommuniCo/Wikipedia",
#          },
     });

&dump( \@descriptions );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    # Niels Larsen, April 2007.

    # Returns the above list with "datapath" field added, and defaults added
    # to undefined fields.

    # Returns a list.

    my ( $elem );

    foreach $elem ( @descriptions )
    {
        $elem->{"css"} = "" if not exists $elem->{"css"};

        if ( $elem->{"datapath"} )
        {
            $elem->{"datadir"} = &File::Basename::basename( $elem->{"datapath"} );
            $elem->{"datapath_full"} = "$Common::Config::dat_dir/$elem->{'datapath'}";

	    if ( $elem->{"exports"} ) {
		$elem->{"merge_prefix"} = "ALL_DATA";
	    }
        }
        else
        {
            $elem->{"datadir"} = "";
            $elem->{"datapath_full"} = "";
        }
    }

    return wantarray ? @descriptions : \@descriptions ;
}

1;

__END__

     },{
         "name" => "rna_seq_green",
         "label" => "GreenGenes",
         "title" => "SSU RNA",
         "tiptext" => "SSU RNA alignment, by the GreenGenes project",        
         "datapath" => "RNAs/Greengenes",
         "datatype" => "rna_seq",
         "format" => "fasta",
         "owner" => "rrna",
         "downloads" => {
             "baseurl" => "http://www.secondgenome.com/go/2011-greengenes-taxonomy",
             "files" => [
                 {
                     "remote" => "sequences_16S_all_gg_2011_1_unaligned\.fasta",
                     "local" => "sequences_16S_all_gg_2011_1_unaligned.fasta.gz",
                 },
             ],
             #"post_commands" => [
             #    "gunzip __SRC_DIR__/*.gz",
             #],
         },
         "imports" => {
             "routine" => "Install::Import::create_green_seqs_wrap",
             # "files" => [
             #     {
             #         "in_regexp" => "sequences_16S_all_gg_2011_1_unaligned.fasta",
             #         "outfile" => "SSU_ALL.rna_seq.fasta",
             #         "label" => "SSU seqs",
             #         "title" => "SSU sequences",
             #     }],
             # "hdr_regexp" => '^([^ ]+)\s+\S+\s+(.+)$',
             # "hdr_fields" => {
             #     "seq_id" => '$1',
             #     "org_taxon" => '$2',
             # },
         },

    },{
        "name" => "orgs_taxa_hugenholtz",
        "label" => "Hugenholtz",
        "title" => "Hugenholtz taxonomy",
        "tiptext" => "SSU based organism taxonomy curated by Phil Hugenholtz",
        "datadir" => "Hugenholtz",
        "datatype" => "orgs_taxa",
        "format" => "greengenes_tax",
        "owner" => "rrna",
        "downloads" => {
            "url" => "http://greengenes.lbl.gov/Download/Taxonomic_Outlines/Hugenholtz_SeqDescByOTU_tax_outline.txt",
        },
    },{
        "name" => "orgs_taxa_ludwig",
        "label" => "Ludwig",
        "title" => "Ludwig taxonomy",
        "tiptext" => "SSU based organism taxonomy maintained by Wolfgang Ludwig",
        "datadir" => "Ludwig",
        "datatype" => "orgs_taxa",
        "format" => "greengenes_tax",
        "owner" => "rrna",
        "downloads" => {
            "url" => "http://greengenes.lbl.gov/Download/Taxonomic_Outlines/Ludwig_SeqDescByOTU_tax_outline.txt",
        },
    },{
        "name" => "orgs_taxa_pace",
        "label" => "Pace",
        "title" => "Pace Taxonomy",
        "tiptext" => "SSU based organism taxonomy maintained by Norman Pace et al.",
        "datadir" => "Pace",
        "datatype" => "orgs_taxa",
        "format" => "greengenes_tax",
        "owner" => "rrna",
        "downloads" => {
            "url" => "http://greengenes.lbl.gov/Download/Taxonomic_Outlines/Pace_SeqDescByOTU_tax_outline.txt",
        },
    },{
        "name" => "orgs_taxa_rdp",
        "label" => "RDP",
        "title" => "RDP taxonomy",
        "tiptext" => "SSU based organism taxonomy maintained by the Ribosomal Database Project",
        "datadir" => "RDP",
        "datatype" => "orgs_taxa",
        "format" => "greengenes_tax",
        "owner" => "rrna",
        "downloads" => {
            "url" => "http://greengenes.lbl.gov/Download/Taxonomic_Outlines/RDP_SeqDescByOTU_tax_outline.txt",
        },
    },{        
        "name" => "dna_seq_genbank_local",
        "label" => "GenBank",
        "title" => "NCBI DNA",
        "tiptext" => "The NCBI GenBank DNA library, local mirror",
        "datadir" => "GenBank",
        "datatype" => "dna_seq",
        "format" => "genbank",
        "owner" => "bion",
        "downloads" => {
#            "url" => "ftp://ftp.ncbi.nlm.nih.gov/genbank",
            "url" => "ftp://genomics.dk/pub/genbank-small",
#            "url" => "ftp://genomics.dk/pub/genbank-medium",
        },

    },{
        "name" => "dna_seq_cache",
        "label" => "DNA-cache",
        "title" => "DNA sequence cache",
        "tiptext" => "Local versions of select EMBL/GenBank/DDBJ DNA data library entries",
        "datadir" => "Cache",
        "datatype" => "dna_seq",
        "format" => "genbank",
        "owner" => "bion",
        "downloads" => {},
    },{
        "name" => "dna_seq_embl_release",
        "label" => "EMBL",
        "title" => "EMBL data release",
        "tiptext" => "The EMBL genome and DNA data library",
        "datadir" => "EMBL/Release",
        "datatype" => "dna_seq",
        "format" => "embl",
        "owner" => "bion",
        "downloads" => {
            "url" => "ftp://ftp.ebi.ac.uk/pub/databases/embl/release",
        },
    },{
        "name" => "dna_seq_embl_updates",
        "label" => "EMBL-new",
        "title" => "EMBL data updates",
        "tiptext" => "The EMBL genome and DNA data library, daily updates",
        "datadir" => "EMBL/Updates",
        "datatype" => "dna_seq",
        "format" => "embl",
        "owner" => "bion",
        "downloads" => {
            "url" => "ftp://ftp.ebi.ac.uk/pub/databases/embl/new",
        },

        "name" => "rna_seq_ssu_embl",
        "label" => "SSU-seqs",
        "title" => "SSU RNA sequences",
        "tiptext" => "SSU RNA sequences, extracted from EMBL by Danish Genome Institute",        
        "datadir" => "SSU_EMBL",
        "datatype" => "rna_seq",
        "format" => "embl",
        "owner" => "rrna",
        "downloads" => {
            "url" => "ftp://genomics.dk/pub/SSU_RNA/Database_tables",
        },
    },{

        "name" => "rna_ali_ssu_ludwig",
        "label" => "Ludwig",
        "title" => "SSU RNA",
        "tiptext" => "SSU RNA alignment, by Wolfgang Ludwig",        
        "datadir" => "SSU_Ludwig",
        "datatype" => "rna_ali",
        "format" => "fasta",
        "owner" => "rrna",
    },{
        "name" => "rna_ali_ssu_pace",
        "label" => "Pace",
        "title" => "SSU RNA",
        "tiptext" => "SSU RNA alignment, by Norman Pace et al.",        
        "datadir" => "SSU_Pace",
        "datatype" => "rna_ali",
        "format" => "fasta",
        "owner" => "rrna",
    },{
        "name" => "rna_ali_ssu_rdp",
        "label" => "RDP",
        "title" => "SSU RNA",
        "tiptext" => "SSU RNA alignment, by the Ribosomal Database Project",        
        "datadir" => "SSU_RDP",
        "datatype" => "rna_ali",
        "format" => "stockholm",
        "owner" => "rrna",
    },{

        "name" => "rna_ali_mir_flanks",
        "label" => "mir-flanks",
        "title" => "Mir alignments, with flanking features",
        "datadir" => "mir_flanks",
        "datatype" => "rna_ali",
        "format" => "stockholm",
        "owner" => "rnaport",
    },{

        "name" => "prot_seq_uniprot",
        "label" => "UniProt",
        "title" => "UniProt data release",
        "tiptext" => "UniProt protein sequences, by the UniProt consortium",
        "datadir" => "UniProt/Release",
        "datatype" => "prot_seq",
        "format" => "",
        "owner" => "bion",
        "downloads" => {
            "url" => "ftp://ftp.ebi.ac.uk/pub/databases/uniprot/knowledgebase",
        },
#     },{
#         "name" => "prot_seq_uniprot",
#         "label" => "UniProt-new",
#         "title" => "UniProt data updates",
#         "tiptext" => "UniProt protein sequences, by the UniProt consortium",
#         "datadir" => "UniProt/Updates",
#         "datatype" => "prot_seq",
#         "format" => "",
#         "owner" => "bion",
#         "downloads" => {
#             "url" => "ftp://ftp.ebi.ac.uk/pub/databases/uniprot/knowledgebase",
#         },

# Uniprot
# -------

#  uniprot_release = ftp://ftp.ebi.ac.uk/pub/databases/uniprot/knowledgebase
#  uniprot_updates = ftp://ftp.ebi.ac.uk/pub/databases/swissprot/updates_compressed

# SSU RNA
# -------
#
# Alignments,

#  ssu_rna_belgium = http://www.psb.ugent.be/rRNA/ssu
#  ssu_rna_greengenes = http://greengenes.lbl.gov/Download/Sequence_Data/Fasta_data_files
#  ssu_rna_rdp = http://rdp.cme.msu.edu/misc/resources.jsp

# Annotated sequences,  (not connected to the alignments yet)

#  ssu_rna_embl = ftp://genomics.dk/pub/SSU_RNA/Database_tables

# LSU RNA
# -------

#  lsu_rna_belgium = http://www.psb.ugent.be/rRNA/lsu

# Rfam, miRBase
# -------------
#  rfam_release = ftp://ftp.sanger.ac.uk/pub/databases/Rfam
##   rfam_release = ftp://ftp.genetics.wustl.edu/pub/eddy/Rfam

#  mirbase_release = ftp://ftp.sanger.ac.uk/pub/mirbase/sequences/CURRENT

# Pfam
# ----

#  pfam_release = ftp://ftp.sanger.ac.uk/pub/databases/Pfam/current_release

# SRP, tmRNP
# ----------

#  srp_zwieb_release = http://psyche.uthscsa.edu/dbs/SRPDB
#  tmrnp_zwieb_release = http://psyche.uthscsa.edu/dbs/tmRDB
