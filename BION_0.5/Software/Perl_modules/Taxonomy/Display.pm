package Taxonomy::Display;        #  -*- perl -*-

# Routines that manipulate the memory structures used for the columns
# part of the taxonomy display. They do not reach into database. They
# provide the specific structures used by the browser (Taxonomy::Viewer)
# so it can treat things more abstractly.
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

use List::Util;
use English;

use Common::Config;
use Common::Messages;

use base qw ( Taxonomy::Menus Taxonomy::Cells );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<
# 
# add_column
# append_column
# boldify_ids
# boldify_names
# column_buttons
# columns
# delete_columns
# delete_column
# highlight_sims_columns
# highlight_stats_columns
# ids_selected
# is_select_item
# merge_columns
# nodes
# new_id_column
# new_checkbox_column
# new_stats_column
# set_column
# set_column_cells
# set_column_bgramp
# set_columns_highlight
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_column
{
    # Niels Larsen, October 2005.

    # Appends a column, to the right of the existing columns, but 
    # overwrites a column if 1) the chosen column is already in the
    # display, or if 2) the chosen column is closely related to one
    # already shown (for example, a checkbox column with checked or
    # unchecked boxes respectively). 

    my ( $self,
         $column,
         $index,     # Where to insert - OPTIONAL, default append
         ) = @_;

    # Returns a display object.

    my ( $name, $id, $objtype );

    $id = $column->id;
    $name = $column->name;
    $objtype = $column->objtype;

    if ( $self->columns->options )
    {
        if ( defined $index )
        {
            $self->set_column( $column, $index );
        }            
        elsif ( defined ( $index = $self->columns->match_option_index( "objtype" => $objtype, "id" => $id ) ) )
        {
            $self->set_column( $column, $index );
        }
        else {
            $self->append_column( $column );
        }
    }
    else {
        $self->append_column( $column );
    }

    return $self;
}

sub append_column
{
    # Niels Larsen, November 2005.

    # Appends a column to existing columns. 

    my ( $self,        # Display structure
         $col,         # Column object
         ) = @_;

    # Returns a display object. 

    my ( $cols, $checkbox );

    $self->columns->append_option( $col );

    if ( @{ $self->column_buttons->options } )
    {
        $checkbox = __PACKAGE__->new_col_checkbox;

        $self->column_buttons->append_option( $checkbox, 1 );
    }

    return $self;
}

sub new_col_checkbox
{
    my ( $checkbox );

    $checkbox = Taxonomy::Cells->new( "objtype" => "checkbox",
                                      "datatype" => "columns" );

    return $checkbox;
}

sub boldify_ids
{
    # Niels Larsen, August 2003.

    # Renders the names in boldface from nodes in a given list of ids.

    my ( $self,     # Display object
         $ids,      # List of ids
         $root_id,  # Starting id for search
         ) = @_;

    # Returns a display object.

    my ( $id, $nodes, $node, $name );

    $nodes = $self->nodes;

    foreach $id ( @{ $ids } )
    {
        $node = &Taxonomy::Nodes::get_node( $nodes, $id );
        $name = &Taxonomy::Nodes::get_name( $node );
        
        $node = &Taxonomy::Nodes::set_name( $node, "<strong>$name</strong>" );
    }

    return $self;
}

sub boldify_names
{
    # Niels Larsen, August 2003.

    # For a given set of nodes, renders the names in boldface that match 
    # a given text. 

    my ( $self,     # Display object
         $text,     # Search text
         $target,   # Search target
         $root_id,  # Starting id for search
         ) = @_;

    # Returns a display object.

    my ( $ids, $id, $nodes, $node, $name, $alt_name, $string );

    $nodes = $self->nodes;
    $ids = &Taxonomy::Nodes::get_ids_all( $nodes );
    
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;
    
    foreach $id ( @{ $ids } )
    {
        next if $id == $root_id;
        
        $node = &Taxonomy::Nodes::get_node( $nodes, $id );
        
        $name = &Taxonomy::Nodes::get_name( $node );
        $alt_name = &Taxonomy::Nodes::get_alt_name( $node ) || "";
        
        if ( $name =~ /$text/i )
        {
            $string = $PREMATCH ."<strong>$MATCH</strong>". $POSTMATCH;
            $node = &Taxonomy::Nodes::set_name( $node, $string );
        }

        if ( $alt_name =~ /$text/i )
        {
            $string = $PREMATCH ."<strong>$MATCH</strong>". $POSTMATCH;
            $node = &Taxonomy::Nodes::set_label( $node, "alt_name", $string );
        }
    }

    return $self;
}

