package Common::Info;     #  -*- perl -*-

# This module contains routines which generate documentation in xhtml
# format. We could have made separate static documents, but then we 
# cannot insert dynamically generated output (like statistics) without
# using some PHP-like methods. And thats more than its worth. And since
# the routines all generate strict xhtml we could write a routine that
# creates a printed manual dynamically, one which describes the exact
# data and software that are included in a given system version. 

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &blast
                 &browse_button
                 &contact
                 &credits
                 &dispatch
                 &expression
                 &frontpage
                 &plans
                 &platform
                 &rna
                 &rrna
                 &status
                 );

use Common::Config;
use Common::Messages;

use Common::States;
use Common::Widgets;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub browse_button
{
    # Niels Larsen, March 2004.
    
    # Returns a "Just Browse" button which will invoke one of 
    # the main viewers.

    my ( $sid,       # Session id
         $fgcolor,   # Foreground tooltip color - OPTIONAL
         $bgcolor,   # Background tooltip color - OPTIONAL
         ) = @_;

    # Returns an xhtml string. 

    my ( $url, $args, $xhtml, $tip );

    $bgcolor ||= "#003366";
    $fgcolor ||= "#ffffcc";

    $url = qq ($Common::Config::cgi_url/index.cgi?);
    $url .= "session_id=$sid" if $sid;
    $url .= ";page=taxonomy;request=focus_node;tax_click_id=2";
    $url .= ";menu_1=taxonomy;menu_2=Bacteria;logged_in=0";

    $tip = qq (Displays the default organism hierarchy view, fully functional. But)
         . qq ( no saved selections or preferences will be kept after the browser is)
         . qq ( closed. With a free account however, all selections,)
         . qq ( preferences and views will be kept until next login.);

    $args = qq (LEFT,OFFSETX,-150,OFFSETY,20,WIDTH,250,CAPTION,'Just browse',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor',BORDER,3);

    $xhtml  = qq (   <a href="$url">)
            . qq (   <input type="button" class="summary_button" value="Just browse")
            . qq (   onmouseover="return overlib('$tip',$args);")
            . qq (    onmouseout="return nd();" /></a>);
    
    return $xhtml;
}

sub dispatch
{
    # Niels Larsen, January 2004.

    # Invokes Returns xhtml for a page given by the "info_request" key in the 
    # "about" state.

    my ( $sid,        # Session ID
         $request,    # Request string
         ) = @_;

    # Returns a string.
    
    my ( $state, $requests, $xhtml );

    if ( not $sid ) {
        &Common::Messages::error( qq (No session ID given) );
        exit;
    }

    if ( not $request )
    {
        $request = &Common::States::restore_state( $sid, "info" )->{"info_request"};
    }
    
    $requests = 
    {
        "about" => \&Common::Info::contact,
        "blast" => \&Common::Info::blast,
        "contact" => \&Common::Info::contact,
        "credits" => \&Common::Info::credits,
        "expression" => \&Common::Info::expression,
        "summary" => \&Common::Info::frontpage,
        "plans" => \&Common::Info::plans,
        "platform" => \&Common::Info::platform,
        "rna" => \&Common::Info::rna,
        "rrna" => \&Common::Info::rrna,
    };        

    if ( exists $requests->{ lc $request } )
    {
        $xhtml = &{ $requests->{ lc $request } }( $sid );
    }
    else
    {
        &Common::Messages::error( qq (Unrecognized info_request key -> "$request") );
    }

    return $xhtml;
}

sub blast
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the blast page.

    # Returns a string. 

    my ( $xhtml, $ramp, @colors, @rb_bars, @rg_bars, @m_bars, $width, $index, $row );

    # ----------- Generate red -> blue bars,

    $ramp = &Common::Util::color_ramp( "#ff0000", "#6666ff", 100 );

    push @rb_bars, qq (<table cellspacing="2">\n);

    @colors = ( 
                [ $ramp->[0], 5 ],
                [ $ramp->[10], 3 ],
                [ $ramp->[15], 2 ],
                [ $ramp->[40], 4 ],
                [ $ramp->[60], 2 ],
                [ $ramp->[80], 1 ],
                );
               
    push @rb_bars, "<tr><td>Group 1&nbsp;</td><td>". &Common::Widgets::summary_bar( \@colors, 50, 15, $ramp ) ."</td></tr>";

    @colors = ( 
                [ $ramp->[30], 2 ],
                [ $ramp->[50], 2 ],
                [ $ramp->[60], 1 ],
                [ $ramp->[85], 2 ],
                [ $ramp->[90], 3 ],
                [ $ramp->[99], 3 ],
                );
               
    push @rb_bars, "<tr><td>Group 2&nbsp;</td><td>". &Common::Widgets::summary_bar( \@colors, 50, 15, $ramp ) ."</td></tr>";

    push @rb_bars, "</table>\n";

    # ----------- Generate red -> grey bars,

    $ramp = &Common::Util::color_ramp( "#ff0000", "#dddddd", 100 );

    push @rg_bars, qq (<table cellspacing="2">\n);

    @colors = ( 
                [ $ramp->[0], 5 ],
                [ $ramp->[10], 3 ],
                [ $ramp->[15], 2 ],
                [ $ramp->[40], 4 ],
                [ $ramp->[60], 2 ],
                [ $ramp->[80], 1 ],
                );
               
    push @rg_bars, "<tr><td>Group 1&nbsp;</td><td>". &Common::Widgets::summary_bar( \@colors, 50, 15, $ramp ) ."</td></tr>";

    @colors = ( 
                [ $ramp->[30], 2 ],
                [ $ramp->[50], 2 ],
                [ $ramp->[60], 1 ],
                [ $ramp->[85], 2 ],
                [ $ramp->[90], 3 ],
                [ $ramp->[99], 3 ],
                );
               
    push @rg_bars, "<tr><td>Group 2&nbsp;</td><td>". &Common::Widgets::summary_bar( \@colors, 50, 15, $ramp ) ."</td></tr>";

    push @rg_bars, "</table>\n";

    # ----------- Generate bars with green blips,

    $ramp = &Common::Util::color_ramp( "#00aa00", "#ffffff", 3 );

    push @m_bars, qq (<table cellspacing="2">\n);

    @colors = ( 
                [ $ramp->[2], 5 ],
                [ $ramp->[0], 3 ],
                [ $ramp->[1], 2 ],
                [ $ramp->[2], 8 ],
                [ $ramp->[0], 2 ],
                [ $ramp->[1], 2 ],
                [ $ramp->[2], 8 ],
                [ $ramp->[1], 1 ],
                [ $ramp->[0], 2 ],
                [ $ramp->[2], 2 ],
                );
               
    push @m_bars, "<tr><td>Sequence 1&nbsp;</td><td>". &Common::Widgets::summary_bar( \@colors, 60, 15, $ramp ) ."</td></tr>";

    @colors = ( 
                [ $ramp->[2], 5 ],
                [ $ramp->[0], 1 ],
                [ $ramp->[1], 3 ],
                [ $ramp->[2], 8 ],
                [ $ramp->[0], 2 ],
                [ $ramp->[1], 2 ],
                [ $ramp->[2], 8 ],
                [ $ramp->[1], 1 ],
                [ $ramp->[0], 1 ],
                [ $ramp->[2], 3 ],
                );
               
    push @m_bars, "<tr><td>Sequence 2&nbsp;</td><td>". &Common::Widgets::summary_bar( \@colors, 60, 15, $ramp ) ."</td></tr>";

    push @m_bars, "</table>\n";

    $xhtml = qq (
<div id="info_page">

<h2>Summary</h2>

<table cellpadding="5" id="info_summary">

<tr><td>
Todays most common computer analysis task among biologists is to submit a 
sequence for similarity search. The result comes back soon after as a long 
list of aligned fragments that is difficult to survey; the user must choose
either to see only the best matches or to drown in details. 
</td></tr>
<tr><td>
Our solution is to use the existing viewers to create high-level overviews
of which organisms, functions or chromosomal neighborhoods that match. This
way the user will get an immediate impression of where the strong matches 
and a better feel for how much above the "noise level" these matches are.
</td></tr>
<tr><td>
Second, we improve the accuracy of the analysis by combining matches with 
the same database sequence into one score and by ranking good short matches
higher than a less good longer ones.
</td></tr>

</table>

<h2>Search Software</h2>
<p>
The service could be based on local versions of the widely used NCBI blast
or WU-blast and/or the the request could simply be forwarded to a remote 
server and the result collected and distilled for display. 
</p>
<p>
An alternative blast implementation written by Denis Kaznadzey and coworkers
offers several advantages. It is faster, particularly when the query sequence(s)
are large, and it allows searches against arbitrary subsets of the data. 
However it is closely coupled with a database called SciDM (written by the
same authors) which needs to be ported from Windows to Unix. We hope to be 
able to use this version eventually.
</p>

<h2>Target Selection</h2>
<p>
Today users usually search against all DNA or all protein, because results 
come back quickly and there is no easy way to specify custom organism sets.
But narrowing the searches reduces the noise level and thus exposes weaker 
matches. It may even necessary for interpretation of results - consider 
submitting a protein sequence to see which organisms have a similar one: 
there will be false negatives for all organisms for which there is no 
complete or near-complete genome. A search against only complete or near
complete genomes/proteomes would remedy that problem. The organism viewer
(under Organisms above) can be used for input selection.
</p>

<h2>Scores</h2>
<p>
Blast tends to score a long imperfect match higher than a shorter perfect 
match. This is for most practical purposes wrong and we would like to add 
a score which changes this priority.
</p>
<p>
If a protein query sequence matches with a given database sequence in three 
different spots then three fragments are listed each with their separate score.
The result is that these small matches often drop off the bottom of the list.
But if the scores were combined the hits would rank much higher on the list.
</p>

<h2>Outputs</h2>
<p>
Users need top-level overviews of search results. Some users are interested
in how strong matches are in different organism groups, others wish to know 
approximately which functions match and yet others would like to examine the 
chromosomal neighborhood of the matches. We should therefore project the 
summaries of matches on each of the viewers, so the user may invoke the viewer
that can show the desired kind of overview. 
</p>
<p>
We will be able to do this with the viewers being developed for our genomics 
platform. Summary bars can be shown in many ways, here is simple example 
where red color means strong match and blue weak,
</p>
<table><tr><td width="50"></td><td>
@rb_bars
</td></tr></table>
<p>
or even simpler,
<table><tr><td width="50"></td><td>
@rg_bars
</td></tr></table>
</p>
<p>
This way one can see both the strength of matches and their relative proportion. 
The absolute numbers could either be given as a separate column. In real examples
with large numbers of these bars stacked as cells in a spreadsheet the patterns 
of difference become much easier to see. This kind of "summary bar" can be used 
for organisms but of course also for a function hierarchy or any other context.
Even with a very large number of underlying similarities the user still sees a 
clear picture. This means the match cutoff can be dramatically lowered. A lower 
cutoff can again help the user evaluate whether matches are "noise" or real: if 
the matches are of about equal strength and scattered across the entire taxonomy,
then it is more likely to be noise. If on the other hand they are more localized 
or are growing stronger for organisms that more closely related to the organism 
we know the submitted sequence is from, then that makes it more likely the match
is real.
</p>
<p>
Having seen these top-vel distributions of hits, the user may want more detail.
The next level would be to see summaries of which parts of the submitted sequence
matched the database sequences. We could show it as in this crude constructed
example,
</p>
<table><tr><td width="50"></td><td>
@m_bars
</td></tr></table>
<p>
where the total length of each bar corresponds to the length of the submitted 
sequence and each green blip shows the position of the match. If these blips
align well we take it as a sign that this match may not be noise, whereas if 
every part of the submitted sequence matches some other sequence in a random way
then it is less interesting and perhaps "noise". Again, in real examples the 
visual impression will be good, domain specific similarites will stand out 
clearly for example. There could be one bar for every database gene sequence, 
but they could also be combined so there would be one, perhaps rather thick, 
bar for each organism or function.
</p>
<p>
Finally, if the user wants more detail, we present the sequence fragments in 
aligned form. A crude alignment is first reconstructed from the fragments and 
the "linear map" viewer is then invoked to render it or produce printable output.
</p>

<h2>Sessions</h2>
<p>
The user should be able to give each search result a title, save it for later
reuse. They would then be available for display in one or more viewers and 
for comparison. 
</p>

</div>
);

    return $xhtml;
}

