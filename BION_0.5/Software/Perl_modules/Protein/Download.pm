package Protein::Download;        # -*- perl -*- 

# Download-related routines for Protein databanks. 

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &download_databank
                 &prot_seq_refseq_list_release
                 &prot_seq_refseq_list_daily
                 &prot_seq_refseq_version
                 &prot_seq_refseq_version_local
                 &prot_seq_uniprot_list_release
                 &prot_seq_uniprot_version
                 &prot_seq_uniprot_version_local
                 );

use Common::Config;
use Common::Messages;

use Common::Storage;
use Common::HTTP;
use Common::Download;

use Seq::Download;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub download_databank
{
    # Niels Larsen, December 2007.

    # Routine that sets databank specific helper routines and then calls
    # Seq::Download->download_databank. The helper functions find files 
    # and versions of the release (and daily updates if any) of the local
    # and remote version. Returns a count of the files downloaded.

    my ( $class,
         $args,
        ) = @_;

    # Returns an integer. 

    my ( $dbname, $count, $conf, $routine );

    $args = &Registry::Args::check( $args, { 
        "S:1" => [ qw ( inplace dbname ) ],
    });

    $dbname = $args->dbname;

    $conf = {
        "dbname" => $dbname,
        "inplace" => $args->inplace,
        "version" => __PACKAGE__ ."::$dbname"."_version",
        "version_local" => __PACKAGE__ ."::$dbname"."_version_local",
        "list_release" => __PACKAGE__ ."::$dbname"."_list_release",
    };

    $routine = __PACKAGE__ ."::$dbname"."_list_daily";

    if ( Registry::Check->routine_exists( 
             {
                 "routine" => $routine,
                 "fatal" => 0,
             }) )
    {
        $conf->{"list_daily"} = $routine;
    } else {
        $conf->{"list_daily"} = "";
    }

    $count = Seq::Download->download_databank( $conf );

    return $count;
}

sub prot_seq_refseq_list_daily
{
    # Niels Larsen, December 2007. 

    # Lists Refseq daily release files at the remote end. 
    
    my ( $db,
        ) = @_;

    # Returns a list. 

    my ( $url, @all, @files );

    &echo("   Listing RefSeq remote daily update files ... " );

    $url = $db->downloads->baseurl ."/daily";

    @all = &Common::Storage::list_files( $url );

    @files = grep { $_->{"name"} =~ /gpff\.gz$/ } @all;

    push @files, grep { $_->{"name"} =~ /^README/ } @all;

    &echo_done( scalar @files );

    return wantarray ? @files : \@files;
}

sub prot_seq_refseq_list_release
{
    # Niels Larsen, June 2007.

    # Creates a file list of select RefSeq files at NCBI: the .seq.gz 
    # and .gbff.gz (in the wgs directory) and the readmes.

    my ( $db,
        ) = @_;

    # Returns a list.

    my ( $url, @files, @all );

    &echo("   Listing RefSeq remote release files ... " );

    {
        local $Common::Messages::silent = 1;
        
        $url = $db->downloads->baseurl ."/release";

        # Release file,
        
        @files = &Common::Storage::list_files( "$url/release-notes" );
        @files = grep { $_->{"name"} =~ /^RefSeq-release/ } @files;
        
        if ( @files ) {
            push @all, @files;
        } else {
            &error( qq (No release notes found) );
        }

        # Get all files starting with "complete" assuming everything is 
        # in those files,
        
        @files = &Common::Storage::list_files( "$url/complete" );
        @files = grep { $_->{"name"} =~ /gpff\.gz$/ } @files;
        
        if ( @files ) {
            push @all, @files;
        } else {
            &error( qq (No 'complete' release files found) );
        }
        
        # Whole genome shutgun files in one directory,
        
        $url = $db->downloads->baseurl ."/wgs";
        
        @files = &Common::Storage::list_files( $url );
        @files = grep { $_->{"name"} =~ /gpff\.gz$/ } @files;
        
        if ( @files ) {
            push @all, @files;
        } else {
            &error( qq (No shotgun release files found) );
        }
    }

    &echo_done( (scalar @all) ."\n" );

    return wantarray ? @all : \@all;
}

sub prot_seq_refseq_version
{
    # Niels Larsen, April 2008. 

    # Logs into Genbank's ftp site, looks for the version of the latest 
    # main release and returns the version number. 

    my ( $db,
        ) = @_;

    # Returns an integer. 

    my ( $url, @files, $version );

    $url = $db->downloads->baseurl;

    @files = &Common::Storage::list_files( "$url/release/release-notes" );
    @files = grep { $_->{"name"} =~ /^RefSeq-release/ } @files;

    $version = $files[0]->{"name"};

    if ( $version =~ /(\d+)\.txt$/ ) {
        $version = $1;
    } else {
        &error( qq (Could not extract version number from file name -> "$version") );
    }

    return $version;
}

