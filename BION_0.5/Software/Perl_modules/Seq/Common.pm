package Seq::Common;                # -*- perl -*-

# /*
#
# DESCRIPTION
#
# Routines that manipulate single sequences. They 
# provide only simple operations like "sub-sequence", "complement", etc.
# Some take a sequence object as first argument, and can thus work as 
# instance methods. However this module returns hashes, not objects, as
# blessing slows speed critical routines by 2-2.5 times. Callers do the
# blesses where the convenience methods and object is the most important.
# The @Methods and @Functions lists show routines that can and cannot be
# used as methods.
#
# Sequences
# ---------
#
# They are hashes, with these fields,
#
# id            (string of non-white-space characters)
# type          Alphabet name, one of the keys in %Alphabets below
# strand        + or -
# seq           String of characters from one of %Alphabets below
# qual          String of characters between @ and ~ 
# gaps          String of e.g. "2<3-,5<2~" (from GGC---AGG~~)
#
# Other fields are not permitted, unless explicitly added with the 
# add_field function.
#
# Locators
# --------
#
# These are ranges given by starting position, length and direction. For 
# example, a sub-sequence can be specified by lists of locators,
#
# [[6,10,'+'],[15,20,'-'],[60,40]]
#
# where '+' and '-' are direction indicators, '+' is default. Lists like
# these are input to the sub-sequence routine.
#
# Features
# --------
# 
# Like locators, but with a fourth feature-field, which can be a character
# or a hash with feature keys. Gaps are represented this way.
#
# Qualities
# ---------
#
# The routines use characters for qualities, according to current encodings.
# The user enters accuracy, which is then translated to characters. So for 
# example an accuracy of 0.9975 (1 error in 400 bases) would in Illumina 1.3
# encoding be translated to the character Z. 
#
# */

use strict;
use warnings FATAL => qw ( all );

use feature "state";

use POSIX;
use Storable qw( dclone );
use File::Basename;
use List::Util;

my $inline_dir;

BEGIN 
{
    $inline_dir = &Common::Config::create_inline_dir("Seq/Common");
    $ENV{"PERL_INLINE_DIRECTORY"} = $inline_dir;
}

use Inline C => "DATA", "DIRECTORY" => $inline_dir;

Inline->init;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> BION DEPENDENCY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# The &error function is exported from the Common::Messages module part of 
# BION, i.e. if the shell environment BION_HOME is set. If not, the &error
# function uses plain confess,

