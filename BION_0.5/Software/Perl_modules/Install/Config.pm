package Install::Config;     #  -*- perl -*-

# Configures download and import of software and data. TODO: move all 
# configuration directives to the registry, so all configuration is in
# one place and document, so others can add entries by following 
# instructions.

use strict;
use warnings FATAL => qw ( all );

use Cwd qw ( getcwd cwd abs_path );
use Sys::Hostname;
use File::Find;

use Common::Config;
use Common::Messages;

use Common::OS;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &soft_anal
                 &soft_perl_module
                 &soft_python_module
                 &soft_sys
                 &soft_util
);

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub soft_anal
{
    # Niels Larsen, April 2009.

    # Given a package name from the registry, this routine returns install 
    # instructions. They are used by the installation routines, which fall 
    # back on the defaults given in &Install::Software::default_args.
    # A hash is returned.

    my ( $name,    # Package name
        ) = @_;

    # Returns a hash.

    my ( %conf, $conf, $modi_dir );

    $modi_dir = $Common::Config::pemi_dir;

    %conf = (
        "fastx-toolkit" => {
            "configure_prepend" => qq (export GTEXTUTILS_LIBS=__LIB_DIR__/libgtextutils.a &&)
                                  .qq (export GTEXTUTILS_CFLAGS="-I__INC_DIR__/gtextutils";),
        },
        "mlagan" => {
            "with_configure" => 0,
        },
        "rnamicro" => {
            "with_configure" => 0,
            "edit_files" => {
                "Makefile" => [
                    [ qq (CCFLAGS\\s+=\\s*), qq (CCFLAGS\\t= -L$Common::Config::lib_dir ) ],
                    ],
            },
            "make_command" => "g++ -c svm.cpp && make",
            "install_post_command" => "cp __SRC_DIR__/RNAmicro __INST_DIR__/bin",
            "install_bins" => [ qw ( RNAmicro ) ],
        },
        "rnaz" => {
            "configure_params" => "--datadir __INST_DIR__/share",
        },
        "blastalign" => {
            "edit_files" => {
                "BlastAlign" => [
                    [ qq (^#! /usr/bin/perl -w), qq (#!/usr/bin/env perl\nuse warnings;) ],
                    [ qq (= "blastall"), qq (= "$Common::Config::bin_dir/blastall") ],
                    [ qq (= "formatdb"), qq (= "$Common::Config::bin_dir/formatdb") ],
                    [ qq (= "BlastAlign.py"), qq (= "$Common::Config::bin_dir/BlastAlign.py") ],
                    ],
            },
            "with_configure" => 0,
            "with_make" => 0,
            "install_bins" => [ qw ( BlastAlign BlastAlign.py ) ],
        },
        "mview" => {
            "edit_files" => {
                "bin/mview" => [
                    [ 'use lib \S+;', qq (use lib "__INST_DIR__/lib";) ],
                    ],
            },
            "with_configure" => 0,
            "with_make" => 0,
            "install_bins" => [ qw ( bin ) ],
        },            
        "netblast" => {
            "install_pre_function" => qq (Install::Software::download_blast("netblast")),
            "with_configure" => 0,
            "with_make" => 0,
            "install_bins" => [ qw ( bin ) ],
        },
        "blast" => {
            "install_pre_function" => qq (Install::Software::download_blast("blast")),
            "with_configure" => 0,
            "with_make" => 0,
            "install_bins" => [ qw ( bin data doc ) ],
        },
        "muscle" => {
            "with_configure" => 0,
            "make_command" => "make all",
            "install_bins" => [ qw ( muscle ) ],
        },
        "pfold" => {
            "with_configure" => 0,
            "make_command" => "cd src && make",
            "install_bins" => [ qw ( bin ) ],
            "install_libs" => [ qw ( lib ) ],
        },
        "bowtie" => {
            "with_configure" => 0,
            "make_command" => "make && mkdir bin && mv bowtie bin && mv bowtie-* bin",
            "install_bins" => [ qw ( bin ) ],
        },
        "foldalign" => {
            "with_configure" => 0,
            "make_command" => "make",
            "install_bins" => [ qw ( bin ) ],
            "install_data" => [ qw ( data scorematrix ) ],
        },
        "simscan" => {
            "with_configure" => 0,
            "make_command" => "make",
            "install_bins" => [ qw ( nsimscan/nsimscan psimscan/psimscan ) ],
            "install_libs" => [ qw ( lib/libseq.a ) ],
        },
        "cdhit" => {
            "with_configure" => 0,
            "make_command" => "make",
            "install_bins" => [ qw ( cd-hit cd-hit-2d cd-hit-est cd-hit-est-2d cd-hit-454 ) ],
        },
        "uclust" => {
            "edit_files" => {
                "src/mk" => [
                    [ qq (echo), qq (# echo) ],
                    [ qq (ls -lh), qq (# ls -lh) ],
                    [ qq (sum uclust), qq (# sum uclust) ],
                    [ qq (tail uclust), qq (# tail uclust) ],
                    [ qq (strip uclust), qq (# strip uclust) ],
                    ],
            },
            "with_configure" => 0,
            "make_command" => "cd src && ./mk",
            "install_bins" => [ qw ( src/uclust ) ],
        },
        "uchime" => {
            "edit_files" => {
                "mk" => [
                    [ qq (echo), qq (# echo) ],
                    ],
            },
            "with_configure" => 0,
            "make_command" => "./mk",
            "install_bins" => [ qw ( uchime ) ],
        },
        "patscan" => {
            "with_configure" => 1,
            # "edit_files" => {
            #     "show_hits" => [
            #         [ "/usr/local/bin/perl", qq "/usr/bin/env perl" ],
            #         ],
            #     "testit" => [
            #         [ "/usr/local/bin/perl", qq "/usr/bin/env perl" ],
            #     ],
            # },
            # "make_command" => "gcc -O -o scan_for_matches ggpunit.c scan_for_matches.c",
            "make_command" => "make scan_for_matches",
            "with_test" => 1,
            "test_command" => "./run_tests tmp && mv scan_for_matches patscan",
            "install_bins" => [ qw ( patscan show_hits ) ],
        },
        "viennarna" => {
            "configure_params" => "--without-forester",
            "install_post_command" => "cp -Rfp __SRC_DIR__/Perl/* $modi_dir/lib/perl5",
        },
        "emboss" => {
            "configure_params" => "--without-x --without-java",
        },
        "mothur" => {
            "edit_files" => {
                "makefile" => [
                    [ qq (64BIT_VERSION \\?= yes), qq (64BIT_VERSION \\?= no), "not &Common::OS::is_64bit" ],
                    [ qq (USEREADLINE \\?= yes), qq (USEREADLINE \\?= no) ],
                    [ qq (FORTRAN_COMPILER = gfortran), qq (FORTRAN_COMPILER = f77), "`which f77`" ],
                    [ qq (FORTRAN_COMPILER = gfortran), qq (FORTRAN_COMPILER = f95), "`which f95`" ],
                    [ qq (FORTRAN_COMPILER = gfortran), qq (FORTRAN_COMPILER = gfortran), "`which gfortran`" ],
                    ],
            },
            "with_configure" => 0,
            "install_post_command" => "mv __SRC_DIR__/mothur __INST_DIR__/bin && "
                                 . qq (ln -s __INST_DIR__/bin/mothur __BIN_DIR__),
        },
        );
        
    if ( $conf{ $name } )
    {
        $conf = { 
            %{ $conf{ $name } },
            "name" => $name,
        };
    }
    else
    {
        # If not configured explicitly above we use the GNU way as implicit 
        # configuration,

        $conf = { "name" => $name };
    }

    return wantarray ? %{ $conf } : $conf;
}

sub soft_perl_module
{
    # Niels Larsen, April 2009.

    # Given a perl module name from the registry, this routine returns 
    # install configuration. It is then sed by the installation routines, which
    # fall back on the defaults given in &Install::Software::default_args.
    # A hash is returned.

    my ( $name,    # Package name
        ) = @_;

    # Returns a hash.

    my ( $mods_dir, $modi_dir, %conf, $conf, $pbin_dir );

    $mods_dir = $Common::Config::pems_dir;
    $modi_dir = $Common::Config::pemi_dir;
    $pbin_dir = "$Common::Config::pki_dir/Perl/bin";

    %conf = (
        "ExtUtils-PkgConfig" => {
            "install_pre_function" => qq (&Install::Software::install_utilities("pkg-config")),
        },
        "File-Rename" => {
            "install_post_command" => 
                qq (ln -s -f $pbin_dir/rename __BIN_DIR__)
        },
        "HTML-Parser" => {
            "configure_prepend" => "echo 'n' | ",
            "with_test" => 1,
        },
        "forks" => {
            "configure_prepend" => "echo 'n' | ",
        },
        "Parse-RecDescent" => {
            "configure_prepend" => "echo 'n' | ",
            "with_test" => 1,
        },
        "Inline" => {
            "configure_prepend" => "echo 'y' | ",
            "with_test" => 1,
        },
        "EV" => {
            "configure_prepend" => "echo 'y' | ",
        },
        "Devel-NYTProf" => {
            "install_post_command" => 
                qq (ln -s -f __PEMI_DIR__/bin/nytprofcg __BIN_DIR__ &&)
               .qq (ln -s -f __PEMI_DIR__/bin/nytprofcsv __BIN_DIR__ &&)
               .qq (ln -s -f __PEMI_DIR__/bin/nytprofhtml __BIN_DIR__ &&)
               .qq (ln -s -f __PEMI_DIR__/bin/nytprofmerge __BIN_DIR__),
        },
        "BioPerl" => {
            "with_configure" => 0,
            "with_make" => 0,
            "with_install" => 0,
            "install_post_command" => "cp -Rfp __SRC_DIR__/Bio $modi_dir/lib/perl5",
        },
        "Patscan" => {
            "configure_command" => "cd perl/Bio-Patscan; perl Makefile.PL",
            "make_command" => "cd perl/Bio-Patscan; make",
            "install_command" => "cd perl/Bio-Patscan; make install",            
        },
        "SOAP-Lite" => {
            "configure_params" => "--noprompt",
        },
        "libwww-perl" => {
            "configure_params" => "-n",
        },
        "XML-SAX" => {
            "configure_prepend" => "echo 'y' | ",
        },
        "XML-Parser" => {
            "install_pre_function" => qq (&Install::Software::install_utilities("expat")),
            "configure_params" => "EXPATLIBPATH=$Common::Config::lib_dir"
                               . " EXPATINCPATH=$Common::Config::inc_dir",
            "install_post_function" => qq (&Install::Software::uninstall_utilities("expat")),
        },
        "Math-GSL" => {
            "install_pre_condition" => qq (&Install::Software::check_install("gsl")),
            "configure_prepend" => "export PKG_CONFIG_PATH=$Common::Config::uti_dir/gsl/lib/pkgconfig; ",
        },
        "GD" => {
            "install_pre_condition" => "Install::Software::check_install('gd')",
            "configure_params" => 
                qq ( -options='PNG,GIF,ANIMGIF,FREETYPE')
              . qq ( -lib_zlib_path=$Common::Config::uts_dir/zlib)
              . qq ( -lib_png_path=$Common::Config::uts_dir/libpng)
              . qq ( -lib_ft_path=$Common::Config::uts_dir/freetype)
              . qq ( -lib_gd_path=$Common::Config::uts_dir/gd),
        },
#         "DB_File" => {
#             "install_pre_condition" => "Install::Software::check_install('db')",
#             "edit_files" => {
#                 "config.in" => [
#                     [ 'INCLUDE\s*=\s*/usr/local/BerkeleyDB/include[^\n]*', 'INCLUDE = __INC_DIR__' ],
#                     [ 'LIB\s*=\s*/usr/local/BerkeleyDB/lib[^\n]*', 'LIB = __LIB_DIR__' ],
#                     ],
#             },
#         },
        "PDL" => {
            "edit_files" => {
                "perldl.conf" => [
                    [ 'HTML_DOCS => 1', "HTML_DOCS => 0" ],
                    [ 'TEMPDIR => undef', qq (TEMPDIR => "$Common::Config::tmp_dir") ],
                    [ 'WITH_POSIX_THREADS => undef', 'WITH_POSIX_THREADS => 0' ],
                    [ 'WITH_3D => [^,]+', 'WITH_3D => 0' ],
                    [ 'WITH_PLPLOT\s*=>\s*undef', 'WITH_PLPLOT => 1' ],
                    [ 'WITH_SLATEC\s*=>\s*undef', 'WITH_SLATEC => 0' ],
                    [ 'WITH_GSL\s*=>\s*undef', 'WITH_GSL => 0' ],
                    [ 'WITH_FFTW\s*=>\s*undef', 'WITH_FFTW => 0' ],
                    [ 'WITH_HDF\s*=>\s*undef', 'WITH_HDF => 0' ],
                    [ 'WITH_GD\s*=>\s*undef', 'WITH_GD => 0' ],
                    [ 'WITH_PROJ\s*=>\s*undef', 'WITH_PROJ => 0' ],
                    ],
            },
            "with_no_perl5lib" => 1,
            "with_no_die_handler" => 1,
            "install_post_command" => qq (rm -f __BIN_DIR__/pdl && )
                            . qq (ln -s __INST_DIR__/bin/pdl __BIN_DIR__ && )
                            . qq (rm -f __BIN_DIR__/pdldoc && )
                            . qq (ln -s __INST_DIR__/bin/pdldoc __BIN_DIR__ && )
                            . qq (rm -f __BIN_DIR__/perldl && )
                            . qq (ln -s __INST_DIR__/bin/perldl __BIN_DIR__),
            
        },
        "mod_perl" => {
            "install_pre_condition" => "Install::Software::check_install('apache','soft_sys')",
            "configure_params" => "MP_APXS=$Common::Config::pki_dir/Apache/bin/apxs",
        },
        "DBD-mysql" => {
            "install_pre_condition" => "&Install::Software::check_install('mysql')",
        },
        "kyotocabinet-perl" => {
            "install_pre_condition" => "&Install::Software::check_install('kyotocabinet')",
        },
        );

    if ( $conf = $conf{ $name } )
    {
        return $conf;
    }

    return;
}

sub soft_python_module
{
    # Niels Larsen, November 2010.

    # Given a python module name from the registry, this routine returns 
    # install configuration. It is then sed by the installation routines,
    # which fall back on the defaults given in &Install::Software::default_args.
    # A hash is returned.

    my ( $name,    # Package name
        ) = @_;

    # Returns a hash.

    my ( $mods_dir, $modi_dir, %conf, $conf );

    $mods_dir = $Common::Config::pyms_dir;
    $modi_dir = $Common::Config::pymi_dir;

    %conf = (
        "pychecker" => {
            "install_post_command" => "ln -s __INST_DIR__/bin/pychecker __BIN_DIR__",
        },
        );

    if ( $conf = $conf{ $name } )
    {
        return $conf;
    }

    return;
}

sub soft_sys
{
    # Niels Larsen, May 2009.

    # Returns install options for a given major software package. They are used 
    # by the installation routines, which fall back on the defaults given in 
    # &Install::Software::default_args. A hash is returned.

    my ( $name,     # Package name
        ) = @_;

    # Returns a hash.

    my ( %conf, $conf );

    %conf = (
        "apache" => {
            "uninstall_pre_function" => "Install::Software::uninstall_pre_apache()",
            "with_local_tmp_dir" => 0,
        },
        "mysql" => {
            "uninstall_pre_function" => "Install::Software::uninstall_pre_mysql()",
            "uninstall_post_function" => "Install::Software::uninstall_post_mysql()",
        },
        "perl" => {
            "uninstall_pre_function" => "Install::Software::uninstall_perl_modules()",
        },
        "python" => {
            "install_command" => "PATH=.:\$PATH; make install",
        },
        "ruby" => {
            "install_pre_function" => qq (Common::Config::unset_env_variables),
            "configure_prepend" => "CPPFLAGS=-I$Common::Config::uti_dir/libffi/include; ",
        },
        "nano" => {
            "configure_prepend" => "CPPFLAGS=-I$Common::Config::uti_dir/ncurses/include/ncurses; ",
        },
        );

    if ( $conf = $conf{ $name } )
    {
        return $conf;
    }

    return;
}

sub soft_util
{
    # Niels Larsen, April 2009.

    # Given a utility package name from the registry, this routine returns 
    # install configuration. They are used by the installation routines, which
    # fall back on the defaults given in &Install::Software::default_args.
    # A hash is returned.

    my ( $name,    # Package name
        ) = @_;

    # Returns a hash.

    my ( $uts_dir, $uti_dir, %conf, $conf );

    $uts_dir = $Common::Config::uts_dir;
    $uti_dir = $Common::Config::uti_dir;

    %conf = (
        "libssh2" => {                                                                                                                                    
            # "configure_params" => " -ldl",
            "configure_params" => " --with-openssl --without-libgcrypt",
        },
        "openssl" => {
            "configure_params" => " shared",
        },
        "wget" => {
            "configure_params" => " --without-ssl",
        },
        "sff2fastq" => {
            "with_configure" => 0,
            "make_command" => "make",
            "install_bins" => [ "sff2fastq" ],
        },
        "libffi" => {
            "install_post_function" => qq (&Common::File::create_links_relative("__INST_DIR__/lib/__SRC_NAME__/include","__INST_DIR__/include")),
        },
#        "curl" => {
#            "unset_env_vars" => "LDFLAGS",
#            "configure_params" => " --with-ssl --with-libssh",
#            "configure_params" => " --with-ssl",
#        },
        "bzip2" => {
            "with_configure" => 0,
            "with_make" => 0,
            "install_command" => "make install PREFIX=__INST_DIR__",
        },
        "tree" => {
            "edit_files" => {
                "Makefile" => [
                    [ '\nprefix\s*=\s*/usr', qq (\nprefix = $uti_dir/tree) ],
                    ],
            },
            "with_configure" => 0,
        },
        "gd" => {
            "configure_params" => 
                " --with-x=no".
                " --with-png=$uti_dir/libpng".
                " --with-freetype=$uti_dir/freetype".
                " --with-zlib=$uti_dir/zlib",
            "install_post_function" => qq (Install::Software::install_perl_modules("GD",{"force"=>1})),
        },
        "gsl" => {
            "install_post_function" => qq (\$ENV{"PKG_CONFIG_PATH"} = "$Common::Config::uti_dir/gsl/lib/pkgconfig";)
                                      .qq ( Install::Software::install_perl_modules("Math-GSL",{"force"=>1})),
        },            
        "zlib" => {
            "configure_params" => " -s",
            "edit_files_post_config" => {
                "Makefile" => [
                    [ '\nCFLAGS=([^\n]+)', '\nCFLAGS=$1 -fPIC' ],
                    ],
            },
            "install_post_command" => "( cd $uts_dir && rm -f zlib && ln -s __SRC_NAME__ zlib )",
            "uninstall_post_command" => "( cd $uts_dir && rm -f zlib )",
            "delete_source_dir" => 0,
        },
        "jpeg" => {
            "with_test" => 1,
            "install_post_command" => "cp __SRC_DIR__/*.h __INST_DIR__/include && "
                                     ."cp __SRC_DIR__/*.a __INST_DIR__/lib",
            "delete_source_dir" => 0,
        },
        "di" => {
            "configure_command" => "./Build distclean",
            "make_command" => "CC=gcc prefix=__INST_DIR__ ./Build -mkc",
            "install_command" => "CC=gcc prefix=__INST_DIR__ ./Build -mkc install",
        },
        "bargraph" => {
            "with_configure" => 0,
            "with_make" => 0,
            "install_command" => "cp __SRC_DIR__/bargraph.pl __INST_DIR__/bin/bargraph",
            "install_bins" => [ qw ( bin ) ],
        },
        "kyotocabinet" => {
            "configure_prepend" => "CPPFLAGS=; ",
            "configure_params" => " --disable-bzip --disable-zlib",
            "install_post_function" => qq (&Install::Software::install_perl_modules("kyotocabinet-perl",{"force"=>1})),
        },
        );
        
    if ( $conf = $conf{ $name } )
    {
        return $conf;
    }

    return;
}

1;

__END__
