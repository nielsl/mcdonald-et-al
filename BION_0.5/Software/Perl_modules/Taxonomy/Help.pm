package Taxonomy::Help;     #  -*- perl -*-

# Help texts for taxonomy pages. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &pager
                 &section_main
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Widgets;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Sys_name = $Common::Config::sys_name;

our %Dispatch_dict = (
    "org_profile_seqs" => [ qw ( intro method ) ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub dispatch
{
    # Niels Larsen, January 2013.

    # Dispatch different help page requests. The first argument is the
    # program name that invoked it, then second is the type of help to 
    # be shown. If "org_profile_seqs" is given as first argument and 
    # "intro" as the second, then the routine org_profile_seqs_intro
    # is invoked.

    my ( $prog,           # Program string like "org_profile_seqs"
         $request,        # Help page name like "intro" - OPTIONAL, default "intro"
         ) = @_;

    # Returns a string. 

    my ( $text, $routine, $choices, @msgs, $opts, @opts );

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

    if ( $opts[0] eq "credits" ) {
        $routine = __PACKAGE__ ."::seq_credits";
    } else {
        $routine = __PACKAGE__ ."::$prog" ."_$opts[0]";
    }

    no strict "refs";
    $text = &{ $routine };

    $text =~ s/\n/\n /g;
    chop $text;

    if ( defined wantarray ) {
        return $text;
    } else {
        print $text;
    }

    return;
}

sub org_profile_seqs_intro
{
    # Niels Larsen, January 2013.

    my ( $text, $title );
  
    $title = &echo_info("Introduction");

    $text = qq (
$title

Produces a taxonomic profile from a collection of query sequences
and a reference database with indexed taxonomy. Similarities are 
generated and mapped onto the taxonomy.

These help options have more descriptions,

    --help method
    --help usage
    --help settings
    --help perform

Options can be abbreviated, for example '--help p' will print the 
section with performance.

);

    return $text;
}

sub org_profile_seqs_method
{
    my ( $text, $title, $sim_title, $tax_title );
  
    $title = &echo_info("Method");
    $sim_title = &echo_info("Similarities");
    $tax_title = &echo_info("Taxonomy");

    $text = qq (
$title

Creating taxonomic overview of sequence similarities is a two-step process:
First similarities with reference sequences are made, then these are mapped 
onto the corresponding reference taxonomy.

$sim_title

They are made with seq_simrank, which produces a three-column table with query
sequence id, query oligo count and reference similarities in each row. Simrank 
can skip low quality spots in the query sequences, show very low similarities
and is quite fast. See seq_simrank --help for details. 

$tax_title

The similarities from the table are mapped onto the reference taxonomy. First
a score-tree is made with all the best similarities for a given query sequence.

CONTINUE

    # This routine maps sequence similarities onto a taxonomic tree that has 
    # reference database sequences as leaves. Input is a string with similarity
    # tuples [ seq_id, sim_pct ] for a single query sequence, where seq_id is 
    # from a reference dataset. These are the current steps, 
    # 
    # 1. Increment node score for every similarity tuple. If many matching 
    #    sequences have the same taxonomy, then that node's score is incremented
    #    as many times. The strongest similarities get the highest counts through
    #    a weighting scheme: lower similarities are weighted down to the extent 
    #    defined by the "sim_wgt" argument. The result is scoring at the sequence
    #    level, with "smear" as many nodes often match equally and get very 
    #    small contributions each.
    #    
    # 2. If there are multiple scores under a given node and all are identical,
    #    then add them and assign the score sum to the parent node. Work from 
    #    the leaves toward higher branches, but stop when there is only one score
    #    under a node or they are all different. The result is that identical 
    #    similarities "diffuse" upwards in the tree.
    #
    # 3. Multiple taxa may still have identical scores after the above steps,
    #    especially with short reads. There are now three options,
    #    
    #    a. Leave as is. Combined with high minimum similarity this is useful
    #       for seeing all groups that match. 
    # 
    #    b. Discard them. Return nothing and put the score total into an 
    #       "ambiguous" category to be shown separately in the outputs. The 
    #       output will then show only the matches that are higher for a 
    #       particular taxon. 
    # 
    #    c. Count scores under the parents that exactly spans the nodes with 
    #       identical scores. This will show all matches, but move non-unique 
    #       scores towards higher nodes.


);

    return $text;
}

sub section_main
{
    my ( $title, $arrow, $body, $menu, $opt );

    $title = "Organism View";
    $arrow = &Common::Widgets::arrow_right;
    
    $body = qq (
<p>
This is an HTML based viewer for organism taxonomies. The taxa can 
be opened, closed, zoomed into and out of, and searched. Its main purpose
is to superimpose or "project" data that somehow map to organisms (but this 
has not been implemented yet). Expect it to connect with alignments and 
functions, for example. 
</p>

<h4>Hierarchy Navigation</h4>

<p>
<u>Right Arrows</u> open nodes. <u>Down arrows</u> close nodes.
<u>Group names</u> zooms in by making that group the new title of the page.
<u>Parents menu</u> zooms out by making the selected group the new title of the page.
       This menu is located immediately above the first group.
</p>

<h4>Column Navigation</h4>

<p>
Clicks on <u>Column titles</u> makes that column go away. <u>Raised colored buttons</u>
expand the hierarchy when clicked and <u>Depressed colored buttons</u> close them. 
<u>Small grey dots</u> launch small report pages.
</p>

<p>
<h4><img src="$Common::Config::img_url/sys_search.gif" align="center">&nbsp;Search</h4>
Searches the displayed hierarchy. A search window is opened, which presents a 
few simple search options that are explained within.
</p>

<p>
<h4><img src="$Common::Config::img_url/sys_params_large.png" align="center">&nbsp;&nbsp;Control menu</h4>
The icon opens a menu with the following options,

<ul>
);

    $menu = Taxonomy::Menus->control_menu( undef, "" );

    foreach $opt ( $menu->options )
    {
        $body .= qq (<li><p><u>). $opt->title . qq(</u>. ). $opt->helptext . qq (</p></li>\n);
    }

    $body .= qq (
</ul>
<p>
&nbsp;
</p>
);

    return ( $title, $body );
}


1;


__END__

        $title = "Taxonomy View";
        $arrow = &Common::Widgets::arrow_right;

        $body = qq (
<p>
This page is a taxonomy viewer. The taxa can be opened, closed, 
searched and made title of the page. Additional data can be superimposed, 
e.g. pre-calculated statistics, experimental data or search results. 
</p>

<h4>Credits</h4>

<p>
The NCBI Taxonomy is a curated hierarchy of organism classifications taken
from various primary sources. We are most grateful to be able to use this 
great resource. Please visit the home page of the project at 
<tt>http://www.ncbi.nlm.nih.gov/Taxonomy</tt>, which has instructions for 
literature citation.
</p>

<h4>Basic Navigation</h4>

<p>
The right-arrows open nodes. The down-arrow indicates that a node is open 
and that it can be closed by clicking. Clicks on a given title defines 
that node as the new top node of the displayed subtree; parent nodes are 
then available in the menu immediately above the top node. Titles with a 
light-yellow background are titles without "children" which cannot be 
expanded further. 
</p>
<p>
In the optional columns (explained below), all colored buttons are clickable: 
pressing a 'raised' button expands the graph so all terms are seen which has 
that statistic or feature; pressing again does the opposite. Columns can be
removed by clicking on their titles.
</p>

<p>
<h4><img src="$Common::Config::img_url/sys_menu.png" align="center">&nbsp;&nbsp;Control menu</h4>
The icon opens a menu with the following options,

<ul>
<li><p><tt>Add Taxon IDs</tt>. A column with taxonomy IDs are inserted to 
the immediate left of the term titles. 
</p></li>

<li><p><tt>Add GO links</tt>. A column with an orange header and small square 
buttons are added to the immediate left of the taxon titles. Each button 
shows a "functional overview" of a given organism or organism group. It does
this by showing your currently selected GO tree with one new column inserted. 
This column shows, for each GO term, the number of terms that were annotated 
to a the given organism group via its genes. 
</p></li>

<li><p><tt>Select taxa, none</tt>. An un-checked checkbox will appear for each
taxon. By pressing the save button, selections can be saved under a given name. 
The selections made this way can be used on other pages.
</p></li>

<li><p><tt>Select taxa, all</tt>. Like the above, except the checkboxes are 
checked. 
</p></li>

<li><p><tt>Select columns, none</tt>. This is mostly for convenience: when 
many columns are included, it becomes tedious to remove them one-by-one. A
row of un-checked checkboxes are shown, along with a delete button. 
</p></li>

<li><p><tt>Select columns, all</tt>. Like the above, except the checkboxes are 
checked. 
</p></li>
</ul>

<p>
<h4><img src="$Common::Config::img_url/sys_data_book.png" align="center">&nbsp;&nbsp;Data menu</h4>
The icon opens a menu of menus, one per data category. These menus are,

<p>
<h4>Statistics menu</h4>
A menu of mostly pre-calculated statistics,

<ul>
<li><p><tt>Organisms total</tt>. The total number of organisms under a 
given taxon title. 
</p></li>

<li><p><tt>Organisms with protein</tt>. The number of organisms, under a 
given taxon, for which one or more protein genes have been assigned. 
</p></li>

<li><p><tt>Organisms with DNA</tt>. The number of organisms, under a given
given taxon, which have known DNA. 
</p></li>

<li><p><tt>Organisms with GO terms</tt>. The number of organisms, under a given
taxon, that contain genes with assigned Gene Ontology terms. 
</p></li>

<li><p><tt>GO terms, total</tt>. The total number Gene Ontology terms that 
have been assigned to this taxon. 
</p></li>

<li><p><tt>GO terms, unique</tt>. As previous, except each term is only 
counted once. 
</p></li>

<li><p><tt>Proteins total</tt>. The total number of proteins within each 
taxon, as taken from the SEED collection. 
</p></li>

<li><p><tt>DNA total</tt>. The total number of DNA bases within each 
taxon, as taken from the EMBL data library. 
</p></li>

<li><p><tt>DNA G+C percentages</tt>. Shows a gradient that reflects the G+C 
percentage distribution among the organisms within a given taxon. Just a display
experiment.
</p></li>
</ul>

<p>
<h4>Taxonomy selections menu</h4>
The menu contains previously saved taxon selections, plus a few defaults that 
appear when this page is visited for the first time. To create a selection, 
first choose the 'Select taxa, none' option, select a few taxa with the checkboxes, 
type in a title and press the 'Save Selection' button. Your title should now appear
in this menu. Selecting an option will show the minimal tree that spans the terms 
originally selected. You may delete a selection by pressing the delete button that
will appear. 
</p>

<p>
<h4>GO selections menu</h4>
The menu contains previously saved GO term selections, plus a few defaults that 
appear when this page is visited for the first time. After selecting an option 
an orange column will be added to the immediate left of the taxonomy titles. 
The numbers are the number of GO terms within a given taxonomy category that 
have been annotated to an organism amont that selected organism set.
</p>

<p>
<h4><img src="$Common::Config::img_url/sys_search.gif" align="center">&nbsp;Search window</h4>
Searches the displayed hierarchy. A search window is opened, which presents a 
few simple search options that are explained within.
</p>

);
    }

<h4>Credits</h4>

<p>
The NCBI Taxonomy is a curated hierarchy of organism classifications taken
from various primary sources. We are most grateful to be able to use this 
great resource. Please visit the home page of the project at 
<tt>http://www.ncbi.nlm.nih.gov/Taxonomy</tt>, which has instructions for 
literature citation.
</p>
