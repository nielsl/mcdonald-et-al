package Sims::Import;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that create similarity lists, returned on put on file. They 
# run programs and routines that parse their results, and then emit 
# objects like this,
# 
#  bless( {
#    'id1' => 'query_name',
#    'locs1' => '[[2,5],[],[7,8]]',
#    'frame1' => '1',
#    'frame2' => '-1',
#    'id2' => 'subject_name',
#    'score' => '5',
#    'locs2' => '[[4,5],[6,6],[7,10]]'
#  }, 'Sims::Common' ),
# 
# Id1 and id2 identifies the query and subject sequence. Locs1 and locs2
# specify where the matches between them occur: numbers must all increase,
# but each range may have different length, including zero; the numbering
# is that of the actual input sequences, not in complemented sequences 
# for example (the calling routines will handle the flipping). Frame1 and 
# frame2 specify which frame (1,2,3 for proteins, 1 and -1 for DNA/RNA)
# the match is in. Score is a positive number. 

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use XML::Simple;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Names;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &blast_tabular_to_sims
                 &create_locs1
                 &create_sims
                 &create_sims_single
                 &import_seqs_missing
                 &_locs_from_blast_ali_strings
                 &read_ids_from_blast_bioperl
                 &read_ids_from_blast_report
                 &read_ids_from_blast_tabular
                 &read_ids_from_blast_xml
                 &read_ids_from_patscan
                 &_read_sims_from_blast_table
                 &read_sims_from_blast_table_local
                 &read_sims_from_blast_table_ncbi
                 &read_sims_from_blast_xml_local
                 &read_sims_from_blast_xml_ncbi
                 &_read_sims_from_blast_xml
                 &read_sims_from_mview
                 &read_sims_from_patscan
                 &simrank_to_sims
                 &split_blast_report
                 &split_blast_tabular
                 &split_blast_xml
                 &swap_gis_with_accs
                 &write_fasta_from_blast_report
                 );

use Seq::Run;
use Seq::Common;
use Bio::SearchIO;
use RNA::Import;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub blast_tabular_to_sims
{
    # Niels Larsen, November 2007.

    my ( $infile,
         $outfile,
         $db1,
         $db2,
         ) = @_;

    my ( $ifh, $ofh, $line, @line, @row, $count );

    $db1 ||= "";
    $db2 ||= "";

    $ifh = &Common::File::get_read_handle( $infile );
    $ofh = &Common::File::get_write_handle( $outfile );

    $count = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        chomp $line;
        @line = split "\t", $line;
        
        #         db1  entry1   beg1    end1    db2  entry2   beg2    end2    pct
        @row = ( $db1, $line[0], $line[6], $line[7], $db2, $line[1], $line[8], $line[9], $line[2] );

        $ofh->print( (join "\t", @row) ."\n" );
        $count += 1;
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    return $count;
}

sub create_locs1
{
    # Niels Larsen, January 2008.

    # Creates the locs1 coordinates for a list of similarities. The locs1 field 
    # can be missing when there is no query sequence to directly take query locations
    # from. This routine makes them up by creating locs1 coordinates that exactly 
    # accomodates all the locs2 coordinates. Returns a list of updated similarities.

    my ( $sims,       # List of similarities
        ) = @_;

    # Returns a list. 

    my ( $sim, @lens, $hitmax, $count, $id, @locs1, @locs2, $loc, $len, $i, 
         @offsets, $offset, $sum );

    $hitmax = scalar @{ $sims->[0]->locs2 };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $sim ( @{ $sims } )
    {
        if ( exists $sim->{"locs1"} )
        {
            $id = $sim->id2;
            &error( qq (Locs1 is set for id $id -> $sim->{"locs1"}) );
        }

        $count = scalar @{ $sim->locs2 };

        if ( $hitmax != $count )
        {
            $id = $sim->id2;
            &error( qq (First element has $hitmax hits, but $id has $count) );
        }
    }

    @lens = (0) x $hitmax;

    foreach $sim ( @{ $sims } )
    {
        @locs2 = @{ $sim->locs2 };

        if ( $sim->frame2 < 0 )        {
            @locs2 = @{ &Seq::Common::reverse_locs( \@locs2 ) };
        }

        for ( $i = 0; $i <= $#lens; $i++ )
        {
            $loc = $locs2[$i];
            $len = abs ( $loc->[1] - $loc->[0] ) + 1;

            if ( $len > $lens[$i] ) {
                $lens[$i] = $len;
            }
        }
    }

    $sum = 0;

    foreach $len ( @lens )
    {
        $sum += $len;
        push @offsets, $sum - $len;
    }

    foreach $sim ( @{ $sims } )
    {
        $sim->frame1( 1 );
        
        @locs1 = ();
        @locs2 = @{ $sim->locs2 };

        if ( $sim->frame2 < 0 )        {
            @locs2 = @{ &Seq::Common::reverse_locs( \@locs2 ) };
        }

        $i = 0;

        foreach $loc ( @locs2 )
        {
            $offset = $offsets[$i];
            push @locs1, [ $offset, $offset + abs ( $loc->[1] - $loc->[0] ) ];
            $i += 1;
        }

        $sim->locs1( \@locs1 );
    }

    return wantarray ? @{ $sims } : $sims;
}

sub create_sims
{
    # Niels Larsen, May 2007.

    # Creates sequence similarites on an input file, processing the sequences 
    # one by one. When searches produce matches, a .sims file is saved and the
    # corresponding query sequence is kept (.seq). Returns the number of 
    # matching query sequences.

    my ( $args,         # Arguments
         $msgs,         # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns an integer.

    my ( @i_files, $i_file, $sims, $i_format, @o_files, $o_file );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( run_method parse_method ifile iformat dbpath ),
                   qw ( dbtype dbformat oprefix oformat title ) ],
        "HR:1" => [ qw ( pre_params params post_params ) ],
    });

    if ( -d $args->ifile ) 
    {
        @i_files = map { $_->{"path"} } &Common::File::list_all( $args->ifile, '.patscan$' );
    }
    else
    {
        $i_format = $args->iformat;
        $i_file = $args->oprefix .".$i_format";

        # Link to input file from upload area, 
        
        &Common::File::create_link_if_not_exists( $args->ifile, $i_file );
        
        # Trim all ids to length 15 and substitute blanks with "_",
        
        if ( $args->pre_params->{"trim_ids"} ) {
            &Seq::IO::trim_fasta_ids( $i_file, 15 );
        }
        
        # Split into single-entry fasta files,
        
        if ( $args->pre_params->{"split_input"} )
        {
            @i_files = &Seq::Convert::divide_seqs_fasta( $i_file, $args->oprefix, ".$i_format" );
            &Common::File::delete_file( $i_file );
        }
        else {
            @i_files = $i_file;
        }
    }

    # Process each query sequence: if it matches, create a .sims file and 
    # a single-entry fasta file with the query sequence in. 

    foreach $i_file ( @i_files )
    {
        $o_file = &Common::Names::replace_suffix( $i_file, ".". $args->oformat );

        $sims = &Sims::Import::create_sims_single({
            "run_method" => $args->run_method,
            "parse_method" => $args->parse_method,
            "ifile" => $i_file,
            "dbpath" => $args->dbpath,
            "dbtype" => $args->dbtype,
            "dbformat" => $args->dbformat,
            "ofile" => $o_file,
            "title" => $args->title,
            "pre_params" => $args->pre_params,
            "params" => $args->params,
            "post_params" => $args->post_params,
        }, $msgs );

        &Common::File::delete_file( $o_file );

        if ( $sims and @{ $sims } ) 
        {
            $o_file = &Common::Names::replace_suffix( $i_file, ".sims" );

            &Common::File::dump_file( $o_file, $sims );
            push @o_files, $o_file;
        }
    }

    return wantarray ? @o_files : \@o_files;
}

