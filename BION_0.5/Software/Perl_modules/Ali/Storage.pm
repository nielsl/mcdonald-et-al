package Ali::Storage;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that create, delete and retrieve from local alignment storage. The
# underlying key/value store is Kyoto Cabinet, see http://fallabs.com. This
# module is a modified and pruned version of Seq::Storage, and perhaps it has
# more routines than needed.
#
# The main routines callable from outside this module are,
#
#  create_indices       Creates alignment and aligned sequence storage
#  delete_indices       Deletes alignment and aligned sequence storage
#  fetch_aliseqs        Retrieves alignments or sequences, library version
#  fetch_cmdline        Retrieves alignments or sequences, console wrapper
#
# See the scripts ali_index, ali_unindex and ali_fetch for examples of how to 
# call these. All other routines are callable too of course, but were written 
# as helpers for these main routines and scripts. 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use File::Basename;
use Fcntl qw ( SEEK_SET SEEK_CUR SEEK_END );

use vars qw ( *AUTOLOAD );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::DBM;

use Seq::Storage;
use Seq::Common;
use Ali::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINE NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# about_storage
# check_indices_exist
# check_inputs_exist
# close_handles
# count_seq_keys
# create_index
# create_index_fasta_like
# create_index_stockholm
# create_indices
# default_regex
# delete_indices
# fetch
# fetch_aliseqs
# get_handles
# get_index_config
# get_index_stats
# key_types_info
# key_types_values
# is_indexed
# measure_ali
# measure_ali_fasta
# measure_ali_stockholm
# process_fetch_args
# process_index_args
# read_locators
# set_index_config
# set_kyoto_params
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Index_suffix = ".fetch";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub about_storage
{
    # Niels Larsen, February 2011. 

    # Creates a table of readable statistics about the storage. In void 
    # context this is printed, in non-void context a list of [ title, text ]
    # is returned.

    my ( $file,    # Storage file
        ) = @_;

    # Returns a list.

    my ( $dbh, $conf, @table, $kyoto, $type, @msgs );
    
    $dbh = &Common::DBM::read_open( $file, "fatal" => 0 );

    if ( not defined $dbh )
    {
        push @msgs, ["ERROR", qq (Not an index file -> "$file") ];
        push @msgs, ["INFO", qq (Specify an index file, not a data file) ];

        &append_or_exit( \@msgs );
    }

    $conf = &Ali::Storage::get_index_config( $dbh );

    &Common::DBM::close( $dbh );

    $kyoto = $conf->kyoto_params;
    
    @table = (
        [ "", "" ],
        [ "Alignment file", $conf->ali_file // "" ],
        [ "Alignment format", $conf->ali_format // "" ],
        [ "", "" ],
        );
    
    push @table, [ "Alignments total", $conf->ali_count ] if defined $conf->ali_count;
    push @table, [ "Sequences total", $conf->seq_count ] if defined $conf->seq_count;


#    foreach $type ( @{ $conf->key_types } )
#    {
#        push @table, [ "Indexed type", &Ali::Storage::key_types_info( $type, "title" ) ];
#    }
        
    push @table,
        [ "", "" ],
        [ "Kyoto Cabinet record size alignment power", $kyoto->{"apow"} ],
        [ "Kyoto Cabinet free block pool size", $kyoto->{"fpow"} ],
        [ "Kyoto Cabinet memory mapped region size", $kyoto->{"msiz"} ],
        [ "Kyoto Cabinet optional features", $kyoto->{"opts"} ],
        [ "Kyoto Cabinet page cache size", $kyoto->{"pccap"} ],
        [ "Kyoto Cabinet bucket number", $kyoto->{"bnum"} ],
    ;

    if ( defined wantarray ) 
    {
        return wantarray? @table : \@table;
    }
    else {
        &Seq::Storage::print_about_table( \@table );
    }

    return;
}
    
sub check_indices_exist
{
    # Niels Larsen, January 2011.
    
    # Checks if a given list of files have corresponding up to date indexes
    # of a given type. The index types and their suffixes are given in 
    # Ali::Storage::key_types_info. Returns nothing, but appends messages
    # to the given list or prints them and then exits.

    my ( $files,       # File list
         $suffix,      # Index suffix
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $file, @msgs );

    foreach $file ( @{ $files } )
    {
        if ( &Ali::Storage::is_indexed( $file, { "suffix" => $suffix } ) )
        {
            push @msgs, ["ERROR", qq (Index exists -> "$file") ];
        }
    }

    if ( @msgs )
    {
        push @msgs, ["info", qq (The --clobber option forces creation of a new index.) ];
        &append_or_exit( \@msgs, $msgs );
    }

    return;
}

sub check_inputs_exist
{
    # Niels Larsen, March 2011.

    # Check that the given files exist. Returns nothing, but appends messages
    # to the given list or prints them and then exits.

    my ( $files,       # File list
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns nothing. 

    my ( @files );

    if ( defined $files and @{ $files } )
    {
        push @files, &Common::File::check_files( $files, "efr", $msgs );
    }
    else {
        push @{ $msgs }, ["ERROR", "No input files given" ];
    }

    return wantarray ? @files : \@files;
}

sub close_handles
{
    my ( $fhs,
        ) = @_;

    my ( $key, $fh, $count );

    $count = 0;

    foreach $key ( keys %{ $fhs } )
    {
        $fh = $fhs->{ $key };

        if ( ref $fh )
        {
            if ( ref $fh eq "KyotoCabinet::DB" ) {
                $count += &Common::DBM::close( $fh );
            } else {
                $count += &Common::File::close_handle( $fh );
            }
        }
    }

    return $count;
}

sub count_seq_keys
{
    my ( $keys,
        ) = @_;

    my ( @keys );

    @keys = grep /^seq_/, @{ $keys };

    return @keys if wantarray;

    return scalar @keys;
}
    
sub create_index
{
    # Niels Larsen, April 2011.

    # Creates a index file for a given alignment file. If the given index type
    # is fetch_ali, only whole alignments are indexed, not individual sequences;
    # if it is fetch_aliseq, then ali_fetch gives sequence access too. The index
    # file path is returned. 

    my ( $ifile,     # Input file name
         $ofh,       # Output index handle
         $args,      # Arguments hash - OPTIONAL
        ) = @_;

    # Returns string. 

    my ( $defs, $buf_size, $format, $ifh, $hdr_regex, $counts );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "buf_size" => undef,
        "hdr_regex" => undef,
        "key_types" => [],
        "format" => undef,
        "count_alis" => 0,
        "count_seqs" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $buf_size = $args->buf_size;
    $hdr_regex = $args->hdr_regex;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DETECT FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not ( $format = $args->format ) )
    {
        $format = &Ali::IO::detect_format( $ifile );
    }

    $ifh = &Common::File::get_read_handle( $ifile );

    if ( $format =~ /^uclust|fasta|fasta_wrapped$/ )
    {
        $hdr_regex = &Ali::Storage::default_regex( $format, $args->key_types ) if not $hdr_regex;
        
        $counts = &Ali::Storage::create_index_fasta_like(
            $ifh,
            $ofh,
            {
                "hdr_regex" => $hdr_regex,
                "key_types" => $args->key_types,
                "buf_size" => $buf_size,
                "count_alis" => $args->count_alis,
                "count_seqs" => $args->count_seqs,
            });
    }
    elsif ( $format eq "stockholm" )
    {
        &Ali::Storage::create_index_stockholm(
             $ifh,
             $ofh,
             {
                 "buf_size" => $buf_size,
                 "count_alis" => $args->count_alis,
             });
    }
    else {
        &Common::File::close_handle( $ifh );
        &error( qq (Unrecognized format -> "$format") );
    }

    &Common::File::close_handle( $ifh );

    return wantarray ? %{ $counts } : $counts;
}

sub create_index_fasta_like
{
    # Niels Larsen, April 2011.

    # Indexes fasta-like alignments and their sequences, depending on the key
    # types given. Alignment and sequence ids are extracted from the header 
    # line with the expression given. The routine creates key / value pairs 
    # that are stored on the given handles in a buffered way so the memory is
    # not flooded. Keys can have these forms,
    # 
    #  "alignment-id"                                    (key type ali_ents)
    #  "alignment-id:sequence-id"                        (key type seq_ents)
    #  "alignment-id:sequence-id:sub-sequence-locator"   (key type seq_strs)
    #
    # where sub-sequence-locator is the same as for sub-sequences. The value
    # is always "byte-position<tab>length". Note that the sequences of wrapped 
    # formats (like stockholm) can not be indexed, only the alignment entries
    # as a whole.

    my ( $ifh,    # Alignment input file handle
         $ofh,    # Index output file handle
         $args,   # Arguments hash
        ) = @_;
    
    # Returns nothing.

    my ( $defs, $buf_size, $buf_count, %index, $byt_pos, $byt_len, $ali_id_prev,
         $seq_id_prev, $seq_id, $hdr_regexp, $ali_id, $ali_len, $line, $format,
         $ali_beg, $code, $want_seqs, %key_types, $seq_beg, $seq_len, $line_len,
         $want_seqents, $count_alis, $count_seqs, $ali_count, $seq_count,
         $counts );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "hdr_regex" => undef,
        "key_types" => [],
        "buf_size" => undef,
        "count_alis" => 0,
        "count_seqs" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $hdr_regexp = $args->hdr_regex;    
    $buf_size = $args->buf_size;

    $count_alis = $args->count_alis;
    $count_seqs = $args->count_seqs;

    %key_types = map { $_, 1 } @{ $args->key_types };

    if ( $key_types{"seq_ents"} or $key_types{"seq_strs"} )
    {
        $want_seqs = 1;

        if ( $key_types{"seq_ents"} ) {
            $want_seqents = 1;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> COMPOSE CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $code = q (
    # The outer loop fills a key/value hash in memory that is stored regularly,
    # and at last,

);

    $code .= qq (    \$ali_count = 0;\n) if $count_alis;
    $code .= qq (    \$seq_count = 0;\n) if $want_seqs and $count_seqs;

    $code .= q (
    while ( 1 )
    {
        %index = ();
        $buf_count = 0;
        
        # This inner loop reads line by line and gets alignment id by matching
        # the supplied expression with the '>' header line. If a new alignment
        # id is found then save starting position of the old plus its length,
        # and reset id and length. The buffer count increases by 20, but that 
        # is nearly arbitrary, just a way to keep perl memory to grow wild,

        while ( defined ( $line = <$ifh> ) )
        {
            $line_len = length $line;

            if ( $line =~ /^>/ )
            {
                if ( $line =~ /^>$hdr_regexp/o )
                {
                    $ali_id = $1;
);
    
    if ( $want_seqs )
    {
        $code .= qq (                    \$seq_id = \$2;\n);
        $code .= qq (\n                    \$seq_count += 1;\n) if $count_seqs;
    }

    $code .= q (
                    $ali_id_prev //= $ali_id;
);

    if ( $want_seqs )
    {
        $code .= q (
                    if ( defined $seq_id_prev )
                    {
                        $index{ "$ali_id_prev:$seq_id_prev" } = "$seq_beg\t$seq_len";
                        $buf_count += 20;
                    }

                    $seq_id_prev = $seq_id;
);
    }

    $code .= q (
                    if ( $ali_id ne $ali_id_prev )
                    {
                        $ali_len = $byt_pos - $ali_beg;

                        $index{ $ali_id_prev } = "$ali_beg\t$ali_len";
                        $buf_count += 20;
                        
                        $ali_id_prev = $ali_id;
                        $ali_beg = $byt_pos;
                        $ali_len = 0;
);
    $code .= qq (\n                        \$ali_count += 1;\n) if $count_alis;
    $code .= q (                    }
                }
                else {
                    chomp $line;
                    &error( qq (No match with '$hdr_regexp' -> "$line") );
                }
);
    
    if ( $want_seqs )
    {
        if ( $want_seqents )
        {
            $code .= q (
                $seq_beg = $byt_pos;
                $seq_len = $line_len;
            }
            else {
                $seq_len += $line_len;
);
        }
        else
        {
            $code .= q (            }
            else {
                $seq_beg = $byt_pos;
                $seq_len = $line_len - 1;
);
        }
    }
            
    $code .= q (            }

            $byt_pos += $line_len;

            last if $buf_count > $buf_size;
        }

        last if not %index;

        &Common::DBM::put_bulk( $ofh, \%index );
    }
);

    if ( $want_seqs )
    {
        if ( $want_seqents ) 
        {
            $code .= q (
    $seq_len = $byt_pos - $seq_beg;
);
        } 
        else
        {
            $code .= q (
    $seq_len = $byt_pos - $seq_beg - 1;
);
        }            

        $code .= q (    $index{ "$ali_id:$seq_id" } = "$seq_beg\t$seq_len";
);
    }

    $code .= q (
    $ali_len = $byt_pos - $ali_beg;
    $index{ $ali_id } = "$ali_beg\t$ali_len";

    &Common::DBM::put_bulk( $ofh, \%index );
);

    $code .= qq (    \$ali_count += 1;\n\n) if $count_alis;
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $byt_pos = 0;

    $ali_beg = 0;
    $ali_len = 0;

    $seq_beg = 0;
    $seq_len = 0;

    eval $code;

    if ( $@ ) {
        &error( $@ );
    }
    
    $counts = { "ali_count" => $ali_count, "seq_count" => $seq_count };

    return wantarray ? %{ $counts } : $counts;
}

sub create_index_stockholm
{
    # Niels Larsen, April 2011.
    
    # Indexes whole stockholm formatted alignments, but not sequences. 

    my ( $ifh,    # Alignment input file handle
         $ofh,    # Index output file handle
         $args,   # Arguments hash
        ) = @_;
    
    # Returns nothing.

    my ( $defs, $buf_size, $buf_count, %index, $byt_pos, $byt_len, $ali_id_prev,
         $hdr_regexp, $ali_id, $ali_len, $line, $format, $counts, $count_alis,
         $ali_count );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "hdr_regex" => undef,
        "buf_size" => undef,
        "count_alis" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $hdr_regexp = $args->hdr_regex;
    $buf_size = $args->buf_size;

    $count_alis = $args->count_alis;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $byt_pos = 0;
    $ali_len = 0;

    $ali_count = 0;

    while ( 1 )
    {
        %index = ();
        $buf_count = 0;
        
        while ( defined ( $line = <$ifh> ) )
        {
            $ali_count += 1;

            if ( $line =~ /^# S/ )
            {
                if ( defined $ali_id )
                {
                    $index{ $ali_id } = "$byt_pos\t$ali_len";
                    
                    $buf_count += 20;

                    $byt_pos += $ali_len;
                    $ali_len = 0;
                }
            }
            elsif ( $line =~ /^#/ and $line =~ /^#=GF\s+ID\s+(\S+)/ )
            {
                $ali_id = $1;
            }

            $ali_len += length $line;

            last if $buf_count > $buf_size;
        }

        last if not %index;

        &Common::DBM::put_bulk( $ofh, \%index );
    }

    $index{ $ali_id } = "$byt_pos\t$ali_len";
    &Common::DBM::put_bulk( $ofh, \%index );

    if ( $count_alis ) 
    {
        $counts = { "ali_count" => $ali_count };
        return wantarray ? %{ $counts } : $counts;
    }

    return;
}

sub create_indices
{
    # Niels Larsen, April 2011.
    
    # Creates ali_fetch storage. Call this routine, not the other ones in here,
    # they are just helper routines. 
    
    my ( $args,
         $msgs,
	) = @_;

    # Returns nothing.
    
    my ( $defs, $clobber, @ifiles, $ifile, @ofiles, $ofile, $conf, $dbh,
         $ifh, $i, $tmp_output, $params, $oname, $key_count, $usr_format,
         @istats, $istat, @msgs, $file, $ndx_code, $pct, $buf_size,
         $ndx_stats, $iname, $msg, $ndx_routine, $addmode, $seq_fields,
         $seq_num, $seq_count, $key_diff, $stats, $id_len, $ali_num, $counts,
         $format, $ali_idlen, $seq_idlen, $hdr_regex, %key_types, $with_seqs,
         $count_alis, $count_seqs );
    
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifiles" => [],
        "seqents" => undef,
        "seqstrs" => undef,
        "regexp" => undef,
        "suffix" => undef,
        "alimax" => undef,
        "aidlen" => undef,
        "seqmax" => undef,
        "sidlen" => undef,
        "clobber" => 0,
        "silent" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    $clobber = $args->clobber;
    $hdr_regex = $args->regexp;

    $buf_size = 10_000;
    
    $Common::Messages::silent = $args->silent;

    # Return a simple configuration hash while checking for simple errors. If
    # there are error(s) this call exits with message(s),

    $conf = &Ali::Storage::process_index_args( $args );

    $with_seqs = &Ali::Storage::count_seq_keys( $conf->key_types );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> INDEXING FILE LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<
     
    &echo_bold( "\nCreating indices:\n" );

    @ifiles = @{ $conf->ifiles };
    @ofiles = @{ $conf->ofiles };
    
    for ( $i = 0; $i <= $#ifiles; $i++ )
    {
        $ifile = $ifiles[$i];
        $ofile = $ofiles[$i];

	$iname = &File::Basename::basename( $ifile );
	$oname = &File::Basename::basename( $ofile );
        
        if ( defined $args->alimax )
        {
            # User values for things that determine size of index, which must 
            # be pre-dimensioned,

            $ali_num = $conf->ali_num;
            $seq_num = $conf->seq_num;

            $ali_idlen = $conf->ali_idlen;
            $seq_idlen = $conf->seq_idlen;

            $count_alis = 1;
            $count_seqs = 1 if $with_seqs;
        }
        else
        {
            # Same values, but measured by reading through the input,

            &echo( "   Measuring $iname ... " );
            
            $stats = &Ali::Storage::measure_ali(
                $ifile,
                { 
                    "hdr_regex" => $hdr_regex,
                    "key_types" => $conf->key_types,
                });

            $ali_num = $stats->ali_num;
            $seq_num = $stats->seq_num;

            $ali_idlen = $stats->ali_idlen;
            $seq_idlen = $stats->ali_idlen;
            
            if ( &Ali::Storage::count_seq_keys( $conf->key_types ) ) {
                &echo_done( "$ali_num alignment[s], $seq_num sequence[s]\n" );
            } else {
                &echo_done( "$ali_num alignment[s]\n" );
            }

            $count_alis = 0;
            $count_seqs = 0;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> SET PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Configuring $oname ... " );

        $params = &Ali::Storage::set_kyoto_params(
            $ifile,
            {
                "ali_num" => $ali_num,
                "ali_idlen" => $ali_idlen,
                "seq_num" => $seq_num,
                "seq_idlen" => $seq_idlen,
                "key_types" => $conf->key_types,
            });

        &echo_done( "done\n" );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo( "   Indexing $iname ... " );

        # Write to a ".file" in the output directory and rename below,
            
        $tmp_output = &File::Basename::dirname( $ofile ) ."/.$oname";
        &Common::File::delete_file_if_exists( $tmp_output );

        $dbh = &Common::DBM::write_open( $tmp_output, "params" => $params );
        
        $format = &Ali::IO::detect_format( $ifile );

        $counts = &Ali::Storage::create_index(
            $ifile,
            $dbh,
            {
                "buf_size" => $buf_size,
                "hdr_regex" => $hdr_regex,
                "key_types" => $conf->key_types,
                "format" => $format,
                "count_alis" => $count_alis,
                "count_seqs" => $count_seqs,
            });

        if ( defined $counts->{"ali_count"} ) {
            $ali_num = $counts->{"ali_count"};
        }

        if ( defined $counts->{"seq_count"} ) {
            $seq_num = $counts->{"seq_count"};
        }
        
        $seq_num = undef if not $with_seqs;

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $ndx_stats = &Ali::Storage::get_index_stats( $dbh );

        $key_count = $ndx_stats->key_count;

        &Ali::Storage::set_index_config(
            $dbh,
            "ali_file" => $ifile,
            "ali_format" => $format,
            "ali_count" => $ali_num,
            "seq_count" => $seq_num,
            "ndx_keys" => $key_count,
            "ndx_size" => $ndx_stats->file_size,
            "ndx_file" => $ofile,
            "key_types" => $conf->key_types,
            "kyoto_params" => $params,
            );
    
        # >>>>>>>>>>>>>>>>>>>>>>>>> CLOSE AND PRINT <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &Common::DBM::flush( $dbh );
        &Common::DBM::close( $dbh );
        
        # Delete old index and move new into place,

        &Common::File::delete_file_if_exists( $ofile ) if $clobber;
        &Common::File::rename_file( $tmp_output, $ofile );

        # Print some screen info,

        if ( $with_seqs ) {
            &echo_done( "$ali_num alignment[s], $seq_num sequence[s]\n" );
        } else {
            &echo_done( "$ali_num alignment[s]\n" );
        }            
    }

    &echo_bold( "Finished\n\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> HELPFUL COMMENTS <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $with_seqs ) {
        push @msgs, ["INFO", qq (Alignments and sequences in these files can be fetched with ali_fetch.) ];
    } else {
        push @msgs, ["INFO", qq (Alignments in these files can be fetched with ali_fetch.) ];
    }        
    
    &echo_messages( \@msgs );

    return scalar @ofiles;
}

sub default_regex
{
    # Niels Larsen, April 2011.

    # Returns the default regular expression for parsing the header of a fasta
    # like file. 

    my ( $format,    # Input format
         $types,     # Key types
        ) = @_;

    # Returns a string.

    my ( %exps, $count );

    # Uclust format,

    $exps{"uclust"} = '(\d+)\|[^\|]+\|(\S+)';

    # Fasta format,

    if ( $count = &Ali::Storage::count_seq_keys( $types // [] ) ) {
        $exps{"fasta"} = '([^:\s]+):(\S+)';
    } else {
        $exps{"fasta"} = '([^:\s]+)';
    }

    if ( not exists $exps{ $format } ) {
        &error( qq (Wrong looking format -> "$format") );
    }

    return $exps{ $format };
}

sub delete_indices
{
    # Niels Larsen, April 2011.

    # Deletes indices created by ali_index. 

    my ( $args,
         $msgs,
	) = @_;

    # Returns nothing.

    my ( $defs, @ifiles, $ifile,  @msgs, $count, $name, $suffix );
 
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "paths" => [],
        "suffix" => undef,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    @ifiles = @{ $args->paths };
    $suffix = $args->suffix // $Index_suffix;

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Ali::Storage::check_inputs_exist( \@ifiles, \@msgs );

    &append_or_exit( \@msgs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> EXCLUDE INDEX FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    @ifiles = grep { $_ !~ /$suffix$/ } @ifiles;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE INDICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( "\nDeleting indices:\n" );

    foreach $ifile ( @ifiles )
    {
        $count = 0;
        $name = &File::Basename::basename( $ifile );

        &echo( qq (   Deleting $name index ... ) );
        
        $count += &Common::File::delete_file_if_exists( ".$ifile$suffix" );
        $count += &Common::File::delete_file_if_exists( "$ifile$suffix" );
        
        if ( $count > 0 ) {
            &echo_green( "$count deleted\n" );
        } else {
            &echo_yellow( "none\n" );
        }
    }
    
    &echo_bold( "Finished\n\n" );
    
    return;
}

sub fetch_aliseq
{
    my ( $fhs,
         $loc,
         $bad,
         $msgs,
        ) = @_;

    return \&Ali::Storage::fetch_aliseqs(
        $fhs, 
        {
            "locs" => [[ $loc ]],
            "print" => 0,
        }, $bad, $msgs )->[0];
}

sub fetch_aliseqs
{
    # Niels Larsen, April 2011.

    # Prints alignments or sequences to output handle. UNFINISHED
    
    my ( $fhs,       # File handles or file string
         $args,      # Arguments hash
         $bads,      # Ids not found 
         $msgs,      # Output messages - OPTIONAL
        ) = @_;

    # Returns integer.

    my ( $defs, $locs, $key_types, $key_count, $byt_pos, $buf_str, $buf_len, 
         $ndx_handle, $ali_handle, $print, @out_strs, $ali_fhs,
         $out_handle, $key, $val, $offsets, $output_seqsub, $output_alisub, 
         $loc, $seq_id, $keys, $i, $seek_entsub, $seek_seqsub, $range, 
         $out_str );

    $defs = {
        "locs" => [],
        "locstrs" => [],
        "keytypes" => [],
        "print" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    if ( ref $fhs ) {
        $ali_fhs = $fhs;
    } else {
        $ali_fhs = &Ali::Storage::get_handles( $fhs );
    }

    $ndx_handle = $ali_fhs->ndx_handle;
    $ali_handle = $ali_fhs->ali_handle;
    
    $print = $args->print;
    $out_handle = $ali_fhs->out_handle if $print;
    
    $locs = $args->locs;
    $key_types = $args->keytypes;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE KEY STRINGS <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get seek positions and lengths from the index in one go. This may need 
    # to be split up if there are not millions of keys,
    
    if ( @{ $args->locstrs } )
    {
        $keys = $args->locstrs;
        $locs = &Ali::Common::parse_locators( $keys );
    }
    else
    {
        foreach $loc ( @{ $locs } )
        {
            if ( defined $loc->[1] ) {
                push @{ $keys }, "$loc->[0]:$loc->[1]";
            } else {
                push @{ $keys }, $loc->[0];
            }
        }
    }

    $offsets = &Common::DBM::get_bulk( $ndx_handle, $keys );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SEEK ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $seek_entsub = sub {
        seek( $ali_handle, $byt_pos, SEEK_SET );
        read( $ali_handle, $out_str, $buf_len );
    };

    $seek_seqsub = sub
    {
        $out_str = "";

        foreach $range ( @{ $loc->[2] } )
        {
            seek( $ali_handle, $byt_pos + $range->[0], SEEK_SET );
            read( $ali_handle, $buf_str, $range->[1] );
            
            if ( $range->[2] eq "-" ) {
                $out_str .= ${ &Seq::Common::complement_str( \$buf_str ) };
            } else {
                $out_str .= $buf_str;
            }
        }
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $print )
    {
        if ( grep { $_ eq "seq_strs" } @{ $key_types } )
        {
            $output_seqsub = sub { 
                $seq_id = &Seq::Common::format_locator( [ $loc->[1], $loc->[2] ] );
                $out_handle->print( "$loc->[0]:$seq_id\t$out_str\n" );
            };
        }
        else {
            $output_seqsub = sub { $out_handle->print( $out_str ); };
        }
        
        $output_alisub = sub { $out_handle->print( $out_str ); };
    }
    else 
    {
        $output_seqsub = sub { push @out_strs, $out_str; };
        $output_alisub = sub { push @out_strs, $out_str; };
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FETCH VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $key_count = 0;

    for ( $i = 0; $i <= $#{ $locs }; $i += 1 )
    {
        $loc = $locs->[$i];
        $key = $keys->[$i];

        if ( defined ( $val = $offsets->{ $key } ) )
        {
            ( $byt_pos, $buf_len ) = split "\t", $val;
    
            if ( defined $loc->[1] )
            {
                if ( defined $loc->[2] ) {
                    $seek_seqsub->();
                } else {
                    $seek_entsub->();
                }
                    
                $output_seqsub->();
            }
            else
            {
                $seek_entsub->();
                $output_alisub->();
            }

            $key_count += 1;
        }
        else {
            push @{ $bads }, $key;
        }
    }

    if ( not ref $fhs ) {
        &Ali::Storage::close_handles( $ali_fhs );
    }

    if ( $print ) {
        return $key_count;
    }

    return wantarray ? @out_strs : \@out_strs;
}

sub fetch_cmdline
{
    # Niels Larsen, April 2011.
    
    # Fetches alignments or sequences from a given indexed alignment file 
    # created with ali_index. Alignments are printed as is, and sequences are
    # printed as a table. Kyoto Cabinet is used as store, and there is one 
    # index file per data file. 
    
    my ( $from,       # Input sequence file or Ali::IO handle
         $args,       # Arguments hash
	) = @_;

    # Returns list.

    my ( $defs, $locs, $conf, $loc_count, $bad_ids, $msgs, $id, $seq_count, 
         $bad_count, $err_handle, $out_count, @msgs, $fhs );

    local $Common::Messages::silent;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $defs = {
        "loclist" => [],
        "locfile" => undef,
#        "ssize" => 4_000_000,
        "outfile" => undef,
        "errfile" => undef,
        "getsize" => 100,
        "clobber" => 0,
        "append" => 0,
        "silent" => 0,
        "stdin" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>> PROCESS ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $conf = &Ali::Storage::process_fetch_args( $from, $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> GET HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $fhs = &Ali::Storage::get_handles( $from, { "access" => "read" } );
    
    if ( $args->append ) {
        $fhs->{"out_handle"} = &Common::File::get_append_handle( $args->outfile );
    } else {
        &Common::File::delete_file_if_exists( $args->outfile ) if $args->outfile and $args->clobber;
        $fhs->{"out_handle"} = &Common::File::get_write_handle( $args->outfile );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ LOCATORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( "\nFetching alignments:\n" );
    
    # Get both ARGV list, and from file and STDIN if given,

    &echo( qq (   Reading locators ... ) );

    $conf = &Ali::Storage::get_index_config( $fhs->ndx_handle );

    $locs = &Ali::Storage::read_locators(
        {
            "keytypes" => $conf->key_types,
            "loclist" => $args->loclist,
            "locfile" => $args->locfile,
            "stdin" => $args->stdin,
        }, $conf, \@msgs );
    
    if ( @msgs ) {
        &echo( "\n" );
        &append_or_exit( \@msgs );
    }
    
    $loc_count = scalar @{ $locs };
    &echo_done( "$loc_count\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FETCH SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $bad_ids = [];      # Will be filled with input ids with no match

    &echo( qq (   Fetching entries ... ) );

    $out_count = &Ali::Storage::fetch_aliseqs( 
        $fhs,
        {
            "locs" => $locs,
            "keytypes" => $conf->key_types,
            "print" => 1,
        }, 
        $bad_ids, $msgs );
    
    &echo_done( "$out_count\n" );
        
    &Ali::Storage::close_handles( $fhs );

    &echo_bold( "Finished\n\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>> ERRORS AND MISSING IDS <<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( @{ $bad_ids } ) 
    {
        local $Common::Messages::silent = 0;
        
        $bad_count += scalar @{ $bad_ids };
        
        if ( $args->errfile )
        {
            if ( $args->append ) {
                $err_handle = &Common::File::get_append_handle( $args->errfile );
            } else {
                $err_handle = &Common::File::get_write_handle( $args->errfile, "clobber" => $args->clobber );
            }
            
            map { $err_handle->print( qq (ERROR\tID not found -> "$_"\n) ) } @{ $bad_ids };
            map { $err_handle->print( qq ($_->[0]\t$_->[1]\n) ) } @{ $msgs };

            &Common::File::close_handle( $err_handle );

            &echo_messages( [["WARNING", &done_string( "$bad_count [id was|ids were] not found. See the error file." ) ]] );
        }
        else {
            &echo_messages( [["WARNING", &done_string( "$bad_count [id was|ids were] not found") ]] );
        }
    }

    return;
}

sub get_handles
{
    # Niels Larsen, March 2011.

    # Returns a Ali::Storage object with these accessors,
    # 
    #  ali_file        Alignment file
    #  ali_handle      Alignment handle
    #  ndx_file        Index file
    #  ndx_handle      Index handle
    # 
    # A hash is optional that sets read/write/append mode and the type of 
    # index (hash and btree are recognized). The last argument returns error
    # messages, otherwise the routine exits with fatal error. 

    my ( $file,   # Alignment file name
         $args,   # Argument hash - OPTIONAL
         $msgs,   # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns Ali::Storage object.

    my ( $defs, $access, $fh, $routine, @msgs, $params, $suffix );
    
    # Arguments,

    $defs = {
        "access" => "read",
        "suffix" => $Index_suffix,
    };

    $args = &Registry::Args::create( $args, $defs );

    $access = $args->access;
    $suffix = $args->suffix;

    if ( $access !~ /^read|write|append$/ ) {
        &error( qq (Wrong looking access mode -> "$access". Choices are read, write, append.) );
    }
    
    no strict "refs";

    # Alignment file,

    $file = &Common::File::full_file_path( $file );

    $routine = "Common::File::get_$access". "_handle";

    $fh->{"ali_file"} = $file;
    $fh->{"ali_handle"} = &{ $routine }( $file );

    # Index file,
    
    if ( &Ali::Storage::is_indexed( $file, { "suffix" => $suffix } ) )
    {
        $fh->{"ndx_file"} = &Common::File::resolve_links( "$file$suffix" );
        
        # Kyoto does not save all parameters in the index file. So we must get
        # them from the datafile, and then open kyoto for the second time ..

        $params = &Ali::Storage::get_index_config( $fh->{"ndx_file"} )->kyoto_params;

        $routine = "Common::DBM::$access"."_open";
        $fh->{"ndx_handle"} = &{ $routine }( $fh->{"ndx_file"}, "params" => $params );

    }
    else
    {
        $fh->{"ndx_handle"} = undef;

        push @msgs, ["ERROR", qq (Alignment file is not indexed -> "$file") ];
        push @msgs, ["info", qq (See the ali_index command) ];
    }

    &append_or_exit( \@msgs, $msgs );

    return bless $fh;
}

sub get_index_config
{
    # Niels Larsen, March 2011. 

    # Read the stores configuration hash.

    my ( $dbh,      # Index file or handle
        ) = @_;

    # Returns a hash.

    my ( $conf, $fh );

    if ( ref $dbh ) {
        $fh = $dbh;
    } else {
        $fh = &Common::DBM::read_open( $dbh );
    }

    $conf = &Common::DBM::get_struct( $fh, "__CONFIG__", 0 );

    if ( not ref $dbh ) {
        &Common::DBM::close( $fh );
    }

    if ( defined $conf ) {
        return bless $conf;
    }

    return;
}

sub get_index_stats
{
    # Niels Larsen, February 2011.

    # Given en index handle, returns a hash with these keys: "rec_count", 
    # "file_size", "file_path" and "status". 

    my ( $file,     # Index file or handle 
        ) = @_;

    # Returns a hash.
    
    my ( $stats, $dbh );

    if ( ref $file ) {
        $dbh = $file;
    } else {
        $dbh = &Common::DBM::read_open( $file );
    }

    $stats = {
        "key_count" => $dbh->count,
        "file_size" => $dbh->size,
        "file_path" => $dbh->path,
        "status" => $dbh->status,
    };

    if ( &Ali::Storage::get_index_config( $dbh ) )
    {
        $stats->{"key_count"} -= 1;
    }

    bless $stats;

    if ( not ref $file ) {
        &Common::DBM::close( $dbh );
    }

    return wantarray ? %{ $stats } : $stats;
}

sub key_types_info
{
    # Niels Larsen, February 2011. 
    
    # Returns key-type information. If a key name is given, a hash with info
    # for that key is returned, if none given a hash with all types is returned.
    # If a field is given also, the value for that field is returned.
    # 
    # title          Short description of the key
    # formats        Accepted input formats
    # routine        Indexing routine name

    my ( $name,       # Key name
         $field,      # Index info field - OPTIONAL
         $msgs,       # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns hash, list or scalar.

    my ( %info, $info, $val, $choices, @msgs );

    %info = (
        "ali_ents" => {
            "title" => "Whole alignment entries (ali_ents)",
            "formats" => [ "fasta_wrapped", "fasta", "uclust", "stockholm" ],
            "routine" => "create_index_ali",
        },
        "seq_ents" => {
            "title" => "Whole sequence entries (seq_ents)",
            "formats" => [ "fasta", "uclust" ],
            "routine" => "create_index_aliseq",
        },
        "seq_strs" => {
            "title" => "Aligned sequence strings (seq_strs)",
            "formats" => [ "fasta", "uclust" ],
            "routine" => "create_index_aliseq",
        });

    %info = map { $_, bless $info{ $_ } } keys %info;

    if ( defined $name )
    {
        if ( defined ( $info = $info{ $name } ) )
        {
            if ( defined $field )
            {
                $val = $info->$field;   # Will crash if field does not exist
                
                if ( ref $val ) {
                    return wantarray ? @{ $val } : $val;
                } else {
                    return $val;
                }
            }
            else {
                return $info;
            }
        }
        else
        {
            $choices = join ", ", sort keys %info;
            push @msgs, ["ERROR", qq (Unrecognized index type -> "$name") ];
            push @msgs, ["info", qq (Choices are: $choices.) ];
        }

        &append_or_exit( \@msgs, $msgs );
    }
    
    return wantarray ? %info : \%info;
}

sub key_types_values
{
    # Niels Larsen, February 2011.

    # Returns a uniqified list of all values of a given field in the info
    # hash. 

    my ( $field,    # Info hash field
         $filter,   # Info key filter
        ) = @_;

    # Returns list.

    my ( @names, $info, $name, $val, @list );

    $info = &Ali::Storage::key_types_info();

    @names = keys %{ $info };

    if ( defined $filter ) {
        @names = grep /$filter/, @names;
    }
    
    foreach $name ( @names )
    {
        $val = $info->{ $name }->$field;
        
        if ( ref $val ) {
            push @list, @{ $val };
        } else {
            push @list, $val;
        }
    }

    @list = &Common::Util::uniqify( \@list );

    return wantarray ? @list : \@list;
}

sub is_indexed
{
    # Niels Larsen, March 2011.

    # Given a data file, returns true if there is a corresponding index file 
    # that satisfies the given conditions. Conditions can be file modification 
    # date, file suffix and indexing keys in combination. The given data file 
    # must exist.

    my ( $file,             # Input file path
	 $args,             # Conditions to check
         ) = @_;

    # Returns 1 or nothing.

    my ( $defs, $suffix, @msgs, @keys, $dbh, $conf, %ndx_keys, $key, $ndx_date,
         $dat_file, $ndx_file );

    $defs = {
        "date" => undef,
        "suffix" => $Index_suffix,
        "keys" => [],
    };

    $args = &Registry::Args::create( $args // $defs, $defs );

    $suffix = $args->suffix;

    if ( not -r $file ) {
        &error( qq (File does not exist -> "$file") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SUFFIX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    return if not -s "$file$suffix";
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $dat_file = &Common::File::resolve_links( $file, 1 );
    $ndx_file = &Common::File::resolve_links( "$file$suffix", 1 );
    
    $ndx_date = $args->date // -M $ndx_file;  
    
    return if $ndx_date > -M $dat_file;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> KEYS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( @{ $args->keys } )
    {
        $dbh = &Common::DBM::read_open( "$file$suffix" );
        
        $conf = &Ali::Storage::get_index_config( $dbh );
        
        &Common::DBM::close( $dbh );

        %ndx_keys = map { $_, 1 } @{ $conf->key_types };

        if ( grep { not exists $ndx_keys{ $_ } } @{ $args->keys } )
        {
            return;
        }
    }
        
    # If none of the above tests fail then return true,
    
    return 1;
}

sub measure_ali
{
    # Niels Larsen, April 2011. 

    # Creates counts needed for dimensioning the Kyoto Cabinet index. An object
    # is returned with these keys,
    # 
    #  ali_num       Total number of alignments
    #  seq_num       Total number of sequences
    #  ali_idlen     Average length of alignment ids
    #  seq_idlen     Average length of sequence ids

    my ( $file,
         $args,
        ) = @_;

    # Returns object.

    my ( $defs, $format, $seq_min, $fh, $counts, $hdr_regex );

    $defs = {
        "format" => undef,
        "key_types" => [],
        "hdr_regex" => undef,
        "hdr_fields" => undef,
    };
    
    $args = &Registry::Args::create( $args // $defs, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GUESS FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not ( $format = $args->format ) )
    {
        $format = &Ali::IO::detect_format( $file );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $format eq "stockholm" )
    {
        $counts = &Ali::Storage::measure_ali_stockholm( $file );
    }
    elsif ( $format =~ /^fasta|fasta_wrapped|uclust$/ )
    {
        $hdr_regex = $args->hdr_regex // &Ali::Storage::default_regex( $format, $args->key_types );

        $counts = &Ali::Storage::measure_ali_fasta(
            $file,
            {
                "hdr_regex" => $hdr_regex,
            });
    }
    else {
        &error( qq (Unrecognized format -> "$format") );
    }

    return wantarray ? %{ $counts } : $counts;
}

sub measure_ali_fasta
{
    # Niels Larsen, April 2011.

    # Creates counts needed for dimensioning the Kyoto Cabinet index. An object
    # is returned with these keys,
    # 
    #  ali_num       Total number of alignments
    #  seq_num       Total number of sequences
    #  ali_idlen     Average length of alignment ids
    #  seq_idlen     Average length of sequence ids

    my ( $file,       # File path
         $args,       # Arguments 
        ) = @_;

    # Returns object.
    
    my ( $defs, $seq, $fh, $ali_id, $seq_id, $ali_id_last, $seq_min, $counts, 
         $routine, $hdr_exp, $seq_num, $ali_num, $ali_idlen, $seq_idlen, $line );

    $defs = {
        "hdr_regex" => undef,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    $hdr_exp = $args->hdr_regex;
    
    $fh = &Common::File::get_read_handle( $file );

    $ali_id_last = "";
    $seq_num = 0;
    
    while ( defined ( $line = <$fh> ) )
    {
        if ( $line =~ /^>/ )
        {
            if ( $line =~ /^>$hdr_exp/o )
            {
                ( $ali_id, $seq_id ) = ( $1, $2 );
                
                if ( $ali_id ne $ali_id_last )
                {
                    $ali_num += 1;
                    $ali_idlen += length $ali_id;
                    
                    $ali_id_last = $ali_id;
                }
                
                $seq_num += 1;
                $seq_idlen += length $seq_id if defined $seq_id;
            }
            else {
                &Common::File::close_handle( $fh );
                chomp $line;
                &error( qq (No match with '$hdr_exp' -> "$line") );
            }
        }
    }

    &Common::File::close_handle( $fh );

    $counts = bless {
        "ali_num" => $ali_num,
        "ali_idlen" => int ( $ali_idlen / $ali_num ) + 1,
        "seq_num" => $seq_num,
        "seq_idlen" => int ( ($seq_idlen // 0) / $seq_num ) + 1,
    };

    return wantarray ? %{ $counts } : $counts;
}

sub measure_ali_stockholm
{
    # Niels Larsen, April 2011. 

    # Creates counts needed for dimensioning the Kyoto Cabinet index. An object
    # is returned with these keys,
    # 
    #  ali_num       Total number of alignments
    #  seq_num       Total number of sequences
    #  ali_idlen     Average length of alignment ids
    #  seq_idlen     Average length of sequence ids

    my ( $file,       # File path
        ) = @_;

    # Returns object.

    my ( $defs, $seq, $fh, $ali_id, $seq_id, $ali_id_last, $seq_min, $counts, 
         $routine, $hdr_exp, $seq_num, $ali_num, $ali_idlen, $seq_idlen, $line );

    $fh = &Common::File::get_read_handle( $file );

    $ali_id_last = "";
    $seq_num = 0;
    
    while ( defined ( $line = <$fh> ) )
    {
        if ( $line =~ /^# S/ )
        {
            # Get alignment name,

            while ( defined ( $line = <$fh> ) )
            {
                if ( $line =~ /^#=GF ID\s+(\S+)/ )
                {
                    $ali_id = $1;

                    $ali_num += 1;
                    $ali_idlen += length $ali_id;

                    last;
                }
            }

            # Read down to first sequence block,

            while ( defined ( $line = <$fh> ) )
            {
                last if $line !~ /^#/;
            }

            $line = <$fh>;     # skip blank line

            # Read ids of first sequence block,

            while ( $line and $line =~ /^[^#]/ and $line =~ /^(\S+)/ )
            {
                $seq_id = $1;

                $seq_num += 1;
                $seq_idlen += length $seq_id;

                $line = <$fh>;
            }

            while ( $line !~ m|^//| )
            {
                $line = <$fh>;
            }
        }
    }

    &Common::File::close_handle( $fh );

    $counts = bless {
        "ali_num" => $ali_num,
        "ali_idlen" => int ( $ali_idlen / $ali_num ) + 1,
        "seq_num" => $seq_num,
        "seq_idlen" => int ( $seq_idlen / $seq_num ) + 1,
    };

    return wantarray ? %{ $counts } : $counts;
}

sub process_fetch_args
{
    # Niels Larsen, March 2011.

    # Returns a configuration hash with checked user arguments, plus more
    # derived fields filled in. If some user input is wrong, this routine 
    # prints it to console and exits. 

    my ( $afile,
         $args,
        ) = @_;
    
    # Returns a hash.

    my ( @msgs, $file, %args, $conf );

    $args{"get_size"} = $args->getsize;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILES AND HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sequence and index inputs,

    if ( $afile )
    {
        if ( -r $afile ) {
            $args{"ali_file"} = $afile;
        } else {
            push @msgs, ["ERROR", qq (Alignment file not readable -> "$afile") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (No input alignment file given) ];
    }

    &append_or_exit( \@msgs );
    
    # Optional locator file,
    
    if ( $file = $args->locfile ) 
    {
        if ( not -r $file ) {
            push @msgs, ["ERROR", qq (Locations file not readable -> "$file") ];
        }
    }

    # Optional output file, 

    if ( $file = $args->outfile ) 
    {
        if ( -r $file and not $args->clobber and not $args->append ) {
            push @msgs, ["ERROR", qq (Output file exists -> "$file") ];
        }
    }

    # Optional error file,

    if ( $file = $args->errfile ) 
    {
        if ( -r $file and not $args->clobber and not $args->append ) {
            push @msgs, ["ERROR", qq (Error file exists -> "$file") ];
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SEEK SIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#    $args{"seek_size"} = &Common::Util::expand_number( $args->ssize, \@msgs );

#    &append_or_exit( \@msgs );    
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Reduce the list of all formats to those supported by the index and then
    # check the user format against those. Get config hash from index,


    return wantarray ? %args : \%args;
}

sub process_index_args
{
    # Niels Larsen, March 2011.

    # Checks input arguments and converts and expands them to something that 
    # is convenient for the routines. If some user input is wrong, this routine 
    # prints a message to console and exits. Returns a configuration hash.

    my ( $args,
        ) = @_;
    
    # Returns a hash.

    my ( $key_type, $conf, @ifiles, $ifile, @msgs, $ndx_suffix, @formats, 
         $format, $title );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> CHECK INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Input files may not be duplicated and all must exist,
    
    @ifiles = &Common::File::full_file_paths( $args->ifiles, \@msgs );

    @ifiles = &Common::Util::uniq_check( \@ifiles, \@msgs );
    
    $conf->{"ifiles"} = &Ali::Storage::check_inputs_exist( \@ifiles, \@msgs );

    # Input files may not be compressed,

    foreach $ifile ( @ifiles )
    {
        if ( &Common::Names::is_compressed( $ifile ) )
        {
            push @msgs, ["ERROR", qq (Cannot index compressed file -> "$ifile") ];
        }
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET KEY TYPES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf->{"key_types"} = [ "ali_ents" ];

    if ( $args->seqents or $args->seqstrs )
    {
        if ( $args->seqents and $args->seqstrs ) {
            push @msgs, ["ERROR", qq (Please specify either --seqents or --seqstrs) ];
        } elsif ( $args->seqents ) {
            push @{ $conf->{"key_types"} }, "seq_ents";
        } else {
            push @{ $conf->{"key_types"} }, "seq_strs";
        }
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $key_type ( @{ $conf->{"key_types"} } )
    {
        @formats = &Ali::Storage::key_types_info( $key_type, "formats" );
        $title = &Ali::Storage::key_types_info( $key_type, "title" );

        foreach $ifile ( @ifiles )
        {
            $format = &Ali::IO::detect_format( $ifile );
            
            if ( not $format ~~ @formats ) {
                push @msgs, ["ERROR", qq ("$title" index incompatible with -> "$ifile") ];
            }
        }
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> INDEX KEYS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If the number of index keys is set, then use it, otherwise count alignments
    # and sequences in &create_input_stats,

    if ( $args->alimax ) {
        $conf->{"ali_num"} = &Common::Util::expand_number( $args->alimax, \@msgs );
    } else {
        $conf->{"ali_num"} = undef;
    }

    $conf->{"ali_idlen"} = $args->aidlen;

    if ( defined $conf->{"ali_num"} and not defined $conf->{"ali_idlen"} ) {
        push @msgs, ["ERROR", qq (Average alignment id length must be given with number of alignments) ];
    }    

    if ( $args->seqmax ) {
        $conf->{"seq_num"} = &Common::Util::expand_number( $args->seqmax, \@msgs );
    } else {
        $conf->{"seq_num"} = undef;
    }

    $conf->{"seq_idlen"} = $args->sidlen;

    if ( defined $conf->{"seq_num"} and not defined $conf->{"seq_idlen"} ) {
        push @msgs, ["ERROR", qq (Average sequence id length must be given with number of sequences) ];
    }    

    if ( defined $conf->{"seq_num"} and not defined $conf->{"ali_num"} ) {
        push @msgs, ["ERROR", qq (When number of sequences are given, number of alignments must be too) ];
    }

    &append_or_exit( \@msgs );    
    
    # >>>>>>>>>>>>>>>>>>>>>> SET DEFAULT OUTPUT SUFFIX <<<<<<<<<<<<<<<<<<<<<<<<

    # If no suffix given, pick the default,
    
    $ndx_suffix = $args->suffix || $Index_suffix;

    $conf->{"ndx_suffix"} = $ndx_suffix;

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If named index files are given, these become output. If not, then the 
    # output index files are derived from the inputs by adding a suffix,
    
    if ( not $args->clobber ) {
        &Ali::Storage::check_indices_exist( \@ifiles, $ndx_suffix, \@msgs );
    }
    
    $conf->{"ofiles"} = [ map { $_ . $ndx_suffix } @ifiles ];

    &append_or_exit( \@msgs );

    bless $conf;

    return $conf;
}

sub read_locators
{
    # Niels Larsen, April 2011.

    # Reads and validates locators.
    
    my ( $args,
         $conf,
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $defs, @msgs, $locs, %key_types );
    
    $defs = {
        "keytypes" => [],
        "loclist" => [],
        "locfile" => undef,
        "stdin" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );

    $locs = &Seq::IO::read_locators( $args->loclist, $args->locfile, $args->stdin, $msgs );

    $locs = &Ali::Common::parse_locators( $locs, $msgs );

    %key_types = map { $_, 1 } @{ $args->keytypes };

    if ( grep { defined $_->[2] } @{ $locs } and not $key_types{"seq_strs"} )
    {
        push @{ $msgs }, ["ERROR", qq (Sub-sequence locators found, but sequence-strings were not indexed) ];
        push @{ $msgs }, ["INFO", qq (Re-index and include the --seqstrs option) ];
    }
    elsif ( grep { defined $_->[1] } @{ $locs } and not ( $key_types{"seq_ents"} or $key_types{"seq_strs"} ) )
    {
        push @{ $msgs }, ["ERROR", qq (Sequence locators found, but sequences were not indexed) ];
        push @{ $msgs }, ["INFO", qq (Re-index with either the --seqents or --seqstrs option) ];
    }
    
    return wantarray ? %{ $locs } : $locs;
}

sub set_index_config
{
    # Niels Larsen, January 2011. 

    # USaves the stores configuration hash.

    my ( $dbh,    # Index file or handle
         %args,   # Key-values to be saved
        ) = @_;

    # Returns nothing.
    
    my ( $conf, $arg, $fh );

    if ( ref $dbh ) {
        $fh = $dbh;
    } else {
        $fh = &Common::DBM::write_open( $dbh );
    }

    $conf = &Ali::Storage::get_index_config( $fh );

    foreach $arg ( keys %args )
    {
        $conf->{ $arg } = $args{ $arg };
    }

    &Common::DBM::put_struct( $fh, "__CONFIG__", $conf );

    if ( not ref $dbh ) {
        &Common::DBM::close( $fh );
    }
    
    return;
}

sub set_kyoto_params
{
    # Niels Larsen, March 2011.

    # Tries to optize parameters for the btree version of the underlying 
    # key/value store, Kyoto Cabinet (see http://fallabs.com/kyotocabinet).
    # This routine sets the parameters according to file size, available 
    # ram, the number and average length of sequences. The idea is to 
    # propose settings that make KC work best under different constraints.
    # Authors comments are at the end of this file. Returns a hash with
    # parameters for KC's open statement.

    my ( $file,     # Sequence file path
         $args,     # Script arguments
        ) = @_;

    # Returns a hash.

    my ( $defs, $params, $seq_num, $mem_map, $bkt_num, $align, $page_cache, 
         $blk_pool, $ram_avail, $ndx_size, $new_size, $ali_num, $avg_poslen,
         $avg_alisize, $avg_seqsize, $ali_idlen, $seq_idlen, $add_size,
         $count );
    
    $defs = {
        "ali_num" => undef,
        "ali_idlen" => undef,
        "seq_num" => undef,
        "seq_idlen" => undef,
        "key_types" => [],
    };

    $args = &Registry::Args::create( $args, $defs );

    $ram_avail = &Common::OS::ram_avail();

    $ali_num = $args->ali_num;
    $ali_idlen = $args->ali_idlen;

    $seq_num = $args->seq_num;
    $seq_idlen = $args->seq_idlen;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TUNE_ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $align = 256;      # default 256
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FREE BLOCK POOL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $blk_pool = 10;    # default 10
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GUESS INDEX SIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $new_size = -s $file;
    
    # Indices must always have room for alignment id keys and their values. If
    # sequences are indexed too, then we add those on top,

    $avg_poslen = length ( sprintf "%i", $new_size / 2 ) + 1;
    $avg_alisize = length ( sprintf "%i", $new_size / $ali_num ) + 5;
    
    $ndx_size = $ali_num * ( $ali_idlen + 5 ) + $avg_poslen + $avg_alisize;

    if ( $count = &Ali::Storage::count_seq_keys( $args->key_types ) )
    {
        $avg_poslen = length ( sprintf "%i", $new_size / 2 ) + 1;
        $avg_seqsize = length ( sprintf "%i", $new_size / $seq_num ) + 5;

        $add_size = $seq_num * ( $seq_idlen + 5 ) + $avg_poslen + $avg_seqsize;
        $ndx_size += $count * $add_size;
    }
    
    $ndx_size = int $ndx_size;

    # >>>>>>>>>>>>>>>>>>>>>>> PAGE CACHE / MEMORY MAP <<<<<<<<<<<<<<<<<<<<<<<<<

    # This says "if page cache will fit into ram, then give Kyoto big page 
    # cache. If not, the it is better to set a high memory map",

    $mem_map = 64_000_000;
    $page_cache = 64_000_000;

    if ( $ndx_size + $mem_map < $ram_avail ) {
        $page_cache = $ndx_size;
    } else {
        $mem_map = $ndx_size;
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> TUNE_BUCKETS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Author says it should be "calculated by the number of pages" .. but
    # where is that info .. about 10% of the number of records ... 
    
    $bkt_num = int &List::Util::max( 1, ( $ali_num + $seq_num ) * 0.12 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET ALL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $params = {
        "apow" => $align,             # Alignment power
        "fpow" => $blk_pool,          # Free block pool
        "bnum" => $bkt_num,           # Bucket number
        "msiz" => $mem_map,           # Memory map size
        "pccap" => $page_cache,       # Page cache
        "opts" => "l",                # Index type
    };

    return wantarray ? %{ $params } : $params;
}

1;

__END__
