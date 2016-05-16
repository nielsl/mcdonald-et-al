//
// Functions specific to disease terms display 
// 

function open_node( id ) {

    document.main.do_click_id.value = id;
    document.main.request.value = "open_node";
    document.main.submit();
}

function close_node( id ) {

    document.main.do_click_id.value = id;
    document.main.request.value = "close_node";
    document.main.submit();
}

function focus_node( id ) {

    document.main.do_click_id.value = id;
    document.main.request.value = "focus_node";
    document.main.submit();
}

function focus_name( name ) {

    document.main.do_root_name.value = name;
    document.main.request.value = "focus_name";
    document.main.submit();
}

function expand_node( nid, cid ) {

    document.main.do_click_id.value = nid;
    document.main.do_col_index.value = cid;
    document.main.request.value = "expand_node";
    document.main.submit();
}

function collapse_node( nid, cid ) {

    document.main.do_click_id.value = nid;
    document.main.do_col_index.value = cid;

    document.main.request.value = "collapse_node";
    document.main.submit();
}

function handle_parents_menu( menu ) {

    id = menu.options[menu.selectedIndex].value;

    if ( id ) {
        document.main.do_click_id.value = id;
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

    document.main.do_col_index.value = id;
    document.main.request.value = "delete_column";
    document.main.submit();
}

function delete_columns() {

    document.main.request.value = "delete_columns";
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
    document.main.do_info_type.value = "do";
    document.main.do_info_key.value = "do_terms_tsum";

    document.main.page.value = "do";
    document.main.submit();
}

function delete_selection( id ) {
    
    document.main.do_info_index.value = id;
    document.main.request.value = "delete_terms";
    document.main.submit();
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

