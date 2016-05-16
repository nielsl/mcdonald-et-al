package Disease::Viewer;     #  -*- perl -*-

# Function specific viewer and related functions. The routine to call
# is 'main' which creates the display and invokes the all other 
# routines. This routine requires a session id, a user area where the 
# display structure and state is saved, and a disease database to pull
# from (TODO: de-couple the database). The database accessors are in 
# Disease::DB and the tree memory manipulation routines are in 
# Common::DAG::Nodes. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use List::Util;
use English;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_checkbox_row
                 &add_col_styles
                 &add_data_column
                 &add_checkbox_column
                 &add_data_column
                 &add_statistics_column
                 &create_columns
                 &delete_columns
                 &display_action_buttons
                 &display_checkbox_row
                 &display_col_headers
                 &display_id_cell
                 &display_menu_row
                 &display_report
                 &display_rows
                 &display_row
                 &display_stats_cell
                 &main
                 &parents_menu
                 &rebuild_display
                 &restore_display
                 &save_display
                 &save_selection
                 &save_selection_window
                 &search_window
                 &set_col_checkbox_values
                 &set_row_checkbox_values
                 &text_search
                 &update_display
                  );

use Disease::Help;
use Disease::Menus;
use Disease::DB;
use Disease::Users;
use Disease::Widgets;

use Common::DAG::Nodes;
use Common::DB;
use Common::File;
use Common::Util;
use Common::Widgets;
use Common::Config;
use Common::Messages;
use Common::Users;
use Common::Names;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_checkbox_row
{
    # Niels Larsen, February 2004.
    
    # Sets the "checked" key in all column elements, default 0. This will 
    # cause a row with checkboxes to appear on the page just above the column
    # headers. 

    my ( $dbh,           # Database handle
         $display,       # Display structure
         $request,       # Menu options index 
         $value,         # Whether checkboxes are checked - OPTIONAL, default 1
         ) = @_;

    # Returns an updated display structure. 

    my ( $elem, $menu, $info );
    
    foreach $info ( &Disease::Menus::control_info() )
    {
        if ( $info->{"request"} eq $request ) 
        {
            $menu = $info->{"menu"};
            last;
        }
    }

    if ( not $menu ) 
    {
        &error( qq (Request not found in control menu -> "$request") );
        exit;
    }

    # --------- Defaults,

    if ( defined $value ) {
        $value = 1;
    } else {
        $value = 0;
    }

    foreach $elem ( @{ $display->{"columns"} } )
    {
        $elem->{"checked"} = $value;
    }

    return wantarray ? %{ $display } : $display;
}    

sub add_col_styles
{
    # Niels Larsen, January 2004.

    # Adds background color values for select statistics column keys.
    # Typically the highest receive the brightest color and the colors
    # range between gray and white. 

    my ( $state,   # State hash
         $display, # Display structure
         ) = @_;

    # Returns an updated nodes hash.

    my ( $key, $ramp_keys, $ramp, @node_ids, $id, @counts, @count_ids,
         $count, $min_count, $max_count, $ramp_len, $scale, $index, $i,
         $col_ndx, $style, $columns, $nodes );

    $columns = $display->{"columns"};
    $nodes = $display->{"nodes"};

    $ramp_keys =
    {
        "do_terms_usum" => [ "#cccccc", "#ffffff" ],
        "do_terms_tsum" => [ "#cccccc", "#ffffff" ],
        "do_genes_node" => [ "#cccccc", "#ffffff" ],
        "do_genes_tsum" => [ "#cccccc", "#ffffff" ],
        "do_genes_usum" => [ "#cccccc", "#ffffff" ],
        "do_orgs_usum" => [ "#cccccc", "#ffffff" ],
    };

    @node_ids = keys %{ &Common::DAG::Nodes::get_ids_subtree_unique( $nodes, $state->{"do_root_id"} ) };

    $ramp_len = 50;

    for ( $col_ndx = 0; $col_ndx <= $#{ $columns }; $col_ndx++ )
    {
        $key = $columns->[ $col_ndx ]->{"key"};

        if ( $ramp_keys->{ $key } )
        {
            $ramp = &Common::Util::color_ramp( $ramp_keys->{ $key }->[0], 
                                               $ramp_keys->{ $key }->[1], $ramp_len+1 );

            @counts = ();
            @count_ids = ();
            
            foreach $id ( @node_ids )
            {
                $count = $nodes->{ $id }->{"column_values"}->[ $col_ndx ];

                if ( $count ) 
                {
                    push @counts, $count;
                    push @count_ids, $id;
                }
            }

            $min_count = &List::Util::min( @counts ) || 0;
            $max_count = &List::Util::max( @counts ) || 0;

            $scale = $ramp_len / ( $max_count - $min_count + 1);

            for ( $i = 0; $i < @counts; $i++ )
            {
                $id = $count_ids[ $i ];

                $index = int ( ( $counts[ $i ] - $min_count + 1 ) * $scale );
                $style = "background-color: " . $ramp->[ $index ];

                $nodes->{ $id }->{"column_styles"}->[ $col_ndx ] = $style;
            }
        }
        else 
        {
            foreach $id ( @node_ids )
            {
                $nodes->{ $id }->{"column_styles"}->[ $col_ndx ] = "";
            }
        }
    }

    $display->{"nodes"} = $nodes;

    return wantarray ? %{ $display } : $display;
}

sub add_checkbox_column
{
    # Niels Larsen, February 2004.
    
    # Adds a column of checkboxes immediately to the left of the tree.
    # TODO - remove bad hardcoded $options indices

    my ( $dbh,           # Database handle
         $display,       # Display structure
         $checked,       # Whether checkboxes are checked - OPTIONAL, default 0
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $columns, $nodes, $index, $i, $node_ids, $node_id, @match, $options, $col );

    $columns = $display->{"columns"};
    $nodes = $display->{"nodes"};

    # --------- Defaults,

    if ( defined $checked ) {
        $checked = 1;
    } else {
        $checked = 0;
    }

    # If there is already a checkbox column then we set $index to that
    # position so that column will be overwritten. If not then we set
    # it to the column just after the last so a column will be added,

    $index = scalar @{ $columns };

    for ( $i = 0; $i <= $#{ $columns }; $i++ )
    {
        $col = $columns->[ $i ];

        if ( $col->{"type"} eq "checkbox" )
        {
            $index = $i;
            last;
        }
    }

    # --------- Get ids of nodes to update,

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }
    
    # --------- Set column title,
    
    $options = &Disease::Menus::control_info();    
        
    if ( $checked ) {
        $columns->[ $index ] = &Storable::dclone( $options->[ 1 ] );
    } else {
        $columns->[ $index ] = &Storable::dclone( $options->[ 0 ] );
    }        
    
    # --------- Set values, status and style for nodes,
    
    foreach $node_id ( @{ $node_ids } )
    {
        $nodes->{ $node_id }->{"column_values"}->[ $index ] = $checked;
        $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
    }
    
    $display->{"columns"} = $columns;
    $display->{"nodes"} = $nodes;

    return wantarray ? %{ $display } : $display;
}    

sub add_data_column
{
    # Niels Larsen, October 2004.
    
    # Adds a column of data to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $dbh,           # Database handle
         $display,       # Display structure
         $optndx,        # Menu index of option to add 
         $colndx,        # Column index where to insert - OPTIONAL
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $columns, $nodes, $index, $node_ids, $node_id, @match, $info,
         $options, $option, $type, $key, $xrefs );

    $columns = $display->{"columns"};
    $nodes = $display->{"nodes"};

    $option = &Disease::Menus::data_info()->[ $optndx ];

    $type = $option->{"type"};
    $key = $option->{"key"};

    if ( not $key or not $type ) 
    {
        &error( qq (Option not found in data_menu with index "$optndx") );
        exit;
    }

    # If there is already a column of the given type and key then we 
    # dont overwrite it but just return. If not then we set the index
    # to the column just after the last so a column will be added,

    if ( @match = grep { $_->{"type"} eq $type and $_->{"key"} eq $key } @{ $columns } )
    {
        if ( scalar @match == 1 ) {
            return wantarray ? %{ $display } : $display;
        } else {
            &error( qq (More than one column with key "$key") );
            exit;
        }
    }
    else {
        $index = scalar @{ $columns };
    }

    # --------- Get ids of nodes to update,

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    # --------- Set column title,
    
    $columns->[ $index ] = &Storable::dclone( $option );
    
    # --------- Set column values,

    if ( $key eq "do_id" )
    {
        foreach $node_id ( @{ $node_ids } )
        {
            $nodes->{ $node_id }->{"column_values"}->[ $index ] = [ undef, $node_id ];
            $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
        }
    }
    elsif ( $key eq "do_icd9" )
    {
        $xrefs = &Disease::DB::get_xrefs( $dbh, "ICD9", $node_ids );

        foreach $node_id ( @{ $node_ids } )
        {
            if ( exists $xrefs->{ $node_id } )
            {
                $nodes->{ $node_id }->{"column_values"}->[ $index ] = [ undef, $xrefs->{ $node_id }->{"name"} ];
                $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
            }
            else
            {
                $nodes->{ $node_id }->{"column_values"}->[ $index ] = [ undef, undef ];
                $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
            }                
        }
    }
    
    return wantarray ? %{ $display } : $display;
}

sub add_statistics_column
{
    # Niels Larsen, February 2004.
    
    # Adds a statistics column to the left of the tree. If no insert
    # position is given its done immediately next to the tree. 

    my ( $dbh,           # Database handle
         $display,       # Display structure
         $optndx,        # Menu index of option to add 
         $colndx,        # Column index where to insert - OPTIONAL
         $root_id,       # Root node id - OPTIONAL
         ) = @_;

    # Returns an updated display structure. 

    my ( $columns, $nodes, $index, $node_ids, $node_id, @match,
         $options, $option, $type, $key, $stats );

    if ( not defined $optndx ) 
    {
        &error( qq (No statistics option index given) );
        exit;
    }

    $columns = $display->{"columns"};
    $nodes = $display->{"nodes"};

    $option = &Disease::Menus::statistics_info()->[ $optndx ];

    $type = $option->{"type"};
    $key = $option->{"key"};

    # If there is already a column of the given type and key then we 
    # dont overwrite it but just return. If not then we set the index
    # to the column just after the last so a column will be added,

    if ( @match = grep { $_->{"type"} eq $type and $_->{"key"} eq $key } @{ $columns } )
    {
        if ( scalar @match == 1 ) {
            return wantarray ? %{ $display } : $display;
        } else {
            &error( qq (More than one checkbox column found) );
            exit;
        }
    }
    else {
        $index = scalar @{ $columns };
    }

    # --------- Get ids of nodes to update,

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    # --------- Set column element,
    
    $columns->[ $index ] = &Storable::dclone( $option );
    
    # --------- Get column statistic,

    $stats = &Disease::DB::get_statistics( $dbh, $key, $node_ids );
    
    # --------- Set values, status and style for nodes,
    
    foreach $node_id ( @{ $node_ids } )
    {
        if ( exists $stats->{ $node_id } ) {
            $nodes->{ $node_id }->{"column_values"}->[ $index ] = $stats->{ $node_id }->{ $key };
        } else {
            $nodes->{ $node_id }->{"column_values"}->[ $index ] = undef;
        }
        
        $nodes->{ $node_id }->{"column_status"}->[ $index ] = undef;
    }

    $display->{"nodes"} = $nodes;
    $display->{"columns"} = $columns;
    
    return wantarray ? %{ $display } : $display;
}

