package Seq::Cluster;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that cluster sequences. Scripts should use the cluster routine,
# the the others are helper routines. The process_args routine is used to see
# if the cluster arguments given are right before running.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Fcntl qw ( SEEK_SET SEEK_CUR SEEK_END );

use Time::HiRes;
use Time::Duration qw ( duration );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &cluster
                 &cluster_args
                 &cluster_cdhit
                 &cluster_uclust
                 &list_seeds_cdhit
                 &list_seeds_uclust
                 &run_uclust
                 &write_stats_file
                 &write_stats_sum
                 &write_uclust_seeds
);

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;
use Common::OS;

use Registry::Args;
use Registry::Paths;

use Seq::Args;
use Seq::IO;
use Seq::Clean;

use Ali::Storage;
use Ali::Chimera;

use Recipe::IO;
use Recipe::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use vars qw ( *AUTOLOAD );

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub cluster
{
    # Niels Larsen, March 2010.

    # Clusters a fasta formatted sequence files, using uclust (default)
    # or cdhit. This is the only cluster routine that should be called from 
    # the outside, see the seq_cluster script for an example. 

    my ( $args,       # Arguments hash
	) = @_;

    # Returns nothing.
    
    my ( $defs, $silent, $i, $conf, $indent, $silent2, $name, $recipe, 
         $params, $tmp_dir, $clobber, $prog );
    
    if ( $args->{"silent"} and ( $args->{"iseqs"} and -r $args->{"iseqs"} and not -s $args->{"iseqs"} ) ) {
        return;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->{"recipe"} )
    {
        $recipe = &Recipe::IO::read_recipe( $args->{"recipe"} );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "iseqs" => undef,
        "recipe" => undef,
	"ofasta" => undef,
        "ofasuf" => undef,
        "oalign" => undef,
        "oalsuf" => undef,
        "tmpdir" => "$Common::Config::tmp_dir/seq_cluster",
        "stats" => undef,
        "maxram" => "80%",
	"minsim" => 90,
	"minsize" => 2,
        "cluprog" => "uclust",
        "cluargs" => undef,
        "cloops" => undef,
        "cseqmin" => 3,
        "coffmin" => 60,
        "crowmin" => 60,
        "cbalmin" => 10,
        "corinum" => 1,
        "clobber" => 0,
	"silent" => 0,
	"verbose" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Cluster::cluster_args( $args );

    $clobber = $args->{"clobber"};

    # >>>>>>>>>>>>>>>>>>>>>>> CONVENIENCE VARIABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $silent = $args->{"silent"};

    if ( $silent ) {
        $silent2 = $silent;
    } else {
	$silent2 = $args->{"verbose"} ? 0 : 1;
    }

    $indent = $args->{"verbose"} ? 3 : 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nSequence clustering:\n) ) unless $silent;

    $name = &File::Basename::basename( $conf->iseqs );
    &echo( qq (   Processing $name ... ) ) unless $silent;
    
    $prog = $conf->cluprog;

    if ( $prog =~ /^cd-hit/ )
    {
        &Seq::Cluster::cluster_cdhit(
             {
                 "ifile" => $conf->iseqs,
                 "ofasta" => $conf->ofasta,
                 "oalign" => $conf->oalign,
                 "cluargs" => $conf->cluargs,
                 "minsim" => $conf->minsim,
                 "minsize" => $conf->minsize,
                 "maxram" => $conf->maxram,
                 "clobber" => $clobber,
                 "silent" => $silent2,
                 "indent" => $indent,
             });
    }
    elsif ( $prog =~ /^uclust$/i )
    {
        &Seq::Cluster::cluster_uclust(
             {
                 "ifile" => $conf->iseqs,
                 "oalign" => $conf->oalign,
                 "ofasta" => $conf->ofasta,
                 "ostats" => $conf->ostats,
                 "tmpdir" => $tmp_dir,
                 "cluargs" => $conf->cluargs,
                 "ovlargs" => $conf->ovlargs,
                 "ovlloops" => $conf->ovlloops,
                 "minsim" => $conf->minsim,
                 "minsize" => $conf->minsize,
                 "maxram" => $conf->maxram,
                 "clobber" => $clobber,
                 "silent" => $silent2,
                 "indent" => $indent,
             });
    }
    else {
        &error( qq (Cluster program "$prog" not supported yet) );
    }
    
    &echo_green("done\n", $indent ) unless $silent;

    &echo_bold("Finished\n\n") unless $silent;

    return;
}

