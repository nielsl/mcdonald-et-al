package Submit::Widgets;     #  -*- perl -*-

# Widgets routines specific to the Clipboard viewer. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &aborted_icon
                 &col_titles
                 &completed_icon
                 &config_icon
                 &create_table
                 &downloads_icon
                 &format_table_row
                 &format_title_row
                 &help_icon
                 &message_area
                 &message_box
                 &noresults_icon
                 &org_viewer_icon
                 &params_header_bar
                 &params_panel
                 &pending_icon
                 &results_menu
                 &running_icon
                 &upload_field
                 );

use Common::Config;
use Common::Messages;

use Common::Tables;
use Common::Widgets;
use Common::Names;
use Common::Menus;

use Registry::Get;
use Registry::Args;

use Submit::Menus;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Viewer_name = "submit_viewer";

# Default colors, 

our $FG_color = "#ffffcc";
our $BG_color = "#666666";

# Default tooltip sizes,

our $TT_border = 3;
our $TT_textsize = "12px";
our $TT_captsize = "12px";
our $TT_delay = 300;   # milliseconds before tooltips show

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub aborted_icon
{
    # Niels Larsen, December 2005.

    # Returns an "aborted" icon with a small tooltip and a link that pops
    # up a message window.

    my ( $sid,            # Session id
         $job_id,         # Job id 
         $height,
         $width,
         $img,
         ) = @_;

    # Returns a string.

    my ( $url, $args, $text, $xhtml );

    $height ||= 700;
    $width ||= 600;

    $url = qq ($Common::Config::cgi_url/index.cgi?viewer=clipboard;request=show_error_message;job_id=$job_id);
    $url .= qq (;session_id=$sid);
    
    if ( defined $img ) {
        $img = qq (<img src="$Common::Config::img_url/$img" border="0" alt="Job aborted prematurely" />);
    } else {
        $img = qq (<img src="$Common::Config::img_url/sys_aborted.png" border="0" alt="Job aborted prematurely" />);
    }        

    $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'Job Aborted',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize',DELAY,'$TT_delay');

    $text = qq (The job was aborted prematurely, click for details.);

    $xhtml = qq (<a href="javascript:open_window('popup','$url',$width,$height)")
           . qq ( onmouseover="return overlib('$text',$args);" onmouseout="return nd();">$img</a>);
    
    return $xhtml;
}

sub col_titles
{
    # Niels Larsen, November 2005.

    # Gives titles and tooltips to the table headers. 

    # Returns a hash.

    my ( $titles );

    $titles = {
        "checkbox" => [ "", qq (Checkboxes for row selection.), "center" ],
        "coltext" => [ "Col", "Column label", qq (Title abbreviation used in viewers, e.g. as column IDs.), "center" ],
        "count" => [ "Entries", "Entries", qq (The number of entries, like the number of sequences in an upload.), "right" ],
        "datatype" => [ "Data type", "Data type", qq (The input data type, such as organisms, alignment, etc.), "center" ],
        "date" => [ "Date", "Date", qq (The time where the selection was created or the upload made.), "center" ],
        "id" => [ "Job", "Job ID", qq (ID of the submitted job.), "right" ],
        "message" => [ "System message", "System message", qq (Optional message from the system about the fate of this job.), "left" ],
        "method" => [ "Method", "Method", qq (The type of analysis that we offer with this type of data, either a single program or a pipeline of programs.), "center" ],
        "objtype" => [ "Type", "Data type", qq (The item type, such as upload, selection, etc.), "center" ],
        "userfile" => [ "Orig. file", "Original file", qq (The name of the uploaded file on your computer.), "left" ],
        "config" => [ "Conf", "Configure", qq (Configure and save parameters for the chosen method.), "center" ],
        "results" => [ "Views", "Views", qq (Menu of viewer pages where the result(s) are shown.), "center" ],
        "run_time" => [ "Time", "Run time", qq (The number of seconds a job has been running.), "right" ],
        "serverdb" => [ "Server data", "Server data", qq (The server database used with the selected method.), "center" ],
        "status" => [ "Status", "Job status", qq (Whether a job is pending, running or completed.), "center" ],
        "sub_time" => [ "Submitted when", "Submitted when", qq (The time where the job was submitted.), "center" ],
        "title" => [ "Menu title", "Menu title", qq (The title that appears in pulldown menus on viewer pages.), "left" ],
        "view" => [ "View", "Viewer links", qq (Viewer icons that show the data when clicked.), "center" ],
    };

    return $titles;
}

