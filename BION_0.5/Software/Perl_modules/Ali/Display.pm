package Ali::Display;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines in this module all modify the "image" alignment field. They
# paint short-ids, numbers, sequences, features in various ways and use
# the GD graphics library. The "paint_image" is the main routine, and 
# it uses settings from the viewer state to paint in different ways. 
# The configure sets up rendering routines and coordinates, so that is
# always called first. 
#
#   display_center
#   display_zoom_in_area
#   display_zoom_in_pct
#   display_zoom_out
#   paint_image
# 
# Internal helper routines
# ------------------------
# 
# These are used by functions in this module only. Users of this module
# may call them, but they evolve quickly and break the program. 
#
#   _apply_paint
#   _create_image_map
#   _create_paint_generic
#   _create_paint_ali_pairs_covar
#   _create_paint_ali_prot_hydro
#   _create_paint_ali_rna_pairs
#   _create_paint_ali_seq_cons
#   _create_paint_ali_seq_match
#   _create_viewport_from_state
#   _fit_data_to_image
#   _init
#   _init_image 
#   _init_subroutines
#   _paint_data_area
#   _paint_nums_beg              Paints numbers at left edge of image
#   _paint_nums_end              Paints numbers at right edge of image
#   _paint_sids_beg              Paints short-ids at left image edge
#   _paint_sids_end              Paints short-ids at right image edge
#   _reset_zoom
#   _set_gd_colors
#   set_color
#   _set_pix_scales_if_undefined
#   _subref_alipos_to_pixel_global
#   _subref_paint_data
#   _subref_paint_ft_fillrect
#   _subref_paint_text_row
#   _subref_pixel_to_alipos
#   _subref_sidpos_to_pixel

# >>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;
use Time::Local;

use GD;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;

use Ali::DB;
use Ali::Struct;

use base qw ( Ali::Common Registry::Option );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# These global variables are used as subroutine references throughout 
# this module. The configure routine below configures these with closures
# that "remember" settings, colors etc. They are set in the configure 
# routine, which is called before doing any painting. 

our ( $Alipos_to_pixel, $Pixel_to_alipos,
      $Paint_sid_beg_row, $Paint_sid_end_row,
      $Paint_num_beg_row, $Paint_num_end_row,
      $Paint_data_row, $Paint_data_cols,
      $Paint_ft_boldchar, $Paint_ft_fillrect,
      $Sidpos_beg_to_pixel, $Sidpos_end_to_pixel,
 );

# Feature areas constants (TODO ),

use constant FT_COLBEG => 0;
use constant FT_COLEND => 1;
use constant FT_ROWBEG => 2;
use constant FT_ROWEND => 3;
use constant FT_TITLE => 4;
use constant FT_DESCR => 5;
use constant FT_STYLES => 6;
use constant FT_SPOTS => 7;

# The following are index constants to access paint values with. 
# They must match what the _create_paint_* routines generate in this
# module,

use constant PNT_FTNAME => 0;
use constant PNT_TYPE => 1;
use constant PNT_VALUE => 2;
use constant PNT_COLOR => 3;
use constant PNT_TRANS => 4;
use constant PNT_COLBEG => 5;
use constant PNT_COLEND => 6;
use constant PNT_ROWBEG => 7;
use constant PNT_ROWEND => 8;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub display_center
{
    # Niels Larsen, March 2006.

    # Returns a subalignment centered around an x,y pixel coordinate that is clicked 
    # on. It gets the click pixel coordinates, translates them to data coordinates,
    # and calls subali_center to do the slicing. 

    my ( $self,           # Global alignment
         $cols,           # Global column indices
         $rows,           # Global row indices
         $state,          # State hash
         ) = @_;

    # Returns an alignment.

    my ( $subali, $colndx, $rowndx, $x_beg, $x_end, $y_beg, $y_end, $opt,
         $x_pix, $y_pix );

    # The position comes back as a tiny area, but let us find the middle of
    # that area anyway,

    ( $x_beg, $x_end, $y_beg, $y_end ) = split ',', $state->{"ali_image_area"};

    $x_pix = int ( ( $x_beg + $x_end ) / 2 );
    $y_pix = int ( ( $y_beg + $y_end ) / 2 );

    # Initialize routines etc to the existing subalignment,

    $subali = $self->subali_get( $cols, $rows, 
                                 $state->{"ali_prefs"}->{"ali_with_sids"},
                                 $state->{"ali_prefs"}->{"ali_with_nums"} );

    &Ali::Display::_init( $subali, $state );

    ( $colndx, $rowndx ) = $Pixel_to_alipos->( $subali, $x_pix, $y_pix );

    # HACK TODO fix;

    if ( $opt = $state->{"ali_features"}->match_option( "name" => "ali_seq_match" )
         and $opt->selected )
    {
        $state->{"ali_ref_row"} = $rowndx;
    }
    else 
    {
        # Create new alignment starting from (colndx,rowndx),
        
        if ( defined $colndx and defined $rowndx )
        {
            $subali = $self->subali_center( int $colndx, int $rowndx, $state );
        }
    }

    return $subali;
}

sub display_zoom_in_pct
{
    # Niels Larsen, September 2005.

    # Zooms the display in by a given percentage, while keeping the center of 
    # the image in focus. It does this by increasing pixels per row by the given
    # zoom percentage and then gets the subalignment that will fit into the given
    # image size. Too large zoom percentages are reduced so at least 5 columns 
    # of data are shown. Returns a new alignment. 

    my ( $self,        # Original alignment
         $cols,        # Current column indices
         $rows,        # Current row indices
         $state,       # Parameters hash
         ) = @_;

    # Returns alignment object. 

    my ( $colpos, $rowpos, $x, $y, $ratio, $zoom_pct, $subali );

    $subali = $self->subali_get( $cols, $rows, 
                                 $state->{"ali_prefs"}->{"ali_with_sids"},
                                 $state->{"ali_prefs"}->{"ali_with_nums"} );

    &Ali::Display::_init( $subali, $state );

    # >>>>>>>>>>>>>>>>>>>>>> FIND CENTER COLUMN/ROW <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $x = int ( $state->{"ali_prefs"}->{"ali_img_width"} / 2 );
    $y = int ( $state->{"ali_prefs"}->{"ali_img_height"} / 2 );

    ( $colpos, $rowpos ) = $Pixel_to_alipos->( $subali, $x, $y );

    # >>>>>>>>>>>>>>>>>>>>>>> CREATE NEW SUBALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $colpos and defined $rowpos )
    {
        # Set new pixel per column and row settings,

        if ( $state->{"ali_with_col_zoom"} ) {
            $state->{"ali_pix_per_col"} *= ( 100 + $state->{"ali_prefs"}->{"ali_zoom_pct"} ) / 100;
        }
        
        if ( $state->{"ali_with_row_zoom"} ) {
            $state->{"ali_pix_per_row"} *= ( 100 + $state->{"ali_prefs"}->{"ali_zoom_pct"} ) / 100;
        }

        $state = &Ali::Display::_fit_data_to_image( $self, $state );

        # Make sure there are always at least 5 columns shown, and reset zoom
        # percentage as necessary,

        if ( $state->{"ali_data_cols"} < 5 )
        {
            $state->{"ali_data_cols"} = 5;
            
            $zoom_pct = $state->{"ali_prefs"}->{"ali_zoom_pct"};
            $state = &Ali::Display::_reset_zoom( $self, $state );
        }
            
        $subali = $self->subali_center( $colpos, $rowpos, $state );

        if ( defined $zoom_pct ) {
            $state->{"ali_prefs"}->{"ali_zoom_pct"} = $zoom_pct;
        }
    }
    else
    {
        push @{ $state->{"ali_messages"} }, 
        [ "Advice", qq (Alignment is off the display center. Please center )
                  . qq (the alignment by clicking on a spot on the image that should become the center.) ];
    }
    
    return $subali;
}

sub display_zoom_in_area
{
    # Niels Larsen, August 2008.

    # Zooms the display so the data selected by the mouse is shown closer up. 
    # The display may also include surrounding data when the selected area does
    # not have the same aspect ratio as the image selected from. The selected 
    # area enters this routine as "ali_image_area", then the corresponding data 
    # coordinates are found, the scaling ratios calculated and a new subalignment
    # is returned. 

    my ( $self,        # Original alignment
         $cols,        # Current column indices
         $rows,        # Current row indices
         $state,       # Parameters hash
         ) = @_;

    # Returns alignment object. 

    my ( $colpos, $rowpos, $ratio, $subali, $x, $y, $x_beg, $x_end, $y_beg, $y_end,
         $x_min, $x_max, $y_min, $y_max, $x_ratio, $y_ratio, $zoom_pct, $factor,
         $dat_cols );

    $subali = $self->subali_get( $cols, $rows, 
                                 $state->{"ali_prefs"}->{"ali_with_sids"},
                                 $state->{"ali_prefs"}->{"ali_with_nums"} );

    &Ali::Display::_init( $subali, $state );

    # >>>>>>>>>>>>>>>>>>>>>> FIND CENTER COLUMN/ROW <<<<<<<<<<<<<<<<<<<<<<<<<<<

    ( $x_beg, $x_end, $y_beg, $y_end ) = split ',', $state->{"ali_image_area"};

    $x = int ( ( $x_beg + $x_end ) / 2 );
    $y = int ( ( $y_beg + $y_end ) / 2 );

    ( $colpos, $rowpos ) = $Pixel_to_alipos->( $subali, $x, $y );

    # >>>>>>>>>>>>>>>>>>>>>>> CREATE NEW SUBALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $colpos and defined $rowpos )
    {
        # Set new pixel per column and row settings,

        ( $x_min, $y_min ) = $Alipos_to_pixel->( $subali, $subali->min_col_global, $subali->min_row_global ); 
        ( $x_max, $y_max ) = $Alipos_to_pixel->( $subali, $subali->max_col_global, $subali->max_row_global ); 

        $x_ratio = ( $x_max - $x_min ) / ( $x_end - $x_beg );
        $y_ratio = ( $y_max - $y_min ) / ( $y_end - $y_beg );

        $ratio = &Common::Util::min( $x_ratio, $y_ratio );

        $state->{"ali_pix_per_col"} *= $ratio;
        $state->{"ali_pix_per_row"} *= $ratio;

        # INCREDIBLE HACK - compensate for labels .. this whole routine is bad, rethink needed

        $dat_cols = $subali->dat_cols;

        if ( $state->{"ali_prefs"}->{"ali_with_sids"} )
        {
            $factor = $dat_cols / ( $dat_cols + 2 * ( $subali->sid_cols + 2 ) );
            $ratio *= $factor;
        }

        if ( $state->{"ali_prefs"}->{"ali_with_nums"} )
        {
            $factor = $dat_cols / ( $dat_cols + 2 * ( $subali->beg_cols + $subali->end_cols + 2 ) );
            $ratio *= $factor;
        }

        $state = &Ali::Display::_fit_data_to_image( $self, $state );

        # Make sure there are always at least 5 columns shown, and reset zoom
        # percentage as necessary,

        if ( $state->{"ali_data_cols"} < 5 )
        {
            $state->{"ali_data_cols"} = 5;
            
            $zoom_pct = $state->{"ali_prefs"}->{"ali_zoom_pct"};
            $state = &Ali::Display::_reset_zoom( $self, $state );            
        }
            
        $subali = $self->subali_center( $colpos, $rowpos, $state );

        if ( defined $zoom_pct ) {
            $state->{"ali_prefs"}->{"ali_zoom_pct"} = $zoom_pct;
        }
    }
    else
    {
        push @{ $state->{"ali_messages"} }, 
        [ "Advice", qq (Alignment is off the display center. Please center )
                  . qq (the alignment by clicking on a spot on the image that should become the center.) ];
    }
    
    return $subali;
}

sub display_zoom_out
{
    # Niels Larsen, September 2005.

    # Zooms the display out by a given percentage, while keeping the center of the
    # image in focus. It does this by finding the data coordinate of the center and
    # then invoking subali_center. Returns a new alignment. 

    my ( $self,         # Alignment
         $cols,         # Current column indices
         $rows,         # Current row indices
         $state,        # Parameters hash
         ) = @_;

    # Returns alignment object. 

    my ( $colpos, $rowpos, $subali, $x, $y, $pix_mul );

    $subali = $self->subali_get( $cols, $rows, 
                                 $state->{"ali_prefs"}->{"ali_with_sids"},
                                 $state->{"ali_prefs"}->{"ali_with_nums"} );

    &Ali::Display::_init( $subali, $state );

    # Center around middle column / row,

    $x = int ( $state->{"ali_prefs"}->{"ali_img_width"} / 2 );
    $y = int ( $state->{"ali_prefs"}->{"ali_img_height"} / 2 );

    ( $colpos, $rowpos ) = $Pixel_to_alipos->( $subali, $x, $y );

    if ( defined $colpos and defined $rowpos )
    {
        if ( $state->{"ali_with_col_zoom"} ) {
            $state->{"ali_pix_per_col"} /= ( 100 + $state->{"ali_prefs"}->{"ali_zoom_pct"} ) / 100;
        }

        if ( $state->{"ali_with_row_zoom"} ) {
            $state->{"ali_pix_per_row"} /= ( 100 + $state->{"ali_prefs"}->{"ali_zoom_pct"} ) / 100;
        }

        &Ali::Display::_fit_data_to_image( $self, $state );
            
#         if ( $state->{"ali_pix_per_col"} < 1 and $state->{"ali_pix_per_row"} < 1 )
#         {
#             $pix_mul = &Common::Util::max( $state->{"ali_pix_per_col"}, $state->{"ali_pix_per_row"} );

#             $state->{"ali_pix_per_col"} /= $pix_mul;
#             $state->{"ali_pix_per_row"} /= $pix_mul;
#         }

        $subali = $self->subali_center( $colpos, $rowpos, $state );
    }
    else
    {
        push @{ $state->{"ali_messages"} }, 
          [ "Advice", qq (The alignment is off the display center. Please center )
                    . qq (the alignment by clicking on a spot on the image that should become the center.) ];
    }        

    return $subali;
}

