#
#
#          Nim's Simple Request Routing
#        (c) Copyright 2019 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import re

template via*(re_path: Regex, reqMethods: seq[string], code_to_execute: untyped): untyped =
  # echo "Regex"
  if $req.reqMethod in reqMethods and req.url.path =~ re_path:
    let captures {.inject.} = matches
    code_to_execute
    break routes


template via*(rule_path: string, reqMethods: seq[string], code_to_execute: untyped): untyped =
  # echo rule_path
  if $req.reqMethod in reqMethods and req.url.path == rule_path:
    code_to_execute
    break routes

template routes(body: untyped): untyped {.dirty.}=
  block routes:
    body
