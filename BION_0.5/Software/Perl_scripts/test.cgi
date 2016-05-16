#!/usr/bin/env perl

use strict;
use warnings FATAL => qw ( all );

# use CGI;

use Common::OS;
#use Common::Config;
# use Common::Messages;

#use Common::States;
#u#se Common::Users;
#use Proc::Simple;

#use Ali::Viewer;
#use Ali::State;
#use Ali::IO;

# use Proc::SafeExec;
# use Common::File;

# use Apache2;

my ( $cgi, $url, $file, $ali, $mod_perl, $dbh, $proc, $err_file, $cmd, $output,
    $tmp_path, @output, $oldout, $str, $stdout, $out_file, $command, $status,
    @command, $stderr, $type, @stdout );


@stdout = &Common::OS::run_command_safe( "ls -al" );

print "Content-type: text/html\n\n";
print "<pre>\n";
print join "\n", @stdout;
print "</pre>\n";



# my $testfile = "/home/niels/BION/Sessions/Temporary/a4c218d7ac7453f3e387c030875fd62d/19-AUG-2008-23:21:02.upload";

# if ( &Common::File::is_ascii( $testfile ) )
# {
#     &dump( "is ascii" );
# }

#$type = &Common::File::get_type( "test.html" );

# &dump( $type );

# __END__
#  # $out_file = "garb.out";
# $out_file = "garb.out";
# $err_file = "garb.err";
# @command = split " ", "ls -al";

# $proc = Proc::Simple->new();

# #open $stdout_old, ">&STDOUT" or die "Can't dup STDOUT: $!";
# # close STDOUT;

# $proc->redirect_output( $out_file, $err_file );

# # close STDOUT;

# $status = $proc->start( "ls", "-al" );
# $status = $proc->wait();

# #open STDOUT, ">&", $stdout_old or die "Can't dup \$stdout_old: $!";

# $stdout = ${ &Common::File::read_file( $out_file ) };
# $stderr = ${ &Common::File::read_file( $err_file ) };

# #print "Content-type: text/html\n\n";
# #print "<pre>$stdout</pre>";

# &dump( $stdout );



# __END__


# open $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
# close STDOUT;

# open STDOUT, '>', \$str or die "Can't redirect STDOUT: $!";

# select STDOUT; $| = 1;        # make unbuffered

# print STDOUT "stdout 1\n";        # this works for

# open STDOUT, ">&", $oldout or die "Can't dup \$oldout: $!";

# &dump( \$str );
# print STDOUT "stdout 2\n";


# __END__

# &error( "balbla" );
# &warning( "balbla" );
# &warning( "balbla" );


# # use constant IS_MODPERL => $ENV{"MOD_PERL"};

# # if (IS_MODPERL) {
# #     tie *STDOUT, 'Apache';
# # } else {
# #     open (STDOUT, ">-");
# # }

# #print "Content-type: text/html\n\n";
# #print "hello";


# __END__

# $tmp_path = "/home/work/tmp_path";
# $file = "/home/niels/BION/Sessions/Temporary/6af8557b762043937cf54cc5b2560f59/18-AUG-2008-01:42:01.upload";

# @output = &Common::OS::run_command_simple( "$Common::Config::bin_dir/file $file" );

# $cgi = new CGI;
# $url = $cgi->url( -absolute => 1 );

# $file = "/home/niels/BION/Data/RNAs/Alignments/SRPDB/Installs/srprna";
# $ali = RNA::Ali->connect( $file );

# $mod_perl = $ENV{"MOD_PERL"} || "";

# $dbh = &Common::DB::connect();

# print qq (Content-type: text/html

# <HTML>
# <HEAD>
# <TITLE>Hello page</TITLE>
# </HEAD>

# <BODY>

# <h3>Hello</h3>

# <PRE>
# GATEWAY_INTERFACE: $ENV{GATEWAY_INTERFACE}
# MOD_PERL: $mod_perl
# URL: $url
# DBH: $dbh
# </PRE>

# </BODY>
# </HTML>
# );

# &dump( \@output );

# $dbh->disconnect;

# &dump( $ali );




# # $file = "/home/niels/BION/Sessions/Temporary/6af8557b762043937cf54cc5b2560f59/18-AUG-2008-01:42:01.upload";
# # $cmd = "$Common::Config::bin_dir/file $file";

# # $proc = new Proc::Simple;

# # $err_file = "/home/niels/work/garb.err";

# # my ( $fh_out, $fh_err, $stdout, $stderr );

# # open $fh_out, ">", \$stdout;
# # open $fh_err, ">", \$stderr;

# # $proc->redirect_output ( $fh_out, $fh_err );

# # $proc->start( $cmd );

# # $proc->kill;


# # &dump( \$stderr );
# # &dump( \$stdout );