sub list_seeds_uclust
{
    # Niels Larsen, April 2010.

    # Returns a list of [ seed id, cluster number, cluster size ] read from 
    # a given .uc uclust output. The clusters are listed last in the .uc file,
    # so we can use the unix 'tail' command - the number of clusters are tiny
    # small compared with the whole list usually.

    my ( $file,
        ) = @_;

    # Returns a list.

    my ( @lines, @line, $line, $total, @counts );

    # Get number of clusters from last line,

    @lines = ();
    &Common::OS::run3_command( "tail -n 1", $file, \@lines );

    $total = ( split " ", $lines[0] )[1];
    $total += 1;   # cluster indices start at 0

    # Get cluster info from bottom lines,

    @lines = ();
    &Common::OS::run3_command( "tail -n $total", $file, \@lines );

    # Create list of hashes,

    foreach $line ( @lines )
    {
        @line = split " ", $line;
        
        push @counts, bless {
            "seq_id" => $line[8],
            "clu_num" => $line[1],
            "seq_count" => $line[2],
        };
    }

    return wantarray ? @counts : \@counts;
}

sub list_seeds_cdhit
{
    # Niels Larsen, April 2010.

    # Returns a list of [ seed id, cluster number, cluster size ] read from a 
    # given .clstr cdhit output. 

    my ( $file,
        ) = @_;

    # Returns a list.

    my ( $fh, $line, @line, $id, $num, $size, @counts );

    $fh = &Common::File::get_read_handle( $file );

    while ( defined ( $line = <$fh> ) )
    {
        chomp $line;
            
        if ( $line =~ /^>Cluster\s+(\d+)$/ )
        {
            if ( defined $num )
            {
                push @counts, bless { 
                    "seq_id" => $id,
                    "clu_num" => $num,
                    "seq_count" => $size,
                };
            }
                
            $num = $1;
        }
        elsif ( $line =~ /^0[^>]+>(.+)\s+\.\.\./ )
        {
            $id = $1;
            $size = 1;
        }
        elsif ( $line =~ /^\d+\s+/ )
        {
            $size += 1;
        }
        else {
            &error( qq (Wrong looking .clstr line -> "$line") );
        }
    }

    $fh->close;
    
    push @counts, bless { 
        "seq_id" => $id,
        "clu_num" => $num,
        "seq_count" => $size,
    };

    return wantarray ? @counts : \@counts;
}

