import Base
import ./domain.bend as D
import ./json.bend as J
import ./policy.bend as P
import ./argv.bend as A
import ./api.bend as Api
import ./http.bend as H
import ./bundle.bend as B
import ./cookies.bend as C
import ./tweets.bend as T

# The fold. One message in, the new model and the effects to run next out. No IO
# anywhere, so a test plays a whole run by handing it scripted messages in the
# order the interpreter would deliver them.
#
# Two decisions worth knowing about:
#
# * The config file is read even when the run named none, because "there is no
#   config" is a fact the run needs, and a missing config is not an error. A
#   missing `--text-file` or `--fixture` is an error, and names the path.
# * The request is built from settings that were all resolved before it, so
#   `--dry-run` describes exactly the request a real run would send rather than a
#   second guess at it. `--fixture` answers through the same fold a live response
#   goes through, so it cannot drift from a real run.
#
# Read top to bottom, this file is written so that every def is complete before
# it is called: Bend has no forward declarations, and the sections below are in
# dependency order for that reason rather than by topic.

# ── the ids reads are correlated by ─────────────────────────────────────
# A round's reads are all in flight at once, so each needs its own id; the
# request takes an id of its own above them.
def Update.id_config() -> U32:
  1

def Update.id_text() -> U32:
  2

def Update.id_fixture() -> U32:
  3

def Update.id_request() -> U32:
  7

# The settings cache is read in the same round as the config file: it is the other
# file whose contents are settings.
def Update.id_settings() -> U32:
  6

# Every command the login flow runs shares one id, because only one is ever open:
# the step in the phase says which one, exactly as the media queue does.
def Update.id_login() -> U32:
  5

def Update.why_settings() -> String:
  "settings"

# Media requests get an id of their own, so an upload answer can never be
# mistaken for the post's. Uploads run one at a time, so one id covers them all.
def Update.id_media() -> U32:
  4

def Update.why_config() -> String:
  "config"

def Update.why_text() -> String:
  "text-file"

def Update.why_fixture() -> String:
  "fixture"

# ── which verb is this ─────────────────────────────────────────────────

def Update.is_login(+v: D.Verb) -> Bool:
  match v:
    case D.VerbLogin{}:
      True{}
    case _:
      False{}

def Update.is_chrome(+s: String) -> Bool:
  match s:
    case "chrome":
      True{}
    case _:
      False{}

def Update.have_source(+s: String) -> Bool:
  Bool.not(String.is_empty(s))

# ── reads ───────────────────────────────────────────────────────────────
#
# The argument is "there is no path", not "read this": a run that named no
# config file and no fixture must issue no reads at all, and with the flag the
# other way round the interpreter waits forever for a file nobody asked for.

def Update.read(absent: Bool, id: U32, path: String, why: String) -> List<&2, D.Cmd>:
  match absent:
    case True{}:
      Nil{}
    case False{}:
      D.Cmd.read_file(id, path, why) <> Nil{}

def Update.two_reads(+text_path: String, +fixture_path: String) -> List<&2, D.Cmd>:
  List.append(&2, D.Cmd,
    Update.read(String.is_empty(text_path), Update.id_text(), text_path, Update.why_text()),
    Update.read(String.is_empty(fixture_path), Update.id_fixture(), fixture_path, Update.why_fixture()))

# The first round: the config file, if one was named. A run that named none opens
# the second round instead.
# The first round opens both files whose contents are settings: the config file, if
# one was named, and the cache `login` writes. A missing cache is not an error,
# exactly as a missing config file is not, and both land in the same list in the
# order the resolver reads: a config file wins over the cache because the cache is
# prepended when it lands.
# `login` does not read the cache, because it writes it: a cache that has been
# corrupted is then something `login` can repair rather than something that stops
# the repair from running.
def Update.cache_read_path(wanted: Bool, path: String) -> List<&2, D.Cmd>:
  match wanted:
    case True{}:
      Update.read(False{}, Update.id_settings(), path, Update.why_settings())
    case False{}:
      Nil{}

def Update.cache_read(wanted: Bool, +path: String) -> List<&2, D.Cmd>:
  Update.cache_read_path(Bool.and(wanted, Bool.not(String.is_empty(path))), path)

# The verb is read straight out of the start rather than through the accessor
# defined below, because a def may only call one that is written before it.
def Update.cache_needed(+s: D.Start) -> Bool:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      Bool.not(Update.is_login(P.Cfg.verb(items, D.VerbHelp{})))

def Update.first_reads(+s: D.Start) -> List<&2, D.Cmd>:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      List.append(&2, D.Cmd,
        Update.read(String.is_empty(config_path), Update.id_config(), config_path, Update.why_config()),
        Update.cache_read(Update.cache_needed(s), P.Cfg.settings_path_on(items, env, rc))
      )

def Update.text_path(+s: D.Start) -> String:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      P.Cfg.order(items, env, rc, "--text-file", SNil{})

def Update.fixture_path(+s: D.Start) -> String:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      P.Cfg.order(items, env, rc, "--fixture", SNil{})

# The second round: the text file and the fixture, whose paths the config file
# may set, which is why this round waits for the one before it.
def Update.second_reads(+s: D.Start) -> List<&2, D.Cmd>:
  Update.two_reads(Update.text_path(s), Update.fixture_path(s))

# ── reading the model ───────────────────────────────────────────────────

def Update.start_of(+m: D.Model) -> D.Start:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      start

def Update.cfg_of(+m: D.Model) -> D.RunCfg:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      cfg

