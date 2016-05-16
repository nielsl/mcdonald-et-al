package Seq::Remote;                # -*- perl -*-

# Parses and checks common arguments to sequence routines. 

use strict;
use warnings FATAL => qw ( all );

use Scalar::Util;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &fetch_seqs_ebi
                 &fetch_seqs_ebi_args
                 &fetch_summary_ncbi
                 &fetch_summary_ncbi_args
                 );

use Common::Config;
use Common::Messages;

use Common::Entrez_new;
use Common::OS;
use Common::File;

use Registry::Register;
use Registry::Args;

use Seq::Args;
use Seq::IO;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub fetch_seqs_ebi
{
    # Niels Larsen, August 2010.

    # Fetches sequence by accession number from EBI and either returns them 
    # or writes them to file (or STDOUT). The SOAP-dependent ebi_fetch script
    # from EBI is used.

    my ( $args,          # Arguments hash
         $msgs,          # Outgoing message list - OPTIONAL
	) = @_;

    my ( $defs, $cmd, $beg, $end, $batch, $maxpos, @allids, @ids, $cmdbeg, 
         @msgs, $out_spec, $dbname, $format );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "ids" => [],
	"dbname" => undef,
        "format" => "fasta",
        "batch" => 100,
        "idfile" => undef,
    };

    $args = &Registry::Args::create( $args, $defs );

    $dbname = $args->dbname;
    $format = $args->format;
    $batch = $args->batch;
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ID LIST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @allids = &Seq::IO::read_locators( $args->ids, $args->idfile, 1 );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK OUTPUT FILE <<<<<<<<<<<<<<<<<<<<<<<<<<<

#     if ( $ofile )
#     {
#         $out_spec = ">> $ofile";

#         if ( not $args->append )
#         {
#             if ( $args->clobber ) {
#                 &Common::File::delete_file_if_exists( $ofile );
#             } else {
#                 &Common::File::access_error( $ofile, "!e" );
#             }
#         }
#     }
#     else {
#         $out_spec = "";
#     }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN EBI FETCH <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $cmdbeg = "ebi_fetch fetchBatch $dbname ";

    $maxpos = $#allids;

    for ( $beg = 0; $beg <= $maxpos; $beg += $batch )
    {
        $end = &List::Util::min( $beg + $batch - 1, $maxpos );

        $cmd = $cmdbeg . ( join ",", @allids[ $beg ... $end ] ) ." $format raw";

        &Common::OS::run3_command( $cmd );
    }
    
    return;
}

sub fetch_summary_ncbi_args
{
    # Niels Larsen, March 2010.

    # Checks arguments and prints errors and exits if there are any.

    my ( $ids,
         $args,      # Arguments
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $arg, %valid, $type );

    @msgs = ();

    if ( $type = $args->idtype ) 
    {
        %valid = map { $_, 1 } qw ( gi mmdb tax acc );

        if ( not $valid{ $type } ) {
            push @msgs, ["ERROR", qq (Wrong ID type -> "$type". Choices are acc, gi, mmdb or tax) ];
        }
    }

    # Input files and type,

    if ( $ids and not ref $ids ) {
	&Common::File::check_files( [ $ids ], "efr", \@msgs );
    }

    # Numerical arguments,
    
    foreach $arg ( qw ( batch tries timeout ) )
    {
        if ( defined $args->$arg ) {
            &Registry::Args::check_number( $args->$arg, 1, undef, \@msgs );
        }
    }

    &Registry::Args::check_number( $args->delay, 0, undef, \@msgs );

    # Output files,

    if ( $args->void )
    {
        if ( not defined $args->yaml and not defined $args->table ) {
            push @msgs, ["ERROR", qq (Either yaml or table output formats must be selected) ];
        }
    }

    if ( not $args->clobber )
    {
        &Common::File::check_files( [ $args->yaml ], "!e", \@msgs ) if $args->yaml;
        &Common::File::check_files( [ $args->table ], "!e", \@msgs ) if $args->table;
    }

    &append_or_exit( \@msgs );

    return;
}

