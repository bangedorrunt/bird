import Base
import ./scan.bend as S
import ./domain.bend as D
import ./http.bend as H
import ./update.bend as U
import ./view.bend as V

# The design record is docs/decisions/0001-design-bird.md: one file, all
# decisions, including why this file is the only one allowed to touch the world.
#
# The interpreter. Everything that touches the world is here: the command line,
# the environment, the reads a run asks for, `curl`, and the printing. The fold
# decides what to do; this file does it and hands the answer back.
#
# Four rules of the language shaped this file, and knowing them saves the next
# reader a lot of confusion:
#
# 1. A def must be defined before it is called, so the file reads callee first.
# 2. A self-recursive call must be on a syntactically smaller part of an
#    argument, and it may not sit inside a closure. `IO.bind`'s continuation is a
#    closure, so a walk that performs one effect per element cannot recurse
#    through it: each of those walks carries `fuel` and recurses as a direct
#    argument instead, with the value the effect produced arriving in a trailing
#    parameter of exactly that effect's type.
# 3. A def used as a value (handed to `IO.bind` rather than called) must not mark
#    its parameters `+`, because a reusable parameter is a different type.
# 4. Only one def recurses per walk. A cycle of defs calling each other is what
#    rule 1 forbids, which is why the run's own loop is one def carrying `Ops`.
#
# Commands run one at a time rather than forked together: rule 2 makes the
# fan-out impossible to write, and the rounds the fold issues are two local file
# reads, so the measured difference is microseconds. The design keeps the seam
# where it matters -- `Update.step` folds one answer at a time and does not care
# whether the interpreter fetched them serially or in parallel.

# ── limits ──────────────────────────────────────────────────────────────
#
# A tweet is kilobytes; these caps are here so a wrong path or a hostile answer
# cannot make the program allocate without end.

def Effects.max_file() -> U32:
  4194304

def Effects.max_reply() -> U32:
  8388608

# curl gets a slightly longer budget than its own `--max-time`, so a request that
# hangs is stopped by curl, which can say it timed out, rather than by this
# process, which could only say it gave up.
def Effects.grace_ms(ms: U32) -> U32:
  U32.add(ms, 2000)

# One visit per command and per printed line, so this is far more than any real
# run needs. Reaching it means a walk did not settle, which is a bug worth naming
# rather than a hang worth waiting for.
def Effects.fuel() -> Nat:
  4096n

# A local program's budget. `sqlite3`, `security` and `openssl` all answer in
# milliseconds, but `security` can put up a keychain dialog the first time and wait
# for a person, so the ceiling is generous rather than tight: a login that waits a
# minute for a click is a login that worked.
def Effects.local_ms() -> U32:
  120000

# ── reading a file ──────────────────────────────────────────────────────

def Effects.close_read(pair: File & Result<&1, &1, U32 & String, String>) -> IO(Result<&1, &1, U32 & String, String>):
  (handle, outcome) = pair
  IO.bind(Unit, Result<&1, &1, U32 & String, String>, File.close(handle), u => IO.pure(Result<&1, &1, U32 & String, String>, outcome))

def Effects.read_open(opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, String>):
  match opened:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{handle}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Result<&1, &1, U32 & String, String>, File.read(handle, Effects.max_file()), Effects.close_read)

def Effects.read_text(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, String>, File.open(path, "r"), Effects.read_open)

def Effects.file_msg(id: U32, +path: String, +why: String, outcome: Result<&1, &1, U32 & String, String>) -> IO(D.Msg):
  match outcome:
    case Fail{(code, message)}:
      IO.pure(D.Msg, D.MsgFileFail{id, path, why, code, message})
    case Done{text}:
      IO.pure(D.Msg, D.MsgFileOk{id, path, why, text})

def Effects.file_outcome(+cmd: D.Cmd, outcome: Result<&1, &1, U32 & String, String>) -> IO(D.Msg):
  match cmd:
    case D.CmdReadFile{id, path, why}:
      Effects.file_msg(id, path, why, outcome)
    case _:
      IO.die(D.Msg, 1, "bird: internal: an outcome for a command that was not a read")

def Effects.read_message(+cmd: D.Cmd) -> IO(D.Msg):
  match cmd:
    case D.CmdReadFile{id, path, why}:
      IO.bind(Result<&1, &1, U32 & String, String>, D.Msg, Effects.read_text(path), outcome => Effects.file_outcome(cmd, outcome))
    case _:
      IO.die(D.Msg, 1, "bird: internal: not a read")

