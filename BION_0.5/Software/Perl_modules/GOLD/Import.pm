package GOLD::Import;     #  perl package

# Import functions for the GOLD dataset by Nikos Kyrpides.

use strict;
use warnings;
use Data::Dumper;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &import_all
                 &normalize_data
                 &parse_data
                 );

use Common::Config;
use Common::Messages;
use Common::DB;
use Common::File;
use Common::Logs;

use GOLD::Schema;
use Taxonomy::DB;
use Taxonomy::Nodes;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<

sub import_all
{
    # Niels Larsen, August 2003.

    # Creates the tables "gold_main" and "gold_web" from the GOLD 
    # source data provided by Nikos Kyrpides. 

    my ( $readonly,   # If set creates database tables
         $errors,     # If set prints parsing errors 
         ) = @_;

    # Returns nothing. 

    my ( $dbh, $db_name, @db_table, $db_table, $db_file, $source_file,
         $entries, $entry, %keys, $key, @db_cols, $schema, $install_dir,
         $elem, $ids, $name, $nodes, $node, $id );

    $db_name = $Common::Config::proj_name;
    $source_file = "$Common::Config::gold_dir/gold.db";
    $install_dir = "$Common::Config::dat_dir/GOLD";

    $schema = &GOLD::Schema::relational();
    
    # Create database if it does not exist, then connect. And
    # if old tables exist delete them, 

    # >>>>>>>>>>>>>>>>> PREPARE/CONNECT TO DATABASE <<<<<<<<<<<<<<<<<

    if ( not $readonly )
    {
        &echo( qq (   Preparing database ... ) );

        &Common::DB::create_database_if_not_exists();
        $dbh = &Common::DB::connect();
        
        &Common::DB::delete_tables( $dbh, $schema );
        &Common::DB::create_tables( $dbh, $schema );
        
        &echo_green( "done\n" );
    }
    
    # >>>>>>>>>>>>>>>>>>>>>> PARSE DATA <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Parsing GOLD sources ... ) );

    $entries = &GOLD::Import::parse_data( $source_file );
    $entries = &GOLD::Import::normalize_data( $entries );

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>>> ASSIGN TAXONOMY IDS <<<<<<<<<<<<<<<<<<<<<<

    # We add these automated ones as "tax_id_auto" to indicate that it
    # is done automatically,
    
    &echo( qq (   Mapping taxonomy ids ... ) );

    $nodes = &Taxonomy::DB::get_subtree( $dbh, 1 );

    foreach $entry ( @{ $entries } )
    {
        $name = "$entry->{'genus'}";
        $name .= " $entry->{'species'}" if $entry->{"species"};
        $name .= " $entry->{'strain'}" if $entry->{"strain"};
        
        $name =~ s/\([^\)]+\)//g;

        $ids = &Taxonomy::DB::ids_from_name( $dbh, $name );

        my $hits;
        my $mark;

        if ( @{ $ids } > 1 )
        {
            $node = &Taxonomy::Nodes::get_nodes_parent( $ids, $nodes );
            $entry->{"tax_id_auto"} = &Taxonomy::Nodes::get_id( $node );
            $hits = "multi";
        }
        elsif ( @{ $ids } == 1 ) {
            $entry->{"tax_id_auto"} = $ids->[0];
            $hits = "single";
        } else {
            $entry->{"tax_id_auto"} = "";
            $hits = "none";
        }

        $entry->{"tax_id"} ||= "";

        if ( $entry->{"tax_id"} ne $entry->{"tax_id_auto"} )        {
            $mark = " * ";
        } else {
            $mark = "   ";
        }

        print qq ($mark\t$hits\t$entry->{"tax_id"}\t$entry->{"tax_id_auto"}\t$name\n);
    }

    &echo_green( "done\n" );

    # >>>>>>>>>>>>>>>>>> WRITE DB-READY TABLES <<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Writing tables to disk ... ) );

    &Common::File::create_dir_if_not_exists( $install_dir );

    $db_file = "$install_dir/gold_main.tab";

    if ( -e $db_file ) {
        &Common::File::delete_file( $db_file );
    }
    
    @db_table = ();
    @db_cols = map { $_->[0] } @{ $schema->{"gold_main"} };
    
    foreach $entry ( @{ $entries } )
    {
        push @db_table, [ map { defined $entry->{ $_ } ? $entry->{ $_ } : "" } @db_cols ];
    }

    &Common::Tables::write_tab_table( $db_file, \@db_table );

    $db_file = "$install_dir/gold_web.tab";

    if ( -e $db_file ) {
        &Common::File::delete_file( $db_file );
    }

    @db_table = ();
    @db_cols = grep { $_ !~ /^id$/i } map { $_->[0] } @{ $schema->{"gold_web"} };

    foreach $entry ( @{ $entries } )
    {
        if ( exists $entry->{"webdata"} )
        {
            foreach $elem ( @{ $entry->{"webdata"} } )
            {
                push @db_table, [ $entry->{"id"} || "", map { defined $elem->{ $_ } ? $elem->{ $_ } : "" } @db_cols ];
            }
        }
    }

    &Common::Tables::write_tab_table( $db_file, \@db_table );

    &echo_green( "done\n" );
  
    # >>>>>>>>>>>>>>>>>>>>>>>> LOAD TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<

    if ( not $readonly )
    {
        &echo( qq (   Loading tables into database ... ) );
        
        foreach $db_table ( "gold_main", "gold_web" )
        {
            &Common::DB::create_table( $dbh, $db_table, $schema->{ $db_table } );
            &Common::DB::load_table( $dbh, "$install_dir/$db_table.tab", $db_table );
        }

        &Common::DB::disconnect( $dbh );
        &echo_green( "done\n" );        
    }
}

