# A curl flag must precede its own value

**What happened.** The first live media upload died with curl exit 2 and
`curl: option -F: is badly used here`. `bird` reported it as a network error,
which is exactly right and completely unhelpful.

**The cause.** `Http.part_args` collects the multipart parts into an accumulator
and reverses it on the way out, because that is how every other list in
`src/http.bend` is built. The pair was written flag-first:

```
Http.part_args(rest, "-F" <> (h <> acc))     # acc = ["-F", part]
```

so after `List.reverse` the argv ended `… media=@shot.png -F` — a flag with no
argument after it. The parts *list* was correct, the *argv* was not.

**The fix.** Prepend value-then-flag, so the reversal puts them back in order:

```
Http.part_args(rest, h <> ("-F" <> acc))     # acc = [part, "-F"] → reversed: ["-F", part]
```

**The guard.** Two of them, because the offline suites could not see this:

- `tests/http_test.bend` compares the *whole* argv of a multipart request as one
  joined string. The old assertion only checked that the parts list contained the
  right string, which is true either way — the bug lived strictly between the
  parts list and the argv.
- `tests/e2e.sh` runs a real media write against `tests/live_server.py` and then
  reads the server's log: a multipart `POST /upload.json` carrying the file, the
  alt call naming the returned id, then the `CreateTweet` with that id in
  `media_entities`.

**The general rule.** Whenever a list is assembled through a reversed accumulator,
the *unit* being accumulated has to be reversed too. A test that asserts on the
data before rendering cannot see a rendering bug; for anything that becomes an
argv, assert the argv.
