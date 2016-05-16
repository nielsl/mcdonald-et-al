package Taxonomy::Import;     #  -*- perl -*-

# Taxonomy import functions. They can parse the NCBI and GreeGenes
# taxonomies and load them into a common database. 

use strict;
use warnings FATAL => qw ( all );

use Storable;
use Devel::Size;
use Cwd qw ( getcwd );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &import_ssu_greengenes
                 &import_ncbi
                 &parse_ncbi
                 &parse_ncbi_names
                 &parse_ncbi_nodes
                 &parse_ncbi_division
                 );

use Common::Config;
use Common::Messages;

use Common::DB;
use Common::Storage;
use Common::Tables;
use Common::File;
use Common::Util;
use Common::OS;
use Common::Logs;
use Common::Import;

use Registry::Register;

use Taxonomy::Nodes;
use Taxonomy::DB;
use Taxonomy::Stats;
use Taxonomy::Schema;

our $id_name_def = "tax_id";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# sub import_greengenes
# {
#     # Niels Larsen, December 2005.

#     # Parses downloaded GreenGenes taxonomy sources in a given directory,
#     # flattens it to a database table and then loads this table.

#     my ( $dbh,        # Database handle
#          $tax_name,   # Directory name like "JGI" or similar
#          $args,    # Command line arguments
#          ) = @_;

#     # Returns an integer or nothing. 

#     my ( $tax_dir, $tab_dir, $release_file, @db_table, $db_table, $id, $node, 
#          $nodes, $errors, $cache_file );
    
#     $tax_dir = "$Common::Config::tax_dir/$tax_name";
#     $tab_dir = "$tax_dir/Database_tables";

#     $release_file = "$tax_dir/Downloads/OTU_outline.txt";
#     $db_file = "$tab_dir/taxonomy.tab";

#     $cache_file = "$tax_dir/taxonomy.cache";

#     # >>>>>>>>>>>>>>>>>>>> IS DATABASE UP TO DATE <<<<<<<<<<<<<<<<<<<<<<<<

#     &echo( qq (   $tax_name: Are there new sources ... ) );
    
#     if ( -e $db_file and &Common::File::is_newer_than( $db_file, $release_file ) )
#     {
#         &echo_green( "no\n" );
#         return unless $args->{"force"};
#     }
#     else {
#         &echo_green( "yes\n" );
#     }

#     # >>>>>>>>>>>>>>>>>>> MAKE NODES SKELETON <<<<<<<<<<<<<<<<<<<<<<<

#     # Create cache if it does not exist, or if it is older than the 
#     # downloaded taxonomy distribution. The cache is used by other 
#     # programs because it is faster than building a complete tree 
#     # from database. 

#     $errors = [];

#     if ( not -e $cache_file or 
#          &Common::File::is_newer_than( $release_file, $cache_file ) )
#     {
#         &echo( qq (   $tax_name: Building tree skeleton ... ) );

#         $nodes = &Taxonomy::Import::parse_greengenes( $release_file );
#         $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes );

#         &Taxonomy::Nodes::set_subtree_ids( $nodes, 1 );
#         &Taxonomy::Nodes::set_depth_tree( $nodes, 1 );

#         &echo_green( "done\n" );

#         &echo( qq (   $tax_name: Saving tree cache ... ) );

#         &Taxonomy::Nodes::delete_label_tree( $nodes, 1, "children_ids" );
#         &Common::File::store_file( $cache_file, $nodes );

#         &echo_green( "done\n" );
#     }
#     else
#     {
#         &echo( qq (   $tax_name: Reading tree cache ... ) );
        
#         $nodes = &Common::File::retrieve_file( $cache_file );
        
#         &echo_green( "done\n" );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> BUILD TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     &echo( qq (   $tax_name: Building database table ... ) );

#     foreach $id ( sort { $a <=> $b } keys %{ $nodes } )
#     {
#         $node = $nodes->{ $id };

#         push @db_table, [ $node->{ $id_name_def }, $node->{"parent_id"} || "", 
#                           $node->{"nmin"}, $node->{"nmax"}, $node->{"depth"},
#                           "", "", ];
#     }

#     undef $nodes;

#     # >>>>>>>>>>>>>>>>>>>>>> SAVE AND LOAD TABLE <<<<<<<<<<<<<<<<<<<<<<<<<

