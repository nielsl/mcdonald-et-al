package Expr::Help;     #  -*- perl -*-

# Sequence related help texts. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &dispatch
                 &prof_covar_config
                 &prof_covar_credits
                 &prof_covar_distance
                 &prof_covar_filters
                 &prof_covar_grouping
                 &prof_covar_inputs
                 &prof_covar_intro
                 &prof_covar_missing
                 &prof_covar_outputs
                 &prof_covar_scaling
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Widgets;

our $Sys_name = $Common::Config::sys_name;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub dispatch
{
    # Niels Larsen, June 2011.

    # Dispatches help page requests. The first argument is the program name 
    # that invoked it, then second is the type of help to be shown. If "prof_covar"
    # is given as first argument and "intro" as the second, then the routine 
    # prof_covar_intro is invoked.

    my ( $prog,           # Program string like "prof_covar"
         $request,        # Help page name - OPTIONAL, default "intro"
         ) = @_;

    # Returns a string. 

    my ( %requests, $text, $routine, $choices, @msgs, $opts, @opts );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    %requests = (
        "prof_covar" => [ qw ( config credits intro inputs filters distance grouping outputs missing ) ],
        "prof_combine" => [ qw ( inputs filters ) ],
        );
    
    $request ||= "intro";

    if ( $opts = $requests{ $prog } )
    {
        @opts = grep /^$request/i, @{ $opts };

        if ( scalar @opts != 1 )
        {
            $choices = join ", ", @{ $opts };

            if ( scalar @opts > 1 ) {
                @msgs = ["ERROR", qq (Help request is ambiguous -> "$request") ];
            } else {                
                @msgs = ["ERROR", qq (Unrecognized help request -> "$request") ];
            }

            push @msgs, ["TIP", qq (Choices are: $choices) ];

            &append_or_exit( \@msgs );
        }
    }
    else {
        &error( qq (Wrong program string -> "$prog") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DISPATCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#    if ( $opts[0] eq "credits" ) {
#        $routine = "Expr::Help::expr_credits";
#    } else {
        $routine = "Expr::Help::$prog" ."_$opts[0]";
#    }

    no strict "refs";
    $text = &{ $routine };

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::Messages::print_usage_and_exit( $text );
    }

    return;
}

sub prof_covar_config
{
    # Niels Larsen, June 2011.
    
    # Explains the configuration file purpose and format. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Configuration file" );

    $text = qq (
$title

The prof_covar program has 20-25 different settings so it is practical to
keep them in configuration file, which also makes it easier to manage 
re-runs. We recommend placing configuation files near the datasets they 
apply to, for example in each top-level data directory. That prevents 
mixing and overwriting settings, and shows the user which configurations 
to use with given datasets. 

All command line arguments can be put in the file (but without the leading
dashes). File and command line can be mixed, but the latter override and 
there is no merging of values (it is always either-or). That makes it easy 
to tweak a program to fit certain types of data: rerun it until things look 
good, then put the value(s) into the configuration file for later runs. 

A configuration file template is provided here,

$Common::Config::recp_dir/profile_compare.config

which shows all possible keys and explains each one. The format is simple 
key-value, with leading and trailing "#" allowed as comment lines. Lists 
are created by duplicating keys, omitted values are set to generic program
defaults. There are more recipe and configuration files for other programs
in the parent directory of the above file. For programmers, the format is 
a simplified XML-like format described at 

http://search.cpan.org/~tlinden/Config-General-2.50/General.pm
);

    return $text;
}

sub prof_covar_credits
{
    # Niels Larsen, June 2011.
    
    # Prints credit and a reference.

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info("Credits");

    $text = qq (
$title

This program would not be possible without the GNU Scientific Library, the
Google Charts API service. 

Many thank you's go the a range of free and open source tools, including 
languages, editors, servers and the GNU suite. Had such a rich set of high 
quality components been proprietary, this package could not have been made.

Reference:

Niels Larsen, Danish Genome Institute at http://genomics.dk, unpublished.
);

    return $text;
}

sub prof_covar_distance
{
    # Niels Larsen, June 2011.
    
    # Describes how distance matrices are made and related parameters. 

    # Returns a string.

    my ( $text, $methods_title, $param_title );
  
    $methods_title = &echo_info("Methods");
    $param_title = &echo_info("Parameters");

    $text = qq (
$methods_title

Two scoring methods are available,

1. Pearson Correlation Coefficient (pcc), which is general and popular but has
   not yet worked as well as hoped for us. It is described here,

   http://davidmlane.com/hyperstat/A56626.html
   http://en.wikipedia.org/wiki/Pearson_product-moment_correlation_coefficient

   The PCC score (values between -1.0 and 1.0 for non-correlated and correlated) 
   are mapped to the range zero to one and regarded as distances. 

2. Our best-working method so far is a simple score that measures the average 
   percentage-wise difference between two lists of numbers, first scaled to a 
   common mean or median. Then a list of absolute difference ratios are created,
   and the mean of those ratios are finally taken. As an option, a percentage of
   the biggest differences can be discarded before calculating a value. 

$param_title

Dataset ratios (minrat and maxrat). Datasets may have values that vary in highly 
similar ways, but differ greatly in size. These two options control how many 
times the mean of the two sets may differ. 

Scaling (scale). Before distances are measured, the datasets are scaled so their
means or medians are the same. The smaller of the sets are always scaled up. 
Specify either "mean" or "median".

Clipping (dispct). Outliers can be omitted from the distance measure by setting
dispct to for example 10. Then the ten percent highest differences will be 
discarded before measuring distance. 

Distance bounds (minsco and maxsco). Limits which distances are considered, i.e.
which go into the distance matrix. If they are too large, the noise level goes
up, and 0.25 is often a reasonable maximum. 
);

    return $text;
}

sub prof_covar_filters
{
    # Niels Larsen, June 2011.
    
    # Describes the filtering options.

    # Returns a string.

    my ( $text, $name_title, $value_title );
  
    $name_title = &echo_info( "Name filtering" );
    $value_title = &echo_info( "Value filtering" );

    $text = qq (
$name_title

This is done by the Perl language, so filter expressions must follow its 
conventions. Here is a gentle introduction to that syntax,

http://www.zytrax.com/tech/web/regex.htm

When specified this way, each line below works as a name filter that selects 
all matching names. Names without special expression characters are taken as 
is. If names1 or names2 filters are not given then all names are assumed and
the comparison will become all-against-all. In this example, all miR and let 
names will be compared with all names,

names1   miR
names1   let

names2 

$value_title

Sometimes low and/or highly variable values are considered un-wanted noise,
and the following keys help filter that out. They act like a "bottom-filter" 
where the user decides where to exlude, if anything. These two settings says
to require at least a given percentage (mindef) of data points have have 
values of at least minval,

minval  10
mindef  80

These limit the average values of each dataset to the given bounds (no value 
means no limit),

minavg  50
maxavg

These limit datasets by variability, the score of which varies between zero 
(no variation) and 2.5+ (high variation),

minvar 
maxvar
);

    return $text;
}

sub prof_covar_grouping
{
    # Niels Larsen, June 2011.
    
    # Describes grouping methods and parameters. 

    # Returns a string.

    my ( $text, $methods_title );
  
    $methods_title = &echo_info("Methods");

    $text = qq (
$methods_title

Two methods are available that form groups,

1. Simple grouping. Input is a list of name-pair distances (a distance matrix).
   All name pairs are first sorted by their distances. Names are then placed in
   the groups where their best match were first placed. More and more distant 
   pairs are added, but only once. This naive approach uses the least distant 
   pairs as "nucleus" that attract swarms of more distant points around them. 
   With relaxed parameters it often gives a better impression of the noise 
   level than clustering. Two parameters control the method,

   grp_maxsco: maximum distances to be shown overall
   grp_maxdif: maximum distance within groups

   This method is the default.

2. Tree clustering. This method comes from the commonly used Cluster 3.0 package,
   which is a hiearchical clustering approach, 

   http://en.wikipedia.org/wiki/Cluster_analysis#Hierarchical_clustering

   Two parameters control the method,

   clu_maxnum: maximum number of clusters
   clu_maxdif: maximum distance within clusters
);

    return $text;
}

sub prof_covar_inputs
{
    # Niels Larsen, June 2011.
    
    # Describes the input and input related options.

    # Returns a string.

    my ( $text, $files_title, $format_title, $labels_title, $sort_title );
  
    $files_title = &echo_info( "Files" );
    $format_title = &echo_info( "Formats" );
    $labels_title = &echo_info( "Labels" );
    $sort_title = &echo_info( "Soring" );

    $text = qq (
$files_title

Input files are given either on the command line, where filter expressions 
\("wildcards"\) are allowed. The same syntax is used in the configuration file,
where multiple lines indicates multiple inputs, for example

infiles ~/pig/seqdata*/*.expr
infiles ~/human/new/*.expr

would select all files in all those directories that match. Relative paths 
and use of '~' for home directory is okay. 

$format_title

Input files are tables. Their format does not matter, but this program must 
know in which columns the names and numbers are. It recognizes tables written
by expr_profile, but these two settings define the columns,

namcol   Annotation
numcol   Sum-wgt

Use either 1-based numbers or names that must then be in the first table 
line in all input files, as a header line. Names can be in any column.

$labels_title

Input labels can be given like this,

labels cond1
labels cond2
labels cond4

These are titles for experiment conditions that appear on figures. There must 
be one label for each input file \(there will be an error message if not\) and 
order matters.

$sort_title

When all data has been loaded into memory, they are sorted by either highest 
total sums for each name (sum) or by highest variability (var),

sorder sum

This is done because it helps the grouping logic created more robust results
and it is usually the way users prefer to look at outputs. 
);

    return $text;
}

sub prof_covar_intro
{
    # Niels Larsen, June 2011.
    
    # Returns a small dereplicate introduction and explains how to get more 
    # help. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Introduction" );

    $text = qq (
$title

Creates groups of expression patterns that are similar or dissimilar 
across a given set of conditions. The program can work with any table 
format and can be used to picture the variations of any set of units 
whether or not their expression patterns are correlated. It was written
for gene expression experiments, but should work for organisms or other
dataset types.

Inputs are tables written by the expr_profile script, or any table with 
names and values in them. Various filter options help limit the profiles 
being compared: filter by variability, absolute size, or by name and/or
condition. For spotting correlated expression value sets the common 
Pearson correlation coefficient is used, plus two home-made ones. 

These help options describe usage and arguments further,

    --help config        Configuration file 
    --help inputs        Inputs and input options
    --help scaling       Scaling of input reads
    --help filters       Input filtering options
    --help distance      Distance matrix methods
    --help grouping      Grouping methods and parameters
    --help outputs       Output options
    --help missing       Missing features and to-do's 

Options can be abbreviated, for example '--help f' will show filtering.

Do no work on data within the BION directory, it is safer
to keep them outside as unpredictable things may happen during updates.
);

    $text .= "\n". &Common::Messages::legal_message();

    return $text;
}

sub prof_covar_matching
{
    # Niels Larsen, June 2011.
    
    # Describes how matching is done and related parameters. 

    # Returns a string.

    my ( $text, $methods_title, $param_title );
  
    $methods_title = &echo_info("Methods");
    $param_title = &echo_info("Parameters");

    $text = qq (
$methods_title

Three matching methods are available,

1. Pearson Correlation Coefficient (pcc), which is general and popular but has
   not yet worked as well as hoped for us. It is described here,

   http://davidmlane.com/hyperstat/A56626.html
   http://en.wikipedia.org/wiki/Pearson_product-moment_correlation_coefficient

2. Our best-working method so far is a simple score that measures the average 
   percentage-wise difference between two lists of numbers, first scaled so their
   mean or median are the same. Then a list of absolute difference ratios are 
   created.
    # The optionally this list is sorted and up to skips of the highest ratios 
    # discarded. Finially the average mean is taken and the corresponding percentage
    # returned. 



dif (a simple difference measure) and difpct (also
 a simple difference measure, but percentage based). Below are reasonable 
 default parameters for each. The first one (difpct) has worked best for us.

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> MATCHING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# These settings modify matching, i.e. the pairwise comparisons of lists of 
# numbers. 

# Datasets may have values that vary in a highly similar way, but differ greatly
# in size. These two options control how many times the mean of the two sets 
# may differ for them to go in the same group,

minrat 
maxrat


method difpct
minsco 0
maxsco 35
dispct 10
scale median

# method  pcc
# minsco .9            # Pearson score minimum
# maxsco 1             # Pearson score maximum

# method dif
# minsco 0
# maxsco 0.3
# scale median
);

    return $text;
}

sub prof_covar_missing
{
    # Niels Larsen, June 2011.
    
    # Summarizes obvious missing features and to-do items. 

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Missing" );

    $text = qq (
$title

These are relevant additions, 

1. The Cluster 3.0 is only partially supported: we only use its treecluster 
   method, and we always create our own distance matrix. We find they work 
   the best, but all its other options could also be supported. 

2. Of more concern is the fact that there can be strong correlations across
   an unknown sub-set of conditions. If for example 22 conditions are chosen,
   then what if values correlate strongly among 15 of them? There are programs
   available, such as FABIAN (an R package from University of Linz), but the
   SAX/ISAX method should also be able to handle this situation,

   http://www.cs.ucr.edu/~eamonn/iSAX/iSAX.html

3. More input table options. For example, support tables with all data within.
);

    return $text;
}

sub prof_covar_outputs
{
    # Niels Larsen, June 2011.
    
    # Explains outputs.

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Outputs" );

    $text = qq (
$title

Outputs are in either table or YAML formats. The YAML format is a structured
computer readable format from which human readable outputs can be produced.

The prof_covar_html program makes self-contained HTML table and chart pages.
They show different degree of detail and can be mailed, viewed in a browser 
and put on the web. They contain a header with title, inputs, methods and 
parameters, and are intended as a "web-recipt" for a given run.
);

    return $text;
}

sub prof_covar_scaling
{
    # Niels Larsen, June 2011.
    
    # Eplains scaling options.

    # Returns a string.

    my ( $text, $title );
  
    $title = &echo_info( "Scaling" );

    $text = qq (
$title

Values can be scaled by total sums per file (original reads for expression
experiments)e, by sums of a select group of names, or not at all. If names,
or name filtering expressions (same syntax as input filtering) are given 
then all values are scaled so the sums for the selected names are constant
across all files. If none are given, then the total sums will be made the 
same across all files. To not scale, write the special word __none__ below
as a name. Scaling by names can be useful for example with gene expression 
data where the overall expression of household-genes are known to not 
change much between experiments.

scanam                (scaling by
# scanam               total sums)

scanam  miR           (scaling by miR
scanam  let            and let)

scanam  miR  not      (scaling by anything
scanam  let  not       but miR and let)

scanam  __none__      (no scaling)

Though usually not a very good option, the suppow option reduces the data 
by the given power of 10 before comparison is done and then reverses that 
reduction after it has been done. The effect is the largest differences 
(but not largest data-points) become less pronounced. It can be used to 
reduce the overall disturbance of a few large differences. Use with 
caution, only when there is dirty data and only powers between 1 and 5 or 
so make sense (decimal powers are okay).

suppow

See also the dispct option with --help methods.
);

    return $text;
}

1;

__END__

# sub prof_covar_examples
# {
#     # Niels Larsen, March 2011.
    
#     # Gives examples. 

#     # Returns a string.

#     my ( $text, $title );
  
#     $title = &echo_info( "Examples" );

#     $text = qq (
# $title




# The --mindif and --maxdif arguments can be used to select only those 
# datasets with roughly similar absolute values (the Pearson correlation 
# matches those that trend the same way, regardless of absolute values). 
# The --minvar and --maxvar selects for sets where values vary around their
# mean. Pearson coefficients can vary between -1.0 and +1.0. The --config
# option is provided, so it becomes easy to invoke the script with slight
# parameter changes.
# E
# # Depending on method, minimum and maximum scores are different: for pcc, -1 
# # is strong negative correlation, +1 strong positive. For dif, 0.0 means no 
# # difference, above 0.5 means different and above 1 means very different,

# xamples,

# 1\) prog_name *.expr --tsv myexp.tsv
# 2\) prog_name *.expr --minpear 0.7 --chart myexp.html
# 3\) prog_name *.expr --maxpear -0.5 --minpear -1.0 --html myexp.html

# # Dataset correlation. Pearson correlation coefficient is defined like this,
# #
# # http://en.wikipedia.org/wiki/Pearson_product-moment_correlation_coefficient
# #
# # and can have values between -1.0 and 1.0. 


# with or without a header
# 1. seq_derep pig_expr.fq 

#    This creates the file 'pig_expr.fq.derep', a key/value storage with sequence
#    as key and count and quality as value. 

# 2. seq_derep seqdir*/*.fq --suffix .proj4

#    As above, but processing multiple files at a time and using custom output 
#    suffix. This is useful for customer separation, tests etc.

# 3. seq_derep seqdir*/*.new.fq --addto 'seqdir*/*.proj5 

#    As above, but adding new sequence data to an existing set of de-replication 
#    indices. There must be one new file per existing index.

# 1. seq_derep pig_expr.fq 

#    This creates the file 'pig_expr.fq.derep', a key/value storage with sequence
#    as key and count and quality as value. 

# 2. seq_derep seqdir*/*.fq --suffix .proj4

#    As above, but processing multiple files at a time and using custom output 
#    suffix. This is useful for customer separation, tests etc.

# 3. seq_derep seqdir*/*.new.fq --addto 'seqdir*/*.proj5 

#    As above, but adding new sequence data to an existing set of de-replication 
#    indices. There must be one new file per existing index.

# );

#     return $text;
# }
