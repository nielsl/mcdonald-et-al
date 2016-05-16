package Ali::DB;     #  -*- perl -*-

# Functions specific to alignment databasing. Some are retrieval functions,
# some are housekeeping functions. 

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use File::Basename;

@EXPORT_OK = qw (
                 &count_entries
                 &delete_entries
                 &get_fts
                 &get_fts_clip
                 &get_fts_ali_seq_cons
                 &get_fts_ali_rna_pairs
                 &highest_feature_id
                 &list_features
                 &load_features
                 );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::DB;
use Common::Import;

use Ali::Common;
use Ali::Feature;
use Ali::Schema;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub count_entries
{
    # Niels Larsen, March 2007.

    my ( $dbh,
         $ids,
         ) = @_;

    my ( $sql, $count, $idstr );

    $sql = qq (select count(*) from ali_features);

    if ( defined $ids )
    {
        $idstr = join qq (", "), @{ $ids };
        $sql .= qq ( where source in ("$idstr"));
    }

    $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

    return $count;
}

sub delete_entries
{
    # Niels Larsen, April 2006.

    # Deletes a set of feature entries from the database, given by their
    # data source name (e.g. "SRPDB"), their data type (e.g. "rna_ali") 
    # and their ids. As more arguments are added, the more "fine-grained"
    # selective the deletion becomes. Returns the number of records 
    # deleted. 

    my ( $dbh,        # Database handle
         $source,     # Data source
         $datatype,   # Data type - OPTIONAL
         $ali_ids,    # Alignment ids - OPTIONAL
         ) = @_;

    # Returns an integer.

    my ( $schema, @tables, $where, $sql, $table, $count, @ft_ids, $ft_ids );

    if ( not defined $source ) {
        &error( qq (Data source is not defined) );
    }

    $schema = Ali::Schema->get;

    if ( &Common::DB::datatables_exist( $dbh, $schema ) )
    {
        @tables = $schema->table_names;

        $where = "source = '$source'";
        
        if ( $datatype ) {
            $where .= " and ali_type = '$datatype'";
        }
        
        if ( defined $ali_ids )
        {
            if ( ref $ali_ids ) {
                $where .= " and ali_id in ('" . (join "','", @{ $ali_ids }) . "')";
            } else {
                $where .= " and ali_id = '$ali_ids'";
            }
        }
        
        $sql = qq (select ft_id from ali_features where $where);
        @ft_ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

        $count = 0;
        
        if ( @ft_ids )
        {
            @ft_ids = sort { $a <=> $b } &Common::Util::uniqify( \@ft_ids );

            foreach $table ( @tables )
            {
                if ( &Common::DB::table_exists( $dbh, $table ) )
                {
                    $ft_ids = join ",", @ft_ids;
                    $sql = qq (delete from $table where ft_id in ( $ft_ids ));
                    $count += &Common::DB::request( $dbh, $sql );
                }
            }
        }

        return scalar @ft_ids;
    }
    else {
        return 0;
    }
}

sub get_fts_ali_seq_cons
{
    my ( $self,
         $dbh,
         $args,
        ) = @_;

    my ( $colstr, $sql, $fts );

    $colstr = join ",", @{ $self->global_cols };

    $sql = qq (and ft_type = "$args->{'ft_type'}" and colbeg in ($colstr));

    $fts = &Ali::DB::get_fts_clip( $self, $dbh, { "sql" => $sql } );

    return $fts;
}

