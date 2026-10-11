import Base
import ./domain.bend as D
import ./json.bend as J
import ./policy.bend as P
import ./argv.bend as A
import ./api.bend as Api
import ./http.bend as H

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
def Update.first_reads(+s: D.Start) -> List<&2, D.Cmd>:
  match s:
    case D.Start{stage, items, env, rc, tty, config_path, text, fixture, pending}:
      Update.read(String.is_empty(config_path), Update.id_config(), config_path, Update.why_config())

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
    case _:
      None{}

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

def Update.parsed(+m: D.Model, +p: J.Parsed, http_status: U32, body: String, stderr: String) -> D.Step:
  match p:
    case J.ParsedOk{value}:
      D.mk_step(D.Model.answered(m, http_status, value, body, Update.notes_ok(stderr)), D.no_cmds())
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
def Update.answer_kind(is_media: Bool, curl_status: U32, +http_status: U32, +body: String, +stderr: String, +m: D.Model) -> D.Step:
  match is_media:
    case True{}:
      Update.media_answer(curl_status, http_status, body, stderr, m)
    case False{}:
      Update.transport_ok(H.Http.transport_error(curl_status), http_status, body, stderr, m)

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

def Update.routed(+m: D.Model, +cfg: D.RunCfg) -> D.Step:
  match cfg:
    case D.RunCfg{+verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      # The fixture that answers is the file's text, not the path the setting
      # named: `fixture_path` is where to look, and the read put the contents in
      # the start's fixture. Passing the path here answers every run with a
      # filename.
      Update.ready_on(
        P.Cfg.blank_write(verb, Update.text_in(Update.start_of(m))),
        Update.merged_verb(verb, m),
        D.Model.with_cfg(m, cfg),
        dry_run,
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

def Update.config_round_on(no_config: Bool, +model: D.Model, +s: D.Start) -> D.Step:
  match no_config:
    case True{}:
      Update.files_round(model, D.Start.with_stage(s, D.StageFiles{}))
    case False{}:
      Update.gather(model, D.Start.with_stage(s, D.StageConfig{}), Update.first_reads(s))

def Update.config_round(+model: D.Model, +s: D.Start) -> D.Step:
  Update.config_round_on(String.is_empty(Update.config_path_in(s)), model, s)

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

def Update.rc_checked_on(+bad: Maybe<&2, String>, +m: D.Model, +json: J.Json) -> D.Step:
  match bad:
    case Some{name}:
      D.mk_step(D.Model.failed(m, Update.rc_error(Update.config_at(m), name)), D.no_cmds())
    case None{}:
      Update.landed(D.Model.gathering(m, D.Start.one_less(D.Start.with_rc(Update.start_of(m), P.Cfg.rc_items(J.fields(json))))))

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

def Update.file_ok_on(is_config: Bool, id: U32, text: String, +model: D.Model) -> D.Step:
  match is_config:
    case True{}:
      Update.rc_landed(model, text)
    case False{}:
      Update.read_landed(model, id, text)

def Update.file_ok(+id: U32, text: String, +model: D.Model) -> D.Step:
  Update.file_ok_on(U32.is_eq(id, Update.id_config()), id, text, model)

def Update.file_error(path: String, +message: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "cannot read the file this run was asked for: " ++ path,
    message
  )

# A config file that cannot be read is the one failure the run shrugs off, and
# it still has to close the round it opened: leaving `pending` at 1 would stall a
# run that has nothing left to wait for.
def Update.file_fail_on(is_config: Bool, path: String, message: String, +model: D.Model) -> D.Step:
  match is_config:
    case True{}:
      Update.landed(D.Model.gathering(model, D.Start.one_less(Update.start_of(model))))
    case False{}:
      D.mk_step(D.Model.failed(model, Update.file_error(path, message)), D.no_cmds())

def Update.file_fail(+id: U32, path: String, message: String, +model: D.Model) -> D.Step:
  Update.file_fail_on(U32.is_eq(id, Update.id_config()), path, message, model)

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

def Update.step(msg: D.Msg, model: D.Model) -> D.Step:
  match msg:
    case D.MsgStart{args, env, tty, config_path}:
      Update.started(args, env, tty, config_path, model)
    case D.MsgFileOk{id, path, why, text}:
      Update.file_ok(id, text, model)
    case D.MsgFileFail{id, path, why, code, message}:
      Update.file_fail(id, path, message, model)
    case D.MsgHttpOk{id, curl_status, http_status, body, stderr}:
      Update.http_ok(id, curl_status, http_status, body, stderr, model)
