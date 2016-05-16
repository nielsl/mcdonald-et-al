package Pat::Report;                # -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Tables;

use Registry::Register;
use Seq::Patterns;
use Seq::IO;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_report
);

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_report
{
    my ( $files,
         $args,
        ) = @_;

    my ( @in_files, $in_file, @errors, @seq_dbs, $reg_list, %seq_reg, $seq_db,
         $i, $j, @lines, @locs, $seq, @seq_info, %seen, @hit_seqs, $loc, $hit,
         $hitstr, $count, $diff, @ids, $ofh, @report, $hit_beg, $hit_end, $hit_seq,
         %hit_dict, $annot, $org_name, $tax_names, $function, $seq_id, $line,
         $sys_type, $lin_ends, $lin_end );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> INPUT VALIDATION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Input files,
    
    @in_files = grep { $_ =~ /\w$/ } @{ $files };

    push @errors, &Common::File::access_error( \@in_files, "efr" );

    # Sequence datasets - optional,

    if ( $args->seqdbs )
    {
        @seq_dbs = split /\s*,\s*/, $args->seqdbs;

        if ( scalar @seq_dbs == 1 and scalar @in_files > 1 ) {
            @seq_dbs = ($seq_dbs[0]) x scalar @in_files;
        }
    }
    elsif ( grep /_vs_/, @in_files )
    {
        @seq_dbs = map { $_ =~ /_vs_(.+)$/; $1 } @in_files;
    }
    else {
        push @errors, ["Error", "Dataset names neither given or in file names" ];
    }

    if ( scalar @seq_dbs == scalar @in_files )
    {
        # Check dataset names,
        
        $reg_list = Registry::Register->registered_datasets();
        %seq_reg = map { $_->name, 1 } Registry::Get->seq_data( $reg_list )->options;
        
        foreach $seq_db ( @seq_dbs )
        {
            if ( not exists $seq_reg{ $seq_db } ) {
                push @errors, [ "Error", qq (Not a registered sequence database -> "$seq_db") ];
            }
        }
    }
    else
    {
        $i = scalar @in_files;
        $j = scalar @seq_dbs;
        push @errors, ["Error", qq ($i input files given, but $j sequence datasets given) ];
    }

    # Check output file,
    
    if ( $args->outfile ) {
        push @errors, &Common::File::access_error( $args->outfile, "!e" );
    } else {
        push @errors, ["Error", "An output file must be given"];
    }

    # Check output line ends format,

    if ( $sys_type = $args->outends )
    {
        $lin_ends = &Common::File::line_ends();

        if ( not $lin_end = $lin_ends->{ $sys_type } ) {
            push @errors, ["Error", qq (Wrong looking line end type -> "$sys_type") ];
        }
    }
    else {
        $lin_end = "\n";
    }
    
    # Print errors if any, and exit,

    if ( @errors ) {
        &echo_messages( \@errors );
        exit;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> REPORTING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( qq (\nPatscan report:\n) );

    &echo( qq (   Removing duplicate hits ... ) );

    $count = 0;
    
    for ( $i = 0; $i <= $#in_files; $i += 1 )
    {
        $in_file = $in_files[$i];
        $seq_db = $seq_dbs[$i];

        @lines = split "\n", ${ &Common::File::read_file( $in_file ) };

        foreach $loc ( &Seq::Patterns::patscan_to_locs( \@lines, {"strflag" => 0, "seqflag" => 1 }) )
        {
            $count += 1;

            $seq_id = $loc->[0];
            $hit_beg = $loc->[2]->[0]->[0];
            $hit_end = $loc->[2]->[-1]->[0] + $loc->[2]->[-1]->[1] - 1;
            
            $hitstr = $hit_beg ."_". (join "_", @{ $loc->[3] } ) ."_$hit_end";
            
            if ( not exists $seen{ $hitstr } )
            {
                $seen{ $hitstr } = 1;
                
                push @seq_info, [ $seq_db, $seq_id, $hit_beg, $hit_end ];
                push @hit_seqs, &Storable::dclone( $loc->[3] );
            }
        }
    }
    
    $diff = $count - scalar @seq_info;
    
    if ( $diff > 0 ) {
        &echo_green( &Common::Util::commify_number( $diff ) ."\n" );
    } else {        
        &echo_green( "none\n" );
    }
    
    &echo( qq (   Generating report ... ) );

    # Format table,

    @hit_seqs = &Common::Tables::format_ascii( \@hit_seqs );

    # Create lookup hash,

    for ( $i = 0; $i <= $#hit_seqs; $i += 1 )
    {
        ( $seq_db, $seq_id, $hit_beg, $hit_end) = @{ $seq_info[$i] };
        push @{ $hit_dict{ $seq_db }{ $seq_id } }, [ $hit_beg, (join "\t", @{ $hit_seqs[$i] }), $hit_end ];
    } 

    # Fetch sequences with annotation and create report table,

    foreach $seq_db ( @seq_dbs )
    {
        @ids = keys %{ $hit_dict{ $seq_db } };

        foreach $seq ( Seq::IO->get_seqs_db( \@ids, $seq_db, 1 ) ) 
        {
            $seq_id = $seq->id;

            $annot = $seq->annot; 
            $org_name = $annot->species->{"name"} || "";
            $tax_names = ( join "; ", @{ $annot->species->{"classification"} || [] } ) || "";
            $function = $annot->desc;
            
            foreach $hit ( @{ $hit_dict{ $seq_db }{ $seq_id } } )
            {
                ( $hit_beg, $hit_seq, $hit_end ) = @{ $hit };
                
                push @report, [
                    $hit_beg,   # Start pos
                    $hit_seq,   # Match
                    $hit_end,   # End pos
                    $seq_id,     # Acc number
                    $tax_names,     # Org tax
                    $org_name,    # Org name
                    $function,    # Description
                ];
            }
        }
    }
    
    # Sort by taxonomy,

    @report = sort { $a->[4] cmp $b->[4] } @report;

    # Write output,

    &Common::Tables::write_tab_table( $args->outfile, \@report );
    &echo_green( &Common::Util::commify_number( scalar @report ) ." lines\n" );

    &echo_bold( qq (Done\n\n) );

    return;
}

1;

__END__
