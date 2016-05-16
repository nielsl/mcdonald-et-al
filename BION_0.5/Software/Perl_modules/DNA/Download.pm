package DNA::Download;        # -*- perl -*- 

# Download-related routines for DNA databanks. 

use strict;
use warnings;
use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &download_databank
                 &download_embl
                 &download_genbank
                 &list_embl_daily
                 &list_embl_release
                 &list_genbank_daily
                 &list_genbank_release
                 &version_embl
                 &version_embl_local
                 &version_genbank
                 &version_genbank_local
                 );

use Common::Config;
use Common::Messages;

use Common::Storage;

use Registry::Args;
use Seq::Download;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# sub ebi_genomes
# {
#     my ( $class,
#          $args,
#         ) = @_;

#     &dump( $args );

#     &dump( "got here" );
#     exit;
#     return;
# }

sub download_embl
{
    my ( $class,
         $args,
        ) = @_;

    my ( $count, $conf );

    $args = &Registry::Args::check( $args, { 
        "S:1" => [ qw ( inplace ) ],
    });

    $conf = {
        "dbname" => "dna_seq_embl_local",
        "inplace" => $args->inplace,
        "version" => __PACKAGE__ ."::version_embl",
        "version_local" => __PACKAGE__ ."::version_embl_local",
        "list_release" => __PACKAGE__ ."::list_embl_release",
        "list_daily" => __PACKAGE__ ."::list_embl_daily",
    };

    $count = Seq::Download->download_databank( $conf );

    return $count;
}    

sub download_genbank
{
    my ( $class,
         $args,
        ) = @_;

    my ( $count, $conf );

    $args = &Registry::Args::check( $args, { 
        "S:1" => [ qw ( inplace ) ],
    });

    $conf = {
        "dbname" => "dna_seq_genbank_local",
        "inplace" => $args->inplace,
        "version" => __PACKAGE__ ."::version_genbank",
        "version_local" => __PACKAGE__ ."::version_genbank_local",
        "list_release" => __PACKAGE__ ."::list_genbank_release",
        "list_daily" => __PACKAGE__ ."::list_genbank_daily",
    };

    $count = Seq::Download->download_databank( $conf );

    return $count;
}

sub list_embl_daily
{
    # Niels Larsen, July 2007.

    # Returns a file list of all EMBL's daily update files.

    my ( $db,
        ) = @_;

    # Returns a list.

    my ( $url, @all, @files );

    &echo("   Listing EMBL remote daily update files ... " );

    $url = $db->downloads->baseurl;

    @all = &Common::Storage::list_files( "$url/new" );

    push @files, grep { $_->{"name"} =~ /^README/ } @all;
    push @files, grep { $_->{"name"} =~ /u\d+\.dat\.gz$/ } @all;

    &echo_green( scalar @files );

    return wantarray ? @files : \@files;
}

sub list_embl_release
{
    # Niels Larsen, June 2007.

    # Creates a file list of select EMBL release files: the .seq.gz 
    # and .gbff.gz (in the wgs directory) and the readmes.

    my ( $db,
        ) = @_;

    # Returns a list.

    my ( $url, @all, @files, @wgs, %wgs );

    &echo("   Listing EMBL remote release files ... " );

    $url = $db->downloads->baseurl;

    @all = &Common::Storage::list_files( "$url/release" );
    @all = grep { $_->{"name"} !~ /^rel_con/ } @all;

    push @files, grep { $_->{"name"} =~ /^Release_/ } @all;
    push @files, grep { $_->{"name"} =~ /\.txt$/ } @all;
    push @files, grep { $_->{"name"} =~ /\.dat.gz$/ } @all;

    # WGS files live in /wgs directory, are updated daily or frequently
    # and they replace those in the release directory with the same name.
    # So not to get the same project twice, eliminate the older from list,

    @wgs = &Common::Storage::list_files( "$url/wgs" );
    %wgs = map { $_->{"name"}, 1 } @wgs;

    @files = grep { not exists $wgs{ $_->{"name"} } } @files;
    push @files, @wgs;

    &echo_green( scalar @files );
        
    return wantarray ? @files : \@files;
}

