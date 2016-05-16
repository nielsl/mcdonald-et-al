package DNA::EMBL::Import;     #  -*- perl -*-

# EMBL flatfile specific parse functions. 

use strict;
use warnings;

use IO::File;
use IO::Handle;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &extract_ids
                 &get_ID
                 &get_AC
                 &get_SV
                 &get_DT
                 &get_DE
                 &get_KW
                 &get_OG
                 &get_RA
                 &get_RC
                 &get_RT
                 &get_RP
                 &get_RX
                 &get_RL
                 &get_DR
                 &get_SQ
                 &get_header_minimal
                 &get_ids
                 &get_references
                 &get_sequence
                 &get_features
                 &get_organisms
                 &log_error
                 &parse_entry
                 &parse_entry_file
                 &parse_subs
                  );

use Common::Messages;
use Common::Logs;
use Common::File;

our $Parse_subs_minimal = 
{
    "organisms" => \&DNA::EMBL::Import::get_organisms,
    "ID" => \&DNA::EMBL::Import::get_ID,
    "AC" => \&DNA::EMBL::Import::get_AC,
    "DE" => \&DNA::EMBL::Import::get_DE,
    "OS" => \&DNA::EMBL::Import::get_OS,
    "OC" => \&DNA::EMBL::Import::get_OC,
};

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub extract_ids
{
    # Niels Larsen, June 2007.

    # Returns ID and sequence version from a string that contains an
    # EMBL-style flatfile entry.

    my ( $e_ref,        # Entry string reference.
        ) = @_;
 
    # Returns a list.

    my ( $id, $sv, $substr );

    if ( ${ $e_ref } =~ /^ID\s+\S+;\s+SV\s+(\d+).+?\nAC\s+(\w+);/s )
    {
        ( $id, $sv ) = ( $2, $1 );
    }
    else {
        $substr = substr ${ $e_ref }, 0, 100;
        &error( qq (Wrong looking entry header -> "$substr") );
    }
    
    return ( $id, $sv, "" );
}

sub split_entry
{
    my ( $e_ref,
        ) = @_;

    my ( $beg, $hdrstr, $seqstr );

    $beg = index ${ $e_ref }, "\n    ";

    $hdrstr = substr ${ $e_ref }, 0, $beg + 1;

    $seqstr = substr ${ $e_ref }, $beg + 2;
    $seqstr =~ tr|\n 0123456789/||d;

    return ( \$hdrstr, \$seqstr );
}

