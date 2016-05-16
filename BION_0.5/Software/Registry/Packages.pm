package Software::Registry::Packages;

# -*- perl -*-

# A list of all software packages that the system knows how to install. 
# Each package may contain many programs some of which may be defined 
# as a method (see Methods.pm). 

use strict;
use warnings FATAL => qw ( all );

my @descriptions;

my ( @gnu_utils, @src_names, $src_name, $inst_name, @gnu_list, 
     $util, @list, $osname );

$osname = `uname -s`; chomp $osname;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> BASE PACKAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# These are web-server, databases, programming languages and such,

@list = ({
    "name" => "perl",
    "title" => "Perl programming language",
    "inst_name" => "Perl",
    "src_name" => "perl-5.14.2",
    "url" => "http://www.perl.org",
},{
    "name" => "gawk",
    "title" => "GNU Awk formatting language",
    "inst_name" => "Gawk",
    "src_name" => "gawk-3.1.8",
    "url" => "http://www.gnu.org/software/gawk",
},{
    "name" => "python",
    "title" => "Python programming language",
    "inst_name" => "Python",
    "src_name" => "Python-2.7.1",
    "url" => "http://www.python.org",
},{
    "name" => "ruby",
    "title" => "Ruby programming language",
    "inst_name" => "Ruby",
    "src_name" => "ruby-1.9.3-p194",
    "url" => "http://www.ruby-lang.org",
},{
    "name" => "apache",
    "title" => "Web server",
    "inst_name" => "Apache",
    "src_name" => "httpd-2.2.22",
    "url" => "http://httpd.apache.org",
},{
    "name" => "mysql",
    "title" => "Relational database",
    "inst_name" => "MySQL",
    "src_name" => "mariadb-5.2.12",
    "url" => "http://www.mariadb.org",
},{
    "name" => "nano",
    "title" => "Nano text editor",
    "inst_name" => "Nano",
    "src_name" => "nano-2.2.6",
    "url" => "http://www.nano-editor.org",
});

@list = map { $_->{"datatype"} = "soft_sys"; $_ } @list;

push @descriptions, @list;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PERL MODULES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# These are needed public Perl modules that do not come with the 
# standard Perl distribution. 

# CGI-Session 4.14 is used, later versions have changes that make
# things not work. TODO fix to use latest.

