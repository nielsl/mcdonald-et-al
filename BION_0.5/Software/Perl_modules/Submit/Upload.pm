package Submit::Upload;     #  -*- perl -*-

# Routines that handle uploads and import of the different types. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &process_ali
                 &process_pat
                 &process_seqs
                 &upload_file
                 &validate_seqs
                 );

use Common::Config;
use Common::Messages;

use Common::Widgets;
use Common::File;
use Common::Menus;
use Common::Types;

use Registry::Get;

use Install::Data;

use Seq::IO;
use Seq::Common;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub process_ali
{
    # Niels Larsen, January 2005.
    
    # Fetches an uploaded alignment file and processes it. A success or error 
    # message is generated, and a status hash is returned. 

    my ( $sid,       # Session id
         $args,      # Arguments hash
         $msgs,      # Outgoing message list
         ) = @_;

    # Returns a hash.

    my ( @msgs, $ali, $ali_rows, $count_str, $ali_prefix, $ft_names, $ali_dir, $info );

    @msgs = ();

    # >>>>>>>>>>>>>>>>>>>>>>>>>> IMPORT ALIGNMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ali_prefix = $args->{"out_file_path"};
    
    $ft_names = Common::Menus->datatype_features( $args->{"datatype"} )->options_names;

    &Install::Data::import_alignment(
        {
            "source" => $args->{"source"},
            "title" => $args->{"title"},
            "label" => "",
            "ifile" => $args->{"in_file_path"},
            "iformat" => $args->{"format"},
            "itype" => $args->{"datatype"},
            "ofile" => $ali_prefix,
            "tab_dir" => $args->{"out_table_dir"},
            "ft_names" => $ft_names,
            "db_name" => $sid,
            "ext_types" => [ &Common::Types::ali_to_seq( $args->{"datatype"} ) ],
        },
        \@msgs );

    $ali = &Ali::IO::connect_pdl( $ali_prefix );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> MAKE RECEIPT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $ali and $ali->max_row > 0 )
    {
        # We get here if there only if there are at least two sequences,
    
        $ali_rows = $ali->max_row + 1;

        $info->{"count_str"} = "$ali_rows aligned sequences";
        $info->{"count"} = $ali_rows;

        $info->{"success"} = 1;
    }
    else
    {
        if ( $ali and $ali->max_row == 0 ) {
            @msgs = [ "Error", "The upload has only one sequence, where an alignment should have at least two." ];
        } else {
            @msgs = [ "Error", "The upload was empty. Please check the file name and content." ];
        }

        &Common::File::delete_file_if_exists( "$ali_prefix.pdl" );
        &Common::File::delete_file_if_exists( "$ali_prefix.info" );

        $info->{"success"} = 0;
    }

    undef $ali;

    push @{ $msgs }, @msgs if @msgs;

    return $info;
}