sub get_fts
{
    # Niels Larsen, February 2006.

    # Retrieves all areas of the features that overlap with the given 
    # alignment slice. An optional type prefix and minimum score filters
    # the matches. 

    my ( $self,      # Alignment
         $dbh,       # Database handle
         $args,
         ) = @_;

    # Returns a list. 

    my ( $ali_id, $colmin, $colmax, $rowmin, $rowmax, $sql, @fts,
         @ids, $idstr, $sqlstr, $scostr, @table, $row, %areas, $source );
    
#    &time_start;

    # Optionally filter by type and score,

    if ( $args->{"sql"} ) {
        $sqlstr = $args->{"sql"};
    } elsif ( $args->{"ft_type"} ) {
        $sqlstr = qq (and ft_type = "$args->{'ft_type'}");
    } else {
        $sqlstr = "";
    }
        
    if ( defined $args->{"score"} ) {
        $scostr = "and score >= $args->{'score'}";
    } else {
        $scostr = "";
    }
    
    # Get ids of features that overlap,

    $ali_id = $self->sid;
    $source = $self->source;

    $colmin = $self->min_col_global;
    $colmax = $self->max_col_global;
    
    $rowmin = $self->min_row_global;
    $rowmax = $self->max_row_global;

    $sql = qq (select distinct ft_id from ali_feature_pos)
         . qq ( where ali_id = "$ali_id" $sqlstr and source = "$source")
         . qq ( and not ( rowend < $rowmin or rowbeg > $rowmax ))
         . qq ( and not ( colend < $colmin or colbeg > $colmax ))
         . qq ( $scostr);

    @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    # For each of those ids, get the attributes including all areas,
    # not just those that overlap the alignment,

    if ( @ids )
    {
        $idstr = join ",", @ids;
        
        $sql = qq (select ft_id, colbeg, colend, rowbeg, rowend,)
             . qq ( title, descr, styles, spots from ali_feature_pos)
             . qq ( where ft_id in ($idstr));

        @table = &Common::DB::query_array( $dbh, $sql );

        foreach $row ( @table )
        {
            push @{ $areas{ $row->[0] } }, [ @{ $row }[ 1..8 ] ];
        }
        
        $sql = qq (select ft_id, ft_type, score, stats)
             . qq ( from ali_features where ft_id in ($idstr));
        
        @table = &Common::DB::query_array( $dbh, $sql );

        foreach $row ( @table )
        {
            push @fts, Ali::Feature->new(
                                         "id" => $row->[0],
                                         "type" => $row->[1],
                                         "score" => $row->[2],
                                         "stats" => $row->[3],
                                         "areas" => $areas{ $row->[0] },
                                         );
        }
    }

#    &time_elapsed(undef, "get_features");

    return wantarray ? @fts : \@fts;
}

sub get_fts_clip
{
    # Niels Larsen, February 2006.

    # Retrieves features that overlap with the given alignment slice,
    # with the overlapping areas only. An optional type name and 
    # minimum score filters the matches. 

    my ( $self,         # Alignment
         $dbh,          # Database handle
         $args,         # Arguments hash
        ) = @_;

    # Returns a list. 

    my ( $ali_id, $source, $sql, @fts, $idstr, $array, $row, %areas, $sql_add );

    # Get feature areas that overlap and create a hash of them,

    $ali_id = $self->sid;
    $source = $self->source;

#     my @cols = @{ $self->global_cols };
#     &dump( scalar @cols );

#     my @rows = @{ $self->global_rows };
#     &dump( scalar @rows );

    if ( $args->{"sql"} ) {
        $sql_add = $args->{"sql"};
    } elsif ( $args->{"ft_type"} ) {
        $sql_add = qq (and ft_type = "$args->{'ft_type'}");
    } else {
        &error( qq (Neither ft_type or sql given) );
    }
    
    $sql = qq ( select ft_id, colbeg, colend, rowbeg, rowend,)
         . qq ( title, descr, styles, spots from ali_feature_pos)
         . qq ( where ali_id = "$ali_id" and source = "$source")
         . qq ( $sql_add );

    $array = &Common::DB::query_array( $dbh, $sql );

    foreach $row ( @{ $array } )
    {
        push @{ $areas{ $row->[0] } }, [ @{ $row }[ 1..8 ] ];
    }

    # Get the corresponding ids and make feature objects,

    if ( %areas )
    {
        $idstr = join ",", keys %areas;

        $sql = qq (select ft_id, ft_type, score, stats)
             . qq ( from ali_features where ft_id in ($idstr));

        $array = &Common::DB::query_array( $dbh, $sql );

        foreach $row ( @{ $array } )
        {
            push @fts, Ali::Feature->new(
                                         "id" => $row->[0],
                                         "type" => $row->[1],
                                         "score" => $row->[2],
                                         "stats" => $row->[3],
                                         "areas" => $areas{ $row->[0] },
                                         );
        }
    }
    else {
        @fts = ();
    }

#    &time_elapsed(undef, "get_features_clip");

    return wantarray ? @fts : \@fts;
}

