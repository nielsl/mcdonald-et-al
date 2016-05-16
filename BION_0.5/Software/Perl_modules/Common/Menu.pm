package Common::Menu;     #  -*- perl -*-

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Option;

use base qw ( Common::Option );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Generates different types of menu structures, and has routines to access
# and manipulate them. Object module. 

# AUTOLOAD
# add_dividers
# append_option
# append_options
# checkbox_option
# checkbox_option_index
# checkbox_options
# clone
# delete
# delete_ids
# delete_indices
# delete_option
# delete_options
# delete_key
# get_option
# get_options
# get_submenus
# match_option
# match_option_index
# match_options
# match_options_ids
# match_options_indices
# max_option_id            Highest option id, returns integer
# new                      Initialized menu object
# option_selected
# options                  All options, returns list
# options_count            The number of options, returns integer
# options_names            Returns list of options names (ids)
# prepend_option           Prepends an option, returns menu
# prepend_options          Prepends a list of options, returns menu
# prune_expr               Deletes options matching expression, returns menu                    
# prune_field              Deletes options with ids in list, returns menu
# read_menu
# replace_option
# replace_option_index
# reverse_options
# select_options
# set_options
# sort_options
# objtype
# write 

# >>>>>>>>>>>>>>>>>>>>>>>> SIMPLE GETTERS AND SETTERS <<<<<<<<<<<<<<<<<<<<<

# To add a simple "getter" or "setter" method, just add its name to the
# following list. The AUTOLOAD function below will then generate the 
# corresponding method, which will double as getter and setter. They 
# can also be specified the normal way of course.

our @Auto_get_setters = qw
    (
     id session_id name title alt_title label method
     request sys_request onchange selected is_active 
     css style fgcolor bgcolor
     );

our %Auto_get_setters = map { $_, 1 } @Auto_get_setters;

