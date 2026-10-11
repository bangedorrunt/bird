# A failure that builds a fresh model loses the status

A 404, a 429 and a 500 all reported `"status":0` in the failure envelope. The
status was known, correct, and thrown away by the transition that reported it.

## What happened

The failure path constructed a new model from the error alone. Every offline
test passed, because offline tests checked the error code, the message, and the
exit code — none of them checked that the *answer's own status* survived into
the envelope. The live run against X showed `"status":0` beside real 404s.

## Cause

In a fold, a transition that builds a fresh state instead of carrying the
current one is a data-loss bug the type-checker happily accepts. The status and
body were known when the message arrived; the failure constructor dropped them.

## Fix

```bend
# A failure keeps the body: X's own words are often the useful part of a 4xx.
def Model.failed_with(m: Model, +e: Error, body: String) -> Model: …
```

A local failure — refused before any request existed — still reports status 0,
which is the honest answer for "there was no request". Only the path that had an
answer keeps its status.

## The guard

An e2e case asserts a real 404 does not report `"status":0`; the 429 case
asserts the exact body survives; a local refusal case asserts `"status":0` is
still 0 when no request was made.

## Rule

In a fold, every transition carries the state it arrived on. When a failure
branch builds a new model from scratch, ask what the old model knew — status,
body, notes, ids — and whether the caller needs it. Then assert the status
through the *rendered* output, not just through the fold.
