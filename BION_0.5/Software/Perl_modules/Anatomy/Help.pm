package Anatomy::Help;     #  -*- perl -*-

# Help texts for anatomy pages. 

use warnings;
use strict;

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &fly
                 &mouse
                 &plant
                 );

use Anatomy::Widgets;

use Common::Config;
use Common::Messages;
use Common::Tables;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub fly
{
    # Niels Larsen, October 2004.

    # Writes main help for the plant anatomy viewer page. 

    my ( $section,   # Help section
         ) = @_;

    $section ||= "main";

    # Returns a string. 
    
    my ( $xhtml, $title, $arrow, $body, 
         $control_menu, $control_icon, $data_icon, $data_menu );
    
    if ( $section eq "main" )
    {
        $title = "Fly Anatomy Ontology";
        $arrow = &Common::Widgets::arrow_right;

        $control_icon = &Anatomy::Widgets::control_icon();
        $control_menu = &Anatomy::Widgets::control_menu( undef, 1 );

        $body = qq (<p>

This page is the beginning of a fly anatomy ontology viewer. The titles
can be opened, closed, searched and made title of the page. Additional data
can be superimposed, currently only pre-calculated node-counts, but it is 
prepared for any data that connect to plant anatomy, directly or indirectly. 

</p>
<h4>Credits</h4>
<p>

The fly ontology is maintained by the Fly Consortium, an
international collaborative effort funded by the National Institute of Health
(U.S.A.) and Medical Research Council (U.K.). Please visit

<p> <tt>http://www.flybase.org</tt></p>

for more detail. We are most grateful to be able to use this fine resource. 

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

</p>
<h4><img src="$Common::Config::img_url/sys_menu.png" align="center">&nbsp;&nbsp;Control menu</h4>
<p>

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
<li><p><tt>Ontology IDs</tt>. A column with internal IDs is inserted 
to the immediate left of the titles. Each ID links to a small summary page that lists
what is known about it. 
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

The menu contains previously saved anatomy term selections, plus some
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

sub mouse
{
    # Niels Larsen, October 2004.

    # Writes main help for the adult mouse anatomy viewer page. 

    my ( $section,   # Help section
         ) = @_;

    $section ||= "main";

    # Returns a string. 
    
    my ( $xhtml, $title, $arrow, $body, 
         $control_menu, $control_icon, $data_icon, $data_menu );
    
    if ( $section eq "main" )
    {
        $title = "Mouse Anatomy Ontology";
        $arrow = &Common::Widgets::arrow_right;

        $control_icon = &Anatomy::Widgets::control_icon();
        $control_menu = &Anatomy::Widgets::control_menu( undef, 1 );

        $body = qq (<p>

This page is the beginning of a mouse anatomy ontology viewer. The titles
can be opened, closed, searched and made title of the page. Additional data
can be superimposed, currently only pre-calculated node-counts, but it is 
prepared for any data that connect to plant anatomy, directly or indirectly. 

</p>
<h4>Credits</h4>
<p>

The Anatomical Dictionary for the Adult Mouse has been developed by Terry Hayamizu,
Mary Mangan, John Corradi and Martin Ringwald, as part of the Gene Expression
Database (GXD) Project, Mouse Genome Informatics (MGI), The Jackson Laboratory,
Bar Harbor, ME.  Copyright 2003 The Jackson Laboratory. Please visit

<p> <tt>http://www.jax.org</tt></p>

for more detail. We are most grateful to be able to use this fine resource. 

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

</p>
<h4><img src="$Common::Config::img_url/sys_menu.png" align="center">&nbsp;&nbsp;Control menu</h4>
<p>

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
<li><p><tt>Ontology IDs</tt>. A column with internal IDs is inserted 
to the immediate left of the titles. Each ID links to a small summary page that lists
what is known about it. 
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

The menu contains previously saved anatomy term selections, plus some
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

sub plant
{
    # Niels Larsen, October 2004.

    # Writes main help for the plant anatomy viewer page. 

    my ( $section,   # Help section
         ) = @_;

    $section ||= "main";

    # Returns a string. 
    
    my ( $xhtml, $title, $arrow, $body, 
         $control_menu, $control_icon, $data_icon, $data_menu );
    
    if ( $section eq "main" )
    {
        $title = "Plant Anatomy Ontology";
        $arrow = &Common::Widgets::arrow_right;

        $control_icon = &Anatomy::Widgets::control_icon();
        $control_menu = &Anatomy::Widgets::control_menu( undef, 1 );

        $body = qq (<p>

This page is the beginning of a plant anatomy ontology viewer. The titles
can be opened, closed, searched and made title of the page. Additional data
can be superimposed, currently only pre-calculated node-counts, but it is 
prepared for any data that connect to plant anatomy, directly or indirectly. 

</p>
<h4>Credits</h4>
<p>

The plant ontology is maintained by the Plant Ontology Consortium, an
international collaborative effort funded by the National Science Foundation
(U.S.A.) and others. Please visit

<p> <tt>http://plantontology.org</tt></p>

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

</p>
<h4><img src="$Common::Config::img_url/sys_menu.png" align="center">&nbsp;&nbsp;Control menu</h4>
<p>

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
<li><p><tt>Ontology IDs</tt>. A column with internal IDs is inserted 
to the immediate left of the titles. Each ID links to a small summary page that lists
what is known about it. 
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

The menu contains previously saved anatomy term selections, plus some
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
