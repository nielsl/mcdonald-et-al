package Common::DB;       # -*- perl -*- 

# Module with functions that access MySQL through, mostly, the DBI interface. 

use strict;
use warnings FATAL => qw ( all );

use DBI;
use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &add_row
                 &add_column
                 &connect
                 &connect_user
                 &count_rows
                 &create_database
                 &create_database_if_not_exists
                 &create_index
                 &create_table
                 &create_tables
                 &database_exists
                 &database_is_alive
                 &database_is_empty
                 &datatables_exist
                 &define_column
                 &delete_column
                 &delete_database
                 &delete_row
                 &delete_rows
                 &delete_table
                 &delete_tables
                 &delete_table_if_empty
                 &delete_tables_if_empty
                 &delete_table_if_exists
                 &disconnect
                 &highest_id
                 &insert_column
                 &insert_columns
                 &list_databases
                 &list_tables
                 &list_column_names
                 &list_columns
                 &load_table
                 &needs_update
                 &parse_fulltext
                 &query_array
                 &query_hash
                 &request
                 &table_exists
                 &column_exists
              );

use Common::Config;
use Common::Messages;

use Registry::Schema;
use Registry::Get;

our $Schema_name = "system";

our $dbh;
our $user_dbh;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub add_row
{
    # Martin A. Hansen, May 2003.

    # Appends a row to a given table. The row is given as 
    # a list of values. 
    
    my ( $dbh,    # Database handle
         $name,   # Table name
         $values, # Values to be inserted
         ) = @_;

    # Returns nothing. 
    
    my $sql;
    
    $sql = "insert into $name values ( " . join( ", ", @{ $values } ) . " );";

    &Common::DB::request( $dbh, $sql );

    return;
}

sub add_column
{
    # Niels Larsen, February 2005.

    # Defines a new column and loads a given list of values into it.
    # It is up to the caller to ensure the length of the list matches
    # the number of rows.

    my ( $dbh,
         $values,
         $tabname,
         $colname,
         $type,
         $index,
         ) = @_;

    # Returns nothing.

    &Common::DB::define_column( $dbh, $tabname, $colname, $type, $index );
    &Common::DB::insert_column( $dbh, $tabname, $colname, $values );

    return;
}

sub connect
{
    # Niels Larsen, December 2005.

    # Returns a database handle to a given database name. The routine will 
    # restart the server if it is not running (rare, but happens), and it 
    # checks if the returned handle responds.

    my ( $dsn,     # Database name - OPTIONAL
         $create,
         ) = @_;

    # Returns a database handle (scalar).

    my ( $dbh, $errstr, $user, $pass, $msg, $with_msgs );

    $create //= 0;

    # Connect without raising exception on error,

    $dsn = $Common::Config::proj_name || $Common::Config::db_master if not $dsn;

    if ( $create ) {
        &Common::DB::create_database_if_not_exists( $dsn );
    }

    $user = $Common::Config::db_user;
    $pass = $Common::Config::db_pass;

#    DBI->trace("15|SQL");

    # First try connect, gives no error usually,

    $dbh = DBI->connect( "dbi:mysql:$dsn", $user, $pass,
                         {
                             RaiseError => 0,
                             PrintError => 0,
                             AutoCommit => 1,
                         } );

    # If error try to recover,

    if ( $DBI::errstr )
    {
        # Try re-connect again; this will fix timeouts and a 
        # few other things they say,
        
        $dbh = DBI->connect( "dbi:mysql:$dsn", $user, $pass,
                             {
                                 RaiseError => 0,
                                 PrintError => 0,
                                 AutoCommit => 1,
                             } );
        
        # If that didnt work, make fatal errors,

        if ( not defined $dbh )
        {
            $msg = qq (No MySQL database handle. DBI error: $DBI::errstr\n)
                  .qq (Check that MySQL is running, start it with start_mysql);

            &Common::Messages::error( $msg );
        }
        elsif ( not $dbh->ping )
        {
            $msg = qq (MySQL handle is not alive.);
            
            if ( $DBI::errstr ) {
                $msg .= qq ( DBI error: $DBI::errstr);
            } else {
                $msg .= qq ( No DBI error.);
            }

            &Common::Messages::error( $msg );
        }
    }

    if ( $dbh ) {
        return $dbh;
    } else {
        return;
    }
}

