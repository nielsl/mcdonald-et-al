package Recipe::Params;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use feature "state";
use Tie::IxHash;

use vars qw ( @EXPORT_OK );
require Exporter;

@EXPORT_OK = qw (
                 $Params
);

use Common::Config;
use Common::Messages;

use Seq::Common;
use Taxonomy::Config;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $minlen, $maxlen );
our ( %Param_map, @DB_names  );

$minlen = 1;
$maxlen = 70;

push @DB_names, @Taxonomy::Config::DB_names;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> RECIPE PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# These are step parameter definitions. They can appear in different steps,
# next section.

%Param_map = (
    "author" => {
        "minlen" => $minlen, "maxlen" => $maxlen, "defval" => "Someone's name",
        "desc" => qq (
Name of person or entity, up to $maxlen long. This name will appear in the 
header of the HTML statistics outputs, and on the console.
),
    },
    "alignment-suffix" => {
        "desc" => qq (
File name suffix for output alignment files.
),
    },
    "bar-file" => {
        "perm" => "r",
        "descn" => qq (
Barcode file name path. Paths can be relative and must exist as seen 
from the location of the recipe. A barcode file is a table like this 
made up example, with any number of lines,

# ID F-tag R-tag
Name-1 GAGGCTAC GTGCGTAC
Name-1 GAGGCCAC GTGCGCAC

The first line must contain one or more of three column labels that 
must literally be ID, F-tag and R-tag. They can come in any order, but
at least one of F-tag or R-tag must be present. Tag sequences are used
in output file names, and so are the names. If names are omitted 
numbers are used instead. 
),
    },
    "bar-label" => {
        "vals" => ["F-tag","R-tag"],
        "defval" => "F-tag",
        "desc" => qq (
Barcode names that must be in the first title line of a barcode file. This 
The first title line should start with "#" and have only "ID", "F-Tag" or 
"R-tag" in it.
),
    },
    "bar-quality" => { "defval" => 99.9 },
    "bar-spacing" => { "defval" => 1 },
    "bar-start-offset" => { "defval" => 2 },
    "overlap-alignment-size" => {
        "minval" => 1,
        "defval" => 3,
        "desc" => qq (
The minimum alignment size for it to be checked for being chimeric. The size
means number of aligned sequences, or original reads if the overlap-orig-counts
setting key is set. 
),
    },
    "cluster-program" => { "defval" => "uclust" },
    "cluster-arguments" => {},
    "overlap-minimum-score" => {},
    "overlap-disjunct-matches" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "overlap-off-percent" => {
        "defval" => "60%",
    },
    "overlap-off-proportion" => { "defval" => "10%" },
    "overlap-off-sequences" => { "defval" => "60%" },
    "overlap-orig-counts" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "overlap-reclustering" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "column-ids" => {},
    "column-id-pattern" => {},
    "column-id-file" => {},
    "consensus-method" => {
        "vals" => ["most_frequent","most_frequent_any","least_ambiguous"],
        "defval" => "most_frequent",
        "desc" => qq (
Three consensus methods work: 
1\) most_frequent, use the most frequent non-gap character. 
2\) most_frequent_any, take the most frequent column character, whatever 
that is, even if it is an indel character. 
3\) least_ambiguous, add redundancy codes to the consensus string. For example,
if a column contains mostly A's and G's, then an R shows and so on. The 
number of sequences that should be covered by these redundancy codes are 
added can be controlled by the minimum-ambiguity-coverage key: if there 
are, say, 60% A's and 30% G's and minimum coverage is set to 80%, then 
there will be an R. But had it been set to just 60% an A would have been 
in the consensus, because A's cover 60% of all residues in that column.
),
    },
    
    "dataset-name" => { "vals" => [ @DB_names ] },
    "dataset-file" => {},
    "debug-output" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "decimal-places" => { "minval" => 0, "defval" => 0 },
    "delete-inputs" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "search-distance" => { "minval" => 1 },
    "email" => { "minlen" => $minlen, "maxlen" => $maxlen },
    "file" => {},
    "forward" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "forward-primer" => {},
    "from-position" => {},
    "get-elements" => { "split" => 1, "defval" => 1 },
    "get-orient" => { "vals" => ["forward","reverse"], "defval" => "forward" },
    "include-match" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "include-misses" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "include-primer" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "include-singlets" => { "vals" => [ "yes", "no" ] },
    "input-file-filter" => {},
    "input-sequence-format" => { "vals" => [ "sff", "fasta", "fastq" ], "defval" => "fastq" },
    "input-step" => {},
    "keep-outputs" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "map-method" => { "vals" => [ "similar", "exact" ], "defval" => "exact" },
    "map-minimum-similarity" => { "minval" => 50, "maxval" => 100, "defval" => "95%" },
    "map-scale-reads" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "match-agct-only" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "match-both" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "match-idfile" => {},
    "match-filter" => {},
    "match-forward" => { "vals" => [ "yes", "no" ], "defval" => "yes" },
    "match-minimum" => { "minval" => 20, "maxval" => 100, "defval" => 60 },
    "match-reverse" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "match-step-length" => { "minval" => 1, "defval" => 1 },
    "match-top-range" => { "minval" => 0, "maxval" => 100, "defval" => 3 },
    "match-use-range" => { "minval" => 0, "maxval" => 100, "defval" => 1 },
    "match-weight" => { "minval" => 0, "maxval" => 10, "defval" => 1 },
    "match-word-length" => { "minval" => 6, "maxval" => 10, "defval" => 8 },
    "maximum-ambiguity-level" => { "minval" => 0, "defval" => 1 },
    "maximum-columns-fail" => { "minval" => 0, "maxval" => 100, "defval" => 5 },
    "maximum-columns-quality-fail" => { "minval" => 0, "maxval" => 100, "defval" => 5 },
    "maximum-distance" => { "minval" => 0 },
    "maximum-length" => { "minval" => 1 },
    "maximum-gc-content" => { "minval" => 0 },
    "maximum-quality" => { "minval" => 0, "maxval" => 100, "defval" => 100 },
    "maximum-ram" => { "defval" => "20%" },
    "maximum-sequences" => { "minval" => 1, "defval" => 1 },
    "maximum-strict" => { "minval" => 0, "maxval" => 100, "defval" => "100%" },
    "method" => {},
    "merge-orientations" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "minimum-ambiguity-coverage" => { "minval" => 0, "maxval" => 100, "defval" => 0 },
    "minimum-base-quality" => { "minval" => 50, "maxval" => 100, "defval" => "99.9%" },
    "minimum-cluster-size" => { "minval" => 1, "defval" => 2 },
    "minimum-gc-content" => { "minval" => 0, "defval" => "0%" },
    "minimum-group-percent" => { "minval" => 51, "defval" => "90%" },
    "minimum-length" => { "minval" => 1, "defval" => 15 },
    "minimum-non-gaps" => { "minval" => 1, "maxval" => 100, "defval" => 5 },
    "minimum-oligo-count" => { "minval" => 1, "defval" => 1 },
    "minimum-overlap" => { "minval" => 5, "defval" => 15 },
    "minimum-parent-length" => { "minval" => 50, "defval" => 80 },
    "minimum-quality" => { "minval" => 0, "maxval" => 100, "defval" => "99%" },
    "minimum-quality-conservation" => { "minval" => 0, "maxval" => 100, "defval" => 0 },
    "minimum-read-sum" => { "minval" => 1, "defval" => 1 },
    "minimum-score" => {},
    "minimum-seed-similarity" => { "minval" => 50, "maxval" => 100, "defval" => 100 },
    "minimum-sequences" => { "minval" => 1, "defval" => 1 },
    "minimum-sequence-conservation" => { "minval" => 0, "maxval" => 100, "defval" => 0 },
    "minimum-similarity" => { "minval" => 50, "maxval" => 100, "defval" => 100 },
    "minimum-strict" => { "minval" => 0, "maxval" => 100, "defval" => "95%" },
    "non-match-idfile" => {},
    "non-match-filter" => {},
    "normalized-column-total" => { "minval" => 1, "defval" => 100000 },
    "output-barcode-names" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "output-mismatches" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "output-name" => {},
    "output-sequence-format" => { "vals" => [ "fasta", "fastq" ], "arg" => "oformat", "defval" => "fastq" },
    "pair-files1" => {},
    "pair-files2" => {},
    "pairs-table" => { "perm" => "r" },
    "pattern-orient" => { "vals" => ["forward","reverse"], "defval" => "forward" },
    "pattern-string" => {},
    "pattern-string-nomatch" => {},
    "phone" => { "minlen" => $minlen, "maxlen" => $maxlen },
    "pool-method" => { "vals" => [ "similar", "exact" ], "defval" => "exact" },
    "pool-minimum-length" => { "minval" => 1, "defval" => 20 },
    "pool-minimum-non-gaps" => { "minval" => 0, "maxval" => 100, "defval" => 5 },
    "pool-minimum-reads" => { "minval" => 1, "defval" => 1 },
    "pool-minimum-similarity" => { "minval" => 50, "maxval" => 100, "defval" => "100%" },
    "primer-file" => { "perm" => "r" },
    "primer-table" => { "perm" => "r" },
    "quality-type" => { "vals" => [ keys &Seq::Common::qual_config() ], "defval" => "Illumina_1.8" },
    "read-buffer" => { "minval" => 1 },
    "reference-database" => {},
    "reference-sequence" => {},
    "reference-molecule" => {},
    "reverse" => { "vals" => [ "yes", "no" ], "defval" => "no" },
    "reverse-primer" => {},
    "run-parallel-cores" => { "minval" => 1 },
    "seq-minimum-length" => { "minval" => 1, "defval" => 15 },
    "seq-minimum-reads" => { "minval" => 1, "defval" => 1 },
    "sequence" => { "minlen" => 1, "needed" => 1 },
    "sequence-region" => {},
    "show-level" => {},
    "site" => { "minlen" => $minlen, "maxlen" => $maxlen },
    "skype" => { "minlen" => $minlen, "maxlen" => $maxlen },
    "step-length" => { "minval" => 1, "defval" => 1 },
    "summary" => {},
    "table-title-file" => { "perm" => "r" },
    "table-title-regex" => {},
    "taxonomy-minimum-score" => { "minval" => 1, "defval" => 1 },
    "taxonomy-minimum-sum" => { "minsum" => 1, "defval" => 1 },
    "taxonomy-text-filter" => {},
    "title" => {
        "minlen" => $minlen,
        "maxlen" => $maxlen,
        "desc" => qq (
Title of step or recipe, up to $maxlen long. This title will appear in the 
header of the HTML statistics outputs, and on the console.
)
    },
    "to-position" => {},
    "trim-end" => { "vals" => [ "yes", "no" ] },
    "trim-start" => { "vals" => [ "yes", "no" ] },
    "write-failed" => { "vals" => [ "yes", "no" ] },
    "write-forward" => { "vals" => [ "yes", "no" ] },
    "write-reverse" => { "vals" => [ "yes", "no" ] },
    "write-pairs" => { "vals" => [ "yes", "no" ] },
    "web" => { "minlen" => $minlen, "maxlen" => $maxlen },
    "window-length" => { "minval" => 1, "arg" => "winlen", "defval" => 10 },
    "window-match" => { "minval" => 1, "arg" => "winhit", "defval" => 9 },
    "word-length" => { "minval" => 6, "maxval" => 10, "defval" => 8 },
    "zip-outputs" => { "vals" => [ "yes", "no" ] },
    );

sub help_map
{
    # Niels Larsen, May 2012.

    my ( $key,        # Params key - OPTIONAL
         $msgs,       # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( $msg, %hash );

    if ( $key )
    {
        if ( exists $Param_map{ $key } )
        {
            %hash = %{ $Param_map{ $key } };

            return \%hash;
        }
        else
        {
            $msg = qq (Step key not found in dictionary -> "$key");

            if ( $msgs ) {
                push @{ $msgs }, ["ERROR", $msg ];
            } else {
                &error( $msg );
            }
        }
    }

    return wantarray ? %Param_map : \%Param_map;
}

1;

__END__
