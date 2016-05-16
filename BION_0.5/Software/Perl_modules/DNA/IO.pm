package DNA::IO;                # -*- perl -*-

# DNA specific IO routines.

use strict;
use warnings FATAL => qw ( all );

use base qw ( Seq::IO );

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Class methods that read DNA or RNA records, either from databanks or
# from single indexed files. They are "wrappers" to routines in Seq::IO.
# 
# get_seq
# get_seq_split
# get_seq_remote
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $DB_path = Registry::Get->dataset("dna_seq_embl_local")->datapath_full;
our $DB_type = "dna_seq";

our $Dir_levels = 2;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get_seq
{
    # Niels Larsen, May 2007.

    # Fetches a DNA/RNA sequence entry by its id from a single locally 
    # installed file or databank. If not there, gets from a remote 
    # repository. Accepted formats are accession numbers, with or without
    # version number, i.e. "accession.version". This is the main accessor
    # function to use. 

    my ( $id,        # Entry ID
         $args,      # Arguments hash - OPTIONAL
         $msgs,      # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a bioperl Seq::IO object.

    my ( $seq );

    $args = {} if not defined $args;

    if ( $args->{"dbfile"} )
    {
        $seq = &Seq::IO::get_seq_indexed( $id, $args, $msgs );
    }
    else
    {
        if ( not $seq = &DNA::IO::get_seq_split( $id, { %{ $args }, "fatal" => 0 }, $msgs ) )
        {
            &dump( "remote" );
            $seq = &DNA::IO::get_seq_remote( $id, { %{ $args }, "fatal" => 0 }, $msgs );
        }
        
        if ( not $seq and $args->{"fatal"} ) {
            &error( qq (Could not get entry for id -> "$id") );
        }
    }

    if ( $args->{"reverse"} ) {
        $seq->revcom;
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
    $args->{"dbpath"} = $DB_path;

    $args->{"dir_levels"} = $Dir_levels;
    $args->{"header_sub"} = "DNA::EMBL::Import::get_header_minimal";

    require DNA::EMBL::Import;

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

    
