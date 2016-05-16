package Ali::Viewer;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_bookmark
                 &columns_less
                 &columns_more
                 &connect 
                 &create_image
                 &download_ali_data
                 &download_ali_image
                 &feature_keys_differ
                 &handle_downloads
                 &handle_menu_requests
                 &handle_navigation_requests
                 &handle_panels_requests
                 &handle_print
                 &handle_resets
                 &handle_saves_default
                 &handle_saves_update
                 &handle_toggle_requests
                 &main
                 &save_features_update
                 &save_features_default
                 &save_prefs_update
                 &save_prefs_default
                 &set_display_type
                 &set_session_link
                 &toggle_menu_state
                 );

use Common::Config;
use Common::Messages;

use Common::Util;
use Common::Types;
use Common::DB;

use Ali::IO;
use Ali::Common;
use Ali::State;
use Ali::Widgets;
use Ali::Menus;
use Ali::Bookmark;
use Ali::Display;

# use Ali::Features;

our $Viewer_name = "array_viewer";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_bookmark
{
    # UNFINISHED 

    my ( $sid,
         $ali,
        ) = @_;

    my ( $menu, $opt );

    $menu = Ali::Menus->bookmarks_menu( $sid );

    $opt = Ali::Bookmark->new();

    $opt->cols( [ $ali->_orig_cols->list ] );
    $opt->rows( [ $ali->_orig_rows->list ] );

    $menu->append_option( $opt, 1 );

    $menu->write;

    return;
}

sub columns_less
{
    # Niels Larsen, May 2007.

    # Subtracts enough columns from the state to cover a given width. Used 
    # for switching on labels and numbers: when these are added, the image 
    # area shrinks instead of shifting around. Returns an updated state.
    
    my ( $ali,
         $state,
         $begwid,
         $endwid,
         ) = @_;

    # Returns a hash.

    my ( $cols, $rows, $clip, $drop_cols );

    $cols = [ eval $state->{"ali_colstr"} ];
    $rows = [ eval $state->{"ali_rowstr"} ];

    $clip = $state->{"ali_clipping"}->{"right"};

    if ( $clip >= 0 ) {
        $drop_cols = $endwid;
    } else {
        $drop_cols = &Common::Util::max( 0, $endwid + $clip );
    }

    if ( $drop_cols > 0 )
    {
        splice @{ $cols }, $#{ $cols } - $drop_cols, $drop_cols + 1;
        $state->{"ali_clipping"}->{"right"} += $drop_cols;
    }

    $clip = $state->{"ali_clipping"}->{"left"};

    if ( $clip >= 0 ) {
        $drop_cols = $begwid;
    } else {
        $drop_cols = &Common::Util::max( 0, $begwid + $clip );
    }

    if ( $drop_cols > 0 )
    {
        splice @{ $cols }, 0, $begwid + 1;
        $state->{"ali_clipping"}->{"left"} += $drop_cols;
    }

    $state->{"ali_colstr"} = &Common::Util::integers_to_eval_str( $cols );
    
    return $state;
}

sub columns_more
{
    # Niels Larsen, May 2007.

    # Adds enough columns to the state to cover a given width. Used 
    # for switching off labels and numbers: when these are removed, the 
    # image area grows instead of shifting around. Returns an updated 
    # state.
    
    my ( $ali,
         $state,
         $width,
         ) = @_;
    
    # Returns a hash.

    my ( $cols, $rows, $new_cols, $new_clip, $clip, $get_cols, $subali, 
         $maxcol, $collapse );

    $cols = [ eval $state->{"ali_colstr"} ];
    $rows = [ eval $state->{"ali_rowstr"} ];

    $subali = $ali->subali_get( undef, $rows, 0, 0 );
    $maxcol = $subali->max_col_global();
    $collapse = $state->{"ali_prefs"}->{"ali_with_col_collapse"};

    if ( $cols->[-1] < $maxcol )
    {
        $clip = $state->{"ali_clipping"}->{"right"};
        
        if ( $clip >= 0 ) {
            $get_cols = &Common::Util::min( $clip, $width );
        } else {
            $get_cols = &Common::Util::max( 0, $width + $clip );
        }
        
        ( $new_cols, $new_clip ) = $subali->_get_indices_right( $cols->[-1]+1, $get_cols + 1, $collapse );
        
        if ( $new_cols ) 
        {
            push @{ $cols }, @{ $new_cols };
            $state->{"ali_clipping"}->{"right"} = $new_clip;
        }
    }
    
    if ( $cols->[0] > 0 )
    {
        $clip = $state->{"ali_clipping"}->{"left"};
        
        if ( $clip >= 0 ) {
            $get_cols = &Common::Util::min( $clip, $width );
        } else {
            $get_cols = &Common::Util::max( 0, $width + $clip );
        }
        
        ( $new_cols, $new_clip ) = $subali->_get_indices_left( $cols->[0]-1, $get_cols + 1, $collapse );
        
        if ( $new_cols )
        {
            unshift @{ $cols }, @{ $new_cols };
            $state->{"ali_clipping"}->{"left"} = $new_clip;
        }
    }

    $state->{"ali_colstr"} = &Common::Util::integers_to_eval_str( $cols );
    
    return $state;
}

sub connect
{
    # Niels Larsen, September 2005.

    # Connects to the given file, which must be in "raw" format (see
    # the Ali::Common module) defined by the Perl Data Language. An
    # alignment object is returned, of type rna, protein or dna. The
    # object is not read into memory but is file-resident. 
    
    my ( $sid,          # Session id
         $page,         # Alignment path, not full file path
         $state,        # State hash
         ) = @_;

    # Returns an alignment object. 

    my ( $ali, $type, $prefix, $args );

    $prefix = "$Common::Config::ses_dir/$sid/$page";

    foreach $type ( qw ( sids nums ) )
    {
        if ( $state ) {
            $args->{ "with_$type" } = $state->{"ali_prefs"}->{"ali_with_$type"};
        } else {
            $args->{ "with_$type" } = 1;
        }
    }

    $ali = &Ali::IO::connect_pdl( $prefix, $args );

    return $ali;
}

