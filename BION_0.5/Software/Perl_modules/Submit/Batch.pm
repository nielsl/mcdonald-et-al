package Submit::Batch;     #  -*- perl -*-

# Manages the launch and running of methods. The main routine is 
# submit_jobs, which processes each selected row in the clipboard:
#
# 1) Gets information about clipboard row from database into a 
#    job object.
#
# 2) Creates a self-contained executable perl file with absolute
#    paths and all, ready to be run by the batch queue.
#
# 3) Writes the job object information to the batch_queue database
#    table, which the batch queue daemon is looking at. 
#
# Directories and database tables are created as necessary. See 
# the BION/Documentaion directory for how to add a method.

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &copy_old_input
                 &create_stub_code
                 &run_blastn
                 &run_blastp
                 &run_blastx
                 &_run_blast
                 &run_muscle
                 &run_patscan_dna
                 &run_patscan_prot
                 &run_patscan_rna
                 &_run_patscan
                 &run_tblastn
                 &_run_seq_align
                 &_run_seq_search
                 &run_mir_blast
                 &submit_jobs
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Tables;
use Common::DB;
use Common::Names;
use Common::Option;
use Common::Batch;

use Registry::Args;
use Registry::Get;

use Seq::Run;
use Seq::Import;
use Sims::Import;

use Install::Data;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub copy_old_input
{
    # Niels Larsen, June 2008.

    # Copies similarities and input from the most recent job that was run 
    # with the current dataset and method, instead of recreating them. The
    # files are given new job-derived names. Returns a list of similarity 
    # files.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $old_id, $dbh, $old_dir, $msg, $old_file, $new_id, $new_name, 
         $new_path, $i_format, @sims_paths, @old_ids );

    $dbh = &Common::DB::connect();
    $old_id = &Common::Batch::highest_job_id( $dbh, $args->sid, $args->cid, $args->method, "completed" );
    $dbh->disconnect;
    
    if ( defined $old_id )
    {
        $new_id = $args->jid;

        if ( $new_id eq $old_id )
        {
            $msg = qq (Current and previous job ids are the same -> "$new_id");
            &error( $msg );
        }            
            
        $old_dir = "$Common::Config::ses_dir/". $args->sid ."/Analyses/$old_id";

        if ( not -d $old_dir )
        {
            $msg = qq (Previous job directory does not exist -> "\n$old_dir\n This means it has been )
                 . qq ( deleted but the corresponding batch_queue entry has not.);

            &error( $msg );
        }

        foreach $old_file ( &Common::File::list_files( $old_dir, '.sims$' ) )
        {
            $new_name = $old_file->{"name"};
            $new_name =~ s/^$old_id/$new_id/;
            
            $new_path = $args->res_dir ."/$new_name";
            &Common::File::copy_file( $old_file->{"path"}, $new_path );
            
            push @sims_paths, $new_path;
        }

        if ( not @sims_paths )
        {
            $msg = qq (No similarities files found in job directory -> "$old_dir");
            &error( $msg );
        }            

        $i_format = $args->iformat;
        
        foreach $old_file ( &Common::File::list_files( $old_dir, '.'.$i_format.'$' ) )
        {
            $new_name = $old_file->{"name"};
            $new_name =~ s/^$old_id/$new_id/;
            
            &Common::File::copy_file( $old_file->{"path"}, $args->res_dir ."/$new_name" );
        }
    }

    return wantarray ? @sims_paths : \@sims_paths;
}
    
sub create_stub_code
{
    # Niels Larsen, December 2006.

    # Creates a small snip of code with absolute paths to input, settings
    # and databases. Arguments are passed on to the programs as they are
    # in the given job object, except file paths are expanded. When run, 
    # this file does the work and generates output; the batch queue does
    # the running. 

    my ( $args,        # Arguments hash
         ) = @_;

    # Returns nothing. 

    my ( $method, $code, $argstr1, $argstr2, $args2, $field );

    $argstr1 = &Common::Util::dump_str( $args, 1 );

    # Format code,

    $method = "run_". $args->method;

    $code = qq (#!/usr/bin/env perl

# Code waiting to be run by the batch queue. It is written
# by the routine Submit::Batch::create_stub_code.

use strict;
use warnings FATAL => qw ( all );

use Submit::Batch;
use Submit::Menus;
use Registry::Args;
use Ali::Create;

my ( \$debug, \$count );

\$debug = \$ARGV[0];

\{
    if ( \$debug ) {
        \$Common::Messages::silent = 0;
        \$Common::Config::with_console_messages = 1;
        \$Common::Config::with_errors_dumped = 0;
    } else {
        \$Common::Messages::silent = 1;
        \$Common::Config::with_console_messages = 0;
        \$Common::Config::with_errors_dumped = 1;
    }

    \$count = &Submit::Batch::$method\( $argstr1 \);

    # Creates results menu in the same directory as the results,

    &Ali::Create::save_job_results\(
    \{
        "job_dir" => \"$args->{"job_dir"}\",
        "job_id" => \"$args->{"jid"}\",
    \}\);

    &Submit::Menus::append_results_menu\(
    \{ 
        "ses_id" => \"$args->{"sid"}\", 
        "job_dir" => \"$args->{"job_dir"}\",
    \}\);
\}

);

    return $code;
}

