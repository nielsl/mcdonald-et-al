package Recipe::Docs;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @EXPORT_OK );
require Exporter;

@EXPORT_OK = qw (
                 %Docs_map
                
);

use Common::Config;
use Common::Messages;

our ( %Docs_map );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> STEP SUMMARIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

%Docs_map = (
    "alignment-consensus" => {
        "summary" => qq (
Creates consenses from alignments, with one of three different methods.
The default is to write ambiguity code into the consenses that includes
the most sequences. That is, if there are 80 A', 15 G's and 5 C's in a 
given column, then the code becomes an R if at least 95% of sequences 
are included, above 95% it would be a V.
),
    },
    "consensus-table" => {
        "summary" => qq (
Pools consenses with read counts into a consensus map table. The input is a 
set of files, one for each sample, with consensus sequences that were extracted
from each their alignment and which therefore has a original read count. The 
output table has as many rows as there are different consenses in all files, 
and each column is a sample. The table values are summed up counts for each 
consensus. This intermediate step avoids running the same sequence against 
a database later for example, good for Illumina where many identical 
sequences occur in different samples.
),
    },
    "consensus-table-clustering" => {
        "summary" => qq (
Clusters and filters a consensus map table and produces a new consensus map 
table with fewer rows. Reduction can be done by similarity clustering, minimum 
sequence length and minimum row value. The new consenses can either contain 
most frequent redidues or have ambiguity codes.
),
    },
    "organism-taxonomy-profiler" => {
        "summary" => qq (
Maps similarities onto a reference organism taxonomy and creates a binary
profile. Similarities can be filtered by oligo-totals (=~ sequence length),
by minimum value, by top range and a weighting option controls how to treat 
less good matches relative to the best ones.
),
    },
    "organism-profile-format" => {
        "summary" => qq (
Filters and formats a multi-sample organism taxonomy profile into a set of 
tables. Outputs are HTML and text tables of scores unmodified, normalized 
scores, scores summed across all parents, and summed normalized tables. The 
input profile can be filtered by OTU  name expressions, taxonomy level, row 
score sums and minimum score values. 
),
    },
    "organism-profile-merge" => {},
    "sequence-chimera-filter" => {
        "summary" => qq (
This method measures chimera-potential of single-gene DNA sequences against a
well-formed reference dataset without aligning. Outputs are score tables plus 
a chimera- and non-chimera sequence files. The method runs slightly faster,
uses uses slightly less memory and has at least as good sensitivity as the 
closed-source uchime. Only two-fragment chimeras are detected at present, 
although triple-fragment usually also receive high scores. By default all 
available CPU cores are used.
),
    },
    "sequence-cleaning" => {
        "summary" => qq (
Cleans, filters and trims sequences in various ways. Ends can be trimmed by
complete or partial sequence match, pattern match and quality match. They 
can be filtered by overall quality and length, and sub-sequences extracted.
See under "steps" in the table below for more detailed statistics for each 
sample.
),
    },
    "sequence-clip-pattern-end" => {},
    "sequence-clip-pattern-start" => {},
    "sequence-clustering" => {
        "summary" => qq (
Clusters sequences by similarity while preserving original read counts. 
The output is a set of files with multiple alignments per sample.
),
    },
    "sequence-conversion" => {
        "summary" => qq (
Converts differt input formats such as .sff to .fastq, which this package 
uses as its native format. Read counts and other information is written into
the '+' line.
),
    },
    "sequence-demultiplex" => {
        "summary" => qq (
Separates sequences into files based on barcodes and/or primers. Primer 
matching allows mismatches/indels; position and quality criteria can be 
applied to barcode matching; forward/reverse sequences can be pooled or 
treated as separate; paired ends are handled; sub-sequences can be
extracted and optionally complemented. The primers.txt file shows the 
configuration for this run.
),
    },
    "sequence-demultiplex-fluidigm" => {
        "summary" => qq (
Adds another level of de-multiplexing: the de-multiplexed files are matched
with a set of phylogenetic primers and separated into directories, one per 
phylogenetic group. For each group there are sets of files with sequences 
that match the forward and reverse primers for the group, as well as for 
both of these in combination. 
),
    },
    "sequence-dereplication" => {
        "summary" => qq (
Uniqifies identical sequences and their qualities (if any). The best quality 
is kept for each position in the identical sequences. It is used as a fast 
and crude pre-clustering step that often greatly saves computer resources. 
),
    },
    "sequence-extract" => {},
    "sequence-filter" => {
        "summary" => qq (
Filters sequences by pattern, length and/or GC-content. 
),
    },
    "sequence-filter-quality" => {
        "summary" => qq (
Filters sequences by minimum quality and stringency.
),
    },
    "sequence-id-filter" => {},
    "sequence-info-filter" => {},
    "sequence-join-pairs" => {
        "summary" => qq (
Joins sequence pair mates, overlapping or not. The join allows no gaps, 
only a maximum mismatch percentage (default 80%) and overlap length (20
as default). The highest quality and its base prevails in the joined 
sequence. When there are no overlaps, e.g. the amplicon is too long, 
the two reads are concatenated with or without quality trimming at the 
ends. No N's are inserted, but the break point is remembered. 
),
    },
    "sequence-mates-filter" => {
        "summary" => qq (
Filters paired-end sequence files so the output has identical barcodes 
in both directions. A maximum barcode starting position can be given
\(default 3\).
),
    },
    "sequence-pattern" => {
        "summary" => qq (
Some description here
),
    },
    "sequence-rarefaction" => {
        "summary" => qq (
Extracts a fixed number of sequences, scattered evenly throughout a given
file. Can also extract, in the same way, as many sequences as there are
in the file that contains the least.
),
    },
    "sequence-region" => {},
    "sequence-remove-pattern" => {},
    "sequence-similarities-simrank" => {
        "summary" => qq (
Creates similarities between query sequences and a reference dataset. To
measure similarity between sequences A and B, each are converted to a list
of unique "words" (or "k-mers") that are short sub-sequences of a fixed 
length in the 6-15 range. The similarity is then simply the number of common
words divided by the smallest set of words in either. This ratio is then 
multiplied by 100 to become a percentage. The method is reasonably fast 
(much faster than blast), and can use all available CPU's and cores. It 
will return the best similarities even if they are poor and will skip poor
quality bases in the query sequence (no other program can do this, yet it 
clearly improves the final analysis).
),
    },
    "sequence-trim-end" => {
        "summary" => qq (
Trims sequence ends by overlap with a given sequence probe. The probe slides 
into the sequence and the best match position is used for clipping. Search 
distance, minimum length and strictness can be set. 
),
    },
    "sequence-trim-start" => {
        "summary" => qq (
Trims sequence starts by overlap with a given sequence probe. The probe slides 
into the sequence and the best match position is used for clipping. Search 
distance, minimum length and strictness can be set. 
),
    },
    "sequence-trim-quality-end" => {
        "summary" => qq (
Trims sequence ends by quality within a window. A window of a given length 
slides into the sequence and when the specified window quality and strictness 
is met, the sliding stops and the sequence is clipped and quality-trimmed at
that position. 
),
    },
    "sequence-trim-quality-start" => {
        "summary" => qq (
Trims sequence starts by quality within a window. A window of a given length 
slides into the sequence and when the specified window quality and strictness 
is met, the sliding stops and the sequence is clipped and quality-trimmed at
that position. 
),
    },
    );

1;

__END__
