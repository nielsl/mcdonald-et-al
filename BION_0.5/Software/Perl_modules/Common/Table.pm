package Common::Table;     #  -*- perl -*-

# Module with functions and methods that create, manipulate, format and
# and read/write a table. A table is an object with these fields,
# 
#   col_headers => []    List of column headers
#   row_headers => []    List of row headers
#   values => []         List of rows that are lists of values
# 
# The routines below all assume this structure. 
#
# TODO: redo most routines, merge Common::Tables into this one, and add 
# more commonly needed functions. 

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @EXPORT_OK );
require Exporter; # @ISA = qw ( Exporter );

use Scalar::Util;

@EXPORT_OK = qw (
                 &check_args
                 &col_count
                 &col_index
                 &delete_cols
                 &format_numbers_col
                 &format_to_fldsep
                 &get_col
                 &get_cols
                 &invert
                 &has_col
                 &has_row
                 &name_to_index
                 &names_to_indices
                 &new
                 &pad_rows
                 &read_table
                 &read_cols_hash
                 &read_cols_list
                 &read_col_headers
                 &row_count
                 &scale_cols
                 &set_elem_attrib
                 &sort_rows
                 &splice_col
                 &splice_row
                 &sql_table
                 &sub_table
                 &suffix_to_format
                 &sum_col
                 &sum_cols
                 &sum_rows
                 &table_to_array
                 &write_table
                  );

use Common::Config;
use Common::Messages;

use Common::Util;
use Common::File;

use vars qw ( *AUTOLOAD );

use Common::Obj;

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>> METHODS AND FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_args
{
    my ( $args,
         $defs,
        ) = @_;

    my ( $key );

    # Add defaults where not given,

    $args = &Common::Util::merge_params( $args, $defs );

    # Check none of the arguments are unknown. There are better routines to do
    # this, but this module is used during error handling, so it must be kept 
    # simple,

    foreach $key ( keys %{ $args } )
    {
        if ( not exists $defs->{ $key } ) {
            &Common::Messages::error( qq (Wrong looking argument -> "$key") );
        }
    }

    bless $args, __PACKAGE__;
    
    return $args;
}

sub col_count
{
    # Niels Larsen, October 2010.

    # Returns the number of columns in a given table.

    my ( $table,     # Table object
        ) = @_;

    # Returns integer. 

    return scalar ( @{ $table->values->[0] } );
}

sub col_index
{
    # Niels Larsen, October 2010.

    # Returns a single named index of a given table. 

    my ( $table,
         $name,
        ) = @_;

    return &Common::Table::names_to_indices( [ $name ], $table->col_headers )->[0];
}

sub delete_cols
{
    # Niels Larsen, April 2012. 

    # Deletes the columns with titles in the given list. If no column 
    # headers set or wrong column names given, thats a fatal error. 
    
    my ( $table,      # Table object
         $cols,       # List of column titles
         $fatal,      # Crash on wrong column names - OPTIONAL, default 1
        ) = @_;

    # Returns object. 

    my ( $hdrs, $vals, @ndcs, $ndx, @msgs );

    $fatal = 1 if not defined $fatal;

    $cols = [ $cols ] if not ref $cols;
    $hdrs = $table->col_headers;

    @ndcs = &Common::Table::names_to_indices( $cols, $hdrs, \@msgs );
    @ndcs = sort { $b <=> $a } @ndcs;

    &error( map { $_->[1] } @msgs ) if @msgs and $fatal;

    $vals = $table->values;

    foreach $ndx ( @ndcs )
    {
        splice @{ $hdrs }, $ndx, 1;

        map { splice @{ $_ }, $ndx, 1 } @{ $vals };
    }

    return $table;
}

