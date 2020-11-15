![Stator Logo](https://raw.githubusercontent.com/mrhdias/StatorHTTPServer/master/logo.png)

# Stator - HTTP Server
Experimental and very young HTTP Server write in [Nim](https://nim-lang.org/).

```nim
import stator
import re
from strutils import `%`

proc main() =
  let app = newApp()
  app.config.port = 8080 # optional if default port

  app.get("/", proc (req: Request) {.async.} =
    await req.respond("Hello World!")
  )

  app.get(r"/test/(\w+)".re, proc (req: Request) {.async.} =
    await req.respond("Hello $1!" % req.regexCaptures[0])
  )

  app.match(["GET", "POST"], "/which", proc (req: Request) {.async.} =
    await req.respond("Hello $1!" % $req.reqMethod)
  )

  app.get("/static", proc (req: Request) {.async.} =
    await req.sendFile("./test.txt")
  )

  app.run()

main()
```
If you are using Stator to generate dynamic content of significant size, such as large binary images or large text-based datasets, then you need to consider the use of "**resp**" function instead of "**respond**" to minimize the memory footprint and preserve scalability.

Using "**resp**" function allows Stator to return chunks of data back to the client without the need to build an entire structure, or resource in-memory. See [example](examples/loadimage.nim). You can use the "**resp**" function like the php "echo" function.
```nim
import stator
import tables
from strutils import `%`

proc showPage(req: Request) {.async.} =

  let t = {1: "one", 2: "two", 3: "three"}.toTable

  """<!DOCTYPE html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width">
      <title>Test</title>
    </head>
    <body>
      <table>""".resp

  for k, v in pairs(t):
    resp """<tr>
        <td><strong>$1</strong></td>
        <td>$2</td>
      </tr>
    """ % [$k, v]

  """</table>
    </body>
  </html>""".resp

proc main() =
  let app = newApp()
  app.get("/", showPage)
  app.run()

main()
```
