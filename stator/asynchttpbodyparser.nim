#
#
#       Nim's Asynchronous Http Body Parser
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncnet, asyncdispatch, asynchttpserver, asyncfile
import os, tables, strutils
export asyncnet, tables
import httpcore

type
  FileAttributes* = object
    filename*: string
    content_type*: string
    filesize*: BiggestInt

type
  AsyncHttpBodyParser* = ref object of RootObj
    formdata*: TableRef[string, string]
    formfiles*: TableRef[string, FileAttributes]
    data*: string
    multipart*: bool
    upload_directory: string

  HttpBodyParserError* = object of Exception


const chunkSize = 8*1024
# const debug: bool = true


proc splitInTwo(s: string, c: char): (string, string) =
  var p = find(s, c)
  if not (p > 0 and p < high(s)):
    return ("", "")

  let head = s[0 .. p-1]
  p += 1; while s[p] == ' ': p += 1
  return (head, s[p .. high(s)])


proc incCounterInFilename(filename: string): string =
  if filename.len == 0: return ""

  var p = filename.high
  if p > 0 and filename[p] == ')':
    var strnumber = ""
    while isDigit(filename[p-1]):
      strnumber = filename[p-1] & strnumber
      p -= 1

    if p > 1 and filename[p-1] == '(' and filename[p-2] == ' ':
      let number: int = parseInt(strnumber)
      if number > 0:
        return "$1 ($2)" % [filename[0 .. p - 3], intToStr(number + 1)]

  return "$1 (1)" % filename



proc testFilename(tmpdir: string, filename: var string): string =
  if filename.len == 0:
    filename = "unknown"

  var path = ""
  # var count = 0;
  while true:
    path = tmpdir / filename
    if not fileExists(path):
      return path

    let filenameparts = filename.rsplit(".", maxsplit=1)
    filename = if filenameparts.len == 2: "$1.$2" % [incCounterInFilename(filenameparts[0]), filenameparts[1]] else: incCounterInFilename(filename)

  return path



proc splitContentDisposition(s: string): (string, seq[string]) =
  var parts = newSeq[string]()

  var first_parameter = ""
  var buff = ""
  var p = 0
  while p < s.len:
    if s[p] == ';':
      if p > 0 and s[p-1] == '"':
        parts.add(buff)
        buff = ""

      if first_parameter.len == 0:
        if buff.len == 0: break
        first_parameter = buff
        buff = ""

      if buff == "":
        p += 1; while p < s.len and s[p] == ' ': p += 1
        continue
    buff.add(s[p])
    p += 1

  if buff.len > 0 and buff[high(buff)] == '"':
    parts.add(buff)

  return (first_parameter, parts)



#
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Disposition
#
proc processHeader(raw_headers: seq[string]): Future[(string, Table[string, string])] {.async.} =

  var
    formname = ""
    filename = ""
    content_type = ""

  for raw_header in raw_headers:
    # echo ">> Raw Header: " & raw_header
    let (h_head, h_tail) = splitInTwo(raw_header, ':')
    if h_head == "Content-Disposition":
      let (first_parameter, content_disposition_parts) = splitContentDisposition(h_tail)
      if first_parameter != "form-data": continue
      for content_disposition_part in content_disposition_parts:
        let pair = content_disposition_part.split("=", maxsplit=1)
        if pair.len == 2:
          let value = if pair[1][0] == '"' and pair[1][high(pair[1])] == '"': pair[1][1 .. pair[1].len-2] else: pair[1]
          # echo ">> Pair: " & pair[0] & " = " & value
          if value.len > 0:
            if pair[0] == "name":
              formname = value
          if pair[0] == "filename":
            filename = value

    elif h_head == "Content-Type":
      # echo ">> Raw Header: " & h_head & " = " & h_tail
      content_type = h_tail

  var formdata = initTable[string, string]()
  if filename.len > 0 or content_type.len > 0:
    formdata.add("filename", filename)
    formdata.add("content-type", content_type)
  else:
    formdata.add("data", "")

  # echo ">> Form Data: " & $formdata

  return (formname, formdata)

