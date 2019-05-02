import asyncdispatch, asyncfile
import os, strutils
import enigma/[asynchttpserver, asynchttpfileserver]

proc handler(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
<div>
  <img src="test.svg" /><br />
  <a href="test.svg" target="_blank">Show Image</a>
</div>
<br />
</body>
</html>
"""

  let svgimg = """
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg
   xmlns:dc="http://purl.org/dc/elements/1.1/"
   xmlns:cc="http://creativecommons.org/ns#"
   xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
   xmlns:svg="http://www.w3.org/2000/svg"
   xmlns="http://www.w3.org/2000/svg"
   id="svg8"
   version="1.1"
   viewBox="0 0 60 60"
   height="60mm"
   width="60mm">
  <defs
     id="defs2" />
  <metadata
     id="metadata5">
    <rdf:RDF>
      <cc:Work
         rdf:about="">
        <dc:format>image/svg+xml</dc:format>
        <dc:type
           rdf:resource="http://purl.org/dc/dcmitype/StillImage" />
        <dc:title></dc:title>
      </cc:Work>
    </rdf:RDF>
  </metadata>
  <g
     transform="translate(-65.59523,-77.666656)"
     id="layer1">
    <circle
       r="20"
       cy="107.66666"
       cx="95.59523"
       id="path10"
       style="opacity:1;fill:#204a87;fill-opacity:1;fill-rule:evenodd;stroke:none;stroke-width:0.26499999;stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:4;stroke-dasharray:none;stroke-dashoffset:0;stroke-opacity:1;paint-order:stroke fill markers" />
  </g>
</svg>
"""

  if req.reqMethod == HttpGet:
    if req.url.path == "/":
      await req.respond(Http200, htmlpage)
    else:
      let my_static_dir = getTempDir() / "static"
      discard existsOrCreateDir(my_static_dir)
      let svgfilename = my_static_dir / "test.svg"
      var file = openAsync(svgfilename, fmWrite)
      await file.write(svgimg)
      file.close()

      # The argument "staticDir" is optional.
      # The default is "static/public" directory
      # but the directory must exist to serve files.
      await req.fileserver(staticDir=my_static_dir)
      removeDir(my_static_dir)
  else:
    await req.respond(Http405, "Method Not Allowed")

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
