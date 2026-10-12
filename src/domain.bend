import Base
import ./json.bend as J

# The vocabulary of the app: every value the fold passes around.
#
# Architectural shape (Elm/Redux, on the effect-oriented rules underneath):
#
#   Msg  ──update──▶  Step{model, cmds}
#   cmds ──effects─▶  Msg      (each outcome comes back as a message)
#
# `update` is pure and total: it never reads the world and never performs an
# effect. A `Cmd` *describes* an effect and building one touches nothing;
# `src/effects.bend` is the only module that runs one, and it feeds every
# outcome back in as the next message.
#
# Two Bend facts decide the shapes below, and both cost real effort to work
# around, so they are worth naming:
#
#   1. There is no record-update syntax, and a `Data` record is rebuilt field by
#      field, positionally. So the immutable half of the state is separated from
#      the half that changes: `RunCfg` is built once at startup and only ever
#      read (its parameters are `+`), while `Model` holds the handful of values
#      the fold actually rewrites.
#   2. A callee consumes its arguments, so `Map.get(m, ..)` hands the map back
#      and reading ten settings from one map costs ten copies. Settings are
#      therefore kept as a `List<&2, Item>` -- the raw parsed command line --
#      and read by folding, which needs no copies at all.
#
# Everything the fold reads twice is `Data` and is destructured with `+fields`.

# ── transport ───────────────────────────────────────────────────────────

# Which engine answers: X's own GraphQL, driven by session cookies, or the
# Sweetistics API, driven by an API key.
type Engine is Data:
  EngineGraphql{}
  EngineSweetistics{}
  EngineAuto{}

def Engine.of_lower(lower: String) -> Engine:
  match lower:
    case "graphql":
      EngineGraphql{}
    case "gql":
      EngineGraphql{}
    case "sweetistics":
      EngineSweetistics{}
    case "sweet":
      EngineSweetistics{}
    case _:
      EngineAuto{}

def Engine.of(raw: String) -> Engine:
  Engine.of_lower(String.to_lower(raw))

def Engine.name(e: Engine) -> String:
  match e:
    case EngineGraphql{}:
      "graphql"
    case EngineSweetistics{}:
      "sweetistics"
    case EngineAuto{}:
      "auto"

# Agent mode is the default for a non-tty: one JSON envelope on stdout and
# nothing else. Human mode is for a person at a terminal: short lines.
type OutMode is Data:
  OutAgent{}
  OutHuman{}

def OutMode.by_tty(tty: Bool) -> OutMode:
  match tty:
    case True{}:
      OutHuman{}
    case False{}:
      OutAgent{}

def OutMode.pick(tty: Bool, asked_json: Bool) -> OutMode:
  match asked_json:
    case True{}:
      OutAgent{}
    case False{}:
      OutMode.by_tty(tty)

def OutMode.from(tty: Bool, json_flag: Bool, json_env: Bool) -> OutMode:
  OutMode.pick(tty, Bool.or(json_flag, json_env))

def OutMode.is_agent(m: OutMode) -> Bool:
  match m:
    case OutAgent{}:
      True{}
    case OutHuman{}:
      False{}

type ErrCode is Data:
  ErrUsage{}
  ErrAuth{}
  ErrNotFound{}
  ErrRateLimited{}
  ErrNetwork{}
  ErrUpstream{}
  ErrInternal{}

# The stable string an agent branches on. These are API: never reword them.
def ErrCode.id(c: ErrCode) -> String:
  match c:
    case ErrUsage{}:
      "usage"
    case ErrAuth{}:
      "auth"
    case ErrNotFound{}:
      "not_found"
    case ErrRateLimited{}:
      "rate_limited"
    case ErrNetwork{}:
      "network"
    case ErrUpstream{}:
      "upstream"
    case ErrInternal{}:
      "internal"

# Exit codes are part of the contract too, so an agent can branch on $? with no
# parsing at all.
def ErrCode.exit_code(c: ErrCode) -> U32:
  match c:
    case ErrUsage{}:
      2
    case ErrAuth{}:
      3
    case ErrNotFound{}:
      4
    case ErrRateLimited{}:
      5
    case ErrNetwork{}:
      6
    case ErrUpstream{}:
      7
    case ErrInternal{}:
      1

