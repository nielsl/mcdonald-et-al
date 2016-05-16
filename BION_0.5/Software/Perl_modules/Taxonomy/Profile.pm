package Taxonomy::Profile;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that work with organism taxonomy profiles in some way. A profile is 
# a hash of lists that have parent and children elements, as described below.
# Tree nodes have a packed string of values, one for each sample. The outputs 
# are text and html table, so there are also table routines. 
#
# NOTE - the Nodes.pm module in this directory has overlapping functionality 
# with this one. All the basic tree functions of this module should be moved 
# into an updated Nodes.pm. That will break the old taxonomy viewer though,
# so for now it stays as is. 
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( *AUTOLOAD );

use List::Util;
use Tie::IxHash;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &count_sims_table
                 &count_table_columns
                 &create_page_html
                 &create_tables
                 &filter_table_min
                 &filter_table_rows
                 &filter_table_sum
                 &format_table
                 &format_table_html
                 &init_score_tree
                 &init_stats_format
                 &init_stats_profile
                 &init_stats_sims
                 &init_stats_table
                 &init_tax_tree
                 &is_packed_table
                 &list_datasets
                 &map_seqs_taxons
                 &map_table_taxons
                 &node_share_clip
                 &node_least_common
                 &normalize_table
                 &normalize_tree
                 &org_profile_format
                 &org_profile_format_args
                 &org_profile_format_level
                 &org_profile_getcols
                 &org_profile_mapper
                 &org_profile_mapper_args
                 &org_profile_merge
                 &org_profile_merge_args
                 &org_profile_sims
                 &org_profile_sims_args
                 &pcts_to_weights
                 &read_nosim_seqs
                 &read_seqs
                 &read_table
                 &round_table
                 &sum_sims_counts
                 &sum_table_columns
                 &tablify_tree
                 &tax_show_string
                 &taxify_sims
                 &titles_from_paths
                 &unpack_table
                 &unpack_table_clone
                 &write_stats
                 &write_stats_filter
                 &write_stats_format_dirs
                 &write_stats_profile
                 &write_stats_profile_sum
                 &write_stats_sims
                 &write_stats_sims_sum
                 &write_tables
);

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Table;
use Common::Util_C;
use Common::DBM;

use Registry::Args;

use Seq::IO;
use Seq::Simrank;

use Recipe::IO;
use Recipe::Steps;
use Recipe::Stats;

use Taxonomy::Config;
use Taxonomy::Tree;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TREE GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# See Taxonomy::Tree for description.

use constant OTU_NAME => Taxonomy::Tree::OTU_NAME;
use constant PARENT_ID => Taxonomy::Tree::PARENT_ID;
use constant NODE_ID => Taxonomy::Tree::NODE_ID;
use constant CHILD_IDS => Taxonomy::Tree::CHILD_IDS;
use constant NODE_SUM => Taxonomy::Tree::NODE_SUM;
use constant DEPTH => Taxonomy::Tree::DEPTH;
use constant SIM_SCORES => Taxonomy::Tree::SIM_SCORES;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE STRUCTURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# From the tree above are created tables that can be formatted and used for text
# and html output. A table is a hash with these keys,
#
#  col_count    => the number of columns
#  col_headers  => [ list of column header strings ]
#  col_totals   => [ list of integer column totals ]
#  mis_totals   => [ list of no-similarity counts ]
#  row_headers  => [ list of taxonomy strings ]
#  row_maxima   => [ list of integer row maxima ]
#  values       => [ row-first list of lists of integer scores ]

# The values can be packed or un-packed. These are titles and keys used in the 
# outputs,

my ( $Col_title, $Seq_title, $Row_title, $Tax_title, $Mis_title, $Mis_nid,
     $Len_nid, $Len_title, $Sim_nid, $Sim_title );

$Col_title = "Score sums for mapped reads";
$Seq_title = "Input read totals";
$Row_title = "Row max";
$Tax_title = "Taxonomic groups";

$Mis_nid = "__NO_MATCH__";
$Mis_title = "Input reads with no similarities";

$Len_nid = "__TOO_SHORT__";
$Len_title = "Input reads shorter than __value__";

$Sim_nid = "__LOW_SIMS__";
$Sim_title = "Input reads with similarities less than __value__";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OTHER GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Root_id, %Tax_levels, @Tax_levels, $Max_int, $Float_size,
     %Node_info, %Node_subs );

$Root_id = $Taxonomy::Tree::Root_id;

$Max_int = 2 ** 30;

# Taxonomy levels and depths,

tie %Tax_levels, "Tie::IxHash";

%Tax_levels = (
    "root" => "r__",
    "kingdom" => "k__",
    "phylum" => "p__",
    "class" => "c__",
    "order" => "o__",
    "family" => "f__",
    "genus" => "g__",
    "species" => "s__",
    "sequence" => "n__",
    );

@Tax_levels = keys %Tax_levels;

%Node_info = (
    "share_clip" => "Share equal similarities between clipped nodes",
    "least_common" => "Assign equal similarities to least common ancestor",
    );

%Node_subs = (
    "share_clip" => "Taxonomy::Profile::node_share_clip",
    "least_common" => "Taxonomy::Profile::node_least_common",
    );

$Float_size = &Common::Util_C::size_of_float();

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub count_sims_table
{
    # Niels Larsen, January 2013. 

    my ( $file,
         $split,
        ) = @_;

    my ( $fh, $counts, @counts, $line, $sims, $id, $in, $hits );

    $split //= 1;
    
    $fh = &Common::File::get_read_handle( $file );

    if ( $split )
    {
        while ( defined ( $line = <$fh> ) )
        {
            ( $id, undef, $sims ) = &Seq::Simrank::parse_sim_line( $line );
            
            $id = ( split "__SPLIT__", $id )[0];
            
            $counts->{ $id }->[0] += 1;
            
            if ( $sims ) {
                $counts->{ $id }->[1] += 1;
            }
        }

        foreach $file ( sort keys %{ $counts } )
        {
            push @counts, [ $file, @{ $counts->{ $file } } ];
        }
    }
    else
    {
        $in = 0;
        $hits = 0;

        while ( defined ( $line = <$fh> ) )
        {
            ( $id, undef, $sims ) = &Seq::Simrank::parse_sim_line( $line );
            
            $in += 1;
            $hits += 1 if $sims;
        }
        
        @counts = [ &File::Basename::basename( $file ), $in, $hits ];
    }
    
    &Common::File::close_handle( $fh );
        
    return wantarray ? @counts : \@counts;
}

sub count_table_columns
{
    # Niels Larsen, December 2012. 

    # Returns the number of value columns in a given table. 

    my ( $table,    # Table structure
        ) = @_;

    # Returns integer. 

    my ( @cols, $colnum );
    
    if ( &Taxonomy::Profile::is_packed_table( $table ) )
    {
        $colnum = scalar @{ $table->values->[0] };
    }
    else 
    {
        @cols = unpack "f*", $table->values->[0];
        $colnum = scalar @cols;
    }

    return $colnum;
}

sub create_page_html
{
    # Niels Larsen, December 2012. 

    # Creates a static HTML page with header and footer. Returns HTML text.

    my ( $table,     # Formatted unpacked table
         $args,      # Arguments hash
        ) = @_;

    # Returns string.
    
    my ( $html, $text, @rows, $row );

    $html = "";

    $html = &Recipe::Stats::html_header({"lhead" => $args->lhead, "rhead" => $args->rhead, "header" => $args->header });

    $html .= qq (<table style="margin-top: 1.5em; margin-left: 1.5em; margin-bottom: 2em">\n);

    if ( $text = $args->title ) {
        $html .= qq (<tr><td class="title">$text</td></tr>\n);
    }

    $html .= qq (<tr><td>\n);

    @rows = &Common::Table::table_to_array( $table );

    $html .= qq (<table cellspacing="0" cellpadding="0">\n);

    foreach $row ( @rows )
    {
        $html .= "<tr>". &Common::Tables::_render_html_row( $row, {"show_empty_cells" => 1, "show_zero_cells" => 0 } ) ."</tr>\n";
    }

    $html .= "</table>\n";
    $html .= qq (</table>\n);

    return $html;
}

sub create_tables
{
    # Niels Larsen, August 2012. 

    # Creates normalized and un-normalized tables, each with parents with 
    # summed up values, and each in text and html versions. Eight in all. Row 
    # and column totals are added, and taxonomy strings are placed as the 
    # rightmost column.

    my ( $tree,    # Taxonomy tree with scores
         $conf,    # Configuration hash
        ) = @_;

    # Returns nothing. 

    my ( $clobber, $text_args, $html_args, $ndx, $out_file, $row, $hdr, 
         $pack_table, $groups, $scores, $taxa, $out_table, $args, $tree_copy,
         $i, $j, $count, $html, $summary );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $clobber = $conf->clobber;
    
    $text_args = bless {
        "places" => $conf->places,
        "rowmax" => $conf->rowmax,
    };

    $html_args = bless {
        "lhead" => ( $conf->lhead || $ENV{"BION_RECIPE_TITLE"} || "Taxonomy profile" ),
        "rhead" => ( $conf->rhead || $ENV{"BION_RECIPE_SITE"} || "" ),
        "title" => $conf->title,
        "summary" => $summary,
        "header" => 1,
        "footer" => 1,
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> BASIC TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Creating unmodified tables ... ");

    # Text table,

    $out_file = $conf->otable;

    $pack_table = &Taxonomy::Profile::tablify_tree( $tree, $conf->rowmax );
    
    &Taxonomy::Profile::filter_table_min( $pack_table, $conf->minval ) if $conf->minval;
    &Taxonomy::Profile::filter_table_sum( $pack_table, $conf->minsum ) if $conf->minsum;

    $pack_table = &Taxonomy::Profile::round_table( $pack_table, $conf->places, $conf->rowmax );    
    $out_table = &Taxonomy::Profile::format_table( $pack_table, $text_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::Table::write_table( $out_table, $out_file );

    # HTML table page,

    $out_file = $conf->otable .".html";

    $out_table = &Taxonomy::Profile::format_table_html( $pack_table, $text_args );

    $html = &Taxonomy::Profile::create_page_html( $out_table, $html_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::File::write_file( $out_file, $html );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> NORMALIZED TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Creating normalized tables ... ");

    # Text table,

    $out_file = $conf->otable .".norm";
    
    $pack_table = &Taxonomy::Profile::tablify_tree( $tree );

    &Taxonomy::Profile::filter_table_min( $pack_table, $conf->minval ) if $conf->minval;
    &Taxonomy::Profile::filter_table_sum( $pack_table, $conf->minsum ) if $conf->minsum;

    $pack_table = &Taxonomy::Profile::normalize_table( $pack_table, $conf->colsum );
    $pack_table = &Taxonomy::Profile::round_table( $pack_table, $conf->places, $conf->rowmax );

    $out_table = &Taxonomy::Profile::format_table( $pack_table, $text_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::Table::write_table( $out_table, $out_file );

    # HTML table page,

    $out_file = $conf->otable .".norm.html";

    $out_table = &Taxonomy::Profile::format_table_html( $pack_table, $text_args );
    $html = &Taxonomy::Profile::create_page_html( $out_table, $html_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::File::write_file( $out_file, $html );
        
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SUMMED TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Creating summed tables ... ");

    # Text table,

    $out_file = $conf->otable .".sum";
    
    $tree_copy = &Storable::dclone( $tree );

    &Taxonomy::Tree::filter_min( $tree_copy, $conf->minval ) if $conf->minval;
    &Taxonomy::Tree::filter_sum( $tree_copy, $conf->minsum ) if $conf->minsum;

    &Taxonomy::Tree::sum_parents_tree( $tree_copy );

    $pack_table = &Taxonomy::Profile::tablify_tree( $tree_copy );
    $pack_table = &Taxonomy::Profile::round_table( $pack_table, $conf->places, $conf->rowmax );

    $out_table = &Taxonomy::Profile::format_table( $pack_table, $text_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::Table::write_table( $out_table, $out_file );
    
    # HTML table page,

    $out_file = $conf->otable .".sum.html";

    $out_table = &Taxonomy::Profile::format_table_html( $pack_table, $text_args );

    $html = &Taxonomy::Profile::create_page_html( $out_table, $html_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::File::write_file( $out_file, $html );
        
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>> SUMMED NORMALIZED TABLE <<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Creating summed normalized tables ... ");

    # Text table,

    $out_file = $conf->otable .".norm.sum";
    
    $tree_copy = &Storable::dclone( $tree );

    &Taxonomy::Tree::filter_min( $tree_copy, $conf->minval ) if $conf->minval;
    &Taxonomy::Tree::filter_sum( $tree_copy, $conf->minsum ) if $conf->minsum;

    &Taxonomy::Profile::normalize_tree( $tree_copy, $conf->colsum );
    &Taxonomy::Tree::sum_parents_tree( $tree_copy );

    $pack_table = &Taxonomy::Profile::tablify_tree( $tree_copy );
    $pack_table = &Taxonomy::Profile::round_table( $pack_table, $conf->places, $conf->rowmax );

    $out_table = &Taxonomy::Profile::format_table( $pack_table, $text_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::Table::write_table( $out_table, $out_file );

    # HTML table page,

    $out_file = $conf->otable .".norm.sum.html";

    $out_table = &Taxonomy::Profile::format_table_html( $pack_table, $text_args );
    $html = &Taxonomy::Profile::create_page_html( $out_table, $html_args );

    &Common::File::delete_file_if_exists( $out_file ) if $clobber;
    &Common::File::write_file( $out_file, $html );
        
    &echo_done("done\n");

    return;
}

sub filter_table_min
{
    # Niels Larsen, December 2012. 

    # Reduces a table so only rows containing a score higher than a given
    # threshold are kept. 

    my ( $table,     # Table structure
         $minval,    # Minimum value
        ) = @_;

    # Returns nothing.

    my ( $colnum, $subref, $argref, $count );

    # Define function that checks the maximum value at the current row and 
    # returns 1 if at least the minimum,

    $subref = sub
    {
        my ( $table, $index, $minval, $colnum ) = @_;

        if ( &Common::Util_C::max_value_float( 
                  $table->{"values"}->[ $index ], $colnum ) >= $minval )
        {
            return 1;
        }
        
        return;
    };

    # Submit this callback to the real filter routine,

    $argref = [ $minval, $table->col_count ];    
    $count = &Taxonomy::Profile::filter_table_rows( $table, $subref, $argref );

    return $count;
}

sub filter_table_rows
{
    # Niels Larsen, December 2012. 

    # Helper routine that reduces the number of rows by filter criteria 
    # and re-calculates the column totals. A given routine and arguments
    # are run on the structure made by Taxonomy::Profile::tablify_tree. 
    # Returns the number of rows removed.

    my ( $table,    # Packed table
         $subref,   # Routine reference
         $argref,   # Routine argument list
        ) = @_;

    # Returns a hash.

    my ( $rowmax, $rowndx, $count );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Splice out rows where the given function returns false,

    $rowmax = $#{ $table->values };

    $rowndx = 0;
    $count = 0;
    
    while ( $rowndx <= $rowmax )
    {
        if ( $subref->( $table, $rowndx, @{ $argref } ) )
        {
            $rowndx += 1;
        }
        else
        {
            splice @{ $table->row_headers }, $rowndx, 1;
            splice @{ $table->row_maxima }, $rowndx, 1 if $table->row_maxima;
            splice @{ $table->values }, $rowndx, 1;

            $rowmax -= 1;
            $count += 1;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> NEW COLUMN TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &Taxonomy::Profile::sum_table_columns( $table );

    $table->sco_total( &List::Util::sum( $table->col_totals ) );

    return $count;
}

sub filter_table_sum
{
    # Niels Larsen, December 2012. 

    # Reduces a table so only rows with a score sum higher than a given
    # threshold are kept. 

    my ( $table,     # Table structure
         $minsum,    # Minimum sum
        ) = @_;

    # Returns nothing.

    my ( $colnum, $subref, $argref, $count );

    # Define function that checks the maximum value at the current row and 
    # returns 1 if at least the minimum,

    $subref = sub
    {
        my ( $table, $index, $minsum, $colnum ) = @_;

        if ( &Common::Util_C::sum_array_float( 
                  $table->{"values"}->[ $index ], $colnum ) >= $minsum )
        {
            return 1;
        }
        
        return;
    };

    # Submit this callback to the real filter routine,

    $argref = [ $minsum, $table->col_count ];    
    $count = &Taxonomy::Profile::filter_table_rows( $table, $subref, $argref );

    return $count;
}

sub format_table
{
    # Niels Larsen, November 2012. 

    # Formats a table structure into something the Common::Table::write_table 
    # routine can print. 
    
    my ( $ptab,     # Packed or unpacked table
         $args,     # Arguments hash
        ) = @_;

    # Returns nothing. 

    my ( $defs, $conf, $tab, $format, $col_totals, $col_sum, $col_count,
         @row_headers );

    $defs = {
        "places" => 0,
        "rowmax" => 1,
    };

    $conf = &Registry::Args::create( $args, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> UNPACK IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Taxonomy::Profile::is_packed_table( $ptab ) ) {
        $tab = &Taxonomy::Profile::unpack_table_clone( $ptab );
    } else {
        $tab = $ptab;
    }

    $col_count = $tab->col_count;

    # @row_headers = $Tax_title, @{ $tab->row_headers };

    # >>>>>>>>>>>>>>>>>>>>>>> INSERT ROW SCORE TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<

    # If present and more than one column, add row score totals to values,

    if ( $tab->row_maxima and @{ $tab->row_maxima } and $col_count > 1 )
    {
        &Common::Table::splice_col( $tab, $col_count, 0, [ @{ $tab->row_maxima } ], $Row_title );
        $tab->row_maxima([]);

        $col_count += 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Format all values, assumed to be numbers,

    $format = "%.". ( $conf->places // 0 ) ."f";

    $tab = &Common::Table::format_numbers_col( $tab, $format );

    # >>>>>>>>>>>>>>>>>>>>>>> SPLICE TAXONOMY COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $tab->row_headers } )
    {
        &Common::Table::splice_col( $tab, $col_count, 0, $tab->row_headers, $Tax_title );
        $tab->row_headers([]);
    }

    # >>>>>>>>>>>>>>>>> UNSHIFT ROW OF COLUMN SCORE TOTALS <<<<<<<<<<<<<<<<<<<<
    
    if ( @{ $tab->col_totals } )
    {
        $col_totals = [ map { sprintf $format, $_ } @{ $tab->col_totals } ];
        
        # Only add sum if there are more than one column,

        if ( $conf->rowmax and $col_count > 1 )
        {
            $col_sum = &List::Util::sum( @{ $col_totals } );
            $col_totals->[0] = "# " . $col_totals->[0];

            unshift @{ $tab->values }, [ @{ $col_totals }, 
                                         ( sprintf $format, $col_sum ), $Col_title ];
        }
        else
        {
            $col_totals->[0] = "# " . $col_totals->[0];
            unshift @{ $tab->values }, [ @{ $col_totals }, $Col_title ];
        }            

        $tab->col_totals([]);
    }

    # >>>>>>>>>>>>>>>>>>>>>> UNSHIFT ROW OF READ TOTALS <<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $tab->col_reads } )
    {
        $col_totals = [ map { sprintf $format, $_ } @{ $tab->col_reads } ];

        if ( $conf->rowmax and $col_count > 1 )
        {
            $col_sum = &List::Util::sum( @{ $col_totals } );
            $col_totals->[0] = "# " . $col_totals->[0];

            unshift @{ $tab->values }, [ @{ $col_totals }, 
                                         ( sprintf $format, $col_sum ), $Seq_title ];
        }
        else
        {
            $col_totals->[0] = "# " . $col_totals->[0];
            unshift @{ $tab->values }, [ @{ $col_totals }, $Seq_title ];
        }

        $tab->col_reads([]);
    }

    # >>>>>>>>>>>>>>>>>>>>> UNSHIFT ROW OF NON-MATCHES <<<<<<<<<<<<<<<<<<<<<<<<

    # This goes as the first row in values,

    $col_totals = [ map { sprintf $format, $_ } @{ $tab->mis_totals } ];

    if ( $conf->rowmax and $col_count > 1 ) 
    {
        $col_sum = &List::Util::sum( @{ $col_totals } );
        $col_totals->[0] = "# " . $col_totals->[0];

        unshift @{ $tab->values }, [ @{ $col_totals }, 
                                     ( sprintf $format, $col_sum ), $Mis_title ];
    }
    else
    {
        $col_totals->[0] = "# " . $col_totals->[0];
        unshift @{ $tab->values }, [ @{ $col_totals }, $Mis_title ];
    }
    
    $tab->mis_totals([]);

    return wantarray ? %{ $tab } : $tab;
}

sub format_table_html
{
    # Niels Larsen, June 2012.
          
    # Creates a HTML file from an unformatted profile table as generated by 
    # the Taxonomy::Profile::unpack_table_clone routine.

    my ( $ptab,      # Table structure
         $args,      # Arguments hash
        ) = @_;

    # Returns nothing. 

    my ( $tab, $defs, $conf, $format, $row_tots, $col_tots, $ramp, $row,
         $elem, $html, @rows, $title, $col_elem, $unc, $ndx, $hdr, %skip, 
         $taxa, $vals, $ndcs, $names, $hdrs, $col_sum, $col_count );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "places" => 0,
        "rowmax" => 1,
    };

    $conf = &Registry::Args::create( $args, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> UNPACK IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Taxonomy::Profile::is_packed_table( $ptab ) ) {
        $tab = &Taxonomy::Profile::unpack_table_clone( $ptab );
    } else {
        $tab = $ptab;
    }

    $col_count = $tab->col_count;

    # >>>>>>>>>>>>>>>>>>>>>> SPLICE ROW TOTALS COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<

    # If the table has row maxima and if there is more than one column, add a 
    # right-most column with those maxima,

    if ( $tab->row_maxima and @{ $tab->row_maxima } and $col_count > 1 )
    {
        &Common::Table::splice_col( $tab, $tab->col_count, 0, $tab->row_maxima, $Row_title );
        $tab->row_maxima([]);

        $col_count += 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>> STYLE ALL NUMBER VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<

    %skip = ();

    if ( defined ( $ndx = &Common::Table::name_to_index( $Mis_title, $tab->row_headers ) ) ) {
        $skip{ $ndx } = 1;
    }

    $vals = &Common::Tables::colorize_numbers(
        $tab->values,
        {
            "rows" => [ grep { not $skip{ $_ } } ( 0 ... $tab->row_count - 1 ) ],
            "ramp" => [ &Common::Util::color_ramp( "#cccccc", "#ffffff" ) ],
        });
    
    $tab->values( $vals );
    $tab->values( &Common::Tables::align_columns_xhtml( $tab->values, "right" ) );
    
    foreach $row ( @{ $tab->values } )
    {
        $row = [ map { &Common::Table::set_elem_attrib( $_, "class" => "tax_cell" ) } @{ $row } ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>> SPLICE TAXONOMY COLUMN <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $tab->row_headers } )
    {
        $hdrs = $tab->row_headers;
        
        $hdrs = [ map { &Taxonomy::Profile::tax_show_string( $_ ) } @{ $hdrs } ];

        $hdrs = [ map { &Common::Table::set_elem_attrib( $_, "class" => "tax_cell_name" ) } @{ $hdrs } ];
        $hdrs = [ map { &Common::Table::set_elem_attrib( $_, "style" => "text-align: left" ) } @{ $hdrs } ];

        &Common::Table::splice_col( $tab, $col_count, 0, &Storable::dclone( $hdrs ) );
        
        $tab->row_headers([]);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> INSERT COLUMN TITLES <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $tab->col_headers } )
    {
        $elem = &Common::Table::set_elem_attrib( $Tax_title, "class" => "tax_col_title", "style" => "text-align: left" );
        
        $tab->col_headers([ map { &Common::Table::set_elem_attrib( $_, "class" => "tax_col_title" ) } @{ $tab->col_headers } ]);
        $tab->col_headers([ map { &Common::Table::set_elem_attrib( $_, "style" => "text-align: right" ) } @{ $tab->col_headers } ]);

        push @{ $tab->col_headers }, &Storable::dclone( $elem );
    }

    # >>>>>>>>>>>>>>>>>>>>>>> ROW OF COLUMN SCORE TOTALS <<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $tab->col_totals } )
    {
        # Add column totals as first row,

        $col_tots = $tab->col_totals;

        if ( $conf->rowmax and $col_count > 1 )
        {
            $col_sum = &List::Util::sum( @{ $col_tots } );
            $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "class" => "tot_cell" ) } ( @{ $col_tots }, $col_sum ) ];
        }
        else {
            $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "class" => "tot_cell" ) } ( @{ $col_tots } ) ];
        }

        $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "style" => "text-align: right" ) } @{ $col_tots } ];
        $col_elem = &Common::Table::set_elem_attrib( $Col_title, "class" => "tot_cell", "style" => "text-align: left" );

        unshift @{ $tab->values }, [ @{ $col_tots }, &Storable::dclone( $col_elem ) ];        
        $tab->col_totals([]);
    }

    # >>>>>>>>>>>>>>>>>>>> COLUMN READ TOTALS AT THE TOP <<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $tab->col_reads } )
    {
        $col_tots = $tab->col_reads;

        if ( $conf->rowmax and $col_count > 1 )
        {
            $col_sum = &List::Util::sum( @{ $col_tots } );
            $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "class" => "seq_cell" ) } ( @{ $col_tots }, $col_sum ) ];
        }
        else {
            $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "class" => "seq_cell" ) } ( @{ $col_tots } ) ];
        }

        $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "style" => "text-align: right" ) } @{ $col_tots } ];
        $col_elem = &Common::Table::set_elem_attrib( $Seq_title, "class" => "seq_cell", "style" => "text-align: left" );

        unshift @{ $tab->values }, [ @{ $col_tots }, &Storable::dclone( $col_elem ) ];        
        $tab->col_reads([]);
    }

    # >>>>>>>>>>>>>>>>>>>>>>> ROW OF NON-MATCH COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<

    $col_tots = $tab->mis_totals;

    if ( $conf->rowmax and $col_count > 1 )
    {
        $col_sum = &List::Util::sum( @{ $col_tots } );
        $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "class" => "mis_cell" ) } ( @{ $col_tots }, $col_sum ) ];
    }
    else {
        $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "class" => "mis_cell" ) } ( @{ $col_tots } ) ];
    }

    $col_tots = [ map { &Common::Table::set_elem_attrib( $_, "style" => "text-align: right" ) } @{ $col_tots } ];
    $col_elem = &Common::Table::set_elem_attrib( $Mis_title, "class" => "mis_cell", "style" => "text-align: left" );

    unshift @{ $tab->values }, [ @{ $col_tots }, &Storable::dclone( $col_elem ) ];    
    $tab->mis_totals([]);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT ALL NUMBERS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $format = "%.". ( $conf->places // 0 ) ."f";

    $tab->values( &Common::Tables::format_decimals( $tab->values, $format ) );
    $tab->values( &Common::Tables::commify_numbers( $tab->values ) );

    return wantarray ? %{ $tab } : $tab;
}

