package Recipe::Stats;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Statistics related routines. UNFINISHED.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

use vars qw ( *AUTOLOAD );
use Tie::IxHash;
use Scalar::Util;

@EXPORT_OK = qw (
                 &head_hour
                 &head_menu
                 &head_row
                 &head_type
                 &html_body
                 &html_css 
                 &html_footer
                 &html_header
                 &htmlify_stats
                 &htmlify_stats_args
                 &text_to_html
                 &write_main
);

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Tables;
use Common::Table;
use Common::Widgets;
use Common::OS;
use Common::Names;

use Registry::Args;

use Recipe::Messages;
use Recipe::IO;

use base qw ( Common::Obj );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub head_hour
{
    # Niels Larsen, May 2013.

    # Returns the hour part of the "date" field in the statistics header. 

    my ( $stats,
         $fatal,
        ) = @_;

    # Returns a scalar value. 

    my ( $date, $hour );

    if ( $date = &Recipe::Stats::head_type( $stats, "date", $fatal ) )
    {
        if ( $date =~ /(\d+:\d+:\d+)/ ) {
            $hour = $1;
        } else {
            &error( qq (Wrong looking date -> "$date") );
        }
    }
    else {
        $hour = "";
    }

    return $hour;
}

sub head_menu
{
    # Niels Larsen, May 2013.

    # Returns the list of values for a header menu, optionally with the given 
    # title. If there are multiple matches, or none, a fatal error occurs unless
    # the third argument set to false.

    my ( $stats,    # Statistics hash
         $title,    # Menu title - OPTIONAL, default any
         $fatal,    # Fatal flag - OPTIONAL, default 1
        ) = @_;

    # Returns a scalar. 

    my ( $rows, @list, $value, $name, @vals, $items, $count );

    $fatal //= 1;

    $rows = $stats->{"headers"}->[0]->{"rows"};
    $name = $stats->{"name"};

    if ( $rows and @{ $rows } )
    {
        @list = grep { exists $_->{"type"} and $_->{"type"} eq "menu" } @{ $rows };

        if ( $title ) {
            @list = grep { $_->{"title"} =~ /$title/ } @list;
        }

        if ( scalar @list == 1 )
        {
            $items = [ map { $_->{"value"} } @{ $list[0]->{"items"} } ];
            return wantarray ? @{ $items } : $items;
        }
        elsif ( scalar @list > 1 )
        {
            $count = scalar @list;
            &error( qq ($count menus with title "$title" for "$name") );
        }
        elsif ( $fatal ) {
            &error( qq (No menu with title "$title" for "$name") );
        }
    }
    elsif ( $fatal ) {
        &error( qq (No header rows found) );
    }

    return;
}

sub head_row
{
    # Niels Larsen, May 2013.

    # Returns the value of the header row that matches a given title. If there
    # are multiple matches, or none, a fatal error occurs unless the third 
    # argument set to false.

    my ( $stats,    # Statistics hash
         $title,    # Title expression
         $fatal,    # Fatal flag - OPTIONAL, default 1
        ) = @_;

    # Returns a scalar. 

    my ( $rows, @list, $name, $items, $count );

    $fatal //= 1;

    $rows = $stats->{"headers"}->[0]->{"rows"};
    $name = $stats->{"name"};

    if ( $rows and @{ $rows } )
    {
        @list = grep { exists $_->{"title"} and $_->{"title"} =~ /$title/i } @{ $rows };

        if ( scalar @list == 1 )
        {
            if ( ref $list[0] ) {
                return $list[0]->{"value"};
            } else {
                return $list[0];
            }
        }
        elsif ( scalar @list > 1 )
        {
            $count = scalar @list;
            &error( qq ($count rows with title "$title" for "$name") );
        }
        elsif ( $fatal ) {
            &error( qq (No row with title "$title" for "$name") );
        }
    }
    elsif ( $fatal ) {
        &error( qq (No header rows found) );
    }

    return;
}

sub head_type
{
    # Niels Larsen, May 2013.

    # Returns the value of the header row with the given type. If there are 
    # multiple matches, or none, a fatal error occurs unless the third argument 
    # set to false.

    my ( $stats,    # Statistics hash
         $type,     # Field type key 
         $fatal,    # Fatal flag - OPTIONAL, default 0
        ) = @_;

    # Returns a scalar. 

    my ( $rows, @list, $name, $count );

    $fatal //= 0;

    $rows = $stats->{"headers"}->[0]->{"rows"};
    $name = $stats->{"name"};

    if ( $rows and @{ $rows } )
    {
        @list = grep { $_->{"type"} eq $type } @{ $rows };

        if ( scalar @list == 1 )
        {
            return $list[0]->{"value"};
        }
        elsif ( scalar @list > 1 )
        {
            $count = scalar @list;
            &error( qq ($count rows of type "$type" for "$name") );
        }
        elsif ( $fatal ) {
            &error( qq (No row of type "$type" for "$name") );
        }
    }
    elsif ( $fatal ) {
        &error( qq (No header rows found) );
    }

    return;
}