sub create_sims_single
{
    # Niels Larsen, May 2007.

    # Creates similarities between a single item and a set of items. It runs a 
    # routine the name of which is passed as argument, and sequence and a set. The result
    # is returned as a list.

    my ( $args,
         $msgs,
         ) = @_;

    # Returns a list or nothing.

    my ( $run_method, $sims, $parse_method, $db );
    
    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( run_method ifile ofile ) ],
        "S:0" => [ qw ( dbname dbpath dbtype dbformat title parse_method ) ],
        "HR:0" => [ qw ( pre_params params post_params ) ],
    });

    &Common::File::delete_file_if_exists( $args->ofile );
        
    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE MATCH FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This starts methods that create matches, such as blast. 

    $run_method = $args->run_method;

    if ( not -e $args->ofile )
    {
        $args->pre_params( {} ) if not defined $args->pre_params;
        $args->params( {} ) if not defined $args->params;
        $args->post_params( {} ) if not defined $args->post_params;

        if ( $args->dbname )
        {
            # >>>>>>>>>>>>>>>>>>>>>> DATASETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            &Seq::IO::search_db(
                {
                    "run_method" => $args->run_method,
                    "ifile" => $args->ifile,
                    "dbname" => $args->dbname,
                    "ofile" => $args->ofile,
                    "pre_params" => $args->pre_params,
                    "params" => $args->params,
                    "post_params" => $args->post_params,
                });
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>>>>>> FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            no strict "refs";

            $run_method->(
                {
                    "ifile" => $args->ifile,
                    "dbtype" => $args->dbtype,
                    "dbpath" => $args->dbpath,
#                    "dbfile" => $args->dbpath .".". $args->dbformat,
                    "dbfile" => $args->dbpath,
                    "ofile" => $args->ofile,
                    "pre_params" => $args->pre_params,
                    "params" => $args->params,
                    "post_params" => $args->post_params,
                }, $msgs );
        }

        &Common::File::delete_file_if_empty( $args->ofile );
    }
        
    # >>>>>>>>>>>>>>>>>>>>>> PARSE MATCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( -s $args->ofile and $parse_method = $args->parse_method )
    {
        no strict "refs";

        $sims = $parse_method->({
            "dbtype" => $args->dbtype,
            "title" => $args->title,
            "ifile" => $args->ofile,
        }, $msgs )->[0];

#        if ( not $sims or not @{ $sims } ) {
#            &error( qq (No similarities read by $parse_method from ). $args->ofile );
#        }

        return wantarray ? @{ $sims } : $sims;
    }

    return;
}

sub import_seqs_missing_files
{
    my ( $class, 
         $files,
         $dbtype,
        ) = @_;

    my ( $file, $sims, @ids, $module );

    foreach $file ( @{ $files } )
    {
        $sims = &Common::File::eval_file( $file );
        push @ids, map { [ $_->id2, $_->gi2 ] } @{ $sims };
    }
    
    $module = &Common::Types::type_to_mol( $dbtype ) ."::Import";
    
    {
        no strict "refs";

        eval "require $module";

        $module->import_seqs_missing( \@ids );
    }

    return;
}
        