sub cluster_args
{
    # Niels Larsen, March 2010.

    # Checks and expands the cluster routine parameters and does one of two: 
    # 1) if there are errors, these are printed in void context and pushed onto 
    # a given message list in non-void context, 2) if no errors, returns a hash 
    # of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, $ram_total, $ram_max, $suffix, $keyval, $key, $val, 
         $stats_file );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->iseqs ) {
	$args{"iseqs"} = &Common::File::check_files([ $args->iseqs ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", "No input sequence files given"];
    }

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Mandatory alignment output,

    if ( $args->oalign or $args->oalsuf )
    {
        $args{"oalign"} = $args->oalign // $args->iseqs . $args->oalsuf;

        if ( not $args->clobber )
        {
            &Common::File::check_files([ $args{"oalign"} ], "!e", \@msgs );
    
            if ( defined $args{"minsize"} and $args{"minsize"} > 1 ) {
                &Common::File::check_files([ $args{"oalign"} .".small" ], "!e", \@msgs );
            }
        }
    }
    else {
        push @msgs, ["ERROR", "An output alignment file name or suffix must be given" ];
    }

    # Optional fasta seeds output,

    if ( $args->ofasta or $args->ofasuf )
    {
        $args{"ofasta"} = $args->ofasta // $args->iseqs . $args->ofasuf;
        
        if ( not $args->clobber )
        {
            &Common::File::check_files([ $args{"ofasta"} ], "!e", \@msgs );
            &Common::File::check_files([ $args{"ofasta"} .".small" ], "!e", \@msgs );
        }        
    }
    else {
        $args{"ofasta"} = undef;
    }

    &append_or_exit( \@msgs, $msgs );
        
    # Statistics output,

    if ( not $args{"ostats"} = $args->stats )
    {
        $args{"ostats"} = undef;
    }

    $args{"tmpdir"} = $args->tmpdir;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Program and arguments, 

    $args{"cluprog"} = &Registry::Args::prog_name( $args->cluprog, [ "cdhit", "uclust" ], \@msgs );

    if ( $args{"cluprog"} eq "cdhit" )
    {
        push @msgs, ["ERROR", qq (Only uclust works at the moment .. CD-hit cannot create alignments.) ];
        push @msgs, ["INFO", qq (Alternatives are sought, as later versions of uclust has been named ) ];
        push @msgs, ["INFO", qq (usearch which is closed-source and proprietary.) ];
    }
    
    # Minimum cluster similarity and size,

    if ( defined $args->minsim ) {
	$args{"minsim"} = &Registry::Args::check_number( $args->minsim, 70, 100, \@msgs );
    }

    if ( defined $args->minsize ) {
	$args{"minsize"} = &Registry::Args::check_number( $args->minsize, 1, undef, \@msgs );
    }

    # Ram usage maximum,
    
    if ( defined $args->maxram )
    {
        $ram_total = &Common::OS::ram_avail();

        if ( $args->maxram =~ /^(\d+)%$/ )
        {
            $args{"maxram"} = int ( $ram_total * $1 / 100 );
        }
        else
        {
            $ram_max = &Common::Util::expand_number( $args->maxram, \@msgs );

            if ( defined $ram_max )
            {
                $args{"maxram"} = &List::Util::min( $ram_total, $ram_max );
                
                if ( $ram_max < 100000000 ) {
                    push @msgs, ["ERROR", qq (Maximum RAM should be at least 100mb) ];
                }
            }
        }
    }

    $args{"cluargs"} = $args->cluargs;
    $args{"clobber"} = $args->clobber;

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OVERLAP ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Overlap check loop count,
    
    $args{"ovlloops"} = $args->cloops;

    if ( defined $args{"ovlloops"} and $args{"ovlloops"} > 5 ) {
        push @msgs, ["ERROR", qq (Ovlera re-clustering can only be done up to 5 times) ];
    }

    $args{"ovlargs"}->{"seqmin"} = &Registry::Args::check_number( $args->cseqmin, 3, undef, \@msgs );
    $args{"ovlargs"}->{"offpct"} = &Registry::Args::check_number( $args->coffmin, 50, 100, \@msgs );
    $args{"ovlargs"}->{"rowpct"} = &Registry::Args::check_number( $args->crowmin, 50, 100, \@msgs );
    $args{"ovlargs"}->{"balpct"} = &Registry::Args::check_number( $args->cbalmin, 10, 100, \@msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}

sub cluster_cdhit
{
    # Niels Larsen, March 2010.

    # Clusters the sequences in a single file against themselves, using cdhit.

    my ( $args,
	 $msgs,
	) = @_;

    # Returns nothing.

    my ( $defs, $silent, $prog, $clu_args, $cmd, $stdout, $stderr, $mbram, 
         $size, $seq_file, $clu_file, $out_file, $count, $min_sim, $name,
         $min_size, $max_size, $ali_file );

    local $Common::Messages::indent_plain;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $defs = {
        "ifile" => undef,
        "oalign" => undef,
        "ofasta" => undef,
        "cluargs" => "",
        "minsim" => undef,
        "minsize" => undef,
        "maxram" => 1_000_000,
        "clobber" => 0,
        "silent" => 0,
        "indent" => 3,
    };
        
    $args = &Registry::Args::create( $args );

    $seq_file = $args->ifile;
    $ali_file = $args->oalign;
    $out_file = $args->ofasta;

    $prog = "cd-hit-est";
    $clu_args = $args->cluargs;

    $min_sim = sprintf "%.4f", $args->minsim / 100;
    $min_size = $args->minsize;
    $mbram = int ( $args->maxram / 1_000_000 );

    $silent = $args->silent;
    
    if ( not $silent ) {
	$Common::Messages::indent_plain = $args->indent + 3;
	&echo("\n");
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("Clustering sequences ... ") unless $silent;

    $clu_file = Registry::Paths->new_temp_path( "$prog.out" );

    $cmd = "$prog $clu_args -d 100 -c $min_sim -i $seq_file -o $clu_file";

    if ( defined $mbram ) {
        $cmd .= " -M $mbram";
    }

    &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr );

    &echo_green("done\n") unless $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTA OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $out_file )
    {
        $name = &File::Basename::basename( $out_file );

        &echo("Writing $name ... ") unless $silent;

        $count = &Seq::Cluster::write_fasta_seeds(
            {
                "prog" => $prog,
                "iseqs" => $seq_file,                   # Original input sequences
                "iclus" => "$clu_file.clstr",           # cdhit output
                "oseqs" => $out_file,                   # Output sequences, with sizes
                "minsize" => $min_size,                 # Minimum cluster size
                "maxsize" => undef,                     # Maximum cluster size - any
            });

        &echo_done( "$count\n") unless $silent;

        $max_size = $min_size - 1;
        &echo("Writing $name.small ... ") unless $silent;

        $count = &Seq::Cluster::write_fasta_seeds(
            {
                "prog" => $prog,                        # Program name
                "iseqs" => $seq_file,                   # Original input sequences
                "iclus" => "$clu_file.clstr",           # cdhit output
                "oseqs" => "$out_file.small",           # Output sequences, with sizes
                "minsize" => undef,                     # Minimum cluster size - any
                "maxsize" => $max_size,                 # Maximum cluster size
            });
        
        &echo_done( "$count\n") unless $silent;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE SCRATCH FILES <<<<<<<<<<<<<<<<<<<<<<<

    &echo("Deleting scratch files ... ") unless $silent;

    &Common::File::delete_file( $clu_file );
    &Common::File::delete_file( "$clu_file.bak.clstr" );
    &Common::File::delete_file( "$clu_file.clstr" );

    &echo_green("done\n") unless $silent;
    
    return;
}

sub cluster_uclust
{
    # Niels Larsen, March 2010.

    # Clusters the sequences in a single fasta file against themselves, using
    # uclust.

    my ( $args,
	 $msgs,
	) = @_;

    # Returns nothing.
    
    my ( $defs, $silent, $seq_file, $clu_file, $count1, $count2, $min_sim, 
         $name, $out_file, $ali_file, $clobber, @msgs, $ovl_max, $ovl_args,
         $ovl_done, $ovl_count, @ovl_info, @ovl_ids, $seq_file_orig, $info,
         $fhs, $fh, $ali_id, $ali_seqs, @locs, $indent, $stdout, $ali_seq,
         $seq_clu_in, $seq_clu_out, $old_id, %seen, $key, $stat_file, 
         @stats, $counts_in, $counts_out, $count, $sname, $stats, $time_start,
         $seconds, $text, $sfh, $tmp_dir );

    local $Common::Messages::indent_plain;
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifile" => undef,
        "oalign" => undef,
        "ofasta" => undef,
        "ostats" => undef,
        "tmpdir" => "$Common::Config::tmp_dir/seq_cluster_". $$,
        "cluargs" => "",
        "ovlargs" => {},
        "ovlloops" => undef,
        "minsim" => undef,
        "minsize" => undef,
        "maxram" => 1_000_000,
        "clobber" => 0,
        "silent" => 0,
        "indent" => 3,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    $seq_file = $args->ifile;
    $ali_file = $args->oalign;
    $out_file = $args->ofasta;
    $stat_file = $args->ostats;
    $tmp_dir = $args->tmpdir;

    &Common::File::create_dir( $tmp_dir );

    $ovl_max = $args->ovlloops;
    $ovl_done = 0;
    
    if ( $ovl_max ) {
        $clobber = 1;
    } else {
        $clobber = $args->clobber;
    }

    $Common::Messages::silent = $args->silent;

    $indent = $args->indent + 3;
    &echo("\n");

    $ali_seqs = [];
    
    $seq_clu_in = "$seq_file.cluin";
    $seq_clu_out = "$seq_file.cluout";

    &Common::File::create_link( $seq_file, $seq_clu_in, 0 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT COUNT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stat_file )
    {
        &echo( qq (Counting sequence input ... ), $indent );
        
        $counts_in = &Seq::Stats::count_seq_file( $seq_file );

        $count = $counts_in->seq_count_orig // $counts_in->seq_count;
        &echo_done( "$count\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OVERLAP ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ovl_args = {
        "seqmin" => 3,
        "offpct" => 60,       # How much sequences are off to either side
        "rowpct" => 60,       # How many rows sequences are off in 
        "balpct" => 10,       # Minimum right/left off proportion
        "usize" => 1,         # Include cluster numbers in calculation
        "clobber" => 0,
        "silent" => 1,
        "indent" => 3,
    };

    foreach $key ( keys %{ $args->ovlargs } )
    {
        if ( exists $ovl_args->{ $key } ) {
            $ovl_args->{ $key } = $args->ovlargs->{ $key };
        } else {
            &error( qq (Wrong looking argument -> "$key") );
        }

        $ovl_args->{ $key } =~ s/%//;
    }

    $time_start = &time_start();

  CLUSTER:

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN UCLUST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This produces an alignment output from a given fasta input sequence file,

    &Seq::Cluster::run_uclust(
      {
          "ifile" => $seq_clu_in,
          "oalign" => $ali_file,
          "tmpdir" => $tmp_dir,
          "cluargs" => $args->cluargs,
          "minsim" => $args->minsim,
          "maxram" => $args->maxram,
          "clobber" => $clobber,
          "silent" => 1,
          "indent" => 6,
      }, \@msgs );
    
    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>> OPTIONAL OVERLAP CHECK <<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $ovl_max and $ovl_done < $ovl_max )
    {
        # First index the output alignment to the sequence entry level,

        &echo( qq (Alignment checking ...\n), $indent );

        &echo( qq (Indexing alignments ... ), $indent+3 );
        
        &Ali::Storage::create_indices(
             {
                 "ifiles" => [ $ali_file ],
                 "seqents" => 1,
                 "seqstrs" => 0,
                 "silent" => 1,
                 "clobber" => 1,
             });
        
        &echo_done( "done\n" );

        # The check for non-overlaps. Returned is a list of hashes with these 
        # keys:
        # 
        #  ali_id => alignment id 
        #  off_ids => ids of sequences that are off the middle
        #  cent_ids => ids of sequences that are not off 
        #  row_total => total number of rows in the alignment
        
        &echo( qq (Finding non-overlaps ... ), $indent+3 );
        
        @ovl_info = &Ali::Chimera::chimeras_uclust( $ali_file, $ovl_args );

        $ovl_count = ( scalar @ovl_info ) || "none";
        &echo_done( "$ovl_count\n" );

        if ( @ovl_info )
        {
            # >>>>>>>>>>>>>>>>>>>>> SAVE CENTERED PARTS <<<<<<<<<<<<<<<<<<<<<<<

            # Fetch the non-chimeric parts of the chimeric alignments before 
            # reclustering,

            &echo( qq (Removing non-overlap seeds ... ), $indent+3 );

            @locs = ();

            foreach $info ( @ovl_info )
            {
                $ali_id = $info->{"ali_id"};
                push @locs, map { "$ali_id:$_" } @{ $info->{"cent_ids"} };
            }

            $fhs = &Ali::Storage::get_handles( $ali_file );

            push @{ $ali_seqs }, &Ali::Storage::fetch_aliseqs( $fhs, { "locstrs" => \@locs } );

            &Ali::Storage::close_handles( $fhs );

            &echo_done( (scalar @locs) ."\n" );

            # >>>>>>>>>>>>>>>>>>>>>>> WRITE NEW INPUT <<<<<<<<<<<<<<<<<<<<<<<<<

            # Next write a new cluster input sequence file without any of the 
            # sequences from above,

            &echo( qq (Writing new cluster input ... ), $indent+3 );

            &Seq::Clean::filter_id(
                 {
                     "iseqs" => $seq_clu_in,
                     "oseqs" => $seq_clu_out,
                     "skipids" => [ map { @{ $_->{"cent_ids"} } } @ovl_info ],
                     "silent" => 1,
                     "clobber" => 1,
                 });

            &echo_done( "done\n" );

            &Common::File::delete_file( $seq_clu_in );
            &Common::File::rename_file( $seq_clu_out, $seq_clu_in );

            $ovl_done += 1;

            goto CLUSTER;
        }
        else {
            $ovl_done = $ovl_max;
        }
    }

    # >>>>>>>>>>>>>>>>>>> APPEND SAVED ALIGNMENT PARTS <<<<<<<<<<<<<<<<<<<<

    # The last uclust output alignments file contains only the reads that 
    # dont create chimeric alignments; the rest are in memory as a list of 
    # aligned sequence entries. We must now append the latter to the file;
    # but the alignment ids are not the same anymore, so we get the highest
    # file id and increment from there,
    
    &Common::OS::run3_command( "tail -n 2 $ali_file", undef, \$stdout );
    
    if ( $stdout =~ />(\d+)/ ) {
        $ali_id = $1;
    } else {
        &error( qq (Wrong looking last entry -> "$stdout") );
    }
    
    $fh = &Common::File::get_append_handle( $ali_file );
    
    foreach $ali_seq ( @{ $ali_seqs } )
    {
        if ( $ali_seq =~ /^>(\d+)/ )
        {
            $old_id = $1;
            
            if ( not $seen{ $old_id } )
            {
                $seen{ $old_id } = 1;
                $ali_id += 1;
            }
            
            $ali_seq =~ s/^>\d+/>$ali_id/;
            
            $fh->print( $ali_seq );
        }
        else {
            &error( qq (Wrong looking sequence entry -> "$ali_seq") );
        }
    }
    
    &Common::File::close_handle( $fh );

    # >>>>>>>>>>>>>>>>>>>>>>>> DELETE SCRATCH FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::File::delete_file( $seq_clu_in );
    &Ali::Storage::delete_indices({ "paths" => [ $ali_file ], "silent" => 1 });

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTA OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $out_file )
    {
        $name = &File::Basename::basename( $out_file );

        if ( not &Ali::Storage::is_indexed( $ali_file ) )
        {
            &echo( qq (Indexing alignments ... ), $indent+3 );
            
            &Ali::Storage::create_indices(
                 {
                     "ifiles" => [ $ali_file ],
                     "seqents" => 1,
                     "seqstrs" => 0,
                     "silent" => 1,
                     "clobber" => 1,
                 });
            
            &echo_done( "done\n" );
        }
        
        &echo("Writing seeds to $name ... ", $indent );

        ( $count1, $count2 ) = &Seq::Cluster::write_uclust_seeds(
            {
                "iseqs" => $seq_file,             # Original input sequences
                "oseqs" => $out_file,             # Output sequences, with sizes
                "cluali" => $ali_file,            # uclust output alignment
                "minsize" => $args->minsize,      # Minimum cluster size
                "clobber" => $clobber,            # Delete previous output
            });
        
        &echo_done( "$count1\n");
        
        &echo( qq (Writing seeds to $name.small ... ), $indent );
            
        if ( $count2 > 0 ) {
            &echo_done( "$count2\n" );
        } else {
            &echo_yellow( "none\n" );
        }
    }

    $seconds = &time_elapsed() - $time_start;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $stat_file )
    {
        &echo( qq (Counting alignments ... ), $indent );

        $counts_out = &Ali::IO::count_alis( $ali_file );

        $count = $counts_out->ali_count;
        &echo_done( "$count\n" );

        $sname = &File::Basename::basename( $stat_file );
        &echo( qq (Writing $sname ... ), $indent );

        $stats->{"name"} = "sequence-clustering";
        $stats->{"title"} = "Sequence clustering";
            
        $stats->{"ifile"} = { "title" => "Input file", "value" => &Common::File::full_file_path( $seq_file ) };
        $stats->{"ofile"} = { "title" => "Output file", "value" => &Common::File::full_file_path( $ali_file ) };

        $stats->{"params"} = [
            {
                "title" => "Minimum seed similarity",
                "value" => $args->minsim,
            },{
                "title" => "Mininum cluster size",
                "value" => $args->minsize,
            }];
            
        $stats->{"steps"}->[0] = 
        {
            "iclu" => $counts_in->{"seq_count"},
            "iseq" => $counts_in->{"seq_count_orig"} // $counts_in->{"seq_count"},
            "oclu" => $counts_out->{"ali_count"},
            "oseq" => $counts_out->{"seq_count_orig"} // $counts_out->{"seq_count"},
        };
        
        $stats->{"seconds"} = $seconds;
        $stats->{"finished"} = &Common::Util::epoch_to_time_string();
            
        $text = &Seq::Cluster::write_stats_file( $stat_file, $stats );
            
        $sfh = &Common::File::get_append_handle( $stat_file );
        $sfh->print( $text );
        &Common::File::close_handle( $sfh );
            
        &echo_done( "done\n" );
    }

    &Common::File::delete_dir_tree( $tmp_dir );

    &echo("      Run time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );

    return;
}

sub run_uclust
{
    # Niels Larsen, March 2010.

    # Clusters the sequences in a single fasta file against themselves, using
    # uclust.

    my ( $args,
	 $msgs,
	) = @_;

    # Returns nothing.
    
    my ( $defs, $silent, $prog, $clu_args, $cmd, $stdout, $stderr, $mbram, 
         $seq_file, $clu_file, $min_sim, $seq_sorted, $ucf_file, $name, 
         $ali_file, $split_size, $tmp_dir );

    local $Common::Messages::indent_plain;
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifile" => undef,
        "oalign" => undef,
        "cluargs" => "",
        "minsim" => undef,
        "maxram" => 1_000_000,
        "clobber" => 0,
        "silent" => 0,
        "indent" => 3,
    };
        
    $args = &Registry::Args::create( $args );

    $seq_file = $args->ifile;
    $ali_file = $args->oalign;
    $tmp_dir = $args->tmpdir;

    $Common::Messages::indent_plain = $args->indent;
    $Common::Messages::silent = $args->silent;
    
    $prog = "uclust";
    $clu_args = $args->cluargs // "";

    $min_sim = sprintf "%.4f", $args->minsim / 100;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SORT BY LENGTH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sort input sequences by length,

    &echo("Sorting input by length ... ");

    $seq_sorted = "$tmp_dir/$prog-$$.in.sorted";

    if ( defined $args->maxram ) {
        $split_size = int ( $args->maxram / 2_000_000 );
    } 

    if ( defined $split_size and $split_size < ( ( -s $seq_file ) + 1000 ) / 2_000_000 )
    {
        # A segfault in uclust prevents absolute paths be given with --tmpdir,
        # so we let them be written in the default directory,

        $cmd = "$prog --mergesort $seq_file --output $seq_sorted --split $split_size";
    }
    else {
        $cmd = "$prog --sort $seq_file --output $seq_sorted";
    }

    &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr );

    &echo_green("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("Clustering sequences ... ");

    $clu_file = "$tmp_dir/$prog-$$.out";

    $cmd = "$prog $clu_args --id $min_sim --input $seq_sorted --uc $clu_file";

    &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr );

    &echo_green("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ALIGN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $ali_file )
    {
        $name = &File::Basename::basename( $ali_file );
        &echo("Creating $name ... ");
        
        $ucf_file = "$tmp_dir/$prog-$$.ucfasta";
        $cmd = "$prog --uc2fasta $clu_file --input $seq_sorted --output $ucf_file";
        &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr );
        
        $cmd = "$prog --staralign $ucf_file --output $ali_file";
        &Common::OS::run3_command( $cmd, undef, \$stdout, \$stderr );
        
        &echo_green("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> DELETE SCRATCH FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("Deleting scratch files ... ");

    &Common::File::delete_file( $seq_sorted );
    &Common::File::delete_file( $clu_file );

    &Common::File::delete_file_if_exists( $ucf_file ) if defined $ucf_file;

    &echo_green("done\n");
    
    return;
}

sub write_stats_file
{
    # Niels Larsen, February 2012. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $ifile, $ofile, $title, $value, $steps, $step, 
         $fstep, $time, $iclu, $iseq, $oseq, $oclu, $seqdif, $cludif, 
         $seqpct, $clupct, $lstep, $item );

    $ifile = &File::Basename::basename( $stats->{"ifile"}->{"value"} );
    $ofile = &File::Basename::basename( $stats->{"ofile"}->{"value"} );
    $steps = $stats->{"steps"};

    $time = &Time::Duration::duration( $stats->{"seconds"} );
    
    # >>>>>>>>>>>>>>>>>>>>>>>> FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $iclu = $steps->[0]->{"iclu"};
    $iseq = $steps->[0]->{"iseq"};

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
      file = $stats->{"ifile"}->{"title"}\t$ifile
      file = $stats->{"ofile"}->{"title"}\t$ofile
      <menu>
         title = Parameters
);

    foreach $item ( @{ $stats->{"params"} } )
    {
        $title = $item->{"title"};
        $value = $item->{"value"};
        
        $text .= qq (         item = $title: $value\n);
    }

    $text .= qq (      </menu>
      date = $stats->{"finished"}
      secs = $stats->{"seconds"}
      time = $time
   </header>

   <table>
      title = Cluster and sequence counts
      colh = \tClusters\t&Delta;\t&Delta; %\tSeqs\t&Delta;\t&Delta; %
      trow = Input\t$iclu\t\t\t$iseq\t\t
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $step ( @{ $steps } )
    {
        $iclu = $step->{"iclu"};
        $iseq = $step->{"iseq"};
        $oclu = $step->{"oclu"};
        $oseq = $step->{"oseq"};
        
        $cludif = $oclu - $iclu;
        $seqdif = $oseq - $iseq;

        $clupct = ( sprintf "%.1f", 100 * $cludif / $iclu );
        $seqpct = ( sprintf "%.1f", 100 * $seqdif / $iseq );

        $text .= qq (      trow = Output\t$oclu\t$cludif\t$clupct\t$oseq\t$seqdif\t$seqpct\n);
    }

    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_stats_sum
{
    # Niels Larsen, October 2012. 

    # Reads the content of the given list of statistics files and generates a 
    # summary table. The input files were written by write_stats_file above. The 
    # output file has a tagged format understood by Recipe::Stats::html_body. A
    # string is returned in list context, otherwise it is written to the given 
    # file or STDOUT. 

    my ( $files,       # Input statistics files
         $sfile,       # Output file
        ) = @_;

    # Returns a string or nothing.
    
    my ( $stats, $text, $file, $rows, $secs, @row, @table, $in_seqs, $time,
         $clu_pct, $str, $row, $ofile, $params, $items, $in_reads, $out_clus,
         $out_reads, @dates, $date );

    # Create table array by reading all the given statistics files and getting
    # values from them,

    @table = ();
    $secs = 0;

    foreach $file ( @{ $files } )
    {
        $stats = &Recipe::IO::read_stats( $file )->[0];

        $rows = $stats->{"headers"}->[0]->{"rows"};

        $ofile = $rows->[1]->{"value"};
        $secs += $rows->[4]->{"value"};

        $rows = $stats->{"tables"}->[0]->{"rows"};
        
        @row = split "\t", $rows->[0]->{"value"};
        ( $in_seqs, $in_reads ) = @row[1,4];

        @row = split "\t", $rows->[1]->{"value"};
        ( $out_clus, $out_reads ) = @row[1,4];

        $in_seqs =~ s/,//g;
        $in_reads =~ s/,//g;
        $out_clus =~ s/,//g;
        $out_reads =~ s/,//g;

        push @table, [ "file=$ofile", $in_reads, $in_seqs, 
                       $out_clus, 100 * ( $in_seqs - $out_clus ) / $in_seqs, $out_reads,
        ];
    }

    # Sort descending by input sequences, 

    @table = sort { $b->[2] <=> $a->[2] } @table;
    
    # Calculate totals,

    $in_reads = &List::Util::sum( map { $_->[1] } @table );
    $in_seqs = &List::Util::sum( map { $_->[2] } @table );
    $out_clus = &List::Util::sum( map { $_->[3] } @table );
    $clu_pct = "-". sprintf "%.1f", 100 * ( $in_seqs - $out_clus ) / $in_seqs;
    $out_reads = &List::Util::sum( map { $_->[5] } @table );

    # Re-read any of the stats files, to get parameters and settings that are the
    # same for all files,

    $stats = bless &Recipe::IO::read_stats( $files->[0] )->[0];

    $time = &Time::Duration::duration( $secs );
    $date = &Recipe::Stats::head_type( $stats, "date" );
    
    $params = $stats->{"headers"}->[0]->{"rows"}->[2];

    # Format table,

    $items = "";
    map { $items .= qq (           item = $_->{"value"}\n) } @{ $params->{"items"} };
    chomp $items;

    $text = qq (
<stats>
   title = $stats->{"title"}
   <header>
       <menu>
           title = $params->{"title"}
$items
       </menu>
       hrow = Total input sequences\t$in_seqs
       hrow = Total output clusters\t$out_clus ($clu_pct%)
       hrow = Total input original reads\t$in_reads
       hrow = Input output original reads\t$out_reads
       date = $date
       secs = $secs
       time = $time
   </header>  
   <table>
      title = Cluster sequence and reads statistics
      colh = Output alignments\tIn-reads\tIn-seqs\tOut-clus\t&Delta; %\tOut-reads
);
    
    foreach $row ( @table )
    {
        $row->[1] //= 0;
        $row->[2] //= 0;
        $row->[3] //= 0;
        $row->[4] = "-". sprintf "%.1f", $row->[4];
        $row->[5] //= 0;

        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }

    $text .= qq (   </table>\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_uclust_seeds
{
    # Niels Larsen, March 2010.

    # Extracts seed sequences from a uclust alignment file and writes a fasta
    # file with cluster sizes in the headers. Returns the number of clusters.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns integer. 

    my ( $defs, $min_size, $seq_file, $ali_file, $name, $ali_id, $ali_str, 
         $ali_fhs, $clu_size, $hdr_regex, $out_file, $bout_fh, $sout_fh, 
         $hdr_str, $seq_str, $bcount, $scount );

    $defs = {
        "iseqs" => undef,
        "oseqs" => undef,
        "cluali" => undef,
        "minsize" => undef,
        "clobber" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );

    $seq_file = $args->iseqs;
    $ali_file = $args->cluali;
    $out_file = $args->oseqs;

    $min_size = $args->minsize;

    $ali_fhs = &Ali::Storage::get_handles( $ali_file, { "access" => "read" } );

    &Common::File::delete_file_if_exists( $out_file ) if $args->clobber;
    $bout_fh = &Common::File::get_write_handle( $out_file );

    &Common::File::delete_file_if_exists( "$out_file.small" ) if $args->clobber;
    $sout_fh = &Common::File::get_write_handle( "$out_file.small" );

    $ali_id = 0;
    $bcount = 0;
    $scount = 0;

    while ( $ali_str = &Ali::Storage::fetch_aliseqs( $ali_fhs, { "locs" => [[ $ali_id ]], "print" => 0 } )->[0] )
    {
        $clu_size = 0;

        while ( $ali_str =~ />([^\n]+)/g )
        {
            $hdr_str = $1;

            if ( $hdr_str =~ /seq_count=(\d+)/ ) {
                $clu_size += $1;
            } else {
                $clu_size += 1;
            }
        }
        
        if ( $ali_str =~ /\n([^\n]+)\n*$/ )
        {
            $seq_str = $1;
            $seq_str =~ s/[^A-Za-z]+//g;
            
            if ( $clu_size >= $min_size )
            {
                $bcount += 1;
                $bout_fh->print( ">$ali_id seq_count=$clu_size\n$seq_str\n" );
            }
            else
            {
                $sout_fh->print( ">$ali_id seq_count=$clu_size\n$seq_str\n" );
                $scount += 1;
            }
        }
        else {
            &error( qq (Could not get seed sequence from alignment string) );
        }

        $ali_id += 1;
    }

    &Ali::Storage::close_handles( $ali_fhs );

    &Common::File::close_handle( $bout_fh );
    &Common::File::close_handle( $sout_fh );

    return ( $bcount, $scount );
}

1;

__END__

    # # >>>>>>>>>>>>>>>>>>>>>>>>> INDEX SEQUENCE INPUT <<<<<<<<<<<<<<<<<<<<<<<<<<

    # if ( not &Seq::Storage::is_indexed( $seq_file ) )
    # {
    #     $name = &File::Basename::basename( $seq_file );
    #     &echo( qq (Indexing $name sequences ... ) );

    #     &Seq::Storage::create_indices(
    #          {
    #              "ifiles" => [ $seq_file ],
    #              "progtype" => "fetch",
    #              "stats" => 0,
    #              "silent" => 1,
    #          });
        
    #     &echo_done( "done\n" );
    # }
    
