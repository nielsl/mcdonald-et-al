/*

Functions specific for the alignment display 

They typically set a few form parameter values and then
submit the form. After the submission the "request" parameter
is cleared to prevent repeat requests that make no sense.
The requests are also cleared on the server side each time.

*/

function handle_control_menu( menu ) {
    
    str = menu.options[menu.selectedIndex].value;

    if ( str ) {

        if ( str.match("javascript:") )
        {
            eval( str );
            menu.selectedIndex = 0;
        }
        else
        {
            document.viewer.request.value = str;

            document.viewer.submit();
            document.viewer.request.value = 0;
        }
    }
}

function request( key ) {

    document.viewer.request.value = key;
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

/*

RUBBER BAND BOX

Most of this code is by Michael Foster, http://cross-browser.com, 
with modifications by Gene Selkov.

*/

var pgObj = null;

/*
xAddEventListener(window, 'load',
  function () {
    pgObj = new xPage('../..', false, false, true);
    pgObj.onLoad();
      }, false
);
*/

xAddEventListener(window, 'load',
  function () {
    RubberBandBox('ali_image', rbbOnEnd);
    RubberBandBox('ali_image_map', rbbOnEnd);
  }, false
);

xAddEventListener(window, 'unload',
  function () {
    if (pgObj) pgObj.onUnload();
  }, false
);

function rbbOnEnd( x_beg, y_beg, x_end, y_end)
{
    document.viewer.request.value = "ali_nav_zoom_in_select";
    document.viewer.ali_image_area.value = x_beg +','+ x_end +','+ y_beg +','+ y_end;
    
    document.viewer.submit();
    return true;
}

function RubberBandBox(id, fn)
{
    var numexp = new RegExp("[0-9]+");
    var de = xGetElementById(id); // draggable element (img)
    var rb = document.createElement('div'); // rubber band element

    rb.className = 'RubberBandBox';
    de.parentNode.appendChild(rb);
    xEnableDrag(de, dragStart, drag, dragEnd);
    
    function dragStart(el, mx, my, ev)
    {
        xResizeTo(rb, 2, 2);
        xMoveTo(rb, ev.offsetX, ev.offsetY);
        rb.style.visibility = 'visible';
    }

    function drag(el, dx, dy, ev)
    {
        // xResizeTo(rb, rb.offsetWidth + dx, rb.offsetHeight + dy);

        var w = parseInt(rb.style.width.match(numexp));
        var h = parseInt(rb.style.height.match(numexp));
        rb.style.height = (h + dy ) + 'px';
        rb.style.width = (w + dx ) + 'px';

        return true;
    }

    function dragEnd(el)
    {
        var x_beg = rb.offsetLeft;
        var y_beg = rb.offsetTop; 
        var x_end = x_beg + rb.offsetWidth;
        var y_end = y_beg + rb.offsetHeight; 

        fn( x_beg, y_beg, x_end, y_end );
        
        return true;
    }
}