sub parse_data
{
    # Bo Mikkelsen, June 2003.
    
    # Process gold.db to extract all field-names and their
    # values into array of hashes in memory - a hash per database
    # entry. The values of 'indexed' fields are added to arrays.
    # Other values are added as scalars

    my ( $file,     # Gold source file path
         $errors,   # Error list
         ) = @_;

    # Returns array of hashes.

    # gold.db field list. INFNAM, INFLNK, ANLYNAM, ANLYLNK, INSTNAM
    # INSTLNK, FUNDNAM, FUNDLNK, DATNAM, DATLNK, SEARNAM, SEARLNK,
    # CONTNAM and CONTLNK can hold more than one value: the values
    # from for example INFNAM_0, INFNAM_1 etc. The '_X' fields are
    # also represented since '_X' is equivalent to an empty field
    # (for example TYPE_X)
    #
    # Datastructure:
    # ( { "ID" => value,
    #     "TAXID" => value,
    #     "DOMAIN" => value,
    #     "GENUS" => value,
    #     "SPECIES" => value,
    #     "STRAIN" => value,
    #     "CHROMOSOME" => value,
    #     "TYPE" => value,
    #     "PHYLOGENY" => value,
    #     "STATUS" => value,
    #     "STATREP" => value,
    #     "WEBPAGE" => value,
    #     "SIZE" => value,
    #     "UNIT" => value,
    #     "NORFS" => value,
    #     "MAPLNK" => value,
    #     "PUB_JOURNAL" => value,
    #     "PUB_LNK" => value,
    #     "PUB_VOL" => value,
    #     "DATE" => value,
    #     "WEBDATA" => ( { "TYPE" => value,
    #                      "NAME" => value,
    #                      "LINK" => value,
    #                      "EMAIL" => value
    #                    },
    #                  )
    #   },
    # )

    $file = "$Common::Config::gold_release/gold.db" if not $file;

    my ( $entries, $line, $entry_no, $key, $prevkey, $value, $i, $taxid_set );

    if ( not open FILE, $file ) {
        &error(  qq(Could not open "$file") );
    }

    $entry_no = 0;
    $taxid_set = 1;

    while ( defined ( $line = <FILE> ) )
    {
        chomp ( $line );
        $line =~ s/__//g;   # Remove flanking __ from fieldnames

        if ( not $line =~ m/^\t/ ) {   # Parse left justified fields

            ( $key, $value ) = split ( /\t/, $line, 2 );

            # Undefined values are assigned the empty string, unless if it
            # is the WEBPAGE field, which can hold the value 0

            $value = "" unless ( defined ( $value ) or $key eq "WEBPAGE");

            $key =~ s/_[\dX]//;  # Remove trailing _X or _<number> from field names

            if ( $key eq "DOMAIN" ) {  # NEW ENTRY

                if ( $taxid_set ) {   # Did the previous entry have a taxid?
                    $taxid_set = 0;
                }
                else {
                    push @{ $errors }, &Common::Logs::format_error( qq (No "tax_id" field in entry: "$entry_no"\n));
                }

                $entry_no++;
                $entries->[$entry_no - 1]{"id"} = $entry_no;  # Enter ID key/value
                $i = 0;
            }

            $entries->[$entry_no - 1]{ lc $key } = $value;  # Enter other field/value pairs
        }

        elsif ( $line =~ s/^\t// )     # Parse indented fields
        {
            ( $key, $value ) = split ( /\t/, $line, 2 );

            $key =~ s/_\d+//;  # Remove trailing _<number> from field names
            $value = "" unless ( defined ( $value ) );  # Undefined equals empty string

            if ( $key =~ m/PUB_X/i ) {  # If PUB_X, the other PUB's are undefined
                $entries->[$entry_no - 1]{"pub_journal"} = "";
                $entries->[$entry_no - 1]{"pub_lnk"} = "";
                $entries->[$entry_no - 1]{"pub_vol"} = "";
            }
            elsif ( $key =~ m/DATE_X/ ) {  # If DATE_X, DATE is undefined
                $entries->[$entry_no - 1]{"date"} = "";
            }
            # Fields below are added to main hash
            elsif ( $key =~ m/SIZE|UNIT|NORFS|MAPLNK|PUB_JOURNAL|PUB_LNK|PUB_VOL|DATE/ ) {
                $entries->[$entry_no - 1]{ lc $key } = $value;
            }
            elsif ( $key =~ s/NAM// )
            {
                # Whereas the NAM and LNK fields are added to the WEBDATA substructure
                # (array of hashes)

                $entries->[$entry_no - 1]{"webdata"}[$i]{"type"} = $key 
                    unless ( $key =~ m/_X/ );
                $entries->[$entry_no - 1]{"webdata"}[$i]{"name"} = $value 
                    unless ( $key =~ m/_X/ );

                $key =~ s/_X//;  # Check for proper NAM/LNK pairing
                $prevkey = $key;
            }
            elsif ( $key =~ m/LNK/ ){
                &error( qq(Invalid NAM/LNK pair. In field "$key" in entry "$entry_no"\n) )
                    unless ( $key =~ m/$prevkey/ );

                if ( $key =~ m/INF/ and $value =~ m/Taxonomy/ ) {
                    if ( $value =~ m/id=(\d+)/ ) {
                        if ( $entries->[$entry_no - 1]{"tax_id"} )
                        {
                            $entries->[$entry_no - 1]{"tax_id"} .= " $1";
                            push @{ $errors }, &Common::Logs::format_error( qq(Multiple Taxonomy ids in entry "$entry_no"\n) );
                        }
                        else {
                            $entries->[$entry_no - 1]{"tax_id"} = $1;
                        }
                        $taxid_set = 1;
                    }
                }

                if ( $value =~ m/http|ftp/ ) {
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"link"} = $value;
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"email"} = "";
                }
                elsif ( $value =~ s/^ttp/http/ ) {  # Correct ttp error
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"link"} = $value;
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"email"} = "";
                    push @{ $errors }, &Common::Logs::format_error( qq(Invalid URL: In field "$key" in entry "$entry_no" "ttp" was changed to "http" in "$value"\n) );
                }
                elsif ( $value =~ m/@/ ) {
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"link"} = "";
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"email"} = $value;
                }
                elsif ( not $value eq "") {
                    push @{ $errors }, &Common::Logs::format_error( qq(Not valid URL/email: "$value". In field "$key" in entry "$entry_no"\n) );
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"link"} = "";
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"email"} = "";
                }
                else{
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"link"} = "";
                    $entries->[$entry_no - 1]{"webdata"}[$i]{"email"} = "";
                }
                # lines below handles cases where SOMETHINGNAM_X is followed by
                # SOMETHINGLNK holding a value
                $key =~ s/LNK//;
                $entries->[$entry_no - 1]{"webdata"}[$i]{"type"} = $key  
                    unless ( defined ( $entries->[$entry_no - 1]{"webdata"}[$i]{"type"} ) );
                $entries->[$entry_no - 1]{"webdata"}[$i]{"name"} = "" 
                    unless ( defined( $entries->[$entry_no - 1]{"webdata"}[$i]{"name"} ) );

                $i++;

            }
            else {
                push @{ $errors }, &Common::Logs::format_error( qq(Unknown field: "$key". New field type?\n));
            }
        }
          
    }

    if ( $taxid_set ) {   # Did the last entry have a taxid?
        $taxid_set = 0;
    }
    else {
        push @{ $errors }, &Common::Logs::format_error( qq(No "tax_id" field in entry: "$entry_no"\n));
    }

    close ( FILE );

    return wantarray ? @{ $entries } : $entries;
}