# Whether retrying the same call unchanged could work, by code alone: back off on
# True, do not bother on False. This is only half the answer, and `Error.retryable`
# is the other half: a code that says "try again" is still wrong for a failure
# whose effect may already have happened.
def ErrCode.retryable(c: ErrCode) -> Bool:
  match c:
    case ErrRateLimited{}:
      True{}
    case ErrNetwork{}:
      True{}
    case ErrUpstream{}:
      True{}
    case ErrUsage{}:
      False{}
    case ErrAuth{}:
      False{}
    case ErrNotFound{}:
      False{}
    case ErrInternal{}:
      False{}

# `unknown` is whether the effect may already have happened when this failure was
# raised: the request was sent and the answer was lost, so the post may exist. It
# is appended last so the constructors below keep their arity and only patterns
# have to name it -- the sweep a new field costs is the patterns, not every site
# that builds one.
type Error is Data:
  Error{
    code: ErrCode,
    message: String,
    hint: String,
    unknown: Bool,
  }

def err(code: ErrCode, message: String) -> Error:
  Error{code, message, SNil{}, False{}}

def err_hint(code: ErrCode, message: String, hint: String) -> Error:
  Error{code, message, hint, False{}}

# The failure a retry cannot be trusted with. The code stays `network`, because a
# code says what went wrong and this says whether repeating the call is safe: a
# caller that backs off and retries a timed-out POST posts it twice.
def err_unknown(code: ErrCode, message: String, hint: String) -> Error:
  Error{code, message, hint, True{}}

# What the envelope reports, and the only place the two halves meet: the code's own
# answer, vetoed when the outcome is unknown. A read whose request was lost is still
# safe to repeat, which is why the veto is only ever raised for a verb that writes.
def Error.retryable(e: Error) -> Bool:
  match e:
    case Error{code, message, hint, unknown}:
      Bool.and(ErrCode.retryable(code), Bool.not(unknown))

# One place the build names itself, so `bird version`, the help text and the
# schema cannot disagree.
def version() -> String:
  "0.3.0"

# Every code the program can exit with, for the schema to print. `ok` is not an
# error and is not in here; the schema adds it.
def ErrCode.all() -> List<&2, ErrCode>:
  ErrUsage{} <> (ErrAuth{} <> (ErrNotFound{} <> (ErrRateLimited{} <> (
    ErrNetwork{} <> (ErrUpstream{} <> (ErrInternal{} <> Nil{}))
  ))))

def Error.exit_code(e: Error) -> U32:
  match e:
    case Error{code, message, hint, unknown}:
      ErrCode.exit_code(code)

type MediaKind is Data:
  MediaImage{}
  MediaVideo{}

type Media is Data:
  Media{
    path: String,
    alt: String,
    mime: String,
    kind: MediaKind,
  }

# One step of a media write. An upload carries the file; alt text is a separate
# request because X sets it with a call of its own, after the upload that
# produced the media id it describes.
type MediaJob is Data:
  JobUpload{media: Media}
  JobAlt{text: String}

def mk_media(path: String, alt: String, mime: String, kind: MediaKind) -> Media:
  Media{path, alt, mime, kind}

# A credential is one of three shapes and the transport follows from the shape:
# a session drives GraphQL, a key drives Sweetistics, and no credential is a
# hard error rather than an empty string nobody notices.
type Creds is Data:
  Anon{}
  Session{
    auth_token: String,
    ct0: String,
    source: String,
  }
  ApiKey{
    key: String,
    base_url: String,
  }

def mk_session(auth_token: String, ct0: String, source: String) -> Creds:
  Session{auth_token, ct0, source}

def mk_api_key(key: String, base_url: String) -> Creds:
  ApiKey{key, base_url}

def Creds.source(c: Creds) -> String:
  match c:
    case Anon{}:
      "none"
    case Session{auth_token, ct0, source}:
      source
    case ApiKey{key, base_url}:
      "sweetistics-api-key"

