package DNA::GenBank::Import;     #  -*- perl -*-

# GenBank specific parse and import related routines.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &extract_ids
                 &get_header_minimal
                 &split_entry
                 );

use Common::Messages;
use Common::Config;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub extract_ids
{
    # Niels Larsen, June 2007.

    # Returns ID, sequence version and GI number from a string that 
    # contains a Genbank-style flatfile entry.

    my ( $e_ref,        # Entry string reference.
        ) = @_;
 
    # Returns a list.

    my ( $id, $sv, $gi, $substr );

    if ( ${ $e_ref } =~ /VERSION\s+?(\S+)\s+?(\S+)/ )
    {
        ( $id, $gi ) = ( $1, $2 );

        if ( $id =~ /^(\w+)\.?(\d+)?$/ )
        {
            $id = $1;
            $sv = $2 || "";
        }

        $gi =~ s/^GI://;
    }
    else {
        $substr = substr ${ $e_ref }, 0, 100;
        &error( qq (Wrong looking entry header -> "$substr") );
    }
    
    return ( $id, $sv, $gi );
}

sub split_entry
{
    my ( $e_ref,
        ) = @_;

    my ( $beg, $hdrstr, $seqstr );

    $beg = index ${ $e_ref }, "\nORIGIN";

    $hdrstr = (substr ${ $e_ref }, 0, $beg + 7) . "       \n";
    
    $seqstr = substr ${ $e_ref }, $beg + 8;
    $seqstr =~ s/[\s0-9\/]+//go;

    return ( \$hdrstr, \$seqstr );
}

sub get_header_minimal
{
    my ( $args,
         $msgs,
        ) = @_;
    
    my ( $fpath, $acc, $lines, $i, $i_beg, $i_end, $entries, 
         $entry, $seq, $seqin, $builder, $fh, $cmd, $version,
         $species, $orgstr, $taxon );
    
    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( infile acc ) ],
        "S:0" => [ qw ( fatal ) ],
    });

    $fpath = $args->infile;
    $acc = $args->acc;

    if ( -e $fpath ) {
        $cmd = "$Common::Config::bin_dir/cat $fpath";
    } else {
        $cmd = "$Common::Config::bin_dir/zcat < $fpath.gz";
    }

#    $entries = &Common::OS::run_command( $cmd );
    $entries = `$cmd`;   # TODO

    while ( $entries =~ m|(LOCUS.+?//\n)|gs )
    {
        $entry = $1;
        last if $entry =~ m|\nACCESSION\s+$acc|s;
    }

    $fh = new IO::String( $entry );

    $seqin = Bio::SeqIO->new( -fh => $fh, -format => "genbank" );
    $builder = $seqin->sequence_builder();

    $builder->want_none();
    $builder->add_wanted_slot( 'accession_number', 'primary_id', 'version',
                               'display_id', 'desc', 'species' );

    $entry = $seqin->next_seq();

    $version = $entry->version || 1;         # Sometimes undefined

    $taxon = $entry->species;

    if ( $taxon ) {
        $species->{"name"} = $taxon->binomial;
    } else {
        $species->{"name"} = "";
    }

    $species->{"classification"} = [ reverse $taxon->classification ];
    $species->{"common_name"} = $taxon->common_name || "";

    $seq = Bio::Seq->new(
        -description => $entry->desc,
        -display_id => $entry->display_id .".$version",
        -primary_id => $entry->primary_id ,
        -accession_number => $entry->accession_number,
        -species => $species,
        -version => $version,
        );
    
    return $seq;
};

1;

__END__
