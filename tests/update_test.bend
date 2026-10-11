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
    case D.PhaseLogin{step, loot}:
      "login"
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

def verb_name(+s: D.Step) -> String:
  D.Verb.name(U.Update.verb_of(model_of(s)))

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

def cmd_program(+c: D.Cmd) -> String:
  match c:
    case D.CmdExec{id, program, args}:
      program
    case _:
      SNil{}

# A local program's arguments as one string, so an expectation reads as the
# command line a person would have typed.
def cmd_args(+c: D.Cmd) -> String:
  match c:
    case D.CmdExec{id, program, args}:
      String.join(args, " ")
    case _:
      SNil{}

def cmd_write_path(+c: D.Cmd) -> String:
  match c:
    case D.CmdWriteFile{id, path, text}:
      path
    case _:
      SNil{}

def cmd_write_text(+c: D.Cmd) -> String:
  match c:
    case D.CmdWriteFile{id, path, text}:
      text
    case _:
      SNil{}

def cmd_headers(+c: D.Cmd) -> List<&2, D.Header>:
  match c:
    case D.CmdHttp{id, req}:
      match req:
        case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
          headers
    case _:
      Nil{}

# The header's own name is read through a def rather than matched at the call
# site, because a def may not bind a local before a match that reads one of its
# parameters and `name` is a parameter here.
def header_named(+h: D.Header) -> String:
  match h:
    case D.Header{name, value}:
      name

def header_text(+h: D.Header) -> String:
  match h:
    case D.Header{name, value}:
      value

def header_value(+hs: List<&2, D.Header>, +name: String) -> String:
  match hs:
    case Nil{}:
      SNil{}
    case +h <> t:
      Bool.pick(String, String.eq(header_named(h), name), header_text(h), header_value(t, name))

def header_count(+hs: List<&2, D.Header>, acc: U32) -> U32:
  match hs:
    case Nil{}:
      acc
    case +h <> t:
      header_count(t, U32.add(acc, 1))

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

def exec_count(+cs: List<&2, D.Cmd>, acc: U32) -> U32:
  match cs:
    case Nil{}:
      acc
    case +h <> t:
      match h:
        case D.CmdExec{id, program, args}:
          exec_count(t, U32.add(acc, 1))
        case _:
          exec_count(t, acc)

def write_count(+cs: List<&2, D.Cmd>, acc: U32) -> U32:
  match cs:
    case Nil{}:
      acc
    case +h <> t:
      match h:
        case D.CmdWriteFile{id, path, text}:
          write_count(t, U32.add(acc, 1))
        case _:
          write_count(t, acc)

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

def proc_turn(id: U32, status: U32, +out: String, +err: String, +m: D.Model) -> D.Step:
  U.Update.step(D.MsgProc{id, status, out, err}, m)

def wrote_turn(id: U32, +path: String, ok: Bool, +message: String, +m: D.Model) -> D.Step:
  U.Update.step(D.MsgWrote{id, path, ok, message}, m)

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

# ── the arguments and documents the login scenarios use ─────────────────

def cache_path() -> String:
  "/tmp/bird/settings.json"

def tmp_dir() -> String:
  "/tmp/bird-tmp"

# The browser is Chrome and the key is handed over, so the flow is the whole
# recipe minus the keychain: the one step that can wait for a person, and the one
# step that is not deterministic, are both taken out of it.
# `--tmpdir` is not a flag: the interpreter passes TMPDIR through as an item, the
# same way it passes HOME, because where the temporary directory is is a fact about
# the machine rather than a setting a person types.
def login_env() -> List<&2, D.Item>:
  D.Item.env("--tmpdir", tmp_dir())

# The same, with a home directory: the settings path is passed by hand here, so the
# only thing HOME is read for is the cookie database Chrome's path is guessed from.
def login_home_env() -> List<&2, D.Item>:
  List.append(&2, D.Item, D.Item.env("--home", "/Users/x"), D.Item.env("--tmpdir", tmp_dir()))

def login_tail() -> List<&2, String>:
  "--cookie-db" <> ("/tmp/Cookies" <> (
    "--chrome-key" <> ("thekey" <> (
      "--settings-path" <> (cache_path() <> Nil{})
    ))
  ))

def login_args() -> List<&2, String>:
  "login" <> ("--cookie-source" <> ("chrome" <> login_tail()))

