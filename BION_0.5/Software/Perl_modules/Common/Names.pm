package Common::Names;                # -*- perl -*-

# Module with general utility functions used in many contexts.

use strict;
use warnings FATAL => qw ( all );

use Time::Local;
# use Shell qw ( head );     # Perl complains of this module, find alternative
use Cwd;
use File::Basename;
use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &archive_suffixes
                 &create_path_tuples
                 &create_org_id
                 &format_display_name
                 &format_dataset_str
                 &get_acc_from_blast_id
                 &get_db_from_blast_id
                 &get_gi_from_blast_id
                 &get_prefix
                 &get_suffix
                 &is_cgi_script
                 &is_compressed
                 &is_ftp_uri
                 &is_http_uri
                 &is_javascript_file
                 &is_local_uri
                 &is_perl_module
                 &is_perl_script
                 &is_remote_id
                 &is_stylesheet_file
                 &parse_blast_hit_name
                 &parse_serverdb_str
                 &replace_suffix
                 &strip_archive_suffix
                 &strip_suffix
                 );

use Common::Config;
use Common::Messages;

use Common::Util;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub archive_suffixes
{
    # Niels Larsen, April 2009.

    # Returns a list of recognized file archive suffixes.

    my @list = qw ( .tar .tar.gz .tgz .zip );

    return wantarray ? @list : \@list;
}

sub create_path_tuples
{
    # Niels Larsen, April 2013. 

    # Converts a flat list of paths to a list of tuples like this:
    # 
    #  [ directory-path, [ file-name, ... ] ]
    # 
    # The tuple list has as many elements as there are different directories 
    # in the input path list. The order of the output tuple list is that in 
    # which the directories first appear. 

    my ( $paths,     # List of dir/file paths
        ) = @_;

    # Returns a list.

    my ( $path, %ndcs, @list, $ndx, $dir, $name );

    $ndx = 0;

    foreach $path ( @{ $paths } )
    {
        $dir = &File::Basename::dirname( $path );
        $name = &File::Basename::basename( $path );

        if ( not defined $ndcs{ $dir } ) 
        {
            $list[ $ndx ]->[0] = $dir;
            $ndcs{ $dir } = $ndx++;
        }

        push @{ $list[ $ndcs{ $dir } ]->[1] }, $name;
    }

    return wantarray ? @list : \@list;
}
    
sub create_org_id
{
    # Niels Larsen, March 2007.

    # Example: creates a "Lac.lac." or "Lac.lac.(4)" from a string like 
    # "Lactococcus lactis subsp. cremoris MG1363". If an empty hash reference
    # is given as second argument, incremented version numbers are added 
    # when previously used short-ids are made. 

    my ( $str,           # Description line
         $sids,          # Short-id hash - OPTIONAL
         ) = @_;

    # Returns a string.

    my ( $genus, $species, $gen, $sp, $sid );

    ( $genus, $species ) = ( split " ", $str )[0..1];

    if ( length $genus > 3 )
    {
        $gen = lc substr $genus, 0, 3;
    }
    else {
        $gen = lc $genus;
    }

    if ( length $species > 3 )
    {
        $sp = lc substr $species, 0, 3;
    }
    else {
        $sp = lc $species;
    }

    $sid = (ucfirst $gen) .".";

    if ( $sp =~ /\. *$/ ) {
        $sid .= $sp;
    } else {
        $sid .= "$sp.";
    }

    if ( defined $sids )
    {
        $sids->{ $sid } += 1;

        if ( $sids->{ $sid } > 1 )
        {
            $sid .= "(". $sids->{ $sid } .")";
        }
    }

    return $sid;
}

sub format_display_name
{
    # Niels Larsen, December 2003.

    # Formats names to be displayed so they are more readable. 

    my ( $name,
         ) = @_;

    # Returns a string. 

    if ( defined $name )
    {
        $name =~ s/_/ /g;
        $name =~ s/\\ / /g;
        
        if ( $name =~ /^[a-z\d]+[ \/\-,]/ or $name =~ /^[a-z\d]+$/ ) {
            $name = ucfirst $name;
        }
    }
    else {
        &Common::Messages::error( qq (No name to format) );
    }

    return $name;
}

