package Anatomy::Import;     #  -*- perl -*-

# Anatomy ontology import functions.
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
                 &load_ontology
                 &load_ontology_obo
                 &parse_defs
                 &parse_defs_obo
                 &parse_ontology
                 &parse_ontology_obo
                 &parse_synonyms
                 &parse_synonyms_obo
                 &parse_xrefs
                 &parse_xrefs_obo
                 &print_edges_table
                 &get_all_parents

                 &log_errors
                 &create_lock
                 &delete_lock
                 &is_locked
                  );

use Anatomy::Schema;
use Anatomy::DB;

use Common::DB;
use Common::Storage;
use Common::Messages;
use Common::Tables;
use Common::File;
use Common::Config;

1;

__END__

Fix compile errors

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub load_all
{
    # Niels Larsen, October 2004.

    # Loads one or more anatomy files into a database. First the database 
    # tables are initialized, if they have not been. Then each release file
    # is parsed and saved into database-ready temporary files which are then
    # loaded - unless the "readonly" flag is given. 
    
    my ( $wants,           # Wanted file types
         $cl_readonly,     # Prints messages but does not load
         $cl_force,        # Reloads files even though database is newer
         $cl_keep,         # Avoids deleting database ready tables
         ) = @_;

    # Returns nothing.

    my ( $obo_file, $ont_file, $syn_file, $def_file, 
         $db_prefix, $id_prefix, $dbh, $sql );

    if ( $wants->{"all"} )
    {
        $wants->{"cells"} = 1;
        $wants->{"fly"} = 1;
        $wants->{"mouse"} = 1;
        $wants->{"moused"} = 1;
        $wants->{"plant"} = 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CELL TYPES <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $wants->{"cells"} ) 
    {
        $obo_file = "CELL.ontology";
        $db_prefix = "clo";
        $id_prefix = "CL";

        &Anatomy::Import::load_ontology_obo( $obo_file, $db_prefix, $id_prefix,
                                             $cl_readonly, $cl_force, $cl_keep );

        $dbh = &Common::DB::connect();

#        &Common::DB::add_row( $dbh, "flyo_edges", [ 0, 0, 0, 0, 0, '""' ] );
#        
#        &Common::DB::delete_row( $dbh, "flyo_def", "flyo_id", 1 );
#        &Common::DB::add_row( $dbh, "flyo_def", [ 1, '"Drosophila anatomy"', '""', '""' ] );

        &Common::DB::disconnect( $dbh );
    }

    # >>>>>>>>>>>>>>>>>>>>>>> ADULT DROSOPHILA <<<<<<<<<<<<<<<<<<<<<<<<

    if ( $wants->{"fly"} ) 
    {
        $ont_file = "FLY.ontology";
        $syn_file = "FLY.ontology";
        $def_file = "FLY.defs";
        $db_prefix = "flyo";
        $id_prefix = "FBbt";

        &Anatomy::Import::load_ontology( $ont_file, $syn_file, $def_file, 
                                         $db_prefix, $id_prefix,
                                         $cl_readonly, $cl_force, $cl_keep );
        
        $dbh = &Common::DB::connect();

        &Common::DB::add_row( $dbh, "flyo_edges", [ 0, 0, 0, 0, 0, '""' ] );
        
        &Common::DB::delete_row( $dbh, "flyo_def", "flyo_id", 1 );
        &Common::DB::add_row( $dbh, "flyo_def", [ 1, '"Drosophila anatomy"', '""', '""' ] );

        &Common::DB::disconnect( $dbh );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> ADULT MOUSE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $wants->{"mouse"} ) 
    {
        $ont_file = "MA.ontology";
        $syn_file = "MA.ontology";
        $def_file = "";
        $db_prefix = "mao";
        $id_prefix = "MA";

        &Anatomy::Import::load_ontology( $ont_file, $syn_file, $def_file, 
                                         $db_prefix, $id_prefix,
                                         $cl_readonly, $cl_force, $cl_keep );

        $dbh = &Common::DB::connect();

        &Common::DB::add_row( $dbh, $db_prefix."_edges", [ 1, 0, 0, 0, 0, '""' ] );
        &Common::DB::add_row( $dbh, $db_prefix."_edges", [ 0, 0, 0, 0, 0, '""' ] );
        
        &Common::DB::add_row( $dbh, $db_prefix."_def", [ 1, '"Mouse anatomy (adult)"', '""', '""' ] );

        &Common::DB::delete_row( $dbh, $db_prefix."_def", $db_prefix."_id", 2405 );
        &Common::DB::add_row( $dbh, $db_prefix."_def", [ 2405, '"Mouse anatomy (adult)"', '""', '"<"' ] );

        &Common::DB::disconnect( $dbh );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> MOUSE EMBRYO <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $wants->{"moused"} ) 
    {
        $ont_file = "EMAP.ontology";
        $syn_file = "EMAP.ontology";
        $def_file = "";
        $db_prefix = "mado";
        $id_prefix = "EMAP";

        &Anatomy::Import::load_ontology( $ont_file, $syn_file, $def_file, 
                                         $db_prefix, $id_prefix,
                                         $cl_readonly, $cl_force, $cl_keep );

        $dbh = &Common::DB::connect();

        &Common::DB::add_row( $dbh, $db_prefix."_edges", [ 0, 0, 0, 0, 0, '""' ] );
        
#        &Common::DB::delete_row( $dbh, "mao_def", "mao_id", 2405 );
#        &Common::DB::add_row( $dbh, "mao_def", [ 2405, '"Mouse anatomy (adult)"', '""', '"<"' ] );

        &Common::DB::disconnect( $dbh );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ADULT PLANT <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $wants->{"plant"} ) 
    {
        $ont_file = "PO.ontology";
        $syn_file = "PO.ontology";
        $def_file = "PO.defs";
        $db_prefix = "po";
        $id_prefix = "PO";

        &Anatomy::Import::load_ontology( $ont_file, $syn_file, $def_file,
                                         $db_prefix, $id_prefix,
                                         $cl_readonly, $cl_force, $cl_keep );

        $dbh = &Common::DB::connect();

        &Common::DB::add_row( $dbh, "po_edges", [ 9075, 0, 0, 0, 0, '""' ] );

        &Common::DB::delete_row( $dbh, "po_def", "po_id", 9075 );
        &Common::DB::add_row( $dbh, "po_def", [ 9075, '"Plant anatomy"', '""', '"<"' ] );

        &Common::DB::delete_row( $dbh, "po_def", "po_id", 9011 );
        &Common::DB::add_row( $dbh, "po_def", [ 9011, '"Plant anatomy (adult)"', '""', '"<"' ] );

        &Common::DB::disconnect( $dbh );
    }

    return;
}

