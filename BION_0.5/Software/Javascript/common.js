//
// Handle menu changes
//

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

//
// Open and close popup windows
// 

function show_viewer( type, inputdb ) {

    document.viewer.viewer.value = type;
    document.viewer.inputdb.value = inputdb;
    document.viewer.menu_click.value = '';
    document.viewer.submit();
}

function show_array_viewer( inputdb ) {

    show_viewer( "array_viewer", inputdb );
}

function open_window( name, url, width, height, save ) {

    var win = window.open( url,
                           name,
                          "toolbar=no," +
                          "location=no," +
                          "directories=no," +
                          "status=no," +
                          "menubar=no," +
                          "scrollbars=yes," +
                          "resizable=yes," +
                          "width=" + width + "," +
                          "height=" + height + "," +
                          "innerwidth=" + width + "," +
                          "innerheight=" + height + ","
                          );

    win.resizeTo(width,height);
    win.focus();
}

function popup_window( url, width, height ) 
{
    open_window('popup', url, width, height );
}

function close_window( window ) {

    window.close();
    return false;
}

//
// Change pages 
//

function create_account() {

    document.viewer.sys_request.value = "create_account";
    document.viewer.submit();
}

function request_login_panel() {

    document.viewer.sys_request.value = "login_panel";
    document.viewer.submit();
}

function request_login() { 

    document.viewer.sys_request.value = "login";
    document.viewer.submit();
}

//
// Menu bar functions
// 

function expand_menu( text ) {

    document.viewer.menu_1.value = text;
    document.viewer.submit();
}

//
// X library by Michael Foster, http://www.cross-browser.com
//

function xDef()
{
  for(var i=0; i<arguments.length; ++i){if(typeof(arguments[i])=='undefined') return false;}
  return true;
}

function xGetElementById(e)
{
  if(typeof(e)!='string') return e;
  if(document.getElementById) e=document.getElementById(e);
  else if(document.all) e=document.all[e];
  else e=null;
  return e;
}

function xPageX(e)
{
  if (!(e=xGetElementById(e))) return 0;
  var x = 0;
  while (e) {
    if (xDef(e.offsetLeft)) x += e.offsetLeft;
    e = xDef(e.offsetParent) ? e.offsetParent : null;
  }
  return x;
}

function xPageY(e)
{
  if (!(e=xGetElementById(e))) return 0;
  var y = 0;
  while (e) {
    if (xDef(e.offsetTop)) y += e.offsetTop;
    e = xDef(e.offsetParent) ? e.offsetParent : null;
  }
//  if (xOp7Up) return y - document.body.offsetTop; // v3.14, temporary hack for opera bug 130324 (reported 1nov03)
  return y;
}

