import ../asynchttpserver, asyncdispatch
import ../asynchttpbodyparser
import strutils, json

proc handler(req: Request) {.async.} =
  let htmlpage = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<script>
function test_json() {
  var login = document.getElementById("login").value;
  var password = document.getElementById("password").value;
  if (login.length == 0) {
    alert("Login field is empty!");
    return false;
  }
  if (password.length == 0) {
    alert("Password field is empty!");
    return false;
  }
  fetch("/", {
    method: "post",
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      login: login,
      password: password
    })
  }).then(
    function(response) {
      if (response.status !== 200) {
        console.log('Looks like there was a problem. Status Code: ' + response.status);
        return;
      }

      // Examine the text in the response
      response.json().then(function(data) {
        document.getElementById("response").innerHTML = JSON.stringify(data)
      });
    }
  ).catch(function(err) {
    console.log('Fetch Error :-S', err);
  });

}
</script>
</head>
<body>
<div>
  Login: <input id="login" type="text" name="login" value=""><br /><br />
  Password: <input id="password" type="password" name="password" value=""><br /><br />
  <button onclick="test_json();">Go</button>
</div>
<br>
<div id="response"></div>
</body>
</html>
"""

  if req.reqMethod == HttpPost:
    if req.headers["Content-type"] == "application/json":
      let httpbody = await parseBody(req)
      var msg: JsonNode
      if httpbody.data.len > 0:
        let jsonNode = parseJson(httpbody.data)
        msg = %* {"login": jsonNode["login"], "password": jsonNode["password"], "status": "ok" }
      else:
        msg = %* {"status": "not ok" }

      let headers = newHttpHeaders([("Content-Type","application/json")])
      await req.respond(Http200, $msg, headers)

  await req.respond(Http200, htmlpage)

var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