def Update.verb_in(+cfg: D.RunCfg) -> D.Verb:
  match cfg:
    case D.RunCfg{verb, dry_run, out, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      verb

def Update.verb_of(+m: D.Model) -> D.Verb:
  Update.verb_in(Update.cfg_of(m))

def Update.text_in(+s: D.Start) -> String:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      text

def Update.fixture_in(+s: D.Start) -> String:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      fixture

def Update.stage_of(+s: D.Start) -> D.Stage:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      stage

def Update.items_in(+s: D.Start) -> List<&2, D.Item>:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      items

def Update.env_in(+s: D.Start) -> List<&2, D.Item>:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      env

def Update.rc_in(+s: D.Start) -> List<&2, D.Item>:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      rc

def Update.tty_in(+s: D.Start) -> Bool:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      tty

def Update.config_path_in(+s: D.Start) -> String:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      config_path

def Update.pending_in(+s: D.Start) -> Nat:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      pending

def Update.config_at(+m: D.Model) -> String:
  Update.config_path_in(Update.start_of(m))

def Update.phase_in(+m: D.Model) -> D.Phase:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      phase

# ── the answer ──────────────────────────────────────────────────────────

# The request that is open, so an answer can be matched to it. A message that
# does not answer the open request is ignored rather than folded, which is what
# keeps a late or duplicated answer from corrupting the model.
def Update.phase_id(+p: D.Phase) -> Maybe<&2, U32>:
  match p:
    case D.PhaseRequest{id}:
      Some{id}
    case D.PhaseMedia{jobs, done}:
      Some{Update.id_media()}
    case D.PhaseLogin{step, loot}:
      Some{Update.id_login()}
    case _:
      None{}

def Update.login_phase_on(+p: D.Phase) -> Bool:
  match p:
    case D.PhaseLogin{step, loot}:
      True{}
    case _:
      False{}

def Update.is_login_phase(+m: D.Model) -> Bool:
  Update.login_phase_on(Update.phase_in(m))

def Update.id_matches(+want: Maybe<&2, U32>, id: U32) -> Bool:
  match want:
    case Some{n}:
      U32.is_eq(n, id)
    case None{}:
      False{}

def Update.matches(+m: D.Model, id: U32) -> Bool:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      Update.id_matches(Update.phase_id(phase), id)

# curl's own messages already start with "curl: ", so the prefix is added only
# when it is not already there. This note is where a person first learns why a
# request failed, and "curl: curl: (26) ..." reads like two programs spoke.
def Update.note_on(prefixed: Bool, +stderr: String) -> String:
  match prefixed:
    case True{}:
      stderr
    case False{}:
      "curl: " ++ stderr

def Update.note_text(+stderr: String) -> String:
  Update.note_on(String.starts_with(stderr, "curl: "), stderr)

def Update.notes_on(quiet: Bool, +stderr: String) -> List<&2, String>:
  match quiet:
    case True{}:
      Nil{}
    case False{}:
      Update.note_text(stderr) <> Nil{}

def Update.notes_ok(+stderr: String) -> List<&2, String>:
  Update.notes_on(String.is_empty(stderr), stderr)

# A failure inside a media queue leaves uploads X has already accepted with
# nothing attached, and there is no rollback to call: the ids are the one piece
# of state worth handing back, because whoever retries can reuse them instead of
# sending the same bytes again.
def Update.uploaded_note(+done: List<&2, String>) -> List<&2, String>:
  match done:
    case Nil{}:
      Nil{}
    case _:
      ("already uploaded, still usable: " ++ String.join(List.reverse(&2, String, done), ", ")) <> Nil{}

def Update.phase_done(+p: D.Phase) -> List<&2, String>:
  match p:
    case D.PhaseMedia{jobs, done}:
      done
    case _:
      Nil{}

def Update.media_fail_notes(+m: D.Model, +stderr: String) -> List<&2, String>:
  List.append(&2, String, Update.notes_ok(stderr), Update.uploaded_note(Update.phase_done(Update.phase_in(m))))

# A body that is not JSON is not a failure: the body is kept either way and the
# note says why `data` is null, so an HTML error page is not thrown away.
def Update.not_json(message: String, +stderr: String) -> List<&2, String>:
  ("the response body is not JSON: " ++ message) <> Update.notes_ok(stderr)

# ── what a read verb answers with ───────────────────────────────────────
#
# X answers one tweet with about 119 KB of its own bookkeeping -- timeline entry
# ids, cursors, display options, the author's whole profile blob, the client's
# feature flags -- and the text six levels down inside it. The fold is the one
# place where a response becomes the model's payload, so it is the one place that
# folds the envelope into tweets: a renderer then knows nothing about X's layout,
# and `--raw` is the only way to see the envelope again.
#
# `read` asked for one tweet and X answers with the conversation around it, so it
# narrows to the tweet that was asked for. The other read verbs asked for a list
# and keep every tweet X sent, in the order X sent them, the focal tweet among
# them. Anything else -- a write, a media upload, a login step -- is untouched.

def Update.raw_mode(+m: D.Model) -> Bool:
  D.Items.has_flag(Update.items_in(Update.start_of(m)), "--raw")

def Update.shaped_verb(+v: D.Verb, +root: J.Json) -> J.Json:
  match v:
    case D.VerbRead{target}:
      T.Tweets.list_in(root, P.TweetId.of(target))
    case D.VerbReplies{target}:
      T.Tweets.list_in(root, SNil{})
    case D.VerbThread{target}:
      T.Tweets.list_in(root, SNil{})
    case D.VerbSearch{query, count}:
      T.Tweets.list_in(root, SNil{})
    case D.VerbMentions{count}:
      T.Tweets.list_in(root, SNil{})
    case D.VerbWhoami{}:
      T.Tweets.profile_in(root)
    case _:
      root

def Update.shaped_on(raw: Bool, +m: D.Model, +root: J.Json) -> J.Json:
  match raw:
    case True{}:
      root
    case False{}:
      Update.shaped_verb(Update.verb_of(m), root)

def Update.parsed(+m: D.Model, +p: J.Parsed, http_status: U32, body: String, stderr: String) -> D.Step:
  match p:
    case J.ParsedOk{value}:
      D.mk_step(D.Model.answered(m, http_status, Update.shaped_on(Update.raw_mode(m), m, value), body, Update.notes_ok(stderr)), D.no_cmds())
    case J.ParsedErr{message}:
      D.mk_step(D.Model.answered(m, http_status, J.null(), body, Update.not_json(message, stderr)), D.no_cmds())

def Update.answered(+m: D.Model, http_status: U32, +body: String, stderr: String) -> D.Step:
  Update.parsed(m, J.parse(body), http_status, body, stderr)

def Update.status_ok(+e: Maybe<&2, D.Error>, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match e:
    case Some{x}:
      D.mk_step(D.Model.with_notes(D.Model.failed_status(m, http_status, x, body), Update.notes_ok(stderr)), D.no_cmds())
    case None{}:
      Update.answered(m, http_status, body, stderr)

# A response that arrived is still a failure when the status says so, and the
# code is the one the rest of the program uses, so an agent sees one vocabulary.
def Update.transport_ok(+e: Maybe<&2, D.Error>, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match e:
    case Some{x}:
      D.mk_step(D.Model.with_notes(D.Model.failed_status(m, http_status, x, body), Update.notes_ok(stderr)), D.no_cmds())
    case None{}:
      Update.status_ok(H.Http.status_error(H.Resp{http_status, body}), http_status, body, stderr, m)

# The answer handlers are further down, after the media queue they can open:
# Bend has no forward declarations, so a handler that may queue an upload cannot
# stand above the def that queues it.

# ── the login flow ──────────────────────────────────────────────────────
#
# `login` goes and gets what a run needs rather than being handed it, and it is a
# queue of local programs and two requests folded the way a media write is: the
# step says which command is open and the loot is what the steps before it learned
# and the ones after it need.
#
# There is no login here. No password goes to X and no credential is obtained from
# it: the session comes out of a browser that is already signed in, the bearer and
# the operation ids out of the bundle that browser loads, and the file they are
# written to is what a later run reads. See docs/decisions/0001-design-bird.md
# for why that is a deliberate reversal of an earlier non-goal.
#
# The pages and the bundle are ordinary requests, so they go through the same
# `CmdHttp` the transport uses and land on the same `MsgHttpOk`; everything else is
# `CmdExec`, which is `Process.run` with the program named by the fold. Nothing
# here builds a request of its own shape.

def Update.login_internal() -> D.Error:
  D.err(D.ErrInternal{}, "internal: a login answer arrived with no login step open")

def Update.login_source_lost() -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "the browser had no x.com session to import",
    "check --cookie-db: the database has to be the profile you are signed in with"
  )

def Update.login_key_lost() -> D.Error:
  D.err_hint(
    D.ErrAuth{},
    "the keychain password did not decrypt the cookie",
    "pass --chrome-key, or unlock the login keychain so `security` can read it"
  )

def Update.login_page_lost() -> D.Error:
  D.err_hint(
    D.ErrAuth{},
    "the page came back signed out, so the session was not accepted",
    "the cookies may have expired; sign in again and re-run login"
  )

def Update.login_bundle_lost(+name: String) -> D.Error:
  D.err_hint(
    D.ErrUpstream{},
    "X's bundle no longer carries " ++ name,
    "X renamed or moved its operations; pass that setting by hand for now"
  )

def Update.login_write_lost(+path: String, message: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "cannot write the settings cache: " ++ path,
    message
  )

def Update.timeout_in(+cfg: D.RunCfg) -> U32:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      timeout_ms

def Update.cfg_timeout(+m: D.Model) -> U32:
  Update.timeout_in(Update.cfg_of(m))

def Update.login_cfg(+m: D.Model) -> D.LoginCfg:
  P.Cfg.login_cfg_on(
    Update.items_in(Update.start_of(m)),
    Update.env_in(Update.start_of(m)),
    Update.rc_in(Update.start_of(m))
  )

def Update.session_at(+m: D.Model) -> String:
  P.Cfg.order(Update.items_in(Update.start_of(m)), Update.env_in(Update.start_of(m)), Update.rc_in(Update.start_of(m)), "--auth-token", SNil{})

def Update.session_ct0(+m: D.Model) -> String:
  P.Cfg.order(Update.items_in(Update.start_of(m)), Update.env_in(Update.start_of(m)), Update.rc_in(Update.start_of(m)), "--ct0", SNil{})

def Update.login_settings_path(+lc: D.LoginCfg) -> String:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      settings_path

def Update.login_source(+lc: D.LoginCfg) -> String:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      source

def Update.login_web_home(+lc: D.LoginCfg) -> String:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      web_home

def Update.login_db(+lc: D.LoginCfg) -> String:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      db

def Update.login_bundle_base(+lc: D.LoginCfg) -> String:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      bundle_base

def Update.tmp_dir_of(+lc: D.LoginCfg) -> String:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      tmp_dir

def Update.chrome_key_of(+lc: D.LoginCfg) -> String:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      chrome_key

def Update.loot_dir(+l: D.Loot) -> String:
  match l:
    case D.Loot{dir, url, password, key, at, ct0, cache}:
      dir

def Update.loot_url(+l: D.Loot) -> String:
  match l:
    case D.Loot{dir, url, password, key, at, ct0, cache}:
      url

def Update.loot_password(+l: D.Loot) -> String:
  match l:
    case D.Loot{dir, url, password, key, at, ct0, cache}:
      password

def Update.loot_key(+l: D.Loot) -> String:
  match l:
    case D.Loot{dir, url, password, key, at, ct0, cache}:
      key

def Update.loot_at(+l: D.Loot) -> String:
  match l:
    case D.Loot{dir, url, password, key, at, ct0, cache}:
      at

def Update.loot_ct0(+l: D.Loot) -> String:
  match l:
    case D.Loot{dir, url, password, key, at, ct0, cache}:
      ct0

def Update.loot_cache(+l: D.Loot) -> String:
  match l:
    case D.Loot{dir, url, password, key, at, ct0, cache}:
      cache

def Update.json_of(+p: J.Parsed) -> J.Json:
  match p:
    case J.ParsedOk{value}:
      value
    case J.ParsedErr{message}:
      J.null()

# ── the commands ────────────────────────────────────────────────────────

def Update.cookie_sql_on(chrome: Bool, +dir: String) -> String:
  match chrome:
    case True{}:
      C.Cookies.chrome_sql(dir)
    case False{}:
      C.Cookies.firefox_sql()

def Update.cookies_cmd(+loot: D.Loot, +lc: D.LoginCfg) -> D.Cmd:
  D.CmdExec{Update.id_login(), C.Cookies.sqlite3(), C.Cookies.sqlite_args(Update.login_db(lc), Update.cookie_sql_on(Update.is_chrome(Update.login_source(lc)), Update.loot_dir(loot)))}

# The page wants the session and nothing else: a browser loading its own page
# sends the cookies, and the bearer is only used by the API calls the page's own
# scripts make.
def Update.login_headers(+at: String, +ct0: String) -> List<&2, D.Header>:
  D.hdr("cookie", Api.Api.cookie(at, ct0)) <> (
    D.hdr("x-csrf-token", ct0) <> (
      D.hdr("x-twitter-active-user", "yes") <> Nil{}
    )
  )

def Update.page_cmd(+loot: D.Loot, +lc: D.LoginCfg, timeout_ms: U32) -> D.Cmd:
  D.CmdHttp{Update.id_login(), D.mk_http("GET", Update.login_web_home(lc), Update.login_headers(Update.loot_at(loot), Update.loot_ct0(loot)), SNil{}, timeout_ms)}

def Update.bundle_cmd(+loot: D.Loot, timeout_ms: U32) -> D.Cmd:
  D.CmdHttp{Update.id_login(), D.mk_http("GET", Update.loot_url(loot), Nil{}, SNil{}, timeout_ms)}

def Update.write_cmd(+loot: D.Loot, +lc: D.LoginCfg) -> D.Cmd:
  D.CmdWriteFile{Update.id_login(), Update.login_settings_path(lc), Update.loot_cache(loot)}

def Update.lock_cmd(+lc: D.LoginCfg) -> D.Cmd:
  D.CmdExec{Update.id_login(), C.Cookies.chmod(), C.Cookies.chmod_args(Update.login_settings_path(lc))}

def Update.login_cmd(step: D.LoginStep, +loot: D.Loot, +lc: D.LoginCfg, timeout_ms: U32) -> D.Cmd:
  match step:
    case D.LoginCookies{}:
      Update.cookies_cmd(loot, lc)
    case D.LoginKey{}:
      D.CmdExec{Update.id_login(), C.Cookies.security(), C.Cookies.security_args()}
    case D.LoginDerive{}:
      D.CmdExec{Update.id_login(), C.Cookies.openssl(), C.Cookies.kdf_args(Update.loot_password(loot))}
    case D.LoginDecrypt{}:
      D.CmdExec{Update.id_login(), C.Cookies.openssl(), C.Cookies.decrypt_args(Update.loot_key(loot), C.Cookies.path(Update.loot_dir(loot), C.Cookies.at_name()))}
    case D.LoginDecrypt2{}:
      D.CmdExec{Update.id_login(), C.Cookies.openssl(), C.Cookies.decrypt_args(Update.loot_key(loot), C.Cookies.path(Update.loot_dir(loot), C.Cookies.ct0_name()))}
    case D.LoginClean{}:
      D.CmdExec{Update.id_login(), "rm", C.Cookies.rm_args(Update.loot_dir(loot))}
    case D.LoginPage{}:
      Update.page_cmd(loot, lc, timeout_ms)
    case D.LoginBundle{}:
      Update.bundle_cmd(loot, timeout_ms)
    case D.LoginWrite{}:
      Update.write_cmd(loot, lc)
    case D.LoginLock{}:
      Update.lock_cmd(lc)
    case _:
      D.CmdExit{0, SNil{}}

# Opening a step is one thing: the phase records where the run is and the next
# command goes out. A step with nothing to send (the end) opens nothing.
def Update.login_step(+step: D.LoginStep, +loot: D.Loot, +lc: D.LoginCfg, timeout_ms: U32, +m: D.Model) -> D.Step:
  D.mk_step(
    D.Model.set_phase(m, D.PhaseLogin{step, loot}),
    Update.login_cmd(step, loot, lc, timeout_ms) <> Nil{}
  )

# ── what one answer turns into ──────────────────────────────────────────

def Update.both_here(+at: String, +ct0: String) -> Bool:
  C.Cookies.present(at, ct0)

def Update.chrome_key_on(from_keychain: Bool, +loot: D.Loot, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match from_keychain:
    case True{}:
      Update.login_step(D.LoginKey{}, loot, lc, Update.cfg_timeout(m), m)
    case False{}:
      Update.login_step(D.LoginDerive{}, loot, lc, Update.cfg_timeout(m), m)

# `--chrome-key` is the whole reason the Chrome path is testable, and it is also
# the answer on a machine whose key is not in the login keychain. When it is
# absent the password is read from the keychain, and that is the one step that can
# wait for a person.
def Update.chrome_key(+loot: D.Loot, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  Update.chrome_key_on(String.is_empty(Update.loot_password(loot)), loot, lc, m)

def Update.key_taken(blank: Bool, +loot: D.Loot, +password: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match blank:
    case True{}:
      D.mk_step(D.Model.failed(m, Update.login_key_lost()), Nil{})
    case False{}:
      Update.login_step(D.LoginDerive{}, D.Loot.with_password(loot, password), lc, Update.cfg_timeout(m), m)

def Update.key_ready(ok: Bool, +loot: D.Loot, +key: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match ok:
    case False{}:
      D.mk_step(D.Model.failed(m, Update.login_key_lost()), Nil{})
    case True{}:
      Update.login_step(D.LoginDecrypt{}, D.Loot.with_key(loot, key), lc, Update.cfg_timeout(m), m)

def Update.decrypted(blank: Bool, +loot: D.Loot, +at: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match blank:
    case True{}:
      D.mk_step(D.Model.failed(m, Update.login_key_lost()), Nil{})
    case False{}:
      Update.login_step(D.LoginDecrypt2{}, D.Loot.with_at(loot, at), lc, Update.cfg_timeout(m), m)

def Update.decrypted2(blank: Bool, +loot: D.Loot, +ct0: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match blank:
    case True{}:
      D.mk_step(D.Model.failed(m, Update.login_key_lost()), Nil{})
    case False{}:
      Update.login_step(D.LoginClean{}, D.Loot.with_ct0(loot, ct0), lc, Update.cfg_timeout(m), m)

def Update.page_read(ok: Bool, +loot: D.Loot, +url: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match ok:
    case False{}:
      D.mk_step(D.Model.failed(m, Update.login_page_lost()), Nil{})
    case True{}:
      Update.login_step(D.LoginBundle{}, D.Loot.with_url(loot, url), lc, Update.cfg_timeout(m), m)

def Update.bundle_ok(+found: B.Found, +loot: D.Loot, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +cache : String = B.Bundle.cache_text(found, Update.loot_at(loot), Update.loot_ct0(loot))
  Update.login_step(D.LoginWrite{}, D.Loot.with_cache(loot, cache), lc, Update.cfg_timeout(m), m)

def Update.bundle_read(+missing: String, +found: B.Found, +loot: D.Loot, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match missing:
    case "":
      Update.bundle_ok(found, loot, lc, m)
    case _:
      D.mk_step(D.Model.failed(m, Update.login_bundle_lost(missing)), Nil{})

# ── starting ────────────────────────────────────────────────────────────

def Update.first_cookie_step(importing: Bool) -> D.LoginStep:
  match importing:
    case True{}:
      D.LoginCookies{}
    case False{}:
      D.LoginPage{}

def Update.login_first_step(source: String) -> D.LoginStep:
  Update.first_cookie_step(Update.have_source(source))

# The loot opens with the cookies the settings themselves name, and the browser's
# replace them when a source was asked for: the step after the import then reads
# the same two fields either way, and a run with no source is a refresh of the
# bundle for a session that came from a flag or the cache.
def Update.login_open(+lc: D.LoginCfg, +m: D.Model, timeout_ms: U32) -> D.Step:
  loot : D.Loot = D.mk_loot(
    Update.tmp_dir_of(lc),
    SNil{},
    Update.chrome_key_of(lc),
    SNil{},
    Update.session_at(m),
    Update.session_ct0(m),
    SNil{}
  )
  Update.login_step(Update.login_first_step(Update.login_source(lc)), loot, lc, timeout_ms, m)

def Update.login_gate2(+bad: Maybe<&2, D.Error>, +lc: D.LoginCfg, +m: D.Model, timeout_ms: U32) -> D.Step:
  match bad:
    case Some{e}:
      D.mk_step(D.Model.failed(m, e), Nil{})
    case None{}:
      Update.login_open(lc, m, timeout_ms)

def Update.login_gate(+bad_cfg: Maybe<&2, D.Error>, +bad_session: Maybe<&2, D.Error>, +lc: D.LoginCfg, +m: D.Model, timeout_ms: U32) -> D.Step:
  match bad_cfg:
    case Some{e}:
      D.mk_step(D.Model.failed(m, e), Nil{})
    case None{}:
      Update.login_gate2(bad_session, lc, m, timeout_ms)

def Update.login_start(+m: D.Model, timeout_ms: U32) -> D.Step:
  +lc : D.LoginCfg = Update.login_cfg(m)
  Update.login_gate(
    P.Cfg.login_error(lc),
    P.Cfg.session_error(Update.login_source(lc), Update.session_at(m), Update.session_ct0(m)),
    lc,
    m,
    timeout_ms
  )

# ── the end: the cache and the report ───────────────────────────────────

#
# The report is the settings that were written, read back out of the cache the run
# is about to keep, and the two cookies are deliberately not in it: they are in the
# file, and a token printed to a terminal is a token in a scrollback.
def Update.cookie_origin(+source: String) -> String:
  match source:
    case "":
      "the settings this run already had"
    case _:
      "imported from " ++ source

def Update.login_json(+j: J.Json, +path: String, +source: String) -> J.Json:
  J.obj7(
    J.pair("settings_path", J.of_str(path)),
    J.pair("cookies", J.of_str(Update.cookie_origin(source))),
    J.pair("web_bearer", J.get_or_null(j, "--web-bearer")),
    J.pair("op_viewer", J.get_or_null(j, "--op-viewer")),
    J.pair("op_tweet_detail", J.get_or_null(j, "--op-tweet-detail")),
    J.pair("op_search", J.get_or_null(j, "--op-search")),
    J.pair("op_create_tweet", J.get_or_null(j, "--op-create-tweet"))
  )

def Update.login_report(+loot: D.Loot, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +j : J.Json = Update.json_of(J.parse(Update.loot_cache(loot)))
  +path : String = Update.login_settings_path(lc)
  D.mk_step(
    D.Model.done(m, Update.login_json(j, path, Update.login_source(lc)), Nil{}),
    Nil{}
  )

def Update.login_wrote_on(ok: Bool, +path: String, message: String, +loot: D.Loot, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match ok:
    case True{}:
      Update.login_step(D.LoginLock{}, loot, lc, Update.cfg_timeout(m), m)
    case False{}:
      D.mk_step(D.Model.failed(m, Update.login_write_lost(path, message)), Nil{})

# ── an answer to a local program ────────────────────────────────────────

def Update.cookies_next(chrome: Bool, +loot: D.Loot, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match chrome:
    case True{}:
      Update.chrome_key(loot, lc, m)
    case False{}:
      Update.login_step(D.LoginPage{}, loot, lc, Update.cfg_timeout(m), m)

# The next step depends on which browser the cookies came from: Chrome still owes a
# password and two decryptions, Firefox is done.
def Update.cookies_ok(+loot: D.Loot, +at: String, +ct0: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +next : D.Loot = D.Loot.with_at(D.Loot.with_ct0(loot, ct0), at)
  Update.cookies_next(Update.is_chrome(Update.login_source(lc)), next, lc, m)

def Update.cookies_taken(both: Bool, +loot: D.Loot, +at: String, +ct0: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match both:
    case False{}:
      D.mk_step(D.Model.failed(m, Update.login_source_lost()), Nil{})
    case True{}:
      Update.cookies_ok(loot, at, ct0, lc, m)

# Firefox's answer is the two cookies, so this is where they are read. Chrome's
# answer is the number of bytes `writefile` wrote -- the blobs are on disk, not in
# the output -- so a Chrome run never comes through here: the step after the import
# is the key, and the cookies arrive from the two decryptions.
def Update.login_cookies_in(+loot: D.Loot, +out: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +at : String = C.Cookies.firefox_at(out)
  +ct0 : String = C.Cookies.firefox_ct0(out)
  Update.cookies_taken(Update.both_here(at, ct0), loot, at, ct0, lc, m)

def Update.login_key_in(+loot: D.Loot, +out: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +password : String = String.trim(out)
  Update.key_taken(String.is_empty(password), loot, password, lc, m)

def Update.login_derive_in(+loot: D.Loot, +out: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +key : String = C.Cookies.key_of(out)
  Update.key_ready(C.Cookies.key_ok(key), loot, key, lc, m)

def Update.login_decrypt_in(+loot: D.Loot, +out: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +at : String = C.Cookies.chrome_value(out)
  Update.decrypted(String.is_empty(at), loot, at, lc, m)

def Update.login_decrypt2_in(+loot: D.Loot, +out: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +ct0 : String = C.Cookies.chrome_value(out)
  Update.decrypted2(String.is_empty(ct0), loot, ct0, lc, m)

# The login settings are recomputed here rather than carried: what the login flow
# needs out of them is the same in every step, and a def may not bind a local
# before a `match` that reads one of its parameters, which is the shape the two
# answers below both have.
def Update.login_cookies_on(chrome: Bool, +loot: D.Loot, +out: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  match chrome:
    case True{}:
      Update.chrome_key(loot, lc, m)
    case False{}:
      Update.login_cookies_in(loot, out, lc, m)

def Update.login_proc_on(step: D.LoginStep, +loot: D.Loot, +out: String, +m: D.Model, +lc: D.LoginCfg) -> D.Step:
  match step:
    case D.LoginCookies{}:
      Update.login_cookies_on(Update.is_chrome(Update.login_source(lc)), loot, out, lc, m)
    case D.LoginKey{}:
      Update.login_key_in(loot, out, lc, m)
    case D.LoginDerive{}:
      Update.login_derive_in(loot, out, lc, m)
    case D.LoginDecrypt{}:
      Update.login_decrypt_in(loot, out, lc, m)
    case D.LoginDecrypt2{}:
      Update.login_decrypt2_in(loot, out, lc, m)
    case D.LoginClean{}:
      Update.login_step(D.LoginPage{}, loot, lc, Update.cfg_timeout(m), m)
    case D.LoginLock{}:
      Update.login_report(loot, lc, m)
    case _:
      D.mk_step(D.Model.failed(m, Update.login_internal()), Nil{})

# A non-zero exit from a local program is not read as data: the step that asked
# for it says what an empty answer meant already, and `sqlite3` on a database that
# is not there would otherwise look like a browser with no session.
def Update.login_proc_phase(+p: D.Phase, +out: String, +m: D.Model) -> D.Step:
  match p:
    case D.PhaseLogin{step, loot}:
      Update.login_proc_on(step, loot, out, m, Update.login_cfg(m))
    case _:
      D.mk_step(D.Model.failed(m, Update.login_internal()), Nil{})

# ── an answer to the page and the bundle ────────────────────────────────

def Update.login_page_in(+loot: D.Loot, +body: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +url : String = B.Bundle.identify(Update.login_bundle_base(lc), body)
  Update.page_read(B.Bundle.identified(Update.login_bundle_base(lc), body), loot, url, lc, m)

def Update.login_bundle_in(+loot: D.Loot, +body: String, +lc: D.LoginCfg, +m: D.Model) -> D.Step:
  +found : B.Found = B.Bundle.found(body)
  Update.bundle_read(B.Bundle.missing(found), found, loot, lc, m)

def Update.login_http_in(step: D.LoginStep, +loot: D.Loot, +body: String, +m: D.Model, +lc: D.LoginCfg) -> D.Step:
  match step:
    case D.LoginPage{}:
      Update.login_page_in(loot, body, lc, m)
    case D.LoginBundle{}:
      Update.login_bundle_in(loot, body, lc, m)
    case _:
      D.mk_step(D.Model.failed(m, Update.login_internal()), Nil{})

def Update.login_http_phase(+p: D.Phase, +body: String, +m: D.Model) -> D.Step:
  match p:
    case D.PhaseLogin{step, loot}:
      Update.login_http_in(step, loot, body, m, Update.login_cfg(m))
    case _:
      D.mk_step(D.Model.failed(m, Update.login_internal()), Nil{})

# ── resolving and routing ───────────────────────────────────────────────

# `--text-file` fills the text of a write when `--text` was not given, so the
# file is a way to avoid quoting rather than an override.
def Update.with_file_text_on(has_text: Bool, +v: D.Verb, +text: String) -> D.Verb:
  match has_text:
    case True{}:
      v
    case False{}:
      D.Verb.set_text(v, text)

def Update.with_file_text(+v: D.Verb, +text: String) -> D.Verb:
  Update.with_file_text_on(D.Verb.has_text(v), v, text)

# The count is applied here rather than at parse time because it is a value, not
# a flag: `--count` set in the config file or the environment is not readable
# until both have been read.
def Update.count_in(+s: D.Start) -> U32:
  P.Cfg.count_on(Update.items_in(s), Update.env_in(s), Update.rc_in(s), P.Cfg.default_count())

# `check` answers without a request, and what it can honestly report is what the
# settings resolved to: which engine would answer, and where the credentials came
# from. A `check` that called X would be `whoami`, which is a different verb.
def Update.check_report(+cfg: D.RunCfg) -> J.Json:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      J.obj_of(J.pairs4(
        J.pair("engine", J.of_str(D.Engine.name(engine))),
        J.pair("credentials", J.of_str(D.Creds.source(creds))),
        J.pair("operations", J.obj_of(J.pairs4(
          J.pair("create_tweet", J.of_str(op_create_tweet)),
          J.pair("tweet_detail", J.of_str(op_tweet_detail)),
          J.pair("search", J.of_str(op_search)),
          J.pair("viewer", J.of_str(op_viewer))
        ))),
        J.pair("timeout_ms", J.of_u32(timeout_ms))
      ))

# The verbs that answer on their own carry their answer as their payload, so the
# renderer never has to know which verb it is looking at. `help` prints the
# manual, `schema` the manifest an agent reads before it types anything, and
# `version` the build.
def Update.local_payload(+v: D.Verb, +cfg: D.RunCfg) -> J.Json:
  match v:
    case D.VerbHelp{}:
      J.of_str(A.Argv.help_text())
    case D.VerbSchema{}:
      A.Argv.schema_json()
    case D.VerbVersion{}:
      J.obj_of(J.pairs1(J.pair("version", J.of_str(D.version()))))
    case D.VerbCheck{}:
      Update.check_report(cfg)
    case _:
      J.null()

def Update.answer_local(+m: D.Model) -> D.Step:
  D.mk_step(D.Model.done(m, Update.local_payload(Update.verb_of(m), Update.cfg_of(m)), Nil{}), D.no_cmds())

def Update.described_on(+p: Api.Plan, +m: D.Model) -> D.Step:
  match p:
    case Api.PlanSend{cmd}:
      D.mk_step(D.Model.done(m, Api.Api.describe(cmd), Nil{}), D.no_cmds())
    case Api.PlanStop{error}:
      D.mk_step(D.Model.failed(m, error), D.no_cmds())

# A write that carries attachments goes down the media road instead: several
# requests, and a final one that cannot be built until the uploads have named
# their ids. Every other verb takes the one-request road unchanged.
def Update.media_present(+m: D.Model) -> Bool:
  Bool.not(List.is_empty(&2, D.Media, D.Verb.media_of(Update.verb_of(m))))

def Update.media_described_on(+e: Maybe<&2, D.Error>, +m: D.Model) -> D.Step:
  match e:
    case Some{error}:
      D.mk_step(D.Model.failed(m, error), D.no_cmds())
    case None{}:
      D.mk_step(D.Model.done(m, Api.Api.describe_media(Update.cfg_of(m), Update.id_media()), Nil{}), D.no_cmds())

# The queue opens with its first command and waits. `PhaseMedia` carries the whole
# queue, head included, so the answer handler can pop it; `done` collects the ids
# in reverse, newest first, which is what an alt job needs and what the finale
# flips back into posting order.
def Update.media_queue_on(+jobs: List<&2, D.MediaJob>, +m: D.Model) -> D.Step:
  match jobs:
    case Nil{}:
      D.mk_step(D.Model.failed(m, Api.Api.media_internal()), D.no_cmds())
    case +h <> rest:
      D.mk_step(
        D.Model.set_phase(m, D.PhaseMedia{jobs, Nil{}}),
        Api.Api.media_cmd(Update.cfg_of(m), SNil{}, h, Update.id_media()) <> Nil{}
      )

# The credential gate is asked before a single byte moves: an API key cannot sign
# for X's upload endpoint, and finding that out mid-queue would leave a half-run.
def Update.media_open_on(+e: Maybe<&2, D.Error>, +m: D.Model) -> D.Step:
  match e:
    case Some{error}:
      D.mk_step(D.Model.failed(m, error), D.no_cmds())
    case None{}:
      Update.media_queue_on(Api.Api.media_jobs(D.Verb.media_of(Update.verb_of(m))), m)

def Update.described_route(has_media: Bool, +m: D.Model) -> D.Step:
  match has_media:
    case True{}:
      Update.media_described_on(Api.Api.media_gate_cfg(Update.cfg_of(m)), m)
    case False{}:
      Update.described_on(Api.Api.plan(Update.cfg_of(m), Update.id_request()), m)

def Update.described(+m: D.Model) -> D.Step:
  Update.described_route(Update.media_present(m), m)

def Update.sending_on(+p: Api.Plan, +m: D.Model) -> D.Step:
  match p:
    case Api.PlanSend{cmd}:
      D.mk_step(D.Model.waiting(m, Update.id_request()), cmd <> Nil{})
    case Api.PlanStop{error}:
      D.mk_step(D.Model.failed(m, error), D.no_cmds())

def Update.sending_route(has_media: Bool, +m: D.Model) -> D.Step:
  match has_media:
    case True{}:
      Update.media_open_on(Api.Api.media_gate_cfg(Update.cfg_of(m)), m)
    case False{}:
      Update.sending_on(Api.Api.plan(Update.cfg_of(m), Update.id_request()), m)

def Update.sending(+m: D.Model) -> D.Step:
  Update.sending_route(Update.media_present(m), m)

# `--fixture` answers one request. A media write is several, and the ones after
# the first depend on ids the fixture cannot invent, so the flag is refused by
# name rather than answered with a body that would have to be a lie.
def Update.media_fixture_error() -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "--fixture answers a single request, and a media write is several",
    "drop --fixture, or pass --dry-run to inspect the plan"
  )

def Update.fixture_path_on(has_media: Bool, +m: D.Model, fixture: String) -> D.Step:
  match has_media:
    case True{}:
      D.mk_step(D.Model.failed(m, Update.media_fixture_error()), D.no_cmds())
    case False{}:
      Update.answered(m, 200, fixture, SNil{})

def Update.send_or_fixture_on(no_fixture: Bool, +m: D.Model, fixture: String) -> D.Step:
  match no_fixture:
    case True{}:
      Update.sending(m)
    case False{}:
      Update.fixture_path_on(Update.media_present(m), m, fixture)

def Update.send_or_fixture(+m: D.Model, +fixture: String) -> D.Step:
  Update.send_or_fixture_on(String.is_empty(fixture), m, fixture)

def Update.dry_or_send(dry: Bool, +m: D.Model, fixture: String) -> D.Step:
  match dry:
    case True{}:
      Update.described(m)
    case False{}:
      Update.send_or_fixture(m, fixture)

def Update.dispatch_on(net_needed: Bool, +m: D.Model, dry: Bool, fixture: String) -> D.Step:
  match net_needed:
    case False{}:
      Update.answer_local(m)
    case True{}:
      Update.dry_or_send(dry, m, fixture)

# ── an answer to a media request ────────────────────────────────────────
#
# The same fold, one queue longer. Which step answered is the phase rather than
# the id, because every media request shares one id and only the queue knows
# where it is. The steps below pop the head, keep the id an upload produced, and
# only build the post once the queue is empty.

def Update.nonempty_str(s: String) -> Maybe<&2, String>:
  match s:
    case "":
      None{}
    case _:
      Some{s}

def Update.media_id_kept(found: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{s}:
      Update.nonempty_str(s)
    case None{}:
      None{}

def Update.media_id_text(+x: J.Json) -> Maybe<&2, String>:
  Update.media_id_kept(J.text_of(x))

# `media_id_string` is X's string form and `media_id` the number beside it.
# Either answers the question; the string is preferred because it is what the
# upload endpoints are documented to return.
def Update.media_id_second(found: Maybe<&2, J.Json>) -> Maybe<&2, String>:
  match found:
    case Some{x}:
      Update.media_id_text(x)
    case None{}:
      None{}

def Update.media_id_first(found: Maybe<&2, J.Json>, +j: J.Json) -> Maybe<&2, String>:
  match found:
    case Some{x}:
      Update.media_id_text(x)
    case None{}:
      Update.media_id_second(J.get(j, "media_id"))

def Update.media_id_of(+j: J.Json) -> Maybe<&2, String>:
  Update.media_id_first(J.get(j, "media_id_string"), j)

def Update.media_id_in(+p: J.Parsed) -> Maybe<&2, String>:
  match p:
    case J.ParsedOk{value}:
      Update.media_id_of(value)
    case J.ParsedErr{message}:
      None{}

# An upload that X accepted without naming a media id cannot be attached to
# anything, so it is a failure rather than a post that quietly loses a file.
def Update.media_no_id() -> D.Error:
  D.err_hint(
    D.ErrUpstream{},
    "the upload was accepted without a media id",
    "X's answer had neither media_id_string nor media_id; try again"
  )

def Update.head_or_blank(found: Maybe<&2, String>) -> String:
  match found:
    case Some{s}:
      s
    case None{}:
      SNil{}

def Update.media_last(+done: List<&2, String>) -> String:
  Update.head_or_blank(List.head(&2, String, done))

# An alt job names the media under it by the id the upload just collected, which
# is the head of `done` at this moment.
def Update.media_continue(+rest: List<&2, D.MediaJob>, +done: List<&2, String>, +m: D.Model) -> D.Step:
  match rest:
    case Nil{}:
      Update.sending_on(Api.Api.media_tweet(Update.cfg_of(m), List.reverse(&2, String, done), Update.id_request()), m)
    case +h <> tail:
      D.mk_step(
        D.Model.set_phase(m, D.PhaseMedia{rest, done}),
        Api.Api.media_cmd(Update.cfg_of(m), Update.media_last(done), h, Update.id_media()) <> Nil{}
      )

def Update.media_uploaded(found: Maybe<&2, String>, +rest: List<&2, D.MediaJob>, +done: List<&2, String>, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match found:
    case Some{media_id}:
      Update.media_continue(rest, media_id <> done, m)
    case None{}:
      D.mk_step(D.Model.with_notes(D.Model.failed_status(m, http_status, Update.media_no_id(), body), Update.media_fail_notes(m, stderr)), D.no_cmds())

def Update.media_step(+jobs: List<&2, D.MediaJob>, +done: List<&2, String>, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match jobs:
    case Nil{}:
      D.mk_step(D.Model.failed(m, Api.Api.media_internal()), D.no_cmds())
    case +h <> rest:
      match h:
        case D.JobUpload{media}:
          Update.media_uploaded(Update.media_id_in(J.parse(body)), rest, done, http_status, body, stderr, m)
        case D.JobAlt{text}:
          Update.media_continue(rest, done, m)

def Update.media_landed_on(+p: D.Phase, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match p:
    case D.PhaseMedia{jobs, done}:
      Update.media_step(jobs, done, http_status, body, stderr, m)
    case _:
      D.mk_step(D.Model.failed(m, Api.Api.media_internal()), D.no_cmds())

def Update.media_landed(+m: D.Model, +http_status: U32, +body: String, +stderr: String) -> D.Step:
  Update.media_landed_on(Update.phase_in(m), http_status, body, stderr, m)

def Update.media_status_ok(+e: Maybe<&2, D.Error>, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match e:
    case Some{x}:
      D.mk_step(D.Model.with_notes(D.Model.failed_status(m, http_status, x, body), Update.media_fail_notes(m, stderr)), D.no_cmds())
    case None{}:
      Update.media_landed(m, http_status, body, stderr)

def Update.media_answer_on(+e: Maybe<&2, D.Error>, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match e:
    case Some{x}:
      D.mk_step(D.Model.with_notes(D.Model.failed_status(m, http_status, x, body), Update.media_fail_notes(m, stderr)), D.no_cmds())
    case None{}:
      Update.media_status_ok(H.Http.status_error(H.Resp{http_status, body}), http_status, body, stderr, m)

def Update.media_answer(curl_status: U32, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  Update.media_answer_on(H.Http.transport_error(curl_status), http_status, body, stderr, m)

def Update.media_phase_on(+p: D.Phase) -> Bool:
  match p:
    case D.PhaseMedia{jobs, done}:
      True{}
    case _:
      False{}

def Update.is_media_phase(+m: D.Model) -> Bool:
  Update.media_phase_on(Update.phase_in(m))

# The two roads out of an answer. The plain one keeps the body as the run's
# payload; the media one hands the body to the queue and only keeps it as the
# payload when the post itself answers, which is why the two cannot share a tail.
def Update.answer_plain(is_media: Bool, curl_status: U32, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match is_media:
    case True{}:
      Update.media_answer(curl_status, http_status, body, stderr, m)
    case False{}:
      Update.transport_ok(H.Http.transport_error(curl_status), http_status, body, stderr, m)

# A login answer is not JSON and has no status contract, so it takes the branch
# before the transport's own reading: the page and the bundle are read for what is
# in them, and a body without it is what a refusal looks like.
def Update.answer_route(login: Bool, is_media: Bool, curl_status: U32, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match login:
    case True{}:
      Update.login_http_phase(Update.phase_in(m), body, m)
    case False{}:
      Update.answer_plain(is_media, curl_status, http_status, body, stderr, m)

def Update.answer_kind(is_media: Bool, curl_status: U32, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  Update.answer_route(Update.is_login_phase(m), is_media, curl_status, http_status, body, stderr, m)

def Update.http_matched(ok: Bool, curl_status: U32, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match ok:
    case True{}:
      Update.answer_kind(Update.is_media_phase(m), curl_status, http_status, body, stderr, m)
    case False{}:
      D.Step.only(m)

def Update.http_ok(id: U32, curl_status: U32, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  Update.http_matched(Update.matches(m, id), curl_status, http_status, body, stderr, m)

# A write with no text is refused here, after the text file has been merged in:
# `bird tweet` on its own must not post an empty tweet, and the check cannot
# happen any earlier, because the text may be exactly what the file held.
# The media rules are checked here, before a request exists to attach anything
# to. Only the verbs that carry media are asked, so `bird read --media x` stays a
# command line that happens to have a stray flag rather than a post that was
# refused.
def Update.media_error_on(writes: Bool, +v: D.Verb, +s: D.Start) -> Maybe<&2, D.Error>:
  match writes:
    case True{}:
      P.Cfg.media_error(Update.items_in(s), Update.env_in(s), Update.rc_in(s))
    case False{}:
      None{}

def Update.media_error(+v: D.Verb, +m: D.Model) -> Maybe<&2, D.Error>:
  Update.media_error_on(D.Verb.writes(v), v, Update.start_of(m))

def Update.media_gated_on(+e: Maybe<&2, D.Error>, +v: D.Verb, +m: D.Model, dry: Bool, fixture: String) -> D.Step:
  match e:
    case Some{error}:
      D.mk_step(D.Model.failed(m, error), D.no_cmds())
    case None{}:
      Update.dispatch_on(D.Verb.needs_network(v), D.Model.with_verb(m, v), dry, fixture)

# A number that cannot be read is refused before the media rules are consulted,
# because it is a typo in the settings rather than a problem with the post: the
# caller wrote something the program could not understand either way.
def Update.number_error(+m: D.Model) -> Maybe<&2, D.Error>:
  P.Cfg.number_error(Update.items_in(Update.start_of(m)), Update.env_in(Update.start_of(m)), Update.rc_in(Update.start_of(m)))

# A target with no id in it is the same class of mistake as a number that is not
# one: it is in what the caller wrote, so it is refused here, before the media
# rules are consulted and long before a request exists.
def Update.target_gated_on(+e: Maybe<&2, D.Error>, +v: D.Verb, +m: D.Model, dry: Bool, fixture: String) -> D.Step:
  match e:
    case Some{error}:
      D.mk_step(D.Model.failed(m, error), D.no_cmds())
    case None{}:
      Update.media_gated_on(Update.media_error(v, m), v, m, dry, fixture)

def Update.values_gated_on(+e: Maybe<&2, D.Error>, +v: D.Verb, +m: D.Model, dry: Bool, fixture: String) -> D.Step:
  match e:
    case Some{error}:
      D.mk_step(D.Model.failed(m, error), D.no_cmds())
    case None{}:
      Update.target_gated_on(P.Cfg.target_error(v), v, m, dry, fixture)

def Update.ready_on(blank: Bool, +v: D.Verb, +m: D.Model, dry: Bool, fixture: String) -> D.Step:
  match blank:
    case True{}:
      D.mk_step(D.Model.failed(m, P.Cfg.no_text_error(v)), D.no_cmds())
    case False{}:
      Update.values_gated_on(Update.number_error(m), v, m, dry, fixture)

# The verb as it will actually be sent: the count from every source, and the text
# from the file if the command line did not carry any.
def Update.merged_verb(+verb: D.Verb, +m: D.Model) -> D.Verb:
  Update.with_file_text(
    D.Verb.set_count(verb, Update.count_in(Update.start_of(m))),
    Update.text_in(Update.start_of(m))
  )

# `login` is answered before the ordinary road because it is not a request: it is
# a queue of local programs and two requests of its own, and nothing the transport
# builds applies to it. Every other verb takes the road it took before.
# The config is put on the model before the login flow starts, because the flow
# answers with the verb it ran: without this the report came out as `"verb":"help"`,
# which is the initial model's default and a lie about what the run did.
def Update.route_on(login: Bool, +verb: D.Verb, +m: D.Model, +cfg: D.RunCfg, dry_run: Bool, timeout_ms: U32, +fixture: String) -> D.Step:
  match login:
    case True{}:
      Update.login_start(D.Model.with_cfg(m, cfg), timeout_ms)
    case False{}:
      # The fixture that answers is the file's text, not the path the setting
      # named: `fixture_path` is where to look, and the read put the contents in
      # the start's fixture. Passing the path here answers every run with a
      # filename.
      Update.ready_on(
        P.Cfg.blank_write(verb, Update.text_in(Update.start_of(m))),
        Update.merged_verb(verb, m),
        D.Model.with_cfg(m, cfg),
        dry_run,
        fixture
      )

def Update.routed(+m: D.Model, +cfg: D.RunCfg) -> D.Step:
  match cfg:
    case D.RunCfg{+verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      Update.route_on(
        Update.is_login(verb),
        verb,
        m,
        cfg,
        dry_run,
        timeout_ms,
        Update.fixture_in(Update.start_of(m))
      )

def Update.resolve(+m: D.Model) -> D.Step:
  Update.routed(m, P.Cfg.resolve(
    Update.items_in(Update.start_of(m)),
    Update.env_in(Update.start_of(m)),
    Update.rc_in(Update.start_of(m)),
    Update.tty_in(Update.start_of(m)),
    Update.config_path_in(Update.start_of(m))
  ))

# ── the rounds ──────────────────────────────────────────────────────────
#
# A round is opened by issuing its reads and closed when every one of them has
# answered, which `pending` counts. The interpreter runs them in order -- they are
# two small file reads and it cannot fan out (see `src/effects.bend`) -- and the
# fold does not care either way: it sees the answers, not the schedule.

def Update.open_round(+s: D.Start, cmds: List<&2, D.Cmd>) -> D.Start:
  D.Start.with_pending(s, List.length(&2, D.Cmd, cmds))

def Update.gather(+model: D.Model, +s: D.Start, +cmds: List<&2, D.Cmd>) -> D.Step:
  D.mk_step(D.Model.gathering(model, Update.open_round(s, cmds)), cmds)

def Update.files_round_on(none: Bool, +model: D.Model, +s: D.Start) -> D.Step:
  match none:
    case True{}:
      Update.resolve(D.Model.gathering(model, D.Start.with_stage(s, D.StageDone{})))
    case False{}:
      Update.gather(model, D.Start.with_stage(s, D.StageFiles{}), Update.second_reads(s))

def Update.files_round(+model: D.Model, +s: D.Start) -> D.Step:
  Update.files_round_on(List.is_empty(&2, D.Cmd, Update.second_reads(s)), model, s)

# The first round opens when it has something to read, and that is now two files
# rather than one: the config file, if a run named one, and the settings cache
# `login` writes, if the path resolved to one. Asking `first_reads` rather than the
# config path is what keeps a run with no `--config` from skipping the cache too,
# which it did until a scenario with no flags at all caught it.
def Update.config_round_on(first_none: Bool, +model: D.Model, +s: D.Start) -> D.Step:
  match first_none:
    case True{}:
      Update.files_round(model, D.Start.with_stage(s, D.StageFiles{}))
    case False{}:
      Update.gather(model, D.Start.with_stage(s, D.StageConfig{}), Update.first_reads(s))

def Update.config_round(+model: D.Model, +s: D.Start) -> D.Step:
  Update.config_round_on(List.is_empty(&2, D.Cmd, Update.first_reads(s)), model, s)

def Update.begin(+items: List<&2, D.Item>, +env: List<&2, D.Item>, tty: Bool, config_path: String, model: D.Model) -> D.Step:
  Update.config_round(model, D.mk_start(D.StageConfig{}, items, env, Nil{}, tty, config_path, SNil{}, SNil{}, 0n))

# ── a read landed ───────────────────────────────────────────────────────

def Update.round_over_on(+st: D.Stage, +m: D.Model) -> D.Step:
  match st:
    case D.StageConfig{}:
      Update.files_round(m, D.Start.with_stage(Update.start_of(m), D.StageFiles{}))
    case D.StageFiles{}:
      Update.resolve(m)
    case D.StageDone{}:
      Update.resolve(m)

def Update.landed_on(zero: Bool, +m: D.Model) -> D.Step:
  match zero:
    case True{}:
      Update.round_over_on(Update.stage_of(Update.start_of(m)), m)
    case False{}:
      D.Step.only(m)

def Update.landed(+m: D.Model) -> D.Step:
  Update.landed_on(Nat.is_eq(Update.pending_in(Update.start_of(m)), 0n), m)

# ── the config file ─────────────────────────────────────────────────────
#
# Its keys are flag names and its values are the setting's text, so one setting
# is spelled the same way in a file as on the command line. A key the flag table
# does not know is refused by name: a config file that is quietly ignored is a
# setting that silently does nothing.

# A content flag in a config file is refused for the same reason an unknown key
# is: a key that is accepted and then ignored is a setting that silently does
# nothing. `Update.rc_error` says which of the two it was.
def Update.rc_content_on(content: Bool, +key: String, +so_far: Maybe<&2, String>) -> Maybe<&2, String>:
  match content:
    case True{}:
      Some{key}
    case False{}:
      so_far

def Update.rc_pick(kind: A.FlagKind, +key: String, +so_far: Maybe<&2, String>) -> Maybe<&2, String>:
  match kind:
    case A.FkUnknown{}:
      Some{key}
    case _:
      Update.rc_content_on(P.Cfg.content_flag(key), key, so_far)

# The last unknown key wins, which is all an error message needs. One
# self-recursive def over the names, so no helper has to call back into it.
def Update.rc_unknown(+names: List<&2, String>, so_far: Maybe<&2, String>) -> Maybe<&2, String>:
  match names:
    case Nil{}:
      so_far
    case +h <> rest:
      Update.rc_unknown(rest, Update.rc_pick(A.Argv.kind_of(h), h, so_far))

def Update.rc_bad_key(+json: J.Json) -> Maybe<&2, String>:
  Update.rc_unknown(J.keys(json), None{})

def Update.rc_note(path: String) -> String:
  "in " ++ path ++ ": "

def Update.rc_error(path: String, +name: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    Update.rc_note(path) ++ "not a setting: " ++ name,
    "a config file holds settings such as --engine or --count; the text and the media of one post go on the command line"
  )

def Update.rc_bad(path: String, +message: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    Update.rc_note(path) ++ "the config file is not usable: " ++ message,
    "{\"--auth-token\": \"...\", \"--count\": 5} is the shape"
  )

# Appended rather than replaced: the settings cache lands in the same round and
# prepends, so `cache ++ config` holds whichever order the two reads answered in,
# and the resolver's last-match-wins puts the config file ahead of the cache.
def Update.rc_checked_on(+bad: Maybe<&2, String>, +m: D.Model, +json: J.Json) -> D.Step:
  match bad:
    case Some{name}:
      D.mk_step(D.Model.failed(m, Update.rc_error(Update.config_at(m), name)), D.no_cmds())
    case None{}:
      Update.landed(D.Model.gathering(m, D.Start.one_less(D.Start.with_rc(
        Update.start_of(m),
        List.append(&2, D.Item, Update.rc_in(Update.start_of(m)), P.Cfg.rc_items(J.fields(json)))
      ))))

def Update.rc_checked(+m: D.Model, +json: J.Json) -> D.Step:
  Update.rc_checked_on(Update.rc_bad_key(json), m, json)

def Update.rc_obj(is_object: Bool, +m: D.Model, +json: J.Json) -> D.Step:
  match is_object:
    case False{}:
      D.mk_step(D.Model.failed(m, Update.rc_bad(Update.config_at(m), "it is not a JSON object")), D.no_cmds())
    case True{}:
      Update.rc_checked(m, json)

def Update.rc_landed_on(+p: J.Parsed, +m: D.Model) -> D.Step:
  match p:
    case J.ParsedOk{value}:
      Update.rc_obj(J.is_obj(value), m, value)
    case J.ParsedErr{message}:
      D.mk_step(D.Model.failed(m, Update.rc_bad(Update.config_at(m), message)), D.no_cmds())

def Update.rc_landed(+m: D.Model, text: String) -> D.Step:
  Update.rc_landed_on(J.parse(text), m)

# ── the text file and the fixture landed ────────────────────────────────

def Update.recorded_on(is_text: Bool, +s: D.Start, text: String) -> D.Start:
  match is_text:
    case True{}:
      D.Start.with_text(s, text)
    case False{}:
      D.Start.with_fixture(s, text)

def Update.recorded(+s: D.Start, id: U32, text: String) -> D.Start:
  Update.recorded_on(U32.is_eq(id, Update.id_text()), s, text)

def Update.read_landed(+m: D.Model, +id: U32, text: String) -> D.Step:
  Update.landed(D.Model.gathering(m, D.Start.one_less(Update.recorded(Update.start_of(m), id, text))))

# The settings cache is the third file whose contents are settings. It is read
# this way rather than through the config path because its keys are the same flag
# names and it has to lose to the config file, which prepending gives.
#
# A cache that is not a JSON object is refused by name rather than ignored: a
# setting that silently does nothing is the failure this whole design avoids, and
# the path it names is what a person deletes.
def Update.settings_at(+m: D.Model) -> String:
  P.Cfg.settings_path_on(
    Update.items_in(Update.start_of(m)),
    Update.env_in(Update.start_of(m)),
    Update.rc_in(Update.start_of(m))
  )

def Update.cache_bad(+j: J.Json) -> Bool:
  Bool.not(J.is_obj(j))

def Update.cache_error(path: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "the settings cache is not usable: " ++ path,
    "delete it, or run `bird login` again: it does not read the cache it writes"
  )

def Update.cache_landed_on(+bad: Bool, +path: String, +m: D.Model, +p: J.Parsed) -> D.Step:
  match bad:
    case True{}:
      D.mk_step(D.Model.failed(m, Update.cache_error(path)), D.no_cmds())
    case False{}:
      Update.landed(D.Model.gathering(m, D.Start.one_less(D.Start.with_rc(
        Update.start_of(m),
        List.append(&2, D.Item, P.Cfg.rc_items(J.fields(Update.json_of(p))), Update.rc_in(Update.start_of(m)))
      ))))

def Update.cache_landed(+m: D.Model, text: String) -> D.Step:
  +p : J.Parsed = J.parse(text)
  Update.cache_landed_on(Update.cache_bad(Update.json_of(p)), Update.settings_at(m), m, p)

def Update.file_ok_other(is_settings: Bool, id: U32, +text: String, +model: D.Model) -> D.Step:
  match is_settings:
    case True{}:
      Update.cache_landed(model, text)
    case False{}:
      Update.read_landed(model, id, text)

def Update.file_ok_on(is_config: Bool, is_settings: Bool, id: U32, text: String, +model: D.Model) -> D.Step:
  match is_config:
    case True{}:
      Update.rc_landed(model, text)
    case False{}:
      Update.file_ok_other(is_settings, id, text, model)

def Update.file_ok(+id: U32, text: String, +model: D.Model) -> D.Step:
  Update.file_ok_on(
    U32.is_eq(id, Update.id_config()),
    U32.is_eq(id, Update.id_settings()),
    id,
    text,
    model
  )

def Update.file_error(path: String, +message: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "cannot read the file this run was asked for: " ++ path,
    message
  )

# A config file that cannot be read is the one failure the run shrugs off, and
# it still has to close the round it opened: leaving `pending` at 1 would stall a
# run that has nothing left to wait for.
def Update.file_fail_on(optional: Bool, path: String, message: String, +model: D.Model) -> D.Step:
  match optional:
    case True{}:
      Update.landed(D.Model.gathering(model, D.Start.one_less(Update.start_of(model))))
    case False{}:
      D.mk_step(D.Model.failed(model, Update.file_error(path, message)), D.no_cmds())

def Update.file_fail(+id: U32, path: String, message: String, +model: D.Model) -> D.Step:
  Update.file_fail_on(
    Bool.or(U32.is_eq(id, Update.id_config()), U32.is_eq(id, Update.id_settings())),
    path,
    message,
    model
  )

# ── answers from the login flow ─────────────────────────────────────────
#
# Only the login phase answers these two, and only under the login id, so a
# message that answers nothing is ignored rather than folded -- the same rule the
# requests use.

def Update.proc_matched(ok: Bool, +out: String, +m: D.Model) -> D.Step:
  match ok:
    case True{}:
      Update.login_proc_phase(Update.phase_in(m), out, m)
    case False{}:
      D.Step.only(m)

def Update.proc_ok(id: U32, status: U32, +out: String, +err: String, +m: D.Model) -> D.Step:
  Update.proc_matched(U32.is_eq(id, Update.id_login()), out, m)

def Update.wrote_phase_on(+p: D.Phase, +ok: Bool, +path: String, +message: String, +m: D.Model) -> D.Step:
  match p:
    case D.PhaseLogin{step, loot}:
      Update.login_wrote_on(ok, path, message, loot, Update.login_cfg(m), m)
    case _:
      D.mk_step(D.Model.failed(m, Update.login_internal()), D.no_cmds())

def Update.wrote_matched(ok: Bool, +path: String, +wrote: Bool, +message: String, +m: D.Model) -> D.Step:
  match ok:
    case True{}:
      Update.wrote_phase_on(Update.phase_in(m), wrote, path, message, m)
    case False{}:
      D.Step.only(m)

def Update.wrote(id: U32, +path: String, +ok: Bool, +message: String, +m: D.Model) -> D.Step:
  Update.wrote_matched(U32.is_eq(id, Update.id_login()), path, ok, message, m)

# ── entry ───────────────────────────────────────────────────────────────

def Update.initial() -> D.Model:
  D.mk_model(
    D.PhaseInit{},
    D.mk_start(D.StageConfig{}, Nil{}, Nil{}, Nil{}, False{}, SNil{}, SNil{}, SNil{}, 0n),
    P.Cfg.resolve(Nil{}, Nil{}, Nil{}, False{}, SNil{}),
    0,
    J.null(),
    SNil{},
    0,
    Nil{}
  )

def Update.classified(parsed: A.Argv, env: List<&2, D.Item>, tty: Bool, config_path: String, +model: D.Model) -> D.Step:
  match parsed:
    case A.ArgvOk{items}:
      Update.begin(items, env, tty, config_path, model)
    case A.ArgvBad{error}:
      D.mk_step(D.Model.failed(model, error), D.no_cmds())

def Update.started(+args: List<&2, String>, +env: List<&2, D.Item>, tty: Bool, config_path: String, +model: D.Model) -> D.Step:
  Update.classified(A.Argv.parse(args), env, tty, config_path, model)

# ── a failure ends the run ──────────────────────────────────────────────
#
# Nothing that arrives after a failure changes it, and that is a rule rather than
# a detail: a round can have two answers in flight, so a config file that is
# refused by name while the settings cache is still being read would otherwise be
# *revived* by the cache's own landing -- and the run would report success with the
# default verb, because the model the answer landed on was the one it replaced.
# `tests/e2e.sh` found this with a config key the flag table does not know.

def Update.is_failed_phase(+p: D.Phase) -> Bool:
  match p:
    case D.PhaseFailed{error}:
      True{}
    case _:
      False{}

def Update.dispatch(msg: D.Msg, model: D.Model) -> D.Step:
  match msg:
    case D.MsgStart{args, env, tty, config_path}:
      Update.started(args, env, tty, config_path, model)
    case D.MsgFileOk{id, path, why, text}:
      Update.file_ok(id, text, model)
    case D.MsgFileFail{id, path, why, code, message}:
      Update.file_fail(id, path, message, model)
    case D.MsgHttpOk{id, curl_status, http_status, body, stderr}:
      Update.http_ok(id, curl_status, http_status, body, stderr, model)
    case D.MsgProc{id, status, out, err}:
      Update.proc_ok(id, status, out, err, model)
    case D.MsgWrote{id, path, ok, message}:
      Update.wrote(id, path, ok, message, model)

def Update.step_over(failed: Bool, +msg: D.Msg, +model: D.Model) -> D.Step:
  match failed:
    case True{}:
      D.Step.only(model)
    case False{}:
      Update.dispatch(msg, model)

def Update.step(msg: D.Msg, +model: D.Model) -> D.Step:
  Update.step_over(Update.is_failed_phase(Update.phase_in(model)), msg, model)