sub init_score_tree
{
    # Niels Larsen, January 2013.
    
    # Copies the subtree that exactly spans the given node ids from
    # a given source tree. Returns a tree structure as defined at the 
    # top of this module. 

    my ( $tree,    # Source tree 
         $nids,    # Node ids to span
        ) = @_;

    # Returns hash.

    my ( $subt, $nid, $id, $pid, $cid );

    # Create nodes with all parents, but with empty children ids,

    foreach $nid ( @{ $nids } )
    {
        $id = $nid;

        # Keep adding nodes and their parents while moving up in 
        # the tree until a parent node is set (or until the root 
        # node is hit, which has no parent),

        while ( not exists $subt->{ $id } )
        {
            $subt->{ $id } = &Storable::dclone( $tree->{ $id } );
            $subt->{ $id }->[CHILD_IDS] = [];

            if ( defined ( $pid = $tree->{ $id }->[PARENT_ID] ) ) {
                $id = $pid;
            } else {
                last;
            }
        }
    }

    # Set children ids. For all nodes, if it has a parent, then
    # include add this node to the children list,

    foreach $nid ( keys %{ $subt } )
    {
        if ( defined ( $pid = $subt->{ $nid }->[PARENT_ID] ) )
        {
            push @{ $subt->{ $pid }->[CHILD_IDS] }, $nid;
        }
    }

    # Cut the tree from the root and down, until a node is seen that has 
    # multiple children,

    $nid = $Root_id;

    while ( scalar @{ $subt->{ $nid }->[CHILD_IDS] } == 1 )
    {
        $cid = $subt->{ $nid }->[CHILD_IDS]->[0];
        delete $subt->{ $nid };

        $nid = $cid;
    }

    # Finally set node sum values to 1. These counts are incremented when 
    # the tree is pruned, to tell how many nodes there originally were,

    map { $subt->{ $_ }->[NODE_SUM] = 1 } @{ $nids };

    # Delete parent of root node,

    undef $subt->{ $nid }->[PARENT_ID];

    return ( $nid, $subt );
}

sub init_stats_format
{
    # Niels Larsen, June 2012. 

    # Copies argument settings into a stats structure convenient for writing
    # a statistics file with the required fields. Returns a hash.

    my ( $args,
        ) = @_;

    # Returns hash.

    my ( $stats );

    $stats->{"name"} = "organism-profile-format";

    if ( not $stats->{"title"} = $args->{"title"} ) {
        $stats->{"title"} = "Taxonomy profile filtering";
    }

    $stats->{"itable"} = $args->ifile;
    $stats->{"otable"} = $args->oname;
    
    $stats->{"params"} = [
        {
            "title" => "Taxonomy levels shown",
            "value" => $args->level // "All",
        },{
            "title" => "Minimum row score",
            "value" => $args->minval // 1,
        },{
            "title" => "Column name filter",
            "value" => $args->taxexp // "None",
        },{
            "title" => "Column totals",
            "value" => $args->colsum // "Observed average",
        }];
    
    return $stats;
}

sub init_stats_profile
{
    # Niels Larsen, June 2012. 

    # Copies argument settings into a stats structure convenient for writing
    # a statistics file with the required fields. Returns a hash.

    my ( $conf,
        ) = @_;

    # Returns hash.

    my ( $stats, $home, $file, $title );

    $stats->{"name"} = "organism-profile-mapper";
    $stats->{"title"} = "Taxonomy sequence profiling";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $conf->format eq "table" ) {
        $title = "Input clustered table";
    } else {
        $title = "Input merged sequences";
    }

    $stats->{"seqs"} = { "title" => $title, "value" => $conf->seqs };
    $stats->{"sims"} = { "title" => "Input sequence similarities", "value" => $conf->sims };

    $stats->{"taxdbm"} = { "title" => "Input reference taxonomy", "value" => $conf->taxdbm };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $stats->{"params"} = [
        {
            "title" => "Minimum similarity",
            "value" => $conf->minsim ."%",
        },{
            "title" => "Minimum oligo total",
            "value" => $conf->minoli,
        },{
            "title" => "Top matches used",
            "value" => $conf->topsim ."%",
        },{
            "title" => "Match weight factor",
            "value" => $conf->simwgt,
        },{
            "title" => "Maximum ambiguity",
            "value" => $conf->maxamb,
        }];

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $stats->{"profile"} = { "title" => "Binary output profile", "value" => $conf->profile };

    return $stats;
}

sub init_stats_sims
{
    # Niels Larsen, January 2013.

    # Copies argument settings into a stats structure convenient for writing
    # a statistics file with the required fields. Returns a hash.

    my ( $conf,
        ) = @_;

    # Returns hash.

    my ( $stats, $home, $file, $iseqs );

    $stats->{"name"} = "organism-profile-similarities";
    $stats->{"title"} = "Sequence similarity matching";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $iseqs = &Storable::dclone( $conf->ifiles );

    $stats->{"dbfile"} = { "title" => "Reference dataset", "value" => $conf->dbfile };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $stats->{"osims"} = { "title" => "Similarities table", "value" => $conf->osims };
    $stats->{"omiss"} = { "title" => "Non-match sequences", "value" => $conf->omiss };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $stats->{"params"} = [
        {
            "title" => "Forward matching",
            "value" => $conf->forward ? "yes" : "no",
        },{
            "title" => "Reverse matching",
            "value" => $conf->reverse ? "yes" : "no",
        },{
            "title" => "Minimum similarity",
            "value" => $conf->minsim ."%",
        },{
            "title" => "Oligo word length",
            "value" => $conf->wordlen,
        },{
            "title" => "Oligo step length",
            "value" => $conf->steplen,
        },{
            "title" => "Base quality encoding",
            "value" => $conf->qualtype // "None",
        },{
            "title" => "Minimum base quality",
            "value" => $conf->minqual ? $conf->minqual ."%" : "None",
        },{
            "title" => "Skip ambiguous bases",
            "value" => $conf->wconly ? "yes" : "no",
        },{
            "title" => "Top matches range",
            "value" => $conf->topsim ."%",
        }];

    return $stats;
}

sub init_stats_table
{
    # Niels Larsen, June 2012. 

    # Copies argument settings into a stats structure convenient for writing
    # a statistics file with the required fields. Returns a hash.

    my ( $conf,
        ) = @_;

    # Returns hash.

    my ( $stats );
    
    $stats->{"name"} = "organism-profile-table";
    $stats->{"title"} = "Taxonomy table profiling";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats->{"itable"} = { "title" => "Input table", "value" => $conf->itable };    
    $stats->{"dbfile"} = { "title" => "Reference dataset", "value" => $conf->dbfile };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $stats->{"oraw"} = { "title" => "Taxonomy profile (binary)", "value" => $conf->otable };    
    $stats->{"osims"} = { "title" => "Similarities table", "value" => $conf->osims };
    $stats->{"omiss"} = { "title" => "Un-classified sequences", "value" => $conf->omiss };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $stats->{"params"} = [
        {
            "title" => "Forward matching",
            "value" => $conf->forward ? "yes" : "no",
        },{
            "title" => "Reverse matching",
            "value" => $conf->reverse ? "yes" : "no",
        },{
            "title" => "Minimum similarity",
            "value" => $conf->minsim ."%",
        },{
            "title" => "Oligo word length",
            "value" => $conf->wordlen,
        },{
            "title" => "Oligo step length",
            "value" => $conf->steplen,
        },{
            "title" => "Skip ambiguous bases",
            "value" => $conf->wconly ? "yes" : "no",
        },{
            "title" => "Top matches range",
            "value" => $conf->topsim ."%",
        },{
            "title" => "Match weight factor",
            "value" => $conf->simwgt,
        },{
            "title" => "Column totals",
            "value" => $conf->colsum // "Observed average",
        }];
    
    return $stats;
}

sub init_tax_tree
{
    # Niels Larsen, January 2013.

    my ( $scos,
        ) = @_;

    my ( $tree );

    # Set root node,

    $tree->{ $Root_id }->[OTU_NAME] = "r__Root";
    $tree->{ $Root_id }->[NODE_ID] = $Root_id;
    $tree->{ $Root_id }->[PARENT_ID] = undef;

    # A node for the unmatched,

    $tree->{ $Mis_nid }->[OTU_NAME] = $Mis_title;
    $tree->{ $Mis_nid }->[NODE_ID] = $Mis_nid;
    $tree->{ $Mis_nid }->[PARENT_ID] = "tax_0";
    $tree->{ $Mis_nid }->[CHILD_IDS] = undef;

    # A node for too short sequences,

    $tree->{ $Len_nid }->[OTU_NAME] = $Len_title;
    $tree->{ $Len_nid }->[NODE_ID] = $Len_nid;
    $tree->{ $Len_nid }->[PARENT_ID] = "tax_0";
    $tree->{ $Len_nid }->[CHILD_IDS] = undef;

    # A node for too low similarity,

    $tree->{ $Sim_nid }->[OTU_NAME] = $Sim_title;
    $tree->{ $Sim_nid }->[NODE_ID] = $Sim_nid;
    $tree->{ $Sim_nid }->[PARENT_ID] = "tax_0";
    $tree->{ $Sim_nid }->[CHILD_IDS] = undef;

    if ( $scos )
    {
        $tree->{ $Root_id }->[SIM_SCORES] = $scos;
        $tree->{ $Mis_nid }->[SIM_SCORES] = $scos;
        $tree->{ $Len_nid }->[SIM_SCORES] = $scos;
        $tree->{ $Sim_nid }->[SIM_SCORES] = $scos;
    }

    return $tree;
}
    
sub is_packed_table
{
    # Niels Larsen, December 2012. 

    # Returns 1 if the given table has packed values, otherwise 
    # nothing.

    my ( $table,
        ) = @_;

    return 1 if not ref $table->values->[0];

    return;
}

sub list_datasets
{
    my ( @msgs );
    
    push @msgs, ["INFO", qq (Installed dataset names are one of:\n) ];
    
    map { push @msgs, ["INFO", "  $_" ] } @Taxonomy::Config::DB_names;
    
    &append_or_exit( \@msgs );

    return;
}
    
