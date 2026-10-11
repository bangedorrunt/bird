#!/usr/bin/env bash
# End-to-end check of `bird` through the interface a caller actually uses: the
# command line. Nothing here imports a module. Each case runs the program the way
# a shell or an agent would and asserts what came out and what the exit code was,
# so the things a pure test cannot see -- that the entry point wires the fold to
# the interpreter at all, that `--dry-run` sends nothing, that the envelope and
# the exit code agree -- are covered here.
#
#   bash tests/e2e.sh
#   BIRD_E2E_OUT=/tmp/transcript.txt bash tests/e2e.sh
#
# Needs `bend` on PATH; the last block also needs `curl` and `python3`, and the
# pty case needs `script`. Nothing here needs a shell of its own: the program
# reads `TERM` rather than asking a child, so `curl` is the only process it
# starts. The artifact is the transcript: one block per case carrying the
# command, the exit code and the output, so a failure can be both read and rerun
# by hand. All fixtures are built in a temporary directory and thrown away.
set -u

cd "$(dirname "$0")/.."
BEND="${BEND:-bend}"
# The program reads `TERM` to decide between the envelope and prose, so the
# script owns that variable rather than inheriting whatever the caller had: every
# pipe case here is a pipe, and only the pty case asks for a terminal.
unset TERM
# The suite owns its environment. This machine's shell exports a real X session
# under the alias names (TWITTER_AUTH_TOKEN, TWITTER_CT0), and without this the
# "no credentials" case would find a live session, reach X, and pass or fail on
# someone else's account. Every name the program reads is cleared; a case that
# needs one passes it with `--env`.
for v in TWITTER_AUTH_TOKEN TWITTER_CT0 BIRD_JSON BIRD_AUTH_TOKEN BIRD_CT0 BIRD_ENGINE \
         BIRD_COUNT BIRD_TIMEOUT_MS BIRD_FIXTURE BIRD_TEXT_FILE \
         BIRD_SWEETISTICS_API_KEY BIRD_SWEETISTICS_BASE_URL BIRD_WEB_BEARER \
         BIRD_GQL_FEATURES BIRD_OP_CREATE_TWEET BIRD_OP_TWEET_DETAIL BIRD_OP_SEARCH \
         BIRD_OP_VIEWER BIRD_MEDIA_UPLOAD_BASE BIRD_GQL_BASE BIRD_MENTIONS_URL \
         BIRD_CONFIG; do
  unset "$v"
