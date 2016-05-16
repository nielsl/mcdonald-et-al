package Disease::Import;     #  -*- perl -*-

# Disease Ontology import functions.
#
# TODO
#

use strict;
use warnings;

use Storable qw ( dclone );

use DBI;
use IO::File;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &schema
                 &load_all
                 &load_human
                 &parse_defs
                 &parse_ontology
                 &parse_synonyms
                 &parse_xrefs
                 &print_edges_table
                 &get_all_parents

                 &log_errors
                 &create_lock
                 &delete_lock
                 &is_locked
                  );

use Disease::Schema;

use Common::DB;
use Common::Storage;
use Common::Messages;
use Common::Tables;
use Common::File;
use Common::Config;
use Common::DAG::DB;


# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub load_all
{
    # Niels Larsen, October 2004.

    # Loads one or more disease files into a database. First the database 
    # tables are initialized, if they have not been. Then each release file
    # is parsed and saved into database-ready temporary files which are then
    # loaded - unless the "readonly" flag is given. 
    
    my ( $wants,           # Wanted file types
         $cl_readonly,     # Prints messages but does not load
         $cl_force,        # Reloads files even though database is newer
         $cl_keep,         # Avoids deleting database ready tables
         ) = @_;

    # Returns nothing.

    if ( $wants->{"all"} )
    {
        $wants->{"human"} = 1;
    }

    if ( $wants->{"human"} ) 
    {
        &Disease::Import::load_human( $cl_readonly, $cl_force, $cl_keep );
    }

    return;
}

