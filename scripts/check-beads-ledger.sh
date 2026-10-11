#!/usr/bin/env bash
# Fail closed on a beads-ledger row-set regression.
#
# Why this exists: `.beads/issues.jsonl` is a FULL-SNAPSHOT export. Any worktree
# that writes `.beads/` from its own (older) sqlite rewrites the whole file and
# silently drops the beads other lanes closed in parallel, after which a closed
# bead reads `in_progress` again and nothing looks wrong. The same file is what
# `br sync --flush-only` regenerates, so the loss becomes durable the moment it
# is committed.
#
# A gate row is a verdict, and verdicts are not replaceable: `.beads/gates.jsonl`
# losing a row is what turned this tracker's closes unprovable once. That is the
# fourth pass below, and it is why a dropped row is a failure and not a diff.
#
# Usage:
#   scripts/check-beads-ledger.sh [--base <rev> | --base-ledger <path>]
#                                 [--ledger <path>] [--gates <path>]
#                                 [--base-gates <path>] [--history]
#                                 [--force <reason>] [--self-test]
#
# `--ledger`/`--gates` are the files now; `--base-*` name the reference. Pointing
# `--ledger` at a scratch copy is the normal way to test a fix, and it must not
# change where the reference is read from.
#
# Exit: 0 clean, 1 regression, 2 usage / environment error.
#
# `--base` defaults to HEAD, so a local run compares the committed ledger against
# the worktree's — which is the check to run before `git add .beads/`. In CI,
# point it at the merge base (`--base origin/main`) so a branch that publishes a
# snapshot from a stale sqlite is caught even though its own worktree matches its
# own HEAD.
#
# `--force <reason>` publishes a regression on purpose (a deliberate `br reopen`,
# or a bead genuinely deleted). It is never the default: the whole point is that
# the loss is loud.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

LEDGER=".beads/issues.jsonl"
GATES=".beads/gates.jsonl"
# Where the reference lives at `--base`. Separate from LEDGER/GATES above, which
# say where the files are now.
BASE_LEDGER_PATH=".beads/issues.jsonl"
BASE_GATES_PATH=".beads/gates.jsonl"

# ── self-test ───────────────────────────────────────────────────────────
# Hermetic: builds its own ledgers under a temp directory, so it needs no git
# state and no real ledger. A gate that is never seen failing is decoration.
if [ "${1:-}" = "--self-test" ]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  rc=0

  base="$work/base.jsonl"
  printf '%s\n' \
    '{"id":"bendx-a","status":"closed"}' \
    '{"id":"bendx-b","status":"open"}' > "$base"
  gbase="$work/gates-base.jsonl"
  printf '%s\n' '{"id":1,"issue_id":"bendx-a","gate":"live-verified"}' > "$gbase"

  case_check() { # name, expected exit, got
    if [ "$2" = "$3" ]; then
      printf 'ok   %s (exit %s)\n' "$1" "$3"
    else
      printf 'FAIL %s: expected exit %s, got %s\n' "$1" "$2" "$3" >&2
      rc=1
    fi
  }

  run_case() { # ledger, gates -> exit code
    set +e
    "$0" --base-ledger "$base" --base-gates "$gbase" --ledger "$1" --gates "$2" > "$work/out" 2>&1
    got=$?
    set -e
    printf '%s' "$got"
  }

  cp "$base" "$work/same.jsonl"
  case_check "an unchanged ledger is clean" 0 "$(run_case "$work/same.jsonl" "$gbase")"

  printf '%s\n' '{"id":"bendx-b","status":"open"}' > "$work/dropped.jsonl"
  case_check "a dropped row is a regression" 1 "$(run_case "$work/dropped.jsonl" "$gbase")"

  printf '%s\n' \
    '{"id":"bendx-a","status":"in_progress"}' \
    '{"id":"bendx-b","status":"open"}' > "$work/reopened.jsonl"
  case_check "a closed row reading anything else is a regression" 1 "$(run_case "$work/reopened.jsonl" "$gbase")"

  printf '%s\n' '{"id":1,"issue_id":"bendx-a","gate":"live-verified"}' '{"id":2}' > "$work/gnow.jsonl"
  case_check "a new gate row is clean" 0 "$(run_case "$work/same.jsonl" "$work/gnow.jsonl")"
  printf '%s\n' '{"id":2}' > "$work/gdropped.jsonl"
  case_check "a dropped gate row is a regression" 1 "$(run_case "$work/same.jsonl" "$work/gdropped.jsonl")"

  set +e
  "$0" --base-ledger "$base" --base-gates "$gbase" --ledger "$work/dropped.jsonl" --gates "$gbase" --force "deliberate reopen" > "$work/out" 2>&1
  got=$?
  set -e
  case_check "--force publishes it loud" 0 "$got"
  grep -q 'FORCED' "$work/out" || { printf 'FAIL --force did not say so\n' >&2; rc=1; }

  set +e
  "$0" --base-ledger "$base" --base-gates "$gbase" --ledger "$work/missing.jsonl" --gates "$gbase" > "$work/out" 2>&1
  got=$?
  set -e
  case_check "a missing ledger is a usage error" 2 "$got"

  set +e
  "$0" --nonsense > "$work/out" 2>&1
  got=$?
  set -e
  case_check "an unknown flag is a usage error" 2 "$got"

  [ "$rc" -eq 0 ] && echo "self-test: all cases passed"
  exit "$rc"
