When using Bend:

- run `bend guide` to learn it; the binary is `~/.bend/bin/bend` (not on PATH here)
- use `LAWS.bend` to keep important rules; a law that will not prove is a bug in the code, never edit a law down to what is provable
- run `bend PROOF.bend` before committing (`ALL PROOFS CHECK`); `--verdict` re-checks it with the Lean-proven kernel and works here now that Lean 4.34.0 (`elan`) is installed — it prints the same line only when every def outside Base is a valid proof with no `@unsafe` or foreign code
- parallelize the code whenever possible: the pure core has no limit, but the IO loop in `src/effects.bend` is one serial lane by language rule (a recursive call may not sit inside a closure)

## This repo

Read `docs/decisions/0001-design-bird.md` before changing anything that spans
files. It is the single record of why the design is shaped the way it is: pure
core + one interpreter, laws, requests as data, settings as items, errors as
data, the output contract, and the live-seam test.

Check `docs/learnings/` (`rg -il "<keywords>" docs/learnings/`) before planning
work on the transport, large inputs, the fold's failure path, or the e2e
harness; add a file there after verified work that cost a surprise.

The task-shaped guides are `docs/guides/*.mdx`. They are not compiled, so they
drift: `tests/e2e.sh` reads every `--flag` they name and fails if the parser does
not accept it, and the guides must keep that check green.

```sh
PATH="$HOME/.bend/bin:$PATH"
bend src/effects.bend --check-only        # the program and its imports type-check
bend PROOF.bend                           # laws gate the build
bend tests/argv_test.bend                 # offline suites: argv, api, http, json, update
bash tests/e2e.sh                         # the seam: real socket, stand-in server, exit codes
bend src/effects.bend -- check --json     # run it; everything after `--` is argv
bend src/effects.bend -o bird             # or compile the CLI (needs clang)
install -m 0755 bird ~/.local/bin/bird    # `bird` on PATH; the binary needs only curl
```

The offline suites stop at the pure core. Anything that crosses the fold →
interpreter seam (argv handed to curl, status split off the body, envelope and
exit codes) is only exercised by `tests/e2e.sh`; a change there is not verified
until the e2e transcript is green, and skips must be seen as skips, not passes.
