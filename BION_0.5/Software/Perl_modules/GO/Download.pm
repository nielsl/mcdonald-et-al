package GO::Download;        # -*- perl -*- 

# Routines that are specific to the Gene Ontology updating process. 

use strict;
use warnings;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &download_go
                 );

use Common::Config;
use Common::Messages;
use Common::Storage;

# >>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub download_go
{
    # Niels Larsen, June 2007.
    
    # Downloads GO files, external mappings to GO and gene 
    # associations.
    
    my ( $db,          # Registry item
         $args,        # Arguments and switches
         ) = @_;

    # Returns an integer. 

    my ( $r_dir, $l_dir, @r_files, $count );

    $args = &Registry::Args::check( $args, { "S:1" => [ qw ( src_dir ) ] });

    $count = 0;

    $r_dir = $db->downloads->url;
    $l_dir = $args->src_dir;

    # Main files,

    @r_files = &Common::Storage::list_files( "$r_dir/ontology" );
    @r_files = grep { $_->{"name"} !~ /\.obo$/ } @r_files;

    $count += &Common::Download::download_files( \@r_files, "$l_dir/Ontologies" );

    # Synonyms,

    @r_files = &Common::Storage::list_files( "$r_dir/synonyms" );

    $count += &Common::Download::download_files( \@r_files, "$l_dir/Synonyms" );

    # Gene association files,

    @r_files = &Common::Storage::list_files( "$r_dir/gene-associations" );
    
    $count += &Common::Download::download_files( \@r_files, "$l_dir/Gene_maps" );

    # Mappings from other databases,

    @r_files = &Common::Storage::list_files( "$r_dir/external2go" );
    
    $count += &Common::Download::download_files( \@r_files, "$l_dir/Ext_maps" );

    return $count || 0;
}


1;

__END__