# One constructor per subcommand. `VerbHelp` and `VerbSchema` exist because an
# agent must be able to ask the program what it can do without reading a README.
type Verb is Data:
  VerbHelp{}
  VerbSchema{}
  VerbVersion{}
  VerbTweet{
    text: String,
    media: List<&2, Media>,
  }
  VerbReply{
    target: String,
    text: String,
    media: List<&2, Media>,
  }
  VerbRead{target: String}
  VerbReplies{target: String}
  VerbThread{target: String}
  VerbSearch{
    query: String,
    count: U32,
  }
  VerbMentions{count: U32}
  # `count` is the total the caller asked for, and `cursor` is the page token the
  # request carries -- empty on the first page. X answers a bookmark timeline one
  # page at a time, capped near a hundred, with a bottom cursor for the next one, so
  # a verb that says "200" and a verb that says "the page after this token" are the
  # same verb twice: the fold replaces the cursor and sends the same verb again.
  VerbBookmarks{
    count: U32,
    cursor: String,
  }
  VerbWhoami{}
  VerbCheck{}
  # `login` reads the session cookies out of a browser profile and the rotating
  # settings out of X's own client bundle, then writes both to the settings cache
  # so a later run needs no flags. It is not a write on X and not a login flow:
  # nothing is posted and no credential is obtained from X.
  VerbLogin{}

def Verb.name(v: Verb) -> String:
  match v:
    case VerbHelp{}:
      "help"
    case VerbSchema{}:
      "schema"
    case VerbVersion{}:
      "version"
    case VerbTweet{text, media}:
      "tweet"
    case VerbReply{target, text, media}:
      "reply"
    case VerbRead{target}:
      "read"
    case VerbReplies{target}:
      "replies"
    case VerbThread{target}:
      "thread"
    case VerbSearch{query, count}:
      "search"
    case VerbMentions{count}:
      "mentions"
    case VerbBookmarks{count, cursor}:
      "bookmarks"
    case VerbWhoami{}:
      "whoami"
    case VerbCheck{}:
      "check"
    case VerbLogin{}:
      "login"

# Whether the verb changes something on X. Only these need an idempotency story
# and a dry run an operator can inspect before it counts.
def Verb.writes(v: Verb) -> Bool:
  match v:
    case VerbTweet{text, media}:
      True{}
    case VerbReply{target, text, media}:
      True{}
    case _:
      False{}

# Whether the verb talks to the network at all.
def Verb.needs_network(v: Verb) -> Bool:
  match v:
    case VerbHelp{}:
      False{}
    case VerbSchema{}:
      False{}
    case VerbVersion{}:
      False{}
    case VerbCheck{}:
      False{}
    case _:
      True{}

# Every argv token becomes one of these. Nothing is flattened into a wide
# record, so a flag is added by adding a constructor, not by widening a struct
# that every call site has to be recompiled against.
type Item is Data:
  ItemFlag{name: String, value: String}
  ItemVerb{verb: Verb}
  ItemMedia{path: String}
  ItemAlt{text: String}

def Item.flag(name: String, value: String) -> Item:
  ItemFlag{name, value}

# An env var that is unset is simply absent, so a lookup falls through to the
# next source instead of shadowing it with an empty string.
def Item.env_on(empty: Bool, name: String, value: String) -> List<&2, Item>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      ItemFlag{name, value} <> Nil{}

def Item.env(name: String,+value: String) -> List<&2, Item>:
  Item.env_on(String.is_empty(value), name, value)

def Item.last_wins(same: Bool, v: String, acc: String) -> String:
  match same:
    case True{}:
      v
    case False{}:
      acc

def Item.replace(+it: Item, name: String,+acc: String) -> String:
  match it:
    case ItemFlag{k, v}:
      Item.last_wins(String.eq(k, name), v, acc)
    case ItemVerb{verb}:
      acc
    case ItemMedia{path}:
      acc
    case ItemAlt{text}:
      acc

# The last occurrence wins, which is what every command-line user expects of a
# repeated flag.
def Items.str(items: List<&2, Item>,+name: String,+acc: String) -> String:
  match items:
    case Nil{}:
      acc
    case +it <> rest:
      Items.str(rest, name, Item.replace(it, name, acc))