sub format_dataset_str
{
    my ( $dbname,
         $name, 
         $type,
        ) = @_;
    
    return "$dbname:$name:$type";
}

sub get_acc_from_blast_id
{
    # Niels Larsen, January 2007.
    
    # Returns the accession number part of a string like "gi|91087723|ref|XP_974594.1|" 
    # or "ref|XP_974594.1|" or "ref|XP_974594.1|SRP_HUMAN"

    my ( $str,
         ) = @_;

    my ( $id );

    if ( $str =~ /^(?:gi\|\d+\|)?[a-z]+\|([^\|]+)\|/ )
    {
        $id = $1;
    }
    else {
        &Common::Messages::error( qq (Wrong looking blast hit id -> "$str") );
    }

    return $id;
}

sub get_db_from_blast_id
{
    # Niels Larsen, January 2007.
    
    # Returns the database abbreviation part of strings like 
    # 
    #                x
    #   gi|91087723|ref|XP_974594.1|
    #               ref|XP_974594.1|
    #               ref|XP_974594.1|SRP_HUMAN

    my ( $str,
         ) = @_;

    my ( $id );

    if ( $str =~ /^(?:gi\|\d+\|)?([a-z]+)\|/ )
    {
        $id = $1;
    }
    else {
        &Common::Messages::error( qq (Wrong looking blast hit id -> "$str") );
    }

    return $id;
}

sub get_gi_from_blast_id
{
    # Niels Larsen, January 2007.
    
    # Returns the GI number part of a string like "gi|91087723|ref|XP_974594.1|" 
    # or "ref|XP_974594.1|" or "ref|XP_974594.1|SRP_HUMAN"

    my ( $str,
         ) = @_;

    my ( $id );

    if ( $str =~ /^gi\|(\d+)\|/ )
    {
        $id = $1;
    }
    else {
        &Common::Messages::error( qq (Wrong looking blast hit id -> "$str") );
    }

    return $id;
}

sub get_prefix
{
    # Niels Larsen, April 2007.

    # Returns 

    my ( $file,
         $char,
         ) = @_;

    my ( $name, $dir, $suffix );

    $char = "." if not defined $char;

    ( $name, $dir, $suffix ) = File::Basename::fileparse( $file );

    if ( $name =~ /^([^$char]+)/ )
    {
        if ( $dir eq "./" ) {
            return $1;
        } else {
            return "$dir$1";
        }
    } 
    else {
        &Common::Messages::error( qq (No match -> "$name") );
    }
}

sub set_path
{
    # Niels Larsen, April 2013.

    # Creates a new path from an old. First argument is an input path, from
    # which the name part up until the first period is extracted. If the 
    # second directory path argument is given, then

    my ( $path,   # Input path
         $osuf,   # Output suffix - OPTIONAL, default none
         $odir,   # Output directory - OPTIONAL, default input dir
        ) = @_;

    # Returns a string.

    my ( $dir, $name, $opath );

    $dir = &File::Basename::dirname( $path );
    $name = &File::Basename::basename( $path );
        
    if ( $name =~ /^([^\.]+)\./ or $name =~ /\.([^\.]+)\./ ) {
        $name = $1;
    } else {
        &error( qq (Wrong looking path -> "$path") );
    }
    
    if ( defined $odir )
    {
        $odir =~ s/\/$//;
        $dir = $odir;
    }

    $opath = "$dir/$name";
    $opath .= $osuf if defined $osuf;
    
    return $opath;
}

sub get_suffix
{
    my ( $file,
         ) = @_;

    if ( $file =~ /\.([^.]+)$/ ) {
        return $1;
    } else {
        return;
    }
}

