import Base
import ../src/api.bend as A
import ../src/domain.bend as D
import ../src/json.bend as J

# End-to-end check of the request builder: a verb and a configuration go in, and
# the request that would be sent comes out. The bearer, the operation ids and
# the base url are set here, which is the point of them being settings: a test
# can name them, and no constant is compiled into the program.
#
#   bend tests/api_test.bend

def ok_on(passed: Bool, +name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

# ── unpacking a plan ────────────────────────────────────────────────────

def cmd_of(+p: A.Plan) -> D.Cmd:
  match p:
    case A.PlanSend{cmd}:
      cmd
    case A.PlanStop{error}:
      D.CmdNone{}

def em(+e: D.Error) -> String:
  match e:
    case D.Error{code, message, hint}:
      message

def ec(+e: D.Error) -> String:
  match e:
    case D.Error{code, message, hint}:
      D.ErrCode.id(code)

def stopped_code(+p: A.Plan) -> String:
  match p:
    case A.PlanSend{cmd}:
      SNil{}
    case A.PlanStop{error}:
      ec(error)

def gate_code(+e: Maybe<&2, D.Error>) -> String:
  match e:
    case Some{x}:
      ec(x)
    case None{}:
      SNil{}

def gate_message(+e: Maybe<&2, D.Error>) -> String:
  match e:
    case Some{x}:
      em(x)
    case None{}:
      SNil{}

def stopped_message(+p: A.Plan) -> String:
  match p:
    case A.PlanSend{cmd}:
      SNil{}
    case A.PlanStop{error}:
      em(error)

def req_of(+c: D.Cmd) -> D.HttpReq:
  match c:
    case D.CmdHttp{id, req}:
      req
    case _:
      D.mk_http(SNil{}, SNil{}, Nil{}, SNil{}, 0)

def url_of(+r: D.HttpReq) -> String:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      url

def method_of(+r: D.HttpReq) -> String:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      method

def body_of(+r: D.HttpReq) -> String:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      body

def headers_of(+r: D.HttpReq) -> List<&2, D.Header>:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      headers

# Headers are asserted as a rendered list rather than looked up by name: a
# name lookup over a list needs a helper that calls the walker back, which is a
# forward reference, which this language does not allow. Rendering is one
# self-recursive def and `String.contains` does the rest.
def header_line(+h: D.Header, more: String) -> String:
  match h:
    case D.Header{name, value}:
      name ++ "=" ++ value ++ "\n" ++ more

def headers_text(+hs: List<&2, D.Header>) -> String:
  match hs:
    case Nil{}:
      SNil{}
    case +h <> rest:
      header_line(h, headers_text(rest))

# ── configurations built by hand, because every value here is a setting ──

def gql_cfg(verb: D.Verb, bearer: String) -> D.RunCfg:
  D.mk_cfg(
    verb,
    D.OutAgent{},
    False{},
    D.EngineGraphql{},
    D.mk_session("tok-a", "tok-c", "test"),
    "opTW",
    "opDT",
    "opSE",
    "opVW",
    bearer,
    "{\"flag\":true}",
    "https://sweet.test",
    15000,
    "https://upload.test",
    "https://x.com/i/api/graphql",
    "https://x.com/i/api/2/notifications/mentions.json"
  )

def sweet_cfg(verb: D.Verb) -> D.RunCfg:
  D.mk_cfg(
    verb,
    D.OutAgent{},
    False{},
    D.EngineSweetistics{},
    D.mk_api_key("k-1", "https://sweet.test"),
    "opTW",
    "opDT",
    "opSE",
    "opVW",
    SNil{},
    "{}",
    "https://sweet.test",
    15000,
    "https://upload.test",
    "https://x.com/i/api/graphql",
    "https://x.com/i/api/2/notifications/mentions.json"
  )

def anonymous(verb: D.Verb) -> D.RunCfg:
  D.mk_cfg(
    verb,
    D.OutAgent{},
    False{},
    D.EngineAuto{},
    D.Anon{},
    "opTW",
    "opDT",
    "opSE",
    "opVW",
    SNil{},
    "{}",
    "https://sweet.test",
    15000,
    "https://upload.test",
    "https://x.com/i/api/graphql",
    "https://x.com/i/api/2/notifications/mentions.json"
  )

def gql_req(verb: D.Verb, bearer: String) -> D.HttpReq:
  req_of(cmd_of(A.Api.plan(gql_cfg(verb, bearer), 7)))

def sweet_req(verb: D.Verb) -> D.HttpReq:
  req_of(cmd_of(A.Api.plan(sweet_cfg(verb), 7)))

def tweet(text: String) -> D.Verb:
  D.VerbTweet{text, Nil{}}

def with_media(text: String) -> D.Verb:
  D.VerbTweet{text, D.mk_media("a.jpg", SNil{}, "image/jpeg", D.MediaImage{}) <> Nil{}}

def two_media(text: String) -> D.Verb:
  D.VerbTweet{text, (
    D.mk_media("a.jpg", "the alt", "image/jpeg", D.MediaImage{}) <> (
      D.mk_media("v.mp4", SNil{}, "video/mp4", D.MediaVideo{}) <> Nil{}
    )
  )}

def video_media(text: String) -> D.Verb:
  D.VerbTweet{text, D.mk_media("v.mp4", SNil{}, "video/mp4", D.MediaVideo{}) <> Nil{}}

def parts_of(+r: D.HttpReq) -> List<&2, String>:
  match r:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      parts

def body_empty(+r: D.HttpReq) -> Bool:
  String.is_empty(body_of(r))

def media_path(+m: D.Media) -> String:
  match m:
    case D.Media{path, alt, mime, kind}:
      path

def job_tag(+j: D.MediaJob) -> String:
  match j:
    case D.JobUpload{media}:
      "upload:" ++ media_path(media)
    case D.JobAlt{text}:
      "alt:" ++ text

def job_tags_on(+js: List<&2, D.MediaJob>, +acc: List<&2, String>) -> List<&2, String>:
  match js:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +h <> rest:
      job_tags_on(rest, job_tag(h) <> acc)

def job_tags(+js: List<&2, D.MediaJob>) -> String:
  String.join(job_tags_on(js, Nil{}), ",")

def jobs_of(+verb: D.Verb) -> List<&2, D.MediaJob>:
  A.Api.media_jobs(D.Verb.media_of(verb))

def media_reply(text: String, target: String) -> D.Verb:
  D.VerbReply{target, text, D.mk_media("a.jpg", SNil{}, "image/jpeg", D.MediaImage{}) <> Nil{}}

def media_reply_body() -> String:
  body_of(req_of(cmd_of(A.Api.media_tweet(gql_cfg(media_reply("hi", "12345"), "b"), "11" <> Nil{}, 7))))

def upload_req_on(+js: List<&2, D.MediaJob>, verb: D.Verb) -> D.HttpReq:
  match js:
    case +h <> rest:
      req_of(A.Api.media_cmd(gql_cfg(verb, "b"), SNil{}, h, 4))
    case Nil{}:
      D.mk_http(SNil{}, SNil{}, Nil{}, SNil{}, 0)

def upload_req(+verb: D.Verb) -> D.HttpReq:
  upload_req_on(jobs_of(verb), verb)

def second_job(+js: List<&2, D.MediaJob>) -> D.MediaJob:
  match js:
    case Nil{}:
      D.JobAlt{SNil{}}
    case +_ <> rest:
      match rest:
        case +h <> more:
          h
        case Nil{}:
          D.JobAlt{SNil{}}

# The alt call is built with the id its upload produced, which the test supplies
# the way the fold would: the value that came back in the upload's answer.
def alt_req(+verb: D.Verb) -> D.HttpReq:
  req_of(A.Api.media_cmd(gql_cfg(verb, "b"), "11", second_job(jobs_of(verb)), 4))

def post_body(verb: D.Verb) -> String:
  body_of(req_of(cmd_of(A.Api.media_tweet(gql_cfg(verb, "b"), "11" <> ("22" <> Nil{}), 7))))

def described_media() -> String:
  J.show(A.Api.describe_media(gql_cfg(two_media("hi"), "b"), 7))

def main() -> IO(Unit):
  do IO<Unit>:
    # A tweet: the url is the setting's query id and the operation's own name.
    ok("a tweet posts to CreateTweet with the configured query id", String.eq(
      url_of(gql_req(tweet("hi"), "bearer-1")),
      "https://x.com/i/api/graphql/opTW/CreateTweet"
    ))
    ok("the method is POST", String.eq(method_of(gql_req(tweet("hi"), "bearer-1")), "POST"))
    ok("the bearer goes out as authorization", String.contains(
      headers_text(headers_of(gql_req(tweet("hi"), "bearer-1"))),
      "authorization=Bearer bearer-1"
    ))
    ok("the cookie carries both session tokens", String.contains(
      headers_text(headers_of(gql_req(tweet("hi"), "bearer-1"))),
      "cookie=auth_token=tok-a; ct0=tok-c"
    ))
    ok("ct0 repeats as the csrf token", String.contains(
      headers_text(headers_of(gql_req(tweet("hi"), "bearer-1"))),
      "x-csrf-token=tok-c"
    ))
    ok("the body carries the text", String.contains(
      body_of(gql_req(tweet("hi"), "bearer-1")),
      "\"tweet_text\":\"hi\""
    ))
    ok("the body carries the query id", String.contains(
      body_of(gql_req(tweet("hi"), "bearer-1")),
      "\"queryId\":\"opTW\""
    ))
    ok("the body carries the configured features verbatim", String.contains(
      body_of(gql_req(tweet("hi"), "bearer-1")),
      "\"features\":{\"flag\":true}"
    ))
    ok("a reply carries its target", String.contains(
      body_of(gql_req(D.VerbReply{"12345", "hi", Nil{}}, "b")),
      "\"in_reply_to_tweet_id\":\"12345\""
    ))

    # A read takes a url or an id, and the request only ever carries the id.
    ok("a read posts to TweetDetail", String.eq(
      url_of(gql_req(D.VerbRead{"12345"}, "b")),
      "https://x.com/i/api/graphql/opDT/TweetDetail"
    ))
    ok("a read pulls the id out of a url", String.contains(
      body_of(gql_req(D.VerbRead{"https://x.com/u/status/999888"}, "b")),
      "\"focalTweetId\":\"999888\""
    ))

    ok("a search posts to SearchTimeline with its query", String.contains(
      body_of(gql_req(D.VerbSearch{"rust", 25}, "b")),
      "\"rawQuery\":\"rust\""
    ))
    ok("a search carries its count", String.contains(
      body_of(gql_req(D.VerbSearch{"rust", 25}, "b")),
      "\"count\":25"
    ))

    # Sweetistics: the same operation names, at the base url, signed with the key.
    ok("a keyed run reaches the sweetistics route", String.eq(
      url_of(sweet_req(D.VerbWhoami{})),
      "https://sweet.test/opVW"
    ))
    ok("a keyed run sends its key", String.contains(
      headers_text(headers_of(sweet_req(D.VerbWhoami{}))),
      "x-api-key=k-1"
    ))
    ok("a keyed run sends no cookie", Bool.not(String.contains(
      headers_text(headers_of(sweet_req(D.VerbWhoami{}))),
      "cookie="
    )))

    # Refusals, each naming what is missing rather than sending something wrong.
    ok("no credentials is an auth error", String.eq(
      stopped_code(A.Api.plan(anonymous(D.VerbWhoami{}), 7)),
      D.ErrCode.id(D.ErrAuth{})
    ))
    ok("a session with no bearer is a usage error", String.eq(
      stopped_code(A.Api.plan(gql_cfg(D.VerbWhoami{}, SNil{}), 7)),
      D.ErrCode.id(D.ErrUsage{})
    ))
    ok("and it names the flag to set", String.contains(
      stopped_message(A.Api.plan(gql_cfg(D.VerbWhoami{}, SNil{}), 7)),
      "bearer"
    ))
    # Media: the plain builders refuse attachments rather than dropping them,
    # because a post that quietly loses a file is worse than one that failed.
    ok("an attachment reaching the plain builder is refused", String.eq(
      stopped_code(A.Api.plan(gql_cfg(with_media("hi"), "b"), 7)),
      D.ErrCode.id(D.ErrInternal{})
    ))

    # The queue: one upload per file, and an alt call after the upload it
    # describes. A file with no alt contributes one step.
    ok("the queue is upload, alt, upload", String.eq(
      job_tags(jobs_of(two_media("hi"))),
      "upload:a.jpg,alt:the alt,upload:v.mp4"
    ))

    # The upload itself: multipart, no JSON body, at the upload endpoint. curl
    # sets the content type for a multipart form, so no JSON header is sent.
    ok("an upload posts multipart to the upload endpoint", String.eq(
      url_of(upload_req(with_media("hi"))),
      "https://upload.test/upload.json"
    ))
    ok("...with the file as a form part", String.contains(
      String.join(parts_of(upload_req(with_media("hi"))), "|"),
      "media=@a.jpg"
    ))
    ok("...and no JSON body", body_empty(upload_req(with_media("hi"))))
    ok("...and no content-type header, because curl sets it", Bool.not(String.contains(
      headers_text(headers_of(upload_req(with_media("hi")))),
      "content-type"
    )))
    ok("a video declares its media category", String.contains(
      String.join(parts_of(upload_req(video_media("hi"))), "|"),
      "media_category=tweet_video"
    ))

    # The alt call names the id under it and is a JSON request like any other.
    ok("an alt call posts to the metadata endpoint", String.eq(
      url_of(alt_req(two_media("hi"))),
      "https://upload.test/metadata/create.json"
    ))
    ok("...naming the id its upload produced", String.contains(
      body_of(alt_req(two_media("hi"))),
      "\"media_id\":\"11\""
    ))
    ok("...and the alt text", String.contains(
      body_of(alt_req(two_media("hi"))),
      "the alt"
    ))

    # The post itself, once every upload has answered.
    ok("the post carries every collected id", String.contains(
      post_body(with_media("hi")),
      "\"media_id\":\"11\""
    ))
    ok("...including the second one", String.contains(
      post_body(with_media("hi")),
      "\"media_id\":\"22\""
    ))
    ok("...and still carries the text", String.contains(
      post_body(with_media("hi")),
      "\"tweet_text\":\"hi\""
    ))
    ok("...and the post is the create operation", String.contains(
      url_of(req_of(cmd_of(A.Api.media_tweet(gql_cfg(with_media("hi"), "b"), "11" <> Nil{}, 7)))),
      "/CreateTweet"
    ))
    # A reply with media carries both: the target and the attachments.
    ok("a media reply carries its target", String.contains(
      media_reply_body(),
      "\"in_reply_to_tweet_id\":\"12345\""
    ))
    ok("...and the collected ids", String.contains(
      media_reply_body(),
      "\"media_id\":\"11\""
    ))

    # The dry run of a media write shows the queue and says where the ids come
    # from, rather than pretending the write is one request.
    ok("a dry-run media plan says it is a media plan", String.contains(
      described_media(),
      "media-plan"
    ))
    ok("...lists the upload step", String.contains(described_media(), "upload.json"))
    ok("...and marks the ids that come from the answers", String.contains(
      described_media(),
      "<from-upload>"
    ))

    # The alt call names the id the upload produced, which is why it can only run
    # after that upload answered.
    ok("an api key cannot upload", String.eq(
      gate_code(A.Api.media_gate_cfg(sweet_cfg(with_media("hi")))),
      D.ErrCode.id(D.ErrAuth{})
    ))
    ok("...and the refusal says a session is what it needs", String.contains(
      gate_message(A.Api.media_gate_cfg(sweet_cfg(with_media("hi")))),
      "session"
    ))
    ok("an anonymous run cannot upload", String.eq(
      gate_code(A.Api.media_gate_cfg(anonymous(with_media("hi")))),
      D.ErrCode.id(D.ErrAuth{})
    ))
    ok("a session with no client bearer cannot upload", String.eq(
      gate_code(A.Api.media_gate_cfg(gql_cfg(with_media("hi"), SNil{}))),
      D.ErrCode.id(D.ErrUsage{})
    ))

    # Mentions is a REST read, not an operation: GET, no body, count in the url.
    ok("mentions is a GET", String.eq(
      method_of(gql_req(D.VerbMentions{5}, "b")),
      "GET"
    ))
    ok("...at X's notifications path", String.eq(
      url_of(gql_req(D.VerbMentions{5}, "b")),
      "https://x.com/i/api/2/notifications/mentions.json?count=5"
    ))
    ok("...with no body", body_empty(gql_req(D.VerbMentions{5}, "b")))
    ok("...and no content-type, because it has no body to describe", Bool.not(String.contains(
      headers_text(headers_of(gql_req(D.VerbMentions{5}, "b"))),
      "content-type"
    )))
    ok("mentions under an api key is refused", String.eq(
      stopped_code(A.Api.plan(sweet_cfg(D.VerbMentions{5}), 7)),
      D.ErrCode.id(D.ErrAuth{})
    ))

    # A verb with no request at all stops here instead of building one.
    ok("a local verb builds no request", String.eq(
      stopped_code(A.Api.plan(gql_cfg(D.VerbCheck{}, "b"), 7)),
      D.ErrCode.id(D.ErrInternal{})
    ))
