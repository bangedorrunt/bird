# An argv that prints is not an argv that runs

`--dry-run` prints a curl command a person can paste, so the request builder
returns the whole command line, program name included. `Process.run` takes the
program as its own first argument. Handing it the whole list worked in every
offline test and broke in the first live run.

## What happened

First live read against a real server: HTTP status `000`, the status glued to
the head of the body, and the wire log showed **two requests per call**. curl had
been given `curl` as its first URL: it tried to resolve a host named `curl`,
failed (`Could not resolve host: curl`), and because curl accepts several URLs it
then fetched the real URL as a second request. Between them, exit status and
stdout were garbage.

Every unit test was green. The tests asserted the argv the builder produced, and
the builder was right; the bug lived in the seam where that data was handed to
the runner.

## Fix

Split the two shapes in one place, and name them:

```bend
def Http.program() -> String:
  "curl"

def Http.args(req: D.HttpReq) -> List<&2, String>:   # what Process.run takes

def Http.argv(req: D.HttpReq) -> List<&2, String>:   # what --dry-run prints
  Http.program() <> Http.args(req)
```

The interpreter calls `Process.run(Http.program(), Http.args(req), …)`.

## The guard that would have caught it

An assertion about *what the server received*, not what the program says it
sent: exactly one request per verb, POST, with the variables as the body. The
e2e harness keeps that case (`tests/e2e.sh`, "the server received the variables,
one request each"), and a second case asserts the output never says
`Could not resolve host`.

## Rule

When one string is both a human-facing artifact and a machine-facing value, keep
one source and split it at the boundary — then test **the boundary**, live.
Offline tests of the builder cannot fail for a bug in the runner, which is
exactly where this one lived.