def Item.seen(same: Bool, acc: Bool) -> Bool:
  match same:
    case True{}:
      True{}
    case False{}:
      acc

def Item.present(+it: Item, name: String,+acc: Bool) -> Bool:
  match it:
    case ItemFlag{k, v}:
      Item.seen(String.eq(k, name), acc)
    case ItemVerb{verb}:
      acc
    case ItemMedia{path}:
      acc
    case ItemAlt{text}:
      acc

def Items.has(items: List<&2, Item>,+name: String,+acc: Bool) -> Bool:
  match items:
    case Nil{}:
      acc
    case +it <> rest:
      Items.has(rest, name, Item.present(it, name, acc))

def Items.has_flag(items: List<&2, Item>, name: String) -> Bool:
  Items.has(items, name, False{})

def Item.media_push(+it: Item,+acc: List<&2, String>) -> List<&2, String>:
  match it:
    case ItemMedia{path}:
      path <> acc
    case _:
      acc

# Every `--media` path, in order, then every `--alt`.
def Items.media(items: List<&2, Item>,+acc: List<&2, String>) -> List<&2, String>:
  match items:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +it <> rest:
      Items.media(rest, Item.media_push(it, acc))

def Item.alt_push(+it: Item,+acc: List<&2, String>) -> List<&2, String>:
  match it:
    case ItemAlt{text}:
      text <> acc
    case _:
      acc

def Items.alts(items: List<&2, Item>,+acc: List<&2, String>) -> List<&2, String>:
  match items:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +it <> rest:
      Items.alts(rest, Item.alt_push(it, acc))

# GraphQL operation ids rotate on X's side, so they are settings, not constants
# compiled into the binary. `bird schema --json` prints the ones in force.
type RunCfg is Data:
  RunCfg{
    verb: Verb,
    out: OutMode,
    dry_run: Bool,
    engine: Engine,
    creds: Creds,
    op_create_tweet: String,
    op_tweet_detail: String,
    op_search: String,
    op_bookmarks: String,
    op_viewer: String,
    web_bearer: String,
    gql_features: String,
    api_base: String,
    timeout_ms: U32,
    media_upload_base: String,
    gql_base: String,
    mentions_url: String,
  }

def mk_cfg(
  verb: Verb,
  out: OutMode,
  dry_run: Bool,
  engine: Engine,
  creds: Creds,
  op_create_tweet: String,
  op_tweet_detail: String,
  op_search: String,
  op_bookmarks: String,
  op_viewer: String,
  web_bearer: String,
  gql_features: String,
  api_base: String,
  timeout_ms: U32,
  media_upload_base: String,
  gql_base: String,
  mentions_url: String
) -> RunCfg:
  RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}

# ── what `login` needs ──────────────────────────────────────────────────
#
# Its own settings, gathered before anything runs. `dir` is not here because it
# is `--tmpdir` plus nothing: the login flow builds the two file paths from it, so
# only the directory is carried.
type LoginCfg is Data:
  LoginCfg{
    source: String,
    db: String,
    chrome_key: String,
    web_home: String,
    bundle_base: String,
    settings_path: String,
    tmp_dir: String,
  }

def mk_login_cfg(
  source: String,
  db: String,
  chrome_key: String,
  web_home: String,
  bundle_base: String,
  settings_path: String,
  tmp_dir: String
) -> LoginCfg:
  LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}

# A description of a side effect. `id` correlates an outcome back to its request
# so independent commands could run at once without losing the thread.
type Cmd is Data:
  CmdNone{}
  CmdPrint{text: String}
  CmdPrintErr{text: String}
  CmdReadFile{
    id: U32,
    path: String,
    why: String,
  }
  CmdHttp{id: U32, req: HttpReq}
  # Any program, with an argv list and no shell. `CmdHttp` is this with curl in
  # front, and the login flow needs the same shape for the three local tools it
  # runs: `sqlite3` to read a browser's cookie store, `security` for the Chrome
  # key, and `openssl` to derive it and decrypt with it. The answer comes back as
  # `MsgProc`, text only, which is why the Chrome ciphertext is written to a file
  # by `sqlite3` rather than carried here.
  CmdExec{id: U32, program: String, args: List<&2, String>}
  # A file this program writes, which is one thing in the whole design: the
  # settings cache. It carries the text rather than a handle because nothing else
  # in the fold can hold one.
  CmdWriteFile{
    id: U32,
    path: String,
    text: String,
  }
  CmdExit{
    code: U32,
    message: String,
  }

