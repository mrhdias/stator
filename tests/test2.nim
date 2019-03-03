import ../asynchttpserver, asyncdispatch
import ../asynchttpbodyparser
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

  await req.respond(Http200, htmlpage % "No data!")

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
