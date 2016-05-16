#!/usr/bin/env bash

if [ `which perl` ]; then 

    inst_dir=Software/Perl_scripts/Install

    # >>>>>>>>>>>>>>>>>>>>>>>>> SET ENVIRONMENT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Set a minimal environment that defines BION_HOME, sets or appends to
    # PERL5LIB and PATH. Just enough that our modules can be found (they will 
    # then set the rest),

    if ! [ $BION_HOME ]; then

	# BUG or me not understanding shell: inside the following script $1
	# has the value of $1 from this script, rather than the value of its
	# first argument - why?
	
	home_dir=`pwd`; . Software/Shell/set_env.sh home_dir
        print_message=1
        
    fi

    # >>>>>>>>>>>>>>>>>>>>> INSTALL PERL IF NEEDED <<<<<<<<<<<<<<<<<<<<<<<<<<

    # Install the bundled perl if the detected perl is older than required
    # and the bundled perl has not been installed already. If there is 
    # nothing to do, it returns with exit 0,

    $inst_dir/install_perl_if_needed $@

    # If errors, dont continue,

    if [ $? -gt 0 ]; then
        exit 0
    fi
    
    # >>>>>>>>>>>>>>>>> INSTALL PERL MODULES IF NEEDED <<<<<<<<<<<<<<<<<<<<<<

    # Install all bundled non-standard modules in Software/{lib,share,man},

    $inst_dir/install_modules_if_needed $@

    # If errors, dont continue,

    if [ $? -gt 0 ]; then
        exit 0
    fi
    
    # >>>>>>>>>>>>>>>>>>>>>> PASS ON TO INSTALLER <<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Forward all command line arguments to the perl-based installer. This
    # installs Apache, database, utilities and analysis programs, 

    $inst_dir/install_software $@

    errcode=$?

    # >>>>>>>>>>>>>>>>>>>>>>>>> PRINT MESSAGE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # This section says: if install completed without error, and --silent 
    # are not among the command line arguments, then print a completion 
    # message which explains how to activate environment variables etc. 

    cmdline1=$@
    cmdline2=${cmdline1//-silent/}
    
    cmdlen1=${#cmdline1}
    cmdlen2=${#cmdline2}
	
    if [ $errcode -gt 0 ]; then
	exit 0
    elif [ "$*" ] && [ $print_message ] && [ $cmdlen1 -eq $cmdlen2 ]; then
        $inst_dir/print_setenv_message
    fi
    
else

    echo ""
    echo " Problem"
    echo " -------"
    echo ""
    echo " Perl is not found, and the installer for this package is perl-based. It"
    echo " may seem silly to require perl for installation of perl (the bundled one)"
    echo " but so it is at the moment. Please activate perl 5.6 or later, get it"
    echo " from http://www.perl.org/get.html for example. It can be installed for"
    echo " this user only, or system-wide, and will not be needed when this package"
    echo " is installed. Please update \$PATH so the shell can run it. If needed,"
    echo " contact a person who knows Unix-style shells for help with this."
    echo ""
    echo " We believe this is a rare occurrence and are interested in knowing which"
    echo " kinds of systems do not come with Perl. You are welcome to notify" 
    echo ""
    echo " Niels Larsen"
    echo " Danish Genome Institute"
    echo " niels@genomics.dk"
    echo ""
    echo " It would be especially helpful if you know if the machine came without"
    echo " Perl originally or had Perl removed later."
    echo ""

fi
