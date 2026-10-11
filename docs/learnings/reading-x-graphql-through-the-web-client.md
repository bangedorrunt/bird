# Reading X's GraphQL with a web session takes more than the cookies

The cookies were alive and still every call was refused. Three separate things
had to be right, and X names them one at a time.

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

## Rule

A web-session API is a moving target with several independent knobs: session
cookies, a client bearer, operation ids, and per-operation variables. Keep every
one of them a setting, never a compiled constant, and drive discovery through
the program's own request so the transport stays X-shaped.
