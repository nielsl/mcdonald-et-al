#!/usr/bin/env perl

use strict;
use warnings FATAL => qw ( all );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OVERVIEW <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# 
# This short script is the only CGI script in the system and all 
# clicks pass through here. It receives CGI requests, determines
# subproject, invokes the right viewer with the right input and 
# request, and updates system and viewer states. The system runs 
# under mod_perl normally but mod_cgi for development. 
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $cgi, $url, $proj, $proj_dir, $sid, $sys_state, $viewer_state, 
     $nav_menu, $file, $head, $xhtml, $viewer, $request, $beg_secs,
     $end_secs, $inputdb, $wwwpath, $dirpath, $secs );

# CGI.pm is only used to get arguments with, XHTML generation is abstracted 
# in Common::Widgets and Ali::Widgets etc. 

use CGI;

# Common::Config module sets system variables by loading Config/Profile/system_paths
# which tells the system where the software is.

use Common::Config;
use Common::Messages;

# These are for state-keeping and logging in. The CGI arguments are used to 
# update states for each click. 

use Common::States;
use Common::Users;

# >>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# A few globals are used (may go away). Here they are set, so when run under 
# mod_perl there will be no "leakage" between invocations, because this short 
# script is not pre-loaded. There are more configuration variables, but they 
# dont change at runtime. 

$beg_secs = &time_start;

$Common::Messages::Http_header_sent = 0;
$Common::Messages::silent = 0;

$Common::Config::sys_state = {};
$Common::Config::session_id = "";
$Common::Config::recover_sub = undef;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> GET CGI ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# CGI.pm is not used other than for getting arguments, and $cgi is only being 
# passed to routines that need it for arguments and handles. Most of the XHTML 
# formatting is abstracted away in the Common::Widgets module.

$cgi = new CGI;
$url = $cgi->url( -absolute => 1 );

# >>>>>>>>>>>>>>>>>>>>>>>>> ACCEPT OR REDIRECT URLS <<<<<<<<<<<<<<<<<<<<<<<<<<<

# Extract project name from the start of the url string up to the first slash;
# if there is a directory of that name in the document root then proceed, 
# otherwise show homepage listing,