sub create_image
{
    # Niels Larsen, May 2007.
    
    # Creates display image and image map, saves these to file, and
    # updates the state. 

    my ( $dbh,
         $subali,
         $state,
         $inputdb,
         $sid,
         ) = @_;

    # Returns a hash.

    my ( $img_map, $version, $ses_dir, $fh, $map_path, $pix_mul, 
         $cols, $rows );

    $ses_dir = "$Common::Config::ses_dir/$sid";

    # Create image file name, incremented by 1 per click,

    if ( $state->{"ali_img_file"} )
    {
        if ( -r "$ses_dir/". $state->{"ali_img_file"} )
        {
            if ( $state->{"ali_img_file"} =~ /\.(\d+)\.png$/ ) {
                $version = $1 + 1;
            } else {
                &error( qq (Could not extract version from previous image -> ")
                                           . $state->{"ali_img_file"} . qq (") );
            }

            &Common::File::delete_file( "$ses_dir/". $state->{"ali_img_file"} );
            $state->{'ali_img_file'} = "$inputdb.$version.png";
        }
    }
    else {
        $state->{'ali_img_file'} = "$inputdb.1.png";
    }

    # Create image with features,

    $img_map = &Ali::Display::paint_image( $subali, $sid, $dbh, $state );

    # Save image,

    &Common::File::delete_file_if_exists( "$ses_dir/". $state->{'ali_img_file'} );
    $fh = &Common::File::get_write_handle( "$ses_dir/". $state->{'ali_img_file'} );
    
    $fh->print( $subali->image->png );
    
    &Common::File::close_handle( $fh );
    
    # Save image map,

    if ( $state->{"ali_img_map_file"} )
    {
        &Common::File::delete_file_if_exists( "$ses_dir/". $state->{"ali_img_map_file"} );
        undef $state->{'ali_img_map_file'};
    }

    if ( $img_map )
    {
        $map_path = $state->{'ali_img_file'} .".map";
        
        &Common::File::store_file( "$ses_dir/$map_path", $img_map );
        $state->{'ali_img_map_file'} = $map_path;
    }

    # Set strings of columns and rows that are to be passed to the browser,

    if ( defined $subali->_orig_cols ) {
        $state->{"ali_colstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_cols->list ] );
    } else {
        $state->{"ali_colstr"} = &Common::Util::integers_to_eval_str( [ 0 .. $subali->max_col ] );
    }
    
    if ( defined $subali->_orig_rows ) {
        $state->{"ali_rowstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_rows->list ] );
    } else {
        $state->{"ali_rowstr"} = &Common::Util::integers_to_eval_str( [ 0 .. $subali->max_row ] );
    }

    # Set minimum and maximum columns (just for easier showing in 
    # the viewer),
    
    $state->{"ali_min_col"} = $subali->global_col( 0 );
    $state->{"ali_max_col"} = $subali->global_col( $subali->max_col );
    $state->{"ali_min_row"} = $subali->global_row( 0 );
    $state->{"ali_max_row"} = $subali->global_row( $subali->max_row );

    return $state;
}

sub download_ali_data
{
    # Niels Larsen, May 2007.

    # Sends the given alignment to the client in fasta format. 

    my ( $ali,         # Alignment
         $args,
         $state,       # State hash
         ) = @_;

    # Returns nothing.

    my ( $icols, $irows, $maxbytes, $bytes, $bytstr, $msg, $nl, 
         $i, $sid, $url, $seq, $cgi, $with_gaps, $fname );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( download_file with_gaps ) ],
    });

    $icols = $ali->max_col + 1;
    $irows = $ali->max_row + 1;

    $bytes = $icols * $irows;
    $maxbytes = 100_000_000;

    if ( $bytes > $maxbytes )
    {
        $bytes = &Common::Util::abbreviate_number( $bytes );
        $maxbytes = &Common::Util::abbreviate_number( $maxbytes );

        $msg = qq (The download would be $bytes large, which would probably be unfortunate)
             . qq ( for your browser and might take a long time. Please try select a region)
             . qq ( that is at most $maxbytes large. If you think this maximum is too low,)
             . qq ( then please contact us.);

        if ( $url = Registry::Get->dataset( $ali->source )->downloads->baseurl )
        {
            $msg .= qq ( Or get the entire file from <a href="$url"><font color="blue">its download area</font></a>.);
        }

        push @{ $state->{"ali_messages"} }, [ "Error", $msg ];
    }
    else
    {
        $fname = $args->download_file;

        if ( not defined $fname ) {
            $fname = $ali->sid ."_$icols"."_$irows.fasta";
        }

        $nl = &Common::Users::get_client_newline();
        
        $cgi = new CGI;
        
        print $cgi->header( -type => "text/fasta",
                            -attachment => $fname,
                            -expires => "+10y" );

        $with_gaps = $args->with_gaps;
        
        for ( $i = 0; $i <= $ali->max_row; $i++ )
        {
            $sid = $ali->sid_string( $i );
            $sid =~ s/^\s+//g;
            $sid =~ s/\s+$//g;
            
            $seq = $ali->seq_string( $i );
            
            if ( not $with_gaps ) {
                $seq =~ s/\W//g;
            }

            print qq (>$sid$nl$seq$nl);
        }
    }
    
    return $state;
}

sub download_ali_image
{
    # Niels Larsen, May 2007.

    # Sends the given alignment image to the client in a user selected
    # format. 

    my ( $ali,         # Alignment
         $args,        # Arguments hash
         $state,       # State hash
         ) = @_;

    # Returns nothing.

    my ( $icols, $irows, $maxbytes, $bytes, $bytstr, $msg, $nl, 
         $i, $sid, $url, $seq, $cgi, $with_gaps, $fname );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( download_file with_gaps ) ],
    });

    $fname = $args->download_file;

    $cgi = new CGI;
        
    print $cgi->header( -type => "image/format",
                        -attachment => $fname,
                        -expires => "+10y" );

    return;
}

sub feature_keys_differ
{
    # Niels Larsen, May 2007.

    # Compares the feature keys from the given alignment with those 
    # from the given state, and returns 1 if different, otherwise
    # nothing.

    my ( $ali,         # Alignment
         $state,       # State
         ) = @_;

    # Returns 1 or nothing.

    my ( $menu, $opt, $hash1, $hash2 );

    $menu = $state->{"ali_features"};

    foreach $opt ( $menu->options )
    {
        $hash2->{ $opt->name } = $opt->selected || 0;
    }
        
    $hash1 = $ali->ft_options;

    if ( &Common::Util::hash_keys_differ( $hash1, $hash2 ) ) {
        return 1;
    }
    
    return;
}

