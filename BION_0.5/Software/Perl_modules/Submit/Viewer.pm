package Submit::Viewer;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use English;

@EXPORT_OK = qw (
                 &attach_dataset_menus
                 &attach_method_menus
                 &clear_user_input
                 &clipboard_page
                 &delete_clipboard_rows
                 &delete_result_rows
                 &launch_page
                 &main
                 &params_to_tuples
                 &read_form_fields
                 &results_page
                 &save_params
                 &save_params_default
                 &set_cgi_values
                 &set_checkboxes
                 &upload_data
                 &upload_page
                 &valid_params
                 );

use Common::Config;
use Common::Messages;

use Common::Widgets;
use Common::Menus;
use Common::Batch;
use Common::Users;
use Common::Table;

use Registry::Get;

use Submit::Widgets;
use Submit::Upload;
use Submit::Batch;
use Submit::Menus;

use Expr::DB;

# Default colors, 

our $FG_color = "#ffffcc";
our $BG_color = "#006666";

# Default tooltip settings,

our $TT_border = 3;
our $TT_textsize = "12px";
our $TT_captsize = "12px";
our $TT_delay = 300;   # milliseconds before tooltips show

our $Viewer_name = "submit_viewer";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub attach_dataset_menus
{
    # Niels Larsen, November 2007.

    # Assumes a method has been set, by the attach_method_menus routine. For each 
    # row a menu is created with datasets that are compatible with the set method 
    # and the clipboard dataset of that given row. If no compatible datasets found
    # no menu is attached. 

    my ( $clip,
         $data,
        ) = @_;

    # Returns a menu object.

    my ( @names, $name, @met_opts, @dat_opts, $datmap, $row, $menu, @opts, 
         $method, %met_opts );

    foreach $row ( $clip->options )
    {
        if ( $name = $row->method ) {
            push @names, $name;
        }
    }

    @met_opts = Registry::Get->methods( \@names )->options;
    %met_opts = map { $_->name, $_ } @met_opts;
    
    @dat_opts = Registry::Match->compatible_datasets_exclude( [ $data->options ], \@met_opts );

    foreach $row ( $clip->options )
    {
        if ( $row->method and $method = $met_opts{ $row->method } )
        {
        my $start = [ &Time::HiRes::gettimeofday() ]; 

            @opts = Registry::Match->compatible_datasets( \@dat_opts, $method );

        my $stop = [ &Time::HiRes::gettimeofday() ]; 
        my $diff = &Time::HiRes::tv_interval( $start, $stop );
        
            $menu = Common::Menu->new( "name" => $data->name ."_". $row->id,
                                       "options" => \@opts,
                                       "style" => $data->style );

            $row->datasets_menu( $menu );
            
        }
    }

    return $clip;
}

sub attach_method_menus
{
    # Niels Larsen, November 2007.

    # Attaches methods menus to each row of the given clipboard that can work 
    # with the datatype and format of the row. A menu of methods must be given 
    # to select from. The attached menus may have 0, 1, or several options. 
    # See also the attach_dataset_menus routine that does the same for 
    # data as this one does for methods, except it looks for compatibility 
    # with the selected method. 

    my ( $clip,      # Clipboard object
         $proj,      # Project object or name
         $data,
        ) = @_;

    # Returns a menu object.

    my ( $metmap, $mets, $mets_name, @opts, $row, @met_opts, $opt, $menu, $dset,
         %filter, @dat_mets, $skip, %skip );
 
    if ( not ref $proj ) {
        $proj = Registry::Get->project( $proj );
    }

    # Make menu of method objects that are not deselected by the project,

    $mets = Registry::Get->methods();
    $mets_name = $mets->name;
    @met_opts = $mets->options;

    if ( $skip = $proj->hide_methods )
    {
        if ( ref $skip ) {
            %skip = map { $_, 1 } @{ $skip };
        } else {
            %skip = ( $skip => 1 );
        }

        @met_opts = grep { not exists $skip{ $_->name } } @met_opts;
    }

    # Filter methods by compatibility with installed project data as well as
    # user data on the clipboard,

    @met_opts = Registry::Match->compatible_methods_exclude( \@met_opts, [ $data->options ] );
    $metmap = Registry::Match->methods_map( \@met_opts );

    foreach $row ( $clip->options ) 
    {
        $dset = $row->dataset;
        %filter = map { $_, 1 } @{ $metmap->{ $dset->datatype }->{ $dset->format } };
        @dat_mets = grep { exists $filter{ $_->name } } @met_opts;
        
        # Filter away methods that require more entries than the input has,

        @dat_mets = grep { not defined $_->min_entries or $_->min_entries <= $row->count } @dat_mets;

        # Create a simpler menu of these, where ids look like "methods_menu_2" 
        # etc. The menu can contain no elements (if no method works on the item),
        # or one or more elemens. 

        @opts = map { Registry::Get->method_min( $_ ) } @dat_mets;

        $menu = Common::Menu->new(
            "name" => $mets_name ."_". $row->id,
            "options" => &Storable::dclone( \@opts ),
            );

        # Set methods to first in menus if they are not set,

        if ( not $row->method )
        {
            if ( @opts = @{ $menu->options } ) {
                $row->method( $opts[0]->name );
            } else {
                $row->method("");
            }
        }

        # If the row method matches any of those in the menu, select it,

        if ( $opt = $menu->match_option( "name" => $row->method ) ) {
            $menu->selected( $opt->name );
        }
        
        $row->methods_menu( $menu );
    }

    return $clip;
}

sub clear_user_input
{
    # Niels Larsen, April 2007.

    # Sets the "transient" state values that come directly from user 
    # input fields to nothing. Should be called just after the place 
    # where these fields have been used/saved. The purpose is to avoid 
    # an action repeated if user pressed the reload button.

    my ( $sid,       # Session id
         $state,     # State hash
         ) = @_;

    # Returns a hash.

    $state->{"request"} = "";

    $state->{"clipboard_method"} = "";
    $state->{"clipboard_params"} = "";
    
    return $state;
}

sub clipboard_page
{
    # Niels Larsen, November 2005.
    
    # Presents the selections and uploads in a table, allowing deletion
    # of selected rows. 

    my ( $sid,       # Session id
         $msgs,
         ) = @_;
    
    # Returns an XHTML string.

    my ( @l_widgets, $xhtml, $clip, $colkeys, $message );

    # Read clipboard,

    $clip = Common::Menus->clipboard_menu( $sid );

    # Title,
    
    if ( @{ $clip->options } ) {
        push @l_widgets, &Common::Widgets::title_box( "Clipboard", "title_box" );
    } else {
        push @l_widgets, &Common::Widgets::title_box( "Empty", "title_box" );
    }

    $xhtml = &Common::Widgets::spacer( 10 );
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, [] );

    # Messages,

    if ( $msgs and @{ $msgs } ) {
        $xhtml .= &Submit::Widgets::message_box( $msgs );
    }

    if ( not @{ $clip->options } )
    {
        $message = qq (There is nothing in the clipboard. To add items, make a selection)
                 . qq ( from a viewer page, or make an upload.);
        
        $xhtml .= &Submit::Widgets::message_area( $message );

        return $xhtml;
    }

    # Set checkbox flag so that rendering adds a checkbox,

    map { $_->label("with_checkbox") } $clip->options;

    # Main table,

    $xhtml .= qq (<p>
Below each row is an upload or a selection. To delete a row, click its 
checkbox and press the button. To add more rows, make an upload (the upload
page in the menu bar) or create a selection on a viewer page.
</p>
);
    $colkeys = [ "checkbox", "title", "coltext", "view", "datatype", 
                 "count", "objtype", "date", "userfile" ];

    $xhtml .= &Submit::Widgets::create_table({
        "session_id" => $sid,
        "menu" => $clip,
        "colkeys" => $colkeys,
    });
    
    # Submit button,

    $xhtml .= &Common::Widgets::spacer( 5 );
    $xhtml .= qq (<p>
<input type="hidden" name="viewer" value="">
<input type="hidden" name="inputdb" value="">
<input type="hidden" name="menu_click" value="">
<input type="submit" name="request" value="Delete selected rows" class="grey_button" />
</p>
);
    $xhtml .= &Common::Widgets::spacer( 15 );
    
    return $xhtml;
}