sub load_ontology_obo
{
    # Niels Larsen, October 2004.

    # Loads a single given anatomy ontology in the newer OBO DAG-edit
    # format where a single file contains all information. 

    my ( $ont_file,
         $syn_file,
         $def_file,
         $db_prefix,
         $id_prefix,
         $cl_readonly,   # Prints messages but does not load
         $cl_force,      # Reloads files even though database is newer
         $cl_keep,       # Avoids deleting database ready tables
         ) = @_;

    # Returns nothing.

    my ( $ont_dir, $tab_dir, @files, $tab_time, $src_time, $file, 
         $db_name, $dbh, $array, @table, $ref, $elem, $count, $edges,
         $edge, $table, $schema, $sql, $defs, $id, @defs_table, 
         $maps, $map, $int_nodes, $parent, $gen_dir, %db_tables,
         $def_table, $edges_table, $synonyms_table, $xrefs_table,
         $stats_table, $id_name );

    # >>>>>>>>>>>>>>>>> CHECKS AND INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<

    # Where to find the sources,

    $ont_dir = "$Common::Config::dat_dir/Anatomy/Ontologies";
    $tab_dir = "$Common::Config::dat_dir/Anatomy/Database_tables";

    if ( not -d $ont_dir ) {
        &error( "No ontology directory found", "MISSING DIRECTORY" );
    } elsif ( not grep { $_->{"name"} =~ /\.ontology$/ } &Common::Storage::list_files( $ont_dir ) ) {
        &error( "No source files found", "MISSING SOURCE FILES" );
    }
    
    # Database table names and ids,

    $Anatomy::Schema::db_prefix = $db_prefix;
    $Anatomy::Schema::id_name = $id_name = $db_prefix."_id";
    $Anatomy::Schema::def_table = $def_table = $db_prefix."_def";
    $Anatomy::Schema::edges_table = $edges_table = $db_prefix."_edges";
    $Anatomy::Schema::synonyms_table = $synonyms_table = $db_prefix."_synonyms";
    $Anatomy::Schema::xrefs_table = $xrefs_table = $db_prefix."_xrefs";
    $Anatomy::Schema::stats_table = $stats_table = $db_prefix."_stats";
    
    $schema = &Anatomy::Schema::relational();

    %db_tables = map { $_, 1 } keys %{ $schema };
    
    # Create directories and database if needed,

    &Common::File::create_dir_if_not_exists( $tab_dir );

    if ( not $cl_readonly )
    {
        if ( not &Common::DB::database_exists( $db_name ) )
        {
            &echo( qq (   Creating new database ... ) );
            
            &Common::DB::create_database( $db_name );
            sleep 1;
            
            &echo_green( "done\n" );
        }

        $dbh = &Common::DB::connect( $db_name );
    }

    # >>>>>>>>>>>>>>>>>> CHECK FILE MODIFICATION TIMES <<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there new downloads ... ) );

    $tab_time = &Common::File::get_newest_file_epoch( $tab_dir, '^$id_prefix' );
    $src_time = &Common::File::get_newest_file_epoch( $ont_dir, '^$id_prefix' );
    
    if ( $tab_time < $src_time )
    {
        &echo_green( "yes\n" );
    } 
    else
    {
        &echo_green( "no\n" );
        return unless $cl_force;
    }
    
    # >>>>>>>>>>>>>>>>>> DELETE OLD FILE TABLES IF ANY <<<<<<<<<<<<<<<<<<<

    if ( not $cl_readonly ) 
    {
        &echo( qq (   Are there old .tab files ... ) );
        
        if ( @files = grep { $_->{"name"} =~ /^$db_prefix/ } 
                  &Common::Storage::list_files( $tab_dir ) )
        {
            $count = 0;
            
            foreach $file ( @files )
            {
                &Common::File::delete_file( $file->{"path"} );
                $count++;
            }

            @files = ();
            &echo_green( "$count deleted\n" );
        }
        else {
            &echo_green( "no\n" );
        }
    }
        
    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE DEFINITIONS TABLE <<<<<<<<<<<<<<<<<<

    if ( $def_file )
    {
        if ( $cl_readonly ) {
            &echo( qq (   Parsing definitions ... ) );
        } else {
            &echo( qq (   Creating definitions .tab file ... ) );
        }
        
        $array = &Anatomy::Import::parse_defs( "$ont_dir/$def_file", $id_name, $id_prefix );
        
        &dump( $array );

        if ( not $cl_readonly )
        {
            $defs = { map { $_->{ $id_name }, $_ } @{ $array } };
            $array = [];
        }
    
        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE SYNONYMS TABLE <<<<<<<<<<<<<<<<<<

    if ( $syn_file )
    {
        if ( $cl_readonly ) {
            &echo( qq (   Parsing synonyms ... ) );
        } else {
            &echo( qq (   Creating synonyms .tab file ... ) );
        }
    
        $array = &Anatomy::Import::parse_synonyms( "$ont_dir/$syn_file", $id_name, $id_prefix );

        if ( not $cl_readonly )
        {
            foreach $elem ( @{ $array } )
            {
                push @table, [ $elem->{ $id_name }, $elem->{"name"}, $elem->{"syn"}, $elem->{"rel"} ];
            }
            
            &Common::Tables::write_tab_table( "$tab_dir/$synonyms_table.tab", \@table );
            
            $array = [];
            @table = ();
        }

        &echo_green( "done\n" );
    }
    
    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE ONTOLOGY TABLE <<<<<<<<<<<<<<<<<<
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing ontology ... ) );
    } else {
        &echo( qq (   Creating ontology .tab file ... ) );
    }                
            
    $edges = &Anatomy::Import::parse_ontology( "$ont_dir/$ont_file", $id_name, $id_prefix );

    if ( not $cl_readonly )
    {
        foreach $edge ( @{ $edges } )
        {
            foreach $parent ( @{ $edge->{"parents"} } ) {
                $int_nodes->{ $parent->[0] } = 1;
            }
        }                
        
        foreach $edge ( @{ $edges } )
        {
            if ( exists $int_nodes->{ $edge->{ $id_name } } ) {
                $edge->{"leaf"} = 0;
            } else {
                $edge->{"leaf"} = 1;
            }
        }

        &Anatomy::Import::print_edges_table( "$tab_dir/$edges_table.tab", $edges, $id_name, 1 );

        # Sometimes there are nodes in the ontology file that are not in 
        # the definitions file. The following "pads" the definitions, so 
        # ids and names are taken from the ontology file and put into the
        # definitions as well. 

        foreach $edge ( @{ $edges } )
        {
            if ( not exists $defs->{ $edge->{ $id_name } } )
            {
                $defs->{ $edge->{ $id_name } } = 
                {
                    $id_name => $edge->{ $id_name },
                    "name" => $edge->{"name"},
                    "deftext" => "",
                    "comment" => "",
                }
            }
        }

        foreach $id ( keys %{ $defs } )
        {
            $elem = $defs->{ $id };
            push @table, [ $elem->{ $id_name }, $elem->{"name"}, $elem->{"deftext"}, $elem->{"comment"} ];
        }

        &Common::Tables::write_tab_table( "$tab_dir/$def_table.tab", \@table );
        @table = ();
    }

    $defs = [];
    $edges = [];
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE REFERENCES TABLE <<<<<<<<<<<<<<<<<
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing cross-references ... ) );
    } else {
        &echo( qq (   Creating cross-references .tab file ... ) );
    }
    
    $array = &Anatomy::Import::parse_xrefs( "$ont_dir/$def_file", $id_name, $id_prefix );
    
    if ( not $cl_readonly )
    {
        foreach $elem ( @{ $array } ) 
        {
            push @table, [ $elem->{ $id_name }, $elem->{"db"}, $elem->{"name"} ];
        }
        
        &Common::Tables::write_tab_table( "$tab_dir/$xrefs_table.tab", \@table );
        @table = ();
    }
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>> LOAD DATABASE-READY TABLES <<<<<<<<<<<<<<<<<<<<

    if ( not $cl_readonly )
    {
        &echo( qq (   Loading database tables ... ) );
        
        foreach $table ( keys %db_tables )
        {
            &Common::DB::delete_table_if_exists( $dbh, $table );
            &Common::DB::create_table( $dbh, $table, $schema->{ $table } );
        }
        
        foreach $table ( keys %db_tables )
        {
            next if $table eq $stats_table;

            if ( $table eq $edges_table )
            {
                if ( not -r "$tab_dir/$table.tab" ) {
                    &error( qq (Input table missing -> "$tab_dir/$table.tab") );
                    exit;
                }
                
                &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
            }
            else
            {
                if ( not -r "$tab_dir/$table.tab" ) {
                    &error( qq (Input table missing -> "$tab_dir/$table.tab") );
                    exit;
                }
                
                &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
            }
        }
        
        &echo_green( "done\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>> ADDING INDICES <<<<<<<<<<<<<<<<<<<<<<
        
        &echo( qq (   Fulltext-indexing tables ... ) );
        
        &Common::DB::request( $dbh, "create fulltext index deftext_fndx on $def_table(deftext)" );
        &Common::DB::request( $dbh, "create fulltext index comment_fndx on $def_table(comment)" );
        &Common::DB::request( $dbh, "create fulltext index name_fndx on $def_table(name)" );
        
        &Common::DB::request( $dbh, "create fulltext index name_fndx on $synonyms_table(name)" );
        &Common::DB::request( $dbh, "create fulltext index syn_fndx on $synonyms_table(syn)" );

        &Common::DB::request( $dbh, "create fulltext index name_fndx on $xrefs_table(name)" );
        &Common::DB::request( $dbh, "create fulltext index db_fndx on $xrefs_table(db)" );
        
        &echo_green( "done\n" );
        
        &Common::DB::disconnect( $dbh );

        # >>>>>>>>>>>>>>>>>>>>>>> DELETE DATABASE TABLES <<<<<<<<<<<<<<<<<

        if ( not $cl_keep )
        {
            foreach $file ( keys %db_tables ) 
            {
                &Common::File::delete_file( "$tab_dir/$file" );
            }
        }
    }

    return;
}

