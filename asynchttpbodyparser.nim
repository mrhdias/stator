#
#
#       Nim's Asynchronous Http Body Parser
#        (c) Copyright 2019 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncnet, asyncdispatch, asynchttpserver, asyncfile
import os, tables, strutils, unicode
export asyncnet, tables
import httpcore


type
  FileAttributes* = object
    filename*: string
    content_type*: string
    filesize*: BiggestInt

type
  AsyncHttpBodyParser* = object
    formdata*: Table[string, string]
    formfiles*: Table[string, FileAttributes]
    data*: string
    multipart*: bool

  HttpBodyParserError* = object of Exception


const chunkSize = 8*1024
# const debug: bool = true


# https://www.i18nqa.com/debug/utf8-debug.html
# https://www.utf8-chartable.de/unicode-utf8-table.pl?start=8192&number=128
# https://www.w3schools.com/tags/ref_urlencode.asp
const characterSet = {
    "%20": 0x0020, "%21": 0x0021, "%22": 0x0022, "%23": 0x0023, "%24": 0x0024, "%25": 0x0025, "%26": 0x0026, "%27": 0x0027, "%28": 0x0028, "%29": 0x0029,
    "%2A": 0x002A, "%2B": 0x002B, "%2C": 0x002C, "%2D": 0x002D, "%2E": 0x002E, "%2F": 0x002F,
    "%30": 0x0030, "%31": 0x0031, "%32": 0x0032, "%33": 0x0033, "%34": 0x0034, "%35": 0x0035, "%36": 0x0036, "%37": 0x0037, "%38": 0x0038, "%39": 0x0039,
    "%3A": 0x003A, "%3B": 0x003B, "%3C": 0x003C, "%3D": 0x003D, "%3E": 0x003E, "%3F": 0x003F,
    "%40": 0x0040, "%41": 0x0041, "%42": 0x0042, "%43": 0x0043, "%44": 0x0044, "%45": 0x0045, "%46": 0x0046, "%47": 0x0047, "%48": 0x0048, "%49": 0x0049,
    "%4A": 0x004A, "%4B": 0x004B, "%4C": 0x004C, "%4D": 0x004D, "%4E": 0x004E, "%4F": 0x004F,
    "%50": 0x0050, "%51": 0x0051, "%52": 0x0052, "%53": 0x0053, "%54": 0x0054, "%55": 0x0055, "%56": 0x0056, "%57": 0x0057, "%58": 0x0058, "%59": 0x0059,
    "%5A": 0x005A, "%5B": 0x005B, "%5C": 0x005C, "%5D": 0x005D, "%5E": 0x005E, "%4F": 0x004F,
    "%60": 0x0060, "%61": 0x0061, "%62": 0x0062, "%63": 0x0063, "%64": 0x0064, "%65": 0x0065, "%66": 0x0066, "%67": 0x0067, "%68": 0x0068, "%69": 0x0069,
    "%6A": 0x006A, "%6B": 0x006B, "%6C": 0x006C, "%6D": 0x006D, "%6E": 0x006E, "%6F": 0x006F,
    "%70": 0x0070, "%71": 0x0071, "%72": 0x0072, "%73": 0x0073, "%74": 0x0074, "%75": 0x0075, "%76": 0x0076, "%77": 0x0077, "%78": 0x0078, "%79": 0x0079,
    "%7A": 0x007A, "%7B": 0x007B, "%7C": 0x007C, "%7D": 0x007D, "%7E": 0x007E, "%7F": 0x007F,
    "%E2%82%AC": 0x20AC, "%E2%80%9A": 0x201A, "%C6%92": 0x0192, "%E2%80%9E": 0x201E, "%E2%80%A6": 0x2026, "%E2%80%A0": 0x2020, "%E2%80%A1": 0x2021, "%CB%86": 0x02C6, "%E2%80%B0": 0x2030,
    "%C5%A0": 0x0160, "%E2%80%B9": 0x2039, "%C5%92": 0x0152, "%C5%BD": 0x017D,    
    "%E2%80%98": 0x2018, "%E2%80%99": 0x2019, "%E2%80%9C": 0x201C, "%E2%80%9D": 0x201D, "%E2%80%A2": 0x2022, "%E2%80%93": 0x2013, "%E2%80%94": 0x2014, "%CB%9C": 0x02DC, "%E2%84%A2": 0x2122,
    "%C5%A1": 0x0161, "%E2%80%BA": 0x203A, "%C5%93": 0x0153, "%C5%BE": 0x017E, "%C5%B8": 0x0178,
    "%C2%A0": 0x00A0, "%C2%A1": 0x00A1, "%C2%A2": 0x00A2, "%C2%A3": 0x00A3, "%C2%A4": 0x00A4, "%C2%A5": 0x00A5, "%C2%A6": 0x00A6, "%C2%A7": 0x00A7,
    "%C2%A8": 0x00A8, "%C2%A9": 0x00A9, "%C2%AA": 0x00AA, "%C2%AB": 0x00AB, "%C2%AC": 0x00AC, "%C2%AD": 0x00AD, "%C2%AE": 0x00AE, "%C2%AF": 0x00AF,
    "%C2%B0": 0x00B0, "%C2%B1": 0x00B1, "%C2%B2": 0x00B2, "%C2%B3": 0x00B3, "%C2%B4": 0x00B4, "%C2%B5": 0x00B5, "%C2%B6": 0x00B6, "%C2%B7": 0x00B7,
    "%C2%B8": 0x00B8, "%C2%B9": 0x00B9, "%C2%BA": 0x00BA, "%C2%BB": 0x00BB, "%C2%BC": 0x00BC, "%C2%BD": 0x00BD, "%C2%BE": 0x00BE, "%C2%BF": 0x00BF,
    "%C3%80": 0x00C0, "%C3%81": 0x00C1, "%C3%82": 0x00C2, "%C3%83": 0x00C3, "%C3%84": 0x00C4, "%C3%85": 0x00C5, "%C3%86": 0x00C6, "%C3%87": 0x00C7,
    "%C3%88": 0x00C8, "%C3%89": 0x00C9, "%C3%8A": 0x00CA, "%C3%8B": 0x00CB, "%C3%8C": 0x00CC, "%C3%8D": 0x00CD, "%C3%8E": 0x00CE, "%C3%8F": 0x00CF,
    "%C3%90": 0x00D0, "%C3%91": 0x00D1, "%C3%92": 0x00D2, "%C3%93": 0x00D3, "%C3%94": 0x00D4, "%C3%95": 0x00D5, "%C3%96": 0x00D6, "%C3%97": 0x00D7,
    "%C3%98": 0x00D8, "%C3%99": 0x00D9, "%C3%9A": 0x00DA, "%C3%9B": 0x00DB, "%C3%9C": 0x00DC, "%C3%9D": 0x00DD, "%C3%9E": 0x00DE, "%C3%9F": 0x00DF,
    "%C3%A0": 0x00E0, "%C3%A1": 0x00E1, "%C3%A2": 0x00E2, "%C3%A3": 0x00E3, "%C3%A4": 0x00E4, "%C3%A5": 0x00E5, "%C3%A6": 0x00E6, "%C3%A7": 0x00E7,
    "%C3%A8": 0x00E8, "%C3%A9": 0x00E9, "%C3%AA": 0x00EA, "%C3%AB": 0x00EB, "%C3%AC": 0x00EC, "%C3%AD": 0x00ED, "%C3%AE": 0x00EE, "%C3%AF": 0x00EF,
    "%C3%B0": 0x00F0, "%C3%B1": 0x00F1, "%C3%B2": 0x00F2, "%C3%B3": 0x00F3, "%C3%B4": 0x00F4, "%C3%B5": 0x00F5, "%C3%B6": 0x00F6, "%C3%B7": 0x00F7,
    "%C3%B8": 0x00F8, "%C3%B9": 0x00F9, "%C3%BA": 0x00FA, "%C3%BB": 0x00FB, "%C3%BC": 0x00FC, "%C3%BD": 0x00FD, "%C3%BE": 0x00FE, "%C3%BF": 0x00FF
  }.toTable