sub html_body
{
    # Niels Larsen, February 2012. 

    # Creates HTML output from a tagged statistics file or structure. 

    my ( $stats,   # Statistics list
        ) = @_;

    # Returns a string.

    my ( $html, $table, $stat, $date, $hdrs, $hdr, $time, $rows, $row, @row, 
         $menu, $tab, $items, $title, $value, $size, $item, $path, $type, 
         $val_css, $name, $i, $file, $ali_cols, $col_ramp, $margin, @value, $str );

    $html .= qq (<table cellpadding="0" cellspacing="20" style="margin-bottom: 3em">\n\n);
    
    foreach $stat ( @{ $stats } )
    {
        $html .= qq (<tr><td>\n);
        $html .= qq (<table cellpadding="0" cellspacing="0" style="margin-top: 0.8em">\n);

        if ( $stat->{"title"} ) { 
            $html .= qq (<tr><td><h1>$stat->{"title"}</h1></td></tr>\n);
        }

        $margin = "1.5em";

        if ( $stat->{"summary"} )
        { 
            $html .= qq (<tr><td width="95%"><div class="done_message">$stat->{"summary"}</div></td></tr>\n);
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        foreach $hdr ( @{ $stat->{"headers"} } )
        {
            if ( $hdr->{"rows"} ) {
                $html .= qq (<tr><td><table cellspacing="0" cellpadding="0" style="margin-top: $margin">\n);
            } else {
                $html .= qq (<tr><td><table cellspacing="0" cellpadding="0">\n);
            }
            
            foreach $row ( @{ $hdr->{"rows"} } )
            {
                $type = $row->{"type"};
                next if $type eq "secs";

                $title = $row->{"title"};

                $val_css = "std_cell_left";

                # >>>>>>>>>>>>>>>>>>>>>>>>>> MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                
                if ( $type eq "menu" )
                {
                    $val_css = "";
                    $value = qq (<select class="menu">);
                    
                    foreach $item ( @{ $row->{"items"} } )
                    {
                        $value .= qq (<option>&nbsp;$item->{"value"}&nbsp;</option>\n);
                    }
                    
                    $value .= qq (</select>\n);
                }

                # >>>>>>>>>>>>>>>>>>>>>>>> HTML FILES <<<<<<<<<<<<<<<<<<<<<<<<<

                elsif ( $type eq "html" )
                {
                    $path = $row->{"value"};
                    $name = &File::Basename::basename( $row->{"value"} );
                    
                    $value = qq (<a href="$path.html">$name</a>);
                }
                
                # >>>>>>>>>>>>>>>>>>>>>>> REGULAR FILES <<<<<<<<<<<<<<<<<<<<<<<
                
                elsif ( $type eq "file" )
                {
                    $path = $row->{"value"};
                    $path = "$path.zip" if -e "$path.zip";

                    $name = &File::Basename::basename( $path );

                    if ( -e $path and ( $size = -s $path ) )
                    {
                        if ( $size > 50_000 )
                        {
                            $size = &Common::Util::abbreviate_number( $size );
                            $value = qq (<a href="$path">$name</a>&nbsp;($size));
                        }
                        else {
                            $value = qq (<a href="$path">$name</a>);
                        }
                    }
                    else
                    {
                        $val_css = "std_cell";
                        $value = $path;
                    }
                }

                # >>>>>>>>>>>>>>>>>>>>>>>> DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<

                elsif ( $type eq "dir" )
                {
                    $value = qq (<a href=".">Simple list of all files</a> (primitive));
                }
                
                # >>>>>>>>>>>>>>>>>>>>>> DATE AND RUN TIME <<<<<<<<<<<<<<<<<<<<

                elsif ( $type eq "date" )
                {
                    $title = "Finished";
                    $value = $row->{"value"};
                    $val_css = "std_cell";
                }
                elsif ( $type eq "time" )
                {
                    $title = "Run time";
                    $value = $row->{"value"};
                    $val_css = "std_cell_left";
                } 

                # >>>>>>>>>>>>>>>>>>>>>>>>> OTHER ROWS <<<<<<<<<<<<<<<<<<<<<<<<

                elsif ( $type eq "hrow" )
                {
                    @value = ();
                    
                    foreach $str ( split " ", $row->{"value"} )
                    {
                        if ( &Scalar::Util::looks_like_number( $str ) ) {
                            push @value, &Common::Util::commify_number( $str );
                        } else {
                            push @value, $str;
                        }
                    }

                    $value = join " ", @value;
                    $val_css = "std_cell_left";
                }
                else {
                    &error( qq (Wrong looking type -> "$type") );
                }

                $html .= qq (   <tr>
   <td align="right" class="std_form_key">$title&nbsp;&raquo;</td>
   <td align="left" class="$val_css">$value&nbsp;</td>
   </tr>
);
            }

            $html .= qq (</table></td></tr>\n);
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> COUNTS TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        foreach $tab ( @{ $stat->{"tables"} } )
        {
            $rows = [ map { [ split "\t", $_->{"value"} ] } @{ $tab->{"rows"} } ];

            foreach $row ( @{ $rows } )
            {
                for ( $i = 0; $i <= $#{ $row }; $i++ )
                {
                    if ( $row->[$i] =~ /^html=([^:]+):(.+)$/ )
                    {
                        $row->[$i] = qq (<a href="$2">$1</a>);
                    }
                    elsif ( $row->[$i] =~ /^file=(.+)/ )
                    {
                        $path = $1;
                        $path = "$path.zip" if -e "$path.zip";

                        $name = &File::Basename::basename( $path );

                        if ( -e $path and ( $size = -s $path ) )
                        {
                            $row->[$i] = qq (<a href="$path">$name</a>);
                        }
                        else {
                            $row->[$i] = qq (<div style="padding-right: 0.5em">$name</div>);
                        }
                    }
                }
            }

            $table = &Common::Table::new( $rows );
            
            if ( $tab->{"colh"} ) {
                $table->col_headers([ split "\t", $tab->{"colh"} ]);
            }
            
            if ( $tab->{"rowh"} ) {
                $table->row_headers([ split "\t", $tab->{"rowh"} ]);
            }

            if ( $tab->{"align_columns"} ) {
                $ali_cols = eval $tab->{"align_columns"};
            } else {
                $ali_cols = [];
            }

            if ( $tab->{"color_ramp"} ) {
                $col_ramp = [ &Common::Util::color_ramp( split " ", $tab->{"color_ramp"} ) ];
            } else {
                $col_ramp = [ &Common::Util::color_ramp( "#cfcfcf", "#ffffff" ) ];
            }

            $html .= qq (<tr><td><table cellspacing="0" cellpadding="0" style="margin-top: 1.5em">\n);

            if ( $tab->{"title"} ) {
                $html .= qq (<tr><td class="title">$tab->{"title"}</td></tr>\n);
            }

            $html .= qq (   <tr><td>\n);

            $html .= &Common::Tables::render_html(
                $table,
                "show_empty_cells" => 1,
                "align_columns" => $ali_cols,
                "css_col_ramp" => $col_ramp,
                "css_col_header" => "std_col_title",
                "css_element" => "std_cell_right",
                );

            $html .= qq (   </td></tr>\n);
            $html .= qq (</table></td></tr>\n);
        }

        $html .= qq (</table>\n\n);
        $html .= qq (</td></tr>\n);
    }

    $html .= qq (</table>\n\n);

    return $html;
}

sub html_css
{
    my ( $css );

    $css = qq (
/*
   ----------------------------------------------------------------------------
   General settings
   ----------------------------------------------------------------------------
*/

body {
    margin: 0em;
    background-color: #cccccc;
    font-family: Verdana, "Bitstream Vera Sans", Sans-serif;
    font-size: 1em;
    text-align: left;
    height: 100%;
}

#content {
  background-color: #cccccc;
  font-size: 1.1em;
  padding: 1em 2em 1em 2em;
  height: 100%;
}

h1,h2,h3,h4,h5,h6 {
    text-align: left;
    color: #444444;
    font-family: "MS sans serif", "Gills Sans", "Bitstream Vera Sans", Verdana, Helvetica, sans-serif;
    font-weight: bold;
}

h1 { font-size: 1.4em; font-size: 170%; margin-top: 0px; font-variant: small-caps; }
h2 { font-size: 1.25em; font-size: 140%; margin-top: 0px; }
h3 { font-size: 1.2em; font-size: 120%; }
h4 { font-size: 1.1em; font-size: 100%; }
h5 { font-variant: small-caps; }
h6 { font-style: italic; }

h1 {
    color: #333333;
}

li {
    padding-top: 0.4em;
    padding-bottom: 0.4em;
}

p {
    font-family: "MS sans serif", "Gills Sans", "Bitstream Vera Sans", Verdana, Helvetica, sans-serif;
    margin-left: 2px;
}

a {
    text-decoration: none;
}

a:link {
    color: #000000;
    text-align: left;
}

a:visited { color: #000000 }  /* visited link */
a:hover { color: #000000 }    /* mouse over link */
a:active { color: #003366 }   /* selected link */

a:link {
    color: #0000dd;
    text-align: left;
    text-decoration: none;
/*    padding-right: 0.5em;  */
}

.title {
    font-size: 150%;
    font-weight: bold;
    font-variant: small-caps;
    padding-top: 0.7em;
    padding-bottom: 0.7em;
    color: #444444;
}

.menu {
    width: 100%;
    white-space: nowrap;
}

select {
    font-family: Verdana, "Bitstream Vera Sans", Sans-serif;
    font-size: 1em;
    text-align: left;
    height: 100%;
}

tr {
    height: 1.3em;
}

td {
    white-space: nowrap;
}    

/*
   ----------------------------------------------------------------------------
   Header and footer
   ----------------------------------------------------------------------------
*/

.hdr_bar_green, .ftr_bar_green {
    width: 100%;
    float: right;
    color: #ffffff;
    background-color: #206060;
    border-color: #308080 #004040 #004040 #308080;
    border-style: solid;
    border-width: 0.2em;
    white-space: nowrap;
}

.hdr_bar_purple, .ftr_bar_purple {
    width: 100%;
    color: #ffffff;
    background-color: #382260;
    border-color: #685590 #000033 #000033 #685590;
    border-style: solid;
    border-width: 0.2em;
    white-space: nowrap;
}

.hdr_bar_green, .hdr_bar_purple {
    height: 3em;
    font-size: 1.7em;
    font-weight: bold;
    padding-left: 0.8em;
    padding-right: 0.8em;
    padding-top: 1em;
    padding-bottom: 1em;
}

.hdr_bar_nav {
    color: #000000;
    background-color: #dddddd;
    border-color: #ffffff #999999 #999999 #ffffff;
    font-weight: normal;
    border-style: solid;
    border-width: 0.15em 0.25em 0.15em 0.25em;
    white-space: nowrap;
    height: 1.2em;
    width: 100%;
}

.ftr_bar_green, .ftr_bar_purple {
    height: 1.3em;
    width: 100%;
    margin-top: 3em;
    position: fixed;
    bottom: 0;
}

.ftr_bar_green a:link, .ftr_bar_purple a:link {
    color: white;
    text-decoration: none;
}

/*
   ----------------------------------------------------------------------------
    Message panels
   ----------------------------------------------------------------------------
*/

.warning_panel, .status_panel, .info_panel {
    border-radius: 0.7em;
    border-width: 0.2em;
    border-style: solid;
    padding-top: 2em;
    padding-bottom: 3em;
    padding-left: 2em;
    padding-right: 2em;
    width: 95%;
}

.error_panel, .error_message, .login_error_message {
    background-color: BlanchedAlmond;
    border-color: LightSalmon;
}

.warning_message {
    background-color: LemonChiffon;
    border-color: Gold;
}

.sponsor_message {
    background-color: #dddddd;
    border-color: #999999;
}

.info_panel, .info_message {
    background-color: LightGrey;
    border-color: RoyalBlue;
}

.special_message {
    padding-left: 2em;
    padding-right: 2em;
    padding-top: 1.5em;
    padding-bottom: 1.5em;
    background-color: #eeeecc;
    border-radius: 0.7em;
    border-width: 0.2em;
    border-style: solid;
    border-color: #999999;
}

.error_message, .warning_message, .info_message, .done_message, .todo_message,
.sponsor_message {
    border-radius: 0.7em;
    border-width: 0.2em;
    border-style: solid;
    padding-top: 0.8em;
    padding-bottom: 0.8em;
    padding-left: 1.6em;
    padding-right: 1.6em;
    margin-top: 0.6em;
    margin-right: 2em;
    white-space: normal;
    width: 95%;
}

.done_message {
    background-color: #e6eee6;
    border-color: SeaGreen;
}

/*
   ----------------------------------------------------------------------------
   Standard table outputs
   ----------------------------------------------------------------------------
*/

.std_col_title, .std_row_title
{
    border: 1px solid;
    padding-left: 0.5em;
    padding-right: 0.5em;
    text-align: center;
    white-space: nowrap;
}

.std_col_title
{
    color: #ffffff;
    background-color: DimGray;
    border-color: #aaaaaa #333333 #333333 #aaaaaa;
    height: 1.8em;
    min-width: 2em;
}

.std_row_title
{
    color: #ffffff;
    background-color: #888888;
    border-color: #aaaaaa #777777 #777777 #aaaaaa;
    text-align: right;
}

.std_cell, .std_cell_left, .std_cell_right
{
    color: #000000;
    background-color: #dddddd;
    border-color: #ffffff #999999 #999999 #ffffff;
    font-weight: normal;
    border-style: solid;
    border-width: 1px;
    padding-left: 0.6em;
    padding-right: 0.6em;
    white-space: nowrap;
    min-width: 1.5em;
    height: 1.3em;
}

.std_cell, .std_cell_left, .std_cell_right {
    padding-top: 0.1em;
    padding-bottom: 0.1em;
}

.std_cell_left {
    text-align: left;
}

.std_cell_right {
    text-align: right;
}

.std_form_text {
    color: #333333;
    background-color: #cccccc;
    padding-top: 5px;
    padding-bottom: 15px;
    text-align: left;
}

.std_form_key {
    color: #ffffff;
    border: 1px solid;
    border-color: #aaaaaa #333333 #333333 #aaaaaa;
    background-color: DimGrey;
    padding-top: 0.1em;
    padding-bottom: 0.1em;
    padding-left: 1.5em;
    padding-right: 0.5em;
    white-space: nowrap;
    text-align: right;
    width: 7em;
    height: 1.3em;
}

.std_form_input {
    background-color: #eeeddd;
    border-left: 1px solid #999999;
    border-right: 1px solid #ffffff;
    border-top: 1px solid #999999;
    border-bottom: 1px solid #ffffff;
    height: 100%;
    margin-left: 0px;
    padding-top: 1px;
    padding-bottom: 1px;
    padding-left: 8px;
    padding-right: 8px;
    white-space: nowrap;
}

/*
   ----------------------------------------------------------------------------
   Taxonomy table outputs
   ----------------------------------------------------------------------------
*/

.tax_col_title, .tax_row_title
{
    border: 1px solid;
    padding-left: 0.5em;
    padding-right: 0.5em;
    text-align: center;
    white-space: nowrap;
}

.tax_col_title
{
    color: #ffffff;
    background-color: #555555;
    border-color: #aaaaaa #000000 #000000 #aaaaaa;
    height: 1.8em;
}

.tax_row_title
{
    color: #ffffff;
    background-color: #888888;
    border-color: #aaaaaa #777777 #777777 #aaaaaa;
    text-align: right;
}

.tax_cell_name
{
    color: #000000;
    background-color: #dddddd;
    border-color: #ffffff #999999 #999999 #ffffff;
    font-weight: normal;
    border-style: solid;
    border-width: 1px;
    padding-left: 0.8em;
    padding-right: 0.8em;
    white-space: nowrap;
    height: 1.3em;
}

.mis_cell {
    color: #ffffff;
    background-color: #557755;
    border-color: #999999 #333333 #333333 #999999;
    font-weight: normal;
    border-style: solid;
    border-width: 1px;
    padding-left: 0.8em;
    padding-right: 0.8em;
    padding-top: 0.0em;
    padding-bottom: 0.0em;
    white-space: nowrap;
    height: 1.3em;
}
    
.seq_cell {
    color: #ffffff;
    background-color: SeaGreen;
    border-color: MediumSeaGreen DarkGreen DarkGreen MediumSeaGreen;
    font-weight: normal;
    border-style: solid;
    border-width: 1px;
    padding-left: 0.8em;
    padding-right: 0.8em;
    padding-top: 0.0em;
    padding-bottom: 0.0em;
    white-space: nowrap;
    height: 1.3em;
}
    
.tot_cell {
    color: #000000;
    # background-color: MediumSeaGreen;
    # border-color: LightGreen SeaGreen SeaGreen LightGreen;
    background-color: LightGreen;
    border-color: #ddffdd MediumSeaGreen MediumSeaGreen #ddffdd;
    font-weight: normal;
    border-style: solid;
    border-width: 1px;
    padding-left: 0.8em;
    padding-right: 0.8em;
    padding-top: 0.0em;
    padding-bottom: 0.0em;
    white-space: nowrap;
    height: 1.3em;
}
    
.tax_cell {
    color: #000000;
    background-color: #cccccc;
    border-color: #eeeeee #999999 #999999 #eeeeee;
    font-weight: normal;
    border-style: solid;
    border-width: 1px;
    padding-left: 0.8em;
    padding-right: 0.8em;
    padding-top: 0.0em;
    padding-bottom: 0.0em;
    white-space: nowrap;
    height: 1.3em;
}
    
.tax_cell_left {
    text-align: left;
}

.tax_cell_right {
    text-align: right;
}

);

    return $css;
}

sub html_header
{
    my ( $args,
        ) = @_;

    my ( $html, $lhead, $rhead, $style, $home );

    $lhead = $args->{"lhead"} // "Recipe pipeline";
    $rhead = $args->{"rhead"} // ""; # Danish Genome Institute";

    $style = &Recipe::Stats::html_css();

    $html = qq (
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
   "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>$lhead</title>

<style>
$style
</style>

</head>
<body>
);

    if ( $args->{"header"} )
    {
        $html .= qq (
<table cellpadding="0" cellspacing="0" width="100%">
<tr><td>
   <table class="hdr_bar_green">
   <tr><td style="text-align: left">$lhead</td><td style="text-align: right; font-size: 90%">$rhead</td></tr>
   </table>
</td></tr>
<tr><td>
   <table class="hdr_bar_nav">
   <tr>
       <td style="border-right-width: 0px; padding-left: 1.4em; text-align: left">
          BION Software by <a href="http://genomics.dk">genomics.dk</a></td>
       <td style="border-left-width: 0px; padding-right: 1.6em; text-align: right">
          Pure Web 1.0
       </td>
   </tr>
   </table>
</td></tr>
</table>
);
    }

    return $html;
}

sub htmlify_stats
{
    # Niels Larsen, April 2013.
    
    # Converts statistics text files to html, one html file per input file. 
    # Input files can be given as a list of paths or as a string of file 
    # expressions in shell syntax. Links within the files can be set 
    # 

    my ( $fexp,       # File expression(s), shell syntax
         $args,       # Arguments hash - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $defs, $file, $ofh, $outstr, $ifile, $ofile, $iname, $oname, 
         @ifiles, @ofiles, $i, $clobber, $conf, $stats, $css, $curdir,
         $outdir );
    
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( ref $fexp ) {
        @ifiles = @{ $fexp };
    } else {
        @ifiles = &Recipe::IO::list_files( $fexp, 0 );
    }

    $defs = {
        "files" => [],
        "level" => 0,
        "header" => 1,
        "footer" => 1,
        "lhead" => undef,
        "rhead" => undef,
        "silent" => 0,
        "clobber" => 0,
    };

    # Create object with defaults merged in,

    $args = &Registry::Args::create({ %{ $args // {} }, "files" => \@ifiles }, $defs );
    $conf = &Recipe::Stats::htmlify_stats_args( $args );

    $Common::Messages::silent = $conf->silent;
    
    $clobber = $conf->clobber;

    &echo_bold( "\nCreating HTML:\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SUMMARIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    @ifiles = @{ $conf->ifiles };
    @ofiles = @{ $conf->ofiles };

    $curdir = &Cwd::getcwd;

    for ( $i = 0; $i <= $#ifiles; $i += 1 )
    {
        # Output file is always the input file + .html,

        $ifile = $ifiles[$i];
        $ofile = $ofiles[$i];

        &echo( "   Creating $ofile ... " );

        $stats = &Recipe::IO::read_stats( $ifile );

        # Change directory to where the output file will be written,

        &Common::File::change_dir( $curdir ); 

        $outdir = &File::Basename::dirname( $ofile );
        &Common::File::change_dir( $outdir );

        # Header bar, body and footer bar,

        $outstr = &Recipe::Stats::html_header(
            {
                "header" => $conf->header,
                "lhead" => $conf->lhead // $stats->[0]->{"title"} // "Recipe run",
                "rhead" => $conf->rhead // $stats->[0]->{"site"} // "",
            });

        $outstr .= &Recipe::Stats::html_body( $stats );

        # Change directory back,

        &Common::File::change_dir( $curdir );

        &Common::File::delete_file_if_exists( $ofile );

        $ofh = &Common::File::get_write_handle( $ofile );
        $ofh->print( $outstr );

        &Common::File::close_handle( $ofh );

        &echo_green( "done\n" );
    }

    &echo_bold( "Finished\n\n" );

    return;
}

sub htmlify_stats_args
{
    # Niels Larsen, September 2010. 

    # Checks input arguments and returns a configuration object that is 
    # convenient for the routines. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns object. 

    my ( @files, $conf, @msgs );

    @msgs = ();

    # The full file paths of the input files must be unique and exist,

    if ( @{ $args->files } )
    {
        # @files = &Common::File::full_file_paths( $args->files, \@msgs );
        
        @files = &Common::Util::uniq_check( $args->files, \@msgs );

        $conf->{"ifiles"} = &Common::File::check_files( \@files, "efr", \@msgs );
    }
    else {
        push @msgs, ["ERROR", "No input files given" ];
    }

    &append_or_exit( \@msgs, $msgs );

    $conf->{"ofiles"} = [ map $_ .".html", @{ $conf->{"ifiles"} } ];
    
    if ( not $args->clobber ) {
        &Common::File::check_files( $conf->{"ofiles"}, "!e", \@msgs );
    }

    &append_or_exit( \@msgs, $msgs );

    $conf->{"header"} = $args->header;
    $conf->{"level"} = $args->level;
    $conf->{"header"} = $args->header;
    $conf->{"footer"} = $args->footer;
    $conf->{"lhead"} = $args->lhead;
    $conf->{"rhead"} = $args->rhead;
    $conf->{"silent"} = $args->silent;
    $conf->{"clobber"} = $args->clobber;

    return bless $conf;
}    

sub text_to_html
{
    # Niels Larsen, March 2012.

    # Adds HTML header and footer and pre-tags to one or more text files.

    my ( $fexp,
         $args,
        ) = @_;

    my ( @files, $file, $ofile, $html, $text, $strip );

    @files = &Recipe::IO::list_files( $fexp, 0 );

    foreach $file ( @files )
    {
        $html = &Recipe::Stats::html_header(
            {
                "lhead" => $args->{"lhead"},
                "rhead" => $args->{"rhead"},
                "header" => 1,
            });

        $text = ${ &Common::File::read_file( $file ) };

        $text =~ s/\n/\n   /g;
        $text = "   $text";

        if ( $args->{"pre"} ) 
        {
            $text =~ s/</&lt;/g;
            $text =~ s/>/&gt;/g;

            $html .= "<pre>\n$text\n</pre>\n";
        }
        else {
            $html .= $text;
        }

        $ofile = $file .".html";
        &Common::File::delete_file_if_exists( $ofile );

        &Common::File::write_file( $ofile, $html );
    }

    return;
}

sub write_main
{
    # Niels Larsen, June 2012. 

    # Creates the main statistics file with counts that users look at first 
    # and that links to more detail. The layout of the files and links follows
    # the recipe. The paths are all relative paths from the results directory.
    # The routine creates and returns a text with tags that are understood 
    # by Recipe::Stats::html_body. 

    my ( $rcp,    # Recipe hash
         $args,   # Arguments hash
         $msgs,   # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns a string.
    
    my ( $infdir, $title, $author, $outdir, $outpre, $step, $run, $file,
         $main_text, $text, @files, @msgs, $name, $secs, $stats, $stat,
         $about, $intro, $stat_expr, $step_dir, $out_files, $out_dir, 
         $summary, $rows, $hour, $status );
    
    $outdir = $args->{"outdir"};
    $outpre = $args->{"outpre"};
    $infdir = "BION.about";

    &Recipe::IO::create_dir_if_not_exists( "$outdir/$infdir" );

    # >>>>>>>>>>>>>>>>>>>>>>>>> HEADER FILE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text = qq (
Below is a very simple read-only list of all result files. Each recipe step 
have their own directory where only its own output files are. The list will 
be improved and have links.
);

    $text .= &Common::File::list_files_tree( $outdir, "" );
    $text .= "\n\n";

    &Common::File::write_file( "$outdir/$outpre.files", $text, 1 );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> HEADER RECIPE FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text = qq (
Below is a simple text copy of the recipe that was run. There will be a
web-control interface eventually, where recipes can be loaded, changed
and re-launched. Doing this has not yet been highest priority, but if 
someone thinks that is most important, and wants to fund it, we can 
make a very good one.

);

    $text .= ${ &Common::File::read_file( $rcp->{"file"} ) };
    &Common::File::write_file( "$outdir/$outpre.recipe", $text, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>> HEADER INFO FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &Common::File::copy_file( "$Common::Config::doc_dir/About.txt", "$outdir/$infdir/BION.about", 1 );
    &Common::File::copy_file( "$Common::Config::doc_dir/BION_meta.pdf", "$outdir/$infdir/BION_meta.pdf", 1 );
    &Common::File::copy_file( "$Common::Config::doc_dir/DGI_services.pdf", "$outdir/$infdir/DGI_services.pdf", 1 );
    &Common::File::copy_file( "$Common::Config::doc_dir/TODO.list", "$outdir/$infdir/BION.todo", 1 );
    &Common::File::copy_file( "$Common::Config::doc_dir/NL_CV_brief.pdf", "$outdir/$infdir/NL_CV_brief.pdf", 1 );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MAIN HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $title = $rcp->{"title"} // "Analysis pipeline template";
    $author = $rcp->{"author"} // "Danish Genome Institute";

    $about = qq (These pages are self-contained and can be viewed by
any browser on any system, posted on internet or e-mailed to colleagues.
Results include detailed statistics and data file access. Results can 
be reproduced by re-running a single recipe with all parameters within.
In the interest of full transparency we made the whole BION-meta package 
non-proprietary and open-source. There will be good online support.);
    $about =~ s/\n/ /g;

    $intro = qq (Steps were run in the order they appear in the recipe 
above. Results are listed in the same order below and are accessible via
each link. To get back to this page, use the browser back-button.);
    $intro =~ s/\n/ /g;
    
    $main_text = qq (
<stats>

    title = About
    summary = $about

    <header>
       hrow = Author\t$author
       html = Recipe\t$outpre.recipe
       html = Result files\t$outpre.files
       html = About BION\t$infdir/BION.about
       html = For sponsors\t$infdir/BION.todo
       hrow = Run time\t$args->{'time'}
       hrow = Finished\t$args->{'date'}
    </header>

</stats>

<stats>

    title = Results
    summary = $intro

    <table>
       colh = Recipe step title&nbsp;\tResults\tSeconds\tFinished
       align_columns = [[ 0, "right" ], [ -1, "left" ]]
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> STEP SECTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $step ( @{ $rcp->{"steps"} } )
    {
        $run = $step->{"run"};

        $name = $step->{"name"};
        $title = $step->{"title"};
        $out_dir = $run->out_dir;

        $summary = $step->{"summary"};
        $summary .= qq ( Proper method documentation will be written and linked to here.);

        $stat_expr = "$out_dir/*.stats";

        next if not $run;
        next if not -d $out_dir;
        
        # Warning if no outputs,

        if ( not @files = &Recipe::IO::list_files( $run->out_files, 0 ) and 
             not @files = &Recipe::IO::list_files( $run->out_files .".*", 0 ) )
        {
            $out_files = $run->out_files;
            push @msgs, ["Warning", qq (No outputs for "$out_files") ];
        }

        @files = &Recipe::IO::list_files( $stat_expr, 0 );
        
        if ( @files )
        {
            foreach $file ( @files )
            {
                $stats = &Recipe::IO::read_stats( $file );

                if ( $title and scalar @{ $stats } == 1 )
                {
                    $stats->[0]->{"title"} = $title;
                }
                
                # Set summary at all levels,
                
                foreach $stat ( @{ $stats } ) 
                {
                    $stat->{"summary"} = $summary;
                }

                &Recipe::IO::write_stats( $file, $stats );
                
                if ( $file =~ /step\.stats$/ ) 
                {
                    $step_dir = &File::Basename::basename( $out_dir );

                    $status = &Recipe::IO::read_status( "$out_dir/STATUS" );

                    $secs = $status->{"secs"} // "";
                    $hour = $status->{"hour"} // "";

                    $main_text .= qq (       trow = $title&nbsp;\thtml=Results:$step_dir/step.stats.html\t$secs\t$hour\n);
                }
            } 
        }
        else
        {
            if ( -s "$out_dir/STATUS" )
            {
                $status = &Recipe::IO::read_status( "$out_dir/STATUS" );
                
                $secs = $status->{"secs"} // "";
                $hour = $status->{"hour"} // "";
                
                $main_text .= qq (       trow = $title&nbsp;\t\t$secs\t$hour\n);
            }

            push @msgs, ["Warning", qq (No statistics for "$stat_expr") ];
        }
    }

    &append_or_exit( \@msgs, $msgs, "exit" => 0 );

    $main_text .= qq (    </table>\n\n</stats>\n\n);

    if ( defined wantarray ) {
        return $main_text;
    } else {
        &Common::File::write_file( "$outdir/$outpre.stats", $main_text, 1 );
    }

    return;
}

1;

__END__

        # # &Common::Config::get_contacts()->{"e_mail"} );

        # if ( not -r "$dir/CSS/page.css" )
        # {
        #     &Common::File::create_dir_if_not_exists("$dir/CSS");
        #     $css = &Recipe::Stats::html_css();
        # 
        #     &Common::File::write_file( "$dir/CSS/page.css", $css );
        #  }

# sub html_footer
# {
#     my ( $args,
#         ) = @_;

#     my ( $html );

#     $html = "";

#     if ( $args->{"footer"} )
#     {
#         $html .= qq (
# <table class="ftr_bar_green">
#    <tr><td style="text-align: right; padding-right: 1em">&nbsp;Done with pure Web 1.0&nbsp;</td></tr>
# </table>
# );
#     };

#     $html .= qq (
# </body>
# </html>
# );

#     return $html;
# }

