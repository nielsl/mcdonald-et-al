package Seq::Match;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Routines that match sequences by similarity. UNFINISHED
# TODO move routines from Seq::Run and make them callable through
# match subroutine.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;
use List::Util;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &ann_hash_local
                 &match
                 &match_args
                 &match_single
                 &write_ann_table_local
                 &write_ann_table_ncbi
);

use Common::Config;
use Common::Messages;

use Common::File;
use Common::OS;
use Common::Types;
use Common::Entrez_new;

use Registry::Paths;
use Registry::Args;

use Seq::Args;
use Seq::Run;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOAD <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub ann_hash_local
{
    # Niels Larsen, July 2011.

    # Creates an annotation hash from given blast M8 blast file for the 
    # given target IDs and returns it. The annotation is taken from headers
    # of a given sequence file, which is indexed if not already indexed. If 
    # a sequence is not found, no annotation is added. This is a helper 
    # routine. If no output file given, the output file is named as the input,
    # but with ".ann" appended. The output file path is returned. 

    my ( $args,
         $msgs,
        ) = @_;
    
    # Returns nothing.
    
    my ( $seq_file, $mol_name, $ifh, $ofh, $row, $line, @seqs, $seq, %names, 
         $sfh, $name, $ids, @ids );

    $ids = $args->ids;
    $seq_file = $args->seqfile;
    $mol_name = $args->molname;

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE ANNOTATIONS HASH <<<<<<<<<<<<<<<<<<<<<<<<

    # Index if not done,

    if ( not &Seq::Storage::is_indexed( $seq_file ) )
    {
        &Seq::Storage::create_indices(
             {
                 "ifiles" => [ $seq_file ],
                 "progtype" => "fetch",
                 "stats" => 0,
                 "silent" => 1,
             });
    }

    # Uniqify the given ids,

    @ids = &Common::Util::uniqify( $ids );

    # Get all corresponding sequence objects with only one dummy base from each,

    $sfh = &Seq::Storage::get_handles( $seq_file );

    @seqs = &Seq::Storage::fetch_seqs(
        $sfh,
        {
            "locs" => \@ids,
            "order" => 0,
            "return" => 1,
            "silent" => 1,
        });

    &Seq::Storage::close_handles( $sfh );

    # Create an ID => "annotation string" hash for all target ids that can then 
    # be used below to rewrite the input table,

    foreach $seq ( @seqs )
    {
        if ( $seq->info and $seq->info =~ /mol_name=/ ) {
            $name = &Seq::Info::objectify( $seq->info )->mol_name;
        } else {
            $name = $mol_name || $seq->id || "";
        }

        $names{ $seq->id } = $name;

#        exit;
    }

    return wantarray ? %names : \%names;
}
    