sub credits
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the credits page.

    # Returns a string. 

    my ( $xhtml );

    $xhtml = qq (
<div id="info_page">

<h2>Credits</h2>

<table cellpadding="10">

<tr><td>
The development of this site and its software is sponsored by the Bioinformatics
Research Centre (<a href="http://www.birc.dk">http://www.birc.dk</a>) at Aarhus
University (<a href="http://www.au.dk">http://www.au.dk</a>).
</td></tr>
<tr><td>
We thank the free software community, not least the Free Software Foundation 
(<a href="http://www.fsf.org">http://www.fsf.org</a>) for the wide variety of high 
quality tools without which the development would not have been possible. Please
consider <a href="https://agia.fsf.org/mp/order.py?make-donation=1">making a donation</a>.
</td></tr>

</table>

</div>
);

    return $xhtml;
}

sub contact
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the contacts page.

    # Returns a string. 

    my ( $xhtml );

    my ( @table );

    &Common::Config::set_contacts();

    $xhtml = qq (
<div id="info_page">

<h2>Authors</h2>

<table cellpadding="10">
<tr><td><table cellspacing="2" cellpadding="0" border="0">
   <tr><td colspan="2">$Common::Contact::first_name $Common::Contact::last_name, $Common::Contact::title</td></tr>
   <tr><td colspan="2">$Common::Contact::department</td></tr>
   <tr><td colspan="2">$Common::Contact::institution</td></tr>
   <tr><td colspan="2">$Common::Contact::street</td></tr>
   <tr><td colspan="2">$Common::Contact::postal_code $Common::Contact::city</td></tr>
   <tr><td colspan="2">$Common::Contact::country</td></tr>
   <tr><td height="10" colspan="2"></td></tr>
   <tr><td align="right" width="30%">Electronic mail:</td><td>&nbsp;$Common::Contact::e_mail</td></tr>
   <tr><td align="right" width="30%">Telephone:</td><td>&nbsp;$Common::Contact::telephone</td></tr>
   <tr><td align="right" width="30%">Telefax:</td><td>&nbsp;$Common::Contact::telefax</td></tr>
</table></td></tr>
<tr><td>
</table>

<h2>Contact</h2>

<table cellpadding="10">
<tr><td>
You are welcome to write if you find problems, wish to contribute or collaborate
or for any reason at all. I will usually respond within a day or two.
<td></tr>
</table>


</div>
);

    return $xhtml;
}

sub expression
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the plans page, which is just a summary of the 
    # others. 

    # Returns a string. 

    my ( $xhtml );

    $xhtml = qq (
<div id="info_page">

<h2>Summary</h2>

<table cellpadding="5" id="info_summary">

<tr><td>
We propose to create a service where users can easily put their type of 
expression data into proper genomic context. They would upload data, have
it projected on one or more preferred viewers, be able to highlight 
differences and use differentially expressed gene sets as input to other 
tools. 
</td></tr>

</table>

<h2>Data Types</h2>
<p>
By expression data we mean any data that speak to gene activity or criticality,
i.e. they they may be proteomics data from mass spectrometry, 2D gels, microarrays,
essentiality data as well as ESTs and SNP data. They are tables where the 
data have been through primary processing like normalization. We will support 
simple tables and the most popular formats. 
</p>

<h2>Viewer Summary</h2>
<p>
The viewers we intend to project expression data on are part of our
developing comparative genomics platform (see Platform above), but here is
a short description. 
</p>
<p>
We believe only five to seven different types of viewers are necessary for 
convenient navigation of the most central molecular biology data, including
</p>
<p>
<ol>
<li>Organism hierarchy</li>
<li>Function hierarchy</li>
<li>Linear map, from chromosome outlines to sequence alignments</li>
<li>Networks, e.g. metabolism, protein/protein dependencies</li>
<li>Molecular structure</li>
</ol>
</p>
<p>
Each viewer should present overviews at the highest levels and look and 
work as consistently as possible. They should work as both input and output 
"devices" and be able to take as input the outputs from any of the others. 
</p>
<p>
As a small example, if one or more organisms selected on the taxonomy are
"projected" onto the function viewer, a summary is shown of the functions 
that have been annotated to the given set of organisms. A set of selected
functions could be superimposed on the organism taxonomy in the same way.
Or consider perhaps a common Blast search; instead of serving long lists
of aligned fragments, project results on the viewers where it makes sense: 
the taxonomy will show which organism groups contain matches and how strong
they are, the function tree will show which functional groups matched and a 
comparative linear map viewer can be used to show the chromosomal 
neighborhoods around the genes / gene products that match. This helps the
user from drowning in detail (which they can still get if they wish) and 
we plan to support the expression and essentiality data in this context.
</p>

<h2>Expression Data Support</h2>
<p>
Users will be able to upload tables with gene ids and expression values to
their login areas, so other users cannot see them. There the data are mapped
to the genes in the system and their titles then appear in the menus of the
different viewers together with public datasets. Buttons for "publishing" 
and "retraction" will add and delete the data from the collection that can
be viewed by visitors and other registered users. 
</p>
<p>
After chosing a title in a menu from a given viewer, the corresponding 
experiment (or experiments) will appear superimposed on that viewer. The 
function viewer will display them as summary columns with horizontal bar
graphics that indicate the proportions of up- and down-regulated genes and
their numbers within a given functional category. This "projection" will  
work on all functional categories or on saved sub-hierarchies that cover 
a particular set of interesting genes. 
</p>
<p>
To provide quick overview of the differences between select experiments 
there will be buttons which collapse the views so just the most differently
expressed genes are highlighted. These gene sets can again be used by other
viewers or exported into files that could be used with foreign tools. 
</p>
<p>
Users will be able to hide their data from view by others until they 
choose to make them visible.
</p>
<p>
Any additional public data that helps interpret expression patterns will be
included; obvious example are databases that map genes to disease, metabolic
networks and information about regulatory units.
</p>

</div>
);

    return $xhtml;
}