sub connect_user
{
    # Niels Larsen, November 2005.

    # Connects to a user database. If it does not exist it is created. 

    my ( $sid,
         ) = @_;

    # Returns a database handle. 

    my ( $dir, $dbh, $sidstr, $link, $inst_name );

    if ( not $sid ) {
        &Common::Messages::error( qq (No session id given) );
    }

    $sidstr = $sid;
    $sidstr =~ s/\//_/g;

    if ( not &Common::DB::database_exists( $sidstr ) )
    {
        $dir = "$Common::Config::ses_dir/$sid/Database";
        &Common::File::create_dir_if_not_exists( $dir );

        $link = "$Common::Config::dbs_dir/$sidstr";
        &Common::File::create_link_if_not_exists( $dir, $link );
    }

    $dbh = &Common::DB::connect( $sidstr );

    return $dbh;
}

sub count_rows
{
    # Niels Larsen, October 2006.

    # Returns the number of rows of a given table.

    my ( $dbh, 
         $name,         # Table name
         ) = @_;

    # Returns an integer.

    my ( $sql, $count );

    $sql = qq (select count(*) from $name );

    $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];

    return $count;
}

sub create_database
{
    # Niels Larsen, March 2003.

    # Uses command line tool (mysqladmin) to create a new database.
    # The DBI interface requires a database handle, so I dont see 
    # how to use the 'CREATE DATABASE' sql command from perl. 

    my ( $name,    # Database name
         ) = @_;

    # Returns nothing. 

    my ( $mysqladmin, $command, @output );

    require Common::Admin;

    if ( &Common::Admin::mysql_is_running() )
    {
        $name = $Common::Config::proj_name if not $name;

        $mysqladmin = "$Common::Config::bin_dir/mysqladmin";

        $command = "$mysqladmin create $name --socket=$Common::Config::db_sock_file";
        $command .= " --user=$Common::Config::db_user --password=$Common::Config::db_pass 2>&1";
        
        @output = `$command`;
        
        if ( @output ) {
            &Common::Messages::error( \@output );
        }
    }
    else {
        &Common::Messages::error( qq (MySQL is not running. Start it with "start_mysql") );
    }

    return;
}        

sub create_database_if_not_exists
{
    # Niels Larsen, March 2003.

    # Uses command line tool (mysqladmin) to create a new database
    # but only if it does not exist already. 

    my ( $name,    # Database name
         ) = @_;

    # Returns nothing. 

    $name = $Common::Config::proj_name if not $name;

    if ( not &Common::DB::database_exists( $name ) )
    {
        &Common::DB::create_database( $name );
        return 1;
    }

    return;
}        

sub create_index 
{
    # Niels Larsen, March 2011.

    # Creates an index on an existing table.

    my ( $dbh,
         $args,
        ) = @_;

    my ( $request, $sql );

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( ndx_name tab_name ) ], 
            "AR:1" => [ qw ( col_names ) ],
        });

    $sql = "create index";

    $sql .= " ". $args->ndx_name ." on ". $args->tab_name;
    $sql .= " (". (join ",", @{ $args->col_names }) .")";

    &Common::DB::request( $dbh, $sql );

    return;
}

