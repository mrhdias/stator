#
#
#       Nim's Asynchronous Http Fileserver
#        (c) Copyright 2019 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncnet, asynchttpserver, asyncdispatch, asyncfile
import os, ospaths
import strutils
import tables


type
  FileserverError* = object of Exception


# https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Complete_list_of_MIME_types
const mime_types = {
  "bz":     "application/x-bzip",
  "bz2":    "application/x-bzip2",
  "css":    "text/css",
  "doc":    "application/msword",
  "docx":   "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "eot":    "application/vnd.ms-fontobject",
  "gif":    "image/gif",
  "gz":     "application/gzip",
  "htm":    "text/html",
  "html":   "text/html",
  "ico":    "image/vnd.microsoft.icon",
  "jpeg":   "image/jpeg",
  "jpg":    "image/jpeg",
  "js":     "text/javascript",
  "json":   "application/json",
  "odp":    "application/vnd.oasis.opendocument.presentation",
  "ods":    "application/vnd.oasis.opendocument.spreadsheet",
  "odt":    "application/vnd.oasis.opendocument.text",
  "otf":    "font/otf",
  "png":    "image/png",
  "pdf":    "application/pdf",
  "ppt":    "application/vnd.ms-powerpoint",
  "pptx":   "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "rar":    "application/x-rar-compressed",
  "rtf":    "application/rtf",
  "svg":    "image/svg+xml",
  "tar":    "application/x-tar",
  "tgz":    "application/tar+gzip",
  "ttf":    "font/ttf",
  "txt":    "text/plain",
  "woff":   "font/woff",
  "woff2":  "font/woff2",
  "xhtml":  "application/xhtml+xml",
  "xls":    "application/vnd.ms-excel",
  "xlsx":   "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "xul":    "application/vnd.mozilla.xul+xml",
  "xml":    "text/xml",
  "webapp": "application/x-web-app-manifest+json",
  "zip":    "application/zip"
}.toTable



proc send_file(req: Request, filepath: string, headers: HttpHeaders = nil): Future[string] {.async.} =

  let filesize = cast[int](getFileSize(filepath))
  if filesize == 0:
    return "The size of file is zero."

  if filesize > high(int):
    return "The file size exceeds the integer maximum."
      
  const chunkSize = 8*1024
  var msg = "HTTP/1.1 200\c\L"

  if headers != nil:
    for k, v in headers:
      msg.add("$1: $2\c\L" % [k,v])

  msg.add("Content-Length: ")

  msg.add $filesize
  msg.add "\c\L\c\L"

  var remainder = filesize
  var file = openAsync(filepath, fmRead)
  await req.client.send(msg)

  while remainder > 0:
    let data = await file.read(if remainder < chunkSize: remainder else: chunkSize)
    remainder -= data.len
    await req.client.send(data)
  file.close()

  return if remainder > 0: "The file has not been read until the end." else: ""



proc fileserver*(req: Request, static_dir="static" / "public"): Future[void] {.async.} =
  var url_path = req.url.path
  if ((let p = url_path.find('?')); p > -1):
    url_path = url_path[0 .. p-1]

  url_path = if url_path.len > 1 and url_path[0] == '/': url_path[1 .. url_path.high] else: "index.html"
  var path = static_dir / url_path

  if existsDir(path):
    path = path / "index.html"

  if not existsFile(path):
    await req.respond(Http404, "File not found!")
    return
    
  var extension = "unknown"
  if ((let p = path.rfind('.')); p > -1):
    extension = path[p+1 .. path.high]

  let headers = newHttpHeaders([("Content-Type", if mime_types.hasKey(extension): mime_types[extension] else: "application/octet-stream")])
  let res = await req.send_file(path, headers)
  if res != "":
    await req.respond(Http404, res)
    return



