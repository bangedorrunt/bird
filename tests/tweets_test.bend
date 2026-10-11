import Base
import ../src/tweets.bend as T
import ../src/json.bend as J

# End-to-end check of the tweet extractor. Bend ships no test framework, so the
# test is a program: it prints one line per case and dies with a nonzero exit
# code on the first failure.
#
#   bend tests/tweets_test.bend
#
# The fixtures are shaped like the responses recorded from a live session on
# 2026-10-11, trimmed to the fields the extractor reads. Three shapes are in
# play and each has its own body below: a GraphQL timeline (fields under
# `legacy`, the author nested under `core`), the v2 notifications endpoint
# (fields at the top level, authors in a map beside the tweets), and `whoami`
# (one viewer object).
#
# The cases that matter are the ones a naive reading gets wrong: the author's
# handle is under `core` and NOT under `legacy`; a long post's real text is in
# `note_tweet` and not in the truncated `full_text` beside it; a count X did not
# send is null rather than zero; and a quoted tweet is inside the tweet that
# quoted it, so it must not come back as a result of its own.
#
# Defs are written callee first, because Bend has no forward declarations.

def ok_on(passed: Bool, +name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

# A fixture that does not parse is a broken test rather than a failing case, so it
# stops the run with the parser's own words instead of answering an empty body.
def value_on(p: J.Parsed) -> IO(J.Json):
  match p:
    case J.ParsedOk{value}:
      IO.pure(J.Json, value)
    case J.ParsedErr{message}:
      IO.die(J.Json, 2, "fixture does not parse: " ++ message)

def value_of(body: String) -> IO(J.Json):
  value_on(J.parse(body))

def tweets_of(+root: J.Json, want: String) -> J.Json:
  J.get_or_null(T.Tweets.list_in(root, want), "tweets")

def field_of(+j: J.Json, key: String) -> J.Json:
  J.get_or_null(j, key)

def first_of(xs: J.Json) -> J.Json:
  J.at_index(xs, 0n)

def second_of(xs: J.Json) -> J.Json:
  J.at_index(xs, 1n)

def n_found(+xs: List<&2, J.Json>) -> U32:
  J.count(J.arr_of(xs))

# A GraphQL timeline: a focal tweet that is long, carries media and a quote, and
# is a reply; then a second, plainer tweet. The focal tweet's `legacy.full_text`
# is the truncated line X sends beside a long post, and `entities.media` holds one
# photo while `extended_entities.media` holds two -- the fuller list wins.
def timeline_body() -> String:
  "{\"data\":{\"threaded_conversation_with_injections_v2\":{\"instructions\":[{\"entries\":[{\"entryId\":\"a\",\"content\":{\"itemContent\":{\"tweet_results\":{\"result\":{\"rest_id\":\"200\",\"legacy\":{\"full_text\":\"truncated...\",\"lang\":\"en\",\"created_at\":\"Sat Oct 10 00:00:00 +0000 2026\",\"user_id_str\":\"77\",\"reply_count\":3,\"retweet_count\":4,\"favorite_count\":5,\"quote_count\":6,\"bookmark_count\":7,\"in_reply_to_status_id_str\":\"199\",\"entities\":{\"urls\":[{\"url\":\"https://t.co/aaa\",\"expanded_url\":\"https://example.com/a\",\"display_url\":\"example.com/a\"}],\"media\":[{\"type\":\"photo\",\"media_url_https\":\"https://pbs.twimg.com/media/base.jpg\"}]},\"extended_entities\":{\"media\":[{\"type\":\"photo\",\"media_url_https\":\"https://pbs.twimg.com/media/one.jpg\",\"ext_alt_text\":\"alt one\"},{\"type\":\"video\",\"media_url_https\":\"https://pbs.twimg.com/media/two.jpg\"}]}},\"note_tweet\":{\"note_tweet_results\":{\"result\":{\"text\":\"the whole long post\"}}},\"views\":{\"count\":\"12345\"},\"core\":{\"user_results\":{\"result\":{\"rest_id\":\"77\",\"is_blue_verified\":true,\"screen_name\":\"decoy\",\"name\":\"A Decoy\",\"avatar\":{\"image_url\":\"https://pbs.twimg.com/profile_images/x_normal.jpg\"},\"core\":{\"screen_name\":\"replier\",\"name\":\"A Replier\"}}}},\"quoted_status_result\":{\"result\":{\"rest_id\":\"198\",\"legacy\":{\"full_text\":\"the quoted tweet\",\"lang\":\"en\",\"created_at\":\"Fri Oct 09 00:00:00 +0000 2026\"},\"core\":{\"user_results\":{\"result\":{\"rest_id\":\"88\",\"core\":{\"screen_name\":\"quoted\",\"name\":\"Quoted One\"}}}}}}}}}}},{\"entryId\":\"b\",\"content\":{\"itemContent\":{\"tweet_results\":{\"result\":{\"rest_id\":\"201\",\"legacy\":{\"full_text\":\"a reply tweet\",\"lang\":\"de\",\"created_at\":\"Sat Oct 10 00:01:00 +0000 2026\",\"user_id_str\":\"99\"},\"core\":{\"user_results\":{\"result\":{\"rest_id\":\"99\",\"core\":{\"screen_name\":\"third\",\"name\":\"Third\"}}}}}}}}}]}]}}}"

# The v2 notifications endpoint: fields at the top level, no `lang` at all, and
# the author in `globalObjects.users` keyed by the tweet's `user_id_str`.
def mentions_body() -> String:
  "{\"globalObjects\":{\"tweets\":{\"300\":{\"id_str\":\"300\",\"full_text\":\"a mention\",\"user_id_str\":\"42\",\"favorite_count\":9,\"retweet_count\":1,\"created_at\":\"Sat Oct 10 01:00:00 +0000 2026\",\"in_reply_to_status_id_str\":\"201\"}},\"users\":{\"42\":{\"id_str\":\"42\",\"screen_name\":\"mentioneer\",\"name\":\"Mentioned\",\"verified\":false,\"profile_image_url_https\":\"https://pbs.twimg.com/profile_images/m_normal.jpg\"}}}}"

# The same endpoint with an entry that carries no `id_str` -- the id is also the
# map key, so a real answer can leave it out. The tweet has to come back anyway:
# the field the walk wants is the text, and a timeline answered empty over an id
# the caller never asked for is the silent failure this case exists for.
def mentions_bare_body() -> String:
  "{\"globalObjects\":{\"tweets\":{\"301\":{\"full_text\":\"a bare mention\",\"user_id_str\":\"42\"}},\"users\":{\"42\":{\"id_str\":\"42\",\"screen_name\":\"mentioneer\"}}}}"

def whoami_body() -> String:
  "{\"data\":{\"viewer\":{\"user_results\":{\"result\":{\"rest_id\":\"282004858\",\"is_blue_verified\":false,\"core\":{\"screen_name\":\"someone\",\"name\":\"Some One\",\"created_at\":\"Thu Apr 14 11:35:07 +0000 2011\"},\"avatar\":{\"image_url\":\"https://pbs.twimg.com/profile_images/y_normal.jpg\"},\"profile_bio\":{\"description\":\"a bio\"},\"location\":{\"location\":\"Melbourne, Australia\"},\"relationship_counts\":{\"followers\":75,\"following\":373},\"tweet_counts\":{\"tweets\":188}}}}}}"

# A check that came back signed out: the viewer is gone, so a profile would be a
# record of nothing.
def no_viewer_body() -> String:
  "{\"data\":{\"viewer\":null}}"

def check_shape() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(timeline_body())
    +xs : J.Json = tweets_of(root, SNil{})
    ok("a timeline answers with both of its tweets", U32.is_eq(J.count(xs), 2))
    ok("the focal tweet comes first", String.eq(J.text(field_of(first_of(xs), "id")), "200"))
    ok("the second tweet is the second", String.eq(J.text(field_of(second_of(xs), "id")), "201"))
    ok("a long post answers with the note, not the truncated line",
       String.eq(J.text(field_of(first_of(xs), "text")), "the whole long post"))
    ok("a short tweet answers with its own text",
       String.eq(J.text(field_of(second_of(xs), "text")), "a reply tweet"))
    ok("the language comes back", String.eq(J.text(field_of(second_of(xs), "lang")), "de"))
    ok("the time comes back",
       String.eq(J.text(field_of(first_of(xs), "created_at")), "Sat Oct 10 00:00:00 +0000 2026"))
    ok("the reply target comes back", String.eq(J.text(field_of(first_of(xs), "in_reply_to")), "199"))
    ok("a tweet that is not a reply has no reply target", J.is_null(field_of(second_of(xs), "in_reply_to")))
    ok("a count X sent comes back", U32.is_eq(J.u32(field_of(field_of(first_of(xs), "metrics"), "likes")), 5))
    ok("views come from the count beside them",
       U32.is_eq(J.u32(field_of(field_of(first_of(xs), "metrics"), "views")), 12345))
    ok("a count X did not send is null, not zero",
       J.is_null(field_of(field_of(second_of(xs), "metrics"), "likes")))
    ok("...and that tweet still has its metrics object", J.is_obj(field_of(second_of(xs), "metrics")))

def check_author() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(timeline_body())
    +xs : J.Json = tweets_of(root, SNil{})
    +author : J.Json = field_of(first_of(xs), "author")
    ok("the handle is read from core, not from legacy",
       String.eq(J.text(field_of(author, "handle")), "replier"))
    ok("the display name comes back too", String.eq(J.text(field_of(author, "name")), "A Replier"))
    ok("the author's id survives as a string", String.eq(J.text(field_of(author, "id")), "77"))
    ok("the verification flag is read", J.bool(field_of(author, "verified")))
    ok("the avatar comes back",
       String.eq(J.text(field_of(author, "avatar")), "https://pbs.twimg.com/profile_images/x_normal.jpg"))
    +plain : J.Json = field_of(second_of(xs), "author")
    ok("an author X did not send a flag for is not verified", Bool.not(J.bool(field_of(plain, "verified"))))
    ok("...and has no avatar X sent", J.is_null(field_of(plain, "avatar")))

def check_media() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(timeline_body())
    +xs : J.Json = tweets_of(root, SNil{})
    +media : J.Json = field_of(first_of(xs), "media")
    ok("extended_entities wins over entities", U32.is_eq(J.count(media), 2))
    ok("the first attachment is the first one", String.eq(J.text(field_of(first_of(media), "type")), "photo"))
    ok("its url comes back",
       String.eq(J.text(field_of(first_of(media), "url")), "https://pbs.twimg.com/media/one.jpg"))
    ok("its alt text comes back", String.eq(J.text(field_of(first_of(media), "alt")), "alt one"))
    ok("the second attachment is a video", String.eq(J.text(field_of(second_of(media), "type")), "video"))
    ok("an attachment with no alt text has none", J.is_null(field_of(second_of(media), "alt")))
    ok("a tweet with no attachments answers with an empty list",
       U32.is_eq(J.count(field_of(second_of(xs), "media")), 0))
    +urls : J.Json = field_of(first_of(xs), "urls")
    ok("a link in the text comes back expanded",
       String.eq(J.text(field_of(first_of(urls), "expanded")), "https://example.com/a"))

def check_quote() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(timeline_body())
    +xs : J.Json = tweets_of(root, SNil{})
    ok("a quoted tweet is not a tweet of its own", U32.is_eq(J.count(xs), 2))
    +quoted : J.Json = field_of(first_of(xs), "quoted")
    ok("the quote is one level deep", String.eq(J.text(field_of(quoted, "id")), "198"))
    ok("the quote carries its own text", String.eq(J.text(field_of(quoted, "text")), "the quoted tweet"))
    ok("the quote carries its own author",
       String.eq(J.text(field_of(field_of(quoted, "author"), "handle")), "quoted"))
    ok("a quote of a quote is not followed", J.is_null(field_of(quoted, "quoted")))
    ok("a tweet that quoted nothing has no quote", J.is_null(field_of(second_of(xs), "quoted")))

def check_filter() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(timeline_body())
    ok("read keeps the tweet it asked for", U32.is_eq(J.count(tweets_of(root, "201")), 1))
    ok("...and it is that tweet",
       String.eq(J.text(field_of(first_of(tweets_of(root, "201")), "id")), "201"))
    ok("read answers nothing for a tweet that is not there", U32.is_eq(J.count(tweets_of(root, "404")), 0))
    ok("the count helper counts what a payload holds",
       U32.is_eq(T.Tweets.count_in(T.Tweets.list_in(root, SNil{})), 2))

def check_mentions() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(mentions_body())
    +xs : J.Json = tweets_of(root, SNil{})
    ok("the v2 shape answers with its tweet", U32.is_eq(J.count(xs), 1))
    +t : J.Json = first_of(xs)
    ok("a top level id is read", String.eq(J.text(field_of(t, "id")), "300"))
    ok("a top level text is read", String.eq(J.text(field_of(t, "text")), "a mention"))
    ok("a top level time is read",
       String.eq(J.text(field_of(t, "created_at")), "Sat Oct 10 01:00:00 +0000 2026"))
    ok("a top level count is read", U32.is_eq(J.u32(field_of(field_of(t, "metrics"), "likes")), 9))
    ok("a field this endpoint does not send is null", J.is_null(field_of(t, "lang")))
    +author : J.Json = field_of(t, "author")
    ok("the author comes from the map beside the tweets",
       String.eq(J.text(field_of(author, "handle")), "mentioneer"))
    ok("...with its display name", String.eq(J.text(field_of(author, "name")), "Mentioned"))
    ok("...and its avatar",
       String.eq(J.text(field_of(author, "avatar")), "https://pbs.twimg.com/profile_images/m_normal.jpg"))

def check_bare_mention() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(mentions_bare_body())
    +xs : J.Json = tweets_of(root, SNil{})
    ok("a mention with no id_str is still a mention", U32.is_eq(J.count(xs), 1))
    +t : J.Json = first_of(xs)
    ok("...and its text is read", String.eq(J.text(field_of(t, "text")), "a bare mention"))
    ok("...with an id of nothing, since X sent none", String.eq(J.text(field_of(t, "id")), ""))
    ok("...and the author beside it is still found",
       String.eq(J.text(field_of(field_of(t, "author"), "handle")), "mentioneer"))

def check_profile() -> IO(Unit):
  do IO<Unit>:
    +root : J.Json <- value_of(whoami_body())
    +p : J.Json = field_of(T.Tweets.profile_in(root), "profile")
    ok("whoami answers with one profile", String.eq(J.text(field_of(p, "handle")), "someone"))
    ok("the profile's id is a string", String.eq(J.text(field_of(p, "id")), "282004858"))
    ok("the bio comes back", String.eq(J.text(field_of(p, "bio")), "a bio"))
    ok("the followers come back", U32.is_eq(J.u32(field_of(p, "followers")), 75))
    ok("the following come back", U32.is_eq(J.u32(field_of(p, "following")), 373))
    ok("the tweet count comes back", U32.is_eq(J.u32(field_of(p, "tweets")), 188))
    ok("the location comes back", String.eq(J.text(field_of(p, "location")), "Melbourne, Australia"))
    ok("the join date comes from core",
       String.eq(J.text(field_of(p, "created_at")), "Thu Apr 14 11:35:07 +0000 2011"))
    +gone : J.Json <- value_of(no_viewer_body())
    ok("a signed out check has no profile to answer with",
       J.is_null(field_of(T.Tweets.profile_in(gone), "profile")))

def check_nothing_found() -> IO(Unit):
  do IO<Unit>:
    +empty : J.Json <- value_of("{\"data\":{\"x\":{\"entries\":[{\"promoted\":true}]}}}")
    ok("a timeline with no tweet in it answers with an empty list", U32.is_eq(J.count(tweets_of(empty, SNil{})), 0))
    ok("...and the walk itself finds nothing", U32.is_eq(n_found(T.Tweets.find(empty)), 0))
    +viewer : J.Json <- value_of(whoami_body())
    ok("a user object is not a tweet", U32.is_eq(n_found(T.Tweets.find(viewer)), 0))

def main() -> IO(Unit):
  do IO<Unit>:
    check_shape()
    check_author()
    check_media()
    check_quote()
    check_filter()
    check_mentions()
    check_bare_mention()
    check_profile()
    check_nothing_found()
