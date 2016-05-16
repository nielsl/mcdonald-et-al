package Software::Registry::Methods;            # -*- perl -*-

# A list of all methods that the system understands. The decriptions
# of parameters have been moved to Params.pm because different methods 
# often take the same parameters; their default values are still here
# because they usually differ between methods.

use strict;
use warnings FATAL => qw ( all );

our $out_max = '999999999';         # blast wont take much more

my @descriptions = (
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> MUSCLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "muscle",
        "title" => "Align (muscle)",
        "inputs" => [
            {
                "types" => [ "dna_seq", "rna_seq", "prot_seq" ],
                "formats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "dna_seq", "rna_seq", "prot_seq" ],
                "formats" => [ "fasta" ],
            }],                
        "min_entries" => 2,
        "params" => {
            "name" => "muscle_params",
            "values" => [
                [ "-diags", 0 ],
                [ "-maxiters", 2 ],
                [ "-maxhours", 0.5 ],
                [ "-maxmb", 200 ],
                [ "-stable", 0 ],
                ],
        },
        "window_height" => 500,
        "window_width" => 500,
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>> STACKED_ALIGN <<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "stacked_align",
        "title" => "Align (stacked)",
        "inputs" => [
            {
                "types" => [ "dna_seq", "rna_seq", "prot_seq" ],
                "formats" => [ "blast_xml" ],
            }],
        "outputs" => [
            {
                "types" => [ "dna_seq", "rna_seq", "prot_seq" ],
                "formats" => [ "fasta" ],
            }],                
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>> STACKED_APPEND <<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "stacked_append",
        "title" => "Append sequences",
        "inputs" => [
            {
                "types" => [ "dna_seq", "rna_seq", "prot_seq" ],
                "formats" => [ "blast_xml" ],
            }],
        "outputs" => [
            {
                "types" => [ "dna_seq", "rna_seq", "prot_seq" ],
                "formats" => [ "fasta" ],
            }],                
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> NSIMSCAN <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "nsimscan",
        "title" => "Simscan",
        "description" => "DNA/RNA sequence similarity search",
        "credits" => "Denis Kaznadzey et al.",
        "inputs" => [
            {
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "fasta" ],
            },{
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "matches_simscan" ],
                "formats" => [ "simscan_table" ],
            }],
