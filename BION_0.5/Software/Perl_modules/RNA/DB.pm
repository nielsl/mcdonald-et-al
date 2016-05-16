package RNA::DB;     #  -*- perl -*-

# Routines that add, delete and retrieve things from an RNA database.
# UNFINISHED 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &database_exists
                 &delete_entries_ids
                 &delete_entries_type
                 &delete_entry
                 &drop_tables
                 &entry_exists
                 &get_entry
                 &get_lengths
                 &get_locations
                 &get_max_id
                 &get_molecule
                 &get_organism
                 &get_origin
                 &get_row
                 &get_rows
                 &get_references
                 &get_sequence
                 &get_source
                 &get_types
                 &get_xrefs
                 &load_tables
                 &write_fasta
                 );

use Common::Config;
use Common::Messages;

use RNA::Schema;

use Common::File;
use Common::DB;
use Common::Util;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub database_exists
{
    # Niels Larsen, December 2004.

    # Returns true if all tables from RNA::Schema->get
    # exist in the database. 

    my ( $dbh,       # Database handle - OPTIONAL
         ) = @_;

    # Returns boolean. 

    my ( $table, $missing, $must_close );

    if ( not defined $dbh ) 
    {
        $dbh = &Common::DB::connect();
        $must_close = 1;
    }
    
    foreach $table ( RNA::Schema->get->table_names )
    {
        if ( not &Common::DB::table_exists( $dbh, $table ) )
        {
            $missing = 1;
            last;
        }
    }

    if ( $must_close ) {
        &Common::DB::disconnect( $dbh );
    }
    
    if ( not $missing ) {
        return 1;
    } else {
        return;
    }
}

