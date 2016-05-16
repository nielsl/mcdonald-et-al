package Seq::IO;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that read and write sequences and related things.
#
# TODO: there are Seq::Clean::seqs_filter, Seq::IO::spool_seqs, Seq::IO::grep_fasta
# and Seq::IO::select_seqs that all filter a sequence file by some criteria. 
# Consolidate these. 
#
# TODO: check that the Seq::IO::get_* routines work, including genbank and ebi
#
# TODO: databank indexing is broke - can wait
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;
use IO::Compress::Gzip qw( gzip $GzipError );
use IO::Uncompress::Gunzip qw( gunzip $GunzipError ) ;
use IO::String;
use feature qw( :5.10 );
use Fcntl qw ( SEEK_SET SEEK_CUR SEEK_END );
use English;
use Tie::IxHash;
use Data::MessagePack;
use IO::Unread;
use Capture::Tiny ':all';
use Config::General;

use Common::Config;
use Common::Messages;

use Common::File;
use Common::OS;
use Common::DBM;
use Common::Types;
use Common::Table;

use Registry::Get;
use Registry::Args;
use Registry::Register;
use Registry::Check;

use Seq::Common;
use Seq::List;
use Seq::Info;
use Seq::Storage;

use Inline C => 'DATA';

Inline->init;

use base qw ( Seq::Common Seq::Features );

our $DB_access;

END { &Seq::IO::close_db_access( $DB_access ) };

our @Fields = qw ( seq_file seq_handle ndx_file ndx_handle );
our %Fields = map { $_, 1 } @Fields;

# These are used here, but also by other modules,

our @Bar_titles = qw ( ID F-tag R-tag );
our @Pri_titles = qw ( Pat Orient Mol Name );

our $Max_int = 2 ** 30;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINE LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# close_db_access
# close_handle
# detect_file
# detect_files
# detect_format
# detect_record_size
# detect_record_sizes
# get_ids_fasta
# get_read_routine
# get_write_routine
# get_seq
# get_seqs
# get_seqs_file
# merge_seq_files
# open_db_access
# read_locators
# read_ids
# read_ids_fasta
# read_pairs_table
# read_pairs_expr
# read_patterns
# read_primer_conf
# read_seq_fasta
# read_seq_fasta_wrapped
# read_seq_fastq
# read_seqs_fasta
# read_seqs_fasta_fixpos
# read_seqs_fasta_varpos
# read_seqs_fasta_wrapped
# read_seqs_fastq
# read_seqs_fastq_check
# read_seqs_fastq_fixpos
# read_seqs_fastq_varpos
# read_seqs_file
# read_seqs_filter
# read_seqs_first
# read_seqs_genbank
# read_seqs_genbank_varpos
# read_skip_fasta
# read_skip_fastq
# read_table_primers
# read_table_tags
# search_db
# search_db_recurse
# seek_4bit
# select_seqs
# select_seqs_fasta
# select_seqs_fastq
# split_id
# split_seqs_fasta
# spool_seqs_fasta
# trim_fasta_ids
# write_locators
# write_seq_fasta
# write_seq_fastq
# write_seqs_fasta
# write_seqs_fastq
# write_seqs_file
# write_seqs_handle
# write_seqs_ids
# write_seqs_json
# write_seqs_table
# write_seqs_yaml
# write_table_seqs
# 
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub AUTOLOAD
{
    # Niels Larsen, November 2009.
    
    # Creates missing accessors.
    
    &_new_accessor( @_ );
}

sub _new_accessor
{
    # Niels Larsen, May 2007.

    # Creats a get/setter method if 1) it is not already defined (explicitly
    # or by this routine) and 2) its name are among the keys in the hash given.
    # Attempts to use methods not in @Fields will trigger a crash with 
    # trace-back.

    my ( $self,         # Sequence object 
         ) = @_;

    # Returns nothing.

    our $AUTOLOAD;
    my ( $field, $pkg, $code, $str );

    caller eq __PACKAGE__ or &error( qq(May only be called from within ). __PACKAGE__ );

    # Isolate name of the method called and the object package (in case it is
    # not this package),

    return if $AUTOLOAD =~ /::DESTROY$/;

    $field = $AUTOLOAD;
    $field =~ s/.*::// ;

    $pkg = ref $self;

    # Create a code string that defines the accessor and crashes if its name 
    # is not found in the object hash,

    $code = qq
    {
        package $pkg;
        
        sub $field
        {
            my \$self = shift;
            
            if ( exists \$Fields{"$field"} )
            {
                \@_ ? \$self->{"$field"} = shift : \$self->{"$field"};
            } 
            else
            {
                local \$Common::Config::with_stack_trace;
                \$Common::Config::with_stack_trace = 0;

                &user_error( &Seq::IO::accessor_help( \$field ), "PROGRAMMER ERROR" );
                exit -1;
            }
        }
    };

    eval $code;
    
    if ( $@ ) {
        &error( "Unkown method $AUTOLOAD : $@" );
    }
    
    goto &{ $AUTOLOAD };
    
    return;
};

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub close_db_access
{
    # Niels Larsen, February 2010.

    # Closes the handles opened with open_db_access.

    my ( $dbhs,      # Handles hash
        ) = @_;
    
    # Returns nothing.

    my ( $db_name, $dbh, $key );

    foreach $db_name ( keys %{ $dbhs } )
    {
        $dbh = $dbhs->{ $db_name };
        
        foreach $key ( keys %{ $dbh } )
        {
            if ( $key =~ /ndx_handle$/ ) {
                &Common::DBM::close( $dbh->{ $key } );
            } elsif ( $key =~ /file_handle$/ ) {
                $dbh->{ $key }->close;
            }
        }
    }

    return;
}

sub close_handle
{
    # Niels Larsen, May 2010.

    # Closes an indexed sequence file handle. Returns a hash 
    # without open handles.

    my ( $fh,
        ) = @_;

    # Returns a hash.

    &Common::File::close_handle( $fh->seq_handle );
    delete $fh->{"seq_handle"};
    
    if ( $fh->{"ndx_handle"} )
    {
        &Common::DBM::close( $fh->ndx_handle );
        delete $fh->{"ndx_handle"};
    }

    return $fh;
}

sub detect_file
{
    # Niels Larsen, February 2011.

    # Returns a hash with file path and size, id length, sequence format, 
    # record separator and header lead string. The top of the file (first
    # 1000 bytes by default) is looked at. The keys in the returned hash
    # are: file_path, file_size, id_len, seq_format, has_counts, is_wrapped,
    # rec_sep, hdr_str.

    my ( $file,    # Sequence file
         $buflen,  # Buffer length - OPTIONAL, default 1000
         $msgs,
        ) = @_;

    # Returns a hash.

    my ( $stats, $buffer, $fh, $seq_format, $rec_sep, $hdr_str, $stderr,
         $id_len, $is_wrapped, $has_counts, $has_quals, @msgs );

    $buflen //= 1000;
    $is_wrapped = 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MUST EXIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &Common::File::check_files([ $file ], "efr" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> STDERR CAPTURE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Feb 2013 - why is this capture needed, why not always bail? 

#    $stderr = capture_stderr
#    {
        if ( ref $file ) {
            $fh = $file;
        } else {
            $fh = &Common::File::get_read_handle( $file );
        }
    
        read $fh, $buffer, $buflen;
        
        &Common::File::close_handle( $fh ) if not ref $file;
#    };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> SFF FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $buffer =~ /^.sff/ )
    {
        $seq_format = "sff";
        $has_quals = 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTQ FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $buffer =~ /^@(\S+)/s )
    {
        $id_len = length $1;
        $seq_format = "fastq";
        $has_quals = 1;

        $rec_sep = "\n\@";
        $hdr_str = "\@";
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FASTA FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $buffer =~ /^>(\S+)/s )
    {
        $id_len = length $1;

        $rec_sep = "\n>";
        $hdr_str = ">";

        if ( $buffer =~ /\n[^>]+\n[^>]+/s ) {
            $seq_format = "fasta_wrapped";
            $is_wrapped = 1;
        } else {
            $seq_format = "fasta";
        }

        $has_quals = $buffer =~ /seq_quals=/ ? 1 : 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GENBANK FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
    elsif ( $buffer =~ /^LOCUS       (\S+)/s )
    {
        $id_len = length $1;

        $rec_sep = "\n//";
        $seq_format = "genbank";

        $has_quals = 0;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLE FORMAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $buffer =~ /\t/ )
    {
        $seq_format = "table";
        $has_quals = 0;
    }
    elsif ( not $buffer )
    {
        &error( qq (File is empty -> "$file"), $msgs );
    }
    else {
        &error( qq (Unrecognized format -> "$buffer"), $msgs );
    }
    
    $stats = {
        "file_path" => $file,
        "file_size" => -s $file,
        "seq_format" => $seq_format,
        "has_counts" => $buffer =~ /seq_count=\d+/ ? 1 : 0,
        "has_quals" => $has_quals,
        "is_wrapped" => $is_wrapped,
    };

    $stats->{"id_len"} = $id_len if defined $id_len;
    $stats->{"rec_sep"} = $rec_sep if defined $rec_sep;
    $stats->{"hdr_str"} = $hdr_str if defined $hdr_str;

    return wantarray ? %{ $stats } : $stats;
}

sub detect_files
{
    # Niels Larsen, February 2011. 

    # Runs detect_file on a list of files. Returns a list of 
    # statistics outputs from detect_file. 
    
    my ( $files,         # List of file names
        ) = @_;

    # Returns a list. 

    my ( $file, @stats );

    foreach $file ( @{ $files } )
    {
        push @stats, { &Seq::IO::detect_file( $file ) };
    }

    return wantarray ? @stats : \@stats;
}

sub detect_format
{
    # Niels Larsen, December 2011. 

    # Returns the format of a given sequence file. 

    my ( $file,
         $msgs,
        ) = @_;

    return &Seq::IO::detect_file( $file, undef, $msgs )->{"seq_format"};
}

sub detect_record_size
{
    # Niels Larsen, February 2011.

    # Reads the first entry of the given file and returns the byte size
    # of that record, ie how much room that unparsed record takes up in 
    # the file. 

    my ( $file,
        ) = @_;

    # Returns integer. 

    my ( $format, $line, $fh, $rec_size );

    $format = &Seq::IO::detect_format( $file );

    $fh = &Common::File::get_read_handle( $file );

    $rec_size = 0;
    
    if ( $format eq "fastq" )
    {
        map { $rec_size += length ( $line = <$fh> ) } ( 1 .. 4 );
    }
    elsif ( $format eq "fasta" )
    {
        map { $rec_size += length ( $line = <$fh> ) } ( 1 .. 2 );
    }
    else {
        &error( qq (Unrecognized format -> "$format") );
    }
    
    &Common::File::close_handle( $fh );

    return $rec_size;
}

sub detect_record_sizes
{
    # Niels Larsen, February 2011. 

    # Reads the first entry of each of the given list of files. Returns 
    # a list of sizes.
 
    my ( $files,
        ) = @_;

    my ( $file, @sizes );

    foreach $file ( @{ $files } )
    {        
        push @sizes, &Seq::IO::detect_record_size( $file );
    }

    return wantarray ? @sizes : \@sizes;
}

sub get_ids_fasta
{
    # Niels Larsen, October 2010.

    # Checks IDs in a fasta file for duplicates, length and wrong looks.
    # Error messages are printed to STDOUT. Command line arguments are,

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, %seen, $seq, $id, $regex, @msgs, $len, $ifh, $ofh, 
         $ofile, $minlen, $maxlen, $print_sub, $count, $key, $field, $text,
         $text2 );

    $defs = {
        "ifile" => undef,
        "ofile" => undef,
        "dup" => undef,
        "nodup" => undef,
        "seqs" => 0,
        "regex" => undef,
        "noregex" => undef,
        "minlen" => undef,
        "maxlen" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );

    if ( not defined $args->dup and
         not defined $args->nodup and
         not defined $args->regex and
         not defined $args->noregex and
         not defined $args->minlen and
         not defined $args->maxlen )
    {
        push @msgs, ["ERROR", qq (Please specify an ID check condition) ];
    }

    if ( defined $args->dup and defined $args->nodup ) {
        push @msgs, ["ERROR", qq (--dup and --nodup are exclusive) ];
    }

    if ( defined $args->regex and defined $args->noregex ) {
        push @msgs, ["ERROR", qq (--regex and --noregex are exclusive) ];
    }
    
    if ( $args->ofile ) {
        &Common::File::check_files( [ $args->ofile ], "!e", \@msgs );
    }

    &append_or_exit( \@msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> PRINT FUNCTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->ofile ) 
    {
        $print_sub = sub {
            my ( $fh, $id, $type, $msg ) = @_;
            $fh->print( "$id\t$type\t$msg\n" );
            return 1;
        };
    }
    else 
    {
        $print_sub = sub {
            my ( $fh, $id, $type, $msg ) = @_;
            $type eq "ERROR" ? ( $type = &echo_red( $type ) ) : ( $type = &echo_green( $type ) );
            $fh->print( $type. ":  ". &echo( "$msg\n" ) );
            return 1;
        };
    }

    $ofh = &Common::File::get_write_handle( $args->ofile );
    $count = 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DUPLICATES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $args->dup or defined $args->nodup )
    {
        $ifh = &Common::File::get_read_handle( $args->ifile );
        tie %seen, "Tie::IxHash";

        while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
        {
            $id = $seq->id;
            exists $seen{ $id } ? ( $seen{ $id } += 1 ) : ( $seen{ $id } = 1 );
        }

        if ( defined $args->dup )
        {
            foreach $key ( keys %seen )
            {
                if ( $seen{ $key } > 1 ) {
                    $count += $print_sub->( $ofh, $id, "ERROR", qq (ID is duplicate -> "$key") );
                }
            }
        }
        elsif ( defined $args->nodup )
        {
            foreach $key ( keys %seen )
            {
                if ( $seen{ $key } == 1 ) {
                    $count += $print_sub->( $ofh, $id, "OK", qq (ID is unique -> "$key") );
                }
            }
        }            

        undef %seen;
        &Common::File::close_handle( $ifh );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> REGEX <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ifh = &Common::File::get_read_handle( $args->ifile );

    if ( $args->regex or $args->noregex )
    {
        if ( $args->seqs ) {
            $field = "seq"; $text = "Sequence";
        } else {
            $field = "id"; $text = "ID";
        }

        if ( $regex = $args->regex )
        {
            while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
            {
                if ( $seq->$field =~ /$regex/i )
                {
                    $id = $seq->id;
                    $count += $print_sub->( $ofh, $id, "OK", qq ($text matches '$regex' -> "$id"));
                }
            }
        }
        elsif ( $regex = $args->noregex )
        {
            while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
            {
                if ( $seq->$field !~ /$regex/i )
                {
                    $id = $seq->id;
                    $count += $print_sub->( $ofh, $id, "OK", qq ($text does not match '$regex' -> "$id"));
                }
            }
        }            
    }

    &Common::File::close_handle( $ifh );
        
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> LENGTH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ifh = &Common::File::get_read_handle( $args->ifile );

    if ( $minlen = $args->minlen or $maxlen = $args->maxlen )
    {
        if ( $args->seqs ) {
            $field = "seq"; $text = "Sequence";
        } else {
            $field = "id"; $text = "ID";
        }

        while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
        {
            if ( $field eq "seq" ) {
                $seq->delete_gaps;
            }

            $len = length $seq->$field;
            $id = $seq->id;
        
            if ( defined $minlen and $len < $minlen )
            {
                $len = &Common::Util::commify_number( $len );
                $count += $print_sub->( $ofh, $id, "ERROR", qq ($text shorter than $minlen (is $len) -> "$id") );
            }
            elsif ( defined $maxlen and $len > $maxlen )
            {
                $len = &Common::Util::commify_number( $len );
                $count += $print_sub->( $ofh, $id, "ERROR", qq ($text longer than $maxlen (is $len) -> "$id") );
            }                
        }
    }

    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );
    
    if ( $ofile = $args->ofile ) {
        $text2 = " in $ofile";
    } else {
        $text2 = "";
    }

    if ( $count == 0 ) {
        $text = "No messages";
    } elsif ( $count > 1 ) {
        $text = "$count messages$text2";
    } else {
        $text = "1 message$text2";
    }

    &echo_messages([["INFO", $text ]]);
        
    return;
}

