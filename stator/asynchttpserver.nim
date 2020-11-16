#
#            Stator Async HTTP Server
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncdispatch, asyncnet, asyncfile
import os
import httpcore, uri
import tables
from strutils import `%`, split, cmpIgnoreCase, toUpperAscii, rfind, toHex
from parseutils import skipIgnoreCase, parseSaturatedNatural
import re
import json
from sequtils import toSeq, map
import mimetypes
from times import now, format

import asynchttpbodyparser

export httpcore except parseHeader
export asyncdispatch

const
  DEFAULT_PORT = 8080
  maxLine = 8*1024
  chunkSize = 8*1024
  hexLength = 6
  httpMethods = {
    "GET": HttpGet,
    "POST": HttpPost,
    "HEAD": HttpHead,
    "PUT": HttpPut,
    "DELETE": HttpDelete,
    "PATCH": HttpPatch,
    "OPTIONS": HttpOptions,
    "CONNECT": HttpConnect,
    "TRACE": HttpTrace}.toTable

type
  RouteAttributes = ref object
    pathPattern: string
    regexPattern: Regex
    callback: proc (request: Request): Future[void] {.closure, gcsafe.}

  Config* = object
    port*: int
    address*: string
    reuseAddr*: bool
    reusePort*: bool
    tmpUploadDir*: string ## Default temporary directory of the current user to save temporary files
    autoCleanTmpUploadDir*: bool ## The value true will cause the temporary files left after request processing to be removed.
    staticDir*: string ## To serve static files such as images, CSS files, and JavaScript files
    maxBody*: int ## The maximum content-length that will be read for the body.

  AsyncHttpServer* = ref object
    socket*: AsyncSocket
    allowedIps*: seq[string]
    routes: TableRef[
      HttpMethod,
      seq[RouteAttributes]
    ]
    config*: Config

  Response* = ref object
    headers*: HttpHeaders
    statusCode*: HttpCode
    chunked: bool

  Request* = object
    client*: AsyncSocket
    headers*: HttpHeaders
    reqMethod*: HttpMethod
    protocol*: tuple[orig: string, major, minor: int]
    hostname*: string    ## The hostname of the client that made the request.
    url*: Uri
    regexCaptures*: array[20, string]
    response*: Response
    body*: BodyData
    rawBody*: string

var mt {.threadvar.}: MimeDB
mt = newMimetypes()


proc stringifyHeaders(
  headers: HttpHeaders,
  statusCode: HttpCode,
  contentLength = -1): string =

  var payload = ""
  if not headers.hasKey("status"):
    payload.add("status: $1\c\L" % $statusCode)

  if not headers.hasKey("date"):
    # Fri, 13 Nov 2020 20:30:39 GMT
    let date = now().format("ddd, dd MMM yyyy HH:mm:ss")
    payload.add("date: $1 GMT\c\L" % $date)

  if not headers.hasKey("content-type"):
    payload.add("content-type: text/html; charset=utf-8\c\L")

  if headers.hasKey("content-length") and (contentLength == -1):
    headers.del("content-length")
  elif not headers.hasKey("content-length") and (contentLength > -1):
    payload.add("content-length: $1\c\L" % $contentLength)

  for name, value in headers.pairs:
    payload.add("$1: $2\c\L" % [name, value])

  # echo payload
  return payload


proc respond*(req: Request, content = ""): Future[void] =
  if req.response.chunked:
    raise newException(IOError, "500 Internal Server Error")

  let msg = if content.len == 0: $req.response.statusCode else: content
  result = req.client.send("HTTP/1.1 $1\c\L$2\c\L$3" % [
      $req.response.statusCode,
      req.response.headers.stringifyHeaders(req.response.statusCode, msg.len),
      msg
  ])

proc respond*(req: Request, json: JsonNode) {.async.} =
  let content = $json
  req.response.headers["content-type"] = "application/json"
  req.response.headers["content-length"] = $(content.len())

  await req.respond(content)

#
# Chunked resposne
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Transfer-Encoding
#
proc resp*(req: Request, payload: string) {.async.} =
  if not req.response.chunked:
    if not req.response.headers.hasKey("content-type"):
      req.response.headers["content-type"] = "text/html; charset=utf-8"

    req.response.headers["transfer-encoding"] = "chunked"
    req.response.chunked = true
    await req.client.send("HTTP/1.1 $1\c\L$2\c\L$3" % [
      $Http200,
      req.response.headers.stringifyHeaders(req.response.statusCode, -1),
      "$1\c\L$2\c\L" % [$payload.len.toHex(hexLength), payload]
    ])
    return

  await req.client.send("$1\c\L$2\c\L" % [$payload.len.toHex(hexLength), payload])


