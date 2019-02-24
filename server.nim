import asynchttpserver, asyncdispatch
import os, strutils
include formparser



proc handler(req: Request) {.async.} =
  var form = """<html>
<body>
<form action="/server" method="post" enctype="multipart/form-data">
  <input type="file" name="textfile1" accept="text/*"><br /><br>
  <input type="file" name="textfile2" accept="text/*"><br /><br>
  <input type="text" name="textfield" value="Test"><br /><br>
  <input type="submit">
</form>
</body>
</html>
"""
  if req.reqMethod == HttpPost:
    echo req.body
    # if req.cachedBody != "" and req.cachedBody.existsFile(destinationDirectory = "/var/tmp"):
    if req.cachedBody != "" and req.cachedBody.existsFile():
      let formData = await parseCachedBody(req)
      echo "---FORM DATA --"
      # echo formData["textfile1"]["filename"]
      echo formData
      if formData["textfile1"].hasKey("filename"):
        let path = getTempDir() / formData["textfile1"]["filename"]
        if fileExists(path):
          echo "File Size: " & $getFileSize(path)
        else:
          echo "File not exists!"

  await req.respond(Http200, form)

var server = newAsyncHttpServer(maxBody=167772160)
waitFor server.serve(Port(8080), handler)