type Header is Data:
  Header{name: String, value: String}

# `body` is one literal payload; `parts` is a multipart form, each entry
# `name=value` or `name=@path`. A file upload is the only thing that needs the
# latter, and curl reads the file itself, so nothing binary ever passes through
# this program's strings -- or through its argv, which has a size limit.
type HttpReq is Data:
  HttpReq{
    method: String,
    url: String,
    headers: List<&2, Header>,
    body: String,
    parts: List<&2, String>,
    timeout_ms: U32,
  }

def mk_http(method: String, url: String, headers: List<&2, Header>, body: String, timeout_ms: U32) -> HttpReq:
  HttpReq{method, url, headers, body, Nil{}, timeout_ms}

def mk_http_parts(method: String, url: String, headers: List<&2, Header>, body: String, parts: List<&2, String>, timeout_ms: U32) -> HttpReq:
  HttpReq{method, url, headers, body, parts, timeout_ms}

def hdr(name: String, value: String) -> Header:
  Header{name, value}

def Cmd.print(text: String) -> Cmd:
  CmdPrint{text}

def Cmd.print_err(text: String) -> Cmd:
  CmdPrintErr{text}

def Cmd.exit(code: U32, message: String) -> Cmd:
  CmdExit{code, message}

def Cmd.http(id: U32, req: HttpReq) -> Cmd:
  CmdHttp{id, req}

def Cmd.read_file(id: U32, path: String, why: String) -> Cmd:
  CmdReadFile{id, path, why}

type Msg is Data:
  MsgStart{
    args: List<&2, String>,
    env: List<&2, Item>,
    tty: Bool,
    config_path: String,
  }
  MsgFileOk{
    id: U32,
    path: String,
    why: String,
    text: String,
  }
  MsgFileFail{
    id: U32,
    path: String,
    why: String,
    code: U32,
    message: String,
  }
  MsgHttpOk{
    id: U32,
    curl_status: U32,
    http_status: U32,
    body: String,
    stderr: String,
  }
  # A local program answered. `status` is its exit status and `out`/`err` are what
  # it wrote, which is all any of the three tools the login flow runs needs.
  MsgProc{
    id: U32,
    status: U32,
    out: String,
    err: String,
  }
  # The settings cache was written, or the writing failed and said why. A cache
  # that could not be written is a failed login: the run would otherwise report
  # settings it did not keep.
  MsgWrote{
    id: U32,
    path: String,
    ok: Bool,
    message: String,
  }

# The verb of a resolved run, replaced once the settings are all in hand: the
# text of a write may come from a file, which is not known until the file has
# been read.
def RunCfg.with_verb(cfg: RunCfg, verb: Verb) -> RunCfg:
  match cfg:
    case RunCfg{verb_old, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}

# ── the login flow ──────────────────────────────────────────────────────
#
# `login` is a queue of local programs and two requests, folded the way a media
# write is. The step says which one is open; the loot is what the steps before it
# learned and the ones after it need, so nothing is read twice and no step has to
# be told which cookie it is holding.
#
# The order is the only order that works: the cookies are read first because the
# page that names the bundle answers the signed-in client, the key is derived next
# because decrypting needs it, and the cache is written last because it holds
# everything the run gathered.
type LoginStep is Data:
  LoginCookies{}
  LoginKey{}
  LoginDerive{}
  LoginDecrypt{}
  LoginDecrypt2{}
  LoginClean{}
  LoginPage{}
  LoginBundle{}
  LoginWrite{}
  LoginLock{}
  LoginDone{}