sub completed_icon
{
    # Niels Larsen, December 2005.
    
    # Returns a "completed" icon with a small tooltip.

    my ( $method,
         ) = @_;

    # Returns a string.
    
    my ( $args, $text, $xhtml );

    $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'Job Completed',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

    $text = qq (The $method job was completed successfully. Results are in the Views pulldown menu.);

    $xhtml = qq (<div onmouseover="return overlib('$text',$args);" onmouseout="return nd();" />)
           . qq (<img src="$Common::Config::img_url/sys_completed.png" border="0" alt="Job completed successfully"></div>);
    
    return $xhtml;
}

sub config_icon
{
    # Niels Larsen, April 2007.
    
    # Returns a configuration window with save buttons.

    my ( $sid,            # Session id
         $cid,            # Job id 
         $method,         # Method id
         $height,
         $width,
         ) = @_;

    # Returns a string.

    my ( $url, $args, $text, $xhtml, $img );

    $height ||= 700;
    $width ||= 600;

    $url = qq ($Common::Config::cgi_url/index.cgi?viewer=clipboard;request=show_params_page)
         . qq (;clipboard_id=$cid;clipboard_method=$method;session_id=$sid);

    $img = qq (<img src="$Common::Config::img_url/sys_params.png" border="0" alt="Configure" />);

    $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'Configure',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

    $text = qq (Opens a window where $method parameters can be saved, as default or per-job.);

    $xhtml = qq (<a href="javascript:open_window('popup','$url',$width,$height)")
           . qq ( onmouseover="return overlib('$text',$args);" onmouseout="return nd();">$img</a>);
    
    return $xhtml;
}

sub create_table
{
    # Niels Larsen, November 2005.

    # Creates xhtml that shows the content of the clipboard. 

    my ( $args,
         ) = @_; 

    # Returns an xhtml string.

    my ( @table, $tabrow, $xhtml, $i, $titles, $datatype, $all_meths, 
         $all_dbs, $all_types, $dbname, $name, $type, @methods,
         @dbnames, @names, @types, @opts, @formats, $opt, @searchdbs,
         $method, @user_dbs, @rows, $row );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( session_id ) ],
        "O:1" => "menu",
        "AR:1" => "colkeys",
    });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First title,

    $titles = &Submit::Widgets::col_titles();

    @table = [ &Submit::Widgets::format_title_row( $args->colkeys, $titles ) ];

    # Then rows,

    foreach $row ( @{ $args->menu->options } )
    {
        $datatype = $row->datatype || "";

        if ( $datatype eq "orgs_taxa" ) {
            $row->css( "blue_cell" );
        } else {
            $row->css( "std_cell" );
        }

        push @table, [ &Submit::Widgets::format_table_row( $args->session_id, $row, 
                                                              $args->colkeys, $titles ) ];
    }

    # And render it,
    
    $xhtml = &Common::Tables::render_html( \@table, "show_empty_cells" => 0 );

    return $xhtml;
}