done
OUT="${BIRD_E2E_OUT:-tests/e2e_artifact.txt}"
WORK="$(mktemp -d)"
LIVE_PID=""
# Declared empty so `set -u` is satisfied when the socket block is skipped; the
# transcript normalizer reads it unconditionally at the end.
LIVE_PORT=""
cleanup() {
  [ -n "$LIVE_PID" ] && kill "$LIVE_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

pass=0
fail=0
skip=0
n=0

# ── fixtures ────────────────────────────────────────────────────────────────
printf '%s' '{"data":{"tweetResult":{"result":{"rest_id":"12345","legacy":{"full_text":"a fixture tweet","id_str":"12345"}}}}}' > "$WORK/tweet.json"
printf 'hello from a file' > "$WORK/text.txt"
printf '{"--count":7}' > "$WORK/count.json"
printf '{"--count":7,"--text":"from a config file"}' > "$WORK/content.json"
printf '{"--count":"abc"}' > "$WORK/badnumber.json"
printf '{"--nope":1}' > "$WORK/unknown.json"
printf 'not json at all' > "$WORK/broken.json"
printf 'PNGDATA' > "$WORK/shot.png"
: > "$WORK/second.png"
: > "$WORK/third.png"
: > "$WORK/fourth.png"
: > "$WORK/fifth.png"
: > "$WORK/clip.mp4"
printf 'plain text' > "$WORK/notes.txt"

CREDS="--auth-token T --ct0 C --web-bearer BEARER --gql-features {}"

# ── running and asserting ───────────────────────────────────────────────────
# `bird` is `bend src/effects.bend -- <args>`: the file is the program and
# everything after `--` is its argv, which is the only way to reach it before
# there is a built binary.
run() {
  "$BEND" src/effects.bend -- "$@" > "$WORK/out" 2> "$WORK/err"
  status=$?
}

run_cfg() {
  local cfg="$1"
  shift
  BIRD_CONFIG="$cfg" "$BEND" src/effects.bend -- "$@" > "$WORK/out" 2> "$WORK/err"
  status=$?
}

# For a case that needs variables in the *program's* environment: `--env "A=1 B=2"`
# is word-split into the assignments `env` takes, so nothing leaks to the next case.
run_env() {
  local envs="$1"
  shift
  env $envs "$BEND" src/effects.bend -- "$@" > "$WORK/out" 2> "$WORK/err"
  status=$?
}

# ── the cases ───────────────────────────────────────────────────────────────
# `case_ok` names a case, runs the program with the arguments after `--`, and
# asserts the exit code plus one substring of stdout. The command is echoed into
# the transcript before it runs, so a failure needs no reconstruction.

case_ok() {
  local name="$1" want="$2" expect="$3"
  shift 3
  local cfg="" envs=""
  if [ "$1" = "--env" ]; then
    envs="$2"
    shift 2
  fi
  if [ "$1" = "--config" ]; then
    cfg="$2"
    shift 2
  fi
  [ "$1" = "--" ] && shift
  n=$((n + 1))
  {
    printf '\n## %d. %s\n' "$n" "$name"
    if [ -n "$envs" ]; then
      printf '$ %s bird %s\n' "$envs" "$*"
    elif [ -n "$cfg" ]; then
      printf '$ BIRD_CONFIG=%s bird %s\n' "$cfg" "$*"
    else
      printf '$ bird %s\n' "$*"
    fi
  } >> "$OUT"
  if [ -n "$envs" ]; then
    run_env "$envs" "$@"
  elif [ -n "$cfg" ]; then
    run_cfg "$cfg" "$@"
  else
    run "$@"
  fi
  {
    printf 'exit %s\n' "$status"
    record_output
    [ -s "$WORK/err" ] && { printf 'stderr:\n'; cat "$WORK/err"; }
  } >> "$OUT"
  local why=""
  if [ "$status" != "$want" ]; then
    why="exit $status, wanted $want"
  elif [ -n "$expect" ] && ! grep -Fq "$expect" "$WORK/out"; then
    why="stdout does not contain: $expect"
  fi
  if [ -z "$why" ]; then
    pass=$((pass + 1))
    printf 'ok   %d. %s\n' "$n" "$name" | tee -a "$OUT"
  else
    fail=$((fail + 1))
    printf 'FAIL %d. %s -- %s\n' "$n" "$name" "$why" | tee -a "$OUT"
  fi
}

# The transcript is for reading, and one live case answers with 210 KB: the whole
# body would bury every other case in a file nobody scrolls through, so a case
# records the head of its output and the size of the rest. The assertions read the
# full output either way -- this only decides how much of it is written down.
record_output() {
  local size
  size=$(wc -c < "$WORK/out")
  if [ "$size" -gt 4000 ]; then
    head -c 4000 "$WORK/out" >> "$OUT"
    printf '\n... (%s bytes in total, truncated in this transcript)\n' "$size" >> "$OUT"
  else
    cat "$WORK/out" >> "$OUT"
  fi
}

# The other half of a case: something that must NOT be in the output. A note
# claiming a host named "curl" cannot be resolved is how a broken argv showed up
# in a live run, and no amount of output would have made a positive assertion
# notice it.
case_ok_not() {
  local name="$1" want="$2" reject="$3"
  shift 3
  local cfg=""
  if [ "$1" = "--config" ]; then
    cfg="$2"
    shift 2
  fi
  [ "$1" = "--" ] && shift
  n=$((n + 1))
  {
    printf '\n## %d. %s\n' "$n" "$name"
    if [ -n "$cfg" ]; then
      printf '$ BIRD_CONFIG=%s bird %s\n' "$cfg" "$*"
    else
      printf '$ bird %s\n' "$*"
    fi
  } >> "$OUT"
  if [ -n "$cfg" ]; then
    run_cfg "$cfg" "$@"
  else
    run "$@"
  fi
  {
    printf 'exit %s\n' "$status"
    record_output
    [ -s "$WORK/err" ] && { printf 'stderr:\n'; cat "$WORK/err"; }
  } >> "$OUT"
  local why=""
  if [ "$status" != "$want" ]; then
    why="exit $status, wanted $want"
  elif grep -Fq "$reject" "$WORK/out" || grep -Fq "$reject" "$WORK/err"; then
    why="output contains what it must not: $reject"
  fi
  if [ -z "$why" ]; then
    pass=$((pass + 1))
    printf 'ok   %d. %s\n' "$n" "$name" | tee -a "$OUT"
  else
    fail=$((fail + 1))
    printf 'FAIL %d. %s -- %s\n' "$n" "$name" "$why" | tee -a "$OUT"
  fi
}

# A case that cannot run on this machine is recorded as skipped rather than as a
# pass, so the verdict line never claims coverage it did not get.
case_skip() {
  n=$((n + 1))
  skip=$((skip + 1))
  {
    printf '\n## %d. %s\n' "$n" "$1"
    printf 'SKIP %s\n' "$2"
    printf 'skip %d. %s -- %s\n' "$n" "$1" "$2"
  } >> "$OUT"
  printf 'skip %d. %s -- %s\n' "$n" "$1" "$2"
}

{
  printf '# bird end-to-end transcript\n'
  printf '# %s\n' "$("$BEND" --version 2>&1 | head -1)"
  printf '# produced by: bash tests/e2e.sh\n'
} > "$OUT"

# ── the manual, before anything else ────────────────────────────────────────
case_ok "the manual comes out as one envelope on a pipe" 0 '"verb":"help"' -- --help
case_ok "no arguments is the manual too" 0 '"verb":"help"' -- 
case_ok "version names the build" 0 '"version":"0.3.0"' -- version --json
case_ok "schema lists the verbs it will accept" 0 '"name":"tweet"' -- schema --json
case_ok "schema agrees that reading does not write" 0 '"name":"read","writes":false' -- schema --json
# The manifest is what an agent reads before it types anything, so the defaults
# it can learn have to include where requests will actually go.
case_ok "schema names the default graphql host" 0 '"gql_base":"https://x.com/i/api/graphql"' -- schema --json
case_ok "schema names the default mentions url" 0 '"mentions_url":"https://x.com/i/api/2/notifications/mentions.json"' -- schema --json
case_ok "schema names the default media host" 0 '"media_upload_base":"https://upload.twitter.com/1.1/media"' -- schema --json
case_ok "schema names the default operation ids" 0 '"op_viewer":"Viewer"' -- schema --json

# ── refusals, which are the whole contract with an agent ────────────────────
case_ok "an unknown flag is refused by name" 2 'unknown flag --nope' -- search rust --nope --json
case_ok "a verb without its argument is refused by name" 2 'reply needs an argument' -- reply --json
case_ok "a tweet with nothing to send is refused" 2 'tweet has nothing to send' -- tweet --json
case_ok "a read with no credentials stops at the credential check" 3 '"id":"auth"' -- read 12345 --json
case_ok "a missing file is refused with the path and the reason" 2 'cannot read the file' -- read 12345 --fixture "$WORK/absent.json" --json
case_ok "a config file that is not json names itself" 2 'is not usable' --config "$WORK/broken.json" -- check --json

# ── a dry run describes the request and sends nothing ───────────────────────
case_ok "a dry run prints the curl argv it would use" 0 '"curl":["curl"' -- search rust $CREDS --dry-run --json
case_ok "a text full of shell metacharacters stays one argument" 0 'a; rm -rf /' -- tweet --text 'a; rm -rf /' $CREDS --dry-run --json
case_ok "a tweet id is read out of a url" 0 '99887766' -- read https://x.com/someone/status/99887766 $CREDS --dry-run --json
case_ok "a sub-second budget floors at one second, not zero" 0 '"timeout_ms":1000' -- check --timeout-ms 0 --json
case_ok "a budget past the ceiling is clamped to it" 0 '"timeout_ms":120000' -- check --timeout-ms 999999 --json
case_ok "a search count is clamped to fifty" 0 '\"count\":50' -- search rust --count 999999 $CREDS --dry-run --json

# ── a fixture answers through the same fold as a live response ──────────────
case_ok "a fixture is the body, not the path that named it" 0 'a fixture tweet' -- read 12345 --fixture "$WORK/tweet.json" --json
case_ok "a fixture answers with the status a real 200 would" 0 '"status":200' -- read 12345 --fixture "$WORK/tweet.json" --json
case_ok "a text file supplies the text when the command line does not" 0 'hello from a file' -- tweet --text-file "$WORK/text.txt" $CREDS --dry-run --json
case_ok "the command line beats the text file" 0 'explicit' -- tweet --text explicit --text-file "$WORK/text.txt" $CREDS --dry-run --json

# ── settings: flag, then environment, then config, then default ─────────────
case_ok "a config file sets a setting" 0 '\"count\":7' --config "$WORK/count.json" -- search rust $CREDS --dry-run --json
case_ok "a flag beats the config file" 0 '\"count\":2' --config "$WORK/count.json" -- search rust --count 2 $CREDS --dry-run --json
# A number that cannot be read is refused rather than quietly replaced by its
# default, and the refusal is checked on the winning value, so the flag and the
# config file are the same rule; the `BIRD_<FLAG>` in between takes it too.
case_ok "a count that is not a number is refused, not defaulted" 2 'is not a number: abc' -- search rust --count abc $CREDS --dry-run --json
case_ok "a timeout that is not a number is refused, not defaulted" 2 'is not a number: abc' -- check --timeout-ms abc --json
case_ok "a negative count is refused rather than clamped" 2 'is not a number: -1' -- search rust --count -1 $CREDS --dry-run --json
case_ok "a count of zero is a number, so it is the clamp's business" 0 '\"count\":1' -- search rust --count 0 $CREDS --dry-run --json

# ── media: refused by name, never silently dropped ──────────────────────────
case_ok "an alt with no media to describe is refused" 2 'more --alt than --media' -- tweet --text hi --alt "a description" $CREDS --dry-run --json
case_ok "an unsupported media type is refused by name" 2 'unsupported media type' -- tweet --text hi --media "$WORK/notes.txt" $CREDS --dry-run --json
case_ok "five images is one too many" 2 'at most four images' -- tweet --text hi --media "$WORK/shot.png" --media "$WORK/second.png" --media "$WORK/third.png" --media "$WORK/fourth.png" --media "$WORK/fifth.png" $CREDS --dry-run --json
case_ok "images and a video are refused together" 2 'never both' -- tweet --text hi --media "$WORK/shot.png" --media "$WORK/clip.mp4" $CREDS --dry-run --json

# A media write is a plan rather than a request, and the dry run says so:
# the uploads first, then a create whose ids come from their answers.
case_ok "a media write describes a media plan" 0 '"kind":"media-plan"' -- tweet --text hi --media "$WORK/shot.png" $CREDS --dry-run --json
case_ok "...with the upload step's endpoint" 0 '/upload.json' -- tweet --text hi --media "$WORK/shot.png" $CREDS --dry-run --json
case_ok "...and the ids marked as coming from the answers" 0 '<from-upload>' -- tweet --text hi --media "$WORK/shot.png" $CREDS --dry-run --json
case_ok "four images and four alts are one legal plan" 0 'media-plan' -- tweet --text hi --media "$WORK/shot.png" --media "$WORK/second.png" --media "$WORK/third.png" --media "$WORK/fourth.png" --alt a --alt b --alt c --alt d $CREDS --dry-run --json
# The fixture answers one request, and a media write is several, so it is
# refused by name rather than answered with a body that would have to be a lie.
case_ok "a fixture cannot answer a media write" 2 'media write is several' -- tweet --text hi --media "$WORK/shot.png" --fixture "$WORK/tweet.json" $CREDS --json
# The upload endpoint needs a session, so an api key stops before a byte moves.
case_ok "an api key cannot carry a media write" 3 'needs a session' -- tweet --text hi --media "$WORK/shot.png" --sweetistics-api-key k --json

# ── a target the program cannot read an id out of ──────────────────────────
# Nothing is sent: an empty `focalTweetId` would cost a round trip to learn what
# is knowable here.
case_ok "a target with no id in it is refused by name" 2 'not a tweet id' -- read abc $CREDS --json
case_ok "...and so is a url with no id in it" 2 'not a tweet id' -- reply https://x.com/someone --text hi $CREDS --json
case_ok "a share url still yields its id" 0 '99887766' -- read 'https://x.com/u/status/99887766?s=20&t=abc' $CREDS --dry-run --json

# mentions is a read of its own: a session, a count, and no body.
case_ok "mentions asks X with the count it was given" 0 'mentions.json?count=3' -- mentions --count 3 $CREDS --dry-run --json
case_ok "...as a GET" 0 '"GET"' -- mentions $CREDS --dry-run --json
case_ok "mentions without a session is refused" 3 '"id":"auth"' -- mentions --sweetistics-api-key k --json

# ── a config file holds settings, not the text of one post ──────────────────
case_ok "a config file refuses the text of a post" 2 'not a setting: --text' --config "$WORK/content.json" -- tweet $CREDS --dry-run --json
case_ok "a config file cannot smuggle in a number that is not one" 2 'is not a number: abc' --config "$WORK/badnumber.json" -- check --json
case_ok "a config file refuses a key the flag table does not know" 2 'not a setting: --nope' --config "$WORK/unknown.json" -- check --json

# ── the transport, over a real socket ───────────────────────────────────────
#
# Everything above stops at the argv. These cases put a server on a port and let
# the program make the request for real, which is the only place the seam between
# the fold and the interpreter is exercised. It is where a regression that handed
# curl an argv beginning with "curl" -- so that curl fetched a host named curl
# and then the real url as a second request -- passed every other case here and
# failed only against a live server.
# The stand-in asks for a free port of the operating system and writes the one
# it got, so a server left over from an earlier run cannot answer in its place.
if ! command -v curl >/dev/null || ! command -v python3 >/dev/null; then
  case_skip "the transport against a real server" "needs curl and python3"
else
  python3 tests/live_server.py 0 "$WORK/live.log" "$WORK/port" > "$WORK/server.log" 2>&1 &
  LIVE_PID=$!
  ready=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ -s "$WORK/port" ]; then
      ready=yes
      break
    fi
    sleep 0.3
  done
  LIVE_PORT="$(cat "$WORK/port" 2>/dev/null)"
  LIVE="--engine sweetistics --sweetistics-api-key LIVEKEY --sweetistics-base-url http://127.0.0.1:$LIVE_PORT"
  if [ -z "$ready" ]; then
    case_skip "the transport against a real server" "the stand-in server did not come up"
  else
    case_ok "a real 200 arrives with its status and its payload" 0 '"status":200' -- whoami $LIVE --op-viewer /viewer --json
    case_ok_not "the request is not sent twice, to a host named curl" 0 'Could not resolve host' -- whoami $LIVE --op-viewer /viewer --json
    case_ok "a real 404 is not_found, carrying its own status" 4 '"status":404' -- read 12345 $LIVE --op-tweet-detail /detail --json
    case_ok "a real 429 keeps the exact body, nothing glued to it" 5 '"body":"Rate limit exceeded"' -- search rust $LIVE --op-search /search --json
    case_ok "a real 500 is upstream" 7 '"id":"upstream"' -- tweet hi $LIVE --op-create-tweet /tweet --json
    case_ok "a failure with no request behind it reports no status" 2 '"status":0' -- tweet --json
    # 300 KB in, one envelope out. The status is split off the end of whatever curl
    # wrote, and the obvious way to do that costs a stack frame per character, which
    # is a crash rather than a wrong answer: this case is the size that caught it.
    case_ok "a body far bigger than a tweet still parses and prints" 0 '"status":200' -- read 12345 $LIVE --op-tweet-detail /big --json
    # What the server received, rather than what the program says it sent: one
    # `/detail` request means the request went out once and once only, and the body
    # is the variable object rather than a wrapper around it.
    n=$((n + 1))
    printf '\n## %d. the server received the variables, one request each\n' "$n" >> "$OUT"
    if python3 - "$WORK/live.log" > "$WORK/wire" 2>&1 <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
