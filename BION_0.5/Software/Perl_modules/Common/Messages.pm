package Common::Messages;     #  -*- perl -*-

# Functions that handle interrupts, compile errors, runtime errors and warnings,
# and outputs corresponding messages, in either the browser or on STDERR if run 
# from the command line. A traceback table is included by default. This makes it 
# easier to track and fix errors, since enough information is usually shown to 
# fix the error. The exported "dump" routine will also sense if being run by a 
# web server or not, and can be used as a web print statement, which always 
# appears at the top of the browser window.
# 
# Error handling with fail if there are compile errors in 
#
# Common::Config
# Common::Messages
# Common::States
# Common::Widgets
# Common::Tables
#
# because routines from there is needed for the handling. Then there will be 
# either unformatted text in the browser, or "Internal server error" and the 
# error will be in the log. Another tip is to run WWW-root/index.cgi from 
# the command line with no arguments.
#
# TODO: many of these routines are very old and need work

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

use Common::Config;

BEGIN
{
    sub is_run_by_web_server
    {
        # Niels Larsen, March 2003.
        
        # Returns true if calling program is run by a web server, false
        # otherwise. The routine simply looks at one or more environment
        # variables that web servers usually set. 
        
        # Returns a boolean.

        # &dump( \%ENV );
        
        if ( $ENV{"GATEWAY_INTERFACE"} ) {
            return 1;
        } else {
            return;
        }
    }

    if ( &is_run_by_web_server() ) 
    {
        require HTTP::Date;
        require Common::Widgets;
    }
};

# use Common::Tables;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EXPORTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

@EXPORT = qw (
              &append_or_exit
              &done_string
              &dump
              &dump_cgi
              &dump_env
              &echo
              &echo_bold
              &echo_bold_cyan
              &echo_cyan
              &echo_done
              &echo_green
              &echo_green_number
              &echo_info
              &echo_info_green
              &echo_messages
              &echo_oops
              &echo_or_append
              &echo_red
              &echo_red_info
              &echo_yellow
              &error
              &support_string
              &time_elapsed
              &time_start
              &user_error
              &warning
              );

@EXPORT_OK = qw (
                 &colorize_key
                 &error_hash
                 &format_contacts
                 &format_contacts_for_browser
                 &format_contacts_for_console
                 &html_header
                 &http_header
                 &interrupt
                 &interrupt_for_console
                 &is_run_by_console
                 &is_run_by_web_server
                 &is_run_by_web_server_modperl
                 &legal_message
                 &make_time_string
                 &print_errors
                 &print_usage_and_exit
                 &require_module
                 &set_die_handler
                 &set_warning_handler
                 &set_interrupt_handler
                 &stack_trace
                 &stack_trace_ascii
                 &stack_trace_html
                 &system_error_for_browser
                 &system_error_for_browser_css
                 &system_error_for_console
                 &user_error_for_console
                 );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> GLOBALS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

our $Http_header_sent;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> SIGNAL HANDLERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# The following replaces the default die, warning and interrupts with functions
# that produce trace output for browsers and terminals (depending whether run 
# by Apache or from the command line). 
#
# Some included packages (like bioperl) have their own error handlers; to use 
# them rather than those in here, localize and undefine these where needed; if 
# this is not done, their handler messages and stacktrace will just appear as 
# error text, which is no problem either, maybe even better. 

&set_die_handler;
&set_warning_handler;

$SIG{INT} = &set_interrupt_handler;

#$SIG{PIPE} = sub {
#    my $sig = shift @_;
#    print " Caught SIGPIPE: $sig\n";
#    exit(1);
#};

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> EXPORTED ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub block_public_calls
{
    # Niels Larsen, May 2009.

    # Dies if the parent function is called from outside the given module.

    my ( $pkg,
        ) = @_;

    # Returns nothing.

    my ( $callpkg, $callsub );

    $callpkg = (caller(1))[0];
    $callsub = (caller(1))[3];

    if ( not $pkg eq $callpkg ) {
        &error( qq (The $callsub routine may be called from the $pkg package only) );
    }

    return;
}