sub load_human
{
    # Niels Larsen, October 2004.

    # Loads the Human Disease Ontology (Center for Genetic Medicine,
    # Northwestern University, Chicago) human disease into a database.

    my ( $cl_readonly,   # Prints messages but does not load
         $cl_force,      # Reloads files even though database is newer
         $cl_keep,       # Avoids deleting database ready tables
         ) = @_;

    # Returns nothing.

    my ( $ont_dir, $tab_dir, @files, $tab_time, $src_time, $file, 
         $db_name, $dbh, $array, @table, $prefix, $ref, $elem, $count, $edges,
         $edge, $table, $schema, $sql, $defs, $id, @defs_table, 
         $maps, $map, $int_nodes, $parent, $gen_dir, %db_tables );

    # >>>>>>>>>>>>>>>>> CHECKS AND INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<

    $ont_dir = "$Common::Config::dat_dir/Disease/Ontologies";
    $tab_dir = "$Common::Config::dat_dir/Disease/Database_tables";

    $schema = &Disease::Schema::relational;

    %db_tables = map { $_, 1 } keys %{ $schema };
    
    if ( not -d $ont_dir ) {
        &error( "No disease ontology directory found", "MISSING DIRECTORY" );
    } elsif ( not grep { $_->{"name"} =~ /\.ontology$/ } &Common::Storage::list_files( $ont_dir ) ) {
        &error( "No disease source files found", "MISSING SOURCE FILES" );
    }
    
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

    $tab_time = &Common::File::get_newest_file_epoch( $tab_dir );
    $src_time = &Common::File::get_newest_file_epoch( $ont_dir );
    
    if ( $tab_time < $src_time )
    {
        &echo_green( "yes\n" );
    } 
    else
    {
        &echo_green( "no\n" );
        return unless $cl_force;
    }
    
    # >>>>>>>>>>>>>>>>> PARSE AND CREATE DATABASE TABLES <<<<<<<<<<<<<<<<<

    # -------------- delete old database tables,
        
    if ( not $cl_readonly ) 
    {
        &echo( qq (   Are there old .tab files ... ) );
        
        if ( @files = &Common::Storage::list_files( $tab_dir ) )
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
    }
        
    # -------------- definitions,
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing definitions ... ) );
    } else {
        &echo( qq (   Creating definitions .tab file ... ) );
    }
    
    $array = &Disease::Import::parse_defs( "$ont_dir/DO.ontology" );

    if ( not $cl_readonly )
    {
        $defs = { map { $_->{"do_id"}, $_ } @{ $array } };
        $defs->{ 1 }->{"name"} = "Medical Disorder or Disease";

        @table = ();
        
        foreach $id ( keys %{ $defs } )
        {
            $elem = $defs->{ $id };
            push @table, [ $elem->{"do_id"}, $elem->{"name"}, $elem->{"deftext"}, $elem->{"comment"} ];
        }

        &Common::Tables::write_tab_table( "$tab_dir/do_def.tab", \@table );
    }
    
    &echo_green( "done\n" );

    # -------------- synonyms,
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing synonyms ... ) );
    } else {
        &echo( qq (   Creating synonyms .tab file ... ) );
    }
    
    $array = &Disease::Import::parse_synonyms( "$ont_dir/DO.ontology" );
    
    if ( not $cl_readonly )
    {
        @table = ();

        foreach $elem ( @{ $array } ) {
            push @table, [ $elem->{"do_id"}, $elem->{"name"}, $elem->{"syn"}, $elem->{"rel"} ];
        }
        
        &Common::Tables::write_tab_table( "$tab_dir/do_synonyms.tab", \@table );
        @table = ();
    }
    
    &echo_green( "done\n" );

    # --------------- ontology skeleton,
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing ontology ... ) );
    } else {
        &echo( qq (   Creating ontology .tab file ... ) );
    }                
            
    $edges = &Disease::Import::parse_ontology( "$ont_dir/DO.ontology" );

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
            if ( exists $int_nodes->{ $edge->{"do_id"} } ) {
                $edge->{"leaf"} = 0;
            } else {
                $edge->{"leaf"} = 1;
            }
        }
        
        &Disease::Import::print_edges_table( "$tab_dir/do_edges.tab", $edges, 1 );
    }
    
    $edges = [];
    
    &echo_green( "done\n" );

    # -------------- cross references,
    
    if ( $cl_readonly ) {
        &echo( qq (   Parsing cross-references ... ) );
    } else {
        &echo( qq (   Creating cross-references .tab file ... ) );
    }
    
    $array = &Disease::Import::parse_xrefs( "$ont_dir/DO.ontology" );
    
    if ( not $cl_readonly )
    {
        @table = ();

        foreach $elem ( @{ $array } ) {
            push @table, [ $elem->{"do_id"}, $elem->{"db"}, $elem->{"name"} ];
        }
        
        &Common::Tables::write_tab_table( "$tab_dir/do_xrefs.tab", \@table );
        @table = ();
    }
    
    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>> LOADING  DATABASE TABLES <<<<<<<<<<<<<<<<<<<<

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
            next if $table eq "do_stats";

            if ( $table eq "do_edges" )
            {
                if ( not -r "$tab_dir/$table.tab" ) {
                    &error( qq (Input table missing -> "$tab_dir/$table.tab") );
                    exit;
                }
                
                $sql = qq (insert into do_edges (do_id,parent_id,dist,depth,rel) values )
                     . qq ((1,"",0,0,""));
                
                &Common::DB::request( $dbh, $sql );

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
        
        # >>>>>>>>>>>>>>>>>>>>>> ADDING EXTRA INDEXES <<<<<<<<<<<<<<<<<<<<
        
        &echo( qq (   Fulltext-indexing tables ... ) );
        
        &Common::DB::request( $dbh, "create fulltext index deftext_fndx on do_def(deftext)" );
        &Common::DB::request( $dbh, "create fulltext index comment_fndx on do_def(comment)" );
        &Common::DB::request( $dbh, "create fulltext index name_fndx on do_def(name)" );
        
        &Common::DB::request( $dbh, "create fulltext index name_fndx on do_synonyms(name)" );
        &Common::DB::request( $dbh, "create fulltext index syn_fndx on do_synonyms(syn)" );

        &Common::DB::request( $dbh, "create fulltext index name_fndx on do_xrefs(name)" );
        &Common::DB::request( $dbh, "create fulltext index db_fndx on do_xrefs(db)" );
        
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

    # Extract disease definitions from the ontology release file. The
    # routine creates an array of hashes with keys that correspond to 
    # the field names in the do_def part of the schema (see the &schema
    # routine.)

    my ( $file,     # Full file path to the ontology file
         ) = @_;

    # Returns an array.

    if ( not open FILE, $file ) {
        &error( qq (Could not read-open "$file") );
    }
    
    my ( $line, $name, $id, @defs, $fname, $line_num );

    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        if ( $line =~ /^ *[%<\$](.+?) ?; ?(?:Id|Ic9DOID|DOID):(\d+)/i )
        {
            $name = $1; 
            $id = $2 * 1;

            $name =~ s/[\\]//g;

            push @defs, 
            {
                "do_id" => $id,
                "name" => $name,
                "deftext" => "",
                "comment" => "",
            };
        }
        elsif ( $line !~ /^!/ )
        {
            &warning( qq ($fname, line $line_num: could not parse line -> "$line") );
        }
    }

    return wantarray ? @defs : \@defs;
}

