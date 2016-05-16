package Recipe::Util;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Various non-IO recipe utility functions that work on recipes.
#
# TODO - some of these routines need improvement
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use feature "state";
use English;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &check_params
                 &check_step
                 &check_step_keys
                 &check_step_needed
                 &check_step_values
                 &create_params
                 &edit_recipe
                 &edit_recipe_list
                 &error_message
                 &find_step
                 &format_stats
                 &list_step_keys
                 &list_steps
                 &parse_recipe
                 &parse_stats
                 &recipe_to_args
                 &set_beg_end
                 &set_file_paths
                 &set_input_indices
);

use Common::Config;
use Common::Messages;

use Registry::Check;

use Recipe::Steps;
use Recipe::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Linwid = $Recipe::Messages::Linwid;
our $Sys_name = $Common::Config::sys_name;
our $Qual_type;
our $Stat_suffix = ".stats";

*AUTOLOAD = \&Common::Obj::AUTOLOAD;

our $Edit_text = qq (Please fix this by editing the recipe. This can be done\n)
               . qq (with 'nano recipe-name' or some other editor.\n);

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub check_params
{
    # Niels Larsen, January 2012.

    # Recursively checks keys and values of a given recipe against the dictionary
    # and maps to command parameters. A parameter structure is returned that 
    # mirrors the recipe structure. 
    
    # TODO improve

    my ( $rcp,
         $rdir,
         $msgs,
        ) = @_;

    # Returns a list.

    my ( $step, $params, $key, $type );

    if ( ref $rcp eq "ARRAY" )
    {
        # List of steps,

        foreach $step ( @{ $rcp } )
        {
            push @{ $params }, &Recipe::Util::check_params( $step, $rdir, $msgs );
        }
    }
    else
    {
        # Single step,

        if ( $type = $rcp->{"quality-type"} )
        {
            $Qual_type = $type;
        }

        $params = &Recipe::Util::check_step( $rcp, $rdir, $msgs );
        
        if ( $rcp->{"steps"} and @{ $rcp->{"steps"} } )
        {
            $params->{"steps"} = &Recipe::Util::check_params( $rcp->{"steps"}, $rdir, $msgs );
        }
    }

    return $params;
}

sub check_step
{
    # Niels Larsen, January 2012.
    
    # Checks a single step. 

    my ( $step,     # Key/value hash
         $rdir,
         $msgs,     # Outgoing error messages - OPTIONAL
        ) = @_;

    # Returns a hash.

    my ( $name, $key, $run, $step_def, $params );

    $name = $step->{"name"};

    # Check parameter fields are valid,

    &Recipe::Util::check_step_keys( $step );

    # Add missing keys from the dictionary,

    $step_def = &Recipe::Steps::get_step( $name );

    foreach $key ( keys %{ $step_def } )
    {
        if ( not exists $step->{ $key } ) 
        {
            $step->{ $key } = $step_def->{ $key }->{"defval"};
        }
    }

    # Check mandatory values,

    &Recipe::Util::check_step_needed( $step );

    # Check values are in range,

    &Recipe::Util::check_step_values( $step );

    # Create a parameter hash that has all routine-required keys. Then apply
    # defaults where the dictionary has a "defval" value. Do value conversions
    # for certain keys,

    if ( $run = $step_def->{"run"} ) {
        $step->{"run"} = &Storable::dclone( $run );
    }

    $params = &Recipe::Util::create_params( $step );

    return $params;
}

sub check_step_keys
{
    # Niels Larsen, April 2013.

    # Checks that the parameter keys in a given step do not have wrong
    # names. Returns nothing, but may print error and exit.

    my ( $step,
        ) = @_;

    # Returns nothing.

    my ( $step_def, $skip_keys, @msgs, $name, $key, $title, $msg, @keys );

    $skip_keys = {
        "name" => 1,
        "steps" => 1,
        "run" => 1,
        "file" => 1,
        "summary" => 1,
    };

    @msgs = ();
    $name = $step->{"name"};

    $step_def = &Recipe::Steps::get_step( $name );

    foreach $key ( keys %{ $step } )
    {
        next if $skip_keys->{ $key };
        
        if ( not exists $step_def->{ $key } )
        {
            if ( $title = $step->{"title"} ) {
                push @msgs, qq ("$key" in step $name ("$title"));
            } else {
                push @msgs, qq ("$key" in step $name);
            }
        }
    }

    if ( @msgs )
    {
        $msg->{"oops"} = qq (Wrong looking parameter keys:);
        $msg->{"list"} = \@msgs;

        @keys = map { "  $_\n" } &Recipe::Steps::list_step_keys( $name );

        $msg->{"help"} = qq (Defined parameter fields are:\n);
        $msg->{"help"} .= "\n". ( join "", @keys ) ."\n";
        $msg->{"help"} .= $Edit_text;

        &Recipe::Messages::oops( $msg );
    }

    return;
}