#
# https://tools.ietf.org/html/rfc7578
# https://tools.ietf.org/html/rfc2046#section-5.1
# https://www.w3.org/Protocols/rfc1341/7_2_Multipart.html
# https://httpstatuses.com/400
#

proc processRequestMultipartBody(self: AsyncHttpBodyParser, req: Request): Future[void] {.async.} =
  # echo ">> Begin Process Multipart Body"

  let boundary = "--$1" % req.headers["Content-type"][30 .. high(req.headers["Content-type"])]
  # echo ">> Boundary: " & boundary
  if boundary.len < 3 or boundary.len > 72:
    await req.complete(false)
    raise newException(HttpBodyParserError, "Multipart/data malformed request syntax")

  self.formdata = newTable[string, string]()
  self.formfiles = newTable[string, FileAttributes]()
  self.multipart = true

  proc initFileAttributes(form: Table[string, string]): FileAttributes =
    var attributes: FileAttributes
    attributes.filename = if form.hasKey("filename"): form["filename"] else: "unknown"
    attributes.content_type = if form.hasKey("content_type"): form["content_type"] else: ""
    attributes.filesize = 0

    return attributes

  var remainder = req.content_length
  block parser:

    var count_boundary_chars = 0

    var
      read_boundary = true
      find_headers = false
      read_header = false
      read_content = true

    var
      bag = ""
      buffer = ""

    var raw_headers = newSeq[string]()
    var formname = ""
    var output: AsyncFile

    while remainder > 0:
      let data = await req.client.recv(if remainder < chunkSize: remainder else: chunkSize)
      remainder -= data.len
      for i in 0 .. data.len-1:

        if read_content:
          # echo data[0]

          # echo ">> Find a Boundary: " & data[i]
          if read_boundary and data[i] == boundary[count_boundary_chars]:
            if count_boundary_chars == high(boundary):
              # echo ">> Boundary found"

              # begin the suffix of boundary before "\c\L--boundary"
              if bag.len > 1:
                bag.removeSuffix("\c\L")

              buffer.add(data[i])

              #--- begin if there are still characters in the bag ---
              # echo "Check the bag: " & buffer & " = " & boundary
              if ((let diff = buffer.len - boundary.len); diff) > 0:
                # echo ">> Diferrence: " & $diff
                bag.add(buffer[0 .. diff - 1])

              if bag.len > 0:
                # echo ">> Empty bag: " & bag & " => " & formname
                if self.formfiles.hasKey(formname) and self.formfiles[formname].filename.len > 0:
                  await output.write(bag)
                elif self.formdata.hasKey(formname):
                  self.formdata[formname].add(bag)
                bag = ""

              if self.formfiles.hasKey(formname) and self.formfiles[formname].filename.len > 0:
                output.close()
                self.formfiles[formname].filesize = getFileSize(self.upload_directory / self.formfiles[formname].filename)

              #--- end if there are still characters in the bag ---

              find_headers = true
              read_content = false
              read_header = false
              count_boundary_chars = 0
              continue

            # echo "On the right path to find the Boundary: " & data[i] & " = " & boundary[count_boundary_chars]
            buffer.add(data[i])
            count_boundary_chars += 1
            continue

          if buffer.len > 0:
            bag.add(buffer)
            buffer = ""

          # if not match teh boundary char add stream char to the bag
          bag.add(data[i])

          # --- begin empty bag if full ---
          if bag.len > chunkSize:
            # echo ">> Empty bag: " & bag
            if self.formfiles.hasKey(formname) and self.formfiles[formname].filename.len > 0:
              await output.write(bag)
            elif self.formdata.hasKey(formname):
              self.formdata[formname].add(bag)
            bag = ""
          # --- end empty bag if full ---

          count_boundary_chars = 0
          continue

        if read_header:
          if data[i] == '\c': continue
          if data[i] == '\L':
            if buffer.len == 0:
              read_header = false
              read_content = true
              # echo ">> Process headers"
              #--- begin process headers ---

              if raw_headers.len > 0:
                # echo ">> Raw Headers: " & $raw_headers
                let (name, form) = await processHeader(raw_headers)

                formname = name
                # echo ">> Form Name: " & formname
                #---begin check the type if is a filename or a data value
                if form.hasKey("filename"):
                  let fileattr = initFileAttributes(form)
                  self.formfiles.add(name, fileattr)
                  # test if the temporary directory exists
                  discard existsOrCreateDir(self.upload_directory)

                  if form.hasKey("content-type"):
                    self.formfiles[formname].content_type = form["content-type"]

                  # test the filename
                  var filename = form["filename"]
                  if (let fullpath = testFilename(self.upload_directory, filename); fullpath.len) > 0:
                    self.formfiles[formname].filename = filename
                    output = openAsync(fullpath, fmWrite)

                else:
                  self.formdata.add(name, form["data"])
                raw_headers.setLen(0)
                #-- end check the type if is a filename or a data value

              #--- end process headers ---
              continue

            # echo ">> Header Line: " & buffer
            raw_headers.add(buffer)
            buffer = ""
            bag = ""
            continue

          buffer.add(data[i])
          continue

        if find_headers:
          # echo ">> Find the tail of Boundary: " & buffer & " = " & buffer[buffer.len - 2 .. buffer.len - 1]
          if buffer[high(buffer) - 1 .. high(buffer)] == "--":
            # echo ">> Tail of Boundary found"
            buffer = ""
            break parser

          if data[i] == '-':
            buffer.add(data[i])
            continue
          if data[i] == '\c': continue
          if data[i] == '\L':
            read_header = true
            buffer = ""
            continue

        await req.complete(false)
        raise newException(HttpBodyParserError, "Multipart/data malformed request syntax")
 
  # echo ">> Multipart Body Request Remainder: " & $remainder

  await req.complete(if remainder == 0: true else: false)