sub format_numbers_col
{
    my ( $table,    # Table object 
         $format,   # Sprintf format string
         $cols,     # Column names or indices - OPTIONAL, default all
        ) = @_;
    
    my ( $ndcs, $col, $row, $i );

    if ( $cols )
    {
        if ( $table->col_headers ) {
            $ndcs = &Common::Table::names_to_indices( $cols, $table->col_headers );
        } else {
            $ndcs = $cols;
        }
    }
    else {
        $ndcs = [ 0 ... $table->col_count - 1 ];
    }

    foreach $row ( @{ $table->values } )
    {
        for ( $i = 0; $i <= $#{ $row }; $i += 1 )
        {
            $row->[$i] = sprintf $format, $row->[$i] if &Scalar::Util::looks_like_number( $row->[$i] );
        }
    }
    
    if ( $table->{"col_totals"} ) {
        $table->{"col_totals"} = [ map { sprintf $format, $_ } @{ $table->{"col_totals"} } ];
    }
        
    if ( $table->{"row_totals"} ) {
        $table->{"row_totals"} = [ map { sprintf $format, $_ } @{ $table->{"row_totals"} } ];
    }

    return $table;
}

sub format_to_fldsep
{
    my ( $format,
        ) = @_;

    my ( %fldseps );

    %fldseps = (
        "tsv" => "\t",
        "csv" => ",",
        );

    if ( not exists $fldseps{ $format } ) {
        &Common::Messages::error( qq (Unsupported file format -> "$format") );
    } 

    return $fldseps{ $format };
}

sub get_col
{
    # Niels Larsen, October 2010.

    # Returns a single named column of a given table.

    my ( $table,
         $name,
        ) = @_;

    my ( @values );

    @values = map { $_->[0] } @{ &Common::Table::get_cols( $table, [ $name ] ) };

    return wantarray ? @values : \@values;
}
    
sub get_cols
{
    # Niels Larsen, October 2010.

    # Returns an array with the columns specified by their names or indices.

    my ( $table,
         $cols,
        ) = @_;

    # Returns a list. 

    my ( $ndcs, @msgs, @values );

    if ( grep { not &Scalar::Util::looks_like_number( $_ ) } @{ $cols } )
    {
        if ( @{ $table->col_headers } ) {
            $ndcs = &Common::Table::names_to_indices( $cols, $table->col_headers, \@msgs );
        } else {
            &error( qq (Column names given, but the table has no column headers) );
        }
    }
    else {
        $ndcs = $cols;
    }

    if ( @msgs ) {
        &Common::Messages::error( [ map { $_->[1] } @msgs ] );
    }

    map { push @values, [ @{ $_ }[ @{ $ndcs } ] ] } @{ $table->values };
    
    return wantarray ? @values : \@values;
}

sub invert
{
    # Niels Larsen, October 2010.

    # Creates a table where rows become columns or vice versa.

    my ( $table,    # Table object
        ) = @_;

    # Returns a list.

    my ( $row, $i, @values, $col_headers, $row_headers );
    
    foreach $row ( @{ $table->values } )
    {
        for ( $i = 0; $i <= $#{ $row }; $i++ )
        {
            push @{ $values[$i] }, $row->[$i];
        }
    }
    
    $table->values( \@values );

    $col_headers = $table->col_headers;
    $row_headers = $table->row_headers;
    
    $table->col_headers( $row_headers );
    $table->row_headers( $col_headers );

    return $table;
}

sub has_col
{
    my ( $table,
         $name,
        ) = @_;

    if ( @{ $table->col_headers } )
    {
        $name = quotemeta $name;

        return 1 if grep /^$name$/, @{ $table->col_headers };
    }
    else {
        &Common::Messages::error( qq (No column headers) );
    }

    return;
}

sub has_row
{
    my ( $table,
         $name,
        ) = @_;

    if ( @{ $table->row_headers } )
    {
        $name = quotemeta $name;

        return 1 if grep /^$name$/, @{ $table->row_headers };
    }
    else {
        &Common::Messages::error( qq (No row headers) );
    }

    return;
}

sub name_to_index
{
    # Niels Larsen, June 2012.

    # Looks up index of the given name in a list of names. 

    my ( $name,      # Name to be converted 
         $list,      # Reference list to get indices from 
        ) = @_;

    # Returns integer.

    my ( @msgs, $ndx );

    $ndx = &Common::Table::names_to_indices([ $name ], $list, \@msgs );

    return $ndx->[0] if not @msgs;

    return;
}

sub names_to_indices
{
    # Niels Larsen, October 2010. 

    # Looks up indices of the given names in a list of names. Can be used to 
    # get the indices of column titles in a table. Integers no bigger than 
    # the max index of the reference list are not converted. Returns a list 
    # of indices of the same length as the first argument list.

    my ( $names,     # Names to be converted 
         $hdrs,      # Reference list to get indices from 
         $msgs,      # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $i, %hdrs, @ndcs, $elem, @msgs );

    %hdrs = map { $_, $_ } ( 0 ... $#{ $hdrs } );

    $i = 0;
    map { $hdrs{ $_ } = $i++ } @{ $hdrs };
    
    foreach $elem ( @{ $names } )
    {
        if ( exists $hdrs{ $elem } ) {
            push @ndcs, $hdrs{ $elem };
        } else {
            push @msgs, ["ERROR", qq (Wrong looking header -> "$elem") ];
        }
    }

    &Common::Messages::append_or_exit( \@msgs, $msgs );

    return wantarray ? @ndcs : \@ndcs;
}

sub new
{
    # Niels Larsen, October 2010.

    # Creates a Common::Table object. If the given array is "ragged", padding
    # will be added. If column and row headers are given, they will be checked
    # for length consistency.

    my ( $array,
         $args,
        ) = @_;

    # Returns a Common::Table object.
    
    my ( $defs, $table, $cols, $rows, $key, $hdrs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#    if ( not defined $array ) {
#        &Common::Messages::error( qq (No table given) );
#    } elsif ( not @{ $array } ) {
#        &Common::Messages::error( qq (The given table is empty) );
#    }

    $defs = {
        "title" => "",
        "col_headers" => [],
        "col_totals" => [],
        "row_headers" => [],
        "row_totals" => [],
        "pad_string" => "",
        "clone" => 1,
    };

    $args = &Common::Table::check_args( $args, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DEFINE FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $table = {
        "title" => "",
        "values" => [],
        "col_headers" => [],
        "row_headers" => [],
        "pad_string" => "",
    };

    bless $table, __PACKAGE__;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE TITLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->title ) {
        $table->title( $args->title );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> SET AND PAD VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set values,

    if ( $array )
    {
        if ( $args->clone ) {
            $table->values( &Storable::dclone( $array ) );
        } else {
            $table->values( $array );
        }
    }

    # Add end-padding, so all rows are equally long,
    
    if ( ref $table->values->[0] ) {
        $table = &Common::Table::pad_rows( $table, $args->pad_string );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> COLUMN TITLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $args->col_headers } )
    {
        if ( $args->clone ) {
            $table->col_headers( &Storable::dclone( $args->col_headers ) );
        } else {
            $table->col_headers( $args->col_headers );
        }

        if ( ref $table->values->[0] and 
             ( $cols = scalar @{ $table->values->[0] } ) !=         
             ( $hdrs = scalar @{ $table->col_headers }) )
        {
            &Common::Messages::error( qq ($hdrs column headers, but $cols table columns) );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROW TITLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $args->row_headers } )
    {
        if ( $args->clone ) {
            $table->row_headers( &Storable::dclone( $args->row_headers ) );
        } else {
            $table->row_headers( $args->row_headers );
        }
        
        if ( ref $table->values->[0] and 
             ( $rows = scalar @{ $table->values }) !=
             ( $hdrs = scalar @{ $table->row_headers }) ) 
        {
            &Common::Messages::error( qq ($hdrs row headers, but $rows table rows) );
        }
    }
    
    return $table;
}

sub pad_rows
{
    # Niels Larsen, September 2009.

    # Appends padding so all rows are equally long. The padding is "", 
    # but can be anything, including undef. Returns the number of 
    # paddings added.

    my ( $table,          # Table object 
         $value,          # Padding value - OPTIONAL, default ""
        ) = @_;

    # Returns integer. 

    my ( $colmax, $row );

    $value = "" if not defined $value;

    # Find highest number of columns in any row,

    $colmax = 0;

    foreach $row ( @{ $table->values } )
    {
        if ( $#{ $row } > $colmax ) {
            $colmax = $#{ $row };
        }
    }

    # Add missing elements,

    foreach $row ( @{ $table->values } )
    {
        if ( $#{ $row } < $colmax )
        {
            push @{ $row }, ( $value ) x ( $colmax - $#{ $row } );
        }
    }

    return $table;
}

sub read_table
{
    # Niels Larsen, October 2010.

    # Reads a given table from file into a Common::Table object. The 
    # arguments hash can contain these keys,
    #
    #    "col_indices" => [],           List of column names or indices to read
    #    "has_col_headers" => 1,        Whether first row is column titles
    #    "row_header_index" => undef,   Whether first column is row titles
    #    "pad_string" => "",            String to use as padding for ragged tables
    #    "format" => "tsv",             Table file format, default tab-separated
    #    "os_type" => "",               System type, "mac", "dos" or "unix"
    #    "unquote_row_headers" => 1,    Whether to remove quotes from headers
    #    "unquote_col_headers" => 1,    Whether to remove quotes from headers
    #    "unquote_values" => 1,         Whether to remove quotes from values
    #    "pack_values" => format        Whether to pack values
    #    "skip_hash_rows" => 1,         Whether to skip rows that start with #
    # 
    # The default is to regard the first line as column headers, and the 
    # rest as data. If there are row-headers in the first column, then set
    # "has_row_headers" to 1. The returned table is row-oriented, i.e. the 
    # first list dimension are the lines in the file. All routines operate 
    # on this row-orientation, but the invert routine will change to column 
    # orientation if needed.

    my ( $file,   # File path
         $args,   # Argument hash
        ) = @_;

    # Returns a Common::Table object.

    my ( $defs, $table, $format, $fldsep, $os_type, $fh, $line, $ndx, $row,
         %fldseps, $i, @ndcs, @line, @msgs, @col_headers, @row_headers, 
         @values, $linend, $select_cols, $row_hindex, $pack_format );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "col_indices" => [],            # List of column names or indices to read
        "has_col_headers" => 1,         # Whether first row is column titles
        "row_header_index" => "",       # Whether first column is row titles
        "pad_string" => "",             # String to use as padding for ragged tables
        "format" => "tsv",              # Table file format, default tab-separated
        "os_type" => "",                # System type, "mac", "dos" or "unix"
        "unquote_row_headers" => 1,     # Remove quotes from headers or not
        "unquote_col_headers" => 1,     # Remove quotes from headers or not
        "unquote_values" => 1,          # Remove remove quotes from values or not
        "pack_format" => "",
        "skip_hash_rows" => 1,          # Whether to skip rows that start with #
    };

    $args = &Common::Table::check_args( $args, $defs );

    # Convenience variables,

    if ( @{ $args->col_indices } ) {
        $select_cols = $args->col_indices;
    }

    $file = &Common::File::full_file_path( $file );

    # Guess os if not set,

    if ( not $os_type = $args->os_type ) {
        $os_type = &Common::File::guess_os( $file );
    }

    # Guess and set table format if not set explicitly,

    if ( not $format = $args->format ) {
        $format = &Common::Table::suffix_to_format( $file );
    }

    $fldsep = &Common::Table::format_to_fldsep( $format );
    $linend = &Common::Util::os_line_end( $os_type );

    $fh = &Common::File::get_read_handle( $file );

    $row_hindex = $args->row_header_index;
    
    {
        # OS dependent line end,

        local $/ = $linend;

        # >>>>>>>>>>>>>>>>>>>>>>>>> COLUMN HEADERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # If column headers wanted, take the first line, remove leading "#",
        # and splice out row-header title if present,

        if ( $args->has_col_headers )
        {
            $line = <$fh>;
            $line =~ s/\s+$//;

            @col_headers = split /$fldsep/, $line;
            $col_headers[0] =~ s/^\s*#\s*//;
            
            if ( $row_hindex ne "" ) {
                splice @col_headers, $row_hindex, 1;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>> CREATE COLUMN INDICES <<<<<<<<<<<<<<<<<<<<<<<

        if ( $select_cols )
        {
            # If there are column headers, convert those to indices, otherwise
            # use the given columns as indices,

            if ( @col_headers ) 
            {
                @ndcs = &Common::Table::names_to_indices( $select_cols, \@col_headers, \@msgs );
                @col_headers = @col_headers[ @ndcs ];
            }
            else
            {
                @ndcs = @{ $select_cols };

                foreach $ndx ( @ndcs )
                {
                    if ( $ndx !~ /^\d+$/ ) {
                        push @msgs, ["ERROR", qq (Index not numeric -> "$ndx") ];
                    }
                }
            }                    

            if ( @msgs ) {
                &Common::Messages::error( [ map { $_->[1] } @msgs ] );
            }
        }
        else
        {
            $i = 0;
            @ndcs = map { $i++ } @col_headers;
        }

        if ( $row_hindex ne "" )
        {
            @ndcs = grep { $_ != $row_hindex } @ndcs;
        }
            
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ LINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $pack_format = $args->pack_format;

        if ( $row_hindex ne "" )
        {
            if ( $pack_format )
            {
                while ( defined ( $line = <$fh> ) )
                {
                    $line =~ s/\s+$//;
                    @line = split /$fldsep/, $line;
                    
                    push @row_headers, $line[ $row_hindex ];
                    push @values, pack $pack_format, @line[ @ndcs ];
                }
            }
            else
            {
                while ( defined ( $line = <$fh> ) )
                {
                    $line =~ s/\s+$//;
                    @line = split /$fldsep/, $line;
                    
                    push @row_headers, $line[ $row_hindex ];
                    push @values, [ @line[ @ndcs ] ];
                }
            }
        }
        else 
        {
            if ( $pack_format )
            {
                while ( defined ( $line = <$fh> ) )
                {
                    $line =~ s/\s+$//;
                    @line = split /$fldsep/, $line;
                    
                    push @values, pack $pack_format, @line[ @ndcs ];
                }
            }
            else
            {
                while ( defined ( $line = <$fh> ) )
                {
                    $line =~ s/\s+$//;
                    @line = split /$fldsep/, $line;
                    
                    push @values, [ @line[ @ndcs ] ];
                }                
            }
        }

        $fh->close;
    }

    # Remove quotes,

    if ( $args->unquote_col_headers )
    {
        if ( @col_headers ) {
            @col_headers = map { $_ =~ s/^\s*["'](.+)["']\s*$/$1/; $_ } @col_headers;
        }
    }

    if ( $args->unquote_row_headers )
    {
        if ( @row_headers ) {
            @row_headers = map { $_ =~ s/^\s*["'](.+)["']\s*$/$1/; $_ } @row_headers;
        }
    }

    if ( not $pack_format )
    {
        foreach $row ( @values ) {
            @{ $row } = map { $_ =~ s/^\s*["'](.+)["']\s*$/$1/; $_ } @{ $row };
        }

        # Skip rows that start with '#',
        
        if ( $args->skip_hash_rows ) {
            @values = grep { not defined $_->[0] or $_->[0] !~ /^#/ } @values;
        }
    }

    # Create object,
    
    $table = &Common::Table::new(
        \@values, 
        {
            "col_headers" => \@col_headers,
            "row_headers" => \@row_headers,
            "pad_string" => $args->pad_string,
        });

    return $table;
}

sub read_cols_hash
{
    my ( $file,
         $args,
        ) = @_;

    my ( $keycol, $valcol, $fldsep, $line, %hash, $key, $val, $ifh );

    $keycol = 0 if not defined ( $keycol = $args->{"keycol"} );
    $valcol = 1 if not defined ( $valcol = $args->{"valcol"} );
    $fldsep = "\t" if not defined ( $fldsep = $args->{"fldsep"} );

    $ifh = &Common::File::get_read_handle( $file );

    while ( defined ( $line = <$ifh> ) )
    {
        next if $line =~ /^#/;

        chomp $line;

        ( $key, $val ) = ( split $fldsep, $line )[ $keycol, $valcol ];

        $hash{ $key } = $val;
    }
    
    &Common::File::close_handle( $ifh );

    return wantarray ? %hash : \%hash;
}

sub read_cols_list
{
    my ( $file,
         $args,
        ) = @_;

    my ( $cols, $fldsep, $line, @list, $ifh );

    $cols = [ 0 ] if not defined ( $cols = $args->{"cols"} );
    $fldsep = "\t" if not defined ( $fldsep = $args->{"fldsep"} );

    $ifh = &Common::File::get_read_handle( $file );

    while ( defined ( $line = <$ifh> ) )
    {
        next if $line =~ /^#/;

        chomp $line;

        push @list, [ ( split $fldsep, $line )[ @{ $cols } ] ];
    }
    
    &Common::File::close_handle( $ifh );

    return wantarray ? @list : \@list;
}

sub read_col_headers
{
    my ( $file,
         $args,
        ) = @_;

    my ( $defs, $os_type, $format, $fldsep, $line, @headers, $fh );

    $defs = {
        "has_row_headers" => 0,  # Whether first column is row titles
        "format" => "tsv",       # Table file format, default tab-separated
        "os_type" => "",         # System type, "mac", "dos" or "unix"
        "unquote" => 1,          # Whether to remove quotes
    };

    $args = &Common::Table::check_args( $args, $defs );

    # Set OS type, format and field separator,

    if ( not $os_type = $args->os_type ) {
        $os_type = &Common::File::guess_os( $file );
    }

    if ( not $format = $args->format ) {
        $format = &Common::Table::suffix_to_format( $file );
    }

    $fldsep = &Common::Table::format_to_fldsep( $format );

    # Read,

    $fh = &Common::File::get_read_handle( $file );

    {
        local $/ = &Common::Util::os_line_end( $os_type );

        $line = <$fh>;
    }

    &Common::File::close_handle( $fh );

    $line =~ s/\s+$//;
    @headers = split /$fldsep/, $line;
    
    # If row headers,

    if ( $args->has_row_headers )
    {
        shift @headers;
    }

    # Unquote,

    if ( $args->unquote )
    {
        @headers = map { $_ =~ s/^\s*["'](.+)["']\s*$/$1/; $_ } @headers;
    }

    return wantarray ? @headers : \@headers;
}

sub row_count
{
    # Niels Larsen, October 2010.

    # Returns the number of rows in a given table.

    my ( $table,    # Table object
        ) = @_;

    # Returns integer. 

    return scalar ( @{ $table->values } );
}

sub scale_cols
{
    # Niels Larsen, May 2012. 

    # Scales values up/down so an average so the sum totals for columns become 
    # the same. If an average target value is given, then that is used, otherwise
    # the average of the observed totals. The routine will crash unforgivingly 
    # if the elements are undefined or not numbers. When done the table values 
    # will have many decimals and should normally be reformatted. 

    my ( $table,     # Table object
         $total,     # Target average total - OPTIONAL, the observed
         $skips,
        ) = @_;

    # Returns a table object.

    my ( $col, @rows, $row, @tots, $scale, $values );
    
    if ( defined $skips ) {
        @rows = grep { not exists $skips->{ $_ } } ( 0 ... $table->row_count - 1 );
    } else {
        @rows = ( 0 ... $table->row_count - 1 );
    }

    # Get totals for the given indices,
    
    @tots = &Common::Table::sum_cols( $table );

    # Get a target average value if not given,

    if ( not defined $total )
    {
        $total = &List::Util::sum( @tots ) / scalar @tots;
    }

    # From the difference between $avg and the observed totals, create a list 
    # of scaling factors to multiply numbers in each column with,

    $values = $table->values;

    foreach $col ( 0 ... $#tots )
    {
        if ( $tots[$col] > 0 ) 
        {
            $scale = $total / $tots[$col];
            
            foreach $row ( @rows )
            {
                $values->[$row]->[$col] *= $scale;
            }
        }
    }

    return $table;
}

sub set_elem_attrib
{
    my ( $elem,
         %args,
        ) = @_;

    my ( $replace, $key, $value );

    if ( not ref $elem ) {
        $elem = { "value" => $elem };
    }
    
    $replace = $args{"replace"} || 0;

    delete $args{"replace"};

    foreach $key ( keys %args )
    {
        $value = $args{ $key };

        if ( $replace )
        {
            $elem->{ $key } = $value;
        }
        else 
        {
            if ( $key eq "style" )
            {
                if ( exists $elem->{ $key } ) {
                    $elem->{ $key } .= "; $value";
                } else {
                    $elem->{ $key } = $value;
                }
            }
            elsif ( not exists $elem->{ $key } ) {
                $elem->{ $key } = $value;
            }
        }
    }

    return $elem;
}

sub sort_rows
{
    # Niels Larsen, May 2012. 

    # Sorts the rows of the given table by the values in a single column,
    # in ascending or descending order. Returns updated table.

    my ( $table,    # Table object 
         $col,      # Column index or name
         $des,      # Descending flag - OPTIONAL, default 1
        ) = @_;

    # Returns table object.

    my ( @col );

    $des = 1 if not defined $des;

    if ( @{ $table->col_headers } ) {
        $col = &Common::Table::names_to_indices( [ $col ], $table->col_headers )->[0];
    }

    @col = map { $_->[$col] } @{ $table->values };
    
    if ( grep { not &Scalar::Util::looks_like_number( $_ ) } @col )
    {
        if ( $des ) {
            $table->values([ sort { $b->[$col] cmp $a->[$col] } @{ $table->values } ]);
        } else {
            $table->values([ sort { $a->[$col] cmp $b->[$col] } @{ $table->values } ]);
        }
    }
    else
    {
        if ( $des ) {
            $table->values([ sort { $b->[$col] <=> $a->[$col] } @{ $table->values } ]);
        } else {
            $table->values([ sort { $a->[$col] <=> $b->[$col] } @{ $table->values } ]);
        }
    }    

    return $table;
}

sub splice_col
{
    # Niels Larsen, May 2012.

    # Inserts, deletes or replaces columns as splice for lists does. If rows
    # are deleted then a two elements ( rows, row-headers ) are returned,
    # otherwise nothing. 

    my ( $tab,     # Table object 
         $ndx,     # Column index
         $len,     # Length of deletion - OPTIONAL, default 0
         $col,     # Replacement column values - OPTIONAL
         $hdr,     # Replacement column header - OPTIONAL
         ) = @_;

    # Returns two-element list or nothing.

    my ( $i, @vals, $oldhdr, $imax );

    $len = 0 if not defined $len;
    $imax = $tab->row_count - 1;

    if ( $col )
    {
        # Add or replace column values,

        if ( ref $col->[0] eq "ARRAY" ) 
        {
            for ( $i = 0; $i <= $imax; $i++ ) {
                push @vals, [ splice @{ $tab->values->[$i] }, $ndx, $len, @{ $col->[$i] } ];
            }
        }
        else
        {
            for ( $i = 0; $i <= $imax; $i++ ) {
                push @vals, [ splice @{ $tab->values->[$i] }, $ndx, $len, $col->[$i] ];
            }
        }
    }
    else
    {
        # Pop column values,
        
        for ( $i = 0; $i <= $imax; $i++ ) {
            push @vals, [ splice @{ $tab->values->[$i] }, $ndx, $len ];
        }
    }

    if ( $tab->{"col_headers"} )
    {
        # Add or pop column header value,

        if ( $col and defined $hdr  )
        {
            if ( ref $hdr eq "ARRAY" ) {
                $oldhdr = [ splice @{ $tab->{"col_headers"} }, $ndx, $len, @{ $hdr } ];
            } else {
                $oldhdr = [ splice @{ $tab->{"col_headers"} }, $ndx, $len, $hdr ];
            }                
        }
        else {
            $oldhdr = [ splice @{ $tab->{"col_headers"} }, $ndx, $len ];
        }
    }

    return ( \@vals, $oldhdr ) if $len > 0;

    return;
}
    
sub splice_row
{
    # Niels Larsen, May 2012.

    # Inserts, deletes or replaces rows as splice for lists does. If rows
    # are deleted then a two elements ( rows, row-headers ) are returned,
    # otherwise nothing. 

    my ( $tab,     # Table object 
         $ndx,     # Row index
         $len,     # Length of deletion - OPTIONAL, default 0
         $row,     # Replacement row values - OPTIONAL
         $hdr,     # Replacement row headers - OPTIONAL
         ) = @_;

    # Returns two-element list or nothing.

    my ( $i, $vals, $oldhdr, $key );

    $len = 0 if not defined $len;

    # Add / replace or pop row,

    if ( $row )
    {
        if ( ref $row->[0] eq "ARRAY" ) {
            $vals = [ splice @{ $tab->values }, $ndx, $len, @{ $row } ];
        } else {
            $vals = [ splice @{ $tab->values }, $ndx, $len, $row ];
        }
    }
    else {
        $vals = [ splice @{ $tab->values }, $ndx, $len ];
    }

    foreach $key ( "row_headers", "row_totals" )
    {
        if ( $tab->{ $key } )
        {
            if ( $row and defined $hdr  )
            {
                if ( ref $hdr eq "ARRAY" ) {
                    $oldhdr = [ splice @{ $tab->{ $key } }, $ndx, $len, @{ $hdr } ];
                } else {
                    $oldhdr = [ splice @{ $tab->{ $key } }, $ndx, $len, $hdr ];
                }                
            }
            else {
                $oldhdr = [ splice @{ $tab->{ $key } }, $ndx, $len ];
            }
        }
    }

    return ( $vals, $oldhdr ) if $len > 0;

    return;
}
    
sub sql_table
{
    # Niels Larsen, October 2010.

    # Returns a table with results from querying a given database handle
    # with a given sql string. Only the values are filled, it is up to the
    # caller to set col_headers and/or row_headers.

    my ( $dbh,
         $sql,
        ) = @_;

    # Returns a table object.

    my ( $array, $table );

    $array = &Common::DB::query_array( $dbh, $sql );

    $table = &Common::Table::new( "values" => $array );

    return wantarray ? @{ $table } : $table;
}

sub sub_table
{
    # Niels Larsen, October 2010.

    # Returns a smaller table, reduced in size by lists of indices and or 
    # match requirements.

    my ( $table,
         $args,
        ) = @_;

    # Returns a table object. 

    my ( $defs, $ndcs, %ndcs, $row, $i, $headers, $values, @headers, @values,
         $sub_table, @msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "col_names" => [],            # List of column names
        "row_names" => [],            # List of row names
        "col_indices" => [],          # List of column indices
        "row_indices" => [],          # List of row indices
        "clone" => 0,                 # Whether to copy content or just pointers
    };

    $args = &Common::Table::check_args( $args, $defs );

    if ( @{ $args->col_names } and not @{ $table->col_headers } ) {
        &error( qq (Column names given, but the table has no column headers) );
    }
    
    if ( @{ $args->row_names } and not @{ $table->row_headers } ) {
        &error( qq (Row names given, but the table has no row headers) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sub_table = &Common::Table::new(
        $table->values,
        {
            "col_headers" => $table->col_headers,
            "row_headers" => $table->row_headers,
            "clone" => 0,
        });
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COLUMNS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $args->col_names } or @{ $args->col_indices } )
    {
        if ( @{ $args->col_names } ) {
            $ndcs = &Common::Table::names_to_indices( $args->col_names, $table->col_headers, \@msgs );
        } else {
            $ndcs = $args->col_indices;
        }
        
        @values = ();
        map { push @values, [ @{ $_ }[ @{ $ndcs } ] ] } @{ $table->values };
        
        $sub_table->values( &Storable::dclone( \@values ) );

        if ( @{ $table->col_headers } ) {
            $sub_table->col_headers( &Storable::dclone( $args->col_names ) );
        }
    }
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROWS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $args->row_names } or @{ $args->row_indices } )
    {
        # Create hash of indices,

        if ( @{ $args->row_names } ) {
            $ndcs = &Common::Table::names_to_indices( $args->row_names, $table->row_headers, \@msgs );
        } else {
            $ndcs = $args->row_indices;
        }
        
        %ndcs = map { $_, 1 } @{ $ndcs };
        
        # Mandatory values,

        if ( @{ $args->col_names } or @{ $args->col_indices } ) {
            $values = $sub_table->values;
        } else {
            $values = $table->values;
        }

        @values = ();
        
        for ( $i = 0; $i <= $#{ $values }; $i++ )
        {
            if ( $ndcs{ $i } )
            {
                push @values, $values->[$i];
            }
        }            

        $sub_table->values( &Storable::dclone( \@values ) );

        # Optional headers,

        if ( @{ $table->row_headers } )
        {
            $headers = $table->row_headers;
            @headers = ();

            for ( $i = 0; $i <= $#{ $headers }; $i++ )
            {
                if ( $ndcs{ $i } )
                {
                    push @headers, $headers->[$i];
                }
            }
        
            $sub_table->row_headers( &Storable::dclone( \@headers ) );
        }
    }
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INDICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @msgs ) {
        &Common::Messages::error( [ map { $_->[1] } @msgs ] );
    }

    return $sub_table;
}

sub suffix_to_format
{
    my ( $file,
        ) = @_;

    my ( $format );

    if ( $file =~ /\.(tsv|tab|table|txt)$/ ) {
        $format = "tsv";
    } elsif ( $file =~ /\.(csv)$/ ) {
        $format = "csv";
    } else {
        $format = "tsv";
    }
    
    return $format;
}

sub sum_cols
{
    # Niels Larsen, May 2012. 

    # Returns a list of column totals for the column indices and/or names
    # given. Values must be numeric. Indices can be a mixture of names and
    # integers. 

    my ( $table,    # Table object 
         $cols,     # Indices and/or names - OPTIONAL, default all 
        ) = @_;

    # Returns a list.

    my ( $ndcs, @tots, $row, $imax );

    if ( $cols )
    {
        if ( $table->col_headers ) {
            $ndcs = &Common::Table::names_to_indices( $cols, $table->col_headers );
        } else {
            $ndcs = $cols;
        }
    }
    else {
        $ndcs = [ 0 ... $table->col_count - 1 ];
    }

    @tots = (0) x scalar @{ $ndcs };

    $imax = $#{ $ndcs };

    foreach $row ( @{ $table->values } )
    {
        map { $tots[$_] += $row->[ $ndcs->[$_] ] } ( 0 ... $imax );
    }

    if ( defined wantarray ) {
        return wantarray ? @tots : \@tots;
    } else {
        $table->{"col_totals"} = \@tots;
    }

    return;
}

sub sum_rows
{
    # Niels Larsen, May 2012. 

    # Calculates the totals for rows in a given table. In non-void
    # context returns a list of totals. In void context, sets the 
    # row_totals key in the table object. 

    my ( $table,
        ) = @_;

    my ( @tots, $ndcs, $vals, $i );

    $ndcs = [ 0 ... $table->row_count - 1 ];
    @tots = (0) x scalar @{ $ndcs };

    $vals = $table->values;

    for ( $i = 0; $i <= $#{ $ndcs }; $i += 1 )
    {
        $tots[$i] = &List::Util::sum( @{ $vals->[$i] } );
    }

    if ( defined wantarray ) {
        return wantarray ? @tots : \@tots;
    } else {
        $table->{"row_totals"} = \@tots;
    }

    return;
}

sub table_to_array
{
    # Niels Larsen, October 2009.

    # Merges headers and values into a single list of lists, while checking
    # dimensions match. 

    my ( $table,    # Table object
        ) = @_;

    # Returns a list.

    my ( @array, @col_headers, @row_headers, $i, $j );
    
    @array = @{ $table->values };
    
    if ( @row_headers = @{ $table->row_headers } )
    {
        if ( ( $i = scalar @row_headers ) != ( $j = scalar @array ) ) {
            &Common::Messages::error( qq ($i row headers but $j rows) );
        }

        for ( $i = 0; $i <= $#row_headers; $i++ )
        {
            unshift @{ $array[$i] }, $row_headers[$i];
        }
    }
    
    if ( @col_headers = @{ $table->col_headers } )
    {
        unshift @col_headers, "" if @{ $table->row_headers };

        if ( ( $i = scalar @col_headers ) != ( $j = scalar @{ $array[0] } ) ) {
            &Common::Messages::error( qq ($i column headers but $j columns) );
        }

        unshift @array, [ @col_headers ];
    }
        
    return wantarray ? @array : \@array;
}

sub write_table
{
    # Niels Larsen, October 2010.
    
    # Writes a given Common::Table object to file. The first dimension will
    # become lines in the file. There are switches for "tsv" and "csv" formats
    # (tsv default) and operating system switches "mac", "dos" or "unix" (unix
    # default). The "clobber" argument deletes existing file and "append" 
    # appends to it. Returns the number of lines in the file.

    my ( $table,   # Common::Table object
         $file,    # Output file path
         $args,    # Switches hash - OPTIONAL
        ) = @_;

    # Returns integer.

    my ( $format, $ostype, %fldseps, $fldsep, $linend, $line, $fh, $array,
         $defs, $choices, $row );

    if ( not defined $table ) {
        &Common::Messages::error( qq (No table given) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS CHECK <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "format" => "tsv",     # Table file format, default tab-separated
        "os_type" => "unix",   # System type, "mac", "dos" or "unix"
        "clobber" => 0,        # Delete existing file if any
        "append" => 0,         # Append to existing file if any
    };
    
    $args = &Common::Table::check_args( $args, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CONVERT TO ARRAY <<<<<<<<<<<<<<<<<<<<<<<<<<

    $array = &Common::Table::table_to_array( $table );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE LINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $format = $args->format;
    $ostype = $args->os_type;

    %fldseps = (
        "tsv" => "\t",
        "csv" => ",",
        );
    
    if ( $format eq "tsv" or $format eq "csv" )
    {
        $fldsep = $fldseps{ $format };
        $linend = &Common::File::line_ends()->{ $ostype };
        
        &Common::File::delete_file_if_exists( $file ) if $args->clobber;
        
        if ( $args->append ) {
            $fh = &Common::File::get_append_handle( $file );
        } else {
            $fh = &Common::File::get_write_handle( $file );
        }

        $fh->print( "# " ) if @{ $table->col_headers };

        foreach $row ( @{ $array } )
        {
            $fh->print( (join $fldsep, map { defined $_ ? $_ : '' } @{ $row }) .$linend );
        }

        $fh->close;
    }
    else {
        $choices = join ", ", ( keys %fldseps );
        &Common::Messages::error( qq (Wrong looking format -> "$format"\nChoices are: $choices ) );
    }

    return scalar @{ $table->values };
}

1;

__END__

    
# sub get_column
# {
#     my ( $table,
#          $index,
#         ) = @_;

#     my ( $col );

#     if ( $table->col_orient ) {
#         $col = $table->values->[$index];
#     } else {
#         $col = [ map { $_->[$index] } @{ $table->values } ];
#     }

#     return wantarray ? @{ $col } : $col;
# }

# sub get_row
# {
#     my ( $table,
#          $index,
#         ) = @_;

#     my ( $row );

#     if ( $table->col_orient ) {
#         $row = [ map { $_->[$index] } @{ $table->values } ];
#     } else {
#         $row = $table->values->[$index];
#     }

#     return wantarray ? @{ $row } : $row;
# }

# sub set_row
# {
#     my ( $table,
#          $rowndx,
#          $elems,
#         ) = @_;

#     my ( $row, $values, $i, $maxndx, $rowlen, $col_orient );
    
#     $values = $table->values;
#     $col_orient = $table->col_orient;

#     if ( $col_orient )
#     {
#         $rowlen = scalar @{ $values };
#         $maxndx = $#{ $values->[0] };
#     }
#     else
#     {
#         $rowlen = @{ $values->[0] };
#         $maxndx = $#{ $values };
#     }

#     if ( $rowndx > $maxndx ) {
#         &Common::Messages::error( qq (The given row index is $rowndx, but max row index is $maxndx) );
#     }
    
#     if ( $rowlen != ( $i = scalar @{ $elems } ) ) {
#         &Common::Messages::error( qq (The given row length is $i, but $rowlen is required) );
#     }
    
#     if ( $col_orient )
#     {
#         for ( $i = 0; $i <= $#{ $elems }; $i++ ) {
#             $values->[$i]->[$rowndx] = $elems->[$i];
#         }
#     }
#     else {
#         $values->[$rowndx] = $elems;
#     }

#     $table->values( $values );

#     return $table;
# }

# sub set_col
# {
#     my ( $table,
#          $colndx,
#          $elems,
#         ) = @_;

#     my ( $row, $values, $i, $maxndx, $collen, $col_orient );
    
#     $values = $table->values;
#     $col_orient = $table->col_orient;

#     if ( $col_orient )
#     {
#         $collen = scalar @{ $values->[0] };
#         $maxndx = $#{ $values };
#     }
#     else
#     {
#         $collen = @{ $values };
#         $maxndx = $#{ $values->[0] };
#     }

#     if ( $colndx > $maxndx ) {
#         &Common::Messages::error( qq (The given column index is $colndx, but max column index is $maxndx) );
#     }
    
#     if ( $collen != ( $i = scalar @{ $elems } ) ) {
#         &Common::Messages::error( qq (The given column length is $i, but $collen is required) );
#     }
    
#     if ( $col_orient )
#     {
#         $table->values->[$colndx] = $elems;
#     }
#     else
#     {
#         for ( $i = 0; $i <= $#{ $elems }; $i++ ) {
#             $values->[$i]->[$colndx] = $elems->[$i];
#         }
#     }

#     $table->values( $values );

#     return $table;
# }
