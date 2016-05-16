package Seq::Fluid;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Fluidigm related sequence routines.
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @EXPORT_OK );
require Exporter;

use Time::Duration qw ( duration );
use Fcntl qw( :flock SEEK_SET SEEK_CUR SEEK_END );

@EXPORT_OK = qw (
                 &check_demul_paths
                 &close_demul_files
                 &demul_primers
                 &demul_primers_args
                 &init_stats_match
                 &match_primers
                 &open_demul_files
                 &score_primer_pairs
                 &score_primer_singles
                 &set_demul_paths
                 &write_pairs
                 &write_seqs_dict
                 &write_singles_fwd
                 &write_singles_rev
                 &write_stats_match
                 &write_stats_primer
);

use Common::Config;
use Common::Messages;

use Registry::Args;
use Bio::Patscan;

use Seq::Common;
use Seq::IO;

use Recipe::IO;
use Recipe::Steps;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Out_prefix, $Max_int );

$Out_prefix = "BION";
$Max_int = 2 ** 30;

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_demul_paths
{
    # Niels Larsen, April 2013. 

    my ( $paths,
         $msgs,
        ) = @_;

    my ( @msgs, @paths, $pridir, $fname );

    foreach $fname ( keys %{ $paths } )
    {
        foreach $pridir ( keys %{ $paths->{ $fname } } )
        {
            push @paths, $paths->{ $fname }->{ $pridir };
        }
    }

    &Common::File::check_files( \@paths, "!e", \@msgs );

    &append_or_exit( \@msgs, $msgs );

    return;
}

sub close_demul_files
{
    # Niels Larsen, April 2013. 

    # Close handles opened by open_demul_files. 

    my ( $ofhs,
        ) = @_;

    my ( $dir, $ofile, $count );

    $count = 0;

    foreach $dir ( keys %{ $ofhs } )
    {
        foreach $ofile ( keys %{ $ofhs->{ $dir } } )
        {
            if ( ref $ofhs->{ $dir }->{ $ofile } )
            {
                &Common::File::close_handle( $ofhs->{ $dir }->{ $ofile } );
                $count += 1;
            }
        }
    }

    return $count;
}
    
