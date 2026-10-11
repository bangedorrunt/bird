import Base
import ../src/http.bend as H
import ../src/domain.bend as D
import ../src/policy.bend as P

# End-to-end check of the transport description. A request goes in and the argv
# curl would be handed comes out, whole and compared as one string; an answer
# goes in and the status, body and error code come out. Nothing here needs a
# network, which is the point of keeping the description separate from the
# process that runs it.
#
#   bend tests/http_test.bend
#
# The argv is compared as a `|`-joined string rather than element by element:
# the whole command line is then readable in the expectation, and an argument
# added, dropped or moved shows up as a visible diff instead of a length check.

def ok_on(passed: Bool, +name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

# ── reading back what the module answered ───────────────────────────────

def status_in(+r: H.Resp) -> U32:
  match r:
    case H.Resp{http_status, body}:
      http_status

def body_in(+r: H.Resp) -> String:
  match r:
    case H.Resp{http_status, body}:
      body

def status_of(+raw: String) -> U32:
  status_in(H.Http.reply(raw))

def body_of(+raw: String) -> String:
  body_in(H.Http.reply(raw))

def error_in(+m: Maybe<&2, D.Error>) -> Bool:
  match m:
    case Some{e}:
      True{}
    case None{}:
      False{}

def err_code_id(+e: D.Error) -> String:
  match e:
    case D.Error{code, message, hint}:
      D.ErrCode.id(code)

def code_id_in(+m: Maybe<&2, D.Error>) -> String:
  match m:
    case Some{e}:
      err_code_id(e)
    case None{}:
      SNil{}

def retryable_in(+m: Maybe<&2, D.Error>) -> Bool:
  match m:
    case Some{e}:
      match e:
        case D.Error{code, message, hint}:
          D.ErrCode.retryable(code)
    case None{}:
      False{}

# ── building a request and reading its argv ─────────────────────────────

def argv_of(
  method: String,
  url: String,
  headers: List<&2, D.Header>,
  body: String,
  timeout_ms: U32
) -> String:
  String.join(H.Http.argv(D.mk_http(method, url, headers, body, timeout_ms)), "|")

def headers2(a: D.Header, b: D.Header) -> List<&2, D.Header>:
  a <> (b <> Nil{})

def parts_argv(parts: List<&2, String>) -> String:
  String.join(H.Http.argv(D.mk_http_parts("POST", "https://upload.test/upload.json", Nil{}, SNil{}, parts, 15000)), "|")

def two_parts() -> List<&2, String>:
  "media=@a.png" <> ("media_category=tweet_video" <> Nil{})

def main() -> IO(Unit):
  do IO<Unit>:
    # A read: two headers, no body, a fifteen second budget.
    ok("a GET with headers becomes one curl argv", String.eq(
      argv_of(
        "GET",
        "https://x.com/i/api/graphql/AbC/Viewer",
        headers2(D.hdr("authorization", "Bearer bearer-token"), D.hdr("cookie", "auth_token=a; ct0=b")),
        SNil{},
        15000
      ),
      "curl|-sS|https://x.com/i/api/graphql/AbC/Viewer|-X|GET"
      ++ "|-H|authorization: Bearer bearer-token"
      ++ "|-H|cookie: auth_token=a; ct0=b"
      ++ "|--max-time|15|--write-out|%{http_code}"
    ))

    # A write: the body rides along, still as one literal argument, so nothing
    # in it can be read as a shell metacharacter.
    ok("a POST carries its body as one argument", String.eq(
      argv_of(
        "POST",
        "https://x.com/i/api/graphql/AbC/CreateTweet",
        D.hdr("content-type", "application/json") <> Nil{},
        "{\"text\":\"hi; rm -rf /\"}",
        15000
      ),
      "curl|-sS|https://x.com/i/api/graphql/AbC/CreateTweet|-X|POST"
      ++ "|-H|content-type: application/json"
      ++ "|--max-time|15|-d|{\"text\":\"hi; rm -rf /\"}|--write-out|%{http_code}"
    ))

    # A multipart form: `-F` goes in front of each part, and no `-d` is added.
    # The whole argv is compared because the flag must precede its own value --
    # built the other way round, curl answers "option -F: is badly used here" and
    # the offline tests, which read the parts list rather than the argv, see
    # nothing wrong.
    ok("a multipart body becomes -F flags, flag before its value", String.eq(
      parts_argv(two_parts()),
      "curl|-sS|https://upload.test/upload.json|-X|POST"
      ++ "|--max-time|15"
      ++ "|-F|media=@a.png|-F|media_category=tweet_video"
      ++ "|--write-out|%{http_code}"
    ))
    ok("a multipart request adds no -d", Bool.not(
      String.contains(parts_argv(two_parts()), "|-d|")
    ))

    # No body means no `-d`: a GET with `-d ""` is a POST as far as curl cares.
    ok("an empty body adds no -d", Bool.not(
      String.contains(argv_of("GET", "https://x.com/x", Nil{}, SNil{}, 1000), "|-d|")
    ))

    ok("a sub-second budget becomes one second", String.eq(
      argv_of("GET", "https://x.com/x", Nil{}, SNil{}, 500),
      "curl|-sS|https://x.com/x|-X|GET|--max-time|1|--write-out|%{http_code}"
    ))
    ok("a two second budget is two", String.contains(
      argv_of("GET", "https://x.com/x", Nil{}, SNil{}, 2000),
      "|--max-time|2|"
    ))
    ok("a hundred and twenty second budget is 120", String.contains(
      argv_of("GET", "https://x.com/x", Nil{}, SNil{}, 120000),
      "|--max-time|120|"
    ))

    # The status is glued to the end of stdout, so the split is positional. A
    # body that ends in digits must not be able to shift it.
    ok("the status splits off the end", U32.is_eq(status_of("{\"count\":5}200"), 200))
    ok("the body keeps its own digits", String.eq(body_of("{\"count\":5}200"), "{\"count\":5}"))
    ok("a body with newlines survives", String.eq(body_of("a\nb\n200"), "a\nb\n"))
    ok("a big status is read whole", U32.is_eq(status_of("body429"), 429))
    ok("an empty answer has no status", U32.is_eq(status_of(SNil{}), 0))
    ok("a short answer is not mistaken for a status", U32.is_eq(status_of("ab"), 0))
    ok("a short answer keeps its body", String.eq(body_of("ab"), "ab"))

    # Errors: curl's own failure first, then the HTTP status.
    ok("curl status 0 is not an error", Bool.not(error_in(H.Http.transport_error(0))))
    ok("curl status 7 is a network error", String.eq(
      code_id_in(H.Http.transport_error(7)),
      D.ErrCode.id(D.ErrNetwork{})
    ))
    ok("curl status 28 is a network error too", String.eq(
      code_id_in(H.Http.transport_error(28)),
      D.ErrCode.id(D.ErrNetwork{})
    ))

    # A local file curl could not read is the caller's mistake, not a transport
    # failure: the same argv will fail the same way forever, so it must not be
    # reported as retryable. Only the media upload road puts a file in curl's
    # argv, and these two statuses are how curl says it could not read it.
    ok("a file curl cannot read is a usage error", String.eq(
      code_id_in(H.Http.transport_error(26)),
      D.ErrCode.id(D.ErrUsage{})
    ))
    ok("a file curl cannot open is a usage error too", String.eq(
      code_id_in(H.Http.transport_error(37)),
      D.ErrCode.id(D.ErrUsage{})
    ))
    ok("a file curl cannot read is not retryable", Bool.not(
      retryable_in(H.Http.transport_error(26))
    ))
    ok("a connection failure still is retryable", Bool.not(Bool.not(
      retryable_in(H.Http.transport_error(7))
    )))
    ok("a 200 is not an error", Bool.not(error_in(H.Http.status_error(H.Http.reply("{\"data\":{}}200")))))
    ok("a 404 is a not-found error", String.eq(
      code_id_in(H.Http.status_error(H.Http.reply("{\"errors\":[]}404"))),
      D.ErrCode.id(D.ErrNotFound{})
    ))
    ok("a 429 is a rate-limit error", String.eq(
      code_id_in(H.Http.status_error(H.Http.reply("slow down429"))),
      D.ErrCode.id(D.ErrRateLimited{})
    ))
    ok("a 500 is an upstream error", String.eq(
      code_id_in(H.Http.status_error(H.Http.reply("boom500"))),
      D.ErrCode.id(D.ErrUpstream{})
    ))
    ok("an expired session is an auth error", String.eq(
      code_id_in(H.Http.status_error(H.Http.reply("nope401"))),
      D.ErrCode.id(D.ErrAuth{})
    ))

    # A long body is cut down to something a terminal can show.
    ok("a short body is passed through", String.eq(H.Http.excerpt("{\"a\":1}"), "{\"a\":1}"))
    ok("a long body is cut to 300 characters", Nat.is_eq(String.length(
      H.Http.excerpt(String.repeat("x", 500n))
    ), 300n))