sub list_genbank_daily
{
    # Niels Larsen, July 2007.

    # Returns a file list of all GenBank's daily update files.

    my ( $db,
        ) = @_;

    # Returns a list.

    my ( $url, @all, @files );

    &echo("   Listing GenBank remote daily update files ... " );

    $url = $db->downloads->baseurl ."/daily-nc";

    @all = &Common::Storage::list_files( $url );

    @files = grep { $_->{"name"} =~ /^nc\d{4,4}\.flat\.gz$/ } @all;

    push @files, grep { $_->{"name"} =~ /^README/ } @all;

    &echo_green( scalar @files );

    return wantarray ? @files : \@files;
}

sub list_genbank_release
{
    # Niels Larsen, June 2007.

    # Creates a file list of select Genbank files at NCBI: the .seq.gz 
    # and .gbff.gz (in the wgs directory) and the readmes.

    my ( $db,
        ) = @_;

    # Returns a list.

    my ( $url, @files, @wgs_files, @all );

    &echo("   Listing GenBank remote release files ... " );

    $url = $db->downloads->baseurl;

    @all = &Common::Storage::list_files( $url );

    @files = grep { $_->{"name"} =~ /\.seq\.gz$/ } @all;
    @files = grep { $_->{"name"} !~ /^gbcon/ } @files;

    push @files, grep { $_->{"name"} =~ /^README|GB_Release|gbrel\.txt/ } @all;

    @all = &Common::Storage::list_files( "$url/wgs" );

    @wgs_files = grep { $_->{"name"} =~ /\.gbff\.gz$/ } @all;
    push @wgs_files, grep { $_->{"name"} =~ /^README/ } @all;

    push @files, @wgs_files;

    &echo_green( scalar @files );
        
    return wantarray ? @files : \@files;
}

sub version_embl
{
    # Niels Larsen, April 2007. 

    # Returns the version number of the main release found at EMBL's
    # ftp site.

    my ( $db,
        ) = @_;

    # Returns an integer. 

    my ( $url, @files, $name, $version );

    $url = $db->downloads->baseurl ."/release";

    @files = &Common::Storage::list_files( $url );

    if ( @files = grep { $_->{"name"} =~ /^Release_/ } @files )
    {
        $name = $files[0]->{"name"};

        if ( $name =~ /^Release_(\d+)$/ ) {
            $version = $1;
        } else {
            &error( qq (Wrong looking version number -> "$name".) );
        }
    }
    else {
        &error( qq (No Release number file found) );
    }

    return $version;
}

sub version_embl_local
{
    # Niels Larsen, April 2007. 

    # Returns the version number of the EMBL installed locally.
    # If no local install, nothing is returned. 

    my ( $db,
        ) = @_;

    # Returns integer or nothing. 

    my ( $dir, @files );

    $dir = $db->datapath_full ."/Downloads";

    if ( -e $dir and
         @files = &Common::File::list_files( $dir, 'Release_\d+' ) and
         $files[0]->{"name"} =~ /^Release_(\d+)$/ )
    {
        return $1;
    } else {
        return;
    }
}

sub version_genbank
{
    # Niels Larsen, April 2007. 

    # Returns the version number of the main release found at GenBank's
    # ftp site.

    my ( $db,
        ) = @_;

    # Returns integer or nothing. 

    my ( $url, $version );

    $url = $db->downloads->baseurl;

    $version = ${ &Common::Storage::read_file( "$url/GB_Release_Number" ) };

    $version =~ s/^\s*//;
    $version =~ s/\s*$//;

    if ( $version !~ /^\d+$/ ) {
        &error( qq (Wrong looking version number -> "$version".) );
    }

    return $version;
}

sub version_genbank_local
{
    # Niels Larsen, June 2007.
    
    # Returns the version number of GenBank installed locally.
    # If no local install, nothing is returned. 

    my ( $db,
        ) = @_;

    # Returns integer or nothing.

    my ( $dir, $version, $file );

    $dir = $db->datapath_full ."/Downloads";

    $file = "$dir/GB_Release_Number";

    if ( -e $dir and -e $file )
    {
        $version = ${ &Common::Storage::read_file( $file ) };

        $version =~ s/^\s*//;
        $version =~ s/\s*$//;

        if ( $version !~ /^\d+$/ ) {
            &error( qq (Wrong looking version number -> "$version".) );
        }

        return $version;
    }
    else {
        return;
    }
}

1;

__END__
