# A local file curl cannot read is not a network failure

## What happened

`bird tweet --text hi --media ./missing.png` came back as:

```json
{"ok":false,"error":{"id":"network","message":"curl failed","hint":"curl exit 26","retryable":true},"status":0}
```

`retryable: true` on a path that will never exist. The envelope's own contract
says what `retryable` means — "retrying the same call unchanged could work" — so
the answer told an agent to back off and try again, forever.

## Why

`Http.transport_error` had two branches: curl exit 0 (a response arrived) and
everything else (`network`). Exit 26 is *not* a transport failure; it is curl
saying it could not read a local file, which only happens for the one file this
program ever puts in curl's argv — the `-F media=@path` of an upload. The
generic branch was right for 6, 7, 28, 35, 52 and 56 and wrong for 26 and 37.

## The fix

`Http.transport_failed` names 26 and 37 explicitly and returns `usage` with
`retryable: false` (a hint that names `--media`). Everything else keeps the
`network` classification.

## What to remember

- **An error code is a claim about the future, not a label for the past.** The
  question to ask of every branch is not "what went wrong" but "is a retry of
  this same call able to succeed". A local precondition failure can never be.
- **`curl exit N` is the only diagnosis the transport has, so the honest fix
  lives there.** The file path is not in curl's message, so the hint names the
  flag instead of pretending to know the path.
- **No test caught it because no test could type a path that is not there and
  reach curl.** Only running the write path against a real socket (the
  `--media-upload-base` setting, `tests/live_server.py`) made the case
  reachable. A second reason to keep the stand-in seam.