# `cache` is the settings text as it will be written, built once when the bundle
# answered: the steps after that hold the whole of what the run gathered, and the
# report at the end is read back out of it rather than out of a second copy.
type Loot is Data:
  Loot{
    dir: String,
    url: String,
    password: String,
    key: String,
    at: String,
    ct0: String,
    cache: String,
  }

def mk_loot(
  dir: String,
  url: String,
  password: String,
  key: String,
  at: String,
  ct0: String,
  cache: String
) -> Loot:
  Loot{dir, url, password, key, at, ct0, cache}

def Loot.with_password(l: Loot, password: String) -> Loot:
  match l:
    case Loot{dir, url, password_old, key, at, ct0, cache}:
      mk_loot(dir, url, password, key, at, ct0, cache)

def Loot.with_key(l: Loot, key: String) -> Loot:
  match l:
    case Loot{dir, url, password, key_old, at, ct0, cache}:
      mk_loot(dir, url, password, key, at, ct0, cache)

def Loot.with_at(l: Loot, at: String) -> Loot:
  match l:
    case Loot{dir, url, password, key, at_old, ct0, cache}:
      mk_loot(dir, url, password, key, at, ct0, cache)

def Loot.with_ct0(l: Loot, ct0: String) -> Loot:
  match l:
    case Loot{dir, url, password, key, at, ct0_old, cache}:
      mk_loot(dir, url, password, key, at, ct0, cache)

def Loot.with_url(l: Loot, url: String) -> Loot:
  match l:
    case Loot{dir, url_old, password, key, at, ct0, cache}:
      mk_loot(dir, url, password, key, at, ct0, cache)

def Loot.with_cache(l: Loot, cache: String) -> Loot:
  match l:
    case Loot{dir, url, password, key, at, ct0, cache_old}:
      mk_loot(dir, url, password, key, at, ct0, cache)

# Where the run is. `PhaseInit` is the entry state, `PhaseGather` waits for the
# settings the run reads for itself, `PhaseRequest` waits for the answer, and
# `PhaseDone`/`PhaseFailed` finish it. Nothing below ever sends anything; it
# describes what to send and what the answer meant.
type Phase is Data:
  PhaseInit{}
  PhaseGather{}
  PhaseRequest{id: U32}
  # A media write is a sequence of requests: the queue is what is still to send,
  # its head is the one in flight, and `done` collects the media ids the uploads
  # named, which the final create request needs.
  PhaseMedia{jobs: List<&2, MediaJob>, done: List<&2, String>}
  # The login flow, which is a queue like a media write: one step is open, and
  # the step says which command answers it. `loot` is what the steps before it
  # learned and the ones after it need, so no step has to re-read anything.
  PhaseLogin{step: LoginStep, loot: Loot}
  PhaseDone{}
  PhaseFailed{error: Error}

# What the command line and the read-it-yourself settings resolved to, gathered
# before any request is built. Kept as one record so `Model` keeps its shape,
# and so a read result has one obvious home.
#
# The gather runs in two rounds, because the config file is itself one of the
# files: the paths of the other two are not knowable until it has been read.
# `stage` says which round is open, `pending` how many of its reads are still
# out, so both are readable from the model rather than inferred.
type Stage is Data:
  StageConfig{}
  StageFiles{}
  StageDone{}

type Start is Data:
  Start{
    stage: Stage,
    items: List<&2, Item>,
    env: List<&2, Item>,
    rc: List<&2, Item>,
    tty: Bool,
    config_path: String,
    text: String,
    fixture: String,
    pending: Nat,
  }

def mk_start(
  stage: Stage,
  items: List<&2, Item>,
  env: List<&2, Item>,
  rc: List<&2, Item>,
  tty: Bool,
  config_path: String,
  text: String,
  fixture: String,
  pending: Nat
) -> Start:
  Start{stage, items, env, rc, tty, config_path, text, fixture, pending}

def Start.with_stage(s: Start, stage: Stage) -> Start:
  match s:
    case Start{stage_old, items, env, rc, tty, config_path, text, fixture, pending}:
      mk_start(stage, items, env, rc, tty, config_path, text, fixture, pending)

