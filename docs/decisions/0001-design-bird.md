---
status: accepted
date: 2026-10-11
decision-makers: bangedorrunt (operator), Buffy (agent)
---

# Design `bird`: a provable pure core, one interpreter, and a machine-first contract

This is the project's single architectural record, per the operator's call to
fold the draft decision files into one document. It was written after the design
was implemented and verified, from the code and the live runs; every "proved by"
line names a command or a test file that still exercises the decision.

## Context and Problem Statement

`bird` is a command-line client for X, written in Bend 2. It has to answer
`whoami`, `read`, `thread`, `replies`, `search`, `tweet`, `reply`, `mentions`,
`check`, `help`, `schema` and `version`, against two backends:

- X's own GraphQL endpoints, driven by a signed-in web session (the
  `auth_token` and `ct0` cookies plus a bearer), and
- Sweetistics, a keyed HTTP service whose operations mirror X's.

Five constraints shaped everything:

1. **The callers are agents.** They branch on fields, not prose, and an exit
   code has to mean something without parsing.
2. **Bend 2 is affine and strict.** A parameter is used once unless marked `+`, a
   `match` may only scrutinise a parameter or a field of one, defs must be
   defined before use, and a recursive call may not sit inside a closure. The
   language rules are the environment; the design had to fit them.
3. **X's deployment constants rotate** (bearer, four GraphQL query ids) and its
   hosts have already moved once, so a rebuild cannot be the answer.
4. **Writes are irreversible**, so every local mistake must be caught before a
   request exists, and `--dry-run` must describe exactly what would be sent.
5. **No HTTP library is available in the language** beyond raw sockets, and no
   `isatty` either. Both gaps are worked around deliberately rather than hidden.

## Decisions

The twelve decisions below are the design. Each is stated with what it rules
out and what proves it still holds.

### 1. A pure core and exactly one interpreter

**Decision.** `src/domain.bend`, `src/argv.bend`, `src/policy.bend`,
`src/json.bend`, `src/http.bend`, `src/api.bend`, `src/update.bend` and
`src/view.bend` are pure: they take data and return data, and they never touch
the world. `src/effects.bend` is the only interpreter: it reads the command line
and environment, reads files, runs curl, prints, and exits. `main` is a fold:
`Update.step(msg, model)` consumes one message and returns the next model plus
the commands it wants; `Effects` runs those commands and feeds the answers back.

The fold lives in `src/update.bend` (Elm/Redux shape: `Model`, `Msg`, `Step`);
what the run prints is pure data too (`View.commands` returns print commands,
`Effects` executes them).

**Why.** A pure core is testable without a terminal, a network, or a fixture, and
it is provable (section 2). One interpreter means there is exactly one place
where IO order, file handles and process spawning can be wrong.

**Ruled out.** Effects in the core (the fold cannot run curl), a second
interpreter for tests (a fake runner would validate the argv the same file
produced and hide the exact class of bug it exists to catch), a global mutable
model.

**Proved by.** Five offline suites import the modules directly and need nothing
but the compiler; `tests/e2e.sh` exercises the seam the pure tests cannot see
(section 12). `--dry-run` is free: describing a request and sending it consume
the same plan.

### 2. Laws gate the build

**Decision.** `LAWS.bend` states properties over *every* value of the bound
variables; `PROOF.bend` discharges them (a proposition is a type, a def of that
type is a proof). `bend PROOF.bend` prints `ALL PROOFS CHECK` or `SOME PROOFS
FAIL`, and the commit routine runs it before committing (AGENTS.md's rule, not a
hook). Laws are never edited down to what happens to be provable: a law that will
not prove is a bug in the code.

**Why.** Some rules cannot be stated as examples without the example being the
only thing tested. The load-bearing ones: `verb_word_reaches_verb` (a verb
missing from the argv table compiles, proves nothing, is unreachable — this law
turns that gap into a failure), `writes_are_network` (a write verb that skipped
the network would report success without doing anything),
`array_items_round_trip`, `agent_output`, `engine_name_round_trip` (a name that
`Engine.name` prints must parse back to the same engine),
`media_flag_is_a_media_item`, and `the_timeout_floor_is_one_second` (curl reads
`--max-time 0` as no limit; the floor is 1).