sub create_table
{
    # Niels Larsen, May 2005.

    # Creates a database table, given a registry table object. 
    # SHOULD BE REDONE

    my ( $dbh,    # Database handle
         $table,  # Table object
         $topt,   # Table option(s) - OPTIONAL
         $index,  # Index flag - OPTIONAL, default 1
         ) = @_;

    # Returns nothing. 

    my ( $tab_name, $sql, $col, $name, $type, $ndxstr );
    
    $tab_name = $table->name;

    $sql = qq (create table $tab_name \();
    
    foreach $col ( $table->columns )
    {
        $name = $col->[0];
        $type = $col->[1];
        $ndxstr = $col->[2];

        $sql .= qq ($name $type, );
        
        if ( $index ) {
            $sql .= qq ($ndxstr, );
        }
    }

    $sql =~ s/(, *)+$//;
    $sql .= ")";

    if ( $topt ) {
        $sql .= " $topt";
    }

    &Common::DB::request( $dbh, $sql );

    return;
}

sub create_tables
{
    # Niels Larsen, December 2006.

    # Creates all tables of a given schema. If any of the tables exist
    # already, its an error. Returns the number of tables created. 

    my ( $dbh,        # Database handle
         $schema,     # Schema name or structure
         $prefix,     # Database file prefix
         ) = @_;

    # Returns an integer.

    my ( $table, $count, $table2 );

    $count = 0;
    $prefix = "" if not defined $prefix;

    foreach $table ( $schema->tables )
    {
        if ( not &Common::DB::table_exists( $dbh, $prefix . $table->name ) )
        {
            $table2 = &Storable::dclone( $table );
            $table2->name( $prefix . $table2->name );

            &Common::DB::create_table( $dbh, $table2 );
            $count += 1;
        }
    }
    
    return $count;
}

sub database_exists
{
    # Niels Larsen, March 2003.

    # Lists all databases and returns true if a given database
    # name is in the list.

    my ( $name,   # Database name
         ) = @_;

    # Returns 1 or nothing.
    
    $name = $Common::Config::proj_name if not $name;

    if ( grep /$name$/, &Common::DB::list_databases() ) {
        return 1;
    } else {
        return;
    }
}

sub database_is_empty
{
    my ( $dbh,
         ) = @_;

    if ( @{ &Common::DB::list_tables( $dbh ) } ) {
        return;
    } else {
        return 1;
    }

    return;
}
    
sub datatables_exist
{
    # Niels Larsen, October 2005.

    # Returns true if all tables of a given schema exist in the database,
    # otherwise returns nothing. 

    my ( $dbh,       # Database handle - OPTIONAL
         $schema,    # Schema name or object
         ) = @_;
    
    # Returns boolean. 
    
    my ( $table, $missing, $must_close );

    if ( not defined $dbh ) 
    {
        $dbh = &Common::DB::connect();
        $must_close = 1;
    }
    
    foreach $table ( $schema->tables )
    {
        if ( not &Common::DB::table_exists( $dbh, $table->name ) )
        {
            $missing = 1;
            last;
        }
    }

    if ( $must_close ) {
        &Common::DB::disconnect( $dbh );
    }
    
    if ( not $missing ) {
        return 1;
    } else {
        return;
    }
}

sub define_column
{
    # Martin A. Hansen, May 2003.

    # Defines a column, given by its name, in a table. It does
    # not fill it with values. 

    my ( $dbh,      # Database handle
         $tabname,  # Table name
         $colname,  # Name of column
         $type,     # Variable type
         $index,    # Index name - OPTIONAL
       ) = @_;

    # Returns nothing. 

    my $sql;

    if ( $index ) {
        $sql = "ALTER TABLE $tabname ADD COLUMN ( $colname $type, INDEX $index ( $colname ) )";
    } else {
        $sql = "ALTER TABLE $tabname ADD COLUMN ( $colname $type )";
    }
    
    &Common::DB::request( $dbh, $sql );
    
    return;
}

sub delete_column
{
    # Martin A. Hansen, May 2003.

    # Deletes a column, given by name, from a given table.

    my ( $dbh,       # Databse handle
         $tabname,   # Table name
         $colname,   # column to be deleted
         ) = @_;

    # Returns nothing. 

    my $sql;

    $sql = "alter table $tabname drop column $colname";

    &Common::DB::request( $dbh, $sql );

    return;
}

sub delete_database
{
    # Niels Larsen, May 2003.

    # Deletes ("drops") the database that the given handle is
    # connected to. This includes all the database tables, so 
    # use with care. 

    my ( $dbh,     # Database handle
         $name,    # Database name
         ) = @_;

    # Returns nothing.

    my $sql = qq (drop database $name);

    &Common::DB::request( $dbh, $sql );

    return;
}

sub delete_row
{
    # Martin A. Hansen, May 2003.

    # Deletes a row from a table, identified by a given name and
    # value. The deletion happens only if a single row matches this
    # description, otherwise a fatal error. 

    my ( $dbh,       # Database handle
         $tabname,   # Table name
         $field,     # Field e.g. rec no
         $value,     # Value
       ) = @_;

    # Returns nothing.

    my ( $count, $sql );

    $sql = qq( select $field from $tabname where $field = "$value" );
    
    $count = scalar map { $_->[0] } &Common::DB::query_array( $dbh, $sql );

    if ( $count > 1 )
    {
        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( qq (Will not delete: $count rows have $field set to "$value"), "DELETE ROW ERROR" );
    }
    elsif ( $count == 0 )
    {
        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( qq (No rows have $field set to "$value"), "DELETE ROW ERROR" );
    }
    else
    {
        $sql = qq (delete from $tabname where $field = "$value");
        &Common::DB::request( $dbh, $sql );
    }

    return;
}

sub delete_rows
{
    # Niels Larsen, May 2009.
    
    # Deletes rows from a given table that have the given field and 
    # value. Returns the number of rows deleted.

    my ( $dbh,       # Database handle
         $tabname,   # Table name
         $field,     # Field e.g. rec no
         $value,     # Value
       ) = @_;

    # Returns integer.

    my ( $count, $sql );

    $sql = qq (delete from $tabname where $field = "$value");

    $count = &Common::DB::request( $dbh, $sql );

    return $count;
}
    
sub delete_table
{
    # Niels Larsen, April 2003.

    # Deletes ("drops") a table in the database that the given handle is 
    # connected to. 

    my ( $dbh,     # Database handle
         $name,    # Table name
         ) = @_;

    # Returns nothing.
    
    &Common::DB::request( $dbh, "drop table $name" );

    return;
}

sub delete_tables
{
    # Niels Larsen, October 2005.

    # Deletes all database tables for a given schema. 
    
    my ( $dbh,       # Database handle
         $schema,    # Schema object
         $prefix,    # Database file prefix
         ) = @_;

    # Returns nothing.

    my ( $args, $table, $must_close, $count );

    $prefix = "" if not defined $prefix;

    if ( not defined $dbh ) 
    {
        $dbh = &Common::DB::connect();
        $must_close = 1;
    }

    $count = 0;

    foreach $table ( @{ $schema->table_names } )
    {
        if ( &Common::DB::table_exists( $dbh, "$prefix$table" ) )
        {
            &Common::DB::delete_table( $dbh, "$prefix$table" );
            $count += 1;
        }
    }

    if ( $must_close ) {
        &Common::DB::disconnect( $dbh );
    }
    
    return $count;
}

sub delete_table_if_empty
{
    # Niels Larsen, August 2006.
    
    # Counts the rows of a given table and deletes the table if
    # there are none. 

    my ( $dbh,     # Database handle
         $name,    # Table name
         ) = @_;

    # Returns nothing. 

    my ( $sql, $count );

    if ( &Common::DB::table_exists( $dbh, $name ) )
    {
        $sql = qq (select count(*) from $name);

        $count = &Common::DB::query_array( $dbh, $sql )->[0]->[0];
        
        if ( $count == 0 ) {
            &Common::DB::delete_table( $dbh, $name );
            return 1;
        }
        else {
            return;
        }
    }
    else {
        return;
    }
}

sub delete_tables_if_empty
{
    # Niels Larsen, September 2006.
    
    # Deletes all tables in a given schema that are empty. Returns the 
    # number of tables deleted. 

    my ( $dbh,     # Database handle
         $schema,  # Schema name or object
         ) = @_;

    # Returns nothing. 

    my ( $count, $table );

    $count = 0;

    foreach $table ( $schema->tables )
    {
        if ( &Common::DB::delete_table_if_empty( $dbh, $table->name ) )
        {
            $count += 1;
        }
    }

    return $count;
}

sub delete_table_if_exists
{
    # Niels Larsen, April 2003.

    # Deletes ("drops") a table if it exists in the database that 
    # the given handle is connected to. 

    my ( $dbh,     # Database handle
         $name,    # Table name
         ) = @_;

    # Returns nothing.

    if ( &Common::DB::table_exists( $dbh, $name ) )
    {
        &Common::DB::request( $dbh, "drop table $name" );
    }

    return;
}

sub disconnect
{
    # Niels Larsen, March 2003.

    # Disconnects and destroys a given database handle. The tables are optionally
    # "flushed", because that seems to prevent errors when connecting. 

    my ( $dbh,     # Database handle
         $flush,   # Whether to flush tables - OPTIONAL, default on
         ) = @_;

    # Returns nothing.

    $flush = 0 if not defined $flush;

    if ( $flush ) {
        &Common::DB::request( $dbh, "flush tables" );
    }

    if ( not $dbh->disconnect )
    {
        &Common::Messages::error( $DBI::errstr );
    }

    return;
}

sub highest_id
{
    # Niels Larsen, October 2005.

    # Returns the highest number in a given column in a given table.

    my ( $dbh,        # Database handle
         $tabname,    # Table name 
         $colname,    # Column name
         ) = @_;

    # Returns a number.

    my ( $sql, $id );

    if ( &Common::DB::table_exists( $dbh, $tabname ) )
    {
        $sql = qq (select max($colname) from $tabname);
        $id = &Common::DB::query_array( $dbh, $sql )->[0]->[0];
    }
    else {
        $id = 0;
    }

    return $id;
}

sub insert_column
{
    # Niels Larsen, February 2005.

    # Inserts a list of values in a given column of a given table.
    # The list elements are tuples where first element is a unique
    # key, second is the value. The table must have unique keys 
    # that match those in the list of tuples. 
    
    my ( $dbh,        # Database handle
         $tabname,    # Table name 
         $colname,    # Column name
         $values,     # List of lists of values
         ) = @_;

    # Returns nothing.

    my ( $sql, $valstr );

    $valstr = join ",", @{ $values };
    $sql = qq (insert into $tabname ($colname) values ($valstr));

    &Common::DB::request( $dbh, $sql );

    return;
}
    
sub insert_columns
{
    # Niels Larsen, May 2003.

    # Inserts a list of values in a given column of a given table.
    # The list elements are tuples where first element is a unique
    # key, second is the value. The table must have unique keys 
    # that match those in the list of tuples. 
    
    my ( $dbh,         # Database handle
         $tabname,     # Table name 
         $columns,     # Column names
         $values,      # List of lists of values
         ) = @_;

    # Returns nothing.

    my ( $sql, $elem, $key, $valstr, $fldstr );

    $fldstr = join ",", @{ $columns };

    foreach $elem ( @{ $values } )
    {
        $valstr = join ",", @{ $elem };
        
        $sql = qq (insert into $tabname ($fldstr) values ($valstr));
        &Common::DB::request( $dbh, $sql );
    }

    return;
}

sub list_databases
{
    # Niels Larsen, April 2003.

    # Returns a list of databases available. This is done
    # with a mysql-specific command line utility, because
    # DBI->data_sources does not list the databases when
    # user name and password is set - and I dont see a way
    # of supplying it.

    # Returns a list. 

    my ( @list );

    @list = DBI->data_sources( "mysql", {

        "user" => $Common::Config::db_user,
        "password" => $Common::Config::db_pass,
    });

    return wantarray ? @list : \@list;
}

sub list_tables
{
    # Niels Larsen, April 2003.

    # Lists the tables in the database that the given handle 
    # is connected to. 

    my ( $dbh,     # Database handle
         ) = @_;

    # Returns a list. 

    my ( @list );

    @list = &Common::DB::query_array( $dbh, "show tables" );

    if ( @list ) { 
        @list = map { $_->[0] } @list;
    } else { 
        @list = ();
    }

    return wantarray ? @list : \@list;
}

sub list_column_names
{
    # Niels Larsen, February 2005.

    # Creates a list of column names for a given table.

    my ( $dbh,        # Database handle
         $tabname,    # Table name
         ) = @_;

    # Returns a list.

    my ( @names );

    @names = map { $_->[0] } @{ &Common::DB::list_columns( $dbh, $tabname ) };

    return wantarray ? @names : \@names;
}

sub list_columns
{
    # Niels Larsen, February 2005.

    # Creates a list of column descriptions, each of which is a small 
    # list.  

    my ( $dbh,        # Database handle
         $tabname,    # Table name
         ) = @_;

    # Returns a list.

    my ( $sql, @list );

    $sql = qq (show columns from $tabname);

    @list = &Common::DB::query_array( $dbh, $sql );
    
    return wantarray ? @list : \@list;
}

sub load_table
{
    # Niels Larsen, April 2003.

    # Loads the content of a given file into a given database table,
    # optionally the named columns only. Returns the number of rows
    # loaded. 

    my ( $dbh,          # Database handle
         $file,         # File name
         $tabname,        # Table name
         $cols,         # Column names - OPTIONAL
         ) = @_;

    # Returns integer.

    my ( $sql );

    $sql = qq (load data local infile '$file' into table $tabname fields terminated by '\\t' lines terminated by '\\n');

    if ( $cols ) {
        $sql .= qq ( ($cols));
    }

    return &Common::DB::request( $dbh, $sql );
}

sub needs_update
{
    # Niels Larsen, August 2006.

    # Returns 1 if a given database older than a given date (as epoch
    # seconds), nothing otherwise. 

    my ( $time,        # Time to test (epoch seconds)
         $db_type,     # Data type, e.g. "orgs_taxa", "rna_ali", etc
         $db_name,     # Database name, e.g. "rRNA_18S_500"
         ) = @_;

    # Returns 1 or nothing.

    my ( $db_stats, $dbh, $schema, $sql, $db_time, $needs_update, $table );

    $db_stats = "db_stats";

    $dbh = &Common::DB::connect();

    if ( &Common::DB::table_exists( $dbh, $db_stats ) )
    {
        # Get time of last update,

        $sql = qq (select date from $db_stats where type = "$db_type" and name = "$db_name");

        $db_time = &Common::DB::query_array( $dbh, $sql )->[0];

        if ( defined $db_time )
        {
            $db_time = &Common::Util::time_string_to_epoch( $db_time );
            
            if ( $time > $db_time ) {
                $needs_update = 1;
            }
        }
        else {
            $needs_update = 1;
        }
    }
    else
    {
        # Create the "data_stats" table if it does not exist,

        $table = Registry::Schema->get( $Schema_name )->table( $db_stats );
        &Common::DB::create_table( $dbh, $table );
        
        $needs_update = 1;
    }

    &Common::DB::disconnect( $dbh );

    if ( $needs_update ) {
        return 1;
    } else {
        return;
    }
}

sub parse_fulltext
{
    # Niels Larsen, July 2009.

    # Creates a list of strings from a MySQL fulltext search text. The 
    # plus signs etc are stripped, but double-quoted strings kept intact.
    # It is useful for example to help perl highlight matches in an output.

    my ( $text,
        ) = @_;

    # Returns a list.

    my ( @strings, @list );

    @strings = ( $text =~ /\"([^\"]+)\"/g );
    $text =~ s/\"([^\"]+)\"//g;

    @list = split " ", $text;
    @list = map { $_ =~ s/^[\+\-\(\)\~\<\>]//; $_ } @list;
    @list = map { $_ =~ s/[\*]$//; $_ } @list;

    @list = map { split /\W/, $_ } @list;

    unshift @list, @strings;

    return wantarray ? @list : \@list;
}
    
sub query_array
{
    # Niels Larsen, April 2003.

    # Executes a given sql query and returns the result as a table
    # or table reference. 

    my ( $dbh,   # Database handle
         $sql,   # SQL string
         $out,   # Output specification, see DBI documentation. 
         ) = @_;

    # Returns a list.

    my ( $sth, $table, $errstr, @status );

    if ( not $dbh ) {
        &Common::Messages::error( qq (\$dbh is not defined) );
    }
#     elsif ( not $dbh->ping ) 
#     {
#         &Common::Messages::error( qq (\$dbh is not alive) );
#     }

#    &dump( $sql );
    if ( not $sth = $dbh->prepare( $sql ) ) 
    {
        $errstr = $DBI::errstr;

        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( $errstr, "SQL PREPARE ERROR" );
    }
    
    if ( not eval { $sth->execute } )
    {
        $errstr = $DBI::errstr;

        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( $errstr, "SQL EXECUTE ERROR" );
    }
    
    if ( $table = $sth->fetchall_arrayref( $out ) )
    {
#        &Common::Messages::dump( $sql );
        return wantarray ? @{ $table } : $table;
    }
    else
    {
        $errstr = $DBI::errstr;
        
        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( $errstr, "DATABASE RETRIEVE ERROR" );
    }
    
    return;
}

sub query_hash
{
    # Niels Larsen, April 2003.

    # Executes a given sql query and returns the result as a hash
    # or hash reference. The keys are set to the values of the given
    # key. 

    my ( $dbh,   # Database handle
         $sql,   # SQL string
         $key,   # Key string, like "id" - OPTIONAL, default "id"
         ) = @_;

    # Returns a hash.

    if ( not $dbh ) {
        &Common::Messages::error( qq (\$dbh is not defined) );
    }
#     elsif ( not $dbh->ping ) 
#     {
#         &Common::Messages::error( qq (\$dbh is not alive) );
#     }
    $key = "id" if not defined $key;

    my ( $sth, $hash, $errstr );
    
    if ( not $sth = $dbh->prepare( $sql ) ) 
    {
        $errstr = $DBI::errstr;
        
        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( $errstr, "SQL PREPARE ERROR" );
    }
    
    if ( not $sth->execute )
    {
        $errstr = $DBI::errstr;
        
        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( $errstr, "SQL EXECUTE ERROR" );
    }
    
    if ( $hash = $sth->fetchall_hashref( $key ) )
    {
        return wantarray ? %{ $hash } : $hash;
    }
    else
    {
        $errstr = $DBI::errstr;
        
        &Common::DB::disconnect( $dbh );
        &Common::Messages::error( $errstr, "DATABASE RETRIEVE ERROR" );
    }

    return;
}

sub request
{
    # Niels Larsen, April 2003.
    
    # Runs a given sql command on a given database handle. This
    # routine should be used for commands that do not return a 
    # result; for searches, use the 'query_array' and 'query_hash'
    # routines. 

    my ( $dbh,   # Database handle
         $sql,   # SQL string 
         ) = @_;

    # Returns integer. 

    my ( $sth, $errstr, $count );

    $count = 0;

    if ( not $dbh ) {
        &Common::Messages::error( qq (\$dbh is not defined) );
    }
#     elsif ( not $dbh->ping ) 
#     {
#         &Common::Messages::error( qq (\$dbh is not alive) );
#     }

    if ( not $sth = $dbh->prepare( $sql ) ) 
    {
        $errstr = $DBI::errstr;

        &Common::DB::disconnect( $dbh, 0 );
        &Common::Messages::error( $errstr, "SQL PREPARE ERROR" );
    }

    if ( not defined ( $count = $sth->execute ) )
    {
        $errstr = $DBI::errstr;
        
        &Common::DB::disconnect( $dbh, 0 );
        &Common::Messages::error( $errstr, "SQL EXECUTE ERROR" );
    }

    return $count * 1;
}

sub table_exists
{
    # Niels Larsen, March 2003.

    # Checks if a given table is in the table list for a 
    # given database handle. 

    my ( $dbh,    # Database handle
         $name,   # Table name
         ) = @_;

    # Returns 1 or nothing.

    if ( grep /^$name$/, @{ &Common::DB::list_tables( $dbh ) } ) {
        return 1;
    } else {
        return;
    }
}

1;

__END__
