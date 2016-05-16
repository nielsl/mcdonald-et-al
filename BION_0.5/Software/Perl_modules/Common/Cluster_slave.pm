package Common::Cluster_slave;     #  -*- perl -*-

# A no-dependency module that is copied to the cluster slave accounts during
# install of the SSH-cluster. The functions support the sclu_* scripts.

use strict;
use warnings FATAL => qw ( all );

use File::Basename;
use Data::Dumper;

use Common::Config;
use Common::Messages;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &check_runargs
                 &commify_number
                 &find_children
                 &find_files
                 &format_time
                 &free_space
                 &kill_procs
                 &list_capacity
                 &list_jobs
                 &list_load
                 &process_info
                 &program_paths
                 &read_file
                 &read_pid
                 &sum_sizes
);

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_runargs
{
    # Niels Larsen, February 2009.

    # Checks arguments and resolves input and data paths to list of files.
    # Returns ( input files, data files ).

    my ( $args,
        ) = @_;

    my ( @msgs, $key, @inputs, @datasets );

    # Check all arguments are given,

    @msgs = ();
    
    foreach $key ( keys %{ $args } )
    {
        if ( not defined $args->{ $key } )
        {
            push @msgs, qq (Argument "$key" is missing);
        }
    }
    
    if ( @msgs )
    {
        print STDERR join "\n", @msgs;
        print STDERR "\n";
        exit;
    }

    # Check program,
    
    if ( not -x $args->{"program"} )
    {
        print STDERR qq (Program "$args->{'program'}" is not executable\n);
        exit;
    }

    # List and check input files,

    @inputs = &Common::Cluster_slave::find_files( $args->{"input"}, \@msgs );
    
    if ( @msgs )
    {
        print STDERR join "\n", @msgs;
        print STDERR "\n";
        exit;
    }
    
    # List and check data files,

    if ( $args->{"dataset"} )
    {
        @datasets = &Common::Cluster_slave::find_files( $args->{"dataset"}, \@msgs );
        
        if ( @msgs )
        {
            print STDERR join "\n", @msgs;
            print STDERR "\n";
            exit;
        }
    }

    # Output,

    if ( -e $args->{"output"} )
    {
        print STDERR qq (Output path "$args->{'output'}" exists);
        exit;
    }

    return ( \@inputs, \@datasets );
}

sub commify_number
{
    # Niels Larsen, March 2003.

    # Inserts commas into an integer.

    my ( $int,     # Integer or integer string. 
         ) = @_;

    # Returns a string.

    $int = reverse "$int";
    $int =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    
    return scalar reverse $int;
}

sub find_children
{
    # Niels Larsen, February 2009.

    # Finds all children of a given process id. Returns a list of 
    # children process ids.

    my ( $pid,
        ) = @_;

    # Returns a list.

    my ( $os_name, $cmd, @lines, $line, $cpid, $ppid, @pids );

    while ( @lines = `ps ax -o pid,ppid | grep $pid\$` )
    {
        foreach $line ( @lines )
        {
            next if $line !~ /^\s*\d/;

            chomp $line;
            ( $cpid, $ppid ) = split " ", $line;
            
            if ( $ppid == $pid )
            {
                push @pids, $cpid;
                push @pids, &Common::Cluster_slave::find_children( $cpid );
            }
        }

	if ( defined $cpid ) {
	    $pid = $cpid;
	} else {
	    last;
	}
    }

    return wantarray ? @pids : \@pids;
}

