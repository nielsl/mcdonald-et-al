package DNA::Export;     #  -*- perl -*-

# Routines that fetch DNA related things out of the database. 

use strict;
use warnings;

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &format_fasta
                 &print_fasta
                  );

use Common::Config;
use Common::Messages;

#use Common::File;
#use Common::DB;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub format_fasta
{
    my ( $text,
         $seq,
         ) = @_;

    return ">$text\n$seq\n";
}

sub print_fasta
{
    my ( $text,
         $seq,
         ) = @_;

    print ">$text\n$seq\n";

    return;
}

1;