sub handle_downloads
{
    # Niels Larsen, May 2007.

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

sub handle_menu_requests
{
    # Niels Larsen, May 2007.

    # This routine just makes the if-then-else in main shorter, all requests
    # that match "handle_*_menu" end here. State is updated and returned. 

    my ( $sid,            # Session id
         $state,          # State hash
         ) = @_;

    # Returns a hash.

    my ( $request, $menu, $menu_file, $inputdb, $www_path, $dat_path, $name, $file, $db );

    $request = $state->{"request"} || "";
    $inputdb = "";

    if ( $request eq "handle_ali_control_menu" )
    {
        $menu = Ali::Menus->control_menu( $sid );
        $state->{"request"} = $menu->match_option( "id" => $state->{"ali_control_menu"} )->request;
    }
    elsif ( $request eq "handle_ali_features_menu" )
    {
        $menu = $state->{"ali_features"};
        $state->{"request"} = $menu->match_option( "id" => $state->{"ali_features_menu"} )->request;
    }
    elsif ( $request eq "handle_ali_inputdb_menu" )
    {
        $www_path = $state->{'ali_www_path'};
        $menu_file = "$Common::Config::www_dir/$state->{'ali_www_path'}/navigation_menu";

        $menu = Ali::Menus->inputdb_menu( $sid, $menu_file );
        $inputdb = $menu->match_option( "id" => $state->{"ali_inputdb_menu"} )->inputdb;

        ( $name, $file ) = &Ali::State::split_dataloc( $inputdb );
        
        $db = Registry::Get->dataset( $name );
        $dat_path = $db->datapath ."/Installs/$file.". $db->datatype;
        
        $state = &Ali::State::restore_state( $sid, $dat_path );

        $state->{'ali_dat_path'} = $dat_path;
        $state->{'ali_www_path'} = $www_path;

        $state->{"ali_inputdb_menu_open"} = 1;

        $state->{"request"} = "";
        $state->{"inputdb"} = $inputdb;
    }
    elsif ( $request eq "handle_ali_user_menu" )
    {
        $menu = Ali::Menus->user_menu( $sid );
        $inputdb = $menu->match_option( "id" => $state->{"ali_user_menu"} )->input;

        ( $name, $file ) = &Ali::State::split_dataloc( $inputdb );
        
        $db = Registry::Get->dataset( $name );
        $dat_path = $db->datapath ."/Installs/$file.". $db->datatype;
        
        $state = &Ali::State::restore_state( $sid, $dat_path );

        $state->{'ali_dat_path'} = $dat_path;
        $state->{"ali_user_menu_open"} = 1;

        $state->{"request"} = "";
        $state->{"inputdb"} = $inputdb;
    }

    return $state;
}

sub handle_navigation_requests
{
    # Niels Larsen, September 2005.

    # Delegates scroll, zoom and recentering requests to the primitives.
    # Updates the state with clipping values etc.

    my ( $ali,      # Original alignment 
         $cols,     # Column indices
         $rows,     # Row index list
         $request,
         $state,    # States hash
         ) = @_;

    # Returns an alignment object.

    my ( $subali, $zoom_pct, $debug, $colpos, $rowpos, $x_beg, $x_end, 
         $y_beg, $y_end );

    if ( $request eq "ali_nav_begin" )
    {
        $subali = $ali->subali_right( 0, $rows, $state );
    }
    elsif ( $request eq "ali_nav_begin_rows" )
    {
#        $subali = $ali->subali_right_rows( $cols, $rows->[-1] + 1, $state );
    }
    elsif ( $request eq "ali_nav_left" )
    {
        $subali = $ali->subali_left( $cols->[0] - 1, $rows, $state );
    }
    elsif ( $request eq "ali_nav_right" )
    {
        $subali = $ali->subali_right( $cols->[-1] + 1, $rows, $state );
    }
    elsif ( $request eq "ali_nav_end" )
    {
        $subali = $ali->subali_left( $ali->max_col, $rows, $state );
    }
    elsif ( $request eq "ali_nav_top" )
    {
        $subali = $ali->subali_down( $cols->[0], 0, $state );
    }
    elsif ( $request eq "ali_nav_top_cols" )
    {
        $subali = $ali->subali_down_cols( $cols, 0, $state );
    }
    elsif ( $request eq "ali_nav_up" )
    {
        $subali = $ali->subali_up( $cols->[0], $rows->[0] - 1, $state );
    }
    elsif ( $request eq "ali_nav_up_cols" )
    {
        $subali = $ali->subali_up_cols( $cols, $rows->[0] - 1, $state );
    }
    elsif ( $request eq "ali_nav_down" )
    {
        $subali = $ali->subali_down( $cols->[0], $rows->[-1] + 1, $state );
    }
    elsif ( $request eq "ali_nav_down_cols" )
    {
        $subali = $ali->subali_down_cols( $cols, $rows->[-1] + 1, $state );
    }
    elsif ( $request eq "ali_nav_bottom" )
    {
        $subali = $ali->subali_up( $cols->[0], $ali->max_row, $state );
    }
    elsif ( $request eq "ali_nav_bottom_cols" )
    {
        $subali = $ali->subali_up_cols( $cols, $ali->max_row, $state );
    }
    elsif ( $request =~ /^ali_nav_zoom/ )
    {
        if ( $state->{"ali_image_area"} )
        {
            # Mouse click or drag,

            ( $x_beg, $x_end, $y_beg, $y_end ) = split ',', $state->{"ali_image_area"};

            if ( abs ( $x_end - $x_beg ) < 10 and abs ( $y_end - $y_beg ) < 10 )
            {
                $subali = &Ali::Display::display_center( $ali, $cols, $rows, $state );
            }
            else {
                $subali = &Ali::Display::display_zoom_in_area( $ali, $cols, $rows, $state );
            }
        }
        else
        {
            # Zoom buttons, 

            $zoom_pct = $state->{"ali_prefs"}->{"ali_zoom_pct"};

            if ( $zoom_pct =~ /^[\+0-9]+$/ )
            {
                if ( $request eq "ali_nav_zoom_in" )
                {
                    $subali = &Ali::Display::display_zoom_in_pct( $ali, $cols, $rows, $state );
                }
                elsif ( $request eq "ali_nav_zoom_out" )
                {
                    $subali = &Ali::Display::display_zoom_out( $ali, $cols, $rows, $state );
                }
            }
            else 
            {
                push @{ $state->{"ali_messages"} }, 
                [ "Error", qq (Wrong-looking zoom percentage -> "$zoom_pct". It should be a positive integer.) ];
            }
        }
    }
    else {
        &error( qq (Wrong looking navigation argument -> "$request") );
    }

    return $subali;
}

sub handle_panels_requests
{
    # Niels Larsen, May 2007.

    # Dispatches requests for popup panel windows. Returns XHTML code.

    my ( $request,
         $ali,
         $sid,
         $state,
         $proj,
         ) = @_;

    # Returns a string.

    my ( $dir, $xhtml, $ft_hash, $opt, $opts, $menu );

    if ( $request eq "ali_help_panel" )
    {
        require Ali::Help;
        $xhtml = &Ali::Help::pager( "main", $sid );
        
        $state->{"is_help_page"} = 1;
        $state->{"title"} = "Array Viewer Help Page";
    }
    elsif ( $request eq "ali_prefs_panel" )
    {
        $xhtml = &Ali::Widgets::prefs_panel({
            "sid" => $sid,
            "viewer" => $Viewer_name,
            "uri_path" => $proj->projpath,
            "prefs" => $state->{"ali_prefs"},
        });
    }
    elsif ( $request eq "ali_features_panel" )
    {
        $opts = &Common::Options::build_viewer_feature_options(
            {
                "viewer" => $Viewer_name,
                "sid" => $sid,
                "datatype" => $ali->datatype,
                "features" => $state->{"ali_features"},
            });

        $menu = Registry::Get->new( "options" => $opts );

        $xhtml = &Ali::Widgets::features_panel({
            "sid" => $sid,
            "viewer" => $Viewer_name,
            "features" => $menu,
            "uri_path" => $proj->projpath,
        });
    }
    elsif ( $request eq "ali_print_panel" )
    {
        $xhtml = &Ali::Widgets::print_panel({
            "ali_name" => $ali->sid,
            "sid" => $sid,
            "viewer" => $Viewer_name, 
            "uri_path" => $proj->projpath,
        });
    }
    elsif ( $request eq "ali_downloads_panel" )
    {
        $xhtml = &Ali::Widgets::downloads_panel({
            "ali_name" => $ali->sid,
            "sid" => $sid,
            "viewer" => $Viewer_name, 
            "uri_path" => $proj->projpath,
        });
    }
    else {
        &error( qq (Wrong looking panel request -> "$request") );
    }

    return $xhtml;
}

sub handle_print
{
    # Niels Larsen, May 2007.

    # Handles download image option.

    my ( $sid,
         $inputdb,
         $ali,
         $cols,
         $rows,
         $state,
         ) = @_;

    my ( $subali, $form, $menu, $state_c, $dbh, $image, $format, $cgi, $dataset );

    # Create form hash,

    $form = &Common::States::make_hash( $state->{"ali_print_keys"},
                                        $state->{"ali_print_values"} );

    delete $state->{"ali_print_keys"};
    delete $state->{"ali_print_values"};

    $menu = Ali::Menus->print_menu( $ali->sid )->match_option( "name" => "ali_print_format" )->choices;
    $form->{"ali_print_format"} = $menu->match_option( "name" => $form->{"ali_print_format"} )->name;

    if ( $form->{"ali_print_dpi"} ) 
    {
        $menu = Ali::Menus->print_menu( $ali->sid )->match_option( "name" => "ali_print_dpi" )->choices;
        $form->{"ali_print_dpi"} = $menu->match_option( "name" => $form->{"ali_print_dpi"} )->name;
    }
    else {
        $form->{"ali_print_dpi"} = 1.0;
    }

    $form->{"ali_print_file"} ||= $ali->sid;
    $form->{"ali_print_file"} .= ".". $form->{"ali_print_format"};
    $form->{"ali_print_file"} =~ s/\s/_/g;

    $form->{"ali_print_title"} ||= "";

    # Create alignment. Using the current columns and rows recreates the data
    # that was in the viewer last,

    $subali = $ali->subali_get( $cols, $rows, 
                                $state->{"ali_prefs"}->{"ali_with_sids"},
                                $state->{"ali_prefs"}->{"ali_with_nums"} );

    # Create image, with all current features pulled in. The resolution is 
    # passed to the stringFT function in GD.

    if ( &Common::Types::is_user_data( $state->{"ali_dat_path"} ) )
    {
        $dbh = &Common::DB::connect_user( $sid );
    }
    else
    {
        ( $dataset, undef ) = &Ali::State::split_dataloc( $state->{"inputdb"} );        
        $dbh = &Common::DB::connect( $dataset );
    }

    $state_c = &Storable::dclone( $state );
    $state_c->{"ali_bg_color"} = "#ffffff";

    # Dont switch this on again: causes huge characters in print output, because of
    # bug somewhere. But print output should be vector graphics anyway. 
#    $state_c->{"ali_resolution"} = $form->{"ali_print_dpi"} * 600;  # Has no effect for now 

    &Ali::Display::paint_image( $subali, $sid, $dbh, $state_c );

    &Common::DB::disconnect( $dbh );

    $image = $subali->image;
    $format = $form->{"ali_print_format"};

    # Print image,

    $cgi = new CGI;

    print $cgi->header( -type => "image/$format",
                        -attachment => $form->{"ali_print_file"},
                        -expires => "+10y" );

    if ( $format eq "png" ) {
        print $image->$format; # ( 0 );       # no compression

#    } elsif ( $format eq "svg" ) {
#        print STDERR $image->$format;
    }
    else {
        print $image->$format;
    }

    return;
}

sub handle_resets
{
    # Niels Larsen, May 2007.

    # Handles reset button requests from different forms. Returns 
    # XHTML code.

    my ( $args,
         $state,
         $proj,
         ) = @_;

    # Returns a string.

    my ( $viewer, $sid, $form, $prefs, $opts, $ali, $menu, $xhtml );
        
    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer sid inputdb form ) ],
    });

    $viewer = $args->viewer;
    $sid = $args->sid;    
    $form = $args->form;

    if ( $form eq "prefs_panel" )
    {
         $xhtml = &Ali::Widgets::prefs_panel({
             "sid" => $sid,
             "viewer" => $viewer, 
             "uri_path" => $proj->projpath,
             "prefs" => Registry::Get->viewer_prefs( $viewer ),
         });
    }
    elsif ( $form eq "features_panel" )
    {
        $ali = &Ali::Viewer::connect( $sid, $args->inputdb, $state );

        $opts = &Common::Options::build_viewer_feature_options(
            {
                "viewer" => $Viewer_name,
                "datatype" => $ali->datatype,
                "features" => $state->{"ali_features"},
            });

        undef $ali;
        $menu = Registry::Get->new( "options" => $opts );

        $xhtml = &Ali::Widgets::features_panel({
            "sid" => $sid,
            "viewer" => $viewer,
            "uri_path" => $proj->projpath,
            "features" => $menu,
        });
    }
    else {
        &error( qq (Wrong looking form name -> "$form") );
    }

    return $xhtml;
}