sub load_ontology
{
    # Niels Larsen, October 2004.

    # Loads a single given anatomy ontology in the old DAG-edit format
    # with separate files. 

    my ( $ont_file,
         $syn_file,
         $def_file,
         $db_prefix,
         $id_prefix,
         $cl_readonly,   # Prints messages but does not load
         $cl_force,      # Reloads files even though database is newer
         $cl_keep,       # Avoids deleting database ready tables
         ) = @_;

    # Returns nothing.

    my ( $ont_dir, $tab_dir, @files, $tab_time, $src_time, $file, 
         $db_name, $dbh, $array, @table, $ref, $elem, $count, $edges,
         $edge, $table, $schema, $sql, $defs, $id, @defs_table, 
         $maps, $map, $int_nodes, $parent, $gen_dir, %db_tables,
         $def_table, $edges_table, $synonyms_table, $xrefs_table,
         $stats_table, $id_name );

    # >>>>>>>>>>>>>>>>> CHECKS AND INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<

    # Where to find the sources,

    $ont_dir = "$Common::Config::dat_dir/Anatomy/Ontologies";
    $tab_dir = "$Common::Config::dat_dir/Anatomy/Database_tables";

    if ( not -d $ont_dir ) {
        &error( "No ontology directory found", "MISSING DIRECTORY" );
    } elsif ( not grep { $_->{"name"} =~ /\.ontology$/ } &Common::Storage::list_files( $ont_dir ) ) {
        &error( "No source files found", "MISSING SOURCE FILES" );
    }
    
    # Database table names and ids,

    $Anatomy::Schema::db_prefix = $db_prefix;
    $Anatomy::Schema::id_name = $id_name = $db_prefix."_id";
    $Anatomy::Schema::def_table = $def_table = $db_prefix."_def";
    $Anatomy::Schema::edges_table = $edges_table = $db_prefix."_edges";
    $Anatomy::Schema::synonyms_table = $synonyms_table = $db_prefix."_synonyms";
    $Anatomy::Schema::xrefs_table = $xrefs_table = $db_prefix."_xrefs";
    $Anatomy::Schema::stats_table = $stats_table = $db_prefix."_stats";
    
    $schema = &Anatomy::Schema::relational();

    %db_tables = map { $_, 1 } keys %{ $schema };
    
    # Create directories and database if needed,

    &Common::File::create_dir_if_not_exists( $tab_dir );

    if ( not $cl_readonly )
    {
        if ( not &Common::DB::database_exists( $db_name ) )
        {
            &echo( qq (   Creating new database ... ) );
            
            &Common::DB::create_database( $db_name );
            sleep 1;
            
            &echo_green( "done\n" );
        }

        $dbh = &Common::DB::connect( $db_name );
    }

    # >>>>>>>>>>>>>>>>>> CHECK FILE MODIFICATION TIMES <<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are there new downloads ... ) );

    $tab_time = &Common::File::get_newest_file_epoch( $tab_dir, '^$id_prefix' );
    $src_time = &Common::File::get_newest_file_epoch( $ont_dir, '^$id_prefix' );
    
    if ( $tab_time < $src_time )
    {
        &echo_green( "yes\n" );
    } 
    else
    {
        &echo_green( "no\n" );
        return unless $cl_force;
    }
    
    # >>>>>>>>>>>>>>>>>> DELETE OLD FILE TABLES IF ANY <<<<<<<<<<<<<<<<<<<

    if ( not $cl_readonly ) 
    {
        &echo( qq (   Are there old .tab files ... ) );
        
        if ( @files = grep { $_->{"name"} =~ /^$db_prefix/ } 
                  &Common::Storage::list_files( $tab_dir ) )
        {
            $count = 0;
            
            foreach $file ( @files )
            {
                &Common::File::delete_file( $file->{"path"} );
                $count++;
            }

            @files = ();
            &echo_green( "$count deleted\n" );
        }
        else {
            &echo_green( "no\n" );
        }
    }
        
    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE DEFINITIONS TABLE <<<<<<<<<<<<<<<<<<

    if ( $def_file )
    {
        if ( $cl_readonly ) {
            &echo( qq (   Parsing definitions ... ) );
        } else {
            &echo( qq (   Creating definitions .tab file ... ) );
        }
        
        $array = &Anatomy::Import::parse_defs( "$ont_dir/$def_file", $id_name, $id_prefix );
        
        if ( not $cl_readonly )
        {
            $defs = { map { $_->{ $id_name }, $_ } @{ $array } };
            $array = [];
        }
    
        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE SYNONYMS TABLE <<<<<<<<<<<<<<<<<<

    if ( $syn_file )
    {
        if ( $cl_readonly ) {
            &echo( qq (   Parsing synonyms ... ) );
        } else {
            &echo( qq (   Creating synonyms .tab file ... ) );
        }
    
        $array = &Anatomy::Import::parse_synonyms( "$ont_dir/$syn_file", $id_name, $id_prefix );

        if ( not $cl_readonly )
        {
            foreach $elem ( @{ $array } )
            {
                push @table, [ $elem->{ $id_name }, $elem->{"name"}, $elem->{"syn"}, $elem->{"rel"} ];
            }
            
            &Common::Tables::write_tab_table( "$tab_dir/$synonyms_table.tab", \@table );
            
            $array = [];
            @table = ();
        }

        &echo_green( "done\n" );
    }
    
    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE ONTOLOGY TABLE <<<<<<<<<<<<<<<<<<
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing ontology ... ) );
    } else {
        &echo( qq (   Creating ontology .tab file ... ) );
    }                
            
    $edges = &Anatomy::Import::parse_ontology( "$ont_dir/$ont_file", $id_name, $id_prefix );

    if ( not $cl_readonly )
    {
        foreach $edge ( @{ $edges } )
        {
            foreach $parent ( @{ $edge->{"parents"} } ) {
                $int_nodes->{ $parent->[0] } = 1;
            }
        }                
        
        foreach $edge ( @{ $edges } )
        {
            if ( exists $int_nodes->{ $edge->{ $id_name } } ) {
                $edge->{"leaf"} = 0;
            } else {
                $edge->{"leaf"} = 1;
            }
        }

        &Anatomy::Import::print_edges_table( "$tab_dir/$edges_table.tab", $edges, $id_name, 1 );

        # Sometimes there are nodes in the ontology file that are not in 
        # the definitions file. The following "pads" the definitions, so 
        # ids and names are taken from the ontology file and put into the
        # definitions as well. 

        foreach $edge ( @{ $edges } )
        {
            if ( not exists $defs->{ $edge->{ $id_name } } )
            {
                $defs->{ $edge->{ $id_name } } = 
                {
                    $id_name => $edge->{ $id_name },
                    "name" => $edge->{"name"},
                    "deftext" => "",
                    "comment" => "",
                }
            }
        }

        foreach $id ( keys %{ $defs } )
        {
            $elem = $defs->{ $id };
            push @table, [ $elem->{ $id_name }, $elem->{"name"}, $elem->{"deftext"}, $elem->{"comment"} ];
        }

        &Common::Tables::write_tab_table( "$tab_dir/$def_table.tab", \@table );
        @table = ();
    }

    $defs = [];
    $edges = [];
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>> MAKE LOADABLE REFERENCES TABLE <<<<<<<<<<<<<<<<<
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing cross-references ... ) );
    } else {
        &echo( qq (   Creating cross-references .tab file ... ) );
    }
    
    $array = &Anatomy::Import::parse_xrefs( "$ont_dir/$def_file", $id_name, $id_prefix );
    
    if ( not $cl_readonly )
    {
        foreach $elem ( @{ $array } ) 
        {
            push @table, [ $elem->{ $id_name }, $elem->{"db"}, $elem->{"name"} ];
        }
        
        &Common::Tables::write_tab_table( "$tab_dir/$xrefs_table.tab", \@table );
        @table = ();
    }
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>> LOAD DATABASE-READY TABLES <<<<<<<<<<<<<<<<<<<<

    if ( not $cl_readonly )
    {
        &echo( qq (   Loading database tables ... ) );
        
        foreach $table ( keys %db_tables )
        {
            &Common::DB::delete_table_if_exists( $dbh, $table );
            &Common::DB::create_table( $dbh, $table, $schema->{ $table } );
        }
        
        foreach $table ( keys %db_tables )
        {
            next if $table eq $stats_table;

            if ( $table eq $edges_table )
            {
                if ( not -r "$tab_dir/$table.tab" ) {
                    &error( qq (Input table missing -> "$tab_dir/$table.tab") );
                    exit;
                }
                
                &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
            }
            else
            {
                if ( not -r "$tab_dir/$table.tab" ) {
                    &error( qq (Input table missing -> "$tab_dir/$table.tab") );
                    exit;
                }
                
                &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
            }
        }
        
        &echo_green( "done\n" );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>> ADDING INDICES <<<<<<<<<<<<<<<<<<<<<<
        
        &echo( qq (   Fulltext-indexing tables ... ) );
        
        &Common::DB::request( $dbh, "create fulltext index deftext_fndx on $def_table(deftext)" );
        &Common::DB::request( $dbh, "create fulltext index comment_fndx on $def_table(comment)" );
        &Common::DB::request( $dbh, "create fulltext index name_fndx on $def_table(name)" );
        
        &Common::DB::request( $dbh, "create fulltext index name_fndx on $synonyms_table(name)" );
        &Common::DB::request( $dbh, "create fulltext index syn_fndx on $synonyms_table(syn)" );

        &Common::DB::request( $dbh, "create fulltext index name_fndx on $xrefs_table(name)" );
        &Common::DB::request( $dbh, "create fulltext index db_fndx on $xrefs_table(db)" );
        
        &echo_green( "done\n" );
        
        &Common::DB::disconnect( $dbh );

        # >>>>>>>>>>>>>>>>>>>>>>> DELETE DATABASE TABLES <<<<<<<<<<<<<<<<<

        if ( not $cl_keep )
        {
            foreach $file ( keys %db_tables ) 
            {
                &Common::File::delete_file( "$tab_dir/$file" );
            }
        }
    }

    return;
}

