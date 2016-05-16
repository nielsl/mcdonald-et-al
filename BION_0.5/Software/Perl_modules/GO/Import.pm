package GO::Import;     #  -*- perl -*-

# Gene Ontology import functions. 
#
# TODO
#

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use DBI;
use IO::File;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &load_all
                 &load_go
                 &load_ext
                 &load_genes
                 &parse_defs
                 &parse_external
                 &parse_genes_line
                 &parse_ontology
                 &parse_synonyms
                 &print_edges_table
                 &get_all_parents

                 &log_errors
                 &create_lock
                 &delete_lock
                 &is_locked
                  );

use Registry::Schema;
use Registry::Get;

use Common::Config;
use Common::DB;
use Common::Storage;
use Common::Messages;
use Common::Tables;
use Common::File;
use Common::Util;
use Common::Download;
use Common::Logs;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub import_go
{
    # Niels Larsen, June 2003.

    # Loads a set of GO files into a database. First the database tables are
    # initialized, if they have not been. Then each release file is parsed 
    # and saved into database-ready temporary files which are then loaded -
    # unless the "readonly" flag is given. 
    
    my ( $proj,
         $db,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    &GO::Import::load_ontology( $proj, $db, $args, $msgs );
    &GO::Import::load_ext( $proj, $db, $args, $msgs );
    &GO::Import::load_genes( $proj, $db, $args, $msgs );

    return;
}

sub load_ontology
{
    # Niels Larsen, January 2004.

    # Loads the main GO files into a database.

    my ( $proj,
         $db,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $ont_dir, $tab_dir, @files, $tab_time, $src_time, $file, $tables,
         $db_name, $dbh, $array, @table, $prefix, $ref, $elem, $count, $edges,
         $edge, $table, $schema, $sql, $defs, $ont_ids, $id, @defs_table, 
         $maps, $map, $int_nodes, $parent, $gen_dir, %db_tables, $schema_name,
         $syn_dir, $tableO );

    # >>>>>>>>>>>>>>>>> CHECKS AND INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<

    $ont_dir = $args->src_dir ."/Ontologies";
    $syn_dir = $args->src_dir ."/Synonyms";
    $tab_dir = $args->tab_dir;
    $db_name = $db->name;

    $schema_name = Registry::Get->type( $db->datatype )->schema;

    $schema = Registry::Schema->get( $schema_name );
    $schema->table_menu->match_options_expr( '$_->name !~ /^func_ext|func_genes|func_stats/' );

    if ( not -d $ont_dir ) {
        &error( "No GO ontology directory found", "MISSING DIRECTORY" );
    } elsif ( not grep { $_->{"name"} =~ /\.ontology$/ } &Common::Storage::list_files( $ont_dir ) ) {
        &error( "No GO source files found", "MISSING SOURCE FILES" );
    }
    
    &Common::File::create_dir_if_not_exists( $tab_dir );

    if ( not &Common::DB::database_exists( $db_name ) )
    {
        &echo( qq (   Creating new database ... ) );
        
        &Common::DB::create_database( $db_name );
        sleep 1;
        
        &echo_green( "done\n" );
    }
    
    $dbh = &Common::DB::connect( $db_name );

    # >>>>>>>>>>>>>>>>>> CHECK FILE MODIFICATION TIMES <<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there new GO downloads ... ) );

    $tab_time = &Common::File::get_newest_file_epoch( $tab_dir, "func_ext|func_genes", 0 );
    $src_time = &Common::File::get_newest_file_epoch( $ont_dir );
    
    if ( $tab_time < $src_time ) {
        &echo_green( "yes\n" );
    } else {
        &echo_green( "no\n" );
    }
    
    # >>>>>>>>>>>>>>>>> PARSE AND CREATE DATABASE TABLES <<<<<<<<<<<<<<<<<

    # -------------- delete old database tables,
        
    &echo( qq (   Are there old GO .tab files ... ) );
        
    if ( @files = grep { $_->{"name"} !~ /func_ext|func_genes|func_stats/ } &Common::Storage::list_files( $tab_dir ) )
    {
        $count = 0;
        
        foreach $file ( @files )
        {
            &Common::File::delete_file( $file->{"path"} );
            $count++;
        }
        
        &echo_green( "$count deleted\n" );
    }
    else {
        &echo_green( "no\n" );
    }
        
    # -------------- parse definitions file,
    
    &echo( qq (   Creating GO definitions .tab file ... ) );
    
    $array = &GO::Import::parse_defs( "$ont_dir/GO.defs" );
    @defs_table = ();
    
    # ---------- write definitions database table,
        
    $defs = { map { $_->{"id"}, $_ } @{ $array } };
        
    foreach $id ( keys %{ $defs } )
    {
        $elem = $defs->{ $id };
        push @defs_table, [ $elem->{"id"}, $elem->{"name"}, $elem->{"deftext"}, $elem->{"comment"} ];
    }
    
    foreach $elem ( @{ $array } )
    {
        foreach $ref ( @{ $elem->{"refs"} } ) {
            push @table, [ $elem->{"id"}, $ref->[0], $ref->[1] ];
        }
    }
    
    &Common::Tables::write_tab_table( "$tab_dir/func_def_ref.tab", \@table );
    @table = ();
    
    &echo_green( "done\n" );

    # -------------- parse definitions file,
    
    &echo( qq (   Creating GO synonyms .tab file ... ) );
    
    $array = &GO::Import::parse_synonyms( "$syn_dir/Synonyms.txt" );
    
    # ---------- write synonyms file,
        
    foreach $elem ( @{ $array } ) {
        push @table, [ $elem->{"id"}, $elem->{"name"}, $elem->{"syn"}, $elem->{"rel"} ];
    }
    
    &Common::Tables::write_tab_table( "$tab_dir/func_synonyms.tab", \@table );
    @table = ();
    
    &echo_green( "done\n" );
    
    # --------------- parse ontology files,
    
    &echo( qq (   Parsing GO ontology files ... ) );
            
    foreach $prefix ( "component", "function", "process" )
    {
        $edges = &GO::Import::parse_ontology( "$ont_dir/$prefix.ontology" );
        
        foreach $edge ( @{ $edges } )
        {
            foreach $parent ( @{ $edge->{"parents"} } ) {
                $int_nodes->{ $parent->[0] } = 1;
            }
        }                
        
        foreach $edge ( @{ $edges } )
        {
            if ( exists $int_nodes->{ $edge->{"id"} } ) {
                $edge->{"leaf"} = 0;
            } else {
                $edge->{"leaf"} = 1;
            }
        }
        
        &GO::Import::print_edges_table( "$tab_dir/func_edges.tab", $edges, 1 );
        
        # There are pt some 20% of the terms that dont have definitions. So
        # here we pad the definitions file with those ids and names taken 
        # from the ontology files,
        
        foreach $edge ( @{ $edges } )
        {
            $id = $edge->{"id"};
            $ont_ids->{ $id } = 1;
            
            if ( not exists $defs->{ $id } )
            {
                $defs->{ $id } = 
                {
                    "id" => $id,
                    "name" => $edge->{"name"}, 
                    "deftext" => "",
                    "comment" => "",
                    "refs" => [],
                };
                
                push @defs_table, [ $edge->{"id"}, $edge->{"name"}, "", "" ];
            }
        }
    }
    
    $edges = [];
    
    &Common::Tables::write_tab_table( "$tab_dir/func_def.tab", \@defs_table );
    @defs_table = ();
    
    &echo_green( "done\n" );

    foreach $id ( keys %{ $defs } )
    {
        if ( not exists $ont_ids->{ $id } ) {
            &warning( qq (Definition ID $id is missing from ontologies) );
        }
    }

    # >>>>>>>>>>>>>>>>>>> LOADING  DATABASE TABLES <<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Loading GO database tables ... ) );
        
    foreach $tableO ( $schema->tables )
    {
        &Common::DB::delete_table_if_exists( $dbh, $tableO->name );
        &Common::DB::create_table( $dbh, $tableO );
    }
        
    foreach $tableO ( $schema->tables )
    {
        $table = $tableO->name;

        if ( $table eq "func_edges" )
        {
            if ( not -r "$tab_dir/$table.tab" ) {
                &error( qq (Input table missing -> "$tab_dir/$table.tab") );
            }
            
            $sql = qq (insert into func_def (id,name,deftext,comment) values )
                 . qq ((3673,"Gene ontology","Root node of all three GO trees",""));
            
            &Common::DB::request( $dbh, $sql );
            
            $sql = qq (insert into func_edges (id,parent_id,dist,depth,rel) values )
                 . qq ((3673,"",0,0,""));
            
            &Common::DB::request( $dbh, $sql );
            
            &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
        }
        else
        {
            if ( not -r "$tab_dir/$table.tab" ) {
                &error( qq (Input table missing -> "$tab_dir/$table.tab") );
            }
            
            &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
        }
    }
        
    &echo_green( "done\n" );
        
    # >>>>>>>>>>>>>>>>>>>>>> ADDING EXTRA INDEXES <<<<<<<<<<<<<<<<<<<<
    
    &echo( qq (   Fulltext-indexing GO tables ... ) );
    
    &Common::DB::request( $dbh, "create fulltext index name_fndx on func_def(name)" );
    &Common::DB::request( $dbh, "create fulltext index deftext_fndx on func_def(deftext)" );
    &Common::DB::request( $dbh, "create fulltext index comment_fndx on func_def(comment)" );
    
    &Common::DB::request( $dbh, "create fulltext index name_fndx on func_synonyms(name)" );
    &Common::DB::request( $dbh, "create fulltext index syn_fndx on func_synonyms(syn)" );
    
    &echo_green( "done\n" );
    
    &Common::DB::disconnect( $dbh );
    
    # >>>>>>>>>>>>>>>>>>>>>>> DELETE DATABASE TABLES <<<<<<<<<<<<<<<<<
    
#     if ( not $cl_keep )
#     {
#         foreach $file ( keys %db_tables ) 
#         {
#             &Common::File::delete_file( "$tab_dir/$file" );
#         }
#     }

    return ( 0 , 0 );
}

sub load_ext
{
    # Niels Larsen, January 2004.

    # Loads the external term mappings into a database.

    my ( $proj,
         $db,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $ext_dir, $tab_dir, @files, $tab_time, $src_time, $file, $tableO,
         $db_name, $dbh, $array, @table, $prefix, $ref, $elem, $count, $edges,
         $edge, $table, $schema, $sql, $defs, $ont_ids, $id, @defs_table, 
         $maps, $map, $int_nodes, $parent, $gen_dir, $schema_name );

    # >>>>>>>>>>>>>>>>> CHECKS AND INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<

    $ext_dir = $args->src_dir ."/Ext_maps";
    $tab_dir = $args->tab_dir;

    $schema_name = Registry::Get->type( $db->datatype )->schema;

    $schema = Registry::Schema->get( $schema_name );

    $table = "func_external";
    
    if ( not -d $ext_dir ) {
        &error( "No external mappings directory found", "MISSING DIRECTORY" );
    } elsif ( not grep { $_->{"name"} =~ /2go/ } &Common::Storage::list_files( $ext_dir ) ) {
        &error( "No external mapping files found", "MISSING SOURCE FILES" );
    }
    
    &Common::File::create_dir_if_not_exists( $tab_dir );

    if ( not &Common::DB::database_exists( Registry::Get->project( $db->owner )->datadir ) )
    {
        &echo( qq (   Creating new database ... ) );
        
        &Common::DB::create_database();
        sleep 1;
        
        &echo_green( "done\n" );
    }
    
    $dbh = &Common::DB::connect();

    # >>>>>>>>>>>>>>>>>> CHECK FILE MODIFICATION TIMES <<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there new term map downloads ... ) );

    $tab_time = &Common::File::get_newest_file_epoch( $tab_dir, "func_ext" );
    $src_time = &Common::File::get_newest_file_epoch( $ext_dir );
   
    if ( $tab_time < $src_time ) {
        &echo_green( "yes\n" );
    } else {
        &echo_green( "no\n" );
    }
    
    # >>>>>>>>>>>>>>>>>>> DELETE OLD DATABASE TABLES <<<<<<<<<<<<<<<<<<<<<<
        
    &echo( qq (   Is there an old mapping .tab file ... ) );

    if ( -e "$tab_dir/$table.tab" ) 
    {
        &Common::File::delete_file( "$tab_dir/$table.tab" );            
        &echo_green( "1 deleted\n" );
    }
    else {
        &echo_green( "no\n" );
    }
        
    # >>>>>>>>>>>>>>>>> PARSING EXTERNAL MAPPINGS <<<<<<<<<<<<<<<<<<<<
    
    &echo( qq (   Parsing mappings files ... ) );

    foreach $file ( grep { $_->{"name"} =~ /2go/ } &Common::Storage::list_files( $ext_dir ) )
    {
        $maps = &GO::Import::parse_external( $file->{"path"} );
        
        foreach $map ( @{ $maps } )
        {
            push @table, [ $map->{"id"}, $map->{"ext_db"}, $map->{"ext_id"}, $map->{"ext_name"} ];
        }
    }
    
    &Common::Tables::write_tab_table( "$tab_dir/$table.tab", \@table );
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>> LOADING  DATABASE TABLES <<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Loading mappings table ... ) );

    $tableO = $schema->table( $table );
    
    &Common::DB::delete_table_if_exists( $dbh, $table );
    &Common::DB::create_table( $dbh, $tableO );
    
    if ( not -r "$tab_dir/$table.tab" ) {
        &error( qq (Input table missing -> "$tab_dir/$table.tab") );
    }
    
    &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
    
    &Common::DB::disconnect( $dbh );
    
    # >>>>>>>>>>>>>>>>>>>>>>> DELETE DATABASE TABLES <<<<<<<<<<<<<<<<<
    
