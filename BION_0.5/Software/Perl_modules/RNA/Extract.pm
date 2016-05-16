package RNA::Extract;     #  -*- perl -*-

# Routines that extract RNAs. 

use strict;
use warnings FATAL => qw ( all );

use IO::File;
use Cwd;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

{
    local $SIG{__DIE__};

    require Bio::Seq;
    require Bio::SeqIO;
    require Bio::DB::GenBank;
    require Bio::Index::Fasta;
    require Bio::Index::EMBL;
    require Bio::Index::Swissprot;
    require Bio::Index::GenBank;
    require Bio::Index::Abstract;
}

@EXPORT_OK = qw (
                 &check_arguments
                 &extract_ssu_ali
                 &index_ssu_entries
                 &read_seed_ids
                 &read_seed_org_name
                 &read_seed_names
                 &read_ssu_entries
                 &read_ssu_entry
                 &save_ssu_sequences
                 &select_entries_by_name
                  );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Util;

use Seq::Run;
use Seq::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_arguments
{
    # Niels Larsen, July 2004.

    # Validates the arguments needed by the match_rna routine. It 
    # checks that word length is reasonable, that files exist that
    # must, adds defaults and expands file names to their absolute
    # paths. If errors found, program stops here. 

    my ( $cl_args,    # Command line argument hash
         ) = @_;

    # Returns a hash. 

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

sub extract_ssu_ali
{
    # Niels Larsen, July 2004.

    # Given a list of SEED organism ids, finds corresponding small 
    # subunit RNAs in a file of aligned (ssu RNA) sequences. Where a
    # single aligned sequence cannot be found by name matching, a number
    # of candidate sequences are compared with the genome sequence and
    # that with the highest score selected. The output is a file with 
    # aligned sequences in fasta format with SEED id, alignment id and
    # match percentage in the header. 

    my ( $cl_args,    # Command line argument hash
         ) = @_;

    # Returns nothing. 

    my ( @ssu_info, @seed_ids, $str, @entries, $q_fh,
         $entry, $s_fh, $seed_id, $seed_name, %seed_names, $silent,
         %ssu_index, $ssu_seqs_file, $ssu_ali_file, $ali_fh, $out_fh,
         $query_file, $begpos, $endpos, $seq_fh, $results, $length,
         $pct, $chunk, @matches, $match, $score, $ssu_id, $count,
         $subject_file, $i, $contig_id, $contig_seq, $seq, $seqlen,
         $contig_found, $log_fh, $log, $ssu_to_seed, $id );

    $ssu_ali_file = $cl_args->{"ali"};
    $ssu_seqs_file = $cl_args->{"temp"}."/ssu_seqs.fasta";
    $query_file = $cl_args->{"temp"} ."/query.fasta";
    $subject_file = $cl_args->{"temp"} ."/subject.fasta";
    $silent = $cl_args->{"silent"};

    # >>>>>>>>>>>>>>>>>>>>>> PREPROCESSING <<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Reading SEED organism id list ... ) ) if not $silent;
    @seed_ids = &RNA::Extract::read_seed_ids( $cl_args->{"sids"} );
    &echo_green( qq (done\n) ) if not $silent;

    &echo( qq (   Reading SEED organism names ... ) ) if not $silent;

    foreach $seed_id ( @seed_ids )
    {
        $seed_name = &RNA::Extract::read_seed_org_name( "$cl_args->{'orgs'}/$seed_id/GENOME" );
        $seed_names{ $seed_id } = $seed_name;
    }
    
    &echo_green( qq (done\n) ) if not $silent;
 
    &echo( qq (   Reading SSU entry info (patience) ... ) ) if not $silent;
    @ssu_info = &RNA::Extract::read_ssu_entries( $ssu_ali_file, 0 );
    &echo_green( qq (done\n) ) if not $silent;

    &echo( qq (   Saving ungapped rRNAs (patience) ... ) ) if not $silent;
    &RNA::Extract::save_ssu_sequences( $ssu_ali_file, $ssu_seqs_file );
    &echo_green( qq (done\n) ) if not $silent;

    &echo( qq (   Indexing ungapped rRNAs ... ) ) if not $silent;
    %ssu_index = &RNA::Extract::index_ssu_entries( $ssu_seqs_file );
    &echo_green( qq (done\n) ) if not $silent;

    # >>>>>>>>>>>>>>>>>>>>> SELECT ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<

    # If only one match by name, then use that. If more than one, blast
    # them all against the genome in question and pick the one with the
    # highest bit-score,

    foreach $seed_id ( @seed_ids )
    {
        $seed_name = $seed_names{ $seed_id };

        &echo( "   $seed_name ... " ) if not $silent;

        @entries = &RNA::Extract::select_entries_by_name( $seed_name, \@ssu_info );

        # >>>>>>>>>>>>>>>>>>>>>> NAME MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( @entries )
        {
            # Create query file. It contains the entries that were selected
            # by name,

            $seq_fh = &Common::File::get_read_handle( $ssu_seqs_file );

            &Common::File::delete_file_if_exists( $query_file );
            $q_fh = &Common::File::get_write_handle( $query_file );
            
            foreach $entry ( @entries )
            {
                ( $begpos, $endpos ) = @{ $ssu_index{ $entry->{"id"} } }[ 0..1 ];
                $chunk = &Common::File::seek_file( $seq_fh, $begpos, ($endpos-$begpos+1) );
                
                $q_fh->print( $chunk );
            }
            
            &Common::File::close_handle( $q_fh );

            # Create subject file. Link to seed contig file,

            &Common::File::delete_file_if_exists( $subject_file );
            &Common::File::create_link( $cl_args->{"orgs"} ."/$seed_id/contigs", $subject_file );
        }

        # >>>>>>>>>>>>>>>>>>>>>> NO NAME MATCHES <<<<<<<<<<<<<<<<<<<<<<<<

        # With no clue which RNA gives good match, we could blast all of 
        # them against the whole genome. But thats too slow. Instead we 
        # cut out the genome piece that includes the RNA and then use 
        # that as query sequence. The subject sequences are now all the 
        # SSU RNA sequences. 

        else
        {
            # Save query sample set,
            
            $q_fh = &Common::File::get_write_handle( $query_file );

            for ( $i = 0; $i <= $#ssu_info; $i += 100 )
            {
                ( $begpos, $endpos ) = @{ $ssu_index{ $ssu_info[$i]->{"id"} } }[ 0..1 ];
                $chunk = &Common::File::seek_file( $seq_fh, $begpos, ($endpos-$begpos+1) );

                $q_fh->print( $chunk );
            }

            &Common::File::close_handle( $q_fh );
            
            &Common::File::delete_file_if_exists( $subject_file );
            &Common::File::create_link( $cl_args->{"orgs"} ."/$seed_id/contigs", $subject_file );

            # Find best region in genome,

            &Seq::IO::index_blastn( $subject_file, $subject_file );

            @matches = &Seq::Run::run_blastn_local( $query_file, $subject_file,
                                                    { 
                                                        "e" => 1e-70, 
                                                        "m" => 8,
                                                    });
            
            &Common::File::delete_file( $query_file );
            &Common::File::delete_file( $subject_file );
            &Common::File::delete_file( $subject_file .".nhr");
            &Common::File::delete_file( $subject_file .".nin");
            &Common::File::delete_file( $subject_file .".nsq");

            # If there are matches, then cut out a reasonable chunk that will 
            # include the RNA and save it as query file. Subject file becomes
            # all the SSU RNA sequences. Without this upside-down maneuver 
            # blast will never finish,

            if ( @matches )
            {
                @matches = sort { $a->[11] <=> $b->[11] } @matches;

                $contig_id = $matches[-1]->[1];
                
                &Common::File::create_link( $cl_args->{"orgs"} ."/$seed_id/contigs", $subject_file );
                $s_fh = &Common::File::get_read_handle( $subject_file );
            
                while ( $entry = bless &Seq::IO::read_seq_fasta( $s_fh, undef, 1 ), "Seq::Common" )
                {
                    $id = &Common::Seq::get_id( $entry );

                    if ( $id eq $contig_id )
                    {
                        $contig_found = 1;
                        $seq = &Common::Seq::get_seq( $entry );
                        last;
                    }
                }

                $s_fh = &Common::File::close_handle( $s_fh );
                
                if ( not $contig_found ) {
                    &error( qq (Contig id not found -> "$contig_id") );
                    exit;
                }

                $begpos = &Common::Util::max( 0, $matches[-1]->[8] - 1500 );
                $endpos = &Common::Util::min( (length $seq) - 1, $matches[-1]->[9] + 1500 );
                $contig_seq = substr $seq, $begpos, $endpos-$begpos+1;
                
                $q_fh = &Common::File::get_write_handle( $query_file );
                $q_fh->print( ">$contig_id\n$contig_seq\n" );
                &Common::File::close_handle( $q_fh );

                &Common::File::delete_file_if_exists( $subject_file );
                &Common::File::create_link( $ssu_seqs_file, $subject_file );
            }
            else
            {
                &echo_red( "NO MATCH\n" ) if not $silent;
                next;
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> RUN BLAST <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &Seq::IO::index_blastn( $subject_file, $subject_file );

        @matches = &Seq::Run::run_blastn_local( $query_file, $subject_file,
                                                { 
                                                    "e" => 1e-70, 
                                                    "m" => 8,
                                                });
        
        # >>>>>>>>>>>>>>>>>>>> COLLECT MATCH RESULTS <<<<<<<<<<<<<<<<<<<<<

        if ( @matches )
        {
            @matches = sort { $a->[11] <=> $b->[11] } @matches;

            if ( @entries ) {
                $ssu_id = $matches[-1]->[0];
                $length = $matches[-1]->[3];
            } else {
                $ssu_id = $matches[-1]->[1];
                $length = $matches[-1]->[7];
            }
                
            $pct = $matches[-1]->[2];
            
            $results->{ $seed_id } =
            {
                "pct" => $pct,
                "length" => $length,
                "seed_id" => $seed_name || "",
                "ssu_id" => $ssu_id || "",
            };

            if ( $pct >= 97 and $length >= 1000 ) {
                &echo_green( "ok\n" ) if not $silent;
            } else {
                &echo_yellow( "$ssu_id, $pct%, $length\n" ) if not $silent;
            }
        } 
        else
        {
            &echo_red( "NO MATCH\n" ) if not $silent;
        }
        
        # Delete temporary files, 
        
        &Common::File::delete_file( $subject_file );
        &Common::File::delete_file( $subject_file .".nhr");
        &Common::File::delete_file( $subject_file .".nin");
        &Common::File::delete_file( $subject_file .".nsq");
        
        &Common::File::delete_file( $query_file );        
    }

    # >>>>>>>>>>>>>>>>>> PRINT ALIGNED SEQUENCES <<<<<<<<<<<<<<<<<<<<

    if ( defined $cl_args->{"out"} )
    {
        &echo( qq (   Printing aligned sequences ... ) ) if not $silent;

        $ali_fh = &Common::File::get_read_handle( $cl_args->{'ali'} );

        if ( $cl_args->{"out"} ) {
            $out_fh = &Common::File::get_write_handle( $cl_args->{'out'} );
        }

        foreach $seed_id ( @seed_ids )
        {
            if ( exists $results->{ $seed_id } )
            {
                $ssu_id = $results->{ $seed_id }->{"ssu_id"};

                push @{ $ssu_to_seed->{ $ssu_id } }, $seed_id;
            }
        }

         while ( $entry = &RNA::Extract::read_ssu_entry( $ali_fh, 1 ) )
         {
            $ssu_id = $entry->{"id"};

            if ( exists $ssu_to_seed->{ $ssu_id } )
            {
                foreach $seed_id ( @{ $ssu_to_seed->{ $ssu_id } } )
                {
                    if ( $seed_id ) 
                    {
                        if ( $out_fh ) {
                            print $out_fh ">$ssu_id $seed_id\n$entry->{'seq'}\n";
                        } else {
                            print ">$ssu_id $seed_id\n$entry->{'seq'}\n";
                        }
                    }
                }
             }
         }
        
        &Common::File::close_handle( $ali_fh );
        &Common::File::close_handle( $out_fh ) if defined $out_fh;

         &echo_green( qq (done\n) ) if not $silent;
    }

    # >>>>>>>>>>>>>>>>>>>>>>> PRINT LOG FILE <<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $cl_args->{"log"} )
    {
        &echo( qq (   Printing log file ... ) ) if not $silent;

        $log_fh = &Common::File::get_write_handle( $cl_args->{'log'} );

        foreach $seed_id ( @seed_ids )
        {
            $seed_name = $seed_names{ $seed_id };

            if ( exists $results->{ $seed_id } )
            {
                $log = $results->{ $seed_id };
                $log_fh->print( "$log->{'ssu_id'}\t$log->{'pct'}\t$log->{'length'}\t$seed_id\t$seed_name\n");
            }
            else {
                $log_fh->print( "\t\t\t$seed_id\t$seed_name\n");
            }
        }

        &Common::File::close_handle( $log_fh ) if defined $log_fh;
         &echo_green( qq (done\n) ) if not $silent;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> MOP UP <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::File::delete_file_if_exists( $query_file );
    &Common::File::delete_file_if_exists( $subject_file );
    &Common::File::delete_file_if_exists( $subject_file .".nhr");
    &Common::File::delete_file_if_exists( $subject_file .".nin");
    &Common::File::delete_file_if_exists( $subject_file .".nsq");
    &Common::File::delete_file_if_exists( $subject_file .".log");
    &Common::File::delete_file_if_exists( $ssu_seqs_file );

    return;
}

sub select_entries_by_name
{
    # Niels Larsen, July 2004.

    # Finds the elements of the given list that shows the best 
    # name match to a given name. 

    my ( $name,   # Database handle
         $list,   # Molecule info, list of hashes
         ) = @_;

    # Returns a list.

    my ( @matches, @list, $match, $genus, $species, @words );

    @list = @{ $list };

    # By genus first, return if <= one match,

    $genus = ( split " ", $name )[0];

    @matches = grep { $_->{"name"} =~ /^$genus/i } @list;

    if ( scalar @matches == 1 ) {
        return wantarray ? @matches : \@matches;
    } elsif ( not @matches ) {
        return;
    }

    @list = @matches;

    # Filter by species next, return if <= one match,

    $species = ( split " ", $name )[1];
    $species =~ s/sp\.?//;

    if ( $species )
    {
        @matches = grep { $_->{"name"} =~ /$species/i } @list;

        if ( scalar @matches == 1 ) {
            return wantarray ? @matches : \@matches;
        } elsif ( not @matches ) {
            return wantarray ? @list : \@list;
        }
    }

    # Filter by strain or what else is left,

#    @words = ( split " ", $name )[2..-1];
#    @words = grep { $_ !~ /\S\./ } @words;

    # Finally if word matching did not give a single match, take
    # the entry with the longest sequence,

#     @list = reverse sort { $a->{"seqlen"} <=> $b->{"seqlen"} } @list;

    return wantarray ? @matches : \@matches;
}

sub read_ssu_entry
{
    # Niels Larsen, July 2004.

    # Collects id, organism name, sequence and sequence length 
    # from a genbank formatted file of aligned ssu rna entries. 
    # The result is a list of hashes where each hash has the 
    # keys "id", "name", "seqlen". 
    
    my ( $fh,        # File handle
         $seqflag,   # Sequence flag
         ) = @_;

    # Returns a list.

    my ( $entry, $id, $line, $count );

    $line = <$fh>;
    return if not defined $line;

    while ( $line !~ /^LOCUS/ )
    {
        $line = <$fh>;
        return if not defined $line;
    }

    $line =~ /^LOCUS\s+(\S+)/;
    $entry->{"id"} = $1;

    while ( $line !~ /^  ORGANISM/ ) {
        $line = <$fh>;
    }

    $line =~ /^  ORGANISM\s+(.+)/;
    $entry->{"name"} = $1;
        
    while ( $line !~ /^ORIGIN/ ) {
        $line = <$fh>;
    }
    
    while ( defined ( $line = <$fh> ) and $line !~ /^\/\// )
    {
        $count = $line =~ tr/AUTCG/AUTCG/;
        
        if ( $line )
        {
            $entry->{"seqlen"} += $count;

            if ( $seqflag )
            {
                $line =~ s/[0-9\s]+//g;
                $entry->{"seq"} .= $line;
            }
        }
    }

    return $entry;
}

sub read_ssu_entries
{
    # Niels Larsen, July 2004.

    # Collects id, organism name, sequence and sequence length 
    # from a genbank formatted file of aligned ssu rna entries. 
    # The result is a list of hashes where each hash has the 
    # keys "id", "name", "seqlen". 
    
    my ( $path,     # File path
         $seqflag,  # Sequence flag
         ) = @_;

    # Returns a list.

    my ( $fh, @entries, $entry, $id, $line, $count );

    $fh = &Common::File::get_read_handle( $path );

    while ( $entry = &RNA::Extract::read_ssu_entry( $fh, $seqflag ) )
    {
        push @entries, $entry;
    }

    &Common::File::close_handle( $fh );

    return wantarray ? @entries : \@entries;
}

sub index_ssu_entries
{
    my ( $seqfile,     # Un-gapped sequence file
         ) = @_;
    
    my ( $seq_fh, %index, $head, $seq, $sid, $beg, $end );

    $seq_fh = &Common::File::get_read_handle( $seqfile );

    $beg = 0;
    $end = 0;

    while ( defined ( $head = <$seq_fh> ) )
    {
        $head =~ />(.+)\n$/; 
        $sid = $1;

        $end += length $head;

        $seq = <$seq_fh>;
        $end += length $seq;

        $index{ $sid } = [ $beg, $end-1 ];

        $beg = $end;
    }

    &Common::File::close_handle( $seq_fh );

    return wantarray ? %index : \%index;
}

sub save_ssu_sequences
{
    my ( $alifile,     # Gapped sequence file
         $seqfile,     # Un-gapped sequence file
         ) = @_;
    
    my ( $ali_fh, $seq_fh, %index, $entry, $id, $line, $count );

    $ali_fh = &Common::File::get_read_handle( $alifile );
    $seq_fh = &Common::File::get_write_handle( $seqfile );

    while ( $entry = &RNA::Extract::read_ssu_entry( $ali_fh, 1 ) )
    {
        $entry->{"seq"} =~ tr/-.~//d;

        $seq_fh->print( ">$entry->{'id'}\n$entry->{'seq'}\n" );
    }

    &Common::File::close_handle( $ali_fh );
    &Common::File::close_handle( $seq_fh );

    return wantarray ? %index : \%index;
}

sub read_seed_ids
{
    my ( $path,
         ) = @_;

    my ( $fh, @ids, $line );

    $fh = &Common::File::get_read_handle( $path );
    
    while ( defined ( $line = <$fh> ) )
    {
        push @ids, ( split "\t", $line )[0];
    }

    &Common::File::close_handle( $fh );

    return wantarray ? @ids : \@ids;
}

sub read_seed_org_name
{
    my ( $path,
         ) = @_;

    my ( $fh, $name );

    $fh = &Common::File::get_read_handle( $path );

    $name = <$fh>;

    &Common::File::close_handle( $fh );

    $name =~ s/\s*//;
    $name =~ s/\s*$//;

    return $name;
}

sub read_seed_names
{
    my ( $path,
         ) = @_;

    my ( $fh, @names, $line );

    $fh = &Common::File::get_read_handle( $path );
    
    while ( defined ( $line = <$fh> ) )
    {
        push @names, ( split "\t", $line )[1];
    }

    &Common::File::close_handle( $fh );

    return wantarray ? @names : \@names;
}

1;
    
__END__
