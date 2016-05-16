package Seq::Oligos;                # -*- perl -*-

# /*
#
# DESCRIPTION
# 
# A mostly-C library with functions related to oligos ("kmers").
#
# */

use strict;
use warnings FATAL => qw ( all );

use feature "state";

use POSIX;
use Storable qw( dclone );
use File::Basename;
use List::Util;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_masks
                 &counts_to_mask
                 &mask_conservation
                 &mask_operation
                 &olis_from_mask
                 &seq_to_mask
                 &uniq_masks

                 &count_olis
                 &count_olis_wc
                 &counts_to_mask_byte
                 &counts_to_mask_uint
                 &create_ndcs
                 &create_ndcs_wc
                 &create_oli
                 &create_olis
                 &create_olis_uniq
                 &create_olis_uniq_wc
                 &init_run_offs
                 &next_oli_wc_beg
                 &olis_from_mask_C
                 &seq_to_mask_C
);

use Common::Config;
use Common::Messages;
use Common::Util_C;

my $inline_dir;

BEGIN 
{
    $inline_dir = &Common::Config::create_inline_dir("Seq/Oligos");
    $ENV{"PERL_INLINE_DIRECTORY"} = $inline_dir;
}

use Inline C => "DATA", "DIRECTORY" => $inline_dir;

Inline->init;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

my ( $Max_int, $Int_size );

$Max_int = 2 ** 30;

$Int_size = &Common::Util_C::size_of_int();

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_masks
{
    # Niels Larsen, June 2013.

    # Adds a list of masks and creates an array of sums. Updates the second 
    # argument, which must have the same length as the input masks. 

    my ( $masks,     # List of masks
         $osums,     # Output sum counts - OPTIONAL
         $mode,      # "byte" or "uint" - OPTIONAL, default "uint"
        ) = @_;

    # Returns nothing.

    my ( $mask );

    $mode //= "uint";

    if ( $osums ) {
        $osums = \$osums if not ref $osums;
    } else {
        $osums = &Common::Util_C::new_array( length $masks->[0], $mode );
    }

    if ( $mode eq "uint" )
    {
        foreach $mask ( @{ $masks } )
        {
            if ( ref $mask ) {
                &Common::Util_C::add_arrays_uint_uint( ${ $osums }, ${ $mask }, ( length ${ $mask } ) / $Int_size );
            } else {
                &Common::Util_C::add_arrays_uint_uint( ${ $osums }, $mask, ( length $mask ) / $Int_size );
            }
        }
    }
    elsif ( $mode eq "byte" ) 
    {
        foreach $mask ( @{ $masks } )
        {
            if ( ref $mask ) {
                &Common::Util_C::add_arrays_uint_byte( ${ $osums }, ${ $mask }, length $mask );
            } else {
                &Common::Util_C::add_arrays_uint_byte( ${ $osums }, $mask, length $mask );
            }
        }
    }
    else {
        &error( qq (Wrong looking mode -> "$mode", should be "byte" or "uint") );
    }

    return;
}

sub counts_to_mask
{
    # Niels Larsen, June 2013. 

    # Creates an array of 0's and 1's from a counts array of unsigned integer 
    # values. The minimum and maximum arguments decide where the mask should 
    # be 1's and 0's. For speed the given counts and mask arrays should be 
    # given as references and must have the same length. The mask argument is 
    # updated and the number of 1's set is returned.

    my ( $vals,    # String reference of integer values
         $mask,    # String reference of byte or uint values
         $min,     # Minimum value - OPTIONAL, default 0
         $max,     # Maximum value - OPTIONAL, default $Max_int
         $mode,    # "uint" or "byte" - OPTOINAL, default "uint"
        ) = @_;

    # Returns integer. 

    my ( $i );

    $vals = \$vals if not ref $vals;
    $mask = \$mask if not ref $mask;
    $min //= 0;
    $max //= $Max_int;
    $mode //= "uint";

    if ( $mode eq "uint" ) {
        $i = &Seq::Oligos::counts_to_mask_uint( ${ $vals }, ${ $mask }, ( length ${ $mask } ) / $Int_size, $min, $max );
    } elsif ( $mode eq "byte" ) {
        $i = &Seq::Oligos::counts_to_mask_byte( ${ $vals }, ${ $mask }, length ${ $mask }, $min, $max );
    } else {
        &error( qq (Wrong looking mode -> "$mode", must be "byte" or "uint") );
    }

    return $i;
}