sub format_table_row
{
    # Niels Larsen, November 2005.

    # Makes a table row from a given list of keys. It is a helper routine to the 
    # create_table function in this package. It takes care of the rendition of all
    # possible types as specified by keys. These keys are being used for different 
    # pages showing different columns from the clipboard. 

    my ( $sid,          # Session id
         $tabrow,       # Table row object
         $colkeys,      # List of column keys
         $titles,       # The hash defined in col_titles
         ) = @_;

    # Returns a list. 

    my ( @row, $colkey, $rowid, $timestr, $css, $style, $results_menu, $name, 
         $names, $count, $img, $datatype, @ids, $i, $opts, $method, $icon, $string,
         @path, $path, $title, $status, @css, @elems, $value, $opt, $epoch, $button,
         $dbname, $meths, $dbs, $type, $serverdb_str, $dir, $format, $meth_selected,
         $params, $message, @opts, $id );

    foreach $colkey ( @{ $colkeys } )
    {
        $rowid = $tabrow->id;

        $style = "";

        if ( $colkey eq "checkbox" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECKBOX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $tabrow->label and $tabrow->label eq "with_checkbox" )
            {
                if ( $tabrow->selected ) {
                    push @row, qq (<input type="checkbox" name="id" value="$rowid" class="checkbox" checked>);
                } else {
                    push @row, qq (<input type="checkbox" name="id" value="$rowid" class="checkbox">);
                }
            }
            else {
                push @row, ""; 
            }
        }
        elsif ( $colkey eq "count" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            # This can be for example the number of entries, etc,

            if ( defined $tabrow->count ) {
                push @row, &Common::Util::commify_number( $tabrow->count );
            } else {
                push @row, "";
            }
        }
        elsif ( $colkey eq "date" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATION DATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            # This can be for example the date the upload was made, etc,

            # $timestr = &Common::Util::epoch_to_time_string( $tabrow->date );
            $timestr = $tabrow->date;
            $timestr =~ s/:\d+$//;
            
            push @row, $timestr;
        }
        elsif ( $colkey eq "results" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $tabrow->results_menu and @{ $tabrow->results_menu->options } ) {
                push @row, &Submit::Widgets::results_menu( $sid, $tabrow->id, $tabrow->results_menu );
            } else {
                push @row, "";
            }
        }
        elsif ( $colkey eq "method" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHOD CHOICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            
            if ( $tabrow->objtype eq "job" ) 
            {
                # If a job, then just print the method name without choice,

                push @row, Registry::Get->method( $tabrow->method )->title;
            }
            else
            {
                # Otherwise make menu of all methods that match datatype and format 
                # of the clipboard item.

                $meths = $tabrow->methods_menu;
                $opts = $meths->options;
                
                if ( not @{ $opts } )
                {
                    # If none, just print empty cell, no style,
                    
                    push @row, qq (&nbsp;None&nbsp;);
                    $style = "missing";
                }
                elsif ( scalar @{ $opts } == 1 )
                {
                    $meth_selected = $opts->[0];

                    # If a single one, print unchangable field and set style,

                    $value = $meth_selected->name;
                    $title = $meth_selected->title;
                    
                    push @row, qq (<input type="hidden" name="methods_menu_$rowid" value="$value" />$title);
                }
                else
                {
                    foreach $opt ( @{ $opts } ) {
                        $opt->id( $opt->name );    # WHY
                    }

                    $meths->onchange( "javascript:handle_menu(this.form.methods_menu_$rowid)" );
                    $meths->css("methods_menu");

                    push @row, &Common::Widgets::pulldown_menu( $meths, { "close_button" => 0 } );
                }
            }
        }
        elsif ( $colkey eq "serverdb" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA CHOICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $tabrow->objtype eq "job" )
            {
                # If a job, then just print the data name without choice,

                if ( $tabrow->serverdb )
                {
                    ( $dbname, $name, $type ) = &Common::Names::parse_serverdb_str( $tabrow->serverdb );

                    if ( $dbname eq "clipboard" ) {
                        push @row, $tabrow->title;
                    } else {
                        push @row, Registry::Get->dataset( $dbname )->title;
                    }
                } 
                else {
                    push @row, "";
                }
            }
            elsif ( $tabrow->method ) 
            {
                # Otherwise look for all data that match datatype and format of the 
                # selected method,

                $dbs = $tabrow->datasets_menu;
 
                if ( $dbs )
                {
                    if ( scalar @{ $dbs->options } > 1 )
                    {
                        # If several, create pulldown menu. If no data is set for this row, 
                        # set it to the first of the choices in the menu,
                        
                        $dbs->onchange( "javascript:handle_menu(this.form.searchdbs_menu_$rowid)" );
                        $dbs->css("searchdbs_menu");
                        
                        push @row, &Common::Widgets::pulldown_menu( $dbs, { "close_button" => 0 } );
                    }
                    elsif ( scalar @{ $dbs->options } == 1 )
                    {
                        # If only one, just print it, no style,

                        $opt = $dbs->get_option( 0 );
                        
                        $value = $opt->id;
                        $title = $opt->title;

                        push @row, qq (<input type="hidden" name="searchdbs_menu_$rowid" value="$value" />$title);
                    }
                    else 
                    {
                        push @row, qq (&nbsp;None&nbsp;);
                        $style = "missing";
                    }
                }
                else {
                    push @row, qq (&nbsp;None&nbsp;);
                    $style = "missing";
                }
            }
            else {
                push @row, qq (&nbsp;None&nbsp;);
                $style = "missing";
            }
        }
        elsif ( $colkey eq "sub_time" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> JOB START TIME <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            $timestr = &Common::Util::epoch_to_time_string( $tabrow->sub_time );
            push @row, "<tt>$timestr</tt>";
        }
        elsif ( $colkey eq "run_time" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> JOB RUN TIME <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $tabrow->status eq "running" )
            {
                $epoch = &Common::Util::time_string_to_epoch();
                $count = $epoch - $tabrow->beg_time;
                $count = &Common::Util::commify_number( $count );
                push @row, "<tt>$count</tt>";
            }
            else
            {
                $count = $tabrow->end_time - $tabrow->beg_time;
                $count = &Common::Util::commify_number( $count );
                push @row, "<tt>$count</tt>";
            }
        }
        elsif ( $colkey eq "userfile" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ORIGINAL FILE NAME <<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $tabrow->userfile ) {
                push @row, "<tt>".$tabrow->userfile."</tt>";
            } else {
                push @row, "";
            }
        }
        elsif ( $colkey eq "config" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS ICON <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( $tabrow->method )
            {
                $method = Registry::Get->method_max( $tabrow->method );
                
                push @row, &Submit::Widgets::config_icon( $sid, $rowid, $method->name,
                                                             $method->window_height,
                                                             $method->window_width );
            } else {
                push @row, "";
            }
        }
        elsif ( $colkey eq "view" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> VIEWER ICON <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            $datatype = $tabrow->dataset->datatype;

            if ( &Common::Types::is_alignment( $datatype ) ) {
                push @row, &Common::Widgets::array_viewer_icon( $sid, $tabrow->input );
            } else {
                push @row, "";
            }
        }
        elsif ( $colkey eq "status" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> JOB STATUS ICON <<<<<<<<<<<<<<<<<<<<<<<<<<<
            
            $status = $tabrow->status;

            if ( $status eq "aborted" )
            {
                $icon = &Submit::Widgets::aborted_icon( $sid, $rowid, 750, 600 );
            }
            elsif ( $status eq "completed" )
            {
                if ( $tabrow->results_menu and @{ $tabrow->results_menu->options } ) {
                    $icon = &Submit::Widgets::completed_icon( $tabrow->method );
                } else {
                    $icon = &Submit::Widgets::noresults_icon( $tabrow->method );
                    $tabrow->message("No results");
                }
            }
            else {
                $icon = eval "&Submit::Widgets::$status" ."_icon()";
            }

            push @row, $icon;
        }
        elsif ( $colkey eq "message" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> JOB MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            $message = ucfirst $tabrow->message;

            $string = qq (<table cellpadding="0" cellspacing="0"><tr><td>&nbsp;&nbsp;)
                    . qq ($message</td></tr></table>);

            push @row, $string;
        }
        elsif ( $colkey eq "datatype" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATATYPE TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            push @row, Registry::Get->type( $tabrow->dataset->datatype )->title;
        }
        elsif ( $colkey eq "objtype" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OBJECT TYPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            push @row, "&nbsp;". (ucfirst $tabrow->$colkey || "");
        }
        else {

            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EMPTY CELL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            push @row, "&nbsp;". ($tabrow->dataset->$colkey || "");
        }

        push @css, $style || $titles->{ $colkey }->[3] || $tabrow->css || "";
    }

    # Add styles,

    for ( $i = 0; $i <= $#row; $i++ )
    {
        if ( $row[$i] ) {
            push @elems, &Common::Tables::xhtml_style( $row[$i], $css[$i]."_cell" );
        } else {
            push @elems, "";
        }
    }

    return wantarray ? @elems : \@elems;
}

