//
// Functions specific to query pages
// 

function handle_results_menu( menu ) {

    eval ( menu.options[menu.selectedIndex].value );

    document.viewer.inputdb.value = inputdb;
    document.viewer.viewer.value = viewer;
    document.viewer.menu_click.value = '';
    document.viewer.submit();

    document.viewer.request.value = '';
}

