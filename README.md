# Enigma - HTTP Server
Experiment write in [Nim](https://nim-lang.org/) to handle the http POST request body.

## How to test?
Install nim and run this command (I just tested on Linux)

        $ git clone https://github.com/mrhdias/EnigmaHTTPServer
        $ cd EnigmaHTTPServer
        $ nim c -p:src -r server.nim
        
        # Run the tests (1 to 4):
        $ cd tests
        $ nim c -p:../src -r test1.nim

Open your browser and type in the URL http://127.0.0.1:8080

If you uploaded anything check the default temporary directory to see
the uploaded files.

This experiment aims to decode multipart/data, x-form-urlencoded and
ajax http post requests.

This experiment is based on Dominik Picheta Nim's
[asynchttpserver](https://github.com/nim-lang/Nim/blob/devel/lib/pure/asynchttpserver.nim/)
library that has been changed in some parts for the experiment run.

This is Work in Progress!

## Examples

### Read Raw Data From the Post Request Stream:

```nim
import asynchttpserver, asyncdispatch
import asynchttpbodyparser
import strutils

proc handler(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
<form action="/" method="post">
  Input Text: <input type="text" name="testfield" value="Test">
  <input type="submit">
</form>
<br>
Raw Data: $1
</body>
</html>
"""

  if req.reqMethod == HttpPost:
    if req.content_length > 0:
      # Read directly from the stream
      let data = await req.client.recv(req.content_length)
      if data.len == req.content_length:
        await req.complete(true)
        await req.respond(Http200, htmlpage % data)
      else:
        await req.complete(false)
        await req.respond(Http400, "Bad Request. Content-Length does not match actual.")
    else:
      await req.respond(Http400, "Bad Request. Content-Length is zero!")
  else:
    await req.respond(Http200, htmlpage % "No data!")

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
```

### Parse Post Request and Get the Name and Value Pair:

```nim
import asynchttpserver, asyncdispatch
import asynchttpbodyparser
import strutils

proc handler(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
<form action="/" method="post">
  Input Text 1: <input type="text" name="testfield-1" value="Test"><br>
  Input Text 2: <input type="text" name="testfield-2" value="Test"><br>
  <input type="submit">
</form>
<br>
$1
</body>
</html>
"""

  if req.reqMethod == HttpPost:
    let httpbody = await newAsyncBodyParser(req)
    var html = "Data:<br /><ul>"
    for k,v in httpbody.formdata:
      html.add("<li>$1 => $2</li>" % [k, v])
    html.add("</ul>")

    await req.respond(Http200, htmlpage % html)
  else:
    await req.respond(Http200, htmlpage % "No data!")

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
```

### Parse Multipart Post Requests (File Uploads):

```nim
import asynchttpserver, asyncdispatch
import asynchttpbodyparser
import os, strutils, oids

proc handler(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
<form action="/" method="post" enctype="multipart/form-data">
  File 1: <input type="file" name="testfile-1" accept="text/*"><br /><br />
  File 2: <input type="file" name="testfile-2" accept="text/*"><br /><br />
  Input 1: <input type="text" name="testfield-1" value="Test"><br /><br />
  Input 2: <input type="text" name="testfield-2" value="Test"><br /><br />
  <input type="checkbox" name="remove_upload_dir" value="yes" checked> Remove Upload Directory<br />
  <br />
  <input type="submit">
</form>
<br>
$1
</body>
</html>
"""

  if req.reqMethod == HttpPost:
    try:
      let uploadDir = getTempDir() / $genOid()

      # the temporary system directory is the default 
      let httpbody = await newAsyncBodyParser(req, uploadDirectory=uploadDir)

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

        if httpbody.formdata.hasKey("remove_upload_dir") and
            httpbody.formdata["remove_upload_dir"] == "yes":
          removeDir(uploadDir)
          html.add(" (Removed)")

      await req.respond(Http200, htmlpage % html)

    except HttpBodyParserError:
      await req.respond(Http422, "Multipart/data malformed request syntax")

  else:
    await req.respond(Http200, htmlpage % "No data!")

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
```

### Parse Json Ajax Request:

```nim
import asynchttpserver, asyncdispatch
import asynchttpbodyparser
import strutils, json

proc handler(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
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
  fetch("/", {
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
        document.getElementById("login").value = ""
        document.getElementById("password").value = ""
        document.getElementById("response").innerHTML = JSON.stringify(data)
      });
    }
  ).catch(function(err) {
    console.log('Fetch Error :-S', err);
  });

}
</script>
</head>
<body>
<div>
  Login: <input id="login" type="text" name="login" value=""><br /><br />
  Password: <input id="password" type="password" name="password" value=""><br /><br />
  <button onclick="test_json();">Go</button>
</div>
<br>
<div id="response"></div>
</body>
</html>
"""

  if req.reqMethod == HttpPost:
    if req.headers["Content-type"] == "application/json":
      let httpbody = await newAsyncBodyParser(req)
      var msg: JsonNode
      if httpbody.data.len > 0:
        let jsonNode = parseJson(httpbody.data)
        msg = %* {"login": jsonNode["login"], "password": jsonNode["password"], "status": "ok" }
      else:
        msg = %* {"status": "not ok" }

      let headers = newHttpHeaders([("Content-Type","application/json")])
      await req.respond(Http200, $msg, headers)
  else:
    await req.respond(Http200, htmlpage)

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
```

### Serving Static Files:

```nim
import asynchttpserver, asyncdispatch, asyncfile
import asynchttpfileserver
import os, strutils

proc handler(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
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
   viewBox="0 0 60 60"
   height="60mm"
   width="60mm">
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
     transform="translate(-65.59523,-77.666656)"
     id="layer1">
    <circle
       r="20"
       cy="107.66666"
       cx="95.59523"
       id="path10"
       style="opacity:1;fill:#204a87;fill-opacity:1;fill-rule:evenodd;
       stroke:none;stroke-width:0.26499999;stroke-linecap:round;
       stroke-linejoin:round;stroke-miterlimit:4;stroke-dasharray:
       none;stroke-dashoffset:0;stroke-opacity:1;paint-order:stroke fill markers" />
  </g>
</svg>
"""

  if req.reqMethod == HttpGet:
    if req.url.path == "/":
      await req.respond(Http200, htmlpage)
    else:
      let my_static_dir = getTempDir() / "static"
      discard existsOrCreateDir(my_static_dir)
      let svgfilename = my_static_dir / "test.svg"
      var file = openAsync(svgfilename, fmWrite)
      await file.write(svgimg)
      file.close()

      # The argument "staticDir" is optional.
      # The default is "static/public" directory
      # but the directory must exist to serve files.
      await req.fileserver(staticDir=my_static_dir)
      removeDir(my_static_dir)
  else:
    await req.respond(Http405, "Method Not Allowed")

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
```