sub format_title_row
{
    # Niels Larsen, November 2005.

    # Returns a list of table headers with tooltips. The given
    # list of keys selects which columns are included. 

    my ( $colkeys,       # List of column keys
         $titles,        # Hash defined by col_titles
         ) = @_;

    # Returns a list. 

    my ( $colkey, @row, $align, $label, $title, $tip, $div, $args );

    foreach $colkey ( @{ $colkeys } )
    {
        if ( $colkey eq "checkbox" )
        {
            push @row, "";
        }
        else
        {
            ( $label, $title, $tip, $align ) = @{ $titles->{ $colkey } };
            
            $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'$title',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,'$TT_border',DELAY,'$TT_delay');
            $div = qq (<div onmouseover="return overlib('$tip',$args);" onmouseout="return nd();" />$label</div>);
            
            push @row, &Common::Tables::xhtml_style( $div, $align ."_col_title" );
        }
    }

    return wantarray ? @row : \@row;
}

sub help_icon
{
    # Niels Larsen, July 2009.
    
    my ( $sid,
         $request,
        ) = @_;

    # Returns an xhtml string. 

    my ( $args, $descr );

    $request //= "help";

    $descr = "Provides help in a pop-up window.";

    $args = {
        "viewer" => $Viewer_name,
        "request" => $request,
        "sid" => $sid,
        "title" => "Help Window",
        "description" => $descr,
        "icon" => "sys_help2.gif",
        "height" => 700,
        "width" => 600,
        "tt_fgcolor" => $FG_color,
        "tt_bgcolor" => $BG_color,
        "tt_width" => 200,
    };

    return &Common::Widgets::window_icon( $args );
}

