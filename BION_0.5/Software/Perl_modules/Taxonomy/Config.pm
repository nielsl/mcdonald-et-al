package Taxonomy::Config;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Taxonomy names and configurations that do not change very often. 
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Messages;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &edit_subseq_template
                 &subseq_template
                 );

my ( $db, $dbname, $mol, $moldb, $seq_file, $name, $tax_file, $prefix );

our %DBs;
our %Defs;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

%DBs = (
    "RDP" => {
        "SSU" => ( bless {
            "prefix" => "RDP_",
            "bact_id" => "S000629954",   # Escherichia coli str. K12 substr. W3110;
            "arch_id" => "S001020552",   # Escherichia coli; _J01695 aligned with archaea
            "lengths" => [ 1000, 1250, 1400, 1 ],
            "src_dir" => "$Common::Config::dat_dir/RNAs/RDP/Sources",
            "out_dir" => "$Common::Config::dat_dir/RNAs/RDP/Installs",
        }),
    },
    "Silva" => {
        "SSU" => ( bless {
            "prefix" => "Silva_",
            "ref_id" => "AP009048.223771.225312",    # Escherichia coli str. K-12 substr. W3110
            "lengths" => [ 1000, 1250, 1400, 1 ],
            "src_dir" => "$Common::Config::dat_dir/RNAs/Silva/Sources",
            "out_dir" => "$Common::Config::dat_dir/RNAs/Silva/Installs",
        }),
        "LSU" => ( bless {
            "prefix" => "Silva_",
            "ref_id" => "AP009048.225759.228662",    # Escherichia coli str. K-12 substr. W3110
            "lengths" => [ 2000, 2500, 1 ],
            "src_dir" => "$Common::Config::dat_dir/RNAs/Silva/Sources",
            "out_dir" => "$Common::Config::dat_dir/RNAs/Silva/Installs",
        }),
    },
    "Green" => {
        "SSU" => ( bless {
            "prefix" => "Green_",
            "src_dir" => "$Common::Config::dat_dir/RNAs/Greengenes/Sources",
            "out_dir" => "$Common::Config::dat_dir/RNAs/Greengenes/Installs",
        }),
    });

# Defaults,

%Defs = (
    "seq_suffix" => ".rna_seq.fasta",
    "tab_suffix" => "_all.tax.table",
    "dbm_suffix" => ".dbm",
    "ref_suffix" => ".ref_seq.fasta",
    );

# Add keys common to all,

