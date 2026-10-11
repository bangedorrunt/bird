# A stand-in that answers the wrong shape still passes

## What happened

Folding reads into tweets (`src/tweets.bend`) turned four e2e cases red at once,
and every one of them was a mentions case. The stand-in's mentions route answered

```json
{"globalObjects":{"tweets":{"11":{"full_text":"@bird hello"}}}}
```

and the reader found no tweet in it: the entry carried no `id_str`, and the shape
test asked for one. So `mentions` answered `{"tweets":[]}` -- an empty timeline,
exit code `0`, which is the worst shape a wrong answer can have.

The fixture was written when a read's payload was the raw body. Any interior at all
passed then, because the case asserted only a substring that the body happened to
contain. It had never been checked against X. The `whoami` route had the same
problem in the other direction: its viewer kept `screen_name` under `legacy`, where
nothing reads it, so the live case asserted `"status":200` while an empty handle
went by unnoticed.

## Why it was invisible

A stand-in is written to satisfy the case, not to mirror the server. While the
program passes a body through, those are the same thing. The moment it *reads* the
body, a fixture with the wrong interior is a test of nothing -- and it stays green,
because the assertion was on a status or a substring that the wrong shape also has.

## The guard

The stand-in now carries the fields the fold reads, and the cases assert what the
fold produced. The mentions route answers a v1.1 entry in its real shape (checked
against `mentions --raw` from a live session: 28 keys, `id_str`, `user_id_str`,
`full_text`, `lang`, `created_at`, `favorite_count`, `retweet_count`, and no
`reply_count`/`quote_count`/`bookmark_count`/`views` at all, which is why those
come back `null`) plus the `globalObjects.users` entry the author is looked up in.
The case asserts the **handle**, which can only be there if the lookup happened. A
read case asserts `data.tweets[0]` and that no envelope key is left, and a second
asserts `--raw` gives the envelope back.

## The rule to carry

**When the program stops passing a body through and starts reading it, re-check
every fixture of that body against the real thing, and assert something only the
read shape can produce.** A status and a substring both survive a fixture with the
wrong insides.

And its twin: **a check must not require a field the consumer does not need.** The
mentions entry's `id_str` was read for the id and was also deciding whether the
entry was a tweet -- so a key nobody needed decided whether the text was there at
all. The text at the top level is what marks the shape now; `id_str` is read when
X sent it and not required.
