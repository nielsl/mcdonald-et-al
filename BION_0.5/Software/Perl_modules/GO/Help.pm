package GO::Help;     #  -*- perl -*-

# Help texts for GO pages. 

use warnings;
use strict;

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &general
                 );

use GO::Widgets;

use Common::Config;
use Common::Messages;
use Common::Tables;
use Common::Widgets;

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
        $title = "Gene Ontology View";
        $arrow = &Common::Widgets::arrow_right;

        $control_icon = &GO::Widgets::control_icon();
        $control_menu = &GO::Widgets::control_menu( undef, 1 );

        $body = qq (
<p>
This page is a Gene Ontology viewer. The titles can be opened, closed, 
searched and made title of the page. Additional data can be superimposed, 
such as pre-calculated statistics, experimental data or search results. 
</p>

<h4>Credits</h4>

<p>
The Gene Ontology (GO) project is a collaborative effort between a number of
institutions and companies, with an editorial office located at the European
Bioinformatics Institute. Please visit <tt>http://www.geneontology.org</tt> for
more detail. We are most grateful to be able to use this great resource. 
</p>

<h4>Basic Navigation</h4>

<p>
Right-arrows open nodes. Down-arrows indicate that a node is open 
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
<li><p><tt>Add Ontology IDs</tt>. A column with GO term IDs are inserted to 
the immediate left of the term titles. Each ID links to a small summary page
for a given term. 
</p></li>

<li><p><tt>Add Taxonomy links</tt>. A column with a blue header and small square 
buttons are added to the immediate left of the term titles. Each button 
shows the organismal distribution of a given functional sub-system. It does
this by showing your currently selected taxonomy tree with one new column
inserted. This column shows, for each organism or organism group, the number
of organisms that have one or more genes annotated as something under the 
given sub-system. 
</p></li>

<li><p><tt>Select rows, none</tt>. An un-checked checkbox will appear for each GO 
term. By pressing the save button, selections can be saved under a given name. 
The selections made this way can be used on other pages.
</p></li>

<li><p><tt>Select rows, all</tt>. Like the above, except the checkboxes are 
checked. 
</p></li>

<li><p><tt>Select columns, none</tt>. This is mostly for convenience: when 
many columns are included, it becomes tedious to remove them one-by-one. A
row of un-checked checkboxes are shown, along with a delete button. 
</p></li>

<li><p><tt>Select columns, all</tt>. Like the above, except the checkboxes are 
checked. 
</p></li>

<li><p><tt>Compare columns</tt>. Adds a row of un-checked checkboxes, along 
with a 'Compare columns' button. With one or more taxonomy columns selected,
this button will show a 'difference tree': only terms are shown where there 
is a difference between one organism, or organism group, and the others.
</p></li>
</ul>

<p>
<h4><img src="$Common::Config::img_url/sys_data_book.png" align="center">&nbsp;&nbsp;Data menu</h4>
The icon opens a menu of menus, one per data category. These menus are,

<p>
<h4>Statistics menu</h4>
A menu of mostly pre-calculated statistics,
<ul>
<li><p><tt>Gene counts, term</tt>. The number of genes directly annotated to 
a given term. This gives an impression of how specific a given annotation is. 
</p></li>

<li><p><tt>Gene counts, total</tt>. The total number of genes directly annotated 
to something within a given term. The counts may include the same gene more than
once, since each term can occur multiple times within. 
</p></li>

<li><p><tt>Gene counts, unique</tt>. As the above, except each gene is only 
counted once. 
</p></li>

<li><p><tt>Term counts, total</tt>. The total number of terms under a given
term. The counts may include the same term more than once, since each term 
can occur multiple times within. 
</p></li>

<li><p><tt>Term counts, unique</tt>. As the above, except each term is only 
counted once. 
</p></li>

<li><p><tt>Organisms, unique</tt>. The number of organisms which have one or
more annotations under a given term. The counts are unique, i.e. each organism
is only counted once. 
</p></li>
</ul>
</p>

<p>
<h4>GO selections menu</h4>
The menu contains previously saved GO term selections, plus some
defaults that appear when you first visit this page. Selecting an option
will show the minimal tree that spans the terms originally selected. You may 
delete a selection by pressing the delete button that will appear. 
</p>

<p>
<h4>Taxonomy selections menu</h4>
The menu contains previously saved organism selections, plus 
some defaults that appear when you first visit the organism taxonomy page.
After selecting an option a blue column will be added to the immediate left
of the GO titles. The numbers are the number of GO terms within a given GO
category that have been annotated to the selected organism set. 
</p>

<p>
<h4><img src="$Common::Config::img_url/sys_search.gif" align="center">&nbsp;Search window</h4>
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
