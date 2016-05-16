package Recipe::Run;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @EXPORT_OK );
require Exporter;

@EXPORT_OK = qw (
                 &cat_commands
                 &check_inputs
                 &check_outputs
                 &command_parallel
                 &command_single
                 &debug_main
                 &print_receipt
                 &run_recipe
                 &run_recipe_args
                 &run_step
                 &stop_recipes
                 &submit_batch
);

use Time::HiRes;
use Time::Duration qw ( duration );
use Data::Dumper;

use Common::Config;
use Common::Messages;
use Common::File;
use Common::OS;
use Common::Admin;

use Registry::Args;

use Recipe::Messages;
use Recipe::Util;
use Recipe::IO;
use Recipe::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub cat_commands
{
    # Niels Larsen, March 2012. 

    # Creates and returns a command string like '( cat file1 && bzcat file2.bz2 )'
    # which will copy a mixture of compressed and uncompressed to STDOUT, which 
    # then is used as program input.

    my ( $fexp,    # Shell file expression
         $msgs,    # Outgoing messages
        ) = @_;

    # Returns string.

    my ( @files, @cmd, $cmd, @list, $file, $msg );

    @files = &Recipe::IO::list_files( $fexp );

    foreach $file ( @files )
    {
        # Why was this done .. 
        # $file = &Common::File::resolve_links( $file );

        if ( &Common::File::is_ascii( $file ) )
        {
            push @cmd, "cat $file";
        }
        elsif ( &Common::File::is_compressed_gzip( $file ) )
        {
            push @cmd, "zcat $file";
        }
        elsif ( &Common::File::is_compressed_bzip2( $file ) )
        {
            push @cmd, "bzcat $file";
        }
        elsif ( &Common::File::is_compressed_zip( $file ) )
        {
            push @cmd, "unzip -p $file";
        }
        else 
        {
            push @list, $file;
        }
    }

    if ( @list )
    {
        $msg->{"oops"} = qq (These input files could not be streamed:\n);
        $msg->{"list"} = \@list;

        $msg->{"help"} = 
            qq (By default, all recipe input files are read as a single\n)
           .qq (stream. The above files are not suitable for that and must\n)
           .qq (be processed separately. Try negate the single-switch by\n)
           .qq (adding --nosingle. Then this error should go away.);
        
        &Recipe::Messages::oops( $msg );
    }

    $cmd = "( ". (join " && ", @cmd) . " )";

    return $cmd;
}

sub check_inputs
{
    # Niels Larsen, March 2013.

    # Make sure all files are readable that are given as input to the first
    # step of the recipe to be run. Returns nothing, but prints a message if
    # something wrong and then exits. 

    my ( $rcp,        # Recipe structure
         $cat,        # Whether to check for streaming
        ) = @_;

    # Returns nothing.

    my ( $begndx, @files, $file, $step, $run, $i, $args, @msgs, $msg, $files, 
         $title, $name, $in_dir );

    $begndx = $rcp->{"begin-step"} // 0;

    $step = $rcp->{"steps"}->[$begndx];
    $run = $step->{"run"};
    $files = $run->in_files;

    $in_dir = &File::Basename::dirname( $run->in_files );

    if ( ref $files ) {
        @files = @{ $files };
    } else {
        @files = $files;
    }

    @files = &Recipe::IO::list_files( \@files, 0 );

    if ( @files )
    {
        $i = 0;

        foreach $file ( @files )
        {
            if ( not -r $file )
            {
                push @{ $msg->{"list"} }, $file;
                $i += 1;
            }
        }

        if ( $i > 0 ) 
        {
            $msg->{"oops"} = qq (These files are not found:);
            $msg->{"help"} = 
            qq (Input files can be located in any directory, their names\n)
           .qq (given in quotes or not, and they be compressed in gzip, zip\n)
           .qq (or bzip2 formats.\n);

            &Recipe::Messages::oops( $msg );
        }
    }
    elsif ( -d $in_dir )
    {
        $name = $step->{"name"};
        $title = $step->{"title"};

        $msg->{"oops"} =
            qq (No input files found for the step "$name",\n)
           .qq ((title "$title").);

        if ( ref $files )
        {
            $msg->{"help"} = qq (Please check that the files given to the recipe do exist.\n);
        }
        else 
        {
            $msg->{"help"} =
                 qq (Each step uses the outputs from the previous step as its input,\n)
                .qq (and for this step the needed input files can be listed with:\n)
                .qq (\n)
                .qq (ls -1 -d $files\n)
                .qq (\n)
                .qq (Maybe they were never created, maybe they were deleted since,\n)
                .qq (maybe a recipe authoring error or maybe even a software error.\n);
        }

        &Recipe::Messages::oops( $msg );
    }
    else 
    {
        $msg->{"oops"} = qq (No such input directory:\n$in_dir\n);
        
        $msg->{"help"} =
            qq (Either the input has not been generated for this step, or\n)
           .qq (perhaps they are under a different output prefix. Change it\n)
           .qq (with the --outpre option.\n);

        &Recipe::Messages::oops( $msg );
    }
        
    # Input files must be streamable if --single is on: if the recipe has 
    # multiple input files and is run with --single, then content of all input 
    # files are piped into the first program. For that to work, all files must 
    # be 'cat-able' or 'zcat-able' and here we just check for that,

    if ( $cat and scalar @files > 1 and 
         not &Recipe::Run::cat_commands( (join " ", @files), \@msgs ) )
    {
        $msg->{"oops"} = qq (Not all files are pipe-able:);
        $msg->{"list"} = [ map { $_->[1] } @msgs ];
        $msg->{"help"} = qq (Uncompressing, or converting to gzip or bzip2 format should help);
    
        &Recipe::Messages::oops( $msg );
    }
    
    return;
}

