package Seq::Storage;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that create, delete and retrieve from local sequence storage. The
# underlying key/value store is Kyoto Cabinet, see http://fallabs.com
#
# The main routines callable from outside this module are,
#
#  create_indices       Creates fetch or dereplication storage
#  delete_indices       Deletes fetch or dereplication storage
#  dump_derep_seqs      Creates various outputs from dereplication storage
#  fetch_seqs           Retrieves sequences
#
# See the scripts seq_index, seq_unindex, seq_derep_dump and seq_fetch for 
# examples of how to call these. All other routines are callable too of course,
# but were written as helpers for these routines and scripts. 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use Time::Duration qw ( duration );

use File::Basename;
use Fcntl qw ( SEEK_SET SEEK_CUR SEEK_END );
use YAML::Syck;

use vars qw ( *AUTOLOAD );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::DBM;
use Common::Obj;

use Seq::Common;
use Seq::IO;
use Seq::Stats;

use Recipe::IO;
use Recipe::Stats;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# about_storage
# canonical_index_type
# check_index_type_string
# check_indices_exist
# check_indices_inputs
# check_input_formats
# check_inputs_exist
# check_output_format
# close_handles
# config_keys_all
# create_index_blast
# create_index_derep
# create_index_embed
# create_index_fixpos
# create_index_varpos
# create_indices
# create_indices_args
# create_indices_blast
# create_input_stats
# delete_index
# delete_indices
# dump_derep_seqs
# fetch_seqs
# fetch_seqs_entries
# fetch_seqs_order
# fetch_seqs_random
# fetch_seqs_random_embed
# fetch_seqs_random_fixpos
# fetch_seqs_random_varpos
# format_fields
# get_handles
# get_index_config
# get_index_stats
# index_info
# index_info_values
# index_seq_file
# index_types_all
# is_indexed
# max_qualities_C
# output_formats
# print_about_table
# process_dump_args
# process_fetch_args
# save_seqs_derep
# set_index_config
# set_kyoto_params
# set_rec_parser
# write_derep_stats
# write_derep_stats_sum
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our @Fields = qw ( seq_file seq_handle ndx_file ndx_type ndx_handle );
our %Fields = map { $_, 1 } @Fields;

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

use Inline C => "DATA";

