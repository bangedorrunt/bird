import Base
import ./domain.bend as D
import ./json.bend as J
import ./http.bend as H
import ./policy.bend as P

# The request each verb sends, built from the settings the run resolved. Pure: a
# verb and a configuration in, a command out. Whether the command runs is the
# interpreter's business, which is what makes `--dry-run` free and every shape
# below testable without a network.
#
# Nothing here is compiled in. The operation ids, the client bearer and X's
# feature flags are all settings, because all three rotate on X's side; a
# missing one is an error that names the flag rather than a request built from a
# guessed constant.
#
# ponytail: `--gql-features` is spliced into the body as raw JSON, so a typo in
# it goes to X and comes back as X's own 400, surfaced verbatim by
# `Http.status_error`. Parsing it here would catch the typo a round trip earlier
# at the cost of threading a Maybe through every builder.

type Plan is Data:
  PlanSend{
    cmd: D.Cmd,
  }
  PlanStop{
    error: D.Error,
  }

# The settings a request needs, gathered once so no builder takes eleven
# arguments.
type Wire is Data:
  Wire{
    bearer: String,
    features: String,
    api_base: String,
    op_tweet: String,
    op_detail: String,
    op_search: String,
    op_bookmarks: String,
    op_viewer: String,
    timeout_ms: U32,
    media_upload_base: String,
    gql_base: String,
    mentions_url: String,
  }

# ── the errors a plan can carry ─────────────────────────────────────────

def Api.no_credentials() -> D.Error:
  D.err_hint(
    D.ErrAuth{},
    "no credentials, so there is nothing to sign in with",
    "set --auth-token and --ct0, or --sweetistics-api-key"
  )

def Api.no_bearer() -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "the graphql engine needs a client bearer",
    "set --web-bearer (or BIRD_WEB_BEARER): it identifies the client, not you"
  )

# Both of these endpoints belong to X's web service, which speaks to a session:
# an API key names a different backend and cannot sign for them.
def Api.media_needs_session() -> D.Error:
  D.err_hint(
    D.ErrAuth{},
    "uploading media uses X's own upload endpoint: it needs a session, not an API key",
    "run with --auth-token and --ct0, or post the text alone"
  )

def Api.mentions_needs_session() -> D.Error:
  D.err_hint(
    D.ErrAuth{},
    "mentions is X's own notifications endpoint: it needs a session, not an API key",
    "run with --auth-token and --ct0"
  )

# The media flow is routed before the plain builders, so a plain builder that
# meets attachments means the routing is wrong. An internal error is the loud
# answer; the alternative is a post that quietly drops them.
def Api.media_internal() -> D.Error:
  D.err(D.ErrInternal{}, "internal: a media write reached the plain request builder")

def Api.no_request(v: D.Verb) -> D.Error:
  D.err_hint(
    D.ErrInternal{},
    "no request is defined for this verb",
    D.Verb.name(v)
  )

# ── headers ─────────────────────────────────────────────────────────────

def Api.cookie(at: String, +ct0: String) -> String:
  "auth_token=" ++ at ++ "; ct0=" ++ ct0

# The session is the authority: the bearer only names the client, and the cookie
# carries the account. `x-csrf-token` repeats the ct0 cookie, which X requires on
# a write.
def Api.session_headers(+bearer: String, +ct0: String, at: String) -> List<&2, D.Header>:
  D.hdr("authorization", "Bearer " ++ bearer) <> (
    D.hdr("x-csrf-token", ct0) <> (
      D.hdr("cookie", Api.cookie(at, ct0)) <> (
        D.hdr("content-type", "application/json") <> (
          D.hdr("x-twitter-active-user", "yes") <> (
            D.hdr("x-twitter-auth-type", "OAuth2Session") <> Nil{})))))

def Api.key_headers(+key: String) -> List<&2, D.Header>:
  D.hdr("x-api-key", key) <> (D.hdr("content-type", "application/json") <> Nil{})

# The session headers without a content type. Two requests carry no JSON body:
# the upload, which is multipart and whose boundary curl sets itself, and the
# mentions read, which is a GET. Claiming a JSON body on either is a lie the
# server is free to act on.
def Api.upload_headers(+bearer: String, +ct0: String, at: String) -> List<&2, D.Header>:
  D.hdr("authorization", "Bearer " ++ bearer) <> (
    D.hdr("x-csrf-token", ct0) <> (
      D.hdr("cookie", Api.cookie(at, ct0)) <> (
        D.hdr("x-twitter-active-user", "yes") <> (
          D.hdr("x-twitter-auth-type", "OAuth2Session") <> Nil{}))))