sub get_fts_ali_rna_pairs
{
    my ( $self,
         $dbh,
         $args,
        ) = @_;

    my ( $fts, $sql );
    
    if ( $args->{"ft_type"} ) {
        $sql = qq (and ft_type like "$args->{'ft_type'}%");
    }

    $fts = &Ali::DB::get_fts( $self, $dbh, { "sql" => $sql } );

    return $fts;
}
         
sub get_fts_ali_covar_pairs
{
    my ( $self,
         $dbh,
         $args,
        ) = @_;

    my ( $fts, $sql );

    if ( $args->{"ft_type"} ) {
        $sql = qq (and ft_type like "$args->{'ft_type'}%");
    }

    $fts = &Ali::DB::get_fts( $self, $dbh, { "sql" => $sql } );

    return $fts;
}
         
sub highest_feature_id
{
    # Niels Larsen, February 2007.

    # Returns the highest feature id

    my ( $dbh,
         ) = @_;

    my ( $id );

    $id = &Common::DB::highest_id( $dbh, "ali_features", "ft_id" ) || 0;

    return $id;
}

sub list_features
{
    # Niels Larsen, August 2007.

    my ( $dbh,
         $ali_id,
        ) = @_;

    my ( $sql, $list );

    $sql = qq ( select distinct ft_type from ali_features where ali_id = "$ali_id");

    $list = &Common::DB::query_array( $dbh, $sql );
    $list = [ map { $_->[0] } @{ $list } ];

    return wantarray ? @{ $list } : $list;
}
    
sub load_features
{
    # Niels Larsen, April 2006.

    # Loads the feature tables in a given directory into database and 
    # optionally deletes the table files. The routine does not delete
    # existing features with same alignment id and type etc. 

    my ( $dbh,       # Database handle
         $dir,       # Table directory
         $delete,    # Delete tables, OPTIONAL - default 1
         ) = @_;

    # Returns an integer.

    my ( $schema, $count );

    $delete = 0 if not defined $delete;

    $schema = Ali::Schema->get;

    if ( not &Common::DB::datatables_exist( $dbh, $schema ) )
    {
        &Common::DB::create_tables( $dbh, $schema ) and sleep 1;
    }

    $count = &Common::Import::load_tabfiles(
        $dbh,
        {
            "tab_dir" => $dir,
            "schema" => $schema->name,
        });

    if ( $delete )
    {
        &Common::Import::delete_tabfiles( $dir, $schema );
        &Common::File::delete_dir_if_empty( $dir );
    }
    
    return $count;
}

1;

__END__

# sub get_features_nopos
# {
#     # Niels Larsen, April 2006.

#     # Retrieves a set of features that have no column or row positions,
#     # for examble label text. 

#     my ( $self,      # Alignment
#          $dbh,       # Database handle
#          $type,      # Feature type string
#          ) = @_;

#     # Returns a list. 

#     my ( $ali_id, $sql, $fts );

#     $ali_id = $self->sid;

#     $sql = qq (select * from ali_features)
#          . qq ( where ali_id = "$ali_id" and ft_type = "$type");

#     $fts = &Common::DB::query_array( $dbh, $sql );

#     return wantarray ? @{ $fts } : $fts;
# }

# sub delete_entries_source
# {
#     # Niels Larsen, October 2005.

#     # Deletes all entries of a given source. Returns the number of 
#     # entries deleted.
    
#     my ( $dbh,       # Database handle
#          $source,    # String like "Rfam"
#          ) = @_;

#     # Returns an integer. 

#     my ( $sql, @ids );

#     $sql = qq (select distinct(ali_id) from ali_annotation where source = '$source');
#     @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

#     &Ali::DB::delete_entries_ids( $dbh, \@ids );