sub demul_primers
{
    # Niels Larsen, March 2013.

    # Creates new sequence files in primer sub-directories. Reads sequence 
    # files, matches primer patterns against these, and writes a copy of each
    # matching sequence to a sub-directory named after the primer it matches.
    # If there are 10 input files and 20 primers, then the result is 10 files
    # in each of 20 directories. All output sequences have "fwd_primer" and 
    # "rev_primer" fields added to their info field. Input primers, their 
    # range and orientations are defined in a given table.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $recipe, $defs, $conf, @f_pats, @r_pats, $io, $ifile, $ofile, $format,
         $misfile, $reader, $writer, $ifh, $ofh, $mfh, $seqs, $pat, $cseq,
         $locs, $clobber, $readbuf, $seq, $iname, $out_seqs, $pridist, $stats,
         $all_tot, $fwd_tot, $rev_tot, $mis_tot, $hit_tot, $hit_pct, $fr_hits,
         $f_hits, $r_hits, $seconds, $time_start, $both_tot, $out_tot,
         $mis_seqs, $count, $i, $j, $k, $prifile, $outdir, $subdir, $forward,
         $reverse, $pairs, $ofhs, @tuples );
    
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }
    
    $defs = {
        "recipe" => undef,
        "ifiles" => [],
        "format" => undef,
        "prifile" => undef,
        "pridist" => undef,
        "forward" => 1,
        "reverse" => 1,
        "pairs" => 1,
        "outdir" => undef,
        "outsuf" => ".primap",
        "outpre" => $Out_prefix,
        "stats" => undef,
        "readbuf" => 1000,
        "replace" => 0,
        "clobber" => 0,
        "silent" => 0,
    };
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE CONFIG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check and expand all arguments into a config hash that contains settings
    # the routines want,
    
    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Fluid::demul_primers_args( $args );

    $clobber = $conf->clobber;
    $readbuf = $conf->readbuf;
    $pridist = $conf->pridist // $Max_int;
    $outdir = $conf->outdir;

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold("\nPhylo-primer matching:\n");

    &echo("   Initializing internals ... ");

    @f_pats = grep { $_->{"orient"} eq "forward" } @{ $conf->{"patlist"} };
    @r_pats = grep { $_->{"orient"} eq "reverse" } @{ $conf->{"patlist"} };

    $stats = &Seq::Fluid::init_stats_match( $conf );

    if ( $clobber )
    {
        foreach $subdir ( @{ $conf->odirs } ) {
            &Common::File::delete_dir_tree_if_exists("$outdir/$subdir");
        }
    }

    foreach $subdir ( @{ $conf->odirs } ) {
        &Common::File::create_dir_if_not_exists("$outdir/$subdir");
    }

    $fr_hits = {};
    $f_hits = {};
    $r_hits = {};

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $time_start = &time_start();

    $forward = $conf->forward;
    $reverse = $conf->reverse;
    $pairs = $conf->pairs;
    
    foreach $ifile ( @{ $conf->ifiles } )
    {
        $iname = &File::Basename::basename( $ifile );
        &echo("   Matching $iname ... ");

        $ifh = &Common::File::get_read_handle( $ifile );
        $ofhs = &Seq::Fluid::set_demul_paths([ $ifile ], $conf );
        $mfh = &Common::File::get_write_handle( "$outdir/$iname.miss" );

        $format = &Seq::IO::detect_format( $ifile );
        $reader = &Seq::IO::get_read_routine( $ifile, $format );
        $writer = &Seq::IO::get_write_routine( $format );

        flock $ifh, LOCK_SH;

        $all_tot = 0;
        $fwd_tot = 0;
        $rev_tot = 0;
        $both_tot = 0;
        $mis_tot = 0;

        no strict "refs";
        
        while ( $seqs = $reader->( $ifh, $readbuf ) )
        {
            # >>>>>>>>>>>>>>>>>>>>> MATCH AND ANNOTATE <<<<<<<<<<<<<<<<<<<<<<<<

            # Matches forward and reverse primers against a list of sequences, 
            # all against all. Annotation is added to the sequence info fields:
            # "fwd_primer=value" or "rev_primer=value" where value is the primer
            # name,
            
            &Seq::Fluid::match_primers(
                 $seqs, 
                 bless {
                     "fpats" => \@f_pats,
                     "rpats" => \@r_pats,
                     "maxbeg" => $pridist,
                 });

            # >>>>>>>>>>>>>>>>>>>>>>> CREATE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<

            # Divide sequences into those with match, and without. If $frmatch
            # is set then matches must be pairs,

            &Seq::Fluid::write_pairs( $ofhs->{"$iname.FR"}, $seqs, $writer ) if $pairs;
            &Seq::Fluid::write_singles_fwd( $ofhs->{"$iname.F"}, $seqs, $writer ) if $forward;
            &Seq::Fluid::write_singles_rev( $ofhs->{"$iname.R"}, $seqs, $writer ) if $reverse;

            $mis_seqs = [ grep { $_->{"info"} !~ /(fwd|rev)_primer=/ } @{ $seqs } ];
            
            if ( @{ $mis_seqs } )
            {
                no strict "refs";
                $writer->( $mfh, $mis_seqs );
            }

            # >>>>>>>>>>>>>>>>>>>>>> INCREMENT COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<

            # Count pairs, single forward and single reverse matches,
           
            foreach $seq ( @{ $seqs } )
            {
                $fwd_tot += &Seq::Fluid::score_primer_singles( $seq, "fwd_primer", $f_hits );
                $rev_tot += &Seq::Fluid::score_primer_singles( $seq, "rev_primer", $r_hits );

                $both_tot += &Seq::Fluid::score_primer_pairs( $seq, $fr_hits );
            }

            # Remember totals for input, output, those that didn't quality and
            # those without any matches,

            $all_tot += scalar @{ $seqs };
            $out_tot += scalar @{ $seqs } - scalar @{ $mis_seqs };
            $mis_tot += scalar @{ $mis_seqs };
        }

        &Common::File::close_handle( $mfh );
        &Seq::Fluid::close_demul_files( $ofhs );
        &Common::File::close_handle( $ifh );

        push @{ $stats->{"counts"} }, {
            "oname" => &File::Basename::basename( $ifile ),
            "alltot" => $all_tot,
            "fwdtot" => $fwd_tot,
            "revtot" => $rev_tot,
            "bothtot" => $both_tot,
            "matches" => $all_tot - $mis_tot,
            "mistot" => $mis_tot,
        };

        $hit_tot = $all_tot - $mis_tot;
        $hit_pct = sprintf "%.2f", 100 * $hit_tot / $all_tot;

        &echo_done( "$hit_tot ($hit_pct%)\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>> DELETE EMPTY DIRECTORIES <<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $subdir ( @{ $conf->odirs } ) {
        &Common::File::delete_dir_if_empty("$outdir/$subdir");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CALCULATE TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $all_tot = &List::Util::sum( map { $_->{"alltot"} } @{ $stats->{"counts"} } );
    $mis_tot = &List::Util::sum( map { $_->{"mistot"} } @{ $stats->{"counts"} } );

    $stats->{"totals"} = {
        "iseqs" => $all_tot,
        "misses" => $mis_tot,
        "matches" => $all_tot - $mis_tot,
        "matchpct" => sprintf "%.2f", 100 * ( $all_tot - $mis_tot ) / $all_tot,
    };

    $stats->{"patlist"} = [ map { $_->{"name"} } @{ $conf->{"patlist"} } ];
    $stats->{"patlist"} = &Common::Util::uniqify( $stats->{"patlist"} );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CONSOLE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "   Input sequence count ... " );
    &echo_done( $stats->{"totals"}->{"iseqs"} ."\n" );

    &echo( "   Primer matches total ... " );

    &echo_done( $stats->{"totals"}->{"matches"} ." (". $stats->{"totals"}->{"matchpct"} .")\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>> WRITE PRIMER MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Writing match tables ... ");

    @tuples = ();
    push @tuples, [ "Single forward primer", $f_hits ] if $forward;
    push @tuples, [ "Single reverse primer", $r_hits ] if $reverse;
    push @tuples, [ "Paired forward / reverse primer", $fr_hits ] if $pairs;

    &Seq::Fluid::write_stats_primer(
        $stats->{"odir"}->{"value"} ."/". &File::Basename::basename( $conf->mapfile ),
        $stats->{"patlist"},
        \@tuples
        );
    
    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $seconds = &time_elapsed() - $time_start;

    $stats->{"seconds"} = $seconds;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    &echo( "   Writing statistics ... " );

    $prifile = $stats->{"odir"}->{"value"} ."/". &File::Basename::basename( $conf->prifile ) .".txt";
    &Common::File::copy_file( $conf->prifile, $prifile, 1 );

    &Common::File::delete_file_if_exists( $conf->statfile );
    &Seq::Fluid::write_stats_match( $conf, $stats );

    &echo_done("done\n");

    &echo_bold("Finished\n\n");

    return;
}

