package Common::Util;                # -*- perl -*-

# Module with general utility functions that can be used in any context.
# Do not use recent perl features here, the module is used before perl 
# installation. Also do not include modules from this package other than
# Common::Config and Common::Messages, as this module is used before the
# others are installed.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

use Time::Local;
use Data::Dumper;

use Common::Config;
use Common::Messages;

@EXPORT_OK = qw (
                 &abbreviate_number
                 &add_lists
                 &binary_search_numbers
                 &bsearch_num_ceil
                 &bsearch_num_floor
                 &break_string_in_half
                 &ceil
                 &color_ramp
                 &commify_number
                 &current_date_emboss
                 &current_date_mysql
                 &current_time_mysql
                 &decommify_number
                 &diff_lists
                 &dump_str
                 &epoch_to_time_string
                 &equal_values
                 &expand_number
                 &first_index
                 &group_numbers
                 &hash_keys_differ
                 &hash_values_differ
                 &hex_to_rgb
                 &integers_to_eval_str
                 &lists_differ
                 &lists_overlap
                 &mask_pool_even
                 &match_regexps
                 &max
                 &max_index_int
                 &max_len_list
                 &max_list_index
                 &max_hash_element
                 &merge_hashes
                 &merge_params
                 &min
                 &min_index_int
                 &min_list
                 &most_frequent_key
                 &multiply_lists
                 &numbers_are_equal
                 &os_line_end
                 &p_bin_selection
                 &parse_string
                 &parse_time_string
                 &random_color
                 &ranges_overlap
                 &rectangles_overlap
                 &rgb_to_hex
                 &sample_list_even
                 &sample_pool_even
                 &stringify
                 &sum
                 &time_string_to_epoch
                 &tooltip_box_size
                 &trim_strings_common
                 &uniq_check
                 &uniqify
                 &web_colors
                 );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub abbreviate_number
{
    # Niels Larsen, August 2003.

    # Formats a given, perhaps large, number to something like
    # "356M" which is better suited for display in places. 

    my ( $count,    # Integer
         ) = @_;

    # Returns a string. 

    my ( $str );

    if ( $count > 999999999999 ) {
        $str = ( sprintf "%.1f", $count/1000000000000 ) . "T";
    } elsif ( $count > 999999999 ) {
        $str = ( sprintf "%.1f", $count/1000000000 ) . "G";
    } elsif ( $count > 99999999 ) {
        $str = ( sprintf "%.0f", $count/1000000 ) . "M";
    } elsif ( $count > 9999999 ) {
        $str = ( sprintf "%.0f", $count/1000000 ) . "M";
    } elsif ( $count > 999999 ) {
        $str = ( sprintf "%.1f", $count/1000000 ) . "M";
    } elsif ( $count > 99999 ) {
        $str = ( sprintf "%.0f", $count/1000 ) . "k";
    } elsif ( $count > 9999 ) {
        $str = ( sprintf "%.0f", $count/1000 ) . "k";
    } else {
        $str = $count;
    }

    return $str;
}