sub parse_defs
{
    # Niels Larsen, October 2004.

    # Returns the content of the plant definitions file as an array
    # of hashes with keys "id", "name", "deftext" and "comment". The
    # "refs" key points to an array, the rest are scalars. 

    my ( $file,     # Full file path to the definitions file
         $id_name,
         $id_prefix,
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
        exit;
    }
    
    my ( $line, $term, $id, $deftext, $comment, @defs, 
         $suffix, $line_num, $fname );

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
        elsif ( $line =~ /^goid:\s*$id_prefix:(\d+)\s*$/ )
        {
            $id = $1 * 1;
        }
        elsif ( $line =~ /^definition:\s*(.+)\.?\s*$/ )
        {
            $deftext = $1;
            $deftext = "" if $deftext eq ".";
        }
        elsif ( $line =~ /^comment:\s*(.+)\.?\s*$/ )
        {
            $comment = $1;
        }
        elsif ( $line !~ /\w/ and $id ) {

            push @defs, 
            {
                $id_name => $id,
                "name" => $term,
                "deftext" => $deftext,
                "comment" => $comment,
            };

            $id = $term = $deftext = $comment = "";
        }
        elsif ( $line !~ /^!/ and $line !~ /^definition_reference:/ )
        {
            &warning( qq ($fname, line $line_num: could not parse line -> "$line") );
        }
    }

    # This is only done if there is no empty line at the bottom of the file,

    if ( $id )
    {
        push @defs, 
        {
            $id_name => $id,
            "name" => $term,
            "deftext" => $deftext,
            "comment" => $comment,
        }
    }

    close FILE;

    return wantarray ? @defs : \@defs;
}

