
#
#         Stator Async HTTP Body Parser
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncdispatch, asyncnet, asyncfile
import httpcore
import os
from strutils import `%`, isDigit, parseInt, intToStr,
  rsplit, split, startsWith, removeSuffix, fromHex
import formtable
import strtabs
import oids

export formtable

type
  FileAttributes* = object
    filename*: string
    content_type*: string
    filesize*: BiggestInt

  BodyData* = ref object
    formdata*: FormTableRef[string, string]
    formfiles*: FormTableRef[string, FileAttributes]
    data*: string
    multipart*: bool
    workingDir*: string

type
  AsyncHttpBodyParser* = ref object of RootObj
    client: AsyncSocket
    headers: HttpHeaders
    tmpUploadDir: string
    chunkSize: int

const debug = false


proc newBodyData(): BodyData =
  new result
  result.formdata = newFormTable[string, string]()
  result.formfiles = newFormTable[string, FileAttributes]()
  result.multipart = false
  result.data = ""


func `$`*(bd: BodyData): string {.inline.} =
  $(
    multipart: bd.multipart,
    formdata: bd.formdata,
    formfiles: bd.formfiles,
    data: bd.data,
    workingDir: bd.workingDir
  )


proc incCounterInFilename(filename: string): string =
  if filename == "":
    return ""

  var p = filename.high
  if p > 0 and filename[^1] == ')':
    var strnumber = ""
    while isDigit(filename[p-1]):
      strnumber = filename[p-1] & strnumber
      p -= 1

    if p > 1 and
      filename[p-1] == '(' and
      filename[p-2] == ' ' and
      (let number = parseInt(strnumber); number) > 0:
      return "$1 ($2)" % [filename[0 .. p - 3], intToStr(number + 1)]

  return "$1 (1)" % filename


proc uniqueFilename(workingDir, formFilename: string): string =

  var filename = formFilename
  while true:
    let fullpath = workingDir / filename
    if debug: echo "Fullpath: ", fullpath

    if not fileExists(fullpath):
      return filename

    let filenameparts = filename.rsplit(".", maxsplit=1)
    let newfilename = incCounterInFilename(filenameparts[0])
    filename = if filenameparts.len == 2: "$1.$2" % [newfilename, filenameparts[1]] else: "$1" % newfilename


proc parseFormData(formStr: string): StringTableRef =
  var
    buffer = ""
    key = ""
  var isFormData = false

  result = newStringTable()

  for c in formStr:
    if c == ' ' and buffer == "":
      continue

    if c == ';':
      let value = if buffer[0] == '"' and buffer[^1] == '"': buffer[1 .. ^2] else: buffer
      if key == "":
        if value == "form-data":
          isFormData = true
      else:
        result[key] = value
      key = ""
      buffer = ""
      continue

    if c == '=':
      key = buffer
      buffer = ""
      continue

    buffer.add(c)

  let value = if buffer[0] == '"': buffer[1 .. ^2] else: buffer
  if key == "":
    if value == "form-data":
      isFormData = true
  else:
    result[key] = value

  if not isFormData:
    raise newException(ValueError, "Multipart/data malformed request syntax")


proc assignToFile(
  formfiles: FormTableRef[string, FileAttributes],
  currentFormData,
  contentType,
  formFilename,
  workingDir: string): AsyncFile =

  let filename = uniqueFilename(workingDir, formFilename)

  var fileattr: FileAttributes
  fileattr.filename = filename
  fileattr.content_type = contentType
  fileattr.filesize = 0

  if currentFormData notin formfiles:
    formfiles[currentFormData] = newSeq[FileAttributes]()
  formfiles[currentFormData] = fileattr

  discard existsOrCreateDir(workingDir)

  let fullpath = workingDir / filename
  if debug: echo "Fullpath: ", fullpath

  result = openAsync(fullpath, fmWrite)


proc getBoundary(contentType: string): string =
  let parts = contentType.split(';')
  if parts.len == 2 and parts[0] == "multipart/form-data":
    let idx = if parts[1][0] == ' ': 1 else: 0
    if parts[1][idx .. ^1].startsWith("boundary="):
      let boundary = parts[1][(idx + 9) .. ^1]
      return "--$1" % boundary
  return ""