#     if ( not $args->{"readonly"} )
#     {
#         # ---------------- Writing database table to disk,

#         &echo( qq (   $tax_name: Saving database table ... ) );
        
#         &Common::File::delete_file_if_exists( $db_file );

#         &Common::Tables::write_tab_table( $db_file, \@db_table );
#         undef @db_table;
        
#         &echo_green( "done\n" );
        
#         # ---------------- Loading database table,
        
#         &echo( qq (   $tax_name: Loading database table ... ) );

#         $db_table = "tax_nodes";
#         $schema = &Taxonomy::Schema::relational()->{ $db_table };


#         &Common::DB::create_table( $dbh, $db_table, $schema );
#         &Common::DB::load_table( $dbh, $db_file, $db_table );
        
#         &Common::DB::request( $dbh, "create fulltext index name_fndx on $db_table (name)" );
#         &Common::DB::request( $dbh, "create fulltext index name_type_fndx on $db_table (name_type)" );

#         &echo_green( "done\n" );
#     }

#     return scalar @db_table;
# }
    

#                $sub_name = $data_name ."::Import::import_". lc $db_name;
                
#                eval { $count = $sub_name->( $i_dir, $o_dir, $args_c, $msgs ) };

sub import_ncbi
{
    # Niels Larsen, May 2003, October 2006.

    # Unpacks taxdump.tar.gz (downloaded from NCBI), parses and loads the 
    # resulting dump files, saves a single table with all information and 
    # finally loads it into our relational database. TO BE REDONE.
    
    my ( $db,            # Dataset object
         $args,          # Arguments hash
         $msgs,          # Messages list
         ) = @_;

    # Returns an integer or nothing. 

    my ( $proj, $dbh, $db_file, $cache_file, $release_file, $row, $db_table, $count,
         $nodes_file, $division_file, $names_file, $node, $down_dir, 
         $nodes, $divisions, $names, $id, $file, @db_table, $src_dir,
         $tab_dir, $parent_id, $parent_node, @rows, $i, $j, $cur_dir, $tmp_dir,
         $errors, $tax_dir, $data_dir, $stats, $entries, $db_tableO );

    $proj = Registry::Get->project( $db->owner );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<

    
    $entries = [{
        "name" => $db->name,
        "datatype" => $db->datatype,
        "datadir" => $db->datadir,
        "formats" => [ $db->format ],
        "label" => $db->label,
        "title" => $db->title,
        "tiptext" => $db->tiptext,
    }];

    # >>>>>>>>>>>>>>>>>>>>>>>>>> FILE PATHS <<<<<<<<<<<<<<<<<<<<<<<<

    $data_dir = $args->{"dat_dir"};
    $src_dir = $args->{"src_dir"};
    $tab_dir = $args->{"tab_dir"};
    $tmp_dir = $args->{"tmp_dir"};

    $cache_file = $args->{"dat_dir"} ."/taxonomy.cache";
    $db_file = "$tab_dir/taxonomy.tab";
    
    $nodes_file = "$tmp_dir/nodes.dmp";
    $names_file = "$tmp_dir/names.dmp";
    $division_file = "$tmp_dir/division.dmp";
    $release_file = "$src_dir/taxdump.tar.gz";

    # >>>>>>>>>>>>>>>>>> IS DATABASE UP TO DATE <<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there new sources ... ) );
    
    if ( -e $db_file and &Common::File::is_newer_than( $db_file, $release_file ) )
    {
        &echo_green( "no\n" );
        return ( 0, 0 ) unless $args->{"force"};
    }
    else {
        &echo_green( "yes\n" );
    }

    # >>>>>>>>>>>>>>>>>>> MAKE NODES SKELETON <<<<<<<<<<<<<<<<<<<<<<<

    # Create cache if it does not exist, or if it is older than the 
    # downloaded taxonomy distribution. The cache is used by other 
    # programs because it is faster than building a complete tree 
    # from database. 

    $errors = [];

    if ( not -e $cache_file or 
         &Common::File::is_newer_than( $release_file, $cache_file ) )
    {
        # Unpack sources,
             
        &echo( qq (   Unpacking sources ... ) );

        $cur_dir = &Cwd::getcwd();
        chdir $tmp_dir;
        
        &Common::OS::run_command( "tar -xzf $release_file", undef, $errors );

        if ( @{ $errors } ) {
            &error( $errors );
        }

        foreach $file ( $nodes_file, $names_file, $division_file )
        {
            if ( not -r $file ) {
                push @{ $errors }, qq (File is not readable -> "$file");
            }
        }
        
        if ( @{ $errors } ) {
            &error( $errors );
        }
        
        &echo_green( "done\n" );

        chdir $cur_dir;

        # Create and save tree structure,

        &echo( qq (   Building tree skeleton ... ) );

        $nodes = &Taxonomy::Import::parse_ncbi_nodes( $nodes_file, [ "tax_id", "parent_id" ] );
        $nodes = &Taxonomy::Nodes::set_ids_children_all( $nodes );

        &Taxonomy::Nodes::set_subtree_ids( $nodes, 1 );
        &Taxonomy::Nodes::set_depth_tree( $nodes, 1 );

        &echo_green( "done\n" );

        &echo( qq (   Saving tree cache ... ) );

        &Taxonomy::Nodes::delete_label_tree( $nodes, 1, "children_ids" );
        &Common::File::store_file( $cache_file, $nodes );

        &echo_green( "done\n" );
    }
    else
    {
        &echo( qq (   Reading tree cache ... ) );
        
        $nodes = &Common::File::retrieve_file( $cache_file );
        
        &echo_green( "done\n" );
    }
         
    # >>>>>>>>>>>>>>>>>>>>>>> BUILD TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Below we create a memory version of what should be loaded into
    # the database, write it to disk and load it into database. Has 
    # to be done in steps to conserve memory. 

    &echo( qq (   Building database table (patience) ... ) );

    # --------------- Initialize with basic ids,

    foreach $id ( sort { $a <=> $b } keys %{ $nodes } )
    {
        $node = $nodes->{ $id };

        push @db_table, [ $node->{ $id_name_def }, $db->name, 
                          $node->{"parent_id"} || "", 
                          $node->{"nmin"}, $node->{"nmax"},
                          $node->{"depth"} ];
    }

    undef $nodes;

    # --------------- Adding EMBL code and rank,

    $nodes = &Taxonomy::Import::parse_ncbi_nodes( $nodes_file, [ "rank", "embl_code" ] );
    
    foreach $row ( @db_table )
    {
        $id = $row->[0];
        $node = $nodes->{ $id };

        push @{ $row }, $node->{"rank"} || "", $node->{"embl_code"} || "";
    }
    
    undef $nodes;
    
    # ---------------- Add division info, 

    $divisions = &Taxonomy::Import::parse_ncbi_division( $division_file );
    $nodes = &Taxonomy::Import::parse_ncbi_nodes( $nodes_file, [ "parent_id", "div_id", "div_inherits" ] );

    foreach $id ( keys %{ $nodes } )
    {
        $node = $nodes->{ $id };

        if ( $node->{"div_id"} ne "" )
        {
            $node->{"div_code"} = $divisions->{ $node->{"div_id"} }->{"div_code"};
            $node->{"div_name"} = $divisions->{ $node->{"div_id"} }->{"div_name"};
        }
        elsif ( $node->{"div_inherits"} )
        {
            $parent_id = $node->{"parent_id"};
            
            while ( $nodes->{ $parent_id }->{"div_id"} eq "" )
            {
                $parent_id = $nodes->{ $parent_id }->{"parent_id"};
            }
            
            $parent_node = $nodes->{ $parent_id };
            $node->{"div_code"} = $divisions->{ $parent_node->{"div_id"} }->{"div_code"};
            $node->{"div_name"} = $divisions->{ $parent_node->{"div_id"} }->{"div_name"};
        }
        
        delete $node->{"div_id"};
        delete $node->{"div_inherits"};
    }
        
    foreach $row ( @db_table )
    {
        $id = $row->[0];
        $node = $nodes->{ $id };
        
        push @{ $row }, $node->{"div_code"} || "", $node->{"div_name"} || "";
    }        
    
    undef $nodes;
    undef $divisions;

    # --------------- Add genetic code info,
    
    $nodes = &Taxonomy::Import::parse_ncbi_nodes( $nodes_file, 
                                                  [ "parent_id", "gc_id", "gc_inherits",
                                                    "mgc_id", "mgc_inherits" ] );
    foreach $id ( keys %{ $nodes } )
    {
        $node = $nodes->{ $id };
    
        # Add genetic code ID if its not already present and if it inherits
        # from a parent node,
        
        if ( $node->{"gc_id"} eq "" and $node->{"gc_inherits"} )
        {
            $parent_id = $node->{"parent_id"};
            
            while ( $nodes->{ $parent_id }->{"gc_id"} eq "" )
            {
                $parent_id = $nodes->{ $parent_id }->{"parent_id"};
            }
            
            $node->{"gc_id"} = $nodes->{ $parent_id }->{"gc_id"};
        }
        
        delete $node->{"gc_inherits"};
        
        # Add mitochondrial genetic code ID if its not already present 
        # and if it inherits from a parent node,
        
        if ( $node->{"mgc_id"} eq "" and $node->{"mgc_inherits"} )
        {
            $parent_id = $node->{"parent_id"};
            
            while ( $nodes->{ $parent_id }->{"mgc_id"} eq "" )
            {
                $parent_id = $nodes->{ $parent_id }->{"parent_id"};
            }
            
            $node->{"mgc_id"} = $nodes->{ $parent_id }->{"mgc_id"};
        }
        
        delete $node->{"mgc_inherits"};
    }

    foreach $row ( @db_table )
    {
        $id = $row->[0];
        $node = $nodes->{ $id };
        
        push @{ $row }, $node->{"gc_id"} || "", $node->{"mgc_id"} || "";
    }        
    
    undef $nodes;

    # --------------- Add names information,

    $names = &Taxonomy::Import::parse_ncbi_names( $names_file );
    
    $i = 0;

    while ( $i < @db_table )
    {
        $row = &Storable::dclone( $db_table[ $i ] );
        $id = $row->[0];
        
        if ( exists $names->{ $id } ) 
        {
            @rows = ();
            $node = $names->{ $id };

            for ( $j = 0; $j < @{ $node->{"name"} }; $j++ )
            {
                push @rows, [ @{ $row }, $node->{"name"}->[$j] || "", $node->{"name_type"}->[$j] || "" ];
            }

            splice @db_table, $i, 1, @rows;

            $i += (scalar @rows) - 1;
        }
        else {
            &error( qq (No name and type for the ID "$id") );
        }

        $i++;
    }
    
    undef $names;

    &echo_green( "done\n" );

    $count = scalar @db_table;

    # >>>>>>>>>>>>>>>>>>>>>> SAVE AND LOAD TABLE <<<<<<<<<<<<<<<<<<<<<<<<<

    $dbh = &Common::DB::connect( $args->{"database"} );

    if ( not $args->{"readonly"} )
    {
        # ---------------- Writing database table to disk,

        &echo( qq (   Saving database table ... ) );
        
        &Common::File::delete_file_if_exists( $db_file );
        &Common::File::create_dir_if_not_exists( $tab_dir );

        &Common::Tables::write_tab_table( $db_file, \@db_table );

        $count = scalar @db_table;
        undef @db_table;
        
        &echo_green( "done\n" );
        
        # ---------------- Loading database table,
        
        &echo( qq (   Loading database table ... ) );

        $db_table = "tax_nodes";
        $db_tableO = Taxonomy::Schema->get->table( $db_table );

        &Common::DB::delete_table_if_exists( $dbh, $db_table );

        &Common::DB::create_table( $dbh, $db_tableO );
        &Common::DB::load_table( $dbh, $db_file, $db_table );
        
        &Common::DB::request( $dbh, "create fulltext index name_fndx on $db_table (name)" );
        &Common::DB::request( $dbh, "create fulltext index name_type_fndx on $db_table (name_type)" );

        &echo_green( "done\n" );

        # ---------------- Register entries,

        Registry::Register->write_entries_list( $entries, $data_dir );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> NODE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<

    # TODO - improve 

    &echo( qq (   Building node statistics ... ) );

    $nodes = &Taxonomy::DB::build_taxonomy( $dbh, "tax_id,parent_id,nmin,nmax" );
    
    $stats = &Taxonomy::Stats::update_nodes( $dbh, $nodes );
    &Taxonomy::Stats::load_stats( $dbh, $db->name, $db->datatype, $stats );

    $entries = [{
        "coltext" => "ID",
        "title" => "Show IDs",
        "tiptext" => "ID for each organism and taxon - click to get small report.",
        "request" => "add_ids_column",
    },{
        "coltext" => "Orgs",
        "title" => "Node counts",
        "tiptext" => "The number of organisms within a given taxon.",
        "request" => "add_statistics_column",
    }];

    Registry::Register->write_decorations_list( $entries, $data_dir );
    
    &echo_green( "done\n" );

    &Common::DB::disconnect( $dbh );

    return ( $count, 0 );
}

sub parse_ncbi_division
{
    # Niels Larsen, February 2003

    # Reads the division.dmp file from the NCBI taxonomy distribution

    my ( $file,   # Input file
         ) = @_;
    
    # Returns hash
    
    my ( $divs, $line, $id, $code, $name );

    if ( not open FILE, $file ) {
        &error( qq (Could not open "$file") );
    }

    while ( defined ( $line = <FILE> ) )
    {
        $line =~ s/\t\|\n$//o;
        ( $id, $code, $name ) = split /\t\|\t/o, $line;

        $divs->{ $id } =
        {
            "div_id" => $id * 1,
            "div_code" => $code,
            "div_name" => $name,
        };
    }
    
    if ( not close FILE ) {
        &error( qq (Could not open "$file") );
    }
    
    wantarray ? return %{ $divs } : return $divs;
}

sub parse_ncbi_names
{
    # Niels Larsen, February 2003

    # Reads the names.dmp file from the NCBI taxonomy distribution 

    my ( $file,   # Input file
         ) = @_;

    # Returns hash

    my ( $names, $line, $types, $id, $name, $name_type );

    if ( not open FILE, $file ) {
        &error( qq (Could not open "$file") );
    }
    
    while ( defined ( $line = <FILE> ) )
    {
        $line =~ s/\t\|\n$//o;
        ( $id, $name, undef, $name_type ) = split /\t\|\t/o, $line;
        
        $id *= 1;

        $name ||= "";
        $name_type ||= "";

        push @{ $names->{ $id }->{"name"} }, $name;
        push @{ $names->{ $id }->{"name_type"} }, $name_type;
    }
    
    if ( not close FILE ) {
        &error( qq (Could not open "$file") );
    }

    wantarray ? return %{ $names } : return $names;
}

sub parse_ncbi_nodes
{
    # Niels Larsen, February 2003
    
    # Parses the nodes.dmp file and sets a number of keys .. explain

    my ( $file,      # Input file name
         $fields,    # Output hash from parse_names_file
         ) = @_;

    # Returns hash

    my ( $field, $line, $nodes, $dict, @line, @errors, $id, $value );

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }

    $dict = {
        $id_name_def => 0,
        "parent_id" => 1,
        "rank" => 2,
        "embl_code" => 3,
        "div_id" => 4,
        "div_inherits" => 5,
        "gc_id" => 6,
        "gc_inherits" => 7,
        "mgc_id" => 8,
        "mgc_inherits" => 9,
        "gb_hidden" => 10,
        "no_seqs" => 11,
        "comments" => 12,
    };

    if ( $fields and @{ $fields } )
    {
        foreach $field ( @{ $fields } )
        {
            if ( not exists $dict->{ $field } ) {
                push @errors, qq (The field "$field" is not recognized.\n);
            }
        }

        if ( @errors ) {
            &error( \@errors );
        }
    }
    else
    {
        $fields = [ $id_name_def, "parent_id" ];
    }

    while ( defined ( $line = <FILE> ) )
    {
        $line =~ s/\t\|\n$//o;
        @line = split /\t\|\t/, $line;

        $id = $line[ $dict->{ $id_name_def } ];
        
        foreach $field ( @{ $fields } )
        {
            $value = $line[ $dict->{ $field } ];

            if ( $field eq $id_name_def or $field eq "parent_id" )
            {
                $value *= 1;
            }
            elsif ( $field eq "gc_id" or $field eq "mgc_id" or $field eq "no_seqs" )
            {
                if ( defined $value ) { $value *= 1 } else { $value = "" };
            }

            $nodes->{ $id }->{ $field } = defined $value ? $value : "";
        }
    }
    
    if ( not close FILE ) {
        &error( qq (Could not open "$file") );
    }

    wantarray ? %{ $nodes } : return $nodes;
}

1;

__END__