sub done_string
{
    # Niels Larsen, January 2011.
    
    # Converts strings like "5472 consens[us|es], 35629 sequence[s]" to 
    # "5,472 consenses, 35,629 sequences". 

    my ( $str,
        ) = @_;

    # Returns string. 

    my ( @str, $i, $num, $numndx, $single, $plural );
    
    @str = split / /, $str;

    for ( $i = 0; $i <= $#str; $i += 1 )
    {
        if ( $str[$i] =~ /^\d+$/ )
        {
            $numndx = $i;
        }
        elsif ( $str[$i] =~ /\[([^|]+)\|([^|]+)\]/ )
        {
            ( $single, $plural ) = ( $1, $2 );
            
            if ( $str[$numndx] == 0 )
            {
                $str[$numndx] = "no";
                $str[$i] =~ s/\[.+\]/$plural/;
            }                
            else
            {
                if ( $str[$numndx] > 1 ) {
                    $str[$i] =~ s/\[.+\]/$plural/;
                } else {
                    $str[$i] =~ s/\[.+\]/$single/;
                }
            }
        }
        elsif ( $str[$i] =~ /\[([^\]]+)\]/ )
        {
            $plural = $1;
            
            if ( $str[$numndx] == 0 )
            {
                $str[$numndx] = "no";
                $str[$i] =~ s/\[.+\]//;
            }
            else
            {
                if ( $str[$numndx] > 1 ) {
                    $str[$i] =~ s/\[.+\]/$plural/;
                } else {
                    $str[$i] =~ s/\[.+\]//;
                }
            }
        }
    }

    for ( $i = 0; $i <= $#str; $i += 1 )
    {
        if ( $str[$i] =~ /^\d+$/ ) {
            $str[$i] = &Common::Util::commify_number( $str[$i] );
        }
    }

    return join " ", @str;
}

sub dump
{
    # Niels Larsen, May 2005.

    # Uses Data::Dumper to output a data structure. If in web context,
    # text is printed within <pre> tags. A http header is printed if it
    # was not already printed by another dump statement. 

    my ( $ref,    # Reference to any data structure
         $name,   # Name to be printed - OPTIONAL 
         ) = @_;

    # Returns text or prints in void context. 

    $name ||= "Data";

    my ( $output, $by_web_server );

    return if not $Common::Config::with_console_messages;

    require Data::Dumper;

    local $Common::Config::silent = 0;

    $output = "";

    if ( $by_web_server = &Common::Messages::is_run_by_web_server ) 
    {
        $output = &Common::Messages::http_header();
        print $output;
        $output .= "<pre>\n";
        $output .= join "\n", Data::Dumper->Dump( [$ref], ["*$name"] );
        $output .= "</pre>\n";
    }
    else
    {
        $output .= join "\n", Data::Dumper->Dump( [$ref], ["*$name"] );
    }

    if ( defined wantarray ) {
        return $output;
    } elsif ( $by_web_server ) {
        print $output;
    } else {
        print STDERR $output;
    }
    
    # This makes dump messages errors if not run from a terminal,
    
    if ( not $by_web_server ) {
        # exit -1 if not -t STDIN;
    }

    return;
}

sub dump_cgi
{
    # Niels Larsen, May 2005.

    # Returns or prints a listing of the parameters and values of the 
    # given CGI.pm object. 

    my ( $cgi,
         ) = @_;

    # Returns list or nothing. 

    my ( @xhtml, $key );

    if ( not $cgi ) {
        &error( qq (No CGI.pm object given) );
    }

    @xhtml = ();

    push @xhtml, qq (<p><hr></p>\n);
    push @xhtml, qq (<h3>CGI parameters and values:</h3>\n);
    
    push @xhtml, $cgi->Dump;
    push @xhtml, "\n";

    push @xhtml, qq (<p><hr></p>\n);

    if ( defined wantarray )
    {
        return wantarray ? @xhtml : \@xhtml;
    }
    else {
        unshift @xhtml, &Common::Messages::http_header();
        print @xhtml;
    }

    return;
}

sub dump_env
{
    # Niels Larsen, May 2005.

    # Returns or prints keys and values of the %ENV hash.

    # Returns list or nothing.

    my ( @xhtml, $key );

    @xhtml = ();

    push @xhtml, qq (<p><hr></p>\n);
    push @xhtml, qq (<h3>Environment variables (\%ENV):</h3>\n);

    push @xhtml, join "<br>\n", map { qq (<b>$_</b> $ENV{"$_"}) } sort keys %ENV;

    push @xhtml, qq (<p><hr></p>\n);    

    if ( defined wantarray )
    {
        return wantarray ? @xhtml : \@xhtml;
    }
    else {
        unshift @xhtml, &Common::Messages::http_header();
        print @xhtml;
    }

    return;
}

sub contact_list
{
    my ( $info, @list );

    $info = &Common::Config::get_contacts();

    @list = (
        "        $info->{'first_name'} $info->{'last_name'}",
        " Skype: $info->{'skype'} (often on)",
        "Mobile: $info->{'telephone'} (GMT+1)",
        "E-mail: $info->{'e_mail'}",
        );

    @list = map {[ "Contact", $_ ]} @list;

    return wantarray ? @list : \@list;
}

sub help_list
{
    my ( @list );

    @list = (
        "All are welcome to report errors at any level. This is best",
        "done by re-running with the --debug option and then e-mail",
        "the archive created, as the --debug option will explain",
        );

    @list = map {[ "Help", $_ ]} @list;

    return wantarray ? @list : \@list;
}

sub support_list
{
    # Niels Larsen, March 2013.
    
    my ( $info, @list );

    $info = &Common::Config::get_contacts();

    @list = (
        "Sites with a paid support agreement may contact us for any",
        "reason. We will fix errors quickly, discuss the data, and",
        "extend the package in needed directions",
        );

    @list = map {["Support", $_ ]} @list;
    
    return wantarray ? @list : \@list;
}

sub support_string
{
    # Niels Larsen, March 2013.
    
    my ( $info, $high, $text );

    $info = bless &Common::Config::get_contacts();
    
    $high = &echo_green("Support");
    
    $text = "\n";
    $text .= "  $high  All are welcome to report errors at any level. This is best\n";
    $text .= "  $high  done by re-running with the --debug option and then e-mail\n";
    $text .= "  $high  the archive created, the --debug option will explain. Sites\n";
    $text .= "  $high  with a support agreement may contact us for any reason.\n";
    $text .= "  $high  Contact person:\n";
    $text .= "  $high\n";
    $text .= "  $high          $info->{'first_name'} $info->{'last_name'}\n";
    $text .= "  $high   Skype: $info->{'skype'} (often on)\n";
    $text .= "  $high  Mobile: $info->{'telephone'} (GMT+1)\n";
    $text .= "  $high  E-mail: $info->{'e_mail'}\n";

    return $text;
}

sub time_elapsed
{
    # Niels Larsen, October 2006.
    
    # Returns or prints the number of seconds since last given time.
    
    my ( $start,
         $text,
         ) = @_;
    
    my ( $stop, $diff );

    require Time::HiRes; #  qw( gettimeofday tv_interval usleep );

    $stop = [ &Time::HiRes::gettimeofday() ];

    if ( $start ) {
        $start = [ $start ] if not ref $start;
        $diff = &Time::HiRes::tv_interval( $start, $stop );
    } else {
        $diff = &Time::HiRes::tv_interval( [ $Common::Config::time_secs ], $stop );
    }

    if ( defined wantarray ) {
        return $diff;
    } else
    {
        $text = "seconds" if not defined $text;
        &dump( "$text: $diff" );
    }

    return;
}

sub time_start
{
    # Niels Larsen, October 2006.
    
    # Returns or sets starting time.
    
    my ( $start );

    require Time::HiRes; #  qw( gettimeofday tv_interval usleep );

    $start = &Time::HiRes::gettimeofday();
    
    if ( defined wantarray ) {
        return $start;
    } else {
        $Common::Config::time_secs = $start;
    }

    return;
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EXPORT OK ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<

sub colorize_key
{
    my ( $key, 
        ) = @_;

    my ( $ckey );

    if ( $key =~ /error/i ) {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold red" } );
    } elsif ( $key =~ /oops/i ) {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold white on_yellow" } );
    } elsif ( $key =~ /warning/i ) {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold yellow" } );
    } elsif ( $key =~ /submitted|success/i or $key =~ /^ok$/i or $key =~ /results/i ) {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold green" } );
    } elsif ( $key =~ /results/i ) {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold green" } );
    } elsif ( $key =~ /info|tip|ok|advice|next|todo|help|contact/i ) {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold white on_blue" } );
    } elsif ( $key =~ /support/i ) {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold white on_green" } );
    } else {
        $ckey = &Common::Tables::ascii_style( $key, { "color" => "bold" } );
    }

    return $ckey;
}

# #!/bin/bash
# #
# #   This file echoes a bunch of color codes to the 
# #   terminal to demonstrate what's available.  Each 
# #   line is the color code of one forground color,
# #   out of 17 (default + 16 escapes), followed by a 
# #   test use of that color on all nine background 
# #   colors (default + 8 escapes).
# #

# T='gYw'   # The test text

# echo -e "\n                 40m     41m     42m     43m\
#      44m     45m     46m     47m";

# for FGs in '    m' '   1m' '  30m' '1;30m' '  31m' '1;31m' '  32m' \
#            '1;32m' '  33m' '1;33m' '  34m' '1;34m' '  35m' '1;35m' \
#            '  36m' '1;36m' '  37m' '1;37m';
#   do FG=${FGs// /}
#   echo -en " $FGs \033[$FG  $T  "
#   for BG in 40m 41m 42m 43m 44m 45m 46m 47m;
#     do echo -en "$EINS \033[$FG\033[$BG  $T  \033[0m";
#   done
#   echo;
# done
# echo

sub _echo ($;$;$)
{
    # Niels Larsen, March 2003.

    # Print a message to STDERR with optional color. If the
    # console cannot show color (like an Emacs shell buffer)
    # then un-colored text is printed. If $Common::Config::console
    # is false then no message is printed. And the routine can
    # be invoked in two ways,
    #
    # $message = echo "text";        # Defined context
    # print STDERR echo "text";      # Void context

    my ( $text,    # Display text
         $color,   # Display color - OPTIONAL
         $indent,  # Text indentation - OPTIONAL
         ) = @_;

    # Returns a string or nothing. 

    return "" if $Common::Messages::silent;

    my %ansi_codes =
        (
         #  Attributes          Foregrounds           Backgrounds
         'clear'      => 0,  'black'      => 30,   'on_black'   => 40,
         'reset'      => 0,  'red'        => 31,   'on_red'     => 41,
         'bold'       => 1,  'green'      => 32,   'on_green'   => 42,
         'dark'       => 2,  'yellow'     => 33,   'on_yellow'  => 43,
         'underline'  => 4,  'blue'       => 34,   'on_blue'    => 44,
         'underscore' => 4,  'magenta'    => 35,   'on_magenta' => 45,
         'blink'      => 5,  'cyan'       => 36,   'on_cyan'    => 46,
         'reverse'    => 7,  'white'      => 37,   'on_white'   => 47,
         'concealed'  => 8,
         );
    
    my ( $output, $beg_code, $end_code, @codes, $orig_text, $blank );
    
    if ( $Common::Config::with_console_messages )
    {
        if ( $color and $ENV{"TERM"} and $ENV{"TERM"} eq "xterm" )
        {
            @codes = map { $ansi_codes{ $_ } } split " ", $color;
            
            $beg_code = "\e\[" . (join ";", @codes) . "m";
            $end_code = "\e\[0m";
        }
        else 
        {
            $beg_code = "";
            $end_code = "";
        }
            
        if ( $text =~ /\n$/ )
        {
            chomp $text;
            $output = "$beg_code$text$end_code\n";
        }
        else
        {
            $output = "$beg_code$text$end_code";
        }

        if ( $indent ) 
        {
            $blank = " " x $indent;
            $output = "$blank$output";
        }
    }
    else {
        $output = "";
    }
    
    return $output;
}

sub echo
{
    # Niels Larsen, April 2009.

    my ( $text,
         $indent,
        ) = @_;

    return "" if $Common::Messages::silent;

    if ( not defined $indent and $Common::Messages::indent_plain ) {
        $indent = $Common::Messages::indent_plain;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, undef, $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, undef, $indent );
    }
    
    return 1;
}

sub echo_bold ($;$)
{
    # Niels Larsen, March 2003.
    
    # Displays a text message in bold on the console. Invokes
    # the echo routine and thus reacts the same way to the 
    # environment (see explanation for the echo routine.) It
    # prints to STDERR in void context and returns a string 
    # in non-void context.

    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing. 

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_bold ) {
        $indent = $Common::Messages::indent_bold;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold", $indent );
    }

    return 1;
}

