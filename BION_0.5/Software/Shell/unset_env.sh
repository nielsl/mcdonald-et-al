#!/bin/sh

# 
# UNSET BASIC SH ENVIRONMENT
#
# Deletes the variable additions done by set_env.sh.
#

# Perl path to our modules,

for path in $BION_HOME/Software/Perl_modules ":$BION_HOME/Software" ":$BION_HOME"; do

    PERL5LIB=`echo $PERL5LIB | sed -e "s%$path%%"`

done

# Shell path to our scripts,

dir=$BION_HOME/Software

for path in $dir/Perl_scripts/Install $dir/Perl_scripts/Admin $dir/Perl_scripts $dir/bin; do

    PATH=`echo $PATH | sed -e "s%$path:%%"`

done

# Shell path to dynamic libraries,

for path in $BION_HOME/Software/lib; do

    LD_LIBRARY_PATH=`echo $LD_LIBRARY_PATH | sed -e "s%$path:%%"`
    LD_LIBRARY_PATH=`echo $LD_LIBRARY_PATH | sed -e "s%$path%%"`

done

# Package home directory,

BION_HOME=""

export BION_HOME
export PERL5LIB
export PATH
