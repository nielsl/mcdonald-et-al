package Common::Tables;     #  -*- perl -*-

# Table related formatting and rendering routines. This is an early module
# called early during installation, so try use "require" instead of "use"; 
# otherwise modules may be included that depend on cpan modules that have 
# not yet been installed. Also do not use recent perl features, like '//'
# etc, because this module is run during installation of perl, and system
# perl may be old.

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;
use English;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &ascii_style
                 &align_columns_xhtml
                 &colorize_numbers
                 &commify_numbers
                 &format_ascii
                 &format_decimals
                 &render_ascii
                 &render_list
                 &render_html
                 &_render_html_row
                 &render_ascii_usage
                 &splice_column
                 &write_tab_table
                 &xhtml_style
                 );

use Common::Config;
use Common::Messages;

use Common::Table;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub ascii_style
{
    # Niels Larsen, March 2003

    # Converts a plain value to a hash with these keys, which the 
    # display routines understand,
    # 
    # value => input value
    # colors => whatever Common::Messages::echo accepts
    # align => "right" or "left"
    
    my ( $value,     # Plain value
         $attribs,   # Attribute hash 
         ) = @_;

    # Returns hash reference.

    my ( $elem, $key );
    
    $elem = { "value" => $value };
    
    foreach $key ( keys %{ $attribs } )
    {
        $elem->{ $key } = $attribs->{ $key };
    }

    return $elem;
}