sub delete_clipboard_rows
{
    # Niels Larsen, November 2005.

    # Deletes items on the clipboard given by their ids. If there are 
    # none left, the menu file(s) are deleted.

    my ( $cgi,         # CGI.pm object
         $sid,         # Session id
         $msgs,        # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a message list or nothing.

    my ( @ids, %ids, $menu, $opt, $path, $file, $dir, @files, 
         $rows_before, @txt, $files_deleted, $rows_deleted,
         $str, $row_msg, $file_msg, $msg );

    if ( @ids = $cgi->param("id") )
    {
        $menu = Common::Menus->clipboard_menu( $sid );
        $files_deleted = 0;

        %ids = map { $_, 1 } @ids;

        # >>>>>>>>>>>>>>>>>>>>>>>>> DELETE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        foreach $opt ( $menu->options )
        {
            if ( $ids{ $opt->id } and $opt->input )
            {
                $path = "$Common::Config::ses_dir/$sid/". $opt->input;
                
                ( $file, $dir ) = &File::Basename::fileparse( $path );
                $dir =~ s|/$||;
                
                @files = &Common::File::list_files( $dir, "^$file" );

                map { &Common::File::delete_file_if_exists( $_->{"path"} ) } @files;
                
                $files_deleted += scalar @files;
            }
        }

        # >>>>>>>>>>>>>>>>>>>> DELETE CLIPBOARD OPTIONS <<<<<<<<<<<<<<<<<<<<<

        $rows_before = $menu->options_count;
        
        $menu->delete_ids( \@ids );

        $rows_deleted = $rows_before - $menu->options_count;

        if ( @{ $menu->options } ) {
            $menu->write( $sid );
        } elsif ( -r "$Common::Config::ses_dir/$sid/".$menu->name ) {
            $menu->delete( $sid );
        }

        # >>>>>>>>>>>>>>>>>>>>>>> DELETE USER MENU OPTIONS 

        # >>>>>>>>>>>>>>>>>>>>>>>>>> MAKE RECEIPT <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( $rows_deleted > 0 ) 
        {
            if ( $rows_deleted > 1 ) {
                $row_msg = qq ($rows_deleted items deleted);
            } else {
                $row_msg = qq (1 item deleted);
            }

            $msg = $row_msg;

            if ( $files_deleted > 0 )
            {
                if ( $files_deleted > 1 ) {
                    $file_msg = qq ($files_deleted files);
                } else {
                    $file_msg = qq (1 file);
                }

                $msg .= qq ( \($file_msg\));
            }

            $msg .= ".";

            push @{ $msgs }, [ "Done", $msg ];
        }
        elsif ( @{ $menu->options } ) 
        {
            push @{ $msgs }, [ "Error", qq (Nothing was deleted from the clipboard.) ];
        }
    }
    else {
        push @{ $msgs }, [ "Error", qq (No rows selected. Please select one (or more) with the checkbox(es).) ];
    }

    return;
}

sub delete_result_rows
{
    # Niels Larsen, April 2008.

    # Deletes result files and everything associated with results: 
    # 
    #   1. Deletes batch queue entries from database
    #   2. Deletes result from user menu
    #   3. Updates job-status to the latest of the remaining jobs
    # 
    # Returns a results menu as it looks after the deletion. 

    my ( $sid,                # Session id
         $job_ids,            # Job ids
         $sys_state,          # System state hash
         $msgs,               # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a menu object. 

    my ( $jobs, @job_ids, $clipboard, $dbh, $job, $job_id );

    # Delete from jobs database, and clipboard maybe,
    
    $jobs = Common::Menus->jobs_menu( $sid );
    
    if ( @{ $jobs->options } )
    {
        if ( @{ $job_ids } )
        {
            # Pull jobs out of batch queue,

            push @{ $msgs }, &Common::Batch::delete_user_jobs( $sid, $job_ids );

            # Delete current job status (set again below),

            &Common::States::delete_job_status( $sid );

            # Get updated job menu,
            
            $jobs = Common::Menus->jobs_menu( $sid );
            
            # Reads and saves shorter version of results menu,

            Submit::Menus->prune_results_menu( $sid, $job_ids );
        }
        else {
            push @{ $msgs }, [ "Error", qq (No rows selected. Please select one (or more) with the checkbox(es).) ];
        }
    }
    
    # Reset job status to that of the newest job,
    
    if ( @{ $jobs->options } )
    {
        $dbh = &Common::DB::connect( $Common::Config::db_master );
        
        $job_id = &Common::Batch::highest_job_id( $dbh, $sid );
        $job = &Common::Batch::get_job( $dbh, $job_id );
        
        &Common::States::save_job_status( $sid, $job->status );
        
        &Common::DB::disconnect( $dbh );
        
        if ( not &Common::Batch::jobs_all_finished( $sid ) ) {
            $sys_state->{"page_refresh"} = 1;
        }
    }
    else {
        &Common::States::delete_job_status( $sid );
        $sys_state->{"with_results"} = 0;
    }
    
    return $jobs;
}

sub handle_downloads
{
    # Niels Larsen, July 2009.

    # Dispatches download requests.

    my ( $ali,
         $cols,
         $rows,
         $state,
         ) = @_;

    # Returns nothing.

    my ( $subali, $form, $key, $menu, $request, $fname );

    $form = &Common::States::make_hash( $state->{"ali_download_keys"},
                                        $state->{"ali_download_values"} );

    delete $state->{"ali_download_keys"};
    delete $state->{"ali_download_values"};

    $menu = Ali::Menus->downloads_menu( $ali->sid )->match_option( "name" => "ali_download_data" )->choices;
    $request = $menu->match_option( "name" => $form->{"ali_download_data"} )->name;

    if ( not $fname = $form->{"ali_download_file"} )
    {
        $fname = $ali->sid;
        $fname .= ".fasta" if $fname !~ /\.fasta$/;
    }

    if ( $request eq "visible_ali" )
    {
        $subali = $ali->subali_get( $cols, $rows, 1, 0 );        

        &Ali::Viewer::download_ali_data( $subali, {
            "download_file" => $fname,
            "with_gaps" => 1,
        }, $state );
    }
    elsif ( $request eq "all_ali" )
    {
        &Ali::Viewer::download_ali_data( $ali, {
            "download_file" => $fname,
            "with_gaps" => 1,
        }, $state );
    }
    elsif ( $request eq "visible_seqs" )
    {
        $subali = $ali->subali_get( $cols, $rows, 1, 0 );        

        &Ali::Viewer::download_ali_data( $subali, {
            "download_file" => $fname,
            "with_gaps" => 0,
        }, $state );
    }
    elsif ( $request eq "all_seqs" )
    {
        &Ali::Viewer::download_ali_data( $ali, {
            "download_file" => $fname,
            "with_gaps" => 0,
        }, $state );
    }
    else {
        push @{ $state->{"ali_messages"} }, 
        [ "Error", qq (Un-implemented request -> "$request") ];
    }
     
    return;
}

sub launch_page
{
    # Niels Larsen, November 2005.
    
    # Shows a version of the clipboard with method and data menus. When a method is 
    # chosen, only data show that is "compatible" with that method. Rows in the table
    # are jobs that can be selected and collectively submitted by pressing the submit
    # button at the bottom of the page. 

    my ( $sid,       # Session id
         $clip,      # Clipboard 
         $proj,
         $msgs,      # Outgoing messages - OPTIONAL
         ) = @_;
    
    # Returns an XHTML string.

    my ( @l_widgets, $xhtml, $colkeys, $count, @rows, $row, $opts, $message,
         $methods, $datasets, @clip_data, $opt, $dat_menu, $data );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Datasets are those defined by the project, plus the user data on the
    # clipboard,

    $dat_menu = Common::Menus->project_data( $proj );

    if ( $clip->options )
    {
        foreach $opt ( $clip->options )
        {
            $data = $opt->dataset;
            
            push @clip_data, Registry::Option->new(
                "owner" => $sid,
                "name" => $data->name,
                "title" => $data->title,
                "label" => $data->coltext,
                "formats" => [ $data->format ],
                "datatype" => $data->datatype,
                "method" => $opt->method || "",
                );
        }
        
        $dat_menu->append_options( \@clip_data );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ADD METHOD MENUS <<<<<<<<<<<<<<<<<<<<<<<<<

    # Attach to each clipboard row method menus that take the given data as
    # input, and menus of data that can work with those menus as databases,

    my $start = [ &Time::HiRes::gettimeofday() ]; 

    $clip = &Submit::Viewer::attach_method_menus( $clip, $proj, $dat_menu );

    my $stop = [ &Time::HiRes::gettimeofday() ]; 
    my $diff = &Time::HiRes::tv_interval( $start, $stop );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ADD DATA MENUS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    {
        $clip = &Submit::Viewer::attach_dataset_menus( $clip, $dat_menu );

    }

    # >>>>>>>>>>>>>>>>>>>>>>>> CHECKBOX DEFAULTS <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set label "with_checkbox" where box method and data have been chosen,

    $count = &Submit::Viewer::set_checkboxes( $clip, $proj );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE XHTML <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Title,

    if ( @{ $clip->options } ) {
        push @l_widgets, &Common::Widgets::title_box( "Launch Analyses", "title_box" );
    } else {
        push @l_widgets, &Common::Widgets::title_box( "Empty", "title_box" );
    }

    $xhtml = &Common::Widgets::spacer( 10 );
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, [] );

    # Messages,

    if ( $msgs and @{ $msgs } ) {
        $xhtml .= &Submit::Widgets::message_box( $msgs );
    }

    # If empty, make message and return,
    
    if ( not @{ $clip->options } )
    {
        $message = qq (There is nothing on the clipboard to submit for analysis.)
                 . qq ( To add items, make a selection)
                 . qq ( from a viewer page, or make an upload.);
        
        $xhtml .= &Submit::Widgets::message_area( $message );
        
        return $xhtml;
    }

    # Main table,
    
    $xhtml .= qq (<p>
This is the page where analyses are started. To start one, select a method,
then a dataset, check one or more boxes, and press the submit button beneath
the table. 
</p>
);
    $colkeys = [ "checkbox", "title", "datatype", "count", "method", "serverdb", "config" ];

    $xhtml .= &Submit::Widgets::create_table({
        "session_id" => $sid,
        "menu" => $clip,
        "colkeys" => $colkeys,
    });
    
    # Submit button,
    
    $xhtml .= &Common::Widgets::spacer( 5 );

    $xhtml .= qq (<p>\n);
    $xhtml .= qq (<input type="hidden" name="page" value="show_launch_page">\n);
    
    if ( $count > 0 ) {
        $xhtml .= qq (<input type="submit" name="request" value="Submit selected rows" class="grey_button" />\n);
    } else {
        $xhtml .= qq (<input type="button" value="Nothing to submit" class="grey_button" />\n);
    }
    $xhtml .= qq (</p>\n);

    $xhtml .= &Common::Widgets::spacer( 15 );

    return $xhtml;
}

sub main
{
    # Niels Larsen, November 2005.

    # Dispatches clipboard related requests and produces xthml. Routine names 
    # that end with "_page" generates xhtml for a given type of page, the rest 
    # respond to other requests. Every click and request goes through this 
    # routine.

    my ( $args,
         $msgs,
         ) = @_;

    # Returns an xhtml string.

    my ( $cgi, $sid, $state, $sys_state, $proj, $cliprow, @job_ids,
         $xhtml, $datatype, $request, $upload, @errors, $clipboard, $method,
         $params, $jobs, $err_file, $job_id, $error, @ids, $dbh, $job, @msgs,
         $is_idle, $form );

#     $args = &Registry::Args::check(
#         $args,
#         {
#             "HR:1" => [ qw ( viewer_state sys_state ) ],
#             "O:1" => [ qw ( cgi project ) ],
#         });

    $cgi = $args->{"cgi"};
    $state = $args->{"viewer_state"};
    $sys_state = $args->{"sys_state"};
    $proj = $args->{"project"};

    $state->{"inputdb"} = $sys_state->{"inputdb"};

#    &dump( $proj );
#   &dump( $sys_state );
#    &dump( $state );

    $msgs ||= [];       

    $request = $state->{"request"};
    $sid = $sys_state->{"session_id"};

    # Set multipart-form on or off,

    if ( $request =~ /^upload/ ) {
        $sys_state->{"multipart_form"} = 1;
    } else {
        $sys_state->{"multipart_form"} = 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Issue warning if batch queue not running,

    if ( not &Common::Batch::queue_is_running() )
    {
        push @{ $msgs }, [ "Warning", qq (The batch queue is not running. Please)
                                    . qq ( contact the site administrator.) ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    #
    #                           DISPATCH REQUESTS 
    # 
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $request eq "show_error_message" )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>> ERROR PANEL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # This is a dead end that shows the page and exits. It is used with 
        # popup windows that appear when an icon is clicked after some job
        # has gone wrong,
        
        $sys_state->{"is_popup_page"} = 1;
        $sys_state->{"title"} = "Batch Job Error Message";

        $job_id = $cgi->param("job_id");
        $err_file = "$Common::Config::ses_dir/$sid/Analyses/$job_id.messages";
        $error = &Common::File::eval_file( $err_file )->{"stdout"};

        $xhtml = &Common::Messages::system_error_for_browser_css( $error );

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj,
            });

        exit 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HELP POPUPS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request =~ /help/ )
    {
        require Submit::Help;
        $xhtml = &Submit::Help::pager( $request );
        
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

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UPLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request =~ /^upload/ )
    {
        # If upload request, then do that, and then show the upload page,

        if ( $request eq "upload" )
        {
            &Submit::Viewer::upload_data( $cgi, $sid, $proj, $msgs );
        }
        
        $xhtml = &Submit::Viewer::upload_page( $sid, $state, $proj, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLIPBOARD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request eq "show_clipboard_page" )
    {
        # Clipboard page,

        $xhtml = &Submit::Viewer::clipboard_page( $sid, $msgs );
    }
    elsif ( $request eq "Delete selected rows" )
    {
        # Clipboard deletion,

        &Submit::Viewer::delete_clipboard_rows( $cgi, $sid, $msgs );

        $xhtml = &Submit::Viewer::clipboard_page( $sid, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> JOB LAUNCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request eq "show_launch_page" )
    {
        # Launch page,

        $clipboard = Common::Menus->clipboard_menu( $sid );
        $clipboard = &Submit::Viewer::set_cgi_values( $cgi, $clipboard );

        if ( $clipboard->options_count > 0 ) {
            $clipboard->write( $sid );
        }

        $xhtml = &Submit::Viewer::launch_page( $sid, $clipboard, $proj, $msgs );
    }
    elsif ( $request eq "Submit selected rows" )
    {
        # Submit new job(s). 

        $clipboard = Common::Menus->clipboard_menu( $sid );
        $clipboard = &Submit::Viewer::set_cgi_values( $cgi, $clipboard );

        $clipboard->write( $sid ) if $clipboard->options_count > 0;

        $is_idle = &Common::Batch::jobs_all_finished();
        @msgs = &Submit::Batch::submit_jobs( $clipboard, $proj );

        push @{ $msgs }, @msgs;

        @errors = grep { $_->[0] =~ /Error/i } @msgs;

        if ( not @errors )
        {
            if ( $is_idle ) {
                &Common::States::save_job_status( $sid, "running" );
            }

            $sys_state->{"with_results"} = 1;
        }

        $xhtml = &Submit::Viewer::launch_page( $sid, $clipboard, $proj, $msgs );
        $state = &Submit::Viewer::clear_user_input( $sid, $state );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request eq "show_params_page" )
    {
        # Parameters page, a popup page,

        $clipboard = Common::Menus->clipboard_menu( $sid );
        $cliprow = $clipboard->match_option( "id" => $state->{"clipboard_id"} );

        $method = &Submit::State::restore_method( $sid, $state->{"clipboard_method"}, $cliprow );
        
#         &dump( $sid );
#         &dump( $proj->projpath );
#         &dump( $method );
#         &dump( $cliprow->id );
#         &dump( $cliprow->datatype );

        $xhtml = &Submit::Widgets::params_panel(
            {
                "session_id" => $sid,
                "uri_path" => $proj->projpath,
                "method" => $method,
                "clipboard_id" => $cliprow->id,
                "datatype" => $cliprow->datatype,
            }, $msgs );
        
        $sys_state->{"is_popup_page"} = 1;

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj,
            });
        
        exit;
    }
    elsif ( $request eq "Save" )
    {
        # Sets a parameter hash in a particular clipboard row,

        &Submit::Viewer::save_params( $sid, $state, $msgs );

        $clipboard = Common::Menus->clipboard_menu( $sid );
        $xhtml = &Submit::Viewer::launch_page( $sid, $clipboard, $proj, $msgs );

        $state = &Submit::Viewer::clear_user_input( $sid, $state );
    }
    elsif ( $request eq "Save as default" )
    {
        # Sets parameters from the parameter popup panel, 

        &Submit::Viewer::save_params_default( $sid, $state, $msgs );

        $clipboard = Common::Menus->clipboard_menu( $sid );
        $xhtml = &Submit::Viewer::launch_page( $sid, $clipboard, $proj, $msgs );

        $state = &Submit::Viewer::clear_user_input( $sid, $state );
    }
    elsif ( $request eq "Reset" )
    {
        # Shows parameters page with defaults,

        $method = Registry::Get->method_max( $state->{"clipboard_method"} );

        $clipboard = Common::Menus->clipboard_menu( $sid );
        $cliprow = $clipboard->match_option( "id" => $state->{"clipboard_id"} );

        $xhtml = &Submit::Widgets::params_panel(
            {
                "session_id" => $sid,
                "method" => $method,
                "clipboard_id" => $cliprow->id,
                "datatype" => $cliprow->datatype,
            }, $msgs );
        
        $sys_state->{"is_popup_page"} = 1;

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj,
            });

        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> JOB RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $request eq "show_results_page" )
    {
        # Results page,

        $jobs = Common::Menus->jobs_menu( $sid );

        if ( $jobs->options )
        {
            $xhtml = &Submit::Viewer::results_page( $sid, $jobs, $proj, $msgs );

            if ( not &Common::Batch::jobs_all_finished( $sid ) ) {
                $sys_state->{"page_refresh"} = 1;
            }
        }
        else {
            $sys_state->{"with_results"} = 0;
        }
    }
    elsif ( $request eq "Delete selected results" )
    {
        @job_ids = $cgi->param("id");
        $jobs = &Submit::Viewer::delete_result_rows( $sid, \@job_ids, $sys_state, $msgs );

        $xhtml = &Submit::Viewer::results_page( $sid, $jobs, $proj, $msgs );

        &Submit::Viewer::clear_user_input( $sid, $state );
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ERROR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    else {
        &error( qq (Wrong looking request -> "$request") );
    }

    return $xhtml;
}

