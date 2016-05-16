package DNA::DB;     #  -*- perl -*-

# Routines that fetch DNA related things out of the database. 
#
# The routines in here are not used at the moment, they are
# from an SQL based earlier EMBL install. But please dont 
# delete it.

use strict;
use warnings;

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_file_info
                 &database_exists
                 &delete_entries
                 &delete_entry
                 &delete_file_info
                 &exists_entry
                 &get_sequence
                 &list_files
                 &query_authors
                 &query_descriptions
                 &query_features
                 &query_keywords
                 &query_titles
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::DB;

use DNA::Schema;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_file_info
{
    # Niels Larsen, July 2003.

    # Loads information about a file into the table "files_loaded".
    # It is used to keep track of how far database building went in
    # case of a crash. The file information is that returned by the 
    # &Common::File::list_all routine. 

    my ( $dbh,     # Database handle
         $file,    # File information hash 
         $dist,    # Source origin - OPTIONAL, default "EMBL RELEASE"
         $table,   # Table name - OPTIONAL, default "files_loaded"
         ) = @_;

    # Returns nothing.

    $dist = "EMBL RELEASE" if not defined $dist;
    $table = "files_loaded" if not defined $table;

    my ( $schema, $key, $colstr, $valstr, $sql );
    
    if ( not &Common::DB::table_exists( $dbh, $table ) )
    {
        $schema = [
                   [ "dist", "text not null", "index dist_ndx (dist(20))" ],
                   [ "name", "varchar(255) not null", "index name_ndx (name)" ],
                   [ "path", "varchar(255) not null", "index path_ndx (path)" ],
                   [ "type", "char(1)", "index type_ndx (type)" ],
                   [ "uid", "smallint", "index uid_ndx (uid)" ],
                   [ "gid", "smallint", "index gid_ndx (gid)" ],
                   [ "size", "bigint", "index size_ndx (size)" ],
                   [ "mtime", "bigint", "index mtime_ndx (mtime)" ],
                   [ "perm", "varchar(10)", "index perm_ndx (perm)" ],
                   ];

        &Common::DB::create_table( $dbh, $table, $schema );
    }

    # Crash if this argument isnt right, because it is so critical,

    if ( ref $file eq "HASH" )
    {
        foreach $key ( "name", "path", "type", "uid", "gid", "size", "mtime", "perm" )
        {
            if ( not exists $file->{ $key } ) {
                &error( qq (Missing key in file hash -> "$key") );
            }
        }
    }
    else {
        &error( qq (Input file must be hash) );
    }

    $colstr = qq (dist);
    $valstr = qq ('$dist');

    foreach $key ( "name", "path", "type", "uid", "gid", "size", "mtime", "perm" )
    {
        $colstr .= ",$key";
        $valstr .= ",'$file->{ $key }'";
    }

    $sql = qq (insert into $table ($colstr) values ($valstr));

    &Common::DB::request( $dbh, $sql );

    return;
}