sub frontpage
{
    # Niels Larsen, March 2004.

    # Creates xhtml for the page that is shown by default when 
    # connecting to the site. 

    my ( $sid,     # Session id
         ) = @_;

    # Returns a string.

    my ( $xhtml, $login_button, $browse_button, $register_button, 
         $slide_icon );

    $login_button = &Common::Widgets::login_button( $sid );
    $browse_button = &Common::Info::browse_button( $sid );
    $register_button = &Common::Widgets::register_button( $sid );
    $slide_icon = &Common::Widgets::slide_forward_icon( $sid );

    $xhtml = qq (
<div id="info_page">

<h2>Summary</h2>

<table cellpadding="5">

<tr><td>
This site shows the beginning of an effort to create a genomics
platform which hopefully will make molecular biology accessible to a wider 
audience. A freely available package is developed which installs itself and lets 
the user choose which data should be integrated locally or accessed remotely; 
once installed, there is no further maintenance, updates are automatic. Through 
a small set of viewers consistent high-level overviews are generated that are 
easy to understand and navigate. Locally produced data can be uploaded and 
integrated without crossing the internet and locally developed algorithms can 
be added. The resulting open-source system, we hope, will allow scientists, 
companies, teachers and students to perform their own local analyses and lookups
as the data grow in volume and complexity.
</td></tr>
<tr><td>
An annotation and curation system is part of another (not yet available) open
source project under development. The two developments are complementary and 
loosely coordinated but will during 2004 enter symbiosis in a more formalized
way. 
</td></tr>

</table>

<p>
<h2>Enter</h2>
</p>
<p>
You may log in, create an account or just browse. There is no difference in 
functionality except preferred views and selections made will not stay until 
next login. 
</p>
<p>
<table>
<tr>
<td>$login_button</td><td>$register_button</td><td>$browse_button</td>
</tr>
</table>
</p>
<p>
<h2>Hints</h2>
</p>
<p>
Switching between viewer pages is done by clicking <strong>Organisms</strong>,
<strong>Functions</strong> in the main menu bar above; each page "remembers", 
so it is possible to switch between them without losing preferred views, 
selections etc. If you register and get a login account (free of course), the 
session will look exactly as you left it. 
</p>
<p>
<h2>Examples</h2>
</p>
<p>
We have prepared a series of pages that exemplify what the system can do. 
Each page will answer the question framed at the top of the page. The button 
below starts the show. 
</p>
<p>
<table width="100%">
<tr>
<td align="right">$slide_icon</td>
</tr>
</table>
</p>

</div>
);

    return $xhtml;
}

