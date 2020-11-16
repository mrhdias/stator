#
#        Stator Web Application Framework
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import stator/asynchttpserver
import stator/asynchttpbodyparser
import json
from strutils import `%`

export asynchttpserver
export asynchttpbodyparser

template respond*(data: string | JsonNode) {.dirty.} =
  ## One time request response
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.respond(data: string | JsonNode)
  await req.respond(data)

template resp*(data: string) {.dirty.} =
  ## Breaks the response to the request into multiple parts
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.resp(data: string)
  await req.resp(data)

template sendFile*(filepath: string) {.dirty.} =
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.sendFile(filepath: string)
  await req.sendFile(filepath)

template formData*(): FormTableRef[string, string] =
  ## Object with the value of the fields from submitted html forms without files.
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   req.body.formdata
  req.body.formdata

template formFiles*(): FormTableRef[string, FileAttributes] =
  ## Object with the value of the input file fields from submitted html forms.
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   req.body.formfiles
  req.body.formfiles

proc run*(server: AsyncHttpServer) =
  echo "The Stator is rotating at http://$1:$2" % [
    if server.config.address == "": "0.0.0.0" else: server.config.address,
    $(server.config.port)
  ]
  asyncCheck server.serve()
  runForever()

proc newApp*(): AsyncHttpServer = newAsyncHttpServer()

when not defined(testing) and isMainModule:
  proc main() =
    let app = newApp()
    app.get("/", proc (req: Request) {.async.} =
      await req.respond("Hello World!")
    )
    app.run()
  main()