sub handle_saves_default
{
    # Niels Larsen, May 2007.

    # Handles the "Save as default" buttons in the settings and 
    # highlights popup windows. It returns an updated state, but no
    # updated alignment data (which means the previous image will be
    # reused. There will be more kinds of saves, bookmarks etc. 

    my ( $args,
         $state,
         $proj,
         ) = @_;

    # Returns a hash.

    my ( $viewer, $sid, $form, $ali, $inputdb, $project );
        
    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( viewer sid inputdb form project ) ],
    });

    $viewer = $args->viewer;
    $sid = $args->sid;
    $inputdb = $args->inputdb;
    $form = $args->form;
    $project = $args->project;

    $ali = &Ali::Viewer::connect( $sid, $inputdb ); 

    if ( $form eq "prefs_panel" )
    {
        &Ali::Viewer::save_prefs_default( $viewer, $sid, $state );
    }
    elsif ( $form eq "features_panel" )
    {
        &Ali::Viewer::save_features_default(
             {
                 "project" => $project,
                 "sid" => $sid,
                 "viewer" => $viewer,
                 "datatype" => $ali->datatype,
             }, $state );
    }
    else {
        &error( qq (Wrong looking form name -> "$form") );
    }

    return $state;
}

sub handle_saves_update
{
    # Niels Larsen, May 2007.

    # Handles the "Save" buttons in the settings and highlights popup windows. 
    # The Save takes immediate effect (returns a $subali), but also updates
    # the given state hash. There will be more kinds of saves, bookmarks etc. 

    my ( $args,
         $state,
         ) = @_;

    # Returns a hash.

    my ( $sid, $form, $ali, $inputdb, $subali, $cols, $rows );
        
    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( sid inputdb form ) ],
    });

    $sid = $args->sid;
    $inputdb = $args->inputdb;
    $form = $args->form;

    $ali = &Ali::Viewer::connect( $sid, $inputdb ); 

    if ( $form eq "prefs_panel" )
    {
        $state = &Ali::Viewer::save_prefs_update( $ali, $state );
    }
    elsif ( $form eq "features_panel" )
    {
        $state = &Ali::Viewer::save_features_update( $ali, $state );
    }
    else {
        &error( qq (Wrong looking form name -> "$form") );
    }
    
    $cols = [ eval $state->{"ali_colstr"} ];
    $rows = [ eval $state->{"ali_rowstr"} ];
    
    $subali = $ali->subali_get( $cols, $rows,
                                $state->{"ali_prefs"}->{"ali_with_sids"},
                                $state->{"ali_prefs"}->{"ali_with_nums"} );

    return $subali;
}