sub read_form_fields
{
    # Niels Larsen, October 2008.

    # Checks form fields .. 

    my ( $cgi,
         $sid,
         $msgs,
        ) = @_;

    # Returns a hash.

    my ( $val, $upload, $up_fh );

    if ( not ref $msgs ) {
        &error( qq (Cannot return messages) );
    }

    $upload = {};

    # Datatype,

    $val = $cgi->param('upload_datatype');

    if ( $val )
    {
        if ( $val =~ /^\d+$/ ) {
            $upload->{"datatype"} = Common::Menus->datatype_menu( $sid )->match_option( "id" => $val )->name;
        } else {
            &error( qq (Wrong looking datatype id -> "$val") );
        }            
    }
    else {
        push @{ $msgs }, [ "Error", qq (Missing data type (<strong>step 1</strong>).) ];
    }

    # Format,

    $val = $cgi->param('upload_format');

    if ( $val )
    {
        if ( $val =~ /^\d+$/ ) {
            $upload->{"format"} = Common::Menus->formats_menu( $sid )->match_option( "id" => $val )->name;
        } else {
            &error( qq (Wrong looking format id -> "$val") );
        }
    }
    else {
        push @{ $msgs }, [ "Error", qq (Missing data format (<strong>step 1</strong>).) ];
    }
    
#         # Then "virtual" formats: the union of the formats of the methods
#         # that accepts the actual format as input. Setting these makes 
#         # filtering according to methods possible, and the formats will 
#         # then by done at submit-time, not here at upload-time.

#         $menu = Common::Menus->project_methods( $proj );
#         $menu->match_options( "itypes" => $upload->{"datatype"} );

#         foreach $option ( @{ $menu->options } )
#         {
#             push @formats, $option->{"dbformat"};
#         }

#         @formats = &Common::Util::uniqify( \@formats );

#         $upload->formats( \@formats );


    # File path,

    $up_fh = $cgi->upload('upload_file');

    if ( $up_fh )
    {
        $upload->{"user_file_name"} = "$up_fh";
        $upload->{"user_file_handle"} = $up_fh;
    }
    else
    {
        if ( $up_fh = $cgi->param('upload_file') ) {
            push @{ $msgs }, [ "Error", qq (File not found -&gt; "$up_fh" (<strong>step 2</strong>).) ];
        } else {
            push @{ $msgs }, [ "Error", qq (Missing upload file (<strong>step 2</strong>).) ];
        }
    }
    
    # Menu title,

    $val = $cgi->param('upload_title');

    if ( $val ) {
        $upload->{"title"} = $val;
    } else {
        push @{ $msgs }, [ "Error", qq (Missing menu title (<strong>step 3</strong>).) ];
    }

    # Abbreviated title,

    $val = $cgi->param('upload_coltext');

    if ( $val ) {
        $upload->{"coltext"} = $val;
    } else {
        push @{ $msgs }, [ "Error", qq (Missing column header abbreviation (<strong>step 3</strong>).) ];
    }

    if ( @{ $msgs } )
    {
        if ( $up_fh ) {
            push @{ $msgs }, [ "Info", qq (It is unfortunately impossible to fill the previous)
                                     . qq ( upload file path, please enter it again (<strong>step 2</strong>).) ];
        }
    }

    return $upload;
}   
    
