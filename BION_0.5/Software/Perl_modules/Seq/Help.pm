package Seq::Help;     #  -*- perl -*-

# Sequence related help texts. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &dispatch
                 &seq_chimera_limits
                 &seq_chimera_method
                 &seq_chimera_intro
                 &seq_chimera_perform
                 &seq_chimera_settings
                 &seq_chimera_usage
                 &seq_classify_intro
                 &seq_clean_features
                 &seq_clean_intro
                 &seq_clean_perform
                 &seq_clean_recipe
                 &seq_cluster_intro
                 &seq_cluster_recipe
                 &seq_credits
                 &seq_demul_intro
                 &seq_demul_perform
                 &seq_demul_recipe
                 &seq_demul_barfile
                 &seq_demul_pat_intro
                 &seq_demul_pat_perform
                 &seq_demul_pat_recipe
                 &seq_demul_pat_barfile
                 &seq_derep_examples
                 &seq_derep_features
                 &seq_derep_intro
                 &seq_derep_perform
                 &seq_extract_pats_intro
                 &seq_extract_pats_perform
                 &seq_extract_pats_recipe
                 &seq_fetch_examples
                 &seq_fetch_features
                 &seq_fetch_intro
                 &seq_fetch_perform
                 &seq_fetch_ebi
                 &seq_index_examples
                 &seq_index_features
                 &seq_index_intro
                 &seq_index_perform
                 &seq_index_switches
                 &seq_map_intro
                 &seq_map_recipe
                 &seq_pool_intro
                 &seq_pool_map_intro
                 &seq_simrank_examples
                 &seq_simrank_features
                 &seq_simrank_intro
                 &seq_simrank_perform
                 &seq_simrank_settings
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Sys_name = $Common::Config::sys_name;

our $Num_source = qq (
These numbers come from an older two-core 2007 model Lenovo t61p laptop 
with a T7500 processor, 4 MB cache and 3 GB RAM. On todays systems, these
numbers ought to be much better. On 64-bit systems the RAM usage may be 
significantly higher because of the larger address space.
);