detail = [r for r in rows if r["path"] == "/detail"]
search = [r for r in rows if r["path"] == "/search"]
ok = (len(detail) == 1
      and detail[0]["method"] == "POST"
      and detail[0]["body"] == '{"focalTweetId":"12345"}'
      and len(search) == 1
      and '"count":10' in search[0]["body"])
print("requests:", [(r["method"], r["path"], r["body"]) for r in rows])
sys.exit(0 if ok else 1)
PY
    then
      pass=$((pass + 1))
      cat "$WORK/wire" >> "$OUT"
      printf 'ok   %d. the server received the variables, one request each\n' "$n" | tee -a "$OUT"
    else
      fail=$((fail + 1))
      cat "$WORK/wire" >> "$OUT"
      printf 'FAIL %d. the server received the variables, one request each\n' "$n" | tee -a "$OUT"
    fi

    # Retryability is part of the envelope, so an agent branches on one boolean
    # instead of keeping its own copy of the status-to-retry table. These run
    # after the log check above, which asserts one request per verb.
    case_ok "a 404 is not retryable" 4 '"retryable":false' -- read 12345 $LIVE --op-tweet-detail /detail --json
    case_ok "a 429 is retryable, and the envelope says so" 5 '"retryable":true' -- search rust $LIVE --op-search /search --json

    # ── the write path and the mentions read, against the stand-in ──────────
    #
    # Every host the run uses is a setting, so the whole media write -- the
    # multipart upload, the alt call that needs the id, and the post that
    # carries it -- can run against a real socket. This is the only place the
    # upload seam is exercised: curl's multipart form, the id coming back, and
    # the fold spending it on the next request.
    LIVE_POST="$CREDS --gql-base http://127.0.0.1:$LIVE_PORT/graphql --mentions-url http://127.0.0.1:$LIVE_PORT/mentions.json --media-upload-base http://127.0.0.1:$LIVE_PORT/media"
    case_ok "a media write uploads, sets the alt, then posts" 0 'media live' -- tweet --text "media live" --media "$WORK/shot.png" --alt "a description" $LIVE_POST --op-create-tweet create-tweet --json
    case_ok "mentions reads the timeline its setting names" 0 'bird hello' -- mentions $LIVE_POST --json
    n=$((n + 1))
    printf '\n## %d. the server received the upload, the alt and the post, in that order\n' "$n" >> "$OUT"
    if python3 - "$WORK/live.log" > "$WORK/wiremedia" 2>&1 <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
