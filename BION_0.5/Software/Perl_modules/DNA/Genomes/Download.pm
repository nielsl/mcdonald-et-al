package DNA::Genomes::Download;        # -*- perl -*- 

# Routines that are specific to the Genome downloading process. 

use strict;
use warnings;

use Data::Dumper;
use Storable qw ( dclone );
use Cwd;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_distinct_projects
                 &diff_projects
                 &download_all
                 &get_baylor_microbes_info
                 &get_jgi_microbes_info
                 &get_ncbi_microbes_info
                 &get_oklahoma_microbes_info
                 &get_sanger_microbes_info
                 &get_tigr_microbes_info
                 &get_wustl_microbes_info
                 &list_file_properties
                 &list_local_project
                 &list_local_projects
                 &parse_org_name
                 &repair_projects_info
                 &same_data_files
                 &same_genus_species
                 &same_org_description
                 &template
                 &update_local_project
                 &write_log
                 );

use Common::HTTP;
use Common::OS;
use Common::Names;
use Common::Storage;
use Common::Config;
use Common::Messages;
use HTML::TreeBuilder;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub make_project_name
{
    my ( $project,
         ) = @_;

    my ( $name );

    $name = $project->{"genus"};

    $name .= " ". $project->{"species"} if $project->{"species"};
    $name .= " ". $project->{"subspecies"} if $project->{"subspecies"};
    $name .= " (". $project->{"strain"} if $project->{"strain"} .")";

    return $name;
}

sub update_existing_project
{
    my ( $r_project,
         $l_matches,
         $readonly,
         $errors,
         ) = @_;

    my ( $outstr, $i, $l_project, $proj_diffs, $template, $count, $r_name, $l_name,
         $message, $diff_flag );

    if ( scalar @{ $l_matches } > 1 )
    {
        $r_name = &DNA::Genomes::download::make_project_name( $r_project );
        $message = qq (Remote project has same datafiles:\n);
        $message = qq ((remote): $r_name\n);
        
        foreach $l_project ( @{ $l_matches } )
        {
            $l_name = &DNA::Genomes::download::make_project_name( $l_project );
            $message = qq ( (local): $l_name\n);
        }
        
        &error( qq ($message) );
        exit;
    }
                
    $l_project = $l_matches->[0];

    $r_project->{"local_dir"} = $l_project->{"local_dir"};
    $r_project->{"local_path"} = $l_project->{"local_path"};

    $template = &DNA::Genomes::Download::template();

    $proj_diffs = &DNA::Genomes::Download::diff_projects( $r_project, $l_project, $template );

    $outstr = "   (". $r_project->{"from_site"}->[0]->[0] ."): ". $r_project->{"genus"};
    $outstr .= " $r_project->{'species'}" if $r_project->{'species'};
    $outstr .= " (". $l_project->{"version"} .") ... ";
    
    &echo( $outstr );
    
    if ( $readonly ) 
    {
        if ( $proj_diffs )
        {
            if ( $proj_diffs->{"downloads"} ) {
                &echo_yellow( qq (data differs) );
            } else {
                &echo_yellow( qq (description differs) );
            }
        }
        else {
            &echo_green( qq (same) );
        }    
    }
    else
    {
        if ( $proj_diffs )
        {
            &DNA::Genomes::Download::update_local_project( $r_project->{"local_path"}, $proj_diffs, $errors );
            $diff_flag = 1;
            
            if ( $proj_diffs->{"downloads"} ) {
                &echo_yellow( qq (data updated) );
            } else {
                &echo_yellow( qq (description updated) );
            }
        }
        else {
            &echo_green( qq (same) );
        }            
    }
    
    if ( not @{ $r_project->{"downloads"} } )
    {
        &echo( ", " );
        &echo_yellow( qq (no data) );
    }
    
    &echo( "\n" );
        
    if ( $diff_flag ) {
        return $diff_flag;
    } else {
        return;
    }
}

sub create_new_project
{
    my ( $folder,
         $r_project,
         $l_projects,
         $readonly,
         $errors,
         ) = @_;

    my ( @projects, @versions, $max_version, $version, $outstr, $i );

    @projects = grep { &DNA::Genomes::Download::same_genus_species( $r_project, $_ ) } @{ $l_projects };
    
    if ( @projects )
    {
        @versions = sort { $a <=> $b } map { $_->{"version"} } @projects;
        $max_version = $versions[-1];
        
        if ( $max_version > scalar @versions )
        {
            for ( $i = 0; $i < scalar @versions; $i++ )
            {
                $version = $versions[$i];
                
                if ( $version > $i+1 ) {
                    $version = $i+1;
                    last;
                }
            }
        }
        else {
            $version = $max_version + 1;
        }
    }
    else {
        $version = 1;
    }
    
    $r_project->{"version"} = $version;
    
    $r_project->{"local_dir"} = $r_project->{"genus"} ."_". ($r_project->{"species"} || "") . ".$version";
    $r_project->{"local_path"} = "$folder/$r_project->{'local_dir'}";
    
    $outstr = "   (". $r_project->{"from_site"}->[0]->[0] ."): ". $r_project->{"genus"};
    $outstr .= " $r_project->{'species'}" if $r_project->{'species'};
    $outstr .= " ($version) ... ";
    
    &echo( $outstr );
    
    if ( $readonly ) 
    {
        &echo_green( qq (new) );
    }
    else
    {
        &DNA::Genomes::Download::update_local_project( $r_project->{"local_path"}, $r_project, $errors );
        &echo_green( qq (created) );
    }
    
    &echo( "\n" );

    return;
}


sub new_projects
{
    # Niels Larsen, August 2003.

    # Finds the projects in a given list that are different from those in 
    # given reference list and then appends them to the reference list.

    my ( $projs1,          # Reference list of projects
         $projs2,          # Projects to be examined
         ) = @_;

    # Returns an array of projects.

    my ( $proj, @new_projects );

    foreach $proj ( @{ $projs2 } )
    {
        # If the data files have same names and sizes, then thats usually because
        # they are mirrored by different sites; in that case we keep the first one
        # encountered. If different names and sizes, and different organism 
        # description, then add it. If different names and sizes, but same organism
        # description, ignore it and take the first project encountered. 

        if ( not grep { &DNA::Genomes::Download::same_data_files( $proj, $_ ) } @{ $projs1 } and 
             not grep { &DNA::Genomes::Download::same_org_description( $_, $proj ) } @{ $projs1 } )
        {
            push @new_projects, &Storable::dclone( $proj );
        }
    }

    if ( @new_projects ) {
        return wantarray ? @new_projects : \@new_projects;
    } else {
        return;
    }
}

