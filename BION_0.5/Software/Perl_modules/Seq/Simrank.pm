package Seq::Simrank;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that compute oligo- or word-based sequence similarities. See 
#
#  seq_simrank --help
#
# Some of the simplest routines are used by Seq::Chimera.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Config;
use Time::Duration qw ( duration );
use feature "state";

use Data::MessagePack;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &calculate_splits
                 &create_db_map
                 &create_query_map
                 &create_query_maps
                 &debug_db_map
                 &debug_query_map
                 &filter_sims_file
                 &format_sim_line
                 &get_top_sims
                 &list_db_maps
                 &match_seqs
                 &match_seqs_args
                 &match_seqs_parallel
                 &measure_splits
                 &merge_sim_files
                 &parse_sim_line
                 &read_db_map
                 &read_query_map
                 &write_db_map
                 &write_db_maps
                 &write_query_map
                 &write_query_maps
                 &write_sims

                 &find_max_value_C
                 &measure_sims_C
                 &merge_sims_C
                 &quicksort_two_C
                 &reverse_arrays_C
                  );

use Common::Config;
use Common::Messages;

use Common::Util_C;

use Registry::Args;
use Common::File;

use Seq::List;
use Seq::IO;
use Seq::Oligos;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Max_int );
our ( $Cache_dir, $Work_dir );

$Max_int = 2 ** 30;

$Cache_dir = ".simrank_cache";
$Work_dir = "simrank_tmpdir_$$";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INLINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my $inline_dir;

BEGIN 
{
    $inline_dir = &Common::Config::create_inline_dir("Seq/Simrank");
    $ENV{"PERL_INLINE_DIRECTORY"} = $inline_dir;
}

use Inline C => 'DATA',
    "DIRECTORY" => $inline_dir, 
    "CCFLAGS" => "-std=c99";
#    'PRINT_INFO' => 1, 'REPORTBUG' => 1;

Inline->init;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use vars qw ( *AUTOLOAD );

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub calculate_splits
{
    # Niels Larsen, September 2012. 

    # Given a file and a number of cores, calculates the number of file splits 
    # so the ram consumption will stay under 100 mb per core.

    my ( $file,       # File name
         $cores,      # Number of cores
        ) = @_;

    # Returns integer. 

    my ( $size, $mult, $splits );

    $size = -s $file;
    $mult = 1;
    
    while ( $size / $cores / $mult > 100_000_000 ) {
        $mult += 1;
    }
    
    $splits = $cores * $mult;

    return $splits;
}