sub check_step_needed
{
    # Niels Larsen, April 2013.

    my ( $step,
        ) = @_;

    my ( $step_def, @msgs, $name, $key, $chk, $arg, $qtype, $msg, @keys );

    # Complain if mandatory keys are missing or if values are empty,

    @msgs = ();
    $name = $step->{"name"};

    $step_def = &Recipe::Steps::get_step( $name );

    foreach $key ( keys %{ $step_def } )
    {
        $chk = $step_def->{ $key };

        next if not ref $chk;
        next if not ref $chk eq "HASH";

        $arg = $chk->{"arg"};
        
        if ( not exists $step->{ $key } and $chk->{"needed"} )
        {
            push @msgs, qq (Mandatory $step->{"name"} field missing -> "$key");
        }
        elsif ( defined $step->{ $key } ) 
        {
            if ( $step->{ $key } !~ /\S/ )
            {
                push @msgs, qq (Recipe key "$key" must have a value);
            }
            elsif ( $arg and $arg =~ /^(min|max)ch$/ and 
                    not ( $qtype = $step->{"quality-type"} ) and not $Qual_type )
            {
                push @msgs, qq (Quality encoding missing for $step->{"title"});
            }
        }            
    }

    if ( @msgs )
    {
        $msg->{"oops"} = qq (Mandatory parameter keys missing in step $name:);
        $msg->{"list"} = \@msgs;

        @keys = map { "  $_\n" } &Recipe::Steps::list_step_keys( $name );

        $msg->{"help"} = qq (Defined parameter keys are:\n);
        $msg->{"help"} .= "\n". ( join "", @keys ) ."\n";
        $msg->{"help"} .= $Edit_text;

        &Recipe::Messages::oops( $msg );
    }

    return;
}

sub check_step_values
{
    my ( $step,
        ) = @_;

    my ( @msgs, $name, $step_def, $key, $val, $chk, %vals, $msg, @keys, @paths );

    # Complain if values do not fit into requirements and boundaries,

    @msgs = ();
    $name = $step->{"name"};

    $step_def = &Recipe::Steps::get_step( $name );

    foreach $key ( grep { $_ ne "name" and $_ ne "steps" } keys %{ $step } )
    {
        $val = $step->{ $key };
        next if not defined $val;

        $chk = $step_def->{ $key };

        $val =~ s/\%$// if defined $chk->{"minval"} or defined $chk->{"maxval"};

        next if not ref $chk;
        
        # Length check,

        if ( defined $chk->{"minlen"} and length $val < $chk->{"minlen"} ) {
            push @msgs, qq (Key "$key" in "$name" is $val but must be at least $chk->{"minlen"});
        } elsif ( defined $chk->{"maxlen"} and length $val > $chk->{"maxlen"} ) {
            push @msgs, qq (Key "$key" in "$name" is $val but may be at most $chk->{"maxlen"} long);
        }

        # Value range check,

        if ( defined $chk->{"minval"} and $val < $chk->{"minval"} ) {
            push @msgs, qq (Key "$key" in "$name" is $val but must be at least $chk->{"minval"});
        } elsif ( defined $chk->{"maxval"} and $val > $chk->{"maxval"} ) {
            push @msgs, qq (Key "$key" in "$name" is $val but may be at most $chk->{"maxval"});
        }

        if ( @msgs ) 
        {
            $msg->{"oops"} = qq (Values out of range:);
            $msg->{"list"} = \@msgs;
            $msg->{"help"} .= $Edit_text;
            
            &Recipe::Messages::oops( $msg );
        }

        # Wrong value choices,

        if ( defined $chk->{"vals"} )
        {
            %vals = map { $_, 1 } @{ $chk->{"vals"} };
            
            if ( not exists $vals{ $val } ) 
            {
                $msg->{"oops"} = qq (Wrong value for "$key" in "$name": "$val");
                @keys = map { "  $_\n" } sort keys %vals;

                $msg->{"help"} = qq (Choices are:\n);
                $msg->{"help"} .= "\n". ( join "", @keys ) ."\n";
                $msg->{"help"} .= $Edit_text;

                &Recipe::Messages::oops( $msg );
            }
        }

        if ( defined $chk->{"perm"} )
        {
            # Single file check and conversion to absolute path,
            
            # $val = &Common::File::full_file_path( $val, $rdir );
            &Common::File::check_files( [ $val ], $chk->{"perm"}, \@msgs );

            $step->{ $key } = $val;
        }
        elsif ( defined $chk->{"perms"} and not $chk->{"nocheck"} )
        {
            # Multiple file-check and conversion to absolute paths,

            # @paths = map { "$rdir/$_" } split " ", $step->{ $key };
            # &Common::File::full_file_paths( \@paths, \@msgs );

            &Common::File::check_files( \@paths, $chk->{"perm"}, \@msgs );
        }

        if ( @msgs ) 
        {
            $msg->{"oops"} = qq (Problem with "$key" in "$name":);
            $msg->{"list"} = [ map { $_->[1] } @msgs ];
            $msg->{"help"} .= $Edit_text;
            
            &Recipe::Messages::oops( $msg );
        }
    }

    return;
}
    