sub message_area
{
    # Niels Larsen, January 2007.

    # Returns a message area with lots of spacing around it. 

    my ( $msg,
         ) = @_;

    # Returns a string.

    my ( $xhtml );

    $xhtml .= qq (<p>\n<table><tr><td height="10"></td></tr></table>\n);
    $xhtml .= qq (<p>\n<table align="center" width="50%" class="message_area"><tr><td class="info_page">$msg</td></tr></table>\n);
    $xhtml .= qq (<table><tr><td height="130"></td></tr></table>\n);

    return $xhtml;
}

sub message_box
{
    # Niels Larsen, January 2007.

    # Returns a message box with a bit of spacing around it. 

    my ( $msgs,
         ) = @_;

    # Returns a string.

    my ( $xhtml );

    $xhtml = qq (<p>\n<table><tr><td height="5"></td></tr></table>\n)
               . &Common::Widgets::message_box( $msgs ) ."\n</p>\n"
               . qq (<table><tr><td height="5"></td></tr></table>\n);

    return $xhtml;
}

sub noresults_icon
{
    # Niels Larsen, May 2007.
    
    # Returns an "incomplete" icon with a small tooltip. Its an
    # orange warning circle.

    my ( $method,
         ) = @_;

    # Returns a string.
    
    my ( $args, $text, $xhtml );

    $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'No results',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

    $text = qq (The $method job completed, but without matches.)
          . qq ( Parameters may be changed with the tools icon on the Launch page.);

    $xhtml = qq (<img src="$Common::Config::img_url/sys_warning.png" border="0" alt="No results")
           . qq ( onmouseover="return overlib('$text',$args);" onmouseout="return nd();">);
    
    return $xhtml;
}