sub get_header_minimal
{
    my ( $args,
         $msgs,
        ) = @_;
    
    my ( $fpath, $acc, @lines, $i, $i_beg, $i_end, $entry, $seq );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( infile acc ) ],
        "S:0" => [ qw ( fatal ) ],
    });

    $fpath = $args->infile;
    $acc = $args->acc;

    if ( -e $fpath ) {
        @lines = `$Common::Config::bin_dir/cat $fpath`;
    } else {
        @lines = `$Common::Config::bin_dir/zcat < $fpath.gz`;
    }

    for ( $i = 0; $i <= $#lines; $i++ )
    {
        if ( $lines[$i] =~ /^ID/ )
        {
            $i_beg = $i;
        }
        elsif ( $lines[$i] =~ /^AC   $acc/ )
        {
            $i_end = $i + 1;
            
            while ( $lines[$i_end] !~ /^\/\// )
            {
                $i_end += 1;
            }
            
            last;
        }
    }

    if ( not defined $i_beg ) {
        &error( qq (\$i_beg not defined) );
    }
    
    if ( not defined $i_end ) {
        &error( qq (\$i_end not defined) );
    }
    
    $entry =  &DNA::EMBL::Import::parse_entry( [ @lines[ $i_beg .. $i_end ] ], 
                                               $Parse_subs_minimal, $msgs );
#    $entry =  &DNA::EMBL::Import::parse_entry( [ @lines[ $i_beg .. $i_end ] ], 
#                                               undef, $msgs );

#    &dump( $entry );
    # Why not let Bioperl do all the work? because it is too slow; there is 
    # a $seqin->sequence_builder() in bioperl that does it faster, but it is
    # only implemented for GenBank (as of bioperl 1.5.2), Hilmar Lapp says.

    if ( $entry and %{ $entry } )
    {
        $seq = Bio::Seq->new(
            -description => $entry->{"description"},
            -display_id => $entry->{"id"} .".". $entry->{"version"},
            -primary_id => $acc,
            -accession_number => $entry->{"accessions"}->[0],
            -species => $entry->{"organisms"}->[0],
            -version => $entry->{"version"},
            );
    }
    elsif ( $args->fatal ) {
        &error( qq (Could not find data for this accession -> "$acc") );
    }
    
    return $seq;
}

sub get_ids
{
    # Niels Larsen, July 2003.

    # Creates a list of entry ID's from an EMBL .dat flatfile, compressed
    # with gzip or not. The entry is not parsed, but is read in chunks and 
    # the ID extracted. 

    my ( $path,    # EMBL flatfile path
         ) = @_;

    # Returns an array.

    my ( $recsep, @ids, $entry, $count );

    if ( $path =~ /\.gz$/ )
    {
        if ( not open ENTRIES, "zcat < $path |" ) {
            &error( qq (Could not read-open gzip\'ed file -> "$path") );
        }
    }
    elsif ( not open ENTRIES, "< $path" ) {
        &error( qq (Could not read-open file -> "$path") );
    }

    $recsep = $/;
    $/ = "\n//\n";
    $count = 0;

    while ( defined ( $entry = <ENTRIES> ) and $entry =~ /\w/ )
    {
        $count++;

        if ( $entry =~ /^\s*ID\s+([^ ]+)/ )
        {
            push @ids, $1;
        }
        else {
            &error( qq (Entry \#$count without an ID in file -> "$path") );
            exit;
        }
    }

    close ENTRIES;

    $/ = $recsep;

    return wantarray ? @ids : \@ids;
}

sub parse_entry
{
    # Niels Larsen, August 2005.

    # Returns an entry in parsed form from an EMBL entry, given as a list
    # of lines. Either all fields are extracted, or just some: this is 
    # determined by an optional hash where keys are the field codes and
    # values are references to the subroutines that extract the information
    # from a given field. Example,
    # 
    # "OC" => \&DNA::EMBL::Import::get_OC
    # 
    # would include the organism classification in the returned entry hash.
    # This routine reads from the file handle, splits the content into fields
    # and feeds these to the routines mentioned. Errors propagate from the 
    # called routines up to this level where they are returned in $errors; 
    # the calling routine can react to that somehow.

    my ( $report,     # EMBL entry text lines
         $subrefs,    # Hash of subroutine references
         $errors,     # Error message array
         ) = @_;

    # Returns a hash.
    
    my ( $line, $code, $text, $entry, $lines, $message, $seq );

    if ( not defined $subrefs )
    {
        $subrefs = &DNA::EMBL::Import::parse_subs;
    }

    # >>>>>>>>>>>>>>>>>>>>> SPLIT LINES IN TYPES <<<<<<<<<<<<<<<<<<<<<<<<<<

    # First we divide the entry approximately, by putting the lines with 
    # the a two-letter code we recognize under its code in a temporary 
    # hash; except the sequence which is easy to get straight away.
    
    foreach $line ( @{ $report } )
    {
        $code = substr $line, 0, 2;

        if ( exists $subrefs->{ $code } )
        {
            $text = substr $line, 2;

            if ( $code =~ /^R/ )
            {
                push @{ $lines->{"references"} }, "$code$text";
            }
            elsif ( $code eq "OS" or $code eq "OC" )
            {
                push @{ $lines->{"organisms"} }, "$code$text";
            }                
            elsif ( $code eq "  " )
            {
                $line =~ tr/ 0-9\n//d;
                $entry->{"molecule"}->{"sequence"} .= $line;
            }
            else
            {
                push @{ $lines->{ $code } }, $text;
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>> PARSE EACH LINE TYPE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Now feed each type of text to the routine that knows what to do with 
    # it; we need to make a special case of the references as it needs one
    # more argument than the others,

    foreach $code ( keys %{ $lines } )
    {
        if ( $code eq "references" ) 
        {
            $entry = &DNA::EMBL::Import::get_references( $lines->{ $code }, $subrefs, $entry, $errors );
        }
        elsif ( exists $subrefs->{ $code } )
        {
            $entry = &{ $subrefs->{ $code } }( $lines->{ $code }, $entry, $errors );
        }
        else {
            push @{ $errors }, &Common::Logs::format_error( qq ($entry->{"id"}: the code "$code" is not recognized) );
        }
    }

    return if not $entry;
    return $entry if not exists $entry->{"features"};

    # >>>>>>>>>>>>>>>>>>>>>>>> POST-PROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get taxonomy ids from the source list and add it to the list of 
    # organisms too. Makes it easier to create tables and doesnt hurt.

    if ( @{ $entry->{"features"}->{"source"} } )
    {
        my ( $source, $org, $xref, $name_to_taxid, $tid );

        if ( scalar @{ $entry->{"features"}->{"source"} } == 1 )
        {
            $source = $entry->{"features"}->{"source"}->[0];

            foreach $xref ( @{ $source->{"db_xref"} } )
            {
                if ( $xref =~ /^taxon:(\d+)$/ )
                {
                    $entry->{"organisms"}->[0]->{"taxonomy_id"} = $1;
                    last;
                }
            }
        }
        else
        {
            foreach $source ( @{ $entry->{"features"}->{"source"} } )
            {
                if ( exists $source->{"organism"} )
                {
                    foreach $xref ( @{ $source->{"db_xref"} } )
                    {
                        if ( $xref =~ /^taxon:(\d+)$/ )
                        {
                            $name_to_taxid->{ $source->{"organism"}->[0] } = $1;
                            last;
                        }
                    }
                }            
            }
            
            foreach $org ( @{ $entry->{"organisms"} } )
            {
                if ( $tid = $name_to_taxid->{ $org->{"name"} } )
                {
                    $org->{"taxonomy_id"} = $tid;
                }
                else
                {
                    $org->{"taxonomy_id"} = "";
                    push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},FT: missing taxonomy id for "$org->{'name'}") );
                }
            }
        }
    }

    return $entry;
}

sub parse_entry_file
{
    # Niels Larsen, June 2003.

    # Returns an entry in parsed form from an EMBL flatfile handle. Or only
    # some of its fields: a hash is given where keys are the field codes and
    # values are references to the subroutines that extract the information
    # from a given field. Example,
    # 
    # "OC" => \&DNA::EMBL::Import::get_OC
    # 
    # would include the organism classification in the returned entry hash.
    # This routine reads from the file handle, splits the content into fields
    # and feeds these to the routines mentioned. Errors propagate from the 
    # called routines up to this level where they are returned in $errors; 
    # the calling routine can react to that somehow.

    my ( $handle,     # File handle
         $subrefs,    # Hash of subroutine references
         $errors,     # Error message array
         ) = @_;

    # Returns a hash.
    
    my ( $line, $code, $text, $entry, $lines, $message );

    # >>>>>>>>>>>>>>>>>>>>> SPLIT LINES IN TYPES <<<<<<<<<<<<<<<<<<<<<<<<<<

    # First we divide the entry approximately, by putting the lines with 
    # the a two-letter code we recognize under its code in a temporary 
    # hash; except the sequence which is easy to get straight away.
    
    while ( defined ( $line = <$handle> ) and $line =~ /^([^\/][^\/])(.*)$/ )
    {
        $code = $1;
        $text = $2;

        if ( exists $subrefs->{ $code } )
        {
            if ( $code =~ /^R/ )
            {
                push @{ $lines->{"references"} }, "$code$text";
            }
            elsif ( $code eq "OS" or $code eq "OC" )
            {
                push @{ $lines->{"organisms"} }, "$code$text";
            }                
            elsif ( $code eq "  " )
            {
                $entry->{"molecule"}->{"sequence"} = &DNA::EMBL::Import::get_sequence( $handle, $line );
                last;
            }
            else
            {
                push @{ $lines->{ $code } }, $text;
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>> PARSE EACH LINE TYPE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Now feed each type of text to the routine that knows what to do with 
    # it; we need to make a special case of the references as it needs one
    # more argument than the others,

    foreach $code ( keys %{ $lines } )
    {
        if ( $code eq "references" ) 
        {
            $entry = &DNA::EMBL::Import::get_references( $lines->{ $code }, $subrefs, $entry, $errors );
        }
        elsif ( exists $subrefs->{ $code } )
        {
            $entry = &{ $subrefs->{ $code } }( $lines->{ $code }, $entry, $errors );
        }
        else {
            push @{ $errors }, &Common::Logs::format_error( qq ($entry->{"id"}: the code "$code" is not recognized) );
        }
    }

    return if not $entry;
    return $entry if not exists $entry->{"features"};

    # >>>>>>>>>>>>>>>>>>>>>>>> POST-PROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get taxonomy ids from the source list and add it to the list of 
    # organisms too. Makes it easier to create tables and doesnt hurt.

    if ( exists $entry->{"features"}->{"source"} and @{ $entry->{"features"}->{"source"} } )
    {
        my ( $source, $org, $xref, $name_to_taxid, $tid );

        if ( scalar @{ $entry->{"features"}->{"source"} } == 1 )
        {
            $source = $entry->{"features"}->{"source"}->[0];

            foreach $xref ( @{ $source->{"db_xref"} } )
            {
                if ( $xref =~ /^taxon:(\d+)$/ )
                {
                    $entry->{"organisms"}->[0]->{"taxonomy_id"} = $1;
                    last;
                }
            }
        }
        else
        {
            foreach $source ( @{ $entry->{"features"}->{"source"} } )
            {
                if ( exists $source->{"organism"} )
                {
                    foreach $xref ( @{ $source->{"db_xref"} } )
                    {
                        if ( $xref =~ /^taxon:(\d+)$/ )
                        {
                            $name_to_taxid->{ $source->{"organism"}->[0] } = $1;
                            last;
                        }
                    }
                }            
            }
            
#            &dump( $name_to_taxid );
#            &dump( $org->{"name"} );
#            exit;

            foreach $org ( @{ $entry->{"organisms"} } )
            {
                if ( $tid = $name_to_taxid->{ $org->{"name"} } )
                {
                    $org->{"taxonomy_id"} = $tid;
                }
                else
                {
                    $org->{"taxonomy_id"} = "";
                    push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},FT: missing taxonomy id for "$org->{'name'}") );
                }
            }
        }
    }

#    &dump( $entry );
    return $entry;
}

sub get_features
{
    # Niels Larsen, June 2003.
    
    # Returns a feature structure from a memory copy of a EMBL/GenBank/DDBJ
    # feature table text (without the FT keys). 

    my ( $lines,   # Feature table text
         $entry,   # Entry structure 
         $errors,  # Error list 
         ) = @_;

    # Returns a hash.

    my ( $line, $key, $qual, $val, $text, $features, $feature, $source, $xref, $temp );

    foreach $line ( @{ $lines } )
    {
        if ( $line =~ /^ {19,19}(.+)$/ )
        {
            $text = $1;

            if ( $text =~ /^\/(\w+)=(.+)$/ )
            {
                push @{ $feature->{ $qual } }, $val;
                $qual = $1;
                $text = $2;

                if ( $text =~ /^\"(.+)\"$/ ) {
                    $val = $1;
                } elsif ( $text =~ /^\"(.+)$/ )        {
                    $val = $1;
                } elsif ( $text =~ /^(.+)\"$/ )        {
                    $val = $1;
                } else {
                    $val = $text;
                }

                $val =~ s/\\//g;
            }
            elsif ( $text =~ /^\/(\w+)\s*$/ )
            {
                push @{ $feature->{ $qual } }, $val;
                $qual = $1;
                $text = "";
            }
            else
            {
                if ( $qual eq "translation" or $qual eq "location" ) {
                    $val .= $text;
                } else {
                    $val .= " $text";
                }
            }
        }
        elsif ( $line =~ /^ {3,3}([^ ]+) +(.+)$/ )
        {
            if ( $feature )
            {
                push @{ $feature->{ $qual } }, $val;
                push @{ $features->{ $key } }, $feature;
            }

            $key = $1;
            $qual = "location";
            $val = $2;

            $feature = {};
        }
        else
        {
            push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},FT: could not parse "$line") );
        }
    }

    if ( $feature )
    {
        push @{ $feature->{ $qual } }, $val;
        push @{ $features->{ $key } }, $feature;
    }

    $entry->{"features"} = $features;

    return $entry;
}

sub get_organisms
{
    # Niels Larsen, July 2003.

    my ( $lines,   # Unparsed text with alternating OS and OC lines
         $entry,   # Parsed entry structure
         $errors,  # List of errors
         ) = @_;

    # Returns an updated 

    my ( $os_ndx, $oc_ndx, $os_flag, $line, $orgs, $text, $i );

    $os_ndx = -1;
    $oc_ndx = -1;
    $os_flag = 0;

    foreach $line ( @{ $lines } )
    {
        if ( $line =~ /^OS\s+( .+)$/ )
        {
            $text = $1;
            $os_ndx++ if not $os_flag;

            $orgs->[ $os_ndx ]->{"name"} .= $text;

            $os_flag = 1;
        }
        elsif ( $line =~ /^OC\s+( .+)$/ )
        {
            $text = $1;

            $text =~ s/^\s*//;
            $text =~ s/\s*\.\s*$//;
        
            $oc_ndx++ if $os_flag;
            push @{ $orgs->[$oc_ndx]->{"classification"} }, split /; */, $text;

            $os_flag = 0;
        }
    }

    for ( $i = 0; $i <= $os_ndx; $i++ )
    {
        if ( $orgs->[$i]->{"name"} =~ /^([^\(]+) \((.+)\)$/ )
        {
            $orgs->[$i]->{"name"} = $1;
            $orgs->[$i]->{"common_name"} = $2;

            $orgs->[$i]->{"common_name"} =~ s/^\s*//;
            $orgs->[$i]->{"common_name"} =~ s/\s*$//;
        }
        else
        {
            $orgs->[$i]->{"common_name"} = "";
        }

        $orgs->[$i]->{"name"} =~ s/^\s*//;
        $orgs->[$i]->{"name"} =~ s/\s*$//;
    }

    $entry->{"organisms"} = $orgs;

    return $entry;
}
        
sub get_references
{
    # Niels Larsen, June 2003.

    # Returns a reference structure from memory copy of a EMBL/GenBank/DDBJ
    # entry reference text (every line that starts with 'R'). An updated 
    # $entry structure is returned. 

    my ( $lines,       # Reference text
         $routines,    # List of subroutine references
         $entry,       # Parsed entry structure
         $errors,      # Error list 
         ) = @_;

    # Returns a hash.
    
    my ( $code, $line, $text, $ref_text, $refs, $ref_num );
    
    foreach $line ( @{ $lines } )
    {
        if ( $line =~ /^(R[A-Z])   (.+)$/ )
        {
            $code = $1;
            $text = $2;

            if ( $code eq "RN" )
            {
                if ( $ref_num )
                {
                    foreach $code ( keys %{ $ref_text } )
                    {
                        $refs->{ $ref_num } = &{ $routines->{ $code } }
                                                  ( $ref_text->{ $code }, $refs->{ $ref_num }, $errors );
                    }                    
                }

                if ( $text =~ /\[(\d+)\]/ )
                {
                    $ref_num = $1;
                    undef $ref_text;
                }
            }
            else
            {
                push @{ $ref_text->{ $code } }, $text;
            }
        }
        else {
            push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'}: could not parse "$line") );
        }
    }
    
    if ( $ref_text and $ref_num )
    {
        foreach $code ( keys %{ $ref_text } )
        {
            $refs->{ $ref_num } = &{ $routines->{ $code } }
                                      ( $ref_text->{ $code }, $refs->{ $ref_num }, $errors );
        }                    
    }
    
    $entry->{"references"} = $refs;
    
    return $entry;
}

sub get_sequence
{
    # Niels Larsen, June 2003.

    # Reads a file handle one line at a time while building a sequence
    # string. Returns when the final "//" is reached. Returns an updated
    # entry where sequence is added.

    my ( $handle,   # File handle
         $line,     # Line to process before reading
         ) = @_;

    # Returns a hash.

    my ( $seq );

    while ( (substr $line, 0, 2) eq "  " )
    {
        $line =~ tr/ 0-9\n//d;
        $seq .= $line;
                    
        $line = <$handle>;
    }

    return $seq;
}

sub get_CC
{
    # Niels Larsen, June 2003.

    # Parses the CC lines from an entry and returns the comment lines
    # as a string without newlines double blanks and final period. 

    my ( $text,    # CC lines 
         $entry,    # 
         $errors,
         ) = @_;
    
    my ( $line, $string );

    foreach $line ( @{ $text } )
    {
        $string .= " $line";
    }

    $string =~ s/^\s*//;
    $string =~ s/[\.\\\s]*$//;
    $string =~ s/\s\s+/ /g;

    $entry->{"comments"} = $string;

    return $entry;
}
    
sub get_DR
{
    # Niels Larsen, June 2003.

    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line );
    
    foreach $line ( @{ $text } )
    {
        if ( $line =~ /^\s*([^ ;]+);\s*([^;]+)(?:;\s*([^ ]+))?\.$/ )
        {
            push @{ $entry->{"db_xref"} }, { "name" => $1, "id1" => $2, "id2" => $3 || "" };
        }
        else {
            push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},DR: could not parse "$line") );
        }
    }
    
    return $entry;
}

