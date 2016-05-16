package Expr::Match;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions that compare expression profiles.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use DBI;
use IO::File;
use Math::GSL::Statistics;
use Tie::IxHash; 
use YAML::XS;
use Data::Structure::Util;
use Algorithm::Cluster;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &cluster_dist_table
                 &combine_profiles
                 &create_dist_table
                 &default_match_args
                 &filter_data_hash
                 &format_groups_table
                 &format_groups_yaml
                 &group_dist_table
                 &groups_to_tables
                 &load_data_hash
                 &match_profiles
                 &measure_list_variation
                 &measure_lists_dif
                 &measure_lists_mean_ratio
                 &measure_lists_pcc
                 &process_combine_args
                 &process_match_args
                 &scale_lists_mean
                 &scale_lists_median
                 &scale_data_hash
                 &shave_list_max
                 &sort_groups
                 &table_to_dist
                 &write_groups
                );

use Common::Config;
use Common::Messages;
use Common::File;
use Common::Tables;
use Common::Names;
use Common::DBM;

use Registry::Args;
use Registry::Paths;

use Expr::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our ( $Sum_header_wgt, $Sum_header, $Nam_header );

$Nam_header = "Annotation";
$Sum_header = "Sum";
$Sum_header_wgt = "Sum-wgt";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub cluster_dist_table
{
    # Niels Larsen, June 2011.

    # Receives a distance matrix table (list of [ name1, name2, value ]), runs
    # kmeans, kmedoids or tree clustring on it, and returns the results as a 
    # set of groups. 

    my ( $values, 
         $distab,
         $args,
        ) = @_;

    my ( $i, $row, $name1, $name2, $dist, %index, $dis_mat, $ndx1, $ndx2, 
         $pad_val, $tree, $clu_list, $max_row, $clu_sco, $clu_num, $max_sco, 
         $method, $nam_ndcs, @groups, $group, $clu_ndx, $avgsco, $nam_ndx1,
         $nam_ndx2, @scores, @ndcs, @dists );
    
    $pad_val = $args->padval;
    $clu_sco = $args->clusco;
    $clu_num = $args->clunum;
    $max_sco = $args->maxsco;
    $method = $args->method // "a";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CONVERT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Return "half" a distance matrix, as a list of rows where row n is one 
    # element longer than row n-1. Also return a name hash, where key is name
    # and value is row index,

    ( $nam_ndcs, $dis_mat ) = &Expr::Match::table_to_dist( $distab, $pad_val );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLUSTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Run treecluster from the Cluster 3.0 package,

    $tree = &Algorithm::Cluster::treecluster( "data" => $dis_mat, "method" => $method );

    # Create from the tree a simple list of cluster numbers. The indices of the
    # numbers are the rows in the distance matrix,

    if ( defined $clu_num and not defined $clu_sco ) {
        $clu_list = $tree->cut( $clu_num );
    } else {
        $clu_list = $tree->cutthresh( $max_sco );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE GROUPS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Put names and values into list,

    for ( $clu_ndx = 0; $clu_ndx <= $#{ $clu_list }; $clu_ndx++ )
    {
        $clu_num = $clu_list->[$clu_ndx];

        push @{ $groups[$clu_num]->{"names"} }, $nam_ndcs->{ $clu_ndx };
        push @{ $groups[$clu_num]->{"values"} }, $values->{ $nam_ndcs->{ $clu_ndx } };
    }

    # Add the average distances to other members of the group,

    $nam_ndcs = { reverse %{ $nam_ndcs } };

    foreach $group ( @groups )
    {
        @scores = ();

        foreach $name1 ( @{ $group->{"names"} } )
        {
            @dists = ();
            $nam_ndx1 = $nam_ndcs->{ $name1 };

            foreach $name2 ( @{ $group->{"names"} } )
            {
                next if $name1 eq $name2;

                $nam_ndx2 = $nam_ndcs->{ $name2 };

                if ( $nam_ndx2 > $nam_ndx1 ) {
                    push @dists, $dis_mat->[ $nam_ndx2 ]->[ $nam_ndx1 ];
                } else {
                    push @dists, $dis_mat->[ $nam_ndx1 ]->[ $nam_ndx2 ];
                }
            }

            @dists = sort { $a <=> $b } @dists;

            push @scores, &Math::GSL::Statistics::gsl_stats_median_from_sorted_data( \@dists, 1, scalar @dists );
        }

        # Sort by increasing score values,

        @ndcs = sort{ $scores[ $a ] <=> $scores[ $b ] } 0 .. $#scores;

        $group->{"names"} = [ @{ $group->{"names"} }[ @ndcs ] ];
        $group->{"values"} = [ @{ $group->{"values"} }[ @ndcs ] ];
        $group->{"scores"} = [ @scores[ @ndcs ] ];

        bless $group;
    }

    return wantarray ? @groups : \@groups;
}

sub combine_profiles
{
    # Niels Larsen, June 2011.

    # Creates groups of sets of expression values that tend to correlate,
    # positively or negatively.
    
    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $dathash, @filter, $name, @msgs, $clobber, $ofh,
         @names, $count );

    local $Common::Messages::silent;
    local $Common::Messages::indent_plain;
    local $Common::Messages::indent_info;
    
    bless $args;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = &Expr::Match::default_match_args();
    $conf = &Expr::Match::process_combine_args( $args, $defs );

    $Common::Messages::silent = $args->silent;
    $Common::Messages::indent_plain = 3;
    $Common::Messages::indent_info = 3;
    
    &echo_bold( qq (\nCombine profiles:\n) );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE HASH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First load each profile table into a hash of lists where keys are names, 
    # and values are expression counts. List indices correspond to experiments.
    # We read through all input files to get the values, possibly filtered by 
    # list expressions.
    
    if ( $conf->names1 and @{ $conf->names1 } and
         $conf->names2 and @{ $conf->names2 } )
    {
        push @filter, @{ $conf->names1 };
        push @filter, @{ $conf->names2 };
    }

    &echo("Loading tables ... ");

    $dathash = &Expr::Match::load_data_hash(
        bless {
            "tables" => $conf->infiles,
            "numcol" => $conf->numcol,
            "namcol" => $conf->namcol,
            "filter" => \@filter,
        });

    if ( %{ $dathash } ) 
    {
        @names = keys %{ $dathash };
        $count = @{ $conf->infiles };
        &echo_done( "$count file[s], ". (scalar @names) ." name[s]\n");
    }
    else 
    {
        push @msgs, ["ERROR", qq (No matches with this gene-name constraint -> "). (join "\" or \"", @filter) ."\"" ];
        &echo("\n");
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SCALING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the scale names argument is empty, then all values are scaled so their
    # sums are the same for experiment. If it contains name expressions, then 
    # they are scaled so the sums of the names they match are the same. If the 
    # string __none__ is found among the names, then no scaling is done. 
    
    if ( not grep /__none__/i, @{ $conf->scanam } )
    {
        if ( @{ $conf->scanam } ) {
            &echo("Scaling by name expressions ... "); 
        } else {
            &echo("Scaling by total value sums ... "); 
        }

        $dathash = &Expr::Match::scale_data_hash( $dathash, $conf->scanam );

        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Filter by non-zero values proportion, absolute values, variability and
    # names. But only if the configuration says so,
    
    ( undef, undef, $dathash ) = &Expr::Match::filter_data_hash( $dathash, $conf );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("Writing output table ... ");

    $ofh = &Common::File::get_write_handle( $conf->ofile );
    
    foreach $name ( sort keys %{ $dathash } )
    {
        $ofh->print( "$name\t". ( join "\t", @{ $dathash->{ $name } } ) ."\n" );
    }

    &Common::File::close_handle( $ofh );

    &echo_done("done\n");

    &echo_bold( "Finished\n\n" );

    return;
}

sub create_dist_table
{
    # Niels Larsen, June 2011.

    # Creates a distance matrix table, as a list of [ name1, name2, value ]. The
    # list can be sparse and non-symmetric. This list is input to the grouping 
    # routines. 

    my ( $data,     # Data hash
         $conf,     # Configuation
        ) = @_;

    # Returns Common::Table object.

    my ( $matrix, $minrat, $maxrat, $rat, $sco, $i, $method, $done, $ndx1,
         $ndx2, $scale, $dispct, $names, $values, $name1, $name2, $minsco, 
         $maxsco, $names1, $names2, $routine );

    $names1 = $conf->names1;
    $names2 = $conf->names2;
    $method = $conf->method;
    $minrat = $conf->minrat;
    $maxrat = $conf->maxrat;
    $minsco = $conf->minsco;
    $maxsco = $conf->maxsco;
    $dispct = $conf->dispct;
    $scale = $conf->scale;

    $routine = "Expr::Match::measure_lists_". $method;
    
    $matrix = [];

    for ( $ndx1 = 0; $ndx1 <= $#{ $names1 }; $ndx1++ )
    {
        $name1 = $names1->[$ndx1];

        for ( $ndx2 = 0; $ndx2 <= $#{ $names2 }; $ndx2++ )
        {
            $name2 = $names2->[$ndx2];

            next if $name1 eq $name2;
            next if $done->{ $name1 }->{ $name2 };

            if ( $minrat > 1.0 or defined $maxrat )
            {
                $rat = &Expr::Match::measure_lists_mean_ratio( $data->{ $name1 }, $data->{ $name2 } );
                
                if ( $rat < $minrat or ( defined $maxrat and $rat > $maxrat ) )
                {
                    $done->{ $name1 }->{ $name2 } = 1;
                    $done->{ $name2 }->{ $name1 } = 1;
                    
                    next;
                }
            }
            
            {
                no strict "refs";
                $sco = $routine->( $data->{ $name1 }, $data->{ $name2 }, $scale, $dispct );
            }
            
            if ( $sco >= $minsco and $sco <= $maxsco )
            {
                push @{ $matrix }, [ $name1, $name2, $sco ];
            }
            
            $done->{ $name1 }->{ $name2 } = 1;
            $done->{ $name2 }->{ $name1 } = 1;
        }
    }

    return wantarray ? @{ $matrix } : $matrix;
}

sub default_match_args
{
    my ( $defs );

    $defs = bless {
        "title" => "Profile comparison",
        "author" => &Common::Config::get_signature(),
        "labels" => undef,
        "numcol" => $Sum_header_wgt,
        "namcol" => $Nam_header,
        "names1" => undef,
        "names2" => undef,
        "scanam" => "",
        "suppow" => undef,
        "sorder" => "size",
	"minval" => 2,
        "mindef" => 80,
	"minavg" => 0.0,
	"maxavg" => undef,
	"minvar" => 0.0,
	"maxvar" => undef,
	"minrat" => 1.0,
	"maxrat" => undef,
        "method" => "dif",
	"minsco" => undef,
	"maxsco" => undef,
        "dispct" => 0,
        "scale" => "median",
        "grp_maxsco" => 0.3,
        "grp_maxdif" => 0.2,
        "clu_maxnum" => undef,
        "clu_maxdif" => undef,
        "clu_method" => undef,
	"mingrp" => 2,
	"maxgrp" => undef,
	"table" => undef,
        "yaml" => undef,
	"silent" => 0,
	"clobber" => 0,
    };

    return wantarray ? %{ $defs } : $defs;
}

sub filter_data_hash
{
    # Niels Larsen, June 2011. 

    # Filters the given data hash by proportion of non-zero values, by 
    # absolute values, by variability and by name. All or none of that is 
    # done, that depends on the given configuration. Returned is a list 
    # with three elements: $names1, $names2 and $data. It is assumed all
    # value lists in the hash are equally long.

    my ( $data,    # Data hash
         $conf,    # Configuration
        ) = @_;

    # Returns a list.

    my ( $maxcol, $minavg, $maxavg, $minvar, $maxvar, $name, %names,
         $val, @msgs, $vars, $i, @ndcs, $names, $values, $mindef, $minval, 
         $def, $regexp, @names1, @names2, $string, @all_names, $count,
         $sums );

    @all_names = keys %{ $data };

    # >>>>>>>>>>>>>>>>>>>>>>> FILTER BY SPARSITY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Delete the data lists where less than mindef % have defined values. Those 
    # that remain have undefined values converted to zero. 

    $maxcol = $#{ $data->{ $all_names[0] } };
    
    $mindef = $conf->mindef * ( $maxcol + 1 ) / 100;
    $minval = $conf->minval;

    if ( $mindef > 0 )
    {
        &echo("Skipping sets with < ". $conf->mindef ."% values < $minval ... ");
    
        foreach $name ( keys %{ $data } )
        {
            $def = 0;
            
            for ( $i = 0; $i <= $maxcol; $i++ )
            {
                $val = $data->{ $name }->[$i];
                $def += 1 if defined $val and $val >= $minval;
            }
            
            delete $data->{ $name } if $def < $mindef;
        }

        $count = keys %{ $data };
        &echo_done( "$count kept\n");
    }
                  
    if ( not %{ $data } ) 
    {
        push @msgs, ["ERROR", qq (All gene sets filered away, please relax parameters.) ];
        undef $Common::Messages::indent_plain;
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> FILTER BY VALUE SIZES <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # This removes datasets with values that are uninterestingly low or high,

    $minavg = $conf->minavg;
    $maxavg = $conf->maxavg;

    if ( $minavg > 1 )
    {
        &echo("Skipping sets with means < $minavg ... ");

        foreach $name ( keys %{ $data } )
        {
            $val = &Math::GSL::Statistics::gsl_stats_mean( $data->{ $name }, 1, scalar @{ $data->{ $name } } );
            delete $data->{ $name } if $val < $minavg;
        }

        $count = keys %{ $data };
        &echo_done("$count kept\n");
    }

    if ( defined $maxavg )
    {
        &echo("Skipping sets with means > $maxavg ... ");

        foreach $name ( keys %{ $data } )
        {
            $val = &Math::GSL::Statistics::gsl_stats_mean( $data->{ $name }, 1, scalar @{ $data->{ $name } } );
            delete $data->{ $name } if $val > $maxavg;
        }

        $count = keys %{ $data };
        &echo_done("$count kept\n");
    }
    
    if ( not %{ $data } ) 
    {
        push @msgs, ["ERROR", qq (All gene sets filtered away, please relax parameters.) ];
        undef $Common::Messages::indent_plain;
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> FILTER BY VARIABILITY <<<<<<<<<<<<<<<<<<<<<<<<<

    # This removes datasets where the variability is too high and/or low,

    $minvar = $conf->minvar;
    $maxvar = $conf->maxvar;

    if ( $minvar > 0 )
    {
        &echo("Skipping sets with variability < $minvar ... ");

        foreach $name ( keys %{ $data } )
        {
            if ( &Expr::Match::measure_list_variation( $data->{ $name } ) < $minvar )
            {
                delete $data->{ $name };
            }
        }

        $count = keys %{ $data };
        &echo_done( "$count kept\n");
    }

    if ( defined $maxvar )
    {
        &echo("Skipping sets with variability > $maxvar ... ");

        foreach $name ( keys %{ $data } )
        {
            if ( &Expr::Match::measure_list_variation( $data->{ $name } ) > $maxvar )
            {
                delete $data->{ $name };
            }
        }

        $count = keys %{ $data };
        &echo_done( "$count kept\n");
    }

    if ( not %{ $data } ) 
    {
        push @msgs, ["ERROR", qq (All gene sets filtered away, please relax parameters.) ];
        undef $Common::Messages::indent_plain;
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE NAME LISTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Form regular expressions for gene set 1 and 2 and search the names with 
    # these expressions. Stop with error if either set does not match. 

    @all_names = keys %{ $data };

    if ( @{ $conf->names1 } )
    {
        &echo("Matching names1 names ... ");

        $regexp = "(". (join ")|(", @{ $conf->names1 }) .")";
        @names1 = sort grep /$regexp/io, @all_names;
        
        if ( not @names1 )
        {
            $string = "'". (join "' or '", @{ $conf->names1 }) ."'";
            push @msgs, ["ERROR", qq (No matches with these names1 expressions -> $string) ];
        }

        &echo_done( scalar @names1 ." match[es]\n" );
    }
    else {
        @names1 = @all_names;
    }

    if ( @{ $conf->names2 } )
    {
        &echo("Matching names2 names ... ");

        $regexp = "(". (join ")|(", @{ $conf->names2 }) .")";
        @names2 = sort grep /$regexp/io, @all_names;
        
        if ( not @names2 )
        {
            $string = "'". (join "' or '", @{ $conf->names2 }) ."'";
            push @msgs, ["ERROR", qq (No matches with these names2 expressions -> $string) ];
        }

        &echo_done( scalar @names2 ." match[es]\n" );
    }
    else {
        @names2 = @all_names;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER BY NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $conf->names1 } or @{ $conf->names2 } )
    {
        &echo("Skipping sets with de-selected names ... ");

        %names = map { $_, 1 } ( @names1, @names2 );
    
        foreach $name ( keys %{ $data } )
        {
            if ( not $names{ $name } )
            {
                delete $data->{ $name };
            }
        }
    
        $count = keys %{ $data };
        &echo_done( "$count kept\n");
    }

    if ( @msgs )
    {
        &echo("\n");
        &append_or_exit( \@msgs );
    }
    
    return ( \@names1, \@names2, $data );
}
    
sub format_groups_table
{
    # Niels Larsen, June 2011.

    # Formats a tab-separated table from a given list of group tables. Returns 
    # the table as a text string.

    my ( $list,   # List of groups
        ) = @_;
    
    # Returns string.

    my ( $gnum, $text, $table, $group_name, $name, $i, $c_hdrs, $r_hdrs, $values );

    $gnum = 0;

    $text = "# Group\tGene\t". (join "\t", @{ $list->[0]->col_headers }) ."\n";

    foreach $table ( @{ $list } )
    {
        $group_name = "Group". ++$gnum;

        $r_hdrs = $table->row_headers;
        $values = $table->values;

        for ( $i = 0; $i <= $#{ $values }; $i++ )
        {
            $text .= "$group_name\t$r_hdrs->[$i]\t". ( join "\t", @{ $values->[$i] } ) ."\n";
        }
    }

    return $text;
}

sub format_groups_yaml
{
    # Niels Larsen, June 2011.

    # Creates a YAML formatted string from a given list of groups.

    my ( $list,   # List of group tables
         $conf,   # Arguments hash
        ) = @_;
    
    # Returns string.

    my ( $scale, $struct, $text, @config, $dis_method, $grp_method, @params, $sca_method );

    if ( not @{ $conf->scanam } ) {
        $sca_method = "By total reads";
    } elsif ( grep /__none__/i, @{ $conf->scanam } ) {
        $sca_method = "None";
    } else {
        $sca_method = qq (By gene filter: ). ( join ", ", @{ $conf->scanam } );
    }

    $scale = $conf->scale;

    $dis_method = $conf->method eq "dif" ? "Scaled $scale differences" : "Pearson correlation";
    $grp_method = $conf->clu_method eq "cluster" ? "Tree clustering with Cluster 3.0 package" : "Simple grouping";

    @params = (
        "mindef = ". $conf->mindef,
        "minval = ". $conf->minval,
        "minavg = ". ( $conf->minavg // "any" ),
        "maxavg = ". ( $conf->maxavg // "any" ),
        "minvar = ". ( $conf->minvar // "any" ),
        "maxvar = ". ( $conf->maxvar // "any" ),
        "minrat = ". ( $conf->minrat // "any" ),
        "maxrat = ". ( $conf->maxrat // "any" ),
        "minsco = ". ( $conf->minsco // "any" ),
        "maxsco = ". ( $conf->maxsco // "any" ),
        );

    if ( $conf->clu_method eq "cluster" )
    {
        push @params, "clu_maxnum = ". $conf->clu_maxnum if defined $conf->clu_maxnum;
        push @params, "clu_maxdif = ". $conf->clu_maxdif if defined $conf->clu_maxdif;
    }
    else
    {
        push @params, "scale = ". $conf->scale;
        push @params, "dispct = ". $conf->dispct;
        push @params, "grp_maxsco = ". $conf->grp_maxsco if defined $conf->grp_maxsco;
        push @params, "grp_maxdif = ". $conf->grp_maxdif if defined $conf->grp_maxdif;        
    }
    
    @config = (
        ["Input files used", $conf->infiles ],
        ["Reads scaling", $sca_method ],
        ["Distance method", $dis_method ],
        ["Grouping method", $grp_method ],
        ["Parameters used", \@params ],
        );

    $struct = {
        "type" => "expr_groups",
        "date" => &Common::Util::time_string_to_epoch(),
        "config" => \@config,
        "author" => $conf->author,
        "title" => $conf->title,
        "tables" => $list,
    };

    $text = &YAML::XS::Dump( &Data::Structure::Util::unbless( $struct ) );

    return $text;
}

sub group_dist_table
{
    # Niels Larsen, June 2011. 

    # Forms groups of similar numbers. First the given list of distances
    # (tuples of [ name1, name2, distance ]) is sorted in ascending order.
    # Then groups are formed by simply adding names to groups, so that the 
    # distances keep growing. A name is only added to one group once, but 
    # can be the first in a group as well as member of another. Returned 
    # is a list of groups, each of which is an object with "names", "values"
    # and "scores" fields.

    my ( $dathash,
         $distab,
         $args,
        ) = @_;

    # Returns a list.

    my ( $max_val, $max_dif, $member, %groups, $name1, $name2, $dist, $row,
         @groups, $group, @mbr_names, @mbr_scores );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args )
    {
        $max_val = $args->maxsco;
        $max_dif = $args->maxdif;
    }

    $max_val //= 1;
    $max_dif //= 0.1;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SORTING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sort by distance values in ascending order,

    $distab = [ sort { $a->[2] <=> $b->[2] } @{ $distab } ];

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GROUPING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a group hash,

    foreach $row ( @{ $distab } )
    {
        ( $name1, $name2, $dist ) = @{ $row };

        next if $name1 eq $name2;
        next if $dist > $max_val;

        next if $member->{ $name1 } and $member->{ $name2 };
        
        if ( not $member->{ $name2 } or ( $dist - $member->{ $name2 }->[1] ) <= $max_dif )
        {
            push @{ $groups{ $name1 } }, 
            {
                "name" => $name2,
                "score" => $dist,
            };
            
            $member->{ $name2 } = [ $name1, $dist ];
        }
        elsif ( not $member->{ $name1 } or ( $dist - $member->{ $name1 }->[1] ) <= $max_dif )
        {
            push @{ $groups{ $name2 } }, 
            {
                "name" => $name1,
                "score" => $dist,
            };
            
            $member->{ $name1 } = [ $name2, $dist ];
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE GROUP LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $name1 ( keys %groups )
    {
        @mbr_names = map { $_->{"name"} } @{ $groups{ $name1 } };
        @mbr_scores = map { $_->{"score"} } @{ $groups{ $name1 } };
        
        $group = bless {
            "names" => [ $name1, @mbr_names ],
            "values" => [ map { $dathash->{ $_ } } ( $name1, @mbr_names ) ],
            "scores" => [ 0, @mbr_scores ],
        };
        
        push @groups, &Storable::dclone( $group );
    }

    return wantarray ? @groups : \@groups;
}

sub groups_to_tables
{
    # Niels Larsen, June 2011. 

    # Helper routine for match_profiles that converts group structure to a list 
    # of Common::Table objects, for which we have printing routines. 

    my ( $groups,
         $labels,
        ) = @_;

    # Returns a list.

    my ( $i, $group, $name, @values, $row, @tables, $table, $names, $scores, 
         $values, $ratios, %titles, $title, $method );

    %titles = (
        "pcc" => "PCC",
        "dif" => "Dif",
    );

    $i = 0;

    foreach $group ( @{ $groups } )
    {
        $method = $group->method;
        
        $names = $group->names;
        $scores = $group->scores;
        $values = $group->values;

        if ( not $title = $titles{ $method } ) {
            &error( qq (Wrong looking method -> "$method") );
        }

        @values = ();

        for ( $row = 0; $row <= $#{ $names }; $row++)
        {
            push @values, [ $scores->[$row], @{ $values->[$row] } ];
        }

        $table = &Common::Table::new( 
            \@values, 
            {
                "title" => "Group ". ++$i,
                "col_headers" => [ $title, @{ $labels } ],
                "row_headers" => $names,
            });
        
        push @tables, &Storable::dclone( $table );
    }

    return wantarray ? @tables : \@tables;
}

sub load_data_hash
{
    # Niels Larsen, June 2011.

    # Reads profile tables from files into a hash where keys are names and 
    # values are lists of numbers. The lists do not have the same lengths and
    # undefined values have been converted to zeros. 

    my ( $conf,
         $msgs,
        ) = @_;

    # Returns a hash.

    my ( $files, $i, $rows, $table, $ndcs, $row, $namndx, $numndx, $name, 
         $maxndx, %data, $filter, $regexp, $list, @values, @row_headers );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE HASH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Read tables and all data into a hash of lists, to handle different names
    # easier. The

    $files = $conf->tables;

    if ( @{ $conf->filter } )
    {
        $filter = &Common::Util::uniqify( $conf->filter );
        $regexp = "(". (join ")|(", @{ $filter }) .")";
    }

    for ( $i = 0; $i <= $#{ $files }; $i++ )
    {
        # Read entire table,

        $table = &Common::Table::read_table( $files->[$i] );
        
        # Set indices for names and numbers,

        if ( $conf->namcol =~ /^\d$/ ) {
            $namndx = $conf->namcol - 1;
        } else {
            $namndx = &Common::Table::names_to_indices( [ $conf->namcol ], $table->col_headers )->[0];
        }

        if ( $conf->numcol =~ /^\d$/ ) {
            $numndx = $conf->numcol - 1;
        } else {
            $numndx = &Common::Table::names_to_indices( [ $conf->numcol ], $table->col_headers )->[0];
        }

        # Create hash where keys are names and values are ists of numbers. If 
        # a name expression filter is given, use only the names that match,

        if ( $filter ) 
        {
            foreach $row ( @{ $table->values } )
            {
                $data{ $row->[$namndx] }->[$i] = $row->[$numndx] if $row->[$namndx] =~ /$regexp/io;
            }
        }
        else
        {
            foreach $row ( @{ $table->values } )
            {
                $data{ $row->[$namndx] }->[$i] = $row->[$numndx];
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>> CONVERT UNDEFINED TO ZERO <<<<<<<<<<<<<<<<<<<<<<<<
    
    $maxndx = 0;

    foreach $name ( keys %data )
    {
        $maxndx = &List::Util::max( $maxndx, $#{ $data{ $name } } );
    }

    # Replace undefined values in the lists with 0's and make all lists have 
    # same length,

    foreach $name ( keys %data )
    {
        for ( $i = 0; $i <= $maxndx; $i++ )
        {
            $data{ $name }->[$i] //= 0;
        }
    }

    return wantarray ? %data : \%data;
}

sub match_profiles
{
    # Niels Larsen, June 2011.

    # Creates groups of sets of expression values that tend to correlate,
    # positively or negatively.
    
    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $regexp, $dathash, @filter, $file,
         $count, $name, $var, $filter, @msgs, $names1, $names2,
         $string, $name1, $name2, $groups, $group, $gen_count, $mingrp,
         $maxgrp, $grp_count, $val, $vars, $routine, $distable,
         $clobber, $minrat, $maxrat, $minsco, $maxsco, $rat, $sco, $sums,
         $tables, $ungrouped, $power, @names );

    local $Common::Messages::silent;
    local $Common::Messages::indent_plain;
    local $Common::Messages::indent_info;
    
    bless $args;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = &Expr::Match::default_match_args();
    $conf = &Expr::Match::process_match_args( $args, $defs );

    $Common::Messages::silent = $args->silent;
    $Common::Messages::indent_plain = 3;
    $Common::Messages::indent_info = 3;
    
    &echo_bold( qq (\nMatch profiles:\n) );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE HASH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First load each profile table into a hash of lists where keys are names, 
    # and values are expression counts. List indices correspond to experiments.
    # We read through all input files to get the values, possibly filtered by 
    # list expressions.
    
    if ( @{ $conf->names1 } and @{ $conf->names2 } )
    {
        push @filter, @{ $conf->names1 };
        push @filter, @{ $conf->names2 };
    }

    &echo("Loading tables ... ");

    $dathash = &Expr::Match::load_data_hash(
        bless {
            "tables" => $conf->infiles,
            "numcol" => $conf->numcol,
            "namcol" => $conf->namcol,
            "labels" => $conf->labels,
            "filter" => \@filter,
        });

    if ( %{ $dathash } ) 
    {
        @names = keys %{ $dathash };
        $count = @{ $conf->infiles };
        &echo_done( "$count file[s], ". (scalar @names) ." name[s]\n");
    }
    else 
    {
        push @msgs, ["ERROR", qq (No matches with this gene-name constraint -> "). (join "\" or \"", @filter) ."\"" ];
        &echo("\n");
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SCALING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the scale names argument is empty, then all values are scaled so their
    # sums are the same for experiment. If it contains name expressions, then 
    # they are scaled so the sums of the names they match are the same. If the 
    # string __none__ is found among the names, then no scaling is done. 
    
    if ( not grep /__none__/i, @{ $conf->scanam } )
    {
        if ( @{ $conf->scanam } ) {
            &echo("Scaling by name expressions ... "); 
        } else {
            &echo("Scaling by total value sums ... "); 
        }            

        $dathash = &Expr::Match::scale_data_hash( $dathash, $conf->scanam );

        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Filter by non-zero values proportion, absolute values, variability and
    # names. But only if the configuration says so,

    ( $names1, $names2, $dathash ) = &Expr::Match::filter_data_hash( $dathash, $conf );

    # >>>>>>>>>>>>>>>>>>>>>>> CREATE DISTANCE MATRIX <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a distance table, where rows are names1 and colums names2,

    &echo("Creating distance matrix ... ");

    $distable = &Expr::Match::create_dist_table(
        $dathash,
        bless {
            "names1" => $names1,
            "names2" => $names2,
            "method" => $conf->method,
            "minrat" => $conf->minrat,
            "maxrat" => $conf->maxrat,
            "minsco" => $conf->minsco,
            "maxsco" => $conf->maxsco,
            "dispct" => $conf->dispct,
            "scale" => $conf->scale,
        });

    &echo_done( scalar @{ $distable } . " value[s]\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GROUPING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Compare @names1 against @names2, all against all but not twice. Identical 
    # names are not compared, and names put in one group will not be put into 
    # another. 
    
    if ( $conf->clu_method eq "cluster" )
    {
        &echo("Clustering distance matrix ... ");

        $groups = &Expr::Match::cluster_dist_table(
            $dathash,
            $distable,
            bless {
                "clunum" => $conf->clu_maxnum,
                "clusco" => $conf->clu_maxdif,
                "maxsco" => $conf->maxsco,
                "method" => "a",
                "padval" => 9999,
            });
    }
    else
    {
        &echo("Grouping distance matrix ... ");

        $groups = &Expr::Match::group_dist_table(
            $dathash,
            $distable,
            bless {
                "maxsco" => $conf->grp_maxsco,
                "maxdif" => $conf->grp_maxdif,
            });
    }

    if ( @{ $groups } )
    {
        $count = scalar @{ $groups };

        map { $_->{"method"} = $conf->method } @{ $groups };

        $gen_count = 0;
        map { $gen_count += scalar @{ $_->names } } @{ $groups };

        &echo_done( qq ($count group[s], $gen_count gene[s]\n) );
    }
    else
    {
        &echo_yellow( qq (No groups\n) );
        &echo_info( "Try adjust parameters, see --help\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $groups } )
    {
        # >>>>>>>>>>>>>>>>>>>>>> EXCLUDE BY GROUP SIZE <<<<<<<<<<<<<<<<<<<<<<<<
        
        # This simply filters by size of the output groups,
        
        $mingrp = $conf->mingrp;
        $maxgrp = $conf->maxgrp;

        if ( $mingrp >= 2 )
        {
            &echo("Skipping groups smaller than $mingrp ... ");
            $count = scalar @{ $groups };
            
            @{ $groups } = grep { scalar @{ $_->names } >= $mingrp } @{ $groups };
            
            $count = $count - scalar @{ $groups };
            &echo_done( "$count skipped\n" );
        }
        
        if ( defined $maxgrp )
        {
            &echo("Skipping groups larger than $maxgrp ... ");
            $count = scalar @{ $groups };
            
            @{ $groups } = grep { scalar @{ $_->names } <= $maxgrp } @{ $groups };
            
            $count = $count - scalar @{ $groups };
            &echo_done( "$count skipped\n" );
        }
        
        if ( not @{ $groups } )
        {
            &echo_yellow( qq (   No groups) ); &echo(".\n", 0);
            &echo_info( "Try adjust parameters, see --help\n" );
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GROUP SORTING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $groups } )
    {
        if ( $conf->sorder eq "size" ) {
            &echo("Sorting by groups size ... ");
        } else {
            &echo("Sorting by member distance ... ");
        }
            
        $groups = &Expr::Match::sort_groups( $groups, $conf->sorder );

        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $groups } )
    {
        # Convert from a list of hashes to a Common::Table object. Then group 
        # insertion order is preserved (IxHash) and table rendering routines can 
        # then be used,
        
        $tables = &Expr::Match::groups_to_tables( $groups, $conf->labels );

        # Write tables in tabular or YAML formats,

        &Expr::Match::write_groups(
            $tables,
            bless {
                %{ $conf }, 
                "clobber" => $args->clobber,
                "silent" => $args->silent,
            });
    }

    &echo_bold( "Finished\n\n" );

    return;
}

sub measure_list_variation
{
    # Niels Larsen, June 2011.

    # Returns a number that reflects how much a given list of values vary
    # around their mean. It is calculated as the sum of the absolute differences
    # to the mean, divided by the average absolute value of the given list.
    # It is a relative measure that is independent of values, and it typically
    # ranges from 0.0 (no variation) to 1.5+ (high variation).

    my ( $list,
        ) = @_;

    # Returns a number. 

    my ( $sum, $var );

    $sum = &List::Util::sum( map { abs $_ } @{ $list } ) / scalar @{ $list };

    $var = &Math::GSL::Statistics::gsl_stats_absdev( $list, 1, scalar @{ $list } ) / $sum;

    return $var;
}

sub measure_lists_dif
{
    # Niels Larsen, June 2011. 
    
    # Measures the average difference between two lists of numbers. The lists are 
    # first scaled by their mean or median (default). Then a list of ratios between
    # each data point are created and the average mean is taken of those and then 
    # returned. Optionally the highest $dispct percent differences between the 
    # scaled lists are ignored. Returned values range between 0 (perfect match) 
    # to 1 (very different).     

    my ( $list1,    # List of numbers
         $list2,    # List of numbers
         $scale,    # "mean" or "median" - OPTIONAL, default "median"
         $dispct,   # Discard percentage - OPTIONAL, default none
        ) = @_;

    # Returns a number.

    my ( $i_max, $i, $sum, $ratsum, $val1, $val2, $mval, $routine, $rats, $rat );

    $scale //= "median";
    $dispct //= 0;

    # Scaling, by mean or median,

    { 
        no strict "refs";

        $routine = "Expr::Match::scale_lists_". $scale;
        ( $list1, $list2, $mval ) = $routine->( $list1, $list2 );
    }

    # Create a list of all absolute differences divided by their sum,

    for ( $i = 0; $i <= &List::Util::min( $#{ $list1 }, $#{ $list2 } ); $i++ )
    {
        $val1 = $list1->[$i];
        $val2 = $list2->[$i];
        
        $sum = $val1 + $val2;

        if ( $sum > 0 ) {
            push @{ $rats }, abs ( $val1 - $val2 ) / $sum;
        } else {
            push @{ $rats }, 0;
        }
    }

    # Remove a given percentage of the highest differences if asked for,

    if ( $dispct ) {
        $rats = &Expr::Match::shave_list_max( $rats, $dispct );
    }

    # Get the mean or average ratio,

#    if ( $scale eq "median" ) 
#    {
#        @{ $rats } = sort { $a <=> $b } @{ $rats };
#        $rat = &Math::GSL::Statistics::gsl_stats_median_from_sorted_data( $rats, 1, scalar @{ $rats } );
#    }
#    else {
    $rat = &List::Util::sum( @{ $rats } ) / scalar @{ $rats };
#    }

    return $rat;
}
    
sub measure_lists_mean_ratio
{
    # Niels Larsen, June 2011.

    # Returns the number of times that the highest mean of two given number
    # lists are higher than the lowest mean. If the lowest mean is zero, then 
    # the highest mean is returned. If it is less than zero, then the highest
    # plus the absolute of the lowest is returned.
    
    my ( $list1,
         $list2,
        ) = @_;

    # Returns a number.

    my ( $ratio, $mean1, $mean2, $min, $max );

    $mean1 = &Math::GSL::Statistics::gsl_stats_mean( $list1, 1, scalar @{ $list1 } );
    $mean2 = &Math::GSL::Statistics::gsl_stats_mean( $list2, 1, scalar @{ $list2 } );

    $min = &List::Util::min( $mean1, $mean2 );
    $max = &List::Util::max( $mean1, $mean2 );

    if ( $min == 0 )
    {
        $ratio = $max;
    }
    elsif ( $min < 0 )
    {
        $ratio = $max - $min;
    }
    else {
        $ratio = $max / $min;
    }

    return $ratio;
}

sub measure_lists_pcc
{
    # Niels Larsen, June 2011.

    # Measures the difference between two lists of numbers, using the Pearson 
    # correlation coefficient. This score ranges between -1.0 (opposite, or 
    # negative, correlation) and 1.0 (positive correlation). These values are 
    # then scaled linearly to the range 0 -> 1, where 0 is positive correlation
    # and 1 is negative (most different). The two given lists must have the 
    # same length and may contain no undefined or non-numeric elements.

    my ( $list1,    # List of numbers
         $list2,    # List of numbers
         $scale,    # "mean" or "median" - OPTIONAL, default "median"
        ) = @_;

    # Returns a number.

    my ( $cor, $len1, $len2, $c_list1, $c_list2, $routine );

    $scale //= "median";

    {
        no strict "refs";

        $routine = "Expr::Match::scale_lists_". $scale;
        ( $c_list1, $c_list2, undef ) = $routine->( $list1, $list2 );
    }

    if ( ( $len1 = scalar @{ $c_list1 } ) == ( $len2 = scalar @{ $c_list2 } ) ) 
    {
        $cor = &Math::GSL::Statistics::gsl_stats_correlation( $c_list1, 1, $c_list2, 1, $len1 );
    }
    else {
        &error( qq (First given list length is $len1, but the second has $len2 elements) );
    }

    return ( $cor + 1 ) / 2;
}

sub process_combine_args
{
    # Niels Larsen, June 2011.

    # Checks and expands config file and user arguments for the expr_combine
    # script. Command line arguments override those in the config file.

    my ( $args,      # Arguments
         $defs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $otype, $ofile, $conf, $file, $path, $name, $min, $max, $count,
         @fields, %fields, $value, $key, $lbool, $choices, $string, @list, 
         @numbers, $tuple, $minfld, $maxfld, $lower, $upper, $method, $i, $j,
         $sorder, $check_num_ranges );

    @msgs = ();
    $conf = {};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf->{"infiles"} = $args->infiles if @{ $args->infiles };
    $conf->{"infiles"} //= [];

    if ( not ref $conf->{"infiles"} ) {
        $conf->{"infiles"} = [ $conf->{"infiles"} ];
    }

    if ( @{ $conf->{"infiles"} } )
    {
        $conf->{"infiles"} = &Common::File::full_file_paths( $conf->{"infiles"}, \@msgs );
	$conf->{"infiles"} = &Common::File::check_files( $conf->{"infiles"}, "efr", \@msgs );
    }
    else {
        push @msgs, ["ERROR", qq (No input expression files given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK KEYS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    push @fields, qw ( numcol namcol names1 names2 scanam );
    push @fields, qw ( mindef minval minavg maxavg minvar maxvar );
        
    foreach $key ( @fields )
    {
        if ( defined $args->{ $key } )
        {
            $conf->{ $key } = $args->$key;
        }
        elsif ( not defined $conf->{ $key } )
        {
            $conf->{ $key } = $defs->$key;
        }
        elsif ( ref $conf->{ $key } ) {
            push @msgs, ["ERROR", qq (The field $key is duplicated but should be a simple value -> "$key") ];
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>> GENE LISTS AND SCALE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # These are optional and values cannot be checked until files are read,

    foreach $key ( "names1", "names2", "scanam" )
    {
        if ( $string = $args->$key ) {
            $conf->{ $key } = [ split /\s*,\s*/, $string ];
        } elsif ( not defined $conf->{ $key } ) {
            $conf->{ $key } = [];
        } elsif ( not ref $conf->{ $key } ) {
            $conf->{ $key } = [ $conf->{ $key } ];
        }
    }

    # if ( ( $conf->{"scale"} = $args->scale || $conf->{"scale"} || $defs->scale ) !~ /^mean|median$/ )
    # {
    #     push @msgs, ["ERROR", qq (Wrong looking scaling argument -> "$conf->{'scale'}") ];
    #     push @msgs, ["TIP", qq (Choices are: mean or median) ];
    # }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->ofile )
    {
        &Common::File::check_files( [ $args->ofile ], "!e", \@msgs );
        $conf->{"ofile"} = $args->ofile;

        &append_or_exit( \@msgs );
    }
    else {
        $conf->{"ofile"} = undef;
    }

    # >>>>>>>>>>>>>>>>>>>> CHECK NUMBERS AND SET ROUTINE <<<<<<<<<<<<<<<<<<<<<<

    bless $conf;

    # Minimum value at a given percent of data points,

    &Registry::Args::check_number( $conf->numcol, 1, undef, \@msgs );
    &Registry::Args::check_number( $conf->namcol, 1, undef, \@msgs );

    &Registry::Args::check_number( $conf->minval, 1, undef, \@msgs );
    &Registry::Args::check_number( $conf->mindef, 1, 100, \@msgs );

    &Registry::Args::check_number( $conf->minavg, 0, undef, \@msgs );
    &Registry::Args::check_number( $conf->minvar, 0, undef, \@msgs );

    return wantarray ? %{ $conf } : $conf;
}

sub process_match_args
{
    # Niels Larsen, June 2011.

    # Checks and expands config file and user arguments for the expr_match
    # script. Command line arguments override those in the config file.

    my ( $args,      # Arguments
         $defs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $otype, $ofile, $conf, $file, $path, $name, $min, $max, $count,
         @fields, %fields, $value, $key, $lbool, $choices, $string, @list, 
         @numbers, $tuple, $minfld, $maxfld, $lower, $upper, $method, $i, $j,
         $sorder, $check_num_ranges );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIG FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->config )
    {
	&Common::File::check_files( [ $args->config ], "efr", \@msgs );
        &append_or_exit( \@msgs );
        
        $conf = &Common::Config::read_config_general( $args->config );
        &append_or_exit( \@msgs );
    }
    else {
        $conf = {};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK KEYS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # List allowed fields, and whether they should be lists or not. The user 
    # may duplicate the wrong field by mistake, but Config::General is not 
    # consistent either.

    push @fields, qw ( title author infiles labels sorder );
    push @fields, qw ( numcol namcol names1 names2 scanam suppow );
    push @fields, qw ( mindef minval minavg maxavg minvar maxvar );
    push @fields, qw ( minrat maxrat method minsco maxsco dispct scale );
    push @fields, qw ( grp_maxsco grp_maxdif clu_maxnum clu_maxdif clu_method );
    push @fields, qw ( mingrp maxgrp );
        
    # Check that there are no wrong fields in the config file,

    %fields = map { $_, 1 } @fields;

    foreach $key ( keys %{ $conf } )
    {
        if ( not exists $fields{ $key } )
        {
            push @msgs, ["ERROR", qq (Wrong looking configuration file key -> "$key") ];
        }
    }

    if ( @msgs )
    {
        $choices = join ", ", map { $_ } @fields;
        push @msgs, ["TIP", qq (Choices are: "$choices") ];
        &append_or_exit( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf->{"infiles"} = $args->infiles if @{ $args->infiles };
    $conf->{"infiles"} //= [];

    if ( not ref $conf->{"infiles"} ) {
        $conf->{"infiles"} = [ $conf->{"infiles"} ];
    }

    if ( @{ $conf->{"infiles"} } )
    {
        $conf->{"infiles"} = &Common::File::full_file_paths( $conf->{"infiles"}, \@msgs );
	$conf->{"infiles"} = &Common::File::check_files( $conf->{"infiles"}, "efr", \@msgs );
    }
    else {
        push @msgs, ["ERROR", qq (No input expression files given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT LABELS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Labels are optional, but if given there must be the same number of them
    # as files,

    $key = "labels";

    if ( $string = $args->$key ) {
        $conf->{ $key } = [ split /\s*,\s*/, $string ];
    } elsif ( not defined $conf->{ $key } ) {
        $conf->{ $key } = [ 1 ... scalar @{ $conf->{"infiles"} } ];
    } elsif ( not ref $conf->{ $key } ) {
        $conf->{ $key } = [ $conf->{ $key } ];
    }
    
    if ( @{ $conf->{ $key } } )
    {
        $i = scalar @{ $conf->{ $key } };
        $j = scalar @{ $conf->{"infiles"} };

        if ( $i != $j ) {
            push @msgs, ["ERROR", qq (There are $j profiles, but $i labels) ];
        }
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>> GENE LISTS AND SCALE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # These are optional and values cannot be checked until files are read,

    foreach $key ( "names1", "names2", "scanam" )
    {
        if ( $string = $args->$key ) {
            $conf->{ $key } = [ split /\s*,\s*/, $string ];
        } elsif ( not defined $conf->{ $key } ) {
            $conf->{ $key } = [];
        } elsif ( not ref $conf->{ $key } ) {
            $conf->{ $key } = [ $conf->{ $key } ];
        }
    }

    if ( ( $conf->{"scale"} = $args->scale || $conf->{"scale"} || $defs->scale ) !~ /^mean|median$/ )
    {
        push @msgs, ["ERROR", qq (Wrong looking scaling argument -> "$conf->{'scale'}") ];
        push @msgs, ["TIP", qq (Choices are: mean or median) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $count = 0;

    foreach $otype ( qw ( table yaml ) )
    {
        $ofile = $args->$otype;

        if ( defined $ofile and not $args->clobber ) {
            &Common::File::check_files( [ $ofile ], "!e", \@msgs );
        }

        $conf->{ $otype } = $ofile;
        $count += 1 if defined $ofile;
    }

    if ( $count == 0 ) {
        push @msgs, ["ERROR", qq (Please specify at least one output type) ];
        push @msgs, ["TIP", qq (Choices are: --table, --yaml) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT SORT ORDER <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( ( $conf->{"sorder"} = $args->sorder || $conf->{"sorder"} || $defs->sorder ) !~ /^size|dif$/ )
    {
        push @msgs, ["ERROR", qq (Wrong looking sort order -> "$conf->{'sorder'}") ];
        push @msgs, ["TIP", qq (Choices are: size or dif) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILL IN THE REST <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Fill in command line values that override. The result is a hash where all
    # keys are set and where some or all have values. Then below we check their
    # values,

    @fields = grep { $_ !~ /names|infiles|labels|scanam|minsco|maxsco/ } @fields;
    
    foreach $key ( @fields )
    {
        if ( defined $args->{ $key } )
        {
            $conf->{ $key } = $args->$key;
        }
        elsif ( not defined $conf->{ $key } )
        {
            $conf->{ $key } = $defs->$key;
        }
        elsif ( ref $conf->{ $key } ) {
            push @msgs, ["ERROR", qq (The field $key is duplicated but should be a simple value -> "$key") ];
        }
    }

    bless $conf;

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>> CHECK NUMBERS AND SET ROUTINE <<<<<<<<<<<<<<<<<<<<<<

    # Minimum value at a given percent of data points,

    &Registry::Args::check_number( $conf->minval, 1, undef, \@msgs );
    &Registry::Args::check_number( $conf->mindef, 1, 100, \@msgs );

    # Check resize option,

    if ( defined $conf->suppow ) {
        &Registry::Args::check_number( $conf->suppow, 1, 10, \@msgs );
    }
    
    # Check method and number pairs,

    @numbers = (
        [ "minavg", 1, undef, "maxavg", 1, undef ],
        [ "minvar", 0.0, undef, "maxvar", 0.0, undef ],
        [ "minrat", 1.0, undef, "maxrat", 1.0, undef ],
        [ "mingrp", 1, undef, "maxgrp", 1, undef ],
        );

    $method = $conf->method;

    if ( $method eq "dif" ) 
    {
        push @numbers, [ "minsco", 0.0, 1.0, "maxsco", 0.0, 1.0 ];
        
        ( $min, $max ) = ( 0.0, 0.2 );

        $conf->{"minsco"} = $args->{"minsco"} // $conf->{"minsco"} // $min;
        $conf->{"maxsco"} = $args->{"maxsco"} // $conf->{"maxsco"} // $max;
    }
    elsif ( $method eq "pcc" )
    {
        push @numbers, [ "minsco", -1.0, 1.0, "maxsco", -1.0, 1.0 ];

        ( $min, $max ) = ( 0.95, 1.0 );

        $conf->{"minsco"} = $args->{"minsco"} // $conf->{"minsco"} // $min;
        $conf->{"maxsco"} = $args->{"maxsco"} // $conf->{"maxsco"} // $max;
    }
    else
    {
        push @msgs, ["ERROR", qq (Wrong looking method -> "$method") ];
        push @msgs, ["TIP", qq (Choices are: "dif" or "pcc" (see --help)) ];

        &append_or_exit( \@msgs );
    }

    $conf->{"dispct"} = $args->{"dispct"} // $conf->{"dispct"} // $defs->{"dispct"};
    $conf->{"scale"} = $args->{"scale"} // $conf->{"scale"} // $defs->{"scale"};

    &append_or_exit( \@msgs );

    $check_num_ranges = sub
    {
        foreach $tuple ( @numbers )
        {
            ( $minfld, $lower, $upper ) = @{ $tuple }[0..2];
            $min = $conf->$minfld;
            
            if ( defined $min ) {
                &Registry::Args::check_number( $min, $lower, $upper, \@msgs );
            }
            
            ( $maxfld, $lower, $upper ) = @{ $tuple }[3..5];
            $max = $conf->$maxfld;
            
            if ( defined $max )
            {
                &Registry::Args::check_number( $max, $lower, $upper, \@msgs );
                
                if ( $min > $max ) {
                    push @msgs, [ "ERROR", qq (The $minfld argument is higher than $maxfld: $min > $max) ];
                }
            }
        }
    };

    $check_num_ranges->();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GROUPING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @numbers = ();

    if ( defined $conf->clu_maxnum or defined $conf->clu_maxdif )
    {
        $conf->clu_method("cluster");

        $conf->{"clu_maxnum"} = $args->{"clu_maxnum"} // $conf->{"clu_maxnum"} // 2;
        &Registry::Args::check_number( $conf->clu_maxnum, 2, undef, \@msgs );

        $conf->{"clu_maxdif"} = $args->{"clu_maxdif"} // $conf->{"clu_maxdif"} // $min;

        @numbers = [ "clu_maxdif", 0.0, 1.0, "maxsco", $conf->maxsco, 1.0 ];
    }
    else 
    {
        $conf->clu_method("group");

        push @numbers, [ "grp_maxsco", 0.0, 1.0, "maxsco", $conf->maxsco, 1.0 ];
        push @numbers, [ "grp_maxdif", 0.0, 1.0, "grp_maxsco", $conf->{"grp_maxsco"}, 1.0 ];
        
        $conf->{"grp_maxsco"} = $args->{"grp_maxsco"} // $conf->{"grp_maxsco"} // $defs->grp_maxsco;
        $conf->{"grp_maxdif"} = $args->{"grp_maxdif"} // $conf->{"grp_maxdif"} // $defs->grp_maxsco;
    }

    $check_num_ranges->();

    return wantarray ? %{ $conf } : $conf;
}

sub scale_lists_mean
{
    # Niels Larsen, June 2011.

    # Scales two lists so the means become the same. The list with the lowest
    # mean is scaled up. Returns a list with references to copies of the given
    # lists and their mean.

    my ( $list1,
         $list2,
        ) = @_;
    
    # Returns a list.

    my ( $mean1, $mean2, $ratio );

    $mean1 = &Math::GSL::Statistics::gsl_stats_mean( $list1, 1, scalar @{ $list1 } );
    $mean2 = &Math::GSL::Statistics::gsl_stats_mean( $list2, 1, scalar @{ $list2 } );

    # If the mean of list1 is higher, then scale list2 up, and vice versa. Make
    # copies to avoid changing the given lists,

    if ( $mean1 > $mean2 )
    {
        $ratio = $mean1 / $mean2;

        return ( $list1, [ map { $_ * $ratio } @{ $list2 } ], $mean1 );
    }
    else 
    {
        $ratio = $mean2 / $mean1;

        return ( $list2, [ map { $_ * $ratio } @{ $list1 } ], $mean2 );
    }

    return;
}
    
sub scale_lists_median
{
    # Niels Larsen, June 2011.

    # Scales two lists so their means become the same. Returns a list with 
    # references to copies of the given lists and their mean.

    my ( $list1,
         $list2,
        ) = @_;
    
    # Returns a list.

    my ( $median1, $median2, @list1, @list2, $ratio );

    @list1 = sort { $a <=> $b } @{ $list1 };
    @list2 = sort { $a <=> $b } @{ $list2 };

    $median1 = &Math::GSL::Statistics::gsl_stats_median_from_sorted_data( \@list1, 1, scalar @list1 );
    $median2 = &Math::GSL::Statistics::gsl_stats_median_from_sorted_data( \@list2, 1, scalar @list2 );

    # If the mean of list1 is higher, then scale list2 up, and vice versa. Make
    # copies to avoid changing the given lists,

    if ( $median1 > $median2 )
    {
        $ratio = $median1 / $median2;

        return ( $list1, [ map { $_ * $ratio } @{ $list2 } ], $median1 );
    }
    else 
    {
        $ratio = $median2 / $median1;

        return ( $list2, [ map { $_ * $ratio } @{ $list1 } ], $median2 );
    }

    return;
}
    
sub scale_data_hash
{
    # Niels Larsen, June 2011.

    # Scales the data hash values. If the filter argument argument is empty, 
    # then all values are scaled so their sums are the same for all conditions. 
    # The sum chosen is the average of all sums. If the filter contains name 
    # expressions, then values are scaled so the sums of the names they match 
    # are the same. The input is a hash where names are key and equally long 
    # lists are value. Each index in the lists correspond to an experiment or
    # condition. Returns an updated hash.

    my ( $data,
         $filter,
        ) = @_;

    # Returns a hash.

    my ( @all_names, @names, $regexp, $i, $imax, $name, @sums, $sum, $grand_avg,
         @msgs, $ratio, $string );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CALCULATE AVERAGE SUM <<<<<<<<<<<<<<<<<<<<<<<<<

    @all_names = keys %{ $data };

    if ( defined $filter and ref $filter and @{ $filter } )
    {
        $regexp = "(". (join ")|(", @{ $filter }) .")";
        @names = grep /$regexp/i, @all_names;

        if ( not @names )
        {
            $filter = join ", ", @{ $filter };
            push @msgs, ["ERROR", qq (No matches with this gene-name scaling expression -> "$filter") ];
            &echo("\n");
            &append_or_exit( \@msgs );
        }
    }
    else {
        @names = @all_names;
    }

    $imax = $#{ $data->{ $names[0] } };

    for ( $i = 0; $i <= $imax; $i++ )
    {
        $sum = 0;
        map { $sum += $data->{ $_ }->[$i] } @names;

        push @sums, $sum;
    }

    $grand_avg = &List::Util::sum( @sums ) / scalar @sums;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ADJUST NUMBERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    for ( $i = 0; $i <= $imax; $i++ )
    {
        $ratio = $grand_avg / $sums[$i];
        
        map { $data->{ $_ }->[$i] = int $data->{ $_ }->[$i] * $ratio } @all_names;
    }

    return wantarray ? %{ $data } : $data;
}

sub shave_list_max
{
    # Niels Larsen, June 2011. 

    # Removes the highest n percent of values from a given list.

    my ( $list,
         $dispct,
        ) = @_;

    my ( @ndcs, $pops );

    @ndcs = sort{ $list->[ $a ] <=> $list->[ $b ] } 0 .. $#{ $list };

    $pops = int ( scalar @ndcs * ( $dispct / 100 ) );

    if ( $pops > 0 )
    {
        splice @ndcs, - $pops;
        $list = [ @{ $list }[ sort { $a <=> $b } @ndcs ] ];
    }
    
    return wantarray ? @{ $list } : $list;
}

sub sort_groups
{
    # Niels Larsen, June 2011.

    # Sorts groups by number of members or by closeness of members. As 
    # closeness measure we use the median distance to the others. Returns
    # an updated list.

    my ( $groups,
         $sorder,
        ) = @_;

    # Returns a list.
    
    my ( @ndcs, @values, $group, $median, @scores );

    if ( $sorder eq "size" )
    {
        @values = map { scalar @{ $_->names } } @{ $groups };
        @ndcs = sort{ $values[ $b ] <=> $values[ $a ] } 0 .. $#values;
    }
    elsif ( $sorder eq "dif" )
    {
        foreach $group ( @{ $groups } )
        {
            @scores = sort { $a <=> $b } @{ $group->scores };
            $median = &Math::GSL::Statistics::gsl_stats_median_from_sorted_data( \@scores, 1, scalar @scores );

            push @values, $median;
        }

        @ndcs = sort{ $values[ $a ] <=> $values[ $b ] } 0 .. $#values;
    }
    else {
        &error( qq (Wrong looking sort order -> "$sorder") );
    }
    
    $groups = [ @{ $groups }[ @ndcs ] ];

    return wantarray ? @{ $groups } : $groups;
}

sub table_to_dist
{
    # Niels Larsen, June 2011.

    # Helper routine that converts a table of [ name1, name2, value ] to the
    # kind of distance matrix that the Cluster 3.0 package wants. A two element
    # list is returned: ( index hash, distance matrix ). The index hash has 
    # names as keys and the distance matrix row index of that name as values.

    my ( $distab,
         $padval,
        ) = @_;

    # Returns a list. 
    
    my ( $i, $dismat, $row, $name1, $name2, $value, %index, $ndx1, $ndx2, 
         $maxrow );

    $i = 0;
    $dismat = [];

    foreach $row ( @{ $distab } )
    {
        ( $name1, $name2, $value ) = @{ $row };
        
        $index{ $name1 } = $i++ if not exists $index{ $name1 };
        $index{ $name2 } = $i++ if not exists $index{ $name2 };

        $ndx1 = $index{ $name1 };
        $ndx2 = $index{ $name2 };

        if ( $ndx1 > $ndx2 ) {
            $dismat->[ $ndx1 ]->[ $ndx2 ] = $value;
        } else {
            $dismat->[ $ndx2 ]->[ $ndx1 ] = $value;
        }
    }

    $dismat->[0] = [];
    $maxrow = $#{ $dismat };

    for ( $row = 1; $row <= $maxrow; $row++ )
    {
        $dismat->[ $row ] = [ map { $_ // $padval } @{ $dismat->[$row] }[ 0 .. $row-1 ] ];
    }

    %index = reverse %index;

    return ( \%index, $dismat );
}
    
sub write_groups
{
    # Niels Larsen, June 2011.

    # Writes outputs in YAML or TSV format. Invokes format_groups_$format 
    # routines. Returns nothing.

    my ( $list,    # List of tables
         $conf,
        ) = @_;

    # Returns nothing.
    
    my ( $file, $fh, $clobber, $silent, $format, $text, $name, $routine );

    $clobber = $conf->clobber // 0;
    $silent = $conf->silent // 0;

    foreach $format ( "table", "yaml" )
    {
        if ( defined ( $file = $conf->{ $format } ) )
        {
            if ( not $silent )
            {
                if ( $file ) {
                    $name = &File::Basename::basename( $file );
                    &echo("Writing $format to $name ... ");
                } else {
                    &echo("Writing $format to STDOUT ... "); 
                }
            }

            &Common::File::delete_file_if_exists( $file ) if $file and $clobber;
            
            $fh = &Common::File::get_write_handle( $file );
            
            $routine = "Expr::Match::format_groups_". $format;

            {
                no strict "refs";
                $text = $routine->( $list, $conf );
            }
            
            $fh->print( $text );
            
            &Common::File::close_handle( $fh );

            &echo_done( scalar @{ $list } ." written\n") if not $silent;
        }
    }

    return;
}

1;

__END__

# sub resize_match_hash
# {
#     my ( $data,
#          $power,
#         ) = @_;

#     my ( $name );

#     foreach $name ( keys %{ $data } )
#     {
#         $data->{ $name } = [ map { $_ ** $power } @{ $data->{ $name } } ];
#     }

#     return wantarray ? %{ $data } : $data;
# }
    
# sub resize_groups
# {
#     my ( $groups,
#          $power,
#         ) = @_;

#     my ( $group, $key, $list );

#     foreach $group ( @{ $groups } )
#     {
#         foreach $list ( @{ $group->values } )
#         {
#             $list = [ map { int $_ ** $power } @{ $list } ];
#         }
#     }

#     return wantarray ? %{ $groups } : $groups;
# }

# sub match_profiles_cluster
# {
#     # Niels Larsen, June 2011. 

#     # Forms groups of lists of numbers that satisfy constraints. All names are 
#     # compared against all, but not twice and not identical names. Datasets can
#     # only be part of one group. It is not a real clustering method, as all are
#     # put into the first group even if there is a better fit in another group.
#     # The match_profiles_cluster routine is an attempt at that. Returns a list 
#     # of groups.

#     my ( $data,
#          $conf,
#         ) = @_;

#     # Returns a list.

#     my ( $minrat, $maxrat, $minsco, $maxsco, $name1, $name2, $routine, $rat, $sco,
#          $done, @groups, $group, $method, $rats, $scos, $ndx, $best_ndx,
#          $best_sco, @ungrouped, $gname1, $scale, $dispct );

#     $routine = $conf->routine;
#     $method = $conf->method;
    
#     $minrat = $conf->minrat;
#     $maxrat = $conf->maxrat // 999_999_999;
#     $minsco = $conf->minsco;
#     $maxsco = $conf->maxsco;
#     $scale = $conf->scale;
#     $dispct = $conf->dispct;

#     $done = {};

#     foreach $name1 ( @{ $conf->names1 } )
#     {
#         next if $done->{ $name1 };

#         # Seed a potential new group, but it will only become a group if other
#         # sets match,

#         {
#             no strict "refs";

#             push @groups, bless {
#                 "method" => $method,
#                 "names" => [ $name1 ],
#                 "values" => [ $data->{ $name1 } ],
#                 "ratios" => [ 1.0 ],
#                 "scores" => [ $routine->( $data->{ $name1 }, $data->{ $name1 }, $scale, $dispct ) ],
#             };
#         }

#         foreach $name2 ( @{ $conf->names2 } )
#         {
#             next if $done->{ $name2 } or $name1 eq $name2;

#             # Go through all groups to find best fit with seed dataset,

#             undef $best_ndx;
#             undef $best_sco;

#             for ( $ndx = 0; $ndx <= $#groups; $ndx++ )
#             {
#                 $gname1 = $groups[$ndx]->names->[0];

#                 next if $gname1 eq $name2;

#                 # Skip if ratio out of bounds (keeps cache),

#                 if ( not defined ( $rat = $rats->{ $gname1 }->{ $name2 } ) )
#                 {
#                     $rat = &Expr::Match::measure_lists_mean_ratio( $data->{ $gname1 }, $data->{ $name2 } );
#                     $rats->{ $gname1 }->{ $name2 } = $rat;
#                 }
                
#                 next if $rat < $minrat or $rat > $maxrat;
                
#                 # Skip if score out of bounds (keeps cache),
                
#                 if ( not defined ( $sco = $scos->{ $gname1 }->{ $name2 } ) )
#                 {
#                     no strict "refs";

#                     $sco = $routine->( $data->{ $gname1 }, $data->{ $name2 }, $scale, $dispct );
#                     $scos->{ $gname1 }->{ $name2 } = $sco;
#                 }
                
#                 next if $sco < $minsco or $sco > $maxsco;

#                 # Remember best score and its group index,

#                 if ( not defined $best_sco or $sco < $best_sco )
#                 {
#                     $best_sco = $sco;
#                     $best_ndx = $ndx;
#                 }
#             }

#             if ( defined $best_ndx )
#             {
#                 # Add to group,
                
#                 push @{ $groups[$best_ndx]->names }, $name2;
#                 push @{ $groups[$best_ndx]->values }, $data->{ $name2 };
#                 push @{ $groups[$best_ndx]->ratios }, 1 / $rat;
#                 push @{ $groups[$best_ndx]->scores }, $best_sco;

#                 $done->{ $name2 } = 1;
#             }
#             else {
#                 push @ungrouped, $name2;
#             }
#         }
#     }

#     return ( \@groups, \@ungrouped );
# }

    # # >>>>>>>>>>>>>>>>>>>>>>>>> SORT BY VARIABILITY <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # if ( $conf->sorder eq "var" )
    # {
    #     &echo("Sorting by descending variations ... ");

    #     foreach $name ( keys %{ $data } ) {
    #         $vars->{ $name } = &Expr::Profile::measure_list_variation( $data->{ $name } );
    #     }

    #     @names1 = sort { $vars->{ $b } <=> $vars->{ $a } } @names1;
    #     @names2 = sort { $vars->{ $b } <=> $vars->{ $a } } @names2;
    # }
    # elsif ( $conf->sorder eq "sum" )
    # {
    #     &echo("Sorting by descending sums ... ");

    #     foreach $name ( keys %{ $data } ) {
    #         $sums->{ $name } = &List::Util::sum( @{ $data->{ $name } } );
    #     }

    #     @names1 = sort { $sums->{ $b } <=> $sums->{ $a } } @names1;
    #     @names2 = sort { $sums->{ $b } <=> $sums->{ $a } } @names2;
    # }
    # else {
    #     &error( qq (Wrong looking sort order -> "). $conf->sorder ."\"" );
    # }

    # &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SUPPRESS PEAKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # A lame attempt to reduce high-peak outliers: simply take the square root,
    # or whatever given power, of all values before comparison, and then scale
    # them up again afterwards (may go away),

#    if ( defined ( $power = $conf->suppow ) )
#    {
#        &echo("Down-sizing data by power $power ... ");
#        $dathash = &Expr::Match::resize_match_hash( $dathash, 1.0 / $power );
#        &echo_done("done\n");
#    }
# This option reduces the data by the given power of 10, before comparison is 
# done, and then reverses that reduction when the outputs are made. As a result
# a few large deviances in otherwise quite similar datasets will become less 
# significant. Use with caution, only when there is dirty data and only powers 
# between 1 and 5 or so make sense (decimal powers are okay). 

#        if ( defined ( $power = $conf->suppow ) )
#        {
#            &echo("Up-sizing data by power $power ... ");
#            $groups = &Expr::Match::resize_groups( $groups, $power );
#            &echo_done("done\n");
#        }
        
# suppow

# sub create_dist_matrix
# {
#     # Niels Larsen, June 2011.

#     # Returns a distance matrix table in the form of a Common::Table structure, 
#     # where rows are names1 and columns names2. The table may be sparse: undefined
#     # values are optionallly given a default value. Input is a hash where names 
#     # are key and values are equal-length lists of numbers.

#     my ( $data,     # Data hash
#          $conf,     # Configuation
#         ) = @_;

#     # Returns Common::Table object.

#     my ( $matrix, $minrat, $maxrat, $rat, $sco, $i, $routine, $done, $ndx1,
#          $ndx2, $scale, $dispct, $names, $values, $name1, $name2, $minsco, 
#          $maxsco, $table, $names1, $names2 );

#     $names1 = $conf->names1;
#     $names2 = $conf->names2;
#     $routine = $conf->routine;
#     $minrat = $conf->minrat;
#     $maxrat = $conf->maxrat;
#     $minsco = $conf->minsco;
#     $maxsco = $conf->maxsco;
#     $dispct = $conf->dispct;
#     $scale = $conf->scale;
    
#     $matrix = [];

#     for ( $ndx1 = 0; $ndx1 <= $#{ $names1 }; $ndx1++ )
#     {
#         $name1 = $names1->[$ndx1];

#         for ( $ndx2 = 0; $ndx2 <= $#{ $names2 }; $ndx2++ )
#         {
#             $name2 = $names2->[$ndx2];

#             next if $name1 eq $name2;
#             next if $done->{ $name1 }->{ $name2 };

#             if ( $minrat > 1.0 or defined $maxrat )
#             {
#                 $rat = &Expr::Match::measure_lists_mean_ratio( $data->{ $name1 }, $data->{ $name2 } );
                
#                 if ( $rat < $minrat or ( defined $maxrat and $rat > $maxrat ) )
#                 {
#                     $done->{ $name1 }->{ $name2 } = 1;
#                     $done->{ $name2 }->{ $name1 } = 1;
                    
#                     next;
#                 }
#             }
            
#             {
#                 no strict "refs";
#                 $sco = $routine->( $data->{ $name1 }, $data->{ $name2 }, $scale, $dispct );
#             }
            
#             if ( $sco >= $minsco and $sco <= $maxsco )
#             {
#                 $matrix->[ $ndx1 ]->[ $ndx2 ] = $sco;
#                 $matrix->[ $ndx2 ]->[ $ndx1 ] = $sco;
#             }
            
#             $done->{ $name1 }->{ $name2 } = 1;
#             $done->{ $name2 }->{ $name1 } = 1;
#         }
#     }

#     # Create matrix table, can be sparse,

#     $table = &Common::Table::new(
#         $matrix,
#         {
#             "row_headers" => $names1,
#             "col_headers" => $names2,
#             "pad_string" => $conf->padval,
#         });
    
#     return $table;
# }

# sub measure_lists_difpct_old
# {
#     # Niels Larsen, June 2011. 
    
#     # Measures the average percentage-wise difference between two lists of numbers,
#     # scaled by mean or median (default). The a list of difference-ratios are created.
#     # The optionally this list is sorted and up to $skips of the highest ratios 
#     # discarded. Finially the average mean is taken and the corresponding percentage
#     # returned. 

#     my ( $list1,     # List of numbers 
#          $list2,     # List of numbers
#          $scale,     # Scaling option, either "mean" or "median", OPTIONAL, default "median"
#          $dispct,    # Percent of highest differences to ignore - OPTIONAL, default 0
#         ) = @_;

#     # Returns a number.

#     my ( $routine, $min, $max, $c_list1, $c_list2, $i, $i_max, $pops, $mid_difpct, 
#          @dif_rats );

#     $scale //= "median";
#     $dispct //= 0;

#     # Scale by mean or median,

#     { 
#         no strict "refs";

#         $routine = "Expr::Match::scale_lists_". $scale;
#         ( $c_list1, $c_list2, undef ) = $routine->( $list1, $list2 );
#     }

#     # Create a list of ratios of difference between the scaled versions,

#     $i_max = &List::Util::min( $#{ $c_list1 }, $#{ $c_list2 } );

#     for ( $i = 0; $i <= $i_max; $i++ )
#     {
#         ( $min, $max ) = &Math::GSL::Statistics::gsl_stats_minmax( [ $c_list1->[$i], $c_list2->[$i] ], 1, 2 );
        
#         if ( $max > 0 ) {
#             push @dif_rats, 1.0 - $min / $max;
#         } else {
#             push @dif_rats, 0;
#         }
#     }

#     # This can ignore the highest deviations so that the mean difference is taken
#     # from the rest,

#     if ( $dispct )
#     {
#         @dif_rats = sort { $a <=> $b } @dif_rats;

#         $pops = int ( scalar @dif_rats * ( $dispct / 100 ) );

#         if ( $pops > 0 ) {
#             splice @dif_rats, - $pops;
#         }
#     }

#     # Get the ratio between that average and the overall mean and convert to %,
    
#     $mid_difpct = 100 * &List::Util::sum( @dif_rats ) / scalar @dif_rats;

#     return $mid_difpct;
# }

# sub measure_lists_dif
# {
#     # Niels Larsen, June 2011. 
    
#     # Measures the difference between two lists of numbers. The two number lists are 
#     # first scaled, so their means are the same; then the mean of differences at each
#     # point is calculated; then the ratio between the difference-mean and the value 
#     # mean is returned. The measure ranges between zero (no difference) to 2 or 3 at
#     # most (high difference). 

#     my ( $list1,   # List of numbers 
#          $list2,   # List of numbers 
#          $scale,   # Scaling option, either "mean" or "median", OPTIONAL, default "median"
#         ) = @_;

#     # Returns a number.

#     my ( $routine, $c_list1, $c_list2, $mid_dif, $dif_sum, $i, $i_max, $mid_val, 
#          @difs, $dif, $max );

#     $scale //= "median";

#     # Scale by mean or median,

#     { 
#         no strict "refs";

#         $routine = "Expr::Match::scale_lists_". $scale;
#         ( $c_list1, $c_list2, $mid_val ) = $routine->( $list1, $list2 );
#     }

#     # Calculate the absolute differences between the scaled versions,

#     $i_max = &List::Util::min( $#{ $c_list1 }, $#{ $c_list2 } );

#     for ( $i = 0; $i <= $i_max; $i++ )
#     {
#         $dif = abs ( $c_list1->[$i] - $c_list2->[$i] );
#         push @difs, $dif;
#     }

#     $dif_sum = &List::Util::sum( @difs );

#     # Take the average,
    
#     $mid_dif = $dif_sum / scalar @difs;

#     # Return the ratio between that average and the overall mean,

#     return $mid_dif / $mid_val;
# }

# sub scale_data_table
# {
#     # Niels Larsen, June 2011.

#     # If the filter argument argument is empty, then all values are scaled so 
#     # their sums are the same for all experiments. The sum chosen is the average
#     # of all sums. If the filter contains name expressions, then values are 
#     # scaled so the sums of the names they match are the same. If the string 
#     # __none__ is found among the names, then no scaling is done. The input is
#     # a hash where names are key and equally long lists are value. Each index
#     # in the lists correspond to an experiment or condition. 
    
#     my ( $table,       # Common::Table object
#          $filter,      # Filter list - OPTIONAL
#         ) = @_;

#     # Returns a hash.

#     my ( @names, $regexp, $i, @sums, $sum, $grand_avg, @msgs, $ratio, 
#          $values, $max_col, $max_row, $col, @ndcs );

#     # >>>>>>>>>>>>>>>>>>>>>>>>> CALCULATE AVERAGE SUM <<<<<<<<<<<<<<<<<<<<<<<<<

#     @names = @{ $table->row_headers };

#     $max_col = $table->col_count - 1;
#     $max_row = $table->row_count - 1;

#     if ( defined $filter and ref $filter and @{ $filter } )
#     {
#         $regexp = "(". (join ")|(", @{ $filter }) .")";

#         for ( $i = 0; $i <= $max_row; $i++ )
#         {
#             push @ndcs, $i if $names[$i] =~ /$regexp/i;
#         }
#     }
#     else {
#         @ndcs = ( 0 .. $max_row );
#     }

#     if ( not @ndcs )
#     {
#         push @msgs, ["ERROR", qq (No matches with this gene-name scaling expression -> ")
#                             . (join ", ", @{ $filter }) ."\"" ];
#         &echo("\n");
#         &append_or_exit( \@msgs );
#     }

#     $values = $table->values;

#     for ( $col = 0; $col <= $max_col; $col++ )
#     {
#         $sum = 0;
#         map { $sum += $values->[ $_ ]->[ $col ] } @ndcs;

#         push @sums, $sum;
#     }

#     $grand_avg = &List::Util::sum( @sums ) / scalar @sums;
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ADJUST NUMBERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     for ( $col = 0; $col <= $max_col; $col++ )
#     {
#         $ratio = $grand_avg / $sums[$col];
        
#         map { $values->[ $_ ]->[ $col ] = int $values->[ $_ ]->[ $col ] * $ratio } ( 0 .. $max_row );
#     }

#     return $table;
# }

