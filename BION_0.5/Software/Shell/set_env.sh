# 
# BASIC SH ENVIRONMENT
#
# This is just enough to run our scripts. More variables need to be 
# set, but that happens in a shell-independent way from within the 
# programs.
#

# Package home directory,

if [ $home_dir ]; then
    export BION_HOME=$home_dir
elif [ $1 ]; then
    export BION_HOME=$1
else
    export BION_HOME=`pwd`
fi

# Perl path to modules,

for path in $BION_HOME $BION_HOME/Software $BION_HOME/Software/Perl_modules; do
    
    if ! [ $PERL5LIB ]; then 
        PERL5LIB=$path
    elif ( ! echo "$PERL5LIB" | grep "$path" >/dev/null ); then
	PERL5LIB=$path:$PERL5LIB
    fi
    
done

export PERL5LIB
    
# Shell path to scripts,

dir=$BION_HOME/Software

for path in $dir/bin $dir/Perl_scripts $dir/Perl_scripts/Install $dir/Perl_scripts/Admin; do
    
    if ( ! echo "$PATH" | grep "$path" >/dev/null ); then
        PATH=$path:$PATH
    fi
    
done

export PATH

# Shell path to dynamic libraries

path=$BION_HOME/Software/lib

if ! [ $LD_LIBRARY_PATH ]; then 
    LD_LIBRARY_PATH=$path
elif ( ! echo "$LD_LIBRARY_PATH" | grep "$path" >/dev/null ); then
    LD_LIBRARY_PATH=$path:$LD_LIBRARY_PATH
fi

export LD_LIBRARY_PATH

# Set aliases,

alias web_log='tail -f $BION_HOME/Logs/Apache/error_log'
alias web_access='tail -f $BION_HOME/Logs/Apache/access_log'

alias my='mysql --user=mysql --password=mysql'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias .......='cd ../../../../../..'
