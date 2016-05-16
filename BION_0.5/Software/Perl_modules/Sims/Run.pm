package Sims::Run;                # -*- perl -*-

# Various routines that take similarities as input. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use File::Basename;
use Cwd qw ( getcwd );

use Common::Config;
use Common::Messages;

use Registry::Args;
use Common::File;
use Common::Util;
use Seq::Import;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# run_blastalign
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# sub run_blastalign
# {
#     # Niels Larsen, April 2008.

#     # Runs the BlastAlign method by Robert Belshaw and Aris Katzourakis.
#     # Temporary files are deleted for each run and the output file is in
#     # fasta format.

#     my ( $args,         # Arguments 
#          $msgs,         # Outgoing list of runtime messages - OPTIONAL
#          ) = @_;

#     my ( $params, $key, $command, @msgs, $msg, $ifile, $iname, $oname,
#          $tmp_dir, $orig_dir, $ofile );
    
#     $args = &Registry::Args::check( $args, {
#         "S:1" => [ qw ( ifile ofile ) ],
#         "HR:1" => [ qw ( params ) ],
#         "S:0" => [ qw ( dbpath dbfile dbtype ) ],
#         "HR:0" => [ qw ( pre_params post_params ) ],
#     });

#     $ifile = &Cwd::abs_path( $args->ifile );
#     $ofile = &Cwd::abs_path( $args->ofile );

#     $params = &Common::Util::merge_params(
#         $args->params,
#         {
#             "-m" => 0.99,
#             "-r" => undef,eq
#             "-x" => undef,
#             "-n" => "T",
#             "-s" => undef,
#         });

#     # Make command,

#     $command = "BlastAlign -i $ifile";

#     foreach $key ( keys %{ $params } )
#     {
#         $command .= " $key ". $params->{ $key };
#     }

#     # Run command; this program creates files with fixed names in the current
#     # directory; to avoid that mess, create and delete a subdirectory in the 
#     # scratch area,

#     $orig_dir = &Cwd::getcwd();
    
#     $tmp_dir = "$Common::Config::tmp_dir/BlastAlign_". $$;
#     &Common::File::create_dir( $tmp_dir );
#     chdir $tmp_dir;

#     @msgs = &Common::OS::run_command( $command, undef, [] );
#     chomp @msgs;

#     @msgs = grep { $_ =~ /\w/ } @msgs;

#     if ( grep { $_ =~ /^BlastAlign finished:/ } @msgs )
#     {
#         push @{ $msgs }, grep { $_ =~ /^Excluding/ } @msgs;
#     }
#     else 
#     {
#         @msgs = grep { $_ =~ /^Error message/ } @msgs;
#         $msg = join "\n", @msgs;
#         &error( 
#               qq (Command line -> "$command"\n)
#             . qq (Message: $msg)
#             );
#     }

#     chdir $orig_dir;

#     # Convert phylip alignment to fasta,
    
#     Seq::Import->write_fasta_from_phylip( "$ifile.phy", $ofile );

#     # Delete all generated files,

#     &Common::File::delete_dir_tree( $tmp_dir );

#     &Common::File::delete_file( "$ifile.phy" );
#     &Common::File::delete_file( "$ifile.nxs" );

#     return;
# }

1;

__END__
