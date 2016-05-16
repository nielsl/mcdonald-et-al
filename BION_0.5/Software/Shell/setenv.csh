
# UNFINISHED

setenv BION_HOME `pwd`

if ( $PERL5LIB != "" ) then
    setenv PERL5LIB $BION_HOME/Software/Perl_modules:$PERL5LIB
else
    setenv PERL5LIB $BION_HOME/Software/Perl_modules
endif

setenv PATH $BION_HOME/Software/Perl_scripts/Install:$PATH