our %Dispatch_dict = (
    "cons_pool" => [ qw ( intro recipe ) ],
    "seq_chimera" => [ qw ( intro method usage settings perform limits ) ],
    "seq_classify" => [ qw ( intro ) ],
    "seq_clean" => [ qw ( intro clipping trimming filtering recipe perform ) ],
    "seq_cluster" => [ qw ( intro features recipe perform ) ],
    "seq_demul" => [ qw ( intro barfile perform recipe ) ],
    "seq_demul_pat" => [ qw ( intro barfile patfile perform recipe ) ],
    "seq_derep" => [ qw ( credits intro examples features perform ) ],
    "seq_extract_pats" => [ qw ( intro perform recipe ) ],
    "seq_fetch" => [ qw ( credits intro examples features perform missing ) ],
    "seq_fetch_ebi" => [ qw ( intro ) ],
    "seq_index" => [ qw ( credits intro examples features perform missing switches ) ],
    "seq_map" => [ qw ( intro recipe ) ],
    "seq_pool" => [ qw ( intro recipe ) ],
    "seq_pool_map" => [ qw ( intro recipe ) ],
    "seq_simrank" => [ qw ( intro features examples settings perform limits ) ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub dispatch
{
    # Niels Larsen, November 2010.

    # Dispatch different help page requests. The first argument is the
    # program name that invoked it, then second is the type of help to 
    # be shown. If "seq_fetch" is given as first argument and "intro"
    # as the second, then the routine seq_fetch_intro is invoked.

    my ( $prog,           # Program string like "seq_fetch"
         $request,        # Help page name like "intro" - OPTIONAL, default "intro"
         ) = @_;

    # Returns a string. 

    my ( $text, $routine, $choices, @msgs, $opts, @opts, @args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $request ||= "intro";

    if ( $opts = $Dispatch_dict{ $prog } )
    {
        @opts = grep /^$request/i, @{ $opts };

        if ( scalar @opts != 1 )
        {
            $choices = join ", ", @{ $opts };

            if ( scalar @opts > 1 ) {
                push @msgs, ["ERROR", qq (Help request is ambiguous -> "$request") ];
                push @msgs, ["INFO", qq (Choices are: $choices) ];
            } else {                
                push @msgs, ["ERROR", qq (Unrecognized help request -> "$request") ];
                push @msgs, ["INFO", qq (Choices are: $choices) ];
            }

            &append_or_exit( \@msgs );
        }
    }
    else {
        &error( qq (Wrong program string -> "$prog") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DISPATCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $opts[0] eq "credits" )
    {
        $routine = "Seq::Help::seq_credits";
    }
    elsif ( $opts[0] eq "method" )
    {
        require Seq::Methods;
        $routine = "Seq::Methods::get_text";
        @args = ( $prog );
    }
    else {
        $routine = "Seq::Help::$prog" ."_$opts[0]";
    }

    no strict "refs";
    $text = &{ $routine }( @args );

    $text =~ s/\n/\n /g;
    chop $text;

    if ( defined wantarray ) {
        return $text;
    } else {
        print $text;
    }

    return;
}

sub seq_chimera_limits
{
    # Niels Larsen, October 2012. 

    my ( $text, $title );
    
    $title = &echo_info("Limits");

    $text = qq (
$title

Reference data is held in RAM and loading for example an entire RDP 
may flood the RAM. Instead de-replicated datasets should be used where
only the sequence parts that correspond to the amplicon is included. 

The output sequence order may be different from the input order if 
run on multiple cores.

);

    return $text;
}

sub seq_chimera_intro
{
    # Niels Larsen, September 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

PCR amplification products can act as false primers, which leads to 
sequences where parts originate from different organisms. The false 
join can be anywhere in a sequence, fragments can be from closely or 
distantly related sources and they may or may not be highly similar 
to known seqeuences. Some datasets can have many such chimeras, some 
very few. All this complicates their removal by computer, and there 
is a "grey-zone" where it is difficult to say if a sequence is 
chimeric or not. Several applications are available with each their
methods, strengths and limitations.

This method measures chimera-potential of single-gene DNA sequences 
against a well-formed reference dataset without aligning. Inputs are
one or more sequence files and a reference dataset file (like 16S) 
that should preferably have no identical sequences in it. Outputs
are score tables plus a chimera- and non-chimera sequence files. The
method does not not align sequences and runs quickly enough that 
experimentation with the score threshold becomes practical, and a 
histogram output helps with this. Only two-fragment chimeras are 
detected, although triple-fragment usually also receive high scores. 
By default all available CPU cores will be used.

These help options have more descriptions,

    --help method
    --help usage
    --help settings
    --help perform
    --help limits

Options can be abbreviated, for example '--help p' will print the 
section with performance.

);

    return $text;
}

sub seq_chimera_method
{
    # Niels Larsen, September 2012.

    my ( $text, $title, $ex_title );
  
    $title = &echo_info("Method");
    $ex_title = &echo_info("Debug output example");

    $text = qq (
$title

OBSOLETE - rewrite when method has stabilized

The debug histogram output example below shows a low-scoring likely 
chimera. The l's mark cumulated dissimilarities from the start of the
sequences, and R's from the end and backwards. The length of the l+R 
horizontal bars becomes dissimilarity sums. In normal sequences each
should increase more or less continually throughout the sequence, give 
or take conserved areas. But in chimeras the cumulative dissimilarities
will be relatively low up to the breakpoint, and then increase. That 
creates "valleys" as the one below.

Fragments can have high or low similarity with known sequences, so 
we must use ratios instead of absolute sums. Below, at valley begin 
there are 17 mismatching oligos (17 R's) and at the end there are 2;
subtract those 2 and 15 is left. Then we do the same subtraction for
the R's at the bottom and get 2 minus 2 = 0, which is changed to 1 
so it can be used as a ratio. Then we get the R-gain by dividing 15 by 
1 which gives 15. Doing the same for the l-fragment gives an l-gain 
of 7.5. Then l-gain and R-gain are multiplied, yielding 112.5. To 
make the score insensitive to step length we multiply by step length
4, giving 450. That's kind of a high number, so why not divide by 10,
and the final score becomes 45. 
 
Using this scoring, a default value of 25 often strikes a good balance
between false positives and negatives. Use 20 to get many  more, and 
30 to get only the worst. The scores can be up to 1000 or more for 
the most easily detectable chimeras. 

The reference dataset sequences must cover the whole amplicon or 
false positives may appear. The reference dataset size is less 
critical, though the broadest phylogenetic coverage improves the 
result. But there is no point in having sequences that are identical
within the amplicon or are more similar than the level chimeras are
detectable at. 

$ex_title

GDPEQA103FR6HT
--------------

 Word length: 8
 Step length: 4

 Break point: 70
     Left ID: S000558527
    Right ID: S003222509
   Left skew: 7.5
  Right skew: 15
       Score: 44

  Pos  Minimum mismatch at hypothetical join
-----  -------------------------------------

    0  RRRRRRRRRRRRRRRRR  <-- valley begin
    4  RRRRRRRRRRRRRRRR
    8  RRRRRRRRRRRRRRR
   12  RRRRRRRRRRRRRR
   16  RRRRRRRRRRRRR
   20  RRRRRRRRRRRR
   24  RRRRRRRRRRR
   28  RRRRRRRRRR
   32  RRRRRRRRR
   36  RRRRRRRR
   40  lRRRRRRR
   44  llRRRRRR
   48  llRRRRR
   52  llRRRR
   56  llRRR
   60  llRR
   64  llRR
   68  llRR  <-- join pos
   72  llRR
   76  llRR
   80  lllRR
   84  llllRR
   88  llllRR
   92  llllRR
   96  llllRR
  100  llllRR
  104  lllllRR
  108  llllllRR
  112  llllllRR
  116  lllllllRR
  120  llllllllRR
  124  llllllllRR
  128  lllllllllRR
  132  llllllllllRR
  136  lllllllllllRR
  140  lllllllllllRR
  144  lllllllllllRR
  148  lllllllllllRR
  152  lllllllllllRR
  156  lllllllllllRR
  160  lllllllllllRR
  164  lllllllllllRR
  168  llllllllllllRR
  172  lllllllllllllRR
  176  lllllllllllllRR
  180  lllllllllllllRR
  184  llllllllllllllRR
  188  lllllllllllllllRR  <-- valley end
  192  lllllllllllllllRR
  196  lllllllllllllllRR
  200  lllllllllllllllRR
  204  lllllllllllllllRR

);

    return $text;
}

sub seq_chimera_perform
{
    # Niels Larsen, September 2012.

    my ( $text, $s_title, $r_title );
  
    $s_title = &echo_info("Speed");
    $r_title = &echo_info("RAM");

    $text = qq (
$s_title

With word size 8 and step length 4, a dataset of 225k 16S sequences
will on a single CPU-core take about 2-3 hours against a dataset of 
400,000 500-long reference sequences. On an 8-core machine it will
20-30 minutes. This can likely be improved. Run-time is proportional
to the number of input sequences, and to the reference data volume 
(i.e. the number of bases). Run-time is inversely proportional to 
step length. 

$r_title

The query input is read progressively, but the whole reference set 
is held in memory. The RAM consumption is 2.5-3 times the number of
bases being loaded, which for fasta format usually is approximately
the file size. 

To read in an entire RDP covering all regions in 16S will flood the
RAM on smaller machines, but there is no reason to do that: reference 
datasets should cover only the amplicon being used, and may first be 
either dereplicated, 98-99% clustered or both. A set of 400,000 
sequences 500 long will take 8-900 MB of RAM, and more agressive 
clustering can be done without sacrificing sensitivity. Diversity at
the 98-99% level will probably never exhaust the RAM of common 
machines, and using PCR for bacterial profiling will likely be 
replaced by direct sequencing long before that happens.

);

    return $text;
}

sub seq_chimera_settings
{
    # Niels Larsen, September 2012.

    my ( $text, $title );
  
    $title = &echo_info("Settings");

    $text = qq (
$title

There are five functionally relevant settings,

 *  Word length (--wordlen). Word length is the oligo-word-size used,
    and must be between 6 and 15. Sensitivity declines with higher 
    values and speed increases somewhat. The default of 8 gives the 
    best accuracy. 

 *  Step length (--steplen). Step length skips sequence positions:
    if set at 4, words will only be made from every fourth position,
    and so on. Step length cannot be higher than word length. The 
    sensitivity declines with higher step lengths and the default of
    4 is a good compromise between accuracy and speed. 

 *  Score threshold (--minsco). This is the minimum chimera score for
    a sequence to be considered chimeric. See --help method for how 
    the score is derived. The default value is 30, which for us works
    best. Lowering it to 20 will often catch more false positives, 
    while at 40 there may be more false negatives. So the higher the 
    score the more strict the search is: set it to 40 or 50 to get 
    just the worst, to 20 to get most or all. The --chist option 
    prints a (primitive) text histogram that shows scores versus 
    frequency.

 *  Minimum fragment length (--minfrag). If one of the fragments is 
    shorter than this value (default 50), then the score is set to 
    zero, i.e. that sequence is considered non-chimeric. 

 *  NOT WORKING YET
    De-novo mode (--denovo). Compare sequences against themselves
    while not comparing sequences with identical IDs. 

);

    return $text;
}

sub seq_chimera_usage
{
    # Niels Larsen, September 2012.

    my ( $text, $q_title, $db_title, $out_title, $ex_title );
  
    $q_title = &echo_info("Query input");
    $db_title = &echo_info("Reference input");
    $out_title = &echo_info("Outputs");
    $ex_title = &echo_info("Examples");

    $text = qq (
$q_title

One or more FASTA or FASTQ files can be given. Upper case, lower case,
U's and T's are treated the same, non-canonical bases become A's and
quality information is ignored. There is no limit on the number of 
sequences and the default length limit is 10,000 which can however be
lifted to 2.1 billion with the --maxlen argument. 

$db_title

A single reference file in FASTA or FASTQ format is given. The --dbfile
option takes a full file path, the --dbname takes the given value as
a prefix and matches files across all BION-installed reference datasets.
The reference dataset should ideally contain on the sub-sequences that 
completely cover the amplicon in question. The BION package has an 
import routine that generates sub-sequence files for all popular 
amplicon ranges. After the right amplicon "slice" has been cut out, the
sequences should be de-replicated or clustered to 99% or 99.5% to 
reduce memory requirement and run-time. The BION import routine does 
this too.

$out_title 

Four types of output files are written for each input file: a table 
with chimeric scores for each query id, a sequence file with chimeras 
and one without, and a primitive histogram that shows scores versus
sequence counts. Both output sequence files have the format of the input
sequence file. An optional debug file is written with large verbose 
histograms - be warned not to run --debug swith under normal runs, 
because there may be gigabytes of output. 

$ex_title

To check a directory of FASTQ formatted file against a reference 
dataset, with default settings,

   seq_chimera dir/*.fq --dbfile db.fa 

This produces four default output files,

   nnnnnnn.fq.chim       Chimeric sequences 
   nnnnnnn.fq.nochim     Non-chimeric sequences
   nnnnnnn.fq.chimtab    Table with query id, score, fragment ids 
   nnnnnnn.fq.chist      Histogram of score versus frequency

The suffixes of these output files cannot be changed. To catch more 
chimeras (--minsco default is 30),

   seq_chimera (as above) --minsco 20

To greately accellerate the program and only catch the worst,

   seq_chimera (as above) --wordlen 12 --steplen 8 --minsco 30

To print verbose debug output (will be large, careful),

   seq_chimera (as above) --debug

This will create in addition to the above

   nnnnnnn.fq.chim.debug
   nnnnnnn.fq.nochim.debug

The default score of 30 is a good cutoff for most datasets. But there 
will always be false negatives and positives, and users may wish to be
more or less agressive. Sometimes experimentation is needed, but the
program is quick enough for this to be feasible.

);

    return $text;
}

sub seq_classify_intro
{
    # Niels Larsen, March 2010.

    # Returns a small description of Seq::Classify and its inputs and 
    # outputs.

    # Returns a string. 

    my ( $text, $input_title, $output_title, $descr_title, $legal_text );

    $descr_title = &echo_info( "Description" );
    $input_title = &echo_info( "Input format" );
    $output_title = &echo_info( "Output format" );
    $legal_text = &Common::Messages::legal_message();

    $text = qq (
$descr_title

Matches fasta-formatted input sequences against one or more reference 
datasets. But unlike seq_match, the output is a seven-column table, and
there are default datasets used in order: the whole input is matched 
against the first set, non-matching sequences against the next, and so 
on. The matching software used is the simscan blast-like programs (by 
Denis Kaznadzey et al), nsimscan for RNA/DNA and psimscan for protein.

$input_title

Input are sequences in fasta format. The fasta header may have words
following the id, but these will be ignored. 

$output_title

Output is a tab-separated table with one or more rows per query 
sequence, each row witht these columns:

  * Input sequence id
  * Input sequence length
  * Dataset name
  * Dataset sequence id
  * Match similarity percent
  * Number of organism hits
  * Free-text comment

If a query has no matches, the table row will contain the first field, 
the rest will be empty. 

$legal_text
);

    return $text;
}

sub seq_clean_clipping
{
    my ( $title, $text );

    $title = &echo_info("Clipping");

    $text = qq (
$title

Sequences can be cut where a sub-sequence or pattern first matches, seen
from the sequence start or end, and optionally within a fixed distance. 
The pattern can include indels, sequence motifs and secondary structure 
and the cut can be made either at the end or the start of the match. This
this recipe step example

 <sequence-clip-pattern-start>
     title = Pattern clipping
     pattern-string = ATT AGATACCCNNGTAG[1,1,1] TCC
     pattern-orient = forward
     include-match = yes
     search-distance = 15
 </sequence-clip-pattern-start>

says "cut all sequences at the end of where this pattern matches in 
forward orientation looking at most 15 positions down the sequence". To
match from ends use the companion step <sequence-clip-pattern-end>. The
pattern language is explained here,

http://blog.theseed.org/servers/2010/07/scan-for-matches.html

);
    return $text;
}

sub seq_clean_filtering
{
    my ( $title, $text );

    $title = &echo_info("Filtering");

    $text = qq (
$title

Does not alter sequences but keeps only those in a list that meet the given
constraints. Filtering constraints include

 * Sequence match / non-match
 * Pattern match / non-match 
 * Overall quality with minimum and/or maximum quality and strictness 
 * Length, minimum and/or maximum 
 * GC content, minimum and/or maximum percentage 
 * ID match / non-match
 * Comments match / non-match

This example step filters sequences by overall quality,

 <sequence-filter-quality>
     title = Quality filter
     minimum-quality = 99%
     maximum-quality = 100%
     minimum-strict = 95%
     maximum-strict = 100%
 </sequence-filter-quality>

where the quality percentages are encoding independent: 99% means true 
bases should occur at 99% or more of the sequence positions. A minimum 
strictness of 95% means at least 95 of 100 positions must meet this 
criterion. 

);
    return $text;
}

sub seq_clean_trimming
{
    my ( $title, $text );

    $title = &echo_info("Trimming");

    $text = qq (
$title

Shortens sequences from their starts or ends by sequence match or by 
sequence match or quality constraint. This example trims ends by 
sequence match,

 <sequence-trim-end>
     title = Sequence trimming
     sequence = AGGTCGGTATTAGGA
     search-distance = 15
     minimum-length = 1
     minimum-strict = 90%
 </sequence-trim-end>

Like a slide-rule, the probe sequence above slides from the end one 
step at a time. If "minimum-strict" was set to 100%, then sliding would
stop when the first mismatch is encountered and the matching sequence
would be cut away. With a strictness of 90% however, one mismatch out 
of 10 would be tolerated. This step is typically used for trimming off
primer remnants. A few bases from the real data may also disappear, 
but sequences are usually clustered, and then they will re-appear in 
the resulting consenses. This example trims starts by quality,

 <sequence-trim-quality-start>
     title = Quality trimming
     window-length = 10
     window-match = 9
     minimum-quality = 99.0%
 </sequence-trim-quality-start>

A sliding window of length 10 counts the number of bases with a quality
of at least 99.0%. If 9 of 10 bases have that quality or better, then 
the window stops and the preceding sequence disappears. Finally the 
bases are trimmed one by one for low quality. 

);
    return $text;
}

sub seq_clean_intro
{
    # Niels Larsen, January 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Cleans, trims and/or extracts sequences by length, quality and pattern.
Settings for each type of filter must be given in a recipe file, which 
this program which print a template of. 

To see more detail,

    --help clipping     Explains cutting sequences
    --help trimming     Explains trimming the ends
    --help filtering    Explains filtering sequences
    --help perform      Lists runtimes and RAM usage
    --help recipe       Gives example of how to combine steps

Options can be abbreviated, for example '--help r' will print an input 
recipe template.

);

    return $text;
}

sub seq_clean_perform
{
    # Niels Larsen, January 2012.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title

A fastq file with 40 million reads, each 90 long, with 26 tags and the 
patterns seen with --help patfile,

       Speed:  17 minutes hot, 19 minutes cold
    Peak RAM:  25 mb.

"Hot" means with the file memory-cached by the system, "cold" is without.
Note however the numbers very much depend on slack in patterns used and 
other settings, but the above hold true for the template printed with
--help recipe. 
$Num_source
);

    return $text;
}

sub seq_clean_recipe
{
    # Niels Larsen, January 2012.

    # Returns a configuration template for a typical cleaning recipe.

    # Returns a string.

    my ( $text, $title, $sys_name );

    if ( -t STDOUT )
    {
        $title = &echo_info("Cleaning recipe");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $sys_name = $Common::Config::sys_name;

    $text .= qq (
$title

Below is a cleaning template example that shows how to combine single 
steps. In $sys_name "cleaning" means a chain of clipping, trimming or 
filtering steps, where the output of one is the input to the next. The
template has the right ready-to-run format, but recipe authors should 
decide how to combine steps, as this depends on the data at hand. 

---------------------------- cut here -------------------------------

# This is a cleaning configuration template. Values may be changed, 
# and tagged sections added or removed. The section below, but also 
# these comments, can be used in combination with other sub-recipes
# and form larger recipes.

<sequence-cleaning>

    title = Reads cleaning template
    author = Someone's Name
    email = Someone's E-mail

    quality-type = Illumina_1.3

    <sequence-filter>
        title = Poly-A removal
        pattern-string-nomatch = AAAAAAAAAAAAAAAAAA[1,0,0]
        forward = yes
    </sequence-filter>

    <sequence-filter>
        title = Low complexity filter
        pattern-string-nomatch = p1=2...2 p1 p1 p1 p1 p1 p1 p1
        forward = yes
    </sequence-filter>

    <sequence-trim-quality-end>
        title = 3-quality trim
        window-length = 10
        window-match = 10
        minimum-quality = 96%
    </sequence-trim-quality-end>

    <sequence-trim-quality-start>
        title = 5-quality trim
        window-length = 10
        window-match = 10
        minimum-quality = 96%
    </sequence-trim-quality-start>

    <sequence-filter>
        title = Length filter
        minimum-length = 25
        maximum-length = 45
    </sequence-filter>

    <sequence-filter-quality>
        title = Quality filter
        minimum-quality = 96%
        minimum-strict = 100%
    </sequence-filter-quality>

 </sequence-cleaning>

----------------------------- cut here ------------------------------

There are more cleaning steps than the ones shown here, see the options
with seq_clean --help.

);

    return $text;
}

sub seq_cluster_intro
{
    my ( $text, $title );

    $title = &echo_info("Clustering");

    $text = qq (
$title

Clusters one or more fasta formatted sequence files and produces uclust
files each with one alignment per cluster. TODO: explain. 

These help options describe clustering further,

    --help features
    --help perform
    --help recipe

Options can be abbreviated, for example '--help r' will print an input 
recipe template.

);
 
    return $text;
}

sub seq_cluster_recipe
{
    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Recipe template");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
# 
# EXPLAIN 
#

<sequence-clustering>
    minimum-seed-similarity = 100
    minimum-cluster-size = 1
    maximum-ram = 20%
    recluster-chimeras = yes
    with-alignments = yes
</sequence-clustering>

);

    return $text;
}

sub seq_credits
{
    # Niels Larsen, March 2011.
    
    # Gives credit where due and gives a reference.

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Credits");

    $text = qq (
$title

This program would not be possible without Kyoto Cabinet, which is the most
suitable high performance key/value storage, written by Mikio Hirabayashi. 
He offers excellent support and commercial licenses for non-free projects.

Many thank you's go the a range of free and open source tools, including 
languages, editors, servers and the GNU suite. Had such a rich set of high 
quality components been proprietary, this package could not have been done.

Reference:

Niels Larsen, Danish Genome Institute at http://genomics.dk, unpublished.

);

    return $text;
}

sub seq_demul_intro
{
    # Niels Larsen, January 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Splits sequences in a given file into separate files based on matches 
near the sequence beginnings with a given set of tags. Can be run from
command line and from recipes.

These help options describe this further,

    --help barfile 
    --help perform
    --help recipe

Options can be abbreviated, for example '--help r' will print an input 
recipe template.

);

    return $text;
}

sub seq_demul_perform
{
    # Niels Larsen, March 2011.

    # Returns a small description of computer resource usage during typical 
    # de-replication runs. 

    # Returns string.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title

A fastq file with 40 million reads, each 90 long, with maximum-distance 
set to 2 and 26 tags:

       Speed:  330 seconds hot, 370 seconds cold.
    Peak RAM:  25 mb.

With maximum-distance 10:

       Speed:  450 seconds hot, 520 seconds cold.
    Peak RAM:  25 mb.
 
"Hot" means with the file memory-cached by the system, "cold" is without.
$Num_source
);

    return $text;
}

sub seq_demul_recipe
{
    # Niels Larsen, January 2012.

    # Returns a configuration template for a tag-only demultiplication.

    my ( %args,   
        ) = @_;

    # Returns a string.

    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Recipe template");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
# This is a cut-and-paste example of a tag-demultiplex recipe, except the 
# values must be given and edited. The fields mean:
#
# title             Short description to appear in outputs
# tag-file          Table of ID's and tag sequences, see --help barfile
# maximum-distance  If set to 2, the first 3 positions will be checked 
# mismatch-file     Whether to save non-matching sequences in a separate
#                   file with the suffix .NOMATCH
#
# The section below, but also these comments, can be used in combination 
# with other sub-recipes and form larger recipes.

<sequence-demultiplex-tag>
    title = Tag de-multiplexing
    tag-file = 
    maximum-distance = 2
    output-mismatches = no
    output-combine = no
    output-tag-names = no
</sequence-demultiplex-tag>

);

    return $text;
}

sub seq_demul_barfile
{
    # Niels Larsen, January 2012.

    # Returns help with tag files.

    # Returns a string.

    my ( $text, $title );

    $title = &echo_info("Tag file");

    $text = qq (
$title

Tag files are tables like this made up example, with any number of lines,

# ID F-tag R-tag
Name-1 GAGGCTAC GTGCGTAC
Name-1 GAGGCCAC GTGCGCAC

The first line must contain one or more of three column labels that must
literally be ID, F-tag and R-tag. They can come in any order, but at least
one of F-tag or R-tag must be present. Tag sequences are used in output 
file names, and so are the names. If names are omitted numbers are used 
instead. 

);

    return $text;
}

sub seq_demul_pat_intro
{
    # Niels Larsen, January 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Splits sequences in a given file into separate files based on matches 
with any n-long sub-sequence that is adjacent to a given pattern. This 
pattern is very flexible and can be used for combined splitting by tag 
and sub-sequence extraction. Can be run from command line and from 
recipes.

These help options describe this further,

    --help barfile      Explains tag file format
    --help patfile      Explains primer pattern file format 
    --help perform      Lists runtimes and RAM usage
    --help recipe       Prints a recipe template

Options can be abbreviated, for example '--help r' will print an input 
recipe template.

);

    return $text;
}

sub seq_demul_pat_patfile
{
    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Pattern file");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
# This section can be used as input to all programs that take a pattern file. 
# The fields mean:
#
# title             Short description to appear in outputs
#
# pattern-orient    If reverse, matches and returns the complement
#
# pattern-match     Pattern string in Patscan format. Briefly, the [2,1,1]
#                   bracket below means "up to 2 mismatches, 1 deletion and 
#                   1 insertion" and the 30...45 sub-pattern means "any 
#                   sequence between 30 and 45 in length". Patscan can do 
#                   far more, look for helices in combination with sequence
#                   conservation etc etc. 
#
# pattern-nonmatch  Same string as pattern-match, except gets the mismatches.
#
# get-elements      Comma- or blank separated numbers of pattern elements to 
#                   get e.g. 3,4,5 gets the sub-sequence that corresponds 
#                   to ATT 30...45 GTT in the pattern string below. 
#
# get-orient        If reverse, the fetched sub-sequence is complemented
#
# The section below, but also these comments, can be used in combination 
# with other sub-recipes and form larger recipes.

<pattern>
    title = Forward primer
    pattern-orient = forward
    pattern-match = CAC TATAGGGGCCACCAACGAC[2,1,1] ATT 30...45 GTT GATATAAATA[1,1,1]
    get-elements = 4
    get-orient = forward
</pattern>

<pattern>
    title = Reverse primer
    pattern-orient = forward
    pattern-match = GGA TCCATGGGCACTATTTATATC[2,1,1] AAC 30...45 AAT GTCGTTGGTGG[1,1,1]
    get-elements = 4
    get-orient = reverse
</pattern>

);

    return $text;
}

sub seq_demul_pat_perform
{
    # Niels Larsen, January 2012.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title

A fastq file with 40 million reads, each 90 long, with 26 tags and the 
patterns seen with --help patfile,

       Speed:  16 minutes hot, 17 minutes cold
    Peak RAM:  25 mb.

"Hot" means with the file memory-cached by the system, "cold" is without.
$Num_source
);

    return $text;
}

sub seq_demul_pat_recipe
{
    # Niels Larsen, January 2012.

    # Returns a configuration template for a pattern demultiplication.

    my ( %args,   
        ) = @_;

    # Returns a string.

    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Recipe template");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
# This is a cut-and-paste example of a pattern based demultiplex recipe,
# except values must be given and edited. The fields mean:
#
# title             Short description to appear in outputs
# tag-file          Table of ID's and tag sequences, see --help barfile
# pattern-file      Pattern recipe file, see --help patfile
# mismatch-file     Whether to save non-matching sequences in a separate
#                   file with the suffix .NOMATCH
#
# The section below, but also these comments, can be used in combination 
# with other sub-recipes and form larger recipes.

<sequence-demultiplex-tag>
    title = Pattern de-multiplexing
    tag-file = 
    pattern-file = 
    output-mismatches = no
    output-combine = no
    output-tag-names = no
</sequence-demultiplex-tag>

);

    return $text;
}

sub seq_demul_pat_barfile
{
    return &Seq::Help::seq_demul_barfile();
}

sub seq_derep_examples
{
    # Niels Larsen, March 2011.
    
    # Gives examples. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Examples" );

    $text = qq (
$title

1. seq_derep pig_expr.fq 

   This creates the file 'pig_expr.fq.derep', a key/value storage with sequence
   as key and count and quality as value. 

2. seq_derep seqdir*/*.fq --suffix .proj4

   As above, but processing multiple files at a time and using custom output 
   suffix. This is useful for customer separation, tests etc.

3. seq_derep seqdir*/*.new.fq --addto 'seqdir*/*.proj5 

   As above, but adding new sequence data to an existing set of de-replication 
   indices. There must be one new file per existing index.

);

    return $text;
}

sub seq_derep_features
{
    # Niels Larsen, March 2011.
    
    # Returns description of features.

    # Returns a string.

    my ( $text, $title, $formats );
  
    $title = &echo_info("Features");
    $formats = join ", ", @{ &Seq::Storage::index_info_values( "formats", "derep" ) };

    $text = qq (
$title

Feature highlights are,

*  High indexing speed, small file size and low resident memory usage.
   Memory and file size depends very much on the degree of redundancy in 
   the data. 

*  Many files can be processed with one command (see examples). The output
   files will have suffixes added, which are user controlled. This makes
   it easier to manage large file sets.

*  Supported input formats: $formats. The fasta format must have
   single-line sequences, convert with seq_convert if not. 

*  De-replication indices can be added to. 

See also seq_derep_dump, which creates various output formats from 
de-replication storage files.

);

    return $text;
}

sub seq_derep_intro
{
    # Niels Larsen, January 2011.
    
    # Returns a small dereplicate introduction and explains how to get more 
    # help. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Introduction" );

    $text = qq (
$title

Collapses identical sequences into single ones. If there are qualities, the
highest quality value is retained at each sequence position. For data with 
high redundancy such as expression experiments, this can be a useful way to 
distill sequences early, so for example clustering programs can be run on 
commodity hardware. 

But this crude approach can be dangerous also: if a given high quality value
is off, so that the corresponding base is really of lower quality, then an 
articifical SNP may show in the upstream analyses. We are not sure how great
the potential for such systematic errors is, that is how reliable the high
quality values are. For Illumina it may depend on their training sets and 
algorithms.

These help options describe de-replication further,

    --help features   Feature list
    --help examples   Commented examples
    --help perform    Performance numbers

Options can be abbreviated, for example '--help p' will show performance
numbers.
);

    $text .= "\n". &Common::Messages::legal_message() ."\n";

    return $text;
}

sub seq_derep_perform
{
    # Niels Larsen, March 2011.

    # Returns a small description of computer resource usage during typical 
    # de-replication runs. 

    # Returns string.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title
$Num_source
Both runs were done with file system cache ('hot') and without ('cold').
The speed will be CPU limited when redundancy is high, gradually disk 
limited when not. 

Expression data with 16.2 million un-cleaned 35-long sequences, as 1.5 gb 
fastq file, index 490 mb:

       Speed:  150 seconds hot, 160 seconds cold.
        Size:  110 mb.
   Sequences:  16.2 million before, 1.3 million after.
    Peak RAM:  310 mb.

The above data, but first cleaned by length and quality:

       Speed:  72 seconds hot, 83 seconds cold.
        Size:  15.2 mb.
   Sequences:  12.2 million before, 258,000 after.
    Peak RAM:  120 mb.

The second example shows much better redundancy, as would be expected. 
But many datasets do not have simple redundancy, and then this program
has no meaning. 

);

    return $text;
}

sub seq_extract_pats_intro
{
    # Niels Larsen, January 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Filters and extracts by one or more patterns. Often parts of reads are 
primers, perhaps both a forward and reverse one. Sub-sequence(s) to be 
extracted can be defined by primer patterns and orientations of sequence
and sub-sequence(s) can be set independently. 

These help options describe this further,

    --help recipe
    --help perform

Options can be abbreviated, for example '--help c' will print a pattern
configuration template.

);

    return $text;
}

sub seq_extract_pats_perform
{
    # Niels Larsen, January 2012.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title

A fastq file with 40 million reads, each 90 long, with 26 tags and the 
patterns seen with --help patfile,

       Speed:  16 minutes hot, 17 minutes cold
    Peak RAM:  25 mb.

"Hot" means with the file memory-cached by the system, "cold" is without.
$Num_source
);

    return $text;
}

sub seq_extract_pats_recipe
{
    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Pattern recipe");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
# This section can be used as input to seq_extract_pats and be used as a 
# building block of larger recipes. The fields mean:
#
# title             Short description to appear in outputs
#
# pattern-orient    If reverse, matches and returns the complement
#
# pattern-match     Pattern string in Patscan format. Briefly, the [2,1,1]
#                   bracket below means "up to 2 mismatches, 1 deletion and 
#                   1 insertion" and the 30...45 sub-pattern means "any 
#                   sequence between 30 and 45 in length". Patscan can do 
#                   far more, look for helices in combination with sequence
#                   conservation etc etc. 
#
# pattern-nonmatch  Same match string as above, but gets the mismatches
#
# get-elements      Comma- or blank separated numbers of pattern elements to 
#                   get e.g. 3,4,5 gets the sub-sequence that corresponds 
#                   to ATT 30...45 GTT in the pattern string below. 
#
# get-orient        If reverse, the fetched sub-sequence is complemented
#
# The section below, but also these comments, can be used in combination 
# with other sub-recipes and form larger recipes.

<sequence-extract>
    <sequence-pattern>
        title = Forward primer
        pattern-orient = forward
        pattern-match = CAC TATAGGGGCCACCAACGAC[2,1,1] ATT 30...45 GTT GATATAAATA[1,1,1]
        get-elements = 4
        get-orient = forward
    </sequence-pattern>
    <sequence-pattern>
        title = Reverse primer
        pattern-orient = forward
        pattern-match = GGA TCCATGGGCACTATTTATATC[2,1,1] AAC 30...45 AAT GTCGTTGGTGG[1,1,1]
        get-elements = 4
        get-orient = reverse
    </sequence-pattern>
</sequence-extract>

);

    return $text;
}