sub _locs_from_blast_ali_strings
{
    # Niels Larsen, February 2007

    # Creates two lists of [ beg1, end1 ] and [ beg2, end2 ] from two 
    # blast-aligned sequence strings, in the numbering of the strings
    # given (means numbers likely have to processed further by calling
    # routine): it extracts regions that match and combine intervening 
    # stretches if their sequences contain no gaps. Input example:
    # 
    # seq1: SVSSRSDREYPLLIRMSYGSHDKKTKC----------STVVKASELDQFWQEYS-VFKG-
    # gstr:    +  +   P+LIR      DKK             STVVK  +LD F+  Y+   K 
    # seq2: LWDTHPETPLPILIRAHNNKSDKKAGTDRKDVDKIVLSTVVKPDDLDGFYVRYAEACKTT
    #                 **************             ****************
    # 
    # The regions marked by asterisks are returned, ie two lists of two
    # tuples each. Since DNA/RNA and protein have different gap lines,
    # a character match expression is given ('[A-Z]' for the above, and 
    # '|' for DNA/RNA) so the procedure knows matches from non-matches.
     
    my ( $seq1,         # Aligned sequence string 1
         $gstr,         # Gap string
         $seq2,         # Aligned sequence string 2 
         $args,         # Switches 
         ) = @_;

    # Returns a list.

    my ( $len1, $len2, $glen, @locs1, @locs2, $maxpos, $minpos,
         $beg1, $beg2, $end1, $end2, $i, $j, $ibeg, $ch1, $ch2, $match, 
         $pos1, $pos2, @ndcs, $add, $loc, $gap_expr );

    # Error if given strings of different length,

    if ( ($len1 = length $seq1) != ($len2 = length $seq2) or
         ($glen = length $gstr) != $len1 )
    {
        &error( qq (Different string lengths -> seq1 is $len1, gap is $glen, seq2 is $len2) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> MAP GAP-FREE AREAS <<<<<<<<<<<<<<<<<<<<<<

    # Create lists of from-to positions where there are no gaps in either
    # sequence. These locations will then be trimmed in the next section.

    $pos1 = 0;
    $pos2 = 0;

    $beg1 = $pos1;
    $beg2 = $pos2;

    for ( $i = 0; $i < length $seq1; $i++ )
    {
        $ch1 = substr $seq1, $i, 1;
        $ch2 = substr $seq2, $i, 1;

        if ( $ch1 ne "-" and $ch2 ne "-" )
        {
            if ( not $match )
            {
                $beg1 = $pos1;
                $beg2 = $pos2;
                $ibeg = $i;

                $match = 1;
            }
        }
        else
        {
            if ( $match )
            {
                push @locs1, [ $beg1, $pos1-1 ];
                push @locs2, [ $beg2, $pos2-1 ];
                push @ndcs, [ $ibeg, $i-1 ];

                $beg1 = $pos1;
                $beg2 = $pos2;

                $match = 0;
            }
        }

        $pos1 += 1 if $ch1 ne "-";
        $pos2 += 1 if $ch2 ne "-";
    }

    if ( $match )
    {
        push @locs1, [ $beg1, $pos1-1 ];
        push @locs2, [ $beg2, $pos2-1 ];
        push @ndcs, [ $ibeg, $glen-1 ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> TRIM OPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->{"trim"} )
    {
        # Narrow the from-to locations to where the gap string has a 
        # match symbol,

        $gap_expr = $args->{"gap_expr"};

        for ( $i = 0; $i <= $#ndcs; $i++ )
        {
            $pos1 = $ndcs[$i]->[0];
            $maxpos = $pos1 + $glen - 1;

            while ( $pos1 <= $maxpos and (substr $gstr, $pos1, 1) !~ /^$gap_expr$/xo )
            {
                $locs1[$i]->[0] += 1;
                $locs2[$i]->[0] += 1;
                $pos1 += 1;
            }

            $pos2 = $ndcs[$i]->[1];
            $minpos = $pos2 - $glen + 1;

            while ( $pos2 >= $minpos and (substr $gstr, $pos2, 1) !~ /^$gap_expr$/xo )
            {
                $locs1[$i]->[1] -= 1;
                $locs2[$i]->[1] -= 1;
                $pos2 -= 1;
            }
        }

        @locs1 = grep { $_->[0] <= $_->[1] } @locs1;
        @locs2 = grep { $_->[0] <= $_->[1] } @locs2;

        if ( ($i = scalar @locs1) != ($j = scalar @locs2) ) {
            &error( qq (Query elements after trim is $i, but $j subject elements) );
        }
    }

    return ( \@locs1, \@locs2 );
}

sub read_ids_from_blast_bioperl
{
    # Niels Larsen, February 2007.

    my ( $i_file,
         $args,
         ) = @_;

    my ( $ifh, @ids, @ids_all, $id, $result, $hit, $hsp, $q_name, $s_acc );

    {
        local $SIG{__DIE__};
        
        require Bio::SearchIO;
    }

    $ifh = new Bio::SearchIO( -format => $args->{"format"}, -file => $i_file );

    while ( $result = $ifh->next_result )
    {
        $q_name = $result->query_name;
        @ids = ();
        
        while ( $hit = $result->next_hit )
        {
            if ( $args and $args->{"extract"} eq "gi" ) {
                $id = &Common::Names::get_gi_from_blast_id( $hit->name );
            } else {
                $id = &Common::Names::get_acc_from_blast_id( $hit->name );
            }                

            push @ids, $id;
        }

        push @ids_all, [ @ids ];
    }
    
    undef $ifh;

    return wantarray ? @ids_all : \@ids_all;
}

sub read_ids_from_blast_report
{
    # Niels Larsen, January 2007.

    # Creates a list of ids from a blast report,
    
    my ( $i_file,          # Blast report file
         $args,            # Arguments
         ) = @_;

    # Returns a list.

    my ( $ids );

    $ids = &Sims::Import::read_ids_from_blast_bioperl( $i_file, { %{ $args }, "format" => "blast" } );

    return wantarray ? @{ $ids } : $ids;
}

sub read_ids_from_blast_tabular
{
    # Niels Larsen, January 2007.

    my ( $file,
         $args,
         ) = @_;

    my ( $fh, $line, @ids, $db, $acc, $loc );
    
    $fh = &Common::File::get_read_handle( $file );

    if ( $args->{"extract"} eq "gi" )
    {
        while ( defined ( $line = <$fh> ) )
        {
            if ( $line =~ /^\S+\s+gi\|(\d+)/ )
            {
                push @ids, $1;
            }
            else {
                &error( qq (Wrong looking blast table line -> "$line") );
            }
        }
    }
    elsif ( $args->{"extract"} eq "acc" )
    {
        while ( defined ( $line = <$fh> ) )
        {
            if ( $line =~ /^\S+\s+gi\|\d+\|([a-z]+)\|([^\|]+)\|([^\|\s]+)?/ )
            {
                # Workaround for NCBI bug.

                ( $db, $acc, $loc ) = ( $1, $2, $3 );

                if ( $db eq "pdb" and defined $loc ) {
                    $acc = $acc ."_$loc";
                }

                push @ids, $acc;
            }
            else {
                &error( qq (Wrong looking blast table line -> "$line") );
            }
        }
    }
    else {
        &error( qq (No extract value given, must be "gi" or "acc") );
    }

    if ( $args->{"uniqify"} ) {
        @ids = &Common::Util::uniqify( \@ids );
    }

    &Common::File::close_handle( $fh );

    return wantarray ? @ids : \@ids;
}

sub read_ids_from_blast_xml
{
    # Niels Larsen, January 2007.

    # Creates a list of lists of hit ids from a blast xml output,
    # one for each query sequence. Recognized arguments are "extract"
    # which should have the value "gi" or "acc".

    my ( $args,             # Arguments
         ) = @_;

    # Returns a list.

    my ( $i_fh, $line, @ids, @ids_all );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile extract ) ],
    });

    $i_fh = &Common::File::get_read_handle( $args->{"ifile"} );

    @ids_all = ();

    while ( defined ( $line = <$i_fh> ) )
    {
        if ( $line =~ /^<\?xml .+>\s*$/ )
        {
            @ids = ();

            while ( defined ( $line = <$i_fh> ) and
                    $line !~ /<\/BlastOutput>\s*$/ )
            {
                if ( $line =~ /<Hit_id>(.+)<\/Hit_id>/ )
                {
                    push @ids, $1;
                }
            }

            if ( $args and $args->{"extract"} eq "gi" ) {
                @ids = map { &Common::Names::get_gi_from_blast_id( $_ ) } @ids;
            } else {
                @ids = map { &Common::Names::get_acc_from_blast_id( $_ ) } @ids;
            }                

            push @ids_all, [ @ids ];
        }
    }

    &Common::File::close_handle( $i_fh );

    return wantarray ? @ids_all : \@ids_all;
}