sub match
{
    # Niels Larsen, February 2010.

    # Compares a set of fasta sequences against a remote or local sequence 
    # database or file. Input can come from STDIN, be a single file, or multiple
    # files. The database can be "ncbi", a locally installed dataset, or a local 
    # file. Output is a similarity table in most cases, but this depends on the
    # similarity program specified and its arguments. Returns nothing.

    my ( $args,
        ) = @_;

    # Returns nothing.

    my ( $defs, $in_files, $in_file, $out_files, $out_file, $i, $silent, 
         $indent, %args, %params, $in_name, $deleted, $clobber );

    # >>>>>>>>>>>>>>>>>>>>>>>> CHECK AND EXPAND ARGUMENTS <<<<<<<<<<<<<<<<<<<<<

    $defs = {
	"ifiles" => [],
	"itype" => undef,
	"dbs" => undef,
        "osingle" => undef,
        "osuffix" => ".match",
        "clobber" => 0,
        "prog" => undef,
        "args" => undef,
	"silent" => 0,
        "tgtann" => 1,
        "verbose" => 0,
	"header" => 1,
	"indent" => 3,
    };
    
    $args = &Registry::Args::create( $args, $defs );
    
    # Checks file permissions and resolve db names to sequence files. Crash
    # with message if something wrong,

    %args = &Seq::Match::match_args( $args );

    $in_files = $args{"ifiles"};
    $out_files = $args{"ofiles"};

    %params = (
        "dbfiles" => $args{"dbfiles"},
        "prog" => $args{"prog"},
        "args" => $args{"args"},
        "silent" => ( not $args->verbose ),
        "indent" => 6,
        );
    
    $silent = $args->silent;
    $clobber = $args->clobber;
    $indent = $args->verbose ? $args->indent : 0;

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    if ( $args->header ) {
	&echo_bold( qq (\nSequence Match:\n) ) unless $silent;
    }

    if ( $in_files and @{ $in_files } )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        for ( $i = 0; $i <= $#{ $in_files }; $i++ )
        {
            $in_file = $in_files->[$i];
            $in_name = &File::Basename::basename( $in_file );

            &echo( qq (   Matching $in_name ... ) ) unless $silent;

            if ( $args{"ofile"} )
            {
                $out_file = $args{"ofile"};
                &Common::File::delete_file_if_exists( $out_file ) if $out_file and $clobber and not $deleted;
                $deleted = 1;
            }
            elsif ( $args{"ofiles"} )
            {
                $out_file = $out_files->[$i];
                &Common::File::delete_file_if_exists( $out_file ) if $clobber;
            }
            else {
                $out_file = "";
            }
            
            &Seq::Match::match_single( 
                {
                    "ifile" => $in_file,
                    "ofile" => $out_file,
                    %params,
                });

            &echo_green( "done\n", $indent ) unless $silent;
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>> INPUT STREAM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        &echo( qq (   Matching STDIN stream ... ) ) unless $silent;

        $out_file = $args{"ofile"} // "";
        &Common::File::delete_file_if_exists( $out_file ) if $out_file and $clobber;

        &Seq::Match::match_single( 
            {
                "ifile" => "",
                "ofile" => $out_file,
                %params,
            });

        &echo_green( "done\n", $indent ) unless $silent;
    }

    if ( $args->header ) {
	&echo_bold("Done\n\n") unless $silent;
    }

    return;
}

sub match_args
{
    # Niels Larsen, February 2010.

    # Checks and expands the match routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, %args, @ofiles );

    @msgs = ();

    # Input files must be readable,

    if ( defined $args->ifiles and @{ $args->ifiles } ) {
	$args{"ifiles"} = &Common::File::check_files( $args->ifiles, "efr", \@msgs );
    }

    # Expand input data type,

    $args{"itype"} = &Seq::Args::canonical_type( $args->itype, \@msgs );

    # Set and check program and arguments,

    if ( &Common::Types::is_protein( $args{"itype"} ) ) {
        $args{"prog"} = &Registry::Args::prog_name( $args->prog, ["psimscan","blastp"], \@msgs );
    } else {
        $args{"prog"} = &Registry::Args::prog_name( $args->prog, ["nsimscan","blastn"], \@msgs );
    }

    # Expand and check dataset paths,

    if ( defined $args->dbs ) {
	push @{ $args{"dbfiles"} }, map { $_->[1] } &Seq::Args::expand_paths( $args->dbs, \@msgs );
    }

    $args{"args"} = $args->args;

    # Output files: if a single output file is given, then that file may not exist
    # unless clobber is set. If no single file is given, then the input files with 
    # suffix appended may not exist unless clobber is set,

    if ( defined $args->osingle )
    {
        if ( $args->osingle ) {
            $args{"ofile"} = $args->osingle;
            &Common::File::check_files( [ $args{"ofile"} ], "!e", \@msgs ) if not $args->clobber;
        }
    }
    elsif ( defined $args->ifiles and @{ $args->ifiles } )
    {
        $args{"ofiles"} = [ map { $_ . $args->osuffix } @{ $args->ifiles } ];
        &Common::File::check_files( $args{"ofiles"}, "!e", \@msgs ) if not $args->clobber;
    }

    if ( @msgs ) {
        &append_or_exit( \@msgs, $msgs );
    }
    
    return wantarray ? %args : \%args;
}

sub match_single
{
    # Niels Larsen, February 2010.
    
    # Compares a set of fasta sequences against a remote or local sequence 
    # database or file. The database can be "dna_seq_genbank", a locally 
    # installed dataset, or a local file. Output is a similarity table. Try 
    # use this instead of the other routines in this module. 

    my ( $args,
	) = @_;

    # Returns nothing. 
    
    my ( $defs, $prog, $prog_args, $in_file, %wants_in_file, $db_files, 
         $db_file, $tmp_in_file, $cmd, $tmp_m8_file, $tmp_out_file, $silent,
         $ifh, $ofh, $in_name, $db_name, $line, $count, $tmpfh, $indent, 
         $out_file, $dbs, %prog_args, $tgt_ann, $stderr );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $defs = {
        "prog" => undef,
        "args" => "",
	"ifile" => undef,
	"dbfiles" => [],
        "ofile" => undef,
        "tgtann" => 1,
	"silent" => 0,
	"indent" => 3,
    };
    
    $args = &Registry::Args::create( $args, $defs );

    # Convenience variables, 

    $prog = $args->prog;
    $prog_args = $args->args;
    $in_file = $args->ifile;
    $db_files = $args->dbfiles;
    $out_file = $args->ofile;
    $tgt_ann = $args->tgtann;

    $silent = $args->silent;
    $indent = $args->indent;

    &echo("\n") unless $silent;

    # >>>>>>>>>>>>>>>>>>>>>>>>>> SET INPUT FILES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Some programs will not read from STDIN, so generate a temporary file,

    %wants_in_file = (
	"nsimscan" => 1,
	"psimscan" => 1,
	);
    
    if ( not $in_file and $wants_in_file{ $prog } )
    {
	&echo( "Writing temporary input file ... ", $indent ) unless $silent;

        $tmp_in_file = Registry::Paths->new_temp_path( "$prog.in" );
        $count = &Common::File::save_stdin( $tmp_in_file );

	&echo_green( "done\n" ) unless $silent;
    }
    else {
        $tmp_in_file = $in_file;
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RUN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $ofh = &Common::File::get_append_handle( $out_file );

    $count = 1;
    $stderr = "";

    foreach $db_file ( @{ $db_files } )
    {
	$db_name = &File::Basename::basename( $db_file );
        $tmp_out_file = undef;

        if ( not $silent ) 
        {
            if ( $in_file ) {
                $in_name = &File::Basename::basename( $in_file );
            } else {
                $in_name = "STDIN";
            }

            &echo( "$in_name vs $db_name ... ", $indent ) unless $silent;
        }
        
        $tmp_m8_file = Registry::Paths->new_temp_path( "$prog.out" ) .".$count";
        &Common::File::delete_file_if_exists( $tmp_m8_file );
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>> LOCAL SIMSCAN <<<<<<<<<<<<<<<<<<<<<<<<<<<<

	if ( $prog eq "nsimscan" or $prog eq "psimscan" )
        {
            $cmd = "$prog $prog_args $tmp_in_file $db_file $tmp_m8_file";
            
            &Common::OS::run3_command( $cmd, undef, \$stderr );
            &error( $stderr ) if $stderr;

            if ( $tgt_ann and -s $tmp_m8_file )
            {
                $tmp_out_file = "$tmp_m8_file.ann";
                &Seq::Match::write_ann_table_local(
                    bless {
                        "itable" => $tmp_m8_file,
                        "seqfile" => $db_file,
                        "molname" => undef,
                        "otable" => $tmp_out_file,
                    });
                
                &Common::File::delete_file( $tmp_m8_file );
            }
            else {
                $tmp_out_file = $tmp_m8_file;
            }
	}

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> LOCAL BLAST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> NCBI BLAST <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        elsif ( $db_file =~ /_seq_genbank:?(.*)/ )
        {
            $dbs = $1 // "gene";
            $dbs = join " ", split /\s*,\s*/, $dbs;
            %prog_args = split " ", $prog_args;

            if ( &Seq::Run::run_blast_at_ncbi(
                      {
                          "ifile" => $tmp_in_file,
                          "ofile" => $tmp_m8_file,
                          "params" => { %prog_args, "-p" => $prog, "-d" => $dbs, "-m" => 8 },
                          "fatal" => 0,
                      }) )
            {
                if ( $tgt_ann and -s $tmp_m8_file )
                {
                    $tmp_out_file = "$tmp_m8_file.ann";
                    &Seq::Match::write_ann_table_ncbi(
                        bless {
                            "itable" => $tmp_m8_file,
                            "otable" => $tmp_out_file,
                        });
                }
                else {
                    $tmp_out_file = $tmp_m8_file;
                }
            }

            # &dump( "tmp_out = $tmp_out_file" );
        }   
        else {
	    &error( qq (Wrong looking program name -> "$prog") );
	}

        # >>>>>>>>>>>>>>>>>>>>>>>> APPEND TO OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        if ( defined $tmp_out_file )
        {
            if ( -r $tmp_out_file )
            {
                $tmpfh = &Common::File::get_read_handle( $tmp_out_file );
                
                while ( defined ( $line = <$tmpfh> ) ) {
                    $ofh->print( $line );
                }
                
                $tmpfh->close;
                
                &Common::File::delete_file( $tmp_out_file );
                
                &echo_green( "done\n" ) unless $silent;
            }
            else {
                &echo_yellow( "no matches\n" ) unless $silent;
            }            
            
            &Common::File::delete_file_if_exists( $tmp_m8_file );
            $count += 1;
        }
        else {
            &echo_red( "FAILED\n" ) unless $silent;
        }
    }

    $ofh->close;

    if ( $tmp_in_file ne $in_file ) {
        &Common::File::delete_file( $tmp_in_file );
    }

    return;
}

sub write_ann_table_local
{
    # Niels Larsen, July 2011.

    # Writes a blast M8 table with added annotation strings for the target 
    # ids as an additional last column. Input is blast M8. Output is either
    # given explicit or becomes the name of the input with ".ann" appended.
    # The output file path is returned. 

    my ( $args,
        ) = @_;

    # Returns a string.

    my ( $in_table, $out_table, $ifh, $line, @ids, %ann, $ann, $ofh );

    $in_table = $args->itable;
    $out_table = $args->otable // "$in_table.ann";

    $ifh = &Common::File::get_read_handle( $in_table );

    $line = <$ifh>;

    while ( defined ( $line = <$ifh> ) )
    {
        push @ids, ( split "\t", $line )[1];
    }
    
    &Common::File::close_handle( $ifh );

    %ann = &Seq::Match::ann_hash_local(
        bless {
            "ids" => \@ids,
            "seqfile" => $args->seqfile,
            "molname" => $args->molname,
        });

    $ifh = &Common::File::get_read_handle( $in_table );
    $ofh = &Common::File::get_append_handle( $out_table );

    $line = <$ifh>;
    $ofh->print( $line );

    while ( defined ( $line = <$ifh> ) )
    {
        chomp $line;
        $ann = $ann{ ( split "\t", $line )[1] };

        $ofh->print( "$line\t$ann\n" );
    }
    
    &Common::File::close_handle( $ifh );
    &Common::File::close_handle( $ofh );
        
    return $out_table;
}

sub write_ann_table_ncbi
{
    # Niels Larsen, July 2011.

    # Writes a blast M8 table with added annotation strings for the target 
    # ids as an additional last column. Input is blast M8, the tabular output
    # that comes from NCBI's blast service. Output is either given explicitly
    # or becomes the name of the input with ".ann" appended. The output file 
    # path is returned. 

    my ( $args,
        ) = @_;

    # Returns a string.

    my ( $in_table, $out_table, $ifh, @ids, $idstr, $line, @tmp, $seq_type,
         @ann, %ann, @orgids, %orgs, $ann, $name, $ofh );
    
    $in_table = $args->{"itable"};
    $seq_type = $args->{"seq_type"} // "dna_seq";
    $out_table = $args->{"otable"} // "$in_table.ann";

    $ifh = &Common::File::get_read_handle( $in_table );

    # Isolate GI numbers,

    while ( defined ( $line = <$ifh> ) )
    {
        $idstr =  ( split "\t", $line )[1];

        if ( $idstr =~ /gi\|(\d+)/ ) {
            push @ids, $1;
        } else {
            &error( qq (No GI number in id-string -> "$idstr") );
        }
    }
    
    &Common::File::close_handle( $ifh );

    # Get GI => Title hash from NCBI,

    @tmp = &Common::Entrez_new::fetch_summaries(
        \@ids,
        {
            "dbtype" => $seq_type,
            "tries" => 5,
            "timeout" => 10,
        });

    @ann = map { [ $_->Gi, $_->TaxId, $_->Title ] } @tmp;

    # Then remove organism name and parantheses and what else will make it 
    # resemble a function name,

    @tmp = &Common::Entrez_new::fetch_summaries(
        [ map { $_->[1] } @ann ],
        {
            "dbtype" => "orgs_taxa",
            "tries" => 5,
            "timeout" => 10,
        });

    %orgs = map { $_->TaxId, $_->ScientificName } @tmp;

    foreach $ann ( @ann )
    {
        if ( $name = $orgs{ $ann->[1] } )
        {
            $ann->[2] =~ s/\W*$name\W*//;
        }
    };

    %ann = map { $_->[0], $_->[2] } @ann;

    # Finally write output table with a last column added,

    $ifh = &Common::File::get_read_handle( $in_table );
    $ofh = &Common::File::get_append_handle( $out_table );

    while ( defined ( $line = <$ifh> ) )
    {
        chomp $line;
        $idstr =  ( split "\t", $line )[1];

        if ( $idstr =~ /gi\|(\d+)/ )
        {
            $ann = $ann{ $1 };

            if ( length $ann > 30 ) {
                $ann = ( substr $ann, 0, 30 ) ." ... (TRUNCATED)";
            }

            $ofh->print( "$line\t$ann\n" );
        }
        else {
            &error( qq (No GI number in id-string -> "$idstr") );
        }

    }
    
    &Common::File::close_handle( $ofh );
    
    return $out_table;
}

1;

__END__
