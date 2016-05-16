package Protein::IO;     #  -*- perl -*-

# Routines that read and write Protein sequence.

use strict;
use warnings;
use feature qw ( :5.10 );

use Common::Config;
use Common::Messages;

use Bit::Vector;
use DNA::GenBank::Import;
use Protein::Uniprot::Import;

use base qw ( Seq::IO );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Class methods that gets protein sequences. either from databanks or
# from single indexed files. They are "wrappers" to routines in Seq::IO.
#
# get_seq
# get_seq_split
# get_seq_remote
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $DB_type = "prot_seq";

our %DB_paths = (
		 "uniprot" => Registry::Get->dataset("prot_seq_uniprot")->datapath_full,
		 "refseq" => Registry::Get->dataset("prot_seq_refseq")->datapath_full,
		 );

our %Header_subs = (
		    "uniprot" => "Protein::Uniprot::Import::get_header_minimal",
		    "refseq" => "DNA::GenBank::Import::get_header_minimal",
		    );

our $Dir_levels = 2;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub _set_routines
{
    my ( $type,
        ) = @_;

    my ( $names, $dbs, $db, %routines, $routine, $args );
    
    $names = Registry::Register->registered_datasets();

    $dbs = Registry::Get->datasets( $names )->match_options( "datatype" => "prot_seq" );
    
    if ( $dbs )
    {
        foreach $db ( @{ $dbs } )
        {
            if ( -r $db->datapath_full ."/Installs/SEQS.dbm" ) 
            {
                $routine = "get_seq";
                $args = { "fatal" => 0 };
            }
            else 
            {
                $routine = "get_seq_split";
                $args = { "fatal" => 0 };
            }

            $routines{ $db->name } = [ $routine, $args ];
        }
    }
    else
    {
        $routines{"remote"} = "get_seq_remote";
    }

    return wantarray ? %routines : \%routines;
}
    
sub header_sub
{
    my ( $id,
	 ) = @_;

    my ( $sub );

    if ( $id =~ /^[A-Z]{1,3}_/ ) {
	$sub = $Header_subs{"refseq"};
    } elsif ( $id =~ /^[A-Z0-9]+\.\d+$/ ) {
	$sub = $Header_subs{"uniprot"};
    } else {
	&error( qq (Wrong looking id -> "$id") );
    } 

    return $sub;
}

sub db_path 
{
    my ( $id,
	 ) = @_;

    my ( $path );

    if ( $id =~ /^[A-Z]{1,3}_/ ) {
	$path = $DB_paths{"refseq"};
    } elsif ( $id =~ /^[A-Z0-9]+\.\d+$/ ) {
	$path = $DB_paths{"uniprot"};
    } else {
	&error( qq (Wrong looking id -> "$id") );
    } 

    return $path;
}

sub get_seq
{
    # Niels Larsen, May 2007.

    # Fetches a protein sequence entry from a locally indexed file or 
    # a locally installed databank, and if not there, from NCBI. The ID's
    # given must be accession numbers, with or without version number, 
    # i.e. "accession.version". 

    my ( $id,        # Entry ID
         $args,      # Arguments hash
         $msgs,      # Outgoing messages
         ) = @_;

    # Returns a bioperl Seq::IO object.

    my ( $seq );

    state $routines = Protein::IO->_set_routines("prot_seq");

    &dump( $routines );
    exit;

    $args = {} if not defined $args;

    if ( $args->{"dbfile"} )
    {
        $seq = &Seq::IO::get_seq_indexed( $id, $args, $msgs );
    }
    else
    {
        if ( not $seq = &Protein::IO::get_seq_split( $id, { %{ $args }, "fatal" => 0 }, $msgs ) )
        {
            $seq = &Protein::IO::get_seq_remote( $id, { %{ $args }, "fatal" => 0 }, $msgs );
        }
        
        if ( not $seq and $args->{"fatal"} ) {
            &error( qq (Could not get entry for id -> "$id") );
        }
    }

    if ( $seq ) {
        return $seq;
    } else {
        return;
    }
}

sub get_seq_split
{
    my ( $id,
         $args,
         $msgs,
        ) = @_;

    my ( $seq, $subref );

    $args->{"dbtype"} = $DB_type;
    $args->{"dbpath"} = &Protein::IO::db_path( $id );

    $args->{"dir_levels"} = $Dir_levels;
    $args->{"header_sub"} = &Protein::IO::header_sub( $id );

    $seq = &Seq::IO::get_seq_split( $id, $args, $msgs );

    return $seq;
}

sub get_seq_remote
{
    my ( $id,
         $args,
         $msgs,
        ) = @_;

    my ( $seq );

    $args->{"dbtype"} = $DB_type;

    $seq = &Seq::IO::get_seq_remote( $id, $args, $msgs );

    return $seq;
}

1;

__END__

    
