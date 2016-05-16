package Expr::DB;     #  -*- perl -*-

# Routines that fetch expression related things out of the database. 
#
# TODO: project specific routines should be moved to sub-modules.

use strict;
use warnings FATAL => qw ( all );

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

use List::Compare;

@EXPORT_OK = qw (
                 &get_exp_ids
                 &get_exp_titles
                 &get_exp_descriptions
                 &get_exp_values
                 &mc_missing_mirids
                 &mc_missing_genids
                 &mc_query
                 &mc_mirnas
                 &split_names
                  );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::DB;
use Common::Table;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub get_exp_ids
{
    # Niels Larsen, April 2004.

    # Returns a list of [ exp_id, cond_id ] for a given list of 
    # condition ids. If no condition ids given, all experiments 
    # are returned. 

    my ( $dbh,
         $cond_ids,
         ) = @_;

    # Returns a list.

    my ( $sql, $cond_str, $tuples );

    if ( $cond_ids )
    {
        if ( ref $cond_ids ) 
        {
            $cond_str = join ",", @{ $cond_ids };
            $sql = qq ( select exp_id, cond_id from exp_experiment where cond_id in ( $cond_str ) );
        }
        else {
            $sql = qq ( select exp_id, cond_id from exp_experiment where cond_id = $cond_ids );
        }
    }
    else {
        $sql = qq (select exp_id, cond_id from exp_experiment);
    }

    $tuples = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $tuples } : $tuples;
}

sub get_exp_titles
{
    my ( $dbh,
         $exp_ids,
         ) = @_;

    my ( $sql, $id_str, $tuples );

    if ( not ref $exp_ids ) {
        $exp_ids = [ $exp_ids ];
    }

    $id_str = join ",", @{ $exp_ids };
    $sql = qq ( select exp_experiment.exp_id, exp_condition.title from exp_experiment )
         . qq ( natural join exp_condition where exp_experiment.exp_id in ( $id_str ) );

    $tuples = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $tuples } : $tuples;
}

sub get_exp_descriptions
{
    my ( $dbh,
         $exp_ids,
         ) = @_;

    my ( $sql, $id_str, $tuples );

    if ( not ref $exp_ids ) {
        $exp_ids = [ $exp_ids ];
    }

    $id_str = join ",", @{ $exp_ids };
    $sql = qq ( select exp_experiment.exp_id, exp_condition.descr from exp_experiment )
         . qq ( natural join exp_condition where exp_experiment.exp_id in ( $id_str ) );

    $tuples = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $tuples } : $tuples;
}

sub get_exp_values
{
    my ( $dbh,
         $exp_id,
         ) = @_;

    my ( $sql, $id_str, $tuples );
    
    $sql = qq ( select gen_id, value from exp_matrix where exp_id = $exp_id );

    $tuples = &Common::DB::query_array( $dbh, $sql );

    return wantarray ? @{ $tuples } : $tuples;
}

sub mc_missing_mirids
{
    # Niels Larsen, July 2009.
    
    # Returns a list of mir ids that are not in the MiRConnect table.

    my ( $dbh,
         $names,
         $method,
        ) = @_;

    # Returns a list.

    my ( $sql, $namstr, %found, @missing );

    $namstr = join qq (","), @{ $names };
    $sql = qq (select mir_id from mir_names where mir_id in ("$namstr") and method = "$method");

    %found = map { uc $_->[0], 1 } @{ &Common::DB::query_array( $dbh, $sql ) };
    
    @missing = grep { not $found{ uc $_ } } @{ $names };

    return wantarray ? @missing : \@missing;
}

sub mc_missing_genids
{
    # Niels Larsen, July 2009.
    
    # Returns a list of mRNA ids that are not in the MiRConnect table.

    my ( $dbh,
         $names,
        ) = @_;

    # Returns a list.

    my ( $sql, $namstr, %found, @missing );

    $namstr = join qq (","), @{ $names };
    $sql = qq (select gene_id from gene_names where gene_id in ("$namstr"));

    %found = map { uc $_->[0], 1 } @{ &Common::DB::query_array( $dbh, $sql ) };
    
    @missing = grep { not $found{ uc $_ } } @{ $names };

    return wantarray ? @missing : \@missing;
}

