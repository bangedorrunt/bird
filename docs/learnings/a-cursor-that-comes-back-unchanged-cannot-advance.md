# A cursor that comes back unchanged cannot advance, and a stand-in that counts cannot say so

## What happened

Teaching `bookmarks` to follow X's cursor left two holes that the suite could not
see.

The first was in the walk (`src/update.bend`). `page_more` stopped on three facts:
the ask was met, X offered no token, or the page carried nothing. A page that hands
back *the token it was fetched with* passes all three, so the walk re-read that same
page and added the same tweets again, once per page, until `--count` was met -- an
answer with the same tweets in it many times over. Under `--count 500` that is up to
500 identical requests.

The second was in the stand-in (`tests/live_server.py`). The paged route answered
from a process-wide counter keyed by route: the first request got page one, the
second got page two, whatever they carried. So the fixture would have served page
two just as happily to a run that had dropped the cursor -- the one bug that route
exists to catch -- and a second case on the route would have started at page two
because the first case had run.

## Why it was invisible

Both holes were invisible for the same reason: the fixture was the only thing
producing the second page, and the fixture was answering a question about *itself*
(how many times have I been asked) rather than about the request. Every unit case
was green, because the unit cases feed the walk bodies the fixture's shape can make
-- two pages, and a last page with no cursor. The stop conditions the fixture could
not produce were the ones not covered, and the client's cursor was asserted in
`tests/e2e.sh` on the wire, which is the only place that sees it.

## The guard

`page_more` now takes the token the page was fetched with, and a page that hands it
back ends the walk the way a missing token does. The stand-in answers as a function
of the request's own `cursor`: no cursor is page one, `LIVECURSOR1` is page two, and
a token it never handed out is an empty timeline. Unit cases pin all four stop
conditions under a `--count` no page can meet, so the ask is never what ends them.

## The rule to carry

**A stand-in that counts requests cannot test a client that has to send state.** It
answers the second request no matter what the second request carried, so a dropped
cursor looks exactly like a sent one. Decide the answer from the request -- then the
fixture is order-independent, a second case can read the same route from the start,
and the state the client was supposed to send is what picks the answer.

**And a walk whose only bound is the ask has to treat a token that did not move as
the end.** "It did not advance" is a fact about the page just read, and it belongs
with the other three ways out, not left to a count that will eventually run out.