media = [r for r in rows if r["path"].startswith("/media/")]
create = [r for r in rows if r["path"] == "/graphql/create-tweet/CreateTweet"]
mentions = [r for r in rows if r["path"].startswith("/mentions.json")]
order = [r["path"] for r in rows
         if r["path"].startswith("/media/") or r["path"] == "/graphql/create-tweet/CreateTweet"]
ok = (len(media) == 2 and len(create) == 1 and len(mentions) == 1
      and order == ["/media/upload.json", "/media/metadata/create.json",
                    "/graphql/create-tweet/CreateTweet"]
      and media[0]["method"] == "POST"
      and (media[0]["content_type"] or "").startswith("multipart/form-data")
      and 'name="media"' in media[0]["body"]
      and 'filename="shot.png"' in media[0]["body"]
      and "PNGDATA" in media[0]["body"]
      # An image declares no category; only a video asks for one.
      and "media_category" not in media[0]["body"]
      and '"media_id":"111"' in media[1]["body"]
      and "a description" in media[1]["body"]
      and '"media_id":"111"' in create[0]["body"]
      and "media live" in create[0]["body"]
      and create[0]["authorization"] == "Bearer BEARER"
      and mentions[0]["method"] == "GET"
      and mentions[0]["path"] == "/mentions.json?count=10"
      and mentions[0]["body_len"] == 0)