proc respondError(req: Request, status: HttpCode) {.async.} =
  req.response.headers["content-type"] = "text/plain; charset=utf-8"
  req.response.statusCode = status
  await req.respond()

proc sendStatus(client: AsyncSocket, status: string): Future[void] =
  client.send("HTTP/1.1 " & status & "\c\L\c\L")


#
# Begin File Server
#

proc sendFile*(req: Request, path: string): Future[void] {.async.} =
  if not fileExists(path):
    await req.respondError(Http404)
    return

  var extension = "unknown"
  if ((let p = path.rfind('.')); p > -1):
    extension = path[p+1 .. ^1]

  let file = openAsync(path, fmRead)

  let filesize = cast[int](getFileSize(file))

  if filesize > high(int):
    raise newException(ValueError, "The file size exceeds the integer maximum.")

  await req.client.send(
    "HTTP/1.1 200\c\Lcontent-type: $1\c\Lcontent-length: $2\c\L\c\L" % [
      mt.getMimetype(extension),
      $filesize
    ]
  )

  var remainder = filesize

  while remainder > 0:
    let data = await file.read(min(remainder, chunkSize))
    await req.client.send(data)
    remainder -= data.len

  file.close()

  if remainder > 0:
    raise newException(IOError, "The file has not been read until the end.")


proc fileServer(req: Request, staticDir=""): Future[void] {.async.} =
  var url_path = if req.url.path.len > 1 and req.url.path[0] == '/': req.url.path[1 .. ^1] else: "index.html"
  var path = staticDir / url_path

  if dirExists(path):
    path = path / "index.html"

  await req.sendFile(path)


#
# End File Server
#

proc skipEmptyLine(
  client: AsyncSocket,
  lineFut: FutureVar[string]): Future[bool] {.async.} =

  for i in 0..1:
    lineFut.mget().setLen(0)
    lineFut.clean()
    await client.recvLineInto(lineFut, maxLength = maxLine) # TODO: Timeouts.

    if lineFut.mget == "":
      return false

    if lineFut.mget.len > maxLine:
      raise newException(ValueError, "The length line header exceeds the maximum allowed.")

    if lineFut.mget != "\c\L":
      break

  return true


proc parseProtocol(protocol: string): tuple[orig: string, major, minor: int] =
  var i = protocol.skipIgnoreCase("HTTP/")
  if i != 5:
    raise newException(ValueError, "Invalid request protocol. Got: " & protocol)
  result.orig = protocol
  i.inc protocol.parseSaturatedNatural(result.major, i)
  i.inc # Skip .
  i.inc protocol.parseSaturatedNatural(result.minor, i)


proc firstLine(
  client: AsyncSocket,
  lineFut: FutureVar[string]
): Future[tuple[`method`: string, url: string, protocol: string]] {.async.} =

  # First line - GET /path HTTP/1.1
  result.`method` = ""
  result.url = ""
  result.protocol = ""

  let parts = lineFut.mget.split(' ')
  if parts.len == 3:
    result.`method` = parts[0]
    result.url = parts[1]
    result.protocol = parts[2]


proc parseHeaders(
  client: AsyncSocket,
  lineFut: FutureVar[string]): Future[HttpHeaders] {.async.} =

  result = newHttpHeaders()
  # Headers
  while true:
    lineFut.mget.setLen(0)
    lineFut.clean()
    await client.recvLineInto(lineFut, maxLength = maxLine)

    if lineFut.mget == "":
      return result

    if lineFut.mget.len > maxLine:
      raise newException(ValueError, "The length line header exceeds the maximum allowed.")

    if lineFut.mget == "\c\L": break
    let (key, value) = parseHeader(lineFut.mget)
    result[key] = value

    # Ensure the client isn't trying to DoS us.
    if result.len > headerLimit:
      raise newException(ResourceExhaustedError, "The number of headers exceeds the maximum allowed.")