sub process_pat
{
    # Niels Larsen, December 2006.

    # Fetches an uploaded pattern file and processes it. A success or error 
    # message is generated, and a status hash is returned with counts. 

    my ( $sid,       # Session id
         $args,      # Arguments hash
         $msgs,      # Messages hash 
         ) = @_;

    # Returns a hash.

    my ( @msgs, $content, $in_file, $info );
    
    @msgs = ();
    $info = {};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read all into memory, as string,

    {
        local $/;

        $in_file = $args->{"in_file_path"};

        $/ = &Common::File::get_record_separator( $in_file );

        $content = ${ &Common::File::read_file( $in_file ) };
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS + MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Simply write the data to its proper place and make messages,

    if ( $content )
    {
        &Common::File::write_file( $args->{"out_file_path"}, $content );

        $info->{"count"} = 1;
        $info->{"success"} = 1;
    }
    else
    {
        @msgs = [ "Error", "The upload was empty. Please check the file name and content." ];
        $info->{"success"} = 0;
    }

    push @{ $msgs }, @msgs if @msgs;

    return $info;
}

sub process_seqs
{
    # Niels Larsen, November 2005.

    # Fetches an uploaded sequence file and processes it. A success or error 
    # message is generated, and a status hash is returned with counts. 

    my ( $sid,       # Session id
         $args,      # Args hash
         $msgs,      # Messages hash
         ) = @_;

    # Returns a hash.

    my ( @msgs, $in_file, $info, $datatype, $string, $entries, 
         $seq_count, $module );
    
    @msgs = ();
    $info = {};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> READ DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Read all into memory, as list of sequence objects,

    {
        local $/;

        $datatype = $args->{"datatype"};
        $in_file = $args->{"in_file_path"};

        $module = &Common::Types::type_to_mol( $datatype ) . "::Seq";
        
        $/ = &Common::File::get_record_separator( $in_file );
        
        $entries = &Seq::IO::read_seqs_file( $in_file );
        $entries = [ map { bless $_, "Seq::Common" } @{ $entries } ];
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> VALIDATE ENTRIES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Skips empty entries, complains about sequences with more than 10% bad
    # characters in them, etc,

    $entries = &Submit::Upload::validate_seqs( $entries, \@msgs );

    if ( @msgs and grep { $_->[0] =~ /error/i } @msgs )
    {
        push @{ $msgs }, @msgs;
        $info->{"success"} = 0;
        return $info;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS + MESSAGES <<<<<<<<<<<<<<<<<<<<<<<<<<

    # We get here if there only if there are at least one ok sequence. Below
    # write one sequence to file at a time and return success message.

    if ( $entries and @{ $entries } )
    {
        $seq_count = scalar @{ $entries };

        &Seq::IO::write_seqs_fasta( $args->{"out_file_path"}, $entries );

        if ( $seq_count == 1 ) {
            $info->{"count_str"} = "$seq_count entry";
        } else {
            $info->{"count_str"} = "$seq_count entries";
        }

        $info->{"count"} = $seq_count;
        $info->{"success"} = 1;
    }
    else
    {
        @msgs = [ "Error", "The upload was empty. Please check the file name and content." ];
        $info->{"success"} = 0;
    }

    push @{ $msgs }, @msgs if @msgs;

    return $info;
}

sub upload_file
{
    # Niels Larsen, November 2005.

    # Does the upload work. Given a CGI.pm handle, it copies line by line from
    # the file handle ($cgi->param('upload_file_name')) to a temporary file with 
    # a unique name. If successful a file path to the upload is returned and it 
    # is up to other routines to process it further. If not successful nothing
    # is returned and error messages are set as the third argument - so check
    # for this $errors being non-empty after calling this routine.
    
    my ( $sid,      # Session id
         $args,     # Form values hash 
         $msgs,     # Message list
         ) = @_;

    # Returns an integer or nothing. 

    my ( $ofile_name, $ofile_path, $count, $o_fh, $line, $i_fh, $key );

    # Check that form hash is ok,

    foreach $key ( qw ( user_file_name user_file_handle out_file_name out_file_path datatype format title coltext ) )
    {
        if ( not $args->{ $key } ) {
            &error( qq (Key missing in form hash -> "$key") );
        }
    }
    
    $ofile_name = $args->{"out_file_name"};
    $ofile_path = $args->{"out_file_path"};

    $i_fh = $args->{"user_file_handle"};
    $o_fh = &Common::File::get_write_handle( $ofile_path );

    $count = 0;

    # Save data into session directory. The data can either be a 
    # file handle to a CGI.pm invisible temporary file, or a string,

    if ( ref $i_fh )
    {
        $line = <$i_fh>;

        if ( defined $line )
        {
            if ( not $o_fh->print( $line ) )
            {
                &Common::File::delete_file( $ofile_path );
                push @{ $msgs }, [ "Error", qq (Could not print from upload filehandle to "$ofile_name".) ];
                return;
            }

            while ( defined ( $line = <$i_fh> ) )
            {
                if ( not $o_fh->print( $line ) )
                {
                    &Common::File::delete_file( $ofile_path );
                    push @{ $msgs }, [ "Error", qq (Could not print from upload filehandle to "$ofile_name".) ];
                    return;
                }

                $count += 1;
            }
        }
        else {
            &Common::File::delete_file( $ofile_path );
            push @{ $msgs }, [ "Error", qq (Wrong looking file name -> "$ofile_name".) ];
            return;
        }
    }
    elsif ( not $o_fh->print( $i_fh ) )
    {
        push @{ $msgs }, [ "Error", qq (Could not get upload filehandle.) ];
        return;
    }
    
    $o_fh->close;

    if ( not -s $ofile_path )
    {
        push @{ $msgs }, [ "Error", qq (Empty file upload. Does the file "$ofile_name"  exist on your machine, )
                                  . qq (or is it empty?) ];
    }

    return $count;
}

sub validate_seqs
{
    # Niels Larsen, November 2005.

    # Creates a warning if more than 10% of the characters in a given sequence
    # are invalid. Resets missing headers to "None" and skips entries with no 
    # sequence. Returns a list of ok entries. 

    my ( $seqs,          # List of sequence objects
         $msgs,          # List of errors and/or warnings
         ) = @_;

    # Returns a list.

    my ( $obj, $id, $seq, $class, $valid_chars, $mask, $i, @seqs, $pct, $tot_count,
         $bad_pct, $warnings );

    $i = 1;

    foreach $obj ( @{ $seqs } )
    {
        $id = $obj->id;
        $seq = $obj->seq;

        # Set name to "None" if missing,

        if ( not defined $id or 
             length $id == 0 or 
             $id eq "None" )
        {
            $obj->id( "" );
            $id = $obj->id;
            
            push @{ $msgs }, [ "Warning", qq (Entry $i has no fasta header.) ];
        }

        # Ignore entry if sequence missing,

        if ( defined $seq and $obj->seq_len > 0 )
        {
            push @seqs, $obj;

            # Create warnings if > 10% invalid characters,
            
            $bad_pct = &Seq::Common::invalid_pct( $seq );

            if ( $bad_pct > 10 )
            {
                $bad_pct = sprintf "%5.1f", $bad_pct;
                push @{ $msgs }, [ "Warning", qq (Entry $i (named "$id") has $bad_pct% invalid characters) ];
            }
        } 
        else {
            push @{ $msgs }, [ "Warning", qq (Entry $i (named "$id") has no sequence, <strong>ignored</strong>) ];
        }

        $i += 1;
    }

    $warnings = scalar @{ $msgs };

    if ( $warnings > 10 ) 
    {
        $tot_count = scalar @{ $seqs };

        splice @{ $msgs }, 10;

        push @{ $msgs }, [ "Error", qq (There were $warnings warnings in $tot_count entries. This )
                         . qq (can happen if a wrong type is chosen, or perhaps there are alignment )
                         . qq (gaps in the file, please check. No entries were uploaded.) ];

        @seqs = ();
    }
    elsif ( not @seqs )
    {
        push @{ $msgs }, [ "Error", qq (There were no valid entries in the upload. Please )
                          . qq (please inspect the file.) ];
    }

    return wantarray ? @seqs : \@seqs;
}

1;

__END__
    

1;
