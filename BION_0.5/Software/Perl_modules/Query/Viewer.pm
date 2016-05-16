package Query::Viewer;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Viewer related routines that are not project specific. The project specific
# routines are in sub-modules (sub-directories).
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use English;

@EXPORT_OK = qw (
                 &color_ramp
                 &main
                 );

use Common::Config;
use Common::Messages;

use Common::Widgets;

use Query::State;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub color_ramp
{
    # Niels Larsen, July 2009.

    # Adds a color ramp to a given table column of numerical values. 
    # Returns an updated table.

    my ( $dbh,
         $args,
        ) = @_;

    # Returns list.
    
    my ( $sql, $min, $max, $pos_ramp, $neg_ramp, $col_ndx, $subref, 
         $row, $val, $bgcolor, $ramp_len, $ramp_max, $field, $pc_min,
         $pc_max, $nc_min, $nc_max, $table, $tname );
    
    $args = &Registry::Args::check(
        $args,
        {
            "O:2" => [ "table" ],
            "S:2" => [ qw (tname field) ],
            "S:0" => [ qw ( pos_color_min pos_color_max neg_color_min neg_color_max ) ],
        });

    $table = $args->table;
    $tname = $args->tname;
    $field = $args->field;

    $pc_min = $args->pos_color_min || "dddddd";
    $pc_max = $args->pos_color_max || "99ff99";

    $nc_min = $args->neg_color_min || "dddddd";
    $nc_max = $args->neg_color_max || "ff9999";

    # Get min and max,

    $sql = qq (select min($field) from $tname);
    $min = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

    $sql = qq (select max($field) from $tname);
    $max = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

    # Make green and red color ramp for positive and negative numbers,

    $ramp_len = 101;
    $ramp_max = $ramp_len - 1;

    $pos_ramp = &Common::Util::color_ramp( $pc_min, $pc_max, $ramp_len );
    $neg_ramp = &Common::Util::color_ramp( $nc_min, $nc_max, $ramp_len );    

    # Function that returns color ramp index,

    $subref = sub
    {
        my ( $min, $val, $max ) = @_;

        if ( ( $max - $min ) == 0 ) {
            return int ( 100 * ( $val-$min ) );
        } else {
            return int ( 100 * ( $val-$min ) / ( $max-$min ) );
        }
    };

    $col_ndx = $table->col_index( $field );
    
    foreach $row ( @{ $table->values } )
    {
        if ( $val = $row->[$col_ndx] )     # some are blank
        {
            if ( $val > 0 ) {
                $bgcolor = $pos_ramp->[ $subref->( 0, $val, $max ) ];
            } else {
                $bgcolor = $neg_ramp->[ $subref->( 0, -$val, -$min ) ];
            }

            $row->[$col_ndx] = {
                "value" => $val,
                "class" => "std_cell",
                "style" => "background-color:$bgcolor",
            };
        }
    }

    return $table;
}

sub main
{
    # Niels Larsen, March 2011.

    # Dispatches query related requests and produces html. The routine calls
    # by default a set of generic query, table, help and downloads pages, but 
    # can also call project-specific routines that live in sub-modules. Every
    # click and request goes through this routine.

    my ( $args,
         $msgs,
         ) = @_;

    # Returns an xhtml string.

    my ( $cgi, $sid, $state, $sys_state, $proj, $xhtml, $request, %modpaths, 
         $modpath, $module, $query_page, $table_page, $help_panel, 
         $downloads_panel, $download_data, $def_state );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Require all arguments present and non-empty,

    $args = &Registry::Args::check(
        $args,
        {
            "HR:2" => [ qw ( sys_state ) ],
            "O:2" => [ qw ( cgi project ) ],
        });
    
    $cgi = $args->cgi;
    $proj = $args->project;
    $sys_state = $args->sys_state;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOAD MODULES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Define more projects here,

    %modpaths = (
        "mirconnect" => "Query::MC",
        );

    if ( not $modpath = $modpaths{ $proj->name } ) {
        $modpath = "Query";
    }

    # Load project-specific or default modules,

    foreach $module ( 
        $modpath ."::Viewer",
        $modpath ."::Menus",
        $modpath ."::State",
        $modpath ."::Widgets",
        $modpath ."::Help",
        ) {
        
        eval "require $module";
        
        &error( $@ ) if $@;
    }

    $query_page = $modpath ."::Viewer::query_page";
    $table_page = $modpath ."::Viewer::table_page";
    $help_panel = $modpath ."::Help::dispatch";
    $downloads_panel = $modpath ."::Widgets::downloads_panel";
    $download_data = $modpath ."::Viewer::download_data";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE STATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This merges the CGI parameters with the current state, and creates a new 
    # default one the first time around,

    $sid = $sys_state->{"session_id"};

    $state = &Query::State::create_viewer_state(
        {
            "cgi" => $cgi,
            "sid" => $sid,
            "dataset" => $sys_state->{"inputdb"},
            "defstate" => $modpath ."::State::default_state",
        });

    $request = $state->{"request"} || "show_query_page";
    
    $msgs ||= [];       

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> HELP PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $request =~ /help/ )
    {
        no strict "refs";

        $xhtml = $help_panel->( $request );
        
        $sys_state->{"is_help_page"} = 1;
        $sys_state->{"title"} = "Help Page";

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj,
            });

        exit 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> QUERY PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    elsif ( $request eq "show_query_page" )
    {
        no strict "refs";

        $xhtml = $query_page->( $sid, $state, $proj, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request eq "Show filtered table" )
    {
        no strict "refs";

        $xhtml = $table_page->( $sid, $state, $msgs );

        if ( @{ $msgs } ) {
            $xhtml = $query_page->( $sid, $state, $proj, $msgs );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> DOWNLOADS PANEL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request eq "downloads_panel" )
    {
        {
            no strict "refs";
            
            $xhtml = $downloads_panel->(
                {
                    "params" => { map { $_->[0], $_->[1] } @{ $state->{"params"} } },
                    "sid" => $sid,
                    "viewer" => "query_viewer", 
                    "uri_path" => $proj->projpath,
                });
        }

        $sys_state->{"is_popup_page"} = 1;
        $sys_state->{"title"} = "Download Panel";

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj,
            });

        exit 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DOWNLOADS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request eq "Download" )
    {
        no strict "refs";

        $state = $download_data->( $state );
        exit 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    else {
        &error( qq (Wrong looking request -> "$request") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE STATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    delete $state->{"request"};

    &Query::State::save_state( $sid, $state );

    return $xhtml;
}

1;

__END__
