# EnigmaHTTPServer
Experiment write in [Nim](https://nim-lang.org/) to decode a multipart/data from http request body.

## How to test?
Install nim and run this command (I just tested on Linux)

        nim c -r server.nim

Open your browser and type in the URL http://127.0.0.1:8080

Upload anything to test and see the result in the terminal.

Check the default temporary directory to see the uploaded files.
