import Base
import ./domain.bend as D
import ./json.bend as J
import ./api.bend as Api

# What the run prints, as data. Pure: a finished model in, the commands that say
# what happened out. The interpreter runs them, which is why nothing here writes
# to a terminal itself and why the whole rendering is testable without one.
#
# Two shapes, and the choice between them is `OutMode`, decided when the settings
# resolved rather than here:
#
# * `--json` puts one envelope on stdout and nothing else, because a caller that
#   branches on `error.id` should never have to parse prose or skip a log line.
# * a terminal gets the data, indented. X answers with kilobytes of nested JSON;
#   one line of it is not readable, and a reader is what a terminal is for.
#
# The exit code is part of the same contract: 0 when the run finished, and the
# error's own code when it did not, so a shell can branch without reading either
# shape.

def View.cfg_of(+m: D.Model) -> D.RunCfg:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      cfg

def View.phase_of(+m: D.Model) -> D.Phase:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      phase

def View.payload_of(+m: D.Model) -> J.Json:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      payload

def View.status_of(+m: D.Model) -> U32:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      status

def View.body_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      body

def View.exit_of(+m: D.Model) -> U32:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      exit_code

def View.notes_of(+m: D.Model) -> List<&2, String>:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      notes

def View.out_of(+cfg: D.RunCfg) -> D.OutMode:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      out

def View.verb_of(+cfg: D.RunCfg) -> D.Verb:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      verb

# ── the envelope ────────────────────────────────────────────────────────

# `retryable` is part of the contract, not advice: it is true for exactly
# `rate_limited`, `network` and `upstream`, so an agent that backs off and retries
# reads one boolean instead of keeping its own copy of that table. Nothing in a
# run retries by itself (see the record's non-goals); the caller decides.
def View.envelope(+m: D.Model, +e: D.Error) -> J.Json:
  match e:
    case D.Error{code, message, hint}:
      J.obj_of(J.pairs5(
        J.pair("ok", J.of_bool(False{})),
        J.pair("error", J.obj_of(J.pairs4(
          J.pair("id", J.of_str(D.ErrCode.id(code))),
          J.pair("message", J.of_str(message)),
          J.pair("hint", J.of_str(hint)),
          J.pair("retryable", J.of_bool(D.ErrCode.retryable(code)))
        ))),
        J.pair("status", J.of_u32(View.status_of(m))),
        J.pair("body", J.of_str(View.body_of(m))),
        J.pair("notes", Api.Api.strings_json(View.notes_of(m), Nil{}))
      ))

# No verb is named here: a usage error is often raised before the command line
# named one, and an envelope that guessed would be worse than one that does not
# claim to know.
def View.ok_envelope(+m: D.Model) -> J.Json:
  J.obj_of(J.pairs5(
    J.pair("ok", J.of_bool(True{})),
    J.pair("verb", J.of_str(D.Verb.name(View.verb_of(View.cfg_of(m))))),
    J.pair("status", J.of_u32(View.status_of(m))),
    J.pair("data", View.payload_of(m)),
    J.pair("notes", Api.Api.strings_json(View.notes_of(m), Nil{}))
  ))

# ── what a terminal sees ────────────────────────────────────────────────

# X wraps everything in `data`, and that member is what a reader wants: the
# envelope around it is X's business, not the user's.
def View.human_field(found: Maybe<&2, J.Json>, +j: J.Json) -> String:
  match found:
    case Some{data}:
      J.pretty(data)
    case None{}:
      J.pretty(j)

def View.human_shape(is_obj: Bool, +j: J.Json) -> String:
  match is_obj:
    case True{}:
      View.human_field(J.get(j, "data"), j)
    case False{}:
      J.pretty(j)

# The manual answers with a string rather than a document, so it is printed as
# itself instead of quoted. Everything else answers with a document and is
# indented.
def View.human_text(found: Maybe<&2, String>, +j: J.Json) -> String:
  match found:
    case Some{s}:
      s
    case None{}:
      View.human_shape(J.is_obj(j), j)

# `null` is a run that did something rather than fetched something: a write, or
# `check`. Saying so beats printing nothing and leaving the reader unsure whether
# it worked.
def View.human_null(is_null: Bool, +j: J.Json) -> String:
  match is_null:
    case True{}:
      "ok"
    case False{}:
      View.human_text(J.text_of(j), j)

def View.human_any(+j: J.Json) -> String:
  View.human_null(J.is_null(j), j)

def View.human(+m: D.Model) -> String:
  View.human_any(View.payload_of(m))

def View.with_hint_on(blank: Bool, +message: String, +hint: String) -> String:
  match blank:
    case True{}:
      "bird: " ++ message
    case False{}:
      "bird: " ++ message ++ "\n  " ++ hint

def View.with_hint(+message: String, +hint: String) -> String:
  View.with_hint_on(String.is_empty(hint), message, hint)

def View.human_error(+e: D.Error) -> String:
  match e:
    case D.Error{code, message, hint}:
      View.with_hint(message, hint)

# ── the commands ────────────────────────────────────────────────────────

# One note per line on stderr, so a warning never lands in the middle of the data
# a script is reading from stdout.
def View.note_cmds(+notes: List<&2, String>) -> List<&2, D.Cmd>:
  match notes:
    case Nil{}:
      Nil{}
    case +h <> rest:
      D.Cmd.print_err(h ++ "\n") <> View.note_cmds(rest)

def View.json_cmds(+phase: D.Phase, +m: D.Model) -> List<&2, D.Cmd>:
  match phase:
    case D.PhaseFailed{error}:
      D.Cmd.print(J.show(View.envelope(m, error)) ++ "\n") <> (D.Cmd.exit(View.exit_of(m), SNil{}) <> Nil{})
    case _:
      D.Cmd.print(J.show(View.ok_envelope(m)) ++ "\n") <> Nil{}

def View.text_cmds(+phase: D.Phase, +m: D.Model) -> List<&2, D.Cmd>:
  match phase:
    case D.PhaseFailed{error}:
      D.Cmd.print_err(View.human_error(error) ++ "\n") <> (D.Cmd.exit(View.exit_of(m), SNil{}) <> Nil{})
    case _:
      D.Cmd.print(View.human(m) ++ "\n") <> View.note_cmds(View.notes_of(m))

def View.by_mode(out: D.OutMode, +phase: D.Phase, +m: D.Model) -> List<&2, D.Cmd>:
  match out:
    case D.OutAgent{}:
      View.json_cmds(phase, m)
    case D.OutHuman{}:
      View.text_cmds(phase, m)

def View.commands(+m: D.Model) -> List<&2, D.Cmd>:
  View.by_mode(View.out_of(View.cfg_of(m)), View.phase_of(m), m)