sub get_RL
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line, $string );

    foreach $line ( @{ $text } )
    {
        $string .= " $line";
    }

    $string =~ s/^\s*//;
    $string =~ s/[\\\s\.]*$//;
    $string =~ s/\s\s+/ /g;

    $entry->{"literature"} = $string;

    return $entry;
}
    
sub get_RX
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line );

    foreach $line ( @{ $text } )
    {
        if ( $line =~ /^\s*(\w+)\s*;\s*(.+)\.\s*$/ )
        {
            push @{ $entry->{"citations"} }, { "name" => $1, "id" => $2 };
        }
        else {
            push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},RX: could not parse "$line") );
        }
    }

    return $entry;
}
    
sub get_RP
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line, $string, $range );

    foreach $line ( @{ $text } )
    {
        $string .= $line;
    }

    $string =~ s/\s//g;
    
    foreach $range ( split ",", $string )
    {
        if ( $range =~ /^(\d+)-(\d+)$/ ) 
        {
            push @{ $entry->{"ranges"} }, { "beg" => $1, "end" => $2 };
        }
        else {
            push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},RP: could not parse "$range") );
        }
    }

    return $entry;
}
    
sub get_RT
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line, $string );

    foreach $line ( @{ $text } )
    {
        $string .= " $line";
    }

    $string =~ s/^\s*\"?//;
    $string =~ s/\s*;?\s*$//;
    $string =~ s/\s\s+/ /g;
    $string =~ s/[\\\"]//g;

    $entry->{"title"} = $string;

    return $entry;
}
    