sub seq_fetch_examples
{
    # Niels Larsen, January 2011.
    
    # Gives examples. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Examples" );

    $text = qq (
$title

1. seq_fetch --seq pig.chr1 'contig1:200,500;3578,1067-' --outfile pig.out

   Fetches a small sub-sequence from pig chromosome 1, in different 
   orientations. The locator notation is 'ID:pos,length,orientation', where
   orientation is '+' (which can be omitted) or '-'. The last comma may
   also be omitted. If both position and length are omitted, the whole 
   sequence is returned. 

2. seq_fetch --seqfile pig_expr.fq --locfile locs.list --order

   Fetches many sequences given in a list that shares some ordering with the 
   sequence file. The list file may contain a mixture of ids and sub-sequence
   locators. 

3. cat locs.list | seq_fetch --seqfile pig_expr.fq --format json 

   Same as above, but takes locators from STDIN and prints in JSON format on 
   STDOUT. 

);

    return $text;
}

sub seq_fetch_features
{
    # Niels Larsen, January 2011.
    
    # Lists features.

    # Returns a string.

    my ( $text, $title, $formats );
  
    $title = &echo_info( "Features" );

    $formats = join ", ", sort keys %{ &Seq::Storage::format_fields("valid") };

    $text = qq (
$title

Feature highlights are,

* High speed. Based on the highly efficient Kyoto Cabinet from 
  http://fallabs.com. It scales to exabytes, and the disk and ram speeds 
  are the limitations, not the cpu or the software. It works very well in
  a multi-threaded environment and with SSD disks.

* FASTQ and single-line fasta input formats are supported. More as needed.

* Index files are small and fetching consumes only small amounts of resident
  ram. The index is memory mapped and loads quickly, but can take significant
  virtual ram depending on its size (see performance numbers).
  
* Easy locators that allows getting sub-sequence pieces in different 
  orientations. 

* Fetches from within storage or from external files, depending on switches 
  used when the index was created. 

* Order mode. When the ordering of input IDs significantly resemble that of
  the sequences of an external file, then fetch speed is much higher. 

* Outputs. These output formats are supported,

  $formats

  However note that fastq format can of course not be made from a fasta file,
  so these output options depend on which file has been indexed. Fields can 
  be de-selected unless required by the chosen format.

Obvious features are missing, see --help missing.

);

    return $text;
}