# ── running one request ─────────────────────────────────────────────────
#
# `curl` is the whole of the transport: one process, the argv `Http.argv` builds,
# and its stdout split into the body and the status it was told to write out.
# Nothing in the request goes through a shell, so the text of a tweet cannot
# become a command.

# `Process.run` takes a list it owns and `Http.argv` hands over a copyable one:
# the argv is data, but the process consumes it, so it is handed across once.
def Effects.owned(xs: List<&2, String>, acc: List<&1, String>) -> List<&1, String>:
  match xs:
    case Nil{}:
      List.reverse(&1, String, acc)
    case +h <> rest:
      Effects.owned(rest, h <> acc)

# The arguments only: the program is `Process.run`'s first argument, so the list
# here must start at the first flag. `Http.argv` is the same list with the program
# in front, which is what a dry run prints.
def Effects.argv(+req: D.HttpReq) -> List<&1, String>:
  Effects.owned(H.Http.args(req), Nil{})

def Effects.spawn_msg(id: U32, curl_status: U32, +resp: H.Resp, +stderr: String) -> D.Msg:
  match resp:
    case H.Resp{http_status, body}:
      D.MsgHttpOk{id, curl_status, http_status, body, stderr}

# A request that could not even be started: curl is missing, or would not
# execute. curl's own exit status 1 is what a failed start reports, so this
# travels the road a failed request travels and lands as a network error.
def Effects.spawn_fail(id: U32, +message: String) -> D.Msg:
  D.MsgHttpOk{id, 1, 0, SNil{}, message}

def Effects.reply_parts(id: U32, curl_status: U32, +raw: String, +stderr: String) -> IO(D.Msg):
  resp : H.Resp = H.Http.reply(raw)
  IO.pure(D.Msg, Effects.spawn_msg(id, curl_status, resp, stderr))

def Effects.reply_value(id: U32, value: U32 & (String & String)) -> IO(D.Msg):
  (curl_status, streams) = value
  (raw, stderr) = streams
  Effects.reply_parts(id, curl_status, raw, stderr)

