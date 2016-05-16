package Ali::Import;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Functions and methods related to alignment import, including loading
# features into database. Routines for native formats are in the IO.pm 
# module. Supported ascii file formats include 
# 
# Fasta
# Stockholm
#
# and more will be added. 
#
# add_rfam_genome_flanks
# copy_stockholm_entries
# import_features_alis
# measure_stream
# needs_update
# paint_features
# read
# read_fasta                Reads fasta format into $ali, in memory
# read_seq_ids
# read_stockholm_1
# read_stockholm_entry
# split_dbflat_generic
# split_dbflats_generic
# split_dbflats_stockholm
# split_uclust
# write_ali_info
# write_feature_tables      Writes features to table file(s)
# write_pdl_from_stream     Converts stream to raw, for data >> memory 
# write_pdl_from_fasta      Converts fasta to raw, for data >> memory 
# write_pdl_from_stockholm  Converts stockholm to raw, for data >> memory 
# write_pdl_from_stockholm_1
# write_rfam_genome_flanks       
# write_fasta_from_uclust   Converts uclust alignment to fasta format
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION END <<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use Data::Dumper;
use List::Util;

use File::Basename;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Import;
use Common::DB;
use Common::Util;
use Common::Names;
use Common::Entrez;

use Ali::DB;
use Ali::IO;
use Ali::Schema;
use Ali::Common;

use Seq::Features;

use Sims::Import;

use RNA::Import;
use DNA::EMBL::Download;

