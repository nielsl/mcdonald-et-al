package Data::Registry::Schemas;            # -*- perl -*-

# Lists all database schemas.

use strict;
use warnings FATAL => qw ( all );

# SELECT sql_no_cache distinct r1.id,r1.mid,r1.v,r2.v FROM r r1, r r2 WHERE r1.id = 'miR-135' AND r2.id = 'let-7a' AND r1.mid = r2.mid AND r1.v >= 1 and abs(r1.v - r2.v) <= 20 AND r1.mid like "%ANK%";

my @schemas = 
    ({
        # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> USERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        
        "name" => "users",
        "datadir" => "Accounts",
        "title" => "Account information",
        "description" => qq (Account information and user registration details),
        "tables" => [
            {
                "name" => "accounts",
                "label" => "Accounts",
                "columns" => [
                    [ "user_id", "mediumint not null auto_increment", "index user_id_ndx (user_id)" ],
                    [ "session_id", "varchar(255) not null", "index session_id_ndx (session_id)" ],
                    [ "project", "varchar(255) not null", "index project_ndx (project)" ],
                    [ "username", "varchar(255) not null", "index username_ndx (username)" ],
                    [ "password", "varchar(255) not null", "index password_ndx (password)" ],
                    [ "credit", "mediumint not null", "index credit_ndx (credit)" ],
                    ],
            },{
                "name" => "info",
                "label" => "Registration",
                "columns" => [
                    [ "user_id", "mediumint not null auto_increment", "index user_id_ndx (user_id)" ],
                    [ "first_name", "varchar(255) not null", "index first_name_ndx (first_name)" ],
                    [ "last_name", "varchar(255) not null", "index last_name_ndx (last_name)" ],
                    [ "title", "varchar(255) not null", "index title_ndx (title)" ],
                    [ "department", "varchar(255) not null", "index department_ndx (department)" ],
                    [ "institution", "varchar(255) not null", "index institution_ndx (institution)" ],
                    [ "company", "varchar(255) not null", "index company_ndx (company)" ],
                    [ "street", "varchar(255) not null", "index street_ndx (street)" ],
                    [ "city", "varchar(255) not null", "index city_ndx (city)" ],
                    [ "postal_code", "varchar(255) not null", "index postal_code_ndx (postal_code)" ],
                    [ "state", "varchar(255) not null", "index state_ndx (state)" ],
                    [ "country", "varchar(255) not null", "index country_ndx (country)" ],
                    [ "web_home", "varchar(255) not null", "index web_home_ndx (web_home)" ],
                    [ "e_mail", "varchar(255) not null", "index e_mail_ndx (e_mail)" ],
                    [ "telephone", "varchar(255) not null", "index telephone_ndx (telephone)" ],
                    [ "telefax", "varchar(255) not null", "index telefax_ndx (telefax)" ],
                    ],
            }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> SYSTEM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "system",
         "title" => "System information",
         "description" => qq (Tables needed for running and doing bookkeeping within the system),
         "tables" => [
             {
                 "name" => "batch_queue",
                 "label" => "Batch queue",
                 "columns" => [
                     [ "id", "mediumint unsigned not null", "index id_ndx (id)" ],
                     [ "pid", "mediumint unsigned not null", "index pid_ndx (pid,id)" ],
                     [ "sid", "varchar(255) not null", "index sid_ndx (sid,id)" ],
                     [ "cid", "mediumint unsigned not null", "index cid_ndx (cid,id)" ],
                     [ "method", "varchar(255) not null", "index method_ndx (method,id)" ],
                     [ "input", "varchar(255) not null", "index input_ndx (input,id)" ],
                     [ "input_type", "varchar(255) not null", "index input_type_ndx (input_type,id)" ],
                     [ "serverdb", "varchar(255) not null", "index serverdb_ndx (serverdb,id)" ],
                     [ "output", "varchar(255) not null", "index output_ndx (output,id)" ],
                     [ "title", "varchar(255) not null", "index title_ndx (title,id)" ],
                     [ "coltext", "varchar(255) not null", "index coltext_ndx (coltext,id)" ],
                     [ "status", "varchar(255) not null", "index status_ndx (status,id)" ],
                     [ "message", "varchar(255) not null", "index message_ndx (message,id)" ],
                     [ "sub_time", "bigint unsigned not null", "index sub_time_ndx (sub_time,id)" ],
                     [ "beg_time", "bigint unsigned not null", "index beg_time_ndx (beg_time,id)" ],
                     [ "end_time", "bigint unsigned not null", "index end_time_ndx (end_time,id)" ],
                     [ "command", "varchar(255) not null" ],
                     [ "timeout", "mediumint unsigned not null" ],
                     ],
             },{
                 "name" => "db_stats",
                 "label" => "Database statistics",
                 "columns" => [
                     [ "type", "varchar(255) not null", "index type_ndx (type)" ],
                     [ "name", "varchar(255) not null", "index name_ndx (name)" ],
                     [ "title", "varchar(255) not null", "index title_ndx (title)" ],
                     [ "date", "bigint unsigned not null", "index date_ndx (date)" ],
                     ],
             },{
                 "name" => "db_test",
                 "label" => "Database test",
                 "columns" => [
                     [ "id1", "int not null", "index id1_ndx (id1)" ],
                     [ "id2", "int unsigned not null default 0" ],
                     ],
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>> ORGANISM TAXONOMY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "orgs_taxa",
         "title" => "Organism taxonomy",
         "description" => qq (Organism taxonomy),
         "datatypes" => [ "orgs_taxa" ],
         "tables" => [
             {
                 "name" => "tax_nodes",
                 "label" => "Nodes",
                 "columns" => [
                     [ "tax_id", "mediumint not null", "index tax_id_ndx (tax_id)" ],
                     [ "inputdb", "varchar(255) not null", "index inputdb_ndx (inputdb,tax_id)" ],
                     [ "parent_id", "mediumint not null", "index parent_id_ndx (parent_id,tax_id)" ],
                     [ "nmin", "mediumint not null", "index nmin_ndx (nmin)" ],
                     [ "nmax", "mediumint not null", "index nmax_ndx (nmax)" ],
                     [ "depth", "tinyint not null", "index depth_ndx (depth,tax_id)" ],
                     [ "rank", "varchar(30) not null", "index rank_ndx (rank,tax_id)" ],
                     [ "embl_code", "char(2) not null", "index embl_code_ndx (embl_code,tax_id)" ],
                     [ "div_code", "varchar(3) not null", "index div_code_ndx (div_code,tax_id)" ],
                     [ "div_name", "varchar(30) not null", "index div_name_ndx (div_name,tax_id)" ],
                     [ "gc_id", "tinyint not null", "index gc_id_ndx (gc_id)" ],
                     [ "mgc_id", "tinyint not null", "index mgc_id_ndx (mgc_id)" ],
                     [ "name", "varchar(100) not null", "index name_ndx (name,tax_id)" ],
                     [ "name_type", "varchar(50) not null", "index name_type_ndx (name_type,tax_id)"  ],
                     ],
             },{
                 "name" => "tax_stats",
                 "label" => "Statistics",
                 "columns" => [
                     [ "tax_id", "int unsigned not null", "index tax_id_ndx (tax_id)" ],
                     [ "job_id", "mediumint unsigned not null", "index job_id_ndx (job_id,tax_id)" ],
                     [ "inputdb", "varchar(255) not null", "index inputdb_ndx (inputdb,datatype,tax_id)" ],
                     [ "datatype", "varchar(255) not null" ],
                     [ "value", "int unsigned not null", "index value_ndx (value,tax_id)" ],
                     [ "sum", "bigint unsigned not null" ],
                     ],
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EXPRESSION <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "expr_mirconnect",
         "title" => "MiRConnect expression data",
         "description" => "MiRConnect miRNA vs genes correlations",
         "datatypes" => [ "expr_mirconnect" ],
         "tables" => [
             {
                 "name" => "mir_names",
                 "label" => "miRNAs, Families",
                 "columns" => [
                     [ "method", "varchar(10) not null", "index method_ndx (method,mir_id)" ],
                     [ "mir_id", "varchar(255) not null", "index mir_id_ndx (mir_id,imbrs)" ],
                     [ "imbrs", "int not null", "index imbrs_ndx (imbrs,mir_id)" ],
                     [ "mbrs", "text not null" ],
                     ],
             },{
                 "name" => "gene_names",
                 "label" => "Gene Names",
                 "columns" => [
                     [ "gene_id", "varchar(30) not null", "index gene_id_ndx (gene_id,gene_chr)" ],
                     [ "gene_chr", "varchar(50) not null", "index gene_chr_ndx (gene_chr,gene_id)" ],
                     [ "gene_name", "text not null" ],
                     ],
             },{
                 "name" => "spcc_method",
                 "label" => "(sPCC) miRNAs vs mRNAs",
                 "columns" => [
                     [ "mir_id", "varchar(100) not null", "index mir_id_ndx (mir_id,gene_id)" ],
                     [ "gene_id", "varchar(50) not null", "index gene_id_ndx (gene_id,mir_id)" ],
#                     [ "ts_cons", "float(5,3)", "index ts_cons_ndx (ts_cons,gene_id,mir_id)" ],
#                     [ "cor_val", "float(5,3)", "index cor_val_ndx (cor_val,gene_id,mir_id)" ],
                     [ "ts_cons", "float(4,2)", "index ts_cons_ndx (ts_cons)" ],
                     [ "cor_val", "float(4,2)", "index cor_val_ndx (cor_val)" ],
                     ],
             },{
                 "name" => "dpcc_method",
                 "label" => "(dPCC) miRNAs vs mRNAs",
                 "optional" => 1,
                 "columns" => [
                     [ "mir_id", "varchar(100) not null", "index mir_id_ndx (mir_id,gene_id)" ],
                     [ "gene_id", "varchar(50) not null", "index gene_id_ndx (gene_id,mir_id)" ],
                     [ "ts_cons", "float(4,2)", "index ts_cons_ndx (ts_cons)" ],
                     [ "cor_val", "float(4,2)", "index cor_val_ndx (cor_val)" ],
                     ],
             }],
     },{

         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "funcs",
         "title" => "Functions",
         "description" => qq (Functions),
         "datatypes" => [ "go_func" ],
         "tables" => [
             {
                 "name" => "func_def",
                 "label" => "Node descriptions",
                 "columns" => [
                     [ "id", "mediumint not null", "index id_ndx (id)" ],
                     [ "name", "varchar(255) not null", "index name_ndx (name,id)" ],
                     [ "deftext", "text not null", "index deftext_ndx (deftext(255))" ],
                     [ "comment", "text not null", "index comment_ndx (comment(255))" ],
                     ],
             },{
                 "name" => "func_def_ref",
                 "label" => "",
                 "columns" => [
                     [ "id", "mediumint not null", "index id_ndx (id)" ],
                     [ "db", "varchar(255) not null", "index db_ndx (db,id)" ],
                     [ "name", "varchar(255) not null", "index name_ndx (name,id)" ],
                     ],
             },{
                 "name" => "func_edges",
                 "label" => "Edges",
                 "columns" => [
                     [ "id", "mediumint not null", "index id_ndx (id,parent_id)" ],
                     [ "parent_id", "mediumint not null", "index parent_id_ndx (parent_id,id)" ],
                     [ "dist", "tinyint not null", "index dist_ndx (dist,id)" ],
                     [ "depth", "tinyint not null", "index depth_ndx (depth,id)" ],
                     [ "leaf", "tinyint not null", "index leaf_ndx (leaf,id)" ],
                     [ "rel", "char(1) not null", "index rel_ndx (rel,id)" ],
                     ],
             },{
                 "name" => "func_synonyms",
                 "label" => "Synonyms",
                 "columns" => [
                     [ "id", "mediumint not null", "index id_ndx (id)" ],
                     [ "name", "varchar(255) not null", "index name_ndx (name,id)" ],
                     [ "syn", "varchar(255) not null", "index syn_ndx (syn,id)" ],
                     [ "rel", "varchar(255) not null", "index rel_ndx (rel,id)" ],
                     ],
             },{
                 "name" => "func_external",
                 "label" => "External",
                 "columns" => [
                     [ "id", "mediumint not null", "index id_ndx (id)" ],
                     [ "ext_db", "varchar(255) not null", "index ext_db_ndx (ext_db,id)" ],
                     [ "ext_id", "varchar(255) not null", "index ext_id_ndx (ext_id,id)" ],
                     [ "ext_name", "varchar(255) not null", "index ext_name_ndx (ext_name,id)" ],
                     ],
             },{
                 "name" => "func_genes",
                 "label" => "Genes",
                 "columns" => [
                     [ "db", "varchar(50) not null", "index db_ndx (db)" ],
                     [ "db_id", "varchar(50) not null", "index db_id_ndx (db_id)" ],
                     [ "gen_id", "mediumint not null", "index get_id_ndx (gen_id)" ],
                     [ "db_name", "varchar(255) not null", "" ],
                     [ "db_symbol", "varchar(50) not null", "index db_symbol_ndx (db_symbol)" ],
                     [ "modifier", "varchar(255) not null", "" ],
                     [ "evidence", "char(3) not null", "" ],
                     [ "aspect", "char(1) not null", "" ],
                     [ "db_type", "varchar(255) not null", "" ],
                     [ "date", "date not null", "" ],
                     [ "db_assn", "varchar(255) not null", "" ],
                     ],
             },{
                 "name" => "func_genes_ref",
                 "label" => "Genes ref",
                 "columns" => [
                     [ "db", "varchar(255) not null", "index db_ndx (db)" ],
                     [ "db_id", "varchar(255) not null", "index db_id_ndx (db_id)" ],
                     [ "gen_id", "mediumint not null", "index gen_id_ndx (gen_id)" ],
                     ],
             },{
                 "name" => "func_genes_tax",
                 "label" => "Genes tax",
                 "columns" => [
                     [ "id", "mediumint not null", "index id_ndx (id,tax_id)" ],
                     [ "gen_id", "mediumint not null", "index gen_id_ndx (gen_id)" ],
                     [ "tax_id", "mediumint not null", "index tax_id_ndx (tax_id,id)" ],
                     [ "tax_id_use", "mediumint not null", "" ],
                     ],
             },{
                 "name" => "func_genes_synonyms",
                 "label" => "Genes synonyms",
                 "columns" => [
                     [ "gen_id", "mediumint not null", "index gen_id_ndx (gen_id)" ],
                     [ "db_syn", "varchar(255) not null", "index db_syn_ndx (db_syn)" ],
                     ],
             },{
                 "name" => "func_stats",
                 "label" => "Stats",
                 "columns" => [
                     [ "id", "int not null", "index id_ndx (id)" ],
                     [ "go_terms_tsum", "int unsigned not null default 0" ],
                     [ "go_terms_usum", "int unsigned not null default 0" ],
                     [ "go_genes_node", "int unsigned not null default 0" ],
                     [ "go_genes_tsum", "int unsigned not null default 0" ],
                     [ "go_genes_usum", "int unsigned not null default 0" ],
                     [ "go_orgs_usum", "int unsigned not null default 0" ],
                     ],
             },
             ],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>> ALIGNMENTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         # See also at the bottom of this page.

         "name" => "ali",
         "title" => "Alignment database",
         "description" => qq (Alignment features and annotation),
         "datatypes" => [ "rna_ali", "prot_ali", "dna_ali" ],
         "tables" => [
             {
                 "name" => "ali_features",
                 "label" => "Features",
                 "columns" => [
                     [ "ali_id", "varchar(255) not null", "index ali_id_ndx (ali_id,ft_id)" ],
                     [ "ali_type", "varchar(255) not null" ],
                     [ "ft_id", "int unsigned not null", "index ft_id_ndx (ft_id,ali_id)" ],
                     [ "ft_type", "varchar(255) not null", "index type_ndx (ft_type,ft_id)" ],
                     [ "source", "varchar(255) not null", "index source_ndx (source,ft_id)" ],
                     [ "score", "float(5,2) not null", "index score_ndx (score,ft_id)" ],
                     [ "stats", "text not null" ],
                     ],
             },{
                 "name" => "ali_feature_pos",
                 "label" => "Feature positions",
                 "columns" => [
                     [ "ali_id", "varchar(255) not null", "index ali_id_ndx (ali_id,ft_type,rowbeg,rowend,colbeg,colend)" ],
                     [ "ali_type", "varchar(255) not null" ],
                     [ "ft_id", "int unsigned not null", "index ft_id_ndx (ft_id,ali_id)" ],
                     [ "ft_type", "varchar(255) not null", "index ft_type_ndx (ft_type,ali_id)" ],
                     [ "source", "varchar(255) not null", "index source_ndx (source,ft_id)" ],
                     [ "colbeg", "int unsigned not null", "index colbeg_ndx (colbeg,ft_id)" ],
                     [ "colend", "int unsigned not null", "index colend_ndx (colend,ft_id)" ],
                     [ "rowbeg", "int unsigned not null", "index rowbeg_ndx (rowbeg,ft_id)" ],
                     [ "rowend", "int unsigned not null", "index rowend_ndx (rowend,ft_id)" ],
                     [ "title", "text not null" ],
                     [ "descr", "text not null" ],
                     [ "styles", "text not null" ],
                     [ "spots", "text not null" ],
                     ],
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> DNA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "dna_seq",
         "title" => "DNA sequence and annotation",
         "description" => qq (DNA sequence and annotation),
         "datatypes" => [ "dna_seq" ],
         "tables" => [
             {
                 "name" => "dna_organism",
                 "columns" => [
                     [ "tax_id", "varchar(6) not null", "index tax_id_ndx (tax_id,ent_id)" ],
                     [ "ent_id", "varchar(12) not null", "index ent_id_ndx (ent_id,tax_id)" ],
                     ],
             },{
                 "name" => "dna_entry",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null", "index ent_id_ndx (ent_id)" ],
                     [ "division", "char(3) not null", "index division_ndx (division,ent_id)" ],
                     [ "c_date", "date not null", "index c_date_ndx (c_date,ent_id)" ],
                     [ "u_date", "date not null", "index u_date_ndx (u_date,ent_id)" ],
                     [ "description", "text not null", "index description_ndx (description(255))" ],
                     [ "keywords", "text not null", "index keywords_ndx (keywords(255))" ],
                     ],
             },{
                 "name" => "dna_organelle",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null", "index ent_id_ndx (ent_id)"  ],
                     [ "type", "varchar(80) not null", "index type_ndx (type)" ],
                     ],
             },{
                 "name" => "dna_molecule",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null", "index end_id_ndx (ent_id)" ],
                     [ "type", "char(3) not null", "index type_ndx (type)" ],
                     [ "length", "mediumint unsigned not null" ],
                     [ "a", "mediumint unsigned not null" ],
                     [ "g", "mediumint unsigned not null" ],
                     [ "c", "mediumint unsigned not null" ],
                     [ "t", "mediumint unsigned not null" ],
                     [ "other", "mediumint unsigned not null" ],
                     [ "gc_pct", "float(5,2) unsigned not null", "index gc_pct_ndx (gc_pct)" ],
                     ],
             },{
                 "name" => "dna_accession",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null", "index ent_id_ndx (ent_id)" ],
                     [ "accession", "varchar(12) not null", "index accession_ndx (accession)" ],
                     ],
             },{
                 "name" => "dna_db_xref",
                 "columns" => [
                     [ "ft_id", "int unsigned not null", "index ft_id_ndx (ft_id)" ],
                     [ "db_name", "varchar(20) not null", "index db_name_ndx (db_name)" ],
                     [ "db_id", "varchar(20) not null", "index db_id_ndx (db_id)" ],
                     ],
             },{
                 "name" => "dna_protein_id",
                 "columns" => [
                     [ "ft_id", "varchar(10) not null", "index ft_id_ndx (ft_id)" ],        
                     [ "prot_id", "varchar(20) not null", "index prot_id_ndx (prot_id)" ],
                     ],
             },{
                 "name" => "dna_ft_locations",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null", "index ent_id_ndx (ent_id)" ],
                     [ "ft_id", "int unsigned not null", "index ft_id_ndx (ft_id,ent_id)" ],
                     [ "key_id", "tinyint unsigned not null", "index key_id_ndx (key_id,ent_id)" ],
                     [ "beg", "mediumint unsigned not null", "index beg_ndx (beg)" ],
                     [ "end", "mediumint unsigned not null", "index end_ndx (end)" ],
                     [ "strand", "bit not null", "index strand_ndx (strand)" ],
                     ],
             },{
                 "name" => "dna_ft_qualifiers",
                 "columns" => [
                     [ "ft_id", "int unsigned not null", "index ft_id_ndx (ft_id)" ],
                     [ "qual_id", "tinyint unsigned not null", "index qual_id_ndx (qual_id,ft_id)" ],
                     [ "val_id", "int unsigned not null", "index val_id_ndx (val_id,ft_id)" ],
                     ],
             },{
                 "name" => "dna_ft_values",
                 "columns" => [
                     [ "val_id", "int unsigned not null", "index val_id_ndx (val_id)" ],
                     [ "val", "text not null", "index val_ndx (val(255))" ],
                     ],
             },{
                 "name" => "dna_reference",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null", "index ent_id_ndx (ent_id)" ],
                     [ "ref_no", "mediumint unsigned not null", "index ref_no_ndx (ref_no)" ],
                     [ "aut_id", "mediumint unsigned not null", "index aut_id_ndx (aut_id,ent_id)" ],
                     [ "lit_id", "mediumint unsigned not null", "index lit_id_ndx (lit_id,ent_id)" ],
                     [ "tit_id", "mediumint unsigned not null", "index tit_id_ndx (tit_id,ent_id)" ],
                     ],
             },{
                 "name" => "dna_authors",
                 "columns" => [
                     [ "aut_id", "mediumint unsigned not null", "index aut_id_ndx (aut_id)"  ],
                     [ "text", "text not null", "index text_ndx (text(255))" ],
                     ],
             },{
                 "name" => "dna_literature",
                 "columns" => [
                     [ "lit_id", "mediumint unsigned not null", "index lit_id_ndx (lit_id)" ],
                     [ "text", "text not null", "index text_ndx (text(255))" ],
                     ],
             },{
                 "name" => "dna_title",
                 "columns" => [
                     [ "tit_id", "mediumint unsigned not null", "index tit_id_ndx (tit_id)"  ],
                     [ "text", "text not null", "index text_ndx (text(255))" ],
                     ],
             },{
                 "name" => "dna_citation",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null", "index ent_id_ndx (ent_id)" ],
                     [ "name", "varchar(10) not null", "index name_ndx (name,ent_id)" ],
                     [ "citid", "varchar(20) not null", "index citid_ndx (citid,ent_id)" ],
                     ],
             },{
                 "name" => "dna_seq_index",
                 "columns" => [
                     [ "ent_id", "varchar(12) not null" ],
                     [ "byte_beg", "bigint unsigned not null" ],
                     [ "byte_end", "bigint unsigned not null", "index byte_pos_ndx (ent_id,byte_beg,byte_end)" ],
                     ],
             }],
     },{
         # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> RNA <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

         "name" => "rna_seq",
         "title" => "RNA sequence and annotation",
         "description" => 
             qq (RNA sequence and annotation. This looks DNA/EMBL-like, and has been used)
             . qq ( to store the result of finding SSU RNAs in EMBL, but will need to be)
             . qq ( modified quite a bit),
             "tables" => [
                 {
                     "name" => "rna_origin",
                     "columns" => [
                         [ "rna_id", "int unsigned not null", "index rna_id_ndx (rna_id)" ],
                         [ "type", "varchar(50) not null", "index type_ndx (type,rna_id)" ],
                         [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,rna_id)" ],
                         [ "src_db", "varchar(20) not null", "index src_db_ndx (src_db,rna_id)" ],
                         [ "src_id", "varchar(10) not null", "index src_id_ndx (src_id,rna_id)" ],
                         [ "src_ac", "varchar(10) not null", "index src_ac_ndx (src_ac,rna_id)" ],
#                                       [ "src_de", "text not null", "index src_de_ndx (src_de(100),rna_id)" ],
#                                       [ "src_kw", "text not null", "index src_kw_ndx (src_kw(100),rna_id)" ],
                         [ "src_de", "text not null" ],
                         [ "src_kw", "text not null" ],
                         [ "src_sv", "int unsigned not null", "index src_sv_ndx (src_sv,rna_id)" ],
                         [ "src_cl", "int unsigned not null", "index src_cl_ndx (src_cl,rna_id)" ],
                         [ "src_ct", "date not null", "index src_ct_ndx (src_ct,rna_id)" ],
                         [ "src_ut", "date not null", "index src_ut_ndx (src_ut,rna_id)" ],
                         [ "vendor", "varchar(20) not null", "index from_ndx (vendor,rna_id)" ],
                         [ "method", "varchar(20) not null", "index method_ndx (method,rna_id)" ],
                         [ "date", "date not null", "index date_ndx (date,rna_id)" ],
                         ],
                 },{
                     "name" => "rna_organism",
                     "columns" => [
                         [ "rna_id", "int unsigned not null", "index rna_id_ndx (rna_id,tax_id)" ],
                         [ "type", "varchar(50) not null", "index type_ndx (type,rna_id)" ],
                         [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,rna_id)" ],
                         [ "tax_id_host", "mediumint unsigned not null", "index tax_id_host_ndx (tax_id_host,rna_id)" ],
#                                       [ "taxonomy", "text not null", "index taxonomy_ndx (taxonomy(255))" ],
                         [ "taxonomy", "text not null" ],
                         [ "genus", "varchar(255) not null", "index genus_ndx (genus,rna_id)" ],
                         [ "species", "varchar(255) not null", "index species_ndx (species,rna_id)" ],
                         [ "sub_species", "varchar(255) not null", "index sub_species_ndx (sub_species,rna_id)" ],
                         [ "strain", "varchar(255) not null", "index strain_ndx (strain,rna_id)" ],
                         [ "sub_strain", "varchar(255) not null", "index sub_strain_ndx (sub_strain,rna_id)" ],
                         [ "variety", "varchar(255) not null", "index variety_ndx (variety,rna_id)" ],
                         [ "serotype", "varchar(255) not null", "index serotype_ndx (serotype,rna_id)" ],
                         [ "serovar", "varchar(255) not null", "index serovar_ndx (serovar,rna_id)" ],
                         [ "biovar", "varchar(255) not null", "index biovar_ndx (biovar,rna_id)" ],
                         [ "cultivar", "varchar(255) not null", "index cultivar_ndx (cultivar,rna_id)" ],
                         [ "ecotype", "varchar(255) not null", "index ecotype_ndx (ecotype,rna_id)" ],
                         [ "haplotype", "varchar(255) not null", "index haplotype_ndx (haplotype,rna_id)" ],
                         [ "name", "varchar(255) not null", "index name_ndx (name,rna_id)" ],
                         [ "common_name", "varchar(255) not null", "index common_name_ndx (common_name,rna_id)" ],
                         ],
                 },{
                     "name" => "rna_source",
                     "columns" => [
                         [ "rna_id", "int unsigned not null", "index rna_id_ndx (rna_id)" ],
                         [ "type", "varchar(50) not null", "index type_ndx (type,rna_id)" ],
                         [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,rna_id)" ],
                         [ "cell_line", "text not null" ],
                         [ "cell_type", "text not null" ],
                         [ "clone", "text not null" ],
                         [ "clone_lib", "text not null" ],
                         [ "sub_clone", "text not null" ],
                         [ "dev_stage", "text not null" ],
                         [ "environmental_sample", "text not null" ],
                         [ "isolate", "text not null" ],
                         [ "isolation_source", "text not null" ],
                         [ "lab_host", "text not null" ],
                         [ "label", "text not null" ],
                         [ "note", "text not null" ],
                         [ "organelle", "text not null" ],
                         [ "plasmid", "text not null" ],
                         [ "specific_host", "text not null" ],
                         [ "tissue", "text not null" ],
                         [ "tissue_lib", "text not null" ],
                         [ "tissue_type", "text not null" ],
                         ],
                 },{
                     "name" => "rna_references",
                     "columns" => [
                         [ "rna_id", "varchar(10) not null", "index rna_id_ndx (rna_id)" ],
                         [ "type", q"varchar(50) not null", "index type_ndx (type,rna_id)" ],
                         [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,rna_id)" ],
                         [ "ref_no", "int unsigned not null", "index ref_no_ndx (ref_no)" ],
                         [ "authors", "text not null", "index authors_ndx (literature(255))" ],
                         [ "literature", "text not null", "index literature_ndx (literature(255))" ],
                         [ "title", "text not null", "index title_ndx (title(255))" ],
                         ],
                 },{
                     "name" => "rna_xrefs",
                     "columns" => [
                         [ "rna_id", "int unsigned not null", "index rna_id_ndx (rna_id)" ],
                         [ "type", "varchar(50) not null", "index type_ndx (type,rna_id)" ],
                         [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,rna_id)" ],
                         [ "name", "varchar(20) not null", "index name_ndx (name,rna_id)" ],
                         [ "id", "varchar(20) not null", "index id_ndx (id,rna_id)" ],
                         ],
                 },{
                     "name" => "rna_molecule",
                     "columns" => [
                         [ "rna_id", "int unsigned not null", "index rna_id_ndx (rna_id)" ],
                         [ "type", "varchar(50) not null", "index type_ndx (type,rna_id)" ],
                         [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,length,rna_id)" ],
                         [ "length", "int unsigned not null" ],
                         [ "a", "int unsigned not null" ],
                         [ "g", "int unsigned not null" ],
                         [ "c", "int unsigned not null" ],
                         [ "t", "int unsigned not null" ],
                         [ "other", "int unsigned not null" ],
                         [ "gc_pct", "float(5,2) unsigned not null", "index gc_pct_ndx (gc_pct,rna_id)" ],
                         [ "complete", "tinyint not null", "index complete_ndx (complete,rna_id)" ],
                         [ "exact", "tinyint not null", "index exact_ndx (exact,rna_id)" ],
#                                       [ "sequence", "text not null" ],
                         ],
                 },{
                     "name" => "rna_locations",
                     "columns" => [
                         [ "rna_id", "int unsigned not null", "index rna_id_ndx (rna_id)" ],
                         [ "type", "varchar(50) not null", "index type_ndx (type,rna_id)" ],
                         [ "tax_id", "mediumint unsigned not null", "index tax_id_ndx (tax_id,rna_id)" ],
                         [ "rna_beg", "int unsigned not null", "index rna_beg_ndx (rna_beg,rna_id)" ],
                         [ "rna_end", "int unsigned not null", "index rna_end_ndx (rna_end,rna_id)" ],
                         [ "dna_id", "varchar(10) not null", "index dna_id_ndx (dna_id,rna_id)" ],
                         [ "dna_beg", "int unsigned not null", "index dna_beg_ndx (dna_beg,rna_id)" ],
                         [ "dna_end", "int unsigned not null", "index dna_end_ndx (dna_end,rna_id)" ],
                         [ "strand", "bit not null", "index strand_ndx (strand,rna_id)" ],
                         ],
                 }],
     });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    my ( $schema, $table );

    foreach $schema ( @schemas )
    {
        foreach $table ( @{ $schema->{"tables"} } )
        {
            $table->{"optional"} = 0 if not exists $table->{"optional"};
        }
    }

    return wantarray ? @schemas : \@schemas;
}
    
