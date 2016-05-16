package Ali::Help;     #  -*- perl -*-

# Sequence related help texts. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &dispatch
                 &ali_cons_examples
                 &ali_cons_filters
                 &ali_cons_intro
                 &ali_cons_methods
                 &ali_cons_recipe
                 &ali_credits
                 &ali_fetch_examples
                 &ali_fetch_features
                 &ali_fetch_intro
                 &ali_fetch_perform
                 &ali_fetch_ebi
                 &ali_index_examples
                 &ali_index_features
                 &ali_index_intro
                 &ali_index_perform
                 &ali_index_switches
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Widgets;

our $Sys_name = $Common::Config::sys_name;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub dispatch
{
    # Niels Larsen, April 2011.

    # Dispatch different help page requests. The first argument is the
    # program name that invoked it, then second is the type of help to 
    # be shown. If "ali_fetch" is given as first argument and "intro"
    # as the second, then the routine ali_fetch_intro is invoked, and 
    # so on.

    my ( $prog,           # Program string like "ali_fetch"
         $request,        # Help page name like "intro" - OPTIONAL, default "intro"
         ) = @_;

    # Returns a string. 

    my ( %requests, $text, $routine, $choices, @msgs, $opts, @opts );

    %requests = (
        "ali_cons" => [ qw ( credits intro methods filters examples recipe ) ],
        "ali_fetch" => [ qw ( credits intro examples features perform missing ) ],
        "ali_index" => [ qw ( credits intro examples features perform missing ) ],
        );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $request ||= "intro";

    if ( $opts = $requests{ $prog } )
    {
        @opts = grep /^$request/i, @{ $opts };

        if ( scalar @opts != 1 )
        {
            $choices = join ", ", @{ $opts };

            if ( scalar @opts > 1 ) {
                @msgs = ["ERROR", qq (Help request is ambiguous -> "$request"; choices are $choices) ];
            } else {                
                @msgs = ["ERROR", qq (Unrecognized help request; choices are $choices) ];
            }

            &Common::Messages::append_or_exit( \@msgs );
        }
    }
    else {
        &error( qq (Wrong program string -> "$prog") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DISPATCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $opts[0] eq "credits" ) {
        $routine = "Ali::Help::ali_credits";
    } else {
        $routine = "Ali::Help::$prog" ."_$opts[0]";
    }

    no strict "refs";
    $text = &{ $routine };

    if ( defined wantarray ) {
        return $text;
    } else {
        print $text;
    }

    return;
}

sub ali_cons_examples
{
    # Niels Larsen, May 2011.

    # Describes different ways of making consenses. 

    my ( $name,
        ) = @_;

    # Returns a string. 

    my ( $text, $title );

    $title = &echo_info( "Examples" );
    
    $text = qq (
$title

1. ali_consensus alidir/*.cluali

   A perhaps large number of uclust alignment outputs are being processed with 
   default settings. The outputs are named as the input files, but with ".confa"
   and ".contab" suffixes added.

2. ali_consensus large.cluali --method least_ambiguous --ambcover 90 --minlen 25 

   Default output files are written, but IUB ambiguity codes are inserted where
   needed to cover at least 90% of the residues in a given columns (that is, if 
   there is higher conservation there is no need to insert any). All printed 
   consenses are at least 25 long.

);

    return $text;
}
    
sub ali_cons_filters
{
    # Niels Larsen, May 2011.

    # Describes different ways of making consenses. 

    my ( $name,
        ) = @_;

    # Returns a string. 

    my ( $text, $filter_title );

    $filter_title = &echo_info( "Filters" );
    
    $text = qq (
$filter_title

There are different ways to filter and reduce the output:

1. Alignment skipping. With the --minseqs option alignments can be ignored 
   with the given number of sequences in them. If the sequences themselves are 
   consenses, then the original number of sequences will be used as criteria.

2. Column splicing. Columns with a very high gap-proportion can be ignored 
   with the --minres option, where the minimum residue percentage can be set.
   Again, the original number of sequences are being used if present, otherwise
   each counts as one. 

3. Masking. Columns with high/low sequence or quality variations cannot be 
   excluded, but they can be masked with the --mincons, --minqual and --minqcons
   options. Masks are then produced in the output for the user to see, and for
   filtering the output.

4. Trimming of ends. The ends can be trimmed with the --trimbeg and --trimend
   options. They will remove low conservation and/or quality columns from the 
   respective ends.

5. Output filtering. The --maxfail and --maxqfail options constrain the maximum
   percentage of overal sequence variability and quality in a consensus; if it
   is lower, then it will not be in the output. The --minlen sets a minimum
   length.

);

    return $text;
}
    
sub ali_cons_methods
{
    # Niels Larsen, May 2011.

    # Describes different ways of making consenses. 

    my ( $name,
        ) = @_;

    # Returns a string. 

    my ( $text, $methods_title );

    $methods_title = &echo_info( "Methods" );
    
    $text = qq (
$methods_title

The program can derive consenses in these different ways, controlled 
by the --method option,

1. Uses the most frequent non-gap character. This is the default and 
   the argument is called "most_frequent". 

2. Takes the most frequent column character, whatever that is. This 
   happens if the argument "most_frequent_any" is given. 

3. Adds redundancy codes to the consensus string. For example, if a 
   column contains mostly A's and G's, an R shows. The extent to which
   these redundancy codes are added can be controlled by the --ambcover
   option: if there are, say, 60% A's and 30% G's and --ambcover is set
   to 80%, then there will be an R. But had it been set to just 60% an
   A would have been in the consensus, because A's cover 60% of all 
   residues in that column.

);

    return $text;
}
    
sub ali_cons_intro
{
    # Niels Larsen, September 2006.

    # Returns a small usage background to consensus calculation. The command 
    # line arguments are explained in the script. 

    my ( $name,
        ) = @_;

    # Returns a string. 

    my ( $text, $title, $legal_title, $credits_title );

    $title = &echo_info( "Introduction" );
    $legal_title = &echo_info( "License and Copyright" );
    $credits_title = &echo_info( "Credits" );

    $text = qq (
$title

Creates consensus files from files with multiple alignments. The programs
purpose is to distill reliable sequences from large numbers of alignments,
so that higher-level analyses are not polluted by artefacts and low quality.
There are a number of filtering and trimming options, sequence counts and 
qualities are forwarded to the output. 

Input files are Input files can be PDL alignments, pseudo-fasta (gapped 
sequences) and uclust alignments. Outputs will be named as the inputs, 
but with ".confa" (fasta) and/or ".contab" (table) suffixes appended. 

These help options describes consensus generation further,

    --help methods
    --help filters 
    --help examples
    --help recipe

Options can be abbreviated, for example '--help m' will show methods.

);

    return $text;
}

sub ali_cons_recipe
{
    # Niels Larsen, January 2012. 

    my ( $text, $title );

    if ( -t STDOUT )
    {
        $title = &echo_info("Consensus recipe");
        $text = qq (\n$title\n);
    }
    else {
        $text = "";
    }

    $text .= qq (
# This is a consensus configuration template. Values may be changed, 
# added or removed. The section below, but also these comments, can
# be used in combination with other sub-recipes and build larger 
# ones.

<alignment-consensus>

    title = Alignment consensus

    quality-type = Illumina_1.3

    consensus-method = most_frequent
    minimum-sequences = 1
    minimum-non-gaps = 5%
    minimum-base-quality = 99.9%
    minimum-sequence-conservation = 0%
    minimum-quality-conservation = 20%
    minimum-ambiguity-coverage = 90%
    maximum-columns-fail = 5%
    maximum-columns-quality-fail = 5%
    trim-start = yes
    trim-end = yes
    minimum-length = 15

</alignment-consensus>

);

    return $text;
}

    
sub ali_credits
{
    # Niels Larsen, April 2011.
    
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
    
sub ali_fetch_examples
{
    # Niels Larsen, April 2011.
    
    # Gives examples. 

    # Returns a string.

    my ( $text, $title );
    
    $title = &echo_info( "Examples" );

    $text = qq (
$title

1. ali_fetch --seq pig.chr1 'contig1:200,500;3578,1067-' --outfile pig.out

   Fetches a small sub-sequence from pig chromosome 1, in different 
   orientations. The locator notation is 'ID:pos,length,orientation', where
   orientation is '+' (which can be omitted) or '-'. The last comma may
   also be omitted. If both position and length are omitted, the whole 
   sequence is returned. 

2. ali_fetch --seqfile pig_expr.fq --locfile locs.list --order

   Fetches many sequences given in a list that shares some ordering with the 
   sequence file. The list file may contain a mixture of ids and sub-sequence
   locators. 

3. cat locs.list | ali_fetch --seqfile pig_expr.fq --format json 

   Same as above, but takes locators from STDIN and prints in JSON format on 
   STDOUT. 

);

    return $text;
}

sub ali_fetch_features
{
    # Niels Larsen, January 2011.
    
    # Lists features.

    # Returns a string.

    my ( $text, $title, $formats );
  
    $title = &echo_info( "Features" );

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



  However note that fastq format can of course not be made from a fasta file,
  so these output options depend on which file has been indexed. Fields can 
  be de-selected unless required by the chosen format.

Obvious features are missing, see --help missing.

);

    return $text;
}

sub ali_fetch_intro
{
    # Niels Larsen, January 2011.
    
    # Returns a small fetch introduction and explains how to get more 
    # help. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Introduction" );

    $text = qq (
$title

Fetches alignments and sequences by ali_index.

HELP NOT DONE - PROGRAM IS INCOMPLETE.
);

    $text .= "\n". &Common::Messages::legal_message() ."\n";

    return $text;
}

sub ali_fetch_intro_old
{
    # Niels Larsen, January 2011.
    
    # Returns a small fetch introduction and explains how to get more 
    # help. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Introduction" );

    $text = qq (
$title

Fetches alignments and sequences
by ali_index, at high speed and in different output formats. The index is 
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

sub ali_fetch_perform
{
    # Niels Larsen, March 2011.

    # Returns a small description of computer resource usage during typical 
    # indexing runs. 

    # Returns string.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title

These numbers come from an older two-core 2007 model Lenovo t61p laptop 
with a T7500 processor, 4 MB cache and 3 GB RAM. On todays systems, these
numbers ought to be much better. On 64-bit systems the RAM usage may be 
significantly higher because of the larger address spaces.

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

sub ali_index_examples
{
    # Niels Larsen, April 2011.
    
    # Gives ali_index examples. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Examples");

    $text = qq (
$title

1. ali_index alidir*/*.stockholm

   Indexes a set of stockholm files, making a set of *.stockholm.fetch files.
   The number of alignments and sequences are measured in the inputs, but only
   alignments are indexed. This gives a very small index file usually, and 
   only whole alignments can be retrieved by ali_fetch, and in its original
   format. 

2. ali_index alidir*/*.fasta --seqndx --suffix .try6 --clobber

   Indexes both alignments and sequences, and produces index files that end 
   with '.try6'. Fasta header ids must be like "ali_id:seq_id", but this will
   be made flexible. The clobber option overwrites existing index files.

3. ali_index alidir*/*.uclust --seqndx --alimax 100k --aidlen 10 --seqmax 12m --sidlen 10 

   A set of large uclust formatted alignment files are indexed, including the
   sequences. The number of alignments and sequences are given, so that the 
   input is only read through once. The '100k' and '12m' means 100,000 and 12
   million, and need only be approximate, but should not be lower than the 
   actual numbers. 

4. ali_index --about alidir/alifile.uclust.try6
 
   Displays a readable list of types, names and dimensions for a given index
   file.

);

    return $text;
}

sub ali_index_features
{
    # Niels Larsen, April 2011.
    
    # Returns description of features.

    # Returns a string.

    my ( $text, $title, $formats );
  
    $title = &echo_info("Features");
    $formats = join ", ", @{ &Ali::Storage::index_registry_values( "formats" ) };

    $text = qq (
$title

Feature highlights are,

*  High indexing speed, small file size and low resident memory usage.
   See the performance page.

*  Many files can be indexed with one command (see examples). The output
   files will have suffixes added, which are user controlled. This makes
   it easier to manage large file sets.

*  Supported input formats are: $formats. 
   Sequences cannot be indexed with the wrapped formats (like stockholm),
   only whole alignments. 

);

    return $text;
}

sub ali_index_intro
{
    # Niels Larsen, April 2011.
    
    # Returns a small introduction and explains how to get more help. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Creates indices from alignment files so they can be quickly accessed by 
ali_fetch. It works equally well many short sequences and genomes, will 
process many files with one command and is low on computer resources. It
uses the fast Kyoto Cabinet key/value storage from from http://fallabs.com.

These help options describe indexing further,

    --help features   Feature list
    --help examples   Commented examples
    --help perform    Performance numbers
    --help missing    Limitations and missing features
    --help credits    Thank you's and reference

Options can be abbreviated, for example '--help p' will show performance
numbers.
);

    $text .= "\n". &Common::Messages::legal_message() ."\n";

    return $text;
}

