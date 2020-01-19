import asyncdispatch
import stator/[asynchttpserver, asynchttpbodyparser, asynchttpsessions]
import cookies
import strutils, strformat
import strtabs

proc login_page(message: string): string =
  return &"""
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
<p>
  Test Sessions:<br />
  {message}
</p>
<form action="/login" method="post">
  Username: <input type="text" name="username" value="test"><br/>
  Password: <input type="password" name="password" value="12345678"><br/>
  <input type="submit" name="login" value="Login">
</form>
</body>
</html>
"""

proc user_page(message: string): string =
  return &"""
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
<form>
{message}<br />
<button onClick="document.location.href=/login">Reload!</button>
</form>
</body>
</html>
"""


proc cb(req: Request, sessions: AsyncHttpSessions) {.async.} =

  if req.url.path == "/login" and req.reqMethod == HttpPost and
    sessions.pool.len <= sessions.max_sessions:

    let httpbody = await newAsyncHttpBodyParser(req)
    if httpbody.formdata.hasKey("username") and httpbody.formdata["username"] == "test" and
      httpbody.formdata.hasKey("password") and httpbody.formdata["password"] == "12345678":

      proc timeout_session(id: string) {.async.} =
        echo "expired session:", id

      var session = sessions.set_session()
      session.map["username"] = httpbody.formdata["username"]
      session.map["password"] = httpbody.formdata["password"] 
      session.callback = timeout_session

      let headers = newHttpHeaders([("Set-Cookie", &"session={session.id}")])
      await req.respond(Http200, user_page(&"""Hello User {session.map["username"]}"""), headers)
    else:
      await req.respond(Http200, login_page("Please login"))

  else:
    var id = ""
    if req.headers.hasKey("Cookie"):
      let cookies = parseCookies(req.headers["Cookie"])
      if cookies.hasKey("session"):
        id = cookies["session"]

    if id == "":
      await req.respond(Http200, login_page("Please login"))
    else:
      if sessions.pool.hasKey(id):
        let session = sessions.get_session(id)
        await req.respond(Http200, user_page(&"""Hello User {session.map["username"]} Again :-)"""))
      else:
        await req.respond(Http200, login_page("Your session has expired please login again!"))

proc main() =
  let server = newAsyncHttpServer()
  let sessions = newAsyncHttpSessions(
    sleep_time=1000,
    session_timeout=30
  )

  waitFor server.serve(
    Port(8080),
    proc (req: Request): Future[void] = cb(req, sessions)
  )

main()