fi

BASE="HEAD"
BASE_LEDGER=""
BASE_GATES_REF=""
HISTORY=0
FORCE_REASON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base)        BASE="${2:-}"; shift 2 ;;
    --base-ledger) BASE_LEDGER="${2:-}"; shift 2 ;;
    --base-gates)  BASE_GATES_REF="${2:-}"; shift 2 ;;
    --ledger)      LEDGER="${2:-}"; shift 2 ;;
    --gates)       GATES="${2:-}"; shift 2 ;;
    --history)     HISTORY=1; shift ;;
    --force)       FORCE_REASON="${2:-}"; shift 2 ;;
    -h|--help)     sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$BASE" ] || { echo "--base needs a revision" >&2; exit 2; }
cd "$ROOT"

[ -f "$LEDGER" ] || { echo "missing ledger: $LEDGER" >&2; exit 2; }

BASE_FILE="$(mktemp)"
BASE_GATES="$(mktemp)"
trap 'rm -f "$BASE_FILE" "$BASE_GATES"' EXIT

# `--ledger` and `--gates` say where the files are NOW; the base is read from
# `--base-ledger`/`--base-gates`, or from the same two paths at `--base`. The two
# are separate on purpose: a caller that points `--gates` at a scratch file is
# asking about that file, not about where the reference lives, and reading the
# reference from the scratch path silently compares nothing at all.
#
# `--base-ledger` exists for two callers: the self-test above, and a CI job that
# already has the reference file in hand. A base with no `gates.jsonl` is not an
# error -- an older base simply has nothing to compare -- so its absence leaves
# the temp file empty and the fourth pass below finds no rows to check.
if [ -n "$BASE_LEDGER" ]; then
  cp "$BASE_LEDGER" "$BASE_FILE" 2>/dev/null || { echo "cannot read --base-ledger $BASE_LEDGER" >&2; exit 2; }
else
  git show "$BASE:$BASE_LEDGER_PATH" > "$BASE_FILE" 2>/dev/null \
    || { echo "cannot read $BASE_LEDGER_PATH at $BASE (not a commit, or the file is new)" >&2; exit 2; }
fi

if [ -n "$BASE_GATES_REF" ]; then
  cp "$BASE_GATES_REF" "$BASE_GATES" 2>/dev/null || true
elif [ -z "$BASE_LEDGER" ]; then
  git show "$BASE:$BASE_GATES_PATH" > "$BASE_GATES" 2>/dev/null || true
