package Common::Types;                # -*- perl -*-

# Functions that define simple TYPES of things, not the things 
# themselves - for that, see the Registry.pm module. data, databases, methods and
# viewers, with strings like "rna_ali", "orgs_taxa", "dna_seq", and 
# so on. The intent is to form a little map, so one can list which
# data types a given method can work on etc. 
#
#
#No data are listed in here, there are in Registry::Get.
# 

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &ali_to_seq
                 &is_alignment
                 &is_checkboxes
                 &is_dna
                 &is_dna_or_rna
                 &is_functions
                 &is_expression
                 &is_menu
                 &is_menu_option
                 &is_organisms
                 &is_pattern
                 &is_protein
                 &is_rna
                 &is_sequence
                 &is_sims
                 &is_stats
                 &is_structure
                 &is_taxonomy
                 &is_user_data
                 &is_word_list
                 &is_word_text
                 &seq_to_ali
                 &truncate_type
                 &type_to_mol
                 &viewers
                 );

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub ali_to_seq
{
    my ( $type,
         ) = @_;

    $type =~ s/_ali/_seq/;

    return $type;
}

sub is_alignment
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_ali$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_checkboxes
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^check_$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_dna
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^dna_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_dna_or_rna
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^dna_|rna_|nuc_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_functions
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^func_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_genome
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_geno$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_expression
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^expr_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_menu
{
    my ( $obj,
         ) = @_;

    if ( ref $obj and (ref $obj) =~ /::Menu(s)?$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_menu_option
{
    my ( $obj,
         ) = @_;

    if ( ref $obj and (ref $obj) =~ /::Option$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_organisms
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^orgs_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_pattern
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_pat$/ ) {
#    if ( $str =~ /^pattern_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_protein
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^prot_/ or $str =~ /^protein_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_rna
{
    my ( $str,
         ) = @_;

    if ( $str =~ /^rna_/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_sequence
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_seq$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_sims
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_sims$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_stats
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_stats$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_structure
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_struct$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_taxonomy
{
    my ( $str,
         ) = @_;

    if ( $str =~ /_taxa$/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_user_data
{
    my ( $path,
         ) = @_;

    if ( $path =~ /^Uploads|Analyses/ ) {
        return 1;
    } else {
        return;
    }
}

sub is_user_db
{
    my ( $path,
         ) = @_;

    if ( $path =~ /^(Accounts|Temporary)\// ) {
        return 1;
    } else {
        return;
    }
}

sub is_word_list
{
    my ( $str,
        ) = @_;

    return 1 if $str eq "words_list";

    return;
}
         
sub is_word_text
{
    my ( $str,
        ) = @_;

    return 1 if $str eq "words_text";

    return;
}
         
sub seq_to_ali
{
    my ( $type,
         ) = @_;

    $type =~ s/_seq/_ali/;

    return $type;
}

sub truncate_type
{
    my ( $type,
	) = @_;

    $type =~ s/_[^_]+$//;

    return $type;
}

sub type_to_mol
{
    # Niels Larsen, September 2006.

    # Returns a readable molecule label for a given datatype.

    my ( $type,       # Type string
         ) = @_;

    # Returns a string.

    my ( $label );

    if ( &Common::Types::is_dna( $type ) ) {
        $label = "DNA";
    } elsif ( &Common::Types::is_rna( $type ) ) {
        $label = "RNA";
    } elsif ( &Common::Types::is_protein( $type ) ) {
        $label = "Protein";
    } elsif ( &Common::Types::is_organisms( $type ) ) {
        $label = "Taxonomy";
    } else {
        &Common::Messages::error( qq (Wrong looking data type -> "$type") );
    }

    return $label;
}

1;

__END__ 