#      if ( not $cl_keep )
#     {
#         &Common::File::delete_file( "$tab_dir/$table.tab" );
#     }
    
    &echo_green( "done\n" );

    return ( 0, 0 );
}

sub load_genes
{
    # Niels Larsen, January 2004.

    # Loads gene associations files into a database. 

    my ( $proj,
         $db,
         $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $gen_dir, $tab_dir, $schema, $dbh, $tab_time, $src_time, @files,
         $line_no, $file, %db_tables, $tab_fhs, $tab_fh, $in_fh, $line,
         $entry, $table, $gene_count, $gene_count_total, $error_count, 
         $tab, $count, $text, %gene_dict, $gene_id, $elem, $schema_name,
         $db_name, $tableO );

    # >>>>>>>>>>>>>>>>> CHECKS AND INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<

    $gen_dir = $args->src_dir ."/Gene_maps";
    $tab_dir = $args->tab_dir;

    $schema_name = Registry::Get->type( $db->datatype )->schema;

    $schema = Registry::Schema->get( $schema_name );
    $schema->table_menu->match_options_expr( '$_->name =~ /func_genes/' );

    if ( not -d $gen_dir ) {
        &error( "No GO gene associations directory found", "MISSING DIRECTORY" );
    } elsif ( not grep { $_->{"name"} =~ /^gene_association/ } &Common::Storage::list_files( $gen_dir ) ) {
        &error( "No GO gene association files found", "MISSING SOURCE FILES" );
    }
    
    &Common::File::create_dir_if_not_exists( $tab_dir );

    $db_name = Registry::Get->project( $db->owner )->datadir;

    if ( not &Common::DB::database_exists( $db_name ) )
    {
        &echo( qq (   Creating new database ... ) );
        
        &Common::DB::create_database( $db_name );
        sleep 1;
        
        &echo_green( "done\n" );
    }
    
    $dbh = &Common::DB::connect();

    # >>>>>>>>>>>>>>>>>> CHECK FILE MODIFICATION TIMES <<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there new gene map downloads ... ) );

    $tab_time = &Common::File::get_newest_file_epoch( $tab_dir, "func_genes" );
    $src_time = &Common::File::get_newest_file_epoch( $gen_dir );
    
    if ( $tab_time < $src_time ) {
        &echo_green( "yes\n" );
    } else {
        &echo_green( "no\n" );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>> DELETE OLD .TAB FILES <<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there old gene map .tab files ... ) );
        
    if ( @files = grep { $_->{"name"} =~ /func_genes/ } &Common::Storage::list_files( $tab_dir ) )
    {
        $count = 0;
        
        foreach $file ( @files )
        {
            &Common::File::delete_file( $file->{"path"} );
            $count++;
        }
        
        &echo_green( "$count deleted\n" );
    }
    else {
        &echo_green( "no\n" );
    }
        
    # >>>>>>>>>>>>>>>>>>>>>>> CREATE NEW .TAB FILES <<<<<<<<<<<<<<<<<<<<<<<

    # ----------- output file handles,

    foreach $table ( $schema->table_names )
    {
        $tab_fhs->{ $table } = &Common::File::get_write_handle( "$tab_dir/$table.tab" );
    }

    $gene_count_total = 0;
    $gene_id = 0;

    foreach $file ( sort { $a->{"name"} cmp $b->{"name"} } &Common::Storage::list_files( $gen_dir ) )
    {
#        next if $file->{"name"} !~ /GeneDB/;
#        next if $file->{"name"} !~ /\.wb$/;

        &echo( qq (   Parsing $file->{'name'} (patience) ... ) );

        $in_fh = &Common::File::get_read_handle( $file->{'path'} );

        $line_no = 0;
        $gene_count = 0;
        $error_count = 0;

        while ( defined ( $line = <$in_fh> ) and $line =~ /^[\!\s]/ )  { $line_no++; }

        while ( defined ( $line = <$in_fh> ) )
        {
            $line_no++;

            $entry = &GO::Import::parse_genes_line( $line, $line_no, $file->{"name"} );

            if ( $entry->{"errors"} )
            {
                $error_count += scalar @{ $entry->{"errors"} };
                &GO::Import::log_errors( $entry->{"errors"} );
            }
            
            $tab = $entry->{"func_genes"};

            if ( $tab->{"id"} and $tab->{"tax_id"} and $tab->{"db"} and $tab->{"db_id"} )
            {
                if ( not $gene_dict{ $tab->{"db"} }{ $tab->{"db_id"} } ) {
                    $gene_id++;
                }

                # -------- func_genes table,
                 
                $tab_fh = $tab_fhs->{"func_genes"};
                
                print $tab_fh
                    qq ($tab->{"db"}\t$tab->{"db_id"}\t$gene_id\t$tab->{"db_name"}\t)
                  . qq ($tab->{"db_symbol"}\t$tab->{"modifier"}\t$tab->{"evidence"}\t$tab->{"aspect"}\t)
                  . qq ($tab->{"db_type"}\t$tab->{"date"}\t$tab->{"db_assn"}\n);

                # -------- func_genes_ref table,

                $tab_fh = $tab_fhs->{"func_genes_ref"};

                foreach $elem ( @{ $entry->{"func_genes_ref"} } )
                {
                    print $tab_fh qq ($elem->[0]\t$elem->[1]\t$gene_id\n);
                }

                # -------- func_genes_tax table,

                $tab_fh = $tab_fhs->{"func_genes_tax"};
                
                print $tab_fh
                    qq ($tab->{"id"}\t$gene_id\t$tab->{"tax_id"}\t$tab->{"tax_id_use"}\n);

                # -------- func_genes_synonyms table,
                
                $tab_fh = $tab_fhs->{"func_genes_synonyms"};
                
                foreach $elem ( @{ $entry->{"func_genes_synonyms"} } )
                {
                    print $tab_fh qq ($gene_id\t$elem->[0]\n);
                }

                $gene_dict{ $tab->{"db"} }{ $tab->{"db_id"} }++;
                $gene_count++;
            }
        }

        &Common::File::close_handle( $in_fh );
    
        $gene_count_total += $gene_count;
        
        $text = &Common::Util::commify_number( $gene_count );
        &echo_green( "$text genes" );
        
        if ( $error_count > 0 ) 
        {
            $text = &Common::Util::commify_number( $error_count );
            &echo( ", " );
            &echo_yellow( "$text errors\n" );
        }
        else 
        {
            &echo( "\n" );
        }
    }

    foreach $tab_fh ( values %{ $tab_fhs } )
    {
        &Common::File::close_handle( $tab_fh );
    }    

    # >>>>>>>>>>>>>>>>>>>>>>>>> LOAD THE .TAB FILES <<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Loading gene association database tables ... ) );
    
    foreach $tableO ( $schema->tables )
    {
        &Common::DB::delete_table_if_exists( $dbh, $tableO->name );
        &Common::DB::create_table( $dbh, $tableO );
    }
    
    foreach $tableO ( $schema->tables )
    {
        $table = $tableO->name;
        
        if ( not -r "$tab_dir/$table.tab" ) {
            &error( qq (Input table missing -> "$tab_dir/$table.tab") );
        }
        
        &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
    }
    
    &echo_green( "done\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>> ADDING EXTRA INDEXES <<<<<<<<<<<<<<<<<<<<
    
    &echo( qq (   Fulltext-indexing gene association tables ... ) );
    
    &Common::DB::request( $dbh, "create fulltext index db_name_fndx on func_genes(db_name)" );
    
    &echo_green( "done\n" );
    
    &Common::DB::disconnect( $dbh );
    
    # >>>>>>>>>>>>>>>>>>>>>>> DELETE DATABASE TABLES <<<<<<<<<<<<<<<<<

#     if ( not $cl_keep )
#     {
#         foreach $file ( keys %db_tables ) 
#         {
#             &Common::File::delete_file( "$tab_dir/$file" );
#         }
#     }

    return ( $gene_count_total, 0 );
}