proc decodeString(encoded: string): string = Rune(if characterSet.hasKey(encoded): characterSet[encoded] else: 0x0000).toUTF8


proc incCounterInFilename(filename: string): string =
  # " (1).txt"
  if not (filename.len > 4 and filename[filename.len-1] == ')'):
    return "$1 (1)" % filename

  var strnumber = ""
  var starter = false
  var i = -1
  for c in filename:
    i += 1

    if starter:
      if isDigit(c):
        strnumber.add(c)
        continue
      if c == ')' and i == filename.len-1:
        break
      strnumber = ""
      starter = false

    if i > 1 and filename[i-1] == ' ' and c == '(':
      starter = true
      continue

  let number: int = parseInt(strnumber)
  return if number > 0 and strnumber.len > 0: "$1 ($2)" % [filename[0 .. (filename.len - strnumber.len) - 1 - 3], intToStr(number + 1)] else: filename


proc testFilename(tmpdir: string, filename: var string): string =
  if filename.len == 0:
    filename = "unknown"

  var path = ""
  var count = 0;
  while true:
    path = tmpdir / filename
    if not fileExists(path):
      return path

    let filenameparts = filename.rsplit(".", maxsplit=1)
    filename = if filenameparts.len == 2: "$1.$2" % [incCounterInFilename(filenameparts[0]), filenameparts[1]] else: incCounterInFilename(filename)

  return path



