package Seq::Clean;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that somehow clean sequences: quality and length filtering,
# quality trimming of ends and trimming by overlap with a given sequence.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

use feature "state";
use Time::Duration qw ( duration );

use List::Util;
use Data::Dumper;
use Bio::Patscan;

@EXPORT_OK = qw (
                 &clean
                 &clean_args
                 &clean_code
                 &clip_pat
                 &clip_pat_args
                 &clip_pat_beg_args
                 &clip_pat_beg_code
                 &clip_pat_end_args
                 &clip_pat_end_code
                 &debug_dump
                 &extract_pats
                 &extract_pats_args
                 &extract_pats_code
                 &filter_id
                 &filter_id_args
                 &filter_id_code
                 &filter_info
                 &filter_info_args
                 &filter_info_code
                 &filter_qual
                 &filter_qual_args
                 &filter_qual_code
                 &filter_seq
                 &filter_seq_args
                 &filter_seq_code
                 &guess_adapter
                 &process_file
                 &process_file_args
                 &trim_qual
                 &trim_qual_args
                 &trim_qual_beg_code
                 &trim_qual_beg_code
                 &trim_seq
                 &trim_seq_args
                 &trim_seq_beg_code
                 &trim_seq_end_code
                 &write_stats
                 &write_stats_sum
);

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;

use Registry::Args;
use Registry::Check;

use Seq::List;
use Seq::Stats;

use Recipe::IO;
use Recipe::Util;
use Recipe::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use vars qw ( *AUTOLOAD );

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

local $| = 1;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub clean
{
    # Niels Larsen, January 2012. 

    # Cleans a given sequence file or stream from STDIN, and writes to
    # file or STDOUT. Returns a hash of statistics counts. 

    my ( $args,
        ) = @_;

    # Returns a hash.

    my ( $code, $stats, $params, $recipe, $defs, $key, $val, $qualtype, 
         $step, $name, $title, $counts, $i );

    $defs = {
        "recipe" => undef,
        "iseqs" => undef,
        "seqfmt" => undef,
        "qualtype" => undef,
        "oseqs" => undef,
        "stats" => undef,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    # This is a temporary fix to skip empty files, should be done in the 
    # recipe run module instead,

    if ( $args->silent and ( $args->iseqs and -r $args->iseqs and not -s $args->iseqs ) )
    {
        return;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HANDLE RECIPE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check argument values, 

    &Seq::Clean::clean_args( $args );
    
    # Get and check recipe,
    
    $recipe = &Recipe::IO::read_recipe( $args->recipe );
    
    # Read parameters and copy to arguments,

    $params = &Recipe::Util::check_params( $recipe );

    # Put quality type into every step, some routines need it and some don't,
    # but won't hurt,

    $qualtype = $args->qualtype // $params->{"qualtype"};

    map { $_->{"qualtype"} = $qualtype } @{ $params->{"steps"} };

    # If a statistics file given, set flag for all steps,

    map { $_->{"stats"} = 1 } @{ $params->{"steps"} };
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # The parameters are used to create code, which again are mostly calls to
    # the list functions in Seq::List,

    $code = &Seq::Clean::clean_code( $params->{"steps"} );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG DUMPS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "confile" => $args->recipe,
             "config" => $recipe, 
             "params" => $params,
             "code" => $code,
            );

        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE STATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats->{"name"} = $recipe->{"name"} // "sequence-cleaning";
    $stats->{"title"} = $recipe->{"title"} // "Sequence cleaning";
    
    $stats->{"iseqs"} =
    {
        "title" => "Input file",
        "value" => &Common::File::full_file_path( $args->iseqs ),
    };
    
    $stats->{"oseqs"} =
    {
        "title" => "Output file",
        "value" => &Common::File::full_file_path( $args->oseqs ),
    };

    map { push @{ $stats->{"steps"} }, { "title" => $_->{"title"} } } @{ $recipe->{"steps"} };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN THE CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # This reads parts of a file into sequence lists and applies the above 
    # configured routine to them while incrementing counts,

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->seqfmt // $params->{"seqfmt"},
            "seqs_code" => $code,
            "seqs_args" => [],
            "seqs_stats" => $stats,
            "read_max" => 500,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => $args->stats,
            "console_head" => $stats->{"title"},
            "console_text" => "Cleaning sequences",
            "append" => $args->append,
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub clean_args
{
    # Niels Larsen, January 2012.

    # Checks arguments, reads and returns configuration file. Exits with 
    # error messages if any.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns a hash.

    my ( $defs, @msgs );

    if ( -t STDIN and not $args->iseqs ) {
        push @msgs, ["ERROR", qq (No input sequence file or stream given.) ];
    }
    
    if ( not $args->recipe )
    {
        push @msgs, ["ERROR", qq (No configuration file given.) ];
        push @msgs, ["INFO", qq (A template can be made with the --help recipe option.) ];
    }
    
    if ( not $args->clobber and not $args->append )
    {
        if ( $args->oseqs and not $args->dryrun ) {
            &Common::File::check_files( [ $args->oseqs ], "!e", \@msgs );
        }

        if ( $args->stats ) {
            &Common::File::check_files( [ $args->stats, $args->stats .".html" ], "!e", \@msgs );
        }
    }

    &Seq::Common::qual_config( $args->qualtype, \@msgs );

    &append_or_exit( \@msgs, $msgs );

    return $args;
}

sub clean_code
{
    # Niels Larsen, January 2012.

    # Creates a routine that does the given list of cleaning steps. Returns 
    # code text that can be eval'ed and run. The coded routine takes a list 
    # of sequences, does the steps in the given parameters, and returns a 
    # list with perhaps fewer and smaller sequences. 

    my ( $params,
         $stat,
        ) = @_;

    # Returns a string.
    
    my ( $code, $args, $argstr, $routine, $i, $j );

    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n);

    $i = 0;

    foreach $args ( @{ $params } )
    {
        if ( $stat )
        {
            if ( $i == 0 ) {
                $code .= qq (    \$stats->[$i]->{"iseq"} += scalar \@{ \$seqs };\n);
                $code .= qq (    \$stats->[$i]->{"ires"} += &Seq::List::sum_length( \$seqs );\n\n);
            } else {
                $j = $i - 1;
                $code .= qq (    \$stats->[$i]->{"iseq"} = \$stats->[$j]->{"oseq"};\n);
                $code .= qq (    \$stats->[$i]->{"ires"} = \$stats->[$j]->{"ores"};\n\n);
            }
        }

        $routine = $args->{"routine"};

        if ( $args->{"steps"} )
        {
            local $Data::Dumper::Terse = 1;     # avoids variable names
            local $Data::Dumper::Useqq = 1;     # avoids variable names
            
            $argstr = Data::Dumper::Dumper( $args->{"steps"} );

            chomp $argstr;
            $argstr =~ s/\n/\n        /g;

            if ( $stat )
            {
                $code .= qq (    state \$routine$i = eval &$routine( $argstr, 0 );\n);
                $code .= qq (    \$seqs = \$routine$i->( \$seqs );\n\n);
            }
        }
        else
        {
            no strict "refs"; 

            $code .= $routine->( $args, 0, 0 );
        }

        if ( $stat )
        {
            $code .= qq (    \$stats->[$i]->{"oseq"} += scalar \@{ \$seqs };\n);
            $code .= qq (    \$stats->[$i]->{"ores"} += &Seq::List::sum_length( \$seqs );\n\n);
            
            $i += 1;
        }
    }

    $code .= "\n" if not $params->[0]->{"stats"};

    $code .= qq (    return \$seqs;\n}\n);

    # Crash if the generated code has syntax problems,

    eval $code;

    if ( $@ ) {
        &error( $@ );
    }

    return $code;
}

sub clip_pat
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by overlap with a given sequence.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $stats, $pats );

    $defs = {
        "iseqs" => undef,
        "iformat" => undef,
        "oseqs" => undef,
        "patstr" => undef,
        "seqori" => "forward",
        "patinc" => 1,
        "dist" => undef,
        "begs" => 0,
        "ends" => 0,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $args = &Seq::Clean::clip_pat_args( $args );

    $code = &Seq::Clean::clip_pat_code( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG DUMP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "args" => $args,
             "code" => $code,
            );
        exit;
    }    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->iformat,
            "seqs_code" => $code,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => 0,
            "console_head" => "Sequence trim",
            "console_text" => "Sequence trimming",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub clip_pat_beg_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $i, $j, $qual_enc );

    @filters = qw ( patstr dist );  

    if ( not grep { defined $args->{ $_ } } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    if ( not $args->{"patstr"} ) {
        push @msgs, ["ERROR", qq (--patstr must be specified) ];
    }

    if ( not $args->{"dist"} ) {
        push @msgs, ["ERROR", qq (--dist must be specified) ];
    }

    &append_or_exit( \@msgs );
    
    return $args;
}

sub clip_pat_beg_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $pstr, $pinc, $ori, $dist, $diff, $mpct, $mmin );

    &Seq::Clean::clip_pat_beg_args( $args );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n\n);
    }

    ( $pstr, $ori, $pinc, $dist ) = ( $args->{"patstr"}, $args->{"seqori"}, $args->{"patinc"}, $args->{"dist"} );

    $code .= qq (    \$seqs = &Seq::List::clip_pat_beg( \$seqs, '$pstr', $dist, $pinc );\n);

    if ( $ori eq "reverse" ) {
        $code .= qq (    \$seqs = &Seq::List::change_complement( \$seqs );\n);
    }

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;

    return $code;
}

sub clip_pat_end_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $i, $j );

    @filters = qw ( patstr dist );  

    if ( not grep { defined $args->{ $_ } } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    if ( not $args->{"patstr"} ) {
        push @msgs, ["ERROR", qq (--patstr must be specified) ];
    }

    if ( not $args->{"dist"} ) {
        push @msgs, ["ERROR", qq (--dist must be specified) ];
    }

    &append_or_exit( \@msgs );
    
    return $args;
}

sub clip_pat_end_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $pstr, $pinc, $ori, $dist, $diff, $mpct, $mmin );

    &Seq::Clean::clip_pat_end_args( $args );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n\n);
    }

    ( $pstr, $ori, $pinc, $dist ) = ( $args->{"patstr"}, $args->{"seqori"}, $args->{"patinc"}, $args->{"dist"} );

    $code .= qq (    \$seqs = &Seq::List::clip_pat_end( \$seqs, '$pstr', $dist, $pinc );\n);

    if ( $ori eq "reverse" ) {
        $code .= qq (    \$seqs = &Seq::List::change_complement( \$seqs );\n);
    }

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;

    return $code;
}