sub map_seqs_taxons
{
    # Niels Larsen, November 2012.

    # Builds a memory taxonomy tree from sequences, similarities and a taxonomy
    # key/value store. The sequence and similarity files are read one entry and
    # line at a time, and they must correspond. 

    my ( $args,
        ) = @_;

    # Returns a hash.
    
    my ( $seq_file, $sim_table, $tax_dbm, $col_hdrs, $min_oli, $sim_wgt,
         $seq_reader, $tax_dbh, $buf_size, $tax_tree, $col_ndcs, $ndx, $sim_list,
         $seqs, $read_count, $col_hdr, $seq_id, $sim_scos, $tax_ids, $sim, 
         $zeroes, $i, $list, $tax_id, $sim_sco, $sim_pct, $sco_sum, $parent_id,
         $seq_fh, $sim_fh, $line, $tot_oli, $sim_ids, $sim_pcts, $sim_id, $seq, 
         $tax_cache, $score, $col_ndx, $tax_scos, $sum, $ids, $scos, $sims,
         $col_reads, $node, @ids, $top_sim, $min_sim, $nid, $hdr, @col_hdrs,
         $counts, $max_sim, $min_grp, $tax_sub, $sub_code, $max_amb, $id );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $seq_file = $args->seq_file;     # Query sequence file with counts
    $sim_table = $args->sim_table;   # Similarity table file
    $tax_dbm = $args->tax_dbm;       # Connects sequence ids to taxonomy
    $tax_sub = $args->tax_sub;       # Node subroutine name
    $col_hdrs = $args->col_hdrs;     # Column titles
    $min_oli = $args->min_oli;       # Minimum number of oligos, skip if less
    $min_sim = $args->min_sim;       # Minimum similarity, skip if less
    $top_sim = $args->top_sim;       # Top similarity percentages to use
    $sim_wgt = $args->sim_wgt;       # Similarity weight exponent
    $min_grp = $args->min_grp;       # Minimum sub-group score percentage
    $max_amb = $args->max_amb;       # Maximum taxonomic ambiguity depth
    $buf_size = $args->buf_size;     # Sequences read buffer size

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Column header to index hash,

    $ndx = 0;
    $col_ndcs = { map { $_ => $ndx++ } @{ $col_hdrs } };

    # Convert from file names to header names - TODO fix this hack,

    @col_hdrs = &Taxonomy::Profile::titles_from_paths( $col_hdrs );

    # Packed string with the score values, used by C routines where it will 
    # map to a float array,

    $zeroes = pack "f*", (0) x scalar @{ $col_hdrs };

    # Initialize tree with root node,

    $tax_tree = &Taxonomy::Profile::init_tax_tree( $zeroes );

    $counts = {
        "reads" => 0,
        "mapped" => 0,
        "short" => 0,
        "nosim" => 0,
        "lowsim" => 0,
    };

    # >>>>>>>>>>>>>>>>>>>>>>>> PROCESS SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read one similarity per sequence and process the matches. The similarity
    # file must correspond 1:1 to the sequence file, i.e. be the similarities 
    # resulting from running that sequence file. If not, chaos.

    $seq_reader = &Seq::IO::get_read_routine( $seq_file );

    $seq_fh = &Common::File::get_read_handle( $seq_file );
    $sim_fh = &Common::File::get_read_handle( $sim_table );

    $tax_dbh = &Common::DBM::read_open( $tax_dbm );
    $tax_cache = bless {}, "Taxonomy::Tree";

    $col_reads = [ (0) x scalar @{ $col_hdrs } ];

    no strict "refs";

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SET NODE ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sub_code = $tax_sub->();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read a number of sequences into a list and then read one similarity for each 
    # of these,

    while ( $seqs = $seq_reader->( $seq_fh, $buf_size ) )
    {
        foreach $seq ( @{ $seqs } )
        {
            # Read similarity line by line,
            
            $line = <$sim_fh>;

            # Ignore similarities with oligo counts less than required,

            ( $seq_id, $tot_oli, $sim_list ) = &Seq::Simrank::parse_sim_line( $line, 1 );
            
            # To keep track of the sample name, a header name was appended to the 
            # ID outsite this routine; here we split that header from the ID,
            
            $col_hdr = ( split "__SPLIT__", $seq_id )[0];
            $col_ndx = $col_ndcs->{ $col_hdr };
            
            # Get the original read count if present, otherwise 1,
            
            if ( $seq->{"info"} =~ /seq_count=(\d+)/ ) {
                $read_count = $1;
            } else {
                $read_count = 1;
            }

            $counts->{"reads"} += $read_count;

            # Count the number of original reads per column,

            $col_reads->[ $col_ndx ] += $read_count;

            if ( $tot_oli < $min_oli )
            {
                # >>>>>>>>>>>>>>>>>>> SEQUENCE TOO SHORT <<<<<<<<<<<<<<<<<<<<<<
                
                # Increment the short-length counts,

                &Common::Util_C::add_value_float( $tax_tree->{ $Len_nid }->[SIM_SCORES], 
                                                  $col_ndx, $read_count );

                $counts->{"short"} += $read_count;
            }
            elsif ( $sim_list )
            {
                # >>>>>>>>>>>>>>>>>>>>>> CREATE SCORES <<<<<<<<<<<<<<<<<<<<<<<<

                if ( $sim_list->[0]->[1] >= $min_sim )
                {
                    # Convert sequence similarities to a taxa score tree,

                    $sim_scos = &Taxonomy::Profile::taxify_sims(
                        {
                            "tax_dbh" => $tax_dbh,
                            "tax_cache" => $tax_cache,
                            "tax_sub" => $sub_code,
                            "sim_list" => $sim_list,
                            "read_count" => $read_count,
                            "top_sim" => $top_sim,
                            "sim_wgt" => $sim_wgt,
                            "max_amb" => $max_amb,
                        });

                    if ( $sim_scos )
                    {
                        # >>>>>>>>>>>>>>>>> UPDATE SCORE TREE <<<<<<<<<<<<<<<<<
                    
                        # Some of the resulting nodes may be new, missing in the tree. 
                        # Here we update the tree with missing nodes if any, including 
                        # parents,
                    
                        if ( @ids = grep { not exists $tax_tree->{ $_ } } keys %{ $sim_scos } )
                        {
                            $ids = &Taxonomy::Tree::load_new_nodes( $tax_dbh, \@ids, $tax_tree );

                            foreach $id ( @{ $ids } ) {
                                $tax_tree->{ $id }->[SIM_SCORES] = $zeroes;
                            }
                        }
                        
                        foreach $nid ( keys %{ $sim_scos } )
                        {
                            &Common::Util_C::add_value_float( 
                                 $tax_tree->{ $nid }->[SIM_SCORES], 
                                 $col_ndx, $sim_scos->{ $nid } );
                        }
                        
                        $counts->{"mapped"} += $read_count;
                    }
                    else {
                        $counts->{"ambig"} += $read_count;
                    }
                }
                else
                {
                    # >>>>>>>>>>>>>>>>>>> LOW SIMILARITY <<<<<<<<<<<<<<<<<<<<<<

                    &Common::Util_C::add_value_float( $tax_tree->{ $Sim_nid }->[SIM_SCORES], 
                                                      $col_ndx, $read_count );

                    $counts->{"lowsim"} += $read_count;
                }
            }
            else
            {
                # >>>>>>>>>>>>>>>>>>>>>>>> NO SIMILARITY <<<<<<<<<<<<<<<<<<<<<<
                
                &Common::Util_C::add_value_float( $tax_tree->{ $Mis_nid }->[SIM_SCORES], 
                                                  $col_ndx, $read_count );

                $counts->{"nosim"} += $read_count;
            }
        }
    }

    &Common::DBM::close( $tax_dbh );

    &Common::File::close_handle( $sim_fh );
    &Common::File::close_handle( $seq_fh );

    # Attach headers and number of reads,

    $tax_tree->{"col_headers"} = &Storable::dclone( \@col_hdrs );
    $tax_tree->{"col_reads"} = &Storable::dclone( $col_reads );

    bless $tax_tree, "Taxonomy::Tree";

    return ( $tax_tree, $counts );
}

