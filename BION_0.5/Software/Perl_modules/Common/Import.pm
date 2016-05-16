package Common::Import;     #  -*- perl -*-

# Routines that are related to data import. They print messages 
# by default, but these can be switched off by setting 
# $Common::Config::silent to 1.

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );
use Filesys::Df;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_tabfile_handles
                 &delete_tabfiles
                 &load_tabfiles
                 );

use Common::Config;
use Common::Messages;

use Common::Storage;
use Common::OS;

use Registry::Schema;
use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub create_tabfile_handles
{
    my ( $dir,
         $schema,
         $mode,
         ) = @_;

    my ( $table, $fhs, $tab_name );

    $mode ||= "<";

    if ( defined $schema )
    {
        foreach $table ( $schema->tables )
        {
            $tab_name = $table->name;

            if ( $mode eq ">>" ) {
                $fhs->{ $tab_name } = &Common::File::get_append_handle( "$dir/$tab_name" );
            } elsif ( $mode eq ">" ) {
                $fhs->{ $tab_name } = &Common::File::get_write_handle( "$dir/$tab_name" );
            } else {
                &error( qq (Wrong looking write mode -> "$mode") );
            }
        }
    }
    else {
        &error( qq (No schema given) );
    }

    return $fhs;
}

sub delete_tabfiles
{
    # Niels Larsen, September 2006.

    # Deletes the database table files (if any) in a given directory that
    # are named as the database tables in a given schema. The number of
    # files deleted are returned. No error if the file does not exist.

    my ( $dir,           # Directory to delete in 
         $schema,        # Schema object
         ) = @_;

    # Returns an integer.

    my ( $count, $table, $tabfile );

    $count = 0;

    if ( -d $dir )
    {
        foreach $table ( $schema->tables )
        {
            $tabfile = "$dir/". $table->name;

            if ( -e $tabfile )
            {
                &Common::File::delete_file( $tabfile );
                $count += 1;
            }
        }

        &Common::File::delete_dir_if_empty( $dir );
    }

    return $count;
}

sub load_tabfiles
{
    # Niels Larsen, March 2011.
    
    # Loads a set of tab-separated tables into corresponding database tables. The
    # table file names must match the database table names, as defined by the given
    # given schema name. If a file is missing according to that schema, a fatal 
    # error happens. If a given database table does not exist, then it is first
    # loaded, then indices are created on it. If it does exist, then the indices
    # updates during loading (which is often much less effective). Returns the 
    # total number of rows loaded.

    my ( $db,        # Database or handle
         $args,      # Arguments hash
         ) = @_;

    # Returns integer.

    my ( $dbh, $count, $schema, $replace, @tables, $table, $tabdir, $tname,
         $total, $must_close, $rows, $prefix, $col, @missing );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( schema tab_dir ) ], 
            "S:0" => [ qw ( replace prefix ) ], 
        });

    $schema = $args->schema;
    $tabdir = $args->tab_dir;
    $replace = $args->replace || 0;
    $prefix = $args->prefix || "";

    # >>>>>>>>>>>>>>>>>>>>> CHECK ALL TABLES ARE PRESENT <<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Are all tab-files present ... ) );

    $schema = Registry::Get->schema( $schema );
    bless $schema, "Registry::Schema";
    
    @tables = @{ $schema->tables };

    foreach $table ( @tables )
    {
        if ( not $table->{"optional"} and not -r "$tabdir/". $table->name )
        {
            push @missing, $table->name;
        }
    }

    if ( not @missing )
    {
        &echo_green( "yes\n" );
    }
    else
    {
        &echo_red( "NO" );
        &error( "Missing tables: ". (join ", ", @missing) ."\n" );
    }

    if ( ref $db ) {
        $dbh = $db;
    } else {
        $dbh = &Common::DB::connect( $db );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>> LOAD AND INDEX TABLES <<<<<<<<<<<<<<<<<<<<<<<<<

    $count = 0;

    foreach $table ( @tables )
    {
        $tname = $table->name;

        next if not -r "$tabdir/$tname";

        if ( $replace and &Common::DB::table_exists( $dbh, $tname ) )
        {
            &Common::DB::delete_table( $dbh, $tname );
        }

        if ( &Common::DB::table_exists( $dbh, $tname ) )
        {
            # >>>>>>>>>>>>>>>>>>>>>> ADD TO EXISTING <<<<<<<<<<<<<<<<<<<<<<<<<<

            &echo( qq (   Adding $tname to database ... ) );

            $rows = &Common::DB::load_table( $dbh, "$tabdir/$tname", "$prefix$tname" );
            $count += $rows;

            &echo_done( "$rows row[s]\n" );
        }
        else
        {
            # >>>>>>>>>>>>>>>>>>>>>>> LOAD AND INDEX <<<<<<<<<<<<<<<<<<<<<<<<<<

            &echo( qq (   Loading $tname table ... ) );

            &Common::DB::create_table( $dbh, $table, undef, 0 );
            
            $rows = &Common::DB::load_table( $dbh, "$tabdir/$tname", "$prefix$tname" );
            $count += $rows;

            &echo_done( "$rows row[s]\n" );

            &echo( qq (   Creating $tname indices ... ) );

            foreach $col ( @{ $table->columns } )
            {
                if ( exists $col->[2] )
                {
                    if ( $col->[2] =~ /index\s+(\S+)\s+\(([^\)]+)\)/ )
                    {
                        &Common::DB::create_index(
                             $dbh,
                             {
                                 "tab_name" => $tname,
                                 "ndx_name" => $1,
                                 "col_names" => [ split /\s*,\s*/, $2 ],
                             });
                    }
                    else {
                        &error( qq (Wrong looking schema index string -> "$col->[2]") );
                    }
                }
            }

            &echo_green( "done\n" );
        }
    }

    if ( not ref $db ) {
        &Common::DB::disconnect( $dbh );
    }

    return $count;
}

1;

__END__