proc multipartFormData(self: AsyncHttpBodyParser, bd: BodyData) {.async.} =
  let boundary = getBoundary(self.headers["content-type"])
  if debug: echo "Boundary: ", boundary
  if boundary == "":
    raise newException(ValueError, "Multipart/data malformed request syntax")

  type
    parseSection = enum
      parseContent = 1, parseHeaders = 2, findTerminus = 3
  # Parse Section
  # 1: Read content
  # 2: Read headers
  # 3: Find Terminus - Search for the string "\c\L" to read the headers or
  #    Search for the string "--" which is after the end of boundary to finish.
  var section = ord(parseContent)
  
  var countBoundaryChars = 0

  var
    buffer = ""
    bag = ""

  var
    pc = '\0'
    tc = '\0'
  
  var headers = newHttpHeaders()
  var currentFormData = ""
  var output: AsyncFile
  
  template flushData() {.dirty.} =
    # flush data
    if bd.formfiles.hasKey(currentFormData):
      await output.write(bag)
      bag = ""
    elif bd.formdata.hasKey(currentFormData):
      bd.formdata[currentFormData] = bag # add values to sequence
      bag = ""


  var remainder = self.headers["Content-Length"].parseInt
  while remainder > 0:
    let readSize = min(remainder, self.chunkSize)
    let data = await self.client.recv(readSize)
    remainder -= readSize

    for c in data:
      pc = tc
      tc = c

      # echo "char: ", c
      if section == ord(parseContent):
 
        if c == boundary[countBoundaryChars]:
          if countBoundaryChars == high(boundary):
            if debug: echo "Boundary Found: ", boundary
            # echo "dubug: bag: >", bag, "< baglen: ", bag.len, " lastchar: >", c, "< buffer: >", buffer, "<"

            buffer.add(c)

            if ((let diff = buffer.len - boundary.len); diff) > 0:
              bag.add(buffer[0 .. diff - 1])

            # Empty the bag if it has data.
            if bag.len > 0:
              if bag.len > 1:
                bag.removeSuffix("\c\L")

              flushData()

            if bd.formfiles.hasKey(currentFormData):
              output.close()
              # looking inside the sequence files for the last insertion
              bd.formfiles[currentFormData, ^1].filesize = getFileSize(bd.workingDir / bd.formfiles[currentFormData, ^1].filename)

            # Next move: goto 3 and 4
            # Find the beginning of the headers or the boundary ending string "--" to finish.
            section = ord(findTerminus)
            countBoundaryChars = 0
            continue

          buffer.add(c)
          countBoundaryChars += 1
          continue

        if buffer.len > 0:
          bag.add(buffer)
          buffer = ""

        bag.add(c)
 
        # Empty the bag if it is full
        if bag.len > self.chunkSize:
          flushData()

        countBoundaryChars = 0
        continue

      #
      # 2. Read the headers until the "\c\L\c\L" string is found
      #
      if section == ord(parseHeaders):

        if c == '\c':
          continue

        if pc == '\c' and c == '\L':
          if buffer.len == 0: # if it is a double newline "\c\L\c\L" separator
            section = ord(parseContent)
            # Next move: goto 1
            # Read the contents

            if headers.len > 0:
              if debug: echo "Headers: ", $headers
              if headers.hasKey("Content-Disposition"):
                let form = parseFormData(headers["Content-Disposition"])
                currentFormData = form["name"]

                if form.hasKey("filename"):
                  # file
                  if debug: echo "File: ", $form
                  
                  output = bd.formfiles.assignToFile(
                    currentFormData,
                    if headers.hasKey("Content-Type"): $headers["Content-Type"] else: "",
                    if form.hasKey("filename") and form["filename"] != "": form["filename"] else: "unknown",
                    bd.workingDir
                  )

                else:
                  # data
                  if debug: echo "Data: ", $form
                  # check if form["data"] is always empty
                  if currentFormData notin bd.formdata:
                    bd.formdata[currentFormData] = newSeq[string]()

              headers.clear()
              continue

          let (key, value) = parseHeader(buffer)
          headers[key] = value

          buffer = ""
          bag = ""
          continue

        buffer.add(c)
        continue

      #
      # 3. Search for the string "--" which is after the end of boundary to finish.
      #
      if pc == '-' and c == '-':
        # buffer = "" # xxxxxxxx necessary?
        break

      #
      # 4. Search for the string "\c\L" to read the headers.
      #
      if c == '-':
        buffer.add(c)
      elif pc == '\c' and c == '\L':
        section = ord(parseHeaders)
        buffer = ""
        # Next move: goto 2
        # Read headers

      # echo "Multipart/data malformed request syntax"


proc formUrlencoded(self: AsyncHttpBodyParser, bd: BodyData) {.async.} =
  var remainder = self.headers["Content-Length"].parseInt

  var
    name = ""
    buffer = ""
    encodedchar = ""

  while remainder > 0:
    let readSize = min(remainder, self.chunkSize)
    let data = await self.client.recv(readSize)
    remainder -= readSize

    for c in data:
      if name != "" and c == '&':
        bd.formdata[name] = buffer
        name = ""
        buffer = ""
        continue

      if c == '=':
        name = buffer
        buffer = ""
        continue

      if encodedchar.len > 1:
        encodedchar.add(c)
        if (encodedchar.len - 1) mod 3 == 0: # checks every 3
          let decodedchar = chr(fromHex[int](encodedchar))
          if decodedchar != '\x00':
            buffer.add(decodedchar)
            encodedchar = ""
            continue
        continue

      if c == '%':
        encodedchar.add("0x")
        continue

      if c == '+':
        buffer.add(' ')
        continue

      buffer.add(c)

  if name != "":
    bd.formdata[name] = buffer



proc process*(self: AsyncHttpBodyParser): Future[BodyData] {.async.} =
  if self.headers["Content-Length"].parseInt == 0:
    raise newException(ValueError, "Invalid Content-Length.")

  if not dirExists(self.tmpUploadDir):
    raise newException(OSError, "Working $1 directory not found!" % self.tmpUploadDir)

  if not self.headers.hasKey("Content-Type"):
    raise newException(ValueError, "No Content-Type.")

  if debug: echo "Process Body"

  result = newBodyData()
  result.multipart = false
  result.workingDir = ""

  if self.headers["Content-Type"].len > 20 and
    self.headers["Content-Type"][0 .. 19] == "multipart/form-data;":
    if debug: echo "Multipart Form Data"
    result.multipart = true
    result.workingDir = self.tmpUploadDir / $genOid()

    await self.multipartFormData(result)

  elif self.headers["Content-Type"] == "application/x-www-form-urlencoded":
    if debug: echo "WWW Form Urlencoded"

    await self.formUrlencoded(result)

  else:
    let contentLength = self.headers["Content-Length"].parseInt
    result.data = await self.client.recv(contentLength)



proc newAsyncHttpBodyParser*(
  client: AsyncSocket,
  reqHeaders: HttpHeaders,
  tmpUploadDir: string = getTempDir(),
  chunkSize = 8*1024
): AsyncHttpBodyParser =

  ## Creates a new ``AsyncHttpBodyParser`` instance.

  new result
  result.client = client
  result.headers = reqHeaders
  result.tmpUploadDir = tmpUploadDir
  result.chunkSize = chunkSize