sub debug_dump
{
    # Niels Larsen, January 2012.
    
    # Prints Data::Dumper outputs of user configuration, routine parameters
    # and code text. 

    my ( %args,
        ) = @_;

    # Returns nothing.

    local $Data::Dumper::Terse = 1;     # avoids variable names
    local $Data::Dumper::Useqq = 1;     # use double quotes

    if ( $args{"args"} )
    {
        print STDERR "------------------------ Arguments hash --------------------------------\n";
        print STDERR Data::Dumper::Dumper( $args{"args"} );
    }

    if ( $args{"confile"} )
    {
        print STDERR "-------------------------- Recipe file ---------------------------------\n";
        print STDERR ${ &Common::File::read_file( $args{"confile"} ) };
    }

    if ( $args{"config"} )
    {
        print STDERR "-------------------------- Recipe dump ---------------------------------\n";
        print STDERR Data::Dumper::Dumper( $args{"config"} );
    }

    if ( $args{"params"} )
    {
        print STDERR "----------------------- Routine parameters -----------------------------\n";
        print STDERR Data::Dumper::Dumper( $args{"params"} );
    }

    if ( $args{"code"} )
    {
        print STDERR "--------------------------- Code text ----------------------------------\n";
        print STDERR $args{"code"};
    }

    return;
}

sub extract_pats
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by pattern. 

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $stats );

    $defs = {
        "iseqs" => undef,
        "seqfmt" => undef,
        "seqtype" => "nuc",
        "oseqs" => undef,
        "patfile" => undef,
        "patlist" => [],
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    # Validate arguments,

    $args = &Seq::Clean::extract_pats_args( $args );

    # Create code,
    
    $code = &Seq::Clean::extract_pats_code( $args->patlist, $args->seqtype eq "prot" ? 1 : 0 );

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "confile" => $args->patfile,
             "args" => $args,
             "code" => $code,
            );
        exit;
    }

    # Run,

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->seqfmt,
            "seqs_code" => $code,
            "read_max" => 500,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => 0,
            "console_head" => "Sequence pattern match",
            "console_text" => "Processing patterns",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub extract_pats_args
{
    my ( $args,
        ) = @_;

    my ( @filters, @msgs, $pats, $pat, $type );

    @filters = qw ( patfile );

    if ( not grep { defined $args->$_ } @filters ) {
        push @msgs, ["ERROR", qq (Please specify an argument) ];
    }

    &append_or_exit( \@msgs );

    $type = $args->seqtype;

    if ( $type ne "nuc" and $type ne "prot" ) {
        push @msgs, ["ERROR", qq (Wrong looking sequence type -> "$type", must be "nuc" or "prot") ];
    }

    if ( $args->patfile ) {
        &Common::File::check_files( [ $args->patfile ], "r", \@msgs );
    } else {
        push @msgs, ["ERROR", qq (No pattern config file given) ];
    }        
    
    &append_or_exit( \@msgs );

    $pats = &Recipe::IO::read_recipe_params( $args->patfile, \@msgs );
    &append_or_exit( \@msgs );

    if ( ref $pats eq "HASH" ) {
        $pats = $pats->{"steps"};
    }
    
    # Are patterns okay,

    $type = $type eq "prot" ? 1 : 0;
    
    foreach $pat ( @{ $pats } )
    {
        if ( not &Bio::Patscan::compile_pattern( $pat->{"pat_string"}, $type ) ) {
            push @msgs, ["ERROR", qq (Mistake in pattern -> "$pat->{'pat_string'}") ];
        }
    }
    
    &append_or_exit( \@msgs );

    $args->patlist( $pats );

    return $args;
}

sub extract_pats_code
{
    # Niels Larsen, December 2011.
    
    # Generates code that filters and/or extracts from lists of sequences,
    # in response to pattern config files.

    my ( $pats,
         $type,
        ) = @_;

    # Returns string.

    my ( $code, $pat, @msgs, $routine, $ndcs, $argstr, $i, $imax );

    $i = 0;
    $imax = $#{ $pats };

    $code = qq (sub\n{\n    my ( \$seqs, \$stats\n        ) = \@_;\n\n);
    
    if ( $imax > 0 ) {
        $code .= qq (    my ( \$iseqs, \$oseqs, \$hits, \%ids );\n\n);
    }

    for ( $i = 0; $i <= $imax; $i++ )
    {
        $pat = $pats->[ $i ];

        # >>>>>>>>>>>>>>>>>>>>> SET ROUTINES AND ARGUMENTS <<<<<<<<<<<<<<<<<<<<
    
        $argstr = qq ("pat_string" => '$pat->{"pat_string"}', "protein" => $type);

        if ( $pat->{"get_subpats"} )
        {
            $argstr .= qq (, "get_ndcs" => [). (join ",", @{ $pat->{"get_subpats"} }) ."]";

            # Match forward or reverse while extracting sub-sequences,

            if ( $pat->{"seq_orient"} eq "forward" ) {
                $routine = "filter_patf_seqs_sub";
            } else {
                $routine = "filter_patr_seqs_sub";
            }
        }
        else
        {
            # Match forward or reverse, without extraction,

            if ( $pat->{"seq_orient"} eq "forward" ) {
                $routine = "filter_patf_seqs";
            } else {
                $routine = "filter_patr_seqs";
            }

            # This gets the sequences that do not match,

            if ( not $pat->{"pat_match"} ) {
                $routine .= "_non";
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # If a single pattern, then return a shortened version of the incoming
        # list. If multiple patterns, use an implied "OR": all patterns will 
        # be tried on each sequence, and those sequences returned that match
        # one of them. 

        if ( scalar @{ $pats } == 1 )
        {
            $code .= qq (    \$seqs = &Seq::List::$routine( \$seqs, { $argstr } );\n);

            # Optionally complement sub-sequences after extraction,
            
            if ( $pat->{"get_subpats"} and $pat->{"get_orient"} eq "reverse" )
            {
                $code .= qq (    \$seqs = &Seq::List::change_complement( \$seqs );\n);
            }

            $code .= qq (\n    return \$seqs;\n}\n);
        }
        else
        {
            if ( $i == 0 ) {
                $code .= qq (    \@{ \$iseqs } = \@{ \$seqs };\n\n);
            }

            $code .= qq (    \$hits = &Seq::List::$routine( \$iseqs, { $argstr } );\n);

            if ( $pat->{"get_subpats"} and $pat->{"get_orient"} eq "reverse" )
            {
                $code .= qq (    \$hits = &Seq::List::change_complement( \$hits );\n);
            }

            $code .= qq (    push \@{ \$oseqs }, \@{ \$hits };\n\n);
            
            if ( $i < $imax )
            {
                $code .= qq (    \%ids = map { \$_->{"id"}, 1 } \@{ \$hits };\n);
                $code .= qq (    \@{ \$iseqs } = grep { not exists \$ids{ \$_->{"id"} } } \@{ \$iseqs };\n\n);
            }
            else {
                $code .= "    return \$oseqs;\n}\n";
            }
        }
    }

    return $code;
}

sub filter_id
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by id match and length.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $write_routine, $get_ids, $skip_ids, $stats );

    $defs = {
        "iseqs" => undef,
        "iformat" => undef,
        "oseqs" => undef,
        "oids" => 0,
        "getfile" => undef,
        "skipfile" => undef,
        "getids" => [],
        "skipids" => [],
        "match" => undef,
        "nomatch" => undef,
        "minlen" => undef,
        "maxlen" => undef,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $args = &Seq::Clean::filter_id_args( $args );
    $code = &Seq::Clean::filter_id_code( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOAD IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $args->getids } ) {
        $get_ids = $args->getids;
    } elsif ( $args->getfile ) {
        $get_ids = { map { $_, 1 } &Common::File::read_ids( $args->getfile ) };
    }

    if ( @{ $args->skipids } ) {
        $skip_ids = $args->skipids;
    } elsif ( $args->skipfile ) {
        $skip_ids = { map { $_, 1 } &Common::File::read_ids( $args->skipfile ) };
    }

    if ( $args->oids ) {
        $write_routine = "Seq::IO::write_seqs_ids";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG DUMP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "args" => $args,
             "code" => $code,
            );

        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->iformat,
            "seqs_code" => $code,
            "seqs_args" => [ $get_ids, $skip_ids ],
            "write_routine" => $write_routine,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "console_head" => "Sequence ID filter",
            "console_text" => "Filtering by ids",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub filter_id_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $i, $j );

    @filters = qw ( getfile skipfile getids skipids match nomatch minlen maxlen );  

    if ( not grep { defined $args->$_ } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    if ( $i = $args->minlen and $j = $args->maxlen and $i > $j ) {
        push @msgs, ["ERROR", qq (minlen larger than maxlen: $i > $j) ];
    }
    
    foreach $file ( qw ( getfile skipfile ) )
    {
        if ( $args->$file ) {
            &Common::File::check_files( [ $args->$file ], "r", \@msgs );
        }
    }

    &append_or_exit( \@msgs );

    return $args;
}

sub filter_id_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats, \$getids, \$skipids ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n);
    }

    if ( $args->{"getfile"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_id_match( \$seqs, \$getids );\n);
    }

    if ( $args->{"skipfile"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_id_non( \$seqs, \$skipids );\n);
    }

    if ( $args->{"match"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_id_regexp( \$seqs, '$args->{"match"}' );\n);
    }
        
    if ( $args->{"nomatch"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_id_regexp_non( \$seqs, '$args->{"nomatch"}' );\n);
    }
    
    if ( $args->{"minlen"} and $args->{"maxlen"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_id_length_range( \$seqs, $args->{"minlen"}, $args->{"maxlen"} );\n);
    } elsif ( $args->{"minlen"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_id_length_min( \$seqs, $args->{"minlen"} );\n);
    } elsif ( $args->{"maxlen"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_id_length_max( \$seqs, $args->{"maxlen"} );\n);
    }
    
    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;

    return $code;
}

