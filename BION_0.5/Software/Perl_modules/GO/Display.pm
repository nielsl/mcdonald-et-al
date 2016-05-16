package GO::Display;        #  -*- perl -*-

# Routines that manipulate the memory structures used for the columns
# part of the go display. They do not reach into database. They provide 
# the specific structures used by the browser (GO::Viewer) so it can treat
# things more abstractly.
#
# Most routines take the whole display structure as argument, but those
# whose names include e.g. _col_ operate on a column only; this is for 
# simple convenience. Some routines accept an optional list of ids; the
# rule is then - always - that if no list is given, all elements are 
# returned. The routines do not make copies of structures, but return
# references, so changing something in a returned structure affects the
# display. 
# 
# (describe display structure)
#

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( store retrieve dclone );
use List::Util;
use English;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &attach_header
                 &attach_headers
                 &attach_nodes
                 &boldify_ids
                 &boldify_names
                 &delete_cell
                 &delete_column
                 &delete_columns
                 &delete_header
                 &detach_headers
                 &detach_nodes
                 &exists_header
                 &get_cell
                  &get_cell_attrib
                 &get_col_ids
                 &get_column
                 &get_columns
                 &get_header
                 &get_headers
                 &get_headers_ref
                 &get_nodes_ref
                 &grep_headers
                 &grep_headers_type
                 &is_select_item
                 &match_headers
                  &new_checkbox_cell
                  &new_checkbox_column
                  &new_id_cell
                  &new_id_column
                  &new_go_link_cell
                  &new_go_link_column
                  &new_stats_cell
                  &new_stats_column
                  &new_sim_cell
                  &new_sim_column
                 &set_cell
                  &set_cell_attrib
                  &set_col_attribs
                  &set_col_bgramp
                 &set_col_styles
                 &set_col_stats
                 &set_column
                  &set_header
                 );


#                  &delete_cell_row
#                  &get_cell
#                  &get_cell_column
#                  &get_cell_columns
#                  &get_cell_row
#                  &get_col_cell
#                  &set_cell
#                  &set_cell_column
#                  &set_cell_row

use Common::DAG::Nodes;
use Common::Menus;
use Common::Messages;

$Common::DAG::Nodes::id_name = "go_id";

# >>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub attach_headers
{
    # Niels Larsen, January 2005.

    # Adds given header elements to a given display structure.

    my ( $display,     # Display structure
         $headers,     # List of header elements
         ) = @_;

    # Returns a hash.

    $display->{"headers"} = $headers;

    return $display;
}

sub attach_nodes
{
    # Niels Larsen, January 2005.

    # Adds given nodes elements to a given display structure.

    my ( $display,    # Display structure
         $nodes,      # Nodes hash
         ) = @_;

    # Returns a hash. 

    $display->{"nodes"} = $nodes;

    return $display;
}

sub boldify_ids
{
    # Niels Larsen, August 2003.

    # Renders the names in boldface that match 
    # a given text. 

    my ( $display,  # Display hash
         $ids,      # List of ids
         $root_id,  # Starting id for search
         ) = @_;

    # Returns a hash.

    my ( $id, $nodes, $node, $name );

    $nodes = $display->{"nodes"};

    foreach $id ( @{ $ids } )
    {
        $node = &GO::Nodes::get_node( $nodes, $id );
        $name = &GO::Nodes::get_name( $node );
        
        $node = &GO::Nodes::set_name( $node, "<strong>$name</strong>" );
    }

    return $display;
}

sub boldify_names
{
    # Niels Larsen, August 2003.

    # For a given set of nodes, renders the names in boldface that match 
    # a given text. 

    my ( $display,  # Display hash
         $text,     # Search text
         $target,   # Search target
         $root_id,  # Starting id for search
         ) = @_;

    # Returns a hash.

    my ( $ids, $id, $nodes, $node, $name, $alt_name, $string );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;
    
    foreach $id ( @{ $ids } )
    {
        next if $id == $root_id;
        
        $node = &Common::DAG::Nodes::get_node( $nodes, $id );
        
        $name = &Common::DAG::Nodes::get_name( $node );
#        $alt_name = &GO::Nodes::get_alt_name( $node ) || "";
        
        if ( $name =~ /$text/i )
        {
            $string = $PREMATCH ."<strong>$MATCH</strong>". $POSTMATCH;
            $node = &Common::DAG::Nodes::set_name( $node, $string );
        }

#         if ( $alt_name =~ /$text/i )
#         {
#             $string = $PREMATCH ."<strong>$MATCH</strong>". $POSTMATCH;
#             $node = &Common::DAG::Nodes::set_label( $node, "alt_name", $string );
#         }
    }

    return $display;
}

