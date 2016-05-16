package Common::Util_C;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# C routines that do general small things that are useful by more than one 
# program. They are written by a naive C person.
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_value_float
                 &add_arrays_float
                 &add_arrays_uint_uint
                 &add_arrays_uint_byte
                 &compare_masks_and
                 &compare_masks_del
                 &compare_masks_dif
                 &equal_array_float
                 &equal_values_int
                 &get_element_float
                 &get_element_int
                 &max_index_int
                 &max_value_float
                 &min_index_int
                 &mul_array_float
                 &mul_arrays_float
                 &new_array
                 &quicksort
                 &range_mask_uint
                 &round_array_float
                 &set_array_min_uint
                 &set_element_float
                 &set_element_uint
                 &set_element_byte
                 &set_mem
                 &size_of_float
                 &size_of_int
                 &size_of_long
                 &sum_array_float
);

use Common::Config;
use Common::Messages;

my $inline_dir;

BEGIN
{
    $inline_dir = &Common::Config::create_inline_dir("Common/Util_C");
    $ENV{"PERL_INLINE_DIRECTORY"} = $inline_dir;
}

use Inline C => 'DATA', "DIRECTORY" => $inline_dir, "CCFLAGS" => "-g -std=c99";

Inline->init;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# All functions below use Perl\'s memory management, no mallocs. They do not 
# use the Perl stack, which would be quite slow. No C-structures, just simple
# 1-D arrays. 

sub new_array
{
    # Niels Larsen, March 2012. 

    # Creates zero-packed perl string used as an array of numbers in C. The
    # reason for the routine is memory inefficiency when creating long 
    # strings: $str = pack "V*", (0) x 100_000_000 takes 1.2 GB of ram for
    # integer4. Dont know why, maybe some uncleaned buffers in perl, but 
    # doing it in 20k increments best removes that problem and is fastest.
    # Returns a string reference.

    my ( $size,      # Number of array elements
         $type,      # Array type
         $val,       # Array initialization value - OPTIONAL default 0
        ) = @_;

    # Returns a string reference.
    
    my ( $buffer, $inc, $mod, $div, $chunk, %pack, $code );

    $type = "uint" if not defined $type;
    $val = 0 if not defined $val;

    %pack = (
        "byte" => "C",
        "char" => "c",
        "uchar" => "C",
        "uint" => "V",
        "ushort" => "v",
        "quad" => "q",
        "uquad" => "Q",
        "float" => "f",
        "dfloat" => "d",
        );

    if ( not $code = $pack{ $type } ) {
        &error( qq (Wrong looking array type -> "$type") );
    }

    $buffer = "";
    $inc = 20_000;

    $div = int ( $size / $inc );
    $mod = $size % $inc;

    if ( $div > 0 )
    {
        $chunk = pack "$code$inc", ($val);
        map { $buffer .= $chunk } ( 1 .. $div );
    }

    if ( $mod > 0 ) {
        $buffer .= pack "$code$mod", ($val);
    }

    return \$buffer;
}

1;

__DATA__

__C__

/*

Inline::C guides,

http://search.cpan.org/~ingy/Inline-0.44/C/C.pod
http://search.cpan.org/~ingy/Inline-0.44/C/C-Cookbook.pod

*/

#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef unsigned int uint32_t;
typedef unsigned short int uint16_t;

/* see more in /usr/include/stdint.h */

/* Function to get the C value (a pointer usually) of a Perl scalar */

static void* get_ptr( SV* obj ) { return SvPVX( obj ); }

#define DEF_NDXPTR( str )  int* ndxptr = get_ptr( str )
#define FETCH( idx )       ndxptr[ idx ]

void add_value_float( SV* arr_sv, int ndx, float val )
{
    /*
      Niels Larsen, November 2012.

      Adds a given float value at a given index to a float array. No
      bounds check is done.
    */

    float* arr = get_ptr( arr_sv );

    arr[ ndx ] += val;

    return;
}

void add_arrays_float( SV* arr_sv, SV* add_sv, int len )
{
    /*
      Niels Larsen, November 2012.

      Adds all values of the second given float array to the corresponding 
      values in the first given float array. The arrays must have the same
      length.
    */
    
    float* arr = get_ptr( arr_sv );
    float* add = get_ptr( add_sv );

    int i;
    
    for ( i = 0; i < len; i++ )
    {
        arr[i] += add[i];
    }

    return;
}

