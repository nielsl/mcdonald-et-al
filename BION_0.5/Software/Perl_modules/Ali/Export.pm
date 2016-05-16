package Ali::Export;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Functions that cast native alignments into other formats.

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &write_fasta_from_pdl
                 &write_fasta_from_pdls
                 );

use Common::Config;
use Common::Messages;

use Ali::IO;
use Seq::Storage;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub write_fasta_from_pdl
{
    # Niels Larsen, June 2005.

    # Writes a given "raw" alignment to fasta format, optionally removing
    # gaps. The input alignment may be in physical memory or attached to 
    # a file (which is done with the "Ali::IO::connect_pdl" routine).
    # Returns the number of entries written. 

    my ( $class,
         $args,
         $msgs, 
         ) = @_;

    # Returns an integer. 
    
    my ( $cols, $rows, $ofh, $must_close, $with_gaps, $with_ali_ids,
         $with_index_sids, $prefix, $masks, $mask, $ofile, $ali,
         $maskrows, $begrow, $endrow, $string, $row, $sid, $seq, $count,
         $row_incr, $maxrow, $maxcol, $i, $subali, $info, @info, $field,
         );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( afile ofile append with_ali_ids with_index_sids with_gaps with_masks clobber ) ],
    });

    $ali = &Ali::IO::connect_pdl( $args->afile );

    ( $cols, $rows ) = $ali->seqs->dims;

    $ofile = $args->ofile;

    if ( $args->clobber ) {
        &Common::File::delete_file_if_exists( $ofile );
    }

    if ( $args->append ) {
        $ofh = &Common::File::get_append_handle( $ofile );
    } else {
        $ofh = &Common::File::get_write_handle( $ofile );
    }

    $with_gaps = $args->with_gaps;
    $with_ali_ids = $args->with_ali_ids;
    $with_index_sids = $args->with_index_sids;

    # Masks if any - make hash for lookup in the loop,

    if ( $args->with_masks and defined ( $masks = $ali->pairmasks ) )
    {
        foreach $mask ( @{ $masks } )
        {
            ( $begrow, $endrow, $string ) = @{ $mask };
            $maskrows->{ $begrow } = $string;
        }
    }

    # Info if header string,

    if ( $string = $ali->title ) {
        push @info, "mol_name=$string";
    }

    if ( @info ) {
        $info = " ". (join "; ", @info);
    } else {
        $info = "";
    }

    $row_incr = int 100_000_000 / $cols;

    $row = 0;
    $maxrow = $ali->max_row;
    $maxcol = $ali->max_col;

    $prefix = $ali->file;
    
    undef $ali;

    while ( $row <= $maxrow )
    {
        $ali = &Ali::IO::connect_pdl( $prefix );

        $subali = $ali->subali_get( [ 0 .. $maxcol ], 
                                    [ $row .. &Common::Util::min( $maxrow, $row + $row_incr - 1 ) ],
                                    1, 0 );

        undef $ali;

        for ( $i = 0; $i <= $subali->max_row; $i++ )
        {
            # Insert masks,

            if ( $maskrows->{ $row } )
            {
                $ofh->print( ">Pairingmask\n$maskrows->{$row}\n" );
            }

            # Short-id,
            
            if ( $with_index_sids ) {
                $sid = $row;
            } else {
                $sid = $subali->sid_string( $i );
                $sid =~ s/\s//g;
            }
            
            if ( $with_ali_ids and defined $subali->sid ) {
                $sid = $subali->sid . ":$sid";
            }
            
            # Sequence, with or without gaps,
            
            $seq = $subali->seq_string( $i );
            $seq =~ s/\0+$//g;
            
            if ( not $with_gaps ) {
                $seq =~ s/[^A-Za-z]//g;
            }

            # Print,
            
            $count = $seq =~ tr/A-Za-z/A-Za-z/;
            
            if ( $count > 0 ) 
            {
                $ofh->print( ">$sid$info\n$seq\n" );
            } 

            $row += 1;
        }

        undef $subali;
    }

    &Common::File::close_handle( $ofh );

    return $rows;
}