sub align_columns_xhtml
{
    # Niels Larsen, October 2009.

    # Given a table array, columns are aligned according to a given mask.
    # The mask has as many elements as there are columns, and elements can
    # be defined or not. If defined they must be either "left", "center" or
    # "right". The updated table is returned. 

    my ( $rows,           # List of lists
         $tuples,          # List of tuples or string 
        ) = @_;

    # Returns a list.

    my ( $tuple, $ndx, $str, $row, $e );

    if ( not ref $tuples ) {
        $tuples = [ map { [ $_, $tuples ] } ( 0 ... $#{ $rows->[0] } ) ];
    }

    foreach $tuple ( @{ $tuples } )
    {
        ( $ndx, $str ) = @{ $tuple };

        foreach $row ( @{ $rows } )
        {
            $e = $row->[$ndx];

            if ( ref $e and $e->{"value"} ne "" or $e ne "" )
            {
                $row->[$ndx] = &Common::Table::set_elem_attrib( $e, "style" => "text-align:$str" );
            }
        }
    }

    return $rows;
}

sub align_headers_xhtml
{
    # Niels Larsen, June 2012.

    my ( $hlist,           # List of strings
         $tuples,          # List of tuples
        ) = @_;

    # Returns a list.

    my ( $tuple, $ndx, $str, $elem, $e );

    foreach $tuple ( @{ $tuples } )
    {
        ( $ndx, $str ) = @{ $tuple };

        $e = $hlist->[$ndx];

        if ( defined $e and ( ref $e and $e->{"value"} ne "" or $e ne "" ) )
        {
            $hlist->[$ndx] = &Common::Table::set_elem_attrib( $e, "style" => "text-align:$str" );
        }
    }

    return $hlist;
}

sub colorize_numbers
{
    # Niels Larsen, June 2012. 

    # Colorizes numbers-only columns, by setting an inline style.
    # All values become hashes with "value" and "style" keys set, if they
    # are not already. The arguments can include lists of row and column
    # indices to colorize, use "cols" and "rows" as keys. All rows must 
    # have the same number of columns.

    my ( $rows,    # List of rows
         $args,    # Arguments hash - OPTIONAL
        ) = @_;

    # Returns array.

    my ( $cols, $col, $row, $minval, $maxval, $ratio, $bgcolor, $ramp,
         $rows2, $isnum );

    # If column indices not given, set them to all,
    
    $cols = $args->{"cols"};

    if ( not $cols or not @{ $cols } ) {
        $cols = [ 0 ... $#{ $rows->[0] } ];
    }
    
    # If row indices not given, set them to all and make copy that is 
    # changed below,

    if ( $args->{"rows"} ) {
        $rows2 = &Storable::dclone( [ @{ $rows }[ @{ $args->{"rows"} } ] ] );
    } else {
        $rows2 = &Storable::dclone( $rows );
    }

    # If no color ramp given, set to default grey -> white,

    if ( @{ $args->{"ramp"} } ) {
        $ramp = $args->{"ramp"};
    } else {
        $ramp = &Common::Util::color_ramp( "#cccccc", "#ffffff" );
    }

    foreach $col ( @{ $cols } )
    {
        $isnum = 1;

        foreach $row ( @{ $rows2 } ) 
        {
            if ( $row->[$col] and not &Scalar::Util::looks_like_number( $row->[$col] ) )
            {
                $isnum = 0;
                last;
            }
        }

        next if not $isnum;

        foreach $row ( @{ $rows2 } )
        {
            $row = [ map { $_ =~ s/,//g; $_ } @{ $row } ];

            if ( not ref $row->[ $col ] ) {
                $row->[ $col ] = { "value" => $row->[ $col ] };
            }
        }

        $minval = abs &List::Util::min( map { $_->[ $col ]->{"value"} || 0 } @{ $rows2 } );
        $maxval = abs &List::Util::max( map { $_->[ $col ]->{"value"} || 0 } @{ $rows2 } );

        if ( $minval > $maxval ) {
            ( $maxval, $minval ) = ( $minval, $maxval );
        }

        if ( $maxval > $minval )
        {
            $ratio = scalar @{ $ramp } / ( $maxval - $minval + 1 );

            foreach $row ( @{ $rows2 } )
            {
                $bgcolor = $ramp->[ int ( ( ( abs ($row->[ $col ]->{"value"} || 0) ) - $minval ) * $ratio ) ];

                if ( not defined $bgcolor ) 
                {
                    &dump( $row );
                    &dump( abs $row->[ $col ]->{"value"} );
                    &dump( int ( ( ( abs $row->[ $col ]->{"value"} ) - $minval ) * $ratio ) );
                }

                $row->[$col] = &Common::Table::set_elem_attrib( $row->[$col], "style" => "background-color: $bgcolor" );
            }
        }
    }

    return wantarray ? @{ $rows2 } : $rows2;
}

sub commify_numbers
{
    # Niels Larsen, September 2009.

    # Commifies the numbers found in a given table.
    
    my ( $table,
        ) = @_;

    # Returns a list of lists.

    my ( $elem, $i );

    foreach $elem ( @{ $table } )
    {
        for ( $i = 0; $i <= $#{ $elem }; $i++ )
        {
            if ( ref $elem->[$i] )
            {
                if ( $elem->[$i]->{"value"} =~ /^-?[\d\.]+$/ )
                {
                    $elem->[$i]->{"value"} = &Common::Util::commify_number( $elem->[$i]->{"value"} );
                }
            }
            elsif ( $elem->[$i] =~ /^-?[\d\.]+$/ )
            {
                $elem->[$i] = &Common::Util::commify_number( $elem->[$i] );
            }
        }
    }

    return $table;
}

sub format_ascii
{
    # Niels Larsen, March 2003.

    # Returns a table where the columns align. Each element can be a 
    # plain value in which case a default style is used with it. It may 
    # also be a reference to a hash with these keys and values,
    # 
    # value => number or string  ( like 4.13 or "<INPUT .... />" )
    # align => "left" or "right" ( like "text-align: right" ) - OPTIONAL
    # color => (whatever echo supports) - OPTIONAL
    # 
    # To use it, feed any array. If you want certain elements to look in
    # certain ways, use the ascii_style function to set the look.

    my ( $table,    # List, one or two-dimensional
         $attribs,  # Hash with attributes for whole table - OPTIONAL
         $indent,
         ) = @_;

    # Returns a string.

    my ( $maxrowndx, $maxcolndx, $rowndx, $colndx, $row, $elem, $f_elem,
         $wid, $maxwid, $f_table, $def_attrib, $colsep, $rowsep, $blanks );

    $colsep = defined $attribs->{"COLSEP"} ? $attribs->{"COLSEP"} : " ";
    $rowsep = defined $attribs->{"ROWSEP"} ? $attribs->{"ROWSEP"} : "";
    $blanks = defined $attribs->{"INDENT"} ? $attribs->{"INDENT"} : $indent;

    $maxrowndx = $#{ $table };
    $maxcolndx = 0;
    
    $def_attrib = { "align" => "left" };
    
    # Find longest column first,

    foreach $row ( @{ $table } )
    {
        $maxcolndx = $#{ $row } if $maxcolndx < $#{ $row };
    }
    
    # Then go through column by column and add padding and looks, so that
    # it all lines up when printed,

    for ( $colndx = 0; $colndx <= $maxcolndx; $colndx++ )
    {
        # Find the maximum width,
        
        $maxwid = 0;
        
        for ( $rowndx = 0; $rowndx <= $maxrowndx; $rowndx++ )
        {
            if ( exists $table->[ $rowndx ]->[ $colndx ] )
            {
                $elem = $table->[ $rowndx ]->[ $colndx ];

                if ( ref $elem )
                {
                    if ( ref $elem eq "HASH" ) {
                        $wid = length $elem->{"value"};
                        $maxwid = $wid if $wid > $maxwid;
                    } else {
                        &Common::Messages::error( "\$elem should be a HASH reference" );
                        exit 0;
                    }
                }
                else
                {
                    $wid = length $elem;
                    $maxwid = $wid if $wid > $maxwid;
                }
            }
        }

        next if $maxwid == 0;
        
        for ( $rowndx = 0; $rowndx <= $maxrowndx; $rowndx++ )
        {
            # Create a hash reference for each existing element,
            
            if ( exists $table->[ $rowndx ]->[ $colndx ] )
            {
                $elem = $table->[ $rowndx ]->[ $colndx ];
                
                if ( ref $elem ) {
                    $elem = { %{ $def_attrib }, %{ $elem } };
                } else {
                    $elem = { %{ $def_attrib }, "value" => $elem };
                } 
            }
            else {
                $elem = { %{ $def_attrib }, "value" => "" };
            }
            
#            if ( $elem->{"value"} =~ /\n/ ) {
#                &warning( "Newline found at position [ $rowndx, $colndx ]\n" );
#            }

            # Format the element,
            
            $f_elem = $elem->{"value"};
            
            if ( exists $elem->{"align"} )
            {
                if ( $elem->{"align"} eq "left" ) {
                    $f_elem = sprintf "%-".$maxwid."s", $f_elem;
                } elsif ( $elem->{"align"} eq "right" ) {
                    $f_elem = sprintf "%".$maxwid."s", $f_elem;
                } else {
                    &warning( "Align attribute looks wrong -> $elem->{'align'}" );
                }
            }
            
            if ( exists $elem->{"color"} ) {
                $f_elem = &Common::Messages::_echo( $f_elem, "$elem->{'color'}" );
            }
            
            $f_table->[ $rowndx ]->[ $colndx ] = $f_elem;
        }
    }

    return wantarray ? @{ $f_table } : $f_table;
}

sub render_ascii
{
    # Niels Larsen, February 2010.

    # Creates a string from the formatted table returned by format_ascii.
    # See that routine for expected input. 

    my ( $table,    # List, one or two-dimensional
         $attribs,  # Hash with attributes for whole table - OPTIONAL
         $indent,   # 
        ) = @_;

    # Returns string.

    my ( $colsep, $rowsep, $blanks, $f_table, $row );

    $colsep = defined $attribs->{"COLSEP"} ? $attribs->{"COLSEP"} : " ";
    $rowsep = defined $attribs->{"ROWSEP"} ? $attribs->{"ROWSEP"} : "";
    $blanks = defined $attribs->{"INDENT"} ? $attribs->{"INDENT"} : $indent;

    if ( ref $table eq "Common::Table" )
    {
        $f_table = &Common::Tables::format_ascii( $table->values, $attribs || {}, $indent );
    }
    elsif ( ref $table eq "ARRAY" )
    {
        $f_table = &Common::Tables::format_ascii( $table, $attribs || {}, $indent );
    }
    else {
        &error( qq (The given table must be object or array) );
    }

    foreach $row ( @{ $f_table } ) {
        $row = join $colsep, @{ $row };
    }

    if ( $blanks )
    {
        foreach $row ( @{ $f_table } ) {
            $row = " " x $blanks . $row;
        }
    }

    if ( $rowsep ) {
        $f_table = join "\n$rowsep\n", @{ $f_table };
    } else {
        $f_table = join "\n", @{ $f_table };
    }

    return $f_table;
}

sub format_decimals
{
    # Niels Larsen, September 2009.

    # Formats all number-looking elements in a given table to the given
    # sprintf compatible format.
    
    my ( $table,    # List of lists
         $format,   # sprintf compatible format
        ) = @_;

    # Returns a list of lists.

    my ( $elem, $i );

    foreach $elem ( @{ $table } )
    {
        for ( $i = 0; $i <= $#{ $elem }; $i++ )
        {
            if ( ref $elem->[$i] )
            {
                if ( $elem->[$i]->{"value"} =~ /^[\d,\.]+(\.|e-)\d+$/ )
                {
                    $elem->[$i]->{"value"} = sprintf $format, $elem->[$i]->{"value"};
                }
            }
            elsif ( $elem->[$i] =~ /^[\d,\.]+(\.|e-)\d+$/ )
            {
                $elem->[$i] = sprintf $format, $elem->[$i];
            }
        }
    }

    return $table;
}

sub render_list
{
    # Niels Larsen, June 2008.

    my ( $class,
         $table,
         $args,
        ) = @_;

    my ( $defs, @fields, $text, @align, $row, $col );

    require Common::Util;
    require Common::Table;
    require Registry::Args;

    $defs = {
        "fields" => undef,
        "header" => undef,
        "colsep" => undef,
        "indent" => undef,
        "align" => undef,
    };

    $args = {} if not defined $args;
    $args = &Registry::Args::create( $args, $defs );

    if ( $args->header )
    {
        @fields = split /\s*,\s*/, $args->fields;
        @fields = map { $_ =~ s/_/ /g; ucfirst $_ } @fields;

        unshift @{ $table }, [ map { "-" x length $_ } @fields ];
        unshift @{ $table }, [ @fields ];
    }

    if ( $args->align )
    {
        @align = split /\s*,\s*/, $args->align;

        foreach $row ( @{ $table } )
        {
            for ( $col = 0; $col <= $#align; $col++ )
            {
                $row->[$col] = &Common::Tables::ascii_style( $row->[$col], { "align" => $align[$col] } );
            }
        }
    }

#    $text = "\n";
    $text .= &Common::Tables::render_ascii( $table, { "COLSEP" => $args->colsep,
                                                      "INDENT" => $args->indent } );
#    $text .= "\n";

    if ( defined wantarray ) {
        return $text;
    } else {
        print $text;
    }

    return;
}

sub render_html
{
    # Niels Larsen, September 2009.

    # Generates HTML from a given table, which can be a Common::Table object 
    # or a straight list of lists array. The table is assumed to have columns
    # along the first dimension unless otherwise specified (with col_orient 
    # set to 0). Table elements can be plain values or hashes. 
    # 
    # value => number or string  ( like 4.13 or "<INPUT .... />" )
    # style => style string      ( like "text-align: right" ) - OPTIONAL
    # class => class string      ( like "std_cell" ) - OPTIONAL
    # tip => ascii string        ( like "This shows .." ) - OPTIONAL
    # 
    # A number of arguments can be given; see them by including "-help" => 1
    # among the arguments, or look at the code of this function near the top.

    my ( $table,    # Common::Table object or array
         %args,
         ) = @_;

    # Returns an XHTML string.

    my ( $args, @xhtml, $dtab, $row, $def_args, @hdrs, @rows, $class,
         $min, $max );

    require Common::Util;
    require Common::Table;
    require Registry::Args;
    require Common::Obj;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $def_args = {
        "format_decimals" => "%.2f",            # Formats all decimal numbers
        "commify_numbers" => 1,                 # Commify all numbers
        "align_columns" => [[ -1, "left" ]],    # Left-align the rightmost column
        "col_headers" => [],
        "row_headers" => [],
        "col_indices" => [],
        
        "css_col_ramp" => [],
        "css_col_header" => "std_col_title",    # Default css for column headers 
        "css_row_header" => "std_row_title",    # Default css for row headers 
        "css_element" => "std_cell",            # Default css for elements
        "show_empty_cells" => 1,
        "rows_only" => 0,

        "tt_fgcolor" => "#ffffcc",
        "tt_bgcolor" => "#666666",
        "tt_border" => 3,
        "tt_textsize" => "12px",
        "tt_captsize" => "12px",
        "tt_delay" => 400,
    };

    $args = &Registry::Args::create( \%args, $def_args );

    # >>>>>>>>>>>>>>>>>>>>>> TEMPORARY COMPATIBILITY <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This routine is called in many places and to not break those for now, a 
    # straight array (row oriented) can be given, which is then converted to an
    # object here,

    if ( ref $table eq "Common::Table" )
    {
        $dtab = $table;
    }
    elsif ( ref $table eq "ARRAY" )
    {
        $dtab = &Common::Table::new( $table, {"col_headers" => [], "row_headers" => []} );
    }
    
    if ( $args->{"col_headers"} and @{ $args->{"col_headers"} } ) {
        $dtab->{"col_headers"} = $args->{"col_headers"};
    }
    
    if ( $args->{"row_headers"} and @{ $args->{"row_headers"} } ) {
        $dtab->{"row_headers"} = $args->{"row_headers"};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> MODIFY ELEMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Convert 45.94857372 to 45.95 for example, 

    if ( $args->{"format_decimals"} )
    {
        $dtab->{"values"} = &Common::Tables::format_decimals( $dtab->{"values"}, $args->{"format_decimals"} );
    }

    # Make color ramps,

    if ( $args->{"css_col_ramp"} )
    {
        $dtab->{"values"} = &Common::Tables::colorize_numbers(
            $dtab->{"values"},
            {
                "cols" => $args->{"col_indices"},
                "ramp" => $args->{"css_col_ramp"},
            });
    }

    # Convert 2849203 to 2,849,203,

    if ( $args->{"commify_numbers"} )
    {
        $dtab->{"values"} = &Common::Tables::commify_numbers( $dtab->{"values"} );
    }

    # Column alignment. The default is to left-align the rightmost column and 
    # right-align the rest. If a list of [ column index, "left|right|center" ]
    # is given, then these values are merged in with the default,

    if ( $args->{"align_columns"} )
    {
        # &dump( $args->{"align_columns"} );

        $dtab->{"values"} = &Common::Tables::align_columns_xhtml( $dtab->{"values"}, $args->{"align_columns"} );
        $dtab->{"col_headers"} = &Common::Tables::align_headers_xhtml( $dtab->{"col_headers"}, $args->{"align_columns"} );

        # &dump( $dtab->{"values"} );
        # &dump( $dtab->{"col_headers"} );
    }

    # Set header styles if headers present,

    if ( $dtab->{"col_headers"} and @hdrs = @{ $dtab->{"col_headers"} } )
    {
        $class = $args->{"css_col_header"};
        $dtab->{"col_headers"} = [ map { &Common::Table::set_elem_attrib( $_, "class" => $class ) } @hdrs ];
    }
    
    if ( $dtab->{"row_headers"} and @hdrs = @{ $dtab->{"row_headers"} } )
    {
        $class = $args->{"css_row_header"};
        $dtab->{"row_headers"} = [ map { &Common::Table::set_elem_attrib( $_, "class" => $class ) } @hdrs ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE XHTML <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @rows = &Common::Table::table_to_array( $dtab );

    if ( not $args->{"rows_only"} ) {
        push @xhtml, qq (<table cellspacing="0" cellpadding="0">);
    }

    foreach $row ( @rows )
    {
        push @xhtml, "<tr>". &Common::Tables::_render_html_row( $row, $args ) ."</tr>";
    }

    if ( not $args->{"rows_only"} ) {
        push @xhtml, "</table>";
    }

    return (join "\n", @xhtml) ."\n";
}

sub _render_html_row
{
    # Niels Larsen, September 2009.

    # Creates XHTML for a row. Style and CSS class set are respected, otherwise
    # the default element style and class are used. If tooltip text is attached,
    # then a Javascript popup window is created using the Overlib library. The
    # routine returns a "<tr>....</tr>" string.

    my ( $row,       # List of elements
         $args,      # Arguments object
        ) = @_;

    # Returns a string.

    my ( $def_css, $xhtml, $elem, $value, $tip, $tip_args, $tip_str, $tt_fgcolor,
         $tt_bgcolor, $tt_border, $tt_delay, $tt_textsize, $tt_captsize, $style,
         $style_str, $class_str, $fgcolor, $bgcolor, $ref, $class, $show_empty,
         $show_zero );

    $def_css = $args->{"css_element"};

    $tt_fgcolor = $args->{"tt_fgcolor"};
    $tt_bgcolor = $args->{"tt_bgcolor"};
    $tt_border = $args->{"tt_border"};
    $tt_delay = $args->{"tt_delay"};
    $tt_textsize = $args->{"tt_textsize"};
    $tt_captsize = $args->{"tt_captsize"};
    $show_empty = $args->{"show_empty_cells"};

    if ( defined $args->{"show_zero_cells"} ) {
        $show_zero = $args->{"show_zero_cells"};
    } else { 
        $show_zero = 1;
    }

    $xhtml = "";
    
    foreach $elem ( @{ $row } )
    {
        $ref = ref $elem;
        
        if ( $ref eq "HASH" )
        {
            $value = $elem->{"value"} || "";

            if ( $value ne "" or $show_empty ) 
            {
                if ( $value =~ /^[0,\.]+$/ and not $show_zero ) 
                {
                    $xhtml .= qq (<td></td>);
                }
                else 
                {
                    $style = $elem->{"style"} || "";
                    $tip = $elem->{"tip"} || "";
                    $class = $elem->{"class"} || $def_css;
                    
                    if ( $style ) { $style_str = qq ( style="$style") } else { $style_str = "" };
                    if ( $class ) { $class_str = qq ( class="$class") } else { $class_str = "" };
                    
                    if ( $tip )
                    {
                        $fgcolor = $elem->{"fgcolor"} || $tt_fgcolor;
                        $bgcolor = $elem->{"bgcolor"} || $tt_bgcolor;
                        
                        $tip_args = qq (LEFT,OFFSETX,-100,OFFSETY,20,CAPTION,'$value',FGCOLOR,'$fgcolor',BGCOLOR,'$bgcolor')
                                  . qq (,BORDER,$tt_border,DELAY,'$tt_delay',TEXTSIZE,'$tt_textsize',CAPTIONSIZE,'$tt_captsize');
                        
                        $tip_str = qq ( onmouseover="return overlib('$tip',$tip_args);" onmouseout="return nd();");
                    }
                    else {
                        $tip_str = "";
                    }
                    
                    $xhtml .= qq (<td$class_str$style_str$tip_str>$value</td>);
                }
            }
            else {
                $xhtml .= qq (<td></td>);
            }
        }
        elsif ( not $ref )
        {
            $value = $elem || "";

            if ( $value ne "" or $show_empty ) 
            {
                if ( $value =~ /^[0,\.]+$/ and not $show_zero ) 
                {
                    $xhtml .= qq (<td></td>);
                }
                else 
                {
                    if ( $def_css ) {
                        $xhtml .= qq (<td class="$def_css">$elem</td>);
                    } else {
                        $xhtml .= qq (<td>$elem</td>);
                    }
                }
            }
            else {
                $xhtml .= qq (<td></td>);
            }
        }
        else {
            &Common::Messages::error( qq (Unsupported element type -> "$ref". Only plain values or hashes allowed.") );
        }
    }
    
    return $xhtml;
}

sub render_ascii_usage
{
    # Niels Larsen, March 2008.

    # Formats tuples of name, title (with green highlight if a list
    # given) and returns ascii text. 

    my ( $tuples,     # List of [ name, title ]
         $args,       # Arguments, all optional
        ) = @_;

    # Returns a string. 

    my ( $defs, $width, $tuple, %strong, $name, $title, $text, $hch,
         $blanks, $expr );

    require Common::Util;
    require Common::Table;
    require Registry::Args;

    $defs = {
        "width" => undef,
        "highlights" => [],
        "highch" => "* ",
        "indent" => 0,
        "match" => "",
    };

    $args = &Registry::Args::create( $args, $defs );

    if ( $args->indent > 0 ) {
        $blanks = " " x $args->indent;
    } else {
        $blanks = "";
    }
        
    $hch = $args->highch;

    if ( defined $args->width ) {
        $width = $args->width;
    } else {
        $width = &List::Util::max( map { length $_->[0] } @{ $tuples } );
        $width += 2;
    }

    if ( defined $args->highlights ) {
        %strong = map { $_, 1 } @{ $args->highlights };
    }
    
    $text = "";
    $expr = $args->match;

    foreach $tuple ( @{ $tuples } )
    {
        ( $name, $title ) = @{ $tuple };

        if ( not $title )
        {
            $text .= "\n";
            next;
        }

        if ( defined $name )
        {
            if ( $expr )
            {
                if ( $name =~ /$expr/ ) {
                    $name = $PREMATCH . &echo_bold( $MATCH ) . $POSTMATCH;
                } elsif ( $title =~ /$expr/ ) {
                    $title = $PREMATCH . &echo_bold( $MATCH ) . $POSTMATCH;
                }

                $text .= "$blanks$name    $title\n";
            }
            elsif ( $strong{ $name } ) 
            {
                $name = &Common::Messages::echo_green( sprintf "%$width"."s", $name );
                $text .= "$blanks$name $hch $title\n";
            }
            else
            {
                $name = sprintf "%$width"."s", $name;
                $text .= "$blanks$name    $title\n";
            }
        }
    }

    return $text;
}

sub write_tab_table
{
    # Niels Larsen, April 2003.

    # Writes Prints  .... 

    my ( $file,
         $table,
         $linend,
         ) = @_;

    # Returns nothing. 

    my ( $row, $rowstr, $ndx, $fh );

    $linend = "\n" if not defined $linend;

    $fh = &Common::File::get_write_handle( $file );

    $ndx = 0;

    foreach $row ( @{ $table } )
    {
        if ( grep { not defined $_ } @{ $row } )
        {
            &Common::Messages::error( qq (Undefined value(s) in row $ndx in -> "$file".\nTable partly written.) );
        }

        $rowstr = ( join "\t", @{ $row } ) . $linend;
        $fh->print( $rowstr );

        $ndx += 1;
    }

    $fh->close;

    return;
}

sub xhtml_style
{
    # Niels Larsen, February 2009

    # Updates an element (hash or plain value) with the given class and style
    # settings that the display routines understand. An element hash is returned. 
    # Keys are,
    # 
    # value => input value
    # class => input class - OPTIONAL
    # style => input style - OPTIONAL

    my ( $value,  # Element hash or plain value
         $class,  # Class name - OPTIONAL
         $style,  # Inline style - OPTIONAL
         ) = @_;

    # Returns hash reference.

    my ( $elem );

    if ( ref $value ) {
        $elem = $value;
    } else {
        $elem->{"value"} = $value;
    } 

    $elem->{"class"} = $class if $class;
    $elem->{"style"} = $style if $style;
    
    return $elem;
}

1;

__END__

# # Garbage can from here on, but dont delete,

# sub splice
# {
#     # Niels Larsen, February 2003

#     # Does for tables what regular splice does for lists. Same syntax,
#     # except for an extra row/column mode switch. It will insert, change
#     # (if you leave $delpos undefined) or delete rows and columns. The
#     # operations have effect on the input table itself, supply a copy 
#     # if you dont want this. Returns the deleted rows or columns, if 
#     # any. 

#     my ( $array,    # One or two-dimensional array 
#          $offset,   # Insert/delete offset in array
#          $length,   # Number of rows/columns to remove
#          $insert,   # Array or scalar to insert, or undef
#          $switch,   # "ROW" or "COL" 
#          ) = @_;

#     my ( @elems );

#     if ( $switch eq "ROW" )
#     {
#         @elems = &Common::Tables::splice_rows( $array, $offset, $length, $insert );
#     }
#     elsif ( $switch eq "COL" )
#     {
#         @elems = &Common::Tables::splice_cols( $array, $offset, $length, $insert );
#     }
#     else
#     {
#         &Common::Messages::error( qq (Switch looks wrong -> "$switch") );
#     }

#     wantarray ? return @elems : return \@elems;
# }

# sub splice_rows
# {
#     my ( $array,    # One or two-dimensional array 
#          $offset,   # Insert/delete offset in array
#          $length,   # Number of rows/columns to remove
#          $insert,   # Array or scalar to insert, or undef
#          ) = @_;

# #    splice @{ $array }, $offset, $length, @{ $insert };

# #    wantarray ? return @elems : return \@elems;
# }
