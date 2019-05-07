import asyncdispatch
import stator/[asynchttpserver, basicauth]
from strutils import `%`
import tables

proc handler(req: Request) {.async.} =
  # print headers for debug
  # echo req.headers

  let users = {"guest": "0123456789", "mrhdias": "abcdef"}.toTable

  let c = req.getCredentials()
  if not (users.hasKey(c.username) and c.password == users[c.username]):
    await req.authRequired("My Server")
    return

  await req.respond(Http200, "Success $1!" % c.username)

let server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
