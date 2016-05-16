package Seq::Run;                # -*- perl -*-

# Various sequence comparison routines. UNFINISHED

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;
use SOAP::Lite;
use URI::Escape;
use LWP::UserAgent;
use HTTP::Request::Common qw( POST );
use Cwd;
use IPC::Run3;
use List::Util;

{
    local $SIG{__DIE__};
    require Bio::Index::Fasta;
    require IPC::System::Simple;
}

use Common::Config;
use Common::Messages;

use Common::File;
use Common::OS;

use Registry::Paths;
use Registry::Args;

use Seq::Features;
use Seq::IO;
use Seq::Stats;
use Seq::Args;
use Seq::Patterns;

use Sims::Import;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# asymmetry
# center
# has_branch
# run_blast_at_ncbi
# run_blast_local
# run_blastalign
# run_justify
# run_justify_left
# run_justify_right
# run_muscle
# run_pat_searches
# run_patscan
# run_patscan_files
# run_rnalfold
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub asymmetry
{
    my ( $pairs,
         ) = @_;

    my ( $side5, $side3, $count );

    if ( &has_branch( $pairs ) )
    {
        return;
    }
    elsif ( $pairs =~ /((?:\(+\.+)+)((?:\.+\)+)+)/ )   # ((?:\)*\.*)+\))/ )
    {
        $side5 = $1;
        $side3 = $2;
        
        $side5 =~ s/\.*$//;
        $side3 =~ s/^\.*//;

        return abs ( (length $side5) - (length $side3) );
    }

    return;
}

