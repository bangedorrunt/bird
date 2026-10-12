# An error code is not a retry contract

## What happened

`bird tweet` that timed out answered:

```json
{"ok":false,"error":{"id":"network","message":"curl timed out","hint":"curl exit 28","retryable":true},"status":0,"body":"","notes":["curl: (28) Operation timed out ..."]}
```

and three places documented that boolean as the whole contract (`agents.mdx`: "true
for exactly `rate_limited`, `network` and `upstream`, so a caller that wants to back
off and retry reads one boolean"; `README` and the ADR said the same). curl's 28
means the request was sent and the answer was lost, so X may have accepted the post.
An agent that obeyed the documented contract posted the tweet a second time.

The mechanism was one line: `View.envelope` computed `retryable` from the code alone
(`ErrCode.retryable(code)`), and every transport failure that is not a local file
problem is `ErrNetwork`. The code is right. The boolean was a second claim hiding
inside it.

## Why it was invisible

The code and the retry contract agreed on every error the suite could raise, because
every one of them was a *status*: 404, 429, 500, a missing attachment. Whether a
retry is safe depends on something no status carries: whether the effect already
happened. Nothing in the domain modelled that, so nothing could ask.

The near miss is worth naming. A neighbouring case had already been fixed this way --
curl 26/37 (a local file it could not read) were moved off `network` onto `usage`
because "a path that does not exist will not exist on the next attempt", which is
the same reasoning about a *repeat*. That fix worked because the answer was a
different code. Here no code fits: `usage`, `auth`, `not_found` and `internal` are
all wrong for "it was sent and we do not know".

## The guard

`Error` carries `unknown: Bool` -- whether the effect may already have happened --
set by `err_unknown` and raised only for a verb whose `Verb.writes` is true, so the
same curl status is retryable on a read and not on a post. `Error.retryable` is the
code's own answer vetoed by that field, and it is what the envelope reports. curl 26
and 37 keep their `usage` mapping; 28, 52 and 56 are the sent-but-unanswered three;
6, 7 and 35 mean nothing was sent, so they stay retryable for a post too.

## The rule to carry

**A retry contract is a separate fact from an error code, because whether repeating
a call is safe depends on whether the effect already happened -- which no status
carries.** A code answers "what went wrong". If the two are one value, the code
silently answers a question it cannot see, and the wrong answer is an invitation.

And its twin, about where to put the fix: **the veto belongs where the verb is
known.** The transport knows the curl status, the fold knows the verb, and the
envelope knows both. Putting the flag on the error and reading it at the envelope
keeps the ids frozen and every pattern honest, at the cost of one field and the
pattern sweep that a new field always costs.