sub create_columns
{
    # Niels Larsen, October 2004.

    # From a given list of column options, fills the corresponding
    # column values across the display. If a root id is given, starts
    # at that node.

    my ( $dbh,        # Database handle
         $sid,        # Session id
         $display,    # Display structure
         $columns,    # Column list
         $root_id,    # Root id - OPTIONAL
         $status,     # Status string - OPTIONAL
         ) = @_;

    # Returns an updated display structure.

    my ( $column, $type, $key, $index, $col_index, $opt_index, $ids );

    for ( $col_index = 0; $col_index <= $#{ $columns }; $col_index++ )
    {
        $column = $columns->[ $col_index ];

        $type = $column->{"type"};
        $key = $column->{"key"};
        $ids = $column->{"ids"};

        if ( defined $column->{"id"} ) {
            $opt_index = $column->{"id"};
        } else {
            $opt_index = $column;
        }            

        if ( $type eq "checkbox" )
        {
            if ( $key eq "checked" ) {
                $display = &Disease::Viewer::add_checkbox_column( $dbh, $display, "checked", $root_id );
            } elsif ( $key eq "unchecked" ) {
                $display = &Disease::Viewer::add_checkbox_column( $dbh, $display, undef, $root_id );
            }
        }
        elsif ( $type eq "statistics" )
        {
            $display = &Disease::Viewer::add_statistics_column( $dbh, $display, $opt_index,
                                                                $col_index, $root_id, $status );
        }
        elsif ( $type eq "data" )
        {
            $display = &Disease::Viewer::add_data_column( $dbh, $display, $opt_index, 
                                                          $col_index, $root_id );
        }
    }

    return wantarray ? %{ $display } : $display;
}    

sub delete_columns
{
    # Niels Larsen, February 2004.

    # Deletes columns with the indices identical to the given list. 

    my ( $display,       # Display structure
         $indices,       # Column index or indices 
         $root_id,       # Starting node id - OPTIONAL, default top node
         ) = @_;

    # Returns nothing, but updates headers and nodes.

    my ( $nodes, $node_ids, $node_id, %indices, @values, @status, $values,
         $status, $i, $columns );

    if ( not ref $indices ) {
        $indices = [ $indices ];
    }

    $columns = $display->{"columns"};    
    $nodes = $display->{"nodes"};    

    if ( not $root_id )
    {
        $columns = &Common::Menus::delete_items( $columns, $indices );
    }
    
    # If a starting node id given, use only the nodes in the subtree that
    # starts at that node. If not, set it to the root node and use all 
    # nodes,

    $nodes = $display->{"nodes"};

    if ( defined $root_id ) {
        $node_ids = &Common::DAG::Nodes::get_ids_subtree( $nodes, $root_id, 1 );
    } else {
        $root_id = &Common::DAG::Nodes::get_node_root( $nodes );
        $node_ids = &Common::DAG::Nodes::get_ids_all( $nodes );
    }

    %indices = map { $_*1, 1 } @{ $indices };

    foreach $node_id ( @{ $node_ids } )
    {
        @values = ();
        @status = ();

        $values = $nodes->{ $node_id }->{"column_values"};
        $status = $nodes->{ $node_id }->{"column_status"};

        for ( $i = 0; $i <= $#{ $display->{"columns"} }; $i++ )
        {
            if ( not exists $indices{ $i } )
            {
                push @values, $values->[ $i ];
                push @status, $status->[ $i ];
            }
        }

        $nodes->{ $node_id }->{"column_values"} = &Storable::dclone( \@values );
        $nodes->{ $node_id }->{"column_status"} = &Storable::dclone( \@status );
    }
    
    $display->{"columns"} = $columns;
    $display->{"nodes"} = $nodes;

    return wantarray ? %{ $display } : $display;
}

sub display_action_buttons
{
    # Niels Larsen, October 2004.

    # Prints a row of buttons, save selection and delete selection so 
    # far. It also prints a text string that indicates if the action
    # completed successfully. 

    my ( $sid,        # Session id
         $state,      # State hash
         $display,    # Display structure
         ) = @_;

    # Returns an xhtml string.

    my ( @cols, $xhtml, $index, $flag );

    $xhtml = qq (<table cellpadding="0" cellspacing="0" height="50"><tr>);
    
    if ( $state->{"do_save_rows_button"} )
    {
        $xhtml .= qq (<td valign="middle">)
                   . &Disease::Widgets::save_selection_button( $sid )
                   . "</td>";
        $flag = 1;
    }

    if ( $state->{"do_delete_rows_button"} and defined $state->{"do_selections_menu"} )
    {
         $index = $state->{"do_selections_menu"};
        
         $xhtml .= qq (<td valign="middle">)
                   . &Disease::Widgets::delete_selection_button( $sid, $index ) 
                    . "</td>";
         $flag = 1;
    }

    if ( $state->{"do_delete_cols_button"} )
    {
        $xhtml .= qq (<td valign="middle">)
                   . &Disease::Widgets::delete_columns_button( $sid ) 
                   . "</td>";

        $flag = 1;
    }

    if ( $state->{"screen_message"} ) 
    {
        $xhtml .= qq (<td width="20">&nbsp;</td><td><strong>$state->{"screen_message"}</strong></td>);
        delete $state->{"screen_message"};

        $flag = 1;
    }

    $xhtml .= qq (</tr></table>);

    if ( not $flag ) 
    {
        $xhtml = qq (<table><tr><td height="10">&nbsp;</td></tr></table>\n);
    }

    return $xhtml;
}

sub display_checkbox_cell
{
    # Niels Larsen, October 2004.

    # Displays a checkbox element.

    my ( $node,
         $index,
         ) = @_;

    # Returns an xhtml string.

    my ( $node_id, $value, $xhtml );

    $node_id = &Common::DAG::Nodes::get_id( $node );

    if ( ref $node->{"column_values"}->[ $index ] )
    {
        &error( qq (Checkbox cell value is not a scalar -> $node->{"column_values"}->[ $index ]) );
        exit;
    }
    else {
        $value = $node->{"column_values"}->[ $index ];
    }            
    
    if ( $value eq "1" ) {
        $xhtml .= qq (<td>&nbsp;<input type="checkbox" name="do_row_ids" value="$node_id" class="checkbox" checked />&nbsp;</td>);
    } else {
        $xhtml .= qq (<td>&nbsp;<input type="checkbox" name="do_row_ids" value="$node_id" class="checkbox" />&nbsp;</td>);
    }
    
    return $xhtml;
}

sub display_checkbox_row
{
    # Niels Larsen, February 2004.

    # Displays the row of column-checkboxes. This row can include
    # one or more headers for projection columns. 

    my ( $display,     # Display structure
         ) = @_;

    # Returns an xhtml string.

    my ( $columns, $key, $title, $text, $xhtml, $i, $style, 
         $type, $value, $icon_xhtml, $fgcolor, $bgcolor, $request );

    if ( grep { exists $_->{"checked"} } @{ $display->{"columns"} } )
    {
        $columns = $display->{"columns"};

        $xhtml = "";

        $key = "do_col_checkboxes";
        $title = "Delete checkboxes";
        $text = "Deletes the row of column checkboxes";

        $style = "std_col_checkbox";        
        $fgcolor ||= "#ffffcc";
        $bgcolor ||= "#cc6633";

        $icon_xhtml = &Disease::Widgets::cancel_icon();
        
        for ( $i = 0; $i <= $#{ $columns }; $i++ )
        {
            $type = $columns->[ $i ]->{"type"};
            $value = $columns->[ $i ]->{"checked"};

            if ( $type eq "checkbox" )
            {
                $xhtml .= qq (<td class="$style">$icon_xhtml</td>);
            }
            else
            {
                if ( $value ) {
                    $xhtml .= qq (<td class="$style"><input name="do_col_ids" type="checkbox" value="$i" checked></td>);
                } else {
                    $xhtml .= qq (<td class="$style"><input name="do_col_ids" type="checkbox" value="$i"></td>);
                }
            }
        }

        if ( not grep { $_->{"type"} eq "checkbox" } @{ $columns } )
        {
            $xhtml .= qq (<td><table><tr><td valign="middle" align="center" width="25">$icon_xhtml</td></tr></table></td>);
        }

        return $xhtml;
    }
    else {
        return;
    }
}

sub display_col_headers
{
    # Niels Larsen, December 2003.

    # Displays the header row for the GO graph. This row can include
    # one or more headers for projection columns, and always includes
    # a pull-down menu with the parent nodes of the current view. 

    my ( $dbh,        # Database handle
         $display,    # Display structure
         $state,      # State hash
         ) = @_;

    # Returns a string.

    my ( $xhtml, $title, $key, $root_node, $menu, $args, $link, $tip, $i,
         $col, $type, $len, $style, $columns, $nodes, $img );

    $columns = $display->{"columns"};
    $nodes = $display->{"nodes"};

    $root_node = $nodes->{ $state->{"do_root_id"} };

    # -------- Optional columns for statistics etc,

    for ( $i = 0; $i <= $#{ $columns }; $i++ )
    {
        $col = $columns->[ $i ];

        $key = $col->{"key"};
        $title = $col->{"col"};
        $len = length $title;

        $menu = $col->{"menu"} || "";
        $tip = $col->{"tip"} || "";
        $type = $col->{"type"} || "";
        
        if ( $type eq "checkbox" )
        {
            $img = qq (<img src="$Common::Config::img_url/sys_cancel_half.gif" border="0" alt="Cancel button" />);
            $link = qq (<a style="color: #ffffff" href="javascript:delete_column($i)">$img</a>);

            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$menu',FGCOLOR,'#ffffcc',BGCOLOR,'#990066',BORDER,3);
            $style = "do_col_title";
        }
        else
        {
            if ( $len <= 2 ) {
                $title = "&nbsp;&nbsp;&nbsp;$title&nbsp;&nbsp;&nbsp;";
            } elsif ( $len <= 3 ) {
                $title = "&nbsp;$title&nbsp;";
            }

            $link = qq (<a style="color: #ffffff" href="javascript:delete_column($i)">$title</a>);

            $args = qq (WIDTH,180,CENTER,BELOW,OFFSETY,20,CAPTION,'$menu',FGCOLOR,'#ffffcc',BGCOLOR,'#990066',BORDER,3);
            $style = "do_col_title";
        }
            
        if ( $title ) {
            $xhtml .= qq (<td class="$style" onmouseover="return overlib('$tip',$args);")
                    . qq ( onmouseout="return nd();">$link</td>);
        } else {
            $xhtml .= qq (<td></td>);
        }
    }

    # -------- Select menu that shows parent nodes,

    if ( $root_node->{"parent_ids"} and @{ $root_node->{"parent_ids"} } )
    {
        $xhtml .= "<td>". &Disease::Viewer::parents_menu( $dbh, $nodes, $state ) ."</td>";
    }

    if ( $xhtml ) {
        return qq (<tr>$xhtml</tr>\n);
    } else {
        return;
    }
}

sub display_id_cell
{
    # Niels Larsen, February 2004.

    # Creates the content of an id column cell. It includes the link 
    # that open up a small GO report. 

    my ( $sid,      # Session id
         $node,     # Node hash
         $nrel,     # Node relation
         $col_ndx,  # Column index 
         ) = @_;

    # Returns a string. 

    my ( $id, $url, $text, $value, $link, $xhtml );

    $id = &Common::DAG::Nodes::get_id( $node );

    $value = $node->{"column_values"}->[ $col_ndx ]->[1];

    if ( defined $value )
    {
        $url = qq ($Common::Config::cgi_url/index.cgi?session_id=$sid;page=disease;request=do_report;do_report_id=$id);
        $text = $value;

        if ( $nrel and $nrel eq "%" )    # is-a relation
        {
            $link = qq (<a style="font-weight: normal" href="javascript:open_window('popup','$url',600,700)">$text&nbsp;</a>);
            $xhtml = qq (<td class="light_grey_button_up">&nbsp;$link</td>);
        }
        elsif ( $nrel and $nrel eq "<" )    # part-of relation
        {
            $link = qq (<a style="font-weight: normal" href="javascript:open_window('popup','$url',600,700)">$text&nbsp;</a>);
            $xhtml = qq (<td class="orange_button_up">&nbsp;$link</td>);
        }
        else 
        {
            $link = qq (<a href="javascript:open_window('popup','$url',600,700)">$text&nbsp;</a>);
            $xhtml = qq (<td class="std_button_up">&nbsp;$link</td>);
        }
    }
    else {
        $xhtml = qq (<td></td>);
    }

    return $xhtml;
}

sub display_menu_row
{
    # Niels Larsen, February 2004.

    # Composes the top row on the page with title and icons. 

    my ( $sid,           # Session ID
         $display,       # Display structure
         $state,         # State hash
         ) = @_;
    
    # Returns an array. 

    my ( $columns, $nodes, $ids,
         $title_text, $root_node, @l_widgets, @r_widgets, @xhtml );

    $columns = $display->{"columns"};
    $nodes = $display->{"nodes"};

    # ------ Title box,

    if ( $state->{"do_terms_title"} )
    {
        $title_text = $state->{"do_terms_title"};
    }
    else
    {
        $root_node = $nodes->{ $state->{"do_root_id"} };

        $title_text = &Common::Names::format_display_name( $root_node->{"name"} );
        
        if ( $root_node->{"alt_name"} and length $root_node->{"name"} <= 50 ) {
            $title_text .= qq ( ($root_node->{"alt_name"}));
        }
    }
    
    push @l_widgets, &Common::Widgets::title_box( $title_text, "do_title" );

    # ------ Control menu,

    if ( $state->{"do_control_menu_open"} ) {
        push @l_widgets, &Disease::Widgets::control_menu( $columns );
    } else {
        push @l_widgets, &Disease::Widgets::control_icon();
    }

    # ------ Data menu,

    if ( $state->{"do_data_menu_open"} ) {
        push @l_widgets, &Disease::Widgets::data_menu( $columns, $state );
    } else {
        push @l_widgets, &Disease::Widgets::data_icon();
    }
    
    # ------ Statistics menu,

    if ( $state->{"do_statistics_menu_open"} ) {
        push @l_widgets, &Disease::Widgets::statistics_menu( $columns );
    }

    # ------ Terms save/restore menu,

    if ( -r "$Common::Config::ses_dir/$sid/do_selections" ) 
    {
        if ( $state->{"do_selections_menu_open"} ) {
            push @l_widgets, &Disease::Widgets::selections_menu( $sid, $state->{"do_terms_title"} );
        }
    }
    
    # ------ Search icon,

    push @r_widgets, &Disease::Widgets::search_icon( $sid );

    # ------ Help button,

    push @r_widgets, &Disease::Widgets::help_icon( $sid );

    # ------ Put everything together as a single row,

    push @xhtml, qq (<table><tr><td height="10">&nbsp;</td></tr></table>\n);
    push @xhtml, &Common::Widgets::title_area( \@l_widgets, \@r_widgets );

    return wantarray ? @xhtml : \@xhtml;
}

sub main
{
    # Niels Larsen, October 2004.

    # The user interface of a disease ontology graph. The routine first 
    # fetches a session hash where CGI arguments have been saved and padded
    # with defaults. The routine looks in the session to see what action 
    # to take and updates the display. The display data are kept as a hash
    # where keys are node ids and values are the fields one would like to
    # see painted on the tree. There are two kinds of queries: overlays, 
    # where the current display tree topology is not changed and searches
    # where the tree becomes the minimal subtree that exactly spans the 
    # results. This routine returns XHTML as a string. 

    my ( $session,      # CGI::Session object 
         ) = @_;

    # Returns a string.
    
    my ( @xhtml, $state, $root_node, $child, $root_id, $dbh, $nodes,
         $p_nodes, $title_text, $hdr_list, %col_keys, $match_nodes,
         @ids, $request, $sel, $ids, $id, $menu, $options,
         $xhtml, $add_count, $display, $col, $index, $columns, $cols, 
         $sid, $infos, $info, $sels, @cols, $opt_index, $i, $type, 
         $menu_requests, $state_key, $state_val, $node );

    if ( $session ) {
        $sid = $session->param("session_dir");
    } else {
        &error( qq (No session/user ID given) );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>> SET TABLE NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $Disease::DB::db_prefix = "do";
    $Disease::DB::id_name = "do_id";
    $Disease::DB::def_table = "do_def";
    $Disease::DB::edges_table = "do_edges";
    $Disease::DB::synonyms_table = "do_synonyms";
    $Disease::DB::xrefs_table = "do_xrefs";
    $Disease::DB::stats_table = "do_stats";

    $Disease::Schema::db_prefix = "do";
    $Disease::Schema::id_name = "do_id";
    $Disease::Schema::def_table = "do_def";
    $Disease::Schema::edges_table = "do_edges";
    $Disease::Schema::synonyms_table = "do_synonyms";
    $Disease::Schema::xrefs_table = "do_xrefs";
    $Disease::Schema::stats_table = "do_stats";

    $Common::DAG::DB::id_name = "do_id";
    $Common::DAG::Nodes::id_name = "do_id";

    # >>>>>>>>>>>>>>>>>>>>>>> LOAD CACHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # We store three caches and read them here for every click.

    # First a hash from file where the CGI parameters, if any, have
    # been merged in. The state hash contains instructions to the 
    # overall page about what should be shown, if menus are open etc.

    $state = &Disease::Users::restore_state( $sid );

    if ( not $state->{"do_click_id"} ) {
        $state->{"do_click_id"} = $state->{"do_root_id"};
    }

    # Then create the display structure. This is a hash with two main 
    # "columns" and "nodes". The first contains information about the 
    # column headers the second holds everything that is node specific.

    $dbh = &Common::DB::connect();

    $display = &Disease::Viewer::restore_display( $dbh, $sid, $state );

    if ( $display->{"columns"} ) {
        $columns = &Storable::dclone( $display->{"columns"} );
    } else {
        $columns = [];
    }

    $nodes = $display->{"nodes"};

    # >>>>>>>>>>>>>>>> CHECK MENUS FOR REQUEST <<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $state->{"do_control_menu"} )
    {
        $opt_index = $state->{"do_control_menu"};
        $state->{"request"} = &Disease::Menus::control_info()->[ $opt_index ]->{"request"};

        $state->{"do_control_menu"} = undef;
    }
    elsif ( defined $state->{"do_data_menu"} )
    {
        $opt_index = $state->{"do_data_menu"};
        $state->{"request"} = &Disease::Menus::data_info()->[ $opt_index ]->{"request"};

        $state->{"do_data_menu"} = undef;
    }

    # >>>>>>>>>>>>>>>>>>>>>> EXECUTE REQUESTS <<<<<<<<<<<<<<<<<<<<<<<<

    # This very long if-then-else tests on the incoming request and acts
    # on it. Some user actions require changes in the tree topology, some 
    # just what is being superimposed on it, or other actions. Currently
    # only one request is allowed at a time, but that would be easy to 
    # change. 

    $request = $state->{"request"};

    if ( $request )
    {
        $state->{"do_root_name"} = &Disease::DB::get_name_of_id( $dbh, $state->{"do_root_id"} );
        $root_id = $state->{"do_click_id"};

        # >>>>>>>>>>>>>>>>>>>>>>> SET MENU STATES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # This section updates state flags for which menus should be shown.
        # The setting of checkboxes is done in order to preserve checkbox
        # changes since last time they were saved. The hash below is done 
        # to avoid many similar if-then-elses. 

        $menu_requests->{"show_do_control_menu"} = [ "do_control_menu_open", 1 ];
        $menu_requests->{"hide_do_control_menu"} = [ "do_control_menu_open", 0 ];
        $menu_requests->{"show_do_data_menu"} = [ "do_data_menu_open", 1 ];
        $menu_requests->{"hide_do_data_menu"} = [ "do_data_menu_open", 0 ];
        $menu_requests->{"show_do_statistics_menu"} = [ "do_statistics_menu_open", 1 ];
        $menu_requests->{"hide_do_statistics_menu"} = [ "do_statistics_menu_open", 0 ];
        $menu_requests->{"show_do_selections_menu"} = [ "do_selections_menu_open", 1 ];
        $menu_requests->{"hide_do_selections_menu"} = [ "do_selections_menu_open", 0 ];
        $menu_requests->{"show_do_expression_menu"} = [ "do_expression_menu_open", 1 ];
        $menu_requests->{"hide_do_expression_menu"} = [ "do_expression_menu_open", 0 ];

        if ( $menu_requests->{ $request } )
        {
            $state_key = $menu_requests->{ $request }->[0];
            $state_val = $menu_requests->{ $request }->[1];

            $state->{ $state_key } = $state_val;

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );
            
            &Disease::Viewer::save_display( $sid, $display );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>> POPUP WINDOWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        elsif ( $request eq "help" )
        {
            $xhtml = &Disease::Help::general();
            
            $state->{"is_help_page"} = 1;
            $state->{"title"} = "Disease Help Page";

            &Common::Widgets::show_page( $xhtml, $sid, $state );
            exit;
        }
        elsif ( $request eq "search_window" )
        {
            $xhtml = &Disease::Viewer::search_window( $session );

            $state->{"is_popup_page"} = 1;
            $state->{"title"} = "Disease Search Page";
            $state->{"page"} = "disease";

            &Common::Widgets::show_page( $xhtml, $sid, $state );
            exit;
        }
        elsif ( $request eq "save_selection_window" )
        {
            $xhtml = &Disease::Viewer::save_selection_window( $session );

            $state->{"is_popup_page"} = 1;
            $state->{"title"} = "Disease Save Selection Page";
            $state->{"page"} = "disease";

            &Common::Widgets::show_page( $xhtml, $session->param("session_dir"), $state );
            exit;
        }
        elsif ( $request eq "do_report" )
        {
            $xhtml = &Disease::Viewer::display_report( $session, $state->{"do_report_id"} );

            $state->{"is_popup_page"} = 1;
            $state->{"title"} = "Disease Report Page";
            $state->{"page"} = "disease";

            &Common::Widgets::show_page( $xhtml, $session->param("session_dir"), $state );
            exit;
        }

        # >>>>>>>>>>>>>>>>>>> ADD CHECKBOX COLUMN AND ROW <<<<<<<<<<<<<<<<<<<

        # Here we attach lists to the display structure that the rendering
        # routines below knows how to handle. The $opt_index is the index of
        # each menu item selected, where the menu items come from 
        # Disease::Menus::control_info
        
        elsif ( $request eq "add_unchecked_column" ) 
        {
            $display = &Disease::Viewer::add_checkbox_column( $dbh, $display );

            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );
            &Disease::Viewer::save_display( $sid, $display );

            $state->{"do_save_rows_button"} = 1;
        }
        elsif ( $request eq "add_checked_column" ) 
        {
            $display = &Disease::Viewer::add_checkbox_column( $dbh, $display, "checked" );

            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );
            &Disease::Viewer::save_display( $sid, $display );

            $state->{"do_save_rows_button"} = 1;
        }
        elsif ( $request eq "add_unchecked_row" ) 
        {
            $display = &Disease::Viewer::add_checkbox_row( $dbh, $display, $request );

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::save_display( $sid, $display );

            $state->{"do_delete_cols_button"} = 1;
            $state->{"do_cols_checkboxes"} = 1;
        }
        elsif ( $request eq "add_checked_row" ) 
        {
            $display = &Disease::Viewer::add_checkbox_row( $dbh, $display, $request, "checked" );

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::save_display( $sid, $display );

            $state->{"do_delete_cols_button"} = 1;
            $state->{"do_cols_checkboxes"} = 1;
        }
        elsif ( $request eq "add_compare_row" ) 
        {
            $display = &Disease::Viewer::add_checkbox_row( $dbh, $display, $request );

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::save_display( $sid, $display );

            $state->{"do_compare_cols_button"} = 1;
            $state->{"do_cols_checkboxes"} = 1;
        }

        # >>>>>>>>>>>>>>>>>>>>>> DELETE CHECKBOX ROW <<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "hide_do_col_checkboxes" )
        {
            foreach $col ( @{ $display->{"columns"} } )
            {
                delete $col->{"checked"};
            }

            &Disease::Viewer::save_display( $sid, $display );

            $state->{"do_delete_cols_button"} = 0;
            $state->{"do_cols_checkboxes"} = 0;
            $state->{"do_compare_cols_button"} = 0;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>> ADD DATA COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_data_column" )
        {
            $display = &Disease::Viewer::add_data_column( $dbh, $display, $opt_index, undef, $root_id );
            $state->{"do_data_menu"} = undef;

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );

            &Disease::Viewer::save_display( $sid, $display );
        }

        # >>>>>>>>>>>>>>>>>>>>> ADD STATISTICS COLUMN(S) <<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "add_statistics_column" )
        {
            $opt_index = $state->{"do_statistics_menu"};
            $display = &Disease::Viewer::add_statistics_column( $dbh, $display, $opt_index, undef, $root_id );

            $state->{"do_statistics_menu"} = undef;

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );

            &Disease::Viewer::save_display( $sid, $display );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> DELETE A COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_column" )
        {
            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );
            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );

            if ( $display->{"columns"}->[ $state->{"do_col_index"} ]->{"type"} eq "checkbox" ) {
                $state->{"do_save_rows_button"} = 0;
            }

            &Disease::Viewer::delete_columns( $display, $state->{"do_col_index"} );

            &Disease::Viewer::save_display( $sid, $display );
        }

        # >>>>>>>>>>>>>>>>>>>>> DELETE SELECTED COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_columns" )
        {
            &Disease::Viewer::delete_columns( $display, $state->{"do_col_ids"} );

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );

            &Disease::Viewer::save_display( $sid, $display );
        }

        # >>>>>>>>>>>>>>>>>>>>>>> SAVE TERMS SELECTION <<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "save_terms" )
        {
            $info = &Common::Users::do_selection_new( $dbh, $state );

            $info->{"ids"} = $state->{"do_row_ids"};
            $state->{"screen_message"} = &Disease::Viewer::save_selection( $sid, $info );

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );

            &Disease::Viewer::save_display( $sid, $display );
        }

        # >>>>>>>>>>>>>>>>>>>>>> DELETE TERMS SELECTION <<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request eq "delete_terms" )
        {
            $index = $state->{"do_info_index"};
            $sels = &Common::Users::do_selections_delete( $sid, $index );

            if ( $sels )
            {
                $index-- if $index > $#{ $sels };
                $sel = $sels->[ $index ];

                $display = &Disease::Viewer::rebuild_display( $dbh, $sid, $state, $display, $sel );

                &Disease::Viewer::set_row_checkbox_values( $display, $sel->{"ids"} );
                &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );
                
                $root_node = &Common::DAG::Nodes::get_nodes_ancestor( $display->{"nodes"}, $sel->{"ids"} );
                $state->{"do_root_id"} = &Common::DAG::Nodes::get_id( $root_node );

                $state->{"do_delete_rows_button"} = 1;
                $state->{"do_selections_menu"} = $index;
            }
            else
            {
                $state->{"request"} = "focus_node";
                $state->{"do_click_id"} = 1;
                $state->{"do_terms_title"} = "Human Disorder or Disease";

                $display = &Disease::Viewer::update_display( $dbh, $sid, $display, $state );

                $state->{"do_delete_rows_button"} = 0;
                $state->{"do_selections_menu_open"} = 0;
            }
            
            &Disease::Viewer::save_display( $sid, $display );
        }

        # >>>>>>>>>>>>>>> RECONSTRUCT DISPLAY FROM SAVED IDS <<<<<<<<<<<<<<<<<

        elsif ( $request eq "restore_terms_selection" )
        {
            $index = $state->{"do_selections_menu"};
            $sel = &Disease::Menus::selections_info( $sid )->[ $index ];

            $display->{"nodes"} = {};
            $display = &Disease::Viewer::rebuild_display( $dbh, $sid, $state, $display, $sel );

            &Disease::Viewer::set_row_checkbox_values( $display, $sel->{"ids"} );
            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );

            &Disease::Viewer::save_display( $sid, $display );

            $root_node = &Common::DAG::Nodes::get_nodes_ancestor( $display->{"nodes"}, $sel->{"ids"} );

            $state->{"do_root_id"} = &Common::DAG::Nodes::get_id( $root_node );
            $state->{"do_delete_rows_button"} = 1;
            $state->{"do_selections_menu"} = $index;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>> TEXT SEARCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $request =~ /^Search$/i )
        {
            $state->{"do_root_id"} = $state->{"do_search_id"};
    
            $display->{"nodes"} = &Disease::Viewer::text_search( $dbh, $state );
            $display->{"columns"} = [];

            $display = &Disease::Viewer::create_columns( $dbh, $sid, $display, $columns, $state->{"do_root_id"} );

            &Disease::Viewer::save_display( $sid, $display );

            $root_node = $display->{"nodes"}->{ $state->{"do_root_id"} };
            $state->{"do_root_name"} = $root_node->{"name"};
            
            $state->{"do_click_id"} = "";
            $state->{"do_terms_title"} = "";
        }

        # >>>>>>>>>>>>>>>>>>>>> NORMAL EDITING UPDATES <<<<<<<<<<<<<<<<<<<<<<<<

        # This includes open, close, focusing on sub-categories and different
        # types of expanding by the column pushbuttons,

        else
        {
            $display = &Disease::Viewer::update_display( $dbh, $sid, $display, $state );

            &Disease::Viewer::set_row_checkbox_values( $display, $state->{"do_row_ids"} );
            &Disease::Viewer::set_col_checkbox_values( $display, $state->{"do_col_ids"}, 1 );

            &Disease::Viewer::save_display( $sid, $display );

            $root_node = $nodes->{ $state->{"do_root_id"} };
            $state->{"do_root_name"} = $root_node->{"name"};
            
            $state->{"do_click_id"} = "";
            $state->{"do_terms_title"} = "";
        }
 
        $state->{"request"} = "";
        $state->{"do_info_type"} = "";
        $state->{"do_info_key"} = "";
        $state->{"do_info_menu"} = "";
        $state->{"do_info_col"} = "";
        $state->{"do_info_index"} = "";
        $state->{"do_info_ids"} = [];
    }

    if ( not @{ $display->{"columns"} } )
    {
        $state->{"do_delete_cols_button"} = 0;
        $state->{"do_delete_rows_button"} = 0;
        $state->{"do_save_rows_button"} = 0;
        $state->{"do_compare_cols_button"} = 0;
    }

    &Common::DB::disconnect( $dbh );

    # Add column styles,

    $display = &Disease::Viewer::add_col_styles( $state, $display );

    # >>>>>>>>>>>>>>>>>>>>>>> DISPLAY THE PAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # At the top of the page there is a row with widgets and pullout 
    # menus, then follows the skeleton,

    @xhtml = &Disease::Viewer::display_menu_row( $sid, $display, $state );

    # ------ Initialize hidden variables,

    # They are needed by the javascript functions,

    push @xhtml, qq (
<input type="hidden" name="page" value="" />
<input type="hidden" name="request" value="" />
<input type="hidden" name="do_click_id" value="" />
<input type="hidden" name="do_info_type" value="" />
<input type="hidden" name="do_info_key" value="" />
<input type="hidden" name="do_info_tip" value="" />
<input type="hidden" name="do_info_col" value="" />
<input type="hidden" name="do_info_menu" value="" />
<input type="hidden" name="do_info_index" value="" />
<input type="hidden" name="do_col_index" value="" />
<input type="hidden" name="do_info_ids" value="" />
<input type="hidden" name="do_col_ids" value="" />
<input type="hidden" name="do_row_ids" value="" />
<input type="hidden" name="do_show_widget" value="" />
<input type="hidden" name="do_hide_widget" value="" />
);

    # -------- Save button and delete button

    push @xhtml, &Disease::Viewer::display_action_buttons( $sid, $state, $display );

    # Each skeleton row is a table row,

    push @xhtml, qq (\n<table border="0" cellspacing="0" cellpadding="0">\n);

    # ------ Optional row with column checkboxes,
    
    push @xhtml, &Disease::Viewer::display_checkbox_row( $display );

    # ------ Optional row with column headers and parents menu,

    push @xhtml, &Disease::Viewer::display_col_headers( $dbh, $display, $state );

    # ------ Display children only if at the root,

    $root_id = $state->{"do_root_id"};

    push @xhtml, &Disease::Viewer::display_rows( $sid, $display, $root_id, undef, 0, $state );
    
    push @xhtml, qq (</table>\n);
    push @xhtml, qq (<table><tr><td height="15">&nbsp;</td></tr></table>\n);

    &Disease::Users::save_state( $sid, $state );
    
    return join "", @xhtml;
}