proc processHeader(raw_headers: seq[string]): Future[(string, Table[string, string])] {.async.} =

  var
    formname = ""
    filename = ""
    content_type = ""

  for raw_header in raw_headers:
    let raw_header_parts = raw_header.split(": ", maxsplit=1)
    if raw_header_parts.len == 2:
      if raw_header_parts[0] == "Content-Disposition":
        let content_disposition_parts = raw_header_parts[1].split("; ")
        for content_disposition_part in content_disposition_parts:
          if content_disposition_part == "form-data": continue
          let pair = content_disposition_part.split("=", maxsplit=1)
          if pair.len == 2:
            let value = if pair[1][0] == '"' and pair[1][pair[1].len-1] == '"': pair[1][1 .. pair[1].len-2] else: pair[1]
            # echo ">> Pair: " & pair[0] & " = " & value
            if value.len > 0:
              if pair[0] == "name":
                formname = value
            if pair[0] == "filename":
              filename = value

      elif raw_header_parts[0] == "Content-Type":
        # echo ">> Raw Header: " & raw_header_parts[0] & " = " & raw_header_parts[1]
        content_type = raw_header_parts[1]

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
proc processRequestMultipartBody(req: Request, uploadDirectory: string): Future[AsyncHttpBodyParser] {.async.} =
  # echo ">> Begin Process Multipart Body"

  let boundary = "--$1" % req.headers["Content-type"][30 .. req.headers["Content-type"].len-1]
  # echo ">> Boundary: " & boundary
  if boundary.len < 3 or boundary.len > 72:
    await req.complete(false)
    raise newException(HttpBodyParserError, "Multipart/data malformed request syntax")


  var httpbody: AsyncHttpBodyParser
  httpbody.formdata = initTable[string, string]()
  httpbody.formfiles = initTable[string, FileAttributes]()
  httpbody.multipart = true

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
            if count_boundary_chars == boundary.len-1:
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
                if httpbody.formfiles.hasKey(formname) and httpbody.formfiles[formname].filename.len > 0:
                  await output.write(bag)
                elif httpbody.formdata.hasKey(formname):
                  httpbody.formdata[formname].add(bag)
                bag = ""

              if httpbody.formfiles.hasKey(formname) and httpbody.formfiles[formname].filename.len > 0:
                output.close()
                httpbody.formfiles[formname].filesize = getFileSize(uploadDirectory / httpbody.formfiles[formname].filename)

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
            if httpbody.formfiles.hasKey(formname) and httpbody.formfiles[formname].filename.len > 0:
              await output.write(bag)
            elif httpbody.formdata.hasKey(formname):
              httpbody.formdata[formname].add(bag)
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
                  var fileattr = initFileAttributes(form)
                  httpbody.formfiles.add(name, fileattr)
                  # test if the temporary directory exists
                  discard existsOrCreateDir(uploadDirectory)

                  if form.hasKey("content-type"):
                    httpbody.formfiles[formname].content_type = form["content-type"]

                  # test the filename
                  var filename = form["filename"]
                  if (let fullpath = testFilename(uploadDirectory, filename); fullpath.len) > 0:
                    httpbody.formfiles[formname].filename = filename
                    output = openAsync(fullpath, fmWrite)

                else:
                  httpbody.formdata.add(name, form["data"])
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
          if buffer[buffer.len - 2 .. buffer.len - 1] == "--":
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

  return httpbody


proc processRequestBody(req: Request): Future[AsyncHttpBodyParser] {.async.} =
  # echo ">> Begin Process Body"

  var httpbody: AsyncHttpBodyParser
  httpbody.formdata = initTable[string, string]()
  httpbody.multipart = false

  var remainder = req.content_length
  # echo ">> Remainder: " & $remainder

  var buffer = ""
  var name = ""
  var encodedchar = ""
  while remainder > 0:
    let data = await req.client.recv(if remainder < chunkSize: remainder else: chunkSize)

    remainder -= data.len
    for i in 0 .. data.len-1:
      # echo data[i]
      if name.len > 0 and data[i] == '&':
        # echo ">> End of the value found"
        httpbody.formdata.add(name, buffer)
        name = ""
        buffer = ""
        continue

      if data[i] == '=':
        # echo ">> End of the key found"
        name = buffer
        buffer = ""
        continue


      if encodedchar.len > 0:
        encodedchar.add(data[i])
        if encodedchar.len mod 3 == 0: # check the 3 and 3
          # echo ">> ENCODED CHAR: " & encodedchar
          let utf8char = decodeString(encodedchar)
          # echo ">> UTF8 CHAR: " & utf8char
          if utf8char != "\x00":
            buffer.add(utf8char)
            encodedchar = ""
            continue
        continue

      if data[i] == '%':
        encodedchar.add(data[i])
        continue


      if data[i] == '+':
        buffer.add(' ')
        continue

      buffer.add(data[i])

  if name.len > 0:
    httpbody.formdata.add(name, buffer)

  # echo "Request Body Remainder: " & $remainder

  await req.complete(if remainder == 0: true else: false)

  return httpbody



proc parseBody*(req: Request, uploadDirectory: string = getTempDir()): Future[AsyncHttpBodyParser] {.async.} =

  if req.headers.hasKey("Content-type"):
    if req.headers["Content-type"].len > 32 and req.headers["Content-type"][0 .. 29] == "multipart/form-data; boundary=":
      let httpbody = await processRequestMultipartBody(req, uploadDirectory)
      return httpbody

    if req.headers["Content-type"] == "application/x-www-form-urlencoded":
      let httpbody = await processRequestBody(req)
      return httpbody

  var httpbody: AsyncHttpBodyParser
  httpbody.data = await req.client.recv(req.content_length)
  let remainder = req.content_length - httpbody.data.len
  await req.complete(if remainder == 0: true else: false)
  return httpbody