1;

__END__

# sub schema
# {
#     # Niels Larsen, April 2004.

#     # Creates a hash where keys are table names and values are lists of 
#     # [ field name, datatype, index specification ] where the index 
#     # specification is optional. 

#     # Returns a hash. 

#     my $schema = 
#     {
#         "exp_matrix" => [
#                          [ "exp_id", "mediumint not null", "index ext_id_ndx (exp_id,gen_id)" ],
#                          [ "gen_id", "varchar(255) not null", "index gen_id_ndx (gen_id,exp_id)" ],
#                          [ "value", "float(2) not null", "index value_ndx (value)" ],
#                          [ "var", "float(2) not null", "index var_ndx (var)" ],
#                          ],

#         "exp_experiment" => [
#                              [ "exp_id", "mediumint not null", "index exp_id_ndx (exp_id)" ],
#                              [ "cond_id", "mediumint not null", "index cond_id_ndx (cond_id,exp_id)" ],
#                              ],
        
#         "exp_condition" => [
#                             [ "cond_id", "mediumint not null", "index cond_id_ndx (cond_id)" ],
#                             [ "title", "varchar(255) not null", "index title_ndx (title)" ],
#                             [ "descr", "varchar(255) not null", "" ],
#                             ],
        
#         "exp_gene" => [
#                        [ "gen_id", "varchar(20) not null", "index gen_id_ndx (gen_id)" ],
#                        [ "name", "varchar(255) not null", "index name_ndx (name,gen_id)" ],
#                        [ "unig_id", "mediumint not null", "index unig_ndx (unig_id,gen_id)" ],
#                        [ "cyto_id", "varchar(255) not null", "index cyto_id_ndx (cyto_id,gen_id)" ],
#                        [ "oli_id", "varchar(255) not null", "index oli_id_ndx (oli_id,gen_id)" ],
#                        ],
#     };