sub mc_query
{
    # Niels Larsen, July 2009 + October 2010.

    # Composes an SQL string from the given parameters, queries the MiRConnect tables
    # and returns a Common::Table structure with the result.

    my ( $dbh,
         $params,
        ) = @_;

    # Returns a Common::Table object.

    my ( $sql, $fields, $table, $method, $target, $corr, $tablen, $idsql,
         $orderby, $awords, $genids, $mirids, @gene_ids, @name_ids, $lc, @ids, $idstr,
         @gene_fields, @expr_fields, $array, $field, $hash, $index, $tuple, $row,
         $fldstr, $tab_name, @sql, @mir_ids, @tab_names );

    # Convenience variables,

    $method = $params->{"method"};
    $target = $params->{"target"};
    $corr = $params->{"correlation"};  
    $tablen = $params->{"maxtablen"};
    $mirids = $params->{"mirna_names"};

    # >>>>>>>>>>>>>>>>>>>>>>> SET MIR IDS AND TABLES <<<<<<<<<<<<<<<<<<<<<<<<<<

    @mir_ids = ();
    $tab_name = $method ."_method";

    if ( $params->{"mirna_single"} )
    {
        push @mir_ids, $params->{"mirna_single"};
    }

    if ( $params->{"mirna_family"} )
    {
        push @mir_ids, $params->{"mirna_family"};
    }

    if ( $params->{"mirna_names"} )
    {
        push @mir_ids, &Expr::DB::split_names( $params->{"mirna_names"} );
    }

    @mir_ids = &Common::Util::uniqify( \@mir_ids );
    
    # >>>>>>>>>>>>>>>>>>>>>>> SET GENE NAMES IF GIVEN <<<<<<<<<<<<<<<<<<<<<<<<<

    # If gene (mRNA) names are given, and/or gene annotation search words, then
    # query the gene_names table and get a string of gene ids. The gene_names 
    # table is small, so that is quick to do. The gene ids are then used to 
    # constrain the query below with,

    $table = &Common::Table::new();

    $genids = $params->{"genid_names"};
    $awords = $params->{"annot_filter"};

    @gene_ids = ();

    if ( $genids or $awords )
    {
        # If mRNA gene name constraint,

        if ( $genids )
        {
            $idstr = join qq (","), &Expr::DB::split_names( $genids );
            $idsql = qq (select gene_id from gene_names where gene_id in ("$idstr") );

            @gene_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $idsql ) };
        }

        # If annotation words constraint,

        if ( $awords )
        {
            $awords = &Expr::DB::format_words( $awords );
            $idsql = qq (select gene_id from gene_names where match (gene_name) against ('$awords' in boolean mode) );
            @name_ids = map { $_->[0] } @{ &Common::DB::query_array( $dbh, $idsql ) };
        }

        # Take intersection,

        if ( @gene_ids and @name_ids )
        {
            @gene_ids = List::Compare->new( \@gene_ids, \@name_ids )->get_intersection;
        }
        elsif ( @name_ids )
        {
            @gene_ids = @name_ids;
        }

        # Create gene id string, or return empty table if nothing matched,

        if ( not @gene_ids )
        {
            return $table;
        }
    }
    
    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> COMPOSE QUERY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create field string,
    
    foreach $field ( @{ $params->{"fields"} } )
    {
        if ( $field =~ /^gene_(chr|name)$/ ) {
            push @gene_fields, $field;
        } else {
            push @expr_fields, $field;
        }
    }

    $fields = join ",", @expr_fields;
    $mirids = join qq (","), @mir_ids;
    $genids = join qq (","), &Common::Util::uniqify( \@gene_ids );

    if ( @mir_ids )
    {
        $sql = qq (SELECT $fields FROM $tab_name WHERE mir_id IN \("$mirids"\));
        
        if ( @gene_ids )
        {
            $sql .= qq ( AND gene_id IN ("$genids"));
        }
    }
    elsif ( @gene_ids )
    {
        $sql = qq (SELECT $fields FROM $tab_name WHERE gene_id IN \("$genids"\));
    }
    else
    {
        $sql = qq (SELECT $fields FROM $tab_name);
    }
    
    # If targetscan constraint,

    if ( $target eq "cons_val" )
    {
        if ( @mir_ids or @gene_ids ) {
            $sql .= qq ( and ts_cons < "0" and cor_val < "0");
        } else {
            $sql .= qq ( where ts_cons < "0" and cor_val < "0");
        }            
    }

    # Ordering,

    if ( $target eq "ts_cons" and grep /ts_cons/, @expr_fields ) {
        $orderby = "ts_cons,cor_val";
    } else {
        $orderby = "cor_val";
    }

    $sql .= qq ( order by $orderby);

    if ( $corr eq "positive" ) {
        $sql .= qq ( desc);
    } else {
        $sql .= qq ( asc);
    }

    # Limit by length,

    if ( $tablen ) {
        $sql .= qq ( limit $tablen);
    }

    $array = &Common::DB::query_array( $dbh, $sql );

    $table->values( $array );
    $table->col_headers( \@expr_fields );

    # >>>>>>>>>>>>>>>>>>>>>> ADD GENE NAMES AND CHROMOSOMES <<<<<<<<<<<<<<<<<<<

    $idstr = join qq (","), @{ &Common::Util::uniqify( [ $table->get_col("gene_id") ] ) };
    $fldstr = join ",", @gene_fields;
    
    $sql = qq (select gene_id,$fldstr from gene_names where gene_id in ("$idstr"));

    $hash = { map { $_->[0], [ $_->[1], $_->[2] ] } @{ &Common::DB::query_array( $dbh, $sql ) } };

    $index = $table->col_index("gene_id");

    foreach $row ( @{ $table->values } )
    {
        if ( $tuple = $hash->{ $row->[$index] } ) {
            push @{ $row }, @{ $tuple };
        } else {
            push @{ $row }, "", "";
        }
    }

    $table->col_headers( [ @{ $table->col_headers }, @gene_fields ] );

    return $table;
}