print("media:", [(r["method"], r["path"], (r["content_type"] or "")[:20], r["body_len"]) for r in media])
print("create:", [(r["method"], r["path"], r["body_len"]) for r in create])
print("mentions:", [(r["method"], r["path"], r["body_len"]) for r in mentions])
sys.exit(0 if ok else 1)
PY
    then
      pass=$((pass + 1))
      cat "$WORK/wiremedia" >> "$OUT"
      printf 'ok   %d. the server received the upload, the alt and the post, in that order\n' "$n" | tee -a "$OUT"
    else
      fail=$((fail + 1))
      cat "$WORK/wiremedia" >> "$OUT"
      printf 'FAIL %d. the server received the upload, the alt and the post, in that order\n' "$n" | tee -a "$OUT"
    fi

    # An attachment that is not there is the caller's mistake, and curl reports it
    # as a local read failure (exit 26). It was classified as a network error, which
    # set `retryable` and invited a retry that can never work. These two cases run
    # after the count check above, because a failed upload sends nothing.
    case_ok "an attachment that is not there is a usage error" 2 '"id":"usage"' -- tweet --text hi --media "$WORK/missing.png" $LIVE_POST --json
    case_ok "...and it is not retryable" 2 '"retryable":false' -- tweet --text hi --media "$WORK/missing.png" $LIVE_POST --json

    # The credential aliases. A shell that already talks to X exports
    # TWITTER_AUTH_TOKEN and TWITTER_CT0, so those names are read when the BIRD_
    # spelling is not set, and the BIRD_ spelling wins when both are. The envelope
    # cannot show which one was used -- both report "environment" -- so the proof
    # is the cookie the stand-in received.
    LIVE_NOFLAGS="--web-bearer BEARER --gql-features {} --gql-base http://127.0.0.1:$LIVE_PORT/graphql --mentions-url http://127.0.0.1:$LIVE_PORT/mentions.json --media-upload-base http://127.0.0.1:$LIVE_PORT/media"
    case_ok "the cookie names a shell already exports are read" 0 'bird hello' --env "TWITTER_AUTH_TOKEN=ALIAS-AT TWITTER_CT0=ALIAS-CT0" -- mentions $LIVE_NOFLAGS --json
    case_ok "...and BIRD_ wins when both spellings are set" 0 'bird hello' --env "TWITTER_AUTH_TOKEN=ALIAS-AT TWITTER_CT0=ALIAS-CT0 BIRD_AUTH_TOKEN=BIRD-AT BIRD_CT0=BIRD-CT0" -- mentions $LIVE_NOFLAGS --json
    n=$((n + 1))
    printf '\n## %d. the server received the credential each case asked for\n' "$n" >> "$OUT"
    if python3 - "$WORK/live.log" > "$WORK/wirealias" 2>&1 <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
