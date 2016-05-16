package Expr::Import;     #  -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# This contains project specific routines that should be put in sub-modules.
# Routines starting with mc_ are specific to the mirconnect project.
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Storable qw ( dclone );

use DBI;
use IO::File;

use vars qw ( @ISA @EXPORT_OK );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &expand_args
                 &mc_create_hugo_aliases
                 &mc_create_hugo_approved
                 &mc_create_mirdict
                 &mc_create_ts_hash
                 &mc_has_targetscan
                 &mc_write_hugo_gene_names
                 &mc_write_tables
                );

use Common::Config;
use Common::Messages;

use Common::File;
use Common::Table;
use Common::Names;

use Registry::Args;

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub expand_args
{
    # Niels Larsen, March 2010.

    # Checks and expands the classify routine parameters and does one of 
    # two: 1) if there are errors, these are printed in void context and
    # pushed onto a given message list in non-void context, 2) if no 
    # errors, returns a hash of expanded arguments.

    my ( $args,      # Arguments
         $msgs,      # Outgoing messages
	) = @_;

    # Returns hash or nothing.

    my ( @msgs, $isuffix, %args, @sfiles, $file, $path, $name );

    @msgs = ();
    $isuffix = $args->isuffix;

    if ( $args->ifiles )
    {
	$args{"ifiles"} = &Common::File::check_files( $args->ifiles, "efr", \@msgs );

        foreach $file ( @{ $args{"ifiles"} } )
        {
            if ( $path = &Common::Names::strip_suffix( $file, $args->isuffix ) ) {
                push @sfiles, $path;
            } else {
                $name = &File::Basename::basename( $file );
                push @msgs, ["ERROR", qq ("$isuffix" is not suffix of "$name") ];
            }
        }
        
        if ( @sfiles ) {
            $args{"sfiles"} = &Common::File::check_files( \@sfiles, "efr", \@msgs );
        }
    }

    $args{"ofiles"} = &Registry::Args::out_files( $args->ifiles, $args->osuffix, $args->ofile, \@msgs );

    if ( defined $args->maxval ) {
	$args{"maxval"} = &Registry::Args::check_number( $args->maxval, 1, undef, \@msgs );
    }

    &Common::Messages::append_or_exit( \@msgs );

    return wantarray ? %args : \%args;
}

sub mc_create_hugo_aliases
{
    # Niels Larsen, October 2009.

    # Creates a "alias gene id" => "approved gene id" hash from a HUGO table 
    # download.

    my ( $file,    # File path
        ) = @_;
    
    # Returns a hash.

    my ( $cols, $table, $row, %hugo, $id, $id2, $i );
    
    #                 0               1             2
    $cols = [ "Approved Symbol", "Synonyms", "Previous Symbols" ];
    
    $table = &Common::Table::read_table( $file, { "format" => "tsv", "col_indices" => $cols } );

    # Create a hash with approved symbols as key and [ name, chromosome ] as value,

    foreach $row ( @{ $table->values } )
    {
        if ( $row->[0] !~ /~withdrawn$/ )
        {
            $id = $row->[0];

            foreach $i ( 1, 2 )
            {
                if ( $row->[$i] )
                {
                    foreach $id2 ( split /\s*,\s*/, $row->[$i] )
                    {
                        $hugo{ $id2 } = $id;
                    }
                }
            }
        }
    }

    return wantarray ? %hugo : \%hugo;
}

sub mc_create_hugo_approved
{
    # Niels Larsen, October 2010.

    # Creates a "approved gene id" => 1 hash from a HUGO table.
    
    my ( $file,    # File path
        ) = @_;
    
    # Returns a hash.

    my ( $cols, $table, $row, %hugo );
    
    #                 0
    $cols = [ "Approved Symbol" ];    
    $table = &Common::Table::read_table( $file, { "format" => "tsv", "col_indices" => $cols } );

    foreach $row ( @{ $table->values } )
    {
        if ( $row->[0] !~ /~withdrawn$/ )
        {
            $hugo{ $row->[0] } = 1;
        }
    }

    return wantarray ? %hugo : \%hugo;
}