sub find_files
{
    # Niels Larsen, February 2009.

    # Lists the files that match the given path expression. Shell syntax
    # should be ok, but must work on all slaves. The path is expanded to 
    # all non-empty regular files. If a directory is given all regular 
    # non-empty files therein are returned. Returns a list of unambiguous
    # paths that are relative to the current working directory.

    my ( $path,   # Path expression
         $msgs,   # Outgoing messages
        ) = @_;

    # Returns a list.

    my ( @path, @files, $file, $expr, $dir );

    $expr = &File::Basename::basename( $path );
    $dir = &File::Basename::dirname( $path );

    if ( -e $path )
    {
        if ( -f $path )
        {
            push @files, $path;
        }
        elsif ( -d $path )
        {
            @files = `find $path -maxdepth 1 -print 2>&1`;
            $? and die "@files $!";
        }
        else {
            push @{ $msgs }, qq (Not a regular file or directory: "$path");
        }
    }
    else
    {
        @files = `find $dir -name "$expr" -maxdepth 1 -print 2>&1`;
        $? and die "@files $!";
    }

    chomp @files;

    if ( @files )
    {
        @files = grep { -f $_ and -s $_ } @files;
    }
    else {
        push @{ $msgs }, qq (No files found for "$path");
    }

    return wantarray ? @files : \@files;
}

sub format_time
{
    # Niels Larsen, March 2009.

    # Formats a given number of seconds like this,
    #
    # 21:36:19
    # 90 00:32:46
    # 

    my ( $secs,
        ) = @_;

    # Returns a string. 

    my ( @str, $str, $unit );

    foreach $unit ( 60, 60, 24 )
    {
        unshift @str, sprintf "%02i", ( $secs % $unit );

        $secs = int ($secs / $unit);

        last if $secs == 0;
    }

    $str = join ":", @str;

    if ( $secs > 0 ) {
        $str = "$secs $str";
    }

    $str =~ s/^0*//;
    $str = 1 if not $str;

    return $str;
}

sub free_space
{
    # Niels Larsen, February 2009.

    my ( $dir,
        ) = @_;

    my ( @diout, $maxlen, $homedir, $space, $part, $mount, $len );

    @diout = map { [ split " ", $_ ] } split "\n", `di -d g -l -n -f fM`;

    $homedir = $ENV{"HOME"};

    $maxlen = 0;

    foreach $part ( @diout )
    {
        $mount = $part->[1];

        if ( $homedir =~ m|^$mount| )
        {
            $len = length $&;
            
            if ( $len > $maxlen )
            {
                $space = $part->[0];
                $maxlen = $len;
            }
        }
    }

    return $space;
}

sub kill_procs
{
    my ( $pid,
        ) = @_;

    my ( @pids, @stats );

    @pids = ( $pid, &Common::Cluster_slave::find_children( $pid ) );

    foreach $pid ( @pids )
    {
        if ( system( "kill $pid" ) ) {
            push @stats, [ $pid, 0, "$!" ];
        } else {
            push @stats, [ $pid, 1, "" ];
        }
    }

    return wantarray ? @stats : \@stats;
}
    
sub list_capacity
{
    my ( $bin_dir,
        ) = @_;

    my ( $os_name, $cpu_cores, $info, $cpu_ghz, $mem_gb, $disk_gb, $space,
         @fields );

    $os_name = `uname`;
    chomp $os_name;

    if ( $os_name =~ /Linux/i )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LINUX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        $info = `cat /proc/cpuinfo`;
        
        if ( $info =~ /\nmodel name\s+:.+?([\d\.]+)GHz/si ) {
            $cpu_ghz = $1;
        } else {
            $cpu_ghz = "---";
        }        
        
        if ( $info =~ /cpu cores\s+:\s*(\d+)/si ) {
            $cpu_cores = $1;
        } else {
            $cpu_cores = "---";
        }
        
        $info = `cat /proc/meminfo`;
        
        if ( $info =~ /MemTotal\s*:\s*(\d+)/ ) {
            $mem_gb = ( sprintf "%.1f", $1 / 1000000 ) ." Gb";
        } else {
            $mem_gb = "---";
        }
        
        if ( $space = &Common::Cluster_slave::free_space( $bin_dir ) ) {
            $disk_gb = "$space Gb";
        } else {
            $disk_gb = "---";
        }
    }
    elsif ( $os_name =~ /Darwin/i )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> MAC <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        $os_name = "Mac OSX";
        
        $info = `system_profiler -detailLevel mini`;
        
        if ( $info =~ /Processor Speed\s*:\s*([\d\.]+)/si ) {
            $cpu_ghz = ( sprintf "%.1f", $1 ) ." Ghz";
        } else {
            $cpu_ghz = "---";
        }        
        
        if ( $info =~ /Total Number Of Cores\s*:\s*(\d+)/si ) {
            $cpu_cores = $1;
        } else {
            $cpu_cores = "---";
        }
        
        if ( $info =~ /\s+Memory:\s*(\d+)/ ) {
            $mem_gb = ( sprintf "%.1f", $1 ) ." Gb";
        } else {
            $mem_gb = "---";
        }
        
        if ( $space = &Common::Cluster_slave::free_space( $bin_dir ) ) {
            $disk_gb = "$space Gb";
        } else {
            $disk_gb = "---";
        }
    }

    @fields = ( $os_name, $cpu_ghz, $cpu_cores, $mem_gb, $disk_gb );

    return wantarray ? @fields : \@fields;
}

