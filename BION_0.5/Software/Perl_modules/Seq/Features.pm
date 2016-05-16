package Seq::Features;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions and methods that compare features or operate on lists of 
# them.  IN FLUX
# 
# filter
# filter_single
# locs_compress
# sort
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Common::Config;
use Common::Messages;
use Common::Util;

use base qw ( Seq::Feature );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub filter
{
    # Niels Larsen, June 2006.

    # Filters a list of features: removes those that overlap with higher 
    # scoring ones. The "info" field is set to the number of overlaps 
    # removed for a given feature. 

    my ( $class,
         $fts,
         $method,
         ) = @_;

    # Returns a list.

    my ( @fts, %fts, $ft, $id );

    foreach $ft ( @{ $fts } )
    {
        push @{ $fts{ $ft->id } }, $ft;
    }

    foreach $id ( keys %fts )
    {
        push @fts, Seq::Features->filter_single( $fts{ $id }, $method );
    }

    return wantarray ? @fts : \@fts;
}

sub filter_single
{
    # Niels Larsen, August 2006.

    # Removes low-scoring features from a given list that should be
    # ignored according to the method given. 

    my ( $class,
         $fts,         # Feature list
         $method,
         ) = @_;

    # Returns a list. 

    my ( @fts, @new_fts, $ft, $new_ft, $i, $info, $match );
    
    @fts = sort { $b->score <=> $a->score } @{ $fts };
    @new_fts = $fts[0];

    for ( $i = 1; $i <= $#fts; $i++ )
    {
        $ft = $fts[$i];

        foreach $new_ft ( @new_fts )
        {
            if ( $new_ft->$method( $ft ) )
            {
                $info = $new_ft->info;
                push @{ $info->{ $method } }, $ft->molecule;
                $new_ft->info( $info );
                
                $match = 1;
            }
        }

        if ( not $match ) {
            push @new_fts, $ft;
        }
    }

    foreach $new_ft ( @new_fts )
    {
        if ( $info = $new_ft->info and exists $info->{ $method } )
        {
            $info->{ $method } = &Common::Util::uniqify( $info->{ $info } );
            $new_ft->info( $info );
        }
    }

    return wantarray ? @new_fts : \@new_fts;
}

sub sort
{
    # Niels Larsen, January 2007.
    
    # Sorts a list of features by the given list of keys: the
    # first key is primary key, next is secondary and so on.
    
    my ( $fts,         # Feature objects
         $keys,        # List of keys
         ) = @_;

    # Returns a list.

    my ( @fts, @expr, $expr, $key );

    foreach $key ( @{ $keys } )
    {
        if ( $key =~ /^db|id/ ) {
            push @expr, '$a->'.$key.' eq $b->'.$key;
        } else {
            push @expr, '$a->'.$key.' <=> $b->'.$key;
        }
    }

    $expr = join " || ", @expr;

    @fts = sort { eval $expr } @{ $fts };

    if ( wantarray ) {
        return @fts;
    } else {
        return \@fts;
    }
}

sub strand
{
    my ( $self,
         $value,
         ) = @_;

    if ( defined $value )
    {
        if ( $value ) {
            $self->{"strand"} = 1;
        } else {
            $self->{"strand"} = 0;
        }

        return $self;
    }
    else {
        return $self->{"strand"};
    }
}

1;

__END__

sub location
{
    my ( $self,
         $value,
         ) = @_;

    my ( $id, $beg, $end );

    if ( defined $value )
    {
        ( $id, $beg, $end ) = @{ $value };
        $self->{"location"} = "$id:$beg-$end";
    }
    elsif ( $value =~ /^(.+):(\d+)-(\d+)$/ )
    {
        return ( $1, $2, $3 );
    }
    else {
        &error( qq (Wrong looking location string -> "$value") );
        exit;
    }
    
    return $self;
}
