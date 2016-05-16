package Common::DBM;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Abstract DBM access functions that provide error checks and packing and 
# unpacking of data structures as values. The underlying library is Kyoto 
# Cabinet, see http://fallabs.com/kyotocabinet.
#
# UNFINISHED 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

# use Storable qw ( freeze thaw );

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &append
                 &close
                 &delete
                 &delete_bulk
                 &flush
                 &get
                 &get_bulk
                 &get_struct
                 &get_struct_bulk
                 &_open_mode_bits
                 &_open_file_desc
                 &open
                 &put
                 &put_bulk
                 &put_struct
                 &put_struct_bulk
                 &read_open
                 &read_tie
                 &tie
                 &untie
                 &write_open
                 );

use KyotoCabinet;
use Data::MessagePack;

use Common::Config;
use Common::Messages;

# >>>>>>>>>>>>>>>>>>>>>>>>>>> BION DEPENDENCY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# The &error function is exported from the Common::Messages module if part of 
# BION, i.e. if the shell environment BION_HOME is set. If not, the &error 
# function is defined here to use plain confess,

BEGIN
{
    if ( $ENV{"BION_HOME"} ) {
        eval qq (use Common::Messages);
    } else {
        eval qq (use Carp; sub error { confess("Error: ". (shift) ."\n") });
    }
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub append
{
    # Niels Larsen, February 2011. 
    
    # Appends a given value to the given key. Returns 1 on success or 
    # crashes.

    my ( $dbh,    # DB handle
         $key,    # String key
         $val,    # String value
        ) = @_;

    # Returns 1 or crash.
    
    my ( $msg );
    
    if ( not $dbh->append( $key, $val ) )
    {
	$msg = $dbh->error;
	&error( "Could not append $key value: $msg" );
    }

    return 1;
}

sub close
{
    # Niels Larsen, February 2011.

    # Closes an open handle. Returns 1 on success or crashes.

    my ( $dbh,     # DB handle
        ) = @_;

    # Returns 1 or nothing.

    my ( $msg );

    if ( not $dbh->close() )
    {
        $msg = $dbh->error;
        &error( "Could not close handle: $msg" );
    }

    return 1;
}
 
sub delete
{
    # Niels Larsen, February 2011.

    # Deletes a single key-value pair. Returns 1 on success. Crashes if 
    # failure, but if $fatal is set to 0 nothing is returned.

    my ( $dbh,     # DB handle
         $key,     # Key string
         $fatal,   # Fatal flag - OPTIONAL, default 1
        ) = @_;

    # Returns 1 or nothing.
    
    my ( $msg );

    $fatal //= 1;

    if ( $dbh->remove( $key ) )
    {
        return 1;
    }
    elsif ( $fatal )
    {
        $msg = $dbh->error;
        &error( "Could not delete $key: $msg" );
    }

    return;
}
 
sub delete_bulk
{
    # Deletes a list of key-value pairs. Returns 1 on success. Crashes 
    # if failure.

    my ( $dbh,     # DB handle
         $keys,    # Key string list
        ) = @_;

    # Returns 1 or nothing.
    
    my ( $msg, $count );

    $count = $dbh->remove_bulk( $keys );

    if ( $count == -1 )
    {
        $msg = $dbh->error;
        $count = scalar @{ $keys };
        &error( "Could not delete $count keys: $msg" );
    }

    return $count;
}

sub flush
{
    # Niels Larsen, February 2011.

    # Synchronizes internal DBM buffers with the file system. 
    # Returns nothing.

    my ( $dbh,      # DB handle
        ) = @_;

    # Returns nothing.

    $dbh->synchronize;

    return;
}

sub get
{
    # Niels Larsen, February 2011. 
    
    # Returns a single value for a given key. Crashes if the key is not found,
    # except if $fatal set to 0 then nothing is returned.

    my ( $dbh,    # DB handle
         $key,    # Key string
	 $fatal,  # Crash flag - OPTIONAL, default 1
        ) = @_;

    # Returns string or nothing.
    
    my ( $val, $msg );

    $fatal //= 1;

    if ( defined ( $val = $dbh->get( $key ) ) )
    {
        return $val;
    }
    elsif ( $fatal )
    {
        $msg = $dbh->error;
        &error( "Could not get $key: $msg" );
    }
    
    return;
}

sub get_bulk
{
    # Niels Larsen, February 2011. 

    # Gets a hash with key/values for a given list of keys. Crashes if no keys 
    # are found, except if $fatal is set to 0 then nothing is returned.

    my ( $dbh,    # DB handle
         $keys,   # Key list
	 $fatal,  # Crash flag - OPTIONAL, default 1
        ) = @_;

    # Returns 1 or nothing.
    
    my ( $vals, $msg, $count );

    $fatal //= 1;

    if ( defined ( $vals = $dbh->get_bulk( $keys ) ) )
    {
        return $vals;
    }
    elsif ( $fatal )
    {
        $msg = $dbh->error;
        $count = scalar @{ $keys };
        &error( "Could not get any of the $count given keys: $msg" );
    }

    return;
}

sub get_struct
{
    # Niels Larsen, February 2011.

    # Returns reference to a memory structure that has been saved in string form 
    # with put_struct. Crashes if the key is not found, but if $fatal is set to 
    # 0 then nothing is returned.  

    my ( $dbh,     # DB handle
         $key,     # Key string
	 $fatal,   # Crash flag - OPTIONAL, default 1
        ) = @_;
    
    # Returns reference or nothing.

    my ( $val, $msg );

    $fatal //= 1;

    if ( defined ( $val = $dbh->get( $key ) ) )
    {
        return Data::MessagePack->unpack( $val );
    }
    elsif ( $fatal )
    {
        $msg = $dbh->error;
        &error( "Could not get $key: $msg" );
    }

    return;
}

sub get_struct_bulk
{
    # Niels Larsen, February 2011. 

    # Gets a hash with key/values for a given list of keys. The values are
    # hash or list references unpacked with Data::MessagePack. Crashes if 
    # no keys are found, except if $fatal is set to 0 then nothing is 
    # returned.

    my ( $dbh,    # DB handle
         $keys,   # Key list
	 $fatal,  # Crash flag - OPTIONAL, default 1
        ) = @_;

    # Returns 1 or nothing.
    
    my ( $key, $vals, $msg, $count );

    $fatal //= 1;

    if ( defined ( $vals = $dbh->get_bulk( $keys ) ) )
    {
        foreach $key ( @{ $keys } )
        {
            if ( $vals->{ $key } ) {
                $vals->{ $key } = Data::MessagePack->unpack( $vals->{ $key } );
            } elsif ( $fatal ) {
                &error( qq (Key not found in key/value storage -> "$key") );
            }
        }

        return $vals;
    }
    elsif ( $fatal )
    {
        $msg = $dbh->error;
        $count = scalar @{ $keys };
        &error( "Could not get any of the $count given keys: $msg" );
    }

    return;
}

sub _open_file_desc
{
    my ( $file,
         $params,
         $type,
        ) = @_;

    my ( $desc );

    if ( defined $type )
    {
        if ( $type eq "hash" ) {
            $desc = "$file#type=kch";
        } elsif ( $type eq "btree" ) {
            $desc = "$file#type=kct";
        } else {
            &error( qq (Wrong type -> "$type". Should be either "hash" or "btree") );
        }
    }
    else {
        $type = "btree";
    }
    
    if ( defined $params ) {
        $desc = "$desc#" . join "#", map { $_ ."=". $params->{ $_ } } keys %{ $params };
    }
    
    return $desc;
}

sub _open_mode_bits
{
    my ( $modes,
        ) = @_;

    my ( %defs, $code );

    if ( defined $modes )
    {
        $modes = [ split /\s*,\s*/, $modes ] if not ref $modes;

        if ( not grep { $_ eq "OREADER" or $_ eq "OWRITER" } @{ $modes } ) {
            &error( "Either OREADER or OWRITER mode must be given" );
        }
    }
    else {
        $modes = ["OREADER"];
    }
    
    %defs = (
        "OWRITER" => 1,
        "OREADER" => 1,
        "OCREATE" => 1,
        "OTRUNCATE" => 1,
        "OAUTOTRAN" => 1,
        "OAUTOSYNC" => 1,
        "ONOLOCK" => 1,
        "OTRYLOCK" => 1,
        "ONOREPAIR" => 1,
        );

    map { &error( qq (Wrong looking mode -> "$_") ) if not exists $defs{ $_ } } @{ $modes };

    $code = join ' | ', map { "\$dbh->$_" } @{ $modes };
#    $code = eval $code;

    return $code;
}
    
sub open
{
    # Niels Larsen, January 2011.

    # Opens a kyoto cabinet store. TODO
    
    my ( $file,      # File path
         %args,
        ) = @_;

    # Returns KC object.

    my ( $modes, $params, $type, $fatal, $dbh, $msg, $modstr, $mcode, $fdesc );
    
    $modes = $args{"modes"};       # IO modes 
    $params = $args{"params"};     # Parameter key / values
    $type //= "btree";             # "hash" or "btree"
    $fatal = $args{"fatal"} // 1;  # To error-crash or not

    # Set file descriptor (file name followed by # and maybe parameters),

    $fdesc = &Common::DBM::_open_file_desc( $file, $params, $type );

    # Set Fcntl open mode, OWRITER etc,
    
    $mcode = &Common::DBM::_open_mode_bits( $modes );

    # Open,

    if ( $dbh = KyotoCabinet::DB->new() and $dbh->open( $fdesc, eval $mcode ) )
    {
        return $dbh;
    }
    elsif ( $fatal )
    {
        $msg = $dbh->error;

        if ( ref $modes ) {
            $modstr = join ", ", @{ $modes };
        } else {
            $modstr = $modes;
        }

        &error( "Could not access $fdesc: $msg\nModes were: $modstr" );
    }

    return;
}

sub put
{
    # Niels Larsen, February 2011. 

    # Stores a single key and value. Crashes if failure.

    my ( $dbh,   # DB handle
         $key,   # Key string
         $val,   # Value string
        ) = @_;

    # Returns 1 or crash.

    my ( $msg );
    
    if ( not $dbh->set( $key, $val ) )
    {
	$msg = $dbh->error;
	&error( "Could not put $key value: $msg" );
    }

    return 1;
}

sub put_bulk
{
    # Niels Larsen, February 2011. 

    # Stores a hash of string keys and values. Crashes if something goes
    # wrong. Return 1 on success. 

    my ( $dbh,       # DB handle
         $hash,      # Key and value strings
        ) = @_;

    # Returns 1 or crash.
    
    my ( $msg, $count );
    
    if ( not $dbh->set_bulk( $hash ) )
    {
	$msg = $dbh->error;
        $count = ( keys %{ $hash } );

	&error( "Could not put hash with $count keys: $msg" );
    }

    return 1;
}

sub put_struct
{
    # Niels Larsen, February 2011.

    # Stores a string key and a structure which can be list or hash, but not
    # object or file handle. Returns 1 on success, crashes is something wrong.

    my ( $dbh,     # DB handle
         $key,     # Key string
         $ref,     # Structure reference
        ) = @_;

    # Returns 1 or crash.

    my ( $msg );
    
    if ( not $dbh->set( $key, Data::MessagePack->pack( $ref ) ) )
    {
	$msg = $dbh->error;
	&error( "Could not put_struct $key value: $msg" );
    }

    return 1;
}

sub put_struct_bulk
{
    # Niels Larsen, November 2012.

    # Stores a hash of string keys and values which are hash or list references.
    # The values are stringified with Data::MessagePack into a scratch hash that 
    # uses some memory. Crashes if something goes wrong. Return 1 on success. 

    my ( $dbh,       # DB handle
         $hash,      # Key strings and value structures
        ) = @_;

    # Returns 1 or crash.
    
    my ( $key, $str_hash, $msg, $count );

    foreach $key ( keys %{ $hash } )
    {
        $str_hash->{ $key } = Data::MessagePack->pack( $hash->{ $key } );
    }

    if ( not $dbh->set_bulk( $str_hash ) )
    {
	$msg = $dbh->error;
        $count = ( keys %{ $str_hash } );

	&error( "Could not put hash with $count keys: $msg" );
    }

    return 1;
}

sub read_open
{
    # Niels Larsen, February 2010.

    # Opens in readonly mode. Creates a new file if needed. Returns a DBM 
    # handle object. 

    my ( $file,      # File path
         %args,      # Arguments hash
        ) = @_;

    # Returns object.

    my ( $dbh );

    $file = &Common::File::full_file_path( $file );

    if ( -r $file ) {
        $dbh = &Common::DBM::open( $file, %args, "modes" => ["OREADER"] );
    } else {
        &error( qq (Index file not found -> "$file") );
    }

    return $dbh;
}

sub read_tie
{
    my ( $file,
         $params,
         $type,
        ) = @_;

    my ( $dbh, $hash );
    
    if ( -r $file ) {
        ( $dbh, $hash ) = &Common::DBM::tie( $file, ["OREADER"], $params, $type );
    } else {
        &error( qq (Storage file not found -> "$file") );
    }

    return ( $dbh, $hash );
}

sub tie
{
    my ( $file,
         $modes,
         $params,
         $type,
        ) = @_;

    my ( %hash, $dbh, $fdesc, $mcode, $msg, $modstr );

    $type //= "btree";

    # Set file descriptor (file name followed by # and maybe parameters),

    $fdesc = &Common::DBM::_open_file_desc( $file, $params, $type );

    # Set Fcntl open mode, OWRITER etc,
    
    $mcode = &Common::DBM::_open_mode_bits( $modes );

    if ( not ( $dbh = tie ( %hash, "KyotoCabinet::DB", $fdesc, eval $mcode ) ) )
    {
        $msg = $dbh->error;

        if ( ref $modes ) {
            $modstr = join ", ", @{ $modes };
        } else {
            $modstr = $modes;
        }

        &error( "Could not tie $fdesc: $msg\nModes were: $modstr" );
    }

    return ( $dbh, \%hash );
}

sub untie
{
    my ( $dbh,
         $hash,
        ) = @_;

    undef $dbh;

    if ( $dbh ) {
        &error( qq (Could not undef DBM handle) );
    }

    if ( not untie %{ $hash } ) {
        &error( qq (Could not untie DBM hash) );
    }

    return;
}

sub write_open
{
    # Niels Larsen, February 2011.

    # Opens for writes and reads. Creates a new file if needed. Returns
    # a DBM database handle. 

    my ( $file,      # File path
         %args,      # Arguments hash
        ) = @_;

    # Returns object.

    my ( $dbh, $modes, @modes );

    $modes = $args{"modes"};

    if ( defined $modes )
    {
        if ( ref $modes ) {
            @modes = @{ $modes };
        } else {
            @modes = split /\s*,\s*/, $modes;
        }

        @modes = grep { $_ !~ /^OREADER|OWRITER|OCREATE$/ } @modes;
    }

    unshift @modes, "OWRITER","OCREATE";

    $file = &Common::File::full_file_path( $file );

    $dbh = &Common::DBM::open(
        $file, 
        "modes" => \@modes,
        "params" => $args{"params"},
        "type" => $args{"type"} // "btree",
        "fatal" => $args{"fatal"} // 1,
        );

    return $dbh;
}

1;

__END__

Open a database file.

@param path the path of a database file. If it
is "-", the database will be a prototype hash database. If it is "+",
the database will be a prototype tree database. If it is ":", the
database will be a stash database. If it is "*", the database will be
a cache hash database. If it is "%", the database will be a cache tree
database. If its suffix is ".kch", the database will be a file hash
database. If its suffix is ".kct", the database will be a file tree
database. If its suffix is ".kcd", the database will be a directory
hash database. If its suffix is ".kcf", the database will be a
directory tree database. Otherwise, this function fails. Tuning
parameters can trail the name, separated by "#". Each parameter is
composed of the name and the value, separated by "=". If the "type"
parameter is specified, the database type is determined by the value
in "-", "+", ":", "*", "%", "kch", "kct", "kcd", and "kcf". All
database types support the logging parameters of "log", "logkinds",
and "logpx". The prototype hash database and the prototype tree
database do not support any other tuning parameter. The stash database
supports "bnum". The cache hash database supports "opts", "bnum",
"zcomp", "capcnt", "capsiz", and "zkey". The cache tree database
supports all parameters of the cache hash database except for capacity
limitation, and supports "psiz", "rcomp", "pccap" in addition. The
file hash database supports "apow", "fpow", "opts", "bnum", "msiz",
"dfunit", "zcomp", and "zkey". The file tree database supports all
parameters of the file hash database and "psiz", "rcomp", "pccap" in
addition. The directory hash database supports "opts", "zcomp", and
"zkey". The directory tree database supports all parameters of the
directory hash database and "psiz", "rcomp", "pccap" in addition.

@param mode the connection mode. KyotoCabinet::DB::OWRITER as a
writer, KyotoCabinet::DB::OREADER as a reader. The following may be
added to the writer mode by bitwise-or: KyotoCabinet::DB::OCREATE,
which means it creates a new database if the file does not exist,
KyotoCabinet::DB::OTRUNCATE, which means it creates a new database
regardless if the file exists, KyotoCabinet::DB::OAUTOTRAN, which
means each updating operation is performed in implicit transaction,
KyotoCabinet::DB::OAUTOSYNC, which means each updating operation is
followed by implicit synchronization with the file system. The
following may be added to both of the reader mode and the writer mode
by bitwise-or: KyotoCabinet::DB::ONOLOCK, which means it opens the
database file without file locking, KyotoCabinet::DB::OTRYLOCK, which
means locking is performed without blocking,
KyotoCabinet::DB::ONOREPAIR, which means the database file is not
repaired implicitly even if file destruction is detected.  

@return true on success, or false on failure.

@note The tuning parameter
"log" is for the original "tune_logger" and the value specifies the
path of the log file, or "-" for the standard output, or "+" for the
standard error. "logkinds" specifies kinds of logged messages and the
value can be "debug", "info", "warn", or "error". "logpx" specifies
the prefix of each log message. "opts" is for "tune_options" and the
value can contain "s" for the small option, "l" for the linear option,
and "c" for the compress option. "bnum" corresponds to
"tune_bucket". "zcomp" is for "tune_compressor" and the value can be
"zlib" for the ZLIB raw compressor, "def" for the ZLIB deflate
compressor, "gz" for the ZLIB gzip compressor, "lzo" for the LZO
compressor, "lzma" for the LZMA compressor, or "arc" for the Arcfour
cipher. "zkey" specifies the cipher key of the compressor. "capcnt" is
for "cap_count". "capsiz" is for "cap_size". "psiz" is for
"tune_page". "rcomp" is for "tune_comparator" and the value can be
"lex" for the lexical comparator or "dec" for the decimal
comparator. "pccap" is for "tune_page_cache". "apow" is for
"tune_alignment". "fpow" is for "tune_fbp". "msiz" is for
"tune_map". "dfunit" is for "tune_defrag". Every opened database must
be closed by the PolyDB::close method when it is no longer in use. It
is not allowed for two or more database objects in the same process to
keep their connections to the same database file at the same time.