sub center
{
    my ( $pairs,
         ) = @_;

    if ( $pairs =~ /[\(<][\.x]+[\)>]/ )
    {
        return ( length $` ) + ( length $& ) / 2;
    }
    else {
        return;
    }
}

sub has_branch
{
    my ( $pairs,   # Pair-string like  (((...)))...((((.....)))).. 
         ) = @_;

    if ( $pairs =~ /[\)>]([^\(<])*[\(<]/ ) {
        return 1;
    } else {
        return;
    }
}

sub run_blast_at_ncbi
{
    # Niels Larsen, December 2006.

    # Runs blast at NCBI in its four forms. Input file ("ifile"), server database
    # ("dbfile") and output ("ofile") are given in the first argument as a hash,
    # blast parameters in the second. These parameters must be exactly those that 
    # the blastcl3 program wants, with the preceding dash included. This routine 
    # sets rudimentary defaults but the caller should set the arguments. If there
    # are no NCBI errors the routine returns 1; on error it crashes by default or
    # if fatal is set to zero returns undef.

    my ( $args,         # Arguments 
         $msgs,         # Outgoing list of runtime messages - OPTIONAL
         ) = @_;

    # Returns nothing. 

    my ( $q_file, $params, $o_file, @command, $command, $key, $stderr,
         $program, @lists, $list, $ids, $count, $fatal, @msgs );

    # Check arguments and files,

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile ofile ) ],
        "S:0" => [ qw ( dbtype dbfile dbpath fatal ) ],
        "HR:0" => [ qw ( pre_params params post_params ) ],
    });

    $q_file = $args->ifile;
    $o_file = $args->ofile;
    $params = $args->params;
    $fatal = $args->fatal // 1;
    
    $program = $params->{"-p"};

    if ( not $program ) {
        &error( qq (Blast program (-p) is not given) );
    }
        
    if ( not -r $q_file ) {
        &error( qq (Blast query file not found -> "$q_file") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DEFAULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $program =~ /^t?blastn$/ ) 
    {
        $params->{"-e"} = 1e-30 if not defined $params->{"-e"};
        $params->{"-b"} = 999999999 if not defined $params->{"-b"};
        $params->{"-v"} = 999999999 if not defined $params->{"-v"};
    }
    elsif ( $program =~ /^blast(p|x)$/ )
    {
        $params->{"-e"} = 1e-5 if not defined $params->{"-e"};
        $params->{"-b"} = 999999999 if not defined $params->{"-b"};
        $params->{"-v"} = 999999999 if not defined $params->{"-v"};
    }
    else {
        &error( qq (Wrong looking blast program -> "$program") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @command = "$Common::Config::bin_dir/blastcl3";

    delete $params->{"-i"};

    foreach $key ( keys %{ $params } )
    {
        push @command, "$key", $params->{ $key };
    }

    push @command, "-i", $q_file;
    push @command, "-o", $o_file;

    $command = join " ", @command;

    $stderr = "";

    &Common::OS::run3_command( $command, undef, undef, \$stderr, $fatal );

    # Run3 crashes if $fatal set, so here we can write message,

    if ( $stderr )
    {
        print STDERR "$stderr\n";
#        @msgs = map { ["NCBI ERROR", $_] } split "\n", $stderr;
#        &echo_messages( \@msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>> POST-PROCESSING OPTIONS <<<<<<<<<<<<<<<<<<<<<

#     if ( $args->post_params->{"update_seq_cache"} )
#     {
#         if ( $params->{"-m"} == 7 )
#         {
#             @lists = &Sims::Import::read_ids_from_blast_xml({
#                 "ifile" => $args->ofile,
#                 "extract" => "gi",
#             });
#         }
#         elsif ( $params->{"-m"} == 8 )
#         {
#             @lists = &Sims::Import::read_ids_from_blast_tabular({
#                 "ifile" => $args->ofile,
#                 "extract" => "gi",
#             });
#         }
#         else {
#             &error( qq (Wrong looking blast output format -> "$params->{'-m'}") );
#         }

#         foreach $list ( @lists )
#         {
#             push @{ $ids }, @{ $list };
#         }
        
#         $ids = &Common::Util::uniqify( $ids );

#         $count = &Seq::Import::update_seq_cache( $ids, $args->dbtype, $msgs );
#     }

    return 1 if not $stderr;

    return;
}

sub run_blast_local
{
    # Niels Larsen, July 2006.

    # Runs blast on local databases in its four forms. Input file ("input"),
    # server database ("serverdb") and output ("output") are given in the 
    # first argument as a hash, blast parameters in the second. These 
    # parameters must be exactly those that the blastall program wants, with 
    # the preceding dash included. This routine sets rudimentary defaults but
    # the caller should set the arguments. 

    my ( $args,         # Program and file arguments
         $msgs,         # Outgoing list of messages - OPTIONAL
         ) = @_;

    # Returns nothing. 

    my ( $q_file, $db_pre, $o_file, $params, @command, $command, $key, 
         @results, $method, $suffix, $abbrev, @lists, $list, $ids, $count,
         $missing_index, $routine );

    # Check arguments and files,

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( dbtype dbpath ifile ofile ) ],
        "HR:1" => [ qw ( params ) ],
        "S:0" => [ qw ( dbfile ) ],
        "HR:0" => [ qw ( pre_params post_params ) ],
    });

    $q_file = $args->ifile;
    $db_pre = $args->dbpath;
    $o_file = $args->ofile;
    $params = $args->params;

    $method = $params->{"-p"};

    if ( not $method ) {
        &error( qq (Blast program (-p) is not given) );
    }
        
    if ( not -r $q_file ) {
        &error( qq (Blast query file not found -> "$q_file") );
    }

    if ( $method =~ /^t?blastn$/ ) {
        $abbrev = "n";
    } elsif ( $method =~ /^blast(p|x)$/ ) {
        $abbrev = "p";
    } else {
        &error( qq (Wrong looking blast program -> "$method") );
    }
    
    # >>>>>>>>>>>>>>>>>>>>> CREATE INDICES IF MISSING <<<<<<<<<<<<<<<<<<<<<

    # For system data blast indices are made during install, but for uploads
    # and search results they are not. To catch those cases we here check for
    # and create indices if missing,

    foreach $suffix ( "hr", "in", "sq" )
    {
        if ( not -s "$db_pre.$abbrev$suffix" ) {
            $missing_index = 1;
        }
    }
    
    if ( $missing_index )
    {
        $routine = "write_blast$abbrev"."_db";

        no strict "refs";

        Seq::Import->$routine(
            {
                "i_file" => $db_pre,
                "o_prefix" => $db_pre,
            }, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DEFAULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $method =~ /^t?blastn$/ ) 
    {
        $params->{"-e"} = 1e-30 if not defined $params->{"-e"};
        $params->{"-b"} = 999999999 if not defined $params->{"-b"};
        $params->{"-v"} = 999999999 if not defined $params->{"-v"};
    }
    elsif ( $method =~ /^blast(p|x)$/ )
    {
        $params->{"-e"} = 1e-5 if not defined $params->{"-e"};
        $params->{"-b"} = 999999999 if not defined $params->{"-b"};
        $params->{"-v"} = 999999999 if not defined $params->{"-v"};
    }
    else {
        &error( qq (Wrong looking blast program -> "$method") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> RUN COMMAND <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @command = "$Common::Config::bin_dir/blastall";

    delete $params->{"-d"}; 
    delete $params->{"-i"};

    foreach $key ( keys %{ $params } )
    {
        push @command, "$key", $params->{ $key };
    }

    push @command, "-d", $db_pre;
    push @command, "-i", $q_file;
    push @command, "-o", $o_file;

    $command = join " ", @command;

    &Common::OS::run_command( $command, undef, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>> POST-PROCESSING OPTIONS <<<<<<<<<<<<<<<<<<<<<

#     if ( $args->post_params->{"update_seq_cache"} )
#     {
#         if ( $params->{"-m"} == 7 )
#         {
#             @lists = &Sims::Import::read_ids_from_blast_xml({
#                 "ifile" => $args->ofile,
#                 "extract" => "gi",
#             });
#         }
#         elsif ( $params->{"-m"} == 8 )
#         {
#             @lists = &Sims::Import::read_ids_from_blast_tabular({
#                 "ifile" => $args->ofile,
#                 "extract" => "gi",
#             });
#         }
#         else {
#             &error( qq (Wrong looking blast output format -> "$params->{'-m'}") );
#         }

#         foreach $list ( @lists )
#         {
#             push @{ $ids }, @{ $list };
#         }
        
#         $ids = &Common::Util::uniqify( $ids );

#         $count = &Seq::Import::update_seq_cache( $ids, $args->dbtype, $msgs );
#     }

    return;
}

sub run_blastalign
{
    # Niels Larsen, April 2008.

    # Runs the BlastAlign method by Robert Belshaw and Aris Katzourakis.
    # Temporary files are deleted for each run and the output file is in
    # fasta format.

    my ( $args,         # Arguments 
         $msgs,         # Outgoing list of runtime messages - OPTIONAL
         ) = @_;

    my ( $params, $key, $command, @msgs, $msg, $ifile, $iname, $oname,
         $tmp_dir, $orig_dir, $ofile, $ifile2, $ifh, $ofh, $seq, $id );
    
    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile ofile ) ],
        "HR:1" => [ qw ( params ) ],
        "S:0" => [ qw ( dbpath dbfile dbtype ) ],
        "HR:0" => [ qw ( pre_params post_params ) ],
    });

    $ifile = &Cwd::abs_path( $args->ifile );
    $ofile = &Cwd::abs_path( $args->ofile );

    $params = &Common::Util::merge_params(
        $args->params,
        {
            "-m" => 0.99,
            "-r" => undef,
            "-x" => undef,
            "-n" => "T",
            "-s" => undef,
        });

    $orig_dir = &Cwd::getcwd();
    
    $tmp_dir = "$Common::Config::tmp_dir/BlastAlign_". $$;
    &Common::File::create_dir( $tmp_dir );
    chdir $tmp_dir;

    # Make new input file with ids that BlastAlign will accept, 

    $ifile2 = "$tmp_dir/BlastAlign.input";
    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( $ifile2 );

    while ( $seq = bless &Seq::IO::read_seq_fasta( $ifh ), "Seq::Common" )
    {
        $id = $seq->id;
        $id =~ s/[:]/_/g;
        $seq->id( $id );

        &Seq::IO::write_seq_fasta( $ofh, $seq );
    }

    $ifh->close;
    $ofh->close;
    
    # Make command,

    $command = "$Common::Config::bin_dir/BlastAlign -i $ifile2";

    foreach $key ( keys %{ $params } )
    {
        $command .= " $key ". $params->{ $key };
    }

    # Run command; this program creates files with fixed names in the current
    # directory; to avoid that mess, create and delete a subdirectory in the 
    # scratch area,

    @msgs = &Common::OS::run_command( $command, undef, [] );

    chomp @msgs;

    @msgs = grep { $_ =~ /\w/ } @msgs;

    if ( grep { $_ =~ /^BlastAlign finished:/ } @msgs )
    {
        push @{ $msgs }, grep { $_ =~ /^Excluding/ } @msgs;
    }
    elsif ( grep { $_ =~ /failed to find any alignment/ } @msgs )
    {
         push @{ $msgs }, [ "Info", qq (No alignment found) ];
        return;
    }
    else 
    {
        @msgs = grep { $_ =~ /Error message from BlastAlign/ } @msgs;
        $msg = join "\n", @msgs;
        &error( 
              qq (Command line -> "$command"\n)
            . qq (Message: $msg)
            );
    }

    chdir $orig_dir;

    # Convert phylip alignment to fasta,
    
    Seq::Import->write_fasta_from_phylip( "$ifile2.phy", $ofile );

    # Delete all generated files,

    &Common::File::delete_dir_tree( $tmp_dir );

    return;
}

sub run_justify
{
    # Niels Larsen, June 2008.

    # 

    my ( $args,
         $msgs,
        ) = @_;

    my ( $anchor, $counts, $maxlen, $ifh, $ofh, $seq, $str );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile ofile anchor ) ],
        "HR:1" => [ qw ( params ) ],
    });

    $anchor = $args->anchor;

    $counts = &Seq::Stats::measure_fasta_list( $args->ifile );
    $maxlen = &List::Util::max( map { $_->[1] } @{ $counts } );

    $ifh = &Common::File::get_read_handle( $args->ifile );
    $ofh = &Common::File::get_write_handle( $args->ofile );

    while ( $seq = bless &Seq::IO::read_seq_fasta( $ifh ), "Seq::Common" )
    {
        $str = $seq->seq;
        
        if ( length $str < $maxlen )
        {
            if ( $anchor eq "left" ) {
                $str .= "-" x ( $maxlen - length $str );
            } elsif ( $anchor eq "right" ) {
                $str = "-" x ( $maxlen - length $str ) . $str;
            } else {
                &error( qq (Wrong looking justify anchor -> "$anchor", should be left or right) );
            }

            $seq->seq( \$str );
            $seq->pdlify;
        }

        &Seq::IO::write_seq_fasta( $ofh, $seq );
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );
    
    return;
}
    
sub run_justify_left
{
    my ( $args,
         $msgs,
        ) = @_;

    &Seq::Run::run_justify( { %{ $args }, "anchor" => "left" }, $msgs );

    return;
}

sub run_justify_right
{
    my ( $args,
         $msgs,
        ) = @_;

    &Seq::Run::run_justify( { %{ $args }, "anchor" => "right" }, $msgs );

    return;
}

sub run_muscle
{
    # Niels Larsen, January 2007.

    # Runs the multiple sequence alignment program muscle. 

    my ( $args,           # Main arguments
         $msgs,         # Error list
         ) = @_;

    # Returns a list or nothing.

    my ( $command, $argstr, $key, $params );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile ofile ) ],
        "HR:1" => [ qw ( params ) ],
        "HR:0" => [ qw ( pre_params post_params ) ],
        "S:0" => [ qw ( dbpath dbtype dbfile ) ],
    });

    $command = "$Common::Config::bin_dir/muscle";

    $command .= " -in ". $args->ifile;
    $command .= " -out ". $args->ofile;

    $params = Common::Obj->merge_args(
        {
            "-stable" => "",
            "-quiet" => "",
        },
        $args->params );

    if ( defined $params )
    {
        foreach $key ( keys %{ $params } )
        {
            if ( $key eq "-diags" )
            {
                if ( $params->{ $key } ) {
                    $command .= " -diags";
                }
            }
            elsif ( $key eq "-stable" )
            {
                if ( defined $params->{ $key } ) {
                    $command .= " $key";
                } else {
                    $command .= " -group";
                }
            }
            else
            {
                $command .= " $key ". $params->{ $key };
            }
        }
    }

    &Common::OS::run_command( $command, undef, $msgs );

    return;
}    

sub run_pat_searches
{
    # Niels Larsen, February 2010.

    # 
    my ( $args,
        ) = @_;

    my ( @pat_paths, $pat_path, @seq_paths, $seq_path, @seq_dbs, $seq_db, 
         @errors, %seq_dbs, $out_dir, $dir, @check, $reg_list, %seq_reg,
         $out_path, $file, $path, $pat_file, $seq_file, $tmp_path, $seq_type,
         $title );

    # >>>>>>>>>>>>>>>>>>>>>>> CREATE FILE AND DB LISTS <<<<<<<<<<<<<<<<<<<<<<<<

    # Create lists of fully expanded file and db names. First check lists that 
    # must be readable if given,
    
    push @check, $args->{"patlist"} if $args->{"patlist"};
    push @check, $args->{"seqlist"} if $args->{"seqlist"};
    push @check, $args->{"seqdbs"} if $args->{"seqdbs"};

    @errors = &Common::File::access_error( \@check, "efr" );

    if ( @errors ) {
        &echo_messages( \@errors );
        exit;
    }

    # Create list of pattern files, @pat_paths,
    
    if ( $args->{"patfiles"} )
    {
        push @pat_paths, split /\s*,\s*/, $args->{"patfiles"};
    }

    if ( $args->{"patlist"} )
    {
        $dir = File::Basename::dirname( $args->{"patlist"} );
        
        foreach $pat_path ( split " ", ${ &Common::File::read_file( $args->{"patlist"} ) } )
        {
            if ( $dir and $pat_path !~ /\// ) {
                push @pat_paths, "$dir/$pat_path";
            } else {
                push @pat_paths, $pat_path;
            }
        }
    }

    # Create list of sequence files, @seq_paths,

    if ( $args->{"seqfiles"} )
    {
        push @seq_paths, split /\s*,\s*/, $args->{"seqfiles"};
    }

    if ( $args->{"seqlist"} )
    {
        $dir = File::Basename::dirname( $args->{"seqlist"} );
        
        foreach $seq_path ( split " ", ${ &Common::File::read_file( $args->{"seqlist"} ) } )
        {
            if ( $dir and $seq_path !~ /\// ) {
                push @seq_paths, "$dir/$seq_path";
            } else {
                push @seq_paths, $seq_path;
            }
        }
    }

    # Create list of dataset names, @seq_dbs,

    if ( $args->{"seqdbs"} )
    {
        foreach $seq_db ( split " ", ${ &Common::File::read_file( $args->{"seqdbs"} ) } )
        {
            push @seq_dbs, $seq_db;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK ERRORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Either patterns or sequences missing,

    if ( not @pat_paths ) {
        push @errors, [ "Error", qq (No pattern files given) ];
    }
    
    if ( not @seq_paths and not @seq_dbs ) {
        push @errors, [ "Error", qq (No sequence data given) ];
    }

    # Expand file paths where possible,

    @pat_paths = map { defined ( $path = &Common::File::full_file_path( $_ ) ) ? $path : $_ } @pat_paths;
    @seq_paths = map { defined ( $path = &Common::File::full_file_path( $_ ) ) ? $path : $_ } @seq_paths;

    # Check file read access,

    push @errors, &Common::File::access_error( \@pat_paths, "r" );
    push @errors, &Common::File::access_error( \@seq_paths, "r" );

    # Check dataset names,

    $reg_list = Registry::Register->registered_datasets();
    %seq_reg = map { $_->name, 1 } Registry::Get->seq_data( $reg_list )->options;
    
    foreach $seq_db ( @seq_dbs )
    {
        if ( not exists $seq_reg{ $seq_db } ) {
            push @errors, [ "Error", qq (Not a registered sequence database -> "$seq_db") ];
        }
    }

    # Check single output file,
    
    if ( $args->{"outfile"} ) {
        push @errors, &Common::File::access_error( $args->{"outfile"}, "!e" );
    }

    # Check output files that will be generated below, so errors are caught
    # before program runs for a long time,

    if ( $out_dir = $args->{"outdir"} )
    {
        foreach $pat_path ( @pat_paths )
        {
            $pat_file = &File::Basename::basename( $pat_path );
            
            foreach $seq_path ( @seq_paths )
            {
                $seq_file = &File::Basename::basename( $seq_path );
                $out_path = "$out_dir/$pat_file"."_vs_$seq_file";
                
                push @errors, &Common::File::access_error( $out_path, "!e" );
            }

            foreach $seq_db ( @seq_dbs )
            {
                $out_path = "$out_dir/$pat_file"."_vs_$seq_db";
                push @errors, &Common::File::access_error( $out_path, "!e" );
            }
        }
    }

    # Print errors if any, and exit,

    if ( @errors ) {
        &echo_messages( \@errors );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nPattern search:\n) );

    # Create directory if missing,

    &Common::File::create_dir_if_not_exists( $out_dir );

    $seq_type = $args->{"protein"} ? "prot_seq" : "dna_seq";

    foreach $pat_path ( @pat_paths )
    {
        $pat_file = &File::Basename::basename( $pat_path );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SINGLE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<
        
        foreach $seq_path ( @seq_paths )
        {
            $seq_file = &File::Basename::basename( $seq_path );
            $title = "$pat_file vs $seq_file";
            &echo( qq (   $pat_file vs $seq_file ... ) );

            $tmp_path = Registry::Paths->new_temp_path( $pat_file );

            &Sims::Import::create_sims_single(
                {
                    "run_method" => "Seq::Run::run_patscan_files",
                    "ifile" => $pat_path,
                    "dbpath" => $seq_path,
                    "dbtype" => $seq_type,
                    "dbformat" => "fasta",
                    "ofile" => $tmp_path,
                    "title" => $title,
                });
            
            if ( -e $tmp_path )
            {
                $out_path = "$out_dir/$pat_file"."_vs_$seq_file";
                &Common::File::copy_file( $tmp_path, $out_path );
                &Common::File::delete_file( $tmp_path );

                &echo_green("done\n");
            }
            else {
                &echo_yellow("no matches\n");
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        foreach $seq_db ( @seq_dbs )
        {
            $title = "$pat_file vs $seq_db";
            &echo( qq (   $title ... ) );
            
            $tmp_path = Registry::Paths->new_temp_path( $pat_file );
            
            &Sims::Import::create_sims_single(
                {
                    "run_method" => "Seq::Run::run_patscan_files",
                    "ifile" => $pat_path,
                    "dbname" => $seq_db,
                    "dbformat" => "fasta",
                    "ofile" => $tmp_path,
                    "title" => $title,
                });
            
            if ( -e $tmp_path )
            {
                $out_path = "$out_dir/$pat_file"."_vs_$seq_db";
                &Common::File::copy_file( $tmp_path, $out_path );
                &Common::File::delete_file( $tmp_path );

                &echo_green("done\n");
            }
            else {
                &echo_yellow("no matches\n");
            }
        }
    }

    &echo_bold( qq (Done\n\n) );

    return;
}

sub run_patscan
{
    # Niels Larsen, January 2010.

    # Runs patscan with a given pattern file on a given list of sequences.
    # A list of [ id, strand, locations ] is returned. The locations is either
    # a string (the default) or a list of [ position, length ], this depends
    # on the loc_strings argument.

    my ( $seqs,    # List of sequence objects
         $pat,     # Pattern file
         $args,    # Arguments
        ) = @_;

    my ( $defs, @cmd, $str, @faseqs, $locs, @output, $tmp_file, $tmp_fh );

    $defs = {
        "both_strands" => 1,
        "protein" => 0,    
        "max_misses" => undef,
        "max_hits" => undef,
        "ids_file" => undef,
        "loc_strings" => 1,    # Locators as strings
    };

    $args = &Registry::Args::create( $args, $defs );

    @cmd = "$Common::Config::bin_dir/patscan";

    push @cmd, "-c" if $args->both_strands;
    push @cmd, "-p" if $args->protein;

    if ( defined ( $str = $args->max_misses ) ) {
        push @cmd, "-n $str";
    }

    if ( defined ( $str = $args->max_hits ) ) {
        push @cmd, "-m $str";
    }

    if ( defined ( $str = $args->ids_file ) ) {
        push @cmd, "-i $str";
    }

    push @cmd, $pat;

#    @faseqs = map { ">". $_->id ."\n", $_->seq ."\n" } @{ $seqs };

    $tmp_file = Registry::Paths->new_temp_path( "patscan.in.$$" );
    &Seq::IO::write_seqs_fasta( $tmp_file, $seqs );

    push @cmd, " < $tmp_file";

    @output = ();
    @output = IPC::System::Simple::capture( [255], join " ", @cmd );

    &Common::File::delete_file( $tmp_file );

    $locs = &Seq::Patterns::patscan_to_locs( \@output, { "strflag" => $args->loc_strings } );

    return wantarray ? @{ $locs } : $locs;
}

sub run_patscan_files
{
    # Niels Larsen, November 2007.

    # Runs the pattern matching program scan_for_matches on a given set of 
    # fasta formatted sequences, using a given pattern. The sequence argument
    # may be a file name or a list of sequences (see top of this module for 
    # its format). The pattern argument may be a file name or a string that
    # contains a valid pattern. The output is a list of sub-sequences that
    # match, in the same format as the input sequences, except each original
    # id has a range, like [4567:4612] appended. If the second number is 
    # lower than the first, the match is on the opposite strand. 

    my ( $args,      # Package name
         $msgs,      # Outgoing list of messages - OPTIONAL
         ) = @_;

    # Returns a list. 

    my ( $dbtype, $dbfile, $patfile, $ofile, $params, $key, $command, @output, $stderr );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile dbtype dbfile ofile ) ],
        "HR:1" => [ qw ( params ) ],
        "S:0" => [ qw ( dbpath ) ],
        "HR:0" => [ qw ( pre_params post_params ) ],
    });

    $patfile = $args->ifile;
    $dbtype = $args->dbtype;
    $dbfile = $args->dbfile;
    $ofile = $args->ofile;

    $params = $args->params;

    $params->{"-c"} = "" if exists $params->{"-c"};

    if ( &Common::Types::is_protein( $dbtype ) or exists $params->{"-p"} ) {
        $params->{"-p"} = "";
    }

    if ( not -r $dbfile ) {
        &error( qq (Sequence file is not readable -> "$dbfile") );
    }

    if ( not -r $patfile ) {
        &error( qq (Pattern file is not readable -> "$patfile") );
    }

    if ( -e $ofile ) {
        &error( qq (Outfile file exists -> "$ofile") );
    }        

    $command = "patscan"; 

    if ( $params and %{ $params } )
    {
        foreach $key ( keys %{ $params } ) {
            $command .= " $key ". $params->{ $key };
        }
    }

    $command .= " $patfile < $dbfile > $ofile";

    # No need to check pattern parse errors, scan_for_matches will bomb out,

    @output = &Common::OS::run_command( $command, undef, [] );

    if ( @output ) {
        &error( qq (Wrong looking scan_for_matches command line -> "$command") );
    }

    return;
}

sub run_rnalfold
{
    # Niels Larsen, August 2006. 

    # Runs RNALfold on a given set of DNA/RNA sequences, either passed as a list
    # or given by a fasta-formatted file name. Returns a list of sequence features.

    my ( $seqs,      # File path or list of sequence objects
         $args,      # Hash of arguments - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $def_args, $command, $arg, $tmp_file, @lines, $line, $mask, $delta_g, 
         $name, $end, $beg, @fts, $asymmetry, %fts, @list, $hit, $info );

    # >>>>>>>>>>>>>>>>>>>>>> ADD DEFAULTS WHERE MISSING <<<<<<<<<<<<<<<<<<<<<

    $args = Common::Obj->merge_args(
        {
            "max_asymmetry" => undef,
            "max_pair_length" => 100,
            "max_delta_g" => -10,
            "energy_temperature" => 37,
            "with_dangling_ends" => 0,       # can be 0, 1, 2, 3 - see man page
            "with_lone_pairs" => 0,
            "with_gu_pairs" => 1,
            "with_gu_pairs_at_ends" => 0,
            "with_ag_pairs" => 0,
            "with_branches" => 0,
            "with_contained" => 0,
            "with_overlaps" => 0,
        }, $args );

    if ( $args->{"with_branches"} ) {
        undef $args->{"max_asymmetry"};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> COMPOSE COMMAND LINE <<<<<<<<<<<<<<<<<<<<<<<<

    # Complain over unrecognized arguments, 

    $command = "$Common::Config::bin_dir/RNALfold";

    foreach $arg ( keys %{ $args } )
    {
        if ( $arg eq "max_pair_length" ) {
            $command .= qq ( -L $args->{ $arg });
        } elsif ( $arg eq "energy_temperature" ) {
            $command .= qq ( -T $args->{ $arg });
        } elsif ( $arg eq "with_dangling_ends" ) {
            $command .= qq ( -d$args->{ $arg });
        } elsif ( $arg eq "with_lone_pairs" ) {
            $command .= qq ( -noLP) if not $args->{ $arg };
        } elsif ( $arg eq "with_gu_pairs" ) {
            $command .= qq ( -noGU) if not $args->{ $arg };
        } elsif ( $arg eq "with_gu_pairs_at_ends" ) {
            $command .= qq ( -noCloseGU) if not $args->{ $arg };
        } elsif ( $arg eq "with_ag_pairs" ) {
            $command .= qq ( -nsp AG) if $args->{ $arg };
        } elsif ( $arg !~ /^max_asymmetry|with_branches|max_delta_g|with_contained|with_overlaps$/ ) {
            &error( qq (Wrong looking RNALfold argument -> "$arg") );
        }
    }
            
    # >>>>>>>>>>>>>>>>>>>>>> WRITE SCRATCH FILE IF NEEDED <<<<<<<<<<<<<<<<<<<<
    
    if ( ref $seqs eq "ARRAY" )
    {
        $tmp_file = "$Common::Config::tmp_dir/rnalfold_seqs_$$.fasta";
        &Seq::IO::write_seqs_fasta( $tmp_file, $seqs );
        $seqs = $tmp_file;
    }
    elsif ( not $seqs ) {
        &error( qq (No sequences given) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN PROGRAM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @lines = `$command < $seqs`;

    if ( $tmp_file ) {
        &Common::File::delete_file( $tmp_file );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARSE OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $line ( @lines )
    {
        chomp $line;

        # ID line,

        if ( $line =~ /^>(\S+)/ )
        {
            $name = $1;
        }
        elsif ( $line !~ /^[\w ]/ )
        {
            # A score line like so: '((((((((((....)))..))))))) ( -4.10)   30'

            if ( $line =~ /^([\.\(\)]+) +\(\s*(-?\d+\.\d+)\) +(\d+)$/ )
            {
                $mask = $1;
                $delta_g = $2;
                $beg = $3 - 1;
                $end = $beg + (length $mask) - 1;

                $info = {};
                
                # Trim '.' from ends if any,

                if ( $mask =~ s/^(\.+)// ) {
                    $beg += length $1;
                }
                
                if ( $mask =~ s/(\.+)$// ) {
                    $end -= length $1;
                }
                
                # Skip if negative score is above treshold, 

                if ( $delta_g <= $args->{"max_delta_g"} ) {
                    $info->{"delta_g"} = $delta_g;
                } else {
                    next;
                }

                # Skip if asymmetric structure (TODO)

                if ( defined $args->{"max_asymmetry"} )
                {
                    $asymmetry = &asymmetry( $mask );

                    if ( $asymmetry <= $args->{"max_asymmetry"} ) {
                        $info->{"asymmetry"} = $asymmetry;
                    } else {
                        next;
                    }
                }
                
                # Skip structure has branches if requested (TODO),

                if ( not $args->{"with_branches"} and &has_branch( $mask ) ) {
                    next;
                }

                push @fts, Seq::Feature->new( "molecule" => "mirna",
                                              "id" => $name,
                                              "beg" => $beg,
                                              "end" => $end,
                                              "score" => (abs $delta_g) * 1,
                                              "mask" => $mask,
                                              "info" => &Storable::dclone( $info ) );
            }
            else {
                &error( qq (Wrong looking line -> "$line") );
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> FILTER ALTERNATIVES <<<<<<<<<<<<<<<<<<<<<<<<

    # RNALfold will propose structures that are fully contained within a higher
    # scoring one, whether it has the same topology or not. Sometimes those are 
    # undesired and here we filter them out on request,

    if ( not $args->{"with_overlaps"} )
    {
        @fts = Seq::Features->filter( \@fts, "overlap" );
    }
    elsif ( not $args->{"with_alternatives"} )
    {
        @fts = Seq::Features->filter( \@fts, "within" );
    }

    if ( @fts ) {
        return wantarray ? @fts : \@fts;
    } else {
        return;
    }
}

1;

__END__

# sub run_blastn_at_ncbi
# {
#     # Niels Larsen, November 2006.

#     # Submits the sequence in a given file to one of the blast services that 
#     # NCBI offers through their URL interface, while waiting for result. The 
#     # second argument is a hash where keys and values should be among those
#     # listed here,
#     #
#     # http://www.ncbi.nlm.nih.gov/blast/Doc/node9.html
#     # 
#     # If second argument not given, the default is running blastn on the nr 
#     # database with an expect value of 10, and output returned is text with 
#     # aligned fragments shown. 

#     my ( $q_file,             # Input query sequence
#          $args,               # NCBI supported blast parameters
#          ) = @_;

#     # Returns a string.

#     my ( $script_url, $def_args, $params, $key, $val, @params, $paramstr, 
#          $request, $agent, $response, $q_content, $request_id, $run_time_guess,
#          $results );

#     $script_url = "http://www.ncbi.nlm.nih.gov/blast/Blast.cgi";

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $def_args = {
#         "PROGRAM" => "blastn",
#         "DATABASE" => "nr",
#         "EXPECT" => 10,
#         "ALIGNMENTS" => 999999,
#         "DESCRIPTIONS" => 999999,
#         "HITLIST_SIZE" => 999999,
#         "FORMAT_OBJECT" => "Alignment",
#         "FORMAT_TYPE" => "XML",
#         "RESULTS_FILE" => "yes",
#     };

#     if ( defined $args ) {
#         $params = { %{ $def_args }, %{ $args } };
#     } else {
#         $params = $def_args;
#     }

#     if ( $params->{"PROGRAM"} eq "megablast" )
#     {
#         $params->{"PROGRAM"} = "blastn";
#         $params->{"MEGABLAST"} = "on";
#     }
#     elsif ( $params->{"PROGRAM"} eq "rpsblast" )
#     {
#         $params->{"PROGRAM"} = "blastp";
#         $params->{"SERVICE"} = "rpsblast";
#     }

#     while ( ( $key, $val ) = each %{ $params } )
#     {
#         push @params, "$key=$val";
#     }
    
#     $paramstr = join "&", @params;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SUBMIT AND WAIT <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Read and append sequence to url,

#     $q_content = ${ &Common::File::read_file( $q_file ) };
#     $q_content = uri_escape( $q_content );

#     $paramstr .= "&QUERY=$q_content";

#     $request = new HTTP::Request POST => $script_url;
#     $request->content_type('application/x-www-form-urlencoded');

#     &dump( $paramstr );
#     $request->content( "CMD=Put&$paramstr" );
    
#     $agent = LWP::UserAgent->new;
#     $response = $agent->request( $request );

#     if ( $response->content =~ /^    RID = (.*)$/m ) {
#         $request_id = $1;
#     } else {
#         &error( qq (Could not extract NCBI blast request id) );
#     }

#     if ( $response->content =~ /^    RTOE = (.*)$/m ) {
#         $run_time_guess = $1; 
#     } else {
#         &error( qq (Could not extract NCBI blast runtime estimate) );
#     }

#     sleep $run_time_guess;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FETCH RESULTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     while ( 1 )
#     {
#         sleep 5;

#         $request = new HTTP::Request GET => "$script_url?CMD=Get&FORMAT_OBJECT=SearchInfo&RID=$request_id";
#         $response = $agent->request( $request );

#         if ( $response->content =~ /\tStatus=WAITING/m )
#         {
#             next;
#         }
#         elsif ( $response->content =~ /\tStatus=FAILED/m )
#         {
#             &error( qq (Blast failed at NCBI for -> "$request_id". Please )
#                                     . qq (report to blast-help\@ncbi.nlm.nih.gov.), "NCBI BLAST ERROR" );
#         }
#         elsif ( $response->content =~ /\tStatus=UNKNOWN/m )
#         {
#             &error( qq (Blast request expired at NCBI for -> "$request_id".), "NCBI BLAST ERROR" );
#         }
#         elsif ( $response->content =~ /\tStatus=READY/m )
#         {
#             if ( $response->content =~ /\tThereAreHits=yes/m )
#             {
#                 $request = new HTTP::Request GET => "$script_url?CMD=Get&FORMAT_TYPE=Text&RID=$request_id";
#                 $response = $agent->request( $request );
                
#                 &dump( $response );
#                 # $results = \$response->content;
#             }

#             last;
#         }
#         else {
#             &error( qq (Unhandled error for -> "$request_id".) );
#         }            
#     }

#     if ( $results ) {
#         return ${ $results };
#     } else {
#         return;
#     }
# }

# sub run_needleman_wunsch
# {
#     # Niels Larsen, June 2005.

#     # Aligns short sequence strings using the Needleman-Wunsch method.
#     # This is a short wrap-function that sets defaults for the Align::NW
#     # module written by Andreas Doms <ad11@inf.tu-dresden.de>. Expect 
#     # long running time and high memory use for long sequences. Output
#     # is a hash like this:
#     # 
#     #   'a' => 'UGGAUACUAAUAAAA',
#     #   'b' => 'UAAAUA..AAUAAAAGG',
#     #   's' => '|  |||  |||||||',
#     #   'score' => 22,

#     my ( $seq1,   # Sequence 1
#          $seq2,   # Sequence 2
#          $args,   # Parameters - OPTIONAL, default see code
#          ) = @_;

#     # Returns a hash.

#     my ( $params, $nw, $score, $align );
    
#     $args = {} if not defined $args;

#     $params = { 
#         "match" => 3,
#         "mismatch" => -2,
#         "gap_open" => -3,
#         "gap_extend" => -2,
#         %{ $args },
#     };

#     $nw = new Align::NW $seq1, $seq2, $params;

#     $nw->score;
#     $nw->align;

#     $nw->print_align;
  
#     $score = $nw->get_score;
#     $align = $nw->get_align;

#     $align->{"score"} = $score;

#     return $align;
# }

# sub derive_blast_pcts
# {
#     # Niels Larsen, February 2005.

#     # From a given blast m8 output file, extracts percentage similarities
#     # for a given query sequence id. Several matches may be listed for any
#     # given database sequence, so we count matches, mismatches and gaps, 
#     # and then derive percentages from that. Returns a list of tuples of
#     # subject id and percentage, the list sorted by percentage in descending
#     # order. 

#     my ( $file,       # File name
#          $q_id,       # Query id
#          ) = @_;

#     # Returns a list.

#     my ( $fh, $line, $s_id, $len, $miss, $gaps, $counts, $count, $pcts, $pct );

#     $fh = &Common::File::get_read_handle( $file );

#     if ( $q_id )
#     {
#         while ( defined ( $line = <$fh> ) )
#         {
#             if ( $line =~ /^$q_id/ )
#             {
#                 ( $s_id, $len, $miss, $gaps ) = ( split "\t", $line )[ 1,3,4,5 ];
                
#                 $counts->{ $s_id }->[0] += $len;
#                 $counts->{ $s_id }->[1] += $miss;
#                 $counts->{ $s_id }->[2] += $gaps;
#             }
#         }
#     }
#     else
#     {
#         while ( defined ( $line = <$fh> ) )
#         {
#             ( $s_id, $len, $miss, $gaps ) = ( split "\t", $line )[ 1,3,4,5 ];
            
#             $counts->{ $s_id }->[0] += $len;
#             $counts->{ $s_id }->[1] += $miss;
#             $counts->{ $s_id }->[2] += $gaps;
#         }
#     }        
    
#     &Common::File::close_handle( $fh );

#     foreach $s_id ( keys %{ $counts } )
#     {
#         $count = $counts->{ $s_id };
#         $pct = 100 * ( $count->[0] - $count->[1] - $count->[2] ) / $count->[0];

#         push @{ $pcts }, [ $s_id, sprintf "%.2f", $pct ];
#     }

#     @{ $pcts } = sort { $b->[1] <=> $a->[1] } @{ $pcts };

#     return wantarray ? @{ $pcts } : $pcts;
# }

# sub run_blastn_at_ebi
# {
#     # Niels Larsen, November 2006.

#     # Runs blast at EBI via their soapblast-20061123-22125395.txt

#     my ( $q_file,
#          $args,
#          ) = @_;

#     my ( $url, $serv, $def_args, $jobid, $q_hash, $results, $result, $params,
#          $text );

#     $url = 'http://www.ebi.ac.uk/Tools/webservices/wsdl/WSWUBlast.wsdl';
#     $serv = SOAP::Lite->service( $url );

#     $def_args = {
#         "program" => "blastn",
#         "database" => "embl",
#         "email" => "niels\@genomics.dk",
#     };

#     if ( defined $args ) {
#         $params = { %{ $def_args }, %{ $args } };
#     } else {
#         $params = $def_args;
#     }
      
#     $q_hash = {
#         "type" => "sequence",
#         "content" => ${ &Common::File::read_file( $q_file ) },
#     };

#     # Submit job and check its running,

#     $jobid = $serv->runWUBlast( SOAP::Data->name('params')->type( "map" => $params ),
#                                 SOAP::Data->name( content => [ $q_hash ] ) );

#     if ( $serv->call->fault ) {
#         &error( $serv->call->faultstring, "EBI LAUNCH ERROR" );
#     }

#     # Fetch results and save in local scratch area,

#     $results = $serv->getResults( $jobid );

#     if ( $serv->call->fault ) {
#         &error( $serv->call->faultstring, "EBI RESULTS ERROR" );
#     }

#     foreach $result ( @{ $results } )
#     {
#         if ( $result->{"ext"} eq "txt" )
#         {
#             $text = $serv->poll( $jobid, $result->{"type"} );
#             &Common::File::write_file( "$Common::Config::tmp_dir/blast_test$$.".$result->{"ext"}, \$text );
#         }
#     }

#     return 
# }

# sub run_megablast_local
# {
#     # Niels Larsen, October 2004.

#     # Runs megablast with a given file as query sequence(s) and a given
#     # fasta formatted subject file. If the blast indices do not exist
#     # then they will be created. An optional argument hash may be 
#     # given where keys are the arguments that 'megablast' accepts. A
#     # flag may be given to force recreation of indices. Results are 
#     # returned as an array of lines.

#     my ( $q_file,       # Query file path
#          $s_pre,        # Subject file index prefix path
#          $bindir,       # Executables directory - OPTIONAL
#          $args,         # Blast parameters - OPTIONAL
#          $reindex,      # Re-index boolean - OPTIONAL
#          ) = @_;

#     # Returns an array. 

#     my ( $fh, @command, $command, $key, @results, $method, $suffix );

#     # Defaults,

#     if ( $bindir ) {
#         $method = "$bindir/megablast";
#     } else {
#         $method = `which megablast`;
#         chomp $method;
#     }

#     $args->{"D"} = 3 if not defined $args->{"D"};
#     $args->{"m"} = 8 if not defined $args->{"m"};
#     $args->{"e"} = 1e-30 if not defined $args->{"e"};
#     $args->{"b"} = 1000 if not defined $args->{"b"};

#     $reindex = 0 if not defined $reindex;

#     # File checks,

#     if ( not -r $q_file ) {
#         &error( qq (Blast query file not found -> "$q_file") );
#     }

#     # Optional recreation of indices,

#     if ( $reindex ) {
#         &Seq::IO::index_blastn( $s_pre );
#     }
#     else
#     {
#         foreach $suffix ( "nhr", "nin", "nsq" )
#         {
#             if ( not -s "$s_pre.$suffix" ) {
#                 &error( qq (Blast index not found -> "$s_pre.$suffix") );
#             }
#         }
#     }
    
#     # Compose command line,

#     @command = $method;

#     foreach $key ( keys %{ $args } )
#     {
#         push @command, "-$key", $args->{ $key };
#     }

#     push @command, "-d", $s_pre;
#     push @command, "-i", $q_file;

#     $command = join " ", @command;

#     @results = `$command`;

#     if ( @results )
#     {
#         # Remove header lines that megablast creates even when 
#         # there are no matches, 
        
#         while ( @results and $results[0] =~ /^\#/ ) {
#             shift @results;
#         }
#     }

#     if ( @results ) {
#         return wantarray ? @results : \@results;
#     } else {
#         return;
#     }
# }

# sub align_muscle
# {
#     # Martin A. Hansen, June 2007.
 
#     # Aligns a given list of FASTA entries using Muscle.
#     # Returns a list of aligned sequences as FASTA entries.
 
#     my ( $entries,   # FASTA entries
#          $args,      # additional Muscle arguments
#        ) = @_;
 
#     # returns a list
 
#     my ( $pid, $fh_in, $fh_out, $cmd, $entry, @aligned_entries );
 
#     $cmd  = "muscle";
#     $cmd .= " " . $args if $args;
 
#     $pid = open2( $fh_out, $fh_in, $cmd );
 
#     map { &Fasta::fasta_put_entry( $_, $fh_in ) } @{ $entries };
 
#     close $fh_in;                                                                                                               
                                                                                                                                
#     while ( $entry = &Fasta::fasta_get_entry( $fh_out ) ) {                                                                     
#         push @aligned_entries, $entry;                                                                                          
#     }                                                                                                                           
                                                                                                                                
#     close $fh_out;                                                                                                              
                                                                                                                                
#     waitpid $pid, 0;
 
#     return wantarray ? @aligned_entries : \@aligned_entries;                                                                    
# }
