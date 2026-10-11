import Base
import ./json.bend as J

# X's answers into the tweets that are in them.
#
# Why this exists: a `read` of one tweet comes back as 119 KB of GraphQL envelope,
# and almost all of it is X's own bookkeeping -- entry ids, cursors, display
# options, the whole profile blob of the author, the client's feature flags. The
# one thing a caller wants out of it, the text, is six levels down at
# `...itemContent.tweet_results.result.legacy.full_text`. This module is that
# walk, done once, in the pure core, so every read verb answers with one shape and
# `--raw` is the only way to see the envelope again.
#
# Three response shapes are in play and they are genuinely different:
#
#   1. GraphQL timelines (`read`, `replies`, `thread`, `search`): a tweet is
#      `{rest_id, legacy:{…}, core:{user_results:{result:{…}}}}`, so its fields
#      live one level down under `legacy` and its author is a nested user object.
#   2. The v2 notifications endpoint (`mentions`): `globalObjects.tweets` maps an
#      id to a v1.1 tweet with its fields at the TOP level, and the author is not
#      in the tweet at all -- it is `globalObjects.users[user_id_str]`.
#   3. `whoami`: one user object wrapped in kilobytes of account flags.
#
# `field` is the one place that knows about (1) versus (2): a key is read from
# `legacy` when the tweet has one and holds that key, and from the top level
# otherwise, which resolves per key rather than per shape. The author is the only
# thing that needs the response root as well as the tweet, because the v2 shape
# keeps its authors in a map beside them.
#
# Four rules of the language shaped this file, and they are the same four
# `src/scan.bend` states at more length: a def must be written before it is
# called; mutual recursion does not typecheck, so each walk is ONE self-recursive
# def; a `match` may only scrutinise a parameter, so every decision on a computed
# test is a def that takes the test as a parameter; and a value is affine, so a
# def that reads a value twice takes it `+`.

# ── digging into an object ──────────────────────────────────────────────
#
# `J.at` answers a `Maybe`; these answer JSON `null` for a missing path, which is
# what a reader wants to hand to the next dig or to a builder.

def Tweets.dig1(+j: J.Json, +a: String) -> J.Json:
  J.or_null(J.at1(j, a))

def Tweets.dig2(+j: J.Json, +a: String, +b: String) -> J.Json:
  J.or_null(J.at2(j, a, b))

def Tweets.dig3(+j: J.Json, +a: String, +b: String, +c: String) -> J.Json:
  J.or_null(J.at3(j, a, b, c))

def Tweets.dig4(+j: J.Json, +a: String, +b: String, +c: String, +d: String) -> J.Json:
  J.or_null(J.at4(j, a, b, c, d))

# `j` when the test says so, and `fallback` otherwise. Named `prefer` rather than
# `if` because both sides are already computed by the caller.
def Tweets.prefer(+use_j: Bool, +fallback: J.Json, +j: J.Json) -> J.Json:
  match use_j:
    case True{}:
      j
    case False{}:
      fallback

