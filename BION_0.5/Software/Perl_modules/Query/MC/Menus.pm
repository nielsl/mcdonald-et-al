package Query::MC::Menus;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Generates different types of menu structures, and has routines to access
# and manipulate them. Object module. Inherits from Common::Menus.
#
# downloads_menu
# query_menu
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use IO::File;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Users;

use Registry::Get;
use Expr::DB;

use base qw ( Common::Menus Common::Option );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub downloads_menu
{
    # Niels Larsen, July 2009.

    # Creates a menu structure for the download data menu.

    my ( $class,
         $mir_name,
         ) = @_;
    
    # Returns a Registry menu object.

    my ( $source, @opts, $opt, $menu );

    $source = $mir_name;
    $source =~ s|[\&\;\(\)\[\]\{\}\/\\]|_|g;
    $source .= ".csv" if $source !~ /\.csv$/i;

    @opts = ({
        "name" => "download_data",
        "value" => 0,
        "title" => "Download data", 
        "description" => qq (Chooses type of download data.),
        "datatype" => "boolean",
        "choices" => [{
            "name" => "visible_table",
            "title" => "browser table"
        },{
            "name" => "all_table",
            "title" => "whole table"
        }],
    },{
        "name" => "download_format",
        "title" => "Download format",
        "value" => "CSV text",
        "description" => qq (Comma-separated format is currently the only choice.),
        "datatype" => "text",
        "selectable" => 0,
    },{
        "name" => "download_file",
        "title" => "File name",
        "value" => $source,
        "description" => qq (This is our suggested name for the file that will come to your machine.)
                       . qq ( This name may be changed here, and there will be another chance when)
                       . qq ( the download popup window appears.),
        "datatype" => "text",
        "width" => 20,
        "maxlength" => 50,
    });

    $menu = Registry::Get->_objectify( \@opts, 1);

    foreach $opt ( $menu->options )
    {
        $opt->visible(1);
        $opt->selectable(1) if not defined $opt->selectable;
    }

    return $menu;
}