void add_arrays_uint_uint( SV* arr_sv, SV* add_sv, int len )
{
    /*
      Niels Larsen, November 2012.

      Adds all values of the second given unsigned integer array to the 
      corresponding values in the first given unsigned integer array. The 
      arrays must have the same length.
    */
    
    unsigned int* arr = get_ptr( arr_sv );
    unsigned int* add = get_ptr( add_sv );

    int i;
    
    // printf("len = %d\n", len );

    for ( i = 0; i < len; i++ )
    {
        // printf("add, i = %d, %d\n", add[i], i );

        arr[i] += add[i];
    }

    return;
}

void add_arrays_uint_byte( SV* arr_sv, unsigned char* add, unsigned int len )
{
    /*
      Niels Larsen, November 2012.

      Adds all values of the second given unsigned integer array to the 
      corresponding values in the first given unsigned integer array. The 
      arrays must have the same length.
    */
    
    unsigned int* arr = get_ptr( arr_sv );

    int i;

    for ( i = 0; i < len; i++ )
    {
        arr[i] += add[i];
    }

    return;
}

unsigned int compare_masks_byte_and( unsigned char* mask1, unsigned char* mask2, 
                                     unsigned char* omask, unsigned int len )
{
    /*
      Niels Larsen, June 2013.
    */
    
    int i, count;

    count = 0;

    for ( i = 0; i < len; i++ )
    {
        if ( mask1[i] == 1 && mask2[i] == 1 )
        {
            omask[i] = 1;
            count ++;
        }
        else {
            omask[i] = 0;
        }
    }

    return count;
}

unsigned int compare_masks_byte_del( unsigned char* mask1, unsigned char* mask2,
                                     unsigned char* omask, unsigned int len )
{
    /*
      Niels Larsen, June 2013.
    */
    
    int i, count;

    count = 0;

    for ( i = 0; i < len; i++ )
    {
        if ( mask2[i] == 1 )
        {
            omask[i] = 0;
            count ++;
        }
        else {
            omask[i] = mask1[i];
        }
    }

    return count;
}

unsigned int compare_masks_byte_dif( unsigned char* mask1, unsigned char* mask2,
                                     unsigned char* omask, unsigned int len )
{
    /*
      Niels Larsen, June 2013.
    */
    
    int i, count;

    count = 0;

    for ( i = 0; i < len; i++ )
    {
        if ( mask1[i] != mask2[i] )
        {
            omask[i] = 1;
            count ++;
        }
        else {
            omask[i] = 0;
        }
    }

    return count;
}

unsigned int compare_masks_uint_and( SV* mask1_sv, SV* mask2_sv, SV* omask_sv, unsigned int len )
{
    /*
      Niels Larsen, June 2013.
    */
    
    unsigned int* mask1 = get_ptr( mask1_sv );
    unsigned int* mask2 = get_ptr( mask2_sv );
    unsigned int* omask = get_ptr( omask_sv );

    unsigned int i, count;

    count = 0;

    // printf("len = %d\n", len );

    for ( i = 0; i < len; i++ )
    {
        // printf("i = %d\n", i );
        
        if ( mask1[i] == 1 && mask2[i] == 1 )
        {
            omask[i] = 1;
            count ++;
        }
        else {
            omask[i] = 0;
        }
    }

    return count;
}

unsigned int compare_masks_uint_del( SV* mask1_sv, SV* mask2_sv, SV* omask_sv, unsigned int len )
{
    /*
      Niels Larsen, June 2013.
    */
    
    unsigned int* mask1 = get_ptr( mask1_sv );
    unsigned int* mask2 = get_ptr( mask2_sv );
    unsigned int* omask = get_ptr( omask_sv );

    int i, count;

    count = 0;

    for ( i = 0; i < len; i++ )
    {
        if ( mask2[i] == 1 )
        {
            omask[i] = 0;
            count ++;
        }
        else {
            omask[i] = mask1[i];
        }
    }

    return count;
}

unsigned int compare_masks_uint_dif( SV* mask1_sv, SV* mask2_sv, SV* omask_sv, unsigned int len )
{
    /*
      Niels Larsen, June 2013.
    */
    
    unsigned int* mask1 = get_ptr( mask1_sv );
    unsigned int* mask2 = get_ptr( mask2_sv );
    unsigned int* omask = get_ptr( omask_sv );

    int i, count;

    count = 0;

    for ( i = 0; i < len; i++ )
    {
        if ( mask1[i] != mask2[i] )
        {
            omask[i] = 1;
            count ++;
        }
        else {
            omask[i] = 0;
        }
    }

    return count;
}