def Tweets.cons(+yes: Bool, +x: J.Json, +acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match yes:
    case True{}:
      x <> acc
    case False{}:
      acc

# ── what is a tweet ─────────────────────────────────────────────────────
#
# The GraphQL shape is recognised by `rest_id` next to a `legacy` that holds
# `full_text`; the v2 one by a `full_text` at the top level, which is where a v1.1
# tweet keeps it and where nothing else in an answer does. A user object has an id
# and no text, and a timeline entry wrapper has text nowhere, so neither is
# collected. `rest_id` alone cannot mark a v2 tweet, because it is also how a
# *user* is identified here, so the two tests stay separate.
#
# `id_str` is read for the id when X sent it, and is deliberately NOT part of the
# test: a tweet dropped for a field the walk does not need is an empty timeline
# handed to the caller, which is a worse answer than one with no id.
def Tweets.has_text_at(+j: J.Json) -> Bool:
  J.present(j, "full_text")

def Tweets.graph_shaped(+j: J.Json) -> Bool:
  Bool.and(J.present(j, "rest_id"), Tweets.has_text_at(Tweets.dig1(j, "legacy")))

def Tweets.v2_shaped(+j: J.Json) -> Bool:
  Tweets.has_text_at(j)

def Tweets.is_node(+j: J.Json) -> Bool:
  Bool.or(Tweets.graph_shaped(j), Tweets.v2_shaped(j))

# A node's own subtree is its payload, so the walk collects it and does not
# descend: a quoted tweet is a node inside a node, and descending would answer a
# search with the quote as a result of its own.
# One recursive def, because two that call each other do not typecheck. `skip` is
# the mode: once a node is entered, its whole subtree is skipped rather than
# descended. The dispatch on `skip` sits INSIDE the arm for an object, after the
# match on `j`, because a `match` may only scrutinise a parameter and the test for
# an object's value is computed. Every recursive call is then on `value` or
# `tail`, which is what the termination checker wants.
def Tweets.walk(+j: J.Json, +skip: Bool, +acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match j:
    case J.JsonObj{key, value, tail}:
      match skip:
        case True{}:
          Tweets.walk(tail, True{}, acc)
        case False{}:
          Tweets.walk(tail, False{}, Tweets.walk(value, Tweets.is_node(value), Tweets.cons(Tweets.is_node(value), value, acc)))
    case J.JsonArr{head, tail}:
      Tweets.walk(tail, skip, Tweets.walk(head, skip, acc))
    case _:
      acc

# `walk` conses as it goes, so its accumulator ends in the reverse of the order the
# document has the tweets in; the reversal happens here, once, and every consumer
# below can then build a list the same way and reverse it the same way. Without
# this the answer to a search came back oldest-first, which is the opposite of
# what X sent and of what a caller scrolls.
def Tweets.find(+j: J.Json) -> List<&2, J.Json>:
  List.reverse(&2, J.Json, Tweets.walk(j, False{}, Nil{}))

# ── one field, whichever shape it is in ─────────────────────────────────

def Tweets.meta(+t: J.Json) -> J.Json:
  Tweets.dig1(t, "legacy")

# The value of `key`, from `legacy` when the tweet has one there and from the top
# level otherwise. `views` and `rest_id` are top-level on both shapes, and a count
# is top-level on the v2 one, so this is decided per key rather than per shape.
def Tweets.field_from(+from_legacy: Bool, +t: J.Json, +key: String) -> J.Json:
  match from_legacy:
    case True{}:
      J.get_or_null(Tweets.meta(t), key)
    case False{}:
      J.get_or_null(t, key)

def Tweets.field(+t: J.Json, +key: String) -> J.Json:
  Tweets.field_from(J.present(Tweets.meta(t), key), t, key)

# A key X did not send, or sent as null, is JSON `null` rather than an empty
# string: "this response did not say" and "it said nothing" are different answers.
def Tweets.text_json(+sent: Bool, +value: String) -> J.Json:
  match sent:
    case True{}:
      J.of_str(value)
    case False{}:
      J.null()

def Tweets.field_text(+t: J.Json, +key: String) -> J.Json:
  +value : String = J.text(Tweets.field(t, key))
  Tweets.text_json(Bool.not(J.is_null(Tweets.field(t, key))), value)

def Tweets.count_json(+sent: Bool, +value: J.Json) -> J.Json:
  match sent:
    case True{}:
      J.of_u32(J.u32(value))
    case False{}:
      J.null()

def Tweets.field_count(+t: J.Json, +key: String) -> J.Json:
  +value : J.Json = Tweets.field(t, key)
  Tweets.count_json(Bool.not(J.is_null(value)), value)

# ── the text ────────────────────────────────────────────────────────────
#
# A long post puts the whole thing in `note_tweet` and leaves `legacy.full_text`
# as a truncated line with a link to itself, so the note wins when it is there.
# That is the difference between scraping a tweet and scraping the paragraph in it.
def Tweets.long_form(+t: J.Json) -> String:
  J.text(Tweets.dig4(t, "note_tweet", "note_tweet_results", "result", "text"))

def Tweets.short_form(+t: J.Json) -> String:
  J.text(Tweets.field(t, "full_text"))

def Tweets.text_body(+long: Bool, +full: String, +short: String) -> String:
  match long:
    case True{}:
      full
    case False{}:
      short

def Tweets.text_of(+t: J.Json) -> String:
  +long : String = Tweets.long_form(t)
  Tweets.text_body(Bool.not(String.is_empty(long)), long, Tweets.short_form(t))

# ── the author ──────────────────────────────────────────────────────────
#
# The GraphQL shape keeps the handle under `core`, NOT under `legacy`: reading
# `legacy.screen_name` on a live response returns nothing, which is how a
# normalizer quietly answers with an empty author.
def Tweets.user_of(+t: J.Json) -> J.Json:
  Tweets.dig3(t, "core", "user_results", "result")

def Tweets.user_id_ref(+t: J.Json) -> String:
  J.text(Tweets.field(t, "user_id_str"))

def Tweets.listed_user_on(+anonymous: Bool, +t: J.Json, +root: J.Json) -> J.Json:
  match anonymous:
    case True{}:
      J.null()
    case False{}:
      Tweets.dig3(root, "globalObjects", "users", Tweets.user_id_ref(t))

def Tweets.listed_user(+t: J.Json, +root: J.Json) -> J.Json:
  Tweets.listed_user_on(String.is_empty(Tweets.user_id_ref(t)), t, root)

def Tweets.user_on(+found: Bool, +t: J.Json, +root: J.Json) -> J.Json:
  match found:
    case True{}:
      Tweets.user_of(t)
    case False{}:
      Tweets.listed_user(t, root)

def Tweets.first_text_on(+blank: Bool, +a: J.Json, +b: J.Json) -> String:
  match blank:
    case True{}:
      J.text(b)
    case False{}:
      J.text(a)

def Tweets.first_text(+a: J.Json, +b: J.Json) -> String:
  Tweets.first_text_on(String.is_empty(J.text(a)), a, b)

def Tweets.user_field(+u: J.Json, +key: String) -> String:
  Tweets.first_text(Tweets.dig2(u, "core", key), Tweets.dig1(u, key))

def Tweets.user_id(+u: J.Json) -> String:
  Tweets.first_text(J.get_or_null(u, "rest_id"), J.get_or_null(u, "id_str"))

def Tweets.avatar_of(+u: J.Json) -> String:
  Tweets.first_text(Tweets.dig2(u, "avatar", "image_url"), Tweets.dig1(u, "profile_image_url_https"))

# `is_blue_verified` is the modern flag, `verification.verified` the one the v2
# endpoint still sends, and `verified` the v1.1 one the mentions map carries.
def Tweets.verified_on(+modern: Bool, +u: J.Json) -> Bool:
  match modern:
    case True{}:
      J.bool(J.get_or_null(u, "is_blue_verified"))
    case False{}:
      Bool.or(J.bool(Tweets.dig2(u, "verification", "verified")), J.bool(J.get_or_null(u, "verified")))

def Tweets.verified_of(+u: J.Json) -> Bool:
  Tweets.verified_on(J.present(u, "is_blue_verified"), u)

def Tweets.author_fields(+u: J.Json) -> List<&2, J.JField>:
  J.pair("id", J.of_str(Tweets.user_id(u))) <> (
    J.pair("handle", J.of_str(Tweets.user_field(u, "screen_name"))) <> (
      J.pair("name", J.of_str(Tweets.user_field(u, "name"))) <> (
        J.pair("verified", J.of_bool(Tweets.verified_of(u))) <> (
          J.pair("avatar", Tweets.text_json(Bool.not(String.is_empty(Tweets.avatar_of(u))), Tweets.avatar_of(u))) <> Nil{}
        )
      )
    )
  )

def Tweets.author_on(+none: Bool, +u: J.Json) -> J.Json:
  match none:
    case True{}:
      J.null()
    case False{}:
      J.obj_of(Tweets.author_fields(u))

def Tweets.author_of(+t: J.Json, +root: J.Json) -> J.Json:
  +u : J.Json = Tweets.user_on(Bool.not(J.is_null(Tweets.user_of(t))), t, root)
  Tweets.author_on(J.is_null(u), u)

# ── media and links ─────────────────────────────────────────────────────
#
# `extended_entities` is the fuller list and only appears on a post that has one;
# plain `entities.media` is the fallback, and both live wherever `field` says.
def Tweets.media_array(+t: J.Json) -> J.Json:
  +ext : J.Json = Tweets.dig1(Tweets.field(t, "extended_entities"), "media")
  Tweets.prefer(Bool.not(J.is_null(ext)), Tweets.dig1(Tweets.field(t, "entities"), "media"), ext)

def Tweets.media_item(+m: J.Json) -> J.Json:
  +kind : String = J.text(J.get_or_null(m, "type"))
  +url : String = J.text(J.get_or_null(m, "media_url_https"))
  +alt : String = J.text(J.get_or_null(m, "ext_alt_text"))
  J.obj_of(
    J.pair("type", Tweets.text_json(Bool.not(String.is_empty(kind)), kind)) <> (
      J.pair("url", Tweets.text_json(Bool.not(String.is_empty(url)), url)) <> (
        J.pair("alt", Tweets.text_json(Bool.not(String.is_empty(alt)), alt)) <> Nil{}
      )
    )
  )

def Tweets.media_each(+xs: List<&2, J.Json>, +acc: List<&2, J.Json>) -> J.Json:
  match xs:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Tweets.media_each(rest, Tweets.media_item(h) <> acc)

def Tweets.media(+t: J.Json) -> J.Json:
  Tweets.media_each(J.items(Tweets.media_array(t)), Nil{})

def Tweets.url_item(+u: J.Json) -> J.Json:
  J.obj_of(
    J.pair("url", J.of_str(J.text(J.get_or_null(u, "url")))) <> (
      J.pair("expanded", J.of_str(J.text(J.get_or_null(u, "expanded_url")))) <> (
        J.pair("display", J.of_str(J.text(J.get_or_null(u, "display_url")))) <> Nil{}
      )
    )
  )

def Tweets.url_each(+xs: List<&2, J.Json>, +acc: List<&2, J.Json>) -> J.Json:
  match xs:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Tweets.url_each(rest, Tweets.url_item(h) <> acc)

def Tweets.urls(+t: J.Json) -> J.Json:
  Tweets.url_each(J.items(Tweets.dig1(Tweets.field(t, "entities"), "urls")), Nil{})

# ── what it counts ──────────────────────────────────────────────────────

def Tweets.views(+t: J.Json) -> J.Json:
  +count : J.Json = Tweets.dig2(t, "views", "count")
  Tweets.count_json(Bool.not(J.is_null(count)), count)

def Tweets.metrics_fields(+t: J.Json) -> List<&2, J.JField>:
  J.pair("replies", Tweets.field_count(t, "reply_count")) <> (
    J.pair("retweets", Tweets.field_count(t, "retweet_count")) <> (
      J.pair("likes", Tweets.field_count(t, "favorite_count")) <> (
        J.pair("quotes", Tweets.field_count(t, "quote_count")) <> (
          J.pair("bookmarks", Tweets.field_count(t, "bookmark_count")) <> (
            J.pair("views", Tweets.views(t)) <> Nil{}
          )
        )
      )
    )
  )

def Tweets.id_on(+graph: Bool, +t: J.Json) -> String:
  match graph:
    case True{}:
      J.text(J.get_or_null(t, "rest_id"))
    case False{}:
      J.text(J.get_or_null(t, "id_str"))

def Tweets.id_of(+t: J.Json) -> String:
  Tweets.id_on(J.present(t, "rest_id"), t)

# ── one tweet ───────────────────────────────────────────────────────────
#
# `body` is identity, text, time, author, counts, media and links: everything a
# caller asked for and nothing else. A quoted tweet IS a body, one level only,
# because a quote of a quote is the quoted tweet's own business and following it
# would need a fuel argument: a recursion on a value the termination checker
# cannot see shrinking is refused.
def Tweets.body_fields(+t: J.Json, +root: J.Json) -> List<&2, J.JField>:
  J.pair("id", J.of_str(Tweets.id_of(t))) <> (
    J.pair("text", J.of_str(Tweets.text_of(t))) <> (
      J.pair("lang", Tweets.field_text(t, "lang")) <> (
        J.pair("created_at", Tweets.field_text(t, "created_at")) <> (
          J.pair("author", Tweets.author_of(t, root)) <> (
            J.pair("metrics", J.obj_of(Tweets.metrics_fields(t))) <> (
              J.pair("media", Tweets.media(t)) <> (
                J.pair("urls", Tweets.urls(t)) <> Nil{}
              )
            )
          )
        )
      )
    )
  )

def Tweets.body(+t: J.Json, +root: J.Json) -> J.Json:
  J.obj_of(Tweets.body_fields(t, root))

# `quoted_status_id_str` is the v2 fallback, which carries the id of the quote and
# not its text: a quote X did not send cannot be invented, so the field is null.
def Tweets.quoted_node(+t: J.Json) -> J.Json:
  Tweets.dig2(t, "quoted_status_result", "result")

def Tweets.quoted_on(+has_node: Bool, +t: J.Json, +root: J.Json) -> J.Json:
  match has_node:
    case True{}:
      Tweets.body(Tweets.quoted_node(t), root)
    case False{}:
      J.null()

def Tweets.quoted(+t: J.Json, +root: J.Json) -> J.Json:
  Tweets.quoted_on(Tweets.is_node(Tweets.quoted_node(t)), t, root)

def Tweets.extra_fields(+t: J.Json, +root: J.Json) -> List<&2, J.JField>:
  J.pair("quoted", Tweets.quoted(t, root)) <> (
    J.pair("in_reply_to", Tweets.field_text(t, "in_reply_to_status_id_str")) <> Nil{}
  )

def Tweets.one(+t: J.Json, +root: J.Json) -> J.Json:
  J.obj_of(List.append(&2, J.JField, Tweets.body_fields(t, root), Tweets.extra_fields(t, root)))

# ── a whole answer ──────────────────────────────────────────────────────

def Tweets.each(+nodes: List<&2, J.Json>, +root: J.Json, +acc: List<&2, J.Json>) -> J.Json:
  match nodes:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Tweets.each(rest, root, Tweets.one(h, root) <> acc)

# `read` asks for one tweet and X answers with the conversation around it, so the
# nodes are filtered to the id that was asked for. `replies`, `thread`, `search`
# and `mentions` asked for a list and pass nothing.
def Tweets.keeping(+nodes: List<&2, J.Json>, +want: String, +acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match nodes:
    case Nil{}:
      List.reverse(&2, J.Json, acc)
    case +h <> rest:
      Tweets.keeping(rest, want, Tweets.cons(String.eq(Tweets.id_of(h), want), h, acc))

def Tweets.chosen_on(+every: Bool, +nodes: List<&2, J.Json>, +want: String) -> List<&2, J.Json>:
  match every:
    case True{}:
      nodes
    case False{}:
      Tweets.keeping(nodes, want, Nil{})

def Tweets.chosen(+nodes: List<&2, J.Json>, +want: String) -> List<&2, J.Json>:
  Tweets.chosen_on(String.is_empty(want), nodes, want)

def Tweets.list_in(+root: J.Json, +want: String) -> J.Json:
  J.obj_of(J.pairs1(J.pair("tweets", Tweets.each(Tweets.chosen(Tweets.find(root), want), root, Nil{}))))

def Tweets.count_in(+payload: J.Json) -> U32:
  J.count(Tweets.dig1(payload, "tweets"))

# ── one profile ─────────────────────────────────────────────────────────
#
# `whoami` answers with the signed-in user wrapped in account flags
# (`can_access_payments`, `is_super_follow_subscriber`, …) that no caller asked
# for. The bio, the counts and the handle are what a caller wanted.
def Tweets.bio_of(+u: J.Json) -> String:
  Tweets.first_text(Tweets.dig2(u, "profile_bio", "description"), Tweets.dig1(u, "description"))

def Tweets.place_of(+u: J.Json) -> String:
  Tweets.first_text(Tweets.dig2(u, "location", "location"), Tweets.dig1(u, "location"))

# `created_at` and the handle are the same shape here: a user object keeps both
# under `core` on the GraphQL side and at the top level on the v1.1 side.
def Tweets.profile_fields(+u: J.Json) -> List<&2, J.JField>:
  List.append(&2, J.JField, Tweets.author_fields(u), (
    J.pair("bio", Tweets.text_json(Bool.not(String.is_empty(Tweets.bio_of(u))), Tweets.bio_of(u))) <> (
      J.pair("followers", Tweets.dig1(Tweets.dig1(u, "relationship_counts"), "followers")) <> (
        J.pair("following", Tweets.dig1(Tweets.dig1(u, "relationship_counts"), "following")) <> (
          J.pair("tweets", Tweets.dig1(Tweets.dig1(u, "tweet_counts"), "tweets")) <> (
            J.pair("location", Tweets.text_json(Bool.not(String.is_empty(Tweets.place_of(u))), Tweets.place_of(u))) <> (
              J.pair("created_at", Tweets.text_json(Bool.not(String.is_empty(Tweets.user_field(u, "created_at"))), Tweets.user_field(u, "created_at"))) <> Nil{}
            )
          )
        )
      )
    )
  ))

def Tweets.viewer(+root: J.Json) -> J.Json:
  Tweets.dig4(root, "data", "viewer", "user_results", "result")

def Tweets.profile_on(+none: Bool, +u: J.Json) -> J.Json:
  match none:
    case True{}:
      J.null()
    case False{}:
      J.obj_of(Tweets.profile_fields(u))

def Tweets.profile_in(+root: J.Json) -> J.Json:
  +u : J.Json = Tweets.viewer(root)
  J.obj_of(J.pairs1(J.pair("profile", Tweets.profile_on(J.is_null(u), u))))