sub seq_fetch_intro
{
    # Niels Larsen, January 2011.
    
    # Returns a small fetch introduction and explains how to get more 
    # help. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Introduction" );

    $text = qq (
$title

Fetches sequences and sub-sequences from a single file that has bee indexed
by seq_index, at high speed and in different output formats. The index is 
based on Kyoto Cabinet from http://fallabs.com which scales to exabytes. 

These help options describe fetching further,

    --help features   Feature list
    --help examples   Commented examples
    --help perform    Performance numbers
    --help missing    Limitations and missing features

Options can be abbreviated, for example '--help p' will show performance
numbers.
);

    $text .= "\n". &Common::Messages::legal_message() ."\n";

    return $text;
}

sub seq_fetch_perform
{
    # Niels Larsen, March 2011.

    # Returns a small description of computer resource usage during typical 
    # indexing runs. 

    # Returns string.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title
$Num_source
Each fetch operation was done with file system cache ('hot') and without
('cold'). The first is RAM limited, the second is more limited by disk
speed. The locator list was ordered quite like the ids in the sequence 
file, so that the numbers reflect extremes.

Silva 16S with 260,000 sequences, 420 mb fasta file, 8.3 mb index, and 
fetching 100,000 sequences:

       Speed, order:  6.4 seconds hot, 10.0 seconds cold.
      Speed, random:  6.5 seconds hot, 9.8 seconds cold.
           Peak RAM:  72 mb.

Expression data, 16.2 million 35-long sequences, 1.5 gb fastq file,
index 490 mb, and fetching 100,000 sequences:

      Speed, order:  2.3 seconds hot, 3.8 seconds cold.
     Speed, random:  6.7 seconds hot, 198 seconds cold.
          Peak RAM:  390 mb.

Pig chromosome 1, one sequence, 295 mb fasta file, index 6.7 kb, fetching
100 fragments in different positions:

         Speed:  0.0029 seconds hot, 0.4 seconds cold.
      Peak RAM:  insignificant.

NOTE: Random disk seeks can take a lot of time with many sequences as in
the second example. If this is an issue, add more RAM or get an SSD disk.

);

    return $text;
}

