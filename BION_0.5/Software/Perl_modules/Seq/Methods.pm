package Seq::Methods;     #  -*- perl -*-

# Descriptions for sequence related methods. The text is in multimarkdown
# format (mmd), a superset of markdown format. HTML and plain text is made
# from mmd programmatically. The markdown formats:
#
# http://github.com/fletcher/MultiMarkdown/wiki/MultiMarkdown-Syntax-Guide
# http://daringfireball.net/projects/markdown/syntax

use strict;
use warnings FATAL => qw ( all );

use Tie::IxHash;
use Data::Dumper;
use Text::MultiMarkdown;
use HTML::TreeBuilder;
use HTML::FormatText;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &get
                 &get_html
                 &get_text
);

use Common::Config;
use Common::Messages;

use Common::Tables;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our ( %Doc_map );

tie %Doc_map, "Tie::IxHash";

$Doc_map{"seq_chimera"} = qq (

OBSOLETE - rewrite when method has stabilized

The debug histogram output example below shows a low-scoring likely 
chimera. The l's mark cumulated dissimilarities from the start of the
sequences, and R's from the end and backwards. The length of the l+R 
horizontal bars becomes dissimilarity sums. In normal sequences each
should increase more or less continually throughout the sequence, give 
or take conserved areas. But in chimeras the cumulative dissimilarities
will be relatively low up to the breakpoint, and then increase. That 
creates "valleys" as the one below.

Fragments can have high or low similarity with known sequences, so 
we must use ratios instead of absolute sums. Below, at valley begin 
there are 17 mismatching oligos (17 R's) and at the end there are 2;
subtract those 2 and 15 is left. Then we do the same subtraction for
the R's at the bottom and get 2 minus 2 = 0, which is changed to 1 
so it can be used as a ratio. Then we get the R-gain by dividing 15 by 
1 which gives 15. Doing the same for the l-fragment gives an l-gain 
of 7.5. Then l-gain and R-gain are multiplied, yielding 112.5. To 
make the score insensitive to step length we multiply by step length
4, giving 450. That's kind of a high number, so why not divide by 10,
and the final score becomes 45. 
 
Using this scoring, a default value of 25 often strikes a good balance
between false positives and negatives. Use 20 to get many  more, and 
30 to get only the worst. The scores can be up to 1000 or more for 
the most easily detectable chimeras. 

The reference dataset sequences must cover the whole amplicon or 
false positives may appear. The reference dataset size is less 
critical, though the broadest phylogenetic coverage improves the 
result. But there is no point in having sequences that are identical
within the amplicon or are more similar than the level chimeras are
detectable at. 

        GDPEQA103FR6HT
        --------------
        
         Word length: 8
         Step length: 4
        
         Break point: 70
             Left ID: S000558527
            Right ID: S003222509
           Left skew: 7.5
          Right skew: 15
               Score: 44
        
          Pos  Minimum mismatch at hypothetical join
        -----  -------------------------------------
        
            0  RRRRRRRRRRRRRRRRR  <-- valley begin
            4  RRRRRRRRRRRRRRRR
            8  RRRRRRRRRRRRRRR
           12  RRRRRRRRRRRRRR
           16  RRRRRRRRRRRRR
           20  RRRRRRRRRRRR
           24  RRRRRRRRRRR
           28  RRRRRRRRRR
           32  RRRRRRRRR
           36  RRRRRRRR
           40  lRRRRRRR
           44  llRRRRRR
           48  llRRRRR
           52  llRRRR
           56  llRRR
           60  llRR
           64  llRR
           68  llRR  <-- join pos
           72  llRR
           76  llRR
           80  lllRR
           84  llllRR
           88  llllRR
           92  llllRR
           96  llllRR
          100  llllRR
          104  lllllRR
          108  llllllRR
          112  llllllRR
          116  lllllllRR
          120  llllllllRR
          124  llllllllRR
          128  lllllllllRR
          132  llllllllllRR
          136  lllllllllllRR
          140  lllllllllllRR
          144  lllllllllllRR
          148  lllllllllllRR
          152  lllllllllllRR
          156  lllllllllllRR
          160  lllllllllllRR
          164  lllllllllllRR
          168  llllllllllllRR
          172  lllllllllllllRR
          176  lllllllllllllRR
          180  lllllllllllllRR
          184  llllllllllllllRR
          188  lllllllllllllllRR  <-- valley end
          192  lllllllllllllllRR
          196  lllllllllllllllRR
          200  lllllllllllllllRR
          204  lllllllllllllllRR
);

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get
{
    # Niels Larsen, May 2013.

    # Returns a description of a method with the given name. If the method 
    # is not found, a fatal error message is created or if the fatal flag 
    # is unset, undef is returned. 

    my ( $name,        # Method name
         $fatal,       # Fatal flag - OPTIONAL, default 1
        ) = @_;

    # Returns a hash, nothing or exits.

    my ( $msg );

    if ( $name )
    {
        if ( exists $Doc_map{ $name } )
        {
            return $Doc_map{ $name };
        }
        else
        {
            $msg->{"oops"} = qq (Un-recognized method name "$name");

            $msg->{"help"} = qq (Perhaps this is a documentation mistake, or the description\n);
            $msg->{"help"} .= qq (has not been written yet.\n);
            
            &Recipe::Messages::oops( $msg );
        }
    }
    else {
        &error( qq (No method name is given) );
    }

    return wantarray ? %Doc_map : \%Doc_map;
}

sub get_html
{
    my ( $name,
         $fatal,
        ) = @_;

    my ( $text, $html );

    $text = &Seq::Methods::get( $name, $fatal );

    $html = &Text::MultiMarkdown::markdown( $text );

    return $html;
}

sub get_text
{
    my ( $name,
         $fatal,
        ) = @_;

    my ( $text, $html );

    $text = &Seq::Methods::get( $name, $fatal );

    $html = &Text::MultiMarkdown::markdown( $text );

    return $html;
}

1;

__END__