sub get_RC
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line, $string );

    foreach $line ( @{ $text } )
    {
        $string .= " $line";
    }

    $string =~ s/^\s*//;
    $string =~ s/\s*$//;
    $string =~ s/\s\s+/ /g;
    $string =~ s/[\"]//g;

    $entry->{"comment"} = $string;

    return $entry;
}
    
sub get_RA
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line, $string );

    foreach $line ( @{ $text } )
    {
        $string .= " $line";
    }

    $string =~ s/^\s*//;
    $string =~ s/[\\\s]*$//;
    $string =~ s/\s\s+/ /g;

    chop $string;

    $entry->{"authors"} = $string;

    return $entry;
}
    
sub get_OG
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;

    my ( $line );

    if ( $text->[0] =~ /^ *(\w+) +(\w+) *$/ )
    {
        $entry->{"organelle"}->{"type"} = $1;
        $entry->{"organelle"}->{"name"} = $2;
    }
    elsif ( $text->[0] =~ /^ *(\w+) *$/ )
    {
        $entry->{"organelle"}->{"type"} = $1;
    }

    return $entry;
}

sub get_KW
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;

    my ( $line );

    foreach $line ( @{ $text } )
    {
        $line =~ s/^\s*//;
        $line =~ s/\s*\.\s*$//;

        push @{ $entry->{"keywords"} }, split /; */, $line;
    }

    return $entry;
}

