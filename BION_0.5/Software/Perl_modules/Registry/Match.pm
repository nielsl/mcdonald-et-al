package Registry::Match;            # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Routines that match and filter methods. 

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_dataset_formats
                 &compatible_datasets
                 &compatible_methods
                 &compatible_methods_exclude
                 &datasets_map
                 &_filter_datasets
                 &_filter_methods
                 &matching_datasets
                 &match_input_dataset
                 &matching_methods
                 &matching_viewers
);

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_dataset_formats
{
    # Niels Larsen, June 2009.

    # Adds formats to each dataset export option; they are not manually kept by
    # the registry, but derived from what methods require. The given method list
    # determines which formats will be added to the export options. Adding these
    # formats makes comparison between methods and data easier. Returns dataset
    # list with formats added.

    my ( $class,
         $datlist,    # Dataset list
         $metlist,    # Method list 
        ) = @_;

    # Returns a list.

    my ( @datlist, @types, $exports, $export, $dat, $t2f, @formats, 
         $fhash, $iformats, $type, $name );
    
    @datlist = Registry::Get->objectify_datasets( $datlist );
    @types = Registry::Get->dataset_types( \@datlist );

    $t2f = Registry::Get->datatypes_to_formats( \@types, $metlist );

    if ( $t2f )
    {
        foreach $dat ( @datlist )
        {
            if ( $exports = $dat->exports )
            {
                foreach $export ( $exports->options )
                {
                    if ( $fhash = $t2f->{ $export->datatype } )
                    {
                        @formats = ();
                        $iformats = $fhash->{"iformats"};
                    
                        if ( $iformats and @{ $iformats } ) {
                            push @formats, @{ $iformats };
                        }
                    
                        push @formats, @{ $fhash->{"formats"} };
                    
                        $export->formats( [ &Common::Util::uniqify( \@formats ) ] );
                    }
                }
            }
        }
    }

    return wantarray ? @datlist : \@datlist;
}

sub compatible_datasets
{
    # Niels Larsen, October 2008.

    # Filters the given dataset list and returns the datasets that match one of 
    # the given method's inputs by type and format. A third optional argument is
    # a (short) list of datasets that has already been mapped to the method, to
    # answer the question "given this method and these data that match the method
    # already, which additional datasets would completely satisfy the method?"
    # Datasets are returned in the same order as given, and either names or
    # objects may be used for all arguments. 

    my ( $class,
         $datlist,            # Dataset name or object list
         $method,             # Method name or object
         $inputs,             # Inputs list - OPTIONAL
        ) = @_;

    # Returns a list or nothing.

    my ( $datobjs );

    $datlist = [ $datlist ] if not ref $datlist;    
    $datobjs = Registry::Get->objectify_datasets( $datlist );

    $method = Registry::Get->method( $method ) if not ref $method;

    return Registry::Match->_filter_datasets( $datobjs, $method, $inputs, "compatible" );
}

sub datasets_map
{
    my ( $class,
         $datobjs,
        ) = @_;

    my ( $name, $type, $format, $map, $obj, $exports, $export );

#    $datlist = [ $datlist ] if not ref $datlist;    
#    $datobjs = Registry::Get->objectify_datasets( $datlist );

    foreach $obj ( @{ $datobjs } )
    {
        $name = $obj->name;
        $type = $obj->datatype;

        if ( $format = $obj->format )
        {
            push @{ $map->{ $type }->{ $format } }, $name;
        }
        else
        {
            foreach $format ( @{ $obj->formats } )
            {
                push @{ $map->{ $type }->{ $format } }, $name;
            }
        }

        if ( $obj->{"exports"} and $exports = $obj->exports->options )
        {
            foreach $export ( @{ $exports } )
            {
                push @{ $map->{ $export->datatype }->{ $export->format } }, $name;
            }
        }
    }

    foreach $type ( keys %{ $map } )
    {
        foreach $format ( keys %{ $map->{ $type } } )
        {
            if ( scalar @{ $map->{ $type }->{ $format } } > 1 ) {
                $map->{ $type }->{ $format } = &Common::Util::uniqify( $map->{ $type }->{ $format } );
            }
        }
    }

    return wantarray ? %{ $map } : $map;
}