sub get_read_routine
{
    # Niels Larsen, August 2012. 

    # Returns the name of the read routine that can read a given format.
    # The top of the given file will be looked at and the right routine
    # chosen. If a messages list is given then errors will be returned,
    # otherwise fatal.

    my ( $file,        # Input file name
         $format,      # File format - OPTIONAL
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns string.

    my ( $routine );

    if ( not $format ) {
        $format = &Seq::IO::detect_format( $file );
    }

    $routine = "Seq::IO::read_seqs_$format";

    if ( not Registry::Check->routine_exists({ "routine" => $routine, "fatal" => 0 }) )
    {
        if ( $msgs ) {
            push @{ $msgs }, ["ERROR", qq (Routine does not exist -> "$routine") ];
        } else {
            &error( qq (Routine does not exist -> "$routine") );
        }
    }

    return $routine;
}

sub get_write_routine
{
    # Niels Larsen, October 2012. 

    # Simply returns the write routine name given a format.

    my ( $format,
         $msgs,
        ) = @_;

    my ( $routine );

    $format =~ s/_wrapped$//;

    $routine = "Seq::IO::write_seqs_$format";

    if ( not Registry::Check->routine_exists({ "routine" => $routine, "fatal" => 0 }) )
    {
        if ( $msgs ) {
            push @{ $msgs }, ["ERROR", qq (Routine does not exist -> "$routine") ];
        } else {
            &error( qq (Routine does not exist -> "$routine") );
        }
    }

    return $routine;
}

sub get_seq
{
    my ( $loc,         # Single locator
         $from,        # Where to get from
         $conf,        # Switches and settings - OPTIONAL
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    my ( %conf );

    if ( $conf ) {
        %conf = %{ $conf };
    } else {
        %conf = ();
    }

    return &Seq::IO::get_seqs(
        {
            "locs" => [ $loc ],
            "from" => $from,
            %conf,
        }, $msgs )->[0];
}

sub get_seqs
{
    # Niels Larsen, February 2010.

    # Fetches sequences from named files, installed datasets or remote servers
    # and writes them to a given file or STDOUT. This function does not accept 
    # file handles and thus is not well suited for feeding other routines (but
    # get_seqs_* in this module are). IDs can be either plain or sub-sequence 
    # locators, parsed or not,
    # 
    # CP001140.1
    # CP001140.1:100,20,-;500,100
    # 
    # The sub-sequence locations are given by start, length direction ('+' or 
    # '-', '+' assumed if not given). Output are sequences in fasta format 
    # (more formats later) written to STDOUT or file. If a defined message list 
    # is given, then all errors etc are returned, otherwise they are printed 
    # and the routine exits. 

    my ( $args,        # Arguments hash
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $defs, $input, $clobber, $seqs, @locs, $conf, $ifh, $line, $routine, 
         $ofh, $seq, $file, @msgs, $output, $count, $seqdb, @all_locs, $regexp );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "argv" => [],
        "locs" => undef,
        "idex" => undef,
        "from" => undef,
        "to" => undef,
	"anno" => 0,
        "type" => undef,
        "format" => "fasta",
        "clobber" => 0,
        "append" => 0,
        "verbose" => 0,
        "silent" => 0,
    };

    $conf = &Registry::Args::create( $args, $defs );

    $input = $conf->from || "";
    $output = $conf->to;
    $clobber = $conf->clobber;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> GET LOCATORS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Get locators from file and/or STDIN, 

    @locs = &Seq::IO::read_locators( $conf->locs );

    # From command line,

    if ( @{ $conf->argv } ) {
        push @locs, @{ $conf->argv };
    }

    # From file if --idex is given,

    if ( $regexp = $conf->idex )
    {
        @all_locs = &Seq::IO::read_ids_fasta( $input );
        push @locs, grep /$regexp/, @all_locs;
    }

    if ( not @locs ) {
        &echo_messages( [["ERROR", qq (No locators given from STDIN, command line or file) ]] );
        exit;
    }
    
    # Parse and exit with messages if trouble,

    @locs = &Seq::Common::parse_locators( \@locs );

    # >>>>>>>>>>>>>>>>>>>>>>>> DISPATCH BY SOURCE TYPE <<<<<<<<<<<<<<<<<<<<<<<

    if ( $input =~ /^ncbi/i )
    {
	# >>>>>>>>>>>>>>>>>>>>>>>>>>> FROM NCBI <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        &echo_messages( [["INFO", qq (Not working yet, sorry) ]] );
        exit;
    }
    elsif ( $input =~ /^ebi/i )
    {
	# >>>>>>>>>>>>>>>>>>>>>>>>>>>> FROM EBI <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $input =~ /^ebi:(\w+)$/i ) {
            $seqdb = $1;
        } else {
            &echo_messages( [["ERROR", qq (Databases must be given as "ebi:database")],
                             ["HELP", qq ('ebi_fetch getSupportedDBs' shows database names) ]] );
            exit;
        }
        
	$count = &Seq::IO::get_seqs_ebi( \@locs, $seqdb, $output,
                                         {
                                             "write_format" => "fasta",
                                             "datatype" => $conf->type,
                                             "clobber" => $conf->clobber,
                                             "append" => $conf->append,
                                             "verbose" => $conf->verbose,
                                             "silent" => $conf->silent,
                                         },
                                         \@msgs );
    }
    elsif ( -r $input )
    {
	# >>>>>>>>>>>>>>>>>>>>>>>>>>>> FROM FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

	if ( not &Seq::Storage::is_indexed( $input ) ) {
            &echo_messages( [["ERROR", qq (Sequence file not indexed -> "$input")],
                             ["HELP", qq (Index it with "seq_index $input") ]] );
            exit;
	}

        $count = &Seq::IO::get_seqs_file( \@locs, $input, $output,
                                          {
                                              "return_seqs" => 0,
                                              "write_seqs" => 1,
                                              "write_format" => $conf->format,
                                              "datatype" => $conf->type,
                                              "clobber" => $conf->clobber,
                                              "append" => $conf->append,
                                              "verbose" => $conf->verbose,
                                              "silent" => $conf->silent,
                                          },
                                          \@msgs );
    }
    else
    {
#         state $dbhs = &Seq::IO::open_db_access;
#         &dump( $dbhs );

#         if ( exists $dbhs->{ $input } )
#         {
#             # >>>>>>>>>>>>>>>>>>>>>>> FROM LOCAL DATABANK <<<<<<<<<<<<<<<<<<<<<<<<

#             $seqs = &Seq::IO::get_seqs_db( \@locs, $dbhs->{ $input }, $conf->anno, $conf->type );
#         }
#         else {
#             &error( qq (Neither remote location, local databank or file -> "$input") );
#         }

        &echo_messages( [["ERROR", qq (Wrong looking input -> "$input")],
                         ["HELP", qq (Input must be either a database or an existing file) ]] );
        exit;
    }

    return $count;
}

sub get_seqs_file
{
    # Niels Larsen, February 2010.

    # Fetches sequences or sub-sequences from an indexed local file and 
    # either returns them or write them to file (or STDOUT). This routine 
    # is suited for looping, as inputs and output can be file names 
    # or open handles. If the write_seqs switch is set, the routine writes
    # output and returns the number of sequences written. If the return_seqs
    # switch is set, the routine returns a list of Seq::Common objects,
    # depending on the write_seqs and return_seqs switches. 

    my ( $args,          # Arguments hash
         $msgs,          # Outgoing message list - OPTIONAL
	) = @_;

    # Returns a list or a number.

    my ( $defs, $seq_h, $ndx_h, $seq_beg, $seq_len, $seq_end, $seq_loc, $seq_id,
         $seq_fh, $buf, $loc, @seqs, $seq_str, $strand, $beg, $len, $seq, $seq_type,
         $close_seq, $info_beg, $info_len, $info_str, $close_out, $conf, $write_format,
         $write_seqs, $return_seqs, $count, $routine, $hash, $qual_beg, $qual_len,
         $qual_str, $loc_list, $out_file, $seq_file );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "locs" => undef,
	"seqfile" => undef,
        "seqfmt" => "fasta",
        "locfile" => undef,
        "outfile" => undef,
        "clobber" => 0,
        "append" => 0,
	"silent" => 0,
	"verbose" => 0,
    };
    
    $conf = &Registry::Args::create( $args, $defs );

    if ( not $loc_list or not @{ $loc_list } ) {
        &echo_messages( [["ERROR", qq (No locators given from STDIN, command line or file) ]] );
        exit;
    }

    $return_seqs = $conf->return_seqs;
    $write_seqs = $conf->write_seqs;
    $write_format = $conf->write_format;
    $seq_type = $conf->datatype;

    # >>>>>>>>>>>>>>>>>>>>>>>>> OPEN FILES IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Open input sequence and its index, unless it is already a handle,
    
    if ( $seq_file )
    {
        if ( not ref $seq_file )
        {
            $seq_file = &Seq::Storage::get_handles( $seq_file );
            $close_seq = 1;
        }
    }
    else {
        &error( qq (No input sequence file given) );
    }

    # Open output file if output requested and it is not already a handle,

    if ( $write_seqs and not ref $out_file )
    {
        if ( $conf->append ) {
            $out_file = &Common::File::get_append_handle( $out_file );
        } else {
            &Common::File::delete_file_if_exists( $out_file ) if $conf->clobber;
            $out_file = &Common::File::get_write_handle( $out_file, "clobber" => $conf->clobber );
        }
        
        $close_out = 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> GET SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $seq_h = $seq_file->seq_handle;
    $ndx_h = $seq_file->ndx_handle;

    $count = 0;

    foreach $seq_loc ( @{ $loc_list } )
    {
        # Locator is either an id string or an element of the form 
        # [ id, [[pos,len,strand],[pos,len,strand],...]],
        
	if ( ref $seq_loc ) {
	    $seq_id = $seq_loc->[0];
        } else {
	    $seq_id = $seq_loc;
        }

        # Get sequence start and length, and optional annotation string start and length, 

        ( $seq_beg, $seq_len, 
          $info_beg, $info_len,
          $qual_beg, $qual_len ) = split "\t", &Common::DBM::get( $ndx_h, $seq_id );

        # ID,

        $hash = {
            "id" => $seq_id,
            "strand" => "+",
            "type" => $seq_type,
        };
	  
        # Sequences,

        if ( ref $seq_loc and defined $seq_loc->[1] )
        {
            # Sub-sequences,

	    $seq_str = "";
	    $seq_end = $seq_beg + $seq_len - 1;

	    foreach $loc ( @{ $seq_loc->[1] } )
	    {
		( $beg, $len, $strand ) = @{ $loc };

		if ( $beg + $len > $seq_len ) {
		    &error( qq ($seq_loc->[0] off the end: $beg + $len > $seq_len) );
		}

		seek( $seq_h, $seq_beg + $beg, SEEK_SET );
		read( $seq_h, $buf, $len );

                # Complement if minus strand, 
                
                if ( $strand eq "-" ) {
                    $seq_str .= ${ &Seq::Common::complement_str( \$buf ) };
                } else {
                    $seq_str .= $buf;
                }
	    }

            $hash->{"seq"} = $seq_str;

            # Sub-qualities,

            if ( $qual_len )
            {
                $qual_str = "";

                foreach $loc ( @{ $seq_loc->[1] } )
                {
                    ( $beg, $len, $strand ) = @{ $loc };
                    
                    if ( $beg + $len > $qual_len ) {
                        &error( qq ($seq_loc->[0] off the end: $beg + $len > $qual_len) );
                    }
                    
                    seek( $seq_h, $qual_beg + $beg, SEEK_SET );
                    read( $seq_h, $buf, $len );
                    
                    # Complement if minus strand, 
                    
                    if ( $strand eq "-" ) {
                        $qual_str .= ${ &Seq::Common::complement_str( \$buf ) };
                    } else {
                        $qual_str .= $buf;
                    }
                }

                $hash->{"qual"} = $qual_str;
            }
	}
	else
	{
	    # Whole sequences,

	    seek( $seq_h, $seq_beg, SEEK_SET );
	    read( $seq_h, $hash->{"seq"}, $seq_len );

            # Quality string,
            
            if ( $qual_len )
            {
                seek( $seq_h, $qual_beg, SEEK_SET );
                read( $seq_h, $hash->{"qual"}, $qual_len );
            }
	}

        # Information fields,

        if ( $info_beg )
        {
            seek( $seq_h, $info_beg, SEEK_SET );
            read( $seq_h, $hash->{"info"}, $info_len );
        }

        # Create object, without checking arguments,

	$seq = Seq::Common->new( $hash );

        # Write if asked for,

        if ( $write_seqs )
        {
            $routine = "Seq::IO::write_seq_". $write_format;
            $routine =~ s/1$//;

            no strict "refs";

            $routine->( $out_file, $seq );
        };

        # Put in list if asked for,

        if ( $return_seqs ) {
            push @seqs, $seq;
        }

        $count += 1;
    }

    # >>>>>>>>>>>>>>>>>>>>>>> CLOSE HANDLES IF OPENED ABOVE <<<<<<<<<<<<<<<<<<<

    if ( $close_seq ) {
        &Seq::IO::close_handle( $seq_file );
    }

    if ( $close_out ) {
        $out_file->close;
    }

    # Return if asked for,

    if ( $return_seqs ) {
        return wantarray ? @seqs : \@seqs;
    }

    return $count;
}

sub merge_seq_files
{
    # Niels Larsen, August 2012.

    # Writes a all sequences from the given files into a single file with 
    # a title prepended to the IDs, so they can be separated afterwards. 
    # It is easier this way than to run simrank on many files.

    my ( $args,  # Arguments hash
        ) = @_;

    # Returns hash or nothing.

    my ( $reader, $writer, $file, $ifiles, $ititles, $name, $ifh, 
         $i, $ofh, $seqs, $tots, $readbuf, $sum, @counts );

    $reader = "Seq::IO::read_seqs_". $args->{"iformat"};
    $writer = "Seq::IO::write_seqs_". $args->{"iformat"};
    
    $ifiles = [ @{ $args->{"ifiles"} } ];
    $ititles = $args->{"ititles"};
    $readbuf = $args->{"readbuf"} // 1_000;

    $ofh = &Common::File::get_append_handle( $args->{"ofile"} );

    no strict "refs";

    @counts = ();
    
    for ( $i = 0; $i < @{ $ifiles }; $i++ )
    {
        if ( defined ( $file = $ifiles->[$i] ) )
        {
            $ifh = &Common::File::get_read_handle( $file );
            $sum = 0;
            
            while ( $seqs = $reader->( $ifh, $readbuf ) )
            {
                if ( $ititles )
                {
                    $name = $ititles->[$i];
                    $seqs = [ map { $_->{"id"} = $name ."__SPLIT__". $_->{'id'}; $_ } @{ $seqs } ];
                }

                $writer->( $ofh, $seqs );
                $sum += scalar @{ $seqs };
            }
                    
            &Common::File::close_handle( $ifh );

            push @counts, [ $file, $sum ];
        }
    }

    &Common::File::close_handle( $ofh );

    return wantarray ? @counts : \@counts;
}

