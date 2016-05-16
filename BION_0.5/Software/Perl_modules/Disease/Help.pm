package Disease::Help;     #  -*- perl -*-

# Help texts for GO pages. 

use warnings;
use strict;

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &general
                 );

use Disease::Widgets;

use Common::Config;
use Common::Messages;
use Common::Tables;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub general
{
    # Niels Larsen, December 2003.

    # Writes general help for the GO viewer page. NOTE: there are 
    # formatting statements in here because I couldnt get the style 
    # sheets to work right in Mozilla.

    my ( $section,
         ) = @_;

    $section ||= "main";

    # Returns a string. 
    
    my ( $xhtml, $title, $arrow, $body, 
         $control_menu, $control_icon, $data_icon, $data_menu );
    
    if ( $section eq "main" )
    {
        $title = "Disease Ontology View";
        $arrow = &Common::Widgets::arrow_right;

        $control_icon = &Disease::Widgets::control_icon();
        $control_menu = &Disease::Widgets::control_menu( undef, 1 );

        $body = qq (<p>

This page is the beginning of a disease ontology viewer. The titles can
be opened, closed, searched and made title of the page. Additional data 
can be superimposed, currently only pre-calculated node-counts, but it 
is prepared for any data that connect to disease, directly or indirectly. 

</p>
<h4>Credits</h4>
<p>

The Disease Ontology project is curated by Patricia Dyck and Rex Chisholm 
at Center for Genetic Medicine, Northwestern University, USA. Please visit

<p><tt>http://diseaseontology.sourceforge.net</tt></p>

for more detail. We are most grateful to be able to use this great resource. 

</p>
<h4>Basic Navigation</h4>
<p>

Right-arrows open nodes. Down-arrows indicate that a node is open 
and that it can be closed by clicking. Clicks on a given title defines 
that node as the new top node of the displayed subtree; parent nodes are 
then available in the menu immediately above the top node. Titles with a 
light-yellow background are titles without "children" which cannot be 
expanded further. 

</p><p>

In the optional columns (explained below), all colored buttons are clickable: 
pressing a 'raised' button expands the graph so all terms are seen which has 
that statistic or feature; pressing again does the opposite. Columns can be
removed by clicking on their titles.

</p><p>

<h4><img src="$Common::Config::img_url/sys_menu.png" align="center">&nbsp;&nbsp;Control menu</h4>

</p><p>

The icon opens a menu with the following options,

</p><p>
<ul>
<li><p><tt>Select, unchecked</tt>. An column will appear with an un-checked 
checkbox for each term. By pressing the save button, selections can be saved
under a given name. The selections made this way can be used on other pages.
</p></li>

<li><p><tt>Select, checked</tt>. Like the above, except the checkboxes are 
initially checked. 
</p></li>
</ul>

</p>
<h4><img src="$Common::Config::img_url/sys_data_book.png" align="center">&nbsp;&nbsp;Data menu</h4>
<p>

The icon opens a menu with the following choices,

</p><p>

<ul>
<li><p><tt>Ontology IDs</tt>. A column with internal disease term IDs are inserted 
to the immediate left of the titles. Each ID links to a small summary page that lists
what is known about it. 
</p></li>

<li><p><tt>ICD9 codes</tt>. A column with ICD9 codes are inserted to the immediate
left of the titles. Each code links to a small summary page that lists what is known
about the corresponding title. 
</p></li>

<li><p><tt>Statistics menu -&gt;</tt>. A new menu will appear with statistics
choices (see below.) 
</p></li>

<li><p><tt>Selections menu -&gt;</tt>. A new menu will appear where previously
saved selections can be recalled. 
</p></li>
</ul>

</p>
<h4>Statistics menu</h4>
<p>

A menu of mostly pre-calculated statistics,

</p><p>

<ul>
<li><p><tt>Term counts, total</tt>. The total number of terms under a given
term. The counts may include the same term more than once, since each term 
can occur multiple times within. 
</p></li>

<li><p><tt>Term counts, unique</tt>. As the above, except each term is only 
counted once. 
</p></li>
</ul>

</p>
<h4>Selections menu</h4>
<p>

The menu contains previously saved disease term selections, plus some
defaults that appear when you first visit this page. Selecting an option
will show the minimal tree that spans the terms originally selected. You may 
delete a selection by pressing the delete button that will appear. 

</p>
<h4><img src="$Common::Config::img_url/sys_search.gif" align="center">&nbsp;Search window</h4>
<p>

Searches the displayed graph. A search window is opened, which presents a 
few simple search options that are explained within.

</p>

);
    }

    $xhtml = &Common::Widgets::help_page( $body, $title );

    return $xhtml;
}


1;


__END__