sub filter_info
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by info field match.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $stats );

    $defs = {
        "iseqs" => undef,
        "iformat" => undef,
        "oseqs" => undef,
        "match" => undef,
        "nomatch" => undef,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $args = &Seq::Clean::filter_info_args( $args );
    $code = &Seq::Clean::filter_info_code( $args );

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "args" => $args,
             "code" => $code,
            );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->iformat,
            "seqs_code" => $code,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => 0,
            "console_head" => "Sequence info filter",
            "console_text" => "Filtering by info",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub filter_info_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $i, $j );

    @filters = qw ( match nomatch );  

    if ( not grep { defined $args->$_ } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    return $args;
}

sub filter_info_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n);
    }

    if ( $args->{"match"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_info_regexp( \$seqs, '$args->{"match"}' );\n);
    }
        
    if ( $args->{"nomatch"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_info_regexp( \$seqs, '$args->{"nomatch"}' );\n);
    }

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;
    
    return $code;
}

sub filter_qual
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by info field match.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $stats );

    $defs = {
        "iseqs" => undef,
        "iformat" => undef,
        "oseqs" => undef,
        "qualtype" => undef,
        "minqual" => 0,
        "maxqual" => 100,
        "minch" => undef,
        "maxch" => undef,
        "minpct" => 0,
        "maxpct" => 100,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $args = &Seq::Clean::filter_qual_args( $args );
    $code = &Seq::Clean::filter_qual_code( $args );

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "args" => $args,
             "code" => $code,
            );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->iformat,
            "seqs_code" => $code,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => 0,
            "console_head" => "Sequence qualify filter",
            "console_text" => "Filtering by quality",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub filter_qual_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $min, $max, $i, $j, $qual_given, $pct_given,
         $qual_enc, $str );

    @filters = qw ( minqual maxqual minpct maxpct );  

    if ( not grep { defined $args->$_ } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    &append_or_exit( \@msgs );

    # Quality encoding,

    if ( not $args->qualtype )
    {
        push @msgs, ["ERROR", qq (Please specify quality encoding name) ];
        push @msgs, ["INFO", qq (Choices are:) ];
        map { push @msgs, ["INFO", "  $_" ] } &Seq::Common::qual_config_names();

        &append_or_exit( \@msgs );
    }

    $qual_enc = &Seq::Common::qual_config( $args->qualtype, \@msgs );

    # Quality bounds,

    ( $min, $max ) = ( $args->minqual // 0, $args->maxqual // 100 );

    if ( $min < 0 or $min > 100 ) { 
        push @msgs, ["ERROR", qq (Mininum quality ($min) must be between 0 and 100) ];
    }
    
    if ( $max < 0 or $max > 100 ) {
        push @msgs, ["ERROR", qq (Maximum quality ($max) must be between 0 and 100) ];
    }
    
    if ( $min > $max ) {
        push @msgs, ["ERROR", qq (Quality minimum ($min) higher than maximum ($max)) ];
    }
    
    if ( $min > 0 or $max < 100 and not @msgs ) {
        $qual_given = 1;
    }
    
    # Stringency bounds,
    
    ( $min, $max ) = ( $args->minpct // 0, $args->maxpct // 100 );
    
    if ( $min < 0 or $min > 100 ) { 
        push @msgs, ["ERROR", qq (Minimum stringency ($min) must be between 0 and 100) ];
    }
    
    if ( $max < 0 or $max > 100 ) {
        push @msgs, ["ERROR", qq (Maximum stringency ($max) must be between 0 and 100) ];
    }
    
    if ( $min > $max ) {
        push @msgs, ["ERROR", qq (Stringency minimum ($min) higher than maximum ($max)) ];
    }
    
    if ( ( $min > 0 or $max < 100 ) and not @msgs ) {
        $pct_given = 1;
    }
    
    if ( $qual_given and not $pct_given ) {
        push @msgs, ["ERROR", qq (A minimum percentage must be given with quality) ];
    } elsif ( $pct_given and not $qual_given ) {
        push @msgs, ["ERROR", qq (A quality cutoff must be given with percentage) ];
    } elsif ( not $qual_given and not $pct_given ) {
        push @msgs, ["ERROR", qq (A quality + percentage must be given) ];
    }

    &append_or_exit( \@msgs );

    $args->minch( &Seq::Common::qual_to_qualch( $args->minqual / 100, $qual_enc ) );
    $args->maxch( &Seq::Common::qual_to_qualch( $args->maxqual / 100, $qual_enc ) );
    
    &append_or_exit( \@msgs );

    return $args;
}

sub filter_qual_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $minch, $maxch, $minpct, $maxpct );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n);
    }

    ( $minch, $maxch, $minpct, $maxpct ) = ( $args->{"minch"}, $args->{"maxch"}, $args->{"minpct"}, $args->{"maxpct"} );

    if ( $minch or $maxch ) {
        $code .= qq (    \$seqs = &Seq::List::filter_qual( \$seqs, '$minch', '$maxch', $minpct, $maxpct );\n);
    }

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;

    return $code;
}

sub filter_seq
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by id match and length.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $stats, $pats );

    $defs = {
        "iseqs" => undef,
        "iformat" => undef,
        "readbuf" => 500,
        "oseqs" => undef,
        "patstr" => undef,
        "nomatch" => 0,
        "forward" => 1,
        "reverse" => 0,
        "mingc" => undef,
        "maxgc" => undef,
        "minlen" => undef,
        "maxlen" => undef,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $args = &Seq::Clean::filter_seq_args( $args );
    $code = &Seq::Clean::filter_seq_code( $args );

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "args" => $args,
             "code" => $code,
            );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->iformat,
            "seqs_code" => $code,
            "read_max" => $args->readbuf,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => 0,
            "console_head" => "Sequence filter",
            "console_text" => "Sequence filtering",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub filter_seq_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $i, $j, $patstr );

    @filters = qw ( patstr mingc maxgc minlen maxlen );  

    if ( not grep { defined $args->$_ } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    if ( $patstr = $args->patstr and 
         not &Bio::Patscan::compile_pattern( $patstr, 0 ) )
    {
        push @msgs, ["ERROR", qq (Mistake in pattern -> "$patstr") ];
    }

    if ( not $args->forward and not $args->reverse ) {
        push @msgs, ["ERROR", qq (Please specify --forward, --reverse or both) ];
    }
    
    if ( $i = $args->mingc and $j = $args->maxgc and $i > $j ) {
        push @msgs, ["ERROR", qq (mingc larger than maxgc: $i > $j) ];
    }
    
    if ( $i = $args->minlen and $j = $args->maxlen and $i > $j ) {
        push @msgs, ["ERROR", qq (minlen larger than maxlen: $i > $j) ];
    }
    
#    if ( $args->patfile ) {
#        &Common::File::check_files( [ $args->patfile ], "r", \@msgs );
#    }

    &append_or_exit( \@msgs );

    return $args;
}

sub filter_seq_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $mingc, $maxgc, $argstr );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n);
    }

    if ( $args->{"minlen"} and $args->{"maxlen"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_length_range( \$seqs, $args->{"minlen"}, $args->{"maxlen"} );\n);
    } elsif ( $args->{"minlen"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_length_min( \$seqs, $args->{"minlen"} );\n);
    } elsif ( $args->{"maxlen"} ) {
        $code .= qq (    \$seqs = &Seq::List::filter_length_max( \$seqs, $args->{"maxlen"} );\n);
    }

    if ( $args->{"mingc"} or $args->{"maxgc"} )
    {
        $mingc = ( $args->{"mingc"} // 0 ) / 100;
        $maxgc = ( $args->{"maxgc"} // 100 ) / 100;

        $code .= qq (    \$seqs = &Seq::List::filter_gc( \$seqs, $mingc, $maxgc );\n);
    }
    
    if ( $args->{"patstr"} )
    {
        $argstr = qq ({"pat_string" => '$args->{"patstr"}', "protein" => 0 });

        if ( $args->{"forward"} )
        {
            if ( $args->{"nomatch"} ) {
                $code .= qq (    \$seqs = &Seq::List::filter_patf_seqs_non( \$seqs, $argstr );\n);
            } else {
                $code .= qq (    \$seqs = &Seq::List::filter_patf_seqs( \$seqs, $argstr );\n);
            }
        }
        
        if ( $args->{"reverse"} )
        {
            if ( $args->{"nomatch"} ) {
                $code .= qq (    \$seqs = &Seq::List::filter_patr_seqs_non( \$seqs, $argstr );\n);
            } else {
                $code .= qq (    \$seqs = &Seq::List::filter_patr_seqs( \$seqs, $argstr );\n);
            }
        }
    }

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }
    
    $code .= qq (\n    return \$seqs;\n}\n) if $func;

    return $code;
}

