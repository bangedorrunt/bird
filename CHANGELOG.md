# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This is the first public release. Earlier iterations were not published, so the
log starts at `0.3.0`.

## [Unreleased]

### Added

- **A read answers with the tweet, not with the envelope it arrived in.** X wraps
  one tweet in about 119 KB of timeline entry ids, cursors, the author's whole
  profile blob and the client's feature flags, with the text six levels down
  inside it. `src/tweets.bend` is that walk, done once in the pure core, and
  `read`, `replies`, `thread`, `search`, `mentions` and `whoami` all answer with
  one shape: `data.tweets[]` of `id`, `text`, `lang`, `created_at`, `author`
  (`id`, `handle`, `name`, `verified`, `avatar`), `metrics`, `media`, `urls`,
  `quoted` and `in_reply_to`, with a count X did not send as `null` rather than
  `0`. `read` narrows to the tweet that was asked for; a long post answers with
  the `note_tweet` text rather than the truncated line beside it; a quoted tweet
  is one level deep. The three response shapes it reads — GraphQL timelines, the
  notifications endpoint's top-level v1.1 tweets with their authors in a map
  beside them, and `whoami`'s viewer — are described in `src/tweets.bend`.
- **`--raw`**: answers with the body X sent, unwrapped and untouched, for the
  times the fold has thrown away something a caller wanted. It is the only way to
  see the envelope again.
- **A terminal gets the tweets.** A read printed as indented JSON answered a
  terminal with brackets and quotes around the two things the reader came for, so
  each tweet is now one block: the head, the text, one line per attachment, the
  quote, the reply target, and a last line of the id and the counts X sent. A
  field X did not send drops out of its line instead of leaving an empty slot, an
  answer holding no tweet says `no tweets`, and every other payload keeps the
  indent rendering.
- `scripts/check-beads-ledger.sh`: fails closed on a beads-ledger row-set
  regression before `.beads/` is committed. `.beads/issues.jsonl` is a
  full-snapshot export, so a worktree writing it from its own older sqlite drops
  the beads another lane closed; a gate verdict can be lost the same way, and a
  lost verdict is what makes a close unprovable. It also reads commit subjects, so
  a bead a commit claims to close cannot be sitting open. `--self-test` exercises
  the guard itself against its own fixtures, `--base origin/main` is the CI shape,
  and `--force "<why>"` publishes a deliberate reopen loudly.
- `install.sh`: compiles the CLI and installs it, with `PREFIX=` to choose where
  (default `~/.local/bin`) and a `bird version` check of what was installed. The
  build happens in a temporary directory and is moved into place, so a failed build
  leaves the copy already on PATH alone and leaves nothing in the repo.
- **`login`**: reads the session out of Chrome or Firefox and the rotating
  settings — the web bearer and the four operation ids — out of X's own client
  bundle, and writes both to a settings cache every later run reads with no
  credential flags. Chrome's cookies are decrypted with the key from the login
  keychain (`--chrome-key` supplies it directly, which is what makes the recipe
  testable and what a machine with an unusual keychain needs); Firefox's are read
  with one `sqlite3` query. A wrongly-decrypted value is a refusal naming
  `--chrome-key`, never a cache written with it. See `docs/guides/login.mdx`.
- `--settings-path`: where that cache lives, default
  `$HOME/.config/bird/settings.json`. It is read by every verb in the same first
  round as the config file, and loses to it, so a stale cache never overrides a
  setting someone wrote down. `login` itself does not read it.
- `--cookie-source`, `--cookie-db`, `--chrome-key`, `--web-home` and
  `--bundle-base`: the login flow's settings. The last two are settings rather
  than constants so the flow can be exercised against a stand-in, which is how
  `tests/e2e.sh` checks it over a real socket.
- The two session cookies are also read from `TWITTER_AUTH_TOKEN` and
  `TWITTER_CT0`, the names a shell that already talks to X exports. Both spellings
  work and neither is deprecated; when both are set, `BIRD_AUTH_TOKEN`/`BIRD_CT0`
  wins, so one extra variable overrides an inherited shell value.

### Fixed

- A mentions entry carrying no `id_str` answered an empty timeline. A tweet was
  recognised by `id_str` beside a top-level `full_text`, but the map key is also
  the id and a real answer can leave the field out — so the walk dropped every
  mention over a field it does not need. The text at the top level is what marks
  the shape now, and the id is read from `id_str` when X sent it.
- `bird login` with no `--settings-path` failed on a fresh machine: the default is
  `$HOME/.config/bird/settings.json`, and opening it where that directory has never
  been made reports the OS's own "no such file or directory", which names the file
  rather than the missing directory. The directory is now made first, the same way
  the flow runs every other program, so the default path works on a first run.
  Found by running the installed binary by hand; the suite had pre-created that
  directory for reasons of its own and could not see it.