sub plans
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the plans page, which is just a summary of the 
    # others. 

    # Returns a string. 

    my ( $xhtml );

    $xhtml = qq (
<div id="info_page">

<h2>Plans</h2>

<table cellpadding="5">

<tr><td>
This page lists computer biology topics for which there is both good 
experimental and theoretical expertise available at Aarhus University and 
which we believe should be initial focus areas for a practically 
oriented bioinformatics effort. Each topics is described in more detail 
under the menu options above. 
</td></tr>
<tr><td>
We believe it is possible to create success stories on the topics below,
but if you have other topics please contact us (see About above). We would 
like to shape every tool in close collaboration with the groups who need 
them. We are forming partnerships with interested university laboratories,
but will be happy to work with commercial entities as well. 
</td></tr>
<tr><td>
<u>Expression data</u>. This includes proteomics data from mass 
spectrometry, 2D gels, microarrays, essentiality data as well as ESTs and
SNP data. No tools exist to project expression data onto full genomic 
context, see differences and look for their true meaning in a meaningful
way. We are in the process of supporting the "projection" part, which will
be one of the capabilities included with our comparative genomics 
platform (see Platform above.)
</td></tr>
<tr><td>
<u>16S rRNA</u>. Automatic daily update of a collection of unaligned set of 
16S rRNA sequences; make "Unclassified" categories in the taxonomy viewer 
(see Organisms above) for the environmental sample sequences; a new similarity
service for uploads of unaligned sequence; maintain a pre-computed atlas of 
group-specific probes.
</td></tr>
<tr><td>
<u>Other RNAs</u>. Create the best possible framework for finding genes for
RNA, of which there are many new species to be discovered. This work will 
benefit from genome cross mapping, which will be done as part of the 
comparative genomics platform (see Platform above.)
</td></tr>
<tr><td>
<u>Blast</u>. Instead of serving long lists of aligned fragments, create 
high-level overviews of the results: use the existing viewers to show 
match score summaries of organisms, functions or chromosomal neighborhoods.
In addition to presentation, the scoring can be significantly improved.
</td></tr>
<tr><td>
<u>Platform</u>. A framework is being created to support effective integration
and presentation of a variety molecular biology data. It will perform well with
far larger data volumes than we have today, give the user consistent overviews
and provide a research environment in which new comparative methods are inspired
and developed. It should significantly reduce the learning curve for both experts 
and non-experts and can be shaped according to local needs and ideas (as opposed
to waiting for foreign sites to create what you need.) Its development is 
coordinated with a recently initiated effort in USA (led by Dr. Ross Overbeek)
and with groups of experts within each "systems biology" discipline. Our aim is
to bring molecular biology to a much wider audience, not least the educational 
sector. 
</td></tr>

</table>

</div>
);

    return $xhtml;
}