int equal_array_float( SV* arr_sv, int len )
{
    /*
      Niels Larsen, December 2012.

      Returns 1 if all the given float values are equal, otherwise zero. 
    */
    
    float* arr = get_ptr( arr_sv );

    int i, flag, val;
    
    flag = 1;
    val = arr[0];

    for ( i = 1; i < len; i++ )
    {
        if ( arr[i] != val ) {
            return 0;
        }
    }

    return 1;
}

int equal_values_int( SV* arr_sv, int len )
{
    /*
      Niels Larsen, December 2012.

      Returns 1 if all the given values are equal, otherwise zero. 
    */
    
    int* arr = get_ptr( arr_sv );

    int i, flag, val;
    
    flag = 1;
    val = arr[0];

    for ( i = 1; i < len; i++ )
    {
        if ( arr[i] != val ) {
            return 0;
        }
    }

    return 1;
}

int get_element_float( SV* arr_sv, int ndx )
{
    /*
      Niels Larsen, December 2012.

      Gets an element. 
    */
    
    float* arr = get_ptr( arr_sv );

    return arr[ndx];
}

int get_element_uint( SV* arr_sv, unsigned int ndx )
{
    /*
      Niels Larsen, December 2012.

      Gets an element. 
    */
    
    unsigned int* arr = get_ptr( arr_sv );

    return arr[ndx];
}

int max_index_int( SV* ndxstr, long value, int low, int high )
{
    /*

      Niels Larsen, May 2004.
      
      Returns the index of a given integer in a ascending-sorted list 
      of integers. However unlike other binary searches, if the integer
      is not found the index of the nearest lower integer is returned.
      
    */
    
    DEF_NDXPTR( ndxstr );

    int cur, index;

    index = low;

    while ( index < high )
    {
        cur = ( index + high ) / 2;

        if ( FETCH(cur) <= value ) {
            index = cur + 1;
        } else {
            high = cur;
        }
    }

    while ( index > low && FETCH(index) > value )
    {
        index--;
    }

    return index;
}

float max_value_float( SV* arr_sv, unsigned int len )
{
    /*
      Niels Larsen, November 2012.

      Finds and returns the maximum value in a given float array.
    */

    float* arr = get_ptr( arr_sv );

    float max = 0;
    unsigned int i;

    for ( i = 0; i < len; i++ )
    {
        if ( arr[i] > max ) {
            max = arr[i];
        }
    }

    return max;
}

int min_index_int( SV* ndxstr, long value, int low, int high )
{
    /* 
       Niels Larsen, May 2004.
       
       Returns the index of a given integer in a ascending-sorted list 
       of integers. However unlike other binary searches, if the integer
       is not found the index of the nearest higher integer is returned.
    */

    DEF_NDXPTR( ndxstr );

    int cur;

    while ( low < high )
    {
        cur = ( low + high ) / 2;

        if ( FETCH(cur) < value ) {
            low = cur + 1;
        } else {
            high = cur;
        }
    }

    return low;
}

void mul_array_float( SV* arr_sv, float mul, int len )
{
    /*
      Niels Larsen, December 2012.

      Multiplies all values of the given float array with the given
      value. 
    */
    
    float* arr = get_ptr( arr_sv );

    int i;
    
    for ( i = 0; i < len; i++ )
    {
        arr[i] *= mul;
    }

    return;
}

void mul_arrays_float( SV* arr_sv, SV* mul_sv, int len )
{
    /*
      Niels Larsen, December 2012.

      Multiplies all values of the two given float arrays and stores the 
      result into the first. The arrays must have the same length.
    */
    
    float* arr = get_ptr( arr_sv );
    float* mul = get_ptr( mul_sv );

    int i;
    
    for ( i = 0; i < len; i++ )
    {
        arr[i] *= mul[i];
    }

    return;
}

void mul_arrays_uint( SV* arr_sv, SV* mul_sv, int len )
{
    /*
      Niels Larsen, December 2012.

      Multiplies all values of the two given int arrays and stores the 
      result into the first. The arrays must have the same length.
    */
    
    unsigned int* arr = get_ptr( arr_sv );
    unsigned int* mul = get_ptr( mul_sv );

    int i;
    
    for ( i = 0; i < len; i++ )
    {
        arr[i] *= mul[i];
    }

    return;
}

void mul_array_in( SV* arr_sv, int mul, int len )
{
    /*
      Niels Larsen, December 2012.

      Multiplies all values of the given int array with the given
      value. 
    */
    
    int* arr = get_ptr( arr_sv );

    int i;
    
    for ( i = 0; i < len; i++ )
    {
        arr[i] *= mul;
    }

    return;
}

