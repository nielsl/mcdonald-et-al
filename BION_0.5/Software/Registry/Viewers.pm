package Software::Registry::Viewers;            # -*- perl -*-

# A list of all viewers that the system knows. Viewers are methods sort
# of, we will see later if they should be pooled.

use strict;
use warnings FATAL => qw ( all );

my @descriptions =
    ({
        "name" => "orgs_viewer",
        "title" => "Organism Viewer",
        "inputs" => [
            {
                "types" => [ "orgs_taxa" ],
                "formats" => [ "ncbi_tax" ],
            }],
     },{
         "name" => "funcs_viewer",
         "title" => "Function Viewer",
         "inputs" => [
             {
                 "types" => [ "go_func" ],
                 "formats" => [ "obo" ],
             }],
     },{
         "name" => "table_viewer",
         "title" => "Table Viewer",
         "inputs" => [
             {
                 "types" => [ "expr_mirconnect" ],
                 "formats" => [ "tab_table", "db_table" ],
             }],
     },{
         "name" => "array_viewer",
         "title" => "Array Viewer",
         "params" => {
             "name" => "array_viewer_params",
             "window_height" => 500,
             "window_width" => 600,
             "values" => [
                 [ "ali_img_width", 800 ],
                 [ "ali_img_height", 500 ],
                 [ "ali_zoom_pct", 100 ],
                 [ "ali_with_border", 0 ],
                 [ "ali_with_sids", 1 ],
                 [ "ali_with_nums", 1 ],
                 [ "ali_with_col_collapse", 1 ],
                 [ "ali_with_row_collapse", 0 ],
                 ],
         },
         "inputs" => [
             {
                 "types" => [ "rna_ali", "dna_ali", "prot_ali" ],
                 "formats" => [ "pdl" ],
             }],
     });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    return wantarray ? @descriptions : \@descriptions ;
}    
    
1;

__END__