sub check_outputs
{
    # Niels Larsen, March 2013. 

    # Checks existence of directories and files for each step being run in the 
    # given recipe. Returns nothing, but prints message and exits.

    my ( $rcp,       # Recipe
         $msgs,      # Message list - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $i, $step, $dir, $run, $args, $files, @files, $str );

    for ( $i = $rcp->{"begin-step"}; $i <= $rcp->{"end-step"}; $i += 1 )
    {
        $run = $rcp->{"steps"}->[$i]->{"run"};

        if ( -e ( $dir = $run->out_dir ) )
        {
            @files = &Recipe::IO::list_files( $run->out_dir );

            $str = &echo_yellow( &done_string( ( scalar @files ) ." file[s]" ) );

            push @{ $args->{"list"} }, [ "( $str )", $dir ];
        }
    }
    
    if ( $args )
    {
        $args->{"oops"} = qq (These output directories exist:);
        $args->{"help"} = qq (The --clobber option will overwrite them.); 

        &Recipe::Messages::oops( $args );
        exit;
    }

    return;
}

sub command_parallel
{
    # Niels Larsen, May 2012. 

    # Creates a GNU parallel command-line string and a file of commands to 
    # to be used as its input. A token-command is input, which comes from
    # definitions in Recipe::Steps. The second argument is the run-time 
    # from the recipe for a given step. Output is the GNU parallel command
    # string and this routine also writes the corresponding file of commands
    # to be run in parallel.

    my ( $tcmd,    # Token command string
         $run,     # Run-time configuration
         $args,    # General arguments 
        ) = @_;

    # Returns a string.
    
    my ( @in_files, @out_files, @stat_files, $i, $j, $cmd, @prl_commands, 
         $log_dir, $fh, $add_args, @msgs, $file, $out_dir, $out_pre, $name,
         $run_file );

    $out_dir = $run->out_dir;

    $log_dir = $args->logdir;
    $out_pre = $args->outpre;

    &Recipe::IO::create_dir_if_not_exists( $log_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LOG RUN CONFIG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::File::dump_file( "$log_dir/run-config.dump", $run, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Use the given expression to list the files, then continue only with 
    # the non-empty ones,
        
    @in_files = &Recipe::IO::list_files( $run->in_files, $args->fatal );
    @in_files = grep { -s $_ } @in_files;

    if ( @in_files )
    {
        # Largest input files first, so run time will be shorter,
        @in_files = reverse sort { -s $a <=> -s $b } @in_files;
    }
    else
    {
        $out_dir = $run->out_dir;
        &error( qq (Input files exist but are all empty\n)
                .qq (Directory is "$out_dir") );
    }
    
    # If all or some files are zipped, and the method does not tolerate that,
    # then unzip them and strip the file name suffixes. It cannot be done in 
    # parallel, so might as well do it here,
    
    if ( not $run->in_zipped and grep { $_ =~ /\.zip$/ } @in_files )
    {
        &Common::File::unzip_files_single( \@in_files );
        @in_files = map { &Common::Names::strip_suffix( $_, ".zip" ) } @in_files;
    }
    
    &Common::File::write_file( "$log_dir/input-files", [ map { $_."\n" } @in_files ], 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Use name prefixes from the output directory of the previous step, but 
    # add this step's suffix,
    
    @out_files = ();
    
    foreach $file ( @in_files )
    {
        $name = &File::Basename::basename( $file );
        
        if ( $name = &Common::Names::strip_suffix( $name ) )
        {
            push @out_files, $run->out_dir ."/". $name . $run->out_suffix;
        }
        else {
            &error( qq (Wrong looking output file -> "$file". Programming error.) );
        }
    }
    
    &Common::File::write_file( "$log_dir/output-files", [ map { $_."\n" } @out_files ], 1 );

    # Check there are the same number of input and output files, now that 
    # the empty ones are handled above,

    if ( ($i = scalar @in_files) != ($j = scalar @out_files) )
    {
        &error( qq ($i input files, but $j output files.) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Use the output file names, except replace their suffix,

    if ( $tcmd =~ /__STATS__/ )
    {
        @stat_files = ();

        foreach $file ( @out_files )
        {
            $name = &File::Basename::basename( $file );

            if ( $name = &Common::Names::strip_suffix( $name ) )
            {
                push @stat_files, $run->out_dir ."/$name.stats";
            }
            else {
                &error( qq (Wrong looking statistics file -> "$file". Programming error.) );
            }
        }
        
        &Common::File::write_file( "$log_dir/stat-files", [ map { $_."\n" } @stat_files ], 1 );

        if ( ($i = scalar @in_files) != ($j = scalar @stat_files) )
        {
            &error( qq ($i input files, but $j statistics files.) );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE COMMAND LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $add_args = "";

    $add_args .= " --recipe ". $args->recipe if $args->recipe;
    $add_args .= " --clobber" if $args->clobber;
    $add_args .= " --silent" if $args->silent;

    for ( $i = 0; $i <= $#in_files; $i++ )
    {
        $cmd = $tcmd;

        $cmd =~ s/__INPUT__/$in_files[$i]/g;
        $cmd =~ s/__OUTPUT__/$out_files[$i]/g;
        $cmd =~ s/__TMPDIR__/$log_dir/g;
        $cmd =~ s/__OUTDIR__/$out_dir/g;
        $cmd =~ s/__OUTPRE__/$out_pre/g;
        $cmd =~ s/__STATS__/$stat_files[$i]/g if @stat_files;
        
        push @prl_commands, $cmd . $add_args;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE COMMAND FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Save the commands to file that are to be run in parallel, overwrite 
    # existing,

    $run_file = "$log_dir/run-commands";
    &Common::File::write_file( $run_file, [ map { $_."\n" } @prl_commands ], 1 );

    # >>>>>>>>>>>>>>>>>>>> BUILD GNU PARALLEL COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<

    $cmd = "parallel";
    $cmd .= " --nice 19" if $args->yield;
    $cmd .= " --halt-on-error 2 --joblog $log_dir/gnu-parallel.log --tmpdir $log_dir";

    $cmd = "$cmd < $run_file";

    return $cmd;
}

sub command_single
{
    # Niels Larsen, May 2012. 
    
    # Creates a command-line string with expanded input, output and stats 
    # tokens, ready to be run. Makes the string from the dictionary run config
    # hash + general arguments. Returns a command string.

    my ( $tcmd,    # Token command string
         $run,     # Run-time configuration
         $args,    # General arguments 
        ) = @_;

    # Returns a string.

    my ( $cmd, @in_files, $cat_cmd, $file, $in_files, $suffix, @msgs, 
         $str, @out_files, $out_dir, $log_dir, $name, $filexp );
    
    $cmd = $tcmd; 

    $log_dir = $args->logdir;

    &Recipe::IO::create_dir_if_not_exists( $log_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LOG RUN CONFIG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::File::dump_file( "$log_dir/run-config.dump", $run, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( ref $run->in_files )
    {
        $in_files = join " ", @{ $run->in_files };

        @in_files = &Recipe::IO::list_files( $in_files, $args->fatal );
        $in_files = join " ", @in_files;
    }
    else {
        $in_files = $run->in_files;
    }

    @in_files = &Recipe::IO::list_files( $in_files, $args->fatal );

    # Filter for non-empty files,
    
    @in_files = grep { -s $_ } @in_files;

    if ( not @in_files )
    {
        $out_dir = $run->out_dir;
        &error( qq (Input files exist but are all empty\n)
               .qq (Output directory is "$out_dir") );
    }

    # If all or some files are zipped, and the method does not tolerate that,
    # then unzip them and strip the file name suffixes. It cannot be done in 
    # parallel, so might as well do it here,

    if ( not $run->in_zipped and grep { $_ =~ /\.zip$/ } @in_files )
    {
        &Common::File::unzip_files_single( \@in_files );
        @in_files = map { &Common::Names::strip_suffix( $_, ".zip" ) } @in_files;
    }

    &Common::File::write_file( "$log_dir/input-files", [ map { $_."\n" } @in_files ], 1 );

    $in_files = join " ", @in_files;

    # >>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILE TOKENS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( scalar @in_files == 1 )
    {
        $cmd =~ s/__INPUT__/$in_files[0]/g;
    }
    else
    {
        if ( $run->in_multi ) 
        {
            $cmd =~ s/__INPUT__/$in_files/g;
        }
        else
        {
            # $cmd =~ s/__INPUT__/ /g;
            # $cat_cmd = &Recipe::Run::cat_commands( $files );
            
            $cmd =~ s/__INPUT__/$in_files/g;

            # $cmd = "$cat_cmd | $cmd";
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @out_files = ();
    $out_dir = $run->out_dir;

    if ( $cmd =~ /__OUTPUT__/ ) 
    {
        if ( $run->out_multi )
        {
            foreach $file ( @in_files )
            {
                $name = &File::Basename::basename( $file );
                
                if ( $name =~ /^([^\.]+)/ ) {
                    push @out_files, "$out_dir/$1". $run->out_suffix;
                } else {
                    &error( qq (Wrong looking output file -> "$file") );
                }
            }
        }
        else
        {
            $filexp = $run->out_files;
            $filexp =~ s/\*$//;

            @out_files = $filexp;
        }

        $str = join " ", @out_files;
        $cmd =~ s/__OUTPUT__/$str/g;

        &Common::File::write_file( "$log_dir/output-files", [ map { $_."\n" } @out_files ], 1 );
    }
    else {
        &Common::File::write_file( "$log_dir/output-file", $run->out_files ."\n", 1 );
    }        

    if ( $cmd =~ /__TMPDIR__/ )
    {
        $str = $args->logdir;
        $cmd =~ s/__TMPDIR__/$str/g;
    }

    if ( $cmd =~ /__OUTDIR__/ )
    {
        $str = $run->out_dir;
        $cmd =~ s/__OUTDIR__/$str/g;
    }

    if ( $cmd =~ /__OUTPRE__/ )
    {
        $str = $args->outpre;
        $cmd =~ s/__OUTPRE__/$str/g;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file = $run->stat_files )
    {
        if ( $cmd =~ /__STATS__/ )
        {
            &Common::File::write_file( "$log_dir/stats-file", "$file\n", 1 );

            $cmd =~ s/__STATS__/$file/g;
        }
        # else
        # {
        #     &error( qq (Stats file but no __STATS__ token\n)
        #            .qq (Output directory is "$out_dir"\n)
        #            .qq (Command is "$cmd"\n)
        #         );
        # }
    }
    elsif ( $cmd =~ /__STATS__/ )
    {
        &error( qq (__STATS__ token but no stats file.\n)
               .qq (Output directory is "$out_dir"\n)
               .qq (Command is "$cmd")
            );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe ) {
        $cmd .= " --recipe ". $args->recipe;
    }

    if ( $args->clobber ) {
        $cmd .= " --clobber";
    }

    if ( $args->silent ) {
        $cmd .= " --silent";
    }

    return $cmd;
}

sub debug_main
{
    # Niels Larsen, April 2013.
    
    # Prints Data::Dumper outputs of user configuration, routine parameters
    # and code text. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $file, $info, $msg, $text, $logdir, $outdir, $outpre, $out_file,
         @dirs, $dirs, $cmd, $step );

    $outdir = $args->outdir;
    $outpre = $args->outpre;

    $logdir = "$outdir/$outpre.logs";
    
    local $Data::Dumper::Terse = 1;     # avoids variable names
    local $Data::Dumper::Useqq = 1;     # use double quotes

    &Recipe::IO::create_dir_if_not_exists( $logdir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RECIPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # File text as is,

    $file = "$logdir/recipe_orig.text";

    $text = ${ &Common::File::read_file( $args->rcp_file ) };
    &Common::File::write_file( $file, $text, 1 );

    # Parsed recipe with paths set,

    $file = "$logdir/recipe_dump";
    &Common::File::dump_file( $file, $args->rcp, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CONFIGURATIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Command line arguments, with added defaults,

    $file = "$logdir/command_line.args";
    &Common::File::dump_file( $file, $args->cmd_args, 1 );

    # Recipe configuration,
    
    $file = "$logdir/command_line.conf";
    &Common::File::dump_file( $file, $args->rcp_conf, 1 );

    # Run-time configuration hash,
    
    $file = "$logdir/run_args.conf";
    &Common::File::dump_file( $file, $args->run_args, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->debug )
    {
        $info = &Common::Config::get_contacts();

        &echo("\n");
        &echo("   "); &echo_info("DEBUG INFORMATION"); &echo("\n");

        @dirs = "$outdir/$outpre.logs";

        foreach $step ( @{ $args->rcp->{"steps"} } ) {
            push @dirs, $step->{"run"}->out_dir ."/logs";
        }

        $dirs = join "\n", map { "   $_" } @dirs;

        $cmd = "tar -cvzf BION_debug.tar.gz $outdir/$outpre.logs $outdir/*/logs";
        
        $msg = qq (
   These directories will contain files with debug information:

$dirs

   The whole output file tree can be listed by running this command 
   on the command line,

   tree $outdir

   To submit debug information if there is a software problem, run 

   $cmd

   and send us the resulting BION_debug.tar.gz file, which is small 
   and can be sent as an e-mail attachment. If possible, please attach
   a small dataset that demonstrates the problem, and write a few words
   about the problem in general terms. Contact information:

           $info->{'first_name'} $info->{'last_name'}
           $info->{'company'}
   E-mail: $info->{'e_mail'}
    Skype: $info->{'skype'} (GMT+1)

   -------------------------------------------------------------------

);
        &echo( $msg );
    }
    
    return;
}

sub print_receipt
{
    # Niels Larsen, April 2013.

    my ( $conf,
         $msgs,
        ) = @_;

    my ( @msgs, $str, $file, $out_dir, $out_pre, $out_hdr, $help_hdr,
         $con_hdr, $sup_hdr, $text, $info, $done_hdr );

    $out_dir = $conf->outdir;
    $out_pre = $conf->outpre;

    if ( $msgs and @{ $msgs } )
    {
        push @msgs, @{ $msgs };
        &echo_messages( \@msgs );
    }

    $str = &echo_bold("GMT+1");
    $file = &echo_info( "$out_dir/$out_pre.html" );

    $done_hdr = &echo_info_green(" Finished ");
    $help_hdr = &echo_info(" Help ");
    $sup_hdr = &echo_oops(" Support ");

    $info = &Common::Config::get_contacts();

    $text = qq ( ----------------------------------------------------------------------

 $done_hdr

 Outputs can be seen by web-browser by loading $out_dir/index.html,
 or by console by running 'tree $out_dir' on the command line. 
 The output directory is a self-contained web-site that can be 
 accessed on any system or put on the intra/internet.

 $help_hdr

 All are welcome to report errors at any level. This is best done by 
 re-running with the --debug option and then e-mail the tar.gz archive 
 created, the --debug option will explain.

 $sup_hdr

 Sites with a support agreement may contact us for any reason. We 
 will fix errors quickly, discuss the data, and extend the package 
 in any needed direction at reasonable cost. Contact person:

         $info->{'first_name'} $info->{'last_name'}
  Skype: $info->{'skype'} (often on)
 Mobile: $info->{'telephone'} ($str)
 E-mail: $info->{'e_mail'}

 ----------------------------------------------------------------------

);

    &echo( $text );

    return;
}

sub run_recipe
{
    # Niels Larsen, January 2012.

    # Main routine that runs recipes. Each step takes input from the output 
    # of the previous step and are configured in Recipe::Steps. Steps can run
    # in parallel, with the GNU parallel command line utility, when there are
    # multiple input files. 

    my ( $args,            # Arguments hash or object
        ) = @_;

    # Returns nothing.

    my ( $defs, $log_dir, $val, $rcp, $title, $rcp_file, $step, @msgs, 
         $out_dir, $cpus, $cores, $conf, $name, $count, @info, $info, 
         $step_start, $step_secs, $prefix, $rcp_start, $out_pre, $stats, 
         $run_secs, $run_args, $site, @out_files, $msgs, $file, $i,
         $steps, $msg, @sub_dirs, $sub_dir, $run, $sub_run, $author,
         $routine, $module, @files, $status, $substep_start, $substep_secs );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> STOP RECIPE RUNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->stop )
    {
        &Recipe::Run::stop_recipes( $args );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LIST RECIPE STEPS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->list )
    {
        if ( $args->recipe )
        {
            $rcp = &Recipe::IO::read_recipe( $args->recipe, { "delta" => $args->delta, "check" => 0 } );
            &Recipe::Util::list_steps( $rcp );
            exit;
        }
        else
        {
            $msg->{"oops"} = qq (The --list option requires a recipe file to list steps from.\n);
            $msg->{"help"} = qq (Please specify a recipe file\n);
            &Recipe::Messages::oops( $msg );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "recipe" => undef,      # Recipe text file
        "ifiles" => [],         # List of input files 
        "outdir" => "Results",  # Output directory
        "outpre" => "BION",     # Output file prefix
        "list" => 0,            # List recipe steps
        "batch" => 0,           # Run job in the background or not 
        "single" => 1,          # Regard multiple inputs as single stream
        "delta" => undef,       # File of overriding keys and values
        "beg" => undef,         # Name of first main step
        "end" => undef,         # Name of last main step
        "yield" => 1,           # Runs at lowest priority 
        "stop" => 0,            # Stops all running recipes
        "stats" => 0,           # Rewrites main statistics
        "clobber" => 0,         # Overwrites existing outputs
        "silent" => 0,          # Prints no console messages
        "debug" => 0,           # Runs in debug mode 
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Recipe::Run::run_recipe_args( $args );

    $out_dir = $conf->outdir;
    $out_pre = $conf->outpre;
    $log_dir = $out_dir ."/$out_pre.logs";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> READ RECIPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read and parse recipe. If a delta file is given, its lines overwrite the
    # lines that match in the template recipe. This is a way to avoid multiple
    # recipe versions that only differ little. 

    $rcp = &Recipe::IO::read_recipe( $conf->recipe, { "delta" => $conf->delta } );
    
    &Recipe::Util::set_beg_end( $rcp, $conf->beg, $conf->end );

    $title = $rcp->{"title"};
    $author = $rcp->{"author"};
    $site = $rcp->{"site"} // $Common::Config::company // "";
    
    $rcp->{"log_dir"} = $log_dir;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> SET AND CHECK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sets an index for each step that tells which other step the input should
    # be taken from. By default it comes from the previous step, but if recipe
    # says "input-step = (step name)" then that step is looked up and its 
    # index set. If step name is "recipe-input" then index is undefined,

    &Recipe::Util::set_input_indices( $rcp, $conf );

    # Sets file path expressions for each recipe step. The recipe input files
    # are known, but output file names from the following steps are not always
    # known until after the step has been run. So file expressions are set in
    # this routine so that the 'ls' command can list the files by their suffix.

    &Recipe::Util::set_file_paths( $rcp, $conf );

    # Check that all files are readable that are given as input to the first
    # step of the recipe to be run,

    if ( not $args->stats ) {
        &Recipe::Run::check_inputs( $rcp, $conf->single );
    }

    # Check for existing outputs that may not exist unless --clobber,
    
    if ( not $conf->clobber ) {
        &Recipe::Run::check_outputs( $rcp );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> BACKGROUND JOBS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Fork this process, exit with a message and reassign screen output to the
    # file run_recipe.screen in the directory where the job is submitted,

    if ( $conf->batch ) {
        &Recipe::Run::submit_batch( $rcp );
    }

    # >>>>>>>>>>>>>>>>>>>>>> JUST REWRITE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\n$title:\n) );

    if ( $args->stats ) {
        goto RECEIPT;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Variables used repeatedly below, etc,

    $Common::Messages::silent = $conf->silent;

    &Recipe::IO::create_dir_if_not_exists( $out_dir );
    &Recipe::IO::create_dir_if_not_exists( $log_dir );

    $rcp_start = time();

    $run_args = bless {
        "logdir" => undef,
        "outdir" => $conf->outdir,
        "outpre" => $conf->outpre,
        "yield" => $conf->yield,
        "fatal" => 1,
        "clobber" => $conf->clobber,
        "silent" => undef,
        "recipe" => undef,
        "env" => {
            "BION_RECIPE_TITLE" => $title,
            "BION_RECIPE_SITE" => $site,
        },
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG LOGGING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This writes a copy of everything relevant to separate files within a 
    # scratch directory. Without --debug, this directory is deleted after an 
    # error free run, otherwise kept,

    &Recipe::Run::debug_main(
        bless {
            "log_dir" => $log_dir,
            "rcp" => $rcp,
            "rcp_file" => $conf->recipe,
            "cmd_args" => $args,
            "rcp_conf" => $conf,
            "run_args" => $run_args,
            "debug" => $conf->debug,
            "outdir" => $out_dir,
            "outpre" => $out_pre,
        });

    # There are also log directories below, for each step when run.

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PRINT AUTHOR INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Print author etc on console,

    @info = (
        [ "author", "Author" ],
        [ "email",  "E-mail" ],
        [ "skype",  " Skype" ],
        [ "phone",  " Phone" ],
        [ "web",    "WW Web" ],
        );

    foreach $info ( @info )
    {
        if ( $val = $rcp->{ $info->[0] } )
        {
            &echo("   $info->[1]: " );
            &echo_info( $val );
            &echo("\n");
        }
    }

    &echo("   Started: ". &Common::Util::epoch_to_time_string() ."\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PRINT CPU CORES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Mention CPU and cores, just to make clear to users they are being used,

    &echo("   Detecting hardware ... ");

    $cpus = &Common::OS::get_cpus( $log_dir );
    $cores = &Common::OS::get_cores( $log_dir );

    &echo_done("$cpus cpu[s], $cores core[s]\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> DELETE IF CLOBBER <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If --clobber given, delete all old outputs produced by the steps being 
    # run, but leave the rest,

    if ( $conf->clobber )
    {
        &echo("   Deleting previous outputs ... ");
        $count = &Recipe::IO::delete_outputs( $rcp, $conf );
        &echo_done( "$count file[s]\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> LOOP THROUGH STEPS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    for ( $i = $rcp->{"begin-step"}; $i <= $rcp->{"end-step"}; $i += 1 )
    {
        $step = $rcp->{"steps"}->[$i];

        &echo("   $step->{'title'} ... ");
        
        $step_start = &Common::Messages::time_start();
        $run = $step->{"run"};

        &Recipe::IO::create_dir_if_not_exists( $run->out_dir );

        if ( $run->in_dir )
        {
            @sub_dirs = &Recipe::IO::list_dirs( $run->in_dir );
            @sub_dirs = grep { $_ !~ /\/logs$/ } @sub_dirs;
        }
        else {
            @sub_dirs = ();
        }

        if ( defined $run->in_dir and @sub_dirs )
        {
            # >>>>>>>>>>>>>>>>>>>>>> LOOP SUBDIRECTORIES <<<<<<<<<<<<<<<<<<<<<<

            # If sub-directories produced by previous step, then through the
            # step on each, as a simple un-parallelized loop. The easist is to
            # edit the file paths and set them 

            foreach $sub_dir ( map { &File::Basename::basename( $_ ) } @sub_dirs )
            {
                $substep_start = &Common::Messages::time_start();

                $sub_run = &Storable::dclone( $run );

                $sub_run->{"in_dir"} .= "/$sub_dir";
                $sub_run->{"in_files"} =~ s|/\*|/$sub_dir/\*|;
                $sub_run->{"out_dir"} .= "/$sub_dir";
                $sub_run->{"out_files"} =~ s|/\*/\*|/$sub_dir/\*|;
                $sub_run->{"stat_files"} =~ s|/([^\/]+)$|/$sub_dir/$1|;
                
                $step->{"run"} = $sub_run;

                &Recipe::Run::run_step( $step, $run_args );

                $substep_secs = int ( &Common::Util::time_elapsed() - $substep_start );

                &Recipe::IO::write_status(
                    $sub_run->{"out_dir"} ."/STATUS",
                    "secs" => $substep_secs,
                    "date" => &Common::Util::epoch_to_time_string(),
                    );
            }

            # >>>>>>>>>>>>>>>>>>>>> SUMMARY STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<

            # Create summary statistics if a sum-routine is given,

            if ( $routine = $run->dir_routine )
            {
                if ( $routine =~ /^(.+)::([^:]+)$/ )
                {
                    $module = $1;
                    
                    if ( not eval "require $module" ) {
                        &error( qq (Wrong looking module -> "$module") );
                    }
                    
                    @files = &Recipe::IO::list_files( $run->out_dir ."/*/*.stats", 0 );

                    {
                        no strict "refs";
                        $routine->( \@files, $run->out_dir ."/step.stats" );
                    }
                }
                else {
                    &error( qq (Wrong looking routine -> "$routine") );
                }
            }
        }
        else
        {
            &Recipe::Run::run_step( $step, $run_args );
        }

        $step_secs = int ( &Common::Util::time_elapsed() - $step_start );

        &Recipe::IO::write_status(
            $run->out_dir ."/STATUS",
            "secs" => $step_secs,
            "date" => &Common::Util::epoch_to_time_string(),
            );

        $step->{"run"} = $run;

        &echo_done("$step_secs sec[s]\n");
    }

    $run_secs = time() - $rcp_start;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLEANUP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Delete files the recipe wants deleted (keep-outputs = no), 

    &echo("   Deleting no-keep files ... ");
    $count = &Recipe::IO::delete_outputs_nokeep( $rcp );
    &echo_done("$count\n");

    # Delete scratch directory and its files unless Debug is on,

    if ( not $conf->debug )
    {
        &echo("   Deleting log files ... ");
        $count = &Recipe::IO::delete_step_logs( $rcp );
        &echo_done("$count\n");
    }

    # Zip-compress files where the recipe wants it,

    &echo("   Zip-compressing outputs ... ");
    $count = &Recipe::IO::zip_some_outputs( $rcp );
    &echo_done("$count files\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE RECEIPTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  RECEIPT: 

    &echo("   Write receipt files ... ");

    $msgs = [];

    &Recipe::Stats::write_main(
        $rcp,
        {
            "outdir" => $out_dir,
            "outpre" => $out_pre,
            "title" => $title,
            "author" => $author,
            "date" => &Common::Util::epoch_to_time_string(),
            "time" => &Time::Duration::duration( $run_secs ),
        }, $msgs );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> HTMLIFY RECEIPTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Make HTML versions of the files written in last section,

    &echo("   Making html versions ... ");

    $prefix = "$out_dir/$out_pre";

    &Recipe::Stats::text_to_html(
        "$prefix.recipe $prefix.files $prefix.*/*.txt",
        {
            "lhead" => $title,
            "rhead" => $site,
            "pre" => 1,
        });

    &Recipe::Stats::text_to_html(
        "$out_dir/BION.about/*.todo $out_dir/BION.about/*.about",
        {
            "lhead" => $title,
            "rhead" => $site,
            "pre" => 0,
        });
    
    &Recipe::Stats::htmlify_stats(
        "$prefix.stats",
        {
            "level" => 0,
            "lhead" => $title,
            "rhead" => $site,
            "clobber" => 1,
            "silent" => 1,
        });

    &Recipe::Stats::htmlify_stats(
        "$prefix.*/*.stats $prefix.*/*/*.stats",
        {
            "level" => 0,
            "lhead" => $title,
            "rhead" => $site,
            "clobber" => 1,
            "silent" => 1,
        });

    &echo_done("done\n");
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE LINKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create an index.html and index.htm to simplify the link for users,

    &echo("   Creating index.html ... ");

    &Common::File::delete_file_if_exists( "$prefix.html" );
    &Common::File::create_link( "$prefix.stats.html", "$prefix.html" );

    &Common::File::delete_file_if_exists( "$out_dir/index.html" );
    &Common::File::create_link( "$prefix.stats.html", "$out_dir/index.html" );
    
    &Common::File::delete_file_if_exists( "$out_dir/index.htm" );
    &Common::File::create_link( "$prefix.stats.html", "$out_dir/index.htm" );
    
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TOTAL RUN TIME <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo("   Finished: " . &Common::Util::epoch_to_time_string() ."\n" );

    &echo("   Run time: ");
    &echo_info( &Time::Duration::duration( $run_secs ) ."\n" );

    &echo_bold("Finished\n\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FINAL MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Recipe::Run::print_receipt( $conf, $msgs );

    return;
}

sub run_recipe_args
{
    # Niels Larsen, January 2012.

    # Basic arguments check of input and output files and directories. 
    # Exits with messages if something wrong.

    my ( $args,
        ) = @_;

    # Returns a hash.

    my ( @msgs, $file, @files, @ofiles, $outdir, $outpre, $rcp, $i,
         $steps, $step, $name, $run, $msg, $help );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> RECIPE INPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Recipe must be given, exist and really be a recipe,

    $help = 
        qq (The recipe file must be given as first argument. The next\n)
       .qq (argument, or arguments, are data files. Data files can be\n)
       .qq (omitted if the --beg option is given, because then input is\n)
       .qq (taken from the step previous to that specified with --beg.\n);

    if ( not $file = $args->recipe )
    {
        $msg->{"oops"} = qq (No recipe file given.);
        $msg->{"help"} = $help;
    }
    elsif ( not -r $file )
    {
        $name = &File::Basename::basename( $file );

        $msg->{"oops"} = qq (Recipe file not found: "$file");
        $msg->{"help"} = $help;
    }
    elsif ( not &Recipe::IO::is_recipe_file( $file ) )
    {
        $msg->{"oops"} = qq (Recipe file looks wrong inside: "$file");
        $msg->{"help"} = $help;
    }        

    if ( $msg ) {
        &Recipe::Messages::oops( $msg );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Only check for presence. The check_inputs routine does the rest, because
    # that must be done after the recipe is read etc,

    $help = 
        qq (Input files can be located in any directory, their names\n)
       .qq (given in quotes or not, and they be compressed in gzip, zip\n)
       .qq (or bzip2 formats.\n);

    if ( not $args->beg and ( not $args->ifiles or not @{ $args->ifiles } ) )
    {
        $msg->{"oops"} = qq (No input data files given.);
        $msg->{"help"} = $help;

        &Recipe::Messages::oops( $msg );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Again, just check the very basic. The check_outputs routine does the 
    # rest later,

    $outdir = $args->outdir;
    $outpre = $args->outpre;

    $help = 
        qq (The output directory is where all results go. In it, each step\n)
       .qq (has a sub-directory with all files produced by that step, with\n)
       .qq (prefixed names ($outpre by default, but changable with --outpre).\n);

    if ( not $outdir )
    {
        $msg->{"oops"} = qq (An output directory must be given with --outdir);
        $msg->{"help"} = $help;

        &Recipe::Messages::oops( $msg );
    }
    elsif ( -e $outdir and not -w $outdir )
    {
        $msg->{"oops"} = qq (Output directory not writable: "$outdir");
        $msg->{"help"} = $help;

        &Recipe::Messages::oops( $msg );
    }

    return $args;
}

sub run_step
{
    # Niels Larsen, April 2013.

    # Runs a step, with pre- and post-commands. 

    my ( $step,
         $args,
        ) = @_;

    my ( $run, $token_cmd, $run_cmd, $run_args, $rcp_file, $log_dir, $out_dir,
         $routine, $module, @files, $stat_text, $stats, $summary, $base_dir );

    $run = $step->{"run"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $log_dir = $run->out_dir ."/logs";
    $run->add_field("log_dir", $log_dir );

    &Recipe::IO::create_dir( $log_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>> RUN PRE-COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Pre-commands could be format conversion for example, and can be run in 
    # parallel or as single process,

    $run_args = &Storable::dclone( $args );

    $run_args->clobber( undef );
    $run_args->silent( undef );
    $run_args->recipe( undef );
    
    if ( $token_cmd = $run->prl_precmd )
    {
        $run_args->logdir( "$log_dir/prl_precmd" );
        $run_cmd = &Recipe::Run::command_parallel( $token_cmd, $run, $run_args );
        
        &Common::OS::run_command_parallel( $run_cmd, $run_args );
    } 
    elsif ( $token_cmd = $run->precmd )
    {
        $run_args->logdir( "$log_dir/precmd" );
        $run_cmd = &Recipe::Run::command_single( $token_cmd, $run, $run_args );
        
        &Common::OS::run_command_single( $run_cmd, $run_args );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> RUN MAIN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # If a step wants recipe (its use_recipe field set), write a temporary 
    # sub-recipe for this step and add its path to the command formed below,
    
    if ( $run->use_recipe )
    {
        $rcp_file = "$log_dir/". $step->{"name"} .".recipe";
        &Recipe::IO::write_recipe( $rcp_file, $step );
        
        $run_args->recipe( $rcp_file );
    }
    else {
        $run_args->recipe( undef );
    }
    
    $run_args->silent( 1 );

    # Run command as parallel or single, 

    if ( $token_cmd = $run->prl_cmd )
    {
        $run_args->logdir( "$log_dir/prl_cmd" );
        $run_cmd = &Recipe::Run::command_parallel( $token_cmd, $run, $run_args );

        &Common::OS::run_command_parallel( $run_cmd, $run_args );
    }
    elsif ( $token_cmd = $run->cmd )
    {
        $run_args->logdir( "$log_dir/cmd" );
        $run_cmd = &Recipe::Run::command_single( $token_cmd, $run, $run_args );

        &Common::OS::run_command_single( $run_cmd, $run_args );
    }
    else
    {
        &dump( $run );
        &error( qq (Missing prl_cmd and cmd fields. Programming error.\n) );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> RUN POST-COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Post-commands could be format conversion or deleting temporary files for 
    # example, and can be run in parallel or as single process,

    $run_args = &Storable::dclone( $args );

    $run_args->clobber( undef );
    $run_args->silent( undef );
    $run_args->recipe( undef );
    
    if ( $token_cmd = $run->prl_postcmd )
    {
        $run_args->logdir( "$log_dir/prl_postcmd" );
        $run_cmd = &Recipe::Run::command_parallel( $token_cmd, $run, $run_args );
        
        &Common::OS::run_command_parallel( $run_cmd, $run_args );
    }
    elsif ( $token_cmd = $run->postcmd )
    {
        $run_args->logdir( "$log_dir/postcmd" );
        $run_cmd = &Recipe::Run::command_single( $token_cmd, $run, $run_args );
        
        &Common::OS::run_command_single( $run_cmd, $run_args );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> SUMMARY STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a statistics file with summary information from each of the runs 
    # in parallel. 

    if ( $routine = $run->sum_routine )
    {
        # Extract module name and load it,

        if ( $routine =~ /^(.+)::([^:]+)$/ ) {
            $module = $1;
        } else {
            &error( qq (Wrong looking routine -> "$routine") );
        }
        
        if ( not eval "require $module" ) {
            &error( qq (Wrong looking module -> "$module") );
        }
        
        @files = &Recipe::IO::list_files( $run->stat_files, 0 );
        
        if ( @files )
        {
            {
                no strict "refs";
                $routine->( \@files, $run->out_dir ."/step.stats" );
            }
            
            #$stats = &Recipe::Util::parse_stats( $stat_text );            
            #$stat_text = &Recipe::Util::format_stats( $stats );

            #&Common::File::write_file( $run->out_dir ."/step.stats", $stat_text );
        }
        else {
            &error( qq (No statistics for "$step->{'title'}" ($step->{'name'}) ) );
        }
    }

    return;
}

sub stop_recipes
{
    # Niels Larsen, August 2012. 

    # Stops all run_recipe processes and their children processes. There will 
    # be a job-queue instead of this.

    my ( @procs, @ids, $id, $i, $j );

    &echo_bold("\nStopping recipes:\n");

    &echo("   Are there running recipes ... ");
    
    @procs = &Common::Admin::list_processes("run_recipe");
    @procs = grep { $_->cmndline !~ /--stop/i } @procs;

    @ids = map { $_->pid } @procs;

    push @ids, map { &Common::Admin::child_process_ids( $_ ) } @ids;

    @ids = &Common::Util::uniqify( \@ids );

    if ( @ids )
    {
        $i = scalar @ids;
        &echo_green("yes $i\n");

        &echo("   Stopping all recipe processes ... ");

        $j = 0;

        foreach $id ( @ids )
        {
            kill 2, $id || &error("Cannot interrupt $id: $!");
            $j += 1;
        }

        sleep 1;

        &echo_green( "$j\n" );
        
        if ( $i != $j ) {
            &echo_warning("   There were $i processes, but $j were stopped\n");
        }

        &echo("   Are all processes gone ... ");
        
        @procs = &Common::Admin::list_processes("run_recipe");

        @procs = grep { $_->cmndline !~ /--stop/i } @procs;

        if ( scalar @procs == 0 ) {
            &echo_green( "yes\n" );
        } else {
            &echo_red( "NO\n" );
            &echo_red( "These were not stopped:\n" );
            &dump([ map { $_->cmndline } @procs ]);
        }
    }
    else {
        &echo_green("no\n");
    }

    &echo_bold("Done\n\n");

    return;
}

sub submit_batch
{
    # Niels Larsen, March 2012. 

    # Forks a copy of this process and exits. First a screen message is 
    # written to the user, then STDERR is redirected to run_recipe.screen
    # in the working directory. Then exit.

    my ( $rcp,    # Recipe
        ) = @_;

    # Returns nothing.

    my ( $name, @msgs );

    $name = &File::Basename::basename( $0 ) .".screen";

    push @msgs, ["SUCCESS", qq (The job was sent to the background and should be running.) ];
    push @msgs, ["WARNING", qq (Do not re-submit with the same output prefix until finished.) ];
    
    push @msgs, ["", ""];
    push @msgs, ["ADVICE", qq (Screen progress messages are in $name.) ];
    push @msgs, ["ADVICE", qq (Progress can be followed with "cat $name".) ];
    push @msgs, ["ADVICE", qq (The command "top" shows computer load (q key exits).) ];

    push @msgs, ["", ""];
    push @msgs, ["ADVICE", qq (It is safe to log off now.) ];

    &echo_messages( \@msgs );

    open STDERR, ">> $name";

    fork and exit;

    return;
}

1;

__END__

        
