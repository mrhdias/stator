import asyncdispatch
import ../stator

var stop = false

proc shutdown(app: AsyncHttpServer) {.async.} =
  while true:
    if stop:
      app.close()
      echo "App test shutdown completed."
      quit(QuitSuccess)

    await sleepAsync(2000)
    echo "Start the app test shutdown ..."
    stop = true


proc main() =
  let app = newAsyncHttpServer()
  app.config.port = 8080 # optional if default port

  asyncCheck app.shutdown()

  app.get("/", proc (req: Request) {.async.} =
    await req.response("Hello World!")
  )

  app.run()

main()