sub create_params
{
    # Niels Larsen, April 2013.

    # Translates the key/value pairs of a step to a parameter hash that can
    # be fed a given program as arguments or on the command line. Returns a 
    # hash.

    my ( $step,     # Step hash
        ) = @_;

    # Returns a hash.

    my ( $name, $step_def, $params, $run, $key, $chk, $parg, $pval, $qenc, $set,
         @msgs, $msg );

    $name = $step->{"name"};

    $step_def = &Recipe::Steps::get_step( $name );

    if ( $run = $step_def->{"run"} ) {
        $params->{"routine"} = $run->{"routine"};
    } else {
        $params = {};
    }
    
    foreach $key ( keys %{ $step } )
    {
        next if $key eq "run";
        next if $key eq "steps";

        $chk = $step_def->{ $key };
        $parg = $chk->{"arg"};

        next if not $parg;

        $pval = $step->{ $key };
        next if not defined $pval;

        $pval =~ s/\%$// if defined $chk->{"minval"} or defined $chk->{"maxval"};

        if ( $parg eq "minch" or $parg eq "maxch" )
        {
            $qenc = &Seq::Common::qual_config( $step->{"quality-type"} // $Qual_type, \@msgs );
            $pval = &Seq::Common::qual_to_qualch( $pval / 100, $qenc ) if $qenc;
        }
        elsif ( $pval eq "yes" ) {
            $pval = 1;
        } elsif ( $pval eq "no" ) {
            $pval = 0;
        } elsif ( $chk->{"split"} ) {
            $pval = [ map { $_ - 1 } split /\s*[,\s]+\s*/, $pval ];
        }
        
        $params->{ $parg } = $pval;

        if ( $chk->{"set"} )
        {
            foreach $set ( split /\s*;\s*/, $chk->{"set"} )
            {
                $params->{ $1 } = $2 if $set =~ /^([^=]+)=(.+)$/;
            }
        }
    }

    if ( @msgs ) 
    {
        @msgs = map { $_->[1] } @msgs;

        $msg->{"oops"} = qq (Wrong looking quality type:);
        $msg->{"list"} = \@msgs;
        $msg->{"help"} .= $Edit_text;
        
        &Recipe::Messages::oops( $msg );
    }

    return $params;
}

sub edit_recipe
{
    # Niels Larsen, February 2013.

    # Recursive routine that replaces the fields in the given recipe that 
    # match the given list of edits. The edits are hashes with the keys
    # "step", "key", "value" and "regex". The step can be "" and then key
    # and value are used in all steps where key matches. If regex is given
    # instead of value, then a regular expression match is done instead of
    # checking identity. Returns the number of replacements made. The 
    # given recipe is changed. 

    my ( $node,    # Recipe or step hash
         $edit,    # Edit hash made by Recipe::IO::read_recipe_delta
        ) = @_;
    
    # Returns integer.

    my ( @msgs, $key, $name, $v_name, $step, $count );

    $count = 0;

    if ( ref $node eq "ARRAY" )
    {
        foreach $step ( @{ $node } )
        {
            $count += &Recipe::Util::edit_recipe( $step, $edit );
        }
    }
    else
    {
        $v_name = $node->{"name"};    # Names have ".n" version suffixes

        $name = $v_name;
        $name =~ s/\.\d+$//;

        foreach $key ( sort keys %{ $node } )
        {
            if ( $key eq "steps" )
            {
                $count += &Recipe::Util::edit_recipe( $node->{"steps"}, $edit );
            }
            elsif ( not $edit->{"step"} or $v_name eq $edit->{"step"} or $name eq $edit->{"step"} )
            {
                if ( $key eq $edit->{"key"} )
                {
                    $node->{ $key } = $edit->{"value"};
                    
                    $count += 1;
                }
            }
        }
    }
    
    return $count;
}

sub edit_recipe_list
{
    # Niels Larsen, February 2013.
    
    # Updates a recipe with a list of edits and makes errors if edits 
    # do not match. 

    my ( $rcp,         # Recipe structure
         $edits,       # Edits list
        ) = @_;

    # Returns nothing.

    my ( $edit, $count, $str, @msgs, $msg, @keys );

    foreach $edit ( @{ $edits } )
    {
        $count = &Recipe::Util::edit_recipe( $rcp, $edit );
        
        if ( $count == 0 )
        {
            if ( $edit->{"step"} ) {
                $str = $edit->{"step"} .": ";
            } else {
                $str = "";
            }
            
            $str .= $edit->{"key"} ." = ". $edit->{"value"};
            push @msgs, qq (No match with: "$str");
        }
    }

    if ( @msgs )
    {
        $msg->{"oops"} = qq (These delta file lines do not match any recipe line:);
        $msg->{"list"} = \@msgs;

        $msg->{"help"} .= qq (Please fix this by editing the delta file or the recipe.\n);
        $msg->{"help"} .= qq (This can be done with 'nano recipe-name' or other editors.\n);

        &Recipe::Messages::oops( $msg );
    }

    return $rcp;
}

sub find_step
{
    # Niels Larsen, March 2013.
    
    # Returns the step name in a given recipe that matches the given 
    # search-word or expression. Both step names and titles are searched.
    # If there is no match, or multiple matches, a helpful message is 
    # shown and the routine exits. 

    my ( $rcp,    # Recipe structure
         $expr,   # Step name expression
         $fatal,  # Error messages and exit if set - OPTIONAL, default 1
        ) = @_;
    
    # Returns string or nothing.

    my ( @steps, @hits, $hit, $text, @lines, $line, $name, $i );

    $fatal //= 1;

    # Create two-element search list, 

    $i = 0;
    @steps = map {[ $_->{"name"}, $_->{"title"}, $i++ ]} @{ $rcp->{"steps"} };

    # Search names by identity first, then by match,

    @hits = grep { $_->[0] eq $expr .".1" } @steps;

    if ( not @hits ) {
        @hits = grep { $_->[0] =~ /$expr/i } @steps;
    }

    # Search titles too if names did not match,

    if ( not @hits ) {
        @hits = grep { $_->[1] =~ /$expr/i } @steps;
    }

    if ( @hits )
    {
        if ( scalar @hits == 1 )
        {
            # One match, return step name,

            return $hits[0]->[2];
        }
        elsif ( $fatal )
        {
            # Several matches. Show them with search word highlight,

            $text = "-" x $Linwid ."\n\n";
            $text .= "  ". &echo_red_info(" OOPS ") ."  ". qq ("$expr" matches more than one step:\n\n);

            @lines = split "\n", &Common::Tables::render_ascii_usage( \@hits );

            foreach $line ( @lines )
            {
                if ( $line =~ /$expr/ ) {
                    $text .= "    ". $PREMATCH . &echo_bold( $MATCH ) . $POSTMATCH ."\n";
                } else {
                    &error("Programmer error: no match with $expr" );
                }
            }
            
            $text .= "\n  ". &echo_info(" HELP ") ."  ". qq (Please enter a string that match just one name or title.\n);
            $text .= &Common::Messages::support_string;

            $text .= "\n". "-" x $Linwid ."\n";

            &echo( $text );
            exit;
        }
    }
    elsif ( $fatal )
    {
        $name = &File::Basename::basename( $rcp->{"file"} );

        $text = "-" x $Linwid ."\n\n";
        $text .= "   ". &echo_red_info(" OOPS ") ."   ". qq (Step name not found: "$expr"\n\n);
        $text .= "   ". &echo_info(" HELP ") ."   ". &echo("$name has these step and title names:\n\n");
        
        $text .= &Common::Tables::render_ascii_usage(
            \@steps,
            {
                # "highlights" => [ map { $_->[0] } @steps ],
                "highch" => " ",
            });
        
        $text .= "\n   ". &echo_info(" HELP ") ."   ". &echo("Both partial step names and titles can be given.\n");
        
        $text .= &Common::Messages::support_string;

        $text .= "\n". "-" x $Linwid ."\n";
        
        &echo( $text );
        exit;
    }

    return;
}

sub format_stats
{
    # Niels Larsen, March 2013.

    # Formats a given statistics hashes or list of hashes. This structure 
    # has a just a few fixed fields and is not recursive like recipes. 
    # Returns a text string that parses into the same structure expected
    # by this routine.

    my ( $stats,
        ) = @_;

    # Returns a string.

    my ( $text, $hdr, $row, $item, $tab, $stat, $key );

    $text = "";

    if ( ref $stats eq "ARRAY" )
    {
        foreach $stat ( @{ $stats } )
        {
            $text .= &Recipe::Util::format_stats( $stat );
        }
    }
    else
    {
        $stat = $stats;

        $text .= qq (\n<stats>\n\n);
        $text .= qq (   title = $stat->{"title"}\n) if $stat->{"title"};
        $text .= qq (   name = $stat->{"name"}\n) if $stat->{"name"};
        $text .= qq (   summary = $stat->{"summary"}\n) if $stat->{"summary"};

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> HEADERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        foreach $hdr ( @{ $stat->{"headers"} } )
        {
            $text .= qq (\n   <header>\n);
            
            foreach $row ( @{ $hdr->{"rows"} } )
            {
                if ( $row->{"type"} eq "menu" ) 
                {
                    $text .= qq (      <menu>\n);

                    if ( exists $row->{"title"} ) {
                        $text .= qq (         title = $row->{"title"}\n);
                    }
                    
                    foreach $item ( @{ $row->{"items"} } )
                    {
                        $text .= qq (         item = $item->{"value"}\n);
                    }
                    
                    $text .= qq (      </menu>\n);
                }
                elsif ( exists $row->{"title"} ) {
                    $text .= qq (      $row->{"type"} = $row->{"title"}\t$row->{"value"}\n);
                } else {
                    $text .= qq (      $row->{"type"} = $row->{"value"}\n);
                }                    
            }
            
            $text .= qq (   </header>\n);
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        foreach $tab ( @{ $stat->{"tables"} } )
        {
            $text .= qq (\n   <table>\n);

            foreach $key ( keys %{ $tab } )
            {
                if ( $key eq "rows" )
                {
                    foreach $row ( @{ $tab->{"rows"} } )
                    {
                        $text .= qq (      trow = $row->{"value"}\n);
                    }
                }
                else {
                    $text .= qq (      $key = $tab->{ $key }\n);
                }
            }
            
            $text .= qq (   </table>\n);
        }
        
        $text .= qq (\n</stats>\n\n);
    }

    return $text;
}

sub list_step_keys
{
    my ( $name,
        ) = @_;

    my ( $step, $key, @list );

    $name =~ s/\.\d+$//;

    if ( $step = $Recipe::Steps::Step_map{ $name } )
    {
        foreach $key ( keys %{ $step } )
        {
            next if $key eq "run";
            next if $key eq "summary";
            next if $key eq "id";
            next if $key eq "title";

            push @list, $key // "";
        }
    }
    else {
        &error("Step name not in dictionary: $name");
    }
    
    return wantarray ? @list : \@list;
}
    
sub list_steps
{
    # Niels Larsen, March 2013.

    # Returns or prints the steps and titles for a given recipe, as a string.
    # The string has console color codes in it. 

    my ( $rcp,
        ) = @_;

    # Returns string or nothing.

    my ( $name, @steps, $text );

    $name = &File::Basename::basename( $rcp->{"file"} );

    @steps = map {[ $_->{"name"}, $_->{"title"} ]} @{ $rcp->{"steps"} };

    $text = "-" x $Linwid ."\n\n";

    $text .= "  ". &echo_info(" INFO ") ."   ". &echo("Steps and titles for $name are, in recipe order:\n\n");

    $text .= &Common::Tables::render_ascii_usage(
        \@steps,
        {
            # "highlights" => [ map { $_->[0] } @steps ],
            "highch" => " ",
        });
    
    $text .= "\n  ". &echo_info(" INFO ") ."   ". &echo("Both --beg and --end accept partial names or titles.\n");

    $text .= "\n". "-" x $Linwid ."\n";
    
    if ( defined wantarray ) {
        return $text;
    } else {
        &echo( $text );
        exit;
    }

    return;
}
    
sub parse_recipe
{
    # Niels Larsen, Janary 2012.

    # Primitive parser that reads a recipe file nested to any depth. See the 
    # BION/Recipes directory for format examples. 

    my ( $lines,
         $seen,
        ) = @_;

    # Returns a list. 

    my ( $line, @list, $elem, $key, $val, $rcp, $pos, $open_name, $id,
         @msgs, $close_name, $msg );

    # Step open and close format,

    state $open_regex = '\s*<([a-z-]+(?:\.\d+)?)>\s*';
    state $key_regex = '\s*([a-z-0-9]+)\s*=\s*(.*)';
    state $close_regex = '\s*<\/([a-z-]+(?:\.\d+)?)>\s*';

    # Skip leading comments,

    while ( $lines->[0] =~ /^\s*#/ or $lines->[0] !~ /\w/ ) { shift @{ $lines } };

    $id = 0;

    while ( @{ $lines } and $lines->[0] =~ /^$open_regex/ )
    {
        $open_name = $1;

        if ( $open_name !~ /\.\d+/ )
        {
            $seen->{ $open_name } += 1;
            $elem = { "name" => $open_name .".". $seen->{ $open_name } };
        }
        else {
            $elem = { "name" => $open_name };
        }            

        shift @{ $lines };

        while ( $lines->[0] !~ /^$close_regex/ )
        {
            # Skip comments and empty lines,

            if ( $lines->[0] =~ /^\s*#/ or $lines->[0] !~ /\w/ )
            {
                shift @{ $lines };
                next;
            }

            if ( $lines->[0] =~ /^$open_regex/ )
            {
                $rcp = &Recipe::Util::parse_recipe( $lines, $seen );

                if ( ref $rcp eq "ARRAY" ) {
                    push @{ $elem->{"steps"} }, @{ $rcp };
                } else {
                    push @{ $elem->{"steps"} }, $rcp;
                }
            }
            elsif ( $lines->[0] =~ /^$key_regex/ )
            {
                ( $key, $val ) = ( $1, $2 );

                if ( defined $val and $val ne "" )
                {
                    if ( ( $pos = index $val, "#" ) > -1 ) {
                        $val = substr $val, 0, $pos;
                    }

                    $val =~ s/\s*$//;

                    if ( exists $elem->{ $key } )
                    {
                        $elem->{ $key } = [ $elem->{ $key } ] if not ref $elem->{ $key };
                        push @{ $elem->{ $key } }, $val;
                    }
                    else {
                        $elem->{ $key } = $val;
                    }
                }
                else
                {
                    $msg->{"oops"} = qq (Recipe line without a value);
                    $msg->{"list"} = [ $lines->[0] ];
                    $msg->{"help"} = qq (All parameter keys must have some value.\n);

                    if ( exists $elem->{"name"} )
                    {
                        $msg->{"help"} .= qq (To see a list of keys, try the command\n);
                        $msg->{"help"} .= qq ('help_recipe $elem->{"name"}' on the command line.);
                    }
                    
                    &Recipe::Messages::oops( $msg );
                }
                
                shift @{ $lines };
            }
            else
            {
                $msg->{"oops"} = qq (Wrong looking recipe line:);
                $msg->{"list"} = [ $lines->[0] ];
                $msg->{"help"} = qq (Recipe steps and parameters must look like the output\n);
                $msg->{"help"} .= qq (shown with for example the command 'help_recipe chimera'\n);
                $msg->{"help"} .= qq (Please fix this by editing the recipe. This can be done\n);
                $msg->{"help"} .= qq (with 'nano recipe-name' or other editors.\n);
                
                &Recipe::Messages::oops( $msg );
            }
        }

        $lines->[0] =~ /^$close_regex/;
        $close_name = $1;

        if ( $open_name ne $close_name )
        {
            $msg->{"oops"} = qq (Step "$open_name" ends with "$close_name");
            $msg->{"help"} = qq (Step-open and step-close tags must match. They should like\n);
            $msg->{"help"} .= qq (that shown with for example the command 'help_recipe chimera'\n);
                
            &Recipe::Messages::oops( $msg );
        }
        
        $elem->{"id"} = $id++;

        push @list, $elem;

        shift @{ $lines } if $lines;
    }

    if ( scalar @list == 1 ) {
        return $list[0];
    }

    return \@list;
}

sub parse_stats
{
    # Niels Larsen, March 2012.

    # Parses a list of stats lines and returns a list of header and table 
    # hashes. Unlike recipes they have a defined structure so the parser can 
    # be smaller, more rigid and non-recursive. 

    my ( $lines,      # Text or list of lines
         $msgs,       # Message list - OPTIONAL
        ) = @_;

    # Returns a list. 

    my ( @lines, $line, @list, $elem, $menu, $title, @values, $ref, @msgs, 
         $key, $value, $str, $type );

    if ( ref $lines ) {
        @lines = @{ &Storable::dclone( $lines ) };
    } else {
        @lines = split /\n/, $lines;
    }

    @lines = grep { $_ =~ /\w/ and $_ !~ /^\s*(#|<!--)/ } @lines;

    foreach $line ( @lines )
    {
        if ( $line =~ /^\s*<stats>/ )
        {
            $elem = {};
            $ref = undef;
        }
        elsif ( $line =~ /^\s*<\/stats>/ )
        {
            $elem->{"tables"} //= [];
            $elem->{"headers"} //= [];
            
            push @list, &Storable::dclone( $elem );
        }
        elsif ( $line =~ /^\s*<(header|table)>/ )
        {
            $ref = { "type" => $1 };
        }
        elsif ( $line =~ /^\s*<menu>/ )
        {
            $menu = { "type" => "menu" };
        }
        elsif ( $line =~ /^\s*item\s*=\s*(.+)/ )
        {
            push @{ $menu->{"items"} }, { "type" => "item", "value" => $1 };
        }
        elsif ( $line =~ /^\s*<\/menu>/ )
        {
            push @{ $ref->{"rows"} }, &Storable::dclone( $menu );
            undef $menu;
        }
        elsif ( $line =~ /^\s*<\/(header|table)>/ )
        {
            if ( $1 eq "header" ) {
                push @{ $elem->{"headers"} }, &Storable::dclone( $ref );
            } else {
                push @{ $elem->{"tables"} }, &Storable::dclone( $ref );
            }

            undef $ref;
        }
        elsif ( $line =~ /^\s*(title|summary|name|id|type)\s*=\s*(.+)/ )
        {
            if ( $menu ) {
                $menu->{ $1 } = $2;
            } elsif ( $ref ) {
                $ref->{ $1 } = $2;
            } else {
                $elem->{ $1 } = $2;
            }
        }
        elsif ( $line =~ /^\s+(date|time|secs)\s*= *(.+)/ )
        {
            push @{ $ref->{"rows"} }, { "type" => $1, "value" => $2 };
        }
        elsif ( $line =~ /^\s*(colh|rowh|align_columns|color_ramp)\s*= *(.+)/ )
        {
            $ref->{ $1 } = $2;
        }
        elsif ( $line =~ /^\s*(hrow|file|html|dir)\s*= *(.+)/ )
        {
            ( $title, $value ) = split "\t", $2;

            push @{ $ref->{"rows"} }, {"type" => $1, "title" => $title, "value" => $value };
        }
        elsif ( $line =~ /^\s*(trow)\s*= *(.+)/ )
        {
            push @{ $ref->{"rows"} }, {"type" => $1, "value" => $2 };
        }
        else {
            push @msgs, ["ERROR", qq (Wrong looking line -> "$line") ];
        }
    }

    if ( @msgs ) 
    {
        &echo("\n") if not $msgs;
        &append_or_exit( \@msgs, $msgs );
    }

    return \@list;
}

sub recipe_to_args
{
    # To be improved 

    my ( $rcp,
         $args,
        ) = @_;

    my ( $params, $key, $val );

    # &dump( $rcp );
    $params = &Recipe::Util::check_params( $rcp );
    
    # &dump( $params );

    while ( ( $key, $val ) = each %{ $params } )
    {
        next if $key eq "routine";

#        $args->{ $key } = $val unless defined $args->{ $key };
        $args->{ $key } = $val;
    }

    # &dump( $args );

    return $args;
}

sub set_beg_end
{
    # Niels Larsen, June 2012. 

    # Sets begin-step and end-step fields fields from incomplete names given
    # by the user. Checks that begin step comes earlier than end step. 

    my ( $rcp,    # Recipe structure
         $beg,    # Begin step expression - OPTIONAL
         $end,    # End step expression - OPTIONAL
        ) = @_;

    # Returns recipe structure. 

    my ( $name, $beg_ndx, $end_ndx, $beg_name, $end_name, $msg );
    
    if ( defined $beg ) {
        $rcp->{"begin-step"} = &Recipe::Util::find_step( $rcp, $beg );
    } else {
        $rcp->{"begin-step"} = 0;
    }

    if ( defined $end ) {
        $rcp->{"end-step"} = &Recipe::Util::find_step( $rcp, $end );
    } else {
        $rcp->{"end-step"} = $#{ $rcp->{"steps"} };
    }

    if ( ( $beg_ndx = $rcp->{"begin-step"} ) > ( $end_ndx = $rcp->{"end-step"} ) )
    {
        $beg_name = $rcp->{"steps"}->[$beg_ndx]->{"name"};
        $end_name = $rcp->{"steps"}->[$end_ndx]->{"name"};

        $msg->{"oops"} = 
            qq (The begin-name "$beg" matches the step "$beg_name",\n)
           .qq (and the end-name "$end" matches the step "$end_name",\n)
           .qq (but the latter precedes the former.\n);
        
        $msg->{"help"} = 
            qq (Please specify --beg and --end, so that --beg matches an\n)
           .qq (earlier step than --end does. A version number can be added\n)
           .qq (to get the right step among several with the same name,\n)
           .qq (like this example: $beg_name);
        
        &Recipe::Messages::oops( $msg );
    }

    return;
}

sub set_file_paths
{
    # Niels Larsen, March 2013.
    
    # Sets file path expressions for each recipe step. The recipe input files
    # are known, but output file names from the following steps are not always
    # known until after the step has been run. So file expressions are set in
    # this routine so that the 'ls' command can list the files by their suffix.
    # Each step writes to its own uniquely named sub-directory, and reads from
    # the sub-directories of other steps. The 'input-step' key determines which
    # step to get input from; if set to 'recipe-input' then it uses the input 
    # files to the recipe.

    my ( $rcp,       # Recipe
         $args,      # Arguments 
        ) = @_;

    # Returns hash.

    my ( $steps, $step, $istep, $run, $outdir, $outpre, @msgs, $name, $key,
         $files, $copy_list, $in_step, $suffix, $find_step, $in_run, 
         $sub_dirs );

    $outdir = $args->outdir;
    $outpre = $args->outpre;

    $steps = $rcp->{"steps"};

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FOR EACH STEP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    for ( $istep = 0; $istep <= $#{ $steps }; $istep += 1 )
    {
        $step = $steps->[$istep];
        $run = $step->{"run"};

        $suffix = $run->out_suffix;

        # Fields to be set below,

        $run->add_field("in_dir");
        $run->add_field("in_files");
        $run->add_field("out_files");
        $run->add_field("stat_files");

        # Fetch the run-hash of the given input step for use below. Set to 
        # undefined if input is the recipe input,

        if ( not defined $step->{"input-step"} 
             or $step->{"input-step"} eq "recipe-input" )
        {
            $in_run = undef;
        } else {
            $in_run = $steps->[ $step->{"input-step"} ]->{"run"};
        }
        
        # If the current step produces sub-directories, or if the input step
        # did, then set a boolean for use below,

        if ( $run->out_dirs ) 
        {
            $sub_dirs = 1;
        }
        elsif ( defined $in_run and $in_run->out_dirs ) 
        {
            $sub_dirs = 1;
            $run->out_dirs( 1 );
        }
        else {
            $sub_dirs = 0;
        }
        
        # >>>>>>>>>>>>>>>>>>>>>> SET DIRECTORY NAME <<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Construct output directory path from unique step names,

        $step->{"run"}->{"out_dir"} = $outdir ."/". $outpre .".". $step->{"name"};

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> INPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Sets $run->{"in_files"} to a file path or a list of paths. The first
        # step in a recipe always gets the recipe input. The following steps
        # either get the output(s) from the previous step, or the output from
        # last of a named step. 

        if ( $istep == 0 )
        {
            # First step. Set in_files to the file list given to the recipe,
            
            if ( @{ $args->ifiles } )
            {
                if ( ref $args->ifiles ) {
                    $run->in_files( &Storable::dclone( $args->ifiles ) );
                } else {
                    $run->in_files( $args->ifiles );
                }

                $run->in_dir( undef );
            }
            elsif ( not $args->beg and not $args->beg eq $step->{"name"} )
            {
                &error(
                     qq (No command line input given. Programmer error,\n)
                    .qq (should have been checked before getting here.)
                    );
            }
        }
        else
        {
            if ( not defined $step->{"input-step"} 
                 or $step->{"input-step"} eq "recipe-input" )
            {
                # Use the input to the first step as this step's input,

                $run->in_files( &Storable::dclone( $steps->[0]->{"run"}->in_files ) );
            }
            else
            {
                # Use the outputs of a user-requested step as input. If that 
                # step has produced multiple output directories, then let the 
                # file expression cover all these,
                
                $run->in_dir( $in_run->out_dir );
                $run->in_files( $in_run->out_dir ."/*". $in_run->out_suffix );
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        if ( $run->out_multi )
        {
            # Multiple outputs. If this step, or this step's input, produces 
            # output in sub-directories, then the file expression covers those,

            if ( $sub_dirs ) {
                $run->out_files( $run->out_dir ."/*/*". $suffix );
            } else {
                $run->out_files( $run->out_dir ."/*". $suffix );
            }
        }
        else
        {
            # Single file output. Use recipe or configured name it,

            if ( $name = $step->{"output-name"} or $name = $run->out_name )                 
            {
                $run->out_files( $run->out_dir ."/$name$suffix" );
            }
            else {
                &error( qq (No step->output-name or run->out_name for $step->{"name"}\n)
                       .qq (Should never happen, programming error.) );
            }
        }

        # >>>>>>>>>>>>>>>>>>>>>>>>>>> STATISTICS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Methods run in parallel work on one input file, produces one statistics
        # file and one or more output files. Methods run as a single process 
        # produce only one statistics file for all input(s). 

        if ( $run->out_multi )
        {
            if ( $name = $step->{"output-name"} or $name = $run->out_name )
            {
                # $run->stat_files( $run->out_dir ."/$name$Stat_suffix" );
                $run->stat_files( $run->out_dir ."/step$Stat_suffix" );
            }
            elsif ( $run->in_multi )
            {
                $run->stat_files( $run->out_dir ."/*$Stat_suffix" );
                # $run->stat_files( $run->out_dir ."/step$Stat_suffix" );
            }
            else {
                &error( qq (No step->output-name or run->out_name or run->in_multi)
                        .qq (for $step->{"name"}. Should never happen, steps or programming error.) );
            }
        }
        else
        {
            if ( $name = $run->out_name )
            {
                # $run->stat_files( $run->out_dir ."/$name$Stat_suffix" );
                $run->stat_files( $run->out_dir ."/step$Stat_suffix" );
            }
            else {
                &error( qq (No run->out_name for $step->{"name"}\n)
                        .qq (Should never happen, programming error.) );
            }
        }
    }

    return;
}

sub set_input_indices
{
    # Niels Larsen, April 2013.

    # Sets input step indices for every recipe step. By default steps take 
    # input from the previous step, but a "input-step = step name" in the 
    # recipe sets it to that step (which must come before the curren step).
    # The special step name "recipe-input" causes the input step to be 
    # undefined. Returns nothing, but sets the "inut-step" fields in the 
    # recipe. 

    my ( $rcp,      # Recipe
        ) = @_;

    # Returns nothing.

    my ( $steps, $step, $in, $name, $msg, $ndx, $in_ndx, $in_name );

    $steps = $rcp->{"steps"};
    
    for ( $ndx = 0; $ndx <= $#{ $rcp->{"steps"} }; $ndx += 1 )
    {
        $step = $steps->[$ndx];

        # If the input step is defined, then check it for unique matches and 
        # convert to an index. Error and exit if the match is not unique.

        if ( defined ( $in = $step->{"input-step"} ) )
        {
            if ( $in eq "recipe-input" )
            {
                $step->{"input-step"} = undef;
            }
            else
            {
                $in_ndx = &Recipe::Util::find_step( $rcp, $in );

                if ( $in_ndx >= $ndx ) 
                {
                    $name = $step->{"name"};
                    $in_name = $steps->[$in_ndx]->{"name"};
                    
                    $msg->{"oops"} = 
                        qq (The recipe step "$name" has its input-step field set to\n)
                       .qq ("$in" which matches the later step "$in_name".\n);
                    
                    $msg->{"help"} = 
                        qq (Please edit this mistake, input-step fields must refer to preceding\n)
                       .qq (steps, or be set to "recipe-input" to use the recipe's original input.\n);
                    
                    &Recipe::Messages::oops( $msg );
                }
                else {
                    $step->{"input-step"} = $in_ndx;
                }
            }
        }
        else
        {
            if ( $ndx == 0 ) {
                $step->{"input-step"} = undef;
            } else {
                $step->{"input-step"} = $ndx - 1;
            }
        }
    }

    return;
}

1;

__END__

# sub edit_stat_paths
# {
#     # Niels Larsen, March 2013.

#     # Adds a given step directory to a statistics structure, just so 
#     # the links work from the results directory. Returns an updated 
#     # statistics hash.

#     my ( $stats,      # Statistics hash or list of hashes
#          $outdir,
#          $stepdir,     # Base directory to add/replace
#         ) = @_;

#     # Returns a hash.

#     my ( $basedir, $hdr, $tab, $row, @row, $elem, $title, $file, $stat,
#          @stats );

#     if ( ref $stats eq "ARRAY" )
#     {
#         foreach $stat ( @{ $stats } )
#         {
#             push @stats, &Recipe::Util::edit_stat_paths( $stat, $outdir, $stepdir );
#         }

#         return wantarray ? @stats : \@stats;
#     }
#     else
#     {
#         $stat = $stats;

#         $basedir = $stepdir;
#         $basedir =~ s/^$outdir\///;

#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> HEADERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         foreach $hdr ( @{ $stat->{"headers"} } )
#         {
#             foreach $row ( @{ $hdr->{"rows"} } )
#             {
#                 next if $row->{"type"} eq "menu";
                
#                 $file = &File::Basename::basename( $row->{"value"} );

#                 if ( -e "$stepdir/$file" ) {
#                     $row->{"value"} = "$basedir/$file";
#                 } elsif ( -e "$stepdir/$file.zip" ) {
#                     $row->{"value"} = "$basedir/$file.zip";
#                 }
#             }
#         }

#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>> TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
#         foreach $tab ( @{ $stat->{"tables"} } )
#         {
#             foreach $row ( @{ $tab->{"rows"} } )
#             {
#                 chomp $row->{"value"};
#                 @row = split /\t/, $row->{"value"}, -1;
                
#                 foreach $elem ( @row )
#                 {
#                     if ( $elem =~ /^html=([^:]+):(.+)$/ ) 
#                     {
#                         $file = &File::Basename::basename( $2 );
#                         $elem = "html=$1:$basedir/$file";
#                     }
#                     elsif ( $elem =~ /^html=([^\t]+)\t(.+)$/ )
#                     {
#                         $title = $1;
#                         $file = &File::Basename::basename( $2 );
                        
#                         if ( -e "$stepdir/$file" ) {
#                             $elem = "html=$title\t$basedir/$file";
#                         } elsif ( -e "$stepdir/$file.zip" ) {
#                             $elem = "html=$title\t$basedir/$file.zip";
#                         }
#                     }
#                     elsif ( $elem =~ /^file=(\S+)$/ )
#                     {
#                         $file = &File::Basename::basename( $1 );
                        
#                         if ( -e "$stepdir/$file" ) {
#                             $elem = "file=$basedir/$file";
#                         } elsif ( -e "$stepdir/$file.zip" ) {
#                             $elem = "file=$basedir/$file.zip";
#                         }
#                     }
#                 }
                
#                 $row->{"value"} = ( join "\t", @row );
#             }
#         }
#     }

#     return $stat;
# }                    
    