sub echo_bold_cyan ($;$)
{
    # Niels Larsen, December 2010.
    
    # Displays a text message in bold cyan on the console. Invokes
    # the echo routine and thus reacts the same way to the 
    # environment (see explanation for the echo routine.) It
    # prints to STDERR in void context and returns a string 
    # in non-void context.

    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing. 

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_bold ) {
        $indent = $Common::Messages::indent_bold;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold cyan", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold cyan", $indent );
    }

    return 1;
}

sub echo_done
{
    my ( $str,
         $indent,
        ) = @_;

    my ( $outstr );

    $indent = 0 if not defined $indent;

    $outstr = &echo_green( &done_string( $str ), $indent );

    if ( defined wantarray ) {
        return $outstr;
    } else {
        &echo( $outstr, 0 );
    }

    return 1; 
}

sub echo_green ($;$)
{
    # Displays a text message in green on the console. Invokes
    # the echo routine and thus reacts the same way to the 
    # environment (see explanation for the echo routine.) It
    # prints to STDERR in void context and returns a string 
    # in non-void context.

    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_green ) {
        $indent = $Common::Messages::indent_green;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold green", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold green", $indent );
    }

    return 1;
}

sub echo_green_number
{
    my ( $num,
         $wrap,
        ) = @_;

    $wrap = 1 if not defined $wrap;

    $num = reverse "$num";
    $num =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    $num = scalar reverse $num;

    $num = "$num\n" if $wrap;

    return &Common::Messages::echo_green( $num );
}

sub echo_info ($;$)
{
    # Displays a text message in white on blue background
    # on the console. Invokes the echo routine and thus reacts 
    # the same way to the environment (see explanation for 
    # the echo routine.) It prints to STDERR in void context 
    # and returns a string in non-void context.

    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing.

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_info ) {
        $indent = $Common::Messages::indent_info;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold white on_blue", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold white on_blue", $indent );
    }

    return 1;
}

sub echo_info_green ($;$)
{
    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing.

    return "" if $Common::Messages::silent;

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold white on_green", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold white on_green", $indent );
    }

    return 1;
}

sub echo_messages
{
    # Niels Larsen, March 2006.

    # Prints a list of messages to STDERR. A message is [ type, text ]
    # where text is any text type is one of (case independent):
    #
    # error (shown red)
    # warning (shown yellow)
    # submitted, success, help, ok, results (shown green)
    # info, tip, advice, next, todo (shown blue)

    my ( $msgs,      # List of message tuples
         $args,
         ) = @_; 

    # Returns a text string. 

    my ( $row, $key, @table, $text, $title, $linewid, $linech, $sepstr,
         $console );

    $linewid = defined $args->{"linewid"} ? $args->{"linewid"} : 70;
    $linech = defined $args->{"linech"} ? $args->{"linech"} : "-";
    $sepstr = defined $args->{"sepstr"} ? $args->{"sepstr"} : "->";

    $console = not &Common::Messages::is_run_by_web_server();

    foreach $row ( @{ $msgs } )
    {
        if ( ref $row )
        {
            if ( $console )
            {
                if ( $row->[0] )
                {
                    $key = &Common::Messages::colorize_key( $row->[0] );
                    push @table, [ $key, $sepstr,  $row->[1] ];
                }
                else
                {
                    if ( defined $row->[1] ) {
                        push @table, [ "", "",  $row->[1] ];
                    } else {
                        push @table, [ "", "",  "" ];
                    }                        
                }                    
            }
            else {
                push @table, [ $row->[1] ];
            }
        }
        elsif ( $row =~ /\w/ ) {
            $title = $row;
        } else {
            push @table, [ "", "", "" ];
        }            
    }
    
    $text = " ";
    $text .= ( $linech x $linewid ) ."\n\n" if $console;

    if ( defined $title ) 
    {
        $text .= " $title\n";
        $text .= "\n" if $console;
    }

    if ( @table )
    {
        $text .= &Common::Tables::render_ascii( \@table, {"INDENT" => 1} ) ."\n";
        $text .= "\n" if $console;
    }

    $text .= " ". ( $linech x $linewid ) ."\n" if $console;
    
    if ( defined wantarray ) {
        return $text;
    } else {
        &echo( $text );
    }

    return $text;
}

sub echo_oops ($;$)
{
    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing.

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_info ) {
        $indent = $Common::Messages::indent_info;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold white on_yellow", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold white on_yellow", $indent );
    }

    return 1;
}

sub echo_cyan ($;$)
{
    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing.

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_info ) {
        $indent = $Common::Messages::indent_info;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold white on_cyan", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold white on_cyan", $indent );
    }

    return 1;
}

