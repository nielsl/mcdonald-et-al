package Data::Registry::Features;            # -*- perl -*-

# Descriptions of all features known to the system. 

use strict;
use warnings FATAL => qw ( all );

my @descriptions =
    ({
        # >>>>>>>>>>>>>>>>>>>>>>>>>> ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        "name" => "ali_nuc_color_dots",
        "title" => "Base color dots", 
        "description" => "Changes the default display to color dots that give a good"
                       . " impression of base conservation patterns.",
        "dbtypes" => [ "rna_ali", "dna_ali" ],
        "viewers" => [ "array_viewer" ],    
     },{
         "name" => "ali_prot_color_dots",
         "title" => "Res. color dots", 
         "description" => qq (Changes the default display to color dots that give a good)
                        . qq ( impression of residue conservation patterns.),
         "dbtypes" => [ "prot_ali" ],
         "viewers" => [ "array_viewer" ],    
     },{
         "name" => "ali_seq_cons",
         "title" => "Seq. conservation",
         "description" => "Highlights highly conserved columns, with mouse-over information.",
         "dbtypes" => [ "rna_ali", "dna_ali", "prot_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_seq_cons",
             "min_score" => 60,
             "max_score" => 100,
         },
         "display" => {
             "style" => {
                 "bgcolor" => [ "#3366cc", "#cccccc" ],
                 "bgtrans" => 90,
             },
             "min_pix_per_col" => 3,
             "min_score" => 60,
             "max_score" => 100,
         },
     },{
         "name" => "ali_seq_match",
         "title" => "Seq. similarities",
         "description" => "Highlights residues similar to those in a chosen reference sequence.",
         "dbtypes" => [ "rna_ali", "dna_ali", "prot_ali" ],
         "viewers" => [ "array_viewer" ],
         "display" => {
             "style" => {
                 "bgcolor" => [ "#3366cc", "#cccccc" ],
                 "bgtrans" => 80,
             },
             "min_pix_per_col" => 3,
         },
     },{
         "name" => "ali_prot_hydro",
         "title" => "Res. hydrophobicity",
         "description" => "Highlights amino acids according to hydrophobicity.",
         "dbtypes" => [ "prot_ali" ],
         "viewers" => [ "array_viewer" ],
     },{
         "name" => "ali_rna_pairs",
         "title" => "Base pairings",
         "description" => "RNA pairings are shown in symmetric color shades, with mouse-over information.",
         "dbtypes" => [ "rna_ali", "dna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_rna_pairs",
         },
         "display" => {
             "style" => {
                 "bgtrans" => 95,
             },
         },
     },{
         "name" => "ali_pairs_covar",
         "title" => "Base covariations",
         "description" => "Single-column RNA/DNA base covariations are highlighted, with mouse-over information.",
         "dbtypes" => [ "rna_ali", "dna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_pairs_covar",
             "min_score" => 0.20,
         },
         "display" => {
             "style" => {
                 "bgcolor" => [ "#00ff00", "#ccffcc" ],
                 "bgtrans" => 60,
             },
             "min_pix_per_col" => 3,
             "min_score" => 0.20,
         },
     },{
         "name" => "ali_sid_text",
         "title" => "Short-ID tooltips",
         "description" => qq (Activates mouse-over information on the left margin text labels. This increases the page size and may slow their update.),
         "dbtypes" => [ "rna_ali", "dna_ali", "prot_ali" ],
         "viewers" => [ "array_viewer" ],
         "selectable" => 0,
         "imports" => {
             "routine" => "create_features_sid_text",
         },
         "display" => {
             "min_pix_per_row" => 7,
         },
     },{
         "name" => "ali_sim_match",
         "title" => "Match regions",
         "description" => qq (Shows the regions of subject sequences that match a query sequence.),
         "dbtypes" => [ "rna_ali", "dna_ali", "prot_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_sims",
         },
         "display" => {
             "style" => {
                 "bgcolor" => [ "#cccccc", "#3366cc" ],
                 "bgtrans" => 98,
             },
             "min_pix_per_col" => 3,
         },
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>> MIRNA RELATED <<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "ali_mirna_hairpins",
         "title" => "miRNA-like hairpins",
         "description" => qq (Shows where there RNALfold finds miRNA-like hairpins.),
         "dbtypes" => [ "rna_ali", "dna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_mirna_hairpin",
         },
         "display" => {
             "style" => {
                 "bgcolor" => [ "#9999ff", "#333399" ],
                 "bgtrans" => 100,
             },
             "min_pix_per_col" => 3,
         },
     },{
         "name" => "ali_mirna_mature",
         "title" => "miRNA matches (mature)",
         "description" => qq (Shows matches with mature miRNAs from miRBase.),
         "dbtypes" => [ "rna_ali", "dna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_mirna_mature",
         },
         "display" => {
             "style" => {
                 "bgcolor" => "#ff0000",
                 "bgtrans" => 99,
             },
             "min_pix_per_col" => 3,
         },
     },{
         "name" => "ali_mirna_patterns",
         "title" => "miRNA patterns (precursors)",
         "description" => qq (Shows matches with sequence and pairing patterns extracted from miRNA alignments in Rfam.),
         "dbtypes" => [ "rna_ali", "dna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_mirna_patterns",
         },
         "display" => {
             "style" => {
                 "bgcolor" => [ "#99cc99", "#003300" ],
                 "bgtrans" => 100,
             },
             "min_pix_per_col" => 3,
         },
     },{
         "name" => "ali_mirna_precursor",
         "title" => "miRNA matches (precursors)",
         "description" => qq (Shows matches with precursor miRNAs from miRBase.),
         "dbtypes" => [ "rna_ali", "dna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_mirna_precursor",
         },
         "display" => {
             "style" => {
                 "bgcolor" => "#aaaaaa",
                 "bgtrans" => 98,
             },
             "min_pix_per_col" => 3,
         },

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<

     },{
         "name" => "seq_pattern",
         "title" => "Sequence patterns",
         "description" => "blabla",
         "dbtypes" => [ "rna_ali", "dna_ali", "prot_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_patterns",
             "min_score" => 25,
         },
         "display" => {
             "style" => {
                 "bgcolor" => [ "#bbccbb", "#006600" ],
                 "bgtrans" => 70,
             },
             "min_score" => 25,
         },
     },{
         "name" => "seq_precursor",
         "title" => "Precursor sequence",
         "description" => "blabla",
         "dbtypes" => [ "rna_ali", "dna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_precursor",
         },
         "display" => {
             "style" => {
                 "bgcolor" => "#666666",
                 "bgtrans" => 98,
             },
         },
     },{
         "name" => "seq_mature",
         "title" => "Mature sequence",
         "description" => "blabla",
         "dbtypes" => [ "rna_ali", "dna_ali", "prot_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_mature",
         },
         "display" => {
             "style" => {
                 "bgcolor" => "#ff0000",
                 "bgtrans" => 90,
             },
         },
     },{
         "name" => "seq_rnafold",
         "title" => "Folding potential",
         "description" => "blabla",
         "dbtypes" => [ "rna_ali" ],
         "viewers" => [ "array_viewer" ],
         "imports" => {
             "routine" => "create_features_rnafold",
         },
         "display" => {
             "style" => {
                 "bgcolor" => [ "#bbbbcc", "#000099" ],
                 "bgtrans" => 80,
             },
         },
     });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    # Niels Larsen, April 2007.

    # Returns the above list with defaults added to certain fields
    # if undefined.

    # Returns a list.

    my ( $elem );

    foreach $elem ( @descriptions )
    {
        $elem->{"selectable"} = 1 if not defined $elem->{"selectable"};
        $elem->{"selected"} = 0 if not defined $elem->{"selected"};

        $elem->{"datatype"} = "boolean" if not defined $elem->{"datatype"};

        if ( $elem->{"datatype"} eq "boolean" and not $elem->{"choices"} )
        {
            $elem->{"choices"} = [{
                "name" => 1,
                "title" => "Yes",
            },{
                "name" => 0,
                "title" => "No",
            }],
        }

        $elem->{"imports"}->{"routine"} //= "";

        $elem->{"display"}->{"min_pix_per_col"} //= 1;
        $elem->{"display"}->{"min_pix_per_row"} //= 1;
        $elem->{"display"}->{"css"} //= "menu_item";
    }

    return wantarray ? @descriptions : \@descriptions ;
}

1;

__END__