sub normalize_data
{
    my ( $entries,
         ) = @_;

    my ( $entry, $elem, $key, $val, $year, $months, $month, $day );

#    &dump( $entries );

#    exit;#
    # ---------- Remove leading and trailing blanks and slashes,

    foreach $entry ( @{ $entries } )
    {
        foreach $key ( keys %{ $entry } )
        {
            $val = $entry->{ $key };

            if ( ref $val eq "ARRAY" )
            {
                foreach $elem ( @{ $val } )
                {
                    &dump( $val );
                    exit;
                    foreach $key ( keys %{ $val } )
                    {
                        if ( defined $elem->{ $key } )
                        {
                            $elem->{ $key } =~ s/^\s*//;
                            $elem->{ $key } =~ s/\/?\s*$//;
                        }
                        else {
                            $elem->{ $key } = "";
                        }
                    }
                }
            }
            else
            {
                if ( defined $entry->{ $key } )
                {
                    $entry->{ $key } =~ s/^\s*//;
                    $entry->{ $key } =~ s/\/?\s*$//;
                }
                else {
                    $entry->{ $key } = "";
                }
            }
        }
    }

    # ----------- Convert date to MySQL format,

    $months = 
    {
        "january" => "01",
        "february" => "02",
        "march" => "03",
        "april" => "04",
        "may" => "05",
        "june" => "06",
        "july" => "07",
        "august" => "08",
        "september" => "09",
        "october" => "10",
        "november" => "11",
        "december" => "12",
    };

    foreach $entry ( @{ $entries } )
    {
        if ( $entry->{"date"} and $entry->{"date"} =~ /^\s*(.+?)\s*(\d+)\s*,\s*(\d+)/ )
        {
            ( $month, $day, $year ) = ( $1 || "January", $2 || "01", $3 || "1970" );

            $entry->{"date"} = $year ."-". $months->{ lc $month } ."-". $day;
        }
        else
        {
            $entry->{"date"} = "";
        }

    }
    
    # ----------- Convert sizes from M-bases or K-bases to bases,

    foreach $entry ( @{ $entries } )
    {
        if ( $entry->{"size"} and $entry->{"size"} > 0 )
        {
            if ( $entry->{"unit"} =~ /^kb$/i ) {
                $entry->{"size"} *= 1000;
            } elsif ( $entry->{"unit"} =~ /^mb$/i ) {
                $entry->{"size"} *= 1000000;
            } elsif ( not $entry->{"unit"} ) {
                $entry->{"size"} *= 1000;
            }
        }
    }

    return wantarray ? @{ $entries } : $entries;
}

1;


__END__