sub guess_adapter
{
    # Niels Larsen, December 2009.

    # Guesses the adapter part of the ends of a set of solexa sequences on 
    # file. It works by looking at a sample: the first [1000] reads or so of 
    # high quality [300 or better] for all bases, are read into memory; then 
    # the most frequent oligo [6 long] at the very ends is found; this oligo 
    # is then matched against the downstream parts of the sequences, and a 
    # list of pre- and post-match sequences is made; the adapter sequence is 
    # then extended upstream as far as highly conserved [95%] positions go;
    # same with downstream, except with the additional constraint that a
    # certain number [ sample size / (100 - minimum conservation percent ] 
    # of sequences must be represented, so a wrong adapter will not be 
    # inferred from a few misaligned sequences. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns a string.
    
    my ( $defs, @seqs, $seq, $seq_count, $max_count, $routine, $fh, $i,  
         $table, $seq_str, $reads, $min_pct, $max_pct, @prematch, @postmatch,
         $str, $min_qual, $max_qual, %counts, $oli_str, $oli_len, $oli_max,
         $oli_dist, $apt_str, $apt_len, $ch, @stats, $stat, $pos, $sum_count,
         $oli_min, $cons_min, $sum_min, @matches, $sample, $end_dist,
         $sub_str, $beg_pos, @table, $qual_count, $qual_type, $qual_enc,
         $min_ch, $max_ch, @msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "iseqs" => undef,
        "iformat" => "fastq",
        "oseq" => undef,
        "sample" => 1000,       # Number of reads in sample
        "qualtype" => undef,
        "minqual" => 99.5,      # Minimum quality percent
        "olilen" => 6,          # Seed oligo length
        "olipct" => 30,         # Seed oligo minimum percent frequency at ends
        "olidist" => 15,        # Maximum distance from end to look for match
        "conspct" => 95,        # Minimum conservation percentage
        "header" => 1,
        "silent" => 0,
        "indent" => 3,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    if ( not $args->iseqs ) { push @{ $msgs }, ["ERROR", qq (No input file given) ] };
    if ( $args->olilen < 4 ) { push @{ $msgs }, ["ERROR", qq (Seed oligo length should be at least 4) ] };
    if ( $args->sample < 500 ) { push @{ $msgs }, ["ERROR", qq (Number of sample reads should be at least 500) ] };
    if ( $args->minqual < 99 ) { push @{ $msgs }, ["ERROR", qq (Sequence quality should be at least 99 pct) ] };
    if ( $args->conspct < 80 ) { push @{ $msgs }, ["ERROR", qq (Conservation percentage should be at least 80) ] };

    $qual_enc = &Seq::Common::qual_config( $args->qualtype, $msgs );
    
    if ( $msgs and @{ $msgs } ) 
    {
        &echo_messages( $msgs, { "linewid" => 70, "linech" => "-" } );
        exit 0;
    } 

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $sample = $args->sample;
    $oli_len = $args->olilen;
    $oli_min = $args->olipct / 100;
    $oli_dist = $args->olidist;
    $cons_min = $args->conspct / 100;
    $qual_type = $args->qualtype;
    $min_qual = $args->minqual / 100;

    $min_ch = &Seq::Common::qual_to_qualch( $args->minqual / 100, $qual_enc );
    $max_ch = &Seq::Common::qual_to_qualch( 1, $qual_enc );

    local $Common::Messages::silent = $args->silent;
    local $Common::Messages::indent_plain = $args->indent;

    if ( $args->header ) {
        &echo_bold( "\nGuessing adapter:\n" );
    }
    
    # >>>>>>>>>>>>>>>>>>>>> LOAD SAMPLE SET OF GOOD READS <<<<<<<<<<<<<<<<<<<<<

    &echo( qq (Loading high-quality reads ... ) );

    $routine = "Seq::IO::read_seq_". $args->iformat;

    $fh = &Common::File::get_read_handle( $args->iseqs );

    @seqs = ();
    $seq_count = 0;

    no strict "refs";

    while ( defined ( $seq = $routine->( $fh ) ) )
    {
        $seq_count += 1;

        if ( &Seq::Common::qual_pct( $seq, $min_ch, $max_ch ) >= 99.9 ) {
            push @seqs, &Seq::Common::uppercase( $seq );
        }
        
        last if scalar @seqs >= $sample;
    }

    &Common::File::close_handle( $fh );

    $qual_count = scalar @seqs;

    if ( $qual_count == 0 )
    {
        $str = &Seq::Common::qual_config_names();

        push @msgs, ["ERROR", qq (No good quality sequences found) ];
        push @msgs, ["INFO", qq (Perhaps the quality encoding scheme ($qual_type) is wrong?) ];
        push @msgs, ["INFO", qq (Choices are: $str) ];

        &echo("\n");
        &append_or_exit( \@msgs );
    }

    &echo_green( &Common::Util::commify_number( $qual_count ) ." from ".
                 &Common::Util::commify_number( $seq_count ) ."\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE ADAPTER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Count the oligos at the 3-end. If one of them recurs more than xx% of 
    # the time, then assign initial adapter sequence to that one. If not it is
    # a fatal error,

    &echo( qq (Finding most frequent end-oligo ... ) );

    foreach $seq ( @seqs ) {
        $counts{ substr $seq->{"seq"}, -$oli_len }++;
    }

    while ( ( $oli_str, $sum_count ) = each %counts ) {
        push @stats, [ $oli_str, $sum_count ];
    }

    @stats = sort { $b->[1] <=> $a->[1] } @stats;
    
    ( $oli_str, $oli_max ) = @{ $stats[0] };

    if ( $oli_max / $qual_count < $oli_min )
    {
        &error( qq (Most frequent oligo found only $oli_max times out of $qual_count.\n)
               .qq (That may mean there are no common sub-sequence near the 3-ends\n)
               .qq (or that the given oligo length is too long - try reduce.) );
    }

    $apt_str = $oli_str;
    $apt_len = length $apt_str;

    $str = &Common::Util::commify_number( $oli_max );
    &echo_green( qq ($apt_str ($str)\n) );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE MATCH TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Search sequence ends with the candidate and create a list of 
    # [ id, pre-match string, post-match string ],

    &echo( qq (Matching oligo against ends ... ) );

    foreach $seq ( @seqs )
    {
        $seq_str = $seq->{"seq"};

        $beg_pos = &List::Util::max( 0, &Seq::Common::seq_len( $seq ) - $oli_dist );
        $sub_str = substr $seq_str, $beg_pos;

        if ( ($i = rindex $sub_str, $apt_str) >= 0 )
        {
            $str = reverse substr $seq_str, 0, $beg_pos+$i;
            push @matches, [ $seq->{"id"}, $str, $apt_str, substr $seq_str, $beg_pos+$i+$apt_len ];
        }
    }

    $str = &Common::Util::commify_number( scalar @matches );
    &echo_green( qq ($str matches\n) );

    if ( $args->debug )
    {
        require Common::Tables;

        @table = map { $_->[1] = reverse $_->[1]; $_ } @{ &Storable::dclone( \@matches ) };

        $table = Common::Tables->render_list(
            \@table,
            { "align" => "right,right,left,left", "indent" => 3, "colsep" => "  " });
    
        print "$table\n"; 
    }

    # >>>>>>>>>>>>>>>>>>>>>> EXTEND ADAPTER TOWARD 5-END <<<<<<<<<<<<<<<<<<<<<<<

    # If the pre-match endings are well conserved, then extend adapter toward 
    # the 5-end by the most frequent base,

    &echo( qq (Extending adapter 5-end ... ) );

    @stats = &Seq::Stats::colstats( [ map { $_->[1] } @matches ], 0, "dna" );

    $str = "";

    foreach $stat ( @stats )
    {
        @{ $stat } = sort { $b->[1] <=> $a->[1] } @{ $stat };
        ( $ch, $max_count ) = @{ $stat->[0] };

        $sum_count = &List::Util::sum( map { $_->[1] } @{ $stat } );

        if ( $max_count / $sum_count >= $cons_min ) {
            $str .= lc $ch; 
        } else {
            last;
        }
    }

    if ( not $str ) {
        &error( qq (Could not extend "$apt_str" upstream. This could be due to\n)
               .qq (very strict settings, or maybe this most frequent oligo\n)
               .qq (is from a variable region. Try experiment with settings\n)
               .qq (and if that fails, contact the author.) );
    }

    $apt_str = (reverse $str) . $apt_str;

    &echo_green( qq ($apt_str\n) );

    # >>>>>>>>>>>>>>>>>>>>>> EXTEND ADAPTER TOWARD 3-END <<<<<<<<<<<<<<<<<<<<<

    &echo( qq (Extending adapter 3-end ... ) );

    @stats = &Seq::Stats::colstats( [ map { $_->[3] } @matches ], 0, "dna" );

    $sum_min = ( scalar @matches ) * ( 1 - $cons_min );

    foreach $stat ( @stats )
    {
        @{ $stat } = sort { $b->[1] <=> $a->[1] } @{ $stat };
        ( $ch, $max_count ) = @{ $stat->[0] };

        $sum_count = &List::Util::sum( map { $_->[1] } @{ $stat } );

        if ( $sum_count >= $sum_min and $max_count / $sum_count >= $cons_min ) {
            $apt_str .= lc $ch;
        } else {
            last;
        }
    }

    &echo_green( qq ($apt_str\n) );

    if ( defined $args->oseq )
    {
        $fh = &Common::File::get_write_handle( $args->oseq );
        $fh->print( "$apt_str\n" );
        $fh->close;
    }

    if ( $args->header ) {
        &echo_bold( "Finished\n\n" );
    }

    return $apt_str;
}

sub process_file
{
    # Niels Larsen, December 2011.

    # Processes a given file by using the given code on it. Sequences are
    # read in batches, processed as lists by the given code, and written in
    # batches. The most optimal batch size is a few hundred. Counts and 
    # timings are made underway, and returned in a hash.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns a hash.

    my ( $counts, $ifh, $ofh, $sfh, $params, $seqs_routine, $read_routine, 
         $write_routine, $read_max, $iseqs, $oseqs, $stats, $basename,
         $pct, $defs, $seqs_args, $dry_run, @msgs, $format, $conf, 
         $args_copy, $iseq, $ires, $oseq, $ores, $time_start, $file, $text );

    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "in_seqs" => undef,
        "in_format" => undef,
        "read_max" => 1000,
        "seqs_code" => undef,
        "seqs_args" => [],
        "seqs_stats" => {},
        "dry_run" => undef,
        "out_seqs" => undef,
        "out_stats" => undef,
        "write_routine" => undef,
        "console_head" => undef,
        "console_text" => undef,
        "verbose" => 0,
        "silent" => 0,
        "clobber" => 0,
        "append" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $conf = bless &Seq::Clean::process_file_args( $args );

    $Common::Messages::silent = $args->silent;

    &echo_bold( "\n". $args->console_head .":\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OPEN FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ifh = &Common::File::get_read_handle( $args->in_seqs );
    $ifh->blocking( 1 );

    if ( not $args->dry_run )
    {
        if ( $args->clobber )
        {
            # Output file,

            if ( $file = $args->out_seqs )
            {
                if ( -e $file )
                {
                    $basename = &File::Basename::basename( $file );
                    &echo("   Deleting $basename ... " );

                    &Common::File::delete_file( $file );
                    &echo_done("done\n");
                }
            }

            # Output statistics,

            if ( $file = $args->out_stats )
            {
                if ( -e $file )
                {
                    $basename = &File::Basename::basename( $file );
                    &echo("   Deleting $basename ... " );

                    &Common::File::delete_file( $file );
                    &echo_done("done\n");
                }

                if ( -e "$file.html" )
                {
                    $basename = &File::Basename::basename( "$file.html" );
                    &echo("   Deleting $basename ... " );

                    &Common::File::delete_file( "$file.html" );
                    &echo_done("done\n");
                }
            }
        }

        if ( $args->append ) {
            $ofh = &Common::File::get_append_handle( $args->out_seqs );
            $sfh = &Common::File::get_append_handle( $args->out_stats );
        } else {
            $ofh = &Common::File::get_write_handle( $args->out_seqs );
            $sfh = &Common::File::get_write_handle( $args->out_stats );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN-LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $read_max = $args->read_max;
    $dry_run = $args->dry_run;

    if ( $dry_run ) {
        &echo("   ". $args->console_text ." (dryrun) ... " );
    } else {
        &echo("   ". $args->console_text ." ... " );
    }        

    $time_start = &time_start();

    $read_routine = $conf->read_routine;
    $seqs_routine = $conf->seqs_routine;
    $seqs_args = $args->seqs_args;
    $write_routine = $conf->write_routine;

    $stats = $args->seqs_stats;
    $stats->{"steps"} //= [];

    no strict "refs";

    while ( $iseqs = $read_routine->( $ifh, $read_max ) )
    {
        # Process a list of sequences,

        $oseqs = $seqs_routine->( $iseqs, $stats->{"steps"}, @{ $seqs_args } );

        # Write output,
            
        if ( not $dry_run ) 
        {
            $write_routine->( $ofh, $oseqs );
        }
    }

    &Common::File::close_handle( $ofh ) unless $dry_run;
    &Common::File::close_handle( $ifh );

    # &Common::File::delete_file_if_empty( $args->out_seqs ) if $args->out_seqs;

    $stats->{"seconds"} = &time_elapsed() - $time_start;
    $stats->{"finished"} = &Common::Util::epoch_to_time_string();

    &echo_done("done\n");

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $file = $args->out_stats )
    {
        $basename = &File::Basename::basename( $file );
        &echo("   Writing $basename ... ");

        $text = &Seq::Clean::write_stats( $file, $stats );

        $sfh->print( $text );
        &Common::File::close_handle( $sfh );

        &echo_done("done\n");
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CONSOLE RECEIPT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Write number of input and output sequences and bases to screen,
    
    $iseq = $stats->{"steps"}->[0]->{"iseq"};
    $ires = $stats->{"steps"}->[0]->{"ires"};
    
    $oseq = $stats->{"steps"}->[-1]->{"oseq"};
    $ores = $stats->{"steps"}->[-1]->{"ores"};
    
    if ( $iseq ) {
        $pct = sprintf "%.2f", 100 * $oseq / $iseq;
    } else {
        $pct = 0;
    }
    
    &echo( "   Input sequence count ... " );
    &echo_done( "$iseq\n" );
    
    &echo( "   Output sequence count ... " );
    &echo_done( "$oseq ($pct%)\n" );
    
    if ( $ires ) {
        $pct = sprintf "%.2f", 100 * $ores / $ires;
    } else {
        $pct = 0;
    }
    
    &echo( "   Input base count ... " );
    &echo_done( "$ires\n" );
    
    &echo( "   Output base count ... " );
    &echo_done( "$ores ($pct%)\n" );

    # Write run-time to screen,

    &echo("   Run time: ");
    &echo_info( &Time::Duration::duration( time() - $time_start ) ."\n" );

    &echo_bold("Finished\n\n");

    return wantarray ? %{ $stats } : $stats;
}

sub process_file_args
{
    # Niels Larsen, December 2011. 

    # Validates arguments and returns a config hash. 

    my ( $args,
        ) = @_;

    # Returns a hash.

    my ( $conf, $seqs_routine, $read_routine, $write_routine, @msgs, $format );

    # >>>>>>>>>>>>>>>>>>>>>> CHECK FILES AND FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<

    $format = $args->in_format;

    if ( $args->in_seqs )
    {
        &Common::File::check_files( [ $args->in_seqs ], "r", \@msgs );
        &append_or_exit( \@msgs );

        $format = &Seq::IO::detect_format( $args->in_seqs );
    }
    elsif ( -t STDIN )
    {
        push @msgs, ["ERROR", qq (No sequence input given) ];
    }
    elsif ( not $format )
    {
        push @msgs, ["ERROR", qq (Input format must be given with data from STDIN) ];
    }

    if ( $args->out_seqs and not $args->dry_run and not $args->clobber and not $args->append ) {
        &Common::File::check_files( [ $args->out_seqs ], "!e", \@msgs );
    }
    
    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>> SET AND CHECK ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read routine,

    $read_routine = "Seq::IO::read_seqs_$format";

    if ( Registry::Check->routine_exists( { "routine" => $read_routine, "fatal" => 0 } ) )
    {
        $conf->{"read_routine"} = $read_routine;
    }
    else {
        push @msgs, ["ERROR", qq (Wrong looking format -> "$format") ];
        push @msgs, ["INFO", qq (Supported formats are: fastq, fasta and fasta_wrapped) ];
    }

    &append_or_exit( \@msgs );

    # Write routine, 

    if ( not $write_routine = $args->write_routine ) {
        $write_routine = "Seq::IO::write_seqs_$format";
    }

    if ( Registry::Check->routine_exists( { "routine" => $write_routine, "fatal" => 0 } ) ) {
        $conf->{"write_routine"} = $write_routine;
    } else {
        &error( qq (Sequence write routine not found -> "$read_routine") );
    }

    # Sequence list routine,

    $seqs_routine = eval $args->seqs_code;

    if ( $@ ) {
        &error( $@ )
    };

    $conf->{"seqs_routine"} = $seqs_routine;

    return $conf;
}

sub trim_qual
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by quality.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $stats, $pats );

    $defs = {
        "iseqs" => undef,
        "iformat" => undef,
        "oseqs" => undef,
        "winlen" => 10,
        "winhit" => 9,
        "minqual" => 99.0,
        "minch" => undef,
        "qualtype" => undef,
        "begs" => 0,
        "ends" => 0,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $args = &Seq::Clean::trim_qual_args( $args );
    $code = &Seq::Clean::trim_qual_code( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG DUMP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "args" => $args,
             "code" => $code,
            );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->iformat,
            "seqs_code" => $code,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => 0,
            "console_head" => "Quality trim",
            "console_text" => "Quality trimming",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub trim_qual_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $i, $j, $qual_enc );

    @filters = qw ( begs ends winlen winhit minqual );  

    if ( not grep { defined $args->$_ } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    # Quality encoding,

    if ( not $args->qualtype )
    {
        push @msgs, ["ERROR", qq (Please specify quality encoding name) ];
        push @msgs, ["INFO", qq (Choices are:) ];
        map { push @msgs, ["INFO", "  $_" ] } &Seq::Common::qual_config_names();

        &append_or_exit( \@msgs );
    }

    if ( not $args->begs and not $args->ends ) {
        push @msgs, ["ERROR", qq (Either --begs or --ends must be given) ];
    }

    if ( $i = $args->winhit and $j = $args->winlen and $i > $j ) {
        push @msgs, ["ERROR", qq (--winhit larger than --winlen: $i > $j) ];
    }

    if ( ( $i = $args->minqual ) < 0 or $i > 100 ) { 
        push @msgs, ["ERROR", qq (Mininum quality ($i) must be between 0 and 100) ];
    }
 
    $qual_enc = &Seq::Common::qual_config( $args->qualtype, \@msgs );
    
    &append_or_exit( \@msgs );
    
    $args->minch( &Seq::Common::qual_to_qualch( $args->minqual / 100, $qual_enc ) );
    
    return $args;
}

sub trim_qual_beg_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $mingc, $maxgc );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n\n);
    }

    $code .= qq (    \$seqs = &Seq::List::trim_qual_beg( \$seqs, '$args->{"minch"}', $args->{"winlen"}, $args->{"winhit"} );\n);

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;
    
    return $code;
}

