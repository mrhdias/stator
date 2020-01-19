import os, strutils, oids
import json
import asyncdispatch, asyncfile
import stator/[asynchttpserver, asynchttpbodyparser, asynchttpfileserver]

proc handler(req: Request) {.async.} =
  let form = """<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<script>

function test_json() {
  var login = document.getElementById("login").value;
  var password = document.getElementById("password").value;
  if (login.length == 0) {
    alert("Login field is empty!");
    return false;
  }
  if (password.length == 0) {
    alert("Password field is empty!");
    return false;
  }
  fetch("/json", {
    method: "post",
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      login: login,
      password: password
    })
  }).then(
    function(response) {
      if (response.status !== 200) {
        console.log('Looks like there was a problem. Status Code: ' + response.status);
        return;
      }

      // Examine the text in the response
      response.json().then(function(data) {
        //console.log(data);
        document.getElementById("login").value = ""
        document.getElementById("password").value = ""
        alert(JSON.stringify(data));
      });
    }
  ).catch(function(err) {
    console.log('Fetch Error :-S', err);
  });

}

</script>
</head>
<body>
<h1>Test Nim's Asynchronous Http Body Parser</h1>

<hr>

<h2>Test Form</h2>

<form action="/form" method="post">
  Input 1: <input type="text" name="testfield-1" value="Test 1"><br /><br />
  Input 2: <input type="text" name="testfield-2" value="Test 2"><br /><br />
  Input 3: <input type="text" name="testfield-3" value="Test 3"><br /><br />
  Test Text:<br /> 
  <textarea name="message" rows="10" cols="30">The cat was playing in the garden.</textarea><br /><br />
  <input type="submit">
</form>

<br /><hr>

<h2>Test Multipart Form</h2>

<form action="/multipart" method="post" enctype="multipart/form-data">
  File 1: <input type="file" name="testfile-1" accept="text/*"><br /><br />
  File 2: <input type="file" name="testfile-2" accept="text/*"><br /><br />
  File 3: <input type="file" name="testfile-3" accept="text/*"><br /><br />
  Input 1: <input type="text" name="testfield-1" value="Test"><br /><br />
  Input 2: <input type="text" name="testfield-2" value="Test"><br /><br />
  <input type="checkbox" name="remove_upload_dir" value="yes" checked> Remove Upload Directory<br /><br />
  <input type="submit">
</form>

<br /><hr>

<h2>Test Json</h2>
<div>
  Login: <input id="login" type="text" name="login" value=""><br /><br />
  Password: <input id="password" type="password" name="password" value=""><br /><br />
  <button onclick="test_json();">Go</button>
</div>

<br /><hr>

<h2>Test File Server</h2>
<div>
<img src="test.svg" /><br />
<a href="test.svg" target="_blank">Show Image</a>
</div>

<br />
</body>
</html>
"""

  let svgimg = """
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg
   xmlns:dc="http://purl.org/dc/elements/1.1/"
   xmlns:cc="http://creativecommons.org/ns#"
   xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
   xmlns:svg="http://www.w3.org/2000/svg"
   xmlns="http://www.w3.org/2000/svg"
   id="svg8"
   version="1.1"
   viewBox="0 0 75.812652 60.952541"
   height="60.952541mm"
   width="75.812653mm">
  <defs
     id="defs2" />
  <metadata
     id="metadata5">
    <rdf:RDF>
      <cc:Work
         rdf:about="">
        <dc:format>image/svg+xml</dc:format>
        <dc:type
           rdf:resource="http://purl.org/dc/dcmitype/StillImage" />
        <dc:title></dc:title>
      </cc:Work>
    </rdf:RDF>
  </metadata>
  <g
     transform="translate(-65.762965,-88.875519)"
     id="layer1">
    <path
       d="m 109.57175,123.70501 q 0,3.12539 -2.48046,8.40879 -2.1084,4.48965 -4.53926,7.71426 3.99355,-12.1791 3.99355,-14.60996 0,-0.74414 -0.19844,-1.11621 -0.44648,-0.79375 -3.69589,-1.71153 0.52089,1.0666 0.52089,1.98438 0,5.75469 -5.233784,14.08906 0.818554,-3.32383 1.612304,-6.67246 0.91777,-4.2168 0.91777,-6.69727 0,-1.86035 -0.471285,-2.55488 -0.42168,-0.62012 -2.232422,-1.56269 0.272851,1.5875 0.272851,3.47265 0,2.28203 -0.545703,4.46485 -0.545703,2.18281 -1.637109,4.19199 -1.537891,2.75332 -3.150195,2.75332 -1.63711,0 -3.175,-2.75332 -1.116211,-2.00918 -1.661914,-4.19199 -0.545704,-2.18282 -0.545704,-4.46485 0,-1.88515 0.248047,-3.47265 -1.810742,0.94257 -2.232422,1.56269 -0.471289,0.69453 -0.471289,2.55488 0,2.48047 0.917774,6.69727 0.818555,3.34863 1.612305,6.67246 -5.233789,-8.30957 -5.233789,-14.08906 0,-0.91778 0.545703,-1.98438 -3.274219,0.91778 -3.695899,1.71153 -0.223242,0.37207 -0.223242,1.11621 0,2.50527 4.018359,14.60996 -2.430859,-3.19981 -4.564062,-7.71426 -2.480469,-5.2834 -2.480469,-8.40879 0,-0.96738 0.347266,-1.41387 0.694531,-0.89296 12.203906,-3.86953 l 0.124023,-0.24804 q -5.010546,0.44648 -7.590234,0.44648 -1.661914,0 -2.033984,-0.22324 -0.917774,-0.5209 -0.917774,-4.61367 0,-8.28477 3.547071,-13.44414 -1.190625,8.25996 -1.190625,11.43496 0,3.79511 1.091406,4.63847 0.42168,0.32246 1.711523,0.32246 1.041797,0 2.083594,-0.14882 -1.513086,-1.48829 -1.513086,-3.89434 0,-8.43359 4.043164,-13.816211 -1.339453,7.391801 -1.339453,11.583791 0,4.71289 0.843359,5.25859 0.372071,0.24805 1.265039,0.24805 1.116211,0 2.877344,-0.29766 -2.108398,-1.21543 -2.108398,-4.31601 0,-1.71153 0.843359,-3.07578 0.992188,-1.61231 2.604492,-1.61231 1.612305,0 2.604492,1.5875 0.868164,1.38906 0.868164,3.10059 0,3.10058 -2.108398,4.31601 1.785937,0.29766 2.877344,0.29766 0.917773,0 1.289843,-0.24805 0.84336,-0.5457 0.84336,-5.25859 0,-4.14238 -1.364258,-11.583791 4.043166,5.382621 4.043166,13.816211 0,2.40605 -1.51309,3.89434 1.0418,0.14882 2.0836,0.14882 1.31464,0 1.71152,-0.32246 1.09141,-0.84336 1.09141,-4.63847 0,-3.1502 -1.16582,-11.43496 3.54707,5.18418 3.54707,13.44414 0,4.09277 -0.94258,4.61367 -0.34727,0.22324 -2.00918,0.22324 -2.57969,0 -7.615041,-0.44648 l 0.124023,0.24804 q 11.509378,2.97657 12.203908,3.86953 0.34726,0.44649 0.34726,1.41387 z"
       style="font-style:normal;font-variant:normal;font-weight:normal;font-stretch:normal;font-size:50.79999924px;line-height:6.61458302px;font-family:Webdings;-inkscape-font-specification:Webdings;letter-spacing:0px;word-spacing:0px;fill:#a40000;fill-opacity:1;stroke:none;stroke-width:0.26458332px;stroke-linecap:butt;stroke-linejoin:miter;stroke-opacity:1"
       id="path67" />
    <path
       d="m 118.46922,135.13065 q -2.032,0 -3.4544,-1.3716 -1.4224,-1.3716 -1.4224,-3.3528 0,-2.032 1.4224,-3.4036 1.4224,-1.4224 3.4544,-1.4224 2.032,0 3.4036,1.4224 1.4224,1.3716 1.4224,3.4036 0,1.9812 -1.4224,3.3528 -1.3716,1.3716 -3.4036,1.3716 z m 4.0132,-32.3596 v -2.7432 q 4.0132,0.5588 6.5532,3.3528 2.54,2.7432 2.54,6.604 0,4.2672 -2.9464,7.2644 -2.8956,2.9464 -7.7216,3.5052 -1.2192,0.1016 -1.524,0.3556 -0.254,0.254 -0.3048,1.27 0,0.8128 -0.3048,1.1684 -0.254,0.3556 -0.8636,0.3556 -0.6604,0 -1.016,-0.3556 -0.3556,-0.4064 -0.3556,-1.1176 v -8.7376 q 0,-0.7112 0.254,-0.8636 0.254,-0.1524 1.3208,-0.2032 2.6416,-0.1016 4.2672,-1.7272 1.6256,-1.6764 1.6256,-4.318 0,-1.3208 -0.3556,-2.1844 -0.3556,-0.9144 -1.1684,-1.5748 z m -2.1844,-2.844804 v 2.743204 q -0.7112,0.1016 -0.9652,0.3048 -0.254,0.2032 -0.254,0.7112 l 0.1524,0.6604 0.2032,0.6096 q 0.1016,0.3048 0.1524,0.6096 0.0508,0.254 0.0508,0.6096 0,1.6764 -1.27,2.8448 -1.2192,1.1176 -2.9972,1.1176 -1.8796,0 -3.2004,-1.2192 -1.27,-1.27 -1.27,-2.9972 0,-2.54 2.54,-4.2164 2.5908,-1.727204 6.2992,-1.727204 z"
       style="font-style:normal;font-variant:normal;font-weight:normal;font-stretch:normal;font-size:50.79999924px;line-height:6.61458302px;font-family:Army;-inkscape-font-specification:Army;letter-spacing:0px;word-spacing:0px;fill:#204a87;fill-opacity:1;stroke:none;stroke-width:0.26458332px;stroke-linecap:butt;stroke-linejoin:miter;stroke-opacity:1"
       id="path69" />
  </g>
</svg>
"""

  let resform = """<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<script>
</script>
</head>
<body>
<h2>Result:</h2>
$1
<br /><hr>
<button onclick="location.href='/';">Back</button>
</body>
</html>
"""

  if req.reqMethod == HttpPost:
    if req.url.path == "/multipart":
      try:
        let uploadDir = getTempDir() / $genOid()
  
        # the temporary system directory is the default 
        let httpbody = await newAsyncHttpBodyParser(req, uploadDirectory=uploadDir)
  
        var html = "Data:<br />"
        if httpbody.formdata.len > 0:
          html.add("<ul>")
          for k,v in httpbody.formdata:
            html.add("<li>$1 => $2</li>" % [k, v])
          html.add("</ul>")
  
        html.add("Files:<br />")
        if httpbody.formfiles.len > 0:
          html.add("<ul>")
          for k,f in httpbody.formfiles:
            html.add("<li>$1:</li>" % k)
            html.add("<ul>")
            html.add("<li>Filename: $1</li>" % httpbody.formfiles[k].filename)
            html.add("<li>Content-Type: $1</li>" % httpbody.formfiles[k].content_type)
            html.add("<li>File Size: $1</li>" % $httpbody.formfiles[k].filesize)
            html.add("</ul>")
          html.add("</ul>")
          html.add("Upload Directory: $1" % uploadDir)
          
          if httpbody.formdata.hasKey("remove_upload_dir") and httpbody.formdata["remove_upload_dir"] == "yes":
            removeDir(uploadDir)
            html.add(" (Removed)")

          await req.respond(Http200, resform % html)

      except HttpBodyParserError:
        await req.respond(Http422, "Multipart/data malformed request syntax")

    elif req.url.path == "/form":
      let httpbody = await newAsyncHttpBodyParser(req)
      var html = "Data:<br /><ul>"
      for k,v in httpbody.formdata:
        html.add("<li>$1 => $2</li>" % [k, v])
      html.add("</ul>")

      await req.respond(Http200, resform % html)

    elif req.url.path == "/json" and req.headers["Content-type"] == "application/json":
      let httpbody = await newAsyncHttpBodyParser(req)
      var msg: JsonNode
      if httpbody.data.len > 0:
        let jsonNode = parseJson(httpbody.data)
        msg = %* {"login": jsonNode["login"], "password": jsonNode["password"], "status": "ok" }
      else:
        msg = %* {"status": "not ok" }

      let headers = newHttpHeaders([("Content-Type","application/json")])
      await req.respond(Http200, $msg, headers)
    else:
      await req.respond(Http404, "Not Found")

  else:
    if req.url.path == "/":
      await req.respond(Http200, form)
    else:
      let my_static_dir = getTempDir() / "static"
      discard existsOrCreateDir(my_static_dir)
      let svgfilename = my_static_dir / "test.svg"
      let file = openAsync(svgfilename, fmWrite)
      await file.write(svgimg)
      file.close()

      # The parameter "staticDir" is optional.
      # The default is "static/public" directory
      # but the directory must exist to serve files.
      await req.fileserver(staticDir=my_static_dir)
      removeDir(my_static_dir)

var server = newAsyncHttpServer(maxBody=167772160)

echo "Server running in http://0.0.0.0:8080."

waitFor server.serve(Port(8080), handler)
