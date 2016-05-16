package Common::DAG::Schema;     #  -*- perl -*-

# Schema definition for generic Directed Acyclic Graph database. 

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 $def_table
                 $edges_table
                 $synonyms_table
                 $xrefs_table
                 $stats_table
                 $db_prefix

                 &relational
                 &field_index
                  );

use Common::Messages;

our ( $def_table, $edges_table, $synonyms_table, $xrefs_table, 
      $stats_table, $db_prefix );

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub relational
{
    # Niels Larsen, October 2004.

    # Creates a hash where keys are table names and values are lists of 
    # [ field name, datatype, index specification ] where the index 
    # specification is optional. 

    # Returns a hash. 

    if ( not ( $def_table && $edges_table && $synonyms_table && $xrefs_table ) )
    {
        &error( "Table names not defined" );
        exit;
    }
    
    if ( not $db_prefix ) 
    {
        &error( "Database prefix not defined" );
        exit;
    }

    my ( $schema, $id_name );

    # The field names used here are used in several other routines, and 
    # in several directories, so dont change without good reason.
    
    $id_name = $db_prefix . "_id";

    $schema = 
    {
        "$def_table" => [
                         [ "$id_name", "int not null", "index $id_name"."_ndx ($id_name)" ],
                         [ "name", "varchar(255) not null", "index name_ndx (name,$id_name)" ],
                         [ "deftext", "text not null", "index deftext_ndx (deftext(255))" ],
                         [ "comment", "text not null", "index comment_ndx (comment(255))" ],
                         ],

        "$edges_table" => [
                           [ "$id_name", "int not null", "index $id_name"."_ndx ($id_name,parent_id)" ],
                           [ "parent_id", "int not null", "index parent_id_ndx (parent_id,$id_name)" ],
                           [ "dist", "tinyint not null", "index dist_ndx (dist,$id_name)" ],
                           [ "depth", "tinyint not null", "index depth_ndx (depth,$id_name)" ],
                           [ "leaf", "tinyint not null", "index leaf_ndx (leaf,$id_name)" ],
                           [ "rel", "char(1) not null", "index rel_ndx (rel,$id_name)" ],
                           ],
        
        "$synonyms_table" => [
                              [ "$id_name", "int not null", "index $id_name"."_ndx ($id_name)" ],
                              [ "name", "varchar(255) not null", "index name_ndx (name,$id_name)" ],
                              [ "syn", "varchar(255) not null", "index syn_ndx (syn,$id_name)" ],
                              [ "rel", "varchar(255) not null", "index rel_ndx (rel,$id_name)" ],
                              ],
        
        "$xrefs_table" => [
                           [ "$id_name", "int not null", "index $id_name"."_ndx ($id_name)" ],
                           [ "db", "varchar(255) not null", "index db_ndx (db,$id_name)" ],
                           [ "name", "varchar(255) not null", "index name_ndx (name,$id_name)" ],
                           ],

        "$stats_table" => [
                           [ "$id_name", "int not null", "index $id_name"."_ndx ($id_name)" ],
                           [ $db_prefix."_terms_tsum", "int unsigned not null default 0" ],
                           [ $db_prefix."_terms_usum", "int unsigned not null default 0" ],
                           ],
    };

    return $schema;
}

sub field_index
{
    # Niels Larsen, October 2004.

    # Simply returns the column index of a given field name in a
    # given schema.

    my ( $schema,    # Schema hash
         $table,     # Table name
         $field,     # Field name
         ) = @_;

    # Returns an integer.

    if ( not $table ) {
        &error( "Table name not given" );
        exit;
    }

    if ( not $field ) {
        &error( "Field name not given" );
        exit;
    }

    my ( $ndx, $i, $str );

    $ndx = undef;
    
    for ( $i = 0; $i < @{ $schema->{ $table } }; $i++ )
    {
        $str = $schema->{ $table }->[ $i ]->[0];

        if ( $field =~ /^$str$/i )
        {
            $ndx = $i;
            last;
        }
    }

    if ( defined $ndx ) {
        return $ndx;
    } else {
        return;
    }
}


1;

__END__