sub list_load
{
    # Niels Larsen, March 2009.

    # Summarizes the CPU and RAM consumption of all CPU-consuming processes,
    # except the current one and its children. The ps command is used which 
    # should exist in some form on nearly all unix-like machines.

    # Returns a list.

    my ( $os_name, $cmd, %pids, @list, @lines, $line, @line, $pid );

    # Create ps command,

    $os_name = `uname`;
    chomp $os_name;

    if ( $os_name =~ /^Linux$/i )
    {
        #                  0   1    2     3    4       5     6
        $cmd = "ps -ax -o pid,user,pcpu,pmem,majflt,cputime,command";
    }
    elsif ( $os_name =~ /^Darwin$/i )
    {
        $cmd = "ps -ax -o pid,user,pcpu,pmem,majflt,cputime,command";
    }        
    else {
        die qq (Wrong looking operating system -> "$os_name");
    }
    
    # Find pids associated with this perl,

    %pids = map { $_, 1 } &Common::Cluster_slave::find_children( $$ );
    $pids{ $$ } = 1;

    # Output from ps,

    @lines = split "\n", `$cmd 2>&1`;
    $? and die "@lines $!";

    # Get lines that start with numbers (process ids),

    @lines = grep { $_ =~ /^\s*\d/ } @lines;

    if ( not @lines ) {
        print STDERR qq (No processes returned) and exit;
    }

    chomp @lines;

    # Keep that lines that have CPU pct > 0,

    foreach $line ( @lines )
    {
        @line = split " ", $line;

        $pid = $line[0];

        if ( not $pids{ $pid } and $line[2] > 0 )
        {
            $line[6] =~ s/\W+$//;

            if ( $line[6] ne "sshd" ) 
            {
                $line[4] = $line[4] eq "-" ? 0 : $line[4];
                $line[4] = &Common::Cluster_slave::commify_number( $line[4] );
                $line[5] =~ s/[\.\:]\d+$//;
                
                push @list, [ $os_name, @line[1...6] ];
            }
        }
    }

    if ( @list )
    {
        @list = sort { $b->[2] <=> $a->[2] } @list;
    }
    else {
        @list = [ $os_name, (" - ") x 6 ];
    }

    return wantarray ? @list : \@list;
}