sub read_ids_from_patscan
{
    my ( $ifile,
        ) = @_;
    
    my ( $ifh, $line, @ids );

    $ifh = &Common::File::get_read_handle( $ifile );

    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ /^>([^:]+)/ )
        {
            push @ids, $1;
        }
    }

    $ifh->close;

    return wantarray ? @ids : \@ids;
}
    
sub _read_sims_from_blast_table
{
    # Niels Larsen, November 2007.

    # Reads each line of a blast output table (-m 8) into a 
    # similarity object and returns a list.

    my ( $args,
         ) = @_;

    # Returns a list.

    my ( $def_args, $ifh, $line, @line, @sims, @sims_all, $id1, $id2, $i, $sim );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile extract id2_tag ) ],
    });

    $ifh = &Common::File::get_read_handle( $args->ifile );

    while ( defined ( $line = <$ifh> ) )
    {
        chomp $line;
        @line = split "\t", $line;

        $id2 = $line[1];

        if ( $args->id2_tag and $args->id2_tag eq "acc" and 
             $id2 =~ /^gi\|\d+\|[a-z]+\|([^\|]+)\|/ ) {
            $id2 = $1;
        }

        push @sims, Sims::Common->new( "id1" => $line[0],
                                       "beg1" => $line[6] - 1,
                                       "end1" => $line[7] - 1,
                                       "id2" => $id2,
                                       "beg2" => $line[8] - 1,
                                       "end2" => $line[9] - 1,
                                       "pct" => $line[2] );
    }

    &Common::File::close_handle( $ifh );

    if ( $args->extract eq "gi" )
    {
        @sims = map { $_->id2( &Common::Names::get_gi_from_blast_id( $_->id2 ) ); $_ } @sims;
    }

    $i = -1;
    $id1 = "";

    foreach $sim ( @sims )
    {
        if ( $id1 ne $sim->id1 ) 
        {
            $i++;
            $id1 = $sim->id1;
        }

        push @{ $sims_all[$i] }, $sim;
    }

    return \@sims_all;
}

sub read_sims_from_blast_table_local
{
    my ( $args,
         ) = @_;

    my ( $sims );

    $args->{"extract"} = "";
    $args->{"id2_tag"} = "";

    $sims = &Sims::Import::_read_sims_from_blast_table( $args );

    return $sims;
}
    
sub read_sims_from_blast_table_ncbi
{
    my ( $args,
         ) = @_;

    my ( $sims );

    $args->{"extract"} = "gi";
    $args->{"id2_tag"} = "acc";

    $sims = &Sims::Import::_read_sims_from_blast_table( $args );

    return $sims;
}
    
sub read_sims_from_blast_xml_local
{
    # Niels Larsen, May 2007.

    # Read similarities from XML output from blast run locally (yes the 
    # output is different from runs at NCBI). The routine just configures
    # Sims::Import::read_sims_from_blast_xml, look there for detail.

    my ( $args,      # Arguments hash
         ) = @_;

    # Returns a list.

    my ( $sims );

    $sims = &Sims::Import::_read_sims_from_blast_xml(
        {
            "ifile" => $args->{"ifile"},
            "extract" => "",
            "beg_tag" => "Iteration",
            "hit_tag" => "Iteration_hits",
            "id1_tag" => "Iteration_query-def",
            "id2_tag" => "Hit_def",
            "dbtype" => $args->{"dbtype"},
        } );

    return $sims;
}

sub read_sims_from_blast_xml_ncbi
{
    # Niels Larsen, May 2007.

    # Read similarities from XML output from blast run at NCBI (yes the 
    # output is different from local runs). The routine just configures
    # Sims::Import::read_sims_from_blast_xml, look there for detail.

    my ( $args,      # Arguments hash
         ) = @_;

    # Returns a list.

    my ( $sims_all, $sims );

    $sims_all = &Sims::Import::_read_sims_from_blast_xml(
        {
            "ifile" => $args->{"ifile"},
            "extract" => "acc",
            "beg_tag" => "BlastOutput",
            "hit_tag" => "Iteration_hits",
            "id1_tag" => "BlastOutput_query-def",
            "id2_tag" => "Hit_id",
            "dbtype" => $args->{"dbtype"},
        } );

#    foreach $sims ( @{ $sims_all } )
#    {
#        $sims = &Sims::Import::swap_gis_with_accs( $sims );
#    }

    return $sims_all;
}