sub handle_toggle_requests
{
    # Niels Larsen, September 2005.

    # Handles toggle requests, like switch on/off sequence numbering 
    # and labels in the margins. Modifies state.

    my ( $ali,       # Alignment object 
         $sid,
         $input,
         $cols,      # Column index list
         $rows,      # Row index list
         $request,   # 
         $state,     # States hash
         ) = @_;

    # Returns an alignment object. 

    my ( $subali, $colpos, $rowpos, $name, $option, $menu );

    if ( $request =~ /^highlight_(.*)/ )
    {
        $name = $1;
        $menu = $state->{"ali_features"};
        $option = $menu->match_option( "name" => $name );

        $option->selected( not $option->selected );

        if ( $option->name =~ /_color_dots$/ )
        {
            if ( $option->selected ) {
                $state->{"ali_display_type"} = "color_dots";
            } else {
                $state->{"ali_display_type"} = "characters";
            }
        }
    
        $subali = $ali->subali_get( $cols, $rows, 
                                    $state->{"ali_prefs"}->{"ali_with_sids"},
                                    $state->{"ali_prefs"}->{"ali_with_nums"} );
    }
    elsif ( $request =~ /^toggle_(col|row)_collapse$/ )
    {
        $name = $1 . "_collapse";

        $state->{"ali_prefs"}->{"ali_with_$name"} = not $state->{"ali_prefs"}->{"ali_with_$name"};

        $colpos = $cols->[ int scalar @{ $cols } / 2 ];
        $rowpos = $rows->[ int scalar @{ $rows } / 2 ];

        $subali = $ali->subali_center( $colpos, $rowpos, $state );
    }
    elsif ( $request =~ /^toggle_(col|row)_zoom$/ )
    {
        $name = $1 ."_zoom";

        $state->{"ali_prefs"}->{"ali_with_$name"} = not $state->{"ali_prefs"}->{"ali_with_$name"};

        if ( $name eq "row_zoom" and not $state->{"ali_prefs"}->{"ali_with_row_zoom"} ) {
            $state->{"ali_prefs"}->{"ali_with_col_zoom"} = 1;
        } elsif ( $name eq "col_zoom" and not $state->{"ali_prefs"}->{"ali_with_col_zoom"} ) {
            $state->{"ali_prefs"}->{"ali_with_row_zoom"} = 1;
        }
    }

    return $subali;
}
        