sub parse_ontology
{
    # Niels Larsen, October 2004.

    # Reads an ontology file and creates an array of hashes where each 
    # hash has the keys "do_id", "name", "rel" (relation, either "%" or "<" 
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

            while ( $line =~ /([%<\$])(.+?) ; (?:Id|Ic9DOID|DOID):(\d+)/g )
            {
                push @list, [ $3*1, $2, $1 ];
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
                    "do_id" => $id,
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

sub parse_synonyms
{
    # Niels Larsen, October 2004.

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
    
    my ( $line, $id, $name, $fields, $field, $synonym, @synonyms, $fname, 
         $line_num );

    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        next if $line =~ /^!/;
        chomp $line;
        
        if ( $line =~ /^ *[%<\$](.+?) ?; ?(?:Id|Ic9DOID|DOID):(\d+) ?; ?(.+)$/i )
        {
            $name = $1; 
            $id = $2 * 1;
            $fields = $3;

            $name =~ s/[\\]//g;

            if ( $id and $name )
            {
                foreach $field ( split / [;%] /, $fields )
                {
                    if ( $field =~ /^synonym:(.+)/ )
                    {
                        $synonym = $1;
                        $synonym =~ s/[\\]//g;
                        
                        push @synonyms,
                        {
                            "do_id" => $id,
                            "name" => $name,
                            "syn" => $synonym,
                            "rel" => "%",
                        };
                    }
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
    
    my ( $line, $id, $name, $fields, $field, $db, @xrefs, $fname, $line_num );

    $line_num = 0;
    $fname = ( split "/", $file )[-1];

    while ( defined ( $line = <FILE> ) )
    {
        $line_num++;

        next if $line =~ /^!/;
        chomp $line;
        
        if ( $line =~ /^ *[%<\$].+? ?; ?(?:Id|Ic9DOID|DOID):(\d+) ?; ?(.+)$/i )
        {
            $id = $1 * 1;
            $fields = $2;

            if ( defined $id )
            {
                foreach $field ( split / [;%] /, $fields )
                {
                    if ( $field =~ /^ICD9:(.+)/ )
                    {
                        $db = "ICD9";
                        $name = $1;
                        $name =~ s/\.$//;
                        $name =~ s/usitis\s*$//;
                        
                        if ( $name !~ /dbxref/i )
                        {
                            push @xrefs,
                            {
                                "do_id" => $id,
                                "db" => $db,
                                "name" => $name,
                            };
                        }
                    }
                }
            }
            else {
                &warning( qq ($fname, line $line_num: no ID -> "$line") );
            }
        }                    
    }

    return wantarray ? @xrefs : \@xrefs;
}

sub print_edges_table
{
    # Niels Larsen, October 2004.
    
    # Creates the do_edges table from the edges hash created by the
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

    %edges = map { $_->{"do_id"}, $_ } @{ $edges };

    foreach $id ( sort { $a <=> $b } keys %edges )
    {
        $parents = &Disease::Import::get_all_parents( $id, 1, \%edges );

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
            
            if ( $parents2 = &Disease::Import::get_all_parents( $parent_id, $dist+1, $edges ) )
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