sub _read_sims_from_blast_xml
{
    # Niels Larsen, July 2011.

    # Helper routine that similarity objects from a NCBI blast XML listing. 
    # The objects are equivalent to "HSPs", although they are furthere broken
    # down in gapfree pieces, the coordinates of these held by the locs1 and
    # locs2 fields. These fields are set:
    # 
    # id1           id of sequence 1, usually the query 
    # locs1         list seq 1 coordinates like [[3,30],[49,76], etc] 
    # id2           id of sequence 2, usually the subject sequence
    # locs2         list seq 2 coordinates like [[5,32],[55,82], etc] 
    # score         numeric score
    # pct           percentage score
    # 
    # The numbers are blast numbers without any processing, and are in global
    # numbering. If the match is against the complement, the numbers have to 
    # be changed - this is the responsibility of the caller.

    my ( $args,          # Arguments
         ) = @_;

    # Returns a list.

    my ( $i_fh, $line, @sims, @sims_all, $q_id, $s_id, $chunk, $hsp_expr, $sim,
         $q_beg, $q_end, $s_beg, $s_end, $q_seqstr, $s_seqstr, $gapstr, $q_locs, 
         $s_locs, $beg_tag, $hit_tag, $q_id_tag, $s_id_tag, $gap_expr, $score,
         $q_frame, $s_frame, $xmlstr, $xml, $hits, $hit, $hsps, $hsp, $q_len,
         $extract, $gap_args, $s_descr );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile extract beg_tag hit_tag id1_tag id2_tag dbtype ) ],
    });
    
    if ( &Common::Types::is_dna_or_rna( $args->dbtype ) ) {
        $gap_expr = '|';
    } else {
        $gap_expr = '[A-Za-z\+]';
    }

    $gap_args = { "trim" => 1, "gap_expr" => $gap_expr };

    $beg_tag = $args->beg_tag;
    $hit_tag = $args->hit_tag;
    $q_id_tag = $args->id1_tag;
    $s_id_tag = $args->id2_tag;
    $extract = $args->extract;

    local $/ = "</BlastOutput>\n";

    $i_fh = &Common::File::get_read_handle( $args->ifile );

    while ( defined ( $xmlstr = <$i_fh> ) )
    {
        # Parse output for one query sequence,
        
        $xml = bless &XML::Simple::XMLin( $xmlstr );

        # Initiate similarity object with query id,

        $q_id = $xml->{ $q_id_tag };
        $q_id =~ s/ .*//;

        $q_len = $xml->{"BlastOutput_query-len"};

        # Loop through the list of hits (match against a given database entry),
        # each with their matches,

        $hits = $xml->{"BlastOutput_iterations"}->{"Iteration"}->{ $hit_tag }->{"Hit"};
        @sims = ();

        foreach $hit ( @{ $hits } )
        {
            $hsps = $hit->{"Hit_hsps"}->{"Hsp"};
            $hsps = [ $hsps ] if ref $hsps eq "HASH";

            if ( $extract eq "gi" )
            {
                if ( $hit->{"Hit_id"} =~ /^gi\|(\d+)/ ) {
                    $s_id = $1;
                } else {
                    &error( qq (Wrong looking Hit_id -> $hit->{"Hit_id"} in ). $args->ifile );
                }
            }
            elsif ( $extract eq "acc" ) {
                $s_id = $hit->{"Hit_accession"};
            }
            else {
                &error( qq (Wrong looking id type to extract -> "$extract") );
            }
            
            $s_descr = $hit->{"Hit_def"};
            
            foreach $hsp ( @{ $hsps } )
            {
                $q_beg = $hsp->{"Hsp_query-from"} - 1;
                $q_end = $hsp->{"Hsp_query-to"} - 1;
                $s_beg = $hsp->{"Hsp_hit-from"} - 1;
                $s_end = $hsp->{"Hsp_hit-to"} - 1;
                $q_frame = $hsp->{"Hsp_query-frame"};
                $s_frame = $hsp->{"Hsp_hit-frame"};
                $q_seqstr = $hsp->{"Hsp_qseq"};
                $s_seqstr = $hsp->{"Hsp_hseq"};
                $gapstr = $hsp->{"Hsp_midline"};
                $score = $hsp->{"Hsp_score"};
                
                $sim = Sims::Common->new(
                    "id1" => $q_id,
                    "id2" => $s_id,
                    "score" => $score,
                    "descr" => $s_descr,
                    );

                ( $q_locs, $s_locs ) = &Sims::Import::_locs_from_blast_ali_strings( $q_seqstr, $gapstr, $s_seqstr, $gap_args );
                
                if ( $s_beg < $s_end and $q_frame > 0 )
                {
                    if ( $q_beg <= $q_end and $s_frame > 0 )
                    {                                
                        $q_locs = &Seq::Common::increment_locs( $q_locs, $q_beg );
                        
                        $sim->frame1( 1 );
                        $sim->frame2( 1 );
                    }
                    elsif ( $q_beg > $q_end and $s_frame < 0 )
                    {
                        $q_locs = &Seq::Common::subtract_locs( $q_locs, $q_beg );
                        $q_locs = &Seq::Common::reverse_locs( $q_locs, $q_len );
                        
                        $sim->frame1( 1 );
                        $sim->frame2( -1 );
                    }
                    else {
                        &error( qq (Programmer surprise: q_beg = $q_beg, q_end = $q_end,)
                                . qq ( s_frame = $s_frame; this combination should not happen.) );
                    }
                    
                    $s_locs = &Seq::Common::increment_locs( $s_locs, $s_beg );
                }
                else {
                    &error( qq (Programmer surprise: s_beg = $s_beg, s_end = $s_end,)
                            . qq ( q_frame = $q_frame; this combination should not happen.) );
                }
                
                $sim->locs1( $q_locs );
                $sim->locs2( $s_locs );
                
                push @sims, &Storable::dclone( $sim );
            }
        }

        push @sims_all, [ @sims ];
    }

    &Common::File::close_handle( $i_fh );

    return \@sims_all;
}

