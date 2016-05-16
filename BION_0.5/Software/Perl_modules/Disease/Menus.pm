package Disease::Menus;     #  -*- perl -*-

# Menu options and functions. Some are specific to specific to certain
# pages, some are not. They are collected here because different pages
# invoke menus from other pages.

use strict;
use warnings;

use Storable;
use IO::File;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &control_info
                 &data_info                 
                 &selections_info
                 &statistics_info
                  );

use Common::Config;
use Common::Messages;
use Common::Tables;
use Common::File;
use Common::DB;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub control_info
{
    # Niels Larsen, October 2004.

    # Returns the content of the Disease control menu. The viewer gets the
    # index of the menu option chosen; then it sets the request variable 
    # to the corresponding request key value below. 

    # Returns an array. 

    my ( $list, $elem, $right_arrow );

    $right_arrow = &Common::Widgets::arrow_right();

    $list = 
        [{
            "key" => "unchecked",
            "type" => "checkbox",
            "request" => "add_unchecked_column",
            "col" => "X",
            "menu" => "Select, unchecked",
            "tip" => "Checkboxes, unchecked, for disease terms and/or group rows.",
        },{
            "key" => "checked",
            "type" => "checkbox",
            "request" => "add_checked_column",
            "col" => "X",
            "menu" => "Select, checked",
            "tip" => "Checkboxes, chedked, for disease terms and/or group rows.",
        }];
    
    foreach $elem ( @{ $list } )
    {
        $elem->{"tip"} .= qq ( Click this title to delete the column.);
        $elem->{"ids"} = [];
    }

    $list = &Common::Menus::set_items_ids( $list );

    return wantarray ? @{ $list } : $list;
}

sub data_info
{
    # Niels Larsen, October 2004.

    # Returns the content of the Disease data menu. 

    # Returns an array. 

    my ( $list, $elem );

    $list = 
        [{
            "key" => "do_id",
            "type" => "data",
            "request" => "add_data_column",
            "col" => "ID",
            "menu" => "Ontology IDs",
            "tip" => "Internal IDs. Each ID links to a report page.",
        },{
            "key" => "do_icd9",
            "type" => "data",
            "request" => "add_data_column",
            "col" => "ICD9",
            "menu" => "ICD9 codes",
            "tip" => "ICD9 codes. Each code links to a report page.",
        },{
            "key" => "do_statistics_menu",
            "type" => "data",
            "request" => "show_do_statistics_menu",
            "col" => "",
            "menu" => "Statistics menu ->",
            "tip" => "",
        },{
            "key" => "do_selections_menu",
            "type" => "data",
            "request" => "show_do_selections_menu",
            "col" => "",
            "menu" => "Selections menu ->",
            "tip" => "",
        }];
    
    foreach $elem ( @{ $list } )
    {
        $elem->{"tip"} .= " Click this title to delete the column.";
        $elem->{"ids"} = [];
    }

    $list = &Common::Menus::set_items_ids( $list );

    return wantarray ? @{ $list } : $list;
}

sub selections_info
{
    # Niels Larsen, October 2004.

    # Reads the selections from file into a list of hashes 
    # with keys "title" (value is string) and "ids" (value is 
    # array of ids). 

    my ( $sid,    # User id
         ) = @_;

    # Returns an array. 

    my ( $file, $list, $elem );

    if ( not $sid ) {
        &error( qq (User ID is not given) );
    }

    $file = "$Common::Config::ses_dir/$sid/do_selections";

    if ( -r $file )
    {
        $list = &Common::File::eval_file( $file );
    }
    else
    {
        $list = 
            [{
                 "type" => "do",
                 "key" => "do_terms_usum",
                 "col" => "Caol",
                 "menu" => "Limbs anomaly",
                 "tip" => "Congenital anomaly of limbs",
                 "ids" => [ 140000755 ],
            }];

        foreach $elem ( @{ $list } )
        {
            $elem->{"tip"} .= " Click this title to delete the column.";
        }
    }
    
    $list = &Common::Menus::set_items_ids( $list );
    
    return wantarray ? @{ $list } : $list;
}

sub statistics_info
{
    # Niels Larsen, October 2004.

    # Returns a list of hashes that describe all possible disease
    # ontology statistics.

    # Returns an array. 

    my ( $list, $elem );

    $list = 
        [{
            "type" => "statistics",
            "key" => "do_terms_tsum",
            "col" => "Terms",
            "menu" => "Term counts, total",
            "tip" => "Total sums of terms within each category. A given term may occur more than once.",
        },{
            "type" => "statistics",
            "key" => "do_terms_usum",
            "col" => "Terms",
            "menu" => "Term counts, unique",
            "tip" => "Sums of terms within each category. A given term is only counted once.",
        }];

    foreach $elem ( @{ $list } )
    {
        $elem->{"tip"} .= " Click this title to delete the column.";
        $elem->{"ids"} = [];
    }

    $list = &Common::Menus::set_items_ids( $list );

    return wantarray ? @{ $list } : $list;
}

1;

__END__