sub trim_qual_end_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $mingc, $maxgc );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n\n);
    }

    $code .= qq (    \$seqs = &Seq::List::trim_qual_end( \$seqs, '$args->{"minch"}', $args->{"winlen"}, $args->{"winhit"} );\n);

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;
    
    return $code;
}

sub trim_seq
{
    # Niels Larsen, December 2011.

    # Filters a sequence file by overlap with a given sequence.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $code, $stats, $pats );

    $defs = {
        "iseqs" => undef,
        "iformat" => undef,
        "oseqs" => undef,
        "seq" => undef,
        "dist" => undef,
        "minpct" => 80,
        "minlen" => 1,
        "begs" => 0,
        "ends" => 0,
        "dryrun" => 0,
        "silent" => 0,
        "append" => 0,
        "clobber" => 0,
        "debug" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    $args = &Seq::Clean::trim_seq_args( $args );
    
    $args->{"dist"} //= length $args->seq;

    $code = &Seq::Clean::trim_seq_code( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DEBUG DUMP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Exit with debug info if --debug,

    if ( $args->debug )
    {
        &Seq::Clean::debug_dump(
             "args" => $args,
             "code" => $code,
            );
        exit;
    }    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $stats = &Seq::Clean::process_file(
        {
            "in_seqs" => $args->iseqs,
            "in_format" => $args->iformat,
            "seqs_code" => $code,
            "dry_run" => $args->dryrun,
            "out_seqs" => $args->oseqs,
            "out_stats" => 0,
            "console_head" => "Sequence trim",
            "console_text" => "Sequence trimming",
            "silent" => $args->silent,
            "clobber" => $args->clobber,
        });

    return $stats;
}

sub trim_seq_args
{
    my ( $args,
        ) = @_;

    my ( @filters, $file, @msgs, $i, $j, $qual_enc );

    @filters = qw ( begs ends seq dist minpct minlen );  

    if ( not grep { defined $args->$_ } @filters ) {
        push @msgs, ["ERROR", qq (Please specify a filter condition) ];
    }

    if ( not $args->seq ) {
        push @msgs, ["ERROR", qq (--seq must be specified) ];
    }

    if ( not $args->begs and not $args->ends ) {
        push @msgs, ["ERROR", qq (Either --begs or --ends must be given) ];
    }
    
    if ( defined $args->minlen and $args->minlen < 1 ) {
        push @msgs, ["ERROR", qq (--minlen must be 1 or greater) ];
    }
    
    if ( ( $i = $args->minpct ) < 0 or $i > 100 ) { 
        push @msgs, ["ERROR", qq (--minpct must be between 0 and 100) ];
    }
 
    &append_or_exit( \@msgs );
    
    return $args;
}

sub trim_seq_beg_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $pstr, $dist, $diff, $mpct, $mmin );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n\n);
    }

    ( $pstr, $dist, $mpct, $mmin ) = ( $args->{"seq"}, $args->{"dist"}, $args->{"minpct"}, $args->{"minlen"} );

    $code .= qq (    \$seqs = &Seq::List::trim_seq_beg( \$seqs, '$pstr', $dist, $mpct, $mmin );\n);

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;

    return $code;
}