sub main
{
    # Niels Larsen, August 2005.

    # Main routine that handles all array_viewer requests and generates 
    # browser xhtml. A state file is kept in the sessions area that tells
    # which menus are open, the preferences in effect, etc. The given 
    # session ID is part of a directory path to the sessions area. The 
    # data are kept in PDL format. 

    my ( $args,
         $msgs,
         ) = @_;

    # Returns a string.
    
    my ( $request, $ali, $menu, $xhtml, $subali, $inputdb, $rows, $cols, 
         $fh, $ses_dir, $site_dir, $secs, $dbh, $sid, $state, $sys_state, 
         $img_map, $img_area, $col, $row, $width, $prefs, $file, $proj, 
         $ft_menu, $header, $x_beg, $y_beg, $x_end, $y_end, $data_owner, 
         $data_dir, $datpath );

    $args = &Registry::Args::check( $args, {
        "O:1" => [ qw ( project ) ],
        "HR:1" => [ qw ( viewer_state sys_state ) ],
    });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sys_state = $args->sys_state;
    $state = $args->viewer_state;
    $proj = $args->project;

    $sid = $sys_state->{"session_id"};

    $ses_dir = "$Common::Config::ses_dir/$sid";

    # >>>>>>>>>>>>>>>>>>>> MENU REQUESTS AND INPUT <<<<<<<<<<<<<<<<<<<<<<<<

    # Requests are often in menus and input data. This step intercepts
    # those requests and resets requst and inputdb in the state hash,

    $request = $state->{"request"} || "";

    if ( $request =~ /^handle_.+_menu$/ )
    {
        $state = &Ali::Viewer::handle_menu_requests( $sid, $state );
    }

    $request = $state->{"request"} || "";
    $inputdb = $state->{"inputdb"} || "";
    $datpath = $state->{"ali_dat_path"} || "";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CONNECT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # State and configuration files are kept for each user, but system 
    # provided alignments are linked to, 

    if ( not &Common::Types::is_user_data( $datpath ) and
         not -l "$ses_dir/$datpath.pdl" )
    {
        &Ali::Viewer::set_session_link( $sid, $datpath );
    }

    # Connect to memory mapped PDL file, and set title and datatype,

    $ali = &Ali::Viewer::connect( $sid, $datpath, $state );

    if ( not &Common::Types::is_user_data( $datpath ) )
    {
        ( $data_dir, undef ) = &Ali::State::split_dataloc( $inputdb );
    }
    
    $state->{"ali_title"} = $ali->title;
    $state->{"ali_datatype"} = $ali->datatype;

    # >>>>>>>>>>>>>>>>>>>>>>> INIT FEATURE MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If there is no features menu in the state, derive it from the 
    # data: fill the menu with the features that actually exist and 
    # turn on reasonable defaults to be shown,

    if ( not exists $state->{"ali_features"} )
    {
        if ( &Common::Types::is_user_data( $datpath ) ) {
            $dbh = &Common::DB::connect_user( $sid );
        } else {
            $dbh = &Common::DB::connect( $data_dir );
        }

        $state->{"ali_features"} = &Ali::Menus::features_existing(
            $dbh,
            {
                "sid" => $sid,
                "viewer" => $Viewer_name,
                "ali_id" => $ali->sid,
                "ali_type" => $ali->datatype,
            });
        
        $state = &Ali::Viewer::set_display_type( $state );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> FIT TO IMAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Image size is given (but configurable), and this finds out how much
    # data can fit within the image,

    $state = &Ali::Display::_fit_data_to_image( $ali, $state );

    # >>>>>>>>>>>>>>>>>>>>>> GET COLUMNS AND ROWS <<<<<<<<<<<<<<<<<<<<<<<<<

    # Strings like '40,56,60..68,71' are passed on each page and eval'ed 
    # here, to get the columns and rows that were on the previous page. It
    # allows the back-button the browser to be used with less risk .. 

    if ( defined $state->{"ali_colstr"} and 
         (length $state->{"ali_colstr"} > 0) and 
         $state->{"ali_img_file"} )
    {
        $cols = [ eval $state->{"ali_colstr"} ];
    } else {
        $cols = [];
    }

    if ( defined $state->{"ali_rowstr"} and 
         (length $state->{"ali_rowstr"} > 0) and 
         $state->{"ali_img_file"} )
    {
        $rows = [ eval $state->{"ali_rowstr"} ];
    } else {
        $rows = [];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    #
    #                           DISPATCH REQUESTS 
    # 
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $request =~ /^ali_nav/ )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>> BASIC NAVIGATION <<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $request =~ /^ali_nav_reset/ )
        {
            foreach $file ( $state->{"ali_img_file"}, $state->{"ali_img_map_file"} )
            {
                if ( defined $file ) {
                    &Common::File::delete_file_if_exists( "$ses_dir/$file" );
                }
            }

            $ft_menu = $state->{"ali_features"};
            $state = &Ali::State::restore_state( $sid, $datpath, ".first" );
            $state->{"ali_features"} = $ft_menu;

            $prefs = $state->{"ali_prefs"};

            $subali = $ali->subali_get( [ eval $state->{"ali_colstr"} ],
                                        [ eval $state->{"ali_rowstr"} ],
                                        $prefs->{"ali_with_sids"},
                                        $prefs->{"ali_with_nums"} );
        }
        else
        {
            $subali = &Ali::Viewer::handle_navigation_requests( $ali, $cols, $rows, $request, $state );
        }
    }
    elsif ( $request =~ /^toggle_|highlight_/ )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> TOGGLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # The page has short-cut toggles for the most used switches. This handles
        # such toggle requests,

        $subali = &Ali::Viewer::handle_toggle_requests( $ali, $sid, $datpath, 
                                                        $cols, $rows, $request, $state );
    }
    elsif ( $request =~ /^show.*menu$/ or $request =~ /hide.*menu$/ )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>> MENU OPEN AND CLOSE <<<<<<<<<<<<<<<<<<<<<<<

        $state = &Ali::Viewer::toggle_menu_state( $state, $request );
    }
    elsif ( $request =~ /_panel$/ )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> POPUP PANELS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $xhtml = &Ali::Viewer::handle_panels_requests( $request, $ali, $sid, $state, $proj );

        if ( $request eq "ali_help_panel" ) {
            $sys_state->{"is_help_page"} = 1;
        } else {
            $sys_state->{"is_popup_page"} = 1;
        }

        $sys_state->{"viewer"} = $Viewer_name;
        $sys_state->{"session_id"} = $sid;

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj,
            });

        exit 0;
    }
    elsif ( $request eq "Save as default" )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE DEFAULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # This handles the "Save as default" buttons in the settings and 
        # highlights popup windows. It returns an updated state, but no
        # updated alignment data (which means the previous image will be
        # reused,

        $state = &Ali::Viewer::handle_saves_default(
            {
                "viewer" => $Viewer_name,
                "sid" => $sid,
                "inputdb" => $datpath,
                "form" => $sys_state->{"form_name"},
                "project" => $proj->name,
            }, $state );
    }
    elsif ( $request eq "Save" )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>> SAVE THAT UPDATES <<<<<<<<<<<<<<<<<<<<<<<<<

        # This handles the "Save" buttons in the settings and highlights popup 
        # windows. The Save takes immediate effect (returns a $subali), but also
        # updates the given state hash. 

        $subali = &Ali::Viewer::handle_saves_update({
            "sid" => $sid,
            "inputdb" => $datpath,
            "form" => $sys_state->{"form_name"},
        }, $state );
    }
    elsif ( $request =~ /^Reset/ )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> RESET REQUESTS <<<<<<<<<<<<<<<<<<<<<<<<<<

        $xhtml = &Ali::Viewer::handle_resets({
            "viewer" => $Viewer_name,
            "sid" => $sid,
            "inputdb" => $datpath,
            "form" => $sys_state->{"form_name"},
        }, $state, $proj );

        $sys_state->{"is_popup_page"} = 1;

        &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj, 
            });

        exit 0;
    }
    elsif ( $request =~ /^Download/ )
    {
        if ( $sys_state->{"form_name"} eq "downloads_panel" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA DOWNLOADS <<<<<<<<<<<<<<<<<<<<<<<<<<<

            &Ali::Viewer::handle_downloads( $ali, $cols, $rows, $state );
        }
        elsif ( $sys_state->{"form_name"} eq "print_panel" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>> IMAGE DOWNLOADS <<<<<<<<<<<<<<<<<<<<<<<<<<<

            &Ali::Viewer::handle_print( $sid, $datpath, $ali, $cols, $rows, $state );
        }
        else {
            &error( qq (Wrong looking form name -> "$sys_state->{'form_name'}") );
        }
        
        if ( @{ $state->{"ali_messages"} } )
        {
            $xhtml = &Ali::Widgets::format_page( $sid, $state, $inputdb );
            &Common::Widgets::show_page(
            {
                "body" => $xhtml,
                "sys_state" => $sys_state, 
                "project" => $proj, 
            });
        }

        exit 0;
    }
    elsif ( not @{ $cols } or not @{ $rows } )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> IF NO REQUEST <<<<<<<<<<<<<<<<<<<<<<<<<<<

        $subali = $ali->subali_down( 0, 0, $state );
        
        $state->{"ali_colstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_cols->list ] );
        $state->{"ali_rowstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_rows->list ] );
        
        &Ali::State::save_state( $sid, $datpath, $state, ".first" );
    }
    elsif ( $request )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ERROR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &error( qq (Wrong looking request in main -> "$request") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>> CREATE IMAGE AND PAGE <<<<<<<<<<<<<<<<<<<<<<<<<

    # A new view is usually generated, but not if just a menu is 
    # opened, say. This writes a new image to disk if a new sub-alignment
    # is generated, otherwise uses the old (faster when jumping around 
    # between menus). To prevent the browser from caching the image and
    # optional image map are stored in constantly changing file names
    # (and the previous ones are deleted).

    if ( $subali )
    {
        if ( $state->{"ali_prefs"}->{"ali_with_sids"} or $state->{"ali_features"} )
        {
            if ( &Common::Types::is_user_data( $datpath ) ) {
                $dbh = &Common::DB::connect_user( $sid );
            } else {
                $dbh = &Common::DB::connect( $data_dir );
            }
        }

        $state = &Ali::Viewer::create_image( $dbh, $subali, $state, $datpath, $sid );
    }

#    &time_elapsed( $secs, "create_image" );

    if ( $dbh ) {
        &Common::DB::disconnect( $dbh )
    };

    $header = &Ali::Widgets::format_header( $state );
    $xhtml = &Ali::Widgets::format_page( $sid, $state, $inputdb );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE STATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $state->{"ali_messages"} = [];
    $state->{"request"} = "";

    $Common::Config::inputdb = $inputdb;

    &Ali::State::save_state( $sid, $datpath, $state );

    return ( $header || "", $xhtml );
}

sub save_features_update
{
    # Niels Larsen, May 2007.

    # Updates the feature menu included in state with the values coming
    # from a form. Returns an updated state.

    my ( $ali,         # 
         $state,
         ) = @_;

    # Returns a hash.

    my ( $hash, $opt, $key, $val );

    $hash = &Common::States::make_hash( $state->{"ali_features_keys"},
                                        $state->{"ali_features_values"} );
    
    delete $state->{"ali_features_keys"};
    delete $state->{"ali_features_values"};
    
    foreach $opt ( $state->{"ali_features"}->options )
    {
        if ( exists $hash->{ $opt->name } ) {
            $opt->selected( $hash->{ $opt->name } );
        } else {
            $opt->selected( 1 );
        }
    }

    $state = &Ali::Viewer::set_display_type( $state );

    return $state;
}

sub save_features_default
{
    my ( $args,
         $state,
         ) = @_;

    my ( $new_fts, $fts, $datatype, $file, $msg, $title );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( sid viewer datatype project ) ],
    });

    $new_fts = &Common::States::make_hash( $state->{"ali_features_keys"},
                                           $state->{"ali_features_values"} );

    delete $state->{"ali_features_keys"};
    delete $state->{"ali_features_values"};

    $datatype = $args->datatype;
    
    $fts = &Common::States::restore_viewer_features({
        "viewer" => $args->viewer,
        "sid" => $args->sid,
        "datatype" => $datatype,
    });
    
    $fts = &Common::Util::merge_hashes( $fts, $new_fts );

    $file = &Common::States::save_viewer_features( $args->viewer, $args->sid, $fts, $datatype );
    
    $title = Registry::Get->type( $datatype )->title;

    $msg = qq (Features saved. They will now be used as defaults for all $title datasets not yet visited.);
    push @{ $state->{"ali_messages"} }, [ "Done", $msg ];

    return $file;
}

