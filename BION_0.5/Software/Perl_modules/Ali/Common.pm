package Ali::Common;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# This module provides methods, functions and accessors for single alignment 
# objects. Perl Data Language (PDL, see http://pdl.perl.org) is used hroughout,
# because of its speed and memory savings, and support for slices. The downside
# is one must know PDL to grow this library (but not to use it of course).
#
# An alignment is defined as an object, a hash where two mandatory fields are
#
# sids => a byte PDL with dimensions 20 x (alignment rows)
# seqs => a byte PDL with dimensions (max. seq. length) x (alignment rows)
#
# In addition there are various optional fields, timestamp, which file it 
# came from, which original positions a slice came from, etc. All indices are 
# zero-based, except when on file or when presented to the user.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use feature "state";

{
    local $SIG{__DIE__} = undef;

    require PDL::Lite;
    require PDL::Char;
    require PDL::IO::FastRaw;
#    require PDL::IO::FlexRaw;
};

use Common::Config;
use Common::Messages;

use File::Basename;
use Time::Local;

use Common::File;
use Common::Util;

use Seq::Common;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> BION DEPENDENCY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# The &error function is exported from the Common::Messages module if 
# if part of Genome Office, i.e. if the shell environment BION_HOME 
# is set. If not, the &error function uses plain confess,