sub paint_image
{
    # Niels Larsen, July 2005.

    # Paints a given alignment on an image with features. Short-ids, numbers and
    # sequences are are shown if they have been added to the given alignment object.
    # Features are painted as shades on top of the sequences. Scaling is calculated
    # from the given maximum image height and width, in pixels; image size is fixed 
    # and we fill in as much data as can fit. Characters are used for small 
    # alignments (point size 8 or above), four different kinds of dots for 
    # larger alignments and lines for real big sections. 

    my ( $self,       # Alignment
         $sid,        # Session id
         $dbh,        # Database handle
         $state,      # State - OPTIONAL
         ) = @_;

    my ( $data, $width, $height, $margin, $rgb, $colors,
         $fts, $paint, $routine, $opt, $ft_name, $img_map, @img_map,
         $style, @paint_opts, $nums, $ft_display, $secs );

    # >>>>>>>>>>>>>>>>>>>>>>>>> MAKE PAINTING ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<

    # Before we can paint short-ids, sequences, etc, we need to know where in the
    # image they go. This routine finds out, 

    &Ali::Display::_init( $self, $state );

#    $secs = &Common::Messages::time_start();
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SHORT IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Left short-ids,

    if ( $state->{"ali_prefs"}->{"ali_with_sids"} and defined $self->sids )
    {
        &Ali::Display::_paint_sids_beg( $self, $state );
        &Ali::Display::_paint_sids_end( $self, $state );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> NUMBERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Left and right numbers,

    if ( $state->{"ali_prefs"}->{"ali_with_nums"} )
    {
        &Ali::Display::_paint_nums_beg( $self, $state );
        &Ali::Display::_paint_nums_end( $self, $state );
    }

    # >>>>>>>>>>>>>>>>>>>>> NON-CHARACTER DATA ROWS FIRST <<<<<<<<<<<<<<<<<<<<<<

    # Paint lines etc first, so features painted on top will dim them. 
    # Characters have background, so those are painted after the features 
    # below, to make the characters stand out more. 

    if ( $state->{"ali_pix_per_row"} < 7 or
         $state->{"ali_pix_per_col"} < 4 or
         $state->{"ali_display_type"} ne "characters" )
    {
        &Ali::Display::_paint_data_area( $self, $state );
    }

#    &Common::Messages::time_elapsed( $secs, "paint data" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA FEATURES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $opt ( $state->{"ali_features"}->options )
    {
        if ( $opt->name !~ /_color_dots$/ ) {
            push @paint_opts, $opt;
        }
    }

    foreach $opt ( @paint_opts )
    {
        $ft_name = $opt->name;
#        $ft_display = $opt->display;

        if ( $opt->selected )
        {
            if ( $routine = $opt->routine )
            {
                # >>>>>>>>>>>>>>>>>>>>>> ROUTINE SPECIFIED <<<<<<<<<<<<<<<<<<<<<

                # If routine given with the feature, first pull the features 
                # from database that overlap with the current view, and then
                # call the routine. If the given routine does not exist, then
                # fill in feature colors and use generic routine,

                # >>>>>>>>>>>>>>>>>>>>>>>> GET FEATURES <<<<<<<<<<<<<<<<<<<<<<<<

#                $secs = &Common::Messages::time_start();

                $routine = "get_fts_$ft_name";

                if ( $Ali::DB::{ $routine } ) {
                    $routine = "Ali::DB::$routine";
                } else {
                    $routine = "Ali::DB::get_fts_clip";
                }

                {
                    no strict "refs";
                    $fts = &{ $routine }( $self, $dbh, { "ft_type" => $ft_name } );
                }
                
#                &Common::Messages::time_elapsed( $secs, "get features" );

                if ( $fts and @{ $fts } )
                {
                    # >>>>>>>>>>>>>>>>>>>>>> MAKE PAINT <<<<<<<<<<<<<<<<<<<<<<<<

                    $routine = "_create_paint_$ft_name";
                    
                    if ( $Ali::Display::{ $routine } ) {
                        $routine = "Ali::Display::$routine";
                    } else {
                        $routine = "Ali::Display::_create_paint_generic";
                    }

                    $state->{"ali_ft_desc"} = Registry::Get->feature( $ft_name );

#                    $secs = &Common::Messages::time_start();

                    {
                        no strict "refs";
                        push @{ $paint }, &{ $routine }( $self, $state, $fts );
                    }

#                    &Common::Messages::time_elapsed( $secs, "create paint" );

#                    $secs = &Common::Messages::time_start();

                    delete $state->{"ali_ft_desc"};

                    if ( $state->{"ali_pix_per_row"} > $opt->min_pix_per_row  and
                         $state->{"ali_pix_per_col"} > $opt->min_pix_per_col )
                    {
                        push @img_map, @{ &Ali::Display::_create_image_map( $self, $fts, $state ) };
                    }
                    
#                    &Common::Messages::time_elapsed( $secs, "make map" );
                }
            }
            else
            {
                # >>>>>>>>>>>>>>>>>>>>>> NO ROUTINE GIVEN <<<<<<<<<<<<<<<<<<<<<<

                # We get here when features can just as well be generated at
                # runtime (protein hydrophobicity for example),

                $routine = "_create_paint_$ft_name";

                if ( $Ali::Display::{ $routine } ) {
                    $routine = "Ali::Display::$routine";
                } else {
                    &error( qq (Routine not found -> "Ali::Display::$routine") );
                }
                
                $state->{"ali_ft_desc"} = Registry::Get->feature( $ft_name );

                {
                    no strict "refs";
                    push @{ $paint }, &{ $routine }( $self, $state );
                }
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> MARGIN TEXTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Get short-id texts from database only if magnification is over certain
        # limit, and then create image map with tooltips,

        elsif ( $ft_name eq "ali_sid_text" and 
                $state->{"ali_pix_per_row"} > $opt->min_pix_per_row  and
                $state->{"ali_pix_per_col"} > $opt->min_pix_per_col )
        {
            $fts = &Ali::DB::get_fts( $self, $dbh, { "ft_type" => $ft_name } );
            push @img_map, @{ &Ali::Display::_create_image_map( $self, $fts, $state ) };
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> APPLY FEATURE PAINT <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $paint and @{ $paint } )
    {
#       $secs = &Common::Messages::time_start();

        &Ali::Display::_apply_paint( $self, $paint );
#       &Common::Messages::time_elapsed( $secs, "paint features" );
    }

    # >>>>>>>>>>>>>>>>>>>>>> CHARACTER DATA ROWS LAST <<<<<<<<<<<<<<<<<<<<<<<

    # Paint characters, lines etc last, so it overwrites even features that 
    # are set as non-transparent. This makes the characters stand out more,
    # while the features are still visible in the character backgrounds,

    if ( $state->{"ali_pix_per_row"} >= 7 and 
         $state->{"ali_pix_per_col"} >= 4 and
         $state->{"ali_display_type"} eq "characters" )
    {
#        $secs = &Common::Messages::time_start();
        
        &Ali::Display::_paint_data_area( $self, $state );
#        &Common::Messages::time_elapsed( $secs, "paint data (characters)" );
    }

    if ( @img_map ) {
        return wantarray ? @img_map : \@img_map;
    } else {
        return;
    }
}

# >>>>>>>>>>>>>>>>>>>>>>>>>> INTERNAL ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<

# These are used by functions in this module only. Users of this module
# may call them, but they evolve quickly and break the program. 

sub _apply_paint
{
    # Niels Larsen, January 2006.

    # Paints features on the image, given a list of "paint" elements, created 
    # by the "create_paint*" routines. The the paint elements should have column
    # and row numbers that correspond to the current subalignment, not the 
    # global coordinates on file. The routines that create the "paint" should
    # do the translation between global and local coordinates.

    my ( $self,         # Alignment
         $paint,        # Paint list
         ) = @_;

    # Returns an updated alignment object.

    my ( $elem, $colstr, $colors, $image, $rgb, $subs, $color );

    $image = $self->image;

    $subs = 
    {
        "boldchar" => $Paint_ft_boldchar,
        "fillrect" => $Paint_ft_fillrect,
    };

    foreach $elem ( @{ $paint } )
    {
        $colstr = $elem->[PNT_COLOR];

        if ( not defined ( $color = $colors->{ $colstr } ) )
        {
            $rgb = &Common::Util::hex_to_rgb( $colstr );
            $color = $image->colorAllocateAlpha( @{ $rgb }, $elem->[PNT_TRANS] );

            $colors->{ $colstr } = $color;
        }

        $subs->{ $elem->[PNT_TYPE] }->(
            $image, 
            $elem->[PNT_VALUE], $color, 
            $elem->[PNT_COLBEG], $elem->[PNT_ROWBEG],
            $elem->[PNT_COLEND], $elem->[PNT_ROWEND],
            );
    }

    $self->image( $image );

    return $self;
}

sub _create_image_map
{
    # Niels Larsen, March 2006.
    
    # Creates a list of [ shape, "xbeg,ybeg,xend,yend", title, text ] to be
    # formatted and used as client side image map. 

    my ( $self,        # Alignment object
         $fts,         # Feature list
         $state,       # State hash
         ) = @_;

    # Returns a list.

    my ( $mincol, $maxcol, $minrow, $maxrow, $ft, $title, $descr,
         @map, $colbeg, $colend, $rowbeg, $rowend, $xbeg, $ybeg, $xend,
         $yend, $pix_per_col, $pix_per_row, $cols, $col_collapse, $sid_maxcol,
         $ft_colbeg, $ft_colend, $ft_rowbeg, $ft_rowend, $area );

    $mincol = $self->global_col( 0 );
    $maxcol = $self->max_col_global;
    $minrow = $self->global_row( 0 );
    $maxrow = $self->max_row_global;

    $sid_maxcol = $self->sid_len - 1;

    $pix_per_col = $state->{"ali_pix_per_col"};
    $pix_per_row = $state->{"ali_pix_per_row"};

    $col_collapse = $state->{"ali_prefs"}->{"ali_with_col_collapse"};

    $cols = [ $self->_orig_cols->list ] if $col_collapse;

    foreach $ft ( @{ $fts } )
    {
        foreach $area ( @{ $ft->areas } )
        {
            $rowbeg = &Common::Util::max( $minrow, $area->[FT_ROWBEG] );
            $rowend = &Common::Util::min( $maxrow, $area->[FT_ROWEND] );

            $title = $area->[FT_TITLE];
            $descr = $area->[FT_DESCR];

            if ( $ft->type eq "ali_sid_text" )
            {
                ( $xbeg, $ybeg ) = $Sidpos_beg_to_pixel->( $self, 0, $rowbeg );
                ( $xend, $yend ) = $Sidpos_beg_to_pixel->( $self, $sid_maxcol, $rowend );
                
                $xbeg -= $pix_per_col - 1;
                $ybeg -= $pix_per_row - 1;

                $xbeg = int $xbeg;
                $ybeg = int $ybeg;

                push @map, [ "rect", "$xbeg,$ybeg,$xend,$yend", $title, $descr ];
            }
            else
            {
                $ft_colbeg = $area->[FT_COLBEG];
                $ft_colend = $area->[FT_COLEND];
            
                # This if condition is there because there are "double features" like 
                # helix pairings, where one half may be outside the picture. Should 
                # reconsider this idea .. 

                if ( &Common::Util::ranges_overlap( $mincol, $maxcol, $ft_colbeg, $ft_colend ) and
                     &Common::Util::ranges_overlap( $minrow, $maxrow, $rowbeg, $rowend ) )
                {
                    $colbeg = &Common::Util::max( $mincol, $ft_colbeg );
                    $colend = &Common::Util::min( $maxcol, $ft_colend );
                
                    if ( $col_collapse )
                    {
                        $colbeg = $cols->[ &Common::Util::binary_search_numbers( $cols, $colbeg, 0 ) ];
                        $colend = $cols->[ &Common::Util::binary_search_numbers( $cols, $colend, 1 ) ];
                    }
                    
                    ( $xbeg, $ybeg ) = $Alipos_to_pixel->( $self, $colbeg, $rowbeg );
                    ( $xend, $yend ) = $Alipos_to_pixel->( $self, $colend, $rowend );
 
                    if ( defined $xbeg and defined $ybeg and 
                         defined $xend and defined $yend )
                    {
                        $xbeg -= $pix_per_col - 1;
                        $ybeg -= $pix_per_row - 1;
                        
                        $xbeg = int $xbeg;
                        $ybeg = int $ybeg;
                        
                        push @map, [ "rect", "$xbeg,$ybeg,$xend,$yend", $title, $descr ];
                    }
                }
            }
        }
    }

    return wantarray ? @map : \@map;
}

sub _create_paint_generic
{
    # Niels Larsen, February 2006.

    # Generates "generic paint" where there is no calculations done.

    my ( $self,       # Alignment
         $state,      # Parameters hash
         $fts,        # Features list
         ) = @_;

    # Returns a list.

    my ( $ft, $styles, $style, $colors, $color, @paint, $colbeg, $colend,
         $rowbeg, $rowend, $colmin, $colmax, $rowmin, $rowmax, $trans,
         $area, $spots, $spot, $l_colbeg, $l_colend, $l_rowbeg, $score,
         $l_rowend, $bgcolor, @l_cols, @l_rows );

    # Get min and max column row index of current alignment section,

    $colmin = $self->min_col_global;
    $colmax = $self->max_col_global;

    $rowmin = $self->min_row_global;
    $rowmax = $self->max_row_global;

    $style = $state->{"ali_ft_desc"}->display->style;

    ( $bgcolor, $trans ) = ( $style->{"bgcolor"}, $style->{"bgtrans"} );

    if ( ref $bgcolor ) {
        $colors = &Common::Util::color_ramp( @{ $bgcolor }, 101 );
    } else {
        $colors = &Common::Util::color_ramp( $bgcolor, $bgcolor, 101 );
    }

    @l_cols = $self->local_cols;
    @l_rows = $self->local_rows;

    foreach $ft ( @{ $fts } )
    {
        foreach $area ( @{ $ft->areas } )
        {
            if ( &Common::Util::ranges_overlap( $colmin, $colmax, 
                                                $area->[FT_COLBEG], $area->[FT_COLEND] ) )
            {
                if ( $styles = eval $area->[FT_STYLES] )
                {
                    $color = $styles->{"bgcolor"} || "";
                    $trans = $styles->{"bgtrans"} || "";
                }
                else
                {
                    $color = $colors->[100];
                }

                if ( $area->[FT_SPOTS] )
                {
                    $spots = eval $area->[FT_SPOTS];

                    foreach $spot ( @{ $spots } )
                    {
                        if ( &Common::Util::ranges_overlap( $colmin, $colmax, 
                                                            $spot->[FT_COLBEG], $spot->[FT_COLEND] ) )
                        {
                            $colbeg = &Common::Util::max( $colmin, $spot->[FT_COLBEG] );
                            $colend = &Common::Util::min( $colmax, $spot->[FT_COLEND] );
                            
                            $rowbeg = &Common::Util::max( $rowmin, $spot->[FT_ROWBEG] );
                            $rowend = &Common::Util::min( $rowmax, $spot->[FT_ROWEND] );

                            $l_colbeg = $l_cols[ $colbeg ];
                            $l_colend = $l_cols[ $colend ];
                            
                            $l_rowbeg = $l_rows[ $rowbeg ];
                            $l_rowend = $l_rows[ $rowend ];

                            push @paint, [ $ft->type, "fillrect", undef, $color, $trans, $l_colbeg, $l_colend, $l_rowbeg, $l_rowend ];
                        }
                    }
                }
                else
                {
                    # Trim the feature positions so they are within section, 
                    # and translate to local coordinates,

                    $colbeg = &Common::Util::max( $colmin, $area->[FT_COLBEG] );
                    $colend = &Common::Util::min( $colmax, $area->[FT_COLEND] );
                    
                    $rowbeg = &Common::Util::max( $rowmin, $area->[FT_ROWBEG] );
                    $rowend = &Common::Util::min( $rowmax, $area->[FT_ROWEND] );

                    $l_colbeg = $l_cols[ $colbeg ];
                    $l_colend = $l_cols[ $colend ];
                    
                    $l_rowbeg = $l_rows[ $rowbeg ];
                    $l_rowend = $l_rows[ $rowend ];

                    push @paint, [ $ft->type, "fillrect", undef, $color, $trans, $l_colbeg, $l_colend, $l_rowbeg, $l_rowend ];
                }
            }
        }
    }

    return wantarray ? @paint : \@paint;
}

sub _create_paint_ali_pairs_covar
{
    # Niels Larsen, February 2006.

    # Generates "covariation paint" that when rendered will highlight columns 
    # involved in pairings according to how strongly they covary with the column
    # to which they are paired. Highly scoring columns have light green 
    # background, and the background is graded for lesser scores. Returns a 
    # list of instructions to graphics rendering routine.

    my ( $self,       # Alignment
         $state,      # Parameters hash
         $fts,        # Features list
         ) = @_;

    # Returns a list.

    my ( $colors, $color, %colors, $max_row, $char, $lcol, $chars, $row, $begrow,
         $ft, $seqs, $stat_chars, @paint, $score, $valid_chars, $min_score, $endrow, 
         $lmax_row, $minrow, $maxrow, $ft_colbeg, $area, $style, $bgtrans, $ft_desc );

    $seqs = $self->seqs;

    $ft_desc = $state->{"ali_ft_desc"}->display;

    $style = $ft_desc->style;
    $bgtrans = $style->{"bgtrans"};
    $min_score = $ft_desc->min_score;

    # Make color ramp and get alphabet,

    $colors = &Common::Util::color_ramp( @{ $style->{"bgcolor"} }, 101 );

    $valid_chars = { map { $_, 1 } split "", $self->alphabet_paint };

    $lmax_row = $self->max_row;

    foreach $ft ( @{ $fts } )
    {
        next if $ft->score < $min_score;

        foreach $area ( @{ $ft->areas } )
        {
            if ( defined ( $lcol = $self->local_col( $area->[FT_COLBEG] ) ) )
            {
                $score = int 100 * $ft->score;
                next if $score < $min_score;

                if ( not defined ( $minrow = $self->local_row( $area->[FT_ROWBEG] ) ) ) {
                    $minrow = 0;
                }

                if ( not defined ( $maxrow = $self->local_row( $area->[FT_ROWEND] ) ) ) {
                    $maxrow = $lmax_row;
                }
                
                $chars = ${ $seqs->slice( "($lcol),$minrow:$maxrow" )->get_dataref };
                
                $row = $minrow;
                
                while ( $row <= $maxrow )
                {
                    if ( $valid_chars->{ substr $chars, $row-$minrow, 1 } )
                    {
                        $begrow = $row;
                        $row += 1;
                        
                        while ( $row <= $maxrow and $valid_chars->{ substr $chars, $row-$minrow, 1 } )
                        {
                            $row += 1;
                        }
                        
                        $endrow = $row - 1;
                        
                        push @paint, [ $ft->type, "fillrect", undef, $colors->[ $score ], $bgtrans, $lcol, $lcol, $begrow, $endrow ];
                    }
                    else {
                        $row += 1;
                    }
                }
            }
        }
    }
    
    return wantarray ? @paint : \@paint;
}

sub _create_paint_ali_prot_hydro
{
    # Niels Larsen, February 2006.

    # Generates "hydrophobicity paint" that when rendered will highlight columns 
    # according to how hydrophobic they are. The most hydrophobic residues have
    # red background, and the colors are graded into the blue for hydrophilic 
    # residues. Returns a list of instructions to graphics rendering routine.

    my ( $self,       # Alignment
         $state,     # Parameters hash
         ) = @_;

    # Returns a list.

    my ( $seqs, $colors, $valid_chars, $max_row, $max_col, $col, $chars,
         $refchar, $row, @paint, $begrow, $endrow, $colstr, $trans );

    $seqs = $self->seqs;

    $colors = &Ali::Display::set_colors_hydrophobicity( $self );
    $valid_chars = { map { $_, 1 } split "", $self->alphabet_paint };

    $max_row = $self->max_row;
    $max_col = $self->max_col;

    if ( $state->{"ali_pix_per_row"} >= 7 ) {
        $trans = 93;
    } else {
        $trans = 85;
    }

    for ( $col = 0; $col <= $max_col; $col++ )
    {
        $chars = ${ $seqs->slice( "($col),:" )->get_dataref };

        $row = 0;

        while ( $row <= $max_row )
        {
            $refchar = substr $chars, $row, 1;

            if ( $valid_chars->{ $refchar } )
            {
                $colstr = @{ $colors->{ $refchar } }[0];

                $begrow = $row;
                $row += 1;

                while ( $row <= $max_row and $refchar eq substr $chars, $row, 1 )
                {
                    $row += 1;
                }

                $endrow = $row - 1;
                
                push @paint, [ "ali_prot_hydro", "fillrect", undef, $colstr, $trans, $col, $col, $begrow, $endrow ];
            }
            else {
                $row += 1;
            }
        }
    }

    return wantarray ? @paint : \@paint;
}

sub _create_paint_ali_rna_pairs
{
    # Niels Larsen, February 2006.

    # Generates "pairing paint" that when rendered will highlight bases involved 
    # in pairings. Only the columns involved are stored database, pairs and mispairs 
    # are found on the fly, and WC + GU are highlighted the rest not. Returns a list 
    # graphics rendering instructions that the paint_* routines in this module 
    # understand.

    my ( $self,       # Alignment
         $state,      # Parameters hash
         $fts,        # Feature list
         ) = @_;

    # Returns a list.

    my ( $seqs, $orig_seqs, $trans, $char, $chars5, $chars3, $type, $area5, $area3,
         $is_pair, $pairs, $pair, $col5, $col3, $colbeg5, $colbeg3, $colend5, $lcol5,
         $lcol3, $paint5, $paint3, $ft, $i, @paint, $lcols, $ft_id, $row, $begrow,
         $styles, $style, $orig_ali, $endrow, $minrow, $maxrow, $lmin_row, $lmax_row,
         $color5, $color3, $ft_desc );

    $seqs = $self->seqs;

    $orig_ali = $self->orig_ali;
    $orig_seqs = $orig_ali->subali_get( undef, $self->_orig_rows )->seqs;

    $ft_desc = $state->{"ali_ft_desc"}->display;

    # Transparency,

    $style = $ft_desc->style;
    $trans = $style->{"bgtrans"};

    # To find and highlight pairs on the fly, we may need access to data that are 
    # not in the current subalignment,
    # Some column ranges now overlap the subalignment ($self), others dont. For those
    # that do, get the column from there and create paint, otherwise from global 
    # alignment. 

    $lcols = { map { $_, $i++ } $self->_orig_cols->list };

    $is_pair = &Ali::Struct::is_pair_hash_gu();
    
    $lmin_row = 0;
    $lmax_row = $self->max_row;

    foreach $ft ( @{ $fts } )
    {
        ( $area5, $area3 ) = @{ $ft->areas };

        $colbeg5 = $area5->[FT_COLBEG];
        $colend5 = $area5->[FT_COLEND];
        
        $minrow = $self->local_row( $area5->[FT_ROWBEG] );
        $minrow = $lmin_row if not defined $minrow;
        
        $maxrow = $self->local_row( $area5->[FT_ROWEND] );
        $maxrow = $lmax_row if not defined $maxrow;

        $col3 = $area3->[FT_COLEND];

        $styles = eval $area5->[FT_STYLES];
        $color5 = $styles->{"bgcolor"};

        $styles = eval $area3->[FT_STYLES];
        $color3 = $styles->{"bgcolor"};

        for ( $col5 = $colbeg5; $col5 <= $colend5; $col5++ )
        {
            if ( exists $lcols->{ $col5 } or exists $lcols->{ $col3 } )
            {
                if ( defined ( $lcol5 = $lcols->{ $col5 } ) ) {
                    $chars5 = ${ $seqs->slice( "($lcol5),:" )->get_dataref };
                    $paint5 = 1;
                } else {
                    $chars5 = ${ $orig_seqs->slice( "($col5),:" )->get_dataref };
                    $paint5 = 0;
                }
                
                if ( defined ( $lcol3 = $lcols->{ $col3 } ) ) {
                    $chars3 = ${ $seqs->slice( "($lcol3),:" )->get_dataref };
                    $paint3 = 1;
                } else {
                    $chars3 = ${ $orig_seqs->slice( "($col3),:" )->get_dataref };
                    $paint3 = 0;
                }

                $row = $minrow;

                while ( $row <= $maxrow )
                {
                    if ( $is_pair->{ substr $chars5, $row, 1 }->{ substr $chars3, $row, 1 } )
                    {
                        $begrow = $row;
                        $row += 1;

                        while ( $row <= $maxrow and $is_pair->{ substr $chars5, $row, 1 }->{ substr $chars3, $row, 1 } )
                        {
                            $row += 1;
                        }
                        
                        $endrow = $row - 1;

                        if ( $paint5 ) {
                            push @paint, [ $ft->type, "fillrect", undef, $color5, $trans, $lcol5, $lcol5, $begrow, $endrow ];
                        }
                        
                        if ( $paint3 ) {
                            push @paint, [ $ft->type, "fillrect", undef, $color3, $trans, $lcol3, $lcol3, $begrow, $endrow ];
                        }
                    }
                    else {
                        $row += 1;
                    }
                }
            }

            $col3 -= 1;
        }
    }

    return wantarray ? @paint : \@paint;
}

sub _create_paint_ali_seq_cons
{
    # Niels Larsen, February 2006.

    # Generates "conservation paint" that when rendered will highlight columns 
    # according to how conserved they are. Highly conserved residues has red 
    # background, and the colors are graded for less conserved residues. Returns
    # a list of instructions to the graphics rendering routine.

    my ( $self,       # Alignment
         $state,      # Parameters hash
         $fts,        # Features list
         ) = @_;

    # Returns a list.

    my ( $colors, $color, %colors, $max_row, $max_pct, $char, $col, $chars, $refchar,
         $ft, $seqs, $counts, $sum, $i, $min_pct, $stat_chars, @paint, $ft_colbeg,
         $cons_pcts, $cons_pct, $valid_chars, $row, $begrow, $endrow, $style, 
         $bgtrans, $min_score, $max_score, $ft_desc, $score );

    $seqs = $self->seqs;
    $ft_desc = $state->{"ali_ft_desc"}->display;

    # Get color settings from registry,

    $style = $ft_desc->style;
    $bgtrans = $style->{"bgtrans"};

    $min_score = $ft_desc->min_score;
    $max_score = $ft_desc->max_score;

    # Make color ramp and get alphabet,
    
    $colors = &Common::Util::color_ramp( @{ $style->{"bgcolor"} }, 101 );
    
    $stat_chars = [ split "", $self->alphabet_stats ];
    $valid_chars = { map { $_, 1 } split "", $self->alphabet_paint };

    $max_row = $self->max_row;

    $sum = $self->orig_ali->max_row + 1;

    foreach $ft ( @{ $fts } )
    {
        $score = $ft->score;
        next if $score < $min_score or $score > $max_score;
        
        $ft_colbeg = $ft->areas()->[0]->[0];

        if ( defined ( $col = $self->local_col( $ft_colbeg ) ) )
        {
            $counts = eval $ft->stats;
#            $sum = &Common::Util::sum( $counts );

            undef $cons_pcts;
            
            for ( $i = 0; $i <= $#{ $counts }; $i++ )
            {
                $char = $stat_chars->[$i];
                $cons_pct = 100 * $counts->[$i] / $sum; 

                if ( $valid_chars->{ $char } )
                {
                    $cons_pcts->{ $char } = $cons_pct; 
                    $cons_pcts->{ lc $char } = $cons_pct; 
                }
            }
            
            $chars = ${ $seqs->slice( "($col),:" )->get_dataref };

            $row = 0;

            while ( $row <= $max_row )
            {
                if ( defined ( $cons_pct = $cons_pcts->{ substr $chars, $row, 1 } ) )
                {
                    $begrow = $row;
                    $refchar = substr $chars, $row, 1;

                    $row += 1;
                    
                    while ( $row <= $max_row and $refchar eq substr $chars, $row, 1 )
                    {
                        $row += 1;
                    }
                    
                    $cons_pct = $cons_pcts->{ $refchar };
                    $endrow = $row - 1;

                    push @paint, [ $ft->type, "fillrect", undef, $colors->[ 100-$cons_pct ], $bgtrans, 
                                   $col, $col, $begrow, $endrow ];
                }
                else {
                    $row += 1;
                }
            }
        }
    }

    return wantarray ? @paint : \@paint;
}

sub _create_paint_ali_seq_match
{
    # Niels Larsen, September 2007.

    # Highlights bases or residues that are identical to those in a given
    # reference sequence in the same column.

    my ( $self,       # Alignment
         $state,      # Parameters hash
         ) = @_;
    
    # Returns a list.

    my ( $seqs, $valid_chars, $max_row, $max_col, $col, $chars, $row, 
         @paint, $begrow, $endrow, $colstr, $bgtrans, $style, $ref_row, 
         $orig_cols, $ref_chars, $ref_char, $char, $is_match );

    $seqs = $self->seqs;

    $style = $state->{"ali_ft_desc"}->display->style;
    $colstr = $style->{"bgcolor"}->[0];

    $bgtrans = $style->{"bgtrans"};

    $valid_chars = { map { $_, 1 } split "", $self->alphabet_paint };
    $is_match = $self->is_match_hash();

    $ref_row = $state->{"ali_ref_row"} || 0;
    $ref_chars = $self->orig_ali->subali_get( $self->_orig_cols, [ $ref_row ] )->seq_string( 0 );

    $max_row = $self->max_row;
    $max_col = $self->max_col;

    for ( $col = 0; $col <= $max_col; $col++ )
    {
        $chars = ${ $seqs->slice( "($col),:" )->get_dataref };
        $ref_char = substr $ref_chars, $col, 1;

        next if not $valid_chars->{ $ref_char };

        $row = 0;

        while ( $row <= $max_row )
        {
            $char = substr $chars, $row, 1;

            if ( $valid_chars->{ $char } and $is_match->{ $char }->{ $ref_char } )
            {
                $begrow = $row;
                $row += 1;

                while ( $row <= $max_row and $is_match->{ $ref_char }->{ substr $chars, $row, 1 } )
                {
                    $row += 1;
                }

                $endrow = $row - 1;
                
                push @paint, [ "ali_seq_match", "fillrect", undef, $colstr, $bgtrans, $col, $col, $begrow, $endrow ];
            }
            else {
                $row += 1;
            }
        }
    }

    return wantarray ? @paint : \@paint;
}

sub _create_viewport_from_state
{
    # Niels Larsen, July 2005.

    # Returns layout coordinates in local data coordinates. The routine 
    # _pixel_coordinates transforms this to pixel positions in the
    # image coordinate system. 

    my ( $self,      # Alignment
         $state,    # Parameters, same as for render_graphics
         ) = @_;

    # Returns a hash. 

    my ( $viewport, $maxrow, $icol, $irow, $maxlen, $nums, $cols, $rows );

    # Set clipping values if not defined; this means center the image if the 
    # whole alignment fits into view, otherwise show subalignment starting at 
    # upper left corner,

    $maxrow = $self->max_row;

#     if ( not defined $state->{"ali_clipping"} )
#     {
#         $state->{"ali_clipping"} = {
#             "left" => 0,
#             "top" => 0,
#             "bottom" => 0,
#             "right" => 0,
#         };
#     }

    $icol = &Common::Util::max( 0, - $state->{"ali_clipping"}->{"left"} || 0 );
    $irow = &Common::Util::max( 0, - $state->{"ali_clipping"}->{"top"} || 0 );

    # --- Short ids to the left of sequences,
    
    if ( defined $self->sids and $state->{"ali_prefs"}->{"ali_with_sids"} )
    {
        $icol += 1 if $icol > 0;
        $maxlen = ( $self->sids->dims )[0];
        
        $viewport->{"sids_beg"}->{"mincol"} = $icol;
        $viewport->{"sids_beg"}->{"maxcol"} = $icol + $maxlen - 1;
        $viewport->{"sids_beg"}->{"minrow"} = $irow;
        $viewport->{"sids_beg"}->{"maxrow"} = $maxrow;

        $icol += $maxlen;
    }
    
    # --- Sequence numbers, left edge,
    
    if ( defined $self->begs )
    {
        $icol += 1 if $icol > 0;
        $maxlen = ( $self->begs->dims )[0];
        
        $viewport->{"nums_beg"}->{"mincol"} = $icol;
        $viewport->{"nums_beg"}->{"maxcol"} = $icol + $maxlen - 1;
        $viewport->{"nums_beg"}->{"minrow"} = $irow;
        $viewport->{"nums_beg"}->{"maxrow"} = $maxrow;

        $icol += $maxlen;
    }
    
    # --- Data,
    
    if ( defined $self->seqs )
    {
        $icol += 1 if $icol > 0;
        $maxlen = $self->max_col + 1;
        
        $viewport->{"data"}->{"mincol"} = $icol;
        $viewport->{"data"}->{"maxcol"} = $icol + $maxlen - 1;
        $viewport->{"data"}->{"minrow"} = $irow;
        $viewport->{"data"}->{"maxrow"} = $maxrow;

        $icol += $maxlen;
    }
    
    # --- Sequence numbers, right edge,
    
    if ( defined $self->ends )
    {
        $icol += 1 if $icol > 0;
        $maxlen = ( $self->ends->dims )[0];
        
        $viewport->{"nums_end"}->{"mincol"} = $icol;
        $viewport->{"nums_end"}->{"maxcol"} = $icol + $maxlen - 1;
        $viewport->{"nums_end"}->{"minrow"} = $irow;
        $viewport->{"nums_end"}->{"maxrow"} = $maxrow;

        $icol += $maxlen;
    }
    
    # --- Short-ids to the right of sequences,
    
    if ( defined $self->sids and $state->{"ali_prefs"}->{"ali_with_sids"} )
    {
        $icol += 1 if $icol > 0;
        $maxlen = ( $self->sids->dims )[0];
        
        $viewport->{"sids_end"}->{"mincol"} = $icol;
        $viewport->{"sids_end"}->{"maxcol"} = $icol + $maxlen - 1;
        $viewport->{"sids_end"}->{"minrow"} = $irow;
        $viewport->{"sids_end"}->{"maxrow"} = $maxrow;

        $icol += $maxlen;
    }
    
    return $viewport;
}

sub _fit_data_to_image
{
    # Niels Larsen, September 2005.

    # Finds how much data will fit into an image: given an image width and height
    # ("ali_img_width" and "ali_img_height") and a number of pixels per row 
    # ("ali_pix_per_row"), finds the max number of characters that will fit into 
    # that space, given the current resolution. If the resolution (pixels per row)
    # is not defined, the routine sets it to something reasonable first. 

    my ( $self,      # Alignment
         $state,     # State hash
         ) = @_;

    # Returns an updated state hash.

    my ( $font, $size, $cols, $bounds, $string, $maxcols, $maxrows, $clip, 
         $prefs );

    $prefs = $state->{"ali_prefs"};

    # Set "ali_pix_per_col" and "ali_pix_per_row" if either is not defined,

    $state = &Ali::Display::_set_pix_scales_if_undefined( $self, $state );

    # TEMPORARY 

    if ( defined $state->{"ali_start_width"} )
    {
        $cols = $state->{"ali_start_width"};

        if ( $prefs->{"ali_with_sids"} ) {
            $cols += 2 * $self->sid_len + 2;
        }

        if ( $prefs->{"ali_with_nums"} ) {
            $cols += $self->beg_cols + $self->end_cols + 2;
        }

        $state->{"ali_pix_per_col"} = $prefs->{"ali_img_width"} / $cols;
        $state->{"ali_pix_per_row"} = 1.15 * $state->{"ali_pix_per_col"} / $state->{"ali_font_scale"};
    }

    # Set number of columns,

    $cols = int $prefs->{"ali_img_width"} / $state->{"ali_pix_per_col"};

    if ( $prefs->{"ali_with_sids"} ) {
        $cols -= 2 * ( $self->sid_len + 1 );
    }

    if ( $prefs->{"ali_with_nums"} ) {
        $cols -= $self->beg_cols + $self->end_cols + 2;
    }
    
    $state->{"ali_data_cols"} = $cols;

    # Set number of rows,

    $state->{"ali_data_rows"} = int $prefs->{"ali_img_height"} / $state->{"ali_pix_per_row"};

    # Set clipping if not defined,

    if ( not defined $state->{"ali_clipping"} )
    {
        $maxcols = $self->max_col + 1;
        $maxrows = $self->max_row + 1;

        if ( $state->{"ali_data_cols"} > $maxcols )
        {
            $clip->{"left"} = - int ( $state->{"ali_data_cols"} - $maxcols ) / 2;
            $clip->{"right"} = $clip->{"left"};
        }
        
        if ( $state->{"ali_data_rows"} > $maxrows )
        {
            $clip->{"top"} = - int ( $state->{"ali_data_rows"} - $maxrows ) / 2;
            $clip->{"bottom"} = $clip->{"top"};
        }
        
        $state->{"ali_clipping"} = $clip;
    }
    
    return $state;
}

sub _init
{
    # Niels Larsen, January 2006.

    # Creates an empty image and a set of global rendering functions 
    # that know colors and how to go from data coordinates to pixels.
    # They are declared in the GLOBALS section above. 

    my ( $self,       # Alignment
         $state,      # Alignment parameters / state
         ) = @_;

    # Returns nothing.

    my ( $width, $height, $bgcolor, $image );

    # >>>>>>>>>>>>>>>>>>>>> INITIALIZE IMAGE <<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Create an empty image with the GD library that is truecolor, 
    # alphablended, interlaced, and of the given width, height and 
    # background color, read to be painted on. But only if it was 
    # not created already (certain routines do that to be able to 
    # translate between data and pixel coordinates),

    if ( not $self->image ) 
    {
        $width = int $state->{"ali_prefs"}->{"ali_img_width"};
        $height = int $state->{"ali_prefs"}->{"ali_img_height"};
        $bgcolor = $state->{"ali_bg_color"};

        $image = &Ali::Display::_init_image( $self, $width, $height, $bgcolor );
        
        $self->image( $image );
    }

    # >>>>>>>>>>>>>>>>>> CONFIGURE PAINT ROUTINES <<<<<<<<<<<<<<<<<<<<

    # Creates a number of paint and positioning routines as global 
    # variables in this module, call $Paint_data_row etc (see GLOBALS
    # section at the top). These routines "knows" colors and how to 
    # translate between incoming data coordinates and pixels. For 
    # example, 
    # 
    # $Paint_num_end_row->( $image, 12, "349   " );
    # 
    # would know how to paint "349   " in row 12 in the given image.
    # The individual routine-creating routines start with "_subref"
    # and the routines created are used in the routines that start 
    # with "paint_".

    &Ali::Display::_init_subroutines( $self, $state );

    return $self;
}

sub _init_image
{
    # Niels Larsen, January 2006.

    # Returns an empty image with a given width, height and background 
    # color. It is using truecolor, alphablending and is interlaced. 

    my ( $class,         # Class name
         $width,         # Width in pixels - OPTIONAL, default 800
         $height,        # Height in pixels - OPTIONAL, default 500
         $bgcolor,       # Background color string - OPTIONAL, default "#CCCCCC"
         ) = @_;

    # Returns a GD image object.

    my ( $image, $rgb, $gd_color );

    $image = GD::Image->new( $width, $height, 1 );

    $image->trueColor( 1 );
    $image->alphaBlending( 1 );
#    $image->saveAlpha( 1 );

    $rgb = &Common::Util::hex_to_rgb( $bgcolor );
    $gd_color = $image->colorAllocateAlpha( @{ $rgb }, 0 );

    $image->filledRectangle( 0, 0, $width-1, $height-1, $gd_color );
#    $image->interlaced( 'true' );

    return $image;
}

sub _init_subroutines
{
    # Niels Larsen, February 2006.

    # Creates a set of subroutines that "knows" where in the image to paint,
    # and how to go between data and image coordinates. This knowledge comes
    # from closures, that remember the scaling information. The subroutine
    # references are assigned to the globals defined in the top of this file,
    # so they can be used anywhere. 

    my ( $self,          # Alignment
         $state,         # State hash
         ) = @_;

    # Returns unchanged alignment object.

    my ( $width, $image, $height, $rgb, $viewport, $col_scale,
         $row_scale, $margin, $font_bold, $font_normal, $font_size, $res,
         $color_sids, $color_nums, $color_data, $color_gap, $color_out,
         $args );

    $image = $self->image();

    # EXPLAIN 

    $viewport = &Ali::Display::_create_viewport_from_state( $self, $state );

    # Scale factors between data columns and rows and pixels,

    $col_scale = $state->{"ali_pix_per_col"};
    $row_scale = $state->{"ali_pix_per_row"};

    $margin = 0; # &Common::Util::max( $row_scale, 5 ) * $state->{"ali_font_scale"};

    # Fonts and colors used,

    $font_bold = $state->{"ali_font_bold"};
    $font_normal = $state->{"ali_font_normal"};
    
    $font_size = $state->{"ali_pix_per_row"} * $state->{"ali_font_scale"};

    $rgb = &Common::Util::hex_to_rgb( $state->{"ali_sid_color"} );
    $color_sids = $image->colorAllocateAlpha( @{ $rgb }, 0 );

    $rgb = &Common::Util::hex_to_rgb( $state->{"ali_num_color"} );
    $color_nums = $image->colorAllocateAlpha( @{ $rgb }, 0 );

    $color_data = $image->colorAllocateAlpha( 50, 50, 50, 0 );

    $rgb = &Common::Util::hex_to_rgb( $state->{"ali_gap_color"} );
    $color_gap = $image->colorAllocateAlpha( @{ $rgb }, 0 );

    # >>>>>>>>>>>>>>>>>>>> CREATE SUBROUTINES <<<<<<<<<<<<<<<<<<<<<<<

    # The following are painting routine references that know where
    # on the image to paint when given data coordinates. 

    $args = { "size" => $font_size, 
              "margin" => $margin,
              "col_scale" => $col_scale,
              "row_scale" => $row_scale,
              "viewport" => $viewport->{"data"},
          };

    if ( defined ( $res = $state->{"ali_resolution"} ) ) {
        $args->{"resolution"} = $res;
    }

    $Alipos_to_pixel = &Ali::Display::_subref_alipos_to_pixel_global( $self, $args );
    $Pixel_to_alipos = &Ali::Display::_subref_pixel_to_alipos( $self, $args );

    # Short ids, left side,

    if ( defined $self->sids and $state->{"ali_prefs"}->{"ali_with_sids"} )
    {
        $args->{"viewport"} = $viewport->{"sids_beg"};
        $args->{"font"} = $font_bold;
        $args->{"color"} = $color_sids;
        $args->{"indent"} = $state->{"ali_sid_left_indent"};

        $Paint_sid_beg_row = &Ali::Display::_subref_paint_text_row( $self, $args );
        $Sidpos_beg_to_pixel = &Ali::Display::_subref_sidpos_to_pixel( $self, $args );
    }

    # Numbers, left side,

    if ( defined $self->begs and $state->{"ali_prefs"}->{"ali_with_nums"} )
    {
        $args->{"viewport"} = $viewport->{"nums_beg"};
        $args->{"font"} = $font_normal;
        $args->{"color"} = $color_nums;
        $args->{"indent"} = "right";
        
        $Paint_num_beg_row = &Ali::Display::_subref_paint_text_row( $self, $args );
    }

    # Data,

    $args->{"viewport"} = $viewport->{"data"};
    $args->{"font"} = $font_normal;
    $args->{"color"} = $color_data;
    $args->{"color_gap"} = $color_gap;
    $args->{"display_type"} = $state->{"ali_display_type"};

    ( $Paint_data_row, $Paint_data_cols ) = &Ali::Display::_subref_paint_data( $self, $args );

    # Numbers, right side,

    if ( defined $self->ends and $state->{"ali_prefs"}->{"ali_with_nums"} )
    {
        $args->{"viewport"} = $viewport->{"nums_end"};
        $args->{"font"} = $font_normal;
        $args->{"color"} = $color_nums;
        $args->{"indent"} = $state->{"ali_sid_right_indent"};
        
        $Paint_num_end_row = &Ali::Display::_subref_paint_text_row( $self, $args );
    }

    # Short ids, right side,

    if ( defined $self->sids and $state->{"ali_prefs"}->{"ali_with_sids"} )
    {
        $args->{"viewport"} = $viewport->{"sids_end"};
        $args->{"font"} = $font_bold;
        $args->{"color"} = $color_sids;
        $args->{"indent"} = $state->{"ali_sid_right_indent"};
        
        $Paint_sid_end_row = &Ali::Display::_subref_paint_text_row( $self, $args );
        $Sidpos_end_to_pixel = &Ali::Display::_subref_sidpos_to_pixel( $self, $args );
    }

    # Feature painting routines,

    if ( $state->{"ali_highlight_rna_covar"} or
         $state->{"ali_highlight_rna_pairs"} or
         $state->{"ali_highlight_seq_cons"} )
    {
        $args->{"viewport"} = $viewport->{"data"};
        $args->{"font"} = $font_bold;
        
        $Paint_ft_fillrect = &Ali::Display::_subref_paint_ft_fillrect( $self, $args );
    }
    
    return $self;
}

sub _paint_data_area
{
    # Niels Larsen, January 2006.

    # Paints data. 

    my ( $self,
         $state,
         ) = @_;

    # Returns alignment.

    my ( $image, $row );

    $image = $self->image;

    if ( defined $Paint_data_row )
    {
        foreach $row ( 0 .. $self->max_row )
        {
            $Paint_data_row->( $self, $row );
        }
    }
    else
    {
        $Paint_data_cols->( $self );
    }        

    $self->image( $image );

    return $self;
}

sub _paint_nums_beg
{
    # Niels Larsen, January 2006.

    # Paints sequence numbers, left side. 

    my ( $self,
         $state,
         ) = @_;

    # Returns alignment.

    my ( $image, $rows, $row, $chars );

    $image = $self->image;
    
    $rows = [ 0 .. $self->max_row ];

#    if ( $state->{"ali_pix_per_row"} < 0.9 ) {
#        $rows = &Common::Util::sample_list( $rows, scalar @{ $rows } * $state->{"ali_pix_per_row"} );
#    }

    foreach $row ( @{ $rows } )
    {
        $chars = $self->seq_beg( $row );
        
        if ( $chars =~ /[1-9]/ ) {
            $Paint_num_beg_row->( $image, $row, $chars );
        }
    }
    
    $self->image( $image );

    return $self;
}

sub _paint_nums_end
{
    # Niels Larsen, January 2006.

    # Paints sequence numbers, right side. 

    my ( $self,
         $state,
         $nums,
         ) = @_;

    # Returns alignment.

    my ( $image, $rows, $row, $chars );

    $image = $self->image;
        
    $rows = [ 0 .. $self->max_row ];

#    if ( $state->{"ali_pix_per_row"} < 0.9 ) {
#        $rows = &Common::Util::sample_list( $rows, scalar @{ $rows } * $state->{"ali_pix_per_row"} );
#   }

    foreach $row ( @{ $rows } )
    {
        $chars = $self->seq_end( $row );
        
        if ( $chars =~ /[1-9]/ ) {
            $Paint_num_end_row->( $image, $row, $chars );
        }
    }
    
    $self->image( $image );

    return $self;
}

sub _paint_sids_beg
{
    # Niels Larsen, January 2006.

    # Paints short ids, left side. 

    my ( $self,
         $state,
         ) = @_;

    # Returns alignment.

    my ( $image, $rows, $row );

    $image = $self->image;
 
    $rows = [ 0 .. $self->max_row ];

#    if ( $state->{"ali_pix_per_row"} < 0.9 ) {
#        $rows = &Common::Util::sample_list( $rows, scalar @{ $rows } * $state->{"ali_pix_per_row"} );
#    }

    foreach $row ( @{ $rows } )
    {
        $Paint_sid_beg_row->( $image, $row, $self->sid_string( $row ) );
    }

    $self->image( $image );

    return $self;
}

sub _paint_sids_end
{
    # Niels Larsen, January 2006.

    # Paints short ids, right side. 

    my ( $self,
         $state,
         ) = @_;

    # Returns alignment.

    my ( $image, $rows, $row );

    $image = $self->image;

    $rows = [ 0 .. $self->max_row ];

#    if ( $state->{"ali_pix_per_row"} < 0.9 ) {
#        $rows = &Common::Util::sample_list( $rows, scalar @{ $rows } * $state->{"ali_pix_per_row"} );
#    }

    foreach $row ( @{ $rows } )
    {
        $Paint_sid_end_row->( $image, $row, $self->sid_string( $row ) );
    }

    $self->image( $image );

    return $self;
}

sub _reset_zoom
{
    # Niels Larsen, August 2008.

    # Sets state zoom percentage and pixels per row/column so at least the given
    # number of data columns can be shown. It is triggered when zooms are attempted
    # that would show no data columns (because the labels takes up the space).
    # Returns an updated state.

    my ( $self,
         $state,
        ) = @_;

    # Returns a hash.

    my ( $colmin, $new_pix_per_col, $ratio );

    $colmin = $state->{"ali_data_cols"};
    $colmin += ( $self->sid_len * 2 + 2 ) if $state->{"ali_prefs"}->{"ali_with_sids"};
    $colmin += ( $self->beg_cols + $self->end_cols + 2 ) if $state->{"ali_prefs"}->{"ali_with_nums"};
            
    $new_pix_per_col = $state->{"ali_prefs"}->{"ali_img_width"} / $colmin;
    
    $ratio = $new_pix_per_col / $state->{"ali_pix_per_col"};
    
    $state->{"ali_prefs"}->{"ali_zoom_pct"} *= $ratio;
    $state->{"ali_prefs"}->{"ali_zoom_pct"} = int $state->{"ali_prefs"}->{"ali_zoom_pct"};
    
    $state->{"ali_pix_per_col"} *= $ratio;
    $state->{"ali_pix_per_row"} *= $ratio;
    
    $state->{"ali_data_rows"} = int $state->{"ali_prefs"}->{"ali_img_height"} / $state->{"ali_pix_per_row"};
    
    push @{ $state->{"ali_messages"} }, 
    [ "Warning", qq (Zoom percentage reduced to $state->{"ali_prefs"}->{'ali_zoom_pct'},)
               . qq ( or else the alignment would not fit in the view.) ];
    
    return $state;
}

sub _set_gd_colors
{
    # Niels Larsen, February 2006.

    # Allocates a given hash of color strings and transparency values on a given
    # GD image. The GD colors are returned as a hash. 

    my ( $self,         # Alignment 
         $image,        # GD image
         $colors,       # Color hash
         ) = @_;

    # Updates image and returns a GD color hash. 

    my ( $ch, $rgb, $gd_colors, $colstr, $trans, $color, $visited );

    foreach $ch ( keys %{ $colors } )
    {
        ( $colstr, $trans ) = @{ $colors->{ $ch } };

        if ( not defined ( $color = $visited->{ $colstr }->{ $trans } ) )
        {
            $rgb = &Common::Util::hex_to_rgb( $colstr );
            $color = $image->colorAllocateAlpha( @{ $rgb }, $trans );

            $visited->{ $colstr }->{ $trans } = $color;
        }
            
        $gd_colors->{ $ch } = $color;
    }

    return wantarray ? %{ $gd_colors } : $gd_colors;
}

sub set_color
{
    # Niels Larsen, February 2006.

    # Creates a hash with GD color values for each valid character.

    my ( $self,          # Class or alignment
         $colstr,        # String like "#ff0000"
         $trans,         # Transparency value - OPTIONAL, default 0
         ) = @_;

    # Returns a hash.

    my ( $color, $rgb, $ch, $colors );

    $trans = 0 if not defined $trans;

    $color = [ $colstr, $trans ];

    foreach $ch ( split "", $self->alphabet_paint )
    {
        $colors->{ $ch } = $color;
    }

    return $colors;
}

sub set_colors
{
    # Niels Larsen, July 2005.

    # Sets A and G to dark shades of grey, C and T/U to lighter ones.
    # All other valid characters are set to red, so they stand out. 

    my ( $self,
         $trans,
         ) = @_;
 
    # Returns a hash.

    my ( $colors, $type );

    if ( $type = $self->datatype )
    {
        if ( &Common::Types::is_dna_or_rna( $type ) )
        {
            $trans = 20 if not defined $trans;
            
            $colors = &Ali::Display::set_color( $self, "#000000" );
            
            $colors->{"A"} = $colors->{"a"} = [ "#CC9933", $trans ];
            $colors->{"G"} = $colors->{"g"} = [ "#669999", $trans ];
            $colors->{"C"} = $colors->{"c"} = [ "#CCFFFF", $trans ];
            $colors->{"T"} = $colors->{"t"} = [ "#FFFFCC", $trans ];
            $colors->{"U"} = $colors->{"u"} = $colors->{"T"};;
        }
        elsif ( &Common::Types::is_protein( $type ) )
        {
            $trans = 20 if not defined $trans;

            $colors->{"G"} = $colors->{"g"} = [ "#CE86D0", $trans ];
            $colors->{"P"} = $colors->{"p"} = $colors->{"G"};
            
            $colors->{"A"} = $colors->{"a"} = [ "#FFF2DF", $trans ];
            $colors->{"V"} = $colors->{"v"} = $colors->{"A"};
            $colors->{"L"} = $colors->{"l"} = $colors->{"A"};
            $colors->{"I"} = $colors->{"i"} = $colors->{"A"};
            $colors->{"M"} = $colors->{"m"} = $colors->{"A"};
            
            $colors->{"S"} = $colors->{"s"} = [ "#93DC93", $trans ];
            $colors->{"T"} = $colors->{"t"} = $colors->{"S"};
            $colors->{"N"} = $colors->{"n"} = $colors->{"S"};
            $colors->{"Q"} = $colors->{"q"} = $colors->{"S"};
            
            $colors->{"D"} = $colors->{"d"} = [ "#CC6666", $trans ];
            $colors->{"E"} = $colors->{"e"} = $colors->{"D"};
            
            $colors->{"C"} = $colors->{"c"} = [ "#CCCC00", $trans ];
            $colors->{"U"} = $colors->{"u"} = $colors->{"C"}; 
            
            $colors->{"F"} = $colors->{"f"} = [ "#FFC27F", $trans ];
            $colors->{"Y"} = $colors->{"y"} = $colors->{"F"};
            $colors->{"W"} = $colors->{"w"} = $colors->{"F"};
            
            $colors->{"K"} = $colors->{"k"} = [ "#87ABCD", $trans ];
            $colors->{"R"} = $colors->{"r"} = $colors->{"K"};
            $colors->{"H"} = $colors->{"h"} = $colors->{"K"};
        }
        else {
            &error( qq (Wrong looking type -> "$type") );
        }
    }
    else {
        &error( qq (Type is undefined) );
    }
    
    return $colors;
}

sub set_colors_greyscale
{
    # Niels Larsen, February 2006.

    # Sets A and G to dark shades of grey, C and T/U to lighter ones.
    # All other valid characters are set to red, so they stand out. 

    my ( $self, 
         $trans,
         ) = @_;

    # Returns a hash.

    my ( $colors, $type );

    if ( $type = $self->datatype )
    {
        if ( &Common::Types::is_dna_or_rna( $type ) )
        {
            $trans = 0 if not defined $trans;

            $colors = &Ali::Display::set_color( $self, "#ff0000" );
            
            $colors->{"A"} = $colors->{"a"} = [ "#AAAAAA", $trans ];
            $colors->{"G"} = $colors->{"g"} = [ "#858585", $trans ];
            $colors->{"C"} = $colors->{"c"} = [ "#FFFFFF", $trans ];
            $colors->{"T"} = $colors->{"t"} = [ "#E6E6E6", $trans ];
            $colors->{"U"} = $colors->{"u"} = $colors->{"T"};
        }
        elsif ( &Common::Types::is_protein( $type ) )
        {
            $trans = 0 if not defined $trans;
            
            $colors->{"I"} = $colors->{"i"} = [ "#E6E6E6", $trans ];
            $colors->{"L"} = $colors->{"l"} = $colors->{"I"};
            $colors->{"V"} = $colors->{"v"} = $colors->{"I"};
            $colors->{"A"} = $colors->{"a"} = $colors->{"I"};
            $colors->{"M"} = $colors->{"m"} = $colors->{"I"};
            
            $colors->{"F"} = $colors->{"f"} = [ "#828282", $trans ];
            $colors->{"Y"} = $colors->{"y"} = $colors->{"F"};
            $colors->{"W"} = $colors->{"w"} = $colors->{"F"};
            
            $colors->{"K"} = $colors->{"k"} = [ "#646464", $trans ];
            $colors->{"R"} = $colors->{"r"} = $colors->{"K"};
            $colors->{"H"} = $colors->{"h"} = $colors->{"K"};
            
            $colors->{"D"} = $colors->{"d"} = [ "#A0A0A0", $trans ];
            $colors->{"E"} = $colors->{"e"} = $colors->{"D"};
            
            $colors->{"S"} = $colors->{"s"} = [ "#B4B4B4", $trans ];
            $colors->{"T"} = $colors->{"t"} = $colors->{"S"};
            $colors->{"N"} = $colors->{"n"} = $colors->{"S"};
            $colors->{"Q"} = $colors->{"q"} = $colors->{"S"};
            
            $colors->{"P"} = $colors->{"p"} = [ "#D7D7D7", $trans ];
            $colors->{"G"} = $colors->{"g"} = $colors->{"P"};
            
            $colors->{"C"} = $colors->{"c"} = [ "#FFFFFF", $trans ];
            $colors->{"U"} = $colors->{"u"} = $colors->{"C"}; 
        }
        else {
            &error( qq (Wrong looking type -> "$type") );
        }
    }
    else {
        &error( qq (Type is undefined) );
    }
            
    return $colors;
}

sub set_colors_hydrophobicity
{
    # Niels Larsen, January 2006.

    # Different tones of red and blue. 

    my ( $self,
         $trans,
         ) = @_;
    
    # Returns a hash.

    my ( $type, $colors );

    if ( $type = $self->datatype )
    {
        if ( &Common::Types::is_protein( $type ) )
        {
            $trans = 90 if not defined $trans;
            
            $colors->{"I"} = $colors->{"i"} = [ "#ff3333", $trans ];
            $colors->{"L"} = $colors->{"l"} = $colors->{"I"};
            $colors->{"V"} = $colors->{"v"} = $colors->{"I"};
            
            $colors->{"F"} = $colors->{"f"} = [ "#ff6666", $trans ];
            $colors->{"C"} = $colors->{"c"} = $colors->{"F"};
            $colors->{"M"} = $colors->{"m"} = $colors->{"F"};
            $colors->{"A"} = $colors->{"a"} = $colors->{"F"};
            
            $colors->{"G"} = $colors->{"g"} = [ "#ff9999", $trans ];
            $colors->{"X"} = $colors->{"x"} = $colors->{"G"};
            $colors->{"T"} = $colors->{"t"} = $colors->{"G"};
            $colors->{"S"} = $colors->{"s"} = $colors->{"G"};
            $colors->{"W"} = $colors->{"w"} = $colors->{"G"};
            
            $colors->{"Y"} = $colors->{"y"} = [ "#9999ff", $trans ];
            $colors->{"P"} = $colors->{"p"} = $colors->{"Y"};
            
            $colors->{"H"} = $colors->{"h"} = [ "#3333ff", $trans ];
            $colors->{"E"} = $colors->{"e"} = $colors->{"H"};
            $colors->{"Z"} = $colors->{"z"} = $colors->{"H"};
            $colors->{"Q"} = $colors->{"q"} = $colors->{"H"};
            $colors->{"D"} = $colors->{"d"} = $colors->{"H"};
            $colors->{"B"} = $colors->{"b"} = $colors->{"H"};
            $colors->{"N"} = $colors->{"n"} = $colors->{"H"};
            $colors->{"K"} = $colors->{"k"} = $colors->{"H"};
            $colors->{"R"} = $colors->{"r"} = $colors->{"H"};
        }
        else {
            &error( qq (Wrong looking type -> "$type") );
        }
    }
    else {
        &error( qq (Type is undefined) );
    }
            
    return $colors;
}

sub _set_pix_scales_if_undefined
{
    # Niels Larsen, July 2005.

    # Sets the number of pixels per data column, by measuring how long
    # a string of 100 '@' characters in the current font are and divide 
    # by 100. The number is fractional and can be higher or lower than 
    # one. 
 
    my ( $self,
         $state,
         ) = @_;

    my ( $maxrows, $font, $size, $string, $bounds );

    if ( not defined $state->{"ali_pix_per_row"} )
    {
        # Set a reasonable row default if not defined, 

        $maxrows = $self->max_row + 1;
    
        if ( $maxrows > $state->{"ali_prefs"}->{"ali_img_height"} / 3 ) {
            $state->{"ali_pix_per_row"} = 3;
        } else {
            $state->{"ali_pix_per_row"} = &Common::Util::min( 15, $state->{"ali_prefs"}->{"ali_img_height"} / $maxrows );
        }
    }

    if ( not defined $state->{"ali_pix_per_col"} )
    {
        # Set column value based on row value,

        $font = $Common::Config::font_dir ."/". $state->{"ali_font_normal"};
        $size = $state->{"ali_pix_per_row"} * $state->{"ali_font_scale"};
        $string = "@" x 100;
        
        @{ $bounds } = GD::Image->stringFT( 0, $font, $size, 0, 0, 0, $string );
        
        $state->{"ali_pix_per_col"} = ( $bounds->[2] - $bounds->[0] ) / 100;
    }
    
    return $state;
}

sub _subref_alipos_to_pixel_global
{
    # Niels Larsen, January 2006.
    
    # Creates a subroutine that returns the image (x,y) pixel position of a given 
    # alignment (col,row) position. This routine is used for plotting features
    # for example. Returns 2-tuple of (x,y).

    my ( $self,      # Alignment
         $args,      # Arguments hash
         ) = @_;
    
    # Returns a list.
    
    my ( $minrow, $mincol, $subref );
    
    $mincol = $args->{"viewport"}->{"mincol"};
    $minrow = $args->{"viewport"}->{"minrow"};
    
    $subref = sub
    {
        my ( $self, $col, $row ) = @_;
        my ( $xpix, $ypix, $local_col, $local_row );

        if ( defined ( $local_col = $self->local_col( $col ) ) and
             defined ( $local_row = $self->local_row( $row ) ) )
        {
            $xpix = ( $mincol + $local_col + 0.9 ) * $args->{"col_scale"} + $args->{"margin"};
            $ypix = ( $minrow + $local_row + 0.9 ) * $args->{"row_scale"} + $args->{"margin"};

            return ( int $xpix, int $ypix );
        }
        else {
            return ( undef, undef );
        }
    };
     
    return $subref;
}

sub _subref_paint_data
{
    # Niels Larsen, January 2005.

    # Creates subroutines that render the data. Depending on resolution and 
    # user settings, they get painted as characters, filled boxes with space
    # between, or just strokes of color. IN FLUX

    my ( $self,       # Alignment object
         $args,       # Arguments hash
         ) = @_;

    # Returns a GD image object. 

    my ( $mincol, $minrow, $max_row, $thickness, $y_mid, $colors, $font, $size,
         $x_min, $y_min, $x_inc, $y_inc, $code, $row_subref, $cols_subref, 
         $x_gap, $y_gap, $valid_chars, $gd_colors, $trans, $options, $res );    

    $mincol = $args->{"viewport"}->{"mincol"};
    $minrow = $args->{"viewport"}->{"minrow"};

    $x_inc = $args->{"col_scale"};
    $y_inc = $args->{"row_scale"};
    
    $x_min = $mincol * $x_inc + $args->{"margin"} - 1;
    $y_min = ( $minrow + 1 ) * $y_inc + $args->{"margin"};

    $thickness = &Common::Util::max( int $y_inc / 10, 1 );

    $options = {};

    if ( defined ( $res = $args->{"resolution"} ) ) {
        $options->{"resolution"} = "$res,$res";
    }

    if ( $y_inc >= 7 and $x_inc > 4 and $args->{"display_type"} eq "characters" )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHARACTERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        $font = $Common::Config::font_dir ."/". $args->{"font"};
        $size = $args->{"size"};

        $colors = &Ali::Display::set_color( $self, "#000000" );
        $colors = &Ali::Display::_set_gd_colors( $self, $self->image, $colors );

        $row_subref = sub
        {
            my ( $ali, $row ) = @_;
            
            my ( $image, $chars, $col, $char, $x, $y_ch );
            
            $image = $ali->image; 
            $image->setThickness( $thickness );
            
            $y_ch = $y_min + $y_inc * ( $row - 0.12 );
            $y_mid = $y_min + $y_inc * $row - $y_inc / 2;
            
            $chars = $ali->seq_string( $row );

            foreach $col ( 0 .. (length $chars)-1 )
            {
                $char = substr $chars, $col, 1; 
                
                if ( exists $colors->{ $char } )
                {
                    $x = $x_min + $x_inc * ( $col + 0.05 );
                    $image->stringFT( $colors->{ $char }, $font, $size, 0, $x, $y_ch, $char, $options );
                }
                else
                {
                    $x = $x_min + $x_inc * $col;
                    $image->line( $x+1, $y_mid, $x+$x_inc-1, $y_mid, $args->{"color_gap"} );
                }
            }
            
            return $ali;
        };
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>> LINES AND BOXES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # The following configures the overall look: x_gap and y_gap are the 
        # number of pixels between columns and rows.

        if ( $args->{"display_type"} eq "characters" )
        {
            $x_gap = &Common::Util::min( int $x_inc / 7, 1 );
            $y_gap = int $y_inc / 3;

            if ( $y_gap > 0 ) {
                $colors = &Ali::Display::set_color( $self, "#a0a0a0", 0 );
            } else {
                $colors = &Ali::Display::set_color( $self, "#a7a7a7", 50 );
            }
        }
        else
        {
            $x_gap = &Common::Util::min( int $x_inc / 2.3, 1 );
            $y_gap = &Common::Util::min( int $y_inc / 2, 1 );

            if ( $y_gap > 0 ) {
                $trans = 0;
            } else {
                $trans = 40;
            }

            if ( $args->{"display_type"} eq "color_dots" )
            {
                $colors = &Ali::Display::set_colors( $self, $trans );
            }
            else {
                $colors = &Ali::Display::set_colors_greyscale( $self, $trans );
            }
        }
        
        $gd_colors = &Ali::Display::_set_gd_colors( $self, $self->image, $colors );

        # >>>>>>>>>>>>>>>>>>>>>>>>> MEDIUM RESOLUTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # If space between rows, follow the grid and draw each cell one rectangle
        # at a time. 

        if ( $y_gap > 0 )
        {
            $row_subref = sub
            {
                my ( $ali, $row ) = @_;
                
                my ( $image, $chars, $col, $char, $x, $y, $y_mid );

                $image = $ali->image;
                $image->setThickness( $thickness );
                
                $y = $y_min + $y_inc * $row;
                $y_mid = $y - $y_inc / 2;
                
                $chars = $ali->seq_string( $row );
                
                foreach $col ( 0 .. (length $chars)-1 )
                {
                    $char = substr $chars, $col, 1;
                    $x = $x_min + $x_inc * $col;
                    
                    if ( exists $gd_colors->{ $char } ) {
                        $image->filledRectangle( $x+1, $y-$y_inc+1, $x+$x_inc-$x_gap, $y-$y_gap, $gd_colors->{ $char } );
                    } else {
                        $image->line( $x+1, $y_mid, $x+$x_inc-$x_gap, $y_mid, $args->{"color_gap"} );
                    }
                }
                
                return $ali;
            };
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> LOW RESOLUTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Here we have no space between rows. Then we can omit gap characters and 
        # draw column by column for speed,

        else
        {
#            $max_row = $self->max_row;
            $valid_chars = { map { $_, 1 } split "", $self->alphabet_paint };

            $cols_subref = sub
            {
                my ( $ali ) = @_;
                
                my ( $image, $seqs, $chars, $col, $char, $x, $y, $y_beg, $row, $begrow,
                     $cols, $rows, $inc_mul, $rowndx );
                
                $image = $ali->image;
                $seqs = $ali->seqs;

#                $inc_mul = &Common::Util::max( $x_inc, $y_inc );

                $cols = [ 0 .. $ali->max_col ];
                
#                 if ( $x_inc < 1.0 ) 
#                 {
#                     $cols = &Common::Util::sample_list( $cols, scalar @{ $cols } * $x_inc );
#                     $x_inc = 1.0;
#                 }

                $rows = [ 0 .. $ali->max_row ];

#                 if ( $y_inc < 1.0 ) 
#                 {
#                     $rows = &Common::Util::sample_list( $rows, scalar @{ $rows } * $y_inc );
#                     $y_inc = 1.0;
#                 }

                $max_row = $#{ $rows };

#                &dump( scalar @{ $rows } );
#                &dump( scalar @{ $cols } );

#                $x_inc /= $inc_mul;
#                $y_inc /= $inc_mul;

#                &dump( "$x_inc, $y_inc");
                
                foreach $col ( @{ $cols } )
                {
                    $chars = [ map { chr $_ } $seqs->dice( [ $col ], $rows )->list ];
                    $x = $x_min + $x_inc * $col;

                    $row = 0;

                    while ( $row <= $max_row ) 
                    {
                        if ( $valid_chars->{ $chars->[$row] } )
                        {
                            $begrow = $row;

                            while ( $row <= $max_row and $valid_chars->{ $chars->[$row] } )
                            {
                                $char = $chars->[$row];
                                $row += 1;
                            }

                            $y_beg = $y_min + $y_inc * ( $begrow - 1 );
                            $y = $y_min + $y_inc * ( $row - 1 );

                            $image->filledRectangle( $x+1, $y_beg, $x+$x_inc, $y-$y_gap, $gd_colors->{ $char } );
                        }
                        else {
                            $row += 1;
                        }
                    }
                }
                
                return $ali;
            };
        }

    }
    
    return ( $row_subref, $cols_subref );
}

sub _subref_paint_ft_fillrect
{
    # Niels Larsen, February 2005.

    # Creates a subroutine that knows 

    my ( $self,       # Alignment object
         $args,       # Arguments hash
         ) = @_;

    # Returns a GD image object. 

    my ( $mincol, $minrow, $x_min, $y_min, $x_inc, $y_inc, $subref );

    $mincol = $args->{"viewport"}->{"mincol"};
    $minrow = $args->{"viewport"}->{"minrow"};

    $x_inc = $args->{"col_scale"};
    $y_inc = $args->{"row_scale"};
    
    $x_min = $mincol * $x_inc + $args->{"margin"};
    $y_min = ( $minrow + 1 ) * $y_inc + $args->{"margin"};

    $subref = sub
    {
        my ( $image, $value, $color, $col1, $row1, $col2, $row2 ) = @_;
        
        my ( $x1, $y1, $x2, $y2 );
        
        $x1 = $x_min + $x_inc * $col1;
        $y1 = $y_min + $y_inc * ( $row1 - 1 );
        
        $x2 = $x_min + $x_inc * ( $col2 + 1 ) - 1;
        $y2 = $y_min + $y_inc * $row2 - 1;
        
        $image->filledRectangle( $x1, $y1, $x2, $y2, $color );
        
        return $image;
    };
    
    return $subref;
}

sub _subref_paint_text_row
{
    # Niels Larsen, January 2006.

    # Creates a subroutine that takes 3 arguments: image, row index, and a string to 
    # be painted. A number of arguments determine how the routine is configured: font,
    # size, colors, etc, see the configure routine for examples. This routine should
    # only be called once, and is purely a configuration helper routine. 

    my ( $self,         # Class or alignment
         $args,         # Arguments hash
         ) = @_;

    # Returns a subroutine reference.

    my ( $x_min, $x_max, $y_min, $minrow, $mincol, $maxcol, $format, $col_wid, 
         $color, $font, $size, $regexp, $subref, $x_inc, $y_inc, $y_mid, $rgb, 
         $image, $thickness, $options, $res );

    $mincol = $args->{"viewport"}->{"mincol"};
    $maxcol = $args->{"viewport"}->{"maxcol"};
    $minrow = $args->{"viewport"}->{"minrow"};

    # The following are in-scope variables for the routine below,
    
    $col_wid = $maxcol - $mincol + 1;

    $y_inc = $args->{"row_scale"};
    $x_inc = $args->{"col_scale"};

    $x_min = $mincol * $x_inc + $args->{"margin"};
    $x_max = $maxcol * $x_inc + $args->{"margin"};

    $y_min = ( $minrow + 1 ) * $y_inc + $args->{"margin"};

    $font = $Common::Config::font_dir ."/". $args->{"font"};
    $size = $args->{"size"};

    $color = $args->{"color"};

    $thickness = &Common::Util::max( $y_inc / 2.5, 1 );

    $options = {};
    
    if ( defined ( $res = $args->{"resolution"} ) ) {
        $options->{"resolution"} = "$res,$res";
    }

    # Subroutine definition: draw readable text if resolution over 6 pixels per 
    # character, otherwise just a line. Note use of closure to "remember" values
    # from above,

    if ( $args->{"indent"} eq "right" )
    {
        if ( $y_inc >= 7 and $x_inc > 4 )
        {
            $subref = sub
            {
                my ( $image, $row, $chars ) = @_;
                my ( $x, $y, $col_beg );
                
                $chars =~ s/ *$//;
                $chars =~ s/^ *//;
                
                $col_beg = $col_wid - ( length $chars );

                $x = $x_min + $x_inc * ( $col_beg - 0.05 );
                $y = $y_min + $y_inc * ( $row - 0.12 );

                $image->stringFT( $color, $font, $size, 0, $x, $y, $chars, $options );
                
                return $image;
            };
        }
        else
        {
            $subref = sub
            {
                my ( $image, $row, $chars ) = @_;
                my ( $x_beg, $col_beg, $y_mid );
                
                $chars =~ s/ *$//;
                $chars =~ s/^ *//;

                $col_beg = $col_wid - ( length $chars );

                $x_beg = $x_min + $x_inc * $col_beg;
                $y_mid = $y_min + $y_inc * $row - $y_inc / 2;

                $image->setThickness( $thickness );
                $image->line( $x_beg, $y_mid, $x_max, $y_mid, $color );
                
                return $image;
            };
        }
    }
    else
    {
        if ( $y_inc >= 7 and $x_inc > 4 )
        {
            $subref = sub
            {
                my ( $image, $row, $chars ) = @_;
                my ( $x, $y, $col_end );
                
                $chars =~ s/ *$//;
                $chars =~ s/^ *//;
                
                $y = $y_min + $y_inc * ( $row - 0.12 );

                $image->stringFT( $color, $font, $size, 0, $x_min, $y, $chars, $options );
                
                return $image;
            };
        }
        else
        {
            $subref = sub
            {
                my ( $image, $row, $chars ) = @_;
                my ( $x_end, $col_end, $y_mid );
                
                $chars =~ s/ *$//;
                $chars =~ s/^ *//;
                
                $col_end = ( length $chars ) - 1;

                $y_mid = $y_min + $y_inc * $row - $y_inc / 2;
                $x_end = $x_min + $x_inc * $col_end;

                $image->setThickness( $thickness );
                $image->line( $x_min, $y_mid, $x_end, $y_mid, $color );
                
                return $image;
            };
        }
    }

    return $subref;
}

sub _subref_pixel_to_alipos
{
    # Niels Larsen, June 2008. 
    
    # (See older version at bottom of this file)
    # Creates a subroutine that returns the original alignment (col,row) 
    # position, when given a (x,y) image pixel position. Both col and row
    # may be undefined if an (x,y) coordinate is given that is off the data
    # area in the image. 

    my ( $self,      # Alignment
         $args,      # Arguments hash
         ) = @_;
    
    # Returns a list.
    
    my ( $mincol, $maxcol, $minrow, $maxrow, $subref, $x_min, $y_min, $x_max, $y_max );

    ( $x_min, $y_min ) = $Alipos_to_pixel->( $self, $self->_orig_cols->at(0), $self->_orig_rows->at(0) );
    ( $x_max, $y_max ) = $Alipos_to_pixel->( $self, $self->_orig_cols->at(-1), $self->_orig_rows->at(-1) );

    $subref = sub
    {
        my ( $self, $x, $y ) = @_;
        my ( $lcol, $lrow, $col, $row );

        if ( $x < $x_min ) {
            $x = $x_min;
        } elsif ( $x > $x_max ) {
            $x = $x_max;
        }

        $lcol = int ( ( $x - $x_min + 1 ) / $args->{"col_scale"} + 1);
        $lcol = &Common::Util::min( $lcol, $self->max_col );

        $col = $self->global_col( $lcol );

        if ( $y < $y_min ) {
            $y = $y_min;
        } elsif ( $y > $y_max ) {
            $y = $y_max;
        }

        $lrow = int ( ( $y - $y_min + 1 ) / $args->{"row_scale"} + 1);
        $lrow = &Common::Util::min( $lrow, $self->max_row );
        
        $row = $self->global_row( $lrow );
        
        return ( $col, $row );
    };

    return $subref;
}

sub _subref_sidpos_to_pixel
{
    # Niels Larsen, January 2006.
    
    # Creates a subroutine that returns the image (x,y) pixel position of a given 
    # alignment (col,row) position. This routine is used for plotting features
    # for example. Returns 2-tuple of (x,y).

    my ( $self,      # Alignment
         $args,      # Arguments hash
         ) = @_;
    
    # Returns a list.
    
    my ( $minrow, $mincol, $subref );
    
    $mincol = $args->{"viewport"}->{"mincol"};
    $minrow = $args->{"viewport"}->{"minrow"};

    $subref = sub
    {
        my ( $self, $col, $row ) = @_;
        my ( $xpix, $ypix );
        
        $xpix = ( $mincol + $col + 0.9 ) * $args->{"col_scale"} + $args->{"margin"};
        $ypix = ( $minrow + $self->local_row( $row ) + 0.9 ) * $args->{"row_scale"} + $args->{"margin"};
#        $ypix = ( $minrow + $row + 0.9 ) * $args->{"row_scale"} + $args->{"margin"};

        return ( int $xpix, int $ypix );
    };
     
    return $subref;
}

1;

__END__
          'indent' => 'left',
          'font' => 'VeraMoBd.ttf',
          'display_type' => 'characters',
          'size' => '9.09090909090909',
          'viewport' => {
                          'maxrow' => 76,
                          'maxcol' => 111,
                          'minrow' => 0,
                          'mincol' => 89
                        },
          'color' => 3355443,
          'row_scale' => '12.987012987013',
          'color_gap' => 10066329,
          'margin' => 0,
          'col_scale' => '7.08'


          'indent' => 'left',
          'font' => 'VeraMoBd.ttf',
          'display_type' => 'characters',
          'size' => '9.09090909090909',
          'viewport' => {
                          'maxrow' => 76,
                          'maxcol' => 111,
                          'minrow' => 0,
                          'mincol' => 89
                        },
          'color' => 3355443,
          'row_scale' => '12.987012987013',
          'resolution' => 600,
          'color_gap' => 10066329,
          'margin' => 0,
          'col_scale' => '7.08'


# sub _set_clipping
# {
#     my ( $self,
#          $state,
#          ) = @_;

#     my ( $maxcols, $maxrows, $clip );

#     $maxcols = $self->max_col + 1;
#     $maxrows = $self->max_row + 1;

#     if ( $state->{"ali_data_cols"} > $maxcols )
#     {
#         $clip->{"left"} = - int ( $state->{"ali_data_cols"} - $maxcols ) / 2;
#         $clip->{"right"} = $clip->{"left"};
#     }

#     if ( $state->{"ali_data_rows"} > $maxrows )
#     {
#         $clip->{"top"} = - int ( $state->{"ali_data_rows"} - $maxrows ) / 2;
#         $clip->{"bottom"} = $clip->{"top"};
#     }

#     $state->{"ali_clipping"} = $clip;

#     return $state;
# }

# Retired routines, but dont delete yet.

# sub _subref_pixel_to_alipos
# {
#     # Niels Larsen, January 2006.
    
#     # Creates a subroutine that returns the original alignment (col,row) 
#     # position, when given a (x,y) image pixel position. Both col and row
#     # may be undefined if an (x,y) coordinate is given that is off the data
#     # area in the image. 

#     my ( $self,      # Alignment
#          $args,      # Arguments hash
#          ) = @_;
    
#     # Returns a list.
    
#     my ( $mincol, $maxcol, $minrow, $maxrow, $subref, $x_min, $y_min, $x_max, $y_max );

#     ( $x_min, $y_min ) = $Alipos_to_pixel->( $self, $self->_orig_cols->at(0), $self->_orig_rows->at(0) );
#     ( $x_max, $y_max ) = $Alipos_to_pixel->( $self, $self->_orig_cols->at(-1), $self->_orig_rows->at(-1) );

#     $subref = sub
#     {
#         my ( $self, $x, $y ) = @_;
#         my ( $lcol, $lrow, $col, $row );

#         if ( $x >= $x_min and $x <= $x_max )
#         {
#             $lcol = int ( ( $x - $x_min + 1 ) / $args->{"col_scale"} + 1);
#             $lcol = &Common::Util::min( $lcol, $self->max_col );

#             $col = $self->global_col( $lcol );
#         } 

#         if ( $y >= $y_min and $y <= $y_max )
#         {
#             $lrow = int ( ( $y - $y_min + 1 ) / $args->{"row_scale"} + 1);
#             $lrow = &Common::Util::min( $lrow, $self->max_row );

#             $row = $self->global_row( $lrow );
#         }
        
#         return ( $col, $row );
#     };

#     return $subref;
# }


# sub _subref_sidpos_beg_to_pixel
# {
#     # Niels Larsen, April 2006.
    
#     # Creates a subroutine that returns the image (x,y) pixel position of a given 
#     # label position (col,row) position. This routine is used for showing tooltips
#     # for example. Returns 2-tuple of (x,y).

#     my ( $self,      # Alignment
#          $args,      # Arguments hash
#          ) = @_;
    
#     # Returns a list.
    
#     my ( $minrow, $mincol, $subref );

#     $mincol = $args->{"viewport"}->{"mincol"};
#     $minrow = $args->{"viewport"}->{"minrow"};
    
#     $subref = sub
#     {
#         my ( $col, $row ) = @_;
#         my ( $xpix, $ypix );
        
#         $xpix = ( $mincol + $col + 0.9 ) * $args->{"col_scale"} + $args->{"margin"};
#         $ypix = ( $minrow + $row + 0.9 ) * $args->{"row_scale"} + $args->{"margin"};

#         return ( int $xpix, int $ypix );
#     };
     
#     return $subref;
# }

# sub _subref_paint_line
# {
#     # Niels Larsen, January 2006.

#     # Creates a subroutine that takes 3 arguments: image, row index. Column position 
#     # and conversion to pixel position is hardcoded into the routine. This is purely 
#     # a helper routine internal to this package.

#     my ( $class,        # Class
#          $args,         # Arguments hash
#          ) = @_;
    
#     # Returns a subroutine reference. 
    
#     my ( $code, $x_min, $xend, $minrow, $maxrow, $mincol, $maxcol, $subref,
#          $y_shift );
    
#     ( $mincol, $maxcol, $minrow, $maxrow ) = @{ $args->{"viewport"} }[0,2,7,1];
    
#     $x_min = $mincol * $args->{"col_scale"} + $args->{"margin"};
#     $xend = $maxcol * $args->{"col_scale"} + $args->{"margin"};

#     if ( $args->{"row_scale"} > 1 )
#     {
#         $y_shift = $args->{"row_scale"} / 2;
    
#         $subref = sub
#         {
#             my ( $image, $row ) = @_;
#             my ( $y, $y_mid );
            
#             $y = ( $minrow + $row + 0.9 ) * $args->{"row_scale"} + $args->{"margin"};
#             $y_mid = $y - $y_shift;

#             $image->line( $x_min, $y_mid, $xend, $y_mid, $args->{"color"} );

#             return $image;
#         };
#     }
#     else
#     {
#         $subref = sub
#         {
#             my ( $image, $row ) = @_;
#             my ( $y );
            
#             $y = ( $minrow + $row + 0.9 ) * $args->{"row_scale"} + $args->{"margin"};

#             $image->line( $x_min, $y, $xend, $y, $args->{"color"} );

#             return $image;
#         };
#     }                

#     return $subref;
# }

# sub _subref_paint_ft_boldchar
# {
#     # Niels Larsen, February 2006.

#     # Configures a routine that paints a boldface character. 

#     my ( $self,         # Class or alignment
#          $args,         # Arguments hash
#          ) = @_;

#     # Returns a subroutine reference.
    
#     my ( $mincol, $minrow, $font, $size,
#          $x_min, $y_min, $x_inc, $y_inc, $subref );

#     ( $mincol, $minrow ) = @{ $args->{"viewport"} }[0,7];

#     $x_inc = $args->{"col_scale"};
#     $y_inc = $args->{"row_scale"};
    
#     $x_min = $mincol * $x_inc + $args->{"margin"};
#     $y_min = ( $minrow + 1 ) * $y_inc + $args->{"margin"};

#     $font = $args->{"font"};
#     $size = $args->{"size"};

#     $subref = sub
#     {
#         my ( $image, $char, $color, $trans, $col, $row ) = @_;
        
#         my ( $x, $y );
        
#         $x = $x_min + $x_inc * ( $col + 0.05 );
#         $y = $y_min + $y_inc * ( $row - 0.12 );
        
#         $image->stringFT( $color, $font, $size, $trans, $x, $y, $char );
        
#         return $image;
#     };

#     return $subref;
# }

# sub img_resize_all_cols
# {
#     # Niels Larsen, September 2005.

#     # Expands the image to the entire width of the alignment: if collapse mode
#     # is on, the length of the alignment depends on which rows are in view; if 
#     # not the image includes all columns in the original file. 

#     my ( $self,        # Alignment object
#          $rows,        # Row indices
#          $state,      # Parameters hash
#          ) = @_;

#     # Returns an alignment object.

#     my ( $subali, @cols, $new_cols );

#     if ( $state->{"ali_prefs"}->{"ali_with_col_collapse"} )
#     {
#         $subali = $self->subali_get( undef, $rows, 0, 0 );

#         ( $new_cols, $state->{"ali_clipping"}->{"right"} ) =
#             $subali->_get_indices_right( 0, $self->max_col + 1, 1 );

#         push @cols, @{ $new_cols };

#         $subali = $self->subali_get( \@cols, $rows, 
#                                 $state->{"ali_prefs"}->{"ali_with_sids"},
#                                 $state->{"ali_prefs"}->{"ali_with_nums"} );
#     }
#     else
#     {
#         @cols = ( 0 .. $self->max_col );
#         $subali = $self->subali_get( undef, $rows, 
#                                 $state->{"ali_prefs"}->{"ali_with_sids"},
#                                 $state->{"ali_prefs"}->{"ali_with_nums"} );
#     }

#     $state->{"ali_prefs"}->{"ali_img_width"} = (scalar @cols) * $state->{"ali_pix_per_col"};

#     if ( $state->{"ali_prefs"}->{"ali_with_sids"} ) {
#         $state->{"ali_prefs"}->{"ali_img_width"} += ( $self->sid_len * 2 + 2 ) * $state->{"ali_pix_per_col"};
#     }

#     if ( $state->{"ali_prefs"}->{"ali_with_nums"} ) {
#         $state->{"ali_prefs"}->{"ali_img_width"} += ( $self->beg_cols + $self->end_cols + 2 ) * $state->{"ali_pix_per_col"};
#     }

#     return $subali;
# }

# sub img_resize_all_rows
# {
#     # Niels Larsen, September 2005.

#     # Expands the image to the entire height of the alignment. 

#     my ( $self,        # Alignment object
#          $cols,        # Column indices
#          $state,      # Parameters hash
#          ) = @_;

#     # Returns an alignment object.

#     my ( $subali, @rows );

#     $subali = $self->subali_get( $cols, undef, 
#                             $state->{"ali_prefs"}->{"ali_with_sids"},
#                             $state->{"ali_prefs"}->{"ali_with_nums"} );

#     $state->{"ali_prefs"}->{"ali_img_height"} = ( $self->max_row + 1 ) * $state->{"ali_pix_per_row"};

#     return $subali;
# }

# sub img_resize_less_cols
# {
#     # Niels Larsen, September 2005.

#     # Shrinks the image from right to contain less columns.

#     my ( $self,
#          $cols,
#          $rows,
#          $state,
#          ) = @_;
    
#     my ( $data_cols, $length, $subali );

#     $state->{"ali_prefs"}->{"ali_img_width"} /= ( 100 + $state->{"ali_img_resize_pct"} ) / 100;

#     $data_cols = $state->{"ali_data_cols"};

#     $self->_fit_data_to_image( $state );

#     $length = $data_cols - $state->{"ali_data_cols"};

#     splice @{ $cols }, scalar @{ $cols } - $length, $length;

#     $subali = $self->subali_get( $cols, $rows,
#                             $state->{"ali_prefs"}->{"ali_with_sids"},
#                             $state->{"ali_prefs"}->{"ali_with_nums"} );

#     return $subali;
# }

# sub img_resize_less_rows
# {
#     my ( $self,
#          $cols,
#          $rows,
#          $state,
#          ) = @_;
    
#     my ( $data_rows, $length, $subali );

#     $state->{"ali_prefs"}->{"ali_img_height"} /= ( 100 + $state->{"ali_img_resize_pct"} ) / 100;

#     $data_rows = $state->{"ali_data_rows"};

#     $self->_fit_data_to_image( $state );

#     $length = $data_rows - $state->{"ali_data_rows"};

#     splice @{ $rows }, scalar @{ $rows } - $length, $length;

#     $subali = $self->subali_get( $cols, $rows, 
#                             $state->{"ali_prefs"}->{"ali_with_sids"},
#                             $state->{"ali_prefs"}->{"ali_with_nums"} );

#     return $subali;
# }

# sub img_resize_more_cols
# {
#     my ( $self,
#          $cols,
#          $rows,
#          $state,
#          ) = @_;
    
#     my ( $maxcol, $data_cols, $length, $subali, $new_cols );

#     $state->{"ali_prefs"}->{"ali_img_width"} *= ( 100 + $state->{"ali_img_resize_pct"} ) / 100;

#     $maxcol = $self->max_col;

#     if ( $cols->[-1] < $maxcol )
#     {
#         $data_cols = $state->{"ali_data_cols"};

#         $self->_fit_data_to_image( $state );

#         $length = $state->{"ali_data_cols"} - $data_cols;
        
#         $subali = $self->subali_get( undef, $rows, 0, 0 );

#         ( $new_cols, $state->{"ali_clipping"}->{"right"} ) = 
#             $subali->_get_indices_right( $cols->[-1] + 1, $length, $state->{"ali_prefs"}->{"ali_with_col_collapse"} );

#         push @{ $cols }, @{ $new_cols };
#     }

#     $subali = $self->subali_get( $cols, $rows, 
#                             $state->{"ali_prefs"}->{"ali_with_sids"},
#                             $state->{"ali_prefs"}->{"ali_with_nums"} );

#     return $subali;
# }

# sub img_resize_more_rows
# {
#     # Niels Larsen, March 2006.

#     # 
#     my ( $self,
#          $cols,
#          $rows,
#          $state,
#          ) = @_;

#     my ( $maxrow, $length, $subali, $data_rows, $new_rows );

#     $state->{"ali_prefs"}->{"ali_img_height"} *= ( 100 + $state->{"ali_img_resize_pct"} ) / 100;        

#     $maxrow = $self->max_row;

#     if ( $rows->[-1] < $maxrow ) 
#     {
#         $data_rows = $state->{"ali_data_rows"};

#         $self->_fit_data_to_image( $state );

#         $length = $state->{"ali_data_rows"} - $data_rows;

#         ( $new_rows, $state->{"ali_clipping"}->{"bottom"} ) =
#             $self->_get_indices_down( $rows->[-1] + 1, $length, $state->{"ali_prefs"}->{"ali_with_row_collapse"} );

#         push @{ $rows }, @{ $new_rows };
#     }
    
#     $subali = $self->subali_get( $cols, $rows, 
#                             $state->{"ali_prefs"}->{"ali_with_sids"},
#                             $state->{"ali_prefs"}->{"ali_with_nums"} );

#     return $subali;
# }