**Ruled out.** Editing a law to fit the code; adding a verb without classifying
it (every `match` over `Verb` names every constructor, so a new one fails the
proof until classified).

**Proved by.** `bend PROOF.bend`. `bend PROOF.bend --verdict` re-checks with the
proven kernel; with Lean 4.34.0 installed it prints the same `ALL PROOFS CHECK`
and exits 0, which is the stronger claim: every def outside Base is a valid proof
that the Lean-verified kernel accepts, with no `@unsafe` and no foreign code.
Without a toolchain it fails loudly (`the kernel did not build ... needs Lean
v4.34.0`), so an absent kernel can never read as a pass.

### 3. Bend's rules shape the code; write with them

**Decision.** The code is written to the language's constraints, which are
stated where they are load-bearing:

1. **A def must be defined before it is called** — no forward declarations, and
   a call to a later def reads as an *unfilled law*. Files are callee-first;
   mutual recursion is impossible; each walk is one self-recursive def whose
   argument gets smaller.
2. **A recursive call may not sit inside a closure.** `IO.bind`'s continuation
   is a closure, so an effectful walk carries `fuel` and recurses as a direct
   argument, with the produced value arriving in a trailing parameter of exactly
   that effect's type.
3. **A `match` may scrutinise only a parameter or a field of one**, never a
   computed value. Derived facts are routed through `*_on` defs (`Argv.classify`,
   `Http.*_on`, the `*_on` defs in `src/update.bend`).
4. **A parameter is used once unless marked `+`**; a def handed to `IO.bind` as a
   value must *not* mark its parameters `+` (a reusable parameter is a different
   type).
5. **Only tail-safe string primitives walk whole values.** `String.take` and
   `String.length` are not tail-recursive; `String.drop` and `String.reverse`
   are accumulator-based, and the response split uses only the safe two. A
   138 KB body once took the program down with `memory fault (machine stack
   overflow?)` because splitting the status off the end cost one stack frame per
   character.

Commands run one at a time, not forked together: a fan-out inside a walk is what
rule 2 refuses. The seam stays where it matters — `Update.step` does not care
whether the interpreter fetched answers serially or in parallel, and the pure
core runs in parallel on the runtime's own terms.

**Ruled out.** Matching a computed value; recursing inside `IO.bind`; `+`
sprinkled to silence the affine checker; `String.take`/`String.length` on
anything a caller could make large.

**Proved by.** `bend src/effects.bend --check-only` is the whole rule set in
force; the e2e stand-in answers one route with ~300 KB so rule 5 cannot regress
unnoticed.

### 4. A request is data; the transport is one curl argv

**Decision.** A request is `D.HttpReq{method, url, headers, body, timeout_ms}`.
`Http.argv` builds the whole command line including the program name (that is
what `--dry-run` prints: a command a person can paste); `Http.args` is the same
list without the program, and that is what `Process.run(program, args, …)` gets.
Nothing goes through a shell — the argv is a list, so a tweet's text is one
argument, not syntax. The HTTP status is glued to the end of stdout by curl's
`--write-out` and split off positionally.

**Why.** Describing a request and sending it are the same data, so `--dry-run`
cannot drift from the real request, and shell metacharacters in content cannot
become commands.

**Ruled out.** The runtime's raw socket layer (no TLS, hand-written HTTP), a
vendor SDK, `sh -c "curl …"` (reintroduces quoting), reading the status from
headers (changes what the body is).

**Gotcha, and it is why the seam is tested live.** The first version handed the
whole argv to `Process.run`, so curl fetched a host named `curl`, failed, and
then fetched the real URL as a *second* request: status `000`, status glued to
the body head, two requests per call. Every offline test passed. `Http.program`
and `Http.args` are the split, and `tests/e2e.sh` asserts what the server
received, not what the program says it sent.

### 5. Settings arrive as items; one resolver reads them

**Decision.** The command line, the environment and the config file each reduce
to `List<Item{key, value}>`; precedence is list order (flag > environment >
config); one resolver reads the winner. `Cfg.resolve` takes what the caller has,
`Cfg.*_on` takes the environment and config file too, because a setting that can
be written in three places and then ignored is worse than one that does not
exist. `--count` and `--timeout-ms` are read from the item list rather than baked
into the verb, so they work before or after the verb they belong to. The config
file is one JSON object of flag names to values; a file that is not JSON, a key
the flag table does not know, or a value that is not a number is refused with a
`usage` error rather than ignored.

