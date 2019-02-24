import asyncdispatch, asyncfile
import os, strutils, oids
import tables


# HEADER: Content-Disposition: form-data; name="textfile2"; filename=""
# HEADER: Content-Type: application/octet-stream
# HEADER: Content-Disposition: form-data; name="textfield"


proc processHeader(raw_headers: seq[string]): Future[(string, Table[string, string])] {.async.} =
  echo "RAW HEADERS: " & raw_headers

  var formname = ""
  var filename = ""
  var content_type = ""
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
            echo pair[0] & " = " & value
            if value.len > 0:
              if pair[0] == "name":
                formname = value
            if pair[0] == "filename":
              filename = value

      elif raw_header_parts[0] == "Content-Type":
        echo raw_header_parts[0] & " = " & raw_header_parts[1]
        content_type = raw_header_parts[1]

  var formdata = initTable[string, string]()
  if filename.len > 0 or content_type.len > 0:
    formdata.add("filename", filename)
    formdata.add("content-type", content_type)
  else:
    formdata.add("data", "")

  return (formname, formdata)



# decode multipart body
proc parseCachedBody(req: Request, destinationDirectory: string = getTempDir()): Future[Table[string, Table[string, string]]] {.async.} =

  let fileSize = req.cachedBody.getFileSize()
  let fh = openAsync(req.cachedBody, fmRead)

  var formData = initTable[string, Table[string, string]]()
  block parser:
    let boundary = req.headers["content-type"][30 .. req.headers["content-type"].len-1]
    echo boundary
    const chunkSize = 8*1024

    var
      bag = ""
      buffer = ""
      
    var
      count_boundary_chars = 0
      count_dashes = 0

    var
      read_boundary = false
      read_headers = false
      read_header = false
      read_content = false

    var raw_headers = newSeq[string]()
    var formname = ""
    var output: AsyncFile
    
    while (let remainder = fileSize - fh.getFilePos(); remainder) > 0:
      let data = await fh.read(int(if remainder < chunkSize: remainder else: chunkSize))
    
      for i in 0 .. data.len-1:

        if read_content:
          # echo data[i]
          if read_boundary and data[i] == boundary[count_boundary_chars]:
            if count_boundary_chars == boundary.len-1:

              #--- begin if there are still characters in the bag ---
              if bag.len > 0:
                if formData[formname].hasKey("filename"):
                  await output.write(bag)
                else:
                  formData[formname]["data"].add(bag)
                bag = ""

              if formData[formname].hasKey("filename"):
                output.close()
              #--- end if there are still characters in the bag ---
              
              echo "INNER BOUNDARY FOUND"
              read_content = false
              read_header = false
              read_headers = true
              buffer = ""
              count_boundary_chars = 0
              continue
            buffer.add(data[i])
            count_boundary_chars += 1
            continue
          else:
            if count_dashes == 2:
              read_boundary = false
              count_dashes = 0
          count_boundary_chars = 0
            
          
          if read_boundary == false:
            if data[i] == '\c':
              buffer.add(data[i])
              continue
            if data[i] == '\L':
              buffer.add(data[i])
              continue
            if data[i] == '-':
              if count_dashes == 1:
                echo "INNER DASHES FOUND"
                read_boundary = true
                count_dashes = 2
                buffer.add(data[i])
                continue
              buffer.add(data[i])
              count_dashes = 1
              continue


          if buffer.len > 0:
            bag.add(buffer)
            buffer = ""
          bag.add(data[i])

          # --- begin empty bag if full ---
          if bag.len > chunkSize:
            if formData[formname].hasKey("filename"):
              await output.write(bag)
            else:
              formData[formname]["data"].add(bag)
            bag = ""
          # --- end empty bag if full ---
          
          continue



        if read_header:
          if data[i] == '\c': continue
          if data[i] == '\L':
            if buffer == "":
              read_header = false
              read_boundary = false
              read_content = true
              #--- begin process headers ---
              if raw_headers.len > 0:
                let (name, form) = await processHeader(raw_headers)
                formData.add(name, form)
                formname = name
                raw_headers.setLen(0)
                if form.hasKey("filename"):
                  # test if filename is empty
                  if form["filename"].len == 0:
                    formData[formname]["filename"] = "unknown"

                  #--- begin test if the file exists ---
                  var path = ""
                  while true:
                    path = destinationDirectory / formData[formname]["filename"]
                    if fileExists(path) == false:
                      break
                      
                    let filenameparts = formData[formname]["filename"].rsplit(".", maxsplit=1)
                    if filenameparts.len == 2:
                      formData[formname]["filename"] = join([join([filenameparts[0], $genOid()], "-"), filenameparts[1]], ".")
                    else:
                      formData[formname]["filename"] = join([formData[formname]["filename"], $genOid()], "-")
                  #--- end test if the file exists ---

                  output = openAsync(path, fmWrite)
              #--- end process headers ---
              continue
            # echo "HEADER: " & buffer
            raw_headers.add(buffer)
            buffer = ""
            bag = ""
            continue
          buffer.add(data[i])
          continue


        if read_headers:
          if data[i] == '-':
            if count_dashes == 1:
              echo "TAIL OF BOUNDARY FOUND"
              break parser
            count_dashes = 1
            continue
            
          if data[i] == '\c': continue
          if data[i] == '\L':
            read_header = true
            continue


        if read_boundary and data[i] == boundary[count_boundary_chars]:
          if count_boundary_chars == boundary.len-1:
            echo "HEAD BOUNDARY FOUND"
            read_headers = true
            count_boundary_chars = 0
            continue
          count_boundary_chars += 1
          continue
        count_boundary_chars = 0


        if read_boundary == false and data[i] == '-':
          if count_dashes == 1:
            echo "BEGIN DASHES FOUND"
            read_boundary = true
            count_dashes = 0
            continue
          count_dashes = 1
          continue
        count_dashes = 0


  fh.close()
  req.cachedBody.removeFile()
  

  return formData