sub parse_defs_obo
{
    # Niels Larsen, October 2004.

    # Parses the OBO file and returns an array of hashes with keys "id", 
    # "name", "deftext" and "comment". The "refs" key points to an array,
    # the rest are scalars. 

    my ( $file,     # Full file path to the definitions file
         $id_name,
         $id_prefix,
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
        exit;
    }
    
    my ( $line, $term, $id, $deftext, $comment, @defs, 
         $suffix, $line_num, $fname, $name );

    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        if ( $line =~ /^\[Term\]/ )
        {
            $line = <FILE>;
            $line_num++;

            $id = $name = $deftext = $comment = "";

            while ( defined ( $line = <FILE> ) )
            {
                if ( $line =~ /^id:\s*$id_prefix:(\d+)\s*$/ )
                {

            }


        if ( $line =~ /^term:\s*(.+)\s*$/ )
        {
            $term = $1;
        }
        elsif ( $line =~ /^goid:\s*$id_prefix:(\d+)\s*$/ )
        {
            $id = $1 * 1;
        }
        elsif ( $line =~ /^definition:\s*(.+)\.?\s*$/ )
        {
            $deftext = $1;
            $deftext = "" if $deftext eq ".";
        }
        elsif ( $line =~ /^comment:\s*(.+)\.?\s*$/ )
        {
            $comment = $1;
        }
        elsif ( $line !~ /\w/ and $id ) {

            push @defs, 
            {
                $id_name => $id,
                "name" => $term,
                "deftext" => $deftext,
                "comment" => $comment,
            };

            $id = $term = $deftext = $comment = "";
        }
        elsif ( $line !~ /^!/ and $line !~ /^definition_reference:/ )
        {
            &warning( qq ($fname, line $line_num: could not parse line -> "$line") );
        }
    }

    # This is only done if there is no empty line at the bottom of the file,

    if ( $id )
    {
        push @defs, 
        {
            $id_name => $id,
            "name" => $term,
            "deftext" => $deftext,
            "comment" => $comment,
        }
    }

    close FILE;

    return wantarray ? @defs : \@defs;
}

# [Term]
# id: CL:0000008
# name: cranial_neural_crest_cell
# is_a: CL:0000333

# [Term]
# id: CL:0000009
# name: fusiform_initial
# alt_id: CL:0000274
# def: "An elongated cell with approximately wedge-shaped ends\, found in the vascular cambium\, which gives rise to the elements of the axial system in the secondary vascular tissues." [ISBN:0471245208]
# synonym: "xylem mother cell" []
# synonym: "xylem_initial" []
# is_a: CL:0000272
# is_a: CL:0000610

sub parse_ontology
{
    # Niels Larsen, October 2004.

    # Reads an ontology flat file and creates an array of hashes where each 
    # hash has the keys "id", "name", "rel" and "parents". The value of "parents"
    # is a list of tuples of the form [ id, rel ]. 

    my ( $file,    # Ontology file path
         $id_name,
         $id_prefix,
         ) = @_;

    # Returns a hash. 

    my ( $line, $depth, $edges, @parent_ids, $id, $parent_id, $relation,
         @list, $elem, $name, @parents, @edges, $fname, $line_num );

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
        exit;
    }
    
    $line_num = 0;
    $fname = ( split "/", $file )[-1];

# $Mouse_anatomy_by_time_xproduct; EMAP:0
 #<TS1\,first polar body; EMAP:1
# <TS1\,one-cell stage; EMAP:2
# <TS1\,second polar body; EMAP:3


    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;
        chomp $line;

        next if $line !~ /\w/;

        if ( $line =~ /^(\s*)([%<~\$].+)$/ )
        {
            $depth = length $1;
            $line = $2;

            $line =~ s/;? synonym:[^%<~;]+[;]?//g;
            @list = ();

            while ( $line =~ /\s*([%<~\$])(.+?)\s*;\s*$id_prefix(?:_root)?:(\d+)/g )
            {
                $relation = $1;
                $name = $2;
                $id = $3;

                if ( $id !~ /^\d+$/ ) {
                    &warning( qq ($fname, line $line_num: $id_prefix id looks wrong -> "$id") );
                }

                push @list, [ $id*1, $name, $relation ];
            }

            ( $id, $name, $relation ) = @{ shift @list };

            if ( $depth == 0 )
            {
                push @edges,
                {
                    $id_name => $id,
                    "name" => $name,
                    "depth" => 0,
                    "parents" => [],
                };
            } 
            else
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
                    $id_name => $id,
                    "name" => $name,
                    "depth" => $depth,
                    "parents" => &Storable::dclone( \@parents ),
                };
            }

            $parent_ids[ $depth ] = $id;
        }
        elsif ( $line !~ /^!/ )
        {
            &warning( qq ($fname, line $line_num: line looks wrong -> "$line") );
        }
    }

    close FILE;

    return wantarray ? @edges : \@edges;
}