sub database_exists
{
    # Niels Larsen, December 2004.

    # Returns true if all tables from DNA::Schema->get
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
    
    foreach $table ( DNA::Schema->table_names )
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


sub delete_entries
{
    # Niels Larsen, July 2003.

    # Deletes a set of entries from the database, given by their IDs.
    # Bulk deletes are used, so it should have decent speed. 

    my ( $dbh,    # Database handle
         $ids,    # List of ids
         ) = @_;

    # Returns the number of entries deleted.

    $ids = [ $ids ] if not ref $ids;

    my ( $idstr, $sql, @ids, $table, $count );

    # The strategy is to first visit all tables where ent_id is a column 
    # and delete all rows where ent_id is among our ids. Next we visit the
    # tables that were normalized out and which dont have ent_id columns.
    # By joining we obtain these other ids and bulk-delete their rows. 
    
    $count = 0;

    # First get a non-redundant set of entry ids which are all in the database,

    $idstr = "'". (join "','", @{ $ids }) . "'";

    foreach $table ( "dna_organism", "dna_entry", "dna_organelle", "dna_molecule",
                     "dna_accession", "dna_ft_locations", "dna_reference", 
                     "dna_citation", "dna_seq_index" )
    {
        $sql = qq (select distinct ent_id from $table where ent_id in ($idstr));
        @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };
        $count += scalar @ids;        

        $idstr = "'". (join "','", @ids) . "'";
        $sql = qq (delete from $table where ent_id in ($idstr));

        &Common::DB::request( $dbh, $sql );
    }

    # Then get the rows from ft_qualifiers which now dont refer to any entry,

    $sql = qq (select distinct dna_ft_qualifiers.ft_id from dna_ft_qualifiers natural join dna_ft_locations )
         . qq (where dna_ft_qualifiers.ft_id=dna_ft_locations.ft_id and dna_ft_locations.ft_id is null);

    @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    if ( @ids )
    {
        $count += scalar @ids;
        $idstr = "'". (join "','", @ids) . "'";
        $sql = qq (delete from dna_ft_qualifiers where ft_id in ($idstr));
        &Common::DB::request( $dbh, $sql );
    }

    # Then delete the rows in ft_values which are not used anywhere,

    $sql = qq (select distinct dna_ft_values.val_id from dna_ft_values natural join dna_ft_qualifiers )
         . qq (where dna_ft_values.val_id=dna_ft_qualifiers.val_id and dna_ft_qualifiers.val_id is null);

    @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    if ( @ids )
    {
        $count += @ids;
        $idstr = "'". (join "','", @ids) . "'";
        $sql = qq (delete from dna_ft_values where val_id in ($idstr));
        &Common::DB::request( $dbh, $sql );
    }
    
    # Same with authors which were also normalized out,

    $sql = qq (select distinct dna_authors.aut_id from dna_authors natural join dna_reference )
         . qq (where dna_authors.aut_id=dna_reference.aut_id and dna_reference.aut_id is null);

    @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    if ( @ids )
    {
        $count += @ids; 
        $idstr = "'". (join "','", @ids) . "'";
        $sql = qq (delete from dna_authors where aut_id in ($idstr));
        &Common::DB::request( $dbh, $sql );
    }

    # Same with literature which was also normalized out,

    $sql = qq (select distinct dna_literature.lit_id from dna_literature natural join dna_reference )
         . qq (where dna_literature.lit_id=dna_reference.lit_id and dna_reference.lit_id is null);

    @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    if ( @ids )
    {
        $count += @ids; 
        $idstr = "'". (join "','", @ids) . "'";
        $sql = qq (delete from dna_literature where lit_id in ($idstr));
        &Common::DB::request( $dbh, $sql );
    }

    # Same with title which was also normalized out,

    $sql = qq (select distinct dna_title.tit_id from dna_title natural join dna_reference )
         . qq (where dna_title.tit_id=dna_reference.tit_id and dna_reference.tit_id is null);

    @ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    if ( @ids )
    {
        $count += @ids; 
        $idstr = "'". (join "','", @ids) . "'";        
        $sql = qq (delete from dna_title where tit_id in ($idstr));
        &Common::DB::request( $dbh, $sql );
    }

    return $count;
}