**Ruled out.** Per-verb flag reading (the parser cannot know `--count` belongs to
`search` when it comes after the verb's arguments), a settings record threaded
everywhere (it forces the whole config to be read even for `help`).

**One home per setting.** `RunCfg` carries only what a request builder reads.
The path settings the fold consumes — the config path, `--text-file`, `--fixture`
— live in `Start` and nowhere else: a second copy in `RunCfg` would have been a
value that could disagree with the one the reads used, and every record pattern
names every field, so dead state is charged again on every future field change.
Three such fields were removed for exactly that reason.

**Proved by.** `tests/argv_test.bend` (resolution and precedence; `--json`/tty
modes), `tests/update_test.bend` (a named config file is read, an unnamed one is
not, a config count reaches the request), and `tests/e2e.sh` (env and config
cases, bad numbers refused).

### 6. Deployment constants are settings, never compiled in

**Decision.** Everything that can rotate or belong to a deployment is a setting:
the GraphQL query ids (`--op-viewer`, `--op-tweet-detail`, `--op-search`,
`--op-create-tweet`), the web bearer, the features blob, `api_base`, the
timeouts, **and the hosts** — `--gql-base` (`https://x.com/i/api/graphql`),
`--mentions-url` (`https://x.com/i/api/2/notifications/mentions.json`) and
`--media-upload-base` (`https://upload.twitter.com/1.1/media`, the `/1.1/media`
prefix both uploader endpoints hang off). They are read through the same resolver
as everything else (section 5) and carried in `RunCfg`.

Settling the hosts was not cosmetic: it is what lets section 12 point the whole
write path at a stand-in and assert what went over the socket, which is how a
multipart bug that every offline test passed through was caught.

**Why.** These rotate on X's schedule, not ours, and a rebuild is not an
acceptable response to a rotated query id. Live, the bearer and four query ids
were pulled out of X's own client bundle and passed as settings, with no code
change: the four read verbs had been refused (403) until then.

**Ruled out.** Compiling a bearer or a query id into the source; a "constants"
module; re-deriving them at runtime (that is a scraper, not a program).

**Proved by.** `tests/api_test.bend` (configured query ids and features reach the
URL/body verbatim), `tests/update_test.bend`, and the live run: `whoami`, `read`,
`thread`, `replies`, `search` answered 200 with settings alone.

### 7. A credential is a shape; the engine follows from it

**Decision.** `Creds` is a sum type: `Anon`, `Session{auth_token, ct0, source}`,
`ApiKey{key, base_url}`. The shape *is* the engine choice: `Api.choose`
dispatches on it, so a session can only build GraphQL requests and a key can only
build Sweetistics ones. A missing credential is `Anon`, refused at the point of
use as an `auth` error whose hint names the setting to provide. `--engine`
decides which credential is read (graphql → session, sweetistics → key, auto →
key if present else session); the session carries the source string so `check`
can say where it came from without re-deriving it.

**Ruled out.** Empty-string sentinels (the failure surfaces as X's 401 instead of
a local refusal), one struct with optional fields, choosing an engine from
presence silently when `--engine` said otherwise.

**Proved by.** `tests/api_test.bend` (Anon refused before a request is built; a
keyed run reaches the Sweetistics route), `tests/update_test.bend` (an API key
reaches the Sweetistics host), `tests/e2e.sh` (no credentials → exit 3,
`"id":"auth"`, no request), live `whoami` with a real session (X's home answers
200 with the cookies and 307 to login without them).

### 8. An error is data: a stable id, a message, a hint, an exit code

**Decision.** Every failure is `Error{code, message, hint}`. Seven codes, stable
ids, fixed exit codes — contract, never reworded:

| id | exit | means |
| --- | --- | --- |
| `usage` | 2 | the command line or a setting is wrong |
| `auth` | 3 | the credential is missing or refused |
| `not_found` | 4 | X's 404 |
| `rate_limited` | 5 | back off, retry unchanged |
| `network` | 6 | curl could not complete the request |
| `upstream` | 7 | X failed or refused the request (5xx, or a 4xx not named above) |
| `internal` | 1 | a bug in this program |

One function maps HTTP status to code (401/403→`auth`, 404→`not_found`,
429→`rate_limited`; every other 4xx and every 5xx → `upstream`, because X
refused or failed the request and none of the local codes fit; a status below
400 that reached the mapper at all → `internal`). The mapper is only called for
a response at or above 400, and `ErrCode.retryable` is true for exactly
`rate_limited`, `network` and `upstream`. Retryability is *reported*, not acted
on: the failure envelope carries `retryable`, so a caller that backs off and
retries reads one boolean, and no run retries by itself. A failure keeps what it
has: the
status when a request happened, X's own body when X sent one, curl's own words as
a note when the request never started. A local failure carries status 0, which is
the honest answer for "there was no request". A usage error raised before a verb
is known does not name a verb.

**Ruled out.** Prose-only errors (the exit code alone cannot tell "you typed it
wrong" from "X is down"), HTTP status as the only code (says nothing about local
failures), one `internal` for everything local.

**A local file is not a network failure.** curl's exit 26 (a read error) and 37 (a
file it could not open) mean the file in `-F media=@path` could not be read, and
that is the only local file any request in this program puts in curl's argv. It
was classified by the generic branch, so a missing attachment came back as
`"id":"network","retryable":true` — an invitation to retry a path that will
never exist. Both statuses now map to `usage` with `retryable: false`, and the
hint names `--media`.