sub run_blastn
{
    my ( $args,
         $msgs,
         ) = @_;

    $args->params->{"-p"} = "blastn";

    return &Submit::Batch::_run_blast( $args, $msgs );
}

sub run_blastp
{
    my ( $args,
         $msgs,
         ) = @_;

    $args->params->{"-p"} = "blastp";

    return &Submit::Batch::_run_blast( $args, $msgs );
}

sub run_blastx
{
    my ( $args,
         $msgs,
         ) = @_;

    $args->params->{"-p"} = "blastx";

    return &Submit::Batch::_run_blast( $args, $msgs );
}

sub run_muscle
{
    my ( $args,
         $msgs,
         ) = @_;

    &Submit::Batch::_run_seq_align( $args, $msgs );

    return;
}

sub run_blastalign
{
    my ( $args,
         $msgs,
         ) = @_;

    &Submit::Batch::_run_seq_align( $args, $msgs );

    return;
}

sub _run_seq_align
{
    # Niels Larsen, May 2008.

    # Runs the sequence alignment program specified with the "method" argument
    # and imports the resulting alignment. 

    my ( $args,                  # Arguments object
         $msgs,                  # Outgoing messages hash - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $routine, $ofile, $ft_names, @counts, $title, $ali_type );

    $routine = "Seq::IO::measure_". $args->iformat;
    
    no strict "refs";

    # Check that there are at least two sequences,

    @counts = $routine->( $args->ifile );

    if ( scalar @counts < 2 )
    {
        $title = $args->title;
        &error( qq (Only one sequence in "$title", there should be at least two.) );
    }

    # Run sequence alignment program,

    $routine = "Seq::Run::run_". $args->method;

    $ofile = $args->opath .".". Registry::Get->method( $args->method )->oformat;

    {
        no strict "refs";

        &{ $routine }(
            {
                "ifile" => $args->ifile,
                "ofile" => $ofile,
                "params" => $args->params,
            }, $msgs );
    }

    # Import alignment, 

    if ( -r $ofile )
    {
        $ali_type = &Common::Types::seq_to_ali( $args->itype );

        $ft_names = Common::Menus->datatype_features( $ali_type )->options_names;
        $ft_names = [ grep { $_ !~ /sid_text$/ } @{ $ft_names } ];
        
        &Install::Data::import_alignment(
            {
                "title" => $args->title,
                "label" => "",
                "ifile" => $ofile,
                "iformat" => $args->iformat,
                "itype" => $ali_type,
                "opath" => $args->opath,
                "tab_dir" => $args->tab_dir,
                "ft_names" => $ft_names,
                "db_name" => $args->sid,
                "source" => $args->source,
            }, $msgs );
        
    }
    
    return;
}
 
sub run_patscan_rna
{
    my ( $args,
         $msgs,
         ) = @_;

    $args->params->{"-c"} = 1;
    $args->dbformat( Registry::Get->method("patscan_rna")->dbformat );

    return &Submit::Batch::_run_patscan( $args, $msgs );
}

sub run_patscan_dna
{
    my ( $args,
         $msgs,
         ) = @_;

    $args->params->{"-c"} = 1;
    $args->dbformat( Registry::Get->method("patscan_dna")->dbformat );

    return &Submit::Batch::_run_patscan( $args, $msgs );
}

sub run_patscan_prot
{
    my ( $args,
         $msgs,
         ) = @_;

    $args->params->{"-p"} = 1;
    $args->dbformat( Registry::Get->method("patscan_prot")->dbformat );

    return &Submit::Batch::_run_patscan( $args, $msgs );
}

sub _run_patscan
{
    # Niels Larsen, December 2006.

    my ( $args,           # Arguments object
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns nothing. 

    my ( $count );

    $args->run_method( "Seq::Run::run_patscan_files" );
    $args->parse_method( "Sims::Import::read_sims_from_patscan" );

    $args->iformat( "patscan" );

    $args->pre_params->{"split_input"} = 0;

    $args->post_params->{"with_condense"} = 0;
    $args->post_params->{"with_query_seq"} = 0;
    $args->post_params->{"sort_sims"} = "";
    $args->post_params->{"align_method"} //= "stacked_append";

    $count = &Submit::Batch::_run_seq_search( $args, $msgs );

    return $count;
}

sub run_tblastn
{
    my ( $args,
         $msgs,
         ) = @_;

    $args->params->{"-p"} = "tblastn";

    return &Submit::Batch::_run_blast( $args, $msgs );
}

sub _run_blast
{
    # Niels Larsen, December 2006.

    # Creates similarities from Constructs the arguments needed by the Ali::Import routines and runs
    # them. Also handles this distinction: if a existing alignment is given
    # as blast db, then only match features are generated; but if a sequence
    # blast db is given then a new alignment is created from the matches.

    my ( $args,           # Arguments object
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns nothing. 

    my ( $args_c, $run_method, $parse_method, $count );

    if ( $args->dbpath ) {
        $run_method = "Seq::Run::run_blast_local";
    } else {
        $run_method = "Seq::Run::run_blast_at_ncbi";
    }

    if ( $run_method =~ /_(ncbi|local)$/ ) {
        $parse_method = "Sims::Import::read_sims_from_". $args->oformat ."_$1";
    } else {
        &error( qq (Wrong looking similarity method -> "$run_method".) );
    }

    $args->run_method( $run_method );
    $args->parse_method( $parse_method );

    $args->iformat("fasta");

    $args->pre_params->{"trim_ids"} = 1;
    $args->pre_params->{"split_input"} = 1;

    $args->post_params->{"with_query_seq"} = 1;
    $args->post_params->{"align_method"} //= "stacked_append";

    $count = &Submit::Batch::_run_seq_search( $args, $msgs );

    return $count;
}

sub _run_seq_search
{
    # Niels Larsen, December 2007.

    # Handles requests that search against sequences, either remote or local,
    # aligned or unaligned. The search probe may be a sequence, a pattern or
    # what else there are programs for. If unaligned sequences are given as 
    # the search target, then an alignment will be created; if an alignment is
    # the target, the matches will just be painted on top. Database features 
    # menu structures for the display are generated. 

    my ( $args,     # Arguments hash
         $msgs,     # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $reuse_sims, $count, $create_sims, @sims_files );

    require Ali::IO;
    require Ali::Create;
    require Ali::State;

    $reuse_sims = $args->pre_params->{"use_latest_sims"};

    # >>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL REUSE <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Copy similarities and input from the most recent similar job,

    if ( $reuse_sims )
    {
        @sims_files = &Submit::Batch::copy_old_input( $args, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>> CREATE SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<

    # Run the search probe(s) one by one through the method given by the 
    # arguments and create similarity files (.sims) and query sequence 
    # files,

    if ( not @sims_files )
    {
        @sims_files = &Sims::Import::create_sims(
            {
                "run_method" => $args->run_method,
                "parse_method" => $args->parse_method,
                "ifile" => $args->ifile,
                "iformat" => $args->iformat,
                "dbpath" => $args->dbpath,
                "dbtype" => $args->dbtype,
                "dbformat" => $args->dbformat,
                "oprefix" => $args->opath,
                "oformat" => $args->oformat,
                "title" => $args->title,
                "pre_params" => $args->pre_params,
                "params" => $args->params,
                "post_params" => $args->post_params,
            }, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>> PROCESS SIMILARITIES <<<<<<<<<<<<<<<<<<<<<<<

    $count = 0;

    if ( &Ali::IO::ali_exists( $args->dbpath ) )
    {
        # >>>>>>>>>>>>>>>>>>> PAINT EXISTING ALIGNMENT <<<<<<<<<<<<<<<<<

        # Create sequence index for sequence retrieval,

#        Seq::Import->create_seq_index_if_not_exists({
#            "ifile" => $args->dbpath,
#            "iformat" => "fasta",
#            "clobber" => 0,
#        });

        # If the comparison was made against an alignment, then paint 
        # all matches for all queries on top of it, thus "pooling" all
        # matches,

        $count = &Ali::Import::paint_features(
            {
                "jid" => $args->jid,
                "sid" => $args->sid,
                "res_dir" => $args->res_dir,
                "tab_dir" => $args->tab_dir,
                "dbname" => $args->dbname,
                "dbpath" => $args->dbpath,
                "itype" => $args->itype,
                "title" => $args->title,
                "method" => $args->method,
            }, $msgs );
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>> MAKE NEW ALIGNMENTS <<<<<<<<<<<<<<<<<<<<

        # Make sure all referred to remote sequences become local: if 
        # the target dataset is local, then index it, otherwise download 
        # and import entries to a directory structure, where they can be 
        # retrieved quickly,

#          if ( not $args->dbname eq "clipboard" and 
#              not Registry::Get->dataset( $args->dbname )->is_local_db )
#          {
#             if ( not @sims_files ) 
#             {
#                 @sims_files = &Common::File::list_files( $args->res_dir, '.sims$' );
#                 @sims_files = map { $_->{"path"} } @sims_files;
#             }
            
#              Sims::Import->import_seqs_missing_files( \@sims_files, $args->dbtype );
#          }
        
        # Make alignment from each .sims file,

        $count = &Ali::Create::alis_from_sims_files(
            \@sims_files,
            {
                "sid" => $args->sid,
                "res_dir" => $args->res_dir,
                "tab_dir" => $args->tab_dir,
                "dbname" => $args->dbname,
                "dbtype" => $args->dbtype,
                "dbpath" => $args->dbpath,
                "post_params" => $args->post_params,
            }, $msgs );
    }

    return $count;
}

sub run_mir_blast
{
    # Niels Larsen, December 2006.

    # Runs regular blast plus adds flanks and paints mature miRNAs, precursors,
    # potential hairpins and miRNA pattern matches on the resulting alignment.

    my ( $args,          
         $msgs,          
         ) = @_;

    # Returns nothing. 

    my ( @q_seqs, $seq, $id, $len, $msg );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK INPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Check that the lengths of the input sequences are all less than 200 
#     # bases, due to loose blast settings in this method (if longer, then 
#     # use regular blast with different default settings).
    
#     @q_seqs = &Seq::IO::read_seqs_file( $job->input );

#     foreach $seq ( @q_seqs )
#     {
#         if ( $seq->seq_len > 100 )
#         {
#             $id = $seq->id;
#             $len = $seq->seq_len;
            
#             $msg = qq (The input sequence "$id" is $len bases long. )
#                  . qq (For this mir-analysis the maximum is 100, due to very loose )
#                  . qq (blast settings. However the regular blast methods have no )
#                  . qq (such limit.);
            
#             &error( $msg );
#         }
#     }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMON BLAST <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args->params->{"-p"} = "blastn";

    &Submit::Batch::_run_blast( $args, $msgs );


    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ADD FEATURES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE RESULTS MENU <<<<<<<<<<<<<<<<<<<<<<<<<



    return;
}

sub submit_jobs
{
    # Niels Larsen, November 2005.

    # Submits the jobs on the clipboard that have the "submit" field set. A line
    # is added to the database table "batch_queue" and a small file is written 
    # with perl code that can be executed. The batch queue daemon then takes the
    # jobs one by one and runs them (see Common::Batch::daemon). After submission
    # one or more messages are returned, mentioning success and/or problems. 

    my ( $clip,        # Clipboard menu structure 
         $proj,        # Project object
         ) = @_;

    # Returns a list.

    my ( $schema, $table, $sid, $ses_dir, $dbh, $row, $jobid, $keys, $job,
         $db_name, $db_ent, $db_path, $db_type, $db, $args, $key, $code_text, 
         $code_file, $submitted, @msgs, $txt, $opt, $params, $params_file, 
         $method, $db_format, $db_source, $in_source, $param_type, $in_name, 
         $in_type, $in_format, $serverdb_str, $in_path );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $schema = "system";
    $table = "batch_queue";

    $sid = $clip->session_id;
    $ses_dir = "$Common::Config::ses_dir/$sid";

    $submitted = 0;

    $dbh = &Common::DB::connect( $Common::Config::db_master );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS CLIPBOARD <<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $row ( $clip->options )
    {
        next if not $row->selected;

        # >>>>>>>>>>>>>>>>>>>>>>>>> SET DATASET INFO <<<<<<<<<<<<<<<<<<<<<<<<<<

        # Sets db_name (dataset name), db_ent (dataset entry), db_type (dataset
        # type) and data source,

        if ( $row->serverdb )
        {
            ( $db_name, $db_ent, $db_type ) = &Common::Names::parse_serverdb_str( $row->serverdb );

            $db_format = "";
            $db_source = $db_name;

            if ( $db_name eq "clipboard" )
            {
                $opt = Common::Menus->clipboard_menu( $sid )->match_option( "id" => $db_ent );
                $db_path = "$Common::Config::ses_dir/$sid/". $opt->input;
            }
            else
            {
                $db = Registry::Get->dataset( $db_name );
                $db_format = $db->format;
                
                if ( $db->is_local_db )
                {
                    $db_path = "$Common::Config::dat_dir/". $db->datapath . "/Installs";
                    
                    if ( $db_ent ne "" ) {
                        $db_path .= "/$db_ent";
                    }                    
                }
                else {
                    $db_path = "";
                }
            }
        }
        else
        {
            $db_name = "";
            $db_path = "";
            $db_type = "";
            $db_format = "";
            $db_source = "upload";
        }

        $in_name = "upload";
        $in_path = "$ses_dir/". $row->input;
        $in_format = $row->format;
        $in_type = $row->datatype || "";
        $in_source = $row->objtype;

        &dump( "$db_name, $db_path, $db_type, $db_format, $db_source" );
        &dump( "$in_name, $in_path, $in_format, $in_type, $in_source" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TODO FIX THIS HACK 
        
        # This swaps serverdb and input if needed .. but instead methods should just
        # have a list of inputs and outputs, and datasets should probably have multiple 
        # datatypes .. should make things easier. 

        $method = Registry::Get->method( $row->method );

        if ( not $method->match( "dbitypes" => $db_type ) )
        {
#            ( $in_name, $db_name ) = ( $db_name, $in_name );
            ( $in_path, $db_path ) = ( $db_path, $in_path );
            ( $in_format, $db_format ) = ( $db_format, $in_format );
            ( $in_type, $db_type ) = ( $db_type, $in_type );
            ( $in_source, $db_source ) = ( $db_source, $in_source );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> MAKE JOB OBJECT <<<<<<<<<<<<<<<<<<<<<<<<<<

        # Set job id to 1 above the the highest in database,

        $jobid = ( &Common::Batch::highest_job_id( $dbh ) || 0 )  + 1;

        # Create a job object with fields that correspond to those in the 
        # batch_queue schema. A check is done here against the schema, 

        $keys = &Common::Batch::table_keys;

        $job = Registry::Obs->new( { map { $_, "" } @{ $keys } } );

        $job->id( $jobid );
        $job->sid ( $sid );
        $job->cid ( $row->id );
        $job->method( $row->method );   
        $job->input( $in_path );
        $job->input_type( $in_type );
        $job->output( "$jobid.output" );
        $job->serverdb( &Common::Names::format_dataset_str( $db_name, "", $db_type ) );
        $job->title( $row->title );
        $job->coltext( $row->coltext );

        # >>>>>>>>>>>>>>>>>>>>>>>>> COMPOSE ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # The argument hash is used to package all information to the routine 
        # that is launched. 

        $method = &Submit::State::restore_method( $clip, $row->method, $row );

        $args =
        {
            "jid" => $jobid,
            "sid" => $sid,
            "cid" => $job->cid,
            "title" => $job->title,
            "project" => $proj->name,
            "source" => $db_source,

            "job_dir" => "$ses_dir/Analyses/$jobid",
            "res_dir" => "$ses_dir/Analyses/$jobid",
            "tab_dir" => "$ses_dir/Analyses/$jobid",
            "db_dir" => "$ses_dir/Database",

            "method" => $job->method,
            "run_method" => "",
            "parse_method" => "",
            
            "ifile" => $in_path,
            "iformat" => $in_format,
            "itype" => $in_type,

            "dbname" => $db_name,         # registry id string
            "dbtype" => $db_type,         # registry type string
            "dbpath" => $db_path,
            "dbformat" => $db_format,
            
            "oformat" => Registry::Get->method( $job->method )->oformat,
            "opath" => "$ses_dir/Analyses/$jobid/$jobid",
        };

        foreach $param_type ( "pre_params", "params", "post_params" )
        {
            if ( $method->$param_type ) {
                $args->{ $param_type } = { map { $_->name, $_->value } @{ $method->$param_type->values->options } };
            } else {
                $args->{ $param_type } = {};
            }
        }

        $args = Common::Obj->new( $args );

        # >>>>>>>>>>>>>>>>>>>>>>> CREATE DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<

        foreach $key ( qw ( job_dir res_dir tab_dir db_dir ) )
        {
            &Common::File::create_dir_if_not_exists( $args->$key );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> GENERATE CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # A mini-program is written that executes the job when run,

        $code_text = &Submit::Batch::create_stub_code( $args );

        $code_file = $args->job_dir ."/batch_script";
        &Common::File::write_file( $code_file, $code_text );

        $job->command( "perl $code_file" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> SUBMIT JOB <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &Common::Batch::create_queue_if_not_exists( $dbh );
        &Common::Batch::submit_job( $dbh, $job );

        $submitted += 1;
    }

    &Common::DB::disconnect( $dbh );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE RECEIPT <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $submitted >= 1 )
    {
        if ( $submitted == 1 ) {
            $txt = qq (1 job submitted to the batch queue.);
        } else {
            $txt = qq ($submitted jobs submitted to the batch queue.);
        }

        $txt .= qq ( The "Results" page will auto-refresh and show if jobs are running and)
              . qq ( where they are in the queue. The icon at the right edge of the top menu bar)
              . qq ( will also indicate completion or failure, while browsing.);

        push @msgs, [ "Submitted", $txt ];
    }
    else {
        push @msgs, [ "Error", qq (No job submitted. Please select one (or more) with the checkbox(es).) ];
    }

    return wantarray ? @msgs : \@msgs;
}

1;

__END__

# sub create_blast_alignments
# {
#     # Niels Larsen, January 2007.
    
#     # Writes alignments from blast outputs, one per query sequence. Gaps 
#     # are inserted to make all database sequences align with the query 
#     # sequence, but the database sequences do not necessarily align among
#     # themselves (though in high-similarity regions they will). The output
#     # files are named (batch-job-number).(0,1,2..).(fasta_ali,fasta). 

#     my ( $job,               # Job object
#          $params,            # Settings
#          $msgs,              # Message list
#          ) = @_;

#     # Returns nothing. 

#     my ( $db_type, @sim_files, %sim_files, $sim_file, $i_fh, $q_id, $i,
#          $q_seq, $sims, $sims2, @o_prefixes, $o_prefix, $o_dir, $i_file, $o_file,
#          $infos, $dbh, $ali, $state, $sid_fts, @sids );
    
#     use Ali::Create;
#     use Ali::State;

#     $db_type = $params->{"db_type"};

#     # >>>>>>>>>>>>>>>>>>>>>>> SPLIT BLAST OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     # Split the single output into outputs, one per query sequence,

#     # >>>>>>>>>>>>>>>>>> WRITE ONE ALIGNMENT PER QUERY SEQ <<<<<<<<<<<<<<<<<<<

#     $i_fh = &Common::File::get_read_handle( $job->input );

#     while ( $q_seq = bless &Seq::IO::read_seq_fasta( $i_fh ), "Seq::Common" )
#     {
#         $q_id = $q_seq->id;
        
#         if ( $sim_file = $sim_files{ $q_id } )
#         {
#             # >>>>>>>>>>>>>>>>>>>>> READ BLAST SIMILARITIES <<<<<<<<<<<<<<<<<<

#             if ( &Common::Types::is_dna_or_rna( $db_type ) ) {
#                 $sims = &Sims::Import::read_sims_from_blast_tabular( $sim_file, { "extract" => "gi" } );
#             } else {
#                 $sims = &Sims::Import::read_sims_from_blast_xml( $sim_file, { "extract" => "gi" } );
#             }

#             $sims = $sims->[0];

#             # >>>>>>>>>>>>>>>>>>>>> CONDENSE SIMILARITIES <<<<<<<<<<<<<<<<<<<<

#             # Condense the similarities so there is only one match per subject 
#             # sequence. This is done with an alignment routine (DNA::Ali::align_two_dnas) 
#             # that takes ranges (as well as sequence) and outputs the highest
#             # scoring fragment alignment. The "locs2" fields are set to strings
#             # like '[[8,100],[117,200]]' or '[[200,117],[100,8]]', which gives 
#             # the coordinates of these matches,
            
#             $sims = &Sims::Common::combine( $sims );
#             $sims = [ sort { $b->score <=> $a->score } @{ $sims } ];
            
#             # >>>>>>>>>>>>>>>>>>>>> CREATE ALIGNMENT FILES <<<<<<<<<<<<<<<<<<<

#             # Creates files with these suffixes appended:
#             # 
#             # .pdl     native alignment data
#             # .info    native alignment meta information
#             # .fasta   sequences without gaps
#             # .fts     locations of matches etc as feature objects
#             #

#             $o_dir = &File::Basename::dirname( $job->output );
#             $o_prefix = "$o_dir/". $job->id .".$q_id";

#             $params->{"ali_id"} = $job->id .".$q_id";
#             $params->{"ali_title"} = $job->title ." (". ($q_id+1) .")";

#             $o_file = "$o_prefix.fasta_ali";
#             ( $sims, $sid_fts ) = &Ali::Create::create_fasta_ali_from_sims( $q_seq, $sims, $o_file, $params );
 
#             # Similarities are updated with lloc fields that hold the match
#             # coordinates in the numbering of the excised sequences, so we 
#             # save them here,

#             $o_file = "$o_prefix.sims";
#             &Common::File::dump_file( $o_file, $sims );

#             $o_file = "$o_prefix.sid_fts";
#             &Common::File::dump_file( $o_file, $sid_fts );

#             # Write PDL version,

#             @sids = map { $_->sid } @{ $sid_fts };

#             $i_file = "$o_prefix.fasta_ali";

#             Ali::Import->write_pdl_from_fasta( $i_file, $o_prefix,
#                                                {
#                                                    "datatype" => &Common::Types::seq_to_ali( $db_type ),
#                                                    "sid" => $params->{"ali_id"},
#                                                    "sids" => \@sids,
#                                                    "source" => $params->{"ali_source"},
#                                                    "title" => $params->{"ali_title"},
#                                                });

#             # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE STATE <<<<<<<<<<<<<<<<<<<<<<<<

#             # Left-align short-ids instead of the default right-align (TODO: 
#             # fix inconsistent alignment path, sometimes with, sometimes 
#             # without $Common::Config::ses_dir)

#             $state = &Ali::State::default_state();
#             $state->{"ali_sid_left_indent"} = "left";

#             $o_file = "$o_prefix.state";
#             &Common::File::store_file( $o_file, $state );


#             push @o_prefixes, $o_prefix;
#         }
#         else {
#             push @{ $msgs }, [ "Info", qq (No matches with "$q_id") ];
#         }
#     }

#     &Common::File::close_handle( $i_fh );

#     return wantarray ? @o_prefixes : \@o_prefixes;
# }

# sub load_matches
# {
#     # Niels Larsen, December 2006.

#     # Loads a given set of matches into a user database.

#     my ( $sid,                # Session id
#          $matches,            # 
#          ) = @_;

#     # 

#     my ( $tmp_file, $dbh, $qid, $sims, $sim, $ent_id, $value, $count, $jid, $cid, 
#          $inputdb, $dir, @q_seqs );
         
#     # Format a similarities table (as defined by the user_sims schema) and 
#     # load it into database,

#     $tmp_file = "$Common::Config::ses_dir/$sid/Scratch/user_sims.tab";
#     &Common::File::create_dir_if_not_exists( "$Common::Config::ses_dir/$sid/Scratch" );

#     $dbh = &Common::DB::connect_user( $sid );

#     $count = 0;

#     foreach $qid ( keys %{ $matches } )
#     {
#         $sims = [];

#         foreach $sim ( @{ $matches->{ $qid } } )
#         {
#             ( $ent_id, $value ) = @{ $sim };
#             push @{ $sims }, [ $jid, $cid, $inputdb, $ent_id, $value ];
#         }

#         &Common::File::delete_file_if_exists( $tmp_file );
        
#         &Common::Tables::write_tab_table( $tmp_file, $sims );
#         $count += &Common::DB::load_table( $dbh, $tmp_file, "user_sims" );
#         &Common::File::delete_file( $tmp_file );
#     }

#     &Common::DB::disconnect( $dbh );

#     return $count;
# }

