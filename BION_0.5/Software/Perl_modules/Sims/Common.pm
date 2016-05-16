package Sims::Common;                # -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use Data::Dumper;
use List::Util;

use Registry::Get;

use Common::Config;
use Common::Messages;
use Seq::Common;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Primitives that create sequence similarity features and give access 
# to them. These are autoloaded functions:
#

our @Auto_get_setters = qw
    (
     id1 id2 gi2 locs1 locs2 frame1 frame2 score taxid title label orgname
     );

our %Auto_get_setters = map { $_, 1 } @Auto_get_setters;

#
# and these are explicitly defined,
#
# align_sims
# beg1
# beg2
# condense
# condense_forward
# create_locs1
# delete
# end1
# end2
# locs
# locs1
# locs2
# new
# select_sims_forward
# set_fields
# sort
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub AUTOLOAD
{
    # Niels Larsen, January 2007.
    
    # Defines a number of simple getter and setter methods, as defined in
    # the %Get_setters hash above. Returns nothing but defines methods 
    # into the name space of this package.

    my ( $method );

    our $AUTOLOAD;

    if ( $AUTOLOAD =~ /::(\w+)$/ and $Auto_get_setters{ $1 } )
    {
        $method = $1;
        
        {
            no strict 'refs';

            *{ $AUTOLOAD } = sub {

                if ( defined $_[1] ) {
                    $_[0]->{ $method } = $_[1];
                } else {
                    $_[0]->{ $method };
                }
            }
        }

        goto &{ $AUTOLOAD };
    }
    elsif ( $AUTOLOAD !~ /DESTROY$/ )
    {
        &error( qq (Undefined method called -> "$AUTOLOAD") );
    }

    return;
}