**Gotcha, found live.** The first version reported a 404, a 429 and a 500 all as
`status: 0`, because the failure path built a fresh model instead of carrying the
one the answer arrived on. Every offline test passed. `Model.failed_with` keeps
the status, and e2e asserts a 404 does not report zero.

**Gotcha, found live (2).** The missing-attachment case above reached the
envelope as a retryable network error, which no test could see until the write
path could be pointed at a stand-in and a path that is not there was actually
attempted. `tests/http_test.bend` pins the code and the boolean offline;
`tests/e2e.sh` runs the real upload with a missing path.

**Proved by.** `tests/http_test.bend` and `tests/update_test.bend` (status→code,
exit follows code), `tests/e2e.sh` (refused `--count` → 2 `usage`; no credentials
→ 3 `auth`; real 404 keeps its status; real 429 → `rate_limited` with the exact
body; real 500 → `upstream`; a local failure → `"status":0`).

### 9. One result, two renderings: envelope for machines, prose for people

**Decision.** `OutMode` picks the rendering, decided when settings resolve:
`--json`, `BIRD_JSON=1`, or stdout not a terminal → **agent mode**: exactly one
JSON envelope on stdout and nothing else. Success:
`{ok:true, verb, status, data, notes}`; failure:
`{ok:false, error:{id,message,hint}, status, body, notes}`. Notes ride inside the
envelope, so a warning can never land in the middle of the data. Otherwise
**human mode**: the payload indented with X's outer `data` member unwrapped; a
manual answer printed as itself; `null` prints `ok`; errors and notes go to
stderr (notes one per line), so stdout stays parseable. The exit code is part of
both contracts (section 8).

`OutMode.pick` is pinned by a law: agent-shaped exactly when asked or stdout is
not a terminal, never otherwise. Rendering is pure data, so both shapes are
testable without a terminal.

**Limitation, named.** There is no `isatty`; the tty is inferred from `TERM`
(absent or `dumb` means no terminal). So `bird read x | jq` typed at a terminal
gets prose, and an agent harness that exports `TERM` gets prose unless it passes
`--json` or `BIRD_JSON=1`. A pipe/pty case in e2e covers both directions.

**Ruled out.** Always-JSON, pretty JSON plus a log line on stdout, notes on
stdout in text mode, a mode decided in the renderer.

### 10. Refuse before the request is built

**Decision.** Every write is validated first, built second:

- A `tweet`/`reply` with no text is refused (`tweet has nothing to send`, exit
  2). Text comes from `--text`, `--text-file`, or config; the command line wins;
  both sources are checked by one predicate.
- A `--count`/`--timeout-ms` that is not a number is refused, **not defaulted**
  (`is not a number: abc`). A negative count is refused (a typo), `0` is a number
  and the clamp's business. Clamps: count `1..50`, ms `1000..120000`.