elif [ -f "$(dirname "$BASE_LEDGER")/$(basename "$BASE_GATES_PATH")" ]; then
  # The two files travel together, so a reference ledger with a sibling gates
  # file uses it unless `--base-gates` said otherwise.
  cp "$(dirname "$BASE_LEDGER")/$(basename "$BASE_GATES_PATH")" "$BASE_GATES" 2>/dev/null || true
fi

HISTORY_IDS=""
if [ "$HISTORY" -eq 1 ]; then
  # A shallow clone sees one commit, so the scan would quietly check nothing and
  # report OK. That silent degradation is the failure this gate exists to stop.
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
    echo "--history needs full history, but this is a shallow clone" >&2
    echo "(re-run with \`git fetch --unshallow\`, or drop --history)" >&2
    exit 2
  fi
  # The ids a commit SUBJECT claims to close. Subjects are prose ("close bendx-a,
  # bendx-b; file bendx-c"), so the close clause ends at the first `;` or at a
  # "file"/"and"/"then" keyword -- anything past that names beads in some other
  # role. A commit that merely cites a bead in parentheses is implementing it,
  # not closing it, so only the close clause is read. An id with no row is a
  # bead from another tracker: absence, not a regression.
  HISTORY_IDS="$(git log --format=%s "$BASE" \
    | grep -oE 'close[[:space:]]+[^;]*' \
    | sed -E 's/([[:space:]]|^)(file|and|then|plus)([[:space:]]|$).*/ /' \
    | grep -oE 'bendx-[A-Za-z0-9._-]+' || true)"
fi

RC=0
BASE_FILE="$BASE_FILE" BASE_GATES="$BASE_GATES" LEDGER="$LEDGER" GATES="$GATES" HISTORY_IDS="$HISTORY_IDS" \
python3 - <<'PY' || RC=$?
import json, os, sys

def rows(path):
    out = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            out[rec["id"]] = rec.get("status")
    return out

def ids(path):
    got = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                got.append(json.loads(line)["id"])
    return got

base = rows(os.environ["BASE_FILE"])
now = rows(os.environ["LEDGER"])

regressions = []
for bead, status in base.items():
    if bead not in now:
        regressions.append((bead, "row dropped (was %s)" % status))
    elif status == "closed" and now[bead] != "closed":
        regressions.append((bead, "closed -> %s" % now[bead]))

# Identity only, never content: a gate verdict is appended, so a row that
# disappears was lost, and a row that changed was rewritten.
base_gates = ids(os.environ["BASE_GATES"])
now_gates = set(ids(os.environ["GATES"]))
for row in base_gates:
    if row not in now_gates:
        regressions.append(("gate-row-%s" % row, "gate verdict dropped"))

for bead in os.environ.get("HISTORY_IDS", "").split():
    if bead in now and now[bead] != "closed":
        regressions.append((bead, "a commit claims to close it, ledger reads %r" % now[bead]))

for bead, what in regressions:
    print("REGRESSION %s: %s" % (bead, what))
sys.exit(1 if regressions else 0)
PY

if [ "$RC" -eq 0 ]; then
  echo "OK: beads ledger has no row-set regression vs $BASE"
  exit 0
fi

if [ -n "$FORCE_REASON" ]; then
  echo "FORCED past $RC regression(s) vs $BASE — reason: $FORCE_REASON"
  exit 0
fi

REF="$BASE"
[ -n "$BASE_LEDGER" ] && REF="$BASE_LEDGER"
cat >&2 <<EOF
FAIL: the ledger at $LEDGER dropped or reopened rows that $REF has closed.
      (this is the full-snapshot export clobbering a parallel lane's closes)
      Fix: re-apply the closes (br close <id> --commit-sha <sha>), re-export with
      \`br sync --flush-only\`, then re-run. A lost gate row is repaired by
      reopening and re-closing its bead. To publish anyway:
        $0 --base $BASE --force "<why>"
EOF
exit 1
