package Taxonomy::Export;        #  -*- perl -*-

# Functions that import or export a hierarchy from disk somehow. 

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;
use Storable qw ( retrieve store );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &export_dump
                 &export_human
                 &export_table
                 &export_xml
                 &print_dump
                 &print_table
                 &print_parents_tuples
                 );

use Common::Config;
use Common::Messages;

use Taxonomy::Nodes;

our $id_name_def = "tax_id";

# >>>>>>>>>>>>>>>>>>>>>>>>> ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub export_human
{
    my ( $nodes,
         $nid,
         $fields,
         $lines,
         $depth,
         ) = @_;

    $fields = [ $id_name_def, "parent_id" ] if not $fields;
    $depth = 0 if not defined $depth;

    my ( $line, $field, $node, $child_id );

    $line = " " x $depth;
    $node = $nodes->{ $nid };

    foreach $field ( @{ $fields } )        {
        $line .= "$node->{ $field }\t";
    }
        
    $line =~ s/\t$/\n/;
        
    push @{ $lines }, $line;
    
    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $node ) )
    {
        &Taxonomy::Export::export_human( $nodes, $child_id, $fields, $lines, $depth+1 );
    }

    return wantarray ? @{ $lines } : $lines;
}

sub export_dump
{
    # Niels Larsen, May 2003.

    # Returns a given nodes structure formatted with Data::Dumper
    # This ascii output can be read by the import_dump routine. 
    
    my ( $nodes,   # Input structure
         ) = @_;

    # Returns a string.

    my ( $text );

    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;

    if ( not $text = Dumper( $nodes ) ) {
        &error( qq (Could not dump nodes structure), "DATA::DUMPER ERROR" );
    }

    return $text;
}

sub export_table
{
    # Niels Larsen, February 2003

    # Returns a memory hierarchy as a table. No children fields
    # are made, but a parent id is always added. 

    my ( $nid,       # Starting node ID
         $nodes,     # Nodes hash
         $fields,    # List of field names to output
         $table,     # Output table
         ) = @_;

    # Returns a list. 

    my ( %fields, $field, $child, $node_copy, @temp, @row, $value, 
         $count, $elem, $i, $node, $child_id );
    
    %fields = map { $_, 1 } @{ $fields };
    @temp = ();

    $node = $nodes->{ $nid };
    
    foreach $field ( @{ $fields } )
    {
        if ( exists $node->{ $field } )
        {
            $value = $node->{ $field };
            
            push @temp, $value;
        }
        else
        {
            my $dump = Dumper( $node );
            &error( qq (Missing "$field" in node -> "$dump") );
            exit;
        }
    }

    $count = 0;

    foreach $elem ( @temp )
    {
        if ( ref $elem eq "ARRAY"  and scalar @{ $elem } > $count ) {
            $count = scalar @{ $elem };
        }
    }

    if ( $count > 0 ) 
    {
        foreach $elem ( @temp )
        {
            if ( not ref $elem ) {
                $elem = [ ($elem) x $count ];
            }
        }
        
        for ( $i = 0; $i < $count; $i++ )
        {
            @row = ();

            foreach $elem ( @temp )
            {
                if ( ref $elem ) {
                    push @row, $elem->[$i];
                } else {
                    push @row, $elem;
                }
            }
            
            push @{ $table }, [ @row ];
        }
    }
    else
    {
        push @{ $table }, [ @temp ];
    }
    
    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $node ) )
    {
        $child = $nodes->{ $child_id };
        $table = &Taxonomy::Export::export_table( $child, $fields, $table );
    }
    
    return wantarray ? @{ $table } : $table;
}

sub print_dump
{
    # Niels Larsen, May 2003.

    # Returns a given nodes structure formatted with Data::Dumper
    # This ascii output can be read by the import_dump routine. 
    
    my ( $nodes,   # Nodes structure
         $file,    # Output file path
         ) = @_;

    # Returns nothing. 

    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;

    if ( not open FILE, "> $file" )        {
        &error( qq (Could not write-open the file\n"$file"), "FILE OPEN ERROR" );
    }
    
    if ( not print FILE Dumper( $nodes ) ) {
        &error( qq (Could not write to the file\n"$file"), "FILE WRITE ERROR" );
    }

    if ( not close FILE ) {
        &error( qq (Could not close the file\n"$file"), "FILE CLOSE ERROR" );
    }

    return;
}