#     return scalar @ids;
# }

# sub trim_database
# {
#     my ( $dbh,
#          $cl_args,
#          ) = @_;

#     my ( $schema, $rna_src, $count );

#     $schema = Ali::Schema->get;

#     $rna_src = $cl_args->{"source"};

#     if ( &Common::DB::database_exists() )
#     {
#         if ( &Common::DB::datatables_exist( $dbh, $schema ) )
#         {
#             if ( $cl_args->{"delete"} )
#             {
#                 # Delete tables if requested,

#                 &echo( qq (   Deleting whole alignment database ... ) );
#                 &Common::DB::delete_tables( $dbh, $schema );
#                 &echo_green( "done\n" );
#             }
#             elsif ( $cl_args->{"replace"} )
#             {
#                 # Delete records if requested,

#                 &echo( qq (   Deleting old $rna_src database ... ) );

#                 $count = &Ali::DB::delete_entries_source( $dbh, $rna_src );
#                 $count = &Common::Util::commify_number( $count || 0 );
#                 &echo_green( "$count gone\n" );
#             }
#         }
        
#         # Initialize database if needed,

#         if ( not &Common::DB::datatables_exist( $dbh, $schema ) )
#         {
#             &echo( qq (   Initializing database tables ... ) );            
#             &Common::DB::create_tables( $dbh, $schema ) and sleep 1;
#             &echo_green( "done\n" );
#         }
#     }
#     else
#     {
#         # Create database if needed,
    
#         &echo( qq (   Creating new database ... ) );
#         &Common::DB::create_database() and sleep 1;
#         &echo_green( "done\n" );
#     }

#     return;
# }


# sub get_features_pairs
# {
#     # Niels Larsen, February 2006.

#     # Retrieves a list of alignment pairs where one side or the other overlap
#     # with the given alignment. Returns a feature list.

#     my ( $self,      # Alignment
#          $dbh,       # Database handle
#          $type,      # Feature type string - OPTIONAL, default "helix_mask"
#          ) = @_;

#     # Returns a list.

#     my ( $ali_id, $colbeg, $colend, $rowbeg, $rowend, $sql, @fts, $ft,
#          @ids, $idstr, $temp1, $temp2, $i, $orig, $styles );

#     $type = "helix_mask" if not defined $type;

#     $ali_id = &File::Basename::basename( $self->file );

#     if ( defined ( $orig = $self->_orig_cols ) ) {
#         $colbeg = $orig->at(0);
#         $colend = $orig->at(-1);
#     } else {
#         $colbeg = 0;
#         $colend = $self->max_col;
#     }
    
#     if ( defined ( $orig = $self->_orig_rows ) ) {
#         $rowbeg = $orig->at(0);
#         $rowend = $orig->at(-1);
#     } else {
#         $rowbeg = 0;
#         $rowbeg = $self->max_row;
#     }

#     # First get ids of features that overlap given alignment,

#     $sql = qq (select ft_id from ali_feature_pos )
#          . qq (where ali_id = "$ali_id" and ft_type like "$type%" and )
#          . qq (rowend >= $rowbeg and rowbeg <= $rowend and )
#          . qq (colend >= $colbeg and colbeg <= $colend order by ft_id);

#     @ids = map { $_->[0] } &Common::DB::query_array( $dbh, $sql );
#     $idstr = join ",", @ids;

#     # Then get positions for those ids,

#     $sql = qq (select ft_type, ft_id, colbeg, colend, rowbeg, rowend from )
#          . qq (ali_feature_pos where ft_id in ($idstr) order by ft_id);

#     @fts = &Common::DB::query_array( $dbh, $sql );

#     # Then get and add styles,

#     $sql = qq (select ft_id, styles from ali_features where ft_id in ($idstr));

#     $styles = &Common::DB::query_hash( $dbh, $sql, "ft_id" );

#     foreach $ft ( @fts )
#     {
#         $ft->[8] = $styles->{ $ft->[1] }->{"styles"};
#     }

#     return wantarray ? @fts : \@fts;
# }
