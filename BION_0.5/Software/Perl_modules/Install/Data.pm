package Install::Data;     #  -*- perl -*-

# Routines that do data download and installation. More dataset specific
# routines are in Install::Download and Install::Import. 
#
# TODO: data installation is in very bad shape and needs a rework. There
# are now {RNA,DNA,Protein}::Download and {RNA,DNA,Protein}::Import modules
# and some under Seq and some under Common. This mess should be 
# consolidated.

use strict;
use warnings FATAL => qw ( all );

use English;
use Time::Local;
use Tie::IxHash;
use Data::Structure::Util;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &ask_confirmation
                 &check_datasets
                 &check_routines
                 &confirm_menu
                 &create_import_list
                 &create_missing_datadirs
                 &create_ofile_list
                 &create_registry_entries
                 &divide_files
                 &download_dataset
                 &download_files
                 &expand_tokens
                 &export_derived_data
                 &filter_file_lists
                 &filter_owned_datasets
                 &import_alignment
                 &import_alignments
                 &import_dataset
                 &import_datasets
                 &import_expression
                 &import_patterns
                 &import_sequences
                 &index_sequences
                 &install_data
                 &install_projects
                 &list_datasets
                 &list_projects
                 &name_download_routine
                 &name_import_routine
                 &name_uninstall_routine
                 &needs_import
                 &run_commands
                 &uninstall_dataset
                 &uninstall_dataset_db
                 &uninstall_data
                 &uninstall_genomes_ebi
                 &uninstall_projects
                 &updates_available
                 );

use Common::Config;
use Common::Messages;

use Common::Types;
use Common::Util;
use Common::Menus;
use Common::Admin;
use Common::Names;
use Common::Import;
use Common::Download;
use Common::Obj;

use Registry::Get;
use Registry::Option;
use Registry::Register;
use Registry::List;
use Registry::Check;

use Install::Profile;
use Install::Config;
use Install::Download;
use Install::Import;

use Seq::IO;
use Seq::Info;
use Seq::Storage;

use Expr::Import;

local $| = 1;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Linwid = 74;
our $Sys_name = $Common::Config::sys_name;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub ask_confirmation
{
    # Niels Larsen, April 2008.

    # Given a list of datasets returns those that the user wants by 
    # responding to interactive prompts. No response in 10 seconds
    # means "yes".

    my ( $all_dbs,
         $type,
        ) = @_;

    my ( $pause, @dbs, $db, $title, $answer, $prompt );

    require Term::ReadKey;

    $pause = 10;
    $type = ucfirst $type;
    
    &echo_yellow( "\n" );
    &echo_yellow( qq (   You may enter "yes" or "no" to the questions below.\n) );
    &echo_yellow( qq (   If no answer within $pause seconds, "yes" is assumed.\n) );
    &echo_yellow( "\n" );
    
    foreach $db ( @{ $all_dbs } )
    {
        $title = $db->title;
        $prompt = &echo( "   $type $title? [yes] " );
        
        $answer = &Common::File::read_keyboard( $pause, $prompt );
        $answer = "yes" if not $answer;
        
        if ( $answer =~ /^yes$/i )
        {
            push @dbs, $db;
            &echo( " - " );
            &echo_green( "ok, will do\n" );
        }
        else {
            &echo( " - " );
            &echo( "ok, will skip\n" );
        }
    }
    
    &echo( "\n" );

    return wantarray ? @dbs : \@dbs;
}

