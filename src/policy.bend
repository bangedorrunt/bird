import Base
import ./domain.bend as D
import ./json.bend as J

# Pure policy: every decision that is not a side effect. No IO, no clock, no
# environment reads -- the environment arrives as data in `MsgStart`, which is
# what makes all of this testable, and provable, without a fake world.
#
# The defs are written callee first. Bend has no forward declarations: a call to
# a def written below its caller is reported as an unfilled law.
#
# A walk that stops early is written as an unconditional fold that carries its
# answer, because the "shall I recurse?" branch would have to call back into the
# fold: mutual recursion, which Bend rejects.

# ── tweet ids ───────────────────────────────────────────────────────────

# `read`, `reply`, `replies` and `thread` all take "a tweet id or a URL". A URL
# is split on `/` and the segment after `status` is the id; anything else is
# read as an id and reduced to its leading digits.
def TweetId.push_if_digit(is_digit: Bool, h: Char,+acc: String) -> String:
  match is_digit:
    case True{}:
      SCon{h, acc}
    case False{}:
      acc

def TweetId.push_digit(stopped: Bool,+h: Char,+acc: String) -> String:
  match stopped:
    case True{}:
      acc
    case False{}:
      TweetId.push_if_digit(Char.is_digit(h), h, acc)

def TweetId.stop_on(stopped: Bool, h: Char) -> Bool:
  match stopped:
    case True{}:
      True{}
    case False{}:
      Bool.not(Char.is_digit(h))

# acc holds the digits reversed, so a push is O(1) and the reversal happens once.
def TweetId.digits(s: String,+acc: String,+stopped: Bool) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+h, t}:
      TweetId.digits(t, TweetId.push_digit(stopped, h, acc), TweetId.stop_on(stopped, h))

def TweetId.leading(s: String) -> String:
  TweetId.digits(s, SNil{}, False{})

def TweetId.take_if(prev: Bool, s: String, fallback: String) -> String:
  match prev:
    case True{}:
      s
    case False{}:
      fallback

def TweetId.after_status(segs: List<&2, String>, prev: Bool,+fallback: String) -> String:
  match segs:
    case Nil{}:
      fallback
    case +s <> rest:
      TweetId.after_status(rest, String.eq(s, "status"), TweetId.take_if(prev, s, fallback))

def TweetId.finish(+segment: String, input: String) -> String:
  match segment:
    case "":
      TweetId.leading(input)
    case _:
      TweetId.leading(segment)

def TweetId.of(+input: String) -> String:
  TweetId.finish(TweetId.after_status(String.split(input, '/'), False{}, SNil{}), input)

def TweetId.is_plausible(+id: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(id)), String.eq(TweetId.leading(id), id))

# ── the target a verb points at ─────────────────────────────────────────
#
# `read`, `replies`, `thread` and `reply` take an id or a whole url, and what
# reaches the request is the id read out of it. An input with no digits in it
# reads out nothing, and an empty `focalTweetId` or `in_reply_to_tweet_id` spends
# a round trip to learn something knowable here. `TweetId.is_plausible` was
# written for this guard and had nothing calling it.
def Target.bad(t: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "that is not a tweet id, and none can be read out of it: " ++ t,
    "pass the numeric id, or a url with /status/<id> in its path"
  )

def Target.checked(ok: Bool, +t: String) -> Maybe<&2, D.Error>:
  match ok:
    case True{}:
      None{}
    case False{}:
      Some{Target.bad(t)}

def Target.error_on(target: Maybe<&2, String>) -> Maybe<&2, D.Error>:
  match target:
    case Some{+t}:
      Target.checked(TweetId.is_plausible(TweetId.of(t)), t)
    case None{}:
      None{}

def Cfg.target_error(+v: D.Verb) -> Maybe<&2, D.Error>:
  Target.error_on(D.Verb.target_of(v))

# ── media policy ────────────────────────────────────────────────────────

# X accepts up to four images, or one video, and never a mixture.
def Media.kind_of(mime: String) -> D.MediaKind:
  match mime:
    case "video/mp4":
      D.MediaVideo{}
    case "video/quicktime":
      D.MediaVideo{}
    case _:
      D.MediaImage{}

