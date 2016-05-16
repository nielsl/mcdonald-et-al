package Ali::Chimera;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that have to do with chimeric alignment.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use feature "state";
use Fcntl qw ( SEEK_SET SEEK_CUR SEEK_END );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Names;
use Common::Types;
use Common::DBM;

use Registry::Args;

use Ali::Common;
use Ali::Storage;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub chimeras_uclust
{
    # Niels Larsen, May 2011. 

    # Examines each alignment in the given uclust alignment output
    # for being "chimeric": if many reads map mostly on the left half 
    # of the seed, and many others to the right, then we call the 
    # alignment chimeric. The routine returns a list of seed sequence
    # ids that form the chimeras.

    my ( $file,
         $args,
        ) = @_;
    
    # Returns a list. 

    my ( $defs, $fhs, $ali_str, $ali_id, $ali, @output, $offsets, $silent,
         $byt_pos, $str_len, $ali_handle, $ndx_handle, $get_bulk, $conf,
         $beg_id, $end_id, $out_file, $out_fh, $count, $name, $indent, 
         $tuple, $line );
    
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "outfile" => undef,
        "seqmin" => 3,
        "offpct" => 60,       # How much sequences are off to either side
        "rowpct" => 60,       # How many rows sequences are off in 
        "balpct" => 10,       # Minimum right/left off proportion
        "usize" => 1,         # Include cluster numbers in calculation
        "clobber" => 0,
        "silent" => 0,
        "indent" => 3,
    };

    $args = &Registry::Args::create( $args, $defs );

    $get_bulk = 1000;
    $indent = $args->indent;

    $Common::Messages::silent = $args->silent;

    $conf = {
        "min_offpct" => $args->offpct,
        "min_rowpct" => $args->rowpct,
        "min_balpct" => $args->balpct,
        "with_nums" => $args->usize,
        "skip_row" => -1,
    };

    if ( not &Ali::Storage::is_indexed( $file ) ) {
        &error( qq (Alignment file not indexed -> "$file") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> FETCH ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( "Chimera checking ... ", $indent );

    $fhs = &Ali::Storage::get_handles( $file );

    $ali_handle = $fhs->ali_handle;
    $ndx_handle = $fhs->ndx_handle;

    $beg_id = 0;
    $end_id = $beg_id + $get_bulk - 1;

    @output = ();

    while ( $offsets = &Common::DBM::get_bulk( $ndx_handle, [ $beg_id ... $end_id ] ) 
            and %{ $offsets } )
    {
        for ( $ali_id = $beg_id; $ali_id <= $end_id; $ali_id += 1 )
        {
            if ( exists $offsets->{ $ali_id } )
            {
                ( $byt_pos, $str_len ) = split "\t", $offsets->{ $ali_id };
            
                seek( $ali_handle, $byt_pos, SEEK_SET );
                read( $ali_handle, $ali_str, $str_len );

                # &dump( $ali_str );
                
                $ali = &Ali::Common::parse_uclust( \$ali_str );
                $ali->sid( $ali_id );

                if ( @{ $ali->sids } > 1 and $tuple = &Ali::Common::is_chimeric( $ali, $conf ) )
                {
                    push @output, $tuple;
                }
            }
        }
        
        $beg_id = $end_id + 1;
        $end_id += $get_bulk;
    }

    &Ali::Storage::close_handles( $fhs );

    $count = scalar @output;
    &echo_done( "$count found\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined wantarray ) {
        return wantarray ? @output : \@output;
    }
    
    if ( defined ( $out_file = $args->outfile ) )
    {
        &Common::File::delete_file_if_exists( $out_file ) if $out_file and $args->clobber;

        $out_fh = &Common::File::get_append_handle( $out_file );

        foreach $tuple ( @output )
        {
            $line = $tuple->ali_id 
                ."\t". ( join ",", @{ $tuple->off_ids } )
                ."\t". ( join ",", @{ $tuple->cent_ids } )
                ."\n";

            $out_fh->print( $line );
        }

        &Common::File::close_handle( $out_fh );
    }

    return;
}

1;

__END__
