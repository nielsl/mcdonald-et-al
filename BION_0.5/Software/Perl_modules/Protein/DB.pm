package Protein::DB;     #  -*- perl -*-

# Routines that fetch DNA related things out of the database. 

use strict;
use warnings;

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &get_sequence
                 &get_sequences
                 &get_synonyms
                 &get_annotation
                 &get_tax_ids
                 &get_ids
                 &query_functions
                 &query_ec_numbers
                  );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::DB;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub query_functions
{
    my ( $dbh,
         $text,
         ) = @_;

    my ( $sql, $matches );

    $sql = qq (select id,tax_id from fig_annotation where match(function) against('$text'));
    $matches = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $matches } : $matches;
}

sub query_ec_numbers
{
    my ( $dbh,
         $text,
         ) = @_;

    my ( $sql, $matches );

    if ( $text =~ /\%$/ ) {
        $sql = qq (select id,tax_id from fig_annotation where ec_number like '$text%');
    } else {
        $sql = qq (select id,tax_id from fig_annotation where ec_number = '$text');
    }
        
    $matches = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $matches } : $matches;
}

sub get_sequence
{
    # Niels Larsen, July 2003.

    # Fetches a sequence or sub-sequence for a given id. From 
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

    my ( $sql, $list, $seq, $i, $j );

    $list = &Common::DB::query_array( $dbh, "select byte_beg,byte_end from fig_seq_index where id = '$id'" );

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

    $seq = &Common::File::seek_file( "$Common::Config::dat_dir/FIG/fig_proteins.fasta", $i, $j-$i+1 );

    return $seq;
}

sub get_sequences
{
    # Niels Larsen, July 2003.

    # Fetches a sequence for each of a given list of ids. From 
    # a database table of begin and end positions in a fasta file
    # a simple seek is done to return the sequence string. If the
    # optional begin end positions (starting at 1) are given then 
    # part of the sequence is returned, so the memory doesnt 
    # overflow. A list of sequences is returned. 

    my ( $dbh,     # Database handle
         $ids,     # Sequence id list or sequence id
         $beg,     # Begin position in sequence - OPTIONAL
         $end,     # End position in sequence - OPTIONAL
         ) = @_;

    # Returns a list. 

    $ids = [ $ids ] if not ref $ids;

    my ( $idstr, $list, $elem, @seqs, $i, $j );

    $idstr = "'". (join "','", @{ $ids }) ."'";
    $list = &Common::DB::query_array( $dbh, "select byte_beg,byte_end from fig_seq_index where id in ($idstr)");

    foreach $elem ( @{ $list } )
    {
        $i = $elem->[0];
        $j = $elem->[1];

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
        
        push @seqs, &Common::File::seek_file( "$Common::Config::dat_dir/FIG/fig_proteins.fasta", $i, $j-$i+1 );
    }

    return wantarray ? @seqs : \@seqs;
}

1;


__END__