sub check_datasets
{
    # Niels Larsen, July 2012.

    # Checks that a given list of names all uniquely match dataset names
    # in the registry. Errors are returned if a list is given, otherwise 
    # printed. 

    my ( $names,    # Dataset name list
         $msgs,     # Error list - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( @dbs, @dball, $name, $db, @msgs, @hits, $hit, $text );

    @dball = map { [ $_->name, $_->tiptext ] } Registry::Get->datasets()->options;
    $text = "";

    foreach $name ( @{ $names } )
    {
        @hits = grep { $_->[0] =~ /$name/i } @dball;

        if ( scalar @hits == 1 )
        {
            push @dbs, $hits[0]->[0];
        }
        else
        {
            if ( @hits ) 
            {
                $text .= "\n  ". &echo_oops(" OOPS ") ."  ". qq (Match with more than one option:\n\n);

                foreach $hit ( @hits )
                {
                    if ( $hit->[0] =~ /$name/ ) {
                        $text .= "    ". $PREMATCH . &echo_bold( $MATCH ) . $POSTMATCH ."\n";
                    } else {
                        &error("Programmer error: no match with $name" );
                    }
                }

                $text .= "\n  ". &echo_info_green(" HELP ") ."  ". qq (Please enter a string that gives one unique match.\n);
            }
            else 
            {
                $text .= "\n  ". &echo_oops(" OOPS ") ."  ". qq (Wrong looking dataset name -> "$name"\n\n);
                $text .= "  ". &echo_info_green(" HELP ") ."  ". qq (The --list option shows all uninstalled datasets\n);
                $text .= "  ". &echo_info_green(" HELP ") ."  ". qq (The --listall option shows all datasets\n);
            }
        }
    }

    if ( $text )
    {
        $text = "-" x $Linwid ."\n$text";
        $text .= "\n". "-" x $Linwid ."\n";

        print STDERR $text;
        exit;
    }

    return wantarray ? @dbs : \@dbs;
}

sub check_projects
{
    # Niels Larsen, June 2009.

    # Checks that a given list of project names are all found as configuration
    # files in the Config/Projects directory. If one is only found in the bundled
    # distribution directory, a link is made that points to the bundled file.
    # Errors are returned if a list is given, otherwise printed. Returns the 
    # names list unchanged.

    my ( $names,      # Project names list
         $msgs,       # Error list - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( %all, $proj_dir, $projd_dir, $field, $name, @msgs );

    %all = map { $_->name, 1 } Registry::Get->projects()->options;

    $proj_dir = $Common::Config::conf_proj_dir;
    $projd_dir = $Common::Config::conf_projd_dir;

    foreach $name ( @{ $names } )
    {
        if ( not exists $all{ $name } ) {
            push @msgs, ["ERROR", qq (Wrong looking project name -> "$name") ];
        }
    }
    
    if ( @msgs ) {
        push @msgs, [" Help", qq (The --list option shows available projects) ];
    }

    &Common::Messages::append_or_exit( \@msgs, $msgs );

    return wantarray ? @{ $names } : $names;
}

sub check_routines
{
    my ( $dbs,
         $args,
        ) = @_;

    my ( $db, $routine, @msgs );

    foreach $db ( @{ $dbs } )
    {
        if ( $args->download and $db->downloads and $db->downloads->baseurl ) 
        {
            $routine = &Install::Data::name_download_routine( $db, 0 );

            if ( not $routine ) {
                push @msgs, ["Error", qq (No download routine found for "). $db->name .qq (") ];
            }
        }

        if ( $args->install ) 
        {
            $routine = &Install::Data::name_import_routine( $db, 0 );

            if ( not $routine ) {
                push @msgs, ["Error", qq (No import routine found for "). $db->name .qq (") ];
            }
        }
    }

    if ( defined wantarray ) {
        return wantarray ? @msgs : \@msgs;
    } else {
        &echo_messages( \@msgs );
        exit;
    }
}

sub confirm_menu
{
    my ( $names,
         $type,
         $title,
        ) = @_;

    my ( $name, $text, $prompt, $str );

    if ( $type eq "install" )
    {
        $prompt = "WILL INSTALL";
        $str = "uninstalled";
    }
    elsif ( $type eq "uninstall" )
    {
        $prompt = "WILL UNINSTALL";
        $str = "uninstalled";
    }
    else {
        &error( qq (Wrong looking type -> "$type") );
    }

    if ( $title ) {
        &echo_bold( $title );
    } 

    foreach $name ( @{ $names } )
    {
        &echo( "   " );
        &echo_green( "$prompt" );
        &echo( "-> $name\n" );
    }
    
    $text = qq (
Are these the options to be $str? If not, please
press ctrl-C now. 

Otherwise the procedure will start in 10 seconds ... );

    &echo( $text );
    sleep 10;
    
    &echo_green( "gone\n" );

    return;
}

sub create_import_list
{
    # Niels Larsen, September 2008.

    # Creates a list of files to be installed, with explicit file paths for
    # install inputs and outputs, and name, title and label. A list of hashes
    # is returned, each hash with these keys: name, title, label, infile, 
    # outfile.

    my ( $db,           # Dataset object 
         $conf,         # Configuration object
        ) = @_;

    # Returns a list.

    my ( @opts, $opt, @io_list, $elem, @files, $file, $src_type, $label, $title,
         $name, $src_dir, $ins_dir, $src_format, $ins_format, $regex, @msgs,
         $prefix, $info, $imports, $db_fields, $db_regex, $fields, $tmp_dir,
         $src_files, $ifile,
        );
    
    require Data::Structure::Util;

    # Directories,

    $src_dir = $conf->src_dir;
    $ins_dir = $conf->ins_dir;
    $tmp_dir = $conf->tmp_dir;
         
    # Formats,

    $src_format = $db->format;
    $src_type = $db->datatype;
    $src_files = [ map { $_->{"name"} } &Common::File::list_files( $src_dir ) ];

    $ins_format = Registry::Get->type( $db->datatype )->formats->[0];

    $imports = $db->imports;

    if ( $imports and $imports->files and @files = @{ $imports->files->options } )
    {
        # Set info fields that apply to all files, unless overridden by fields in 
        # the specified fields,
        
        if ( $db_fields = $imports->hdr_fields )
        {
            $db_fields = &Storable::dclone( $db_fields );
            $db_fields->delete("id");
            $db_fields = &Data::Structure::Util::unbless( $db_fields );
        } 
        
        $db_regex = $imports->hdr_regexp;

        # >>>>>>>>>>>>>>>>>>>>>>> SET NAMES AND FIELDS <<<<<<<<<<<<<<<<<<<<<<<<
        
        # When names are given explicitly by the registry entry,

        foreach $file ( @files )
        {
            # If a name is given, use it. If not, take it from the output file
            # if given, otherwise use the prefix of the input file,

            if ( not $name = $file->name )
            {
                if ( $file->outfile ) {
                    $prefix = &Common::Names::get_prefix( $file->outfile );
                } elsif ( $file->infile ) {
                    $prefix = &Common::Names::get_prefix( $file->infile );
                } else {
                    $prefix = &Common::Util::match_list( [ $file->in_regexp ], $src_files )->[0];
                }

                $name = &File::Basename::basename( $prefix );
            }

            # If a label is given, use it. If not, use the name,

            if ( $file->label ) {
                $label = $file->label;
            } else {
                $label = ucfirst $name;
            }

            $label = " $label ";

            # If title is given, use it, otherwise use the name,

            if ( $file->title ) {
                $title = $file->title;
            } else {
                $title = ucfirst $name ." (". $db->label .")";
            }

            # If infile is given, use it, otherwise use the regexp to filter the 
            # source files with,
            
            if ( $file->infile ) {
                $ifile = "$src_dir/". $file->infile;
            } else {
                $ifile = "$src_dir/". &Common::Util::match_list( [ $file->in_regexp ], $src_files )->[0];
            }

            # Set element,

            $elem = {
                "name" => $name,
                "title" => $title,
                "label" => $label,
                "ifile" => $ifile,
                "ofile" => "$ins_dir/$name.$src_type.$src_format",
            };

            # Set info fields,

            if ( $file->hdr_fields )
            {
                $file->hdr_fields->delete("id");
                $fields = { %{ $db_fields // {} }, %{ $file->hdr_fields } };
            }
            elsif ( $db_fields ) {
                $fields = $db_fields;
            } else {
                $fields = undef;
            }

            if ( $file->hdr_regexp ) {
                $regex = $file->hdr_regexp;
            } elsif ( $db_regex ) {
                $regex = $db_regex;
            } else {
                $regex = undef;
            }
            
            if ( $regex and not $fields ) {
                &error( qq (Expression given, but no fields) );
            } 
            
            if ( ref $fields ) {
                $elem->{"hdr_fields"} = &Storable::dclone( $fields );
            } else {
                $elem->{"hdr_fields"} = $fields;
            }

            $elem->{"hdr_regexp"} = $regex;
            
            # Set split fields,

            if ( $elem->{"divide_files" } = $file->divide_files ) 
            {
                if ( not $elem->{"divide_regex"} = $file->divide_regex ) {
                    &error( qq (File name template given, but not expression) );
                }
            }

            # Add element to list,

            push @io_list, &Storable::dclone( $elem );
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>> SET HEADER REGEX AND FIELDS <<<<<<<<<<<<<<<<<<<<<
        
        if ( $imports ) 
        {
            $db_fields = $imports->hdr_fields;
            $db_regex = $imports->hdr_regexp;

            if ( $db_fields and not $db_regex ) {
                &error( qq (Missing regex in ). $db->name );
            }
        }

        # >>>>>>>>>>>>>>>>>>>>> IMPLICIT NAMES FROM FILES <<<<<<<<<<<<<<<<<<<<<<

        # List files, can be in both scratch and source directory, depends
        # if they were result of splitting,

        $regex = '\.'. $src_format . '(\.gz)?$';
        
        if ( -d $tmp_dir ) {
            @files = &Common::File::list_all( $tmp_dir, $regex );
        }

        if ( not @files ) {
            @files = &Common::File::list_all( $src_dir, $regex );
        }

        if ( not @files ) {
            &error( qq (No "$regex" files in $tmp_dir or $src_dir) );
        }

        # Create IO list,

        foreach $file ( @files )
        {
            $name = &Common::Names::get_prefix( $file->{"name"} );

            $elem = {
                "name" => $name,
                "title" => ucfirst $name,
                "label" => " ". ucfirst $name ." ",
                "ifile" => $file->{"path"},
                "ofile" => "$ins_dir/$name.$src_type.$ins_format",
            };

            if ( $db_fields ) {
                $elem->{"hdr_fields"} = &Storable::dclone( $db_fields );
            }

            if ( $db_regex ) {
                $elem->{"hdr_regexp"} = $db_regex;
            }
            
            push @io_list, &Storable::dclone( $elem );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check all files exist,

    foreach $elem ( @io_list )
    {
        $file = $elem->{"ifile"};

        if ( not -r $file and not -r $file ) {
            push @msgs, [ "Error", qq (File is not readable -> "$file") ];
        }
    }

    if ( @msgs ) {
        &echo_messages( \@msgs );
        exit;
    }

    @io_list = sort { $a->{"name"} cmp $b->{"name"} } @io_list;

    return wantarray ? @io_list : \@io_list;
}

sub create_missing_datadirs
{
    # Niels Larsen, May 2009.

    # Creates top-level installation directories.

    my ( $fatal,        # Error flag - OPTIONAL, default 0
         ) = @_;

    # Returns nothing.

    require Common::File;

    my ( $inst_dir, $dir, $i );

    $fatal = 0 if not defined $fatal;

    foreach $dir ( $Common::Config::dat_dir,
                   $Common::Config::dbs_dir )
    {
        if ( $fatal ) {
            &Common::File::create_dir( $dir );
        } else {
            &Common::File::create_dir_if_not_exists( $dir );
        }
    }

    return;
}

sub filter_file_lists
{
    # Niels Larsen, June 2009.

    # Creates a list of output files. 

    my ( $ifiles,
         $ofiles,
         $merge,
         ) = @_;

    my ( $iage, @oages, $oage, $i );

    # Get file hashes from paths in order to compare dates below,
    
    if ( $merge )
    {
        $iage = ( sort map { -M $_ } @{ $ifiles } )[0];

        @oages = grep { defined $_ } map { -M $_ } @{ $ofiles };

        if ( @oages ) {
            $oage = ( sort @oages )[0];
        } else {
            $oage = 99999;    # 300 years old
        }

        $ofiles = [] if $iage >= $oage;
    }
    elsif ( scalar @{ $ifiles } == scalar @{ $ofiles } )
    {
        for ( $i = 0; $i <= $#{ $ifiles }; $i++ )
        {
            if ( -e $ofiles->[$i] and -M $ifiles->[$i] >= -M $ofiles->[$i] )
            {
                $ifiles->[$i] = undef;
                $ofiles->[$i] = undef;
            }
        }
        
        @{ $ifiles } = grep { defined $_ } @{ $ifiles };
        @{ $ofiles } = grep { defined $_ } @{ $ofiles };
    }

    return ( $ifiles, $ofiles );
}
    
sub create_registry_entries
{
    # Niels Larsen, June 2009.

    # Creates entries that tell which name, title, label, datatype and format
    # each file has in the install directory of a given dataset. Returns a list
    # of hashes. 

    my ( $db,     # Dataset
         $conf,   # Configuration object 
        ) = @_;

    # Returns a list.
    
    my ( %imports, @ins_files, $file, $name, $type, $format, %seen, $title,
         $label, @entries, %skip, $merge_prefix );
    
    if ( not $conf->silent ) {
        &echo( "   Registering ". $db->title ." ... " );
    }

    $merge_prefix = $db->merge_prefix // "";

    if ( -d $conf->ins_dir and
         @ins_files = &Common::File::list_files( $conf->ins_dir ) and
         @ins_files = grep { $_->{"name"} ne "TIME_STAMP" } @ins_files )
    {
        @ins_files = sort { $a->{"name"} cmp $b->{"name"} } @ins_files;

        %skip = ( "info" => 1 );

        foreach $file ( @ins_files )
        {
            $name = $file->{"name"};

            next if $skip{ &Common::Names::get_suffix( $name ) };
            
            if ( $name =~ m|([^.]+)\.([^\.]+)\.([^\.]+)| )
            {
                $name = $1;
                $type = $2;
                $format = $3;

                if ( not $seen{ $name }{ $type }{ $format } )
                {
                    if ( $name eq $merge_prefix )
                    {
                        $title = $db->title;
                        $label = $db->label;
                    }
                    else
                    {
                        $title = ucfirst $name;
                        $label = " $title ";
                    }
                    
                    push @entries, Registry::Option->new(
                        "name" => $name,
                        "title" => $title,
                        "label" => $label,
                        "datatype" => $type,
                        "format" => $format,
                        );
                    
                    $seen{ $name }{ $type }{ $format } = 1;
                }
            }
            else {
                &error( qq (Wrong looking file path -> "$file->{'path'}") );
            }
        }
    }
    else
    {
        @entries = Registry::Option->new(
            "name" => $db->name,
            "title" => $db->title,
            "label" => $db->label,
            "datatype" => $db->datatype,
            "format" => $db->format,
            );
    }

    if ( not $conf->silent ) {
        &echo_green( "done\n" );
    }

    return wantarray ? @entries : \@entries;
}

sub divide_files
{
    # Niels Larsen, May 2010.

    my ( $ifile,         # Input file
         $regexp,        # ID filter
         $ofstr,         # Output file string template 
         $odir,          # Output directory - OPTIONAL
        ) = @_;

    my ( $ifh, %ofhs, $seq, $oname, @ofiles, $ofile );

    $odir //= &File::Basename::dirname( $ifile );

    $ifh = &Common::File::get_read_handle( $ifile );

    while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
    {
        $oname = &Common::Util::parse_string( $seq->id, $regexp, $ofstr );

        if ( not exists $ofhs{ $oname } )
        {
            $ofile = "$odir/$oname";
            $ofhs{ $oname } = &Common::File::get_write_handle( $ofile );

            push @ofiles, $ofile;
        }

        &Seq::IO::write_seq_fasta( $ofhs{ $oname }, $seq );
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handles( \%ofhs );

    return wantarray ? @ofiles : \@ofiles;
}
    
sub download_dataset
{
    # Niels Larsen, April 2008.

    # Downloads a single dataset. But the actual routine that does the work is 
    # not this generic one, because we download data that are posted in all kinds
    # of ways. This means there has to be a download routine for most datasets,
    # and they are located in Download.pm modules for the different datatypes. 
    # For an RNA dataset with the data directory SRPDB for example, the routine 
    # would be "RNAs::Download::download_srpdb". Returns a message string that
    # can be printed. 

    my ( $db,               # Package name
         $conf,             # Configuration hash
         ) = @_;

    # Returns a string.

    my ( $is_owner, $src_dir, $routine, $count, $msg, $cmds, $cmd, @files,
         $file, $stdout, $stderr, $suffix );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }

    $src_dir = $conf->src_dir;

    &echo( "   Downloading ". $db->title ." ... " ) unless $conf->silent;

    {
        # Control screen display settings, made local so they revert back,
        
        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;

        if ( $conf->silent or not $conf->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        if ( defined $conf->indent ) {
            $Common::Messages::indent_plain = $conf->indent;
        } else {
            $Common::Messages::indent_plain = 3;
        }

        &Common::File::create_dir_if_not_exists( $src_dir );

        $count = 0;
            
        # Delete directories if force,
        
        if ( $conf->force )
        {
            &echo( qq (\n   Deleting old source tree ... ) );
            
            $count = &Common::File::delete_dir_tree_if_exists( $src_dir );
            &Common::File::create_dir( $src_dir );
            
            &echo_green( $count > 0 ? "$count\n" : "none\n" );
        }
            
        if ( &Install::Data::updates_available( $db, $conf ) )
        {
            # Rename existing files by appending a date string,
            # TODO: make tolerance of bad network
            # TODO: only rename files to be downloaded, not all old files

            @files = &Common::File::list_files( $src_dir );
            @files = grep { $_->{"name"} !~ /\.BION\.old\./ } @files;

            foreach $file ( @files )
            {
                $suffix = ".BION.old.". &Common::Util::epoch_to_time_string();
                &Common::File::rename_file( $file->{"path"}, $file->{"path"} . $suffix );
            }

            # Set routine name,
            
            $routine = &Install::Data::name_download_routine( $db );

            # >>>>>>>>>>>>>>>>>>>>>>>>> RUN ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<

            &echo( "\n" ) if not $conf->force;
            
            {
                no strict "refs";
                eval { $count = $routine->( $db, $conf ) };
            }
            
            if ( $@ ) {
                &error( $@ );
            }
            
            # Post-commands,
            
            if ( $cmds = $db->downloads->post_commands )
            {
                &echo("   Running post-commands ... ");
                &Install::Data::run_commands( $cmds, $conf );
                &echo_done("done\n");
            }
            
            &echo("");
        }
    }
     
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( not defined $count ) 
    {
        &error( qq (Download routine must return a count.) );
    }
    elsif ( $count > -1 )
    {
        if ( $count >= 1 ) {
            $msg = ( $count > 1 ? &Common::Util::commify_number( $count ). " files" : "1 file" );
        } else {
            $msg = "up to date";
        }
    }
    else {
        $msg = "present";
    }

    &echo_green( "$msg\n" ) unless $conf->silent;

    return;
}

sub download_files
{
    # Niels Larsen, April 2010.

    # Routine that downloads the files associated with a dataset. If just a
    # base-url is given (no wildards allowed) then all files are downloaded 
    # recursively. If a list of file-filters is given, then only the matching
    # file names are downloaded. See the registry for rules and examples. 
    # Returns the number of files downloaded.

    my ( $db,            # Registry dataset object
         $args,          # Arguments hash
        ) = @_;

    # Returns integer.

    my ( $baseurl, $download, $r_folder, $r_filexp, $get_url, @copied, $count,
         $l_dir, $l_path, $depth, $show_url, @msgs );

    &Common::File::create_dir_if_not_exists( $args->{"src_dir"} );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }
    
    $count = 0;
    $baseurl = $db->downloads->baseurl;

    if ( defined $db->downloads->files )
    {
        # >>>>>>>>>>>>>>>>>>>>>>> SELECT FILES ONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # This is a non-recursive download that however uses curl-wildcards,
        # which resemble that of a shell,

        foreach $download ( @{ $db->downloads->files->options } )
        {
            # Source url from base url and filter path,
            
            $get_url = $baseurl;

            $r_folder = &File::Basename::dirname( $download->remote );
            $r_filexp = &File::Basename::basename( $download->remote );

            if ( defined $r_folder and $r_folder ne "." ) {
                $get_url .= "/$r_folder";
            }

            if ( $download->local ) {
                $show_url = $get_url ."/". $download->local;
            } else {
                $show_url = $get_url ."/$r_filexp";
            }

            $get_url .= "/$r_filexp";

            # Destination directory in CURL syntax,

            $l_path = $args->{"src_dir"};

            if ( $download->local ) {
                $l_path .= "/". $download->local;
            } else {
                $l_path .= "/$r_filexp";
            }

            &echo( "   Fetching $show_url ... " );

            @copied = &Common::Storage::fetch_files_curl( $get_url, $l_path, undef, \@msgs );
            
            if ( @msgs )
            {
                &echo("\n");
                $Common::Messages::indent_plain = 0;
                &append_or_exit( \@msgs );
            } else {
                &echo_done( ( scalar @copied ) ."\n" );
            }

            $count += scalar @copied;
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>> ENTIRE SITE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Recursive download with wget,

        if ( $depth = $db->downloads->depth ) {
            &echo( "   Copying (depth $depth) $baseurl ... " );
        } else {
            &echo( "   Copying all of $baseurl ... " );
        }

        @copied = &Common::Storage::fetch_files_wget(
            $db->downloads->baseurl ."/*",
            $args->{"src_dir"},
            {
                "recursive" => 1,
                "depth" => $depth,
            });

        @copied = grep { $_->[1] !~ m|/.listing| } @copied;

        $count = scalar @copied;

        &echo_done( "$count\n" );
    }

    # Set time stamp,

    if ( $count > 0 ) {
        Registry::Register->set_timestamp( $args->{"src_dir"} );
    }
    
    return $count;
}

sub expand_tokens
{
    # Niels Larsen, April 2010.

    # Expands strings like "__SRC_DIR__" to real paths. Returns an updated
    # string. 

    my ( $str,
         $conf,
        ) = @_;

    # Returns a string. 

    my ( $src_dir, $ins_dir, $src_name, $ins_name );

    $src_dir = $conf->src_dir;
    $ins_dir = $conf->ins_dir;

    $src_name = &File::Basename::basename( $src_dir );
    $ins_name = &File::Basename::basename( $ins_dir );

    $str =~ s/__SRC_DIR__/$src_dir/g;
    $str =~ s/__SRC_NAME__/$src_name/g;
    $str =~ s/__INST_DIR__/$ins_dir/g;
    $str =~ s/__INST_NAME__/$ins_name/g;

    return $str;
}

sub import_datasets
{
    my ( $args,
        ) = @_;

    my ( $defs, $db, @msgs, $conf );

    $db = $args->dataset;
    $args->delete_field("dataset");

    if ( not defined $db ) {
        &append_or_exit([["ERROR", qq (No dataset given) ]]);
    }

    require Install::Import;

    if ( $db eq "green" )
    {
        &Install::Import::create_green_seqs("rna_seq_green", $args, \@msgs );
    }
    elsif ( $db eq "rdp" )
    {
        &Install::Import::create_rdp_sub_seqs("rna_seq_rdp", $args, \@msgs );
    }
    elsif ( $db eq "silva" )
    {
        &Install::Import::create_silva_sub_seqs("rna_seq_silva", $args, \@msgs );
    }
    else {
        push @msgs, ["ERROR", qq (Unrecognized dataset name -> "$db") ];
        push @msgs, ["Info", qq (Recognized ones are "rdp", "silva".) ];
    }

    &append_or_exit( \@msgs );

    return;
}

sub export_derived_data
{
    # Niels Larsen, April 2008.

    # Creates derived datasets, such as sequences from an alignment. Returns
    # the number of files written. Returns a list of files written.

    my ( $db,            # Dataset to export from
         $conf,          # Configuration object
         $msgs,          # Outgoing messages
        ) = @_;

    # Returns a list.

    my ( $metlist, $itype, $iformat, $iname, @ifiles, $export, $otype, $clobber,
         $oformat, @paths, $path, @ofiles, @io_list, @entries, $fmtlist, $args,
	 $merge_prefix, $inst_dir, $routine, %written, %present, $count, $ofile,
	 $ifile, $oname, @olist, $oage, $msg, $ifiles, $ofiles, @written );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ADD FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # The formats to save in are those required by the methods that go with the
    # project that "owns" the dataset and that are compatible with the given 
    # dataset. 

    $metlist = Common::Menus->project_methods( $db->owner )->options_names;
    $metlist = Common::Menus->dataset_methods( $db, $metlist )->options_names;
   
    $itype = $db->datatype;
    $iformat = $db->format;
    $merge_prefix = $db->merge_prefix;

    $inst_dir = $conf->ins_dir;
    $clobber = $conf->force;

    %written = ();
    %present = ();

    $count = 0;

    if ( not $conf->silent ) {
        &echo( "   Exporting ". $db->title ." ... " );
    }

    {
        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;
        
        if ( $conf->silent or not $conf->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        $Common::Messages::indent_plain = 3;
        
        &echo( "\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> EXPORT FROM NATIVE <<<<<<<<<<<<<<<<<<<<<<<<<<<

        $fmtlist = Registry::Get->datatype_to_iformats( $metlist );

        foreach $export ( $db->exports->options )
        {
            $otype = $export->datatype;
            
            foreach $oformat ( @{ $fmtlist->{ $otype } } )
            {
                # List input files,
                
                if ( &Common::Types::is_alignment( $itype ) )
                {
                    @{ $ifiles } = map { $_->{"path"} } &Common::File::list_pdls( $inst_dir );
                }
                else {
                    &error( qq (Missing export routine for datatype "$itype") );
                }
                
                # Create output file list,
                
                if ( $export->merge ) {
                    $ofiles = [ $conf->ins_dir ."/$merge_prefix.$otype.$oformat" ];
                } 
                else {
                    @{ $ofiles } = map { &Common::Names::strip_suffix( $_ ) } @{ $ifiles };
                    @{ $ofiles } = map { &Common::Names::replace_suffix( $_, ".$otype.$oformat" ) } @{ $ofiles };
                }

                %present = ( %present, map { $_, 1 } @{ $ofiles } );

                if ( not $clobber ) {
                    ( $ifiles, $ofiles ) = &Install::Data::filter_file_lists( $ifiles, $ofiles, $export->merge );
                }

                @{ $ofiles } = grep { not exists $written{ $_ } } @{ $ofiles };

                if ( @{ $ofiles } )
                {
                    $count = scalar @{ $ofiles };

                    if ( $count > 1 ) {
                        &echo( qq (   Writing $count $otype.$oformat files ... ) );
                    } else {
                        &echo( qq (   Writing $otype.$oformat file ... ) );
                    }                        
                
                    # >>>>>>>>>>>>>>>>>>>>> SEQUENCE ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<

                    if ( &Common::Types::is_alignment( $itype ) )
                    {
                        $routine = "write_". $oformat ."_from_pdls";
                        require Ali::Export;

                        $args = &Storable::dclone(
                            {
                                "ifiles" => $ifiles,
                                "ofiles" => $ofiles,
                                "clobber" => 1,
                                "with_ali_ids" => 1,
                                "with_index_sids" => 1,
                                "with_gaps" => 0,
                                "with_masks" => 0,
                            });
                        
                        Ali::Export->$routine( $args, $msgs );
                    }

                    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OTHER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                    # >>>>>>>>>>>>>>>>>>>>>>>>> DATATYPES <<<<<<<<<<<<<<<<<<<<<<<<<<<
                    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HERE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                    
                    %written = ( %written, map { $_, 1 } @{ $ofiles } );

                    $count = scalar @{ $ofiles };
                    &echo_green( "$count\n", 0 ); 
                }
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>> INDEX THE EXPORTS <<<<<<<<<<<<<<<<<<<<<<<<<<

        # This makes index files. First get list of program-native formats,

        $fmtlist = Registry::Get->datatype_to_formats( $metlist );

        # Then list of input / output files,

        @ifiles = sort keys %present;
        @ofiles = ();

        foreach $ifile ( @ifiles )
        {
            if ( $ifile =~ m|/([^/]+)\.([^\.]+)\.([^\.]+)$| )
            {
                $iname = $1;
                $itype = $2;
                $iformat = $3;
                
                if ( $fmtlist->{ $itype } )
                {
                    foreach $oformat ( @{ $fmtlist->{ $itype } } )
                    {
                        $ofile = &Common::Names::replace_suffix( $ifile, ".$oformat" );
                        $oname = &File::Basename::basename( $ofile );

                        @olist = &Common::File::list_files( $conf->ins_dir, "$oname.*" );

                        if ( @olist )
                        {
                            $oage = ( sort map { -M $_->{"path"} } @olist )[0];
                            
                            if ( -M $ifile >= $oage ) {
                                $present{ $ofile } = 1;
                            }
                        }

                        if ( $clobber or not $present{ $ofile } )
                        {
                            &echo( qq (   Writing $itype.$oformat file ... ) );

                            {
                                local $Common::Messages::silent = 1;
                                
                                if ( &Common::Types::is_sequence( $itype ) )
                                {
                                    # >>>>>>>>>>>>>>>>>>>> SEQUENCE INDEXING <<<<<<<<<<<<<<<<<<<<
                                    
                                    &Seq::Storage::index_seq_file(
                                         {
                                             "ifile" => $ifile,
                                             "oprefix" => $ofile,
                                             "oformat" => $oformat,
                                             "datatype" => $itype,
                                             "silent" => 1,
                                         }, $msgs );
                                }
                                
                                $written{ $ofile } = 1;
                                $present{ $ofile } = 1;
                            }

                            &echo_green( "done\n", 0 ); 
                        }
                    }
                }
            }
        }

        &echo("");
    }

    @written = sort keys %written;

    if ( not $conf->silent )
    {
        $count = scalar @written;
        $msg = $count > 0 ? "$count files" : "up to date";

        &echo_green( "$msg\n" );
    }

    return wantarray ? @written : \@written;
}

sub filter_owned_datasets
{
    # Niels Larsen, September 2008.

    # Returs a list of datasets that are registered and owned by the 
    # given project.

    my ( $proj,        # Project object
         $dbs,         # Dataset list 
        ) = @_;

    # Returns a list. 

    my ( @dbs, $db, $title, $owner );

    foreach $db ( @{ $dbs } )
    {
        if ( $proj->name ne $db->owner and 
             Registry::Register->registered_datasets( $db->name ) )
        {
            $title = $db->title;
            $owner = $db->owner;

            &echo( "   $title $owner owned ... ");
            &echo_info( " skipped\n");
        }
        else {
            push @dbs, $db;
        }
    }

    return wantarray ? @dbs : \@dbs;
}

sub import_alignment
{
    # Niels Larsen, April 2008.

    # Imports/installs a single alignment that must exist. This is used during 
    # upload, system installation etc. 

    my ( $args,     # Arguments hash
         $msgs,     # Outgoing messages - OPTIONAL
        ) = @_;

    my ( %def_params, $params, $routine, $ft_count, $opath, @msgs, $count, 
         $itype );
    
    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( title label ifile iformat itype ofile tab_dir db_name source ) ], 
            "AR:1" => [ qw ( ft_names ) ],
            "AR:0" => [ qw ( ext_types methods ) ],
            "HR:0" => [ qw ( params ) ],
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    %def_params = (
        "colbeg" => undef,
        "colend" => undef,
        );

    $params = &Common::Util::merge_params( $args->params, \%def_params );
    
    $opath = &Common::Names::strip_suffix( $args->ofile );

    $itype = $args->itype;

    local $Common::Messages::silent = 1;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE NATIVE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Call Ali::Import::write_pdl_from_(iformat) routines to write native 
    # PDL files. It is up to them to use some or all of the arguments below,
    # but at least they must tolerate them all.

    $routine = "write_pdl_from_". $args->iformat;

    Ali::Import->$routine(
        {
            "title" => $args->title,
            "ifile" => $args->ifile,
            "opath" => $opath,
            "suffixes" => [ "pdl", "info" ],
            "sid" => &File::Basename::basename( &Common::Names::strip_suffix( $opath ) ),
            "datatype" => $itype,
            "source" => $args->source,
            "params" => $params,
        },
        $msgs );

    # Check that it was created and intact, or error,

    if ( not &Ali::IO::connect_pdl( $opath ) )
    {
        push @msgs, [ "Error", qq (Alignment not made -> "$opath" ("Ali::Import->$routine".) ) ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE FEATURES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This takes a list of features, writes feature tables, loads them
    # and then deletes them. If a dataset is given then the features 
    # are used that apply, otherwise the features are used that apply
    # to the given datatype. 

    if ( not @msgs )
    {
        $ft_count = &Ali::Import::import_features_alis(
            {
                "in_files" => [ $opath ],
                "ft_names" => $args->ft_names,
                "tab_dir" => $args->tab_dir,
                "db_name" => $args->db_name,
                "ft_source" => $args->source,
            }, \@msgs );
    }

    &Common::Messages::append_or_exit( \@msgs );

    return;
}

sub import_alignments
{
    # Niels Larsen, March 2007.
    
    # Installs alignment files and optionally features and sequence search 
    # files for a given dataset. It uses the descriptions in the 
    # Registry::Datasets file as guide. 
    
    my ( $db,            # Dataset object
         $conf,          # Arguments hash
         $msgs,          # Messages list
         ) = @_;

    # Returns an integer.

    my ( $proj, $dat_dir, $src_dir, $ins_dir, $source, @src_files,
         @io_list, $methods, $ft_names, $skip_ids, $format, $elem, 
         $params, $exts, @entries, @msgs, @metlist, $count, 
         $src_format, $tab_dir, $tmp_dir );

    require Data::Structure::Util;
    require Ali::Import;
    require Ali::Split;
    require Ali::IO;

    $msgs //= [];

    $source = $conf->source;
    $dat_dir = $conf->dat_dir;
    $src_dir = $conf->src_dir;
    $ins_dir = $conf->ins_dir;
    $tab_dir = $conf->tab_dir;
    $tmp_dir = $conf->tmp_dir;
    
    $src_format = $db->format;

    $proj = Registry::Get->project( $db->owner );

    # >>>>>>>>>>>>>>>>>>>>>>> OPTIONALLY SPLIT ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<

    # For example in stockholm formats there may be several alignments per file,
    
    if ( $db->imports and $db->imports->split_src ) 
    {
        &echo( qq (   Splitting source files ... ) );

        @src_files = &Common::File::list_all( $src_dir, "\.$src_format(.gz)?\$" );

        if ( not @src_files ) {
            &error( qq (No source files found in dir -> "$src_dir") );
        }
        
        &Ali::Split::split_alis(
            {
                "files" => [ map { $_->{"path"} } @src_files ],
                "format" => $src_format,
                "odir" => $tmp_dir,
                "osuffix" => $db->datatype .".$src_format",
                "skipids" => ( join ",", @{ $db->imports->params->skip_ids } ),
                "silent" => 1,
            }, $msgs );

        &echo_green( "done\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE IO-LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Creates a list of files to process,

    &echo( qq (   Getting names and files ... ) );

    @io_list = &Install::Data::create_import_list( $db, $conf );
#    @io_list = map { $_->{"title"} = $_->{"title"} ." alignment"; $_ } @io_list;
#    @io_list = grep { $_->{"name"} =~ /^mir/ } @io_list;

    &echo_done( ( scalar @io_list ) ."\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PREPROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Filter the IO-list in some specified way,

    if ( $db->imports and $params = $db->imports->params )
    {
        if ( $params->skip_ids )
        {
            &echo( qq (   Filtering ids ... ) );
            
            $skip_ids = { map { $_, 1 } @{ $params->skip_ids } };
            @io_list = grep { not exists $skip_ids->{ $_->{"name"} } } @io_list;

            &echo_green( "done\n" );
        }

        $params = &Data::Structure::Util::unbless( $params );
    }
    else {
        $params = {};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create simple list of default features - this tells which should be pre-
    # calculated and databased, which depends on datatype etc,

    &echo( qq (   Getting feature names ... ) );
    $ft_names = Common::Menus->dataset_features( $db )->options_names;
    &echo_done( ( scalar @{ $ft_names } ) ."\n" );

    # Process each alignment, 

    foreach $elem ( @io_list )
    {
        &echo( qq (   Importing $elem->{"name"} alignment ... ) );

        # Write native files and put features in database,

        &Install::Data::import_alignment(
            {
                "source" => $source,
                "title" => $elem->{"title"},
                "label" => $elem->{"label"},
                "ifile" => $elem->{"ifile"},
                "iformat" => $db->format,
                "itype" => $db->datatype,
                "ofile" => $elem->{"ofile"},
                "tab_dir" => $tab_dir,
                "ft_names" => $ft_names,
                "db_name" => $db->name,
                "params" => $params,
            },
            $msgs );

        if ( $elem->{"ifile"} =~ /^$tmp_dir/ ) {
            &Common::File::delete_file_if_exists( $elem->{"ifile"} );
        }

        &echo_green( "done\n" );
    }

    # Set time stamp,

    Registry::Register->set_timestamp( $ins_dir );

    # This return format is for "compatibility" with other routines called by 
    # import_dataset,

    return ( \@io_list, 0  );
}

sub import_expression
{
    # Niels Larsen, June 2009.

    # Imports and loads expression data, so far only those from MiRConnect.
    # UNFINISHED.

    my ( $db,
         $args,
         $msgs,
        ) = @_;

    my ( $dbh, $count, $prefix );

    $dbh = &Common::DB::connect( $args->database, 1 );

    if ( $args->datatype eq "expr_mirconnect" )
    {
        &Expr::Import::mc_write_tables( 
             {
                 "src_dir" => $args->src_dir,
                 "tab_dir" => $args->tab_dir,
                 "source" => $args->source,
                 "db_name" => $db->name,
             }, $msgs );

#        $prefix = $db->name ."_";
        $prefix = "";

        $count = &Common::Import::load_tabfiles(
            $dbh,
            {
                "tab_dir" => $args->tab_dir,
                "schema" => "expr_mirconnect",
#                "prefix" => $prefix,
                "replace" => 1,
            });

        &echo( qq (   Fulltext-indexing gene names ... ) );
        &Common::DB::request( $dbh, "create fulltext index gene_name_fndx on $prefix"."gene_names(gene_name,gene_id)" );
        &echo_green( "done\n" );
    }

    &Common::DB::disconnect( $dbh );

    # Set time stamp,
    
    Registry::Register->set_timestamp( $args->ins_dir );
    
    return ( undef, $count );
}

sub import_patterns
{
    # Niels Larsen, September 2008.
    
    # Installs a pattern dataset. Only links to the source directory
    # for the moment. 

    my ( $db,            # Dataset object
         $args,          # Arguments hash
         $msgs,          # Messages list
         ) = @_;

    # Returns an integer.

    my ( $count );

    $count = &Common::File::create_links_relative( $args->{"src_dir"},
                                                   $args->{"ins_dir"},
                                                   1 );

    # Set time stamp,
    
    Registry::Register->set_timestamp( $args->{"ins_dir"} );
    
    return ( $count, 0 );
}
    
sub import_sequences
{
    # Niels Larsen, June 2007.
    
    # Installs a sequence dataset. Returns a two-element list: ( \@io_list, 0 ).

    my ( $db,            # Dataset object
         $conf,          # Arguments hash
         $msgs,          # Messages list
         ) = @_;

    # Returns a two-element list.

    my ( $elem, $ifh, $ofh, @io_list, $format, $seq, $count_str, %info, @files,
         $fields, $regexp, $after, $silent, $clobber );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SET DEFAULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }

    if ( not defined $conf )
    {
        $conf = &Install::Profile::create_install_config( $db,
            { "silent" => 0, "verbose" => 1, "force" => 0, "update" => 0 } );
    }
    
    $silent = $conf->silent;
    $clobber = $conf->force || $conf->update;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE IO-LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Getting names and files ... ) ) unless $silent;
    
    @io_list = &Install::Data::create_import_list( $db, $conf );

    &echo_done( ( scalar @io_list ) ."\n" ) unless $silent;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE FASTA OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    foreach $elem ( @io_list )
    {
        &echo( qq (   Importing $elem->{"name"} sequences ... ) ) unless $silent;

        # I/O handles, 

        $ifh = &Common::File::get_read_handle( $elem->{"ifile"} );
        $ofh = &Common::File::get_write_handle( $elem->{"ofile"}, "clobber" => 1 );
#        $ofh = &Common::File::get_write_handle( $elem->{"ofile"}, "clobber" => $clobber );

        # Convenience variables for annotation fields, if the registry wants,

        $fields = $elem->{"hdr_fields"};
        $regexp = $elem->{"hdr_regexp"};

        if ( $db->format eq "fasta" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>> FASTA INPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<

            &Seq::IO::spool_seqs_fasta( $ifh, $ofh, $regexp, $fields );
        }
        else {
            $format = $db->format;
            &error( qq (Un-supported sequence source format (should be fasta) -> "$format") );
        }
        
        &Common::File::close_handle( $ofh );
        &Common::File::close_handle( $ifh );

        &echo_green( "done\n" ) unless $silent;

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( qq (   Indexing $elem->{"name"} sequences ... ) ) unless $silent;

        &Seq::Storage::index_seq_file( { "ifile" => $elem->{"ofile"} } );

        &echo_green( "done\n" ) unless $silent;

        # >>>>>>>>>>>>>>>>>>>>>>>>>> DIVIDE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # THERE SHOULD BE A BETTER WAY

#         if ( $elem->{"divide_files"} )
#         {
#             &echo( qq (   Dividing $elem->{"name"} sequences ... ) ) unless $silent;
#             @files = &Install::Data::divide_files( $elem->{"ofile"}, $elem->{"divide_regex"}, $elem->{"divide_files"} );
#             &echo_green( "done\n" ) unless $silent;

#             &echo( qq (   Indexing divided sequences ... ) ) unless $silent;
#             map { &Seq::Storage::create_index( $_ ) } @files;
#             &echo_green( "done\n" ) unless $silent;
#         }
    }

    # Set time stamp,
    
    Registry::Register->set_timestamp( $conf->ins_dir );

    return ( \@io_list, 0 );
}

sub import_dataset
{
    # Niels Larsen, April 2008.

    # Installs a single dataset, but does not download. This is the routine
    # to use from elsewhere. Missing directories will be created and needed 
    # databases initiated. The dataset can be of any of the supported types,
    # the right modules and routines will be loaded and called (each datatype
    # is processes very differently due to their nature). These arguments
    # are accepted as keys to the $args hash,
    # 
    #    force    Overwrites current install if any
    #   update    Installs the pieces that are missing or outdated
    #   silent    Prints no log messages
    #  verbose    Prints many log messages

    my ( $db,                # Dataset object or name
         $conf,              # Configuration object 
        ) = @_;

    # Returns nothing.

    my ( $src_dir, $routine, $count, $dir, $bool, $msgs, $msg, $module, 
         $sub_name, $proj, $ft_count, @msgs, $database, $io_list, @files,
         $file, $stdout, $stderr, $i, $cmds );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $msgs = [];
    
    if ( not $conf->silent ) {
        &echo( "   Importing ". $db->title ." ... " );
    }

    {
        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;

        if ( $conf->silent or not $conf->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        $Common::Messages::indent_plain = 3;
        
        if ( not -e ( $dir = $conf->src_dir ) ) {
            &error( qq (Sources directory not found -> "$dir") );
        }

        # Check timestamps between main source and install directories. There may 
        # also be timestamps at sub-directories, but those are then managed by 
        # each install routine. 

        if ( &Install::Data::needs_import( $conf->src_dir, $conf->ins_dir ) or $conf->force )
        {
            &echo("\n");

            # >>>>>>>>>>>>>>>>>>>>> NAME IMPORT ROUTINE <<<<<<<<<<<<<<<<<<<<<<<

            # Some data import routines live in their own modules, this defines their
            # names,

            $routine = &Install::Data::name_import_routine( $db );

            # >>>>>>>>>>>>>>>>>>>>> REMOVE IF REQUESTED <<<<<<<<<<<<<<<<<<<<<<<

            if ( $conf->force )
            {
                &echo( qq (   Deleting old install tree ... ) );
                
                $i = &Common::File::delete_dir_tree_if_exists( $conf->tab_dir );
                $i += &Common::File::delete_dir_tree_if_exists( $conf->tmp_dir );
                $i += &Common::File::delete_dir_tree_if_exists( $conf->ins_dir );
                
                Registry::Register->unregister_datasets( $db->name );
 
                &echo_green( $i > 0 ? "$i\n" : "none\n" );
            }
            
            # >>>>>>>>>>>>>>>>>>>> INITIALIZE IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<

            # Create directories if needed, 

            &Common::File::create_dir_if_not_exists( $conf->tab_dir );
            &Common::File::create_dir_if_not_exists( $conf->tmp_dir );
            &Common::File::create_dir_if_not_exists( $conf->ins_dir );
            
            &Common::File::create_dir_if_not_exists( qq ($Common::Config::dbs_dir/). $conf->database );

            # >>>>>>>>>>>>>>>>>>>> UNPACK ARCHIVES IF ANY <<<<<<<<<<<<<<<<<<<<<

            $stdout = "";
            $stderr = "";

            foreach $file ( @files = &Common::File::list_files( $conf->src_dir, '.zip$' ) )
            {
                &echo( "Un-zipping $file->{'name'} ... " );
                &Common::OS::run3_command( "unzip -o $file->{'path'} -d $file->{'dir'}", undef, \$stdout, \$stderr );
                &echo_green( "done\n" );
            }

            # >>>>>>>>>>>>>>>>>>>>>>>>> RUN ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<

            # Run the import routine,

            if ( $db->imports and ( $db->imports->files or $db->imports->routine ) )
            {
                no strict "refs";

                eval { ( $io_list, $ft_count ) = $routine->( $db, $conf, $msgs ) };

                if ( ref $io_list ) {
                    $count = scalar @{ $io_list };
                } else {
                    $count = $io_list;
                }
            }
            
            if ( $@ ) {
                &error( $@ );
            }
            
            # >>>>>>>>>>>>>>>>>>>>>>>> POST COMMANDS <<<<<<<<<<<<<<<<<<<<<<<<<<
            
            if ( $db->imports and $cmds = $db->imports->post_commands )
            {
                &echo("   Running post-commands ... ");
                &Install::Data::run_commands( $cmds, $conf );
                &echo_done("done\n");
            }
            
            # Delete empty directories, a cleanup step,

            &Common::File::delete_dir_if_empty( $conf->tab_dir );
            &Common::File::delete_dir_if_empty( $conf->tmp_dir );
            &Common::File::delete_dir_if_empty( $conf->ins_dir );
            
            $count //= 0;
            $ft_count //= 0;
            
            &echo("");
        }
        else
        {
            $count = 0;
            $ft_count = 0;
        }
        
        if ( @{ $msgs } ) {
            &echo_messages( $msgs );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $conf->silent )
    {
        if ( $count > -1 )
        {
            if ( $count > 0 or $ft_count > 0 )
            {
                @msgs = ();
                
                if ( $count >= 1 ) {
                    push @msgs, ( $count > 1 ? &Common::Util::commify_number( $count ). " entries" : "1 entry" );
                }
                
                if ( $ft_count >= 1 ) {
                    push @msgs, ( $ft_count > 1 ? &Common::Util::commify_number( $ft_count ). " rows" : "1 row" );
                }
                
                $msg = join ", ", @msgs;
            }
            else {
                $msg = "up to date";
            }
        }
        else { 
            $msg = "is ready";
        }
    
        &echo_green( "$msg\n" );
    }
    
    if ( $msgs ) {
        return wantarray ? @{ $msgs } : $msgs;
    } else {
        return;
    }
}

sub install_data
{
    # Niels Larsen, September 2008.

    # Downloads and/or installs a list of datasets given by their names. This 
    # is the highest-level routine routine that should be called from scripts
    # wrappers. If given a "list" argument it makes a table of uninstalled
    # datasets (or all if "all" is given. If not, it does a number of steps: 
    # validates dataset names; remove installed datasets (unless "force" is 
    # given); creates main install directories if needed; check that install 
    # routines exist before starting; downloads data (optional); installs data
    # into database etc (optional). The total number of downloads and installs
    # is returned. 

    my ( $dbs,          # List of dataset names or objects
         $args,         # Arguments hash
        ) = @_;

    # Returns integer.

    my ( $def_args, @dbs, $db, $str, @names, %filter, $count, $conf,
         @entries, @msgs, $silent );
    
    $def_args = {
        "all" => 0,
        "download" => 1,
        "install" => 1,
        "export" => 1,
        "verbose" => 0,
        "silent" => 0,
        "force" => 0,
        "update" => 0,
        "list" => 0,
        "listall" => 0,
        "confirm" => 0,
        "print_header" => 1,
    };

    $args = &Common::Util::merge_params( $args, $def_args );

    $args = &Registry::Args::check(
        $args || {},
        { 
            "S:0" => [ keys %{ $def_args } ],
        });

    $silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND SKIP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of datasets and exit,

    if ( $args->list )
    {
        &Install::Data::list_datasets( "uninstalled", 0 );
        exit;
    }
    elsif ( $args->listall )
    {
        &Install::Data::list_datasets( "uninstalled", 1 );
        exit;
    }    

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET DATASET LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all package names,

    if ( $args->all )
    {
        @names = Registry::Get->datasets()->options_names;
    }
    elsif ( $dbs and @{ $dbs } )
    {
        @names = &Install::Data::check_datasets( $dbs );
    }
    else {
        &error( qq (No datasets given) );
    }

    # Filter if not update/force,

    if ( not $args->update and not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->unregistered_datasets();
        @names = grep { $filter{ $_ } } @names;
    }
    
    # Return if nothing to install,

    return if not @names;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRINT MAIN MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $args->silent and $args->print_header )
    {
        $str = "Installing datasets";

        if ( $args->print_header ) {
            &echo_bold( "\n$str:\n" ) unless $silent;
        } else {
            &echo( "   $str ... " ) unless $silent;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK DATABASE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # if ( not &Common::Admin::mysql_is_running() )
    # {
    #     &echo( qq (   Starting MySQL database ... ) ) unless $silent;
    #     &Common::Admin::start_mysql({ "headers" => 0, "silent" => 1 });
    #     &echo_green( "done\n" ) unless $silent;
    # }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get the registry content that correspond to the names,

    @dbs = Registry::Get->datasets( \@names )->options;

    # Since downloads can be lengthy, check that all routines exist, 

    @msgs = &Install::Data::check_routines( \@dbs, $args );

    if ( @msgs ) {
        &echo_messages( \@msgs );
        exit;
    }

    $count = 0;

    foreach $db ( @dbs )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIGURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Sets names, types and directory paths needed by install routines,

        $conf = &Install::Profile::create_install_config(
            $db,
            { 
                "silent" => $args->silent,
                "verbose" => $args->verbose,
                "force" => $args->force,
                "update" => $args->update,
                "clobber" => undef,
                "indent" => undef,
            });

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DOWNLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Downloads data if they are out of date,
        # If the datadir field of a DNA dataset is for example "GenBank",
        # then there must be a DNA::Download::download_genbank routine.

        if ( $args->download and $db->downloads )
        {
            &Install::Data::download_dataset( $db, $conf );
            $count += 1;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> IMPORTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Imports datasets to this system's native formats,
        
        if ( $args->install )
        {
            &Install::Data::import_dataset( $db, $conf );
            
            $count += 1;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> EXPORTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Write extra formats that the methods in the project definition 
        # want, and that exist for the datatypes defined in the dataset 
        # registry entry.
        
        if ( $args->export and $db->exports and 
             defined $conf and -r $conf->ins_dir )
        {
            $count += &Install::Data::export_derived_data( $db, $conf );
        }

        # >>>>>>>>>>>>>>>>>>>> MAKE REGISTRY ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<
        
        # Write .yaml files that list installed entries; this is a help for 
        # the routines that build menu content etc,

        if ( defined $conf and -r $conf->ins_dir )
        {
            @entries = &Install::Data::create_registry_entries( $db, $conf );
            Registry::Register->write_entries_list( \@entries,  $conf->dat_dir );
        }

        # >>>>>>>>>>>>>>>>>>>>>>> REGISTER DATASET <<<<<<<<<<<<<<<<<<<<<<<<<<<

        Registry::Register->register_datasets( $db->name );

        $count += 1;
    }
    
    if ( not $args->silent and $args->print_header )
    {
        if ( $args->print_header ) {
            &echo_bold( "Finished\n" ) unless $silent;
        } else {
            &echo_green( "done\n" ) unless $silent;
        }
    }

    return $count;
}

sub install_projects
{
    # Niels Larsen, June 2009.

    # Install a given list of project names, and all their associated data
    # if specified in the project file. 

    my ( $projs,        # List of project names
         $args,         # Arguments hash
        ) = @_;

    # Returns nothing.

    my ( $def_args, @dbs, $db, @names, $name, $proj, %filter, $count, 
         $db_count, $db_name, $title, $proj_dir, $projd_dir, @msgs );
    
    $def_args = {
        "download" => 1,
        "install" => 1,
        "export" => 1,
        "all" => 0,
        "update" => 0,
        "verbose" => 0,
        "silent" => 0,
        "force" => 0,
        "list" => 0,
        "confirm" => 0,
        "print_header" => 0,
    };

    $args = &Common::Util::merge_params( $args, $def_args );
    
    $args = &Registry::Args::check(
        $args || {},
        { 
            "S:0" => [ keys %{ $def_args } ],
        });
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND SKIP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of projects and exit,

    if ( $args->list )
    {
        &Install::Data::list_projects( "installed", $args->all );
        exit 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GET PROJECT LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check if the given project names match those in the registry. If --all or
    # no installs, get all package names,

    if ( $args->all )
    {
        @names = Registry::Get->projects()->options_names;
    }
    elsif ( $projs and @{ $projs } )
    {
        @names = &Install::Data::check_projects( $projs );
    }
    else {
        &error( qq (No projects given) );
    }
    
    # Filter if not force,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->unregistered_projects();
        @names = grep { $filter{ $_ } } @names;
    }

    # Return if nothing to install,

    return if not @names;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIRM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->confirm )
    {
        $title = "\n$Common::Config::sys_name Project Installation\n\n";
        &Install::Data::confirm_menu( \@names, "install", $title );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args->print_header( 0 );
    $count = 0;
    
    foreach $name ( @names )
    {
        $proj = Registry::Get->project( $name );
        
        if ( not $args->silent ) {
            &echo_bold( "\nInstalling $name:\n" );
        }
        
        if ( $proj->{"datasets"} )
        {
            @dbs = Registry::Get->project_dbs_local( $proj->name )->options;

            # Skip datasets not owned by this project,

            @dbs = &Install::Data::filter_owned_datasets( $proj, \@dbs );
        
            # The --confirm command line argument triggers asking which datasets 
            # should be installed,
            
#        if ( $args->confirm ) {
#            @dbs = &Install::Data::ask_confirmation( \@dbs, "install" );
#        }
            
            # Install datasets,
            
            foreach $db ( @dbs )
            {
                $db_count = &Install::Data::install_data( [ $db->name ], $args );
                
                if ( $db_count )
                {
                    $count += 1;
                }
                else
                {
                    $title = $db->title;
                    &echo( qq (   Installing $title ... ) );
                    &echo_green( "installed\n" );
                }
            }
        }

        # Write profile,
        
        &echo( "   Creating site profile ... " );
        Install::Profile->create_profile( $proj );
        &echo_green( "done\n" );

        # Register project,

        &echo( "   Registering project ... " );
        Registry::Register->register_projects( $name );
        &echo_green( "done\n" );

        if ( not $args->silent ) {
            &echo_bold( "Finished\n" );
        }
    }

    return $count;
}

sub list_datasets
{
    # Niels Larsen, May 2009.

    # Lists datasets of a given type, installed or uninstalled. 

    my ( $filter,      # Filter name, e.g. "uninstalled"
         $force,       # List all, OPTIONAL - default off
        ) = @_;

    # Returns nothing.

    my ( @table, $args, $status, $msgs );

    if ( $force ) {
        $filter = "";
    } elsif ( $filter !~ /^installed|uninstalled$/ ) {
        &error( qq (Wrong looking filter -> "$filter" ) );
    }
    
    $args = &Registry::Args::check(
        {
            "fields" => "name,datatype,tiptext",
            "filter" => $filter,
        },{
            "S:1" => [ "fields", "filter" ],
            "S:0" => [ "sort" ],
        });

    @table = Registry::List->list_datasets( $args, $msgs );

    if ( @table )
    {
        print "\n";
        
        Common::Tables->render_list(
            \@table,
            {
                "fields" => $args->fields,
                "header" => 1, 
                "colsep" => "  ",
                "indent" => 3,
            });
        
        print "\n\n";
    }
    elsif ( $filter )
    {
        if ( $filter eq "installed" ) {
            $status = "uninstalled";
        } elsif ( $filter eq "uninstalled" ) {
            $status = "installed";
        } 

        &echo_messages(
             [["OK", qq (All packages are $status) ]],
             { "linewid" => 60, "linech" => "-" } );
    }

    return;
}

sub list_projects
{
    # Niels Larsen, May 2009.

    # Lists projects, installed or uninstalled. 

    my ( $filter,      # Filter name, e.g. "uninstalled"
         $force,       # List all, OPTIONAL - default off
        ) = @_;

    # Returns nothing.

    my ( @table, $args, $status, $msgs );

    if ( $force ) {
        $filter = "";
    } elsif ( $filter !~ /^installed|uninstalled$/ ) {
        &error( qq (Wrong looking filter -> "$filter" ) );
    }
    
    $args = &Registry::Args::check(
        {
            "fields" => "name,datadir,title",
            "filter" => $filter,
        },{
            "S:1" => [ "fields", "filter" ],
            "S:0" => [ "sort" ],
        });

    @table = Registry::List->list_projects( $args, $msgs );

    if ( @table )
    {
        print "\n";
        
        Common::Tables->render_list(
            \@table,
            {
                "fields" => $args->fields,
                "header" => 1, 
                "colsep" => "  ",
                "indent" => 3,
            });
        
        print "\n\n";
    }
    elsif ( $filter )
    {
        if ( $filter eq "installed" ) {
            $status = "uninstalled";
        } elsif ( $filter eq "uninstalled" ) {
            $status = "installed";
        } 

        &echo_messages(
            [["OK", qq (All projects are $status) ]],
            { "linewid" => 60, "linech" => "-" } );
    }

    return;
}

sub name_download_routine
{
    # Niels Larsen, April 2008.

    # Sets a routine name for a download. Names can be given in the dataset
    # description, be "Install::Download::" + datset name, and the fallback 
    # default is "Install::Data::download_files.

    my ( $db,            # Dataset object or name
        ) = @_;

    # Returns a string.

    my ( $module, $routine );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }
    
    if ( not ( $routine = $db->downloads->routine ) )
    {
        # $routine = "Install::Download::". lc $db->name;
        
        # if ( not Registry::Check->routine_exists({ "routine" => $routine, "fatal" => 0 }) )
        # {
        $routine = "Install::Data::download_files";
        # }
    }

    Registry::Check->routine_exists({ "routine" => $routine, "fatal" => 1 });

    return $routine;
}

sub name_export_routine
{
    my ( $db,
         $type,           # Export type
        ) = @_;

    return;
}

sub name_import_routine
{
    # Niels Larsen, April 2008.

    # Returns an import routine name for a given dataset, in full module path
    # like this Install::Data::import_alignments. Explicit routines can be given
    # in the registry, otherwise one is inferred from the datatype. Explicit ones
    # are used for dataset-specific imports and the defaults for generic imports.
    # All routines must take a dataset object or string as first argument and a
    # file path configuration object as second argument. 

    my ( $db,             # Dataset object or name
        ) = @_;

    # Returns a string. 

    my ( $module, $subname, $datatype, $dbname, $routine );

    # Convert string to object if needed, 

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> EXPLICIT ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $routine = $db->imports->routine )
    {
        if ( not Registry::Check->routine_exists( 
                 {
                     "routine" => $routine,
                     "fatal" => 0,
                 }) )
        {
            $dbname = $db->name;
            &error( qq (Routine does not exist -> "$routine ($dbname)") );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> ROUTINE BY DATATYPE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    else
    {
        $module = Registry::Get->type( $db->datatype )->module ."::Import";
        $subname = "import_". lc $db->datadir;
            
        $routine = $module ."::". $subname;
        
        if ( not Registry::Check->routine_exists( 
                 {
                     "routine" => $routine,
                     "fatal" => 0,
                 }) )
        {        
            $datatype = $db->datatype;
            $dbname = $db->name;
        
            # >>>>>>>>>>>>>>>>>>>>>>> DEFAULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            if ( &Common::Types::is_alignment( $datatype ) )
            {
                $module = "Install::Data";
                $subname = "import_alignments";
            }
            elsif ( &Common::Types::is_sequence( $datatype ) )
            {
                $module = "Install::Data";
                $subname = "import_sequences";
            }
            elsif ( &Common::Types::is_genome( $datatype ) )
            {
                $module = "Install::Import";
                $subname = "import_genomes_ebi";
            }
            elsif ( &Common::Types::is_pattern( $datatype ) )
            {
                $module = "Install::Data";
                $subname = "import_patterns";
            }
            elsif ( &Common::Types::is_functions( $datatype ) )
            {
                $module = "GO::Import";
                $subname = "import_go";
            }
            elsif ( &Common::Types::is_expression( $datatype ) )
            {
                # $module = "Expr::Import";
                # $subname = "import_mirconnect";
                $module = "Install::Data";
                $subname = "import_expression";
            }
            elsif ( &Common::Types::is_organisms( $datatype ) )
            {
                $module = "Taxonomy::Import";
                $subname = "import_ncbi";
            }
            elsif ( &Common::Types::is_word_list( $datatype ) )
            {
                $module = "Words::Import";
                $subname = "import_word_lists";
            }
            elsif ( &Common::Types::is_word_text( $datatype ) )
            {
                $module = "Words::Import";
                $subname = "import_word_texts";
            }
            else {
                &error( qq (Could not locate routine for -> "$dbname (type $datatype)") );
            }
            
            $routine = $module ."::". $subname;
            
            if ( not Registry::Check->routine_exists( 
                     {
                         "routine" => $routine,
                         "fatal" => 0,
                     }) )
            {
                &error( qq (Could not locate routine for -> "$dbname (type $datatype)") );
            }
        }
    }

    return $routine;
}    

sub name_uninstall_routine
{
    # Niels Larsen, August 2010.

    # Returns uninstall routine that is right for the given dataset. The 
    # routine is returned in the form Module::function.

    my ( $db,             # Dataset object or name
        ) = @_;

    # Returns a string. 

    my ( $module, $subname, $datatype, $dbname, $routine );

    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }

    $datatype = $db->datatype;
    $dbname = $db->name;
    
    if ( &Common::Types::is_genome( $datatype ) )
    {
        $module = "Install::Import";
        $subname = "uninstall_genomes_ebi";
    }
    else
    {
        $module = "Install::Data";
        $subname = "uninstall_dataset";
    }
    
    $routine = $module ."::". $subname;

    if ( not Registry::Check->routine_exists( 
             {
                 "routine" => $routine,
                 "fatal" => 0,
             }) )
    {
        &error( qq (Could not locate routine for -> "$dbname (type $datatype)") );
    }

    return $routine;
}    

sub needs_import
{
    # Niels Larsen, October 2006.
    
    # Compares the time stamp in the given source directory with that in the given
    # destination subdirectory: if the first is more recent then this routine returns 1.
    # The routine returns 1 if either source or destination directory does not exist.

    my ( $src_dir,   # Source directory full path
         $dst_dir,   # Destination directory full path
         ) = @_;

    # Returns 1 or nothing.

    my ( $src_time, $dst_time );

    if ( -e "$src_dir/TIME_STAMP" ) {
        $src_time = Registry::Register->get_timestamp( $src_dir );
    } else {
        return 1;
    }

    if ( -e "$dst_dir/TIME_STAMP" ) {
        $dst_time = Registry::Register->get_timestamp( $dst_dir );
    } else {
        $dst_time = 0;    # The beginning of all computer time
    }

    return 1 if $dst_time < $src_time;

    return;
}

sub run_commands
{
    # Niels Larsen, June 2012. 

    # Runs a list of commands, with expansion of file path tokens
    # like __SRC_DIR__ and others. 

    my ( $cmds,
         $conf,
        ) = @_;
 
    my ( $stdout, $stderr, $cmd );

    $stdout = "";
    $stderr = "";
    
    foreach $cmd ( @{ $cmds } )
    {
        $cmd = &Install::Data::expand_tokens( $cmd, $conf );

        if ( not &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr ) )
        {
            if ( $stderr ) {
                &error( $stderr );
            }
        }
    }

    return;
}
    
sub uninstall_dataset_db
{
    # Niels Larsen, May 2009.

    # Removes all database records that belongs to a given dataset.
    # Returns the number of rows deleted.

    my ( $db,     # Dataset name or object
         $dbh,
        ) = @_;

    # Returns integer.

    my ( $schema, $database, $tables, $table, $count, $must_close, 
         $sum, $type );
    
    if ( not ref $db ) {
        $db = Registry::Get->dataset( $db );
    }
    
    $schema = Registry::Get->type( $db->datatype )->schema;

    if ( not $schema ) {
        return 0;
    }

    $tables = Registry::Schema->get( $schema )->table_names;

    $database = $db->name;

    if ( not $dbh )
    {
        if ( not &Common::Admin::mysql_is_running() ) {
            &Common::Admin::start_mysql({ "headers" => 0 });
        }

        if ( &Common::DB::database_exists( $database ) ) 
        {
            $dbh = &Common::DB::connect( $database );
            $must_close = 1;
        } 
        else {
            return 0;
        }
    }

    $sum = 0;

    $type = Registry::Get->type( $db->datatype );
    
    if ( $type->schema )
    {
        foreach $table ( @{ $tables } )
        {
            if ( &Common::DB::table_exists( $dbh, $table ) )
            {
                if ( grep { $_ =~ /source/i } &Common::DB::list_column_names( $dbh, $table ) )
                {
                    &echo( qq (   Deleting rows in "$database:$table" ... ) );

                    $count = &Common::DB::delete_rows( $dbh, $table, "source", $db->name );
                    &echo_done( "$count row[s]\n" );

                    if ( &Common::DB::count_rows( $dbh, $table ) == 0 ) {
                        &Common::DB::delete_table( $dbh, $table );
                    }
                }
                else
                {
                    &echo( qq (   Deleting "$database:$table" ... ) );

                    $count = &Common::DB::count_rows( $dbh, $table );
                    &Common::DB::delete_table( $dbh, $table );

                    &echo_green( "done\n" );
                }

                $sum += $count;
            }
            else
            {
                &echo( qq (   Deleting from "$database:$table" ... ) );
                &echo_yellow( "missing\n" );
            }                
        }
    }

    if ( not @{ &Common::DB::list_tables( $dbh ) } ) {
        &Common::DB::delete_database( $dbh, $database );
    }

    if ( $must_close ) {
        &Common::DB::disconnect( $dbh );
    }

    return $sum;
}

sub uninstall_data
{
    # Niels Larsen, May 2009.

    # Uninstalls the list of given utility packages. Returns the number of 
    # packages uninstalled.

    my ( $dbs,      # List of packages - OPTIONAL
         $args,     # Install options hash - OPTIONAL
         $msgs,     # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns integer.

    my ( @dbs, @names, %filter, $count, $name, $conf, $str, $db, $silent, 
         $routine );

    if ( defined $dbs and not ref $dbs ) {
        $dbs = [ $dbs ];
    }

    $args = &Registry::Args::check(
        $args || {},
        {
            "S:0" => [ qw ( all force download install verbose silent list print_header ) ],
        } );

    $silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND SKIP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of installed datasets and 
    # exit,

    if ( $args->list )
    {
        &Install::Data::list_datasets( "installed", $args->all );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET DATASET LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If installs are given and no --all option (which should override), then
    # check the install names match those in the registry. If --all or no 
    # installs, get all dataset names,

    if ( not $args->all and $dbs and @{ $dbs } ) {
        @names = &Install::Data::check_datasets( $dbs );
    } else {
        @names = Registry::Get->datasets()->options_names;
    }

    # Unless --force, show only installed packages,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->registered_datasets();
        @names = grep { $filter{ $_ } } @names;
    }

    return if not @names;

    # With these names, get corresponding registry objects,
    
    @dbs = Registry::Get->datasets( \@names )->options;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRINT MAIN MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->print_header ) {
        &echo_bold( "\nUninstalling datasets\n" ) unless $silent;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNINSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $count = 0;

    foreach $db ( @dbs )
    {
        $routine = &Install::Data::name_uninstall_routine( $db );

        $conf = Registry::Args->new(
            {
                "clean" => 1,
                "download" => $args->download,
                "install" => $args->install,
                "force" => $args->force,
                "verbose" => $args->verbose,
                "silent" => $args->silent,
                "print_header" => 0,
                "indent" => undef,
            });

        # Run routine,

        {
            no strict "refs";
            eval { $count = $routine->( $db, $conf, $msgs ) };
        }

        if ( $@ ) {
            &error( $@ );
        }

        $count += 1;
    }

    if ( $args->print_header ) {
        &echo_bold( "Finished\n" ) unless $silent;
    }

    return $count;
}

sub uninstall_dataset
{
    # Niels Larsen, May 2009.

    # Deletes data files for the given registry dataset entry. Returns the 
    # number of files deleted.

    my ( $db,       # Registry dataset entry
         $args,     # Command line data arguments
         ) = @_;

    # Returns an integer. 

    my ( $conf, $fcount, $rcount, $dir, $dat_dir, @dirs, $file, $count, 
         $count_str, $name );

    &Common::Messages::block_public_calls( __PACKAGE__ );

    $args = &Registry::Args::check(
        $args || {},
        {
            "AR:0" => [ "dirs" ],
            "S:0" => [ qw ( force clean download install verbose silent list print_header indent ) ],
        } );

    $conf = &Install::Profile::create_install_config( $db );

    if ( $args->dirs )
    {
        @dirs = @{ $args->dirs };
    }
    else
    {
        if ( $args->download ) {
            push @dirs, $conf->src_dir;
        }

        if ( $args->install ) {
            push @dirs, ( $conf->tab_dir, $conf->tmp_dir, $conf->ins_dir );
        }
    }

    $dat_dir = $conf->dat_dir;

    # Un-install files,

    $fcount = 0;
    $rcount = 0;

    if ( not $args->silent ) {
        &echo( "   Uninstalling ". $db->title ." ... " );
    }

    {
        local $Common::Messages::silent;
        local $Common::Messages::indent_plain;
        
        if ( $args->silent or not $args->verbose ) {
            $Common::Messages::silent = 1;
        }
        
        if ( defined $args->indent ) {
            $Common::Messages::indent_plain = $args->indent;
        } else {
            $Common::Messages::indent_plain = 3;
        }

        &echo( "\n" );
        
        # Database records,

        if ( $args->install ) {
            $rcount = &Install::Data::uninstall_dataset_db( $db );
        }

        # Install, scratch and optionally download files, 
        
        foreach $dir ( @dirs )
        {
            $name = &File::Basename::basename( $dir );

            &echo( qq (   Deleting from $name ... ) );
            
            if ( -e $dir )
            {
                $count = &Common::File::delete_dir_tree( $dir );
                $count += &Common::File::delete_dir_path_if_empty( $dir );
                
                if ( $count > 0 )
                {
                    &echo_done( "$count\n" );
                    $fcount += $count;
                }
                else {
                    &echo_green( "none\n" );
                }
            }
            else {
                &echo_yellow( "missing\n" );
            }
        }
        
        # "Meta" files,
        
        if ( $args->install and $args->clean and -d $dat_dir )
        {
            &echo( qq (   Deleting meta files ... ) );
            
            $count = 0;
            
            foreach $file ( &Common::File::list_files( $dat_dir, '.cache$' ),
                            &Common::File::list_files( $dat_dir, '.yaml$' ) )
            {
                &Common::File::delete_file( "$dat_dir/". $file->{"name"} );
                $count += 1;
            }
            
            $count += Registry::Register->delete_timestamp( $dat_dir );
            $count += Registry::Register->delete_entries_list( $dat_dir );
            
            $count += &Common::File::delete_dir_path_if_empty( $dat_dir );
            
            if ( $count > 0 )
            {
                &echo_green( "$count\n" );
                $fcount += $count;
            }
            else {
                &echo_green( "none\n" );
            }
        }

        # Unregister,
        
        if ( $args->install )
        {
            &echo( qq (   Unregistering ... ) );
            $count = Registry::Register->unregister_datasets( $db->name );
            
            if ( $count ) {
                &echo_green( "done\n" );
            } else {
                &echo_yellow( "not registered\n" );
            }
        }

        &echo("");
    }
    
    if ( not $args->silent )
    {
        &echo_green( "done\n" );
    }

    return ( $fcount, $rcount );
}

sub uninstall_projects
{
    # Niels Larsen, June 2009.

    # Uninstall a given list of projects, and all their associated data if 
    # needed. 

    my ( $projs,        # List of project names or objects
         $args,         # Arguments hash
        ) = @_;

    # Returns nothing.

    my ( $def_args, @dbs, $db, @names, $name, $proj, %filter, $count, $db_count,
         $title, $proj_dir );
    
    $def_args = {
        "download" => 1,
        "install" => 1,
        "all" => 0,
        "verbose" => 0,
        "silent" => 0,
        "force" => 0,
        "list" => 0,
        "confirm" => 0,
        "print_header" => 0,
    };

    $args = &Common::Util::merge_params( $args, $def_args );
    
    $args = &Registry::Args::check(
        $args || {},
        { 
            "S:0" => [ keys %{ $def_args } ],
        });
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LIST AND SKIP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the list argument is given, create table of projects and exit,

    if ( $args->list )
    {
        &Install::Data::list_projects( "uninstalled", $args->all );
        exit 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GET PROJECT LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check if the given project names match those in the registry. If --all or
    # no projects given, get them all,

    if ( $args->all )
    {
        @names = Registry::Get->projects()->options_names;
    }
    elsif ( $projs and @{ $projs } )
    {
        @names = &Install::Data::check_projects( $projs );
    }
    else {
        &error( qq (No projects given) );
    }

    # Filter if not force,

    if ( not $args->force ) 
    {
        %filter = map { $_, 1 } Registry::Register->registered_projects();
        @names = grep { $filter{ $_ } } @names;
    }
    
    # Return if nothing to install,

    return if not @names;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONFIRM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->confirm )
    {
        $title = "\n$Common::Config::sys_name Project Un-installation\n\n";
        &Install::Data::confirm_menu( \@names, "uninstall", $title );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INSTALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args->print_header( 0 );
    $count = 0;

    foreach $name ( @names )
    {
        if ( not $args->silent ) {
            &echo_bold( "\nUn-installing $name:\n" );
        }

        $proj = Registry::Get->project( $name );
        @dbs = Registry::Get->project_dbs_local( $proj->name )->options;

        # Skip datasets not owned by this project,

        @dbs = &Install::Data::filter_owned_datasets( $proj, \@dbs );
        
        # The --confirm command line argument triggers asking which datasets 
        # should be installed,
        
#        if ( $args->confirm ) {
#            @dbs = &Install::Data::ask_confirmation( \@dbs, "remove" );
#        }

        # Uninstall datasets,
        
        delete $args->{"confirm"};

        foreach $db ( @dbs )
        {
            &Install::Data::uninstall_data( [ $db->name ], $args );
        }

        # Unregister project,

        &echo( "   Unregistering project ... " );
        Registry::Register->unregister_projects( $name );
        &echo_green( "done\n" );
        
        # Remove profile,

        &echo( "   Removing site profile ... " );

        $proj_dir = "$Common::Config::www_dir/". $proj->projpath;

        if ( $proj->projpath and $proj_dir = "$Common::Config::www_dir/". $proj->projpath and -d $proj_dir ) {
            $count = &Common::File::delete_dir_tree( $proj_dir );
        }

        &echo_green( "done\n" );
        
        if ( not $args->silent ) {
            &echo_bold( "Finished\n" );
        }

        $count += 1;
    }

    return $count;
}

sub updates_available
{
    # Niels Larsen, June 2012. 

    # Checks if there are new file versions to download for a given dataset. 
    # If there are, sets or updates the datasets download information. Since
    # download sites keep their data in many different ways, this routine 
    # runs an Install::Download routine named after the dataset that checks 
    # if the remote versions are newer by version number, size or date etc.
    # Returns 1 if there are new data, nothing if not.
    
    my ( $db,
         $conf,
        ) = @_;

    my ( $count, $routine, $files, $expr, @updates, $i, $opts, @hits );

    $routine = "Install::Download::". $db->name;
    $count = 0;

    if ( Registry::Check->routine_exists({ "routine" => $routine, "fatal" => 0 }) )
    {
        no strict "refs";

        @updates = $routine->( $db, $conf );
        $files = $db->downloads->files;

        if ( @updates )
        {
            $opts = $files->options;

            for ( $i = 0; $i <= $#{ $opts }; $i++ )
            {
                $expr = $opts->[$i]->remote;

                if ( @hits = grep /$expr/, @updates )
                {
                    if ( scalar @hits == 1 ) {
                        $opts->[$i]->remote( $hits[0] );
                    } else {
                        &error( qq (More than one remote file match "$expr") );
                    }
                }
                else {
                    $opts->[$i] = undef;
                }
            }
            
            $files->options([ grep { defined $_ } @{ $opts } ]);

            $count = 1;
        }
    }
    else {
        $count = 1;
    }

    return $count if $count > 0;

    return;
}

1;

__END__