sub open_db_access
{
    # Niels Larsen, February 2010.

    # Makes data handles for all installed sequence datasets. A hash is created
    # with dataset names as keys and hashes as values, 

    my ( $names,     # Dataset names, OPTIONAL - default all installed
        ) = @_;

    # Returns a hash.

    my ( @dbs, $dbm_file, $db, $dat_file, $fh );

    if ( not defined $names ) {
        $names = Registry::Register->registered_datasets();
    }

    @dbs = Registry::Get->seq_data( $names )->options;

    foreach $db ( @dbs )
    {
        if ( -r ( $dbm_file = $db->datapath_full ."/Installs/SEQS.kch" ) and
             -r ( $dat_file = $db->datapath_full ."/Installs/SEQS.fasta" ) )
        {
            $DB_access->{ $db->name }->{"seqs_ndx_handle"} = &Common::DBM::write_open( $dbm_file );

            $fh = new IO::Handle;
            sysopen $fh, $dat_file, 0;

            $DB_access->{ $db->name }->{"seqs_file_handle"} = $fh;
        }

        if ( -r ( $dbm_file = $db->datapath_full ."/Installs/HDRS.kch" ) and
             -r ( $dat_file = $db->datapath_full ."/Installs/HDRS.text" ) )
        {
            $DB_access->{ $db->name }->{"hdrs_ndx_handle"} = &Common::DBM::write_open( $dbm_file );
            
            $fh = new IO::Handle;
            sysopen $fh, $dat_file, 0;

            $DB_access->{ $db->name }->{"hdrs_file_handle"} = $fh;
        }

        $DB_access->{ $db->name }->{"datatype"} = $db->datatype;
    }

    return wantarray ? %{ $DB_access } : $DB_access;
}

