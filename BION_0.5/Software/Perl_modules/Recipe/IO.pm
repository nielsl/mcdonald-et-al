package Recipe::IO;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Recipes are structured files of keys and values, in a format that is easy 
# to read and write for both human and computer. The command 
#
# run_recipe --example
#
# will print an example. Recipes have several benefits:
#
# 1. Users can edit them to their needs and let them stay near the data they
#    apply to. That way analyses can be easily rerun by just entering a data
#    directory and just type 'run_recipe recipe.file'.
#
# 2. Only parameters are included in the recipe that make sense adjusting in
#    a given analysis. Then users will not be overwhelmed by command line 
#    arguments.
#
# 3. Programs invoked by recipes can change parameters without breaking the 
#    recipe. Programs can even be replaced entirely, if a better open-source 
#    appears for the job.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use feature "state";

use vars qw ( @EXPORT_OK );
require Exporter;

use Tie::IxHash;

@EXPORT_OK = qw (
                 &create_dir
                 &create_dir_if_not_exists
                 &delete_dir
                 &delete_dir_if_exists
                 &delete_step_logs
                 &delete_outputs
                 &delete_outputs_nokeep
                 &is_recipe_file
                 &list_dirs
                 &list_files
                 &read_recipe
                 &read_recipe_delta
                 &read_recipe_params
                 &read_stats
                 &read_status
                 &write_recipe
                 &write_stats
                 &write_status
                 &zip_some_outputs
);

use Common::Config;
use Common::Messages;
use Common::File;

use Seq::Common;

use Recipe::Steps;
use Recipe::Util;
use Recipe::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Qual_type;

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_dir
{
    # Niels Larsen, March 2013.

    # Creates a directory with an empty .BION_dir file in it. The 
    # corresponding Recipe::IO::delete_dir routine will only delete 
    # directories that have this file. Crashes if directory exists
    # or creation failed. 

    my ( $dir,      # Directory path
        ) = @_;

    # Returns nothing.

    my ( $count );

    if ( not -d $dir )
    {
        &Common::File::create_dir( $dir );
        &Common::File::touch_file( "$dir/.BION_dir" );
    }
    else {
        &error( qq (Directory exists -> "$dir") );
    }

    return;
}

sub create_dir_if_not_exists
{
    # Niels Larsen, March 2013.

    my ( $dir,
        ) = @_;

    if ( not -d $dir )
    {
        &Recipe::IO::create_dir( $dir );
        return 1;
    }

    return;
}

sub delete_dir
{
    # Niels Larsen, March 2013.

    # Deletes a directory recurcively, with all content. As safety,
    # it will only do so if there is a .BION_dir file at the 
    # top level, a file that Recipe::IO::create_dir creates. That 
    # way at least, only directories created by this package can 
    # disappear. Returns number of deleted files and directories.

    my ( $dir,      # Directory path
        ) = @_;

    # Returns integer.

    my ( $count );

    if ( -d $dir )
    {
        if ( -e "$dir/.BION_dir" )
        {
            $count = &Common::File::delete_dir_tree( $dir );
        }
        else {
            &error( qq (Not a BION directory -> "$dir"\n)
                   .qq (There should be a .BION_dir file in it, there is not.) );
        }
    }
    else {
        &error( qq (Directory does not exist -> "$dir") );
    }

    return $count;
}

sub delete_dir_if_exists
{
    # Niels Larsen, March 2013.

    my ( $dir,
        ) = @_;

    my ( $count );

    if ( -d $dir )
    {
        $count = &Recipe::IO::delete_dir( $dir );
        return $count;
    }

    return;
}

sub delete_outputs
{
    # Niels Larsen, May 2012. 

    # Deletes all existing output directories - with all their content - 
    # that will be produced by running the given recipe steps. 

    my ( $rcp,      # Recipe
        ) = @_;

    my ( $beg, $end, $step, $i, $dir, $count );

    $count = 0;

    for ( $i = $rcp->{"begin-step"}; $i <= $rcp->{"end-step"}; $i += 1 )
    {
        $step = $rcp->{"steps"}->[$i];

        if ( -d ( $dir = $step->{"run"}->out_dir ) )
        {
            $count += &Recipe::IO::delete_dir_if_exists( $dir );
        }
    }
     
    return $count;
}

