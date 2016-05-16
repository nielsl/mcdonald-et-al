package Install::Download;     #  -*- perl -*-

# Download routines that do dataset specific things.

use strict;
use warnings FATAL => qw ( all );

use Time::Local;
use Tie::IxHash;
use Data::Structure::Util;
use URI;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &ebi_genomes
                 &parse_ebi_genomes_list
                 &rna_seq_green
                 &rna_seq_rdp
                 &rna_seq_silva
                 );

use Common::Config;
use Common::Messages;

use Common::HTTP;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub ebi_genomes
{
    # Niels Larsen, August 2010.

    # Fetches genomes from EBI and saves each in Sources/taxid directories. 
    # Returns the number of genomes downloaded.

    my ( $db,
         $conf,
        ) = @_;

    # Returns integer. 

    my ( $url, @ebi_list, $line, $acc_no, $tax_id, $desc, 
         $src_dir, $tax_dir, $dodownload, @desc_list, $ebi_line, $desc_file,
         $count, $ebi_text, $ebi_file, $seq_file, $org_file, $org_name,
         $dat_dir, $ebi, %downloads, @org_names );

    $dat_dir = $conf->dat_dir;
    $src_dir = $conf->src_dir;

    # >>>>>>>>>>>>>>>>>>>>>>>>> GETTING EBI LISTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get EBI table list,

    &echo( qq (   Saving EBI descriptions list ... ) );

    # Get and save list from EBI,
    
    $url = $db->downloads->baseurl;
    $url = &Common::Names::replace_suffix( $url, ".details.txt" );

    $ebi_file = "$dat_dir/". $db->name .".table";
    &Common::File::delete_file_if_exists( $ebi_file );

    &Common::Storage::fetch_files_curl( $url, $ebi_file );

    # Parse saved EBI list and save to a YAML file,

    $ebi_text = ${ &Common::File::read_file( $ebi_file ) };
    @ebi_list = &Install::Download::parse_ebi_genomes_list( $ebi_text );

    $ebi_file = &Common::Names::replace_suffix( $ebi_file, ".yaml" );
    &Common::File::delete_file_if_exists( $ebi_file );

    &Common::File::write_yaml( $ebi_file, [ \@ebi_list ] );

    &echo_green( "done\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE DOWNLOADS LIST <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Create a list of downloads we do not have or for which the version number
    # differs with EBI,
            
    &echo( qq (   Listing files to be downloaded ... ) );

    tie %downloads, "Tie::IxHash";      # Preserves insertion order

    %downloads = ();
    $count = 0;
    
    foreach $ebi ( @ebi_list )
    {
        bless $ebi, "Common::Obj";

        $tax_id = $ebi->org_taxid;

        $desc_file = "$src_dir/$tax_id/DESCRIPTION.yaml";
        $org_file = "$src_dir/$tax_id/ORGANISM";

        if ( -s $desc_file ) # and -s $org_file )
        {
            $acc_no = $ebi->acc_number;
            @desc_list = map { bless $_, "Common::Obj" } @{ &Common::File::read_yaml( $desc_file ) };
            
            if ( not grep { $_->acc_number eq $acc_no } @desc_list or 
                 grep { $_->acc_number eq $acc_no and 
                        $_->ent_version != $ebi->ent_version } @desc_list )
            {
                push @{ $downloads{ $tax_id } }, &Storable::dclone( $ebi );
		$count += 1;
            }
	    
	    if ( not -s $org_file )
	    {
		@org_names = map { $_ =~ s/[,\s]+(mitochondrion|chromosome).*//; $_ } map { $_->description } @desc_list;
		$org_name = ( sort { length $a <=> length $b } @org_names )[0];
                
		&Common::File::delete_file_if_exists( $org_file );
		&Common::File::write_file( $org_file, "$org_name\n" );
	    }
        }
        else {
            push @{ $downloads{ $tax_id } }, &Storable::dclone( $ebi );
	    $count += 1;
        }
    }

    if ( $count > 0 ) {
        &echo_green( &Common::Util::commify_number( $count ) ."\n" );
    } else {
        &echo_green( "none\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DOWNLOAD GENOMES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $count = 0;

    foreach $tax_id ( keys %downloads )
    {
        foreach $ebi ( @{ $downloads{ $tax_id } } )
        {
            $desc = $ebi->description;
            $acc_no = $ebi->acc_number;

            $tax_dir = "$src_dir/$tax_id";
            $desc_file = "$src_dir/$tax_id/DESCRIPTION.yaml";
            $org_file = "$src_dir/$tax_id/ORGANISM";
            
            &echo( qq (   $desc (tax. id $tax_id) ... ) );
            
            &Common::File::create_dir_if_not_exists( $tax_dir );
            
            # Get the sequence file,
            
            $url = "http://www.ebi.ac.uk/ena/data/view/$acc_no&display=fasta&download&filename=$acc_no.fasta";
            $seq_file = "$tax_dir/$acc_no.fasta";
            
            &Common::File::delete_file_if_exists( $seq_file );
            
            &Common::Storage::fetch_files_curl( $url, $seq_file );
            
            # Update the descriptions file,
            
            if ( -r $desc_file ) {
                @desc_list = @{ &Common::File::read_yaml( $desc_file ) };
            } else {
                @desc_list = ();
            }
            
            @desc_list = grep { $_->acc_number ne $acc_no } @desc_list;
            push @desc_list, &Storable::dclone( &Data::Structure::Util::unbless( $ebi ) );
            
            &Common::File::write_yaml( $desc_file, [ \@desc_list ], 1 );
            
            # Save organism name if not done already,
            
            if ( not -s $org_file )
            {
                @org_names = map { $_ =~ s/[,\s]+(mitochondrion|chromosome).*//; $_ } map { $_->{"description"} } @desc_list;
                $org_name = ( sort { length $a <=> length $b } @org_names )[0];
                
                &Common::File::delete_file_if_exists( $org_file );
                &Common::File::write_file( $org_file, "$org_name\n" );
            }
            
            Registry::Register->set_timestamp( $tax_dir );
            
            &echo_green( "done\n" );
            
            $count += 1;
        }
    }
        
    return $count;
}

sub parse_ebi_genomes_list
{
    # Niels Larsen, August 2010.

    # Reads EBI's genome list from file and returns a list of objects with the 
    # fields acc_number, seq_version, ent_version, ent_epoch, org_taxid, description.
    
    my ( $text,    # File content
        ) = @_;

    # Returns a list.

    my ( @list, @line, $line, $obj );

    foreach $line ( split "\n", $text )
    {
        next if $line =~ /^#/;

        chomp $line;
        @line = split "\t", $line;

        if ( $line[0] =~ /^(.+)\.(\d+)$/ ) {
            ( $obj->{"acc_number"}, $obj->{"seq_version"} ) = ( $1, $2 );
        } else {
            &error( qq (Wrong looking accession -> "$line[0]") );
        }

        $obj->{"ent_version"} = $line[1];

        if ( $line[2] =~ /^(\d{4,4})(\d{2,2})(\d{2,2})$/ ) {
            $obj->{"ent_epoch"} = &Time::Local::timelocal( undef, undef, undef, $3, $2-1, $1-1900 );
        } else {
            &error( qq (Wrong looking date -> "$line[2]") );
        }
        
        $obj->{"org_taxid"} = $line[3];
        $obj->{"description"} = $line[4];

        push @list, &Storable::dclone( $obj );
    }

    return wantarray ? @list : \@list;
}

sub rna_seq_green
{
    # Niels Larsen, June 2012. 

    # Creates a list of names of files that are on Greengenes but not locally. Also 
    # resets the baseurl path in $db, because the Silva site does.

    my ( $db, 
         $conf,
        ) = @_;

    # Returns a list.

    my ( @exps, $links, @lfiles, @rfiles, $uri );

    $links = &Common::HTTP::get_html_links( $db->downloads->baseurl );
    @exps = map { $_->remote } @{ $db->downloads->files->options };

    @rfiles = &Common::Util::match_list( \@exps, $links );
    @rfiles = grep { $_ !~ /\.gz\.md5/ } @rfiles;

    if ( scalar @rfiles < scalar @exps ) {
        &error( qq (Dictionary expressions do not all match. Perhaps Secondgenome site site has changed.) );
    } elsif ( scalar @rfiles > scalar @exps ) {
        &error( qq (Too many matches with dictionary expressions. Perhaps Secondgenome site has changed.) );
    }

    @lfiles = map { $_->{"name"} } &Common::File::list_files( $conf->src_dir, "_gg_" );

    if ( @lfiles ) {
        @rfiles = &Common::Util::mismatch_list( \@lfiles, \@rfiles );
    }

    # $uri = "http://secondgenome1.s3.amazonaws.com/greengenes_reference_files";
    $uri = "https://s3.amazonaws.com:443/gg_sg_web"; 

    map { $_ =~ s/$uri\/// } @rfiles;

    $db->downloads->baseurl( $uri );

    if ( @rfiles ) {
        return wantarray ? @rfiles : \@rfiles;
    }

    return;
}

sub rna_seq_rdp
{
    # Niels Larsen, June 2012. 

    # Creates a list of names of files that are at RDP but not locally. Also 
    # resets the baseurl path in $db to the download url they use.

    my ( $db, 
         $conf,
        ) = @_;

    # Returns a list.

    my ( @exps, $links, @lfiles, @rfiles, $uri );

    $links = &Common::HTTP::get_html_links( $db->downloads->baseurl );

    @exps = map { $_->remote } @{ $db->downloads->files->options };

    @rfiles = &Common::Util::match_list( \@exps, $links );

    if ( scalar @rfiles < scalar @exps ) {
        &error( qq (Dictionary expressions do not all match. Perhaps RDP site has changed.) );
    } elsif ( scalar @rfiles > scalar @exps ) {
        &error( qq (Too many matches with dictionary expressions. Perhaps RDP site has changed.) );
    }

    @lfiles = map { $_->{"name"} } &Common::File::list_files( $conf->src_dir, '^release\d+' );

    if ( @lfiles ) {
        @rfiles = &Common::Util::mismatch_list( \@lfiles, \@rfiles );
    }

    @rfiles = map { ( split "/", $_ )[-1] } @rfiles;

    $uri = "http://rdp.cme.msu.edu/download";

    map { $_ =~ s/$uri\/// } @rfiles;

    $db->downloads->baseurl( $uri );

    #&dump( \@rfiles );
    #exit;
    
    if ( @rfiles ) {
        return wantarray ? @rfiles : \@rfiles;
    }

    return;
}

sub rna_seq_silva
{
    # Niels Larsen, June 2012. 

    # Creates a list of names of files that are on Silva but not locally. Also 
    # resets the baseurl path in $db, because the Silva site does.

    my ( $db, 
         $conf,
        ) = @_;

    # Returns a list.

    my ( @exps, $links, @lfiles, @rfiles, $uri );

    $links = &Common::HTTP::get_html_links( $db->downloads->baseurl );
    @exps = map { $_->remote } @{ $db->downloads->files->options };

    @rfiles = &Common::Util::match_list( \@exps, $links );

    if ( scalar @rfiles < scalar @exps ) {
        &error( qq (Dictionary expressions do not all match. Perhaps Silva site has changed.) );
    } elsif ( scalar @rfiles > scalar @exps ) {
        &error( qq (Too many matches with dictionary expressions. Perhaps Silva site has changed.) );
    }

    @lfiles = map { $_->{"name"} } &Common::File::list_files( $conf->src_dir, "^(SSU|LSU)" );

    if ( @lfiles ) {
        @rfiles = &Common::Util::mismatch_list( \@lfiles, \@rfiles );
    }

    @rfiles = map { ( split "/", $_ )[-1] } @rfiles;

    # Substitute Silva page paths with download paths .. why are they doing this .. 

    $uri = URI->new( $db->downloads->baseurl );
    $db->downloads->baseurl( $uri->scheme ."://". $uri->host ."/fileadmin/silva_databases/current/Exports" );

    if ( @rfiles ) {
        return wantarray ? @rfiles : \@rfiles;
    }

    return;
}

1;

__END__