sub delete_entries_ids
{
    # Niels Larsen, October 2006.

    # Deletes a set of entries from the database, given by their IDs. Deletes
    # are slow, but the routine tries to do its best: if the ids are over 50%
    # of the total, then "delete quick .. " is used and the indices rebuilt,
    # otherwise delete one by one. 

    my ( $dbh,    # Database handle
         $ids,    # List of ids
         ) = @_;

    # Returns an integer.

    my ( $idstr, $sql, @ids, $table, $i, $j, $count, $rows, $rebuild );

    $ids = [ $ids ] if not ref $ids;
    
    $count = 0;

    foreach $table ( RNA::Schema->get->table_names )
    {
        if ( &Common::DB::table_exists( $dbh, $table ) )
        {
            # Very long list if ids creates overflow, so we delete
            # 10000 at a time,

            $rows = &Common::DB::count_rows( $dbh, $table );
            $rebuild = scalar @{ $ids } > $rows / 2;

            $i = 0;
            
            while ( $i <= $#{ $ids } )
            {
                $j = &Common::Util::min( $i+9999, $#{ $ids } );
                $idstr = "'". (join "','", @{ $ids }[ $i..$j ] ) . "'";
        
                if ( $rebuild ) {
                    $sql = qq (delete quick from $table where rna_id in ($idstr));
                } else {
                    $sql = qq (delete from $table where rna_id in ($idstr));
                }

                $count += &Common::DB::request( $dbh, $sql );
                
                $i = $j + 1;
            }

            if ( $rebuild ) {
                &Common::DB::request( $dbh, "optimize table $table" );
            }
        }
    }

    return $count;
}

sub delete_entries
{
    # Niels Larsen, December 2004.

    # Deletes all entries of a given type. Returns the number of 
    # entries deleted.
    
    my ( $dbh,       # Database handle
         $source,    # RNA source string, e.g. "SSU_EMBL"
         $type,      # RNA type string, e.g. "rRNA_18S" - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( $where, $table, $sql, @ids, $count );
    
    # Get the ids that correspond to the entries from the given source
    # and optionally type,

    $where = "vendor = '$source'";

    if ( $type ) {
        $where .= " and type = '$type'";
    }

    $count = 0;

    if ( &Common::DB::table_exists( $dbh, "rna_origin" ) )
    {
        $sql = qq (select rna_id from rna_origin where $where);
        @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };
        
        $count += &RNA::DB::delete_entries_ids( $dbh, \@ids );
    }        

    return $count;
}

sub delete_entry
{
    # Niels Larsen, December 2004.

    # Deletes an entry given by its id from the database.

    my ( $dbh,     # Database handle
         $id,      # Entry ID
         ) = @_;
    
    # Returns nothing.

    &RNA::DB::delete_entries_ids( $dbh, [ $id ] );

    return;
}

sub drop_tables
{
    # Niels Larsen, December 2005.

    # Deletes all tables in the RNA schema.

    my ( $dbh,
         ) = @_;

    my ( $schema );

    $schema = RNA::Schema->get;

    &Common::DB::delete_tables( $dbh, $schema );

    return;
}

sub entry_exists
{
    # Niels Larsen, July 2003.

    # Returns true if a given entry is present in the database, 
    # false otherwise. 

    my ( $dbh,       # Database handle
         $id,        # Entry ID
         ) = @_;

    # Returns boolean. 

    my $sql = qq (select rna_id from rna_origin where rna_id = '$id');

    if ( @{ &Common::DB::query_array( $dbh, $sql ) } ) {
        return 1;
    } else {
        return 0;
    }
}

sub get_routines
{
    my ( $subs );

    $subs = 
    {
        "origin" => \&RNA::DB::get_origin,
        "organism" => \&RNA::DB::get_organism,
        "source" => \&RNA::DB::get_source,
        "molecule" => \&RNA::DB::get_molecule,
        "xrefs" => \&RNA::DB::get_xrefs,
        "references" => \&RNA::DB::get_references,
        "locations" => \&RNA::DB::get_locations,
    };

    return $subs;
}    

sub get_entry
{
    # Niels Larsen, January 2005.

    # Returns an RNA entry structure for a given id. The structure is 
    # hash where the 

    my ( $dbh,   # Database handle
         $id,    # Entry id
         ) = @_;

    # Returns a hash.

    my ( $schema, $entry, $subs, $table, $results );

    $schema = RNA::Schema->get;

    foreach $table ( $schema->table_names )
    {
        if ( $table eq "rna_origin" ) {
            $results = &RNA::DB::get_origin( $dbh, $id );
        } elsif ( $table eq "rna_organism" ) {
            $results = &RNA::DB::get_organism( $dbh, $id );
        } elsif ( $table eq "rna_source" ) {
            $results = &RNA::DB::get_source( $dbh, $id );
        } elsif ( $table eq "rna_molecule" ) {
            $results = &RNA::DB::get_molecule( $dbh, $id );
        } elsif ( $table eq "rna_xrefs" ) {
            $results = &RNA::DB::get_xrefs( $dbh, $id, $schema );
        } elsif ( $table eq "rna_references" ) {
            $results = &RNA::DB::get_references( $dbh, $id, $schema );
        } elsif ( $table eq "rna_locations" ) {
            $results = &RNA::DB::get_locations( $dbh, $id, $schema );
        } elsif ( $table ne "rna_features" ) {
            &error( qq (Strange table name -> "$table") );
            exit;
        }

        if ( $results )
        {
            if ( ref $results eq "ARRAY" and @{ $results } ) {
                $entry->{ $table } = $results;
            } elsif ( ref $results eq "HASH" and %{ $results } ) {
                $entry->{ $table } = $results;
            }
        }
    }

    return $entry;
}

sub get_lengths
{
    # Niels Larsen, January 2005.

    my ( $dbh,        # Database handle
         ) = @_;

    # Returns an array.
    
    my ( @lengths, $beg, $end, $range, $sql, $count );

    foreach $range ( [ 1, 100 ], [ 101, 200 ], [ 201, 300 ], 
                     [ 301, 500 ], [ 501, 700 ], [ 701, 1000 ],
                     [ 1001, 1200 ], [ 1201, 1400 ], [ 1401, 1600 ],
                     [ 1601, 2000 ], [ 2001, 2500 ], [ 2501, 5000 ] )
    {
        ( $beg, $end ) = @{ $range };

        $sql = qq (select count(rna_id) from rna_molecule where length >= $beg and length <= $end);
        $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

        push @lengths, [ $beg, $end, $count*1 ];
    }

    return wantarray ? @lengths : \@lengths;
}

sub get_locations
{
    # Niels Larsen, January 2005.

    # Fetches DNA and RNA positions of the molecule of a given RNA id. 

    my ( $dbh,    # Database handle
         $id,     # Entry id
         $schema, # Schema hash - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( @rows );

    @rows = &RNA::DB::get_rows( $dbh, "rna_locations", $id, $schema );

    return wantarray ? @rows : \@rows;
}

sub get_max_id
{
    # Niels Larsen, January 2005.

    # Returns the highest rna entry id.

    my ( $dbh,        # Database handle - OPTIONAL
         ) = @_; 

    # Returns an integer. 

    my ( $sql, $id, $must_close );

    if ( not defined $dbh ) 
    {
        $dbh = &Common::DB::connect();
        $must_close = 1;
    }

    $sql = qq (select max(rna_id) from rna_origin);

    $id = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

    if ( $must_close ) {
        &Common::DB::disconnect( $dbh );
    }

    return $id;
}

sub get_molecule
{
    # Niels Larsen, January 2005.

    # Fetches statistics and sequence, as defined by RNA::Schema->get. 

    my ( $dbh,    # Database handle
         $id,     # Entry id
         ) = @_;

    # Returns a hash.

    my ( $row );
    
    $row = &RNA::DB::get_row( $dbh, "rna_molecule", $id );

    return $row;
}

sub get_organism
{
    # Niels Larsen, January 2005.

    # Returns a record of molecule organism, as defined by RNA::Schema->get. 

    my ( $dbh,    # Database handle
         $id,     # Entry id
         ) = @_;

    # Returns a hash.

    my ( $row );
    
    $row = &RNA::DB::get_row( $dbh, "rna_organism", $id );

    return $row;
}

sub get_origin
{
    # Niels Larsen, January 2005.

    # Returns a record of record origin, as defined by RNA::Schema->get. 

    my ( $dbh,    # Database handle
         $id,     # Entry id
         ) = @_;

    # Returns a hash.

    my ( $row );
    
    $row = &RNA::DB::get_row( $dbh, "rna_origin", $id );

    return $row;
}

sub get_rows
{
    # Niels Larsen, January 2005.

    # Returns a list of row records for a given table and RNA id. 
    # Each record is a hash where the table fields are keys. Use 
    # this routine for tables where the same id is used for several 
    # rows, e.g. rna_references. 

    my ( $dbh,    # Database handle
         $table,  # Table name
         $id,     # Entry id
         $schema, # Schema structure - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( $sql, $row, @records, $i, %index );

    if ( not $schema ) {
        $schema = RNA::Schema->get;
    }

    $i = 0;
    %index = map { $_->[0], $i++ } $schema->table( $table )->columns;

    $sql = "select * from $table where rna_id = $id";

    foreach $row ( @{ &Common::DB::query_array( $dbh, $sql ) } )
    {
        push @records, { map { $_, $row->[ $index{ $_ } ] } keys %index };
    }
    
    return wantarray ? @records : \@records;
}

sub get_row
{
    # Niels Larsen, January 2005.

    # Returns a row record for a given table and RNA id. The record
    # is a hash where the table fields are keys. There may only 
    # a single record for a given id. 

    my ( $dbh,    # Database handle
         $table,  # Table name
         $id,     # Entry id
         ) = @_;

    # Returns a hash.

    my ( $sql, $record );

    $sql = "select * from $table where rna_id = '$id'";

    $record = &Common::DB::query_hash( $dbh, $sql, "rna_id" )->{ $id };

    return $record;
}

sub get_references
{
    # Niels Larsen, January 2005.

    # Returns a list of reference records for a given RNA id. 

    my ( $dbh,    # Database handle
         $id,     # Entry id
         $schema, # Schema hash - OPTIONAL
         ) = @_;

    # Returns a hash.

    my ( @rows );

    @rows = &RNA::DB::get_rows( $dbh, "rna_references", $id, $schema );

    return wantarray ? @rows : \@rows;
}

sub get_sequence
{
    # Niels Larsen, December 2004.

    # Fetches a sequence or sub-sequence from a given entry. 
    # Numbers are 1-based.

    my ( $dbh,     # Database handle
         $id,      # ID of entry/contig
         $beg,     # Begin position in sequence - OPTIONAL
         $end,     # End position in sequence - OPTIONAL
         ) = @_;

    # Returns a string. 

    my ( $sql, $seq );

    $sql = "select sequence from rna_molecule where rna_id = '$id'";
    $seq = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

    if ( $end ) {
        $seq = substr $seq, 0, $end;
    }

    if ( $beg ) {
        $seq = substr $seq, $beg-1;
    }        

    return $seq;
}

sub get_source
{
    # Niels Larsen, January 2005.

    # Returns a record of molecule source, as defined by RNA::Schema->get. 

    my ( $dbh,    # Database handle
         $id,     # Entry id
         ) = @_;

    # Returns a hash.

    my ( $row );
    
    $row = &RNA::DB::get_row( $dbh, "rna_source", $id );

    return $row;
}

sub get_types
{
    # Niels Larsen, January 2005.

    # Returns a list of the RNA types in the database. Each type is a tuple
    # of [ database key, display name ], e.g. [ 'rRNA_18S', 'SSU RNA' ].

    my ( $dbh,     # Database handle
         ) = @_;

    # Returns a list.

    my ( $sql, @types, $type );

    $sql = qq (select distinct type from rna_origin);
    
    @types = map { [ $_->[0], $_->[0] ] } &Common::DB::query_array( $dbh, $sql );

    foreach $type ( @types )
    {
        if ( $type->[0] eq "rRNA_18S" ) {
            $type->[1] = "SSU RNA";
        }
    }

    return wantarray ? @types : \@types;
}

sub get_xrefs
{
    # Niels Larsen, January 2005.

    # Returns a list of database cross references, as defined by RNA::Schema->get. 

    my ( $dbh,    # Database handle
         $id,     # Entry id
         $schema, # Schema hash - OPTIONAL
         ) = @_;

    # Returns an array.

    my ( @rows );
    
    @rows = &RNA::DB::get_rows( $dbh, "rna_xrefs", $id, $schema );

    return wantarray ? @rows : \@rows;
}

sub load_tables
{
    # Niels Larsen, December 2004.
    
    # Loads a set of data tables into an RNA database, defined by 
    # RNA::Schema->get. First the database tables are initialized,
    # if they have not been. 

    my ( $dbh,        # Database handle
         $args,    # Commmand line arguments hash
         ) = @_;

    # Returns nothing.

    my ( $tab_dir, $schema, $count, $rna_type, $rna_source, $table, $text_index, 
         @missing, $missing );

    $tab_dir = $args->{"tab_dir"};
    $rna_type = $args->{"type"};
    $rna_source = $args->{"source"};

    $schema = RNA::Schema->get;

    # >>>>>>>>>>>>>>>>>>> CHECK ALL TABLES ARE PRESENT <<<<<<<<<<<<<<<<<<<<

    # Before we load, check that all files are there,

    &echo( qq (   Are all table files present ... ) );
    
    $count = 0;

    foreach $table ( $schema->table_names )
    {
        if ( not -r "$tab_dir/$table.tab" )
        {
            push @missing, "$table.tab";
        }
    }

    if ( scalar @missing == 0 ) {
        &echo_green( "yes\n" );
    } else
    {
        &echo_red( "NO\n" );

        $missing = '"'. (join '" and "', @missing) .'"';
        &error( "The tables $missing were missing. Please resolve this." );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>> PROCESS EXISTING DATABASE <<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::DB::database_exists() )
    {
        if ( &RNA::DB::database_exists( $dbh ) )
        {
            if ( $args->{"delete"} )
            {
                # Delete tables if requested,

                &echo( qq (   Deleting whole RNA database ... ) );
                &RNA::DB::drop_tables( $dbh );
                &echo_green( "done\n" );
            }
            elsif ( $args->{"replace"} )
            {
                # Delete records if requested,

                &echo( qq (   Deleting $rna_type records ... ) );
                $count = &RNA::DB::delete_entries( $dbh, $rna_source, $rna_type );
                $count = &Common::Util::commify_number( $count || 0 );
                &echo_green( "$count deleted\n" );
            }
        }
        
        # Initialize database if needed,

        if ( not &RNA::DB::database_exists( $dbh ) )
        {
            &echo( qq (   Initializing RNA database tables ... ) );
            &Common::DB::create_tables( $dbh, $schema ) and sleep 1;
            &echo_green( "done\n" );

            $text_index = 1;
        }
    }
    else
    {
        # Create database if needed,
    
        &echo( qq (   Creating new database ... ) );
        &Common::DB::create_database() and sleep 1;
        &echo_green( "done\n" );

        $text_index = 1;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>> LOAD AND INDEX TABLES <<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->{"replace"} or $args->{"delete"} ) {
        &echo( qq (   Loading tables into database ... ) );
    } else {
        &echo( qq (   Adding tables to database ... ) );
    }        
    
    foreach $table ( $schema->table_names )
    {
        &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
    }
    
    &echo_green( "done\n" );

#     if ( $text_index )
#     {
#         &echo( qq (   Creating full-text indices ... ) );
    
#         &Common::DB::request( $dbh, "create fulltext index src_de_fndx on rna_origin (src_de)" );
#         &Common::DB::request( $dbh, "create fulltext index src_kw_fndx on rna_origin (src_kw)" );
        
#         &Common::DB::request( $dbh, "create fulltext index cell_line_fndx on rna_source (cell_line)" );
#         &Common::DB::request( $dbh, "create fulltext index cell_type_fndx on rna_source (cell_type)" );
#         &Common::DB::request( $dbh, "create fulltext index clone_fndx on rna_source (clone)" );
#         &Common::DB::request( $dbh, "create fulltext index clone_lib_fndx on rna_source (clone_lib)" );
#         &Common::DB::request( $dbh, "create fulltext index sub_clone_fndx on rna_source (sub_clone)" );
#         &Common::DB::request( $dbh, "create fulltext index dev_stage_fndx on rna_source (dev_stage)" );
#         &Common::DB::request( $dbh, "create fulltext index environmental_sample_fndx on rna_source (environmental_sample)" );
#         &Common::DB::request( $dbh, "create fulltext index isolate_fndx on rna_source (isolate)" );
#         &Common::DB::request( $dbh, "create fulltext index isolation_source_fndx on rna_source (isolation_source)" );
#         &Common::DB::request( $dbh, "create fulltext index lab_host_fndx on rna_source (lab_host)" );
#         &Common::DB::request( $dbh, "create fulltext index label_fndx on rna_source (label)" );
#         &Common::DB::request( $dbh, "create fulltext index note_fndx on rna_source (note)" );
#         &Common::DB::request( $dbh, "create fulltext index organelle_fndx on rna_source (organelle)" );
#         &Common::DB::request( $dbh, "create fulltext index plasmid_fndx on rna_source (plasmid)" );
#         &Common::DB::request( $dbh, "create fulltext index specific_host_fndx on rna_source (specific_host)" );
#         &Common::DB::request( $dbh, "create fulltext index tissue_fndx on rna_source (tissue)" );
#         &Common::DB::request( $dbh, "create fulltext index tissue_lib_fndx on rna_source (tissue_lib)" );
#         &Common::DB::request( $dbh, "create fulltext index tissue_type_fndx on rna_source (tissue_type)" );
        
#         &Common::DB::request( $dbh, "create fulltext index authors_fndx on rna_references (authors)" );
#         &Common::DB::request( $dbh, "create fulltext index literature_fndx on rna_references (literature)" );
#         &Common::DB::request( $dbh, "create fulltext index title_fndx on rna_references (title)" );
        
#         &echo_green( "done\n" );
#     }
        
    return;
}

sub write_fasta
{
    # Niels Larsen, November 2005.

    # Writes sequences from RNA database to fasta file. If a type is given,
    # like "rRNA_18S", then only that RNA is written. 

    my ( $dbh,        # Database handle
         $file,       # Output file
         $type,       # RNA type, like "rRNA_18S"
         $minlen,     # Minimum sequence length
         ) = @_;

    # Returns nothing. 

    my ( $fh, $sql, @ids, $id, $seq, $org, $count );

    $fh = &Common::File::get_write_handle( $file );

    if ( $type ) {
        $sql = qq (select rna_id from rna_origin where type = "$type");
    } else {
        $sql = qq (select rna_id from rna_origin);
    }

    @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };
    $count = 0;

    if ( $minlen )
    {
        foreach $id ( @ids )
        {
            $org = &RNA::DB::get_organism( $dbh, $id );
            $seq = &RNA::DB::get_sequence( $dbh, $id );
         
            if ( length $seq > $minlen )
            {
                $fh->print( qq (>$id; $org->{"tax_id"}; $org->{"name"}\n$seq\n) );
                $count += 1;
            }
        }
    }
    else
    {
        foreach $id ( @ids )
        {
            $org = &RNA::DB::get_organism( $dbh, $id );
            $seq = &RNA::DB::get_sequence( $dbh, $id );
         
            $fh->print( qq (>$id; $org->{"tax_id"}; $org->{"name"}\n$seq\n) );
            $count += 1;
        }
    }
        
    &Common::File::close_handle( $fh );

    return $count;
}

1;

__END__ 

sub list_files
{
    # Niels Larsen, July 2003.

    # Lists information about files that have been loaded into the 
    # database. Returned is a list of hashes similar to those returned
    # by &Common::File::list_files. 

    my ( $dbh,     # Database handle
         $dist,    # Source origin - OPTIONAL, default "EMBL RELEASE"
         $table,   # Table name - OPTIONAL, default "files_loaded"
         ) = @_;

    # Returns an array.

    $dist = "EMBL RELEASE" if not defined $dist;
    $table = "files_loaded" if not defined $table;

    my ( $sql, @files, $file );

    if ( &Common::DB::table_exists( $dbh, $table ) )
    {
        $sql = qq (select * from $table where dist = '$dist');
        
        foreach $file ( sort { $a->[1] cmp $b->[1] } 
                        &Common::DB::query_array( $dbh, $sql ) )
        {
            push @files,
            {
                "name" => $file->[1],
                "path" => $file->[2],
                "type" => $file->[3],
                "uid" => $file->[4],
                "gid" => $file->[5],
                "size" => $file->[6],
                "mtime" => $file->[7],
                "perm" => $file->[8],
            };
        }
    }
    else
    {
        @files = ();
    }

    return wantarray ? @files : \@files;
}

sub query_authors
{
    my ( $dbh,
         $text,
         ) = @_;

    my ( $sql, @ids, $idstr, $matches );

    $sql = qq (select distinct ent_id from dna_reference natural join dna_authors )
         . qq (where match(dna_authors.text) against('$text'));

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    $idstr = "'". (join "','", @ids) . "'";
    $sql = qq (select tax_id,ent_id from dna_organism where ent_id in ($idstr));

    $matches = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $matches } : $matches;
}

sub query_descriptions
{
    my ( $dbh,
         $text,
         ) = @_;

    my ( $sql, @ids, $idstr, $matches );

    $sql = qq (select dna_organism.tax_id,dna_organism.ent_id from dna_organism )
         . qq (natural join dna_entry where match(dna_entry.description) against('$text'));

    $matches = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $matches } : $matches;
}

sub query_features
{
    my ( $dbh,
         $text,
         ) = @_;

    my ( $sql, @ids, $idstr, $matches );

    $sql = qq (select ft_id from dna_ft_qualifiers natural join dna_ft_values where match(val) against('$text'));
    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    $idstr = "'". (join "','", @ids) . "'";
    $sql = qq (select dna_organism.tax_id,dna_organism.ent_id from dna_organism )
         . qq (natural join dna_ft_locations where dna_ft_locations.ft_id in ($idstr));

    $matches = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $matches } : $matches;
}

sub query_keywords
{
    my ( $dbh,
         $text,
         ) = @_;

    my ( $sql, @ids, $idstr, $matches );

    $sql = qq (select dna_organism.tax_id,dna_organism.ent_id from dna_organism )
         . qq (natural join dna_entry where match(dna_entry.keywords) against('$text'));

    $matches = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $matches } : $matches;
}

sub query_titles
{
    my ( $dbh,
         $text,
         ) = @_;

    my ( $sql, @ids, $idstr, $matches );

    $sql = qq (select distinct ent_id from dna_reference natural join dna_title )
         . qq (where match(dna_title.text) against('$text'));

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    $idstr = "'". (join "','", @ids) . "'";
    $sql = qq (select tax_id,ent_id from dna_organism where ent_id in ($idstr));

    $matches = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $matches } : $matches;
}

1;


__END__