sub append_or_exit
{
    # Niels Larsen, October 2010.

    # Appends a list of messages to a given list, or if no given 
    # list, prints the messages and exits. It may not sound so useful,
    # but this conditional is repeated in many places.

    my ( $newmsgs,
         $oldmsgs,
         %args,
        ) = @_;

    # Returns nothing.

    my ( $exit, $newlines, $errs );
    
    if ( defined $args{"exit"} ) {
        $exit = $args{"exit"};
    } else {
        $exit = 1;
    }

    #$errs = join "\n", map { $_->[1] } @{ $newmsgs };
    #&dump( $oldmsgs);

    # &error( "$errs\n" );

    if ( defined $args{"newlines"} and not $Common::Messages::silent ) {
        $newlines = $args{"newlines"};
    } else {
        $newlines = 0;
    }

    if ( not defined $newmsgs ) {
        &error( "Message list not defined" );
    }

    if ( defined $oldmsgs )
    {
        push @{ $oldmsgs }, @{ $newmsgs };
        
        $newmsgs = [];

        return;
    }
    elsif ( @{ $newmsgs } )
    {
        local $Common::Messages::silent = 0;

        if ( &Common::Messages::is_run_by_console() )
        {
            if ( $newlines > 0 ) {
                &echo("\n") for 1 ... $newlines;
            }
            
            &echo_messages( $newmsgs );
            # &error( $newmsgs );
            exit -1 if $exit;
        }
        else
        {
            $errs = join "\n", map { $_->[1] } @{ $newmsgs };
            &error( "$errs\n" );
        }
    }

    return;
}

sub echo_red ($;$)
{
    # Displays a text message in red on the console. Invokes
    # the echo routine and thus reacts the same way to the 
    # environment (see explanation for the echo routine.) It
    # prints to STDERR in void context and returns a string 
    # in non-void context.

    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing.

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_red ) {
        $indent = $Common::Messages::indent_red;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold red", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold red", $indent );
    }

    return;
}

sub echo_red_info ($;$)
{
    # Displays a text message in red on the console. Invokes
    # the echo routine and thus reacts the same way to the 
    # environment (see explanation for the echo routine.) It
    # prints to STDERR in void context and returns a string 
    # in non-void context.

    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing.

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_red ) {
        $indent = $Common::Messages::indent_red;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold white on_red", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold white on_red", $indent );
    }

    return;
}

sub echo_yellow ($;$)
{
    # Displays a text message in yellow on the console. Invokes
    # the echo routine and thus reacts the same way to the 
    # environment (see explanation for the echo routine.) It
    # prints to STDERR in void context and returns a string 
    # in non-void context.

    my ( $text,    # Display text
         $indent,
         ) = @_;

    # Returns a string or nothing.

    return "" if $Common::Messages::silent;

    if ( not $indent and $Common::Messages::indent_yellow ) {
        $indent = $Common::Messages::indent_yellow;
    }

    if ( defined wantarray ) {
        return &Common::Messages::_echo( $text, "bold yellow", $indent );
    } else {
        print STDERR &Common::Messages::_echo( $text, "bold yellow", $indent );
    }

    return;
}

sub error
{
    # Niels Larsen, December 2005.

    # Produces a plain text error message to STDERR, or XHTML to STDOUT if 
    # run by a web server, and then exits. 
    # 
    # DEAD END POTENTIAL: this routine is called by SIG{__DIE__} in the (see 
    # start of the Common::Messages module). So if there are errors in this 
    # routine no output would be made, causing Error 500 maybe. The __DIE__ 
    # handler is unset within to prevent "race" conditions with errors in 
    # routines that this routine depends on. 

    my ( $message,     # Message text or signal
         $title,       # Error title - OPTIONAL
         ) = @_;

    # Returns nothing. 

    my ( @modules, $module, $i, $info, $output, $headstr, $state, $xhtml );

    require Data::Dumper;

    $SIG{__DIE__} = ""; 
    $SIG{__WARN__} = "";

    select STDERR; $| = 1; 
    select STDOUT; $| = 1; 

    $Common::Messages::silent = 0;
    $Common::Config::with_console_messages = 1;

    $info = &Common::Messages::error_hash( $message, $title );

    if ( $Common::Config::with_errors_dumped )
    {
        # >>>>>>>>>>>>>>>>>>>>>> NON-INTERACTIVE USE <<<<<<<<<<<<<<<<<<<<<<<<<<

        $Data::Dumper::Terse = 1;     # avoids variable names
        $Data::Dumper::Indent = 1;    # mild indentation
        
        print STDOUT Dumper( $info );
    }
    else
    {
        if ( &Common::Messages::is_run_by_web_server )
        {
            # >>>>>>>>>>>>>>>>>>>>>>>> WEB TO STDOUT <<<<<<<<<<<<<<<<<<<<<<<<<

            ( $state, $xhtml ) = &Common::Messages::system_error_for_browser( $info );

            $state->{"session_id"} = $Common::Config::session_id;

            eval { $output = &Common::Widgets::show_page(
                       {
                           "body" => $xhtml,
                           "sys_state" => $state, 
                       }) };

            if ( $@ )
            {
                $headstr = &Common::Messages::html_header( $info );
                
                if ( $xhtml ) 
                {
                    print STDOUT $headstr;
                    print STDOUT $xhtml;
                }
                else {
                    print STDOUT $headstr ."Problem generating XHTML\n";
                }
            }
            else {
                print STDOUT $output;
            }
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>> CONSOLE TO STDERR <<<<<<<<<<<<<<<<<<<<<<<<<

            $output = &Common::Messages::system_error_for_console( $info );

            print STDERR $output;
        }
    }

    CORE::exit( -1 );
}

sub error_hash
{
    # Niels Larsen, December 2005.

    # Creates a hash with error information. The routine "error" uses it. 

    my ( $text,     # Message text or signal
         $title,    # Header text - OPTIONAL
         ) = @_;

    # In void context, prints a string. In non-void context,
    # returns a string. 

    my ( $info, @table, $output );

    # Gather what we can from the OS,

    if ( $? ) {
        $info->{"CHILD_ERROR"} = $?;
    } else {
        $info->{"CHILD_ERROR"} = "";
    }
    
    if ( $! ) {
        $info->{"OS_ERROR"} = $!;
    } else {
        $info->{"OS_ERROR"} = "";
    }
    
    if ( $@ ) {
        $info->{"EVAL_ERROR"} = $@;
    } else {
        $info->{"EVAL_ERROR"} = "";
    }

    # Set session id if available,

    if ( $Common::Config::session_id ) {
        $info->{"SESSION_ID"} = $Common::Config::session_id;
    }

    # Set date,

    $info->{"DATE"} = &Common::Messages::make_time_string( (localtime)[0..5] );

    # Set default text and title, 

    if ( ref $text eq "ARRAY" ) {
        $text = join "\n", @{ $text };
    } 
    
    if ( not $text ) {
        $text = "No error message was passed.";
    }

    if ( not $title )
    {
#        if ( $Common::Config::sys_name ) {
#            $title = uc $Common::Config::sys_name . " ERROR";
#        } else {
#            $title = "SYSTEM ERROR";
#        }

        $title = "RUN ERROR";
    }

    $info->{"COMMENT"} = "";

    # Contact information,

    if ( $Common::Config::with_contact_info )
    {
        $info->{"FROM"} = &Common::Config::get_contacts();
    }

    # Deal with the different possibilities,

    chomp $text;

    if ( $text =~ /^SIG[A-Z]+$/ )
    {
        $info->{"TITLE"} = "SYSTEM SIGNAL";
        $info->{"MESSAGE"} = qq ($text);
        $info->{"COMMENT"} = qq (
This unhandled error condition should never happen. It is likely 
a problem with system resources, but then it means we have not 
foreseen this. It could also be a programming error on our part.
);
    }
    elsif ( $text =~ /Compilation failed/i or 
            $text =~ /Compilation aborted/i or 
            $text =~ /Compilation errors/i )
    {
        $info->{"TITLE"} = "COMPILATION ERROR";
        $info->{"MESSAGE"} = "$text\n";
    }    
    else
    {
        $info->{"TITLE"} = uc $title;
        $info->{"MESSAGE"} = qq ($text);
    }

    # Optional trace information and logging,
    
    if ( $Common::Config::with_stack_trace )
    {
        @table = &Common::Messages::stack_trace();
        
        if ( @table ) {
            $info->{"STACK_TRACE"} = \@table;
        } else {
            $info->{"STACK_TRACE"} = "";
        }
    }
    
    return $info;
}