# ── urls ────────────────────────────────────────────────────────────────

# `<base>/<query id>/<operation name>`: both the base and the query id are
# settings, and the name is fixed by the operation, which is what makes a
# rotating id readable in a log.
def Api.gql_url(base: String, op_id: String, op_name: String) -> String:
  base ++ "/" ++ op_id ++ "/" ++ op_name

# The mentions timeline is not GraphQL: X serves it from a versioned REST path,
# and `count` is the only variable it needs. The url is a setting like the rest of
# X's endpoints, so an end-to-end run can point it at a stand-in.
def Api.mentions_url_at(base: String, count: U32) -> String:
  base ++ "?count=" ++ U32.show(count)

# Sweetistics is reached at `<base>/<operation>`, so the operation ids are its
# routes too and one setting names the operation for both engines. `api_base` is
# already trimmed of its trailing slash by the settings policy.
def Api.sweet_url(base: String, +op_id: String) -> String:
  base ++ "/" ++ op_id

# ── bodies ──────────────────────────────────────────────────────────────

def Api.empty_obj() -> J.Json:
  J.obj_of(Nil{})

# A target may be a bare id or a whole url; the policy decides, and the request
# never carries whatever the user pasted.
def Api.focal(+target: String) -> J.Json:
  J.obj_of(J.pairs1(J.pair("focalTweetId", J.of_str(P.TweetId.of(target)))))

# X validates the variables before it runs anything, and `TweetDetail` wants
# three of them beside the id: without them the answer is a 422 whose body names
# the first one missing. These were not guessed -- X named them, one round trip
# at a time, until the request was accepted: `includePromotedContent`,
# `withBirdwatchNotes`, `withVoice`. The last two ask for the fields the web
# client shows, so sending them is what a working read costs.
#
# Only the graphql engine takes them. Sweeteristics reads the same id and has no
# opinion about X's field toggles, so it keeps the minimal shape above.
def Api.gql_focal(+target: String) -> J.Json:
  J.obj_of(J.pairs4(
    J.pair("focalTweetId", J.of_str(P.TweetId.of(target))),
    J.pair("includePromotedContent", J.of_bool(False{})),
    J.pair("withBirdwatchNotes", J.of_bool(False{})),
    J.pair("withVoice", J.of_bool(False{}))
  ))

def Api.search_vars(query: String, count: U32) -> J.Json:
  J.obj_of(J.pairs4(
    J.pair("rawQuery", J.of_str(query)),
    J.pair("count", J.of_u32(count)),
    J.pair("query_source", J.of_str("typed_query")),
    J.pair("product", J.of_str("Latest"))
  ))

# X's bookmark timeline takes the web client's own timeline variables. The count,
# the promoted-content switch and the launch context are what its request
# carries, and X validates variables before it runs anything; twitter-cli sends
# exactly these three beside the count, and a live run is what keeps this list
# honest.
#
# `count` is a PAGE size on X's side, not a total, and the page it answers with is
# X's own: measured 2026-10-12, an ask of 60 came back as 60, and asks of 100 and of
# 200 both came back as 97..100, so the page caps near a hundred whatever is asked.
# A second page is therefore this same request with `cursor` added -- absent rather
# than empty on the first page, since an empty token is not the request that has no
# token -- and the same measurement is what showed the pages do not overlap.
def Api.cursor_var(blank: Bool, +cursor: String) -> List<&2, J.JField>:
  match blank:
    case True{}:
      Nil{}
    case False{}:
      J.pair("cursor", J.of_str(cursor)) <> Nil{}

def Api.bookmarks_vars(count: U32, +cursor: String) -> J.Json:
  J.obj_of(List.append(&2, J.JField,
    Api.cursor_var(String.is_empty(cursor), cursor),
    J.pairs4(
      J.pair("count", J.of_u32(count)),
      J.pair("includePromotedContent", J.of_bool(False{})),
      J.pair("latestControlAvailable", J.of_bool(True{})),
      J.pair("requestContext", J.of_str("launch"))
    )
  ))

def Api.tweet_vars(+text: String) -> J.Json:
  J.obj_of(J.pairs2(
    J.pair("tweet_text", J.of_str(text)),
    J.pair("dark_request", J.of_bool(False{}))
  ))