Inline->init;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Index_suffix = ".fetch";

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub about_storage
{
    # Niels Larsen, February 2011. 

    # Creates a table of readable statistics about the storage. In void 
    # context this is printed, in non-void context a two-column table is 
    # returned.

    my ( $file,    # Storage file
        ) = @_;

    my ( $dbh, $conf, @table, $descr, $kyoto, @msgs );
    
    $dbh = &Common::DBM::read_open( $file, "fatal" => 0 );

    if ( not defined $dbh )
    {
        push @msgs, ["ERROR", qq (Not an index file -> "$file") ];
        push @msgs, ["INFO", qq (Specify an index file, not a data file) ];

        &append_or_exit( \@msgs );
    }
        
    $conf = &Seq::Storage::get_index_config( $dbh );

    &Common::DBM::close( $dbh );

    $descr = &Seq::Storage::index_info( $conf->ndx_type, "title" );
    $kyoto = $conf->kyoto_params;

    @table = (
        [ "", "" ],
        [ "Sequence file path", $conf->seq_file // "" ],
        [ "Sequence file format", $conf->seq_format // "" ],
        [ "Sequence count total", $conf->seq_count // "" ],
        [ "", "" ],
        [ "Storage description", $descr // "" ],
        [ "Storage key type", $conf->ndx_type ],
        [ "", "" ],
        [ "Kyoto Cabinet record size alignment power", $kyoto->{"apow"} ],
        [ "Kyoto Cabinet free block pool size", $kyoto->{"fpow"} ],
        [ "Kyoto Cabinet memory mapped region size", $kyoto->{"msiz"} ],
        [ "Kyoto Cabinet optional features", $kyoto->{"opts"} ],
        [ "Kyoto Cabinet page cache size", $kyoto->{"pccap"} ],
        [ "Kyoto Cabinet bucket number", $kyoto->{"bnum"} ],
        );

    if ( defined wantarray ) 
    {
        return wantarray? @table : \@table;
    }
    else {
        &Seq::Storage::print_about_table( \@table );
    }

    return;
}

sub canonical_index_type
{
    # Niels Larsen, February 2011. 

    # Returns an index type string in response to argument switches.

    my ( $args,       # Arguments object 
        ) = @_;
    
    # Returns string.

    my ( $prog_type, $ndx_type );

    $prog_type = $args->progtype;

    if ( $prog_type eq "derep" )
    {
        $ndx_type = "derep_seq";
    }
    elsif ( $prog_type eq "fetch" ) 
    {
        if ( $args->within ) {
            $ndx_type = "fetch_embed";
        } else {
            if ( $args->fixed ) {
                $ndx_type = "fetch_fixpos";
            } else {
                $ndx_type = "fetch_varpos";
            }
        }
    }
    else {
        &error( qq (Wrong looking program type -> "$prog_type") );
    }
    
    return $ndx_type;
}

sub check_index_type_string
{
    # Niels Larsen, January 2011.

    # Splits and checks the given type string. If "all" is among the 
    # types, return all valid types. 

    my ( $types,      # Types string 
         $msgs,       # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns nothing. 

    my ( %valid, @usr_types, $type, $count, @types );
    
    @usr_types = split /\s*[, ]+\s*/, lc $types;

    %valid = &Seq::Storage::index_types_all();
    $count = 0;

    foreach $type ( @usr_types )
    {
        if ( $type eq "all" )
        {
            push @types, map { @{ $valid{ $_ } } } keys %valid;
            last;
        }
        elsif ( not $valid{ $type } )
        {
            push @{ $msgs }, ["ERROR", qq (Wrong looking type -> "$type") ];
            $count += 1;
        }
        else {
            push @types, @{ $valid{ $type } };
        }
    }

    if ( $count > 0 ) {
        push @{ $msgs }, ["info", "Choices are: ". join ", ", ( sort keys %valid ) ];
    }

    return wantarray ? @types : \@types;
}

sub check_indices_exist
{
    # Niels Larsen, January 2011.
    
    # Checks if a given list of files have corresponding up to date indexes
    # of a given type. The index types and their suffixes are given in 
    # Seq::Storage::index_info. Returns nothing, but appends messages
    # to the given list or prints them and then exits.

    my ( $files,       # File list
         $type,        # Index type
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $file, @msgs );

    foreach $file ( @{ $files } )
    {
        if ( &Seq::Storage::is_indexed( $file, $type ) )
        {
            push @msgs, ["ERROR", qq (File is indexed -> "$file") ];
        }
    }

    if ( @msgs )
    {
        push @msgs, ["info", qq (The --clobber option forces creation of a new index.) ];
        &append_or_exit( \@msgs, $msgs );
    }

    return;
}

sub check_indices_inputs
{
    # Niels Larsen, February 2011.

    # Compares a list of input file properties with a list of index files, to 
    # 1) if the two lists are equally long, and 2) if the fields that exist in 
    # the index are also present in the files. 

    my ( $stats,     # File properties
         $ndcs,      # Index name list
         $msgs,      # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns nothing.

    my ( $i, $j, @msgs, @ndx_fields, %seq_fields, $field, $file );

    if ( ( $i = scalar @{ $ndcs } ) == ( $j = scalar @{ $stats } ) )
    {
        for ( $i = 0; $i <= $#{ $ndcs }; $i += 1 )
        {
            @ndx_fields = @{ &Seq::Storage::get_index_config( $ndcs->[$i] )->seq_fields };
            %seq_fields = map { $_, 1 } &Seq::Storage::format_fields( "required", $stats->[$i]->seq_format );
            
            foreach $field ( @ndx_fields )
            {
                if ( not $seq_fields{ $field } )
                {
                    $file = $stats->[$i]->file_path;
                    push @msgs, ["ERROR", qq (File missing required $field field -> "$file") ];
                }
            }
        }
    }
    else {
        &error( qq (File list is $j long, but there are $i indices) );
    }

    &append_or_exit( \@msgs, $msgs );

    return;
}

sub check_input_formats
{
    # Niels Larsen, February 2011.

    # 
    my ( $files,
         $formats,
         $msgs,
        ) = @_;

    my ( $file, %formats, $format, @msgs, $name );

    %formats = map { $_, 1 } @{ $formats };

    foreach $file ( @{ $files } )
    {
        $format = &Seq::IO::detect_format( $file );
        
        if ( not exists $formats{ $format } )
        {
            $name = &File::Basename::basename( $file );
            push @msgs, ["ERROR", qq (Unsupported format in $name -> "$format") ];
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return;
}

sub check_inputs_exist
{
    # Niels Larsen, January 2011.

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

sub check_output_format
{
    # Niels Larsen, February 2011.

    # Creates error message if the given output format is not supported, or
    # if the output format requires fields that are not in the data.

    my ( $outfmt,      # Output format
         $seqfmt,      # Original sequence format
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( @formats, @msgs, $choices, $outfld, %valid );
    
    @formats = &Seq::Storage::output_formats( $seqfmt );
    
    if ( $outfmt ~~ @formats )
    {
        # See if there are fields required by the output format that are 
        # not supported by the original sequence format,

        %valid = map{ $_, 1 } &Seq::Storage::format_fields( "valid", $seqfmt );
        
        foreach $outfld ( &Seq::Storage::format_fields( "required", $outfmt ) )
        {
            if ( not $valid{ $outfld } ) {
                push @msgs, ["ERROR", qq (Output format field not supported by $seqfmt -> "$outfld") ];
            }
        }
    }
    else 
    {
        $choices = join ", ", @formats;
        push @msgs, ["ERROR", qq (Unsupported output format -> "$outfmt".) ];
        push @msgs, ["info", qq (This $seqfmt sequence index supports $choices.) ];
    }

    &append_or_exit( \@msgs, $msgs );

    return;
}

sub close_handles
{
    # Niels Larsen, May 2011.

    # Closes an indexed sequence file handle.

    my ( $fh,
        ) = @_;

    &Common::File::close_handle( $fh->seq_handle );
    delete $fh->{"seq_handle"};
    
    if ( $fh->{"ndx_handle"} )
    {
        &Common::DBM::close( $fh->ndx_handle );
        delete $fh->{"ndx_handle"};
    }

    return $fh;
}

sub config_keys_all
{
    # Niels Larsen, February 2011.

    # Returns a reference hash of keys that make up the reserved __CONFIG__
    # record. The values are 1 if a key is mandatory and must have value, or
    # 0 if it is optional.

    my ( %keys );

    %keys = (
        "seq_file" => 0,
        "seq_fields" => 0,
        "seq_count" => 0,
        "ndx_keys" => 1,
        "ndx_mode" => 1,
        "kyoto_params" => 1,
        );

    return wantarray ? %keys : \%keys;
}

sub create_index_blast
{
    # Niels Larsen, February 2010.

    # Indexes a given fasta file for blast search, using the given output
    # path as prefix to the indexes. If a program name is given then the index will
    # be for that program, otherwise the default random access index is 
    # created. The clobber argument overwrites old index files, otherwise 
    # existing indexes causes crash.

    my ( $ifile,
         $oprefix,
         $args,
	) = @_;

    # Returns nothing.
    
    my ( $defs, $count, $protein, $clobber, $type, $cmd, $logflag );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "protein" => 0,
        "log" => 0,
        "clobber" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );
    
    $protein = $args->protein;
    $clobber = $args->clobber;
    $logflag = $args->log;
    
    if ( $protein ) {
        $type = "T";
    } else {
        $type = "F"; 
    }
    
    if ( $clobber ) {
        &Seq::Storage::delete_index_blast( $oprefix, $protein );
    }
    
    $cmd = "formatdb -p $type -i $ifile -n $oprefix -l $ifile.log";

    if ( &Common::OS::run3_command( $cmd ) )
    {
        if ( $logflag )
        {
            $count = 4;
        } 
        else 
        {
            &Common::File::delete_file( "$ifile.log" );
            $count = 3;
        }

        return $count;
    }

    return;
}

sub create_index_derep
{
    # Niels Larsen, December 2012.

    # Uniqifies completely identical sequences. If there are qualities, the best
    # are kept at each base positions. If there are read counts, these are added,
    # otherwise "1" is used as count. If output ids wanted, then original ids of
    # the dereplicated sequences are included. The routine fills a hash buffer 
    # and periodically updates the key/value storage. The buffer hash has this 
    # structure,
    # 
    # sequence => [ counts, qualities, ids ]
    #
    # where qualities and ids are empty strings if not present in the input.

    my ( $ifh,     # Input sequence handle
         $ofh,     # Output index handle
         $args,    # Arguments hash - OPTIONAL
        ) = @_;

    # Returns nothing. 

    my ( $buffer, $counts, $has_counts, $seqs, $tuple, $read_max, $seq, 
         $has_quals, $read_sub, $out_ids, $subref, $code );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $has_counts = $args->has_counts;
    $has_quals = $args->has_quals;
    $read_max = $args->read_max // 50_000;
    $read_sub = $args->read_sub;
    $out_ids = $args->out_ids;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $code = q (sub 
{
     my ( $buffer, $seq ) = @_;

     if ( not $buffer->{ $seq->{"seq"} } ) {
         $buffer->{ $seq->{"seq"} } = [ 0, "", "" ];
     }

     $tuple = $buffer->{ $seq->{"seq"} };

);

    if ( $has_counts )
    {
        $code .= q (
     $seq->{"info"} =~ /seq_count=(\d+)/;
     $tuple->[0] += $1 // 0;
);
    }
    else {
        $code .= q (     $tuple->[0] += 1 // 0;);
    }

    $code .= "\n";

    if ( $has_quals )
    {
        $code .= q (
     if ( $tuple->[1] ) {
          &Seq::Storage::max_qualities_C( \$tuple->[1], \$seq->{"qual"}, length $seq->{"qual"} );
     } else {
          $tuple->[1] = $seq->{"qual"};
     });
    }
    else {
        $code .= q (
     $tuple->[1] //= "";);
    }

    $code .= "\n";

    if ( $out_ids )
    {
        $code .= q (
     $tuple->[2] .= $seq->{"id"} ." ";);
    }
    else {
        $code .= q (
     $tuple->[2] //= "";);
    }

    $code .= qq (\n\};\n);

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    no strict "refs";

    $subref = eval $code;

    while ( $seqs = $read_sub->( $ifh, $read_max ) )
    {
        use strict;

        $buffer = {};

        foreach $seq ( @{ $seqs } )
        {
            $subref->( $buffer, $seq );
        }

        &Seq::Storage::save_seqs_derep( $ofh, $buffer );

        $counts->{"iseq"} += scalar @{ $seqs };
    }

    $counts->{"oseq"} = $counts->{"iseq"};

    return wantarray ? %{ $counts } : $counts;
}

sub create_index_embed
{
    # Niels Larsen, February 2011.

    # Creates a key/value storage where key is id and value is sequence and/or
    # quality, depending on original input format.

    my ( $ifh,     # Input fasta handle
         $ofh,     # Output index handle
         $args,    # Arguments hash - OPTIONAL
        ) = @_;

    # Returns nothing.
    
    my ( $index, $seq_format, $hdr_regex, $seqs, $read_max, $counts );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $seq_format = $args->seq_format;
    $hdr_regex = $args->hdr_regex // '(\S+)';
    $read_max = $args->read_max // 500;

    if ( $seq_format eq "fastq" )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTQ FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<

        while ( $seqs = &Seq::IO::read_seqs_fastq( $ifh, $read_max ) )
        {
            $index = {};
            
            map { $index->{ $_->{"id"} } = $_->{"seq"} ."\t". $_->{"qual"} } @{ $seqs };
            
            &Common::DBM::put_bulk( $ofh, $index );
        }
    }
    elsif ( $seq_format eq "fasta" )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTA FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        while ( $seqs = &Seq::IO::read_seqs_fasta( $ifh, $read_max ) )
        {
            $index = {};
            
            map { $index->{ $_->{"id"} } = ( $_->{"info"} // "" ) ."\t". $_->{"seq"} } @{ $seqs };
            
            &Common::DBM::put_bulk( $ofh, $index );
        }
    }
    else {
        &error( qq (Unsupported format -> "$seq_format") );
    }

    return;
}

sub create_index_varpos
{
    # Niels Larsen, January 2011.

    # Creates a index file for a given fasta file with sequences as single 
    # lines. The index file path is returned. 

    my ( $ifh,     # Input sequence handle
         $ofh,     # Output index handle
         $args,    # Arguments hash - OPTIONAL
        ) = @_;

    # Returns string. 

    my ( $conf, $index, $routine );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf = { 
        "readbuf" => ( $args->read_max // 1000 ),
        "filepos" => 0,
        "regex" => ( $args->hdr_regex // '.(\S+)' ),
    };

    $routine = "Seq::IO::read_seqs_". $args->{"seq_format"} ."_varpos";

    no strict "refs";

    while ( $index = &{ $routine }( $ifh, $conf ) )
    {
        &Common::DBM::put_bulk( $ofh, $index );
    }

    return;
}

sub create_index_fixpos
{
    # Niels Larsen, January 2011.

    # Creates a index file for a given fasta file with sequences as single 
    # lines. The index file path is returned. 

    my ( $ifh,     # Input sequence handle
         $ofh,     # Output index handle
         $args,    # Arguments hash - OPTIONAL
        ) = @_;

    # Returns string. 

    my ( $conf, $index, $routine );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf = { 
        "readbuf" => ( $args->{"read_max"} // 100 ),
        "seqnum" => 0,
        "regex" => ( $args->{"hdr_regex"} // '.(\S+)' ),
    };

    $routine = "Seq::IO::read_seqs_". $args->{"seq_format"} ."_fixpos";

    no strict "refs";

    while ( $index = &{ $routine }( $ifh, $conf ) )
    {
        &Common::DBM::put_bulk( $ofh, $index );
    }

    return;
}

sub create_indices
{
    # Niels Larsen, February 2010.
    
    # Creates fetch and dereplication storage. Can also add to dereplication
    # storage, but not yet to fetch storage. Call this routine, not the other
    # ones in here, they are just helper routines. 
    
    my ( $args,
         $msgs,
	) = @_;

    # Returns nothing.
    
    my ( $defs, $clobber, @ifiles, $ifile, @ofiles, $ofile, $conf, $dbh,
         $ifh, $i, $tmp_output, $params, $oname, $ndx_type, $stat_title,
         $usr_format, @istats, $istat, @msgs, $file, $ndx_code, $pct,
         $ndx_stats, $iname, $msg, $ndx_routine, $addmode, $seq_fields,
         $seq_num, $seq_count, $seq_diff, $seq_count_prev, $seq_counts,
         @sfiles, $sfile, $hdr_regex, $stats, $outfmt, $outsuf, $new_stats,
         $sname, $with_stats, $stat_type, $read_max, $time_start, $seconds,
         $text, $sfh, $read_sub );
    
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifiles" => [],
        "progtype" => "fetch",
        "ndxdir" => undef,
        "ndxsuf" => undef,
        "ndxadd" => 0,
        "regexp" => undef,
        "outfmt" => undef,
        "outids" => 0,
        "outdir" => undef,
        "outfile" => undef,
        "outsuf" => undef,
        "stats" => undef,
        "newstats" => undef,
        "within" => 0,
        "fixed" => 0,
        "seqmax" => undef,
        "readbuf" => undef,
        "count" => 1,
        "clobber" => 0,
        "silent" => 0,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    $addmode = $args->ndxadd;
    $clobber = $args->clobber;
    $hdr_regex = $args->regexp;
    $new_stats = defined $args->newstats;
    $read_max = $args->readbuf;

    $Common::Messages::silent = $args->silent;

    # Return a simple configuration hash while checking for simple errors. If
    # there are error(s) this call exits with message(s),

    $conf = &Seq::Storage::create_indices_args( $args );

    $with_stats = defined $conf->sfiles;

    &echo_bold( "\nCreating indices:\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>> DETECT FILE PROPERTIES <<<<<<<<<<<<<<<<<<<<<<<<<

    # Detect format, id length, number of sequences, and set record separator
    # and file header lead string,

    @ifiles = @{ $conf->ifiles };
    @ofiles = @{ $conf->ofiles };
    @sfiles = @{ $conf->sfiles } if $with_stats;
    
    @istats = &Seq::Storage::create_input_stats( \@ifiles, $conf, \@msgs );

    &append_or_exit( \@msgs );

    # In add-mode, check if all input files contain the fields required by 
    # the index,

    if ( $addmode )
    {
        &Seq::Storage::check_indices_inputs( \@istats, \@ofiles, \@msgs );
        &append_or_exit( \@msgs );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>> INDEXING FILE LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    for ( $i = 0; $i <= $#ifiles; $i++ )
    {
        $time_start = &time_start();

        $ifile = $ifiles[$i];
        $ofile = $ofiles[$i];
        $sfile = $sfiles[$i] if $with_stats;

        $istat = $istats[$i];
        
	$iname = &File::Basename::basename( $ifile );
	$oname = &File::Basename::basename( $ofile );

        if ( $addmode )
        {
            &echo( "   Add-indexing $oname ... " );
            $ndx_stats = &Seq::Storage::get_index_stats( $ofile )->status;
        }
        else
        {
            if ( $conf->ndx_type =~ /^derep/ ) {
                &echo( "   De-replicating $iname ... " );
            } else {
                &echo( "   Indexing $iname ... " );
            }

            $ndx_stats = undef;
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> SET PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $ndx_type = $istat->ndx_type;

        $params = &Seq::Storage::set_kyoto_params(
            $ifile,
            {
                "id_len" => $istat->id_len,
                "seq_format" => $istat->seq_format,
                "seq_num" => $istat->seq_num,
                "ndx_type" => $ndx_type,
                "ndx_stats" => $ndx_stats,
            });

        # >>>>>>>>>>>>>>>>>>>>>>>>>> OPEN HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $ifh = &Common::File::get_read_handle( $ifile );
        $read_sub = &Seq::IO::get_read_routine( $ifile, $istat->seq_format );

        if ( $addmode )
        {
            $dbh = &Common::DBM::write_open( $ofile, "params" => $params );
        }
        else
        {
            # Write to a ".file" in the output directory and rename below,
            
            $tmp_output = &File::Basename::dirname( $ofile ) ."/.$oname";
            &Common::File::delete_file_if_exists( $tmp_output );

            $dbh = &Common::DBM::write_open( $tmp_output, "params" => $params );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $seq_count_prev = &Seq::Storage::get_index_stats( $dbh )->seq_count;

        $ndx_routine = &Seq::Storage::index_info( $ndx_type, "routine" );

        {
            no strict "refs";
            
            &{ $ndx_routine }(
                $ifh,
                $dbh,
                bless {
                    "read_sub" => $read_sub,
                    "read_max" => $read_max,
                    "hdr_regex" => $hdr_regex,
                    "ndx_type" => $ndx_type,
                    "seq_format" => $istat->seq_format,
                    "has_counts" => $istat->has_counts,
                    "has_quals" => $istat->has_quals,
                    "out_ids" => $conf->out_ids,
                });
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SAVE INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $addmode ) {
            $seq_fields = &Seq::Storage::get_index_config( $dbh )->seq_fields;
        } else {
            $seq_fields = &Seq::Storage::format_fields( "required", $istat->seq_format );
        }            

        $ndx_stats = &Seq::Storage::get_index_stats( $dbh );

        $seq_count = $ndx_stats->seq_count;
        
        &Seq::Storage::set_index_config(
            $dbh,
            "seq_fields" => $seq_fields,
            "seq_format" => $istat->seq_format,
            "seq_count" => $seq_count,
            "seq_file" => $ifile,
            "ndx_keys" => $ndx_stats->key_count,            
            "ndx_type" => $ndx_type,
            "ndx_size" => $ndx_stats->file_size,
            "kyoto_params" => $params,
            );
    
        # >>>>>>>>>>>>>>>>>>>>>>>>>> CLOSE AND RENAME <<<<<<<<<<<<<<<<<<<<<<<<<
        
        &Common::DBM::flush( $dbh );
        &Common::DBM::close( $dbh );
        
        $ifh->close;

        if ( not $addmode )
        {
            # Delete old index and move new into place,

            &Seq::Storage::delete_index( $ofile, $ndx_type ) if $clobber;
            &Common::File::rename_file( $tmp_output, $ofile );
        }

        # Print some screen info,

        if ( $ndx_type =~ /^derep_/ )
        {
            $seq_diff = $seq_count - $seq_count_prev;
            &echo_done( "$seq_count key[s] total, $seq_diff new\n" );
        }
        else {
            &echo_done( "$seq_count sequence[s]\n" );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>> DEREPLICATION ONLY <<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $ndx_type =~ /^derep_/ )
        {
            $outsuf = $conf->out_suffix;

            &echo( qq (   Writing $oname$outsuf ... ) );
            
            $seq_counts = &Seq::Storage::dump_derep_seqs(
                {
                    "ifiles" => [ $ofile ],
                    "outfmt" => $conf->out_format,
                    "outids" => $conf->out_ids,
                    "outsuf" => $conf->out_suffix,
                    "clobber" => $clobber,
                    "silent" => 1,
                })->[0];
            
            &echo_done( "done\n" );
        }

        $seconds = &time_elapsed() - $time_start;

        &echo("   Run-time seconds ... ");
        &echo_done( (sprintf "%.2f", $seconds ) ."\n" );

        if ( $ndx_type =~ /^derep_/ and $with_stats )
        {
            # >>>>>>>>>>>>>>>>>>> DEREPLICATION STATISTICS <<<<<<<<<<<<<<<<<<<<
            
            # No statistics is done for regular indexing, as there is no filtering.
            # But de-replication reduces the number of sequences, or, creates very 
            # simple clusters. 
            
            $sname = &File::Basename::basename( $sfile );
            &echo( "   Writing $sname ... " );
            
            &Common::File::delete_file_if_exists( $sfile ) if $new_stats;
            
            $stats->{"name"} = "sequence-dereplication";
            $stats->{"title"} = "Sequence de-replication";
            
            $stats->{"iseqs"} = { "title" => "Input file", "value" => $ifile };
            # $stats->{"oseqs"} = { "title" => "Output file", "value" => "$ofile$outsuf" };
            $stats->{"oseqs"} = { "title" => "Output file", "value" => "$ofile" };
            
            $stats->{"steps"}->[0] = 
            {
                "iseq" => $seq_counts->seq_count_orig,
                "oseq" => $seq_counts->seq_count,
            };
            
            $stats->{"seconds"} = $seconds;
            $stats->{"finished"} = &Common::Util::epoch_to_time_string();
            
            $text = &Seq::Storage::write_derep_stats( $sfile, $stats );
            
            $sfh = &Common::File::get_append_handle( $sfile );
            $sfh->print( $text );
            &Common::File::close_handle( $sfh );
            
            &echo_done( "done\n" );
        }
    }

    &echo_bold( "Finished\n\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> HELPFUL COMMENTS <<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $ndx_type =~ /^derep_/ )
    {
        push @msgs, ["INFO", qq (De-replicated data storage can be accessed with seq_derep_dump.) ];
    }
    elsif ( defined $conf->seq_max or $seq_count eq $istat->{"seq_num"} )
    {
        push @msgs, ["INFO", qq (Sequences in these files can be fetched with seq_fetch.) ];
    }
    else {
        push @msgs, ["WARNING", qq (Conflicting sequence counts. Sure all records have same size?) ];
        push @msgs, ["info", qq (Omitting the --fixed argument should cure this.) ];
        
    }
    
    &echo_messages( \@msgs );

    return scalar @ofiles;
}

sub create_indices_args
{
    # Niels Larsen, January 2011.

    # Checks input arguments and converts and expands them to something that 
    # is convenient for the routines. If some user input is wrong, this routine 
    # prints a message to console and exits. Returns a configuration hash.

    my ( $args,
        ) = @_;
    
    # Returns a hash.

    my ( $prog_type, $ndx_type, $conf, @ifiles, @xfiles, @ofiles, $ndx_dir,
         %formats, $formats, $format, @msgs, $choices, $file, $ndx_suffix, 
         $i, $j, $stats_file, $out_dir );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CHECK INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Input files may not be duplicated and all must exist,
    
    @ifiles = &Common::File::full_file_paths( $args->ifiles, \@msgs );

    @ifiles = &Common::Util::uniq_check( \@ifiles, \@msgs );
    
    $conf->{"ifiles"} = &Seq::Storage::check_inputs_exist( \@ifiles, \@msgs );

    foreach $file ( @{ $conf->{"ifiles"} } )
    {
        if ( &Common::File::is_compressed( $file ) ) {
            push @msgs, ["ERROR", qq (File is compressed -> "$file") ];
        }
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>> SET DEFAULT INDEX TYPE <<<<<<<<<<<<<<<<<<<<<<<<<

    $ndx_type = &Seq::Storage::canonical_index_type( $args );

    if ( $ndx_type =~ /^derep_/ )
    {
        %formats = %{ &Seq::Storage::format_fields("valid") };
        $format = $args->outfmt;

        if ( $format and not $formats{ $format } )
        {
            $formats = join ", ", sort keys %formats;
            
            push @msgs, ["ERROR", qq (Wrong looking format -> "$format") ];
            push @msgs, ["HELP", qq (Supported formats: $formats) ];
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SEEK SIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->seqmax ) {
        $conf->{"seq_max"} = &Common::Util::expand_number( $args->seqmax, \@msgs );
    } else {
        $conf->{"seq_max"} = undef;
    }

    &append_or_exit( \@msgs );    
    
    # >>>>>>>>>>>>>>>>>>>>>> SET DEFAULT OUTPUT SUFFIX <<<<<<<<<<<<<<<<<<<<<<<<

    if ( not ( $ndx_suffix = $args->ndxsuf ) )
    {
        $ndx_suffix = &Seq::Storage::index_info( $ndx_type, "suffixes" )->[0];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If named index files are given, these become output. If not, then the 
    # output index files are derived from the inputs by adding a suffix,

    if ( $args->ndxadd )
    {
        @ofiles = &Common::File::full_file_paths( [ $args->ndxadd ], \@msgs );

        # Number of outputs must be same as number of inputs,
        
        if ( ( $i = scalar @ifiles ) != ( $j = scalar @ofiles ) ) {
            push @msgs, ["ERROR", qq ($i input files, but $j output files) ];
        }
        
        $conf->{"ofiles"} = \@ofiles;
    }
    else
    {
        if ( scalar @ifiles == 1 and $args->outfile ) {
            @ofiles = $args->outfile;
        } elsif ( $out_dir = $args->outdir ) {
            @ofiles = map { "$out_dir/". &File::Basename::basename( $_ ) } @ifiles;
        } else {
            @ofiles = @ifiles;
        }
        
        if ( not $args->clobber ) {
            &Seq::Storage::check_indices_exist( \@ofiles, $ndx_type, \@msgs );
        }

        $conf->{"ofiles"} = [ map { $_ . $ndx_suffix } @ofiles ];
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->newstats or defined $args->stats )
    {
        $stats_file = $args->newstats || $args->stats;

        if ( scalar @{ $conf->{"ifiles"} } == 1 and $stats_file ) {
            $conf->{"sfiles"} = [ $stats_file ];
        } else {
            $conf->{"sfiles"} = [ map { $_ . ".stats" } @{ $conf->{"ifiles"} } ];
        }

#        if ( not $args->newstats and not $args->clobber )
#        {
#            &Common::File::check_files( $conf->{"sfiles"}, "!e", \@msgs );
#            &append_or_exit( \@msgs );
#        }
    }
    else {
        $conf->{"sfiles"} = undef;
    }

    $conf->{"ndx_type"} = $ndx_type;
    $conf->{"ndx_suffix"} = $ndx_suffix;

    $conf->{"input_count"} = $args->count;

    $conf->{"out_format"} = $args->outfmt // "table";
    $conf->{"out_suffix"} = $args->outsuf // ".". $conf->{"out_format"};
    $conf->{"out_ids"} = $args->outids;

    bless $conf;

    return $conf;
}

sub create_indices_blast
{
    # Niels Larsen, January 2011.

    # Creates blast indices for a given list of fasta files.

    my ( $args,
         $msgs,
	) = @_;

    # Returns nothing.

    my ( $defs, $clobber, @ifiles, $ifile, @ofiles, $ofile, $name, $count,
         $i, @msgs, $ndx_dir, $ndx_type, $protein, $logflag, $title );
    
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifiles" => [],
        "protein" => undef,
        "ndxdir" => undef,
        "log" => 0,
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    @ifiles = @{ $args->ifiles };

    $ndx_dir = $args->ndxdir;
    $ndx_type = $protein ? "blast_prot" : "blast_nuc";

    $protein = $args->protein;
    $logflag = $args->log;
    $clobber = $args->clobber;
    
    $Common::Messages::silent = $args->silent;

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Seq::Storage::check_inputs_exist( \@ifiles, \@msgs );
    &Seq::Storage::check_input_formats( \@ifiles, [ &Seq::Storage::index_info( $ndx_type, "formats" ) ], \@msgs );

    # Set output prefix files,

    if ( $ndx_dir ) {
        @ofiles = map { "$ndx_dir/". &File::Basename::basename( $_ ) } @ifiles;
    } else {
        @ofiles = @ifiles;
    }
    
    if ( not $clobber ) {
        &Seq::Storage::check_indices_exist( \@ofiles, $ndx_type, \@msgs );
    }

    &Common::Util::uniq_check( \@ofiles, \@msgs );

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INDEXING LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo_bold( "\nCreating blast indices:\n" );
    
    for ( $i = 0; $i <= $#ifiles; $i++ )
    {
        $ifile = $ifiles[$i];
        $ofile = $ofiles[$i];

	$name = &File::Basename::basename( $ifile );

        &echo( "   Indexing $name ... " );
        
        $count = &Seq::Storage::create_index_blast(
            $ifile,
            $ofile,
            {
                "protein" => $protein,
                "clobber" => $clobber,
                "log" => $logflag,
            });
        
        &echo_done("$count index file[s]\n");
    }

    &echo_bold( "Finished\n\n" );

    return;
}

sub create_input_stats
{
    # Niels Larsen, February 2011.

    # Creates an information hash for each input file. File formats are 
    # detected, sequence numbers set or counted.

    my ( $files,     # Sequence files
         $conf,      # Configuration hash
         $msgs,      # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( @stats, @sizes, $stat, $file, $count, @msgs, $seq_max, $i, $type,
         $input_count, $out_ids );

    $type = $conf->ndx_type;
    $seq_max = $conf->seq_max;
    $input_count = $conf->input_count;
    $out_ids = $conf->out_ids;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo("   Detecting file formats ... " );

    @stats = &Seq::IO::detect_files( $files );

    &echo_green( "done\n" );

    foreach $stat ( @stats )
    {
        if ( $stat->{"is_wrapped"} )
        {
            push @msgs, ["ERROR", qq (File has wrapped sequence lines -> "$stat->{'file_path'}") ];
            push @msgs, ["INFO", qq (Use seq_convert to create single-line sequence format) ];
        }
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> QUALITIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # If set explicitly, then use that user-given figure,

    if ( defined $seq_max )
    {
        foreach $stat ( @stats )
        {
            $stat->{"seq_num"} = $seq_max;
        }
    }

    # If all records are equally long, divide file size by the size of the 
    # first record,
    
    elsif ( $type eq "fetch_fixpos" or not $input_count )
    {
        &echo( "   Guessing sequence counts ... " );

        @sizes = &Seq::IO::detect_record_sizes( $files );
        
        for ( $i = 0; $i <= $#stats; $i += 1 )
        {
            $stats[$i]->{"seq_num"} = int ( ( -s $stats[$i]->{"file_path"} ) / $sizes[$i] );
        }

        $count = &List::Util::sum( map { $_->{"seq_num"} } @stats );

        &echo_done( "$count total\n" );
    }

    # If neither set manually or good guesses can be made, count sequences,

    else
    {
        &echo( "   Counting sequences ... " );
        
        foreach $stat ( @stats )
        {
            $stat->{"seq_num"} = &Seq::Stats::count_seq_file( $stat->{"file_path"} )->{"seq_count"};
            
            if ( int $stat->{"seq_num"} != $stat->{"seq_num"} )
            {
                push @msgs, ["ERROR", qq (There are $stat->{"seq_num"} sequences in $stat->{"file_path"}) ];
                push @msgs, ["info", qq (Is --fixed mistakenly switched on? are there blank lines in the file?) ];

                $stat->{"seq_num"} = int $stat->{"seq_num"};
            }
        }

        $count = &List::Util::sum( map { $_->{"seq_num"} } @stats );

        &echo_done( "$count total\n" );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> INDEX TYPES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $stat ( @stats )
    {
        $stat->{"ndx_type"} = $type;
    }

    @stats = map {  bless &Storable::dclone( $_ ) } @stats;

    &append_or_exit( \@msgs, $msgs );    
    
    return wantarray ? @stats : \@stats;
}

sub delete_index
{
    # Niels Larsen, January 2011. 

    # Deletes one or more index files for a given sequence file and index
    # type. Returns the number of index files deleted.

    my ( $file,    # Sequence file
         $type,    # Index type
        ) = @_;

    my ( @suffices, $suffix, $count );

    @suffices = &Seq::Storage::index_info( $type, "suffixes" );

    foreach $suffix ( @suffices )
    {
        $count += &Common::File::delete_file_if_exists( "$file.$suffix" );
    }

    return $count;
}

sub delete_indices
{
    # Niels Larsen, January 2011.

    # Deletes indices of different types, created by seq_index. 

    my ( $args,
         $msgs,
	) = @_;

    # Returns nothing.

    my ( $defs, @ifiles, $ifile, $type, @suffixes, @msgs, @ndx_files, $count, 
         @types, $name, %suffixes, $key, $val, $sufsall, $suffix );
 
    local $Common::Messages::silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "paths" => [],
        "ndxsuf" => ".fetch",
        "types" => undef,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    @ifiles = @{ $args->paths };
    $suffix = $args->ndxsuf;

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Seq::Storage::check_inputs_exist( \@ifiles, \@msgs );

    if ( $suffix or $args->types )
    {
        if ( $args->types ) {
            @types = &Seq::Storage::check_index_type_string( $args->types, \@msgs );
        }
    }
    else {
        push @msgs, ["ERROR", qq (No types or suffix given) ];
    }
    
    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>> EXCLUDE INDEX FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    %suffixes = map { $_, 1 } &Seq::Storage::index_info_values("suffixes");

    @ifiles = grep { $_ !~ /(\.[^\.]+)$/ or not exists $suffixes{ $1 } } @ifiles;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET SUFFIXES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $suffix )
    {
        @suffixes = ( $suffix );
    }
    else
    {
        foreach $type ( @types ) {
            push @suffixes, &Seq::Storage::index_info( $type, "suffixes" );
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> DELETE INDICES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo_bold( "\nDeleting indices:\n" );

    foreach $ifile ( @ifiles )
    {
        @ndx_files = map { "$ifile$_" } @suffixes;

        $count = 0;
        $name = &File::Basename::basename( $ifile );

        &echo( qq (   Deleting $name indices ... ) );
        
        map { $count += &Common::File::delete_file_if_exists( ".$_" ) } @ndx_files;
        map { $count += &Common::File::delete_file_if_exists( $_ ) } @ndx_files;
        
        if ( $count > 0 ) {
            &echo_green( "$count deleted\n" );
        } else {
            &echo_green( "none\n" );
        }
    }
    
    &echo_bold( "Finished\n\n" );
    
    return;
}

sub dump_derep_seqs
{
    # Niels Larsen, February 2011.

    # Iterates through one or more dereplicated sequence stores and writes 
    # all data to files, in the format chosen.

    my ( $args,       # Arguments hash
	) = @_;

    # Returns list.

    my ( $defs, $conf, $seq_count, @ifiles, @ofiles, $key_vals, $dbh, $key, 
         $val, $out_routine, $ifile, $ofile, $i, $cursor, $get_size, 
         $byt_count, $name, @seqs, @stats, $stat, $out_handle, $clobber,
         @counts, $seq );

    local $Common::Messages::silent;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $defs = {
        "ifiles" => [],
        "outsuf" => undef,
        "outids" => 0,
        "outfmt" => "table",
        "clobber" => 0,
        "silent" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $Common::Messages::silent = $args->silent;
    $get_size = 100_000;
    $clobber = $args->clobber;

    # >>>>>>>>>>>>>>>>>>>>>>>>> PROCESS ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $conf = &Seq::Storage::process_dump_args( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DUMP DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @ifiles = @{ $conf->{"ifiles"} };
    @ofiles = @{ $conf->{"ofiles"} };

    $out_routine = &Seq::IO::get_write_routine( $conf->{"out_format"} );

    &echo_bold( "\nDe-replicated sequences:\n" );

    @stats = ();

    for ( $i = 0; $i <= $#ifiles; $i += 1 )
    {
        $ifile = $ifiles[$i];
        $ofile = $ofiles[$i];
        
        $name = &File::Basename::basename( $ofile );
        &echo( qq (   Creating $name ... ) );

        # Connect inputs and outputs,

        ( $dbh, $key_vals ) = &Common::DBM::read_tie( $ifile );
        $out_handle = &Common::File::get_write_handle( $ofile, "clobber" => $clobber );
        
        # Use Kyoto cursor to iterate through the keys/values, while 
        # skipping the __CONFIG__ key,

        $cursor = $dbh->cursor;
        $cursor->jump;

        $byt_count = 0;
        $seq_count = 0;

        @seqs = ();
        $stat = { "seq_count" => 0, "seq_count_orig" => 0 };

        while ( 1 )
        {
            while ( $byt_count < $get_size and ( $key, $val ) = $cursor->get(1) )
            {
                next if $key eq "__CONFIG__";
                
                $byt_count += length $val;
                $seq_count += 1;

                if ( $val =~ /^(\d+)\t([^\t]*)\t(.*)$/ )
                {
                    $seq = { "id" => $seq_count, "seq" => $key };

                    $seq->{"info"} = "seq_count=$1" if $1;
                    $seq->{"qual"} = $2 if $2;

                    if ( $3 ) 
                    {
                        if ( $seq->{"info"} ) {
                            $seq->{"info"} .= " seq_ids=$3";
                        } else {
                            $seq->{"info"} = "seq_ids=$3";
                        }
                    }                            
                }
                else {
                    &error( qq (Wrong looking value in derep mode:\n\n) . $val );
                }
                
                push @seqs, $seq;
            }

            last if not @seqs;

            no strict "refs";
    
            &{ $out_routine }( $out_handle, \@seqs );

            $stat->{"seq_count"} += scalar @seqs;

            @counts = map { $_->{"info"} =~ /seq_count=(\d+)/; $1 } @seqs;
            $stat->{"seq_count_orig"} += &List::Util::sum( @counts );
            
            $byt_count = 0;
            @seqs = ();
        }

        push @stats, bless &Storable::dclone( $stat );

        # Close output and input,

        &Common::File::close_handle( $out_handle );

        &Common::DBM::untie( $dbh, $key_vals );

        &echo_done( "$seq_count\n" );
    }
 
    &echo_bold( "Finished\n\n" );

    return wantarray ? @stats : \@stats;
}

sub fetch_seqs
{
    # Niels Larsen, January 2011.

    # Fetches sequences or sub-sequences from a given indexed sequence file 
    # created with seq_index and either returns or prints them in different
    # formats. Kyoto Cabinet is used as store, and there is one index file 
    # per data file with a .kch suffix (later there will be an index that 
    # will work with multiple files). 
    
    my ( $from,       # Input sequence file or Seq::IO handle
         $args,       # Arguments hash
	) = @_;

    # Returns list.

    my ( $defs, $locs, $seq_objs, $conf, $loc_count, $bad_ids, @msgs, 
         $msgs, $id, $seq_count, $bad_count, $out_format, $err_handle,
         $return_data );

    local $Common::Messages::silent;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $defs = {
        "locs" => [],
        "locfile" => undef,
        "order" => 0,
        "parse" => 1,
        "ssize" => 4_000_000,
        "format" => undef,
        "fields" => undef,
        "outfile" => undef,
        "errfile" => undef,
        "getsize" => 10_000,
        "clobber" => 0,
        "append" => 0,
        "return" => 0,
        "silent" => 0,
        "stdin" => 0,
    };

    $args = &Registry::Args::create( $args, $defs );

    $Common::Messages::silent = $args->silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>> PROCESS ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $conf = &Seq::Storage::process_fetch_args( $from, $args );

    &echo_bold( "\nFetching sequences:\n" );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ LOCATORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Reading locators ... ) );

    # Get both ARGV list, and from file and STDIN if given,

    $locs = &Seq::IO::read_locators( $args->locs, $args->locfile, $args->stdin, \@msgs );

    if ( @msgs ) {
        &echo( "\n" );
        &append_or_exit( \@msgs );
    }
    
    $locs = &Seq::Common::parse_locators( $locs );

    $loc_count = scalar @{ $locs };
    &echo_done( "$loc_count\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FETCH SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Uses bulk-get provided by the underlying key/value store to get hashes 
    # of sequence data, field by field. These hashes are either returned as 
    # objects, or printed in different formats.

    &echo( qq (   Fetching sequences ... ) );

    $seq_objs = [];     # Will be filled if no output printed
    $bad_ids = [];      # Will be filled with input ids with no match
    
    # Open output handle; no output format means sequence objects are returned,

    if ( $out_format = $conf->{"out_format"} )
    {
        if ( $args->append ) {
            $conf->{"out_handle"} = &Common::File::get_append_handle( $args->outfile );
        } else {
            $conf->{"out_handle"} = &Common::File::get_write_handle( $args->outfile, "clobber" => $args->clobber );
        }
    }

    if ( $conf->{"seq_format"} eq "genbank" or $conf->{"seq_format"} eq "embl" or not $args->parse )
    {
        # Routine that fetches whole entries without parsing their content,
        
        $seq_count = &Seq::Storage::fetch_seqs_entries( $locs, $conf, $bad_ids, $msgs );
    }
    elsif ( $args->order and $conf->{"ndx_type"} ne "fetch_embed" )
    {
        # Routine that reads ahead in the sequence file, avoids lot of seeks 
        # when input ids share some order with sequence file ids,

        $seq_count = &Seq::Storage::fetch_seqs_order( $locs, $conf, $bad_ids, $seq_objs, $msgs );
    }
    else 
    {
        # When input ids share little order with sequence file ids,
        
        $seq_count = &Seq::Storage::fetch_seqs_random( $locs, $conf, $bad_ids, $seq_objs, $msgs );
    }        

    if ( $conf->{"out_handle"} ) {
        &Common::File::close_handle( $conf->{"out_handle"} );
    }

    &echo_done( "$seq_count\n" );
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

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OTHER MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( @{ $seq_objs } ) {
        return wantarray ? @{ $seq_objs } : $seq_objs;
    }
    
    return;
}

sub fetch_seqs_entries
{
    # Niels Larsen, July 2012.

    # Fetches a list of entries without parsing them.

    my ( $locs,
         $args,      # Arguments hash
         $bids,      # Missing ids
         $msgs,      # Error messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $offsets, $id, $val, $i, $ndx_h, $out_h, $seq_h, $entry, $count );

    $ndx_h = $args->{"ndx_handle"};
    $seq_h = $args->{"seq_handle"};
    $out_h = $args->{"out_handle"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GET SEEK INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get seek positions and lengths from index,

    $offsets = &Common::DBM::get_bulk( $ndx_h, [ map { $_->[0] } @{ $locs } ] );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FOR EACH LOCATOR <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $count = 1;

    for ( $i = 0; $i <= $#{ $locs }; $i += 1 )
    {
        $id = $locs->[$i]->[0];

        if ( not defined ( $val = $offsets->{ $id } ) )
        {
            # Missing ID,

            push @{ $bids }, $id;
        }
        elsif ( $val =~ /^(.+?)\t(.+)$/o )
        {
            seek( $seq_h, $1, SEEK_SET );
            read( $seq_h, $entry, $2 );

            $count += 1;

            $out_h->print( $entry );
        }
        else {
            &error( qq (Wrong looking index value -> "$val" ) );
        }
    }

    return $count;
}

sub fetch_seqs_order
{
    # Niels Larsen, February 2011.

    # Is fastest for ids that share some ordering with the sequence file ids.
    # See also fetch_seqs_random. Prints to output handle or returns list of 
    # sequence objects; this depends on whether there is an output format given.
    # Returns the number of sequences fetched.

    my ( $locs,      # Input locator list
         $conf,      # Input configuration hash
         $bads,      # Ids not found 
         $seqs,      # Output sequence hash list - OPTIONAL
         $msgs,      # Output messages - OPTIONAL
        ) = @_;

    # Returns integer. 

    my ( $get_size, $imax, $seq_count, @seqs, $pos_sub,
         $bad_count, $out_fields, $ibeg, $iend, @msgs, @bad_ids, $seq_hashes,
         $format, $out_routine, $rec_reader, $seq_fields, $ndx_type, 
         $ndx_handle, $seq_handle, $out_handle, $seq_format, %locs, $val,
         $id, $ranges, $seq, $count, $i, $byt_size, $byt_field, $byt_count,
         $file_pos, $rec_size );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CONVENIENCE VARIABLES <<<<<<<<<<<<<<<<<<<<<<<<<

    # Settings,

    $get_size = $conf->{"get_size"};
    $ndx_type = $conf->{"ndx_type"};
    $byt_size = 100_000;

    # Handles, 

    $ndx_handle = $conf->{"ndx_handle"};
    $seq_handle = $conf->{"seq_handle"};
    $out_handle = $conf->{"out_handle"};

    # Format and fields,

    $seq_format = $conf->{"seq_format"};
    $out_fields = $conf->{"out_fields"};

    $seq_fields = $conf->{"seq_fields"};
    $byt_field = $seq_fields->[0];

    # Output routine,

    if ( $format = $conf->{"out_format"} )
    {
        $out_routine = "Seq::IO::write_seqs_$format";
    }

    # Record reading routine,

    $rec_reader = "Seq::IO::read_seq_". $seq_format;

    # Calculate file seek position,

    if ( $ndx_type eq "fetch_fixpos" )
    {
        $rec_size = ( -s $conf->{"seq_file"} ) / $conf->{"seq_count"};
        $pos_sub = sub { return $val * $rec_size };
    }
    else {
        $pos_sub = sub { $val =~ /^(\d+)/ and return $1 };
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> LOCATOR LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Speed is gained when input ids share ordering with those in the sequence
    # file: one "position<tab>length" pair is fetched from the index, and the 
    # sequence file is read from there until there is an id not in the locator
    # list. Then back and fetch a new one. To make that work, first create a 
    # locators hash,

    %locs = map { $_->[0], $i++ } @{ $locs };

    $i = 0;
    $imax = $#{ $locs };

    $seq_count = 0;
    $byt_count = 0;

    @seqs = ();

    while ( $i <= $imax )
    {
        ( $id, $ranges ) = @{ $locs->[$i] };

        # Fetch file position of entry, and length of it,

        $val = &Common::DBM::get( $ndx_handle, $id, 0 );

        if ( not defined $val )
        {
            push @{ $bads }, $id;
            delete $locs{ $id };
        } 
        elsif ( defined ( $file_pos = $pos_sub->() ) )
        {
            # Go to that point and read from there,

            seek $seq_handle, $file_pos, SEEK_SET;
            
            no strict "refs";
            
            while ( $seq = $rec_reader->( $seq_handle ) 
                    and exists $locs{ $id = $seq->{"id"} } )
            {
                # Handle sub-sequences if ranges given,

                ( $id, $ranges ) = @{ $locs->[ $locs{ $id } ] };

                if ( defined $ranges ) {
                    $seq = &Seq::Common::sub_seq_clobber( $seq, $ranges );
                }

                # Add to a buffer, just to avoid printing for each sequence,

                push @seqs, $seq;
                $byt_count += length $seq->{ $byt_field };

                # Delete the ids from locators as we run into them in the file,

                delete $locs{ $id };

                $seq_count += 1;

                # Output or push to a list,

                if ( $byt_count > $byt_size )
                {
                    if ( $out_routine ) {
                        &{ $out_routine }( $out_handle, \@seqs, $out_fields );
                    } else {
                        push @{ $seqs }, map { Seq::Common->new( $_, 0 ) } @seqs;
                    }

                    $byt_count = 0;
                    @seqs = ();
                }
            }
        }
        else {
            &error( qq (Wrong looking index value -> "$val" ) );
        }

        # Skip over the locators found by reading ahead above,

        $i++ while $i <= $imax and not exists $locs{ $locs->[$i]->[0] };
    }

    # Empty the buffer if there are leftovers,

    if ( @seqs )
    {
        no strict "refs";

        if ( $out_routine ) {
            &{ $out_routine }( $out_handle, \@seqs, $out_fields );
        } else {
            push @{ $seqs }, map { Seq::Common->new( $_, 0 ) } @seqs;
        }
    }

    return $seq_count;
}

sub fetch_seqs_random
{
    # Niels Larsen, February 2011.

    # Is fastest for ids that do not share much ordering with the sequence file
    # ids. See also fetch_seqs_order. Prints to output handle or returns list of 
    # sequence objects; this depends on whether there is an output format given.
    # Returns the number of sequences fetched.

    my ( $locs,      # Input locator list
         $conf,      # Input configuration hash
         $bads,      # Ids not found 
         $seqs,      # Output sequence hash list - OPTIONAL
         $msgs,      # Output messages - OPTIONAL
        ) = @_;

    # Returns integer.

    my ( $get_size, $get_routine, $imax, $seq_count, $rec_size, $seek_size,
         $bad_count, $out_fields, $ibeg, $iend, @msgs, @bad_ids, $seq_hashes,
         $format, $out_routine, $rec_parser, $seq_fields, $ndx_type, 
         $ndx_handle, $seq_handle, $out_handle, $seq_format );

    # Settings,

    $get_size = $conf->{"get_size"};
    $ndx_type = $conf->{"ndx_type"};
    $rec_size = ( -s $conf->{"seq_file"} ) / $conf->{"seq_count"};
    $seek_size = $conf->{"seek_size"};

    # Handles,

    $ndx_handle = $conf->{"ndx_handle"};
    $seq_handle = $conf->{"seq_handle"};
    $out_handle = $conf->{"out_handle"};

    # Format and fields,

    $seq_format = $conf->{"seq_format"};

    $out_fields = $conf->{"out_fields"};    
    $seq_fields = $conf->{"seq_fields"};
    
    # Get routine,

    if ( $ndx_type =~ /^fetch_(varpos|fixpos)$/ ) {
        $get_routine = "Seq::Storage::fetch_seqs_random_$1";
    } else {
        $get_routine = "Seq::Storage::fetch_seqs_random_embed";
    }        

    # Entry parse routine, 

    $rec_parser = &Seq::Storage::set_rec_parser( $seq_format, $ndx_type );

    # Output routine if called for,

    if ( $format = $conf->{"out_format"} )
    {
        $out_routine = "Seq::IO::write_seqs_$format";
        $out_handle = $conf->{"out_handle"};
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> LOCATORS LOOP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Advance in ranges and get hashes for all ids in each range,

    $imax = $#{ $locs };

    $seq_count = 0;
    $bad_count = 0;

    for ( $ibeg = 0; $ibeg <= $imax; $ibeg += $get_size )
    {
        @msgs = ();
        
        $iend = &List::Util::min( $ibeg + $get_size - 1, $imax );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FETCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        {
            no strict "refs";

            $seq_hashes = &{ $get_routine }(
                {
                    "loc_list" => [ @{ $locs }[ $ibeg .. $iend ] ],
                    "ndx_handle" => $ndx_handle,
                    "seq_handle" => $seq_handle,
                    "rec_parser" => $rec_parser,
                    "rec_size" => $rec_size,
                    "seek_size" => $seek_size,
                    "seq_fields" => $seq_fields,
                },
                $bads, \@msgs );
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # If output routine given, run it, otherwise create list of objects
        # and return those,

        if ( @{ $seq_hashes } )
        { 
            $seq_count += scalar @{ $seq_hashes };

            no strict "refs";

            if ( $out_routine ) {
                &{ $out_routine }( $out_handle, $seq_hashes, $out_fields );
            } else {
                push @{ $seqs }, map { Seq::Common->new( $_, 0 ) } @{ $seq_hashes };
            }
        }
    }
    
    return $seq_count;
}

sub fetch_seqs_random_embed
{
    # Niels Larsen, January 2011.

    # Creates a list of sequence entry hashes by reading and parsing values 
    # saved in the key/value store. Values are tab-separated strings, depending
    # on the source format.
    
    my ( $args,
         $bids,
         $msgs,
        ) = @_;

    # Returns a list reference.
    
    my ( $values, $id, $ref, $ranges, @seqs, $i, $locs, $parser, $ndx_h,
         $seq_fields, $seq );

    $locs = $args->{"loc_list"};
    $ndx_h = $args->{"ndx_handle"};
    $seq_fields = $args->{"seq_fields"};

    $parser = $args->{"rec_parser"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET STORAGE VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $values = &Common::DBM::get_bulk( $ndx_h, [ map { $_->[0] } @{ $locs } ] );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FOR EACH LOCATOR <<<<<<<<<<<<<<<<<<<<<<<<<<<

    @seqs = ();
    
    for ( $i = 0; $i <= $#{ $locs }; $i += 1 )
    {
        ( $id, $ranges ) = @{ $locs->[$i] };

        $ref = \$values->{ $id };

        if ( not defined ${ $ref } )
        {
            # Missing id,

            push @{ $bids }, $id;
        }
        else
        {
            no strict "refs";

            # Parse value,

            $seq = $parser->( $id, $ref );
            
            # Get sub-sequence. Locators can be just ids or have ranges. Ranges 
            # are only cut out of the fields where that makes sense (not on 
            # annotation and such),

            if ( defined $ranges ) {
                $seq = &Seq::Common::sub_seq_clobber( $seq, $ranges );
            }

            push @seqs, $seq;
        }
    }

    return wantarray ? @seqs : \@seqs;
}

sub fetch_seqs_random_fixpos
{
    # Niels Larsen, January 2011.

    # Creates a list of sequence entry hashes by seeking, reading and parsing
    # whole entries from sequence files. It is fastest for ids that share little
    # ordering with the sequence file ids. 

    my ( $args,      # Arguments hash
         $bids,      # Missing ids
         $msgs,      # Error messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $seq_nums, $seq_num, $id, $val, $ranges, @seqs, $i, $locs, $parser,
         $ndx_h, $seq_h, $seq_fields, $seq, $entry, $rec_size );

    $locs = $args->{"loc_list"};
    $ndx_h = $args->{"ndx_handle"};
    $seq_h = $args->{"seq_handle"};
    $seq_fields = $args->{"seq_fields"};
    $rec_size = $args->{"rec_size"};
    
    $parser = $args->{"rec_parser"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GET SEEK INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get seek positions and lengths from index,

    $seq_nums = &Common::DBM::get_bulk( $ndx_h, [ map { $_->[0] } @{ $locs } ] );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FOR EACH LOCATOR <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    @seqs = ();
    
    for ( $i = 0; $i <= $#{ $locs }; $i += 1 )
    {
        ( $id, $ranges ) = @{ $locs->[$i] };

        if ( not defined ( $seq_num = $seq_nums->{ $id } ) )
        {
            # Missing ID,

            push @{ $bids }, $id;
        }
        else
        {
            # Seek and read,
            
            seek( $seq_h, $rec_size * $seq_num, SEEK_SET );
            read( $seq_h, $entry, $rec_size );
            
            # Parse entry,

            no strict "refs";

            $seq = $parser->( $id, \$entry );

            # Get sub-sequence. Locators can be just ids or have ranges. Ranges 
            # are only cut out of the fields where that makes sense (not on 
            # annotation and such),

            if ( defined $ranges ) {
                $seq = &Seq::Common::sub_seq_clobber( $seq, $ranges );
            }

            push @seqs, $seq;
        }
    }

    return wantarray ? @seqs : \@seqs;
}

sub fetch_seqs_random_varpos
{
    # Niels Larsen, January 2011.

    # Creates a list of sequence entry hashes by seeking, reading and parsing
    # whole entries from sequence files. It is fastest for ids that share little
    # ordering with the sequence file ids. 

    my ( $args,      # Arguments hash
         $bids,      # Missing ids
         $msgs,      # Error messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $offsets, $id, $val, $ranges, @seqs, $i, $locs, $parser, $ndx_h,
         $seq_h, $seq_fields, $seq, $entry, $seek_size, $read_sub, $seek_sub );

    $locs = $args->{"loc_list"};
    $ndx_h = $args->{"ndx_handle"};
    $seq_h = $args->{"seq_handle"};
    $seq_fields = $args->{"seq_fields"};
    $seek_size = $args->{"seek_size"};

    $parser = $args->{"rec_parser"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GET SEEK INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get seek positions and lengths from index,

    $offsets = &Common::DBM::get_bulk( $ndx_h, [ map { $_->[0] } @{ $locs } ] );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SHORT SEQUENCE READER <<<<<<<<<<<<<<<<<<<<<<<<

    # For short sequences it is faster to read the whole record, parse, and 
    # optionally extract sub-sequences from that memory copy. When run below 
    # this routine does that,

    $read_sub = sub
    {
        seek( $seq_h, $1, SEEK_SET );
        read( $seq_h, $entry, $2 );
        
        # Parse entry,

        $seq = $parser->( $id, \$entry );

        # Get sub-sequence. Locators can be just ids or have ranges. Ranges 
        # are only cut out of the fields where that makes sense (not on 
        # annotation and such),
        
        if ( defined $ranges ) {
            $seq = &Seq::Common::sub_seq_clobber( $seq, $ranges );
        }

        return;
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>> LONG SEQUENCE SEEKER <<<<<<<<<<<<<<<<<<<<<<<<<<

    # On the other hand, reading a whole chromosome to get a small piece is a
    # bad idea. In that case we must seek while looking for start positions of
    # the sequence (and quality maybe), and apply offsets from there. The 
    # alternative would be to store those extra positions, but that would make
    # the indices for small sequences larger. 
    
    $seek_sub = sub
    {
        my ( $ndx, $rec_beg, $seq_beg, $seq_len, $buf, $offset, $range, 
             $seq_str );

        # Find starting point of sequence by reading chunks ahead while 
        # checking for newline,

        $rec_beg = $1;
        $seq_len = $2;

        seek( $seq_h, $rec_beg, SEEK_SET );
        read( $seq_h, $buf, 100 );
        
        $seq_beg = $rec_beg;

        while ( ( $ndx = index $buf, "\n" ) eq -1 )
        {
            $seq_beg += 100;
            read( $seq_h, $buf, 100 );
        }
        
        $seq_beg += $ndx + 1;

        # Seek through each position while appending, complement if needed,

        $seq = { "id" => $id };

        if ( $ranges )
        {
            $seq->{"seq"} = "";

            foreach $range ( @{ $ranges } )
            {
                seek( $seq_h, $seq_beg + $range->[0], SEEK_SET );
                read( $seq_h, $buf, $range->[1] );
            
                if ( $range->[2] eq "-" ) {
                    $seq->{"seq"} .= ${ &Seq::Common::complement_str( \$buf ) };
                } else {
                    $seq->{"seq"} .= $buf;
                }
            }
        }
        else
        {
            seek( $seq_h, $seq_beg, SEEK_SET );
            read( $seq_h, $seq->{"seq"}, $seq_len );
        }
        
        return;
    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> FOR EACH LOCATOR <<<<<<<<<<<<<<<<<<<<<<<<<<
    
    @seqs = ();
    
    for ( $i = 0; $i <= $#{ $locs }; $i += 1 )
    {
        ( $id, $ranges ) = @{ $locs->[$i] };

        if ( not defined ( $val = $offsets->{ $id } ) )
        {
            # Missing ID,

            push @{ $bids }, $id;
        }
        elsif ( $val =~ /^(.+?)\t(.+)$/o )
        {
            no strict "refs";

            if ( $2 < $seek_size )
            {
                # Read whole entry,

                &{ $read_sub };
            }
            else 
            {
                # Seek through entry,
                
                &{ $seek_sub };
            }

            push @seqs, $seq;
        }
        else {
            &error( qq (Wrong looking index value -> "$val" ) );
        }
    }

    return wantarray ? @seqs : \@seqs;
}

sub format_fields
{
    # Niels Larsen, January 2011.

    # Defines sequence-related, valid and minimal fields for each supported 
    # format.

    my ( $type,
         $format,
        ) = @_;

    # Returns a hash.

    my ( %fields );

    &error( "type not defined" ) if not defined $type;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DEFINE FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $type eq "valid" )
    {
        # Format compatible fields,

        %fields = (
            "fasta_wrapped" => [ qw ( id seq info ) ],
            "fasta" => [ qw ( id seq info ) ],
            "fastq" => [ qw ( id seq qual ) ],
            "genbank" => [ qw ( id ) ],
#            "json" => [ qw ( id seq qual ) ],
            "yaml" => [ qw ( id seq qual ) ],
            "table" => [ qw ( id seq qual ) ],
            );
    }
    elsif ( $type eq "seq" )
    {
        # Sequence related fields,

        %fields = (
            "fasta_wrapped" => [ qw ( seq ) ],
            "fasta" => [ qw ( seq ) ],
            "fastq" => [ qw ( seq qual ) ],
            "genbank" => [ qw ( id ) ],
#            "json" => [ qw ( seq qual ) ],
            "yaml" => [ qw ( seq qual ) ],
            "table" => [ qw ( seq qual ) ],
            );
    }
    elsif ( $type eq "required" )    # Those that the format requires
    {
        %fields = (
            "fasta_wrapped" => [ qw ( id seq ) ],
            "fasta" => [ qw ( id seq ) ],
            "fastq" => [ qw ( id seq qual ) ],
            "genbank" => [ qw ( id ) ],
#            "json" => [],
            "yaml" => [],
            "table" => [],            
            );
    }
    else {
        &error( qq (Wrong looking modifier -> "$type") );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SELECT FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $format )
    {
        if ( exists $fields{ $format } ) {
            return wantarray ? @{ $fields{ $format } } : $fields{ $format };
        } else {
            &error( qq (Unrecognized format -> "$format") );
        }
    }
    else {
        return wantarray ? %fields : \%fields;
    }

    return;
}

sub get_handles
{
    # Niels Larsen, January 2011.

    # Returns a Seq::Storage object with these accessors,
    # 
    #  seq_file        Sequence file
    #  seq_handle      Sequence handle
    #  ndx_file        Index file
    #  ndx_handle      Index handle
    #  ndx_type        Index type
    # 
    # A hash is optional that sets read/write/append mode and the type of 
    # index (hash and btree are recognized). The last argument returns error
    # messages, otherwise the routine exits with fatal error. 

    my ( $file,   # Sequence file name
         $args,   # Argument hash - OPTIONAL
         $msgs,   # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns Seq::Storage object.

    my ( $defs, $access, $ndx_type, $fh, $routine, @msgs, $params );
    
    # Arguments,

    $defs = {
        "access" => "read",
        "ndxtype" => "fetch_varpos",
    };

    $args = &Registry::Args::create( $args, $defs );

    $access = $args->access;
    $ndx_type = $args->ndxtype;

    if ( $access !~ /^read|write|append$/ ) {
        &error( qq (Wrong looking access mode -> "$access". Choices are read, write, append.) );
    }
    
    $fh->{"ndx_type"} = $ndx_type;
    $fh->{"seq_file"} = &Common::File::resolve_links( $file );

    no strict "refs";

    $routine = "Common::File::get_$access". "_handle";

    # Index file,
    
    if ( &Seq::Storage::is_indexed( $file, $ndx_type ) )
    {
        $fh->{"ndx_file"} = "$file$Index_suffix";
        
        # Sequence file,

        $fh->{"seq_handle"} = &{ $routine }( $file );

        # Kyoto does not save all parameters in the index file. So we must get
        # them from the datafile, and then open kyoto for the second time ..

        $params = &Seq::Storage::get_index_config( $fh->{"ndx_file"} )->kyoto_params;

        $routine = "Common::DBM::$access"."_open";
        $fh->{"ndx_handle"} = &{ $routine }( $fh->{"ndx_file"}, "params" => $params );

    }
    else
    {
        $fh->{"seq_handle"} = undef;
        $fh->{"ndx_handle"} = undef;

        push @msgs, ["ERROR", qq (Sequence file is not indexed -> "$file") ];
        push @msgs, ["info", qq (See the seq_index command) ];
    }

    &append_or_exit( \@msgs, $msgs );

    return bless $fh;
}

sub get_index_config
{
    # Niels Larsen, January 2011. 

    # Returns all information saved under the __CONFIG__ key. 

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

    # Returns statistics about the index itself. Given en index file or handle, 
    # returns a hash with these keys:
    # 
    # key_count
    # seq_count
    # file_size
    # file_path
    # status

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

    if ( &Seq::Storage::get_index_config( $dbh ) ) {
        $stats->{"seq_count"} = $stats->{"key_count"} - 1;
    } else {
        $stats->{"seq_count"} = $stats->{"key_count"};
    }        

    bless $stats;

    if ( not ref $file ) {
        &Common::DBM::close( $dbh );
    }

    return wantarray ? %{ $stats } : $stats;
}

sub index_info
{
    # Niels Larsen, February 2011. 

    # Returns index information. If no index name given, a hash with all index
    # info is returned. If valid index name, a hash for that index is returned.
    # If field is given also, the value for that field is returned.
    # 
    # title          Short description of the index type
    # progtype       Index type
    # formats        Accepted sequence input formats
    # routine        Indexing routine name
    # suffixes       Suffix list or string

    my ( $name,       # Index name
         $field,      # Index info field - OPTIONAL
         $msgs,       # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns hash, list or scalar.

    my ( %info, $info, $val, $choices, @msgs );

    %info = (
        "derep_seq" => {
            "title" => "De-replication storage",
            "progtype" => "derep",
            "formats" => [ "fasta", "fastq" ],
            "routine" => "create_index_derep",
            "suffixes" => [ ".derep" ],
        },
        "fetch_embed" => {
            "title" => "Fetch storage, all data within",
            "progtype" => "fetch",
            "formats" => [ "fasta", "fastq" ],
            "routine" => "create_index_embed",
            "suffixes" => [ $Index_suffix ],
        },
        "fetch_fixpos" => {
            "title" => "Fetch index, external same-size records",
            "progtype" => "fetch",
            "formats" => [ "fasta", "fastq" ],
            "routine" => "create_index_fixpos",
            "suffixes" => [ $Index_suffix ],
        },
        "fetch_varpos" => {
            "title" => "Fetch index, external variable-size records",
            "progtype" => "fetch",
            "formats" => [ "fasta", "fastq", "genbank", "embl" ],
            "routine" => "create_index_varpos",
            "suffixes" => [ $Index_suffix ],
        },
        "blast_prot" => {
            "title" => "Protein blast index",
            "progtype" => "blastp",
            "formats" => [ "fasta", "fasta_wrapped" ],
            "routine" => "",
            "suffixes" => [ ".phr", ".pin", ".psq", ".log" ],
        },
        "blast_nuc" => {
            "title" => "Nucleotide blast index",
            "progtype" => "blastn",
            "formats" => [ "fasta", "fasta_wrapped" ],
            "routine" => "formatdb",
            "suffixes" => [ ".nhr", ".nin", ".nsq", ".log" ],
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
    }
    
    &append_or_exit( \@msgs, $msgs );

    return wantarray ? %info : \%info;
}

sub index_info_values
{
    # Niels Larsen, February 2011.

    # Returns a uniqified list of all values of a given field in the info
    # hash. 

    my ( $field,    # Info hash field
         $filter,   # Info key filter
        ) = @_;

    # Returns list.

    my ( @names, $info, $name, $val, @list );

    $info = &Seq::Storage::index_info();

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

sub index_seq_file
{
    # Niels Larsen, March 2011.

    # Dispatches sequence indexing to the routines in Seq::Storage.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns nothing.

    my ( $defs, $conf, $format, $protein );

    $defs = {
        "ifile" => undef,
        "oprefix" => undef,
        "oformat" => undef,
        "datatype" => undef,
        "silent" => 1,
        "clobber" => 0,
    };

    $conf = &Registry::Args::create( $args, $defs );

    $format = $conf->oformat || "";
    
    if ( $format =~ /^blast/ )
    {
        if ( &Common::Types::is_protein( $conf->datatype ) ) {
            $protein = 1;
        } else {
            $protein = 0;
        }

        &Seq::Storage::create_indices_blast( 
             {
                 "ifiles" => [ $conf->ifile ],
                 "protein" => $protein,
                 "clobber" => $conf->clobber,
                 "silent" => $conf->silent,
             });
    }
    elsif ( not $format )
    {
        &Seq::Storage::create_indices( 
             {
                 "ifiles" => [ $conf->ifile ],
                 "progtype" => "fetch",
                 "clobber" => $conf->clobber,
                 "silent" => $conf->silent,
             });
        
    } else {
        &error( qq (Unrecognized format -> "$format") );
    }
    
    return;
}
    
sub index_types_all
{
    my ( %types );

    %types = (
        "derep" => [ qw ( derep_seq ) ],
        "fetch" => [ qw ( fetch_embed fetch_fixpos fetch_varpos ) ],
        "blastp" => [ qw ( blast_prot ) ],
        "blastn" => [ qw ( blast_nuc ) ],
        );

    return wantarray ? %types : \%types;
}

sub is_indexed
{
    # Niels Larsen, February 2010.

    # Returns true if index file(s) exist for the given file AND that file
    # is older than any of the index files. If a program name is given then
    # the index must be for that program, otherwise the default random
    # access index is checked. The given file must exist.

    my ( $ifile,             # Input file path
	 $type,              # Program name - OPTIONAL
         ) = @_;

    # Returns 1 or nothing.

    my ( @sufs, $suf, @msgs );

    $type //= "fetch_varpos";

    @sufs = &Seq::Storage::index_info( $type, "suffixes" );

    if ( -r $ifile )
    {
        # If an index file is missing or older than the file itself,
        # then return false,
        
        foreach $suf ( @sufs )
        {
            if ( not -s "$ifile$suf" or
                 &Common::File::is_newer_than( $ifile, "$ifile$suf" ) )
            {
                return;
            }
        }
    }
    else
    {
        # If an index file is missing, then return false,
        
        foreach $suf ( @sufs )
        {
            return if not -s "$ifile$suf";
        }
    }
    
    # Otherwise return true,
    
    return 1;
}

sub output_formats
{
    # Niels Larsen, January 2011.

    # Returns a hash where key is original input format and value is a
    # list of output formats that can be made from that. For example,
    # fasta can be made from fastq, but not the opposite because fasta
    # has no quality line.

    my ( $orig,
         $msgs,
        ) = @_;

    # Returns list.

    my ( %formats, $format, @out, @msgs );

    %formats = (
        "fasta" => [ qw ( fasta_wrapped fasta ) ],
        "fastq" => [ qw ( fastq fasta_wrapped fasta ) ],
        );
    
    foreach $format ( keys %formats )
    {
        push @{ $formats{ $format } }, qw ( yaml json table );
    }

    if ( exists $formats{ $orig } ) {
        @out = @{ $formats{ $orig } };
    } else {
        push @msgs, ["ERROR", qq (Index does not support format -> "$orig") ];
    }
    
    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @out : \@out;
}

sub print_about_table
{
    my ( $table,
        ) = @_;

    my ( @table, $row, $str );

    @table = @{ &Storable::dclone( $table ) };

    foreach $row ( @table )
    {
        if ( $row->[1] =~ /^\d+$/ ) {
            $row->[1] = &Common::Util::commify_number( $row->[1] );
        }

        if ( $row->[0] )
        {
            $row->[0] = "  $row->[0] -> ";
            $row->[1] = " $row->[1]";
        }

        $row->[0] = &Common::Tables::ascii_style( $row->[0], { "align" => "right" } );
    }

    unshift @table, [ "Settings    ", " Values" ];

    $table[0]->[0] = &Common::Tables::ascii_style( $table[0]->[0], { "color" => "bold white on_blue", "align" => "right" } );
    $table[0]->[1] = &Common::Tables::ascii_style( $table[0]->[1], { "color" => "bold white on_blue" } );
        
    $str = join "\n", &Common::Tables::render_ascii( \@table );
    
    &echo( "\n". $str."\n\n" );
    
    return;
}

sub process_dump_args
{
    # Niels Larsen, February 2011.

    # Checks input arguments and converts and expands them to something that 
    # is convenient for the routines. If some user input is wrong, this routine 
    # prints a message to console and exits. Returns a configuration hash.

    my ( $args,
        ) = @_;
    
    # Returns a hash.

    my ( %args, @ifiles, $formats, $format, @msgs, $choices, $suffix, $dbh,
         $conf, $file );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Input files may not be duplicated and all must exist,
    
    @ifiles = &Common::Util::uniq_check( $args->ifiles, \@msgs );
    
    $args{"ifiles"} = &Seq::Storage::check_inputs_exist( \@ifiles, \@msgs );

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->outsuf ) {
        $suffix = $args->outsuf;
    } else {
        $suffix = ".". $args->outfmt;
    }

    $args{"ofiles"} = [ map { $_ . $suffix } @ifiles ];

    if ( not $args->clobber ) {
        &Common::File::check_files( $args{"ofiles"}, "!e", \@msgs );
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMAT CHECK <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create error message if the given output format is not supported, or
    # if the output format requires fields that are not in the storage,

    foreach $file ( @ifiles )
    {
        if ( $dbh = &Common::DBM::read_open( $file, "fatal" => 0 ) )
        {
            $conf = &Seq::Storage::get_index_config( $dbh );        
            &Common::DBM::close( $dbh );
            
            &Seq::Storage::check_output_format( $args->outfmt, $conf->seq_format, \@msgs );
        }
        else {
            push @msgs, ["ERROR", qq (Not a sequence index -> "$file") ];
        }
    }

    &append_or_exit( \@msgs );

    $args{"out_format"} = $args->outfmt;

    return wantarray ? %args : \%args;
}

sub process_fetch_args
{
    # Niels Larsen, January 2011.

    # Returns a configuration hash with checked user arguments, plus more
    # derived fields filled in. If some user input is wrong, this routine 
    # prints it to console and exits. 

    my ( $seqh,
         $args,
        ) = @_;
    
    # Returns a hash.

    my ( @msgs, $file, %args, %ndx_fields, $field, @out_fields, $conf,
         $out_format, $choices, $tuple, $mode, $ndx_format, %usr_fields, 
         @usr_fields, @out_formats, $seq_format, $routines, $lc_field );

    $args{"get_size"} = $args->getsize;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FILES AND HANDLES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Sequence and index,

    if ( $seqh )
    {
        if ( ref $seqh )
        {
            $args{"seq_file"} = $seqh->seq_file;

            $args{"seq_handle"} = $seqh->seq_handle;
            $args{"ndx_handle"} = $seqh->ndx_handle;
        }
        elsif ( -r $seqh )
        {
            $args{"seq_file"} = $seqh;

            $seqh = &Seq::Storage::get_handles(
                $seqh,
                {
                    "access" => "read",
                },
                \@msgs );
            
            $args{"seq_handle"} = $seqh->seq_handle;
            $args{"ndx_handle"} = $seqh->ndx_handle;
        }
        else {
            push @msgs, ["ERROR", qq (Sequence file not readable -> "$seqh") ];
        }
    }
    else {
        push @msgs, ["ERROR", qq (No input sequence file given) ];
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

    $args{"seek_size"} = &Common::Util::expand_number( $args->ssize, \@msgs );

    &append_or_exit( \@msgs );    
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FORMATS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Reduce the list of all formats to those supported by the index and then
    # check the user format against those. Get config hash from index,

    $conf = &Seq::Storage::get_index_config( $args{"ndx_handle"} );

    $args{"ndx_type"} = $conf->ndx_type;
    $args{"seq_count"} = $conf->ndx_keys;

    $seq_format = $conf->seq_format;

    if ( not $args->return )
    {
        if ( $out_format = $args->format ) {
            &Seq::Storage::check_output_format( $out_format, $seq_format, \@msgs );
        } else {
            $out_format = $seq_format;
        }
        
        $args{"out_format"} = $out_format;
    }

    &append_or_exit( \@msgs );

    $args{"seq_format"} = $seq_format;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Output fields are by default all those supported by format and index,

    if ( $args->fields )
    {
        @out_fields = &Seq::Storage::format_fields( "valid", $out_format );

        # Use user given field to reduce output fields, but first check that 
        # are among the known ones,

        @usr_fields = split /\s*[, ]+\s*/, lc $args->fields;
    
        # Check for wrong fields,

        foreach $field ( @usr_fields )
        {
            if ( $field ~~  @out_fields ) {
                push @{ $args{"out_fields"} }, $field;
            } else {
                push @msgs, ["ERROR", qq (Unsupported $out_format output field -> "$field") ];
            }
        }
    }

    &append_or_exit( \@msgs );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FIELD SWITCHES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Some fields, like quality and masks, are closely related to sequence and
    # should be indexed into by sub-sequence locators. Other, like annotation
    # fields, should not. Here a hash is made that the retrieval function uses
    # as switch,
    
    $args{"seq_fields"} = &Seq::Storage::format_fields( "seq", $seq_format );

    return wantarray ? %args : \%args;
}

sub save_seqs_derep
{
    # Niels Larsen, December 2012.

    # Given a hash of keys and integer values, loads these keys from 
    # the store, updates the stored values with quality vectors and 
    # and saves the result back into the store.

    my ( $dbh,      # Index store handle
         $new,      # Hash with new values
        ) = @_;

    # Returns nothing.

    my ( $dbm, @keys, $key, $qual, $count, $tuple, $ids );
    
    @keys = keys %{ $new };

    $dbm = &Common::DBM::get_bulk( $dbh, \@keys );

    foreach $key ( @keys )
    {
        if ( exists $dbm->{ $key } )
        {
            if ( $dbm->{ $key } =~ /^(\d*)\t([^\t]*)\t(.*)$/ )
            {
                ( $count, $qual, $ids )= ( $1, $2, $3 );

                $tuple = $new->{ $key };

                if ( $qual ) {
                    &Seq::Storage::max_qualities_C( \$qual, \$tuple->[1], length $tuple->[1] );
                }

                $dbm->{ $key } = ( $tuple->[0] + $count )."\t". $qual ."\t". $tuple->[2] . $ids;
            }
            else {
                &error( qq (Wrong looking dbm derep value -> "$dbm->{ $key }") );
            }
        }
        else {
            $dbm->{ $key } = join "\t", @{ $new->{ $key } };
        }
    }

    &Common::DBM::put_bulk( $dbh, $dbm );

    return;
}

sub set_index_config
{
    # Niels Larsen, January 2011. 

    # Saves the stores configuration hash.

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

    $conf = &Seq::Storage::get_index_config( $fh );

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
    # Niels Larsen, January 2011.

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

    my ( $defs, $params, $seq_fmt, $seq_num, $seq_len, $mem_map, 
         $bkt_num, $align, $page_cache, $name, $ndx_type, $blk_pool,
         $ram_avail, $id_len, $ndx_size, $new_size, $file_avg, 
         $ndx_stats, $key_count );
    
    $defs = {
        "id_len" => undef,
        "seq_format" => undef,
        "seq_num" => undef,
        "ndx_type" => undef,
        "ndx_stats" => {},
    };

    $args = &Registry::Args::create( $args, $defs );

    $id_len = $args->{"id_len"};
    $seq_fmt = $args->{"seq_format"};
    $ndx_type = $args->{"ndx_type"};
    $ndx_stats = $args->{"ndx_stats"};
    
    $ram_avail = &Common::OS::ram_avail();

    $seq_num = $args->{"seq_num"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TUNE_ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $align = 256;      # default 256
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>> FREE BLOCK POOL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $blk_pool = 10;    # default 10
    
    # >>>>>>>>>>>>>>>>>>>>>>> PAGE CACHE / MEMORY MAP <<<<<<<<<<<<<<<<<<<<<<<<<

    $ndx_size = $ndx_stats->{"realsize"} // 0;
    $new_size = -s $file;

    # This tries to create good kyoto settings based on the expected index 
    # sizes,

    if ( $ndx_type eq "fetch_fixpos" )
    {
        # This mode is for records of exact same lengths, where the index only 
        # holds zero based running integers. Index size depends on key length
        # and integer (the 2x multiplication seems to work best),

        $ndx_size += 2.0 * $seq_num * ( $id_len + 5 ); 
    }
    elsif ( $ndx_type eq "fetch_varpos" )
    {
        if ( $seq_fmt eq "fasta" ) {
            $seq_len = int $new_size / $seq_num;
        } elsif ( $seq_fmt eq "fastq" ) {
            $seq_len = int 0.5 * $new_size / $seq_num;
        } elsif ( $seq_fmt eq "genbank" or $seq_fmt eq "embl" ) {
            $seq_len = int 0.3 * $new_size / $seq_num;
        } else {
            &error( qq (Wrong looking format -> "$seq_fmt") );
        }

        $file_avg = int $new_size / 2;
        $ndx_size += 1.5 * $seq_num * ( $id_len + (length "$seq_len") + 1 + (length "$file_avg") );
    }
    else {
        $ndx_size += $new_size * 1.3;
    }
    
    $ndx_size = int $ndx_size;

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
    
    $key_count = $seq_num + ( $ndx_stats->{"count"} // 0 );  # Upper estimate

    if ( $seq_fmt eq "fasta" ) {
        $bkt_num = int &List::Util::max( 1, $key_count * 0.12 );
    } elsif ( $seq_fmt eq "fastq" ) {
        $bkt_num = int &List::Util::max( 1, $key_count * 0.12 );
    } elsif ( $seq_fmt eq "genbank" or $seq_fmt eq "embl" ) {
        $bkt_num = int &List::Util::max( 1, $key_count * 0.12 );
    }
    else {
        &error( qq (Need to update set_kyoto_params with format "$seq_fmt") );
    }

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

sub set_rec_parser
{
    # Niels Larsen, February 2011.

    # Returns a reference to a routine that parses a record and makes hash 
    # structure with record information. It is defined to handle the current
    # sequence format and index type.

    my ( $seq_format,     # Sequence format
         $ndx_type,       # Index format
        ) = @_;

    # Returns code ref. 

    my ( $regexp, $struct, $parse_sub );

    if ( $seq_format eq "fastq" )
    {
        if ( $ndx_type eq "fetch_embed" ) {
            $regexp = q (([^\t]*)\t(\S+));
        } else {
            $regexp = q (\S+ ?([^\n]*)\n(\S+)\n[^\n]+\n([^\n]+));
        }

        $struct = q ({ "id" => $id, "info" => $1, "seq" => $2, "qual" => $3 });
    }
    elsif ( $seq_format eq "fasta" )
    {
        if ( $ndx_type eq "fetch_embed" ) {
            $regexp = q (([^\t]*)\t(\S+));
        } else {
            $regexp = q (>\S+\s*([^\n]*?)\s*\n([^\n]+));
        }

        $struct = q ({ "id" => $id, "info" => $1, "seq" => $2 });
    }
    else {
        &error( qq (Wrong looking format -> "$seq_format") );
    }

    $parse_sub = eval qq (sub
{
    my ( \$id, \$ref ) = \@_;

    if ( \${ \$ref } =~ /^$regexp/s )
    {
        return $struct;
    }
    else {
        &error( qq (Problem with $seq_format entry in $ndx_type mode:\n\n) . \${ \$ref } );
    }
}
);

    return $parse_sub;
}

sub write_derep_stats
{
    # Niels Larsen, February 2012. 

    # Writes a Config::General formatted file with a few tags that are 
    # understood by Recipe::Stats::html_body. Composes a string that is 
    # either returned (if defined wantarray) or written to file. 

    my ( $sfile,
         $stats,
        ) = @_;

    # Returns a string or nothing.
    
    my ( $fh, $text, $iseqs, $oseqs, $title, $steps, $step, $fstep, $secs, 
         $iseq, $ires, $oseq, $ores, $seqdif, $resdif, $seqpct, $respct,
         $lstep, $time, $ifile, $ofile );

    $iseqs = $stats->{"iseqs"};

    $oseqs = $stats->{"oseqs"};
    # $oseqs->{"value"} =~ s/\.derep(\..+)$/$1/;
    $oseqs->{"value"} =~ s/\.derep$//;
    
    $steps = $stats->{"steps"};

    $fstep = $steps->[0];
    $lstep = $steps->[-1];

    $time = &Time::Duration::duration( $stats->{"seconds"} );

    # >>>>>>>>>>>>>>>>>>>>>>>> FILES AND PARAMETERS <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ifile = &File::Basename::basename( $iseqs->{"value"} );
    $ofile = &File::Basename::basename( $oseqs->{"value"} );

    $text = qq (
<stats>

   title = $stats->{"title"}
   name = $stats->{"name"}

   <header>
      file = $iseqs->{"title"}\t$ifile
      file = $oseqs->{"title"}\t$ofile
      date = $stats->{"finished"}
      secs = $stats->{"seconds"}
      time = $time
   </header>

   <table>
      title = De-replication counts by file
      colh = \tSeqs\t&Delta;\t&Delta; %
      trow = Input\t$fstep->{"iseq"}\t\t
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $step ( @{ $steps } )
    {
        $iseq = $step->{"iseq"};
        $oseq = $step->{"oseq"};

        $seqdif = $oseq - $iseq;

        $seqpct = ( sprintf "%.1f", 100 * $seqdif / $iseq );

        $text .= qq (      trow = Output\t$oseq\t$seqdif\t$seqpct\n);
    }

    $text .= qq (   </table>\n\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

sub write_derep_stats_sum
{
    # Niels Larsen, October 2012. 

    # Reads the content of the given list of statistics files and generates a 
    # summary table. The input files are written by write_derep_stats above. The 
    # output file has a tagged format understood by Recipe::Stats::html_body. A 
    # string is returned in list context, otherwise it is written to the given
    # file or STDOUT. 

    my ( $files,       # Input statistics files
         $sfile,       # Output file
        ) = @_;

    # Returns a string or nothing.
    
    my ( $stats, $text, $file, $ifile, $rows, $secs, @row, @table, $iseq, 
         $oseq, $str, $row, $ofile, $time, $spct, @dates, $date );

    # Create table array by reading all the given statistics files and getting
    # values from them,

    @table = ();
    $secs = 0;

    foreach $file ( @{ $files } )
    {
        $stats = &Recipe::IO::read_stats( $file )->[0];

        $rows = $stats->{"headers"}->[0]->{"rows"};

        $ofile = $rows->[1]->{"value"};
        $secs += $rows->[3]->{"value"};

        $rows = $stats->{"tables"}->[0]->{"rows"};
        
        @row = split "\t", $rows->[0]->{"value"};
        $iseq = $row[1];

        @row = split "\t", $rows->[-1]->{"value"};
        $oseq = $row[1];

        $iseq =~ s/,//g;
        $oseq =~ s/,//g;

        push @table, [ "file=$ofile",
                       $iseq, $oseq, 100 * ( $iseq - $oseq ) / $iseq,
        ];
    }

    # Sort descending by input sequences, 

    @table = sort { $b->[1] <=> $a->[1] } @table;
    
    # Calculate totals,

    $iseq = &List::Util::sum( map { $_->[1] } @table );
    $oseq = &List::Util::sum( map { $_->[2] } @table );
    $spct = sprintf "%.1f", 100 * ( ( $iseq - $oseq ) / $iseq );

    $time = &Time::Duration::duration( $secs );

    $stats = bless &Recipe::IO::read_stats( $files->[0] )->[0];
    $date = &Recipe::Stats::head_type( $stats, "date" );
    
    # Format table,

    $text = qq (
<stats>
   title = $stats->{"title"}
   <header>
       hrow = Total input reads\t$iseq
       hrow = Total output reads\t$oseq (-$spct%)
       date = $date
       secs = $secs
       time = $time
   </header>
   <table>
      title = De-replication counts by file
      colh = Output files\tIn-reads\tOut-seqs\t&Delta; %
);
    
    foreach $row ( @table )
    {
        $row->[1] //= 0;
        $row->[2] //= 0;
        $row->[3] = "-". sprintf "%.1f", $row->[3];

        $str = join "\t", @{ $row };
        $text .= qq (      trow = $str\n);
    }

    $text .= qq (   </table>\n</stats>\n\n);

    if ( defined wantarray )
    {
        return $text;
    }
    else {
        &Common::File::write_file( $sfile, $text );
    }

    return;
}

1;

__DATA__

__C__

static void* get_str( SV* obj ) { return SvPVX( SvRV( obj ) ); }

#define GET_STR1( obj )   char* str1 = get_str( obj )
#define GET_STR2( obj )   char* str2 = get_str( obj )

#define MAXIMIZE( ndx )   if ( str1[ ndx ] < str2[ ndx ] ) { str1[ ndx ] = str2[ ndx ]; }

void max_qualities_C( SV* quals1, SV* quals2, int strlen )
{
    GET_STR1( quals1 );
    GET_STR2( quals2 );

    int i;

    for ( i = 0; i < strlen; i++ )
    {
        MAXIMIZE( i );
    }
    
}

__END__

# sub save_seq_quals
# {
#     # Niels Larsen, February 2011.

#     # Given a hash of keys and integer values, loads these keys from 
#     # the store, updates the stored values with quality vectors and 
#     # and saves the result back into the store.

#     my ( $dbh,      # Index store handle
#          $new,      # Hash with new values
#         ) = @_;

#     # Returns nothing.

#     my ( $dbm, @keys, $key, $qual, $count, $tuple );
    
#     @keys = keys %{ $new };

#     $dbm = &Common::DBM::get_bulk( $dbh, \@keys );

#     foreach $key ( @keys )
#     {
#         if ( exists $dbm->{ $key } )
#         {
#             if ( $dbm->{ $key } =~ /^([^\t]+)\t(\d+)$/ )
#             {
#                 ( $qual, $count )= ( $1, $2 );

#                 $tuple = $new->{ $key };

#                 &Seq::Storage::max_qualities_C( \$qual, \$tuple->[0], length $tuple->[0] );

#                 $dbm->{ $key } = "$qual\t". ( $count + $tuple->[1] );
#             }
#             else {
#                 &error( qq (Wrong looking dbm derep value -> "$dbm->{ $key}") );
#             }
#         }
#         else {
#             $dbm->{ $key } = $new->{ $key }->[0] ."\t". $new->{ $key }->[1];
#         }
#     }

#     &Common::DBM::put_bulk( $dbh, $dbm );

#     return;
# }

# sub create_index_embed_old
# {
#     # Niels Larsen, February 2011.

#     # Creates a key/value storage where key is id and value is sequence and/or
#     # quality, depending on original input format.

#     my ( $ifh,     # Input fasta handle
#          $ofh,     # Output index handle
#          $args,    # Arguments hash - OPTIONAL
#         ) = @_;

#     # Returns nothing.
    
#     my ( $buf_size, $byt_count, %index, $entry, $seq_format, $ndx_type, 
#          $setter, $counter, $rec_sub, $regexp, $hdr_regex );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $buf_size = $args->{"buf_size"};

#     $seq_format = $args->{"seq_format"};
#     $ndx_type = $args->{"ndx_type"};    
#     $hdr_regex = $args->{"hdr_regex"} // '(\S+)';

#     local $/ = $args->{"rec_sep"};

#     if ( $seq_format eq "fastq" )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTQ FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<

#         $regexp = q (\@?(\S+)[^\n]*\n(\S+)\n[^\n]+\n([^\n]+));
#         $setter = q ($index{ $1 } = "$2\t$3");
#         $counter = q ($byt_count += length $index{ $1 });        
#     }
#     elsif ( $seq_format eq "fasta" )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTA FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
# #        $regexp = q (>?$hdr_regex\s*([^\n]*?)\s*\n([^\n]+)\n);
#         $regexp = q (>?$hdr_regex\s*([^\n]*)\n([^\n]+)\n);
#         $setter = q ($index{ $1 } = ( $2 // "" ) ."\t$3");
#         $counter = q ($byt_count += length $index{ $1 });
#     }
#     else {
#         &error( qq (Unsupported format -> "$seq_format") );
#     }

#     # Set routine run below,

#     $rec_sub = eval qq (sub
# {
#     if ( \$entry =~ /^$regexp/s )
#     {
#         $setter;
#         $counter;
#     }
#     else {
#         &error( qq (Trouble entry:\n\n\$entry) );
#     }
# }
# );        
        
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     while ( 1 )
#     {
#         %index = ();
#         $byt_count = 0;
        
#         while ( $entry = <$ifh> )
#         {
#             $rec_sub->();

#             last if $byt_count >= $buf_size;
#         }

#         last if not %index;
        
#         &Common::DBM::put_bulk( $ofh, \%index );
#     }

#     return;
# }


# sub create_index_varpos_old
# {
#     # Niels Larsen, January 2011.

#     # Creates a index file for a given fasta file with sequences as single 
#     # lines. The index file path is returned. 

#     my ( $ifh,     # Input sequence handle
#          $ofh,     # Output index handle
#          $args,    # Arguments hash - OPTIONAL
#         ) = @_;

#     # Returns string. 

#     my ( $defs, $buf_size, $byt_count, %index, $entry, $ent_len, $file_pos,
#          $hdr_str, $hdr_regex );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $buf_size = $args->{"buf_size"};
#     $hdr_str = $args->{"hdr_str"};
#     $hdr_regex = $args->{"hdr_regex"} // '(\S+)';

#     local $/ = $args->{"rec_sep"};

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FIRST ENTRY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     # As we read in chunks the first entry starts with a lead string (@ or > 
#     # and similar) but the rest do not. So the right start file positions for
#     # remaining entries should be one less,

#     $entry = <$ifh>;

#     if ( $entry =~ /^$hdr_str$hdr_regex/s )
#     {
#         $ent_len = ( length $entry ) - 1;
#         &Common::DBM::put( $ofh, $1, "0\t$ent_len" );

#         $file_pos = $ent_len;
#     }
#     else {
#         &error( qq (Trouble entry:\n\n$entry) );
#     }
    
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> REMAINING ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<

#     # These chunks do not start with a lead character, but they end with one, 
#     # except the last one. But $file_pos is one behind from above, so it will
#     # be right. This reads 4-line chunks and fills a hash with buf_size entries
#     # and the stored in bulk,

#     while ( 1 )
#     {
#         %index = ();
#         $byt_count = 0;

#         while ( $entry = <$ifh> )
#         {
#             if ( $entry =~ /^$hdr_regex/ )
#             {
#                 $ent_len = length $entry;
#                 $index{ $1 } = "$file_pos\t$ent_len";

#                 $file_pos += $ent_len;
#                 $byt_count += $ent_len;
#             }
#             else {
#                 &error( qq (Problem entry:\n\n$entry) );
#             }
            
#             last if $byt_count > $buf_size;
#         }

#         last if not %index;

#         &Common::DBM::put_bulk( $ofh, \%index );
#     }

#     return;
# }

# sub create_index_fixpos_old
# {
#     # Niels Larsen, February 2011.

#     # Creates a an index with id keys and running integers as values. This 
#     # makes a smaller index when all records have exactly the same size but
#     # will fail at the slightest deviation from that rule. However if the 
#     # last record parses fine then it would be very unlikely there is a
#     # problem.

#     my ( $ifh,     # Input sequence handle
#          $ofh,     # Output index handle
#          $args,    # Arguments hash - OPTIONAL
#         ) = @_;

#     # Returns string. 

#     my ( $defs, $buf_size, $byt_count, $seq_count, %index, $entry, $rec_sep,
#          $hdr_str, $hdr_regex );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $buf_size = $args->{"buf_size"};
#     $hdr_str = $args->{"hdr_str"};
#     $hdr_regex = $args->{"hdr_regex"} // '(\S+)';

#     local $/ = $args->{"rec_sep"};

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FIRST ENTRY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     # First entry starts with lead string, the rest do not. So reduce entry 
#     # length and file position by one, and it will be fine again below,

#     $entry = <$ifh>;

#     $seq_count = 0;

#     if ( $entry =~ /^$hdr_str$hdr_regex/ )
#     {
#         &Common::DBM::put( $ofh, $1, ++$seq_count );
#     }
#     else {
#         &error( qq (Trouble entry:\n\n$entry) );
#     }
        
#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>> REMAINING ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<

#     # These chunks do not start with a lead character, but they end with one, 
#     # except the last one. But $file_pos is one behind from above, so it will
#     # be right. This reads 4-line chunks and fills a hash with buf_size entries
#     # and the stored in bulk,

#     while ( 1 )
#     {
#         %index = ();
#         $byt_count = 0;

#         while ( $entry = <$ifh> )
#         {
#             if ( $entry =~ /^$hdr_regex/ )
#             {
#                 $index{ $1 } = ++$seq_count;
#                 $byt_count += 10;
#             }
#             else {
#                 &error( qq (Problem entry:\n\n$entry) );
#             }
            
#             last if $byt_count > $buf_size;
#         }            

#         last if not %index;

#         &Common::DBM::put_bulk( $ofh, \%index );
#     }

#     return;
# }

# sub create_index_derep_old
# {
#     # Niels Larsen, February 2011.

#     # Uniqifies completely identical sequences and updates quality strings 
#     # with maximum quality at each position. Taking a simple maximum is maybe
#     # dangerous, but will refine. 

#     my ( $ifh,     # Input sequence handle
#          $ofh,     # Output index handle
#          $args,    # Arguments hash - OPTIONAL
#         ) = @_;

#     # Returns nothing. 

#     my ( $buf_size, $byt_count, $seq_count, %index, $entry, $regexp, $counts,
#          $setter, $saver, $counter, $ndx_type, $seq_format, $code, $has_counts );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $buf_size = 50_000_000;

#     $seq_format = $args->{"seq_format"};
#     $has_counts = $args->{"has_counts"};
#     $ndx_type = $args->{"ndx_type"};

#     local $/ = $args->{"rec_sep"};

#     if ( $seq_format eq "fastq" )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTQ FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<

#         $regexp = q (\@?(\S+)[^\n]*\n(\S+)\n[^\n]+\n([^\n]+));
        
#         if ( $ndx_type eq "derep_seq" )
#         {
#             $setter = q ($index{ $2 } += 1);
#         }
#         else 
#         {
#             $setter = q (if ( exists $index{ $2 } )
#                  {
#                      &Seq::Storage::max_qualities_C( \$index{ $2 }->[0], \$3, length $3 );
#                      $index{ $2 }->[1] += 1;
#                  }
#                  else {
#                      $index{ $2 } = [ $3, 1 ];
#                  }
# );

#             $counter = q ($byt_count += length $3);
#             $saver = "&Seq::Storage::save_seq_quals";
#         }
#     }
#     elsif ( $seq_format eq "fasta" )
#     {
#         # >>>>>>>>>>>>>>>>>>> FASTA SINGLE LINE FORMAT <<<<<<<<<<<<<<<<<<<<<<<<

#         if ( $has_counts )
#         {
#             $regexp = q (>?\S+\s*[^\n]*?seq_count=(\d+)[^\n]*\n([^\n]+)\n);
#             $setter = q ($index{ $2 } += $1);
#             $counter = q ($byt_count += length $2);
#         }
#         else
#         {
#             $regexp = q (>?\S+\s*[^\n]*?\s*\n([^\n]+)\n);
#             $setter = q ($index{ $1 } += 1);
#             $counter = q ($byt_count += length $1);
#         }

#         $saver = "&Seq::Storage::save_seq_counts";
#     }
#     else {
#         &error( qq (Unsupported format -> "$seq_format") );
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SET CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # This code is the same for all formats and settings variables are expanded
#     # to their values,

#     $code = qq (

#     \$seq_count = 0;

#     while ( 1 )
#     {
#         \%index = ();
#         \$byt_count = 0;
        
#         while ( \$entry = <\$ifh> )
#         {
#      &dump( \$entry );
#             \$seq_count += 1;

#             if ( \$entry =~ /^$regexp/s )
#             {
#                  $setter;
#                  $counter;
#             }
#             else {
#                 &error( qq (Trouble entry:\n\n\$entry) );
#             }

#             last if \$byt_count >= $buf_size;
#         }

#         last if not \%index;

#         $saver( \$ofh, \\%index );
#     }
# );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN CODE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     &dump( $code );
#     eval $code;

#     $counts->{"iseq"} = $seq_count;
#     $counts->{"oseq"} = $seq_count; # $ofh->seq_count;
    
#     return wantarray ? %{ $counts } : $counts;
# }