- A target with no id in it is refused (`that is not a tweet id, and none can be
  read out of it: abc`). Digits are what the extraction keeps, so an id, a
  `/status/<id>` url and a share url with a query string all work; anything else
  would have sent an empty `focalTweetId` or `in_reply_to_tweet_id`.
- Media rules run before a request exists, and the *credential* rule before a
  byte moves: unsupported type refused by name, at most four images, at most one
  video, more `--alt` than `--media` refused rather than dropped, no session →
  `auth` exit 3, `--fixture` refused for a write that is several requests.
- A refusal that arrives mid-queue still refuses: an upload X rejects, or an
  upload that comes back *without* a media id, fails the run with X's status and
  body rather than continuing to a post that would quietly lose a file.
- `mentions` needs a session, and says so instead of failing obscurely at X.

`--dry-run` renders the same plan the run would send, so description and request
cannot disagree.

**Ruled out.** Send-and-let-X-refuse (costs a round trip to learn something local
and makes dry-run useless as a check), defaulting a bad number, clamping `-1`,
dropping an unsupported attachment with a note (the tweet would go out looking
fine with no image).

**Proved by.** `tests/update_test.bend` (dry run sends nothing and asks for
nothing; a write with only a text file is accepted; media refused with `usage`),
`tests/argv_test.bend` (timeout clamps, default count), `tests/e2e.sh` (the
refusal cases listed above).

### 11. A media write is a queue of requests, folded like everything else

**Decision.** A write that carries attachments is not one request but a queue:
per file an upload, then (when it has alt text) an alt call that names the id its
upload returned, and finally the `CreateTweet` carrying every collected id in
`media_entities`. The queue is data: `Api.media_jobs` builds it from the verb's
media; `PhaseMedia{jobs, done}` holds what is left and the ids so far; the fold
pops the head, spends the answer's `media_id_string` (falling back to
`media_id`), and only when the queue is empty builds the post. One request id
covers the whole queue — uploads run one at a time — which is why routing on
the answer asks "is this a media phase?" rather than which id came back.

A failure mid-queue reports the ids already uploaded as a note
(`already uploaded, still usable: 111, 222`). There is no upload to cancel and no
rollback endpoint to call, so the one honest thing a half-finished queue can hand
back is the state a retry would otherwise pay for again.

**Why.** X's upload endpoint takes one file per request and an alt text is a
separate call, so the alternative is a request builder that cannot be expressed
as one `HttpReq` anyway. Keeping the queue in the model rather than in an effect
keeps the whole flow testable without a network: a scripted upload answer, then a
scripted alt answer, then asserting the post's body.

**Ruled out.** A loop inside the interpreter (it would put the write's state
outside the fold, where no test can see it); chunked/`INIT`-`APPEND`-`FINALIZE`
video upload (a large video therefore comes back as X's own refusal — see
Consequences); folding `media_entities` after the fact (the post cannot be built
before the ids exist).

**Proved by.** `tests/api_test.bend` (job order, the multipart part, the alt
body, the post carrying both ids, the `media-plan` dry run, and each credential
refusal), `tests/update_test.bend` (the queue end to end through the fold,
including a refused upload and an id-less upload), and section 12's live case.

### 12. Test the seam over a real socket; a skip is not a pass

**Decision.** `tests/e2e.sh` runs the program through the command line — nothing
imports a module — and the transport cases put a stand-in server
(`tests/live_server.py`) on a port the *operating system chooses* (port 0, port
handed back through a file). The stand-in logs every request, and one case
asserts *what the server received*: exactly one request per verb, POST, with the
variables as the body. Another asserts the request is not sent twice to a host
named curl. One route answers ~300 KB. Because every host is a setting
(section 6), the same block also runs the two features that are more than one
request against that stand-in: a media write (`--media-upload-base`,
`--gql-base`) and `mentions` (`--mentions-url`), with the server's log asserted
afterwards — one multipart upload carrying the file, the alt call naming the id
that came back, then the `CreateTweet` holding it. A case that cannot run here
(no curl, no python3, no pty) is recorded as **skipped** and counted separately,
never as a pass. The transcript (`tests/e2e_artifact.txt`, `BIRD_E2E_OUT` to
redirect) is the artifact: per case, the command, the exit code, and the output.

The guides are checked by the same script: every `--flag` named in
`docs/guides/*.mdx` must be accepted by the parser, because a guide is not
compiled and a flag that stops existing is a document that quietly lies.

