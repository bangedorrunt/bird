# Reading X's GraphQL with a web session takes more than the cookies

The cookies were alive and still every call was refused. Three separate things
had to be right, and X names them one at a time. A fourth is worse than a
refusal, because it arrives as a 200: X will hand back a post's `t.co` stub and
call that an answer.

## 1. Cookies alone get 403; X's GraphQL wants the web bearer too

With `auth_token` + `ct0`, X's home answers 200 (and 307s to login without
them), but the GraphQL endpoints answer **403** until the `authorization: Bearer
<web bearer>` header is present. The bearer rotates with X's web client; it is
extractable from the bundle the signed-in page loads (`main.*.js`), together
with the four query ids (`Viewer`, `TweetDetail`, `SearchTimeline`,
`CreateTweet`). In `bird` all six are settings (`--web-bearer`, `--op-*`, or the
`BIRD_*` environment spellings), so a rotation is a settings change, not a
release.

## 2. TweetDetail validates its variables and says what is missing

`read`, `thread`, and `replies` all use `TweetDetail`. A 422 came back naming the
first missing variable; supplying it surfaced the next. The full set beside
`focalTweetId` is `includePromotedContent`, `withBirdwatchNotes`, `withVoice`.
Search and `Viewer` accepted their documented variables as-is.

Guessing at the variable set directly got a **404**, because X discards requests
from unknown clients before validating them. The discovery that worked: take
the program's own `--dry-run` curl argv verbatim, mutate only the variables
object, and read X's own error each round — the request shape stays X's, only
the payload is an experiment.

## 3. The error body is worth keeping

X explains refusals in its JSON: `{"message":"Query not found"}` for a stale
query id, the missing variable for a 422. `bird` keeps status and body in the
failure envelope, which is what turned each refusal into a diagnosis instead of
a mystery.

## 4. A detail read's field toggles are half of it; the article body is gated on
feature flags too

`read` on an article post answered `200` with `text` set to
`https://t.co/cUzaPuUqJ1`, `lang` `zxx`, and no `article` object anywhere in a
320 KB body. Nothing was refused. The request already carried the web client's
`fieldToggles` (`withArticleRichContentState`, `withArticlePlainText`) and X's
documented variables.

The missing half is `features`. With `--gql-features` at its empty default X
answers the stub; the article appears once the request carries the consumption
flags (`longform_notetweets_consumption_enabled`,
`responsive_web_twitter_article_tweet_consumption_enabled`,
`longform_notetweets_rich_text_read_enabled`,
`longform_notetweets_inline_media_enabled`, `articles_preview_enabled`). Those
are what a blob copied out of X's own web client already contains, which is why
no one notices the gap until they send an empty one.

The trap is the signal: a stub is a valid answer shape, so every check that asks
"did it parse, did it 200, is the text non-empty" passes. Only asking for a
tweet known to be an article, and asserting the body is not the link, separates
the two.

## Rule

A web-session API is a moving target with several independent knobs: session
cookies, a client bearer, operation ids, per-operation variables, and both the
`features` and `fieldToggles` halves of a detail read. Keep every one of them a
setting, never a compiled constant, and drive discovery through the program's own
request so the transport stays X-shaped. And since a knob left at its default
gives you a plausible wrong answer rather than a refusal, check that a `200`
carries the thing that was asked for, not a stand-in for it.