sub align_sims
{
    # Niels Larsen, May 2007.

    # Given a list of similarities in forward orientation, converts the 
    # similarities to a single one. This is done by an alignment procedure
    # finds the best combination of the longest regions and makes sure no 
    # matches overlap or conflict. The output is a single similarity 
    # object with recalculated score and location coordinates. 

    my ( $sims,              # List of similarities
         $dbtype,            # Database type
        ) = @_;

    # Returns a list.
    
    my ( $sim, $locs1, $locs2, $beg1, $end1, $beg2, $end2, $i, $length,
         $coords, $module, $routine, @ids, $idstr, %ids1, %ids2 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PRE-PROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<<

    # This is merely preparing the coordinates in the form the alignment 
    # routine requires,

    foreach $sim ( @{ $sims } )
    {
        $ids1{ $sim->id1 } = 1;
        $ids2{ $sim->id2 } = 1;

        $locs1 = $sim->locs1;
        $locs2 = $sim->locs2;
        
        for ( $i = 0; $i <= $#{ $locs1 }; $i++ )
        {
            ( $beg1, $end1 ) = @{ $locs1->[$i] };
            ( $beg2, $end2 ) = @{ $locs2->[$i] };
            
            $length = &List::Util::min( $end1 - $beg1, $end2 - $beg2 ) + 1;

            push @{ $coords }, [ $beg1, $end1, $beg2, $end2, $length, undef, $sim->label ];
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Depending on datatype different parameters are used; here we just 
    # call the right variant depending on datatype,

    $module = Registry::Get->type( $dbtype )->module ."::Ali";
    $routine = $module ."::align_two_seqs";

    {
        no strict "refs";
        $coords = $routine->( undef, undef, $coords );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> POST-PROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Collect the result coordinates and create a single combo similarity
    # object from them,

    if ( @{ $coords } )
    {
        $sim = Sims::Common->new();

        @ids = keys %ids1;

        if ( scalar @ids == 1 ) {
            $sim->id1( $ids[0] );
        } else {
            $idstr = join ", ", @ids;
            &error( qq (Should be a single id1, instead we have -> "$idstr") );
        }
        
        @ids = keys %ids2;
        
        if ( scalar @ids == 1 ) {
            $sim->id2( $ids[0] );
        } else {
            $idstr = join ", ", @ids;
            &error( qq (Should be a single id2, instead we have -> "$idstr") );
        }
        
        $sim->locs1( [ map { [ $_->[0], $_->[1] ] } @{ $coords } ] );
        $sim->locs2( [ map { [ $_->[2], $_->[3] ] } @{ $coords } ] );

        $sim->label( join ",", map { $_->[6] } @{ $coords } );
        
        $sim->score( &List::Util::sum( [ map { $_->[4] } @{ $coords } ] ) );
        
        return $sim;
    }
    else {
        return;
    }
}

sub beg1
{
    my ( $sim,
         ) = @_;

    return $sim->locs1->[0]->[0];
}

sub beg2
{
    my ( $sim,
         ) = @_;

    return $sim->locs2->[0]->[0];
}

sub condense
{
    # Niels Larsen, January 2007.

    # Returns a condensed list of similarities. Input is a perhaps chaotic 
    # list of similarities, perhaps between different query and subject 
    # sequences, in mixed orientations, in no particular order and with 
    # several overlapping and/or conflicting matches between a given query 
    # and subject sequence. This procedure creates order in such a list, 
    # by merging those that can be combined without greatly stretching the 
    # alignment, while leaving the rest separate. No match is discarded, 
    # except if it is embedded in a larger one. Matches are trimmed if 
    # needed to produce an obvious overlap. A score is added to each 
    # output similarity.

    my ( $sims,         # Input list
         $args,         # Arguments hash
         ) = @_;

    # Returns a list.

    my ( %f_tmp, %r_tmp, $id1, $id2, @sims_all, @sims, $sim, $i, $reflen );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( dbtype reflen ) ],
    });

    $reflen = $args->reflen;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SEPARATE MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Make hash with forward and reverse matches,

    %f_tmp = ();
    %r_tmp = ();

    foreach $sim ( @{ $sims } )
    {
        if ( $sim->frame1 > 0 )
        {
            if ( $sim->frame2 > 0 ) {
                push @{ $f_tmp{ $sim->id1 }{ $sim->id2 } }, $sim;
            } else {
                push @{ $r_tmp{ $sim->id1 }{ $sim->id2 } }, $sim;
            }
        }
        else {
            &error( "frame 1 <= 0: ".$sim->frame1 );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORWARD MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Run all forward matches between a given query and subject sequence through a 
    # pairwise alignment procecure that aligns coordinate sets and outputs their
    # best combination(s),

    foreach $id1 ( keys %f_tmp )
    {
        foreach $id2 ( keys %{ $f_tmp{ $id1 } } )
        {
            @sims = &Sims::Common::condense_forward( $f_tmp{ $id1 }{ $id2 }, $args );
            
            foreach $sim ( @sims )
            {
                $sim->frame1( 1 );
                $sim->frame2( 1 );

                push @sims_all, &Storable::dclone( $sim );
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> REVERSE MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Run all reverse matches between a given query and subject sequence through
    # a pairwise alignment procecure that aligns coordinate sets and outputs their
    # best combination(s),

    foreach $id1 ( keys %r_tmp )
    {
        foreach $id2 ( keys %{ $r_tmp{ $id1 } } )
        {
            $sims = $r_tmp{ $id1 }{ $id2 };

            foreach $sim ( @{ $sims } )
            {
                $sim->locs1( &Seq::Common::subtract_locs( $sim->locs1, $args->reflen ) );
            }

            @sims = &Sims::Common::condense_forward( $sims, $args );

            foreach $sim ( @sims )
            {
                $sim->frame1( 1 );
                $sim->frame2( -1 );

                $sim->locs1( &Seq::Common::subtract_locs( $sim->locs1, $args->reflen ) );
                
                push @sims_all, &Storable::dclone( $sim );
            }
        }
    }
    
    return wantarray ? @sims_all : \@sims_all;
}

sub condense_forward
{
    # Niels Larsen, July 2007.

    # Brings order to a list of similarities that all must be in forward
    # direction (all beginnings are <= ends). The input list may include
    # different query and subject sequences, be in no particular order and
    # have overlapping and/or conflicting matches. This procedure combines
    # the matches into fewer ones without large gaps or insertions; somewhat 
    # similar to forming contigs out of single reads. All matches are used 
    # once, none are discarded, except if embedded in a larger one. Matches 
    # are trimmed if needed to produce an obvious overlap. A score is added 
    # to each composite output similarity.

    my ( $sims,          # List of similarities
         $args,          # Argument object
        ) = @_;

    # Returns a list.

    my ( @sims, $dbtype, $sim, $sim_best, $minbeg2, $maxend2, 
         @sims_todo, @sims_wait, @sims_out, $gi2, $i, $sim_group, %labels );

    @sims = @{ $sims };

    $dbtype = $args->dbtype;

    $gi2 = $sims[0]->gi2;

    # Strategy: 

    @sims = sort { $b->score <=> $a->score } @sims;
    @sims = map { $_->label( ++$i ); $_ } @sims;

    while ( $sim_best = shift @sims )
    {
        if ( @sims )
        {
            @sims_todo = &Sims::Common::select_sims_forward( $sim_best, \@sims );
            push @sims_todo, $sim_best;

            $sim_group = &Sims::Common::align_sims( \@sims_todo, $dbtype );

            %labels = map { $_, 1 } split ",", $sim_group->label;
            @sims = grep { not $labels{ $_->label } } @sims;

            @sims = sort { $b->score <=> $a->score } @sims;

            push @sims_out, $sim_group;
        }
        else {
            push @sims_out, $sim_best;
        }
    }

    @sims_out = map { $_->gi2( $gi2 ); $_ } @sims_out;
    @sims_out = map { $_->delete("label"); $_ } @sims_out;

    return wantarray ? @sims_out : \@sims_out;
}

sub delete
{
    my ( $self,
         $key,
        ) = @_;

    delete $self->{ $key };

    return $self;
}

sub end1
{
    my ( $sim,
         ) = @_;

    return $sim->locs1->[-1]->[1];
}

sub end2
{
    my ( $sim,
         ) = @_;

    return $sim->locs2->[-1]->[1];
}

sub locs
{
    # Niels Larsen, January 2007.

    my ( $self,
         $key,
         $range,
         ) = @_;

    if ( defined $range )
    {
        {
            local $Data::Dumper::Terse = 1;     # avoids variable names
            local $Data::Dumper::Indent = 0;    # no indentation

            $self->{ $key } = Dumper( $range );
        }

        return $self;
    }
    else
    {
        return eval $self->{ $key };
    }
}

sub locs1
{
    my ( $self,
         $value,
         ) = @_;

    return $self->locs( "locs1", $value );
}

sub locs2
{
    my ( $self,
         $value,
         ) = @_;

    return $self->locs( "locs2", $value );
}

sub new
{
    # Niels Larsen, January 2007.

    # Creates new objects. 

    my ( $class,
         %args,
         ) = @_;
    
    # Returns object.

    my ( $self, $key );

    if ( %args )
    {
        foreach $key ( keys %args )
        {
            if ( $Auto_get_setters{ $key } )
            {
                $self->{ $key } = $args{ $key };
            }
            else {
                &error( qq (Unrecognized key -> "$key") );
            }
        }
    }
    else {
        $self = {};
    }

    $class = (ref $class) || $class;

    bless $self, $class;
    
    return $self;
}

sub select_sims_forward
{
    # Niels Larsen, September 2007.

    # Given a reference similarity and a list of candidate simiarities, finds 
    # those that are overlapping with or approximately end-to-end with the 
    # reference. 

    my ( $refsim, 
         $sims,
        ) = @_;

    my ( $refbeg1, $refbeg2, $refend1, $refend2, $sim, $beg1, $end1, $beg2, $end2, 
         @sims, $len1, $len2, $lendiff, $maxlen );

    ( $refbeg1, $refend1 ) = ( $refsim->locs1->[0]->[0], $refsim->locs1->[-1]->[1] );
    ( $refbeg2, $refend2 ) = ( $refsim->locs2->[0]->[0], $refsim->locs2->[-1]->[1] );

    foreach $sim ( @{ $sims } )
    {
        ( $beg1, $end1 ) = ( $sim->locs1->[0]->[0], $sim->locs1->[-1]->[1] );
        ( $beg2, $end2 ) = ( $sim->locs2->[0]->[0], $sim->locs2->[-1]->[1] );

        $len1 = $beg1 - $refbeg1;
        $len2 = $beg2 - $refbeg2;

        if ( $len1 >= 0 and $len2 >= 0 )
        {
            $lendiff = abs ( $len1 - $len2 );
            $maxlen = &List::Util::max( $len1, $len2 );
            
            if ( $lendiff <= &List::Util::max( 20, $maxlen / 10 ) ) {
                push @sims, $sim;
            }
        }
        elsif ( $len1 <= 0 and $len2 <= 0 )
        {
            $lendiff = abs ( $len1 - $len2 );
            $maxlen = - &List::Util::min( $len1, $len2 );
            
            if ( $lendiff <= &List::Util::max( 20, $maxlen / 10 ) ) {
                push @sims, $sim;
            }
        }
    }

    return wantarray ? @sims : \@sims;
}

sub set_fields
{
    my ( $sims,
         $key,
         $value,
        ) = @_;

    my ( $sim );

    foreach $sim ( @{ $sims } )
    {
        $sim->$key( $value );
    }

    return wantarray ? @{ $sims } : $sims;
}

sub sort
{
    # Niels Larsen, January 2007.
    
    # Sorts a list of similarities by the given list of keys: the
    # first key is primary key, next is secondary and so on.
    
    my ( $sims,        # Similarity objects
         $keys,        # List of keys
         ) = @_;

    # Returns a list.

    my ( @sims, @expr, $expr, $key );

    foreach $key ( @{ $keys } )
    {
        if ( $key =~ /^db|id/ ) {
            push @expr, '$a->'.$key.' eq $b->'.$key;
        } else {
            push @expr, '$a->'.$key.' <=> $b->'.$key;
        }
    }

    $expr = join " || ", @expr;

    @sims = sort { eval $expr } @{ $sims };

    if ( wantarray ) {
        return @sims;
    } else {
        return \@sims;
    }
}

1;

__END__