sub platform
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the genomics platform page.

    # Returns a string. 

    my ( $xhtml );

    $xhtml = qq (
<div id="info_page">

<h2>Summary</h2>

<table cellpadding="5" id="info_summary">

<tr><td>
This page describes an ongoing effort to create a high-quality genomics platform 
which will scale well into the future. The work is an ongoing collaboration between
a small group of biologists and developers in USA (the FIG project, led by Dr. 
Ross Overbeek) and Europe with a long experience in genomics and data integration.
</tr></td>
<tr><td>
Our ambition is to bring molecular biology to a much wider audience, not least the
educational sector. We do this by providing a freely available package which 
installs locally and updates itself with all core data available on the network at 
any time. Through a small set of viewers it offers easy to understand high-level 
overviews of the integration. Locally produced data can be viewed in context without 
being sent across the internet. The package installs on commodity hardware with a 
single command and will be freely available to academia and businesses alike. If 
the platform gains popularity, we anticipate revenue can be made from derived 
activities.
</td></tr>

</table>

<h2>Rationale</h2>
<p>
The volumes of molecular data have recently begun to grow at a rate faster than
that of computer capacity, and we expect this trend to continue. We have reached
a point where if software is to have a 5-10 year life span, the data have to be 
represented on the computer in a highly scalable and efficient way, not least 
regarding user interfaces. We believe we are able to contribute a higher-quality 
platform with at least the following features,
</p>
<ul>
<li style="padding: 1px">Installs locally by a non-expert.</li>
<li style="padding: 1px">Is freely available (GNU Public License).</li>
<li style="padding: 1px">Works on commodity hardware.</li>
<li style="padding: 1px">Integrated WWW user interfaces of commercial quality.</li>
<li style="padding: 1px">Ready for much more data.</li>
<li style="padding: 1px">Includes the many extra genomes not in the primary databanks.</li>
<li style="padding: 1px">Automatic data and software updates.</li>
<li style="padding: 1px">Avoids submitting local data to public networks.</li>
</ul>
<p>
We also believe there is a great need for this. Our aim is to make general 
overviews of the molecular machinery of life much more accessible. Our measure
of success is simply that lots of people use it.
</p>
<p>
This effort is no small undertaking and it will of course develop gradually. Data
produced by strong local groups will be supported first during development and we
wish to build collaborations this way.
</p>

<h2>Viewers</h2>
<p>
Navigation of complex data requires simple and consistent views. And to support 
queries, the viewers must be able to take each others outputs as input (more below).
We believe five to seven distinct types of viewers are needed,
</p>
<p><u>Organism hierarchy</u></p>
<p>
A hierarchy representation of the NCBI taxonomy, see a prototype under the 
"Organisms" option above. It covers all views of data that somehow map to organisms,
either directly or indirectly, such as sequence similarities, statistics, sequencing
coverage, text search results, population probe results or query results. 
</p>
<p><u>Functional hierarchy</u></p>
<p>
A a hierarchy-like representation of the function, process and component 
ontologies from the Gene Ontology (GO) project. Consider it an "inventory list"
of functions and parts that can occur in any organism. Again this viewer can 
be used in a variety of ways: it is a natural place to show presence or absense
of functions and functional sub-systems for an organism, to overlay expression 
data or to visualize differences and similarities between organisms or organism
groups. It is also an obvious place to select functions or sub-systems as input
for other analyses, methods or viewers. A prototype is available under the 
"Functions" option above. 
</p>
<p><u>Linear maps</u></p>
<p>
A graphical or semi-graphical depiction of "physical" data that can be shown
as linear maps, such as chromosome icons, contigs, genomic DNA sequence 
alignments, higher level genome comparisons showing gene order, similarity views,
sequence qualities, clone information, expression data, regulons or any kind of
annotation and features that somehow map onto genome sequence. 
</p>
<p><u>Network</u></p>
<p>
Displays networks such as metabolic reactions or protein-protein dependencies.
There will probably be both a graphical display but also a hierarchy-like one 
for easier navigation and searches. Starting with one or more metabolites the
viewer can for example display neighbors in the network. We will probably reuse
existing software for this, at least initially. 
</p>
<p><u>3D structure display</u></p>
<p>
Shows molecular structures or models. We will reuse existing software.
</p>
<p>
Each viewer can display query results (as "output device") but is also able to 
save user selections which other viewers can use (as "input device") or project
them directly. Each viewer can accept projections of data of a different type 
than its native type. Consider the simple example of displaying variations in 
functionality among organisms. First we select a set of functions and save them.
Then we invoke the organism viewer and pick the just saved selection from a menu;
each function then is shown as a column, so that in effect a spreadsheet is 
created. The same kind of display can be used for experimental data, so that it 
will quickly become clear which functional groups are up- or down-regulated 
under certain conditions (see "Expression" for more about this). Notice that as 
the number of rows and columns increase patterns of difference will become much
more obvious.
</p>
<p>
Each viewer will be able to export graphics well suited for publication.
</p>

<h2>Queries</h2>
<p>
A natural way to interrogate with a computer is to frame a sentence. Experience
shows that a biologist can do this if the vocabulary includes familiar technical 
terms and is close enough to natural language. So we will implement a query canvas 
where a sentence is built by selection of menu options: when a given menu option 
is chosen, new menus or input fields are added so that as the query grows it reads
like a sentence. This makes the interface far simpler to use, because the user is 
only presented with the choices that makes sense in the query context. When the 
"sentence" has been created it can be saved for later use. 
</p>
<p>
It often makes sense to show results through more than one viewer. Consider
for example a Blast search result: some users would like to see how good the 
matches are for different organisms, others would like to see just which functions
match, yet others would like to inspect the chromosomal neighborhoods of the genes
whose products matched. As part of the query, the user invokes the viewer that 
will show the desired overview. And the results will optionally remain on the 
server so they can be reused during the next login session. For more about how
to improve common similarity search requests, see the "Blast" option.
</p>

<h2>Core Data</h2>

<p><u>DNA</u></p>
<p>
In addition to including the EMBL library we actively fetch many genomes 
from individual sites. As of October 2003 there were around 140 genomes in the 
primary databanks; 100-120 were posted at ten or so other sites under different
licenses that typically do not allow re-distribution. But they usually do allow
local analysis. Having this larger foundation for comparative analysis is an
all important advantage.
</p>
<p><u>Features</u>
<p>
Feature and gene finding is a cyclical process where the first step forms the 
basis for the next which then in turn refines the first and so on. Our first 
step is to find the obvious ORFs by running all genomes through the best available
gene finding programs. Each genome can now be regarded as a list - or sequence - 
of feature ids, typically thousands of them. Alignment software then identifies 
regions of similarity at the feature level, which can then be projected and 
refined at the DNA level. The result is a cross-map which for any given region 
in a genome gives easy access to comparable regions. 
</p>
<p><u>Synteny maps</u></p>
<p>
Knowing which orthologous regions can be compared more or less directly is 
needed for non-similarity based feature finding methods, which will again lead
to more precise annotations. For example large ORFs that look plausible in a 
single genome may be interrupted by stop codons in all the others. Approximately
aligned genomic regions could be scanned for structures that are supported by 
variations and make RNA detection much more precise. In particular the small 
RNAs should benefit, like siRNA and perhaps other medically relevant RNAs (see
"Other RNAs"). 
</p>
<p><u>Protein Clusters</u></p>
<p>
A set of functional clusters is maintained. Each cluster includes a list of 
proteins with the same function, a sequence alignment, a corresponding tree and
a consensus vector. When looking for similarities between proteins only the 
consenses are used. A list of similarities are kept for every protein against 
these consenses.
</p>
<p><u>Annotations</u></p>
<p>
A "resolution" center is being built by the FIG project (not yet publicly 
available), which helps curators assign functions and annotate features that current
computer logic cannot resolve easily. A group of expert curators is forming around 
this new tool. The annotation work of other groups is harvested via publicly 
available software and integrated. Links and crossreferences are obtained from 
existing efforts, like Uniprot at EBI and PIR and Refseq at NCBI.
</p>
<p><u>Metabolism</u></p>
<p>
A reaction network is being built which connects the functions via reactants. 
Existing data is being used amd connected to, particularly the KEGG and Brenda 
projects. 
</p>

<h2>Local Data</h2>
<p>
Locally made data will be viewable in context, starting with microarray and 
proteome data (see "Expression"). No data will be sent across the internet unless
explicitly allowed.
</p>

<h2>Methods</h2>
<p>
A given viewer can submit input to be processed by methods and their output 
displayed on other viewers. Methods can be included as a kind of "plugins" if they
have a documented command line interface, input and output formats, are written
in a standard language. The system should be an excellent testbed for development 
of new comparative methods. 
</p>

<h2>Installation</h2>
<p>
The package, which will fit on a CD, compiles and installs itself with a single 
command on Linux, Apple OS X, BSD several versions of Unix. There are two types
of installation,
</p>
<p><u>Mirror Server</u></p>
<p>
This server fetches updates from one or more central sites of all data, including
the bulky DNA. A machine with good disk capacity and network connection is needed. 
</p>
<p><u>Local Server</u></p>
<p>
Provides departmental or company wide access to all analyses and data, including 
local data. It updates itself and runs a web server with the software described 
above. But when access to externally produced low-level data is requested the 
server fetches it from a mirror server. This way the package will require only 
commodity hardware yet local data will never leave the site. 
</p>

<h2>Updates</h2>
<p>
Both data and software updates are automatic. Mirror servers update from master
sites, local servers from mirror servers. Software copies follows the data.
</p>

<h2>Revenue</h2>
<p>
We plan to launch a Blast service and perhaps other services. If the platform and
these services become popular we may not be able to handle the load unless users 
help cover the cost of running them. We will then arrange a pre-pay setup where 
background jobs are metered but everything interactive, i.e. which does not 
really incur expenses on our part, remains free.
</p>

</div>
);

    return $xhtml;
}

