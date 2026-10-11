# A test suite that reads the environment must own it first

## What happened

Adding two credential aliases (`TWITTER_AUTH_TOKEN`, `TWITTER_CT0`) to the
environment table made `tests/e2e.sh` host-dependent without touching the test.
This machine's shell exports both, so the case asserting *"a read with no
credentials stops at the credential check"* would have found a live session in its
own environment and reached X -- passing or failing on someone else's account, and
sending a real cookie over the network to find out.

## Why it was invisible

The suite already cleared `TERM` (the tty proxy), so the idea of owning the
environment was present; it just was not generalised. The aliases were correct and
the failure was a property of the *test*: a suite that runs a program which reads
the environment inherits whatever the developer exported.

## The guard

`tests/e2e.sh` clears every name the program reads before the first case, in one
loop, and a case that needs a variable passes it with `--env "A=1 B=2"` (word-split
into the assignments `env` takes, so nothing leaks to the next case).

## The rule to carry

**When a program gains a new way to read the world -- an environment name, a file,
a config key -- the test suite must be made to own that input in the same change.**
Not as a follow-up: the suite's green is only worth something if it says the same
thing on every machine and in every shell.
