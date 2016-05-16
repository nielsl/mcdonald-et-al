package Recipe::Help;     #  -*- perl -*-

# Help texts for recipes. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;
use English;

use Text::Format;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &about
                 &consult
                 &dispatch
                 &header
                 &intro
                 &options
                 &run
                 &step
                 &steps
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Widgets;

use Recipe::Steps;
use Recipe::Params;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Linwid = 74;
our $Sys_name = $Common::Config::sys_name;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub about
{
    my ( $author, $website, $software, $text );

    # $author = &echo_info("Author");
    # $website = &echo_info("Website");
    # $software = &echo_info("Software");

    $text = qq (
  Software   GNU Affero GPL license with stipulations
    Author   Danish Genome Institute
   Website   http://genomics.dk (with contact details)
);

    return $text;
}

sub consult
{
    my ( $text );
    
    $text = qq (
We offer live online-help, service contracts and development contracts.
This is for a fee, but prices are reasonable and charges are only made 
when things work. New features, web-interfaces, visualizations etc, 
can be implemented by request. Please refer to 

http://genomics.dk

under "Contact" in the menu bar for current contact details. E-mail is
the preferred way of initial contact and skype for discussions and help.
);
    
    return $text;
}

sub dispatch
{
    # Niels Larsen, March 2012.

    # Act in response to different help requests, with error messages.

    my ( $args,
         ) = @_;

    # Returns a string. 

    my ( $key, @keys1, @steps, @hits, @hits2, $text, $routine, $str, 
         @msgs, $hit, @opts, $defs );

    $defs = {
        "key" => undef,
        "help" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );

    $key = $args->key;
    
    # This should never happen, so ok to crash,

    if ( not defined $key ) {
        &error( qq (No request given) );
    }

    @keys1 = map { $_->[0] } &Recipe::Help::options();
    @steps = sort keys %Recipe::Steps::Step_map;

    @hits = grep /$key/i, @keys1, @steps;

    if ( @hits )
    {
        if ( @hits2 = grep { $_ eq $key } @keys1, @steps ) {
            @hits = @hits2;
        }

        if ( scalar @hits == 1 )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>> SINGLE MATCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( grep /$hits[0]/, @steps )
            {
                $text = &Recipe::Help::step( $hits[0], $args->help, \@msgs );
            }
            else 
            {
                $routine = "Recipe::Help::$hits[0]";
                
                no strict "refs";
                $text = &{ $routine };
            }

            $text =~ s/\n/\n /g;
            $text .= "\n";

            &append_or_exit( \@msgs );
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>> MULTIPLE MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            $text = "-" x $Linwid ."\n\n";
            $text .= "  ". &echo_oops(" OOPS ") ."  ". qq (Match with more than one option:\n\n);

            foreach $hit ( @hits )
            {
                if ( $hit =~ /$key/ ) {
                    $text .= "    ". $PREMATCH . &echo_bold( $MATCH ) . $POSTMATCH ."\n";
                } else {
                    &error("Programmer error: no match with $key" );
                }
            }

            $text .= "\n  ". &echo_info_green(" HELP ") ."  ". qq (Please enter a string that gives one unique match.\n);
            $text .= "\n". "-" x $Linwid ."\n";
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRONG OPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $text = "-" x $Linwid ."\n\n";
        $text .= "   ". &echo_red("ERROR") ."   ". qq (Unrecognized help request: "$key"\n);
        $text .= "  ". &echo_info(" INFO ") ."   ". &echo("Help choices are:\n\n");

        @opts = &Recipe::Help::options();
        $text .= &Common::Tables::render_ascii_usage( \@opts, {"highlights" => [ map { $_->[0] } @opts ], "highch" => " " });

        $text .= "\n". "-" x $Linwid ."\n";
    }

    if ( defined wantarray ) {
        return $text;
    } else {
        print $text;
    }

    return;
}

sub header
{
    my ( $title,  # Title text - OPTIONAL 
         $indent, # Indentation - OPTIONAL, default 1
         $margin, # Margin - OPTIONAL, default 3
         $width,  # Bar width - OPTIONAL, default 79
        ) = @_;

    my ( $text, $blanks );

    $title //= "";
    $indent //= 0;
    $margin //= 2;
    $width //= 73;
    
    $blanks = " " x $margin;

    $text = &Common::Messages::_echo( "-" x $width, "white on_blue", $indent ) ."\n";

    $text .= &Common::Messages::_echo( $blanks.$title . " " x ( $width - length $blanks.$title ),
                                       "bold white on_blue", $indent ) ."\n";

    $text .= &Common::Messages::_echo( "-" x $width, "white on_blue", $indent );
    
    return $text;
}

