package Protein::SEED::Import;     # -*- perl -*- 

# FIG database specific functions. Just a test.

use strict;
use warnings;

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &load_database
                 &schema
                );

use Common::Util;
use Common::File;
use Common::DB;
use Common::Storage;
use Common::Logs;
use Taxonomy::DB;
use Taxonomy::Nodes;
use Common::Config;


# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub schema
{
    # Niels Larsen, August 2003.

    # Creates a hash where keys are table names and values are lists of 
    # [ field name, datatype, index specification ] where the boolean 
    # decides if an index should be made. 

    # Returns a hash. 

    my $schema = 
    {
        "fig_seq_index" => [
                            [ "id", "varchar(30) not null", "index id_ndx (id)" ],
                            [ "byte_beg", "bigint unsigned not null" ],
                            [ "byte_end", "bigint unsigned not null" ],
                            ],
            
       "fig_annotation" => [
                            [ "db", "varchar(10) not null", "index db_ndx (db)" ],
                            [ "id", "varchar(20) not null", "index id_ndx (id,tax_id)" ],
                            [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,id)" ],
                            [ "tax_ids", "mediumint unsigned not null", "index tax_ids_ndx (tax_ids,id)" ],
                            [ "ec_number", "varchar(20) not null", "index ed_number_ndx (ec_number,id)" ],
                            [ "function", "varchar(255) not null", "index function_ndx (function,id)" ],
                            ],
       
       "fig_synonyms" => [
                          [ "db", "varchar(5) not null", "index db_ndx (db)" ],
                          [ "id", "varchar(20) not null", "index id_ndx (id)" ],
                          [ "fig_id", "varchar(20) not null", "index fig_id_ndx (fig_id)" ],
                          [ "pirnr_id", "varchar(20) not null", "index pirnr_id_ndx (pirnr_id)" ],
                          [ "gi_id", "varchar(20) not null", "index gi_id_ndx (gi_id)" ],
                          [ "sp_id", "varchar(20) not null", "index sp_id_ndx (sp_id)" ],
                          [ "tn_id", "varchar(20) not null", "index tn_id_ndx (tn_id)" ],
                          [ "tr_id", "varchar(20) not null", "index tr_id_ndx (tr_id)" ],
                          ],
    };
    
    return $schema;
}