sub read_locators
{
    # Niels Larsen, August 2010.

    # Reads locators from a list, named file and/or stdin and returns a 
    # combined list. Lines with multiple locators are split, commented 
    # and empty lines are filtered. 

    my ( $list,
         $file,
         $stdin,
         $msgs,
        ) = @_;

    my ( @list, $combeg, @stdin, $fh, @file, $line, $str_ref, @msgs,
         $tmp );

    @list = ();
    $combeg = "#%";

    # From optional list,

    if ( defined $list and @{ $list } )
    {
        @stdin = grep { $_ !~ /^[$combeg]/o } @list;
        push @list, @{ $list }; 
    }
    
    # From optional file,

    if ( defined $file )
    {
        $tmp = &Common::File::read_lines( $file );
        $tmp = [ grep /^[^#%]/, map { chomp $_; $_ } @{ $tmp } ];

        push @list, @{ $tmp };
    }

    # From optional stdin,

    if ( defined $stdin and not -t STDIN and @stdin = &Common::File::read_stdin() )
    {
        @stdin = grep { $_ !~ /^[$combeg]/o } @stdin;
        push @list, @stdin;
    }

    if ( not @list ) {
        push @msgs, ["ERROR", qq (No locators given from STDIN, command line or file) ];
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @list : \@list;
}

sub read_ids
{
    my ( $file,
	 $format,
	 $exclude,
	) = @_;

    my ( $close, $routine, $seq, @ids, $ref, $id, $ifh, $i );

    if ( not ref $file ) {
	$file = &Common::File::get_read_handle( $file );
	$close = 1;
    }

    $routine = "Seq::IO::read_seq_$format";

    no strict "refs";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> IDS TO AVOID <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $exclude )
    {
	# A list,  

	if ( ref $exclude eq "ARRAY" )
	{
	    foreach $id ( @{ $exclude } )
	    {
		while ( $seq = $routine->( $file ) and $seq->id ne $id ) {
		    push @ids, $seq->id;
		};

		if ( not defined $seq ) {
		    &error( qq (Exclude-ID not found -> "$id") );
		}
	    }

	    while ( $seq = $routine->( $file ) ) {
		push @ids, $seq->id;
	    };
	}
	
	# A file,

	elsif ( -r $exclude )
	{
	    $ifh = &Common::File::get_read_handle( $exclude );

	    while ( defined ( $id = <$ifh> ) )
	    {
		chomp $id;

		while ( $seq = $routine->( $file ) and $seq->id ne $id ) {
		    push @ids, $seq->id;
		};

		if ( not defined $seq ) {
		    &error( qq (Exclude-ID not found -> "$id") );
		}
	    }

	    $ifh->close;

	    while ( $seq = $routine->( $file ) ) {
		push @ids, $seq->id;
	    };

	}
	else {
	    $ref = ref $exclude;
	    &error( qq (Unsupported exclude list type -> "$ref") );
	}
    }	
    else
    {
	# Get all ids,

	while ( $seq = $routine->( $file ) ) {
	    push @ids, $seq->id;
	}
    }
	
    if ( $close ) {
	&Common::File::close_handle( $file );
    }
    
    return wantarray ? @ids : \@ids;
}
    
sub read_ids_fasta
{
    # Niels Larsen, February 2010.

    # Reads fasta formatted entries sequentially from a given file and returns
    # a list of ids. See the _read_ids routine for detail. 

    my ( $file,          # Input fasta file or handle
	 $exclude,       # Entries to avoid - OPTIONAL, default none
         ) = @_;

    # Returns a list.

    return &Seq::IO::read_ids( $file, "fasta", $exclude );
}

sub read_pairs_table
{
    # Niels Larsen, February 2013.

    # Reads a two column table of file names into a list of tuples. The file
    # is user edited and so can have mistakes. The routine tolerates Unix, Mac
    # and Windows line ends, removes blanks and cheks inconsistencies. If the
    # second argument is given, then a directory path is added to the file 
    # names. A list of tuples is returned. 

    my ( $file,     # Input file  
         $dir,      # Directory - OPTIONAL
         $msgs,     # Outgoing error messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $text, @pairs, $pair, @msgs, $i );

    # Read content as is, but with "\r\n" and "\r" substituted with "\n",

    $text = ${ &Common::File::read_file( $file ) };

    foreach $pair ( split "\n", $text )
    {
        next if $pair =~ /^\s*#/;
        next if $pair !~ /\w/;

        $pair =~ s/^\s+//;
        $pair =~ s/\s+$//;

        push @pairs, [ split " ", $pair ];

        if ( ( $i = scalar @{ $pairs[-1] } ) != 2 ) {
            push @msgs, ["ERROR", qq (Not 2 file names: $pair) ];
        }
    }

    &append_or_exit( \@msgs, $msgs );

    if ( not defined $dir ) {
        $dir = &File::Basename::dirname( $file );
    }

    @pairs = map {[ "$dir/$_->[0]", "$dir/$_->[1]" ]} @pairs;

    return wantarray ? @pairs : \@pairs;
}

sub read_pairs_expr
{
    # Niels Larsen, March 2013.

    # Uses the given shell expressions to list two sets of files. Errors are 
    # produced if the lists are not equally long and optionally if the first
    # ids do not match between corresponding pair files.

    my ( $expr1,    # Pair 1 shell file expression 
         $expr2,    # Pair 2 shell file expression
         $check,    # Verify the ids match between file pairs - OPTIONAL, default 0
         $msgs,     # Outgoing error messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( @files1, @files2, @pairs, @msgs, $i, $j, $seq1, $seq2, $id1, $id2 );

    $check //= 1;

    @files1 = &Common::File::list_files_shell( $expr1, \@msgs );
    @files2 = &Common::File::list_files_shell( $expr2, \@msgs );

    if ( @msgs )
    {
        push @msgs, ["INFO", qq (Please ensured files are visible from the current directory.) ];
        push @msgs, ["INFO", qq (If run by recipe, their paths is relative to the recipe location.) ];

        &append_or_exit( \@msgs, $msgs );
    }

    if ( ( $i = length @files1 ) != ( $j = length @files2 ) )
    {
        push @msgs, ["ERROR", qq (There are $i files for pair 1, but $j for pair 2) ];
        push @msgs, ["ERROR", qq (Please improve the expression or move irrelevant files) ];

        &append_or_exit( \@msgs, $msgs );
    }

    if ( $check )
    {
        for ( $i = 0; $i <= $#files1; $i += 1 )
        {
            $seq1 = &Seq::IO::read_seqs_first( $files1[$i], 1 )->[0];
            $seq2 = &Seq::IO::read_seqs_first( $files2[$i], 1 )->[0];

            $id1 = $seq1->{"id"};
            $id1 =~ s/ .*//;
            $id1 =~ s/\/1$//;

            $id2 = $seq2->{"id"};
            $id2 =~ s/ .*//;
            $id2 =~ s/\/2$//;

            if ( $id1 ne $id2 ) 
            {
                push @msgs, ["ERROR", qq (First sequence pair has mismatching ids:) ];
                push @msgs, ["ERROR", qq (   File 1: $files1[$i]) ];
                push @msgs, ["ERROR", qq (   File 2: $files2[$i]) ];
                push @msgs, ["ERROR", qq (     ID 1: $id1) ];
                push @msgs, ["ERROR", qq (     ID 2: $id2) ];
                push @msgs, ["ERROR", "" ];                
            }
        }
        
        if ( @msgs ) {
            push @msgs, ["INFO", qq (The cause is likely file lists that match the wrong files as pairs) ];
        }
    }

    &append_or_exit( \@msgs, $msgs );

    @pairs = map {[ $files1[$_], $files2[$_] ]} ( 0 ... $#files1 );

    return wantarray ? @pairs : \@pairs;
}
    
sub read_patterns
{
    # Niels Larsen, January 2012.

    # Reads a pattern file in the Config::General tag format format into a 
    # list of patterns. All fields will be checked if present, but only a 
    # patscan pattern string is required. The second argument is a tag name,
    # that if given must match that in the file. Third argument is a list 
    # of mandatory fields.

    my ( $file,       # File name
         $tag,        # Main tag name - OPTIONAL, default "sequence-pattern"
         $flds,       # Mandatory fields - OPTIONAL, default ["pat_string"]
         $msgs,       # Outgoing error messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $pats, $pat, %pats, @msgs, $val, $fld, %flds, $ndcs, $units, $unit,
         $maxndx, $ndx );

    $tag //= "sequence-pattern";
    $flds //= ["pattern-string"];

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    %pats = new Config::General( $file )->getall;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK MAIN TAG <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $pats = $pats{ $tag } ) {
        $pats = [ $pats ] if ref $pats eq "HASH";
    } else {
        push @msgs, ["ERROR", qq (Main tag not found in file -> "$tag") ];
    }

    &append_or_exit( \@msgs, $msgs );
    return if @msgs;

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK MANDATORY FIELDS <<<<<<<<<<<<<<<<<<<<<<<<

    foreach $pat ( @{ $pats } )
    {
        foreach $fld ( @{ $flds } )
        {
            if ( not defined $pat->{ $fld } ) {
                push @msgs, ["ERROR", qq (Missing mandatory field -> "$fld") ];
            }
        }

        if ( not $pat->{"pattern-string"} ) {
            push @msgs, ["ERROR", qq (No pattern string, specify a pattern-string field) ];
        }
    }

    &append_or_exit( \@msgs, $msgs );
    return if @msgs;

    # >>>>>>>>>>>>>>>>>>>>>>>>> CHECK FOR UNKNOWN KEYS <<<<<<<<<<<<<<<<<<<<<<<<

    %flds = (
        "title" => 1,
        "pattern-orient" => 1,
        "pattern-string" => 1,
        "get-elements" => 1,
        "get-orient" => 1,
        );

    foreach $pat ( @{ $pats } )
    {
        foreach $fld ( keys %{ $pat } )
        {
            if ( not exists $flds{ $fld } )
            {
                push @msgs, ["ERROR", qq (Unrecognized pattern field name -> "$fld") ];
            }
        }
    }

    if ( @msgs ) 
    {
        push @msgs, ["ERROR", qq (Recognized fields are:) ];
        push @msgs, ["ERROR", "" ];

        push @msgs, map { ["ERROR", "  $_" ] } sort keys %flds;
    }

    &append_or_exit( \@msgs );
    return if @msgs;

    # >>>>>>>>>>>>>>>>>>>>>>> CHECK FOR MULTIPLE KEYS <<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $pat ( @{ $pats } )
    {
        foreach $fld ( keys %{ $pat } )
        {
            if ( ref $pat->{ $fld } eq "ARRAY" )
            {
                push @msgs, ["ERROR", qq (Field name has been duplicated -> "$fld") ];
            }
        }
    }

    &append_or_exit( \@msgs );
    return if @msgs;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> CHECK FIELD VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $pat ( @{ $pats } )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>> PATTERN ORIENTATION <<<<<<<<<<<<<<<<<<<<<<<<

        if ( $val = $pat->{"pattern-orient"} )
        {
            if ( $val ne "forward" and $val ne "reverse" ) {
                push @msgs, ["ERROR", qq (Wrong seq_orient value -> "$val", should be "forward" or "reverse") ];
            } 
        }
        else {
            $pat->{"pattern-orient"} = "forward";
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>> GET SUB-PATTERNS <<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $val = $pat->{"get-elements"} )
        {
            if ( $val =~ /^(\d+,?)+$/ )
            {
                $ndcs = [ map { $_ - 1 } split /\s*,\s*/, $val ];
                $units = [ split " ", $pat->{"pattern-string"} ];
                $maxndx = scalar @{ $units };

                foreach $ndx ( @{ $ndcs } )
                {
                    if ( $ndx < 0 )
                    {
                        $ndx += 1;
                        push @msgs, ["ERROR", qq (Sub-pattern index less than 1 -> "$ndx") ];
                    }
                    elsif ( $ndx >= $maxndx )
                    {
                        $ndx += 1;
                        push @msgs, ["ERROR", qq (Sub-pattern index off the end -> "$ndx", should be $maxndx at most) ];
                    }
                }

                $pat->{"get-elements"} = $ndcs;
            }
            else {
                push @msgs, ["ERROR", qq (The get-elements field must be a number, or comma-separated numbers -> "$val") ];
            }
        }
        else {
            $pat->{"get-elements"} = [ 0 ... scalar ( split " ", $pat->{"pattern-string"} ) - 1 ];
        }

        # >>>>>>>>>>>>>>>>>>>>>> SUB-PATTERN ORIENTATION <<<<<<<<<<<<<<<<<<<<<<

        if ( $val = $pat->{"get-orient"} )
        {
            if ( not $pat->{"get-elements"} ) {
                push @msgs, ["ERROR", qq (No get-elements given with "get-orient") ];
            }
            elsif ( $val ne "forward" and $val ne "reverse" ) {
                push @msgs, ["ERROR", qq (Wrong get-orient value -> "$val", should be "forward" or "reverse") ];
            } 
        }
        else {
            $pat->{"get-orient"} = "forward";
        }

        # # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TAGS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # if ( $val = $pat->{"tag_pos"} )
        # {
        #     if ( $val !~ /^(start|end)$/ ) {
        #         push @msgs, ["ERROR", qq (Wrong position -> "$val", should be "start" or "end") ];
        #     }
        # }
        
        # if ( $val = $pat->{"tag_label"} ) 
        # {
        #     if ( $val !~ /^(F|R)-tag$/ ) {
        #         push @msgs, ["ERROR", qq (Wrong tag label -> "$val", should be "F-tag" or "R-tag") ];
        #     }
        # }
        
        # if ( $val = $pat->{"tag_qual"} )
        # {
        #     &Registry::Args::check_number( $val, 90, 100, \@msgs );  
        #     $pat->{"tag_qual"} /= 100;
        # }
    }

    &append_or_exit( \@msgs, $msgs );
    
    return wantarray ? @{ $pats } : $pats;
}

sub read_primer_conf
{
    # Niels Larsen, October 2011.

    # Parses and error-checks a primer file in Config::General format into
    # a list of primers. 

    my ( $file,
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $list, $elem, @msgs );

    $list = &Seq::IO::read_patterns( $file );

    $list = [ $list ] if ref $list eq "HASH";

    foreach $elem ( @{ $list } )
    {
        if ( $elem->{"pattern-orient"} eq "forward" ) {
            $elem->{"orient"} = "F";
        } elsif ( $elem->{"pattern-orient"} eq "reverse" ) {
            $elem->{"orient"} = "R";
        } else {
            &error( qq (Wrong looking primer direction -> "$elem->{'pattern-orient'}") );
        }
    }
    
    return wantarray ? @{ $list } : $list;
}

sub read_seq_fasta
{
    # Niels Larsen, December 2011.
    
    # Reads a single fasta entry into a Seq::Common hash. Sequence lines 
    # may not be wrapped or have blanks. The header may be ">nonblankid"
    # have fields in the format ">nonblankid key=value; key=value; ...".
    # Use the slower and more flexible read_seq_fasta_wrapped for any other
    # format. Returns a Seq::Common hash, or nothing if at end-of-file. 

    my ( $fh,           # File handle
        ) = @_;

    # Returns hash or nothing.
    
    my ( $id_line, $seq, $blank_pos );

    if ( defined ( $id_line = <$fh> ) )
    {
        chomp $id_line;

        if ( ( $blank_pos = index $id_line, " " ) > 0 )
        {
            $seq->{"id"} = substr $id_line, 1, $blank_pos - 1;
            $seq->{"info"} = substr $id_line, $blank_pos + 1;
        }
        else {
            $seq->{"id"} = substr $id_line, 1;
        }
        
        chomp ( $seq->{"seq"} = <$fh> );

        return $seq;
    }

    return;
}

sub read_seq_fasta_wrapped
{
    my ( $fh,
        ) = @_;

    my ( $seq );

    $seq = &Seq::IO::read_seqs_fasta_wrapped( $fh, 1 );

    return $seq->[0];
}

sub read_seq_fasta_wrapped_old2
{
    # Niels Larsen, December 2009.
    
    # Reads one fasta entry and returns a Seq::Common hash. Sequence lines may
    # be wrapped, empty or have embedded spaces. The header can be parsed with
    # an optional expression and fields. Without expression and fields given, 
    # the first non-blank word of the header is made the ID. Use this routine 
    # only for importing, and read_seq_fasta for normal reads. 

    my ( $fh,           # File handle
         $regex,        # Header ID regex - OPTONAL, default none
         $fields,       # Field names, hash or list - OPTIONAL, default none
         ) = @_;

    # Returns an object.

    my ( $seq, $line, @lines, $info, $header );

    $line = <$fh>;

    if ( $line =~ /^>(.+)\n$/o ) {
        $header = $1;
    } else {
        chomp $line;
        &error( qq (Wrong looking header line -> "$line") );
    }

    # Parse header,
    
    if ( $regex and $fields and
         $info = &Seq::Info::parse_header( $header, $regex, $fields ) )
    {
        $seq->{"id"} = $info->seq_id;
        delete $info->{"seq_id"};
        
        $seq->{"info"} = $info;
    }
    elsif ( $header =~ /^(\S+)\s+(.+)/ )
    {
        $seq->{"id"} = $1;
        $seq->{"info"} = $2;
    }
    elsif ( $header =~ /^(\S+)/ ) 
    {
        $seq->{"id"} = $1;
    }
    else {
        chomp $header;
        &error( qq (Regex "$regex" did not match "$header") );
    }

    # Read sequence lines until next '>' is read,
    
    $seq->{"seq"} = "";

    while ( defined ( $line = <$fh> ) and $line !~ /^>/ )
    {
        $line =~ s/\s+//g;
        $seq->{"seq"} .= $line;
    }
    
    # Set header for next time this routine is called,

    if ( defined $line and $line =~ /^>(.+)\n$/ ) {
        $header = $1;
    } else {
        $header = undef;
    }
    
    return $seq;
}

sub read_seq_fasta_wrapped_old
{
    # Niels Larsen, December 2009.
    
    # Reads one fasta entry and returns a Seq::Common hash. Sequence lines may
    # be wrapped, empty or have embedded spaces. The header can be parsed with
    # an optional expression and fields. Without expression and fields given, 
    # the first non-blank word of the header is made the ID. Use this routine 
    # only for importing, and read_seq_fasta for normal reads. 

    my ( $fh,           # File handle
         $regex,        # Header ID regex - OPTONAL, default none
         $fields,       # Field names, hash or list - OPTIONAL, default none
         ) = @_;

    # Returns an object.

    my ( $seq, $line, @lines, $info, $header );

    $line = <$fh>;

    if ( $line =~ /^>(.+)\n$/o ) {
        $header = $1;
    } else {
        chomp $line;
        &error( qq (Wrong looking header line -> "$line") );
    }

    # Parse header,
    
    if ( $regex and $fields and
         $info = &Seq::Info::parse_header( $header, $regex, $fields ) )
    {
        $seq->{"id"} = $info->seq_id;
        delete $info->{"seq_id"};
        
        $seq->{"info"} = $info;
    }
    elsif ( $header =~ /^(\S+)\s+(.+)/ )
    {
        $seq->{"id"} = $1;
        $seq->{"info"} = $2;
    }
    elsif ( $header =~ /^(\S+)/ ) 
    {
        $seq->{"id"} = $1;
    }
    else {
        chomp $header;
        &error( qq (Regex "$regex" did not match "$header") );
    }

    # Read sequence lines until next '>' is read,
    
    $seq->{"seq"} = "";

    while ( defined ( $line = <$fh> ) and $line !~ /^>/ )
    {
        $line =~ s/\s+//g;
        $seq->{"seq"} .= $line;
    }
    
    # Set header for next time this routine is called,

    if ( defined $line and $line =~ /^>(.+)\n$/ ) {
        $header = $1;
    } else {
        $header = undef;
    }
    
    return $seq;
}

sub read_seq_fastq
{
    # Niels Larsen, December 2011.

    # Reads a single fastq entry from the given file handle and returns
    # a Seq::Common hash. Lines may not be wrapped and no format check 
    # is done. Is there a faster way?

    my ( $fh,             # File handle
        ) = @_;

    # Returns a hash or nothing.

    my ( $id_line, $seq, $qual );
    
    if ( defined ( $id_line = <$fh> ) )
    {
        $seq = {
            "id" => ( substr $id_line, 1 ),
            "seq" => ( $seq = <$fh> ),
            "info" => ( substr <$fh>, 1 ),
            "qual" => ( $qual = <$fh> ),
        };

        chomp %{ $seq };

        return $seq;
    }

    return;
}

sub read_seqs_fasta
{
    # Niels Larsen, December 2011.
    
    # Returns a list of fasta entries as Seq::Common hashes. Sequence lines 
    # may not be wrapped or have blanks. Header may be just ">nonblankid" or
    # have fields in the format ">nonblankid key=value; key=value; ...".
    # Use the slower and more flexible read_seqs_fasta_wrapped for any other
    # format. Returns a list, or nothing if at end-of-file. 

    my ( $fh,           # File handle
         $num,          # Number of sequences to read - OPTIONAL, default 100
        ) = @_;

    # Returns a list or nothing.
    
    my ( $i, $id_line, @seqs, $seq, $blank_pos );

    $i = 0;
    $num //= 100;

    while ( $i < $num and defined ( $id_line = <$fh> ) )
    {
        if ( ( $blank_pos = index $id_line, " " ) > 0 )
        {
            push @seqs, 
            {
                "id" => ( substr $id_line, 1, $blank_pos - 1 ),
                "info" => ( substr $id_line, $blank_pos + 1 ),
                "seq" => ( $seq = <$fh> ),
            };
        }
        else
        {
            push @seqs, 
            {
                "id" => ( substr $id_line, 1 ),
                "seq" => ( $seq = <$fh> ),
            };
        }
        
        chomp %{ $seqs[-1] };
        
        $i += 1;
    }

    if ( @seqs ) {
        return wantarray ? @seqs : \@seqs;
    }

    return;
}

sub read_seqs_fasta_fixpos
{
    # Niels Larsen, January 2012. 

    my ( $fh,
         $conf,
        ) = @_;
    
    my ( $read, $id, $line, $len, $ndx, $seqnum, $readbuf, $regex );
    
    $readbuf = $conf->{"readbuf"} // 1000;
    $regex = $conf->{"regex"} // '>(\S+)';
    $seqnum = $conf->{"seqnum"} // 0;

    $read = 0;

    while ( $read < $readbuf and defined ( $line = <$fh> ) )
    {
        if ( $line =~ /^$regex/ ) {
            $id = $1;
        } else {
            &error( qq (Wrong looking FASTQ header expression -> "$regex") );
        }
        
        $line = <$fh>;

        $ndx->{ $id } = ++$seqnum;

        $read += 1;
    }
    
    $conf->{"seqnum"} = $seqnum;

    return $ndx;
}

sub read_seqs_fasta_varpos
{
    # Niels Larsen, January 2012. 

    my ( $fh,
         $conf,
        ) = @_;
    
    my ( $read, $id, $line, $len, $ndx, $readbuf, $regex, $filepos );
    
    $readbuf = $conf->{"readbuf"} // 1000;
    $regex = $conf->{"regex"} // '>(\S+)';
    $filepos = $conf->{"filepos"} // 0;

    $read = 0;
    
    while ( $read < $readbuf and defined ( $line = <$fh> ) )
    {
        $len = length $line;

        if ( $line =~ /^$regex/ ) {
            $id = $1;
        } else {
            &error( qq (Wrong looking FASTA header expression -> "$regex") );
        }
        
        $len += length <$fh>;

        $ndx->{ $id } = "$filepos\t$len";

        $filepos += $len;

        $read += 1;
    }
    
    $conf->{"filepos"} = $filepos;

    return $ndx;
}

sub read_seqs_fasta_wrapped
{
    # Niels Larsen, April 2012.

    # Reads a given number of fasta entries with wrapped lines. 
    # Returns a list of hashes.

    my ( $fh,         # File handle
         $max,        # Max number of entries
        ) = @_;

    # Returns a list.

    my ( $num, $hdr, $seq, @seqs, $line, $seqstr );

    $max //= 100;

    $line = "";
    $num = 0;

    $hdr = <$fh> // return;

    while ( $num < $max and defined $line )
    {
        $seqstr = "";

        while ( defined ( $line = <$fh> ) and $line !~ /^>/ )
        {
            $seqstr .= $line;
        }

        if ( $hdr =~ /^>(\S+) *([^\n]+)?/ ) {
            $seq = { "id" => $1, "info" => $2 };
        } else {
            &error( qq (Wrong looking header line -> "$hdr") );
        }

        $seqstr =~ tr/ \t\r\n//d;

        $seq->{"seq"} = $seqstr;
        
        $hdr = $line;

        push @seqs, $seq;

        $num += 1;
    }

    &IO::Unread::unread( $fh, $line ) if defined $line;

    if ( @seqs ) {
        return wantarray ? @seqs : \@seqs;
    }

    return;
}

sub read_seqs_fastq
{
    # Niels Larsen, December 2011.

    # Reads a number of fastq entries from a given file handle and returns
    # a list of Seq::Common hashes. Lines may not be wrapped and no format 
    # check is done. After many tries, this looks like the quickest perl 
    # way to read fastq sequences. Is there a faster way?

    my ( $fh,       # File handle
         $num,      # Number of sequences - OPTIONAL, default 100
        ) = @_;

    # Returns a list or nothing.

    my ( $i, $id_line, @seqs, $seq, $qual );

    if ( not defined $num ) {
        &error( qq (No read-ahead count given) );
    }

    $i = 0;
    $num //= 100;

    while ( $i < $num and defined ( $id_line = <$fh> ) )
    {
        push @seqs,
        {
            "id" => ( substr $id_line, 1 ),
            "seq" => ( $seq = <$fh> ),
            "info" => ( substr <$fh>, 1 ),
            "qual" => ( $qual = <$fh> ),
        };
        
        chomp %{ $seqs[-1] };
        
        $i += 1;
    }
    
    if ( @seqs ) {
        return wantarray ? @seqs : \@seqs;
    }
    
    return;
}

sub read_seqs_fastq_check
{
    # Niels Larsen, March 2013.

    # Like &Seq::IO::read_seqs_fastq, but tolerates corrupted entries and 
    # recovers after those. If an entry is ok, then "seq_error=0" is set in
    # the info field, if bad "seq_error=1" is set. This routine is slower 
    # and should be used only for finding format problems. 

    my ( $fh,       # File handle
         $num,      # Number of sequences - OPTIONAL, default 100
        ) = @_;

    # Returns a list or nothing.

    my ( $i, $hdr, @seqs, $seq, $info, $qual, $err );

    if ( not defined $num ) {
        &error( qq (No read-ahead count given) );
    }

    $i = 0;
    $num //= 100;

    while ( $i < $num and defined ( $hdr = <$fh> ) )
    {
        if ( $hdr =~ /^\@/ )
        {
            $err = 0;

            $seq = <$fh>;
            $info = <$fh>;
            $qual = <$fh>;

            $err = 1 if not &Seq::Common::is_dna({ "seq" => $seq });
            $err = 1 if $info !~ /^\+/;
            $err = 1 if length $seq != length $qual;

            $info .= "seq_error=$err ";

            push @seqs, 
            {
                "id" => ( substr $hdr, 1 ),
                "seq" => $seq,
                "info" => $info,
                "qual" => $qual,
            };

            chomp %{ $seqs[-1] };
            
            $i += 1;
        }
    }
    
    if ( @seqs ) {
        return wantarray ? @seqs : \@seqs;
    }
    
    return;
}

sub read_seqs_fastq_fixpos
{
    # Niels Larsen, January 2012. 

    my ( $fh,
         $conf,
        ) = @_;
    
    my ( $read, $id, $line, $len, $ndx, $seqnum, $readbuf, $regex );
    
    $readbuf = $conf->{"readbuf"} // 1000;
    $regex = $conf->{"regex"} // '@(\S+)';
    $seqnum = $conf->{"seqnum"} // 0;

    $read = 0;

    while ( $read < $readbuf and defined ( $line = <$fh> ) )
    {
        if ( $line =~ /^$regex/ ) {
            $id = $1;
        } else {
            &error( qq (Wrong looking FASTQ header expression -> "$regex") );
        }
        
        $line = <$fh>;
        $line = <$fh>;
        $line = <$fh>;

        $ndx->{ $id } = ++$seqnum;

        $read += 1;
    }
    
    $conf->{"seqnum"} = $seqnum;

    return $ndx;
}

sub read_seqs_fastq_varpos
{
    # Niels Larsen, January 2012. 

    my ( $fh,
         $conf,
        ) = @_;
    
    my ( $read, $id, $line, $len, $ndx, $readbuf, $regex, $filepos );
    
    $readbuf = $conf->{"readbuf"} // 1000;
    $regex = $conf->{"regex"} // '@(\S+)';
    $filepos = $conf->{"filepos"} // 0;

    $read = 0;

    while ( $read < $readbuf and defined ( $line = <$fh> ) )
    {
        $len = length $line;

        if ( $line =~ /^$regex/ ) {
            $id = $1;
        } else {
            &error( qq (Wrong looking FASTQ header expression -> "$regex") );
        }
        
        $len += length <$fh>;
        $len += length <$fh>;
        $len += length <$fh>;

        $ndx->{ $id } = "$filepos\t$len";

        $filepos += $len;

        $read += 1;
    }
    
    $conf->{"filepos"} = $filepos;

    return $ndx;
}

sub read_seqs_file
{
    # Niels Larsen, December 2011.

    # Reads and returns all entries from a given file. The format of the
    # file is auto-detected. 

    my ( $file,       # File name
        ) = @_;
    
    # Returns list.

    my ( $fh, $seqs, $routine );

    $routine = &Seq::IO::get_read_routine( $file );

    $fh = &Common::File::get_read_handle( $file );
    
    no strict "refs";

    $seqs = $routine->( $fh, -s $file );

    &Common::File::close_handle( $fh );

    return wantarray ? @{ $seqs } : $seqs;
}

sub read_seqs_filter
{
    # Niels Larsen, March 2012. 

    # Reads sequences in supported formats into a list that is returned.
    # Removes gaps, complements and filters by length if "degap", "reverse"
    # and "minlen" keys are set in the arguments hash. A "format" value 
    # must also be given. Returns a list of sequences. 

    my ( $file,   # File or file handle
         $args,
        ) = @_;

    # Returns a list.

    my ( $fh, $reader, $seqs, $format );

    if ( ref $file ) {
        $fh = $file;
    } else {
        $fh = &Common::File::get_read_handle( $file );
    }

    $reader = "Seq::IO::read_seqs_". $args->{"format"};

    {
        no strict "refs";
        $seqs = &{ $reader }( $fh, $args->{"readbuf"} );
    }

    &Common::File::close_handle( $fh ) unless ref $file;

    return if not $seqs or not @{ $seqs };

    # Degap, length and/or text filter,

    if ( $args->{"degap"} ) {
        $seqs = &Seq::List::delete_gaps( $seqs );
    }
    
    if ( $args->{"minlen"} ) {
        $seqs = &Seq::List::filter_length_min( $seqs, $args->{"minlen"} );
    }
    
    if ( $args->{"maxlen"} ) {
        $seqs = &Seq::List::filter_length_max( $seqs, $args->{"maxlen"} );
    }
    
    if ( $args->{"filter"} ) {
        $seqs = &Seq::List::filter_info_regexp( $seqs, $args->{"filter"} );
    }

    if ( @{ $seqs } )
    {
        return $seqs;
    }

    return;
}

sub read_seqs_first
{
    # Niels Larsen, December 2011.

    # Reads the first entry or entries of a given sequence file. The 
    # format is auto-detected. Returns a Seq::Common hash.

    my ( $file,
         $num,     # Number of entries to read, OPTIONAL - default 1
        ) = @_;

    # Returns a hash.

    my ( $fh, $format, $routine, $seq );

    $num //= 1;

    $format = &Seq::IO::detect_format( $file );
    $routine = "Seq::IO::read_seqs_$format";
    
    $fh = &Common::File::get_read_handle( $file );
    
    no strict "refs";

    $seq = $routine->( $fh, $num );

    &Common::File::close_handle( $fh );

    return $seq;
}

sub read_seqs_genbank
{
    # Niels Larsen, June 2012.

    # Reads a number of genbank entries from a given file handle and returns
    # a list of Seq::Common hashes. This is a very limited Genbank reader 
    # that only gets id, sequence and taxonomy string.

    my ( $fh,       # File handle
         $num,      # Number of sequences - OPTIONAL, default 100
        ) = @_;

    # Returns list of hashes or nothing.

    my ( $i, $id, $line, @seqs, $seq, $subseq, $key, $val, $taxon );
    
    $i = 0;
    $num //= 100;

    while ( $i < $num and defined ( $line = <$fh> ) )
    {
        chomp $line;
        $key = substr $line, 0, 12;

        if ( $key eq "LOCUS       " )
        {
            $val = substr $line, 12;
            $seq->{"id"} = substr $val, 0, ( index $val, " " );
        }
        elsif ( $key eq "DEFINITION  " )
        {
            $val = substr $line, 12;
            $seq->{"info"}->{"definition"} = $val;
        }
        elsif ( $key eq "  ORGANISM  " )
        {
            # This field can be different: it starts with oranism name, then 
            # taxon. But organism can be long and wrapped, and no rule for 
            # when name stops and taxon starts. 

            $line =~ s/\s*$//;

            if ( $line eq '  ORGANISM' ) {
                $val = "Unclassified";
            } else {
                $val = substr $line, 12;
            }

            while ( defined ( $line = <$fh> ) and $line !~ /;/ )
            {
                $line =~ s/\s*$//;
                $val .= " ". substr $line, 12;
            }

            $seq->{"info"}->{"org_name"} = $val;

            $taxon = "";
            
            while ( $line =~ /^ {12,12}([^\n]+)/ )
            {
                $taxon .= $1;
                $line = <$fh>; 
            }

            $seq->{"info"}->{"org_taxon"} = $taxon if $taxon;
        }
        elsif ( $key eq "COMMENT     " )
        {
            $val = substr $line, 12;

            if ( $val =~ /Genbank: (\S+)/ )
            {
                $seq->{"info"}->{"gb_acc"} = $1;
            }
        }
        elsif ( $line =~ /\/db_xref="taxon:(\d+)"/ )
        {
            $seq->{"info"}->{"ncbi_taxid"} = $1;
        }
        elsif ( $key eq "ORIGIN" )
        {
            $seq->{"seq"} = "";
            
            while ( defined ( $line = <$fh> ) and $line !~ m|^//| )
            {
                ( $subseq = substr $line, 10 ) =~ s/\s//g;
                $seq->{"seq"} .= $subseq;
            }
            
            push @seqs, $seq;
            $seq = {};
            
            $i += 1;
        }
    }
    
    if ( @seqs ) {
        return wantarray ? @seqs : \@seqs;
    }
    
    return;
}

sub read_seqs_genbank_varpos
{
    # Niels Larsen, July 2012. 

    my ( $fh,
         $conf,
        ) = @_;
    
    my ( $read, $id, $line, $len, $ndx, $readbuf, $regex, $filepos );

    $readbuf = $conf->{"readbuf"} // 1000;
    $regex = 'LOCUS       (\S+)';
    $filepos = $conf->{"filepos"} // 0;

    $read = 0;
    
    while ( $read < $readbuf and defined ( $line = <$fh> ) )
    {
        $len = length $line;

        if ( $line =~ /^$regex/ ) {
            $id = $1;
        } else {
            &error( qq (Wrong looking Genbank locus expression -> "$regex") );
        }
        
        while ( $line !~ m|^//| and defined ( $line = <$fh> ) )
        {
            $len += length $line;
        }

        $ndx->{ $id } = "$filepos\t$len";

        $filepos += $len;

        $read += 1;
    }
    
    $conf->{"filepos"} = $filepos;

    return $ndx;
}

sub read_table
{
    # Niels Larsen, October 2011. 

    # Reads a tab-separated table with a column-title line and columns to 
    # match. There can be no blanks in the title or table elements. Users 
    # create this file, so basic checks are done: rows must all have the 
    # same number of elements; this number must correspond to the number 
    # of title elements; if labels are given as the second argument, then
    # the observed must match these; no element may contain blanks. Output 
    # is a list of row hashes, where title elements are keys and the row
    # elements values. 

    my ( $file,        # Input file
         $args,        # Arguments - OPTIONAL
         $msgs,        # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( %hdrs, $row, $hdr, @hdrs, @vals, $hash, $val, @list, @msgs, 
         $choices, @rows, %cols, %rows, $count, $i, $colsep, $hdrs );

    $colsep = $args->{"colsep"};
    $hdrs = $args->{"headers"};

    @rows = split "\n", ${ &Common::File::read_file( $file ) };

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Check that header names are as required,

    $row = shift @rows;
    $row =~ s/^#\s*//;
    chomp $row;

    @hdrs = split " ", $row;

    if ( not @hdrs )
    {
        push @msgs, ["ERROR", qq (First table row is empty.) ];
        push @msgs, ["INFO", qq (It should be a header line starting with "#") ];

        &append_or_exit( \@msgs, $msgs );
        return;
    }
        
    if ( $hdrs )
    {
        %hdrs = map { $_, 1 } @{ $hdrs };

        foreach $hdr ( @hdrs )
        {
            if ( not exists $hdrs{ $hdr } ) 
            {
                $choices = join ", ", sort keys %hdrs;
                push @msgs, ["ERROR", qq (Wrong column title -> "$hdr") ];
                push @msgs, ["INFO", qq (It should be one of $choices) ];
            }
        }

        if ( @msgs ) {
            &append_or_exit( \@msgs, $msgs );
            return;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> VALUES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read values into a list of hashes,

    foreach $row ( @rows )
    {
        next if $row =~ /^#/;
        chomp $row;

        $row =~ s/^\s+//;
        $row =~ s/\s+$//;

        @vals = ();

        foreach $val ( split /\s*$colsep\s*/, $row )
        {
            push @vals, $val;
        }

        map { $_ =~ s/^\s*// } @vals;
        map { $_ =~ s/\s*$// } @vals;

        $cols{ scalar @vals } += 1;
        $rows{ scalar @vals } = $row;

        $hash = {};

        foreach $hdr ( @hdrs ) {
            $hash->{ $hdr } = shift @vals;
        }
        
        if ( @vals ) {
            $hash->{ $hdrs[-1] } .= " ". join " ", @vals;
        }

        push @list, &Storable::dclone( $hash );
    }

    # Check for different number of value columns,

    $count = keys %cols;

    if ( $count > 1 )
    {
        push @msgs, ["ERROR", qq (In file $file: ) ];
        push @msgs, ["ERROR", qq (Rows with different number of columns found. Examples:) ];

        foreach $val ( values %rows ) {
            push @msgs, ["ERROR", $val ];
        }
    }
    else
    {
        $count = ( keys %cols )[0];

        if ( $count ne ( $i = scalar @hdrs ) ) {
            push @msgs, ["ERROR", qq ($count table columns but $i headers) ];
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @list : \@list;
}

sub read_skip_fastq
{
    # Niels Larsen, June 2012.

    # Reads ahead a number of fastq entries from a given file handle. No
    # sequences are read, it mere winds down the file. Returns the number
    # of entries read through.

    my ( $fh,       # File handle
         $num,      # Number of sequences to skip
        ) = @_;

    # Returns integer.

    my ( $i, $line );
    
    $i = 0;

    while ( $i < $num and defined ( $line = <$fh> ) )
    {
        $line = <$fh>;
        $line = <$fh>;
        $line = <$fh>;

        $i += 1;
    }
    
    return $i;
}

sub read_skip_fasta
{
    # Niels Larsen, June 2012.

    # Reads ahead a number of two-line fasta entries from a given file 
    # handle. No sequences are read, it mere winds down the file. Returns
    # the number of entries read through.

    my ( $fh,       # File handle
         $num,      # Number of sequences to skip
        ) = @_;

    # Returns integer.

    my ( $i, $line );
    
    $i = 0;

    while ( $i < $num and defined ( $line = <$fh> ) )
    {
        $line = <$fh>;
        $i += 1;
    }
    
    return $i;
}

sub read_table_primers
{
    # Niels Larsen, April 2013.

    # Reads a table with patterns, orientation, molecule names and titles. 
    # Returns a list of rows. 

    my ( $file,   # Input file
         $msgs,   # Outgoing messages - OPTIONAL
        ) = @_;
    
    # Returns a list.

    my ( @list, $pri, $key, $val );

    @list = &Seq::IO::read_table(
        $file,
        {
            "headers" => [ qw ( Pat Orient Mol Name ) ],
            "colsep" => "\t",
        },
        $msgs );

    foreach $pri ( @list )
    {
        foreach $key ( keys %{ $pri } )
        {
            if ( $key ne lc $key )
            { 
                $val = $pri->{ $key };
                $pri->{ lc $key } = $val;
                delete $pri->{ $key };
            }
        }

        $pri->{"name"} =~ s/ /_/g;
        $pri->{"name"} =~ s/\//-/g;
    } 

    return wantarray ? @list : \@list;
}

sub read_table_tags
{
    # Niels Larsen, November 2011. 

    # Reads a table with barcodes and titles at the top. Uses the table 
    # reader in this module but puts additional constraints on content:
    # 1) there must be a header line at the top with the barcode titles
    # defined at the top of this module, 2) there must be either F-tag 
    # or R-tag or both, 3) ID's, if given, may only contain alpha-numeric
    # characters plus _-., 4) F-tag and R-tag may only contain sequence,
    # 5) ID's, F-tags and R-tags must be unique within a column. No 
    # filling is missing values is done, that should be done at a higher
    # level. Returns a list of hashes. 

    my ( $file,    # Input file
         $msgs,    # Output messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $list, @msgs, $elem, $key, @vals, $val, %seen, $hasbar );

    # Read table, which checks the headers,
    
    $list = &Seq::IO::read_table(
        $file,
        {
            "colsep" => '\s+',
            "headers" => \@Bar_titles,
        },
        \@msgs );

    if ( @msgs )
    {
        &append_or_exit( \@msgs, $msgs );
        return;
    }

    # Check for bad characters, and presence of at lesat one barcode
    # column,

    $hasbar = 0;

    foreach $key ( @Bar_titles )
    {
        next if not exists $list->[0]->{ $key };

        if ( $key =~ /^[FR]\-tag$/ )
        {
            foreach $elem ( @{ $list } ) 
            {
                if ( ( $val = $elem->{ $key } ) =~ /[^AGCTagct]/ ) {
                    push @msgs, ["ERROR", qq ($key with non-AGCT character -> "$val") ];
                }
            }
            
            $hasbar = 1;
        }
        elsif ( $key eq "ID" )
        {
            foreach $elem ( @{ $list } ) 
            {
                if ( ( $val = $elem->{ $key } ) =~ /[^A-Za-z0-9_\-.]/ ) {
                    push @msgs, ["ERROR", qq (Barcode sequence contains non-word character -> "$val") ];
                }
            }
        }
        else {
            &error( qq (Wrong looking tag-table key -> "$key". Programming error) );
        }
    }

    if ( not $hasbar ) {
        push @msgs, ["ERROR", qq (No barcode sequences given) ];
    }

    # Check all are unique,

    foreach $key ( @Bar_titles )
    {
        next if not exists $list->[0]->{ $key };

        %seen = ();
        
        foreach $elem ( @{ $list } )
        {
            if ( $seen{ $val = $elem->{ $key } } ) {
                push @msgs, ["ERROR", qq (Duplicate $key -> "$val") ];
            } else {
                $seen{ $val } = 1;
            }
        }
    }
    
    if ( @msgs )
    {
        if ( defined $msgs ) {
            push @{ $msgs }, @msgs;
        } else {
            &error([ map { $_->[1] } @msgs ]);
        }
    }

    return wantarray ? @{ $list } : $list;
}

sub search_db
{
    # Niels Larsen, February 2010.

    my ( $args,
        ) = @_;

    my ( $db, $count, $conf, $method, $tmp_file, $db_file );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( run_method ifile dbname ofile ) ],
        "HR:0" => [ qw ( pre_params params post_params ) ],
    });

    $db = Registry::Get->dataset( $args->dbname );

    if ( -r ( $db_file = $db->datapath_full ."/Installs/SEQS.fasta" ) )
    {
        $conf = {
            "ifile" => $args->ifile,
            "dbtype" => $db->datatype,
            "pre_params" => $args->pre_params,
            "params" => $args->params,
            "post_params" => $args->post_params,
        };

        $method = $args->run_method;

        # Release files,

        $tmp_file = Registry::Paths->new_temp_path( $method );

        $conf->{"dbfile"} = $db_file;
        $conf->{"ofile"} = $tmp_file;

        {
            no strict "refs";
            $method->( $conf );
        }

        if ( -e $tmp_file ) 
        {
            &Common::File::append_files( $args->ofile, $tmp_file );
            &Common::File::delete_file_if_exists( $tmp_file );
        }

        # Daily files,

        if ( -r ( $db_file = $db->datapath_full ."/Installs/Daily/SEQS.fasta" ) )
        {
            $tmp_file = Registry::Paths->new_temp_path( $method );

            $conf->{"dbfile"} = $db_file;
            $conf->{"ofile"} = $tmp_file;

            {
                no strict "refs";
                $method->( $conf );
            }

            if ( -e $tmp_file ) 
            {
                &Common::File::append_files( $args->ofile, $tmp_file );
                &Common::File::delete_file_if_exists( $tmp_file );
            }
        }
    }
    else 
    {
        $count = &Seq::IO::search_db_recurse(
            $db->datapath_full,
            {
                "run_method" => $args->run_method,
                "ifile" => $args->ifile,
                "dbtype" => $db->datatype,
                "ofile" => $args->ofile,
            });
    }
                
    return $count;
}
         
sub search_db_recurse
{
    # Niels Larsen, March 2008.

    # Recurses a database file tree and runs a given routine on each fasta 
    # file, with the given arguments. Returns the number of files searched.

    my ( $dbdir,          # Input directory path
         $args,           # Arguments hash
        ) = @_;

    # Returns an integer

    my ( @dirs, $dir, @fastas, $db_file, $tmp_file, $method, $file_count );

    $args = &Registry::Args::check( $args, {
        "S:1" => [ qw ( run_method ifile dbtype ofile ) ],
        "HR:0" => [ qw ( pre_params params post_params ) ],
    });

    $file_count = 0;

    $args->pre_params( {} ) if not defined $args->pre_params;
    $args->params( {} ) if not defined $args->params;
    $args->post_params( {} ) if not defined $args->post_params;

    if ( @dirs = &Common::File::list_directories( $dbdir ) )
    {
        foreach $dir ( map { $_->{"path"} } @dirs )
        {
            $file_count += &Seq::IO::search_db_recurse( $dir, $args );
        }
    }
    elsif ( @fastas = &Common::File::list_files( $dbdir, '\.fa$' ) )
    {
        $method = $args->run_method;

        foreach $db_file ( map { $_->{"path"} } @fastas )
        {
            $tmp_file = Registry::Paths->new_temp_path();

            no strict "refs";

            &{ $method }( 
                {
                    "ifile" => $args->ifile,
                    "dbtype" => $args->dbtype,
                    "dbfile" => $db_file,
                    "ofile" => $tmp_file,
                    "pre_params" => $args->pre_params,
                    "params" => $args->params,
                    "post_params" => $args->post_params,
                });

            if ( -s $tmp_file )
            {
                &Common::File::append_files( $args->ofile, $tmp_file );
            }

            &Common::File::delete_file_if_exists( $tmp_file );
        }

        $file_count += scalar @fastas;
    }

    return $file_count;
}

sub seek_4bit
{
    # Niels Larsen, August 2007.

    # Fetches a sequence, or sub-sequence, from a given file of 
    # concatenated 4-bit sequences. The byt offset (bytmin) and length
    # of the sequence (seqlen) must be given. From and to values 
    # (seqbeg and seqend) are optional.

    my ( $args,             # Arguments hash
         $msgs,             # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a string reference.

    my ( $bytbeg, $bytend, $seqbeg, $seqend, $seqstr, $bitvec, $seqmax, 
         $bytmin, $begch, $endch, $byte, $bytstr );

    $args = &Registry::Args::check( $args, {
        "S:2" => [ qw ( fpath bytmin seqlen ) ],
        "S:0" => [ qw ( seqbeg seqend ) ],
    });
    
    $bytmin = $args->bytmin;
    $seqmax = $args->seqlen - 1;

    if ( defined $args->seqbeg ) {
        $seqbeg = $args->seqbeg;
    } else {
        $seqbeg = 0;
    }

    if ( defined $args->seqend ) {
        $seqend = $args->seqend;
    } else {
        $seqend = $seqmax;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> GET FROM FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First fetch a byte string that is approximately right, but which may
    # include one extra create 4-bit base at each end if the coordinates 
    # dont coincide with byte boundaries,

    $bytbeg = $bytmin + int ( ( $seqmax - $seqend ) / 2 );
    $bytend = $bytmin + int ( ( $seqmax - $seqbeg ) / 2 );

    $bytstr = ${ &Common::File::seek_file( $args->fpath, $bytbeg, $bytend-$bytbeg+1 ) };

    # >>>>>>>>>>>>>>>>>>>>>>>>> ADJUST STRING <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # The fetched string may be too large or it may not. Here we lift off
    # single 4-bit characters from half-occupied bytes, remember those 
    # characters, and trim the string to byte boundaries,

    $bytbeg = 0;

    if ( (( $seqmax - $seqend ) % 2) > 0 )
    {
        $bytbeg += 1;
        $endch = vec $bytstr, 1, 4;
    }
    else {
        $endch = "";
    }

    $bytend = (length $bytstr) - 1;

    if ( (( $seqmax - $seqbeg ) % 2) == 0 )
    {
        $bytend -= 1;
        $byte = substr $bytstr, -1, 1;
        $begch = vec $byte, 0, 4;
    }
    else {
        $begch = "";
    }

    $bytstr = substr $bytstr, $bytbeg, $bytend - $bytbeg + 1;

    # >>>>>>>>>>>>>>>>>>>>>> EXPAND TO SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<

    $bitvec = Bit::Vector->new( 8 * length $bytstr );
    $bitvec->Block_Store( $bytstr );

    $seqstr = $begch . $bitvec->to_Hex() . $endch;
    $seqstr =~ tr/0123456789ABCDEF/agcutrywsmkhdvbn/;

    return \$seqstr;
}

sub select_seqs
{
    # Niels Larsen, February 2010. 

    # Reads select entries from a sequence file or handle, in the given format,
    # while printing them to the given file or handle. The $include argument 
    # specifies which entries to select, or just how many: it can be a list, a
    # number or a file name of ids. The list ids must be ordered the same as 
    # those in the file, and all list ids must be in the file (of course the 
    # reverse is not true). See also read_seqs, which returns a list of 
    # sequence objects rather than writes a new file. 

    my ( $ifile,      # Input file path or handle
	 $format,     # Format used as part of read_(format)_seq routines
	 $include,    # IDs to include; list or file
	 $exclude,    # IDs to exclude; list or file
	 $ofile,      # Output file path or handle
	) = @_;

    # Returns a list.


    my ( $iclose, $oclose, $iroutine, $oroutine, $seq, $ref, $id, $ifh, $count );
    
    if ( not ref $ifile ) {
	$ifile = &Common::File::get_read_handle( $ifile );
	$iclose = 1;
    }

    if ( not ref $ofile ) {
	$ofile = &Common::File::get_write_handle( $ofile );
	$oclose = 1;
    }

    $iroutine = "Seq::IO::read_seq_$format";
    $oroutine = "Seq::IO::write_seq_$format"; $oroutine =~ s/1$//;
    
    $count = 0;

    no strict "refs";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> IDS TO GET <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( defined $include )
    {
	# A list, 

	if ( ref $include eq "ARRAY" )
	{
	    foreach $id ( @{ $include } )
	    {
		while ( $seq = $iroutine->( $ifile ) and $seq->id ne $id ) {};

		if ( defined $seq ) {
		    $oroutine->( $ofile, $seq );
		    $count += 1;
		} else {
		    &error( qq (Include-ID not found -> "$id") );
		}
	    }
	}
	
	# A file,

	elsif ( -r $include )
	{
	    $ifh = &Common::File::get_read_handle( $include );

	    while ( defined ( $id = <$ifh> ) )
	    {
		chomp $id;
		while ( $seq = $iroutine->( $ifile ) and $seq->id ne $id ) {};

		if ( defined $seq )
		{
		    $oroutine->( $ofile, $seq );
		    $count += 1;
		}
		else {
		    &error( qq (Include-ID not found -> "$id") );
		}
	    }

	    $ifh->close;
	}
	else {
	    $ref = ref $include;
	    &error( qq (Unsupported include list type -> "$ref") );
	}
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> IDS TO AVOID <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    elsif ( $exclude )
    {
	# A list,  

	if ( ref $exclude eq "ARRAY" )
	{
	    foreach $id ( @{ $exclude } )
	    {
		while ( $seq = $iroutine->( $ifile ) and $seq->id ne $id )
		{
		    $oroutine->( $ofile, $seq );
		    $count += 1;
		};

		if ( not defined $seq ) {
		    &error( qq (Exclude-ID not found -> "$id") );
		}
	    }

	    while ( $seq = $iroutine->( $ifile ) )
	    {
		$oroutine->( $ofile, $seq );
		$count += 1;
	    };
	}
	
	# A file,

	elsif ( -r $exclude )
	{
	    $ifh = &Common::File::get_read_handle( $exclude );

	    while ( defined ( $id = <$ifh> ) )
	    {
		chomp $id;

		while ( $seq = $iroutine->( $ifile ) and $seq->id ne $id )
		{
		    $oroutine->( $ofile, $seq );
		    $count += 1;
		};

		if ( not defined $seq ) {
		    &error( qq (Exclude-ID not found -> "$id") );
		}
	    }

	    $ifh->close;

	    while ( $seq = $iroutine->( $ifile ) )
	    {
		$oroutine->( $ofile, $seq );
		$count += 1;
	    };

	}
	else {
	    $ref = ref $exclude;
	    &error( qq (Unsupported exclude list type -> "$ref") );
	}
    }	
    else {
	&error( qq (An include or exclude filter must be given) );
    }
	
    if ( $iclose ) {
	&Common::File::close_handle( $ifile );
    }
    
    if ( $oclose ) {
	&Common::File::close_handle( $ofile );
    }
    
    return $count;
}

sub select_seqs_fasta
{
    # Niels Larsen, February 2010.

    # Reads fasta formatted entries sequentially from a given input and writes
    # select ones to a given output. See the select_seqs routine for detail.
    # The select_(format)_seqs routines writes new files instead of returning
    # lists. For random access, see the get_* routines. 

    my ( $ifile,         # Input fasta file or handle (<stdin>)
         $include,       # Entries to read, list or file
	 $exclude,       # Entries to avoid, list or file
         $ofile,         # Output fasta file or handle (<stdout>)
         ) = @_;

    # Returns a list.

    my ( $count );

    $count = &Seq::IO::select_seqs( $ifile, "fasta", $include, $exclude, $ofile );

    return $count;
}

sub select_seqs_fastq
{
    # Niels Larsen, February 2010.

    # Reads fastq formatted entries sequentially from a given input and writes
    # select ones to a given output. See the select_seqs routine for detail.
    # The select_(format)_seqs routines writes new files instead of returning
    # lists. For random access, see the get_* routines. Returns the number of 
    # entries written.

    my ( $ifile,         # Input fastq file or handle (<stdin>)
         $include,       # Entries to read
	 $exclude,       # Entries to avoid
         $ofile,         # Output fastq file or handle (<stdout>)
         ) = @_;

    # Returns integer.

    my ( $count );

    $count = &Seq::IO::select_seqs( $ifile, "fastq", $include, $exclude, $ofile );

    return $count;
}

sub split_id
{
    # Niels Larsen, July 2007.

    # Splits a given string into a given number of substrings, which
    # are returned as a list.

    my ( $id,              # ID string or number
         $elems,           # Number of fragments 
        ) = @_;

    # Returns a list.

    my ( $id_len, $len, $beg, @ids );

    $id_len = length $id;
    $beg = 0;

    while ( $elems > 0 and $id_len > 0 )
    {
        $len = &Common::Util::ceil( $id_len / $elems );

        push @ids, substr $id, $beg, $len;

        $beg += $len;
        $elems -= 1;
        $id_len -= $len;
    }

    return wantarray ? @ids : \@ids;
}

sub split_seqs_fasta
{
    # Niels Larsen, May 2010.

    # Splits the sequences in one or more fasta files, so that no sequence is 
    # longer than a given maximum. Returns a list of the output file paths.

    my ( $args,
         $msgs,
        ) = @_;
    
    # Returns a list.

    my ( $defs, @ifiles, @ofiles, @msgs, $i, $seq, $ifile, $ofile, $count,
         $ifh, $ofh, $min_len, $max_len, $sub_seq, $sub_len, $beg, $max_beg,
         $seq_len, $sub_info, $seq_id, $silent, $name, $all_out, $read_sub );

    # >>>>>>>>>>>>>>>>>>>>>>>> GET AND CHECK ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ifiles" => [],
        "maxlen" => 10_000_000,
        "minlen" => 1,
        "suffix" => ".split",
        "single" => 1,
        "index" => 1,
        "allout" => 1,
        "replace" => 0,
        "clobber" => 0,
        "silent" => 0,
    };

    return $defs if not ref $args;

    $args = &Registry::Args::create( $args, $defs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> GET AND CHECK FILES <<<<<<<<<<<<<<<<<<<<<<<<<<

    @ifiles = @{ $args->ifiles };
    @ofiles = map { $_ . $args->suffix } @ifiles;

    @msgs = ();

    @ifiles = &Common::File::check_files( \@ifiles, "efr", \@msgs );

    if ( not $args->clobber ) {
        @ofiles = &Common::File::check_files( \@ofiles, "!e", \@msgs );
    }
    
    if ( @msgs )
    {
        if ( defined wantarray and defined $msgs ) {
            push @{ $msgs }, @msgs; return;
        } else {
            &echo_messages( \@msgs ); exit;
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> SPLIT SEQUENCES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $silent = $args->silent;

    &echo_bold( "\nSplitting sequences:\n" ) unless $silent;

    if ( $args->maxlen =~ /^[\d_]+$/ ) {
        $max_len = $args->maxlen;
    } else {
        $max_len = &Common::Util::expand_number( $args->maxlen );
    }

    $max_beg = $max_len - 1;

    $min_len = $args->minlen;
    $all_out = $args->allout;

    if ( $args->single ) {
        $read_sub = "Seq::IO::read_seq_fasta";
    } else {
        $read_sub = "Seq::IO::read_seq_fasta_wrapped";
    }

    for ( $i = 0; $i <= $#ifiles; $i++ )
    {
        $ifile = $ifiles[$i];
        $ofile = $ofiles[$i];

        if ( $args->replace ) {
            $name = &File::Basename::basename( $ifile );
            &echo("   Replacing $name ... ") unless $silent;
        } else {
            $name = &File::Basename::basename( $ofile );
            &echo("   Writing $name ... ") unless $silent;
        }

        $ifh = &Common::File::get_read_handle( $ifile );
        $ofh = &Common::File::get_write_handle( $ofile, "clobber" => $args->clobber );

        no strict "refs";

        while ( defined ( $seq = $read_sub->( $ifh ) ) )
        {
            if ( ( $seq_len = $seq->seq_len ) > $max_len )
            {
                $seq_id = $seq->id;
                $sub_info = &Seq::Info::objectify( $seq->info // "" );

                for ( $beg = 0; $beg < $seq_len; $beg += $max_len )
                {
                    $sub_len = &List::Util::min( $max_len, $seq_len - $beg );
                    $sub_seq = $seq->sub_seq( [[ $beg, $sub_len ]] );
                    $sub_seq->id( $sub_seq->id .".". ($beg + 1) );

                    $sub_info->orig_id( $seq_id );
                    $sub_info->orig_coords( [[ $beg + 1, $sub_len ]] );

                    $sub_seq->info( &Seq::Info::stringify( $sub_info ) );

                    &Seq::IO::write_seq_fasta( $ofh, $sub_seq );
                }
            }
            elsif ( $all_out ) {
                &Seq::IO::write_seq_fasta( $ofh, $seq );
            }
        }
        
        $ofh->close;
        $ifh->close;

        if ( $args->replace ) {
            &Common::File::rename_file( $ofile, $ifile );
        }

        &echo_green("done\n") unless $silent;

        if ( $args->index ) 
        {
            &echo("   Indexing $name ... ") unless $silent;

            if ( $args->replace ) {
                &Seq::Storage::index_seq_file( { "ifile" => $ifile, "clobber" => 1 } );
            } else {
                &Seq::Storage::index_seq_file( { "ifile" => $ofile } );
            }

            &echo_green("done\n") unless $silent;
        }
    }

    $silent or &echo_bold( "Done\n\n" );

    return;
}

sub spool_seqs_fasta
{
    # Niels Larsen, August 2010.

    # Writes from one fasta file or handle and writes to another fasta
    # file or handle. Input entries may be multi-line, output is single-
    # line. A single sequence is not held in ram, only single lines are.
    # Use this to conserve ram for large sequences.

    my ( $ifile,
         $ofile,
         $regex,
         $fields,
        ) = @_;

    # Returns integer.

    my ( $line, %info, $count, $iclose, $oclose, $header );

    if ( not ref $ifile )
    {
        $ifile = &Common::File::get_read_handle( $ifile );
        $iclose = 1;
    }

    if ( not ref $ofile )
    {
        $ofile = &Common::File::get_write_handle( $ofile );
        $oclose = 1;
    }

    $regex //= '^([^ ]+)';
    $fields //= { "seq_id" => '$1' };

    if ( not defined $fields->{"seq_id"} ) {
        &error( qq (No seq_id field given) );
    }

    $count = 0;

    while ( defined ( $line = <$ifile> ) )
    {
        if ( $line =~ /^>/ )
        {
            if ( $line =~ /^>(.+)$/ ) {
                $header = $1;
            } else {
                &error( "Line problem" );
            }

            $ofile->print("\n") if $count > 0;

            %info = &Common::Util::parse_string( $header, $regex, $fields );

            $ofile->print( ">". $info{"seq_id"} );
            delete $info{"seq_id"};

            if ( %info ) {
                $ofile->print( " ". &Seq::Info::stringify( \%info ) );
            }
            
            $ofile->print("\n");

            $count += 1;
        }
        else 
        {
            $line =~ s/\s//g;
            $ofile->print( $line );
        }
    }

    $ofile->print("\n");

    $ifile->close if $iclose;
    $ofile->close if $oclose;

    return $count;
}
    
sub trim_fasta_ids
{
    my ( $ifile, 
         $len,
         $ofile,
        ) = @_;
    
    my ( $ifh, $tfh, $seq, $temp_file );

    $temp_file = "$ifile.temp";
    &Common::File::delete_file_if_exists( $temp_file );

    $ifh = &Common::File::get_read_handle( $ifile );
    $tfh = &Common::File::get_write_handle( $temp_file );

    while ( $seq = &Seq::IO::read_seq_fasta( $ifh ) )
    {
        $seq->repair_id( $len );

        &Seq::IO::write_seq_fasta( $tfh, $seq );
    }

    if ( defined $ofile )
    {
        &Common::File::rename_file( $temp_file, $ofile );
    }
    else 
    {
        &Common::File::delete_file( $ifile );
        &Common::File::rename_file( $temp_file, $ifile );
    }

    return;
}

sub write_locators
{
    # Niels Larsen, February 2010.
    
    # Formats and writes a given list of locators to a given file or
    # file handle. Returns the number of locators written.

    my ( $file,   # Output file or handle
         $locs,   # List of locators
        ) = @_;

    # Returns nothing.

    my ( $ofh, $loc );
    
    if ( ref $file ) {
        $ofh = $file;
    } else {
        $ofh = &Common::File::get_write_handle( $file );
    }

    foreach $loc ( @{ $locs } )
    {
        $ofh->print( &Seq::Common::format_locator( $loc ) ."\n" );
    }

    &Common::File::close_handle( $ofh ) unless ref $file;

    return scalar @{ $locs };
}

sub write_seq_fasta
{
    # Niels Larsen, June 2005.

    # Prints an entry on a given file handle in fasta format. 

    my ( $fh,           # File handle
         $seq,          # Sequence entry to be written
         ) = @_;

    # Returns nothing. 

    my ( $info );
    
    if ( $info = $seq->{"info"} )
    {
        if ( ref $info ) {
            $fh->print( ">". $seq->{"id"} ." ". &Seq::Info::stringify( $info ) ."\n". $seq->{"seq"} ."\n" );
        } else {
            $fh->print( ">". $seq->{"id"} ." ". $info ."\n". $seq->{"seq"} ."\n" );
        }            
    }
    else {
        $fh->print( ">". $seq->{"id"} ."\n". $seq->{"seq"} ."\n" );
    }

    return;
}

sub write_seq_fastq
{
    # Niels Larsen, October 2009.

    # Prints an entry on a given file handle in fasta format. 

    my ( $fh,           # File handle
         $seq,          # Sequence entry to be written
         ) = @_;

    # Returns nothing. 

    if ( $seq->{"info"} ) {
        $fh->print( "@". $seq->{"id"} ."\n". $seq->{"seq"} ."\n+". $seq->{"info"} ."\n". $seq->{"qual"} ."\n" );
    } else {
        $fh->print( "@". $seq->{"id"} ."\n". $seq->{"seq"} ."\n+\n". $seq->{"qual"} ."\n" );
    }

    return;
}

sub write_seqs_fasta
{
    # Niels Larsen, December 2011.

    # Writes a list of sequence entries to a given file handle. Returns the 
    # number of sequences written.

    my ( $fh,           # File handle
         $seqs,         # List of sequence objects or hashes 
         ) = @_;

    # Returns an integer. 
    
    my ( $seq, $info );

    foreach $seq ( @{ $seqs } )
    {
        if ( $info = $seq->{"info"} )
        {
            if ( ref $info ) {
                $fh->print( ">". $seq->{"id"} ." ". &Seq::Info::stringify( $info ) ."\n". $seq->{"seq"} ."\n" );
            } else {
                $fh->print( ">". $seq->{"id"} ." ". $info ."\n". $seq->{"seq"} ."\n" );
            }
        }
        else {
            $fh->print( ">". $seq->{"id"} ."\n". $seq->{"seq"} ."\n" );
        }
    }

    return scalar @{ $seqs };
}

sub write_seqs_fastq
{
    # Niels Larsen, December 2011.

    # Writes a list of sequence entries to a given file handle in fastq format.
    # Returns the number of sequences written. 

    my ( $fh,          # File handle
         $seqs,        # List of sequence objects or hashes
         ) = @_;

    # Returns an integer.

    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        if ( $seq->{"info"} ) {
            $fh->print( "@". $seq->{"id"} ."\n". $seq->{"seq"} ."\n+". $seq->{"info"} ."\n". $seq->{"qual"} ."\n" );
        } else {
            $fh->print( "@". $seq->{"id"} ."\n". $seq->{"seq"} ."\n+\n". $seq->{"qual"} ."\n" );
        }
    }

    return scalar @{ $seqs };
}

sub write_seqs_file
{
    # Niels Larsen, December 2011.

    # Writes a list of sequence entries to a given named file in the given 
    # format. The file may not exist. Returns the number of sequences written. 

    my ( $file,
         $seqs,
         $fmt,
        ) = @_;

    # Returns an integer. 

    my ( $routine, $fh );

    $routine = "Seq::IO::write_seqs_$fmt";

    $fh = &Common::File::get_write_handle( $file );

    no strict "refs";

    $routine->( $fh, $seqs );

    &Common::File::close_handle( $fh );

    return;
}

sub write_seqs_handle
{
    # Niels Larsen, December 2011.

    # Writes a list of sequence entries to a given file handle in the given 
    # format. The file may not exist. Returns the number of sequences written. 

    my ( $fh,
         $seqs,
         $fmt,
        ) = @_;

    # Returns an integer. 

    my ( $routine );

    no strict "refs";

    $routine = "Seq::IO::write_seqs_$fmt";

    $routine->( $fh, $seqs );

    return;
}

sub write_seqs_ids
{
    my ( $fh,
         $seqs,
        ) = @_;

    my ( $seq );

    foreach $seq ( @{ $seqs } )
    {
        $fh->print( $seq->{"id"} ."\n" );
    }

    return scalar @{ $seqs };
}

sub write_seqs_json
{
    # Niels Larsen, February 2011. 

    # DOESNT WORK: writes [...],[...],[...  and no easy way to avoid it.
    # Must install JSON::XS and play with that. 

    # Writes a list of sequence hashes to an open file handle in JSON
    # format. If a fields list is given, only those fields are written.
    # Returns nothing.

    my ( $fh,       # Open file handle
         $seqs,     # Sequence hashes
         $flds,     # Fields list - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( @flds, @seqs, $seq );

    local $JSON::Syck::SingleQuote = 1;

    if ( defined $flds )
    {
        foreach $seq ( @{ $seqs } )
        {
            push @seqs, { map { $_, $seq->{ $_ } } @{ $flds } };
        }

        &JSON::Syck::DumpFile( $fh, @seqs );
    }
    else {
        &JSON::Syck::DumpFile( $fh, @{ $seqs } );
    }

    return;
}

sub write_seqs_table
{
    # Niels Larsen, February 2011. 

    # Writes a list of sequence hashes to an open file handle in tabular
    # format. If a fields list is given, only those fields are written.
    # Returns nothing.

    my ( $fh,       # Open file handle
         $seqs,     # Sequence hashes
         $flds,     # Fields list - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( $seq );

    if ( not defined $flds ) {
        @{ $flds } = ( "id", grep { $_ ne "id" } keys %{ $seqs->[0] } );
    }

    foreach $seq ( @{ $seqs } )
    {
        $fh->print( ( join "\t", map { $seq->{ $_ } } @{ $flds } ) ."\n" );
    }

    return;
}

sub write_seqs_yaml
{
    # Niels Larsen, February 2011. 

    # Writes a list of sequence hashes to an open file handle in YAML
    # format. If a fields list is given, only those fields are written.
    # Returns nothing.

    my ( $fh,       # Open file handle
         $seqs,     # Sequence hashes
         $flds,     # Fields list - OPTIONAL
        ) = @_;

    # Returns nothing.

    my ( @seqs, $seq, $yaml );

    local $YAML::Syck::Headless = 1;

    if ( defined $flds )
    {
        foreach $seq ( @{ $seqs } )
        {
            push @seqs, { map { $_, $seq->{ $_ } } @{ $flds } };
        }

        &YAML::Syck::DumpFile( $fh, \@seqs );
    }
    else {
        &YAML::Syck::DumpFile( $fh, $seqs );
    }

    return;
}

sub write_table_seqs_dbm
{
    my ( $tfile,
         $sfile,
        ) = @_;
    
    my ( $ifh, $sfh, $dbh, @line, $line, $mpack, $seqs, $id, $count,
         $seq, $seqstr, $id_ndx, $tot_ndx, $seq_ndx, @skip, @ndcs, %skip,
         $tot );

    $ifh = &Common::File::get_read_handle( $tfile );
    $sfh = &Common::File::get_write_handle( $sfile );

    $line = <$ifh>;
    @line = split "\t", $line;
    $line[0] =~ s/#\s*//;

    @skip = &Common::Table::names_to_indices( ["ID","Total","Sequence"], \@line );
    %skip = map { $_, 1 } @skip;

    @ndcs = grep { not $skip{ $_ } } ( 0 ... $#line );
    
    $mpack = Data::MessagePack->new();
    $seqs = 0;
    
    $dbh = &Common::DBM::write_open( "$tfile.dbm" );

    while ( defined ( $line = <$ifh> ) )
    {
        $line =~ s/\n$//;
        @line = split "\t", $line;

        ( $id, $tot, $seq ) = @line[ @ndcs ];
        @line = @line[ @ndcs ];

        &Seq::IO::write_seq_fasta(
            $sfh,
            {
                "id" => $id,
                "seq" => $seq,
                "info" => "seq_count=$tot",
            });

        &Common::DBM::put( $dbh, $id, $mpack->pack( \@line ) );

        $seqs += 1;
    }
        
    &Common::DBM::close( $dbh );

    &Common::File::delete_file( "$tfile.dbm" );

    &Common::File::close_handle( $sfh );
    &Common::File::close_handle( $ifh );
    
    return $seqs;
}

sub write_table_seqs
{
    # Niels Larsen, January 2012. 

    # Writes the ID and Sequence fields of a sequence table to fasta 
    # format. Returns the number of sequences written.

    my ( $tfile,     # Input table file
         $sfile,     # Output sequence file
        ) = @_;

    # Returns integer.
    
    my ( $ifh, $sfh, @line, $line, $seqs, $id, $count, $seq, @ndcs, $tot );

    $ifh = &Common::File::get_read_handle( $tfile );
    $sfh = &Common::File::get_write_handle( $sfile );

    $line = <$ifh>;
    chomp $line;

    @line = split "\t", $line;
    $line[0] =~ s/#\s*//;

    @ndcs = &Common::Table::names_to_indices( ["ID","Total","Sequence"], \@line );

    $seqs = 0;
    
    while ( defined ( $line = <$ifh> ) )
    {
        $line =~ s/\n$//;
        @line = split "\t", $line;

        ( $id, $tot, $seq ) = @line[ @ndcs ];

        &Seq::IO::write_seq_fasta(
            $sfh,
            {
                "id" => $id,
                "seq" => $seq,
                "info" => "seq_count=$tot",
            });

        $seqs += 1;
    }
        
    &Common::File::close_handle( $sfh );
    &Common::File::close_handle( $ifh );
    
    return $seqs;
}

1;

__DATA__

__C__

/* Niels Larsen, May 2004. */

static void* get_ptr( SV* obj ) { return SvPVX( SvRV( obj ) ); }

#define DEF_SCOPTR( str )  int* scoptr = get_ptr( str )
#define DEF_NDXPTR( str )  int* ndxptr = get_ptr( str )
#define FETCH( idx )       ndxptr[ idx ]
#define INCR( idx )        scoptr[ idx ]++

void trim_end_C( SV* chars, int maxndx )
{
    int i;
    int j;

    for ( i = 0; i <= maxndx; i++ ) 
    {
//        printf( INCR( FETCH(i) ); 
    }
}

__END__

# sub read_primer_conf_tags
# {
#     # Niels Larsen, October 2011. 

#     # Makes a list with all combinations of the given primers and the given
#     # tags. If there is a __TAG__ token in the pattern string, then tags
#     # replace that, otherwise they will be prepended. 

#     my ( $args,
#         ) = @_;
    
#     # Returns a list.

#     my ( $pris, $pris_copy, $tags, $tag, $tagseq, $pri, @list, @msgs, 
#          $suffix, $patstr, @patstr );

#     $pris = &Seq::IO::read_primer_conf( $args->{"patfile"} );
#     $tags = &Seq::IO::read_table_tags( $args->{"barfile"} );

#     foreach $tag ( @{ $tags } )
#     {
#         $pris_copy = &Storable::dclone( $pris );
        
#         foreach $pri ( @{ $pris_copy } )
#         {
#             if ( $tagseq = $tag->{ $pri->{"tag_label"} } )
#             {
#                 $pri->{"tag_seq"} = $tagseq;
#                 $pri->{"tag_id"} = $tag->{"ID"} if defined $tag->{"ID"};

#                 $patstr = $pri->{"pat_string"};
                
#                 if ( $pri->{"tag_pos"} and $pri->{"tag_pos"} eq "end" )
#                 {
#                     $patstr .= " $tagseq";

#                     if ( $pri->{"get_subpats"} )
#                     {
#                         @patstr = split " ", $patstr;
#                         push @{ $pri->{"get_subpats"} }, $#patstr;
#                     }
#                 }
#                 else
#                 {
#                     $patstr = qq ($tagseq $patstr);

#                     if ( $pri->{"get_subpats"} ) {
#                         $pri->{"get_subpats"} = [ 0, map { $_ + 1 } @{ $pri->{"get_subpats"} } ];
#                     }
#                 }

#                 $pri->{"pat_string"} = $patstr;

#                 if ( $pri->{"tag_qualpos"} ) {
#                     $pri->{"tag_qualpos"} = [ map { $_ - 1 } split /\s*,\s*/, $pri->{"tag_qualpos"} ];
#                 } else {
#                     $pri->{"tag_qualpos"} = [ 0 ... ( (length $tagseq) - 1 ) ];
#                 }
#             }

#             if ( not $suffix = $pri->{"tag_id"} ) {
#                 $suffix = $tagseq;
#             }
            
#             if ( $pri->{"out_suffix"} ) {
#                 $suffix .= $pri->{"out_suffix"};
#             } else {
#                 $suffix .= $pri->{"seq_orient"} eq "forward" ? ".F" : ".R";
#             }

#             $pri->{"out_suffix"} = $suffix;
#         }

#         push @list, $pris_copy;
#     }

#     &append_or_exit( \@msgs );

#     return wantarray ? @list : \@list;
# }

# sub get_seq_split
# {
#     # Niels Larsen, June 2007.

#     # Retrieves a sequence by its accession number, from the local DNA
#     # databank installation if present, otherwise remotely from GenBank.
#     # Key/value arguments are "beg", "end", "reverse" and "fatal". If
#     # "fatal" is given, then .. 
    
#     my ( $class,
#          $id,            # Accession number
#          $args,          # Arguments hash - OPTIONAL
#          $msgs,          # Outgoing messages - OPTIONAL
#         ) = @_;

#     # Returns a Seq::Common object.

#     my ( $stdout, $seqref, $dir_name, $day_path, $rel_path, $grep, $cat, 
#          $sv, $acc, $fname, $fpath, $bin_dir, $seqio, $sfh, $seq, $entry,
#          $db_path, $acc_sv, @dirs, $gi, @lines, $i, $i_beg, $i_end, $seqlen,
#          $bytbeg, $bytend, $seqbeg, $seqend, $ndxmax, $header_sub, $seqstr,
#          $bitvec, $bitlen, $word_bits );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ qw ( dbtype dbpath dir_levels ) ],
#         "S:0" => [ qw ( dbfile beg end reverse header header_sub fatal checkonly ) ],
#     });

#     $msgs = [] if not defined $msgs;

#     # >>>>>>>>>>>>>>>>>>>>>>>> SET DIRECTORY <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # If Installs exists use that, or else look in Installs_new, or if
#     # that doesnt exist either, error or return.

#     $db_path = $args->dbpath;

#     if ( -e "$db_path/Installs" )
#     {
#         $rel_path = "$db_path/Installs";
#     }
#     elsif ( -e "$db_path/Installs_new" )
#     {
#         $rel_path = "$db_path/Installs_new";
#     }
#     elsif ( $args->fatal ) {
#         &error( qq (No Installs or Installs_new directory.) );
#     }
#     else {
#         return;
#     }

#     $day_path = "$rel_path/Daily";

#     # >>>>>>>>>>>>>>>>>>>>>>>> SET FILE PATH <<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Grep the file LOOKUP_LIST to get the name of the smalll "chunk-file"
#     # that contains the entry,

#     $grep = "$Common::Config::bin_dir/grep -m 1 ";

#     # NCBI Eutils bug: accession numbers come back like 1Q7Y_B, which
#     # does not fetch a record, but 1Q7YB does. Reported. 

#     if ( $id =~ /^([A-Z0-9_]+)(\.\d+)?$/ ) {
#         $acc = $1;
#     } else {
#         &error( qq (Wrong looking accession.version string -> "$id") );
#     }
    
#     @dirs = &Seq::IO::split_id( $acc, $args->dir_levels + 1 );
#     $dir_name = join "/", @dirs[ 0 .. $#dirs-1 ];

#     if ( -e "$day_path/$dir_name/LOOKUP_LIST" and 
#          @{ $stdout } = &Common::OS::run_command( "$grep '^$id\\b' $day_path/$dir_name/LOOKUP_LIST", undef, $msgs ) )
#     {
#         ( $acc_sv, $fname, $bytbeg, $seqlen ) = split " ", $stdout->[0];
#         $fpath = "$day_path/$dir_name/$fname";
#     }
#     elsif ( -e "$rel_path/$dir_name/LOOKUP_LIST" and
#             @{ $stdout } = &Common::OS::run_command( "$grep '^$id\\b' $rel_path/$dir_name/LOOKUP_LIST", undef, $msgs ) )
#     {
#         ( $acc_sv, $fname, $bytbeg, $seqlen ) = split " ", $stdout->[0];
#         $fpath = "$rel_path/$dir_name/$fname";
#     }
#     elsif ( $args and $args->fatal ) {
#         &error( qq (GI number not found -> "$id") );
#     }
#     else {
#         return;
#     }

#     if ( $args->checkonly )
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>> CHECKONLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         # Returns true if entry is present, nothing otherwise,

#         if ( $fpath and -r $fpath ) {
#             return 1;
#         } else {
#             return;
#         }
#     }
#     else 
#     {
#         # >>>>>>>>>>>>>>>>>>>>>>>>>> SEQUENCE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         if ( $args->beg )
#         {
#             $seqbeg = $args->beg;

#             if ( $seqbeg < 0 ) {
#                 &error( qq (Begin-index is negative -> "$seqbeg") );
#             }

#             if ( $seqbeg >= $seqlen ) {                
#                 $seqlen -= 1;
#                 &error( qq (Begin-index exceeds max ($seqlen) -> "$seqbeg") );
#             }
#         }
#         else {
#             $seqbeg = 0;
#         }
        
#         if ( $args->end )
#         {
#             $seqend = $args->end;

#             if ( $seqend < 0 ) {
#                 &error( qq (End-index is negative -> "$seqend") );
#             }

#             if ( $seqend >= $seqlen ) {
#                 $seqlen -= 1;
#                 &error( qq (End-index exceeds max ($seqlen) -> "$seqend") );
#             }
#         }
#         else {
#             $seqend = $seqlen - 1;
#         }
        
#         if ( $seqend < $seqbeg ) {
#             &error( qq (Begin-index higher than end-index: $seqbeg > $seqend) );
#         }

#         if ( $fpath =~ /\.fa$/ )
#         {
#             $seqref = &Common::File::seek_file( $fpath, 
#                                                 $bytbeg + $seqbeg, 
#                                                 $bytbeg + $seqend );
#         }
#         elsif ( $fpath =~ /\.bin$/ )
#         {
#             $seqref = &Seq::IO::seek_4bit({
#                 "fpath" => $fpath,
#                 "bytmin" => $bytbeg,
#                 "seqlen" => $seqlen,
#                 "seqbeg" => $seqbeg,
#                 "seqend" => $seqend,
#             });
#         }
#         else {
#             &error( qq (Wrong looking sequence file suffix -> "$fname") );
#         }

#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HEADER <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         if ( $args->header )
#         {
#             $header_sub = $args->header_sub;
#             $fpath = &Common::Names::strip_suffix( $fpath ) .".hdr";

#             no strict "refs";

#             $seq = $header_sub->({ 
#                 "infile" => $fpath,
#                 "acc" => $acc,
#                 "fatal" => $args->fatal,
#             });
#         }
#         else 
#         {
#             $acc_sv =~ /^(.+)\.(\d+)$/;

#             $seq = Bio::Seq->new(
#                 -display_id => $acc_sv,
#                 -primary_id => $acc_sv,
#                 -accession_number => $1,
#                 -version => $2,
#             );
#         }
            
#         $seq->seq( ${ $seqref } );

#         if ( defined $seq ) {
#             return $seq;
#         } else {
#             return;
#         }
#     }
# }


# sub get_seq_indexed
# {
#     # Niels Larsen, June 2007.

#     # Gets a sequence entry from a local file. This is used for 
#     # smaller datasets. 

#     my ( $class,
#          $id,
#          $args,          # Arguments 
#          $msgs,          # Outgoing messages - OPTIONAL
#         ) = @_;

#     # Returns a Bio::Seq object.

#     my ( $index_path, $db, $bp_seq, $seq, $format, @formats, $p,
#          $entry, $module, $str, $beg, $end );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ qw ( dbfile ) ],
#         "S:0" => [ qw ( beg end reverse header fatal ) ],
#     });

#     $module = "Bio::Index::Abstract";
#     $index_path = $args->dbfile .".bp_index";
    
#     if ( not -r $index_path ) {
#         &error( qq (Index not found -> "$index_path") );
#     }
    
#     {
#         no strict "refs";
#         $db = $module->new( $index_path );
#     }
    
#     if ( $entry = $db->get_Seq_by_id( $id ) )
#     {
#         $p = $entry->primary_seq;
        
#         $seq = Bio::Seq->new(
#             -seq => $p->seq,
#             -description => $p->description,
#             -display_id => $p->display_id,
#             -primary_id => $id,
#             -accession_number => $p->accession_number,
# #            -species => $entry->species ? $entry->species->binomial : "",
#             -species => $entry->species ? $entry->species : "",
#             -version => $p->version,
#             );
        
#         if ( defined $args->beg or defined $args->end )
#         {
#             $beg = defined $args->beg ? $args->beg+1 : 1;
#             $end = defined $args->end ? $args->end+1 : $seq->seq_len;
            
#             $seq->seq( $seq->subseq( $beg, $end ) );
#         }
#     }
#     elsif ( $args->fatal ) {
#         &error( 'Not found in index file -> "'. $args->id .'"'
#                                  ."\nIndex file -> $index_path" );
#     }

#     return $seq;
# }

# sub remove_overlaps
# {
#     my ( $coords,
#          ) = @_;

#     my ( @coords, $i, $c, $cl );

#     @coords = ( sort { $a->[0] <=> $b->[0] } @{ $coords } )[0];

#     for ( $i = 1; $i <= $#{ $coords }; $i++ )
#     {
#         $c = $coords->[$i];
#         $cl = $coords[-1];
        
#         if ( $c->[0] != $cl->[0] or $c->[1] != $cl->[1] or 
#              $c->[2] != $cl->[2] or $c->[3] != $cl->[3] )
#         {
#             push @coords, $c;
#         }
#     }

#     return wantarray ? @coords : \@coords;
# }

# our $Read_Buffer = "";
# our $Read_Offset = 0;

# sub get_seqs_db
# {
#     # Niels Larsen, February 2010. 

#     # Given a list of ids, returns a list of corresponding Seq::Common objects.
#     # If $annot is true, returns annotation as well - TODO - improve and get rid 
#     # of bioperl.

#     my ( $class,
# 	 $locs,      # Locator list
#          $dbhs,      # Dataset handles
#          $args,
#          $msgs,
#         ) = @_;
    
#     # Returns a list.

#     my ( $conf, $write_seqs, $return_seqs, $seq_type, $beg, $len, $seq, $seqs, 
#          $buf, $fh, $entry, $taxon, $p_seq );
    
#     $defs = {
#         "write_seqs" => 1,
#         "return_seqs" => 0,
#         "datatype" => "dna",
#         "clobber" => 0,
#         "verbose" => 0,
#         "silent" => 0,
#     };
    
#     $conf = &Registry::Args::create( $args, $defs );
    
#     $write_seqs = $conf->write_seqs;
#     $return_seqs = $conf->return_seqs;
#     $seq_type = $conf->datatype;

#     # Sequences - fast,

#     $seqs = Seq::IO->get_seqs_file( 
# 	$locs,
# 	$dbhs->{"seqs_file_handle"},
# 	$dbhs->{"seqs_ndx_handle"},
# 	$type // &Common::Types::truncate_type( $dbhs->{"datatype"} ),
# 	);
    
#     # Annotation - very slow,  TODO avoid parsing with bioperl,

#     if ( $annot )
#     {
#         foreach $seq ( @{ $seqs } )
#         {
#             ( $beg, $len ) = split " ", &Common::DBM::get( $dbhs->{"hdrs_ndx_handle"}, $seq->id );
            
#             sysseek( $dbhs->{"hdrs_file_handle"}, $beg, SEEK_SET );
#             sysread( $dbhs->{"hdrs_file_handle"}, $buf, $len );

#             $fh = new IO::String( $buf );
#             $entry = Bio::SeqIO->new( -fh => $fh )->next_seq;

#             if ( $entry )
#             {
#                 $p_seq = $entry->primary_seq;
#                 $taxon = $entry->species;
	
#                 $seq->annot( 
#                     Bio::Seq->new
#                     (
#                      -description => $p_seq->description,
#                      -display_id => $p_seq->display_id,
#                      -primary_id => $seq->id,
#                      -accession_number => $p_seq->accession_number,
#                      -species => {
#                          "common_name" => $taxon->common_name || "",
#                          "name" => $taxon->binomial || "",
#                          "classification" => [ reverse $taxon->classification ],
#                      },
#                      -version => $p_seq->version,
#                     ));
#             }
#         }
#     }       

#     return wantarray ? @{ $seqs } : $seqs;
# }

# sub read_genbank_entry
# {
#     my ( $class,
#          $id,
#          $params,
#          $msgs,
#          ) = @_;

#     my ( %def_params, $cache, $zcat, $entry, $msg, $path, $suffix );

#     %def_params = ( "format" => "bioperl", "source" => "local",
#                     "datatype" => "dna_seq" );

#     if ( defined $params ) {
#         $params = { %def_params, %{ $params } };
#     } else {
#         $params = \%def_params;
#     }

#     $id = &Common::Names::strip_suffix( $id );
        
#     if ( $params->{"source"} eq "local" )
#     {
#         $path = Registry::Get->type( $params->{"datatype"} )->path;

#         if ( $id =~ /^\d+$/ )
#         {
#             $cache = "$Common::Config::dat_dir/$path/Cache/GI";
#             $suffix = "";
#         }
#         else {
#             $cache = "$Common::Config::dat_dir/$path/Cache/ACC";
#             $suffix = ".gz";
#         }

#         $zcat = "$Common::Config::bin_dir/zcat";

#         if ( $params->{"format"} eq "bioperl" )
#         {
#             if ( -r "$cache/$id$suffix" )
#             {
#                 $entry = Bio::SeqIO->new( -file => "$zcat < $cache/$id$suffix |", -format => "genbank" );
#             }
#             else
#             {
#                 $msg = qq (Non-existing file -> "$cache/$id$suffix");

#                 if ( defined $msgs ) {
#                     push @{ $msgs }, [ "Error", $msg ];
#                 } else {
#                     &error( $msg );
#                 }
#             }
#         }
#         else {
#             &error( qq (Wrong looking format -> "$params->{'format'}") );
#         }
#     }
#     else {
#         &error( qq (Wrong looking source -> "$params->{'source'}") );
#     }

#     return $entry;
# }
