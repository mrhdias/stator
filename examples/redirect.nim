#
# nimble install https://github.com/mrhdias/StatorHTTPServer
# nim c -r redirect.nim
# http://example:8080/redirect
#
import ../stator

proc showPage(req: Request) {.async.} =

  req.response.headers["content-type"] = "text/html; charset=utf-8"
  req.response.headers["location"] = "http://www.example.org/"
  req.response.statusCode = Http301

  """<!DOCTYPE html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width">
      <title>Moved</title>
    </head>
    <body>
      <h1>Moved</h1>
      <p>This page has moved to <a href="http://www.example.org/">http://www.example.org/</a>.</p>
    </body>
  </html>""".respond

proc main() =
  let app = newApp()
  app.config.port = 8080 # optional if default port

  app.get("/redirect", showPage)

  app.run()

main()