#        "params" => {
#            "name" => "simscan_params",
#             "values" => [
#                 [ "--minlen", 7 ],
#                 [ "--minpct", 50 ],
#                 [ "--wordlen", 7 ],
#                 [ "--noids", 1 ],
#                 [ "--reverse", 0 ],
#                 [ "--silent", 1 ],
#                 [ "--outlen", $out_max ],
#                 ],
#             "window_height" => 500,
#             "window_width" => 500,
#        },
        "cmdline" => "nsimscan __PARAMETERS__ __INPUT__ __DATASET__ __OUTPUT__",
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PSIMSCAN <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "psimscan",
        "title" => "Simscan",
        "description" => "Protein sequence similarity search",
        "credits" => "Denis Kaznadzey et al.",
        "inputs" => [
            {
                "types" => [ "prot_seq" ],
                "formats" => [ "fasta" ],
            },{
                "types" => [ "prot_seq" ],
                "formats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "matches_simscan" ],
                "formats" => [ "simscan_table" ],
            }],
        "cmdline" => "psimscan __PARAMETERS__ __INPUT__ __DATASET__ __OUTPUT__",
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SIMRANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "simrank",
        "title" => "Simrank",
        "credits" => "Niels Larsen, Danish Genome Institute",
        "inputs" => [
            {
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "fasta" ],
            },{
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "simrank" ],
                "iformats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "matches_simrank" ],
                "formats" => [ "simrank_table" ],
            }],
        "params" => {
            "name" => "simrank_params",
            "values" => [
                [ "--minlen", 7 ],
                [ "--minpct", 50 ],
                [ "--wordlen", 7 ],
                [ "--noids", 1 ],
                [ "--reverse", 0 ],
                [ "--silent", 1 ],
                [ "--outlen", $out_max ],
                ],
            "window_height" => 500,
            "window_width" => 500,
        },
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BLASTN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "blastn",
        "title" => "Blastn (dna/rna)",
        "credits" => "National Library of Medicine, U.S.A.",
        "inputs" => [
            {
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "fasta" ],
            },{
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "blastn" ],
                "iformats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "blast_xml" ],
            }],                
        "pre_params" => {
            "name" => "pre_params",
            "values" => [
                [ "use_latest_sims", 0 ],
                ],
        },
        "params" => {
            "name" => "blast_params",
            "values" => [
                [ "-e", 10 ],
                [ "-q", -2 ],
                [ "-r", 1 ],
                [ "-G", 2 ],
                [ "-E", -1 ],
                [ "-S", 3 ],
                [ "-F", "F" ],
                [ "-W", 7 ],
                [ "-f", 0 ],
                [ "-g", "T" ],
                [ "-m", 7 ],
                [ "-n", "F" ],
                [ "-v", $out_max ],
                [ "-b", $out_max ],
                ],
        },
        "post_params" => {
            "name" => "post_params",
            "values" => [
                [ "with_condense", 1 ],
                [ "sort_sims", "by_score" ],
                [ "align_method", "stacked_append" ],
                [ "flank_left", 200 ],
                [ "flank_right", 200 ],
                ],
        },
        "window_height" => 900,
        "window_width" => 550,
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TBLASTN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "tblastn",
        "title" => "Tblastn (dna/rna)",
        "credits" => "National Library of Medicine, U.S.A.",
        "inputs" => [
            {
                "types" => [ "prot_seq" ],
                "formats" => [ "fasta" ],
            },{
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "blastn" ],
                "iformats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "prot_seq" ],
                "formats" => [ "blast_xml" ],
            }],                
        "pre_params" => {
            "name" => "pre_params",
            "values" => [
                [ "use_latest_sims", 0 ],
                ],
         },
        "params" => {
            "name" => "blast_params",
            "values" => [
                [ "-e", 10 ],
                [ "-G", 2 ],
                [ "-E", -1 ],
                [ "-S", 3 ],
                [ "-F", "F" ],
                [ "-W", 7 ],
                [ "-f", 13 ],
                [ "-g", "T" ],
                [ "-m", 7 ],
                [ "-n", "F" ],
                [ "-v", $out_max ],
                [ "-b", $out_max ],
                ],
        },
        "post_params" => {
            "name" => "post_params",
            "values" => [
                [ "with_condense", 1 ],
                [ "align_method", "stacked_append" ],
                [ "flank_left", 200 ],
                [ "flank_right", 200 ],
                ],
        },
        "window_height" => 900,
        "window_width" => 550,
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BLASTX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "blastx",
        "title" => "Blastx (protein)",
        "credits" => "National Library of Medicine, U.S.A.",
        "inputs" => [
            {
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "fasta" ],
            },{
                "types" => [ "prot_seq" ],
                "formats" => [ "blastp" ],
                "iformats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "dna_seq", "rna_seq" ],
                "formats" => [ "blast_xml" ],
            }],                
        "pre_params" => {
            "name" => "pre_params",
            "values" => [
                [ "use_latest_sims", 0 ],
                ],
         },
        "params" => {
            "name" => "blast_params",
            "values" => [
                [ "-e", 1 ],
                [ "-G", -1 ],
                [ "-E", -1 ],
                [ "-F", "F" ],
                [ "-W", 3 ],
                [ "-f", 12 ],
                [ "-g", "T" ],
                [ "-m", 7 ],
                [ "-n", "F" ],
                [ "-v", $out_max ],
                [ "-b", $out_max ],
                ],
        },
        "post_params" => {
            "name" => "post_params",
            "values" => [
                [ "with_condense", 1 ],
                [ "align_method", "stacked_append" ],
                [ "flank_left", 200 ],
                [ "flank_right", 200 ],
                ],
        },
        "window_height" => 900,
        "window_width" => 500,
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BLASTP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "blastp",
        "title" => "Blastp (protein)",
        "credits" => "National Library of Medicine, U.S.A.",
        "inputs" => [
            {
                "types" => [ "prot_seq" ],
                "formats" => [ "fasta" ],
            },{
                "types" => [ "prot_seq" ],
                "formats" => [ "blastp" ],
                "iformats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "prot_seq" ],
                "formats" => [ "blast_xml" ],
            }],                
        "pre_params" => {
            "name" => "pre_params",
            "values" => [
                [ "use_latest_sims", 0 ],
                ],
        },
        "params" => {
            "name" => "blast_params",
            "values" => [
                [ "-e", 1 ],
                [ "-G", -3 ],
                [ "-E", -1 ],
                [ "-F", "F" ],
                [ "-W", 3 ],
                [ "-f", 11 ],
                [ "-g", "T" ],
                [ "-m", 7 ],
                [ "-n", "F" ],
                [ "-v", $out_max ],
                [ "-b", $out_max ],
                ],
        },
        "post_params" => {
            "name" => "post_params",
            "values" => [
                [ "with_condense", 1 ],
                [ "sort_sims", "by_score" ],
                [ "align_method", "stacked_append" ],
                [ "flank_left", 200 ],
                [ "flank_right", 200 ],
                ],
        },
        "window_height" => 800,
        "window_width" => 550,
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> BLASTALIGN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "blastalign",
        "title" => "Align (BlastAlign)",
        "credits" => "Robert Belshaw and Aris Katzourakis, Oxford",
        "inputs" => [
            {
                "types" => [ "dna_seq" ],
                "formats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "dna_seq" ],
                "formats" => [ "fasta" ],
            }],                
        "min_entries" => 2,
        "params" => {
            "name" => "blastalign_params",
            "values" => [
                [ "-m", 0.95 ],
                ],
        },
        "window_height" => 500,
        "window_width" => 500,
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PATSCAN_NUC <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "patscan_nuc",
        "title" => "Patscan (dna/rna)",
        "description" => "DNA/RNA sequence pattern match",
        "inputs" => [
            {
                "types" => [ "rna_pat", "dna_pat" ],
                "formats" => [ "patscan" ],
            },{
                "types" => [ "rna_seq", "dna_seq" ],
                "formats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "rna_seq", "dna_seq" ],
                "formats" => [ "fasta" ],
            }],
        "pre_params" => {
            "name" => "pre_params",
            "values" => [
                [ "use_latest_sims", 0 ],
                ],
         },
         "params" => {
            "name" => "patscan_params",
            "values" => [
                [ "-c", 1 ],
                [ "-m", 99999 ],
                ],
        },
        "post_params" => {
            "name" => "post_params",
            "values" => [
                [ "flank_left", 200 ],
                [ "flank_right", 200 ],
                [ "align_method", "stacked_append" ],
                ],
         },
        "window_height" => 600,
        "window_width" => 500,
        "cmdline" => "patscan __PARAMETERS__ __INPUT__ < __DATASET__ > __OUTPUT__",
    },{
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PATSCAN_PROT <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "patscan_prot",
        "title" => "Patscan (protein)",
        "description" => "Protein sequence pattern match",
        "inputs" => [
            {
                "types" => [ "prot_pat" ],
                "formats" => [ "patscan" ],
            },{
                "types" => [ "prot_seq" ],
                "formats" => [ "fasta" ],
            }],
        "outputs" => [
            {
                "types" => [ "prot_seq" ],
                "formats" => [ "fasta" ],
            }],
        "pre_params" => {
            "name" => "pre_params",
            "values" => [
                [ "use_latest_sims", 0 ],
                ],
        },
        "params" => {
            "name" => "patscan_params",
            "window_height" => 600,
            "window_width" => 500,
            "values" => [
                [ "-m", 99999 ],
                ],
         },
         "post_params" => {
             "name" => "post_params",
             "values" => [
                 [ "flank_left", 200 ],
                 [ "flank_right", 200 ],
                 [ "align_method", "stacked_append" ],
                 ],
         },
         "window_height" => 600,
         "window_width" => 500,
         "cmdline" => "patscan -p __PARAMETERS__ __INPUT__ < __DATASET__ > __OUTPUT__",
     });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    return wantarray ? @descriptions : \@descriptions ;
}
    
