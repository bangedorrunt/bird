# bird

Post and read X/Twitter from a terminal, a shell script or an agent.

Written in [Bend](https://bend-lang.com), a language where the pure core of a
program is a set of total functions and every claim about them is a *law* that
has to be proved before the code is allowed to ship. That is the point of this
rewrite: the decisions live in pure functions, the laws state what those
decisions must do for *every* input, and `bend PROOF.bend` gates the build on
them.

## Where this is

The whole program is written: the pure core is proved and tested, and the thin
interpreter at the edge is covered end to end by `tests/e2e.sh`, which runs the
program the way a caller does and keeps the transcript.

Task-shaped documentation lives in `docs/guides/`: setup and credentials, login,
writing, media, reading, mentions, and the contract an agent sees.

| | |
|---|---|
| `src/json.bend` | JSON: a lossless encoder, a stack-machine decoder, a pretty printer. No JSON in Base, so this exists. |
| `src/tweets.bend` | X's answers into the tweets that are in them: the three response shapes folded into one, so a read answers with the tweet rather than with the envelope around it. |
| `src/domain.bend` | The vocabulary: verbs, credentials, items, errors, requests, the model and the step. Pure data, no behaviour. |
| `src/scan.bend` | Text walking: finding a needle in a large document and reading the tokens around it. Exists because X's client bundle is over a megabyte. |
| `src/policy.bend` | Every decision that is not a side effect: which engine, which credentials, which settings win, what a tweet id is, which media a post may carry. |
| `src/argv.bend` | The command line into items: flag and verb tables, `--help` text, machine-readable schema. |
| `src/cookies.bend` | The session out of a browser's own cookie store: the `sqlite3`/`security`/`openssl` calls Chrome's recipe needs, and the reading of what they answer. |
| `src/bundle.bend` | X's client bundle into the rotating settings: the script's url, the bearer, and one operation id per operation, each refused by name when it is absent. |
| `src/http.bend` | The transport *described*: one request to one curl argv — literal body or multipart form — curl's answer back into a status and a body, failures into error codes. |
| `src/api.bend` | The requests each verb sends: one constructor per verb, the media upload queue, the headers each credential shape carries, the variables, the operation ids and the hosts. |
| `src/update.bend` | The fold: a run is a state machine over messages, and `Update.step` is the whole of it. Config file, text file, fixture and answer, in rounds. |
| `src/view.bend` | What the run prints, as data: the agent envelope, the tweets as a block each on a terminal, and the indent rendering for everything else. |
| `src/effects.bend` | The interpreter, and the only place IO happens: argv, environment, file reads, `curl`, printing, and `main`. |
| `LAWS.bend` / `PROOF.bend` | Nine laws and their proofs. |
| `tests/*_test.bend` | Eight runnable programs, 472 cases, each dying with a nonzero exit on the first failure. |
| `tests/e2e.sh` | The real command line, 87 cases, writing `tests/e2e_artifact.txt`. |
| `tests/live_server.py` | A stand-in backend so the transport can be exercised over a real socket without reaching X: the four operations, the media service and the mentions timeline. |
| `CHANGELOG.md` | Release notes, [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. `bird version` prints the version the log's newest entry names. |

## Run it

The program is one file, so it runs without being built — and it compiles to a
binary that needs nothing but `curl` at runtime:

```sh
bend src/effects.bend -- read 12345 --json   # run it from source
bend src/effects.bend -o bird                # compile it (needs clang)
install -m 0755 bird ~/.local/bin/bird       # then: bird read 12345 --json
```

`./install.sh` is those last two lines, plus a `PREFIX=` to choose where it lands
(default `~/.local/bin`) and a check that what was installed answers
`bird version`. It needs `bend` — on PATH, or at `~/.bend/bin/bend` — and clang.

`bird` reads its settings from flags, the environment or a `BIRD_CONFIG` file;
`bird help` prints the manual and `bird schema --json` the whole contract.

## Log in

Every verb reads a credential; `login` is the one that obtains one. It reads the
session out of a browser you are already signed into and the values X rotates —
the web bearer and the four operation ids — out of X's own client bundle, and
writes both into one settings cache:

```sh
bird login --cookie-source chrome
bird mentions --count 20 --json     # reads the cache; no credential flags
```

Firefox is one `sqlite3` read because its values are plain text; Chrome's are
encrypted, and the run derives the key from the login keychain with `openssl`,
decrypts the two cookies, and takes the blobs away again. `--chrome-key` supplies
that key directly, which is what makes the recipe testable without a keychain and
usable on a machine that keeps its key elsewhere. A keychain that answers nothing
is an auth failure naming `--chrome-key`, never a cache written with a
wrongly-decrypted value in it.

The cache is a JSON object whose keys are flag names and is written `0600`;
`login` never reads it, so a corrupt one is something `login` repairs rather than
something that stops the repair. With no source, `login` refreshes the rotating
settings for the session it already has. It is also the one verb that runs local
programs, so all four of its refusals happen before the keychain is asked or a
byte is written.

## Verify it

```sh
bend PROOF.bend            # ALL PROOFS CHECK, or SOME PROOFS FAIL
bend src/effects.bend --check-only
bash tests/e2e.sh            # 87 cases against the real command line
bend tests/json_test.bend    # 25 cases
bend tests/argv_test.bend    # 46 cases
bend tests/http_test.bend    # 29 cases
bend tests/api_test.bend     # 48 cases
bend tests/scan_test.bend    # 31 cases
bend tests/bundle_test.bend  # 37 cases
bend tests/tweets_test.bend  # 63 cases
bend tests/update_test.bend  # 193 cases
```

`bend LAWS.bend` on its own prints the open claims (one TODO per law); that is
what an unproved law looks like, and `PROOF.bend` is what closes them.

`bend PROOF.bend --verdict` re-checks with a kernel that has a proof in Lean and
refuses `@unsafe` or foreign code. It needs Lean 4.34.0 (`elan`); with the
toolchain installed it prints `ALL PROOFS CHECK` and exits 0, which is the
mathematical verdict rather than the ordinary gate.

`tests/e2e.sh` needs `bend` on `PATH`, a POSIX `sh`, and — for the last block of
cases — `curl` and `python3`. It builds its fixtures in a temporary directory, runs
`bend src/effects.bend -- <args>` for each case, asserts the exit code and one
substring of stdout, and writes the whole transcript to `tests/e2e_artifact.txt`:
the command, the exit code and the output per case, so a failure can be read and
rerun by hand. That is the artifact a reviewer checks; the assertions are for the
exit status.

That last block starts `tests/live_server.py` on a port the operating system
picks and points the program at it as the `sweetistics` backend, so the transport
runs for real: a real `curl` process, a real socket, real statuses and a real body.
One of its routes answers with 210 KB, because a body that size is what found the
bug described under **Against X** below. A case that cannot run for want of a tool
is reported as skipped, never as a pass.

Every host is a setting, so the same block also runs the two features that are
more than one request against that stand-in: a media write (`--media-upload-base`
and `--gql-base`) and the mentions timeline (`--mentions-url`). The media case
checks the server's log afterwards — one multipart upload carrying the file, the
alt call naming the id that came back, then the `CreateTweet` whose
`media_entities` hold it — which is what found the `-F` ordering bug below.

## The laws

A law is a claim about every value, not an example. Each one is proved in
`PROOF.bend` by a def of the same name, and each was mutation-tested: break the
code it describes and that law, and only that law, fails.

| law | what it pins |
|---|---|
| `engine_name_round_trip` | An engine name that came out of `Engine.name` parses back to the same engine. |
| `engine_name_spelling` | The three names are exactly `graphql`, `sweetistics`, `auto`. This is the one that catches a typo, which would otherwise still round-trip. |
| `agent_output` | Output is agent-shaped exactly when `--json` was asked for **or** stdout is not a terminal, and never otherwise. |
| `array_items_round_trip` | `items(arr_of(xs)) == xs` for every list, by induction. |
| `writes_are_network` | Every verb that writes talks to the network. A write that skipped it would report success without having done anything. |
| `verb_word_reaches_verb` | Every verb the domain can carry is reachable by typing its name. A verb missing from the argv table is unreachable, and no test spelling its name would ever be written. |
| `media_flag_is_a_media_item` | `--media` becomes a media item, not a setting, because the media policy reads the item list. A downgrade would drop the attachment silently. |
| `alt_flag_is_an_alt_item` | Same for `--alt`. |
| `the_timeout_floor_is_one_second` | A sub-second budget floors at 1, never 0: curl reads `--max-time 0` as "no limit", which is the opposite of a timeout. |

## How the code is shaped, and why

Bend 2 is not Python. Four rules did most of the shaping here, and knowing them
saves the next reader a lot of confusion:

1. **A def must be defined before it is called.** There are no forward
   declarations, and a call to a def that appears lower in the file is read as an
   *unfilled law* — the error says "a filled definition". So every file reads
   callee first, and mutually recursive "state machine" modules are impossible.
   Loops are therefore single self-recursive defs whose first argument shrinks,
   with the branch that continues the loop written inside them. `src/effects.bend`
   states the sharper version: a recursive call may not sit inside a closure, so
   a walk that performs one effect per element carries `fuel` and recurses as a
   direct argument, with the value the effect produced arriving in a trailing
   parameter. Only one def recurses per walk — the run's own loop is one def
   carrying its pending work.
2. **A `match` may only scrutinise a parameter or a field of one**, never a
   computed value. So `match is_flag(tok):` is refused. Every branch on a
   derived fact is routed through a def that takes that fact as a parameter and
   matches on it instead. `Argv.classify`, `Http.*_on` and the `*_on` defs
   throughout `src/update.bend` are all that pattern.
3. **A parameter may be used once** unless it is marked `+`, which is why
   signatures carry `+name: String` wherever a message is built from a name
   twice. The same holds for a field bound by a pattern: `case Resp{+status, …}`.
4. **A def used as a value** — handed to `IO.bind` rather than called — must not
   mark its parameters `+`, because a reusable parameter is a different type.

The upshot is a program split into a pure core that is provable and a thin IO
shell. `--dry-run` is free: describing a request and sending it are separate
functions, and the fold only ever returns data.

## The interface an agent sees

`bird <verb> [flags]`, rendered by `Argv.help_text()`. Flags may come before or
after the verb. A bare word after the verb is its text, so `bird tweet hi` and
`bird tweet --text hi` agree. An unknown flag, a flag without its value, a verb
without its argument, a stray word, and a target with no id in it are all refused
by name, because an agent that misspells a flag and gets silence cannot tell that
from a request that asked for nothing.

Exit codes are the contract:

| 0 | 2 | 3 | 4 | 5 | 6 | 7 | 1 |
|---|---|---|---|---|---|---|---|
| ok | usage | auth | not found | rate limited | network | upstream | internal |

Every failure carries a stable `ErrCode.id` (`usage`, `auth`, `not_found`,
`rate_limited`, `network`, `upstream`, `internal`) so a branch needs no parsing,
plus a one-line message, a hint saying what to do about it, and `retryable` —
true for exactly `rate_limited`, `network` and `upstream`, so a caller backing off
and retrying reads one boolean instead of keeping that table itself. Nothing in a
run retries on its own.

The output is one JSON envelope on stdout when `--json` is passed, when
`BIRD_JSON=1` is set, or when `TERM` is empty or `dumb`. Otherwise a terminal
gets the data indented, and a failure is `bird: <message>` plus its hint on
stderr. **`TERM` is a proxy, not a fact**: Bend has no `isatty` and `Process.run`
gives its child pipes, so nothing can ask whether this process's stdout is a
terminal. A script that pipes `bird` while `TERM` is set in the environment gets
the terminal rendering, so pass `--json` rather than relying on the detection.

Settings resolve in one order — flag, then `BIRD_<FLAG>` (uppercased, `-` to `_`),
then the config file, then the default. `BIRD_CONFIG` names a JSON object whose
keys are flag names:

```json
{ "--engine": "graphql", "--count": 5, "--op-viewer": "Viewer" }
```

A key the flag table does not know is refused by name, and so is a content flag —
`--text`, `--media` and `--alt` say what one post is, not how the program
behaves, and a config file that posted the text it happened to hold is a worse
failure than a refusal.

The deployment-specific values stay settings rather than constants, because all
of them rotate on X's side: `--web-bearer`, `--gql-features`, the four operation
ids, and the hosts themselves (`--gql-base`, `--mentions-url`,
`--media-upload-base`). A missing one is an error naming the flag, not a request
built from a guessed constant. `--fixture PATH` answers a run from a file through the
same fold a live response takes, which is how a request can be exercised without
a network; `--dry-run` prints the curl argv it would have run instead.

## Against X

A live run against X is what these settings are for. The bearer, the four
operation ids and the feature blob all come from X's own web client, which
rotates them; none is compiled in:

```sh
# the web bearer and one queryId per operation, out of X's client bundle
bird whoami --auth-token "$TWITTER_AUTH_TOKEN" --ct0 "$TWITTER_CT0" \
  --web-bearer "$BEARER" --op-viewer "$VIEWER_QID" --gql-features "$FEATURES"
bird read 20  --op-tweet-detail "$DETAIL_QID" --gql-features "$FEATURES" ...
```

A live pass on 2026-10-11, with those settings taken from the running web client,
verified `whoami`, `read`, `thread`, `replies` and `search` against the real
service, all four answering 200 with real payloads. The same pass found four
things no offline test could, and they are fixed:

- the argv handed to `curl` began with `curl`, so curl fetched a host of that name,
failed, and then fetched the real url as a second request. `Http.args` and
`Http.program` now split the two, and the dry run still prints the whole command.
- `TweetDetail` was refused with a 422 because X validates variables before it runs
anything. X's own answer named the three missing ones, one round trip at a time;
`Api.gql_focal` now sends them.
- a 138 KB reply took the program down with a stack overflow: `String.take`, which
is not tail-recursive, was splitting the status off the end of the body one stack
frame per character. The split now walks with `drop` and `reverse`, both of which
recurse with an accumulator, and the body may be any size.
- a failure envelope reported `status` 0 for a 404, a 429 and a 500 alike, losing
the one number that told them apart. An HTTP failure now carries its status; a
failure with no request behind it still reports 0, which is the honest answer.

A second live pass, this time against the stand-in with every host as a setting,
found one more thing no offline test could:

- the multipart upload was built as `-F` *followed by* nothing at all: the
  accumulator that collects the parts is reversed on the way out, and the pair was
  written flag-first, so `-F` ended up after its own argument. `curl` answered
  "option -F: is badly used here" on the first live upload. The offline tests only
  read the parts list, which was right either way, so `tests/http_test.bend` now
  compares the whole argv of a multipart request and `tests/e2e.sh` runs a real
  upload over a socket and checks what the server received.

## Not done

- **A real terminal check.** See the caveat above: the rendering is chosen by
  `TERM` because nothing better is reachable.
- **The write half, live against X.** `whoami`, `read`, `thread`, `replies` and
  `search` were run against X; `tweet` and `reply` were not, because posting is a
  side effect on a real account and `--dry-run` describes the request without
  sending it. They *are* exercised end to end against the stand-in: a media write
  runs its whole queue (upload, alt text, `CreateTweet` carrying the ids) over a
  real socket, and the server's log is asserted. Their variables are the ones X's
  client sends for `CreateTweet`, but no post has been made from the real account.
- **`login` against a real browser profile.** The Chrome recipe is exercised for
  real — a database built in Chrome's own shape, ciphertext encrypted the way
  Chrome encrypts it, a real `openssl` derivation and decryption, and the session
  the stand-in received asserted afterwards — but the key comes from `--chrome-key`
  rather than a live keychain, and no run has yet opened a real profile.
- **Video chunking.** A video is a one-shot upload with
  `media_category=tweet_video`. A file large enough for X to insist on `INIT`/
  `APPEND`/`FINALIZE` comes back as X's own refusal rather than a silent
  half-upload.
