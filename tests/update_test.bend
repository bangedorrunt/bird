import Base
import ../src/update.bend as U
import ../src/domain.bend as D
import ../src/json.bend as J

# End-to-end check of the fold. No network, no filesystem: a run is scripted by
# handing `Update.step` the messages the interpreter would deliver, in order, and
# the assertions are about what came out -- which command was asked for, what
# happens to the run when it lands, and what the manifest looks like afterwards.
#
# This is where the two things that are easy to get wrong are pinned: a run that
# named a config file must read it (and a run that named none must read nothing,
# or the interpreter waits forever), and a fixture must answer through exactly
# the same path a real response takes.
#
#   bend tests/update_test.bend

def ok_on(passed: Bool, +name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

# ── reading a step back ─────────────────────────────────────────────────

def model_of(+s: D.Step) -> D.Model:
  match s:
    case D.Step{model, cmds}:
      model

def cmds_of(+s: D.Step) -> List<&2, D.Cmd>:
  match s:
    case D.Step{model, cmds}:
      cmds

def phase_tag_on(+p: D.Phase) -> String:
  match p:
    case D.PhaseInit{}:
      "init"
    case D.PhaseGather{}:
      "gather"
    case D.PhaseRequest{id}:
      "request"
    case D.PhaseMedia{jobs, done}:
      "media"
    case D.PhaseDone{}:
      "done"
    case D.PhaseFailed{error}:
      "failed"

def phase_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      phase_tag_on(phase)

def phase_tag(+s: D.Step) -> String:
  phase_of(model_of(s))

def err_id(+e: D.Error) -> String:
  match e:
    case D.Error{code, message, hint}:
      D.ErrCode.id(code)

def code_of_phase(+p: D.Phase) -> String:
  match p:
    case D.PhaseFailed{error}:
      err_id(error)
    case _:
      SNil{}

def failed_code_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      code_of_phase(phase)

def failed_code(+s: D.Step) -> String:
  failed_code_of(model_of(s))

def message_of_phase(+p: D.Phase) -> String:
  match p:
    case D.PhaseFailed{error}:
      match error:
        case D.Error{code, message, hint}:
          message
    case _:
      SNil{}

def hint_of_phase(+p: D.Phase) -> String:
  match p:
    case D.PhaseFailed{error}:
      match error:
        case D.Error{code, message, hint}:
          hint
    case _:
      SNil{}

def failed_hint_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      hint_of_phase(phase)

def failed_hint(+s: D.Step) -> String:
  failed_hint_of(model_of(s))

def failed_message_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      message_of_phase(phase)

def failed_message(+s: D.Step) -> String:
  failed_message_of(model_of(s))

def payload_of(+m: D.Model) -> J.Json:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      payload

def body_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      body

def status_of(+m: D.Model) -> U32:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      status

def exit_of(+m: D.Model) -> U32:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      exit_code

def notes_text_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      String.join(notes, "|")

def text_in_step(+s: D.Step) -> String:
  J.show(payload_of(model_of(s)))

def body_text(+s: D.Step) -> String:
  body_of(model_of(s))

def notes_text(+s: D.Step) -> String:
  notes_text_of(model_of(s))

# ── reading a command back ──────────────────────────────────────────────

def http_method(+r: D.HttpReq) -> String:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      method

def http_url(+r: D.HttpReq) -> String:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      url

def http_body(+r: D.HttpReq) -> String:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      body

def first(+cs: List<&2, D.Cmd>) -> D.Cmd:
  match cs:
    case Nil{}:
      D.CmdNone{}
    case +h <> t:
      h

def first_cmd(+s: D.Step) -> D.Cmd:
  first(cmds_of(s))

def cmd_method(+c: D.Cmd) -> String:
  match c:
    case D.CmdHttp{id, req}:
      http_method(req)
    case _:
      SNil{}

def cmd_url(+c: D.Cmd) -> String:
  match c:
    case D.CmdHttp{id, req}:
      http_url(req)
    case _:
      SNil{}

def cmd_body(+c: D.Cmd) -> String:
  match c:
    case D.CmdHttp{id, req}:
      http_body(req)
    case _:
      SNil{}

def http_parts(+r: D.HttpReq) -> List<&2, String>:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      parts

def cmd_parts(+c: D.Cmd) -> String:
  match c:
    case D.CmdHttp{id, req}:
      String.join(http_parts(req), "|")
    case _:
      SNil{}

def cmd_path(+c: D.Cmd) -> String:
  match c:
    case D.CmdReadFile{id, path, why}:
      path
    case _:
      SNil{}

def cmd_why(+c: D.Cmd) -> String:
  match c:
    case D.CmdReadFile{id, path, why}:
      why
    case _:
      SNil{}

def http_count(+cs: List<&2, D.Cmd>, acc: U32) -> U32:
  match cs:
    case Nil{}:
      acc
    case +h <> t:
      match h:
        case D.CmdHttp{id, req}:
          http_count(t, U32.add(acc, 1))
        case _:
          http_count(t, acc)

def read_count(+cs: List<&2, D.Cmd>, acc: U32) -> U32:
  match cs:
    case Nil{}:
      acc
    case +h <> t:
      match h:
        case D.CmdReadFile{id, path, why}:
          read_count(t, U32.add(acc, 1))
        case _:
          read_count(t, acc)

# ── driving a run ───────────────────────────────────────────────────────
#
# A run is started the way the interpreter starts it, then fed its answers. The
# model is threaded by hand, so the script reads like the log of one real run.

def boot(+args: List<&2, String>, config_path: String) -> D.Step:
  U.Update.step(D.MsgStart{args, Nil{}, False{}, config_path}, U.Update.initial())

def boot_env(+args: List<&2, String>, +env: List<&2, D.Item>, config_path: String) -> D.Step:
  U.Update.step(D.MsgStart{args, env, False{}, config_path}, U.Update.initial())

def file_turn(action: Bool, id: U32, +path: String, +why: String, text: String, +m: D.Model) -> D.Step:
  U.Update.step(D.MsgFileOk{id, path, why, text}, m)

def file_fail(id: U32, +path: String, +why: String, message: String, +m: D.Model) -> D.Step:
  U.Update.step(D.MsgFileFail{id, path, why, 2, message}, m)

def answer(id: U32, curl_status: U32, http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  U.Update.step(D.MsgHttpOk{id, curl_status, http_status, body, stderr}, m)

# ── the arguments each scenario uses ────────────────────────────────────

def creds() -> List<&2, String>:
  "--auth-token" <> ("at" <> (
    "--ct0" <> ("ct" <> (
      "--web-bearer" <> ("bearer" <> (
        "--gql-features" <> ("{}" <> Nil{})
      ))
    ))
  ))

def whoami_args() -> List<&2, String>:
  "whoami" <> ("--op-viewer" <> ("OPV" <> creds()))

def search_args() -> List<&2, String>:
  "search" <> ("hi" <> creds())

def tweet_file_args() -> List<&2, String>:
  "tweet" <> ("--text-file" <> ("t.txt" <> ("--op-create-tweet" <> ("OPT" <> creds()))))

def tweet_both_args() -> List<&2, String>:
  "tweet" <> ("--text" <> ("explicit" <> ("--text-file" <> ("t.txt" <> creds()))))

def media_args() -> List<&2, String>:
  "tweet" <> ("hi" <> ("--media" <> ("shot.png" <> creds())))

def alt_media_args() -> List<&2, String>:
  "tweet" <> ("hi" <> ("--media" <> ("shot.png" <> ("--alt" <> ("the alt" <> creds())))))

def fixture_media_args() -> List<&2, String>:
  "tweet" <> ("hi" <> ("--media" <> ("shot.png" <> ("--fixture" <> ("fx.json" <> creds())))))

def two_media_args() -> List<&2, String>:
  "tweet" <> ("hi" <> ("--media" <> ("a.png" <> ("--media" <> ("b.png" <> creds())))))

def read_bad_args() -> List<&2, String>:
  "read" <> ("abc" <> creds())

def reply_no_id_args() -> List<&2, String>:
  "reply" <> ("https://x.com/someone" <> ("--text" <> ("hi" <> creds())))

def read_share_url_args() -> List<&2, String>:
  "read" <> ("https://x.com/u/status/99887766?s=20&t=abc" <> creds())

def viewer_body() -> String:
  "{\"data\":{\"viewer\":{\"screen_name\":\"bird\"}}}"

def main() -> IO(Unit):
  do IO<Unit>:
    # ── 1. a whoami run: credentials from flags, one request, no read ──
    +s1 : D.Step = boot(whoami_args(), SNil{})
    ok("a run that named no config file reads no file", U32.is_eq(read_count(cmds_of(s1), 0), 0))
    ok("...and goes straight to the request", String.eq(phase_tag(s1), "request"))
    ok("...asking for exactly one thing", U32.is_eq(http_count(cmds_of(s1), 0), 1))
    ok("...a POST to the operation the setting named", String.eq(cmd_method(first_cmd(s1)), "POST"))
    ok("...at the viewer url", String.contains(cmd_url(first_cmd(s1)), "/OPV/Viewer"))
    ok("...carrying the session as a cookie", String.contains(cmd_url(first_cmd(s1)), "graphql"))

    # ── 2. the answer lands ────────────────────────────────────────────
    +s2 : D.Step = answer(7, 0, 200, viewer_body(), SNil{}, model_of(s1))
    ok("an answer for the open request ends the run", String.eq(phase_tag(s2), "done"))
    ok("...with the body's data as the payload", String.contains(text_in_step(s2), "screen_name"))
    ok("...status 200, exit 0", U32.is_eq(status_of(model_of(s2)), 200))
    ok("...and the reason it is over is the answer's", U32.is_eq(exit_of(model_of(s2)), 0))

    # ── 3. an answer for another request is ignored ────────────────────
    s3 : D.Step = answer(9, 0, 200, "{}", SNil{}, model_of(s1))
    ok("an answer for a different id is ignored", String.eq(phase_tag(s3), "request"))

    # ── 4. curl's own failure ──────────────────────────────────────────
    +s4 : D.Step = answer(7, 7, 0, SNil{}, "could not resolve host", model_of(s1))
    ok("curl's failure is a network error", String.eq(failed_code(s4), "network"))
    ok("...with curl's own words kept", String.contains(notes_text(s4), "could not resolve host"))
    ok("...and exit code 6", U32.is_eq(exit_of(model_of(s4)), 6))

    # ── 5. a status that is not 200 ────────────────────────────────────
    +s5 : D.Step = answer(7, 0, 429, "slow down", SNil{}, model_of(s1))
    ok("a 429 is rate limited, not a success", String.eq(failed_code(s5), "rate_limited"))
    ok("...and the body is kept for the error", String.eq(body_text(s5), "slow down"))

    # ── 6. a body that is not JSON is not thrown away ───────────────────
    +s6 : D.Step = answer(7, 0, 200, "<html>nope</html>", SNil{}, model_of(s1))
    ok("a non-JSON body still ends the run", String.eq(phase_tag(s6), "done"))
    ok("...with a note saying why there is no data", String.contains(notes_text(s6), "not JSON"))
    ok("...and the raw body kept", String.eq(body_text(s6), "<html>nope</html>"))

    # ── 7. dry run ─────────────────────────────────────────────────────
    +d1 : D.Step = boot("--dry-run" <> whoami_args(), SNil{})
    ok("a dry run sends nothing", U32.is_eq(http_count(cmds_of(d1), 0), 0))
    ok("...and asks for nothing either", U32.is_eq(read_count(cmds_of(d1), 0), 0))
    ok("...but describes the request it would have sent", String.contains(text_in_step(d1), "curl"))
    ok("...argv and all", String.contains(text_in_step(d1), "max-time"))
    ok("...against the url the settings name", String.contains(text_in_step(d1), "/OPV/Viewer"))

    # ── 8. the config file is read, and it changes the request ─────────
    +c1 : D.Step = boot(search_args(), "cfg.json")
    ok("a named config file is read", U32.is_eq(read_count(cmds_of(c1), 0), 1))
    ok("...and the read is the one that waits", String.eq(phase_tag(c1), "gather"))
    ok("...for the file it was told to read", String.eq(cmd_path(first_cmd(c1)), "cfg.json"))
    ok("...and it is marked as the config", String.eq(cmd_why(first_cmd(c1)), "config"))

    +c2 : D.Step = file_turn(True{}, 1, "cfg.json", "config", "{\"--count\": 5}", model_of(c1))
    ok("the config's count reaches the request", String.contains(cmd_body(first_cmd(c2)), "\"count\":5"))
    ok("...instead of the built-in default", Bool.not(String.contains(cmd_body(first_cmd(c2)), "\"count\":10")))
    ok("...and the run is waiting on the request", String.eq(phase_tag(c2), "request"))

    # ── 9. a config file that cannot be read is not fatal ──────────────
    +c3 : D.Step = file_fail(1, "cfg.json", "config", "no such file", model_of(c1))
    ok("an unreadable config file is not an error", String.eq(phase_tag(c3), "request"))
    ok("...the run continues without it", U32.is_eq(http_count(cmds_of(c3), 0), 1))

    # ── 10. a config key that is not a flag is refused by name ─────────
    +c4 : D.Step = file_turn(True{}, 1, "cfg.json", "config", "{\"--nope\": 1}", model_of(c1))
    ok("a config key that is not a setting is refused", String.eq(failed_code(c4), "usage"))
    ok("...by name", String.contains(failed_message(c4), "--nope"))
    ok("...exit code 2", U32.is_eq(exit_of(model_of(c4)), 2))

    +c5 : D.Step = file_turn(True{}, 1, "cfg.json", "config", "not json at all", model_of(c1))
    ok("a config file that is not JSON is refused", String.eq(failed_code(c5), "usage"))
    ok("...saying what shape it wants", String.contains(failed_message(c5), "not usable"))

    # ── 11. the environment is a source too ────────────────────────────
    e1 : D.Step = boot_env(search_args(), D.Item.env("--count", "7"), SNil{})
    ok("the environment's count reaches the request", String.contains(cmd_body(first_cmd(e1)), "\"count\":7"))

    e2 : D.Step = boot_env("--count" <> ("2" <> search_args()), D.Item.env("--count", "7"), SNil{})
    ok("a flag beats the environment", String.contains(cmd_body(first_cmd(e2)), "\"count\":2"))

    # ── 12. --text-file alone fills the tweet ──────────────────────────
    +t1 : D.Step = boot(tweet_file_args(), SNil{})
    ok("a write with only a text file is accepted", U32.is_eq(read_count(cmds_of(t1), 0), 1))
    ok("...and it is the text file that is read", String.eq(cmd_why(first_cmd(t1)), "text-file"))
    +t2 : D.Step = file_turn(True{}, 2, "t.txt", "text-file", "hello world", model_of(t1))
    ok("the file's text becomes the tweet", String.contains(cmd_body(first_cmd(t2)), "hello world"))
    ok("...sent to the create operation", String.contains(cmd_url(first_cmd(t2)), "/OPT/CreateTweet"))
    ok("...and it is a POST", String.eq(cmd_method(first_cmd(t2)), "POST"))

    # ── 13. --text wins over the file it was given ─────────────────────
    +b1 : D.Step = file_turn(True{}, 2, "t.txt", "text-file", "from the file", model_of(boot(tweet_both_args(), SNil{})))
    ok("an explicit --text is not overwritten by the file", String.contains(cmd_body(first_cmd(b1)), "explicit"))
    ok("...and the file's text is not sent", Bool.not(String.contains(cmd_body(first_cmd(b1)), "from the file")))

    # ── 14. a file the run named and cannot read is an error ───────────
    +m1 : D.Step = file_fail(2, "t.txt", "text-file", "no such file", model_of(t1))
    ok("a text file that cannot be read fails the run", String.eq(failed_code(m1), "usage"))
    ok("...naming the path", String.contains(failed_message(m1), "t.txt"))

    # ── 15. a local verb needs no network at all ───────────────────────
    +k1 : D.Step = boot("check" <> creds(), SNil{})
    ok("a verb that only reports completes on its own", String.eq(phase_tag(k1), "done"))
    ok("...without asking for anything", U32.is_eq(http_count(cmds_of(k1), 0), 0))

    # ── 16. a fixture answers through the answer path ──────────────────
    +f1 : D.Step = boot("search" <> ("hi" <> ("--fixture" <> ("fx.json" <> Nil{}))), SNil{})
    ok("a fixture is read, and needs no credentials", U32.is_eq(read_count(cmds_of(f1), 0), 1))
    +f2 : D.Step = file_turn(True{}, 3, "fx.json", "fixture", "{\"data\":{\"x\":1}}", model_of(f1))
    ok("the fixture answers instead of the network", U32.is_eq(http_count(cmds_of(f2), 0), 0))
    ok("...through the same path an answer takes", String.eq(phase_tag(f2), "done"))
    ok("...with status 200", U32.is_eq(status_of(model_of(f2)), 200))
    ok("...and its body as the payload", String.contains(text_in_step(f2), "\"x\":1"))

    # ── 17. the two credential failures ───────────────────────────────
    +a1 : D.Step = boot("whoami" <> Nil{}, SNil{})
    ok("no credentials is an auth error, not a request", String.eq(failed_code(a1), "auth"))
    ok("...exit code 3", U32.is_eq(exit_of(model_of(a1)), 3))

    +n1 : D.Step = boot("whoami" <> ("--auth-token" <> ("at" <> ("--ct0" <> ("ct" <> Nil{})))), SNil{})
    ok("a session with no client bearer is refused", String.eq(failed_code(n1), "usage"))
    ok("...and the hint names the setting to set", String.contains(failed_hint(n1), "--web-bearer"))

    # ── 17b. a write with nothing to say ──────────────────────────────
    x1 : D.Step = boot("tweet" <> creds(), SNil{})
    ok("a tweet with no text and no file is refused", String.eq(failed_code(x1), "usage"))

    # ── 18. media: the upload first, the post once the id arrives ──────
    +g1 : D.Step = boot(media_args(), SNil{})
    ok("a media write opens the upload queue", String.eq(phase_tag(g1), "media"))
    ok("...with exactly one request, the upload", U32.is_eq(http_count(cmds_of(g1), 0), 1))
    ok("...at the media upload endpoint", String.contains(cmd_url(first_cmd(g1)), "/upload.json"))
    ok("...sending the file as a multipart part", String.contains(cmd_parts(first_cmd(g1)), "media=@shot.png"))
    ok("...and reaching nothing else yet", Bool.not(String.contains(cmd_url(first_cmd(g1)), "graphql")))

    +g2 : D.Step = answer(4, 0, 200, "{\"media_id_string\":\"11\"}", SNil{}, model_of(g1))
    ok("the upload's id opens the post", String.eq(phase_tag(g2), "request"))
    ok("...which carries the id", String.contains(cmd_body(first_cmd(g2)), "\"media_id\":\"11\""))
    ok("...and the text", String.contains(cmd_body(first_cmd(g2)), "\"tweet_text\":\"hi\""))
    ok("...on the create operation", String.contains(cmd_url(first_cmd(g2)), "/CreateTweet"))

    +g3 : D.Step = answer(7, 0, 200, "{\"data\":{\"create_tweet\":{}}}", SNil{}, model_of(g2))
    ok("the post's answer ends the run", String.eq(phase_tag(g3), "done"))

    # A refusal anywhere in the queue fails the run with X's own status and
    # words, rather than carrying on to post something half-attached.
    +g4 : D.Step = answer(4, 0, 413, "too big", SNil{}, model_of(g1))
    ok("an upload X refused fails the run", String.eq(failed_code(g4), "upstream"))
    ok("...with X's status kept", U32.is_eq(status_of(model_of(g4)), 413))
    ok("...and X's words kept", String.eq(body_text(g4), "too big"))

    +g5 : D.Step = answer(4, 0, 200, "{}", SNil{}, model_of(g1))
    ok("an upload with no media id is a failure", String.eq(failed_code(g5), "upstream"))
    ok("...naming what was missing", String.contains(failed_message(g5), "media id"))

    # An alt is a request of its own, after the upload it describes.
    +g6 : D.Step = boot(alt_media_args(), SNil{})
    ok("an alt write still opens with the upload", String.contains(cmd_url(first_cmd(g6)), "/upload.json"))
    +g7 : D.Step = answer(4, 0, 200, "{\"media_id_string\":\"11\"}", SNil{}, model_of(g6))
    ok("the alt call follows its upload", String.contains(cmd_url(first_cmd(g7)), "/metadata/create.json"))
    ok("...naming the id the upload produced", String.contains(cmd_body(first_cmd(g7)), "\"media_id\":\"11\""))
    ok("...and carrying the alt text", String.contains(cmd_body(first_cmd(g7)), "the alt"))
    +g8 : D.Step = answer(4, 0, 200, "ok", SNil{}, model_of(g7))
    ok("...and then the post", String.contains(cmd_url(first_cmd(g8)), "/CreateTweet"))

    # ── 18b. a fixture cannot answer a media write ─────────────────────
    +q0 : D.Step = boot(fixture_media_args(), SNil{})
    ok("a media write with a fixture still reads it", String.eq(phase_tag(q0), "gather"))
    +q1 : D.Step = file_turn(True{}, 3, "fx.json", "fixture", "{}", model_of(q0))
    ok("a fixture is refused for a media write", String.eq(failed_code(q1), "usage"))
    ok("...naming the flag", String.contains(failed_message(q1), "--fixture"))
    ok("...and sending nothing", U32.is_eq(http_count(cmds_of(q1), 0), 0))

    # ── 18c. an api key cannot carry a media write ─────────────────────
    +q2 : D.Step = boot("tweet" <> ("hi" <> ("--media" <> ("shot.png" <> ("--sweetistics-api-key" <> ("k" <> Nil{}))))), SNil{})
    ok("an api key cannot carry a media write", String.eq(failed_code(q2), "auth"))
    ok("...and no byte moves first", U32.is_eq(http_count(cmds_of(q2), 0), 0))

    # ── 18d. mentions is a read ────────────────────────────────────────
    +r1 : D.Step = boot("mentions" <> creds(), SNil{})
    ok("mentions is a GET on X's notifications path", String.contains(cmd_url(first_cmd(r1)), "notifications/mentions.json"))
    ok("...with the count as a query parameter", String.contains(cmd_url(first_cmd(r1)), "count=10"))
    ok("...and no body", String.eq(cmd_body(first_cmd(r1)), SNil{}))

    # ── 18e. a target with no id in it is refused before a request ─────
    +t9 : D.Step = boot(read_bad_args(), SNil{})
    ok("a target with no id in it is refused", String.eq(failed_code(t9), "usage"))
    ok("...naming what was passed", String.contains(failed_message(t9), "abc"))
    ok("...and nothing is sent", U32.is_eq(http_count(cmds_of(t9), 0), 0))

    +t10 : D.Step = boot(reply_no_id_args(), SNil{})
    ok("a reply url with no id in it is refused too", String.eq(failed_code(t10), "usage"))
    ok("...before a request exists", U32.is_eq(http_count(cmds_of(t10), 0), 0))

    +t11 : D.Step = boot(read_share_url_args(), SNil{})
    ok("a share url still yields its id", String.contains(cmd_body(first_cmd(t11)), "99887766"))

    # ── 18f. a failure mid-queue hands back the ids already uploaded ───
    +h1 : D.Step = boot(two_media_args(), SNil{})
    +h2 : D.Step = answer(4, 0, 200, "{\"media_id_string\":\"11\"}", SNil{}, model_of(h1))
    ok("the second upload follows the first", String.contains(cmd_url(first_cmd(h2)), "/upload.json"))
    +h3 : D.Step = answer(4, 0, 413, "too big", SNil{}, model_of(h2))
    ok("a mid-queue failure names the id already uploaded", String.contains(notes_text(h3), "11"))
    ok("...so a retry can reuse it", String.contains(notes_text(h3), "already uploaded"))

    # ── 19. the engine follows the credential that was given ───────────
    +w1 : D.Step = boot("whoami" <> ("--sweetistics-api-key" <> ("k" <> ("--op-viewer" <> ("/v" <> Nil{})))), SNil{})
    ok("an api key reaches the sweetistics host", String.contains(cmd_url(first_cmd(w1)), "/v"))
    ok("...not X's graphql host", Bool.not(String.contains(cmd_url(first_cmd(w1)), "x.com")))