sub _read_sims_from_blast_xml_old
{
    # Niels Larsen, February 2007.

    # Creates similarity objects from a blast XML listing. The objects are 
    # equivalent to "HSPs", although they are furthere broken down in gapfree
    # pieces, the coordinates of these held by the locs1 and locs2 fields. 
    # These fields are set:
    # 
    # id1           id of sequence 1, usually the query 
    # locs1         list seq 1 coordinates like [[3,30],[49,76], etc] 
    # id2           id of sequence 2, usually the subject sequence
    # locs2         list seq 2 coordinates like [[5,32],[55,82], etc] 
    # score         numeric score
    # pct           percentage score
    # 
    # The numbers are blast numbers without any processing, and are in global
    # numbering. If the match is against the complement, the numbers have to 
    # be changed - this is the responsibility of the caller.

    my ( $args,          # Arguments
         ) = @_;

    # Returns a list.

    my ( $i_fh, $line, @sims, @sims_all, $q_id, $s_id, $chunk, $hsp_expr, $sim,
         $q_beg, $q_end, $s_beg, $s_end, $q_seqstr, $s_seqstr, $gapstr, $q_locs, 
         $s_locs, $beg_tag, $hit_tag, $q_id_tag, $s_id_tag, $gap_expr, $score,
         $q_frame, $s_frame );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile extract beg_tag hit_tag id1_tag id2_tag dbtype ) ],
    });

    $i_fh = &Common::File::get_read_handle( $args->ifile );

    @sims_all = ();

    $hsp_expr = '<Hsp_score>(\d+)</Hsp_score>\s+'
              . '.+'
              . '<Hsp_query-from>(\d+)<\/Hsp_query-from>\s+'
              . '<Hsp_query-to>(\d+)<\/Hsp_query-to>\s+'
              . '<Hsp_hit-from>(\d+)</Hsp_hit-from>\s+'
              . '<Hsp_hit-to>(\d+)</Hsp_hit-to>\s+'
              . '<Hsp_query-frame>(\d+)</Hsp_query-frame>\s+'
              . '<Hsp_hit-frame>(-?\d+)</Hsp_hit-frame>\s+'
              . '.+'
              . '<Hsp_qseq>(.+)<\/Hsp_qseq>\s+'
              . '<Hsp_hseq>(.+)<\/Hsp_hseq>\s+'
              . '<Hsp_midline>(.+)</Hsp_midline>';

    if ( &Common::Types::is_dna_or_rna( $args->dbtype ) ) {
        $gap_expr = '|';
    } else {
        $gap_expr = '[A-Za-z\+]';
    }

    $beg_tag = $args->beg_tag;
    $hit_tag = $args->hit_tag;
    $q_id_tag = $args->id1_tag;
    $s_id_tag = $args->id2_tag;

    while ( defined ( $line = <$i_fh> ) )
    {
        if ( $line =~ /\s*<$beg_tag>\s*$/o )
        {
            @sims = ();

            undef $q_id;
            undef $s_id;

            while ( defined ( $line = <$i_fh> ) and $line !~ /<$hit_tag>\s*$/ )
            {
                if ( $line =~ /^\s*<$q_id_tag>(.+)<\/$q_id_tag>/o )
                {
                    $q_id = $1;
                }
            }

            while ( defined ( $line = <$i_fh> ) and $line !~ /^\s*<\/$hit_tag>\s*$/o )
            {
                if ( $line =~ /<$s_id_tag>(.+)<\/$s_id_tag>/o )
                {
                    $s_id = $1;
                }
                elsif ( $line =~ /^\s*<Hsp>/ )
                {
                    {
                        local $/ = "</Hsp>";

                        $chunk = <$i_fh>;
                    }
                    
                    if ( $chunk =~ /$hsp_expr/os )
                    {
                        ( $score, $q_beg, $q_end, $s_beg, $s_end,
                          $q_frame, $s_frame, $q_seqstr, $s_seqstr, $gapstr )
                            = ( $1, $2 - 1, $3 - 1, $4 - 1, $5 - 1,
                                $6, $7, $8, $9, $10 );

                        $sim = Sims::Common->new( "id1" => $q_id, "id2" => $s_id );

                        ( $q_locs, $s_locs ) = 
                            &Sims::Import::_locs_from_blast_ali_strings( $q_seqstr, $gapstr, $s_seqstr,
                                                                         {
                                                                             "trim" => 1,
                                                                             "gap_expr" => $gap_expr,
                                                                         });
                        if ( $s_beg < $s_end and $q_frame > 0 )
                        {
                            if ( $q_beg <= $q_end and $s_frame > 0 )
                            {                                
                                $q_locs = &Seq::Common::increment_locs( $q_locs, $q_beg );

                                $sim->frame1( 1 );
                                $sim->frame2( 1 );
                            }
                            elsif ( $q_beg > $q_end and $s_frame < 0 )
                            {
                                $q_locs = &Seq::Common::subtract_locs( $q_locs, $q_beg );
                                $q_locs = &Seq::Common::reverse_locs( $q_locs );
                                
                                $sim->frame1( 1 );
                                $sim->frame2( -1 );
                            }
                            else {
                                &error( qq (Programmer surprise: q_beg = $q_beg, q_end = $q_end,)
                                      . qq ( s_frame = $s_frame; this combination should not happen.) );
                            }

                            $s_locs = &Seq::Common::increment_locs( $s_locs, $s_beg );
                        }
                        else {
                            &error( qq (Programmer surprise: s_beg = $s_beg, s_end = $s_end,)
                                  . qq ( q_frame = $q_frame; this combination should not happen.) );
                        }

                        $sim->locs1( $q_locs );
                        $sim->locs2( $s_locs );

                        $sim->score( $score );

                        push @sims, &Storable::dclone( $sim );
                    }
                    else {
                        &error( qq (Wrong looking chunk -> "$chunk") );
                    }
                }
            }

            if ( $args->extract eq "gi" ) {
                @sims = map { $_->id2( &Common::Names::get_gi_from_blast_id( $_->id2 ) ); $_ } @sims;
            } elsif ( $args->extract eq "acc" ) {
                @sims = map { $_->id2( &Common::Names::get_acc_from_blast_id( $_->id2 ) ); $_ } @sims;
            } elsif ( $args->extract ) {
                &error( qq (Wrong looking item to extract -> "$args->{'extract'}") );
            }

            push @sims_all, [ @sims ];
        }
    }

    &Common::File::close_handle( $i_fh );

    return \@sims_all;
}

sub read_sims_from_mview
{
    # Niels Larsen, January 2007.
    
    my ( $i_file,          # Input mview file name 
         ) = @_;

    # Returns integer.

    my ( $ifh, @line, $line, $q_id, $q_seq, $s_id, $s_seq, $q_beg, $q_end,
         $s_beg, $s_end, $count, $db, $acc, $sim, @sims, $pct );

    $ifh = &Common::File::get_read_handle( $i_file );
    
    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ /^\s*(\S+)\s+bits\s+E-value\s+N\s+(\S+)%\s+(\d+):(\d+)/ )
        {
            $q_id = $1;
            $pct = $2;
            $q_beg = $3;
            $q_end = $4;

            $sim = Sims::Common->new( "id1" => $q_id, "id2" => $q_id );
            
            $sim->locs1( [[ $q_beg, $q_end ]] );
            $sim->locs2( [[ $q_beg, $q_end ]] );

            push @sims, $sim;

            $count += 1;
        }
        elsif ( $line =~ /^\s*\d+/ )
        {
            @line = split " ", $line;

            $s_id = $line[1];

            ( $q_beg, $q_end ) = ( split ":", $line[-3] );
            ( $s_beg, $s_end ) = ( split ":", $line[-2] );

            $pct = $line[-4];
            $pct =~ s/\%$//;
            
            $db = &Common::Names::get_db_from_blast_id( $s_id );
            $acc = &Common::Names::get_acc_from_blast_id( $s_id );

            $sim = Sims::Common->new( "id1" => $q_id, "id2" => "$db:$acc" );

            $sim->locs1( [[ $q_beg, $q_end ]] );
            $sim->locs2( [[ $s_beg, $s_end ]] );

            push @sims, $sim;

            $count += 1;
        }
    }

    &Common::File::close_handle( $ifh );

    if ( not defined $q_id ) {
        &error( qq (No query line found) );
    }

    if ( not defined $s_id ) {
        &error( qq (No subject line found) );
    }

    return wantarray ? @sims : \@sims;
}