def Api.reply_vars(+text: String, +target: String) -> J.Json:
  J.obj_of(J.pairs2(
    J.pair("tweet_text", J.of_str(text)),
    J.pair("reply", J.obj_of(J.pairs1(
      J.pair("in_reply_to_tweet_id", J.of_str(P.TweetId.of(target)))
    )))
  ))

# ── the media variables ─────────────────────────────────────────────────
#
# X takes attachments under a `media` member, with one entity per uploaded id
# and the sensitivity flag beside them, which is the shape the web client itself
# builds. The ids arrive after the uploads, so these builders are only reachable
# once the upload queue is empty.

def Api.entity_json(media_id: String) -> J.Json:
  J.obj_of(J.pairs2(
    J.pair("media_id", J.of_str(media_id)),
    J.pair("tagged_users", J.arr_of(Nil{}))
  ))

def Api.entities_from(+ids: List<&2, String>, acc: List<&2, J.Json>) -> J.Json:
  match ids:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Api.entities_from(rest, Api.entity_json(h) <> acc)

def Api.media_obj(+ids: List<&2, String>) -> J.Json:
  J.obj_of(J.pairs2(
    J.pair("media_entities", Api.entities_from(ids, Nil{})),
    J.pair("possibly_sensitive", J.of_bool(False{}))
  ))

def Api.tweet_vars_media(+text: String, +ids: List<&2, String>) -> J.Json:
  J.obj_of(J.pairs3(
    J.pair("tweet_text", J.of_str(text)),
    J.pair("dark_request", J.of_bool(False{})),
    J.pair("media", Api.media_obj(ids))
  ))

def Api.reply_vars_media(+text: String, +target: String, +ids: List<&2, String>) -> J.Json:
  J.obj_of(J.pairs3(
    J.pair("tweet_text", J.of_str(text)),
    J.pair("reply", J.obj_of(J.pairs1(
      J.pair("in_reply_to_tweet_id", J.of_str(P.TweetId.of(target)))
    ))),
    J.pair("media", Api.media_obj(ids))
  ))

# The toggles ride as a body member of their own, and an empty string is how a
# request says it has none. Only the detail reads ask for the article body; every
# other verb's body is byte-identical to before, which is what keeps this a
# setting-shaped add rather than a rewrite of the request shape.
def Api.toggles_empty(empty: Bool, +toggles: String) -> String:
  match empty:
    case True{}:
      SNil{}
    case False{}:
      ",\"fieldToggles\":" ++ toggles

def Api.toggles_part(+toggles: String) -> String:
  Api.toggles_empty(String.is_empty(toggles), toggles)

# X's own toggle names: the web client sends them with a detail read so the
# answer carries an article's `content_state` rather than its stub. They rotate
# the way the operation ids do, so they live here beside the request builder
# rather than in a config file nobody has a value for.
def Api.tweet_toggles() -> String:
  "{\"withArticleRichContentState\":true,\"withArticlePlainText\":true}"

# The toggles are not enough on their own. With `--gql-features` left at its
# default a live detail read answers the article's t.co stub -- `text` is the
# link, `lang` is `zxx`, and there is no `article` object at all -- because X
# gates the body on these feature flags. A blob copied from X's web client
# already carries them, so this stands in only while the setting holds its
# default empty object; a blob the operator pasted wins. Live-checked
# 2026-10-11: with these flags `read 2030904887186514336` answers the article's
# title and 10 KB body; without them, the stub.
def Api.article_features() -> String:
  "{\"longform_notetweets_consumption_enabled\":true,\"responsive_web_twitter_article_tweet_consumption_enabled\":true,\"longform_notetweets_rich_text_read_enabled\":true,\"longform_notetweets_inline_media_enabled\":true,\"articles_preview_enabled\":true}"

# A detail read asks for the article body, so it needs the article flags; every
# other verb's body stays byte-identical to before.
# Two defs because a match may only scrutinize a parameter, never a comparison.
def Api.features_or_article(is_default: Bool, +features: String) -> String:
  match is_default:
    case True{}:
      Api.article_features()
    case False{}:
      features

def Api.detail_features(+features: String) -> String:
  Api.features_or_article(String.eq(features, P.Cfg.default_features()), features)

# Only what this build can supply: X's own `features` and any per-operation
# extras are the caller's business, and its answer names whichever it wanted.
def Api.body_at(+op_id: String, variables: J.Json, +features: String, +toggles: String) -> String:
  "{\"variables\":" ++ J.show(variables)
  ++ ",\"queryId\":\"" ++ op_id ++ "\""
  ++ ",\"features\":" ++ features
  ++ Api.toggles_part(toggles) ++ "}"