sub column_buttons
{
    # Niels Larsen, November 2005.
    
    # Gets or sets the column button menu. 

    my ( $self,        # Display object
         $value,       # Menu object
         ) = @_;

    # Returns a display or menu object.

    if ( defined $value )
    {
        $self->{"column_buttons"} = $value;
        return $self;
    }
    else {
        return $self->{"column_buttons"};
    }
}

sub columns
{
    # Gets or sets the column data menu. 

    my ( $self,        # Display object
         $value,       # Menu object
         ) = @_;

    # Returns a display or menu object.

    if ( defined $value )
    {
        $self->{"columns"} = $value;
        return $self;
    }
    else {
        return $self->{"columns"};
    }
}

sub delete_columns
{
    # Niels Larsen, January 2005.
    
    # Deletes a list of display columns (including title headers) 
    # given by their indices.

    my ( $self,          # Display object
         $indices,       # Column indices
         ) = @_;
    
    # Returns a hash.

    my ( $index );

    foreach $index ( sort { $b <=> $a } @{ $indices } )
    {
        $self->delete_column( $index );
    }

    return $self;
}

sub delete_column
{
    # Niels Larsen, January 2005.
    
    # Deletes a single column given by its index.

    my ( $self,          # Display object
         $index,         # Column index
         ) = @_;
    
    # Returns a display object.

    my ( $cols );

    $self->columns->delete_option( $index );

    if ( @{ $self->column_buttons->options } ) 
    {
        $self->column_buttons->delete_option( $index );
    }

    return $self;
}

sub highlight_sims_columns
{
    # Niels Larsen, December 2005.

    # Sets background and border colors on the similarity cells in a 
    # given display. The colors are scaled between grey and green, and 
    # the scaling is done across the display, as opposed to column by
    # column only. Nodes with visible children nodes are not colored. 

    my ( $self,           # Display structure
         ) = @_;

    # Returns an updated display structure.

    my ( $columns, $column, $datatype, $cells, $cell, $ramp, $id, $counts, 
         $min_count, $max_count, $ramp_len, $scale, $index, $bgcolor, $list,
         $i, $style, $count, $icol, $sim_ramp, $sim_scale, @counts, $tuple,
         $fgcolor, $skipids, $nodes, $node, $b1color, $b2color, $objtype );

    $columns = $self->columns->options;
    $nodes = $self->nodes;

    # Save counts for all columns,

    for ( $icol = 0; $icol <= $#{ $columns }; $icol++ )
    {
        $column = $columns->[ $icol ];
        $objtype = $column->objtype;

        if ( $objtype eq "col_sims" )
        {
            $cells = $column->values;

            if ( %{ $cells } )
            {
                foreach $id ( keys %{ $cells } )
                {
                    if ( defined ( $count = $cells->{ $id }->value ) )
                    {
                        push @{ $counts->{ $icol } }, [ $id, $count ];
                    }
                }
            }
        }
    }            

    # If there were similarity columns, then,

    if ( $counts )
    {
        $ramp_len = 60;

        # Make ramps,

        foreach $list ( values %{ $counts } )
        {
            push @counts, map { $_->[1] } @{ $list };
        }

        $min_count = &List::Util::min( @counts ) || 0;
        $max_count = &List::Util::max( @counts ) || 0;
            
        $ramp = &Common::Util::color_ramp( "#ccddcc", "#339966", $ramp_len + 1 );
        $scale = $ramp_len / ( $max_count - $min_count + 1);

        # Find ids of nodes with children nodes, those we skip,
        
        foreach $id ( &Taxonomy::Nodes::get_ids_all( $nodes ) )
        {
            if ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $id } ) )
            {
                $skipids->{ $id } = 1;
            }
        }

        # Apply ramps,

        foreach $icol ( keys %{ $counts } )
        {
            $column = $columns->[ $icol ];
            $cells = $column->values;
            
            foreach $tuple ( @{ $counts->{ $icol } } )
            {
                ( $id, $count ) = @{ $tuple };
                
                if ( not $skipids->{ $id } and $cells->{ $id } )
                {
                    $index = int ( ( $count - $min_count + 1 ) * $scale );

                    $bgcolor = $ramp->[ $index ];
                    $fgcolor = "#ffffff";

                    if ( $index + 30 > $ramp_len ) {
                        $b1color = "#003300";
                    } else {
                        $b1color = $ramp->[ $index + 30 ];
                    }

                    if ( $index - 25 < 0 ) {
                        $b2color = "#dddfdd";
                    } else {
                        $b2color = $ramp->[ $index - 25 ];
                    }

                    $style = qq (color: $fgcolor; background-color: $bgcolor;)
                           . qq ( border-color: $b2color $b1color $b1color $b2color;);

                    $cells->{ $id }->style( $style );
                }
            }
        }
    }

    $self->columns->options( $columns );

    return $self;
}

