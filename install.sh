#!/usr/bin/env bash
# Build the CLI and put it on PATH.
#
#   ./install.sh                        # into ~/.local/bin
#   PREFIX=/usr/local/bin ./install.sh  # somewhere else
#   BEND=/path/to/bend ./install.sh     # a compiler that is not on PATH
#
# This automates the three lines in the README's "Run it": the program is one file,
# so `bend src/effects.bend -o bird` turns it into a binary that needs nothing but
# `curl` at runtime, and then it is installed. The build happens in a temporary
# directory and the result is moved into place, so a failed build leaves the copy
# already on PATH alone and nothing is left behind in the repo.
#
# Needs `bend` -- on PATH, or at ~/.bend/bin/bend, which is where it installs and
# which a shell that sources ~/.zprofile has -- and clang for the compile itself.
set -eu

repo="$(cd "$(dirname "$0")" && pwd)"
prefix="${PREFIX:-$HOME/.local/bin}"
prefix="${prefix%/}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  printf 'usage: %s [--help]\n\n  PREFIX=DIR   where to install   (default ~/.local/bin)\n  BEND=PATH    the bend compiler  (default: on PATH, then ~/.bend/bin/bend)\n' "$0"
  exit 0
fi

find_bend() {
  if [ -n "${BEND:-}" ]; then
    printf '%s' "$BEND"
  elif command -v bend >/dev/null 2>&1; then
    command -v bend
  elif [ -x "$HOME/.bend/bin/bend" ]; then
    printf '%s' "$HOME/.bend/bin/bend"
  else
    return 1
  fi
}

if ! bend_bin="$(find_bend)"; then
  printf 'install.sh: no bend compiler found: add it to PATH, or pass BEND=/path/to/bend\n' >&2
  printf 'install.sh: it installs to ~/.bend/bin/bend, which a shell that sources ~/.zprofile has\n' >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'building with %s\n' "$bend_bin"
"$bend_bin" "$repo/src/effects.bend" -o "$work/bird"

mkdir -p "$prefix"
install -m 0755 "$work/bird" "$prefix/bird"

printf 'installed %s\n' "$prefix/bird"
"$prefix/bird" version --json

case ":$PATH:" in
  *":$prefix:"*) ;;
  *) printf 'note: %s is not on PATH; add it to your shell profile\n' "$prefix" ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  printf 'warning: curl is not on PATH, and it is the one thing bird needs at runtime\n' >&2
fi