sub rna
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the rna finding page.

    # Returns a string. 

    my ( $xhtml );

    $xhtml = qq (
<div id="info_page">

<h2>Summary</h2>

<table cellpadding="5" id="info_summary">

<tr><td>
Finding protein genes has been, and is, the subject of intensive research.
While locating RNA genes has been pursued as well, it is a less mature area.
There are indications many RNAs are yet undiscovered. But as genomes accumulate
we can use the same methods that generated the correct secondary structures 
(and some tertiary interactions) within mature RNAs. There is great local 
interest in certain medically relevant RNAs, and given our previous experience
in this area we hope to advance the state of the art significantly. 
</td></tr>

</table>

<h2>Background</h2>
<p>
Much effort has gone into finding protein genes from genomic sequence, 
while fewer resources have gone into spotting RNA genes. Specific software has
been written to identify different RNAs: rRNA, tRNA, RNAse P, SRP RNA, tmRNA and
others, listed in (1). The strategies range from simple similarity matching of 
highly conserved RNAs to creation of loose secondary structure patterns. Each RNA
is quite different in degree of conservation and each species often requires its 
own strategy. This approach can find additional occurrences of already known RNAs,
but will probably miss many of the most divergent representatives. And it will 
not find new RNAs.
</p>
<p>
We may however find new RNAs with a different approach. Sub-sequences that lie
within "synteny blocks" - conserved areas between genomes (see the text entitled
"A Scalable Genomics Platform") - can be screened for potential RNA pairings 
that are supported by patterns of compensating base or structure changes (explained
below.) Programs using this simple idea was able to clarify the internal structure
of rRNA and other RNAs (2), later confirmed experimentally. We feel the method 
can be developed further; weaker signals should be detectable, speed improvements 
are possible and covariations could looked for not just at the sequence level. 
</p>
<p>
The outcome is of course uncertain. Given the comparative material accumulating
we feel there is a good chance of finding many new pairings that would otherwise
be hidden in "the noise". For example the spacers and introns themselves might
contain certain RNA structures that help bring the right splice sites together. 
</p>

<h2>Basic Method</h2>
<p>
In its most basic form, comparative RNA analysis is very simple: a given helix
in organism A may be composed of different base pairs that those of the 
equivalent helix in organism B. If differences are observed between many organisms
yet the pairing potential is preserved, then that is highly unlikely to happen
by chance. We take such an observation to indicate that nature needs the given
helix, to preserve a higher order structure perhaps, but that there are little 
evolutionary constraint on the participating base pairs. Or in other words, 
mutations are disadvantageous if they disrupt the helix but tolerated if they
do not. 
</p>
<p>
We need to generalize this simple method to handle compensating changes at 
higher and different levels. For example, the shortening of a given helix may be 
compensated by the growth of another. Or a given helix could disappear while 
another appears. This remains to be investigated and developed. 
</p>

<h2>Pipeline</h2>
<p>
Our success in RNA screening depends on the size of our comparative material, 
how well we can create similarity cross-maps between genomes and how fully we 
can automate its maintenance. Genomes now appear at a rate that necessitates
a very efficient, scalable computer representation. 
</p>
<p>
As part of our genomics efforts we incorporate a significant number of 
genomes, mostly bacterial, that are either in progress or posted under licenses 
that not allow redistribution (but that do allow in-house and targeted analysis.)
There are currently as many as 60% extra such genomes. 
</p>
<p>
Genome cross-maps could be maintained as follows. First run every new genome 
through the best available gene-finding program, like Glimmer and GlimmerM, as
well as other feature finding programs. Then use simple similarity matching to 
obtain a crude function annotation; each genome can now be thought of as a list
(sequence) of feature ids. We then align these "genome sequences", a 1000-fold
smaller problem that aligning the genomes at the DNA level and one which can be
done frequently on cheap hardware. To obtain a DNA level map we can match the 
approximate regions with Blast and save the coordinates. New alignment software
may have to be written.
</p>
<p>
Within aligned "blocks" we then look for structure. We will use existing tools 
and search motifs and write the necessary software for what remains. 
</p>

<h2>Micro-RNA / si-RNA</h2>
<p>
There is great local interest in these RNAs (3) and they have potential for 
medical use, thus we should focus on these from the beginning. This small RNA 
is difficult to find by motif searches, but we can hope a comprehensive genome 
cross-map will help (see above.) Before this cross-map is created we should be 
able to align the precursors and refine their structure. 
</p>

<h2>Notes and Links</h2>
<p>
<ol>
<li style="padding: 5px">Rfam is a collection of multiple sequence alignments and 
covariance models covering many common non-coding RNA families. For a list of 
these, see <a href="http://rfam.wustl.edu/browse.shtml">http://rfam.wustl.edu/browse.shtml</a>
</li>

<li style="padding: 5px">Niels Larsen, 1987, graduate thesis work. Later Bjarne Knudsen 
implemented the same idea and successfully applied his method as well. 
</li>

<li style="padding: 5px">The siRNA delivery centre: 
<a href="http://www.sirna.dk/participants.html">http://www.sirna.dk/participants.html</a>
</li>

</ol>
</p>

</div>
);

    return $xhtml;
}