BEGIN
{
    if ( $ENV{"BION_HOME"} ) {
        eval qq (use Common::Messages);
    } else {
        eval qq (use Carp; sub error { confess("Error: ". (shift) ."\n") });
    }
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our ( @Fields, @Methods, @Functions, @PDL_fields,
      %Fields, %Methods, %Functions, %PDL_fields );

# Set allowed fields,

&_init_globals();

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Methods that outside callers can use. Each operate on an alignment object,
# most return an updated object (but some a list or plain value), 

@Methods = (
    [ "add_padding",             "Makes ids and sequences have same string lengths" ],
    [ "alphabet",                "Allowed sequence characters, as string" ],
    [ "alphabet_stats",          "Sequence characters for statistics, as string" ],
    [ "alphabet_paint",          "Sequence characters for painting, as string" ],
    [ "copy",                    "Copies an alignment object" ],
    [ "de_pdlify",               "Converts from PDL to string represenation" ],
    [ "global_col",              "Returns original column index for a given column index" ],
    [ "global_cols",             "" ],
    [ "global_row",              "Returns original row index for a row index" ],
    [ "global_rows",             "" ],
    [ "grep_ids",                "" ],
    [ "is_chimeric",             "" ],
    [ "is_gap_col",              "True if column contains only gaps" ],
    [ "is_gap_row",              "True if row contains only gaps" ],
    [ "is_match_hash",           "" ],
    [ "is_pdl",                  "" ],
    [ "local_col",               "Local column of original column index" ],
    [ "local_cols",              "List of global -> local column numbers" ],
    [ "local_row",               "Local row of original row index" ],
    [ "local_rows",              "List of global -> local row numbers" ],
    [ "max_col",                 "Max. data column index of current alignment" ],
    [ "max_col_global",          "Max. data column index in original numbering" ],
    [ "max_row",                 "Max. data row index of current alignment" ],
    [ "max_row_global",          "Max. data row index in original numbering" ],
    [ "min_col_global",          "Min. data column index in original numbering" ],
    [ "min_row_global",          "Min. data row index in original numbering" ],
    [ "new",                     "Creates a new alignment object" ],
    [ "parse_fasta",             "Parses fasta alignment string, one-line sequence" ],
    [ "parse_fasta_wrapped",     "Parses fasta alignment string" ],
    [ "parse_locators",          "Parses a list of string locators" ],
    [ "parse_uclust",            "Parses uclust alignment string" ],
    [ "pdlify",                  "Converts from string representation to PDL" ],
    [ "replace_char",            "Replaces a given character with another in the sequences" ],
    [ "remove_gaps",             "" ],
    [ "seq_beg",                 "" ],
    [ "seq_begs",                "" ],
    [ "seq_end",                 "" ],
    [ "seq_ends",                "" ],
    [ "seq_count",               "" ],
    [ "seq_string",              "Returns a given sequence as string" ],
    [ "seq_string_ref",          "Returns a given sequence as string reference" ],
    [ "seq_to_ali_pos",          "Returns local column index of sequence position" ],
    [ "sid_len",                 "Length of short-id field" ],
    [ "sid_string",              "Returns a given short-id as string" ],
    [ "sids_list",               "Returns all short-ids as a list" ],
    [ "subali_at",               "Extracts specified subalignment around given (col,row) position" ],
    [ "subali_center",           "Like subali_at, but fewer arguments" ],
    [ "subali_down",             "Scrolls down, includes all columns" ],
    [ "subali_down_cols",        "Scrolls down, includes only given columns" ],
    [ "subali_left",             "Scrolls left" ],
    [ "subali_get",              "Creates new sub-alignment by cutting rows and/or columns" ],
    [ "subali_right",            "Scrolls right" ],
    [ "subali_up",               "Scrolls up, includes all columns" ],
    [ "subali_up_cols",          "Scrolls up, includes only given columns" ],
    [ "time",                    "Sets or gets the current epoch time" ],
    [ "to_dna",                  "" ],
    [ "to_rna",                  "" ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

@Functions = (
    [ "default_params",          "Gets default parameters for several routines" ],
    );

# >>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD ACCESSORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub _init_globals
{
    @PDL_fields = qw( sids seqs begs ends nums );

    @Fields = qw (
     id sid title file source datatype name desc time info
     sid_cols beg_cols end_cols dat_cols 
     orig_acc orig_ali orig_colbeg orig_colend orig_rowbeg orig_rowend 
     ft_locs ft_options features pairmasks authors url image margins clipping 
     );

    push @Fields, @PDL_fields;
    
    %Fields = map { $_, 1 } @Fields;
    %PDL_fields = map { $_, 1 } @PDL_fields;

    return;
}

sub AUTOLOAD
{
    # Niels Larsen, November 2009.
    
    # Creates missing accessors.
    
    &_new_accessor( @_ );
}

sub _new_accessor
{
    # Niels Larsen, May 2007.

    # Creats a get/setter method if 1) it is not already defined (explicitly
    # or by this routine) and 2) its name are among the keys in the hash given.
    # Attempts to use methods not in @Fields will trigger a crash with 
    # trace-back.

    my ( $ali,         # Alignment object 
         ) = @_;

    # Returns nothing.

    our $AUTOLOAD;
    my ( $field, $pkg, $code, $str );

    caller eq __PACKAGE__ or &error( qq (May only be called from within ). __PACKAGE__ );

    # Isolate name of the method called and the object package (in case it is
    # not this package),

    return if $AUTOLOAD =~ /::DESTROY$/;

    $field = $AUTOLOAD;
    $field =~ s/.*::// ;

    $pkg = ref $ali;

    # Create a code string that defines the accessor and crashes if its name 
    # is not found in the object hash,

    $code = qq
    {
        package $pkg;
        
        sub $field
        {
            my \$ali = shift;
            
            if ( exists \$Fields{"$field"} )
            {
                \@_ ? \$ali->{"$field"} = shift : \$ali->{"$field"};
            } 
            else
            {
#                local \$Common::Config::with_stack_trace;
#                \$Common::Config::with_stack_trace = 0;

                &error( "Wrong looking accessor -> \$field", "PROGRAMMER ERROR" );
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


# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_padding
{
    # Niels Larsen, May 2011.

    # Adds padding to all or select fields in a non-PDL alignment, so that for 
    # example sequence strings all have the same lengths. Only touches fields 
    # whose values are lists.     

    my ( $ali,        # Alignment
         $keys,       # Which fields to be padded - OPTIONAL, default all
         ) = @_;

    # Returns alignment object.

    my ( $maxlen, $lens_uniq, $lens, $rows, $i, $field, $pad_chars, 
         $pad_sides, $pad_str, @fields );
    
    $pad_chars = {
        "sids" => "\0",
        "seqs" => "-",
        "begs" => " ",
        "ends" => " ",
        "nums" => " ",
    };

    $pad_sides = {
        "sids" => "right",
        "seqs" => "right",
        "begs" => "left",
        "ends" => "right",
        "nums" => "left",
    };

    if ( defined $keys ) {
        @fields = @{ $keys };
    } else {
        @fields = @PDL_fields;
    }

    foreach $field ( @fields )
    {
        next if not exists $pad_chars->{ $field };

        if ( ref ( $rows = $ali->$field ) eq "ARRAY" )
        {
            $lens = [ map { length $_ } @{ $rows } ];
            $lens_uniq = &Common::Util::uniqify( $lens );

            if ( scalar @{ $lens_uniq } > 1 )
            {
                $maxlen = &List::Util::max( @{ $lens_uniq } );

                $pad_str = $pad_chars->{ $field } x $maxlen;

                if ( $pad_sides->{ $field } eq "right" )
                {
                    for ( $i = 0; $i <= $#{ $rows }; $i ++ )
                    {
                        if ( $lens->[$i] < $maxlen ) {
                            $rows->[$i] .= substr $pad_str, 0, $maxlen - $lens->[$i];
                        }
                    }
                }
                else
                {
                    for ( $i = 0; $i <= $#{ $rows }; $i ++ )
                    {
                        if ( $lens->[$i] < $maxlen ) {
                            $rows->[$i] = ( substr $pad_str, 0, $maxlen - $lens->[$i] ) . $rows->[$i];
                        }
                    }
                }
            }
        }
    }

    return $ali;
}

sub alphabet
{
    # Niels Larsen, July 2010.
    
    # Returns a string of valid chracters for a given alignment or type.

    my ( $ali,        # Alignment object or type string
         ) = @_;

    # Returns string.

    my ( $type, $str );

    if ( ref $ali ) {
        $type = $ali->datatype;
    } else {
        $type = $ali;
    }

    if ( $type )
    {
        if ( &Common::Types::is_rna( $type ) ) {
            $str = "AGCUagcu-.~";
        } elsif ( &Common::Types::is_dna( $type ) ) {
            $str = "AGCTagct-.~";
        } elsif ( &Common::Types::is_protein( $type ) ) {
            $str = "GAVLISTDNEQCUMFYWKRHPgavlistdneqcumfywkrhp-.~";
        } else {
            &error( qq (Wrong looking type -> "$type") );
        }
    }
    else {
        &error( qq (Type is undefined) );
    }

    return $str;
}

sub alphabet_stats
{
    my ( $ali,
        ) = @_;

    my ( $str );

    $str = &Ali::Common::alphabet( $ali );
    $str =~ s/[a-z]//g;

    if ( (length $str) < 20 ) {
        $str =~ s/(U|T)/$1N/;
    }

    return $str;
}

sub alphabet_paint
{
    my ( $ali,
        ) = @_;

    my ( $str );

    $str = &Ali::Common::alphabet( $ali );
    $str =~ s/[-\.~]//g;

    return $str;
}

sub beg_string
{
    # Niels Larsen, July 2007.

    # Returns the begin number string for a given row. 

    my ( $ali,       # Alignment
         $row,       # Row index
         ) = @_;

    # Returns a string.

    return ${ $ali->begs->slice(":,($row)")->get_dataref };
}

sub copy
{
    # Niels Larsen, June 2005. 

    # Creates a new copy of an alignment, optionally without 
    # connection to file. 

    my ( $ali,         # Alignment
         $sever,       # Cut connection to file, OPTIONAL - default 0
         ) = @_;

    # Returns an alignment object. 

    my ( $copy, $key );

    $sever = 0 if not defined $sever;

    if ( $sever )
    {
        foreach $key ( keys %{ $ali } )
        {
            if ( ref $copy->{ $key } eq "PDL" ) {
                $copy->{ $key } = $ali->{ $key }->sever;
            } else {
                $copy->{ $key } = $ali->{ $key };
            }                
        }
    }
    else
    {
        foreach $key ( keys %{ $ali } )
        {
            $copy->{ $key } = $ali->{ $key };
        }
    }

    $copy = Ali::Common->new( %{ $copy } );
    
    return $copy;
}

sub defined
{
    my ( $ali,
        ) = @_;

    my ( $cols, $rows );

    ( $cols, $rows ) = ( $ali->seqs->dims );

    return 1 if $cols >= 1 and $rows >= 1;

    return;
}
    
sub end_string
{
    # Niels Larsen, July 2007.

    # Returns the end number string for a given row. 

    my ( $ali,       # Alignment
         $row,       # Row index
         ) = @_;

    # Returns a string.

    return ${ $ali->ends->slice(":,($row)")->get_dataref };
}

sub global_col
{
    # Niels Larsen, July 2005.

    # Returns the original column index of a given column. For example
    # when a set of columns is extracted with slice, then column 1 may 
    # correspond to original column 123, and so on. This routine returns
    # the latter number when given the first. If the alignment is not a
    # slice then there is no original number and the number itself is 
    # returned. 

    my ( $ali,        # Alignment
         $col,        # Column index
         ) = @_;

    # Returns an integer. 

    my ( $orig_col );

    if ( defined $ali->_orig_cols ) {
        $orig_col = $ali->_orig_cols->at( $col );
    } else {
        $orig_col = $col;
    }

    return $orig_col;
}

sub global_cols
{
    my ( $ali,
        ) = @_;

    my ( @list );

    if ( defined $ali->_orig_cols ) {
        @list = $ali->_orig_cols->list;
    } else {
        @list = [ 0 .. $ali->max_col ];
    }

    return wantarray ? @list : \@list;
}

sub global_row
{
    # Niels Larsen, July 2005.

    # Returns the original row index of a given row. For example
    # when a set of rows is extracted with slice, then row 1 may 
    # correspond to original row 87, and so on. This routine returns
    # the latter number when given the first. If the alignment is not a
    # slice then there is no original number and the number itself is 
    # returned. 

    my ( $ali,        # Alignment
         $row,        # Row index
         ) = @_;

    # Returns an integer. 

    my ( $orig_row );

    if ( defined $ali->_orig_rows ) {
        $orig_row = $ali->_orig_rows->at( $row );
    } else {
        $orig_row = $row;
    }

    return $orig_row;
}

sub global_rows
{
    my ( $ali,
        ) = @_;

    my ( @list );

    if ( defined $ali->_orig_rows ) {
        @list = $ali->_orig_rows->list;
    } else {
        @list = [ 0 .. $ali->max_row ];
    }

    return wantarray ? @list : \@list;
}

sub grep_ids
{
    # Niels Larsen, April 2006.

    # UNFINISHED

    # Removes all entries whose names match the given expression.
    # Returns an updated alignment version. Assumes an un-pdlified 
    # alignment. 

    my ( $ali,         # Alignment
         $expr,        # Expression 
         ) = @_;

    # Returns alignment. 

    my ( $row, $max_row, $sids, $seqs );

    if ( $ali->is_pdl ) {
        &error( qq (A de-pdlified alignment must be given) );
    }

    $row = 0;
    $max_row = $#{ $ali->sids };

    $sids = $ali->sids;
    $seqs = $ali->seqs;

    while ( $row <= $#{ $sids } )
    {
        if ( $sids->[$row] =~ /$expr/ )
        {
            splice @{ $sids }, $row, 1;
            splice @{ $seqs }, $row, 1;
        }
        else {
            $row += 1;
        }
    }

    $ali->sids( $sids );
    $ali->seqs( $seqs );

    return $ali;
}

sub is_match_hash
{
    # Niels Larsen, September 2007.

    # 

    my ( $ali,
        ) = @_;

    my ( $type, $hash );

    if ( $type = $ali->datatype )
    {
        if ( &Common::Types::is_dna_or_rna( $type ) )
        {
            $hash = &Seq::Common::match_hash_nuc();
        }
        elsif ( &Common::Types::is_protein( $type ) )
        {
            $hash = &Seq::Common::match_hash_prot();
        }
        else {
            &error( qq (Wrong looking type -> "$type") );
        }
    }
    else {
        &error( qq (Type is undefined) );
    }

    return wantarray ? %{ $hash } : $hash;
}

sub is_pdl
{
    # Niels Larsen, August 2010.

    # Returns 1 if all PDL fields of the given alignment are PDL objects,
    # otherwise nothing.

    my ( $ali,
        ) = @_;

    my ( $key );

    foreach $key ( @PDL_fields )
    {
        return if (ref $ali->$key) !~ /^PDL/;
    }

    return 1;
}

sub local_col
{
    # Niels Larsen, July 2005.

    # Returns the local (to the current subalignment) column index of a given 
    # global (original numbering) column. It is set to undef if the global
    # column given falls outside the given alignment. 

    my ( $ali,        # Alignment
         $col,        # Global column index
         ) = @_;

    # Returns an integer. 

    my ( $pdl, $which, $local_col, $mincol, $maxcol );

    if ( defined ( $pdl = $ali->_orig_cols ) )
    {
        $mincol = $ali->min_col_global;
        $maxcol = $ali->max_col_global;

        if ( $col >= $mincol and $col <= $maxcol )
        {
            $which = &PDL::Primitive::which( $pdl == $col );

            if ( $which->isempty ) {
                $which = &PDL::Primitive::which( $pdl < $col );
            }

            if ( $which->isempty ) {
                $local_col = undef;
            } else {
                $local_col = $which->at(-1);
            }
        }
        else {
            $local_col = undef;
        }

    }
    else {
        $local_col = $col;
    }
     
    return $local_col;
}

sub local_cols
{
    # Niels Larsen, September 2008.

    # Returns a list where the indices are global column coordinates and 
    # values are local to the given alignment. The indices where there
    # is no local row are left undefined. 

    my ( $ali,
        ) = @_;

    # Returns a list.

    my ( $pdl, @cols, $i, $val, @list );

    if ( defined ( $pdl = $ali->_orig_cols ) )
    {
        @cols = $pdl->list;
        @list = ( undef ) x ( $ali->max_col_global + 1 );

        for ( $i = 0; $i <= $#cols; $i++ )
        {
            $list[ $cols[$i] ] = $i;
        }

        $val = $cols[0];

        for ( $i = 0; $i <= $#list; $i++ )
        {
            if ( defined $list[$i] )
            {
                $val = $list[$i]
            }
            else 
            {
                $list[$i] = $val;
            }
        }
    }
    else
    {
        @list = ( 0 .. $ali->max_col_global );
    }

    return wantarray ? @list : \@list;
}

sub local_row
{
    # Niels Larsen, July 2005.

    # Returns the local (to the current subalignment) row index of a given 
    # global (original numbering) row. It is set to undef if the global
    # row given falls outside the given alignment. 

    my ( $ali,        # Alignment
         $row,        # Global row index
         ) = @_;

    # Returns an integer. 

    my ( $pdl, $which, $local_row );

    if ( defined ( $pdl = $ali->_orig_rows ) )
    {
        $which = &PDL::Primitive::which( $pdl == $row );

        if ( $which->isempty ) {
            $which = &PDL::Primitive::which( $pdl < $row );
        }

        if ( $which->isempty ) {
            $local_row = undef;
        } else {
            $local_row = $which->at(-1);
        }
    }
    else {
        $local_row = $row;
    }
     
    return $local_row;
}

sub local_rows
{
    # Niels Larsen, September 2008.

    # Returns a list where the indices are global row coordinates and 
    # values are local to the given alignment. The indices where there
    # is no local row are left undefined. 

    my ( $ali,
        ) = @_;

    # Returns a list.

    my ( $pdl, @rows, $i, $val, @list );

    if ( defined ( $pdl = $ali->_orig_rows ) )
    {
        @rows = $pdl->list;
        @list = ( undef ) x ( $ali->max_row_global + 1 );

        for ( $i = 0; $i <= $#rows; $i++ )
        {
            $list[ $rows[$i] ] = $i;
        }

        $val = $rows[0];

        for ( $i = 0; $i <= $#list; $i++ )
        {
            if ( defined $list[$i] )
            {
                $val = $list[$i]
            }
            else 
            {
                $list[$i] = $val;
            }
        }
    }
    else
    {
        @list = ( 0 .. $ali->max_row_global );
    }

    return wantarray ? @list : \@list;
}

sub max_col
{
    my ( $ali,
         ) = @_;

    return ( $ali->seqs->dims )[0] - 1;
}

sub max_col_global
{
    my ( $ali,
         ) = @_;

    return $ali->_orig_cols->at(-1);
}

sub max_row
{
    my ( $ali,
         ) = @_;

    my ( $rows );

    return ( $ali->seqs->dims )[1] - 1;
}

sub max_row_global
{
    my ( $ali,
         ) = @_;

    return $ali->_orig_rows->at(-1);
}

sub min_col_global
{
    my ( $ali,
         ) = @_;

    return $ali->_orig_cols->at(0);
}

sub min_row_global
{
    my ( $ali,
         ) = @_;

    return $ali->_orig_rows->at(0);
}

sub seq_beg
{
    my ( $ali,
         $row,
        ) = @_;

    return $ali->_seq_num( "begs", $row );
}

sub seq_begs
{
    my ( $ali,
        ) = @_;

    return $ali->_seq_nums( "begs" );
}

sub seq_end
{
    my ( $ali,
         $row,
        ) = @_;

    return $ali->_seq_num( "ends", $row );
}

sub seq_ends
{
    my ( $ali,
        ) = @_;

    return $ali->_seq_nums( "ends" );
}

sub _seq_num
{
    # Niels Larsen, September 2007.

    # Returns a the index positions of the last base/residue in the 
    # given alignment, in sequence numbering. It may be lower than the 
    # begin number, to indicate a complemented sequence.

    my ( $ali,        # Alignment
         $name,
         $row,
         ) = @_;

    # Returns a list.

    my ( $pdl );

    $pdl = $ali->$name;

    return ${ $pdl->slice( ":,$row:$row" )->get_dataref };
}
    
sub _seq_nums
{
    # Niels Larsen, September 2007.

    # Returns a list of index positions of the last base/residue in the 
    # given alignment, in sequence numbering. It may be lower than the 
    # begin number, to indicate a complemented sequence.

    my ( $ali,        # Alignment
         $name,
         ) = @_;

    # Returns a list.

    my ( @ints, $row, $int, $pdl );

    $pdl = $ali->$name;

    for ( $row = 0; $row <= $ali->max_row; $row++ )
    {
        push @ints, ${ $pdl->slice( ":,$row:$row" )->get_dataref };
    }

    return wantarray ? @ints : \@ints;
}

sub seq_count
{
    my ( $ali,
         $row,
         $beg,
         $end,
        ) = @_;

    my ( $count );

    if ( $beg > $end ) {
        &error( "End should be > $beg, but is $end" );
    }

    $row = $ali->seqs->slice("$beg:$end,($row)");
    $count = $row->where( $row > 60 )->nelem;

    return $count;
}
    
sub seq_string
{
    # Niels Larsen, July 2005.

    # Returns the sequence for a given row as a character string. 

    my ( $ali,       # Alignment
         $row,       # Row index
         ) = @_;

    # Returns a string.

    my ( $string );

    $string = ${ $ali->seqs->slice(":,($row)")->get_dataref };

    return $string;
}

sub seq_string_ref
{
    # Niels Larsen, January 2006.

    # Returns the sequence for a given row as a character string. 

    my ( $ali,       # Alignment
         $row,       # Row index
         ) = @_;

    # Returns a string reference.

    return $ali->seqs->slice(":,($row)")->get_dataref;
}

sub seq_to_ali_pos
{
    # Niels Larsen, April 2006.

    # Return local column index of a given sequence position. 

    my ( $ali,             # Alignment
         $rowndx,          # Alignment row
         $seqpos,          # Sequence position
         ) = @_;

    # Returns integer.

    my ( $col, $max_col, $row, $cols, $maxpos );

    $max_col = $ali->max_col;
    $row = $ali->seqs->slice("0:$max_col,($rowndx)");

    $cols = &PDL::Primitive::which( $row > 60 );

    $maxpos = $cols->getdim(0) - 1;

    if ( $seqpos > $maxpos )
    {
        &error( qq (Seqpos is $seqpos but may only be $maxpos - program error) );
    }

    $col = $cols->at( $seqpos );

    return $col;
}

sub sid_len
{
    # Niels Larsen, July 2005.

    my ( $ali,
         ) = @_;

    return $ali->{"sid_cols"};
}

sub sid_string
{
    # Niels Larsen, July 2005.

    # Returns the short-id for a given row as a character string. 

    my ( $ali,       # Alignment
         $row,       # Row index
         ) = @_;

    # Returns a string.

    return ${ $ali->sids->slice(":,($row)")->get_dataref };
}

sub sids_list
{
    # Niels Larsen, February 2007.

    # Returns a list of the short ids of a given alignment.

    my ( $ali,        # Alignment
         ) = @_;

    # Returns a list.

    my ( @sids, $row, $sid, $sids_pdl, $max_row );

    $max_row = $ali->max_row;

    $sids_pdl = $ali->sids;

    for ( $row = 0; $row <= $max_row; $row++ )
    {
        $sid = ${ $sids_pdl->slice( ":,$row:$row" )->get_dataref };
        $sid =~ s/^\s*(\S+)\s*$/$1/;

        push @sids, $sid;
    }

    return wantarray ? @sids : \@sids;
}
    
sub time
{
    my ( $ali,
         $bool,
         ) = @_;

    if ( $bool ) {
        $ali->{"time"} = timelocal( (localtime)[0..5] );
    }

    if ( exists $ali->{"time"} ) {
        return $ali->{"time"};
    } else {
        return;
    }
}

# >>>>>>>>>>>>>>>>>>> ROUTINES WITH SOME FUNCTIONALITY <<<<<<<<<<<<<<<<<<

sub default_params
{
    my ( $class,
        ) = @_;

    my ( $params );

    $params = {
        "ali_bg_color" => "#CCCCCC",
        "ali_clipping" => undef,
        "ali_colstr" => "",
        "ali_datatype" => "",
        "ali_font_bold" => "VeraMoBd.ttf",
        "ali_font_normal" => "VeraMono.ttf",
        "ali_font_scale" => 0.7,
        "ali_gap_color" => "#999999",
        "ali_highlight_rna_covar" => 0,
        "ali_highlight_rna_pairs" => 1,
        "ali_highlight_seq_cons" => 0,
        "ali_image_area" => "",
        "ali_img_file" => undef,
        "ali_max_col" => undef,
        "ali_max_row" => undef,
        "ali_min_col" => undef,
        "ali_min_row" => undef,
        "ali_messages" => [],
        "ali_num_color" => "#333333",
        "ali_pix_per_row" => undef,
        "ali_pix_per_col" => undef,
        "ali_rowstr" => "",
        "ali_sid_color" => "#333333",
        "ali_with_resize_buttons" => 0,
        "ali_with_col_zoom" => 1,
        "ali_with_row_zoom" => 1,
        "version" => 1,
    };

    return $params;
}

sub de_pdlify
{
    # Niels Larsen, April 2006.

    # Converts PDL alignments fields to lists of strings. See also the pdlify
    # routine which does the opposite. 

    my ( $ali,        # Alignment
         ) = @_;

    # Returns alignment object.

    my ( $row, $key, $pdl, $max_row, @vals, $val );

    $max_row = $ali->max_row;

    foreach $key ( @PDL_fields )
    {
        if ( exists $ali->{ $key } )
        {
            $pdl = $ali->{ $key };
            @vals = ();
            
            if ( ref $pdl eq "PDL::Char" )
            {
                for ( $row = 0; $row <= $max_row; $row++ )
                {
                    $val = ${ $pdl->slice( ":,$row:$row" )->get_dataref };
                    $val =~ s/^\s*(\S+)\s*$/$1/;
                    
                    push @vals, $val;
                }
            }
            else {
                @vals = $pdl->list;
            }
            
            $ali->{ $key } = [ @vals ];
        }
    }

    return $ali;
}

sub is_chimeric
{
    # Niels Larsen, May 2011.

    # Decides if a given alignment is chimeric. Chimeric here means that in some
    # rows most of the sequence is off to the right, but in others it is off to 
    # the left. These arguments can be adjusted:
    # 
    #  mid_col     The left/right cutoff position, default the middle
    #  skip_row    A row to ignore, the cluster seed sequence usually
    #  min_offpct  How much a sequence must be off to either side 
    #  min_rowpct  How many rows must have off sequences
    #  min_balpct  How many left-off versus right-off sequences

    my ( $ali,    # Alignment object (not PDL)
         $args,   # Arguments hash
        ) = @_;

    # Returns 1 or nothing.

    my ( $mid_col, $min_offpct, $min_rowpct, $min_balpct, $stats, $str_l, 
         $str_r, $beg_l, $len_l, $beg_r, $len_r, $ndx, $seqs, $max_col, 
         $max_row, $res_l, $res_r, $res_tot, $num, $sids, @off_ids, @cent_ids,
         $offs_l, $offs_r, $offs_tot, @pcts, $pct, $num_tot, $i, @nums, $nums,
         @ndcs, $with_nums, $sid );
    
    $min_offpct = $args->{"min_offpct"} // 70;
    $min_rowpct = $args->{"min_rowpct"} // 80;
    $min_balpct = $args->{"min_balpct"} // 10;
    $with_nums = $args->{"with_nums"} // 1;

    $max_col = length $ali->seqs->[0];
    $max_row = $#{ $ali->seqs };

    $mid_col = int ( $max_col / 2 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> PERCENTAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Find how much sequences are off the middle. Those off to the left are 
    # positive, those to the right negative,

    $seqs = $ali->seqs;
    $sids = $ali->sids;

    $beg_l = 0;
    $len_l = $mid_col + 1;

    $beg_r = $mid_col + 1;
    $len_r = $max_col - $mid_col;

    for ( $ndx = 0; $ndx <= $max_row; $ndx += 1 )
    {
        $str_l = substr $seqs->[$ndx], $beg_l, $len_l;
        $str_r = substr $seqs->[$ndx], $beg_r, $len_r;

        $res_l = $str_l =~ tr/A-Za-z/A-Za-z/;
        $res_r = $str_r =~ tr/A-Za-z/A-Za-z/;

        $res_tot =  $res_l + $res_r;
        
        if ( $res_l == 0 )
        {
            $pct = -100;
        }
        elsif ( $res_r == 0 )
        {
            $pct = 100;
        }
        elsif ( $res_l > $res_r ) {
            $pct = int 100 * ( $res_l - $res_r ) / $res_tot;
        } else {
            $pct = int -100 * ( $res_r - $res_l ) / $res_tot;
        }

        push @pcts, $pct;
        push @ndcs, $ndx;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> COUNT OFF-ROW TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<
    
    # If alignment rows have numbers (they are duplicates or consenses) then 
    # include those in the counts,

    $offs_l = 0;
    $offs_r = 0;

    if ( $with_nums ) {
        @nums = map { $_ =~ /seq_count=(\d+)/; $1 } @{ $ali->info }[ @ndcs ];
    } else {
        @nums = ( 1 ) x scalar @ndcs;
    }

    for ( $i = 0; $i <= $#pcts; $i += 1 ) 
    {
        $pct = $pcts[$i];
        $num = $nums[$i];
        $sid = $sids->[$i];

        if ( $pct >= $min_offpct ) 
        {
            $offs_l += $num;
            push @off_ids, $sid;
        }
        elsif ( $pct <= - $min_offpct )
        {
            $offs_r += $num;
            push @off_ids, $sid;
        }
        else {
            push @cent_ids, $sid;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> COMPARE WITH CONDITIONS <<<<<<<<<<<<<<<<<<<<<<<<

    # This says: if enough rows are off, and they are not all off to one side,
    # then alignment is chimeric,
    
    $offs_tot = $offs_l + $offs_r;

    $num_tot = scalar @pcts - 1;    # There is always a seed sequence not to include

    if ( $offs_tot >= $num_tot * $min_rowpct / 100 and
         $offs_l >= $offs_tot * $min_balpct / 100 and
         $offs_r >= $offs_tot * $min_balpct / 100 )
    {
        return bless {
            "ali_id" => $ali->sid,
            "off_ids" => \@off_ids,
            "cent_ids" => \@cent_ids,
            "row_total" => $max_row + 1,
        };
    }

    return;
}

sub is_gap_col
{
    # Niels Larsen, July 2005.

    my ( $ali,
         $ndx,
         ) = @_;

    # Returns 1 or nothing. 

    my ( $col );

    $col = $ali->seqs->slice( "($ndx),:" );

    if ( $col->where( $col > 60 )->isempty )
    {
        return 1;
    } else {
        return;
    }
}

sub is_gap_row
{
    # Niels Larsen, July 2005.

    my ( $ali,
         $ndx,
         ) = @_;

    # Returns 1 or nothing. 

    my ( $row );

    $row = $ali->seqs->slice( ":,($ndx)" );

    if ( $row->where( $row > 60 )->isempty )
    {
        return 1;
    } else {
        return;
    }
}

sub new
{
    # Niels Larsen, June 2005.

    # Creates a new alignment object, with a time stamp and "sids" and "seqs"
    # fields as a minimum. See @PDL_fields for more fields. Fields are either
    # 2D PDL vectors or perl lists. 

    my ( $class,      # Class name
         %args,       # Initializations 
         ) = @_;

    # Returns an alignment object. 

    my ( $ali, $key, $value, $seq_count, $sid_count );

    foreach $key ( keys %args )
    {
        if ( $Fields{ $key } )
        {
            $value = $args{ $key };

            if ( $PDL_fields{ $key } )
            {
                if ( (ref $value) =~ /^PDL/ ) {
                    $ali->{ $key } = $value;
                } elsif ( ref $value eq "ARRAY" ) {
                    $ali->{ $key } = PDL::Char->new( $value );
                } else {
                    &error( qq (Short-ID\'s and sequences must be 2D PDL byte vector\'s) );
                }
            }
            else {
                $ali->{ $key } = $value;
            }
        }
        else {
            &error( qq (Wrong looking key -> "$key") );
        }
    }

    # Check for mandatory keys,

    if ( not exists $ali->{"sids"} ) {
        &error( qq (No short IDs given) );
    }

    if ( not exists $ali->{"seqs"} ) {
        &error( qq (No sequences given) );
    }

    # Check the number of IDs match number of sequences,

    $seq_count = $ali->{"seqs"}->getdim( 1 );
    $sid_count = $ali->{"sids"}->getdim( 1 );

    if ( $seq_count != $sid_count ) {
        &error( qq (Sequence count is $seq_count, but ID count is $sid_count) );
    }

    $class = ( ref $class ) || $class;
    bless $ali, $class;

    # Epoch time stamp,

    $ali->time( 1 );

    return $ali;
}

sub parse_locators
{
    # Niels Larsen, April 2011.

    # Parses locator strings of the form ali_id:seq_id:seq_locator where seq_id 
    # and seq_locator are optional. If seq_id is omitted and seq_locator given,
    # then than means all sub-columns in the given alignment. The seq_locator 
    # has this format "6,10;25,20,-;60,40,+" which parses into 
    # [[6,10,'+'],[15,20,'-'],[60,40,'+']], triplets of position, length and 
    # direction. If the input string is wrong-looking, then either a fatal error 
    # happens or if a message list is given, messages are appended to that. 

    my ( $locs,      # Locator string list
         $msgs,      # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list. 

    my ( @locs, @msgs, $str, $loc_str, $ali_id, $seq_id, $loclist );

    @msgs = ();

    foreach $str ( @{ $locs } )
    {
        if ( $str =~ /^([^:]+)$/o )
        {
            # Alignment id only,

            push @locs, [ $1 ];
        }
        elsif ( $str =~ /^([^:]+):([^:]*):?([^:]*)$/o )
        {
            ( $ali_id, $seq_id, $loc_str ) = ( $1, $2, $3 );

            if ( $loc_str )
            {
                $loclist = &Seq::Common::parse_loc_str( $loc_str, $msgs );

                push @locs, [ $ali_id, $seq_id, $loclist ];
            }
            elsif ( $seq_id )
            {
                push @locs, [ $ali_id, $seq_id ];
            }
            else {
                &error( "shouldnt happen" );
            }
        }
        else {
            push @msgs, ["ERROR", qq (Wrong looking location string -> "$str") ];
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @locs : \@locs;
}

sub parse_fasta
{
    # Niels Larsen, May 2011.

    # Parses a fasta oneline-formatted alignment string with multiple sequences. 
    # Input is a string reference (they can be large), output is an alignment 
    # object in non-PDL form. 

    my ( $astr,      # Alignment string reference
        ) = @_;

    # Returns object.

    my ( @sids, @seqs, @info, $ali );

    state $hdrexp = '(\S+) ?([^\n]*)\n([^\n]+)';
    
    while ( ${ $astr } =~ />$hdrexp/og )
    {
        push @sids, $1;
        push @info, $2;
        push @seqs, $3;
    }
    
    if ( $info[0] ne "" ) {
        $ali = bless { "sids" => \@sids, "seqs" => \@seqs, "info" => \@info };
    } else {
        $ali = bless { "sids" => \@sids, "seqs" => \@seqs };
    }        
    
    return $ali;
}

sub parse_fasta_wrapped
{
    # Niels Larsen, May 2011.

    # Parses a fasta oneline-formatted alignment string with multiple sequences. 
    # Input is a string reference (they can be large), output is an alignment 
    # object in non-PDL form. 

    my ( $astr,      # Alignment string reference
        ) = @_;

    # Returns object.

    my ( @sids, @seqs, @info, $ali, $seq );

    state $hdrexp = '(\S+) ?([^\n]*)\n([^>]+)';
    
    while ( ${ $astr } =~ />$hdrexp/ogs )
    {
        push @sids, $1;
        push @info, $2;

        $seq = $3;
        $seq =~ s/\s//g;
        
        push @seqs, $seq;
    }
    
    if ( $info[0] ne "" ) {
        $ali = bless { "sids" => \@sids, "seqs" => \@seqs, "info" => \@info };
    } else {
        $ali = bless { "sids" => \@sids, "seqs" => \@seqs };
    }        
    
    return $ali;
}

sub parse_uclust
{
    # Niels Larsen, May 2011.

    # Parses a uclust-formatted alignment string with multiple sequences. Input 
    # is a string reference (they can be large), output is an alignment object 
    # in non-PDL form. 

    my ( $astr,      # Alignment string reference
        ) = @_;

    # Returns object.

    my ( @sids, @seqs, @info, $ali );

    state $hdrexp = '\d+\|[^\|]+\|(\S+) ?([^\n]*)\n([^\n]+)';
    
    while ( ${ $astr } =~ />$hdrexp/og )
    {
        push @sids, $1;
        push @info, $2;
        push @seqs, $3;
    }

    if ( $info[0] ne "" ) {
        $ali = bless { "sids" => \@sids, "seqs" => \@seqs, "info" => \@info };
    } else {
        $ali = bless { "sids" => \@sids, "seqs" => \@seqs };
    }        
    
    return $ali;
}

sub pdlify
{
    # Niels Larsen, April 2011.

    # Converts the alignment fields in the global variable @PDL_fields to PDL
    # format. If a given field is already PDL then it is not touched.
    # 
    # UNTESTED - see also pdlify_old (which does un-necessary things it seems)

    my ( $ali,        # Alignment
         $pad,        # Adds padding - OPTIONAL, default 1
         ) = @_;

    # Returns alignment object.

    my ( $field, $rows );

    $pad //= 1;
    
    $ali = &Ali::Common::add_padding( $ali ) if $pad;

    foreach $field ( @PDL_fields )
    {
        if ( ref ( $rows = $ali->$field ) eq "ARRAY" )
        {
            $ali->$field( PDL::Char->new( $rows ) );
        }
    }

    return $ali;
}

sub pdlify_old
{
    # Niels Larsen, March 2010.

    # Converts the alignment fields in the global variable @PDL_fields to PDL
    # format. If a given field is already PDL then it is not touched.

    my ( $ali,        # Alignment
         ) = @_;

    # Returns alignment object.

    my ( $max_row, $row, $key, $val, $len, $nulls, $list, $wid, $pdl );
    
    # Mandatory IDs,

    if ( ref $ali->sids eq "ARRAY" )
    {
        $list = $ali->sids;
        $max_row = $#{ $list };

        $wid = &List::Util::max( map { length $_ } @{ $list } );
        $pdl = PDL->zeroes( PDL->byte(0)->type, $wid, $max_row + 1 );

        for ( $row = 0; $row <= $max_row; $row++ )
        {
            $val = PDL::Char->new( sprintf "%$wid"."s", $list->[$row] );
            $len = $val->nelem;
            
            if ( $len < $wid )
            {
                $nulls = PDL::Char->new( "\0" x ( $wid - $len) );
                $val = $val->append( $nulls );
            }
            
            $pdl->slice( ":,$row:$row" ) .= $val;
        }
        
        $ali->sids( $pdl );
    }

    # Mandatory sequences,

    if ( ref $ali->seqs eq "ARRAY" )
    {
        $list = $ali->seqs;
        $max_row = $#{ $list };

        $wid = &List::Util::max( map { length $_ } @{ $list } );
        $pdl = PDL->zeroes( PDL->byte(0)->type, $wid, $max_row + 1 );

        for ( $row = 0; $row <= $max_row; $row++ )
        {
            $val = PDL::Char->new( $list->[$row] );
            $pdl->slice( ":,$row:$row" ) .= $val;
        }
        
        $ali->seqs( $pdl );
    }
    
    # All other fields,
    
    foreach $key ( grep { $_ ne "seqs" and $_ ne "sids" } @PDL_fields )
    {
        if ( exists $ali->{ $key } and ref $ali->{ $key } eq "ARRAY" )
        {
            $list = $ali->{ $key };
            $max_row = $#{ $list };
            
            $wid = &List::Util::max( map { length $_ } @{ $list } );
            $pdl = PDL->zeroes( PDL->byte(0)->type, $wid, $max_row + 1 );
            
            for ( $row = 0; $row <= $max_row; $row++ )
            {
                $val = PDL::Char->new( sprintf "%$wid"."s", $list->[$row] );
                $pdl->slice( ":,$row:$row" ) .= $val;
            }
            
            $ali->$key( $pdl );
        }
    }

    return $ali;
}

sub replace_char
{
    # Niels Larsen, August 2010.

    # Replaces a given character with another, in the sequences.

    my ( $ali,       # Alignment
         $old,       # Character to be replaced 
         $new,       # The replacement character
         ) = @_;

    # Returns updated alignment.

    my ( $list, $pdl, $max_row, $row );

    if ( $ali->is_pdl )
    {
        $max_row = $ali->max_row;

        # TODO - doesnt work
        for ( $row = 0; $row <= $max_row; $row++ )
        {
            ${ $ali->seqs->slice(":,($row)")->get_dataref } =~ tr/$old/$new/;
        }
    }
    else
    {
        $list = $ali->seqs;

        for ( $row = 0; $row <= $#{ $list }; $row++ )
        {
            $list->[$row] =~ s/$old/$new/g;
        }
    }        

    return $ali;
}

sub remove_gaps
{
    # Niels Larsen, April 2006.

    # Deletes non-valid characters from un-pdlified alignment sequences.
    # Returns an updated alignment.

    my ( $ali,
         ) = @_;

    # Returns an alignment object.
    
    my ( $seqs, $seq, $row );

    $seqs = $ali->seqs;

    for ( $row = 0; $row <= $#{ $seqs }; $row++ )
    {
        $seqs->[$row] =~ s/[.~-]//g;
    }

    return $ali;
}

sub subali_at
{
    # Niels Larsen, September 2005.
    
    # Extracts a subalignment. Unlike the slice function it is relative
    # to a given row and column. The columns and rows to be included in each 
    # direction (up, down, left and right) from that starting coordinate are 
    # also given; if they are lists, their values will be used, or if numbers
    # new indices will be created. If there are less rows/columns to get than
    # asked for, clipping values are set in the given parameters hash. This 
    # routine is used in other routines, like subali_center. It is kind of 
    # the "extraction workhorse". 

    my ( $self,       # Original alignment
         $begcol,     # Starting column value
         $begrow,     # Starting row value
         $r_cols,     # Number of columns to the right or column list
         $l_cols,     # Number of columns to the left or column list
         $d_rows,     # Number of rows down or row list
         $u_rows,     # Number of rows up or row list
         $params,     # Parameters hash
         ) = @_;

    # Returns an alignment object.

    my ( $maxrow, $maxcol, @cols, @rows, $cols, $rows, $subali, $col_step, 
         $row_step, $collapse, $clip );

    $maxrow = $self->max_row;
    $maxcol = $self->max_col;

    if ( $params->{"ali_pix_per_col"} >= 1 ) {
        $col_step = 1;
    } else {
        $col_step = 1 / $params->{"ali_pix_per_col"};
    }

    if ( $params->{"ali_pix_per_row"} >= 1 ) {
        $row_step = 1;
    } else {
        $row_step = 1 / $params->{"ali_pix_per_row"};
    }

#    &dump( $params->{"ali_pix_per_col"} );
#    &dump( $params->{"ali_pix_per_row"} );

    # >>>>>>>>>>>>>>>>>>>>>>> INITIALIZE CLIPPING <<<<<<<<<<<<<<<<<<<<<<<

    # Clipping is the number of columns and rows that are off the edges
    # of the viewport. If the viewport is at the edge of the alignment
    # the clip value is zero, and negative if viewport edge is off the 
    # alignment edge. We keep these values in a hash with the keys "top",
    # "bottom", "left" and "right". Here we initialize them, and below
    # we extend them if requested, 

    $clip = $params->{"ali_clipping"};

    @rows = ( $begrow );
    $collapse = $params->{"ali_prefs"}->{"ali_with_row_collapse"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DOWN ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( ref $d_rows )
    {
        push @rows, @{ $d_rows };
        $clip->{"bottom"} = $maxrow - $d_rows->[-1];
    }
    elsif ( defined $d_rows )
    {
        if ( $begrow < $maxrow )
        {
            if ( $d_rows > 0 )
            {
                ( $rows, $clip->{"bottom"} ) = 
                    $self->_get_indices_down( $begrow + 1, $d_rows, $collapse, $row_step );

                if ( defined $rows ) {
                    push @rows, @{ $rows } ;
                }
            }
        }
        elsif ( $begrow == $maxrow ) 
        {
            $clip->{"bottom"} = - $d_rows;
        }
        else {
            &error( qq (Start row $begrow > max row $maxrow) );
        }
    }
    elsif ( not defined $clip->{"bottom"} )
    {
        $clip->{"bottom"} = $self->max_row - $begrow;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UP ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( ref $u_rows )
    {
        unshift @rows, @{ $u_rows };
        $clip->{"top"} = $d_rows->[0];
    }
    elsif ( defined $u_rows )
    {
        if ( $begrow > 0 )
        {
            if ( $u_rows > 0 ) 
            {
                ( $rows, $clip->{"top"} ) = 
                    $self->_get_indices_up( $begrow - 1, $u_rows, $collapse, $row_step );

                if ( defined $rows ) {
                    unshift @rows, @{ $rows };
                }
            }
        }
        elsif ( $begrow == 0 )
        {
            $clip->{"top"} = - $u_rows;
        }
        else {
            &error( qq (Start row $begrow < 0) );
        }
    }
    elsif ( not defined $clip->{"top"} )
    {
        $clip->{"top"} = $begrow;
    }
        
    $subali = $self->subali_get( undef, \@rows, $params->{"ali_prefs"}->{"ali_with_sids"}, 0 );

    @cols = ( $begcol );
    $collapse = $params->{"ali_prefs"}->{"ali_with_col_collapse"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> RIGHT COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( ref $r_cols )
    {
        push @cols, @{ $r_cols };
        $clip->{"right"} = $maxcol - $r_cols->[-1];
    }
    elsif ( defined $r_cols )
    {
        if ( $begcol < $maxcol ) 
        {
            if ( $r_cols > 0 )
            {
                ( $cols, $clip->{"right"} ) = 
                    $subali->_get_indices_right( $begcol + 1, $r_cols, $collapse, $col_step );

                if ( defined $cols ) {
                    push @cols, @{ $cols };
                }
            }
        } 
        elsif ( $begcol == $maxcol )
        {
            $clip->{"right"} = - $r_cols;
        }
        else
        {
            &error( qq (Start column $begcol > max column $maxcol) );
        }
    }
    elsif ( not defined $clip->{"right"} )
    {
        $clip->{"right"} = $self->max_col - $begcol;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LEFT COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( ref $l_cols )
    {
        unshift @cols, @{ $l_cols };
        $clip->{"left"} = $l_cols->[0];
    }
    elsif ( defined $l_cols )
    {
        if ( $begcol > 0 )
        {
            if ( $l_cols > 0 )
            {
                ( $cols, $clip->{"left"} ) = 
                    $subali->_get_indices_left( $begcol - 1, $l_cols, $collapse, $col_step );

                if ( defined $cols ) {
                    unshift @cols, @{ $cols };
                }
            }
        }
        elsif ( $begcol == 0 )
        {
            $clip->{"left"} = - $l_cols;
        }
        else {
            &error( qq (Start column $begcol < 0) );
        }
    }
    elsif ( not defined $clip->{"left"} )
    {
        $clip->{"left"} = $begcol;
    }

    $subali = $self->subali_get( \@cols, \@rows,
                                 $params->{"ali_prefs"}->{"ali_with_sids"},
                                 $params->{"ali_prefs"}->{"ali_with_nums"} );

    # Save clipping in state,

    $params->{"ali_clipping"} = $clip;

    return $subali;
}

sub subali_center
{
    # Niels Larsen, July 2005.

    # Returns a subalignment that is centered around the given column and row.
    # It calls subali_at to do the real work. 

    my ( $ali,        # Alignment object
         $col,        # New center column
         $row,        # New row column
         $params,     # Parameters hash
         ) = @_;

    # Returns an alignment object. 

    my ( $data_cols, $data_rows, $right_cols, $left_cols,
         $down_rows, $up_rows, $subali );

    $data_cols = $params->{"ali_data_cols"};
    $left_cols = int ( $data_cols / 2 );

    if ( $data_cols % 2 == 1 ) {
        $right_cols = $left_cols;
    } else {
        $right_cols = $left_cols - 1;
    }
    
    $data_rows = $params->{"ali_data_rows"};
    $up_rows = int ( $data_rows / 2 );

    if ( $data_rows % 2 == 1 ) {
        $down_rows = $up_rows;
    } else {
        $down_rows = $up_rows - 1;
    }

    return $ali->subali_at( $col, $row, $right_cols, $left_cols, $down_rows, $up_rows, $params );
}

sub subali_down
{
    # Niels Larsen, July 2005.

    # Scrolls "down", by creating a sub-alignment with higher-index rows. 

    my ( $ali,           # Original alignment
         $begcol,        # Starting column index
         $begrow,        # Starting column index
         $params,        # Parameters (see default_params)
         ) = @_;

    # Returns an alignment object. 

    undef $params->{"ali_clipping"}->{"top"};
    undef $params->{"ali_clipping"}->{"bottom"};

    return $ali->subali_at(
        $begcol,
        $begrow,
        $params->{"ali_data_cols"} - 1,
        undef, 
        $params->{"ali_data_rows"} - 1,
        undef,
        $params,
        );
}

sub subali_down_cols
{
    # Niels Larsen, July 2005.

    # Scrolls "down", by creating a sub-alignment with higher-index rows. 

    my ( $ali,           # Original alignment
         $cols,          # Original column indices
         $begrow,        # Starting row index
         $params,        # Parameters (see default_params)
         ) = @_;

    # Returns an alignment object. 

    my ( $r_cols );

    undef $params->{"ali_clipping"}->{"top"};
    undef $params->{"ali_clipping"}->{"bottom"};

    if ( scalar @{ $cols } > 1 ) {
        $r_cols = [ @{ $cols }[ 1 .. $#{ $cols } ] ];
    } else {
        $r_cols = undef;
    }

    return $ali->subali_at(
        $cols->[0],
        $begrow,
        $r_cols,
        undef, 
        $params->{"ali_data_rows"} - 1,
        undef,
        $params,
        );
}

sub subali_left
{
    # Niels Larsen, July 2005.

    # Scrolls "left", by creating a sub-alignment upstream of a given position.
    # Depending on $params->{"ali_with_col_collapse"} the sub-alignment contains all-gap
    # columns or not. 

    my ( $ali,           # Original alignment
         $begcol,        # Starting column
         $rows,          # Original row indices
         $params,        # Parameters (see default_params)
         ) = @_;

    # Returns an alignment object. 

    my ( $d_rows );

    undef $params->{"ali_clipping"}->{"left"};
    undef $params->{"ali_clipping"}->{"right"};

    if ( scalar @{ $rows } > 1 ) {
        $d_rows = [ @{ $rows }[ 1 .. $#{ $rows } ] ];
    } else {
        $d_rows = undef;
    }

    return $ali->subali_at(
        $begcol, 
        $rows->[0],
        undef, 
        $params->{"ali_data_cols"} - 1,
        $d_rows,
        undef,
        $params
        );
}

sub subali_get
{
    # Niels Larsen, June 2005.

    # Extracts a sub-alignment with everything that goes with it. The input should
    # be a full alignment (not a sub-alignment), along with lists or 1d piddles of 
    # columns and rows to be extracted. 

    my ( $self,           # Alignment object 
         $cols,           # Column indices - OPTIONAL with $rows
         $rows,           # Row indices - OPTIONAL with $cols
         $s_bool,         # Short id flag
         $n_bool,         # Numbers flag
         ) = @_;

    # Returns an alignment object. 

    my ( $ali, $orig_cols, $orig_rows, $orig_col_min, $orig_col_max, 
         @begs, @ends, $orig_beg, $orig_end, $beg, $end, $beg_wid, 
         $end_wid, $row_dim, $begs_pdl, $ends_pdl, $row, $n_off, $n_img,
         $beg_blank, $end_blank );

    if ( not defined $cols and not defined $rows ) {
        &error( qq (Neither column or row indices given - one or the other is needed.) );
    }

    # Make copy of the references but keep connection to original,
    
    $ali = $self->copy( 0 );

    # If the original is not saved already, do it,

    if ( $ali->orig_ali ) {
        &error( qq (Making a subalignment from a subalignment is not supported yet.) );
    } else {
        $ali->orig_ali( $self );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DATA ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get rows first, if any, otherwise use all,

    if ( defined $rows )
    {
        if ( ref $rows eq "PDL" ) {
            $orig_rows = $rows;
        } else {
            $orig_rows = PDL->new( $rows );
        }
        
        $ali->seqs( $ali->seqs->dice( "X", $orig_rows ) );
    }
    else {
        $orig_rows = PDL->new( [ 0 .. $self->max_row ] );
    }

    $ali->_orig_rows( $orig_rows );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DATA COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If rows were specified we now extract from a much smaller set,

    if ( defined $cols )
    {
        if ( ref $cols eq "PDL" ) {
            $orig_cols = $cols;
        } else {
            $orig_cols = PDL->new( $cols );
        }

        $ali->seqs( $ali->seqs->dice( $orig_cols, "X" ) );
    }
    else {
        $orig_cols = PDL->new( [ 0 .. $self->max_col ] );
    }        

    $ali->_orig_cols( $orig_cols );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SHORT-IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $s_bool and defined $rows )
    {
        $ali->sids( $ali->sids->dice( "X", $orig_rows ) );
    }
    elsif ( not $s_bool )
    {
        delete $ali->{"sids"};
    }
    
    # >>>>>>>>>>>>>>>>>>>>>> BEGIN AND END NUMBERS <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $n_bool )
    {
        # The first and last column index in original numbering,

        $orig_col_min = $orig_cols->at( 0 );
        $orig_col_max = $orig_cols->at( -1 );

        $begs_pdl = $ali->begs->dice( "X", $orig_rows );
        $ends_pdl = $ali->ends->dice( "X", $orig_rows );

        ( $beg_wid, $row_dim ) = ( $begs_pdl->dims );
        ( $end_wid, $row_dim ) = ( $ends_pdl->dims );

        $beg_blank = " " x $beg_wid;
        $end_blank = " " x $end_wid;

        for ( $row = 0; $row < $row_dim; $row++ )
        {
            # First and last sequence index in original numbering,

            $orig_beg = ${ $begs_pdl->slice( ":,$row:$row" )->get_dataref } * 1;
            $orig_end = ${ $ends_pdl->slice( ":,$row:$row" )->get_dataref } * 1;

            # n_off: number of residues before display starts
            # n_img: number of residues on display

            if ( $orig_col_min > 0 ) {
                $n_off = $self->seq_count( $orig_rows->at( $row ), 0, $orig_col_min-1 );
            } else {
                $n_off = 0;
            }

            $n_img = $self->seq_count( $orig_rows->at( $row ), $orig_col_min, $orig_col_max );

            if ( $orig_beg < $orig_end )
            {                
                $beg = $orig_beg + $n_off;

                if ( $beg > 0 ) {
                    push @begs, sprintf "%".$beg_wid."s", $beg + 1;
                } else {
                    push @begs, $beg_blank;
                }

                $end = $beg + &Common::Util::max( 0, $n_img - 1 );

                if ( $end > 0 ) {
                    push @ends, sprintf "%".$end_wid."s", $end + 1;
                } else {
                    push @ends, $end_blank;
                }                    
            }
            else
            {
                $beg = $orig_beg - $n_off;

                if ( $beg > 0 ) {
                    push @begs, sprintf "%".$beg_wid."s", $beg + 1;
                } else {
                    push @begs, $beg_blank;
                }
                
                $end = $beg - &Common::Util::max( 0, $n_img - 1 );

                if ( $end > 0 ) {
                    push @ends, sprintf "%".$end_wid."s", $end + 1;
                } else {
                    push @ends, $end_blank;
                }                    
            }
        }

        $ali->begs( PDL::Char->new( \@begs ) );
        $ali->ends( PDL::Char->new( \@ends ) );
    }
    else
    {
        delete $ali->{"begs"};
        delete $ali->{"ends"};
    }

    return $ali;
}

sub subali_right
{
    # Niels Larsen, July 2005.

    # Scrolls "right", by creating a sub-alignment downstream of a given position.
    # Depending on $params->{"ali_with_col_collapse"} the sub-alignment contains all-gap
    # columns or not. 

    my ( $ali,           # Original alignment
         $begcol,        # Starting column
         $rows,          # Original row indices
         $params,        # Parameters (see default_params)
         ) = @_;

    # Returns an alignment object. 

    my ( $d_rows );

    undef $params->{"ali_clipping"}->{"left"};
    undef $params->{"ali_clipping"}->{"right"};

    if ( scalar @{ $rows } > 1 ) {
        $d_rows = [ @{ $rows }[ 1 .. $#{ $rows } ] ];
    } else {
        $d_rows = undef;
    }

    return $ali->subali_at(
        $begcol,
        $rows->[0],
        $params->{"ali_data_cols"} - 1,
        undef,
        $d_rows,
        undef,
        $params,
        );
}

sub subali_up
{
    # Niels Larsen, July 2005.

    # Scrolls "up", by creating a sub-alignment with lower-index rows.

    my ( $ali,           # Original alignment
         $begcol,        # Starting column index
         $begrow,        # Starting row index
         $params,        # Parameters (see default_params)
         ) = @_;

    # Returns an alignment object. 

    undef $params->{"ali_clipping"}->{"top"};
    undef $params->{"ali_clipping"}->{"bottom"};

    return $ali->subali_at(
        $begcol, $begrow, 
        $params->{"ali_data_cols"} - 1,
        undef,
        undef,
        $params->{"ali_data_rows"} - 1,
        $params,
        );
}

sub subali_up_cols
{
    # Niels Larsen, July 2005.

    # Scrolls "up", by creating a sub-alignment slice with lower-index 
    # rows. The existing set of columns are reused, so that only the 
    # corresponding columns are included in the view - i.e. columns 
    # may be skipped that include data. 

    my ( $ali,           # Original alignment
         $cols,          # Original column indices
         $begrow,        # Starting row index
         $params,        # Parameters (see default_params)
         ) = @_;

    # Returns an alignment object. 

    my ( $r_cols );

    undef $params->{"ali_clipping"}->{"top"};
    undef $params->{"ali_clipping"}->{"bottom"};

    if ( scalar @{ $cols } > 1 ) {
        $r_cols = [ @{ $cols }[ 1 .. $#{ $cols } ] ];
    } else {
        $r_cols = undef;
    }

    return $ali->subali_at(
        $cols->[0],
        $begrow, 
        $r_cols,
        undef,
        undef,
        $params->{"ali_data_rows"} - 1,
        $params,
        );
}

# >>>>>>>>>>>>>>>>>>>>>>>>>> INTERNAL ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<

# These are used by functions in this module only. While they users of 
# this module may call them, they may evolve quickly and break your 
# program. 

sub _debug
{
    # Niels Larsen, July 2005.

    # Merely prints all object fields, as debugging help. If the value of  
    # field is a piddle, then only its dimensions are printed. 

    my ( $ali,
         ) = @_;

    # Returns nothing. 

    my ( $key, $cols, $rows, $text );

    $text = "\n";

    foreach $key ( keys %{ $ali } )
    {
        $text .= "$key: ";
        
        if ( ref $ali->{ $key } eq "PDL" )
        {
            ( $cols, $rows ) = $ali->{ $key }->dims;

            if ( defined $rows ) {
                $text .= "$cols columns, $rows rows\n";
            } else {
                $text .= "$cols long\n";
            }
        }
        elsif ( defined $ali->{ $key } )
        {
            $text .= "$ali->{ $key }\n";
        }
        else {
            $text .= "undef\n";
        }
    }

    if ( defined wantarray ) {
        return $text;
    } else {
        &dump( $text ) and return;
    }
}

sub _get_indices_down
{
    # Creates a list of row indices, starting at a given row and extending
    # down. 

    my ( $ali,         # Alignment
         $toprow,       # Start row index
         $height,       # Maximum number of indices to include
         $collapse,     # Row collapse flag
         $step,
         ) = @_;

    # Returns a list.

    $step = 1 if not defined $step;

    my ( $botrow, $maxrow, @rows, $count, $clip, $testfunc, $dist );

    $maxrow = $ali->max_row;

    if ( defined $toprow )
    {
        if ( $toprow > $maxrow ) {
            &error( qq (Down scroll-start row past the end ($maxrow) -> "$toprow") );
        }
    }
    else {
        &error( qq (Down scroll-start row not defined) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TEST FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $collapse )
    {
        $testfunc = sub 
        {
            my ( $ali, $ndx ) = @_;

            return not $ali->is_gap_row( $ndx );
        }
    }
    else
    {
        $testfunc = sub
        {
            my ( $ali, $ndx ) = @_;
            return 1;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SAMPLE ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $botrow = $toprow;
    $dist = $toprow;

    $count = 1; 
        
    while ( $botrow <= $maxrow and $count <= $height )
    {
        if ( &{ $testfunc }( $ali, $botrow ) )
        {
            push @rows, $botrow;
            $count += 1;
        }

        $dist += $step;
        $botrow = int $dist;
#        $botrow += 1;
    }
    
    if ( $botrow > $maxrow ) {
        $clip = $count - $height - 1;
    } else {
        $clip = $maxrow - $botrow + 1;
    }
    
    if ( @rows ) {
        return ( \@rows, $clip );
    } else {
        return ( undef, $clip );
    }
}

sub _get_indices_left
{
    # Creates a list of column indices, starting at a given column and
    # extending left. Optionally columns are skipped that contains only
    # gaps. 

    my ( $ali,         # Alignment
         $endcol,       # Start column index
         $width,       # Maximum number of indices to include
         $collapse,     # Column collapse flag
         $step,
         ) = @_;

    # Returns a list.

    $step = 1 if not defined $step;

    my ( $count, $begcol, @cols, $clip, $testfunc, $dist );

    if ( defined $endcol )
    {
        if ( $endcol < 0 ) {
            &error( qq (Left scroll start-column negative -> "$endcol") );
        }
    }
    else {
        &error( qq (Left scroll start-column not defined) );
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TEST FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $collapse )
    {
        $testfunc = sub 
        {
            my ( $ali, $ndx ) = @_;

            return not $ali->is_gap_col( $ndx );
        }
    }
    else
    {
        $testfunc = sub
        {
            my ( $ali, $ndx ) = @_;
            return 1;
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SAMPLE COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $begcol = $endcol;
    $dist = $endcol;

    $count = 1;
        
    while ( $begcol >= 0 and $count <= $width )
    {
        if ( &{ $testfunc }( $ali, $begcol ) )
        {
            unshift @cols, $begcol;
            $count += 1;
        }

        $dist -= $step;
        $begcol = int $dist;
#        $begcol -= 1;
    }
    
    if ( $begcol < 0 ) {
        $clip = $count - $width - 1;
    } else {
        $clip = $begcol + 1;
    }

    if ( @cols ) {
        return ( \@cols, $clip );
    } else {
        return ( undef, $clip );
    }
}

sub _get_indices_right
{
    # Niels Larsen, September 2005.

    # Creates a list of column indices towards the end of the alignment. If the 
    # end of the alignment is reached, the list gets shorted and a clipping value
    # is set. Depending on the "ali_with_col_collapse" setting, columns are skipped
    # that only contain gaps. 

    my ( $ali,         # Alignment
         $begcol,       # Start column index
         $width,        # Maximum number of indices to include
         $collapse,     # Column collapse flag
         $step,
         ) = @_;

    # Returns a list.

    my ( $count, $endcol, $maxcol, @cols, $clip, $testfunc, $dist );
    
    $step = 1 if not defined $step;

    $maxcol = $ali->max_col;

    if ( defined $begcol )
    {
        if ( $begcol > $maxcol ) {
            &error( qq (Right scroll start-column past the end ($maxcol) -> "$begcol") );
        }
    }
    else {
        &error( qq (Right scroll-start column not defined) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TEST FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $collapse )
    {
        $testfunc = sub 
        {
            my ( $ali, $ndx ) = @_;

            return not $ali->is_gap_col( $ndx );
        }
    }
    else
    {
        $testfunc = sub
        {
            my ( $ali, $ndx ) = @_;
            return 1;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SAMPLE COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $endcol = $begcol;
    $dist = $begcol;

    $count = 1; 
    
    while ( $endcol <= $maxcol and $count <= $width )
    {
        if ( &{ $testfunc }( $ali, $endcol ) )
        {
            push @cols, $endcol;
            $count += 1;
        }

        $dist += $step;
        $endcol = int $dist;
    }
    
    if ( $endcol > $maxcol ) {
        $clip = $count - $width - 1;
    } else {
        $clip = $maxcol - $endcol + 1;
    }
    
    if ( @cols ) {
        return ( \@cols, $clip );
    } else {
        return ( undef, $clip );
    }
}

sub _get_indices_up
{
    # Creates a list of row indices, starting at a given row and extending
    # upwards. It also sets clipping value for the top row.

    my ( $ali,         # Alignment
         $botrow,       # Start row index
         $height,       # Number of indices to include
         $collapse,     # Row collapse flag
         $step,
         ) = @_;

    # Returns a list.

    $step = 1 if not defined $step;
    
    my ( $toprow, @rows, $count, $clip, $i, $testfunc, $dist );

    if ( defined $botrow )
    {
        if ( $botrow < 0 ) {
            &error( qq (Up scroll start-row negative -> "$botrow") );
        }
    }
    else {
        &error( qq (Up scroll start-row not defined) );
    }        

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TEST FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $collapse )
    {
        $testfunc = sub 
        {
            my ( $ali, $ndx ) = @_;

            return not $ali->is_gap_row( $ndx );
        }
    }
    else
    {
        $testfunc = sub
        {
            my ( $ali, $ndx ) = @_;
            return 1;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SAMPLE ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $toprow = $botrow;
    $dist = $botrow;

    $count = 1;

    while ( $toprow >= 0 and $count <= $height )
    {
        if ( &{ $testfunc }( $ali, $toprow ) )
        {
            unshift @rows, $toprow;
            $count += 1;
        }

        $dist -= $step;
        $toprow = int $dist;
#        $toprow -= 1;
    }

    if ( $toprow < 0 ) {
        $clip = $count - $height - 1;
    } else {
        $clip = $toprow + 1;
    }
        
    if ( @rows ) {
        return ( \@rows, $clip );
    } else {
        return ( undef, $clip );
    }
}

sub _orig_cols
{
    # Niels Larsen, July 2005.

    # Gets or sets original column indices. It is used for example in 
    # slice operations, where numbering, features etc requires knowing
    # the original columns that each cut out new column came from.

    my ( $ali,          # Alignment object
         $cols,          # Original columns piddle
         ) = @_;

    # Returns a 1D piddle or nothing. 

    if ( defined $cols )
    {
        if ( exists $ali->{"orig_cols"} ) {
            $ali->{"orig_cols"} = $ali->{"orig_cols"}->index( $cols );
        } else {
            $ali->{"orig_cols"} = $cols;
        }
    }

    if ( exists $ali->{"orig_cols"} ) {
        return $ali->{"orig_cols"};
    } else {
        return;
    }
}

sub _orig_rows
{
    # Niels Larsen, July 2005.

    # Gets or sets original row indices. It is used for example in 
    # slice operations, where numbering, features etc requires knowing
    # the original columns that each cut out new row came from.

    my ( $ali,          # Alignment object
         $rows,          # Original rows piddle
         ) = @_;

    # Returns a 1D piddle. 

    if ( defined $rows )
    {
        if ( $rows->isempty )
        {
            &error( qq (Rows piddle empty) );
        }
        else
        {
            if ( exists $ali->{"orig_rows"} ) {
                $ali->{"orig_rows"} = $ali->{"orig_rows"}->index( $rows );
            } else {
                $ali->{"orig_rows"} = $rows;
            }
        }
    }

    if ( exists $ali->{"orig_rows"} ) {
        return $ali->{"orig_rows"};
    } else {
        return;
    }
}

sub to_dna
{
    # Niels Larsen, March 2006.

    # Changes U's in the sequences to T's. 

    my ( $ali,       # Alignment
         ) = @_;

    # Returns alignment.

    my ( $seq );

    foreach $seq ( @{ $ali->seqs } )
    {
        $seq =~ tr/Uu/Tt/;
    }

    return $ali;
}

sub to_rna
{
    # Niels Larsen, March 2006.

    # Changes T's in the sequences to U's. 

    my ( $ali,       # Alignment
         ) = @_;

    # Returns alignment.

    my ( $seq );

    foreach $seq ( @{ $ali->seqs } )
    {
        $seq =~ tr/Tt/Uu/;
    }

    return $ali;
}

1;

__END__

# sub subali_left_rows
# {
#     # Niels Larsen, September 2007.

#     # Scrolls "left", by creating a sub-alignment with higher-index rows. 

#     my ( $self,          # Original alignment
#          $rows,          # Original row indices
#          $begcol,        # Starting column index
#          $params,        # Parameters (see default_params)
#          ) = @_;

#     # Returns an alignment object. 

#     my ( $ali );

#     undef $params->{"ali_clipping"}->{"left"};
#     undef $params->{"ali_clipping"}->{"right"};

#     $ali = $self->subali_at( $cols->[0], $begrow,
#                              [ @{ $cols }[ 1 .. $#{ $cols } ] ], undef, 
#                              $params->{"ali_data_rows"} - 1, undef, $params );
    
#     return $ali;
# }

# sub _nums_beg
# {
#     # Niels Larsen, July 2005.

#     # Gets sequence numbers for left edge of slice. If the alignment
#     # is not a slice, initialize to zeroes. The 1D piddle returned 
#     # contains 0-based numbers. 

#     my ( $self,       # Current alignment 
#          ) = @_;

#     # Returns a 1D piddle or nothing. 

#     my ( $orig_col_end, $orig_rows, $nums, $seqs, $orig_row, $i, 
#          $row, $end, @nums, $colmax, $rowmax, $begs, $coldim, $rowdim );

#     # Generate PDL of numbers using the original rows,

#     if ( not defined ( $orig_rows = $self->_orig_rows ) )
#     {
#         $orig_rows = PDL->new( [ 0 .. $self->max_row ] );
#     }
    
#         if ( defined ( $begs = $self->begs ) )
#         {
#             ( $coldim, $rowdim ) = $begs->dims;

#             $colmax = $coldim - 1;
#             $rowmax = $rowdim - 1;

#             for ( $row = 0; $row <= $rowmax; $row++ )
#             {
#                 push @nums, ${ $begs->slice("0:$colmax,($row)")->get_dataref } * 1;
#             }

#             $nums = PDL->new( \@nums );
#         }
#         else {
#             $nums = PDL->zeroes( $orig_rows->nelem );
#         }

#         # Count non-gaps all the way from beginning of alignment. PDL is so
#         # fast that this naive way is insignificant, at least for non-genomic
#         # alignments, 

#         $seqs = $orig->seqs;

#         if ( defined $self->_orig_cols ) {
#             $orig_col_end = $self->_orig_cols->at( 0 );
#         } else {
#             $orig_col_end = 0;
#         }
        
#         for ( $i = 0; $i < $nums->nelem; $i++ )
#         {
#             $orig_row = $orig_rows->at( $i );
#             $nums->index( $i ) += $orig->seq_count( $orig_row, 0, $orig_col_end );
#         }
        
#         $self->{"seq_nums_beg"} = $nums;
#     }

#     if ( exists $self->{"seq_nums_beg"} ) {
#         return $self->{"seq_nums_beg"};
#     } else {
#         return;
#     }
# }

# sub _nums_end
# {
#     # Niels Larsen, July 2005.

#     # Returns sequence numbers for the right edge of a given alignment. If an
#     # alignment is given as argument, numbers are calculated, otherwise the 
#     # existing numbers are returned. The original alignment is used for the 
#     # numbers, since some of the data may be hidden.

#     my ( $self,          # Alignment object
#          $orig,          # Original alignment - OPTIONAL
#          ) = @_;

#     # Returns a 1D piddle or nothing. 

#     my ( $nums_beg, $nums_end, $row, $orig_col_beg, $orig_col_end, 
#          $orig_cols, $orig_rows, $orig_row, $seq, $ends, $beg, $end, 
#          $count );

#     if ( $orig )
#     {
#         # Use the begin-numbers to make the end-numbers from, 
        
#         $nums_beg = $self->_nums_beg;
#         $nums_end = $nums_beg->copy();

#         # Original column and row numbers (which we need to count
#         # the characters), 

#         if ( defined ( $orig_cols = $self->_orig_cols ) ) {
#             $orig_col_beg = $orig_cols->at( 0 );
#             $orig_col_end = $orig_cols->at( $self->max_col );
#         } else {
#             $orig_col_beg = 0;
#             $orig_col_end = $self->max_col;
#         }
        
#         if ( not defined ( $orig_rows = $self->_orig_rows ) ) {
#             $orig_rows = PDL->new( [ 0 .. $self->max_row ] );
#         }

#         # Simply use PDL's where function on a slice,

#         $ends = $self->ends;

#         for ( $row = 0; $row < $nums_beg->nelem; $row++ )
#         {
#             $orig_row = $orig_rows->at( $row );
#             $seq = $orig->seqs->slice( $orig_col_beg+1 .":$orig_col_end,($orig_row)");
#             $count = $seq->where( $seq > 60 )->nelem;

#             $beg = $nums_beg->at( $row );

#             if ( $count and defined $ends )
#             {
#                 $end = ${ $ends->slice(":,($row)")->get_dataref } * 1;

#                 if ( $beg > $end ) {
#                     $nums_end->index( $row ) .= $beg - $count;
#                 } else {
#                     $nums_end->index( $row ) .= $beg + $count;
#                 }
#             }
#         }

#         $self->{"seq_nums_end"} = $nums_end;
#     }        

#     if ( exists $self->{"seq_nums_end"} ) {
#         return $self->{"seq_nums_end"};
#     } else {
#         return;
#     }
# }

# (Earlier stuff and garbage can from here on, but dont delete)


# sub score_alignment_two
# {
#     # Niels Larsen, June 2005.

#     # Counts the number of mismatches, insertions and deletions in an 
#     # alignment. The alignment is a list of [ beg1, end1, beg2, end2, len ]
#     # which tells where the matches are between two molecular sequences 
#     # or whatever else. 
    
#     my ( $matches,        # List of matches 
#          $aliend,         # Alignment end position - OPTIONAL
#          $seq1,
#          $seq2,
#          $is_match,
#          ) = @_;

#     my ( $score, $i, $j, $k, $diff1, $diff2, $beg1, $p_end1, $beg2, $p_end2, $ch1, $ch2 );

#     $beg1 = $matches->[0]->[0];
#     $beg2 = $matches->[0]->[2];

#     $diff1 = $beg1;
#     $diff2 = $beg2;

#     $score = 0;

#     if ( $diff1 == $diff2 and $diff1 > 0 )
#     {
#         for ( $i = 0; $i <= $diff1; $i++ )
#         {
#             $ch1 = substr $seq1, $i, 1;
#             $ch2 = substr $seq2, $i, 1;

#             $score += 1 if not $is_match->{ $ch1 }->{ $ch2 };
#         }
#     }
#     elsif ( $diff1 != $diff2 ) {
#         $score = &Common::Util::max( abs ( $diff1 - $diff2 ), &Common::Util::min( $diff1, $diff2 ) );
#     }

#     for ( $i = 1; $i <= $#{ $matches }; $i++ )
#     {
#         $beg1 = $matches->[$i]->[0];
#         $beg2 = $matches->[$i]->[2];

#         $p_end1 = $matches->[$i-1]->[1];
#         $p_end2 = $matches->[$i-1]->[3];
        
#         $diff1 = $beg1 - $p_end1 - 1;
#         $diff2 = $beg2 - $p_end2 - 1;

#         if ( $diff1 == $diff2 )
#         {
#             for ( $j = $p_end1 + 1; $j <= $beg1 - 1; $j++ )
#             {
#                 $ch1 = substr $seq1, $j, 1;
#                 $ch2 = substr $seq2, $j, 1;
                
#                 $score += 1 if not $is_match->{ $ch1 }->{ $ch2 };
#             }
#         }
#         else {
#             $score += &Common::Util::max( abs ( $diff1 - $diff2 ), &Common::Util::min( $diff1, $diff2 ) );
#         }
#     }

#     if ( defined $aliend )
#     {
#         $p_end1 = $matches->[-1]->[1];
#         $p_end2 = $matches->[-1]->[3];

#         $diff1 = (length $seq1) - $p_end1 - 1;
#         $diff2 = (length $seq2) - $p_end2 - 1;
        
#         if ( $diff1 == $diff2 )
#         {
#             $k = $p_end2 + 1;

#             for ( $j = $p_end1 + 1; $j <= $aliend; $j++ )
#             {
#                 $ch1 = substr $seq1, $j, 1;
#                 $ch2 = substr $seq2, $k, 1;
                
#                 $score += 1 if not $is_match->{ $ch1 }->{ $ch2 };
#                 $k += 1;
#             }
#         }
#         else {
#             $score += &Common::Util::max( abs ( $diff1 - $diff2 ), &Common::Util::min( $diff1, $diff2 ) );
#         }
#     }    
        
#     return $score;
# }

# 1;

# __END__

# sub seqs_list
# {
#     # Niels Larsen, January 2006.

#     # Returns all alignment data as a list of lists. It is meant for 
#     # pulling out helix regions for example, to create statistics etc. 
#     # So use it on smaller slices only, or all the RAM may be gone. 

#     my ( $self,      # Alignment
#          ) = @_;

#     # Returns a list. 

#     my ( $list, $i );

#     for ( $i = 0; $i <= $self->max_row; $i++ )
#     {
#         push @{ $list }, [ split "", $self->seq_string( $i ) ];
#     }

#     return wantarray ? @{ $list } : $list;
# }

#     if ( $n_bool )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> BEGIN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         $orig_col_min = $orig_cols->at( 0 );
#         $orig_col_max = $orig_cols->at( -1 );

#         if ( $orig_col_min == 0 )
#         {
#             $ali->begs( $ali->begs->dice( "X", $orig_rows ) );
#         }
#         elsif ( $orig_col_min == $self->max_col )
#         {
#             $ali->begs( $ali->ends->dice( "X", $orig_rows ) );
#         }
#         else
#         {
#             $begs_pdl = $ali->begs->dice( "X", $orig_rows );

#             ( $coldim, $rowdim ) = ( $begs_pdl->dims );
#             @nums = ( 0 ) x $rowdim;
            
#             for ( $row = 0; $row < $rowdim; $row++ )
#             {
#                 $num = ${ $begs_pdl->slice( ":,$row:$row" )->get_dataref } * 1;
                
#                 $nums[ $row ] = sprintf "%".$coldim."s", $num +
#                                 $self->seq_count( $orig_rows->at( $row ), 0, $orig_col_min );
#             }

#             $ali->begs( PDL::Char->new( \@nums ) );
#         }

#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> END <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         if ( $orig_col_max == $orig_col_min )
#         {
#             $ali->ends( $ali->begs );
#         }
#         elsif ( $orig_col_max == $self->max_col )
#         {
#             $ali->ends( $ali->ends->dice( "X", $orig_rows ) );
#         }
#         else
#         {
#             $ends_pdl = $ali->begs;

#             ( $coldim, $rowdim ) = ( $begs_pdl->dims );
#             @nums = ( 0 ) x $rowdim;

#             for ( $row = 0; $row < $rowdim; $row++ )
#             {
#                 $num = ${ $nums_pdl->slice( ":,$row:$row" )->get_dataref } * 1;

#                 $nums[ $row ] = sprintf "%".$coldim."s", $num +
#                                 $self->seq_count( $orig_rows->at( $row ), $orig_col_min+1, $orig_col_max );
#             }

#             $ali->ends( PDL::Char->new( \@nums ) );
#         }
#     }
#     else
#     {
#         delete $ali->{"begs"};
#         delete $ali->{"ends"};
#     }
