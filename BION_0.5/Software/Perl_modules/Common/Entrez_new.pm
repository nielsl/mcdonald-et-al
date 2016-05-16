package Common::Entrez_new;                # -*- perl -*-

# Module with general utility functions that can be used in any context.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

use LWP::Simple;
use LWP::UserAgent;
use Boulder::XML;
use HTTP::Request::Common;
use XML::Simple;

use Common::Config;
use Common::Messages;

use Registry::Args;
use Common::Names;
use Common::Types;

@EXPORT_OK = qw (
                 &accs_to_gis
                 &accs_to_seq_summaries
                 &accs_to_summaries
                 &efetch_ids
                 &efetch_records
                 &esummary
                 &edit_id_underscores
                 &fetch_seqs_file
                 &fetch_subseq
                 &fetch_summaries
                 &gis_to_accs
                 &set_db
                 &set_rettype
                 &taxids_to_summaries
                 &uniqify
                 &xml_to_stream
                 &wait_if_needed
                 );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub accs_to_gis
{
    # Niels Larsen, November 2007.

    # Returns a list of GI numbers from NCBI that corresponds to 
    # the given list of accession numbers and data type.

    my ( $accs,           # Accession number list
         $args,           # Arguments hash - OPTIONAL
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( @gis );

    $args = &Registry::Args::check(
        $args, {
            "S:0" => [ qw ( db rettype retmode retmax trymax waitmax ) ],
        });

    @gis = &Common::Entrez_new::efetch_ids( $accs, {
        "db" => $args->db || "sequences",
        "rettype" => $args->rettype || "gi",
        "retmode" => $args->retmode || "asn.1",    # The only format available - bug submitted 
        "retmax" => $args->retmax || 200,
        "trymax" => $args->trymax || 3,
        "waitmax" => $args->waitmax || 30,
    }, $msgs );

    return wantarray ? @gis : \@gis;
}

sub accs_to_seq_summaries
{
    my ( $accs,
         $type,       # Data type like "rna_seq"
         $msgs,
        ) = @_;

    return &Common::Entrez_new::accs_to_summaries(
        $accs,
        {
            "db" => "sequences",
            "dbtype" => $type,

        }, $msgs );
}

sub accs_to_summaries
{
    # Niels Larsen, January 2007.

    # Gets summary information for each accession number in a given list,
    # using the NCBI eutils service. 

    my ( $accs,           # Accession number list
         $args,
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( @stones, $acc, @taxids, %lookup, %index, $field, $id, $empty, @info, 
	 $stone, @edict, $fields );

    $args //= {};

    $args = &Registry::Args::check(
        $args, {
            "S:1" => [ qw ( db dbtype ) ],
            "S:0" => [ qw ( fields rettype retmode retmax trymax waitmax ) ],
        });

    @edict = (
	      [ "Caption" => 0 ],
	      [ "Title" => 1 ],
	      [ "Extra" => 2 ],
	      [ "Gi" => 3 ],
	      [ "CreateDate" => 4 ],
	      [ "UpdateDate" => 5 ],
	      [ "Flags" => 6 ],
	      [ "TaxId" => 7 ],
	      [ "Length" => 8 ],
	      [ "Status" => 9 ],
	      [ "ReplacedBy" => 10 ],
	      [ "Comment" => 11 ],
	      );

    if ( $args->fields ) {
	$fields = $args->fields;
    } else {
	$fields = [ map { $_->[0] } @edict ];
    }

    %index = map { @{ $_ } } @edict;

    foreach $field ( @{ $fields } )
    {
        if ( not exists $index{ $field } ) {
            &Common::Messages::error( qq (Wrong looking EUtils summary field -> "$field") );
        }
    }

    @stones = &Common::Entrez_new::fetch_summaries( $accs, {
        "db" => $args->db,
        "dbtype" => $args->dbtype,
        "rettype" => $args->rettype,
        "retmode" => $args->retmode, 
        "retmax" => $args->retmax,
        "trymax" => $args->trymax,
        "waitmax" => $args->waitmax || 60,
        "idtype" => "acc",
        "oformat" => "stream",  
    }, $msgs );

    foreach $stone ( @stones )
    {
        $id =  $stone->Id->name;

        foreach $field ( @{ $fields } )
        {
            push @{ $lookup{ $id } }, $stone->get("Item", $index{ $field } )->name || "";
        }
    }

    $empty = [ "" x scalar @{ $fields } ];

    foreach $acc ( @{ $accs } )
    {
        if ( exists $lookup{ $acc } ) {
            push @info, $lookup{ $acc };
        } else {
            push @info, $empty;
        }
    }

    return wantarray ? @info : \@info;
}

sub efetch_ids
{
    # Niels Larsen, January 2007.

    # Uses NCBI eutils to return a list of ids of a given type, given an
    # input list of ids of another type.

    my ( $ids,         # ID list
         $args,        # Arguments
         $msgs,        # Outgoing messages
        ) = @_;

    # Returns a list. 

    my ( $ret_type, $elem, $try, $try_max, $ua, $req, $res, $str, $email,
         $i_ids, $db, $idstr, $url, $ndx, @uniq_ids, $base_url, $wait_max,
         $ret_mode, $id, $errstr, @url_ids, @ids_ncbi, %ids_ncbi, @output, 
         $o_ids, $ret_max, @ids, $j, $dir, $tmp_dir, $tmp_file, $epoch );

    $args = &Registry::Args::check(
        $args, {
            "S:2" => [ qw ( db rettype retmode retmax trymax waitmax ) ],
        });

    $email = &Common::Config::get_contacts()->{"e_mail"};
    $email =~ s/\@/\\@/;

    $base_url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?";
    $base_url .= "tool=bion&email=$email";

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> UNIQIFY AND WARN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # NCBI bug (reported): underscores should be removed from PDB ids, but 
    # not from all other ids, and this is trying to do that,

    @uniq_ids = &Common::Entrez_new::uniqify( $ids );
    @uniq_ids = &Common::Entrez_new::edit_id_underscores( \@uniq_ids );

    $ret_type = $args->rettype;
    $ret_mode = $args->retmode;
    $try_max = $args->trymax;
    $wait_max = $args->waitmax;
    $ret_max = $args->retmax;
    $db = $args->db;

    $epoch = 0;

    for ( $ndx = 0; $ndx <= $#uniq_ids; $ndx += $ret_max )
    {
        @ids = @uniq_ids[ $ndx .. &Common::Util::min( $ndx + $ret_max - 1, $#uniq_ids ) ];
        @url_ids = ();

        $try = 1;

        $url = $base_url ."&rettype=$ret_type&db=$db&id=". (join ",", @ids) ."&retmode=$ret_mode";
        
        while ( $try <= $try_max )
        {
            $epoch = &Common::Entrez_new::wait_if_needed( $epoch );

            $ua = LWP::UserAgent->new;
            $ua->timeout( $wait_max );

            $res = $ua->get( $url );
            
            if ( $res->is_success and defined ( $str = $res->content ) )
            {
                if ( $str =~ /Error:/ )
                {
                    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ERROR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                    
                    if ( ref $msgs ) {
                        push @{ $msgs }, [ "NCBI ENTREZ ERROR", $str ];
                    } else {
                        &Common::Messages::error( $str, "NCBI ENTREZ ERROR" );
                    }
                }
                elsif ( $ret_type eq "acc" or $ret_type eq "gi" )
                {
                    # >>>>>>>>>>>>>>>>>>>> ACCESSION NUMBERS WANTED <<<<<<<<<<<<<<<<<<<<
                    
                    # Here though only text seems to be possible,
                    
                    $str .= "_END_";
                    
                    @ids_ncbi = split "\n", $str;
                    pop @ids_ncbi;
                }
                else {
                    &Common::Messages::error( qq (Wrong looking output type -> "$ret_type") );
                }
                
                # >>>>>>>>>>>>>>>>>>>>>>>>> MISSING DATA CHECK <<<<<<<<<<<<<<<<<<<<<<<<<

                if ( scalar @ids_ncbi == scalar @ids )
                {
                    # Checks which are missing. Frequently one or more ids are not found,
                    # even though the ids come from NCBI via eutils - there are many "dead
                    # end ids" like that.

                    for ( $j = 0; $j < scalar @ids; $j++ )
                    {
                        $id = $ids[$j];
                        
                        if ( $ids_ncbi[$j] ne "" ) {
                            push @output, $ids_ncbi[$j];
                        } else {
                            push @{ $msgs }, [ "Error", qq (No "$ret_type"-ID for -> "$id") ];
                        }
                    }
                }
                else
                {
                    # We get here if the retrieval or parsing went wrong, so the number
                    # of returned ids are different from the number submitted,

                    $i_ids = scalar @ids;
                    $o_ids = scalar @ids_ncbi;

                    &dump( \@ids_ncbi );
                    &Common::Messages::error( qq ($i_ids ID\'s submitted, but NCBI returned $o_ids) );
                }
                
                last;
            }

            $try += 1;
        }

        if ( $try > $try_max ) {
            &Common::Messages::error( qq (
No ids returned from NCBI, tried $try times, each waiting for $wait_max seconds.
It is likely due to downtime at NCBI, or a network disconnect somewhere between 
you and them. We recommend re-submitting some time later.
) );
        }
    }
        
    return wantarray ? @output : \@output;    
}

sub efetch_records
{
    # Niels Larsen, January 2007.

    # 
    my ( $ids,
         $args,
         $msgs,
        ) = @_;

    my ( $email, $base_url, $url, $out_file, $out_str, $try, $ua, $req, $res, 
         $tmp_dir, $tmp_file, $dir, @uniq_ids, $id, $ret_max, $ndx, @ids, 
         @output, $epoch, $wait_max, $try_max );
    
    $args = &Registry::Args::check(
        $args, {
            "S:2" => [ qw ( db rettype retmode retmax trymax waitmax ) ],
            "S:0" => [ qw ( tmpdir outfile clobber seq_start seq_stop ) ],
        });

    $email = &Common::Config::get_contacts()->{"e_mail"};
    $email =~ s/\@/\\@/;

    $base_url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?";
    $base_url .= "tool=bion&email=$email";

    $out_file = $args->outfile;
        
    if ( not $args->clobber and defined $out_file and -e $out_file ) {
        &Common::Messages::error( qq (Output file exists -> "$out_file") );
    }

   # >>>>>>>>>>>>>>>>>>>>>>>>>>> UNIQIFY AND WARN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # NCBI bug (reported): underscores should be removed from PDB ids, but 
    # not from all other ids, and this is trying to do that,

    @uniq_ids = &Common::Entrez_new::uniqify( $ids );
    @uniq_ids = &Common::Entrez_new::edit_id_underscores( \@uniq_ids );

    $tmp_dir = $args->tmpdir;
    $ret_max = $args->retmax;
    $wait_max = $args->waitmax;
    $try_max = $args->trymax;

    $out_str = "";
    $epoch = 0;

    for ( $ndx = 0; $ndx <= $#uniq_ids; $ndx += $ret_max )
    {
        @ids = @uniq_ids[ $ndx .. &Common::Util::min( $ndx + $ret_max - 1, $#uniq_ids ) ];

        $url = $base_url ."&rettype=". $args->rettype . "&db=". $args->db; 
        $url .= "&id=". (join ",", @ids) . "&retmode=". $args->retmode;

        $try = 1;
        
        while ( $try <= $args->trymax )
        {
            $epoch = &Common::Entrez_new::wait_if_needed( $epoch );

            $ua = LWP::UserAgent->new;
            $ua->timeout( $wait_max );
            
            $req = HTTP::Request->new( GET => $url );

            if ( $out_file )
            {
                $dir = &File::Basename::dirname( $out_file );
            
                if ( -d $dir )
                {
                    if ( $tmp_dir ) {
                        &Common::File::create_dir_if_not_exists( $tmp_dir );
                    } else {
                        &Common::Messages::error( qq (No scratch directory given) );
                    }
                    
                    $tmp_file = "$tmp_dir/Entrez_download.$$";
                    
                    $res = $ua->request( $req, $tmp_file );
                    
                    if ( $res->is_success )
                    {
                        &Common::File::append_files( $out_file, $tmp_file );
                        &Common::File::delete_file( $tmp_file );

                        $out_str = $out_file;
                        last;
                    } 
                    else {
                        $try += 1;
                        &Common::File::delete_file_if_exists( $tmp_file );
                    }
                }
                else {
                    &Common::Messages::error( qq (Directory does not exist -> "$dir") );
                }
            }
            else 
            {
                $res = $ua->request( $req );

                if ( $res->content )
                {
                    $out_str .= $res->content;
                    last;
                }
                else {
                    $try += 1;
                }
            }
        }

        if ( $try > $try_max ) {
            &Common::Messages::error( qq (
No records returned from NCBI, tried $try times, each waiting for $wait_max seconds.
It is likely due to downtime at NCBI, or a network disconnect somewhere between 
you and them. We recommend re-submitting some time later.
) );
        }
    }

    return $out_str;
}

sub esummary
{
    # Niels Larsen, July 2007. 

    # Routine that creates an Entrez esummary url and gets back the response.
    # Arguments are those required by Entrez, and must be set by wrap-functions
    # that use this routine as their "driver". The routine checks for input 
    # duplicate ids, splits long lists in pieces, inserts 3 seconds between
    # repeated requests (NCBI wants that) and has primitive checks for error
    # and inconsistency in the output. 

    my ( $ids,               # ID list
         $args,              # Argument hash
         $msgs,              # Outgoing messages - OPTIONAL
        ) = @_;

    # Returns a list.

    my ( $db, $tries, $try, @ids, $url, $ua, $ndx, $req, $res, $xml, @xml,
         $email, %out_ids, $i, $j, @summaries, $format, $epoch, @errors, $idstr,
         $timeout, $xmlstr, $item );

    $args = &Registry::Args::check(
        $args, {
            "S:1" => [ qw ( db tries timeout ) ],
        });

    # >>>>>>>>>>>>>>>>>>>>>>>>> FETCH FROM NCBI <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    @ids = &Common::Entrez_new::uniqify( $ids, $msgs );

    $db = $args->db;
    $tries = $args->tries;
    $timeout = $args->timeout;

    $email = &Common::Config::get_contacts()->{"e_mail"};
    $email =~ s/\@/\\@/;

    $url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?";
    $url .= "tool=bion&email=$email";
    $url .= "&db=$db&id=". (join ",", @ids) ."&retmode=xml";

    $try = 1;
    $epoch = 0;
    
    while ( $try <= $tries )
    {
        $epoch = &Common::Entrez_new::wait_if_needed( $epoch );
        
        $ua = LWP::UserAgent->new;
        $ua->timeout( $timeout );

        $res = $ua->get( $url );

        if ( $res->is_success )
        {
            $xmlstr = $res->content;
            
            if ( @errors = ( $xmlstr =~ /<ERROR>([^<]+)<\/ERROR>/isg ) or 
                 @errors = ( $xmlstr =~ /Error: ([^\n]+)/isg ) )
            {
                map { push @{ $msgs }, [ "Error", $_ ] } @errors;
            }

            last;
        }

        $try += 1;
    }
    
    if ( $try > $tries )
    {
        &Common::Messages::error( qq (
No summaries returned from NCBI, tried $tries times, each waiting for $timeout 
seconds. It is likely due to downtime at NCBI, or a network disconnect somewhere 
between you and them. We recommend re-submitting some time later. 
) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PARSE XML STRING <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # First repair if needed. Sometimes the xml output is truncated .. so first
    # the xml string is checked for completion, repaired so it can be parsed, 
    # and then below it is parsed,

    if ( $xmlstr !~ /<\/eSummaryResult>\s+$/s )
    {
        @xml = split "\n\n", $xmlstr;
        $xmlstr = join "\n\n", @xml[ 0 .. $#xml-1 ];
        
        $xmlstr .= "\n\n</eSummaryResult>\n";
    }

    # Parse XML into a list of summary objects,

    $xml = &XML::Simple::XMLin( $xmlstr );

    if ( ref $xml->{"DocSum"} eq "HASH" ) {
        $xml->{"DocSum"} = [ $xml->{"DocSum"} ];
    }

    foreach $item ( @{ $xml->{"DocSum"} } )
    {
        push @summaries, bless { map { $_->{"Name"} => $_->{"content"} } @{ $item->{"Item"} } };
    }


    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CHECK AND REPEAT <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    $i = scalar @ids;
    $j = scalar @summaries + scalar @errors;

    if ( $i > $j )
    {
        %out_ids = map { $_, 1 } map { $_->Gi } @summaries;
        @ids = grep { not exists $out_ids{ $_ } } @ids;
            
        if ( $args->tries > 1 )
        {
            push @summaries, &Common::Entrez_new::esummary(
                \@ids,
                {
                    "db" => $args->db,
                    "tries" => $args->tries - 1,
                    "timeout" => $args->timeout,
                }, $msgs );
        }
        else
        {
            $idstr = join ", ", &Common::Util::diff_lists( \@ids, [ map { $_->Id } @summaries ] );
            &Common::Messages::error( qq (
Could only retrieve $j summary/summaries from NCBI, where there should really be $i. 
The problem id(s) is/are $idstr. 
) );
        }
    }
    
    return wantarray ? @summaries : \@summaries;
}

sub edit_id_underscores
{
    my ( $ids,
        ) = @_;

    my ( $id, @ids );

    foreach $id ( @{ $ids } )
    { 
        if ( $id =~ /([A-Z0-9]+)_([A-Z0-9]{1,2})(\.\d+)?$/ ) {
            push @ids, "$1$2";
        } else {
            push @ids, $id;
        }
    }

    return wantarray ? @ids : \@ids;
}

sub fetch_seqs_file
{
    # Niels Larsen, July 2007.

    # Given a list of databank entry ids that NCBI Entrez understands, 
    # copies the corresponding entries to the given output file. 

    my ( $ids,        # List of ids accepted by Entrez 
         $args,       # Arguments
         $msgs,
         ) = @_;

    # Returns integer.

    my ( $output );
    
    $args = &Registry::Args::check(
        $args, {
            "S:1" => [ qw ( dbtype outfile ) ],
        });

    $output = &Common::Entrez_new::efetch_records( $ids, {
        "db" => &Common::Entrez_new::set_db( $args->dbtype ),
        "rettype" => &Common::Entrez_new::set_rettype( $args->dbtype ),
        "retmode" => "text",
        "retmax" => 50,
        "trymax" => 3,
        "waitmax" => 30,
        "outfile" => $args->outfile,
        "clobber" => 0,
        "tmpdir" => $Common::Config::tmp_dir,
    }, $msgs );

    return $output;     # File name path
}

sub fetch_subseq
{
    # Niels Larsen, July 2007.

    # Returns a string with a databank entry from NCBI; "beg" and "end" 
    # can be given (0-based numbering). 

    my ( $id,         # List of ids accepted by Entrez 
         $args,       # Arguments
         $msgs,
         ) = @_;

    # Returns integer.

    my ( $output, $conf );
    
    $args = &Registry::Args::check(
        $args, {
            "S:1" => [ qw ( dbtype ) ],
            "S:0" => [ qw ( beg end ) ],
        });

    $conf = {
        "db" => &Common::Entrez_new::set_db( $args->dbtype ),
        "rettype" => &Common::Entrez_new::set_rettype( $args->dbtype ),
        "retmode" => "text",
        "retmax" => 1,
        "trymax" => 3,
        "waitmax" => 20,
    };

    if ( defined $args->beg or defined $args->end )
    {
        if ( defined $args->beg ) {
            $conf->{"seq_start"} = $args->beg + 1;
        } else {
            $conf->{"seq_start"} = 1;
        }

        if ( defined $args->end ) {
            $conf->{"seq_stop"} = $args->end + 1;
        } else {
            $conf->{"seq_stop"} = 999_999_999;    # NCBI bug, submitted
        }
    }

    $output = &Common::Entrez_new::efetch_records( [ $id ], $conf, $msgs );

    return $output;    # Data string
}

sub fetch_summaries
{
    # Niels Larsen, October 2010.

    # Given a list of databank ids that NCBI Entrez understands, fetches 
    # and returns a list of summary reports in XML format.

    my ( $ids,        # List of ids accepted by Entrez 
         $args,       # Arguments
         $msgs,       # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( $defs, $type, @output, %gi_to_id, @uniq_ids, %uniq_ids, @ids, 
         $format, %valid, $xml, $ndx, $i, $j, $obj, @gis, @list, $ret_max, $epoch, 
        );
    
    $defs = {
        "dbtype" => "dna_seq",
	"ofields" => undef,
        "batch" => 1000,
        "delay" => 0,
        "tries" => 5,
        "timeout" => 5,
    };

    $args = &Registry::Args::create( $args, $defs );

    $ret_max = $args->batch;

#     # >>>>>>>>>>>>>>>>>>>>> CONVERT TO GIS IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<<<

#     # The esummary.fcgi script at NCBI only understands gi, mmdb (structure) 
#     # and tax ids. So anything else has to be translated, and translated back
#     # again below,

#     %valid = map { $_, 1 } qw ( gi mmdb tax acc );

#     if ( $valid{ $args->idtype } )
#     {
#         @uniq_ids = &Common::Util::uniqify( $ids );

#         if ( $args->idtype eq "acc" )
#         {
#             @gis = &Common::Entrez_new::accs_to_gis( \@uniq_ids,
#                                                  {
#                                                      "db" => $args->db,
#                                                      "rettype" => $args->rettype,
#                                                      "retmode" => $args->retmode, 
#                                                      "retmax" => $args->retmax,
#                                                      "trymax" => $args->trymax,
#                                                      "waitmax" => $args->waitmax,
#                                                  }, $msgs );

#             if ( ($i = scalar @gis) != ($j = scalar @uniq_ids) ) {
#                 &Common::Messages::error( qq (Number of accession numbers sent is $j, but number of received GI's is $i) );
#             }
#         }

#         if ( @gis )
#         {
#             for ( $i = 0; $i <= $#gis; $i++ )
#             {
#                 $gi_to_id{ $gis[$i] } = $uniq_ids[$i];
#             }

#             @uniq_ids = @gis;
#         }
#     }
#     else {
#         &Common::Messages::error( qq (Wrong looking ID type -> "$type") );
#     }

    @uniq_ids = @{ $ids };

    # >>>>>>>>>>>>>>>>>>>>>>>>> GET SUMMARY INFO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $epoch = 0;

    for ( $ndx = 0; $ndx <= $#uniq_ids; $ndx += $ret_max )
    {
        $epoch = &Common::Entrez_new::wait_if_needed( $epoch );

        @ids = @uniq_ids[ $ndx .. &Common::Util::min( $ndx + $ret_max - 1, $#uniq_ids ) ];

        @list = &Common::Entrez_new::esummary( \@ids, {
            "db" => &Common::Entrez_new::set_db( $args->dbtype ),
            "tries" => 3,
            "timeout" => 90,
        }, $msgs );

        push @output, @list;
    }

#     # Restore the original ids,

#     if ( @gis )
#     {
#         if ( $args->oformat eq "stream" ) 
#         {
#             foreach $obj ( @output ) {
#                 $obj->replace( "Id" => $gi_to_id{ $obj->Id } );
#             } 
#         }
#     }

    return wantarray ? @output : \@output;
}

sub gis_to_accs
{
    # Niels Larsen, January 2007.

    # Returns a unique list of sequence accession numbers from NCBI that 
    # corresponds to the given list of GI numbers. 

    my ( $gis,            # Gene ID list
         $msgs,           # Outgoing messages - OPTIONAL
         ) = @_;

    # Returns a list.

    my ( @accs );

    @accs = &Common::Entrez_new::efetch_ids( $gis, {
        "db" => "sequences",
        "rettype" => "acc",
        "retmode" => "text", 
        "retmax" => 500,
        "trymax" => 3,
        "waitmax" => 30,
    }, $msgs );

    return wantarray ? @accs : \@accs;
}

sub set_db
{
    # Niels Larsen, July 2007.
    
    # Returns the NCBI Entrez database name that corresponds to a given 
    # datatype.

    my ( $type,       # BION datatype
        ) = @_;

    # Returns a string.

    my ( $db );

    if ( &Common::Types::is_dna_or_rna( $type ) ) {
        $db = "nucleotide";
    } elsif ( &Common::Types::is_protein( $type ) ) {
        $db = "protein";
    } elsif ( &Common::Types::is_taxonomy( $type ) ) {
        $db = "taxonomy";
    } else {
        &Common::Messages::error( qq (Wrong looking db type -> "$type") );
    }

    return $db;
}

sub set_rettype
{
    # Niels Larsen, July 2007.
    
    # Returns the NCBI Entrez return type that corresponds to a given 
    # datatype.

    my ( $type,           # BION datatype 
        ) = @_;

    # Returns a string.

    my ( $ret );

    if ( &Common::Types::is_dna_or_rna( $type ) ) {
        $ret = "gb";
    } elsif ( &Common::Types::is_protein( $type ) ) {
        $ret = "gp";
    } else {
        &Common::Messages::error( qq (Wrong looking type -> "$type") );
    }

    return $ret;
}

sub taxids_to_summaries
{
    my ( $ids,
         $msgs,
        ) = @_;

    return &Common::Entrez_new::fetch_summaries( $ids, {
            "db" => "taxonomy",
            "dbtype" => "orgs_tax",
            "idtype" => "tax",
            "oformat" => "stream",
        }, $msgs );
}

sub uniqify
{
    my ( $ids,
         $msgs,
        ) = @_;

    my ( @ids, $dups, $dupstr );

    @ids= &Common::Util::uniqify( $ids );

    if ( defined $msgs and $#ids < $#{ $ids } )
    {
        $dups = $#{ $ids } - $#ids;
        $dupstr = ( $dups > 1 ? "$dups duplicates" : "$dups duplicate" );

        push @{ $msgs }, [ "Warning", qq ($dupstr in given accession number list.) ];
    }

    return wantarray ? @ids : \@ids;
}

sub xml_to_stream
{
    my ( $sref,
        ) = @_;

    my ( @output, $stream, $stone );

    @output = ();

    if ( not open STR, "<", $sref ) {
        &Common::Messages::error( qq (Could not read-open string) );
    }
    
    $stream = Boulder::XML->new( -in => *STR, -tag => "DocSum" );

    while ( $stone = $stream->get )
    {
        push @output, $stone;
    }
    
    close STR;
    $stream->done;

    return wantarray ? @output : \@output;
}

sub wait_if_needed
{
    # Niels Larsen, October 2010.

    # Wait until at least n (default 5) seconds have passed since last request,

    my ( $then,
         $delay,
        ) = @_;

    my ( $now );

    $then //= 0;
    $delay //= 5;

    $now = &Common::Util::time_string_to_epoch();
    
    if ( ($now - $then) < $delay )
    {
        sleep $delay - ( $now - $then );
    }
    
    return $now;
}

1;

__END__

# sub accs_to_titles
# {
#     # Niels Larsen, January 2007.

#     # TODO: may swamp memory

#     my ( $accs,           # Accession number list
#          $msgs,           # Outgoing messages - OPTIONAL
#          ) = @_;

#     # Returns a list.

#     my ( @stones, @titles, $acc, %lookup );

#     @stones = &Common::Entrez_new::fetch_summaries( $accs, {
#         "dbtype" => "rna_seq",
#         "idtype" => "acc",
#         "oformat" => "stream",  
#     }, $msgs );

#     %lookup = map { $_->Id->name, $_->get( "Item", 1 )->name || "" } @stones;

#     foreach $acc ( @{ $accs } )
#     {
#         if ( exists $lookup{ $acc } ) {
#             push @titles, $lookup{ $acc };
#         } else {
#             push @titles, "";
#         }
#     }

#     return wantarray ? @titles : \@titles;
# }



# Do not delete, belongs to efetch_ids

#                 elsif ( $ret_type =~ /^seqid$/ )
#                 {
#                     # >>>>>>>>>>>>>>>>>>>>>>>>>>> GIS WANTED <<<<<<<<<<<<<<<<<<<<<<<<<<<
                    
#                     # Can only get ASN1 format no matter what retmode is set to (bug
#                     # submitted). So here we try fish them out from the ASN1 output,
#                     # WHAT A MESS,
                    
#                     foreach $elem ( split "\n\n", $str )
#                     {
#                         if ( $elem =~ /accession\s+\"([^\"]+)\"[\s,]+version\s+(\d+).+Seq-id ::= [a-z]+ (\d+)/s )
#                         {
#                             if ( not defined $1 or not defined $2 ) {
#                                 &dump( $elem );
#                             }

#                             $ids_ncbi{ "$1.$2" } = $3;
#                         }
#                         elsif ( $elem =~ /(?:mol|name)\s+\"([^\"]+)\".+Seq-id ::= [a-z]+ (\d+)/s )
#                         {
#                             if ( not defined $1 or not defined $2 ) {
#                                 &dump( $elem );
#                                 &dump( $1 );
#                                 &dump( $2 );
#                             }

#                             $ids_ncbi{ $1 } = $2;
#                         }
#                         else {
#                             &Common::Messages::error( qq (Wrong looking Entrez output -> "$elem") );
#                         }
#                     }                            
# # 'Seq-id ::= pdb {
# #   mol "2FFH" ,
# #   chain 65 }
# # Seq-id ::= gi 5822474';
                    
#                     if ( %ids_ncbi )
#                     {
#                         foreach $id ( @ids )
#                         {
#                             $id =~ s/_[A-Z0-9]{1,2}$//;
                            
#                             if ( exists $ids_ncbi{ $id } ) {
#                                 push @ids_ncbi, $ids_ncbi{ $id };
#                             } else {
#                                 push @ids_ncbi, "";
#                             }
#                         }
#                     }
#                     else {
#                         &Common::Messages::error( qq (No output from NCBI) );
#                     }
#                 }