use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_rfam_genome_flanks
{
    # Niels Larsen, March 2006.

    # Adds genome sequence upstream and downstream of the current sequence.
    # The sequence added is fetched from EMBL, and the coordinates gotten by
    # parsing the Rfam short-ids (for now). We assume an un-pdlified alignment
    # as input and output.

    my ( $self,          # Alignment
         $flanks,        # Flank upstream/down size - OPTIONAL, default 2000
         $msgs,          # Messages list - OPTIONAL
         ) = @_;

    # Returns updated alignment. 

    my ( $sids, $seqs, $row, $sid, $seq, $embl_id, $bioperlO, @seqs5, @seqs3, 
         $beg, $end, $seq5, $seq3, $maxlen5, $maxlen3, $len5, $len3, $col, 
         $orig_sid, $orig_sids, $orig_len, $genus, $species, $maxcol, $org, 
         $bases5, $bases3, @ft_locs, $ft_beg, $ft_end, $masks, $mask, $errors,
         $seq_len, @accs, @accs_uniq, $acc, @gis, %gis, $gi, $i, $org_str, 
         $org_sid, %org_sids, $seqO );

    $bases5 = $flanks || 2000;
    $bases3 = $flanks || 2000;

    $sids = $self->sids;
    $seqs = $self->seqs;

    $orig_len = length $seqs->[0];

    for ( $row = 0; $row <= $#{ $sids }; $row++ )
    {
        # Get id, beg and end from Rfam label,

        $orig_sid = $sids->[$row];

        if ( $orig_sid =~ /^(.+)\/(\d+)-(\d+)$/ )
        {
            $acc = $1;
            $ft_beg = $2 - 1;   # Make 0-based
            $ft_end = $3 - 1;   #   - 

            push @ft_locs, [ $acc, $ft_beg, $ft_end ];
            push @accs, $acc;
        }
        else {
            &error( qq (Wrong looking label -> "$orig_sid") );
        }
    }

#     @accs_uniq = &Common::Util::uniqify( \@accs );
#     @gis = &Common::Entrez::accs_to_gis( \@accs_uniq, "dna_seq", $msgs );

#     for ( $i = 0; $i <= $#accs_uniq; $i++ )
#     {
#         $gis{ $accs_uniq[$i] } = $gis[$i];
#     }

    %org_sids = ();

    for ( $row = 0; $row <= $#{ $sids }; $row++ )
    {
#        $acc = $accs[$row];
#        $gi = $gis{ $acc };

        ( $acc, $ft_beg, $ft_end ) = @{ $ft_locs[$row] };

        $bioperlO = Seq::IO->read_genbank_entry( $acc,
                                                 {
                                                     "datatype" => "dna_seq",
                                                     "format" => "bioperl",
                                                     "source" => "local",
                                                 }, $msgs );

        if ( defined $bioperlO )
        {
            $seqO = $bioperlO->next_seq;

            $org_str = ( $seqO->species->classification )[0];
            $org_sid = &Common::Names::create_org_id( $org_str, \%org_sids );

            # Use Genbank entry to attach neighborhood regions. Skip entries with 
            # no/little sequence .. some retired records come back from bioperl
            # with the sequence "N", so skip those,
            
            $seq = $seqO->seq;
            $seq_len = length $seq;
            
            if ( $seq and $seq_len > 1 and $ft_beg < $seq_len and $ft_end < $seq_len ) 
            {
                if ( $ft_beg < $ft_end )
                {
                    $beg = &Common::Util::max( 0, $ft_beg - $bases5 );
                    
                    $seq5 = lc substr $seq, $beg, $ft_beg - $beg;
                    
                    $end = &Common::Util::min( (length $seq) - 1, $ft_end + $bases3 );
                    $seq3 = lc substr $seq, $ft_end+1, $end - $ft_end;
                }
                else 
                {
                    $end = &Common::Util::min( (length $seq) - 1, $ft_beg + $bases5 );
                    $seq5 = substr $seq, $ft_beg+1, $end - $ft_beg;
                    $seq5 = lc ${ &Seq::Common::complement_str( \$seq5 ) };
                    
                    $beg = &Common::Util::max( 0, $ft_beg - $bases3 );
                    $seq3 = substr $seq, $beg, $ft_beg - $beg;
                    $seq3 = lc ${ &Seq::Common::complement_str( \$seq3 ) };
                }
                
                push @seqs5, $seq5;
                push @seqs3, $seq3;
            }
            else
            {
                push @seqs5, "";
                push @seqs3, "";
            }
        }
        else
        {
            $org_sid = "---.---.";
            push @seqs5, "";
            push @seqs3, "";
        }

        $sids->[$row] = $org_sid;
    }

    # Add filler gaps to sequences,

    $maxlen5 = &List::Util::max( map { length $_ } @seqs5 );
    $maxlen3 = &List::Util::max( map { length $_ } @seqs3 );
    
    for ( $row = 0; $row <= $#{ $seqs }; $row++ )
    {
        $len5 = length $seqs5[$row];
        $len3 = length $seqs3[$row];
        
        $seqs->[$row] = ("." x ($maxlen5-$len5) ). $seqs5[$row] 
                      . $seqs->[$row]
                      . $seqs3[$row] . ("." x ($maxlen3-$len3) );
    }

    # Add filler gaps to masks,

    if ( defined ( $masks = $self->pairmasks ) )
    {
        foreach $mask ( @{ $masks } ) 
        {
            $mask->[2] = ("." x $maxlen3) . $mask->[2] . ("." x $maxlen3);
        }

        $self->pairmasks( $masks );
    }

    # Mark gene start/end columns,

    $self->orig_colbeg( $maxlen5 );
    $self->orig_colend( $maxlen5 + $orig_len - 1 );

    # Set column counts,

    $self->sid_cols( &List::Util::max( map { length $_ } @{ $sids } ) );
    $self->dat_cols( &List::Util::max( map { length $_ } @{ $seqs } ) );

    # Put back,

    @ft_locs = map { "$_->[0]:$_->[1]-$_->[2]" } @ft_locs;

    $self->ft_locs( \@ft_locs );

    $self->sids( $sids );
    $self->seqs( $seqs );

    return $self;
}

#         $seq = $seqO->seq;

#         if ( defined $seqO->species )
#         {
#             $species = $seqO->species;

#             if ( defined $species->binomial ) {
#                 $orgstr .= $seqO->species->binomial;
#             }

#             if ( defined $species->common_name ) {
#                 $orgstr .= " (". $seqO->species->common_name .")";
#             }
#         }

#         if ( $reverse ) {
#             $infh->print( ">$id"."_$to-$from\t$orgstr\n$subseq\n" );
#         } else {
#             $infh->print( ">$id"."_$from-$to\t$orgstr\n$subseq\n" );
#         }            
#     }
    
#     &Common::File::close_handle( $infh );
# }

sub copy_stockholm_entries
{
    # Niels Larsen, March 2006.

    # Given an input file of stockholm formatted entries, writes a new file with
    # only those stockholm entries where the ID matches a given list of IDs or 
    # ID-expressions. They input file may be compressed. Returns the number of 
    # entries copied.

    my ( $ifile,          # Input file
         $ofile,          # Output file
         $filter,         # Filter IDs / expressions
         ) = @_;

    # Returns integer. 

    my ( $ifh, $ofh, @lines, $line, $count, $sid );

    if ( not defined $filter ) {
        &error( qq (No filter ids given) );
    }

    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( $ofile );

    $count = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        push @lines, $line;

        if ( $line =~ /^\#=GF ID   (.+)$/ )
        {
            $sid = $1;

            if ( grep { $sid =~ /$_/ } @{ $filter } )
            {
                while ( $line !~ /^\/\// )
                {
                    $line = <$ifh>;
                    push @lines, $line;
                }

                $ofh->print( @lines );
                $count += 1;
            }
            else
            {
                while ( $line !~ /^\/\// )
                {
                    $line = <$ifh>;
                }
            }

            @lines = ();
        }
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    return $count;
}

sub import_features_alis
{
    # Niels Larsen, February 2006.

    # Makes features for a given list of alignments and loads them into the 
    # given database. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $files, $file, $ali, $tab_dir, $dbh, @ali_sids, $count, $ft_id, $beg_id,
         $ft_desc, $ft_names, $ft_menu, $schema, $ali_prefix, $ft_source, $db_name,
         $routine, $fts, $msg );

    require Ali::Features;

    $args = &Registry::Args::check(
        $args,
        {
            "AR:1" => [ qw ( in_files ft_names ) ],
            "S:1" => [ qw ( tab_dir ft_source db_name ) ], 
        });

    $files = $args->in_files;
    $ft_names = $args->ft_names;
    $tab_dir = $args->tab_dir;
    $ft_source = $args->ft_source;
    $db_name = $args->db_name;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> INITIALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( &Common::Types::is_user_db( $db_name ) ) {
        $dbh = &Common::DB::connect_user( $db_name, 1 );
    } else {
        $dbh = &Common::DB::connect( $db_name || "", 1 );
    }
    
    $ft_id = &Ali::DB::highest_feature_id( $dbh ) + 1;
    $beg_id = $ft_id;     # $ft_id is incremented below
    
    $ft_menu = Registry::Get->features( $ft_names );

    foreach $ft_desc ( @{ $ft_menu->options } ) 
    {
        $ft_desc->source( $ft_source );
    }

    # >>>>>>>>>>>>>>>>>>>>> WRITE TABLES AND ALI INFO <<<<<<<<<<<<<<<<<<<

    foreach $file ( @{ $files } )
    {
        foreach $ft_desc ( @{ $ft_menu->options } )
        {
            # Some features are purely made at run-time, like showing protein 
            # hydrophobicity. So we check if there is a feature making routine
            # for the type and only make features if so,

            if ( $routine = $ft_desc->imports->routine )
            {
                # Generate features. This is a routine that dispatches to different 
                # routines that generate a specific feature. The names of the routines 
                # follow the names of the features: "create_features_" followed by the 
                # feature type. Each routine increments the feature id.
                
                if ( $Ali::Features::{ $routine } )
                {
                    if ( not defined $ft_id or $ft_id !~ /^\d+/ )
                    {
                        $msg = qq (Wrong looking feature id);
                        &error( qq (Wrong looking feature id ->\" ) .&dump( $ft_id ). qq (\") );
                    }

                    $fts = Ali::Features->$routine(
                        {
                            "ali_file" => $file,
                            "ft_desc" => $ft_desc,
                            "ft_id" => $ft_id,
                            "ft_file" => &Common::Names::replace_suffix( $file, ".stream" ),
                        }, $msgs );

                    # Write features if any,
                    
                    if ( defined $fts and @{ $fts } )
                    {
                        # Features are put in two tables, one that identifies them etc, and 
                        # one that gives their positions (features can be arbitrary sets of 
                        # rectangles),
                        
                        &Ali::Import::write_feature_tables( $fts, $tab_dir, ">>" );

                        $ft_id = $fts->[-1]->id + 1;
                    }
                }
                else {
                    &error( qq (Subroutine does not exist -> "$routine") );
                }
            }
        }

        $ali = &Ali::IO::connect_pdl( $file );

        push @ali_sids, $ali->sid;

        undef $ali;
    }

#    &dump( "done writing feature files" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LOAD TABLES <<<<<<<<<<<<<<<<<<<<<<<<<

    $schema = Ali::Schema->get;

    if ( &Common::DB::datatables_exist( $dbh, $schema ) ) {
        &Ali::DB::delete_entries( $dbh, $ft_source, undef, \@ali_sids );
    } else {
        &Common::DB::create_tables( $dbh, $schema );
    }
    
    if ( $ft_id > $beg_id )
    {
        &Ali::DB::load_features( $dbh, $tab_dir );
        &Common::Import::delete_tabfiles( $tab_dir, $schema );
    }

    &Common::DB::disconnect( $dbh );

#    &dump( "done loading feature files" );

    return ( $ft_id - $beg_id );
}

sub measure_stream
{
    # Niels Larsen, May 2007.

    # Reads a file of streamed alignment entries and returns a hash
    # with "measurements": the number of rows, length of longest 
    # sequence, width of longest label (or id if not given), width
    # of begin and end numbers.

    my ( $class,
         $file,       # Input file name
         $args,       # Arguments - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $sid_cols, $dat_cols, $seq_beg, $seq_end, $dat_rows, 
         $stream, $stone, %counts, $i, $j );

    $stream = Boulder::Stream->newFh( -in => $file );
    
    $dat_rows = $dat_cols = 0;
    $seq_beg = $seq_end = 0;
    $sid_cols = 0;

    while ( $stone = <$stream> )
    {
        if ( $stone->Label ) {
            $i = length $stone->Label;
        } else {
            $i = length $stone->ID;
        }            

        $sid_cols = $i if $i > $sid_cols;

        $i = length $stone->Seq;
        $dat_cols = $i if $i > $dat_cols;

        if ( $stone->Seq_frame2 > 0 )
        {
            $i = $stone->Seq_beg;
            $j = $stone->Seq_end;
        }
        else
        {
            $i = $stone->Seq_len - $stone->Seq_end - 1;
            $j = $stone->Seq_len - $stone->Seq_beg - 1;
        }

        $seq_beg = $i if $i > $seq_beg;
        $seq_end = $j if $j > $seq_end;
        
        $dat_rows += 1;
    }

    undef $stream;

    if ( $seq_beg < $seq_end ) {
        $seq_end += $dat_cols;
    } else {
        $seq_end -= $dat_cols;
    }

    %counts = (
        "sid_cols" => $sid_cols,
        "dat_cols" => $dat_cols,
        "dat_rows" => $dat_rows,
        "beg_cols" => length (sprintf "%s", $seq_beg),
        "end_cols" => length (sprintf "%s", $seq_end),
        );

    return wantarray ? %counts : \%counts;
}

sub needs_update
{
    # Niels Larsen, April 2006.

    # Given a list of source and destination files, returns the source files
    # that are newer than or missing among the destination files. The names 
    # must somehow match in order to do that, and the name part up to the 
    # first period is used. The input lists are lists of hashes as generated
    # by the Common::File::list_* routines.

    my ( $src_files,         # Source file list or path
         $dst_files,         # Destination file list or path
         $expr,
         ) = @_;

    # Returns a list.

    my ( %dst_files, $file, $name, @upd_files );

    $expr ||= '\..*$';

    if ( not defined $src_files ) {
        &error( qq (Source file(s) not given.) );
    } 
    elsif ( not ref $src_files ) {
        $src_files = [ &Common::File::get_stats( $src_files ) ];
    }

    if ( not defined $dst_files ) {
        &error( qq (Source file list not given.) );
    }
    elsif ( not ref $dst_files ) {
        $dst_files = [ &Common::File::get_stats( $dst_files ) ];
    }

    foreach $file ( @{ $dst_files } )
    {
        $name = $file->{"name"};
        $name =~ s/$expr//;
        
        $dst_files{ $name } = $file;
    }

    foreach $file ( @{ $src_files } )
    {
        $name = $file->{"name"};
        $name =~ s/$expr//;

        if ( not exists $dst_files{ $name } or
             ( -M $file->{"path"} < -M $dst_files{ $name }->{"path"} ) )
        {
            push @upd_files, $file;
        }
    }

    return wantarray ? @upd_files : \@upd_files;
}

sub paint_features
{
    # Niels Larsen, May 2007.

    # Reads all .sims files in a given results directory (res_dir), creates
    # similarity features of these, loads them into the users own database,
    # and finally adds a similarity matchh option to the users state file.
    # All features are painted on the same alignment, and a link is made to 
    # the system alignment (making it "virtual").

    my ( $args,
         $msgs,
         ) = @_;

    # Returns nothing.

    my ( $prefix, $stream, $sims_file, $sims, $sim, $irow, $ali, $stone,
         $tuples, $ft_menu, $opt, $dbh, $ali_file, $count, $state, $menu, $dir,
         $file );

    $args = &Registry::Args::check(
        $args,
        {
            "S:1" => [ qw ( tab_dir res_dir dbpath dbname sid jid itype title method ) ], 
        });

    $prefix = $args->res_dir ."/". $args->jid;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET LINK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # We use existing alignment, but create a link to it in the users
    # session directory,

    if ( not -r "$prefix.pdl" )
    {
        &Common::File::create_link( $args->dbpath .".pdl", "$prefix.pdl" );
        &Common::File::create_link( $args->dbpath .".info", "$prefix.info" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE STREAM FILE <<<<<<<<<<<<<<<<<<<<<<<<

    $stream = Boulder::Stream->newFh( -out => "$prefix.stream" );

    foreach $sims_file ( &Common::File::list_files( $args->res_dir, '.sims$' ) )
    {
        $sims = &Common::File::eval_file( $sims_file->{"path"} );

        foreach $sim ( @{ $sims } )
        {
            if ( $sim->id2 =~ /:(\d+)$/ ) {
                $irow = $1;
            } else {
                &error( qq (Wrong looking match id -> ). $sim->id2 );
            }

            $stone = Stone->new(
                "ID" => $sim->id2,
                "Type" => "subject",
                "Score" => 0, 
                "Seq_beg" => 0,
                "Sim_locs2" => &Common::Util::stringify( $sim->locs2 ),
                "Sim_rows" => &Common::Util::stringify( [[ int $irow, int $irow ]] ),
                );

            $stream->print( $stone );
        }
    }

    undef $stream;

    # >>>>>>>>>>>>>>>>>>>>>>> LOAD SIMILARITY FEATURES <<<<<<<<<<<<<<<<<<<<

    $count = &Ali::Import::import_features_alis(
        {
            "in_files" => [ "$prefix.pdl" ],
            "ft_names" => [ "ali_sim_match" ],
            "ft_source" => $args->dbname,
            "tab_dir" => $args->tab_dir,
            "db_name" => $args->sid,
        }, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATE FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This section creates a menu of features, where there is at least
    # one occurrence - users will not see feature options without hits
    # (alternatively one could grey those out, but not all browsers 
    # support CSS in pulldown menus yet). 
    
    &Ali::Create::create_state_files(
        {
            "ali_file" => "$prefix.pdl",
            "state_file" => "$prefix.state",
            "with_query_seq" => 0,
        }, $msgs );

    return $count;
}

sub read
{
    # Niels Larsen, April 2006.

    # Reads an alignment into memory from a given file, with format given.
    
    my ( $file, 
         $format,
         $args,
         ) = @_;

    # Returns alignment.

    my ( $ali, $method );

    if ( $format eq "fasta" )
    {
        $ali = Ali::Import->read_fasta( $file, $args );
    }
    elsif ( $format eq "stockholm" ) 
    {
        $ali = Ali::Import->read_stockholm_1( $file );
    }
    else {
        &error( qq (Unrecognized alignment format.) );
    }

    return $ali;
}

sub read_fasta
{
    # Niels Larsen, June 2005.
    
    # Loads an alignment into memory from a fasta file as an un-pdlified
    # alignment object. Multiple pairing masks are ok, but they must all
    # be called "Pairingmask". 

    my ( $class,         # Class name
         $ifile,         # Input file name
         $args,          # Hash with extra information - OPTIONAL
         ) = @_;

    # Returns an alignment object. 
    
    my ( $ifh, $pairmasks, $i_row, $o_row, $seqO, $seqid, $ali, 
         @sids, @seqs, $key, $ignore );

    # >>>>>>>>>>>>>>>>>>>>>> READ AND WRITE ENTRIES <<<<<<<<<<<<<<<<<<<<<<

    # Here we print sequence lines as PDL likes it: "$id$seq$id$seq...".
    # If custom short-ids are given then they are written as ids rather than
    # those coming from the fasta file. 

    $ifh = &Common::File::get_read_handle( $ifile );

    $i_row = 0;
    $o_row = 0;

    $ignore = $args->{"ignore"};

    while ( $seqO = bless &Seq::IO::read_seq_fasta( $ifh ), "Seq::Common" )
    {
        $seqid = $seqO->id;

        if ( not $ignore or $seqid !~ / *$ignore */i )
        {
            if ( $seqid =~ /^\s*Pairingmask/i )
            {
                push @{ $pairmasks }, [ $o_row, $o_row-1, $seqO->seq ];
            }
            else
            {
                push @sids, $seqid;
                push @seqs, $seqO->seq;

                $pairmasks->[-1]->[1] += 1 if $pairmasks;

                $o_row += 1;
            }
        }

        $i_row += 1;
    }

    &Common::File::close_handle( $ifh );

    $ali = $class->new( "file" => $ifile );

    $ali->sids( \@sids );
    $ali->seqs( \@seqs );

    if ( $pairmasks ) 
    {
        $ali->pairmasks( $pairmasks );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> ADD "META" INFO <<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $key ( keys %{ $args } )
    {
        if ( $key ne "sids" ) {
            $ali->{ $key } = $args->{ $key };
        }
    }

    return $ali;
}

sub read_seq_ids
{
    # Niels Larsen, December 2006.

    # Collects a list of sequence ids from a set of alignment files given
    # by their file paths.

    my ( $class,
         $files,         # File paths
         ) = @_;

    # Returns a list.

    my ( @sids, %sids, $file, $ali );

    foreach $file ( @{ $files } )
    {
        $ali = &Ali::IO::connect_pdl( $file->{"path"} );
        $ali = &Ali::Common::de_pdlify( $ali );

        push @sids, @{ $ali->sids };

        undef $ali;
    }

    @sids = &Common::Util::uniqify( \@sids );

    return wantarray ? @sids : \@sids;
}

sub read_stockholm_1
{
    # Niels Larsen, January 2006.

    # Reads one entry, the first, from a Stockholm formatted alignment file.
    
    my ( $class,       # Class name
         $ifile,       # Input stockholm file
         ) = @_;

    my ( $measure, $sidlen, $seqlen, $ali, $fh );

    $fh = &Common::File::get_read_handle( $ifile );

    $ali = $class->read_stockholm_entry( $fh );
    $ali = &Ali::Commmon::pdlify( $ali );
        
    &Common::File::close_handle( $fh );

    return $ali;
}

sub read_stockholm_entry
{
    # Niels Larsen, September 2005.
    
    # Reads a "Stockholm" formatted entry from a given file handle into into 
    # an alignment object in memory. If a hash of IDs is given, then only entries
    # whose IDs are in that hash are returned, the rest return undefined; the 
    # caller must check for this. But if no ID hash given, the next entry is 
    # always returned. The sequences (aligned or unaligned) are stored as a 
    # list of strings. 

    my ( $class,         # Class name
         $fh,            # File handle
         $args,          # Hash of arguments - OPTIONAL
         $msgs,          # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns an alignment object. 
    
    my ( $line, $ali, $seqrow, $maskrow, $sid, $seq, $subseq, $key, $first, 
         @sids, @sids_orig, @seqs, @begs, @ends, @masks, $seqrow_max, 
         $skip_ids, $regexp );

    if ( $args->{"skip_ids"} ) {
        $skip_ids = { map { $_, 1 } @{ $args->{"skip_ids"} } };
    }

    while ( defined ( $line = <$fh> ) and 
            ( $line =~ /^\s*$/ or $line =~ /^\# STOCKHOLM/ ) )
    {
        $line = <$fh>;
    };

    if ( not defined $line ) {
        return;
    }

    $ali = {};

    # >>>>>>>>>>>>>>>>>>>>>>>>>> HEADER PART <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Only uses ID, DE and SQ lines, will be expanded. If ids hash given 
    # and the encountered ID value not in the hash, then skip ahead and 
    # return nothing,

    while ( $line =~ /^\#=GF ([A-Z][A-Z])   (.+)$/ )
    {
        $key = $1;
        $sid = $2;

        if ( $key eq "ID" )
        {
            if ( $skip_ids and $skip_ids->{ $sid } )
            {
                while ( $line !~ /^\/\// )
                {
                    $line = <$fh>;
                }

                return;
            }

            $ali->{"sid"} = $sid;
        }
        elsif ( $1 eq "DE" )
        {
            $ali->{"title"} = $sid;
        }
        elsif ( $1 eq "SQ" )
        {
            $seqrow_max = $2 - 1;
        }

        $line = <$fh>;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE BLOCKS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Loop through a sequence blocks.
        
    $first = 1;

    while ( $line !~ /^\/\// )
    {
        # Skip blanks,

        while ( $line =~ /^\s*$/ )
        {
            $line = <$fh>;
        };

        $seqrow = 0;
        $maskrow = 0;

        while ( $line =~ /\S/ and $line !~ /^\/\// )
        {
            # Pairing masks,

            if ( $line =~ /^\#=GC\s+(\S+)\s+(\S+)/ )
            {
                $sid = $1;
                $subseq = $2;

                if ( $sid eq "SS_cons" )
                {
                    if ( $first ) {
                        push @masks, $subseq;
                    } else {
                        $masks[$maskrow] .= $subseq;
                    }
                }

                $maskrow += 1;
            }

            # Sequence lines,

            elsif ( $line =~ /^(.+\/\d+-\d+) +(\S+)$/ )
            {
                $sid = $1;
                $subseq = $2;

                if ( $first )
                {
                    push @sids, $sid;
                    push @seqs, $subseq;
                }
                else {
                    $seqs[$seqrow] .= $subseq;
                }

                $seqrow += 1;
            }
            else {
                &error( qq (Wrong looking sequence line -> "$line") );
            }

            $line = <$fh>;
        }

        $first = 0;
    }

    @begs = ();
    @ends = ();

    if ( $args->{"split_sids"} )
    {
        @sids_orig = @sids;
        @sids = ();
        $regexp = $args->{"split_sids"};

        foreach $sid ( @sids_orig ) 
        {
            if ( $sid =~ /$regexp/ ) {
                push @sids, $1;
                push @begs, $2 - 1;
                push @ends, $3;
            } else {
                push @sids, $sid;
                push @begs, 0;
                push @ends, 0;
                print "no:  '$sid', $regexp\n";
            }
        }
    }
    else
    {
        foreach $seq ( @seqs )
        {
            push @begs, 0;
            push @ends, length $seq;
        }
    }

    $ali->{"sids"} = \@sids;
    $ali->{"seqs"} = \@seqs;
    $ali->{"begs"} = \@begs;
    $ali->{"ends"} = \@ends;

    if ( scalar @masks == 1 )
    {
        $ali->{"pairmasks"} = [[ 0, $seqrow_max, $masks[0] ]];
    }
    elsif ( scalar @masks > 1 )
    {
        push @{ $msgs }, [ "Error", "Entry ". $ali->sid .": multiple masks are not yet supported. Entry skipped." ];
        return;
    }

    bless $ali, "Ali::Common";

#    $ali = Ali::Common->new( %{ $ali } );

    return $ali;
}

# sub split_dbflat_generic_works
# {
#     my ( $class,
#          $args,
#          $msgs,
#         ) = @_;

#     my ( $ifh, $chunk, $id_expr, $odir, @paths, $suffix, $ofile, $ofh );
    
#     $args = &Registry::Args::check(
#         $args,
#         { 
#             "S:2" => [ qw ( ifile odir suffix id_expr ) ],
#         });

#     $odir = $args->odir;
#     $suffix = $args->suffix;
#     $id_expr = $args->id_expr;
    
#     $ifh = &Common::File::get_read_handle( $args->ifile );

#     local $/;
#     $/ = "//\n";

#     while ( defined ( $chunk = <$ifh> ) )
#     {
#         if ( $chunk =~ /$id_expr/m )
#         {
#             $ofile = "$odir/$1.$suffix";
#             $ofh = &Common::File::get_write_handle( $ofile );
            
#             $ofh->print( $chunk );
#             $ofh->close;
            
#             push @paths, $ofile;
#         }
#         else {
#             &error( qq (ID expression did not match entry) );
#             }
#     }
    
#     $ifh->close;

#     return wantarray ? @paths : \@paths;    
# }

sub split_dbflats_generic
{
    my ( $class,
         $args,
         $msgs,
        ) = @_;

    my ( $ifile, @paths );

    $args = &Registry::Args::check(
        $args,
        { 
            "AR:1" => [ qw ( ifiles ) ], 
            "S:1" => [ qw ( odir suffix id_expr ) ],
            "AR:0" => [ qw ( skip_ids ) ],
        });

    foreach $ifile ( @{ $args->ifiles } )
    {
        push @paths, Ali::Import->split_dbflat_generic(
            {
                "ifile" => $ifile,
                "odir" => $args->odir,
                "suffix" => $args->suffix,
                "id_expr" => $args->id_expr,
                "skip_ids" => $args->skip_ids,
            }, $msgs );
    }

    return wantarray ? @paths : \@paths;
}    

sub split_uclust
{
    # Niels Larsen, June 2010.

    # Fills a given output directory with the alignments that are in a given
    # uclust alignment file. Each output alignment is in fasta format. Returns
    # number of alignments written.

    my ( $args,        # Arguments hash
        ) = @_;

    # Returns integer.

    my ( $defs, $old_num, $num, $ifh, $min_size, $out_dir, @lines, $line, 
         $id, $count );

    $defs = {
        "ifile" => undef,
        "iformat" => "uclust",
        "odir" => ".",
        "minsize" => 1,
    };

    $args = &Registry::Args::create( $args, $defs );

    $old_num = -1;
    $min_size = $args->minsize;
    $out_dir = $args->odir;

    @lines = ();
    $count = 0;

    $ifh = &Common::File::get_read_handle( $args->ifile );
    
    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ />(\d+)\|[^\|]+\|(.+)/ )
        {
            $num = $1;
            $id = $2;
            
            if ( $num ne $old_num )
            {
                if ( $#lines / 2 >= $min_size )
                {
                    unshift @lines, ( $lines[-2], $lines[-1] );                    
                    &Common::File::write_file( "$out_dir/$num.cluali", \@lines );

                    $count += 1;
                }

                $old_num = $num;
                @lines = ();
            }

            push @lines, ">$id\n";
            push @lines, $line = <$ifh>;
        }
        else {
            chomp $line;
            &error( qq (Wrong looking line -> "$line") );
        }
    }

    $ifh->close;

    return $count;
}

sub write_ali_info
{
    my ( $class,
         $opath,
         $counts,
         $args,
         $masks,
        ) = @_;

    my ( $info );

    $info = {
        "sid_cols" => $counts->{"sid_cols"}, 
        "beg_cols" => $counts->{"beg_cols"},
        "end_cols" => $counts->{"end_cols"},
        "dat_cols" => $counts->{"dat_cols"},
        "dat_rows" => $counts->{"dat_rows"},
        "datatype" => $args->datatype,
        "sid" => $args->sid,
        "source" => $args->source,
        "title" => $args->title,
    };

    if ( $masks and @{ $masks } ) {
        $info->{"pairmasks"} = $masks;
    }
    
    &Ali::IO::write_into_pdl( undef, $opath, $info );

    return;
}
    
sub write_feature_tables
{
    # Niels Larsen, February 2007.

    # Writes a list of features to table file(s). The second argument
    # is a directory where to write the files. The file names are the
    # key names from the alignment schema. 

    my ( $fts,        # Feature list
         $dir,        # Directory path
         $mode,       # Write mode, ">>" or ">"
         ) = @_;

    # Returns nothing.
    
    my ( $fh, $schema, $ft, $rowstr, $area, $fhs );

    &Common::File::create_dir_if_not_exists( $dir );

    $schema = Ali::Schema->get;
    $fhs = &Common::Import::create_tabfile_handles( $dir, $schema, $mode );

    # Table "ali_features",

    foreach $ft ( @{ $fts } )
    {
        $rowstr = join "\t", ( $ft->ali_id, $ft->ali_type, $ft->id, $ft->type, 
                               $ft->source || "", $ft->score || "", $ft->stats || "" );
        
        $fhs->{"ali_features"}->print( "$rowstr\n" );
    }

    # Table "ali_feature_pos",

    foreach $ft ( @{ $fts } )
    {
        if ( $ft->areas )
        {
            foreach $area ( @{ $ft->areas } )
            {
                $area->[4] ||= "";
                $area->[5] ||= "";
                $area->[6] ||= "";
                $area->[7] ||= "";
                
                if ( not $ft->source ) {
                    &dump( "No source field:" );
                    &dump( $ft );
                }
                
                $rowstr = join "\t", ( $ft->ali_id, $ft->ali_type, $ft->id, $ft->type, 
                                       $ft->source, @{ $area } );
                
                $fhs->{"ali_feature_pos"}->print( "$rowstr\n" );
            }
        }
        else {
            &dump( "No areas field:" );
            &dump( $ft );
        }
    }
    
    &Common::File::close_handles( $fhs );

    return;
}

sub write_pdl_from_stream
{
    # Niels Larsen, May 2007.

    my ( $class,          # Class name
         $args,           # Arguments hash
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;
    
    # Returns an integer. 

    my ( $counts, $o_fh, $stream, $sid_cols, $dat_cols, $dat_rows, 
         $beg_cols, $end_cols, $stone, $seqid, $begstr, $endstr,
         $seqstr, $info, $suff1, $suff2, $suff, $idstr );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( ifile opath datatype sid source title ) ], 
            "HR:0" => [ qw ( params ) ],
            "S:0" => [ qw ( sids ) ],
            "AR:1" => [ qw ( suffixes ) ],
        });

    ( $suff1, $suff2 ) = @{ $args->suffixes };

    $counts = Ali::Import->measure_stream( $args->ifile );

    &Common::File::delete_file_if_exists( $args->opath . $suff1 );
    &Common::File::delete_file_if_exists( $args->opath . $suff2 );

    # >>>>>>>>>>>>>>>>>>>>>> READ AND WRITE ENTRIES <<<<<<<<<<<<<<<<<<<<<<

    # Here we print sequence lines as PDL likes it: "$id$seq$id$seq...".
    # If custom short-ids are given then they are written as ids rather than
    # those coming from the fasta file,

    $o_fh = &Common::File::get_write_handle( $args->opath .".pdl" );
    binmode $o_fh;

    $stream = Boulder::Stream->newFh( -in => $args->ifile );

    $sid_cols = $counts->{"sid_cols"};
    $dat_cols = $counts->{"dat_cols"};
    $dat_rows = $counts->{"dat_rows"};
    $beg_cols = $counts->{"beg_cols"};
    $end_cols = $counts->{"end_cols"};
    
    while ( $stone = <$stream> )
    {
        if ( $stone->Label ) {
            $idstr = sprintf "%$sid_cols"."s", $stone->Label;
        } else {
            $idstr = sprintf "%$sid_cols"."s", $stone->ID;
        }

        if ( $stone->Seq_frame2 > 0 ) {
            $begstr = sprintf "%$beg_cols"."s", $stone->Seq_beg;
            $endstr = sprintf "%$end_cols"."s", $stone->Seq_end;
        } else {
            $begstr = sprintf "%$beg_cols"."s", $stone->Seq_len - $stone->Seq_beg - 1;
            $endstr = sprintf "%$end_cols"."s", $stone->Seq_len - $stone->Seq_end - 1;
        }            

        $seqstr = $stone->Seq;
        $seqstr =~ s/~/-/g;
        
        $seqstr .= "-" x ( $dat_cols - length $seqstr );

        $o_fh->print( $idstr . $begstr . $endstr . $seqstr );
    }

    undef $stream;
    $o_fh->close;

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE "META" INFO <<<<<<<<<<<<<<<<<<<<<<<<<

    # Save information about PDL file layout in separate file, 

    Ali::Import->write_ali_info( $args->opath, $counts, $args );

    return $dat_rows;
}

sub write_pdl_from_fasta
{
    # Niels Larsen, June 2005.

    # Reads through a given fasta file and writes the sequences and masks 
    # into native "raw" format (used by PDL for efficiency reason, see top
    # of this file). Only the id (consecutive non-blanks following the '>')
    # is used and the sequence ends are padded with nulls. An info file is 
    # created (output file name with .info appended) and contains alignment
    # dimensions, type, title and whatever other "meta-information" is 
    # needed. Use this routine for large alignments that will not easily 
    # fit into physical ram, as it only loads one entry at a time. The 
    # number of entries written is returned. 

    my ( $class,          # Class name
         $args,           # Hash with extra information - OPTIONAL
         $msgs,
         ) = @_;

    # Returns an integer. 

    my ( $ifile, $opath, $ifh, $ofh, $suffix, $dat_cols, $seqid, $seqlen, $seqstr, 
         $info, $i_row, $o_row, @masks, $seq, $seqO, $count, $dat_rows, $sid_cols,
         $sids, $key, $recsep, $pairmasks, $ali, $tmp_path, $suff1, $suff2, $suff,
         $counts, $beg_cols, $end_cols, $begstr, $endstr, $params, $colbeg, $colend,
         $seqbeg, $seqend, $idstr, $split_exp, $ignore );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &dump( $args );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( ifile opath datatype sid source title ) ], 
            "AR:1" => [ qw ( suffixes ) ],
            "HR:0" => [ qw ( params ) ],
            "S:0" => [ qw ( sids ) ],
        });

    $ifile = $args->ifile;
    $opath = $args->opath;
    $params = &Storable::dclone( $args->params );

    if ( not defined $params->{"hdr_regexp"} ) {
        $params->{"hdr_regexp"} = '(\S+)';
    }

    if ( not defined $params->{"hdr_fields"} ) {
        $params->{"hdr_fields"} = { "seq_id" => '$1' };
    }

    if ( not defined $params->{"wrapped"} ) {
        $params->{"wrapped"} = 1;
    }

    $split_exp = $params->{"split_sids"};
    $colbeg = $params->{"colbeg"};
    $colend = $params->{"colend"};
    $ignore = $params->{"ignore"};

    # >>>>>>>>>>>>>>>>>>>>>>>> MEASURE FASTA FILE <<<<<<<<<<<<<<<<<<<<<<<<

    # Distribution alignment files sometimes come with lines of uneven 
    # length. Native format on the other hand requires that all sequence 
    # lines and short-ids have the same length and shorter lines be
    # padded with nulls. To find the number of sequences, and the max 
    # length of ids and sequences we read through the file first to get it,
    
    $counts = &Ali::IO::measure_alipdl_fasta( $ifile, $params )->[0];

    $sid_cols = $counts->{"sid_cols"};
    $dat_rows = $counts->{"dat_rows"};
    $dat_cols = $counts->{"dat_cols"};
    $beg_cols = $counts->{"beg_cols"};
    $end_cols = $counts->{"end_cols"};

    if ( defined $colend ) {
        $dat_cols = $colend;
    }

    if ( defined $colbeg ) {
        $dat_cols -= $colbeg - 1;
    }

    if ( $args->sids )
    {
        if ( $dat_rows == scalar @{ $args->sids } )
        {
            $sids = $args->sids;
            $sid_cols = &List::Util::max( map { length $_ } @{ $sids } );
        }
        else
        {
            $count = scalar @{ $args->sids };
            &error( qq (There are $dat_rows entries in fasta file, but $count short-ids given.) );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>> SET RECORD SEPARATOR <<<<<<<<<<<<<<<<<<<<<<<<

    $recsep = $/;
    
    if ( &Common::File::is_dos( $ifile ) ) {
        $/ = "\r\n";
    } elsif ( &Common::File::is_mac( $ifile ) ) {
        $/ = "\r";
    }

    # >>>>>>>>>>>>>>>>>>>>>> READ AND WRITE ENTRIES <<<<<<<<<<<<<<<<<<<<<<

    # Here we print sequence lines to the PDL file: "$id$seq$id$seq...".
    # If custom short-ids are given then they are written as ids rather than
    # those coming from the fasta file,

    ( $suff1, $suff2 ) = @{ $args->suffixes };

    # Create output file name if not given,

    if ( not $opath )
    {
        $opath = $ifile;
        
        $opath =~ s/\.bz2$//;
        $opath =~ s/\.gz$//;
        $opath =~ s/\.fasta$//;
        $opath =~ s/\.fa$//;
    }

    $tmp_path = "$opath.temp_ali";

    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( "$tmp_path.$suff1" );

    $i_row = 0;
    $o_row = 0;

    binmode $ofh;

    while ( $seqO = bless &Seq::IO::read_seq_fasta( $ifh ), "Seq::Common" )
    {
        if ( $sids ) {
            $seqid = $sids->[ $i_row ];
        } else {
            $seqid = $seqO->id;
        }

        if ( not $ignore or $seqid !~ /$ignore/i )
        {
            if ( $seqid =~ /^\s*Pairingmask/i )
            {
                push @{ $pairmasks }, [ $o_row, $o_row-1, $seqO->seq_string ];
            }
            else
            {
                $seqstr = $seqO->seq;

                # ID and begin / end: $seqbeg is the zero-based index of the first 
                # character in the numbering of the original sequence, otherwise
                # zero. $seqend is the last. The display routine adds 1 on the 
                # human readable output. 

                if ( $split_exp and $seqid =~ /$split_exp/ )
                {
                    ( $seqid, $seqbeg, $seqend ) = ( $1, $2-1, $3-1 );
                }
                else
                {
                    $seqbeg = 0;
                    $seqend = ( $seqstr =~ tr/[A-Z][a-z]/[A-Z][a-z]/ - 1 );
                }

                if ( defined $colend and $colend <= length $seqstr ) {
                    $seqstr = substr $seqstr, 0, $colend;
                }
                
                if ( defined $colbeg ) {
                    $seqstr = substr $seqstr, $colbeg - 1;
                }                
                
                $seqstr =~ s/~/-/g;                                
                $seqstr .= "\0" x ( $dat_cols - $seqO->seq_len );

                $idstr = sprintf "%$sid_cols"."s", $seqid;
                $begstr = sprintf "%$beg_cols"."s", $seqbeg;
                $endstr = sprintf "%$end_cols"."s", $seqend;
                
                $ofh->print( $idstr . $begstr . $endstr . $seqstr );
                
                $pairmasks->[-1]->[1] += 1 if $pairmasks;
                
                $o_row += 1;
            }
        }
        
        $i_row += 1;
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    $/ = $recsep;

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE "META" INFO <<<<<<<<<<<<<<<<<<<<<<<<<

    # Save information about PDL file layout in separate file, 
    
    Ali::Import->write_ali_info( $tmp_path, $counts, $args, $pairmasks );

    # >>>>>>>>>>>>>>>>>>>>>>>> MOVE IN PLACE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Temporary files were written above to delay overwriting active files.
    # Here, after everything went well, we move the new ones in place,

    foreach $suff ( $suff1, $suff2 )
    {
        &Common::File::delete_file_if_exists( "$opath.$suff" );
    
        if ( not rename "$tmp_path.$suff", "$opath.$suff" ) {
            &error( qq (Could not rename "$tmp_path.$suff" to "$opath.$suff".) );
        }
    }

    return $dat_rows;
}

sub write_pdl_from_stockholm
{
    # Niels Larsen, January 2006.

    # Reads through a given stockholm formatted file and writes each entry
    # to a separate file in the given directory. The files are named by their 
    # short-ids with .pdl and .info suffixes. The number of files written is 
    # returned. NOTE: each entry is read into memory, this may cause problems
    # for huge entries; for those use write_pdl_from_fasta, which doesnt do
    # this. 

    my ( $class,          # Class name
         $args,           # Settings, e.g. "datatype" => "rna_ali" - OPTIONAL
         $msgs,
         ) = @_;
    
    # Returns an integer. 

    my ( $ifh, $ali, $ifile, $path, $line, %skip_ids, @sids, $params,
         $suff1, $suff2, $dat_rows, $opath, $split_exp, $colbeg, $colend,
         $max_wid, $field );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( ifile opath datatype sid source title ) ], 
            "HR:0" => [ qw ( params ) ],
            "S:0" => [ qw ( sids ) ],
            "AR:1" => [ qw ( suffixes ) ],
        });

    $ifile = $args->ifile;
    $opath = $args->opath;
    $params = $args->params;

    ( $suff1, $suff2 ) = @{ $args->suffixes };

    # >>>>>>>>>>>>>>>>>>>>>>> READ / WRITE ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<

    # Read a whole entry at a time into memory,

    $ifh = &Common::File::get_read_handle( $ifile );
    
    $ali = Ali::Import->read_stockholm_entry( $ifh, $params );

    &Common::File::close_handle( $ifh );

    # Find column widths of short-ids and begin/end numbers,

    foreach $field ( qw ( sids begs ends ) )
    {
        $max_wid = &List::Util::max( map { length $_ } @{ $ali->$field } );
        $ali->$field( [ map { sprintf "%$max_wid"."s", $_ } @{ $ali->$field } ] );
    }

    # Write alignment object to alignment directory in PDL raw format.
    # Pairing mask, if present, ends up in the info file,
            
    $ali = &Ali::Common::pdlify( $ali );
    
    $ali->datatype( $args->datatype );
    $ali->source( $args->source );

    $dat_rows = $ali->max_row + 1;
    
    &Ali::IO::write_pdl( $ali, $opath, $args );
    
    return $dat_rows;
}

sub write_pdl_from_stockholm_1
{
    my ( $class,          # Class name
         $ifile,          # Input stockholm file
         $ofile,          # Output file
         $args,           # Settings, e.g. "datatype" => "rna_ali" - OPTIONAL
         ) = @_;
    
    # Returns an integer. 

    my ( $fh, $ali );

    $args = &Registry::Args::check( $args, { 
        "S:1" => [ qw ( datatype sid source title ) ],
        "S:0" => [ qw ( split_sids ) ],
    });

    $fh = &Common::File::get_read_handle( $ifile );

    $ali = Ali::Import->read_stockholm_entry( $fh, $args );

    # Write alignment object to alignment directory in PDL raw format.
    # Pairing mask, if present, ends up in the info file,
    
    $ali = &Ali::Common::pdlify( $ali );
    
    $ali->datatype( $args->datatype );
    $ali->source( $args->source );
    $ali->title( $args->title );
    $ali->sid( $args->sid );
    
    &Ali::IO::write_pdl( $ali, $ofile, $args );

    &Common::File::close_handle( $fh );

    return $ali->max_row + 1;
}

sub write_rfam_genome_flanks
{
    # Niels Larsen, April 2006.

    # Adds genome flanks to a given list of alignments. These added pieces are
    # flanks are gotten from EMBL by parsing the alignment labels, which are 
    # Rfam specific (they look like ""AJ057347/2545-5959"). 

    my ( $class,            # Package name
         $ifiles,           # Alignment directory path or file list
         $odir,             # Output directory path
         $flanks,           # Flanks size - OPTIONAL, default 2000
         $msgs,             # Messages returned - OPTIONAL
         ) = @_;

    # Returns an integer. 

    my ( $ali_file, $ali, $colbeg, $colend, $col, $row, $file, $name, $sid );

    $flanks ||= 2000;

    &Common::File::create_dir_if_not_exists( $odir );

    foreach $file ( @{ $ifiles } )
    {
        $ali = &Ali::IO::connect_pdl( $file->{"path"} );

        $ali = &Ali::Common::de_pdlify( $ali );
        $ali = &Ali::Import::add_rfam_genome_flanks( $ali, $flanks, $msgs );
        $ali = &Ali::Common::pdlify( $ali );
        
        $colbeg = $ali->orig_colbeg;
        $colend = $ali->orig_colend;
        
        $ali->start_width( $colend - $colbeg + 1 );
        
        $col = int ( ( $colbeg + $colend ) / 2 );
        $row = int ( $ali->max_row / 2 );
        
        $ali->center_col( $col );
        $ali->center_row( $row );
        
        $name = $file->{"name"};
        $name =~ s/_pre\./_flank\./;

        $ali_file = "$odir/$name";
        $ali->file( $ali_file );

        $sid = $name;
        $sid =~ s/\..+$//;

        $ali->sid( $sid );

        &Ali::IO::write_pdl( $ali, $ali_file );
    }

    return scalar @{ $ifiles };
}

sub write_fasta_from_uclust
{
    # Niels Larsen, July 2010.

    # Writes a given uclust multiple-alignments file into fasta format.
    # Returns nothing.

    my ( $ifile,
         $ofile,
        ) = @_;

    # Returns nothing.

    my ( $num, $ifh, $ofh, $line, $id, $seq, $count );

    $count = 0;

    $ifh = &Common::File::get_read_handle( $ifile );
    $ofh = &Common::File::get_write_handle( $ofile );
    
    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ />(\d+)\|[^\|]+\|(.+)/ )
        {
            $num = $1;
            $id = $2;

            $line = <$ifh>;
            
            $ofh->print( ">$id clu_num=$num\n$line" );
        }
        else {
            chomp $line;
            &error( qq (Wrong looking line -> "$line") );
        }
    }

    $ifh->close;
    $ofh->close;

    return;
}

1;

__END__

# sub paint_features
# {
#     # Niels Larsen, May 2007.

#     # Reads all .sims files in a given results directory (res_dir), creates
#     # similarity features of these, loads them into the users own database,
#     # and finally adds a similarity matchh option to the users state file.
#     # All features are painted on the same alignment, and a link is made to 
#     # the system alignment (making it "virtual").

#     my ( $args,
#          $msgs,
#          ) = @_;

#     # Returns nothing.

#     my ( $prefix, $stream, $sims_file, $sims, $sim, $irow, $ali, $stone,
#          $tuples, $ft_menu, $opt, $dbh, $ali_file, $count, $state, $menu, $dir,
#          $file );

#     $args = &Registry::Args::check(
#         $args,
#         {
#             "S:1" => [ qw ( tab_dir res_dir dbpath dbname sid jid itype title method ) ], 
#         });

#     $prefix = $args->res_dir ."/". $args->jid;

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET LINK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # We use existing alignment, but create a link to it in the users
#     # session directory,

#     if ( not -r "$prefix.pdl" )
#     {
#         &Common::File::create_link( $args->dbpath .".pdl", "$prefix.pdl" );
#         &Common::File::create_link( $args->dbpath .".info", "$prefix.info" );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE STREAM FILE <<<<<<<<<<<<<<<<<<<<<<<<

#     $stream = Boulder::Stream->newFh( -out => "$prefix.stream" );

#     foreach $sims_file ( &Common::File::list_files( $args->res_dir, '.sims$' ) )
#     {
#         $sims = &Common::File::eval_file( $sims_file->{"path"} );

#         foreach $sim ( @{ $sims } )
#         {
#             if ( $sim->id2 =~ /:(\d+)$/ ) {
#                 $irow = $1;
#             } else {
#                 &error( qq (Wrong looking match id -> ). $sim->id2 );
#             }

#             $stone = Stone->new(
#                 "ID" => $sim->id2,
#                 "Type" => "subject",
#                 "Score" => 0, 
#                 "Seq_beg" => 0,
#                 "Sim_locs2" => &Common::Util::stringify( $sim->locs2 ),
#                 "Sim_rows" => &Common::Util::stringify( [[ int $irow, int $irow ]] ),
#                 );

#             $stream->print( $stone );
#         }
#     }

#     undef $stream;

#     # >>>>>>>>>>>>>>>>>>>>>>> LOAD SIMILARITY FEATURES <<<<<<<<<<<<<<<<<<<<

#     $dbh = &Common::DB::connect_user( $args->sid );
    
#     $ali_file = &Common::File::get_stats( "$prefix.pdl" );

#     $ft_menu = Ali::Menus->features_menu( [[ "ali_sim_match", 1 ]] );
    
#     # Set method and feature file name for similarities .. this may be 
#     # temporary,
    
#     $opt = $ft_menu->match_option( "name" => "ali_sim_match" );
    
#     $opt->method( $args->method );
#     $opt->ifile( "$prefix.stream" );

#     $count = &Ali::Import::import_features_alis( [ $ali_file ], $ft_menu, {
#         "ft_source" => $args->dbname,
#         "tab_dir" => $args->tab_dir,
#         "database" => $args->sid,
#     }, $msgs, $dbh );

#     &Common::DB::disconnect( $dbh );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>> FEATURE MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Make a default feature menu where the similarities are switched on
#     # and the rest is off - the first most want is to see clearly where the
#     # matches are,

#     $ali = &Ali::IO::connect_pdl( $prefix );

#     $tuples = Ali::Menus->features_tuples_default(
#         {
#             "dbname" => $args->dbname,
#         });

#     unshift @{ $tuples }, [ "ali_sim_match", 1 ];

#     undef $ali;

#     $ft_menu = Ali::Menus->features_menu( $tuples );

#     foreach $opt ( $ft_menu->options )
#     {
#         if ( $opt->name ne "ali_sim_match" ) {
#             $opt->selected( 0 );
#         }
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> STATE FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # The feature menu initializes the state,
    
#     $state = &Ali::State::default_state();

#     $state->{"ali_sid_left_indent"} = "left";        # Left-align short ids
#     $state->{"ali_display_type"} = "characters";     # Show characters 

#     $state->{"ali_features"} = $ft_menu;
        
#     &Common::File::store_file( "$prefix.state", $state );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RESULTS MENU <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Make a menu for the results page with a single option - entries
#     # that match are not individually selectable,

#     $menu = Common::Menu->new( "id" => $args->jid,
#                                "name" => "result_views" );

#     $opt = Common::Option->new();
        
#     $opt->id( 0 );
#     $opt->sid( $args->sid );
#     $opt->title( $args->title );
#     $opt->datatype( &Common::Types::seq_to_ali( $args->itype ) );
#     $opt->input( "Analyses/". $args->jid ."/". $args->jid );
    
#     $menu->options( [ $opt ] );

#     $file = $args->res_dir ."/results_menu.yaml";

#     &Common::File::write_yaml( $file, $menu );

#     return $count;
# }

# sub append_tabfiles
# {
#     # Niels Larsen, October 2005.

#     # Appends fields in a given alignment object to table files with 
#     # the same fields as those in Ali::Schema::relational. A hash of 
#     # file handles are given, where the keys are - and must be - the
#     # same as defined in the schema.

#     my ( $tabfhs,       # Hash of file handles
#          $ali,          # Alignment object
#          ) = @_;

#     my ( $line, @lines, $ali_id, $ft_id, $row, $seq_id, $ft, $col_range,
#          $row_range, $area );

#     $ali_id = $ali->id;

#     # Annotation, 

#     $line = ( join "\t", ( $ali_id, $ali->sid, $ali->title, $ali->source, $ali->datatype,
#                            $ali->authors || "", $ali->desc || "", $ali->url || "" ) ) ."\n";

#     $tabfhs->{"ali_annotation"}->print( $line );

#     # References, 

#     # TODO

#     # Seqs,

#     for ( $row = 0; $row <= $ali->max_row; $row++ )
#     {
#         $seq_id = $ali->sid_string( $row );
#         $seq_id =~ s/^\s+//;
#         $seq_id =~ s/\s+$//;

#         $line = ( join "\t", ( $ali_id, $seq_id, $row ) ) ."\n";

#         $tabfhs->{"ali_seqs"}->print( $line );
#     }

#     # Features, 

#     foreach $ft ( @{ $ali->features } )
#     {
#         $ft_id = $ft->id;

#         $line = ( join "\t", ( $ali_id, $ft_id, $ft->source || "", $ft->type || "", 
#                                $ft->score || "", $ft->desc || "" ) ) ."\n";

#         $tabfhs->{"ali_features"}->print( $line );

#         foreach $area ( @{ $ft->areas } )
#         {
#             $line = ( join "\t", ( $ali_id, $ft_id, @{ $area } ) ) ."\n";
            
#             $tabfhs->{"ali_feature_pos"}->print( $line );
#         }

# #         foreach $col_range ( @{ $ft->cols } )
# #         {
# #             foreach $row_range ( @{ $ft->rows } )
# #             {
# #                 $line = ( join "\t", ( $ali_id, $ft_id, 
# #                                        $col_range->[0], $col_range->[1],
# #                                        $row_range->[0], $row_range->[1] ) ) ."\n";
                
# #                 $tabfhs->{"ali_feature_pos"}->print( $line );
# #             }
# #         }
#     }

#     return;
# }

# sub measure_stockholm
# {
#     # Niels Larsen, September 2005.

#     # Reads a file of stockholm-formatted alignment entries and returns a 
#     # hash of hashes where keys are alignment ids and values are hashes 
#     # with these keys,
#     # 
#     # ali_id
#     # seq_count
#     # sid_length_max
#     # seq_length_max
#     # has_pairing_mask
#     # 

#     my ( $class,      # Class, e.g. "RNA::Ali"
#          $file,       # Input fasta file
#          $toget,      # List of entry ids to include
#          $toskip,     # List of entry ids to skip
#          ) = @_;

#     # Returns a list.

#     my ( $fh, $line, $ali_id, $sidlen, $seqlen, $seqnum, $maxsidlen, %stats,
#          $maxseqlen, $i, @seqlens, $count, $hasmask );

#     $fh = &Common::File::get_read_handle( $file );

#     $count = 0;

#     while ( defined ( $line = <$fh> ) )
#     {
#         $line = <$fh>;        # read blank line
#         $line = <$fh>;        # read AC line

#         $seqnum = 0;
#         @seqlens = ();
#         $maxsidlen = 0;
#         $maxseqlen = 0;

#         while ( $line =~ /^\#=GF ([A-Z]{2,2}) +(.+)/ )
#         {
#             if ( $1 eq "SQ" ) {
#                 $seqnum = $2;
#             } elsif ( $1 eq "ID" ) {
#                 $ali_id = $2;
#             }

#             $line = <$fh>;
#         }

#         if ( $toget and not grep { $ali_id =~ /$_/ } @{ $toget } or
#              $toskip and grep { $ali_id =~ /$_/ } @{ $toskip } )
#         {
#             while ( $line !~ /^\/\// )
#             {
#                 $line = <$fh>;
#             }
#         }
#         else
#         {
#             $hasmask = 0;

#             while ( $line !~ /^\/\// )
#             {
#                 $line = <$fh>;
                
#                 for ( $i = 0; $i < $seqnum; $i++ )
#                 {
#                     if ( $line =~ /^(\S+) +(\S+)$/ )
#                     {
#                         $sidlen = length $1;
#                         $seqlens[$i] += length $2;
#                     }
                    
#                     $maxsidlen = $sidlen if $sidlen > $maxsidlen;
                    
#                     $line = <$fh>;
#                 }
                
#                 if ( $line =~ /^\#=GC SS_cons/ ) 
#                 {
#                     $line = <$fh>;
#                     $hasmask = 1;
#                 }
#             }

#             $maxseqlen = &List::Util::max( @seqlens );

#             $stats{ $ali_id } = 
#             {
#                 "ali_id" => $ali_id,
#                 "seq_count" => $seqnum,
#                 "sid_length_max" => $maxsidlen, 
#                 "seq_length_max" => $maxseqlen,
#                 "has_pairing_mask" => $hasmask,
#             };
            
#             $count += 1;
#         }
#     }
    
#     &Common::File::close_handle( $fh );

#     return wantarray ? %stats : \%stats;
# }


# sub pair_bases
# {
#     # Niels Larsen, January 2006.

#     # Maps where the pairs and mispairs are between two given base 
#     # character strings (given as lists). The routine starts at the 
#     # beginning of the first string and the end of the second (like
#     # in a helix) and moves until one of the ends. This map is a 
#     # list of [ 5' beg, 5' end, 3' beg, 3' end ]. The third argument
#     # is a pairing matrix used to tell which bases form pairs. 

#     my ( $chars5,       # Upstream base string
#          $chars3,       # Downstream base string
#          $is_pair,      # Pairing matrix 
#          ) = @_;

#     # Returns a list. 

#     my ( $ch5, $ch3, $imax, $beg5, $end5, $beg3, $end3, $i, $j, @pos5, @pos3 );

#     $imax = ( length $chars5 ) - 1;

#     $i = 0;
#     $j = ( length $chars3 ) - 1;

#     $beg5 = $i;
#     $end3 = $j;

#     while ( $i <= $imax and $j >= 0 )
#     {
#         $ch5 = substr $chars5, $i, 1;
#         $ch3 = substr $chars3, $j, 1;

#         if ( $is_pair->{ $ch5 }->{ $ch3 } )
#         {
#             $end5 = $i;
#             $beg3 = $j;
#         }
#         else
#         {
#             if ( defined $end5 ) 
#             {
#                 push @pos5, [ $beg5, $end5 ];
#                 push @pos3, [ $beg3, $end3 ];

#                 undef $end5;
#                 undef $beg3;
#             }

#             $beg5 = $i + 1;
#             $end3 = $j - 1;
#         }

#         $i += 1;
#         $j -= 1;
#     }
    
#     if ( defined $end5 ) 
#     {
#         push @pos5, [ $beg5, $end5 ];
#         push @pos3, [ $beg3, $end3 ];
#     }

#     return ( \@pos5, \@pos3 );
# }
    
# sub p_random_pair
# {
#     # Niels Larsen, April 2005.

#     # Calculates the probability that a pair occurs by chance, given two
#     # hashes with base counts. Base characters are keys, their numbers are
#     # values. 

#     my ( $sums1,      # Base counts
#          $sums2,      # Base counts
#          $is_pair,    # Pairing hash
#          ) = @_;

#     # Returns a number.

#     my ( $base1, $base2, $sum1, $sum2, $total1, $total2, $p );

#     map { $total1 += $_ } values %{ $sums1 };
#     map { $total2 += $_ } values %{ $sums2 };

#     $p = 0;

#     foreach $base1 ( keys %{ $sums1 } )
#     {
#         $sum1 = $sums1->{ $base1 };

#         foreach $base2 ( keys %{ $sums2 } )
#         {
#             if ( $is_pair->{ $base1 }->{ $base2 } )
#             {
#                 $p += ( $sum1 / $total1 ) * ( $sums2->{ $base2 } / $total2 );
#             }
#         }
#     }
            
#     return $p;
# }


#             if ( $mask =~ /[()]/ )
#             {
# #                $ldiff = &RNA::Import::stem_length_difference( $mask, $msgs );
# #                $shift = &RNA::Import::stem_position_shift( $mask, $msgs );

#                 if ( $mask =~ /\((\.+)\)/ )
#                 {
#                     # Put
#                    $loop = $1;
#                     $len5 = int ( (length $loop) / 2 );
#                     $len3 = (length $loop) - $len5;
#                     $loop = ("<" x $len5) . (">" x $len3);

#                     $mask =~ s/\((\.+)\)/\($loop\)/;
#                     &dump( $mask );

#                     ( $mask, $deltag ) = RNA::fold( $seq, $mask );

#                     &dump( $mask );
# #                    &dump( "delta-G, ldiff, shift = $deltag, $ldiff, $shift" );
#                 }
#             }
#             else {
#                 $deltag = 0;
#             }