sub write_fasta_from_pdls
{
    # Niels Larsen, June 2009.

    # Creates a single fasta sequence file from the given alignment files.
    # The ids are "ali_id:seq_id" so their origin can be recognized.

    my ( $class,           
         $args,
         $msgs,            # Messages returned - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( @ifiles, @ofiles, $clobber, $ifile, $ofile, $prefix, $i, $o, 
         %params );

    $args = &Registry::Args::check( $args, {
        "AR:2" => [ qw ( ofiles ifiles ) ],        
        "S:1" => [ qw ( clobber ) ],
        "S:0" => [ qw ( with_ali_ids with_index_sids with_gaps with_masks ) ],
    });

    $args->with_ali_ids( 0 ) if not defined $args->with_ali_ids;
    $args->with_index_sids( 0 ) if not defined $args->with_index_sids;
    $args->with_gaps( 0 ) if not defined $args->with_gaps;
    $args->with_masks( 0 ) if not defined $args->with_masks;

    @ifiles = @{ $args->ifiles };
    @ofiles = @{ $args->ofiles };

    $clobber = $args->clobber;

    # Crash if output files exist and clobber not set,
    
    if ( not $args->clobber )
    {
        foreach $ofile ( @ofiles )
        {
            if ( -e $ofile ) {
                &error( qq (File exists -> "$ofile") );
            }
        }
    }
    
    %params = (
        "clobber" => $clobber,
        "with_gaps" => $args->with_gaps,
        "with_index_sids" => $args->with_index_sids,
        "with_ali_ids" => $args->with_ali_ids,
        "with_masks" => $args->with_masks,
        );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ONE TO ONE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( scalar @ifiles == scalar @ofiles )
    {
        for ( $i = 0; $i <= $#ifiles; $i++ )
        {
            if ( $clobber ) {
                &Common::File::delete_file_if_exists( $ofiles[$i] );
            }
                
            Ali::Export->write_fasta_from_pdl(
                {
                    "afile" => &Common::Names::strip_suffix( $ifiles[$i] ),
                    "ofile" => $ofiles[$i],
                    %params,
                    "append" => 0,
                }, $msgs );

            &Seq::Storage::create_indices(
                {
                    "ifiles" => [ $ofiles[$i] ],
                    "progtype" => "fetch",
                    "clobber" => $clobber,
                    "silent" => 1,
                });
        }
    }
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MANY TO ONE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( scalar @ofiles == 1 )
    {
        $ofile = $ofiles[0];

        if ( $clobber ) {
            &Common::File::delete_file_if_exists( $ofile );
        }
                
        for ( $i = 0; $i <= $#ifiles; $i++ )
        {
            Ali::Export->write_fasta_from_pdl(
                {
                    "afile" => &Common::Names::strip_suffix( $ifiles[$i] ),
                    "ofile" => $ofile,
                    %params,
                    "append" => 1,
		    "clobber" => 0,
                }, $msgs );
        }

        &Seq::Storage::create_indices(
            {
                "ifiles" => [ $ofile ],
                "progtype" => "fetch",
                "clobber" => $clobber,
                "silent" => 1,
            });
    }
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OTHERWISE ERROR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    else
    {
        $i = scalar @ifiles;
        $o = scalar @ofiles;

        &error( qq (Wrong combination: $i input and $o output files) );
    }

    return scalar @ifiles;
}

1;

__END__

# sub write_fasta
# {
#     # Niels Larsen, June 2005.

#     # Writes a given un-pdlified alignment to fasta format. The input 
#     # alignment must be in physical memory. Gaps are optionally removed
#     # before writing. For file bound alignments see the write_fasta_pdl
#     # routine. Returns the number of entries written. 

#     my ( $self,         # Alignment
#          $ofh,          # Output file or file handle
#          $ndxids,       # Writes indices rather - OPTIONAL
#          $aliids,
#          ) = @_;

#     # Returns an integer. 
    
#     my ( $sids, $seqs, $sid, $seq, $row, $masks, $mask, $maskrows,
#          $begrow, $endrow, $string, $must_close, $aliid, $count );

#     $ndxids = 0 if not defined $ndxids;
#     $aliids = 0 if not defined $aliids;

#     if ( not &Common::File::is_handle( $ofh ) )
#     {
#         $ofh = &Common::File::get_write_handle( $ofh );
#         $must_close = 1;
#     }

# #    $sids = $self->sids;
# #    $seqs = $self->seqs;

#     $aliid = $self->id;

#     if ( defined ( $masks = $self->pairmasks ) )
#     {
#         foreach $mask ( @{ $masks } )
#         {
#             ( $begrow, $endrow, $string ) = @{ $mask };
#             $maskrows->{ $begrow } = $string;
#         }
#     }

#     for ( $row = 0; $row <= $#{ $seqs }; $row++ )
#     {
#         if ( $maskrows->{ $row } )
#         {
#             $ofh->print( ">Pairingmask\n$maskrows->{$row}\n" );
#         }

#         if ( $ndxids ) {
#             $sid = $row;
#         } else {
#             $sid = $sids->[$row];
#             $sid =~ s/\s//g;
#         }

#         if ( $aliids ) {
#             $sid = "$aliid:$sid";
#         }

#         $seq = $seqs->[$row];
#         $seq =~ s/\0+$//g;

#         $count = $seq =~ tr/A-Za-z/A-Za-z/;

#         if ( $count > 0 ) 
#         {
#             $ofh->print( ">$sid\n$seq\n" );
#         }
#     }

#     if ( $must_close ) {
#         &Common::File::close_handle( $ofh );
#     }

#     return;
# }