sub parse_synonyms
{
    # Niels Larsen, October 2004.

    # Extracts synonyms from the ontology file. Returns an array of 
    # [ id, name, syn, rel ]. The relation value either "related",
    # "exact", "broader", "narrower", "inexact" or "todo" (see gene
    # ontology documentation for more detail.) 

    my ( $file,     # Full file path to the ontology file
         $id_name,
         $id_prefix,
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }
    
    my ( $line, $id, $name, $fields, $field, $synonym, @synonyms, $fname, 
         $line_num );

    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        next if $line =~ /^!/;
        chomp $line;

        if ( $line =~ /^ *[%<~\$](.+?) ?; ?(?:$id_prefix):(\d+) ?; ?(.+)$/i )
        {
            $name = $1; 
            $id = $2 * 1;
            $fields = $3;

            $name =~ s/[\\]//g;

            if ( $id and $name )
            {
                while ( $line =~ /synonym:([^<~%;]+)/g )
                {
                    push @synonyms,
                    {
                        $id_name => $id,
                        "name" => $name,
                        "syn" => $1,
                        "rel" => "%",       # NOT USED
                    };
                }

                while ( $line =~ /abbrev:([^<~%;]+)/g )
                {
                    push @synonyms,
                    {
                        $id_name => $id,
                        "name" => $name,
                        "syn" => $1,
                        "rel" => "%",       # NOT USED
                    };
                }
            }
            elsif ( not defined $id ) {
                &warning( qq ($fname, line $line_num: no ID -> "$line") );
            } elsif ( not $name ) {
                &warning( qq ($fname, line $line_num: no name -> "$line") );
            }
        }                    
    }

    return wantarray ? @synonyms : \@synonyms;
}

