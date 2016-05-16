package Common::Batch;     #  -*- perl -*-

# Functions that manage batch jobs. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_queue_if_not_exists
                 &daemon
                 &delete_user_jobs
                 &delete_queue_pid_if_exists
                 &delete_submitted_job
                 &get_job
                 &get_job_ids
                 &get_jobs
                 &highest_job_id
                 &jobs_ahead
                 &jobs_all_finished
                 &jobs_completed
                 &jobs_pending
                 &jobs_running
                 &kill_process
                 &list_queue
                 &queue_exists
                 &queue_is_started
                 &queue_is_running
                 &read_pid
                 &submit_job
                 &table_keys
                 &write_pid
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;
use Common::DB;
use Common::States;

use Registry::Schema;
use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> QUEUE NAME <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Def_queue = "batch_queue";
our $DB_master = $Common::Config::db_master;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_queue_if_not_exists
{
    # Niels Larsen, August 2003.

    # Creates a given queue database table if it does not exist.

    my ( $dbh,
         $queue,      # Database table name
         ) = @_;
    
    # Returns nothing.

    my ( $table );

    $queue = $Def_queue if not defined $queue;

    $dbh = &Common::DB::connect( $DB_master ) if not defined $dbh;

    &Common::File::create_dir_if_not_exists( $Common::Config::adm_dir );
    &Common::File::create_dir_if_not_exists( $Common::Config::bat_dir );

    if ( not &Common::DB::table_exists( $dbh, $queue ) )
    {
        $table = Registry::Schema->get( "system" )->table( $queue );
        &Common::DB::create_table( $dbh, $table );
    }
    
    &Common::DB::disconnect( $dbh );

    return;
}

