import ../asynchttpserver, asyncdispatch
import ../asynchttpbodyparser
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