sub add_lists
{
    # Niels Larsen, April 2012. 

    # Returns a list where elements are the sum of all elements at the same
    # index in the given equally long lists. For example, adding the three 
    # lists [ 1,2,3 ] + [ 1,2,3 ] + [ 1,2,3 ] returns [ 3,6,9 ]. Usage can
    # be to calculate column totals in a table for example. The given lists
    # are not changed. PDL is meant for this, but adds dependency. 

    my ( @lists,
        ) = @_;

    # Returns a list.
    
    my ( @ndcs, @sums, $list );

    @ndcs = ( 0 ... $#{ $lists[0] } );
    @sums = (0) x scalar @ndcs;

    foreach $list ( @lists )
    {
        map { $sums[$_] += $list->[$_] } @ndcs;
    }

    return wantarray ? @sums : \@sums;
}

sub binary_search_numbers
{
    # Niels Larsen, May 2004.

    # Finds the index of a given sorted array where a given number
    # would fit in the sorted order. The returned index can then
    # be used to insert the number, for example. The array may 
    # contain integers and/or floats, same for the number. 

    my ( $array,       # List of numbers
         $value,       # Lookup value 
         $ndxdown,     # 
         ) = @_;

    # Returns an integer. 

    my ( $low, $high ) = ( 0, scalar @{ $array } );
    my ( $cur );

    while ( $low < $high )
    {
        $cur = int ( ( $low + $high ) / 2 );

        if ( $array->[$cur] < $value ) {
            $low = $cur + 1;
        } else {
            $high = $cur;
        }
    }

    if ( $low >= $#{ $array } )
    {
        $low = $#{ $array };
    }
    elsif ( $ndxdown and $low > 0 and $value != $array->[$low] )
    {
        $low -= 1;
    }
    
    return $low;
}

sub bsearch_num_ceil
{
    # Niels Larsen, October 2010.

    # Finds the index of a given sorted list before which a given number
    # would belong in sorted order. The returned index can then be used 
    # to insert the number or get the closest numbers, for example. 

    my ( $nums,       # List of numbers
         $num,        # Lookup number
         ) = @_;

    # Returns an integer. 

    my ( $low, $high, $cur );

    if ( $num < $nums->[0] )
    {
        return 0;
    }
    elsif ( $num > $nums->[-1] )
    {
        return;
    }
    else 
    {
        ( $low, $high ) = ( 0, scalar @{ $nums } );
        
        while ( $low < $high )
        {
            $cur = int ( ( $low + $high ) / 2 );
            
            if ( $nums->[$cur] < $num ) {
                $low = $cur + 1;
            } else {
                $high = $cur;
            }
        }
    }
    
    return $high;
}

sub bsearch_num_floor
{
    # Niels Larsen, October 2010.

    # Finds the index of a given sorted list after which a given number
    # would belong in sorted order. The returned index can then be used 
    # to insert the number or get the closest numbers, for example. 

    my ( $nums,       # List of numbers
         $num,        # Lookup number
         ) = @_;

    # Returns an integer. 

    my ( $low, $high, $cur );

    if ( $num < $nums->[0] )
    {
        return;
    }
    elsif ( $num > $nums->[-1] )
    {
        return $#{ $nums };
    }
    else 
    {
        ( $low, $high ) = ( 0, scalar @{ $nums } );
        
        while ( $low < $high )
        {
            $cur = int ( ( $low + $high ) / 2 );
            
            if ( $nums->[$cur] < $num ) {
                $low = $cur + 1;
            } else {
                $high = $cur;
            }
        }

        if ( $num != $nums->[$low] ) {
            $low -= 1;
        }
    }
    
    return $low;
}

sub break_string_in_half
{
    # Niels Larsen, May 2008.

    # Returns two strings that are the halves of a given string.

    my ( $str,
        ) = @_;

    # Returns a list. 

    my ( $len, $len1, $substr1, $substr2 );

    $len = length $str;
    $len1 = &Common::Util::ceil( $len / 2 );
    
    $substr1 = substr $str, 0, $len1;
    
    if ( $len1 < $len ) {
        $substr2 = substr $str, $len1;
    } else {
        $substr2 = "";
    }

    return ( $substr1, $substr2 );
}

sub ceil
{
    # Niels Larsen, May 2005.

    # Returns the integer ceiling of a given number.

    my ( $x,
         ) = @_;

    # Returns an integer.

    my ( $ceil );

    if ( ( $x - int $x ) > 0 ) {
        $ceil = (int $x) + 1;
    } else {
        $ceil = $x;
    }

    return $ceil;
}
    
sub color_ramp
{
    # Niels Larsen, February 1998.

    # Creates a list of color codes like '#FF33AA' that form a
    # gradient from a given start and end color code. The length
    # of the list can be specified.

    my ( $colstr1,   # A starting color code like '#FF88CC'
         $colstr2,   # A final color code, like '#AACCCC'
         $length,    # The length of the gradient
         ) = @_;

    # Returns a list.

    $length = 100 if not defined $length;

    $colstr1 =~ s/\#//g;
    $colstr2 =~ s/\#//g;

    my ( $beg, $end, $v, $color );
    my ( $step, $off, %rgbs, @ramp );

    $off = 0;

    foreach $color ( "red", "green", "blue" )
    {
        $beg = hex substr $colstr1, $off, 2;
        $end = hex substr $colstr2, $off, 2;

        if ( $beg < $end )
        {
            $step = ( $end - $beg ) / ($length-1);

            for ( $v = $beg; $v <= ($end+1/$length); $v += $step )
            {
                push @{ $rgbs{ $color } }, (sprintf "%2.2X", int $v);
            }
        }
        elsif ( $beg > $end )
        {
            $step = ( $beg - $end ) / ($length-1);

            for ( $v = $beg; $v >= ($end-1/$length); $v -= $step )
            {
                push @{ $rgbs{ $color } }, (sprintf "%2.2X", int $v);
            }
        }
        else
        {
            @{ $rgbs{ $color } } = ( sprintf "%2.2X", $beg ) x $length;
        }

        $off += 2;
    }

    @ramp = map { "#" . $rgbs{"red"}->[$_]
                      . $rgbs{"green"}->[$_]
                      . $rgbs{"blue"}->[$_] }
                ( 0 ... $#{ $rgbs{"green"} } );

    return wantarray ? @ramp : \@ramp;
}

sub commify_number
{
    # Niels Larsen, March 2003.

    # Inserts commas into an integer or number.

    my ( $num,     # Integer or number
         ) = @_;

    # Returns a string.

    $num = reverse "$num";
    $num =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    
    return scalar reverse $num;
}

sub current_date_emboss
{
    # Niels Larsen, May 2007.

    # Returns the current date in 'DD/MM/YY' format, as EMBOSS prefers it. 

    # Returns a string.

    my ( $day, $month, $year, $date );

    ( $day, $month, $year ) = (localtime)[3..5];

    $date = (sprintf "%02.0f", $day) ."/". (sprintf "%02.0f", $month+1) ."/". (sprintf "%02.0f", $year-100);

    return $date;
}

sub current_date_mysql
{
    # Niels Larsen, August 2003.

    # Returns the current date in 'YYYY-MM-DD' format, as 
    # MySQL prefers it. 

    # Returns a string.

    my ( $day, $month, $year, $date );

    ( $day, $month, $year ) = (localtime)[3..5];

    $date = ($year+1900) ."-". (sprintf "%02.0f", $month+1) ."-". sprintf "%02.0f", $day;

    return $date;
}

sub current_time_mysql
{
    # Niels Larsen, August 2003.

    # Returns the current time in 'HH:MM:SS' format, as 
    # MySQL prefers it. 

    # Returns a string.

    my ( $sec, $min, $hour, $time );

    ( $sec, $min, $hour ) = (localtime)[0..2];

    $time = (sprintf "%02.0f", $hour) .":". (sprintf "%02.0f", $min) .":". (sprintf "%02.0f", $sec);

    return $time;
}

sub epoch_to_time_string
{
    # Niels Larsen, March 2003.

    # Converts epoch seconds to a time string. If no epoch seconds given,
    # use current. Returns a time string of the form '12-SEP-2000-04:37'.

    my ( $epoch,  # Epoch seconds - OPTIONAL
         ) = @_;

    # Returns a string.

    my ( @elems );
    
    if ( defined $epoch ) {
        @elems = (localtime( $epoch ))[0..5];
    } else {
        @elems = (localtime)[0..5];
    }
    
    return &Common::Messages::make_time_string( @elems );
}

sub decommify_number
{
    # Niels Larsen, April 2013.

    my ( $num, 
        ) = @_;

    $num =~ s/[,\.]//g;

    return $num;
}

sub diff_lists
{
    # Niels Larsen, October 2007.

    # Returns the elements in list 1 that are not in list 2. 

    my ( $list1,
         $list2,
        ) = @_;

    # Returns a list.

    my ( %list2, @list );

    %list2 = map { $_, 1 } @{ $list2 };

    @list = grep { not $list2{ $_ } } @{ $list1 };

    return wantarray ? @list : \@list;
}

sub dump_str
{
    # Niels Larsen, April 2007.

    my ( $struct,    # Reference 
         $indent,    # Integer indentation level - OPTIONAL
         ) = @_;

    # 

    $indent = 0 if not defined $indent;

    local $Data::Dumper::Indent = $indent;   # indentation level
    local $Data::Dumper::Terse = 1;          # avoids variable names
        
    return Dumper( $struct );
}

sub equal_values
{
    my ( $list,
        ) = @_;

    my ( $val, $i );

    return if not @{ $list };

    $val = $list->[0];

    for ( $i = 1; $i <= $#{ $list }; $i += 1 )
    {
        return if $list->[$i] != $val;
    }

    return 1;
}

sub expand_number
{
    # Niels Larsen, January 2006.

    # Converts a number like "134M" or "134m" or "134Mb" or "1.3mb" to a byte 
    # integer, where the M mean "megabyte". K, G, T are also understood. 

    my ( $str,
         $msgs,
         ) = @_;

    # Returns integer.

    my ( $value, $modif, $num, $msg, @msgs );

    if ( $str =~ /^(\d+)$/ )
    {
        $num = $1;
    }
    elsif ( $str =~ /^(\d*\.?\d+)(K|M|G|T)b?$/i )
    {
        $value = $1;
        $modif = lc $2;

        if ( $modif eq "k" ) {
            $num = $value * 1000;
        } elsif ( $modif eq "m" ) {
            $num = $value * 1000000;
        } elsif ( $modif eq "g" ) {
            $num = $value * 1000000000;
        } elsif ( $modif eq "t" ) {
            $num = $value * 1000000000000;
        }
        else {
            push @msgs, ["ERROR", qq (Wrong looking modifier -> "$modif") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (Wrong looking number string -> "$str") ];
    }

    &append_or_exit( \@msgs, $msgs );

    if ( defined $num ) {
        return int $num;
    }

    return;
}

sub first_index
{
    # Niels Larsen, June 2008.

    # Returns the first index of a given element in a given list. If not found 
    # nothing is returned. 

    my ( $list,
         $elem,
        ) = @_;
    
    my ( $i );

    for ( $i = 0; $i <= $#{ $list }; $i++ )
    {
        if ( $list->[$i] eq $elem ) {
            return $i;
        }
    }

    return;
}

sub group_numbers
{
    # Niels Larsen, March 2009.

    # Distributes a given list of numbers into a given number of groups, so 
    # the difference between sums of each group is minimal. Returns a list of
    # groups, where each group is a list of numbers. The logic is the dumbest 
    # and does not scale: 10000 numbers in 1000 groups takes some five seconds.

    my ( $nums,     # List of numbers
         $grps,     # Number of groups
        ) = @_;

    # Returns a hash.

    my ( @sums, @nums, $num, $min, $min_ndx, $i, @groups );

    @sums = (0) x $grps;

    @nums = sort { $b <=> $a } @{ $nums };
    $min = 0;

    foreach $num ( @nums )
    {
        $min = $sums[0];
        $min_ndx = 0;

        for ( $i = 1; $i <= $#sums; $i++ )
        {
            if ( $sums[$i] < $min )
            {
                $min = $sums[$i];
                $min_ndx = $i;
            }
        }

        $sums[$min_ndx] += $num;
        push @{ $groups[$min_ndx] }, $num;
    }

    return wantarray ? @groups : \@groups;
}
    
sub group_number_tuples
{
    # Niels Larsen, March 2009.

    # Distributes a given list of numbers into a given number of groups, so 
    # the difference between sums of each group is minimal. Returns a list of
    # groups, where each group is a list of numbers. The logic is the dumbest 
    # and does not scale: 10000 numbers in 1000 groups takes some five seconds.

    my ( $tups,     # List of number tuples
         $grps,     # Number of groups
        ) = @_;

    # Returns a hash.

    my ( @sums, @tuples, $tuple, $num, $min, $min_ndx, $i, @groups );

    @sums = (0) x $grps;

    @tuples = sort { $b->[1] <=> $a->[1] } @{ $tups };
    $min = 0;

    foreach $tuple ( @tuples )
    {
        $min = $sums[0];
        $min_ndx = 0;

        for ( $i = 1; $i <= $#sums; $i++ )
        {
            if ( $sums[$i] < $min )
            {
                $min = $sums[$i];
                $min_ndx = $i;
            }
        }

        $sums[$min_ndx] += $tuple->[1];
        push @{ $groups[$min_ndx] }, $tuple;
    }

    return wantarray ? @groups : \@groups;
}
    
sub hash_keys_differ
{
    my ( $hash1,
         $hash2,
         ) = @_;

    my ( $key );

    foreach $key ( keys %{ $hash1 } )
    {
        return 1 if not exists $hash2->{ $key };
    }

    foreach $key ( keys %{ $hash2 } )
    {
        return 1 if not exists $hash1->{ $key };
    }

    return;
}

sub hash_values_differ
{
    my ( $hash1,
         $hash2,
         ) = @_;

    my ( $key );

    if ( &Common::Util::hash_keys_differ( $hash1, $hash2 ) )
    {
        return 1;
    }
    else
    {
        foreach $key ( keys %{ $hash1 } )
        {
            return 1 if $hash1->{ $key } ne $hash2->{ $key };
        }
    }

    return;
}

sub hex_to_rgb
{
    # Niels Larsen, July 2005.

    # Converts a string like "#99CAFF" to ( r, g, b ).

    my ( $str,        # Color string 
         ) = @_;

    # Returns a list.

    my ( $r, $g, $b );

    $str =~ s/^\#//;

    $r = hex substr $str, 0, 2;
    $g = hex substr $str, 2, 2;
    $b = hex substr $str, 4, 2;

    if ( wantarray ) {
        return ( $r, $g, $b );
    } else {
        return [ $r, $g, $b ];
    }
}

sub integers_to_eval_str
{
    # Niels Larsen, July 2005.

    # Converts a list of integers to a string of the form 
    # "7..15,55,0..2", where consecutive integers are converted to 
    # ranges that can be eval'ed into the original lists. Good for 
    # preserving indices in CGI scripts for example. 

    my ( $list,       # List of integers. 
         ) = @_;

    # Returns a string.

    my ( @ranges, $beg, $end, $max, $str, $range );

    $beg = $end = 0;
    $max = $#{ $list };

    while ( $beg <= $max )
    {
        while ( $end+1 <= $max and $list->[$end+1] == $list->[$end] + 1 )
        {
            $end += 1;
        }

        push @ranges, [ $list->[$beg], $list->[$end] ];

        $beg = $end + 1;
        $end = $beg;
    }

    foreach $range ( @ranges )
    {
        if ( $range->[0] == $range->[1] ) {
            $range = $range->[0];
        } else {
            $range = "$range->[0]..$range->[1]";
        }
    }
    
    return join ",", @ranges;
}

sub lists_differ
{
    # Niels Larsen, March 2011. 

    # If the two given lists differ in length or content, then 1 is returned, 
    # otherwise nothing. 

    my ( $list1,
         $list2,
        ) = @_;

    # Returns 1 or nothing.

    my ( $i );

    if ( scalar @{ $list1 } != scalar @{ $list2 } )
    {
        return 1;
    }
    else
    {
        for ( $i = 0; $i <= $#{ $list1 }; $i += 1 )
        {
            if ( defined $list1->[$i] and
                 defined $list2->[$i] and 
                 $list1->[$i] ne $list2->[$i] )
            {
                return 1;
            }
            elsif ( not defined $list1->[$i] )
            {
                return 1 if defined $list2->[$i];
            }
            elsif ( not defined $list2->[$i] )
            {
                return 1;
            }
        }
    }
    
    return;
}

sub match_list
{
    # Niels Larsen, June 2012. 

    # Returns all matches between a list of regexes and a list of 
    # strings. If there are matches a list is returned, otherwise
    # nothing. 

    my ( $exps,
         $strs,
         $args,
        ) = @_;

    # Returns list.

    my ( @hits, $exp );

    foreach $exp ( @{ $exps } )
    {
        push @hits, grep /$exp/, @{ $strs };
    }

    if ( @hits ) {
        return wantarray ? @hits : \@hits;
    }

    return;
}

sub lists_overlap
{
    # Niels Larsen, August 2012.

    # Measures if two given lists of scalars (not references) overlap.
    # Returns 1 if they do, otherwise nothing.

    my ( $list1,
         $list2,
        ) = @_;

    # Returns 1 or nothing.

    my ( %list1, %list2 );
    
    %list1 = map { $_, 1 } @{ $list1 };
    %list2 = map { $_, 1 } @{ $list2 };
    
    if ( grep { exists $list1{ $_ } } @{ $list2 } or
         grep { exists $list2{ $_ } } @{ $list1 } )
    {
        return 1;
    }
    
    return;
}

sub mask_pool_even
{
    # Niels Larsen, March 2013. 

    # Creates a list of equally spaced 1's among zeros. The number of 
    # 1's is the sample size, and the list of the first argument.

    my ( $total,    # Total pool size
         $sample,   # Total sample size
        ) = @_;

    # Returns a list.

    my ( $incr, $i, $j, @mask );

    if ( $total >= $sample )
    {
        $incr = $total / $sample;
    }
    else {
        &error( qq (Total is $total, but sample size is $sample\n) 
                .qq (The total should be larger than the sample size) );
    }

    @mask = (0) x $total;

    $i = 0;
    $j = 0;

    while ( $j < $total )
    {
        $mask[$j] = 1;

        $i += 1;
        $j = int $i * $incr;
    }

    return wantarray ? @mask : \@mask;
}

sub match_regexps
{
    # Niels Larsen, May 2010.

    # Returns 1 if at least one expression matches a given text string.

    my ( $str,
         $regexps,
#         $all,
#         $case,
        ) = @_;

    my ( $regexp );

    foreach $regexp ( @{ $regexps } )
    {
        return 1 if $str =~ /$regexp/;
    }

    return;
}    
    
sub mismatch_list
{
    # Niels Larsen, June 2012. 

    # Returns all matches between a list of regexes and a list of 
    # strings. If there are matches a list is returned, otherwise
    # nothing. 

    my ( $exps,
         $strs,
         $args,
        ) = @_;

    # Returns list.

    my ( @hits, $exp );

    @hits = @{ $strs };

    foreach $exp ( @{ $exps } )
    {
        @hits = grep { $_ !~ /$exp/ } @hits;
    }

    if ( @hits ) {
        return wantarray ? @hits : \@hits;
    }

    return;
}

sub max
{
    # Niels Larsen, July 2004.

    # Return the smallest of two given numbers.

    my ( $x,    # Number
         $y,    # Number
         ) = @_;

    # Returns a number

    if ( $x >= $y ) {
        return $x;
    } else {
        return $y;
    }
}

sub max_len_list
{
    # Niels Larsen, July 2005.

    # Return the length of the longest element in a given list.

    my ( $list,    # List of plain scalars
         ) = @_;

    # Returns a number.

    my ( $maxlen, $len, $i );

    $maxlen = length $list->[0];

    for ( $i = 1; $i <= $#{ $list }; $i++ )
    {
        $len = length $list->[$i];
        $maxlen = $len if $len > $maxlen;
    }

    return $maxlen;
}

sub max_list_index
{
    # Niels Larsen, May 2005.

    # Return the index of the largest of the numbers in a given list.

    my ( $list,    # List of numbers
         ) = @_;

    # Returns a number.

    my ( $max_val, $max_ndx, $ndx );

    $max_val = $list->[0];
    $max_ndx = 0;

    for ( $ndx = 1; $ndx <= $#{ $list }; $ndx++ )
    {
        if ( $list->[$ndx] > $max_val )
        {
            $max_val = $list->[$ndx];
            $max_ndx = $ndx;
        }
    }

    return $max_ndx;
}

sub merge_hashes
{
    # Niels Larsen, May 2007.

    my ( $hash1,       # 
         $hash2,       # 
         ) = @_;

    # Returns a hash.

    my ( $key );

    foreach $key ( keys %{ $hash2 } )
    {
        $hash1->{ $key } = $hash2->{ $key };
    }

    return wantarray ? %{ $hash1 } : $hash1;
}

sub merge_params
{
    # Niels Larsen, April 2008.

    # Keys and values from defs are copied to params if non-existing or 
    # not defined in params. An updated params hash is returned. 

    my ( $params,       # 
         $defs,         # 
         ) = @_;

    # Returns a hash.

    my ( $key, $val );

    foreach $key ( keys %{ $defs } )
    {
        if ( defined ( $val = $defs->{ $key } ) and 
             not defined $params->{ $key } )
        {
            $params->{ $key } = $val;
        }
    }

    return wantarray ? %{ $params } : $params;
}

sub min
{
    # Niels Larsen, July 2004.

    # Return the smallest of two given numbers.

    my ( $x,    # Number
         $y,    # Number
         ) = @_;

    # Returns a number

    if ( $x <= $y ) {
        return $x;
    } else {
        return $y;
    }
}

sub min_index_int
{
    my ( $pdl,
         $val,
         ) = @_;

    my ( $ndx );

    $ndx = &PDL::Primitive::vsearch( $val, $pdl );

    return $ndx;
}  

sub min_len_list
{
    # Niels Larsen, July 2005.

    # Return the length of the shortest element in a given list.

    my ( $list,    # List of plain scalars
         ) = @_;

    # Returns a number.

    my ( $minlen, $len, $i );

    $minlen = length $list->[0];

    for ( $i = 1; $i <= $#{ $list }; $i++ )
    {
        $len = length $list->[$i];
        $minlen = $len if $len < $minlen;
    }

    return $minlen;
}

sub min_list
{
    # Niels Larsen, May 2005.

    # Return the smallest of the numbers in a given list.

    my ( $list,    # List of numbers
         ) = @_;

    # Returns a number.

    my ( $min, $num, $i );

    $min = $list->[0];

    for ( $i = 1; $i <= $#{ $list }; $i++ )
    {
        $num = $list->[$i];
        $min = $num if $num < $min;
    }

    return $min;
}

sub max_hash_element
{
    my ( $hash,
        ) = @_;

    my ( $key, $maxval, $maxkey );

    $maxval = 0;

    foreach $key ( keys %{ $hash } )
    {
        if ( $hash->{ $key } > $maxval )
        {
            $maxkey = $key;
            $maxval = $hash->{ $key };
        }
    }

    return ( $maxkey, $maxval );
}

sub multiply_lists
{
    # Niels Larsen, April 2012. 

    # Returns a list where elements are the products of all elements at the 
    # same index in the given equally long lists. For example, multiplying
    # the two lists [ 1,2,3 ] * [ 1.0, 0.5, 2 ] returns [ 1.0, 1.0, 6 ]. 
    # The given lists are not changed. PDL is meant for this, but adds 
    # dependency. 

    my ( $lists,
        ) = @_;

    # Returns a list.
    
    my ( @ndcs, @prods, $list, $i );

    @ndcs = ( 0 ... $#{ $lists->[0] } );
    @prods = @{ &Storable::dclone( $lists->[0] ) };

    for ( $i = 1; $i <= $#{ $lists }; $i += 1 )
    {
        $list = $lists->[$i];
        map { $prods[$_] *= $list->[$_] } @ndcs;
    }

    return wantarray ? @prods : \@prods;
}

sub numbers_are_equal
{
    # Niels Larsen, November 2012. 

    # Returns 1 if all numbers in a given list are the same, otherwise
    # nothing.

    my ( $list,
        ) = @_;

    # Returns 1 or nothing.

    my ( $elem, $i );

    return 1 if scalar @{ $list } == 1;

    $elem = $list->[0];

    for ( $i = 1; $i <= $#{ $list }; $i += 1 )
    {
        return if $list->[$i] != $elem;
    }

    return 1;
}

sub os_line_end
{
    my ( $sys,
        ) = @_;

    my ( %ends, $end );

    %ends = (
        "unix" => "\n",
        "dos" => "\r\n",
        "mac" => "\r",
        );

    if ( not $end = $ends{ $sys } ) {
        &Common::Messages::error( qq (Wrong looking system name -> "$sys") );
    }

    return $end;
}

sub p_bin_selection
{
    # Niels Larsen, December 2009. 

    # Calculates the probability of getting k out of n by random selection 
    # from a pool of two kinds of items. When k and n are small, the binomial
    # coefficient is used, so that factorial overflow is avoided. For larger 
    # n and k approximation to the normal distribution is used (TODO). 

    my ( $k,     # Trials ("number of white balls")
         $n,     # Choices ("total number of balls")
         $p,     # P-trial ("frequency of white balls")
        ) = @_;

    # Returns a number.

    my ( $q, $prob, @mul, @div );

    $p = 0.25 if not defined $p;
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

sub parse_time_string
{
    # Niels Larsen, March 2003.

    # Converts a time string of the form '12-SEP-2000-04:37' to a list 
    # of its elements. They are ordered the same way as in the string.

    my ( $str,    # Time string
         ) = @_;

    # Returns a string.
    
    if ( $str =~ /^(\d\d)-([A-Z]{3,3})-(\d\d\d\d)-(\d\d):(\d\d):(\d\d)/ ) {
        return ( $1*1, $2, $3*1, $4*1, $5*1, $6*1 );
    } else {
        return;
    }
}

sub parse_string
{
    # Niels Larsen, May 2010.

    # Parses a string with a given regexp, and returns $1, $2, etc in some
    # wanted way: the first way is when no third argument ($out) is given,
    # then matches are returned as a list. The second way is giving a list
    # of strings with $1, $2, etc, in them, e.g. 'MicroRNA $2 from $1'. A
    # third way is to give a hash with desired keys, and same kind of values
    # as in the second way. Returns list or hash, depending on the $out 
    # argument. 

    my ( $str,      # String to be parsed
         $exp,      # Expression that must match
         $out,      # Scaffold output with $1, $2 etc placeholders - OPTIONAL
         $msgs,     # Output messages - OPTIONAL
        ) = @_;

    # Returns list or hash.

    my ( $key, $msg, $val, @out, %out, $ref );

    if ( $str =~ /$exp/ )
    {
        if ( defined $out )
        {
            if ( ref $out )
            {
                if ( ref $out eq "ARRAY" )
                {
                    @out = map { eval qq !"$_"! } @{ $out };
                    
                    return wantarray ? @out : \@out;
                }
                elsif ( ref $out eq "HASH" )
                {
                    foreach $key ( keys %{ $out } ) {
                        $out{ $key } = eval qq !"$out->{ $key }"!;
                    }
                    
                    return wantarray ? %out : \%out;
                }
                else {
                    $ref = ref $out;
                    &Common::Messages::error( qq (Wrong looking reference type -> "$ref") );
                }
            }
            else
            {
                $out = eval qq !"$out"!;
                return $out;
            }
        }
        else
        {
            @out = $str =~ /$exp/;
            
            return wantarray ? @out : \@out;
        }
        
    }
    else
    {
        $msg = "Regex $exp does not match '$str'";
        
        if ( defined $msgs ) {
            push @{ $msgs }, ["ERROR", "Regex $exp does not match '$str'"];
        } else {
            &Common::Messages::error( $msg );
        }
    }

    return;
}

sub random_color
{
    my ( $min,
         $max,
         ) = @_;

    my ( $colstr, $diff );

    $min = 0 if not defined $min;
    $max = 255 if not defined $max;

    $diff = $max - $min;

    $colstr = &Common::Util::rgb_to_hex( ( rand $diff ) + $min,
                                         ( rand $diff ) + $min,
                                         ( rand $diff ) + $min );

    return $colstr;
}

sub range_within
{
    # Niels Larsen, August 2006.

    # Tests if range 1 is contained within range 2.

    my ( $beg1,      
         $end1,
         $beg2,
         $end2,
         ) = @_;

    # Returns 1 or 0;

    if ( $beg1 >= $beg2 and $end1 <= $end2 ) {
        return 1;
    } else {
        return 0;
    }
}

sub ranges_overlap
{
    # Niels Larsen, May 2004.

    # Tests if two ranges of numbers overlap. 

    my ( $beg1,      
         $end1,
         $beg2,
         $end2,
         ) = @_;

    # Returns 1 or 0;

    if ( $end1 < $beg2 or $end2 < $beg1 ) {
        return 0;
    } else {
        return 1;
    }
}

sub rectangles_overlap
{
    # Niels Larsen, April 2006.

    # Tests if two rectangles overlap and returns 1 if they do, 
    # otherwise 0. 

    my ( $xul1,      # Rectangle 1, X upper left
         $yul1,      # Rectangle 1, Y upper left
         $xlr1,      # Rectangle 1, X lower right
         $ylr1,      # Rectangle 1, Y lower right
         $xul2,      # Rectangle 2, X upper left
         $yul2,      # Rectangle 2, Y upper left
         $xlr2,      # Rectangle 2, X lower right
         $ylr2,      # Rectangle 2, Y lower right
         ) = @_;

    # Returns 1 or 0;

    if ( &Common::Util::ranges_overlap( $xul1, $xlr1, $xul2, $xlr2 ) and
         &Common::Util::ranges_overlap( $yul1, $ylr1, $yul2, $ylr2 ) )
    {
        return 1;
    } else {
        return 0;
    }
}

sub rgb_to_hex
{
    # Niels Larsen, July 2005.

    # Converts RGB values to a hex string used for web, like "#99CAFF"

    my ( $r,        # Red, 0-255
         $g,        # Green, 0-255
         $b,        # Blue, 0-255
         ) = @_;

    # Returns a list.

    my ( $str );

    $str = "#";
    $str .= sprintf "%2.2X", $r;
    $str .= sprintf "%2.2X", $g;
    $str .= sprintf "%2.2X", $b;

    return $str;
}    

sub sample_list_even
{
    # Niels Larsen, July 2008.

    # Returns a sub-list where elements are sampled from the original,
    # evenly across the original list and put into a new list. The newlen
    # gives the length of the new list. 

    my ( $list,
         $newlen,
        ) = @_;

    # Returns a list.

    my ( $oldlen, $offset, @list, $ndx );

    $oldlen = scalar @{ $list };

    $offset = $oldlen / $newlen;

    for ( $ndx = 0; $ndx <= $#{ $list }; $ndx += $offset )
    {
        push @list, $list->[ int $ndx ];
    }

    return wantarray ? @list : \@list;
}

sub sample_pool_even
{
    # Niels Larsen, March 2013. 

    # Creates a list of equally spaced integers, and with a given number 
    # of elements.

    my ( $total,    # Total pool size
         $sample,   # Total sample size
        ) = @_;

    # Returns a list.

    my ( $incr, $i, $j, @list );

    if ( $total > $sample )
    {
        $incr = $total / $sample;
    }
    else {
        &error( qq (Total is $total, but sample size is $sample\n) 
                .qq (The total should be larger than the sample size) );
    }

    $j = 0;
    $i = 0;

    while ( $j < $total )
    {
        push @list, $j;

        $i += 1;
        $j = int $i * $incr;
    }

    pop @list if scalar @list > $sample;

    return wantarray ? @list : \@list;
}

sub stringify
{
    my ( $struct,
         ) = @_;

    local $Data::Dumper::Terse = 1;     # avoids variable names
    local $Data::Dumper::Indent = 0;    # no indentation

    return Dumper( $struct );
}

sub sum
{
    # Niels Larsen, January 2005.

    # Returns the sum of a given list of numbers. 

    my ( $numbers,
         ) = @_;

    my ( $sum );

    $sum = 0;

    map { $sum += $_ } @{ $numbers };

    return $sum;
}

sub time_string_to_epoch
{
    # Niels Larsen, March 2003.

    # Converts a time string of the form '12-SEP-2003-04:37' to epoch 
    # seconds. If no time string is given, one is generated from the
    # current time. 

    my ( $timestr,   # Time string 
         ) = @_;

    # Returns an integer. 

    my ( $epoch, $months );

    $months = {
        "JAN" => 1,   "FEB" => 2,  "MAR" => 3,  "APR" => 4,
        "MAY" => 5,   "JUN" => 6,  "JUL" => 7,  "AUG" => 8,
        "SEP" => 9,   "OCT" => 10, "NOV" => 11, "DEC" => 12,
    };

    if ( $timestr )
    {
        if ( my ( $day, $month, $year, $hour, $min, $sec ) 
                   = &Common::Util::parse_time_string( $timestr ) )
        {
            $epoch = timelocal( $sec, $min, $hour, $day, $months->{ $month }-1, $year-1900 );
        }
        else
        {
            my $message = qq (Time string "$timestr" looks wrong);
            &Common::Messages::error( $message );
        }
    }
    else
    {
        my ( $sec, $min, $hour, $day, $month, $year ) = (localtime)[0..5];
        $epoch = timelocal( $sec, $min, $hour, $day, $month, $year );
    }
    
    return $epoch;
}

sub tooltip_box_width
{
    # Niels Larsen, June 2008.

    # Returns height and width of a tooltip with reasonable proportions.

    my ( $title,
         $text,
        ) = @_;

    my ( $width );
    
    $width = int &Common::Util::min( ( (length $text) + (length $title) ) * 3, 300 );
    $width = &Common::Util::max( $width, 150 );

    return $width;
}

sub uniqify 
{
    # Niels Larsen, February 2004.

    # Removes elements that occur more than once in a given list and 
    # and returns the result. Preserves order. 

    my ( $list,     # list 
         ) = @_;

    # Returns a list. 

    my ( %seen, @list, $elem );

    foreach $elem ( @{ $list } )
    {
        if ( not $seen{ $elem } )
        {
            push @list, $elem;
            $seen{ $elem } = 1;
        }
    }

    return wantarray ? @list : \@list;
}

sub trim_strings_common
{
    # Niels Larsen, July 2012. 

    # Removes leading and trailing characters are identical in all strings in 
    # the given list. Does not affect the input list.

    my ( $list,    # List of strings
         $begs,    # Trim beginnings flag
         $ends,    # Trim ends flag
        ) = @_;

    # Returns a list.

    my ( $imax, $imin, $same, $uniq, $llen, $i, $str, $ch, @list );

    $begs = 1 if not defined $begs;
    $ends = 1 if not defined $ends;

    @list = @{ $list };
    $llen = scalar @list;

    if ( $begs )
    {
        $i = 0;

        $imax = &List::Util::min( map { length $_ } @list );
        $same = 1;

        while ( $same and $i < $imax )
        {
            $ch = substr $list->[0], $i, 1;
            $uniq = $ch x $llen;
            
            $str = join "", map { substr $_, $i, 1 } @list;
        
            if ( $str eq $uniq ) {
                $i += 1;
            } else {
                $same = 0;
            }
        }
        
        @list = map { substr $_, $i } @list;
    }

    if ( $ends )
    {
        $i = -1;

        $imin = - &List::Util::min( map { length $_ } @list );
        $same = 1;

        while ( $same and $i > $imin )
        {
            $ch = substr $list->[0], $i, 1;
            $uniq = $ch x $llen;
            
            $str = join "", map { substr $_, $i, 1 } @list;
        
            if ( $str eq $uniq ) {
                $i -= 1;
            } else {
                $same = 0;
            }
        }
        
        @list = map { substr $_, 0, $i + 1 + length $_ } @list;
    }

    return wantarray ? @list : \@list;
}

sub uniq_check
{
    # Niels Larsen, January 2011.

    # Given a list of strings, returns a list of the unique ones plus errors
    # for those that are not.

    my ( $strs,
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $str, %seen, @unique );

    foreach $str ( @{ $strs } )
    {
        if ( exists $seen{ $str } )
        {
            push @{ $msgs }, ["ERROR", qq (Duplicate -> "$str") ];
        }
        else
        {
            $seen{ $str } = 1;
            push @unique, $str;
        }
    }

    return wantarray ? @unique : \@unique;
}

sub web_colors
{
    # Niels Larsen, February 2006.

    # 
    my ( $min,
         $max,
         $step,
         ) = @_;

    my ( @colors, $r, $g, $b );

    $min = 0 if not defined $min;
    $max = 255 if not defined $max;
    $step = 51 if not defined $step;

    for ( $b = $min; $b <= $max; $b += $step )
    {
        for ( $g = $min; $g <= $max; $g += $step )
        {
            for ( $r = $min; $r <= $max; $r += $step )
            {
                push @colors, &Common::Util::rgb_to_hex( $r, $g, $b );
            }
        }
    }

    return wantarray ? @colors : \@colors;
}

1;

__END__

# sub max_index_int
# {
#     my ( $pdl,
#          $num,
#          ) = @_;

#     my ( $ndx, $val );

#     $ndx = &PDL::Primitive::vsearch( $num, $pdl );

#     $val = &PDL::Core::at( $pdl, $ndx );

#     while ( $ndx >= 0 and $val > $num ) 
#     {
#         $val = &PDL::Core::at( $pdl, --$ndx );
#     }

#     return $ndx;
# }  


# sub integers_to_string
# {
#     # Martin Hansen, August 2002 
    
#     # Compresses a list of integer ids to a small string of characters. 
#     # In this compression, contigous runs of characters are given codes, so 
#     # that very large runs of zeros (or ones) will take up very little space.
#     # The output will look like "FFEEDBAA001HHFFAA001HEEDDCCA001HHGGE" ... 

#     my ( $ids,     # List of integers 
#          ) = @_;

#     # Returns a string. 

#     return "" if not $ids or not @{ $ids };

#     my ( @ids, $id, $mask, @codes, $substr, $code, $count, $wordlen );

#     # ------- Convert from list of integer IDs to a mask,

#     @ids = sort { $a <=> $b } @{ $ids };
#     $mask = '0' x $ids[-1];

#     foreach $id ( @ids ) {
#         ( substr $mask, $id-1, 0 ) = 1;
#     }

#     # ------- Convert from "000001010001100" .. to compressed string,

#     $wordlen ||= 4;
#     @codes = ( 'A' .. 'Z' );

#     $substr = '0' x $wordlen;
#     $code = shift @codes;
#     $count = ( $mask =~ s/$substr/$code/g );
    
#     while ( $count > 0 )
#     {
#         $substr = $code x $wordlen;
#         $code = shift @codes;
#         $count = ( $mask =~ s/$substr/$code/g );
#     }

#     @codes = ( 'a' .. 'z' );

#     $substr = '1' x $wordlen;
#     $code = shift @codes;
#     $count = ( $mask =~ s/$substr/$code/g );
    
#     while ( $count > 0 )
#     {
#         $substr = $code x $wordlen;
#         $code = shift @codes;
#         $count = ( $mask =~ s/$substr/$code/g );
#     }

#     return $mask;
# }

# sub string_to_integers
# {
#     # Martin Hansen, August 2002

#     # Unompresses a string generated by integers_to_string to a list of
#     # integer ids, like ( 1,4,5,6,60,65,100, 50000 ). 

#     my ( $c_mask,     # Compressed string made by integers_to_string
#          ) = @_;     

#     # Returns a list. 
    
#     if ( not $c_mask ) {
#         wantarray ? return () : return [];
#     }

#     my ( $pos, $b_mask, @codes, $substr, $code, $count, $wordlen, @ids );

#     # ------ Convert from "FAACA001HHGGE" to "00001010001100" ..

#     $wordlen = 4;
#     @codes = ( '0', 'A' .. 'Z' );

#     $b_mask = $c_mask;

#     while ( $#codes > 0 )
#     {
#         $code = pop @codes;
#         $substr = $codes[-1] x $wordlen;
#         $b_mask =~ s/$code/$substr/g;
#     }

#     @codes = ( '1', 'a' .. 'z' );

#     while ( $#codes > 0 )
#     {
#         $code = pop @codes;
#         $substr = $codes[-1] x $wordlen;
#         $b_mask =~ s/$code/$substr/g;
#     }

#     # ------ Convert from "00001010001100" to ( 5,7,11,12 ) ..
    
#     $pos = -1;

#     while ( ( $pos = index $b_mask, '1', $pos ) > -1 )
#     {
#         push @ids, $pos+1;
#         $pos++;
#     }

#     wantarray ? return @ids : return \@ids;
# }

# sub equal_integers
# {
#     # Niels Larsen, June 2012. 

#     # Returns a list of integers whose sum is exactly the integer
#     # part of the number given. The length of the list is determined
#     # by the second argument. 

#     my ( $tot,    # Number total
#          $len,    # List length
#         ) = @_;

#     # Returns a list.

#     my ( $num, @list, $dif, $sum, $i );

#     if ( $len > $tot ) {
#         &error( qq (List length > total) );
#     }

#     $num = int $tot / $len;
#     @list = ( $num ) x $len;

#     $sum = &List::Util::sum( @list );

#     $i = 0;

#     while ( $tot - $sum - $i )
#     {
#         $list[$i++] += 1;
#     }

#     return wantarray ? @list : \@list;
# }