sub get_DE
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;

    my ( $line );

    foreach $line ( @{ $text } )
    {
        $entry->{"description"} .= $line;
    }

    $entry->{"description"} =~ s/^\s*//;
    $entry->{"description"} =~ s/\s*$//;
    $entry->{"description"} =~ s/\s\s+/ /g;
    $entry->{"description"} =~ s/[\"]//g;

    return $entry;
}

sub get_DT
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;

    if ( $text->[0] =~ /^\s*(\d\d)-([A-Z][A-Z][A-Z])-(\d\d\d\d) \(Rel\. (\d+), Created\)/ )
    {
        $entry->{"created"}->{"day"} = $1;
        $entry->{"created"}->{"month"} = $2;
        $entry->{"created"}->{"year"} = $3;
        $entry->{"created"}->{"release"} = $4;
    }
    else {
        push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},DT: could not parse "$text->[0]") );
    }

    if ( $text->[1] =~ /^\s*(\d\d)-([A-Z][A-Z][A-Z])-(\d\d\d\d) \(Rel\. (\d+), Last updated, Version (\d+)\)/ )
    {
        $entry->{"updated"}->{"day"} = $1;
        $entry->{"updated"}->{"month"} = $2;
        $entry->{"updated"}->{"year"} = $3;
        $entry->{"updated"}->{"release"} = $4;
        $entry->{"updated"}->{"version"} = $5;
    }
    else {
        push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},DT: could not parse "$text->[1]") );
    }

    return $entry;
}