sub parse_xrefs
{
    # Niels Larsen, October 2004.

    # Extracts cross-references from the definitions file. Returns
    # an array of [ id, db, name ].

    my ( $file,     # Full file path to the definitions file
         $id_name,
         $id_prefix,
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }
    
    my ( $line, $id, @refs, @allrefs, $prefix, $suffix, $line_num, 
         $fname, $elem );

    $id = "";
    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        if ( $line =~ /^goid:\s*$id_prefix:(\d+)\s*$/ )
        {
            $id = $1 * 1;
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
        elsif ( $line !~ /\w/ and $id )
        {
            foreach $elem ( @refs )
            {
                push @allrefs,
                {
                    $id_name => $id,
                    "db" => $elem->[0],
                    "name" => $elem->[1],
                };
            }

            $id = "";
            @refs = ();
        }
        elsif ( $line !~ /^!/ and $line !~ /^term:/ and $line !~ /^definition:/ and $line !~ /^comment/ )
        {
            &warning( qq ($fname, line $line_num: could not parse line -> "$line") );
        }
    }

    # This is only done if there is no empty line at the bottom of the file,

    if ( $id )
    {
        foreach $elem ( @refs )
        {
            push @allrefs,
            {
                $id_name => $id,
                "db" => $elem->[0],
                "name" => $elem->[1],
            };
        }
    }

    return wantarray ? @allrefs : \@allrefs;
}

