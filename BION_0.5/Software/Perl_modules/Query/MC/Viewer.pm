package Query::MC::Viewer;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use English;

@EXPORT_OK = qw (
                 &download_data
                 &query_page
                 &settings_text
                 &table_page
                 &table_titles
                 );

use Common::Config;
use Common::Messages;

use Common::Widgets;
use Common::Table;

use Registry::Get;

use Query::MC::Widgets;
use Query::MC::Menus;

use Query::Widgets;

use Expr::DB;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub download_data
{
    # Niels Larsen, July 2009.

    # Sends the given table to the client in tsv format. A header
    # line is included.

    my ( $state,       # State hash
         ) = @_;

    # Returns nothing.

    my ( %params, $titles, $dbh, $nl, $table, $cgi, $form, $row );

    $form = &Common::States::make_hash( $state->{"download_keys"},
                                        $state->{"download_values"} );

    %params = map { $_->[0], $_->[1] } @{ $state->{"params"} };
    
    # Get table data,

    $titles = &Query::MC::Viewer::table_titles( $state->{"dataset"}, \%params );
    $params{"fields"} = [ map { $_->{"name"} } @{ $titles } ];

    if ( $form->{"download_data"} eq "all_table" ) {
        undef $params{"maxtablen"};
    }

    $dbh = &Common::DB::connect( $state->{"dataset"} );

    $table = &Expr::DB::mc_query( $dbh, \%params );
    
    &Common::DB::disconnect( $dbh );

    # Print to stdout,

    require Common::Users;

    $nl = &Common::Users::get_client_newline();
    
    $cgi = new CGI;
    
    print $cgi->header( -type => "text/csv",
                        -attachment => $form->{"download_file"},
                        -expires => "+10y" );
    
    print qq (");
    print join qq (","), map { $_->{"value"} } @{ $titles };
    print qq ("$nl);
    
    foreach $row ( @{ $table->values } )
    {
        print qq (");
        print join qq (","), @{ $row };
        print qq ("$nl);
    }
    
    return $state;
}

sub query_page
{
    # Niels Larsen, June 2009.

    # Creates a query interface page for MiRConnect expression correlation data.

    my ( $sid,         # Session id
         $state,       # Arguments hash
         $proj,        # Project object
         $msgs,        # Message list - OPTIONAL
         ) = @_;

    # Returns XHTML.

    my ( $page_title, $xhtml, @l_widgets, @r_widgets, $menu, $spacer, $opt, 
         $query_menu, $select_menu, $mirna_menu, $mrna_menu, $but_desc, $keyname,
         $valname, $filter_menu );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORM DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $query_menu = &Query::MC::Menus::query_menu( $state->{"dataset"}, $state->{"params"} );

    $select_menu = Registry::Get->new(
        "title" => "Table selections",
        "description" => qq (The choices below selects from the underlying correlation table.
Mouse-over tooltips on the dark titles explain the choices. See also the help page.),
        "options" => [ $query_menu->match_options_expr( '$_->name !~ /_(names|filter)$/' ) ],
        );
    
    $mirna_menu = Registry::Get->new(
        "title" => "MicroRNA gene name filter",
        "description" => qq (Here, only the coding genes will be shown that all entered miRNA 
genes correlate with. The selection criteria above remain in effect, but can be changed or set
to blank. Use the same miRNA names as in the menu of individual miRNAs above.),
        "options" => [ $query_menu->match_options_expr( '$_->name =~ /mirna_names/' ) ],
        );

    $mrna_menu = Registry::Get->new(
        "title" => "Coding gene name and annotation filters",
        "description" => qq (Entering mRNA gene names as defined by 
<a style="color:blue" href="http://www.hugo-international.org">HUGO</a> also 
reduces the output table. If no miRNAs have been selected above, entering annotation 
words in the second box will list the miRNAs that correlate most positively or negatively. 
),
        "options" => [ $query_menu->match_options_expr( '$_->name =~ /(genid_names|annot_filter)/' ) ],
        );

    $menu = Registry::Get->new();
    $menu->options( [ $select_menu, $mirna_menu, $mrna_menu ] );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE XHTML <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $spacer = &Common::Widgets::spacer( 10 );

    # Title box in its own row,

    push @l_widgets, &Common::Widgets::title_box( "Cancer miRNA correlations", "title_box" );
    push @r_widgets, &Query::MC::Widgets::help_icon( $sid, "help_mirconnect" );

    $xhtml = $spacer; 

    $xhtml .= &Common::Widgets::title_area( \@l_widgets, \@r_widgets );

    # Messages if any,

    if ( $msgs and @{ $msgs } ) {
        $xhtml .= &Query::Widgets::message_box( $msgs );
    }

    $but_desc = qq (
Submits the form and replaces the page with a table. To get back to this
page, click Query in the menu bar.
);

    $xhtml .= &Common::Widgets::form_page( $menu, {

            "form_name" => "query_page",
            "param_key" => "query_keys",
            "param_values" => "query_values",
            
            "viewer" => "submit_viewer",
            "uri_path" => $proj->projpath,
            
            "buttons" => [{
                "type" => "submit",
                "request" => "request",
                "value" => "Show filtered table",
                "style" => "grey_button",
                "description" => $but_desc,
                          }],
    });

    $xhtml .= &Common::Widgets::spacer( 25 );

    return $xhtml;
}

sub settings_text
{
    # Niels Larsen, July 2009.

    # Creates a text string that explains the settings used during query of 
    # MiRConnect data.

    my ( $menu,
         $params,
        ) = @_;

    # Returns a string.

    my ( $text, $mtext, $ttext, @desc, @names, $names, $count, $desc, $mirna );

    if ( $mirna = $params->{"mirna_single"} or $mirna = $params->{"mirna_family"} )
    {
        push @desc, qq (selected miRNA <span class="info_text">$mirna</span>);
    }
    elsif ( $params->{"mirna_names"} )
    {
        @names = &Expr::DB::split_names( $params->{"mirna_names"} );
        $text = join " and ", map { qq (<span class="info_text">$_</span>) } @names;
        push @desc, qq (entered miRNAs $text);
    }

    #&dump( $menu );

    $mtext = $menu->match_option( "name" => "method" )->choices->match_option( "name" => $params->{"method"} )->title;
    $ttext = $menu->match_option( "name" => "target" )->choices->match_option( "name" => $params->{"target"} )->title;
    
    push @desc, ( 
        qq (correlation <span class="info_text">$params->{'correlation'}</span>),
        qq (method <span class="info_text">$mtext</span>),
        qq (target type <span class="info_text">$ttext</span>),
    );

    if ( $names = $params->{"genid_names"} )
    {
        # $count = scalar ( @{ &Expr::DB::split_names( $names ) } );
        push @desc, qq (<span class="info_text">$names</span> used as gene id filter);
    }

    if ( $names = $params->{"annot_filter"} )
    {
        @names = split " ", $names;
        $text = join " and ", map { qq (<span class="info_text">$_</span>) } @names;
        push @desc, qq (annotation search terms $text);
    }

    $desc = join ", ", @desc;
    $desc = " Settings were: $desc";

    return $desc;
}

sub table_page
{
    # Niels Larsen, July 2009.

    # Does a query of MiRConnect data and generates a table. Returns XHTML code.

    my ( $sid,
         $state,
         $msgs,
        ) = @_;
    
    # Returns a string.

    my ( $dataset, $title, $desc, $dbh, $table, $titles, $xhtml, @l_widgets, 
         %params, $row, $count, $mirna, $dat_hdr, $dat_tip, $i, @msgs, $menu,
         $method_text, $target_text, $namexp, $ndx, $str, $value, $tab_name,
         $genid_text, $nofrow, $msg, @namexp, @names, @missing, @r_widgets );

    # Parameter hash,

    %params = map { $_->[0], $_->[1] } @{ $state->{"params"} };

    $dataset = $state->{"dataset"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORM ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $params{"maxtablen"} ) {
        push @msgs, [ "Error", qq (Maximum table length missing. Please enter a positive integer.) ];
    } elsif ( $params{"maxtablen"} !~ /^\s*\d+\s*$/ ) {
        push @msgs, [ "Error", qq (Maximum table length looks wrong, should be a positive integer.) ];
    }

    if ( @msgs ) {
        push @{ $msgs }, @msgs;
        return;
    }

    $dbh = &Common::DB::connect( $state->{"dataset"} );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> WARNINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @msgs = ();
    
    if ( $params{"mirna_names"} )
    {
        @names = &Expr::DB::split_names( $params{"mirna_names"} );
        @missing = &Expr::DB::mc_missing_mirids( $dbh, \@names, $params{"method"} );

        if ( @missing ) {
            $str = join qq (", "), @missing;
            push @msgs, ["Warning", qq (Wrong looking miRNA names: "$str". Check with the menus.)
                                   .qq ( Names must match exactly, except they are case independent.) ];
        }
    }

    if ( $params{"genid_names"} )
    {
        @names = &Expr::DB::split_names( $params{"genid_names"} );
        @missing = &Expr::DB::mc_missing_genids( $dbh, \@names );

        if ( @missing ) {
            $str = join qq (", "), @missing;
            push @msgs, ["Warning", qq (Wrong looking gene ids: "$str". Names must match the HUGO names exactly, except)
                                   .qq ( they are case independent.) ];
        }
    }

    if ( $params{"target"} eq "cons_val" and $params{"correlation"} eq "positive" )
    {
        $params{"correlation"} = "negative";
        push @msgs, [ "Warning", qq (The chosen analysis type does not produce positive correlations)
                                .qq ( - reset to negative correlations.) ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE TITLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $titles = &Query::MC::Viewer::table_titles( $dataset, \%params );

    $params{"fields"} = [ map { $_->{"name"} } @{ $titles } ];

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $table = &Expr::DB::mc_query( $dbh, \%params );

    &Common::DB::disconnect( $dbh );

    $nofrow = $table->row_count;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PAGE TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $mirna = $params{"mirna_single"} ) {
        $mirna = $params{"mirna_family"};
    } 
    
    if ( $mirna ) {
        $title = $mirna;
    } elsif ( $params{"mirna_names"} ) {
        $title = "Custom miRNAs";
    } else {
        $title = "Any miRNA";
    }

    @l_widgets = &Common::Widgets::title_box( "$title", "title_box" );

    if ( @{ $table->values } ) {
        push @l_widgets, &Query::MC::Widgets::downloads_icon( $sid );
    }

    push @r_widgets, &Query::MC::Widgets::help_icon( $sid, "help_mirconnect" );

    $xhtml = &Common::Widgets::spacer( 10 );
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, \@r_widgets );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MESSAGES IF ANY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $menu = &Query::MC::Menus::query_menu( $state->{"dataset"}, $state->{"params"} );

    if ( @msgs ) {
        $xhtml .= &Query::Widgets::message_box( \@msgs );
    } else {
        $xhtml .= &Common::Widgets::spacer( 10 );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RETURN IF EMPTY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $nofrow == 0 )
    {
        $desc = &Query::MC::Viewer::settings_text( $menu, \%params );
        $msg = qq (<strong>There were no matches</strong><p>Please click Query in the menu bar and)
             . qq ( try change settings.</p><p>$desc.</p>);
        
        $xhtml .= &Query::Widgets::message_area( $msg );
        return $xhtml;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $params{"mirna_single"} or $params{"mirna_family"} or $params{"mirna_names"} ) {
        $str = "mRNA genes";
    } else {
        $str = "miRNAs";
    }

    if ( $nofrow < $params{"maxtablen"} ) {
        $desc = "The table below shows all $nofrow correlating $str.";
    } else {
        $desc = "The table below shows the $nofrow most strongly correlating $str.";
    }
    
    $desc .= &Query::MC::Viewer::settings_text( $menu, \%params );
    $desc .= ". Click Query in the menu bar to bring back the query page.";
    
    $xhtml .= qq (<table cellpadding="5"><tr><td>$desc</td></tr></table>\n\n);
    $xhtml .= &Common::Widgets::spacer( 10 );

    # Highlight name matches,

    if ( $namexp = $params{"annot_filter"} )
    {
        @namexp = &Common::DB::parse_fulltext( $namexp );

        $ndx = $table->col_index("gene_name");

        foreach $row ( @{ $table->values } )
        {
            foreach $namexp ( @namexp )
            {
                if ( $row->[$ndx] =~ /$namexp/i ) {
                    $row->[$ndx] = $PREMATCH ."<strong>$MATCH</strong>". $POSTMATCH;
                }
            }
        }
    }

    # Make gene_name left-adjusted, 

    $ndx = $table->col_index("gene_name");

    foreach $row ( @{ $table->values } )
    {
        if ( defined ( $value = $row->[$ndx] ) ) {
            $value = ucfirst $value;
        } else {
            $value = "";
        }

        $row->[$ndx] = { "value" => $value, "class" => "left_cell" };
    }

    # Add color ramp to correlation values,
    
    $tab_name = $params{"method"} ."_method";

    $table = &Query::Viewer::color_ramp(
        $dbh,
        {
            "table" => $table,
            "tname" => $tab_name,
            "field" => "cor_val",
        });

    if ( grep /ts_cons/, @{ $table->col_headers } )
    {
        $table = &Query::Viewer::color_ramp(
            $dbh,
            {
                "table" => $table,
                "tname" => $tab_name,
                "field" => "ts_cons",
            });
    }

    $xhtml .= qq (<table cellpadding="5"><tr><td>\n\n);
    $xhtml .= &Common::Tables::render_html( $table->values, "col_headers" => $titles );
    $xhtml .= qq (</td></tr></table>\n\n);

    $xhtml .= &Common::Widgets::spacer( 25 );

    return $xhtml;
}

sub table_titles
{
    # Niels Larsen, July 2009.

    # Returns a list of MiRConnect table titles. 

    my ( $dataset,
         $params,
        ) = @_;

    # Returns a list.

    my ( $dat_hdr, $dat_tip, $titles );

    if ( $params->{"method"} eq "dpcc" ) {
        $dat_hdr = "dPCC";
        $dat_tip = "dPCC: PCCs obtained from COMPARE analysis on real data.";
    } else {
        $dat_hdr = "sPCC";
        $dat_tip = "sPCC: Biological Correlation Factor.";
    }

    $titles = [
        { 
            "name" => "mir_id",
            "value" => "miRNA",
            "tip" => "miRNA gene name as shown in the selection menus on the query page.",
            "class" => "right_col_title"
        },{
            "name" => "gene_id",
            "value" => "Gene ID",
            "tip" => "Gene IDs as used by the Human Genome Organization.",
            "class" => "right_col_title"
        },{
            "name" => "ts_cons",
            "value" => "TS",
            "tip" => "TargetScan correlation.",
            "class" => "center_col_title",
        },{
            "name" => "cor_val",
            "value" => $dat_hdr,
            "tip" => $dat_tip,
            "class" => "right_col_title",
        },{
            "name" => "gene_chr",
            "value" => "Location",
            "tip" => "Human chromosome position, as taken from Human Genome Organisation downloads.",
            "class" => "right_col_title",
        },{ 
            "name" => "gene_name",
            "value" => "HUGO Annotated Function",
            "tip" => "Human gene function annotation, as taken from Human Genome Organisation downloads.",
            "class" => "left_col_title",
        }];
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $params->{"correlation"} eq "positive" or $dataset !~ /_q$/ ) {
        $titles = [ grep { $_->{"name"} ne "ts_cons" } @{ $titles } ];
    }

    if ( $params->{"mirna_single"} or $params->{"mirna_family"} ) {
        $titles = [ grep { $_->{"name"} ne "mir_id" } @{ $titles } ];
    }

    return $titles;
}

1;

__END__