proc processRequest(
  server: AsyncHttpServer,
  req: FutureVar[Request],
  client: AsyncSocket,
  address: string,
  lineFut: FutureVar[string]): Future[bool] {.async.} =


  # Alias `request` to `req.mget()` so we don't have to write `mget` everywhere.
  template request(): Request =
    req.mget()

  # GET /path HTTP/1.1
  # Header: val
  # \n
  # request.headers.clear()
  request.rawBody = ""
  request.hostname.shallowCopy(address)
  assert client != nil
  request.client = client

  request.response = new Response
  request.response.headers = newHttpHeaders()
  request.response.statusCode = Http200
  request.response.chunked = false

  # We should skip at least one empty line before the request
  # https://tools.ietf.org/html/rfc7230#section-3.5
  try:
    if not await client.skipEmptyLine(lineFut):
      client.close()
      return false
  except ValueError:
    await request.respondError(Http413)
    client.close()
    return false

  # First line - GET /path HTTP/1.1
  let line = await client.firstLine(lineFut)

  if line.`method` != "" and httpMethods.hasKey(line.`method`):
    request.reqMethod = httpMethods[line.`method`]
  else:
    asyncCheck request.respondError(Http400)
    return true # Retry processing of request

  try:
    request.url = initUri()
    parseUri(line.url, request.url)
  except ValueError:
    asyncCheck request.respondError(Http400)
    return true

  try:
    request.protocol = parseProtocol(line.protocol)
  except ValueError:
    asyncCheck request.respondError(Http400)
    return true

  # Headers
  try:
    request.headers = await client.parseHeaders(lineFut)
  except ValueError:
    await request.respondError(Http413)
    client.close()
    return false
  except ResourceExhaustedError:
    await client.sendStatus("400 Bad Request")
    client.close()
    return false

  if request.headers.len == 0:
    await client.sendStatus("400 Bad Request")
    client.close()
    return false

  if request.reqMethod == HttpPost:
    # Check for Expect header
    if request.headers.hasKey("Expect"):
      if "100-continue" in request.headers["Expect"]:
        await client.sendStatus("100 Continue")
      else:
        await client.sendStatus("417 Expectation Failed")


  # Read the body
  # - Check for Content-length header
  if request.headers.hasKey("Content-Length"):
    var contentLength = 0
    if parseSaturatedNatural(request.headers["Content-Length"], contentLength) == 0:
      request.response.statusCode = Http400
      await request.respond("Bad Request. Invalid Content-Length.")
      return true
    else:
      if contentLength > server.config.maxBody:
        await request.respondError(Http413)
        return false

      # request.rawBody = await client.recv(contentLength)
      # if request.rawBody.len != contentLength:
      #   request.response.statusCode = Http400
      #   await request.respond("Bad Request. Content-Length does not match actual.")
      #   return true

      let bodyParser = newAsyncHttpBodyParser(client, request.headers)
      request.body = await bodyParser.process()

  elif request.reqMethod == HttpPost:
    request.response.statusCode = Http411
    await request.respond("Content-Length required.")
    return true

  # Call the user's callback.
  # await callback(request)

  ### begin find routes ###

  proc routeCallback(
    routes: seq[RouteAttributes],
    documentUri: string): proc (request: Request): Future[void] {.closure, gcsafe.} =

    let pattern = if (documentUri.len > 1 and documentUri[^1] == '/'): documentUri[0 ..< ^1] else: documentUri
    for route in routes:
      if route.regexPattern != nil:
        if pattern =~ route.regexPattern:
          request.regexCaptures = matches
          return route.callback
      elif route.pathPattern != "":
        if route.pathPattern == pattern:
          return route.callback

    return nil

  if server.routes.hasKey(request.reqMethod) and
    (let callback = routeCallback(server.routes[request.reqMethod], request.url.path); callback) != nil:
    await callback(request)
    if request.response.chunked:
      let lengthZero = 0
      await request.client.send("$1\c\L\c\L" % lengthZero.toHex(hexLength))


    # Clear the temporary directory here if auto clean
    if request.reqMethod == HttpPost and
      server.config.autoCleanTmpUploadDir and
        (request.body.workingDir != "") and
          dirExists(request.body.workingDir) and
            request.body.workingDir != server.config.tmpUploadDir:
      echo "Remove Working Directory: ", request.body.workingDir
      removeDir(request.body.workingDir)


  else:
    # begin serve static files
    if (request.reqMethod == HttpGet) and
          (server.config.staticDir != "") and
            dirExists(server.config.staticDir):
      # echo "serve static file"
      try:
        await request.fileServer(server.config.staticDir)
      except OSError:
        await request.respondError(Http429)
    else:
      await request.respondError(Http404)


  if "upgrade" in request.headers.getOrDefault("connection"):
    return false

  # The request has been served, from this point on returning `true` means the
  # connection will not be closed and will be kept in the connection pool.

  # Persistent connections
  if (request.protocol == HttpVer11 and
      cmpIgnoreCase(request.headers.getOrDefault("connection"), "close") != 0) or
     (request.protocol == HttpVer10 and
      cmpIgnoreCase(request.headers.getOrDefault("connection"), "keep-alive") == 0):
    # In HTTP 1.1 we assume that connection is persistent. Unless connection
    # header states otherwise.
    # In HTTP 1.0 we assume that the connection should not be persistent.
    # Unless the connection header states otherwise.

    return true
  else:
    request.client.close()
    return false