sub read_sims_from_patscan
{
    # Niels Larsen, july 2007.

    # Parses the output from scan_for_matches and returns a list of similarity
    # objects. 

    my ( $args,           # Arguments hash
        ) = @_;

    # Returns a list.

    my ( $sims, $i_fh, $line, @seqs, $seq, $beg, $end, $i, $j, $sim, $str, $locs, $id1 );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile title ) ],
        "S:0" => [ qw ( dbtype ) ],       # dummy argument, other parse routines want it
    });

    $i_fh = &Common::File::get_read_handle( $args->ifile );

    while ( defined ( $line = <$i_fh> ) )
    {
        chomp $line;

        if ( $line =~ /^>(.+):\[(\d+),(\d+)\]$/ )
        {
            $sim = Sims::Common->new( "id2" => $1 );

            $beg = $2 - 1;
            $end = $3 - 1;

            $line = <$i_fh>; chomp $line;

            $j = -1;
            undef $locs;

            @seqs = split / /, $line;

            if ( $beg > $end ) {
                @seqs = reverse @seqs;
            }

            foreach $str ( @seqs )
            {
                if ( $str ) 
                {
                    $i = $j + 1;
                    $j = $i - 1 + length $str;
                    
                    push @{ $locs }, [ $i, $j ];
                }
                else {
                    push @{ $locs }, [];
                }
            }
            
            if ( $beg <= $end )
            {
                $sim->frame2( 1 );
                $sim->locs2( &Seq::Common::increment_locs( $locs, $beg ) );
            }
            else
            {
                $sim->frame2( -1 );
                $sim->locs2( &Seq::Common::increment_locs( $locs, $end ) );
            }                

            push @{ $sims }, $sim;
        }
    }
    
    &Common::File::close_handle( $i_fh );

    $id1 = $args->title;
    $id1 =~ s/\s/_/g;
    $sims = &Sims::Common::set_fields( $sims, "id1", $id1 );

    $sims = &Sims::Common::set_fields( $sims, "score", 0 );

    $sims = &Sims::Import::create_locs1( $sims );

    return [ $sims ];
}

sub simrank_to_sims
{
    my ( $infile,
         $outfile,
         $db1,
         $db2,
         ) = @_;

    my ( $ifh, $ofh, $line, @line, @row, $count, $ent1, $ent2, $pct, $field );

    $db1 ||= "";
    $db2 ||= "";

    $ifh = &Common::File::get_read_handle( $infile );
    $ofh = &Common::File::get_write_handle( $outfile );

    $count = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        chomp $line;
        @line = split "\t", $line;

        $ent1 = shift @line;

        foreach $field ( @line )
        {
            ( $ent2, $pct ) = split ":", $field;

            #         db1  entry1   beg1    end1    db2  entry2   beg2    end2    pct
            @row = ( $db1, $ent1,    "",     "",   $db2,  $ent2,   "",     "",   $pct );

            $ofh->print( (join "\t", @row) ."\n" );
            $count += 1;
        }
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    return $count;
}

sub split_blast_report
{
    # Niels Larsen, January 2007.

    # Splits a blast report into a report file for each query sequence 
    # results in it. MView needs this, among others (and BioPerl doesnt).
    # Returns a list of "$i_file.n". 
    
    my ( $i_file,
         ) = @_;

    # Returns a list.

    my ( $ifh, $ofh, @header, $line, @o_files, $suffix );
         
    $ifh = &Common::File::get_read_handle( $i_file );

    while ( defined ( $line = <$ifh> ) and $line !~ /^Query=/ )
    {
        push @header, $line;
    }

    while ( $line and $line =~ /^Query=\s*(\S+)/ )
    {
        $suffix = $1 ."_report";
        
        &Common::File::delete_file_if_exists( "$i_file.$suffix" );
        $ofh = &Common::File::get_write_handle( "$i_file.$suffix" );

        $ofh->print( @header );
        $ofh->print( $line );

        while ( defined ( $line = <$ifh> ) and $line !~ /^Query=/ )
        {
            $ofh->print( $line );
        }

        &Common::File::close_handle( $ofh );

        push @o_files, "$i_file.$suffix";
    }

    &Common::File::close_handle( $ifh );

    return wantarray ? @o_files : \@o_files;
}

sub split_blast_tabular
{
    # Niels Larsen, January 2007.

    # Splits a blast m8 table into smaller m8 files with only a single 
    # query sequence in them. Returned is a { "query_id" => file } 
    # hash. 
    
    my ( $i_file,
         $o_prefix,
         ) = @_;

    # Returns a list.

    my ( $ifh, $ofh, $line, $q_id, %seen, $i, $o_file );
         
    $ifh = &Common::File::get_read_handle( $i_file );

    $i = 0;

    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ /^(\S+)\s+/ )
        {
            $q_id = $1;

            if ( not $seen{ $q_id } )
            {
                $o_file = "$o_prefix.". $q_id .".blast_tabular";
                $seen{ $q_id } = $o_file;

                &Common::File::close_handle( $ofh ) if defined $ofh;

                &Common::File::delete_file_if_exists( $o_file );
                $ofh = &Common::File::get_write_handle( $o_file );
            }

            $ofh->print( $line );
        }
        else {
            &error( qq (Wrong looking blast line -> "$line") );
        }
    }

    &Common::File::close_handle( $ifh );

    return wantarray ? %seen : \%seen;
}