sub AUTOLOAD
{
    # Niels Larsen, September 2005.
    
    my ( $self,
         $value,
         ) = @_;

    our $AUTOLOAD;

    my ( $method );
    
    if ( not ref $self ) {
        $self = __PACKAGE__->new();
#        &Common::Messages::error( qq (AUTOLOAD argument is not an object -> "$self" ) );
    }
        
    $AUTOLOAD =~ /::(\w+)$/ and $method = $1;
    
    if ( $Auto_get_setters{ $method } )
    {
        if ( defined $value ) {
             return $self->{ $method } = $value;
         } else {
             return $self->{ $method };
         }
    }
    elsif ( $AUTOLOAD !~ /DESTROY$/ ) {
        &Common::Messages::error( qq (Undefined method called -> "$AUTOLOAD") );
    }

    return;
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_dividers
{
    # Niels Larsen, October 2005.

    # Inserts given dividers among the options in the given menu. The
    # dividers are given as a list of [ key, display text, css class ],
    # and are typically set in the viewer specific modules.

    my ( $self,      # Menu object 
         $divs,      # Dividers list
         ) = @_;

    # Returns an updated menu object.

    my ( $key, $option, $options, %options, $datatype, $divider, @keys,
         $expr, $div, $i );

    @keys = map { $_->[0] } @{ $divs };
    $expr = join "|", @keys;

    foreach $option ( @{ $self->options } )
    {
        $datatype = $option->datatype || "";

        if ( $datatype =~ /^($expr)_?/ )
        {
            push @{ $options{ $1 } }, $option;
        }
        else {
            &Common::Messages::error( qq (Unrecognized option data type -> "$datatype") );
        }
    }

    for ( $i = 0; $i <= $#keys; $i++ )
    {
        $div = $divs->[$i];
        $key = $div->[0];

        if ( $options{ $key } )
        {
            $divider = Common::Option->new( "id" => "" );
            
            $divider->title( $div->[1] );
            $divider->css( $div->[2] );
            $divider->objtype( "divider" );
            $divider->datatype( $key );
            $divider->request("");
            
            push @{ $options }, $divider, @{ $options{ $key } };
        }
    }

    $self->options( $options );

    return $self;
}

sub append_option
{
    # Niels Larsen, October 2005.

    # Appends a given option to a given menu.

    my ( $self,         # Menu object
         $option,       # Option object
         $withid,       # Whether to create id - OPTIONAL, default off
         ) = @_;

    # Returns an array. 

    my ( $options );

    $options = $self->options;

    if ( $withid )
    {
        if ( @{ $options } ) {
            $option->id( $self->max_option_id + 1 );
        } else {
            $option->id( 1 );
        }
    }

    push @{ $options }, $option;

    $self->options( $options );

    return $self;
}

sub append_options
{
    # Niels Larsen, November 2006.

    # Attaches a given list of menu options to the end of a menu. 
    # ID's are incremented from the highest existing ID. 

    my ( $self,          # Menu object
         $list,          # Options list
         $withid,
         ) = @_;

    # Returns updated menu.

    my ( $id, $opts, $elem );

    $withid = 1 if not defined $withid;

    $opts = $self->options;

    if ( $withid )
    {
        $id = $self->max_option_id;

        foreach $elem ( @{ $list } )
        {
            push @{ $opts }, $elem;
            $opts->[-1]->id( ++$id );
        }
    }
    else
    {
        foreach $elem ( @{ $list } )
        {
            push @{ $opts }, $elem;
        }
    }        
        
    $self->options( $opts );

    return $self;
}

sub checkbox_option
{
    my ( $self,
         ) = @_;

    my ( $option );

    $option = $self->match_option( "expr" => 'objtype =~ /^checkbox/' );

    return $option;
}

sub checkbox_option_index
{
    my ( $self,
         ) = @_;

    my ( $index );

    $index = $self->match_option_index( "expr" => 'objtype =~ /^checkbox/' );

    return $index;
}

sub checkbox_options
{
    my ( $self,
         ) = @_;
    
    my ( $options );

    $options = $self->match_options( "expr" => 'objtype =~ /^checkbox/' );

    return wantarray ? @{ $options } : $options;
}

sub clone
{
    # Niels Larsen, October 2005.

    # Copies a menu object to a new one.

    my ( $self,           # Menu object
         ) = @_;

    # Returns a menu object.

    my ( $copy );

    $copy = &Storable::dclone( $self );

    return $copy;
}

sub delete
{
    my ( $self,
         $sid,
         ) = @_;

    my ( $file );

    $file = "$Common::Config::ses_dir/$sid/". $self->name;

    &Common::File::delete_file( $file );
    &Common::File::delete_file_if_exists( "$file.yaml" );

    return;
}

sub delete_ids
{
    # Niels Larsen, October 2005. 

    # Deletes options with ids in a given list.

    my ( $self,         # Menu object
         $ids,          # Option ids
         ) = @_;

    # Returns an updated menu object. 

    my ( $options, %ids, $option );

    if ( ref $ids ) {
        %ids = map { $_, 1 } @{ $ids };
    } else {
        $ids{ $ids } = 1;
    }

    $options = [];

    foreach $option ( @{ $self->options } )
    {
        if ( not exists $ids{ $option->id } )
        {
            push @{ $options }, $option;
        }
    }

    $self->options( $options );

    return $self;
}

sub delete_indices
{
    # Niels Larsen, October 2008. 

    # Deletes options at the given list of indeces.

    my ( $self,         # Menu object
         $ndcs,         # Option indices
         ) = @_;

    # Returns an updated menu object. 

    my ( $options, %ndcs, $i, @options );

    if ( ref $ndcs ) {
        %ndcs = map { $_, 1 } @{ $ndcs };
    } else {
        $ndcs{ $ndcs } = 1;
    }

    $options = $self->options;
    @options = ();

    for ( $i = 0; $i <= $#{ $options }; $i++ )
    {
        if ( not exists $ndcs{ $i } )
        {
            push @options, $options->[$i];
        }
    }

    $self->options( \@options );

    return $self;
}

sub delete_option
{
    # Niels Larsen, November 2005.

    # Deletes the menu option at the given index (not id).

    my ( $self,        # Menu object
         $index,       # Option index
         ) = @_;

    # Returns a menu object.

    my ( $cols );

    $cols = $self->options;

    splice @{ $cols }, $index, 1;

    return $self;
}

sub delete_options
{
    # Niels Larsen, June 2007.

    my ( $self,
         @args,
        ) = @_;

    my ( $opts );

    @{ $opts } = grep { not $_->matches( @args ) } @{ $self->options };

    if ( defined wantarray ) {
        return wantarray ? @{ $opts } : $opts;
    } 
    else {
        $self->options( $opts );
        return $self;
    }
}
         
sub delete_key
{
    my ( $self,
         $key,
         ) = @_;

    delete $self->{ $key };

    return $self;
}

sub get_option
{
    # Niels Larsen, October 2005. 

    # Returns the option with a given index. To extract an option, or 
    # options, by their ids or keys, see match_option and match_options.

    my ( $self,         # Menu object
         $index,        # Option index
         ) = @_;

    # Returns an option object. 

    my ( $options, $count );

    $options = $self->options;

    if ( defined $options )
    {
        if ( $index < 0 )
        {
            &Common::Messages::error( qq (Negative index -> "$index") );
        }
        elsif ( $index > $#{ $options } )
        {
            &Common::Messages::error( qq (Index must be no higher than ).$#{ $options }.qq( -> "$index") );
        }
        else {
            return $options->[ $index ];
        }
    }
    else {
        &Common::Messages::error( qq (No options in menu) );
    }

    return;
}

sub get_option_values
{
    my ( $self,
         $key,
         ) = @_;

    my ( @values, $value, $opt );

    @values = ();

    foreach $opt ( @{ $self->options } )
    {
        $value = $opt->$key;

        if ( defined $value )
        {
            if ( ref $value ) {
                push @values, @{ $value };
            } else {
                push @values, $value;
            }
        }
    }

    @values = &Common::Util::uniqify( \@values );

    return wantarray ? @values : \@values;
}

sub get_options
{
    # Niels Larsen, October 2005. 

    # Returns the list of options that correspond to a given list of indices.

    my ( $self,         # Menu object
         $indices,      # Option indices
         ) = @_;

    # Returns an option object. 

    my ( @options, $index );

    foreach $index ( @{ $indices } )
    {
        push @options, $self->get_option( $index );
    }

    return wantarray ? @options : \@options;
}

sub get_submenus
{
    # Niels Larsen, October 2006.

    # Returns a list of menus that are submenus to a given menu.

    my ( $self,
         ) = @_;

    # Returns a list.

    my ( $opt, @menus );

    foreach $opt ( $self->options )
    {
        if ( (ref $opt) =~ /::Menu$/ )
        {
            push @menus, $opt;
        }
    }

    return wantarray ? @menus : \@menus;
}
            
sub match_option
{
    # Niels Larsen, October 2005. 

    # Like the match_options routine, except here a single option is returned.
    # If more than one option matches the filter criteria an error occurs.

    my ( $self,         # Menu object
         @args,         # Key/value pairs
         ) = @_;

    # Returns an option object. 

    my ( $options, $count );

    $options = $self->match_options( @args );

    $count = scalar @{ $options };

    if ( $count == 1 )
    {
        return $options->[0];
    }
    elsif ( $count == 0 )
    {
        return;
    }
    else {
        &Common::Messages::error( qq ($count matching options found, should only be one.) );
    }

    return;
}

sub match_options
{
    # Niels Larsen, October 2005.

    # Returns a list of options that satisfy given exact match criteria:
    # The second argument is a list of key value pairs, where the key 
    # must be one of the methods known by the objects that are in the 
    # options list. The value is a string, with one exception: if the 
    # key is "id", then a list of ids are allowed; then all options that
    # match either of the ids will be included. Between the key/value
    # pairs there is an implicit "and". The following call
    # 
    # $options = $menu->match_options( "id" => [2,3], "bgcolor" => "#666666" );
    #
    # means "get all options with id 2 or 3, and with background color
    # set to "#666666".

    my ( $self,    # Menu object
         @args,    # Key/value pairs
         ) = @_;

    # Returns a menu structure. 

    my ( $opts );

    @{ $opts } = grep { $_->matches( @args ) } @{ $self->options };

    if ( defined wantarray ) {
        return wantarray ? @{ $opts } : $opts;
    } 
    else {
        $self->options( $opts );
        return $self;
    }
}

sub match_options_expr
{
    # Niels Larsen, October 2005.

    # Returns a list of options that satisfy given filter criteria.
    # Filter criteria are an eval expression string. This routine is
    # typically called by context specific routines that form the 
    # expression. An expression example could be 
    # 
    # '$_->title eq "My title" and $->datatype eq "rna_ali"'
    # 

    my ( $self,        # Menu object
         $expr,        # Match criteria
         ) = @_;

    # Returns an updated menu object. 

    my ( $opts, $opt );

    $opts = &Storable::dclone( [ $self->options ] );

    @{ $opts } = grep { eval $expr } @{ $opts };

    if ( defined wantarray ) {
        return wantarray ? @{ $opts } : $opts;
    } 
    else {
        $self->options( $opts );
        return $self;
    }
}

sub match_options_ids
{
    # Niels Larsen, October 2005. 

    # Returns a list of ids of the options that match the given filter 
    # criteria (see the match_options routine). 

    my ( $self,         # Menu object
         %args,         # Option id
         ) = @_;

    # Returns an option object. 

    my ( $ids );

    $ids = [ map { $_->id } $self->match_options( %args ) ];

    return wantarray ? @{ $ids } : $ids;
}

sub match_option_index
{
    # Niels Larsen, October 2005.

    # Returns the index of the option that matches the given filter
    # criteria. More than one match is an error. 

    my ( $self,      # Menu object
         @args,      # Key/value pairs
         ) = @_;

    # Returns an integer. 

    my ( $ndcs, $count );

    if ( defined ( $ndcs = $self->match_options_indices( @args ) ) ) {
        $count = scalar @{ $ndcs };
    } else {
        $count = 0;
    }

    if ( $count == 1 )
    {
        return $ndcs->[0];
    }
    elsif ( $count == 0 )
    {
        return;
    }
    else {
        &Common::Messages::error( qq ($count matching options found, should only be one.) );
    }
}

sub match_options_indices
{
    # Niels Larsen, October 2005.

    # Returns the indices of the options that matches the given filter
    # criteria. 

    my ( $self,      # Menu object
         @args,      # Key/value pairs
         ) = @_;

    # Returns an integer. 

    my ( $option, $ndx, @ndcs );

    $ndx = 0;

    foreach $option ( $self->options )
    {
        if ( defined $option->match( @args ) )
        {
            push @ndcs, $ndx;
        }

        $ndx += 1;
    }

    if ( @ndcs ) {
        return wantarray ? @ndcs : \@ndcs;
    } else {
        return;
    }
}

sub get_option_ids
{
    # Niels Larsen, October 2005.

    # Returns all menu option ids, if any. 
 
    my ( $self,
         ) = @_;

    # Returns a list or nothing.

    my ( @ids );

    @ids = map { $_->id } @{ $self->options };

    if ( @ids ) {
        return wantarray ? @ids : \@ids;
    } else {
        return;
    }
}

sub max_option_id
{
    # Niels Larsen, October 2005.

    # Finds the highest id among options in a given menu.

    my ( $self,        # Menu object
         ) = @_;

    # Returns an integer or undef if no options.

    my ( $options, $option, $maxid, $id );

    $options = $self->options;

    if ( @{ $options } )
    {
        $maxid = 0;

        foreach $option ( @{ $options } )
        {
            $id = $option->id;
            $maxid = $id if $id > $maxid;
        }
    }
    else {
        $maxid = undef;
    }

    return $maxid;
}

sub new
{
    # Niels Larsen, October 2005.

    # Creates a new menu structure with options, if given. The options
    # may themselves be menus. 

    my ( $class,          # Class name
         %args,           # Argument keys
         ) = @_;

    # Returns a menu object.

    my ( $self, $valid, $option, $key, $id );

    $valid = { map { $_, 1 } ( @Auto_get_setters, "objtype", "options" ) };

    $self->{"options"} = [];

    $class = ( ref $class ) || $class;
    bless $self, $class;
    
    foreach $key ( keys %args )
    {
        if ( $valid->{ $key } )
        {
            if ( $key eq "options" )
            {
                 $id = 1;

                 foreach $option ( @{ $args{ $key } } )
                 {
                     if ( $option->{"options"} and @{ $option->{"options"} } ) {
                         push @{ $self->{"options"} }, Common::Menu->new( "id" => $id, %{ $option } );
                     } else {
                         push @{ $self->{"options"} }, Common::Option->new( "id" => $id, %{ $option } );
                     }

                     $id += 1;
                 }
            }
            elsif ( $key eq "objtype" ) {
                $self->objtype( $args{ $key } );
            } else {
                $self->{ $key } = $args{ $key };
            }
        }
        else {
            &Common::Messages::error( qq (Wrong looking key -> "$key") );
        }
    }

    return $self;
}

sub option_selected
{
    my ( $self,
        ) = @_;

    my ( $name, $opt );

    if ( defined ( $name = $self->selected ) )
    {
        $opt = $self->match_option( "name" => $name );
        return $opt;
    }
    
    return;
}

sub options
{
    # Niels Larsen, October 2005.
    
    # Sets or gets, as array or array reference, the list of options.

    my ( $self,
         $options,
         ) = @_;

    # Returns menu object or list.

    if ( defined $options )
    {
        $self->{"options"} = $options;
        return $self;
    }
    else {
        return wantarray ? @{ $self->{"options"} || [] } : $self->{"options"} || [];
    }
}

sub options_count
{
    # Niels Larsen, October 2005.
    
    # Returns the number of options in a given menu.

    my ( $self,
         ) = @_;

    # Returns an integer. 

    return scalar @{ $self->options };
}

sub options_names
{
    # Niels Larsen, March 2008.
    
    # Returns the number of options in a given menu.

    my ( $self,
         ) = @_;

    # Returns an integer.

    my ( @list );

    @list = map { $_->name } @{ $self->options };

    return wantarray ? @list : \@list;
}

sub prepend_option
{
    # Niels Larsen, October 2005.

    # Prepends a given option to a given menu. The new option
    # is given an id that is one higher than the highest current
    # id. 

    my ( $self,         # Menu object
         $opt,          # Option object
         ) = @_;

    # Returns updated menu.

    my ( $opts, $copt );
    
    $opts = $self->options;

    $copt = &Storable::dclone( $opt );

    if ( @{ $opts } ) {
        $copt->id( $self->max_option_id + 1 );
    } else {
        $copt->id( 1 );
    }

    unshift @{ $opts }, $copt;

    $self->options( $opts );

    return $self;
}

sub prepend_options
{
    # Niels Larsen, April 2006.

    # Attaches a given list of menu options to the beginning of a 
    # menu. ID's are incremented from the highest existing ID. 

    my ( $self,          # Menu object
         $list,          # Options list
         ) = @_;

    # Returns updated menu.

    my ( $id, $opts, $i );

    $opts = $self->options;

    $id = $self->max_option_id + 1;

    unshift @{ $opts }, @{ $list };

    for ( $i = 0; $i <= $#{ $list }; $i++ )
    {
        $opts->[$i]->id( $id );

        $id += 1;
    }

    $self->options( $opts );

    return $self;
}

sub prune_expr
{
    # Niels Larsen, October 2005.

    # Returns a menu where the options match a given expression that 
    # can be eval'ed. 
    
    my ( $self,     # Menu object
         $expr,     # Eval expression string
         ) = @_;

    # Returns a menu object.

    my ( $options );

    $options = [ grep { eval $expr } @{ $self->options } ];

    $self->options( $options );

    return $self;
}

sub prune_field
{
    # Niels Larsen, October 2005. 

    # Removes options that have field values of the given name in 
    # the given list. Returns an updated menu.

    my ( $self,         # Menu object
         $name,         # Field name
         $vals,         # Field values
         ) = @_;

    # Returns a menu object. 

    my ( $options, %vals, $option, $id );

    if ( ref $vals ) {
        %vals = map { $_, 1 } @{ $vals };
    } else {
        $vals{ $vals } = 1;
    }

    $options = [];

    foreach $option ( @{ $self->options } )
    {
        if ( not defined $option->$name or not $vals{ $option->$name } )
        {
            push @{ $options }, $option;
        }
    }

    $self->options( $options );

    return $self;
}

sub read_menu
{
    # Niels Larsen, October 2005.
    
    # Reads a menu from a given file prefix path: if "$prefix.bin" is no older
    # than "$prefix.yaml" then it is read from the .bin file, otherwise from 
    # the .yaml file and a new .bin file is written. If the optional $fatal 
    # argument is set to 0, then the routine returns nothing if there is no
    # .yaml file found. 

    my ( $class,        # Class or object name
         $prefix,       # File prefix path
         $fatal,        # Flag 0 or 1 - OPTIONAL, default 1
         ) = @_;

    # Returns a menu object.

    my ( $menu, $bin_file, $yaml_file, $i, $opt );

    $fatal = 1 if not defined $fatal;

    $bin_file = "$prefix.bin";
    $yaml_file = "$prefix.yaml";

    if ( not $fatal and not -r $yaml_file ) {
        return;
    }

    if ( not -r $bin_file or
         -r $yaml_file and -M $bin_file > -M $yaml_file )
    {
        $menu = &Common::File::read_yaml( $yaml_file );
        
        $i = 0;

        foreach $opt ( $menu->options )
        {
            $opt->id( ++$i );
        }
        
        &Common::File::store_file( $bin_file, $menu );
    }
    else {
        $menu = &Common::File::retrieve_file( $bin_file );
    }

    $menu->css( "grey_menu" );

    $class = ( ref $class ) || $class;
    bless $menu, $class;

    return $menu;
}

sub replace_option_index
{
    my ( $self,
         $option,
         $index,
         ) = @_;

    my ( $options );

    $options = $self->options;

    splice @{ $options }, $index, 1, $option;

    return $self;
}

sub replace_option
{
    # Niels Larsen, October 2005.

    # Replaces an option with the given id with a given one. 

    my ( $self,         # Menu object
         $newopt,       # Option object
         $id,           # Option id
         ) = @_;

    # Returns an updated menu object. 

    my ( $found, $option, $name );

    foreach $option ( @{ $self->options } )
    {
        if ( $option->id == $id )
        {
            $option = $newopt;
            $found = 1;
        }
    }

    if ( $found ) {
        return $self;
    }
    else
    {
        $name = $self->name;
        &Common::Messages::error( qq (In "$name" there is no id "$id") );
    }
}

sub reverse_options
{
    # Niels Larsen, November 2005.

    # Reverses the order of the options in a given menu.
    
    my ( $self,
         ) = @_;

    # Returns an updated menu object. 

    my ( $options );

    $options = [ reverse @{ $self->options } ];

    $self->options( $options );

    return $self;
}

sub select_options
{
    # Niels Larsen, October 2005.

    # Sets options with the given ids as selected. 

    my ( $self,    # Menu object
         $ids,     # List of ids
         $field,
         ) = @_;

    # Returns updated menu object or list of ids;

    my ( %ids, $options, $option, @ids );

    if ( defined $ids and @{ $ids } )
    {
        %ids = map { $_, 1 } @{ $ids };
        $options = $self->options;

        $field ||= "id";
        
        foreach $option ( @{ $options } )
        {
            if ( $ids{ $option->$field } )
            {
                $option->selected( 1 );
            }
        }

        $self->options( $options );
    }
#    else {
#        &Common::Messages::error( qq (A list of ids must be given) );
#    }

    return $self;
}    

sub selected_options
{
    my ( $self,
         ) = @_;

    my ( @opts );

    @opts = $self->match_options( "selected" => 1 );

    return wantarray ? @opts : \@opts;
}

sub set_options
{
    # Niels Larsen, February 2007.

    # Sets the given key/value of the options that have the
    # given id, and then returns the updated menu object.

    my ( $self,
         $id,           
         $key,
         $val,
         ) = @_;

    # Returns a menu object.

    my ( $opt );

    foreach $opt ( @{ $self->options } )
    {
        if ( $opt->name eq $id ) {
            $opt->$key( $val );
        }
    }

    return $self;
}
    
sub sort_options
{
    # Niels Larsen, October 2005.

    # Sorts the options in a given menu by the values of a given field. 
    
    my ( $self,
         $field,
         ) = @_;

    # Returns an updated menu object. 

    my ( $options );

    $options = [ sort { $a->$field cmp $b->$field } @{ $self->options } ];

    $self->options( $options );

    return $self;
}

sub sort_options_list
{
    # Niels Larsen, May 2008.

    # Sorts the options in a given menu by a list of values of a given 
    # field. For example if a list of names are given, then the options
    # will have the same order as in the list.
    
    my ( $self,
         $field,      # Field name
         $list,       # Field values
         ) = @_;

    # Returns an updated menu object. 

    my ( %options, @options, $key );

    %options = map { $_->$field, $_ } @{ $self->options };

    foreach $key ( @{ $list } )
    {
        if ( exists $options{ $key } )
        {
            push @options, $options{ $key };
        }
    }

    $self->options( \@options );

    return $self;
}

sub objtype
{
    # Niels Larsen, October 2005.

    # Sets menu type. Recognized types are "controls", "data", "oploads",
    # "selections". 

    my ( $self,      # Menu object
         $type,      # Type string - OPTIONAL
         ) = @_;

    # Returns updated menu object or type string.

    my ( $valid );

    if ( defined $type )
    {
        $valid = { map { $_, 1 } ( "controls", "datatypes", "uploads", "selections", 
                                   "clipboard", "results", "formats" ) };
        
        if ( $valid->{ $type } )
        {
            $self->{"objtype"} = $type;
        }
        else {
            &Common::Messages::error( qq (Wrong looking key -> "$type") );
        }

        return $self;
    }
    else {
        return $self->{"objtype"};
    }
}

sub write
{
    # Niels Larsen, October 2005.
    
    # Writes a given menu to file in "Storable" format, in a given
    # session directory. The file name is that of the menu name. The 
    # session directory is created if it does not exist. 

    my ( $self,       # Class or object name
         $sid,        # Session id
         $file,       # File name - OPTIONAL
         ) = @_;

    # Returns nothing.

    my ( $dir );

    if ( not $sid ) {
        $sid = $self->session_id;
    }

    $dir = "$Common::Config::ses_dir/$sid";
    &Common::File::create_dir_if_not_exists( $dir );

    if ( not defined $file ) {
        $file = "$dir/" . $self->name;
    }

#     $self->delete_key( "title" );
#     $self->delete_key( "name" );
#     $self->delete_key( "objtype" );
#     $self->delete_key( "onchange" );
#     $self->delete_key( "css" );

    &Common::File::store_file( $file, $self );

    return;
}

1;

__END__

sub match_options
{
    # Niels Larsen, October 2005.

    # Returns a list of options that satisfy given exact match criteria:
    # The second argument is a list of key value pairs, where the key 
    # must be one of the methods known by the objects that are in the 
    # options list. The value is a string, with one exception: if the 
    # key is "id", then a list of ids are allowed; then all options that
    # match either of the ids will be included. Between the key/value
    # pairs there is an implicit "and". The following call
    # 
    # $options = $menu->match_options( "id" => [2,3], "bgcolor" => "#666666" );
    #
    # means "get all options with id 2 or 3, and with background color
    # set to "#666666".

    my ( $self,    # Menu object
         @args,    # Key/value pairs
         ) = @_;

    # Returns a list. 

    my ( $orig_opts, $opts, @opts, $arg_key, $arg_value, $value, %ids, 
         @expr, $expr, $opt );

    if ( @args ) 
    {
        if ( scalar @args % 2 != 0 ) {
            &Common::Messages::error( qq (Uneven number of arguments.) );
        }
    } 
    else {
        &Common::Messages::error( qq (No arguments.) );
    }

    $opts = &Storable::dclone( [ $self->options ] );

    while ( @args )
    {
        $arg_key = shift @args;
        $arg_value = shift @args;
        $arg_value = "" if not defined $arg_value;

        if ( ref $arg_value )
        {
        }
        elsif ( not ref $arg_value )
        {
            if ( $arg_key eq "expr" ) {
                $expr = $arg_value;
            } else {
                $expr = '$_->'.$arg_key.' eq "'.$arg_value.'"';
            }

            @{ $opts } = grep { eval $expr } @{ $opts };
        }
        else {
            &Common::Messages::error( qq (The value of "$arg_key" should be either a list or a simple scalar.) );
        }
    }

    if ( defined wantarray ) {
        return wantarray ? @{ $opts } : $opts;
    } 
    else {
        $self->options( $opts );
        return $self;
    }
}


sub read
{
    # Niels Larsen, October 2005.

    # Reads a given menu file. It is typically called by a viewer specific
    # read routine that sets the file name.

    my ( $class,      # Class name
         $file,       # File path
         ) = @_;

    # Returns a menu object.

    my ( $menu );

    if ( -r $file )
    {
        $menu = &Common::File::retrieve_file( $file );
        return $menu;
    }
    else {
        return;
    }
}