sub daemon
{
    # Niels Larsen, December 2005.

    # Looks in the batch queue and runs the oldest job if there are any.
    # This routine never exits, but is started and stopped by the routines
    # Common::Admin::start_queue and Common::Admin::stop_queue. They write
    # and read a process ID file, and starts and stops this routine 
    # safely. 

    my ( $queue,     # Queue name
         $jobid,     # Job id
         ) = @_;

    # Returns nothing. 
    
    require Proc::ProcessTable;

    my ( $proc, $pid, $status, $jid, $sql, $command, $code, $dbh, $job_dir,
         $requests, $message, $beg_date, $beg_time, $end_date, $jobs, $sub_time,
         $end_time, $sid, $stderr, $stdout, $msgs, $table, $proch, $state, $id );

    # >>>>>>>>>>>>>>>>>>>>>> ERRORS AND WARNINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    require Proc::Simple;

    $queue = $Def_queue if not defined $queue;
    
    $dbh = &Common::DB::connect( $DB_master );

    local $Common::Config::with_console_messages = 1;
    local $Common::Config::with_errors_dumped = 1;

    while ( $dbh->ping )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>> FINISHED JOBS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # If $proc is defined a job has finished within the last n seconds.
        # Then we get its exit status and the current date and time and 
        # record them,

        if ( $proc )
        {
            if ( $proc->poll() ) {
                sleep 2;
            }
            else
            {
                if ( not $dbh->ping ) {
                    &Common::DB::disconnect( $dbh );
                    exit;
                }

                $stdout = "";
                $stderr = "";
                $status = "";
                $message = "";
                $msgs = {};

                if ( -s "$job_dir/STDOUT" )
                {
                    if ( not $stdout = &Common::File::eval_file( "$job_dir/STDOUT", 0 ) ) {
                        $stdout->{"TITLE"} = qq (Wrong looking output in -> "$job_dir/STDOUT");
                    }

                    $status = "aborted";
                    $message = $stdout->{"TITLE"};
                }

                if ( -s "$job_dir/STDERR" )
                {
                    if ( not $stderr = &Common::File::eval_file( "$job_dir/STDERR", 0 ) ) {
                        $stderr = qq (Wrong looking error message in -> "$job_dir/STDERR");
                    }

                    $status = "aborted";
                    $message = $stdout->{"TITLE"};
                }

                if ( $code = $proc->exit_status )
                {
                    $msgs->{"exit_code"} = $code;
                    $msgs->{"exit_status"} = $!;
                    $status = "aborted";
                    $message = "Aborted";
                }
                
                if ( $dbh->ping )
                {
                    $status ||= "completed";
                    $message ||= "completed";
                    $message = quotemeta $message;

                    $end_time = &Common::Util::time_string_to_epoch();

                    $sql = qq (update $queue set status="$status", message="$message",)
                         . qq ( end_time = $end_time where id = $jid);

                    &Common::DB::request( $dbh, $sql );

                    if ( $msgs and ( $stdout or $stderr ) )
                    {
                        $stdout->{"SESSION_ID"} = $sid;

                        $msgs->{"stdout"} = $stdout;
                        $msgs->{"stderr"} = $stderr;

                        &Common::File::dump_file( "$job_dir/$jid.messages", $msgs );
                    }

                    # Set job icon to aborted or completed,

                    &Common::States::save_job_status( $sid, $status );
                } 
                else {
                    &Common::DB::disconnect( $dbh );
                    exit;
                }

                undef $proc;

                &Common::File::delete_file_if_exists( "$job_dir/STDOUT" );
                &Common::File::delete_file_if_exists( "$job_dir/STDERR" );
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> LAUNCH NEW JOB <<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        # If no jobs are currently running, take the oldest of the pending 
        # requests (if any) and launch it,

        if ( not $proc )
        {
            if ( $dbh->ping ) 
            {
                $sql = qq (select id,sid,command,sub_time from $queue where status = "pending")
                     . qq ( order by sub_time asc);
            
                $requests = &Common::DB::query_array( $dbh, $sql );
            } 
            else {
                &Common::DB::disconnect( $dbh );
                exit;
            }
            
            if ( @{ $requests } )
            {
                $proc = Proc::Simple->new();

                ( $jid, $sid, $command, $sub_time ) = @{ $requests->[0] };

                $job_dir = "$Common::Config::ses_dir/$sid/Analyses";

                $proc->redirect_output ( "$job_dir/STDOUT", "$job_dir/STDERR" );

                $proc->start( $command );
                $proc->kill_on_destroy( 1 );

                $pid = $proc->pid;
                $beg_time = &Common::Util::time_string_to_epoch();

                if ( $dbh->ping ) 
                {
                    $sql = qq (update $queue set pid = "$pid", status = "running",)
                         . qq ( beg_time = $beg_time where id = $jid);

                    &Common::DB::request( $dbh, $sql );
                } 
                else {
                    &Common::DB::disconnect( $dbh );
                    exit;
                }

                # Nice it - seems one must use another package (Proc::ProcessTable):

                $table = new Proc::ProcessTable(); 
                $proch = ( grep { $_->pid eq $pid } @{ $table->table } )[0];

                $proch->priority( 19 );

                # Set job icon to running,

                &Common::States::save_job_status( $sid, "running" );

                # Cleaning measure: there may be older jobs than the one just launched
                # that have "running" status, because of software error, or crash due
                # to unforeseeable things (like network outage). So here all those are
                # given "aborted" status,

                $sql = qq (select id from $queue where sub_time < $sub_time and status = "running");

                foreach $id ( map { $_->[0] } &Common::DB::query_array( $dbh, $sql ) )
                {
                    $sql = qq (update $queue set status="aborted" where id = $id);
                    &Common::DB::request( $dbh, $sql );
                }
            }

            sleep 2;
        }
    }

    exit;
}

sub delete_user_jobs
{
    # Niels Larsen, December 2005.

    # Deletes jobs from the queue, given by their ids. Pending jobs are 
    # taken out of the queue; completed jobs are removed from the queue and 
    # the results they generated are deleted; same for running jobs, except
    # that their processes are also killed. 

    my ( $sid,         # Session id
         $jobids,      # Job ids
         $tables,      # Tables to delete from - OPTIONAL
         $queue,       # Queue name - OPTIONAL
         ) = @_;

    # Returns nothing. 

    my ( $sql, $idstr, $dbh, $jobs, $job, $jobid, $job_dir, %jobids, 
         @files, @ids, $file, $clipid, $name, %tables, $table, 
         $user_dbh, $count, @msgs, @txt, $schema );

    $queue = $Def_queue if not defined $queue;
    @txt = ();
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> GET JOB LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $jobs = Common::Menus->jobs_menu( $sid );

    # >>>>>>>>>>>>>>>>>>>> KILL RUNNING PROCESSES <<<<<<<<<<<<<<<<<<<<<<<<

    %jobids = map { $_, 1 } @{ $jobids };
    $count = 0;

    foreach $job ( @{ $jobs->options } )
    {
        if ( $job and exists $jobids{ $job->id } and 
             $job->status eq "running" and $job->pid )
        {
            &Common::Batch::kill_process( $job->pid );
            $count += 1;
        }
    }

    if ( $count == 1 ) {
        push @txt, qq (1 running process was killed);
    } else {
        push @txt, qq ($count running processes were stopped);
    }

    # >>>>>>>>>>>>>>>>>>>>> DELETE FROM BATCH TABLE <<<<<<<<<<<<<<<<<<<<<<

    $dbh = &Common::DB::connect( $DB_master );

    $count = 0;
    $idstr = '"'. (join '","', @{ $jobids }) .'"';

    $sql = qq (delete from $queue where id in ( $idstr ));
    $count += &Common::DB::request( $dbh, $sql );

    if ( $count == 1 ) {
        push @txt, qq (1 job de-listed);
    } else {
        push @txt, qq ($count jobs de-listed);
    }

    &Common::DB::disconnect( $dbh );

    # >>>>>>>>>>>>>>>>>>>>> DELETE DATABASE ENTRIES <<<<<<<<<<<<<<<<<<<<<<

    $user_dbh = &Common::DB::connect_user( $sid );

    $count = 0;

    foreach $jobid ( @{ $jobids } )
    {
        $job_dir = "$Common::Config::ses_dir/$sid/Analyses/$jobid";

        if ( -d $job_dir )
        {
            # Alignment files,

            @files = &Common::File::list_pdls( $job_dir );
            @ids = map { &Common::Names::strip_suffix( $_->{"name"} ) } @files;
            $idstr = '"'. (join '","', @ids) .'"';
            
            foreach $table ( Registry::Schema->get("ali")->table_names )
            {
                if ( &Common::DB::table_exists( $user_dbh, $table ) )
                {
                    $sql = qq (delete from $table where ali_id in ( $idstr ));  
                    $count += &Common::DB::request( $user_dbh, $sql );
                }
            }
        }
    }

    if ( $count == 1 ) {
        push @txt, qq (1 database entry deleted);
    } else {
        $count = &Common::Util::commify_number( $count );
        push @txt, qq ($count database entries deleted);
    }

    &Common::DB::disconnect( $user_dbh );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> REMOVE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $count = 0;

    foreach $jobid ( @{ $jobids } )
    {
        $job_dir = "$Common::Config::ses_dir/$sid/Analyses/$jobid";
        
        if ( -d $job_dir ) {
            $count += &Common::File::delete_dir_tree( $job_dir );
        }
    }

    if ( $count == 1 ) {
        push @txt, qq (1 output file deleted);
    } else {
        push @txt, qq ($count output files deleted);
    }

    push @msgs, [ "Done", (join ", ", @txt) ."." ];

    return wantarray ? @msgs : \@msgs;
}

sub delete_queue_pid_if_exists
{
    # Niels Larsen, August 2003.
    
    # Deletes the process id file for the daemon that runs a given queue.

    my ( $queue,
         ) = @_;

    # Returns an integer. 
    
    my ( $pid_file, $pid );

    $queue = $Def_queue if not defined $queue;

    $pid_file = "$Common::Config::bat_dir/$queue.pid";

    &Common::File::delete_file_if_exists( $pid_file );

    return;
}

sub delete_submitted_job
{
    # Niels Larsen, August 2003.

    # Deletes a given (by id) row from the batch queue table if its 
    # status is "pending".

    my ( $dbh,     # Database handle
         $id,      # Job id
         $queue,   # Queue name 
         ) = @_;

    # Returns nothing.

    my ( $sql );

    $sql = qq (delete from $queue where id = $id and status = "pending");

    &Common::DB::request( $dbh, $sql );

    return;
}

sub get_job
{
    # Niels Larsen, April 2007.

    # Returns an object where the fields are the columns in the batch queue
    # schema. 

    my ( $dbh,    # Database handle
         $jid,    # Job id
         ) = @_;

    # Returns an object.

    my ( $sql, $job, $reqs );

    $sql = qq (select * from $Def_queue where id = "$jid");
    
    $job = &Common::DB::query_hash( $dbh, $sql, "id" )->{ $jid };

    $job =  &Registry::Args::check( $job, { "S:1" => [ keys %{ $job } ] } );

    return $job;
}

sub get_job_ids
{
    # Niels Larsen, December 2005.

    # Returns a list of ids from jobs in the batch queue that match given
    # session id, clipboard id, method and server database id. 

    my ( $dbh,
         $sid,       # Session id 
         $cid,       # Clipboard id
         $method,    # Method name
         ) = @_;

    my ( $table, $sql, @ids );

    $table = $Def_queue;

    $sql = qq (select id from $table where sid = "$sid" and method = "$method") 
         . qq ( and cid = $cid);

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    
    return wantarray ? @ids : \@ids;
}

sub highest_job_id
{
    # Niels Larsen, December 2005.

    # Returns the highest id of any job in the batch queue. 
    
    my ( $dbh,    # Database handle
         $sid,    # Session id - OPTIONAL
         $cid,    # Clipboard id - OPTIONAL
         $method, # Method name - OPTIONAL
         $status, # Job status - OPTIONAL
         ) = @_; 

    my ( $sql, $id, $table );

    $table = $Def_queue;

    if ( $sid )
    {
        $sql = qq (select max(id) from $table where sid = "$sid");

        if ( $cid ) { 
            $sql .= qq ( and cid = "$cid");
        }

        if ( $method ) {
            $sql .= qq ( and method = "$method");
        }
            
        if ( $status ) {
            $sql .= qq ( and status = "$status");
        }
            
        $id = &Common::DB::query_array( $dbh, $sql )->[0]->[0];
    }
    else {
        $id = &Common::DB::highest_id( $dbh, $table, "id" );
    }

    return $id;
}

sub jobs_ahead
{
    # Niels Larsen, March 2007.

    # Returns a list of job ids that are higher than the
    # highest of a given user. If the list is empty, nothing
    # is returned. 

    my ( $sid,                 # Session id 
         $table,               # Queue table name - OPTIONAL
         ) = @_;

    # Returns a list or nothing.

    my ( $dbh, $jid, $sql, @ids );

    $table = $Def_queue if not defined $table;

    $dbh = &Common::DB::connect( $DB_master );

    $jid = &Common::Batch::highest_job_id( $dbh, $sid );

    $sql = qq (select id from $table where (status = "pending" or status = "running"))
         . qq ( and id < $jid and sid != "$sid");

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    &Common::DB::disconnect( $dbh );

    if ( @ids ) {
        return wantarray ? @ids : \@ids;
    } else {
        return;
    }
}

sub jobs_all_finished
{
    # Niels Larsen, December 2005.

    # Returns true if all jobs have the status "completed", otherwise
    # returns nothing. If a session id is given, then only jobs for that
    # user are questioned, otherwise all.

    my ( $sid,      # Session id - OPTIONAL
         ) = @_;

    # Returns a string. 

    my ( $dbh, $sql, %status, $jobs, $bool, $table );

    $table = $Def_queue if not defined $table;

    if ( $sid ) {
        $sql = qq (select status from $table where sid like "$sid");
    } else {
        $sql = qq (select status from $table);
    }        

    $dbh = &Common::DB::connect( $DB_master );

    $jobs = &Common::DB::query_array( $dbh, $sql );

    if ( $jobs and @{ $jobs } )
    {
        %status = map { $_->[0], 1 } @{ $jobs };

        if ( $status{"running"} ) {
            $bool = 0;
        } elsif ( $status{"pending"} ) {
            $bool = 0;
        } else {
            $bool = 1;
        }
    }
    else {
        $bool = 1;
    }

    &Common::DB::disconnect( $dbh );

    if ( $bool ) {
        return 1;
    } else {
        return;
    }
}

sub jobs_aborted
{
    # Niels Larsen, March 2007.

    # 

    my ( $sid,
         ) = @_;

    my ( @ids );

    @ids = &Common::Batch::jobs_with_status( $sid, "aborted" );

    if ( @ids ) {
        return wantarray ? @ids : \@ids;
    } else {
        return;
    }
}

sub jobs_completed
{
    # Niels Larsen, March 2007.

    # 

    my ( $sid,
         ) = @_;

    my ( @ids );

    @ids = &Common::Batch::jobs_with_status( $sid, "completed" );

    if ( @ids ) {
        return wantarray ? @ids : \@ids;
    } else {
        return;
    }
}

sub jobs_pending
{
    # Niels Larsen, March 2007.

    # 

    my ( $sid,
         ) = @_;

    my ( @ids );

    @ids = &Common::Batch::jobs_with_status( $sid, "pending" );

    if ( @ids ) {
        return wantarray ? @ids : \@ids;
    } else {
        return;
    }
}

sub jobs_running
{
    # Niels Larsen, March 2007.

    # 

    my ( $sid,
         ) = @_;

    my ( @ids );

    @ids = &Common::Batch::jobs_with_status( $sid, "running" );

    if ( @ids ) {
        return wantarray ? @ids : \@ids;
    } else {
        return;
    }
}

sub jobs_with_status
{
    # Niels Larsen, March 2007.

    # 

    my ( $sid,
         $status,
         ) = @_;

    my ( $dbh, $sql, @ids );

    $dbh = &Common::DB::connect( $DB_master );

    $sql = qq (select id from batch_queue where status = "$status");

    if ( $sid ) {
        $sql .= qq ( and sid like "$sid");
    }        

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
    
    &Common::DB::disconnect( $dbh );

    if ( @ids ) {
        return wantarray ? @ids : \@ids;
    } else {
        return;
    }
}

sub kill_process
{
    # Niels Larsen, December 2005.

    # Kills a process given by its process id. Its children are killed 
    # too. Returns the number of processes killed. 

    my ( $pid,     # Process id
         ) = @_;

    # Returns an integer.

    require Proc::Killfam;

    my ( $count );

    $count = &Proc::Killfam::killfam( 9, $pid );

    return $count;
}

sub list_queue
{
    # Niels Larsen, December 2005.

    # Lists the batch queue content, with the fields given. Default 
    # fields are "id,sid,status,command". If session id is given only
    # jobs for that user is included, otherwise all. 

    my ( $sid,          # Session id - OPTIONAL
         $fields,       # Fields list - OPTIONAL 
         $queue,        # Queue name - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $dbh, $list, $sql, $fldstr );

    $queue = $Def_queue if not defined $queue;

    $dbh = &Common::DB::connect( $DB_master );

    if ( &Common::DB::table_exists( $dbh, $queue ) )
    {
        if ( defined $fields ) {
            $fldstr = join ",", @{ $fields };
        } else {
            $fldstr = "id,sid,status,command";
        }
        
        if ( defined $sid ) {
            $sql = qq (select $fldstr from $queue where sid like "$sid");
        } else {
            $sql = qq (select $fldstr from $queue);
        }

        $sql .= qq ( order by id asc);

        $list = &Common::DB::query_array( $dbh, $sql );
    }
    else {
        $list = [];
    }

    &Common::DB::disconnect( $dbh );
    
    return wantarray ? @{ $list } : $list;
}

sub queue_exists
{
    # Niels Larsen, November 2005.

    # Returns 1 if the queue exists, 0 otherwise. 

    my ( $queue,      # Database table name
         ) = @_;
    
    # Returns nothing.

    my ( $dbh, $exists );

    $queue = $Def_queue if not defined $queue;

    $dbh = &Common::DB::connect( $DB_master, 0 );
    
    if ( $dbh->ping )
    {
        if ( &Common::DB::table_exists( $dbh, $queue ) ) {
            $exists = 1;
        } else {
            $exists = 0;
        }

        &Common::DB::disconnect( $dbh );
    }
    else {
        &Common::Messages::error( qq (Database server is not running.) );
    }

    if ( $exists ) {
        return 1;
    } else {
        return;
    }
}

sub queue_is_started
{
    # Niels Larsen, AUgust 2003.

    # Simply checks if there is a .pid file in the batch
    # directory. Returns 1 if it does, 0 otherwise. 

    my ( $queue,     # Name of queue to check
         ) = @_;

    # Returns boolean. 

    $queue = $Def_queue if not defined $queue;
    
    my ( $pid );

    if ( -e "$Common::Config::bat_dir/$queue.pid" ) {
        return 1;
    } else {
        return 0;
    }
}

sub queue_is_running
{
    # Niels Larsen, August 2003.

    # Checks if the process given by the pid file is alive.
    # Returns 1 if it is, 0 otherwise. 

    my ( $queue,     # Name of queue to check
         ) = @_;

    # Returns boolean. 

    my ( $pid, $status );

    $queue = $Def_queue if not defined $queue;
    
    if ( &Common::Batch::queue_is_started( $queue ) )
    {
        $pid = &Common::Batch::read_pid( $queue );
        
        if ( kill 0 => $pid ) {
            return 1;
        } else {
            return 0;
        }
    }
    else
    {
        return 0;
    }
}

sub read_pid
{
    # Niels Larsen, August 2003.

    # Gets the process id for the daemon that runs a given queue.

    my ( $queue,
         ) = @_;

    # Returns an integer. 
    
    my ( $pid_file, $pid );

    $pid_file = "$Common::Config::bat_dir/$queue.pid";

    if ( -e $pid_file )
    {
        $pid = ${ &Common::File::read_file( $pid_file ) };

        $pid =~ s/^\s*//;
        $pid =~ s/\s*$//;

        return $pid;
    }
    else {
        return;
    }
}

sub submit_job
{
    # Niels Larsen, April 2005.

    # Appends a given command to be run in batch to the batch_queue database
    # table. Also sets a state jobs-icon to pending if it is not set already
    # (there may already be a job running).

    my ( $dbh,       # Database handle
         $job,       # Job option object
         ) = @_;

    # Returns nothing.

    my ( $sub_time, $sql, $table, $fields, $field, $values, $value, 
         $tuples, $row );

    $table = $Def_queue;

    &Common::Batch::create_queue_if_not_exists( $dbh, $table );
    
    $tuples = Registry::Schema->get("system")->table( $table )->columns;

    foreach $row ( @{ $tuples } )
    {
        $field = $row->[0];

        if ( defined ( $value = $job->$field ) )
        {
            if ( $value ) {
                push @{ $fields }, $field;
                push @{ $values }, $value;
            }
        }
        else {
            &Common::Messages::error( qq (Undefined field -> "$field") );
        }
    }

    $fields = join ', ', @{ $fields };
    $values = '"'. (join '", "', @{ $values }) .'"';

    $sub_time = &Common::Util::time_string_to_epoch();

    $sql = qq (insert into $table ( $fields, status, sub_time ) values ( $values, "pending", "$sub_time" ) );

    &Common::DB::request( $dbh, $sql );

    return;
}

sub table_keys
{
    # Niels Larsen, March 2008.

    # Returns a list of keys of the batch queue table.

    # Returns a list.

    my ( $keys );

    $keys = Registry::Schema->get("system")->table("batch_queue")->column_names;

    return wantarray ? @{ $keys } : $keys;
}

sub write_pid
{
    # Niels Larsen, August 2003.

    # Saves a process id in a .pid file in the batch directory. 

    my ( $pid,      # Process id
         $queue,    # Name of queue
         ) = @_;

    # Returns an integer. 
    
    if ( not $pid ) {
        &Common::Messages::error( qq (No process id was given) );
    }
        
    my ( $pid_file );

    $pid_file = "$Common::Config::bat_dir/$queue.pid";

    &Common::File::write_file( $pid_file, "$pid\n" );

    return;
}

1;


__END__