sub mask_operation
{
    # Niels Larsen, June 2013. 

    # Compares the two given masks of 1's and 0's and creates a new one. Masks
    # are perl strings seen as char arrays in C and the three given masks must
    # have the same lengths. These modes exist:
    #
    #   and - sets 1 where mask1 and mask2 are both 1, otherwise 0
    #   dif - sets 1 where mask1 is different from mask2
    #   del - copies mask1, but sets 0 where mask2 has 1
    #
    # The output mask is $omask, the third argument. Returns the number of 1's
    # set.

    my ( $mask1,    # Input string mask 1 
         $mask2,    # Input string mask 2
         $omask,    # Output string mask
         $mode,     # Mask mode
        ) = @_;

    # Returns integer. 

    my ( $i, $j, $routine );

    if ( ( $i = length ${ $mask1 } ) != ( $j = length ${ $mask2 } ) ) {
        &error( qq (Programming error: mask1 is $i long, but mask2 is $j long) );
    }

    if ( ( $i = length ${ $mask2 } ) != ( $j = length ${ $omask } ) ) {
        &error( qq (Programming error: mask2 is $i long, but omask is $j long) );
    }

    state $modes = {
        "and" => 1,
        "dif" => 1,
        "del" => 1,
    };

    if ( exists $modes->{ $mode } )
    {
        $routine = "Common::Util_C::compare_masks_uint_". $mode;

        no strict "refs";
        $i = $routine->( ${ $mask1 }, ${ $mask2 }, ${ $omask }, ( length ${ $omask } ) / $Int_size );
    }
    else {
        &error( qq (Wrong looking mask mode -> "$mode") );
    }

    return $i;
}

sub olis_from_mask
{
    # Niels Larsen, June 2013. 

    # Converts an oligo mask to a string of oligos. Returns a reference
    # to the oligo string created. A string write-buffer must be given
    # with a length of at least four times the number of indices set in 
    # the mask.
    
    my ( $mask,       # Mask string
         $buff,       # Output oligo string buffer
        ) = @_;

    # Returns integer.

    my ( $len, $olis );

    if ( not ref $mask ) {
        &error( qq (The given mask should be a reference) );
    }

    if ( not ref $buff ) {
        &error( qq (The given string buffer should be a reference) );
    }

    $len = &Seq::Oligos::olis_from_mask_C( ${ $mask }, ( length ${ $mask } ) / $Int_size, ${ $buff } );
    
    $olis = substr ${ $buff }, 0, $len * 4;

    return \$olis;
}

sub seq_to_mask
{
    my ( $seq,     # Sequence string
         $wlen,    # Word length
         $mask,    # Mask string
        ) = @_;

    my ( $count );

    if ( not ref $seq ) {
        &error( qq (The given sequence string should be a reference) );
    }

    if ( not ref $mask ) {
        &error( qq (The given mask string should be a reference) );
    }

    $count = &Seq::Oligos::seq_to_mask_C( ${ $seq }, $wlen, ${ $mask }, length ${ $mask } );
    
    return $count;
}