#     return $schema;
# }



#         "ali_annotation" => [
#                              [ "ali_id", "int unsigned not null", "index ali_id_ndx (ali_id)" ],
#                              [ "sid", "varchar(20) not null", "index sid_ndx (sid,ali_id)" ],
#                              [ "title", "varchar(255) not null", "index title_ndx (title,ali_id)" ],
#                              [ "source", "varchar(20) not null", "index source_ndx (source,ali_id)" ],
#                              [ "datatype", "varchar(20) not null", "index datatype_ndx (datatype,ali_id)" ],
#                              [ "authors", "varchar(255) not null", "index authors_ndx (authors,ali_id)" ],
#                              [ "descr", "varchar(255) not null", "index descr_ndx (descr,ali_id)" ],
#                              [ "url", "varchar(255) not null" ],
#                              ],

#         "ali_references" => [
#                              [ "ali_id", "int unsigned not null", "index ali_id_ndx (ali_id)" ],
#                              [ "ref_no", "int unsigned not null", "index ref_no_ndx (ref_no)" ],
#                              [ "authors", "text not null", "index authors_ndx (authors(255))" ],
#                              [ "literature", "text not null", "index literature_ndx (literature(255))" ],
#                              [ "title", "text not null", "index title_ndx (title(255))" ],
#                              ],

#         "ali_seqs" => [
#                        [ "ali_id", "int unsigned not null", "index ali_id_ndx (ali_id)" ],
#                        [ "seq_id", "varchar(50) not null", "index seq_id_ndx (seq_id,ali_id)" ],
#                        [ "row_ndx", "int unsigned not null" ],
#                        ],

        # A feature is defined in these two tables, as sets of column- and row-ranges.
        # They can be disjunct, but the pieces will in that case have the same feature
        # id (ft_id).   IN FLUX - will move towards GFF3.