mentions = [r for r in rows if r["path"].startswith("/mentions.json")]
# The last two mentions reads are the alias cases, in the order they ran.
alias, both = mentions[-2], mentions[-1]
ok = (alias["cookie"] == "auth_token=ALIAS-AT; ct0=ALIAS-CT0"
      and alias["csrf"] == "ALIAS-CT0"
      and both["cookie"] == "auth_token=BIRD-AT; ct0=BIRD-CT0"
      and both["csrf"] == "BIRD-CT0")
print("alias only:", alias["cookie"], "|", alias["csrf"])
print("both set:  ", both["cookie"], "|", both["csrf"])
sys.exit(0 if ok else 1)
PY
    then
      pass=$((pass + 1))
      cat "$WORK/wirealias" >> "$OUT"
      printf 'ok   %d. the server received the credential each case asked for\n' "$n" | tee -a "$OUT"
    else
      fail=$((fail + 1))
      cat "$WORK/wirealias" >> "$OUT"
      printf 'FAIL %d. the server received the credential each case asked for\n' "$n" | tee -a "$OUT"
    fi
  fi
fi

# ── a terminal gets prose, and the failure names the verb ───────────────────
# `test -t 1` is what the program asks, so this needs a real pty: a pipe always
# gets the envelope, which is the point of the default and is asserted above.
if script -q /dev/null true >/dev/null 2>&1; then
  n=$((n + 1))
  {
    printf '\n## %d. %s\n' "$n" "on a terminal a read is indented data, not an envelope"
    printf '$ TERM=xterm bird read 12345 --fixture <fixture>\n'
  } >> "$OUT"
  # Without TERM the pty changes nothing -- which is the limitation the program's
  # own comment names -- so the case sets it, the way a shell would.
  TERM=xterm script -q /dev/null "$BEND" src/effects.bend -- read 12345 --fixture "$WORK/tweet.json" > "$WORK/out" 2>&1
  status=$?
  { printf 'exit %s\n' "$status"; cat "$WORK/out"; } >> "$OUT"
  if [ "$status" = "0" ] && grep -Fq 'a fixture tweet' "$WORK/out" && ! grep -Fq '"ok":true' "$WORK/out"; then
    pass=$((pass + 1))
    printf 'ok   %d. on a terminal a read is indented data, not an envelope\n' "$n" | tee -a "$OUT"
  else
    fail=$((fail + 1))
    printf 'FAIL %d. on a terminal a read is indented data, not an envelope\n' "$n" | tee -a "$OUT"
  fi