sub list_jobs
{
    # Niels Larsen, March 2009.

    # Lists jobs. 

    my ( $dirpath,
         $fields,
        ) = @_;

    my ( $path, $job_id, %info, $pid, $begsecs, $endsecs, $key, $size, %fields, $field, 
         %pinfo, $all_fields, %all_fields, @fields, $program, @job_paths, @list );

    $all_fields = "jobid,status,program,outsize,time,cpu,pcpu,pmem,swap";
    %all_fields = map { $_, 1 } split ",", $all_fields;

    if ( not $fields ) {
        $fields = $all_fields;
    }

    foreach $field ( split ",", $fields )
    {
        if ( exists $all_fields{ $field } ) {
            $fields{ $field } = 1;
        } else {
            die qq (Wrong looking field -> "$field");
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not opendir DIR, $dirpath )
    {
        return wantarray ? @list : \@list;
    }

    while ( defined ( $job_id = readdir DIR ) )
    {
        next if $job_id =~ /^\./;
        
        $path = "$dirpath/$job_id";
        
        if ( -d $path ) {
            push @job_paths, "$path";
        }
    }
    
    close DIR;
    
    foreach $path ( @job_paths )
    {
        $job_id = &File::Basename::basename( $path );
        
        %info = ( "jobid" => $job_id );
        
        if ( -r "$path/pid" )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SOME PROBLEM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            
            # PID file exists. If the saved parent process, or any of its children,
            # are in the process table, then it is running. If not that means the 
            # job has died and there may then be a message in the error file,
            
            if ( -s "$path/pid" ) {
                $pid = ( &Common::Cluster_slave::read_file( "$path/pid" ) )[0];
                chomp $pid;
            }
            
            if ( $pid and %pinfo = &Common::Cluster_slave::process_info( $pid ) )
            {
                foreach $key ( keys %pinfo ) {
                    $info{ $key } = $pinfo{ $key };
                }
                
                $info{"status"} = "Running";
                $endsecs = `date +%s`; 
                chomp $endsecs;
            }
            else
            {
                if ( -s "$path/errors" )
                {
                    $info{"status"} = "Error";
                    $info{"message"} = &Common::Cluster_slave::read_file( "$path/errors" );
                }
                else {
                    $info{"status"} = "Unknown";
                }
                
                if ( -r "$path/endsecs" and -s "$path/endsecs" ) {
                    $endsecs = ( &Common::Cluster_slave::read_file( "$path/endsecs" ) )[0];
                    chomp $endsecs;
                } else {
                    $endsecs = undef;
                }
            }
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> NORMAL COMPLETION <<<<<<<<<<<<<<<<<<<<<<<<
            
            $info{"status"} = "Done";
            
            if ( -r "$path/endsecs" and -s "$path/endsecs" ) {
                $endsecs = ( &Common::Cluster_slave::read_file( "$path/endsecs" ) )[0];
                chomp $endsecs;
            } else {
                $endsecs = undef;
            }
        }
        
        if ( -r "$path/program" and -s "$path/program" )
        {
            $program = ( &Common::Cluster_slave::read_file( "$path/program" ) )[0];
            chomp $program;
            $info{"program"} = $program;
        }
        
        if ( $size = &Common::Cluster_slave::sum_sizes( "$path/output" ) ) {
            $info{"outsize"} = &Common::Cluster_slave::commify_number( $size );
        } else {
            $info{"outsize"} = " ";
        }
        
        # When job was started, in epoch seconds,
        
        if ( -r "$path/begsecs" and -s "$path/begsecs" ) {
            $begsecs = ( &Common::Cluster_slave::read_file( "$path/begsecs" ) )[0];
            chomp $begsecs;
        } else {
            $begsecs = undef;
        }
        
        if ( defined $begsecs and defined $endsecs ) {
            $info{"time"} = &Common::Cluster_slave::format_time( $endsecs - $begsecs );
        }
        
        push @list, { %info };
    }

    return wantarray ? @list : \@list;
}