foreach $dbname ( keys %DBs )
{
    $db = $DBs{ $dbname };

    foreach $mol ( keys %{ $db } )
    {
        $moldb = $db->{ $mol };

        $moldb->{"ref_mol"} = $mol;

        $moldb->{"seq_suffix"} = $Defs{"seq_suffix"};
        $moldb->{"tab_suffix"} = $Defs{"tab_suffix"};
        $moldb->{"dbm_suffix"} = $Defs{"dbm_suffix"};
        $moldb->{"ref_suffix"} = $Defs{"ref_suffix"};
    }    
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Create DB_files with paths to fasta and taxonomy tables,

our %DB_files;

foreach $dbname ( keys %DBs )
{
    $db = $DBs{ $dbname };

    foreach $mol ( keys %{ $db } )
    {
        $moldb = $db->{ $mol };
        $prefix = $moldb->{"prefix"};

        if ( -d $moldb->{"out_dir"} )
        {
            foreach $seq_file ( @{ &Common::File::list_files( $moldb->{"out_dir"}, $moldb->{"seq_suffix"} .'$' ) } )
            {
                $name = $seq_file->{"name"};
                $name =~ s/$moldb->{"seq_suffix"}$//;
                
                $DB_files{ $name } = $seq_file->{"path"};
            }
        }
    }
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our @DB_names;

@DB_names = sort keys %DB_files;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub edit_subseq_template
{
    # Niels Larsen, September 2012.

    # Helper routine that absolutifies file paths, edits other fields and 
    # adds some that are good for the routines. Returns an updated recipe.

    my ( $rcp,    # Recipe
         $conf,    # Reference info
        ) = @_;

    # Returns a hash.

    my ( $odir, $refmol, $prefix, $suffix, $step, $beg, $end, $minlen );

    $refmol = $rcp->{"reference-molecule"};

    $odir = $conf->{"out_dir"};
    $prefix = $conf->{"prefix"};
    $suffix = $conf->{"seq_suffix"};
    
    foreach $step ( @{ $rcp->{"steps"} } )
    {
        $beg = $step->{"from-position"};
        $end = $step->{"to-position"};

        if ( defined $beg and defined $end )
        {
            delete $step->{"from-position"};
            delete $step->{"to-position"};
            
            # Set output file path,
            
            $step->{"out-file"} = "$odir/$prefix$refmol"."_". $beg ."-". $end . $suffix;
            
            # Change positions if primer sequence not included,
            
            if ( $step->{"include-primer"} eq "no" )
            {
                $beg += length $step->{"forward-primer"};
                $end -= length $step->{"reverse-primer"};
            }
            
            $step->{"ref-beg"} = $beg;
            $step->{"ref-end"} = $end;

            $step->{"region"} = 1;
        }
        elsif ( $minlen = $step->{"minimum-length"} )
        {
            if ( $minlen eq "all" ) {
                $step->{"out-file"} = "$odir/$prefix$refmol"."_all$suffix";
            } else {
                $step->{"out-file"} = "$odir/$prefix$refmol"."_minlen_$minlen$suffix";
            }

            $step->{"region"} = 0;
        }            
    }

    return $rcp;
}

sub subseq_template
{
    # Niels Larsen, September 2012.

    # Returns recipe-formatted text that describe which alignment slices
    # should be written by default. 

    my ( $conf,
        ) = @_;
    
    # Returns a string.
    
    my ( $text, $dbname, $dbid, $refmol, $refid, $len );

    $dbname = $conf->{"prefix"};
    $dbname =~ s/[^A-Za-z]$//;

    $dbid = lc $dbname;
    $refmol = $conf->{"ref_mol"};

    $text = qq (
#
# Recipe for amplicon sub-sequence extraction
# -------------------------------------------
# 
# This is our default amplicon extractions from $dbname. Primers 
# missing below can be added and unused primers deleted. With editing
# done, run 
# 
# install_data $dbid --nodownload
#
# and after one hour or so there will be files in the $dbname/Installs
# directory. They can be referred to from workflow recipes by stating 
# their file name prefixes, e.g. 
# 
);

    $text .= "# $dbname" ."_". $refmol ."_341-806";
    $text .= qq (
#
# The reference sequence is E.coli K12, sub-strain W3110. Between
# E. coli strains there is nearly no difference in sequence length,
# 1-2 bases at most.
#
# NOTE: always specify the start of the forward primer and the end 
# of the reverse primer as positions, i.e. the longest range. If
# the keyword "include-primer" is set to "no" (the default) then the
# program will substract the lengths of the primers and cut out the
# region that does not include them.

<recipe>

   reference-molecule = $refmol

   # >>>>>>>>>>>>>>>>>>>>>>> LONGER AMPLICONS <<<<<<<<<<<<<<<<<<<<<<<<<

   # The following primers are good for 454 sequencing. See World J 
   # Gastroenterol 2010 September 7; 16(33): 4135-4144. ISSN 1007-9327,
   # for a good discussion of 454 primers. They conclude: "347F/803R 
   # is the most suitable pair of primers for classification of foregut
   # 16S rRNA genes but also possess universality suitable for analyses
   # of other complex microbiomes".

   <sequence-region>
       title = Variable domain 1-2
       forward-primer = CCTAACACATGCAAGTCG
       reverse-primer = TACGGGAGGCAGCAG
       from-position = 44
       to-position = 380
       minimum-length = 10
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 1-3
       forward-primer = AGAGTTTGATCCTGGCTCAG
       reverse-primer = ATTAGATACCCNNGTAGTCC
       from-position = 7
       to-position = 534
       minimum-length = 200
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 1-3
       forward-primer = GCCTAACACATGCAAGTC
       reverse-primer = CCAGCAGCCGCGGTAAT
       from-position = 30
       to-position = 550
       minimum-length = 200
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 1-3
       forward-primer = GCCTAACACATGCAAGTC
       reverse-primer = CCAGCAGCCGCGGTAAT
       from-position = 44
       to-position = 534
       minimum-length = 200
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 2-4
       forward-primer = TACGGRAGGCAGCAG
       reverse-primer = AGGGTATCTAATCCT
       from-position = 341
       to-position = 806
       minimum-length = 200
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 2-5
       forward-primer = CCTACGGGDGGCWGCA
       reverse-primer = CTGACGACRRCCRTGCA
       from-position = 341
       to-position = 1068
       minimum-length = 350
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 2-5
       forward-primer = ACTCCTACGGRAGGCAGCAG
       reverse-primer = CCGTCAATTCMTTTRAGT
       from-position = 337
       to-position = 926
       minimum-length = 200
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 3-5
       forward-primer = GCCAGCAGCCGCGGTAA
       reverse-primer = CCGTCAATTYYTTTRAGTTT
       from-position = 517
       to-position = 926
       minimum-length = 200
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 4-6
       forward-primer = AGGATTAGATACCCT
       reverse-primer = GGGTTGCGCTCGTTRC
       from-position = 784
       to-position = 1114
       minimum-length = 150
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 5-7
       forward-primer = GAATTGACGGGGRCCC
       reverse-primer = GACGGGCGGTGTGTRC
       from-position = 917
       to-position = 1407
       minimum-length = 250
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 6-9
       forward-primer = GYAACGAGCGCAACCC
       reverse-primer = AAGGAGGTGATCCAGCCGCA
       from-position = 1099
       to-position = 1541
       minimum-length = 300
       include-primer = no
   </sequence-region>

   # >>>>>>>>>>>>>>>>>>>>>>> SHORTER AMPLICONS <<<<<<<<<<<<<<<<<<<<<<<<

   # In "Selection of primers for optimal taxonomic classification of 
   # environmental 16S rRNA gene sequences" by David Soergel et al. in 
   # ISME Journal (2012) 6, 1440–1444, primers for shorter regions and
   # combinations of these are evaluated. Below are listed those we 
   # know are being used, but be welcome to add,

   <sequence-region>
       title = Variable domain 1
       forward-primer = CYTAAYRCATGCAAG
       reverse-primer = YYCACGYGTTACKCA
       from-position = 45
       to-position = 128
       minimum-length = 25
       include-primer = no
   </sequence-region>

   <sequence-region>
       title = Variable domain 5
       forward-primer = GGATTAGATACCCNGGTAGTC
       reverse-primer = CCGTCAATTCCTTTRAGTTT
       from-position = 804
       to-position = 926
       minimum-length = 40
       include-primer = no
   </sequence-region>

   # >>>>>>>>>>>>>>>>>>>>>> REGION INDEPENDENT <<<<<<<<<<<<<<<<<<<<<<<<
);

    if ( $conf->{"lengths"} )
    {
        foreach $len ( @{ $conf->{"lengths"} } )
        {
            $text .= qq (
   <sequence-region>
       title = Minimum length $len
       minimum-length = $len
   </sequence-region>
);
        }
    }

    $text .= "\n</recipe>\n\n";

    return $text;
}

1;

__END__

This is the reference sequence being used, forward and complemented:
>S000629954-F
AAATTGAAGAGTTTGATCATGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAACGGTAACAGGAAGAAGCTTGCTTCTTTGCTGACGAGTGGCGGACGGGTGAGTAATGTCTGGGAAACTGCCTGATGGAGGGGGATAACTACTGGAAACGGTAGCTAATACCGCATAACGTCGCAAGACCAAAGAGGGGGACCTTCGGGCCTCTTGCCATCGGATGTGCCCAGATGGGATTAGCTAGTAGGTGGGGTAACGGCTCACCTAGGCGACGATCCCTAGCTGGTCTGAGAGGATGACCAGCCACACTGGAACTGAGACACGGTCCAGACTCCTACGGGAGGCAGCAGTGGGGAATATTGCACAATGGGCGCAAGCCTGATGCAGCCATGCCGCGTGTATGAAGAAGGCCTTCGGGTTGTAAAGTACTTTCAGCGGGGAGGAAGGGAGTAAAGTTAATACCTTTGCTCATTGACGTTACCCGCAGAAGAAGCACCGGCTAACTCCGTGCCAGCAGCCGCGGTAATACGGAGGGTGCAAGCGTTAATCGGAATTACTGGGCGTAAAGCGCACGCAGGCGGTTTGTTAAGTCAGATGTGAAATCCCCGGGCTCAACCTGGGAACTGCATCTGATACTGGCAAGCTTGAGTCTCGTAGAGGGGGGTAGAATTCCAGGTGTAGCGGTGAAATGCGTAGAGATCTGGAGGAATACCGGTGGCGAAGGCGGCCCCCTGGACGAAGACTGACGCTCAGGTGCGAAAGCGTGGGGAGCAAACAGGATTAGATACCCTGGTAGTCCACGCCGTAAACGATGTCGACTTGGAGGTTGTGCCCTTGAGGCGTGGCTTCCGGAGCTAACGCGTTAAGTCGACCGCCTGGGGAGTACGGCCGCAAGGTTAAAACTCAAATGAATTGACGGGGGCCCGCACAAGCGGTGGAGCATGTGGTTTAATTCGATGCAACGCGAAGAACCTTACCTGGTCTTGACATCCACAGAACTTTCCAGAGATGGATTGGTGCCTTCGGGAACTGTGAGACAGGTGCTGCATGGCTGTCGTCAGCTCGTGTTGTGAAATGTTGGGTTAAGTCCCGCAACGAGCGCAACCCTTATCTTTTGTTGCCAGCGGTCCGGCCGGGAACTCAAAGGAGACTGCCAGTGATAAACTGGAGGAAGGTGGGGATGACGTCAAGTCATCATGGCCCTTACGACCAGGGCTACACACGTGCTACAATGGCGCATACAAAGAGAAGCGACCTCGCGAGAGCAAGCGGACCTCATAAAGTGCGTCGTAGTCCGGATTGGAGTCTGCAACTCGACTCCATGAAGTCGGAATCGCTAGTAATCGTGGATCAGAATGCCACGGTGAATACGTTCCCGGGCCTTGTACACACCGCCCGTCACACCATGGGAGTGGGTTGCAAAAGAAGTAGGTAGCTTAACCTTCGGGAGGGCGCTTACCACTTTGTGATTCATGACTGGGGTGAAGTCGTAACAAGGTAACCGTAGGGGAACCTGCGGTTGGATCACCTCCTTA

>S000629954-R
TAAGGAGGTGATCCAACCGCAGGTTCCCCTACGGTTACCTTGTTACGACTTCACCCCAGTCATGAATCACAAAGTGGTAAGCGCCCTCCCGAAGGTTAAGCTACCTACTTCTTTTGCAACCCACTCCCATGGTGTGACGGGCGGTGTGTACAAGGCCCGGGAACGTATTCACCGTGGCATTCTGATCCACGATTACTAGCGATTCCGACTTCATGGAGTCGAGTTGCAGACTCCAATCCGGACTACGACGCACTTTATGAGGTCCGCTTGCTCTCGCGAGGTCGCTTCTCTTTGTATGCGCCATTGTAGCACGTGTGTAGCCCTGGTCGTAAGGGCCATGATGACTTGACGTCATCCCCACCTTCCTCCAGTTTATCACTGGCAGTCTCCTTTGAGTTCCCGGCCGGACCGCTGGCAACAAAAGATAAGGGTTGCGCTCGTTGCGGGACTTAACCCAACATTTCACAACACGAGCTGACGACAGCCATGCAGCACCTGTCTCACAGTTCCCGAAGGCACCAATCCATCTCTGGAAAGTTCTGTGGATGTCAAGACCAGGTAAGGTTCTTCGCGTTGCATCGAATTAAACCACATGCTCCACCGCTTGTGCGGGCCCCCGTCAATTCATTTGAGTTTTAACCTTGCGGCCGTACTCCCCAGGCGGTCGACTTAACGCGTTAGCTCCGGAAGCCACGCCTCAAGGGCACAACCTCCAAGTCGACATCGTTTACGGCGTGGACTACCAGGGTATCTAATCCTGTTTGCTCCCCACGCTTTCGCACCTGAGCGTCAGTCTTCGTCCAGGGGGCCGCCTTCGCCACCGGTATTCCTCCAGATCTCTACGCATTTCACCGCTACACCTGGAATTCTACCCCCCTCTACGAGACTCAAGCTTGCCAGTATCAGATGCAGTTCCCAGGTTGAGCCCGGGGATTTCACATCTGACTTAACAAACCGCCTGCGTGCGCTTTACGCCCAGTAATTCCGATTAACGCTTGCACCCTCCGTATTACCGCGGCTGCTGGCACGGAGTTAGCCGGTGCTTCTTCTGCGGGTAACGTCAATGAGCAAAGGTATTAACTTTACTCCCTTCCTCCCCGCTGAAAGTACTTTACAACCCGAAGGCCTTCTTCATACACGCGGCATGGCTGCATCAGGCTTGCGCCCATTGTGCAATATTCCCCACTGCTGCCTCCCGTAGGAGTCTGGACCGTGTCTCAGTTCCAGTGTGGCTGGTCATCCTCTCAGACCAGCTAGGGATCGTCGCCTAGGTGAGCCGTTACCCCACCTACTAGCTAATCCCATCTGGGCACATCCGATGGCAAGAGGCCCGAAGGTCCCCCTCTTTGGTCTTGCGACGTTATGCGGTATTAGCTACCGTTTCCAGTAGTTATCCCCCTCCATCAGGCAGTTTCCCAGACATTACTCACCCGTCCGCCACTCGTCAGCAAAGAAGCAAGCTTCTTCCTGTTACCGTTCGACTTGCATGTGTTAGGCCTGCCGCCAGCGTTCAATCTGAGCCATGATCAAACTCTTCAATTT



    pattern-string = AGAGTTTGATCCTGGCTCAG
    pattern-string = CTGCTGCCTYCCGTA
    pat-rev: TACGGRAGGCAGCAG








Malene-primere:

F: CAGCAGCCGCGGTAATAC
R: CCGTCAATTCCTTTGAGTTT

   AAACACAAAGGAATTGACGG  complemented

Lif-primere:

F: CCTAACACATGCAAGTCG
R: TACGGGAGGCAGCAG


Garbage can from here on, but dont delete yet
---------------------------------------------

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GENERAL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Regions used for PCR amplification in the numbering of Escherichia
# coli strain K12, sub-strain W3110 (RDP ID is S000629954). These regions
# include commonly use primer sites at both ends and the variable region.
# Please edit if there are good primer sites not included in the ranges. 
# Is there a good figure somewhere that shows all primer sites?

our %SSU_domains = (
    "V1" => [ 10, 136 ],         # Variable from 69 to 99
    "V2" => [ 100, 340 ],        #     -     -   137 to 242
    "V3" => [ 330, 550 ],        #     -     -   433 to 497
    "V4" => [ 500, 800 ],        #     -     -   576 to 682
    "V5" => [ 750, 950 ],        #     -     -   822 to 879
    "V6" => [ 900, 1100 ],       #     -     -   986 to 1043
    "V7" => [ 1050, 1230 ],      #     -     -   1117 to 1173
    "V8" => [ 1190, 1400 ],      #     -     -   1243 to 1294
    "V9" => [ 1320, 1542 ],      #     -     -   1435 to 1465
);

# Subtract 1 to get zero-based numbers,

map { $_->[0] -= 1; $_->[1] -= 1 } values %SSU_domains;

# Domain combinations to write sequences for,

our %SSU_exports = (
    "SSU_domain_1" => [ "V1" ],
    "SSU_domain_2" => [ "V2" ],
    "SSU_domain_3" => [ "V3" ],
    "SSU_domain_4" => [ "V4" ],
    "SSU_domain_5" => [ "V5" ],
    "SSU_domain_6" => [ "V6" ],
    "SSU_domain_7" => [ "V7" ],
    "SSU_domain_8" => [ "V8" ],
    "SSU_domain_9" => [ "V9" ],
    "SSU_domain_1-3" => [ "V1", "V2", "V3" ],
    "SSU_domain_2-3" => [ "V2", "V3" ],
    "SSU_domain_3-4" => [ "V3", "V4" ],
    "SSU_domain_3-5" => [ "V3", "V4", "V5" ],
    "SSU_domain_4-5" => [ "V4", "V5" ],
    "SSU_domain_4-6" => [ "V4", "V5", "V6" ],
    "SSU_domain_5-6" => [ "V5", "V6" ],
    "SSU_domain_6-7" => [ "V6", "V7" ],
    "SSU_domain_6-8" => [ "V6", "V7", "V8" ],
    "SSU_domain_7-8" => [ "V7", "V8" ],
    "SSU_domain_7-9" => [ "V7", "V9" ],
    "SSU_domain_8-9" => [ "V8", "V9" ],
    "SSU_minlen_1000" => 1000,
    "SSU" => 1,
);