@src_names = qw (
                 Shell-0.72
                 ExtUtils-PkgConfig-1.13
                 Test-Most-0.23
                 Test-Class-0.36
                 Test-Exception-0.31
                 IO-String-1.08
                 IPC-Run3-0.045
                 IPC-System-Simple-1.20
                 IPC-Pipeline-0.3
                 Data-ShowTable-3.3
                 Data-CTable-1.03
                 Data-Stag-0.11
                 Getopt-ArgvFile-1.11
                 Proc-Reliable-1.16
                 Proc-ProcessTable-0.44
                 Config-General-2.50
                 Error-0.17008
                 Memory-Usage-0.201
                 File-Type-0.22
                 MIME-Base64-3.07
                 URI-1.54
                 Clone-0.31
                 Data-Structure-Util-0.15
                 String-Approx-3.26
                 Scalar-List-Utils-1.18
                 List-Compare-0.33
                 HTML-Tagset-3.20
                 HTML-Parser-3.68
                 HTML-Tree-3.21
                 HTML-FormatExternal-14
                 Parse-RecDescent-1.94
                 Object-Destroyer-2.00
                 Parse-MediaWikiDump-0.92
                 Lingua-Stem-Snowball-0.952
                 Inline-0.46
                 Class-Inspector-1.16
                 Class-AutoAccess-0.02
                 Compress-LZF-3.43
                 Compress-LZ4-0.17
                 IO-Compress-2.061
                 Compress-Raw-Zlib-2.061
                 Compress-Raw-Bzip2-2.061
                 IO-Compress-Zlib-2.005
                 Net-Daemon-0.39
                 Net-OpenSSH-0.47
                 Math-GSL-0.26
                 Math-Matrix-0.5
                 PlRPC-0.2018
                 Filesys-Df-0.92
                 Filesys-DfPortable-0.85
                 File-Copy-Recursive-0.30
                 File-Fetch-0.24
                 File-Rename-0.06
                 DBI-1.616
                 Boulder-1.30
                 Date-Simple-3.02
                 Data-Password-1.07
                 Data-Table-1.54
                 Log-Agent-0.307
                 Locale-Maketext-Lexicon-0.81
                 Run-0.03
                 CGI-Session-4.14
                 Proc-Simple-1.26
                 kyotocabinet-perl-1.20
                 Devel-Size-0.71
                 HTTP-Date-6.02
                 HTTP-BrowserDetect-0.98
                 JSON-2.50
                 JSON-Any-1.25
                 Devel-NYTProf-4.06
                 YAML-LibYAML-0.35
                 YAML-Syck-1.17
                 IO-stringy-2.110
                 IO-Tty-1.08
                 IO-Unread-1.04
                 Heap-0.71
                 Carp-Clan-5.3
                 Bit-Vector-7.1
                 Graph-0.20105
                 Capture-Tiny-0.18
                 Text-Shellwords-1.08
                 Text-Format-0.53
                 Tie-IxHash-1.22
                 Net-FTP-Common-5.31
                 libwww-perl-5.825
                 Data-MessagePack-0.38
                 TermReadKey-2.30
                 XML-NamespaceSupport-1.09
                 XML-SAX-0.96
                 XML-Parser-2.36
                 XML-Simple-2.18
                 SOAP-Lite-0.712
                 SVG-2.52
                 GD-2.41
                 GDTextUtil-0.86
                 GDGraph-1.44
                 mod_perl-2.0.6
                 Sys-Hostname-Long-1.4
                 Sys-MemInfo-0.91
                 BioPerl-1.6.0
                 ExtUtils-F77-1.17
                 PDL-2.4.11
                 PDL-Stats-0.6.2
                 Algorithm-Cluster-1.50
                 Patscan-0.2
                 Devel-Symdump-2.08
                 Pod-Coverage-0.22
                 Test-Pod-1.26
                 Test-Pod-Coverage-1.08
                 Time-Duration-1.06
                 List-MoreUtils-0.33
                 Sub-Install-0.925
                 Params-Util-1.04
                 Data-OptList-0.107
                 Sub-Exporter-0.982
                 Const-Fast-0.010
                 PerlIO-Layers-0.008
                 File-Map-0.52
                 DBD-mysql-4.021
                 Statistics-Descriptive-3.0604
                 Statistics-Histogram-0.2
                 common-sense-3.6
                 Guard-1.022
                 Event-1.20
                 EV-4.11 
                 AnyEvent-7.02
                 Algorithm-Diff-1.1902
                 Text-Diff-1.41
                 Test-Differences-0.61
                 Text-Markdown-1.000031
                 Text-MultiMarkdown-1.000034
                 File-Slurp-9999.19
                 Font-AFM-1.20
                 HTML-Format-2.10
                 );


# Sys-SigAction-0.15
# forks-0.34
#                 Parallel-ForkManager-0.7.9
#                 Parallel-Loops-0.07
#                 IPC-Shareable-0.60
#                 IPC-ShareLite-0.17