sub trim_seq_end_code
{
    my ( $args,
         $func,
         $stat,
        ) = @_;

    my ( $code, $pstr, $dist, $diff, $mpct, $mmin );

    $func //= 1;
    $stat //= 1;

    $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

    if ( $stat )
    {
        $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n\n);
    }

    ( $pstr, $dist, $mpct, $mmin ) = ( $args->{"seq"}, $args->{"dist"}, $args->{"minpct"}, $args->{"minlen"} );

    $code .= qq (    \$seqs = &Seq::List::trim_seq_end( \$seqs, '$pstr', $dist, $mpct, $mmin );\n);

    if ( $stat )
    {
        $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
        $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
    }

    $code .= qq (\n    return \$seqs;\n}\n) if $func;

    return $code;
}

sub write_stats
{
    # Niels Larsen, February 2012. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $text, $iseqs, $oseqs, $title, $step, $fstep, $time, $ifile, $ofile,
         $iseq, $ires, $oseq, $ores, $seqdif, $resdif, $seqpct, $respct,
         $lstep, @table, $row, $str );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @table = ();

    foreach $step ( @{ $stats->{"steps"} } )
    {
        $title = $step->{"title"};

        $iseq = $step->{"iseq"};
        $ires = $step->{"ires"};
        $oseq = $step->{"oseq"};
        $ores = $step->{"ores"};

        $seqdif = $oseq - $iseq;
        $resdif = $ores - $ires;

        if ( $iseq == 0 ) {
            $seqpct = sprintf "%.1f", 0;
        } else {
            $seqpct = ( sprintf "%.1f", 100 * $seqdif / $iseq );
        }

        if ( $ires == 0 ) {
            $respct = sprintf "%.1f", 0;
        } else {
            $respct = ( sprintf "%.1f", 100 * $resdif / $ires );
        }

        push @table, [ $title,
                       $iseq, $oseq, $seqdif, $seqpct,
                       $ires, $ores, $resdif, $respct,
        ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TOTALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $fstep = $stats->{"steps"}->[0];
    $lstep = $stats->{"steps"}->[-1];

    $iseq = $fstep->{"iseq"};
    $ires = $fstep->{"ires"};
    $oseq = $lstep->{"oseq"};
    $ores = $lstep->{"ores"};
    
    $seqdif = $oseq - $iseq;
    $resdif = $ores - $ires;
    
    if ( $iseq == 0 ) {
        $seqpct = sprintf "%.1f", 0;
    } else {
        $seqpct = ( sprintf "%.1f", 100 * $seqdif / $iseq );
    }
    
    if ( $ires == 0 ) {
        $respct = sprintf "%.1f", 0;
    } else {
        $respct = ( sprintf "%.1f", 100 * $resdif / $ires );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $iseqs = $stats->{"iseqs"};
    $oseqs = $stats->{"oseqs"};

    $time = &Time::Duration::duration( $stats->{"seconds"} );

    $ifile = &File::Basename::basename( $iseqs->{"value"} );
    $ofile = &File::Basename::basename( $oseqs->{"value"} );

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
      file = $iseqs->{"title"}\t$ifile
      file = $oseqs->{"title"}\t$ofile
      hrow = Total input reads\t$iseq
      hrow = Total output reads\t$oseq ($seqpct%)
      hrow = Total input bases\t$ires
      hrow = Total output bases\t$ores ($respct%)
      date = $stats->{"finished"}
      secs = $stats->{"seconds"}
      time = $time
   </header>

   <table>
      title = Stepwise sequence and reads statistics
      colh = Method\tIn-reads\tOut-reads\t&Delta;\t&Delta; %\tIn-bases\tOut-bases\t&Delta;\t&Delta; %
);

    foreach $row ( @table )
    {
        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }

    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_stats_sum
{
    # Niels Larsen, October 2012. 

    # Reads the content of the given list of statistics files and generates a 
    # summary table. The input files are written by write_stats above. The output
    # file has a tagged format understood by Recipe::Stats::html_body. A string 
    # is returned in list context, otherwise it is written to the given file or
    # STDOUT. 

    my ( $files,       # Input statistics files
         $sfile,       # Output file
        ) = @_;

    # Returns a string or nothing.
    
    my ( $stats, $text, $file, $rows, $secs, @row, @table, $iseq, $time,
         $ires, $sdif, $rdif, $oseq, $ores, $spct, $rpct, $str, $row, $ofile,
         $name, @dates, $date );

    # Create table array by reading all the given statistics files and getting
    # values from them,

    @table = ();
    $secs = 0;

    foreach $file ( @{ $files } )
    {
        $stats = &Recipe::IO::read_stats( $file )->[0];

        $rows = $stats->{"headers"}->[0]->{"rows"};

        $ofile = $rows->[1]->{"value"};
        $secs += $rows->[7]->{"value"};

        $rows = $stats->{"tables"}->[0]->{"rows"};
        
        @row = split "\t", $rows->[0]->{"value"};
        ( $iseq, $ires ) = @row[1,5];

        @row = split "\t", $rows->[-1]->{"value"};
        ( $oseq, $ores ) = @row[2,6];

        $name = &File::Basename::basename( $file );

        push @table, [ "file=". &File::Basename::basename( $ofile ),
                       $iseq, $oseq, 100 * ( $iseq - $oseq ) / $iseq,
                       $ires, $ores, 100 * ( $ires - $ores ) / $ires,
                       qq (html=Steps:$name.html),
        ];
    }

    # Sort descending by input sequences, 

    @table = sort { $b->[1] <=> $a->[1] } @table;
    
    # Calculate totals,

    $iseq = &List::Util::sum( map { $_->[1] } @table );
    $oseq = &List::Util::sum( map { $_->[2] } @table );
    $spct = sprintf "%.1f", 100 * ( ( $iseq - $oseq ) / $iseq );

    $ires = &List::Util::sum( map { $_->[4] } @table );
    $ores = &List::Util::sum( map { $_->[5] } @table );
    $rpct = sprintf "%.1f", 100 * ( ( $ires - $ores ) / $ires );
    
    $time = &Time::Duration::duration( $secs );

    $stats = bless &Recipe::IO::read_stats( $files->[0] )->[0];

    $date = &Recipe::Stats::head_type( $stats, "date" );

    # Format table,

    $text = qq (
<stats>
   title = $stats->{"title"}
   <header>
       hrow = Total input reads\t$iseq
       hrow = Total output reads\t$oseq (-$spct%)
       hrow = Total input bases\t$ires
       hrow = Total output bases\t$ores (-$rpct%)
       date = $date
       secs = $secs
       time = $time
   </header>   
   <table>
      title = Stepwise sequence and reads statistics
      colh = Output files\tIn-reads\tOut-reads\t&Delta; %\tIn-bases\tOut-bases\t&Delta; %\tSteps
);
    
    foreach $row ( @table )
    {
        $row->[1] //= 0;
        $row->[2] //= 0;
        $row->[3] = "-". sprintf "%.1f", $row->[3];
        $row->[4] //= 0;
        $row->[5] //= 0;
        $row->[6] = "-". sprintf "%.1f", $row->[6];

        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }

    $text .= qq (   </table>\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

1;

__END__


            
#             $value = join " or ", map { $_->{"patstr"} } @{ $pat };

#             push @{ $stats{"parameters"} },
#             {
#                 "name" => "pattern",
#                 "title" => $title,
#                 "descr" => $descr,
#                 "value" => $value,
#             }
#         }

#         # Quality,

#         if ( $params->{"quality"} )
#         {
#             push @{ $stats{"parameters"} },
#             {
#                 "name" => "minqual",
#                 "title" => "Minimum quality",
#                 "descr" => "Minimum accuracy percentage of a base",
#                 "value" => $args->minqual,
#             },{
#                 "name" => "maxqual",
#                 "title" => "Maximum quality",
#                 "descr" => "Maximum accuracy percentage of a base",
#                 "value" => $args->maxqual,
#             },{
#                 "name" => "minpct",
#                 "title" => "Minimum stringency",
#                 "descr" => "Minimum percentage of quality bases in the sequence",
#                 "value" => $args->minpct,
#             },{
#                 "name" => "maxpct",
#                 "title" => "Maximum stringency",
#                 "descr" => "Maximum percentage of quality bases in the sequence",
#                 "value" => $args->maxpct,
#             };
#         }

#         # Length,

#         if ( $params->{"length"} )
#         {
#             push @{ $stats{"parameters"} },
#             {
#                 "name" => "minlen",
#                 "title" => "Minimum length",
#                 "descr" => "Minimum sequence length",
#                 "value" => $args->minlen,
#             },{
#                 "name" => "maxlen",
#                 "title" => "Maximum length",
#                 "descr" => "Maximum sequence length",
#                 "value" => ($args->maxlen // ""),
#             };
#         }
#     }
#     elsif ( $method eq "trim_qual" )
#     {
#         # Quality trimming,

#         push @{ $stats{"parameters"} },
#         {
#             "name" => "begs",
#             "title" => "Trim beginnings",
#             "descr" => "Quality trimming of sequence beginnings",
#             "value" => $args->begs,
#         },{
#             "name" => "ends",
#             "title" => "Trim ends",
#             "descr" => "Quality trimming of sequence ends",
#             "value" => $args->ends,
#         },{
#             "name" => "winlen",
#             "title" => "Window length",
#             "descr" => "Length of window over which to measure quality",
#             "value" => $args->winlen,
#         },{
#             "name" => "minqual",
#             "title" => "Minimum quality",
#             "descr" => "Minimum accuracy percentage of a base",
#             "value" => $args->minqual,
#         },{
#             "name" => "minpct",
#             "title" => "Minimum stringency",
#             "descr" => "Minimum percentage of quality bases in the window",
#             "value" => $args->minpct,
#         };
#     }
#     elsif ( $method eq "trim_seq" )
#     {
#         # Sequence trimming,
        
#         push @{ $stats{"parameters"} },
#         {
#             "name" => "begs",
#             "title" => "Trim beginnings",
#             "descr" => "Quality trimming of sequence beginnings",
#             "value" => $args->begs,
#         },{
#             "name" => "ends",
#             "title" => "Trim ends",
#             "descr" => "Quality trimming of sequence ends",
#             "value" => $args->ends,
#         },{
#             "name" => "seq",
#             "title" => "Trim sequence",
#             "descr" => "Sequence used for trimming",
#             "value" => $args->seq,
#         },{
#             "name" => "dist",
#             "title" => "Search distance",
#             "descr" => "How far the trim sequence is allowed to slide upstream/downstream",
#             "value" => $args->dist,
#         },{
#             "name" => "diff",
#             "title" => "Score difference",
#             "descr" => "How much better the best match candidate is than the second best",
#             "value" => $args->diff,
#         },{
#             "name" => "minpct",
#             "title" => "Overlap quality",
#             "descr" => "Overlap match percentage",
#             "value" => $args->minpct,
#         };
#     }
#     else {
#         &error( qq (Wrong looking method -> "$method") );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     $seq_in = $counts->{"iseq"};
#     $seq_out = $counts->{"oseq"};

#     $res_in = $counts->{"ires"};
#     $res_out = $counts->{"ores"};
    
#     push @{ $stats{"values"} },
#     {
#         "name" => "seq_in",
#         "title" => "Seqs in",
#         "descr" => "Total number of input sequences",
#         "value" => $seq_in,
#     },{
#         "name" => "seq_out",
#         "title" => "Seqs out",
#         "descr" => "Total number of output sequences",
#         "value" => $seq_out,
#     },{
#         "name" => "res_in",
#         "title" => "Res in",
#         "descr" => "Total number of input residues",
#         "value" => $res_in,
#     },{
#         "name" => "res_out",
#         "title" => "Res out",
#         "descr" => "Total number of output residues",
#         "value" => $res_out,
#     };

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> DISPLAY TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Table titles,

#     push @{ $stats{"table_titles"} }, (
#         "File",
#         "Method",
#         "Seqs",
#         "&Delta;",
#         "&Delta; %",
#         "Bases",
#         "&Delta;",
#         "&Delta; %",
#     );

#     # First row,

#     push @{ $stats{"table_begin"} }, (
#         &File::Basename::basename( $stats{"files"}->[0]->{"value"} ),
#         "",
#         $seq_in,
#         "",
#         "",
#         $res_in,
#         "",
#         "",
#     );

#     # Value row,

#     push @{ $stats{"table_values"} }, (
#         ( $stats{"title"} || $stats{"method"} ),
#         $seq_in,
#         $seq_out - $seq_in,
#         ( sprintf "%.1f", 100 * ( $seq_out - $seq_in ) / $seq_in ),
#         $res_in,
#         $res_out - $res_in,
#         ( sprintf "%.1f", 100 * ( $res_out - $res_in ) / $res_in ),
#     );

#     return wantarray ? %stats : \%stats;
# }

# sub tablify_stats
# {
#     # Niels Larsen, April 2011. 

#     # Adds derived values and converts the statistics to a more tabular structure 
#     # that a general formatter can render. 

#     my ( $stats,
#         ) = @_;

#     # Returns hash.

#     my ( $step0, $step, @col_hdrs, @row_hdrs, $seq_beg, $res_beg, $seq_in, $seq_out, 
#          $res_in, $res_out, @values, $seq_pct_d, $res_pct_d );

#     @col_hdrs = ( "Method", "Seqs", "&Delta;", "&Delta; %", "Bases", "&Delta;", "&Delta; %" );

#     $seq_beg = $stats->{"counts"}->[0]->{"value"};
#     $res_beg = $stats->{"counts"}->[2]->{"value"};

#     # The following rows have current values plus deltas against the previous, 

#     ( $seq_in, $seq_out, $res_in, $res_out ) = map { $_->{"value"} } @{ $step->{"counts"} };

#     $seq_pct_d = 100 * ( $seq_out - $seq_in ) / $seq_in;   # Negative
#     $res_pct_d = 100 * ( $res_out - $res_in ) / $res_in;   # Negative
    
#     @values = (
#         $step->{"title"} || $step->{"method"}, 
#         $seq_out, $seq_out - $seq_in, (sprintf "%.1f", $seq_pct_d),
#         $res_out, $res_out - $res_in, (sprintf "%.1f", $res_pct_d),
#         );
    
#     return ( \@col_hdrs, \@values );
# }

# sub load_pattern
# {
#     # Niels Larsen, October 2009.

#     # Gets one or more patterns by name from routine or file. Returns a 
#     # list of patscan pattern texts.

#     my ( $args,
#          $silent,
#         ) = @_;

#     # Returns list.

#     my ( $name, $title, @pats, $file, $pat, %lib, %allowed, $field, @msgs, 
#          $text, $basename );

#     if ( $args->patstr )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STRING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         if ( $title = $args->patitle ) {
#             &echo( qq (Setting "$title" pattern ... ) ) unless $silent;
#         } else {
#             &echo( qq (Setting anonymous string pattern ... ) ) unless $silent;
#         }
        
#         @pats = {
#             "name" => "anonymous",
#             "patstr" => $args->patstr,
#             "title" => $title // "",
#         };
#     }
#     elsif ( $file = $args->patfile )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         $name = &File::Basename::basename( $file );
#         &echo( "Reading $name pattern ... " ) unless $silent;
        
#         $text = ${ &Common::File::read_file( $file ) };

#         if ( length $text > 5000 ) {
#             &error( qq (Pattern file "$file" over 5 kb, perhaps not a pattern file?) );
#         }

#         @pats = {
#             "name" => $name,
#             "patstr" => ( join " ", grep { $_ !~ /^\s*%/ } split "\n", $text ),
#             "title" => "",
#         }
#     }
#     elsif ( $args->patname or $args->patlib )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>> LIBRARY ENTRY <<<<<<<<<<<<<<<<<<<<<<<<<

#         &echo( qq (Loading "$name" library pattern ... ) ) unless $silent;
        
#         $file = $args->patlib // $Pattern_lib;
#         $name = $args->patname;

#         %lib = new Config::General( $file )->getall;

#         if ( $name )
#         {
#             if ( $lib{ $name } )
#             {
#                 if ( ref $lib{ $name } eq "HASH" ) {
#                     @pats = $lib{ $name };
#                 } else {
#                     @pats = @{ $lib{ $name } };
#                 }
#             }
#             else {
#                 &error( qq (Pattern "$name" not found in "$file") );
#             }
#         }
#         else {
#             &dump( \%lib );
#         }
#     }
#     else {
#         &error( qq (Pattern string, library + name, or existing file must be given) );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     %allowed = map { $_, 1 } qw ( name title patstr fetch fetch_rev check elems );

#     foreach $pat ( @pats )
#     {
#         foreach $field ( keys %{ $pat } ) 
#         {
#             if ( not exists $allowed{ $field } ) {
#                 push @msgs, qq (Wrong looking field -> "$field");
#             }
#         }
                         
#         foreach $field ( qw ( name patstr ) )
#         {
#             if ( not exists $pat->{ $field } ) {
#                 push @msgs, qq (Missing mandatory field -> "$field");
#             }
#         }
#     }
    
#     if ( @msgs ) {
#         &error( \@msgs );
#     }
    
#     &echo_green( (scalar @pats) ."\n" ) unless $silent;

#     return wantarray ? @pats : \@pats;
# }

# sub params_extract
# {
#     # Creates a parameter hash with values for the extract routine.

#     my ( $args,    # Arguments object
#         ) = @_;

#     # Returns a hash.

#     my ( @pats, $pat, $pat_file, $params, $elems, $fetch );

#     if ( $args->patname )
#     {
#         @pats = &Seq::Clean::load_pattern( $args, 1 );

#         foreach $pat ( @pats )
#         {
#             $pat_file = "$Common::Config::tmp_dir/$pat->{'name'}_$$.pat";
#             &Common::File::write_file( $pat_file, $pat->{"patstr"} ."\n", 1 );

#             $pat->{"file"} = $pat_file;
#             $elems = $pat->{"elems"};

#             if ( defined $pat->{"check"} )
#             {
#                 $pat->{"qual_ndcs+"} = [ split /\s*,\s*/, $pat->{"check"} ];
#                 $pat->{"qual_ndcs-"} = [ map { $elems - $_ - 1 } split /\s*,\s*/, $pat->{"check"} ];

#                 delete $pat->{"check"};
#             }

#             if ( defined $pat->{"fetch"} or defined $pat->{"fetch_rev"} )
#             {
#                 $fetch = $pat->{"fetch"} // $pat->{"fetch_rev"};

#                 $pat->{"get_ndcs+"} = [ split /\s*,\s*/, $fetch ];
#                 $pat->{"get_ndcs-"} = [ map { $elems - $_ - 1} split /\s*,\s*/, $fetch ];

#                 delete $pat->{"fetch"};

#                 if ( $pat->{"fetch_rev"} )
#                 {
#                     $pat->{"complement"} = 1;
#                     delete $pat->{"fetch_rev"};
#                 }
#             }

#             delete $pat->{"elems"};

#             push @{ $params->{"pattern"} }, &Storable::dclone( $pat );
#         }
#     }

#     $params->{"multi"} = $args->multi;

#     if ( ($args->minqual > 0 or $args->maxqual < 100) and 
#          ($args->minpct > 0 or $args->maxpct < 100) )
#     {
#         $params->{"quality"} = 
#         {
#             "minqual" => $args->minqual / 100,
#             "maxqual" => $args->maxqual / 100,
#             "minpct" => $args->minpct,
#             "maxpct" => $args->maxpct,
#         };
#     }
    
#     return wantarray ? %{ $params } : $params;
# }

# sub params_filter
# {
#     # Niels Larsen, January 2010.

#     # Creates a parameter hash with values for the filter routine.

#     my ( $args,    # Arguments object
#         ) = @_;

#     # Returns a hash.

#     my ( @pats, $pat, $pat_file, $params, $qual_enc );

#     $params->{"nonmatch"} = $args->nonmatch;

#     if ( $args->patstr or $args->patfile or $args->patname )
#     {
#         @pats = &Seq::Clean::load_pattern( $args, 1 );

#         foreach $pat ( @pats )
#         {
#             $pat_file = "$Common::Config::tmp_dir/$pat->{'name'}_$$.pat";
#             &Common::File::write_file( $pat_file, $pat->{"patstr"} ."\n", 1 );

#             $pat->{"file"} = $pat_file;
            
#             push @{ $params->{"pattern"} }, &Storable::dclone( $pat );
#         }
#     }
    
#     if ( ($args->minqual > 0 or $args->maxqual < 100) and 
#          ($args->minpct > 0 or $args->maxpct < 100) )
#     {
#         $qual_enc = &Seq::Common::qual_config( $args->qualtype );

#         $params->{"quality"} = 
#         {
#             "minqual" => $args->minqual / 100,
#             "maxqual" => $args->maxqual / 100,
#             "minch" => &Seq::Common::qual_to_qualch( $args->minqual / 100, $qual_enc ),
#             "maxch" => &Seq::Common::qual_to_qualch( $args->maxqual / 100, $qual_enc ),
#             "minpct" => $args->minpct,
#             "maxpct" => $args->maxpct,
#             "winlen" => $args->winlen,
#         };
#     }
    
#     if ( ($args->minlen > 1 or defined $args->maxlen) )
#     {
#         $params->{"length"} = 
#         {
#             "minlen" => $args->minlen,
#             "maxlen" => $args->maxlen,
#         };
#     }

#     return wantarray ? %{ $params } : $params;
# }

# sub validate_args
# {
#     # Niels Larsen, October 2009.

#     # Checks consistency of arguments used by routines in this module. 
#     # Exits with printed messages in void context, otherwise returns 
#     # list or nothing.

#     my ( $files,
#          $args,         # Arguments as object
#          $msgs,
#         ) = @_;

#     # Returns nothing.

#     my ( @files, @ifiles, $errs, $file, $iformat, $oformat, $method,
#          $qual_given, $pct_given, $len_given, $min, $max );

#     $errs = [];
#     $method = $args->method // "";

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> FILES AND FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Input sequence files: input can come from stdin, but if files given all
#     # must be readable,

#     push @ifiles, @{ $files } if ($files and @{ $files });
#     push @ifiles, $args->iseqs if $args->iseqs;
    
#     if ( (-t STDIN) and not @ifiles ) {
#         push @{ $errs }, qq (No input given by file or coming from STDIN);
#     }

#     foreach $file ( @ifiles )
#     {
#         if ( &Common::File::access_error( $file, "er", 0 ) ) {
#             push @{ $errs }, qq (Input sequence file not found -> "$file");
#         }
#     }

#     # Input configuration file: mandatory when running a work-flow,

#     if ( $args->method eq "run_flow" )
#     {
#         if ( $file = $args->iconf )
#         {
#             if ( &Common::File::access_error( $file, "er", 0 ) ) {
#                 push @{ $errs }, qq (Input pipe configuration file not found -> "$file");
#             }
#         }
#         else {
#             push @{ $errs }, qq (Pipe configuration file must be given);
#         }
#     }

#     # Output sequence files: if not defined, infer names from input files; 
#     # if a named file given, make sure it is writable; if --oseqs defined 
#     # but no file given, send to stdout,
    
#     @files = ();

#     if ( defined $args->oseqs ) {
#         @files = $args->oseqs if $args->oseqs;
#     } else {
#         @files = map { $_ . $args->osuffix } @ifiles;
#     }

#     if ( @files and not $args->clobber and not $args->append ) 
#     {
#         foreach $file ( @files )
#         {
#             if ( not &Common::File::access_error( $file, "e", 0 ) ) {
#                 push @{ $errs }, qq (Output sequence file exists -> "$file");
#             }
#         }
#     }
    
#     # Output statistics files,

#     @files = ();

#     if ( $args->ostats ) {
#         @files = $args->ostats;
#     }
#     elsif ( defined $args->ostats )
#     {
#         if ( @ifiles ) {
#             @files = map { $_ . $args->osuffix . $args->ssuffix } @ifiles;
#         } else {
#             push @{ $errs }, qq (Statistics file or output file must be given with --ostats with input from STDIN);
#         }
#     }

#     # if ( not $args->clobber and not $args->append ) 
#     # {
#     #     foreach $file ( @files )
#     #     {
#     #         if ( not &Common::File::access_error( $file, "e", 0 ) ) {
#     #             push @{ $errs }, qq (Output statistics file exists -> "$file");
#     #         }
#     #     }
#     # }

#     # Format names,

#     if ( ($iformat = $args->iformat) =~ /^fasta|fastq$/i ) {
#         $args->iformat( lc $iformat );
#     } else {
#         push @{ $errs }, qq (Wrong looking input format -> "$iformat");
#     }

#     if ( ($oformat = $args->oformat) =~ /^fasta|fastq$/i ) {
#         $args->oformat( lc $oformat );
#     } else {
#         push @{ $errs }, qq (Wrong looking output format -> "$oformat");
#     }
    
#     # Format compatibility,

#     if ( ( $iformat = $args->iformat ) eq "fasta" )
#     {
#         if ( ( $oformat = $args->oformat ) ne "fasta" ) {
#             push @{ $errs }, qq (Output format "$oformat" not compatible with "$iformat" input format);
#         }
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>> PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     if ( $method ne "run_flow" )
#     {
#         # Quality encoding,

#         &Seq::Common::qual_config( $args->qualtype, $errs );

#         # Quality bounds,

#         ( $min, $max ) = ( $args->minqual // 0, $args->maxqual // 100 );

#         if ( $min < 0 or $min > 100 ) { 
#             push @{ $errs }, qq (Mininum quality ($min) must be between 0 and 100);
#         }
        
#         if ( $max < 0 or $max > 100 ) {
#             push @{ $errs }, qq (Maximum quality ($max) must be between 0 and 100);
#         }
        
#         if ( $min > $max ) {
#             push @{ $errs }, qq (Quality minimum ($min) higher than maximum ($max));
#         }
        
#         if ( $min > 0 or $max < 100 and not @{ $errs } ) {
#             $qual_given = 1;
#         }
        
#         # Stringency bounds,
        
#         ( $min, $max ) = ( $args->minpct // 0, $args->maxpct // 100 );
        
#         if ( $min < 0 or $min > 100 ) { 
#             push @{ $errs }, qq (Minimum stringency ($min) must be between 0 and 100);
#         }
        
#         if ( $max < 0 or $max > 100 ) {
#             push @{ $errs }, qq (Maximum stringency ($max) must be between 0 and 100);
#         }
        
#         if ( $min > $max ) {
#             push @{ $errs }, qq (Stringency minimum ($min) higher than maximum ($max));
#         }
        
#         if ( ( $min > 0 or $max < 100 ) and not @{ $errs } ) {
#             $pct_given = 1;
#         }
        
#         # Length bounds,
        
#         ( $min, $max ) = ( $args->minlen // 1, $args->maxlen );
        
#         if ( $min < 1 ) { 
#             push @{ $errs }, qq (Minimum length ($min) must be at least 1);
#         }
        
#         if ( defined $max ) 
#         {
#             if ( $max < 1 ) {
#                 push @{ $errs }, qq (Maximum length ($max) must be at least 1);
#             } elsif ( $min > $max ) {  
#                 push @{ $errs }, qq (Maximum length ($max) is be greater than minimum ($min));
#             }
#         }
        
#         if ( $min > 1 or defined $max ) {
#             $len_given = 1;
#         }
        
#         # Either pattern and/or quality+percentage must be given,
        
#         if ( $method eq "filter" or $method eq "extract" or $method eq "trim_qual" )
#         {
#             if ( $qual_given and not $pct_given ) {
#                 push @{ $errs }, qq (A minimum percentage must be given with quality);
#             } elsif ( $pct_given and not $qual_given ) {
#                 push @{ $errs }, qq (A quality cutoff must be given with percentage);
#             } elsif ( not $qual_given and not $pct_given and not $len_given and 
#                       not ( $args->patstr or $args->patname or $args->patfile ) ) {
#                 push @{ $errs }, qq (Either a pattern or quality + percentage or length must be given);
#             }
#         }
        
#         # Input vs output format check,
        
#         if ( ( $iformat = $args->iformat ) eq "fasta" )
#         {
#             if ( $qual_given and $pct_given ) {
#                 push @{ $errs }, qq (Quality filtering impossible with \"$iformat\" input);
#             }
#         }
        
#         # Either beginnings or ends must be given,
        
#         if ( not $args->begs and not $args->ends ) {
#             push @{ $errs }, qq (Either beginnings or ends flags must be given);
#         }
#     }

#     if ( @{ $errs } )
#     {
#         if ( defined $msgs ) {
#             $msgs = $errs;
#         } else {
#             &Workflow::Messages::save_errors( [ map { ["ERROR", $_] } @{ $errs } ], $args );
#             &Workflow::Messages::show_errors( [ map { ["ERROR", $_] } @{ $errs } ] );
#             exit -1;
#         }
#     }

#     return $args;
# }


# sub trim_seq_code
# {
#     my ( $args,
#          $func,
#          $stat,
#         ) = @_;

#     my ( $code, $pstr, $dist, $diff, $mpct, $mmin );

#     $func //= 1;
#     $stat //= 1;

#     $code = qq (sub\n{\n    my ( \$seqs, \$stats ) = \@_;\n\n) if $func;

#     if ( $stat )
#     {
#         $code .= qq (    \$stats->[0]->{"iseq"} += scalar \@{ \$seqs };\n);
#         $code .= qq (    \$stats->[0]->{"ires"} += &Seq::List::sum_length( \$seqs );\n);
#     }

#     ( $pstr, $dist, $diff, $mpct, $mmin ) = ( $args->{"seq"},
#                                               $args->{"dist"} // length $args->{"seq"},
#                                               $args->{"diff"} // 100,
#                                               $args->{"minpct"} // 80,
#                                               $args->{"minlen"} // 1 );

#     if ( $args->{"begs"} ) {
#         $code .= qq (    \$seqs = &Seq::List::trim_seq_beg( \$seqs, '$pstr', $dist, $diff, $mpct, $mmin );\n);
#     }

#     if ( $args->{"ends"} ) {
#         $code .= qq (    \$seqs = &Seq::List::trim_seq_end( \$seqs, '$pstr', $dist, $diff, $mpct, $mmin );\n);
#     }

#     if ( $stat )
#     {
#         $code .= qq (\n    \$stats->[0]->{"oseq"} += scalar \@{ \$seqs };\n);
#         $code .= qq (    \$stats->[0]->{"ores"} += &Seq::List::sum_length( \$seqs );\n);
#     }

#     $code .= qq (\n    return \$seqs;\n}\n) if $func;

#     return $code;
# }