def Start.with_rc(s: Start, rc: List<&2, Item>) -> Start:
  match s:
    case Start{stage, items, env, rc_old, tty, config_path, text, fixture, pending}:
      mk_start(stage, items, env, rc, tty, config_path, text, fixture, pending)

def Start.with_text(s: Start, text: String) -> Start:
  match s:
    case Start{stage, items, env, rc, tty, config_path, text_old, fixture, pending}:
      mk_start(stage, items, env, rc, tty, config_path, text, fixture, pending)

def Start.with_fixture(s: Start, fixture: String) -> Start:
  match s:
    case Start{stage, items, env, rc, tty, config_path, text, fixture_old, pending}:
      mk_start(stage, items, env, rc, tty, config_path, text, fixture, pending)

def Start.with_pending(s: Start, pending: Nat) -> Start:
  match s:
    case Start{stage, items, env, rc, tty, config_path, text, fixture, pending_old}:
      mk_start(stage, items, env, rc, tty, config_path, text, fixture, pending)

# One read landed. `Nat.sub` floors at zero, so a message that arrives twice
# cannot underflow the count into a number that never reaches zero.
def Start.one_less(s: Start) -> Start:
  match s:
    case Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      mk_start(stage, items, env, rc, tty, config_path, text, fixture, Nat.sub(pending, 1n))

type Model is Data:
  Model{
    phase: Phase,
    start: Start,
    cfg: RunCfg,
    status: U32,
    payload: J.Json,
    body: String,
    exit_code: U32,
    notes: List<&2, String>,
  }

# One turn of the fold: the new model and the effects to run next.
type Step is Data:
  Step{model: Model, cmds: List<&2, Cmd>}

def mk_step(model: Model, cmds: List<&2, Cmd>) -> Step:
  Step{model, cmds}

def mk_model(
  phase: Phase,
  start: Start,
  cfg: RunCfg,
  status: U32,
  payload: J.Json,
  body: String,
  exit_code: U32,
  notes: List<&2, String>
) -> Model:
  Model{phase, start, cfg, status, payload, body, exit_code, notes}

def Model.set_phase(m: Model, phase: Phase) -> Model:
  match m:
    case Model{phase_old, start, cfg, status, payload, body, exit_code, notes}:
      mk_model(phase, start, cfg, status, payload, body, exit_code, notes)

def Model.gathering(m: Model, start: Start) -> Model:
  match m:
    case Model{phase, start_old, cfg, status, payload, body, exit_code, notes}:
      mk_model(PhaseGather{}, start, cfg, status, payload, body, exit_code, notes)

def Model.with_cfg(m: Model, cfg: RunCfg) -> Model:
  match m:
    case Model{phase, start, cfg_old, status, payload, body, exit_code, notes}:
      mk_model(phase, start, cfg, status, payload, body, exit_code, notes)

def Model.waiting(m: Model, id: U32) -> Model:
  match m:
    case Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      mk_model(PhaseRequest{id}, start, cfg, status, payload, body, exit_code, notes)

def Model.with_verb(m: Model, verb: Verb) -> Model:
  match m:
    case Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      mk_model(phase, start, RunCfg.with_verb(cfg, verb), status, payload, body, exit_code, notes)

# A page that is not the last one keeps what has been folded so far, in the field
# the finished answer already uses. The alternative -- a second home for the
# tweets read so far -- is the shape that lets an accumulation and the answer
# disagree, and every field of this record costs a sweep on the next one added.
def Model.with_payload(m: Model, payload: J.Json) -> Model:
  match m:
    case Model{phase, start, cfg, status, payload_old, body, exit_code, notes}:
      mk_model(phase, start, cfg, status, payload, body, exit_code, notes)

# An answer arrived and was understood: the run is over and the exit code is 0.
def Model.answered(m: Model, status: U32, payload: J.Json, body: String, notes: List<&2, String>) -> Model:
  match m:
    case Model{phase, start, cfg, status_old, payload_old, body_old, exit_code, notes_old}:
      mk_model(PhaseDone{}, start, cfg, status, payload, body, 0, notes)