def Api.body(+op_id: String, variables: J.Json, +features: String) -> String:
  Api.body_at(op_id, variables, features, SNil{})

def Api.body_toggles(+op_id: String, variables: J.Json, +features: String) -> String:
  Api.body_at(op_id, variables, Api.detail_features(features), Api.tweet_toggles())

def Api.raw_vars(variables: J.Json) -> String:
  J.show(variables)

# Every GraphQL operation goes out as POST. `send_at` exists for the reads that
# are not operations: X's mentions timeline takes GET, and nothing else does.
def Api.method() -> String:
  "POST"

def Api.send_at(method: String, id: U32, url: String, headers: List<&2, D.Header>, body: String, timeout_ms: U32) -> Plan:
  PlanSend{D.Cmd.http(id, D.mk_http(method, url, headers, body, timeout_ms))}

def Api.send(id: U32, url: String, headers: List<&2, D.Header>, body: String, timeout_ms: U32) -> Plan:
  Api.send_at(Api.method(), id, url, headers, body, timeout_ms)

def Api.send_get(id: U32, url: String, headers: List<&2, D.Header>, timeout_ms: U32) -> Plan:
  Api.send_at("GET", id, url, headers, SNil{}, timeout_ms)

# ── media ───────────────────────────────────────────────────────────────
#
# A media write is a queue of requests. Every file is uploaded first, and an alt
# text is a request of its own after the upload that produced the id it
# describes. The fold runs the queue head by head and only then builds the post.

# The queue, in order: for each file an upload, then (when it has alt text) its
# alt call. Built reversed and flipped once at the end.
def Api.jobs_push(+m: D.Media, +acc: List<&2, D.MediaJob>) -> List<&2, D.MediaJob>:
  match m:
    case D.Media{path, +alt, mime, kind}:
      match alt:
        case "":
          D.JobUpload{D.mk_media(path, alt, mime, kind)} <> acc
        case _:
          D.JobAlt{alt} <> (D.JobUpload{D.mk_media(path, alt, mime, kind)} <> acc)

def Api.media_jobs_walk(+ms: List<&2, D.Media>, +acc: List<&2, D.MediaJob>) -> List<&2, D.MediaJob>:
  match ms:
    case Nil{}:
      List.reverse(&2, D.MediaJob, acc)
    case +m <> rest:
      Api.media_jobs_walk(rest, Api.jobs_push(m, acc))

def Api.media_jobs(media: List<&2, D.Media>) -> List<&2, D.MediaJob>:
  Api.media_jobs_walk(media, Nil{})

# Both endpoints belong to the one media service the setting names.
def Api.upload_url(base: String) -> String:
  base ++ "/upload.json"

def Api.alt_url(base: String) -> String:
  base ++ "/metadata/create.json"

# A video is declared as such; an image needs no category. One-shot uploads are
# all this transport asks for, so a video X insists on chunking comes back as
# X's own refusal rather than a silent half-upload.
def Api.media_category(kind: D.MediaKind) -> List<&2, String>:
  match kind:
    case D.MediaVideo{}:
      "media_category=tweet_video" <> Nil{}
    case D.MediaImage{}:
      Nil{}

def Api.upload_cmd(id: U32, +m: D.Media, at: String, ct0: String, +bearer: String, base: String, timeout_ms: U32) -> D.Cmd:
  match m:
    case D.Media{path, alt, mime, kind}:
      D.Cmd.http(id, D.mk_http_parts(
        "POST",
        Api.upload_url(base),
        Api.upload_headers(bearer, ct0, at),
        SNil{},
        ("media=@" ++ path) <> Api.media_category(kind),
        timeout_ms
      ))

def Api.alt_body(media_id: String, +text: String) -> String:
  J.show(J.obj_of(J.pairs2(
    J.pair("media_id", J.of_str(media_id)),
    J.pair("alt_text", J.obj_of(J.pairs1(J.pair("text", J.of_str(text)))))
  )))

def Api.alt_cmd(id: U32, media_id: String, +text: String, at: String, ct0: String, +bearer: String, base: String, timeout_ms: U32) -> D.Cmd:
  D.Cmd.http(id, D.mk_http(
    "POST",
    Api.alt_url(base),
    Api.session_headers(bearer, ct0, at),
    Api.alt_body(media_id, text),
    timeout_ms
  ))