if ( $url =~ m|/?([^/]+)| ) {
    $proj_dir = $1;
} else {
    $proj_dir = "";
}
if ( $proj_dir and -r "$Common::Config::www_dir/$proj_dir" )
{
    # Normal requests, load project,

    $proj = &Common::Config::load_project( $proj_dir );

    $Common::Config::cgi_url = "/$proj_dir";  # TODO - may be removed
    $Common::Config::proj_name = $proj_dir;   # TODO - may be removed

    # If sys_message.html exists in the site directory, then display it 
    # and exit (sys_message.html is made with the stop_servers script and 
    # deleted with the start_servers script),

    $file = "$Common::Config::www_dir/$proj_dir/sys_message.html";
    
    if ( -e $file )
    {
        print &Common::Messages::html_header({"viewer" => "common"});
        print ${ &Common::File::read_file( $file ) };
        exit 0;
    }
}
else
{
    # No project name or bad project names end here, and causes 
    # redirection to a home page that lists the known projects,

    print &Common::Widgets::home_page();
    exit 0;
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> GET SESSION ID <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# No cookies. Instead, session IDs are passed around on all pages as a hidden 
# field, and so during normal browsing is included in $cgi. If it is, the ID 
# is just returned and the user is in. If not, but a user and password is given,
# then the session is looked up in a user database. If neither is given, a new
# one is created. The following login routine contains a "closed loop" that 
# handles creating new accounts and errors, and the user only gets beyond this
# point if accepted by the system. 

$sid = &Common::Users::login( $cgi, $proj );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> GET SYSTEM STATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# The system state is a hash that holds overal settings not specific to a 
# viewer. Here we load from file the previously saved state (done at the end 
# of this script) and lets the corresponding CGI ones override,

$sys_state = &Common::States::merge_cgi_with_sys_state( $cgi, $sid, $proj );

# Make it globally available, for error recovery mostly,

$Common::Config::sys_state = $sys_state;

# >>>>>>>>>>>>>>>>>>>>>>> GET SYSTEM NAVIGATION MENU <<<<<<<<<<<<<<<<<<<<<<<<<<

# 1. Creates a navigation menu structure that the display can render. Submenus 
# are read from files in subdirectories, as CMS systems do, except site 
# independent submenus like "Upload", "Analyze", "Login" etc are hardcoded. 
#
# 2. Updates the keys "viewer", "inputdb" and "request" in the system state. 
# These three keys are what the viewers need as input.

$nav_menu = Common::Menus->navigation_menu( $proj->projpath, $sys_state );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CALL VIEWERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Invoke the given viewer with given data and viewer request. The viewers 
# modify and save their own states, but do not touch the global state 
# ($sys_state).

$viewer = $sys_state->{"viewer"} || $proj->defaults->def_viewer;
$inputdb = $sys_state->{"inputdb"} || $proj->defaults->def_input;
$request = $sys_state->{"request"} || $proj->defaults->def_request;

$wwwpath = "$proj_dir/$sys_state->{'sys_menu_1'}/$sys_state->{'sys_menu_2'}";

$sys_state->{"page_refresh"} = 0;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RECTANGULAR DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

if ( $viewer eq "array_viewer" )
{
    require Ali::Viewer;
    require Ali::State;

    $viewer_state = &Ali::State::merge_cgi_with_viewer_state( $cgi, $sid, $inputdb );
    
    $viewer_state->{"ali_www_path"} = $wwwpath; 

    ( $head, $xhtml ) = &Ali::Viewer::main(
        {
            "project" => $proj,
            "sys_state" => $sys_state,
            "viewer_state" => $viewer_state,
        });
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ORGANISMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

elsif ( $viewer eq "orgs_viewer" )
{
    require Taxonomy::Viewer;
    require Taxonomy::State;

    $viewer_state = &Taxonomy::State::merge_cgi_with_viewer_state( $cgi, $sid, $inputdb );

    $viewer_state->{"tax_www_path"} = $wwwpath;

    $Common::Config::inputdb = $inputdb;

    $xhtml = &Taxonomy::Viewer::main(
        {
            "project" => $proj,
            "sys_state" => $sys_state,
            "viewer_state" => $viewer_state,
        });
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> QUERIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Here come interactive query requests, where results may be shown by one or 
# more of the other viewers,

elsif ( $viewer eq "query_viewer" )
{
    require Query::Viewer;

    $xhtml = &Query::Viewer::main(
        {
            "cgi" => $cgi,
            "project" => $proj,
            "sys_state" => $sys_state,
        });

    # Menus update depending on uploads and results, so have to get 
    # here again,

    $nav_menu = Common::Menus->navigation_menu( $proj->projpath, $sys_state );
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ANALYSES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# This is for submitting analysis jobs, that run in the background for longer 
# times, but can also be shown on one or more of the other viewers,

elsif ( $viewer eq "submit_viewer" )
{
    require Submit::Viewer;
    require Submit::State;
    
    $viewer_state = &Submit::State::merge_cgi_with_viewer_state( $cgi, $sid );
    $viewer_state->{"request"} ||= $request;

    $xhtml = &Submit::Viewer::main(
        {
            "cgi" => $cgi,
            "project" => $proj,
            "sys_state" => $sys_state,
            "viewer_state" => $viewer_state,
        });

    # Menus update depending on uploads and results, so have to get 
    # here again,

    $nav_menu = Common::Menus->navigation_menu( $proj->projpath, $sys_state );

    delete $viewer_state->{"request"};

    &Submit::State::save_state( $sid, $viewer_state );
}
else {
    &error( qq (Unrecognized viewer name -> "$viewer") );
}

# The fraction of seconds the programs have run are calculated
# and displayed in the footer bar on the web page,

$Common::Config::Run_secs = &time_elapsed( $beg_secs );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DISPLAY XHTML <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Send page content to display routine, which does headers and 
# footers, invokes style sheets, etc,

print &Common::Widgets::show_page(
    {
        "head" => $head,
        "body" => $xhtml,
        "sys_state" => $sys_state, 
        "project" => $proj,
        "nav_menu" => $nav_menu,
        "window_target" => "main",
    });

# >>>>>>>>>>>>>>>>>>>>>>>>>> UPDATE AND SAVE STATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Above viewers may have changed inputdb, here we make sure it is saved,

$sys_state->{"inputdb"} = $Common::Config::inputdb;

# Clear requests so repeated reloads wont cause repeat of action,

$sys_state->{"request"} = "";

# Records under the "menu_visits" key which navigation paths have
# been used before. This allows very handy browsing "memory", where 
# submenus are remembered from earlier visits.

$sys_state = &Common::States::set_navigation_visit( $sys_state );

# Save state under session directory,

&Common::States::save_sys_state( $sid, $sys_state );


__END__

# elsif ( $viewer eq "funcs_viewer" )
# {
#     require GO::Viewer;
#     require GO::State;

#     $viewer_state = &GO::State::merge_cgi_with_viewer_state( $cgi, $sid, $dirpath );

#     $viewer_state->{"go_dir_path"} = $dirpath;
#     $viewer_state->{"go_www_path"} = $wwwpath;

#     $Common::Config::inputdb = $dirpath;
#     $xhtml = &GO::Viewer::main( $sid, $viewer_state );
# }