sub genes_fields
{
    # Niels Larsen, January 2004.

    # Simply returns a hash with column indices as keys and text strings
    # as values. This routine is hardly useful outside this module.

    # Returns a hash.

    return 
    {
        0 => "DB",
        1 => "DB_Object_ID",
        2 => "DB_Object_Symbol",
        3 => "NOT",
        4 => "GO ID",
        5 => "DB:Reference",
        6 => "Evidence",
        7 => "With (or) From",
        8 => "Aspect",
        9 => "DB_Object_Name",
        10 => "DB_Object_Synonym",
        11 => "DB_Object_Type",
        12 => "taxon",
        13 => "Date",
        14 => "Assigned_by",
    };
}

sub parse_genes_line
{
    # Niels Larsen, January 2004;

    # Parses a given line from a gene associations file into a memory
    # structure that makes it easier to write database ready tables. 
    # This routine is probably not very useful outside this module.

    my ( $line,    # Gene associations table line
         $count,   # Line number
         $file,    # File name
         ) = @_; 

    # Returns a hash.

    my ( @line, $entry, $i, $fields, $field, $this_year, $year, $month, $day,
         $error, $text, $message, $db, $db_id, $db_refs );

    $line =~ s/\n$//;
    @line = split "\t", $line;

    # -------- contributing database, 

    if ( $line[0] and $line[0] =~ /\S/ )
    {
        $entry->{"func_genes"}->{"db"} = $line[0];
    }
    else {
        $message = qq ($file, line $count: DB field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }

    $entry->{"func_genes"}->{"db"} ||= "";

    # -------- unique id in contributing database,

    if ( $line[1] and $line[1] =~ /\S/ )
    {
        $entry->{"func_genes"}->{"db_id"} = $line[1];
    }
    else {
        $message = qq ($file, line $count: DB_Object_ID field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }

    $entry->{"func_genes"}->{"db_id"} ||= "";

    # -------- unique symbol for above id,

    if ( $line[2] and $line[2] =~ /\S/ )
    {
        $entry->{"func_genes"}->{"db_symbol"} = $line[2];
    }
    else {
        $message = qq ($file, line $count: DB_Object_Symbol field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }

    $entry->{"func_genes"}->{"db_symbol"} ||= "";

    # -------- annotation modifier,

    if ( $line[3] and $line[3] =~ /\S/ )
    {
        if ( $line[3] =~ /^NOT|contributes_to$/ )
        {
            $entry->{"func_genes"}->{"modifier"} = $line[3];
        }
        else {
            $message = qq ($file, line $count: NOT field looks wrong -> "$line[3]");
            push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
        }
    }

    $entry->{"func_genes"}->{"modifier"} ||= "";

    # -------- GO id,

    if ( $line[4] )
    {
        if ( $line[4] =~ /^GO:(\d+)$/ )
        {
            $entry->{"func_genes"}->{"id"} = $1 * 1;
        }
        else {
            $message = qq ($file, line $count: GO ID field looks wrong -> "$line[4]");
            push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
        }
    }
    else {
        $message = qq ($file, line $count: GO ID field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }

    $entry->{"func_genes"}->{"id"} ||= "";

    # -------- database reference,

    if ( $line[5] and $line[5] =~ /\S/ )
    {
        foreach $field ( split /\|/, $line[5] )
        {
            if ( $field and $field =~ /^(.+):(.+)$/ )
            {
                if ( exists $db_refs->{ $1 }->{ $2 } ) 
                {
                    $message = qq ($file, line $count: reference has duplication -> "$line[5]");
                    push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
                }
                else {
                    $db_refs->{ $1 }->{ $2 } = 1;
                }
            }
            elsif ( $field )
            {
                $message = qq ($file, line $count: reference field looks wrong -> "$line[5]");
                push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
            }
        }

        foreach $db ( keys %{ $db_refs } )
        {
            foreach $db_id ( keys %{ $db_refs->{ $db } } )
            {
                push @{ $entry->{"func_genes_ref"} }, [ $db, $db_id ];
            }
        }
    }
    else {
        $message = qq ($file, line $count: reference field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }
    
    $entry->{"func_genes_ref"} ||= [];

    # -------- annotation evidence,

    if ( $line[6] )
    {
        if ( $line[6] =~ /^IMP|IGI|IPI|ISS|IDA|IEP|IEA|TAS|NAS|ND|IC$/ )
        {
            $entry->{"func_genes"}->{"evidence"} = $line[6];
        }
        else {
            $message = qq ($file, line $count: evidence field looks wrong -> "$line[6]");
            push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
        }
    }
    else {
        $message = qq ($file, line $count: evidence field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }

    $entry->{"func_genes"}->{"evidence"} ||= "";
            
    # -------- with or from field,

    # This we skip. It isnt clearly explained why its there and there 
    # is no strict format documented. 

    # -------- GO category ("aspect"),

    if ( $line[8] )
    {
        if ( $line[8] =~ /^P|F|C$/ )
        {
            $entry->{"func_genes"}->{"aspect"} = $line[8];
        }
        else {
            $message = qq ($file, line $count: aspect field looks wrong -> "$line[8]");
            push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
        }
    }
    else {
        $message = qq ($file, line $count: aspect field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }
    
    $entry->{"func_genes"}->{"aspect"} ||= "";

    # -------- gene/product name,

    if ( $line[9] and $line[9] =~ /\S/ )
    {
        $entry->{"func_genes"}->{"db_name"} = $line[9];
    }
    else
    {
        $entry->{"func_genes"}->{"db_name"} = "";
    }

    # -------- database object synonym,

    if ( $line[10] and $line[10] =~ /\S/ )
    {
        foreach $field ( split /\s*\|\s*/, $line[10] )
        {
            if ( $field and $field =~ /\S/ )
            {
                $field =~ s/^\s*//;
                $field =~ s/\s*$//;

                push @{ $entry->{"func_genes_synonyms"} }, [ $field ];
            }
        }
    }

    $entry->{"func_genes_synonyms"} ||= [];
    
    # -------- annotation object type,
    
    if ( $line[11] )
    {
        if ( $line[11] =~ /^gene|transcript|protein|protein_structure|complex$/i )
        {
            $entry->{"func_genes"}->{"db_type"} = lc $line[11];
        }
        else {
            $message = qq ($file, line $count: type field looks wrong -> "$line[11]");
            push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
        }
    }
    else {
        $message = qq ($file, line $count: type field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }
    
    $entry->{"func_genes"}->{"db_type"} ||= "";
            
    # -------- organism taxon,
    
    if ( $line[12] )
    {
        if ( $line[12] =~ /^taxon:(\d+)$/ )
        {
            $entry->{"func_genes"}->{"tax_id"} = $1;
            $entry->{"func_genes"}->{"tax_id_use"} = "";
        }
        elsif ( $line[12] =~ /^taxon:(\d+)\|taxon:(\d+)$/ )
        {
            $entry->{"func_genes"}->{"tax_id"} = $1;
            $entry->{"func_genes"}->{"tax_id_use"} = $2;
        }
        else {
            $message = qq ($file, line $count: taxonomy field looks wrong -> "$line[12]");
            push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
        }
    }
    else {
        $message = qq ($file, line $count: taxonomy field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }         
    
    $entry->{"func_genes"}->{"tax_id"} ||= "";
    $entry->{"func_genes"}->{"tax_id_use"} ||= "";
            
    # -------- annotation date,

    if ( $line[13] and $line[13] =~ /GeneDB/ )
    {
        ( $line[13], $line[14] ) = ( split /\s+/, $line[13] );

        $message = qq ($file, line $count: assigned_by data in date field);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }
    elsif ( $line[15] and $line[15] =~ /^\s*(\S+)\s*$/ )
    {
        $line[14] = $1;
        $message = qq ($file, line $count: assigned_by data in column 16, but column 15 is max);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }

    if ( $line[13] )
    {
        if ( $line[13] =~ /^\s*(\d\d\d\d)(\d\d)(\d\d)\s*$/ )
        {
            $year = $1;
            $month = $2;
            $day = $3;
            
            $this_year = ( localtime() )[5] + 1900;
            
            $error = 0;
            
            if ( $year > $this_year or $year < 1990 ) 
            {
                $error = 1;
                $message = qq ($file, line $count: wrong year in date field -> "$line[13]");
                push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
            }
            
            if ( $month > 12 or $month < 1 ) 
            {
                $error = 1;
                $message = qq ($file, line $count: wrong month in date field -> "$line[13]");
                push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
            }
            
            if ( $day > 31 or $day < 1 ) 
            {
                $error = 1;
                $message = qq ($file, line $count: wrong day in date field -> "$line[13]");
                push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
            }
            
            if ( $error ) {
                $entry->{"func_genes"}->{"date"} = "";
            } else {
                $entry->{"func_genes"}->{"date"} = "$year-$month-$day";  # as MySQL likes it
            }
        }
        else {
            $message = qq ($file, line $count: date field format looks wrong -> "$line[13]");
            push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
        }
    }
    else {
        $message = qq ($file, line $count: date field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }        

    $entry->{"func_genes"}->{"date"} ||= "";
            
    # -------- database who made the assignment,

    if ( $line[14] and $line[14] =~ /\S/ )
    {
        $entry->{"func_genes"}->{"db_assn"} = $line[14];
    }
    else
    {
        $entry->{"func_genes"}->{"db_assn"} = "";

        $message = qq ($file, line $count: assigned_by field is empty);
        push @{ $entry->{"errors"} }, &Common::Logs::format_error( $message );
    }
    
    # >>>>>>>>>>>>>>>> CREATE FIELDS FOR FUNC_GENES_REF TABLE <<<<<<<<<<<<<<<<<

    return $entry;
}

sub parse_defs
{
    # Niels Larsen, October 2003.

    # Returns the content of the GO definitions file as an 
    # array of hashes with keys "id", "name", "deftext", "comment"
    # and "refs". The "refs" key points to an array, the rest are
    # scalars. 

    my ( $file,     # Full file path to the GO.defs file
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }
    
    my ( $line, $term, $id, $deftext, $comment, @refs, @defs, 
         $prefix, $suffix, $line_num, $fname );

    $id = $term = $deftext = $comment = "";
    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        if ( $line =~ /^term:\s*(.+)\s*$/ )
        {
            $term = $1;
        }
        elsif ( $line =~ /^goid:\s*GO:(\d+)\s*$/ )
        {
            $id = $1 * 1;
        }
        elsif ( $line =~ /^definition:\s*(.+)\.?\s*$/ )
        {
            $deftext = $1;
        }
        elsif ( $line =~ /^definition_reference:\s*([^:]+):(.+)\s*$/ )
        {
            $prefix = $1;
            $suffix = $2;

            if ( $prefix eq "http" ) {
                push @refs, [ "WWW", "$prefix:$suffix" ];
            } else {
                push @refs, [ $prefix, $suffix ];
            }
        }
        elsif ( $line =~ /^comment:\s*(.+)\.?\s*$/ )
        {
            $comment = $1;
        }
        elsif ( $line !~ /\w/ and $id ) {

            push @defs, 
            {
                "id" => $id,
                "name" => $term,
                "deftext" => $deftext,
                "comment" => $comment,
                "refs" => dclone \@refs,
            };

            $id = $term = $deftext = $comment = "";
            @refs = ();
        }
        elsif ( $line !~ /^!/ )
        {
            &warning( qq ($fname, line $line_num: could not parse line -> "$line") );
        }
    }

    # This is only done if there is no empty line at the bottom of the file,

    if ( $id )
    {
        push @defs, 
        {
            "id" => $id,
            "name" => $term,
            "deftext" => $deftext,
            "comment" => $comment,
            "refs" => dclone \@refs,
        }
    }

    return wantarray ? @defs : \@defs;
}

sub parse_external
{
    # Niels Larsen, October 2003.

    # Returns the content of the GO external mappings as an array 
    # of hashes with keys "id", "name", "ext_db", "ext_id" and "ext_name".

    my ( $file,       # Full file path to the xxxxx2go file.
         $ids,        # Ontology ids for checking - OPTIONAL
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }
    
    my ( $line, @line, $ext, $ext_db, $ext_id, $ext_term, @terms, $term, 
         @mappings, $line_num, $fname, $go_id );
    
    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        next if $line =~ /^!/ or $line !~ /\w/;
        
        chomp $line;
        ( $ext, @terms ) = split /\s+>\s+/, $line;

        next if not @terms;

        if ( defined $ext and $ext =~ /^([^:]+):([^\s]+)\s*(.*)\s*$/ )
        {
            $ext_db = $1;
            $ext_id = $2;
            $ext_term = $3 || "";
            
            foreach $term ( @terms )
            {
                if ( $term =~ /^\s*(?:GO:)?(.+) +; +GO:(\d{7,7})\s*$/ )
                {
                    $go_id = $2*1;

                    push @mappings,
                    {
                        "id" => $2*1,
                        "name" => $1,
                        "ext_db" => $ext_db,
                        "ext_id" => $ext_id,
                        "ext_name" => $ext_term,
                    };

#                    if ( $ids and not exists $ids->{ $go_id } ) {
#                        &warning( qq ($fname, line $line_num: GO id $go_id does not exist) );
#                    }
                }
                elsif ( $term !~ /^\s*GO:\.\s*$/ )
                {
                    $term ||= "";
                    &warning( qq ($fname, line $line_num: could not parse GO id -> "$term") );
                }
            }
        }
        else
        {
            $ext ||= "";
            &warning( qq ($fname, line $line_num: could not parse external id -> "$ext") );
        }
   }

    return wantarray ? @mappings : \@mappings;
}

sub parse_synonyms
{
    # Niels Larsen, October 2003.

    # Creates an array of synonym hashes with the keys "id", "name", 
    # "relation" and "synonym". The relation value can be either "exact"
    # "broader", "narrower" or "inexact". See GO documentation if you
    # more information. 

    my ( $file,     # Full file path to the synonyms file
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }
    
    my ( $line, %dict, $id, $name, $relation, $synonym, @synonyms, $fname, 
         $line_num );

    %dict = (
             "~" => "related",
             "=" => "exact",
             "<" => "broader",
             ">" => "narrower",
             "!=" => "inexact",
             "?" => "todo",
             );

    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        next if $line =~ /^!/;
        
        chomp $line;
        
        if ( ( $id, $name, $relation, $synonym ) = split "\t", $line )
        {
            if ( $id =~ /^GO:(\d+)$/ ) {
                $id = $1 * 1;
            } else {
                &warning( qq ($fname, line $line_num: GO id looks wrong -> "$id") );
            }

            if ( $name ) {
                $name =~ s/^\s*//;
                $name =~ s/\s*$//;
            }

            if ( not $name ) {
                &warning( qq (No name found for id $id) );
            }
            
            if ( $relation and exists $dict{ $relation } ) {
                $relation = $dict{ $relation };
            } else {
                &warning( qq ($fname, line $line_num: relation looks wrong -> "$relation") );
            }

            if ( $synonym ) {
                $synonym =~ s/^\s*//;
                $synonym =~ s/\s*$//;
            }

            if ( not $synonym ) {
                &warning( qq ($fname, line $line_num: no synonym for id = $id) );
            }            

            if ( $id and $name and $relation and $synonym )
            {
                push @synonyms,
                {
                    "id" => $id,
                    "name" => $name,
                    "rel" => $relation,
                    "syn" => $synonym,
                };
            }
        }
    }

    return wantarray ? @synonyms : \@synonyms;
}

sub parse_ontology
{
    # Niels Larsen, October 2003.

    # Reads an ontology flat file and creates an array of hashes where each 
    # hash has the keys "id", "name", "rel" (relation, either "%" or "<" 
    # which symbolizes "is a" and "part of" relationship respectively) and
    # "parents". The value of "parents" is a list of tuples of the form
    # [ id, rel ]. 

    my ( $file,    # Ontology file path
         ) = @_;

    # Returns a hash. 

    my ( $line, $depth, $edges, @parent_ids, $id, $parent_id, $relation,
         @list, $elem, $name, @parents, @edges, $fname, $line_num );

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }
    
    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;
        chomp $line;

        if ( $line =~ /^(\s*)([%<\$].+)$/ )
        {
            $depth = length $1;
            $line = $2;

            $line =~ s/;? synonym:[^%<;]+[;]?//g;
            @list = ();

            while ( $line =~ /([%<\$])(.+?) ; GO:(\d+)/g )
            {
                push @list, [ $3*1, $2, $1 ];
                
                if ( length $3 != 7 ) {
                    &warning( qq ($fname, line $line_num: GO id looks wrong -> "$2") );
                }
            }
            
            ( $id, $name, $relation ) = @{ shift @list };

            if ( $depth > 0 )
            {
                $parent_id = $parent_ids[ $depth-1 ];
                @parents = [ $parent_id, $relation ];

                foreach $elem ( @list )
                {
                    $parent_id = $elem->[0];
                    $relation = $elem->[2];

                    push @parents, [ $parent_id, $relation ];
                }

                push @edges,
                {
                    "id" => $id,
                    "name" => $name,
                    "depth" => $depth,
                    "parents" => &Storable::dclone( \@parents ),
                }
            }

            $parent_ids[ $depth ] = $id;
        }
        elsif ( $line !~ /^!/ )
        {
            &warning( qq ($fname, line $line_num: line looks wrong -> "$line") );
        }
    }

    return wantarray ? @edges : \@edges;
}

sub print_edges_table
{
    # Niels Larsen, October 2003.
    
    # Creates the go_edges table from the edges hash created by the
    # parse_ontology routine. The table has four columns, see the 
    # schema. 

    my ( $file,          # Edges file path
         $edges,         # Edges array
         $append,        # Append flag, OPTIONAL, default 1
         ) = @_;

    # Returns nothing.

    $append = 1 if not defined $append;

    if ( $append ) 
    {
        if ( not open FILE, ">> $file" ) {
            &error( qq (Could not append-open "$file") );
        }
    }
    else
    {
        if ( not open FILE, "> $file" ) {
            &error( qq (Could not write-open "$file") );
        }
    }
    
    my ( $id, $parents, $parent, $parent_id, %edges, $depth, $leaf );

    %edges = map { $_->{"id"}, $_ } @{ $edges };

    foreach $id ( sort { $a <=> $b } keys %edges )
    {
        $parents = &GO::Import::get_all_parents( $id, 1, \%edges );

        $depth = $edges{ $id }->{"depth"};
        $leaf = $edges{ $id }->{"leaf"};

        foreach $parent_id ( sort { $a <=> $b } keys %{ $parents } )
        {
            $parent = $parents->{ $parent_id };
            
            print FILE qq ($id\t$parent_id\t$parent->[0]\t$depth\t$leaf\t$parent->[1]\n);
        }
    }

    close FILE;

    return;
 }   

sub get_all_parents
{
    # Niels Larsen, October 2003.

    # Given a node id, creates a hash of all its parents. Each key is the 
    # parent id and the values have the form [ hops, relation ] where hops
    # are the number of position moves from a given node to the parent; for
    # two immediate neighbors hops would be 1, with one node between 2 and 
    # so on. Relation is either "%" or "<" which symbolizes "is a" and 
    # "part of" relationship respectively. To create the, the routine 
    # travels the edges hash made by the parse_ontology routine. 

    my ( $id,      # Node id
         $dist,    # Node distance
         $edges,   # Edges hash
         ) = @_;

    # Returns an array.

    my ( $parents, $parents2, $parent, $parent_id, $relation, $edge );
    
    if ( exists $edges->{ $id } )
    {
        foreach $parent ( @{ $edges->{ $id }->{"parents"} } )
        {
            $parent_id = $parent->[0];
            $relation = $parent->[1];

            $parents->{ $parent_id } = [ $dist, $relation ];
            
            if ( $parents2 = &GO::Import::get_all_parents( $parent_id, $dist+1, $edges ) )
            {
                $parents = { %{ $parents }, %{ $parents2 } };
            }
        }
    }
    
    return wantarray ? %{ $parents } : $parents;
}
 
sub log_errors
{
    # Niels Larsen, January 2004.
    
    # Appends a given list of messages to an ERRORS file in the 
    # GO/Import subdirectory. 

    my ( $errors,   # Error messages
         ) = @_;

    # Returns nothing.

    my ( $error, $log_dir, $log_file );

    $log_dir = "$Common::Config::log_dir/GO/Import";
    $log_file = "$log_dir/ERRORS";

    &Common::File::create_dir_if_not_exists( $log_dir );

    if ( open LOG, ">> $log_file" )
    {
        foreach $error ( @{ $errors } )        {
            print LOG ( join "\t", @{ $error } ) . "\n";
        }

        close LOG;
    }
    else {
        &error( qq (Could not append-open "$log_file") );
    }

    return;
}

sub create_lock
{
    # Niels Larsen, October 2003.

    # Creates a GO/Import subdirectory under the configured scratch
    # directory. The existence of this directory means GO data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::log_dir/GO/Import" );

    return;
}

sub remove_lock
{
    # Niels Larsen, October 2003.
    
    # Deletes a GO/Import subdirectory from the configured scratch
    # directory. Errors are thrown if the directory is not empty or if
    # it could not be deleted. 

    # Returns nothing. 

    my $lock_dir = "$Common::Config::log_dir/GO/Import";

    if ( @{ &Common::File::list_files( $lock_dir ) } )
    {
        &error( qq (Directory is not empty -> "$lock_dir") );
    }
    elsif ( not rmdir $lock_dir )
    {
        &error( qq (Could not remove lock directory "$lock_dir") );
    }

    return;
}

sub is_locked 
{
    # Niels Larsen, October 2003.

    # Checks if there is an GO/Import subdirectory under the scratch
    # directory of the system. 

    # Returns nothing.

    my $lock_dir = "$Common::Config::log_dir/GO/Import";

    if ( -e $lock_dir ) {
        return 1;
    } else {
        return;
    }
}

1;


__END__