sub methods_map
{
    my ( $class,
         $metobjs,
        ) = @_;

    my ( $map, $obj, $input, $type, $format, $name );
    
#    $metlist = [ $metlist ] if not ref $metlist;
#    $metobjs = Registry::Get->objectify_methods( $metlist );

    foreach $obj ( @{ $metobjs } )
    {
        $name = $obj->name;

        foreach $input ( @{ $obj->inputs->options } )
        {
            foreach $type ( @{ $input->types } )
            {
                foreach $format ( @{ $input->formats } )
                {
                    push @{ $map->{ $type }->{ $format } }, $name;
                }
            }
        }
    }

    foreach $type ( keys %{ $map } )
    {
        foreach $format ( keys %{ $map->{ $type } } )
        {
            if ( scalar @{ $map->{ $type }->{ $format } } > 1 ) {
                $map->{ $type }->{ $format } = &Common::Util::uniqify( $map->{ $type }->{ $format } );
            }
        }
    }

    return wantarray ? %{ $map } : $map;
}

sub compatible_methods
{
    # Niels Larsen, October 2008.

    # Filters the given list of methods by using this criteria: all of the given
    # datasets must satisfy at least some of the inputs (by type and format) for 
    # a method to be included. A menu structure is returned.

    my ( $class,
         $metlist,   # List of method names or objects
         $datlist,   # List of dataset names or objects
        ) = @_;

    # Returns an object.

    my ( $metobjs, $datobjs );

    $metlist = [ $metlist ] if not ref $metlist;
    $metobjs = Registry::Get->objectify_methods( $metlist );

    $datlist = [ $datlist ] if not ref $datlist;    
    $datobjs = Registry::Get->objectify_datasets( $datlist );

    return Registry::Match->_filter_methods( $metobjs, $datobjs, "methods", "compatible" );
}

sub compatible_datasets_exclude
{
    # Niels Larsen, June 2009.
    
    # Eliminates the datasets that cannot be compatible with any of the 
    # the given methods, because no input slots match. A list is returned 
    # of datasets that satisfy one or more fields in one or more methods.

    my ( $class,
         $datobjs,   # List of dataset names or objects
         $metobjs,   # List of method names or objects
         $metmap,
        ) = @_;

    # Returns an object.

    my ( $datmap, $dataset, $type, $format, @opts, %seen, $name );

    if ( not $metmap ) {
        $metmap = Registry::Match->methods_map( $metobjs );
    }

    foreach $dataset ( @{ $datobjs } )
    {
        $name = $dataset->name;
        $datmap = Registry::Match->datasets_map( [ $dataset ] );

        foreach $type ( keys %{ $datmap } )
        {
            foreach $format ( keys %{ $datmap->{ $type } } )
            {
                if ( exists $metmap->{ $type }->{ $format } and not $seen{ $name } )
                {
                    push @opts, $dataset;
                    $seen{ $name } = 1;
                }
            }
        }
    }

    return wantarray ? @opts : \@opts;
}

sub compatible_methods_exclude
{
    # Niels Larsen, June 2009.

    # Eliminates the methods that cannot be compatible with the given datasets,
    # because no input slots match. A list is returned of methods that satisfy
    # one or more fields in one or more methods.

    my ( $class,
         $metobjs,   # List of method names or objects
         $datobjs,   # List of dataset names or objects
         $datmap,
        ) = @_;

    # Returns an object.

    my ( $metmap, $method, $type, $format, @opts, %seen, $name );

    if ( not $datmap ) {
        $datmap = Registry::Match->datasets_map( $datobjs );
    }

    foreach $method ( @{ $metobjs } )
    {
        $name = $method->name;
        $metmap = Registry::Match->methods_map( [ $method ] );

        foreach $type ( keys %{ $metmap } )
        {
            foreach $format ( keys %{ $metmap->{ $type } } )
            {
                if ( exists $datmap->{ $type }->{ $format } and not $seen{ $name } )
                {
                    push @opts, $method;
                    $seen{ $name } = 1;
                }
            }
        }
    }

    return wantarray ? @opts : \@opts;
}

sub compatible_viewers
{
    # Niels Larsen, October 2008.

    # Filters the given list of viewers by using this criteria: all of the given
    # datasets must satisfy at least some of the inputs (by type and format) for 
    # a viewer to be included. A menu structure is returned.

    my ( $class,
         $metlist,   # List of viewer names or objects
         $datlist,   # List of dataset names or objects
        ) = @_;

    # Returns an object.

    my ( $metobjs, $datobjs );

    $metlist = [ $metlist ] if not ref $metlist;
    $metobjs = Registry::Get->objectify_methods( $metlist );

    $datlist = [ $datlist ] if not ref $datlist;    
    $datobjs = Registry::Get->objectify_datasets( $datlist );

    return Registry::Match->_filter_methods( $metobjs, $datobjs, "viewers", "compatible" );
}

