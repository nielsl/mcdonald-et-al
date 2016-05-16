package DNA::Map;     #  -*- perl -*-

# Routines that are related to DNA alignment and matches.

use strict;
use warnings FATAL => qw ( all );

require Exporter; 
use Cwd;

our @ISA = qw ( Exporter );
our @EXPORT_OK = qw (
                     &approve_arguments
                     &build_synteny_map
                     &chain_matches
                     &chain_matches_beg
                     &chain_matches_end
                     &chains_debug
                     &clip_match
                     &clip_match_beg
                     &clip_match_end
                     &clip_matches_beg
                     &clip_matches_end
                     &create_chains_table
                     &get_match
                     &get_matches
                     &matches_overlap
                     &print_chains
                     &print_errors
                     &print_matches
                     &read_mummer_matches
                     &read_blast_matches
                     &validate_arguments

                     &min_index_C
                     &max_index_C
                     );

use Common::Config;
use Common::Messages;

use Storable qw ( dclone );
use PDL::Lite;

use Common::File;
use Common::Names;
use Common::Util;

BEGIN
{
    my $inline_dir = &Common::Config::create_inline_dir("DNA/Map");
    $ENV{"PERL_INLINE_DIRECTORY"} = $inline_dir;

    use Inline ( C => 'DATA' );
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>> CONSTANTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Match and chain array index global constants,

use constant Q_BEG => 0;
use constant Q_END => 1;
use constant S_BEG => 2;
use constant S_END => 3;
use constant LENGTH => 4;
use constant SCORE => 5;
use constant C_ID => 6;
use constant M_ID => 7;

use constant ELEMS => 4;
use constant Q_GAPS => 7;
use constant S_GAPS => 8;
use constant Q_LEN => 9;
use constant S_LEN => 10;
use constant BASES => 5;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub approve_arguments
{
    # Niels Larsen, December 2004.

    # Validates the arguments needed by the build_synteny_map and 
    # chain_matches routines. It checks user input is reasonable, 
    # that mandatory files exist, adds defaults and expands file 
    # names to their absolute paths. If errors are found, a list
    # of printable error strings are returned. 

    my ( $cl_args,    # Command line argument hash
         ) = @_;

    # Returns a list or nothing. The input hash is modified.

    # >>>>>>>>>>>>>>>>>>>>> CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<

    my ( @errors, $error, $dir );

    # The mandatory SEED id input file: if given, expand to absolute path 
    # and check that its readable. If not given, error,

    if ( $cl_args->{"sids"} )
    {
        $cl_args->{"sids"} = &Cwd::abs_path( $cl_args->{"sids"} );
        
        if ( not -r $cl_args->{"sids"} ) {
            push @errors, qq (SEED id list not found -> "$cl_args->{'sids'}");
        }
    }
    else {
        push @errors, qq (SEED id list must be given);
    }

    # The mandatory SEED organism directory: if given, expand to absolute path 
    # and check that its readable. If not given, error,

    if ( $cl_args->{"orgs"} )
    {
        $cl_args->{"orgs"} = &Cwd::abs_path( $cl_args->{"orgs"} );
        chop $cl_args->{"orgs"} if $cl_args->{"orgs"} =~ /\/$/;
        $dir = $cl_args->{"orgs"};
        
        if ( not -d $dir ) {
            push @errors, qq (SEED organism directory does not exist -> "$dir");
        } elsif ( not -r $dir ) {
            push @errors, qq (SEED organism directory is not readable -> "$dir");
        }            
    }
    else {
        push @errors, qq (SEED organism directory must be given);
    }

    # The mandatory aligned sequence input file: if given, expand to absolute 
    # path and check that its readable. If not given, error,

    if ( $cl_args->{"ali"} )
    {
        $cl_args->{"ali"} = &Cwd::abs_path( $cl_args->{"ali"} );
        
        if ( not -r $cl_args->{"ali"} ) {
            push @errors, qq (Aligned SSU sequences not found -> "$cl_args->{'ali'}");
        }
    }
    else {
        push @errors, qq (Aligned sequences file (Genbank format) must be given);
    }

    # If output file given, check if it exists and if its directory does not exist,

    if ( $cl_args->{"out"} )
    {
        $cl_args->{"out"} = &Cwd::abs_path( $cl_args->{"out"} );
        
        if ( -e $cl_args->{"out"} )        {
            push @errors, qq (Output file exists -> "$cl_args->{'out'}");
        }
        
        $dir = &File::Basename::dirname( $cl_args->{"out"} );
        
        if ( not -d $dir ) {
            push @errors, qq (Output directory does not exist -> "$dir");
        } elsif ( not -w $dir ) {
            push @errors, qq (Output directory is not writable -> "$dir");
        }            
    }
    
    # If log file given, check if it exists and if its directory does not exist,

    if ( $cl_args->{"log"} )
    {
        $cl_args->{"log"} = &Cwd::abs_path( $cl_args->{"log"} );
        
        if ( -e $cl_args->{"log"} )        {
            push @errors, qq (Log file exists -> "$cl_args->{'log'}");
        }
        
        $dir = &File::Basename::dirname( $cl_args->{"log"} );
        
        if ( not -d $dir ) {
            push @errors, qq (Log directory does not exist -> "$dir");
        } elsif ( not -w $dir ) {
            push @errors, qq (Log directory is not writable -> "$dir");
        }            
    }
    else {
        $cl_args->{"log"} = "";
    }
    
    # If scratch directory given, check if it exists,
    
    if ( $cl_args->{"temp"} )
    {
        $cl_args->{"temp"} = &Cwd::abs_path( $cl_args->{"temp"} );
        chop $cl_args->{"temp"} if $cl_args->{"temp"} =~ /\/$/;
        $dir = $cl_args->{"temp"};
        
        if ( not -d $dir ) {
            push @errors, qq (Scratch directory does not exist -> "$dir");
        } elsif ( not -w $dir ) {
            push @errors, qq (Scratch directory is not writable -> "$dir");
        }            
    }
    else {
        push @errors, qq (Scratch directory must be given);
    }
    
    # Remove undefs,
    
    $cl_args->{"silent"} ||= 0;
    
    # Print errors if any and exit,

    if ( @errors )
    {
        foreach $error ( @errors )
        {
            &echo_red( "ERROR: ");
            &echo( "$error\n" );
        }
        
        exit;
    }
    else {
        wantarray ? return %{ $cl_args } : return $cl_args;
    }
}

sub build_synteny_map
{
    # Niels Larsen, December 2004.

    # Builds a table of matches and "chains" of matches from two 
    # fasta formatted files of DNA sequence, perhaps with multiple
    # contigs in each. First blastn, megablast or mummer generates
    # a temporary file of input matches that are then combined and
    # extended. The result files contain coordinates of regions of
    # that match reasonably (in other organisms or in the same.) 

    my ( $params,
         ) = @_;

    # Returns nothing.

    my ( @errors, $error );

    if ( @errors = &DNA::Map::approve_arguments( $params ) )
    {
        foreach $error ( @errors )
        {
            &echo_red( "ERROR: ");
            &echo( "$error\n" );
        }
        
        exit;
    }

    

#                     "rfile=s" => \$cl_args->{"rfile"},
#                     "qfiles=s" => \$cl_args->{"qfiles"},
#                     "tmpdir=s" => \$cl_args->{"tmpdir"},
#                     "program=s" => \$cl_args->{"program"},
#                     "lenmin=i" => \$cl_args->{"lenmin"},
#                     "gapmax=i" => \$cl_args->{"gapmax"},
#                     "seedmin=i" => \$cl_args->{"seedmin"},
#                     "basemin=i" => \$cl_args->{"basemin"},
#                     "extqual=f" => \$cl_args->{"extqual"},
#                     "chains:s" => \$cl_args->{"chains"},
#                     "matches=s" => \$cl_args->{"matches"},
#                     "errors=s" => \$cl_args->{"errors"},
#                     "headers!" => \$cl_headers,
    
}

sub chain_matches
{
    # Niels Larsen, November 2004.

    # Links together matches that are part of larger "chains". It does this 
    # by simply starting with the longest matches ("seeds") looks in a given
    # search space from each end for decent matches that can be added. 
    # Parameters, given as an optional argument, as key/value pairs, are
    # 
    #  "gapmax" - default 1000, size of search space 
    #  "seedmin" - default 100, minimum match length for "seeds"
    #  "basemin" - default 500, minimum number of bases 
    #  "extqual" - default 2.0, quality of extension 
    # 
    # Quality of extension is calculated as the square of the length of the 
    # potential extension match divided by the size of the search space 
    # between the new match and the end of the chain.
    
    my ( $params,      # Parameter hash - OPTIONAL
         ) = @_;
    
    # Returns an array.
    
    my ( $seed, $i, $chain_id, $bases, $matches, $map, $i_max, @chain, $extension,
         %used, @results, $count, $seed_ids, $seed_id, $seed_lens, $ndx );
    
    # Defaults,
    
    $params = {
        "gapmax" => 1000,
        "lenmin" => 10,
        "seedmin" => 100,
        "basemin" => 500,
        "extqual" => 2.0,
        %{ $params }
    };

    # >>>>>>>>>>>>>>>>>>>>>>> GET MUMMER INPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Reading mummer matches ... ) );

    # We use the element numbers as ids, and there are an equal number of 
    # elements in q_begs, s_begs and lengths, 

    $matches = &DNA::Map::read_mummer_matches( $params );

    ( undef, $count ) = &PDL::Core::dims( $matches );
    $i_max = $count - 1;

    &echo_green( "total ".&Common::Util::commify_number( $count ) ."\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE SEED IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create vector with seed indices, sorted by length,

    $seed_ids = &PDL::Basic::sequence( $i_max + 1 );      # zero-based 
    $seed_lens = &PDL::copy( &PDL::Slices::slice( $matches, 2 ) );

    $seed_ids = &PDL::Primitive::where( $seed_ids, $seed_lens >= $params->{"seedmin"} );
#    print $seed_ids;

    $seed_lens = &PDL::Primitive::where( $seed_lens, $seed_lens >= $params->{"seedmin"} );
    $seed_ids = &PDL::Slices::index( $seed_ids, &PDL::Ufunc::qsorti( $seed_lens ) );
#    undef $seed_lens;

    ( $count ) = &PDL::Core::dims( $seed_ids );
    &echo( "   Matches selected as seeds ... " );
    &echo_green( "total ".&Common::Util::commify_number( $count ). "\n" );

    # >>>>>>>>>>>>>>>>>>>>>> CREATE SEARCH VECTORS <<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Creating sorted lookup indices ... ) );

    $map->{"Q_BEGS"} = &PDL::copy( &PDL::Slices::slice( $matches, "(0),:,(0)" ) );
    $map->{"Q_BEGS_I"} = &PDL::Ufunc::qsorti( $map->{"Q_BEGS"} );

    $map->{"S_BEGS"} = &PDL::copy( &PDL::Slices::slice( $matches, "(1),:,(0)" ) );
    $map->{"S_BEGS_I"} = &PDL::Ufunc::qsorti( $map->{"S_BEGS"} );

    $map->{"Q_ENDS"} = &PDL::copy( $map->{"Q_BEGS"} );
    $map->{"Q_ENDS"} += &PDL::Slices::slice( $matches, "(2),:,(0)" ) - 1;
    $map->{"Q_ENDS_I"} = &PDL::Ufunc::qsorti( $map->{"Q_ENDS"} );

    $map->{"S_ENDS"} = &PDL::copy( $map->{"S_BEGS"} );
    $map->{"S_ENDS"} += &PDL::Slices::slice( $matches, "(2),:,(0)" ) - 1;
    $map->{"S_ENDS_I"} = &PDL::Ufunc::qsorti( $map->{"S_ENDS"} );

    $map->{"Q_BEGS"} = &PDL::Ufunc::qsort( $map->{"Q_BEGS"} );
    $map->{"S_BEGS"} = &PDL::Ufunc::qsort( $map->{"S_BEGS"} );
    $map->{"Q_ENDS"} = &PDL::Ufunc::qsort( $map->{"Q_ENDS"} );
    $map->{"S_ENDS"} = &PDL::Ufunc::qsort( $map->{"S_ENDS"} );

    $map->{"IMAX"} = $i_max;

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CHAIN LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Chaining matches (patience) ... ) );

    $chain_id = 0;

    for ( $ndx = &PDL::Core::nelem( $seed_ids )-1; $ndx >= 0; $ndx-- )
    {
        $seed_id = &PDL::Core::at( $seed_ids, $ndx );
        $seed = &DNA::Map::get_match( $matches, $seed_id );

        next if $used{ $seed_id };
        
        @chain = ( $seed );

        # Add matches to beginning,

         while ( $extension = &DNA::Map::chain_matches_beg( $params, \@chain, \%used,
                                                           $matches, $map ) )
         {
             unshift @chain, @{ &Storable::dclone( $extension ) };
         }
        
        # Add matches to end,
        
        while ( $extension = &DNA::Map::chain_matches_end( $params, \@chain, \%used,
                                                           $matches, $map ) )
        {
            push @chain, @{ &Storable::dclone( $extension ) };
        }

        # Accept chain only if it includes more bases than required,

        $bases = 0;
        map { $bases += $_->[Q_END] - $_->[Q_BEG] + 1 } @chain;

        if ( $bases >= $params->{"basemin"} )
        {
            $chain_id++;

            for ( $i = 0; $i <= $#chain; $i++ )
            {
                $used{ $chain[$i]->[M_ID] } = 1;
                $chain[$i]->[C_ID] = $chain_id;
            }

            push @results, @chain;
        }
    }
    
    $count = &Common::Util::commify_number( scalar @results );
    &echo_green( "$count in chains\n" );
    
    if ( @results ) {
        return wantarray ? @results : \@results;
    } else {
        return;
    }
}

sub chain_matches_beg
{
    # Niels Larsen, December 2004.

    # Looks for reasonable matches within a given distance from a chain
    # end and returns these if any.

    my ( $params,          # Command line arguments
         $chain,           # Growing list of matches
         $used,            # Hash of $id => 1 pairs
         $matches,         # Piddle of q_beg, s_beg, length rows
         $map,             # Contains eight search vectors
         ) = @_;

    # Returns an array. 

    my ( $matches_in_area, $i, $j, @anchors, $anchor, 
         @extension, $area, $ids, $q_ids, $s_ids, $match, $i_max );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DEFINE SEARCH AREA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Set it to a square that extends "gapmax" from the end of the last match,
    
    $area->[Q_END] = $chain->[0]->[Q_BEG] - 1;
    $area->[Q_BEG] = $area->[Q_END] - $params->{"gapmax"} + 1;
    
    $area->[S_END] = $chain->[0]->[S_BEG] - 1;
    $area->[S_BEG] = $area->[S_END] - $params->{"gapmax"} + 1;

    $i_max = $map->{"IMAX"};    # Max index in search vectors
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FIND MATCHES IN AREA <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Below we find all ids of fragments whose end positions are in the search 
    # area and that dont overlap with the chain beginning by more than 100 positions.
    # The value 100 is completely arbitrary but it should catch almost all good 
    # matches that sometimes overlap slightly due to low complexity sequence,

    # Q end ids,

    $i = &DNA::Map::min_index_C( $map->{"Q_ENDS"}->get_dataref(), $area->[Q_BEG], 0, $i_max );
    $j = &DNA::Map::max_index_C( $map->{"Q_ENDS"}->get_dataref(), $area->[Q_END]+100, $i, $i_max );

    if ( $i <= $j ) {
        $q_ids = &PDL::Slices::slice( $map->{"Q_ENDS_I"}, "$i:$j" );
    } else {
        return;
    }

    $q_ids = &PDL::Primitive::where( $q_ids, $q_ids != $chain->[0]->[M_ID] );  # May get itself
    return if &PDL::Core::isempty( $q_ids );

    # S end ids,

    $i = &DNA::Map::min_index_C( $map->{"S_ENDS"}->get_dataref(), $area->[S_BEG], 0, $i_max );
    $j = &DNA::Map::max_index_C( $map->{"S_ENDS"}->get_dataref(), $area->[S_END]+100, $i, $i_max );
    
    if ( $i <= $j ) {
        $s_ids = &PDL::Slices::slice( $map->{"S_ENDS_I"}, "$i:$j" );
    } else {
        return;
    }
    
    $s_ids = &PDL::Primitive::where( $s_ids, $s_ids != $chain->[0]->[M_ID] );  # May get itself
    return if &PDL::Core::isempty( $s_ids );

    # Get the intersection and corresponding matches,

    $ids = &PDL::Primitive::where( $q_ids, &PDL::Primitive::in( $q_ids, $s_ids ) );
    return if &PDL::Core::isempty( $ids );

    $matches_in_area = &DNA::Map::get_matches( $matches, $ids );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Discard used ones, meaning extension will stop if used before,

    $matches_in_area = [ grep { not $used->{ $_->[M_ID] } } @{ $matches_in_area } ];
    return if not $matches_in_area;
    
    # Must clip ends because above we allowed ends slightly outside area,

    $matches_in_area = &DNA::Map::clip_matches_end( $area->[Q_END], $area->[S_END], $matches_in_area );
    return if not $matches_in_area;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LOOK FOR "ANCHOR" <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # To avoid heading into garbage, we want to accept a real good match even 
    # though it is at some distance from the beginning and then fill in with 
    # whatever smaller matches are in between. So we look for an "anchor" that
    # is either rather close to the beginning we wish to extend or is very long.
    # And after picking the best, we fill in the space between the chain end 
    # and the anchor with whatever smaller matches are in between, aligned if
    # necessary. First add quality score,
     
    foreach $match ( @{ $matches_in_area } )
    {
        $match->[SCORE] = $match->[LENGTH]**2 
                        / &Common::Util::max( $area->[Q_END] - $match->[Q_END],
                                              $area->[S_END] - $match->[S_END] )**2;
    }
    
    # Then get anchor candidates,

    @anchors = grep { $_->[SCORE] >= $params->{"extqual"} } @{ $matches_in_area };
    
    if ( @anchors )
    {
        # Pick the best one and add it as extension,
        
        $anchor = ( sort { $b->[SCORE] <=> $a->[SCORE] } @anchors )[0];
        @extension = $anchor;
        
        # If there is room between this anchor and end of area, pick an
        # optimal set of whatever smaller fragments may fit in,
        
        if ( $anchor->[Q_END]+1 < $area->[Q_END] and $anchor->[S_END]+1 < $area->[S_END] )
        {
            # See if there are matches in the area between anchor and chain begin,

            $area->[Q_BEG] = $anchor->[Q_END] + 1;
            $area->[S_BEG] = $anchor->[S_END] + 1;
            
            $matches_in_area = &DNA::Map::clip_matches_beg( $area->[Q_BEG], $area->[S_BEG], $matches_in_area );
            
            # If so align them,
            
            if ( $matches_in_area )
            {
                # If there is only one little match in the area, should we accept
                # it without conditions? yes think so,
                
                if ( scalar @{ $matches_in_area } == 1 )
                {
                    push @extension, $matches_in_area->[0];
                }
                elsif ( scalar @{ $matches_in_area } > 1 )
                {
                    push @extension, &DNA::Ali::align_two_dnas( undef, undef, 
                                                                $matches_in_area, $params, undef,
                                                                $area->[Q_BEG], $area->[Q_END], 
                                                                $area->[S_BEG], $area->[S_END] );
                }
            }
        }
    }
    
    if ( @extension ) {
        return wantarray ? @extension : \@extension;
    } else {
        return;
    }
}

sub chain_matches_end
{
    # Niels Larsen, December 2004.

    # Looks for reasonable matches within a given distance from a chain
    # end and returns these if any.

    my ( $params,          # Command line arguments
         $chain,           # Growing list of matches
         $used,            # Hash of $id => 1 pairs
         $matches,         # Piddle of q_beg, s_beg, length rows
         $map,             # Contains eight search vectors
         ) = @_;

    # Returns an array. 

    my ( $matches_in_area, $i, $j, @anchors, $anchor,
         @extension, $area, $ids, $q_ids, $s_ids, $match, $i_max );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> DEFINE SEARCH AREA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set it to a square that extends "gapmax" from the end of the last match,

    $area->[Q_BEG] = $chain->[-1]->[Q_END] + 1;
    $area->[Q_END] = $area->[Q_BEG] + $params->{"gapmax"} - 1;
    
    $area->[S_BEG] = $chain->[-1]->[S_END] + 1;
    $area->[S_END] = $area->[S_BEG] + $params->{"gapmax"} - 1;

    $i_max = $map->{"IMAX"};  # Max index of search vectors

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FIND MATCHES IN AREA <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Below we find all ids of fragments whose begin positions are in the search 
    # area and that dont overlap with the chain end by more than 100 positions.
    # The value 100 is completely arbitrary but it should catch almost all good 
    # matches that sometimes overlap slightly due to low complexity sequence,

    # Q begins,

    $i = &DNA::Map::min_index_C( $map->{"Q_BEGS"}->get_dataref(), $area->[Q_BEG]-100, 0, $i_max );
    $j = &DNA::Map::max_index_C( $map->{"Q_BEGS"}->get_dataref(), $area->[Q_END], $i, $i_max );

    if ( $i <= $j ) {
        $q_ids = &PDL::Slices::slice( $map->{"Q_BEGS_I"}, "$i:$j" );
    } else {
        return;
    }

    $q_ids = &PDL::Primitive::where( $q_ids, $q_ids != $chain->[-1]->[M_ID] );  # May get itself
    return if &PDL::Core::isempty( $q_ids );

    # S begins, 

    $s_ids = &PDL::Core::null();

    $i = &DNA::Map::min_index_C( $map->{"S_BEGS"}->get_dataref(), $area->[S_BEG]-100, 0, $i_max );
    $j = &DNA::Map::max_index_C( $map->{"S_BEGS"}->get_dataref(), $area->[S_END], $i, $i_max );
    
    if ( $i <= $j ) {
        $s_ids = &PDL::Slices::slice( $map->{"S_BEGS_I"}, "$i:$j" );
    } else {
        return;
    }

    $s_ids = &PDL::Primitive::where( $s_ids, $s_ids != $chain->[-1]->[M_ID] );  # May get itself
    return if &PDL::Core::isempty( $s_ids );

    # Get the intersection and corresponding matches,

    $ids = &PDL::Primitive::where( $q_ids, &PDL::Primitive::in( $q_ids, $s_ids ) );
    return if &PDL::Core::isempty( $ids );

    $matches_in_area = &DNA::Map::get_matches( $matches, $ids );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Discard used ones, meaning extension will stop if used before,

    $matches_in_area = [ grep { not $used->{ $_->[M_ID] } } @{ $matches_in_area } ];
    return if not $matches_in_area;

    # Must clip ends because above we allowed begins slightly outside area,

    $matches_in_area = &DNA::Map::clip_matches_beg( $area->[Q_BEG], $area->[S_BEG], $matches_in_area );
    return if not $matches_in_area;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LOOK FOR "ANCHOR" <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # To avoid heading into garbage, we want to accept a real good match even 
    # though it is at some distance from the end and then fill in with whatever
    # smaller matches are in between. So we look for an "anchor" that is either
    # rather close to the end we wish to extend or is very long. And after picking 
    # the best, we fill in the space between the chain end and the anchor with 
    # whatever smaller matches are in between, aligned if necessary. 
    # First add quality score,

    foreach $match ( @{ $matches_in_area } )
    {
        $match->[SCORE] = $match->[LENGTH]**2 
                        / &Common::Util::max( $match->[Q_BEG] - $area->[Q_BEG],
                                              $match->[S_BEG] - $area->[S_BEG] )**2;
    }

    # Then get anchor candidates,

    @anchors = grep { $_->[SCORE] >= $params->{"extqual"} } @{ $matches_in_area };

    if ( @anchors )
    {
        # Pick the best one and add it as extension,
        
        $anchor = ( sort { $b->[SCORE] <=> $a->[SCORE] } @anchors )[0];
        @extension = $anchor;

        # If there is room between this anchor and beginning of area, pick an
        # optimal set of whatever smaller fragments may fit in,

        if ( $anchor->[Q_BEG]-1 > $area->[Q_BEG] and $anchor->[S_BEG]-1 > $area->[S_BEG] )
        {
            # See if there are matches in the area between anchor and chain end,
        
            $area->[Q_END] = $anchor->[Q_BEG] - 1;
            $area->[S_END] = $anchor->[S_BEG] - 1;

            $matches_in_area = &DNA::Map::clip_matches_end( $area->[Q_END], $area->[S_END], $matches_in_area );
            
            # If so align them,
            
            if ( $matches_in_area )
            {
                # If there is only one little match in the area, should we accept
                # it without conditions? yes think so,
                
                if ( scalar @{ $matches_in_area } == 1 )
                {
                    unshift @extension, $matches_in_area->[0];
                }
                elsif ( scalar @{ $matches_in_area } > 1 )
                {
                    unshift @extension, &DNA::Ali::align_two_dnas( undef, undef, 
                                                                   $matches_in_area, $params, undef,
                                                                   $area->[Q_BEG], $area->[Q_END], 
                                                                   $area->[S_BEG], $area->[S_END] );
                }
            }
        }
    }
    
    if ( @extension ) {
        return wantarray ? @extension : \@extension;
    } else {
        return;
    }
}

sub chains_debug
{
    # Niels Larsen, November 2004.

    # Inconsistency checks, for debugging only. For chains, checks that 
    # begins are always lower than ends, that bases + gaps add up to the
    # totals, that there are no symmetrical ( = redundant) chains and that
    # none are included in another (but in itself is ok.) For matches that
    # make up a given chain, checks that all begins are lower than ends, 
    # that Q and S differences are always the same, that none overlap, that
    # the gap counts equal those for chains and that all matches agree with
    # sequence. Returns an array of printable messages.

    my ( $chains, 
         $matches,
         ) = @_;

    # Returns an array.

    my ( $i, $j, $id, $chain, @errors, $pos, $ci, $cj, $q_diff, $s_diff,
         $match, $m_bad, $match_prev );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CHAINS SECTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Check for negative gap lengths; matches are checked the same way
    # below, 

    foreach $chain ( @{ $chains } )
    {
        if ( $chain->[Q_GAPS] < 0 ) {
            push @errors, qq (ERROR, chain $chain->[C_ID]: Q_GAPS is negative -> "$chain->[Q_GAPS]"\n);
        }

        if ( $chain->[S_GAPS] < 0 ) {
            push @errors, qq (ERROR, chain $chain->[C_ID]: S_GAPS is negative -> "$chain->[S_GAPS]"\n);
        }
    }

    # Check that ends are always higher than begins,

    foreach $chain ( @{ $chains } )
    {
        if ( $chain->[Q_END] <= $chain->[Q_BEG] ) {
            push @errors, qq (ERROR, chain $chain->[C_ID]: Q_END <= Q_BEG\n);
        }

        if ( $chain->[S_END] <= $chain->[S_BEG] ) {
            push @errors, qq (ERROR, chain $chain->[C_ID]: S_END <= S_BEG\n);
        }
    }

    # Check that there are no symmetrical matches,

    foreach $chain ( @{ $chains } )
    {
        $pos->{ $chain->[Q_BEG] }->{ $chain->[Q_END] }
            ->{ $chain->[S_BEG] }->{ $chain->[S_END] } = $chain->[C_ID];
    }

    foreach $chain ( @{ $chains } )
    {
        if ( $id = $pos->{ $chain->[S_BEG] }->{ $chain->[S_END] }
                       ->{ $chain->[Q_BEG] }->{ $chain->[Q_END] } )
        {
            push @errors, qq (ERROR, chain $chain->[C_ID]: is symmetrical to chain $id\n);
        }
    }

    # Check that the number of bases plus the number of gaps add up
    # to the total q_len and s_len,

    foreach $chain ( @{ $chains } )
    {
        if ( $chain->[Q_LEN] != $chain->[BASES] + $chain->[Q_GAPS] ) {
            push @errors, qq (ERROR, chain $chain->[C_ID]: BASES + Q_GAPS does not equal Q_LEN\n);
        }

        if ( $chain->[S_LEN] != $chain->[BASES] + $chain->[S_GAPS] ) {
            push @errors, qq (ERROR, chain $chain->[C_ID]: BASES + S_GAPS does not equal S_LEN\n);
        }
    }

    # Check that no part of a chain is included in another (SLOW - fix it by sorting 4 times),

    for ( $i = 0; $i <= $#{ $chains }; $i++ )
    {
        $ci = $chains->[$i];

        for ( $j = $i+1; $j <= $#{ $chains }; $j++ )
        {
            $cj = $chains->[$j];

            if ( &DNA::Map::matches_overlap( $ci, $cj ) )
            {
                if ( $ci->[Q_BEG] < $cj->[Q_BEG] ) { 
                    $q_diff = $ci->[Q_END]-$cj->[Q_BEG]+1;
                } else {
                    $q_diff = $cj->[Q_END]-$ci->[Q_BEG]+1;
                }
                
                if ( $ci->[S_BEG] < $cj->[S_BEG] ) { 
                    $s_diff = $ci->[S_END]-$cj->[S_BEG]+1;
                } else {
                    $s_diff = $cj->[S_END]-$ci->[S_BEG]+1;
                }
                
                if ( $q_diff > $s_diff ) {
                    push @errors, qq (ERROR: chains $ci->[C_ID] and $cj->[C_ID] overlap by $q_diff bases\n);
                } else {
                    push @errors, qq (ERROR: chains $ci->[C_ID] and $cj->[C_ID] overlap by $s_diff bases\n);
                }
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MATCHES SECTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check that all ends are higher than begins,

    foreach $match ( @{ $matches } )
    {
        next if exists $m_bad->{ $match->[M_ID] };

        $q_diff = $match->[Q_END] - $match->[Q_BEG];
        $s_diff = $match->[S_END] - $match->[S_BEG];

        if ( $q_diff < 0 )
        {
            $m_bad->{ $match->[M_ID] } = 1;
            push @errors, qq (ERROR, match $match->[M_ID]: Q_BEG is higher than Q_END\n);
        } 
        elsif ( $s_diff < 0 )
        {
            $m_bad->{ $match->[M_ID] } = 1;
            push @errors, qq (ERROR, match $match->[M_ID]: S_BEG is higher than S_END\n);
        }
    }

    # Check that all Q and S ranges are equally long,

    foreach $match ( @{ $matches } )
    {
        $q_diff = $match->[Q_END] - $match->[Q_BEG];
        $s_diff = $match->[S_END] - $match->[S_BEG];

        if ( $q_diff != $s_diff )
        {
            $m_bad->{ $match->[M_ID] } = 1; 
            push @errors, qq (ERROR, match $match->[M_ID]: Q length is $q_diff, but S length is $s_diff\n);
        }
    }

    # Check that lengths match,

    foreach $match ( @{ $matches } )
    {
        $q_diff = $match->[Q_END] - $match->[Q_BEG];

        if ( $q_diff != $match->[LENGTH] - 1 )
        {
            $m_bad->{ $match->[M_ID] } = 1; 
            push @errors, qq (ERROR, match $match->[M_ID]: length is $q_diff, but should be $match->[LENGTH]\n);
        }
    }

    # Check that matches agree with sequence,

#    if ( $q_seq and $s_seq )
#    {
#        foreach $match ( @{ $matches } )
#        {
#            $q_subseq = substr ${ $q_seq }, $match->[Q_BEG], $match->[LENGTH];
#            $s_subseq = substr ${ $s_seq }, $match->[S_BEG], $match->[LENGTH];
#
#            if ( $q_subseq ne $s_subseq )
#            {
#                $m_bad->{ $match->[M_ID] } = 1; 
#                push @errors, qq (ERROR, match $match->[M_ID]: sequences are different\n);
#            }
#        }
#    }

    # Check for overlapping matches,

    $match_prev = $matches->[0];

    for ( $i = 1; $i <= $#{ $matches }; $i++ )
    {
        $match = $matches->[$i];

        if ( $match->[C_ID] == $match_prev->[C_ID] and
             &DNA::Map::matches_overlap( $match, $match_prev ) )
        {
            push @errors, qq (ERROR: match $match->[M_ID] overlaps with match $match_prev->[M_ID]\n);
        }

        $match_prev = $match;
    }

    # Check that 


    if ( @errors ) {
        return wantarray ? @errors : \@errors;
    } else {
        return;
    }
}   

sub clip_match
{
    # Niels Larsen, November 2004.

    # Clips a given match so its ends are within a given area.
    # If the match is outside the area nothing is returned.

    my ( $area,       # Area 
         $match,      # Match to be clipped
         ) = @_;

    # Returns an array or nothing. 

    my ( $clip );

    if ( $match->[Q_END] < $area->[Q_BEG] or $match->[S_END] < $area->[S_BEG] or
         $match->[Q_BEG] > $area->[Q_END] or $match->[S_BEG] > $area->[S_END] )
    {
        return;
    }
    else
    {
        $clip = &Common::Util::max( $area->[Q_BEG] - $match->[Q_BEG], $area->[S_BEG] - $match->[S_BEG] );

        if ( $clip > 0 )
        {
            $match->[Q_BEG] += $clip;
            $match->[S_BEG] += $clip;
            $match->[LENGTH] -= $clip;
        }

        $clip = &Common::Util::max( $match->[Q_END] - $area->[Q_END], $match->[S_END] - $area->[S_END] );
        
        if ( $clip > 0 )
        {
            $match->[Q_END] -= $clip;
            $match->[S_END] -= $clip;
            $match->[LENGTH] -= $clip;
        }
    }

    return $match;
}
    
sub clip_match_beg
{
    my ( $q_min,
         $s_min,
         $match,
         ) = @_;

    my ( $matches );

    $matches = &DNA::Map::clip_matches_beg( $q_min, $s_min, [ $match ] );

    if ( $matches ) {
        return $matches->[0];
    } else {
        return;
    }
}

sub clip_match_end
{
    my ( $q_max,
         $s_max,
         $match,
         ) = @_;

    my ( $matches );

    $matches = &DNA::Map::clip_matches_beg( $q_max, $s_max, [ $match ] );

    if ( $matches ) {
        return $matches->[0];
    } else {
        return;
    }
}

sub clip_matches_beg
{
    # Niels Larsen, December 2004.

    # Given a list of matches, returns only those matches with ends
    # that are >= given q and s minimum values. The begins of such 
    # matches are clipped so they are no lower than the given minimum 
    # values. 

    my ( $q_min,     # Q clip value
         $s_min,     # S clip value
         $matches,   # Match list
         ) = @_;

    # Returns a list.

    my ( @matches, $match, $clip );

    foreach $match ( @{ $matches } )
    {
        if ( $match->[Q_END] >= $q_min and $match->[S_END] >= $s_min )
        {
            $clip = &Common::Util::max( $q_min - $match->[Q_BEG], $s_min - $match->[S_BEG] );
            
            if ( $clip > 0 )
            {
                $match->[Q_BEG] += $clip;
                $match->[S_BEG] += $clip;
                $match->[LENGTH] -= $clip;
            }
            
            push @matches, $match;
        }
    }

    if ( @matches ) {
        return wantarray ? @matches : \@matches;
    } else {
        return;
    }
}

sub clip_matches_end
{
    # Niels Larsen, December 2004.

    # Given a list of matches, returns only those matches with begins
    # that are <= given q and s maximum values. The ends of such 
    # matches are clipped so they dont exceed the given maximum
    # values. 

    my ( $q_max,     # Q clip value
         $s_max,     # S clip value
         $matches,   # Match list
         ) = @_;

    # Returns a list.
    
    my ( @matches, $match, $clip );

    foreach $match ( @{ $matches } )
    {
        if ( $match->[Q_BEG] <= $q_max and $match->[S_BEG] <= $s_max )
        {
            $clip = &Common::Util::max( $match->[Q_END] - $q_max, $match->[S_END] - $s_max );
    
            if ( $clip > 0 )
            {
                $match->[Q_END] -= $clip;
                $match->[S_END] -= $clip;
                $match->[LENGTH] -= $clip;
            }

            push @matches, $match;
        }
    }
    
    if ( @matches ) {
        return wantarray ? @matches : \@matches;
    } else {
        return;
    }
}

sub create_chains_table
{
    my ( $matches,
         ) = @_;

    my ( @table, $row, $m, $i );
    
    
    $row->[C_ID] = 1;
    $row->[Q_BEG] = $matches->[0]->[Q_BEG];
    $row->[S_BEG] = $matches->[0]->[S_BEG];
    $row->[Q_END] = $matches->[0]->[Q_END];
    $row->[S_END] = $matches->[0]->[S_END];
    $row->[ELEMS] = 1;
    $row->[BASES] = $matches->[0]->[LENGTH];
    $row->[Q_GAPS] = 0;
    $row->[S_GAPS] = 0;
    $row->[Q_LEN] = $row->[BASES];
    $row->[S_LEN] = $row->[BASES];
    
    for ( $i = 1; $i <= $#{ $matches }; $i++ )
    {
        $m = $matches->[$i];

        if ( $m->[C_ID] == $row->[C_ID] )
        {
            $row->[Q_END] = $matches->[$i]->[Q_END];
            $row->[S_END] = $matches->[$i]->[S_END];
            $row->[ELEMS] += 1;
            $row->[BASES] += $m->[LENGTH];
            $row->[Q_GAPS] += $m->[Q_BEG] - $matches->[$i-1]->[Q_END] - 1;
            $row->[S_GAPS] += $m->[S_BEG] - $matches->[$i-1]->[S_END] - 1;
        }
        else
        {
            $row->[Q_LEN] = $row->[Q_END] - $row->[Q_BEG] + 1;
            $row->[S_LEN] = $row->[S_END] - $row->[S_BEG] + 1;

            push @table, &Storable::dclone( $row );
            undef $row;

            $row->[C_ID] = $m->[C_ID];
            $row->[Q_BEG] = $matches->[$i]->[Q_BEG];
            $row->[S_BEG] = $matches->[$i]->[S_BEG];
            $row->[Q_END] = $matches->[$i]->[Q_END];
            $row->[S_END] = $matches->[$i]->[S_END];
            $row->[ELEMS] = 1;
            $row->[BASES] = $m->[LENGTH];
            $row->[Q_GAPS] = 0;
            $row->[S_GAPS] = 0;
        }
    }

    $row->[Q_LEN] = $row->[Q_END] - $row->[Q_BEG] + 1;
    $row->[S_LEN] = $row->[S_END] - $row->[S_BEG] + 1;

    push @table, &Storable::dclone( $row );
    undef $row;

    return wantarray ? @table : \@table;
}

sub get_match
{
    # Niels Larsen, December 2004.

    # Gets a single match from q_begs, s_begs and lengths (all pdl's) 
    # as created by DNA::Map::read_mummer_matches. Returned is a six
    # element array with M_ID, Q_BEG, S_BEG, LENGTH, Q_END, S_END set.

    my ( $all,         # Three column "piddle" (PDL::Core::pdl)
         $id,          # Match id 
         ) = @_;

    # Returns an array.

    my ( $match );

    $match = &DNA::Map::get_matches( $all, [ $id ] )->[0];

    return $match;
}

sub get_matches
{
    # Niels Larsen, December 2004.

    # Assembles a list of matches q_begs, s_begs and lengths (all pdl's),
    # specified by the ids given by a PDL array of ids (indices). Each 
    # match is an array with M_ID, Q_BEG, S_BEG, LENGTH, Q_END, S_END set.

    my ( $all,          # Three column "piddle" (PDL::Core::pdl)
         $ids,          # PDL integer array of match ids
         ) = @_;

    # Returns an array.

    my ( @ids, $id, @matches, $match );

    if ( ref $ids eq "ARRAY" ) {
        @ids = @{ $ids };
    } else {
        @ids = &PDL::Core::list( $ids );
    }

    foreach $id ( @ids )
    {
        $match->[M_ID] = $id*1;

        $match->[Q_BEG] = &PDL::Core::at( $all, 0, $id, 0 );
        $match->[S_BEG] = &PDL::Core::at( $all, 1, $id, 0 );
        
        $match->[LENGTH] = &PDL::Core::at( $all, 2, $id, 0 );
        
        $match->[Q_END] = $match->[Q_BEG] + $match->[LENGTH] - 1;
        $match->[S_END] = $match->[S_BEG] + $match->[LENGTH] - 1;
        
        push @matches, &Storable::dclone( $match );
    }

    return wantarray ? @matches : \@matches;
}
    
sub matches_overlap
{
    my ( $m1,
         $m2,
         ) = @_;

    if ( not ( $m1->[Q_END] < $m2->[Q_BEG] or $m2->[Q_END] < $m1->[Q_BEG] ) and
         not ( $m1->[S_END] < $m2->[S_BEG] or $m2->[S_END] < $m1->[S_BEG] ) )
    {
        return 1;
    }

    return;
}

sub print_chains
{
    my ( $chains,
         $file,
         ) = @_;

    my ( $c );

    if ( $file )
    {
        if ( not open FILE, "> $file" ) {
            die qq (ERROR: Could not write-open file -> "$file");
        }

        print FILE "# C_ID\tQ_BEG\tQ_END\tS_BEG\tS_END\tELEMS\tBASES\tQ_GAPS\tS_GAPS\tQ_LEN\tS_LEN\n";

        foreach $c ( @{ $chains } )
        {
            print FILE $c->[C_ID]."\t".$c->[Q_BEG]."\t".$c->[Q_END]."\t".$c->[S_BEG]."\t".$c->[S_END]."\t".
                       $c->[ELEMS]."\t".$c->[BASES]."\t".
                       $c->[Q_GAPS]."\t".$c->[S_GAPS]."\t".$c->[Q_LEN]."\t".$c->[S_LEN]."\n";
        }
    
        close FILE;
    }
    else
    {
        print "# C_ID\tQ_BEG\tQ_END\tS_BEG\tS_END\tELEMS\tBASES\tQ_GAPS\tS_GAPS\tQ_LEN\tS_LEN\n";

        foreach $c ( @{ $chains } )
        {
            print $c->[C_ID]."\t".$c->[Q_BEG]."\t".$c->[Q_END]."\t".$c->[S_BEG]."\t".$c->[S_END]."\t".
                  $c->[ELEMS]."\t".$c->[BASES]."\t".
                  $c->[Q_GAPS]."\t".$c->[S_GAPS]."\t".$c->[Q_LEN]."\t".$c->[S_LEN]."\n";
        }
    }
    
    return;
}

sub print_errors
{
    my ( $errors,
         $file,
         ) = @_;

    my ( $c );

    if ( $file )
    {
        if ( not open FILE, "> $file" ) {
            die qq (ERROR: Could not write-open file -> "$file");
        }

        print FILE @{ $errors };

        close FILE;
    }
    else
    {
        print @{ $errors };        
    }        
    
    return;
}

sub print_matches
{
    my ( $matches,
         $file,
         ) = @_;

    my ( $m );

    if ( $file )
    {
        if ( not open FILE, "> $file" ) {
            die qq (ERROR: Could not write-open file -> "$file");
        }

        foreach $m ( @{ $matches } )
        {
            print FILE $m->[C_ID]."\t".($m->[M_ID]+1)."\t".$m->[Q_BEG]."\t".$m->[Q_END]."\t".
                       $m->[S_BEG]."\t".$m->[S_END]."\t".$m->[LENGTH]."\n";
        }
    
        close FILE;
    }
    else
    {
        foreach $m ( @{ $matches } )
        {
            print $m->[C_ID]."\t".($m->[M_ID]+1)."\t".$m->[Q_BEG]."\t".$m->[Q_END]."\t".
                  $m->[S_BEG]."\t".$m->[S_END]."\t".$m->[LENGTH]."\n";
        }
    }        
    
    return;
}
   
sub read_mummer_matches
{
    # Niels Larsen, November 2004.

    # Reads a mummer output file with lines of "q_beg>tab>s_beg<tab>length\n" 
    # into a "piddle" with three columns - q_beg, s_beg and length - and as 
    # many rows as there are match lines. If the second argument is given, only 
    # the reverse (bottom half) of the file is read. The first line of the upper
    # half (the forward section) is ignored, because it is the perfect match 
    # against self. 

    my ( $params,     # Command line arguments,
         ) = @_;

    # Returns an array.

    my ( $matches, $line, $io, $q_beg, $s_beg, $length, @rows, $rows, 
         $count, $maxcount, $irows, $lenmin );

    $lenmin = $params->{"lenmin"};

    $io = &Common::File::get_read_handle( $params->{'mummer'} );
    
    $matches = &PDL::Core::null();
    $maxcount = 20000;
    
    if ( $params->{"reverse"} )
    {
        $line = <$io>; 
        while ( defined ( $line = <$io> ) and $line !~ /^>/ ) { };

        while ( defined ( $line = <$io> ) )
        {
            chomp $line;
            
            ( $q_beg, $s_beg, $length ) = split " ", $line;

            if ( $length <= $lenmin ) {
                @rows = [ $q_beg * 1, $s_beg * 1, $length * 1 ];
            } else {
                @rows = ();
            }

            $count = 0;
            
            while ( $count <= $maxcount )
            {
                if ( defined ( $line = <$io> ) )
                {
                    chomp $line;

                    ( $q_beg, $s_beg, $length ) = split " ", $line;

                    if ( $length >= $lenmin )
                    {
                        push @rows, [ $q_beg * 1, $s_beg * 1, $length * 1 ];
                        $count += 1;
                    }
                }
                else {
                    $count = $maxcount + 1;
                }
            }
            
            $rows = &PDL::Core::pdl( \@rows );

            ( undef, $irows ) = &PDL::Core::dims( $matches );

            if ( $irows ) {
                $matches = $matches->glue( 1, $rows->dummy(2) );
            } else {
                $matches = $rows;
            }
        }
    }
    else
    {
        $line = <$io>;
        $line = <$io>;

        while ( $line !~ /^>/ and defined ( $line = <$io> ) )
        {
            chomp $line;

            ( $q_beg, $s_beg, $length ) = split " ", $line;

            if ( $length >= $lenmin and $q_beg != $s_beg ) {
                @rows = [ $q_beg * 1, $s_beg * 1, $length * 1 ];
            } else {
                @rows = ();
            }

            $count = 0;

            while ( $count <= $maxcount )
            {
                if ( defined ( $line = <$io> ) and $line !~ /^>/ )
                {
                    chomp $line;

                    ( $q_beg, $s_beg, $length ) = split " ", $line;

                    if ( $length >= $lenmin and $q_beg != $s_beg )
                    {
                        push @rows, [ $q_beg * 1, $s_beg * 1, $length * 1 ];
                        $count += 1;
                    }
                }
                else {
                    $count = $maxcount + 1;
                }
            }
            
            $rows = &PDL::Core::pdl( \@rows );

            ( undef, $irows ) = &PDL::Core::dims( $matches );

            if ( $irows ) {
                $matches = $matches->glue( 1, $rows->dummy(2) );
            } else {
                $matches = $rows;
            }
        }
    }

    &Common::File::close_handle( $io );

    return $matches;
}

1;

__DATA__
__C__

/*

Inline::C guides,

http://search.cpan.org/~ingy/Inline-0.44/C/C.pod
http://search.cpan.org/~ingy/Inline-0.44/C/C-Cookbook.pod

*/

static void* get_ptr( SV* obj ) { return SvPVX( SvRV( obj ) ); }

#define DEF_NDXPTR( str )  double* ndxptr = get_ptr( str )
#define FETCH( idx )       ndxptr[ idx ]

/* 

min_index_C, Niels Larsen, November 2004.

Looks up an integer value in a sorted list of integers and returns 
its index. If the value is lower than the lowest, 0 is returned. If
the value lies in between two integers in the list, the index of the
higher one is returned. If its higher than the highest, the highest
index + 1 is returned. 

*/

int min_index_C( SV* ndxstr, int value, int imin, int imax )
{
    DEF_NDXPTR( ndxstr );

    int cur, low, high;

    low = imin;
    high = imax;

    while ( low < high )
    {
        cur = ( low + high ) / 2;

        if ( FETCH(cur) < value ) {
            low = cur + 1;
        } else {
            high = cur;
        }
    }

    if ( FETCH(low) < value ) {
        low += 1;
    }

    return low;
}

/* 

max_index_C, Niels Larsen, November 2004.

Looks up an integer value in a sorted list of integers and returns 
its index. If the value is lower than the lowest, -1 is returned. If
the value lies in between two integers in the list, the index of the
lower one is returned. If its higher than the highest, the highest
index is returned. 

*/

int max_index_C( SV* ndxstr, int value, int imin, int imax )
{
    DEF_NDXPTR( ndxstr );

    int cur, low, high;

    low = imin;
    high = imax;

    while ( low < high )
    {
        cur = ( low + high ) / 2;

        if ( FETCH(cur) <= value ) {
            low = cur + 1;
        } else {
            high = cur;
        }
    }

    if ( low > imax || FETCH(low) > value ) {
        low -= 1;
    } 

    return low;
}


__END__

# our ( $t0, $t1, $t2, $t3, $time, $all_time,
#       $align_two_dnas_time, $select_matches_bin_time,
#       $extension_quality_time, $clip_match_time, $extend_time,
#       $clip_time, 
#       $slice_time, $get_match_time, $in_time, $lookup_time );


# /* 

# get_mummer_match_C, Niels Larsen, November 2004.

# Gets a single match from a string created by read_mummer_matches_str.
# It is done this way rather than a plain array to save memory. The 
# second argument is the index you would have given the array. 

# */

# void get_mummer_match_C( SV* ndxstr, int index )
# {
#     DEF_NDXPTR( ndxstr );

#     int q_beg, s_beg, length;

#     q_beg = FETCH( index );
#     s_beg = FETCH( index+1 );
#     length = FETCH( index+2 );

#     Inline_Stack_Vars;
#     Inline_Stack_Reset;

#     Inline_Stack_Push(sv_2mortal(newSViv( q_beg )));
#     Inline_Stack_Push(sv_2mortal(newSViv( s_beg )));
#     Inline_Stack_Push(sv_2mortal(newSViv( q_beg+length-1 )));
#     Inline_Stack_Push(sv_2mortal(newSViv( s_beg+length-1 )));
#     Inline_Stack_Push(sv_2mortal(newSViv( length )));

#     Inline_Stack_Done;
# }