sub download_all
{
    # Niels Larsen, Bo Mikkelsen, January 2004.
    
    my ( $folder,     # Download folder
         $sites,      # Comma separated string of numbers
         $readonly,   # Readonly flag
         $restart,    # Restart flag
         ) = @_;

    # Returns nothing.

    $folder = &Cwd::abs_path( $folder );

    &Common::File::create_dir_if_not_exists( $folder );
    
    my ( @sites, $site,
         @r_projects, @projects, $project, @info, $count, $errors, $dir, @l_sources, 
         @r_sources, $org_name, $strain, $template, $downloads, $download, $r_dir, $r_files,
         @r_extra, @l_extra, $l_file, $r_file, $r_path, $l_path, $r_project, %r_files,
         $org_dir, @l_projects, $file, @content, @downloads, $l_dir, $version, $i, $j,
         $genus, $species, $instname, $file_name, $row, $val, $text, $got_cache, $content,
         $proj_diffs, $l_project, $l_projects, @versions, $max_version, @new_projects,
         $outstr, $space_needed, $space_free, $space_total, @last_download,
         $r_total, $l_total, $message, $full_pct, $full_pct_f, @projects_all,
         $key, $value, @l_matches, $l_name, $r_name, $update_count, $new_count );

    # >>>>>>>>>>>>>>>>>> GET PROJECT INFORMATION <<<<<<<<<<<<<<<<<<<<<<

    # This section visits web sites and gathers summary information about
    # genome projects. The information is put into a hash like that below.
    # To add more sites you must create get_xxxx_info routines that return 
    # lists of hashes like this; many fields can be left empty. 

    $template = &DNA::Genomes::Download::template();

    @r_projects = ();

    # --------- Read summary information about previous download,

    if ( $restart and -r "$folder/last_download.info" )
    {
        &echo( qq (   Reading about previous download ... ) );
        @r_projects = @{ &Common::File::eval_file( "$folder/last_download.info" ) };
        &echo_green( "done\n" );
    }
    else
    {
        @sites = split ",", $sites;

        foreach $site ( @sites )
        {
            # --------- Oklahoma microbes,

            if ( $site == 1 )
            {
                &echo( qq (   Finding Oklahoma microbes (patience) ... ) );
                
                @projects = &DNA::Genomes::Download::get_oklahoma_microbes_info( $errors );
                @projects = &DNA::Genomes::Download::repair_projects_info( \@projects, $template );
                
                $count = scalar @projects;
                &echo_green( "$count" );
                
                if ( $count = scalar grep { not @{ $_->{"downloads"} } } @projects )
                {
                    &echo( ", " );
                    &echo_yellow( "$count no data" );
                }
                
                &echo( "\n" );
                
                push @projects_all, @projects;

                if ( @new_projects = &DNA::Genomes::Download::new_projects( \@r_projects, \@projects ) )
                {
                    push @r_projects, @new_projects;
                }
            }
            
            # --------- WUSTL microbes,
            
            elsif ( $site == 2 )
            {
                &echo( qq (   Finding WUSTL microbes (patience) ... ) );
                
                @projects = &DNA::Genomes::Download::get_wustl_microbes_info( $errors );
                @projects = &DNA::Genomes::Download::repair_projects_info( \@projects, $template );
                
                $count = scalar @projects;
                &echo_green( "$count" );
                
                if ( $count = scalar grep { not @{ $_->{"downloads"} } } @projects )
                {
                    &echo( ", " );
                    &echo_yellow( "$count no data" );
                }
                
                &echo( "\n" );
                
                push @projects_all, @projects;

                if ( @new_projects = &DNA::Genomes::Download::new_projects( \@r_projects, \@projects ) )
                {
                    push @r_projects, @new_projects;
                }
            }
            
            # --------- Sanger microbes,
            
            elsif ( $site == 3 )
            {
                &echo( qq (   Finding Sanger microbes (patience) ... ) );
                
                @projects = &DNA::Genomes::Download::get_sanger_microbes_info( $errors );
                @projects = &DNA::Genomes::Download::repair_projects_info( \@projects, $template );
                
                $count = scalar @projects;
                &echo_green( "$count" );
                
                if ( $count = scalar grep { not @{ $_->{"downloads"} } } @projects )
                {
                    &echo( ", " );
                    &echo_yellow( "$count no data" );
                }
                
                &echo( "\n" );
                
                push @projects_all, @projects;

                if ( @new_projects = &DNA::Genomes::Download::new_projects( \@r_projects, \@projects ) )
                {
                    push @r_projects, @new_projects;
                }
            }
            
            # --------- TIGR microbes,

            elsif ( $site == 4 )
            {
                &echo( qq (   Finding TIGR microbes (patience) ... ) );
                
                @projects = &DNA::Genomes::Download::get_tigr_microbes_info( $errors );
                @projects = &DNA::Genomes::Download::repair_projects_info( \@projects, $template );
                
                $count = scalar @projects;
                &echo_green( "$count" );
                
                if ( $count = scalar grep { not @{ $_->{"downloads"} } } @projects )
                {
                    &echo( ", " );
                    &echo_yellow( "$count no data" );
                }
                
                &echo( "\n" );
                
                push @projects_all, @projects;

                if ( @new_projects = &DNA::Genomes::Download::new_projects( \@r_projects, \@projects ) )
                {
                    push @r_projects, @new_projects;
                }
            }
            
            # --------- JGI microbes,
            
            elsif ( $site == 5 )
            {
                &echo( qq (   Finding JGI microbes (patience) ... ) );
                
                @projects = &DNA::Genomes::Download::get_jgi_microbes_info( $errors );
                @projects = &DNA::Genomes::Download::repair_projects_info( \@projects, $template );
                
                $count = scalar @projects;
                &echo_green( "$count" );
                
                if ( $count = scalar grep { not @{ $_->{"downloads"} } } @projects )
                {
                    &echo( ", " );
                    &echo_yellow( "$count no data" );
                }
                
                &echo( "\n" );
                
                push @projects_all, @projects;

                if ( @new_projects = &DNA::Genomes::Download::new_projects( \@r_projects, \@projects ) )
                {
                    push @r_projects, @new_projects;
                }
            }
            
            # --------- Baylor microbes,
            
            elsif ( $site == 6 )
            {
                &echo( qq (   Finding Baylor microbes (patience) ... ) );
                
                @projects = &DNA::Genomes::Download::get_baylor_microbes_info( $errors );
                @projects = &DNA::Genomes::Download::repair_projects_info( \@projects, $template );

                $count = scalar @projects;
                &echo_green( "$count" );
                
                if ( $count = scalar grep { not @{ $_->{"downloads"} } } @projects )
                {
                    &echo( ", " );
                    &echo_yellow( "$count no data" );
                }
                
                &echo( "\n" );
                
                push @projects_all, @projects;

                if ( @new_projects = &DNA::Genomes::Download::new_projects( \@r_projects, \@projects ) )
                {
                    push @r_projects, @new_projects;
                }
            }
            
            # --------- NCBI microbes,
            
            elsif ( $site == 7 )
            {
                &echo( qq (   Finding NCBI microbes (patience) ... ) );
                
                @projects = &DNA::Genomes::Download::get_ncbi_microbes_info( $errors );
                @projects = &DNA::Genomes::Download::repair_projects_info( \@projects, $template );
                
                $count = scalar @projects;
                &echo_green( "$count" );
                
                if ( $count = scalar grep { not @{ $_->{"downloads"} } } @projects )
                {
                    &echo( ", " );
                    &echo_yellow( "$count no data" );
                }
                
                &echo( "\n" );
                
                push @projects_all, @projects;

                if ( @new_projects = &DNA::Genomes::Download::new_projects( \@r_projects, \@projects ) )
                {
                    push @r_projects, @new_projects;
                }
            }
        }
        
        # --------- EMBL microbes,
    }
    
    # >>>>>>>>>>>>>>>>>> VALIDATE PROJECT INFORMATION <<<<<<<<<<<<<<<<<

    @r_projects = grep { $_->{"genus"} } @r_projects;
    @r_projects = grep { @{ $_->{"downloads"} } } @r_projects;

    # Print warnings when there are projects without genus, species 
    # or download files,

    foreach $key ( "genus", "species", "institutions", "downloads" )
    {
        $count = 0;

        foreach $r_project ( @r_projects )
        {
            $value = $r_project->{ $key };

            if ( ref $value eq "ARRAY" ) {
                $count++ if not @{ $value };
            } else {
                $count++ if not $value or $value !~ /\S/;
            }
        }

        if ( $count > 0 )
        {
            &echo_yellow( "   WARNING: " );
            &echo( qq (projects without "$key" ... ) );
            &echo_yellow( "$count\n" );
        }
    }

#   TEMP:

#    @r_projects = @{ &Common::File::eval_file( "$Common::Config::dat_dir/Genomes/last_download.info" ) };


    # >>>>>>>>>>>>>>>>>>>>>>>> SAVE DOWNLOAD INFO <<<<<<<<<<<<<<<<<<<<<

    if ( not $restart )
    {
        if ( @projects_all ) {
            &Common::File::dump_file( "$folder/all.info", \@projects_all );
        }
        
        if ( @r_projects ) {
            &Common::File::dump_file( "$folder/last_download.info", \@r_projects );
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST THE TOTAL <<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Total number of different projects ... ) );

    $count = scalar @r_projects;
    &echo_green( "$count\n" );

    # >>>>>>>>>>>>>>>>> GATHER LOCAL FILE STATISTICS <<<<<<<<<<<<<<<<<<

    # List separately the same information as for the remote sites,
    # but with the local directory included. The directory names are 
    # of the form "genus_species.integer". 

    &echo( qq (   Listing local project versions ... ) );

    @l_projects = &DNA::Genomes::Download::list_local_projects( $folder, $template );

    $count = scalar @l_projects;

    if ( $count == 0 ) {
        &echo_green( qq (none found\n) );
    } else {
        &echo_green( qq ($count found\n) );
    }                

    # >>>>>>>>>>>>>>>>>>>> ESTIMATE DISK SPACE <<<<<<<<<<<<<<<<<<<<<<<<

    # Before downloading, see if there would be enough space. We find
    # this out by subtracting the local file size total from the remote
    # total and then look at the disk partition to see if the difference
    # can be accomodated,

    if ( $readonly ) {
        &echo( "   Would there be enough disk space ... " );
    } else {
         &echo( "   Will there be enough disk space ... " );
    }

    @r_sources = ();

    foreach $project ( @r_projects ) {
        push @r_sources, @{ $project->{"downloads"} };
    }

    @l_sources = ();

    foreach $project ( @l_projects ) {
        push @l_sources, @{ $project->{"downloads"} };
    }

    $r_total = &Common::Storage::add_sizes( \@r_sources );
    $l_total = &Common::Storage::add_sizes( \@l_sources );

    $space_needed = $r_total - $l_total;

    $space_total = &Common::OS::disk_space_total( $folder );
    $space_free = &Common::OS::disk_space_free( $folder );

    $space_free -= $space_needed;

    $full_pct = 100 * ( $space_total - $space_free ) / $space_total;
    $full_pct_f = sprintf "%.1f", $full_pct;

    if ( $full_pct > 99 )
    {
         &echo_red( "NO\n" );
        
         $message = qq (
 Downloading would fill the disk to $full_pct_f% capacity. Please 
 try delete something on this partition or add more disk 
 capacity. 
 );
         &error( $message, "DOWNLOAD GENOMES" );
        exit;
    }
    elsif ( $full_pct > 95 )
    {
         &echo_yellow( "barely" );

         if ( $readonly ) {
             &echo( ", would be $full_pct_f% full\n" );
         } else {
             &echo( ", will be $full_pct_f% full\n" );
         }
        
         $message = qq (

Downloading would fill the disk to $full_pct_f capacity. Please 
make more disk space available soon. 

 );
         &warning( $message, "DOWNLOAD GENOMES" );
    }
    else
    {
         &echo_green( "yes" );
        
         if ( $readonly ) {
             &echo( ", would be $full_pct_f% full\n" );
         } else {
             &echo( ", will be $full_pct_f% full\n" );
         }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>> DOWNLOAD SECTION <<<<<<<<<<<<<<<<<<<<<<<<<

    # Here we go through each remote project and see if there is a local
    # one which matches by the names and sizes of its data files, or its
    # description: same institution, genus, species and strain. If there
    # is, update it. If not, create a new directory and download. 

    $update_count = 0;
    $new_count = 0;

    foreach $r_project ( @r_projects )
    {
        if ( @l_matches = grep { &DNA::Genomes::Download::same_data_files( $r_project, $_ ) } @l_projects )
        {
            # Same data files, but the organism description may be different,

            if ( &DNA::Genomes::Download::update_existing_project( $r_project, \@l_matches, $readonly ) )
            {
                $update_count++;
            }
        }
        else
        {
            # Different data files. If there is a project with same organism
            # description, update it. Otherwise create a new project,
            
            if ( @l_matches = grep { &DNA::Genomes::Download::same_org_description( $r_project, $_ ) } @l_projects )
            {
                if ( &DNA::Genomes::Download::update_existing_project( $r_project, \@l_matches, $readonly ) )
                {
                    $update_count++;
                }
            }
            else
            {
                &DNA::Genomes::Download::create_new_project( $folder, $r_project, \@l_projects, $readonly, $errors );

                push @l_projects, &Storable::dclone( $r_project );
                $new_count++;
            }                
        }            
    }

    if ( $update_count == 0 and $new_count == 0 )
    {
        $l_projects = scalar @l_projects;
        &echo( qq (   All $l_projects are up to date ... ) );
        &echo_green( "good\n" );
    }
    else
    {
        if ( $update_count > 0 )
        {
            if ( $readonly ) {
                &echo( qq (   Projects that would be updated .. ) );
            } else {
                &echo( qq (   Projects updated .. ) );
            }

            &echo_green( qq ($update_count\n) );
        }

        if ( $new_count > 0 )
        {
            if ( $readonly ) {
                &echo( qq (   Projects that would be created .. ) );
            } else {
                &echo( qq (   Projects created .. ) );
            }

            &echo_green( qq ($new_count\n) );
        }
    }

    print STDERR @{ $errors } if defined $errors;
#    &DNA::Genomes::Download::write_log ( $errors ) if defined $errors;
    
    return;
}

sub write_log
{
    # Bo Mikkelsen, November 2003.

    # Writes diagnostic messages to log file.

    my ( $errors   # Reference to array with messages
         ) = @_;

    # Returns nothing.

    my ( $log_dir, $log_file, $time_str );

    $log_dir = "$Common::Config::log_dir/Genomes/Download";
    $log_file = "$log_dir/ERRORS";

    $time_str = &Common::Util::epoch_to_time_string();

    &Common::File::create_dir( $log_dir, 0 );

    if ( open LOG, ">> $log_file" )
    {
        print LOG "$time_str\n";
        print LOG @{$errors};
        close LOG;
    }
    else {
        &error( qq (Could not open or append to "$log_file") );
    }
}
   
sub same_genus_species
{
    # Niels Larsen, August 2003.

    # Returns true if both genus and species are the same for 
    # two given project description hashes. 

    my ( $project1,    # Project description 
         $project2,    # Project description 
         ) = @_;
    
    # Returns a boolean.

    if ( lc $project1->{"genus"} eq lc $project2->{"genus"} and
         lc $project1->{"species"} eq lc $project2->{"species"} )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub same_data_files
{
    # Niels Larsen, January 2004.

    # Returns true if the download files of two given project 
    # hashes have same names and sizes, otherwise false.

    my ( $project1,    # Project description 
         $project2,    # Project description 
         ) = @_;

    # Returns a boolean.

    my ( @diff_files );

    if ( @diff_files = &Common::Storage::diff_lists( $project1->{"downloads"}, 
                                                     $project2->{"downloads"},
                                                     [ "name", "size"] ) )
    {
        return 0;
    } 
    else
    {
        return 1;
    }
}

sub same_org_description
{
    # Niels Larsen, January 2004.

    # Returns true if two given hashes describe the same project,
    # false otherwise. The frail logic is: if the download files
    # have same name and sizes, then it must be the same project
    # (even if the organism description seems different). If the
    # names or sizes are different (this can happen when a project
    # is updated) then genus, species, strain and sequencing 
    # institution must be the same. This may cause a few redundant
    # downloads, since organism description is not always exact
    # and consistent. 

    my ( $project1,    # Project description 
         $project2,    # Project description 
         ) = @_;

    # Returns a boolean.

    my ( $genus1, $genus2, $species1, $species2, %urls1, %urls2, $url,
         @diff_files, $overlapping_institutions, $same_downloads,
         $same_strain, $inst );

    $genus1 = lc $project1->{"genus"};
    $genus2 = lc $project2->{"genus"};

    $species1 = lc $project1->{"species"};
    $species2 = lc $project2->{"species"};

    foreach $inst ( @{ $project1->{"institutions"} } )
    {
        if ( $inst->[1] and $inst->[1] =~ /^http:\/\/([^\/]+)/i )
        {
            $url = $1;
            $url =~ /([^\.]+\.[^\.]+)$/;
            $urls1{ $1 } = 1;
        }
    }

    foreach $inst ( @{ $project2->{"institutions"} } )
    {
        if ( $inst->[1] and $inst->[1] =~ /^http:\/\/([^\/]+)/i )
        {
            $url = $1;
            $url =~ /([^\.]+\.[^\.]+)$/;
            $urls2{ $1 } = 1;
        }
    }

    $overlapping_institutions = 0;

    foreach $url ( keys %urls1 )
    {
        if ( exists $urls2{ $url } )
        {
            $overlapping_institutions = 1;
            last;
        }
    }

    if ( lc $project1->{"strain"} eq lc $project2->{"strain"} )
    {
        $same_strain = 1;
    }
    
    if ( $genus1 eq $genus2  and
         $species1 eq $species2  and
         $overlapping_institutions  and
         $same_strain )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub list_file_properties
{
    # Niels Larsen, January 2004.

    # Returns full file properties for the files in a given input list. 
    # The input list elements are tuples of name and url (or directory)
    # location. 

    my ( $tuples,
         ) = @_;

    # Returns a list.

    my ( $tuple, $name, $dir, %dir_files, @files, @want_files );

    # Put the given files in a hash where directory location is key
    # and a list of desired files is value,

    foreach $tuple ( @{ $tuples } )
    {
        ( $name, $dir ) = @{ $tuple };

        $name =~ s/^\s*//;
        $name =~ s/\s*$//;

        $dir =~ s/^\s*//;
        $dir =~ s/\s*$//;

        push @{ $dir_files{ $dir } }, $name;
    }

    # Fetch these files directory by directory,

    foreach $dir ( keys %dir_files )
    {
        @files = &Common::Storage::list_files( $dir );

        foreach $name ( @{ $dir_files{ $dir } } )
        {
            push @want_files, grep { $_->{"name"} =~ $name } @files;
        }
    }
    
    return wantarray ? @want_files : \@want_files;
}

sub diff_projects
{
    # Niels Larsen, August 2003.

    # For a given project 1 and 2, returns the part of project 1 that 
    # differ from project 2. 

    my ( $project1,   # Project directory path
         $project2,   # Project directory path
         $template,   # Project hash template
         $errors,     # Error list
         ) = @_;
    
    # Returns a hash or nothing.

    if ( not $template ) {
        $template = &DNA::Genomes::Download::template();
    }

    my ( $diffs, @list, $key, $content1, $content2 );

    foreach $key ( keys %{ $template } )
    {
        if ( $key eq "downloads" )
        {
            @list = &Common::Storage::diff_lists( $project1->{"downloads"}, 
                                                  $project2->{"downloads"},
                                                  [ "name", "size" ] );
            
            $diffs->{"downloads"} = \@list if @list;
        }
        else 
        {
            $content1 = Dumper( $project1->{ $key } );
            $content2 = Dumper( $project2->{ $key } );

            if ( ref $project1->{ $key } eq "ARRAY" )
            {
                if ( @{ $project1->{ $key } } and $content1 ne $content2 ) {
                    $diffs->{ $key } = &Storable::dclone( $project1->{ $key } );
                }
            }
            else
            {
                if ( $project1->{ $key } and $content1 ne $content2 ) {
                    $diffs->{ $key } = $project1->{ $key };
                }
            }
        }
    }

    if ( $diffs ) {
        return wantarray ? %{ $diffs } : $diffs;
    } else {
        return;
    }
}

sub update_local_project
{
    # Niels Larsen, August 2003.

    # Saves a given project to file. It does the opposite of 
    # list_local_project. 

    my ( $folder,     # Project directory path
         $project,    # Project description hash
         $errors,     # Error list
         ) = @_;
    
    # Returns a hash or nothing.

    my ( $file, $key, $value, $content, $row, $time_str );
    
    &Common::File::create_dir_if_not_exists( $folder );
    &Common::File::create_dir_if_not_exists( "$folder/Downloads" );

    foreach $key ( keys %{ $project } )
    {
        if ( $key !~ /^downloads|local_dir|local_path|version$/ )
        {
            &Common::File::delete_file_if_exists( qq ($folder/$key) );
            
            $value = $project->{ $key };
            $content = "";
            
            if ( ref $value eq "ARRAY" ) 
            {
                foreach $row ( @{ $value } )
                {
                    if ( ref $row eq "ARRAY" ) {
                        $content .= ( join "\t", @{ $row } ) . "\n";
                    } else {
                        $content .= "$row\n";
                    }
                }
            }
            else {
                $content .= "$value\n";
            }
            
            if ( $content =~ /\w/ ) {
                &Common::File::write_file( "$folder/$key", $content );
            }
        }
    }

    foreach $file ( @{ $project->{"downloads"} } )
    {
        &Common::File::delete_file_if_exists( qq ($folder/Downloads/$file->{"name"}) );
        &Common::Storage::copy_file( $file->{"path"}, qq ($folder/Downloads/$file->{"name"}) );
    }

    $time_str = &Common::Util::epoch_to_time_string();

    &Common::File::delete_file_if_exists( "$folder/last_updated" );
    &Common::File::write_file( "$folder/last_updated", "$time_str\n" );

    return;
}

sub list_local_project
{
    # Niels Larsen, August 2003.

    # For a given project directory, creates a hash similar to those 
    # made by the routines that visit different sites. 

    my ( $folder,   # Project directory path
         $template,   # Project hash template
         $errors,   # Error list
         ) = @_;

    # Returns a hash.

    $folder =~ s|/$||;

    my ( $project, $content, $row, $keys, $key, $value );

    if ( -e $folder )
    {
        foreach $key ( keys %{ $template } )
        {
            $value = $template->{ $key };

            if ( $key eq "downloads" )
            {
                if ( -r "$folder/Downloads" ) {
                    $project->{"downloads"} = &Common::Storage::list_files( "$folder/Downloads" );
                } else {
                    $project->{"downloads"} = [];
                }
            }
            elsif ( -r "$folder/$key" )
            {
                $content = ${ &Common::File::read_file( "$folder/$key" ) };
#                $content =~ s/^ *//;
                $content =~ s/[ \n]*$//;

                if ( ref $value eq "ARRAY" ) 
                {
                    $content = [ split "\n", $content ];

                    if ( ref $value->[0] eq "ARRAY" )
                    {
                        foreach $row ( @{ $content } )
                        {
                            if ( $row =~ /^(.*)\t(.*)$/ ) {
                                $row = [ $1, $2 ];
                            }
                        }
                    }

                    $project->{ $key } = &Storable::dclone( $content );
                }
                else {
                    $project->{ $key } = $content;
                }
            }
            else
            {
                if ( ref $value eq "ARRAY" ) {
                    $project->{ $key } = [];
                } else {
                    $project->{ $key } = "";
                }
            }
        }

        $project->{"local_path"} = $folder;
        $project->{"local_dir"} = ( split "/", $folder )[-1];

        if ( $folder =~ /\.(\d+)$/ ) {
            $project->{"version"} = $1;
#        } else {
#            $project->{"version"} = "";
        }
    }
    else
    {
        $project = {};
        push @{ $errors }, qq (ERROR: Local: project directory does not exist -> "$folder"\n);
    }

    return wantarray ? %{ $project } : $project;
}

sub list_local_projects
{
    # Niels Larsen, August 2003.

    # Builds a list of project hashes similar to those which are made
    # by the routines that visit different sites. The idea is to have 
    # two similar lists to compare, so the differences can be found.

    my ( $folder,     # Main directory where projects are
         $template,   # Project hash template
         $errors,     # Error list 
         ) = @_;

    # Returns an array.

    if ( not $folder ) {
        $folder = "$Common::Config::dat_dir/Genomes";
    }

    if ( not $template ) {
        $template = &DNA::Genomes::Download::template();
    }

    my ( @projects, $project, $dir );

    foreach $dir ( grep { $_->{"name"} =~ /\.\d+$/ } &Common::File::list_directories( $folder ) )
    {
        $project = &DNA::Genomes::Download::list_local_project( "$folder/$dir->{'name'}", $template, $errors );
        push @projects, &Storable::dclone( $project );
    }

    return wantarray ? @projects : \@projects;
}

sub parse_org_name
{
    # Niels Larsen, May 2004.

    # Creates a hash that holds the pieces that an organism name can be
    # split into. Its keys are genus, species, subspecies and strain.

    my ( $name,    # Organism name
         ) = @_;

    # Returns a hash.

    my ( $info, @name );

    $name =~ s/\(.+?\)//;         # Strip everything in parantheses

    @name = split " ", $name;

    $info->{"genus"} = $name[0];

    if ( not $name[1] or $name[1] =~ /^sp\.$/i ) {
        $info->{"species"} = "";
    } else {
        $info->{"species"} = $name[1];
    }
    
    shift @name; 
    shift @name;

    if ( $name[0] and $name[0] =~ /^subsp\.$/ )
    {
        $info->{"subspecies"} = $name[1] || "";
        shift @name;
        shift @name;
    }
    else {
        $info->{"subspecies"} = "";
    }
    
    if ( $name[0] ) {
        $info->{"strain"} = join " ", grep { $_ !~ /^str\.|strain$/ } @name;
    } else {
        $info->{"strain"} = "";
    }
    
    return wantarray ? %{ $info } : $info;
}    
    
sub repair_projects_info
{
    # Niels Larsen, August 2003.

    # Tries to make fields more consistent so comparisons become more 
    # safe. This becomes important for example when we check if a project
    # exists in a local copy already or a new folder should be created.

    my ( $projects,    # List of project hashes
         $template,    # Project hash template
         ) = @_;

    # Returns a list.

    my ( $project, $key, $elem, $inst, %names, $name );

    foreach $project ( @{ $projects } )
    {
        # Give empty values to non-existing keys, 
    
        foreach $key ( keys %{ $template } )
        {
            if ( ref $template->{ $key } eq "ARRAY" ) {
                $project->{ $key } = [] if not defined $project->{ $key };
            } else {
                $project->{ $key } = "" if not defined $project->{ $key };
            }
        }

        # Remove trailing slashes and blanks,
        
        foreach $key ( keys %{ $template } )
        {
            if ( ref $template->{ $key } eq "ARRAY" )
            {
                foreach $elem ( @{ $project->{ $key } } )
                {
                    next if $key eq "downloads";

                    if ( ref $elem eq "ARRAY" ) {
#                        if ( not defined $elem->[1] ) { &dump( $project ) };
                        $elem->[1] =~ s/[\/ \n]*$//;
                    } else {
                        $elem =~ s/[\/ \n]*$//;
                    }
                }
            }
            elsif ( $key =~ /_url$/ )
            {
                $project->{ $key } =~ s/[\/ \n]+$//;
            }
        }

        # Change "sp." to nothing,

        if ( $project->{"species"} =~ /^\s*(sp\.?|species)\s*$/ )
        {
            $project->{"species"} = "";
        }

        # Remove 'trailing' parentheses from strain,

        $project->{"strain"} =~ s/^\((.*)\)$/$1/;

        # Remove "str."

        $project->{"strain"} =~ s/^\s*(str\.?|strain)\s+//i;
        

        # Make sure institutions URLs can be used for comparison,

        foreach $inst ( @{ $project->{"institutions"} } )
        {
            $inst->[1] = "http://$inst->[1]" if ( not $inst->[1] =~ m|http://|i and $inst->[1] ne "" );
            $inst->[1] =~ s|\s*(http://[^/]+).*\s*$|$1|i if ( $inst->[1] ne "" );
            $inst->[1] =~ s|:\d+$|| if ( $inst->[1] ne "" );
        }

        # Try make organism categories (expand),

        if ( $project->{"strain"} =~ /virus/i ) {
            $project->{"category"} = "virus";
        } elsif ( $project->{"strain"} =~ /plasmid/i ) {
            $project->{"category"} = "plasmid";
        } else {
            $project->{"category"} = "organism";
        }

        # Trim list of files so we 1) only get the compressed versions
        # if they exist and 2) dont get .Z versions if there are .gz
        # versions,

        if ( @{ $project->{"downloads"} } )
        {
            %names = map { $_->{"name"}, 1 } @{ $project->{"downloads"} };
            
            foreach $name ( keys %names )
            {
                if ( $name =~ /^(.+)\.(gz|Z)$/ and $names{ $1 } ) {
                    delete $names{ $1 };
                }
        
                if ( $name =~ /^(.+)\.gz$/ and $names{ "$1.Z" } ) {
                    delete $names{ "$1.Z" };
                }
            }

            $project->{"downloads"} = [ grep { $names{ $_->{"name"} } } @{ $project->{"downloads"} } ];
        }
    }

    return wantarray ? @{ $projects } : $projects;
}

sub get_tigr_microbes_info
{
    # Niels Larsen, August 2003.

    # Looks at the TIGR microbial web pages and creates a list of hashes
    # with summary information about their microbial projects. Information
    # is extracted out of html, so the procedure is sensitive to changes 
    # and will need maintenance.

    my ( $errors,     # List of error messages
         ) = @_;

    # Returns an array.

    my ( $tr, $http_base, $tigr_ftp, $projects_html, @projects, $project, $genus, $species,
         $desc, $name, $strain, $link, @desc, $status, @sponsors, $sponsors, $downloads,
         $strains, $sponsor, $r_files, $r_dir, $project_html, @downloads, $td, $key, $value,
         $file_list, $tuple, $gbk_ftp );

    $http_base = "http://www.tigr.org";
    $tigr_ftp = "ftp://ftp.tigr.org/pub/data/Microbial_Genomes";
    $gbk_ftp = "ftp://ftp.ncbi.nih.gov/genomes/Bacteria";

    # Error compensation,

    $downloads->{"Methanococcus"}->{"maripaludis"}->{"S2"} = [['.+',"$gbk_ftp/Methanococcus_maripaludis_S2"]];
    $downloads->{"Staphylococcus"}->{"aureus"}->{"subsp. aureus COL"} = [['.+',"$tigr_ftp/s_aureus_subsp_aureus_col/annotation_dbs"]];
    $downloads->{"Staphylococcus"}->{"aureus"}->{"N315"} = [['.+',"$gbk_ftp/Staphylococcus_aureus_N315"]];
    $downloads->{"Staphylococcus"}->{"epidermidis"}->{"ATCC 12228"} = [['.+',"$gbk_ftp/Staphylococcus_epidermidis_ATCC_12228"]];
    $downloads->{"Agrobacterium"}->{"tumefaciens"}->{"C58 Cereon"} = [['.+',"$gbk_ftp/Agrobacterium_tumefaciens_C58_Cereon"]];
    $downloads->{"Salmonella"}->{"typhimurium"}->{"LT2 SGSC1412"} = [['.+',"$gbk_ftp/Salmonella_typhimurium_LT2"]];
    # Wolbachia pipientis wMel  TIGR link bad, Genbank link ok
    $downloads->{"Yersinia"}->{"pestis"}->{"CO92"} = [['.+',"$gbk_ftp/Yersinia_pestis_CO92"]];
    # Haemophilus influenzae KW20 Rd  TIGR link bad, Genbank link ok
    # Magnetococcus - no ftp link
    $downloads->{"Streptococcus"}->{"pyogenes"}->{"MGAS8232"} = [['.+',"$gbk_ftp/Streptococcus_pyogenes_MGAS8232"]];

    $projects_html = &Common::HTTP::get_html_page( "$http_base/tigr-scripts/CMR2/CMRGenomes.spl", $errors );

    if ( not defined $projects_html )
    {
        push @{ $errors }, "ERROR: TIGR: Could not access $http_base/tigr_scripts/CMR2/CMRGenomes.spl.\n";
        return;
    }

    while ( $projects_html =~ /(<td[^>]*>\s*(.+?)\s*<\/td>)/sgi )
    {
        $td = $1;
        
        if ( $td =~ /href\s*=\s*\"([^\"]+GenomePage3\.spl[^\"]+)/ )
        {
            undef $project;

            $project->{"project_url"} = "$http_base$1";
            $project->{"from_site"} = [ [ "TIGR", "$http_base/tigr-scripts/CMR2/CMRGenomes.spl" ] ];
            $project->{"conditions_url"} = "";

            next if $td =~ /virus|phage/si;

            $project_html = &Common::HTTP::get_html_page( $project->{"project_url"}, $errors ) || "";

            while ( $project_html =~ /(<td[^>]*>\s*(.+?)\s*<\/td>)/sgi )
            {
                $td = $1;
                $key = "";
                $value = "";

                if ( $td =~ /Sequencing\s+Center\s*:/i )
                {
                    if ( $project_html =~ /<a href\s*=\s*\"([^\"]+)\">\s*(.+?)<\/a>/sgi ) {
                        $project->{"institutions"} = [ [ $2, $1 ] ];
                    } else {
                        $project->{"institutions"} = [];
                    }
                }                        
                elsif ( $td =~ /Funding\s+Center\s*:/i )
                {
                    if ( $project_html =~ /<a href\s*=\s*\"([^\"]+)\">\s*(.+?)<\/a>/sgi ) {
                        $project->{"funding"} = [ [ $2, $1 ] ];
                    } else {
                        $project->{"funding"} = [];
                    }
                }
                elsif ( $td =~ /Publication\s*:/i )
                {
                    if ( $project_html =~ /<a href\s*=\s*\"([^\"]+)\">.+?<\/a>/sgi ) {
                        push @{ $project->{"literature_urls"} }, [ "", $1 ];
                    } else {
                        $project->{"literature_urls"} = [];
                    }
                }
                elsif ( $td =~ /Genus\s*:/i )
                {
                    $key = "genus";

                    if ( $project_html =~ /<td[^>]*>\s*(.+?)\s*<\/td>/sgi ) {
                        $value = $1;
                    } else {
                        $value = ""; 
                    }
                }
                elsif ( $td =~ /Species\s*:/i )
                {
                    $key = "species";

                    if ( $project_html =~ /<td[^>]*>\s*(.+?)\s*<\/td>/sgi ) {
                        $value = $1;
                    } else {
                        $value = "";
                    }
                }
                elsif ( $td =~ /Strain\s*:/i )
                {
                    $key = "strain";

                    if ( $project_html =~ /<td[^>]*>\s*(.+?)\s*<\/td>/sgi) {
                        $value = $1;
                    } else {
                        $value = "";
                    }
                }
                elsif ( $td =~ /Other\s*:/i )
                {
                    if ( $project_html =~ /<a href\s*=\s*\"([^\"]+)\">.+?<\/a>/sgi ) {
                        $project->{"organism_url"} = $1;
                    } else {
                        $project->{"organism_url"} = "";
                    }
                }
                elsif ( $td =~ /Kingdom\s*:/i or $td =~ /Intermediate\s+Rank\s+\d+\s*:/i )
                {
                    if ( $project_html =~ /<td[^>]*>\s*(.+?)\s*<\/td>/sgi )
                    {
                        $value = $1;
                        $value =~ s/<\/?(b|br|font)[^>]*>//gi;
                        push @{ $project->{"taxonomy"} }, $value;
                    }
                }
                elsif ( $td =~ /Completed\s+Genome\s*:/i )
                {
                    $key = "status";
                    
                    if ( $project_html =~ /<td[^>]*>\s*(.+?)\s*<\/td>/sgi ) {
                        $value = $1;
                    } else {
                        $value = ""; 
                    }
                }
                elsif ( $td =~ /<a href\s*=\s*\"\s*ftp:.+?\">.+\s*GenBank FTP\s*/i or 
                        $td =~ /<a href\s*=\s*\"\s*ftp:.+?\">.+\s*TIGR FTP\s*/i )
                {
                    if ( $td =~ /<a href\s*=\s*\"\s*(ftp:.+?)\">.+\s*TIGR FTP\s*/i )
                    {
                        $r_dir = $1;

                        $file_list = &Common::Storage::list_files( $r_dir );

                        if ( defined $file_list ) {
                            $project->{"downloads"} = &Storable::dclone( $file_list );
                        }
                    }

                    if ( not $project->{"downloads"} and 
                         $td =~ /<a href\s*=\s*\"\s*(ftp:.+?)\">.+\s*GenBank FTP\s*/i )
                    {
                        $r_dir = $1;

                        $file_list = &Common::Storage::list_files( $r_dir );

                        if ( defined $file_list ) {
                            $project->{"downloads"} = &Storable::dclone( $file_list );
                        }
                    }
                }

                $value =~ s/<\/?(b|br|font|td)[^>]*>//gi;

                if ( $key ) {
                    $project->{ $key } = $value;
                }

                if ( exists $project->{"status"} )
                {
                    if ( $project->{"status"} =~ /yes/i ) {
                        $project->{"status"} = "finished";
                    } else {
                        $project->{"status"} = "in progress";
                    }
                }
            }

            if ( not $project->{"downloads"} or not @{ $project->{"downloads"} } )
            {
                $tuple = $downloads->{ $project->{"genus"} }->{ $project->{"species"} }->{ $project->{"strain"} };

                if ( $tuple )
                {
                    $file_list = &Common::Storage::list_files( $tuple->[0]->[1] );

                    if ( $file_list ) {
                        $project->{"downloads"} = &Storable::dclone( $file_list );
                    } else {
                        $project->{"downloads"} = [];
                    }
                }
                else
                {
                    push @{ $errors }, qq (ERROR: TIGR: Invalid remote ftp dir -> "$r_dir"\n);
                    $project->{"downloads"} = [];
                }
            }

#            if ( not @{ $project->{"downloads"} } ) {
#                &dump( "no downloads" );
#                &dump( $project );
#            }

            push @projects, &Storable::dclone( $project );
        }
    }

    return wantarray ? @projects : \@projects;
}

sub get_sanger_microbes_info
{
    # Niels Larsen, August 2003.

    # Looks at the Sanger Centre web pages and creates a list of hashes
    # with summary information about their microbial projects. Information
    # is extracted out of html and supplemented by hand, so the procedure 
    # is sensitive to changes and will need maintenance until the day where
    # Sanger Centre describes their projects consistently somehow. In other
    # words, this is a necessary hack. Dont look. 

    my ( $errors,     # List of error messages
         ) = @_;

    # Returns an array.

    my ( $tr, $http_base, $ftp_base, $projects_html, @projects, $project, $genus, $species,
         $desc, $name, $strain, $link, @desc, $status, @sponsors, $sponsors, $downloads,
         $strains, $sponsor, $r_files, $r_dir, $desc_html, $desc_dir, $key, $file_list,
         $url );

    $http_base = "http://www.sanger.ac.uk/Projects/Microbes";
    $ftp_base = "ftp://ftp.sanger.ac.uk/pub";

    # The following hashes contains hard-to-get unlikely-to-change information 
    # from the pages. The routine checks with them just before trying the pages,

    $downloads->{"Bacteroides"}->{"fragilis"}->{"NCTC9343"} = [["BF.dbs","$ftp_base/pathogens/bf"]];
    $downloads->{"Bacteroides"}->{"fragilis"}->{"638R"} = [["BF638R.dbs","$ftp_base/pathogens/bf"]];
    $downloads->{"Escherichia"}->{"coli"}->{"042"} = [["Ec042.dbs","$ftp_base/pathogens/Escherichia_Shigella"]];
    $downloads->{"Escherichia"}->{"coli"}->{"E2348/69"} = [["EcE2348.dbs","$ftp_base/pathogens/Escherichia_Shigella"]];
    $downloads->{"Escherichia"}->{"coli"}->{"non-K1 clinical isolate"} = [];
    $downloads->{"Salmonella"}->{"enteritidis"}->{"PT4"} = [["SePT4.dbs","$ftp_base/pathogens/Salmonella"]];
    $downloads->{"Salmonella"}->{"typhimurium"}->{"DT104"} = [["STmDT104.dbs","$ftp_base/pathogens/Salmonella"]];
    $downloads->{"Salmonella"}->{"typhimurium"}->{"SL1344"} = [["STmSL1344.dbs","$ftp_base/pathogens/Salmonella"]];
    $downloads->{"Salmonella"}->{"bongori"}->{"12419"} = [["SB.dbs","$ftp_base/pathogens/Salmonella"]];
    $downloads->{"Salmonella"}->{"gallinarum"}->{"287/91"} = [["SG.dbs","$ftp_base/pathogens/Salmonella"]];
    $downloads->{"Shigella"}->{"dysenteriae"}->{"M131649"} = [["SD.dbs","$ftp_base/pathogens/Escherichia_Shigella"]];
    $downloads->{"Shigella"}->{"sonnei"}->{"53G"} = [["Sso.dbs","$ftp_base/pathogens/Escherichia_Shigella"]];
    $downloads->{"Staphylococcus"}->{"aureus"}->{"MRSA252"} = [["MRSA252.dna","$ftp_base/pathogens/sa"]];
    $downloads->{"Staphylococcus"}->{"aureus"}->{"MSSA476"} = [["MSSA476.dna","$ftp_base/pathogens/sa"]];
    $downloads->{"Streptomyces"}->{"coelicolor"}->{"A3(2)"} = [['\.seq$', "$ftp_base/S_coelicolor/sequences"]];
    $downloads->{"Bordetella"}->{"parapertussis"}->{"12822"} = [["BPP.dna", "$ftp_base/pathogens/bp"]];
    $downloads->{"Bordetella"}->{"pertussis"}->{"Tohama I"} = [["BP.dna", "$ftp_base/pathogens/bp"]];
    $downloads->{"Bordetella"}->{"bronchiseptica"}->{"RB50"} = [["BB.dna", "$ftp_base/pathogens/bp"]];
    $downloads->{"Neisseria"}->{"meningitidis"}->{"Serogroup A strain Z2491"} = [["NM.dbs", "$ftp_base/pathogens/nm"]];
    $downloads->{"Neisseria"}->{"meningitidis"}->{"Serogroup C strain FAM18"} = [["NmC.dbs", "$ftp_base/pathogens/nm"]];
    $downloads->{"Wolbachia"}->{"pipientis"}->{"endosymbiont of Culex quinquefasciatus"} = [["Wb_Cq.dbs", "$ftp_base/pathogens/Wolbachia"]];
    $downloads->{"Wolbachia"}->{" "}->{"endosymbiont of Onchocerca volvulus"} = [["Wb_Ov.dbs", "$ftp_base/pathogens/Wolbachia"]];

    $strains->{"Bordetella"}->{"parapertussis"} = "12822";
    $strains->{"Bordetella"}->{"bronchiseptica"} = "RB50";
    $strains->{"Bordetella"}->{"pertussis"} = "Tohama I";
    $strains->{"Burkholderia"}->{"pseudomallei"} = "K96243";
    $strains->{"Burkholderia"}->{"cenocepacia"} = "J2315";
    $strains->{"Campylobacter"}->{"jejuni"} = "NCTC 11168";
    $strains->{"Clostridium"}->{"botulinum"} = "Hall strain A";
    $strains->{"Erwinia"}->{"carotovora"} = "SCRI1043";
    $strains->{"Mycobacterium"}->{"marinum"} = "M";
    $strains->{"Mycobacterium"}->{"tuberculosis"} = "H37Rv";
    $strains->{"Neisseria"}->{"lactamica"} = "ST-640";
    $strains->{"Pseudomonas"}->{"fluorescens"} = "SBW25";
    $strains->{"Rhizobium"}->{"leguminosarum"} = "3841";
    $strains->{"Salmonella"}->{"bongori"} = "12419";
    $strains->{"Salmonella"}->{"typhi"} = "CT18";
    $strains->{"Shigella"}->{"dysenteriae"} = "M131649";
    $strains->{"Shigella"}->{"sonnei"} = "53G";
    $strains->{"Streptococcus"}->{"pneumoniae"} = "23F";
    $strains->{"Streptomyces"}->{"coelicolor"} = "A3(2)";
    $strains->{"Yersinia"}->{"enterocolitica"} = "8081";
    $strains->{"Yersinia"}->{"pestis"} = "CO92";

    $projects_html = &Common::HTTP::get_html_page( $http_base, $errors );

    if ( not defined $projects_html ) {
        push @{ $errors }, "ERROR: Sanger: Could not access $http_base.\n";
        return;
    }

    while ( $projects_html =~ /(<tr class=\"violet\d+\">\s*.+?\s*<\/tr>)/sgi )
    {
        $tr = $1;
        
        if ( $tr =~ /href=\"\/Projects\/\w/ and $tr =~ /<td [^>]+>(.+?)<\/td>/sgi )
        {
            $link = $1;
            $link =~ s/\n//g;
            $link =~ s/\s+</</g;
            $link =~ s/>\s+/>/g;

            undef $project;

            next if $link =~ /virus|plasmid|capsular/i;

            $project->{"category"} = "organism";
            $project->{"from_site"} = [ [ "Sanger", $http_base ] ];
            $project->{"institutions"} = [ [ "Sanger Centre", "http://www.sanger.ac.uk" ] ];
            $project->{"conditions_url"} = "http://www.sanger.ac.uk/Projects/use-policy.shtml";

            if ( $link =~ /^\s*<a href="\/(.+?)">(.+?)(<\/?a>)?$/sgi )
            {
                # ------------ Description pages,
                
                $desc_dir = $1;
                $desc = $2;

                $desc =~ s/<\s*\/?br\s*\/?>//g;
                $desc =~ s/<\s*\/?a\s*>//g;

                $project->{"project_url"} = "http://www.sanger.ac.uk/$desc_dir";
                $project->{"project_url"} =~ s/\/\s*$//;

                $project->{"organism_url"} = $project->{"project_url"};
                
                $desc_html = &Common::HTTP::get_html_page( $project->{"project_url"}, $errors ) || "";

                # ------------ Genus and species,

                if ( $desc =~ /<i>([^<]+)<\/?i>/ )
                {
                    ( $project->{"genus"}, $project->{"species"} ) = split " ", $1;
                    $project->{"species"} ||= " ";
                }
                else {
                    push @{ $errors }, qq (ERROR: Sanger: Could not extract genus/species from -> "$desc"\n);
                }

                # ------------ Strain,

                if ( $desc =~ /<i>[^<]+<\/?i>(.*)$/ )
                {
                    $strain = $1;

                    $strain =~ s/[()]//g;
                    $strain =~ s/<\/?i>/ /g;
                    $strain =~ s/^\s*//;
                    $strain =~ s/\s*$//;

                    $strain = "" if $strain =~ /formerly/;
                    
                    if ( not $strain )
                    {
                        if ( $strains->{ $project->{"genus"} }->{ $project->{"species"} } )
                        {
                            $strain = $strains->{ $project->{"genus"} }->{ $project->{"species"} };
                        }
                        elsif ( $desc_html =~ /$project->{"species"}(<\/i>)?\s+strain,?\s+([^ ,.]+\s+[^ ,.]+)/gxi )
                        {
                            $strain = $2;

                            if ( $strain =~ /^(ATCC|DSM)\s*(.+)/ ) {
                                $strain = $2;
                            } elsif ( $strain =~ /^(.+)\s+.+/ ) {
                                $strain = $1;
                            }
                        }
                    }

                    $project->{"strain"} = $strain || "";
                }
                else {
                    push @{ $errors }, qq (ERROR: Could not extract genus/species from -> "$desc"\n);
                }

                # ------------ Download files,
                
                 if ( $r_files = $downloads->{ $project->{"genus"} }->{ $project->{"species"} }->{ $project->{"strain"} } )
                 {
                     $file_list = &DNA::Genomes::Download::list_file_properties( $r_files );

                     $project->{"downloads"} = &Storable::dclone( $file_list );
                 }
                 else
                 {
                     if ( $desc_html =~ m|href="(ftp://ftp.sanger.ac.uk/pub/[^\"]+)">(Sequence)?\s*FTP| )
                    {
                         $r_dir = $1; 
                         $file_list = &Common::Storage::list_files( $r_dir );

                         if ( defined $file_list )
                         {
                             # This says "if there are contig files, then we dont want the shotgun file",
                             # because the shotgun file is large. 
                        
                             if ( ( grep { $_->{"name"} =~ /\.dbs$/ } @{ $file_list } ) > 1 )
                             {
                                 $file_list = [ grep { $_->{"name"} !~ /shotgun|reads/i } @{ $file_list } ];
                             }

                             $project->{"downloads"} = &Storable::dclone( $file_list );
                         }
                         else
                         {
                             push @{ $errors }, qq (ERROR: Sanger: Invalid remote dir "$r_dir"\n);
                             $project->{"downloads"} = [];
                         }
                     }
                    else
                    {
                         push @{ $errors }, qq (ERROR: Sanger: Could not find ftp url for -> "$project->{'genus'} $project->{'species'}"\n);
                         $project->{"downloads"} = [];
                     }
                 }
            }
            else {
                push @{ $errors }, qq (ERROR: Sanger: Could not parse organism link "$link"\n);
            }

            # -------------- Skip genome sizes and G+C,

            $tr =~ /\s<td [^>]+>.+?<\/td>/sgi;     # skip size column
            $tr =~ /\s<td [^>]+>.+?<\/td>/sgi;     # skip column

            # -------------- Status,

            $tr =~ /\s<td [^>]+>(.+?)<\/td>/sgi;
            $status = $1 || "";

            if ( $status =~ /^finished$/i )
            {
                $project->{"status"} = "finished";
            }
            elsif ( $status =~ m|href=\"(http://[^\"]+)\"|sgi )
            {
                push @{ $project->{"literature_urls"} }, [ "", $1 ];
                $project->{"status"} = "finished";
            }
            elsif ( $status =~ /finishing|closure/i ) 
            {
                $project->{"status"} = "finishing";
            }
            elsif ( $status =~ /funded/i or not @{ $project->{"downloads"} } )
            {
                $project->{"status"} = "planned";
            }
            else
            {
                $project->{"status"} = "in progress";
            }

            # -------------- Sponsors,

            $tr =~ /\s<td [^>]+>(.+?)<\/td>/sgi;
            $sponsors = $1 || "";
            $project->{"funding"} = [];

            foreach $sponsor ( split /\s*\/?\s*<\s*br\s*\/?\s*>/i, $sponsors )
            {
                if ( $sponsor =~ m|<a \s*href="(.+?)">\s*(.+?)</a>| )
                {
                    $url = $1;
                    $name = $2;

                    $url =~ s/\/$//;
                    push @{ $project->{"funding"} }, [ $name, $url ];
                }
                elsif ( $sponsor !~ /pilot project/i ) {
                    push @{ $errors }, qq (ERROR: Sanger: Could not parse sponsor "$sponsor"\n);
                }
            }
        }

        push @projects, &Storable::dclone( $project );
    }
    
    return wantarray ? @projects : \@projects;
}

sub get_oklahoma_microbes_info
{
    # Bo Mikkelsen, October 2003.

    # TreeBuilder is used to extract info from the Advanced Center for Genome
    # Technology at University of Oklahoma's web pages regarding their microbial 
    # genomes - finished as well as drafts.
    # Some error checking is included since the procedure is obviously very
    # sensitive to changes at web site.

    my ( $errors
       ) = @_;
   
    # Returns array of hashes. 
  
    my ( $web_site, @finished_links, @finishing_links, $genome_html, $genome_tree,
         $conditions_url, $genus, $species, $strain, @ftp_files, $ftp_dir, $ftp_file,
         $status, $reference, $funding, @projects, $db_xref,
         @db_xref, @downloads, @funding, $file_list );


    # OKLAHOMA MICROBIAL GENOMES MAINPAGE
    $web_site = "http://www.genome.ou.edu";
    
    $conditions_url = "$web_site/data_release.html";
    
    @finished_links = (
                       "$web_site/strep.html",
                       "$web_site/smutans.html",
                       "$web_site/staph.html",
                       );
    
    @finishing_links = (
                        "$web_site/gono.html",
                        "$web_site/act.html",
                        "$web_site/bstearo.html",
                        "$web_site/spiro.html",
                        );
    
    $reference->{'Streptococcus'}->{'pyogenes'}->{'M1 GAS'} = "J.J. Ferretti, W.M. McShan, D. Ajdic, D. J. Savic, G. Savic, K. Lyon, S. Sezate, A. N. Suvorov, C. Primeaux, S. Kenton, H. Lai, S. Lin, Y. Qian, H. Jia, H. Zhu, Q. Ren, F.Z, Najar, L. Song, J. White, X. Yuan, S. W. Clifton, B. A. Roe, R. McLaughlin. Complete Genome Sequence of an M1 Strain of Streptococcus pyogenes Proc. Natl. Acad. Sci. USA. 98, 4658-4663 (2001).";
    $reference->{'Streptococcus'}->{'mutans'}->{'UA159'} = "Dragana Ajdic, William M. McShan, Robert E. McLaughlin, Gorana Savic, Jin Chang, Matthew B. Carson, Charles Primeaux, Runying Tian, Steve Kenton, Honggui Jia, Shaoping Lin, Yudong Qian, Shuling Li, Hua Zhu, Fares Najar, Hongshing Lai, Jim White, Bruce A. Roe, and Joseph J. Ferretti. Genome sequence of Streptococcus mutans UA159, a cariogenic dental pathogen. PNAS 99, 14434-14439 (2002).";
    $reference->{'Staphylococcus'}->{'aureus'}->{'NCTC 8325'} = "J. J. Iandolo, V. Worrell, K.H. Groicher, Y. Qian, R. Y. Tian, S. Kenton, A. Dorman, H-G. Jia, S. Lin, P. Loh, S. Qi, H. Zhu and B.A. Roe. Comparative analysis of the genomes of the temperate bacteriophages phi 11, phi 12 and phi 13 of Staphylococcus aureus 8325. Gene 289 109-118 (2002).";
    
    $db_xref->{'Streptococcus'}->{'pyogenes'}->{'M1 GAS'} = "AE004092";
    $db_xref->{'Streptococcus'}->{'mutans'}->{'UA159'} = "AEO14133";
    $db_xref->{'Neisseria'}->{'gonorrhoeae'}->{'FA 1090'} = "AE004969";
    
    $funding->{'Streptococcus'}->{'pyogenes'}->{'M1 GAS'} = "USPHS NIH grant \#AI38406";
    $funding->{'Streptococcus'}->{'mutans'}->{'UA159'} = "USPHS/NIH grant from the Dental Institute";
    $funding->{'Staphylococcus'}->{'aureus'}->{'NCTC 8325'} = "NIH and the Merck Genome Research Institute";
    $funding->{'Neisseria'}->{'gonorrhoeae'}->{'FA 1090'} = "USPHS NIH grant \#AI38399";
    $funding->{'Actinobacillus'}->{'actinomycetemcomitans'}->{'HK1651'} = "USPHS/NIH grant from the National Institute of Dental Research";
    $funding->{'Bacillus'}->{'stearothermophilus'}->{'10'} = "NSF EPSCoR Program (Experimental Program to Stimulate Competitive Research Grant \#EPS-9550478)";
    $funding->{"Spiroplasma"}->{"kunkelii"}->{"CR2-3x"} = "US Department of Agriculture, Agricultural Research Service cooperative agreement, and Dr. Robert E. Davis at the USDA";

    # Extract relevant data from each of the microbe's genome project
    
    foreach my $genome_url ( @finished_links )
    {
        $genome_html = &Common::HTTP::get_html_page( $genome_url, $errors );

        if ( defined $genome_html )
        {
            $genome_tree = HTML::TreeBuilder->new();
            $genome_tree->parse($genome_html);
            $genome_tree->eof;
        }
        else {
            push @{ $errors }, "ERROR: Oklahoma: Could not access $genome_url.\n";
        }


        $species = $genome_tree->look_down('_tag','h1')->as_trimmed_text;
        $species =~ s/ Genome Sequencing//;
        $species =~ s/ ?[Ss]train//;
        ($genus, $species, $strain) = split " ", $species, 3;


        $ftp_dir = $genome_tree->look_down('_tag','a',
            sub {
                return 1 if $_[0]->as_text =~ m/via ftp/ and $_[0]->attr('href') =~ m|ftp://ftp|;
            }
            )->attr('href');

        if ( not defined $ftp_dir ) {
            push @{ $errors }, qq (ERROR: Oklahoma: Could not extract ftp dir for "$genus $species $strain"\n);
        }
        else {
            # Get list of files from ftp directory...
            $file_list = &Common::Storage::list_files( $ftp_dir );
            if ( not defined $file_list ) {
                push @{ $errors }, qq (ERROR: Oklahoma: Could not open remote dir "$ftp_dir"\n);
                @downloads = ();
            }
            else {
                @downloads = map { [ $_->{"name"}, $_->{"dir"} ] } @{ $file_list };
                # Only fetch the fasta files...
                @downloads = grep { $_->[0] =~ /\.fa$/ } @downloads;
            }
        }

        if ( $funding->{$genus}->{$species}->{$strain} ) {
            @funding = [$funding->{$genus}->{$species}->{$strain}, ""];
        }
        else {
            @funding = ();
        }

        if ( $db_xref->{$genus}->{$species}->{$strain} ) {
            @db_xref = [ "GenBank", $db_xref->{$genus}->{$species}->{$strain} ];
        }
        else {
            @db_xref = ();
        }

        @downloads = &DNA::Genomes::Download::list_file_properties( \@downloads );

        push @projects,
        {
            "conditions_url" =>  $conditions_url,
            "institutions" => [[
                             "Advanced Center for Genome Technology, University of Oklahoma",
                             "$web_site",
                             ]],
            "from_site" => [[ "Oklahoma", $web_site ]],
            "organism_url"     =>  $genome_url,
            "project_url"      =>  $genome_url,
            "taxonomy"         =>  [],
            "genus"            =>  $genus,
            "species"          =>  $species,
            "subspecies"       =>  "",
            "strain"           =>  $strain,
            "category"         =>  "organism",
            "downloads"        =>  &Storable::dclone( \@downloads ),
            "sequence_format"  =>  "fasta",
            "status"           =>  "finished",
            "literature_urls"  =>  [
                                    [
                                     $reference->{$genus}->{$species}->{$strain},
                                     ""
                                     ]
                                    ],
            "db_xref"          =>  &Storable::dclone( \@db_xref ),
            "funding"          =>  &Storable::dclone( \@funding ),
        };

    }

    foreach my $genome_url ( @finishing_links )
    {
        $genome_html = &Common::HTTP::get_html_page( $genome_url, $errors );

        if ( defined $genome_html ) {
            $genome_tree = HTML::TreeBuilder->new();
            $genome_tree->parse($genome_html);
            $genome_tree->eof;
        }
        else {
            push @{ $errors }, "ERROR: Oklahoma: Could not access $genome_url.\n";
        }


        $species = $genome_tree->look_down('_tag','h1')->as_trimmed_text;
        $species =~ s/ Genome Sequencing//;
        $species =~ s/ ?[Ss]train//;
        $species =~ s/ \(\w+\)//;
        $species =~ s/ \-//;
        ($genus, $species, $strain) = split " ", $species, 3;


        $ftp_dir = $genome_tree->look_down('_tag','a',
            sub {
                return 1 if $_[0]->as_text =~ m/via ftp/ and $_[0]->attr('href') =~ m|ftp://ftp|;
            }
            )->attr('href');

        if ( not defined $ftp_dir ) {
            push @{ $errors }, qq (ERROR: Oklahoma: Could not extract ftp dir for "$genus $species $strain"\n);
        }
        else {
            # Get list of files from ftp directory...
            $file_list = &Common::Storage::list_files( $ftp_dir );
            if ( not defined $file_list ) {
                push @{ $errors }, qq (ERROR: Oklahoma: Could not open remote dir "$ftp_dir"\n);
                @downloads = ();
            }
            else {
                @downloads = map { [ $_->{"name"}, $_->{"dir"} ] } @{ $file_list };
                # Only fetch the fasta files...
                @downloads = grep { $_->[0] =~ /\.fa$/ } @downloads;
            }
        }


        if ( $funding->{$genus}->{$species}->{$strain} ) {
            @funding = [$funding->{$genus}->{$species}->{$strain}, ""];
        }
        else {
            @funding = ();
        }

        if ( $db_xref->{$genus}->{$species}->{$strain} ) {
            @db_xref = [ "GenBank", $db_xref->{$genus}->{$species}->{$strain} ];
        }
        else {
            @db_xref = ();
        }

        @downloads = &DNA::Genomes::Download::list_file_properties( \@downloads );

        push @projects,
        {
            "conditions_url" =>  $conditions_url,
            "institutions" => [[
                             "Advanced Center for Genome Technology, University of Oklahoma",
                             "$web_site",
                             ]],
            "from_site" => [[ "Oklahoma", $web_site ]],
            "organism_url"     =>  $genome_url,
            "project_url"      =>  $genome_url,
            "taxonomy"         =>  [],
            "genus"            =>  $genus,
            "species"          =>  $species,
            "subspecies"       =>  "",
            "strain"           =>  $strain,
            "category"         =>  "organism",
            "downloads"        =>  &Storable::dclone( \@downloads ),
            "sequence_format"  =>  "fasta",
            "status"           =>  "finishing",
            "literature_urls"  =>  [],
            "db_xref"          =>  &Storable::dclone( \@db_xref ),
            "funding"          =>  &Storable::dclone( \@funding ),
        };

    }

    return wantarray ? @projects : \@projects;
}

sub get_ncbi_microbes_info
{
    # Niels Larsen, May 2004.

    # Looks at the NCBI microbial web page and creates a list of hashes
    # with summary information about the projects. Information is extracted
    # out of html, so the procedure is sensitive to changes. 

    my ( $errors,        # List of error messages
       ) = @_;
   
    # Returns array of hashes. 
  
    my ( $http_base, $page_html, $row_html, @row, $row, $project, $r_files, 
         $ftp_dir, $name, $url, $org_html, $tax_html, @name, @org_links,
         $orgs_url, $org_url, @projects, $inst_name, $org_name, $downloads,
         $gbk_ftp, $genus, $species, $strain );

    $http_base = "http://www.ncbi.nlm.nih.gov";
    $orgs_url = "$http_base/genomes/Complete.html";
    $gbk_ftp = "ftp://ftp.ncbi.nih.gov/genomes/Bacteria";

    $downloads->{"Bacillus"}->{"cereus"}->{"ZK"} = "$gbk_ftp/Bacillus_cereus_ZK";
    $downloads->{"Bacillus"}->{"licheniformis"}->{"DSM 13"} = "$gbk_ftp/Bacillus_licheniformis_DSM_13";
    $downloads->{"Bacteroides"}->{"fragilis"}->{"YCH46"} = "$gbk_ftp/Bacteroides_fragilis_YCH46";
    $downloads->{"Borrelia"}->{"garinii"}->{"PB1"} = "$gbk_ftp/Borrelia_garinii_PBi";
    $downloads->{"Burkholderia"}->{"mallei"}->{"ATCC 23344"} = "$gbk_ftp/Burkholderia_mallei_ATCC_23344";
    $downloads->{"Burkholderia"}->{"pseudomallei"}->{"K96243"} = "$gbk_ftp/Burkholderia_pseudomallei_K96243";
    $downloads->{"Haloarcula"}->{"marismortui"}->{"ATCC 43049"} = "$gbk_ftp/Haloarcula_marismortui_ATCC_43049";
    $downloads->{"Legionella"}->{"pneumophila"}->{"Lens"} = "$gbk_ftp/Legionella_pneumophila_Lens";
    $downloads->{"Legionella"}->{"pneumophila"}->{"Paris"} = "$gbk_ftp/Legionella_pneumophila_Paris";
    $downloads->{"Legionella"}->{"pneumophila"}->{"Philadelphia 1"} = "$gbk_ftp/Legionella_pneumophila_Philadelphia_1";
    $downloads->{"Mannheimia"}->{"succiniciproducens"}->{"MBEL55E"} = "$gbk_ftp/Mannheimia_succiniciproducens_MBEL55E";
    $downloads->{"Methylococcus"}->{"capsulatus"}->{"Bath"} = "$gbk_ftp/Methylococcus_capsulatus_Bath";
    $downloads->{"Mycoplasma"}->{"hyopneumoniae"}->{"232"} = "$gbk_ftp/Mycoplasma_hyopneumoniae_232";
    $downloads->{"Nocardia"}->{"farcinica"}->{"IFM 10152"} = "$gbk_ftp/Nocardia_farcinica_IFM10152";
    $downloads->{"Photobacterium"}->{"profundum"}->{"SS9"} = "$gbk_ftp/Photobacterium_profundum_SS9";
    $downloads->{"Staphylococcus"}->{"aureus"}->{"MRSA252"} = "$gbk_ftp/Staphylococcus_aureus_aureus_MRSA252";
    $downloads->{"Staphylococcus"}->{"aureus"}->{"MSSA476"} = "$gbk_ftp/Staphylococcus_aureus_aureus_MSSA476";
    $downloads->{"Streptococcus"}->{"thermophilus"}->{"CNRZ1066"} = "$gbk_ftp/Streptococcus_thermophilus_CNRZ1066";  # doesnt exist now, but probably will
    $downloads->{"Streptococcus"}->{"thermophilus"}->{"LMG 18311"} = "$gbk_ftp/Streptococcus_thermophilus_LMG18311";  # doesnt exist now, but probably will
    $downloads->{"Symbiobacterium"}->{"thermophilum"}->{"IAM 14863"} = "$gbk_ftp/Symbiobacterium_thermophilum_IAM14863";
    $downloads->{"Yersinia"}->{"pseudotuberculosis"}->{"IP 32953"} = "$gbk_ftp/Yersinia_pseudotuberculosis_IP32953";
    $downloads->{"Sulfolobus"}->{"solfataricus"}->{"P2"} = "$gbk_ftp/Sulfolobus_solfataricus";

    $downloads->{"Corynebacterium"}->{"efficiens"}->{"YS-314"} = "$gbk_ftp/Corynebacterium_efficiens_YS-314";
    $downloads->{"Mesoplasma"}->{"florum"}->{"L1"} = "$gbk_ftp/Mesoplasma_florum_L1";
    $downloads->{"Methanococcus"}->{"maripaludis"}->{"S2"} = "$gbk_ftp/Methanococcus_maripaludis_S2";
    $downloads->{"Picrophilus"}->{"torridus"}->{"DSM 9790"} = "$gbk_ftp/Picrophilus_torridus_DSM_9790";
    $downloads->{"Staphylococcus"}->{"epidermidis"}->{"ATCC 12228"} = "$gbk_ftp/Staphylococcus_epidermidis_ATCC_12228";
    $downloads->{"Streptococcus"}->{"agalactiae"}->{"2603V/R"} = "$gbk_ftp/Streptococcus_agalactiae_2603";
    $downloads->{"Streptococcus"}->{"pyogenes"}->{"MGAS8232"} = "$gbk_ftp/Streptococcus_pyogenes_MGAS8232";
    $downloads->{"Streptococcus"}->{"pyogenes"}->{"SSI-1"} = "$gbk_ftp/Streptococcus_pyogenes_SSI-1";
    $downloads->{"Tropheryma"}->{"whipplei"}->{"TW08/27"} = "$gbk_ftp/Tropheryma_whipplei_TW08_27";
    $downloads->{"Yersinia"}->{"pestis"}->{"CO92"} = "$gbk_ftp/Yersinia_pestis_CO92";
    $downloads->{"Yersinia"}->{"pestis"}->{"biovar Mediaevails 91001"} = "$gbk_ftp/Yersinia_pestis_biovar_Mediaevails";

    $page_html = &Common::HTTP::get_html_page( $orgs_url, $errors );

    if ( not defined $page_html )
    {
        push @{ $errors }, "ERROR: NCBI: could not access $orgs_url.\n";
        return;
    }

    while ( $page_html =~ /<tr bgcolor="#FFFFFE">(.+?)<\/tr>/sgi )
    {
        $row_html = $1;

        @row = ();

        # ----- Strip tags and put html table links into a list,

        while ( $row_html =~ /<td.*?>\s*(.+?)\s*<\/td>/sgi )
        {
            $row = $1;

            if ( $row =~ /a href/ )
            {
                $row =~ s/[\n\r]//g;                             # some links are wrapped

                if ( $row =~ /^\s*<a href=\"(.+?)\">(.+?)<\/a>\s*/ )
                {
                    $url = $1;
                    $name = $2;

                    $url =~ s/\/$//;                                # strip trailing slash
                    $url = "http://$url" if $url !~ /^http|ftp/;   # prepend http or ftp if missing
                }
                else
                {
                    $url = "";
                    $name = "";
                    push @{ $errors }, qq (ERROR: NCBI: element looks wrong -> "$row"\n);
                }
            }
            else
            {
                $url = "";
                $name = $row;
            }

            $name =~ s/<b>(.+)<\/?b>/$1/;                 # bold tags gone
            $name =~ s/<i>(.+)<\/?i>/$1/;                 # italics tags gone
            $name =~ s/<font.+?>(.+)<\/?font>/$1/;        # font tags gone
            
            push @row, [ $url, $name ];
        }

        # ------ There is nothing to fill into these,

        $project = {};

        $project->{"from_site"} = [[ "NCBI", $orgs_url ]];
        $project->{"conditions_url"} = "";
        $project->{"db_xref"} = [];
        $project->{"funding"} = [];
        $project->{"category"} = "organism";
        $project->{"status"} = "finished";
        $project->{"sequence_format"} = "";
        $project->{"literature_urls"} = [];
        $project->{"project_url"} = "";

        # ------ Institution link and name,

        push @{ $project->{"institutions"} }, [ $row[5]->[1], $row[5]->[0] ];

        # ------ Taxonomy ranking and id, genus, species, subspecies,

        $org_url = $row[0]->[0];
        $org_html = &Common::HTTP::get_html_page( $org_url, $errors );        
        
        # Sometimes the same organism has been done by different sites. Then
        # NCBI links to an intermediate page, which we then need to skip and
        # get the right one (bah),

        if ( $org_html !~ /\s*Taxonomy\s+ID:\s*/ )
        {
            $inst_name = $row[5]->[1];      # Institution name
            $org_name = $row[0]->[1];

            if ( $org_html =~ /<a.+?href="\/?([^\"]+?)">[^\"]+$inst_name/i or 
                 $org_html =~ /<a.+?href="\/?([^\"]+?wwwtax\.cgi\?mode=Info[^\"]+?)">[^\"]+$org_name/i )
            {
                $org_url = "$http_base/$1";
                $org_html = &Common::HTTP::get_html_page( $org_url, $errors );

                if ( not $org_html ) {
                    &warning( qq (ERROR: NCBI: could not access $org_url.\n) );
                    next;
                }
            }
            else {
                &error( qq (NCBI: Institution name not found -> "$name") );
                exit;
            }
        }

        $project->{"organism_url"} = $org_url;

        # ------ Genus, species, subspecies and strain,

        %{ $project } = ( %{ $project }, &DNA::Genomes::Download::parse_org_name( $row[0]->[1] ) );

        # -------- Taxonomy id and rankings,

        if ( $org_html =~ /<em>\s*Taxonomy\s*ID:\s*<\/em>(\d+)/i )
        {
            $project->{"taxonomy_id"} = $1;
        }
        else
        {
            $project->{"taxonomy_id"} = "";
            &warning( qq (Taxonomy ID not found -> "$name") );
        }

        $org_html =~ /<dd>(.+?)<\/dd>/i;
        $tax_html = $1;

        while ( $tax_html and $tax_html =~ /<a.+?>(.+?)<\/a>/sgi )
        {
            push @{ $project->{"taxonomy"} }, $1;
        }

        $project->{"taxonomy"}->[0] = ucfirst $project->{"taxonomy"}->[0];

        # ------ Literature,

        if ( $org_html =~ /<a href=\"\/?([^\"]+db=PubMed[^\"]+)\".+?<dd>(.+?)<\/dd>/si )
        {
            push @{ $project->{"literature_urls"} }, [ $2, "$http_base/$1" ];
        }

         # ------ File locations, 

        $genus = $project->{"genus"};
        $species = $project->{"species"};
        $strain = $project->{"strain"};

        if ( exists $downloads->{ $genus }->{ $species }->{ $strain } ) {
            $ftp_dir = $downloads->{ $genus }->{ $species }->{ $strain };
        } else {
            $ftp_dir = $row[12]->[0];
        }

        if ( $ftp_dir )
        {
            if ( $r_files = &Common::Storage::list_files( $ftp_dir ) )
            {
                if ( @{ $r_files } )
                { 
                    $project->{"downloads"} = &Storable::dclone( $r_files );
#                    $project->{"downloads"} = [ grep { $_->{"name"} !~ /\.asn/ } @{ $project->{"downloads"} } ];
                }
                else 
                {
                    $project->{"downloads"} = [];
                    push @{ $errors }, qq (WARNING: NCBI: Remote dir is empty -> "$ftp_dir"\n);
                }
            }
            else
            {
                $project->{"downloads"} = [];
                push @{ $errors }, qq (ERROR: NCBI: Remote dir does not exist -> "$ftp_dir"\n);
            }
        }
        else {
            $project->{"downloads"} = [];
        } 
        
        push @projects, &Storable::dclone( $project );
    }
 
    return wantarray ? @projects : \@projects;
}

sub get_wustl_microbes_info
{
    # Bo Mikkelsen, November 2003.

    # TreeBuilder is used to extract info from the Genome Sequencing Center,
    # Washington University in St.Louis (WUSTL) web pages regarding their 
    # microbial genomes.
    # Some error checking is included since the procedure is obviously very
    # sensitive to changes at web site.

    my ( $errors
       ) = @_;
   
    # Returns array of hashes. 
  
    my ( $web_site, $microbial_url, $microbial_index_html, $microbial_index_tree,
         $projects_table, @project_rows, @microbes, $microbe_name, $microbe_link,
         $microbe_strain, $microbe_status, $subspecies, $genus, $species, $strain,
         $microbe_html, $microbe_tree, $ftp_dir, $file_list, $ftp_file, @literature_urls,
         $funding, $grant, @projects, @downloads, @funding );


    # WUSTL MICROBIAL GENOMES MAINPAGE
    $web_site = "http://www.genome.wustl.edu";
    $microbial_url = "$web_site/projects/bacterial/";

    # Get the mainpage html and parse it into a TreeBuilder tree
    $microbial_index_html = &Common::HTTP::get_html_page( $microbial_url, $errors );
    if ( defined $microbial_index_html ) {
        $microbial_index_tree = HTML::TreeBuilder->new();
        $microbial_index_tree->parse($microbial_index_html);
        $microbial_index_tree->eof;
    }
    else {
        push @{ $errors }, "ERROR: WUSTL: Could not access $microbial_url.\n";
        return;
    }

    # Extract rows with microbe info from table with bacterial projects info
    $projects_table = ( $microbial_index_tree->look_down ('_tag', 'table', 'cellspacing', '2') )[0];
    $projects_table = $projects_table->look_down ('_tag', 'td')->look_down ('_tag', 'table');

    @project_rows = $projects_table->look_down ( '_tag', 'tr');
    @project_rows = @project_rows[ 1..$#project_rows ];


    # From the table rows extract info and links to the microbes mainpages
    if ( @project_rows )
    {
        foreach my $microbe ( @project_rows )
        {
            $microbe_name = ( $microbe->look_down ( '_tag', 'td' ) )[0]->look_down ( '_tag', 'a' )->as_trimmed_text;
            $microbe_link = ( $microbe->look_down ( '_tag', 'td' ) )[0]->look_down ( '_tag', 'a' )->attr('href');
            $microbe_link = "$web_site/$microbe_link";
            $microbe_strain = ( $microbe->look_down ( '_tag', 'td' ) )[2]->as_trimmed_text;
            $microbe_status = ( $microbe->look_down ( '_tag', 'td' ) )[4]->as_trimmed_text;

            # Get genus, species, subspecies and strain

            ($genus, $species, $strain) = split " ", $microbe_name, 3;

            if ( defined $strain )
            {
                if ( $strain =~ m/subspecies/ ) {
                    $strain =~ s/subspecies (\S+) //;
                    $subspecies = $1;
                }
                else {
                    $subspecies = "";
                }
                if ( defined $microbe_strain ) {
                    $strain = "$strain ($microbe_strain)";
                }
            }
            else {
                $strain = $microbe_strain;
            }

            # Literature link ...

            if ( $genus eq "Salmonella" and $species eq "enterica" and $microbe_strain eq "LT2") {
                @literature_urls = [ "Nature", $microbe_link."nature.pdf" ];
            }
            else {
                @literature_urls = ();
            }

            # Set status

            $microbe_status =~ s/Starting Shotgun|Survey Shotgun Completed/in progress/;
            $microbe_status =~ s/In Finishing|In Annotation/finishing/;
            $microbe_status =~ s/Finished/finished/;
            
            $microbe_html = &Common::HTTP::get_html_page( $microbe_link, $errors );

            if ( defined $microbe_html )
            {
                $microbe_tree = HTML::TreeBuilder->new();
                $microbe_tree->parse($microbe_html);
                $microbe_tree->eof;
            }
            else {
                push @{ $errors }, "ERROR: WUSTL: Could not access $microbe_link.\n";
            }

            $ftp_dir = $microbe_tree->look_down('_tag','a',
                sub {
                return 1 if $_[0]->as_text =~ m/ftp/i and $_[0]->attr('href') =~ m|ftp://|;
            }
            );

            if ( not defined $ftp_dir )
            {
                if ( $microbe_status =~ m/finishing|finished/ ) {
                    push @{ $errors }, qq (ERROR: WUSTL: Could not extract ftp dir for "$genus $species $strain"\n);
                }

                @downloads = ();
            }
            else
            {
                $ftp_dir = $ftp_dir->attr('href');

                # Get list of files from ftp directory...
                $file_list = &Common::Storage::list_files( $ftp_dir );

                if ( not defined $file_list ) {
                    push @{ $errors }, qq (ERROR: WUSTL: Could not open remote dir "$ftp_dir"\n);
                    @downloads = ();
                }
                else {
                    if ( $genus eq "Klebsiella" and $species eq "pneumoniae" and $microbe_strain eq "MCG 78578" ) {
                        # Sort according to mtime to get the name of the newest file...
                        $ftp_file = (sort { $a->{'mtime'} <=> $b->{'mtime'} } @{ $file_list } )[-1]->{'name'};
                        @downloads = [ $ftp_file, $ftp_dir ];
                    }
                    elsif ( $genus eq "Salmonella" and $species eq "enterica" and $microbe_strain eq "LT2" ) {
                        @downloads = map { [ $_->{"name"}, $_->{"dir"} ] } @{ $file_list };
                        # Only fetch the fasta files...
                        @downloads = grep { $_->[0] =~ /\.fasta$/ } @downloads;
                    }
                    else {
                        @downloads = map { [ $_->{"name"}, $_->{"dir"} ] } @{ $file_list };
                    }
                }
            }

            @downloads = &DNA::Genomes::Download::list_file_properties( \@downloads );

            push @projects,
            {
                "conditions_url"   =>  [],
                "institutions"     =>  [[
                                         "Genome Sequencing Center, Washington University in St.Louis",
                                         "http://hgsc.bcm.tmc.edu"
                                         ]],
                "from_site"        =>  [[ "WUSTL", $microbial_url ]],
                "organism_url"     =>  $microbe_link,
                "project_url"      =>  $microbe_link,
                "taxonomy"         =>  [],
                "genus"            =>  $genus,
                "species"          =>  $species,
                "subspecies"       =>  $subspecies,
                "strain"           =>  $strain,
                "category"         =>  "organism",
                "downloads"        =>  &Storable::dclone( \@downloads ),
                "sequence_format"  =>  "fasta",
                "status"           =>  $microbe_status,
                "literature_urls"  =>  &Storable::dclone( \@literature_urls ),
                "db_xref"          =>  [],
                "funding"          =>  [[ 
                                          "National Human Genome Research Institute at the National Institutes of Health",
                                          "" 
                                          ]]
            };


        }
    }
    else {
        push @{ $errors }, "ERROR: WUSTL: No microbes links - the $microbial_url html must have changed.\n";
    }
    
    return wantarray ? @projects : \@projects;
}

sub get_baylor_microbes_info
{
    # Niels Larsen, November 2004.

    # Gets projects from Baylor college of medicine. 

    my ( $errors,
       ) = @_;
   
    # Returns array of hashes. 
  
    my ( $http_base, $projects_html, $url, $abbrev, $org_url, $org_html, $project,
         $genus, $species, $subspecies, $name, $strain, $ftp_dir, @files, @projects,
         $ftp_base, $funding );

    $http_base = "http://www.hgsc.bcm.tmc.edu/projects/microbial";
    $ftp_base = "ftp://ftp.hgsc.bcm.tmc.edu/pub/data";
    
    $projects_html = &Common::HTTP::get_html_page( $http_base, $errors );

    while ( $projects_html =~ /<a href=\"\/projects\/microbial\/([^\"]+)\">.{25,35}\(more information\)/gi )
    {
        $abbrev = $1;
        $org_url = "$http_base/$abbrev";

        if ( $abbrev eq "Tdenticola" ) {
            $org_html = &Common::HTTP::get_html_page( "$org_url/tdenticola-overview.html", $errors );
        } else {
            $org_html = &Common::HTTP::get_html_page( $org_url, $errors );
        }
            
        $org_html =~ s/\n//g;

        undef $project;

        # Common settings, 

        $project->{"institutions"} = [[
                                       "Human Genome Sequencing Center, Baylor College of Medicine",
                                       "http://hgsc.bcm.tmc.edu",
                                       ]];

        $project->{"from_site"} = [[ "Baylor", $http_base ]];
        $project->{"taxonomy"} = [];
        $project->{"category"} = "organism";
        $project->{"sequence_format"} = "fasta";
        $project->{"db_xref"} = [];
        $project->{"literature_urls"} = [];
        $project->{"status"} = "finishing";   # not specified, looks this way

        # Pages,

        $project->{"organism_url"} = $org_url;
        $project->{"project_url"} = $org_url;

        # Genus, species and subspecies,

        $project->{"genus"} = "";
        $project->{"species"} = "";
        $project->{"subspecies"} = "";

        if ( $org_html =~ /<i>([A-Z][a-z]+)\s+([a-z]+)\s*([a-z]+)?<\/i>/ )
        {
            $genus = $1;
            $species = $2 || "";
            $subspecies = $3 || "";
            
            $project->{"genus"} = $genus;
            $project->{"species"} = $species;
            $project->{"subspecies"} = $subspecies;
        }
        elsif ( $abbrev eq "Tdenticola" )
        {
            $project->{"genus"} = "Treponema";
            $project->{"species"} = "denticola";
            $project->{"subspecies"} = "";
        }
        else {
            push @{ $errors }, qq (ERROR: Baylor: Could not get genus, species or subspecies from "$abbrev"\n);
        }

        # Strain,

        if ( $org_html =~ /Strain:\s*<\/td>\s*<td>\s*<a href=\"http:[^\"]+\">([^<]+)<\/a>\s*<\/td>/ or
             $org_html =~ /Strain:\s*<\/td>\s*<td>\s*([^<]+)<\/td>/ )
        {
            $strain = $1;
            $strain =~ s/^\s*//;
            $strain =~ s/\s*$//;
            $strain = "" if $strain !~ /\w/;

            $project->{"strain"} = $strain;
        }
        else {
            push @{ $errors }, qq (ERROR: Baylor: Could not get strain from "$abbrev"\n);
        }
            
        # Download files,

        if ( $abbrev eq "Tdenticola" )
        {
            @files = &Common::Storage::list_files( "$ftp_base/$abbrev/current" );
            @files = grep { $_->{"name"} =~ /-genome$/ } @files;
        }            
        elsif ( $abbrev eq "Tpallidum" )
        {
            @files = &Common::Storage::list_files( "$ftp_base/$abbrev/genome" );
            @files = grep { $_->{"name"} =~ /\.fa$/ } @files;
        }
        elsif ( $abbrev eq "Rtyphi" )
        {
            @files = &Common::Storage::list_files( "$ftp_base/$abbrev" );
            @files = grep { $_->{"name"} =~ /final/i } @files;
        }
        elsif ( $org_html =~ /<a href=\"(ftp:\/\/[^\"]+)/ )
        {
            $ftp_dir = $1;
            $ftp_dir =~ s/\/\s*$//;

            @files = &Common::Storage::list_files( "$ftp_dir/contigs" );
            @files = grep { $_->{"name"} =~ /\.fa$/ } @files;
        }

        if ( @files )
        {
            $project->{"downloads"} = [ grep { $_->{"name"} !~ /contigs\.fa$/ } @files ]; 

            @files = grep { $_->{"name"} =~ /contigs\.fa$/ } @files;

            if ( @files )
            {
                @files = sort { $b->{'mtime'} <=> $a->{'mtime'} } @files;
                push @{ $project->{"downloads"} }, $files[0];
            }
        }
        else {
            $project->{"downloads"} = [];
        }

        # Funding,

        if ( $org_html =~ /Funding:\s*<\/td>\s*<td>\s*([^<]+)<\/td>/ )
        {
            $funding = $1;
            $funding =~ s/;\s*//;
            $funding =~ s/^\s*//;
            $funding =~ s/\s*$//;

            $project->{"funding"} = [ $funding, "" ];
        }
        else {
            push @{ $errors }, qq (ERROR: Baylor: Could not get funding string from "$abbrev"\n);
        }
            
        push @projects, &Storable::dclone( $project );
    }

    return wantarray ? @projects : \@projects;
}

sub get_jgi_microbes_info
{
    # Bo Mikkelsen, July 2003.

    # TreeBuilder is used to extract info from the DOE Joint Genome Institute's
    # web pages regarding their microbial genomes - finished as well as drafts.
    # Some error checking is included since the procedure is obviously very
    # sensitive to changes at web site.

    my ( $errors,
       ) = @_;
   
    # Returns array of hashes. 
  

    my %status_map = (    # Maps from the JGI's status categories (draft genomes)
                          "I"=>"in progress",
                          "II"=>"in progress",
                          "III"=>"in progress",
                          "IV"=>"finishing",
                          "V"=>"finished"
                          );

    my ( $microbial_url, $microbial_index_html, $microbial_index_tree,
         @finished_links, @draft_links, @genomes_links, $genus, $species,
         $dir, $info_url, $info_html, $info_tree, $details_table, $strain_row,
         $strain, $GBid_row, $GBid, $funding_row, $funding, $license_url,
         $home_url, $download_url, $download_html, $download_tree, $ftp_cell,
         $ftp_uri, $ftp_dir, $ftp_file, $phase_row, $phase, $status, $ftp_html,
         $ftp_tree, $file_line_txt, $file_line, @data, @ftp_files, @downloads );


    # JGI MICROBIAL GENOMES MAINPAGE
    $microbial_url = "http://genome.jgi-psf.org/microbial";

    # Get the mainpage html and parse it into a TreeBuilder tree

    $microbial_index_html = &Common::HTTP::get_html_page( $microbial_url, $errors );

    if ( defined $microbial_index_html ) {
        $microbial_index_tree = HTML::TreeBuilder->new();
        $microbial_index_tree->parse($microbial_index_html);
        $microbial_index_tree->eof;
    }
    else {
        push @{ $errors }, "ERROR: JGI: Could not access $microbial_url.\n";
        return;
    }

    # From the tree extract links to the finished microbes mainpages
    @finished_links = $microbial_index_tree->look_down (
        '_tag', 'a',
        sub {
            return 1 if $_[0]->attr('href') =~ m{/finished_microbes/} and $_[0]->as_text =~ m/\S+/;
        }
    );

    if ( @finished_links )
    {
        foreach my $link ( @finished_links ) {
            push @genomes_links, [$link->attr('href'), $link->as_text , "finished"];
        }
    }
    else {
        push @{ $errors }, "ERROR: JGI: No finished microbes links - the $microbial_url html must have changed.\n";
    }
    
    # From the tree extract links to the draft microbes mainpages

    @draft_links = $microbial_index_tree->look_down ( # !
        '_tag', 'a',
        sub {
            return 1 if $_[0]->attr('href') =~ m{/draft_microbes/} and $_[0]->as_text =~ m/\S+/;
        }
    );

    if ( @draft_links )
    {
        foreach my $link ( @draft_links ) {
            push @genomes_links, [$link->attr('href'), $link->as_text, "draft" ];
        }
    }
    else {
        push @{ $errors }, "ERROR: JGI: No draft microbes links - the $microbial_url html must have changed.\n";
    }


    # Extract relevant data from each of the microbe's genome project

    foreach my $elem ( @genomes_links )
    {
        $$elem[1] =~ s/\s+$//;
        ($genus, $species) = split " ", $$elem[1];  # this split will ignore a leading space
        $species = "" unless $species;

        # Set a bunch of finished/draft urls
        if ( $$elem[2] eq "finished" )
        {
            $dir = $$elem[0];
            $dir =~ s/\/([^\s\/]+)\/$//;
            $dir = $1;
            $info_url = $$elem[0].$dir.".info.html";
            $license_url = $$elem[0].$dir.".download.html";
            $home_url = $$elem[0].$dir.".home.html";
            $download_url = $$elem[0].$dir.".download.ftp.html";
        }
        else
        {
            $info_url = $$elem[0];
            $info_url =~ s/home/info/;
            $license_url = $$elem[0];
            $license_url =~ s/home/download/;
            $home_url = $$elem[0];
            $download_url = $$elem[0];
            $download_url =~ s/home/download.ftp/;
        }

        # Get the Info html and extract strain, GenBank ID, and funding info
        $info_html = &Common::HTTP::get_html_page( $info_url, $errors );

        if ( defined $info_html )
        {
            $info_tree = HTML::TreeBuilder->new();
            $info_tree->parse($info_html);
            $info_tree->eof;
        }
        else {
            push @{ $errors }, "ERROR: JGI: Could not access $info_url.\n";
        }

        $details_table = $info_tree->look_down ( # !
            '_tag', 'table',
            sub {
                my $row = $_[0]->look_down('_tag','tr',
                         sub {
                      my $cell = $_[0]->look_down('_tag','td');
                      return 1 if $cell->as_text =~ m/Strain:/;
                  }
                );
            }
        );

        $strain_row = $details_table->look_down('_tag','tr',
            sub {
                my $cell = $_[0]->look_down('_tag','td');
                return 1 if $cell->as_text =~ m/Strain:/;
            }
        );

        if ( not $strain_row ) {
            push @{ $errors }, "ERROR: JGI: Could not fetch strain info for $genus $species - the $info_url html must have changed.\n";
        }
        else {
            $strain = ( $strain_row->look_down('_tag','td') )[-1]->as_trimmed_text;
            $strain =~ s/^\W+//;
            $strain =~ s/ and .*$//;
        }

        if ( $strain eq $species ) { # $species as extracted from the main table may be strain id
            $species = "";
        }

        $GBid_row = $details_table->look_down('_tag','tr',
            sub {
                my $cell = $_[0]->look_down('_tag','td');
                return 1 if $cell->as_text =~ m/GenBank ID:/;
            }
        );

        $GBid = ( $GBid_row->look_down('_tag','td') )[-1]->as_trimmed_text if $GBid_row;

        if ( $$elem[2] eq "finished" ) {
            $status = "finished";
        }
        else {
            $phase_row = $details_table->look_down('_tag','tr',
                sub {
                    my $cell = $_[0]->look_down('_tag','td');
                    return 1 if $cell->as_text =~ m/Phase:/;
                }
            );

            if ( not $phase_row ) {
                push @{ $errors }, "ERROR: JGI: Could not fetch status info for $genus $species - the $info_url html must have changed.\n";
            }
            else {
                $phase = ( $phase_row->look_down('_tag','td') )[-1]->as_trimmed_text;
                $status = $status_map{$phase};
            }
        }

        $funding_row = $info_tree->look_down('_tag','tr',
            sub {
                my @cell = $_[0]->look_down('_tag','td');
                return 1 if $cell[-1]->as_text =~ m/Funding/;
            }
        )->right;

        if ( not $funding_row ) {
            push @{ $errors }, "ERROR: JGI: Could not fetch funding info for $genus $species - the $info_url html must have changed.\n";
        }
        else {
            $funding = ( $funding_row->look_down('_tag','td') )[-1]->as_trimmed_text;
        }

        # Get the download info
        $download_html = &Common::HTTP::get_html_page( $download_url, $errors );

        if ( defined $download_html )
        {
            $download_tree = HTML::TreeBuilder->new();
            $download_tree->parse($download_html);
            $download_tree->eof;
        }
        else {
            push @{ $errors }, "ERROR: JGI: Could not access $download_url.\n";
        }

        $ftp_cell = $download_tree->look_down ( # !
            '_tag', 'a',
            sub {
                return 1 if $_[0]->attr('href') =~ m/ftp/;
            }
        );

        if ( not $ftp_cell ) {
            push @{ $errors }, "ERROR: JGI: Could not fetch download info for $genus $species - the $download_url html must have changed.\n";
        }
        else
        {
            $ftp_uri = $ftp_cell->attr('href');
            $ftp_uri =~ s/\s//g;
            $ftp_uri =~ s/\.fasta\/$/.fasta/;    # Remove trailing / from ftp filename. These
            $ftp_uri =~ s/\.fsa\/$/.fsa/;        #  Remove trailing / from ftp filename. These
            $ftp_uri =~ s/\.contigs\/$/.contigs/;  # end in .fasta or .contig
            $ftp_uri =~ m/(^.*)\/(.*)$/;
            $ftp_dir = $1;
            $ftp_file = $2;

            if ( $ftp_file eq "" ) { # Some links only specify the ftp directory!!!
                # Get list of files from ftp directory...
                @ftp_files = Common::Storage::list_files( $ftp_dir );
                $ftp_file = $ftp_files[-1]{'name'};
            }

        }

        @downloads = &DNA::Genomes::Download::list_file_properties( [[ $ftp_file, $ftp_dir ]] );
        
        push @data,
        {
            "conditions_url" =>  $license_url,
            "institutions" => [[
                             "DOE Joint Genome Institute",
                             "http://www.jgi.doe.gov",
                             ]],
            "from_site" => [[ "JGI", $microbial_url ]],
            "organism_url"     =>  $home_url,
            "project_url"      =>  $info_url,
            "taxonomy"         =>  [],
            "genus"            =>  $genus,
            "species"          =>  $species,
            "subspecies"       =>  "",
            "strain"           =>  $strain,
            "category"         =>  "organism",
            "downloads"        =>  &Storable::dclone( \@downloads ),
            "sequence_format"  =>  "fasta",
            "status"           =>  $status,
            "literature_urls"  =>  [],
            "db_xref"          =>  [[
                                     "GenBank", 
                                     $GBid
                                    ]],
            "funding" =>  [[
                            $funding,
                            ""
                            ]]
        };

    }

    return wantarray?@data:\@data;
}

sub template
{
    return 
    {
        "conditions_url" => "url to licensing/usage page",
        "institutions" => [ [ "institution name", "institution url" ] ],
        "from_site" => [ [ "site name", "site url" ] ],
        "organism_url" => "url to page that describes organism ",
        "project_url" => "url to page that describes project",
        "taxonomy" => [ "taxon", "taxon", ".." ],
        "taxonomy_id" => "",
        "genus" => "",
        "species" => "",
        "subspecies" => "",
        "strain" => "",
        "category" => "type of genome, e.g organism, virus, chloroplast .. ",
        "downloads" => [ { }, { } ],
        "sequence_format" => "string",
        "status" => "planned or in progres or finishing or finished",
        "literature_urls" => [ [ "reference text", "reference url" ] ],
        "db_xref" => [ [ "database name", "database id" ] ],
        "funding" => [ [ "sponsor name", "sponsor url" ] ],
    };
}

1;

__END__
