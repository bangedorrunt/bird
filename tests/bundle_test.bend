import Base
import ../src/bundle.bend as B
import ../src/cookies.bend as C
import ../src/json.bend as J
import ../src/policy.bend as P
import ../src/domain.bend as D

# End-to-end check of what `bird login` reads and what it writes. Bend ships no
# test framework, so the test is a program: one line per case, nonzero exit on the
# first failure.
#
#   bend tests/bundle_test.bend
#
# The documents are shaped like the live ones. The bundle ids were recorded on
# 2026-10-11 from https://abs.twimg.com/responsive-web/client-web/main.<hash>.js,
# except the Bookmarks id, which comes from twitter-cli's recorded fallback
# table. The block that
# matters most is the cache one: the settings the cache writes are read back
# through `Cfg.resolve`, so a cache the resolver cannot read is a failing test
# rather than a run that silently has no bearer.

def ok_on(passed: Bool, +name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

# ── the fixture ─────────────────────────────────────────────────────────

def html() -> String:
  "<script defer src=\"https://abs.twimg.com/responsive-web/client-web/main.759a3196d8872caea.js\" nonce=\"x\"></script>"

def bundle_url() -> String:
  "https://abs.twimg.com/responsive-web/client-web/main.759a3196d8872caea.js"

def bearer() -> String:
  "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

def js() -> String:
  "e.exports={queryId:\"TpQxQtWMTMnIAMPlMGMqNw\",operationName:\"Viewer\",operationType:\"query\"}"
  ++ ",{queryId:\"3BlMtudy4N-d78ch7zTLZQ\",operationName:\"TweetDetail\",operationType:\"query\"}"
  ++ ",{queryId:\"irezafrnzav4Ulf1vDkEBg\",operationName:\"SearchTimeline\",operationType:\"query\"}"
  ++ ",{queryId:\"uzboyXSHSJrR-mGJqep0TQ\",operationName:\"Bookmarks\",operationType:\"query\"}"
  ++ ",{queryId:\"wR5Z_lEibLvkew3tF9w-Sg\",operationName:\"CreateTweet\",operationType:\"mutation\"}"
  ++ ",Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA\","

# The bundle X served on 2026-10-11: four operations and no `Bookmarks` record
# at all, which is why that one is left optional -- a login that refused on it
# would refuse every login. The other four are the ones a bundle must carry.
def js_four() -> String:
  "e.exports={queryId:\"TpQxQtWMTMnIAMPlMGMqNw\",operationName:\"Viewer\",operationType:\"query\"}"
  ++ ",{queryId:\"3BlMtudy4N-d78ch7zTLZQ\",operationName:\"TweetDetail\",operationType:\"query\"}"
  ++ ",{queryId:\"irezafrnzav4Ulf1vDkEBg\",operationName:\"SearchTimeline\",operationType:\"query\"}"
  ++ ",{queryId:\"wR5Z_lEibLvkew3tF9w-Sg\",operationName:\"CreateTweet\",operationType:\"mutation\"}"
  ++ ",Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA\","

# A bundle that is complete but for the operation ids, so the refusal can be
# checked by name.
def js_short() -> String:
  "e.exports={queryId:\"TpQxQtWMTMnIAMPlMGMqNw\",operationName:\"Viewer\",operationType:\"query\"}"
  ++ ",Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA\","

def j(xs: List<&2, String>) -> String:
  String.join(xs, "|")

# ── reading the fixture ─────────────────────────────────────────────────

def viewer_of(+f: B.Found) -> String:
  match f:
    case B.Found{bearer, viewer, detail, search, bookmarks, create}:
      viewer

def detail_of(+f: B.Found) -> String:
  match f:
    case B.Found{bearer, viewer, detail, search, bookmarks, create}:
      detail

def search_of(+f: B.Found) -> String:
  match f:
    case B.Found{bearer, viewer, detail, search, bookmarks, create}:
      search

def bookmarks_of(+f: B.Found) -> String:
  match f:
    case B.Found{bearer, viewer, detail, search, bookmarks, create}:
      bookmarks

def create_of(+f: B.Found) -> String:
  match f:
    case B.Found{bearer, viewer, detail, search, bookmarks, create}:
      create

# ── reading a resolved run ──────────────────────────────────────────────

def bearer_in(+cfg: D.RunCfg) -> String:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      web_bearer

def detail_in(+cfg: D.RunCfg) -> String:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      op_tweet_detail

def op_bookmarks_in(+cfg: D.RunCfg) -> String:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      op_bookmarks

def creds_in(+cfg: D.RunCfg) -> D.Creds:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      creds

# A match may not scrutinise a computed value, so the credential is read by a def
# that takes it as its own parameter: `creds_in(cfg)` is an argument, not a
# scrutinee.
def at_on(+c: D.Creds) -> String:
  match c:
    case D.Session{auth_token, ct0, source}:
      auth_token
    case _:
      SNil{}

def session_on(+c: D.Creds) -> Bool:
  match c:
    case D.Session{auth_token, ct0, source}:
      True{}
    case _:
      False{}

def at_in(+cfg: D.RunCfg) -> String:
  at_on(creds_in(cfg))

def is_session(+cfg: D.RunCfg) -> Bool:
  session_on(creds_in(cfg))

# ── the checks ──────────────────────────────────────────────────────────

def base() -> String:
  "https://abs.twimg.com/responsive-web/client-web/"

# The head the bundle is served from is a setting, so the same page read against a
# stand-in's base answers the stand-in's url: that is what lets the whole login
# flow run against `tests/e2e.sh`'s own server.
def check_bundle_url() -> IO(Unit):
  do IO<Unit>:
    ok("the page names its bundle", String.eq(B.Bundle.identify(base(), html()), bundle_url()))
    ok("and that is a bundle", B.Bundle.identified(base(), html()))
    ok("a page with no bundle is not one", Bool.not(B.Bundle.identified(base(), "<html></html>")))
    ok("a different base moves the url with it", String.eq(
      B.Bundle.identify("http://127.0.0.1:9/client-web/", html()),
      "http://127.0.0.1:9/client-web/main.759a3196d8872caea.js"
    ))

def check_bundle(+f: B.Found) -> IO(Unit):
  do IO<Unit>:
    ok("the bearer is whole", String.eq(B.Bundle.bearer(js()), bearer()))
    ok("the viewer id is read", String.eq(viewer_of(f), "TpQxQtWMTMnIAMPlMGMqNw"))
    ok("the detail id is read", String.eq(detail_of(f), "3BlMtudy4N-d78ch7zTLZQ"))
    ok("the search id is read", String.eq(search_of(f), "irezafrnzav4Ulf1vDkEBg"))
    ok("the bookmarks id is read", String.eq(bookmarks_of(f), "uzboyXSHSJrR-mGJqep0TQ"))
    ok("the create id is read", String.eq(create_of(f), "wR5Z_lEibLvkew3tF9w-Sg"))
    ok("a complete bundle is missing nothing", String.eq(B.Bundle.missing(f), ""))

def check_missing() -> IO(Unit):
  do IO<Unit>:
    ok("a bundle with holes names the first one", String.eq(B.Bundle.missing(B.Bundle.found(js_short())), "--op-tweet-detail"))
    ok("a bundle with no bearer names that", String.eq(B.Bundle.missing(B.Bundle.found("{}{}")), "--web-bearer"))
    ok("a bundle without the bookmarks operation is still complete",
       String.eq(B.Bundle.missing(B.Bundle.found(js_four())), ""))
    ok("...and it writes no bookmarks setting into the cache", Bool.not(String.contains(
      B.Bundle.cache_text(B.Bundle.found(js_four()), "AT-VALUE", "CT0-VALUE"),
      "--op-bookmarks"
    )))

def json_of(p: J.Parsed) -> J.Json:
  match p:
    case J.ParsedOk{value}:
      value
    case J.ParsedErr{message}:
      J.null()

def cache_items(+f: B.Found) -> List<&2, D.Item>:
  text : String = B.Bundle.cache_text(f, "AT-VALUE", "CT0-VALUE")
  P.Cfg.rc_items(J.fields(json_of(J.parse(text))))

# The cache is a settings file, so the thing it has to satisfy is the resolver: a
# flag still wins over it, it wins over nothing, and its values arrive where the
# request builders read them.
def check_cache(+f: B.Found) -> IO(Unit):
  do IO<Unit>:
    +rc : List<&2, D.Item> = cache_items(f)
    +cfg : D.RunCfg = P.Cfg.resolve(Nil{}, Nil{}, rc, False{}, SNil{})
    ok("the cached bearer reaches the config", String.eq(bearer_in(cfg), bearer()))
    ok("the cached detail id reaches the config", String.eq(detail_in(cfg), "3BlMtudy4N-d78ch7zTLZQ"))
    ok("the cached bookmarks id reaches the config", String.eq(op_bookmarks_in(cfg), "uzboyXSHSJrR-mGJqep0TQ"))
    ok("the cached cookies make a session", is_session(cfg))
    ok("the cached auth token is the one written", String.eq(at_in(cfg), "AT-VALUE"))
    +rc2 : List<&2, D.Item> = cache_items(f)
    flagged : D.RunCfg = P.Cfg.resolve(D.Item.flag("--web-bearer", "flag-wins") <> Nil{}, Nil{}, rc2, False{}, SNil{})
    ok("a flag still wins over the cache", String.eq(bearer_in(flagged), "flag-wins"))

def check_sql() -> IO(Unit):
  do IO<Unit>:
    +f : String = C.Cookies.firefox_sql()
    ok("the firefox query reads both cookies", String.contains(f, "moz_cookies"))
    ok("and names both names", Bool.and(String.contains(f, "auth_token"), String.contains(f, "ct0")))
    ok("and is limited to the domain", String.contains(f, "%x.com"))
    +c : String = C.Cookies.chrome_sql("/tmp/d")
    ok("the chrome query writes the auth token out", String.contains(c, "writefile('/tmp/d/auth_token', encrypted_value)"))
    ok("the chrome query writes ct0 out", String.contains(c, "writefile('/tmp/d/ct0', encrypted_value)"))

def check_readings() -> IO(Unit):
  do IO<Unit>:
    +out : String = "auth_token|1234567890abcdef\nct0|aaaaaaaaaaaaaaaaaaaa\n"
    ok("a firefox line is read", String.eq(C.Cookies.firefox_at(out), "1234567890abcdef"))
    ok("and the second one too", String.eq(C.Cookies.firefox_ct0(out), "aaaaaaaaaaaaaaaaaaaa"))
    ok("a missing name reads as nothing", String.eq(C.Cookies.firefox_at("ct0|aa\n"), ""))
    ok("a key loses its colons", String.eq(C.Cookies.key_of("9F:E8:1A:62\n"), "9FE81A62"))
    ok("a decrypted cookie drops chrome's marker", String.eq(C.Cookies.chrome_value("v10abcdef"), "abcdef"))
    ok("a value with no marker is itself", String.eq(C.Cookies.chrome_value("abcdef"), "abcdef"))
    ok("a decrypted value with a space is refused", String.eq(C.Cookies.chrome_value("v10a bcd"), ""))
    ok("an empty decryption is refused", String.eq(C.Cookies.chrome_value(""), ""))
    ok("padding around a cookie is trimmed", String.eq(C.Cookies.chrome_value("  v10abc  \n"), "abc"))

def check_argv() -> IO(Unit):
  do IO<Unit>:
    ok("the key derivation asks for the right key", String.eq(
      j(C.Cookies.kdf_args("pw")),
      "kdf|-keylen|16|-kdfopt|digest:SHA1|-kdfopt|pass:pw|-kdfopt|hexsalt:73616c747973616c74|-kdfopt|iter:1003|PBKDF2"
    ))
    ok("the decryption reads the file it was given", String.eq(
      j(C.Cookies.decrypt_args("AABB", "/tmp/d/auth_token")),
      "enc|-aes-128-cbc|-d|-K|AABB|-iv|20202020202020202020202020202020|-nopad|-in|/tmp/d/auth_token"
    ))
    ok("the sqlite call is read only", String.eq(j(C.Cookies.sqlite_args("/db", "select 1")), "-readonly|-noheader|/db|select 1"))
    ok("the keychain entry is named", String.eq(j(C.Cookies.security_args()), "find-generic-password|-w|-s|Chrome Safe Storage"))
    ok("the cleanup names both files", String.eq(j(C.Cookies.rm_args("/tmp/d")), "-f|/tmp/d/auth_token|/tmp/d/ct0"))
    ok("the cache is readable only by its owner", String.eq(j(C.Cookies.chmod_args("/x/settings.json")), "600|/x/settings.json"))

def main() -> IO(Unit):
  do IO<Unit>:
    check_bundle_url()
    +found : B.Found = B.Bundle.found(js())
    check_bundle(found)
    +for_cache : B.Found = B.Bundle.found(js())
    check_cache(for_cache)
    check_missing()
    check_sql()
    check_readings()
    check_argv()