sub mc_create_mirdict
{
    # Niels Larsen, October 2010.

    # Creates %mir_dict where key is the name of a single mirna or a family.
    # The values are lists of family members, or the empty list for singles.
    # Singles data are mandatory, family data optional.

    my ( $args,
         $msgs,
        ) = @_;

    # Returns hash.

    my ( @spcc_names, @dpcc_names, %fam_dict, %mir_dict, %sin_dict, $dir,
         $name, @diff, @tgt_files, $file, $fam_name, @msgs, $msg, $method,
         @names, %fam_members, @ct_fam_names, @ct_sin_names, @tgt_sin_names,
         @tgt_fam_names, @tgt_sinfam_names );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ CT FAMILIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Create a sorted list of ct_all family names, while checking that they 
    # dont differ between dPCC and sPCC,

    if ( -s ( $file = $args->src_dir ."/dPCC/dPCC_ct_all_family.csv" ) )
    {
        &echo( qq (   Reading dPCC_ct_all_family names ... ) );
        
        @dpcc_names = sort &Common::Table::read_col_headers(
            $file,
            {
                "format" => "csv", "row_header_index" => 0, "unquote" => 1,
            });

        &echo_done( (scalar @dpcc_names) ."\n" );
    }
    
    if ( -s ( $file = $args->src_dir ."/sPCC/sPCC_ct_all_family.csv" ) )
    {
        &echo( qq (   Reading sPCC_ct_all_family names ... ) );
        
        @spcc_names = sort &Common::Table::read_col_headers(
            $file,
            {
                "format" => "csv", "row_header_index" => 0, "unquote" => 1,
            });
        
        &echo_done( (scalar @spcc_names) ."\n" );
    }

    if ( @dpcc_names and @spcc_names
         and &Common::Util::lists_differ( \@spcc_names, \@dpcc_names ) )
    {
        if ( @diff = @{ &Common::Util::diff_lists( \@spcc_names, \@dpcc_names ) } ) {
            $msg = qq (sPCC ct_all family names not in dPCC: ). join ", ", @diff;
        } elsif ( @diff = @{ &Common::Util::diff_lists( \@dpcc_names, \@spcc_names ) } ) {
            $msg = qq (dPCC ct_all family names not in sPCC: ). join ", ", @diff;
        }
        
        push @msgs, ["ERROR", $msg ];
    }
    elsif ( @spcc_names )
    {
        @ct_fam_names = sort @spcc_names;
    }

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> READ CT SINGLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    # Create a sorted list of ct_all singles names, while checking that they 
    # dont differ between dPCC and sPCC,

    if ( -s ( $file = $args->src_dir ."/dPCC/dPCC_ct_all_single.csv" ) )
    {
        &echo( qq (   Reading dPCC_ct_all_single names ... ) );
    
        @dpcc_names = sort &Common::Table::read_col_headers(
            $file,
            { "format" => "csv", "row_header_index" => 0, "unquote" => 1 },
            );
        
        @dpcc_names = map { $_ =~ s/^hsa-//; $_ } @dpcc_names;
        
        &echo_done( (scalar @dpcc_names) ."\n" );
    }
    
    &echo( qq (   Reading sPCC_ct_all_single names ... ) );

    @spcc_names = sort &Common::Table::read_col_headers(
        $args->src_dir ."/sPCC/sPCC_ct_all_single.csv",
        { "format" => "csv", "row_header_index" => 0, "unquote" => 1 },
        );

    @spcc_names = map { $_ =~ s/^\s*hsa-//; $_ } @spcc_names;

    &echo_done( (scalar @spcc_names) ."\n" );

    if ( @spcc_names and @dpcc_names 
         and &Common::Util::lists_differ( \@spcc_names, \@dpcc_names ) )
    {
        if ( @diff = @{ &Common::Util::diff_lists( \@spcc_names, \@dpcc_names ) } ) {
            $msg = qq (sPCC ct_all single names not in dPCC: ). join ", ", @diff;
        } elsif ( @diff = @{ &Common::Util::diff_lists( \@dpcc_names, \@spcc_names ) } ) {
            $msg = qq (dPCC ct_all single names not in sPCC: ). join ", ", @diff;
        }
            
        push @msgs, ["ERROR", $msg ];
    }

    @ct_sin_names = sort @spcc_names;

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> TARGET FAMILIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # Create a family member hash from the target files in the family directory.
    # Keys are family names, values are lists of member singles,

    if ( -d ( $dir = $args->src_dir ."/sPCC/sPCC_Targets_miRNA_family" ) )
    {
        &echo( qq (   Reading sPCC_Targets_miRNA_family/*.csv ... ) );

        @tgt_files = &Common::File::list_files( $dir, '\.csv$' );

        foreach $file ( @tgt_files )
        {
            @names = &Common::Table::read_col_headers(
                $file->{"path"},
                { "format" => "csv", "row_header_index" => 0, "unquote" => 1 },
                );

            if ( @names = grep { $_ =~ /^\s*result-/ } @names )
            {
                $fam_name = pop @names;
                $fam_name =~ s/\s*result-bcf-//;

                @names = map { $_ =~ s/\s*result-bcf-(hsa-)?//; $_ } @names;
            
                if ( not @names ) {
                    push @msgs, ["ERROR", qq (No $method family members found for $file->{"name"}) ];
                }
                        
                if ( defined $fam_name )
                {
                    $fam_members{ $fam_name } = &Storable::dclone( \@names );
                }
                else {
                    push @msgs, ["ERROR", qq (Wrong looking sPCC family name in $file->{"name"}) ];
                }
            }
            else {
                push @msgs, ["ERROR", qq (No "result-" names in sPCC in family file $file->{"name"}) ];
            }
        }

        @tgt_fam_names = sort keys %fam_members;

        &echo_done( (scalar @tgt_fam_names) ."\n" );

        &append_or_exit( \@msgs, $msgs );
    }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>> TARGET SINGLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    &echo( qq (   Reading sPCC_Targets_miRNA_single/*.csv ... ) );
    
    @tgt_files = &Common::File::list_files( $args->src_dir ."/sPCC/sPCC_Targets_miRNA_single", '\.csv$' );
    
    foreach $file ( @tgt_files )
    {
        @names = &Common::Table::read_col_headers(
            $file->{"path"},
            { "format" => "csv", "row_header_index" => 0, "unquote" => 1 },
            );
        
        if ( @names = grep { $_ =~ /^\s*result-bcf/ } @names )
        {
            @names = map { $_ =~ s/^\s*result-bcf-(hsa-)?//; $_ } @names;

            push @tgt_sin_names, @names;
        }
        else {
            push @msgs, ["ERROR", qq (Wrong sPCC target single name -> "$names[-1]") ];
        }
    }

    @tgt_sin_names = sort @tgt_sin_names;
    
    &echo_done( (scalar @tgt_sin_names) ."\n" );

    &append_or_exit( \@msgs, $msgs );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>> CT / TARGET NAMES <<<<<<<<<<<<<<<<<<<<<<<<<<<
    
    # There should be no family in the family directory not in the ct_family 
    # file, and vice versa,

    if ( @ct_fam_names and @tgt_fam_names )
    {
        &echo( qq (   Do ct and target families match ... ) );

        if ( &Common::Util::lists_differ( \@ct_fam_names, \@tgt_fam_names ) )
        {
            if ( @diff = @{ &Common::Util::diff_lists( \@ct_fam_names, \@tgt_fam_names ) } ) {
                $msg = qq (ct_all family names not in target files: ). join ", ", @diff;
            } elsif ( @diff = @{ &Common::Util::diff_lists( \@tgt_fam_names, \@ct_fam_names ) } ) {
                $msg = qq (target file (sPCC) family names not in ct_all: ). join ", ", @diff;
            } else {
                &error( qq (Programming error, list comparison problem) );
            }
            
            &echo_yellow( "NO\n" );
            &echo_yellow( "      $msg\n" );
        }
        else {
            &echo_done("yes\n");
        }
    }

#     # Some ...

#     &echo( qq (   Do ct and target singles match ... ) );
    
#     @tgt_sinfam_names = sort ( @tgt_sin_names, map { @{ $fam_members{ $_ } } } keys %fam_members );

#     &dump( scalar @tgt_sinfam_names );
#     &dump( scalar @tgt_sin_names );

# #    for ( my $i = 0; $i <= $#tgt_sinfam_names; $i++ )
# #    {
# #        &dump( "$tgt_sinfam_names[$i], $tgt_sin_names[$i]" );
# #    }

#     if ( &Common::Util::lists_differ( \@ct_sin_names, \@tgt_sinfam_names ) )
#     {
#         if ( @diff = @{ &Common::Util::diff_lists( \@ct_sin_names, \@tgt_sinfam_names ) } ) {
#             $msg = qq (ct_all single names not in target files: ). join ", ", @diff;
#         } elsif ( @diff = @{ &Common::Util::diff_lists( \@tgt_sinfam_names, \@ct_sin_names ) } ) {
#             $msg = qq (target file (sPCC) single names not in ct_all: ). join ", ", @diff;
#         } else {
#             &error( qq (Programming error, list comparison problem) );
#         }
            
#         &echo_yellow( "NO\n" );
#         &echo_yellow( "      $msg\n" );
#     }
#     else {
#         &echo_done("yes\n");
#     }

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> COMBINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    &echo( qq (   Creating mir family dictionary ... ) );

    %mir_dict = %fam_members if %fam_members;

    foreach $name ( @ct_sin_names )
    {
        if ( exists $mir_dict{ $name } )
        {
            &error( qq (Single name exists as family name -> "$name") );
        } 
        else {
            $mir_dict{ $name } = [];
        }
    }

    &echo_done( "done\n" );

    return wantarray ? %mir_dict : \%mir_dict;
}

sub mc_create_ts_hash
{
    # Niels Larsen, June 2009.

    # Creates a hash of hashes where gene id and mir id are keys, and targetscan 
    # scores are values. If there are no targetscan scores, the hash will be empty.

    my ( $dir,
         $method,
         $dict,
         $params,
        ) = @_;

    # Returns hash.
    
    my ( @tgt_dirs, %tgt_tcons, $count, $count2, $tgt_dir, $tgt_tab, $gene_ids,
         $col_vals, @msgs, @mir_ids, $mir_name, $mir_id, $i, $tcons, $gene_id,
         $tgt_file, $outstr );

    @tgt_dirs = &Common::File::list_directories( $dir, '^[A-Za-z]' );
    
    @tgt_dirs = (
        ( grep { $_->{"name"} =~ /single$/i } @tgt_dirs ), 
        ( grep { $_->{"name"} =~ /family$/i } @tgt_dirs ), 
        );
    
    %tgt_tcons = ();

    foreach $tgt_dir ( @tgt_dirs )
    {
        &echo( qq (   Reading $tgt_dir->{"name"}/*.csv ... ) );
        
        $count = 0;
        $count2 = 0;
        
        foreach $tgt_file ( &Common::File::list_files( $tgt_dir->{"path"}, '\.csv$' ) )
        {
            $tgt_tab = &Common::Table::read_table( $tgt_file->{"path"}, $params );

            next if not $tgt_tab->has_col( "family_ts_cons" );

            $col_vals = $tgt_tab->get_col("family_ts_cons");
            $gene_ids = $tgt_tab->row_headers;
            
            if ( $method eq "sPCC" )
            {
                @mir_ids = grep /^result-/, @{ $tgt_tab->col_headers };
                @mir_ids = map { $_ =~ s/.*(miR-|let-)/$1/i; $_ } @mir_ids;
            } 
            else 
            {
                $mir_name = $tgt_file->{"name"};
                $mir_name =~ s|_|/|g;
                $mir_name =~ s/\.csv$//;
                $mir_name =~ s/star$/\*/;
                
                if ( exists $dict->{ $mir_name } )
                {
                    @mir_ids = $mir_name;
                    push @mir_ids, @{ $dict->{ $mir_name } };
                }
                else {
                    @mir_ids = ();
#                    &echo_yellow( qq (   ($method) Not in dict -> "$mir_name") );
                }
            }

            foreach $mir_id ( @mir_ids )
            {
                for ( $i = 0; $i <= $#{ $gene_ids }; $i++ )
                {
                    $tcons = $col_vals->[$i] // "";
                    
                    if ( $tcons ne "" ) 
                    {
                        $gene_id = $gene_ids->[$i];
                        
                        if ( exists $tgt_tcons{ $gene_id }{ $mir_id } )
                        {
                            if ( $tcons != $tgt_tcons{ $gene_id }{ $mir_id } ) {
                                $count2 += 1;
                            }
                        }
                        else {
                            $tgt_tcons{ $gene_id }{ $mir_id } = $tcons;
                            $count += 1;
                        }
                    }
                }
            }
        }
        
        $outstr = &echo_done( "$count value[s]" );
        
        if ( $count2 > 0 ) {
            $outstr .= ", ";
            $outstr .= &echo_yellow( "$count2 ignored" ); 
        }
        
        &echo( "$outstr\n", 0 );
    }
    
    return wantarray ? %tgt_tcons : \%tgt_tcons;
}

sub mc_has_targetscan
{
    # Niels Larsen, April 2011.

    # 
}
    
sub mc_write_hugo_gene_names
{
    # Niels Larsen, October 2010.

    # Writes a two-column table that translates from ( approved, previous or alias) 
    # id to the current approved id. 

    my ( $ifile,    # Input HUGO file path
         $otable,   # Output table
        ) = @_;
    
    # Returns a hash.

    my ( $ofh, $must_close, $cols, $table, $count, $row, $id, $name, $i );

    if ( ref $otable ) {
        $ofh = $otable;
    } else {
        $ofh = &Common::File::get_write_handle( $otable );
        $must_close = 1;
    }

    # Read the whole table into memory first, its not so big,

    #                 0                1               2
    $cols = [ "Approved Symbol", "Chromosome", "Approved Name" ];
    $table = &Common::Table::read_table( $ifile, { "format" => "tsv", "col_indices" => $cols } );

    $count = 0;

    foreach $row ( @{ $table->values } )
    {
        $id = $row->[0];

        next if $id =~ /^(.+)~withdrawn$/;
        
        $ofh->print( "$id\t$row->[1]\t$row->[2]\n" );
        $count += 1;
    }
    
    if ( $must_close ) {
        &Common::File::close_handle( $ofh );
    }
    
    return $count;
}

sub mc_write_tables
{
    # Niels Larsen, June 2009.

    # Parses data from miRConnect and writes database tables. His format will 
    # change. See Registry::Data::Schemas::expr_mirconnect for the database 
    # table format. 

    my ( $args,
         $msgs,
        ) = @_;

    # Returns nothing.
    
    my ( @met_dirs, $met_dir, $src_file, $tab_file, $method, $ofh, %mir_dict, 
         $gene_id, $i, $j, $mir_id, $count, $value, $hugo_aliases, $gene_name, 
         $id, $ct_tab, $ct_file, $tab_params, @msgs, $col_vals, $gene_ids, 
         $hugo_approved, @methods, $lc_method, @mbrs, $tgt_tcons, $db_name,
         $tcons, $write_code, $tab_name );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ARGUMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $args = &Registry::Args::check(
        $args,
        { 
            "S:1" => [ qw ( source src_dir tab_dir db_name ) ],
        });
    
    $db_name = $args->db_name;

    # Table reader arguments,

    $tab_params = {
        "format" => "csv",
        "has_col_headers" => 1,       # First row is column titles
        "row_header_index" => 0,      # First column is gene names
        "unquote_row_headers" => 1,   # Remove quotes from row headers
        "unquote_col_headers" => 1,   # Remove quotes from column headers
        "unquote_values" => 1,        # Remove quotes from values
    };

    # >>>>>>>>>>>>>>>>>>>>>>>> READ/WRITE HUGO GENES <<<<<<<<<<<<<<<<<<<<<<<<<<

    $src_file = $args->src_dir ."/hugo_genes.tab";
    
    &echo( qq (   Writing HUGO gene names table ... ) );

    $tab_file = $args->tab_dir ."/gene_names";
    
    &Common::File::delete_file_if_exists( $tab_file );
    $ofh = &Common::File::get_write_handle( $tab_file );

    $count = &Expr::Import::mc_write_hugo_gene_names( $src_file, $ofh );

    &echo_done( "$count row[s]\n" );

    &echo( qq (   Loading HUGO approved symbols ... ) );

    $hugo_approved = &Expr::Import::mc_create_hugo_approved( $src_file );

    $count = scalar ( keys %{ $hugo_approved } );
    &echo_done( "$count symbol[s]\n" );

    &echo( qq (   Loading HUGO alias symbols ... ) );

    $hugo_aliases = &Expr::Import::mc_create_hugo_aliases( $src_file );

    $count = scalar ( keys %{ $hugo_aliases } );
    &echo_done( "$count symbol[s]\n" );

    # >>>>>>>>>>>>>>>>>>>>>>>>> CREATE MIR NAMES HASH <<<<<<<<<<<<<<<<<<<<<<<<<

    # Create %mir_dict where key is the name of a single mirna or a family, 
    # and the values are lists of family members - where single ones have 
    # the empty list,

    %mir_dict = &Expr::Import::mc_create_mirdict( $args );

    # >>>>>>>>>>>>>>>>>>>>>>>>> WRITE MIR NAMES TABLE <<<<<<<<<<<<<<<<<<<<<<<<<

    @met_dirs = &Common::File::list_directories( $args->src_dir, '^[A-Za-z]' );
    @methods = map { $_->{"name"} } @met_dirs;

    $tab_file = $args->tab_dir ."/mir_names";
    $tab_name = &Common::File::basename( $tab_file );
    
    &Common::File::delete_file_if_exists( $tab_file );
    $ofh = &Common::File::get_write_handle( $tab_file );

    foreach $method ( @methods )
    {
        &echo( qq (   Writing miRNA ids ($method) ... ) );

        $count = 0;
        $lc_method = lc $method;

        foreach $id ( keys %mir_dict )
        {
            @mbrs = @{ $mir_dict{ $id } };

            $ofh->print( "$lc_method\t$id\t". (scalar @mbrs) ."\t". (join ",", @mbrs) ."\n" );
            $count += 1;
        }

        &echo_done( "$count row[s]\n" );
    }

    &Common::File::close_handle( $ofh );

    # >>>>>>>>>>>>>>>>>>>>>>>>>> WRITING ROUTINE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $write_code = q (
          for ( $i = 0; $i <= $#{ $gene_ids }; $i++ )
          {
              $gene_id = $gene_ids->[$i];
                    
              # This says "if there is a value or a targetscan value, then 
              # write a table line",

              if ( ( $value = $col_vals->[$i] and 
                     $value ne "NA" and 
                     abs $value >= 0.01 )
                     or 
                   ( exists $tgt_tcons->{ $gene_id } and 
                     $tcons = $tgt_tcons->{ $gene_id }->{ $mir_id } and
                     $tcons ne "NA" and
                     abs $tcons >= 0.01 ) )
              {
                   # But first unalias the gene name if it is not among the 
                   # approved ones,
                        
                   if ( not exists $hugo_approved->{ $gene_id } 
                        and exists $hugo_aliases->{ $gene_id } )
                   {
                       $gene_id = $hugo_aliases->{ $gene_id };
                   }

                   if ( $tcons ) {
                      $tcons = sprintf "%.2f", $tcons;
                   } else {
                      $tcons = "";
                   }

                   if ( $value ) {
                      $value = sprintf "%.2f", $value;
                   } else {
                      $value = "";
                   }

                   $ofh->print( "$mir_id\t$gene_id\t$tcons\t$value\n" );
                   $count += 1;
               }
           }
);

    # >>>>>>>>>>>>>>>>>>>>>>>>>> READ/WRITE VALUES  <<<<<<<<<<<<<<<<<<<<<<<<<<<

    foreach $met_dir ( @met_dirs )
    {
        $method = $met_dir->{"name"};
        $lc_method = lc $method;

        # >>>>>>>>>>>>>>>>>>>>>>>>>> PREDICTIONS HASH <<<<<<<<<<<<<<<<<<<<<<<<<

        # Targetscan values are averaged across members of families and values
        # for those members (single miRNAs) must be extracted from the family 
        # files, they are not listed separately (whereas the correlation values
        # are in the ct_all files). 

        $tgt_tcons = &Expr::Import::mc_create_ts_hash( $met_dir->{"path"}, $method, \%mir_dict, $tab_params );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> OUTPUT TABLE <<<<<<<<<<<<<<<<<<<<<<<<<<<

        $tab_file = $args->tab_dir ."/". (lc $method) ."_method";
        $tab_name = &Common::File::basename( $tab_file );
        
        &Common::File::delete_file_if_exists( $tab_file );
        $ofh = &Common::File::get_write_handle( $tab_file );

        # >>>>>>>>>>>>>>>>>>>>>>>>>>>> FAMILIES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Read correlations,

        if ( -s ( $ct_file = "$met_dir->{'path'}/$method". "_ct_all_family.csv" ) )
        {
            &echo( "   Reading $method". "_ct_all_family.csv ... " );

            $ct_tab = &Common::Table::read_table( $ct_file, $tab_params );
        
            $i = $ct_tab->col_count;
            $j = $ct_tab->row_count;
            &echo_done( qq ($i famil[y|ies], $j gene[s]\n) );
            
            # Write table,
            
            &echo( qq (   Writing $tab_name family table ... ) );
            
            $gene_ids = $ct_tab->row_headers;
            
            $count = 0;
            
            foreach $mir_id ( keys %mir_dict )
            {
                if ( @{ $mir_dict{ $mir_id } } )
                {
                    if ( $ct_tab->has_col( $mir_id ) and 
                         defined ( $col_vals = $ct_tab->get_col( $mir_id ) ) )
                    {
                        eval $write_code;
                        
                        &error( $@ ) if $@;
                    }
                }
            }
        
            &echo_done( "$count row[s] written\n" );
        }
        
        # >>>>>>>>>>>>>>>>>>>>>>>>>>> SINGLES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

        # Read correlations,

        &echo( "   Reading $method". "_ct_all_single.csv ... " );

        $ct_file = "$met_dir->{'path'}/$method". "_ct_all_single.csv";
        $ct_tab = &Common::Table::read_table( $ct_file, $tab_params );

        $ct_tab->col_headers( [ map { $_ =~ s/^hsa-//; $_ } @{ $ct_tab->col_headers } ] );

        $i = $ct_tab->col_count;
        $j = $ct_tab->row_count;

        &echo_done( qq ($i single[s], $j gene[s]\n) );

        # Write table,

        &echo( qq (   Writing $tab_name single table ... ) );

        $gene_ids = $ct_tab->row_headers;

        $count = 0;

        foreach $mir_id ( keys %mir_dict )
        {
            if ( not @{ $mir_dict{ $mir_id } } )
            {
                if ( $ct_tab->has_col( $mir_id ) and 
                     defined ( $col_vals = $ct_tab->get_col( $mir_id ) ) )
                {
                    eval $write_code;

                    &error( $@ ) if $@;
                }
            }
        }
        
        &echo_done( "$count row[s] written\n" );
        
        &Common::File::close_handle( $ofh );        
    }

    return;
}

1;

__END__

# sub mc_write_hugo_gene_ids
# {
#     # Niels Larsen, October 2010.

#     # Writes a two-column table that translates from ( approved, withdrawn, previous
#     # or alias) id to the current approved id. 

#     my ( $ifile,    # Input HUGO file path
#          $otable,   # Output table
#         ) = @_;
    
#     # Returns a hash.

#     my ( $must_close, $ofh, $cols, $table, $count, $row, $id, $id_other, $idstr, $name, $i );

#     if ( ref $otable ) {
#         $ofh = $otable;
#     } else {
#         $ofh = &Common::File::get_write_handle( $otable );
#         $must_close = 1;
#     }

#     # Read the whole table into memory first, its not so big,

#     #                 0                  1               2               3
#     $cols = [ "Approved Symbol", "Approved Name", "Previous Symbols", "Aliases" ];
    
#     $table = &Common::Table::read_table( $ifile, { "format" => "tsv", "cols" => $cols } );

#     $count = 0;

#     foreach $row ( @{ $table->values } )
#     {
#         $id = $row->[0];

#         if ( $id =~ /^(.+)~withdrawn$/ )
#         {
#             $id_other = $1;
#             $name = $row->[1];

#             if ( $name =~ /^(symbol|entry) withdrawn, see (.+)/ )
#             {
#                 $idstr = $2; 
#                 $idstr =~ s/ and /, /g;

#                 foreach $id ( split /\*,\s*/, $idstr )
#                 {
#                     $ofh->print( "$id\t$id_other\n" );
#                     $count += 1;
#                 }
#             }
#         }
#         else
#         {
#             foreach $i ( 3 )
#             {
#                 if ( $row->[$i] )
#                 {
#                     foreach $id_other ( split /\s*,\s*/, $row->[$i] )
#                     {
#                         $ofh->print( "$id\t$id_other\n" );
#                         $count += 1;
#                     }
#                 }
#             }

#             $ofh->print( "$id\t$id\n" );
#             $count += 1;
#         }
#     }

#     if ( $must_close ) {
#         &Common::File::close_handle( $ofh );
#     }
    
#     return $count;
# }

#         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHECKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#         # All single ids from the target files must be in the ct single file (vice versa 
#         # need not be, because thats the way the data are),

#         @mir_ids = @{ $ct_sin_tab->col_headers };
#         %mir_ids = map { $_ =~ s/.*(miR-|let-)/$1/i; $_, 1 } @mir_ids;

#         foreach $mir_id ( keys %mir_dict )
#         {
#             if ( not @{ $mir_dict{ $mir_id } } and not exists $mir_ids{ $mir_id } ) {
#                 push @msgs, ["ERROR", "($method) Single $mir_id from target files is not in ct single"];
#             }
#         }

#         # The family ids from target files must match those in the family ct files 
#         # exactly, and vice versa,
        
#         @mir_ids = @{ $ct_fam_tab->col_headers };
#         %mir_ids = map { $_ =~ s/.*(miR-|let-)/$1/i; $_, 1 } @mir_ids;
        
#         foreach $mir_id ( keys %mir_dict )
#         {
#             if ( @{ $mir_dict{ $mir_id } } and not exists $mir_ids{ $mir_id } ) {
#                 push @msgs, ["ERROR", "($method) Family $mir_id from target files is not in ct file"];
#             }
#         }

#         foreach $mir_id ( keys %mir_ids )
#         {
#             if ( not exists $mir_dict{ $mir_id } ) {
#                 push @msgs, ["ERROR", "($method) Family $mir_id from ct file is not in target files"];
#             }
#         }
                
# # >>>>>>>>>>>>>>>>>>>>>>>>>>> CONSTANTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# # Indices into the classification table,

# use constant TAB_QID => 0;
# use constant TAB_QLEN => 1;
# use constant TAB_SDB => 2;
# use constant TAB_SID => 3;
# use constant TAB_SIM => 4;
# use constant TAB_HITS => 5;
# use constant TAB_COM => 6;

# # >>>>>>>>>>>>>>>>>>>>>>>>>>>> ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# sub classify_tables
# {
#     my ( $class,
#          $args,
#         ) = @_;

#     my ( $defs, %args, $silent, $silent2, $i, $in_files, $out_files, $indent, %params,
#          $name, $seq_files );

#     $defs = {
#         "ifiles" => [],
#         "isuffix" => undef,
#         "osuffix" => undef,
#         "ofile" => "",
# 	"maxval" => undef,
# 	"silent" => 0,
# 	"verbose" => 0,
#     };

#     $args = &Registry::Args::create( $args, $defs );
#     %args = &Expr::Import::expand_args( $args );

#     &dump( \%args );
#     exit;

#     $in_files = $args{"ifiles"};
#     $seq_files = $args{"sfiles"};
#     $out_files = $args{"ofiles"};

#     $silent = $args->silent;

#     if ( $silent ) {
#         $silent2 = $silent;
#     } else {
# 	$silent2 = $args->verbose ? 0 : 1;
#     }

#     $indent = $args->verbose ? 3 : 0;
    
#     %params = (
#         "maxval" => $args{"maxval"},
#         "silent" => $silent2,
#         "verbose" => $args->verbose,
#         "indent" => $indent,
#         );

#     # Handle multiple files, single file or stream.

#     $silent or &echo_bold( qq (\nCreate profiles:\n) );

#     if ( $in_files and scalar @{ $in_files } > 1 )
#     {
#         # Multiple files,

#         for ( $i = 0; $i <= $#{ $in_files }; $i++ )
#         {
#             $name = &File::Basename::basename( $in_files->[$i] );
#             $silent or &echo( "   Processing $name ... " );

#             no strict "refs";

#             &Expr::Import::_classify_table(
#                 {
#                     "ifile" => $in_files->[$i],
#                     "sfile" => $seq_files->[$i],
#                     "ofile" => $out_files->[$i],
#                     %params,
#                 });

#             $silent or &echo_green( "done\n", $indent );
#         }
#     }
#     else
#     {
#         # Single file or stream,

#         if ( $in_files and @{ $in_files } ) {
#             $name = &File::Basename::basename( $in_files->[0] );
#         } else {
#             $name = "STDIN";
#         }

#         $silent or &echo( "   Processing $name ... " );
        
#         no strict "refs";
        
#         &Expr::Import::_classify_table(
#             {
#                 "ifile" => $in_files->[0],
#                 "sfile" => $seq_files->[0],
#                 "ofile" => $args->ofile,
#                 %params,
#             });
        
#         $silent or &echo_green( "done\n", $indent );
#     }        

#     $silent or &echo_bold("Done\n\n");

#     return;
# }

# sub _classify_table
# {
#     # Niels Larsen, March 2010.

#     # Converts a single classification output to an expression profile. 

#     my ( $args,
#         ) = @_;

#     # Returns nothing.

#     my ( $silent, $indent, $dbm_file, $dbm, $fh, $seq, $count, $line, @line,
#          %expr, $db, $sid, $tuples, $best_sim, $qid, $len, $pct, $matches, 
#          $p_best, $p, $exp, @expr, $tuple, $max, $scale, $name, @unknowns,
#          $row, $seq_count );

#     local $Common::Messages::indent_plain;

#     $args = &Registry::Args::create( $args );

#     $silent = $args->silent;
#     $indent = $args->indent;

#     if ( not $silent ) {
# 	$Common::Messages::indent_plain = 6;
# 	&echo("\n");
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>> SAVE CLUSTER COUNTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Put id => count into dbm storage, used below,

#     $silent or &echo("Create id / value hash ... " );

#     $dbm_file = Registry::Paths->new_temp_path( "expr_create.dbm" );

#     $dbm = &Common::DBM::open( $dbm_file, "BDB" );
#     $fh = &Common::File::get_read_handle( $args->sfile );

#     $count = 0;

#     while ( $seq = bless &Seq::IO::read_seq_fasta( $fh ), "Seq::Common" )
#     {
#         &Common::DBM::put( $dbm, $seq->id, $seq->info );
#         $count += 1;
#     }

#     $fh->close;

#     $count = &Common::Util::commify_number( $count );
#     $silent or &echo_green("$count ids\n");

#     # >>>>>>>>>>>>>>>>>>>>>>>>> READ TABLE INTO HASH <<<<<<<<<<<<<<<<<<<<<<<<<<

#     # Create a hash of { database }{ id }->[ query id, query len, sim pct ],
#     # so below we can sum up the expression values that go with each query id,

#     $silent or &echo("Reading table data ... " );

#     $fh = &Common::File::get_read_handle( $args->ifile );
#     $count = 0;

#     while ( defined ( $line = <$fh> ) )
#     {
#         chomp $line;
#         @line = split "\t", $line;

#         if ( $line[TAB_SID] )
#         {
#             push @{ $expr{ $line[TAB_SDB] }{ $line[TAB_SID] } }, 
#                          [ $line[TAB_QID], $line[TAB_QLEN], $line[TAB_SIM] ];
#         }
#         elsif ( $line[TAB_SDB] ) {
#             push @unknowns, [ $line[TAB_QID], $line[TAB_SDB], "", $line[TAB_SIM], $line[TAB_SIM], $line[TAB_COM] ];
#         } else {
#             push @unknowns, [ $line[TAB_QID], "", "", "", "", "" ];
#         }            
        
#         $count += 1;
#     }

#     $fh->close;

#     $count = &Common::Util::commify_number( $count );
#     $silent or &echo_green("$count rows\n");

#     # >>>>>>>>>>>>>>>>>>>>>>> COMPUTE MATCHING VALUES <<<<<<<<<<<<<<<<<<<<<<<<<

#     $silent or &echo("Compute matching expressions ... " );
#     $count = 0;
    
#     foreach $db ( keys %expr )
#     {
#         foreach $sid ( keys %{ $expr{ $db } } )
#         {
#             # Sort by similarity, highest first,

#             $tuples = $expr{ $db }{ $sid };
#             @{ $tuples } = sort { $b->[2] <=> $a->[2] } @{ $tuples };

#             $seq_count = scalar @{ $tuples };

#             # Calculate probability of best match: if m matches of n, calculate
#             # permutation value. The ratio of this and those of lower similarities
#             # is used to "distribute" scores,

#             ( $qid, $len, $pct ) = @{ shift @{ $tuples } };
            
#             $matches = int ( $len * $pct / 100 );
#             $p_best = &Common::Util::p_bin_selection( $matches, $len, 0.25 );

#             # Get expression value of best match from file,

#             $exp = &Common::DBM::get( $dbm, $qid );

#             # Add the contributions from other sequences with the same classification,

#             foreach $tuple ( @{ $tuples } )
#             {
#                 ( $qid, $len, $pct ) = @{ $tuple };
#                 $matches = int ( $len * $pct / 100 );
#                 $p = &Common::Util::p_bin_selection( $matches, $len, 0.25 );

#                 $exp += &Common::DBM::get( $dbm, $qid ) * $p_best / $p;
#             }
            
#             push @expr, [ $db, $sid, int $exp, $seq_count, "" ];   # Last is comment
#             $count += 1;
#         }
#     }

#     $count = &Common::Util::commify_number( $count );
#     $silent or &echo_green("$count types\n");

#     # >>>>>>>>>>>>>>>>>>>>>>>> COMPUTE UNKNOWN VALUES <<<<<<<<<<<<<<<<<<<<<<<<<

#     $silent or &echo("Add expression of unknowns ... " );

#     foreach $row ( @unknowns )
#     {
#         $exp = int &Common::DBM::get( $dbm, $row->[0] );

#         if ( $row->[1] ) {
#             push @expr, [ $row->[1], "", $exp, 1, $row->[5] ];
#         } else {
#             push @expr, [ "", "", $exp, 1, "Seq id: $row->[0]" ];
#         }
#     }

#     $count = &Common::Util::commify_number( scalar @unknowns );
#     $silent or &echo_green("$count types\n");

#     &Common::DBM::close( $dbm );

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> NORMALIZE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    
#     if ( defined $args->maxval )
#     {
#         $silent or &echo("Scaling to max ". $args->maxval ." ... " );

#         $max = &List::Util::max( map { $_->[2] } @expr );
#         $scale = $args->maxval / $max;

#         @expr = map { $_->[2] = int ($_->[2] *= $scale); $_ } @expr;

#         $silent or &echo_green("done\n");
#     }

#     # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> WRITE OUTPUT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<

#     $name = &Common::File::basename( $args->ofile );
#     $silent or &echo("Writing $name ... " );
    
#     @expr = sort { $b->[2] <=> $a->[2] } @expr;

#     &Common::Tables::write_tab_table( $args->ofile, \@expr );

#     $silent or &echo_green("done\n");

#     # Delete temporary files,

#     $silent or &echo("Deleting temporary files ... " );

#     &Common::File::delete_file( $dbm_file );

#     $silent or &echo_green("done\n");

#     return;
# }

# sub load_all
# {
#     # Niels Larsen, April 2004.

#     # Loads a set of expression data files into a database. First the 
#     # database tables are initialized, if they have not been. Then each 
#     # release file is parsed and saved into database-ready temporary 
#     # files which are then loaded - unless the "readonly" flag is given. 
    
#     my ( $wants,           # Wanted file types
#          $cl_readonly,     # Prints messages but does not load
#          $cl_force,        # Reloads files even though database is newer
#          $cl_keep,         # Avoids deleting database ready tables
#          ) = @_;

#     # Returns nothing.

#     if ( $wants->{"all"} )
#     {
#         $wants->{"test"} = 1;
#     }

#     if ( $wants->{"test"} ) 
#     {
#         &Expr::Import::load_test( $cl_readonly, $cl_force, $cl_keep );
#     }

#     return;
# }

# sub load_test
# {
#     # Niels Larsen, April 2004.

#     # Loads test files into a database.

#     my ( $cl_readonly,
#          $cl_force,
#          $cl_keep,
#          ) = @_;

#     # Returns nothing.

#     my ( $src_dir, $tab_dir, @files, $tab_time, $src_time, $file, $data,
#          $dbh, @table, $table, $schema, $defs, $ont_ids, $id, $count,
#          $maps, $map, $int_nodes, $parent, $gen_dir, $exp_id, $values );

#     # >>>>>>>>>>>>>>>>> CHECKS AND INITIALIZATIONS <<<<<<<<<<<<<<<<<<<<<<

#     $src_dir = "$Common::Config::dat_dir/Expression";
#     $tab_dir = "$Common::Config::dat_dir/Expression/Database_tables";

#     $schema = &Expr::Import::schema();

#     if ( not -d $src_dir ) {
#         &error( "No Expression data source directory found", "MISSING DIRECTORY" );
#     } elsif ( not &Common::Storage::list_files( $src_dir ) ) {
#         &error( "No Expression source files found", "MISSING SOURCE FILES" );
#     }
    
#     &Common::File::create_dir_if_not_exists( $tab_dir );

#     if ( not $cl_readonly )
#     {
#         if ( not &Common::DB::database_exists() )
#         {
#             &echo( qq (   Creating new $Common::Config::sys_name database ... ) );
            
#             &Common::DB::create_database();
#             sleep 1;
            
#             &echo_green( "done\n" );
#         }

#         $dbh = &Common::DB::connect();
#     }

#     # >>>>>>>>>>>>>>>>>> CHECK FILE MODIFICATION TIMES <<<<<<<<<<<<<<<<<<<

#     &echo( qq (   Are there new Expression downloads ... ) );

#     $tab_time = &Common::File::get_newest_file_epoch( $tab_dir );
#     $src_time = &Common::File::get_newest_file_epoch( $src_dir, "test" );
    
#     if ( $tab_time < $src_time )
#     {
#         &echo_green( "yes\n" );
#     } 
#     else
#     {
#         &echo_green( "no\n" );
#         return unless $cl_force;
#     }
    
#     # >>>>>>>>>>>>>>>>> PARSE AND CREATE DATABASE TABLES <<<<<<<<<<<<<<<<<

#     # -------------- delete old database tables,
        
#     if ( not $cl_readonly ) 
#     {
#         &echo( qq (   Are there old Expression .tab files ... ) );
        
#         if ( @files = &Common::Storage::list_files( $tab_dir ) )
#         {
#             $count = 0;
            
#             foreach $file ( @files )
#             {
#                 &Common::File::delete_file( $file->{"path"} );
#                 $count++;
#             }
            
#             &echo_green( "$count deleted\n" );
#         }
#         else {
#             &echo_green( "no\n" );
#         }
#     }
        
#     # -------------- parse test,
    
#     if ( $cl_readonly ) {
#         &echo( qq (   Parsing test file ... ) );            
#     } else {
#         &echo( qq (   Creating test .tab file ... ) );
#     }
    
#     $data = &Expr::Import::parse_test( "$src_dir/test.txt" );

#     if ( not $cl_readonly )
#     {
#         # ---------- write experiment table,

#         foreach $exp_id ( grep { $_ =~ /^\d+$/ } keys %{ $data } )
#         {
#             push @table, dclone $data->{ $exp_id }->{"experiment"};
#         }
        
#         &Common::Tables::write_tab_table( "$tab_dir/exp_experiment.tab", \@table );
#         @table = ();

#         foreach $exp_id ( grep { $_ =~ /^\d+$/ } keys %{ $data } )
#         {
#             push @table, dclone $data->{ $exp_id }->{"condition"};
#         }
        
#         &Common::Tables::write_tab_table( "$tab_dir/exp_condition.tab", \@table );
#         @table = ();

#         &Common::Tables::write_tab_table( "$tab_dir/exp_gene.tab", $data->{"gene"} );
        
#         foreach $exp_id ( grep { $_ =~ /^\d+$/ } keys %{ $data } )
#         {
#             foreach $values ( @{ $data->{ $exp_id }->{"matrix"} } )
#             {
#                 push @table, dclone $values;
#             }
#         }
        
#         &Common::Tables::write_tab_table( "$tab_dir/exp_matrix.tab", \@table );
#         @table = ();
#     }
    
#     &echo_green( "done\n" );
    
#     # >>>>>>>>>>>>>>>>>>>>>> DELETE OLD DATABASE <<<<<<<<<<<<<<<<<<<<<<

#     if ( not $cl_readonly )
#     {
#         foreach $table ( keys %{ $schema } )
#         {
#             &Common::DB::delete_table_if_exists( $dbh, $table );
#         }
#     }
    
#     # >>>>>>>>>>>>>>>>>>> LOADING  DATABASE TABLES <<<<<<<<<<<<<<<<<<<<

#     if ( not $cl_readonly )
#     {
#         &echo( qq (   Loading test .tab files ... ) );
        
#         foreach $table ( keys %{ $schema } )
#         {
#             &Common::DB::create_table( $dbh, $table, $schema->{ $table } );
#         }
        
#         foreach $table ( keys %{ $schema } )
#         {
#             if ( not -r "$tab_dir/$table.tab" ) {
#                 &error( qq (Input table missing -> "$tab_dir/$table.tab") );
#                 exit;
#             }
            
#             &Common::DB::load_table( $dbh, "$tab_dir/$table.tab", $table );
#         }
        
#         &echo_green( "done\n" );
        
#         # >>>>>>>>>>>>>>>>>>>>>> ADDING EXTRA INDEXES <<<<<<<<<<<<<<<<<<<<
        
#         &echo( qq (   Fulltext-indexing text fields ... ) );
        
#         &Common::DB::request( $dbh, "create fulltext index descr_fndx on exp_condition(descr)" );
        
#         &echo_green( "done\n" );
        
#         &Common::DB::disconnect( $dbh );

#         # >>>>>>>>>>>>>>>>>>>>>>> DELETE DATABASE TABLES <<<<<<<<<<<<<<<<<

#         if ( not $cl_keep )
#         {
#             foreach $table ( keys %{ $schema } ) 
#             {
#                 &Common::File::delete_file( "$tab_dir/$table.tab" );
#             }

#             &Common::File::delete_dir_if_empty( $tab_dir );
#         }
#     }

#     return;
# }

# sub parse_test
# {
#     # Niels Larsen, April 2004.

#     my ( $file,    # file path
#          ) = @_;

#     # Returns a hash. 

#     my ( $line, @line, $data, @col_ndcs, $ndx, $gen_id, $value );

#     if ( not open FILE, $file ) {
#         &error( qq (Could not read-open "$file") );
#     }
    
#     while ( defined ( $line = <FILE> ) )
#     {
#         @line = split "\t", $line;
#         last if $line[0] =~ /^\w/;
#     }
    
#     @col_ndcs = ( 1, 3, 7, 11, 15 );

#     foreach $ndx ( @col_ndcs ) 
#     {
#         $data->{ $ndx }->{"condition"} = [ $ndx, $line[ $ndx ], "" ];
#     }

#     $data->{ 1 }->{"experiment"} = [ 1, 1 ];

#     foreach $ndx ( @col_ndcs[ 1 .. $#col_ndcs ] )
#     {
#         $data->{ $ndx }->{"experiment"} = [ $ndx, $ndx ];
#     }

#     while ( defined ( $line = <FILE> ) )
#     {
#         @line = split "\t", $line;
        
#         $gen_id = $line[21];

#         push @{ $data->{"gene"} }, [ $gen_id, $line[19], $line[22], $line[23], $line[0] ];

#         foreach $ndx ( @col_ndcs )
#         {
#             if ( $line[ $ndx+1 ] =~ /^P|A|M$/ )
#             {
#                 $line[ $ndx ] =~ s/,/\./;
#                 push @{ $data->{ $ndx }->{"matrix"} }, [ $ndx, $gen_id, $line[ $ndx ], "" ];
#             }
#             else
#             {
#                 $value = $line[ $ndx+1 ];
#                 &error( qq (Field looks strange -> $value) );
#             }
#         }
#     }

#     close FILE;

#     return wantarray ? %{ $data } : $data;
# }

# 1;


# __END__
