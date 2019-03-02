# EnigmaHTTPServer
Experiment write in [Nim](https://nim-lang.org/) to handle the http POST request body.

## How to test?
Install nim and run this command (I just tested on Linux)

        $ git clone https://github.com/mrhdias/EnigmaHTTPServer
        $ cd EnigmaHTTPServer
        $ nim c -r server.nim
        
        # Run the tests (1 to 4):
        $ cd tests
        $ nim c -r test1.nim

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
    let httpbody = await parseBody(req)
    var html = "Data:<br /><ul>"
    for k,v in httpbody.formdata:
      html.add("<li>$1 => $2</li>" % [k, v])
    html.add("</ul>")

    await req.respond(Http200, htmlpage % html)

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
  <input type="submit">
</form>
<br>
$1
</body>
</html>
"""

  if req.reqMethod == HttpPost:
    let uploadDir = getTempDir() / $genOid()

    # the temporary system directory is the default 
    let httpbody = await parseBody(req, uploadDirectory=uploadDir)

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

    await req.respond(Http200, htmlpage % html)
    removeDir(uploadDir)

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
      let httpbody = await parseBody(req)
      var msg: JsonNode
      if httpbody.data.len > 0:
        let jsonNode = parseJson(httpbody.data)
        msg = %* {"login": jsonNode["login"], "password": jsonNode["password"], "status": "ok" }
      else:
        msg = %* {"status": "not ok" }

      let headers = newHttpHeaders([("Content-Type","application/json")])
      await req.respond(Http200, $msg, headers)

  await req.respond(Http200, htmlpage)

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
```