sub is_cgi_script
{
    # Niels Larsen, October 2004.
    
    # Returns true if the file name ends with ".cgi".

    my ( $file,    # File path
         ) = @_;

    # Returns 1 or nothing.
    
    if ( $file =~ /\.cgi$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_compressed
{
    # Niels Larsen, January 2004.

    # Returns true is the given file name ends with .gz

    my ( $file,     # File path
         ) = @_;

    # Returns a boolean.

    if ( $file =~ /\.gz$/ ) {
        return 1;
    } else {
        return;
    }
}
    
sub is_ftp_uri
{
    # Niels Larsen, March 2003.

    # Returns true if a URI string starts with "ftp:". The path
    # must be fully expanded. 

    my ( $uri,      # Absolute file path
         ) = @_;

    # Returns 1 or nothing.
    
    if ( $uri =~ /^ftp:/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_http_uri
{
    # Niels Larsen, December 2003.

    # Returns true if a URI string starts with "http:". The path
    # must be fully expanded. 

    my ( $uri,      # Absolute file path
         ) = @_;

    # Returns 1 or nothing.
    
    if ( $uri =~ /^http:/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_javascript_file
{
    # Niels Larsen, February 2004.
    
    # Returns true if the file suffix of the given file is ".js".

    my ( $file,    # File path
         ) = @_;

    # Returns 1 or nothing. 
    
    if ( $file =~ /\.js$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_local_uri
{
    # Niels Larsen, March 2003.

    # Returns true if an URI string starts with "file:" or "/". The path
    # must be fully expanded. TODO: better checks, include non-unix systems?

    my ( $uri,      # Absolute file path
         ) = @_;

    # Returns 1 or nothing.
    
    if ( $uri =~ /^file:/ or $uri =~ /^\.?\// or -e $uri ) {
        return 1;
    } else {
        return;
    }
}

# sub is_perl_script
# {
#     # Niels Larsen, March 2003.
    
#     # Returns true if the first line of a file looks like invocation 
#     # of perl by env, e.g. "#!/usr/bin/env perl".

#     my ( $file,    # File path
#          ) = @_;

#     # Returns 1 or nothing.
    
#     if ( ( Shell::head "-n 1", $file) =~ /^\#\!.+env\s+perl/ ) {
#         return 1;
#     } else {
#         return;
#     }
# }

# sub is_perl_module
# {
#     # Niels Larsen, March 2003.

#     # Returns true if a file name ends with .pm and the first line 
#     # names a package, e.g. "package Util;".

#     my ( $file,    # File path
#          ) = @_;

#     # Returns 1 or nothing.
    
#     if ( $file =~ /\.pm*$/ and (Shell::head "-n 1", $file) =~ /^package\s+[A-Z:_a-z]+;/ ) {
#         return 1;
#     } else {
#         return;
#     }
# }

# sub is_shell_script
# {
#     # Niels Larsen, March 2003.
    
#     # Returns true if the first line of a file looks like invocation 
#     # of sh, csh, tcsh or bash, e.g. "#!/bin/sh".

#     my ( $file,    # File path
#          ) = @_;

#     # Returns 1 or nothing.
    
#     if ( ( Shell::head "-n 1", $file) =~ m/^\#\!(\/usr)?\/bin\/(sh|csh|tcsh|bash)/ ) {
#         return 1;
#     } else {
#         return;
#     }
# }

sub is_remote_id
{
    # Niels Larsen, January 2007.

    # Returns true if the given string starts with a database abbreviation,
    # then a ":" then another string which is usually an accession number.
    # Otherwise it returns nothing.

    my ( $str,
         ) = @_;

    # Returns 1 or nothing.

    if ( $str =~ /^[A-Za-z]+:[A-Za-z0-9._]+$/ ) {
        return 1;
    } else {
        return;
    }
}
    
sub is_stylesheet_file
{
    # Niels Larsen, February 2004.
    
    # Returns true if the file suffix of the given file is ".css".

    my ( $file,    # File path
         ) = @_;

    # Returns 1 or nothing. 
    
    if ( $file =~ /\.css$/ ) {
        return 1;
    } else {
        return;
    }
}

sub parse_serverdb_str
{
    my ( $str,
         $fatal,
         ) = @_;

    my ( $name, $file, $type );

    $fatal = 1 if not defined $fatal;

    ( $name, $file, $type ) = split ":", $str;

    if ( $name !~ /^[a-z_]+$/ ) {
        &Common::Messages::error( qq (Wrong looking dataset name in "$str" -> "$name") );
    }

    if ( defined $file and $file !~ /^[A-Za-z_0-9]*$/ ) {
        &Common::Messages::error( qq (Wrong looking file part of "$str" -> "$file") );
    }

    if ( defined $type and $type !~ /^[a-z_]+$/ ) {
        &Common::Messages::error( qq (Wrong looking datatype in "$str" -> "$type") );
    }

    return ( $name, $file, $type );
}

sub replace_suffix
{
    my ( $name,
         $suffix,
         ) = @_;

    $name =~ s/\.[^.]+$//;
    $name .= $suffix;

    return $name; 
}

sub replace_suffixes
{
    my ( $name,
         $suffix,
        ) = @_;

    my ( $dirname, $basename );

    $dirname = File::Basename::dirname( $name );
    $basename = File::Basename::basename( $name );
    $basename =~ s/\..+//;
    $basename .= $suffix;

    return "$dirname/$basename";
}

sub strip_archive_suffix
{
    # Niels Larsen, April 2009.

    my ( $path,
        ) = @_;

    my ( @suffixes, $suffix );

    @suffixes = &Common::Names::archive_suffixes();

    foreach $suffix ( @suffixes )
    {
        $suffix = quotemeta $suffix;

        if ( $path =~ s/$suffix$// ) {
            last;
        }
    }

    return $path;
}

sub strip_suffix
{
    # Niels Larsen, December 2006.

    # Removes the file suffix and returns the rest. 

    my ( $path,    # File path
         $expr,    # Suffix - OPTIONAL, default last . to the end
         ) = @_;

    # Returns a string.
    
    $expr ||= '\.[^.]+$';
    
#    if ( $path =~ s/$expr// ) {
    $path =~ s/$expr$//;

    return $path;
#    }

#    return;
}

1;



__END__ 


# sub parse_location_str
# {
#     # Niels Larsen, January 2007.

#     # Parses a given locator string of the form "AUCHH43:6-10,15-20,30-40"
#     # into [ "AUCHH43", [[6,10],[15,20],[30-40]]]. 

#     my ( $str,         # String
#          ) = @_;

#     # Returns a list.

#     my ( @loc, $id, @ranges, $ranges, $range );

#     if ( $str =~ /^(.+):(.+)$/ )
#     {
#         $id = $1;
#         $ranges = $2;
        
#         foreach $range ( split ",", $ranges )
#         {
#             if ( $range =~ /^(\d+)-(\d+)$/ )
#             {
#                 push @ranges, [ $1, $2 ];
#             }
#             else {
#                 &Common::Messages::error( qq (Wrong looking range -> "$range") );
#             }
#         }
#     }
#     else {
#         &Common::Messages::error( qq (Wrong looking location string -> "$str") );
#     }

#     @loc = ( $id, [ @ranges ] );
    
#     return wantarray ? @loc : \@loc;
# }

# sub format_location_str
# {
#     # Niels Larsen, January 2007.

#     # Formats a location structure into "AUCHH43:6-10,15-20,30-40". The
#     # parse_location_str does the opposite.

#     my ( $loc,          # Location 
#          ) = @_;

#     # Returns a string.

#     my ( $str );

#     $str = $loc->[0] .":". ( join ",", map { $_->[0] ."-". $_->[1] } @{ $loc->[1] } );
    
#     return $str;
# }