sub delete_cell
{
    # Niels Larsen, January 2005.

    # Deletes the cell for a given node at a given column index.

    my ( $node,        # Node structure
         $index,       # Column index
         ) = @_;
    
    # Returns a hash.

    if ( $node->{"cells"} ) {
        splice @{ $node->{"cells"} }, $index, 1;
    }

    return $node;
}

sub delete_column
{
    # Niels Larsen, February 2005.
    
    # Deletes a display column, including the title headers. 

    my ( $display,      # Display structure
         $index,        # Column index position
         ) = @_;

    $display = &GO::Display::delete_columns( $display, [ $index ] );

    return $display;
}

sub delete_columns
{
    # Niels Larsen, January 2005.
    
    # Deletes a list of display columns (including title headers) 
    # given by their indices.

    my ( $display,       # Display structure
         $indices,       # Column indices
         ) = @_;
    
    # Returns a hash.

    my ( $headers, $nodes, $node, $index, $id );

    $headers = &GO::Display::get_headers_ref( $display );
    $nodes = &GO::Display::get_nodes_ref( $display );

    foreach $index ( sort { $b <=> $a } @{ $indices } )
    {
        &GO::Display::delete_header( $headers, $index );

        foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
        {
            $node = &Common::DAG::Nodes::get_node( $nodes, $id );
            $node = &GO::Display::delete_cell( $node, $index );
        }
    }

    return $display;
}

sub delete_header
{
    # Niels Larsen, January 2005.

    # Deletes the header element at the given index.

    my ( $headers,
         $index,
         ) = @_;

    splice @{ $headers }, $index, 1;
    
    return $headers;
}
    
sub detach_headers
{
    # Niels Larsen, January 2005.

    # Returns the nodes part of the display.

    my ( $display,       # Display structure
         ) = @_;

    # Returns a hash.

    my ( $headers );

    $headers = $display->{"headers"};

    $display->{"headers"} = [];

    return $headers;
}

sub detach_nodes
{
    # Niels Larsen, January 2005.

    # Returns the nodes part of the display.

    my ( $display,       # Display structure
         ) = @_;

    # Returns a hash.

    my ( $nodes );

    $nodes = $display->{"nodes"};

    $display->{"nodes"} = [];

    return $nodes;
}

sub exists_header
{
    # Niels Larsen, January 2005.

    # Checks if a given header exists in a given list of headers.
    # The matching is done by keys: the values of "type" and "key" 
    # must match by default, but that can be overridden. 

    my ( $headers,      # List of header items
         $header,       # Header
         $keys,         # Keys that must match - OPTIONAL, default [ "type", "key" ]
         ) = @_;

    # Returns 1 or nothing. 

    my ( $matches );

    $matches = &GO::Display::grep_headers( $headers, $header, $keys );

    if ( @{ $matches } ) {
        return 1;
    } else {
        return;
    }
}

sub get_cell
{
    # Niels Larsen, January 2005.

    # Returns a cell for a given node id and column index.

    my ( $display,     # Display structure
         $id,          # Node id
         $index,       # Column index
         ) = @_;
    
    # Returns a hash.

    my ( $cell );

    if ( not defined $id ) {
        &error( qq (ID is not defined) );
        exit;
    }

    if ( not defined $index ) {
        &error( qq (Index is not defined) );
        exit;
    }
        
    $cell = $display->{"nodes"}->{ $id }->{"cells"}->[ $index ];

    return $cell;
}

sub get_cell_attrib
{
    # Niels Larsen, January 2005.

    # Returns the attribute value of a given cell and a given key.

    my ( $cell,      # Cell hash
         $key,       # Key string
         ) = @_;

    # Returns a hash.

    return $cell->{ $key };
}
         
