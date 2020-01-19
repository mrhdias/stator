#
# Copyright (C) 2020 Henrique Dias
# MIT License - Look at LICENSE for details.
#
import macros
import re
import asyncdispatch
from strutils import `%`
import stator/[routes, asynchttpserver, asynchttpbodyparser, asynchttpserver, asynchttpsessions, asynchttpfileserver, basicauth]

export asyncdispatch
export re
export routes
export asynchttpserver
export asynchttpbodyparser
export asynchttpserver
export asynchttpsessions
export asynchttpfileserver
export basicauth

type
  Settings = object
    port: int
    maxBody: int

proc listenFor*(port: int = 8080, maxBody: int = 8388608): Settings =
  return Settings(port: port, maxBody: maxBody)

macro withStator*(args, body: untyped): untyped =
  if args.kind != nnkInfix or args.len != 3 or not eqIdent(args[0], "->"):
    error "'(value) -> (name)' expected in withStator, found: '$1'" % [args.repr]

  let varValue = args[1]
  let varName = args[2]

  template withStatorImpl(name, value, body) =
    let settings = value
    proc handler(name: Request) {.async gcsafe.} =
      body
    let server = newAsyncHttpServer(maxBody=settings.maxBody)
    waitFor server.serve(Port(settings.port), handler)

  getAst(withStatorImpl(varName, varValue, body))
  