sub split_blast_xml
{
    # Niels Larsen, January 2007.

    # Splits a blast XML output into a file for each query sequence in
    # it. MView needs this, among others (and BioPerl doesnt). Returns
    # a list of the files made, called "$i_file.(query suffix)". 
    
    my ( $args,
         ) = @_;

    # Returns a list.

    my ( $i_file, $i_fh, $o_fh, $o_num, $line, @o_files, $o_file,
         @lines, $q_id );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( ifile ) ],
    });
         
    $i_file = $args->{"ifile"};
    $i_fh = &Common::File::get_read_handle( $i_file );

    $o_num = 0;

    while ( defined ( $line = <$i_fh> ) )
    {
        if ( $line =~ /^<\?xml .+>\s*$/ )
        {
            @lines = $line;

            while ( defined ( $line = <$i_fh> ) and $line !~ /^\s*<BlastOutput_query-def>/ )
            {
                push @lines, $line;
            }

            if ( $line =~ /^\s*<BlastOutput_query-def>(.+)<\/BlastOutput_query-def>\s*$/ )
            {
                $o_file = &Common::Names::replace_suffix( $i_file, ".$o_num.blast_xml" );

                &Common::File::delete_file_if_exists( $o_file );
                $o_fh = &Common::File::get_write_handle( $o_file );

                $o_fh->print( @lines );
                $o_fh->print( $line );

                $o_num += 1;
            }
        }
        elsif ( $line =~ /<\/BlastOutput>\s*$/ )
        {
            $o_fh->print( $line );
            &Common::File::close_handle( $o_fh );

            push @o_files, $o_file;
        }
        else {
            $o_fh->print( $line );
        }            
    }

    &Common::File::close_handle( $i_fh );

    return wantarray ? @o_files : \@o_files;
}

sub swap_gis_with_accs
{
    # Niels Larsen, February 2007.

    # Replaces the "id2" fields with accession numbers, assuming they are NCBI
    # gi numbers. The gi number is moved to "gi2". Returns an updated list of 
    # similarities.

    my ( $sims,       # Similarity list
        ) = @_;
    
    # Returns a list.

    my ( $sim, @gis, @accs, $i, $j, %to_accs );

    @gis = map { $_->id2 } @{ $sims };
    @gis = &Common::Util::uniqify( \@gis );

    @accs = &Common::Entrez::gis_to_accs( \@gis );

    if ( scalar @gis == scalar @accs )
    {
        for ( $i = 0; $i <= $#gis; $i ++ )
        {
            $to_accs{ $gis[$i] } = $accs[$i];
        }
    }
    else
    {
        $i = scalar @gis;
        $j = scalar @accs;
        
        &error( qq ($i unique GI numbers, but $j accession numbers) );
    }
    
    foreach $sim ( @{ $sims } )
    {
        $sim->gi2( $sim->id2 );
        $sim->id2( $to_accs{ $sim->id2 } );
    }

    return wantarray ? @{ $sims } : $sims;
}

sub write_fasta_from_blast_report
{
    # Niels Larsen, January 2007.

    # Writes the subject sequence fragments from a blast output into a fasta
    # file, one file per query sequence. If query sequences are given, then 
    # the query sequence is first in the file(s). HSP's for a subject sequence
    # are simply strung together. A list of file names is returned.
    
    my ( $i_file,          # Input blast report file name 
         $o_file,          # Output fasta file name or handle
         $args,            # Switches - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $i_close, $o_close, $result, $hit, $hsp, $ndx, $s_name, 
         $seq, @coords, $hit_count );

    if ( not ref $i_file )
    {
        $i_file = new Bio::SearchIO( -format => "blast", -file => $i_file );
        $i_close = 1;
    }

    if ( not ref $o_file )
    {
        if ( $args->{"append"} ) {
            $o_file = &Common::File::get_append_handle( $o_file );
        } else {
            $o_file = &Common::File::get_write_handle( $o_file );
        }

        $o_close = 1;
    }        

    $ndx = 0;
    $hit_count = 0;

    while ( $result = $i_file->next_result )
    {
        while ( $hit = $result->next_hit )
        {
            $s_name = &Common::Names::get_acc_from_blast_id( $hit->name );
            @coords = ();
            
            while ( $hsp = $hit->next_hsp )
            {
                push @coords, [ $hsp->range('query'), $hsp->range('hit'), $hsp->hit_string ];
            }
            
            if ( $args->{"align_hits"} )
            {
                @coords = map { [ @{ $_ }[0..3], $_->[1] - $_->[0], undef, $_->[4] ] } @coords;
#                @coords = &DNA::Ali::align_two_dnas( undef, undef, \@coords );
                
                $seq = join "", (map { $_->[6] } @coords);
            }
            else {
                $seq = join "", (map { $_->[4] } @coords);
            }

            $o_file->print( ">$s_name\n$seq\n" );

            $hit_count += 1;
        }

        $ndx += 1;
    }
        
    if ( $i_close ) {
        undef $i_file;
    }
    
    if ( $o_close ) {
        &Common::File::close_handle( $o_file );
    }

    return $hit_count;
}

1;

__END__

sub write_fasta_from_mview
{
    # Niels Larsen, January 2007.
    
    # Writes the fasta "sequences" from a given mview output (in "new"
    # format) to a given fasta file. The number of sequences is returned.

    my ( $i_file,          # Input mview file name 
         $o_file,          # Output fasta file name 
         ) = @_;

    # Returns integer.

    my ( $ifh, $ofh, @line, $line, $q_id, $q_seq, $s_id, $s_seq,
         $count, $db, $acc );

    $ifh = &Common::File::get_read_handle( $i_file );
    $ofh = &Common::File::get_write_handle( $o_file );
    
    while ( defined ( $line = <$ifh> ) )
    {
        if ( $line =~ /^\s*(\S+)\s+bits\s+E-value\s+N\s+\S+\s+\S+\s+(\S+)\s*$/ )
        {
            $q_id = $1;
            $q_seq = $2;

            $ofh->print( ">$q_id\n$q_seq\n" );
            $count += 1;
        }
        elsif ( $line =~ /^\s*\d+/ )
        {
            @line = split " ", $line;

            $s_id = $line[1];
            $s_seq = $line[-1];

            $db = &Common::Names::get_db_from_blast_id( $s_id );
            $acc = &Common::Names::get_acc_from_blast_id( $s_id );

            $ofh->print( ">$db:$acc\n$s_seq\n" );
            $count += 1;
        }
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );

    if ( not defined $q_id ) {
        &error( qq (No query line found) );
    }

    if ( not defined $s_id ) {
        &error( qq (No subject line found) );
    }

    return $count;
}