sub get_col_ids
{
    # Niels Larsen, January 2005.
    
    # Returns a list of ids from a given column.

    my ( $column,
         ) = @_;
    
    my ( @ids );

    @ids = keys %{ $column };

    return wantarray ? @ids : \@ids;
}

sub get_column
{
    # Niels Larsen, January 2005.

    # Extracts from a given display the column with the given 
    # index.

    my ( $display,    # Display structure
         $index,      # Column index
         ) = @_;

    # Returns a hash.

    my ( $nodes, $node, $id, $column );

    $nodes = &GO::Display::get_nodes_ref( $display );

#    &dump( $nodes );
#    exit;

    foreach $node ( &Common::DAG::Nodes::get_nodes_all( $nodes ) )
    {
        $id = &Common::DAG::Nodes::get_id( $node );
#        &dump( $node );
#        &dump( "$id, $index" );
        $column->{ $id } = &GO::Display::get_cell( $display, $id, $index );
    }
    
    return wantarray ? %{ $column } : $column;
}

sub get_columns
{
    # Niels Larsen, January 2005.

    # Returns all column elements of a given display as a hash of 
    # [ node id, list of column elements ]. 

    my ( $display,
         ) = @_;
    
    # Returns a list.

    my ( $nodes, $node, $headers, $id );

    $nodes = &GO::Display::get_nodes_ref( $display );
    
    foreach $node ( &Common::DAG::Nodes::get_nodes_all( $nodes ) )
    {
        $id = &Common::DAG::Nodes::get_id( $node );
        $headers->{ $id } = $node->{"cells"};
    }

    return wantarray ? %{ $headers } : $headers;
}
    
sub get_header
{
    # Niels Larsen, January 2005.

    # Returns a header of a given index. 

    my ( $display,      # Display structure
         $index,        # Index value
         ) = @_;

    # Returns a list.

    my ( $headers );

    $headers = &GO::Display::get_headers( $display, [ $index ] );
    
    return $headers->[0];
}