else
  case_skip "on a terminal a read is indented data, not an envelope" "no pty helper (script) available"
fi

# ── the guides name only flags this build has ───────────────────────────────
#
# A guide is not compiled, so a flag that stops existing is a document that
# quietly lies. The schema is the list the parser accepts, so it decides. The
# extra names are the ones that legitimately appear without being settings:
# the three dashed verbs, and `curl`'s own flags as they show up in the argv
# examples a dry run prints.
if command -v python3 >/dev/null && [ -d docs/guides ]; then
  n=$((n + 1))
  printf '\n## %d. every flag the guides name is one the parser accepts\n' "$n" >> "$OUT"
  if python3 - "$BEND" > "$WORK/docscheck" 2>&1 <<'PY'
import json, pathlib, re, subprocess, sys
schema = json.loads(subprocess.run([sys.argv[1], "src/effects.bend", "--", "schema", "--json"],
                                   capture_output=True, text=True).stdout)
known = {f["name"] for f in schema["data"]["flags"]}
known |= {"--help", "--version", "--schema", "--max-time", "--write-out"}
seen = {}
for page in sorted(pathlib.Path("docs/guides").glob("*.mdx")):
    for flag in re.findall(r"--[a-z][a-z0-9-]*", page.read_text()):
        seen.setdefault(flag, []).append(page.name)
