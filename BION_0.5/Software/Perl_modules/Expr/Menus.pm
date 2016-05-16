package Expr::Menus;     #  -*- perl -*-

# Menu options and functions that are specific to expression data.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &expr_selections_items
                  );

use Expr::DB;

use Common::Config;
use Common::Messages;
use Common::File;
use Common::DB;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub expr_selections_items
{
    # Niels Larsen, April 2004.

    # Restores the currently selected expression experiment titles,
    # previously saved under the user's directory. If this file does
    # not exist then a default selection is saved and loaded. 

    my ( $sid,         # Session ID
         ) = @_;

    # Returns a hash. 

    my ( $file, $dbh, $items, $item, $i );

    $file = "$Common::Config::ses_dir/$sid/expr_selections";

    if ( -r $file )
    {
        $items = &Common::File::eval_file( $file );
    }
    else
    {
        $dbh = &Common::DB::connect();

        $items = &Expr::DB::get_exp_titles( $dbh, [ 1, 3, 7, 11, 15 ] );

        &Common::DB::disconnect( $dbh );

        $i = 1;

        foreach $item ( @{ $items } )
        {
            $item = 
            {
                "type" => "expression",
                "key" => $item->[0],
                "col" => $i,
                "text" => $item->[1],
                "tip" => "\"$item->[1]\". Click this title to delete the column.",
                "request" => "add_expr_column",
                "ids" => [],
            };
            
            $i++;
        }

        &Common::File::dump_file( $file, $items );
    }

    unshift @{ $items },
    {
        "type" => "",
        "key" => "",
        "request" => "",
        "col" => "",
        "text" => "Expression Menu",
        "tip" => "",
        "class" => "grey_menu",
    };

    $items = &Common::Menus::set_items_ids( $items );

    return wantarray ? @{ $items } : $items;
}

1;

__END__