sub delete_entry
{
    # Niels Larsen, July 2003.

    # Deletes a single entry from the database. Since the delete involves
    # several queries and tables this function is quite slow, so dont use
    # it for more than a single or a few entries. Use delete_entries instead. 

    my ( $dbh,     # Database handle
         $id,      # Entry ID
         ) = @_;
    
    # Returns boolean or nothing.

    my ( $sql, $ft_ids, $val_ids, @refs, $aut_ids, $lit_ids, $tit_ids, $table, $list );

    # --------------- Get ids, 

    $sql = qq (select distinct ft_id from dna_ft_locations where ent_id = '$id');
    $ft_ids = join ",", map { $_->[0] } @{ &Common::DB::query_array( $dbh, $sql ) };

    $sql = qq (select distinct val_id from dna_ft_qualifiers where ft_id in ($ft_ids));
    $val_ids = join ",", ( map { $_->[0] } &Common::DB::query_array( $dbh, $sql ) );

    $sql = qq (select distinct aut_id,lit_id,tit_id from dna_reference where ent_id = '$id');
    @refs = &Common::DB::query_array( $dbh, $sql );

    $aut_ids = join ",", map { $_->[0] } @refs;
    $lit_ids = join ",", map { $_->[1] } @refs;
    $tit_ids = join ",", map { $_->[2] } @refs;

    # --------------- Then delete from tables where these ids occur,

    # ft_qualifiers, protein_id, db_xref,

    foreach $table ( "dna_ft_qualifiers", "dna_protein_id", "dna_db_xref" )
    {
        $sql = qq (delete from $table where ft_id in ($ft_ids));
        &Common::DB::request( $dbh, $sql );
    }
    
    # ft_values, 

    $sql = qq (delete from dna_ft_values where val_id in ($val_ids));
    &Common::DB::request( $dbh, $sql );

    # authors,

    $sql = qq (delete from dna_authors where aut_id in ($aut_ids));
    &Common::DB::request( $dbh, $sql );

    # literature,

    $sql = qq (delete from dna_literature where lit_id in ($lit_ids));
    &Common::DB::request( $dbh, $sql );

    # title,

    $sql = qq (delete from dna_title where tit_id in ($tit_ids));
    &Common::DB::request( $dbh, $sql );

    # organism, entry, organelle, molecule, accession, ft_locations, reference, citation, seq_index,

    foreach $table ( "dna_organism", "dna_entry", "dna_organelle", "dna_molecule", 
                     "dna_accession", "dna_ft_locations", "dna_reference", "dna_citation", "dna_seq_index" )
    {
        $sql = qq (delete from $table where ent_id = '$id');
        &Common::DB::request( $dbh, $sql );
    }
}

sub delete_file_info
{
    # Niels Larsen, July 2003.

    # Removed a file of a given name from a given table. 

    my ( $dbh,        # Database handle
         $name,       # File name
         $dist,       # Source origin - OPTIONAL, default "EMBL RELEASE"
         $table,      # Table name - OPTIONAL, default "files_loaded"
         ) = @_;

    # Returns nothing. 

    $table = "files_loaded" if not defined $table;

    my ( $sql );

    $sql = qq (delete from $table where dist = '$dist' and name = '$name');

    &Common::DB::request( $dbh, $sql );

    return;
}
         
sub exists_entry
{
    # Niels Larsen, July 2003.

    # Returns true if a given entry is present in the database, 
    # false otherwise. 

    my ( $dbh,
         $id,
         ) = @_;

    # Returns boolean. 

    my $sql = qq (select ent_id from dna_entry where ent_id = '$id');

    if ( @{ &Common::DB::query_array( $dbh, $sql ) } ) {
        return 1;
    } else {
        return 0;
    }
}

sub get_sequence
{
    # Niels Larsen, July 2003.

    # Fetches a sequence or sub-sequence from a given entry. From
    # a database table of begin and end positions in a fasta file
    # a simple seek is done to return the sequence string. If the
    # optional begin end positions (starting at 1) are given then 
    # part of the sequence is returned, so the memory doesnt 
    # overflow. 

    my ( $dbh,     # Database handle
         $id,      # ID of entry/contig
         $beg,     # Begin position in sequence - OPTIONAL
         $end,     # End position in sequence - OPTIONAL
         ) = @_;

    # Returns a string. 

    my ( $sql, $list, $seq, $i, $j, $db_name );

    $list = &Common::DB::query_array( $dbh, "select byte_beg,byte_end from dna_seq_index where ent_id = '$id'" );

    if ( $list and @{ $list } )
    {
        $i = $list->[0]->[0];
        $j = $list->[0]->[1];
        
        if ( $end )
        {
            $end--;
            $end = $j-$i if $end > $j-$i;
            $j = $i + $end;
        }
        
        if ( $beg )
        {
            $beg--;
            $beg = 0 if $beg < 0;
            $i += $beg;
        }
        
        # The incoming offsets are 1-based, so we subtract one,

        $db_name = $Common::Config::proj_name;
        $seq = &Common::File::seek_file( "$Common::Config::dat_dir/$db_name/DNA.fasta", $i-1, $j-$i+1 );

        return $seq;
    }
    else
    {
        return;
    }
}

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
