package Expr::Stats;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Expression profile filtering and statistics routines.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &count_file
                 &create_stat
                 &create_stats
                 &process_args
                 &render_groups
                 &render_groups_chart
                 &render_groups_html
                 &render_groups_params
);

use Config::General;

use Common::Config;
use Common::Messages;
use Common::Tables;
use Common::Table;
use Common::Names;

use Registry::Args;
use Recipe::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub count_file
{
    # Niels Larsen, May 2011.

    # Filters an expression profile table, as generated with expr_profile. 

    my ( $file,
         $conf,
        ) = @_;
    
    my ( $table, $type, $mol_match, $mol_nomatch, $title, $dat_match, 
         $dat_nomatch, @rows, $regexp, $row, @counts, @orig_rows );

    # Slurp whole table,

    $table = &Common::Table::read_table( $file );

    use constant WGT_NDX => 0;
    use constant SUM_NDX => 1;
    use constant SEQ_NDX => 2;
    use constant DB_NDX => 4;
    use constant ANN_NDX => 5;

    @orig_rows = @{ &Storable::dclone( $table->values ) };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Filter the original table with the given dataset and/or annotation 
    # expressions. 

    @counts = ();

    foreach $type ( @{ $conf } )
    {
        $title = $type->label;

        $dat_match = $type->db_match;
        $dat_nomatch = $type->db_nomatch;

        $mol_match = $type->mol_match;
        $mol_nomatch = $type->mol_nomatch;
        
        @rows = @orig_rows;

        # >>>>>>>>>>>>>>>>>>>>>>>>>> BY DATASET <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $dat_match ) {
            @rows = grep { $_->[DB_NDX] =~ /$dat_match/i } @rows;
        }
        
        if ( $dat_nomatch ) {
            @rows = grep { $_->[DB_NDX] !~ /$dat_nomatch/i } @rows;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>> BY ANNOTATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $mol_match )
        {
            if ( ref $mol_match ) {
                $regexp = "(". ( join "|", @{ $mol_match } ) .")";
            } else {
                $regexp = $mol_match;
            }

            @rows = grep { $_->[ANN_NDX] =~ /$regexp/i } @rows;
        }

        if ( $mol_nomatch )
        {
            if ( ref $mol_nomatch ) {
                $regexp = "(". ( join "|", @{ $mol_nomatch } ) .")";
            } else {
                $regexp = $mol_match;
            }

            @rows = grep { $_->[ANN_NDX] !~ /$regexp/i } @rows;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>> ADD COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        push @counts, bless {            
            "title" => $title,
            "row_sum" => ( @rows ? scalar @rows : 0 ),
            "hit_sum" => ( @rows ? &List::Util::sum( map { $_->[SEQ_NDX] } @rows ) : 0 ),
            "exp_sum" => ( @rows ? &List::Util::sum( map { $_->[SUM_NDX] } @rows ) : 0 ),
            "exp_sum_wgt" => ( @rows ? &List::Util::sum( map { $_->[WGT_NDX] } @rows ) : 0 ),
        };
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> ADD DERIVED TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( @counts )
    {
        # Main types total,
        
        push @counts, bless {
            "title" => "Above groups total",
            "row_sum" => &List::Util::sum( map { $_->{"row_sum"} } @counts ),
            "hit_sum" => &List::Util::sum( map { $_->{"hit_sum"} } @counts ),
            "exp_sum" => &List::Util::sum( map { $_->{"exp_sum"} } @counts ),
            "exp_sum_wgt" => &List::Util::sum( map { $_->{"exp_sum_wgt"} } @counts ),
        };
    
        # Annotation total,

        @rows = grep { $_->[DB_NDX] ne "Nomatch" } @orig_rows ;
        
        push @counts, bless {            
            "title" => "Annotation total",
            "row_sum" => ( @rows ? scalar @rows : 0 ),
            "hit_sum" => ( @rows ? &List::Util::sum( map { $_->[SEQ_NDX] } @rows ) : 0 ),
            "exp_sum" => ( @rows ? &List::Util::sum( map { $_->[SUM_NDX] } @rows ) : 0 ),
            "exp_sum_wgt" => ( @rows ? &List::Util::sum( map { $_->[WGT_NDX] } @rows ) : 0 ),
        };
        
        # No-match total,
        
        @rows = grep { $_->[DB_NDX] eq "Nomatch" } @orig_rows;
        
        push @counts, bless {            
            "title" => "No-match total",
            "row_sum" => ( @rows ? scalar @rows : 0 ),
            "hit_sum" => ( @rows ? &List::Util::sum( map { $_->[SEQ_NDX] } @rows ) : 0 ),
            "exp_sum" => ( @rows ? &List::Util::sum( map { $_->[SUM_NDX] } @rows ) : 0 ),
            "exp_sum_wgt" => ( @rows ? &List::Util::sum( map { $_->[WGT_NDX] } @rows ) : 0 ),
        };
        
        # Grand total,
        
        push @counts, bless {            
            "title" => "Grand total",
            "row_sum" => scalar @orig_rows,
            "hit_sum" => &List::Util::sum( map { $_->[SEQ_NDX] } @orig_rows ),
            "exp_sum" => &List::Util::sum( map { $_->[SUM_NDX] } @orig_rows ),
            "exp_sum_wgt" => &List::Util::sum( map { $_->[WGT_NDX] } @orig_rows ),
        };
    }

    return wantarray ? @counts : \@counts;
}

sub create_stat
{
    # Niels Larsen, May 2011.

    # Creates a YAML file with counts in void context and returns a
    # perl structure in non-void context. The given file may contain several
    # "documents", which here means statistics tables with titles, type, 
    # values, etc. The routine updates the last document by appending to its 
    # table. Table headers are added only if there is no table. The 
    # formatting routines (see Workflow::Stats) know how to display the list 
    # of YAML documents.

    my ( $file,        # YAML file
         $stats,       # Statistics object 
        ) = @_;

    # Returns a hash.

    my ( @stats, $stat, $in_file, $out_file, $step_type, $flow_title, 
         $stat_rows, $row, $tot_row, $row_total, $hit_total, $exp_total,
         $exp_total_wgt, $exp_sum_wgt, $exp_sum, $exp_pct_wgt, $exp_pct,
         $recp_file, $recp_title, $recp_author );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> FROM ENVIRONMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set variables to appear in the table; if given as arguments that takes 
    # precedence, second environment variables, and finally fallback defaults.
    # The environment is used for getting values set in recipes rather than
    # given to the programs. 

    $in_file = $stats->input_file || $ENV{"BION_STEP_INPUT"};
    $out_file = $stats->output_file || $ENV{"BION_STEP_OUTPUT"};

    $flow_title = $stats->{"flow_title"} || $ENV{"BION_FLOW_TITLE"} || "Expression profile";
    $recp_title = $stats->{"recipe_title"} || $ENV{"BION_RECIPE_TITLE"} || "Recipe run";
    $recp_author = $stats->{"recipe_author"} || $ENV{"BION_RECIPE_AUTHOR"} || &Common::Config::get_contacts()->{"email"};

    $step_type = $stats->{"step_type"} || "expr_profile";

    $stat_rows = $stats->stat_rows;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ ALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( -r $file ) {
        @stats = &Common::File::read_yaml( $file );
        $stat = &Storable::dclone( $stats[-1]->[-1] );
    } else {
        @stats = ();
        $stat = {};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> ADD HEADER DEPENDING <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Only add header if no statistics exist or this type of statistics is 
    # different from the previous,

    if ( not %{ $stat } or $stat->{"type"} ne $step_type )
    {
        $stat = undef;

        $stat->{"table"}->{"col_headers"} = [
            "&nbsp;", "Expr weight", "%", "Expr plain", "%", "Hits", "Annotations", 
            ];
    
        $stat->{"table"}->{"row_headers"} = [];
    
        $stat->{"type"} = $step_type;
        $stat->{"title"} = $flow_title;
    }
    else {
        pop @stats;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILES AND TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $in_file and not $stat->{"input_file"} ) {
        $stat->{"input_file"} = $in_file;
    }

    if ( $out_file ) {
        $stat->{"output_file"} = $out_file;
    }
    
    $stat->{"recipe_title"} = $recp_title;
    $stat->{"recipe_author"} = $recp_author;
    $stat->{"stat_date"} = &Common::Util::time_string_to_epoch();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ADD ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $row = ( grep { $_->{"title"} =~ /Grand total/i } @{ $stat_rows } )[0];
    bless $row;

    $row_total = $row->row_sum;
    $hit_total = $row->hit_sum;
    $exp_total = $row->exp_sum;
    $exp_total_wgt = $row->exp_sum_wgt;

    # Add table data rows given to the routine,

    foreach $row ( @{ $stat_rows } )
    {
        $exp_sum_wgt = $row->exp_sum_wgt || 0;
        $exp_sum = $row->exp_sum || 0;

        if ( $exp_total_wgt == 0 ) {
            $exp_pct_wgt = 0;
        } else {
            $exp_pct_wgt = ( sprintf "%.1f", 100 * $exp_sum_wgt / $exp_total_wgt );
        }

        if ( $exp_total == 0 ) {
            $exp_pct = 0;
        } else {
            $exp_pct = ( sprintf "%.1f", 100 * $exp_sum / $exp_total );
        }

        push @{ $stat->{"table"}->{"values"} }, [
            ( $row->title || "" ),
            $exp_sum_wgt,
            $exp_pct_wgt,
            $exp_sum,
            $exp_pct,
            ( $row->hit_sum || 0 ),
            ( $row->row_sum || 0 ),
        ];
    }

    if ( @stats ) {
        push @{ $stats[-1] }, $stat;
    } else {
        @stats = [ $stat ];
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OR RETURN <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Return updated list in non-void context, update file in void,

    if ( defined wantarray ) {
        return wantarray ? @stats : \@stats;
    } else {
        &Common::File::write_yaml( $file, \@stats );
    }

    return;
}

sub create_stats
{
    # Niels Larsen, May 2011.

    # Creates statistics from expression tables and a given configuration 
    # file. If a single input file is given, then a named output file can
    # be written, otherwise the outputs will be named as the input but with
    # a given suffix appended. 

    my ( $args,
         $msgs,
        ) = @_;

    my ( $defs, $i, $name, $in_table, $out_stats, $conf, $tab_conf, 
         $stat_rows );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "itables" => [],
        "config" => undef,
        "stats" => undef,
        "ilabel" => undef,
        "olabel" => undef,
        "suffix" => ".stats",
	"silent" => 0,
	"verbose" => 0,
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Expr::Stats::process_args( $args );

    $tab_conf = $conf->config;

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE STATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nProfile statistics:\n) );

    for ( $i = 0; $i <= $#{ $conf->{"itables"} }; $i++ )
    {
        $in_table = $conf->{"itables"}->[$i];
        $out_stats = $conf->{"ostats"}->[$i];
    
        $name = &File::Basename::basename( $out_stats );
        &echo( "   Writing $name ... " );

        if ( $args->clobber ) {
            &Common::File::delete_file_if_exists( $out_stats );
        }

        $stat_rows = &Expr::Stats::count_file( $in_table, $tab_conf->table_row );

        &Expr::Stats::create_stat(
            $out_stats,
            bless {
                "input_file" => ( $args->ilabel // $in_table ),
                "output_file" => ( $args->olabel // $out_stats ),
                "flow_title" => $tab_conf->title,
                "stat_rows" => $stat_rows,
            }, "Expr::Stats" );
        
        &echo_green( "done\n" );
    }

    &echo_bold("Done\n\n");

    return;
}

sub process_args
{
    # Niels Larsen, May 2011.

    # Checks and expands the statistics routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $conf, $file, %valid, $key, $choices, $row, $config );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->itables and @{ $args->itables } ) {
	$conf->{"itables"} = &Common::File::check_files( $args->itables, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No input expression profile tables given) ];
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> READ CONFIGURATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file = $args->config )
    {
        if ( -r $file ) {
            $conf->{"config"} = &Common::Config::read_config_general( $file );
        } else {
            push @msgs, ["ERROR", qq (Configuration file not readable -> "$file") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (No statistics configuration file given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>> VALIDATE CONFIGURATION <<<<<<<<<<<<<<<<<<<<<<<<<<

    $config = $conf->{"config"};

    # Check main keys,

    %valid = map { $_, 1 } qw ( title table_row );
    
    foreach $key ( keys %{ $config } )
    {
        if ( not $valid{ $key } ) {
            push @msgs, ["ERROR", qq (Wrong looking configuration key -> "$key") ];
        }
    }

    if ( @msgs )
    {
        $choices = join ", ", keys %valid;
        push @msgs, ["INFO", qq (Please edit. Choices are: $choices) ];

        &append_or_exit( \@msgs );
    }

    foreach $key ( keys %valid ) {
        $config->{ $key } = undef if not exists $config->{ $key };
    }
    
    # Check section keys,

    %valid = map { $_, 1 } qw ( label db_match db_nomatch mol_match mol_nomatch );

    foreach $row ( @{ $config->{"table_row"} } )
    {
        foreach $key ( keys %{ $row } )
        {
            if ( not $valid{ $key } ) {
                push @msgs, ["ERROR", qq (Wrong looking configuration table row key -> "$key") ];
            }
        }

        foreach $key ( keys %valid ) {
            $row->{ $key } = undef if not exists $row->{ $key };
        }

        bless $row;
    }

    if ( @msgs )
    {
        $choices = join ", ", keys %valid;
        push @msgs, ["INFO", qq (Please edit. Choices are: $choices) ];

        &append_or_exit( \@msgs );
    }

    $conf->{"config"} = bless $config;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->stats ) {
        $conf->{"ostats"} = [ $args->stats ];
    } else {
        $conf->{"ostats"} = [ map { $_. $args->suffix } @{ $args->itables } ];
    }

    bless $conf;

    return wantarray ? %{ $conf } : $conf;
}

sub render_groups
{
    my ( $args,
        ) = @_;

    my ( $defs, $tables, $html, $ofile, $name, $clobber );

    $defs = {
        "ifile" => undef,
        "table" => undef,
        "chart" => "",
        "title" => undef,
        "author" => undef,
        "header" => 1,
        "footer" => 1,
        "clobber" => undef,
        "silent" => undef,
        "verbose" => undef,
    };
        
    $args = &Registry::Args::create( $args, $defs );
    
    $clobber = $args->clobber;

    &echo_bold("\nCreating HTML:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ YAML <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $name = &File::Basename::basename( $args->ifile );

    &echo("   Reading $name ... ");
    
    $tables = &Common::File::read_yaml( $args->ifile );
    bless $tables;

    map { bless $_, "Common::Table" } @{ $tables->tables };

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HTML TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->table )
    {
        if ( not $ofile = $args->table ) {
            $ofile = $args->ifile .".table.html";
        }

        $name = &File::Basename::basename( $ofile );
        &echo( "   Writing $name ... " );

        &Expr::Stats::render_groups_html(
            $tables->tables,
            {
                "title" => $tables->title,
                "author" => $tables->author,
                "config" => $tables->config,
                "clobber" => $args->clobber,
                "header" => $args->header,
                "footer" => $args->footer,
            },
            $ofile );

        &echo_done("done\n");
    }

    if ( defined $args->chart )
    {
        if ( not $ofile = $args->chart ) {
            $ofile = $args->ifile .".chart.html";
        }

        $name = &File::Basename::basename( $ofile );
        &echo( "   Writing $name ... " );

        &Expr::Stats::render_groups_chart(
            $tables->tables,
            {
                "title" => $tables->title,
                "author" => $tables->author,
                "config" => $tables->config,
                "clobber" => $args->clobber,
                "header" => $args->header,
                "footer" => $args->footer,
            },
            $ofile );
        
        &echo_done("done\n");
    }
    
    &echo_bold("Finished\n\n");

    return;
}

sub render_groups_chart
{
    # Niels Larsen, June 2011. 

    # Creates HTML with Google line-chart figures. Returns an HTML 
    # string.

    my ( $tables,
         $args,
         $ofile,
        ) = @_;

    # Returns a string.

    my ( $html, $table, $ofh, $row, $col, $col_names, $name, @vals, $valstr, 
         $values, $height, $grafwid, $chartwid, $title, $chart_num, $params,
         $namlen, $row_names );

    $html = &Workflow::Stats::html_header( bless $args, "Workflow::Stats" );

    $html .= &Common::Widgets::spacer( 15 );
    $html .= &Expr::Stats::render_groups_params( $args->config );

    $html .= qq (\n<script type="text/javascript" src="https://www.google.com/jsapi"></script>\n);

    $chart_num = 0;

    foreach $table ( @{ $tables } )
    {
        # Pop the first column,

        shift @{ $table->col_headers };
        map { shift @{ $_ } } @{ $table->values };

        # The line-chart wants a table where rows are column labels followed
        # by values for each row,

        $html .= qq (
<script type="text/javascript">

   google.load("visualization", "1", {packages:["corechart"]});
   google.setOnLoadCallback(drawChart);

   function drawChart() {
      var data = new google.visualization.DataTable();

      data.addColumn('string', 'x');
);
        $namlen = 0;

        $col_names = $table->col_headers;
        $row_names = $table->row_headers;

        foreach $name ( @{ $row_names } )
        {
            $name =~ s/'/\\'/g;
            $html .= qq (      data.addColumn('number', '$name');\n);

            $namlen = &List::Util::max( length $name, $namlen );
        }

        $html .= "\n";

        $values = $table->values;

        for ( $col = 0; $col <= $#{ $col_names }; $col++ )
        {
            $name = $col_names->[$col];
            $name =~ s/'/\\'/g;

            @vals = ();

            for ( $row = 0; $row <= $#{ $values }; $row++ ) {
                push @vals, $values->[$row]->[$col] || 1;
            }
        
            $valstr = join ", ", @vals;

            $html .= qq (      data.addRow(["$name", $valstr]);\n);
        }

        $height = 350;

        $grafwid = 18 * &List::Util::sum( map { length $_ } @{ $col_names } ); 
        $grafwid = &List::Util::max( 30 * scalar @{ $col_names }, $grafwid );

        $chartwid = $grafwid + 150 + $namlen * 10;    # scale whole chart with names

        $params = qq ({width:$chartwid, height:$height, fontSize:12, backgroundColor:'#cccccc',);
        $params .= qq ( pointSize:4, vAxis: {logScale:1, format:'#0'},);
        $params .= qq ( chartArea: {left:80,top:30,width:"$grafwid",height:"80%"} });

        $chart_num += 1;

        $html .= "\n";
        $html .= qq (      var chart = new google.visualization.LineChart(document.getElementById('chart_div_$chart_num'));\n);
        $html .= qq (      chart.draw( data, $params );\n);
        $html .= "   }\n</script>\n\n";

        $html .= "<h4>". $table->title ."</h4>\n";
        $html .= qq (<div id="chart_div_$chart_num"></div>\n);
    }

    $html .= qq (<table><tr><td height="30">&nbsp;</td></tr></table>\n);
    $html .= &Workflow::Stats::html_footer( bless $args, "Workflow::Stats" );
    
    if ( $ofile )
    {
        &Common::File::delete_file_if_exists( $ofile ) if $args->{"clobber"};

        $ofh = &Common::File::get_write_handle( $ofile );    
        $ofh->print( $html );
        &Common::File::close_handle( $ofh );
    }

    if ( defined wantarray ) {
        return $html;
    }

    return;
}

sub render_groups_html
{
    my ( $tables,
         $args,
         $ofile,
        ) = @_;

    my ( $html, $table, $ofh );

    $html = &Workflow::Stats::html_header( bless $args, "Workflow::Stats" );

    $html .= &Common::Widgets::spacer( 15 );
    $html .= &Expr::Stats::render_groups_params( $args->config );

    foreach $table ( @{ $tables } )
    {
        $html .= "<h4>". $table->title ."</h4>\n";
        $html .= &Common::Tables::render_html(
            $table,
            "show_empty_cells" => 0,
            "format_decimals" => "%.2f",
            "align_columns" => [[ 0, "right" ]],
            );
    }

    $html .= qq (<table><tr><td height="30">&nbsp;</td></tr></table>\n);
    $html .= &Workflow::Stats::html_footer( bless $args, "Workflow::Stats" );
    
    if ( $ofile )
    {
        &Common::File::delete_file_if_exists( $ofile ) if $args->{"clobber"};

        $ofh = &Common::File::get_write_handle( $ofile );
    
        $ofh->print( $html );
        
        &Common::File::close_handle( $ofh );
    }

    if ( defined wantarray ) {
        return $html;
    }

    return;
}

sub render_groups_params
{
    my ( $conf,
        ) = @_;
    
    my ( $html, $menu, $sub_menu, @sub_opts, @opts, $row, $i );

    foreach $row ( @{ $conf } )
    {
        if ( ref $row->[1] )
        {
            $i = 0;

            push @sub_opts, 
            {
                "title" => $row->[0],
                "value" => 0,
                "choices" => [ map { { "name" => "", "value" => $i++, "title" => $_ } } @{ $row->[1] } ],
                "selectable" => 1,
            }
        }
        else {
            push @sub_opts, { "title" => $row->[0], "value" => $row->[1], "datatype" => "text" };
        }
    }

    $sub_menu = Registry::Get->_objectify( \@sub_opts, 1);

    push @opts, Registry::Get->new( "options" => [ $sub_menu->options ] );

    $menu = Registry::Get->new();
    $menu->options( \@opts );

    $html = qq (<h3>Inputs, methods and parameters</h3>\n);

    $html .= &Common::Widgets::form_page(
        $menu,
        {
            "form_name" => "dummy_page",
            "param_key" => "dummy_keys",
            "param_values" => "dummy_values",
            
            "viewer" => "dummy_viewer",
            "uri_path" => "",
            
            "buttons" => [],
        });
    
    return $html;
}

1;

__END__

# sub tablify
# {
#     my ( $stats,
#         ) = @_;

#     my ( $count, @col_hdrs, @row_hdrs, @values, $name );

#     # Top row with titles,

#     @col_hdrs = ( "Run", "Molecule type", "Expr weight", "%", "Expr plain", "%", "Clusters", "Annotations" );

#     # The following rows have current values plus deltas against the previous, 
    
#     foreach $count ( @{ $stats->[0]->{"counts"} } )
#     {
#         push @row_hdrs, "";

#         push @values, [
#             $count->{"title"},
#             $count->{"val_sum_wgt"},
#             $count->{"val_sum_wgt_pct"},
#             $count->{"val_sum"},
#             $count->{"val_sum_pct"},
#             $count->{"seq_sum"},
#             $count->{"row_sum"},
#         ];
#     }
    
#     $name = &File::Basename::basename( $stats->[0]->{"files"}->[0]->{"value"} );
#     $name = &Common::Names::get_prefix( $name );
#     $row_hdrs[0] = $name;

#     return ( \@col_hdrs, \@row_hdrs, \@values );
# }

# sub config_stats
# {
#     # Niels Larsen, May 2010.

#     # Names different sets of statistics categories. Each has a name and
#     # a filter to grep the profile table by. The filter is a dataset name
#     # and/or a list of regular expression for the annotation strings. If
#     # a category name is given, then the categories for that type is 
#     # returned, otherwise the whole dictionary.

#     my ( $type,    # Category name
#         ) = @_;

#     # Returns a hash.

#     my ( %types );

#     %types = (
#         "mirna" => {
#             "title" => "Micro RNA / ncRNA statistics",
#             "types" => [
#                 {
#                     "title" => "Pig miRNA",
#                     "dataset" => "MiRBase pig-subset",
#                 },{
#                     "title" => "Non-pig miRNA",
#                     "dataset" => "MiRBase mature",
#                 },{
#                     "title" => "piRNA",
#                     "annexpr" => [ "piwi" ],
#                 },{
#                     "title" => "snoRNA",
#                     "annexpr" => [ "snoRNA" ],
#                 },{
#                     "title" => "SSU rRNA",
#                     "annexpr" => [ "SSU RNA", "SSU.+ribosomal" ],
#                 },{
#                     "title" => "LSU rRNA",
#                     "annexpr" => [ "LSU RNA" ],
#                 },{
#                     "title" => "5S rRNA",
#                     "annexpr" => [ "5S.+ribosomal" ],
#                 },{
#                     "title" => "tRNA",
#                     "annexpr" => [ "tRNA" ],
#                 }],
#             },
#         );

#     if ( $type ) 
#     {
#         if ( exists $types{ $type } ) {
#             return wantarray ? %{ $types{ $type } } : $types{ $type };
#         } else {
#             &error( qq (Wrong looking statistics type -> "$type") );
#         }
#     }

#     return wantarray ? %types : \%types;
# }

    # # >>>>>>>>>>>>>>>>>>>>>>>>>>> SEPARATE HTML FILES <<<<<<<<<<<<<<<<<<<<<<<<<

    # if ( $args{"oformats"} )
    # {
    #     for ( $i = 0; $i <= $#{ $args{"ostats"} }; $i++ )
    #     {
    #         $ifile = $args{"ostats"}->[$i];
    #         $ofile = $args{"oformats"}->[$i];

    #         $name = &File::Basename::basename( $ofile );
    #         $silent or &echo( "   Writing $name ... " );
            
    #         &Workflow::Stats::render(
    #             [ $ifile ],
    #             {
    #                 "oformat" => "html",
    #                 "ofile" => $ofile,
    #                 "silent" => 1,
    #                 "clobber" => $args->clobber,
    #             });
            
    #         $silent or &echo_green( "done\n", $indent );
    #     }
    # }

    # # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SINGLE HTML FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # if ( $args{"html"} )
    # {
    #     $name = &File::Basename::basename( $args{"html"} );
    #     $silent or &echo( "   Writing merged HTML $name ... " );
        
    #     &Workflow::Stats::render_single(
    #         $args{"ostats"},
    #         {
    #             "oformat" => "html",
    #             "ofile" => $args{"html"},
    #             "silent" => 1,
    #             "clobber" => $args->clobber,
    #         });

    #     $silent or &echo_green( "done\n", $indent );
    # }

# sub colstats
# {
#     # Niels Larsen, January 2010. 

#     # Input is a list of sequence-strings, that may or may not be 
#     # aligned. Output a list of column statistics for this "alignment".
#     # See Seq::Common::seq_stats for format.

#     my ( $strs,         # List of strings
#          $begcol,       # Starting column
#          $type,         # Sequence type
#         ) = @_;

#     # Returns a list.
         
#     my ( $colpos, $colstr, $seq, $i, @maxcols, @stats );

#     $colpos = $begcol;
#     @maxcols = map { (length $_) - 1 } @{ $strs };

#     while ( 1 )
#     {
#         $colstr = "";

#         for ( $i = 0; $i <= $#{ $strs }; $i++ )
#         {
#             if ( $colpos <= $maxcols[$i] ) {
#                 $colstr .= substr $strs->[$i], $colpos, 1;
#             }
#         }

#         if ( $colstr )
#         {
#             $seq = Seq::Common->new({ "id" => "dummy", "seq" => $colstr, "type" => $type }, 0 );
#             push @stats, [ $seq->seq_stats ];
            
#             $colpos += 1;
#         }
#         else {
#             last;
#         }
#     }

#     return wantarray ? @stats : \@stats;
# }

# 1;

# __END__

# sub format_stats_table
# {
#     my ( $table,
#         ) = @_;

#     my ( @msgs, $row, @table, $text, $num );

#     foreach $row ( @{ $table } )
#     {
#         ( $text, $num ) = @{ $row };

#         if ( $num =~ /\./ ) {
#             $num = sprintf "%.2f", $num;
#         } else {
#             $num = &Common::Util::commify_number( $num );
#         }

#         push @table, [ $text, $num ];
#     }

#     @msgs = map { [ "OK", $_ ] } map { "$_->[0]: $_->[1]" } @table;

#     &echo_messages( \@msgs, { "linewid" => 60, "linech" => "-" } );
#     &echo("\n");

#     return;
# }

# sub create_stats_table
# {
#     my ( $stats,
#         ) = @_;

#     my ( $fwd_qual, $rev_qual, $fwd_hits, $rev_hits, $seq_tot, @table, $dup_ids,
#          $pct );

#     $fwd_qual = $stats->hits_forward_qual;
#     $rev_qual = $stats->hits_reverse_qual;
#     $fwd_hits = $stats->hits_forward_total;
#     $rev_hits = $stats->hits_reverse_total;
#     $seq_tot = $stats->input_seq_total;
#     $dup_ids = $stats->duplicated_ids;

#     if ( $fwd_qual and $rev_qual )
#     {
#         $pct = 100 * ( $fwd_qual + $rev_qual ) / $seq_tot;

#         push @table, [ "Forward matches filtered", $fwd_qual ];
#         push @table, [ "Reverse matches filtered", $rev_qual ];
#     }
#     else {
#         $pct = 100 * ( $fwd_hits + $rev_hits ) / $seq_tot;
#     }        

#     push @table, [ "Forward matches all", $fwd_hits ];
#     push @table, [ "Reverse matches all", $rev_hits ];
#     push @table, [ "Input sequences total", $seq_tot ];
#     push @table, [ "Duplicate ids", $dup_ids ];

#     push @table, [ "Match percent", $pct ];

#     return wantarray ? @table : \@table;
# }