sub get_SV
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;

    my ( $line );

    if ( $text->[0] =~ /^\s+[^\.]+\.(\d+)/ )
    {
        $entry->{"version"} = $1;
    }
    else {
        push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'}, SV: could not parse "$text->[0]") );
    }

    return $entry;
}

sub get_AC
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line );
    
    foreach $line ( @{ $text } )
    {
        $line =~ s/^\s*//;
        $line =~ s/;\s*$//;
        
        push @{ $entry->{"accessions"} }, split /;\s*/, $line;
    }
    
    return $entry;
}

sub get_ID
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;

    if ( $text->[0] =~ /^\s+(\S+); SV (\d+); (circular|linear); ([^;]+); (\S+); (\S+); (\d+) (BP|AA)\.$/ )
    {
        $entry->{"id"} = $1;
        
        ( $entry->{"version"},
          $entry->{"topology"},
          $entry->{"molecule"}->{"type"},
          $entry->{"class"},
          $entry->{"division"},
          $entry->{"molecule"}->{"length"} ) = ( $2, $3, $4, $5, $6, $7 );
    }
    else {
        push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},ID: could not parse "$text->[0]") );
    }

    return $entry;
}

sub get_SQ
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;
    
    my ( $line );
    
    if ( $text->[0] =~ /^ *Sequence \d+ BP; (\d+) A; (\d+) C; (\d+) G; (\d+) T; (\d+) other;\s*$/ )
    {
        $entry->{"molecule"}->{"a"} = $1;
        $entry->{"molecule"}->{"c"} = $2;
        $entry->{"molecule"}->{"g"} = $3;
        $entry->{"molecule"}->{"t"} = $4;
        $entry->{"molecule"}->{"other"} = $5;
    }
    else {
        push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'}, SQ: could not parse "$text->[0]") );
    }
    
    return $entry;
}