sub org_viewer_icon
{
    my ( $args, $text, $xhtml );

    $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'Organism Viewer',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

    $text = qq (Click here to see the result projected on the organism viewer.);

    $xhtml = qq (<img src="$Common::Config::img_url/sys_org_viewer.png" border="0" alt="Organism Viewer")
           . qq ( onmouseover="return overlib('$text',$args);" onmouseout="return nd();">);

#    $xhtml = qq (<input type="button" value="Org" class="org_viewer" border="0" alt="Organism Viewer")
#           . qq ( onmouseover="return overlib('$text',$args);" onmouseout="return nd();">);
    
    return $xhtml;
}

sub params_header_bar
{
    my ( $text,
         ) = @_;

    my ( $xhtml );

    $xhtml = qq (<table border="0" cellpadding="0" cellspacing="0">)
           . qq (<tr><td><img src="/Software/Images/sys_params_large.png"></td>)
           . qq (<td>&nbsp; $text</td></tr>)
           . qq (</table>);

    return &Common::Widgets::popup_bar( $xhtml );
}

sub params_panel
{
    # Niels Larsen, May 2007.

    # Creates a parameter input form window, given a session id and 
    # a method id. 

    my ( $args,
         $msgs,          # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns an XHTML string.

    my ( $method, $sid, $cid, $params, $page_descr, $cite_text, $field, $type,
         $index, $title, $tuple, @opts, @sub_opts, $sub_menu, $menu, $xhtml, $opt,
         $names );
         
    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( session_id clipboard_id uri_path datatype ) ],
        "O:1" => "method",
    });

    $sid = $args->session_id;
    $method = $args->method;
    $cid = $args->clipboard_id;

    if ( not defined ( $index = &Common::Util::first_index( $method->itypes, $args->datatype ) ) )
    {
        $index = &Common::Util::first_index( $method->dbitypes, $args->datatype );
    }
    
    if ( $index ) {
        $type = $method->otypes->[ $index ];
    } else {
        &error( qq (Index not found) );
    }

    $params = $method->params;

    if ( not ( $page_descr = $params->description ) ) {
        $page_descr = "";
    }

    if ( not ( $cite_text = $params->citation ) ) {
        $cite_text = "";
    }

    # Pre-parameters,

    if ( $method->pre_params )
    {
        $method->pre_params->values->sort_options("selectable");
        @sub_opts = $method->pre_params->values->match_options( "visible" => 1 );
        @sub_opts = reverse @sub_opts;
        
        $sub_menu = Registry::Get->new( "options" => \@sub_opts );
        $sub_menu->title( "Pre-settings" );
        
        push @opts, &Storable::dclone( $sub_menu );
    }
    
    # Parameters,

    if ( $method->params )
    {
        $method->params->values->sort_options("selectable");
        @sub_opts = $method->params->values->match_options( "visible" => 1 );
        @sub_opts = reverse @sub_opts;
        
        $sub_menu = Registry::Get->new( "options" => \@sub_opts );
        $sub_menu->title( "Main analysis" );
        
        push @opts, &Storable::dclone( $sub_menu );
    }

    # Post-parameters,

    if ( $method->post_params )
    {
        @sub_opts = $method->post_params->values->match_options( "visible" => 1 );

        foreach $opt ( @sub_opts )
        {
            if ( $opt->name =~ /method$/ and $opt->choices )
            {
                # Retain only methods compatible with current datatype, 

                $menu = Registry::Get->methods( [ $opt->choices->options_names ] );
                $menu->match_options( "itypes" => $type );

                $opt->choices->match_options( "name" => [ $menu->options_names ] );
            }
        }

        $sub_menu = Registry::Get->new( "options" => \@sub_opts );
        $sub_menu->title( "Post-analysis" );

        push @opts, &Storable::dclone( $sub_menu );
    }

    $menu = Registry::Get->new();
    $menu->options( \@opts );

    $xhtml = &Common::Widgets::form_page( $menu, {

        "form_name" => "clip_params_panel",
        "param_key" => "clip_params_keys",
        "param_values" => "clip_params_values",

        "viewer" => $Viewer_name,
        "session_id" => $sid,
        "uri_path" => $args->uri_path,

        "header_icon" => "sys_params_large.png",
        "header_title" => "Set parameters for ". $method->name,
        "description" => $page_descr,
        "citation" => $cite_text,

        "buttons" => [{
            "type" => "submit",
            "request" => "request",
            "value" => "Save",
            "description" => "Sets the parameters for this analysis only.",
            "style" => "grey_button",
        },{
            "type" => "submit",
            "request" => "request",
            "value" => "Save as default",
            "description" => "Saves the parameters as default for future analyses of this type.",
            "style" => "grey_button",
        },{
            "type" => "submit",
            "request" => "request",
            "onclick" => qq (this.form.target='_self'),
            "value" => "Reset",
            "description" => "Resets the form to system defaults.",
            "style" => "grey_button",
        }],

        "hidden" => [
            { "name" => "page", "value" => "show_launch_page" },
            { "name" => "clipboard_id", "value" => $cid },
            { "name" => "clipboard_method", "value" => $method->name },
            ],        
        });

    return $xhtml;
}