proc processRequestBody(self: AsyncHttpBodyParser, req: Request): Future[void] {.async.} =
  # echo ">> Begin Process Request Body"

  self.formdata = newTable[string, string]()
  self.multipart = false

  var remainder = req.content_length
  # echo ">> Remainder: " & $remainder

  var buffer = ""
  var name = ""
  var encodedchar = ""
  while remainder > 0:
    let data = await req.client.recv(if remainder < chunkSize: remainder else: chunkSize)

    remainder -= data.len
    for i in 0 .. high(data):
      # echo data[i]
      if name.len > 0 and data[i] == '&':
        # echo ">> End of the value found"
        self.formdata.add(name, buffer)
        name = ""
        buffer = ""
        continue

      if data[i] == '=':
        # echo ">> End of the key found"
        name = buffer
        buffer = ""
        continue

      if encodedchar.len > 1:
        encodedchar.add(data[i])
        if (encodedchar.len - 1) mod 3 == 0: # check the 3 and 3
          # echo ">> ENCODED CHAR: " & encodedchar
          let decodedchar = chr(fromHex[int](encodedchar))
          # echo ">> DECODED CHAR: " & decodedchar
          if decodedchar != '\x00':
            buffer.add(decodedchar)
            encodedchar = ""
            continue
        continue

      if data[i] == '%':
        encodedchar.add("0x")
        continue

      if data[i] == '+':
        buffer.add(' ')
        continue

      buffer.add(data[i])

  if name.len > 0:
    self.formdata.add(name, buffer)

  # echo "Request Body Remainder: " & $remainder

  await req.complete(if remainder == 0: true else: false)

proc parseBody(self: AsyncHttpBodyParser, req: Request): Future[void] {.async.} =

  if req.headers.hasKey("Content-type"):
    if req.headers["Content-type"].len > 32 and req.headers["Content-type"][0 .. 29] == "multipart/form-data; boundary=":
      await self.processRequestMultipartBody(req)
      return

    if req.headers["Content-type"] == "application/x-www-form-urlencoded":
      await self.processRequestBody(req)
      return

  self.data = await req.client.recv(req.content_length)
  let remainder = req.content_length - self.data.len
  await req.complete(if remainder == 0: true else: false)

  return

proc newAsyncHttpBodyParser*(req: Request, uploadDirectory: string = getTempDir()): Future[AsyncHttpBodyParser] {.async.} =
  ## Creates a new ``AsyncHttpBodyParser`` instance.
  new result
  result.upload_directory = uploadDirectory

  await result.parseBody(req)