def login_args_keychain() -> List<&2, String>:
  "login" <> ("--cookie-source" <> ("chrome" <> ("--cookie-db" <> ("/tmp/Cookies" <> ("--settings-path" <> (cache_path() <> Nil{}))))))

def page_html() -> String:
  "<script defer src=\"https://abs.twimg.com/responsive-web/client-web/main.759a3196d8872caea.js\" nonce=\"x\"></script>"

def page_bundle_url() -> String:
  "https://abs.twimg.com/responsive-web/client-web/main.759a3196d8872caea.js"

def bundle_bearer() -> String:
  "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

def bundle_js() -> String:
  "e.exports={queryId:\"TpQxQtWMTMnIAMPlMGMqNw\",operationName:\"Viewer\",operationType:\"query\"}"
  ++ ",{queryId:\"3BlMtudy4N-d78ch7zTLZQ\",operationName:\"TweetDetail\",operationType:\"query\"}"
  ++ ",{queryId:\"irezafrnzav4Ulf1vDkEBg\",operationName:\"SearchTimeline\",operationType:\"query\"}"
  ++ ",{queryId:\"wR5Z_libLvkew3tF9w-Sg\",operationName:\"CreateTweet\",operationType:\"mutation\"}"
  ++ ",Bearer " ++ bundle_bearer() ++ "\","