def Api.media_job_cmd(id: U32, +job: D.MediaJob, +last_id: String, at: String, ct0: String, +bearer: String, base: String, timeout_ms: U32) -> D.Cmd:
  match job:
    case D.JobUpload{media}:
      Api.upload_cmd(id, media, at, ct0, bearer, base, timeout_ms)
    case D.JobAlt{text}:
      Api.alt_cmd(id, last_id, text, at, ct0, bearer, base, timeout_ms)

# The alt job names the media under it by the id the previous upload collected,
# which is the head of `done` at the moment the job runs.
def Api.media_cmd(+cfg: D.RunCfg, +last_id: String, +job: D.MediaJob, id: U32) -> D.Cmd:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      match creds:
        case D.Session{auth_token, ct0, source}:
          Api.media_job_cmd(id, job, last_id, auth_token, ct0, web_bearer, media_upload_base, timeout_ms)
        case _:
          # The fold gates first; a command with no answer is a loud bug.
          D.CmdNone{}

# Which credential can carry a media write, and why not the others. The fold
# asks before it queues anything, so the refusal happens before a byte moves.
def Api.bearer_ok(blank: Bool) -> Maybe<&2, D.Error>:
  match blank:
    case True{}:
      Some{Api.no_bearer()}
    case False{}:
      None{}

def Api.media_gate(+creds: D.Creds, +bearer: String) -> Maybe<&2, D.Error>:
  match creds:
    case D.Anon{}:
      Some{Api.no_credentials()}
    case D.ApiKey{key, base_url}:
      Some{Api.media_needs_session()}
    case D.Session{auth_token, ct0, source}:
      Api.bearer_ok(String.is_empty(bearer))

# The gate reads the configuration itself, so the fold asks one question and does
# not have to know which two settings the answer depends on.
def Api.media_gate_cfg(+cfg: D.RunCfg) -> Maybe<&2, D.Error>:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      Api.media_gate(creds, web_bearer)

# The plain builders refuse attachments rather than dropping them; the fold is
# supposed to route media writes around them.
def Api.media_empty_on(empty: Bool, plan: Plan) -> Plan:
  match empty:
    case True{}:
      plan
    case False{}:
      PlanStop{Api.media_internal()}

def Api.media_guard(+media: List<&2, D.Media>, plan: Plan) -> Plan:
  Api.media_empty_on(List.is_empty(&2, D.Media, media), plan)

# The final post, once every upload has named its id.
def Api.session_tweet(
  +verb: D.Verb,
  at: String,
  ct0: String,
  id: U32,
  +bearer: String,
  +features: String,
  +op_tweet: String,
  timeout_ms: U32,
  +gql_base: String,
  +ids: List<&2, String>
) -> Plan:
  match verb:
    case D.VerbTweet{text, media}:
      Api.send(id, Api.gql_url(gql_base, op_tweet, "CreateTweet"), Api.session_headers(bearer, ct0, at), Api.body(op_tweet, Api.tweet_vars_media(text, ids), features), timeout_ms)
    case D.VerbReply{target, text, media}:
      Api.send(id, Api.gql_url(gql_base, op_tweet, "CreateTweet"), Api.session_headers(bearer, ct0, at), Api.body(op_tweet, Api.reply_vars_media(text, target, ids), features), timeout_ms)
    case _:
      PlanStop{Api.no_request(verb)}

def Api.media_tweet(+cfg: D.RunCfg, +ids: List<&2, String>, id: U32) -> Plan:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      match creds:
        case D.Session{auth_token, ct0, source}:
          Api.session_tweet(verb, auth_token, ct0, id, web_bearer, gql_features, op_create_tweet, timeout_ms, gql_base, ids)
        case D.ApiKey{key, base_url}:
          PlanStop{Api.media_needs_session()}
        case D.Anon{}:
          PlanStop{Api.no_credentials()}

# ── the graphql engine ──────────────────────────────────────────────────