sub uniq_masks
{
    # Niels Larsen, June 2013.

    # Converts the given list of masks to a list of masks where only 1's are
    # set for words that are unique. The second argument is a temporary buffer.

    my ( $masks,      # List of masks
         $osums,      # Counts buffer - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $mask, $i );

    state $mode = "uint";

    if ( defined $osums )
    {
        if ( not ref $osums ) {
            &error( qq (The \$osums argument must be a string reference) );
        }
    }
    else {
        $osums = &Common::Util_C::new_array( ( length $masks->[0] ) / $Int_size, $mode );
    }

    # Sum up counts and set a mask where the counts are 1. This new mask then 
    # shows which words are unique to one of the input masks,

    &Seq::Oligos::add_masks( $masks, $osums, $mode );

    &Seq::Oligos::counts_to_mask( $osums, $osums, 1, 1, $mode );

    # Overwrite the given masks with 1's where there are unique words,

    for ( $i = 0; $i <= $#{ $masks }; $i += 1 )
    {
        &Seq::Oligos::mask_operation( \$masks->[$i], $osums, \$masks->[$i], "and" );
    }

    return;
}

1;

# sub mask_conservation
# {
#     # Niels Larsen, June 2013.

#     # Generates a conservation mask from a list of masks. 

#     my ( $masks,         # List of masks or mask references
#          $minrat,        # Minimum conservation ratio
#          $maxrat,        # Maximum conservation ratio
#          $omask,         # Output mask reference
#          $counts,        # Counts buffer, always uint - OPTIONAL
#          $mode,          # "byte" or "uint" - OPTOINAL, default "uint"
#         ) = @_;

#     my ( $mask, $total );

#     $mode //= "uint";

#     if ( $counts ) {
#         $counts = \$counts if not ref $counts;
#     } else {
#         $counts = &Common::Util_C::new_array( length $masks->[0], $mode );
#     }

#     if ( $mode eq "uint" )
#     {
#         foreach $mask ( @{ $masks } )
#         {
#             if ( ref $mask ) {
#                 &Common::Util_C::add_arrays_uint_uint( ${ $counts }, ${ $mask }, ( length ${ $mask } ) / $Int_size );
#             } else {
#                 &Common::Util_C::add_arrays_uint_uint( ${ $counts }, $mask, ( length $mask ) / $Int_size );
#             }
#         }
#     }
#     elsif ( $mode eq "byte" ) 
#     {
#         foreach $mask ( @{ $masks } )
#         {
#             if ( ref $mask ) {
#                 &Common::Util_C::add_arrays_uint_byte( ${ $counts }, ${ $mask }, length $mask );
#             } else {
#                 &Common::Util_C::add_arrays_uint_byte( ${ $counts }, $mask, length $mask );
#             }
#         }
#     }
#     else {
#         &error( qq (Wrong looking mode -> "$mode", should be "byte" or "uint") );
#     }

#     $total = scalar @{ $masks };    
    
#     &Seq::Oligos::counts_to_mask( $counts, $omask, $minrat * $total, $maxrat * $total, $mode );
    
#     return;
# }


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

unsigned int count_olis( char* seq, unsigned int seqlen, SV* oliarr_sv, 
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

    unsigned int seqpos, oli, clear, olindx, i;

    /* Create first oligo number */

    oli = create_oli( &seq[0], wordlen );
    
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

unsigned int count_olis_wc( char* seq, unsigned int seqlen, SV* oliarr_sv, 
                            unsigned int wordlen, SV* oliseen_sv, SV* olizero_sv )
{
    /* 
       Niels Larsen, February 2012. 

       As count_olis, but skips over non-AGCTU bases. See count_olis.

       Returns an integer. 
    */

    unsigned int* oliarr = get_ptr( oliarr_sv );
    unsigned int* olizero = get_ptr( olizero_sv );

    char* oliseen = get_ptr( oliseen_sv );

    unsigned int endpos, olibeg, oliend, oli, clear, olindx, i;
    int begpos;

    /*
      Find the next start position of a WC-oligo and create the first 
      oligo. Return 0 if none found - this should happen rarely, but still
    */

    begpos = next_oli_wc_beg( seq, seqlen, wordlen, 0 );

    if ( begpos == -1 ) {
        return 0;
    }

    oli = create_oli( &seq[begpos], wordlen );
    
    /* Initialize bookkeeping arrays */

    oliarr[ oli ]++;
    oliseen[ oli ] = 1;

    olindx = 0;
    olizero[olindx++] = oli;

    /* Do the following ones by bit-shifting to the left */

    clear = ~( 3 << (2 * wordlen) );
    endpos = begpos + wordlen;
    
    while ( endpos < seqlen )
    {
        if ( wcbase[ seq[endpos] ] )
        {
            oli = ( oli << 2 ) & clear;
            oli = oli | bcodes[ seq[endpos] ];

            endpos++;
        }
        else
        {
            begpos = next_oli_wc_beg( seq, seqlen, wordlen, endpos + 1 );

            if ( begpos == -1 ) {
                break;
            } else {
                oli = create_oli( &seq[begpos], wordlen );
                endpos = begpos + wordlen;
            }
        }

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

unsigned int counts_to_mask_byte( SV* arr_sv, unsigned char* mask, unsigned int arrlen, 
                                  float min, float max )
{
    /*
      Niels Larsen, June 2013.

      Creates an array (mask) of 0's and 1's from a counts array of integer 
      values (arr_sv). The minimum and maximum arguments decide where the 
      mask should be 1's and 0's. The given counts and mask arrays should 
      have the same length.
    */
    
    unsigned int* arr = get_ptr( arr_sv );
    
    int i, count;

    count = 0;

    for ( i = 0; i < arrlen; i++ )
    {
        if ( arr[i] >= min && arr[i] <= max )
        {
            mask[i] = 1;
            count++;
        }
        else {
            mask[i] = 0;
        }
    }

    return count;
}

unsigned int counts_to_mask_uint( SV* arr_sv, SV* mask_sv, unsigned int arrlen, 
                                  float min, float max )
{
    /*
      Niels Larsen, June 2013.

      Creates an array (mask) of 0's and 1's from a counts array of integer 
      values (arr_sv). The minimum and maximum arguments decide where the 
      mask should be 1's and 0's. The given counts and mask arrays should 
      have the same length.
    */
    
    unsigned int* arr = get_ptr( arr_sv );
    unsigned int* mask = get_ptr( mask_sv );
    
    int i, count;

    count = 0;

    for ( i = 0; i < arrlen; i++ )
    {
        if ( arr[i] >= min && arr[i] <= max )
        {
            mask[i] = 1;
            count++;
        }
        else {
            mask[i] = 0;
        }
    }

    return count;
}

void create_ndcs( char* seq, unsigned int seqlen, unsigned int seqnum, 
                  SV* seqndcs_sv, SV* ndxoffs_sv, unsigned int wordlen,
                  SV* oliseen_sv, SV* olizero_sv )
{
    /* 
       Niels Larsen, February 2012. 

       Fills seqndcs_sv with sequence indices for each oligo encountered in the 
       given sequence, but identical oligos are only added once. The ndxoffs_sv 
       array holds the places in seqndcs_sv where oligos are to be stored. When 
       an oligo is stored, ndxoffs_sv is incremented for that oligo. The "runs" 
       of sequence ids (zero-based indices) must not overlap of course, but that
       has been prevented by first counting all oligos with the count_oligos 
       routines. Returns nothing, but updates both seqndcs_sv and ndxoffs_sv.
       
       Returns nothing.
    */

    unsigned int* seqndcs = get_ptr( seqndcs_sv );
    unsigned long* ndxoffs = get_ptr( ndxoffs_sv );
    unsigned int* olizero = get_ptr( olizero_sv );

    char* oliseen = get_ptr( oliseen_sv );

    unsigned int seqpos, oli, clear, olindx, i;

    /* The first oligo number is created */

    oli = create_oli( &seq[0], wordlen );

    seqndcs[ ndxoffs[ oli ] ] = seqnum;
    ndxoffs[ oli ]++;

    oliseen[ oli ] = 1;

    olindx = 0;
    olizero[olindx++] = oli;

    /*
        The following ones are made by shifting the previous two places to the 
        left and then clearing the high bits.
    */

    clear = ~( 3 << (2 * wordlen) );

    for ( seqpos = wordlen; seqpos < seqlen; seqpos += 1 )
    {
        oli = ( oli << 2 ) & clear;
        oli = oli | bcodes[ seq[ seqpos ] ];

        if ( oliseen[ oli ] == 0 )
        {
            seqndcs[ ndxoffs[ oli ] ] = seqnum;
            ndxoffs[ oli ]++;

            oliseen[ oli ] = 1;
            olizero[olindx++] = oli;
        }
    }

    /* Set all oliseen-positions set above back to zero */

    for ( i = 0; i < olindx; i++ ) {
        oliseen[ olizero[i] ] = 0;
    }

    return;
}

void create_ndcs_wc( char* seq, unsigned int seqlen, unsigned int seqnum,
                     SV* seqndcs_sv, SV* ndxoffs_sv, unsigned int wordlen,
                     SV* oliseen_sv, SV* olizero_sv )
{
    /* 
       Niels Larsen, February 2012. 

       Same as create_ndcs except it uses only A, G, C, T/U bases. See 
       that routine for description.
       
       Returns nothing.
    */

    unsigned int* seqndcs = get_ptr( seqndcs_sv );
    unsigned long* ndxoffs = get_ptr( ndxoffs_sv );
    unsigned int* olizero = get_ptr( olizero_sv );

    char* oliseen = get_ptr( oliseen_sv );

    unsigned int endpos, seqpos, oli, clear, olindx, i;
    int begpos;

    /*
      Find the next start position of a WC-oligo and create the first 
      oligo. Return 0 if none found - this should happen rarely, but still
    */

    begpos = next_oli_wc_beg( seq, seqlen, wordlen, 0 );

    if ( begpos == -1 ) {
        return;
    }

    oli = create_oli( &seq[begpos], wordlen );

    /* Initialize bookkeeping arrays and values */
    
    seqndcs[ ndxoffs[ oli ] ] = seqnum;
    ndxoffs[ oli ]++;

    oliseen[ oli ] = 1;

    olindx = 0;
    olizero[olindx++] = oli;

    /*
        The following ones are made by shifting the previous two places to the 
        left and then clearing the high bits.
    */

    clear = ~( 3 << (2 * wordlen) );
    endpos = begpos + wordlen;

    while ( endpos < seqlen )
    {
        if ( wcbase[ seq[endpos] ] )
        {
            oli = ( oli << 2 ) & clear;
            oli = oli | bcodes[ seq[endpos] ];

            endpos++;
        }
        else
        {
            begpos = next_oli_wc_beg( seq, seqlen, wordlen, endpos + 1 );

            if ( begpos == -1 ) {
                break;
            } else {
                oli = create_oli( &seq[begpos], wordlen );
                endpos = begpos + wordlen;
            }
        }

        if ( oliseen[ oli ] == 0 )
        {
            seqndcs[ ndxoffs[ oli ] ] = seqnum;
            ndxoffs[ oli ]++;

            oliseen[ oli ] = 1;
            olizero[olindx++] = oli;
        }
    }

    /* Set all oliseen-positions set above back to zero */

    for ( i = 0; i < olindx; i++ ) {
        oliseen[ olizero[i] ] = 0;
    }

    return;
}

int create_oli( char* seq, int wordlen )
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

unsigned long create_olis( char* seq, unsigned int seqlen, 
                           unsigned int wordlen, unsigned int steplen, 
                           SV* olis_sv, unsigned long olindx )
{
    /*
      Niels Larsen, August 2012. 

      Converts a sequence to integer oligo ids: if wordlen is 8 for example, 
      ids will be in the range 0 -> 4**8-1 or 0 -> 65535. Ambiguity codes 
      become A\'s. A given step length of 2 means every second possible oligo
      is used; step length must be between 1 and word length. The oligo ids 
      are stored in the given olis_sv array from position olindx and on. 
      Returns the index where the next sequence should start. 

      Regarding speed: bit shifting + clearing was tried, but it seems just
      as fast to remake the oligo every time, even for stepsize 1. And much
      simpler to handle step length then.
      
      Returns an integer. 
    */

    unsigned int* olis = get_ptr( olis_sv );
    unsigned int begpos, oli, i, pos, maxpos;
    
    maxpos = seqlen - wordlen;
    begpos = 0;

    while ( begpos <= maxpos )
    {
        oli = 0;
        
        for ( pos = begpos; pos < begpos + wordlen; pos++ )
        {
            oli = oli << 2;
            oli = oli | bcodes[ seq[pos] ];
        }

        olis[olindx++] = oli;
        
        begpos = begpos + steplen;
    }

    return olindx;
}

unsigned long create_olis_uniq( char* seq, unsigned int seqlen, unsigned int wordlen,
                                unsigned int steplen, SV* olis_sv, unsigned long olindx,
                                char* oliseen, SV* olizero_sv )
{
    /*
      Niels Larsen, May 2012. 

      Converts a sequence to oligo ids. Ambiguity codes become A's. The 
      codes are integers: if wordlen is 8 for example, ids will be in the 
      range 0 -> 65535 or 0 -> 4**8-1. Oligos that occur more than once in
      a sequence are only counted once - this helps composition bias. A 
      given step length of 2 means only every second possible oligo is used;
      step length must be between 1 and word length. The oligos ids are 
      stored in the given olis_sv array from position olindx and on. 
      Returns the index where the next sequence should start. 

      Speed. Bit shifting + clearing was tried, but it seems just as fast to
      remake the oligo every time, even for stepsize 1. And much simpler.
      
      Returns an integer. 
    */

    unsigned int* olis = get_ptr( olis_sv );
    unsigned int* olizero = get_ptr( olizero_sv );

    int begpos, zerondx, oli, i, pos, maxpos;
    
    zerondx = 0;
    maxpos = seqlen - wordlen;
    begpos = 0;

    while ( begpos <= maxpos )
    {
        /*
          Right-shift two-bit codes from the array above.
        */
        
        oli = 0;
        
        for ( pos = begpos; pos < begpos + wordlen; pos++ )
        {
            oli = oli << 2;
            oli = oli | bcodes[ seq[pos] ];
        }
        
        begpos = begpos + steplen;

        /*
          This tracks if an oligo has been seen before and only adds it if not.
          The olizero array remembers which positions have to be cleared, so that
          oliseen is always zeroes only when this routine is called. 
        */

        if ( oliseen[ oli ] == 0 )
        {
            olis[olindx++] = oli;

            oliseen[ oli ] = 1;
            olizero[ zerondx++ ] = oli;
        }
    }

    /*
      Set all oliseen-positions set above back to zero.
    */
    
    for ( i = 0; i < zerondx; i++ ) {
        oliseen[ olizero[i] ] = 0;
    }

    return olindx;
}

unsigned long create_olis_uniq_wc( char* seq, unsigned int seqlen, unsigned int wordlen,
                                   unsigned int steplen, SV* olis_sv, unsigned long olindx,
                                   char* oliseen, SV* olizero_sv )
{
    /*
      Niels Larsen, May 2012. 

      Converts a sequence to oligo ids while skipping ambiguity codes. The 
      codes are integers: if wordlen is 8 for example, ids will be in the 
      range 0 -> 65535 or 0 -> 4**8-1. Oligos that occur more than once in
      a sequence are only counted once - this helps composition bias. A 
      given step length of 2 means only every second possible oligo is used;
      step length must be between 1 and word length. The oligos ids are 
      stored in the given olis_sv array from position olindx and on. 
      Returns the index where the next sequence should start. 

      Speed. Bit shifting + clearing was tried, but it seems just as fast to
      remake the oligo every time, even for stepsize 1. And much simpler.
      
      Returns an integer. 
    */

    unsigned int* olis = get_ptr( olis_sv );
    unsigned int* olizero = get_ptr( olizero_sv );

    int begpos, zerondx, oli, i, pos, maxpos;
    
    zerondx = 0;
    maxpos = seqlen - wordlen;
    begpos = 0;

    // printf("seqlen, wordlen, maxpos = %d, %d, %d\n", seqlen, wordlen, maxpos );

    while ( begpos <= maxpos )
    {
        /*
          Skips ahead to where next oligo can be made. Returns -1 if there 
          are no positions before the end.
        */

        begpos = next_oli_wc_beg( seq, seqlen, wordlen, begpos );

        // printf("begpos = %d\n", begpos );

        if ( begpos == -1 )
        {
            break;
        }
        else
        {
            /*
              Right-shift two-bit codes from the array above.
            */

            oli = 0;

            for ( pos = begpos; pos < begpos + wordlen; pos++ )
            {
                oli = oli << 2;
                oli = oli | bcodes[ seq[pos] ];

                // printf("oli = %d\n", oli );
            }

            begpos = begpos + steplen;
        }

        /*
          This tracks if an oligo has been seen before and only adds it if not.
          The olizero array remembers which positions have to be cleared, so that
          oliseen is always zeroes only when this routine is called. 
        */

        if ( oliseen[ oli ] == 0 )
        {
            olis[olindx++] = oli;

            oliseen[ oli ] = 1;
            olizero[ zerondx++ ] = oli;
        }
    }

    /*
      Set all oliseen-positions set above back to zero.
    */
    
    for ( i = 0; i < zerondx; i++ ) {
        oliseen[ olizero[i] ] = 0;
    }

    return olindx;
}

unsigned long init_run_offs( SV* lens_sv, SV* begs_sv, unsigned int olidim )
{
    /*
      Niels Larsen, March 2012.

      Initializes sequence index "run" start positions by summing the given
      lengths. Returns the total length.

      Returns an integer.
    */

    unsigned int* lens = get_ptr( lens_sv );
    unsigned long* begs = get_ptr( begs_sv );

    unsigned long off;
    unsigned int oli;

    off = 0;

    for ( oli = 0; oli < olidim; oli++ )
    {
        if ( lens[oli] > 0 )
        {
            begs[oli] = off;
            off += lens[oli];
        }
    }            
    
    return off;
}
    
int next_oli_wc_beg( char* seq, unsigned int seqlen,
                     unsigned int wordlen, unsigned int seqpos )
{
    /*
      Niels Larsen, April 2012.

      Starting at seqpos, looks for the first position where a wordlen long
      oligo of only A, G, C and T/U begins. If none found, returns -1. 

      Returns an integer.
    */

    unsigned int pos, maxpos;
    int olibeg;

    olibeg = -1;
    maxpos = seqlen - wordlen;

    while ( olibeg == -1 && seqpos <= maxpos )
    {
        for ( pos = seqpos; pos < seqpos + wordlen; pos++ )
        {
            if ( wcbase[ seq[pos] ] == 0 )
            {
                seqpos = pos + 1;
                break;
            }
        }

        if ( pos == seqpos + wordlen ) {
            olibeg = seqpos;
        }
    }

    return olibeg;
}

unsigned int olis_from_mask_C( SV* mask_sv, unsigned int len, SV* olis_sv )
{
    /*
      Niels Larsen, June 2013.

      Stores all indices of the given mask where the value is 1. An oligo
      and a mask index is the same. Returns the number of elements set in 
      the olis argument. 

      Returns an integer. 
    */

    unsigned int* mask = get_ptr( mask_sv );
    unsigned int* olis = get_ptr( olis_sv );

    unsigned int oli, count;

    count = 0;
    
    for ( oli = 0; oli < len; oli += 1 )
    {
        if ( mask[oli] == 1 )
        {
            olis[count++] = oli;
        }
    }

    return count;
}

unsigned int seq_to_mask_C( char* seq, unsigned int wordlen, 
                            SV* mask_sv, unsigned int masklen )
{
    /* 
       Niels Larsen, May 2013. 

       Create a 4**wordlen long mask with 1's for the oligos present in a given
       sequence and 0's where not present. If wordlen is 8 for example, oligo
       ids will in the range 0 -> 65535 or 0 -> 4**8-1. Returns the number of 
       1's in the resulting mask. 

       Returns an integer. 
    */

    unsigned int* mask = get_ptr( mask_sv );
    unsigned int seqpos, oli, clear, count;

    /* Initialize with zero */

    memset( mask, 0, masklen );

    /* Create and set first oligo */

    oli = create_oli( &seq[0], wordlen );
    mask[ oli ] = 1;

    count = 1;

    /* Do the following ones by bit-shifting to the left */

    clear = ~( 3 << (2 * wordlen) );
    
    for ( seqpos = wordlen; seqpos < strlen( seq ); seqpos++ )
    {
        oli = ( oli << 2 ) & clear;
        oli = oli | bcodes[ seq[seqpos] ];

        if ( mask[ oli ] == 0 )
        {
            mask[ oli ] = 1;
            count++;
        }
    }

    return count;
}

__END__

void test( char* mask, unsigned int ndx, unsigned int len )
{
    // unsigned char* mask = get_ptr( mask_sv );

    // printf("strlen = %d\n", strlen( mask ) );
    
    memset( mask, 0, len );

    mask[ndx] = 10;

    return;
}