sub format_contacts
{
    # Niels Larsen, December 2005.

    # Returns a table with contact information. 

    # Returns a string. 

    my ( $table, $info );

    $info = &Common::Config::get_contacts();

    $table = [
        [ "Author", qq ($info->{"first_name"} $info->{"last_name"}) ],
        [ "Address", qq ($info->{"company"}\t$info->{"street"}\t)
                   . qq ($info->{"postal_code"} $info->{"city"}\t)
                   . qq ($info->{"country"}) ],
        [ "E-mail", $info->{"e_mail"} ],
        [ "Skype", $info->{"skype"} ]
        ];

    return wantarray ? @{ $table } : $table;
}

sub format_contacts_for_browser
{
    # Niels Larsen, December 2005.

    # Returns a table with contact information. 

    my ( $key_style,
         $val_style,
        ) = @_;

    # Returns a string. 

    my ( $table, $xhtml, $row );

    $key_style = "info_report_key" if not defined $key_style;
    $val_style = "info_report_value" if not defined $val_style;

    $table = &Common::Messages::format_contacts();

    foreach $row ( @{ $table } )
    {
        $row->[1] =~ s/\t/<br \/>/g;

        $row->[0] = &Common::Tables::xhtml_style( $row->[0], $key_style );
        $row->[1] = &Common::Tables::xhtml_style( $row->[1], $val_style );
    }        
    
    $xhtml = &Common::Tables::render_html( $table );

    return $xhtml;
}

sub format_contacts_for_console
{
    # Niels Larsen, December 2005.

    # Returns a table with contact information. 

    # Returns a string. 

    my ( @table, @address, $text, $row );

    foreach $row ( &Common::Messages::format_contacts() )
    {
        if ( $row->[0] eq "Address" )
        {
            @address = split "\t", $row->[1];

            push @table, [ "Address", shift @address ];
            push @table, map { [ "", $_ ] } @address;
            push @table, [ "", "" ];
        }
        else {
            push @table, $row;
        }
    }

    $text = &Common::Tables::render_ascii( \@table, {}, 1 );

    return $text;
}

sub html_header
{
    # Niels Larsen, August 2008.

    # Returns a HTML <head> section string with javascript and css references, meta 
    # tags etc. Returns a string.
    
    my ( $args,
        ) = @_;
    
    my ( $title, $keywords, $insert, $timestr, $server_software, $http_host,
         $viewer, $xhtml, $length );

    # Returns string.

    # XHTML header,

    $title = $args->{"title"} || $Common::Config::sys_name;
    $keywords = $args->{"keywords"} || "computer biology, bioinformatics, free software, GPL";
    $insert = $args->{"insert"} || "";
#    $length = $args->{"body_length"} || 0;
    $viewer = $args->{"viewer"} || "array_viewer";

    $xhtml = qq (<head>
<title>$title</title>
);

    if ( $http_host = $ENV{'HTTP_X_FORWARDED_HOST'} or
         $http_host = $ENV{'HTTP_HOST'} )
    {
        $xhtml .= qq (<base href="http://$http_host" />\n);
    }
    else
    {
        print STDOUT &Common::Messages::http_header();
        print STDOUT qq (Could not get http_host from ENV);
        
        CORE::exit( -1 );
    }
    
    $xhtml .= qq (
<meta name="keywords" content="$keywords" />

<meta name="robots" content="none" />
<meta name="rating" content="general" />

<meta http-equiv="Window-target" content="_top" />

<meta name="viewport" content="initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, width=device-width" />

<!-- The following makes sure the page takes full screen -->

<script type="text/javascript">

/*   if (window.self != window.top) window.top.location = window.self.location; */

   function doLoad() {
      setTimeout( "refresh()", 10000 );
   }

   function refresh() {
      document.viewer.submit();
      document.viewer.request.value = '';
   }

</script>
);

    if ( $insert ) {
        $xhtml .= $insert;
    }

    $xhtml .= qq (
<meta name="author" content="Danish Genome Institute" />

<script type="text/javascript" src="$Common::Config::jvs_url/common.js"></script>
<script type="text/javascript" src="$Common::Config::jvs_url/$viewer.js"></script>
        
<script type="text/javascript" src="$Common::Config::jvs_url/overlib_mini.js"><!-- overLIB (c) Erik Bosrup --></script> 

<link rel="stylesheet" type="text/css" href="$Common::Config::css_url/common.css" />
<link rel="stylesheet" type="text/css" href="$Common::Config::css_url/$viewer.css" />

</head>

);

#    $xhtml = &Common::Messages::http_header( $length + (length $xhtml) ) . $xhtml;
    $xhtml = &Common::Messages::http_header() . $xhtml;

    return $xhtml;
}