sub mc_mirnas
{
    # Niels Larsen, July 2009.

    # Returns a sorted lists of mirna names, single or family. 

    my ( $dbh,
         $args,
        ) = @_;

    # Returns a list.

    $args = &Registry::Args::check(
        $args,
        {
            "S:2" => [ qw ( method type ) ],
        });
    
    my ( $type, $method, @opts, $elem, $id, $mbrs, $sql, $menu, @list );

    $method = $args->method;
    $type = $args->type;

    $sql = qq (select mir_id,imbrs from mir_names where method = "$method" and);

    if ( $type =~ /^sing/ )
    {
        $sql .= " imbrs = 0";
        $type = "single";
    }
    elsif ( $type =~ /^fam/ )
    {
        $sql .= " imbrs > 0";
        $type = "family";
    }
    else {
        &echo( qq (Wrong looking type -> "$type") );
    }

    @list = &Common::DB::query_array( $dbh, $sql );

    # return if not @list;

    foreach $elem ( @list )
    {
        ( $id, $mbrs ) = @{ $elem };

        if ( $id =~ /^(let|miR)-(\d+)(.*)/ ) {
            $elem = [ $id, $1, $2, $3 || "", $mbrs ];
        } else {
            &error( qq (Wrong looking id -> "$id") );
        }
    }

    @list = sort { $a->[1] cmp $b->[1] 
                || $a->[2] <=> $b->[2]
                || $b->[3] cmp $b->[3] } @list;

    if ( $type eq "single" ) 
    {
        @opts = map { { "name" => $_->[0], "title" => $_->[0] } } @list; 
    }
    else 
    {
        foreach $elem ( @list )
        {
            $id = $elem->[0];
            $mbrs = $elem->[-1];

            push @opts, { "name" => $id, "title" => qq ($id &nbsp;&nbsp;\($mbrs\)) };
        }
    }

    unshift @opts, { "name" => "", "title" => "" };

    return wantarray ? @opts : \@opts;
}

sub split_names
{
    my ( $names,
        ) = @_;

    my ( @names );
    
    @names = split /[\s+;+,+\"\()]+/, $names;
    
    return wantarray ? @names : \@names;
}

sub format_words
{
    my ( $words,
        ) = @_;

    my ( @words, $word, $quoted );
    
    foreach $word ( split " ", $words )
    {
        if ( $word =~ /"/ )
        {
            if ( $quoted ) {
                $quoted = 0;
            } else {
                $quoted = 1;
            }
        }
        elsif ( not $quoted and $word !~ /^[+-]/ )
        {
            $word = "+$word";
        }

        push @words, $word;
    }

    $words = join " ", @words;

    return $words;
}

1;

__END__
