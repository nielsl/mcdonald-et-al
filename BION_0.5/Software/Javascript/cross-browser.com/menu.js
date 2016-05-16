/* This is only for convenience because this is an offline package.
   Don't include menus like this on a production site.
*/
/*
p (page): 0=other, 1=X, 2=XC, 3=Demos, 4=Docs, 5=Home
r (root): path to root (no trailing slash)
*/
function insert_header(p, r)
{
  var s = "<div id='header'><div id='menubar1'>";

  if (p == 1)
    s += "<b title='You are here'>X</b>";
  else
    s += "<a href='" + r + "/x/docs/x_index.html' title='X Library Symbol Index'>X</a>";

  s += "&nbsp;|&nbsp;";

  if (p == 2)
    s += "<b title='You are here'>XC</b>";
  else
    s += "<a href='" + r + "/x/docs/xc_reference.html' title='X Library Compiler Reference'>XC</a>";

  s += "&nbsp;|&nbsp;";

/*
  if (p == 3)
    s += "<b title='You are here'>Demos</b>";
  else
    s += "<a href='" + r + "/toys/index.html' title='Demos and Applications'>Demos</a>";

  s += "&nbsp;|&nbsp;";

  if (p == 4)
    s += "<b title='You are here'>Docs</b>";
  else
    s += "<a href='" + r + "/talk/index.html' title='Articles and Documentation'>Docs</a>";

  s += "&nbsp;|&nbsp;";
*/

  s += "<a href='http://cross-browser.com/forums/' title='X Library Support Forums'>Forums</a>";
  s += "&nbsp;|&nbsp;";

  if (p == 5)
    s += "<b title='You are here'>Home</b>";
  else
    s += "<a href='" + r + "/index.html' title='Offline Home Page'>Home</a>";

  s += "</div><h1>Cross-Browser.com</h1></div>";

  document.write(s);
}

