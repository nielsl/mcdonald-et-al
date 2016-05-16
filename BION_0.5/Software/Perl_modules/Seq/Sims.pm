package Seq::Sims;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Sequence similarity related routines. UNFINISHED.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

use vars qw ( *AUTOLOAD );

@EXPORT_OK = qw (
                 &seq_sims
                 &seq_sims_args
);

use Common::Config;
use Common::Messages;

use Seq::Common;
use Seq::IO;
use Seq::Align;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub seq_sims
{
    # Niels Larsen, May 2013.

    # Creates a table of sequence similarities from a table of oligo 
    # similarities. 

    my ( $args,
        ) = @_;

    my ( $defs, $recipe, $conf, $i, $j );
    
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->recipe )
    {
        $recipe = &Recipe::IO::read_recipe( $args->recipe );
        $args = &Recipe::Util::recipe_to_args( $recipe, $args );
    }

    $defs = {
        "recipe" => undef,
        "isims" => undef,
        "iseqs" => undef,
        "dbseqs" => undef,
        "osims" => undef,
        "topsim" => 0.0,
        "stats" => undef,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = &Seq::Sims::seq_sims_args( $args );

    &echo_bold("\nSimilarity conversion:\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Reference sequences indexed ... ");

    if ( not &Seq::Storage::is_indexed( $conf->dbseqs ) )
    {
        &echo_yellow("NO\n");
        &echo("   Indexing reference sequences ... ");

        &Seq::Storage::create_indices(
             {
                 "ifiles" => [ $conf->dbseqs ],
                 "progtype" => "fetch",
                 "stats" => 0,
                 "silent" => 1,
             });

        &echo_done("done\n");
    }
    else {
        &echo_done("yes\n");
    }

    &echo("   Counting seqs and sims ... ");

    $i = &Seq::Stats::count_seq_file( $conf->iseqs )->{"seq_count"};
    $j = &Common::File::count_lines( $conf->isims );

    if ( $i == $j ) {
        &echo_done("same\n");
    } else {
        &error( qq ($i sequences, but $j similarity lines\n) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> ALIGN SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    


    &echo_bold("Finished\n\n");

    return;
}

sub seq_sims_args
{
    # Niels Larsen, May 2013.

    # Checks command line arguments for seq_sims with error messages and 
    # returns a configuration hash that is convenient for the routine.

    my ( $args,
        ) = @_;

    # Returns a hash.

    my ( @msgs, %args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->isims ) {
	$args{"isims"} = &Common::File::check_files( [ $args->isims ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", qq (No input similarity table given) ];
    }

    if ( $args->iseqs ) {
	$args{"iseqs"} = &Common::File::check_files( [ $args->iseqs ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", qq (No input query sequence file given) ];
    }

    if ( $args->dbseqs ) {
	$args{"dbseqs"} = &Common::File::check_files( [ $args->dbseqs ], "efr", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", qq (No input reference sequence file given) ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $args{"topsim"} = $args->topsim;

    if ( defined $args{"topsim"} ) {
        $args{"topsim"} = &Registry::Args::check_number( $args{"topsim"}, 0, undef, \@msgs );
    }

    $args{"clobber"} = $args->clobber;
    $args{"silent"} = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<    
    
    if ( $args->osims ) {
	$args{"osims"} = &Common::File::check_files( [ $args->osims ], "!e", \@msgs )->[0];
    } else {
        push @msgs, ["ERROR", qq (No output similarity table given) ];
    }

    &append_or_exit( \@msgs );

    if ( $args->stats ) {
        $args{"stats"} = $args->stats;
    } elsif ( not defined $args->stats ) {
        $args{"stats"} = $args{"osims"} .".stats";
    } else {
        $args{"stats"} = undef;
    }
    
    if ( $args{"stats"} ) {
        &Common::File::check_files([ $args{"stats"}], "!e", \@msgs ) if not $args->clobber;
    }

    if ( @msgs ) {
        push @msgs, ["INFO", qq (Files are overwritten with --clobber) ];
    }
    
    &echo("\n") if @msgs;
    &append_or_exit( \@msgs );

    bless \%args;

    return wantarray ? %args : \%args;
}



1;

__END__