sub print_table
{
    # Niels Larsen, April 2003

    # Writes a given list of fields to a given file handle, starting at 
    # given hierarchy node. 

    my ( $id,        # Starting node ID
         $nodes,     # Node hash
         $fields,    # List of field names to output
         $handle,    # Output file handle
         ) = @_;

    # Returns a list. 

    my ( %fields, $field, $child, $child_id, $node_copy, @temp, @row, $row, $value, 
         $count, $elem, $i, $node );
    
    %fields = map { $_, 1 } @{ $fields };
    @temp = ();

    $node = $nodes->{ $id };

    foreach $field ( @{ $fields } )
    {
        if ( exists $node->{ $field } )
        {
            $value = $node->{ $field };
            
            push @temp, $value;
        }
        else
        {
            my $dump = Dumper( $node );
            &error( qq (Missing "$field" in node -> "$dump") );
        }
    }

    $count = 0;

    foreach $elem ( @temp )
    {
        if ( ref $elem eq "ARRAY"  and scalar @{ $elem } > $count ) {
            $count = scalar @{ $elem };
        }
    }

    if ( $count > 0 ) 
    {
        foreach $elem ( @temp )
        {
            if ( not ref $elem ) {
                $elem = [ ($elem) x $count ];
            }
        }
        
        for ( $i = 0; $i < $count; $i++ )
        {
            @row = ();

            foreach $elem ( @temp )
            {
                if ( ref $elem ) {
                    push @row, $elem->[$i];
                } else {
                    push @row, $elem;
                }
            }
            
            $row = join "\t", @row;
            print $handle "$row\n";
        }
    }
    else
    {
        $row = join "\t", @temp;
        print $handle "$row\n";
    }
    
    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $node ) )
    {
        &Taxonomy::Export::print_table( $child_id, $nodes, $fields, $handle );
    }
}

sub export_xml
{
    # Niels Larsen, February 2003

    # Writes a memory tree into an XML formatted stream. 

    my ( $node,   # Input starting node
         ) = @_;

    # Returns nothing 

    my ( $child, $child_id, $node_copy, $name, $key, $value, $elem, @xml );
    
    if ( @{ &Taxonomy::Nodes::get_ids_children( $node ) } ) {
        push @xml, "<node>\n";
    } else {
        push @xml, "<leaf>\n";
    }
    
    $node_copy = &Taxonomy::Nodes::copy_node( $node );
    
    foreach $key ( keys %{ $node_copy } )
    {
        $value = $node_copy->{ $key };
        $key = lc $key;
        
        if ( ref $value eq "ARRAY" )
        {
            foreach $elem ( @{ $value } )
            {
                push @xml, "   <$key>$elem</$key>\n";
            }
        }
        elsif ( not ref $value )
        {
            push @xml, "   <$key>$value</$key>\n";
        }
        else
        {
            my $dump = Dumper( $node_copy );
            &error( qq (Illegal node structure -> "$dump") );
            exit;
        }
    }
    
    foreach $child_id ( &Taxonomy::Nodes::get_ids_children( $node ) )
    {
        push @xml, @{ &Taxonomy::Nodes::export_xml( $child_id ) };
    }
    
    if ( @{ &Taxonomy::Nodes::get_ids_children( $node ) } ) {
        push @xml, "</node>\n";
    } else {
        push @xml, "</leaf>\n";
    }

    return wantarray ? @xml : \@xml;
}

sub print_parents_tuples
{
    # Niels Larsen, April 2003.

    # Prints a list [ id, parent_id ] tuples where parent_id is 
    # any parent up the "lineage". 

    my ( $nodes,     # Node hash
         $id,        # Starting node ID
         $handle,    # File handle
         ) = @_;
    
    # Returns a list. 

    my ( $subref, $argref );

    $subref = sub 
    {
        my ( $nodes, $id, $handle ) = @_;
        my ( $parent_id, $temp_id );

        if ( &Taxonomy::Nodes::get_ids_children( $nodes->{ $id } ) )
        {
            $temp_id = $id;

            while ( $parent_id = &Taxonomy::Nodes::get_node_parent( $nodes->{ $temp_id } ) )
            {
                print $handle "$id\t$parent_id\n";
                $temp_id = $parent_id;
            }
        }
    };
    
    $argref = [ $handle ];

    &Taxonomy::Nodes::tree_traverse_head( $nodes, $id, $subref, $argref );
    
    return;
}

1;
