//
// Functions specific to GO terms display 
// 

function open_node( id ) {

    document.main.go_click_id.value = id;
    document.main.request.value = "open_node";
    document.main.submit();
}

function close_node( id ) {

    document.main.go_click_id.value = id;
    document.main.request.value = "close_node";
    document.main.submit();
}

function focus_node( id ) {

    document.main.go_click_id.value = id;
    document.main.request.value = "focus_node";
    document.main.submit();
}

function focus_name( name ) {

    document.main.go_root_name.value = name;
    document.main.request.value = "focus_name";
    document.main.submit();
}

function expand_node( nid, cid ) {

    document.main.go_click_id.value = nid;
    document.main.go_col_index.value = cid;
    document.main.request.value = "expand_node";
    document.main.submit();
}

function collapse_node( nid, cid ) {

    document.main.go_click_id.value = nid;
    document.main.go_col_index.value = cid;

    document.main.request.value = "collapse_node";
    document.main.submit();
}

function tax_projection( key, id ) {

    document.main.go_info_type.value = "functions";
    document.main.go_info_key.value = key;
    document.main.go_info_ids.value = id;

    document.main.page.value = "taxonomy";
    document.main.viewer.value = "taxonomy";
    document.main.request.value = "add_go_column";

    document.main.menu_1.value = "taxonomy";

    document.main.submit();
}

function handle_parents_menu( menu ) {

    id = menu.options[menu.selectedIndex].value;

    if ( id ) {
        document.main.go_click_id.value = id;
        document.main.request.value = "focus_node";
        document.main.submit();
    }
}

function handle_menu( menu, request ) {
    
    value = menu.options[menu.selectedIndex].value;

    if ( value ) {

        if ( request ) {
            document.main.request.value = request;
        }

            document.main.submit();
    }
}

function delete_column( id ) {

    document.main.go_col_index.value = id;
    document.main.request.value = "delete_column";
    document.main.submit();
}

function delete_columns() {

    document.main.request.value = "delete_columns";
    document.main.submit();
}

function column_differences() {

    document.main.request.value = "compare_columns";
    document.main.submit();
}

function show_widget( key ) {

    document.main.request.value = 'show_' + key;
    document.main.submit();
}

function hide_widget( key ) {

    document.main.request.value = 'hide_' + key;
    document.main.submit();
}

function save_terms() {
    
    document.main.request.value = "save_terms";
    document.main.go_info_type.value = "go";
    document.main.go_info_key.value = "go_terms_tsum";

    document.main.page.value = "go";
    document.main.submit();
}

function delete_selection( id ) {
    
    document.main.go_info_index.value = id;
    document.main.request.value = "delete_terms";
    document.main.submit();
}

function go_report( id, sid ) {
    
    var url;
    var sid;

    sid = document.main.session_id.value;

    url = "index.cgi?"
        + "go_report_id=" + id + ";"
        + "request=go_report;"
        + "viewer=go;page=go;"
        + "session_id=" + sid;

    open_window( "popup", url, 600, 700 );
}

/* 

function set_input_field( form, name, value ) {

    field = document.createElement('input');
    field.id = "1";
    field.name = name;
    
    if ( value ) {
        field.value = value;
    }

    form.appendChild(field);
}

*/