sub create_db_map
{
    # Niels Larsen, February 2012.

    # Builds an oligo map from a list of sequences. It is assumed they have no
    # gaps, are DNA/RNA and they should be all in the same direction. For each 
    # oligo it lists the indices of the dataset sequences that have that oligo.
    # This is used for the query sequence oligos to build similarities with.
    # The map has four C arrays, two integers and a perl id list:
    #
    # 1 ndcs: concatenated runs of sequence indices, one stretch per oligo
    # 2 begs: indices into ndcs where each run starts
    # 3 lens: the number of sequences (ndcs elements) for each oligo
    # 4 sums: the number of oligos for each sequence
    # 5 stot: total number of sequences
    # 6 wlen: oligo (word) length
    # 7 sids: sequence ids perl list
    # 
    # The three arrays 1-4 are packed strings that map to C arrays used  by the
    # routines in this module. They have these datatypes,
    #
    # ndcs: 4 bytes (unsigned int)
    # begs: 4/8 bytes (unsigned long, 8 bytes if C compiler supports it)
    # lens: 2 bytes (unsigned short) 
    # sums: 2 bytes (unsigned short) 
    #
    # The keys for the input argument switches are,
    # 
    # wconly: skip non-canonical bases or not
    # wordlen:  oligo word length
    # 
    # Output is a hash with references to 1-7 above, with the listed names as 
    # keys. 

    my ( $seqs,     # List of sequence hashes
         $args,     # Hash of arguments
        ) = @_;

    # Returns a hash.

    my ( $wordlen, $wconly, $seq_num, $oli_dim, $oli_seen, $run_begs, $l_size,
         $run_lens, $seq_ndcs, $run_beg, $tmp_begs, $seq, $run_end, $oli_sums, 
         $sum, @seq_ids, $oli_zero, $max_len );

    $wordlen = $args->wordlen;
    $wconly = $args->wconly;

    $oli_dim = 4 ** $wordlen;          # DNA/RNA only
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET DIMENSIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # For each oligo, find how many sequences have it. This the same as the 
    # lengths of each sequence id run,
    
    $run_lens = &Common::Util_C::new_array( $oli_dim, "uint" );
    $oli_sums = "";

    $oli_seen = "\0" x $oli_dim;

    $max_len = &List::Util::max( map { length $_->{"seq"} } @{ $seqs } );
    $oli_zero = &Common::Util_C::new_array( $max_len, "uint" );

    if ( $wconly )
    {
        foreach $seq ( @{ $seqs } )
        {
            $sum = &Seq::Oligos::count_olis_wc(
                $seq->{"seq"}, length $seq->{"seq"},
                ${ $run_lens }, $wordlen, $oli_seen, ${ $oli_zero } );
            
            $oli_sums .= pack "V", $sum;
        }
    }
    else
    {
        foreach $seq ( @{ $seqs } )
        {
            $sum = &Seq::Oligos::count_olis(
                $seq->{"seq"}, length $seq->{"seq"},
                ${ $run_lens }, $wordlen, $oli_seen, ${ $oli_zero } );
            
            $oli_sums .= pack "V", $sum;
        }
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE MAP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create run_begs: for each oligo the positions in $seq_ndcs below where 
    # run starts. Check long size in C, and allocate accordingly,

    $l_size = &Common::Util_C::size_of_long();
    
    if ( $l_size == 4 ) {
        $run_begs = &Common::Util_C::new_array( $oli_dim, "uint" );
    } elsif ( $l_size == 8 ) {
        $run_begs = &Common::Util_C::new_array( $oli_dim, "uquad" );
    } else {
        &error( qq (Unsupported long-int byte size -> "$l_size") );
    }

    $run_end = &Seq::Oligos::init_run_offs( ${ $run_lens }, ${ $run_begs }, $oli_dim );

    # Fill run_ids with sequence ids. The $seq_ndcs array is populated with 
    # the sequence numbers while offsets in $tmp_begs are moved forward,

    $seq_ndcs = &Common::Util_C::new_array( $run_end, "uint" );

    $tmp_begs = ${ $run_begs };

    $seq_num = 0;
    @seq_ids = ();
    
    if ( $wconly )
    {
        foreach $seq ( @{ $seqs } )
        {
            &Seq::Oligos::create_ndcs_wc(
                $seq->{"seq"}, length $seq->{"seq"},
                $seq_num, ${ $seq_ndcs }, $tmp_begs,
                $wordlen, $oli_seen, ${ $oli_zero } );
            
            push @seq_ids, $seq->{"id"};

            $seq_num += 1;
        }
    }
    else
    {
        foreach $seq ( @{ $seqs } )
        {
            &Seq::Oligos::create_ndcs(
                $seq->{"seq"}, length $seq->{"seq"},
                $seq_num, ${ $seq_ndcs }, $tmp_begs,
                $wordlen, $oli_seen, ${ $oli_zero } );
            
            push @seq_ids, $seq->{"id"};

            $seq_num += 1;
        }
    }

    return {
        "ndcs" => $seq_ndcs,
        "begs" => $run_begs,
        "lens" => $run_lens,
        "sums" => \$oli_sums,
        "sids" => \@seq_ids,
        "stot" => $seq_num,
        "wlen" => $wordlen,
    };
}

sub create_query_map
{
    # Niels Larsen, March 2012. 

    # Reads a given number of entries from the given file handle and converts
    # them to a numeric oligo map stored in strings used as arrays in C. The
    # sequences are de-gapped, complemented and length-filtered if the $args 
    # hash has "degap", "comp" and "minlen" keys set. The return map is a
    # hash with these keys:
    # 
    # sids         Perl list with sequence ids
    # olis         Packed string of numeric oligos
    # begs         Packed string of offsets into olis for each sequence
    # sums         Packed string of the number of oligos for each sequence
    # wordlen      Oligo word length
    # steplen      Step length
    # seqstot      Total number of sequences

    my ( $seqs,       # Sequence list 
         $args,       # Arguments hash
        ) = @_;

    # Returns hash.

    my ( $seq, $wordlen, $olinum, $olis, $ondx, $begs, $sums, $oli_zero, $fh,
         $map, $oli_seen, $ondx_new, $oli_dim, $max_len, $maxch, @sids,
         $steplen, $routine, $mpack, $l_size, $l_pack );

    # Substitute low quality with N's,

    if ( $args->minch and $seqs->[0]->{"qual"} )
    {
        $maxch = chr ( ( ord $args->minch ) - 1 );
        $seqs = &Seq::List::change_by_quality( $seqs, "N", "!", $maxch );
    }

    # Insert blanks in the sequences that have the seq_break info field set
    # to a non-negative number,

    if ( $args->breaks )
    {
        if ( $seqs->[0]->{"qual"} ) {
            $seqs = &Seq::List::insert_breaks( $seqs, " ", " " );
        } else {
            $seqs = &Seq::List::insert_breaks( $seqs, " " );
        }            
    }
    
    # Allocate string to hold the oligos. For a given sequence the number of 
    # possible oligos is the number of possible steps through it,
    
    $wordlen = $args->wordlen;
    $steplen = $args->steplen;

    $olinum = &List::Util::sum( map
        {
            ( ( ( length $_->{"seq"} ) - $wordlen ) / $steplen ) + 1
        } @{ $seqs } );

    $olis = &Common::Util_C::new_array( $olinum, "uint" );

    # Initialize,

    $begs = "";
    $sums = "";
    
    $max_len = &List::Util::max( map { length $_->{"seq"} } @{ $seqs } );
    $oli_zero = &Common::Util_C::new_array( $max_len, "uint" );
    
    if ( $args->wconly ) {
        $routine = "Seq::Oligos::create_olis_uniq_wc";
    } else {
        $routine = "Seq::Oligos::create_olis_uniq";
    }

    # With high word length this grows large, so word length is capped at 12
    # for the moment, where this array will be 16,777,216 bytes long. The 
    # alternative is to use non-unique oligos, but that is not good either.

    $oli_seen = "\0" x 4 ** $wordlen;

    # Check long size in C, and pack accordingly,

    $l_size = &Common::Util_C::size_of_long();
    
    if ( $l_size == 4 ) {
        $l_pack = "V";
    } elsif ( $l_size == 8 ) {
        $l_pack = "Q";
    } else {
        &error( qq (Unsupported long-int byte size -> "$l_size") );
    }

    # Create oligos. The C routine is filling up $olis and returns the next
    # empty index after being done with a sequence. The $oli_seen and $oli_zero
    # are scratch arrays the routine uses to keep track of oligo uniqueness
    # and it blanks them out after each sequence,

    $ondx = 0;

    foreach $seq ( @{ $seqs } )
    {
        no strict "refs";

        $ondx_new = &{ $routine  }(
            $seq->{"seq"}, length $seq->{"seq"}, $wordlen, $steplen,
            ${ $olis }, $ondx, $oli_seen, ${ $oli_zero } );

        $begs .= pack $l_pack, $ondx;
        $sums .= pack "V", $ondx_new - $ondx;
        
        $ondx = $ondx_new;

        push @sids, $seq->{"id"};
    }

    # Trim the empty elements that result from not all oligos being unique,

    # ( substr ${ $olis }, $ondx * $l_size ) = "";

    # Put references into output hash,

    $map->{"wordlen"} = $wordlen;
    $map->{"steplen"} = $steplen;
    $map->{"seqstot"} = scalar @{ $seqs };

    $map->{"sids"} = \@sids;
    $map->{"begs"} = \$begs;
    $map->{"sums"} = \$sums;
    $map->{"olis"} = $olis;

    return bless $map;
}

sub create_query_maps 
{
    my ( $file,
         $conf,
        ) = @_;

    my ( $map_fwd, $map_rev, $count, $read_args, $seqs );

    if ( $conf->fwdmap or $conf->revmap )
    {
        if ( $conf->fwdmap )
        {
            &echo("   Reading query map (F) ... ");
            
            $map_fwd = &Seq::Simrank::read_query_map( $conf->fwdmap );
            
            $count = $map_fwd->seqstot;
            &echo_done("$count seq[s]\n");
        }

        if ( $conf->revmap )
        {
            &echo("   Reading query map (R) ... ");
            
            $map_rev = &Seq::Simrank::read_query_map( $conf->revmap );
            
            $count = $map_rev->seqstot;
            &echo_done("$count seq[s]\n");
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CREATE QUERY MAPS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    else
    {
        $read_args = bless {
            "degap" => $conf->degap,        # Remove gaps or not
            "minlen" => $conf->minlen,      # Minimum sequence length
            "filter" => $conf->filter,      # Annotation string filter expression
            "readbuf" => $conf->readbuf,    # A C-compatible large positive integer
            "wordlen" => $conf->wordlen,    # Oligo word length
            "steplen" => $conf->steplen,    # Oligo step length
            "format" => $conf->format,      # Whatever Seq::IO supports
            "wconly" => $conf->wconly,      # Make oligos with WC bases only
            "minch" => $conf->minch,        # Substitute anything less by N's
            "breaks" => $conf->breaks,      # Insert breaks if seq_break field set
        };
        
        if ( $conf->forward )
        {
            &echo("   Creating query map (F) ... ");
            
            $seqs = &Seq::IO::read_seqs_filter( $file, $read_args );
            $map_fwd = &Seq::Simrank::create_query_map( $seqs, $read_args );
            
            $count = $map_fwd->seqstot;
            &echo_done("$count seq[s]\n");
        }
        
        if ( $conf->reverse )
        {
            &echo("   Create query map (R) ... ");
            
            if ( not $seqs ) {
                $seqs = &Seq::IO::read_seqs_filter( $file, $read_args );
            }
            
            &Seq::List::change_complement( $seqs );
            
            $map_rev = &Seq::Simrank::create_query_map( $seqs, $read_args );
            
            $count = $map_rev->seqstot;
            &echo_done("$count seq[s]\n");
        }
    }
    
    return ( $map_fwd, $map_rev );
}

sub debug_db_map
{
    # Niels Larsen, March 2012. 

    # Prints the sequence indices map in readable form for debugging.
    # Use only with small datasets. 

    my ( $map,
        ) = @_;

    # Returns nothing.

    my ( $oli, @ndcs, @begs, @lens, @sums, $sids, @tmp, $ndcs, $i );

    @ndcs = unpack "V*", ${ $map->{"ndcs"} };
    @begs = unpack "V*", ${ $map->{"begs"} };
    @lens = unpack "V*", ${ $map->{"lens"} };
    @sums = unpack "V*", ${ $map->{"sums"} };
    $sids = $map->{"sids"};

    # Totals and datatypes,

    print "\n";
    print "Word length: $map->{'wlen'}\n";
    print "Number of sequences: $map->{'stot'}\n\n";

    print "Bytes for int in C: ". &Common::Util_C::size_of_int() ."\n";
    print "Bytes for long in C: ". &Common::Util_C::size_of_long() ."\n";

    # Number of oligos per sequence,

    print "\nTotal\tSequence ids\n";

    for( $i = 0; $i <= $#{ $map->{"sids"} }; $i++ )
    {
        print "$sums[$i]\t$sids->[$i]\n";
    }

    print "\n\nOlinum\tSeq total\tSeq list\n";    

    for ( $oli = 0; $oli < 4 ** $map->{"wlen"}; $oli += 1 )
    {
        if ( $lens[$oli] > 0 )
        {
            @tmp = @ndcs[ $begs[$oli] ... $begs[$oli] + $lens[$oli] - 1 ];
            $ndcs = scalar @tmp;
            
            print "$oli\t$ndcs\t". (join ",", @tmp) ."\n";
        }
    }

    print "\n";

    return 1;
}

sub debug_query_map
{
    # Niels Larsen, March 2012. 

    # Prints the oligo map in readable form for debugging.
    # Use only with small datasets. 

    my ( $map,
        ) = @_;

    # Returns nothing.

    my ( $i, $id, $sids, @olis, @begs, @sums, @tmp, $olis );

    print "\n";
    print "\$Config{'u16size'} = $Config{'u16size'}\n";
    print "\$Config{'u32size'} = $Config{'u32size'}\n";
    print "\$Config{'u64size'} = $Config{'u64size'}\n";
    print "Bytes for int in C: ". &Common::Util_C::size_of_int() ."\n";
    print "Bytes for long in C: ". &Common::Util_C::size_of_long() ."\n";

    print "\nSeq id\tOligo total\tUnique olinum\n";

    $sids = $map->sids;
    @begs = unpack "V*", ${ $map->{"begs"} };
    @sums = unpack "V*", ${ $map->{"sums"} };
    @olis = unpack "V*", ${ $map->{"olis"} };

    for ( $i = 0; $i < scalar @{ $sids }; $i += 1 )
    {
        $id = $sids->[$i];
        
        @tmp = @olis[ $begs[$i] ... $begs[$i] + $sums[$i] - 1 ];
        $olis = scalar @tmp;
        
        print "$id\t$olis\t". (join ",", @tmp) ."\n";
    }

    print "\n";
    
    return 1;
}

sub delete_self_sims
{
    # Niels Larsen, May 2013.

    # Rewrites the given similarity file so query ids are not among 
    # the match ids. The output has the same number of lines as the 
    # input. If no second argument is given, the input file is
    # overwritten. Returns the number of lines written. 

    my ( $ifile,       # Input similarities table
         $ofile,       # Output similarities table - OPTIONAL, default overwrite input
        ) = @_;

    # Returns integer. 

    my ( $ifh, $ofh, $lines, $line, $row, $qid );

    $ofile //= $ifile .".tmp";

    $ifh = &Common::File::get_read_handle( $ifile );

    &Common::File::delete_file_if_exists( $ofile );
    $ofh = &Common::File::get_write_handle( $ofile );

    $lines = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        $row = &Seq::Simrank::parse_sim_line( \$line, 1 );
        $qid = $row->[0];

        if ( defined $row->[2] ) {
            $row->[2] = [ grep { $_->[0] ne $qid } @{ $row->[2] } ];
        }
        
        $line = &Seq::Simrank::format_sim_line( $row );

        $ofh->print( $line );

        $lines += 1;
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    return $lines;
}
    
sub format_sim_line
{
    # Niels Larsen, May 2013.

    # Creates a similarity table line from the given arguments, doing
    # the opposite of &Seq::Simrank::parse_sim_line. Returns a string.

    my ( $list,
         $places,
        ) = @_;

    # Returns a string.

    my ( $line );

    $line = $list->[0] ."\t". $list->[1] ."\t";

    if ( ref $list->[2] ) 
    {
        $line .= join " ", map { $_->[0] ."=". $_->[1] } @{ $list->[2] };
    }
    else {
        $line .= $list->[2];
    }

    $line .= "\n";

    return $line;
}

sub get_top_sims
{
    # Niels Larsen, May 2013.

    # Returns the best of the given similarity tuples. 

    my ( $sims,
         $range,
        ) = @_;

    my ( $max, @sims, $i );

    $range //= 0;
    $max = $sims->[0]->[1];

    @sims = [ @{ $sims->[0] } ];

    for ( $i = 1; $i <= $#{ $sims }; $i += 1 )
    {
        if ( ( $max - $sims->[$i]->[1] ) <= $range )
        {
            push @sims, $sims->[$i];
        }
        else {
            last;
        }
    }

    return wantarray ? @sims : \@sims;
}

sub list_db_maps
{
    # Niels Larsen, September 2012. 
    
    # Reads a directory of cache files and returns them as a list. Also returns 
    # the total number of sequences in all files combined. 

    my ( $dir,   # Cache directory
        ) = @_;

    # Returns two-element list.

    my ( @files, $total );

    @files = &Common::File::list_files( $dir, '^\d+$' );

    @files = sort { $a->{"name"} <=> $b->{"name"} } @files;
    @files = map { $_->{"path"} } @files;

    $total = ${ &Common::File::read_file("$dir/TOTAL") };

    return ( $total, \@files );
}

sub match_seqs
{
    # Niels Larsen, March 2012.

    # An oligo based sequence similarity matcher. Creates similarities between
    # a sequence file and a reference file of sequences, typically new gene
    # sequences against a larger reference set. The output is a table with 
    # three columns: query id, number of query oligos, list of matches in the
    # form db-id=percent. The matcher will by default run in parallel and use 
    # as manu cores as there are on the system.

    my ( $q_file,   # Query file 
         $args,     # Arguments hash
         ) = @_;

    # Returns a list of matches. 

    my ( $defs, $numids, $ndx_add, $minsim, $q_map_fwd, $q_map_rev, $q_begs,
         $q_sums, $q_olis, $q_ndx, $db_fh, $db_ndcs, $db_begs, $db_sim_sums,
         $db_seqs, $db_map, $db_lens, $db_stot, $q_read_args, $db_read_args,
         $topsim, $q_tot, $run_start, $mat_start, $simcnt, $db_read, $conf,
         $db_sums, @db_sim_sco, @db_sim_ids, $db_sim_sco, $db_sim_ids, 
         @db_ids, $debug, $count, $db_tot, $db_ids_buf, $db_sco_buf, $q_ids,
         $orient, @orient, $q_seqs_rev, $q_seqs, $db_maps, $db_map_dir, 
         $db_map_file, $match_maps, $wordlen, $wconly, $map_args );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "qseqs" => undef,
        "format" => undef,
        "wordlen" => 8,
        "steplen" => 4,
        "fwdmap" => undef,
        "revmap" => undef,
        "forward" => 1,
        "reverse" => 0,
        "breaks" => 1,
        "degap" => 0,
        "minlen" => undef,
        "filter" => undef,
        "qualtype" => undef,
        "minqual" => 0,
        "readbuf" => 10_000,
        "splits" => undef,
        "dbfile" => undef,
        "dbdegap" => 0,
        "dbminlen" => undef,
        "dbfilter" => undef,
        "dbread" => 10_000,
        "dbcache" => undef,
        "dbtot" => undef,
        "minsim" => 40,
        "topsim" => 1,
        "wconly" => 1,
        "maxout" => $Max_int, 
        "otable" => undef,
        "osuffix" => undef,
        "simfmt" => "%.5f",
        "numids" => 0,
        "cores" => undef,
        "silent" => 0,
        "debug" => 0,
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $args->qseqs( $q_file );
    $conf = &Seq::Simrank::match_seqs_args( $args );
    $args->delete_field("qseqs");

    if ( $debug = $args->debug )
    {
        $Common::Messages::silent = 1;
        $conf->splits( 0 );
    }
    else {
        $Common::Messages::silent = $args->silent;
    }

    $run_start = time();

    &echo_bold("\nSimrank matching:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE DATASET CACHE <<<<<<<<<<<<<<<<<<<<<<<<<<

    # If cache files do not exist or are out of date, then create them and 
    # return a sorted list of their names,

    $db_read_args = bless {
        "degap" => $conf->dbdegap,     # Remove gaps or not
        "minlen" => $conf->dbminlen,   # Minimum sequence length
        "filter" => $conf->dbfilter,   # Annotation string filter expression
        "format" => $conf->dbformat,   # Whatever Seq::IO supports
        "readbuf" => $conf->dbread,    # Seqs to read at a time
        "wordlen" => $conf->wordlen,   # Oligo length
        "wconly" => $conf->wconly,     # Skip non-canonical bases
    };
    
    if ( $db_map_dir = $conf->dbcache )
    {
        &Common::File::create_dir_if_not_exists( $db_map_dir );
        $db_map_file = &Common::File::get_newest_file( $db_map_dir );

        if ( not $db_map_file or 
             &Common::File::is_newer_than( $conf->dbfile, $db_map_file->{"path"} ) )
        {
            &echo("   Creating cache files ... ");
            &Seq::Simrank::write_db_maps( $conf->dbfile, $db_map_dir, $db_read_args );
            &echo_done("done\n");
        }
        
        &echo("   Listing cache files ... ");

        ( $db_tot, $db_maps ) = &Seq::Simrank::list_db_maps( $db_map_dir );
        
        $count = scalar @{ $db_maps };
        &echo_done("$count\n");
    }
    else
    {
        &echo("   Counting dataset ... ");
        $db_tot = &Seq::Stats::count_seq_file( $conf->dbfile )->seq_count;
        &echo_done("$db_tot\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>> RUN IN PARALLEL AND EXIT <<<<<<<<<<<<<<<<<<<<<<<<<

    # If the number of cores is higher than one, then write oligo maps to a 
    # scratch directory and run them in parallel. It will create a file for GNU 
    # parallel that simply runs n instances of simrank from the command line, 
    # each instance processing its map. The routine finally merges results,
    # deletes the scratch directory and returns,

    if ( not defined $conf->cores or $conf->cores > 1 or
         defined $conf->splits and $conf->splits > 1 )
    {
        &Seq::Simrank::match_seqs_parallel( $q_file, $conf );

        &echo("   Run time: ");
        &echo_info( &Time::Duration::duration( time() - $run_start ) ."\n" );
        
        &echo_bold("Finished\n\n");
        return;
    }

    # >>>>>>>>>>>>>>>>>>>>>> CREATE-OR-READ QUERY MAPS <<<<<<<<<<<<<<<<<<<<<<<<
    
    ( $q_map_fwd, $q_map_rev ) = &Seq::Simrank::create_query_maps( $q_file, $conf );

    if ( $debug )
    {
        &debug_query_map( $q_map_fwd ) if $q_map_fwd;
        &debug_query_map( $q_map_rev ) if $q_map_rev;
    }

    push @orient, "forward" if $conf->fwdmap or $conf->forward;
    push @orient, "reverse" if $conf->revmap or $conf->reverse;
    
    # >>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE ARRAYS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Initializing internals ... ");

    $db_ids_buf = &Common::Util_C::new_array( $db_tot, "uint" );
    $db_sco_buf = &Common::Util_C::new_array( $db_tot, "float" );

    $minsim = $conf->minsim / 100;
    $topsim = $conf->topsim / 100;
    $numids = $conf->numids;

    $db_read = $conf->dbread;

    $db_sim_sums = &Common::Util_C::new_array( $db_tot, "uint" );
    $db_sim_ids = &Common::Util_C::new_array( $db_tot, "uint" );
    $db_sim_sco = &Common::Util_C::new_array( $db_tot, "float" );

    if ( $q_map_fwd ) {
        $q_tot = $q_map_fwd->seqstot;
    } else {
        $q_tot = $q_map_rev->seqstot;
    }

    @db_ids = ();
    @db_sim_ids = ( pack "V", 0 ) x $q_tot;
    @db_sim_sco = ( pack "V", 0 ) x $q_tot;

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> PROCESSING ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This routine is where similarity matching happens. It compares a forward
    # and/or reverse query map with a reference map.

    $match_maps = sub
    {
        push @db_ids, @{ $db_map->{"sids"} };
        
        if ( $debug ) {
            &debug_db_map( $db_map );
        }
        
        # These are packed strings that will be seen as arrays in C,
        
        $db_ndcs = $db_map->{"ndcs"};     # Runs of sequence indices, for all oligos
        $db_begs = $db_map->{"begs"};     # Start offsets into ndcs for each oligo
        $db_lens = $db_map->{"lens"};     # Sequence totals for each oligo
        $db_sums = $db_map->{"sums"};     # Oligo totals for each sequence
        $db_stot = scalar @{ $db_map->{"sids"} };  # Number of sequences read
        
        # Compare each query sequence against the map,
        
        foreach $orient ( @orient )
        {
            if ( $orient eq "forward" )
            {
                $q_olis = $q_map_fwd->{"olis"};     # Packed string of numeric oligos
                $q_begs = $q_map_fwd->{"begs"};     # Packed string of offsets into olis for each sequence
                $q_sums = $q_map_fwd->{"sums"};     # Packed string of the number of oligos for each sequence
            }
            else
            {
                $q_olis = $q_map_rev->{"olis"};
                $q_begs = $q_map_rev->{"begs"};
                $q_sums = $q_map_rev->{"sums"};
            }
            
            for ( $q_ndx = 0; $q_ndx < $q_tot; $q_ndx += 1 )
            {
                # For each query sequence, match against all dataset sequences read.
                
                $simcnt = &Seq::Simrank::measure_sims_C(
                    ${ $q_olis }, ${ $q_begs }, ${ $q_sums }, $q_ndx, 
                    ${ $db_ndcs }, ${ $db_begs }, ${ $db_lens }, ${ $db_sums },
                    $db_stot, ${ $db_sim_sums }, ${ $db_sim_sco }, ${ $db_sim_ids }, 
                    $minsim, $topsim, $ndx_add
                    );
                
                if ( $simcnt > 0 )
                {
                    # If there are matches, then merge these into the results arrays which
                    # are @db_sim_ids and @db_sim_sco. These are lists of strings, one for 
                    # each query sequence, with the best matching ids and scores at all 
                    # time.
                    
                    $simcnt = &Seq::Simrank::merge_sims_C(
                        $db_sim_ids[$q_ndx], $db_sim_sco[$q_ndx], (length $db_sim_sco[$q_ndx]) / 4,
                        ${ $db_sim_ids }, ${ $db_sim_sco }, $simcnt,
                        ${ $db_ids_buf }, ${ $db_sco_buf }, $topsim,
                        );
                    
                    if ( $simcnt > 0 )
                    {
                        # The merged matches are stored in $db_ids_buf and $db_sco_buf, 
                        # which then becomes the new best matches.
                        
                        $db_sim_ids[$q_ndx] = substr ${ $db_ids_buf }, 0, 4 * $simcnt;
                        $db_sim_sco[$q_ndx] = substr ${ $db_sco_buf }, 0, 4 * $simcnt;
                    }
                }
            }
        }
        
        $ndx_add += scalar @{ $db_map->{"sids"} };
        
        &echo("\n      Matched total ... ");
        &echo_done( "$ndx_add " );
    };

    # >>>>>>>>>>>>>>>>>>>>>>> PROCESS DATASET ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<

    # The query oligo map is held in memory, but the reference map is either 
    # read from cache files, or sequences are read and maps built on the fly.
    # The query and dataset maps are compared and matches merged and kept track
    # of in the routine just above. When the end is reached, the best scores 
    # are writtten. 

    &echo("   Processing queries ... ");
    
    $mat_start = time();

    $ndx_add = 0;

    if ( $db_maps )
    {
        # >>>>>>>>>>>>>>>>>>>>>>> READ MAP CACHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        foreach $db_map_file ( @{ $db_maps } )
        {
            $db_map = &Seq::Simrank::read_db_map( $db_map_file );

            $match_maps->();
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>> READ FROM SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<

        $wordlen = $conf->wordlen;
        $wconly = $conf->wconly;
        
        $db_fh = &Common::File::get_read_handle( $conf->dbfile );

        $map_args = bless { "wordlen" => $wordlen, "wconly" => $wconly };

        while ( $db_seqs = &Seq::IO::read_seqs_filter( $db_fh, $db_read_args ) )
        {
            $db_map = &Seq::Simrank::create_db_map( $db_seqs, $map_args );

            $match_maps->();
        }

        &Common::File::close_handle( $db_fh );
    }

    &echo_done("\n   done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Writing output table ... ");
    
    if ( $conf->otable and $conf->clobber ) {
        &Common::File::delete_file_if_exists( $args->otable );
    }

    if ( $q_map_fwd ) {
        $q_ids = $q_map_fwd->sids;
    } elsif ( $q_map_rev ) {
        $q_ids = $q_map_rev->sids;
    }        

    &Seq::Simrank::write_sims(
        {
            "qids" => $q_ids,             # Query ids
            "qsums" => $q_sums,           # Query oligo count
            "dbids" => \@db_ids,          # Dataset all ids
            "dbsids" => \@db_sim_ids,     # Dataset match indices
            "dbsims" => \@db_sim_sco,     # Dataset match scores
            "numids" => $conf->numids,    # Number ids boolean
            "otable" => $conf->otable,    # Output table file name
            "simfmt" => $conf->simfmt,    # Similarity sprintf format 
            "maxout" => $conf->maxout,    # Max. number of matches
        });

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN TIMES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Match time: ");
    &echo_info( &Time::Duration::duration( time() - $mat_start ) ."\n" );

    &echo("     Run time: ");
    &echo_info( &Time::Duration::duration( time() - $run_start ) ."\n" );

    &echo_bold("Finished\n\n");

    return $count;
}

sub match_seqs_args
{
    # Niels Larsen, January 2012.

    # Validates arguments the user can touch and returns error and info 
    # messages if something is wrong.

    my ( $args,    # Command line argument hash
         ) = @_;

    # Returns a hash. 

    my ( $format, @msgs, $error, $path, $ram_avail, $ram_max, $wordlen, 
         %args, @files, $file, $qual_enc, $steplen, $stdout, $stderr );

    $args{"clobber"} = $args->clobber;
    $args{"numids"} = $args->numids;
    $args{"wconly"} = $args->wconly;
    $args{"simfmt"} = $args->simfmt;
    $args{"format"} = $args->format;
    $args{"qseqs"} = $args->qseqs;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> QUERY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args{"fwdmap"} = $args->fwdmap;
    $args{"revmap"} = $args->revmap;

    if ( $args{"fwdmap"} ) {
        &Common::File::check_files( [ $args{"fwdmap"} ], "r", \@msgs );
    }

    if ( $args{"revdmap"} ) {
        &Common::File::check_files( [ $args{"revmap"} ], "r", \@msgs );
    }

    &append_or_exit( \@msgs );
    
    unless ( $args{"fwdmap"} or $args{"revmap"} )
    {
        if ( $args{"qseqs"} )
        {
            &Common::File::check_files( [ $args{"qseqs"} ], "r", \@msgs );
            &append_or_exit( \@msgs );
            
            $args{"format"} = &Seq::IO::detect_format( $args{"qseqs"}, \@msgs );
            
            if ( $args{"format"} and $args{"format"} !~ /^fastq|fasta|fasta_wrapped$/ ) 
            {
                push @msgs, ["ERROR", qq (Wrong looking query file format -> "$args{'format'}") ];
                push @msgs, ["INFO", qq (Supported formats are: fasta, fastq, fasta_wrapped) ];
            }
        }
        elsif ( -t STDIN )
        {
            push @msgs, ["ERROR", qq (Query sequence must be specified or piped) ];
        }
        elsif ( not $args{"format"} )
        {
            push @msgs, ["ERROR", qq (Query sequence input format must be given for piped input) ];
        }
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->dbfile )
    {
        $args{"dbfile"} = &Common::File::check_files([ $args->dbfile ], "r", \@msgs )->[0];
        
        if ( $args{"dbfile"} and -r $args{"dbfile"} )
        {
            $format = &Seq::IO::detect_format( $args{"dbfile"}, \@msgs );

            if ( $format =~ /^fastq|fasta|fasta_wrapped$/ ) 
            {
                $args{"dbformat"} = $format;
            }
            else {
                push @msgs, ["ERROR", qq (Wrong looking $args{"dbfile"} file format -> "$format") ];
                push @msgs, ["INFO", qq (Supported formats are: fasta, fastq) ];
            }
        }
    }
    else {
        push @msgs, [ "ERROR", qq (Dataset file(s) must be specified) ];
    }

    &append_or_exit( \@msgs );

    $args{"dbcache"} = $args->dbcache;
    
    if ( defined $args{"dbcache"} )
    {
        if ( not $args{"dbcache"} ) {
            $args{"dbcache"} = $args{"dbfile"} . $Cache_dir;
        }

        if ( -d $args{"dbcache"} )
        {
            @files = &Common::File::list_files( $args{"dbcache"} );
            
            @files = grep { $_->{"name"} !~ /^\d+$/ } @files;
            @files = grep { $_->{"name"} ne "TOTAL" } @files;
            
            if ( @files ) {
                push @msgs, ["ERROR", qq (Non-cache files found in the cache directory) ];
                push @msgs, ["ERROR", "" ];
                push @msgs, ["ERROR", $args{'dbcache'} ];
                push @msgs, ["ERROR", "" ];
                push @msgs, ["INFO", qq (The cache directory should have only cache-files in it.) ];
                push @msgs, ["INFO", qq (Either use --dbcache with no arguments, specify another) ];
                push @msgs, ["INFO", qq (directory, or delete the foreign files.) ];
            }
        }
    }

    $args{"dbtot"} = $args->dbtot;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args{"cores"} = $args->cores;

    $args{"degap"} = $args->degap;
    $args{"filter"} = $args->filter;

    $args{"forward"} = $args->forward;
    $args{"reverse"} = $args->reverse;
    $args{"breaks"} = $args->breaks;

    $args{"splits"} = $args->splits;
    
    if ( not $args{"forward"} and not $args{"reverse"} ) {
        push @msgs, [ "ERROR", qq (At least one of --forward or --reverse must be used) ];
    }

    $wordlen = $args->wordlen;

    if ( $wordlen ) {
        $args{"wordlen"} = &Registry::Args::check_number( $wordlen, 1, 12, \@msgs );
    } else {
        push @msgs, [ "ERROR", qq (Word length must be given - 7 or 8 is often best) ];
    }        

    &append_or_exit( \@msgs );

    $args{"steplen"} = &Registry::Args::check_number( $args->steplen, 1, $wordlen, \@msgs );

    &append_or_exit( \@msgs );

    if ( $args->minlen ) {
        $args{"minlen"} = &Registry::Args::check_number( $args->minlen, $wordlen, undef, \@msgs );
    } else {
        $args{"minlen"} = $wordlen;
    }

    if ( $args->dbminlen ) {
        $args{"dbminlen"} = &Registry::Args::check_number( $args->dbminlen, $wordlen, undef, \@msgs );
    } else {
        $args{"dbminlen"} = $wordlen;
    }

    $args{"dbread"} = &Registry::Args::check_number( $args->dbread, 1, 65536, \@msgs );
    $args{"dbdegap"} = $args->dbdegap;
    $args{"dbfilter"} = $args->dbfilter;

    $args{"minsim"} = &Registry::Args::check_number( $args->minsim, 0, 100, \@msgs );
    $args{"minqual"} = &Registry::Args::check_number( $args->minqual, 0, 100, \@msgs );
    $args{"topsim"} = &Registry::Args::check_number( $args->topsim, 0, 100, \@msgs );

    $args{"qualtype"} = $args->qualtype;
    $args{"minch"} = undef;

    $args{"readbuf"} = $args->readbuf;
    
    if ( $args->qualtype )
    {
        $qual_enc = &Seq::Common::qual_config( $args->qualtype, \@msgs );
        &append_or_exit( \@msgs );

        $args{"minch"} = &Seq::Common::qual_to_qualch( $args->minqual / 100, $qual_enc );
        $args{"wconly"} = 1;
    }
    elsif ( $args->minqual ) {
        push @msgs, ["ERROR", qq (A quality type must be given with minimum quality) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->maxout ) {
        $args{"maxout"} = &Registry::Args::check_number( $args->maxout, 1, undef, \@msgs );
    } else {
        $args{"maxout"} = undef;
    }

    $args{"otable"} = $args->otable;

    if ( not defined $args{"otable"} and defined $args->osuffix ) {
        $args{"otable"} = $args{"qfile"} . $args->osuffix;
    }

    if ( defined $args{"otable"} ) {
        &Common::File::check_files([ $args{"otable"} ], "!e", \@msgs ) unless $args->clobber;
    }

    &append_or_exit( \@msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}

sub match_seqs_parallel
{
    # Niels Larsen, June 2012. 

    # Runs the matcher on a given file with GNU parallel from the command
    # line. In a scratch directory named after the output table these steps
    # are done: write a number of oligo-maps with equal size; write command
    # file for GNU parallel; run GNU parallel on this command file; combine
    # resulting output tables; delete scratch directory.

    my ( $file,    # Query sequence file
         $args,    # Arguments object
        ) = @_;

    # Returns nothing.
    
    my ( $cpus, $cores, $run_start, $tmp_dir, $cmd, @cmds, $argstr, 
         @otables, $otable, $maps, $map_file, $fwd_file, $rev_file, 
         $splits );

    # >>>>>>>>>>>>>>>>>>>>>>>> GET NUMBER OF CORES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This is purely for display, but useful to see if the right number of 
    # cores are detected before program runs,

    if ( not defined ( $cores = $args->cores ) )
    {
        &echo("   Checking hardware ... ");

        ( $cpus, $cores ) = &Common::OS::cpus_and_cores();
        $args->cores( $cores );
                
        &echo_done("$cpus cpu[s], $cores core[s]\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> SPLIT QUERY FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $splits = $args->splits;

    if ( not defined $splits )
    {
        &echo("   Setting number of splits ... ");
        $splits = &Seq::Simrank::calculate_splits( $file, $cores );
        &echo_done("$splits\n");
    }
    elsif ( $splits < $cores )
    {
        $splits = $cores;
    }
    
    &echo("   Writing query map files ... ");
        
    if ( $args->otable ) {
        $tmp_dir = $args->otable .".". $Work_dir;
    } else {
        $tmp_dir = $Work_dir;
    }

    $maps = &Seq::Simrank::write_query_maps(
        $file, 
        bless {
            "tmpdir" => $tmp_dir,
            "splits" => $splits,
            "forward" => $args->forward,
            "reverse" => $args->reverse,
            "wordlen" => $args->wordlen,
            "steplen" => $args->steplen,
            "minch" => $args->minch,
            "wconly" => $args->wconly,
            "readbuf" => $args->readbuf,
            "breaks" => $args->breaks,      # Insert breaks if seq_break field set
            "clobber" => 1,
        });
        
    &echo_done("$splits\n");

    # >>>>>>>>>>>>>>>>>>>>>>>> WRITE PARALLEL FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Commands are written to a file, and then GNU parallel simply runs that,

    &echo("   Writing command file ... ");

    if ( $fwd_file = $maps->[0]->{"fwd"} ) {
        $tmp_dir = &File::Basename::dirname( $fwd_file );
    } else {
        $tmp_dir = &File::Basename::dirname( $maps->[0]->{"rev"} );
    }

    $argstr = "--cores 1";
    $argstr .= " --dbfile ". $args->dbfile;
    $argstr .= " --dbdegap ". $args->dbdegap if $args->dbdegap;
    $argstr .= " --dbminlen ". $args->dbminlen if defined $args->dbminlen;
    $argstr .= " --dbfilter ". $args->dbfilter if defined $args->dbfilter;
    $argstr .= " --dbread ". $args->dbread if defined $args->dbread;
    $argstr .= " --dbtot ". $args->dbtot if defined $args->dbtot;
    $argstr .= " --dbcache ". $args->dbcache if defined $args->dbcache;
    $argstr .= " --minsim ". $args->minsim if defined $args->minsim;
    $argstr .= " --topsim ". $args->topsim if defined $args->topsim;
    $argstr .= " --maxout ". $args->maxout if defined $args->maxout;
    $argstr .= " --simfmt '". $args->simfmt ."'" if defined $args->simfmt;
    $argstr .= " --numids ". $args->numids if $args->numids;
    $argstr .= " --silent";
    
    foreach $map_file ( @{ $maps } )
    {
        $cmd = "seq_simrank";

        if ( $fwd_file = $map_file->{"fwd"} )
        {
            $cmd .= " --fwdmap $fwd_file";
            $otable = "$tmp_dir/". &File::Basename::basename( $fwd_file ) .".tab";
        }

        if ( $rev_file = $map_file->{"rev"} )
        {
            $cmd .= " --revmap $rev_file";
            $otable = "$tmp_dir/". &File::Basename::basename( $rev_file ) .".tab";
        }

        $cmd .= " --otable $otable $argstr\n";

        &Common::File::delete_file_if_exists( $otable );

        push @cmds, $cmd;
        push @otables, $otable;
    }
    
    &Common::File::delete_file_if_exists("$tmp_dir/run-commands");
    &Common::File::write_file("$tmp_dir/run-commands", \@cmds );

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> RUN GNU PARALLEL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Running GNU parallel ... ");

    $cmd = "parallel --max-procs $cores";
    $cmd .= " --halt-on-error 2 --joblog $tmp_dir/gnu-parallel.log --tmpdir $tmp_dir";

    $cmd = "$cmd < $tmp_dir/run-commands";

    &Common::OS::run_command_single( $cmd, {"logdir" => $tmp_dir, "fatal" => 0 });

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> COMBINING OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Combining outputs ... ");

    if ( $args->otable and $args->clobber ) {
        &Common::File::delete_file_if_exists( $args->otable );
    }

    foreach $otable ( @otables )
    {
        if ( -s $otable ) {
            &Common::File::append_files( $args->otable, $otable );
        }
    }

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>> DELETE WORK DIR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Deleting scratch area ... ");
    
    &Common::File::delete_dir_tree_if_exists( $tmp_dir );
    
    &echo_done("done\n");

    return;
}

sub measure_splits
{
    # Niels Larsen, September 2012. 

    # Reads a sequence file and returns a list of read-ahead integers. Reading
    # as many sequences the these integers say will give sequence sets with 
    # approximately the same combined length. This helps split a larger input
    # file into smaller ones to be processed separately, on each their cpu 
    # core for example.

    my ( $file,    # Input file
         $args,    # Arguments hash
        ) = @_;

    # Returns list.

    my ( $divs, $readbuf, $routine, $fh, $seqs, @lens, @offs, 
         $lensum, $divsum, $seq, $len, $seqndx, $off );

    $divs = $args->{"splits"};
    $readbuf = $args->{"readbuf"};

    # Read the file and create a list of lengths,

    $routine = &Seq::IO::get_read_routine( $file );
    $lensum = 0;
    
    $fh = &Common::File::get_read_handle( $file );

    {
        no strict "refs";

        while ( $seqs = $routine->( $fh, $readbuf ) )
        {
            foreach $seq ( @{ $seqs } )
            {
                push @lens, ( $len = length $seq->{"seq"} );

                $lensum += $len;
            }
        }
    }

    &Common::File::close_handle( $fh );

    # Go through the lengths and record the indices where the byte count
    # hits the desired average,

    $divsum = $lensum / $divs;
    $lensum = 0;
    $off = 0;

    for ( $seqndx = 0; $seqndx <= $#lens; $seqndx++ )
    {
        if ( $lensum >= $divsum )
        {
            push @offs, $off;

            $lensum = 0;
            $off = 0;
        }

        $lensum += $lens[$seqndx];
        $off += 1;
    }
    
    if ( scalar @offs < $divs ) {
        push @offs, $off;
    }

    return wantarray ? @offs : \@offs;
}

sub merge_sim_files
{
    # Niels Larsen, May 2013.

    # Reads two similarity files and writes a new one with the highest 
    # similarities of the two. The input files must have the same number 
    # of lines and the same number of query sequences. Returns the number
    # of lines written.

    my ( $file1,     # Input similarity table
         $file2,     # Input similarity table
         $ofile,     # Output similarity table
         $topsim,    # Top similarity range written
        ) = @_;

    # Returns integer.

    my ( $ifh1, $ifh2, $ofh, $line1, $line2, $row1, $row2, @sims, $id, 
         $pct, $sims1, $sims2, $maxpct, $i1, $i2, $imax1, $imax2, $line,
         $lines );

    $topsim //= 0;

    $ifh1 = &Common::File::get_read_handle( $file1 );
    $ifh2 = &Common::File::get_read_handle( $file2 );

    $ofh = &Common::File::get_write_handle( $ofile );
    
    $lines = 0;

    while ( defined ( $line1 = <$ifh1> ) )
    {
        if ( not defined ( $line2 = <$ifh2> ) ) {
            &error( qq (Unexpected end of file reached -> "$file2") );
        }

        $row1 = &Seq::Simrank::parse_sim_line( \$line1, 1 );
        $row2 = &Seq::Simrank::parse_sim_line( \$line2, 1 );

        if ( $row1->[0] ne $row2->[0] ) {
            &error( qq (Query id 1 is "$row1->[0]" but id 2 is "$row2->[0]"\n)
                    .qq (The two given similarity files are from different query data.) );
        }
        
        $sims1 = $row1->[2];
        $sims2 = $row2->[2];
        
        $i1 = 0;
        $i2 = 0;
        
        $imax1 = $#{ $sims1 } if defined $sims1;
        $imax2 = $#{ $sims2 } if defined $sims2;
        
        @sims = ();
        
        if ( defined $sims1 and defined $sims2 )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>> INTERLEAVE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            $maxpct = &List::Util::max( $sims1->[0]->[1], $sims2->[0]->[1] );
            
            while ( $i1 <= $imax1 or $i2 <= $imax2 )
            {
                if ( $i1 <= $imax1 and $i2 <= $imax2 )
                {
                    if ( $sims1->[$i1]->[1] <= $sims2->[$i2]->[1] )
                    {
                        ( $id, $pct ) = @{ $sims2->[$i2] };
                        $i2 += 1;
                    }
                    else
                    {
                        ( $id, $pct ) = @{ $sims1->[$i1] };
                        $i1 += 1;
                    }
                }
                elsif ( $i1 > $imax1 )
                {
                    ( $id, $pct ) = @{ $sims2->[$i2] };
                    $i2 += 1;
                }
                elsif ( $i2 > $imax2 )
                {
                    ( $id, $pct ) = @{ $sims1->[$i1] };
                    $i1 += 1;
                }
                
                if ( $maxpct - $pct <= $topsim ) {
                    push @sims, [ $id, $pct ];
                } else {
                    last;
                }
            }
        }
        elsif ( defined $sims1 )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>> COPY FROM 1 <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            $maxpct = $sims1->[0]->[1];
            
            while ( $i1 <= $imax1 and ( $maxpct - $sims1->[$i1]->[1] ) <= $topsim )
            {
                push @sims, [ @{ $sims1->[$i1] } ];
                $i1 += 1;
            }
        }
        elsif ( defined $sims2 )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>> COPY FROM 2 <<<<<<<<<<<<<<<<<<<<<<<<<<<<

            $maxpct = $sims2->[0]->[1];
            
            while ( $i2 <= $imax2 and ( $maxpct - $sims2->[$i2]->[1] ) <= $topsim )
            {
                push @sims, [ @{ $sims2->[$i2] } ];
                $i2 += 1;
            }
        }
        
        $line = &Seq::Simrank::format_sim_line([ @{ $row1 }[0...1], \@sims ]);
        $ofh->print( $line );

        $lines += 1;
    }
    
    if ( defined ( $line2 = <$ifh2> ) ) {
        &error( qq (Unexpected end of file reached -> "$file1") );
    }

    &Common::File::close_handle( $ifh1 );
    &Common::File::close_handle( $ifh2 );
    &Common::File::close_handle( $ofh );

    return $lines;
}

sub parse_sim_line
{
    # Niels Larsen, May 2013.

    # Parses a Simrank similarity line into a list. If no indices are given
    # then all columns in the file are in the list in the order they appear:
    # [ query-id, query-oligo-count, [[db-id, hit-pct],[db-id, hit-pct], ..]
    # But the second argument can be used to get only wanted columns, so for
    # example if given [0,2] the output will have query-id and similarities 
    # only. If given [2,0] then the order is reversed. If there are no 
    # similarities the last element is missing. Returns a list with one or 
    # more elements.

    my ( $line,     # Simrank similarity table line or line reference
         $split,    # Split the similarity column or not - OPTIONAL, default 0
        ) = @_;

    # Returns a list.

    my ( $sref, @cols, @sim, $ndx );

    if ( ref $line ) {
        $sref = $line;
    } else {
        $sref = \$line;
    }

    chomp ${ $sref };

    @cols = split "\t", ${ $sref };

    if ( $cols[2] )
    {
        if ( $split ) {
            $cols[2] = [ map {[ split "=", $_ ]} split " ", $cols[2] ];
        }
    }
    else {
        $cols[2] = undef;
    }

    return wantarray ? @cols : \@cols;
};
         
sub read_db_map
{
    # Niels Larsen, August 2012.

    # Reads an oligo map written with write_db_map in this module. This
    # works as a cache and save a few seconds or minutes if the file is big.

    my ( $file,
        ) = @_;

    # Returns a hash.

    my ( $map_file, $ndcs_len, $begs_len, $lens_len, $sums_len, $fh, $buffer,
         $map, $seq_num, $word_len, $sids_len );

    $fh = &Common::File::get_read_handle( $file );

    read $fh, $buffer, 120;

    $word_len = ( substr $buffer, 0, 20 ) * 1;
    $ndcs_len = ( substr $buffer, 20, 20 ) * 1;
    $begs_len = ( substr $buffer, 40, 20 ) * 1;
    $lens_len = ( substr $buffer, 60, 20 ) * 1;
    $sums_len = ( substr $buffer, 80, 20 ) * 1;
    $seq_num = ( substr $buffer, 100, 20 ) * 1;

    $map->{"wlen"} = $word_len;
    $map->{"stot"} = $seq_num;

    read $fh, ${ $map->{"ndcs"} }, $ndcs_len;
    read $fh, ${ $map->{"begs"} }, $begs_len;
    read $fh, ${ $map->{"lens"} }, $lens_len;
    read $fh, ${ $map->{"sums"} }, $sums_len;

    $sids_len = ( -s $file ) - ( tell $fh ) + 1;
    read $fh, $map->{"sids"}, $sids_len;

    $map->{"sids"} = Data::MessagePack->unpack( $map->{"sids"} );

    &Common::File::close_handle( $fh );

    return $map;
}

sub read_query_map
{
    # Niels Larsen, September 2012. 

    # Reads an oligo map from file, the opposite of what write_query_map
    # does. 

    my ( $file,     # Input file
        ) = @_;

    # Returns a hash.

    my ( $fh, $buffer, $word_len, $step_len, $seqs_tot, $sids_len, 
         $begs_len, $sums_len, $olis_len, $map, $sids_str );

    $fh = &Common::File::get_read_handle( $file );

    read $fh, $buffer, 140;

    $word_len = ( substr $buffer, 0, 20 ) * 1;
    $step_len = ( substr $buffer, 20, 20 ) * 1;
    $seqs_tot = ( substr $buffer, 40, 20 ) * 1;

    $sids_len = ( substr $buffer, 60, 20 ) * 1;
    $begs_len = ( substr $buffer, 80, 20 ) * 1;
    $sums_len = ( substr $buffer, 100, 20 ) * 1;
    $olis_len = ( substr $buffer, 120, 20 ) * 1;

    $map->{"wordlen"} = $word_len;
    $map->{"steplen"} = $step_len;
    $map->{"seqstot"} = $seqs_tot;

    read $fh, $sids_str, $sids_len;
    $map->{"sids"} = Data::MessagePack->unpack( $sids_str );

    read $fh, ${ $map->{"begs"} }, $begs_len;
    read $fh, ${ $map->{"sums"} }, $sums_len;
    read $fh, ${ $map->{"olis"} }, $olis_len;

    &Common::File::close_handle( $fh );

    return bless $map;
}

sub write_db_map
{
    # Niels Larsen, September 2012. 

    # Writes a given oligo map to cache file, from which it can be reloaded
    # quickly. Returns nothing.

    my ( $file,     # Output file
         $map,      # Oligo map
        ) = @_;

    # Returns nothing.

    my ( $map_file, $ndcs_len, $begs_len, $lens_len, $sums_len, $seq_num,
         $fh, $word_len );

    &Common::File::delete_file_if_exists( $file );

    $fh = &Common::File::get_write_handle( $file );

    $word_len = sprintf "%20s", $map->{"wlen"};
    $ndcs_len = sprintf "%20s", length ${ $map->{"ndcs"} };
    $begs_len = sprintf "%20s", length ${ $map->{"begs"} };
    $lens_len = sprintf "%20s", length ${ $map->{"lens"} };
    $sums_len = sprintf "%20s", length ${ $map->{"sums"} };
    $seq_num = sprintf "%20s", $map->{"stot"};

    $fh->print( $word_len . $ndcs_len . $begs_len . $lens_len . $sums_len . $seq_num );

    $fh->print( ${ $map->{"ndcs"} } );
    $fh->print( ${ $map->{"begs"} } );
    $fh->print( ${ $map->{"lens"} } );
    $fh->print( ${ $map->{"sums"} } );

    $fh->print( Data::MessagePack->pack( $map->{"sids"} ) );

    &Common::File::close_handle( $fh );

    return;
}

sub write_db_maps
{
    # Niels Larsen, September 2012. 

    # Reads a sequence file in chunks, creates a map for each (see create_db_map)
    # and writes each to named file in a given directory. 

    my ( $file,
         $dir,
         $args,
        ) = @_;

    my ( $seqs, $fh, $map_args, $map, $map_file, $seq_count );

    &Common::File::delete_dir_tree( $dir );
    &Common::File::create_dir( $dir );

    $map_args = bless {
        "wordlen" => $args->wordlen,
        "wconly" => $args->wconly,
    };
    
    $fh = &Common::File::get_read_handle( $file );
    $seq_count = 0;

    while ( $seqs = &Seq::IO::read_seqs_filter( $fh, $args ) )
    {
        $map = &Seq::Simrank::create_db_map( $seqs, $map_args );

        $map_file = "$dir/$seq_count";
        &Seq::Simrank::write_db_map( $map_file, $map );

        $seq_count += scalar @{ $seqs };
    }

    &Common::File::close_handle( $fh );

    &Common::File::write_file( "$dir/TOTAL", $seq_count );

    return $seq_count;
}

sub write_query_map
{
    # Niels Larsen, September 2012. 

    # Writes a given oligo map to file, from which it can be loaded by the
    # read_query_map routine. Returns nothing.

    my ( $file,     # Output file
         $map,      # Oligo map
        ) = @_;

    # Returns nothing.

    my ( $fh, $word_len, $step_len, $seqs_tot, $sids_len, $begs_len, $sums_len,
         $olis_len, $sids_ref );

    $fh = &Common::File::get_write_handle( $file );

    $word_len = sprintf "%20s", $map->{"wordlen"};
    $step_len = sprintf "%20s", $map->{"steplen"};
    $seqs_tot = sprintf "%20s", $map->{"seqstot"};

    $sids_ref = \Data::MessagePack->pack( $map->{"sids"} );
    $sids_len = sprintf "%20s", length ${ $sids_ref };

    $begs_len = sprintf "%20s", length ${ $map->{"begs"} };
    $sums_len = sprintf "%20s", length ${ $map->{"sums"} };
    $olis_len = sprintf "%20s", length ${ $map->{"olis"} };

    $fh->print( $word_len . $step_len . $seqs_tot . $sids_len . $begs_len . $sums_len . $olis_len );

    $fh->print( ${ $sids_ref } );
    $fh->print( ${ $map->{"begs"} } );
    $fh->print( ${ $map->{"sums"} } );
    $fh->print( ${ $map->{"olis"} } );

    &Common::File::close_handle( $fh );

    return;
}

sub write_query_maps
{
    # Niels Larsen, September 2012. 

    # Reads a sequence file and writes query maps of approximately equal byte size.
    # The outputs are named "map_1", "map_2" etc, and they are written in the given
    # directory. The number of maps is determined by the "splits" argument key.
    # Returns a list of map version numbers.

    my ( $file,    # Sequence file
         $args,    # Arguments hash
        ) = @_;

    # Returns a list.

    my ( $splits, $fh, $tmp_dir, @sums, $sum, $routine, $map, @map_files, 
         $map_file, $clobber, $num, $seqs, $forward, $reverse, $prefix,
         $fwd_file, $rev_file, $read_buf );

    $tmp_dir = $args->tmpdir;
    $splits = $args->splits;
    $clobber = $args->clobber;
    $forward = $args->forward;
    $reverse = $args->reverse;
    $read_buf = $args->readbuf;

    if ( $clobber ) {
        &Common::File::create_dir_if_not_exists( $tmp_dir );
    }

    # Get read-ahead numbers of sequences with equal combined length,

    @sums = &Seq::Simrank::measure_splits( $file, { "splits" => $splits, "readbuf" => $read_buf } );
    
    # Write the given number of oligo maps into the given directory,

    $fh = &Common::File::get_read_handle( $file );

    $routine = &Seq::IO::get_read_routine( $file );
    $num = 0;

    foreach $sum ( @sums )
    {
        no strict "refs";

        $seqs = $routine->( $fh, $sum );
        $prefix = "$tmp_dir/map_" . ++$num;

        push @map_files, {};

        if ( $forward )
        {
            $fwd_file = "$prefix.F";
            &Common::File::delete_file_if_exists( $fwd_file ) if $clobber;

            $map = &Seq::Simrank::create_query_map( $seqs, $args );
            &Seq::Simrank::write_query_map( $fwd_file, $map );

            $map_files[-1]->{"fwd"} = $fwd_file;
        }

        if ( $reverse )
        {
            $rev_file = "$prefix.R";
            &Common::File::delete_file_if_exists( $rev_file ) if $clobber;

            &Seq::List::change_complement( $seqs );

            $map = &Seq::Simrank::create_query_map( $seqs, $args );
            &Seq::Simrank::write_query_map( $rev_file, $map );

            $map_files[-1]->{"rev"} = $rev_file;
        }
    }

    &Common::File::close_handle( $fh );

    return wantarray ? @map_files : \@map_files;
}

sub write_sims
{
    # Niels Larsen, March 2012. 

    # Prints similarities as a three-column table with lines like this:
    # 
    # query id<tab>query oligos total<tab>dbid=pct dbid=pct ... 
    #
    # Memory based, lists of similarities given.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $fh, $ndx, @pcts, @dbids, $numids, $dbsims, $qids, $qsums, $dbids, 
         $dbndcs, $i, $j, $simfmt, $maxout );

    $qids = $args->{"qids"};
    $qsums = [ unpack "V*", ${ $args->{"qsums"} } ];

    $dbids = $args->{"dbids"};
    $dbsims = $args->{"dbsims"};
    $dbndcs = $args->{"dbsids"};
    $numids = $args->{"numids"};
    $simfmt = $args->{"simfmt"};
    $maxout = $args->{"maxout"};

    if ( ( $i = scalar @{ $qsums } ) != ( $j = scalar @{ $dbsims } ) ) {
        &error( qq (Number of query sequences is $i, but number of similarities $j. Programming error.) );
    }

    $fh = &Common::File::get_write_handle( $args->{"otable"} );

    if ( $numids )
    {
        for ( $ndx = 0; $ndx < scalar @{ $dbsims }; $ndx += 1 )
        {
            $fh->print( ($ndx + 1) ."\t". $qsums->[$ndx] );
            
            if ( $dbsims->[$ndx] )
            {
                @pcts = map { sprintf $simfmt, $_ * 100 } ( unpack "f$maxout", $dbsims->[$ndx] );

                if ( $pcts[0] > 0 )
                {
                    @dbids = map { $_ + 1 } unpack "V*", $dbndcs->[$ndx];
                    $fh->print( "\t". ( join " ", map { $dbids[$_] ."=". $pcts[$_] } 0 ... $#pcts ) );
                }
            }

            $fh->print("\n");
        }
    }
    else
    {
        for ( $ndx = 0; $ndx < scalar @{ $dbsims }; $ndx += 1 )
        {
            $fh->print( $qids->[$ndx] ."\t". $qsums->[$ndx] );

            if ( $dbsims->[$ndx] ) 
            {
                @pcts = map { sprintf $simfmt, $_ * 100 } ( unpack "f$maxout", $dbsims->[$ndx] );
                
                if ( $pcts[0] > 0 ) 
                {
                    @dbids = map { $dbids->[$_] } ( unpack "V*", $dbndcs->[$ndx] );
                    $fh->print( "\t". ( join " ", map { $dbids[$_] ."=". $pcts[$_] } 0 ... $#pcts ) );
                }
            }

            $fh->print("\n");
        }
    }

    &Common::File::close_handle( $fh );

    return;
}

1;

__DATA__

__C__

/* >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< */

/* Function to get the C value (a pointer usually) of a Perl scalar */

static void* get_ptr( SV* obj ) { return SvPVX( obj ); }

/*
  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  All functions below use Perl\'s memory management, no mallocs. They do not 
  use the Perl stack, which would be quite slow. No C-structures, just simple
  1-D arrays. 

  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
*/

float find_max_value_C( float *arr, unsigned int len )
{
    float max=0;
    unsigned int i;

    for ( i = 0; i < len; i++ )
    {
        if ( arr[i] > max ) {
            max = arr[i];
        }
    }

    return max;
}
    
unsigned int measure_sims_C( SV* q_olis_sv, SV* q_begs_sv, SV* q_sums_sv, unsigned int q_num,
                             SV* db_ndcs_sv, SV* db_begs_sv, SV* db_lens_sv, SV* db_sums_sv,
                             unsigned int db_stot, SV* db_mats_sv, SV* db_scor_sv, SV* db_ids_sv, 
                             float minsim, float maxdif, unsigned int ndx_add )
{
    /*
      Niels Larsen, March 2012. 
      
      Compares one oligofied query sequence against a map of dataset sequences. 
      Each oligo of the query sequence is used as a lookup index into the map.
      The map returns a list of dataset sequence ids (their zero-based index)
      that have that oligo. Counts are then summed up. 

      Similarities are made by dividing the match count by the smallest number 
      of oligos in either the query or the dataset sequence. That way a short 
      sequence can match a longer one 100%.

      Similarities are filtered first by a given minimum, then by a given top
      range from the maximum and down. 

      There are many arguments, because Perl does all memory management, think
      it is safer and faster. So in Perl strings are created with the right 
      size and initial values to map to C arrays. Three arguments are used as 
      writable buffers: db_mats, db_scor and db_ids; the rest are only read 
      from.

      The return value is the number of elements in those three buffers which 
      has data that passed the minsim and maxdif requirements. A zero return
      value means no match.
    */

    /*
      Read only:

      q_olis: array of integer oligo ids for all query sequences.
      q_begs: array of starting positions in q_olis for each query sequence.
      q_sums: array of oligo counts for each query sequence. When one of those
              counts are added to the corresponding begin offset in q_olis, 
              then that points to the end in q_olis.
    */

    unsigned int* q_olis = get_ptr( q_olis_sv );
    unsigned long* q_begs = get_ptr( q_begs_sv );
    unsigned int* q_sums = get_ptr( q_sums_sv );

    /*
      Read only:
      
      db_ndcs: array of sequence indices for all oligos
      db_begs: array of offsets into db_ndcs for each oligo
      db_lens: array of sequence totals for each oligo
      db_sums: array of oligo totals for each sequence
    */

    unsigned int* db_ndcs = get_ptr( db_ndcs_sv );
    unsigned long* db_begs = get_ptr( db_begs_sv );
    unsigned int* db_lens = get_ptr( db_lens_sv );
    unsigned int* db_sums = get_ptr( db_sums_sv );

    /*
      Read-write buffers:
    */

    unsigned int* db_mats = get_ptr( db_mats_sv );
    unsigned int* db_ids = get_ptr( db_ids_sv );

    float* db_scor = get_ptr( db_scor_sv );

    int oli, i;
    unsigned long q_beg, q_ndx, db_beg, db_ndx;
    int q_sum, db_sum, db_len;
    int sim_ndx, max_ndx;

    float match, sim, sim_max;

    /* Initialize db_mats array with zeroes */

    memset( db_mats, 0, sizeof(int) * db_stot );

    /*
      Create db_mats
 
      This double loop says: for every oligo in a given query sequence (q), 
      increment the match score for every database (db) sequence that has 
      it. The db sequences that have it is stored in db_ndcs which is given.
      When this is done, the db_mats array holds the number of oligos in 
      common with the query sequence.
    */

    q_beg = q_begs[q_num];
    q_sum = q_sums[q_num];

    // printf("q_num, q_beg, q_sum: %d, %d, %d\n", q_num, q_beg, q_sum );

    for ( q_ndx = q_beg; q_ndx <= q_beg + q_sum - 1; q_ndx++ )
    {
        oli = q_olis[q_ndx];
        db_len = db_lens[oli];

        // printf("q_ndx, oli, db_len: %d, %d, %d\n", q_ndx, oli, db_len );
        
        if ( db_len > 0 )
        {
            db_beg = db_begs[oli];

            for ( db_ndx = db_beg; db_ndx <= db_beg + db_len - 1; db_ndx++ )
            {
                db_mats[ db_ndcs[db_ndx] ]++;
            }
        }
    }

    /*
      Create db_ids and db_scor

      Use the number of shared oligos from above, then divide by the smallest 
      number of oligos found in either query or dataset sequence. Then short 
      sequences embedded in longer ones will match 100%. The db_scor array is
      filled with values that are at least the user specified minsim. The 
      number of such similarities is returned. 
    */

    sim_ndx = 0;
    sim_max = 0;

    for ( db_ndx = 0; db_ndx < db_stot; db_ndx++ )
    {
        db_sum = db_sums[db_ndx];
        
        if ( q_sum > db_sum ) {
            sim = (float)db_mats[db_ndx] / db_sum;
        } else {
            sim = (float)db_mats[db_ndx] / q_sum;
        }
        
        if ( sim >= minsim )
        {
            db_scor[sim_ndx] = sim;
            db_ids[sim_ndx] = db_ndx + ndx_add;
            
            sim_ndx++;
            
            if ( sim > sim_max ) {
                sim_max = sim;
            }
        }
    }

    /* 
       Get maxdif best similarities
    */

    max_ndx = sim_ndx;
    sim_ndx = 0;

    for ( i = 0; i < max_ndx; i++ )
    {
        if ( ( sim_max - db_scor[i] ) <= maxdif )
        {
            db_scor[sim_ndx] = db_scor[i];
            db_ids[sim_ndx] = db_ids[i];

            sim_ndx++;
        }
    }

    return sim_ndx;
}

unsigned int merge_sims_C( SV* oldids_sv, SV* oldsco_sv, unsigned int oldlen,
                           SV* addids_sv, SV* addsco_sv, unsigned int addlen,
                           SV* newids_sv, SV* newsco_sv, float maxdif )
{
    /*
      Niels Larsen, May 2012.

      Merges scores and ids from addids/addsco with oldids/oldsco and stores 
      them into newids/newsco. The ids are dataset zero-based integer indices
      and the scores are floating point values in the 0 -> 1 range.
      
      The oldids/oldsco arrays is assumed to be sorted in decreasing order, 
      but the addids/addsco arrays are sorted that way in this routine. If
      maximum addsco value is more than maxdif less than the maximum oldsco
      value, then no interleaving will happen and the routine returns zero. 

      The return value is the number of elements in newids/newsco which the 
      caller should use. A return value of zero tells the caller to just 
      keep using oldids/oldsco. 

      This routine is critical and after the __END__ there is perl script 
      that can be used for testing, should a bug-suspicion arise. 
    */

    unsigned int* oldids = get_ptr( oldids_sv );
    unsigned int* addids = get_ptr( addids_sv );
    unsigned int* newids = get_ptr( newids_sv );

    float* oldsco = get_ptr( oldsco_sv );
    float* addsco = get_ptr( addsco_sv );
    float* newsco = get_ptr( newsco_sv );

    float addmax, oldmax, maxsco;
    int io, ia, in;

    /*
      Only merge if the highest value in the new list is higher than the existing
      highest value minus maxdif. There is no need to add values that will never
      be in the output anyway.
    */

    addmax = find_max_value_C( addsco, addlen );
    oldmax = oldsco[0];

    in = 0;

    if ( addmax >= ( oldmax - maxdif ) )
    {
        /*
          Sort addids/addsco in descending order. TODO: fix the sort instead of
          sorting ascending first, then reverse the list ... 
        */

        quicksort_two_C( addids, addsco, addlen );
        reverse_arrays_C( addids, addsco, addlen );
        
        /*
          Find the highest value in either oldsco or addsco, so we know when to
          stop adding below 
        */

        if ( oldsco[0] > addsco[0] ) {
            maxsco = oldsco[0];
        } else {
            maxsco = addsco[0];
        }            
        
        io = 0;
        ia = 0;

        while ( 1 )
        {
            /*
              Logic: if the old value is higher than the new, add it and advance its 
              index. Otherwise, if old is equal or less than new, then advance the new
              index until that no more is true. That will progress until 1) the end of 
              either list is reached, or 2) the added value is too different from the 
              maximum. Unused parts of either list is handled below.
            */

            if ( oldsco[io] > addsco[ia] )
            {
                newids[in] = oldids[io];
                newsco[in] = oldsco[io];

                if ( io < oldlen ) {
                    io++;
                } else {
                    break;
                }
            }
            else
            {
                newids[in] = addids[ia];
                newsco[in] = addsco[ia];

                if ( ia < addlen ) {
                    ia++;
                } else {
                    break;
                }
            }

            if ( (maxsco - newsco[in]) > maxdif ) {
                break;
            }

            in++;
        }

        /*
          This says: if the old list reached the end, then take from the new until 
          the maximum is exceeded, like above. And vice versa for the add list.
        */

        if ( io >= oldlen )
        {
            while ( ia < addlen && (maxsco-addsco[ia]) <= maxdif )
            {
                newids[in] = addids[ia];
                newsco[in++] = addsco[ia++];
            }
        }
        else if ( ia >= addlen )
        {
            while ( io < oldlen && (maxsco-oldsco[io]) <= maxdif )
            {
                newids[in] = oldids[io];
                newsco[in++] = oldsco[io++];
            }
        }
    }
      
    return in;
}

void quicksort_two_C( unsigned int* arr2, float* arr1, unsigned int elements )
{
    /*
      Niels Larsen, 2012. 

      Modified from original by Darel Rex Finley, 2007 posted at 
      http://alienryderflex.com/quicksort
    */

#define  MAX_LEVELS  300
    
    float piv, fval, f;

    int piv2, beg[MAX_LEVELS], end[MAX_LEVELS], i=0, L, R, swap, ival, j;
    int v;

    beg[0]=0; end[0]=elements;

    while ( i >= 0 )
    {
        L = beg[i]; 
        R = end[i]-1;

        if ( L < R )
        {
            piv = arr1[L];
            piv2 = arr2[L];

            while ( L < R )
            {
                while ( arr1[R] >= piv && L < R ) R--; 

                if ( L < R )
                {
                    arr1[L] = arr1[R];
                    arr2[L++] = arr2[R];
                }

                while ( arr1[L] <= piv && L < R ) L++;
                
                if ( L < R ) {
                    arr1[R] = arr1[L];
                    arr2[R--] = arr2[L];
                }
            }

            arr1[L] = piv; 
            arr2[L] = piv2; 

            beg[i+1] = L+1;
            end[i+1] = end[i];
            end[i++] = L;

            if ( end[i] - beg[i] > end[i-1] - beg[i-1] )
            {
                swap = beg[i]; beg[i] = beg[i-1]; beg[i-1] = swap;
                swap = end[i]; end[i] = end[i-1]; end[i-1] = swap;
            }
        }
        else {
            i--;
        }
    }

    return;
}

void reverse_arrays_C( unsigned int* arr1, float* arr2, unsigned int len )
{
    //int* arr1 = get_ptr( arr1_sv );
    //float* arr2 = get_ptr( arr2_sv );

    int i, j, v;
    float f;

    i = 0;
    j = len - 1;

    while ( i < j )
    {
        v = arr1[i];
        arr1[i] = arr1[j];
        arr1[j] = v;

        f = arr2[i];
        arr2[i] = arr2[j];
        arr2[j] = f;

        i++;
        j--;
    }

    return;
}

__END__

#include <stdlib.h>
#include <string.h>

typedef unsigned short uint16_t;
typedef unsigned int uint32_t;

#if __WORDSIZE == 32
typedef unsigned long uint64_t;
#endif

/* see more in /usr/include/stdint.h */


--------------------------------------------------------------------------------------------------

TEST SCRIPT for merge_sims_C

#!/usr/bin/env perl

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

use Seq::Simrank;

my ( $count,
     @oldids, $oldids, @oldsco, $oldsco, $oldlen, 
     @addids, $addids, @addsco, $addsco, $addlen,
     $newids, $newsco, $newlen, $maxdif
    );

# @oldids = ( 1,2 );
# @addids = ( 20,30, 6 );
# @oldsco = ( .99, .99 );
# @addsco = ( .18, .19, .19 );

@oldids = ( 20,30, 6 );
@addids = ( 1,2 );
@oldsco = ( .20, .19, .19 );
@addsco = ( .99, .98 );

$oldlen = scalar @oldsco;
$addlen = scalar @addsco;
$newlen = $oldlen + $addlen;

$maxdif = 1;

$oldids = pack "V*", @oldids;
$addids = pack "V*", @addids;
$newids = pack "V*", (0) x $newlen;

$oldsco = pack "f*", @oldsco;
$addsco = pack "f*", @addsco;
$newsco = pack "f*", (0) x $newlen;

$count = &Seq::Simrank::merge_sims_C(
    $oldids, $oldsco, $oldlen,
    $addids, $addsco, $addlen,
    $newids, $newsco, $newlen,
    $maxdif,
    );

if ( $count > 0 ) {
    &dump([ unpack "i*", substr $newids, 0, $count*4 ]);
    &dump([ unpack "f*", substr $newsco, 0, $count*4 ]);
} else {
    &dump( \@oldids );
    &dump( \@oldsco );
}

--------------------------------------------------------------------------------------------------

Garbage can from here on, but dont delete yet. 

Niels, September 2012.


int oli_to_number_C( SV* oliseq_sv )
{
    /*
      Niels Larsen, February 2012.

      Converts a sub-sequence to a number.

      Returns an integer.
    */

    char* oliseq = get_ptr( oliseq_sv );
    int olinum, i;

    olinum = 0;
    
    for ( i = 0; i < strlen( oliseq ); i++ )
    {
        olinum = olinum << 2;
        olinum = olinum | bcodes[ oliseq[i] ];
    }

    return olinum;
}


void init_test( SV* oldsco_sv, int len )
{
    float* oldsco = get_ptr( oldsco_sv );
    int i;

    for ( i = 0; i < len; i++ )
    {
        printf("val = %.2f\n", oldsco[i] );
    }

    return;
}

void test_ptr()
{
    int ArrayA[3]={1,2,3};

    int *ptr;
    ptr=ArrayA;
    printf("address: %p - array value:%d\n",ptr,*ptr);
    ptr++;
    printf("address: %p - array value:%d\n",ptr,*ptr);                     

    return;
}

void test_ptr2( SV* arr_sv, int len )
{
    unsigned short* arr = get_ptr( arr_sv );
    int i;
    unsigned short *ptr;

    ptr = arr;

    for ( i = 0; i < len; i++ )
    {
        printf("val = %d\n", *ptr );
        ptr++;
    }

    return;
}

void test_cache( SV* arr_sv, int len )
{
    unsigned short* arr = get_ptr( arr_sv );
    int i, j;

    for ( j = 0; j < 10000; j++ )
    {
        for ( i = 0; i < len; i = i + 2 )
        {
            arr[i]++;
            arr[i+1]++;
        }
    }

    return;
}

void test_jump( SV* arr1_sv, SV* arr2_sv, int len )
{
    unsigned short* arr1 = get_ptr( arr1_sv );
    unsigned short* arr2 = get_ptr( arr2_sv );

    int i, j;

    for ( j = 0; j < 10000; j++ )
    {
        for ( i = 0; i < len; i++ )
        {
            arr1[i]++;
            arr2[i]++;
        }
    }

    return;
}

void test_jump_static()
{
    int dim = 100000;

    int arr1[dim];
    int arr2[dim];

    int i, j;

    for ( j = 0; j < 10000; j++ )
    {
        for ( i = 0; i < dim; i++ )
        {
            arr1[i]++;
            arr2[i]++;
        }
    }

    return;
}

void add_int_array_C( SV* arr_sv, int add, int len )
{
    /*
      Niels Larsen, September 2012.

      Adds the given value to all elements on the given unsigned integer 
      array. The resulting array elements should not be negative. Returns 
      nothing.
    */

    unsigned int* arr = get_ptr( arr_sv );

    int i;

    for ( i = 0; i < len; i++ )
    {
        arr[i] += add;
    }            
    
    return;
}

    # if ( not ref $q_seqs ) 
    # {
    #     &echo("   Reading query sequences ... ");
        
    #     $read_args{"format"} = $conf->format // &Seq::IO::detect_format( $q_seqs );

    #     $q_fh = &Common::File::get_read_handle( $q_seqs );
    #     $q_seqs = &Seq::Simrank::read_seqs( $q_fh, \%read_args );
    #     &Common::File::close_handle( $q_fh );

    #     &echo_done( scalar @{ $q_seqs } ." seq[s]\n" );
    # }

    # if ( not $q_seqs or not @{ $q_seqs } )
    # {
    #     push @msgs, ["ERROR", qq (No query sequences) ];
        
    #     if ( $conf->filter ) {
    #         push @msgs, ["INFO", qq (This can happen if the filter expression does not match,) ];
    #         push @msgs, ["INFO", qq (or if the sequence file has no entries, please check.) ];
    #     } else {
    #         push @msgs, ["INFO", qq (This can happen if the file has no entries, please check.) ];
    #     }
     
    #     &echo("\n");
    #     &append_or_exit( \@msgs );
    # }


# sub is_query_map_cached
# {
#     # Niels Larsen, August 2012. 

#     # Returns 1 if there is an up to date cache version of the given reference
#     # file, otherwise nothing.

#     my ( $seqf,     # Sequence file
#          $mapf,     # Map file
#          $wlen,     # Word length required
#          $slen,     # Step length required
#         ) = @_;

#     # Returns 1 or nothing.
    
#     my ( $fh, $wlen_map, $slen_map, $buffer );

#     if ( -r $seqf and 
#          &Common::File::is_newer_than( $mapf, $seqf ) )
#     {
#         $fh = &Common::File::get_read_handle( $mapf );
#         read $fh, $buffer, 40;
#         &Common::File::close_handle( $fh );

#         $wlen_map = ( substr $buffer, 0, 20 ) * 1;
#         $slen_map = ( substr $buffer, 20, 20 ) * 1;

#         return 1 if $wlen == $wlen_map and $slen == $slen_map;
#     }

#     return;
# }

# sub parallel_arg_string
# {
#     # Niels Larsen, June 2012. 

#     # Helper routine that creates a command line argument string for the 
#     # parallel calls.

#     my ( $args,
#         ) = @_;

#     # Returns a string.

#     my ( $cmd, $conf, $key, %skip, %bool, $argstr );

#     $argstr = "";

#     $argstr .= "--cores 1";

#     $argstr .= "--dbdegap ". $args->dbdegap if $args->dbdegap;
#     $argstr .= "--dbminlen ". $args->dbminlen if defined $args->dbminlen;
#     $argstr .= "--dbfilter ". $args->dbfilter if defined $args->dbfilter;
#     $argstr .= "--dbread ". $args->dbread if defined $args->dbread;
#     $argstr .= "--minsim ". $args->minsim if defined $args->minsim;
#     $argstr .= "--topsim ". $args->topsim if defined $args->topsim;
#     $argstr .= "--maxout ". $args->maxout if defined $args->maxout;
#     $argstr .= "--simfmt ". $args->simfmt if defined $args->simfmt;
#     $argstr .= "--numids ". $args->numids if $args->numids;

#     $argstr .= "--silent";
    
#     %skip = (
#         "readlen" => 1,
#         "dbformat" => 1,
#         "qseqs" => 1,
#         "silent" => 1,
#         "clobber" => 1,
#         "debug" => 1,
#         "parallel" => 1,
#         );

#     %bool = (
#         "forward" => 1,
#         "reverse" => 1,
#         "degap" => 1,
#         "dbdegap" => 1,
#         "wconly" => 1,
#         "numids" => 1,
#         );

#     $argstr = "";

#     foreach $key ( keys %{ $args } )
#     {
#         next if $skip{ $key };

#         if ( defined $args->{ $key } )
#         {
#             if ( exists $bool{ $key } )
#             {
#                 if ( $args->{ $key } ) {
#                     $argstr .= " --$key";
#                 } else {
#                     $argstr .= " --no$key";
#                 }
#             }
#             else {
#                 $argstr .= " --$key '$args->{ $key }'";
#             }                
#         }
#     }

#     $argstr =~ s/^\s*//;

#     return $argstr;
# }

# sub read_query_map_wrong_idea
# {
#     # Niels Larsen, September 2012.

#     # Reads an oligo map from file, or part of it. Only oligos from the 
#     # requested sequence range (default all) are loaded: if $beg is given
#     # as 10 and $end is 19, then only the oligos from sequences 10 through
#     # 19 are loaded. This saves memory and is good for multiple-core runs 
#     # for example. For map description, see the create_query_map routine
#     # which writes the map.

#     my ( $file,     # Map file
#          $beg,      # Index of first sequence - OPTIONAL, default 0
#          $end,      # Index of last sequence - OPTIONAL, default the last
#         ) = @_;

#     # Returns a hash.

#     my ( $hdr_len, $num_len, $word_len, $step_len, $seqs_tot, $olis_len, 
#          $begs_len, $sums_len, $fh, $buffer, $map, $byt_len, $seq_beg, 
#          $seq_end, $arr_len, $olibeg_ndx, $oliend_ndx, $oliend_sum, 
#          $seqs_max );

#     $num_len = 4;

#     $fh = &Common::File::get_read_handle( $file );

#     # >>>>>>>>>>>>>>>>>>>>>>>>> SETTINGS AND COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Settings and lengths are in the first 120 bytes,

#     $hdr_len = 120;

#     read $fh, $buffer, $hdr_len;

#     $word_len = ( substr $buffer, 0, 20 ) * 1;
#     $step_len = ( substr $buffer, 20, 20 ) * 1;
#     $seqs_tot = ( substr $buffer, 40, 20 ) * 1;

#     $begs_len = ( substr $buffer, 60, 20 ) * 1;
#     $sums_len = ( substr $buffer, 80, 20 ) * 1;
#     $olis_len = ( substr $buffer, 100, 20 ) * 1;

#     # >>>>>>>>>>>>>>>>>>>>>>> DEFAULTS AND VALIDATE <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Set begin and end indices defaults if not set,

#     $seq_beg = $beg // 0;
#     $seq_end = $end // ( $seqs_tot - 1 );

#    # Crash if indices are off,

#     if ( $seq_end >= $seqs_tot ) {
#         &error( qq (Requested zero-based index end is $seq_end, but there are only $seqs_tot entries total) );
#     }

#     if ( $seq_beg > $seq_end ) {
#         &error( qq (Start index $seq_beg is higher than end index $seq_end) );
#     }        

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OLIGO BEGINS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Get begin-indices. First seek to where they start, plus the right offset,
#     # and read in the numbers that correspond to the wanted entries,

#     seek $fh, $hdr_len + $seq_beg * $num_len, 0;

#     $byt_len = $num_len * ( $seq_end - $seq_beg + 1 );
#     read $fh, ${ $map->{"begs"} }, $byt_len;

#     # Remember the first and last of these for use in the oligos section below,

#     $olibeg_ndx = unpack "V", substr ${ $map->{"begs"} }, 0, $num_len;
#     $oliend_ndx = unpack "V", substr ${ $map->{"begs"} }, - $num_len;

#     # Unless the map is loaded starting at the first entry, decrement to match
#     # cut-out sections - the first one in the output should always be zero,

#     if ( $seq_beg > 0 )
#     {
#         $arr_len = ( length ${ $map->{"begs"} } ) / $num_len;
#         &Seq::Simrank::add_int_array_C( ${ $map->{"begs"} }, - $olibeg_ndx, $arr_len );
#     }

#     # &dump("begs:");
#     # &dump([ unpack "V*", ${ $map->{"begs"} } ]);

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OLIGO SUMS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Get oligo sums. These are the number of oligos in each sequence. No change 
#     # has to be made there, just start at the right file position,

#     seek $fh, $hdr_len + $begs_len + $seq_beg * $num_len, 0;

#     $byt_len = $num_len * ( $seq_end - $seq_beg + 1 );
#     read $fh, ${ $map->{"sums"} }, $byt_len;

#     # &dump("sums:");
#     # &dump([ unpack "V*", ${ $map->{"sums"} } ]);

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OLIGOS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Get oligos. First seek to where oligos start, plus the offset gotten from
#     # above,

#     seek $fh, $hdr_len + $begs_len + $sums_len + $olibeg_ndx * $num_len, 0;

#     # The end of what we need is 

#     $oliend_sum = unpack "V", substr ${ $map->{"sums"} }, - $num_len;
    
#     $byt_len = $num_len * ( $oliend_ndx - $olibeg_ndx + $oliend_sum );
#     read $fh, ${ $map->{"olis"} }, $byt_len;

#     # &dump("olis:");
#     # &dump([ unpack "V*", ${ $map->{"olis"} } ]);
    
#     # Include settings and counts,

#     $map->{"wordlen"} = $word_len;
#     $map->{"steplen"} = $step_len;
#     $map->{"seqstot"} = $seqs_tot;

#     &Common::File::close_handle( $fh );

#     return $map;
# }

# sub description
# {
#     # Niels Larsen, September 2006.

#     # Returns a small description of how Seq::Simrank works. 

#     # Returns a string. 

#     my ( $text, $descr_title, $credits_title, $legal_title, $usage_title,
#          $line );

#     $line = "=" x 70;

#     $descr_title = &echo_info( "Description" );
#     $usage_title = &echo_info( "Usage" );
#     $legal_title = &echo_info( "License and Copyright" );
#     $credits_title = &echo_info( "Credits" );

#     $text = qq ($line

# $descr_title

# The similarity between sequences A and B are the number of unique 
# k-words (short subsequence) that they share, divided by the smallest
# total k-word count in either A or B. The result are scores that do 
# not depend on sequence lengths. Opposite blast it ranks a short good
# match higher than a longer less good one. 

# It returns a sorted list of similarities as percentages in a tab
# separated table, one row for each query sequence. First column is the
# query sequence ID and percentage (the two separated by ":"), then the
# matches, the best first.

# $usage_title

# Works good for comparing sequences against a large set of the same 
# type, where high similarities are expected. Comparing small sequence
# against large is ok. Quality of the analysis degrades quickly as the
# similarity decreases. It will not work for proteins. 

# $legal_title

# $Common::Config::sys_license
# $Common::Config::sys_license_url

# $Common::Config::sys_copyright

# $credits_title

# Niels Larsen, Danish Genome Institute and Bioinformatics Research,
# Aarhus University; Unpublished.

# $line
# );

#     return $text;
# }

# sub parse_sim_line_old
# {
#     # Niels Larsen, August 2012. 

#     # Parses a Simrank similarity line into a list. If no indices are given
#     # then all columns in the file are in the list in the order they appear:
#     # [ query-id, query-oligo-count, [[db-id, hit-pct],[db-id, hit-pct], ..]
#     # But the second argument can be used to get only wanted columns, so for
#     # example if given [0,2] the output will have query-id and similarities 
#     # only. If given [2,0] then the order is reversed. If there are no 
#     # similarities the last element is missing. Returns a list with one or 
#     # more elements.

#     my ( $line,    # Simrank table output line
#          $ndcs,    # List of column indices - OPTIONAL
#         ) = @_;

#     # Returns a list.

#     my ( @cols, @sim, $ndx );

#     chomp $line;

#     @cols = split "\t", $line;
    
#     if ( $ndcs )
#     {
#         foreach $ndx ( @{ $ndcs } )
#         {
#             if ( $ndx == 2 )
#             {
#                 if ( $cols[2] ) {
#                     push @sim, { map { split "=", $_ } split " ", $cols[2] };
#                 } else {
#                     push @sim, undef;
#                 }
#             }
#             else {
#                 push @sim, $cols[ $ndx ];
#             }
#         }

#         return wantarray ? @sim : \@sim;
#     }
#     else 
#     {
#         if ( $cols[2] ) {
#             $cols[2] = { map { split "=", $_ } split " ", $cols[2] };
#         } 

#         return wantarray ? @cols : \@cols;
#     }
    
#     return;
# };