sub _filter_datasets
{
    # Niels Larsen, October 2008.

    # Filters the given dataset list and returns the datasets that match one of 
    # the given method's inputs by type and format. A third optional argument is
    # a (short) list of datasets that has already been mapped to the method, to
    # answer the question "given this method and these data that match the method
    # already, which additional datasets would completely satisfy the method?"
    # Datasets are returned in the same order as given, and either names or
    # objects may be used for all arguments. 

    my ( $class,
         $datobjs,            # Dataset name or object list
         $metobj,             # Method name or object
         $inlist,             # Inputs list - OPTIONAL
         $strict,             # "compatible" or "match"
        ) = @_;

    # Returns a list or nothing.

    my ( @inlist, @orig_mask, @mask, @inputs, $dataset,
         $i, @matches, $orig_matches, $matches );

    # Add formats to each dataset export option; they are not manually kept by
    # the registry, but derived from what methods require,

    $datobjs = Registry::Match::->add_dataset_formats( $datobjs, [ $metobj ] );

    # Set input mask, a bookkeeping list used below: if a dataset matches a given
    # input, set the corresponding element in the mask.

    @orig_mask = ( undef ) x scalar @{ $metobj->inputs->options };
    
    # If input datasets given, pre-match those and set the corresponding elements 
    # in the mask; these are then skipped below,

    @inputs = @{ $metobj->inputs->options };

    if ( $inlist )
    {
        $inlist = Registry::Get->objectify_datasets( $inlist );
        $inlist = Registry::Match::->add_dataset_formats( $inlist, [ $metobj ] );

        foreach $dataset ( @{ $inlist } )
        {
            for ( $i = 0; $i <= $#inputs; $i++ )
            {
                if ( not defined $orig_mask[$i] and
                     Registry::Match->match_input_dataset( $inputs[$i], $dataset ) )
                {
                    $orig_mask[$i] = 1;
                    last;
                }
            }
        }
    }

    # Match each dataset against the unsatisfied mask slots, 

    $orig_matches = grep { defined $_ } @orig_mask;

    foreach $dataset ( @{ $datobjs } )
    {
        @mask = @orig_mask;

        for ( $i = 0; $i <= $#inputs; $i++ )
        {
            if ( not defined $mask[$i] and
                 Registry::Match->match_input_dataset( $inputs[$i], $dataset ) )
            {
                $mask[$i] = 1;
                last;
            }
        }

        $matches = grep { defined $_ } @mask;

        # If something has been added: if strict is on and every input satisfied, 
        # then keep the dataset; if strict is off, keep any dataset that fits into
        # a free input slot,

        if ( $matches > $orig_matches )
        {
            if ( $strict eq "matching" )
            {
                if ( $matches == scalar @mask )
                {
                    push @matches, $dataset;
                }
            }
            elsif ( $strict eq "compatible" )
            {
                push @matches, $dataset;
            }
            else {
                &error( qq (Wrong looking strict argument -> "$strict") );
            }
        }
    }
        
    if ( @matches ) {
        return wantarray ? @matches : \@matches;
    } else {
        return;
    }
}

sub _filter_methods
{
    # Niels Larsen, October 2008.

    # Returns the methods from a given list that are "satisfied" by the given 
    # datasets. If $strict is on, then there must be a 1-to-1 match of all inputs.
    # Otherwise not all inputs need be satisfied. In either case however all given
    # datasets must be "consumed" by inputs.

    my ( $class,
         $metobjs,            # Methods, names or objects
         $datobjs,            # Datasets, names or objectsist
         $type,               # "methods" or "viewers"
         $strict,             # "compatible" or "match"
        ) = @_;

    # Returns a list or nothing.

    my ( $routine, @matches, @inputs, @mask, $dataset, $method, $i, $matches );

    # Add formats to each dataset export option; they are not manually kept by
    # the registry, but derived from what methods require,

#    $datobjs = Registry::Match::->add_dataset_formats( $datobjs, $metobjs );

    # For each method, match its inputs with the given datasets. Only if all 
    # datasets match different inputs is the method kept. If strict, all method
    # inputs must be used, otherwise one is enough. 

    foreach $method ( @{ $metobjs } )
    {
        @inputs = @{ $method->inputs->options };
        @mask = ( undef ) x scalar @inputs;

        foreach $dataset ( @{ $datobjs } )
        {
            for ( $i = 0; $i <= $#inputs; $i++ )
            {
                if ( not defined $mask[$i] and
                     Registry::Match->match_input_dataset( $inputs[$i], $dataset ) )
                {
                    $mask[$i] = 1;
                    last;
                }
            }
        }

        $matches = grep { defined $_ } @mask;

        if ( $matches == scalar @{ $datobjs } )
        {
            if ( $strict eq "matching" )
            {
                if ( scalar @mask == scalar @{ $datobjs } )
                {
                    push @matches, $method;
                }
            }
            elsif ( $strict eq "compatible" )
            {
                push @matches, $method;
            }
            else {
                &echo( qq (Wrong looking strict argument -> "$strict") );
            }
        }
    }

    if ( @matches ) {
        return wantarray ? @matches : \@matches;
    } else {
        return;
    }
}

sub match_input_dataset
{
    # Niels Larsen, June 2009.
    
    # Compares a method input with a dataset to see if it matches by datatype
    # and format. If the second argument is true (it is by default) then the 
    # export types will be included; in that case the dataset must have had 
    # formats added to each export type. Returns 1 if match, 0 otherwise. 

    my ( $class,
         $input,         # Input object 
         $dataset,       # Dataset object 
         $fatal,
        ) = @_;

    # Returns 0 or 1. 

    my ( $match, $types, $formats, $exports, $export, $name, $dat_formats );
    
    require List::Compare;

    $fatal = 0 if not defined $fatal;
    $match = 0;

    if ( $dataset->format ) {
        $dat_formats = [ $dataset->format ];
    } else {
        $dat_formats = $dataset->formats;
    }

    $types = List::Compare->new( $input->types, [ $dataset->datatype ] );
    $formats = List::Compare->new( $input->formats, $dat_formats );

    if ( $types->get_intersection and $formats->get_intersection )
    {
        $match = 1;
    }
    elsif ( $dataset->exports )
    {
        foreach $export ( @{ $dataset->exports->options } )
        {
            if ( $export->format )
            {
                $types = List::Compare->new( $input->types, [ $export->datatype ] );
                $formats = List::Compare->new( $input->formats, [ $export->format ] );
                
                if ( $types->get_intersection and $formats->get_intersection )
                {
                    $match = 1;
                    last;
                }
            }
            elsif ( $fatal )
            {
                $name = $dataset->name;
                &error( qq (No format set in export in "$name") );
            }
        }
    }
    
    return $match;
}

sub matching_datasets
{
    # Niels Larsen, October 2008.

    # Filters the given dataset list and returns the datasets that match one of 
    # the given method's inputs by type and format. A third optional argument is
    # a (short) list of datasets that has already been mapped to the method, to
    # answer the question "given this method and these data that match the method
    # already, which additional datasets would completely satisfy the method?"
    # Datasets are returned in the same order as given, and either names or
    # objects may be used for all arguments. 

    my ( $class,
         $datlist,            # Dataset name or object list
         $method,             # Method name or object
         $inputs,             # Inputs list - OPTIONAL
        ) = @_;

    # Returns a list or nothing.

    my ( $datobjs );

    $datlist = [ $datlist ] if not ref $datlist;    
    $datobjs = Registry::Get->objectify_datasets( $datlist );

    $method = Registry::Get->method( $method ) if not ref $method;

    return Registry::Match->_filter_datasets( $datobjs, $method, $inputs, "matching" );
}

sub matching_methods
{
    # Niels Larsen, October 2008.

    # Filters the given list of methods by using this criteria: all of the given
    # datasets must satisfy all inputs (by type and format) for a method to be 
    # included. A menu structure is returned.

    my ( $class,
         $metlist,   # List of method names or objects
         $datlist,   # List of dataset names or objects
        ) = @_;

    # Returns an object.

    my ( $metobjs, $datobjs );

    $metlist = [ $metlist ] if not ref $metlist;
    $metobjs = Registry::Get->objectify_methods( $metlist );

    $datlist = [ $datlist ] if not ref $datlist;    
    $datobjs = Registry::Get->objectify_datasets( $datlist );

    return Registry::Match->_filter_methods( $metobjs, $datobjs, "methods", "matching" );
}

sub matching_viewers
{
    # Niels Larsen, October 2008.

    # Filters the given list of viewers by using this criteria: all of the given
    # datasets must satisfy all inputs (by type and format) for a viewer to be 
    # included. A menu structure is returned.

    my ( $class,
         $metlist,   # List of viewer names or objects
         $datlist,   # List of dataset names or objects
        ) = @_;

    # Returns an object.
    
    my ( $metobjs, $datobjs );

    $metlist = [ $metlist ] if not ref $metlist;
    $metobjs = Registry::Get->objectify_methods( $metlist );

    $datlist = [ $datlist ] if not ref $datlist;    
    $datobjs = Registry::Get->objectify_datasets( $datlist );

    return Registry::Match->_filter_methods( $metobjs, $datobjs, "viewers", "matching" );
}

1;

__END__
