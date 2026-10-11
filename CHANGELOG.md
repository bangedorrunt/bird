# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This is the first public release. Earlier iterations were not published, so the
log starts at `0.3.0`.

## [Unreleased]

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