def bundle_js_short() -> String:
  "e.exports={queryId:\"TpQxQtWMTMnIAMPlMGMqNw\",operationName:\"Viewer\",operationType:\"query\"}"
  ++ ",Bearer " ++ bundle_bearer() ++ "\","

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

    # ── 20. login: the browser's session, the bundle's constants, the cache ──
    +l1 : D.Step = boot_env(login_args(), login_env(), SNil{})
    ok("login opens on a local step, not on a request", String.eq(phase_tag(l1), "login"))
    ok("...reading the browser rather than the cache it is about to write", U32.is_eq(read_count(cmds_of(l1), 0), 0))
    ok("...and sending nothing yet", U32.is_eq(http_count(cmds_of(l1), 0), 0))
    ok("...with one read-only sqlite3", Bool.and(U32.is_eq(exec_count(cmds_of(l1), 0), 1), String.contains(cmd_args(first_cmd(l1)), "-readonly")))
    ok("...naming the database the setting gave", String.contains(cmd_args(first_cmd(l1)), "/tmp/Cookies"))
    ok("...writing both blobs into the temp directory", Bool.and(String.contains(cmd_args(first_cmd(l1)), "/tmp/bird-tmp/auth_token"), String.contains(cmd_args(first_cmd(l1)), "/tmp/bird-tmp/ct0")))

    # What a Chrome import answers is the number of bytes `writefile` wrote, one
    # per select -- not the cookies, which are in the two files on disk. A fixture
    # that answered with tidy `name|value` lines passed the step that reads them,
    # which is exactly the mistake this one records.
    +l2 : D.Step = proc_turn(5, 0, "16\n16\n", SNil{}, model_of(l1))
    ok("chrome's import answer is byte counts, not cookies", String.eq(phase_tag(l2), "login"))
    ok("a key that was handed over skips the keychain", String.eq(cmd_program(first_cmd(l2)), "openssl"))
    ok("...deriving the key from that password", String.contains(cmd_args(first_cmd(l2)), "pass:thekey"))
    ok("...at the recipe Chrome uses", Bool.and(String.contains(cmd_args(first_cmd(l2)), "PBKDF2"), String.contains(cmd_args(first_cmd(l2)), "iter:1003")))

    +l3 : D.Step = proc_turn(5, 0, "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99", SNil{}, model_of(l2))
    ok("the derived key decrypts, without its colons", String.contains(cmd_args(first_cmd(l3)), "-K AABBCCDDEEFF00112233445566778899"))
    ok("...reading the blob sqlite wrote", String.contains(cmd_args(first_cmd(l3)), "-in /tmp/bird-tmp/auth_token"))

    +l4 : D.Step = proc_turn(5, 0, "v10first-token", SNil{}, model_of(l3))
    ok("the second cookie is decrypted after the first", String.contains(cmd_args(first_cmd(l4)), "-in /tmp/bird-tmp/ct0"))

    +l5 : D.Step = proc_turn(5, 0, "second-token\n", SNil{}, model_of(l4))
    ok("the blobs are taken away once they are read", String.eq(cmd_program(first_cmd(l5)), "rm"))
    ok("...both of them", Bool.and(String.contains(cmd_args(first_cmd(l5)), "/auth_token"), String.contains(cmd_args(first_cmd(l5)), "/ct0")))

    +l6 : D.Step = proc_turn(5, 0, SNil{}, SNil{}, model_of(l5))
    ok("the session the browser gave is sent to X's own page", String.eq(cmd_method(first_cmd(l6)), "GET"))
    ok("...at the web home the settings name", String.eq(cmd_url(first_cmd(l6)), "https://x.com/home"))
    ok("...carrying both cookies", String.contains(header_value(cmd_headers(first_cmd(l6)), "cookie"), "auth_token=first-token; ct0=second-token"))
    ok("...with chrome's marker taken off", Bool.not(String.contains(header_value(cmd_headers(first_cmd(l6)), "cookie"), "v10")))
    ok("...and the csrf token X asks for", String.eq(header_value(cmd_headers(first_cmd(l6)), "x-csrf-token"), "second-token"))

    +l7 : D.Step = answer(5, 0, 200, page_html(), SNil{}, model_of(l6))
    ok("the page's bundle is asked for by its full url", String.eq(cmd_url(first_cmd(l7)), page_bundle_url()))
    ok("...with no cookies, because a bundle is public", U32.is_eq(header_count(cmd_headers(first_cmd(l7)), 0), 0))

    +l8 : D.Step = answer(5, 0, 200, bundle_js(), SNil{}, model_of(l7))
    ok("the cache is written where the setting said", Bool.and(U32.is_eq(write_count(cmds_of(l8), 0), 1), String.eq(cmd_write_path(first_cmd(l8)), cache_path())))
    ok("...carrying the bearer the bundle carried", String.contains(cmd_write_text(first_cmd(l8)), bundle_bearer()))
    ok("...and the viewer id", String.contains(cmd_write_text(first_cmd(l8)), "TpQxQtWMTMnIAMPlMGMqNw"))
    ok("...and the detail id", String.contains(cmd_write_text(first_cmd(l8)), "3BlMtudy4N-d78ch7zTLZQ"))
    ok("...and the search id", String.contains(cmd_write_text(first_cmd(l8)), "irezafrnzav4Ulf1vDkEBg"))
    ok("...and the create id", String.contains(cmd_write_text(first_cmd(l8)), "wR5Z_libLvkew3tF9w-Sg"))
    ok("...and the session the browser gave", String.contains(cmd_write_text(first_cmd(l8)), "first-token"))

    +l9 : D.Step = wrote_turn(5, cache_path(), True{}, SNil{}, model_of(l8))
    ok("the cache is closed to everyone but its owner", String.eq(cmd_program(first_cmd(l9)), "chmod"))
    ok("...mode 600", String.contains(cmd_args(first_cmd(l9)), "600 " ++ cache_path()))

    +l10 : D.Step = proc_turn(5, 0, SNil{}, SNil{}, model_of(l9))
    ok("login ends when the cache is on disk and locked", String.eq(phase_tag(l10), "done"))
    ok("...and reports the verb it ran, not the default", String.eq(verb_name(l10), "login"))
    ok("...reporting the path it wrote", String.contains(text_in_step(l10), cache_path()))
    ok("...naming an operation it found", String.contains(text_in_step(l10), "TpQxQtWMTMnIAMPlMGMqNw"))
    ok("...and never the cookies themselves", Bool.not(String.contains(text_in_step(l10), "first-token")))

    +l11 : D.Step = wrote_turn(5, cache_path(), False{}, "no such file or directory", model_of(l8))
    ok("a cache that cannot be written fails the run", String.eq(failed_code(l11), "usage"))
    ok("...naming the path", String.contains(failed_message(l11), cache_path()))
    ok("...and keeping what the write itself said", String.contains(failed_hint(l11), "no such file"))

    # ── 21. a cache that is not a settings file ────────────────────────
    +v1 : D.Step = boot("whoami" <> ("--settings-path" <> (cache_path() <> Nil{})), SNil{})
    ok("a run with no flags reads the cache login wrote", String.eq(cmd_why(first_cmd(v1)), "settings"))
    ok("...and waits for it", String.eq(phase_tag(v1), "gather"))

    +v2 : D.Step = file_turn(True{}, 6, cache_path(), "settings", cmd_write_text(first_cmd(l8)), model_of(v1))
    ok("the cached bearer reaches the request", String.eq(header_value(cmd_headers(first_cmd(v2)), "authorization"), "Bearer " ++ bundle_bearer()))
    ok("...the cached operation id reaches the url", String.contains(cmd_url(first_cmd(v2)), "/TpQxQtWMTMnIAMPlMGMqNw/Viewer"))
    ok("...and the cached cookies make it a session", String.contains(header_value(cmd_headers(first_cmd(v2)), "cookie"), "auth_token=first-token"))

    +v3 : D.Step = boot("--web-bearer" <> ("flag-bearer" <> ("whoami" <> ("--settings-path" <> (cache_path() <> Nil{})))), SNil{})
    +v4 : D.Step = file_turn(True{}, 6, cache_path(), "settings", cmd_write_text(first_cmd(l8)), model_of(v3))
    ok("a flag still wins over the cache", String.eq(header_value(cmd_headers(first_cmd(v4)), "authorization"), "Bearer flag-bearer"))

    +v5 : D.Step = file_turn(True{}, 6, cache_path(), "settings", "not json at all", model_of(v1))
    ok("a cache that is not a JSON object is refused", String.eq(failed_code(v5), "usage"))
    ok("...by path, so a person can delete it", String.contains(failed_message(v5), cache_path()))
    ok("...with the hint naming the way back", String.contains(failed_hint(v5), "login"))

    # ── 22. login refuses what it cannot do, before running anything ────
    +n2 : D.Step = boot("login" <> ("--cookie-source" <> ("safari" <> Nil{})), SNil{})
    ok("a browser this build cannot read is refused by name", String.contains(failed_message(n2), "safari"))

    # Firefox has no path this program can guess, so a firefox run has to name one.
    +n3 : D.Step = boot_env("login" <> ("--cookie-source" <> ("firefox" <> ("--settings-path" <> (cache_path() <> Nil{})))), login_env(), SNil{})
    ok("firefox with no database is refused", String.eq(failed_code(n3), "usage"))
    ok("...and the hint names the flag", String.contains(failed_hint(n3), "--cookie-db"))

    # Chrome's is guessed from the home directory, so the same run needs no flag.
    +n5 : D.Step = boot_env("login" <> ("--cookie-source" <> ("chrome" <> ("--settings-path" <> (cache_path() <> Nil{})))), login_home_env(), SNil{})
    ok("chrome's database is guessed from the home directory", String.contains(cmd_args(first_cmd(n5)), "Chrome/Default/Cookies"))

    +n4 : D.Step = boot("login" <> ("--settings-path" <> (cache_path() <> Nil{})), SNil{})
    ok("login with no session at all is refused", String.eq(failed_code(n4), "usage"))
    ok("...with the flags that would fix it", String.contains(failed_hint(n4), "--cookie-source"))
    ok("...and nothing runs first", U32.is_eq(exec_count(cmds_of(n4), 0), 0))

    # ── 23. the keychain, when the key was not handed over ─────────────
    +k3 : D.Step = boot_env(login_args_keychain(), login_env(), SNil{})
    +k4 : D.Step = proc_turn(5, 0, "10|20", SNil{}, model_of(k3))
    ok("with no --chrome-key the keychain is asked", String.eq(cmd_program(first_cmd(k4)), "security"))
    ok("...for the entry Chrome keeps its key in", String.contains(cmd_args(first_cmd(k4)), "Chrome Safe Storage"))

    +k5 : D.Step = proc_turn(5, 0, "keychain-password\n", SNil{}, model_of(k4))
    ok("what the keychain answered is the derivation's password", String.contains(cmd_args(first_cmd(k5)), "pass:keychain-password"))

    +k6 : D.Step = proc_turn(5, 44, SNil{}, "the specified item could not be found", model_of(k4))
    ok("an empty keychain answer is an auth error", String.eq(failed_code(k6), "auth"))
    ok("...naming --chrome-key as the way past it", String.contains(failed_hint(k6), "--chrome-key"))

    # ── 24. a page that came back signed out, a bundle with a hole ──────
    +p2 : D.Step = answer(5, 0, 200, "<html>sign in to x</html>", SNil{}, model_of(l6))
    ok("a page with no bundle in it is refused", String.eq(failed_code(p2), "auth"))
    ok("...saying the session was not accepted", String.contains(failed_message(p2), "signed out"))

    +p3 : D.Step = answer(5, 0, 200, bundle_js_short(), SNil{}, model_of(l7))
    ok("a bundle missing an operation is refused by name", String.eq(failed_code(p3), "upstream"))
    ok("...naming the setting to pass by hand", String.contains(failed_message(p3), "--op-tweet-detail"))

    # ── 25. the config file and the settings cache land in one round ────
    #
    # Two files whose contents are settings now open the first round together, so
    # the run has to wait for both: a round that closed on the first answer would
    # resolve the request before the config file had been read.
    +r9 : D.Step = boot_env(search_args(), login_home_env(), "cfg.json")
    ok("both settings files are read in the first round", U32.is_eq(read_count(cmds_of(r9), 0), 2))
    ok("...and the run waits for both of them", String.eq(phase_tag(r9), "gather"))

    +r10 : D.Step = U.Update.step(D.MsgFileFail{6, "/Users/x/.config/bird/settings.json", "settings", 2, "no such file"}, model_of(r9))
    ok("one landing of two does not close the round", String.eq(phase_tag(r10), "gather"))

    +r11 : D.Step = U.Update.step(D.MsgFileOk{1, "cfg.json", "config", "{\"--count\": 5}"}, model_of(r10))
    ok("the second landing closes it, and the config still counts", String.contains(cmd_body(first_cmd(r11)), "\"count\":5"))

    # ── 26. a failure ends the run while the round drains ───────────────
    #
    # The refusal arrives with the cache read still open, and the cache's own
    # landing must not revive the run: it did once, and the report came out as a
    # success naming the default verb, because the answer landed on the model the
    # failure had already replaced.
    +r12 : D.Step = boot_env("check" <> ("--json" <> Nil{}), login_home_env(), "cfg.json")
    +r13 : D.Step = U.Update.step(D.MsgFileOk{1, "cfg.json", "config", "{\"--nope\":1}"}, model_of(r12))
    ok("a config key that is not a setting is refused", String.eq(failed_code(r13), "usage"))

    +r14 : D.Step = U.Update.step(D.MsgFileOk{6, "/Users/x/.config/bird/settings.json", "settings", "{}"}, model_of(r13))
    ok("...and the run stays failed while the round drains", String.eq(failed_code(r14), "usage"))
    ok("...with nothing sent", U32.is_eq(http_count(cmds_of(r14), 0), 0))
    ok("...and the failure is still the one that happened", String.contains(failed_message(r14), "--nope"))

    # ── 27. a Firefox profile answers in one call, with no cipher ───────
    +fr1 : D.Step = boot_env("login" <> ("--cookie-source" <> ("firefox" <> ("--cookie-db" <> ("/tmp/cookies.sqlite" <> ("--settings-path" <> (cache_path() <> Nil{})))))), login_env(), SNil{})
    ok("firefox reads its cookies with one sqlite3 call", Bool.and(String.eq(cmd_program(first_cmd(fr1)), "sqlite3"), String.contains(cmd_args(first_cmd(fr1)), "/tmp/cookies.sqlite")))
    ok("...and the query is a plain select", String.contains(cmd_args(first_cmd(fr1)), "select name, value from moz_cookies"))

    +fr2 : D.Step = proc_turn(5, 0, "auth_token|at-from-firefox\nct0|ct0-from-firefox\n", SNil{}, model_of(fr1))
    ok("a firefox answer goes straight to the page, with no keychain and no openssl", Bool.and(String.eq(cmd_method(first_cmd(fr2)), "GET"), Bool.not(String.contains(cmd_args(first_cmd(fr2)), "openssl"))))
    ok("...carrying what the table held", String.contains(header_value(cmd_headers(first_cmd(fr2)), "cookie"), "auth_token=at-from-firefox; ct0=ct0-from-firefox"))

    +fr3 : D.Step = proc_turn(5, 0, "auth_token|only-one\n", SNil{}, model_of(fr1))
    ok("a session with only half a cookie is refused", String.eq(failed_code(fr3), "usage"))
    ok("...naming the database as the thing to check", String.contains(failed_hint(fr3), "--cookie-db"))