sub load_database
{
    # Niels Larsen, August 2003.

    # Loads FIG files into a database structure given by the schema
    # function. Database-ready tables are created and then loaded,
    # except the readonly option does not do the loading. This can
    # be used to 

    my ( $readonly,   # If set creates database tables.
         $keep,       # Whether to delete database-ready tables 
         $errors,     # If set prints parsing errors.
         ) = @_;

    # Returns nothing.

    $keep = 1 if not defined $keep;

    my ( $db_name, $source_dir, $install_dir, $schema, $dbh, $db_table,
         $file_handles, $id, $byte_beg, $byte_end, @seq_ids, $org_ids, $org_id, %seq_ids, 
         $func_id, $func, $func_to_id, $func_to_func_id, $func_id_to_func, $seq_ids,
         $id_to_func_id, $db_id, @unmappable, $func_name,
         $count, $i, $j, $dir, $col_ndx, @ids, $ids, $fh, $db, $nodes, 
         @synonyms, $synonym, $line, $org_name, $ec_number,
         $tax_ids, $tax_id, $hits, $node, $id_to_tax_ids, 
         $fig_dir_to_tax_id, $id_to_org_id, $in_fh, $out_fh,
         $func_ids, $func_names, $file,
         ); 

    $db_name = $Common::Config::proj_name;
    $source_dir = $Common::Config::fig_release;
    $install_dir = "$Common::Config::dat_dir/FIG";
    
    # >>>>>>>>>>>>>>>>>>>> ARE SOURCE FILES READABLE <<<<<<<<<<<<<<<<<<<<<<<

    # Each of the get_read_handle calls will die if the file isnt there,

    &echo( qq (   Do we have all source files ... ) );

    foreach $file ( "fig_proteins", "fig_synonyms", "fig_functions", "fig_organisms" )
    {
        $file_handles->{ $file } = &Common::File::get_read_handle( "$source_dir/Global/$file" );
    }

    &echo_green( "yes\n" );

    # >>>>>>>>>>>>>>>>> CREATE INSTALL DIRECTORY IF NEEDED <<<<<<<<<<<<<<<<

    if ( not -d $install_dir )
    {
        &echo( qq (   Creating installation directory ... ) );
        &Common::File::create_dir( $install_dir );
        &echo_green( "done\n" );
    }
    
    # >>>>>>>>>>>>>>>>>>>>> DELETE OLD TAB FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there old database files ... ) );

    $count = 0;

    foreach $file ( "fig_seq_index.tab", "fig_synonyms.tab",
                    "fig_annotation.tab", "unmappable_org.tab" )
    {
        if ( -e "$install_dir/$file" )
        {
            &Common::File::delete_file( "$install_dir/$file" );
            $count++;
        }

        $file_handles->{ $file } = &Common::File::get_append_handle( "$install_dir/$file" );
    }
    
    if ( $count > 0 ) {
        &echo_green( "$count deleted\n" );
    } else {
        &echo_green( "no\n" );
    }

    # >>>>>>>>>>>>>>>>>>> CONNECT TO DATABASE <<<<<<<<<<<<<<<<<<<<<<<<<

    $schema = &Protein::SEED::Import::schema;
    
    $dbh = &Common::DB::connect( $db_name );
    
    if ( not &Common::DB::database_exists( $db_name ) )
    {
        &echo( qq (   Creating new $db_name database ... ) );
        &Common::DB::create_database( $db_name );
        sleep 1;
        
        &echo_green( "done\n" );
    }
    
    # >>>>>>>>>>>>>>>>>>> CREATE SEQUENCE INDEX <<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Creating sequence index ... ) );

    $in_fh = $file_handles->{ "fig_proteins" };
    $out_fh = $file_handles->{ "fig_seq_index.tab" };
                              
    while ( defined ( $line = <$in_fh> ) )
    {
        if ( $line =~ /^>(\S+)/ )
        {
            if ( $byte_beg ) 
            {
                $byte_end = ( tell $in_fh ) - ( length $line ) - 1;
                print $out_fh "$id\t$byte_beg\t$byte_end\n";
            }
            
            $id = $1;
            $byte_beg = ( tell $in_fh ) + 1;

            $seq_ids{ $id } = 1;
        }
    }
    
    $byte_end = ( tell $in_fh ) - 1;
    print $out_fh "$id\t$byte_beg\t$byte_end\n";
    
    &Common::File::close_handle( $out_fh );
    &Common::File::close_handle( $in_fh );

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>> CREATE SYNONYM MAP <<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Creating synonyms map ... ) );

    $in_fh = $file_handles->{ "fig_synonyms" };
    $out_fh = $file_handles->{ "fig_synonyms.tab" };

    $col_ndx = { 
        "fig" => 0,
        "pirnr" => 1,
        "gi" => 2,
        "sp" => 3,
        "tn" => 4,
        "tr" => 5,
    };

    while ( defined ( $line = <$in_fh> ) ) 
    {
        chomp $line;
        
        @synonyms = map { $_ =~ /(.+),\d+$/; $1 } split /[\t;]/, $line;
        @ids = ("") x 6;
        
        foreach $synonym ( @synonyms )
        {
            if ( $synonym =~ /^(fig|pirnr|gi|sp|tn|tr)\|(.+)$/ )
            {
                $ids[ $col_ndx->{ $1 } ] = $2;
            }
            else {
                &error( qq (Unrecognized ID -> $synonym) );
            }
        }
        
        $ids = join "\t", @ids;
        
        foreach $synonym ( @synonyms )
        {
            $synonym =~ /^(fig|pirnr|gi|sp|tn|tr)\|(.+)$/;   # checked above

            print $out_fh "$1\t$2\t$ids\n";
        }
    }
    
    &Common::File::close_handle( $out_fh );
    &Common::File::close_handle( $in_fh );

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>> GET ORGANISM TAXONOMY <<<<<<<<<<<<<<<<<<<<<<<<
    
    # It is used to map organism names to taxonomy ids below,
    
    &echo( qq (   Fetching organism taxonomy ... ) );
    
    $nodes = &Taxonomy::DB::get_subtree( $dbh, 1 );
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>> MAP FIG ORGANISMS <<<<<<<<<<<<<<<<<<<<<<<<<<

    # This section just builds a tax_ids hash where key is organism name
    # and values are [ taxonomy id, number ] where number is the count of
    # taxonomy ids that seem possible, i.e. were used to derive common
    # parent. 

    &echo( qq (   Mapping FIG organisms to taxonomy ... ) );
    
    foreach $dir ( &Common::File::list_directories( "$source_dir/Organisms" ) )
    {
        $org_name = ${ &Common::File::read_file( "$source_dir/Organisms/$dir->{'name'}/GENOME" ) };

        $org_name =~ s/^\s*//s;
        $org_name =~ s/^\s*//s;

        $ids = &Taxonomy::DB::ids_from_name( $dbh, $org_name );
            
        if ( @{ $ids } > 1 )
        {
            $node = &Taxonomy::Nodes::get_nodes_parent( $ids, $nodes );
            $tax_id = &Taxonomy::Nodes::get_id( $node );
        }
        elsif ( @{ $ids } == 1 ) {
            $tax_id = $ids->[0];
        } else {
            $tax_id = "";
        }
        
        $fig_dir_to_tax_id->{ $dir->{"name"} } = [ $tax_id, scalar @{ $ids } ] ;
    }

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>> MAP NON-FIG ORGANISMS <<<<<<<<<<<<<<<<<<<<<

    # This section expands the tax_ids hash with organisms from external 
    # (non-FIG) sources. 

    &echo( qq (   Mapping non-FIG organisms (patience) ... ) );
    
    $in_fh = $file_handles->{ "fig_organisms" };

    $org_id = 0;

    while ( defined ( $line = <$in_fh> ) )
    {
        chomp $line;

        ( $id, $org_name ) = split /\t/, $line;
        
        if ( exists $seq_ids{ $id } )
        {
            if ( not exists $org_ids->{ $org_name } )
            {
                $org_id++;
                $org_ids->{ $org_name } = $org_id;
                
                $ids = &Taxonomy::DB::ids_from_name( $dbh, $org_name );
                
                if ( @{ $ids } > 1 )
                {
                    $node = &Taxonomy::Nodes::get_nodes_parent( $ids, $nodes );
                    $tax_id = &Taxonomy::Nodes::get_id( $node );
                }
                elsif ( @{ $ids } == 1 ) {
                    $tax_id = $ids->[0];
                } else {
                    $tax_id = "";
                }
                
                $tax_ids->{ $org_id } = [ $tax_id, scalar @{ $ids } ];
            }

            $id_to_org_id->{ $id } = $org_ids->{ $org_name };
        }
    }

    &Common::File::close_handle( $in_fh );
    
    $org_ids = {};
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>> WRITE ORGNISM ANNOTATION <<<<<<<<<<<<<<<<<<<<<

    # Only the first four columns. The last (function) column is added
    # in the next section. 

    &echo( qq (   Writing organism annotation ... ) );

    $out_fh = &Common::File::get_write_handle( "$install_dir/annotation.org" );

    while ( ( $id, undef ) = each %seq_ids )
    {
        if ( $id =~ /^fig/ )
        {
            if ( $id =~ /^fig\|(\d+\.\d+)(\.peg.*)$/ )
            {
                $dir = $1;
                $db = "fig";
                $db_id = "$dir$2";

                ( $tax_id, $hits )  = @{ $fig_dir_to_tax_id->{ $dir } };
            }
            else {
                &error( qq (Unrecognized ID -> "$id") );
            }
        }
        elsif ( $org_id = $id_to_org_id->{ $id } )
        {
            ( $tax_id, $hits )  = @{ $tax_ids->{ $org_id } };
            
            if ( $id =~ /^(pirnr|gi|sp|tn|tr)\|(.+)$/ )
            {
                $db = $1;
                $db_id = $2;
            } 
            else {
                &error( qq (Unrecognized ID -> "$id") );
            }
        }
        else
        {
            push @unmappable, "$id\n";

            $id =~ /^(fig|pirnr|gi|sp|tn|tr)\|(.+)$/;
            $db = $1;
            $db_id = $2;
            $tax_id = "";
            $hits = "";
        }

        print $out_fh "$db\t$db_id\t$tax_id\t$hits\n";
    }
                
    &Common::File::close_handle( $out_fh );

    # Lets hope this frees up memory,

    $nodes = {};
    $tax_ids = {};
    $fig_dir_to_tax_id = {};
    $id_to_org_id = {};

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>> WRITE UN-MAPPABLE IDS IF ANY <<<<<<<<<<<<<<<<<<

    if ( @unmappable )
    {
        $count = scalar @unmappable;
        &echo( qq (   Saving organism-unmappable ID\'s ... ) );
        
        $out_fh = $file_handles->{"unmappable_org.tab"};

        print $out_fh @unmappable;

        &Common::File::close_handle( $out_fh );

        @unmappable = ();

        &echo_green( "$count total\n" );
    }        

    # >>>>>>>>>>>>>>>>>>>>>> CREATE FUNCTION MAP <<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Mapping functions (patience) ... ) );
    
    $in_fh = $file_handles->{"fig_functions"};

    $func_id = 0;

    while ( defined ( $line = <$in_fh> ) )
    {
        chomp $line;

        ( $id, $func_name ) = split /\t/, $line;

        if ( exists $seq_ids{ $id } )
        {
            if ( not exists $func_ids->{ $func_name } )
            {
                $func_id++;
                $func_ids->{ $func_name } = $func_id;
                $func_names->{ $func_id } = $func_name;
            }

            $id_to_func_id->{ $id } = $func_ids->{ $func_name };
        }
    }

    &Common::File::close_handle( $in_fh );
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>> WRITE FUNCTION ANNOTATION <<<<<<<<<<<<<<<<<<
    
    &echo( qq (   Writing function annotation ... ) );
    
    $in_fh = &Common::File::get_read_handle( "$install_dir/annotation.org" );
    $out_fh = $file_handles->{"fig_annotation.tab"};

    while ( defined ( $line = <$in_fh> ) )
    {
        chomp $line;

        ( $db, $db_id, $tax_id, $hits ) = split "\t", $line;

        if ( $func_id = $id_to_func_id->{ "$db|$db_id" } )
        {
            $func_name = $func_names->{ $func_id };

            if ( $func_name =~ /((\d+|-)\.(\d+|-)\.(\d+|-)\.(\d+|-))/ ) {
                $ec_number = $1;
            } else {
                $ec_number = "";
            }
        }
        else
        {
            $func_name = "";
            $ec_number = "";
        }

        print $out_fh "$db\t$db_id\t$tax_id\t$hits\t$ec_number\t$func_name\n";
    }        
            
    &Common::File::close_handle( $out_fh );
    &Common::File::close_handle( $in_fh );

    &Common::File::delete_file( "$install_dir/annotation.org" );

    $func_names = {};
    $func_ids = {};
    $id_to_func_id = {};

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>> LOAD DATABASE TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $readonly )
    {
        foreach $db_table ( "fig_seq_index", "fig_annotation", "fig_synonyms" )
        {
            &echo( qq (   Loading "$db_table.tab" ... ) );
        
            if ( &Common::DB::table_exists( $dbh, $db_table ) ) {
                &Common::DB::delete_table( $dbh, $db_table );
            }
            
            &Common::DB::create_table( $dbh, $db_table, $schema->{ $db_table });
            &Common::DB::load_table( $dbh, "$install_dir/$db_table.tab", $db_table );

            if ( not $keep ) {
                &Common::File::delete_file( "$install_dir/$db_table.tab" );
            }
                
            &echo_green( "done\n" );
        }

        &echo( qq (   Indexing function annotation ... ) );
        &Common::DB::request( $dbh, "create fulltext index function_fndx on fig_annotation (function)" );
        &echo_green( "done\n" );

        &echo( qq (   Copying sequences into place ... ) );
        &Common::File::delete_file_if_exists( "$install_dir/fig_proteins.fasta" );
        &Common::File::copy_file( "$source_dir/Global/fig_proteins", "$install_dir/fig_proteins.fasta" );
        &echo_green( "done\n" );
    }
        
    &Common::DB::disconnect( $dbh );

    return;
}

1;

__END__
