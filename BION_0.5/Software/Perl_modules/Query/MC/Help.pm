package Query::MC::Help;     #  -*- perl -*-

# Help texts for clipboard pages. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &dispatch
                 &section_mirconnect
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Widgets;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub dispatch
{
    # Niels Larsen, July 2009.

    # Writes general help for the clipboard related pages. 

    my ( $request,
         ) = @_;

    # Returns a string. 

    my ( $xhtml, $title, $arrow, $body, $routine );

    if ( not defined $request ) {
        &error( qq (No request given) );
    }

    if ( $request =~ /^help_([a-z]+)$/ )
    {
        $routine = __PACKAGE__ ."::section_$1";
    
        no strict "refs";
        ( $title, $body ) = &{ $routine };
    }
    else {
        &error( qq (Wrong looking request -> "$request") );
    }

    $xhtml = &Common::Widgets::help_page( $body, $title );

    return $xhtml;
}

sub section_mirconnect
{
    my ( $title, $arrow, $body, $menu, $opt );

    $title = "About";
    $arrow = &Common::Widgets::arrow_right;
    
    $body = qq (
<p>
This searchable web interface is based on the following publications which describe the details of
the data and their generation:
</p>
<p>
Hua, Y.J., Duan, S., Murmann, A.E., Larsen, N., Kjems, J., Lund, A.H. and Peter, M.E. (2011) 
miRConnect: identifying effector genes of miRNAs and miRNA families. PLoS One. 2011, 6:e26521.
</p>
<p>
Hua, Y.J., Larsen, N., Kalyana-Sundaram, S., Kjems, J., Chinnaiyan, A.M. and Peter, M.E. (2012) 
Identification of antagonistic, oncogenic miRNA families in three human cancers. submitted.
</p>
<p>
miRConnect-Q is based on a set of 208 miRNA data sets quantified by real time PCR (the "Q" data 
set) (see Gaur et al., 2007, Cancer Res 67: 2456). miRConnect-L is based on a set of 571 miRNA 
data sets quantified by using LNA oligo arrays (the "L" data set) (see Sokilde et al., 2011, Mol 
Cancer Ther 10: 375). Both miRConnect-Q and L allow comparison of miRNA expressions with those 
of more than 18,000 mRNAs expressed in the NCI60 cell lines and available at 
<a href="http://dtp.nci.nih.gov/mtargets/download.html">
http://dtp.nci.nih.gov/mtargets/download.html</a>.
</p>
<p>
For the NCI60 data there are two types of analyses one can choose from: sPCC and dPCC. sPCC is 
a novel way of generating correlation data. It is a form of a summed (s)PCC that involves 30 
reiterating comparisons using growing numbers of cell lines (beginning with 30 cell lines) ranked 
from the highest to lowest miRNA expression and resembles an in silico titration. In contrast, 
the dPCC or direct PCC represents the last of the 30 iterations (the comparison of all 59 
cell lines).
</p>
<p>
miRConnect-OvCa (ovarian cancer), miRConnect-GBM (gliobastoma multiforme) and miRConnect-KIRC
(kidney renal clear cell carcinoma) are based on miRNA and mRNA data sets generated as part of
The Cancer Genome Atlas (TCGA) available at http://cancergenome.nih.gov.
</p>
<p>
<h4>Examples</h4>
<p>
Here are a few examples of how to use miRConnect and what kind of data can be obtained:
</p>
<p>
<u>Example 1</u>: Choose either miRConnect-Q or -L. Type CDH1 (for the epithelial marker 
E-cadherin) into the field "mRNA Gene IDs" then hit "Show filtered table". sPCCs of miRNAs will 
be displayed that are positively (default setting) correlated with the expression of CDH1. On 
top of the list are mostly miR-200 family members that both individually and as families are 
consistent with their activity in the maintenance of the epithelial state. In addition three 
new EMT regulators miR-203, miR-7 and miR-375 we describe in our paper are also close to the 
top of the list.
</p>
<p>
<u>Example 2</u>: Select miRConnect-L. From the miRNA family pull down menu select the 
miR-302abcde/372.. etc. family (which is expressed in embryonic stem cells and can be used to 
generate induced pluripotent stem (iPS) cells) and hit "Show filtered table". The most highly
correlating gene is LIN28 which is one of 4 genes that can be used to reprogram somatic 
fibroblasts to become iPS cells.
</p>
<p>
<u>Example 3</u>: Choose miRConnect-Q and then select the let-7 family and the Correlation 
Type "Negative values" and type "apoptosis" in the "Annotation Words" box and hit "Show 
filtered table". All apoptosis regulators that are negatively correlating with the expression 
of the entire let-7 activity will be shown plus which ones of these are predicted TargetScan 
targets.
</p>
<p>
<h4>Table Filters</h4>
</p>
<p>
<u>miRNA Gene IDs</u>. Filters the table output by the miRNAs given. This is useful for trying 
combinations of miRNAs other than those grouped in our pre-made functional families. Enter or 
copy/paste a list of miRNA names as they are given in the selection menus, separated by blanks,
commas, semicolons or newlines.
</p>
<p>
<u>mRNA Gene IDs</u>. Filters the table output by the mRNA gene ids given. If not miRNA is 
given, then this can be used to show which miRNAs correlate the most with a certain set of 
genes. Enter or copy/paste a list of miRNA names as they are given in the selection menus, 
separated by blanks, commas, semicolons or newlines. The list pasted can be no more than 
1000 characters long, and the gene names must match those used by the Human Genome 
Organisation.
</p>
<p>
<u>Annotation Filter</u>. Filters the output by words that match gene annotations. One or 
many plain words may be entered, and not all words have to match. But matching behavior can 
be modified by special characters, the most useful of which are,
<ul>
<li>A leading plus (e.g. +membrane) means that word must always match.</li>
<li>A leading minus (e.g. -membrane) means that word may never match.</li>
<li>A trailing asterisk (e.g. +lipo*) will match lipoma, lipolysis, etc.</li>
<li>Double quotes (e.g. "lipoma HMGIC") causes matching of that literal string.</li>
</ul>
</p>
<p>
There are more rules and special characters described on this MySQL database page: 
<a style="color:blue" href="http://dev.mysql.com/doc/refman/5.1/en/fulltext-boolean.html">
Boolean Fulltext Searches</a>.
</p>
<p>
<h4>Credits</h4>
<p>
This web-presentation was written by Niels Larsen at <a style="color:blue" href="http://genomics.dk">Danish 
Genome Institute</a>, Aarhus, Denmark. Its development was partly supported by the 
<a style="color:blue" href="http://www.rnai.dk">Kjems laboratory</a>
at Department of Molecular Biology, Aarhus University, Denmark. The gene 
annotations were downloaded from the 
<a style="color:blue" href="http://www.hugo-international.org">Human Genome Organisation</a>.
</p>
<p>
    &nbsp;
</p>
);

    return ( $title, $body );
}

1;

__END__