sub ali_index_missing
{
    # Niels Larsen, April 2011.

    # Returns a small description of what is missing and not done. 

    # Returns string.

    my ( $text, $title );
  
    $title = &echo_info("Missing");

    $text = qq (
$title

The ali_index program is unfinished. Missing are,

1. Flexibility. Should be able to specify the looks of fasta headers and 
   small changes to other formats, so it can be used in many more recipes.

2. Input formats. Add input formats.

3. Out formats. Add output formats. 

4. Efficiency. Add read/seek tradeoff at around 4 mb for speed. 

5. Sub-sequences. Should be able to extract sub-alignments easily.

);

    return $text;
}

sub ali_index_perform
{
    # Niels Larsen, March 2011.

    # Returns a small description of computer resource usage during typical 
    # indexing runs. 

    # Returns string.

    my ( $text, $title );

    $title = &echo_info("Performance");
    
    $text = qq (
$title

These numbers come from an older two-core 2007 model Lenovo t61p laptop 
with a T7500 processor, 4 MB cache and 3 GB RAM. On todays systems, these
numbers ought to be much better. On 64-bit systems the RAM usage may be 
significantly higher because of the larger address spaces.

Each dataset below were indexed twice, both without file system cache 
('hot') and without ('cold'). The first is RAM limited, the second is 
limited by disk speed, and indeed those were the limits in each case.

Rfam, 1446 alignments, single 10.5 gb stockholm file:

     Speed:  2 min 7 secs hot, 2 min 18 secs cold.
      Size:  45 kb.
       RAM:  89 mb virtual, resident ram 19 mb.

Expression data, 11.7 million 35-long sequences, single 690 mb uclust 
file, alignments only:

     Speed:  49 secs hot, 54 secs cold.
      Size:  10.6 mb.
       RAM:  99 mb virtual, resident ram 23 mb.

Expression data, 11.7 million 35-long sequences, single 690 mb uclust 
file, sequences included:

     Speed:  2 min 31 secs hot, 2 min 39 secs cold.
      Size:  41 mb.
       RAM:  390 mb virtual, resident ram increasing linearly up to that.

);

    return $text;
}

1;

__END__