sub demul_primers_args
{
    # Niels Larsen, March 2013.
    
    # Checks and expands the match routine parameters and creates a config 
    # hash that is convenient for the caller. 

    my ( $args,      # Arguments
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $ifile, $ofile, $format, @paths, $seqfiles, $conf, $file,
         $basename, $statfile, $barfile, $pridir, @dirs, $dir, $outsuf,
         @files, $pat, $outpre, $outdir, $subdir, $ofiles, $odirs );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf = bless {
        "ifiles" => undef,
        "prifile" => undef,
        "patlist" => undef,
        "forward" => $args->forward,
        "reverse" => $args->reverse,
        "pairs" => $args->pairs,
        "outdir" => $args->outdir,
        "outsuf" => $args->outsuf,
        "outpre" => $args->outpre,
        "odirs" => undef,
        "statfile" => undef,
        "mapfile" => undef,
        "pridist" => $args->pridist,
        "readbuf" => $args->readbuf,
        "silent" => $args->silent,
        "clobber" => $args->clobber,
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Are input files all readable,

    &Common::File::check_files( $args->ifiles, "efr", \@msgs );
    &append_or_exit( \@msgs );

    # Create a list of input/output files and their formats, 
    
    if ( @{ $args->ifiles } )
    {
        &Common::File::check_files([ $args->ifiles ], "efr", \@msgs );
        &append_or_exit( \@msgs );

        $conf->ifiles( $args->ifiles );
    }
    else {
        push @msgs, ["ERROR", qq (No input sequence files given) ];
    }
    
    # Check primer table,

    if ( defined $args->prifile ) {
	&Common::File::check_files([ $args->prifile ], "efr", \@msgs );
    } else {
        push @msgs, ["ERROR", "No input primer table given." ];
    }

    &append_or_exit( \@msgs );
    $conf->prifile( $args->prifile );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PRIMER PATTERNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf->patlist([ &Seq::IO::read_table_primers( $args->prifile, \@msgs ) ]);
    
    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check output prefix, 

    if ( not defined $args->outpre ) {
        push @msgs, ["ERROR", qq (Output file prefix must be given) ];
    }

    &append_or_exit( \@msgs );
    $conf->outpre( $args->outpre );

    # Check directory,
    
    if ( defined $args->outdir )
    {
        if ( not $conf->clobber and not -d ( $outdir = $args->outdir ) ) {
            push @msgs, ["ERROR", qq (Output directory does not exist -> "$outdir") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (An output directory must be given, but can be ".") ];
    }

    &append_or_exit( \@msgs );
    $conf->outdir( $args->outdir );

    # Check that output files do not exist, unless clobber is set,

    if ( not $conf->clobber )
    {
        $ofiles = &Seq::Fluid::set_demul_paths( $conf->ifiles, $conf );
        &Seq::Fluid::check_demul_paths( $ofiles, \@msgs );

        if ( @msgs )
        {
            @msgs = ( ["ERROR", ( scalar @msgs ) ." output file(s) exist" ],
                      ["HELP", qq (The --clobber option will overwrite those ) ] );

            &append_or_exit( \@msgs );
        }
    }

    $odirs = [ map { $_->{"name"} } @{ $conf->patlist } ];
    $odirs = &Common::Util::uniqify( $odirs );

    $conf->odirs( $odirs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $outsuf = $args->outsuf;
    $outsuf =~ s/^\.//;
    
    if ( $args->stats ) {
        $conf->statfile( $args->stats );
    } else {
        $conf->statfile( ( $args->outdir // "." ) ."/$outsuf.stats" );
    }

    &Common::File::check_files([ $conf->statfile ], "!e", \@msgs ) unless $args->clobber;

    $conf->mapfile( &Common::Names::replace_suffix( $conf->statfile, ".match.stats" ) );
    &Common::File::check_files([ $conf->mapfile ], "!e", \@msgs ) unless $args->clobber;

    $conf->mapfile( &File::Basename::basename( $conf->mapfile ) );

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SETTINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    return wantarray ? %{ $conf } : $conf;
}

sub init_stats_match
{
    # Niels Larsen, March 2013.
    
    # Initializes a statistics hash that Seq::Fluid::write_stats_match writes 
    # to file.

    my ( $conf,
        ) = @_;

    # Returns a hash.

    my ( $stats, $io );

    $stats->{"name"} = "sequence-demultiplex-fluidigm";
    $stats->{"title"} = "Phylogenetic primer matching";

    $stats->{"files"} = [
        {
            "title" => "Input sequence files",
            "value" => $conf->ifiles,
        },{
            "title" => "Output sub-directories",
            "value" => [ sort @{ $conf->odirs } ],
        },{
            "type" => "html",
            "title" => "Primer table file",
            "value" => &File::Basename::basename( $conf->prifile ) .".txt",
        },{
            "type" => "html",
            "title" => "Primer cross-matches",
            "value" => &File::Basename::basename( $conf->mapfile ),
        }];

    $stats->{"odir"} = {
        "title" => "Output directory",
        "value" => $conf->outdir,
    };
    
    $stats->{"params"} = [
        {
            "title" => "Max. primer start",
            "value" => ( defined $conf->{"pridist"} ? $conf->{"pridist"} + 1 : "any" ),
        }];

    return $stats;
}

sub match_primers
{
    # Niels Larsen, April 2013. 

    # Helper function that matches primer patterns against a list of 
    # sequences, all against all, and adds pattern names to the
    # sequence info fields. The annotation looks like "fwd_primer=value"
    # or "rev_primer=value" where value is the primer name. Returns 
    # nothing but updates the input sequences.

    my ( $seqs,     # Sequence list
         $args,     # Arguments hash
        ) = @_;

    # Returns nothing.

    my ( $pat, $seq, $locs, $maxbeg, $cseq );

    $maxbeg = $args->maxbeg;

    # >>>>>>>>>>>>>>>>>>>>> FORWARD PATTERNS <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Test each pattern: if there is match, and match lies within the 
    # given distance from the start, then add annotation to the info
    # field,
    
    foreach $pat ( @{ $args->fpats } )
    {
        &Bio::Patscan::compile_pattern( $pat->{"pat"}, 0 );
        
        foreach $seq ( @{ $seqs } )
        {
            if ( $locs = &Bio::Patscan::match_forward( $seq->{"seq"} )->[0] 
                 and @{ $locs } and $locs->[0]->[0] <= $maxbeg )
            {
                $seq->{"info"} .= " " if $seq->{"info"};
                $seq->{"info"} .= "fwd_primer=". $pat->{"name"};
            }
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>> REVERSE PATTERNS <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Same as forward, except make a complemented copy of the sequence
    # before trying,
    
    foreach $pat ( @{ $args->rpats } )
    {
        &Bio::Patscan::compile_pattern( $pat->{"pat"}, 0 );
        
        foreach $seq ( @{ $seqs } )
        {
            $cseq = &Seq::Common::complement( $seq );
            
            if ( $locs = &Bio::Patscan::match_forward( $cseq->{"seq"} )->[0]
                 and @{ $locs } and $locs->[0]->[0] <= $maxbeg )
            {
                $seq->{"info"} .= " " if $seq->{"info"};
                $seq->{"info"} .= "rev_primer=". $pat->{"name"};
            }
        }
    }
    
    return;
}

sub open_demul_files
{
    # Niels Larsen, April 2013. 

    # Append-open output files for a single input. 

    my ( $ifile,
         $conf,
        ) = @_;

    my ( $ofhs, $fname, $pridir );

    $ofhs = &Seq::Fluid::set_demul_paths([ $ifile ], $conf );

    foreach $fname ( keys %{ $ofhs } )
    {
        foreach $pridir ( keys %{ $ofhs->{ $fname } } )
        {
            $ofhs->{ $fname }->{ $pridir } = &Common::File::get_append_handle( $ofhs->{ $fname }->{ $pridir } );
        }
    }

    return wantarray ? %{ $ofhs } : $ofhs;
}
    
sub score_primer_pairs
{
    # Niels Larsen, April 2014. 

    my ( $seq,
         $hits,
        ) = @_;

    my ( $seen, $key, $val, $count, @names, $i, $j );

    while ( $seq->{"info"} =~ /(fwd|rev)_primer=(\S+)/g )
    {
        $seen->{ $2 }->{ $1 } = 1;
    }

    foreach $key ( keys %{ $seen } )
    {
        if ( $seen->{ $key }->{"fwd"} and $seen->{ $key }->{"rev"} )
        {
            push @names, $key;
        }
    }

    $count = 0;

    for ( $i = 0; $i <= $#names; $i += 1 )
    {
        $hits->{ $names[$i] }->{ $names[$i] } += 1;

        for ( $j = $i + 1; $j <= $#names; $j += 1 )
        {
            $hits->{ $names[$i] }->{ $names[$j] } += 1;
            $hits->{ $names[$j] }->{ $names[$i] } += 1;
        }

        $count += 1;
    }

    return $count;
}

sub score_primer_singles
{
    # Niels Larsen, April 2013.

    my ( $seq,
         $expr,
         $hits,
        ) = @_;

    my ( $seen, $key, $val, $count, @names, $i, $j );

    while ( $seq->{"info"} =~ /($expr)=(\S+)/g )
    {
        $seen->{ $2 } = 1;
    }

    @names = keys %{ $seen };

    $count = 0;

    for ( $i = 0; $i <= $#names; $i += 1 )
    {
        $hits->{ $names[$i] }->{ $names[$i] } += 1;

        for ( $j = $i + 1; $j <= $#names; $j += 1 )
        {
            $hits->{ $names[$i] }->{ $names[$j] } += 1;
            $hits->{ $names[$j] }->{ $names[$i] } += 1;
        }

        $count += 1;
    }

    return $count;
}

sub set_demul_paths
{
    # Niels Larsen, April 2013. 

    # Helper routine that creates a double-hash of paths. The first key is 
    # the primer name, second key is file basename and values are paths. 

    my ( $files,
         $conf,
        ) = @_;

    my ( $outdir, $outsuf, $pridir, @files, $file, %paths );

    $outdir = $conf->outdir;
    $outsuf = $conf->outsuf;

    @files = map { &File::Basename::basename( $_ ) } @{ $files };

    foreach $pridir ( map { $_->{"name"} } @{ $conf->patlist } )
    {
        foreach $file ( @files )
        {
            $paths{ "$file.FR" }{ $pridir } = "$outdir/$pridir/$file.FR$outsuf";
            $paths{ "$file.F" }{ $pridir } = "$outdir/$pridir/$file.F$outsuf";
            $paths{ "$file.R" }{ $pridir } = "$outdir/$pridir/$file.R$outsuf";
        }
    }

    return wantarray ? %paths : \%paths;
}

sub write_pairs
{
    # Niels Larsen, April 2013.

    # Returns 1 if the info field of given sequence has both a forward
    # (fwd_primer=value) and reverse primer (rev_primer=value) with the same
    # value, otherwise nothing.

    my ( $ofhs,      # Output file handles
         $seqs,      # Sequence list
         $writer,    # Writing routine name
        ) = @_;

    # Returns 1 or nothing.

    my ( $seen, $seq, $pridir, $oseqs, $count );

    foreach $seq ( @{ $seqs } )
    {
        $seen = {};

        while ( $seq->{"info"} =~ /(fwd|rev)_primer=(\S+)/g )
        {
            $seen->{ $2 }->{ $1 } = 1;
        }

        foreach $pridir ( keys %{ $seen } )
        {
            if ( $seen->{ $pridir }->{"fwd"} and $seen->{ $pridir }->{"rev"} )
            {
                push @{ $oseqs->{ $pridir } }, $seq;
            }
        }
    }

    $count = &Seq::Fluid::write_seqs_dict( $ofhs, $oseqs, $writer );

    return $count;
}

sub write_seqs_dict
{
    my ( $ofhs,
         $seqs,
         $writer,
        ) = @_;

    my ( $pridir, $count );

    $count = 0;

    foreach $pridir ( keys %{ $seqs } )
    {
        no strict "refs";

        if ( not ref $ofhs->{ $pridir } ) {
            $ofhs->{ $pridir } = &Common::File::get_append_handle( $ofhs->{ $pridir } );
        }

        $writer->( $ofhs->{ $pridir }, $seqs->{ $pridir } );

        $count += scalar @{ $seqs->{ $pridir } };
    }
    
    return $count;
}

sub write_singles_fwd
{
    # Niels Larsen, April 2013.

    my ( $ofhs,      # Output file handles
         $seqs,      # Sequence list
         $writer,    # Writing routine name
        ) = @_;

    # Returns integer.

    my ( $seq, $oseqs, $count );

    foreach $seq ( @{ $seqs } )
    {
        while ( $seq->{"info"} =~ /fwd_primer=(\S+)/g )
        {
            push @{ $oseqs->{ $1 } }, $seq;
        }
    }

    $count = &Seq::Fluid::write_seqs_dict( $ofhs, $oseqs, $writer );

    return $count;
}

sub write_singles_rev
{
    # Niels Larsen, April 2013.

    my ( $ofhs,      # Output file handles
         $seqs,      # Sequence list
         $writer,    # Writing routine name
        ) = @_;

    # Returns 1 or nothing.

    my ( $seq, $oseqs, $count );

    foreach $seq ( @{ $seqs } )
    {
        while ( $seq->{"info"} =~ /rev_primer=(\S+)/g )
        {
            push @{ $oseqs->{ $1 } }, $seq;
        }
    }

    $count = &Seq::Fluid::write_seqs_dict( $ofhs, $oseqs, $writer );

    return $count;
}

sub write_stats_match
{
    # Niels Larsen, March 2013. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $conf,
         $stats,
        ) = @_;

    my ( $file_str, $param_str, $time, $totstr, $hitstr, $hitpct, $text,
         $elem, $numstr, $i, $j, $hits, $str, $key1, $key2, $title, $row,
         @keys, $num, $nbsp, $prifile, $tuple );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $file_str = &Seq::Stats::format_files( $stats->{"files"} );
    $param_str = &Seq::Stats::format_params( $stats->{"params"} );

    $time = &Time::Duration::duration( $stats->{"seconds"} );

    $totstr = $stats->{"totals"}->{"iseqs"} // 0;
    $hitstr = $stats->{"totals"}->{"matches"} // 0;
    $hitpct = sprintf "%.2f", $stats->{"totals"}->{"matchpct"};

    $text = qq (
<stats>

   title = $stats->{"title"} 
   name = $stats->{"name"}

   <header>
$file_str
      hrow = Total input reads\t$totstr
      hrow = Total matched reads\t$hitstr ($hitpct%)
);

    $text .= qq ($param_str
      date = $stats->{"finished"}
      secs = $stats->{"seconds"}
      time = $time
   </header>
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> COUNTS TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text .= qq (
   <table>
      title = Primer matches per file
      colh = Input file\tReads\tForward\tReverse\tBoth\tMatches\tMisses\tMiss %
);

    foreach $elem ( @{ $stats->{"counts"} } )
    {
        $text .= qq (      trow = file=$elem->{"oname"});
        $text .= "\t". $elem->{"alltot"};
        $text .= "\t". $elem->{"fwdtot"};
        $text .= "\t". $elem->{"revtot"};
        $text .= "\t". $elem->{"bothtot"};
        $text .= "\t". $elem->{"matches"};
        $text .= "\t". $elem->{"mistot"};
        $text .= "\t". sprintf "%.2f", 100 * $elem->{"mistot"} / $elem->{"alltot"};
        $text .= "\n";
    }

    $text .= qq (   </table>\n);
    $text .= qq (</stats>\n\n);
    
    if ( defined wantarray ) {
        return $text;
    } else {
        &Common::File::write_file( $conf->statfile, $text );
    }

    return;
}

sub write_stats_primer
{
    # Niels Larsen, April 2013.
    
    # Helper routine that writes primer cross-match tables. 

    my ( $file,       # Output file
         $pats,       # List of patterns
         $tuples,     # Titles / counts
        ) = @_;

    # Returns nothing.

    my ( $fh, @keys, $title, $hits, $nbsp, $text, $numstr, $i, $row, $j, $num,
         $tuple, $summary );

    $summary = qq (Below is shown how many times different primers match
the same sequence. Sometimes a sequence is matched by both specific and less-specific
primers and this shows which primers tend to do that, for all samples combined.);

    $summary =~ s/\n/ /g;
    $summary =~ s/  / /g;
    
    @keys = @{ $pats };

    $text = qq (
<stats>
    title = Target group cross-matches
    summary = $summary
);

    foreach $tuple ( @{ $tuples } )
    {
        ( $title, $hits ) = @{ $tuple };

        $nbsp = "&nbsp;&nbsp;";
        $numstr = "(". ( join ")\t(", ( 1 ... $#keys + 1 ) ) .")";

        $text .= qq (
   <table>
      title = $title
      align_columns = [[ 0, "right" ], [ -1, "left" ]]
      color_ramp = #dddddd #ffffff
      colh = Target organism group$nbsp$nbsp(n)\t$numstr\t(n)$nbsp Target organism group
);
    
        for ( $i = 0; $i <= $#keys; $i += 1 )
        {
            $title = $keys[$i];
            $title =~ s/_/ /g;

            $row = [];
            
            for ( $j = 0; $j <= $#keys; $j +=  1 )
            {
                push @{ $row }, $hits->{ $keys[$i] }->{ $keys[$j] } // 0;
            }
            
            $num = $i + 1;
            $text .= qq (      trow = $title $nbsp ($num)\t). ( join "\t", @{ $row } );
            $text .= qq (\t \($num\) $nbsp $title\n);
        }
        
        $text .= qq (   </table>\n\n);
    }

    $text .= "</stats>\n\n";

    &Common::File::write_file( $file, $text, 1 );
    
    return;
}

1;

__END__