# One case per verb, so a verb added to the domain stops here rather than
# silently building someone else's request.
def Api.gql_verb(
  +verb: D.Verb,
  at: String,
  +ct0: String,
  id: U32,
  +bearer: String,
  +features: String,
  +op_tweet: String,
  +op_detail: String,
  +op_search: String,
  +op_bookmarks: String,
  +op_viewer: String,
  timeout_ms: U32,
  gql_base: String,
  mentions_url: String
) -> Plan:
  match verb:
    case D.VerbWhoami{}:
      Api.send(id, Api.gql_url(gql_base, op_viewer, "Viewer"), Api.session_headers(bearer, ct0, at), Api.body(op_viewer, Api.empty_obj(), features), timeout_ms)
    case D.VerbRead{target}:
      Api.send(id, Api.gql_url(gql_base, op_detail, "TweetDetail"), Api.session_headers(bearer, ct0, at), Api.body_toggles(op_detail, Api.gql_focal(target), features), timeout_ms)
    case D.VerbReplies{target}:
      Api.send(id, Api.gql_url(gql_base, op_detail, "TweetDetail"), Api.session_headers(bearer, ct0, at), Api.body_toggles(op_detail, Api.gql_focal(target), features), timeout_ms)
    case D.VerbThread{target}:
      Api.send(id, Api.gql_url(gql_base, op_detail, "TweetDetail"), Api.session_headers(bearer, ct0, at), Api.body_toggles(op_detail, Api.gql_focal(target), features), timeout_ms)
    case D.VerbSearch{query, count}:
      Api.send(id, Api.gql_url(gql_base, op_search, "SearchTimeline"), Api.session_headers(bearer, ct0, at), Api.body(op_search, Api.search_vars(query, count), features), timeout_ms)
    case D.VerbBookmarks{count, cursor}:
      Api.send(id, Api.gql_url(gql_base, op_bookmarks, "Bookmarks"), Api.session_headers(bearer, ct0, at), Api.body(op_bookmarks, Api.bookmarks_vars(count, cursor), features), timeout_ms)
    case D.VerbTweet{text, media}:
      Api.media_guard(media, Api.send(id, Api.gql_url(gql_base, op_tweet, "CreateTweet"), Api.session_headers(bearer, ct0, at), Api.body(op_tweet, Api.tweet_vars(text), features), timeout_ms))
    case D.VerbReply{target, text, media}:
      Api.media_guard(media, Api.send(id, Api.gql_url(gql_base, op_tweet, "CreateTweet"), Api.session_headers(bearer, ct0, at), Api.body(op_tweet, Api.reply_vars(text, target), features), timeout_ms))
    case D.VerbMentions{count}:
      Api.send_get(id, Api.mentions_url_at(mentions_url, count), Api.upload_headers(bearer, ct0, at), timeout_ms)
    case _:
      PlanStop{Api.no_request(verb)}

def Api.session_verb(
  no_bearer: Bool,
  verb: D.Verb,
  at: String,
  ct0: String,
  id: U32,
  +bearer: String,
  features: String,
  op_tweet: String,
  op_detail: String,
  op_search: String,
  op_bookmarks: String,
  op_viewer: String,
  timeout_ms: U32,
  gql_base: String,
  mentions_url: String
) -> Plan:
  match no_bearer:
    case True{}:
      PlanStop{Api.no_bearer()}
    case False{}:
      Api.gql_verb(verb, at, ct0, id, bearer, features, op_tweet, op_detail, op_search, op_bookmarks, op_viewer, timeout_ms, gql_base, mentions_url)

def Api.session(verb: D.Verb, at: String, ct0: String, id: U32, wire: Wire) -> Plan:
  match wire:
    case Wire{+bearer, features, api_base, op_tweet, op_detail, op_search, op_bookmarks, op_viewer, timeout_ms, media_upload_base, gql_base, mentions_url}:
      Api.session_verb(String.is_empty(bearer), verb, at, ct0, id, bearer, features, op_tweet, op_detail, op_search, op_bookmarks, op_viewer, timeout_ms, gql_base, mentions_url)

# ── the sweetistics engine ──────────────────────────────────────────────

# The same variables, at the operation's route, signed with the key: the
# service names its operations the way X names them, so nothing extra has to be
# configured to reach it.
def Api.sweet_body(op_id: String, variables: J.Json) -> String:
  Api.raw_vars(variables)