void quicksort( unsigned int *arr, unsigned int elements)
{
    /*
      Darel Rex Finley, 2007.
      Taken from http://alienryderflex.com/quicksort

      This public-domain C implementation by Darel Rex Finley.

    * This function assumes it is called with valid parameters.

    * Example calls:

    quicksort( &myArray[0], 5 ); // sorts elements 0, 1, 2, 3, and 4
    quicksort( &myArray[3], 5 ); // sorts elements 3, 4, 5, 6, and 7    
    */

#define  MAX_LEVELS  300

    int  piv, beg[MAX_LEVELS], end[MAX_LEVELS], i=0, L, R, swap;

    beg[0]=0; end[0]=elements;

    while ( i >= 0 )
    {
        L = beg[i]; 
        R = end[i]-1;

        if ( L < R )
        {
            piv = arr[L];

            while ( L < R )
            {
                while ( arr[R] >= piv && L < R ) R--;

                if ( L < R ) {
                    arr[L++] = arr[R];
                }

                while ( arr[L] <= piv && L < R ) L++;

                if ( L < R ) {
                    arr[R--] = arr[L];
                }
            }

            arr[L] = piv;

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
}

void round_array_float( SV* arr_sv, int pre, int len ) 
{
    /*
      Niels Larsen, December 2012.

      Sets the values in a given array so they have no significant values 
      after a given precision. For example 5.42987 becomes 5.42000 at 
      precision 2. 
    */
    
    float* arr = get_ptr( arr_sv );

    int i, mul;

    mul = pow( 10, pre );

    for ( i = 0; i < len; i++ )
    {
        arr[i] = (float) ( (int) ( arr[i] * mul ) ) / mul;
    }

    return;
}

unsigned int set_array_min_uint( SV* arr_sv, unsigned int len, unsigned int min, unsigned int new )
{
    /*
      Niels Larsen, June 2013.

      Sets all values of the given array to 'new' if they are less than 'min'.
    */
    
    unsigned int* arr = get_ptr( arr_sv );
    
    int i, count;

    count = 0;

    for ( i = 0; i < len; i++ )
    {
        if ( arr[i] != new && arr[i] < min )
        {
            arr[i] = new;
            count ++;
        }
    }

    return count;
}

void set_element_byte( char* arr, int ndx, unsigned char val )
{
    /*
      Niels Larsen, June 2013.

      Sets an element. 
    */
    
    arr[ndx] = val;

    return;
}

void set_element_float( SV* arr_sv, int ndx, float val )
{
    /*
      Niels Larsen, June 2013.

      Sets an element. 
    */
    
    float* arr = get_ptr( arr_sv );
    
    arr[ndx] = val;

    return;
}

void set_element_uint( SV* arr_sv, int ndx, unsigned int val )
{
    /*
      Niels Larsen, June 2013.

      Sets an element. 
    */
    
    unsigned int* arr = get_ptr( arr_sv );

    arr[ndx] = val;

    return;
}

void set_mem( unsigned char* arr, unsigned int len )
{
    /*
      Niels Larsen, June 2013.

      Sets all elements of a given char array to zero.
    */
    
    memset( arr, 0, len );

    return;
}
    
int size_of_float()
{
    /*
      Niels Larsen, September 2012.

      Returns the number of bytes the C compiler uses for float declarations.
      When Perl knows this, it can pack/unpack strings accordingly that are
      passed to C as arrays. Perl is always compiled with -Duse64bitint.
    */

    return sizeof(float);
}

int size_of_int()
{
    /*
      Niels Larsen, September 2012.

      Returns the number of bytes the C compiler uses for int declarations.
      When Perl knows this, it can pack/unpack strings accordingly that are
      passed to C as arrays. Perl is always compiled with -Duse64bitint.
    */

    return sizeof(int);
}

int size_of_long()
{
    /*
      Niels Larsen, September 2012.

      Returns the number of bytes the C compiler uses for long declarations.
      When Perl knows this, it can pack/unpack strings accordingly that are
      passed to C as arrays. Perl is always compiled with -Duse64bitint.
    */

    return sizeof(long);
}

float sum_array_float( SV* arr_sv, int len )
{
    /*
      Niels Larsen, November 2012.

      Returns the sum of all values in the given array.
    */

    float* arr = get_ptr( arr_sv );

    float sum;
    int i;
    
    sum = 0;

    for ( i = 0; i < len; i++ )
    {
        sum += arr[i];
    }

    return sum;
}

__END__