sub pending_icon
{
    # Niels Larsen, December 2005.
    
    # Returns a "running" icon with a small tooltip.

    # Returns a string.
    
    my ( $args, $text, $xhtml );

    $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'Job is pending',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

    $text = qq (The job is waiting to be run in the background.);

    $xhtml = qq (<img src="$Common::Config::img_url/sys_pending.png" border="0" alt="Job is pending")
           . qq ( onmouseover="return overlib('$text',$args);" onmouseout="return nd();">);
    
    return $xhtml;
}

sub results_menu
{
    # Niels Larsen, February 2007.

    # Generates a menu where results are grouped for different viewers,
    # separated by colored dividers. An asterisk indicates options selected. 

    my ( $sid,        # Session id
         $jobid,      # Job id
         $menu,
         ) = @_;

    # Returns an xhtml string. 

    my ( $ids, $xhtml, $name, $option, @divs );

    if ( not defined $menu ) {
        $menu = Submit::Menus->job_results( $sid, $jobid );
    }

    @divs = (
             [ "prot_ali", "Matches", "green_menu_divider" ],
             [ "rna_ali", "Matches", "green_menu_divider" ],
             [ "dna_ali", "Matches", "green_menu_divider" ],
             );

    $menu->add_dividers( \@divs );

#    $menu->select_options( $ids );

    $name = $menu->name;

    $menu->onchange( "javascript:handle_results_menu(this.form.$name)" );
    $menu->css( "beige_menu" );

    $menu->fgcolor( $FG_color );
    $menu->bgcolor( $BG_color );

    $xhtml = &Common::Widgets::pulldown_menu( $menu, { "close_button" => 0 } );
    
    return $xhtml;
}

sub running_icon
{
    # Niels Larsen, December 2005.
    
    # Returns a "running" icon with a small tooltip.

    # Returns a string.
    
    my ( $args, $text, $xhtml );

    $args = qq (LEFT,OFFSETX,-220,OFFSETY,-60,CAPTION,'Job is running',FGCOLOR,'$FG_color',BGCOLOR,'$BG_color',BORDER,3)
          . qq (,TEXTSIZE,'$TT_textsize',CAPTIONSIZE,'$TT_captsize');

    $text = qq (The analysis is currently running in the background. A spinning busy icon is shown in the main)
          . qq ( menu bar which turns green when all jobs are completed, and red if there was a problem.);

    $xhtml = qq (<img src="$Common::Config::img_url/sys_running.gif" border="0" alt="Job is running")
           . qq ( onmouseover="return overlib('$text',$args);" onmouseout="return nd();">);
    
    return $xhtml;
}

sub upload_field
{
    # Niels Larsen, October 2004.

    # Prints an upload field. 

    my ( $name,    # Name
         $value,   # Value
         $size,    # Width 
         $maxl,    # Maximum number of characters
         ) = @_;
    
    # Returns an XHTML string. 

    my ( $xhtml );

    $size ||= 70;
    $maxl ||= 200;

    $xhtml = qq (\n<input type="file" name="$name" size="$size" maxlength="$maxl" />);

    return $xhtml;
}

1;

__END__