sub map_table_taxons
{
    # Niels Larsen, November 2012.

    # Helper routine that builds a memory taxonomy tree with scores. The inputs
    # are a sequence list, a table of frequencies, a reference dataset similarity
    # file name, and a taxonomy key/value store with OTU names and their parents.
    # The sequence list and the similarity file have same number of elements/lines.

    my ( $args,          # Arguments hash
        ) = @_;

    # Returns a hash.
    
    my ( $con_file, $sim_table, $tax_dbm, $col_hdrs, $top_sim,
         $min_oli, $min_sim, $min_grp, $sim_wgt, $tax_dbh, $tax_tree, $sim_list,
         $seq_id, $zeroes, $i, @ids, $tax_id, $sim_fh, $line, $col_vals, 
         $seq_ndx, $col_count, $row_tots, $tax_cache, $col_reads, $freqs, 
         $ids, $scos, $counts, $sim_scos, $con_table, $buf_size, $nid,
         $tot_ndx, @con_seqs, $tot_oli, $tax_sub, $sub_code, $max_amb, $id );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $con_file = $args->con_table;      # Consensus table with counts and sequences
    $sim_table = $args->sim_table;     # Similarity table file
    $tax_dbm = $args->tax_dbm;         # Sequence id => taxonomy storage
    $tax_sub = $args->tax_sub;         # Node subroutine name
    $col_hdrs = $args->col_hdrs;       # Column titles
    $min_oli = $args->min_oli;         # Minimum number of oligos, skip if less
    $min_sim = $args->min_sim;         # Minimum similarity, skip if less
    $sim_wgt = $args->sim_wgt;         # Similarity weight exponentiator
    $top_sim = $args->top_sim;         # Top similarity percentages to use
    $min_grp = $args->min_grp;         # Minimum sub-group score percentage
    $max_amb = $args->max_amb;         # Maximum ambiguity level
    $buf_size = $args->buf_size;       # Sequences read buffer size

    # >>>>>>>>>>>>>>>>>>>>>>>> READ FREQUENCY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read table,

    $con_table = &Common::Table::read_table( $con_file );

    # Splice out sequences from table,

    ( $tot_ndx, $seq_ndx ) = &Common::Table::names_to_indices(
        ["Total", "Sequence"], $con_table->col_headers );

    @con_seqs = map {{
        "id" => ++$i,
        "seq" => $_->[$seq_ndx],
        "info" => "seq_count=$_->[$tot_ndx]",
        }}
    @{ $con_table->values };

    # Delete derived columns,

    $con_table = &Common::Table::delete_cols( $con_table, ["ID","Total","Totpct","Sequence"], 0 );

    $col_hdrs = $con_table->col_headers;
    $col_vals = $con_table->values;

    $col_count = scalar @{ $col_hdrs };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Packed string with the score values, used by C routines where it will 
    # map to a float array,

    $zeroes = pack "f*", (0) x scalar @{ $col_hdrs };

    # Initialize tree with root node,

    $tax_tree = &Taxonomy::Profile::init_tax_tree( $zeroes );

    # >>>>>>>>>>>>>>>>>>>>>>>> PROCESS SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read one similarity per sequence and process the matches. The similarity
    # file must correspond 1:1 to the sequence file, i.e. be the similarities 
    # resulting from running that sequence file. If not, chaos.

    $sim_fh = &Common::File::get_read_handle( $sim_table );
    $tax_dbh = &Common::DBM::read_open( $tax_dbm );

    $tax_cache = bless {}, "Taxonomy::Tree";
    $col_reads = [ (0) x scalar @{ $col_hdrs } ];

    $counts = {
        "reads" => 0,
        "mapped" => 0,
        "short" => 0,
        "nosim" => 0,
        "lowsim" => 0,
    };
    
    no strict "refs";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SET NODE ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sub_code = $tax_sub->();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read a number of sequences into a list and then read one similarity for each 
    # of these,

    for ( $seq_ndx = 0; $seq_ndx <= $#con_seqs; $seq_ndx += 1 )
    {
        $line = <$sim_fh>;

        # Ignore similarities with oligo counts less than required,

        #   ID     Oligos  Similarities
        ( $seq_id, $tot_oli, $sim_list ) = &Seq::Simrank::parse_sim_line( $line, 1 );

        # To keep track of the sample name, a header name was appended to the 
        # ID outsite this routine; here we split that header from the ID,
        
        $col_reads = &Common::Util::add_lists( $col_reads, $col_vals->[$seq_ndx] );
        
        $counts->{"reads"} += &List::Util::sum( @{ $col_vals->[$seq_ndx] } );

        # If there are matches process them, otherwise add count to the $Mis_nid node,
        
        if ( $tot_oli < $min_oli )
        {
            # >>>>>>>>>>>>>>>>>>>> SEQUENCE TOO SHORT <<<<<<<<<<<<<<<<<<<<<<<<<
            
            $row_tots = pack "f*", @{ $col_vals->[$seq_ndx] }; 

            &Common::Util_C::add_arrays_float( $tax_tree->{ $Len_nid }->[SIM_SCORES], 
                                               $row_tots, $col_count );

            $counts->{"short"} += &List::Util::sum( @{ $col_vals->[$seq_ndx] } );
        }
        elsif ( $sim_list )
        {
            # >>>>>>>>>>>>>>>>>>>>>>> CREATE SCORES <<<<<<<<<<<<<<<<<<<<<<<<<<<
            # 
            # Convert sequence similarities to taxa scores. 
            
            if ( $sim_list->[0]->[1] >= $min_sim )
            {
                $sim_scos = &Taxonomy::Profile::taxify_sims(
                    {
                        "tax_dbh" => $tax_dbh,
                        "tax_cache" => $tax_cache,
                        "tax_sub" => $sub_code,
                        "sim_list" => $sim_list,
                        "read_count" => 1,
                        "top_sim" => $top_sim,
                        "sim_wgt" => $sim_wgt,
                        "max_amb" => $max_amb,
                    });

                if ( $sim_scos )
                {
                    # >>>>>>>>>>>>>>>>> UPDATE SCORE TREE <<<<<<<<<<<<<<<<<<<<<
                    
                    # Some of the resulting nodes may be new, i.e. missing in the tree. Here we
                    # update the tree with missing nodes if any, including all parents,
                    
                    if ( @ids = grep { not exists $tax_tree->{ $_ } } keys %{ $sim_scos } )
                    {
                        $ids = &Taxonomy::Tree::load_new_nodes( $tax_dbh, \@ids, $tax_tree );

                        foreach $id ( @{ $ids } ) {
                            $tax_tree->{ $id }->[SIM_SCORES] = $zeroes;
                        }
                    }
                    
                    # Finally update scores for the ids,
                    
                    $freqs = pack "f*", @{ $col_vals->[$seq_ndx] };
                    
                    foreach $nid ( keys %{ $sim_scos } )
                    {
                        $row_tots = $freqs;
                        &Common::Util_C::mul_array_float( $row_tots, $sim_scos->{ $nid }, $col_count );
                        
                        &Common::Util_C::add_arrays_float( $tax_tree->{ $nid }->[SIM_SCORES],
                                                           $row_tots, $col_count );
                    }
                    
                    $counts->{"mapped"} += &List::Util::sum( @{ $col_vals->[$seq_ndx] } );
                }
                else {
                    $counts->{"ambig"} += &List::Util::sum( @{ $col_vals->[$seq_ndx] } );
                }
            }
            else 
            {
                $row_tots = pack "f*", @{ $col_vals->[$seq_ndx] }; 

                &Common::Util_C::add_arrays_float( $tax_tree->{ $Sim_nid }->[SIM_SCORES], 
                                                   $row_tots, $col_count );

                $counts->{"lowsim"} += &List::Util::sum( @{ $col_vals->[$seq_ndx] } );
            }
        }
        else
        {
            # No similarities. Increment the unclassified count,
            
            $row_tots = pack "f*", @{ $col_vals->[$seq_ndx] }; 

            &Common::Util_C::add_arrays_float( $tax_tree->{ $Mis_nid }->[SIM_SCORES], 
                                               $row_tots, $col_count );

            $counts->{"nosim"} += &List::Util::sum( @{ $col_vals->[$seq_ndx] } );
        }
    }

    &Common::DBM::close( $tax_dbh );
    &Common::File::close_handle( $sim_fh );

    # Attach headers and number of reads,
    
    $tax_tree->{"col_headers"} = &Storable::dclone( $col_hdrs );
    $tax_tree->{"col_reads"} = &Storable::dclone( $col_reads );

    bless $tax_tree, "Taxonomy::Tree";

    return ( $tax_tree, $counts );
}

sub node_share_clip
{
    # Niels Larsen, May 2013. 

    # Returns a routine that reduces mini-tree that similarities are mapped onto.
    # The routine input is a score tree with creates a Encodes Contains the Create a score tree skeleton by clipping it: if a node has multiple 
    # children, then delete those that are "leaves" i.e. have no children 
    # themselves. 
    # 

    my ( $subref );

    $subref = sub
    {
        # Create a score tree skeleton by clipping it: if a node has multiple 
        # children, then delete those that are "leaves" i.e. have no children 
        # themselves. 

        my ( $tree, $nid ) = @_;
        
        my ( $c_ids, $i );
    
        if ( scalar @{ $tree->{ $nid }->[CHILD_IDS] } > 1 )
        {
            $c_ids = $tree->{ $nid }->[CHILD_IDS];

            $i = 0;

            while ( @{ $c_ids } and $i <= $#{ $c_ids } )
            {
                if ( @{ $tree->{ $c_ids->[$i] }->[CHILD_IDS] } )
                {
                    $i += 1;
                }
                else 
                {
                    $tree->{ $nid }->[NODE_SUM] += 1;

                    delete $tree->{ $c_ids->[$i] };
                    splice @{ $c_ids }, $i, 1;
                }
            }
        }
        
        return;
    };
    
    return $subref;
}

sub node_least_common
{
    # Niels Larsen, May 2013.

    my ( $subref );

    $subref = sub
    {
        my ( $tree, $nid ) = @_;

        my ( $id );

        foreach $id ( keys %{ $tree } )
        {
            if ( $id ne $nid )
            {
                $tree->{ $tree->{ $id }->[PARENT_ID] }->[NODE_SUM] += 1;
                delete $tree->{ $id };
            }
        }

        $tree->{ $nid }->[CHILD_IDS] = [];
    };

    return $subref;
}

sub normalize_table
{
    # Niels Larsen, December 2012. 
    
    # Scales all values in a given table so the totals are the same in all 
    # columns. Totals are recalculated from the new values. Returns updated
    # table.

    my ( $table,    # Table with value strings
         $total,    # New column total - OPTIONAL, default the average
         $nunc,     # Dont normalize unmatched - OPTIONAL, default 1
        ) = @_;

    # Returns hash. 

    my ( $skip, $ndx, $row, $vals, $sum, $ratios, $maxrow, $values, $coltot );

    $nunc //= 1;

    # >>>>>>>>>>>>>>>>>>>>>>>>> SKIP NON-MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $nunc )
    {
        if ( defined ( $ndx = &Common::Table::name_to_index( $Mis_title, $table->row_headers ) ) ) {
            $skip->{ $ndx } = 1;
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>> SET SCALING RATIOS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $values = $table->{"values"};
    $maxrow = $#{ $values };
    $coltot = scalar @{ $table->col_headers };

    $vals = pack "f*", (0) x $coltot;

    for ( $ndx = 0; $ndx <= $maxrow; $ndx += 1 )
    {
        next if $skip->{ $ndx };
        &Common::Util_C::add_arrays_float( $vals, $values->[$ndx], $coltot );
    }

    if ( not defined $total ) {
        $total = &Common::Util_C::sum_array_float( $vals, $coltot ) / $coltot;
    }

    $ratios = "";
    
    foreach $sum ( unpack "f*", $vals )
    {
        if ( $sum == 0 ) {
            $ratios .= pack "f", 0;
        } else {
            $ratios .= pack "f", $total / $sum;
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> APPLY SCALING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    for ( $ndx = 0; $ndx <= $maxrow; $ndx += 1 )
    {
        next if $skip->{ $ndx };
        &Common::Util_C::mul_arrays_float( $values->[$ndx], $ratios, $coltot );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE NEW SUMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Row totals,

    $vals = "";

    foreach $row ( @{ $values } )
    {
        $vals .= pack "f", &Common::Util_C::max_value_float( $row, $coltot );
    }
    
    $table->{"row_maxima"} = [ unpack "f*", $vals ];

    # Column totals,

    $vals = pack "f*", (0) x $coltot;

    foreach $row ( @{ $values } )
    {
        &Common::Util_C::add_arrays_float( $vals, $row, $coltot );
    }
     
    $table->{"col_totals"} = [ unpack "f*", $vals ];

    # Table total,

    $table->{"sco_total"} = &List::Util::sum( @{ $table->{"row_maxima"} } );

    return $table;
}

sub normalize_tree
{
    # Niels Larsen, December 2012. 

    # Scales the column value strings of a tree so the total for each column
    # is the same. Each column is scaled to the given total. Returns nothing,
    # but the given tree is updated.

    my ( $nodes,    # Hash of nodes
         $total,    # Scaling total - OPTIONAL, default the average
        ) = @_;

    # Returns nothing.

    my ( $colnum, @cols, $sums, $sum, $subref, $argref, $ratios, $nid, $node );

    $colnum = &Taxonomy::Tree::count_columns( $nodes );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FIND SUMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sums = &Taxonomy::Tree::sum_subtree( $nodes, $Root_id );

    # >>>>>>>>>>>>>>>>>>>>>>>> SET SCALING RATIOS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( not defined $total ) {
        $total = &Common::Util_C::sum_array_float( $sums, $colnum ) / $colnum;
    }

    $ratios = "";

    foreach $sum ( unpack "f*", $sums )
    {
        if ( $sum == 0 ) {
            $ratios .= pack "f", 0;
        } else {
            $ratios .= pack "f", $total / $sum;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> APPLY SCALING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # TODO: this is a quick hack that fixes a summation bug in the commented 
    # code. FIX IT Likely something is wrong with the tree traversal or the 
    # parent-child connections.

    # foreach $nid ( keys %{ $nodes } )
    # {
    #     next if $nid eq "col_reads";
    #     next if $nid eq "col_headers";

    #     &Common::Util_C::mul_arrays_float( $nodes->{ $nid }->[SIM_SCORES], $ratios, $colnum );
    # };

    $subref = sub
    {
        my ( $nodes, $nid, $ratios, $colnum ) = @_;

        &Common::Util_C::mul_arrays_float( $nodes->{ $nid }->[SIM_SCORES], ${ $ratios }, $colnum );
    };
    
    $argref = [ \$ratios, $colnum ];

    &Taxonomy::Tree::traverse_head( $nodes, $Root_id, $subref, $argref );

    return;
}

sub org_profile_format
{
    # Niels Larsen, April 2012.
    
    # Filters and formats an organism taxonomy profile with scores. The profile
    # can be filtered by taxonomy group name expressions, by taxonomy level and
    # by taxonomy group score sums and minimum values. Tables are written in 
    # text and HTML formats, each in as-is, with parent sums, normalized and 
    # normalized summed versions. 

    my ( $args,
        ) = @_;

    # Returns nothing. 

    my ( $defs, $conf, $recipe, $level, $stats, $title, $count, $oname, 
         @stats, $stat_file, $stat_text );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "ifile" => undef,
        "level" => undef,
        "minsum" => 1,
        "minval" => 0,
        "taxexp" => undef,
        "colsum" => undef,
        "colexp" => undef,
        "rowmax" => 1,
        "barfile" => undef,
        "places" => 0,
        "title" => "Taxonomy profile",
        "lhead" => undef,
        "rhead" => undef,
        "oname" => undef,
        "osuffix" => undef,
        "stats" => undef,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Taxonomy::Profile::org_profile_format_args( $args );

    $count = 0;

    if ( defined $args->level )
    {
        &Taxonomy::Profile::org_profile_format_level( $conf );

        $count = 4;
    }
    else
    {
        $Common::Messages::silent = $conf->silent;

        &echo_bold("\nProfile tables:\n");

        $stat_file = $conf->stats;

        $conf->stats( undef );
        $conf->level( undef );

        $stat_text = "";

        foreach $level ( reverse keys %Tax_levels )
        {
            next if $level eq "root";

            &echo("   Writing $level tables ... ");

            if ( $args->title ) {
                $title = $args->title .", $level level";
            } else {
                $title = "Taxonomic profile, $level level";
            }

            if ( $oname = $args->oname ) {
                $oname .= ".$level";
            } else {
                $oname = undef;
            }

            $conf = &Taxonomy::Profile::org_profile_format_args(
                bless {
                    %{ $args },
                    "oname" => $oname,
                    "title" => $title,
                    "level" => $level,
                    "silent" => 1,
                },
                );

            $stat_text .= &Taxonomy::Profile::org_profile_format_level( $conf );

            $count += 4;

            &echo_done("done\n");
        }

        if ( $stat_file )
        {
            &echo("   Saving statistics ... ");
            
            &Common::File::delete_file_if_exists( $stat_file ) if $conf->clobber;
            &Common::File::write_file( $stat_file, $stat_text );
            
            &echo_done("done\n");
        }

        &echo_bold("Finished\n\n");
    }
    
    return $count;
}

sub org_profile_format_args
{
    # Niels Larsen, April 2012.

    # Checks command line arguments for org_profile_format with error messages
    # and returns a configuration hash that is convenient for the routine.

    my ( $args,
        ) = @_;

    # Returns a hash.

    my ( @msgs, %args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->ifile ) {
	$args{"ifile"} = &Common::File::check_files( [ $args->ifile ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", qq (No input organism profile given) ];
    }

    if ( $args->barfile ) {
	$args{"barfile"} = &Common::File::check_files( [ $args->barfile ], "efr", \@msgs )->[0];
    } else {
        $args{"barfile"} = undef;
    }
        
    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> OTHER PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( defined ( $args{"level"} = $args->level ) )
    {
        $args{"level"} = lc $args{"level"};

        if ( not exists $Tax_levels{ $args{"level"} } )
        {
            push @msgs, ["ERROR", qq (Wrong looking taxonomy level -> "$args{'level'}") ];
            push @msgs, ["INFO", qq (Choices are one of: ) ];
            
            map { push @msgs, ["INFO", "  $_" ] } @Tax_levels;
        }
    }

    $args{"minsum"} = $args->minsum;

    if ( defined $args{"minsum"} ) {
        $args{"minsum"} = &Registry::Args::check_number( $args{"minsum"}, 1, undef, \@msgs );
    }

    $args{"minval"} = $args->minval;

    if ( defined $args{"minval"} ) {
        $args{"minval"} = &Registry::Args::check_number( $args{"minval"}, 0, undef, \@msgs );
    }

    $args{"places"} = $args->places;

    if ( defined $args{"places"} ) {
        &Registry::Args::check_number( $args{"places"}, 0, 10, \@msgs );
    } 

    $args{"colsum"} = $args->colsum;

    if ( defined $args{"colsum"} ) {
        &Registry::Args::check_number( $args{"colsum"}, 1, undef, \@msgs );
    }

    $args{"taxexp"} = $args->taxexp;
    $args{"colexp"} = $args->colexp;
    $args{"rowmax"} = $args->rowmax;

    $args{"lhead"} = $args->lhead;
    $args{"rhead"} = $args->rhead;
    $args{"title"} = $args->title;
    $args{"titles"} = undef;

    $args{"clobber"} = $args->clobber;
    $args{"silent"} = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->oname ) {
        $args{"oname"} = $args->oname;
    } elsif ( $args->osuffix ) {
        $args{"oname"} = $args->ifile . $args->osuffix;
    } elsif ( $args{"level"} ) {
        $args{"oname"} = $args->ifile . ".". $args{"level"};
    } else {
        push @msgs, ["ERROR", qq (An output file name prefix must be given) ];
    }
    
    if ( @msgs ) {
        push @msgs, ["INFO", qq (Files are overwritten with --clobber) ];
    }
    
    &echo("\n") if @msgs;
    &append_or_exit( \@msgs );
    
    &Common::File::check_files( [ $args{"oname"} ], "!e", \@msgs ) if not $args->clobber;
    
    if ( $args->stats ) {
        $args{"stats"} = $args->stats;
    } elsif ( not defined $args->stats ) {
        $args{"stats"} = $args{"oname"} .".stats";
    } else {
        $args{"stats"} = undef;
    }
    
    if ( $args{"stats"} ) {
        &Common::File::check_files([ $args{"stats"}], "!e", \@msgs ) if not $args->clobber;
    }
    
    if ( @msgs ) {
        push @msgs, ["INFO", qq (Files are overwritten with --clobber) ];
    }
    
    &echo("\n") if @msgs;
    &append_or_exit( \@msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}

sub org_profile_format_level
{
    # Niels Larsen, January 2013. 

    # Helper routine for org_profile_format that writes files for one level
    # only. The input profile can be filtered by taxonomy group name expressions, 
    # by taxonomy level and by taxonomy group score sums and minimum values. 
    # Tables are written in text and HTML formats, each in as-is, with parent
    # sums, normalized and normalized summed versions. 

    my ( $conf,
        ) = @_;

    my ( $run_start, $stats, $tree, $node_count, $count, $level, @mis_tots,
         $table );

    local $Common::Messages::silent = $conf->silent;
    $run_start = time();

    $stats = &Taxonomy::Profile::init_stats_format( $conf );

    &echo_bold("\nProfile filtering:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> READ TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Reading input profile ... ");

    $tree = &Common::File::retrieve_file( $conf->ifile );
    
    $count = &Taxonomy::Tree::count_nodes( $tree );

    push @{ $stats->{"steps"} }, [ "Input groups", $count ];
    
    &echo_done("$count nodes\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> NEW COLUMN TITLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $conf->barfile or $conf->colexp )
    {
        &echo("   Re-titling table columns ... ");
        &Taxonomy::Profile::org_profile_getcols( $tree, $conf );
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> COLLAPSE TAXA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $count > 0 and $conf->level and $conf->level ne "sequence" )
    {
        $level = $conf->level;
        
        &echo("   Truncate to $level level ... ");
        
        $count = &Taxonomy::Tree::prune_level( $tree, $Tax_levels{ $level } );
        
        push @{ $stats->{"steps"} }, [ "Level truncation", $count ];
        
        &echo_done( "$count left\n");
    }
    
    # >>>>>>>>>>>>>>>>>>>>>> MINIMUM VALUE FILTERING <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $count > 0 and $conf->minval )
    {
        &echo("   Filtering by row value ... ");
        $count = &Taxonomy::Tree::filter_min( $tree, $conf->minval );
        
        push @{ $stats->{"steps"} }, [ "Row value filter", $count ];
        
        if ( $count > 0 ) {
            &echo_done( "$count left\n");
        } else {
            &echo_done("none left\n");
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>> MINIMUM SUM FILTERING <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $count > 0 and $conf->minsum )
    {
        &echo("   Filtering by row sum ... ");
        $count = &Taxonomy::Tree::filter_sum( $tree, $conf->minsum );
        
        push @{ $stats->{"steps"} }, [ "Row sum filter", $count ];
        
        if ( $count > 0 ) {
            &echo_done( "$count left\n");
        } else {
            &echo_done("none left\n");
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> TEXT FILTERING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $count > 0 and $conf->taxexp )
    {
        &echo("   Filtering by names ... ");
        $count = &Taxonomy::Tree::filter_regex( $tree, $conf->taxexp );
        
        push @{ $stats->{"steps"} }, [ "Text filter", $count ];
        
        if ( $count > 0 ) {
            &echo_done( "$count matched\n");
        } else {
            &echo_done("no matches\n");
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $count > 0 )
    {
        &Taxonomy::Profile::create_tables(
             $tree,
             bless {
                 "lhead" => $conf->lhead,
                 "rhead" => $conf->rhead,
                 "title" => $conf->title,
                 "otable" => $conf->oname,
                 "minval" => $conf->minval,
                 "minsum" => $conf->minsum,
                 "colsum" => $conf->colsum,
                 "rowmax" => $conf->rowmax,
                 "places" => $conf->places,
                 "clobber" => $conf->clobber,
             });

        $stats->{"reads"} = &List::Util::sum( @{ $tree->col_reads } ) // 0;

        $table = &Taxonomy::Profile::tablify_tree( $tree, $conf->rowmax );
        $stats->{"mapped"} = int ( &List::Util::sum( @{ $table->col_totals } ) || 0 );
    }

    $stats->{"seconds"} = time() - $run_start;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    if ( $conf->stats and not defined wantarray )
    {
        &echo("   Saving statistics ... ");
        &Common::File::delete_file_if_exists( $conf->stats ) if $conf->clobber;
        &Taxonomy::Profile::write_stats_filter( $conf->stats, bless $stats );
    }
    else
    {
        &echo("   Formatting statistics ... ");
        $stats = &Taxonomy::Profile::write_stats_filter( $conf->stats, bless $stats );
    }

    &echo_done("done\n");

    &echo_bold("Finished\n\n");

    return $stats;
}

sub org_profile_getcols
{
    # Niels Larsen, January 2013. 

    # If a barcode-file is given then use its IDs or sequences as titles and 
    # fall back on the barcodes (which must then all match). If barcodes have 
    # a different order than the corresponding files in the profile col_headers
    # field, then titles and values are reordered. That is one can reorder and
    # select among columns by giving a barcode file. Returns nothing but 
    # updates the given profile tree.

    my ( $tree,       # Profile
         $conf,       # Arguments hash
        ) = @_;

    # Returns nothing.

    my ( $bars, @tree_hdrs, @tree_ndcs, $i, $j, $tag, @hits, @msgs, $regex, 
         $str, @new_ndcs, @bar_hdrs, @bar_ndcs, $subref, @col_ndcs );

    if ( $conf->barfile )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> IDS FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $bars = &Seq::IO::read_table_tags( $conf->barfile );
        
        if ( $bars->[0]->{"ID"} ) {
            @bar_hdrs = map { $_->{"ID"} } @{ $bars };
        } elsif ( $bars->[0]->{"F-tag"} ) {
            @bar_hdrs = map { $_->{"F-tag"} } @{ $bars };
        } elsif ( $bars->[0]->{"R-tag"} ) {
            @bar_hdrs = map { $_->{"R-tag"} } @{ $bars };
        } else {
            &error( qq (No F-tag's or R-tag's) );
        }

        $i = 0;
        @tree_hdrs = map { [ $_, $i++ ] } @{ $tree->{"col_headers"} };

        @bar_ndcs = ();
        @col_ndcs = ();

        for ( $i = 0; $i <= $#bar_hdrs; $i += 1 )
        {
            $str = $bar_hdrs[$i];

            if ( @hits = grep { $_->[0] eq $str 
                                    or $_->[0] =~ /^$str\W/ 
                                    or $_->[0] =~ /\W$str$/ 
                                    or $_->[0] =~ /\W$str\W/ } @tree_hdrs )
            {
                if ( ( $j = scalar @hits ) == 1 )
                {
                    push @bar_ndcs, $i;
                    push @col_ndcs, $hits[0]->[1];
                }
                else {
                    push @msgs, ["ERROR", qq ("$str" is not unique: $j file names match "$str") ];
                }
            }
        }

        &append_or_exit( \@msgs );

        if ( not @col_ndcs )
        {
            &dump( \@tree_hdrs );
            &dump( \@bar_hdrs );
            &dump( \@bar_ndcs );
            &dump( \@col_ndcs );

            &error( qq (Column headers match with barcodes failed - programming problem) );
        }

        # Set new headers and read counts,

        if ( $bars->[0]->{"ID"} ) {
            @bar_hdrs = map { $_->{"ID"} } @{ $bars };
        }

        @{ $tree->{"col_headers"} } = @bar_hdrs[ @bar_ndcs ];
        @{ $tree->{"col_reads"} } = @{ $tree->{"col_reads"} }[ @col_ndcs ];

        # Re-arrange column values if needed, 

        @tree_ndcs = map { $_->[1] } @tree_hdrs;

        if ( not @tree_ndcs ~~ @col_ndcs )
        {
            $subref = sub 
            {
                my ( $tree, $nid, $ndcs ) = @_;

                my ( @scos );

                @scos = unpack "f*", $tree->{ $nid }->[SIM_SCORES];
                @scos = @scos[ @{ $ndcs } ];
                
                $tree->{ $nid }->[SIM_SCORES] = pack "f*", @scos;

                return;
            };

            &Taxonomy::Tree::traverse_tail( $tree, $Root_id, $subref, [ \@col_ndcs ] );

            $subref->( $tree, $Mis_nid, \@col_ndcs );
            $subref->( $tree, $Len_nid, \@col_ndcs );
            $subref->( $tree, $Sim_nid, \@col_ndcs );
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> NO BAR FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Expression given, use file names and whatever order they list in,

    elsif ( $regex = $conf->colexp ) 
    {
        @tree_hdrs = map { $_ =~ /$regex/; $1 } @{ $tree->{"col_headers"} };

        if ( @tree_hdrs and grep { not defined $_ } @tree_hdrs )
        {
            push @msgs, ["ERROR", qq (Expression did not match all file names -> "$regex") ];
            push @msgs, ["INFO", qq (Try put the expression in single quotes, or) ];
            push @msgs, ["INFO", qq (escape special characters with an extra backslash.) ];

            &echo("\n");
        }
        elsif ( not @tree_hdrs )
        {
            &error( qq (No col_headers in the profile, this is a program error) );
        }

        &append_or_exit( \@msgs );

        $tree->{"col_headers"} = \@tree_hdrs;
    }

    return;
}

sub org_profile_mapper
{
    # Niels Larsen, January 2013.
    
    # Creates a taxonomy profile from a set of sequence files and a reference
    # dataset. Input formats are whatever Seq::IO accepts (fasta and fastq at 
    # least). If sequences have seq_count=nn in the info/header line, then these
    # counts are used. There is one column per file and the values are either 
    # these counts, or a percentage. The rightmost column has taxonomy strings.

    my ( $args,
        ) = @_;

    # Returns nothing. 

    my ( $defs, $conf, $recipe, $q_seqs, $i, $q_sims, $tax_table, $tax_tree,
         $tax_file, $j, $ofh, $seq_hit, $seq_pct, $tax_dir, $q_miss, $run_start,
         $routine, $count, $stats, $q_tots, $qm_tots, $ofile, $counts, @indirs );

    local $Common::Messages::silent;

    if ( $args->list ) {
        &Taxonomy::Profile::list_datasets();
    } else {
        delete $args->{"list"};
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "list" => 0,
        "recipe" => undef,
        "seqs" => undef,
        "format" => undef,
        "sims" => undef,
        "dbname" => undef,
        "titles" => undef,
        "minsim" => 40,
        "minoli" => 1,
        "topsim" => 1,
        "simwgt" => 1.5,
        "method" => "share_clip",
        "maxamb" => 1,
        "mingrp" => 90,
        "outdir" => ".",
        "outpre" => "output",
        "profile" => undef,
        "stats" => undef,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Taxonomy::Profile::org_profile_mapper_args( $args );

    $Common::Messages::silent = $args->silent;
    
    $run_start = time();

    if ( $conf->format eq "table" )
    {
        # >>>>>>>>>>>>>>>>>>>> WITH FREQUENCY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo_bold("\nOrganism profiling:\n");
        &echo("   Taxonomy mapping table ... ");

        # These are for large dereplicated and clustered datasets,
    
        ( $tax_tree, $counts ) = &Taxonomy::Profile::map_table_taxons(
            bless {
                "con_table" => $conf->seqs,
                "sim_table" => $conf->sims,
                "tax_dbm" => $conf->taxdbm,
                "tax_sub" => $conf->taxsub,
                "col_hdrs" => $conf->titles,
                "min_oli" => $conf->minoli,
                "min_sim" => $conf->minsim,
                "top_sim" => $conf->topsim,
                "sim_wgt" => $conf->simwgt,
                "min_grp" => $conf->mingrp,
                "max_amb" => $conf->maxamb,
                "buf_size" => 1000,
            });
    }        
    else
    {
        # >>>>>>>>>>>>>>>>>>> UNCLUSTERED SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo_bold("\nOrganism profiling:\n");
        &echo("   Taxonomy mapping files ... ");

        ( $tax_tree, $counts ) = &Taxonomy::Profile::map_seqs_taxons(
            bless {
                "seq_file" => $conf->seqs,
                "sim_table" => $conf->sims,
                "tax_dbm" => $conf->taxdbm,
                "tax_sub" => $conf->taxsub,
                "col_hdrs" => $conf->titles,
                "min_oli" => $conf->minoli,
                "min_sim" => $conf->minsim,
                "top_sim" => $conf->topsim,
                "sim_wgt" => $conf->simwgt,
                "min_grp" => $conf->mingrp,
                "max_amb" => $conf->maxamb,
                "buf_size" => 1000,
            });
    }

    $count = &Taxonomy::Tree::count_nodes( $tax_tree );

    $conf->sims( $conf->sims );
    $conf->seqs( $conf->seqs );
    $conf->titles( $conf->titles );

    $stats = &Taxonomy::Profile::init_stats_profile( $conf );

    $stats->{"counts"} = $counts;

    &echo_done("$count taxa\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE PROFILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Saving taxonomy profile ... ");

    # Create a table structure from the tree with all scoring nodes included,
    # and make a file copy,

    $tax_file = $conf->profile;

    &Common::File::delete_file_if_exists( $tax_file );
    &Common::File::store_file( $tax_file, $tax_tree );
    
    $count = &Taxonomy::Tree::count_nodes( $tax_tree );

    if ( $count > 0 )
    {
        $stats->{"out-taxa"} = $count;
        &echo_done("$count taxa\n");
    } 
    else
    {
        $stats->{"out-taxa"} = 0;
        &echo_red("NO TAXA\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats->{"seconds"} = time() - $run_start;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    &Common::File::delete_file_if_exists( $conf->stats ) if $args->clobber;

    &echo("   Saving statistics ... ");
    &Taxonomy::Profile::write_stats_profile( $conf->stats, bless $stats );
    &echo_done("done\n");

    # Print run time,

    &echo("   Run time: ");
    &echo_info( &Time::Duration::duration( $stats->{"seconds"} ) ."\n" );

    &echo_bold("Finished\n\n");

    return wantarray ? @{ $counts } : $counts;
}

sub org_profile_mapper_args
{
    # Niels Larsen, April 2012.

    # Takes command line arguments, checks values, adds fields and returns a
    # configuration object for the org_profile_mapper routine.

    my ( $args,
        ) = @_;

    # Returns object.

    my ( @msgs, $name, $hdr, $db_dir, $db_file, $bars, $key, $conf, $file,
         @titles, $i, $j, $files, $outdir, $outpre, @formats, @indirs, 
         @subdirs, @inseqs, $method );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf = {
        "sims" => undef,
        "titles" => undef,
        "seqs" => undef,
        "taxdbm" => undef,
        "taxsub" => $args->method,
        "minsim" => $args->minsim,
        "topsim" => $args->topsim,
        "simwgt" => $args->simwgt,
        "maxamb" => $args->maxamb,
        "mingrp" => $args->mingrp,
        "minoli" => $args->minoli,
        "clobber" => $args->clobber,
        "outdir" => $args->outdir,
        "outpre" => $args->outpre,
        "stats" => undef,
    };

    @inseqs = &Recipe::IO::list_files( $args->seqs );
    @indirs = &Common::Names::create_path_tuples( \@inseqs );
    @subdirs = map { &File::Basename::basename( $_->[0] ) } @indirs;
    
    if ( scalar @indirs > 1 )
    {
        $conf->{"formats"} = [];
        $conf->{"substats"} = [];
        $conf->{"subdirs"} = [];
        $conf->{"profiles"} = [];
    }
    else 
    {
        $conf->{"format"} = [];
        $conf->{"profile"} = [];
    }

    bless $conf;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $files = $args->sims )
    {
        if ( @indirs > 1 ) {
            $conf->sims([ &Recipe::IO::list_files( $args->sims ) ]);
        } else {
            $conf->sims( $args->sims );
        }
            
	&Common::File::check_files( $conf->sims, "esfr", \@msgs );
    } 
    else {
        push @msgs, ["ERROR", qq (No input similarity table given) ];
    }

    &append_or_exit( \@msgs );

    if ( $args->seqs )
    {
        if ( @indirs > 1 ) {
            $conf->seqs([ &Recipe::IO::list_files( $args->seqs ) ]);
        } else {
            $conf->seqs( $args->seqs );
        }
            
	&Common::File::check_files( $conf->seqs, "esfr", \@msgs );
    }
    else {
        push @msgs, ["ERROR", qq (No input sequence file or table given) ];
    }

    &append_or_exit( \@msgs );

    if ( @indirs > 1 )
    {
        if ( ( $i = scalar @{ $conf->sims } ) != ( $j = scalar @{ $conf->seqs } ) ) {
            push @msgs, ["ERROR", qq ($i similarity tables but $j sequence files) ];
        }

        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @indirs > 1 ) {
        $conf->subdirs([ map { &File::Basename::basename( $_->[0] ) } @indirs ]);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT TITLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @indirs > 1 )
    {
        foreach $file ( @{ $conf->sims } ) {
            push @titles, [ &Common::File::read_ids( "$file.titles" ) ];
        }

        $conf->titles( \@titles );
    }
    elsif ( $args->titles )
    {
        $bars = &Seq::IO::read_table_tags( $args->titles, \@msgs );
        $key = undef;

        foreach $hdr ( @Seq::IO::Bar_titles )
        {
            if ( $bars->[0]->{ $hdr } ) {
                $key = $hdr;
                last;
            }
        }
        
        if ( $key ) {
            $conf->titles([ map { $_->{ $key } } @{ $bars } ]);
        } else {
            push @msgs, ["ERROR", qq (No title key matched) ];
        }

        &append_or_exit( \@msgs );
    }
    else {
        $conf->titles([ &Common::File::read_ids( $conf->sims .".titles" ) ]);
    }

    if ( @indirs > 1 ) 
    {
        if ( ( $i = scalar @{ $conf->sims } ) != ( $j = scalar @{ $conf->titles } ) ) {
            push @msgs, ["ERROR", qq ($i similarity tables but $j title files) ];
        }        
        
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @indirs > 1 )
    {
        @formats = ();
        
        foreach $file ( @{ $conf->seqs } )
        {
            push @formats, &Seq::IO::detect_format( $file );
        }
        
        $conf->formats( \@formats );
    }
    else {
        $conf->format( &Seq::IO::detect_format( $conf->seqs ) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> REFERENCE DATASET <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First make sure a valid name or file is given,

    if ( $args->dbname )
    {
        if ( $db_file = $Taxonomy::Config::DB_files{ $name = $args->dbname } )
        {
            $db_dir = &File::Basename::dirname( $db_file );
            $conf->taxdbm( &Common::File::list_files( $db_dir, '\.dbm$' )->[0]->{"path"} );
        }
        else
        {
            push @msgs, ["ERROR", qq (Wrong looking dataset name -> "$name") ];
            push @msgs, ["INFO", qq (Choices are one of:\n) ];
            
            map { push @msgs, ["INFO", $_ ] } @Taxonomy::Config::DB_names;
        }
    }
    else
    {
        push @msgs, ["ERROR", qq (A dataset name must be given.) ];
        push @msgs, ["INFO", qq (Choices are one of:\n) ];

        map { push @msgs, ["INFO", $_ ] } @Taxonomy::Config::DB_names;
    }
        
    &append_or_exit( \@msgs );

    # Then check that the file exists,

    &Common::File::check_files( [ $conf->taxdbm ], "efr", \@msgs );

    if ( @msgs ) {
        push @msgs, ["INFO", qq (Perhaps the dataset is not installed?) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Registry::Args::check_number( $conf->minsim, 0, 100, \@msgs );
    &Registry::Args::check_number( $conf->topsim, 0, 100, \@msgs );
    &Registry::Args::check_number( $conf->simwgt, 0.0, 10.0, \@msgs );

    &Registry::Args::check_number( $conf->maxamb, 0, undef, \@msgs );
    &Registry::Args::check_number( $conf->mingrp, 51, 100, \@msgs );
    $conf->mingrp( $conf->mingrp / 100 );

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHOD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $method = $args->method;

    if ( $Node_info{ $method } ) 
    {
        $conf->taxsub( $Node_subs{ $method } );
    }
    else
    {
        push @msgs, ["ERROR", qq (Wrong looking mapping method -> "$method") ];
        push @msgs, ["INFO", qq (Choices are one of:\n) ];

        map { push @msgs, ["INFO", "$_ ($Node_info{ $_ })" ] } keys %Node_info;
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check output prefix, 

    $outpre = $conf->outpre;

    if ( not defined $outpre ) {
        push @msgs, ["ERROR", qq (Output file prefix must be given) ];
    }

    &append_or_exit( \@msgs );

    # Check directory,
    
    $outdir = $conf->outdir;

    if ( defined $outdir )
    {
        if ( not $conf->clobber and not -d $outdir ) {
            push @msgs, ["ERROR", qq (Output directory does not exist -> "$outdir") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (An output directory must be given, but can be ".") ];
    }

    &append_or_exit( \@msgs );

    # Set output similarity table name (not the full path),
    
    if ( @indirs > 1 )
    {
        for ( $i = 0; $i <= $#{ $conf->seqs }; $i += 1 )
        {
            push @{ $conf->profiles }, "$outdir/$subdirs[$i]/$outpre.profile";
            push @{ $conf->substats }, "$outdir/$subdirs[$i]/$outpre.stats";
        }
        
        if ( not $conf->clobber ) 
        {
            &Common::File::check_files([ @{ $conf->profiles }, @{ $conf->substats } ], "!e", \@msgs );
            &append_or_exit( \@msgs );
        }
    }
    else
    {
        $conf->profile( "$outdir/$outpre.profile" );

        if ( not $conf->clobber ) 
        {
            &Common::File::check_files( $conf->profile, "!e", \@msgs );
            &append_or_exit( \@msgs );
        }
    }
    
    if ( $args->stats ) {
        $conf->stats( $args->stats );
    } else {
        $conf->stats( "$outdir/$outpre.stats" );
    }
        
    if ( not $conf->clobber ) 
    {
        &Common::File::check_files( $conf->stats, "!e", \@msgs );
        &append_or_exit( \@msgs );
    }

    &append_or_exit( \@msgs );

    return wantarray ? %{ $conf } : $conf;
}

sub org_profile_merge
{
    # Niels Larsen, June 2012.
    
    # Merges a list of organism taxonomy profiles into one. The input files 
    # can have rows with different taxonomy strings, but the taxonomies must
    # be of the same kind, i.e. either Greengenes, RDP or what else is 
    # supported. 

    my ( $args,
        ) = @_;

    # Returns nothing. 

    my ( $defs, $conf, @ifiles, $count, $recipe, $name, $file, $t_dst, $t_src,
         $copy_node, $link_node, $copy_scores, $add_nulls, $nulls1, $nulls2 );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "ifiles" => [],
        "ofile" => undef,
        "title" => "Merged profile",
        "lhead" => "Taxonomy profile",
        "rhead" => "BION Meta",
        "tables" => 1,
        "colsum" => undef,
        "minval" => 1,
        "rowmax" => 1,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Taxonomy::Profile::org_profile_merge_args( $args );

    @ifiles = @{ $conf->ifiles };

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES USED BELOW <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # These un-fancy routines are run depth-first in the next section.

    $copy_node = sub
    {
        # Copies missing nodes in the destination tree from the source tree.
        # Sets scores to a given null-padding.

        my ( $t_src,      # Source tree
             $n_id,       # Source tree node id
             $t_dst,      # Destination tree
             $nulls,      # String of f-packed zeroes
            ) = @_;

        my ( $parent_id );

        if ( not exists $t_dst->{ $n_id } )
        {
            # If the node does not exist in the target tree, then make a new
            # target node by copying all fields from the source tree,
            
            $t_dst->{ $n_id }->[OTU_NAME] = $t_src->{ $n_id }->[OTU_NAME];
            $t_dst->{ $n_id }->[PARENT_ID] = $t_src->{ $n_id }->[PARENT_ID];
            $t_dst->{ $n_id }->[NODE_ID] = $t_src->{ $n_id }->[NODE_ID];
            $t_dst->{ $n_id }->[SIM_SCORES] = $nulls;
            $t_dst->{ $n_id }->[CHILD_IDS] = [];
        };

        return;
    };

    $link_node = sub
    {
        # Links added source nodes by adding their id to their parents child 
        # ids in the destination tree. 

        my ( $t_src,     # Source tree
             $n_id,      # Source tree node id
             $t_dst,     # Destination tree
            ) = @_;

        my ( $parent_id );

        if ( defined ( $parent_id = $t_src->{ $n_id }->[PARENT_ID] ) )
        {
            if ( not grep { $_ eq $n_id } @{ $t_dst->{ $parent_id }->[CHILD_IDS] } )
            {
                push @{ $t_dst->{ $parent_id }->[CHILD_IDS] }, $n_id;
            }
        }
        
        return;
    };

    $copy_scores = sub
    {
        # Copies source node scores to the destination by appending score 
        # strings. 

        my ( $t_src,     # Source tree
             $n_id,      # Source tree node id
             $t_dst,     # Destination tree
            ) = @_;

        $t_dst->{ $n_id }->[SIM_SCORES] .= $t_src->{ $n_id }->[SIM_SCORES];

        return;
    };
    
    $add_nulls = sub
    {
        # Adds zero-scores to the destination nodes that are missing from in 
        # the source tree. 

        my ( $t_dst,     # Destination tree
             $n_id,      # Destination tree node id
             $t_src,     # Source tree
             $nulls,     # f-packed string of zeroes
            ) = @_;

        if ( not exists $t_src->{ $n_id } )
        {
            $t_dst->{ $n_id }->[SIM_SCORES] .= $nulls;
        }

        return;
    };
    
    &echo_bold("\nProfile merge:\n");

    # >>>>>>>>>>>>>>>>>>>>>> LOAD DESTINATION PROFILE <<<<<<<<<<<<<<<<<<<<<<<<<

    # The first profile is used as destination profile, as starting point, and
    # the rest are being added to it in the next section,

    $file = shift @ifiles;

    $name = &File::Basename::basename( $file );
    &echo("   Reading $name ... ");

    $t_dst = bless &Common::File::retrieve_file( $file );
    # $t_dst->col_headers([ &Taxonomy::Profile::titles_from_paths( $t_dst->col_headers ) ]);
    $t_dst->col_headers([ map { &Common::Names::strip_suffix( $_ ) } @{ $t_dst->col_headers } ]);

    $nulls1 = pack "f*", (0) x scalar @{ $t_dst->col_headers };

    $count = &Taxonomy::Tree::count_nodes( $t_dst );
    &echo_done("$count nodes\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> MERGE THE REST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $file ( @ifiles )
    {
        $name = &File::Basename::basename( $file );
        &echo("   Adding $name ... ");

        $t_src = bless &Common::File::retrieve_file( $file );

        # Copy missing destination nodes, add missing parents and copy scores
        # from source to destination,

        &Taxonomy::Tree::traverse_tail( $t_src, $Root_id, $copy_node, [ $t_dst, $nulls1 ] );
        &Taxonomy::Tree::traverse_tail( $t_src, $Root_id, $link_node, [ $t_dst ] );
        &Taxonomy::Tree::traverse_tail( $t_src, $Root_id, $copy_scores, [ $t_dst ] );

        # Use zero-padding for nodes in the destination tree that are not in 
        # the source tree,

        $nulls2 = pack "f*", (0) x scalar @{ $t_src->col_headers };
        &Taxonomy::Tree::traverse_tail( $t_dst, $Root_id, $add_nulls, [ $t_src, $nulls2 ] );

        # Append headers, read counts and mismatch counts,

        # push @{ $t_dst->col_headers }, @{ &Taxonomy::Profile::titles_from_paths( $t_src->col_headers ) };
        push @{ $t_dst->col_headers }, map { &Common::Names::strip_suffix( $_ ) } @{ $t_src->col_headers };
        push @{ $t_dst->col_reads }, @{ $t_src->col_reads };

        $t_dst->{ $Mis_nid }->[SIM_SCORES] .= $t_src->{ $Mis_nid }->[SIM_SCORES];

        # Make padding longer and longer for each source tree, 

        $nulls1 .= pack "f*", (0) x scalar @{ $t_src->col_headers };

        $count = &Taxonomy::Tree::count_nodes( $t_src );
        &echo_done("$count nodes\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> COUNT RESULT TREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Nodes in merged profile ... ");
    $count = &Taxonomy::Tree::count_nodes( $t_dst );
    &echo_done("$count nodes\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUT TREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $file = $conf->ofile;

    $name = &File::Basename::basename( $file );
    &echo("   Writing binary profile $name ... ");

    &Common::File::delete_file_if_exists( $file ) if $conf->clobber;
    &Common::File::store_file( $file, $t_dst );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUT TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $conf->tables )
    {
        &echo("   Writing taxonomy tables ... ");

        $count = &Taxonomy::Profile::org_profile_format(
             bless {
                 "recipe" => undef,
                 "ifile" => $file,
                 "oname" => $file,
                 "minval" => $conf->minval,
                 "rowmax" => $conf->rowmax,
                 "colsum" => $conf->colsum,
                 "title" => $conf->title,
                 "lhead" => $conf->lhead,
                 "rhead" => $conf->rhead,
                 "stats" => 0,
                 "clobber" => 1,
                 "silent" => 1,
             });

        &echo_done("$count\n");
    }

    &echo_bold("Finished\n\n");

    return;
}

sub org_profile_merge_args
{
    # Niels Larsen, December 2012.

    # Validates arguments and returns a configuration hash. 

    my ( $args,
        ) = @_;

    # Returns a hash.

    my ( @msgs, %args, $file, $name, $str );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->ifiles ) {
	$args{"ifiles"} = &Common::File::check_files( $args->ifiles, "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No input organism profiles given) ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->ofile )
    {
        &Common::File::check_files( [ $args->ofile ], "!e", \@msgs ) if not $args->clobber;
        $args{"ofile"} = $args->ofile;
    }
    else {
        push @msgs, ["ERROR", qq (No output profile file given) ];
    }

    $args{"tables"} = $args->tables;
    $args{"colsum"} = $args->colsum;
    $args{"minval"} = $args->minval;
    $args{"rowmax"} = $args->rowmax;

    $args{"clobber"} = $args->clobber;
    $args{"silent"} = $args->silent;

    $args{"title"} = $args->title;
    $args{"lhead"} = $args->lhead;
    $args{"rhead"} = $args->rhead;
    
    &append_or_exit( \@msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}

sub org_profile_sims
{
    # Niels Larsen, January 2013.
    
    # Creates a similarity table from query sequences a reference dataset. A
    # list of sequences may given as input. If they are from multiple 
    # directories, then the output will be written to directories with the 
    # same names. A table with sequences and sample frequencies may also be
    # input, but only one. Returns nothing.

    my ( $args,
        ) = @_;

    # Returns nothing. 

    my ( $defs, $conf, $recipe, $q_seqs, $i, $q_sims, $j, $ofh, $q_miss, 
         $run_start, $routine, $count, $stats, $q_tots, $qm_tots, $ofile, 
         $q_tot, $q_sums, $q_table, $tot_ndx, $seq_ndx, @q_seqs, $q_hdrs,
         @indirs, @outdirs, @outfiles, $outfile, $indir, $files, $outdir,
         $tuple, $dir, $name, $file );

    local $Common::Messages::silent;

    if ( $args->list ) {
        &Taxonomy::Profile::list_datasets();
    } else {
        delete $args->{"list"};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "ifiles" => [],
        "recipe" => undef,
        "dbname" => undef,
        "dbfile" => undef,
        "dbread" => 10_000,
        "self" => 1,
        "minsim" => 50,
        "topsim" => 1,
        "forward" => 1,
        "reverse" => 0,
        "minqual" => undef,
        "qualtype" => undef,
        "wordlen" => 8,
        "steplen" => 2,
        "wconly" => 1,
        "outdir" => undef,
        "outpre" => "output",
        "stats" => undef,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Taxonomy::Profile::org_profile_sims_args( $args );

    $Common::Messages::silent = $args->silent;

    $stats = &Taxonomy::Profile::init_stats_sims( $conf );

    $run_start = time();
    
    &Common::File::create_dir_if_not_exists( $conf->outdir );

    if ( $conf->iformat eq "table" )
    {
        &echo_bold("\nSequence similarity (table):\n");

        # >>>>>>>>>>>>>>>>> FREQUENCY TABLE WITH SEQUENCES <<<<<<<<<<<<<<<<<<<<

        # TODO: This is most unelegant. Find a way to put all information into
        # a single file. Maybe define a table format.

        # Tables have occurrence counts for each sample after clustering; this 
        # is a way to cope with millions of short and highly redundant Illumina 
        # reads. Here we isolate its sequences for the similarity matching and 
        # then in the taxonomy mapper we use the counts,
        
        &echo("   Reading input table ... ");

        $q_table = &Common::Table::read_table( $conf->ifiles->[0] );
        $q_hdrs = &Storable::dclone( $q_table->col_headers );

        &echo_done("done\n");
        
        &echo("   Saving table consenses ... ");
        
        ( $tot_ndx, $seq_ndx ) = &Common::Table::names_to_indices( ["Total", "Sequence"], $q_table->col_headers );
        
        $i = 0;
        
        @q_seqs = map {{
            "id" => ++$i,
            "seq" => $_->[$seq_ndx],
            "info" => "seq_count=$_->[$tot_ndx]",
            }}
        @{ $q_table->values };
    
        $q_seqs = $conf->ifiles->[0] .".seqs";
        &Common::File::delete_file_if_exists( $q_seqs );

        &Common::File::delete_file_if_exists( $conf->osims .".seqs" );
        &Common::File::create_link( $conf->ifiles->[0], $conf->osims .".seqs" );

        $conf->qualtype( undef );
        $conf->minqual( undef );

        &Common::File::delete_file_if_exists( $q_seqs );
        &Seq::IO::write_seqs_file( $q_seqs, \@q_seqs, "fasta" );

        $q_tot = scalar @q_seqs;
        
        &echo_done( $q_tot ."\n" );
    }
    else
    {
        &echo_bold("\nSequence similarity (files):\n");

        # >>>>>>>>>>>>>>>>>>>>>>>> MERGE SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Here the sequences are not highly redundant and have not been 
        # clustered. But we merge the given separate sequence files and use the
        # file names as headers. This is needed as simrank requires a single 
        # file to run efficiently in parallel. 
        
        &echo("   Pooling all sequences ... ");
        
        $q_seqs = $conf->osims . ".seqs";
        &Common::File::delete_file_if_exists( $q_seqs );

        # Create headers that include

        foreach $file ( @{ $conf->ifiles } )
        {
            $dir = &File::Basename::dirname( $file );
            $name = &File::Basename::basename( $file );

            # push @{ $q_hdrs }, &File::Basename::basename( $dir ) ."/$name";
            push @{ $q_hdrs }, $name;
        }

        $q_sums = &Seq::IO::merge_seq_files(
            {
                "iformat" => $conf->iformat,
                "ifiles" => $conf->ifiles,
                "ititles" => $q_hdrs,
                "ofile" => $q_seqs,
            });

        $q_tot = &List::Util::sum( map { $_->[1] } @{ $q_sums } );
        
        &echo_done("$q_tot\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN SIMRANK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Simrank creates a file table with these values separated by tab:
    # 
    # query id
    # number of oligos
    # hits 
    # 
    # where hits is a blank separated string of database_id:match_percent.
    # This table is then read and interpreted below. 

    &echo("   Matching all sequences ... ");

    &Seq::Simrank::match_seqs(
        $q_seqs,
        {
            "dbfile" => $conf->dbfile,
            "dbread" => $conf->dbread,
            "wordlen" => $conf->wordlen,
            "steplen" => $conf->steplen,
            "minsim" => $conf->minsim,
            "topsim" => $conf->topsim,
            "forward" => $conf->forward,
            "reverse" => $conf->reverse,
            "qualtype" => $conf->qualtype,
            "minqual" => $conf->minqual,
            "wconly" => $conf->wconly,
            "otable" => $conf->osims,
            "clobber" => $args->clobber,
            "simfmt" => "%.10f",
            "numids" => 0,
            "silent" => 1,
        });
    
    $q_sims = $conf->osims;

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>> COUNT OUTPUT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Similarity table counts ... ");

    if ( $conf->iformat eq "table" ) {
        $stats->{"files"} = &Taxonomy::Profile::count_sims_table( $q_sims, 0 );
    } else {
        $stats->{"files"} = &Taxonomy::Profile::count_sims_table( $q_sims, 1 );
    }

    # There must be the same number of lines in the similarity table ($q_sims)
    # as there are query sequences, so check for that,
    
    $j = &List::Util::sum( map { $_->[1] } @{ $stats->{"files"} } );

    if ( $q_tot != $j )
    {
        &error( qq ($q_tot input sequences but similarity table has $j rows ..\n)
              . qq (This is a programming or file system error.) );
    }

    &echo_green("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE TITLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Saving column titles ... ");

    &Common::File::delete_file_if_exists( $q_sims .".titles" );
    &Common::File::write_file( $q_sims .".titles", [ map {"$_\n"} @{ $q_hdrs } ] );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>> WRITE THE UNMATCHED <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( -s $q_sims )
    {
        &echo("   Separating the unmatched ... ");
        
        $q_miss = &Taxonomy::Profile::read_nosim_seqs( $q_seqs, $q_sims );
        
        if ( $q_miss ) {
            $count = scalar @{ $q_miss };
        } else {
            $count = 0;
        }

        &echo_done("$count seq[s]\n");
    }

    if ( $q_miss )
    {
        &echo("   Saving the unmatched ... ");
        
        &Common::File::delete_file_if_exists( $conf->omiss ) if $args->clobber;
        &Seq::IO::write_seqs_file( $conf->omiss, $q_miss, $conf->iformat );
        
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>> DELETE SCRATCH FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $conf->iformat eq "table" ) 
    {
        &echo("   Deleting scratch files ... ");    
        &Common::File::delete_file( $q_seqs );
        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats->{"seconds"} = time() - $run_start;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    &Common::File::delete_file_if_exists( $conf->stats ) if $args->clobber;

    &echo("   Saving statistics ... ");
    &Taxonomy::Profile::write_stats_sims( $conf->stats, bless $stats );
    &echo_done("done\n");

    # Print run time,

    &echo("   Run time: ");
    &echo_info( &Time::Duration::duration( $stats->{"seconds"} ) ."\n" );

    &echo_bold("Finished\n\n");

    return;
}

sub org_profile_sims_args
{
    # Niels Larsen, April 2012.

    # Takes command line arguments, checks values, adds fields and returns a
    # configuration object for the org_profile_sims routine.

    my ( $args,
        ) = @_;

    # Returns object.

    my ( $conf, @msgs, %args, $file, $name, $str, %formats, @list, $i, $j, 
         @files, $ref_mol, $outdir );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf = bless {
        "ifiles" => $args->ifiles,
        "iformat" => undef,
        "dbname" => $args->dbname,
        "dbfile" => $args->dbfile,
        "dbread" => $args->dbread,
        "self" => $args->self,
        "minsim" => $args->minsim,
        "topsim" => $args->topsim,
        "minqual" => $args->minqual,
        "qualtype" => $args->qualtype,
        "wordlen" => $args->wordlen,
        "steplen" => $args->steplen,
        "wconly" => $args->wconly,
        "forward" => $args->forward,
        "reverse" => $args->reverse,
        "clobber" => $args->clobber,
        "outdir" => $args->outdir,
        "outpre" => $args->outpre,
        "osims" => undef,
        "omiss" => undef,
        "stats" => $args->stats,
        "silent" => $args->silent,
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check files exist and are non-empty,

    if ( @files = @{ $conf->ifiles } )
    {
	&Common::File::check_files( \@files, "efr", \@msgs );

        if ( not @msgs )
        {
            @files = grep { -s $_ } @files;
        
            if ( @files ) {
                $conf->ifiles( \@files );
            } else {
                push @msgs, ["ERROR", qq (All the given files are empty) ];
            }
        }
    }
    else {
        push @msgs, ["ERROR", qq (No input sequence file(s) given) ];
    }

    &append_or_exit( \@msgs );

    # Check all files have the same format, 

    @list = ();

    map { push @list, &Seq::IO::detect_format( $_ ) } @{ $conf->ifiles };
    @list = &Common::Util::uniqify( \@list );

    if ( scalar @list == 1 )
    {
        $conf->iformat( $list[0] );

        if ( $conf->iformat eq "table" and scalar @{ $conf->ifiles } > 1 ) {
            push @msgs, ["ERROR", qq (Only one input table may be given -> $str) ];
        }
    }
    else
    {
        $str = join ", ", @list;
        push @msgs, ["ERROR", qq (Multiple input formats detected -> $str) ];
        push @msgs, ["INFO", qq (All files must have same format, fasta and fastq are ok) ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> REFERENCE DATASET <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First make sure a valid name or file is given,

    if ( $name = $conf->dbname )
    {
        if ( $file = $Taxonomy::Config::DB_files{ $name } )
        {
            $conf->dbfile( $file );
        }
        else 
        {
            push @msgs, ["ERROR", qq (Wrong looking dataset name -> "$name") ];
            push @msgs, ["INFO", qq (Choices are one of:) ];
            
            map { push @msgs, ["INFO", $_ ] } @Taxonomy::Config::DB_names;
        }
    }
    elsif ( not $conf->dbfile )
    {
        push @msgs, ["ERROR", qq (No reference dataset name or file given) ];
    }

    &append_or_exit( \@msgs );

    # Then check that the file exists,

    &Common::File::check_files( [ $conf->dbfile ], "efr", \@msgs );

    if ( @msgs ) {
        push @msgs, ["INFO", qq (Perhaps the dataset is not installed?) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &Registry::Args::check_number( $conf->dbread, 1, undef, \@msgs );

    &Registry::Args::check_number( $conf->minsim, 0, 100, \@msgs );
    &Registry::Args::check_number( $conf->topsim, 0, 100, \@msgs );

    if ( $conf->minqual ) {
        &Registry::Args::check_number( $conf->minqual, 0, 100, \@msgs );
    }

    if ( $conf->qualtype )
    {
        &Seq::Common::qual_config( $conf->qualtype, \@msgs );
        &append_or_exit( \@msgs );
    }
    elsif ( $conf->minqual ) {
        push @msgs, ["ERROR", qq (A quality type must be given with minimum quality) ];
    }
    
    if ( $conf->wordlen ) {
        &Registry::Args::check_number( $conf->wordlen, 1, 12, \@msgs );
    } else {
        push @msgs, [ "ERROR", qq (Word length must be given - 7 or 8 is often best) ];
    }
    
    if ( not $conf->forward and not $conf->reverse ) {
        push @msgs, [ "ERROR", qq (At least one of --forward or --reverse must be used) ];
    }

    &append_or_exit( \@msgs );

    if ( $conf->steplen ) {
        &Registry::Args::check_number( $conf->steplen, 1, $conf->wordlen, \@msgs );
    } else {
        push @msgs, [ "ERROR", qq (Step length must be given - 2 is often best) ];
    }

    &append_or_exit( \@msgs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check output prefix, 

    if ( not defined $conf->outpre ) {
        push @msgs, ["ERROR", qq (Output file prefix must be given) ];
    }

    &append_or_exit( \@msgs );

    # Check directory,
    
    $outdir = $conf->outdir;

    if ( defined $outdir )
    {
        if ( not $conf->clobber and not -d $outdir ) {
            push @msgs, ["ERROR", qq (Output directory does not exist -> "$outdir") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (An output directory must be given, but can be ".") ];
    }

    &append_or_exit( \@msgs );

    # Set output similarity table name (not the full path),

    $conf->osims( "$outdir/". $conf->outpre .".sims" );
    $conf->omiss( "$outdir/". $conf->outpre .".miss" );

    if ( not defined $conf->stats ) {
        $conf->stats( "$outdir/". $conf->outpre .".stats" );
    }

    if ( not $conf->clobber ) 
    {
        # Check output files,
    
        &Common::File::check_files([ $conf->osims, $conf->omiss, $conf->stats ], "!e", \@msgs );
        &append_or_exit( \@msgs );
    }

    return wantarray ? %{ $conf } : $conf;
}

sub pcts_to_weights
{
    # Niels Larsen, April 2012. 

    # Given a list of percentage values, creates a list of corresponding
    # weights. The weights are 1 plus the inverse of the differences between
    # the highest percentage and a given one. The numbers are then scaled 
    # down so their sum is 1. Example percentages and weights,
    #
    # 100, 100, 98, 97, 96.3, 92 -> 0.344, 0.344, 0.115, 0.086, 0.073, 0.038
    
    my ( $pcts,    # List of percentages
         $mult,    # Number to multiply each weight with
         $wgtx,    # Down-weighting exponentiation factor
        ) = @_;

    # Returns a list.

    my ( @pcts, @wgts, $max, $pct, $sum );

    $max = &List::Util::max( @{ $pcts } );

    foreach $pct ( @{ $pcts } )
    {
        push @wgts, 1 / ( 1 + $max - $pct ) ** $wgtx;
    }

    $sum = &List::Util::sum( @wgts );

    if ( $sum > 0 )
    {
        if ( $mult > 1 ) {
            @wgts = map { $mult * $_ / $sum } @wgts;
        } else {
            @wgts = map { $_ / $sum } @wgts;
        }
    }
    else {
        @wgts = map { 1 } @wgts;
    }

    return wantarray ? @wgts : \@wgts;
}

sub read_nosim_seqs
{
    my ( $seqs,
         $sims,
        ) = @_;

    my ( $reader, $seq_fh, $sim_fh, $i, $line, $id, $hits, $seq, @miss );

    $reader = &Seq::IO::get_read_routine( $seqs );

    $seq_fh = &Common::File::get_read_handle( $seqs );
    $sim_fh = &Common::File::get_read_handle( $sims );

    $i = 0;

    no strict "refs";

    while ( $seqs = $reader->( $seq_fh, 1 ) )
    {
        $seq = $seqs->[0];

        $line = <$sim_fh>;
        chomp $line;

        ( undef, undef, $hits ) = split "\t", $line;

        push @miss, $seq if not $hits;

        $i++;
    }

    &Common::File::close_handle( $sim_fh );
    &Common::File::close_handle( $seq_fh );

    if ( @miss ) {
        return wantarray ? @miss : \@miss;
    } 

    return;
}

sub read_seqs
{
    # Niels Larsen, April 2012.

    # Reads all sequences from the given files into 

    my ( $args,
        ) = @_;

    my ( @seqs, $routine, $name, $fh, $file, $files, $i );

    $routine = "Seq::IO::read_seqs_". $args->{"iformat"};
    $files = [ @{ $args->{"iseqs"} } ];

    no strict "refs";

    for ( $i = 0; $i < @{ $files }; $i++ )
    {
        if ( defined ( $file = $files->[$i] ) )
        {
            $name = $args->{"titles"}->[$i];

            $fh = &Common::File::get_read_handle( $file );

            push @seqs, map { $_->{"id"} = $name ."__SPLIT__". $_->{'id'}; $_ } @{ $routine->( $fh, $Max_int ) };

            &Common::File::close_handle( $fh );
        }
    }

    return wantarray ? @seqs : \@seqs;
}

sub read_table
{
    # Niels Larsen, May 2012. 

    # As Common::Table::read_table, but removes column totals if present, 
    # optionally removes row totals and optionally splices out taxonomy 
    # names and saves them under row_headers. Returns a table object.

    my ( $file,   # Table file 
         %args,
        ) = @_;
    
    # Return table object.

    my ( $table, $col, @hdrs, $row, $ndx, $nam_ndx );

    %args = ( "del_row_sums" => 1, "splice_names" => 1, %args );

    $table = &Common::Table::read_table( $file );

    # Remove column totals,

    $ndx = &Common::Table::name_to_index( $Tax_title, $table->col_headers );
    
    @{ $table->values } = grep { $_->[$ndx] ne $Col_title } @{ $table->values };

    # Optionally remove row totals,

    if ( $args{"del_row_sums"} )
    {
        if ( defined ( $ndx = &Common::Table::name_to_index( $Row_title, $table->col_headers ) ) )
        {
            &Common::Table::splice_col( $table, $ndx, 1 );
        }
    }
    
    # Optionally save taxonomy as row headers,

    if ( $args{"splice_names"} )
    {
        if ( defined ( $ndx = &Common::Table::name_to_index( $Tax_title, $table->col_headers ) ) )
        {
            $table->row_headers([ &Common::Table::get_col( $table, $Tax_title ) ]);
            &Common::Table::splice_col( $table, $ndx, 1 );
        }
    }

    return $table;
}

sub round_table
{
    # Niels Larsen, December 2012. 

    # Rounds table values and totals down to a given number of decimals.
    # The table can be packed or unpacked. Input table is changed, not 
    # cloned. Returns a table object.

    my ( $table,
         $places,
         $rowmax,
        ) = @_;

    # Returns object.

    my ( $format, $colnum, $row, $i, @vals );

    # Round values,

    $colnum = $table->col_count;
    @vals = ();

    if ( &Taxonomy::Profile::is_packed_table( $table ) )
    {
        foreach $row ( @{ $table->values } )
        {
            &Common::Util_C::round_array_float( $row, $places, $colnum );

            push @vals, &Common::Util_C::max_value_float( $row, $colnum );
        }
    }
    else 
    {
        $format = "%.$places". "f";

        foreach $row ( @{ $table->values } )
        {
            for ( $i = 0; $i < $colnum; $i += 1 )
            {
                $row->[$i] = sprintf $format, $row->[$i];
            }

            push @vals, &List::Util::max( @{ $row } );
        }
    }

    if ( $rowmax ) {
        $table->row_maxima( \@vals );
    } else {
        $table->row_maxima( undef );
    }

    &Taxonomy::Profile::sum_table_columns( $table );

    $table->sco_total( &List::Util::sum( $table->col_totals ) );

    return $table;
}
    
sub sum_profile_counts
{
    # Niels Larsen, April 2013.

    # Reads stats files from each of the given files and returns summed up 
    # counts. 

    my ( $files,
        ) = @_;

    my ( $counts, $row, $file, $vals, $in, $hit, $name, @list );

    foreach $file ( @{ $files } )
    {
        $in = 0;
        $hit = 0;

        foreach $row ( @{ &Recipe::IO::read_stats( $file )->[0]->{"tables"}->[0]->{"rows"} } )
        {
            $vals = [ split "\t", $row->{"value"} ];

            $in += &Common::Util::decommify_number( $vals->[1] );
            $hit += &Common::Util::decommify_number( $vals->[2] );
        }

        $name = &File::Basename::dirname( $file );
        $name = &File::Basename::basename( $name );
        $name =~ s/_/ /g;

        push @list, [ $name, $in, $hit ];
    }

    return wantarray ? @list : \@list;
}

sub sum_sims_counts
{
    # Niels Larsen, April 2013.

    # Reads stats files from each of the given files and returns summed up 
    # counts. 

    my ( $files,
        ) = @_;

    my ( $counts, $row, $file, $vals, $in, $hit, $name, @list );

    foreach $file ( @{ $files } )
    {
        $in = 0;
        $hit = 0;

        foreach $row ( @{ &Recipe::IO::read_stats( $file )->[0]->{"tables"}->[0]->{"rows"} } )
        {
            $vals = [ split "\t", $row->{"value"} ];
            
            $in += $vals->[1];
            $hit += $vals->[2];
        }

        $name = &File::Basename::dirname( $file );
        $name = &File::Basename::basename( $name );
        $name =~ s/_/ /g;

        push @list, [ $name, $in, $hit ];
    }

    return wantarray ? @list : \@list;
}

sub sum_table_columns
{
    # Niels Larsen, December 2012. 

    # Sums the column values of a table with packed or unpacked values. In 
    # non-void context, the totals are returned, in void context the table
    # itself is updated.

    my ( $table,
        ) = @_;

    my ( @counts, $counts, $colnum, $row, $i );

    $colnum = $table->col_count;

    if ( &Taxonomy::Profile::is_packed_table( $table ) )
    {
        $counts = pack "f*", (0) x $colnum;

        foreach $row ( @{ $table->values } )
        {
            &Common::Util_C::add_arrays_float( $counts, $row, $colnum );
        }

        @counts = unpack "f*", $counts;
    }
    else 
    {
        @counts = (0) x $colnum;

        foreach $row ( @{ $table->values } )
        {
            for ( $i = 0; $i < $colnum; $i += 1 )
            {
                $counts[$i] += $row->[$i];
            }
        }
    }

    if ( defined wantarray )
    {
        return wantarray ? @counts : \@counts;
    }
    else {
        $table->col_totals( \@counts );
    }

    return;
}

sub tablify_tree
{
    # Niels Larsen, November 2012. 

    # Converts a hash of nodes used for similarity mapping to a table object 
    # with the fields and values listed at the top of this module. This table
    # structure is used by the output routines.

    my ( $tree,
         $rowmax,
        ) = @_;

    # Returns an object.

    my ( $subref, $tab, $node, $nid, $row, $counts, $i, @len, $len, $hdrs, 
         $rows, @hdrs, @ndcs, @temp );

    $rowmax //= 1;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ADD ROW HEADERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $subref = sub
    {
        my ( $tree,
             $nid,
             $tpre,
             $tab,
            ) = @_;

        my ( $node );

        $node = $tree->{ $nid };
        
        # Put taxonomy strings into row headers,

        if ( $tpre ) {
            $tpre .= "; ". $node->[OTU_NAME];
        } else {
            $tpre = $node->[OTU_NAME];
        }
        
        push @{ $tab->{"row_headers"} }, $tpre;

        # Put score string into values,
        
        push @{ $tab->{"values"} }, $node->[SIM_SCORES];
        
        # If there are children, then loop through them,
        
        foreach $nid ( @{ $node->[CHILD_IDS] } )
        {
            if ( exists $tree->{ $nid } ) 
            {
                $subref->( $tree, $nid, $tpre, $tab );
            }
        }
        
        return $tab;
    };

    $tab = {};

    foreach $nid ( @{ $tree->{ $Root_id }->[CHILD_IDS] } )
    {
        $subref->( $tree, $nid, "", $tab );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> ADD COLUMN HEADERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $tree->{"col_headers"} ) {
        $tab->{"col_headers"} = &Storable::dclone( $tree->{"col_headers"} );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SORT BY TAXONOMY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sort by connecting taxonomy row headers with indices and then rearranging
    # value rows according to those indices,

    @hdrs = @{ $tab->{"row_headers"} };
    
    $i = 0;
    @temp = sort { $a->[1] cmp $b->[1] } map {[ $i++, $_ ]} @hdrs;
    
    @hdrs = map { $_->[1] } @temp;
    @ndcs = map { $_->[0] } @temp;
    
    @{ $tab->{"values"} } = @{ $tab->{"values"} }[ @ndcs ];
    @{ $tab->{"row_headers"} } = @hdrs;     
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> COLUMN TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $len = &Taxonomy::Tree::count_columns( $tree );

    $counts = pack "f*", (0) x $len;

    foreach $row ( @{ $tab->{"values"} } )
    {
        &Common::Util_C::add_arrays_float( $counts, $row, $len );
    }

    $tab->{"col_totals"} = [ unpack "f*", $counts ];
    $tab->{"col_reads"} = &Storable::dclone( $tree->{"col_reads"} );

    $tab->{"col_count"} = scalar @{ $tab->{"col_totals"} };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROW TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $rowmax )
    {
        foreach $row ( @{ $tab->{"values"} } )
        {
            push @{ $tab->{"row_maxima"} }, &Common::Util_C::max_value_float( $row, $len );
        }
    }
    else {
        $tab->{"row_maxima"} = undef;
    }

    # Scores grand totals,

    $tab->{"sco_total"} = &List::Util::sum( @{ $tab->{"col_totals"} } );

    # >>>>>>>>>>>>>>>>>>>>>>>>> ADD NON-MATCH ROW <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # A top row for those that did not match,
    
    if ( $tree->{ $Mis_nid } ) {
        $tab->{"mis_totals"} = [ unpack "f*", $tree->{ $Mis_nid }->[SIM_SCORES] ];
    } else {
        $tab->{"mis_totals"} = [ (0) x $tab->{"col_count"} ];
    }

    bless $tab;

    return wantarray ? %{ $tab } : $tab;
}

sub tax_show_string
{
    # Niels Larsen, October 2012. 

    # Replaces empty placeholders with "Unclassified" and removes all other 
    # placeholders. The result is a printable string for human-readable outputs.
    # Purely for display purpose.

    my ( $str,         # Taxonomy string
        ) = @_;

    # Returns a string.

    my ( @str, $grp );

    @str = split /;\s*/, $str;

    while ( @str and $str[-1] =~ /^[a-z\+]__$/ ) {
        pop @str;
    }
    
    foreach $grp ( @str )
    {
        if ( $grp =~ /^[a-z\+]__$/ ) {
            $grp = $Mis_title;
        } elsif ( $grp =~ /Unclassified/ ) {
            $grp = "----";
        } else {
            $grp =~ s/^[a-z\+]__//; 
        }
    }

    return join "; ", @str;
}

sub taxify_sims
{
    # Niels Larsen, January 2013. 

    # This routine maps database similarities for one query sequence onto a 
    # taxonomic tree where database sequences are leaves. Input is a list of 
    # similarity tuples [ seq_id, sim_pct ].
    #
    # The logic is simple. First find the taxonomic group that exactly spans
    # all included similarities, which is the top one percent by default. Then
    # from that group look at the children: if one of them have more than N%
    # (default 90%) of the total score for all children, then assign the 
    # score total to that node instead. Keep moving towards the leaves until
    # this no longer is true. 
    # 
    # The parameters and their effects are (defaults in parantheses):
    # 
    #   top_sim    Range of lesser similarities to include
    #   sim_wgt    Down-weighting of less good matches
    #   read_count The read count
    #   min_grp    Minimum score percent for a child to be score node

    my ( $args, 
        ) = @_;

    # Returns two lists. 

    my ( $sim_list, $top_sim, $sim_wgt, $read_count, $tax_cache, $tax_dbh, 
         $sim_pcts, $sim_ids, $sim_scos, $sco_nid, $leaf_sco, $node, $method,
         $sco_tree, $leaves, $sim_wgts, $tax_sub, $beg_depth, $max_depth, 
         $max_amb );

    $tax_dbh = $args->{"tax_dbh"};           # Taxonomy storage handle
    $tax_cache = $args->{"tax_cache"};       # Taxonomy tree cache 
    $tax_sub = $args->{"tax_sub"};           # Node processing method
    $sim_list = $args->{"sim_list"};         # List of [ id, pct ] tuples
    $top_sim = $args->{"top_sim"};           # Top similarity range to use
    $sim_wgt = $args->{"sim_wgt"};           # Similarity weight exponent
    $max_amb = $args->{"max_amb"};           # Maximum ambiguity level
    $read_count = $args->{"read_count"};     # Original read count

    # >>>>>>>>>>>>>>>>>>>>>>>> GET TOP SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Use only the top range of the similarities. If for example the highest 
    # similarity percentage is 80 and $top_sim is 1, then similarities between 
    # 79 and 80 are used,

    $sim_list = &Seq::Simrank::get_top_sims( $sim_list, $top_sim );

    $sim_ids = [ map { $_->[0] } @{ $sim_list } ];
    $sim_pcts = [ map { $_->[1] } @{ $sim_list } ];

    # >>>>>>>>>>>>>>>>>>>>>> PERCENTAGES TO SCORES <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    # 
    # Convert percentages to scores that add up to the given read count. The
    # percentages are converted to weights that add up to 1.0 as this example,
    # 
    #  100, 100, 98, 97, 96.3, 92 -> 0.344, 0.344, 0.115, 0.086, 0.073, 0.038
    # 
    # Below weights are then multiplied by the read count ($read_count) to give 
    # scores. 

    $sim_wgts = &Taxonomy::Profile::pcts_to_weights( $sim_pcts, $read_count, $sim_wgt );
    
    # >>>>>>>>>>>>>>>>>>>>>>>> UPDATE SCORE TREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Instead of loading an entire taxonomy, which can be large and take much
    # ram, keep a cache version with only the parts of that have similarities.
    # Below $tax_cache does that: when there are similarities to nodes not 
    # present, then fetch them from the DBM storage. That way it grows "on 
    # demand". It will keep growing during a run.

    &Taxonomy::Tree::load_new_parents( $tax_dbh, $sim_ids, $tax_cache );
    
    # >>>>>>>>>>>>>>>>>>>>>>> LEAST COMMON SUBTREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a taxonomy subtree skeleton that exactly spans all similarities, 
    # and return the common ancestor node id. This mini-tree is then decorated
    # with scores below,

    ( $sco_nid, $sco_tree ) = &Taxonomy::Profile::init_score_tree( $tax_cache, $sim_ids );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CLIP SCORE TREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Count the number of leaves before pruning or clipping,

    $leaves = &Taxonomy::Tree::count_leaves( $sco_tree );

    # Run the $tax_sub routine, which may prune and clip the tree,

    &Taxonomy::Tree::traverse_head( $sco_tree, $sco_nid, $tax_sub );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ASSIGN SCORES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Divide the score total between the leaves of the score-tree, i.e. between
    # the tree "tips" without children. Create a score hash with those node ids
    # as keys and their score as value,

    $max_depth = &Taxonomy::Tree::max_depth( $sco_tree );
    $beg_depth = $sco_tree->{ $sco_nid }->[DEPTH];

    if ( ( $max_depth - $beg_depth ) <= $max_amb )
    {
        $sim_scos = {};
        $leaf_sco = &List::Util::sum( @{ $sim_wgts } ) / $leaves;

        foreach $node ( values %{ $sco_tree } )
        {
            if ( not @{ $node->[CHILD_IDS] } )
            {
                $sim_scos->{ $node->[NODE_ID] } = $leaf_sco * $node->[NODE_SUM];
            }
        }

        return wantarray ? %{ $sim_scos } : $sim_scos;
    }

    return;
}

sub titles_from_paths
{
    # Niels Larsen, March 2013.

    # Hack that gets a header from a typical file name. This is a hack
    # that should go away when headers are carried through all steps.
    # TODO - fix.

    my ( $hdrs,
        ) = @_;

    my ( $hdr, @hdrs );

    @hdrs = ();

    foreach $hdr ( @{ $hdrs } ) 
    {
        if ( $hdr =~ /^([^\.]+)\.([^\.]+)\./ ) {
            push @hdrs, $1;
        } else {
            push @hdrs, $hdr;
        }
    }

    return wantarray ? @hdrs : \@hdrs;
}

sub unpack_table
{
    # Niels Larsen, November 2012. 

    # Modifies a given table by packing its row values. Returns updated table.

    my ( $table,   # Table hash
        ) = @_;

    # Returns a hash

    my ( $i );

    for ( $i = 0; $i <= $#{ $table->{"values"} }; $i += 1 )
    {
        $table->{"values"}->[$i] = [ unpack "f*", $table->{"values"}->[$i] ];
    }

    wantarray ? %{ $table } : $table;
}

sub unpack_table_clone
{
    # Niels Larsen, November 2012. 

    # Makes a copy of a table structure with unpacked value strings. 
    # The given table is not affected. Returns a hash.

    my ( $table,   # Table hash
        ) = @_;

    # Returns a hash

    my ( $ftab, $key, $row );

    foreach $key ( keys %{ $table } )
    {
        if ( $key eq "values" ) 
        {
            foreach $row ( @{ $table->{"values"} } )
            {
                push @{ $ftab->{"values"} }, [ unpack "f*", $row ];
            }
        }
        elsif ( ref $table->{ $key } ) {
            $ftab->{ $key } = &Storable::dclone( $table->{ $key } );
        } else {
            $ftab->{ $key } = $table->{ $key };
        }
    }

    bless $ftab, "Common::Table";

    wantarray ? %{ $ftab } : $ftab;
}

sub write_stats
{
    # Niels Larsen, August 2012. 

    # Creates a Config::General formatted string with tags that are understood 
    # by Recipe::Stats::html_body. Writes the string to the given file in void
    # context, otherwise returns it. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $oseqs, $title, $value, $steps, $step, $fstep, 
         $time, $iseq, $ires, $oseq, $ores, $seqdif, $resdif, $seqpct, 
         $respct, $lstep, $key, $i, $istr, $pstr, $elem, $file, $str1, $str2,
         $pct, $dir, $home );

    # >>>>>>>>>>>>>>>>>>>>>>>> FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stats->{"itable"} ) 
    {
        $title = $stats->{"itable"}->{"title"};
        $value = &File::Basename::basename( $stats->{"itable"}->{"value"} );

        $istr = qq (      file = $title\t$value\n);
    }
    else
    {
        $istr = "      <menu>\n";
        $istr .= "         title = Input sequence files\n";

        foreach $file ( @{ $stats->{"ifiles"} } )
        {
            $file = &File::Basename::basename( $file );
            $istr .= qq (         item = $file\n);
        }

        $istr .= "      </menu>\n";
    }

    $title = $stats->{"dbfile"}->{"title"};
    $value = $stats->{"dbfile"}->{"value"};

    $istr .= qq (      file = $title\t$value\n);

    chomp $istr;
    $pstr = "";

    foreach $elem ( @{ $stats->{"params"} } ) {
        $pstr .= qq (         item = $elem->{"title"}: $elem->{"value"}\n);
    }

    chomp $pstr;

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
$istr
      <menu>
         title = Parameters
$pstr
      </menu>
);

    foreach $key ( qw ( oraw oraw-html onorm onorm-html osims omiss ) )
    {
        next if not exists $stats->{ $key };

        $title = $stats->{ $key }->{"title"};
        $value = &File::Basename::basename( $stats->{ $key }->{"value"} );

        $text .= qq (      file = $title\t$value\n);
    }

    $time = &Time::Duration::duration( $stats->{"seconds"} );

    $text .= qq (      date = $stats->{"finished"}
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $steps = $stats->{"steps"};
    $fstep = $steps->[0];

    $text .= qq (
   <table>
      colh = Type\tSeqs\t&Delta;\t&Delta; %\tReads\t&Delta;\t&Delta; %
      trow = Total input\t$fstep->{"seq"}\t\t\t$fstep->{"res"}\t\t\t
);

    for ( $i = 1; $i <= $#{ $steps }; $i++ )
    {
        $step = $steps->[$i];

        $title = $step->{"title"};

        $iseq = $steps->[$i-1]->{"seq"};
        $ires = $steps->[$i-1]->{"res"};
        $oseq = $step->{"seq"};
        $ores = $step->{"res"};

        $seqdif = $oseq - $iseq;
        $resdif = $ores - $ires;

        if ( $iseq == 0 ) {
            $seqpct = sprintf "%.1f", 0;
        } else {
            $seqpct = ( sprintf "%.1f", 100 * $seqdif / $iseq );
        }

        if ( $ires == 0 ) {
            $respct = sprintf "%.1f", 0;
        } else {
            $respct = ( sprintf "%.1f", 100 * $resdif / $ires );
        }

        $text .= qq (      trow = $title\t$oseq\t$seqdif\t$seqpct\t$ores\t$resdif\t$respct\n);
    }

    $text .= qq (   </table>\n\n);

    $text .= qq (</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
};

sub write_stats_filter
{
    # Niels Larsen, June 2012. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $istr, $pstr, $tpct, $spct, $rpct, $key, $time, $file,
         $elem, $tuple, $itable, $otable, $vstr, $date, $secs, $summary,
         $reads, $mapped );

    $itable = &File::Basename::basename( $stats->{"itable"} );
    $otable = &File::Basename::basename( $stats->{"otable"} );

    $summary = qq (
Below are spreadsheet-ready taxonomy table in four variants, each with an
HTML version. The first two show scores as is, the second two (.sum and .sum.html) 
include values for all parent groups. In the third two (.norm and .norm.html)
values are adjusted in each column, so their sum equals a fixed value, give 
or take rounding errors. The last two have both parent sums and are normalized.
);
    $summary =~ s/\n/ /g;
    $summary =~ s/ +/ /g;

    $reads = $stats->{"reads"} // 0;
    $mapped = $stats->{"mapped"} // 0;

    $date = $stats->{"finished"};
    $secs = $stats->{"seconds"};
    $time = &Time::Duration::duration( $secs );

    # >>>>>>>>>>>>>>>>>>>>>>>> FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $istr = qq (      file = Input profile\t$itable\n);
    chomp $istr;

    $pstr = "";

    foreach $elem ( @{ $stats->{"params"} } ) {
        $pstr .= qq (         item = $elem->{"title"}: $elem->{"value"}\n);
    }

    chomp $pstr;

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   summary = $summary

   <header>
$istr
      <menu>
         title = Parameters
$pstr
      </menu>
      file = Original counts\t$otable
      file = Original counts\t$otable.html
      file = Original counts + sums\t$otable.sum
      file = Original counts + sums\t$otable.sum.html
      file = Scaled counts\t$otable.norm
      file = Scaled counts\t$otable.norm.html
      file = Scaled counts + sums\t$otable.norm.sum
      file = Scaled counts + sums\t$otable.norm.sum.html
      hrow = Input reads total\t$reads
      hrow = Mapped reads total\t$mapped
      secs = $secs
      date = $date
      time = $time
   </header>

</stats>
);

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_stats_format_dirs
{
    # Niels Larsen, April 2013. 

    # Writes a summary table for a given list of statistics files. The title,
    # name and parameters are taken from the first of the files. Returns text
    # in non-void context or writes a file.

    my ( $files,     # File list
         $ofile,     # Output file
        ) = @_;

    # Returns string or nothing.

    my ( $file, $text, $name, $path, $stats, $outdir, $subdir, $date, $secs,
         $params, $title, $tab_text, $pstr, $i, $time, $reads, $reads_total,
         $mapped, $mapped_total );

    $secs = 0;
    $tab_text = "";
    $reads_total = 0;

    for ( $i = 0; $i <= $#{ $files }; $i += 1 )
    {
        $file = $files->[$i];

        $stats = &Recipe::IO::read_stats( $file )->[0];

        $reads = &Recipe::Stats::head_row( $stats, "Input reads total" );
        $mapped = &Recipe::Stats::head_row( $stats, "Mapped reads total" );

        if ( $i == 0 )
        {
            $name = $stats->{"name"};
            $title = $stats->{"title"};
        }
        
        $secs += &Recipe::Stats::head_type( $stats, "secs" );
        
        $path = &File::Basename::dirname( $file );
        $subdir = &File::Basename::basename( $path );

        $name = $subdir;
        $name =~ s/_/ /g;
        
        $tab_text .= qq (       trow = $name\t$reads\t$mapped\thtml=Taxonomy tables:$subdir/step.stats.html\n);

        $reads_total += $reads;
        $mapped_total += $mapped;
    }

    chomp $tab_text;

    $date = &Common::Util::epoch_to_time_string();
    $time = &Time::Duration::duration( $secs );

    $text = qq (
<stats>

   title = $title
   name = $name

   <header>
      hrow = Reads total\t$reads_total
      hrow = Mapped total\t$mapped_total
      date = $date
      secs = $secs
      time = $time     
   </header>

   <table>
       title = Taxonomy profiles
       colh = Primer target group\tReads\tMapped\tTaxonomy tables
$tab_text
   </table>

</stats>

);

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $ofile, $text, 1 );
    }
}
    
sub write_stats_profile
{
    # Niels Larsen, January 2013. 

    # Creates a Config::General formatted string with tags that are understood 
    # by Recipe::Stats::html_body. Writes the string to the given file in void
    # context, otherwise returns it. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $oseqs, $title, $value, $steps, $step, $fstep, $secs,
         $time, $iseq, $ires, $oseq, $ores, $seqdif, $resdif, $seqpct, 
         $respct, $lstep, $key, $i, $istr, $pstr, $elem, $file, $str1, $str2,
         $pct, $dir, $titles, $reads, $counts );

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $key ( qw ( seqs sims taxdbm ) )
    {
        $title = $stats->{ $key }->{"title"};
        $value = &File::Basename::basename( $stats->{ $key }->{"value"} );
        
        $text .= qq (      file = $title\t$value\n);
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text .= qq (      <menu>
         title = Parameters
);

    foreach $elem ( @{ $stats->{"params"} } )
    {
        $text .= qq (         item = $elem->{"title"}: $elem->{"value"}\n);
    }

    $text .= qq (      </menu>\n);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $title = $stats->{"profile"}->{"title"};
    $value = &File::Basename::basename( $stats->{"profile"}->{"value"} );

    $text .= qq (      file = $title\t$value\n);

    $secs = $stats->{"seconds"};
    $time = &Time::Duration::duration( $secs );

    $text .= qq (      date = $stats->{"finished"}
      secs = $secs
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> COUNTS TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $counts = $stats->{"counts"};

    $titles = {
        "reads" => "Input reads total",
        "mapped" => "Profiled reads total",
        "ambig" => "Ambiguous mappings total",
        "nosim" => "No similarities total",
        "lowsim" => "Low similarities total",
        "short" => "Short sequences total",
    };

    $text .= qq (
   <table>
      title = Profiling totals
      colh = \tReads\t%
);

    $reads = $counts->{"reads"};

    foreach $key ( qw ( reads nosim lowsim short ambig mapped ) )
    {
        $title = $titles->{ $key };
        $value = $counts->{ $key } // 0;

        if ( $value == 0 ) {
            $pct = sprintf "%.1f", 0;
        } else {
            $pct = ( sprintf "%.1f", 100 * $value / $reads );
        }

        $text .= qq (      trow = $title\t$value\t$pct\n);
    }

    $text .= qq (   </table>\n\n);
    
    $text .= qq (</stats>\n\n);

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
};

sub write_stats_profile_sum
{
    # Niels Larsen, April 2013. 

    # Reads the given statistics files and creates and writes a single 
    # summary statistics file.

    my ( $files,    # Input statistics files
         $ofile,    # Output statistics file
        ) = @_;
    
    # Returns nothing. 

    my ( $stats, $file, @table, $name, $rows, $row, @params, @row, $pstr, $text, 
         $date, $time, @nums, @tots, $i, $match_pct, $secs );

    # Create summary table values,

    $secs = 0;

    foreach $file ( @{ $files } )
    {
        $stats = &Recipe::IO::read_stats( $file )->[0];
        $secs += &Recipe::Stats::head_type( $stats, "secs" );

        $name = &File::Basename::dirname( $file );
        $name = &File::Basename::basename( $name );
        $name =~ s/_/ /g;

        $rows = $stats->{"tables"}->[0]->{"rows"};

        @nums = map { ( split "\t", $_->{"value"} )[1] } @{ $rows };

        $i = 0;
        map { $tots[$i++] += $_ } @nums;

        $match_pct = sprintf "%.2f", 100 * $nums[1] / $nums[0];
        
        push @table, [ $name, @nums, $match_pct ];
    }

    # Get parameters etc from last read file (they all have same headers),

    $rows = $stats->{"headers"}->[0]->{"rows"};

    @params = &Recipe::Stats::head_menu( $stats, "Parameters" );
    $pstr = join "\n", map { "           item = $_" } @params;

    $match_pct = sprintf "%.2f", 100 * $tots[1] / $tots[0];

    $date = &Recipe::Stats::head_type( $stats, "date" );
    $time = &Time::Duration::duration( $secs );
    
    # Format stats text,

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
       file = $rows->[0]->{"title"}\t$rows->[0]->{"value"}
       hrow = Reads total\t$tots[0]
       hrow = Matches total\t$tots[1] ($match_pct%)
       hrow = Misses total\t$tots[2]
       hrow = Too dissimilar\t$tots[3]
       hrow = Too short\t$tots[4]
       <menu>
           title = Parameters
$pstr
       </menu>
       date = $date
       secs = $secs
       time = $time
   </header>

   <table>
       title = Taxonomy profiling statistics
       colh = Target group\tReads\tMatches\tMisses\tLowsim\tShort\tMatch %
);

    foreach $row ( @table )
    {
        $text .= "       trow = ". ( join "\t", @{ $row } ) ."\n";
    }
    
    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $ofile, $text, 1 );
    }

    return;
}

sub write_stats_sims
{
    # Niels Larsen, January 2013. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $fh, $text, $time, $itotal, $ototal, $mtotal, @table, $row, $str, 
         $matpct, $mispct, $file, $istr, $item, $title, $value, $size, $in, 
         $out, $name, $stat, $fstr, $secs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> BARCODE TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Make a table of file, tag, count, and percent; sort by percent,

    @table = ();

    foreach $stat ( @{ $stats->{"files"} } )
    {
        ( $file, $in, $out ) = @{ $stat };

        $in //= 0;
        $out //= 0;

        $name = &File::Basename::basename( $file );

        push @table, [ "file=$name", $in, $out, $in - $out,
                       100 - 100 * $out / $in ];
    }

    @table = sort { $b->[1] <=> $a->[1] } @table;

    $itotal = &List::Util::sum( map { $_->[1] // 0 } @table ) // 0;
    $ototal = &List::Util::sum( map { $_->[2] // 0 } @table ) // 0;

    foreach $row ( @table )
    {
        $row->[1] //= 0;
        $row->[2] //= 0;
        $row->[3] //= 0;
        $row->[4] = sprintf "%.2f", $row->[4];
    }

    # >>>>>>>>>>>>>>>>>>>>> HEADER FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<

    $title = $stats->{"dbfile"}->{"title"};
    $value = &File::Basename::basename( $stats->{"dbfile"}->{"value"} );
    $fstr = qq (      file = $title\t$value\n);

    if ( $stats->{"osims"} )
    {
        $title = $stats->{"osims"}->{"title"};
        $value = &File::Basename::basename( $stats->{"osims"}->{"value"} );
        $fstr .= qq (      file = $title\t$value\n);
    }

    if ( $stats->{"omiss"} )
    {
        $title = $stats->{"omiss"}->{"title"};
        $value = &File::Basename::basename( $stats->{"omiss"}->{"value"} );
        $fstr .= qq (      file = $title\t$value\n);
    }

    chomp $fstr;
    
    $istr = "";

    foreach $item ( @{ $stats->{"params"} } )
    {
        $title = $item->{"title"};
        $value = $item->{"value"};
        
        $istr .= qq (         item = $title: $value\n);
    }

    chomp $istr;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $matpct = sprintf "%.2f", 100 * $ototal / $itotal;

    $mtotal = $itotal - $ototal;
    $mispct = sprintf "%.2f", ( 100 - 100 * $ototal / $itotal );

    $secs = $stats->{"seconds"};
    $time = &Time::Duration::duration( $secs );

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
$fstr
      hrow = Input total\t$itotal
      hrow = Match total\t$ototal ($matpct%)
      hrow = Non-match total\t$mtotal ($mispct%)
      <menu>
         title = Parameters
$istr
      </menu>
      date = $stats->{"finished"}
      secs = $secs
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text .= qq (
   <table>
      title = Similarity match/mismatch statistics
      colh = Target group\tReads\tMatches\tMisses\tMiss %
);

    foreach $row ( @table )
    {
        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }

    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_stats_sims_sum
{
    # Niels Larsen, April 2013. 

    # Reads the given statistics files and creates and writes a single 
    # summary statistics file.

    my ( $files,    # Input statistics files
         $ofile,    # Output statistics file
        ) = @_;
    
    # Returns nothing. 

    my ( $stats, $file, @table, $name, $rows, $row, $reads, $matches, $misses,
         @params, @row, $pstr, $text, $dbfile, $dbtitle, $reads_tot, $match_tot,
         $miss_tot, $miss_pct, $time, $date, $secs );

    # Create summary table values,

    $reads_tot = 0;
    $match_tot = 0;
    $miss_tot = 0;
    $secs = 0;

    foreach $file ( @{ $files } )
    {
        $stats = &Recipe::IO::read_stats( $file )->[0];

        $secs += &Recipe::Stats::head_type( $stats, "secs" );

        $name = &File::Basename::dirname( $file );
        $name = &File::Basename::basename( $name );
        $name =~ s/_/ /g;

        $reads = 0;
        $matches = 0;

        foreach $row ( @{ $stats->{"tables"}->[0]->{"rows"} } )
        {
            @row = split "\t", $row->{"value"};

            $reads += $row[1];
            $matches += $row[2];
        }

        $misses = $reads - $matches;

        push @table, [
            $name, $reads, $matches, $misses, 
            sprintf "%.2f", 100 * $misses / $reads,
        ];

        $reads_tot += $reads;
        $match_tot += $matches;
        $miss_tot += $misses;
    }

    # Get parameters etc from last read file (they all have same headers),

    $rows = $stats->{"headers"}->[0]->{"rows"};

    @params = &Recipe::Stats::head_menu( $stats, "Parameters" );

    $pstr = join "\n", map { "           item = $_" } @params;

    $miss_pct = sprintf "%.2f", 100 * $miss_tot / $reads_tot;

    $date = &Recipe::Stats::head_type( $stats, "date" );
    $time = &Time::Duration::duration( $secs );

    # Format stats text,

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
       file = $rows->[0]->{"title"}\t$rows->[0]->{"value"}
       hrow = Reads total\t$reads_tot
       hrow = Matches total\t$match_tot
       hrow = Misses total\t$miss_tot ($miss_pct%)
       <menu>
           title = Parameters
$pstr
       </menu>
       date = $date
       secs = $secs
       time = $time
   </header>

   <table>
       title = Similarity match/mismatch statistics
       colh = Target group	Reads	Matches	Misses	Miss %
);

    foreach $row ( @table )
    {
        $text .= "       trow = ". ( join "\t", @{ $row } ) ."\n";
    }
    
    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $ofile, $text, 1 );
    }

    return;
}

1;

__END__

# sub pcts_to_weights_hash
# {
#     # Niels Larsen, April 2012. 

#     # Given a list of percentage values, creates a list of corresponding
#     # weights. The weights are 1 plus the inverse of the differences between
#     # the highest percentage and a given one. The numbers are then scaled 
#     # down so their sum is 1. Example percentages and weights,
#     #
#     # 100, 100, 98, 97, 96.3, 92 -> 0.344, 0.344, 0.115, 0.086, 0.073, 0.038
    
#     my ( $pcts,    # List of percentages
#          $mult,    # Number to multiply each weight with - OPTIONAL, default 1
#          $wgtx,    # Down-weighting exponentiation factor - OPTIONAL, default 0
#         ) = @_;

#     # Returns a hash.

#     my ( @pcts, %wgts, $max, $id, $pct, $sum, $val );

#     $mult //= 1;

#     if ( defined $wgtx )
#     {
#         $max = &List::Util::max( values %{ $pcts } );
        
#         foreach $id ( keys %{ $pcts } )
#         {
#             $pct = $pcts->{ $id };
#             $wgts{ $id } = 1 / ( 1 + $max - $pct ) ** $wgtx;
#         }
        
#         $sum = &List::Util::sum( values %wgts );
        
#         if ( $sum > 0 )
#         {
#             if ( $mult > 1 ) {
#                 %wgts = map { $_ => $mult * $wgts{ $_ } / $sum } keys %wgts;
#             } else {
#                 %wgts = map { $_ => $wgts{ $_ } / $sum } keys %wgts;
#             }
#         }
#         else {
#             %wgts = map { $_ => 1 } keys %wgts;
#         }
#     }
#     else
#     {
#         $val = $mult / scalar ( keys %{ $pcts } );
#         %wgts = map { $_ => $val } keys %{ $pcts };
#     }

#     return wantarray ? %wgts : \%wgts;
# }

# sub check_tree
# {
#     # Niels Larsen, December 2012. 

#     # Reduces the tree so that only rows containing a value higher than a given
#     # threshold is kept. 

#     my ( $nodes,     # Hash of nodes
#          $rootid,
#         ) = @_;

#     # Returns nothing.

#     my ( $subref, $argref, $count );

#     $count = 0;
#     $rootid //= $Root_id;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FIND SUMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $subref = sub 
#     {
#         my ( $nodes, $nid, $level ) = @_;
        
#         my ( $cid );

#         foreach $cid ( @{ $nodes->{ $nid }->[CHILD_IDS] } )
#         {
#             if ( not exists $nodes->{ $cid } ) {
#                 $count += 1;
#             }
#         }

#         return $count;
#     };
    
#     $argref = [];

#     &Taxonomy::Tree::traverse_head( $nodes, $rootid, $subref, $argref );

#     return $count;
# }


# sub load_tax_tree
# {
#     # Niels Larsen, January 2013. 
    
#     # Builds a memory tree structure of the subtree that starts at a given
#     # root id. If another tree is given as a cache, then the tree is copied
#     # from there. 

#     my ( $dbm,         # Input dbm storage file or handle
#         ) = @_;

#     # Returns a hash.

#     my ( $dbh, $ids, $id, $par_id, $tree, @child_ids );

#     if ( ref $dbm ) {
#         $dbh = $dbm;
#     } else {
#         $dbh = &Common::DBM::read_open( $dbm );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> FROM FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $ids = &Common::DBM::get_struct( $dbh, "all_node_ids" );
#     $tree = &Common::DBM::get_struct_bulk( $dbh, $ids );

#     foreach $id ( keys %{ $tree } )
#     {
#         if ( defined ( $par_id = $tree->{ $id }->[PARENT_ID] ) )
#         {
#             if ( defined $tree->{ $par_id }->[CHILD_IDS] ) {
#                 push @{ $tree->{ $par_id }->[CHILD_IDS] }, $id;
#             } else {
#                 $tree->{ $par_id }->[CHILD_IDS] = [ $id ];
#             }
#         }
#     }

#     if ( not ref $dbm ) {
#         &Common::DBM::close( $dbh );
#     }

#     return wantarray ? %{ $tree } : $tree;
# }

# sub common_ancestor
# {
#     # Niels Larsen, January 2013.

#     # Returns the id of the node where the minimal subtree starts that spans 
#     # all given node ids. 

#     my ( $tree,    # Tree structure
#          $nids,    # Node id list
#         ) = @_;

#     # Returns string.

#     my ( %depth, $nid, $pid, $ca_nid, $ca_dep, $i );

#     $nid = $nids->[0];

#     $ca_nid = $nid;
#     $ca_dep = $Tax_depths{"n__"};

#     while ( not exists $depth{ $nid } )
#     {
#         $depth{ $nid } = $tree->{ $nid }->[DEPTH];
        
#         if ( defined ( $pid = $tree->{ $nid }->[PARENT_ID] ) ) {
#             $nid = $pid;
#         } else {
#             last;
#         }
#     }

#     for ( $i = 1; $i <= $#{ $nids }; $i += 1 )
#     {
#         $nid = $nids->[$i];

#         while ( not exists $depth{ $nid } )
#         {
#             $depth{ $nid } = $tree->{ $nid }->[DEPTH];
#             $nid = $tree->{ $nid }->[PARENT_ID];
#         }
        
#         if ( $depth{ $nid } < $ca_dep )
#         {
#             $ca_nid = $nid;
#             $ca_dep = $depth{ $nid };
#         }
#     }

#     return $ca_nid;
# }

# sub create_col_titles
# {
#     # Niels Larsen, January 2013. 

#     # 
#     my ( $args,
#         ) = @_;


#     $args{"regex"} = $args->regex;

#     # Id file given,

#     if ( $args->idfile )
#     {
#         @list = map { [ &File::Basename::basename( $_ ), $_ ] } @{ $args{"iseqs"} };

#         # Read and check ids,

#         $tags = &Seq::IO::read_table_tags( $args->idfile );
        
#         if ( $tags->[0]->{"ID"} ) {
#             @hdrs = map { $_->{"ID"} } @{ $tags };
#         } elsif ( $tags->[0]->{"F-tag"} ) {
#             @hdrs = map { $_->{"F-tag"} } @{ $tags }; 
#         } else {
#             @hdrs = map { $_->{"R-tag"} } @{ $tags }; 
#         }            

#         if ( ( $i = scalar @{ $tags } ) != ( $j = scalar @hdrs ) )
#         {
#             push @msgs, ["ERROR", qq ($i ID table rows but $j IDs) ];
#             push @msgs, ["INFO", qq (Use the barcode file from de-multiplexing) ];

#             &append_or_exit( \@msgs );
#         }

#         # Connect the given ids with file names so that the file names 
#         # assume the order of the headers,

#         @files = ();
        
#         foreach $hdr ( @hdrs )
#         {
#             if ( @hits = grep { $_->[0] =~ /\.$hdr\./ } @list )
#             {
#                 $i = scalar @hits;

#                 if ( $i == 1 ) {
#                     push @files, [ $hdr, $hits[0]->[1] ];
#                 } else {
#                     push @msgs, ["ERROR", qq ($i file names match "$hdr") ];
#                 }
#             }
#             else {
#                 push @files, [ $hdr, undef ];
#             }
#         }

#         # Save the now rearranged file paths and headers,

#         @{ $args{"iseqs"} } = map { $_->[1] } @files;
#         @{ $args{"titles"} } = map { $_->[0] } @files;
#     }
    
#     # Expression given, use file names and whatever order they list in,

#     elsif ( $regex = $args->regex ) 
#     {
#         @list = map { &File::Basename::basename( $_ ) } @{ $args{"iseqs"} };

#         @list = map { $_ =~ /($regex)/; $1 } @list;

#         if ( grep { not defined $_ } @list )
#         {
#             push @msgs, ["ERROR", qq (Expression did not match all file names -> "$regex") ];
#             push @msgs, ["INFO", qq (Try put the expression in single quotes, or) ];
#             push @msgs, ["INFO", qq (escape special characters with an extra backslash.) ];

#             &append_or_exit( \@msgs );
#         }

#         $args{"titles"} = \@list;
#     }

#     # Just use file names, use whatever order they list in,

#     else
#     {
#         @list = map { &File::Basename::basename( $_ ) } @{ $args{"iseqs"} };

#         if ( scalar @list > 1 ) {
#             @list = &Common::Util::trim_strings_common( \@list );
#         }

#         $args{"titles"} = \@list;
#     }

#     # Check that titles are unique,

#     @list_uniq = &Common::Util::uniqify( $args{"titles"} );

#     if ( (scalar @list) != ( scalar @list_uniq ) )
#     {
#         %counts = ();
#         map { $counts{ $_ } += 1 } @list;

#         foreach $hdr ( sort keys %counts )
#         {
#             if ( $counts{ $hdr } > 1 ) {
#                 push @msgs, ["ERROR", qq (Non-unique header ID -> "$hdr") ];
#             }
#         }
#     }

#     &append_or_exit( \@msgs );

    
# sub taxify_sims_old
# {
#     # Niels Larsen, January 2013. 

#     # This routine maps database similarities for one query sequence onto a 
#     # taxonomic tree where database sequences are leaves. Input is a list of 
#     # similarity tuples [ seq_id, sim_pct ].
#     #
#     # The logic is simple. First find the taxonomic group that exactly spans
#     # all included similarities, which is the top one percent by default. Then
#     # from that group look at the children: if one of them have more than N%
#     # (default 90%) of the total score for all children, then assign the 
#     # score total to that node instead. Keep moving towards the leaves until
#     # this no longer is true. 
#     # 
#     # The parameters and their effects are (defaults in parantheses):
#     # 
#     #   top_sim    Range of lesser similarities to include
#     #   sim_wgt    Down-weighting of less good matches
#     #   sco_mult   The read count
#     #   min_grp    Minimum score percent for a child to be score node

#     my ( $args, 
#         ) = @_;

#     # Returns two lists. 

#     my ( $sim_sref, $top_sim, $sim_wgt, $sco_mult, $min_grp, $tax_cache, 
#          $tax_dbh, $sim_pcts, $sim_ids, $node_id, $parent_id, $i, $id,
#          $sim_scos, $sco_nid, $all_sum, $sim_max, $child_ids, $descend, 
#          $sco_sum, $child_scos, $child_sum, @max_sco, $sco, $node, $subref,
#          $argref, $sco_tree, $new_id, $stop );

#     $sim_sref = $args->{"sim_sref"};
#     $top_sim = $args->{"top_sim"};
#     $sim_wgt = $args->{"sim_wgt"};
#     $sco_mult = $args->{"sco_mult"};
#     $min_grp = $args->{"min_grp"};
#     $tax_cache = $args->{"tax_cache"};
#     $tax_dbh = $args->{"tax_dbh"};

#     # >>>>>>>>>>>>>>>>>>>>> PARSE SIMILARITY STRING <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Split the similarity string, select the top similarities that are no 
#     # more than $top_sim less than the best, and convert to an ID => pct hash,

#     $sim_pcts = [ map { split "=", $_ } split " ", ${ $sim_sref } ];
#     $sim_max = $sim_pcts->[1];

#     for ( $i = 1; $i <= $#{ $sim_pcts }; $i += 2 )
#     {
#         if ( ( $sim_max - $sim_pcts->[$i] ) > $top_sim )
#         {
#             splice @{ $sim_pcts }, $i - 1;
#             last;
#         }
#     }

#     $sim_pcts = { @{ $sim_pcts } };

#     # >>>>>>>>>>>>>>>>>>>>>> PERCENTAGES TO SCORES <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#     # 
#     # Convert percentages to scores that add up to the given read count. This 
#     # is done in two ways:
#     # 
#     # 1. If $sim_wgt is above zero, then percentages are converted to weights 
#     #    that add up to 1.0 as this example,
#     # 
#     #    100, 100, 98, 97, 96.3, 92 -> 0.344, 0.344, 0.115, 0.086, 0.073, 0.038
#     # 
#     #    Then weights are multiplied by the read count ($sco_mult) to give 
#     #    scores. 
#     #
#     # 2. If $sim_wgt is zero, then the returned scores are all the same, but 
#     #    still add up to the read count.

#     $sim_scos = &Taxonomy::Profile::pcts_to_weights( $sim_pcts, $sco_mult, $sim_wgt );

#     # >>>>>>>>>>>>>>>>>>>>>>>> UPDATE SCORE TREE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     # Maintain a temporary tree on which similarities are held. Missing nodes 
#     # are fetched from DBM storage and it will keep growing during a run. It 
#     # has the same structure as the result tree. 

#     $sim_ids = [ keys %{ $sim_scos } ];

#     &Taxonomy::Profile::add_sim_nodes( $tax_dbh, $sim_ids, $tax_cache );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> FIND TOP NODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Calculate score sum and create a subtree that exactly spans all the 
#     # similarities, and return the common ancestor node. This mini-tree is 
#     # used to sum up the scores on below,

#     $all_sum = &List::Util::sum( values %{ $sim_scos } );

#     ( $sco_nid, $sco_tree ) = &Taxonomy::Profile::copy_span_tree( $tax_cache, $sim_ids );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> COPY SCORES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Copy scores to the subtree from above,
    
#     foreach $id ( keys %{ $sco_tree } )
#     {
#         $sco_tree->{ $id }->[SIM_SCORES] = $sim_scos->{ $id } // 0;
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>> FIND UNIQUE CHILDREN <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     # Above $sco_nid is the common ancestor node that spans all similarities
#     # and the whole score ($all_sum) will be assigned to that node if the 
#     # following is not done: if one of the sub-tree starting at $sco_nid has 
#     # a score sum of at least N% ($min_grp) of the scores, then select that 
#     # node; continue towards the leaves until that is no longer true. 

#     if ( defined $min_grp )
#     {
#         # Sum up scores from the leaves upwards through the tree, so that 
#         # the common ancestor node ends up with the total,
        
#         $subref = sub
#         {
#             my ( $tree, $nid ) = @_;
            
#             my ( $pid );
            
#             if ( defined ( $pid = $tree->{ $nid }->[PARENT_ID] ) )
#             {
#                 $tree->{ $pid }->[SIM_SCORES] += $tree->{ $nid }->[SIM_SCORES];
#             }
            
#             return;
#         };
        
#         &Taxonomy::Tree::traverse_tail( $sco_tree, $sco_nid, $subref );

#         # If a single sub-node has nearly all the score (at least $min_grp of the 
#         # total), then assign the score to that one. Keep descending until this is 
#         # no longer true,

#         $stop = 0;

#         while ( not $stop )
#         {
#             $sco_sum = &List::Util::sum( 
#                 map { $sco_tree->{ $_ }->[SIM_SCORES] } @{ $sco_tree->{ $sco_nid }->[CHILD_IDS] } );
            
#             $new_id = undef;

#             foreach $id ( @{ $sco_tree->{ $sco_nid }->[CHILD_IDS] } )
#             {
#                 if ( $sco_tree->{ $id }->[SIM_SCORES] / $sco_sum >= $min_grp )
#                 {
#                     $new_id = $id;
#                     last;
#                 }
#             }

#             if ( defined $new_id ) {
#                 $sco_nid = $new_id;
#             } else {
#                 $stop = 1;
#             }
#         }
#     }

#     # Return the scores to add to the result tree,

#     $sim_scos = { $sco_nid => $all_sum };
    
#     return wantarray ? %{ $sim_scos } : $sim_scos;
# }
# sub sum_tree_columns
# {
#     # Niels Larsen, December 2012. 

#     my ( $tree,      # Hash of nodes
#         ) = @_;

#     # Returns nothing.

#     my ( $colnum, $subref, $argref, $totals );

#     # Define function that checks the maximum value at the current node and 
#     # returns 1 if at least the minimum,

#     $subref = sub
#     {
#         my ( $nodes, $nid, $totals, $colnum ) = @_;
        
#         &Common::Util_C::add_arrays_float( ${ $totals }, $nodes->{ $nid }->[SIM_SCORES], $colnum );
        
#         return;
#     };
    
#     # Submit this callback to the generic filter routine,
    
#     $colnum = &Taxonomy::Tree::count_columns( $tree );
#     $totals = pack "f*", (0) x $colnum;
    
#     $argref = [ \$totals, $colnum ];
    
#     &Taxonomy::Tree::traverse_tail( $tree, $Root_id, $subref, $argref );

#     return [ unpack "f*", $totals ];
# }