def Effects.http_outcome(id: U32, outcome: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(D.Msg):
  match outcome:
    case Fail{(code, message)}:
      IO.pure(D.Msg, Effects.spawn_fail(id, message))
    case Done{value}:
      Effects.reply_value(id, value)

def Effects.request(id: U32, +req: D.HttpReq) -> IO(D.Msg):
  match req:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      IO.bind(
        Result<&1, &1, U32 & String, U32 & (String & String)>,
        D.Msg,
        Process.run(H.Http.program(), Effects.argv(req), SNil{}, Effects.max_reply(), Effects.grace_ms(timeout_ms)),
        outcome => Effects.http_outcome(id, outcome)
      )

# ── running one local program ───────────────────────────────────────────
#
# The same `Process.run` the transport uses, with the program named by the fold
# instead of being curl. No shell is involved, so an argument is an argument: a
# password or a path cannot become syntax. Everything comes back as text, which is
# why the Chrome ciphertext never travels this way -- it is written to a file by
# `sqlite3` and read by `openssl`.

def Effects.proc_value(id: U32, value: U32 & (String & String)) -> IO(D.Msg):
  (status, streams) = value
  (out, err) = streams
  IO.pure(D.Msg, D.MsgProc{id, status, out, err})

def Effects.proc_outcome(id: U32, outcome: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(D.Msg):
  match outcome:
    case Fail{(code, message)}:
      IO.pure(D.Msg, D.MsgProc{id, code, SNil{}, message})
    case Done{value}:
      Effects.proc_value(id, value)

def Effects.exec(id: U32, program: String, +args: List<&2, String>) -> IO(D.Msg):
  IO.bind(
    Result<&1, &1, U32 & String, U32 & (String & String)>,
    D.Msg,
    Process.run(program, Effects.owned(args, Nil{}), SNil{}, Effects.max_reply(), Effects.local_ms()),
    outcome => Effects.proc_outcome(id, outcome)
  )

# ── writing one file ────────────────────────────────────────────────────
#
# The settings cache, and the only file this program writes. `File.write` hands
# the handle back, so the close happens before the outcome is read.

def Effects.wrote(id: U32, +path: String, outcome: Result<&1, &1, U32 & String, Unit>) -> IO(D.Msg):
  match outcome:
    case Fail{(code, message)}:
      IO.pure(D.Msg, D.MsgWrote{id, path, False{}, message})
    case Done{value}:
      IO.pure(D.Msg, D.MsgWrote{id, path, True{}, SNil{}})

def Effects.write_close(id: U32, +path: String, pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(D.Msg):
  (handle, outcome) = pair
  IO.bind(Unit, D.Msg, File.close(handle), u => Effects.wrote(id, path, outcome))

def Effects.write_open(id: U32, +path: String, +text: String, opened: Result<&1, &1, U32 & String, File>) -> IO(D.Msg):
  match opened:
    case Fail{(code, message)}:
      IO.pure(D.Msg, D.MsgWrote{id, path, False{}, message})
    case Done{handle}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, D.Msg, File.write(handle, text), Effects.write_close(id, path))

def Effects.now(id: U32, +path: String, +text: String) -> IO(D.Msg):
  IO.bind(Result<&1, &1, U32 & String, File>, D.Msg, File.open(path, "w"), Effects.write_open(id, path, text))

def Effects.dir_args(+dir: String) -> List<&2, String>:
  "-p" <> (dir <> Nil{})

# The directory is made first, because the settings cache's default path is
# `$HOME/.config/bird/settings.json` and `File.open` on it fails on a machine where
# that directory has never been made -- with the OS naming the file rather than the
# missing directory. `mkdir -p` runs the way the login flow runs `sqlite3` and
# `openssl`: a program and an argv, no shell, `-p` so one that is already there is
# not an error. Its outcome is dropped on purpose, so a `mkdir` that cannot run
# leaves the write to report its own message, which is the one naming the file. A
# path with no `/` in it is written where it says, with no call at all.
def Effects.write_here(no_dir: Bool, id: U32, +path: String, +text: String) -> IO(D.Msg):
  match no_dir:
    case True{}:
      Effects.now(id, path, text)
    case False{}:
      IO.bind(
        Result<&1, &1, U32 & String, U32 & (String & String)>,
        D.Msg,
        Process.run("mkdir", Effects.owned(Effects.dir_args(S.Scan.dir_of(path, SNil{})), Nil{}), SNil{}, Effects.max_file(), Effects.local_ms()),
        made => Effects.now(id, path, text)
      )

def Effects.write_file(id: U32, +path: String, +text: String) -> IO(D.Msg):
  Effects.write_here(String.is_empty(S.Scan.dir_of(path, SNil{})), id, path, text)

def Effects.http_message(+cmd: D.Cmd) -> IO(D.Msg):
  match cmd:
    case D.CmdHttp{id, req}:
      Effects.request(id, req)
    case _:
      IO.die(D.Msg, 1, "bird: internal: not a request")

def Effects.message(+cmd: D.Cmd) -> IO(D.Msg):
  match cmd:
    case D.CmdReadFile{id, path, why}:
      Effects.read_message(cmd)
    case D.CmdHttp{id, req}:
      Effects.http_message(cmd)
    case D.CmdExec{id, program, args}:
      Effects.exec(id, program, args)
    case D.CmdWriteFile{id, path, text}:
      Effects.write_file(id, path, text)
    case _:
      IO.die(D.Msg, 1, "bird: internal: a command with no way to answer")

# ── printing ────────────────────────────────────────────────────────────
#
# These return a `U32` rather than `Unit` because of rule 3 above: a def handed
# to `IO.bind` as its continuation cannot return `IO(Unit)`, so every step of the
# chain produces something. The value is never read; `IO.die` exits long before
# anyone could.

def Effects.after_print(act: IO(Unit)) -> IO(U32):
  IO.bind(Unit, U32, act, u => IO.pure(U32, 0))

def Effects.exit_on(blank: Bool, code: U32, +message: String) -> IO(U32):
  match blank:
    case True{}:
      IO.die(U32, code, SNil{})
    case False{}:
      IO.die(U32, code, message)

def Effects.say_one(+cmd: D.Cmd) -> IO(U32):
  match cmd:
    case D.CmdPrint{text}:
      Effects.after_print(IO.print(text))
    case D.CmdPrintErr{text}:
      Effects.after_print(IO.print_err(text))
    case D.CmdExit{code, message}:
      Effects.exit_on(String.is_empty(message), code, message)
    case _:
      Effects.after_print(IO.pure(Unit, Unit{}))

# Every line the run prints, in order. `u` is the value each line produces and is
# never read: the trailing parameter is there so `IO.bind` can hand the next step
# over, which is the shape a walk that performs one effect per element has to
# take here.
def Effects.say(fuel: Nat, +cmds: List<&2, D.Cmd>, u: U32) -> IO(U32):
  match fuel:
    case 0n:
      IO.die(U32, 1, "bird: internal: printing did not settle")
    case 1n+less:
      match cmds:
        case Nil{}:
          IO.pure(U32, 0)
        case +h <> rest:
          IO.bind(U32, U32, Effects.say_one(h), Effects.say(less, rest))

# The run is over: the model is rendered, and a failed run exits with the error's
# own code, so a shell branches without reading either output shape.
def Effects.finish(+model: D.Model) -> IO(U32):
  Effects.say(Effects.fuel(), V.View.commands(model), 0)

# ── the loop ────────────────────────────────────────────────────────────
#
# What to do next. `OFetch` holds the commands the fold asked for; answering one
# gives the fold the message and the rest of the list.
type Ops is Data:
  OFetch{cmds: List<&2, D.Cmd>, model: D.Model}
  OFold{rest: List<&2, D.Cmd>, model: D.Model}

# The fold's answer, as the next state. A round normally closes on its last
# command, so the commands it opens are the whole of what is left; if a round
# closed early they are put in front of what remains rather than replacing it.
def Effects.pending(none: Bool, +model: D.Model, +opened: List<&2, D.Cmd>, +rest: List<&2, D.Cmd>) -> Ops:
  match none:
    case True{}:
      OFetch{rest, model}
    case False{}:
      OFetch{List.append(&2, D.Cmd, opened, rest), model}

def Effects.after_step(+step: D.Step, +rest: List<&2, D.Cmd>) -> Ops:
  match step:
    case D.Step{model_next, cmds}:
      Effects.pending(List.is_empty(&2, D.Cmd, cmds), model_next, cmds, rest)

def Effects.after(+msg: D.Msg, +model: D.Model, +rest: List<&2, D.Cmd>) -> Ops:
  Effects.after_step(U.Update.step(msg, model), rest)

# A message is needed only where one arrives, so the entry passes a placeholder
# that no `OFetch` branch reads.
def Effects.no_msg() -> D.Msg:
  D.MsgFileOk{0, SNil{}, SNil{}, SNil{}}

def Effects.loop(fuel: Nat, ops: Ops, msg: D.Msg) -> IO(U32):
  match fuel:
    case 0n:
      IO.die(U32, 1, "bird: internal: the run did not settle")
    case 1n+less:
      match ops:
        case OFetch{cmds, model}:
          match cmds:
            case Nil{}:
              Effects.finish(model)
            case +h <> rest:
              IO.bind(D.Msg, U32, Effects.message(h), Effects.loop(less, OFold{rest, model}))
        case OFold{rest, model}:
          Effects.loop(less, Effects.after(msg, model, rest), Effects.no_msg())

def Effects.begin(+cmds: List<&2, D.Cmd>, +model: D.Model) -> IO(U32):
  Effects.loop(Effects.fuel(), OFetch{cmds, model}, Effects.no_msg())

def Effects.next(+step: D.Step) -> IO(U32):
  match step:
    case D.Step{model, cmds}:
      Effects.begin(cmds, model)

# ── the environment ─────────────────────────────────────────────────────
#
# Environment variables are read as items named by the flag they stand for, so a
# setting has one spelling everywhere and `Cfg.order` looks all three sources up
# the same way. `BIRD_JSON` is the exception that proves it: it is a switch, and
# `OutMode.from` reads it by its own name.
#
# The two session cookies are the second exception. `TWITTER_AUTH_TOKEN` and
# `TWITTER_CT0` are the names a shell that already talks to X exports, and they
# are the names every guide example passes explicitly, so a run that ignored them
# would report `auth` with the credential sitting right there in its own# environment. They are listed FIRST because `Items.str` takes the last match:
# the fallback goes first so the `BIRD_` spelling wins when both are set.
type EnvSpec is Data:
  EnvSpec{var: String, flag: String}

# What one variable turned into, carried to the visit that absorbs it. The
# answer is resolved to the flag and the text right here rather than carried as a
# `Result`, because a `Result` is linear and a record field must be `Data`.
type EnvDone is Data:
  EnvNone{}
  EnvTaken{flag: String, value: String}

def Effects.specs() -> List<&2, EnvSpec>:
  EnvSpec{"TWITTER_AUTH_TOKEN", "--auth-token"} <> (
    EnvSpec{"TWITTER_CT0", "--ct0"} <> (
      EnvSpec{"BIRD_JSON", "BIRD_JSON"} <> (
        EnvSpec{"BIRD_AUTH_TOKEN", "--auth-token"} <> (
          EnvSpec{"BIRD_CT0", "--ct0"} <> (
            EnvSpec{"BIRD_ENGINE", "--engine"} <> (
              EnvSpec{"BIRD_COUNT", "--count"} <> (
                EnvSpec{"BIRD_TIMEOUT_MS", "--timeout-ms"} <> (
                  EnvSpec{"BIRD_FIXTURE", "--fixture"} <> (
                    EnvSpec{"BIRD_TEXT_FILE", "--text-file"} <> (
                      EnvSpec{"BIRD_SWEETISTICS_API_KEY", "--sweetistics-api-key"} <> (
                        EnvSpec{"BIRD_SWEETISTICS_BASE_URL", "--sweetistics-base-url"} <> (
                          EnvSpec{"BIRD_WEB_BEARER", "--web-bearer"} <> (
                            EnvSpec{"BIRD_GQL_FEATURES", "--gql-features"} <> (
                              EnvSpec{"BIRD_OP_CREATE_TWEET", "--op-create-tweet"} <> (
                                EnvSpec{"BIRD_OP_TWEET_DETAIL", "--op-tweet-detail"} <> (
                                  EnvSpec{"BIRD_OP_SEARCH", "--op-search"} <> (
                                    EnvSpec{"BIRD_OP_BOOKMARKS", "--op-bookmarks"} <> (
                                    EnvSpec{"BIRD_OP_VIEWER", "--op-viewer"} <> (
                                      EnvSpec{"BIRD_MEDIA_UPLOAD_BASE", "--media-upload-base"} <> (
                                        EnvSpec{"BIRD_GQL_BASE", "--gql-base"} <> (
                                          EnvSpec{"BIRD_MENTIONS_URL", "--mentions-url"} <> (
                                            EnvSpec{"BIRD_BUNDLE_BASE", "--bundle-base"} <> (
                                              EnvSpec{"HOME", "--home"} <> (
                                                EnvSpec{"TMPDIR", "--tmpdir"} <> Nil{}
                                              )
                                              )
                                            )
                                          )
                                          )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )

def Effects.text_of(got: Result<&1, &1, U32 & String, String>) -> String:
  match got:
    case Done{value}:
      value
    case Fail{e}:
      SNil{}

def Effects.env_spec(+spec: EnvSpec) -> IO(Result<&1, &1, U32 & String, String>):
  match spec:
    case EnvSpec{var, flag}:
      IO.get_env(var)

def Effects.taken_of(+spec: EnvSpec, got: Result<&1, &1, U32 & String, String>) -> EnvDone:
  match spec:
    case EnvSpec{var, flag}:
      EnvTaken{flag, Effects.text_of(got)}

def Effects.env_pair(spec: EnvSpec, got: Result<&1, &1, U32 & String, String>) -> IO(EnvDone):
  IO.pure(EnvDone, Effects.taken_of(spec, got))

# An unset variable is not an empty setting: `--count` from nowhere stays nowhere
# rather than becoming the empty string, which would read as a count of zero.
def Effects.env_on(absent: Bool, +flag: String, value: String, +acc: List<&2, D.Item>) -> List<&2, D.Item>:
  match absent:
    case True{}:
      acc
    case False{}:
      List.append(&2, D.Item, D.Item.env(flag, value), acc)

def Effects.env_added(+flag: String, +value: String, +acc: List<&2, D.Item>) -> List<&2, D.Item>:
  Effects.env_on(String.is_empty(value), flag, value, acc)

def Effects.env_take(done: EnvDone, +acc: List<&2, D.Item>) -> List<&2, D.Item>:
  match done:
    case EnvNone{}:
      acc
    case EnvTaken{flag, value}:
      Effects.env_added(flag, value, acc)

def Effects.env_items(fuel: Nat, +specs: List<&2, EnvSpec>, +acc: List<&2, D.Item>, done: EnvDone) -> IO(List<&2, D.Item>):
  match fuel:
    case 0n:
      IO.die(List<&2, D.Item>, 1, "bird: internal: reading the environment did not settle")
    case 1n+less:
      match specs:
        case Nil{}:
          IO.pure(List<&2, D.Item>, List.reverse(&2, D.Item, Effects.env_take(done, acc)))
        case +h <> rest:
          IO.bind(EnvDone, List<&2, D.Item>, IO.bind(Result<&1, &1, U32 & String, String>, EnvDone, Effects.env_spec(h), Effects.env_pair(h)), Effects.env_items(less, rest, Effects.env_take(done, acc)))

# ── the command line ────────────────────────────────────────────────────
#
# The chain from the argument list to the run is a series of `IO.bind`s whose
# continuations are named defs rather than closures: a closure that calls back
# into the run's loop does not typecheck here, because the loop's effect
# parameters cannot be instantiated twice. Each of these takes exactly what the
# effect before it produced, as its last parameter.

def Effects.copy_args(args: List<String>, +acc: List<&2, String>) -> List<&2, String>:
  match args:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +h <> rest:
      Effects.copy_args(rest, h <> acc)

# `IO.args()` hands over the program as it was invoked, then its arguments.
def Effects.arguments(args: List<String>) -> List<&2, String>:
  match args:
    case Nil{}:
      Nil{}
    case +_ <> rest:
      Effects.copy_args(rest, Nil{})

# Whether stdout is a terminal, without an isatty effect: `TERM` is set by a
# terminal and by essentially nothing else, and `dumb` is what a program that is
# not one calls itself. Reading it wrong only changes how the output is written,
# and `--json` overrides it either way.
def Effects.tty_on(dumb: Bool, +term: String) -> Bool:
  match dumb:
    case True{}:
      False{}
    case False{}:
      Bool.not(String.is_empty(term))

def Effects.tty_is(+term: String) -> Bool:
  Effects.tty_on(String.eq(term, "dumb"), term)

def Effects.launch(+args: List<&2, String>, +items: List<&2, D.Item>, config_path: String, tty: Bool) -> IO(U32):
  Effects.next(U.Update.step(D.MsgStart{args, items, tty, config_path}, U.Update.initial()))

# Whether a terminal is attached is read from `TERM`, and that is a proxy rather
# than the answer, because the answer is not reachable here: Bend has no `isatty`,
# and `Process.run` hands its child pipes on all three descriptors, so asking a
# child `test -t 1` asks about the child's stdout -- a pipe -- and always answers
# no. An earlier version of this file did exactly that, which made the human path
# unreachable no matter where the program was run. `TERM` is set by a shell with a
# terminal and left empty by a cron job or an agent harness, and `dumb` is a
# program saying it is not one.
#
# A proxy can be wrong in one direction: `bird read x | jq` typed at a terminal
# has a pipe on stdout and a `TERM` in the environment, so it gets the reading a
# person gets rather than the envelope a pipe is documented to get. `--json` and
# `BIRD_JSON=1` are the answer to that, and a script should pass one of them
# rather than rely on the detection.
def Effects.after_term(+args: List<&2, String>, +items: List<&2, D.Item>, config_path: String, got: Result<&1, &1, U32 & String, String>) -> IO(U32):
  Effects.launch(args, items, config_path, Effects.tty_is(Effects.text_of(got)))

def Effects.after_config(+args: List<&2, String>, +items: List<&2, D.Item>, got: Result<&1, &1, U32 & String, String>) -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, String>, U32, IO.get_env("TERM"), Effects.after_term(args, items, Effects.text_of(got)))

def Effects.after_env(+args: List<&2, String>, items: List<&2, D.Item>) -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, String>, U32, IO.get_env("BIRD_CONFIG"), Effects.after_config(args, items))

def Effects.start(args: List<String>) -> IO(U32):
  IO.bind(
    List<&2, D.Item>,
    U32,
    Effects.env_items(Effects.fuel(), Effects.specs(), Nil{}, EnvNone{}),
    Effects.after_env(Effects.arguments(args))
  )

def main() -> IO(U32):
  IO.bind(List<String>, U32, IO.args(), Effects.start)