foreach $src_name ( @src_names )
{
    $inst_name = $src_name;
    $inst_name =~ s/\-[^-]+$//;
    
    push @descriptions,
    {
        "name" => $inst_name,
        "datatype" => "soft_perl_module",
        "title" => "Perl $inst_name module",
        "src_name" => $src_name,
        "inst_name" => $inst_name,
    };
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PYTHON MODULES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

@src_names = qw (
                 pychecker-0.8.18
                 numpy-1.6.1
);

foreach $src_name ( @src_names )
{
    $inst_name = $src_name;
    $inst_name =~ s/\-[^-]+$//;
    
    push @descriptions,
    {
        "name" => $inst_name,
        "datatype" => "soft_python_module",
        "title" => "Python $inst_name module",
        "src_name" => $src_name,
        "inst_name" => $inst_name,
    };
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> BASE UTILITIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# These are support packages that are perhaps not needed, but are 
# installed to ensure that everything else compiles. Portability
# increases this way.

# GNU utilities,

#                 autoconf-2.61
#                 automake-1.10
#                 zip30
#                 unzip60

@gnu_utils = qw (
                 make-3.80
                 cmake-2.8.8
                 grep-2.6.3
                 tar-1.15.1
                 gzip-1.5
                 bzip2-1.0.5
                 readline-5.0
                 m4-1.4.2
                 bison-2.1
                 flex-2.5.33
                 enscript-1.6.1
                 file-4.24
                 coreutils-8.13
                 findutils-4.2.31
                 gsl-1.15
                 time-1.7
                 pkg-config-0.24
                 wget-1.13
                 curl-7.28.1
                 pcre-8.32
                 parallel-20130222
                 );

#                 libgtextutils-0.6.1

if ( $osname ne "Darwin" )
{
    push @gnu_utils, "tree-1.6.0";    # Fails on Mac, but can live without
    push @gnu_utils, "ncurses-5.9";   # Fails on Mac, but doesnt seem needed
}

foreach $src_name ( @gnu_utils )
{
    $inst_name = $src_name;
    $inst_name =~ s/\-[^-]+$//;
    
    push @gnu_list,
    {
        "name" => $inst_name,
        "title" => "GNU $inst_name",
        "src_name" => $src_name,
        "inst_name" => $inst_name,
        "datatype" => "soft_util",
        "url" => "http://www.fsf.org",
    };
}

# Non-GNU utilities,

@list = ({
#     "title" => "Netpbm graphics converter",
#     "src_name" => "netpbm-990",
#     "url" => "http://netpbm.sourceforge.net",
# },{
#     "title" => "Ghostscript postscript interpreter",
#     "src_name" => "ghostscript-8.70",
#     "url" => "http://pages.cs.wisc.edu/~ghost",
# },{
#     "title" => "Xfig vector drawing",
#     "src_name" => "xfig.3.2.5b",
#     "url" => "http://www.xfig.org",
# },{
#     "title" => "Transfig Xfig converter",
#     "src_name" => "transfig.3.2.5a",
#     "url" => "http://www.xfig.org",
# },{
#     "title" => "Bar graph generator",
#     "src_name" => "bargraph-4.4",
#     "url" => "http://www.burningcutlery.com/derek/bargraph",
# },{
#     "title" => "Gnuplot graph library",
#     "src_name" => "gnuplot-4.4.0",
#     "url" => "http://www.gnuplot.info",
# },{

    "title" => "Function interface library",
    "src_name" => "libffi-3.0.9",
    "url" => "http://sourceware.org/libffi",
},{
    "title" => "Zlib compression library",
    "src_name" => "zlib-1.2.7",
    "url" => "",
},{
    "title" => "JPEG image library",
    "src_name" => "jpeg-6b",
    "url" => "http://www.ijg.org",
},{
    "title" => "Freetype font engine",
    "src_name" => "freetype-2.3.4",
    "url" => "http://www.freetype.org",
},{
    "title" => "PNG image library",
    "src_name" => "libpng-1.2.12",
    "url" => "http://www.libpng.org",
},{
    "title" => "2D graphics library",
    "src_name" => "gd-2.0.36RC1",
    "url" => "http://www.libgd.org",
},{
    "title" => "Expat XML parser",
    "src_name" => "expat-2.0.1",
    "url" => "http://expat.sourceforge.net",
},{
    "title" => "Kyoto Cabinet",
    "src_name" => "kyotocabinet-1.2.76",
    "url" => "http://fallabs.com/kyotocabinet",
},{
    "title" => "Disk information utility",
    "src_name" => "di-4.19",
    "url" => "http://www.gentoo.com/di",
},{
    "title" => "Web server security",
    "src_name" => "openssl-1.0.1e",
    "url" => "http://www.openssl.org",
},{
    "title" => "SFF format conversion",
    "src_name" => "sff2fastq",
    "url" => "https://github.com/indraniel/sff2fastq",
},{
    "title" => "SSH client library",
    "src_name" => "libssh2-1.4.3",
    "url" => "http://www.libssh2.org",
});

foreach $util ( @list )
{
    $inst_name = $util->{"src_name"};
    $inst_name =~ s/\-[^-]+$//;
    
    $util->{"inst_name"} = $inst_name;
    $util->{"name"} = $inst_name;
    $util->{"datatype"} = "soft_util";
};

push @descriptions, @gnu_list, @list;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ANALYSIS PACKAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

@list = ();

if ( $osname ne "Darwin" ) 
{
    push @list, {
        "name" => "simscan",
        "title" => "Sequence similarity, local",
        "description" => "Fast blast-like sequence comparison",
        "inst_name" => "Simscan",
        "src_name" => "qsimscan",
        "methods" => [ "nsimscan", "psimscan" ],
    };
}

push @list, ({
    "name" => "pfold",
    "title" => "RNA structure finding",
    "description" => "Derives comparatively supported RNA secondary structure from alignments",
    "inst_name" => "Pfold",
    "src_name" => "pfold",
},{
    "name" => "blast",
    "title" => "Sequence similarity, local",
    "inst_name" => "Blast",
    "src_name" => "blast-2.2.25",
    "url" => "ftp://ftp.ncbi.nlm.nih.gov/blast/executables/release/2.2.25",
},{
    "name" => "netblast",
    "title" => "Sequence similarity, remote",
    "inst_name" => "NetBlast",
    "src_name" => "netblast-2.2.25",
    "url" => "ftp://ftp.ncbi.nlm.nih.gov/blast/executables/release/2.2.25",
},{ 
    "name" => "blastalign",
    "title" => "Blast output alignment",
    "inst_name" => "BlastAlign",
    "src_name" => "BlastAlign.v1.2",
},{
    "name" => "patscan",
    "title" => "Pattern search",
    "description" => "Flexible sequence pattern match",
    "inst_name" => "Patscan",
    "src_name" => "scan_for_matches",
    "methods" => [ "patscan_nuc", "patscan_prot" ],
},{
    "name" => "muscle",
    "title" => "Sequence alignment",
    "inst_name" => "Muscle",
    "src_name" => "muscle3.6", 
},{
    "name" => "mview",
    "title" => "Alignment formatting",
    "inst_name" => "MView",
    "src_name" => "mview-1.51",
# },{
#     "name" => "yass",
#     "title" => "Sequence similarity, local",
#     "inst_name" => "YASS",
#     "src_name" => "yass-1.14",
},{
    "name" => "emboss",
    "title" => "EMBOSS sequence analysis",
    "inst_name" => "EMBOSS",
    "src_name" => "EMBOSS-6.3.1",
},{
    "name" => "viennarna",
    "title" => "RNA structure programs",
    "inst_name" => "ViennaRNA",
    "src_name" => "ViennaRNA-1.8.4",
},{
#     "name" => "bowtie",
#     "title" => "Fast short read aligner",
#     "inst_name" => "Bowtie",
#     "src_name" => "bowtie-0.10.0.2",
# },{
    "name" => "fastx-toolkit",
    "title" => "FASTQ/A short-reads pre-processing tools",
    "inst_name" => "Fastx-Kit",
    "src_name" => "fastx_toolkit-0.0.13.2",
},{
#     "name" => "cdhit",
#     "title" => "Sequence clustering",
#     "inst_name" => "cdhit",
#     "src_name" => "cdhit-4.5.7",
# },{
    "name" => "uclust",
    "title" => "Sequence clustering",
    "inst_name" => "uclust",
    "src_name" => "uclust1.1.579",
},{
    "name" => "uchime",
    "title" => "Sequence chimera check",
    "inst_name" => "uchime",
    "src_name" => "uchime4.2.40_src",
# },{
#     "name" => "mothur",
#     "title" => "Microbial ecology software",
#     "inst_name" => "Mothur",
#     "src_name" => "Mothur-1.23.1",
});

@list = map { $_->{"datatype"} = "soft_anal"; $_ } @list;

push @descriptions, @list;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    return wantarray ? @descriptions : \@descriptions ;
}
    
1;

__END__