sub log_error
{
    # Niels Larsen, July 2003.
    
    # Appends a given message to an ERRORS file in the EMBL/Parse
    # sub-directory under the configured general log directory. 

    my ( $text,   # Error message
         $type,   # Error category - OPTIONAL
         ) = @_;

    # Returns nothing.

    $text =~ s/\n/ /g;
    $type = "EMBL PARSE ERROR" if not $type;

    my ( $time_str, $script_pkg, $script_file, $script_line, $log_dir, $log_file );

    $time_str = &Common::Util::epoch_to_time_string();
    
    ( $script_pkg, $script_file, $script_line ) = caller;
    
    $log_dir = "$Common::Config::log_dir/EMBL/Parse";
    $log_file = "$log_dir/ERRORS";

    &Common::File::create_dir( $log_dir, 0 );

    if ( open LOG, ">> $log_file" )
    {
        print LOG "$time_str\t$script_pkg\t$script_file\t$script_line\t$type\t$text\n";
        close LOG;
    }
    else {
        &error( qq (Could not append-open "$log_file") );
    }

    return;
}

sub parse_subs
{
    # Niels Larsen, May 2004.

    # Returns a hash of references to code that parses
    # a particular section of an EMBL entry. 

    # Returns a hash.

    my $parse_subs = 
    {
        "R" => \&DNA::EMBL::Import::get_references,
        "organisms" => \&DNA::EMBL::Import::get_organisms,
        "RN" => "",
        "  " => \&DNA::EMBL::Import::get_sequence,
        "FT" => \&DNA::EMBL::Import::get_features,
        "ID" => \&DNA::EMBL::Import::get_ID,
        "AC" => \&DNA::EMBL::Import::get_AC,
        "SV" => \&DNA::EMBL::Import::get_SV,
        "DT" => \&DNA::EMBL::Import::get_DT,
        "DE" => \&DNA::EMBL::Import::get_DE,
        "KW" => \&DNA::EMBL::Import::get_KW,
        "OS" => \&DNA::EMBL::Import::get_OS,
        "OC" => \&DNA::EMBL::Import::get_OC,
        "OG" => \&DNA::EMBL::Import::get_OG,
        "RA" => \&DNA::EMBL::Import::get_RA,
        "RC" => \&DNA::EMBL::Import::get_RC,
        "RT" => \&DNA::EMBL::Import::get_RT,
        "RP" => \&DNA::EMBL::Import::get_RP,
        "RX" => \&DNA::EMBL::Import::get_RX,
        "RL" => \&DNA::EMBL::Import::get_RL,
        "DR" => \&DNA::EMBL::Import::get_DR,
        "SQ" => \&DNA::EMBL::Import::get_SQ,    
        "CC" => \&DNA::EMBL::Import::get_CC,
    };

    wantarray ? return %{ $parse_subs } : return $parse_subs;
}
    
1;

__END__



sub get_OC
{
    my ( $text,
         $hash,
         $errors,
         ) = @_;

    my ( $line );

    foreach $line ( @{ $text } )
    {
        $line =~ s/^\s*//;
        $line =~ s/\s*\.\s*$//;
        
        push @{ $hash->{"organism"}->{"classification"} }, split /; */, $line;
    }

    return $hash;
}

sub get_OS
{
    my ( $text,
         $hash,
         $errors,
         ) = @_;

    my ( $line, $string );

    foreach $line ( @{ $text } )
    {
        $string .= " $line";
    }

    if ( $string =~ /\(([^\)]+)\)/ )
    {
        $hash->{"organism"}->{"name"} = "$` $'";
        $hash->{"organism"}->{"common_name"} = $1;

        $hash->{"organism"}->{"common_name"} =~ s/^\s*//;
        $hash->{"organism"}->{"common_name"} =~ s/\s*$//;
    }
    else
    {
        $hash->{"organism"}->{"name"} = $string;
    }        

    $hash->{"organism"}->{"name"} =~ s/^\s*//;
    $hash->{"organism"}->{"name"} =~ s/\s*$//;
        
    return $hash;
}