sub intro
{
    # Niels Larsen, March 2012.
    
    # Returns a small introduction to recipes, and explains how to get 
    # more help. 

    # Returns a string.

    my ( $sys_name, $text, $recp_hdr, $xtra_hdr, $unix_hdr, $contact );
    
    $recp_hdr = &Recipe::Help::header( "Introduction to recipes" );
    $unix_hdr = &Recipe::Help::header( "Command line introduction" );
    $xtra_hdr = &Recipe::Help::header( "Further assistance" );

    $sys_name = $Common::Config::sys_name;
    $contact = &Common::Messages::format_contacts_for_console();

    $text = qq (
$recp_hdr

A recipe is a text file with steps that together form an analysis flow. 
The text is easy to understand and contains all parameter settings and 
recipes provide a way for mere mortals to repeat complex analyses and 
see the effects of parameter changes etc. Running recipes is done with 
the run_recipe command, and help_recipe explains how. 

A number of recipe templates are included with this package, list them
with the command

  tree $Common::Config::recp_dir

Also bundled is the nano text editor, which can be used to edit recipes
and is the most novice-friendly free editor (Emacs and others are much 
more capable but take longer to learn). Try for example the command 

  nano <template file name>

where of course the "<template file name>" should be replaced with one 
of the listed file names. The Ctrl-X key combination exits the editor. 
Each recipe section defines a step, maybe with sub-steps, that define 
methods and parameters in a simple "key = value" format. Steps are run
in the order given, in parallel where possible. No web interface yet 
exists and recipes are run from the command line, like so for example,

  run_recipe recipe.file seqdir*/*.fq.gz --outdir Outputs 

There is command line help available that lists and explains steps, 
their parameters and the method logic behind each. Try these example
commands,

  help_recipe steps 
  help_recipe sequence-cleaning 

to see available steps, and information about a particular step.
);

    $text .= qq (    
$unix_hdr

The package does not yet come with a web interface for running recipes,
that must be done from the command line (however there are web outputs 
for results). Knowing how to examine the data closely also help detect 
problems early. We recommend command line novices to take the 2-3 days
needed to learn the most common commands for moving, filtering, editing 
and deleting files for example; learning a limited "vocabulary" of 15-25 
commands should be enough. These are good starting points with cheat-
sheets etc,

http://fosswire.com/post/2007/08/unixlinux-command-cheat-sheet
http://www.cyberciti.biz/tips/linux-unix-commands-cheat-sheets.html

$xtra_hdr
);

    $text .= &Recipe::Help::consult();

    return $text;
}

sub options
{
    my ( @opts );

    @opts = (
        [ "intro", "Prints introduction for first-time users" ],
        [ "steps", "Lists all steps available for recipes" ],
        [ "run", "Explains how to run recipes" ],
        [ "modify", "How to modify template recipes" ],
        [ "build", "How to build new recipes" ],
        # [ "new", "Add building blocks (perl knowledge required)" ],
        );
    
    return wantarray ? @opts : \@opts;
}

sub run
{
    # Niels Larsen, March 2012.
    
    # Returns help with how to run recipes.

    # Returns a string.

    my ( $run_hdr, $io_hdr, $msg_hdr, $tips_hdr, $ass_hdr, $text, $rep_text );
  
    $run_hdr = &Recipe::Help::header( "How to run recipes" );
    $io_hdr = &Recipe::Help::header( "Inputs and outputs" );
    $msg_hdr = &Recipe::Help::header( "Errors and messages" );
    $tips_hdr = &Recipe::Help::header( "Caveats and tips" );
    $ass_hdr = &Recipe::Help::header( "Further assistance" );
    
    $rep_text = &echo_green("reproduce results in a transparent way, which is too often neglected");

    $text = qq (
$run_hdr

\(TODO: Expand with downloadable example data\)

All recipes are run by the run_recipe command. Its first argument must 
be a recipe file, the following ones are input files. In addition there 
can be any number of "dashed" arguments like "--outdir" which are used 
to alter its running behaviour in some way (typing run_recipe with no 
arguments will list these). As example, a recipe that accepts sequence
data as input is launched like this,

  run_recipe recipe.file Seqdir/*.fastq.gz --outdir Outputs --batch

If run interactively \(without --batch\) then there will progress messages
on the console, unless --silent is given. Steps that allow it will be 
automatically parallelized on multi-core machines. There is no e-mail 
or other notifications yet, so one will have to watch the console or 
the given output directory. 

$io_hdr

Inputs can be a single file, multiple files or multiple files treated as 
a single one \(with the --single argument on\). The input type depends 
on what the first recipe step requires. Initial parts of a recipe may be
deleted or commented out with the "#" sign, and run from there. However,
then the recipe must be fed the input that it now expects.

Outputs are saved in a single given output directory. It is recommended 
to have one directory per input dataset to prevent unfortunate mixing of
results. However, a file prefix can also be used to keep track of outputs
from different runs within the same directory. The outputs are saved from
all steps by default, but adding "keep-outputs = no" to a step deletes 
them. Web statistics outputs are saved for most steps, with parameters 
and inputs and outputs listed. These are generated static HTML files that
will allow users to zip an output directory and post the results to the 
web anywhere, without installing this package, but a web server must be
running to show the HTML.

Recipe steps take as input the files given on the command line, output 
files from a previous step, either a named one or the preceding one. 
This works because each step uses fixed file prefixes and suffixes that 
cannot be changes from a recipe. Some methods split files (one to many),
some work on each given file (many to many) and some create single files
from many. But recipe authors do not need to care about how this happens,
only step authors do.

$msg_hdr 

The slightest error or warning anywhere will cause a complete crash with 
a detailed traceback message. This brings all errors to the surface so 
they can be fixed quickly, and we will of course do our best to do that 
should there be a problem. If so happens, please run the recipe again 
with the --debug switch. This will produce a directory with very helpful
information for the programmer, and there will screen instructions how 
to package and send it to us. Errors will appear on the console for 
interactive runs, and in the file run_recipe.screen for background jobs.

$tips_hdr

Do not save or run anything within the BION directory tree. Instead
copy templates to where they are to be used. The BION directory is 
reserved for our software and its data and may be updated or deleted 
at any time. 

Avoid file names containing blanks: command line parsing uses blanks to
separate arguments. On the command line, one file with a blank in its 
name will look the same as two files without. 

It is good to have recipes a location very near the data it applies to: 
Then it is always clear which parameters were used on the data, it becomes
easy to rerun a recipe with the appropriate settings, and recipes will 
be part of data backups. Most importantly, referees and peers can then 

$rep_text.

Recipe titles appear in the web-outputs, so make them descriptive.
Comments can be added if starting with a pound sign "#".
);

    $text .= "\n$ass_hdr\n";
    $text .= &Recipe::Help::consult();

    return $text;
}

sub step
{
    # Niels Larsen, May 2012.

    # Lists a single step with all parameters and default values. Returns 
    # a string.

    my ( $name,
         $help,
         $msgs,
        ) = @_;

    my ( $hdr, $tpl, $text, $step, $info, $key, $wrap, $htxt, $hmap, @lines,
         $val );

    $hdr = &Recipe::Help::header( "Recipe step template" );
    $tpl = &Recipe::Steps::get_step_text( $name, 1 );

    $text = qq (
$hdr

The text below can be pasted into a recipe as is, but the parameters
will of course have to be adjusted to fit the data at hand.

$tpl
);

    if ( $help )
    {
        $text .= qq (The options in this template have the meanings listed below.\n\n);

        $wrap = Text::Format->new({ "columns" => 70, "firstIndent" => 0, "leftMargin" => 2 });
        $hmap = &Recipe::Params::help_map();
        
        $step = &Recipe::Steps::get_step( $name );
        
        foreach $key ( keys %{ $step } )
        {
            next if $key eq "steps";
            next if $key eq "run";
            next if $key eq "summary";
            next if $key eq "id";
            
            $val = $hmap->{ $key };
            
            # Header with title, choices, min/max and default,
            
            $text .= &echo_bold("* ") . &echo_cyan( $key ) ."\n";
            
            if ( exists $val->{"vals"} ) {
                $text .= "\n  Choices: ". ( join ", ", @{ $val->{"vals"} } ) .".\n";
            }
            
            if ( exists $val->{"minval"} ) {
                $text .= "\n  Minimum value: $val->{'minval'}.";
            }
            
            if ( exists $val->{"maxval"} ) {
                $text .= "  Maximum value: $val->{'maxval'}.";
            }
            
            if ( defined $val->{"defval"} ) {
                $text .= "  Default value: $val->{'defval'}.\n";
            }
            
            # Help text,
            
            if ( exists $val->{"desc"} )
            {
                $text .= "\n". $wrap->format([ split "\n", $val->{"desc"} ]) ."\n";
            }
            elsif ( exists $val->{"descn"} )
            {
                @lines = map { " $_" } split "\n", $val->{"descn"};
                $text .= ( join "\n", @lines ) ."\n\n";
            }
            else {
                $text .= "\n  No description yet\n\n";
            }
        }
    }
    else {
        $text .= qq (To see the keys explained, add --help.\n);
    }
        
    return $text;
}

sub steps
{
    # Niels Larsen, May 2012. 

    # Creates a screen message that lists all recipe steps by name, plus
    # some text.

    my ( $hdr, $map, @names, $text, $name, @table );

    $map = &Recipe::Steps::get_map();
    @names = keys %{ $map };
    
    $hdr = &Recipe::Help::header( "List of recipe steps" );

    $text = qq (
$hdr

Recognized recipe step names (with default titles as second column):

);

    foreach $name ( @names )
    {
        next if $name eq "recipe";

        push @table, [ $name, $map->{ $name }->{"title"}->{"defval"} ];
    }

    @table = sort { $a->[0] cmp $b->[0] } @table;

    $text .= &Common::Tables::render_ascii_usage( \@table );

    $text .= qq (
However more can of course be added. Parameters and their default values
are shown with "help_recipe <step-name>" where <step-name> is one of the 
above names.
);

    return $text;
}

1;

__END__

# sub tips
# {
#     # Niels Larsen, November 2010.

#     # Shows advice about what to do and what to avoid. Returns a text string.

#     # Returns a string.

#     my ( $sys_name, $text, $title );
# When building a recipe, Do trial runs with a small data samples. Syntax errors are checked (except
#    awk), but run-time errors are not.
 
#  * Test each command and recipe separately before combining them.

  
#     $title = &echo_info( "Tips" );
#     $sys_name = $Common::Config::sys_name;

#     $text = qq (
# $title

#  * Put only small code pieces into recipes. Recipes should be small and easy 
#    to read. Instead consider putting larger code into script files or programs
#    that take well defined inputs and outputs.

#  * All installed commands, utilities and packages can be used, not just those
#    that come with $sys_name.

#  * Descriptive titles and good comments help colleagues understand the flow, 
#    and yourself too many months later.

#  * Keep recipes in directories or somehow organised. 

#  * All work should be done outside the main $sys_name directory. This avoids 
#    the risk of having files overwritten or deleted during $sys_name updates.

# );

#     return $text;
# }

# sub caveats
# {
#     # Niels Larsen, November 2010.

#     # Shows advice about what is good to do. Returns a text string.

#     # Returns a string.

#     my ( $sys_name, $text, $title );
  
#     $title = &echo_info( "What to avoid" );
#     $sys_name = $Common::Config::sys_name;

#     $text = qq (
# $title

# If a given command or piece of code is not given input, then the recipe 
# may hang. No attempt has been made yet to prevent that, and it is not so
# easy.

# Do not redirect input and output (with '<' and '>') within pipe sections. 
# This derails the pipe flow, since all preceding steps will have to finish
# completely before the following step can proceed. Instead, programs or code
# that cannot operate on a stream (read from STDIN and while writing to STDOUT)
# should at the moment be placed outside pipe sections as a separate step.

# );

#     return $text;
# }

# sub features
# {
#     # Niels Larsen, November 2010.

#     # Describes features and abilities and returns a text string.

#     # Returns a string.

#     my ( $text, $title );
  
#     $title = &echo_info( "Features" );

#     $text = qq (
# $title

# Currently implemented advantages over shell script files include

# 1. Simpler grammar. Bench biologists and non-programmers can understand,
#    modify, and (with one day of practice), create recipes. Like shell 
#    languages, the grammar includes arbitrary symbols which are substituted 
#    by the values given to a recipe where it is invoked. They can be used 
#    anywhere in the recipe, are checked in advance, and should not interfere 
#    with normal language variables.

# 2. Steps may different languages. Bash, Awk, Perl, Python and Ruby are 
#    supported so far. That means authors familiar with either will be able to
#    create the "glue" often needed to make different applications communicate.

# 3. Better error checks. Many recipe mistakes are caught and all code pieces 
#    are syntax checked before being run, except awk (there seems to be no way
#    to do that). Runs will not fail after five hours because of a trivial
#    error. However, runtime errors like missing files and disk space are not 
#    checked. For that do a trial run with a small data sample. 

# 4. Easier piping. Simply move the PIPE_BEGIN and PIPE_END tags to where the 
#    pipe starts and ends should be. Multiple pipes per recipe are okay, but 
#    they may of course not overlap.

# 5. Error handling. If a given step has a fatal error and exits, then the 
#    following steps will also be stopped and a log will show which step went
#    wrong and what the error message is. There will be no "zombie" processes
#    left over. A similar cleanup happens if the user interrupts the run.

# Future advantages include

# 6. Easy parallelism. There could be PARALLEL_BEGIN and PARALLEL_END tages 
#    to indicate the steps in between should be run in parallel, while waiting 
#    for the last one to finish.

# 7. Visual web controls map directly. It would be possible to create a web 
#    interface that creates recipe texts, controls their execution and reacts
#    to errors, and perhaps even monitors the data flow.

# Like shell scripts, a recipe can run other recipes, but not itself. There is
# no support for conditionals like "if this outcome, then do this, otherwise 
# that", but this can be done with a bash if statement for example. There is 
# no support for loops either. These features will be added when/if there is
# a need for them.

# );

#     return $text;
# }

# sub format
# {
#     # Niels Larsen, November 2010.

#     # Details the recipe format. Returns a text string.

#     # Returns a string.

#     my ( $sys_name, $text, $title, $lang_str, %titles );
  
#     $title = &echo_info( "Format" );
#     $sys_name = $Common::Config::sys_name;

#     $lang_str = join ", ", sort keys %{ &Recipe::Help::language_hash() };

#     %titles = (
#         "main" => "Main recipe",
#         "comments" => "Comments",
#         "recipe" => "Recipe steps",
#         "normal" => "Language steps",
#         "pipes" => "Pipe steps",
#         "symbols" => "Symbols",
#         "files" => "File names",
#         );

#     %titles = map { $_, &Common::Messages::echo_bold_cyan( $titles{ $_ } ) } keys %titles;

#     $text = qq (
# $title

# $titles{'main'}

# A recipe title must be given before any recipe steps, and in this form,

# title = Some recipe title

# $titles{'comments'}

# Lines that start with a pound sign "#" are ignored. Inline comments, that 
# is lines with "#" followed by a comment, are also allowed, but when in code
# lines, they are passed to the given language interpreter (where they may or
# may not be errors). An __END__ tag can be placed anywhere to execute only 
# parts of a recipe; all lines that follow are then ignored.

# $titles{'recipe'}

# A given recipe may run sub-recipes, but not one of its 'parents'. The
# grammar for running another recipe is the same as for the run_recipe script,

# recipe: recipe_file_name SOME_SYMBOL='some value' OTHER_SYMBOL='other value'

# $titles{'normal'}

# They follow this grammar,

# language: Some step title                      (step type and header)
#    input = input_file_name                     (step input - OPTIONAL)
#    output = output_file_name                   (step output - OPTIONAL)
#    code and/or commands                        (step code)
#    that can span multiple lines                (step code)

# with a step header that includes type and title, followed by one or more 
# optional input/output, then one or more code lines. Supported languages are,

#    $lang_str

# The step title is mandatory and must be a single line of text. Having to 
# write a title forces the author to state what the step does, which is good. 
# The step type must not be indented, but the lines that follow may, by one or
# more columns. 

# $titles{'pipes'}

# Pipe steps are normal steps, except they are between PIPE_BEGIN and PIPE_END
# tags. Such steps form a pipeline. The first step in the pipeline should be 
# be given input from a file, and the last step write to one. This can be done
# with the 'input =' and 'output =' lines, or with symbols. All steps must be 
# 'pipeable', which means they read from STDIN and write to STDOUT. If one of
# the steps does not do this, then end the pipe there. A pipe can also be 
# started with 'cat \$INPUT_FILE'. See the examples. 

# $titles{'symbols'}

# Symbols can be used anywhere in the recipe text. A step that uses symbols 
# could look like

# awk: \$INPUT_TITLE
#    input = \$INPUT_FILE
#    output = \$OUTPUT_FILE
#    a few awk code statements
#    perhaps also with embedded symbols

# $titles{'files'}

# File names may only include alphanumeric characters, plus dashes, periods,
# and underscores. However, when for example '*' is used as part of an input
# file name, then that name is turned into a list, as the shell would do it.
# This makes it much easier to loop across many input data files.

# );

#     return $text;
# }
