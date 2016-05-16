package Pat::Patscan;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# December 30, 2011. Gene Selkov and Niels Larsen.
#
# Patscan interface
# -----------------
#
# The original patscan (scan_for_matches) package processed files only and did
# not have functions for single strings. This version adds the functions
#
# match_pattern_forward
# match_pattern_reverse
#
# to the patscan library, and the Perl interface below defines these functions,
#
# compile_pattern_C
# match_pattern_forward_C
# match_pattern_reverse_C
#
# Pattern text should first be converted from text string to an efficient 
# internal representation, which then lives in the C space until overwritten. 
# Then the two match routines can be run many times without performance loss.
# Each match routine returns a match list of lists, as in this example:
#
#   [ [[0,6],[10,5]], [[30,7],[39,5]] ]
# 
# In this example a two-element pattern has matched twice. The first match
# "two sub-matches, the first starting at position 0 and of length 6, the 
# second at position 10, length 5". These coordinates are the same for both
# directions.
#
# Patscan reference and download
# ------------------------------
# 
# The patscan functionality is described in
#
# Dsouza M, Larsen N, Overbeek R. Searching for patterns in genomic data. 
# Trends Genet. 1997 Dec;13(12):497-8.
#
# The latest version of the package can be downloaded from 
# 
# http://www.theseed.org/servers/downloads/scan_for_matches.tgz
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;

BEGIN 
{
  my $inline_dir = "./inline_dir";

  mkdir $inline_dir unless -d $inline_dir;

  use Inline ( C => 'DATA',
               DIRECTORY => $inline_dir,
               LIBS => '-L/home/niels/People/Selkov-Jr/patscan -lpatscan',
               BUILD_NOISY => 1,
      );
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

1;

__DATA__
__C__

int protein_flag;

int compile_pattern( char* pattern, protein )
{
    /*
        Niels Larsen, December 2011.
        
        Converts a string pattern to internal Patscan representation. 
        Returns 1 if syntax is ok, 0 otherwise. Use this function before
        calling match_(forward,reverse) many times. 
    */
    
    if ( protein )
    {
        protein_flag = 1;
        return ( parse_peptide_cmd(pattern) ? 1 : 0 );
    }
    else
    {
        protein_flag = 0;
        return ( parse_dna_cmd(pattern) ? 1 : 0 );
    }
}

SV* decode_matches_forward( unsigned long hitbuf[] )
{
    /*
        Niels Larsen, December 2011.

        Creates a perl array from patscan matches. The patscan functions 
        match_forward and match_reverse encode matches in an array like 
        this:

        { 2,  2,0,6,10,5,  2,30,7,39,5 }
    
        First element is the number of matches with the entire pattern,
        and each following cluster of numbers are the pattern element sub-
        matches. The first match reads "two sub-matches, the first starting
        at 0 and of length 6, the second at position 10, length 5". This 
        routine returns the above example to Perl as

        [ [[0,6],[10,5]], [[30,7],[39,5]] ]
    */

    AV* mats = newAV();
    AV* submats;
    AV* submat;

    int ndx, ihit, isubs, isub;

    ndx = 1;

    for ( ihit = 0; ihit < hitbuf[0]; ihit++ )
    {
        submats = newAV();
        av_push( mats, newRV_noinc( (SV*)submats ));

        isubs = hitbuf[ndx++];

        for ( isub = 0; isub < isubs; isub++ )
        {
            submat = newAV();
            av_push( submats, newRV_noinc( (SV*)submat ));

            av_push( submat, newSVuv( hitbuf[ndx++] ) );
            av_push( submat, newSVuv( hitbuf[ndx++] ) );
        }
    }

    return newRV_noinc( (SV*) mats );
}

SV* decode_matches_reverse( unsigned long hitbuf[], int seqlen )
{
    /*
        Niels Larsen, December 2011.

        Decodes the same hit buffer as decode_matches_forward, but returns 
        numbers as seen from the beginning of the sequence. 
    */

    AV* mats = newAV();
    AV* submats;
    AV* submat;

    int ndx, seqmax, ihit, isubs, isub, matpos, matlen;

    ndx = 1;
    seqmax = seqlen - 1;

    for ( ihit = 0; ihit < hitbuf[0]; ihit++ )
    {
        submats = newAV();

        av_unshift( mats, 1 );
        av_store( mats, 0, newRV_noinc( (SV*)submats ));
        
        isubs = hitbuf[ndx++];

        for ( isub = 0; isub < isubs; isub++ )
        {
            submat = newAV();

            av_unshift( submats, 1 );
            av_store( submats, 0, newRV_noinc( (SV*)submat ));

            av_unshift( submat, 2 );

            matpos = hitbuf[ndx++];
            matlen = hitbuf[ndx++];

            av_store( submat, 0, newSVuv( seqlen - matpos - matlen ) );
            av_store( submat, 1, newSVuv( matlen ) );
        }
    }

    return newRV_noinc( (SV*) mats );
}

SV* match_forward( SV* seq )
{
    /*
        Niels Larsen, December 2011.

        Matches the currently compiled (with compile_pattern above) pattern
        against the given sequence in the forward direction. The only argument
        is a Perl string, passed from Perl as the string variable. Returns a 
        list of lists, see decode_matches_forward above.
    */

    STRLEN seqlen;
    char *seqptr;

    seqptr = SvPV( seq, seqlen );

    unsigned long hitbuf_size = seqlen/2 + 100;
    unsigned long hitbuf[ hitbuf_size ];
    unsigned long hitbuf_len;

    match_pattern_forward( seqptr, seqlen, hitbuf, protein_flag );

    hitbuf_len = 1 + hitbuf[0] + 2 * hitbuf[0] * hitbuf[1];
    
    if ( hitbuf_len > hitbuf_size ) 
    {
        fprintf( stderr, " *************\n PATSCAN ERROR\n" );
        fprintf( stderr, " Match buffer length exceeds its allocated size: %d > %d\n", hitbuf_len, hitbuf_size );
        fprintf( stderr, " *************\n" );

        exit(1);
    }

    return decode_matches_forward( hitbuf );
}

SV* match_reverse( SV* seq )
{
    /*
        Niels Larsen, December 2011.

        Matches the currently compiled (with compile_pattern above) pattern
        against the given sequence in the reverse direction. The only argument
        is a Perl string, passed from Perl as the string variable. Returns a 
        list of lists, see decode_matches_reverse above.
    */

    STRLEN seqlen;
    char *seqptr;

    seqptr = SvPV( seq, seqlen);

    unsigned long hitbuf_size = seqlen/2 + 100;
    unsigned long hitbuf[ hitbuf_size ];
    unsigned long hitbuf_len;
    
    match_pattern_reverse( seqptr, seqlen, hitbuf, protein_flag );

    hitbuf_len = 1 + hitbuf[0] + 2 * hitbuf[0] * hitbuf[1];

    if ( hitbuf_len > hitbuf_size ) 
    {
        fprintf( stderr, " *************\n PATSCAN ERROR\n" );
        fprintf( stderr, " Match buffer length exceeds its allocated size: %d > %d\n", hitbuf_len, hitbuf_size );
        fprintf( stderr, " *************\n" );

        exit(1);
    }

    return decode_matches_reverse( hitbuf, seqlen );
}

__END__