sub display_report
{
    # Niels Larsen, October 2004.

    # Produces a report page for a single entry. 

    my ( $session,   # CGI::Session object
         $id,        # Disease entry id
         ) = @_;

    # Returns a string. 

    my ( $dbh, $entry, $sql, $xhtml, $title, @matches, $linkstr, $str, $pubstr, $statstr,
         $width, $img, $elem, $text, $menu, @options, $menus, $key );

    $width = 20;
    
    $dbh = &Common::DB::connect();

    $entry = &Disease::DB::get_entry( $dbh, $id );

    &Common::DB::disconnect( $dbh );
    
    $xhtml = &Disease::Widgets::report_title( "Disease Ontology Entry" );

    $xhtml .= qq (<table cellpadding="0" cellspacing="0">\n);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # ID and name, 

    $id = $entry->{"do_id"};
    $text = &Common::Names::format_display_name( $entry->{"name"} );

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="do_report_title"><tr><td>Description</td></tr></table></td></tr>
<tr><td width="$width"></td><td class="do_report_key">ID</td><td class="do_report_value">$id</td><td width="$width"></td></tr>
<tr><td width="$width"></td><td class="do_report_key">Name</td><td class="do_report_value">$text</td><td width="$width"></td></tr>
);

    # Synonyms,

    if ( @{ $entry->{"synonyms"} } )
    {
        foreach $elem ( @{ $entry->{"synonyms"} } )
        {
            $text = &Common::Names::format_display_name( $elem->{"synonym"} );
            
            $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Synonym</td>)
                    . qq (<td class="do_report_value">$text</td><td width="$width"></td></tr>\n);
        }
    }
    else {
        $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Synonyms</td>)
                . qq (<td class="do_report_value">&nbsp;</td><td width="$width"></td></tr>\n);
    }
        
    # Descriptional text,

    if ( $entry->{"description"} ) {
        $text = $entry->{"description"};
    } else {
        $text = "&nbsp;";
    }

    $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Description</td>)
            . qq (<td class="do_report_value">$text</td><td width="$width"></td></tr>);

    # Comment,

    if ( $entry->{"comment"} ) {
        $text = $entry->{"comment"};
    } else {
        $text = "&nbsp;";
    }

    $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Comment</td>)
            . qq (<td class="do_report_value">$text</td><td width="$width"></td></tr>);
    
    # >>>>>>>>>>>>>>>>>>>>>>>> CROSS REFERENCES <<<<<<<<<<<<<<<<<<<<<<<<<<

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="do_report_title"><tr><td>Cross references</td></tr></table></td></tr>
);
    if ( @{ $entry->{"references"} } )
    {
        foreach $elem ( sort { $a->{"db_name"} cmp $b->{"db_name"} } @{ $entry->{"references"} } )
        {
            $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">$elem->{"db_name"}</td>)
                    . qq (<td class="do_report_value">$elem->{"db_id"}</td><td width="$width"></td></tr>\n);
        }
    }
    else 
    {
        $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">ICD9</td>)
                . qq (<td class="do_report_value">&nbsp;</td><td width="$width"></td></tr>\n);
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CONNECTS TO <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $xhtml .= qq (
<tr height="8"><td></td></tr>
<tr><td colspan="3"><table class="do_report_title"><tr><td>Parents and Children</td></tr></table></td></tr>
);
    
    # Parents,

    if ( @{ $entry->{"parents"} } )
    {
        @options = ();

        foreach $elem ( sort { $a->{"terms_total"} <=> $b->{"terms_total"} } @{ $entry->{"parents"} } )
        {
            $text = &Common::Names::format_display_name( $elem->{"name"} );
            $text .= qq ( (ID $elem->{"do_id"}));
            
            push @options, [ $elem->{"do_id"}, $text ];
        }
    
        if ( @options )
        {
            $menu = &Common::Widgets::select_menu( "do_parents_menu",      # Element name
                                                   \@options,              # List of tuples
                                                   $options[0]->[1],       # Selected option
                                                   "beige_menu",           # Style class 
                                                   );
            
            $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Parents</td>)
                   . qq (<td class="do_report_value" style="padding-top: 0px; padding-bottom: 0px;)
                   . qq (padding-left: 1px;">$menu</td><td width="$width"></td></tr>\n);
        }
    }
    else
    {
        $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Parents</td>)
                . qq (<td class="do_report_value" style="padding-top: 0px; padding-bottom: 0px;)
                . qq (padding-left: 1px;">&nbsp;</td><td width="$width"></td></tr>\n);
    }

    # Children,

    if ( @{ $entry->{"children"} } )
    {
        @options = ();

        foreach $elem ( sort { $a->{"terms_total"} <=> $b->{"terms_total"} } @{ $entry->{"children"} } )
        {
            $text = &Common::Names::format_display_name( $elem->{"name"} );
            $text .= qq ( (ID $elem->{"do_id"}));
            
            push @options, [ $elem->{"do_id"}, $text ];
        }
    
        if ( @options )
        {
            $menu = &Common::Widgets::select_menu( "do_parents_menu",      # Element name
                                                   \@options,              # List of tuples
                                                   $options[0]->[1],       # Selected option
                                                   "beige_menu",           # Style class 
                                                   );
            
            $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Children</td>)
                   . qq (<td class="do_report_value" style="padding-top: 0px; padding-bottom: 0px;)
                   . qq (padding-left: 1px;">$menu</td><td width="$width"></td></tr>\n);
        }
    }
    else
    {
        $xhtml .= qq (<tr><td width="$width"></td><td class="do_report_key">Children</td>)
                . qq (<td class="do_report_value" style="padding-top: 0px; padding-bottom: 0px;)
                . qq (padding-left: 1px;">&nbsp;</td><td width="$width"></td></tr>\n);
    }    
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     if ( $entry->{"terms_total"} )
#     {
#         $text = &Common::Util::commify_number( $entry->{"terms_total"} ) . " total";
#         $text .= "; " . &Common::Util::commify_number( $entry->{"terms_unique"} ) . " unique.";

#         $xhtml .= qq (
# <tr height="8"><td></td></tr>
# <tr><td colspan="3"><table class="do_report_title"><tr><td>Statistics</td></tr></table></td><td width="$width"></td></tr>
# <tr><td width="$width"></td><td class="do_report_key">Terms</td><td class="do_report_value">$text</td><td width="$width"></td></tr>
# );
#     }

    $xhtml .= "</table>\n";

     $xhtml .= qq (<table width="100%"><tr height="60"><td align="right" valign="bottom">
  <div class="do_report_author">Data maintained by <strong>Patricia Dyck and Rex Chisholm</strong>, Northwestern University, Chicago, U.S.A.</div>
  </td></tr></table>\n);

    return $xhtml;
}

sub display_rows
{
    # Niels Larsen, October 2004.
    
    # Goes through the graph structure and produces xhtml for each row.

    my ( $sid,      # User or session id
         $display,  # Display structure
         $nid,      # Starting node id
         $nrel,     # Node relation
         $indent,   # Starting indentation level
         $state,    # State hash
         ) = @_;

    # Returns a list. 

    my ( @xhtml, $child, $i, @cids, @rels, %rels, $cid, $rel, $columns );

    $columns = $display->{"columns"};

    $indent = 0 if not defined $indent;

    push @xhtml, &Disease::Viewer::display_row( $sid, $columns, $display->{"nodes"}->{ $nid },
                                                $nrel, $indent, $state );
    $indent += 1;

    @cids = &Common::DAG::Nodes::get_ids_children( $display->{"nodes"}->{ $nid } );
    @rels = &Common::DAG::Nodes::get_rels_children( $display->{"nodes"}->{ $nid } );

    for ( $i = 0; $i < @cids; $i++ ) {
        $rels{ $cids[$i] } = $rels[$i];
    }

    foreach $child ( sort { $a->{"name"} cmp $b->{"name"} }
                     &Common::DAG::Nodes::get_children_list( $display->{"nodes"}, $nid ) )
    {
        $cid = &Common::DAG::Nodes::get_id( $child );
        $rel = $rels{ $cid };

        push @xhtml, &Disease::Viewer::display_rows( $sid, $display, $cid, $rel, $indent, $state );
    }

    return wantarray ? @xhtml : \@xhtml;
}

sub display_row
{
    # Niels Larsen, October 2004.

    # Generates XHTML for a single row in the graph display, from a 
    # given node, indentation value and a state hash with various settings.
    
    my ( $sid,     # User or session id
         $columns, # Columns list
         $node,    # Node hash
         $nrel,    # Node relation
         $indent,  # Indentation 
         $state,   # State hash
         )= @_;

    # Returns a string. 

    my ( $text_xhtml, $xhtml, $width, $arrow, $arrow_link, $key, $text, $node_id,
         $class, $leaf_node, $has_children, $i, $statistics, $img, $url, $type,
         $tuple, $id, $status, $session_id, $counts, @tuples, $ramp, $number,
         $bgcolor, $style, $links, $link, $col_ndx, $col_row, $value, $value_sum );

    $node_id = $node->{"do_id"};

    $sid ||= "";

    if ( $node->{"leaf"} ) {
        $leaf_node = 1;
    } else {
        $leaf_node = 0;
    }        

    if ( &Common::DAG::Nodes::get_ids_children( $node ) ) {
        $has_children = 1;
    } else {
        $has_children = 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> HIERARCHY SKELETON <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This is the part that contains the text, the arrows and indentation 
    # spacer cells, or the "skeleton" part of the tree. 

    $text_xhtml = qq (<table border="0" cellspacing="0" cellpadding="0"><tr>);
    
    if ( defined $indent and $indent > 0 )
    {
        if ( $leaf_node ) {
            $width = 18 * ($indent - 1);
        } else {
            $width = 18 * $indent;
        }
            
        $text_xhtml .= qq (<td width="$width"></td>);
    }

    # Optional left open/close arrow,

    if ( $state->{"do_with_form"} )
    {
        if ( $leaf_node )
        {
            $text_xhtml .= qq (<td width="18" align="center">&nbsp;</td>);
        }
        else
        {
            if ( $has_children ) 
            {
                $arrow = &Common::Widgets::arrow_down;
                $arrow_link = qq (<a class="arrow_l" href="javascript:close_node($node_id)">$arrow</a>);
            }
            else
            {
                $arrow = &Common::Widgets::arrow_right;
                $arrow_link = qq (<a class="arrow_l" href="javascript:open_node($node_id)">$arrow</a>);
            }
            
            $text_xhtml .= qq (<td class="arrow_l">$arrow_link</td>);
        }
    }

    # Main text,

    if ( $node->{"text"} ) {
        $text = &Common::Names::format_display_name( $node->{"text"} );
    } elsif ( $node->{"name"} ) {
        $text = &Common::Names::format_display_name( $node->{"name"} );
    } else {
        &error( qq (Node "$node_id" has no name or text to display) );
        exit;
    }

    if ( exists $node->{"alt_name"} ) {
        $text .= qq ( ($node->{"alt_name"}));
    }

    if ( $leaf_node ) 
    {
        $text_xhtml .= qq (<td class="leaf">$text</td>);
    }
    else 
    {
        if ( $has_children ) {
            $text_xhtml .= qq (<td class="group_arrow"><a class="group" href="javascript:focus_node($node_id)">$text</a></td>);
        } else {
            $text_xhtml .= qq (<td class="group"><a class="group" href="javascript:focus_node($node_id)">$text</a></td>);
        }
    }

    # Optional right open/close arrow,

    if ( $state->{"do_with_form"} )
    {
        if ( $has_children )
        {
            $arrow = &Common::Widgets::arrow_right;
            $arrow_link = qq (<a class="arrow_r" href="javascript:open_node($node_id)">$arrow</a>);
            $text_xhtml .= qq (<td class="arrow_r" width="18" align="center">$arrow_link</td>);
        }
    }

    $text_xhtml .= qq (</tr></table>);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # These are the leftmost columns on the display. They show precomputed 
    # statistics.
    
    $xhtml = qq (<tr>);

    for ( $col_ndx = 0; $col_ndx <= $#{ $columns }; $col_ndx++ )
    {
        $key = $columns->[ $col_ndx ]->{"key"};
        $type = $columns->[ $col_ndx ]->{"type"};

        if ( $type eq "statistics" )
        {
            # ------ Total number of terms,

            if ( $key eq "do_terms_tsum" or $key eq "do_terms_usum" )
            {
                $xhtml .= &Disease::Viewer::display_stats_cell( $node, $key, $col_ndx, 1, 1, 1 );
            }
        }
        elsif ( $type eq "data" )
        {
            # ------ Term ids,
            
            if ( $key eq "do_id" or $key eq "do_icd9" )
            {
                $xhtml .= &Disease::Viewer::display_id_cell( $sid, $node, $nrel, $col_ndx );
            }
        }

        # ------ Term checkboxes,

        elsif ( $type eq "checkbox" )
        {
            $xhtml .= &Disease::Viewer::display_checkbox_cell( $node, $col_ndx );
        }
        else
        {
            &error( qq (Column type not recognized -> "$type") );
            exit;
        }
    }

    $xhtml .= qq (<td>$text_xhtml</td>);
    $xhtml .= qq (</tr>\n);
    
    return $xhtml;
}

sub display_stats_cell
{
    # Niels Larsen, October 2004.

    # Displays the content of a "cell" of the table of disease groups
    # and data columns. Three flags determine how the cell is shown: 
    # with numbers abbreviated or not, to include backgroud highlight
    # or not, and whether to put an expansion button or not. 

    my ( $node,        # Node structure
         $key,         # Column key 
         $index,       # Column index position
         $abr_flag,    # Abbreviation flag - OPTIONAL, default 1
         $css_flag,    # Style flag - OPTIONAL, default 1
         $exp_flag,    # Expand button flag - OPTIONAL, default 0
         ) = @_;

    # Returns an xhtml string.

    $abr_flag = 1 if not defined $abr_flag;
    $css_flag = 1 if not defined $css_flag;
    $exp_flag = 0 if not defined $exp_flag;

    my ( $xhtml, $value, $value_sum, $style, $node_id, $status, $links, $link );

    if ( ref $node->{"column_values"}->[ $index ] )
    {
        $value = $node->{"column_values"}->[ $index ]->[0];
        $value_sum = $node->{"column_values"}->[ $index ]->[1];
    }
    else
    {
        $value = 1;
        $value_sum = $node->{"column_values"}->[ $index ];
    }
    
    $style = $node->{"column_styles"}->[ $index ] || "";
    $node_id = &Common::DAG::Nodes::get_id( $node );
    $status = $node->{"column_status"}->[ $index ] || "";

    if ( defined $value_sum )
    {
        if ( $exp_flag and $value_sum <= 300 )
        {
            $link = qq (<img src="$Common::Config::img_url/report.gif" alt="Diseases" />);
            $links = "";
                    
            if ( &Common::DAG::Nodes::is_leaf( $node ) )
            {
                if ( defined $value )
                {
                    foreach ( 1 .. $value ) { $links .= $link; }

                    $xhtml .= qq (<td class="bullet_link">&nbsp;$links&nbsp;</td>);
                }
                else {
                    $xhtml .= qq (<td></td>);
                }
            }
            else
            {
                if ( $status eq "expanded" ) {
                    $xhtml .= qq (<td class="pink_button_down">);
                } else {
                    $xhtml .= qq (<td class="pink_button_up">);
                }

                if ( $key !~ /^do_terms/ )
                {
                    if ( defined $value and $value > 0 )
                    {
                        foreach ( 1 .. $value ) {
                            $links .= $link;
                        }
                        
                        $xhtml .= $links;
                    }
                }
                
                if ( $status eq "expanded" ) {
                    $xhtml .= qq (<a href="javascript:collapse_node($node_id,$index)">&nbsp;$value_sum&nbsp;</a></td>);
                } else {
                    $xhtml .= qq (<a href="javascript:expand_node($node_id,$index)">&nbsp;$value_sum&nbsp;</a></td>);
                }
            }
        }
        elsif ( $css_flag ) 
        {
            if ( $value_sum > 0 ) 
            {
                if ( $abr_flag ) {
                    $value_sum = &Common::Util::abbreviate_number( $value_sum );
                }
            
                $xhtml = qq (<td class="std_button_up" style="$style">&nbsp;$value_sum&nbsp;</td>);
            }
            else {
                $xhtml .= qq (<td></td>);
            }
        }
        else
        {
            if ( $value_sum > 0 ) 
            {
                if ( $abr_flag ) {
                    $value_sum = &Common::Util::abbreviate_number( $value_sum );
                }
                
                $xhtml = qq (<td class="std_button_up">&nbsp;$value_sum&nbsp;</td>);
            } 
            else {
                $xhtml .= qq (<td></td>);
            }
        }        
    }
    else
    {
        $xhtml .= qq (<td></td>);
    }
    
    return $xhtml;
}

sub parents_menu
{
    # Niels Larsen, October 2004.

    # Generates a pull-down menu where all parents to the current root (as
    # specified by the given state hash) are listed. The parents options
    # are sorted by the number of associated terms.

    my ( $dbh,     # Database handle
         $nodes,   # Nodes hash
         $state,   # State hash
         $title,   # Input field name
         ) = @_;

    # Returns an xhtml string.

    $title ||= "do_parents_menu";

    my ( $root_node, $name, $p_nodes, $id, $node, $xhtml, @options, 
         @menu_ids, $stats, $root_id );

    $root_node = $nodes->{ $state->{"do_root_id"} };
    $root_id = $root_node->{"do_id"};

    $name = &Common::Names::format_display_name( $root_node->{"name"} );

    $p_nodes = &Disease::DB::get_parents( $dbh, $root_id );
    delete $p_nodes->{ 0 };  # TODO: eliminate this

    @menu_ids = &Common::DAG::Nodes::get_ids_all( $p_nodes );

    $stats = &Disease::DB::get_statistics( $dbh, "do_terms_tsum", [ @menu_ids, $root_id ] );

    @options = [ $root_node->{"do_id"}, $name, $stats->{ $root_id }->{"do_terms_tsum"} ];
    
    foreach $id ( @menu_ids )
    {
        $node = $p_nodes->{ $id };
        $name = &Common::Names::format_display_name( $node->{"name"} );
        
        push @options, [ $id, $name, $stats->{ $id }->{"do_terms_tsum"} ];
    }

    @options = sort { $a->[2] <=> $b->[2] } @options;
    
    $xhtml = &Common::Widgets::select_menu( $title,                 # Element name
                                            \@options,              # List of tuples
                                            $options[0]->[1],       # Selected option
                                            "grey_menu",            # Style class 
                                            "javascript:handle_parents_menu(this.form.do_parents_menu)" );
    
    return $xhtml;
}

sub rebuild_display
{
    # Niels Larsen, October 2004.

    # Given a selection, creates display nodes that span the ids given
    # by the selection. We do not change the column part of the display,
    # but create column information. 

    my ( $dbh,       # Database handle
         $sid,       # Session id
         $state,     # State hash
         $display,   # Display structure
         $sel,       # Selection hash
         ) = @_;

    # Returns a nodes hash.

    my ( $nodes, $p_nodes, $root_node, $columns, $col, $index );

    $columns = &Storable::dclone( $display->{"columns"} );

    # Build node skeleton,

    $nodes = &Disease::DB::get_nodes( $dbh, $sel->{"ids"} );
    $p_nodes = &Disease::DB::get_nodes_parents( $dbh, $nodes );
    
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );
    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

    $display->{"nodes"} = $nodes;

    # Attach column values,

    $display->{"columns"} = [];
    $display = &Disease::Viewer::create_columns( $dbh, $sid, $display, $columns );

    # Update state,

    $state->{"do_terms_title"} = $sel->{"menu"};

    return wantarray ? %{ $display } : $display;
}

sub restore_display
{
    # Niels Larsen, October 2004.

    # Restores the display tree as a nodes hash fron the file do_display
    # under the user's directory. If this file does not exist then it is
    # created with the default display tree. There are three main keys in 
    # the display structure: "nodes" and "columns".

    my ( $dbh,         # Database handle
         $sid,         # Session ID
         $state,       # State hash
         ) = @_;

    # Returns a hash. 

    my ( $file, $nodes, $parent_nodes, $cols, $col, $id, $depth, 
         $display, $list, $info );

    $file = "$Common::Config::ses_dir/$sid/do_display";

    if ( -r $file )
    {
        # Get diplay previously saved,

        $display = &Common::File::retrieve_file( $file );
#        $display = &Common::File::eval_file( $file );
    }
    else
    {
        # Create default display,

        $info = &Disease::Menus::statistics_info();
        $cols = [ $info->[1] ];

        $id = $state->{"do_root_id"};
        $depth = 1;

        $nodes = &Disease::DB::open_node( $dbh, $id, $depth );

        $parent_nodes = &Disease::DB::get_parents( $dbh, $id );
        $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $parent_nodes, 1 );

        $nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $nodes );
        $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

        $display->{"nodes"} = $nodes;
        $display = &Disease::Viewer::create_columns( $dbh, $sid, $display, $cols, $id );

        &Common::File::store_file( $file, $display );
#        &Common::File::dump_file( $file, $display );

        # Save default disease selections,

        $list = &Disease::Menus::selections_info( $sid );
        &Disease::Users::save_selections( $sid, $list );
    }

    return wantarray ? %{ $display } : $display;
}

sub save_display
{
    # Niels Larsen, October 2004.

    # Saves the display to the file do_display under the user's directory. 

    my ( $sid,        # Session ID
         $display,    # Display structure
         ) = @_;

    # Returns nothing. 

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/do_display";

    &Common::File::store_file( $file, $display );
#    &Common::File::dump_file( $file, $display );

    return;
}

sub save_selection 
{
    # Niels Larsen, October 2004.

    # Saves an informational hash to a file under the users area. 
    # A text message is returned that tells if the saving went ok.
    
    my ( $sid,     # Session id
         $info,    # Information hash
         $index,   # Insertion index - OPTIONAL
         ) = @_;

    # Returns a string. 

    my ( $list, $len, $message );

    if ( not defined $info ) 
    {
        &error( qq (No info hash is given) );
        exit;
    }        
    elsif ( not $info->{"menu"} or not $info->{"col"} )
    {
        $message = qq (<font color="red">Please specify titles</font>);
    }
    elsif ( not $info->{"ids"} or not @{ $info->{"ids"} } )
    {
        $message = qq (<font color="red">Please make a selection</font>);
    }
    else
    {
        $list = &Common::Users::do_selections_add( $sid, $info, $index );
        $message = qq (<font color="green"><strong>Saved</strong></font>);
    }

    return $message;
}

sub save_selection_window
{
    # Niels Larsen, October 2004.

    # Creates a save selection page with title bar, close button and a 
    # form that accepts a menu title and a column header for the selection.

    my ( $session,   # CGI::Session object
         ) = @_;

    # Returns a string. 

    my ( $state, $title, $title_bar, $xhtml, $sid );

    # -------- Get state from file,

    $sid = $session->param("session_dir");
    $state = &Disease::Users::restore_state( $sid );

    # -------- Title,

    $title = qq (Save Selection);
    $title_bar = &Common::Widgets::popup_bar( $title, "form_bar_text", "form_bar_close" );

    # -------- Page html,

    $xhtml = qq (

<table cellpadding="0" cellspacing="0" width="100%">
<tr><td>
$title_bar
</td></tr>

<tr><td>
<div id="form_content">
<p>
Saved selections appear by their title in menus and as "projection columns" 
on different pages. Below you can enter the name that should appear in the 
menu and a short abbreviation to be used as column title. 
</p>
<form action="$Common::Config::cgi_url/index.cgi" method="post" target="main"
      onSubmit="opener.document.main.submit(); setTimeout('',1000); submit(); return false">

<input type="hidden" name="session_id" value="$sid" />
<input type="hidden" name="request" value="save_terms" />
<input type="hidden" name="do_info_key" value="do_terms_usum" />

<div id="search_box">
<table cellspacing="5">
<tr height="25">
   <td align="right">Menu title&nbsp;&raquo;</td>
   <td colspan="3"><input type="text" size="25" maxlength="25" name="do_search_text" value="">
</tr>
<tr height="25">
   <td align="right">Column header&nbsp;&raquo;</td>
   <td colspan="3"><input type="text" size="4" maxlength="4" name="do_search_text" value="" /></td>
</tr>
<tr>
   <td></td>
   <td height="60"><input type="submit" value="Save" class="grey_button" /></td>
</tr>
</table>
</div>

</form>
</div>
</td></tr></table>
);

    return $xhtml;
}

sub search_window
{
    # Niels Larsen, October 2004.

    # Creates a search page with title bar, close button and a form that 
    # specifies what to search against and how. 

    my ( $session,   # CGI::Session object
         ) = @_;

    # Returns a string. 

    my ( $state, $title, $title_bar, $xhtml, $sid, $dbh, $nodes, $p_nodes,
         $name, $search_text, $search_titles_menu, $root_id,
         $search_target, @target_options, $search_target_menu,
         $search_type, @type_options, $search_type_menu );

    $dbh = &Common::DB::connect();

    # -------- Get state from file,

    $sid = $session->param("session_dir");
    $state = &Disease::Users::restore_state( $sid );

    # -------- Title,

    $name = &Disease::DB::get_name_of_id( $dbh, $state->{"do_root_id"} );
    $name = &Common::Names::format_display_name( $name );

    $title = qq (Search "$name");
    $title_bar = &Common::Widgets::popup_bar( $title, "form_bar_text", "form_bar_close" );

    # -------- Initialize search box,

    $search_text = $state->{"do_search_text"} || "";

    $search_text =~ s/^\s*//;
    $search_text =~ s/\s*$//;

    # -------- Search titles,

    $nodes = &Disease::DB::get_nodes( $dbh, [ $state->{"do_root_id"} ] );
    $p_nodes = &Disease::DB::get_parents( $dbh, $state->{"do_root_id"} );

    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );

    $search_titles_menu = &Disease::Viewer::parents_menu( $dbh, $nodes, $state, "do_search_id" );

    &Common::DB::disconnect( $dbh );

    # -------- Target select menu,

    $search_target = $state->{"do_search_target"};

    @target_options = (
                       [ "ids", "ids" ],
                       [ "titles", "titles" ],
                       [ "icd9", "ICD9 codes" ],
                       [ "titles_synonyms", "titles + synonyms" ],
                       [ "descriptions", "descriptions" ],
                       [ "everything", "everything" ],
                       );
    
    $search_target_menu = &Common::Widgets::select_menu( "do_search_target",
                                                         \@target_options,
                                                         $search_target,
                                                         "grey_menu" );
    # -------- Type select menu,

    $search_type = $state->{"do_search_type"};

    @type_options = (
                     [ "partial_words", "partial words" ],
                     [ "name_beginnings", "name beginnings" ],
                     [ "whole_words", "whole words only" ],
                     );

    $search_type_menu = &Common::Widgets::select_menu( "do_search_type",
                                                       \@type_options,
                                                       $search_type,
                                                       "grey_menu" );

    # -------- Page html,

    $xhtml = qq (

<table cellpadding="0" cellspacing="0" width="100%">
<tr><td>
$title_bar
</td></tr>

<tr><td>
<div id="form_content">
<p>
The content in the search box below is used to search against the 
<strong>$name</strong> category or one of its parents. It is possible 
to search against ids, titles 
(with synonyms), the more verbose descriptions or everything at the 
same time. Matches may occur in the middle of names but can be limited
to whole words only, in which case your search word should have three
characters or more. The matching is done case-independently.
</p>
<form action="$Common::Config::cgi_url/index.cgi" target="main" method="post">

<input type="hidden" name="session_id" value="$sid" />

<div id="search_box">
<table cellspacing="5">
<tr height="25">
   <td align="right">Search</td>
   <td align="left">$search_titles_menu</td>
</tr>
<tr height="25">
   <td align="right">for</td>
   <td align="left"><input type="text" size="50" name="do_search_text" value=" $search_text" /></td>
</tr>
<tr height="25">
   <td align="right">against</td>
   <td><table cellspacing="0" cellpadding="0"><tr>
       <td>$search_target_menu</td>
       <td align="right">&nbsp;&nbsp;while matching&nbsp;&nbsp;</td>
       <td>$search_type_menu</td></tr></table>
   </td>
</tr>
<tr>
   <td></td>
   <td height="60"><input type="submit" name="request" value="Search" class="grey_button_up" /></td>
</tr>
</table>
</div>

</form>
</div>
</td></tr></table>
);

    return $xhtml;
}

sub set_col_checkbox_values
{
    # Niels Larsen, October 2004.

    # If there is a checkbox row in the given display, sets the values
    # for each column in a given list of ids and unsets the rest. 

    my ( $display,   # Display hash
         $ids,       # List of node ids
         $value,     # Value to set
         ) = @_;

    # Returns an updated display. 

    $value = 0 if not defined $value;

    my ( $id, $col, %ids, $i );

    %ids = map { $_, 1 } @{ $ids };
    
    for ( $i = 0; $i <= $#{ $display->{"columns"} }; $i++ )
    {
        $col = $display->{"columns"}->[ $i ];
        
        if ( $ids{ $i } ) {
            $col->{"checked"} = $value;
        }
    }
    
    return wantarray ? %{ $display } : $display;
}    

sub set_row_checkbox_values
{
    # Niels Larsen, October 2004.

    # If there is a checkbox column in the given display, sets the values
    # at the nodes in a given list of ids and unsets the rest. 

    my ( $display,   # Display hash
         $ids,       # List of node ids
         ) = @_;

    # Returns an updated display. 

    my ( $i, $col, %ids, $id, $nodes );

    $nodes = $display->{"nodes"};

    for ( $i = 0; $i <= $#{ $display->{"columns"} }; $i++ )
    {
        $col = $display->{"columns"}->[ $i ];
        
        if ( $col->{"type"} eq "checkbox" )
        {
            %ids = map { $_, 1 } @{ $ids };

            foreach $id ( &Common::DAG::Nodes::get_ids_all( $nodes ) )
            {
                if ( exists $ids{ $id } ) {
                    $nodes->{ $id }->{"column_values"}->[ $i ] = 1;
                } else {
                    $nodes->{ $id }->{"column_values"}->[ $i ] = 0;
                }
            }
        }
    }

    $display->{"nodes"} = $nodes;   # not necessary 

    return wantarray ? %{ $display } : $display;
}    

sub text_search
{
    # Niels Larsen, October 2004.

    # Returns a new subtree with text matches. EXPLAIN

    my ( $dbh,        # Database handle
         $state,      # State hash
         ) = @_;

    # Returns a nodes hash.
    
    my ( @ids, $match_nodes, $id, $p_nodes, $nodes, $node, $root_node,
         $root_id, $text, $type, $target, $count );

    $root_id = $state->{"do_root_id"};
    $text = $state->{"do_search_text"};
    $type = $state->{"do_search_type"};
    $target = $state->{"do_search_target"};

    if ( $target ne "ids" )
    {
        $text =~ s/^\s*//;
        $text =~ s/\s*$//;
        $text = quotemeta $text;
    }

    # This gets the nodes one level down whether or not anything
    # matches. Then one can see which nodes did not match.

    $nodes = &Disease::DB::open_node( $dbh, $root_id, 1 );

    # Get matching ids, if any, 

    @ids = &Disease::DB::text_search( $dbh, $root_id, $text, $type, $target );
    
    if ( @ids )
    {
        @ids = &Common::Util::uniqify( \@ids );

        $match_nodes = &Disease::DB::get_nodes( $dbh, \@ids, 0, 1 );
        
        if ( $target eq "ids" or $target eq "icd9" )
        {
            foreach $id ( @ids )
            {
                $node = $match_nodes->{ $id };
                $node->{"name"} = qq (<strong>$node->{"name"}</strong>);
            }
        }
        else
        {
            foreach $id ( @ids )
            {
                $node = $match_nodes->{ $id };

                if ( $node->{"name"} =~ /$text/i ) {
                    $node->{"name"} = $PREMATCH ."<strong>$MATCH</strong>". $POSTMATCH;
                }
            }
        }

        $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $match_nodes, 1 );

        $count = scalar @ids;

        if ( $count == 1 ) {
            $state->{"screen_message"} = qq (<font color="green">1 match</font>);
        } else {
            $state->{"screen_message"} = qq (<font color="green">$count matches</font>);
        }            
    }
    else {
        $state->{"screen_message"} = qq (<font color="brown">No match</font>);
    }            

    $p_nodes = &Disease::DB::get_nodes_parents( $dbh, $nodes, 0, 1 );
    $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $p_nodes );

    $nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $nodes );

    $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );
    
    if ( $target eq "ids" )
    {
        $root_node = &Common::DAG::Nodes::get_nodes_ancestor( $nodes, \@ids );
        $root_id = &Common::DAG::Nodes::get_id( $root_node );
    }

    return wantarray ? %{ $nodes } : $nodes;
}

sub update_display
{
    # Niels Larsen, October 2004.

    # Updates the GO skeleton according to editing requests. The requests 
    # include "open_node", "close_node", "focus_node", "focus_name", "expand_node"
    # "search". The request is kept in the given state hash under the "request"
    # key. The output is an updated nodes hash which contains all the nodes 
    # needed for display. 

    my ( $dbh,       # Database handle
         $sid,       # Session id
         $display,   # Display structure
         $state,     # Argument hash - OPTIONAL
         ) = @_;

    # Returns an updated nodes hash.

    my ( $request, $root_node, $id, $node, $tables, $depth, $col, $col_id,
         $name, $key, $col_key, $p_nodes, $p_ids, $p_rels, $columns, $i, 
         $click_id, $p_node, @nodes, $new_nodes, $parent_nodes, $col_type, 
         $col_ids, $nodes, $col_index, $c_ids, $c_rels, @ids );

    if ( not defined $dbh ) {
        &error( "Database file handle is un-defined" );
    }

    if ( not defined $state ) {
        $state = &Disease::Users::default_state();
    }
    
    $nodes = $display->{"nodes"};

    if ( $display->{"columns"} ) {
        $columns = &Storable::dclone( $display->{"columns"} );
    } else {
        $columns = [];
    }

    if ( not defined $nodes ) {
        $nodes = {};
    }
    
    $request = $state->{"request"} || "";
    $click_id = $state->{"do_click_id"};

    if ( $state->{"do_root_id"} ) {
        $depth = $nodes->{ $state->{"do_root_id"} }->{"depth"};
    } else {
        &error( "Depth is un-defined" );
    }   

    if ( $request eq "close_node" or $request eq "collapse_node" )
    {
        # Does not fetch anything from the database but simply amputates
        # the nodes in memory,

        $nodes = &Common::DAG::Nodes::delete_subtree( $nodes, $click_id, 1 );

        for ( $i = 0; $i <= $#{ $columns }; $i++ ) {
            &Common::DAG::Nodes::set_node_col_status( $nodes->{ $click_id }, $i, undef );
        }

        $display->{"nodes"} = $nodes;
    }
    else
    {
        if ( $request eq "focus_name" ) 
        {
            $click_id = &Disease::DB::get_id_of_name( $dbh, $state->{"do_root_name"} );

            $state->{"do_root_id"} = $click_id;
            $state->{"do_click_id"} = $click_id;

            $request = "focus_node";
        }

        # Dive into the database and attach new things,

        if ( $request eq "open_node" )
        {
            # Opens the node that is clicked on,

            $new_nodes = &Disease::DB::open_node( $dbh, $click_id, $depth );

            $new_nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $new_nodes );
            $new_nodes = &Common::DAG::Nodes::set_ids_children_all( $new_nodes );

            $p_ids = &Common::DAG::Nodes::get_ids_parents( $nodes->{ $click_id } );
            &Common::DAG::Nodes::set_ids_parents( $new_nodes->{ $click_id }, $p_ids );

            $p_rels = &Common::DAG::Nodes::get_rels_parents( $nodes->{ $click_id } );
            &Common::DAG::Nodes::set_rels_parents( $new_nodes->{ $click_id }, $p_rels );

            $nodes = &Common::DAG::Nodes::delete_subtree( $nodes, $click_id, 1 );
            $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $new_nodes, 1 );

            $display->{"nodes"} = $nodes;
            $display->{"columns"} = [];

            $display = &Disease::Viewer::create_columns( $dbh, $sid, $display, $columns, $click_id );
        }
        elsif ( $request eq "focus_node" )
        {
            # Fetches new nodes from the database where the clicked id is the parent,

            $nodes = &Disease::DB::open_node( $dbh, $click_id, $depth );

            if ( $click_id > 1 )
            {
                $parent_nodes = &Disease::DB::get_parents( $dbh, $click_id );
                $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $parent_nodes, 1 );
            }

            $nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $nodes );
            $nodes = &Common::DAG::Nodes::set_ids_children_all( $nodes );

            $display->{"nodes"} = $nodes;
            $display->{"columns"} = [];

            $display = &Disease::Viewer::create_columns( $dbh, $sid, $display, $columns, $click_id );
            $state->{"do_root_id"} = $click_id;
        }
        elsif ( $request eq "expand_node" )
        {
            # Let a column button do the expansion of nodes, so only nodes 
            # are visible that have some values in this column. 
            
            $col_id = $state->{"do_col_index"};
            $col = $columns->[ $col_id ];

            if ( $col->{"type"} eq "statistics" )
            {
                $new_nodes = &Disease::DB::expand_node( $dbh, $click_id, 9999 );
            }

            $new_nodes = &Common::DAG::Nodes::delete_ids_parent_orphan( $new_nodes );
            $new_nodes = &Common::DAG::Nodes::set_ids_children_all( $new_nodes );

            $nodes = &Common::DAG::Nodes::delete_subtree( $nodes, $click_id, 1 );

            $c_ids = &Common::DAG::Nodes::get_ids_children( $new_nodes->{ $click_id } );
            &Common::DAG::Nodes::set_ids_children( $nodes->{ $click_id }, $c_ids );

            $c_rels = &Common::DAG::Nodes::get_rels_children( $new_nodes->{ $click_id } );
            &Common::DAG::Nodes::set_rels_children( $nodes->{ $click_id }, $c_rels );
            
            $nodes = &Common::DAG::Nodes::merge_nodes( $nodes, $new_nodes );

            $display->{"nodes"} = $nodes;
            $display->{"columns"} = [];

            $display = &Disease::Viewer::create_columns( $dbh, $sid, $display, $columns, $click_id );

             foreach $id ( &Common::DAG::Nodes::get_ids_all( $new_nodes ), $click_id )
             {
                 for ( $i = 0; $i <= $#{ $columns }; $i++ )
                 {
                     if ( $i == $col_id ) {
                        &Common::DAG::Nodes::set_node_col_status( $nodes->{ $id }, $i, "expanded" );
                     } else {
                        &Common::DAG::Nodes::set_node_col_status( $nodes->{ $id }, $i, undef );
                     }                        
                 }
             }
        }
        else {
            &error( qq (Unrecognized update request -> "$request") );
        }
    }

    return wantarray ? %{ $display } : $display;
}

1;

__END__

sub check_column_selections
{
    # Niels Larsen, February 2004.

    # Returns nothing if two or more columns of same type have been
    # selected. Otherwise a printable message string is returned. 

    my ( $display,
         $ids,
         ) = @_;

    # Returns a string or nothing.

    my ( $message, @cols, %types, $types, $i );

    if ( scalar @{ $ids } < 2 )
    {
        $message = qq (<font color="red">Please select at least two columns</font>);
    }
    else
    {
        foreach $i ( @{ $ids } ) {
            push @cols, $display->{"columns"}->[ $i ];
        }

        %types = map { $_->{"type"}, 1 } @cols;
        $types = scalar ( keys %types );

        if ( $types > 1 )
        {
            $message = qq (<font color="red">Please select columns of the same type</font>);
        }
    }

    if ( $message ) {
        return $message;
    } else {
        return;
    }
}