sub get_headers
{
    # Niels Larsen, January 2005.

    # Returns a list of header element references, given by 
    # their indices. 

    my ( $display,      # Display structure
         $indices,      # Index list
         ) = @_;

    # Returns a list.

    my ( $all_headers, $headers, $i, $i_max );

    $all_headers = &GO::Display::get_headers_ref( $display );

    foreach $i ( @{ $indices } )
    {
        if ( $i <= $#{ $all_headers } )
        {
            push @{ $headers }, $all_headers->[$i];
        }
        else
        {
            $i_max = $#{ $all_headers };
            &error( qq (Header index is higher than $i_max -> "$i") );
            exit;
        }
    }

    return $headers;
}

sub get_headers_ref
{
    # Niels Larsen, January 2005.

    # Returns the nodes part of the display.

    my ( $display,       # Display structure
         ) = @_;

    # Returns a hash.

    return $display->{"headers"} || [];
}

sub get_nodes_ref
{
    # Niels Larsen, January 2005.

    # Returns the nodes part of the display.

    my ( $display,       # Display structure
         ) = @_;

    # Returns a hash.

    return $display->{"nodes"} || {};
}

sub grep_headers
{
    # Niels Larsen, February 2005.

    # Returns the elements in a given header list that match a given 
    # hash. Match means having same values for a the keys. If no 
    # matches the empty list is returned. 

    my ( $headers,    # List of header hashes
         $hash,       # Hash that must match
         ) = @_;

    # Returns a list or nothing. 
    
    my ( $header, @matches );

    foreach $header ( @{ $headers } )
    {
        if ( &GO::Display::match_headers( $header, $hash ) )
        {
            push @matches, $header;
        }
    }
    
    return \@matches;
}

sub is_select_item
{
    # Niels Larsen, January 2005.

    # Looks at the type of a given item and decides if it is 
    # one that has to do with selection checkboxes. 

    my ( $item,     # Item hash
         ) = @_;

    # Returns 1 or nothing.

    my ( $type );
    
    $type = &Common::Menus::get_item_value( $item, "type" );

    if ( $type =~ /^save|delete|download|retrieve$/ )
    {
        return 1;
    }
    else {
        return;
    }
}

sub match_headers
{
    # Niels Larsen, February 2004.

    # Compares two given header elements and returns 1 if similar and 
    # nothing if not. Being similar means having same values for a given
    # list of keys, which is by default [ "type", "key" ]. 

    my ( $header,     # Header hash
         $hash,       # Header hash
         ) = @_;

    # Returns a list or nothing. 
    
    my ( $flag, $key );

    $flag = 1;
    
    foreach $key ( keys %{ $hash } )
    {
        if ( $header->{ $key } ne $hash->{ $key } )
        {
            $flag = 0;
            last;
        }
    }
    
    if ( $flag ) {
        return 1;
    } else {
        return;
    }
}

sub new_checkbox_cell
{
    # Niels Larsen, January 2005.
    
    # Creates a column cell hash for a checkbox from a given
    # name.

    my ( $checked,      # 1 or 0
         ) = @_;

    # Returns a hash.

    my ( $cell );

    $cell = {
#        "type" => "checkbox",
        "value" => $checked || 0,
    };

    return $cell;
}

sub new_checkbox_column
{
    # Niels Larsen, January 2005.
    
    # Creates a column structure for a given list of node ids,
    # where the value elements are checkbox cells. 

    my ( $ids,
         $checked,
         ) = @_;

    my ( $column, $id );

    foreach $id ( @{ $ids } )
    {
        $column->{ $id } = &GO::Display::new_checkbox_cell( $checked );
    }

    return $column;
}

sub new_id_cell
{
    # Niels Larsen, January 2005.
    
    # Creates a column display cell hash. 

    my ( $id,
         ) = @_;

    # Returns a hash.

    my ( $cell );

    $cell = {
        "type" => "functions",
        "key" => "go_id",
        "value" => $id,
    };

    return $cell;
}
    
sub new_tax_link_column
{
    # Niels Larsen, January 2005.
    
    my ( $ids,
         ) = @_;

    my ( $column, $id );

    foreach $id ( @{ $ids } )
    {
        $column->{ $id } = &GO::Display::new_tax_link_cell( $id );
    }

    return $column;
}

sub new_tax_link_cell
{
    # Niels Larsen, January 2005.
    
    # Creates a column display cell hash. 

    my ( $id,
         ) = @_;

    # Returns a hash.

    my ( $cell );

    $cell = {
#        "type" => "organisms",
#"key" => "tax_link",
        "value" => $id,
    };

    return $cell;
}
    
sub new_id_column
{
    # Niels Larsen, January 2005.
    
    my ( $ids,
         ) = @_;

    my ( $column, $id );

    foreach $id ( @{ $ids } )
    {
        $column->{ $id } = &GO::Display::new_id_cell( $id );
    }

    return $column;
}

sub new_stats_cell
{
    # Niels Larsen, January 2005.
    
    # Creates a statistics column display cell hash. 

    # Returns a hash.

    my ( $cell );

    $cell = {
        "class" => "statistics",
#        "count" => undef,
#        "sum_count" => undef,
    };

    return $cell;
}
    
sub new_stats_column
{
    # Niels Larsen, January 2005.
    
    my ( $ids,
         ) = @_;

    my ( $column, $id );

    foreach $id ( @{ $ids } )
    {
        $column->{ $id } = &GO::Display::new_stats_cell();
    }

    return $column;
}

sub new_sim_cell
{
    # Niels Larsen, January 2005.
    
    # Creates a column display cell hash. 

    # Returns a hash.

    my ( $cell );

    $cell = {
        "type" => "similarity",
        "sum" => [ (undef) x 10 ],
    };

    return $cell;
}

sub new_sim_column
{
    # Niels Larsen, January 2005.
    
    my ( $ids,
         ) = @_;

    my ( $column, $id );

    foreach $id ( @{ $ids } )
    {
        $column->{ $id } = &GO::Display::new_sim_cell();
    }

    return $column;
}

sub set_cell
{
    # Niels Larsen, January 2005.

    # Sets a given cell for a given node id at a given column index.

    my ( $display,     # Display structure
         $nid,         # Node id
         $index,       # Column index
         $cell,        # Cell hash
         ) = @_;
    
    # Returns a hash.

    $display->{"nodes"}->{ $nid }->{"cells"}->[ $index ] = $cell;

    return $display;
}

sub set_cell_attrib
{
    # Niels Larsen, January 2005.

    # Sets a given cell for a given node id at a given column index.

    my ( $cell,        # Cell hash
         $key,         # Cell key
         $value,       # Cell value
         ) = @_;
    
    # Returns a hash.

    $cell->{ $key } = $value;

    return $cell;
}

sub set_col_attribs
{
    # Niels Larsen, February 2005.

    # Sets an attribute, given by a key and a value, for a column.

    my ( $column,      
         $key,
         $value,
         $ids,        # OPTIONAL, default all
         ) = @_;

    my ( $id );

    if ( not $ids )
    {
        $ids = &GO::Display::get_col_ids( $column );
    };

    foreach $id ( @{ $ids } )
    {
        $column->{ $id }->{ $key } = $value;
    }

    return $column;
}

sub set_col_bgramp
{
    # Niels Larsen, January 2005.
    
    # Sets a background color ramp by adding a "style" key to each cell. 
    # The ramp is given by a start and end color value. Typically the highest
    # value receive the brightest color and the colors range between gray 
    # and white. 

    my ( $column,
         $key,
         $begcol,
         $endcol,
         $root_id,
         ) = @_;

    # Returns an updated nodes hash.

    my ( $ramp, $id, @counts, @count_ids, $min_count, $max_count, $ramp_len,
         $scale, $index, $i, $style, $count, $cell );

    # Get minimum and maximum values,

    foreach $id ( &GO::Display::get_col_ids( $column ) )
    {
        next if $id == $root_id;

        $cell = $column->{ $id };

        if ( $count = &GO::Display::get_cell_attrib( $cell, $key ) )
        {
            push @counts, $count;
            push @count_ids, $id;
        }
    }
    
    $min_count = &List::Util::min( @counts ) || 0;
    $max_count = &List::Util::max( @counts ) || 0;

    # Ramp + scale,

    $ramp_len = 50;

    $ramp = &Common::Util::color_ramp( $begcol, $endcol, $ramp_len+1 );
    
    $scale = $ramp_len / ( $max_count - $min_count + 1);

    # Apply,

    for ( $i = 0; $i < @counts; $i++ )
    {
        $id = $count_ids[ $i ];
        
        $index = int ( ( $counts[ $i ] - $min_count + 1 ) * $scale );
        $style = "background-color: " . $ramp->[ $index ];
        
        &GO::Display::set_cell_attrib( $column->{ $id }, "style", $style );
    }

    return $column;
}

sub set_col_stats
{
    # Niels Larsen, January 2005.
    
    # Copies a given statistics hash into a given column.

    my ( $column,
         $stats,
         ) = @_;

    my ( $id, $key );

    foreach $id ( &GO::Display::get_col_ids( $column ) )
    {
        if ( exists $stats->{ $id } )
        {
            foreach $key ( keys %{ $stats->{ $id } } )
            {
                $column->{ $id }->{ $key } = $stats->{ $id }->{ $key };
            }
        }
    }

    return $column;
}

sub set_col_styles
{
    # Niels Larsen, February 2005.

    # Colors the statistics columns so those with highest numbers are brighter than
    # those with lower numbers. The top node is ignored. An updated display is returned.

    my ( $display,    # Display structure
         $root_id,    # Node to ignore
         ) = @_;

    # Returns a hash.

    my ( $headers, $header, $column, $i, $type, $key, $subtree, $id, $nodes );

    $headers = &GO::Display::get_headers_ref( $display );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $subtree = &Common::DAG::Nodes::get_subtree( $nodes, $root_id, 0 );

    for ( $i = 0; $i <= $#{ $headers }; $i++ )
    {
        $header = $headers->[$i];
        $type = $header->{"type"};
        $key = $header->{"key"};

        if ( $type eq "organisms" or $type eq "rna" or $type eq "dna" or $type eq "genes" or
             ( $type eq "functions" and $key ne "go_link" ) )
        {
            $column = &GO::Display::get_column( $display, $i );
#            $column = &Storable::dclone( $column );

            foreach $id ( &Common::DAG::Nodes::get_ids_all( $column ) )
            {
                delete $column->{ $id } if not exists $subtree->{ $id };
            }

            $column = &GO::Display::set_col_bgramp( $column, "sum_count", "#cccccc", "#ffffff", $root_id );

            $display = &GO::Display::set_column( $display, $column, $i );
        }
    }

    return $display;
}
    
sub set_column
{
    # Niels Larsen, January 2005.

    # Sets a given column at a given index. The new column overwrites
    # any old values there may be at any node. 

    my ( $display,       # Display structure.
         $column,        # Column hash
         $index,         # Column index
         ) = @_;

    # Returns a hash.

    my ( $nodes, $node, $id, $cell );

    # Add column values, 

    $nodes = &GO::Display::get_nodes_ref( $display );

    foreach $node ( &Common::DAG::Nodes::get_nodes_all( $nodes ) )
    {
        $id = &Common::DAG::Nodes::get_id( $node );

        if ( exists $column->{ $id } ) {
            &GO::Display::set_cell( $display, $id, $index, $column->{ $id } );
        }            
    }

    
    return $display;
}

sub set_header
{
    # Niels Larsen, January 2005.

    # Sets a header at a given index in a header list.

    my ( $display,       # Display structure
         $header,        # Header hash
         $index,         # Index position
         ) = @_;

    # Returns a list.

    # Delete keys not needed,

    delete $header->{"class"};      

    $display->{"headers"}->[ $index ] = $header;

    return $display;
}

1;

__END__

sub delete_cell_row
{
    # Niels Larsen, January 2005.

    # Deletes the cell row for a given node.

    my ( $display,     # Display structure
         $id,          # Node id
         ) = @_;
    
    # Returns a hash.

    my ( $nodes, $node );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $node = &Common::DAG::Nodes::get_node( $nodes, $id );

    $node->{"cells"} = [ (undef) x @{ $node->{"cells"} } ];

    return $display;
}

sub get_cell_row
{
    # Niels Larsen, January 2005.

    # Returns the column cells for a given node id.

    my ( $display,     # Display structure
         $id,          # Node id
         ) = @_;
    
    # Returns a list.

    my ( $nodes, $node, $cells );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $node = &Common::DAG::Nodes::get_node( $nodes, $id );

    $cells = $node->{"cells"};

    return $cells;
}

sub get_col_cell
{
    # Niels Larsen, January 2005.

    # Returns a cell for a given node id and column index.

    my ( $column,      # Column hash
         $id,          # Node id
         ) = @_;
    
    # Returns a hash.

    return $column->{ $id };
}

sub set_cell_row
{
    # Niels Larsen, January 2005.

    # Sets the column cells for a given node id.

    my ( $display,     # Display structure
         $id,          # Node id
         $cells,       # List of cells
         ) = @_;
    
    # Returns a hash.

    my ( $nodes, $node );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $node = &Common::DAG::Nodes::get_node( $nodes, $id );

    $node->{"cells"} = $cells;

    return $display;
}

1;

__END__

sub get_col_header
{
    # Niels Larsen, January 2005.

    # Returns a header element with a given index.

    my ( $display,     # Display structure
         $index,       # Index value
         ) = @_;

    # Returns a hash.

    my ( $header );

    $header = &GO::Display::get_headers_ref( $display )->[ $index ];

    return $header;
}

sub set_col_header
{
    # Niels Larsen, January 2005.

    # Sets a given column header at a given index position. 

    my ( $display,     # Display structure
         $header,      # Header element hash
         $index,       # Index value
         ) = @_;

    # Returns a hash.

    my ( $headers );

    $headers = &GO::Display::get_headers_ref( $display );

    $headers->[ $index ] = $header;
    
    $display = &GO::Display::attach_headers( $display, $headers );

    return $display;
}

sub get_node
{
    # Niels Larsen, January 2005.

    # Returns the nodes part of the display.

    my ( $display,       # Display structure
         $id,
         ) = @_;

    # Returns a hash.

    my ( $nodes, $node );

    $nodes = &GO::Display::get_nodes_ref( $display );
    $node = &Common::DAG::Nodes::get_node( $nodes, $id ) || {};

    return $node;
}