sub prot_seq_refseq_version_local
{
    # Niels Larsen, June 2007.
    
    # Determines the main release version installed locally.

    my ( $db,
        ) = @_;

    # Returns an integer.

    my ( $dir, $version, @files, $file );

    $dir = $db->datapath_full ."/Downloads";

    if ( -e $dir )
    {
        @files = &Common::File::list_files( $dir, '^RefSeq-release' );

        if ( @files ) 
        {
            $file = $files[0]->{"name"};

            if ( $file =~ /(\d+)\.txt$/ ) {
                $version = $1;
            } else {
                &error( qq (Could not extract version number from file name -> "$file") );
            }
        }
    }

    if ( defined $version ) {
        return $version;
    } else {
        return;
    }
}

sub prot_seq_uniprot_list_release
{
    # Niels Larsen, August 2008.

    # Creates a file list of the main UniProt ftp release files.

    my ( $db,
        ) = @_;

    # Returns a list.

    my ( @all, @files );

    &echo("   Listing UniProt remote release files ... " );

    {
        local $Common::Messages::silent = 1;

        @files = &Common::Storage::list_files( $db->downloads->baseurl );
        @files = grep { $_->{"name"} eq "relnotes.txt" } @files;
        
        if ( @files ) {
            push @all, @files;
        } else {
            &error( qq (No release notes found) );
        }
        
        @files = &Common::Storage::list_files( $db->downloads->baseurl ."/knowledgebase/complete" );
        @files = grep { $_->{"name"} =~ /dat.gz$/ } @files;
        
        if ( @files ) {
            push @all, @files;
        } else {
            &error( qq (No knowledgebase release files found) );
        }

#     @files = &Common::Storage::list_files( $db->downloads->baseurl ."/unimes" );
#     @files = grep { $_->{"name"} eq "unimes.fasta.gz" } @files;

#     if ( @files ) {
#         push @all, @files;
#     } else {
#         &error( qq (No meta/env release files found) );
#     }
    }

    &echo_done( (scalar @all) ."\n" );
    
    return wantarray ? @all : \@all;
}

sub prot_seq_uniprot_version
{
    # Niels Larsen, August 2008.

    # Get current version number from UniProts ftp site. 

    my ( $db,
        ) = @_;

    # Returns an integer. 

    my ( $url, @files, $version, $content );

    $url = $db->downloads->baseurl;

    $content = ${ &Common::Storage::read_file( "$url/relnotes.txt" ) };

    if ( $content =~ /Release (\d+)[_\.](\d+)/ )
    {
        $version = "$1$2";
    } else {
        &dump( $content );
        &error( qq (Version number description must have changed) );
    }

    return $version;
}

sub prot_seq_uniprot_version_local
{
    # Niels Larsen, June 2007.
    
    # Determines the main release version installed locally.

    my ( $db,
        ) = @_;

    # Returns an integer.

    my ( $dir, $version, $content, $file );

    $dir = $db->datapath_full ."/Downloads";

    if ( -e $dir )
    {
        $file = "$dir/relnotes.txt";
        $content = ${ &Common::Storage::read_file( $file  ) };

        if ( $content =~ /^UniProt Release (\d+)[\._](\d+)/ )
        {
            $version = "$1$2";
        } else {
            &dump( $content );
            &error( qq (Could not extract version number from file name -> "$file") );
        }
    }

    if ( defined $version ) {
        return $version;
    } else {
        return;
    }
}

1;

__END__

# sub download_pfam
# {
#     # Niels Larsen, January 2006.

#     # Downloads files from the Pfam project. The remote files are checked 
#     # against local ones and files are gotten that are either missing or 
#     # outdated. A readonly flag makes the routine just return the number 
#     # of missing files, without doing any download. 

#     my ( $l_dir,       # Local base directory
#          $readonly,    # Switches off downloading if true 
#          ) = @_;

#     # Returns the number of files fetched or missing. 

#     my ( $uris, $r_dir, @r_files, $count );

#     $uris = &Common::Config::get_internet_addresses;
#     $count = 0;

#     # Main release files,

#     @r_files = &Common::Storage::list_files( $uris->{"pfam_release"} );

#     $count += &Common::Download::download_files( \@r_files, $l_dir, $readonly );

#     return $count;
# }

# sub download_swissprot_entry
# {
#     my ( $id,
#          ) = @_;

#     my ( $db, $entry );

#     require Bio::DB::SwissProt;

#     $db = new Bio::DB::SwissProt();

#     $entry = $db->get_Seq_by_acc( $id );

#     return $entry;
# }

# sub download_uniprot
# {
#     # Niels Larsen, January 2006.

#     # Downloads files from the UniProt project. The remote files 
#     # are checked against local ones and files are gotten that are either 
#     # missing or outdated. A readonly flag makes the routine just return 
#     # the number of missing files, without doing any download. 

#     my ( $l_dir,       # Local base directory
#          $readonly,    # Switches off downloading if true 
#          ) = @_;

#     # Returns the number of files fetched or missing. 

#     my ( $uris, $r_dir, @r_files, $count );

#     $uris = &Common::Config::get_internet_addresses;
#     $count = 0;

#     # Main release files,

#     @r_files = &Common::Storage::list_files( $uris->{"uniprot_release"} );

#     $count += &Common::Download::download_files( \@r_files, "$l_dir/Release", $readonly );

#     # Update files,

#     @r_files = &Common::Storage::list_files( $uris->{"uniprot_updates"} );

#     $count += &Common::Download::download_files( \@r_files, "$l_dir/Updates", $readonly );

#     return $count;
# }