sub query_menu
{
    # Niels Larsen, July 2009.

    # Creates a menu of form data for MiRConnect's query page. Returns a menu
    # object.

    my ( $dataset,
         $tuples,
        ) = @_;

    # Returns menu object.

    my ( $db_dir, $dbh, @opts, $opt, $menu, $ms_list, $mf_list, $ms_count,
         $mf_count, $i, $method, %params, $width, $textlen, $dpcc, $desc );

    $dbh = &Common::DB::connect( $dataset );

    %params = map { $_->[0], $_->[1] } @{ $tuples };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE FORM MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ms_list = &Expr::DB::mc_mirnas( $dbh, {
        "method" => $params{"method"},
        "type" => "single",
    });

    $mf_list = &Expr::DB::mc_mirnas( $dbh, {
        "method" => $params{"method"},
        "type" => "family",
    });

    if ( scalar @{ $mf_list } == 1 ) {
        $mf_list->[0]->{"title"} = "No family data";
    }

    $dpcc = &Common::DB::table_exists( $dbh, "dpcc_method" );

    &Common::DB::disconnect( $dbh );

    $ms_count = scalar @{ $ms_list } - 1;

    $width = 40;
    $textlen = 1000;

    # Singles always there, 

    @opts = ({
        "name" => "mirna_single",
        "title" => "Select individual miRNA &raquo;", 
        "description" => qq (Selects a single miRNA, out of $ms_count total. Selections here override family selections.),
        "datatype" => "boolean",
        "choices" => $ms_list,
        "value" => $ms_list->[1]->{"name"},
    });

    # Families sometimes there,

    $mf_count = scalar @{ $mf_list } - 1;

    if ( $mf_count == 0 ) {
        $desc = qq (Selects a miRNA family, but there are none for this dataset.);
        $width = 40;
    } else {
        $desc = qq (
Selects a miRNA family, out of $mf_count. Family member counts are given in parantheses. 
Single miRNA selections override selections here - but single miRNA selection can be set
to empty above.);
        $width = 40;
    };

    push @opts,
    {
        "name" => "mirna_family",
        "title" => "- or miRNA family &raquo;", 
        "description" => $desc,
        "datatype" => "boolean",
        "choices" => $mf_list,
        "width" => $width,
    };

    # Method: sPCC always there, dPCC sometimes,

    push @opts,
    {
        "name" => "method",
        "title" => "Analysis Method  &raquo;", 
        "description" => qq (Selects the analysis method used.),
        "datatype" => "boolean",
        "choices" => [{
            "name" => "spcc",
            "title" => "sPCC",
        }],
    };

    if ( $dpcc )
    {
        push @{ $opts[-1]->{"choices"} },
        {
            "name" => "dpcc",        
            "title" => "dPCC",
        };
    }

    # Target types,
    
    push @opts,
    {
        "name" => "target",
        "title" => "Target Types &raquo;", 
        "description" => qq (Selects target types, known or predicted.),
        "datatype" => "boolean",
        "choices" => [{
            "name" => "cor_val",
            "title" => "Known mRNA genes",
        }],
    };

    if ( $dataset =~ /_(q|l)$/ )
    {
        push @{ $opts[-1]->{"choices"} },
        {
            "name" => "cons_val",
            "title" => "Known mRNAs predicted by TargetScan",
        },{
            "name" => "ts_cons",
            "title" => "Predicted (TargetScan)",
        };
    }

    # Options always present,

    push @opts,
    {
        "name" => "correlation",
        "title" => "Correlation Type &raquo;",
        "description" => qq (Shows positive or negative correlation numbers at the top of tables, i.e. a sort option.),
        "datatype" => "boolean",
        "choices" => [{
            "name" => "positive",
            "title" => "Positive values",
        },{
            "name" => "negative",
            "title" => "Negative values",
        }],
    },{
        "name" => "maxtablen",
        "title" => "Maximum Table Length &raquo;",
        "description" => qq (Maximum length of the table to be shown.),
        "datatype" => "integer",
    },{
        "name" => "mirna_names",
        "title" => "miRNA Gene IDs &raquo;", 
        "description" => qq (One or more miRNA names from the lists above, separated by commas, spaces,)
                        .qq ( semicolons or newlines. These names are disregarded if single miRNAs or)
                        .qq ( families are selected in the menus above.),
        "datatype" => "text",
        "width" => $width,
        "maxlength" => $textlen,
    },{
        "name" => "genid_names",
        "title" => "mRNA Gene IDs &raquo;",
        "description" => qq (One or more mRNA gene ids, separated by commas, spaces, semicolons or)
                        .qq ( newlines. The ids pasted should be from the human genome, as annotated)
                        .qq ( by the HUGO project.),
        "datatype" => "text",
        "width" => $width,
        "maxlength" => $textlen,
    },{
        "name" => "annot_filter",
        "title" => "Annotation Words &raquo;",
        "description" => qq (Words that must match mRNA gene annotation strings from HUGO. Single words)
                        .qq ( should work, as well as combinations and negations. The rules are listed on the help page.),
        "datatype" => "text",
        "width" => $width,
        "maxlength" => $textlen,
    };

    # Fill in submitted values,

    for ( $i = 0; $i <= $#opts; $i++ )
    {
        $opts[$i]->{"name"} = $tuples->[$i]->[0] // "";
        $opts[$i]->{"value"} = $tuples->[$i]->[1] // "";
    }

    # L-dataset hack,

    if ( $dataset =~ /_l$/ )
    {
        pop @{ $opts[3]->{"choices"} };
        pop @{ $opts[3]->{"choices"} };
        
        $opts[3]->{"value"} = "cor_val";
    }

    $menu = Registry::Get->_objectify( \@opts, 1);

    foreach $opt ( $menu->options )
    {
        $opt->visible(1);
        
        if ( defined $opt->choices )
        {
            #if ( scalar @{ $opt->choices->options } == 1 ) {
            #    $opt->selectable( 0 );
            #} else {
                $opt->selectable( 1 );
            #}
        }
        elsif ( not defined $opt->selectable ) {
            $opt->selectable(1);
        }
    }

    return $menu;
}

1;

__END__
