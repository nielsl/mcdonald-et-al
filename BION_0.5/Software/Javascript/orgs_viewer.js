//
// Functions specific to taxonomy display 
// 
// They typically set a few form parameter values and then
// submit the form. After the submission the "request" parameter
// is cleared to prevent repeat requests that make no sense.
// The requests are also cleared on the server side each time.
//

function open_node( id ) {

    document.viewer.tax_click_id.value = id;
    document.viewer.request.value = "open_node";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function close_data( nid, cid ) {

    document.viewer.tax_click_id.value = nid;
    document.viewer.tax_col_index.value = cid;
    document.viewer.request.value = "close_data";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function close_node( id ) {

    document.viewer.tax_click_id.value = id;
    document.viewer.request.value = "close_node";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function focus_node( id ) {

    document.viewer.tax_click_id.value = id;
    document.viewer.request.value = "focus_node";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function focus_name( name ) {

    /* document.viewer.tax_root_name.value = name; */

    document.viewer.request.value = "focus_name";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function expand_data( nid, cid ) {

    document.viewer.tax_click_id.value = nid;
    document.viewer.tax_col_index.value = cid;
    document.viewer.request.value = "expand_data";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function expand_node( nid, cid ) {

    document.viewer.tax_click_id.value = nid;
    document.viewer.tax_col_index.value = cid;
    document.viewer.request.value = "expand_node";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function collapse_node( nid, cid ) {

    document.viewer.tax_click_id.value = nid;
    document.viewer.tax_col_index.value = cid;

    document.viewer.request.value = "collapse_node";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function go_projection( key, id ) {

    document.viewer.tax_info_type.value = "organisms";
    document.viewer.tax_info_key.value = key;
    document.viewer.tax_info_ids.value = id;

    document.viewer.page.value = "go";
    document.viewer.viewer.value = "go";
    document.viewer.request.value = "add_tax_column";

    document.viewer.menu_1.value = "go";

    document.viewer.submit();

    document.viewer.request.value = '';
}

function handle_parents_menu( menu ) {

    id = menu.options[menu.selectedIndex].value;

    if ( id ) {
        document.viewer.tax_click_id.value = id;
        document.viewer.request.value = "focus_node";
        document.viewer.submit();

        document.viewer.request.value = '';
    }
}

function handle_menu( menu, request ) {
    
    value = menu.options[menu.selectedIndex].value;

    if ( value ) {

        if ( request ) {
            document.viewer.request.value = request;
        }

        document.viewer.submit();

        document.viewer.request.value = '';
    }
}

function delete_column( id ) {

    document.viewer.tax_col_index.value = id;
    document.viewer.request.value = "delete_column";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function delete_columns() {

    document.viewer.request.value = "delete_columns";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function show_widget( key ) {

    document.viewer.request.value = 'show_' + key;
    document.viewer.submit();

    document.viewer.request.value = '';
}

function hide_widget( key ) {

    document.viewer.request.value = 'hide_' + key;
    document.viewer.submit();

    document.viewer.request.value = '';
}

function save_orgs() {
    
    document.viewer.request.value = "save_orgs";
    document.viewer.tax_info_type.value = "tax";
    document.viewer.tax_info_key.value = "go_terms_tsum";

    document.viewer.page.value="taxonomy";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function delete_selection( id ) {
    
    document.viewer.tax_info_index.value = id;
    document.viewer.request.value = "delete_orgs";
    document.viewer.submit();

    document.viewer.request.value = '';
}

function orgs_taxa_report( id, cgi_url ) {
    
    var url;
    var sid;

    sid = document.viewer.session_id.value;

    url = cgi_url + "/index.cgi?"
        + "tax_report_id=" + id + ";"
        + "request=orgs_taxa_report;"
        + "viewer=orgs_viewer;page=taxonomy;"
        + "session_id=" + sid;

    open_window( "popup", url, 550, 600 );
}

function rna_seq_report( id, cgi_url ) {
    
    var url;
    var sid;

    sid = document.viewer.session_id.value;

    url = cgi_url + "/index.cgi?"
        + "tax_report_id=" + id + ";"
        + "request=rna_seq_report;"
        + "viewer=orgs_viewer;page=taxonomy;"
        + "session_id=" + sid;

    open_window( "popup", url, 700, 900 );
}

// 
// Download
//

function download_seqs( inputdb ) {

    document.viewer.tax_inputdb.value = inputdb;    
    document.viewer.request.value = "download_seqs";
    document.viewer.submit();

    document.viewer.request.value = '';
}