sub delete_outputs_nokeep
{
    # Niels Larsen, March 2013.

    # Deletes the output files for a given recipe where "keep-outputs" is
    # set to "no", from the begin step to the end step. If there are sub-
    # directories, then logs are deleted from those too. Returns the number
    # of files deleted.

    my ( $rcp,    # Recipe 
        ) = @_;

    # Returns integer.

    my ( $i, $step, $fexpr, @files, $count );

    $count = 0;

    for ( $i = $rcp->{"begin-step"}; $i <= $rcp->{"end-step"}; $i += 1 )
    {
        $step = $rcp->{"steps"}->[$i];

        if ( ( $step->{"keep-outputs"} // "" ) eq "no" )
        {
            if ( $fexpr = $step->{"run"}->out_files )
            {
                @files = &Recipe::IO::list_files( $fexpr );
                $count += &Common::File::delete_files_if_exist( \@files );
            }
        }
    }
    
    return $count;
}

sub delete_step_logs
{
    # Niels Larsen, March 2013.

    # Deletes the log directories created by the given recipe, from the 
    # begin step to the end step. If there are sub-directories, then logs
    # are deleted from those too. Returns the total number of files and 
    # directories deleted.

    my ( $rcp,
        ) = @_;

    # Returns integer. 

    my ( $i, $step, $run, $count, @paths, $path );

    $count = 0;

    # $count += &Recipe::IO::delete_dir_if_exists( $rcp->{"log_dir"} );

    for ( $i = $rcp->{"begin-step"}; $i <= $rcp->{"end-step"}; $i += 1 )
    {
        $step = $rcp->{"steps"}->[$i];

        if ( $run = $step->{"run"} )
        {
            @paths = &Recipe::IO::list_dirs( $run->out_dir, 0 );

            if ( @paths ) {
                @paths = &Recipe::IO::list_files( $run->out_dir ."/*/*", 0 );
            } else {
                @paths = &Recipe::IO::list_files( $run->out_dir, 0 );
            }

            @paths = grep { $_ =~ m|/logs$| } @paths;

            foreach $path ( @paths )
            {
                $count += &Recipe::IO::delete_dir_if_exists( $path );
            }
        }
    }
    
    return $count;
}

sub is_recipe_file
{
    # Niels Larsen, February 2012. 

    # Returns 1 if the given file is at most 1 mb and starts and ends with 
    # two symmetrical tags (e.g. <recipe> and </recipe>), otherwise nothing.

    my ( $file,
        ) = @_;
    
    my ( $text );

    if ( -r $file and -s $file <= 1_000_000 )
    {
        $text = ${ &Common::File::read_file( $file ) };
        $text = join "\n", grep { $_ !~ /^#/ } split "\n", $text;

        $text =~ s/^\s*//;
        $text =~ s/\s*$//;

        if ( $text =~ /^<([^>]+)>/ and $text =~ /<\/$1>$/ )
        {
            return 1;
        }
    }

    return;
}

sub list_dirs
{
    # Niels Larsen, April 2013. 

    # Creates a directory list from one or more shell expressions, given as a 
    # list or a string with blanks between expressions. If $fatal is on (on by 
    # default), then the returned file list may not be empty, but not all 
    # expression have to match. Error messages are either display or returned
    # if the $msgs argument is given. 

    my ( $fexps,
         $fatal,
         $msgs,
        ) = @_;

    # Returns a list or nothing.

    my ( @dirs );
    
    if ( @dirs = &Recipe::IO::list_files( $fexps, $fatal, $msgs ) )
    {
        @dirs = grep { $_ !~ m|/logs$| } @dirs;
        @dirs = grep { -d $_ } @dirs;

        if ( @dirs ) {
            return wantarray ? @dirs : \@dirs;
        }
    }
    
    return;
}

sub list_files
{
    # Niels Larsen, March 2012.

    # Creates a file list from one or more shell expressions, given as a list or 
    # a string with blanks between expressions. If $fatal is on (on by default), 
    # then the returned file list may not be empty, but not all expression have 
    # to match. Error messages are either display or returned if the $msgs 
    # argument is given. 

    my ( $fexps,    # File expressions, list or string
         $fatal,    # Fatal flag, OPTIONAL, default 1
         $msgs,     # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list or nothing.

    my ( @files, @msgs, $fexp, @fexps, @tmp, $msg );

    $fatal //= 1;
    
    $fexps = [ $fexps ] if not ref $fexps;

    @tmp = ();

    foreach $fexp ( @{ $fexps } )
    {
        push @tmp, split " ", $fexp;
    }

    foreach $fexp ( @tmp )
    {
        $fexp .= "/*" if -d $fexp;

        push @fexps, $fexp;

        if ( $fexp !~ /\.zip$/ ) {
            push @fexps, $fexp .".zip";
        }
    }

    @files = &Common::File::list_files_shell( \@fexps, \@msgs );

    if ( $fatal and not @files )
    {
        if ( @msgs )
        {
            $msg->{"oops"} = "No inputs found:\n" . ( join "\n", map { $_->[1] } @msgs );

            $msg->{"help"} = 
                  qq (Most likely they are missing because of wrong inputs or\n)
                . qq (or settings. If you suspect it is a software error, then\n)
                . qq (re-run the recipe with --debug and contact us as described\n)
                . qq (by the console message that appears with --debug.);

            &echo("\n\n") if @msgs and not $msgs;
            &Recipe::Messages::oops( $msg );
        }
        else {
            &error( qq (No file listing, yet no error messages) );
        }
    }    

    if ( @files ) {
        return wantarray ? @files : \@files;
    }

    return;
}

sub read_recipe
{
    # Niels Larsen, January 2012.

    # Reads a recipe into a hash structure that mainly looks like this,
    # 
    # $recipe = {
    #    name => string value
    #    key => string value,
    #     .. =>     ....,
    #    "steps" => [
    #         step node hash,
    #              ...,
    #    ],
    #    "run" => {
    #          key => string value,
    #           .. =>    ....,
    #    }
    #  }
    # 
    # Steps have the same shape, and it is a recursive structure. The input
    # step order is preserved, so the execution of each step follows their
    # order in the recipe file. Recipe keys and values are checked against 
    # those defined in Recipe::Steps. Any key name is ok, but "name", "steps"
    # and "run" are mandatory. The "run" hash gets passed to routines and 
    # may change during execution. Step names are given version numbers, so
    # if for example "sequence-cleaning" occurs twice, the first would be 
    # named "sequence-cleaning.1" and the second "sequence-cleaning.2". A
    # delta file is given with lines that should overwrite matching ones 
    # in the recipe. Returns a hash.

    my ( $file,   # Input file
         $args,   # Arguments hash
         $msgs,   # Outgoing messages
        ) = @_;

    # Returns a hash. 

    my ( @lines, $rcp, @msgs, $rdir, $edits, $step, $seen, $dfile, $check,
         $msg );

    $args //= {};

    $dfile = $args->{"delta"};
    $check = $args->{"check"} // 1;

    if ( -r $file ) 
    {
        @lines = split "\n", ${ &Common::File::read_file( $file ) };
    }
    else
    {
        $msg->{"oops"} = qq (No such recipe file:\n$file\n);
        &Recipe::Messages::oops( $msg );
    }

    if ( @lines )
    {
        # Skip blank lines and comment lines,

        @lines  = grep { $_ =~ /\w/ and $_ !~ /^\s*(#|<!--)/ } @lines;

        # Parse lines to a recipe structure. The step names have version
        # numbers at all levels, so recipe authors may address them,

        $seen = {};
        $rcp = &Recipe::Util::parse_recipe( \@lines, $seen, $msgs );

        # Apply delta file if given,

        if ( $dfile )
        {
            $edits = &Recipe::IO::read_recipe_delta( $dfile, $msgs );
            &Recipe::Util::edit_recipe_list( $rcp, $edits );
        }
        
        $file = &Common::File::full_file_path( $file );
        $rdir = &File::Basename::dirname( $file );
        
        if ( ref $rcp eq "ARRAY" ) {
            map { $_->{"file"} = $file } @{ $rcp };
        } else {
            $rcp->{"file"} = $file;
        }

        if ( $check )
        {
            &Recipe::Util::check_params( $rcp, $rdir, $msgs );
        }

        # Make objects of the run-time configuration hashes, so there is
        # crash when a missing field is used,
        
        if ( ref $rcp eq "ARRAY" ) {            
            return wantarray ? @{ $rcp } : $rcp;
        } else {
            return wantarray ? %{ $rcp } : $rcp;
        }
    }
    else 
    {
        push @msgs, ["ERROR", qq (Recipe file has no lines -> "$file") ];
        &append_or_exit( \@msgs, $msgs );
    }

    return;
}

sub read_stats
{
    # Niels Larsen, March 2012.

    # Reads a statistics file into a structure where order is preserved.

    my ( $file,
         $msgs,
        ) = @_;

    # Returns hash or array. 

    my ( @lines, $stats, @msgs, $rdir );

    @lines = split "\n", ${ &Common::File::read_file( $file ) };

    if ( @lines )
    {
        $stats = &Recipe::Util::parse_stats( \@lines, $msgs );

        return wantarray ? @{ $stats } : $stats;
    }
    else
    {
        &error( qq (Statistics file is empty -> "$file"\n)
               .qq (Programming error. Maybe it did not parse.) );
    }
    
    return;
}

sub read_status
{
    # Niels Larsen, May 2013.

    my ( $file,
        ) = @_;

    my ( $stat );

    $stat = &Common::File::eval_file( $file );

    if ( $stat->{"date"} )
    {
        if ( $stat->{"date"} =~ /(\d+:\d+:\d+)/ ) {
            $stat->{"hour"} = $1;
        } else {
            &error( qq (Wrong looking date -> "$stat->{'date'}" ) );
        }
    }

    return wantarray ? %{ $stat } : $stat;
}

sub read_recipe_delta
{
    # Niels Larsen, February 2013.

    # Reads a file with keys and values that can be inserted into recipe 
    # templates and replace what is there. Same format is used as in recipes
    # themselves (see Recipe::Util::parse_recipe) but a step name can 
    # also be used as a prefix. These examples are valid lines,
    # 
    #  some-key = some-value
    #  some-key =~ some-regex
    #  some-step: some-key = some-value
    #  some-step: some-key =~ some-regex
    #
    # Returned is a list of hashes, each with the fields "step", "key" and 
    # either "value" or "regex".

    my ( $file,
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $fh, $line, @list, $step_regex, $key_regex, $oper, @msgs, $key, 
         $step, $value );

    $step_regex = '\s*([a-z-]+(?:\.\d+)?)\s*:\s*([a-z0-9-]+)\s*(=~?)\s*(.+)';
    $key_regex = '\s*([a-z0-9-]+)\s*(=~?)\s*(.+)';

    $fh = &Common::File::get_read_handle( $file );

    while ( defined ( $line = <$fh> ) )
    {
        chomp $line;

        next if $line =~ /^\s*#/;
        next if $line !~ /\w/;
        
        if ( $line =~ /^$step_regex$/ )
        {
            $step = $1;
            $key = $2;
            $oper = $3;
            $value = $4;
            $value =~ s/\s*$//;

            if ( $oper eq "=" ) {
                push @list, { "step" => $step, "key" => $key, "value" => $value };
            } elsif ( $oper eq "=~" ) {
                push @list, { "step" => $step, "key" => $key, "regex" => $value };
            } else {
                push @msgs, ["ERROR", qq (Wrong looking "$oper" in delta line -> "$line") ];
            }
        }
        elsif ( $line =~ /^$key_regex$/ )
        {
            $key = $1;
            $oper = $2;
            $value = $3;
            $value =~ s/\s*$//;

            if ( $oper eq "=" ) {
                push @list, { "step" => "", "key" => $key, "value" => $value };
            } elsif ( $oper eq "=~" ) {
                push @list, { "step" => "", "key" => $key, "regex" => $value };
            } else {
                push @msgs, ["ERROR", qq (Wrong looking "$oper" in delta line -> "$line") ];
            }
        }
        else
        {
            push @msgs, ["ERROR", qq (Wrong looking line -> "$line") ];
        }
    }

    &Common::File::close_handle( $fh );

    if ( @msgs )
    {
        push @msgs, ["INFO", qq (Lines must have one of these forms:) ];
        push @msgs, ["INFO", qq (   some-step: some-key = some-value) ];
        push @msgs, ["INFO", qq (   some-step: some-key =~ some-regex) ];
        push @msgs, ["INFO", qq (   some-key = some-value) ];
        push @msgs, ["INFO", qq (   some-key =~ some-regex) ];
    }            

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @list : \@list;
}

sub read_recipe_params
{
    # Niels Larsen, January 2012.

    # Reads and checks a file in recipe format. Returns routine 
    # parameters.

    my ( $file,
         $msgs,
        ) = @_;

    # Returns a hash. 

    my ( $rcp, $params );

    $rcp = &Recipe::IO::read_recipe( $file, undef, $msgs );

    $params = &Recipe::Util::check_params( $rcp, $msgs );

    return $params;
}

sub write_recipe
{
    # Niels Larsen, Janary 2012.

    # Writes a nested recipe file from a given recipe, which can be nested
    # to any depth. See the BION/Recipes directory for format examples. 

    my ( $file,
         $recipe,
         $indent,
        ) = @_;

    # Returns nothing.
    
    my ( $fh, $blanks, $blanks4, $name, $key, $step );

    if ( ref $file ) {
        $fh = $file;
    } else {
        $fh = &Common::File::get_write_handle( $file );
    }

    $indent //= 0;

    $blanks = " " x $indent;
    $blanks4 = " " x ( $indent + 4 );

    if ( ref $recipe eq "ARRAY" )
    {
        # List of steps,

        foreach $step ( @{ $recipe } )
        {
            &Recipe::IO::write_recipe( $fh, $step, $indent );
        }
    }
    else
    {
        # Single step,

        $name = $recipe->{"name"};

        $fh->print( "$blanks<$name>\n" );
    
        foreach $key ( sort keys %{ $recipe } )
        {
            if ( $key eq "steps" )
            {
                &Recipe::IO::write_recipe( $fh, $recipe->{"steps"}, $indent + 4 );
            }
            elsif ( $key ne "name" and $key ne "run" and defined $recipe->{ $key } )
            {
                $fh->print( "$blanks4$key = $recipe->{ $key }\n" );
            }
        }

        $fh->print( "$blanks</$name>\n" );
    }

    &Common::File::close_handle( $fh ) unless ref $file;

    return;
}

sub write_stats
{
    my ( $file,
         $stats,
         $clobber,
        ) = @_;

    my ( $text );

    $clobber //= 1;

    $text = &Recipe::Util::format_stats( $stats );
    &Common::File::write_file( $file, $text, $clobber );
    
    return;
}

sub write_status
{
    # Niels Larsen, May 2013. 

    # Rewrites the given file with the key/value pairs given. The file
    # may exists and then the given pairs overwrite existing pairs. 

    my ( $file,
         %args,
        ) = @_;

    # Returns nothing. 

    my ( $stat, $key );

    if ( -e $file ) {
        $stat = &Recipe::IO::read_status( $file );
    } else {
        $stat = {};
    }

    foreach $key ( keys %args )
    {
        $stat->{ $key } = $args{ $key };
    }

    &Common::File::dump_file( $file, $stat, 1 );

    return;
}

sub zip_some_outputs
{
    # Niels Larsen, March 2013.

    # Zip-compresses the output files for a given recipe, but only 
    # for the steps where "zip-outputs" is set to "yes". Returns the 
    # number of files zipped.

    my ( $rcp,    # Recipe 
        ) = @_;

    # Returns integer.

    my ( $i, $step, $run, @files, $count );

    $count = 0;

    for ( $i = $rcp->{"begin-step"}; $i <= $rcp->{"end-step"}; $i += 1 )
    {
        $step = $rcp->{"steps"}->[$i];

        if ( ( $step->{"zip-outputs"} // "" ) eq "yes" )
        {
            $run = $step->{"run"};

            if ( $run->out_files )
            {
                @files = &Recipe::IO::list_files( $run->out_files, 0 );

                @files = grep { $_ !~ /\.stats$/ } @files;
                @files = grep { $_ !~ /\.stats\.html$/ } @files;

                if ( @files ) {
                    $count += &Common::File::zip_files_single( \@files );
                }
            }

            # @files = &Recipe::IO::list_files( $run->out_dir ."/NO_*" );
            # $count += &Common::File::zip_files_single( \@files );
        }
    }
    
    return $count;
}

1;

__END__