sub results_page
{
    # Niels Larsen, December 2005.
    
    # Builds a page that shows present and past batch jobs for a given user. A
    # delete button and checkboxes offers deletion of completed as well as running
    # jobs. 

    my ( $sid,       # Session id
         $jobs,      # Jobs menu structure
         $proj,
         $msgs,      # Message list - OPTIONAL
         ) = @_;
    
    # Returns an XHTML string.

    my ( $xhtml, @l_widgets, $colkeys, $count, @ids, $msg, $row );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $jobs->options } ) {
        push @l_widgets, &Common::Widgets::title_box( "Results", "title_box" );
    } else {
        push @l_widgets, &Common::Widgets::title_box( "Empty", "title_box" );
    }

    $xhtml = &Common::Widgets::spacer( 10 );
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, [] );

    # >>>>>>>>>>>>>>>>>>>>>> INFORMATIONAL MESSAGES <<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Batch::jobs_pending( $sid ) and 
         @ids = &Common::Batch::jobs_ahead( $sid ) )
    {
        $count = scalar @ids;

        if ( $count > 1 ) {
            $msg = qq (There are $count jobs ahead in the queue.);
        } else {
            $msg = qq (There is 1 job ahead in the queue.);
        }

        push @{ $msgs }, [ "Info", $msg ];
    }

    if ( $msgs and @{ $msgs } ) {
        $xhtml .= &Submit::Widgets::message_box( $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>> RETURN IF NO JOBS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( not @{ $jobs->options } )
    {
        $msg = qq (No jobs. To launch analyses: make a selection)
             . qq ( from a viewer page, or make an upload, and then go the)
             . qq ( User -&gt; Analyze page.);

        $xhtml .= &Submit::Widgets::message_area( $msg );

        return $xhtml;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Attach result menus,
    
    foreach $row ( $jobs->options )
    {
        $row->results_menu( Submit::Menus->job_results( $sid, $row->id ) );
    }

    map { $_->label("with_checkbox") } $jobs->options;

    # Create table,

    $xhtml .= qq (<p>
Below is a list of background jobs, with status pending, running, aborted or 
completed. When jobs are finished pulldown menus appear, where results can 
be selected. Jobs are submitted from the Launch page (menu bar above).
</p>
);
    $colkeys = [ "checkbox", "status", "title", "results", "method", 
                 "serverdb", "run_time", "id", "sub_time", "message" ];
    
    $jobs->options( [ reverse @{ $jobs->options } ] );

    $xhtml .= &Submit::Widgets::create_table({
        "session_id" => $sid,
        "menu" => $jobs,
        "colkeys" => $colkeys,
    });
    
    # Delete button,
    
    $xhtml .= &Common::Widgets::spacer( 5 );
    $xhtml .= qq (<p>
<input type="hidden" name="page" value="show_results_page">
<input type="hidden" name="viewer" value="">
<input type="hidden" name="inputdb" value="">
<input type="hidden" name="menu_click" value="">
<input type="submit" name="request" value="Delete selected results" class="grey_button" />
</p>
);
    $xhtml .= &Common::Widgets::spacer( 15 );

    return $xhtml;
}

sub save_params
{
    # Niels Larsen, April 2007.

    # Takes a list of parameters in the state (under key "clipboard_params") and
    # puts it in a file of defaults (methods.params) in the user home directory. 

    my ( $sid,              # Session id
         $state,            # State hash
         $msgs,             # Outgoing messages - OPTIONAL
         ) = @_;
    
    # Returns nothing.

    my ( $method, $hash, %params, $menu, $opt, $msg, $title );

    $hash = &Common::States::make_hash( $state->{"clip_params_keys"},
                                        $state->{"clip_params_values"} );

    delete $state->{"clip_params_keys"};
    delete $state->{"clip_params_values"};

    # Validate parameters against data types,

    $method = $state->{"clipboard_method"};

    if ( &Submit::Viewer::valid_params( $hash, $method, $msgs ) )
    {
        $menu = Common::Menus->clipboard_menu( $sid );
    
        $opt = $menu->match_option( "id" => $state->{"clipboard_id"} );
        $opt->params( $hash );
        
        $menu->write( $sid );
        
        $title = $opt->title;
        $msg = qq (Parameters saved. They will be used every time $method is run on "$title".);
        
        push @{ $msgs }, [ "Done", $msg ];
    }

    return;
}

sub save_params_default
{
    # Niels Larsen, April 2007.

    # Takes a list of parameters in the state (under key "clipboard_params") and
    # puts it in a file of defaults (methods.params) in the user home directory. 

    my ( $sid,              # Session id
         $state,            # State hash
         $msgs,             # Outgoing messages - OPTIONAL
         ) = @_;
    
    # Returns nothing.

    my ( $method, $hash, $msg );

    $hash = &Common::States::make_hash( $state->{"clip_params_keys"},
                                        $state->{"clip_params_values"} );

    delete $state->{"clip_params_keys"};
    delete $state->{"clip_params_values"};

    $method = $state->{"clipboard_method"};

    &Submit::State::save_method_params( $method, "$sid/Methods", $hash );

    $msg = qq (Default $method parameters saved. They will be used in $method )
         . qq (analyses from now on, but values are not checked until the methods are run.);

    push @{ $msgs }, [ "Done", $msg ];

    return;
}

sub set_cgi_values
{
    # Niels Larsen, November 2005.

    # Captures cgi parameters "id", "methods_menu_$id" and "searchdbs_menu_$id" and 
    # sets "selected", "method" and "serverdb" in the corresponding table row.

    my ( $cgi,       # CGI.pm object
         $clip,      # Clipboard
         ) = @_;

    # Returns a menu object. 
    
    my ( %ids, $method, $params, $id, $serverdb, $site_dir, $opt,
         $values );

    # Read all available methods and databases from file,

    %ids = map { $_, 1 } $cgi->param("id");

    foreach $opt ( $clip->options )
    {
        $id = $opt->id;

        # Set request and selected option for checkboxes,

        if ( $ids{ $id } ) {
            $opt->selected( 1 );
        } else {
            $opt->selected( 0 );
        }            
        
        # Set method,

        if ( $method = $cgi->param("methods_menu_$id") )
        {
            $opt->method( $method );
            $opt->serverdb("");
        }

        # Set dataset,

        if ( $serverdb = $cgi->param("searchdbs_menu_$id") )
        {
            $opt->serverdb( $serverdb );
        }
    }

    return $clip;
}

sub params_to_tuples
{
    my ( $keys,
         $vals,
        ) = @_;

    my ( $i, $j, @tuples );

    if ( ( $i = scalar @{ $keys } ) != ( $j = scalar @{ $vals } ) ) {
        &error( qq ($i keys, but $j values) );
    }

    for ( $i = 0; $i <= $#{ $vals }; $i++ )
    {
        push @tuples, [ $keys->[$i], $vals->[$i] ];
    }

    return wantarray ? @tuples : \@tuples;
}

sub set_checkboxes
{
    # Niels Larsen, October 2008.

    # Labels the rows with "with_checkbox" where both method and dataset
    # has been set. 

    my ( $clip,     # Clipboard menu
        ) = @_;

    # Returns an integer. 

    my ( $count, $row ); 

    $count = 0;

    foreach $row ( $clip->options ) 
    {
        if ( $row->method and $row->dataset )
        {
            $row->label("with_checkbox");
            $count += 1;
        }
        else {
            $row->label("");
        }
    }            
    
    return $count;
}    

sub upload_data
{
    # Niels Larsen, October 2008.

    # Uploads submissions. A single file is uploaded, imported, and success or 
    # failure messages generated. 
    
    my ( $cgi, 
         $sid, 
         $proj, 
         $msgs,
        ) = @_;

    my ( $datatype, $clipboard, $args, @msgs, $up_file, $title, $timestr, 
         $count, $out_dir, $path, $info, $dataset, $id, @titles, $upload,
         $count_str, $userfile, $str, $msg, $errmsg, $typmsg, $out_file,
         $type );

    if ( not ref $msgs eq "ARRAY" ) {
        &error( qq (Message array not given) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ FORM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @msgs = ();
    $args = &Submit::Viewer::read_form_fields( $cgi, $sid, \@msgs );

    if ( @msgs ) 
    {
        push @{ $msgs }, @msgs;
        return;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DO UPLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a temporary file in the session area with exact content of 
    # file from client machine,

    $timestr = &Common::Util::epoch_to_time_string();
    
    $args->{"out_file_name"} = "$timestr.upload";
    $args->{"out_file_path"} = "$Common::Config::ses_dir/$sid/". $args->{"out_file_name"};

    @msgs = ();
    $count = &Submit::Upload::upload_file( $sid, $args, \@msgs );

    if ( @msgs ) 
    {
        push @{ $msgs }, @msgs;
        return;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>> CHECK FILE TYPE <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check the the file is a regular text file. If it is a MS-Word or 
    # something, then error message(s) is returned,

    $out_file = $args->{"out_file_path"};
    $type = &Common::File::get_type( $out_file );

    $errmsg = qq (Undefined type for upload file -&gt; "$out_file".);

    $typmsg = qq (The upload appears to be of the type "$type". We can)
        . qq ( only take plain-text (ascii) files at this moment, so please)
        . qq ( try create one, in FASTA format.)
        . qq ( <u>Note</u>: a Microsoft-Word file will not work - it is "binary")
        . qq ( and its format <u>secret</u>, which means unreadable except by)
        . qq ( Microsoft and its programs.);

    @msgs = &Common::File::check_file_ascii( $out_file, $errmsg, $typmsg );
    
    if ( @msgs )
    {
        push @{ $msgs }, @msgs;
        &Common::File::delete_file( $args->{"out_file_path"} );
        
        return;
    }

    # >>>>>>>>>>>>>>>>>>>>>> CHECK DUPLICATE TITLES <<<<<<<<<<<<<<<<<<<<<

    # An upload may have a previously used name, by mistake or when the 
    # reload button is pressed, 

    $clipboard = Common::Menus->clipboard_menu( $sid );

    $title = $args->{"title"};
    @titles = map { $_->dataset->title } @{ $clipboard->options };

    if ( grep { $_ =~ /^$title$/ } @titles )
    {
        push @{ $msgs }, [ "Error", qq (The title "$title" has already been used,)
                          . qq ( or perhaps the previous form content was unintentionally)
                          . qq ( re-submitted. Please fill a different name into the form.) ];

        push @{ $msgs }, [ "Info", qq (It is unfortunately impossible to fill in your previous)
                                 . qq ( file path, please enter it again.) ];

        return;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> IMPORT DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Uploaded data now becomes input for processing,

    $args->{"in_file_name"} = $args->{"out_file_name"};
    $args->{"in_file_path"} = $args->{"out_file_path"};

    # Define final places for the data, organised by datatype and date,

    $datatype = $args->{"datatype"};
    $path = Registry::Get->type( $datatype )->path;

    $args->{"out_file_name"} = $timestr;
    $args->{"out_file_path"} = qq ($Common::Config::ses_dir/$sid/Uploads/$path/$timestr);
    $args->{"out_table_dir"} = qq ($Common::Config::ses_dir/$sid/Uploads/$path/Database_tables);

    # Create directory if missing,

    $out_dir = &File::Basename::dirname( $args->{"out_file_path"} );
    &Common::File::create_dir_if_not_exists( $out_dir );

    # Import data and make status messages: load the data in whatever ways apply to 
    # the different types, and return an info hash with keys "success" (1 or 0) and
    # "count" (number of entries) and "count_str" (number of entries text string).
    # These routines should only do datatype specific things, everything else should 
    # be done in here,

    $args->{"source"} = "Upload";

    $Common::Messages::silent = 1;

    if ( &Common::Types::is_alignment( $datatype ) )
    {
        $info = &Submit::Upload::process_ali( $sid, $args, $msgs );
    }
    elsif ( &Common::Types::is_sequence( $datatype ) )
    {
        $info = &Submit::Upload::process_seqs( $sid, $args, $msgs );
    }
    elsif ( &Common::Types::is_pattern( $datatype ) )
    {
        $info = &Submit::Upload::process_pat( $sid, $args, $msgs );
    }
    else {
        &error( qq (Wrong looking datatype -> "$datatype") );
    }

    &Common::File::delete_file_if_exists( $args->{"in_file_path"} );

    if ( $info->{"success"} )
    {
        $userfile = $args->{"user_file_name"};

        if ( $str = $info->{"count_str"} ) {
            $msg = qq (Uploaded "$userfile" \($str\) to the clipboard);
        } else {
            $msg = qq (Uploaded "$userfile" to the clipboard);
        }

        push @{ $msgs }, [ "Success", qq ($msg. It is )
                         . qq ( also visible in the user menu on the viewer pages.) ];
    }
    else {
        return;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FORM DATASET <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create registry dataset object that can be matched against others 
    # later with the routines in Registry::Match,

    $id = ( $clipboard->max_option_id || 0 ) + 1;

    $dataset = bless
    {
        "owner" => $proj->name,
        "name" => &Common::Names::format_dataset_str( $sid, "clipboard", $id ),
        "datatype" => $datatype,
        "format" => $args->{"format"},
        "title" => $args->{"title"},
        "coltext" => $args->{"coltext"},
    },
    "Registry::Option";

    # >>>>>>>>>>>>>>>>>>>> APPEND TO CLIPBOARD AND SAVE <<<<<<<<<<<<<<<<<<<

    $upload->{"count"} = $info->{"count"};
    $upload->{"date"} = $timestr;
    $upload->{"input"} = "Uploads/$path/$timestr";
    $upload->{"id"} = $id;
    $upload->{"dataset"} = $dataset;
    $upload->{"userfile"} = $userfile;
    $upload->{"objtype"} = "upload";
    
    bless $upload, "Registry::Option";

    $clipboard->append_option( $upload );
    $clipboard->write( $sid );

    return;
}
    
sub upload_page
{
    # Niels Larsen, December 2006.

    # Creates an upload form page for a given upload object and a given arguments
    # hash. It is an internal routine used by upload_seq_page in this module, just
    # to reduce code duplication. If an upload object is given, then its values are
    # used to fill default values into the form fields. If not, the state is used. 

    my ( $sid,         # Session id
         $state,       # Arguments hash
         $proj,        # Project object
         $msgs,        # Message list - OPTIONAL
         ) = @_;

    # Returns XHTML

    my ( $dbs, $page_title, $butext, $request, $xhtml, $file_xhtml, $formats, 
         $title, $menu_xhtml, @l_widgets, @r_widgets, $formats_menu, $formats_xhtml, 
         $types_menu, $types_xhtml, $option, $col_xhtml, $types, $submit_label,
         $id, @hidden, $str );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE DATATYPES MENU <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Make list of the datatypes that the current projects data have,

    $types = Registry::Get->supported_input_types();
    $types = [ grep { $_ !~ /go_func|orgs_taxa/ } @{ $types } ];

    $types_menu = Registry::Get->types( $types );

    $types_menu->name( "upload_datatype" );
    $types_menu->title( "&nbsp;" );
    $types_menu->css("beige_menu");
    $types_menu->onchange( "javascript:handle_menu(this.form.upload_datatype,'upload_page')" );

    if ( $state->{"upload_datatype"} )
    {
        $option = $types_menu->match_option( "id" => $state->{"upload_datatype"} );

        if ( $option )
        {
            $types_menu->selected( $option->id );
            
            $state->{"upload_page_title"} = $option->title;
            $state->{"upload_submit_label"} = $option->title;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE FORMATS MENU <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $state->{"upload_datatype"} and $option ) {
        $formats = $option->formats;
    } else {
        $formats = $types_menu->get_option_values( "formats" );
    }

    $formats_menu = Registry::Get->formats( $formats );

    if ( $formats_menu->options_count > 1 )
    {
        $formats_menu->name( "upload_format" );
        $formats_menu->title( "&nbsp;" );
        $formats_menu->css("beige_menu");
        $formats_menu->onchange( "javascript:handle_menu(this.form.upload_format,'upload_page')" );
        
        if ( $state->{"upload_format"} )
        {
            $option = $formats_menu->match_option( "id" => $state->{"upload_format"} );
            $formats_menu->selected( $option->id ) if $option;
        }

        $formats_xhtml = &Common::Widgets::pulldown_menu( $formats_menu, { "close_button" => 0 } );
    }
    elsif ( $formats_menu->options_count == 1 )
    {
        $option = $formats_menu->options->[0];

        $id = $option->id;
        $title = $option->title;

        $formats_xhtml = qq (<table cellpadding="0" cellspacing="0"><tr>)
                       . qq (<td class="single_cell">$title</td></tr></table>);

        push @hidden, qq (<input type="hidden" name="upload_format" value="$id">\n);
    }
    else {
        $str = join ",", @{ $formats };
        &error( qq (Wrong looking formats -> "$str") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE XHTML <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Title box in its own row,

    if ( $state->{"upload_page_title"} ) {
        $page_title = "Upload $state->{'upload_page_title'}";
    } else {
        $page_title = "Upload";
    }

    push @l_widgets, &Common::Widgets::title_box( $page_title, "title_box" );

    $xhtml = &Common::Widgets::spacer( 10 );
    $xhtml .= &Common::Widgets::title_area( \@l_widgets, \@r_widgets );

    # Messages if any,

    if ( $msgs and @{ $msgs } ) {
        $xhtml .= &Submit::Widgets::message_box( $msgs );
    }

    # Widget xhtml (inserted below),

    $file_xhtml = &Submit::Widgets::upload_field( "upload_file", $state->{ "upload_file"}, 60, 200 );
    $menu_xhtml = &Common::Widgets::text_field( "upload_title", $state->{ "upload_title"}, 20, 20 );
    $col_xhtml = &Common::Widgets::text_field( "upload_coltext", $state->{ "upload_coltext"}, 4, 4 );
    
    $types_xhtml = &Common::Widgets::pulldown_menu( $types_menu, { "close_button" => 0 } );

    push @hidden, qq (<input type="hidden" value="upload" name="request" />\n);
    push @hidden, qq (<input type="submit" value="Start upload" name="form" class="grey_button" />\n);

    # Page text,

    $xhtml .= qq (
<p>
The steps below uploads data to a private clipboard area, where noone
else can look, and where analyses can be launched. Everything will stay until next 
login or, if not logged in, disappear forever.
</p>
<h4>1. Choose upload type and format</h4>

<table cellpadding="3" cellspacing="0">
<tr><td>$types_xhtml</td><td>$formats_xhtml</td></tr>
</table>

<h4>2. Find the upload file</h4>
<p>
Please select a data file from your machine. Plain Linux/Unix, Mac and 
MS-Windows text files should work, but MS-word files that only Microsoft
itself is able to read, as well as other secret proprietary binary formats,
will of course not work. Text-only exports from MS-Word may work.
</p>

<table cellpadding="0" cellspacing="3">
<tr><td>&nbsp;$file_xhtml&nbsp;</td></tr>
</table>

<h4>3. Name the upload</h4>
<p>
The system can uploads in menus and summary columns. For these purposes, 
please enter below a menu title for pull-down menus, and a short column
title - they can be chosen freely within the length limit.
</p>

<table cellpadding="0" cellspacing="3">
<tr><td align="right">Menu title</td><td>&raquo;</td><td>&nbsp;$menu_xhtml&nbsp;</td><td>(Max. 20 characters)</td></tr>
<tr><td align="right">Column title</td><td>&raquo;</td><td>&nbsp;$col_xhtml&nbsp;</td><td>(Max. 4 characters)</td></tr>
</table>

<h4>4. Press the button</h4>
<p>
@hidden
</p>

);

    $xhtml .= &Common::Widgets::spacer( 15 );

    return $xhtml;
}

sub valid_params
{
    # Niels Larsen, October 2007.

    # Checks the given argument key/values from the form against the types
    # they should have. If something wrong, the function returns false and 
    # with error messages appended to the given list; and if nothing wrong
    # it returns true. 

    my ( $hash,            # Hash with key/values like "-r"/ "0" 
         $method,          # Method name from registry like "blastn"
         $msgs,            # List of messages - OPTIONAL
        ) = @_;

    # Returns 1 or nothing.

    my ( %lookup, $opt, $param, $name, $value, $title, @msgs, $type );

    $method = Registry::Get->method_max( $method );

    foreach $type ( "pre_params", "params", "post_params" )
    {
        if ( $method->$type )
        {
            foreach $opt ( @{ $method->$type->values->options } )
            {
                $lookup{ $opt->name } = $opt;
            }
        }
    }
            
    foreach $name ( keys %{ $hash } )
    {
        $value = $hash->{ $name };

        if ( $param = $lookup{ $name } and $param->selectable )
        {
            $value =~ s/^ +//;
            $value =~ s/ +$//;

            $title = $param->title;

            if ( $param->datatype eq "integer" )
            {
                $value ||= 0;

                if ( $value =~ /^-?[0-9]+$/ ) {
                    $hash->{ $name } = $value;
                } else {
                    push @msgs, [ "Error", qq (Wrong looking "$title" field -> "$value", must be integer.) ];
                }
            }
            elsif ( $param->datatype eq "real" )
            {
                $value ||= 0.0;

                if ( $value =~ /^[0-9]+\.?[0-9]*$/ ) {
                    $hash->{ $name } = $value;
                } else {
                    push @msgs, [ "Error", qq (Wrong looking "$title" field -> "$value", must be a number.) ];
                }
            }
        }
        else {
            &error( qq (Wrong looking parameter name -> "$name") );
        }
    }

    if ( @msgs )
    {
        push @{ $msgs }, @msgs;
        return;
    }
    else {
        return 1;
    }
}   

1;

__END__

# sub attach_dataset_menus_old
# {
#     # Niels Larsen, November 2007.

#     # Assumes a method has been set, by the attach_method_menus routine. For each 
#     # row a menu is created with datasets that are compatible with the set method 
#     # and the clipboard dataset of that given row. If no compatible datasets found
#     # no menu is attached. 

#     my ( $clip,      # Clipboard object
#          $data,
#          $meths,
#         ) = @_;

#     # Returns a menu object.

#     my ( @meth_ids, @type_ids, @format_ids, $method, @match_opts, $row_id,
#          $row_menu, $row, $opt, %methods, $selected, $serverdb, %filter );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> SIMPLIFY DATA CHOICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     # Set ids to strings of the formst "serverdb:entry:type". These are sent
#     # by the pulldown menu and tells the server which data is wanted,
            
#     @match_opts = ();

#     foreach $opt ( @{ $data->options } )
#     {
#         if ( defined $opt->cid ) {
#             $serverdb = &Common::Names::format_dataset_str( $opt->dbname, $opt->cid, $opt->datatype );
#         } else {
#             $serverdb = &Common::Names::format_dataset_str( $opt->dbname, $opt->name, $opt->datatype );
#         }
            
#         push @match_opts, Common::Option->new(
#             "id" => $serverdb,
#             "title" => $opt->title,
#             "formats" => $opt->formats,
#             "datatype" => $opt->datatype,
#             );
#     }

#     exit;

#     $data->options( &Storable::dclone( \@match_opts ) );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER AND ATTACH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     %methods = map { $_->name, $_ } @{ $meths->options };

#     foreach $row ( $clip->options ) 
#     {
#         if ( not defined ( $method = $methods{ $row->method } ) ) {
#             next;
#         }

#         # Set filter. Most comparison methods, blast for example, take a query input set
#         # and a database set. Here we see if the row data matches the input type and format, 
#         # or it matches the database type and format, and then we set the filter to get 
#         # the "missing" part. 

#         %filter = ();

#         if ( $row->matches( "datatype" => $method->itypes ) )
#         {
#             push @{ $filter{"formats"} }, $method->dbformat if $method->dbformat;
#             push @{ $filter{"datatype"} }, @{ $method->dbitypes } if $method->dbitypes;
#         }
#         elsif ( $row->matches( "datatype" => $method->dbitypes ) )
#         {
#             push @{ $filter{"formats"} }, $method->iformat if $method->iformat;
#             push @{ $filter{"datatype"} }, @{ $method->itypes } if $method->itypes;
#         }

#         if ( %filter )
#         {
#             @match_opts = $data->match_options( %filter );
#             @match_opts = grep { $_->id !~ $row->id } @match_opts;
#         }
#         else {
#             @match_opts = ();
#         }

#         # If compatible datasets found, create pulldown menu. If no data is set for this 
#         # row, set it to the first of the choices in the menu,

#         if ( @match_opts )
#         {
#             $row_menu = Common::Menu->new( "name" => $data->name ."_". $row->id,
#                                            "options" => \@match_opts,
#                                            "style" => $data->style );

#             if ( $row->serverdb and 
#                  $opt = $row_menu->match_option( "id" => $row->serverdb ) )
#             {
#                 $selected = $opt->id;
#             } else {
#                 $selected = $match_opts[0]->id;
#             }

#             $row_menu->selected( $selected );
#             $row->serverdb( $selected );
            
#             $row->serverdbs( &Storable::dclone( $row_menu ) );
#         }
#         else {
#             $row->serverdbs( undef );
#         }
#     }
    
#     return $clip;
# }

# sub reduce_data_by_methods
# {
#     # Niels Larsen, September 2007. 

#     # Removes datasets from the given menu that do not work with any of the given 
#     # methods, ie where datatypes and formats do not overlap. A new dataset menu 
#     # is returned. 

#     my ( $dbs,            # Data menu
#          $meths,          # Methods menu or list of ids
#         ) = @_;

#     # Returns a menu.

#     my ( $db, %filter, @meths, @dbs );

#     if ( ref $meths )
#     {
#         if ( ref $meths eq "ARRAY" ) {
#             $meths = Registry::Get->methods( $meths );
#         }
#     }
#     else {
#         &error( qq (Methods must be given, either as a list of ids or a menu) );
#     }

#     foreach $db ( @{ $dbs->options } )
#     {
#         %filter = ( "dbformat" => $db->formats, "dbitypes" => [ $db->datatype ] );

#         if ( @meths = $meths->match_options( %filter ) )
#         {
#             push @dbs, $db;
#         }
#     }

#     if ( @dbs ) {
#         $dbs->options( \@dbs );
#     } else {
#         &error( qq (Method-shrinking created empty data menu) );
#     }
    
#     return $dbs;
# }

# sub reduce_methods_by_data
# {
#     # Niels Larsen, September 2007. 

#     # Removes methods from the given menu that do not work with the given 
#     # datasets, ie where the datatype and formats do not overlap. A new 
#     # methods menu is returned. 

#     my ( $meths,          # Methods menu or list of ids
#          $dbs,            # Data menu
#         ) = @_;

#     # Returns a menu.

#     my ( $meth, @meths, @dbs, %filter );

#     if ( ref $dbs )
#     {
#         if ( ref $dbs eq "ARRAY" ) {
#             $dbs = Registry::Get->datasets( $dbs );
#         }
#     }
#     else {
#         &error( qq (Datasets must be given, either as a list of ids or a menu) );
#     }

#     foreach $meth ( @{ $meths->options } )
#     {
#         %filter = ( "formats" => [ $meth->dbformat ] );

#         if ( $meth->dbitypes ) {
#             $filter{"datatype"} = $meth->dbitypes;
#         }

#         if ( @dbs = $dbs->match_options( %filter ) )
#         {
#             push @meths, $meth;
#         }
#     }

#     if ( @meths ) {
#         $meths->options( \@meths );
#     } else {
#         &error( qq (Menu reduced to no options) );
#     }
    
#     return $meths;
# }
