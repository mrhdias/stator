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