def Media.mime_of(ext: String) -> Maybe<&2, String>:
  match ext:
    case "jpg":
      Some{"image/jpeg"}
    case "jpeg":
      Some{"image/jpeg"}
    case "png":
      Some{"image/png"}
    case "webp":
      Some{"image/webp"}
    case "gif":
      Some{"image/gif"}
    case "mp4":
      Some{"video/mp4"}
    case "m4v":
      Some{"video/mp4"}
    case "mov":
      Some{"video/quicktime"}
    case _:
      None{}

# The extension is the text after the last dot; a path with one dot or none has
# no extension, which is what the two `<> Nil{}` cases say.
def Media.ext_on(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}:
      SNil{}
    case +one <> Nil{}:
      SNil{}
    case +h <> t:
      String.to_lower(Maybe.default(&2, String, List.last(&2, String, t), SNil{}))

def Media.ext(path: String) -> String:
  Media.ext_on(String.split(path, '.'))

def Media.detect(path: String) -> Maybe<&2, String>:
  Media.mime_of(Media.ext(path))

def Media.mime_or(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      SNil{}
    case Some{s}:
      s

def Media.mime_for(path: String) -> String:
  Media.mime_or(Media.detect(path))

def Media.kind_for(path: String) -> D.MediaKind:
  Media.kind_of(Media.mime_for(path))

def Media.kind_is_image(k: D.MediaKind) -> Bool:
  match k:
    case D.MediaImage{}:
      True{}
    case D.MediaVideo{}:
      False{}

def Media.is_image(path: String) -> Bool:
  Media.kind_is_image(Media.kind_for(path))

def Media.next_images_on(image: Bool,+images: U32) -> U32:
  match image:
    case True{}:
      U32.add(images, 1)
    case False{}:
      images

def Media.next_images(path: String, images: U32) -> U32:
  Media.next_images_on(Media.is_image(path), images)

def Media.next_videos_on(image: Bool,+videos: U32) -> U32:
  match image:
    case True{}:
      videos
    case False{}:
      U32.add(videos, 1)

def Media.next_videos(path: String, videos: U32) -> U32:
  Media.next_videos_on(Media.is_image(path), videos)

# The first complaint wins, so an error names the rule that was actually broken
# rather than whatever a later check happened to notice. Not a media rule: the
# numeric settings read "the first thing wrong with the values that were given"
# the same way, so it lives here on its own.
def Err.first(prev: Maybe<&2, D.Error>, found: Maybe<&2, D.Error>) -> Maybe<&2, D.Error>:
  match prev:
    case Some{e}:
      Some{e}
    case None{}:
      found

def Media.supported_on(+path: String, m: Maybe<&2, String>) -> Maybe<&2, D.Error>:
  match m:
    case None{}:
      Some{D.err(D.ErrUsage{}, "unsupported media type: " ++ path)}
    case Some{mime}:
      None{}

def Media.supported(+path: String) -> Maybe<&2, D.Error>:
  Media.supported_on(path, Media.detect(path))

def Media.one_err(cond: Bool, message: String) -> Maybe<&2, D.Error>:
  match cond:
    case True{}:
      Some{D.err(D.ErrUsage{}, message)}
    case False{}:
      None{}

def q_mix(images: U32, videos: U32) -> Bool:
  Bool.and(U32.is_gt(images, 0), U32.is_gt(videos, 0))

def Media.image_rule(+images: U32, videos: U32) -> Maybe<&2, D.Error>:
  Err.first(
    Media.one_err(q_mix(images, videos), "a post takes images or one video, never both"),
    Media.one_err(U32.is_gt(images, 4), "at most four images per post")
  )

def Media.video_rule(videos: U32) -> Maybe<&2, D.Error>:
  Media.one_err(U32.is_gt(videos, 1), "at most one video per post")

# The first complaint wins, so the error names the rule that was actually broken
# rather than whatever a later path happened to violate.
def Media.verdict(images: U32,+videos: U32, err: Maybe<&2, D.Error>) -> Maybe<&2, D.Error>:
  Err.first(err, Err.first(Media.image_rule(images, videos), Media.video_rule(videos)))

def Media.scan(rest: List<&2, String>,+images: U32,+videos: U32,+err: Maybe<&2, D.Error>) -> Maybe<&2, D.Error>:
  match rest:
    case Nil{}:
      Media.verdict(images, videos, err)
    case +p <> t:
      Media.scan(t, Media.next_images(p, images), Media.next_videos(p, videos), Err.first(err, Media.supported(p)))

def Media.validate(paths: List<&2, String>) -> Maybe<&2, D.Error>:
  Media.scan(paths, 0, 0, None{})

# `--alt` is positional against `--media`, so an alt with no media under it is an
# alt that `Media.build` would drop. Dropping it is the failure this rule exists
# to prevent: the post goes out with no attachment, and nothing in the answer
# says one was asked for.
def Media.alt_rule(paths: List<&2, String>, alts: List<&2, String>) -> Maybe<&2, D.Error>:
  Media.one_err(
    Nat.is_gt(List.length(&2, String, alts), List.length(&2, String, paths)),
    "more --alt than --media, so the extra alts have nothing to describe"
  )

# The media rules in one verdict: what each path is, then whether the alts line
# up. The type complaint comes first, because an unsupported file is a bad
# attachment however the alts are ordered.
def Media.error(+paths: List<&2, String>, alts: List<&2, String>) -> Maybe<&2, D.Error>:
  Err.first(Media.validate(paths), Media.alt_rule(paths, alts))

# `--alt` is positional against `--media`: a missing alt is an empty string, so
# the lists can never shift out of step.
#
# `paths` leads the arguments on purpose: the termination checker only has to
# see one argument shrink, and it reads them left to right, so the list that is
# matched by pattern has to come first. `List.drop` would not count.
def Media.alts_for(paths: List<&2, String>,+alts: List<&2, String>,+acc: List<&2, D.Media>) -> List<&2, D.Media>:
  match paths:
    case Nil{}:
      List.reverse(&2, D.Media, acc)
    case +p <> t:
      Media.alts_for(
        t,
        List.drop(&2, String, alts, 1n),
        D.mk_media(p, Maybe.default(&2, String, List.head(&2, String, alts), SNil{}), Media.mime_for(p), Media.kind_for(p)) <> acc
      )

def Media.build(paths: List<&2, String>, alts: List<&2, String>) -> List<&2, D.Media>:
  Media.alts_for(paths, alts, Nil{})

# ── http status to error code ───────────────────────────────────────────

def ErrCode.of_status_low(ge400: Bool) -> D.ErrCode:
  match ge400:
    case True{}:
      D.ErrUpstream{}
    case False{}:
      D.ErrInternal{}

def ErrCode.of_status_at(ge500: Bool, ge400: Bool) -> D.ErrCode:
  match ge500:
    case True{}:
      D.ErrUpstream{}
    case False{}:
      ErrCode.of_status_low(ge400)

def ErrCode.of_status_more(+status: U32) -> D.ErrCode:
  ErrCode.of_status_at(U32.is_ge(status, 500), U32.is_ge(status, 400))

def ErrCode.of_status(+status: U32) -> D.ErrCode:
  match status:
    case 401:
      D.ErrAuth{}
    case 403:
      D.ErrAuth{}
    case 404:
      D.ErrNotFound{}
    case 429:
      D.ErrRateLimited{}
    case _:
      ErrCode.of_status_more(status)

# ── settings: flags, then environment, then config, then default ────────

def Cfg.order(f: List<&2, D.Item>, e: List<&2, D.Item>, r: List<&2, D.Item>,+name: String, fallback: String) -> String:
  D.Items.str(f, name, D.Items.str(e, name, D.Items.str(r, name, fallback)))

# `--media` and `--alt` are lists rather than single values, so they take the same
# flag > environment > config order as every other setting with one difference: a
# source either named one or it did not, so the first source that named either is
# the source read. Both lists come out of that one source, because their pairing is
# positional and reading one from each would shift an alt onto the wrong file.
#
# The test is on either list rather than on `--media`, so a lone `--alt` is still
# read: that is the case `Media.alt_rule` exists to refuse, and a source that
# looked empty would hand it an empty list and let it through.
def Cfg.no_content_named(+items: List<&2, D.Item>) -> Bool:
  Bool.and(
    List.is_empty(&2, String, D.Items.media(items, Nil{})),
    List.is_empty(&2, String, D.Items.alts(items, Nil{}))
  )

def Cfg.media_src_after_env(none: Bool, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> List<&2, D.Item>:
  match none:
    case True{}:
      rc
    case False{}:
      env

def Cfg.media_src_after_items(none: Bool, +items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> List<&2, D.Item>:
  match none:
    case True{}:
      Cfg.media_src_after_env(Cfg.no_content_named(env), env, rc)
    case False{}:
      items

def Cfg.media_src(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> List<&2, D.Item>:
  Cfg.media_src_after_items(Cfg.no_content_named(items), items, env, rc)

# The gate the fold consults before it builds a post. An empty answer is the
# ordinary case: no media was named, or the media passed every rule.
def Cfg.media_error(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> Maybe<&2, D.Error>:
  Media.error(
    D.Items.media(Cfg.media_src(items, env, rc), Nil{}),
    D.Items.alts(Cfg.media_src(items, env, rc), Nil{})
  )

# `--text`, `--media` and `--alt` are content, not settings: they say what this
# one post is, not how the program should behave. A config file holding a tweet's
# text would post a stale paragraph the day someone forgot it was there, so the
# config file refuses them by name instead of quietly ignoring them.
def Cfg.content_flag(name: String) -> Bool:
  match name:
    case "--text":
      True{}
    case "--media":
      True{}
    case "--alt":
      True{}
    case _:
      False{}

def Cfg.both_set(a: String, b: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(a)), Bool.not(String.is_empty(b)))

def Cfg.key_creds(+key: String, base: String) -> D.Creds:
  match key:
    case "":
      D.Anon{}
    case _:
      D.mk_api_key(key, base)

def Cfg.session_creds_on(at: String, ct: String, both: Bool) -> D.Creds:
  match both:
    case True{}:
      D.mk_session(at, ct, "flags, environment or config file")
    case False{}:
      D.Anon{}

def Cfg.session_creds(+at: String,+ct: String) -> D.Creds:
  Cfg.session_creds_on(at, ct, Cfg.both_set(at, ct))

def Cfg.auto_creds(at: String, ct: String,+key: String, base: String) -> D.Creds:
  match key:
    case "":
      Cfg.session_creds(at, ct)
    case _:
      D.mk_api_key(key, base)

# The credential the chosen engine needs, or `Anon` when it is missing. Nothing
# is guessed silently: a missing credential becomes an `auth` error at the point
# of use, with a hint naming the setting to provide.
def Cfg.creds(engine: String,+at: String,+ct: String,+key: String,+base: String) -> D.Creds:
  match engine:
    case "sweetistics":
      Cfg.key_creds(key, base)
    case "graphql":
      Cfg.session_creds(at, ct)
    case _:
      Cfg.auto_creds(at, ct, key, base)

def Cfg.auto_name(key: String) -> String:
  match key:
    case "":
      "graphql"
    case _:
      "sweetistics"

def Cfg.engine_name(engine: String, key: String) -> String:
  match engine:
    case "sweetistics":
      "sweetistics"
    case "graphql":
      "graphql"
    case _:
      Cfg.auto_name(key)

# The one place the default page size lives: a search that says nothing gets
# this many results, and `bird help` prints the same number through it.
def Cfg.default_count() -> U32:
  10

def Cfg.count_or(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      Cfg.default_count()
    case Some{n}:
      n

def Cfg.read_count(+text: String, fallback: U32) -> U32:
  match text:
    case "":
      fallback
    case _:
      U32.clamp(Cfg.count_or(U32.read(text)), 1, 50)

# A write with nothing to say would send an empty tweet, and X's refusal would
# arrive as a confusing 400. The text may be in the verb or in the file the run
# named, so both are read here: a tweet whose only text is the file's is fine,
# and one with neither is refused before the request is built.
def Cfg.neither_set(a: String, b: String) -> Bool:
  Bool.and(String.is_empty(a), String.is_empty(b))

# A write with media and no text is a real post: X allows a media-only tweet,
# so `tweet --media shot.png` is not empty, it is wordless.
def Cfg.blank_write(+v: D.Verb, +file: String) -> Bool:
  match v:
    case D.VerbTweet{text, media}:
      Bool.and(Cfg.neither_set(text, file), List.is_empty(&2, D.Media, media))
    case D.VerbReply{target, text, media}:
      Bool.and(Cfg.neither_set(text, file), List.is_empty(&2, D.Media, media))
    case _:
      False{}

def Cfg.no_text_error(+v: D.Verb) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    D.Verb.name(v) ++ " has nothing to send",
    "give it its text, or --text-file PATH"
  )

# `--count` is read from the item list rather than threaded through the verb,
# so it counts whether it was written before or after the verb it belongs to.
#
# The `_on` form takes the environment and the config file as well, because a
# setting that can be written in a config file and then ignored is worse than one
# that is refused: `--count` and `--timeout-ms` are values rather than flags, so
# they are read here instead of being baked into the verb the moment the command
# line is parsed.
def Cfg.count_on(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>, fallback: U32) -> U32:
  Cfg.read_count(Cfg.order(items, env, rc, "--count", SNil{}), fallback)

def Cfg.count(items: List<&2, D.Item>) -> U32:
  Cfg.count_on(items, Nil{}, Nil{}, Cfg.default_count())

def Cfg.timeout_or(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      15000
    case Some{n}:
      U32.clamp(n, 1000, 120000)

def Cfg.read_timeout(text: String) -> U32:
  Cfg.timeout_or(U32.read(text))

def Cfg.timeout_on(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> U32:
  Cfg.read_timeout(Cfg.order(items, env, rc, "--timeout-ms", "15000"))

# Both numeric settings have a default, and a typo lands on the default and reads
# as success: `--count abc` would quietly be ten results, and nothing in the
# answer would say the number was ignored. That is the one failure a caller cannot
# detect, so a value that was offered and could not be read is refused.
#
# The check runs on the winning value, in the same flag > environment > config
# order the readers use, so one rule covers all three places a number can be
# written rather than three rules that can drift apart. An absent setting is left
# to the default: only a value that was given and could not be read is a typo.
def Cfg.number_wants(name: String) -> String:
  match name:
    case "--count":
      "give it a whole number, 1..50"
    case _:
      "give it milliseconds, 1000..120000"

# `blank` is the text being empty, which means no source named the setting at
# all: there is nothing to read, so the default stands and the typo rule does not
# apply. Only a value that was actually offered is checked.
def Cfg.number_rule(blank: Bool, ok: Bool, +name: String, text: String) -> Maybe<&2, D.Error>:
  match blank ok:
    case True{} _:
      None{}
    case False{} True{}:
      None{}
    case False{} False{}:
      Some{D.err_hint(D.ErrUsage{}, name ++ " is not a number: " ++ text, Cfg.number_wants(name))}

def Cfg.reads_on(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{n}:
      True{}
    case None{}:
      False{}

def Cfg.numeric_ok(text: String) -> Bool:
  Cfg.reads_on(U32.read(text))

def Cfg.number_check(+name: String, +text: String) -> Maybe<&2, D.Error>:
  Cfg.number_rule(String.is_empty(text), Cfg.numeric_ok(text), name, text)

def Cfg.number_error(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> Maybe<&2, D.Error>:
  Err.first(
    Cfg.number_check("--count", Cfg.order(items, env, rc, "--count", SNil{})),
    Cfg.number_check("--timeout-ms", Cfg.order(items, env, rc, "--timeout-ms", SNil{}))
  )

def Verb.keep(+it: D.Item, acc: D.Verb) -> D.Verb:
  match it:
    case D.ItemVerb{verb}:
      verb
    case _:
      acc

def Cfg.verb_scan(items: List<&2, D.Item>,+acc: D.Verb) -> D.Verb:
  match items:
    case Nil{}:
      acc
    case +it <> rest:
      Cfg.verb_scan(rest, Verb.keep(it, acc))

def Cfg.verb(items: List<&2, D.Item>, fallback: D.Verb) -> D.Verb:
  Cfg.verb_scan(items, fallback)

# `--text` lands on whichever verb was given, so `bird tweet --text hi` and
# `bird tweet hi` agree.
def Verb.attach_text(+v: D.Verb,+text: String,+media: List<&2, D.Media>) -> D.Verb:
  match v:
    case D.VerbTweet{text_old, media_old}:
      D.VerbTweet{text, media}
    case D.VerbReply{target, text_old, media_old}:
      D.VerbReply{target, text, media}
    case _:
      v

def Cfg.trim_nonempty(+u: String, slash: Bool) -> String:
  match slash:
    case True{}:
      String.take(u, (String.length(u) - 1n : Nat))
    case False{}:
      u

def Cfg.trim_slash(+u: String) -> String:
  Cfg.trim_nonempty(u, String.ends_with(u, "/"))

def Cfg.base_url(+u: String) -> String:
  match u:
    case "":
      "https://sweetistics.com"
    case _:
      Cfg.trim_slash(u)

def Cfg.attach(v: D.Verb,+items: List<&2, D.Item>) -> D.Verb:
  Verb.attach_text(
    v,
    D.Items.str(items, "--text", SNil{}),
    Media.build(D.Items.media(items, Nil{}), D.Items.alts(items, Nil{}))
  )

def Cfg.verb_with_media(+items: List<&2, D.Item>) -> D.Verb:
  Cfg.attach(Cfg.verb(items, D.VerbHelp{}), items)

# ── a config file as items ──────────────────────────────────────────────
#
# Its keys are flag names, so a setting is spelled the same way in a file as on
# the command line, and its values are the setting's text: a string, a number, a
# bool, or a nested value rendered as JSON for a setting that takes JSON (the
# feature flags blob is the one that does).
def Cfg.bool_words(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def Cfg.rc_text(+j: J.Json) -> String:
  match j:
    case J.JsonStr{value}:
      value
    case J.JsonNum{text}:
      text
    case J.JsonBool{value}:
      Cfg.bool_words(value)
    case _:
      J.show(j)

def Cfg.rc_item(+f: J.JField) -> D.Item:
  match f:
    case J.JField{key, value}:
      D.Item.flag(key, Cfg.rc_text(value))

def Cfg.rc_walk(+fs: List<&2, J.JField>, acc: List<&2, D.Item>) -> List<&2, D.Item>:
  match fs:
    case Nil{}:
      List.reverse(&2, D.Item, acc)
    case +f <> rest:
      Cfg.rc_walk(rest, Cfg.rc_item(f) <> acc)

def Cfg.rc_items(fs: List<&2, J.JField>) -> List<&2, D.Item>:
  Cfg.rc_walk(fs, Nil{})

# An empty JSON object: a well-formed `features` value that names no flags. X
# answers with the flags it wanted, and that answer reaches the operator intact,
# so the flag can be filled in from a config file without guessing here.
def Cfg.default_features() -> String:
  "{}"

# X's operation names, one per verb the graphql engine sends. They are defaults
# rather than constants in the request builders, so `bird schema` can print them
# and the run can override them without the two drifting apart.
def Cfg.default_op_create_tweet() -> String:
  "CreateTweet"

def Cfg.default_op_tweet_detail() -> String:
  "TweetDetail"

def Cfg.default_op_search() -> String:
  "SearchTimeline"

def Cfg.default_op_viewer() -> String:
  "Viewer"

# Where X's media service lives. It is a setting for the same reason the query
# ids are: it belongs to X's deployment, not ours, and it has already moved
# hosts once. The base is the `/1.1/media` prefix, so both endpoints the uploader
# uses (an upload and an alt-text call) come from one value.
def Cfg.default_media_base() -> String:
  "https://upload.twitter.com/1.1/media"

# The graphql endpoint and the mentions timeline are settings for the same reason:
# both belong to X's deployment. Keeping them settable is also what lets an
# end-to-end run point the whole write path at a stand-in rather than at X.
def Cfg.default_gql_base() -> String:
  "https://x.com/i/api/graphql"

def Cfg.default_mentions_url() -> String:
  "https://x.com/i/api/2/notifications/mentions.json"

# ── the settings `login` reads ──────────────────────────────────────────
#
# `login` is the one verb that reads the world for its own settings rather than
# being handed them, so the handful it needs are gathered here through the same
# flag > environment > config > default chain as everything else. Two of them are
# not settings a person writes: `--home` and `--tmpdir` are the interpreter's own
# environment passed through as items, which is how a default path can depend on
# where the operator's home is without the pure fold ever reading the world.
def Cfg.default_web_home() -> String:
  "https://x.com/home"

def Cfg.default_settings_name() -> String:
  "/.config/bird/settings.json"

def Cfg.default_settings_path(home: String) -> String:
  match home:
    case "":
      SNil{}
    case _:
      home ++ Cfg.default_settings_name()

def Cfg.chrome_profile_db() -> String:
  "/Library/Application Support/Google/Chrome/Default/Cookies"

# Only Chrome has a path this program can guess. Firefox keeps a profile per
# installation with a name that is not knowable from here, so a firefox run says
# which database to read instead of picking one and reading the wrong session.
def Cfg.default_cookie_db(source: String, home: String) -> String:
  match source:
    case "chrome":
      home ++ Cfg.chrome_profile_db()
    case _:
      SNil{}

def Cfg.tmp_dir_or(dir: String) -> String:
  match dir:
    case "":
      "/tmp"
    case _:
      dir

# Where the client bundle is served from, and the base of the operation ids the
# browser reads. A setting rather than a constant, so a run can be pointed at a
# stand-in -- which is what lets the login flow be checked end to end over a socket
# instead of only against a recorded document.
def Cfg.default_bundle_base() -> String:
  "https://abs.twimg.com/responsive-web/client-web/"

def Cfg.bundle_base_on(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> String:
  Cfg.order(items, env, rc, "--bundle-base", Cfg.default_bundle_base())

# The guessed database depends on which source won, so it is worked out from the
# winning source rather than from the flag that happened to name it.
def Cfg.order_cookie_db(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> String:
  Cfg.default_cookie_db(
    Cfg.order(items, env, rc, "--cookie-source", SNil{}),
    Cfg.order(items, env, rc, "--home", SNil{})
  )

def Cfg.login_cfg_on(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> D.LoginCfg:
  D.mk_login_cfg(
    Cfg.order(items, env, rc, "--cookie-source", SNil{}),
    Cfg.order(items, env, rc, "--cookie-db", Cfg.order_cookie_db(items, env, rc)),
    Cfg.order(items, env, rc, "--chrome-key", SNil{}),
    Cfg.order(items, env, rc, "--web-home", Cfg.default_web_home()),
    Cfg.bundle_base_on(items, env, rc),
    Cfg.order(items, env, rc, "--settings-path", Cfg.default_settings_path(Cfg.order(items, env, rc, "--home", SNil{}))),
    Cfg.tmp_dir_or(Cfg.order(items, env, rc, "--tmpdir", SNil{}))
  )

# ── what `login` refuses before it runs anything ────────────────────────

def Cfg.login_source_known(+s: String) -> Bool:
  match s:
    case "chrome":
      True{}
    case "firefox":
      True{}
    case _:
      False{}

def Cfg.source_verdict(known: Bool, +s: String) -> Maybe<&2, D.Error>:
  match known:
    case True{}:
      None{}
    case False{}:
      Some{D.err_hint(
        D.ErrUsage{},
        "--cookie-source is not a browser this build reads: " ++ s,
        "chrome or firefox"
      )}

def Cfg.source_gate(blank: Bool, known: Bool, +s: String) -> Maybe<&2, D.Error>:
  match blank:
    case True{}:
      None{}
    case False{}:
      Cfg.source_verdict(known, s)

def Cfg.cookie_source_error(+s: String) -> Maybe<&2, D.Error>:
  Cfg.source_gate(String.is_empty(s), Cfg.login_source_known(s), s)

# A source that was named needs a database, and a firefox one needs it named by
# hand: a profile directory is not guessable from here, and reading the wrong
# profile's session is worse than not reading one.
def Cfg.db_wanted(blank: Bool, +source: String) -> Maybe<&2, D.Error>:
  match blank:
    case True{}:
      Some{D.err_hint(
        D.ErrUsage{},
        "--cookie-source " ++ source ++ " needs a cookie database",
        "--cookie-db PATH, which for firefox is <profile>/cookies.sqlite"
      )}
    case False{}:
      None{}

def Cfg.db_gate(blank_source: Bool, blank_db: Bool, +source: String) -> Maybe<&2, D.Error>:
  match blank_source:
    case True{}:
      None{}
    case False{}:
      Cfg.db_wanted(blank_db, source)

def Cfg.cookie_db_error(+source: String, +db: String) -> Maybe<&2, D.Error>:
  Cfg.db_gate(String.is_empty(source), String.is_empty(db), source)

# Where the cache lives: named if it was named, and otherwise the operator's home
# with `/.config/bird/settings.json` under it. `--home` is not a setting a person
# writes -- the interpreter passes HOME through as an item, which is how a default
# path can depend on the world without the pure fold reading it.
def Cfg.settings_path_on(+items: List<&2, D.Item>, +env: List<&2, D.Item>, +rc: List<&2, D.Item>) -> String:
  Cfg.order(
    items,
    env,
    rc,
    "--settings-path",
    Cfg.default_settings_path(Cfg.order(items, env, rc, "--home", SNil{}))
  )

# A source that was not asked for is only a problem when there is nothing to fetch
# the bundle with: `bird login` on its own refreshes the rotating settings for the
# session the flags, the environment or the cache already hold.
def Cfg.session_verdict(has_session: Bool) -> Maybe<&2, D.Error>:
  match has_session:
    case True{}:
      None{}
    case False{}:
      Some{D.err_hint(
        D.ErrUsage{},
        "login has no session to read the bundle with",
        "--cookie-source chrome|firefox, or --auth-token and --ct0"
      )}

def Cfg.session_gate(no_source: Bool, has_session: Bool) -> Maybe<&2, D.Error>:
  match no_source:
    case False{}:
      None{}
    case True{}:
      Cfg.session_verdict(has_session)

def Cfg.session_error(+source: String, +at: String, +ct0: String) -> Maybe<&2, D.Error>:
  Cfg.session_gate(String.is_empty(source), Cfg.both_set(at, ct0))

def Cfg.blank_gate(blank: Bool, +name: String, +hint: String) -> Maybe<&2, D.Error>:
  match blank:
    case True{}:
      Some{D.err_hint(D.ErrUsage{}, name ++ " is not set, and login has to write the cache somewhere", hint)}
    case False{}:
      None{}

def Cfg.settings_error(+path: String) -> Maybe<&2, D.Error>:
  Cfg.blank_gate(String.is_empty(path), "--settings-path", "HOME is not set, so the default cannot be worked out; pass one")

# The four refusals, first one wins, so the run names the thing a person would fix
# first rather than whatever the last check happened to notice.
def Cfg.login_error(+lc: D.LoginCfg) -> Maybe<&2, D.Error>:
  match lc:
    case D.LoginCfg{source, db, chrome_key, web_home, bundle_base, settings_path, tmp_dir}:
      Err.first(
        Cfg.cookie_source_error(source),
        Err.first(
          Cfg.cookie_db_error(source, db),
          Cfg.settings_error(settings_path)
        )
      )

# ── the whole resolution, once, at startup ──────────────────────────────
#
# The values a deployment has to supply -- the operation ids, the web bearer and
# X's feature flags -- go through the same flag > environment > config > default
# chain as everything else, so none of them is compiled in. An empty bearer is
# not a default: it is a missing setting, and the request builder refuses rather
# than sending a request it knows X will reject.
def Cfg.finish(+items: List<&2, D.Item>,+env: List<&2, D.Item>,+rc: List<&2, D.Item>,
  tty: Bool,
  config_path: String,+engine: String,+api_base: String
) -> D.RunCfg:
  D.mk_cfg(
    Cfg.verb_with_media(items),
    D.OutMode.from(tty, D.Items.has_flag(items, "--json"), D.Items.has_flag(env, "BIRD_JSON")),
    D.Items.has_flag(items, "--dry-run"),
    D.Engine.of(engine),
    Cfg.creds(
      engine,
      Cfg.order(items, env, rc, "--auth-token", SNil{}),
      Cfg.order(items, env, rc, "--ct0", SNil{}),
      Cfg.order(items, env, rc, "--sweetistics-api-key", SNil{}),
      api_base
    ),
    Cfg.order(items, env, rc, "--op-create-tweet", Cfg.default_op_create_tweet()),
    Cfg.order(items, env, rc, "--op-tweet-detail", Cfg.default_op_tweet_detail()),
    Cfg.order(items, env, rc, "--op-search", Cfg.default_op_search()),
    Cfg.order(items, env, rc, "--op-viewer", Cfg.default_op_viewer()),
    Cfg.order(items, env, rc, "--web-bearer", SNil{}),
    Cfg.order(items, env, rc, "--gql-features", Cfg.default_features()),
    api_base,
    Cfg.timeout_on(items, env, rc),
    Cfg.order(items, env, rc, "--media-upload-base", Cfg.default_media_base()),
    Cfg.order(items, env, rc, "--gql-base", Cfg.default_gql_base()),
    Cfg.order(items, env, rc, "--mentions-url", Cfg.default_mentions_url())
  )

def Cfg.build(+items: List<&2, D.Item>,+env: List<&2, D.Item>,+rc: List<&2, D.Item>,
  tty: Bool,
  config_path: String
) -> D.RunCfg:
  Cfg.finish(
    items,
    env,
    rc,
    tty,
    config_path,
    Cfg.engine_name(
      Cfg.order(items, env, rc, "--engine", SNil{}),
      Cfg.order(items, env, rc, "--sweetistics-api-key", SNil{})
    ),
    Cfg.base_url(Cfg.order(items, env, rc, "--sweetistics-base-url", SNil{}))
  )

def Cfg.resolve(
  items: List<&2, D.Item>,
  env: List<&2, D.Item>,
  rc: List<&2, D.Item>,
  tty: Bool,
  config_path: String
) -> D.RunCfg:
  Cfg.build(items, env, rc, tty, config_path)