A fixed port was tried and abandoned: a stale server answered in the stand-in's
place and the run passed against the wrong process.

**Ruled out.** Re-implementing requests in python, a fake process runner (it
would hide the producer/consumer bug), silent skips, only-live testing (needs
credentials, cannot produce 404/429/500 on demand).

**Live against X, by hand.** `whoami` (real account), `read 20`
("just setting up my twttr"), `thread`, `replies`, `search rust --count 5`
(today's tweets) — all 200, with all of the above in force. The repeatable
artifact remains the stand-in; credentials never enter the repo.

## Consequences

* **Good:** there is exactly one place where IO can be wrong, and the pure core
  is provable, so a bug that survives must be at a seam the tests already cover.
* **Good:** `--dry-run` is structurally incapable of drifting from the real
  request, because they consume the same plan.
* **Good:** an agent can branch on a stable id, an exit code, a status, and a
  body, without parsing prose.
* **Good:** rotated bearer/query ids cost a settings change, not a release.
* **Bad:** the code is unusual to a Python-shaped reader (callee-first files,
  `*_on` defs, `fuel` walks), and that reads as ceremony until the language
  rules are known — which is why they are stated at the top of the files that
  lean on them.
* **Bad:** the tty is a `TERM` proxy, not `isatty`, so a pipe typed at a
  terminal is misread as human output unless `--json`/`BIRD_JSON` is passed.
* **Bad:** an unnamed 4xx maps to `upstream`, and `upstream` is retryable; a
  request X has permanently refused could be retried unchanged. Accepted for now
  (no observed harm; the named statuses cover the real cases), and the first
  place to change if an agent reports retry churn.
* **Bad:** a media write is up to nine requests (four images, each with an alt,
  plus the post), and it is not atomic: a failure mid-queue leaves the uploads X
  already accepted unattached. There is no rollback endpoint to use, so the run
  fails loudly with X's own status and names the ids it already has in `notes` —
  the state a retry would otherwise pay for again. `--dry-run` shows the whole
  plan before any of it happens.
* **Bad:** a video is a one-shot upload with `media_category=tweet_video`. A file
  large enough for X to insist on `INIT`/`APPEND`/`FINALIZE` comes back as X's
  own refusal rather than a silent half-upload, which is accepted until someone
  needs to post one.
* **Good:** `PROOF.bend --verdict` runs here (Lean 4.34.0 via `elan`): the laws
  are re-checked by the Lean-proven kernel, not just by bend2. Running it needs
  the toolchain, so it stays a local, on-demand gate rather than part of the
  ordinary loop.

## Non-goals

- Not a general HTTP client, not a scraper, not a library: one binary, one
  command line, and requests whose shapes are settings.
- No OAuth and no login flow. The program reads a credential; it does not obtain
  one, and it never writes one to disk.
- No second machine-readable output shape, no color, no pager, no streaming.
- No CI service, no test matrix. The gates are local: `bend PROOF.bend` and
  `bash tests/e2e.sh`.
- No retries, no redirects, no rate-limit backoff inside a run. Retryability is
  reported to the caller and the caller decides.

## Implementation Plan

* **Affected paths**: `src/` (the nine modules, each header comment carries the
  rules it leans on), `tests/` (five offline suites, `e2e.sh`,
  `live_server.py`), `docs/decisions/0001-design-bird.md` (this file),
  `docs/guides/*.mdx` (the task-shaped guides), `docs/learnings/`, `AGENTS.md`,
  `README.md`, `CHANGELOG.md` (release notes; `bird version` prints the version
  the newest entry names).
* **Dependencies**: none added. Runtime needs `curl`; the e2e transport block
  needs `python3` and `curl`; the language is Bend 2 (`~/.bend/bin/bend` here).
* **Patterns to follow**: callee-first files; a `*_on` def when a `match` needs a
  derived fact; `fuel` + trailing produced value for effectful walks; `+` only
  where reuse is intended; `Http.program()`/`Http.args()` for the transport;
  `err`/`err_hint` with the section-8 vocabulary; render through `View`, never
  print from the core.
* **Patterns to avoid**: `String.take`/`String.length` on a response body;
  matching a computed value; recursing inside `IO.bind`; building a request
  before a write is validated; putting stdout prose beside a JSON envelope;
  renumbering an exit code or rewording an error id.
* **Configuration** (all read through one resolver; flags of the same name win,
  then environment, then `BIRD_CONFIG`'s JSON file): `BIRD_AUTH_TOKEN`,
  `BIRD_CT0`, `BIRD_ENGINE`, `BIRD_COUNT`, `BIRD_TIMEOUT_MS`, `BIRD_JSON`,
  `BIRD_FIXTURE`, `BIRD_TEXT_FILE`, `BIRD_CONFIG`,
  `BIRD_SWEETISTICS_API_KEY`, `BIRD_SWEETISTICS_BASE_URL`, `BIRD_WEB_BEARER`,
  `BIRD_GQL_FEATURES`, `BIRD_OP_VIEWER`, `BIRD_OP_TWEET_DETAIL`,
  `BIRD_OP_SEARCH`, `BIRD_OP_CREATE_TWEET`, `BIRD_MEDIA_UPLOAD_BASE`,
  `BIRD_GQL_BASE`, `BIRD_MENTIONS_URL`.

### Verification

- [x] `bend src/effects.bend --check-only` — the program and its imports
  type-check under every rule in section 3.
- [x] `bend PROOF.bend` — prints `ALL PROOFS CHECK` (section 2).
- [x] Offline suites, 249 cases, 0 failures (`json` 25, `argv` 46, `http` 29,
  `api` 48, `update` 101): `bend tests/argv_test.bend`, `tests/api_test.bend`,
  `tests/http_test.bend`, `tests/json_test.bend`, `tests/update_test.bend`.
  Covers sections 4–11.
- [x] `bash tests/e2e.sh` — 67 cases, 67 ok, 0 failed, 0 skipped: command line,
  envelope, exit codes, `retryable`, dry runs, wire-log assertions, the media
  write (upload → alt → post) and the mentions read against the stand-in, the
  300 KB body, the pty case, the schema's defaults, and the guides' flags
  (sections 4, 6, 8, 9, 10, 11, 12).
- [x] Live against X by hand once: `whoami`, `read 20`, `thread 20`,
  `replies 20`, `search rust --count 5` — all HTTP 200 with real payloads
  (sections 6, 7). The repeatable artifact remains the stand-in server.
- [x] `bend PROOF.bend --verdict` — `ALL PROOFS CHECK`, exit 0, with Lean 4.34.0
  installed: the kernel accepted every def outside Base, so the laws are valid
  proofs rather than merely type-checked ones. Without the toolchain the same
  command exits 1 naming the missing version, which is asserted by running it
  with the toolchain hidden.
- [ ] A live write (`tweet`/`reply`) against X itself — dry-run only until the
  operator approves posting from the real account. The same request shapes are
  exercised end to end against the stand-in server, log asserted, including the
  media queue.

## More Information

- Revisit triggers: X rotates the bearer/query ids (settings absorb it, no code
  change); an agent reports retry churn on an unnamed 4xx (see Consequences);
  Bend gains `isatty` (replace the `TERM` proxy); a video needs chunked upload
  (add `INIT`/`APPEND`/`FINALIZE` jobs to the queue, which is built for it);
  `--fixture` needs to answer a multi-request write (it would have to answer the
  queue, not one body).
- The environment's cookies live in `~/.env` as `TWITTER_AUTH_TOKEN` /
  `TWITTER_CT0`; the bearer and query ids are not stored there and were
  extracted from X's own bundle for the live run. Nothing sensitive was written
  into the repo.
- Implementation gotchas that cost a live run each live in `docs/learnings/`,
  one file per surprise: the print-vs-run argv, `String.take`'s stack cost, the
  failure envelope that lost its status, the stale stand-in server, what X's
  GraphQL really requires, `curl`'s flag-before-its-value order, matching a
  computed value, a new record field sweeping every pattern, a flag value that is
  also a verb word, and `<>` being cons rather than concatenation.
- Related: `AGENTS.md` (how to run the gates), `tests/e2e_artifact.txt` (the
  last transcript), `LAWS.bend` / `PROOF.bend` (the laws this record's section 2
  describes).
- This record supersedes the earlier per-decision drafts, which were folded into
  this file on the operator's instruction.
