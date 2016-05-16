//
// Functions specific to query pages
// 

function submit_query() {

    document.main.request.value = "query";
    document.main.view.value = "query";
     
    document.main.submit();
}

