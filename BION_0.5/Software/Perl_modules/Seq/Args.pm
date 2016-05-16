package Seq::Args;                # -*- perl -*-

# Parses and checks common arguments to sequence routines. 

use strict;
use warnings FATAL => qw ( all );

use Scalar::Util;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &canonical_type
                 &check_name
                 &check_qualtype
                 &expand_file_paths
                 &expand_paths
                 );

use Common::Config;
use Common::Messages;
use Common::Types;

use Registry::Register;
use Registry::Args;

use Seq::IO;
use Seq::Storage;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub canonical_type
{
    # Niels Larsen, February 2010.
    
    # Expands "rna" to "rna_seq" and so on. Should go away 

    my ( $type,
	 $msgs,
	) = @_;

    my ( $reg_type, $choices );

    $reg_type = $type ."_seq";
    
    if ( not &Common::Types::is_dna_or_rna( $reg_type ) and
	 not &Common::Types::is_protein( $reg_type ) )
    {
        $choices = join ", ", qw ( dna rna prot );
	push @{ $msgs }, ["ERROR", qq (Wrong looking sequence type -> "$type". Choices: $choices) ];
    }

    return $reg_type;
}

sub check_name
{
    my ( $name,
	 $names,
         $type,
	 $msgs,
	) = @_;

    my ( %names, $choices );

    %names = map { $_, 1 } @{ $names };
    
    if ( not defined $name ) 
    {
        push @{ $msgs }, ["ERROR", qq (No $type is given) ];
    } 
    elsif ( not exists $names{ $name } )
    {
        $choices = join ", ", @{ $names };

	push @{ $msgs }, ["ERROR", qq (Wrong looking $type name -> "$name".) ];
        push @{ $msgs }, ["INFO", qq (Choices are: $choices) ];
    }
    
    return $name;
}

sub check_qualtype
{
    my ( $type,
         $msgs,
        ) = @_;

    my ( $keys, $str, @msgs );

    $keys = &Seq::Common::qual_config();
    
    if ( $keys->{ $type } )
    {
        return $type;
    }
    else
    {
        push @msgs, ["ERROR", qq (Wrong looking quality code name -> "$type") ];
        push @msgs, ["INFO", "" ];
        push @msgs, ["INFO", qq (Allowed quality encodings are:) ];
        map { push @msgs, ["INFO", $_] } &Seq::Common::qual_config_names();

        if ( $msgs ) {
            push @{ $msgs }, @msgs;
        } else {
            &error([ map { $_->[1] } @msgs ]);
        }
    }

    return;
}

sub expand_file_paths
{
    # Niels Larsen, February 2010.

    # Converts a given comma-separated string of file paths with wildcards to 
    # a list of full file paths. If a data type is given, then paths with index
    # suffixes are read checked, otherwise the literal path is checked. Errors
    # are either returned or dumped to STDERR.

    my ( $paths,      # Comma-separated string of files with wild-cards
	 $msgs,       # Outgoing error messages - OPTIONAL
	) = @_;

    # Returns a list.

    my ( $path, $stdout, $stderr, @msgs, $msg, @paths, $file, $basename );

    # Create IDs from either string or list,

    if ( not ref $paths ) {
        $paths = &Registry::Args::split_string( $paths );
    }
    
    foreach $path ( @{ $paths } )
    {
        $stdout = "";
        $stderr = "";

        &Common::OS::run3_command( "ls -1 $path", undef, \$stdout, \$stderr, 0 );

        if ( $stderr and not &Seq::Storage::is_indexed( $path ) )
        {
            $msg = ["ERROR", qq (Wrong looking file path -> "$path") ];

            if ( $msgs ) {
                push @{ $msgs }, $msg;
            } else {
                &error( $msg->[1] );
            }
        }
        else {
            push @paths, split " ", $stdout;
        }
    }

    &append_or_exit( \@msgs, $msgs );
    
    return wantarray ? @paths : \@paths;
}

sub expand_paths
{
    # Niels Larsen, February 2010.

    # Converts a mixed list of file paths and dataset paths to a list of 
    # absolute paths. File paths can be relative and contain shell-style 
    # wildcards. Dataset paths are of the form dataset_name:shell-expr
    # where the shell-expr is optional. As with file paths, the optional
    # expression must be in shell style. The output is a list of elements
    # like of [ id, path, display name ]. 

    my ( $paths,     # Dataset comma-separated id/file string or list
	 $msgs,      # Outgoing error messages - OPTIONAL
	) = @_;

    # Returns a list.

    my ( $path, %dbs, %dbs_reg, @dbs, $db, $db_label, $db_name, $expr,
         $tuple, @paths, @output, @files, @msgs, $inst_dir );

    if ( not ref $paths ) {
        $paths = [ $paths ];
    }
    
    %dbs = map { $_->name, $_ } Registry::Get->datasets()->options;

    # Separate into dataset and file paths,

    foreach $path ( @{ $paths } )
    {
        if ( $path =~ /^(.+):(.+)$/ ) {
            push @dbs, [ $1, $2];
        } elsif ( exists $dbs{ $path } ) {
            push @dbs, [ $path, undef ];
        } else {
            push @paths, $path;
        }
    }

    # Expand file paths,

    @output = &Seq::Args::expand_file_paths( \@paths, \@msgs );

    @output = map { [ &File::Basename::basename( $_ ), $_, &File::Basename::basename( $_ ) ] } @output;

    # Expand dataset paths,

    if ( @dbs )
    {
        # Load registered dataset names, and all registered sets,
        
        %dbs_reg = map { $_, 1 } Registry::Register->registered_datasets;

        foreach $tuple ( @dbs )
        {
            ( $db_name, $expr ) = @{ $tuple };

            if ( exists $dbs_reg{ $db_name } )
            {
                $db = $dbs{ $db_name };
                $db_label = $db->label // $db->title;
                
                $inst_dir = $db->datapath_full ."/Installs";
                
                if ( $expr ) {
                    @files = &Seq::Args::expand_file_paths( [ $inst_dir ."/$expr" ], \@msgs );
                } else {
                    @files = map { $_->{"path"} } &Common::File::list_fastas( $inst_dir );
                }
                
                push @output, map { [ $db_name, $_, $db_label ] } @files; 
            }
            elsif ( $db = $dbs{ $db_name } )
            {
                if ( $db->datapath )
                {
                    push @msgs, ["ERROR", qq (Valid dataset name, but not installed -> "$db_name") ];
                }
                else
                {
                    $expr //= "nr";
                    $expr = join ",", split /\s*,\s*/, $expr;
                    push @output, [ $db_name, "$db_name:$expr", $db->label // $db->title ];
                }
            }
            else {
                push @msgs, ["ERROR", qq (Wrong looking dataset name -> "$db_name") ];
            }
        }
    }

    &append_or_exit( \@msgs, $msgs );

    return wantarray ? @output : \@output;
}

1;

__END__

# sub db_list
# {
#     # Niels Larsen, February 2010.

#     # Reads a file of dataset names or files and checks names and permissions
#     # of those. Returns a list of full file paths.

#     my ( $file,     # List file
# 	 $msgs,     # Outgoing error messages - OPTIONAL
# 	) = @_;

#     # Returns a list.

#     my ( @lines, $dbstr, @paths );

#     @lines = split "\n", ${ &Common::File::read_file( $file ) };

#     foreach $dbstr ( @lines )
#     {
# 	next if not $dbstr or $dbstr =~ /^#/;
# 	push @paths, &Seq::Args::db_files( $dbstr, $msgs );
#     }
    
#     return wantarray ? @paths : \@paths;
# }
