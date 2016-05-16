package Registry::Args;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Subroutine/method arguments validation module. It was written in an
# attempt to stop calling certain routines with wrong parameter names
# and values. 
#
# check
# create
# number
# out_files
# prog_name
# split_string
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use Common::Config;
use Common::Messages;

use base qw ( Common::Obj );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check
{
    # Niels Larsen, April 2007.

    # Checks type and presence of the arguments in a given argument 
    # hash against simple rules. Example: 
    # 
    #  $args = { "a" => 1, "b" => [1], "c" => {}, "d" => 2 };
    #  &Registry::Args::check( $args, { "S:1" => ["a","d"], "AR:0" => "b", "HR:1" => "c" } );
    # 
    # This means "a" is a required plain scalar, "b" is an optional
    # array reference and "c" a required hash reference. Errors are 
    # fatal unless a third list argument is given that will then contain
    # [ "ERROR", $message ] tuples. Returned is a Registry::Args 
    # object with the argument key/values set: attempts to use other
    # keys on this object will then cause error. Should not be used
    # for small often-called routines.

    my ( $args,       # Arguments hash
         $reqs,       # Requirements, list or hash
         $msgs,       # Outgoing message list - OPTIONAL
         ) = @_;

    # Returns a Registry::Args object.

    my ( @types, %types, $typ_str, $typ_expr, $fmt_expr, %lookup, $key, 
         $arg_fmt, $arg_list, $arg, $type, $presence, @msgs, $obj_expr, 
         $req_type, $arg_ref, $req_ref, $msg, $arg_type, $arg_text, 
         $req_text, $req_val, $arg_val );

    if ( not $args or not $reqs ) {
        &error( qq (Missing arguments hash or missing requirements list/hash.) );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>> ARGUMENT TYPES <<<<<<<<<<<<<<<<<<<<<<<<<<<

    @types = (
        [ "S" => "", "a plain value" ],
        [ "SR" => "SCALAR", "a scalar reference" ],
        [ "AR" => "ARRAY", "an array reference" ],
        [ "HR" => "HASH", "a hash reference" ],
        [ "R" => "REF", "a reference" ],
        [ "C" => "CODE", "a code reference" ],
        [ "G" => "GLOB", "a glob" ],
        [ "L" => "LVALUE", "an lvalue routine" ],
        [ "O" => "OBJECT", "an object" ],
        );
    
    # >>>>>>>>>>>>>>>>>>>>>>>>> DUMP ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<

    # The -help keyword dumps the required arguments and aborts. This 
    # avoids finding the function in its module and looking for the 
    # arguments,

    if ( exists $args->{"-help"} or exists $args->{"--help"} )
    {
        require Registry::List;
        Registry::List->list_args( $reqs, \@types );
        exit;
    }
    elsif ( exists $args->{"-dump"} or exists $args->{"--dump"} ) {
        &dump( $args );
        exit;
    }

    local $Storable::Deparse = 1;
    local $Storable::Eval = 1;

    $args = &Storable::dclone( $args ); 

    # >>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENT SYNTAX <<<<<<<<<<<<<<<<<<<<<<<<<

    # Syntax of type abbreviations, like "AR:1", where left of colon 
    # is datatype and right is 0 for optional, 1 for required, 2 for 
    # defined,
    
    $fmt_expr = '^([A-Z]+):([012])$';
    $typ_expr = join "|", map { $_->[0] } @types;

    # Strings printed in messages below,

    $typ_str = (join qq (", "), map { qq ($_->[0] ($_->[2])) } @types );

    # >>>>>>>>>>>>>>>>>>>>>>>> CREATE LOOKUP HASH <<<<<<<<<<<<<<<<<<<<<<<<

    # Create hash with argument name as keys and hashes as values. Each
    # value has the keys "type" and "presence". A simple argument list
    # is converted to type = "S" and "presence" = 1,

    %types = map { $_->[0] => $_->[1] } @types;

    if ( ref $reqs eq "ARRAY" )
    {
        $reqs = { "S:1" => $reqs };
    }

    foreach $arg_fmt ( keys %{ $reqs } )
    {
        if ( $arg_fmt =~ /$fmt_expr/o )
        {
            ( $type, $presence ) = ( $1, $2 );
            
            if ( $type =~ /^$typ_expr$/o )
            {
                $arg_list = $reqs->{ $arg_fmt };
                
                if ( defined $arg_list )
                {
                    $arg_list = [ $arg_list ] if not ref $arg_list;
                    
                    foreach $arg ( @{ $arg_list } )
                    {
                        $lookup{ $arg } = { "type" => $types{ $type }, "presence" => $presence };
                    }
                }
                else {
                    &error( qq (No arguments given for type -> "$arg_fmt".) );
                }
            }
            else {
                &error( qq (Wrong looking type specification -> "$type".\n)
                                        . qq ( (Choices: "$typ_str").) );
            }
        }
        else {
            &error( qq (Wrong looking argument specification -> "$arg_fmt".)
                                    . qq ( It must match the expression '$fmt_expr'.) );
        }
    }                

    # >>>>>>>>>>>>>>>>>>>>>> CHECK GIVEN ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<

    # Loop through the given arguments and check their types and values 
    # against the given requirements, as held by the lookup hash above,

    %types = map { $_->[1] => [ $_->[0], $_->[2] ] } @types;

    foreach $key ( keys %{ $args } )
    {
        $arg_ref = ref $args->{ $key };
        $req_ref = exists $lookup{ $key } ? $lookup{ $key }->{"type"} : undef;
 
        if ( defined $req_ref ) 
        {
            # We get here when the argument key is among those required.

            if ( exists $types{ $arg_ref } ) {
                ( $arg_type, $arg_text ) = @{ $types{ $arg_ref } };
            } else {
                ( $arg_type, $arg_text ) = ( $arg_ref, "an object ($arg_ref)" );
            }

            $req_type = $types{ $req_ref }->[0];

            if ( $req_type ne "O" and $req_type ne $arg_type )
            {
                $req_text = $types{ $req_ref }->[1];
                push @msgs, qq (Argument "$key" should be $req_text, but is $arg_text.);
            }

            # Test for empty or undefined when asked not to be,

            $req_val = $lookup{ $key }->{"presence"};

            if ( $req_val == 2 )
            {
                $arg_val = $args->{ $key };

                if ( not defined $arg_val )
                {
                    push @msgs, qq (Argument "$key" has undefined value.);
                }
                else
                {
                    if ( not $arg_ref and $arg_val eq "" or
                         $arg_ref =~ /^SCALAR|REF$/ and not ${ $arg_val } or
                         $arg_ref eq "HASH" and not %{ $arg_val } or
                         $arg_ref eq "ARRAY" and not @{ $arg_val } or
                         $arg_ref eq "HASH" and not %{ $arg_val } or
                         $arg_ref =~ /^CODE|GLOB|LVALUE$/ )
                    {
                        $msg = $arg_ref ? $arg_ref : "PLAIN";
                        push @msgs, qq (Argument "$key" ($msg) is defined but empty.);
                    }
                }
            }
        }
        else
        {
            $msg = join qq ("\n         "), ( sort keys %lookup );
            push @msgs, qq (Wrong looking argument -> "$key".\n\nChoices: "$msg".);
        }
    }

    # >>>>>>>>>>>>>>>>>>>>> CHECK FOR MISSING ARGUMENTS <<<<<<<<<<<<<<<<<<<

    # See if any of the required arguments are not given,

    foreach $key ( keys %lookup )
    {
        if ( not exists $args->{ $key } )
        {
            $args->{ $key } = undef;

            if ( $lookup{ $key }->{"presence"} )
            {
                push @msgs, qq (Required argument "$key" is missing.);
            }
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>> DISPLAY MESSAGES IF ANY <<<<<<<<<<<<<<<<<<<<<

    # If $msgs given return them there, otherwise print messages and die,

    if ( @msgs )
    {
        if ( defined $msgs )
        {
            push @{ $msgs }, map { [ "ERROR", $_ ] } @msgs;
        }
        else {
            &error( \@msgs );
        }
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> RETURN OPTIONAL OBJECT <<<<<<<<<<<<<<<<<<<<

    # If there are no problems and caller wants something back, return the
    # arguments as a Registry::Args object,

    if ( defined wantarray and not @msgs )
    {
        return bless $args, __PACKAGE__;
    }
    else {
        return;
    }
}

sub create
{
    # Niels Larsen, September 2009.

    # Creates an argument object with the keys supplied, plus those of the 
    # default, also given. The datatypes accept are determined by what the 
    # default values are set to. 

    my ( $args,         # Arguments
         $defs,         # Default arguments - OPTIONAL
        ) = @_;

    # Returns a __PACKAGE__ object. 

    my ( $key, $keystr, $val, $obj, %check, $acc, %defs );

    if ( defined $defs )
    {
        # From the supplied defaults, create a hash which the supplied arguments 
        # must agree with,
    
        while ( ($keystr, $val) = each %{ $defs } )
        {
            # Create %defs from the defaults with keys without :[123] notation,
            # so they can be merged with the given arguments below,
            
            if ( $keystr =~ /^([a-z_0-9]+)(?::([012]))?$/ ) {
                ( $key, $acc ) = ( $1, $2 || 0 );
            } else {
                &error( qq (Wrong looking key -> "$keystr") );
            }
            
            $defs{ $key } = $val;
            
            # Create the hash that specifies the checking requirements,
            
            if ( ref $val )
            {
                if ( ref $val eq "ARRAY" ) {
                    push @{ $check{"AR:$acc"} }, $key;
                } elsif ( ref $val eq "HASH" ) {
                    push @{ $check{"HR:$acc"} }, $key;
                } elsif ( ref $val eq "CODE" ) {
                    push @{ $check{"C:$acc"} }, $key;
                } else {
                    push @{ $check{"O:$acc"} }, $key;
                }
            }
            else {
                push @{ $check{"S:$acc"} }, $key;
            }
        }
        
        # Merge,
        
        $args = &Common::Util::merge_params( $args, \%defs );
        
        # Check,
        
        $obj = &Registry::Args::check( $args, \%check );
    }
    else
    {
        $obj = $args;
        bless $obj, __PACKAGE__;
    }

    return $obj;
}

sub check_number
{
    # Niels Larsen, February 2010. 

    # Checks a given string for being a number, within bounds if given. 
    # Returns the number given.

    my ( $num,         # Number
	 $min,         # Lower bound
	 $max,         # Upper bound
	 $msgs,        # Outgoing messages
	) = @_;

    # Returns integer. 

    if ( &Scalar::Util::looks_like_number( $num ) )
    {
	if ( defined $min and $num < $min ) {
	    push @{ $msgs }, [ "ERROR", qq (Number less than minimum, $num < $min) ];
	} 

	if ( defined $max and $num > $max ) {
	    push @{ $msgs }, [ "ERROR", qq (Number larger than maximum, $num > $max) ];
	} 
    }
    else {
	push @{ $msgs }, [ "ERROR", qq (Not a number -> $num) ];
    }

    return $num;
}
    
sub expand_file_paths
{
    # Niels Larsen, February 2010.

    # Converts a given comma-separated string of file paths with wildcards to 
    # a list of full file paths. Errors are either returned or written to STDERR.

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

        if ( $stderr )
        {
            $msg = ["ERROR", qq (Wrong looking path -> "$path") ];

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

    return wantarray ? @paths : \@paths;
}

sub out_files
{
    # Niels Larsen, February 2010. 

    # TODO - bad routine, replace.

    my ( $ifiles,
         $osuffix,
         $ofile,
         $msgs,
        ) = @_;

    my ( @ofiles );

    if ( $ifiles and @{ $ifiles } ) 
    {
        if ( scalar @{ $ifiles } == 1 and $ofile )
        {
            @ofiles = &Common::File::check_files( [ $ofile ], "!e", $msgs );
        }
        else
        {
            @ofiles = &Common::File::check_files( [ map { $_ . $osuffix } @{ $ifiles } ], "!e", $msgs );

            if ( $ofile and scalar @{ $ifiles } > 1 ) {
                push @{ $msgs }, ["ERROR", "Single output file can only be given with a single input file"];
            }
        }
    }
    elsif ( $ofile ) {
        @ofiles = &Common::File::check_files( [ $ofile ], "!e", $msgs );
    }

    return wantarray ? @ofiles : \@ofiles;
}

sub prog_name
{
    my ( $name,
	 $names,
	 $msgs,
	) = @_;

    my ( %names, $choices );

    %names = map { $_, 1 } @{ $names };

    if ( not defined $name )
    {
        push @{ $msgs }, ["ERROR", qq (No program name given) ];
    }
    elsif ( not exists $names{ $name } )
    {
        $choices = join ", ", @{ $names };
	push @{ $msgs }, ["ERROR", qq (Wrong looking program name -> "$name". Choices: $choices) ];
    }
    
    return $name;
}

sub split_string
{
    # Niels Larsen, September 2010.

    # Splits a comma- or blank-separated argument string into a list.

    my ( $str,
        ) = @_;

    # Returns a list.

    my ( @str );

    if ( not @str = split /\s*[, ]\s*/, $str ) {
        &error( qq (Could not split argument string -> "$str") );
    }

    return wantarray ? @str : \@str;
}

1;

__END__
