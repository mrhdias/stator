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
