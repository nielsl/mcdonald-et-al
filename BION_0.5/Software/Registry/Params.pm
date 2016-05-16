package Software::Registry::Params;            # -*- perl -*-

# Definitions of the user-visible parameters for each method and 
# viewer. The default values are given with the methods and viewers,
# see Registry::Methods and Registry::Viewers.

use strict;
use warnings FATAL => qw ( all );

my @descriptions =
    ({
        # >>>>>>>>>>>>>>>>>>>>>>> ARRAY VIEWER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "array_viewer_params",
        "title" => "Preferences",
        "description" => "",
        "citation" => "Niels Larsen, Danish Genome Institute, Unpublished",
        "values" => [
            {
                "name" => "ali_img_width",
                "datatype" => "integer",
                "title" => "Image width (pixels)", 
                "description" => 
                    qq (Sets the image width to the given number of pixels; a high number will)
                  . qq ( show the whole image. Caution: if used as default, then large images may)
                  . qq ( overwhelm the browser.),
            },{
                "name" => "ali_img_height",
                "datatype" => "integer",
                "title" => "Image height (pixels)", 
                "description" => 
                    qq (Sets the image height to the given number of pixels; a high number will)
                  . qq ( show the whole image. Caution: if used as default, then large images may)
                  . qq ( overwhelm the browser.),
            },{
                "name" => "ali_zoom_pct",
                "datatype" => "integer",
                "title" => "Image zoom percentage", 
                "description" => 
                    qq (Determines how much the view is zoomed in or out when the zoom buttons)
                  . qq (are pressed.),
            },{
                "name" => "ali_with_border",
                "datatype" => "boolean",
                "title" => "With image border", 
                "description" => qq (Toggles the showing of a one-pixel wide border around the image.),
            },{
                "name" => "ali_with_sids",
                "datatype" => "boolean",
                "title" => "With margin titles", 
                "description" => "Toggles the showing of short-id sequence title labels on both sides of the data.",
            },{
                "name" => "ali_with_nums",
                "datatype" => "boolean",
                "title" => "With margin numbers", 
                "description" => "Toggles the showing of sequence numbering on both sides of the data.",
            },{
                "name" => "ali_with_col_collapse",
                "datatype" => "boolean",
                "title" => "Hide empty columns", 
                "description" => qq (Hides columns without data.),
            },{
                "name" => "ali_with_row_collapse",
                "datatype" => "boolean",
                "title" => "Hide empty rows", 
                "description" => qq (Hides rows without data.),
                "selectable" => 0,
            }],
     },{
         
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SIMRANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "simrank_params",
        "title" => "Simrank parameters",
        "citation" => "Niels Larsen, Danish Genome Institute, Unpublished",
        "description" =>
            qq (Quick and crude calculation of similarity between a set of RNA/DNA)
          . qq ( sequences and a (perhaps large), set of similar ones. Similarities between)
          . qq ( any two sequences are the number of unique short subsequences that they)
          . qq ( share, divided by the smallest total number in either. As opposed to)
          . qq ( blast it ranks a short good match higher than a longer less good one.),
        "values" => [
            {
                "name" => "--wordlen",
                "datatype" => "integer",
                "title" => "Word length",
                "description" => "Word length of database sequences.",
                "selectable" => 0,
            },{
                "name" => "--minlen",
                "datatype" => "integer",
                "title" => "Min. length",
                "description" => "Minimum length of database sequence to used for comparison.",
            },{
                "name" => "--minpct",
                "datatype" => "integer",
                "title" => "Min. percent", 
                "description" => "Minimum match percentage.",
            },{
                "name" => "--reverse",
                "datatype" => "boolean",
                "title" => "Complement", 
                "description" => "Complements input sequence(s).",
                "selectable" => 0,
            },{
                "name" => "--noids",
                "datatype" => "boolean",
                "title" => "No ids", 
                "description" => "Whether to output row indices rather than short ids.",
                "visible" => 0,
            },{
                "name" => "--silent",
                "datatype" => "boolean",
                "title" => "Silent", 
                "description" => "Whether to produce screen messages.",
                "visible" => 0,
            },{
                "name" => "--outlen",
                "datatype" => "integer",
                "title" => "Output length", 
                "description" => "Maximum number of matches in the output. It is set here to infinite.",
                "selectable" => 0,
            }],
     },{
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BLAST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        "name" => "blast_params",
        "title" => "Blast parameters",
        "description" =>
            qq (National Library of Medicine, U.S.A., created the underlying program)
          . qq ( and runs it as a free service that this system uses.),
        "citation" =>
            qq (Altschul, Stephen F., Thomas L. Madden, Alejandro A. Schaffer, Jinghui Zhang,)
          . qq ( Zheng Zhang, Webb Miller, and David J. Lipman (1997), \"Gapped BLAST and)
          . qq ( PSI-BLAST: a new generation of protein database search programs\", Nucleic)
          . qq ( Acids Res. 25:3389-3402.),
        "url" => "http://www.ncbi.nlm.nih.gov/BLAST",
        "values" => [
            {
                "name" => "-b",
                "datatype" => "integer",
                "title" => "Output alignments",
                "description" => "Maximum number of alignments in the output. It is set here to infinite.",
                "selectable" => 0,
            },{
                "name" => "-E",
                "datatype" => "integer",
                "title" => "Gap ext. score",
                "description" => "Penalty for extending gaps.",
            },{
                "name" => "-e",
                "datatype" => "real",
                "title" => "Expectation value",
                "description" => "Loose e-value.",
            },{
                "name" => "-F",
                "datatype" => "boolean",
                "title" => "Filter query", 
                "description" => "Filter query sequence (DUST with blastn, SEG with others).",
                "choices" => [
                    {
                        "name" => "T",
                        "title" => "Yes",
                    },{
                        "name" => "F",
                        "title" => "No",
                    }],
            },{
                "name" => "-f",
                "datatype" => "integer",
                "title" => "Extension threshold",
                "description" => "Threshold for extending hits.",
                "selectable" => 0,
            },{
                "name" => "-G",
                "datatype" => "integer",
                "title" => "Gap open score",
                "description" => "Penalty for opening a gap.",
            },{
                "name" => "-g",
                "datatype" => "boolean",
                "title" => "Gapped alignment",
                "description" => "Perform gapped alignment.",
                "choices" => [
                    {
                        "name" => "T",
                        "title" => "Yes",
                    },{
                        "name" => "F",
                        "title" => "No",
                    }],
                "selectable" => 0,
            },{
                "name" => "-m",
                "datatype" => "integer",            
                "title" => "Output format",
                "description" => "Output format: 0 for pairwise, 7 for XML, 8 for tabular.",
                "visible" => 0,
            },{
                "name" => "-n",
                "datatype" => "boolean",
                "title" => "Megablast off",
                "description" => "Make sure megablast is off.",
                "visible" => 0,
            },{
                "name" => "-q",
                "datatype" => "integer",
                "title" => "Mismatch score",
                "description" => "Penalty for mismatch.",
            },{
                "name" => "-r",
                "datatype" => "integer",
                "title" => "Match score",
                "description" => "Reward for match.",
            },{
                "name" => "-S",
                "datatype" => "boolean",
                "title" => "Search strand(s)",
                "description" => "Search both strands.",
                "choices" => [
                    {
                        "name" => 1,
                        "title" => "Top",
                    },{
                        "name" => 2,
                        "title" => "Bottom",
                    },{
                        "name" => 3,
                        "title" => "Both", 
                    }],
            },{
                "name" => "-v",
                "datatype" => "integer",
                "title" => "# of descriptions",
                "description" => "Number of description lines.",
                "selectable" => 0,
                "visible" => 0,
            },{
                "name" => "-W",
                "datatype" => "integer",
                "title" => "Word size",
                "description" => "Default word size.",
                "selectable" => 0,
            }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>> BLASTALIGN <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
         "name" => "blastalign_params",
         "title" => "BlastAlign parameters",
         "description" =>
             qq (Creates an alignment of the matches generated by blast when all sequences)
           . qq ( are matched against all in a given set of nucleotide sequences. The sequence)
           . qq ( parts that do not match are not shown.),
         "citation" =>
             qq (Belshaw, R., and Katzourakis, A. (2005), \"BlastAlign: a program that uses)
           . qq ( blast to align problematic nucleotide sequences\", Bioinformatics 21:122-123.),
         "url" => "http://evolve.zoo.ox.ac.uk/software.html?id=blastalign",
         "values" => [
             {
                 "name" => "-m",
                 "datatype" => "real",
                 "title" => "Maximum gap proportion",
                 "description" => "Maximum proportion of gaps allowed in any one sequence in the final alignment.",
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>> MUSCLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
         
         "name" => "muscle_params",
         "title" => "Muscle parameters",
         "description" => qq (Creates an alignment from a set of sequences.),
         "citation" =>
            qq (Edgar, R.C. (2004), \"MUSCLE: multiple sequence alignment with high accuracy)
          . qq ( and high throughput\", Nucleic Acids Research 32(5):1792-1797.),
         "url" => "http://www.drive5.com/muscle/download3.6.html",
         "values" => [
             {
                 "name" => "-diags",
                 "datatype" => "boolean",
                 "title" => "Diagonals",
                 "description" => "Find diagonals (faster for similar sequences).",
             },{
                 "name" => "-maxiters",
                 "datatype" => "integer",
                 "title" => "Iterations",
                 "description" => "Maximum number of iterations.",
             },{
                 "name" => "-maxhours",
                 "datatype" => "real",
                 "title" => "Max. hours",
                 "description" => "Maximum number of run-time in hours.",
                 "selectable" => 0,
             },{
                 "name" => "-maxmb",
                 "datatype" => "integer",
                 "title" => "Max. memory",
                 "description" => "Maximum memory to allocate in Mb.",
                 "selectable" => 0,
             },{
                 "name" => "-stable",
                 "datatype" => "boolean",
                 "title" => "Seq. order",
                 "description" => "Sequence ordering in the output.",
                 "choices" => [
                     {
                         "name" => 1,
                         "title" => "as in input",
                     },{
                         "name" => 0,
                         "title" => "by similarity",
                     }],
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>> PATSCAN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "patscan_params",
         "title" => "Patscan parameters",
         "description" =>
              qq (Written mostly by Ross Overbeek, with help from David Joerg and)
            . qq ( Morgan Price, and inspired by tools from David Searls.),
         "citation" =>
              qq (Mark DeSouza, Niels Larsen and Ross Overbeek (1997). Searching for patterns)
            . qq ( in genomic data. Trends Genet. Dec 13 (12): 497-498.),
         "url" => "http://www-unix.mcs.anl.gov/compbio/PatScan/HTML/patscan.html",
         "values" => [
             {
                 "name" => "-c",
                 "datatype" => "boolean",
                 "title" => "Both strands",
                 "description" => "Searches both strands.",
                 "selectable" => 1,
             },{
                 "name" => "-m",
                 "datatype" => "integer",
                 "title" => "Max. matches",
                 "description" => "Stops after reaching this number of matches.",
                 "selectable" => 1,
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>> PRE-PROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "pre_params",
         "title" => "Pre-settings",
         "description" => qq (Assorted parameters for pre-processing.),
         "values" => [
             {
                 "name" => "use_latest_sims",
                 "title" => "Reuse similarities",
                 "description" => 
                     "Whether to reuse the similarities from the last run of this dataset, thereby"
                    ." skipping a new and perhaps lengthy similarity search. Leaving the switch on (yes)"
                    ." will not cause an error, a similarity search will be launched if there are no"
                    ." previous results.",
                 "datatype" => "boolean",
                 "visible" => 1,
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>> POST-PROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "post_params",
         "title" => "Post-analysis parameters",
         "description" => qq (An assorted bunch of parameters for post-processing. They may be split.),
         "values" => [
             {
                 "name" => "with_condense",
                 "title" => "Condense",
                 "description" => "Whether to collapse similarities as much as possible, so the alignment size is minimized.",
                 "datatype" => "boolean",
                 "visible" => 0,
             },{
                 "name" => "flank_left",
                 "title" => "Left flank length",
                 "description" => "The number of non-matching bases that are included to the left of the match.",
                 "datatype" => "integer",
             },{
                 "name" => "flank_right",
                 "title" => "Right flank length",
                 "description" => "The number of non-matching bases that are included to the right of the match.",
                 "datatype" => "integer",
             },{
                 "name" => "align_method",
                 "title" => "Re-align",
                 "description" => 
                     "Whether or how to align the sub-sequences found by a similarity search against each other,"
                    ." instead of them all being mapped to the query. Alignment methods that show both matching,"
                    ." and non-matching sequences are marked (full), those that only show matches are marked (partial).",
                    "datatype" => "boolean",
                    "choices" => [
                        {
                            "name" => "stacked_align",
                            "title" => "No, keep matches, flanks align (maybe slow)",
                        },{
                            "name" => "stacked_append",
                            "title" => "No, keep matches, flanks dangle (faster)",
                        },{
                            "name" => "muscle",
                            "title" => "Yes, align match regions with muscle",
                        },{
                            "name" => "blastalign",
                            "title" => "Yes, align match regions with blastalign",
                        }],
             },{
                 "name" => "align_flanks_method",
                 "title" => "Align flanks",
                 "description" => 
                     "Whether to align the sequences adjacent to the matching sub-sequences found by a similarity"
                    ." search, and which method to use. Choosing none will center the flank sequences around the"
                    ." match regions. Some methods show only the parts that match (partial), others"
                    ." preserve all data and numbering (full).",
                    "datatype" => "boolean",
                    "choices" => [
                        {
                            "name" => "stacked",
                            "title" => "none (full)",
                        },{
                            "name" => "muscle",
                            "title" => "muscle (full)",
                        },{
                            "name" => "blastalign",
                            "title" => "blast (partial)",
                        }],
             },{
                 "name" => "sort_sims",
                 "title" => "Sort",
                 "description" => "Whether to sort blast similarities by organism or by score.",
                 "datatype" => "boolean",
                 "choices" => [
                     {
                         "name" => "by_score",
                         "title" => "matches by score",
                     },{
                         "name" => "by_organism",
                         "title" => "matches by organism",
                     }],
             },{
                 "name" => "merge_flanks",
                 "datatype" => "boolean",
                 "title" => "Merge flanks",
                 "description" => 
                     "Whether to show aligned or unaligned flank sequences as direct continuations"
                    ." of the matching sub-sequences, or to show them spaced away separately at the margins.",
             },{
                 "name" => "mirna_hairpins",
                 "title" => "miRNA-like hairpins",
                 "description" => qq (Shows where there RNALfold finds miRNA-like hairpins.),
                 "datatype" => "boolean",
             },{
                 "name" => "mirna_mature",
                 "title" => "miRNA matches",
                 "description" => qq (Shows matches with mature miRNAs from miRBase.),
                 "datatype" => "boolean",
             },{
                 "name" => "mirna_patterns",
                 "title" => "miRNA patterns",
                 "description" => qq (Shows matches with sequence and pairing patterns extracted from miRNA precursor alignments in Rfam.),
                 "datatype" => "boolean",
             }],
     });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    # Niels Larsen, April 2007.

    # Sets selectable and visible flags to true where they are not defined.

    # Returns a list. 

    my ( $hash, $key, $opt );

    foreach $hash ( @descriptions )
    {
        foreach $opt ( @{ $hash->{"values"} } )
        {
            $opt->{"selectable"} = 1 if not exists $opt->{"selectable"};
            $opt->{"visible"} = 1 if not exists $opt->{"visible"};

            if ( $opt->{"datatype"} eq "boolean" and not $opt->{"choices"} )
            {
                $opt->{"choices"} = [{
                    "name" => 1,
                    "title" => "Yes",
                },{
                    "name" => 0,
                    "title" => "No",
                }],
            }
        }
    }

    return wantarray ? @descriptions : \@descriptions ;
}    

1;

__END__



  -Q  Query Genetic code to use [Integer]
    default = 1
  -D  DB Genetic code (for tblast[nx] only) [Integer]
    default = 1
  -M  Matrix [String]
    default = BLOSUM62
  -W  Word size, default if zero (blastn 11, megablast 28, all others 3) [Integer]
    default = 0
  -K  Number of best hits from a region to keep (off by default, if used a value of 100 is recommended) [Integer]
    default = 0
  -S  Query strands to search against database (for blast[nx], and tblastx)
       3 is both, 1 is top, 2 is bottom [Integer]
    default = 3




  -Z  X dropoff value for final gapped alignment in bits (0.0 invokes default behavior)
      blastn/megablast 50, tblastx 0, all others 25 [Integer]
    default = 0
  -R  PSI-TBLASTN checkpoint file [File In]  Optional
  -n  MegaBlast search [T/F]
    default = F
  -L  Location on query sequence [String]  Optional
  -A  Multiple Hits window size, default if zero (blastn/megablast 0, all others 40 [Integer]
    default = 0
  -w  Frame shift penalty (OOF algorithm for blastx) [Integer]
    default = 0
  -t  Length of the largest intron allowed in a translated nucleotide sequence when linking multiple distinct alignments. (0 invokes default behavior; a negative value disables linking.) [Integer]
    default = 0
  -B  Number of concatenated queries, for blastn and tblastn [Integer]  Optional
    default = 0
  -V  Force use of the legacy BLAST engine [T/F]  Optional
    default = F
  -C  Use composition-based statistics for blastpgp or tblastn:
      As first character:
      D or d: default (equivalent to F)
      0 or F or f: no composition-based statistics
      1 or T or t: Composition-based statistics as in NAR 29:2994-3005, 2001
      2: Composition-based score adjustment as in Bioinformatics 21:902-911,
          2005, conditioned on sequence properties
      3: Composition-based score adjustment as in Bioinformatics 21:902-911,
          2005, unconditionally
      For programs other than tblastn, must either be absent or be D, F or 0.
           As second character, if first character is equivalent to 1, 2, or 3:
      U or u: unified p-value combining alignment p-value and compositional p-value in round 1 only
 [String]
    default = D
  -s  Compute locally optimal Smith-Waterman alignments (This option is only
      available for gapped tblastn.) [T/F]
    default = F
