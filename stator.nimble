# Package

version       = "0.0.2"
author        = "Henrique Dias"
description   = "Stator - Web Application Framework"
license       = "MIT"

skipDirs = @["examples", "tests"]

# Dependencies

requires "nim >= 1.4.0"

task test, "Test AsyncHttpserver":
  exec "nim c -r -d:release -d:usestd tests/app.nim"