unknown = {f: sorted(set(p)) for f, p in seen.items() if f not in known}
print("flags named in the guides:", len(seen))
for flag, pages in sorted(unknown.items()):
    print("UNKNOWN", flag, "in", ",".join(pages))
sys.exit(1 if unknown else 0)
PY
  then
    pass=$((pass + 1))
    cat "$WORK/docscheck" >> "$OUT"
    printf 'ok   %d. every flag the guides name is one the parser accepts\n' "$n" | tee -a "$OUT"
  else
    fail=$((fail + 1))
    cat "$WORK/docscheck" >> "$OUT"
    printf 'FAIL %d. every flag the guides name is one the parser accepts\n' "$n" | tee -a "$OUT"
  fi
else
  case_skip "every flag the guides name is one the parser accepts" "needs python3 and docs/guides"
fi

# The transcript is committed, so it must not carry the run's own throwaway
# names. The temp directory and the stand-in's port are different every run, and
# left in they make the artifact differ from the committed one for a reason a
# reader can do nothing about -- the diff is noise around the assertions. Both
# are folded to a fixed placeholder here, after every case has been written.
sed -e "s|$WORK|<work>|g" "$OUT" > "$WORK/normalized"
if [ -n "$LIVE_PORT" ]; then
  sed -e "s|127\.0\.0\.1:$LIVE_PORT|127.0.0.1:<port>|g" "$WORK/normalized" > "$WORK/normalized.2"
else
  cp "$WORK/normalized" "$WORK/normalized.2"
fi
mv "$WORK/normalized.2" "$OUT"

{
  printf '\n# %d cases: %d ok, %d failed, %d skipped\n' "$n" "$pass" "$fail" "$skip"
} >> "$OUT"

printf '\n%d cases: %d ok, %d failed, %d skipped\n' "$n" "$pass" "$fail" "$skip"
printf 'transcript: %s\n' "$OUT"
[ "$fail" = "0" ]