sub rrna
{
    # Niels Larsen, January 2004.

    # Creates xhtml for the 16S RNA page.
    
    # Returns a string. 

    my ( $xhtml );

    $xhtml = qq (
<div id="info_page">

<h2>Summary</h2>

<table cellpadding="5" id="info_summary">

<tr><td>
There is no up-to-date properly derived 16S RNA based phylogenetic tree
covering all of life, and certain basic services in support of microbial ecology
are missing. We propose to create these services in a 100% automated way,
starting with un-aligned sequences. 
</td></tr>
<tr><td>
The project presents some algorithmic challenges and there are highly 
motivated local collaborators. But for a full-scale effort funding is 
needed. 
</td></tr>

</table>

<h2>Background</h2>
<p>
The ribosomal RNA based phylogeny has in recent years clarified our view of 
organismal evolutionary relationships and both updated and corrected the taxonomies;
as many as 30% of bacterial species have been reclassified over the last 20 years.
The Archaea, the third basic form of life, was discovered by Carl Woese at 
University of Illinois, USA, in the late seventies. In september 2003 he was 
awarded the Crafoord prize by the Royal Swedish Academy of Sciences for this work.
The following figure summarizes the situation before and after the impact of rRNA 
based phylogeny,
<p>
<table>
<tr><td height="20">&nbsp;</td></tr>
<tr><td><img src="$Common::Config::img_url/Info/Phylo_woese.jpg"></td></tr>
<tr><td height="20">&nbsp;</td></tr>
<tr><td>
<small><u>Figure legend</u>: Biology\'s knowledge of main evolutionary relationships among 
organisms around 1975 (top) and around 1990 (bottom).</small>
</td></tr>
</table>
</p>
<p>
The Ribosomal Database Project (RDP) was initated in 1990 by Carl Woese and 
Gary Olsen at University of Illinois, USA. Soon after Niels Larsen joined 
and Ross Overbeek became a close collaborator from Argonne, Chicago. Over the 
next few years trees and alignments appeared as internet services; the single 
16S tree then covered most organisms for which there were data and it was derived
by maximum-likelihood. The RDP project was relocated to Michican State University
in 1995. Since then, the data have not been up to date and since 1998 no 
universal tree has been available (1) while the online analyses have not been 
significantly improved (2) and the data have become less than freely available
(3). However care has been taken to not include poor-quality sequences and to 
curate organism nomenclature.
</p>
<p>
In Munich, Germany, Wolfgang Ludwig and coworkers have maintained rRNA alignments
and trees for almost 10 years. The quality has been good, but data have not been 
posted regularly and analyses have not been available on the web. Oliver Strunk 
initiated the development of ARB (4), a good and freely available rRNA analysis 
environment. ARB has decent support for probe generation but is not web-based and 
has a learning curve. Recently ARB has been expanded to support genomics of 
environmentally important bacteria and they are working towards automating the 
maintenance of rRNA data (5). We will coordinate with this group to avoid 
duplication. 
</p>
<p>
There are currently more than 100,000 rRNA sequences known. If we can create a
scalable solution for this many sequences, then we will also be able to maintain 
the several hundred thousand protein alignments in the future. Furthermore, the 
alignment software might be used to maintain overall synteny maps which is most 
important to genomics. 
</p>

<h2>Goals</h2>
<p>
To completely automate the creation and maintenance of a single high-quality
SSU rRNA aligment and tree that is up to date with EMBL/GenBank/DDBJ.
</p>
<p>
To provide web analyses and services that support microbial ecology and perhaps 
medicine. We will develop these with local groups initially.
</p>
<p>
To provide a self-installable package that does the above. This would allow users
to include their own data locally if they do not wish to transmit them across the
networks. 
</p>
<p>
Accomplishment of these goals probably requires three persons working for at least
one year, plus one full time person thereafter for software maintenance. However we 
will focus on unaligned sequences first, which will require much less effort. 
</p>

<h2>Tasks</h2>

<p><u>Sequence retrieval</u></p>
<p>
In the major databanks the rRNA sequences are embedded 
in sequence entries and must be spliced out. This can be done by their annotation 
but often the RNAs have not been annotated and sometimes they contain introns. So
a similarity screening has to be performed in addition (in effect a simple gene 
finding step) and rRNA ends have to be approximated after an initial alignment. 
From this initial set of "mature" RNAs then has to be subtracted the very short 
sequences and those that are exact repeats of others from the same organism. 
Possibly the lowest quality sequences have to be subtracted as well, but these 
only reveal themselves after the alignment step. The end result is a directory 
full of sequences ready to be aligned, updated daily. These sequences will be 
downloadable, saving many users time. Every group who are studying a group of 
microbes and their ecology are doing this kind of work by hand or in a 
semi-automated fashion at best. 
</p>
<p><u>Similarity service</u></p>
<p>
Be able to upload one or more rRNA sequences and quickly
receive an overview of the matches. We will use the organism taxonomy viewer that 
is part of our genomics platform under development (see Platform above). Since most
of the 16S rRNA sequences are from unknown organisms, and since we do not have a 
universal tree, this requires placing these in the taxonomic category where they
best fit. Within many taxonomic groups there will thus be "taxa" named Unclassified.
</p>
<p><u>Sequence retrieval</u></p>
<p>
Retrieve the sequences for any set of organisms selected in the browser or stored 
in the users session.
</p>
<p><u>Probe Atlas</u></p>
<p>
The fine ARB package (4) can generate probe candidates on the fly according to 
certain input criteria. Before we do the following we should evaluate these 
cababilities and find out if ARB can be programmatically directed to generate 
probe candidates. 
</p>
<p>
Should probes be generated on the fly or pre-computed? We think both: there is 
probably a limited diversity of different taxon-specific probes, but the user may
want to know if there are probes for arbitrary chosen organism sets and these can
thus not be pre-calculated. Browsing pre-calculated probes will be interactive but
dynamic generation much slower; we will focus on the pre-generated ones. 
</p>
<p>
To find probes for a given taxon the user would simply search for the taxon name 
in our organism viewer, select a column of probe buttons from a pulldown menu and 
click these to see a list of candidates. Filter criteria can be applied to these
including length, approximate melting temperature, mismatch quialification, 
target and non-target specifity percentages and maximum multiplicity.
</p>

<h2>Further Developments</h2>

<p>
These will only happen in 2004 if extra funding is raised and qualified people 
are found to do the development.
</p>

<p><u>Sequence alignment</u>.</p>
<p>
ARB can align, edit and tree sequences, but we should evaluate the quality of the 
auto-alignment it makes. From having edited these alignments it is clear that 
software could be made to replace human curators by creating an alignment the 
humans cannot improve on. The RNACAD program (6), used by the RDP project, should
be evaluated before creating new software.
</p>
<p>
If an alignment procedure needs to be created it should have the following 
features,
</p>
<p>
<ul>
<li style="padding: 5px">
Align hundreds of thousands of sequences in reasonable time, maybe one hour, 
on a standard PC with 1 Gb of physical memory, single processor and disk.
</li>
<li style="padding: 5px">
Align the sequences as well as an experienced human. This means alignment by 
secondary structure must be built in.
</li>
<li style="padding: 5px">
Annotate the regions that are aligned reliably, so that for example tree 
programs can discriminate such regions from those that would only contribute 
noise. 
</li>
<li style="padding: 5px">
Place new sequences into an existing alignment very fast, without changing the 
the existing alignment. 
</li>
<li style="padding: 5px">
Have few or no input parameters.
</li>
<li style="padding: 5px">
Be written in a standard language in a way so others can take over the 
maintenance. Perhaps as Perl or Python with speed-critical routines in C. 
</li>
</ul>
</p>
<p>
It is desirable that the program can be used for related problems. It must be
able to align proteins as well as RNA, ideally be able to use any alphabet. 
For example genomes could be regarded as sequences of feature ids, which could
be aligned or mapped together at that level. 
</p>

<p><u>Treeing</u></p>
<p>
We may be able to use existing software, orchestrated by scripts. For example, 
we still have copies of procedures from 1993-1995, which generated trees in the 
following way: create a representative set of sequences and tree those with maximum
likelihood (fastDNAml by Gary Olsen); then add the rest to the branches of this 
tree without changing its topology; then tree each branch now with full sets of 
sequences on and with a suitable outgroup chosen among the parents in the 
representative tree; finally attach the branch trees to the template tree. All 
this was necessary due to the slowness of the maximum likelihood method.
</p>
<p>
Alternatively one could use the output from the above alignment as follows. For
each saved consensus, create a regular distance matrix tree from the positions that 
are reliably aligned and save it. This way highly variable positions will be used
for trees of closely related species, but for the deeper branches they will not.
And the topology of the deepest branches will be based on the most conserved 
alignment positions, or "signatures". We have now rather quickly generated a 
collection of trees that are probably not additive, but where the topologies are
right. Now what remains is to adjust the branch lengths. A simple - and crude -
way would be to multiply all branch lengths in a given tree with the number of 
positions used in the tree that includes its consensus (the "parent" tree) and 
then divide by the number of positions used to calculate the tree itself. The 
method will of course have to be more refined than this, but it will produce 
trees with better topologies than normal distance matrix trees, because the 
variable positions used to resolve relationships near the leaves are not used 
for the deep branches, where they would just be noise. The branch lengths can
be made reasonable I believe, and the final tree will assemble quickly. There 
may be better ways than this, but given the number of organisms any method will
have to somehow divide the problem into pieces and then put them back together.
</p>


<h2>Notes and Links</h2>
<p>
<ol>
<li style="padding: 5px">
RDP 16S rRNA trees: <a href="http://rdp.cme.msu.edu/cgis/treeview.cgi?su=SSU&init=on">
http://rdp.cme.msu.edu/cgis/treeview.cgi?su=SSU&init=on</a>
</li>
<li style="padding: 5px">
RDP analyses: <a href="http://rdp.cme.msu.edu/html/analyses.html">
http://rdp.cme.msu.edu/html/analyses.html</a>
</li>
<li style="padding: 5px">
RDP license:
<a href="http://rdp.cme.msu.edu/docs/rdp_license.html">http://rdp.cme.msu.edu/docs/rdp_license.html</a>
</li>
<li style="padding: 5px">
ARB home page:
<a href="http://www.arb-home.de">http://www.arb-home.de</a>
</li>
<li style="padding: 5px">
ARB developments: 
<a href="http://www2.mikro.biologie.tu-muenchen.de/arb/projects.html">
http://www2.mikro.biologie.tu-muenchen.de/arb/projects.html</a>
</li>
<li style="padding: 5px">
RNACAD program: <a href="http://www.cse.ucsc.edu/~mpbrown/rnacad">
http://www.cse.ucsc.edu/~mpbrown/rnacad</a>
</li>

</ol>

</div>
);

    return $xhtml;
}

sub status
{
    # Niels Larsen, September 2003.

    # Returns a string. 

    my ( $xhtml, $title, $body );

    $xhtml = qq (
<table><tr><td height="500">

Describe status.

</td></tr></table>
);

    return $xhtml;
}


1;


__END__
