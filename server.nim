import asynchttpserver, asyncdispatch
import os, strutils, oids
import json
import asynchttpbodyparser

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

<br />
</body>
</html>
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
        html.add("Upload Directory: $1" % uploadDir)
        
      if httpbody.formdata.hasKey("remove_upload_dir") and httpbody.formdata["remove_upload_dir"] == "yes":
        removeDir(uploadDir)
        html.add(" (Removed)")

      await req.respond(Http200, resform % html)

    elif req.url.path == "/form":
      let httpbody = await parseBody(req)
      var html = "Data:<br /><ul>"
      for k,v in httpbody.formdata:
        html.add("<li>$1 => $2</li>" % [k, v])
      html.add("</ul>")

      await req.respond(Http200, resform % html)

    elif req.url.path == "/json" and req.headers["Content-type"] == "application/json":
      let httpbody = await parseBody(req)
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
    await req.respond(Http200, form)


var server = newAsyncHttpServer(maxBody=167772160)
waitFor server.serve(Port(8080), handler)