# A local verb: no request went out, so there is no status to report.
def Model.done(m: Model, payload: J.Json, notes: List<&2, String>) -> Model:
  match m:
    case Model{phase, start, cfg, status, payload_old, body, exit_code, notes_old}:
      mk_model(PhaseDone{}, start, cfg, status, payload, body, 0, notes)

# A failure keeps the body: X's own words are often the useful part of a 4xx.
def Model.failed_with(m: Model,+e: Error, body: String) -> Model:
  match m:
    case Model{phase, start, cfg, status, payload, body_old, exit_code, notes}:
      mk_model(PhaseFailed{e}, start, cfg, status, payload, body, Error.exit_code(e), notes)

def Model.failed(m: Model,+e: Error) -> Model:
  Model.failed_with(m, e, SNil{})

# A failure that arrived with an HTTP status keeps it. `failed_with` leaves the
# model's own status alone, which is 0 before any answer, so a 404 and a 500 read
# the same to anyone looking at the envelope's `status` rather than at `error.id`.
# A failure with no request behind it -- a usage error -- has no status to report,
# and 0 is the honest answer there.
def Model.failed_status(m: Model, status: U32, +e: Error, body: String) -> Model:
  match m:
    case Model{phase, start, cfg, status_old, payload, body_old, exit_code, notes}:
      mk_model(PhaseFailed{e}, start, cfg, status, payload, body, Error.exit_code(e), notes)

# A failure can still carry notes: curl's own words are the useful part of a
# connection that never happened, and dropping them leaves "network error" as the
# whole story.
def Model.with_notes(m: Model, notes: List<&2, String>) -> Model:
  match m:
    case Model{phase, start, cfg, status, payload, body, exit_code, notes_old}:
      mk_model(phase, start, cfg, status, payload, body, exit_code, notes)

def Step.only(m: Model) -> Step:
  mk_step(m, Nil{})

def no_cmds() -> List<&2, Cmd>:
  Nil{}

# `--text-file` fills the text of a write when `--text` was not given, so the
# file is a way to avoid quoting rather than an override.
def Verb.set_text(+v: Verb,+text: String) -> Verb:
  match v:
    case VerbTweet{old, media}:
      VerbTweet{text, media}
    case VerbReply{target, old, media}:
      VerbReply{target, text, media}
    case _:
      v

# `--count` is a value rather than a flag, so it can arrive from the config file
# or the environment, and neither is readable until the run has read them. The
# fold sets it once the settings are in, so `--count` means the same thing in a
# file as on the command line.
def Verb.set_count(+v: Verb, n: U32) -> Verb:
  match v:
    case VerbSearch{query, count_old}:
      VerbSearch{query, n}
    case VerbMentions{count_old}:
      VerbMentions{n}
    case VerbBookmarks{count_old, cursor}:
      VerbBookmarks{n, cursor}
    case _:
      v

# The page token the next request carries. Only the bookmark timeline answers with
# one, so every other verb is unchanged.
def Verb.set_cursor(+v: Verb, +cursor: String) -> Verb:
  match v:
    case VerbBookmarks{count, cursor_old}:
      VerbBookmarks{count, cursor}
    case _:
      v

def Verb.has_text(+v: Verb) -> Bool:
  match v:
    case VerbTweet{text, media}:
      Bool.not(String.is_empty(text))
    case VerbReply{target, text, media}:
      Bool.not(String.is_empty(text))
    case _:
      True{}

# The attachments of a write, or nothing: the one reader the media flow needs,
# so it does not have to know which writing verb it is looking at.
def Verb.media_of(+v: Verb) -> List<&2, Media>:
  match v:
    case VerbTweet{text, media}:
      media
    case VerbReply{target, text, media}:
      media
    case _:
      Nil{}

# The tweet a verb points at, or nothing. `read`, `replies`, `thread` and `reply`
# carry one; every other verb has no target for the policy to check.
def Verb.target_of(+v: Verb) -> Maybe<&2, String>:
  match v:
    case VerbRead{target}:
      Some{target}
    case VerbReplies{target}:
      Some{target}
    case VerbThread{target}:
      Some{target}
    case VerbReply{target, text, media}:
      Some{target}
    case _:
      None{}
