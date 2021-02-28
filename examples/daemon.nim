import stator
import stator/asyncsessions
import posix
import os
from cookies import parseCookies
from strutils import `%`
from strformat import `&`
import sugar
import cpuinfo

var pid: Pid

proc getSessionId(headers: HttpHeaders): string =
  if not headers.hasKey("cookie"):
    return ""

  let cookies = parseCookies(headers["cookie"])
  return if "session" in cookies: cookies["session"] else: ""


proc showSessionPage(
  req: Request,
  sessions: AsyncSessions) {.async.} =

  if not (req.headers.hasKey("connection") and req.headers["connection"] == "keep-alive"):
    req.response.statusCode = Http411
    await req.respond("Connectio keep-live required.")
    return

  let sessionId = req.headers.getSessionId()
  if sessionId != "" and (sessionId in sessions.pool):
    if (let session = sessions.getSession(sessionId); session) != nil:
      req.response.headers["content-type"] = "text/plain;charset=utf-8"
      await req.respond(&"""Hello User {session.map["username"]} Again :-) {sessionId}""")
      # sessions.delSession(sessionId)
    else:
      await req.respond("Session Error!")

    return

  proc timeoutSession(id: string) {.async.} =
    echo "expired session: ", id

  var session: Session
  try:
    session = sessions.setSession()
  except AsyncSessionsError as e:
    await req.respond(e.msg)
    return

  session.map["username"] = "Kiss"
  session.callback = timeoutSession

  req.response.headers["set-cookie"] = &"session={session.id}"
  await req.respond("New Session")



proc test(req: Request) {.async.} =
  await req.respond("Test!")


proc launchApp() =

  let sessions = newAsyncSessions(
    sleepTime = 1000, # milliseconds
    sessionTimeout = 30, # seconds
    maxSessions = 100
  )

  let app = newApp()
  app.config.port = 8080 # optional if default port
  app.config.reusePort = true
  app.get("/sessions", (req: Request) => showSessionPage(req, sessions))

  app.get("/", test)

  app.run()


proc processes(forks = 0) =

  var children: seq[Pid]

  for _ in 0 .. forks - 1:
    let pid = fork()
    if pid < 0:
      # error forking a child
      quit(QuitFailure)

    elif pid > 0:
      # In parent process
      children.add(pid)

    else:
      # In child process
      launchApp()
      quit(QuitSuccess)

  for child in children:
    var status: cint
    discard waitpid(child, status, 0)


proc daemonize() =

  let pidFile = "test.pid"
  var standIn, standOut, standErr: File

  pid = fork()

  if pid < 0:
    # error forking a child
    quit(QuitFailure)

  elif pid > 0:
    # In parent process

    if len(pidFile) > 0:
      echo "To stop the server: kill ", $pid
      echo "or kill $(cat test.pid)"
      writeFile(pidFile, $pid)

    quit(QuitSuccess)

  # In child process

  onSignal(SIGKILL, SIGINT, SIGTERM):
    echo "Exiting: ", sig
    discard kill(pid, SIGTERM)
    quit(QuitSuccess)

  # decouple from parent environment
  if chdir("/") < 0:
    quit(QuitFailure)

  discard umask(0) # don't inherit file creation perms from parent

  if setsid() < 0: # make it session leader
    quit(QuitFailure)

  signal(SIGCHLD, SIG_IGN)

  if not standIn.open("/dev/null", fmRead):
    quit(QuitFailure)
  if not standOut.open("/dev/null", fmAppend):
    quit(QuitFailure)
  if not standErr.open("/dev/null", fmAppend):
    quit(QuitFailure)

  if dup2(getFileHandle(standIn), getFileHandle(stdin)) < 0:
    quit(QuitFailure)
  if dup2(getFileHandle(standOut), getFileHandle(stdout)) < 0:
    quit(QuitFailure)
  if dup2(getFileHandle(standErr), getFileHandle(stderr)) < 0:
    quit(QuitFailure)

  # fork n x cpu processes
  var processors = countProcessors()
  if processors == 0:
    processors = 2
  processes(processors)


proc main() =
  daemonize()

main()