- `tests/e2e.sh` now clears every environment name the program reads before the
  first case. A shell that exports a real session would otherwise let the
  "no credentials" case find it and reach X.
- The e2e transcript folds the run's temp directory and the stand-in's port to
  `<work>` and `<port>` as it is written. Both are different every run, and the
  committed artifact differed from itself for no reason a reader could act on.
- The login wire case asserted a fixed number of requests to the page and to the
  bundle, so adding a login case failed it for no reason and removing one would
  have kept it green through a real regression. It now reads **every** row and
  asserts the two facts that matter: the session reached the page each time, and
  never reached the bundle.

## [0.3.0] - 2026-10-11

### Added

- **Verbs**: `tweet`, `reply`, `read`, `replies`, `thread`, `search`, `mentions`,
  `whoami`, `check`, `help`, `schema`, `version`.
- **Writes**: `tweet` and `reply` with `--text`, `--text-file`, or attachments.
  Text from a file fills a write that named none; a write with neither is refused
  before a request is built.
- **Media attachments** (`--media`, `--alt`): a folded queue of requests —
  multipart `POST /upload.json`, then the alt-text call naming the id the upload
  returned, then the post carrying `media_entities`. Up to four images or one
  video, never a mixture; `jpg`/`jpeg`/`png`/`webp`/`gif`/`mp4`/`m4v`/`mov`. The
  alt is positional against the media it describes.
- **`mentions`**: X's notifications timeline, the one `GET` the program sends,
  with `--count` clamped to 1..50.
- **Two engines**: X's GraphQL over a session (`--auth-token`, `--ct0`,
  `--web-bearer`, `--op-*`, `--gql-features`), or Sweetistics over an API key
  (`--sweetistics-api-key`, `--sweetistics-base-url`). The credential shape picks
  the engine.
- **An agent contract**: one JSON envelope on stdout, seven stable error ids, a
  fixed exit code per id (`0` ok, `2` usage, `3` auth, `4` not_found, `5`
  rate_limited, `6` network, `7` upstream, `1` internal), `error.retryable`, X's
  own body kept verbatim, curl's own words as notes, and `--dry-run` printing the
  exact argv a real run would hand curl.
- **Hosts as settings** (`--gql-base`, `--mentions-url`, `--media-upload-base`),
  which is what lets the whole write path run against a stand-in server.
- **Laws**: `LAWS.bend` states the claims, `PROOF.bend` discharges them;
  `bend PROOF.bend` is the gate and `--verdict` re-checks with the Lean-proven
  kernel.
- **Tests**: five offline suites (249 cases) plus `tests/e2e.sh` (67 cases) over a
  real socket against `tests/live_server.py`, and `docs/guides/*.mdx` whose every
  `--flag` the e2e asserts the parser accepts.
- **Docs**: an ADR recording the design decisions, task-shaped guides, and
  `docs/learnings/` for the failures that cost a surprise.

### Changed

- `--fixture` answers a single request. A media write is several, so the flag is
  refused by name for one rather than answered with a body that would have to be
  a lie.

### Fixed

- Multipart uploads failed against a real server (`option -F: is badly used
  here`): the `-F` flag was emitted after its own value. Every offline test read
  the parts list, which was right either way; only a live upload caught it.
- A `--media` path that cannot be read was reported as a `network` failure with
  `retryable: true`, inviting a retry of a path that will never exist. curl's
  local-read statuses (26, 37) now map to `usage` with `retryable: false`.
- A failure dropped the HTTP status it arrived with: a 404, a 429 and a 500 all
  reported `status: 0`. The status is now carried onto the failed model.
- A response body of 138 KB crashed the program (`machine stack overflow`):
  `String.take` and `String.length` are not tail-recursive, so the status is now
  split off the end of the body with `String.drop` and `String.reverse`.
- Requests went out with an argv that began with `curl`, so curl fetched a host
  named `curl` and reported status `000` with the status glued to the body.
- The human output path was unreachable: a terminal was detected by asking a
  child `test -t 1`, whose stdout is always a pipe. Detection is now `TERM`, with
  `--json`/`BIRD_JSON` to force the envelope.
- An upload X accepted without naming a media id is a failure rather than a post
  that quietly loses its attachment.
- A config file that cannot be read left the round open (`pending` stuck at 1),
  stalling a run that had nothing left to wait for.
- `--count` and `--timeout-ms` typos are refused by name instead of silently
  falling back to the default.
- A failure inside the media queue now names the uploads X already accepted in
  `notes`, so a retry can reuse them instead of sending the same bytes again.

### Removed

- Write-only state that no branch read, and which every record pattern had to
  name on every change: `Model.next_id`, `RunCfg.fixture`, `RunCfg.text_file`,
  `RunCfg.config_path`, plus four defs nothing called.

[Unreleased]: https://github.com/bangedorrunt/bird/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/bangedorrunt/bird/releases/tag/v0.3.0
