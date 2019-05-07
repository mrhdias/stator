#
#
#         Nim's HTTP Basic Authentication
#        (c) Copyright 2019 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncdispatch, asynchttpserver
from strutils import splitWhitespace, startsWith, split, `%`
from base64 import decode

type
  Credentials = object
    username*: string
    password*: string

proc get_credentials*(req: Request): Credentials =
  if req.headers.hasKey("Authorization") and
      req.headers["Authorization"].len() > 10 and
      req.headers["Authorization"].startsWith("Basic "):

    let parts = req.headers["Authorization"].splitWhitespace(maxsplit=1)

    if parts.len() == 2 and parts[1].len() > 3:
      let credentials = decode(parts[1]).split(':', maxsplit=1)
      if credentials.len() == 2:
        return Credentials(username: credentials[0], password: credentials[1])

  return Credentials(username: "", password: "")


proc auth_required*(req: Request, realm: string = "") {.async.} =
  let htmlpage = """
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html>
<head><title>401 Unauthorized</title></head>
<body>
<h1>Unauthorized</h1>
<p>This server could not verify that you
are authorized to access the document
requested.  Either you supplied the wrong
credentials (e.g., bad password), or your
browser doesn't understand how to supply
the credentials required.</p>
</body>
</html>
"""
  let headers = newHttpHeaders([
    ("WWW-Authenticate", "Basic realm=\"$1\"" % realm),
    ("Content-Length", $(htmlpage.len()))
  ])
  await req.respond(Http401, htmlpage, headers)

