# `String.take` is not tail-recursive, and a 138 KB tweet proved it

Splitting curl's HTTP status off the end of the response is three characters of
arithmetic. The obvious implementation of it took the program down on the first
real read.

## What happened

`bird read <id>` against X's real API: `memory fault (machine stack overflow?)`.
The same response body parsed fine through a fixture, so the crash was in the
transport, not the JSON decoder.

## Cause

The split was written as `String.take(raw, length - 3)` for the body.
`String.take` builds its result on the way back up the recursion, so it costs one
stack frame per character taken — about 138 000 frames for one tweet.
`String.length` has the same shape and is the same trap. The body size is X's to
choose, so no limit fixes this; the primitive does.

## Fix

Walk with the accumulator-based primitives only: `String.drop` and
`String.reverse` recurse with an accumulator, so they pay in heap instead of
stack. The split is done on the reversed string with a fixed-width drop, and the
length check is a hand-rolled tail-recursive walk (`Http.width_of`) rather than
`String.length`.

```bend
def Http.from_reversed(+rev: String) -> Resp:
  Resp{
    Http.status_of(String.reverse(String.take(rev, Http.status_width()))),  # take 3: bounded
    String.reverse(String.drop(rev, Http.status_width()))
  }
```

`String.take` with a *small constant* count is fine: the cost is the count, not
the string.

## The guard

The e2e stand-in server answers one route with ~300 KB, and a case asserts it
arrives intact. A crash cannot come back silently.

## Rule

"Tail recursion" is a property of each stdlib function, not of the language. In
Bend 2, trust `drop` and `reverse`; treat `take` and `length` as bounded-count
tools only; audit any primitive called on a string whose size a caller controls.