sub seq_fetch_ebi
{
    # Niels Larsen, January 2011.

    # Lists EBI databases and formats.

    # Returns a string.

    my ( $sys_name, $text, $title, $stdout, @table, $table, $row );
  
    $title = &echo_info( "EBI datasets" );
    $sys_name = $Common::Config::sys_name;

    $text = qq (
 $title

 Below is a list of EBI dataset names and formats that can be given 
 as --db and --format respectively.

);

    &Common::OS::run3_command( "ebi_fetch getSupportedFormats", undef, \$stdout );

    @table = map { [ split "\t", $_ ] } split "\n", $stdout;

    @table = map { $_->[1] =~ s/^default,//; $_ } @table;

    unshift @table, [ "-----------", "-------" ];
    unshift @table, [ "EBI dataset", "Formats" ];

    $text .= join "\n", &Common::Tables::render_ascii( \@table, undef, 2 );
    $text .= "\n\n";

    return $text;
}

sub seq_index_examples
{
    # Niels Larsen, January 2011.
    
    # Gives seq_index examples. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Examples");

    $text = qq (
$title

1. seq_index seqdir1/*.fq seqdir2/*.fq

   Indexes a set of fastq files in the default mode, creating a set of 
   *.fastq.fetch files. The indexes created contain starting positions and
   lengths of every sequence entry, which is the default. There is one 
   index per sequence file.

2. seq_index seqdir/*.fq --fixed 

   Does the same as 1\), but the index contains integer entry numbers only.
   This makes for smaller index files.

3. seq_index seqdir/*.fq --within
 
   Creates indices that includes all data. The index becomes larger this
   way, but no external disk-seeks have to be done. A bad idea for long 
   sequences. 

4. seq_index seqdir/*.fq --suffix .proj27

   Indexes files the default way, but index files will be named with the 
   given suffix, that is a set of *.fq.proj27 files will be generated.

5. seq_index --about seqdir/xxx.fq.proj27 

   Lists index properties including index type number of sequences.

All options can be combined, except --within and --fixed (which applies 
only to external entries). 

);

    return $text;
}

sub seq_index_features
{
    # Niels Larsen, January 2011.
    
    # Returns description of features.

    # Returns a string.

    my ( $text, $title, $formats );
  
    $title = &echo_info("Features");
    $formats = join ", ", @{ &Seq::Storage::index_info_values( "formats", "fetch" ) };

    $text = qq (
$title

Feature highlights are,

*  High indexing speed, small file size and low resident memory usage.
   See the performance page.

*  Many files can be indexed with one command (see examples). The output
   files will have suffixes added, which are user controlled. This makes
   it easier to manage large file sets.

*  Supported input formats: $formats. The fasta format must have
   single-line sequences, convert with seq_convert if not. 

*  Different indexing modes, each optimized for different common use
   cases. See switches for more.

See also seq_derep, which efficiently de-replicates sequence.

);

    return $text;
}

sub seq_index_intro
{
    # Niels Larsen, January 2011.
    
    # Returns a small introduction and explains how to get more help. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Creates indices from sequence files access by seq_fetch. It works equally 
well expression-style short sequences and genomes, will process many files 
with one command and is low on computer resources. It uses the fast Kyoto 
Cabinet key/value storage from from http://fallabs.com.

These help options describe indexing further,

    --help features   Feature list
    --help examples   Commented examples
    --help switches   When to use which options
    --help perform    Performance numbers
    --help missing    Limitations and missing features
    --help credits    Thank you's and reference

Options can be abbreviated, for example '--help p' will show performance
numbers.
);

    $text .= "\n". &Common::Messages::legal_message() ."\n";

    return $text;
}

sub seq_index_perform
{
    # Niels Larsen, March 2011.

    # Returns a small description of computer resource usage during typical 
    # indexing runs. 

    # Returns string.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title
$Num_source
Each dataset below were indexed twice, both without file system cache 
('hot') and without ('cold'). The first is RAM limited, the second is 
limited by disk speed, and indeed those were the limits in each case.

Rfam, 1.1 million sequences, single 200 mb fasta file:

     Speed:  8.4 seconds hot, 17.5 seconds cold.
      Size:  30.5 mb in default mode.
       RAM:  130 mb virtual, resident ram increasing up to that.

Expression data, 16.2 million 35-long sequences, single 1.5 gb fastq file:

     Speed:  185 seconds hot, 195 seconds cold.
      Size:  410 mb in fixed mode, 490 in default mode
       RAM:  810 mb virtual, resident ram increasing linearly up to that.

Pig genome, 20 fasta files with 1 sequence each, 2.2 gb total:

     Speed:  67 seconds hot, 85 seconds cold.
      Size:  160 kb.
       RAM:  600 mb for the biggest chromosome.

);

    return $text;
}

sub seq_index_switches
{
    # Niels Larsen, March 2011.
    
    # Returns a small explanation of what the switches are good for.

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Switches");

    $text = qq (
$title

There are three kinds of indices,

1. Default mode. Indices contain start position and length for entries in their
   external files. This is the best choice for genomes, any variable-length 
   sequences and fixed-length of any significant length. Sequences may contain
   gaps, that is alignments should be indexed this way. 

2. Fixed size entries (--fixed option). Use this when all entries have exactly 
   the same size, like they have in a fastq file from a Solexa machine. Indices
   then contain only running integers for entry numbers, which makes it smaller
   and thus faster. This option is incompatible with --within. WARNING: using
   this option with a variable-sized file will make seq_fetch return garbage.

3. Data within (--within option). All data are put within the storage. The only
   advantage is that the file becomes independent of its sequence file and can
   be moved. Access is also faster in theory as there are no external lookups
   but in practice the larger storage size often make it slower because of more 
   swapping. This option the least good one. 

For most efficient operation the indices must be pre-configured with approximate
total number of sequences. The software finds that number in three ways,

1. The user sets it with the --seqmax option. It does not have to be set exactly,
   but better too high than too low. Specifying too few means slow indexing, too
   many produces a larger file, which is often acceptable.

2. Via the --fixed option. The first entry is then read in each file and the 
   number of entries inferred from that divided into the file size. 

3. Sequences are counted. This is always a safe way, but means the input files
   are read twice. 

);

    return $text;
}

sub seq_map_intro
{
    # Niels Larsen, January 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Pools a set of consensus files with read counts and creates a table map
of them. A table map has one sequence per row, the values are original 
read counts and each column corresponds to an input file. Read counts 
are summed up and can be scaled, so the total number of reads for each 
file are the same. The program includes a pooling step and a mapping 
step. 

For more descriptions,

    --help recipe       Prints a recipe template

Options can be abbreviated, for example '--help r' will print an input 
recipe template.

);

    return $text;
}

sub seq_map_recipe
{
    # Niels Larsen, January 2012.

    # Returns a configuration template for sequence similarity map.

    my ( %args,   
        ) = @_;

    # Returns a string.

    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Recipe template");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
# This is a cut-and-paste example of a pattern based demultiplex recipe,
# except values must be given and edited. The fields mean:
#
# title                         Short description to appear in outputs
# pool-method
# pool-minimum-read-count
# pool-minimum-sequence-length
# pool-minimum-similarity
# pool-minimum-nongaps
# map-method
# map-minimum-similarity
# scale-read-totals
# column-ids
# column-id-file
# column-id-pattern
#
# The section below, but also these comments, can be used in combination 
# with other sub-recipes and form larger recipes.

<consensus-table>
    title = Consensus table
    pool-method = exact
    seq-minimum-reads = 1
    seq-minimum-length = 20
    pool-minimum-similarity = 100%
    pool-minimum-nongaps = 5%
    pool-minimum-reads = 5
    pool-minimum-length = 20
    map-method = exact
    map-minimum-similarity = 95%
    map-scale-reads = yes
    column-ids = 
    column-id-pattern = 
    # column-id-file = 
</consensus-table>

);

    return $text;
}

sub seq_pool_intro
{
    # Niels Larsen, January 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Pools multiple files with consenses and creates a non-redundant set from 
those. If the inputs include original read-counts, then these are summed
up. There are two methods: normal clustering, which allows non-identity 
and different lengths, and simple de-replication where pooling only 
happens for identical sequences of same length. 

For more descriptions,

    --help recipe       Prints a recipe template

Options can be abbreviated, for example '--help r' will print an input 
recipe template.

);

    return $text;
}

sub seq_pool_recipe
{
    # Niels Larsen, January 2012.

    # Returns a configuration template for pooling consenses. 

    # Returns a string.

    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Consensus-pool recipe");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
<consensus-pooling>
    title = Consensus pooling
    minimum-reads = 1
    minimum-length = 20
</consensus-pooling>

);

    return $text;
}

sub seq_simrank_examples
{
    # Niels Larsen, September 2012.
    
    # Returns description of features.

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Usage examples");

    $text = qq (
$title

Compare a FASTQ formatted file against Greengenes, RDP or Silva, with 
all default settings,

   seq_simrank query.fq --dbfile db.fa --otable query.fq.tab

Same as above, but skipping bad qualities,

   seq_simrank (as above) --minqual 95 --qualtype Sanger

And getting the best 1% of all similarities down to 30%,

   seq_simrank (as above) --minsim 30 --topsim 1

Force the number of CPU cores (default all available),

   seq_simrank (as above) --cores 4

Increase the number of query input splits to save RAM, should be set 
to a multiplum of the number of cores,

   seq_simrank (as above) --splits 16

Most of the RAM usage that cannot be controlled this way is due to 
accumulation of results, all of which at the moment is held in memory 
until output tables are written and merged. Similarity lists can become 
very long, especially if there are many identical or highly similar 
sequences in the reference dataset. But reference datasets should be
de-replicated or even clustered to 99% for example.

);

    return $text;
}

sub seq_simrank_features
{
    # Niels Larsen, September 2012.
    
    # Returns description of features.

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Features");

    $text = qq (
$title

Feature highlights are,

*  Quality handling. Positions below a set quality value can be skipped.
   Ignoring low-quality spots in otherwise good sequences makes a clear
   difference. All similarity encodings are supported. N's are also 
   skipped over by default. 

*  Low similarities. The output includes the best n% matches no matter 
   how poor they are. In other programs there is a choice between either
   high similarities or a huge number of them.

*  Auto-parallelization. Unless prevented by the user, all available CPU
   cores will be used to each run a part of the query data. It works by 
   splitting the input into quickly loadable pieces in a scratch 
   directory.

*  Unique words. An oligo that occurs multiple times in a sequence is 
   only counted once. This makes the method less sensitive to sequence 
   anomalities and composition bias.

*  Good performance. It is written in Perl but with speed-critical spots
   isolated into C-routines. Both speed and RAM usage is quite acceptable
   and controllable by settings, see --help perform for more.

There are also a number of smaller features, each with their options, 
see --help settings.

);

    return $text;
}

sub seq_simrank_intro
{
    # Niels Larsen, September 2012.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Finds oligo-based similarities between sequences in a query file and 
a dataset file with reference sequences. Output is a table of matches 
with percentages. The method is reasonably fast, handles qualities
and will use available CPU cores. It will not work for proteins yet.

To calculate similarity between sequences A and B, each are converted to
a list of unique "words" (or "k-mers") that are short sub-sequences of a 
fixed length in the 6-12 range. The similarity is then simply the number
of common words divided by the smallest set of words in either. This 
ratio is then multiplied by 100 to become a percentage. 

This percentage is very different from normal sequence similarity based 
on mismatches on single positions, and there is no straight relationship
between the two: if with word-length 8 every 8th base position is a 
mismatch, the oligo-percent is then zero, but the similarity percent 
is 87.5. In practice, however, the conservation patterns do not very 
much between reference sequences, and the method is robust, it always 
pulls out the best reference matches.

These help options have more descriptions,

    --help features
    --help examples
    --help settings
    --help perform
    --help limits

Options can be abbreviated, for example '--help p' will print the 
section with performance.

);

    return $text;
}

sub seq_simrank_limits
{
    # Niels Larsen, September 2012.
    
    # Returns description of limitations.

    # Returns a string.

    my ( $text, $typ_title, $len_title, $tot_title );
  
    $typ_title = &echo_info("Sequence type");
    $len_title = &echo_info("Sequence length");
    $tot_title = &echo_info("Sequence totals");

    $text = qq (
$typ_title

No proteins, only DNA/RNA sequences. This could be added however, please
let us know if interested.

$len_title

Word size 8 is good for 16S rRNA, but up to word-size 12 is allowed, and
higher could be implemented. Word size 12 would accommodate virus genomes,
for example, or regions on larger genomes. However the method is not good
for comparing large genomes, or for mapping short reads onto genomes (but
are good tools for that). The query and reference sequences should be 
comparable in length, perhaps within 10-100 times length difference or 
so. The method is intended for comparing many query sequences against 
many reference sequences of the same type.

$tot_title

There are no hard limits on the number of either query or reference 
sequences. Well of course there is, but they will not be reached before 
the author has long retired.

);

    return $text;
}

sub seq_simrank_perform
{
    # Niels Larsen, September 2012.
    
    # Returns description of features.

    # Returns a string.

    my ( $text, $run_title, $ram_title );
  
    $run_title = &echo_info("Speed");
    $ram_title = &echo_info("Memory");

    $text = qq (
$run_title

With word size 8 and step length 4, a dataset of 250k 16S sequences will
on a single CPU-core take 60-90 minutes against a dataset of 1.5 million
500-long reference sequences. On an 8-core machine that run time will be
around 10 minutes. Run-time is roughly linearly proportional to the query
sequence volume, and to the reference sequence volume (i.e. the number 
of bases). Run-time is inversely proportional to step length, whereas 
longer words only have a moderate speed advantage.

$ram_title

RAM usage very much depends on the --splits setting, and the number of 
output matches. This again depends on the datasets. But in the above 
example, total resident RAM started at 500 MB and crept up till about 
2 GB by the end of the run. If this is a problem, use more --splits, 
that will decrease ram at the expense of some 10-30% of run-time. These
numbers was with an un-replicated dataset, and with a reference dataset
with no identical sequences the RAM usage will be at least one third 
less, maybe more. 

);

    return $text;
}

sub seq_simrank_settings
{
    # Niels Larsen, September 2012.
    
    # Returns description of non-obvious or functionally important settings.

    # Returns a string.

    my ( $text, $title, @names );
  
    $title = &echo_info("Settings");

    @names = &Seq::Common::qual_config_names();

    $text = qq (
$title

Functionally relevant settings are,

 *  Word control. The --wordlen option sets the length of a word, which
    must be in the 6-12 range, but up to 15 could be allowed if someone
    needs that (there is a RAM issue preventing that, which could be 
    removed). The --steplen option sets step length, so that if at 4, 
    only every 4th position will be used, i.e. 4 positions are skipped 
    when forming words. The program runs 4 times faster at 4 than at 1, 
    and usually not much sensitivity is lost by setting it to 2, 3 or 4,
    but this depends on both query and reference data. 

 *  Query direction. The --forward (default on) and --reverse contol if 
    one or both query sequence directions should be checked. Like all 
    toggles, each option has a 'no' version: --noforward will skip 
    forward matching. 

 *  Input indels. Both query and reference may have embedded indels in 
    their sequences, which will then the removed with the --degap and 
    --dbdegap options respectively. Only periods (missing data), dashes
    (alignment gaps) and tilde (end-of-molecule) characters are deleted.
    It is best for both storage and speed to have no indels. This method 
    used unaligned sequences and does not align them to calculate 
    similarities. 

 *  Qualities. The --qualtype option specifies encoding, which can be one
    of these,

);
    map { $text .= "    $_\n" } @names;

    $text .= qq (
    The --minqual option is a percentage below which a base is skipped 
    and oligo-words that include those will not be formed. 

 *  Input filtering. The --minlen and --dbminlen options skips shorter 
    query and reference sequences respectively. The --filter and --dbfilter
    options includes only sequences that have a header annotation string
    that match the given quoted perl expressions. The --wconly excludes 
    forming words that involve non-canonical bases including N's, and is
    on by default. 

 *  Similarity control. All matches in the output have at least the 
    word-percentage set by --minsim. This word-percent can be set as low 
    as 30% or 25%, which would make other programs such as blast create 
    large outputs. But the --topsim option takes only the desired range 
    off the top of the list of similarities, however good or bad they are.
    For example, if set to 2, only similarities from 98-100%, 50-52%, 
    whatever the best matches are, will be shown. 

 *  Caching. If --dbcache is given then reference dataset cache files are 
    written. With an argument to --dbcache, that argument becomes the 
    directory with the cache files. Without an argument, the directory 
    will be the output table name with ".simrank_cache" appended. These 
    cache files speed up matching of a single or a few query sequences,
    but they are 10-20 times larger than the dataset sequence file.

 *  Output control. The output is a tab-separated table with three columns:
    query id, number of words, matches. The last column is a blank-separated
    list of reference-id / similarity-percent tuples. The --maxout option 
    limits the number of tuples to a set number. With --numids, query ids 
    become running integers. The --simfmt controls the number of decimal 
    places in the similarity percentages.

More operational settings are,

 *  Parallelization. The --splits option controls the number of pieces to
    split the query data into. If left off, the number of pieces will be a 
    multiple of the number of cores, so that no piece is larger than 100 MB.
    If set to zero or one, no splitting or parallelization is done, but 
    then RAM usage may be high. With --splits > 1, the --cores option sets
    the number of cores used, available or not.

 *  RAM usage. The --splits option partions the query input, more splits
    means less RAM. The --readlen and --dbread options determine how many 
    sequences are read into memory at a time, and by lowering these RAM is
    reduced and run-time somewhat increased. Generally, use the available
    RAM.

);

    return $text;
}

# sub seq_pool_map_intro
# {
#     # Niels Larsen, January 2012.

#     my ( $text, $title );
  
#     $title = &echo_info("Introduction");

#     $text = qq (
# $title

# Matches a set of sequence files against a union of all 
# Pools multiple files with consenses and creates a non-redundant set from 
# those. If the inputs include original read-counts, then these are summed
# up. There are two methods: normal clustering, which allows non-identity 
# and different lengths, and simple de-replication where pooling only 
# happens for identical sequences of same length. 

# For more descriptions,

#     --help recipe       Prints a recipe template

# Options can be abbreviated, for example '--help r' will print an input 
# recipe template.

# );

#     return $text;
# }

# sub seq_pool_recipe
# {
#     # Niels Larsen, January 2012.

#     # Returns a configuration template for pooling consenses. 

#     # Returns a string.

#     my ( $text, $title );

#     if ( -t STDOUT )
#     {
#         $title = &echo_info("Consensus-pool recipe");
#         $text = qq (\n$title\n);
#     }
#     else {
#         $text = "";
#     }

#     $text .= qq (
# <consensus-pooling>
#     title = Consensus pooling
#     minimum-reads = 1
#     minimum-length = 20
# </consensus-pooling>

# );

#     return $text;
# }

1;

__END__