def Api.sweet_verb(
  +verb: D.Verb,
  key: String,
  id: U32,
  +op_tweet: String,
  +op_detail: String,
  +op_search: String,
  +op_bookmarks: String,
  +op_viewer: String,
  timeout_ms: U32
) -> Plan:
  match verb:
    case D.VerbWhoami{}:
      Api.send(id, op_viewer, Api.key_headers(key), Api.sweet_body(op_viewer, Api.empty_obj()), timeout_ms)
    case D.VerbRead{target}:
      Api.send(id, op_detail, Api.key_headers(key), Api.sweet_body(op_detail, Api.focal(target)), timeout_ms)
    case D.VerbReplies{target}:
      Api.send(id, op_detail, Api.key_headers(key), Api.sweet_body(op_detail, Api.focal(target)), timeout_ms)
    case D.VerbThread{target}:
      Api.send(id, op_detail, Api.key_headers(key), Api.sweet_body(op_detail, Api.focal(target)), timeout_ms)
    case D.VerbSearch{query, count}:
      Api.send(id, op_search, Api.key_headers(key), Api.sweet_body(op_search, Api.search_vars(query, count)), timeout_ms)
    case D.VerbTweet{text, media}:
      Api.media_guard(media, Api.send(id, op_tweet, Api.key_headers(key), Api.sweet_body(op_tweet, Api.tweet_vars(text)), timeout_ms))
    case D.VerbReply{target, text, media}:
      Api.media_guard(media, Api.send(id, op_tweet, Api.key_headers(key), Api.sweet_body(op_tweet, Api.reply_vars(text, target)), timeout_ms))
    case D.VerbBookmarks{count, cursor}:
      Api.send(id, op_bookmarks, Api.key_headers(key), Api.sweet_body(op_bookmarks, Api.bookmarks_vars(count, cursor)), timeout_ms)
    case D.VerbMentions{count}:
      PlanStop{Api.mentions_needs_session()}
    case _:
      PlanStop{Api.no_request(verb)}

# The routes come from the same settings as X's query ids, so they are relative
# to `api_base`; the builder only sees them already joined.
def Api.sweet_plan(verb: D.Verb, key: String, +base: String, id: U32, wire: Wire) -> Plan:
  match wire:
    case Wire{bearer, features, api_base, op_tweet, op_detail, op_search, op_bookmarks, op_viewer, timeout_ms, media_upload_base, gql_base, mentions_url}:
      Api.sweet_verb(verb, key, id, Api.sweet_url(base, op_tweet), Api.sweet_url(base, op_detail), Api.sweet_url(base, op_search), Api.sweet_url(base, op_bookmarks), Api.sweet_url(base, op_viewer), timeout_ms)

# ── entry ───────────────────────────────────────────────────────────────

# The credential shape picks the engine, which is why `Creds` is a sum type: a
# session cannot be sent to Sweetistics and a key cannot be sent to X.
def Api.choose(verb: D.Verb, creds: D.Creds, id: U32, wire: Wire) -> Plan:
  match creds:
    case D.Anon{}:
      PlanStop{Api.no_credentials()}
    case D.Session{auth_token, ct0, source}:
      Api.session(verb, auth_token, ct0, id, wire)
    case D.ApiKey{key, base_url}:
      Api.sweet_plan(verb, key, base_url, id, wire)

def Api.plan(cfg: D.RunCfg, id: U32) -> Plan:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      Api.choose(verb, creds, id, Wire{web_bearer, gql_features, api_base, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, timeout_ms, media_upload_base, gql_base, mentions_url})

# ── describing a command, for `--dry-run` ───────────────────────────────
#
# The description is the same data the interpreter would act on, including the
# curl argv it would use, so a dry run can be compared with what a real run
# sends rather than trusted. `curl` is spelled out because that argv is what
# `Http` hands `Process.run`, and pasting it into a shell is how a request gets
# inspected by hand.
def Api.strings_json(+xs: List<&2, String>, acc: List<&2, J.Json>) -> J.Json:
  match xs:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Api.strings_json(rest, J.of_str(h) <> acc)

def Api.header_json(+h: D.Header) -> J.Json:
  match h:
    case D.Header{name, value}:
      J.obj_of(J.pairs2(J.pair("name", J.of_str(name)), J.pair("value", J.of_str(value))))

def Api.headers_json(+hs: List<&2, D.Header>, acc: List<&2, J.Json>) -> J.Json:
  match hs:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Api.headers_json(rest, Api.header_json(h) <> acc)

def Api.request_json(+req: D.HttpReq) -> J.Json:
  match req:
    case D.HttpReq{+method, +url, +headers, +body, +parts, +timeout_ms}:
      J.obj_of(J.pairs7(
        J.pair("method", J.of_str(method)),
        J.pair("url", J.of_str(url)),
        J.pair("headers", Api.headers_json(headers, Nil{})),
        J.pair("body", J.of_str(body)),
        J.pair("parts", Api.strings_json(parts, Nil{})),
        J.pair("timeout_ms", J.of_u32(timeout_ms)),
        J.pair("curl", Api.strings_json(H.Http.argv(D.mk_http_parts(method, url, headers, body, parts, timeout_ms)), Nil{}))
      ))

