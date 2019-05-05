import asyncdispatch
import strutils
import re
import stator/[asynchttpserver, routes, asynchttpfileserver]

proc home(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
Home Sweet Home...
<p>
Test Routes:
<ul>
<li><a href="method">Methods</a></li>
<li><a href="users/test">Regex Capture</a></li>
<li><a href="unknow">Unknow</a></li>
</ul>
</p>
</body>
</html>
"""

  await req.respond(Http200, htmlpage)


proc whichMethod(req: Request) {.async.} =
  await req.respond(Http200, "Method: $1" % $req.reqMethod)


proc testRegex(req: Request, user: string) {.async.} =
  if user == "test":
    await req.respond(Http200, "Result: \"$1\" user exist" % user)
  else:
    await req.respond(Http200, "Result: \"$1\" user not exist" % user)


proc handler(req: Request) {.async.} =

  block routes:

    via("/", @["GET"]):
      await req.home()

    via("/method", @["GET", "POST"]):
      await req.whichMethod()

    via(r"/users/(\w+)".re, @["GET"]):
      await req.testRegex(captures[0])

    via(r".+/([a-z]+\.[a-z]+)$".re, @["GET"]):
      await req.respond(Http404, "File \"$1\" not found!" % captures[0])

  # if unknow route
  await req.fileserver()

var server = newAsyncHttpServer(maxBody=10240)
waitFor server.serve(Port(8080), handler)