1;

__END__

#     },{
#         "name" => "mir_blast",
#         "title" => "Mir-blast vs DNA",
#         "itypes" => [ "dna_seq", "rna_seq" ],
#         "dbitypes" => [ "dna_seq", "rna_seq" ],
#         "otypes" => [ "dna_seq", "rna_seq" ],
#         "dbiformat" => "fasta",
#         "dbformat" => "blastn",
#         "iformat" => "fasta",
#         "oformat" => "blast_xml",
#         "pre_params" => {
#             "name" => "pre_params",
#             "values" => [
#                 [ "use_latest_sims", 0 ],
#                 ],
#          },
#         "params" => {
#             "name" => "blast_params",
#             "values" => [
#                 [ "-e", 50 ],
#                 [ "-q", -2 ],
#                 [ "-r", 1 ],
#                 [ "-G", 1 ],
#                 [ "-E", -1 ],
#                 [ "-S", 3 ],
#                 [ "-F", "F" ],
#                 [ "-W", 7 ],
#                 [ "-f", 0 ],
#                 [ "-g", "T" ],
#                 [ "-m", 7 ],
#                 [ "-n", "F" ],
#                 [ "-v", $out_max ],
#                 [ "-b", $out_max ],
#                 ],
#         },
#         "post_params" => {
#             "name" => "post_params",
#             "values" => [
#                 [ "flank_left", 2000 ],
#                 [ "flank_right", 2000 ],
#                 [ "mirna_hairpins", "T" ],
#                 [ "mirna_mature", "T" ],
#                 [ "mirna_patterns", "T" ],
#                 [ "align_method", "stacked_append" ],
#                 [ "flank_left", 200 ],
#                 [ "flank_right", 200 ],
#                 ],
#         },
#         "window_height" => 850,
#         "window_width" => 550,