proc processClient(
  server: AsyncHttpServer,
  client: AsyncSocket,
  address: string) {.async.} =

  var request = newFutureVar[Request]("asynchttpserver.processClient")
  var lineFut = newFutureVar[string]("asynchttpserver.processClient")
  lineFut.mget() = newStringOfCap(80)

  while not client.isClosed:
    let retry = await server.processRequest(request, client, address, lineFut)
    if not retry:
      break


#
# Begin Handle Methods
#

proc initRouteAttributes(
  pattern: string,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}): RouteAttributes = RouteAttributes(
  pathPattern: pattern,
  regexPattern: nil,
  callback: callback
)

proc initRouteAttributes(
  pattern: Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}): RouteAttributes = RouteAttributes(
  pathPattern: "",
  regexPattern: pattern,
  callback: callback
)


proc addRoute(
  server: AsyncHttpServer,
  methods: openArray[string],
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}) =

  for `method` in methods:
    if not httpMethods.hasKey(`method`):
      echo "Error: HTTP method \"$1\" not exists! skiped..." % `method`
      continue

    if not server.routes.hasKey(httpMethods[`method`]):
      server.routes[httpMethods[`method`]] = newSeq[RouteAttributes]()

    server.routes[httpMethods[`method`]].add(initRouteAttributes(pattern, callback))

proc get*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["GET"], pattern, callback)

proc post*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["POST"], pattern, callback)

proc put*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["PUT"], pattern, callback)

proc head*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["HEAD"], pattern, callback)

proc patch*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["PATCH"], pattern, callback)

proc delete*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["DELETE"], pattern, callback)

proc options*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["OPTIONS"], pattern, callback)

proc connect*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["CONNECT"], pattern, callback)

proc trace*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["TRACE"], pattern, callback)

proc any*(
  server: AsyncHttpServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(toSeq(httpMethods.keys), pattern, callback)

proc match*(
  server: AsyncHttpServer,
  methods: openArray[string],
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(methods.map(toUpperAscii), pattern, callback)

#
# End handle Methods
#


proc checkRemoteAddrs(server: AsyncHttpServer, client: AsyncSocket): bool =
  if server.allowedIps.len > 0:
    let (remote, _) = client.getPeerAddr()
    return remote in server.allowedIps
  return true


proc close*(server: AsyncHttpServer) =
  ## Terminates the async http server instance.
  server.socket.close()


proc serve*(server: AsyncHttpServer) {.async.} =
  ## Starts the process of listening for incoming TCP connections
  server.socket = newAsyncSocket()
  if server.config.reuseAddr:
    server.socket.setSockOpt(OptReuseAddr, true)
  if server.config.reusePort:
    server.socket.setSockOpt(OptReusePort, true)
  server.socket.bindAddr(Port(server.config.port), server.config.address)
  server.socket.listen()

  while true:
    try:
      var (address, client) = await server.socket.acceptAddr()
      if server.checkRemoteAddrs(client):
        asyncCheck server.processClient(client, address)
      else:
        client.close()
    except OSError as e:
      echo "Error: ", e.msg
      await sleepAsync(1000)


proc newAsyncHttpServer*(): AsyncHttpServer =
  ## Creates a new ``AsyncHttpServer`` instance.
  new result
  result.config.reuseAddr = true
  result.config.reusePort = true
  result.routes = newTable[HttpMethod, seq[RouteAttributes]]()

  result.config.port = DEFAULT_PORT
  result.config.address = ""
  result.config.tmpUploadDir = getTempDir()
  result.config.autoCleanTmpUploadDir = true
  result.config.staticDir = ""
  result.config.maxBody = 8388608 # 8MB = 8388608 Bytes


when not defined(testing) and isMainModule:
  proc main() =
    var server = newAsyncHttpServer()
    server.get("/", proc (req: Request) {.async.} =
      await req.respond("Hello World!")
    )
    asyncCheck server.serve()
    runForever()

  main()
