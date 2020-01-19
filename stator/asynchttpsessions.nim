#
#           Nim's Async HTTP Sessions
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import asyncdispatch
import tables
import times
import oids
import strutils

type
  Session = ref object
    id*: string
    map*: TableRef[string, string]
    request_time: DateTime
    callback*: proc (id: string): Future[void]

type
  AsyncHttpSessions* = ref object of RootObj
    pool*: TableRef[string, Session]
    session_timeout: int
    sleep_time: int
    max_sessions*: int

proc sessions_manager(self: AsyncHttpSessions): Future[void] {.async.} =
  while true:
    await sleepAsync(self.sleep_time)

    if self.pool == nil:
      continue

    # echo "Number of active sessions: ", self.pool.len
    # echo "check for sessions timeout..."
    var to_del = newSeq[string]()
    for key, value in self.pool:
      if (now() - self.pool[key].request_time).inSeconds > self.session_timeout:
        # echo "session id timeout:", key
        to_del.add(key)

    for key in to_del:
      if self.pool[key].callback != nil:
        await self.pool[key].callback(key)
      # echo "the session will be deleted:", key
      self.pool.del(key)

proc set_session*(self: AsyncHttpSessions): Session =
  let session_id = genOid()

  return (self.pool[$session_id] = Session(
    id: $session_id,
    map: newTable[string, string](),
    request_time: now(),
    callback: nil
  ); self.pool[$session_id])

proc get_session*(self: AsyncHttpSessions, id: string): Session =
  (self.pool[id].request_time = now(); self.pool[id])

proc new_async_http_sessions*(
  sleep_time = 5000,
  session_timeout = 3600,
  max_sessions: int = 100): AsyncHttpSessions =

  ## Creates a new ``AsyncHttpSessions`` instance.
  new result
  result.sleep_time = sleep_time
  result.session_timeout = session_timeout
  result.pool = newTable[string, Session]()

  asyncCheck result.sessions_manager()
