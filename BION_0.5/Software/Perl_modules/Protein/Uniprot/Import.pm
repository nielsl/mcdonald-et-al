package Protein::Uniprot::Import;     #  -*- perl -*-

# UniProt flatfile specific functions. Very rudimentary
# and preliminary.

use strict;
use warnings;

use IO::File;
use IO::Handle;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &extract_ids
                 &get_header_minimal
		 &get_organisms
		 &get_references
		 &parse_entry
                 &split_entry
                  );

use Common::Messages;
use Common::File;

our $Parse_subs_minimal = 
{
    "ID" => \&Protein::Uniprot::Import::get_ID,
    "AC" => \&Protein::Uniprot::Import::get_AC,
    "DE" => \&Protein::Uniprot::Import::get_DE,
    "organisms" => \&Protein::Uniprot::Import::get_organisms,
    "OS" => \&Protein::Uniprot::Import::get_OS,
    "OC" => \&Protein::Uniprot::Import::get_OC,
};

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub extract_ids
{
    # Niels Larsen, August 2008.

    # Returns ID and sequence version from a string that contains an
    # entry.

    my ( $e_ref,        # Entry string reference.
        ) = @_;
 
    # Returns a list.

    my ( $id, $sv, $substr );

    if ( ${ $e_ref } =~ /\nAC\s+(\S+);[^\n]*\nDT\s+[^\n]+\nDT\s+[^\n]+sequence version (\d+)./s )
    {
        ( $id, $sv ) = ( $1, $2 );
    }
    else {
        $substr = substr ${ $e_ref }, 0, 100;
        &error( qq (Wrong looking entry header -> "$substr") );
    }
    
    return ( $id, $sv, "" );
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

sub get_header_minimal
{
    # Niels Larsen, August 2008.

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
    
    $entry =  &Protein::Uniprot::Import::parse_entry( [ @lines[ $i_beg .. $i_end ] ], 
						      $Parse_subs_minimal, $msgs );

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

sub get_ID
{
    my ( $text,
         $entry,
         $errors,
         ) = @_;

    if ( $text->[0] =~ /^\s+(\S+);?\s+([^;]+);\s+(\d+) (BP|AA)\.$/ )
    {
        $entry->{"id"} = $1;
        
        ( $entry->{"version"},
          $entry->{"topology"},
          $entry->{"molecule"}->{"type"},
          $entry->{"class"},
          $entry->{"division"},
          $entry->{"molecule"}->{"length"} ) = ( 1, "linear", "protein", $2, "", $3 );
    }
    else {
        push @{ $errors }, &Common::Logs::format_error( qq ($entry->{'id'},ID: could not parse "$text->[0]") );
    }

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

sub parse_entry
{
    # Niels Larsen, August 2008.

    # Returns an entry in parsed form from a Uniprot entry, given as a list
    # of lines. Either all fields are extracted, or just some: this is 
    # determined by an optional hash where keys are the field codes and
    # values are references to the subroutines that extract the information
    # from a given field. Example,
    # 
    # "OC" => \&Protein::Uniprot::Import::get_OC
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
        $subrefs = &Protein::Uniprot::Import::parse_subs;
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
            $entry = &Protein::Uniprot::Import::get_references( $lines->{ $code }, $subrefs, $entry, $errors );
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

sub parse_subs
{
    # Niels Larsen, May 2004.

    # Returns a hash of references to code that parses
    # a particular section of an EMBL entry. 

    # Returns a hash.

    my $parse_subs = 
    {
#        "R" => \&Protein::Uniprot::Import::get_references,
        "organisms" => \&Protein::Uniprot::Import::get_organisms,
#        "RN" => "",
        "  " => \&Protein::Uniprot::Import::get_sequence,
#        "FT" => \&Protein::Uniprot::Import::get_features,
        "ID" => \&Protein::Uniprot::Import::get_ID,
        "AC" => \&Protein::Uniprot::Import::get_AC,
#        "SV" => \&Protein::Uniprot::Import::get_SV,
#        "DT" => \&Protein::Uniprot::Import::get_DT,
        "DE" => \&Protein::Uniprot::Import::get_DE,
#        "KW" => \&Protein::Uniprot::Import::get_KW,
        "OS" => \&Protein::Uniprot::Import::get_OS,
        "OC" => \&Protein::Uniprot::Import::get_OC,
#        "OG" => \&Protein::Uniprot::Import::get_OG,
#        "RA" => \&Protein::Uniprot::Import::get_RA,
#        "RC" => \&Protein::Uniprot::Import::get_RC,
#        "RT" => \&Protein::Uniprot::Import::get_RT,
#        "RP" => \&Protein::Uniprot::Import::get_RP,
#        "RX" => \&Protein::Uniprot::Import::get_RX,
#        "RL" => \&Protein::Uniprot::Import::get_RL,
#        "DR" => \&Protein::Uniprot::Import::get_DR,
#        "SQ" => \&Protein::Uniprot::Import::get_SQ,    
#        "CC" => \&Protein::Uniprot::Import::get_CC,
    };

    wantarray ? return %{ $parse_subs } : return $parse_subs;
}
    
sub split_entry
{
    # Niels Larsen, August 2008. 

    my ( $e_ref,
        ) = @_;

    my ( $beg, $hdrstr, $seqstr );

    $beg = index ${ $e_ref }, "\n    ";

    $hdrstr = substr ${ $e_ref }, 0, $beg + 1;

    $seqstr = substr ${ $e_ref }, $beg + 2;
    $seqstr =~ tr|\n 0123456789/||d;

    return ( \$hdrstr, \$seqstr );
}


1;

__END__

# sub get_header_minimal_broken
# {
#     my ( $args,
#          $msgs,
#         ) = @_;
    
#     my ( $fpath, $acc, $lines, $i, $i_beg, $i_end, $entries, 
#          $entry, $seq, $seqin, $builder, $fh, $cmd, $version,
#          $species, $orgstr, $taxstr );
    
#     $args = &Registry::Args::check( $args, {
#         "S:2" => [ qw ( infile acc ) ],
#         "S:0" => [ qw ( fatal ) ],
#     });

#     $fpath = $args->infile;
#     $acc = $args->acc;

#     if ( -e $fpath ) {
#         $cmd = "$Common::Config::bin_dir/cat $fpath";
#     } else {
#         $cmd = "$Common::Config::bin_dir/zcat < $fpath.gz";
#     }

# #    $entries = &Common::OS::run_command( $cmd );
#     $entries = `$cmd`;   # TODO

#     while ( $entries =~ m|(ID   .+?//\n)|gs )
#     {
#         $entry = $1;
#         last if $entry =~ m|\nAC\s+$acc|s;
#     }

#     $fh = new IO::String( $entry );

#     $seqin = Bio::SeqIO->new( -fh => $fh, -format => "swiss" );
#     $builder = $seqin->sequence_builder();

#     $builder->want_none();
#     $builder->add_wanted_slot( 'accession_number', 'primary_id', 'version',
#                                'display_id', 'desc', 'species' );

#     $entry = $seqin->next_seq();

#     $version = $entry->version || 1;         # Sometimes undefined

#     if ( $species = $entry->species ) {
#         $orgstr = $species->binomial;
#     } else {
#         $orgstr = "";
#     }

# #    $taxstr = join ";", $species->classification;

# #    &dump( $taxstr );

#     $seq = Bio::Seq->new(
#         -description => $entry->desc,
#         -display_id => $entry->display_id .".$version",
#         -primary_id => $entry->primary_id ,
#         -accession_number => $entry->accession_number,
#         -species => $species,
#         -version => $version,
#         );
    
#     return $seq;
# };
