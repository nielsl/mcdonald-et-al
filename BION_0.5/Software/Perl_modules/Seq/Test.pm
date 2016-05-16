package Seq::Test;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Config;
use Time::Duration qw ( duration );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INLINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my $inline_dir;

BEGIN 
{
    $inline_dir = &Common::Config::create_inline_dir("Seq/Test");
    $ENV{"PERL_INLINE_DIRECTORY"} = $inline_dir;
}

use Inline C => 'DATA', "DIRECTORY" => $inline_dir, 
    "CCFLAGS" => "-std=c99",
    'PRINT_INFO' => 1, 'REPORTBUG' => 1;

Inline->init;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use vars qw ( *AUTOLOAD );

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

1;

__DATA__

__C__

/* >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< */

/* Function to get the C value (a pointer usually) of a Perl scalar */

static void* get_ptr( SV* obj ) { return SvPVX( obj ); }

/*
    Oligo number encoding scheme. Only 128 elements are needed, but 
    rare base errors do occur, where characters > 128 sneak in. They
    should be caught earlier, not here.
*/

static int bcodes[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,1,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,3,3,0,0,0,0,0,0,0,0,0,0,
    0,0,0,1,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,3,3,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
};
//    A   C       G                         T U

/* Watson-Crick base boolean array */

static int wcbase[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,1,0,1,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,
    0,1,0,1,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
};
//    A   C       G                         T U

/*
  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  All functions below use Perl\'s memory management, no mallocs. They do not 
  use the Perl stack, which would be quite slow. No C-structures, just simple
  1-D arrays. 

  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
*/

unsigned int count_olis_C( char* seq, unsigned int seqlen, SV* oliarr_sv, 
                           unsigned int wordlen, SV* oliseen_sv, SV* olizero_sv )
{
    /* 
       Niels Larsen, February 2012. 

       Counts oligos found in a given sequence, but identical oligos are only
       counted once. If wordlen is 8 for example, oligo ids will in the range 
       0 -> 65535 or 0 -> 4**8-1. Oligo ids are created by reading along the 
       sequence while bit-shifting and clearing the highest bits. Counts are 
       incremented in the oliarr array and when called repeatedly then counts 
       increase. Returns the number of oligos in the given sequence.

       Returns an integer. 
    */

    unsigned int* oliarr = get_ptr( oliarr_sv );
    unsigned int* olizero = get_ptr( olizero_sv );

    char* oliseen = get_ptr( oliseen_sv );

    unsigned int seqpos, clear, olindx, i;
    int oli;

    /* Create first oligo number */

    oli = create_oli_C( &seq[0], wordlen );
    
    /* Initialize bookkeeping arrays */

    oliarr[ oli ]++;
    oliseen[ oli ] = 1;

    olindx = 0;
    olizero[olindx++] = oli;

    /* Do the following ones by bit-shifting to the left */

    clear = ~( 3 << (2 * wordlen) );

    for ( seqpos = wordlen; seqpos < seqlen; seqpos++ )
    {
        oli = ( oli << 2 ) & clear;
        oli = oli | bcodes[ seq[seqpos] ];

        if ( oliseen[ oli ] == 0 )
        {
            oliarr[ oli ]++;
            oliseen[ oli ] = 1;

            olizero[olindx++] = oli;
        }
    }

    /* Set all oliseen-positions set above back to zero */

    for ( i = 0; i < olindx; i++ ) {
        oliseen[ olizero[i] ] = 0;
    }

    return olindx;
}

int create_oli_C( char* seq, int wordlen )
{
    /*
      Niels Larsen, April 2012.

      Makes a new oligo number from the beginning of the given character array. 
      Call it with &seq[pos] if a different offset wanted. 
    */

    int oli, pos;

    oli = 0;

    for ( pos = 0; pos < wordlen; pos++ )
    {
        oli = oli << 2;
        oli = oli | bcodes[ seq[pos] ];
    }

    return oli;
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