sub save_prefs_update
{
    # Niels Larsen, May 2007.

    # Looks at incoming image preferences and updates the view if they are 
    # different from the ones we have already: shows image with or without
    # labels, numbers and in different sizes with smaller or larger amounts
    # of data shown. Returns an updated state.

    my ( $ali,
         $state,
         ) = @_;

    # Returns a hash.

    my ( $old_prefs, $new_prefs, $cols, $rows, $subali );

    $old_prefs = $state->{"ali_prefs"};
    
    $new_prefs = &Common::States::make_hash( $state->{"ali_prefs_keys"},
                                             $state->{"ali_prefs_values"} );

    delete $state->{"ali_prefs_keys"};
    delete $state->{"ali_prefs_values"};

    # Hide or show numbers,

    if ( $old_prefs->{"ali_with_nums"} ne $new_prefs->{"ali_with_nums"} )
    {
        if ( $new_prefs->{"ali_with_nums"} ) {
            $state = &Ali::Viewer::columns_less( $ali, $state, $ali->beg_cols, $ali->end_cols );
        } else {
            $state = &Ali::Viewer::columns_more( $ali, $state, $ali->beg_cols, $ali->end_cols );
        }
    }

    # Hide or show short-ids (labels),

    if ( $old_prefs->{"ali_with_sids"} ne $new_prefs->{"ali_with_sids"} )
    {
        if ( $new_prefs->{"ali_with_sids"} ) {
            $state = &Ali::Viewer::columns_less( $ali, $state, $ali->sid_len, $ali->sid_len );
        } else {
            $state = &Ali::Viewer::columns_more( $ali, $state, $ali->sid_len, $ali->sid_len );
        }
    }

    # Change height and/or width of image, and fit data to new dimension,

    if ( $old_prefs->{"ali_img_height"} ne $new_prefs->{"ali_img_height"} or
         $old_prefs->{"ali_img_width"} ne $new_prefs->{"ali_img_width"} )
    {
        $state->{"ali_prefs"} = $new_prefs;
        $state = &Ali::Display::_fit_data_to_image( $ali, $state );

        $cols = [ eval $state->{"ali_colstr"} ];
        $rows = [ eval $state->{"ali_rowstr"} ];

        $subali = $ali->subali_down( $cols->[0], $rows->[0], $state );
        
        $state->{"ali_colstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_cols->list ] );
        $state->{"ali_rowstr"} = &Common::Util::integers_to_eval_str( [ $subali->_orig_rows->list ] );
    }

    $state->{"ali_prefs"} = $new_prefs;

    return $state;
}

sub save_prefs_default
{
    # Niels Larsen, May 2007.

    # 
    my ( $viewer,
         $sid,
         $state,
         ) = @_;

    my ( $new_prefs, $prefs, $file, $msg );

    $new_prefs = &Common::States::make_hash( $state->{"ali_prefs_keys"},
                                             $state->{"ali_prefs_values"} );

    delete $state->{"ali_prefs_keys"};
    delete $state->{"ali_prefs_values"};

    $prefs = &Common::States::restore_viewer_prefs({
        "viewer" => $viewer,
        "sid" => $sid,
    });

    $prefs = &Common::Util::merge_hashes( $prefs, $new_prefs );

    $file = &Common::States::save_viewer_prefs( $viewer, $sid, $prefs );

    $msg = qq (Preferences saved. They will now be used as defaults for all datasets not yet visited.);
    push @{ $state->{"ali_messages"} }, [ "Done", $msg ];

    return $file;
}

sub set_display_type
{
    # Niels Larsen, May 2007.
    
    # Looks at the feature menu to see if color-dot display mode has been
    # selected, and sets state key "ali_display_type" to "color_dots" if so,
    # otherwise "characters". TODO: routines like these are silly, should 
    # overhaul the whole state thing. Returns an updated state.

    my ( $state,
         ) = @_;

    # Returns a hash.

    my ( $hash );

    $hash = { map { $_->name, $_->selected } @{ $state->{"ali_features"}->options } };

    if ( $hash->{"ali_nuc_color_dots"} or 
         $hash->{"ali_prot_color_dots"} )
    {
        $state->{"ali_display_type"} = "color_dots";
    } else {
        $state->{"ali_display_type"} = "characters";
    }

    return $state;
}

sub set_session_link
{
    # Niels Larsen, September 2005.

    # Creates a link from a system alignment into a users session area.

    my ( $sid,
         $prefix,
         ) = @_;

    # Returns nothing.

    my ( $dat_dir, $ses_dir, $base_dir );

    $dat_dir = $Common::Config::dat_dir;
    $ses_dir = "$Common::Config::ses_dir/$sid";

    $base_dir = &File::Basename::dirname( "$ses_dir/$prefix" );
    
    &Common::File::create_dir_if_not_exists( $base_dir );
    
    &Common::File::create_link( "$dat_dir/$prefix.pdl", "$ses_dir/$prefix.pdl" );
    &Common::File::create_link( "$dat_dir/$prefix.info", "$ses_dir/$prefix.info" );
    
    if ( -r "$dat_dir/$prefix.features" ) {
        &Common::File::create_link( "$dat_dir/$prefix.features", "$ses_dir/$prefix.features" );
    }

    return;
}

sub toggle_menu_state
{
    # Niels Larsen, September 2005.

    # Sets a state flag about "openness" of a menu. For example,
    # if the user clicks to open the control menu the state key 
    # "ali_control_menu_open" will be set to 1. Then the display
    # routine will show the menu as open. Returns an updated
    # state hash. 

    my ( $state,      # States hash
         $request,    # Request string
         ) = @_;

    # Returns a hash. 

    my ( $requests, $key, $val );

    $requests->{"show_ali_control_menu"} = [ "ali_control_menu_open", 1 ];
    $requests->{"hide_ali_control_menu"} = [ "ali_control_menu_open", 0 ];
    $requests->{"show_ali_features_menu"} = [ "ali_features_menu_open", 1 ];
    $requests->{"hide_ali_features_menu"} = [ "ali_features_menu_open", 0 ];
    $requests->{"show_ali_inputdb_menu"} = [ "ali_inputdb_menu_open", 1 ];
    $requests->{"hide_ali_inputdb_menu"} = [ "ali_inputdb_menu_open", 0 ];
    $requests->{"show_ali_resize_buttons"} = [ "ali_with_resize_buttons", 1 ];
    $requests->{"hide_ali_resize_buttons"} = [ "ali_with_resize_buttons", 0 ];
    $requests->{"show_ali_selections_menu"} = [ "ali_selections_menu_open", 1 ];
    $requests->{"hide_ali_selections_menu"} = [ "ali_selections_menu_open", 0 ];
    $requests->{"show_ali_user_menu"} = [ "ali_user_menu_open", 1 ];
    $requests->{"hide_ali_user_menu"} = [ "ali_user_menu_open", 0 ];
    $requests->{"show_uploads_menu"} = [ "uploads_menu_open", 1 ];
    $requests->{"hide_uploads_menu"} = [ "uploads_menu_open", 0 ];
    
    if ( exists $requests->{ $request } )
    {
        $key = $requests->{ $request }->[0];
        $val = $requests->{ $request }->[1];
        
        $state->{ $key } = $val;
    }

    return wantarray ? %{ $state } : $state;
}

1;

__END__


# sub clear_user_input
# {
#     # Niels Larsen, May 2007.

#     # Sets the "transient" state values that come directly from user 
#     # input fields to nothing. Should be called just after the place 
#     # where these fields have been used/saved. The purpose is to avoid 
#     # an action repeated if user pressed the reload button.

#     my ( $sid,       # Session id
#          $state,     # State hash
#          ) = @_;

#     # Returns a hash.

#     $state->{"request"} = "";

#     delete $state->{"ali_prefs_keys"};
#     delete $state->{"ali_prefs_values"};
    
#     delete $state->{"ali_features_keys"};
#     delete $state->{"ali_features_values"};
    
#     return $state;
# }


# sub set_params
# {
#     # Niels Larsen, July 2005.

#     # Creates a preferences hash which most functions pay attention
#     # to. If a CGI.pm object is given, its parameters are used to 
#     # override the defaults. Otherwise, the preferences hash becomes
#     # the default.

#     my ( $cgi,         # CGI.pm object
#          ) = @_;

#     # Returns a hash.

#     my ( $def_params, $params, $key );

#     $params = Ali::Common->default_params;

#     foreach $key ( keys %{ $params } )
#     {
#         if ( $cgi->param( $key ) )
#         {
#             if ( $key =~ /^with_/ ) {
#                 $params->{ $key } = 1;
#             } else {
#                 $params->{ $key } = $cgi->param( $key );
#             }
#         }
#         elsif ( $key =~ /^with_/ ) {
#             $params->{ $key } = 0;
#         }
#     }

#     return $params;
# }