def Api.describe_other(+text: String, why: String) -> J.Json:
  J.obj_of(J.pairs2(J.pair("cmd", J.of_str(text)), J.pair("why", J.of_str(why))))

# A local program is described by its name and how many arguments it was handed,
# never by the arguments themselves: the login flow's `openssl` carries the derived
# key in its own command line, and a description that printed it would put a secret
# in a terminal's scrollback.
def Api.describe_exec(+program: String, +args: List<&2, String>) -> J.Json:
  J.obj_of(J.pairs3(
    J.pair("cmd", J.of_str("exec")),
    J.pair("program", J.of_str(program)),
    J.pair("args", J.of_u32(U32.from_nat(List.length(&2, String, args))))
  ))

def Api.describe(+cmd: D.Cmd) -> J.Json:
  match cmd:
    case D.CmdHttp{id, req}:
      Api.request_json(req)
    case D.CmdExec{id, program, args}:
      Api.describe_exec(program, args)
    case D.CmdWriteFile{id, path, text}:
      Api.describe_other("write_file", path)
    case D.CmdReadFile{id, path, why}:
      Api.describe_other("read_file", path)
    case D.CmdPrint{text}:
      Api.describe_other("print", text)
    case D.CmdPrintErr{text}:
      Api.describe_other("print_err", text)
    case D.CmdExit{code, message}:
      Api.describe_other("exit", message)
    case D.CmdNone{}:
      Api.describe_other("none", SNil{})

# ── describing a media write, for `--dry-run` ───────────────────────────
#
# A media write is several requests, and the last one cannot be built until the
# uploads have answered, so the dry run shows the queue and a final request whose
# media ids are placeholders, with a note saying so. That is more honest than
# printing one request and implying the run is one request long.

def Api.placeholder_id() -> String:
  "<from-upload>"

def Api.placeholder_ids(count: Nat, acc: List<&2, String>) -> List<&2, String>:
  match count:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+p:
      Api.placeholder_ids(p, Api.placeholder_id() <> acc)

def Api.describe_failure(+e: D.Error) -> J.Json:
  match e:
    case D.Error{code, message, hint}:
      J.obj_of(J.pairs1(J.pair("error", J.of_str(message))))

def Api.plan_request_json(+p: Plan) -> J.Json:
  match p:
    case PlanSend{cmd}:
      Api.describe(cmd)
    case PlanStop{error}:
      Api.describe_failure(error)

def Api.job_jsons(+jobs: List<&2, D.MediaJob>, +last_id: String, +at: String, +ct0: String, +bearer: String, +base: String, +timeout_ms: U32, acc: List<&2, J.Json>) -> J.Json:
  match jobs:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Api.job_jsons(rest, last_id, at, ct0, bearer, base, timeout_ms, Api.describe(Api.media_job_cmd(0, h, last_id, at, ct0, bearer, base, timeout_ms)) <> acc)

def Api.describe_media(+cfg: D.RunCfg, id: U32) -> J.Json:
  match cfg:
    case D.RunCfg{+verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, +web_bearer, +gql_features, api_base, +timeout_ms, media_upload_base, gql_base, mentions_url}:
      match creds:
        case D.Session{+auth_token, +ct0, source}:
          J.obj_of(J.pairs4(
            J.pair("kind", J.of_str("media-plan")),
            J.pair("steps", Api.job_jsons(Api.media_jobs(D.Verb.media_of(verb)), Api.placeholder_id(), auth_token, ct0, web_bearer, media_upload_base, timeout_ms, Nil{})),
            J.pair("request", Api.plan_request_json(Api.session_tweet(verb, auth_token, ct0, id, web_bearer, gql_features, op_create_tweet, timeout_ms, gql_base, Api.placeholder_ids(List.length(&2, D.Media, D.Verb.media_of(verb)), Nil{})))),
            J.pair("note", J.of_str("the media ids in the final request are filled from the upload responses"))
          ))
        case D.ApiKey{key, base_url}:
          Api.describe_failure(Api.media_needs_session())
        case D.Anon{}:
          Api.describe_failure(Api.no_credentials())