sub http_header
{
    # Niels Larsen, August 2008.

    # Returns a HTTP header string with date, language etc fields.

    my ( $length,
        ) = @_;

    # Returns a string.

    my ( $str, $timestr, $server_software );

    return "" if $Http_header_sent;
    
    $timestr = &HTTP::Date::time2str( time );
    $server_software = $ENV{"SERVER_SOFTWARE"} || "";
    
    $str = qq (Date: $timestr\r\n)
         . qq (Server: $server_software\r\n)
        . qq (Connection: close\r\n)
        . qq (Pragma: no-cache\r\n)
        . qq (Cache-control: no-cache\r\n)
        . qq (Accept-Charset: ISO-8859-1\r\n);
    
    if ( $length ) {
        $str .= qq (Content-length: $length\r\n);
    }
    
    $str .= qq (Content-language: en, da\r\n)
          . qq (Content-type: text/html; charset=UTF-8\r\n\r\n)
          . qq (<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"\r\n)
          . qq (     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">\r\n\r\n)
          . qq (<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">\r\n\r\n);

    $Http_header_sent = 1;
    
    return $str;
}

sub interrupt
{
    # Niels Larsen, March 2005.

    # Displays a text or XHTML interrupt message, returned or printed,
    # depending on context. In non-interactive contexts (batch jobs)
    # nothing happens (just return;). 

    my ( $message,
        ) = @_;

    # Returns string or nothing.

    my ( $info, @table, $output );

    $SIG{__DIE__} = "";
    $SIG{__WARN__} = "";

    $Common::Messages::silent = 0;
    $Common::Config::with_console_messages = 1;
    
    $info->{"TITLE"} = "INTERRUPTED";

    if ( $message ) 
    {
        $info->{"MESSAGE"} = $message;
    }
    else
    {
        $info->{"MESSAGE"} = qq (
Ctrl-C was pressed, which may have left the system in a corrupt
 state. If the install was stopped due to a problem, please first
 look for the cause in the files in Logs/Install.
);
    }

    # Contact information,

    if ( $Common::Config::with_contact_info )
    {
        $info->{"FROM"} = &Common::Config::get_contacts();
    }

    # Optional trace information and logging,
    
    if ( $Common::Config::with_stack_trace )
    {
        @table = &Common::Messages::stack_trace();
        
        if ( @table ) {
            $info->{"STACK_TRACE"} = \@table;
        } else {
            $info->{"STACK_TRACE"} = "";
        }
    }
    
    # Return XHTML for browser, text for console, or nothing (for batch jobs). 
    
    if ( &Common::Messages::is_run_by_web_server )
    {
        &error( "Not implemented" );
    }
    elsif ( &Common::Messages::is_run_by_console )
    {
        $output = &Common::Messages::interrupt_for_console( $info );
        
        if ( defined wantarray() ) {
            return $output;
        } else {
            print STDERR $output;
        }
    }

    return;
}

sub interrupt_for_console
{
    # Niels Larsen, March 2005.
    
    # Returns a text string formatted from a given info hash, made by 
    # &Common::Messages::interrupt, suited for a console window. 

    my ( $info,    # Error hash
         ) = @_;
    
    # Returns a string. 

    my ( $output, $line, $title, $body, $comment, $redbar, $row, $table, $f_table );

    $line = "=" x 70;
    $title = "\n " . &echo_red( $info->{"TITLE"} ) . "\n";
    
    $redbar = &Common::Messages::_echo( "|", "bold white on_red" );

    $body = $info->{"MESSAGE"};
    $body =~ s/^\n*//g;

    if ( $info->{"FROM"} )
    {
        $body .= "\n";
        $body .= &Common::Messages::format_contacts_for_console();
        $body .= "\n";
    }

    if ( $info->{"STACK_TRACE"} )
    {
        $f_table = &Common::Messages::stack_trace_ascii( $info->{"STACK_TRACE"} );
        $f_table =~ s/\n/\n /g;

        $body .= "\n Packages, line numbers and functions where the interrupt happened:\n\n $f_table\n";
    }

    $output = qq (
$line
 $title
 $body
$line

);

    return $output;
}

sub is_run_by_console
{
    # Niels Larsen, March 2003.

    # Returns true if calling programme is run from the console,
    # false if not. For example if run by cron it will be false.
    # The routine can be used to decide if screen messages should
    # be printed for example. 

    # Returns a boolean. 
    
    if ( -t STDIN ) {
        return 1;
    } else {
        return;
    }
}

sub is_run_by_web_server_modperl
{
    # Niels Larsen, August 2008.
    
    # Returns true if calling program is run by a mod_perl under a 
    # web server, false otherwise. 

    # Returns a boolean.

    if ( &Common::Messages::is_run_by_web_server and $ENV{"MOD_PERL"} ) {
        return 1;
    } else {
        return;
    }
}

sub require_module
{
    # Niels Larsen, August 2008.

    # Loads a given module with require inside an eval statement. If there 
    # is a problem a rudimentary message is sent to the browser or the console.
    # This routine has no dependencies outside this module, and the purpose of
    # it is to tell when there is a problem in a basic module needed for proper
    # display of error messages. Returns nothing or exits.

    my ( $module,
        ) = @_;

    # Returns nothing or exits. 

    my ( $title, $text, $err );

    eval ("use $module");
#    require "Common::Tables";

    if ( $@ )
    {
        $title = "$module Load Error";
        $text = qq (
Eval Error: $@
System Message: $!

There is probably a compilation error in $module. This is 
a basic module needed for error handling and formatting, so 
we cannot even print a better error message. To see this 
error, first comment out 'use Common::Messages' in the 
tables module (Common::Tables) near the top. Then run
<pre>
perl -e 'use $module;'
</pre>
on the command line and try fix the error. Then uncomment 
the messages module again.
);
        if ( &Common::Messages::is_run_by_web_server() )
        {
            print &Common::Messages::http_header();
            print qq (
<h4 class="error_bar_text">$title</h4>
<p class="error_content">
$text Restart apache if under mod_perl, and load again. 
</p>
);
        }
        else {
            print &Common::Messages::system_error_for_console({ "TITLE" => $title, "MESSAGE" => $text});
        }

        CORE::exit( -1 );
    }
    
    return;
}

sub set_die_handler
{
    $SIG{__DIE__} = sub
    {
        # Niels Larsen, March 2005.
        
        # Function that handles the __DIE__ signal. 
        
        my ( $signal,    # Message caught
            ) = @_;
        
        # Returns nothing, dead end.
        
        no warnings;

        if ( not $^S )
        {
            require Common::Tables;

            if ( &Common::Messages::is_run_by_web_server )
            {
                require Common::Widgets;
                require Common::States;
            }
            
            &error( "$0:\n$signal" );
            
            exit( 1 );
            CORE::exit( -1 );
        };

        return 1;
    };

    return 1;
}

sub set_interrupt_handler
{
    my ( $subref );

    require Common::Tables;

    if ( &Common::Messages::is_run_by_web_server )
    {
        require Common::Widgets;
        require Common::States;
    }

    $subref = sub
    {
        # Niels Larsen, March 2005.
        
        # Function that handles interrupt signals. The routine calls the
        # &interrupt function which senses if it is in a web or shell 
        # environment. 
        
        # Returns nothing. 

        local $SIG{HUP} = 'IGNORE';
        kill HUP => -$$;

        no warnings;
        
        $Common::Config::with_contact_info = 0;
        $Common::Config::with_stack_trace = 1;
        $Common::Config::silent = 0;
        
        &Common::Messages::interrupt();
        
        CORE::exit( -1 );

        return 1;
    };

    return $subref;
}

sub set_warning_handler
{
    require Common::Tables;

    if ( &Common::Messages::is_run_by_web_server )
    {
        require Common::Widgets;
        require Common::States;
    }

    $SIG{__WARN__} = sub
    {
        # Niels Larsen, March 2005.
        
        # Function that handles the __WARN__ signal. 
        
        my ( $signal,    # Signal caught
            ) = @_;
        
        # Returns nothing. 
        
        no warnings;
        
        &warning( $signal );
        
        return 1;
    };

    return 1;
}

sub stack_trace
{
    # Niels Larsen, March 2005.

    # Creates a list of the current execution stack using the caller function.
    # The returned list has rows of the form [ module, line, function ] and 
    # at most 20 rows are returned. This module is removed from the list, so
    # usually the last row shows where the problem is. 

    # Returns a list.

    my ( @rows, $count, $row, $attrib, $maxlines, $module, $filename, 
         $line, $routine );

    $maxlines = 20;
    $count = 0;
    @rows = ();
    
    while ( $count <= $maxlines )
    {
        ( $module, $filename, $line, $routine ) = ( caller( $count ) )[0..3];
        $count++;

        last if not defined $module;

        push @rows, [ $module, $line, $routine ];
    }

    if ( @rows )
    {
        @rows = reverse @rows;

        unshift @rows, [ "Package", "Line", "Function" ];
    }

    return wantarray ? @rows : \@rows;
}

sub stack_trace_ascii
{
    # Niels Larsen, November 2005.

    # Creates a list of the current execution stack using the caller function,
    # suited for console display. See also Common::Messages::stack_trace. Returns
    # a text string with color codes embedded. 

    my ( $rows,
        ) = @_;

    # Returns string.

    my ( $row, $str );
    
    if ( not defined $rows ) {
        $rows = &Common::Messages::stack_trace();
    }

    $row = $rows->[0];

    $row->[0] = &Common::Tables::ascii_style( $row->[0], { "color" => "bold white on_blue" } );
    $row->[1] = &Common::Tables::ascii_style( $row->[1], { "color" => "bold white on_blue" } );
    $row->[2] = &Common::Tables::ascii_style( $row->[2], { "color" => "bold white on_blue" } );
    
    $str = join "\n", &Common::Tables::render_ascii( $rows );

    return $str;
}

sub stack_trace_html
{
    # Niels Larsen, November 2005.

    # Creates a list of the current execution stack using the caller function,
    # suited for web display. See also Common::Messages::stack_trace. Returns
    # an XHTML string. 

    my ( $rows,
        ) = @_;

    # Returns string.

    my ( $xhtml );

    if ( not defined $rows ) {
        $rows = &Common::Messages::stack_trace();
    }
    
    $xhtml = &Common::Tables::render_html(
        $rows,
        "col_headers" => shift @{ $rows },
        );

    return $xhtml;
}

sub system_error_for_browser
{
    my ( $info,
        ) = @_;

    my ( $xhtml, $sid, $sys_state, $viewer_state, $text, $headstr, $output );

    require Common::Widgets;

    if ( $Common::Config::sys_state )
    {
        $sys_state = $Common::Config::sys_state;
    } 
    else
    {
        if ( $Common::Config::session_id )
        {
            $sid = $Common::Config::session_id;
            
            eval { $sys_state = &Common::States::restore_sys_state( $sid ) };
            
            if ( $@ )
            {
                $headstr = &Common::Messages::http_header( $info );
                print $headstr ."Error in Common::States::restore_state";
            }
            
            $sys_state->{"session_id"} = $sid;
        }
        else
        {
            $sys_state->{"description"} = { "title" => "$Common::Config::sys_name Error" };
        }
    }

    $sys_state->{"is_error_page"} = 1;
    
    if ( $Common::Config::recover_sub )
    {
        # Recovery routine - experimental

        eval { $viewer_state = &{ $Common::Config::recover_sub } };
        
        if ( $@ )
        {
            $headstr = &Common::Messages::http_header( $info );
            print $headstr ."Error in Common::Config::recover_sub";

            CORE::exit( -1 );
        }
    }

    if ( $viewer_state->{"is_help_page"} or $viewer_state->{"is_popup_page"} )
    {
        $sys_state->{"is_popup_page"} = 1;
        eval { $xhtml = &Common::Messages::system_error_for_browser_css( $info, 1 ) };
        
        if ( $@ )
        {
            $headstr = &Common::Messages::http_header( $info );
            print $headstr ."Error in Common::Messages::system_error_for_browser_css (help/popup page)\n";

            CORE::exit( -1 );
        }
    }
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> NORMAL PAGES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $sys_state->{"is_popup_page"} = 0;
        $sys_state->{"with_header_bar"} = 1;
        $sys_state->{"with_footer_bar"} = 1;

        $xhtml = &Common::Messages::system_error_for_browser_css( $info, 0 );

#         eval { $xhtml = &Common::Messages::system_error_for_browser_css( $info, 0 ) };
        
#         if ( $@ )
#         {
#             $headstr = &Common::Messages::html_header( $info );
#             print $headstr ."Error in Common::Messages::system_error_for_browser_css\n";
#             CORE::exit( -1 );
#         }
    }
 
   return ( $sys_state, $xhtml );
}

sub system_error_for_browser_css
{
    # Niels Larsen, December 2005.

    # Returns XHTML for an error page, given an error hash made by the 
    # error_hash routine. 

    my ( $info,         # Error hash.
         $header,       # Header bar or not - OPTIONAL, default 1
         ) = @_;

    # Returns a string. 

    my ( $xhtml, $title, $msgs, $titles, $rows, $row );

    $header = 1 if not defined $header;

    $xhtml = "";
    $msgs = [];

    # Title bar,

    if ( $header )
    {
        $title = "&nbsp;&nbsp;$Common::Config::sys_name&nbsp;";
        $xhtml .= &Common::Widgets::popup_bar( $title, "error_bar_text", "error_bar_close" );
    }

    # Messages,

    $xhtml .= qq (<table cellpadding="15" border="0"><tr><td>\n);
    $xhtml .= qq (<table cellpadding="5" cellspacing="10" border="0">);

    if ( defined $info->{"TITLE"} ) {
        push @{ $msgs }, [ "Error type", $info->{"TITLE"} ];
    }

    if ( defined $info->{"MESSAGE"} ) {
        push @{ $msgs }, [ "Error message", $info->{"MESSAGE"} ];
    }

    if ( defined $info->{"SESSION_ID"} ) {
        push @{ $msgs }, [ "Session ID", $info->{"SESSION_ID"} ];
    }

    if ( defined $info->{"DATE"} ) {
        push @{ $msgs }, [ "Date", $info->{"DATE"} ];
    }

#     if ( $info->{"OS_ERROR"} ) {
#         push @{ $msgs }, [ "OS error", $info->{"OS_ERROR"} ];
#     }

    if ( $info->{"CHILD_ERROR"} ) {
        push @{ $msgs }, [ "Child error", $info->{"CHILD_ERROR"} ];
    }
    
    if ( $info->{"EVAL_ERROR"} ) {
        push @{ $msgs }, [ "Eval error", $info->{"EVAL_ERROR"} ];
    }
    
    $xhtml .= qq (<tr><td>\n);
    $xhtml .= &Common::Widgets::message_box( $msgs ) ."\n</p>\n";
    $xhtml .= qq (</td></tr>\n);

    # Instructions, 

    $xhtml .= qq (<tr><td>\n);
    $xhtml .= qq (
This error should be reported to the site maintainer, and/or the provider
of the system below. Please either capture a screen image or paste the while 
text or HTML, including the line number information below, into an e-mail message. 
To recover, the main menus above should work, and uploads and analysis results 
will be intact, but unfortunately the displays will be reset to their defaults. 
Later there will be automatic error reporting.
);
    $xhtml .= qq (</td></tr>\n);

    # Stack trace,

    $xhtml .= qq (<tr><td>\n);
    $xhtml .= &Common::Messages::stack_trace_html( $info->{"STACK_TRACE"} );
    $xhtml .= qq (</td></tr>\n);

    # Contact information,

    $xhtml .= qq (<tr><td>\n);
    $xhtml .= &Common::Messages::format_contacts_for_browser();
    $xhtml .= qq (</td></tr>\n);

    $xhtml .= "</table>\n";
    $xhtml .= "</td></tr></table>\n";

    return $xhtml;
}

sub system_error_for_console
{
    # Niels Larsen, April 2005.
    
    # Accepts an error hash made by &Common::Messages::error and displays
    # the values so it looks decent in a console window. 

    my ( $info,    # Error hash
         ) = @_;
    
    # Returns a string. 

    my ( $output, $line, $title, $body, $comment, $redbar, $row, $table, $f_table );

    $Common::Messages::silent = 0;

    $line = "=" x 70;
    $title = "\n  ". &echo_red( $info->{"TITLE"} ) ."\n";
    
    $redbar = &Common::Messages::_echo( "|", "bold white on_red" );

    $body = $info->{"MESSAGE"};

#    if ( $info->{"OS_ERROR"} and $info->{"OS_ERROR"} ne $info->{"MESSAGE"} )
#    {
#        $body .= qq (\nOperating system says: $info->{"OS_ERROR"});
#    }
    
    $body =~ s/^\n*//;
    $body =~ s/\n*$//;
    $body =~ s/\n/\n  $redbar /xg;
    $body = " $redbar $body\n";

    if ( $info->{"COMMENT"} ) 
    {
        $comment = $info->{"COMMENT"};
        $comment =~ s/^\n*//;
        $comment =~ s/\n*$//;
        $comment =~ s/\n/\n /g;
        
        $body .= qq (\n $comment\n);
    }

    if ( $info->{"STACK_TRACE"} )
    {
        $f_table = &Common::Messages::stack_trace_ascii( $info->{"STACK_TRACE"} );
        $f_table =~ s/\n/\n  /g;

        $body .= "\n  Packages, line numbers and functions where the error happened :\n\n  $f_table\n";
    }

    if ( $info->{"FROM"} )
    {
        $body .= qq (
  This error should be reported to the site maintainer, and/or the 
  contact person below. Please paste this whole text into a message 
  and send it to the E-mail address below.

);
        $body .= &Common::Messages::format_contacts_for_console();
        $body .= "\n";
    }
    else
    {
        $body .= &Common::Messages::support_string();
    }

    $output = qq (
 $line
  $title
 $body
 $line

);

    return $output;
}

sub user_error
{
    # Niels Larsen, March 2005.

    # Displays an error message for the user. Should only be used for wrong
    # choices by the user, not for system errors or crashes. 

    my ( $text,     # Message text
         $title,    # Message title - OPTIONAL
         ) = @_;

    # In void context, prints a string. In non-void context,
    # returns a string. 

    my ( $output );

    chomp $text;
        
    # Return XHTML if run by web server, text if from command line,
    # or nothing. Returning nothing is non-interactive jobs.
    
    if ( &Common::Messages::is_run_by_web_server )
    {
        $output = &Common::Messages::user_error_for_browser( $text, $title );
        
        if ( defined wantarray ) {
            return $output;
        } else {
            print $output;
        }
    }
    elsif ( &Common::Messages::is_run_by_console )
    {
        $output = &Common::Messages::user_error_for_console( $text, $title );
        
        if ( defined wantarray() ) {
            return $output;
        } else {
            print STDERR $output;
        }    
    }
    
    return;
}

sub user_error_for_console
{
    # Niels Larsen, March 2005.

    # Prints or returns a console message with yellow header and optional contact 
    # information.
    
    my ( $text,         # Message string
         $title,        # Title string - OPTIONAL
         $contact,      # Prints contact information if true - OPTIONAL, default 1
         ) = @_;
    
    # Returns string or nothing. 

    my ( $output, $line, $head, $body, $contact_info, $table, $f_table );

    $title ||= "USER ERROR";
    $contact = 0 if not defined $contact;

    $line = "=" x 70;

    $text =~ s/^\s+//;
    $text =~ s/\s+$//;

    $output = "$line\n\n";
    $output .= " ". &echo_yellow( uc $title );
    $output .= "\n\n $text\n\n";
    
    if ( $contact ){
        $output .= &Common::Messages::format_contacts_for_console();
        $output .= "\n\n";
    }

    $output .= "$line\n";

    if ( defined wantarray() ) {
        return $output;
    } else {
        print STDERR $output;
    }

    return;
}

sub legal_message
{
    # Niels Larsen, March 2010.

    # Returns a string with copyright and license. 

    my ( $text, $legal_title, $credits_title );

    $legal_title = &echo_info( "License and Copyright" );
    $credits_title = &echo_info( "Credits" );

    $text = qq ($legal_title

$Common::Config::sys_license
$Common::Config::sys_license_url

$Common::Config::sys_copyright

$credits_title

Niels Larsen, Danish Genome Institute and Bioinformatics Research,
Aarhus University; Unpublished.
);

    return $text;
}

sub make_time_string
{
    # Niels Larsen, March 2003.

    # Creates a time string of the form '12-SEP-2000-04:37'. This is 
    # the opposite of what parse_time_string does. The order of input
    # arguments is not the same however: it follows that of localtime,
    # ie seconds first, year last.

    my ( $sec,      # Seconds 
         $min,      # Minutes
         $hour,     # Hours
         $day,      # Day
         $month,    # Month
         $year,     # Year
         ) = @_;

    # Returns a string.

    my $months = [ "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                   "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" ];
    
    my $timestr = ( sprintf "%02.0f", $day ) . "-" 
                . ( $months->[ $month ] ) . "-" 
                . ( sprintf "%04.0f", $year+1900 ) . "-" 
                . ( sprintf "%02.0f", $hour ) . ":" 
                . ( sprintf "%02.0f", $min ) . ":"
                . ( sprintf "%02.0f", $sec );

    return $timestr;
}

sub print_errors
{
    my ( $errors,
        ) = @_;

    my ( $error, $str );

    &echo( "\n" );

    foreach $error ( @{ $errors } )
    {
        $str = &echo_red( "ERROR" );
        &echo( "$str: $error\n" );
    }
    
    &echo( "\n" );

    return;
}

sub print_usage_and_exit
{
    # Niels Larsen, September 2009.

    # Prints a given message to stderr 

    my ( $usage,
        ) = @_;

    if ( not @ARGV and -t STDIN )
    {
        $usage =~ s/\n/\n /g;
        print STDERR "$usage\n" and exit;
    }

    return;
}

sub warning
{
    # Niels Larsen, March 2005.

    # Produces a plain text warning message, or XHTML if run by a web server.
    # If called in void context (wantarray not defined) the
    # routine prints to STDERR (console) and STDOUT (web), if in 
    # scalar or list context the text is returned. To use it, call
    # &warning("message") and the right thing will
    # happen. 
    
    my ( $text,     # Message text
         $title,    # Warning title - OPTIONAL
         ) = @_;

    # Returns a string in non-void context.

    my ( $info, @table, $output );

    return if not $Common::Config::with_warnings;

    $text ||= "";

    if ( not $title ) 
    {
#        if ( $Common::Config::sys_name ) {
#            $title = uc $Common::Config::sys_name . " WARNING";
#        } else {
#            $title = "SYSTEM WARNING";
#        }

        $title = "WARNING";
    }

    $text =~ s/^\s*//g;
    $text =~ s/\s*$//g;

    $info->{"MESSAGE"} = "$text";
    $info->{"TITLE"} = $title;

    # If in web context, return a single line of XHTML. If from console,
    # return a text line. If in batch, return nothing. 

    if ( &Common::Messages::is_run_by_web_server )
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> WEB CONTEXT <<<<<<<<<<<<<<<<<<<<<<<<<<<<

        $output = &Common::Messages::http_header();

        $output .= qq (<table border="2" cellspacing="0" cellpadding="8" bgcolor="#ffcc66" width="100%">
   <tr><td><strong>$info->{"TITLE"}</strong>:&nbsp;$info->{"MESSAGE"}</td></tr>
</table>
);
        if ( defined wantarray ) {
            return $output;
        } else {
            print $output;
        }
    }
#    elsif ( &Common::Messages::is_run_by_console )
    else
    {
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CONSOLE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        $output = "-" x 70;
        $output .= "\n\n";

        $output .= &echo_yellow( 
            qq ($info->{"TITLE"}) ) . &echo( qq (: $info->{"MESSAGE"}\n) );

        $output .= "\n";
        $output .= "-" x 70;
        $output .= "\n";

        if ( defined wantarray() ) {
            return $output;
        } else {
            print STDERR $output;
        }
    }
    
    return;
}

1;

__END__