# sub viewers
# {
#     # Niels Larsen, October 2005.
    
#     # Returns a list of the viewers that the system understands.
    
#     # Returns a list reference. 
    
#     my ( @list );

#     @list = ({
#         "title" => "Organism Taxa",
#         "name" => "orgs_viewer",
#         "inputs" => [ "orgs_taxa", "col_stats", "col_sims" ],
#     });

#     return wantarray ? @list : \@list;
# }


#         "name" => "simrank",
#         "title" => "Simrank",
#         "dbiformat" => "fasta",
#         "dbformat" => "simrank",
#         "dbitypes" => [ "rna_seq", "dna_seq" ],
#         "itypes" => [ "rna_seq", "dna_seq" ],
#         "otype" => "matches_simrank",
#         "iformat" => "fasta",
#         "oformat" => "simrank_table",
#         "params" => {
#             "name" => "simrank_params",
#             "window_height" => 500,
#             "window_width" => 500,
#             "values" => [
#                 [ "--minlen", 7 ],
#                 [ "--minpct", 50 ],
#                 [ "--wordlen", 7 ],
#                 [ "--noids", 1 ],
#                 [ "--reverse", 0 ],
#                 [ "--silent", 1 ],
#                 [ "--outlen", $out_max ],
#                 ],
#         },
#      },{


                
#      },{
#          "name" => "pfold",
#          "title" => "Pfold prediction",
#          "credits" => "Bjarne Knudsen and Jotun Hein",
#          "itypes" => [ "dna_seq", "dna_ali", "rna_seq", "rna_ali" ],
#          "otype" => "",
#          "iformat" => "fasta",
#          "oformat" => "col",
#      },{
#          "name" => "megablast",
#          "title" => "Megablast",
#          "dbiformat" => "fasta",
#          "dbformat" => "blastn",
#          "itypes" => [ "rna_seq", "dna_seq" ],
#          "otype" => "matches_blast",
#          "iformat" => "fasta",
#          "oformat" => "blast_table",