BEGIN
{
    if ( $ENV{"BION_HOME"} ) {
        eval qq(use Common::Config; use Common::Messages);
    } else {
        eval qq(use Carp; sub error { confess("Error: ". (shift) ."\n") });
    }
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our ( %Alphabets_str, %Alphabets_str_upper, %Alphabets, %Alphabets_upper,
      $RNA_disamb, $DNA_disamb, @Seq_fields, @Fields, %Seq_fields, %Fields );

# Set alphabets and allowed fields,

&_init_globals();

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> METHOD ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 
# Methods that operate on single sequence object hashes, blessed or not. Most
# return an updated object, but some return a list, a plain value or nothing.

our @Methods = (
    [ "add_field",           "Adds a field to the object" ],
    [ "complement",          "Translates and reverses sequences, gaps" ],
    [ "count_gaps",          "Counts the number of gap characters" ],
    [ "count_invalid",       "Number of invalid characters" ],
    [ "count_invalid_pct",   "Percent invalid characters" ],
    [ "delete_field",        "Deletes a field and its value" ],
    [ "delete_gaps",         "Deletes sequence gaps irreversibly" ],
    [ "disambiguate",        "Converts ambiguity codes to Watson-Crick" ],
    [ "embed_gaps",          "Inserts gaps from a gap string" ],
    [ "format_locator",      "Formats a location string, the opposite of parse_locator" ],
    [ "format_locators",     "Formats a list of locators, the opposite of parse_locators" ],
    [ "is_dna",              "Returns true if sequence looks like DNA" ],
    [ "is_rna",              "Returns true if sequence looks like RNA" ],
    [ "info_field",          "Returns the value of a given info field key" ],
    [ "lowercase",           "Changes the sequence to lowercase" ],
    [ "new",                 "Constructs sequence object" ], 
    [ "parse_info",          "Parses or sets the info field" ],
    [ "parse_locator",       "Parses a sequence location string" ],
    [ "parse_locators",      "Parses sequence location strings" ],
    [ "qual_to_info",        "" ],
    [ "qual_count",          "Counts quality residues" ],
    [ "qual_mask",           "Creates a quality mask" ],
    [ "qual_pct",            "Measures quality percentage" ],
    [ "seq_len",             "Returns sequence length" ],
    [ "seq_ref",             "Returns sequence string reference" ],
    [ "seq_stats",           "Returns sequence statistics" ],
    [ "splice_gaps",         "Moves gaps from sequence to gap vector" ],
    [ "sub_seq",             "Creates sub-sequence non-destructively" ],
    [ "sub_seq_clobber",     "Reduces to sub-sequence" ],
    [ "to_dna",              "Changes Uu to Tt" ],
    [ "to_rna",              "Changes Tt to Uu" ],
    [ "trim_beg_len",        "Trims n characters from the beginning" ],
    [ "trim_beg_qual",       "Trims the beginning by quality" ],
    [ "trim_beg_seq",        "Trims the beginning by sequence match" ],
    [ "trim_end_len",        "Trims n characters from the end" ],
    [ "trim_end_qual",       "Trims the end by quality" ],
    [ "trim_end_seq",        "Trims the end by sequence match" ],
    [ "truncate_id",         "Truncates the id after first occurrence of a character" ],
    [ "uppercase",           "Changes the sequence to uppercase" ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>> NON-METHOD ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions that work on other than single sequences. Most of these may be called
# from the outside but are considered "helper functions" that can be ignored, 

our @Functions = (
    [ "accessor_help",          "" ],
    [ "add_chars_str",          "" ],
    [ "agaps_to_sgaps",         "" ],
    [ "alphabet_freqs",         "" ],
    [ "alphabet_hash",          "" ],
    [ "alphabet_list",          "" ],
    [ "alphabet_list_upper",    "" ],
    [ "alphabet_str",           "" ],
    [ "complement_str",         "" ],
    [ "count_invalid_dna",      "" ],
    [ "count_invalid_nuc",      "" ],
    [ "count_invalid_prot",     "" ],
    [ "count_invalid_rna",      "" ],
    [ "count_valid_dna",        "" ],
    [ "count_valid_nuc",        "" ],
    [ "count_valid_prot",       "" ],
    [ "count_valid_rna",        "" ],
    [ "decrement_locs",         "" ],
    [ "format_loc_str",         "" ],
    [ "gaplocs_to_gapstr",      "" ],
    [ "gapstr_to_gaplocs",      "" ],
    [ "guess_type",             "" ],
    [ "increment_locs",         "" ],
    [ "is_nuc_type",            "" ],
    [ "iub_codes_chars",        "" ],
    [ "iub_codes_def",          "" ],
    [ "iub_codes_num",          "" ],
    [ "locate_agaps",           "" ],
    [ "locate_aseqs",           "" ],
    [ "locate_nongaps",         "" ],
    [ "locate_sgaps",           "" ],
    [ "match_hash_nuc",         "" ],
    [ "match_hash_prot",        "" ],
    [ "p_bin_selection",        "" ],
    [ "qual_config",            "" ],
    [ "qual_config_names",      "" ],
    [ "qual_match",             "" ],
    [ "qual_to_qualch",         "" ],
    [ "qualch_to_qual",         "" ],
    [ "random_seq",             "" ],
    [ "repair_id",              "" ],
    [ "reverse_locs",           "" ],
    [ "sgaps_to_agaps",         "" ],
    [ "spos_to_apos",           "" ],
    [ "sub_locs",               "" ],
    [ "sub_str",                "" ],
    [ "subtract_locs",          "" ],
    [ "validate_gaps",          "" ],
    );

our @Croutines = (
    [ "change_by_quality_C", "" ],
    [ "char_stats_C", "" ],
    [ "check_quals_min_C", "" ],
    [ "count_chars_invalid_C", "" ],
    [ "count_chars_valid_C", "" ],
    [ "count_quals_min_C", "" ],
    [ "count_quals_min_max_C", "" ],
    [ "count_similarity_beg_C", "" ],
    [ "count_similarity_end_C", "" ],
    [ "find_overlap_beg_C", "" ],
    [ "find_overlap_end_C", "" ],
    [ "join_seq_pairs_C", "" ],
    [ "trim_beg_qual_pos_C", "" ],
    [ "trim_end_qual_pos_C", "" ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD ACCESSORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub AUTOLOAD
{
    # Niels Larsen, November 2009.
    
    # Creates missing accessors.
    
    &_new_accessor( @_ );
}

sub _init_globals
{
    # Niels Larsen, December 2009.

    # Initializes global hashes and lists for alphabets and allowed fields. 
    # The routine is run once when this module is loaded, so the functions.

    my ( $key );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> ALPHABET HASHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # All alphabets are defined here, 

    %Alphabets_str_upper = (
        "dna"   => "AGCTRYWSMKHDVBN",
        "dna-"  => "TCGAYRWSKMDHBVN",
        "dna16" => "0123456789ABCDE",
        "dnawc" => "ACTG",
        
        "rna"   => "AGCURYWSMKHDVBN",
        "rna-"  => "UCGAYRWSKMDHBVN",
        "rna16" => "0123456789ABCDE",
        "rnawc" => "ACUG",

        "nuc"   => "AGCTURYWSMKHDVBN",
        "nuc-"  => "TCGAAYRWSKMDHBVN",
        "nucgc" => "GC",
        "nucat" => "ATU",

        "prot"  => "GAVLISTDNEQCMFYWKRHP",
        
        "gaps"  => "-~.",
        "qual"  => ( join "", map { chr $_ } ( 64 ... 126 ) ),
        "ascii" => ( join "", map { chr $_ } ( 0 ... 127 ) ),
        );

    # Append lower case, where it makes sense,

    %Alphabets_str = %Alphabets_str_upper;

    foreach $key ( keys %Alphabets_str )
    {
        if ( $key !~ /16|gaps|qual$/ ) {
            $Alphabets_str{ $key } .= lc $Alphabets_str{ $key };
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> ALPHABET LISTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # List versions of the above,

    %Alphabets_upper = map { $_, [ split "", $Alphabets_str_upper{ $_ } ] } keys %Alphabets_str_upper;
    %Alphabets = map { $_, [ split "", $Alphabets_str{ $_ } ] } keys %Alphabets_str;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ALPHABET STRINGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create strings that are handy in routines below, just to reduce number 
    # of calls,

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OBJECT FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    #
    # Allowed fields in sequence objects are specified here. Fields are divided 
    # into sequence-related and non-sequence-related; then methods know not to 
    # forget a field during transformation. Object is a hash and all fields are 
    # strings. The fields "id" and "seq" are mandatory, the rest not.
    
    @Seq_fields = qw( seq qual mask );
    @Fields = ( qw( id type info header annot strand ), @Seq_fields, qw( gaps ));
    
    %Fields = map { $_, 1 } @Fields;
    %Seq_fields = map { $_, 1 } @Seq_fields;

    return;
}

sub _new_accessor
{
    # Niels Larsen, May 2007.

    # Creats a get/setter method if 1) it is not already defined (explicitly
    # or by this routine) and 2) its name are among the keys in the hash given.
    # Attempts to use methods not in @Fields will trigger a crash with 
    # trace-back.

    my ( $seq,         # Sequence object 
         ) = @_;

    # Returns nothing.

    our $AUTOLOAD;
    my ( $field, $pkg, $code, $str );

    caller eq __PACKAGE__ or &error( qq(May only be called from within ). __PACKAGE__ );

    # Isolate name of the method called and the object package (in case it is
    # not this package),

    return if $AUTOLOAD =~ /::DESTROY$/;

    $field = $AUTOLOAD;
    $field =~ s/.*::// ;

    $pkg = ref $seq;

    # Create a code string that defines the accessor and crashes if its name 
    # is not found in the object hash,

    $code = qq
    {
        package $pkg;
        
        sub $field
        {
            my \$seq = shift;
            
            if ( exists \$Fields{"$field"} )
            {
                \@_ ? \$seq->{"$field"} = shift : \$seq->{"$field"};
            } 
            else
            {
                local \$Common::Config::with_stack_trace;
                \$Common::Config::with_stack_trace = 0;

                &user_error( &Seq::Common::accessor_help( \$field ), "PROGRAMMER ERROR" );
                exit -1;
            }
        }
    };

    eval $code;
    
    if ( $@ ) {
        &error( "Could not create method $AUTOLOAD : $@" );
    }
    
    goto &{ $AUTOLOAD };
    
    return;
};

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_field
{
    # Niels Larsen, November 2009.
    
    # Adds an allowed field to an existing hash, optionally with the given 
    # value. Returns the updated hash.

    my ( $seq,
         $field,      # Field name
         $value,      # Field value - OPTIONAL
         $force,      # 
        ) = @_;

    # Returns hash or object.

    if ( exists $Fields{ $field } or $force ) {
        $seq->{ $field } = $value;
    } else {
        &error( qq (Field not allowed -> "$field") );
    }

    return $seq;
}

sub complement
{
    # Niels Larsen, November 2009.

    # Complements (translate and reverse) a nucleotide sequence with qualities
    # and preservation of case. Works on gapped or ungapped sequence, with or 
    # without gap specification string. Strange things happen with a protein 
    # sequence, no check is done, and the caller must make sure it is DNA or 
    # RNA.

    my ( $seq,     # Sequence object or hash
         ) = @_;

    # Returns hash or object.

    my ( $field, $gaps );

    # Reverse all sequence-related fields,

    foreach $field ( @Seq_fields )
    {
        if ( exists $seq->{ $field } )
        {
            $seq->{ $field } = reverse $seq->{ $field };
        }
    }
    
    if ( exists $seq->{"seq"} )
    {
        # Translate sequence,
        
        $seq->{"seq"} =~ tr/AGCTURYWSMKHDVBNagcturywsmkhdvbn/TCGAAYRWSKMDHBVNtcgaayrwskmdhbvn/;
        
        if ( exists $seq->{"gaps"} ) 
        {
            # Reverse gap locations,
            
            $gaps = &Seq::Common::gapstr_to_gaplocs( \$seq->{"gaps"} );
            $gaps = &Seq::Common::reverse_locs( $gaps, length $seq->{"seq"} );
            
            $seq->{"gaps"} = ${ &Seq::Common::gaplocs_to_gapstr( $gaps ) };
        }
    }
    
    # Toggle strand,
    
    if ( $seq->{"strand"} ) {
        $seq->{"strand"} = $seq->{"strand"} eq "+" ? "-" : "+";
    } else {
        $seq->{"strand"} = "-";
    }

    return $seq;
}

sub count_gaps
{
    # Niels Larsen, November 2009.

    # Returns the number of gap characters in the sequence of a given 
    # object. 

    my ( $seq,
        ) = @_;
    
    # Returns integer. 

    return $seq->{"seq"} =~ tr/-~./-~./;
}

sub count_invalid
{
    # Niels Larsen, November 2009.

    # Returns the number of invalid characters in the sequence of a given 
    # object. 

    my ( $seq,
         $type,    # Data type 
        ) = @_;
    
    # Returns integer. 

    my ( $count, $routine );

    no strict "refs";

    $routine = "Seq::Common::count_invalid_" . ( $type // $seq->{"type"} );

    $count = $routine->( \$seq->{"seq"} );

    return $count;
}

sub count_invalid_pct
{
    # Niels Larsen, November 2009.

    # Returns the percentage of invalid characters in the sequence of a given 
    # object. 

    my ( $seq,
         $type,    # Alphabet name - OPTIONAL
        ) = @_;
    
    # Returns number. 

    return 100 * &Seq::Common::count_invalid( $seq, $type ) / ( length $seq->{"seq"} );
}

sub delete_field
{
    # Niels Larsen, November 2009.
    
    # Deletes a field with the given name. No error if the field does not 
    # exist. Returns an updated object.

    my ( $seq,
         $key,
        ) = @_;

    # Returns hash or object.

    if ( defined $key ) {
        delete $seq->{ $key };
    } else {
        &error("No delete key given");
    }

    return $seq;
}

sub delete_gaps
{
    # Niels Larsen, November 2009.

    # Irreversibly and destructively removes all indels in a given object. See
    # also splice_gaps and insert_gaps, which instead swap gaps in and out of 
    # a sequence. 

    my ( $seq,         
         ) = @_;
    
    # Returns hash or object.

    my ( $locs, $field );

    $locs = &Seq::Common::locate_nongaps( \$seq->{"seq"} );

    foreach $field ( @Seq_fields )
    {
        if ( exists $seq->{ $field } ) {
            $seq->{ $field } = ${ &Seq::Common::sub_str( \$seq->{ $field }, $locs ) };
        }
    }

    return $seq;
}

sub disambiguate
{
    # Niels Larsen, February 2010.

    # For DNA/RNA sequences, substitutes IUB ambiguity codes to Watson-Crick 
    # bases.

    my ( $seq, 
         ) = @_;
    
    # Returns hash or object. 

    my ( $expr );

    if ( $seq->{"type"} )
    {
	if ( $seq->{"type"} eq "rna" )	{
            $seq->{"seq"} =~ tr/TRYWSMKHDVBNtrywsmkhdvbn/UGCAGUAAAAAGugcaguaaaaag/;
	} elsif ( $seq->{"type"} eq "dna" ) {
            $seq->{"seq"} =~ tr/URYWSMKHDVBNurywsmkhdvbn/TGCAGTAAAAAGtgcagtaaaaag/;
	}
    }
    else {
	&error( qq (Type must be set to disambiguate) );
    }

    return $seq;
}

sub embed_gaps
{
    # Niels Larsen, November 2009.

    # Inserts gaps into the sequence and quality parts of a sequence object.
    # If no gaps are given as second argument, the "gaps" field must be set.
    # Returns an updated object.

    my ( $seq,
         $gaps,         # Gap descriptor list - OPTIONAL
         $dele,         # Whether to delete the gap descriptor - OPTIONAL, default 1
        ) = @_;

    # Returns hash or object.

    my ( $field );

    $dele //= 1;

    if ( not $gaps )
    {
        if ( exists $seq->{"gaps"} ) {
            $gaps = $seq->{"gaps"};
        } else {
            &error( qq (No gaps given, and gaps field not set) );
        }
    }

    if ( not ref $gaps ) {
        $gaps = &Seq::Common::gapstr_to_gaplocs( \$gaps );
    }

    foreach $field ( @Seq_fields )
    {
        if ( exists $seq->{ $field } ) {
            $seq->{ $field } = ${ &Seq::Common::add_chars_str( \$seq->{ $field }, $gaps ) };
        }
    }

    if ( $dele ) {
        delete $seq->{"gaps"};
    }

    return $seq;
}

sub format_locator
{
    # Niels Larsen, August 2010.

    # Formats a list like [ "AUCHH43", [[6,10,'+'],[15,20,'-'],[60,40,'+']]]
    # into "AUCHH43:6,10;25,20,-;60,40,+". Or if there is no sub-sequence 
    # coordinates, then [ "AUCHH43" ] becomes "AUCHH43". This function does 
    # the reverse of the parse_locator function. 

    my ( $loc,          # Location 
         ) = @_;

    # Returns a string.

    my ( $str );

    $str = $loc->[0];

    if ( defined $loc->[1] )
    {
        $str .= " ". ${ &Seq::Common::format_loc_str( $loc->[1] ) };
    }

    return $str;
}

sub format_locators
{
    # Niels Larsen, August 2010.

    # Formats a list of parsed locators. A mixture of parsed and unparsed
    # is okay.

    my ( $locs,
        ) = @_;

    # Returns a list.

    my ( @locs );

    @locs = map { &Seq::Common::format_locator( $_ ) } @{ $locs };

    return wantarray ? @locs : \@locs;
}

sub is_dna
{
    # Niels Larsen, March 2013.

    # Returns 1 if the given sequence hash looks like DNA by composition,
    # otherwise nothing.

    my ( $seq,    # Sequence hash
         $rat,    # Ratio of DNA-bases vs length
        ) = @_;

    # Returns 1 or nothing.

    my ( $count );

    $rat //= 0.9;

    $count = $seq->{"seq"} =~ tr/AGCTNagctn/AGCTNagctn/;

    if ( $count / length $seq->{"seq"} >= $rat ) {
        return 1;
    }
    
    return;
}

sub is_not_dna
{
    # Niels Larsen, March 2013.

    # Returns 1 if the given sequence hash looks like DNA by composition,
    # otherwise nothing.

    my ( $seq,    # Sequence hash
         $rat,    # Ratio of DNA-bases vs length
        ) = @_;

    # Returns 1 or nothing.

    my ( $count );

    $rat //= 0.9;

    $count = $seq->{"seq"} =~ tr/AGCTagct/AGCTagct/;

    if ( $count / length $seq->{"seq"} < $rat ) {
        return 1;
    }
    
    return;
}

sub is_rna
{
    # Niels Larsen, March 2013.

    # Returns 1 if the given sequence hash looks like RNA by composition,
    # otherwise nothing.

    my ( $seq,    # Sequence hash
         $rat,    # Ratio of DNA-bases vs length
        ) = @_;

    # Returns 1 or nothing.

    my ( $count );

    $rat //= 0.9;

    $count = $seq->{"seq"} =~ tr/AGCUagcu/AGCUagcu/;

    if ( $count / length $seq->{"seq"} >= $rat ) {
        return 1;
    }
    
    return;
}

sub info_field
{
    # Niels Larsen, October 2010.

    # Returns the value of the header field with a given key. Does not parse
    # the info string into an object (which is slower) but depends on the 
    # exact format of the info string - see Seq::Info::stringify.
    
    my ( $seq,
         $key,
        ) = @_;

    # Returns string.
    
    if ( defined $seq->{"info"} and $seq->{"info"} =~ /$key=([^;]+)/ ) {
        return $1;
    }

    return;
}

sub lowercase
{
    # Niels Larsen, November 2009.

    # Converts the sequence to lowercase. Returns an updated object.

    my ( $seq,
        ) = @_;

    # Returns hash or object.
    
    $seq->{"seq"} =~ tr/A-Z/a-z/;

    return $seq;
}

sub new
{
    # Niels Larsen, November 2009. 

    # Creates a sequence object with the given fields and values. The fields
    # must be in the global hash %Fields (see top of this module) and
    # the values must be simple scalars, with two exceptions: "seq" and "qual"
    # may be string references, but the object is always populated with the 
    # string, not the reference. Using a field that does not exist in the 
    # resulting object causes crash; to add and remove fields use the 
    # add_field and delete_field methods. 

    my ( $class,
         $args,           # Arguments hash
         $check,
         ) = @_;

    # Returns hash or object.

    my ( $seq, $key, $str, $type );

    $check //= 1;

    if ( $check )
    {
        # Check that there are at least id and sequence,
        
        if ( not defined $args->{"id"} ) {  &error( qq (An id must be given) );  }
        if ( not defined $args->{"seq"} ) {  &error( qq (A sequence string must be given) );  }

        # Put keys and values into a hash while checking for allowed keys, 

        foreach $key ( keys %{ $args } )
        {
            if ( exists $Fields{ $key } )
            {
                if ( ($key eq "seq" or $key eq "qual") and ref $args->{ $key } ) {
                    ${ $seq->{ $key } } = $args->{ $key };
                } else {
                    $seq->{ $key } = $args->{ $key };
                }
            }
            else {
                $str = join ", ", ( sort keys %Fields );
                &error( qq(Wrong looking field -> "$key".\nAllowed fields are $str.) );
            }
        }

        if ( $type = $seq->{"type"} ) 
        {
            if ( not exists $Alphabets{ lc $type } ) {
                &error( qq(Wrong looking type -> "$type") );
            }
        }
        else {
            $seq->{"type"} = &Seq::Common::guess_type( \$seq->{"seq"} );
        }
    }
    else {
        $seq = $args;
    }
    
    $seq->{"strand"} = "+" if not defined $seq->{"strand"};

    bless $seq, $class;
    
    return $seq;
}

sub parse_info
{
    # Niels Larsen, March 2011.

    # Converts the info field to an info object. 

    my ( $seq,
        ) = @_;

    # Returns hash or object. 

    my ( $info );

    if ( exists $seq->{"info"} )
    {
        $info = &Seq::Info::objectify( $seq->{"info"} );

        if ( defined wantarray ) {
            return $info;
        } else {
            $seq->{"info"} = $info;
        }
    }
    else {
        &error( qq (No info field) );
    }

    return $seq;
}

sub parse_loc_str
{
    # Niels Larsen, March 2011. 

    # Parses a string of the form '6,10;25,20,-;60,40,+' into 
    # 
    # [[6,10,'+'],[15,20,'-'],[60,40,'+']]
    #
    # If an error list is given, then parse errors go there, otherwise 
    # fatal error. 
    
    my ( $str,
         $msgs,
        ) = @_;

    # Returns list.

    my ( $loc, @locs );

    foreach $loc ( split ";", $str, -1 )
    {
        if ( $loc =~ /^(\d+),(\d+),?(\+|\-)?$/o )
        {
            push @locs, [ $1-1, $2, $3 || "+" ];
        }
        elsif ( $loc eq "" ) 
        {
            push @locs, undef;
        }
        elsif ( $msgs )
        {
            push @{ $msgs }, ["ERROR", qq (Wrong looking locator string -> "$loc") ];
        }
        else {
            &error( qq (Wrong looking locator string -> "$loc") );
        }            
    }
    
    return wantarray ? @locs : \@locs;
}
    
sub parse_locators
{
    # Niels Larsen, August 2010.

    # Parses locator strings of the form "ID 6,10;25,20,-;60,40,+"
    # into [ "ID", [[6,10,'+'],[15,20,'-'],[60,40,'+']]]. If there is 
    # no sub-sequence locators, then "ID" becomes [ "ID" ]. If 
    # the input string is wrong-looking, then either a fatal error happens 
    # or if a message list is given, messages are appended to that. 

    my ( $locs,      # Locator string list
         $msgs,      # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list. 

    my ( @locs, @msgs, $str, $id, $loclist );

    @msgs = ();

    foreach $str ( @{ $locs } )
    {
        if ( $str =~ /^([^ ]+)$/o )
        {
            push @locs, [ $1 ];
        }
        elsif ( $str =~ /^([^ ]+) (.+)$/o )
        {
            $id = $1;
            $loclist = &Seq::Common::parse_loc_str( $2, $msgs );

            push @locs, [ $id, $loclist ];
        }
        else {
            push @msgs, ["ERROR", qq (Wrong looking location string -> "$str") ];
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @locs : \@locs;
}

sub qual_to_info
{
    my ( $seq,
        ) = @_;

    if ( $seq->{"info"} ) {
        $seq->{"info"} .= qq (; seq_quals=$seq->{"qual"});
    } else {
        $seq->{"info"} .= qq (seq_quals=$seq->{"qual"});
    }

    return $seq;
}
    
sub qual_count
{
    # Niels Larsen, November 2009.

    # Counts the number of residues with quality in a given range. If locations
    # are given, then only those locations are measured for quality.
    
    my ( $seq, 
         $minch,      # Minimum quality character
         $maxch,      # Maximum quality character 
         $locs,       # Locator list - OPTIONAL
        ) = @_;

    # Returns integer.

    my ( $loc, $maxlen, $pos, $len, $count );

    if ( $locs )
    {
        $count = 0;

        foreach $loc ( @{ $locs } )
        {
            next if not defined $loc;

            ( $pos, $len ) = @{ $loc };

            if ( $pos + $len > length $seq->{"qual"} )
            {
                $maxlen = length $seq->{"qual"};
                &error( qq (Position $pos + $len goes past the end of the $maxlen long sequence) );
            }

            $count += &Seq::Common::count_quals_min_max_C( $seq->{"qual"}, $pos, $len, $minch, $maxch );
        }
    }
    else {
        $count = &Seq::Common::count_quals_min_max_C( $seq->{"qual"}, 0, length $seq->{"qual"}, $minch, $maxch );
    }

    return $count;
}

sub qual_pct
{
    # Niels Larsen, November 2009.

    # Counts the percentage of characters that are within a given quality
    # range. Given locations only those regions are looked at.

    my ( $seq,
         $minch,     # Quality percentage minimum
         $maxch,     # Quality percentage maximum - OPTIONAL, default 100.0
         $locs,      # Location list - OPTIONAL
        ) = @_;

    # Returns number.

    my ( $count, $len, $pct );

    $count = &Seq::Common::qual_count( $seq, $minch, $maxch, $locs );

    if ( $locs ) {
        $len = &List::Util::sum( map { $_->[1] } grep { defined $_ } @{ $locs } );
    } else {
        $len = length $seq->{"qual"};
    }

    if ( $count == 0 ) {
        $pct = 0;
    } else {
        $pct = 100 * $count / $len;
    }
    
    return $pct;
}

sub seq_len
{
    # Niels Larsen, October 2009.

    # Returns the length of a given sequence. 

    my ( $seq,
         ) = @_;

    # Returns integer. 

    return length $seq->{"seq"};
}

sub seq_ref
{
    # Niels Larsen, November 2009.
    
    # Returns a reference to the sequence string. 

    my ( $seq,
         ) = @_;

    # Returns string reference.

    return \$seq->{"seq"};
}

sub seq_stats
{
    # Niels Larsen, November 2011.

    # Counts characters of a sequence, or if locations are given parts of it. 
    # A list of [ character, count ] is returned. Upper- and lower case are 
    # listed separately. 

    my ( $seq,
         $locs,     # Locations list - OPTIONAL
         $chars,
        ) = @_;

    # Returns list or list reference. 
    
    my ( @counts, $counts, $count, $loc, $char, @stats );

    $counts = pack "I127", (0) x 127;

    if ( $locs )
    {
        foreach $loc ( @{ $locs } )
        {
            &Seq::Common::char_stats_C( $seq->{"seq"}, $counts, $loc->[0], $loc->[1] );
        }            
    }
    else {
        &Seq::Common::char_stats_C( $seq->{"seq"}, $counts, 0, length $seq->{"seq"} );
    }

    @counts = unpack "I127", $counts;

    $chars = &Seq::Common::alphabet_list( $seq->{"type"} ) unless $chars;

    foreach $char ( @{ $chars } ) 
    {
        if ( ( $count = $counts[ ord $char ] ) > 0 )
        {
            push @stats, [ $char, $count ];
        }
    }
    
    return wantarray ? @stats : \@stats;
}

sub seq_stats_upper
{
    # Niels Larsen, November 2011.

    # Counts characters of a sequence, or if locations are given parts of it. 
    # A list of [ character, count ] is returned. Looks for upper case 
    # characters only.

    my ( $seq,
         $locs,     # Locations list - OPTIONAL
        ) = @_;

    # Returns list or list reference. 
    
    my ( $chars, $stats );

    $chars = &Seq::Common::alphabet_list_upper( $seq->{"type"} );
        
    $stats = &Seq::Common::seq_stats( $seq, $locs, $chars );

    return wantarray ? @{ $stats } : $stats;
}

sub uppercase
{
    # Niels Larsen, October 2010.

    # Converts sequence to uppercase.

    my ( $seq,
        ) = @_;

    # Returns hash or object.
    
    $seq->{"seq"} =~ tr/a-z/A-Z/;

    return $seq;
}

sub splice_gaps
{
    # Niels Larsen, November 2009.

    # Removes gaps but stores them as a string in the object, as value
    # of the field "gaps". See the gaplocs_to_gapstr routine.

    my ( $seq,
        ) = @_;

    # Returns hash or object.

    my ( $gaps, $strref );

    $gaps = &Seq::Common::locate_sgaps( $seq->{"seq"} );

    if ( $strref = &Seq::Common::gaplocs_to_gapstr( $gaps ) )
    {
        $seq->{"gaps"} = ${ $strref };
    }

    &Seq::Common::delete_gaps( $seq );

    return $seq;
}

sub sub_seq
{
    # Niels Larsen, November 2009.

    # Returns a sub-sequence entry according to a given location list. The given
    # sequence entry is not modified. 

    my ( $seq,      # Entry
         $locs,     # Locators
         $mkobj,    # Make object or not - OPTIONAL, default 1
        ) = @_;

    # Returns hash or object.

    my ( $field, $subseq );

    if ( $locs ) {
        $locs = &Seq::Common::parse_loc_str( $locs ) if not ref $locs;
    } else {
        &error("No locations given");
    }

    # print qq ($seq->{"id"} - ). length $seq->{"seq"} ."\n";

    foreach $field ( @Fields )
    {
        if ( exists $seq->{ $field } )
        {
            if ( $Seq_fields{ $field } )
            {
                if ( $field eq "seq" ) {
                    $subseq->{ $field } = ${ &Seq::Common::sub_str( \$seq->{ $field }, $locs, 1 ) };
                } else {
                    $subseq->{ $field } = ${ &Seq::Common::sub_str( \$seq->{ $field }, $locs, 0 ) };
                }
            }
            else {
                $subseq->{ $field } = $seq->{ $field };
            }
        }
    }

    if ( $mkobj ) {
        $subseq = __PACKAGE__->new( $subseq, 0 );
    }

    return $subseq;
}

sub sub_seq_clobber
{
    # Niels Larsen, November 2009.

    # Returns a sub-sequence entry according to a given location list. The sequence
    # of the given object is overwritten with the sub-sequence. 

    my ( $seq,      # Entry
         $locs,     # Locators
         ) = @_;

    # Returns hash or object.

    my ( $key, $field, $subseq );

    if ( $locs ) {
        $locs = &Seq::Common::parse_loc_str( $locs ) if not ref $locs;
    } else {
        &error("No locations given");
    }

    foreach $field ( @Seq_fields )
    {
        if ( exists $seq->{ $field } and $Seq_fields{ $field } )
        {
            if ( $field eq "seq" ) {
                $seq->{ $field } = ${ &Seq::Common::sub_str( \$seq->{ $field }, $locs, 1 ) };
            } else {
                $seq->{ $field } = ${ &Seq::Common::sub_str( \$seq->{ $field }, $locs, 0 ) };
            }
        }
    }

    return $seq;
}

sub to_dna
{
    # Niels Larsen, November 2009.

    # Substitutes all RNA characters to DNA characters. Returns an 
    # updated sequence object.

    my ( $seq,
        ) = @_;

    # Returns hash or object. 

    $seq->{"seq"} =~ tr/Uu/Tt/;

    $seq->{"type"} = "dna";

    return $seq;
}

sub to_rna
{
    # Niels Larsen, November 2009.

    # Substitutes all DNA characters to RNA characters. Returns a
    # list of updated sequence objects.

    my ( $seq,
        ) = @_;

    # Returns hash or object. 

    $seq->{"seq"} =~ tr/Tt/Uu/;

    $seq->{"type"} = "rna";

    return $seq;
}

sub trim_beg_len
{
    # Niels Larsen, December 2009.

    # Removes a given number of residues from the beginning of a sequence.
    # Returns an updated object.

    my ( $seq,
         $len,    # Number of residues to delete
        ) = @_;

    # Returns hash or object.

    my ( $field );
    
    if ( $len <= length $seq->{"seq"} )
    {
        foreach $field ( @Seq_fields )
        {
            if ( exists $seq->{ $field } ) {
                ( substr $seq->{ $field }, 0, $len ) = "";
            }
        }

        return $seq;
    }

    return;
}

sub trim_beg_qual
{
    # Niels Larsen, December 2009.

    # Trims the start of a sequence by quality. A window of a given length
    # is moved from the start one step at a time until it reaches a good enough 
    # stretch. Good enough means having at least a given number of characters
    # (wmin) above a certain ASCII value (cmin) within the window (wlen). Leading
    # low quality bases are finally stripped off. All sequence-related fields
    # are trimmed. Returns an updated object/hash, but nothing if 1) the input
    # sequence is shorter than the window length, or 2) if no quality residues
    # left. 

    my ( $seq,
         $cmin,       # Minimum quality character
         $wlen,       # Quality window length
         $whit,       # Minimum number of > min. quality residues in window 
        ) = @_;

    # Returns hash or object.
    
    my ( $trimlen, $slen );

    $slen = length $seq->{"qual"};

    if ( $slen >= $wlen )
    {
        $trimlen = &Seq::Common::trim_beg_qual_pos_C( $seq->{"qual"}, $slen, $cmin, $wlen, $whit );

        if ( $trimlen < $slen )
        {
            if ( $trimlen > 0 ) {
                &Seq::Common::trim_beg_len( $seq, $trimlen );
            }
            
            return $seq;
        }
    }
    
    return;
}

sub trim_beg_seq
{
    my ( $seq,
         $prb,      # Probe sequence used to trim
         $dist,     # Max distance from end
         $mrat,     # Maximum mismatches to length ratio
         $mmin,     # Minimum overlap length
        ) = @_;

    my ( $pos );

    $pos = &Seq::Common::find_overlap_beg_C( $seq->{"seq"}, $prb, $dist, $mrat, $mmin );

    if ( $pos >= 0 )
    {
        &Seq::Common::trim_beg_len( $seq, $pos + 1 );
    }

    return $seq;
}

sub trim_end_len
{
    # Niels Larsen, December 2009.

    # Removes a given number of residues from the end of a sequence.
    # Returns an updated object.

    my ( $seq,
         $len,    # Number of residues to delete
        ) = @_;

    # Returns hash or object.

    my ( $field, $begpos );
    
    if ( ( $begpos = (length $seq->{"seq"}) - $len ) > 0 )
    {
        foreach $field ( @Seq_fields )
        {
            if ( exists $seq->{ $field } ) {
                ( substr $seq->{ $field }, $begpos, $len ) = "";
            }
        }

        return $seq;
    }

    return;
}

sub trim_end_qual
{
    # Niels Larsen, December 2011.

    # Trims the end of a sequence by quality. A window of a given length
    # is moved from the end one step at a time until it reaches a good enough 
    # stretch. Good enough means having at least a given number of characters
    # (whit) above a certain value (cmin) within the window (wlen). Trailing
    # low quality bases are finally stripped off the end. All sequence-related
    # fields are trimmed. Returns an updated object/hash, but nothing if 1) 
    # the input sequence is shorter than the window length, or 2) if no 
    # quality residues left. 

    my ( $seq,       # Sequence hash or object
         $cmin,       # Minimum quality character
         $wlen,       # Quality window length
         $whit,       # Minimum number of good residues in window - OPTIONAL, default window length
        ) = @_;

    # Returns hash or object.
    
    my ( $trimlen, $slen );

    $slen = length $seq->{"qual"};

    if ( $slen >= $wlen )
    {
        $trimlen = &Seq::Common::trim_end_qual_pos_C( $seq->{"qual"}, $slen, $cmin, $wlen, $whit );

        if ( $trimlen < $slen )
        {
            if ( $trimlen > 0 ) {
                &Seq::Common::trim_end_len( $seq, $trimlen );
            }
            
            return $seq;
        }
    }
    
    return;
}

sub trim_end_seq
{
    my ( $seq,
         $prb,      # Probe sequence used to trim
         $dist,     # Max distance from end
         $mrat,     # Maximum mismatch to length ratio
         $mmin,     # Minimum overlap length
        ) = @_;

    my ( $pos );

    $pos = &Seq::Common::find_overlap_end_C( $seq->{"seq"}, $prb, $dist, $mrat, $mmin );
    
    if ( $pos == -1 )
    {
        return $seq;
    }
    elsif ( $pos > 0 )
    {
        &Seq::Common::trim_end_len( $seq, (length $seq->{"seq"}) - $pos );

        return $seq;
    }

    return;
}    

sub truncate_id
{
    # Niels Larsen, April 2010.

    # Truncates the id after first occurrence of a given character, which 
    # defaults to white space.

    my ( $seq,
         $ch,        # Character - OPTIONAL, default white space
        ) = @_;

    # Returns an updated object.

    if ( defined $ch ) {
        $ch = quotemeta $ch;
    } else {
        $ch = '\s';
    }

    $seq->{"id"} =~ s/$ch.+//x;

    return $seq;
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub accessor_help
{
    # Niels Larsen, December 2009.

    # Formats an error message and a simple list of a accessors and methods 
    # available. 

    my ( $field,    # A wrong field or method name
        ) = @_;

    # Returns string.

    my ( $msg, $fldstr, $maxwid, $row );

    $fldstr = join qq(", "), @Fields;

    $msg = qq(Unknown accessor or method "$field".)
          .qq( Get/setters available:\n\n  "$fldstr".\n\n)
          .qq( Methods available:\n);

    $maxwid = &List::Util::max( map { length $_->[0] } @Methods ) + 2;

    foreach $row ( @Methods ) {
        $msg .= (sprintf "%".$maxwid."s", $row->[0])."   $row->[1]\n";
    }

    return $msg;
}        

sub add_chars_str
{
    # Niels Larsen, November 2009.

    # Inserts a given character in a given string or string reference, following
    # the recipe of a given location list. Returns reference to a new string.

    my ( $str,       # String or string reference
         $locs,      # Locations list 
        ) = @_;

    # Returns string reference.

    my ( $strref, $newstr, $begpos, $maxpos, $loc, $locpos, $inslen, $ch );

    if ( ref $str ) { $strref = $str } else { $strref = \$str };

    $newstr = "";

    $begpos = 0;
    $maxpos = (length ${ $strref }) - 1;

    foreach $loc ( sort { $a->[0] <=> $b->[0] } grep { defined } @{ $locs } )
    {
        ( $locpos, $inslen, $ch ) = @{ $loc };

        if ( $locpos < -1 ) {
            &error( qq(Locator position is $locpos but must be -1 or greater.) );
        } elsif ( $locpos > $maxpos ) {
            &error( qq(Locator position is $locpos but must be $maxpos or less.) );
        }

        $newstr .= substr ${ $strref }, $begpos, $locpos - $begpos + 1;
        $newstr .= $ch x $inslen;

        $begpos = $locpos + 1;
    }

    $newstr .= substr ${ $strref }, $begpos;

    return \$newstr;
}

sub agaps_to_sgaps
{
    # Niels Larsen, November 2009.

    # Converts alignment numbered gap locations to sequence numbering. 
    # No new list copy is made, ie the input list is modified. Returns an
    # updated list.

    my ( $gaps,    # Gap locations
        ) = @_;

    # Returns list.

    my ( $gap, $gapsum );

    $gapsum = 0;

    foreach $gap ( @{ $gaps } )
    {
        $gap->[0] -= $gapsum;
        $gapsum += $gap->[1];
    }

    return wantarray ? @{ $gaps } : $gaps;
}

sub alphabet_freqs
{
    # Niels Larsen, November 2009.

    # Returns default frequency lists for the alphabet that corresponds to a given
    # type. That type must be key in the %Alphabets hash near the top of this module.

    my ( $name,    # Sequence type
        ) = @_;

    # Returns string.

    my ( $chars, $freqs, $pct );

    $name = lc $name;

    if ( $name =~ /^dna/ ) {
        $freqs = [ map { [ $_, 25.0 ] } qw( A G C T ) ];
    } elsif ( $name =~ /^rna/ ) {
        $freqs = [ map { [ $_, 25.0 ] } qw( A G C U ) ];
    } 
    elsif ( $name eq "prot" ) 
    {
        $freqs = [
            [ "G", 7.4 ],
            [ "A", 7.4 ],
            [ "V", 6.8 ],
            [ "L", 7.6 ],
            [ "I", 3.8 ],
            [ "S", 8.1 ],
            [ "T", 6.2 ],
            [ "D", 5.9 ],
            [ "N", 4.4 ],
            [ "E", 5.8 ],
            [ "Q", 3.7 ],
            [ "C", 3.3 ],
            [ "M", 1.8 ],
            [ "F", 4.0 ],
            [ "Y", 3.3 ],
            [ "W", 1.3 ],
            [ "K", 7.2 ],
            [ "R", 4.2 ],
            [ "H", 2.9 ],
            [ "P", 5.0 ],
            ];
    }
    else
    {
        $chars = &Seq::Common::alphabet_list( $name );

        $pct = sprintf "%.1f", 100 / ( scalar @{ $chars } );
        $freqs = [ map { [ $_, $pct ] } @{ $chars } ];
    }
        
    return wantarray ? @{ $freqs } : $freqs;
}

sub alphabet_hash
{
    # Niels Larsen, November 2009.

    # Creates a lookup hash from a given alphabet. A character is key 
    # and the hash returns 1 if the character is in the alphabet. 

    my ( $name,     # Alphabet name
        ) = @_;

    # Returns a hash.

    my ( %hash );

    %hash = map { $_, 1 } @{ &Seq::Common::alphabet_list( $name ) };

    return wantarray ? %hash : \%hash;
}

sub alphabet_list
{
    # Niels Larsen, November 2009.

    # Returns the alphabet list that corresponds to a given type. That
    # type must be key in the %Alphabets hash near the top of this module.

    my ( $name,    # Sequence type
        ) = @_;

    # Returns string.

    my ( $msg );

    if ( not defined $name ) 
    {
        $msg = join ",", ( sort keys %Alphabets );
        &error( qq(No alphabet name given\nChoices are: $msg.) );
    }
    elsif ( not exists $Alphabets{ lc $name } )
    {
        $msg = join ",", ( sort keys %Alphabets );
        &error( qq(Wrong looking alphabet name -> "$name"\nChoices are: $msg.) );
    }

    return $Alphabets{ lc $name };
}

sub alphabet_list_upper
{
    # Niels Larsen, November 2009.

    # Returns the alphabet list that corresponds to a given type. That
    # type must be key in the %Alphabets hash near the top of this module.

    my ( $name,    # Sequence type
        ) = @_;

    # Returns string.

    my ( $msg );

    if ( not defined $name ) 
    {
        $msg = join ",", ( sort keys %Alphabets_upper );
        &error( qq(No alphabet name given\nChoices are: $msg.) );
    }
    elsif ( not exists $Alphabets_upper{ lc $name } )
    {
        $msg = join ",", ( sort keys %Alphabets_upper );
        &error( qq(Wrong looking alphabet name -> "$name"\nChoices are: $msg.) );
    }

    return $Alphabets_upper{ lc $name };
}

sub alphabet_str
{
    # Niels Larsen, November 2009.

    # Returns the alphabet string that corresponds to a given type. That
    # type must be key in the %Alphabets_str hash near the top of this module.

    my ( $name,    # Sequence type
        ) = @_;

    # Returns string.

    my ( $msg );

    if ( not defined $name ) 
    {
        $msg = join ",", ( sort keys %Alphabets_str );
        &error( qq(No alphabet name given\nChoices are: $msg.) );
    }
    elsif ( not exists $Alphabets_str{ lc $name } )
    {
        $msg = join ",", ( sort keys %Alphabets_str );
        &error( qq(Wrong looking alphabet name -> "$name"\nChoices are: $msg.) );
    }

    return $Alphabets_str{ lc $name };
}

sub apos_to_spos
{
    # Niels Larsen, November 2012. 

    # Converts a number in a given aligned sequence to its sequence 
    # coordinate. 

    my ( $seq,    # Sequence with gaps
         $pos,    # Alignment position
        ) = @_;

    # Returns integer. 

    my ( $subseq, $count );

    $count = ( substr $seq->{"seq"}, 0, $pos+1 ) =~ tr/A-Za-z/A-Za-z/;

    return $count - 1;
}

sub complement_str
{
    # Niels Larsen, August 2010.

    # Complements a given nucleotide sequence string. If a string
    # reference is given, then the original is modified and a new 
    # reference to it is returned. If a string is given, then a 
    # reference to a copy is returned, without modifying the 
    # original. 

    my ( $str,    # String or string reference
        ) = @_;

    # Returns a string reference. 

    if ( ref $str )
    {
        ${ $str } = reverse ${ $str };
        ${ $str } =~ tr/AGCTURYWSMKHDVBNagcturywsmkhdvbn/TCGAAYRWSKMDHBVNtcgaayrwskmdhbvn/;

        return $str;
    }
    else
    {
        $str = reverse $str;
        $str =~ tr/AGCTURYWSMKHDVBNagcturywsmkhdvbn/TCGAAYRWSKMDHBVNtcgaayrwskmdhbvn/;
    }

    return \$str;
}

sub count_invalid_dna
{
    # Niels Larsen, December 2011.

    # Returns the number of DNA canonical base characters from 0 -> $wlen-1
    # of a given string reference.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("dnawc");

    return &Seq::Common::count_chars_invalid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub count_invalid_nuc
{
    # Niels Larsen, December 2011.

    # Returns the number of invalid DNA/RNA characters from 0 -> $wlen-1
    # of a given string reference. This includes gaps.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("nuc");

    return &Seq::Common::count_chars_invalid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub count_invalid_prot
{
    # Niels Larsen, December 2011.

    # Returns the number of non-protein residue characters from 0 -> $wlen-1
    # of a given string reference. This includes gaps.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("prot");

    return &Seq::Common::count_chars_invalid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub count_invalid_rna
{
    # Niels Larsen, December 2011.

    # Returns the number of RNA canonical base characters from 0 -> $wlen-1
    # of a given string reference.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("rnawc");

    return &Seq::Common::count_chars_valid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub count_valid_dna
{
    # Niels Larsen, December 2011.

    # Returns the number of DNA canonical base characters from 0 -> $wlen-1
    # of a given string reference.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("dnawc");

    return &Seq::Common::count_chars_valid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub count_valid_nuc
{
    # Niels Larsen, December 2011.

    # Returns the number of DNA/RNA canonical base characters from 0 -> $wlen-1
    # of a given string reference.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("nuc");

    return &Seq::Common::count_chars_valid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub count_valid_prot
{
    # Niels Larsen, December 2011.

    # Returns the number of protein residue characters from 0 -> $wlen-1
    # of a given string reference.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("prot");

    return &Seq::Common::count_chars_valid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub count_valid_rna
{
    # Niels Larsen, December 2011.

    # Returns the number of RNA canonical base characters from 0 -> $wlen-1
    # of a given string reference.

    my ( $sref,    # Sequence string reference
         $wlen,    # Count length - OPTIONAL, default 50
        ) = @_;

    # Returns integer. 

    state $valid = &Seq::Common::pack_valid_mask("rnawc");

    return &Seq::Common::count_chars_valid_C( ${ $sref }, length ${ $sref }, $wlen // 50, $valid );
}

sub decrement_locs
{
    # Niels Larsen, October 2009.

    # Subtracts a given value from the given locations. The input list is 
    # modified. Returns an updated list.

    my ( $locs,         # Location list
         $decr,         # Number to subtract
         ) = @_;

    # Returns a list reference.

    my ( $loc );

    foreach $loc ( @{ $locs } )
    {
        if ( defined $loc ) {
            $loc->[0] -= $decr;
        }
    }

    return wantarray ? @{ $locs } : $locs;
}

sub format_loc_str
{
    # Niels Larsen, March 2011.

    # Converts a list of tuples like [[6,10],[15,20,'-'],undef,[60,40,'+']]
    # to this string: '6,10,+;25,20,-;;60,40,+'. Elements can be undefined.

    my ( $locs,          # Locator list
        ) = @_;

    # Returns string reference. 

    my ( @locs, $loc, $locstr );

    foreach $loc ( @{ $locs } )
    {
        if ( defined $loc )
        {
            if ( defined $loc->[2] and $loc->[2] eq "-" ) {
                push @locs, ($loc->[0]+1) .",$loc->[1],-";
            } else {
                push @locs, ($loc->[0]+1) .",$loc->[1]";
            }
        }
        else {
            push @locs, "";
        }
    }

    if ( not @locs ) {
        &error( qq (Locator list empty) );
    }

    $locstr = join ";", @locs;    

    return \$locstr;
}

sub gaplocs_to_gapstr
{
    # Niels Larsen, November 2009.

    # Converts a list of gap locators to a string. Returns a reference 
    # to this string. 

    my ( $gaps,      # Locator list
        ) = @_;

    # Returns string reference. 

    my ( $gap, @gaps, $gapstr );

    foreach $gap ( @{ $gaps } )
    {
        if ( defined $gap ) {
            push @gaps, "$gap->[0]<$gap->[1]$gap->[2]";
        } else {
            push @gaps, "";
        }
    }

    if ( not @gaps ) {
        &error( qq(Gap locator list empty) );
    }

    $gapstr = join ",", @gaps;
    return \$gapstr;
} 

sub gapstr_to_gaplocs
{
    # Niels Larsen, November 2009.

    # Converts a gap locator string to a locator list. Crashes if given an 
    # empty or invalid string. Returns a locator list.

    my ( $gapstr,    # Gap string or reference
        ) = @_;

    # Returns list or nothing.

    my ( $strref, @gaps, $gap );

    if ( ref $gapstr ) { $strref = $gapstr } else { $strref = \$gapstr };

    foreach $gap ( split ",", ${ $strref }, -1 )
    {
        if ( $gap ne "" )
        {
            if ( $gap =~ /^(-1|\d+)<(\d+)([-~.])$/ ) {
                push @gaps, [ $1, $2, $3 ];
            } else {
                &error( qq(Wrong looking gap descriptor -> "$gap") );
            }
        }
        else {
            push @gaps, undef;
        }
    }

    if ( not @gaps ) {
        &error( qq(Gap locator list empty) );
    }

    return wantarray ? @gaps : \@gaps;
}

sub guess_type
{
    # Niels Larsen, November 2009.

    # Callers should set the type explicitly, but this routine guesses it.
    # Accepts a string reference and returns one of the types set as keys
    # in the global %Alphabets hash. Returns a short type string. 

    my ( $sref,
        ) = @_;

    # Returns string.

    my ( $len, $minrat, $rat, $count );

    $len = 100;        # Minimum length to check 
    $minrat = 0.8;     # Mininum valid/non-valid ratio

    # DNA?

    $rat = &Seq::Common::count_valid_dna( $sref, $len );
    return "dna" if $rat >= $minrat;

    # RNA?
    
    $rat = &Seq::Common::count_valid_rna( $sref, $len );
    return "rna" if $rat >= $minrat;
    
    # No, then protein,

    return "prot";
}
    
sub increment_locs
{
    # Niels Larsen, October 2009.

    # Increments the given locations by a given value. Modifies the 
    # given list. Returns an updated list.

    my ( $locs,         # Location list
         $incr,         # Number to increment
         ) = @_;

    # Returns list or list reference.

    my ( $loc );

    foreach $loc ( @{ $locs } )
    {
        if ( defined $loc ) {
            $loc->[0] += $incr;
        }
    }

    return wantarray ? @{ $locs } : $locs;
}

sub is_nuc_type
{
    # Niels Larsen, November 2009.

    # Returns 1 if the given type is rna or dna, otherwise nothing.

    my ( $type,
        ) = @_;

    # Returns 1 or nothing.

    $type = lc $type;

    if ( $type eq "rna" or $type eq "dna" ) {
        return 1;
    }

    return;
}

sub iub_codes_chars
{
    # Niels Larsen, May 2005.

    # Creates a hash that returns the IUB ambiguity code that corresponds
    # to two or more given Watson-Crick bases. The bases should be given 
    # as a string and in upper-case. It can be used to create a consensus
    # string with, for example.

    my ( $type,
        ) = @_;

    # Returns hash or hash reference.

    my ( $hash, $code, $bases );

    if ( not defined $type ) {
        &error( qq (Type is undefined) );
    }

    if ( &Common::Types::is_dna_or_rna( $type ) )
    {
        $hash->{"A"} = "A";
        $hash->{"C"} = "C";
        $hash->{"T"} = "T";
        $hash->{"G"} = "G";

        $hash->{"AG"} = $hash->{"GA"} = "R";
        $hash->{"CT"} = $hash->{"TC"} = "Y";
        $hash->{"AC"} = $hash->{"CA"} = "M";
        $hash->{"AT"} = $hash->{"TA"} = "W";
        $hash->{"GC"} = $hash->{"CG"} = "S";
        $hash->{"GT"} = $hash->{"TG"} = "K";
        
        $hash->{"GAT"} = $hash->{"GTA"} = "D";
        $hash->{"ATG"} = $hash->{"AGT"} = "D";
        $hash->{"TAG"} = $hash->{"TGA"} = "D";
        
        $hash->{"ATC"} = $hash->{"ACT"} = "H";
        $hash->{"TCA"} = $hash->{"TAC"} = "H";
        $hash->{"CTA"} = $hash->{"CAT"} = "H";
        
        $hash->{"GTC"} = $hash->{"GCT"} = "B";
        $hash->{"TCG"} = $hash->{"TGC"} = "B";
        $hash->{"CTG"} = $hash->{"CGT"} = "B";
        
        $hash->{"GAC"} = $hash->{"GCA"} = "V";
        $hash->{"ACG"} = $hash->{"AGC"} = "V";
        $hash->{"CAG"} = $hash->{"CGA"} = "V";
        
        $hash->{"AGTC"} = $hash->{"AGCT"} = "N";
        $hash->{"ATCG"} = $hash->{"ATGC"} = "N";
        $hash->{"ACTG"} = $hash->{"ACGT"} = "N";
        
        $hash->{"GATC"} = $hash->{"GACT"} = "N";
        $hash->{"TACG"} = $hash->{"TAGC"} = "N";
        $hash->{"CATG"} = $hash->{"CAGT"} = "N";
        
        $hash->{"GTAC"} = $hash->{"GCAT"} = "N";
        $hash->{"TCAG"} = $hash->{"TGAC"} = "N";
        $hash->{"CTAG"} = $hash->{"CGAT"} = "N";
        
        $hash->{"GTCA"} = $hash->{"GCTA"} = "N";
        $hash->{"TCGA"} = $hash->{"TGCA"} = "N";
        $hash->{"CTGA"} = $hash->{"CGTA"} = "N";
        
        foreach $bases ( keys %{ $hash } )
        {
            $code = $hash->{ $bases };
            
            if ( $bases =~ /T/ )
            {
                $bases =~ s/T/U/;
                $hash->{ $bases } = $code;
            }
            
            $hash->{ lc $bases } = lc $code;
        }
    }
    else {
        &error( qq (Wrong looking type -> "$type") );
    }

    return wantarray ? %{ $hash } : $hash;
}

sub iub_codes_def
{
    # Niels Larsen, October 2011.

    # Creates a hash of ambiguity code definitions. The values
    # are lists of WC bases. 

    # Returns a hash.

    my ( %hash, $key );

    %hash = (
        "R" => "AG",
        "Y" => "TC",
        "M" => "CA",
        "W" => "TA",
        "S" => "CG",
        "K" => "TG",
        "D" => "GTA",
        "H" => "ACT",
        "B" => "GCT",
        "V" => "GCA",
        "N" => "GCAT",
        );

    foreach $key ( keys %hash )
    {
        $hash{ uc $key } = [ split "", $hash{ $key } ];
        $hash{ lc $key } = $hash{ uc $key };
    }

    return wantarray ? %hash : \%hash;
}

sub iub_codes_num
{
    # Niels Larsen, December 2005.
    
    # Creates and returns a hash that returns the IUB ambiguity code that 
    # corresponds to one, two or three concatenated Watson-Crick base number
    # codes. The codes are: A = 0, G = 1, C = 2, T = 3. NOTE: lower case
    # characters in an original alignment will be converted to upper case
    # and U's will be T's. See also &iub_codes_chars which takes characters
    # and respects case and T/U.

    my ( $type,
         ) = @_;

    # Returns a hash.

    my ( $hash, $str, $i );

    if ( not defined $type ) {
        &error( qq (Type is undefined) );
    }

    if ( &Common::Types::is_dna_or_rna( $type ) )
    {
        $hash->{"0"} = "A";
        $hash->{"1"} = "G";
        $hash->{"2"} = "C";
        $hash->{"3"} = "T";
        
        $hash->{"01"} = $hash->{"10"} = "R";
        $hash->{"23"} = $hash->{"32"} = "Y";
        $hash->{"02"} = $hash->{"20"} = "M";
        $hash->{"03"} = $hash->{"30"} = "W";
        $hash->{"12"} = $hash->{"21"} = "S";
        $hash->{"13"} = $hash->{"31"} = "K";
        
        $hash->{"103"} = $hash->{"130"} = "D";
        $hash->{"031"} = $hash->{"013"} = "D";
        $hash->{"301"} = $hash->{"310"} = "D";
        
        $hash->{"032"} = $hash->{"023"} = "H";
        $hash->{"320"} = $hash->{"302"} = "H";
        $hash->{"230"} = $hash->{"203"} = "H";
        
        $hash->{"132"} = $hash->{"123"} = "B";
        $hash->{"321"} = $hash->{"312"} = "B";
        $hash->{"231"} = $hash->{"213"} = "B";
        
        $hash->{"102"} = $hash->{"120"} = "V";
        $hash->{"021"} = $hash->{"012"} = "V";
        $hash->{"201"} = $hash->{"210"} = "V";
        
        $hash->{"0132"} = $hash->{"0123"} = "N";
        $hash->{"0321"} = $hash->{"0312"} = "N";
        $hash->{"0231"} = $hash->{"0213"} = "N";
        
        $hash->{"1032"} = $hash->{"1023"} = "N";
        $hash->{"3021"} = $hash->{"3012"} = "N";
        $hash->{"2031"} = $hash->{"2013"} = "N";
        
        $hash->{"1302"} = $hash->{"1203"} = "N";
        $hash->{"3201"} = $hash->{"3102"} = "N";
        $hash->{"2301"} = $hash->{"2103"} = "N";
        
        $hash->{"1320"} = $hash->{"1230"} = "N";
        $hash->{"3210"} = $hash->{"3120"} = "N";
        $hash->{"2310"} = $hash->{"2130"} = "N";

        if ( &Common::Types::is_rna( $type ) )
        {
            $hash->{"3"} = "U";
        }
    }
    elsif ( &Common::Types::is_protein( $type ) )
    {
        $str = $Alphabets_str_upper{"prot"};
        
        for ( $i = 0; $i < length $str; $i++ )
        {
            $hash->{"$i"} = substr $str, $i, 1;
        }
    }   
    else {
        &error( qq (Wrong looking type -> "$type") );
    }

    return wantarray ? %{ $hash } : $hash;
}

sub locate_agaps
{
    # Niels Larsen, November 2009.

    # Returns a locator list of where the gaps are in a given string or string
    # reference. The numbering is that of the sequence with gaps embedded. If 
    # no gaps, nothing is returned. 

    my ( $seq,     # Sequence string or reference
        ) = @_;

    # Returns list or list reference or nothing.

    my ( $strref, @locs );

    if ( ref $seq ) { $strref = $seq } else { $strref = \$seq };

    while ( ${ $strref } =~ /[-~.]+/og )
    {
        push @locs, [ $-[0]-1, $+[0]-$-[0], (substr ${ $strref }, $-[0], 1) ];
    }

    if ( @locs ) {
        return wantarray ? @locs : \@locs;
    } else {
        return;
    }
}

sub locate_aseqs
{
    # Niels Larsen, November 2009.
    
    # Returns a locator list of where the valid characters are in a given 
    # string or string reference. The numbering is that of the sequence with
    # the non-sequence characters embedded. A type (alphabet name) must be given. 
    # Returns a list or nothing.

    my ( $seq,       # String or string reference
         $type,      # Sequence type
        ) = @_;

    # Returns list or list reference or nothing.

    my ( $strref, $chars, @locs );

    if ( ref $seq ) { $strref = $seq } else { $strref = \$seq };

    $chars = &Seq::Common::alphabet_str( $type );

    while ( ${ $strref } =~ /[$chars]+/og )
    {
        push @locs, [ $-[0], $+[0]-$-[0] ];
    }

    if ( @locs ) {
        return wantarray ? @locs : \@locs;
    } else {
        return;
    }
}

sub locate_nongaps
{
    # Niels Larsen, November 2009.

    # Returns a locator list of where the non-gap characters are in a given 
    # string or string reference. The numbering is that of the sequence with 
    # gaps embedded. If no gaps, a single range is returned. 

    my ( $seq,     # Sequence string or reference
        ) = @_;

    # Returns list or list reference or nothing.

    my ( $strref, @locs );

    if ( ref $seq ) { $strref = $seq } else { $strref = \$seq };

    while ( ${ $strref } =~ /[^-~.]+/og )
    {
        push @locs, [ $-[0], $+[0]-$-[0] ];
    }
    
    if ( not @locs ) {
        @locs = [ 0, length ${ $strref } ];
    }

    return wantarray ? @locs : \@locs;
}

sub locate_sgaps
{
    # Niels Larsen, November 2009.

    # Returns a locator list of where the gaps are in a given string or string
    # reference. The numbering is that of the sequence without gaps embedded. If 
    # no gaps, nothing is returned. 

    my ( $seq,     # Sequence string or reference
        ) = @_;

    # Returns list or list reference or nothing.

    my ( $gaps );

    if ( $gaps = &Seq::Common::locate_agaps( $seq ) )
    {
        $gaps = &Seq::Common::agaps_to_sgaps( $gaps );

        return wantarray ? @{ $gaps } : $gaps;
    }
    
    return;
}

sub match_hash_nuc
{
    my ( $hash, $key );

    $hash = {
        "A" => { "A" => 1, "a" => 1 },
        "U" => { "U" => 1, "u" => 1, "T" => 1, "t" => 1 },
        "G" => { "G" => 1, "g" => 1 },
        "C" => { "C" => 1, "c" => 1 },
        "T" => { "T" => 1, "t" => 1, "U" => 1, "u" => 1 },
    };

    foreach $key ( keys %{ $hash } )
    {
        $hash->{ lc $key } = &Storable::dclone( $hash->{ $key } );
    }

    return wantarray ? %{ $hash } : $hash;
}

sub match_hash_prot
{
    my ( $hash, $key );

    $hash = {
        "G" => { "G" => 1, "g" => 1 },
        "P" => { "P" => 1, "p" => 1 },
        "A" => { "A" => 1, "a" => 1 },
        "V" => { "V" => 1, "v" => 1 },
        "L" => { "L" => 1, "l" => 1 },
        "I" => { "I" => 1, "i" => 1 },
        "M" => { "M" => 1, "m" => 1 },
        "S" => { "S" => 1, "s" => 1 },
        "T" => { "T" => 1, "t" => 1 },
        "N" => { "N" => 1, "n" => 1 },
        "Q" => { "Q" => 1, "q" => 1 },
        "D" => { "D" => 1, "d" => 1 },
        "E" => { "E" => 1, "e" => 1 },
        "C" => { "C" => 1, "c" => 1 },
        "U" => { "U" => 1, "u" => 1 },
        "F" => { "F" => 1, "f" => 1 },
        "Y" => { "Y" => 1, "y" => 1 },
        "W" => { "W" => 1, "w" => 1 },
        "K" => { "K" => 1, "k" => 1 },
        "R" => { "R" => 1, "r" => 1 },
        "H" => { "H" => 1, "h" => 1 },
    };

    foreach $key ( keys %{ $hash } )
    {
        $hash->{ lc $key } = &Storable::dclone( $hash->{ $key } );
    }

    return wantarray ? %{ $hash } : $hash;
}

sub p_bin_selection
{
    # Niels Larsen, December 2009. 

    # Calculates the probability of getting n out of k by random selection 
    # from a pool of two kinds of items. When n and k are small, the binomial
    # coefficient is used, so that factorial overflow is avoided. For larger 
    # n and k approximation to the normal distribution is used (TODO). 

    my ( $k,     # Trials ("number of white balls")
         $n,     # Choices ("total number of balls")
         $p,     # P-trial ("frequency of white balls")
        ) = @_;

    # Returns a number.

    my ( $q, $prob, @mul, @div );

    $p //= 0.25;
    $q = 1 - $p;

    @mul = ( $n-$k+1 .. $n );
    @div = ( 2 .. $k, (1/$p) x $k, (1/$q) x ($n-$k) );

    $prob = 1;

    while ( @div and @mul )
    {
        if ( $prob >= 0 ) {
            $prob /= shift @div;
        } else {
            $prob *= shift @mul;
        }
    }

    map { $prob /= $_ } @div;
    map { $prob *= $_ } @mul;

    return $prob;
}

sub pack_valid_mask
{
    # Niels Larsen, December 2011. 
    
    # Creates a 127 long character mask, where the characters in the 
    # given alphabet are set to 1. The mask is used for some C routines.

    my ( $akey,    # Alphabet name
        ) = @_;

    # Returns a string.

    my ( $mask, $ch );

    $mask = pack "C127", (0) x 127;

    foreach $ch ( split "", $Alphabets_str{ $akey } )
    {
        ( substr $mask, ord $ch, 1 ) = $ch;
    }

    return $mask;
}

sub qual_config
{
    # Niels Larsen, December 2011.

    # For a given type, returns a hash with encoding/decoding formulae 
    # and ascii minimum and maximum values. Without a type, all code
    # names are returned. 

    my ( $type,
         $msgs,
        ) = @_;

    # Returns a hash.

    my ( %codes, $enc, $str, $msg, $msg2 );

    # http://en.wikipedia.org/wiki/FASTQ_format says the often used Solexa
    # (Illumina 1.0) encoding "10 * log10( 1 / ( 1-$pacc ) ) + 64" was a 
    # mistake in the manual and should be Phred + 64, like Illumina_1.3 
    # below. 

    %codes = (
        "Sanger" => {
            "p2ch" => "- 10 * log10( 1 - \$p ) + 33",
            "ch2p" => "10 ** ( ( (ord \$ch) - 33 ) / 10 )",
            "min" => 33,
        },
        "Solexa" => {
            "p2ch" => "- 10 * log10( 1 - \$p ) + 59",
            "ch2p" => "10 ** ( ( (ord \$ch) - 59 ) / 10 )",
            "min" => 59,
        },
        "Illumina_1.3" => {
            "p2ch" => "- 10 * log10( 1 - \$p ) + 64",
            "ch2p" => "10 ** ( ( (ord \$ch) - 64 ) / 10 )",
            "min" => 64,
        },
        "Illumina_1.5" => {
            "p2ch" => "- 10 * log10( 1 - \$p ) + 64",
            "ch2p" => "10 ** ( ( (ord \$ch) - 64 ) / 10 )",
            "min" => 64,
        },
        "Illumina_1.8" => {
            "p2ch" => "- 10 * log10( 1 - \$p ) + 33",
            "ch2p" => "10 ** ( ( (ord \$ch) - 33 ) / 10 )",
            "min" => 33,
        },
        );

    foreach $enc ( values %codes )
    {
        $enc->{"max"} = 126;
    }

    if ( $type )
    {
        if ( $enc = $codes{ $type } )
        {
            return wantarray ? %{ $enc } : $enc;
        }
        else
        {
            $str = join ", ", sort keys %codes;
            $msg = qq (Wrong quality code name -> "$type".);
            $msg2 = qq (Choices are: $str);

            if ( $msgs )
            {
                push @{ $msgs }, ["ERROR", $msg ];
                push @{ $msgs }, ["INFO", $msg2 ];

                return;
            }
            else {
                &error( "$msg\n$msg2" );
            }
        }
    }
    
    return wantarray ? %codes : \%codes;
}

sub qual_config_names
{
    my ( @keys );

    @keys = sort keys %{ &Seq::Common::qual_config() };

    if ( wantarray ) {
        return @keys;
    }

    return join ", ", @keys;
}

sub qual_match
{
    # Niels Larsen, November 2011. 

    # See C function too.

    my ( $qual,     # Quality string
         $mask,     # Minimum qualities list
         $ndcs,     # Index positions to check
        ) = @_;

    # Returns 1 or nothing.

    my ( $ndx );

    foreach $ndx ( @{ $ndcs } )
    {
        return if ( substr $qual, $ndx, 1 ) lt $mask->[$ndx];
    }

    return 1;
}

sub qual_to_qualch
{
    # Niels Larsen, December 2011.

    # Returns the character that corresponds to a given base correctness
    # probability between 0 and 1. For example, the input 0.9975 (1 error 
    # per 400 bases) is converted to "Z". The second argument is one of the 
    # encoding schemes listed on Wikipedias FASTQ format page,
    # http://en.wikipedia.org/wiki/FASTQ_format. This routine uses eval
    # and should not be called in a fast place.

    my ( $p,        # Probability of accuracy
         $enc,      # Encoding entry from &Seq::Common::qual_config
        ) = @_;

    # Returns a character.

    my ( $choices, $ord );
    
    if ( $p < 0.0 or $p > 1.0 ) {
        &error( qq (Quality p-value is $p, should be between 0 and 1) );
    }

    if ( not ref $enc ) {
        $enc = &Seq::Common::qual_config( $enc );
    }

    if ( $p <= 0.0 ) {
        $ord = $enc->{"min"};
    } elsif ( $p >= 1.0 ) {
        $ord = $enc->{"max"};
    } 
    else
    {
        $ord = eval $enc->{"p2ch"}; 

        $ord = &List::Util::max( $enc->{"min"}, $ord );
        $ord = &List::Util::min( $enc->{"max"}, $ord );
    }

    return chr $ord;
}

sub qualch_to_qual
{
    # Niels Larsen, December 2011.

    # Converts a quality character to an accuracy between 0 and 1, using the 
    # given encoding. For example, with "Illumina_1.3" encoding, the character
    # "Z" would be converted to 0.9975. 

    my ( $ch,        # Single character
         $enc,       # Encoding name like "Illumina_1.8"
        ) = @_;

    # Returns integer.

    my ( $ord, $p, $val, $choices, $minch, $maxch );

    $ord = ord $ch;

    if ( $ord < $enc->{"min"} or $ord > $enc->{"max"} )
    {
        $minch = chr $enc->{"min"};
        $maxch = chr $enc->{"max"};
        
        &error( qq (Wrong looking quality character -> "$ch" (ascii $ord)\n)
               .qq (It should be between "$minch" ($val->{"min"}) and "$maxch" ($val->{"max"})\n)
               .qq (Could this be due to a sequence with gaps in?));
    }

    $p = eval $enc->{"ch2p"};

    if ( $p > 0 )
    {
        $p = 1 - 1/$p;

        $p = &List::Util::max( 0, $p );
        $p = &List::Util::min( 1, $p );
    }

    return $p;
}

sub random_seq
{
    # Niels Larsen, November 2009.

    # Returns a reference to a string with a random sequence of a given length
    # and composition. The composition is a list of [ character, number ] where 
    # the numbers mean relative abundance, their absolute values dont matter. 
    # For example [["A",1],["G",2.1]] returns a sequence with A's and G's only,
    # with approximately twice as many G's as A's. An alphabet name can be given
    # instead of a composition list, and then default compositions are used (see
    # the alphabet_freqs routine). The routine is memory inefficient, keep length
    # to kilobases at most. 

    my ( $len,      # Length
         $spec,     # Alphabet or composition list
        ) = @_;

    # Returns string reference.

    my ( $freqs, $freq, $ch, $num, $scale, $seq, $sum, @chars );

    if ( ref $spec ) {
        $freqs = $spec;
    } else {
        $freqs = &Seq::Common::alphabet_freqs( $spec );
    }
    
    $sum = 0;
    map { $sum += $_->[1] } @{ $freqs };

    $scale = $len / $sum;
    $freqs = [ map { $_->[1] *= $scale; $_ } @{ $freqs } ];

    foreach $freq ( @{ $freqs } ) 
    {
        ( $ch, $num ) = @{ $freq };

        push @chars, ($ch) x int $num;
    }

    $seq = join "", &List::Util::shuffle( @chars );
    
    return \$seq;
}

sub repair_id
{
    # Niels Larsen, April 2007.

    # Substitutes non-alphanumeric characters with underscore in a given id,
    # and truncates it if a length is given. Returns new string.
    
    my ( $id,      # ID string
         $len,     # Length - OPTIONAL
        ) = @_;

    # Returns string.

    $id =~ s/[^A-Za-z0-9]/_/g;

    if ( defined $len ) {
        $id = substr $id, 0, $len;
    }

    return $id;
}

sub reverse_locs
{
    # Niels Larsen, November 2009.

    # Given a list of locations and a length, changes the locations as 
    # they would be seen from the opposite end of string of the given 
    # length. 

    my ( $locs,        # Locations list
         $len,         # Length
         ) = @_;

    # Returns a list.

    my ( @locs, $loc, $i_max );

    if ( not $len ) {
        &error( qq(Length must be given) );
    }

    $i_max = $len - 1;

    if ( $locs->[-1]->[0] > $i_max ) {
        &error( qq(Highest index is $locs->[-1]->[0] but given length is $len) );
    }

    $i_max -= 1;   # After-pos becomes before-pos when reversed

    foreach $loc ( @{ $locs } )
    {
        if ( defined $loc ) {
            unshift @locs, [ $i_max - $loc->[0], @{ $loc }[ 1..$#{ $loc } ] ];
        } else {
            unshift @locs, undef;
        }
    }
    
    return \@locs;
}

sub sgaps_to_agaps
{
    # Niels Larsen, November 2009.

    # Converts sequence numbered gap locations to alignment numbering. 
    # No new list copy is made, ie the input list is modified. Returns an
    # updated list.

    my ( $gaps,    # Gap locations
        ) = @_;

    # Returns list.

    my ( $gap, $gapsum );

    $gapsum = 0;

    foreach $gap ( @{ $gaps } )
    {
        $gap->[0] += $gapsum;
        $gapsum += $gap->[1];
    }

    return wantarray ? @{ $gaps } : $gaps;
}

sub spos_to_apos
{
    # Niels Larsen, September 2009.

    # Converts a number in a given aligned sequence to its alignment
    # column number. 

    my ( $seq,    # Sequence with gaps
         $pos,    # Sequence position
        ) = @_;

    # Returns integer. 

    my ( $mul );

    $mul = $pos + 1;

    if ( $seq->{"seq"} =~ /([^A-Za-z]*[A-Za-z]){$mul}/ )
    {
        return $+[0] - 1;
    }

    return;
}

sub sub_locs
{
    # Niels Larsen, October 2009.

    # Returns parts of a locations list given by a list of indices. 

    my ( $locs,   # Locator list
         $ndcs,   # Indices into locator list
        ) = @_;

    # Returns a list.
    
    my ( @locs, $ndx, $maxndx, $minndx );

    $maxndx = $#{ $locs };

    foreach $ndx ( @{ $ndcs } )
    {
        if ( $ndx >= 0 and $ndx <= $maxndx )
        {
            push @locs, $locs->[$ndx];
        }
        else {
            &error( qq(Index $ndx should be between 0 and $maxndx) );
        }
    }

    return wantarray ? @locs : \@locs;
}

sub sub_str
{
    # Niels Larsen, October 2009.

    # Given a string or string reference and a locations list or string, 
    # creates a substring. The locations are always in the numbering of
    # the given string. Returns a substring reference.

    my ( $str,           # String
         $locs,          # Locations list or string
         $comp,          # Complement '-' locators or not - OPTIONAL
        ) = @_;
    
    # Returns a string.

    my ( $strref, $substr, $loc, $locstr, $pos, $len, $strand );

    # Ensure $locs are a list of [ beg, end ],
    
    if ( ref $str ) { $strref = $str } else { $strref = \$str };

    if ( $locs ) {
        $locs = &Seq::Common::parse_loc_str( $locs ) if not ref $locs;
    } else {
        &error("No locations given");
    }

    $substr = "";

    foreach $loc ( @{ $locs } )
    {
        if ( defined $loc )
        {
            ( $pos, $len, $strand ) = @{ $loc };

            if ( defined $len ) {
                $locstr = substr ${ $strref }, $pos, $len;
            } else {
                $locstr = substr ${ $strref }, $pos;
            }                
            
            if ( $comp and defined $strand and $strand eq "-" ) {
                $substr .= ${ &Seq::Common::complement_str( \$locstr ) };
            } else {
                $substr .= $locstr;
            }
        }
    }

    return \$substr;
}

sub subtract_locs
{
    # Niels Larsen, October 2009.

    # Subtract locator positions from a given value. This can be useful for
    # translating numbers to start from the end of the sequence for example.
    # Returns an updated location list reference.

    my ( $locs,
         $decr,
         ) = @_;

    # Returns a list reference.

    my ( $loc );

    foreach $loc ( @{ $locs } )
    {
        if ( defined $loc ) {
            $loc->[0] = $decr - $loc->[0];
        }
    }

    return wantarray ? @{ $locs } : $locs;
}

sub validate_gaps
{
    # Niels Larsen, November 2009.

    # Checks that all gap characters in a locator list is part of the gap
    # alphabet. Crashes if something wrong in void context, in non-void 
    # returns a list of messages. More checks to be added. 

    my ( $gaps,      # Gap locator list
        ) = @_;

    # Returns nothing.
    
    my ( $ch, @msgs );

    foreach $ch ( map { $_->[2] } @{ $gaps } )
    {
        if ( $ch !~ /^[-~.]$/ ) {
            push @msgs, qq (Unacceptable gap character -> "$ch", it must be one of -> "-~.");
        }
    }
    
    if ( defined wantarray ) {
        return wantarray ? @msgs : \@msgs;
    } else {
        &error( join "\n", @msgs );
    }
    
    return;
}

1;

__DATA__

__C__

int change_by_quality_C( char* seq, char* qual, char seqch, char qmin, char qmax, int len )
{
    /*
        Niels Larsen, January 2012.

        Replaces sequence characters that have a quality value within the 
        given range.

        Returns integer. 
    */

    int pos, count;

    count = 0;

    for ( pos = 0; pos < len; pos++ )
    {
        if ( qual[pos] >= qmin && qual[pos] <= qmax )
        {
            seq[pos] = seqch;
            count++;
        }
    }

    return count;
}

static void* get_ptr( SV* obj ) { return SvPVX( obj ); }

void char_stats_C( char* string, SV* stats, int beg, int len )
{
    /*
        Niels Larsen, December 2011.

        Counts the number of characters in the given string. The counts
        are put into the second argument, which for each ASCII value 
        holds the number of characters seen. The count starts at beg and
        ends at beg + len - 1. 
        
        Returns nothing. 
    */

    int* counts = get_ptr( stats );
    int pos;

    for ( pos = beg; pos < beg + len; pos++ ) 
    {
        counts[ string[pos] ]++; 
    }

    return;
}

int count_chars_invalid_C( char* str, int slen, int wlen, char* valid )
{
    /*
        Niels Larsen, December 2011.

        Counts the number of characters in the given string (str) of 
        lenth slen, where the first wlen corresponding ASCII values 
        are not set in the given mask (valid).
        
        Returns integer. 
    */

    int pos, len;
    float count;

    if ( slen > wlen ) {
        len = wlen;
    } else {
        len = slen;
    }

    count = 0;

    for ( pos = 0; pos < len; pos++ )
    {
        if ( ! valid[ str[pos] ] )
        {
            count++;
        }
    }

    return count;
}

float count_chars_valid_C( char* str, int slen, int wlen, char* valid )
{
    /*
        Niels Larsen, December 2011.

        Counts the number of characters in the given string (str) of 
        lenth slen, where the first wlen corresponding ASCII values 
        are set in the given mask (valid).
        
        Returns integer. 
    */

    int pos, len;
    float count;

    if ( slen > wlen ) {
        len = wlen;
    } else {
        len = slen;
    }

    count = 0;

    for ( pos = 0; pos < len; pos++ )
    {
        if ( valid[ str[pos] ] )
        {
            count++;
        }
    }

    return count / len;
}

int count_quals_min_C( char* str, int beg, int len, char min )
{
    /*
        Niels Larsen, December 2011.

        Counts the number of characters in the given string with an ASCII
        value of at least min. The count is started at beg and ends at 
        beg + len - 1.
        
        Returns integer. 
    */

    int pos, count;

    count = 0;

    for ( pos = beg; pos < beg + len; pos++ )
    {
        if ( str[pos] >= min )
        {
            count++;
        }
    }

    return count;
}

int count_quals_min_max_C( char* str, int beg, int len, char min, char max )
{
    /*
        Niels Larsen, December 2011.

        Counts the number of characters in the given string with an ASCII
        value of at least min and at most max. The count is started at beg
        and ends at beg + len - 1.
        
        Returns integer. 
    */

    int pos, count;

    count = 0;

    for ( pos = beg; pos < beg + len; pos++ )
    {
        if ( str[pos] >= min && str[pos] <= max )
        {
            count++;
        }
    }

    return count;
}

int count_similarity_beg_C( char* seq, char* prb, int prbmax, int seqpos, int offmax )
{
    /*
        Niels Larsen, December 2011.

        Returns integer. 
    */

    int off, hits;
    
    hits = 0;

    for ( off = 0; off <= offmax; off++ )
    {
        if ( seq[ seqpos - off ] == prb[ prbmax - off ] )
        {
            hits++;
        }
    }

    return hits;
}

int count_similarity_end_C( char* seq, char* prb, int seqbeg, int matlen )
{
    /*
        Niels Larsen, December 2011.

        Returns integer. 
    */

    int seqpos, prbpos, hits;
    
    prbpos = 0;
    hits = 0;

    for ( seqpos = seqbeg; seqpos <= seqbeg + matlen - 1; seqpos++ )
    {
        if ( seq[ seqpos ] == prb[ prbpos++ ] )
        {
            hits++;
        }
    }

    return hits;
}

int find_overlap_beg_C( char* seq, char* prb, int dist, float misrat, int minlen )
{
    /*
        Niels Larsen, February 2012.

        Returns the index of the end of the longest match between the 
        beginning of a sequence (seq) and the end of a probe sequence
        (prb). The (dist) argument specifies how long into the sequence
        to look for matches. With (minlen) a minimum match length can 
        be set, and (misrat) is the ratio between that length and the 
        number of mismatches. If (misrat) is 0.1 for example, then at 
        most 10% mismatches are tolerated. No score matrix is accepted
        but upper case N's match anything. The logic starts with the
        longest possible overlap and then slides the probe sequence 
        towards less and less overlap (towards the left below):

                012345678901234
                AACATTATTCTCGGG     Sequence
        <- ATTCTAACA                Probe     (returns 3)
               <- CATTATTC          Probe     (returns 9)

        If (dist) is 9 in this example, then the second match is not 
        found, since it involves the 10th position. Non-matches
        return -1.
    */
    
    int seqlen, prblen, seqmin, maxpos, maxlen, seqpos, seqmax;
    int hits, miss, mismat, i, prbpos, prbmax, maxmis;

    seqlen = strlen( seq );
    prblen = strlen( prb );

    if ( dist <= seqlen ) {
        seqmax = dist - 1;
    } else {
        seqmax = seqlen - 1;
    }
    
    prbmax = prblen - 1;

    maxpos = -1;
    maxlen = 0;

    // printf("dist, minlen, misrat = %d, %d, %f\n", dist, minlen, misrat );

    for ( seqpos = seqmax; seqpos >= 0; seqpos-- )
    {
        if ( seqpos <= prbmax ) {
            seqmin = 0;
        } else {
            seqmin = seqpos - prbmax;
        }

        hits = 0;
        miss = 0;

        prbpos = prbmax;        
        maxmis = misrat * ( seqpos - seqmin + 1 );

        // printf("misrat, maxmis, len = %f, %d, %d\n", misrat, maxmis, seqpos-seqmin+1 );
        
        for ( i = seqpos; i >= seqmin; i-- )
        {
            if ( seq[i] == 78 || seq[i] == prb[prbpos] )
            {
                hits++;
            }
            else
            {
                miss++;

                if ( miss > maxmis ) {
                    break;
                }
            }

            prbpos--;
        }

        // printf("hits, miss, maxmis, maxlen = %d, %d, %d, %d\n", hits, miss, maxmis, maxlen );
        
        if ( miss <= maxmis && hits > maxlen )
        {
            maxlen = hits;
            maxpos = seqpos;
            break;
        }
    }
    
    // printf("minlen, maxlen = %d, %d\n", minlen, maxlen );

    if ( maxlen < minlen ) {
        maxpos = -1;
    }
    
    return maxpos;
}

int find_overlap_end_C( char* seq, char* prb, int dist, float misrat, int minlen )
{
    /*
      Niels Larsen, February 2012.

      Returns the index of the beginning of the longest match between the 
      end of a target sequence (seq) and the beginning of a probe sequence
      (prb). The (dist) argument specifies how long into the target to look
      for matches. With (minlen) a minimum match length can 
      be set, and (misrat) is the ratio between that length and the 
      number of mismatches. If (misrat) is 0.1 for example, then at 
      most 10% mismatches are tolerated. No score matrix is accepted
      but upper case N's match anything. The logic starts with the
      longest possible overlap and then slides the probe sequence 
      towards less and less overlap (towards the right below):
      
        012345678901234
        AACATTATTCTCGGG         Target sequence
              ATTCTCG ->        Probe example 1     (returns 6)
                    GGGCTCG ->  Probe example 2     (returns 12)
              
      If (dist) is 8 or less in this example, then the first match 
      is not found, since it involves the 9th position. Non-matches 
      return -1.
    */

    int seqlen, prblen, seqmin, maxpos, maxlen, seqpos, seqmax;
    int hits, miss, mismat, i, prbpos, maxmis;

    seqlen = strlen( seq );
    prblen = strlen( prb );

    if ( dist <= seqlen ) {
        seqmin = seqlen - dist;
    } else {
        seqmin = 0;
    }
    
    maxpos = -1;
    maxlen = 0;

    // printf("dist, minlen, misrat = %d, %d, %f\n", dist, minlen, misrat );

    for ( seqpos = seqmin; seqpos < seqlen; seqpos++ )
    {
        if ( seqlen - seqpos < prblen ) {
            seqmax = seqlen;
        } else {
            seqmax = seqpos + prblen;
        }

        hits = 0;
        miss = 0;

        prbpos = 0;
        maxmis = misrat * ( seqmax - seqpos );

        // printf("misrat, maxmis = %f, %d\n", misrat, maxmis );
        // exit;

        for ( i = seqpos; i < seqmax; i++ )
        {
            if ( seq[i] == 78 || seq[i] == prb[prbpos] )
            {
                hits++;
            }
            else
            {
                miss++;

                if ( miss > maxmis ) {
                    break;
                }
            }

            prbpos++;
        }

        if ( miss <= maxmis && hits > maxlen )
        {
            maxlen = hits;
            maxpos = seqpos;
            break;
        }
    }
    
    if ( maxlen < minlen ) {
        maxpos = -1;
    }
    
    return maxpos;
}

int join_seq_pairs_C( char* seq1, char* qual1, int pos1,
                      char* seq2, char* qual2, 
                      char* seq, char* qual )
{
    /*
      Niels Larsen, February 2013.

      Writes two pieces of sequence into one longer sequence, used when
      combining paired reads. The position where seq2 starts in seq1 is 
      given (other routines find this position) as pos1. Where the two 
      sequences overlap, the best quality base is taken from each and 
      written into the single output sequence and its quality. Length
      of the new sequence is returned.       
    */

    int len1, len2, i1, i2, i, len;

    len1 = strlen( seq1 );
    len2 = strlen( seq2 );

    /* 
       Copy the part of sequence 1 not covered by sequence 2
    */

    i = 0;

    for ( i1 = 0; i1 < pos1; i1 += 1 )
    {
        seq[i] = seq1[i1];
        qual[i] = qual1[i1];

        i += 1;
    }

    /*
      Copy the overlapping part. Take the best qualities from each, with
      their respective bases.
    */

    if ( pos1 + len2 > len1 ) {
        len = len1;
    } else {
        len = pos1 + len2;
    }

    i2 = 0;

    for ( i1 = pos1; i1 < len; i1 += 1 )
    {
        if ( qual1[i1] > qual2[i2] ) 
        {
            seq[i] = seq1[i1];
            qual[i] = qual1[i1];
        }
        else
        {
            seq[i] = seq2[i2];
            qual[i] = qual2[i2];
        }

        i2 += 1;
        i += 1;
    }

    /* 
       Copy the overhangs. If seq2 is longer, then copy that, otherwise copy
       the seq1 overhang if any.
    */
    
    if ( pos1 + len2 > len1 )
    {
        while ( i2 < len2 )
        {
            seq[i] = seq2[i2];
            qual[i] = qual2[i2];
            
            i2 += 1;
            i += 1;
        }
    }
    else
    {
        while ( i1 < len1 )
        {
            seq[i] = seq1[i1];
            qual[i] = qual1[i1];
            
            i1 += 1;
            i += 1;
        }
    }

    return i;
}

int trim_beg_qual_pos_C( char* str, int slen, char cmin, int wlen, int wmin )
{
    /*
      Niels Larsen, December 2011.
      
      Returns the number of characters that should be trimmed from the start
      of the given string. A window of a given length (wlen) is moved from the
      start one step at a time until it reaches a good enough stretch. Good 
      enough means having at least a given number of characters (wmin) above
      a certain ASCII value (cmin) within the window (wlen). Trailing low 
      quality bases are skipped, i.e. trimmed. Returns the number of 
      characters to be removed, which is then done in Perl. 
      
      Returns integer. 
    */

    int leadpos, tailpos, i, sum, maxpos;
    
    maxpos = slen - 1;

    /* Initialize sum of better-than-required characters */

    leadpos = 0;
    sum = 0; 

    for ( i = 0; i < wlen; i++ )
    {
        if ( str[leadpos++] >= cmin ) {
            sum++;
        }
    }

    /* Move window and update sum while incrementing trimlen */

    tailpos = 0;

    while ( leadpos <= maxpos && sum < wmin )
    {
        if ( str[leadpos++] >= cmin ) {
            sum++;
        }

        if ( str[tailpos++] >= cmin ) {
            sum--;
        }
    }

    /* Skip trailing low quality positions */

    tailpos--;

    while ( tailpos <= maxpos && str[tailpos] < cmin )
    {
        tailpos++;
    };

    return tailpos;
}

int trim_end_qual_pos_C( char* str, int slen, char cmin, int wlen, int wmin )
{
    /*
      Niels Larsen, December 2011.
      
      Returns the number of characters that should be trimmed from the end
      of the given string. A window of a given length (wlen) is moved from the
      end one step at a time until it reaches a good enough stretch. Good 
      enough means having at least a given number of characters (wmin) above
      a certain ASCII value (cmin) within the window (wlen). Trailing low 
      quality bases are skipped, i.e. trimmed. Returns the number of 
      characters to be removed, which is then done in Perl.
      
      Returns integer. 
    */

    int leadpos, tailpos, i, sum, minsum;
    
    /* Initialize sum of better-than-required characters */

    leadpos = slen - 1;
    sum = 0;

    for ( i = 0; i < wlen; i++ )
    {
        if ( str[leadpos--] >= cmin ) {
            sum++;
        }
    }

    /* Move window and update sum while incrementing trimlen */

    tailpos = slen - 1;

    while ( leadpos >= 0 && sum < wmin )
    {
        if ( str[leadpos--] >= cmin ) {
            sum++;
        }

        if ( str[tailpos--] >= cmin ) {
            sum--;
        }
    }

    /* Skip trailing low quality positions */

    tailpos++;

    while ( tailpos >= 0 && str[tailpos] < cmin )
    {
        tailpos--;
    }

    return slen - tailpos - 1;
}

__END__

# int check_quals_min_C( char* str, int beg, int len, char min )
# {
#     /*
#         Niels Larsen, December 2011.
               
#         Returns integer. 
#     */

#     int pos, count;

#     count = 0;

#     for ( pos = beg; pos < beg + len; pos++ )
#     {
#         if ( str[pos] < min ) {
#             return;
#         } else {
#             count++;
#         }
#     }

#     return count;
# }

# sub qual_mask
# {
#     # Niels Larsen, December 2009.

#     # Adds or overwrites a "mask" field string with 0's and 1's. The 1's are 
#     # set where residues are above a given minimum. Returns an updated object. 

#     my ( $self,
#          $qmin,     # Minimum quality
#         ) = @_;

#     # Returns hash or object.

#     my ( $quals, $qual, $i );

#     if ( exists $self->{"qual"} ) {
#         $self->{"mask"} = 0 x (length $self->{"qual"});
#     } else {
#         &error( qq (No qualities for "$self->{'id'}") );
#     }

#     # TODO: load as globals or state
#     $quals = &Seq::Common::qualstr_to_quals( \$self->{"qual"} );

#     for ( $i = 0; $i <= $#{ $quals }; $i++ )
#     {
#         if ( $quals->[$i] >= $qmin ) {
#             (substr $self->{"mask"}, $i, 1) = 1;
#         }
#     }

#     return $self;
# }


# sub info_from_id
# {
#     # Niels Larsen, April 2010.

#     # 

#     my ( $self,
#          $exps,
#          $over,
#         ) = @_;

#     my ( @info, $elem, $key, $exp );

#     $over //= 1;

#     foreach $elem ( @{ $exps } )
#     {
#         if ( ref $elem )
#         {
#             ( $key, $exp ) = @{ $elem };

#             $self->{"id"} =~ /$exp/;
#             push @info, [ $key, $1 // "" ] if defined $1;
#         }
#         elsif ( $self->{"id"} =~ /$elem/ ) {
#             push @info, [ $1, $2 ];
#         }           
#     }

#     if ( $over ) {
#         $self->{"info"} = join "; ", map { "$_->[0]=$_->[1]" } @info;
#     } else {
#         $self->{"info"} //= "";
#         $self->{"info"} .= join "; ", map { "$_->[0]=$_->[1]" } @info;
#     }

#     return $self;
# }

# sub str_stats
# {
#     # Niels Larsen, November 2009.

#     # Creates a list of [ character, count ] for each character in a 
#     # given list. A location list can be given to bring out statistics
#     # from just those locations. If the fourth argument is true upper-
#     # and lower-case are pooled, otherwise not.

#     my ( $str,    # String or string reference
#          $chars,  # List of characters
#          $locs,   # Location list - OPTIONAL, default all
#          $case,   # List case separately - OPTIONAL, default false
#         ) = @_;

#     # Returns a list.

#     my ( $strref, @stats, $ch, $count, $lch );

#     if ( ref $str ) { $strref = $str } else { $strref = \$str };

#     if ( defined $locs ) {
#         $strref = &Seq::Common::sub_str( $strref, $locs );
#     }

#     if ( $case )
#     {
#         foreach $ch ( @{ $chars } ) 
#         {
#             $ch = quotemeta $ch;
#             eval qq(\$count = \${ \$strref } =~ tr/$ch/$ch/);
            
#             if ( $count > 0 ) {
#                 push @stats, [ $ch, $count ];
#             }
#         }
#     }
#     else
#     {
#         foreach $ch ( map { uc $_ } @{ $chars } )
#         {
#             $ch = quotemeta $ch;
#             $lch = lc $ch;
#             eval qq(\$count = \${ \$strref } =~ tr/$ch$lch/$ch$lch/);
            
#             if ( $count > 0 ) {
#                 push @stats, [ $ch, $count ];
#             }
#         }
#     }
    
#     return wantarray ? @stats : \@stats;
# }

# sub sub_list
# {
#     # Niels Larsen, February 2010.

#     # Given a string or string reference and a locations list or string, 
#     # creates a list of substrings. The locations are always in the numbering
#     # of the given string. Returns a list reference.

#     my ( $str,           # String
#          $locs,          # Locations list or string
#         ) = @_;
    
#     # Returns a list reference.

#     my ( $strref, @sublist, $loc, $pos, $len );

#     # Ensure $locs are a list of [ beg, end ],

#     if ( ref $str ) { $strref = $str } else { $strref = \$str };

#     if ( $locs ) {
#         $locs = &Seq::Common::parse_loc_str( $locs ) if not ref $locs;
#     } else {
#         &error("No locations given");
#     }

#     @sublist = ();

#     foreach $loc ( @{ $locs } )
#     {
#         if ( defined $loc )
#         {
#             ( $pos, $len ) = @{ $loc };
#             push @sublist, substr ${ $strref }, $pos, $len;
#         }
#     }

#     return \@sublist;
# }

# sub qual_stats
# {
#     # Niels Larsen, December 2009.

#     # Returns a list of [ character, count ] for the qualities. If locations
#     # are given then only characters in those regions are counted. The order
#     # of the returned list is that of the sequence's alphabet. 

#     my ( $self,
#          $locs,   # Locations list - OPTIONAL
#         ) = @_;

#     # Returns a list.

#     my ( $imax, $strref, %stats, @stats, $ch, $i );

#     if ( not exists $self->{"qual"} ) {
#         &error( qq(Sequence has no quality -> "$self->{'id'}") );
#     }

#     if ( defined $locs ) {
#         $strref = &Seq::Common::sub_str( \$self->{"qual"}, $locs );
#     } else {
#         $strref = \$self->{"qual"};
#     }
    
#     $imax = (length ${ $strref }) - 1;
    
#     for ( $i = 0; $i <= $imax; $i++ ) {
#         $stats{ substr ${ $strref }, $i, 1 } += 1;
#     }
    
#     foreach $ch ( @{ $Alphabets{"qual"} } )
#     {
#         if ( exists $stats{ $ch } ) {
#             push @stats, [ $ch, $stats{ $ch } ];
#         }
#     }

#     return wantarray ? @stats : \@stats;
# }