sub fetch_summary_ncbi
{
    # Niels Larsen, October 2010.

    # Fetches summary information from NCBI via its E-utils for a list of IDs.
    # If the first argument is a string, then that is regarded as a file name
    # and STDIN is checked as well. If it is a list, then only that list is 
    # used. then those are input IDThe routine can return information and/or write files. 
    # If the The IDs can come from a from     # service. Input is a list of IDs given as file argument or taken from STDIN.
    # Output is a multi-column table where each row corresponds to an input ID. 
    # IDs are submitted in batches, and the script reading IDs until there is no
    # more input. Command line arguments are (defaults in parantheses),

    my ( $ids,      # File name or list - OPTIONAL
         $args,     # Arguments hash - OPTIONAL
        ) = @_;

    # Returns nothing. 

    my ( $defs, %args, $batch_size, $delay, $tries, $ifh, $ofh, @id_list,
         @all_sums, @sums, $sum, $line, $ncbi_args, $elem, $i, $j, @gis,
         @ids, @list, $epoch, $beg, $end, $msgs, %valid, %gi_to_id, $obj,
         $type, $ifile, %fields, @fields, @values, $table );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "idtype" => undef,
        "dbname" => "nucleotide",
        "yaml" => undef,
        "table" => undef,
	"fields" => undef,
        "titles" => 1,
        "uniqify" => 1,
        "batch" => 100,
        "delay" => 0,
        "tries" => 5,
        "timeout" => 5,
        "clobber" => 0,
	"silent" => 0,
	"verbose" => 0,
        "void" => 1,
    };

    $args = &Registry::Args::create( $args, $defs );

    if ( defined wantarray )
    {
        $Common::Messages::silent = 1;
        $args->void( 0 );
    }
    else {
        $Common::Messages::silent = $args->silent;
    }

    &Seq::Remote::fetch_summary_ncbi_args( $ids, $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CONVENIENCE VARIABLES <<<<<<<<<<<<<<<<<<<<<<<<<

    $batch_size = $args->batch;
    $delay = $args->delay;
    $tries = $args->tries;

    &echo_bold( "\nNCBI ID summaries:\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ IDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not ref $ids )
    {
        &echo( qq (   Reading input IDs ... ) );
        
        push @id_list, &Common::File::read_ids( $ids );
        
        push @id_list, &Common::File::read_stdin();
        
        if ( ( $i = scalar @id_list ) > 0 ) {
            &echo_green_number( $i );
        } else {
            &append_or_exit( [["ERROR", "No ids read" ]] );
        }
    }
    else {
        @id_list = @{ $ids };
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UNIQIFY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->uniqify )
    {
        &echo( qq (   Removing duplicates ... ) );

        $i = scalar @id_list;
        @id_list = &Common::Util::uniqify( \@id_list );
        $j = scalar @id_list;

        if ( $i > $j ) {
            &echo_green_number( ($i - $j) ." left" );
        } else {
            &echo_green( "none\n" );
        }
    }

    if ( $id_list[0] !~ /^\d+$/ ) {
        $args->idtype("acc");
    }

    # >>>>>>>>>>>>>>>>>>>>> CONVERT TO GIS IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<<<

    # The esummary.fcgi script at NCBI only understands gi, mmdb (structure) 
    # and tax ids. So anything else has to be translated, and translated back
    # again below,

    if ( $args->idtype and $args->idtype eq "acc" )
    {
        @gis = &Common::Entrez_new::efetch_ids(
            \@id_list,
            {
                "db" => $args->dbname,
                "rettype" => "gi",
                "retmode" => "xml",    # The only format available - bug submitted 
                "retmax" => $args->batch,
                "trymax" => $args->tries,
                "waitmax" => $args->timeout,
            }, $msgs );
        
        if ( ($i = scalar @gis) != ($j = scalar @id_list) ) {
            &error( qq (Number of accession numbers sent is $j, but number of received GI's is $i) );
        }

        for ( $i = 0; $i <= $#gis; $i++ ) {
            $gi_to_id{ $gis[$i] } = $id_list[$i];
        }
        
        @id_list = @gis;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> BATCH SUBMITS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $epoch = 0;

    for ( $beg = 0; $beg <= $#id_list; $beg += $batch_size )
    {
        $end = &Common::Util::min( $beg + $batch_size - 1, $#id_list );
        @ids = @id_list[ $beg .. $end ];

        &echo( "   Sending ". ($end-$beg+1) ." to E-utils ... " );

        $epoch = &Common::Entrez_new::wait_if_needed( $epoch );

        @sums = &Common::Entrez_new::esummary(
            \@ids,
            {
                "db" => $args->dbname,
                "tries" => $args->tries,
                "timeout" => $args->timeout,
            }, $msgs );
        
        $i = scalar @ids;
        $j = scalar @sums;

        if ( $j == $i ) {
            &echo_done( "got $j\n" ); 
        } else {
            &echo_yellow( "got $j\n" ); 
        }            

        push @all_sums, @sums;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FILTER FIELDS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( $args->fields )
    {
        %fields = map { $_, 1 } split /\s*,\s*/, $args->fields;

        foreach $sum ( @all_sums )
        {
            map { delete $sum->{ $_ } if not $fields{ $_ } } keys %{ $sum };
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # YAML,

    if ( defined $args->yaml )
    {
        if ( $args->yaml ) {
            &Common::File::write_yaml( $args->yaml, \@all_sums );
        } else {
            print ${ &Common::File::format_yaml( \@all_sums ) };
        }
    }
    
    # Table,
    
    if ( defined $args->table )
    {
        $table = &Common::Table::new();

        if ( $args->fields )
        {
            @fields = split /\s*,\s*/, $args->fields;
            $table->col_headers( \@fields );
        }
        else {
            @fields = keys %{ $all_sums[0] };
        }

        @values = ();

        foreach $sum ( @all_sums ) {
            push @values, [ map { $sum->{ $_ } } @fields ];
        }

        $table->values( \@values );

        &Common::Table::write_table( $table, $args->table );
    }

    &echo_bold("Finished\n\n");

    if ( not $args->void )
    {
        return wantarray ? @all_sums : \@all_sums;
    }

    return;
}

1;

__END__

# sub fetch_seq_remote
# {
#     # Niels Larsen, May 2007.

#     # Generates a Bioperl (Bio::PrimarySeq) object of a single sequence
#     # by first fetching it from NCBI with Entrez, then having Bioperl parse
#     # the arriving string. 

#     my ( $class, 
#          $id,
#          $args,          # Arguments hash - OPTIONAL
#          $msgs,          # Outgoing messages - OPTIONAL
#         ) = @_;

#     # Returns a Seq::Common object.

#     my ( $str, $fh, $entry, $p, $seq, $seqio, $orgstr, $taxon );

#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ qw ( dbtype ) ],
#         "S:0" => [ qw ( beg end reverse header fatal checkonly ) ],
#     });

#     require Common::Entrez;

#     $str = &Common::Entrez::fetch_subseq( $id, {
#         "dbtype" => $args->dbtype,
#         "beg" => $args->beg,
#         "end" => $args->end,
#     }); 

#     $fh = new IO::String( $str );

#     $entry = Bio::SeqIO->new( -fh => $fh, -format => "genbank" )->next_seq;

#     if ( $entry )
#     {
#         $p = $entry->primary_seq;

# #         if ( defined $entry->species ) {
# #             $orgstr = $entry->species->binomial;
# #         } else {
# #             $orgstr = "Unknown organism";
# #         }

# 	$taxon = $entry->species;
	
#         $seq = Bio::Seq->new
# 	    (
# 	     -seq => $p->seq,
# 	     -description => $p->description,
# 	     -display_id => $p->display_id,
# 	     -primary_id => $id,
# 	     -accession_number => $p->accession_number,
# 	     -species => {
# 		 "common_name" => $taxon->common_name || "",
# 		 "name" => $taxon->binomial || "",
# 		 "classification" => [ reverse $taxon->classification ],
# 	     },
#             -version => $p->version,
#             );
#     }

#     if ( $seq ) {
#         return $seq;
#     } else {
#         return;
#     }
# }