sub print_edges_table
{
    # Niels Larsen, October 2004.
    
    # Creates the edges table from the edges hash created by the
    # parse_ontology routine. The table has four columns, see the 
    # schema. 

    my ( $file,          # Edges file path
         $edges,         # Edges array
         $id_name,
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

    %edges = map { $_->{ $id_name }, $_ } @{ $edges };

    foreach $id ( sort { $a <=> $b } keys %edges )
    {
        $parents = &Anatomy::Import::get_all_parents( $id, 1, \%edges );

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
    # Niels Larsen, October 2004.

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
            
            if ( $parents2 = &Anatomy::Import::get_all_parents( $parent_id, $dist+1, $edges ) )
            {
                $parents = { %{ $parents }, %{ $parents2 } };
            }
        }
    }
    
    return wantarray ? %{ $parents } : $parents;
}
 
sub log_errors
{
    # Niels Larsen, October 2004.
    
    # Appends a given list of messages to an ERRORS file in the 
    # PO/Import subdirectory. 

    my ( $errors,   # Error messages
         ) = @_;

    # Returns nothing.

    my ( $error, $log_dir, $log_file );

    $log_dir = "$Common::Config::log_dir/Anatomy/Import";
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
    # Niels Larsen, October 2004.

    # Creates a PO/Import subdirectory under the configured scratch
    # directory. The existence of this directory means PO data are
    # being loaded. 

    # Returns nothing. 

    &Common::File::create_dir( "$Common::Config::log_dir/Anatomy/Import" );

    return;
}

sub remove_lock
{
    # Niels Larsen, October 2004.
    
    # Deletes a PO/Import subdirectory from the configured scratch
    # directory. Errors are thrown if the directory is not empty or if
    # it could not be deleted. 

    # Returns nothing. 

    my $lock_dir = "$Common::Config::log_dir/Anatomy/Import";

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
    # Niels Larsen, October 2004.

    # Checks if there is an PO/Import subdirectory under the scratch
    # directory of the system. 

    # Returns nothing.

    my $lock_dir = "$Common::Config::log_dir/Anatomy/Import";

    if ( -e $lock_dir ) {
        return 1;
    } else {
        return;
    }
}

1;


__END__