sub highlight_stats_columns
{
    # Niels Larsen, December 2005.

    # Sets background and border colors on the statistics cells in a 
    # given display. The colors are scaled between grey and white, and 
    # is done column by column. Nodes with visible children nodes are 
    # not colored. 

    my ( $self,           # Display structure
         ) = @_;

    # Returns an updated display structure.

    my ( $columns, $nodes, $column, $objtype, $counts, $skipids, $col_id,
         $node_id, $cells, $count );

    $columns = $self->columns;
    $nodes = $self->nodes;

    # Save counts for all columns,

    foreach $column ( $columns->options )
    {
        $objtype = $column->objtype;

        if ( $objtype eq "col_stats" )
        {
            $cells = $column->values;
            $col_id = $column->id;

            if ( %{ $cells } )
            {
                foreach $node_id ( keys %{ $cells } )
                {
                    if ( defined ( $count = $cells->{ $node_id }->sum_count ) )
                    {
                        push @{ $counts->{ $col_id } }, [ $node_id, $count ];
                    }
                }
            }
        }
    }

    # If statistics columns then,

    if ( $counts )
    {
        # Find ids of nodes with children nodes, those we skip,
        
        foreach $node_id ( &Taxonomy::Nodes::get_ids_all( $nodes ) )
        {
            if ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $node_id } ) )
            {
                $skipids->{ $node_id } = 1;
            }
        }

        # Set grey -> white ramp,

        foreach $column ( $columns->options )
        {
            $col_id = $column->id;

            if ( $counts->{ $col_id } )
            {
                $column = &Taxonomy::Display::set_column_bgramp( $column, "sum_count",
                                                                 "#cccccc", "#ffffff", $skipids );
            }
        }
    }

    $self->columns( $columns );

    return $self;
}

sub ids_selected
{
    # Niels Larsen, January 2006.

    # Returns a list of ids of nodes that have been selected. The given 
    # display must include a column of checkboxes, because that is where
    # the information is taken from, and there may only be one. 

    my ( $self,         # Display object
         ) = @_; 

    my ( $column, $cells, $ids, $id );

    $column = $self->columns->match_option( "expr" => '$_->objtype =~ /^checkboxes_/' );

    $cells = $column->values;
    
    foreach $id ( keys %{ $cells } )
    {
        if ( $cells->{ $id }->selected ) {
            push @{ $ids }, $id;
        }
    }

    if ( $ids ) {
        return wantarray ? @{ $ids } : $ids;
    } else {
        return;
    }
}

sub is_select_item
{
    # Niels Larsen, November 2005.

    # Looks at the type of a given item and decides if it is 
    # one that has to do with selection checkboxes. 

    my ( $item,     # Item hash
         ) = @_;

    # Returns 1 or nothing.

    if ( $item->objtype =~ /^(checkbox|radiobutton)/ )
    {
        return 1;
    }
    else {
        return;
    }
}

sub merge_columns
{
    # Niels Larsen, November 2005.

    # IN FLUX

    my ( $self,
         $new,
         $root_id,
         ) = @_;

    my ( $cols, $newcols, $i, $cells, $newcells, $nid );

    $cols = $self->columns->options;
    $newcols = $new->options;

    for ( $i = 0; $i < $self->columns->options_count; $i++ )
    {
        $cells = $cols->[$i]->values;
        $newcells = $newcols->[$i]->values;

        foreach $nid ( keys %{ $newcells } )
        {
            $cells->{ $nid } = $newcells->{ $nid };
        }
    }

    return $self;
}