sub process_info
{
    # Niels Larsen, February 2009.

    # Returns a hash with CPU, CPU percent, RAM percent and swap information
    # for a given process id. All children are included and summed up. If no
    # processes match, nothing is returned. 

    my ( $pid,
        ) = @_;

    # Returns hash or nothing.

    my ( $os_name, $cmd, @lines, $line, $lines, %info, @cputime, $cputime,
         $pcpu, $pmem, $majflt, $minflt, %pids, @pids );

    # Create ps command,

    $os_name = `uname`;
    chomp $os_name;
    
    if ( $os_name =~ /^Linux|Darwin$/i )
    {
        $cmd = "ps -o pid,cputime,pcpu,pmem,majflt";
    }
    else {
        die qq (Wrong looking operating system -> "$os_name");
    }

    # Make a list of the given process id and all its children,

    %pids = map { $_, 1 } &Common::Cluster_slave::find_children( $pid );
    @pids = sort { $a <=> $b } keys %pids;

    unshift @pids, $pid;
    
    # For each process, sum up statistics,
    
    $cmd .= " -p ". join ",", @pids;
    
    @lines = split "\n", `$cmd`;
    @lines = grep { $_ =~ /^\s*\d/ } @lines;

    # Return if no lines match,

    return if not @lines;

    # Sum up statistics,

    chomp @lines;

    %info = (
        "cpu" => 0,
        "pcpu" => 0,
        "pmem" => 0,
        "swap" => 0,
        );

    foreach $line ( @lines )
    {
        ( $pid, $cputime, $pcpu, $pmem, $majflt ) = split " ", $line;

        @cputime = split /[.:]/, $cputime;
        
        if ( scalar @cputime != 3 ) {
            die qq (Wrong looking cputime string -> "$cputime");
        }
        
        $info{"cpu"} += 3600 * $cputime[0] + 60 * $cputime[1] + $cputime[2];
        $info{"pcpu"} += $pcpu;
        $info{"pmem"} += $pmem;
        $info{"swap"} += $majflt eq "-" ? 0 : $majflt;
    }
        
    $info{"pcpu"} = int $info{"pcpu"};
    $info{"pmem"} = int $info{"pmem"};

    $info{"swap"} = &Common::Cluster_slave::commify_number( $info{"swap"} );

    return wantarray ? %info : \%info;
}

sub program_paths
{
    # Niels Larsen, February 2009.

    # Creates a command template and a list of input and optionally datafiles.
    # The command format depends on the application, so this routine must be 
    # edited when new applications are added. 

    my ( $args,
        ) = @_;

    # Returns a string. 

    my ( $program, $params, $input, $output, $dataset, $command, $inputs, 
         $datasets );

    $program = $args->{"program"};
    
    if ( defined $args->{"parameters"} ) {
        $params = $args->{"parameters"};
    } else {
        $params = "";
    }

    $input = $args->{"input"};
    $dataset = $args->{"dataset"};
    $output = $args->{"output"};

    if ( $program =~ m|/patscan$| )
    {
        $command = "$program $params __INPUT__ < __DATASET__ > __OUTPUT__";

        ( $inputs, $datasets ) = &Common::Cluster_slave::check_runargs(
            {
                "program" => $program,
                "parameters" => $params,
                "input" => $input,
                "dataset" => $dataset,
                "output" => $output,
            });
    }
    elsif ( $program =~ m|/[np]simscan$| )
    { 
        $command = "$program $params __INPUT__ __DATASET__ __OUTPUT__";
        
        ( $inputs, $datasets ) = &Common::Cluster_slave::check_runargs(
            {
                "program" => $program,
                "parameters" => $params,
                "input" => $input,
                "dataset" => $dataset,
                "output" => $output,
            });
    }
    else {
        die qq (Unsupported program: "$program"\n);
    }

    return ( $command, $inputs, $datasets );
}

sub read_file
{
    my ( $path,
        ) = @_;

    my ( @lines, $line );

    if ( open FILE, $path )
    {
        while ( defined ( $line = <FILE> ) )
        {
            push @lines, $line;
        }
    }
    else {
        die qq (Could not read-open file -> "$path");
    }

    return wantarray ? @lines : \@lines;
}

sub read_pid
{
    my ( $path,
        ) = @_;

    my ( $line );

    if ( open FILE, $path )
    {
        $line = <FILE>;
        chomp $line;
    }
    else {
        die qq (Could not read-open file -> "$path");
    }

    return $line;
}

sub sum_sizes
{
    my ( $path,
        ) = @_;

    my ( $file, $sum );

    if ( -r $path )
    {
        if ( -d $path )
        {
            opendir DIR, $path or die qq (Could not read-open directory: $path);

            $sum = 0;

            while ( defined ( $file = readdir DIR ) )
            {
                next if $file =~ /^\./;
                $sum += -s "$path/$file";
            }

            closedir DIR;
        }
        else {
            $sum += -s $path;
        }
    }
    else {
        $sum = 0;
    }

    return $sum;
}

1;

__END__