sub nodes
{
    # Niels Larsen, November 2005.

    # Gets or sets the nodes part of the display. 

    my ( $self,   # Display object
         $value,  # Nodes hash
         ) = @_;

    # Returns a display object. 

    if ( defined $value )
    {
        $self->{"nodes"} = $value;
        return $self;
    }
    else {
        return $self->{"nodes"};
    }
}

sub new_id_column
{
    # Niels Larsen, January 2005.
    
    my ( $class, 
         $ids,
         ) = @_;

    my ( $column, $id );

    foreach $id ( @{ $ids } )
    {
        $column->{ $id } = Taxonomy::Cells->new( "datatype" => "orgs_taxa",
                                                 "objtype" => "tax_id",
                                                 "value" => $id );
    }

    return $column;
}

sub new_checkbox_column
{
    # Niels Larsen, January 2005.
    
    # Creates a column structure for a given list of node ids,
    # where the value elements are checkbox cells. 

    my ( $class, 
         $ids,
         $checked,
         ) = @_;

    my ( $column, $cell, $id );

    foreach $id ( @{ $ids } )
    {
        $cell = Taxonomy::Cells->new();

        $cell->objtype( "checkbox" );
        $cell->selected( $checked );

        $column->{ $id } = $cell;
    }

    return $column;
}

sub new_stats_column
{
    # Niels Larsen, January 2005.
    
    my ( $class,
         $ids,
         ) = @_;

    my ( $column, $id );

    foreach $id ( @{ $ids } )
    {
        $column->{ $id } = Taxonomy::Cells->new( "css" => "std_button_up",
                                                 "abbreviate" => 1 );
    }

    return $column;
}

sub set_column
{
    my ( $self,
         $col,
         $ndx,
         ) = @_;

    my ( $cols );

    $cols = $self->columns->options;

    splice @{ $cols }, $ndx, 1, $col;

    $self->columns->options( $cols );

    return $self;
}

sub set_column_cells
{
    # Niels Larsen, January 2005.
    
    # Copies a given statistics hash into a given column.

    my ( $class,
         $column,
         $stats,
         ) = @_;

    my ( $id, $cell, $cells, $stat, $key );

    $cells = {};

    foreach $id ( keys %{ $stats } )
    {
        $stat = $stats->{ $id };

        $cell = Taxonomy::Cells->new(
                                     "css" => "std_button_up",
                                     "abbreviate" => 1,
                                     );
        
        foreach $key ( keys %{ $stat } )
        {
            $cell->$key( $stat->{ $key } );
        }

        $cell->objtype( $column->objtype );
        $cell->datatype( $column->datatype );

        $cells->{ $id } = $cell;
    }

    $column->values( $cells );

    return $column;
}

sub set_column_bgramp
{
    # Niels Larsen, January 2005.
    
    # Sets a background color ramp by adding a "style" key to each cell. 
    # The ramp is given by a start and end color value. Typically the highest
    # value receive the brightest color and the colors range between gray 
    # and white. 

    my ( $column,    # Column object
         $key,       # Node key
         $begcol,    # Starting color
         $endcol,    # Ending color
         $skipids,   # Ids to ignore
         ) = @_;

    # Returns an updated nodes hash.

    my ( $ramp, $id, @counts, @count_ids, $min_count, $max_count, $ramp_len,
         $scale, $index, $i, $style, $count, $cell, $hash );

    # Get minimum and maximum values,

    $hash = $column->values;
    $skipids = {} if not defined $skipids;

    foreach $id ( keys %{ $hash } )
    {
        next if $skipids->{ $id };

        $cell = $hash->{ $id };

        if ( defined ( $count = $cell->$key ) )
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

        $hash->{ $id }->style( $style );
    }

    return $column;
}

1;

__END__

sub insert_column
{
    my ( $self,
         $col,
         $ndx,
         ) = @_;

    my ( $cols );

    $cols = $self->columns;

    splice @{ $cols }, $ndx, 0, $col;

    $self->columns( $cols );

    return $self;
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
        $column->{ $id } = &Taxonomy::Display::new_sim_cell();
    }

    return $column;
}

1;

__END__
