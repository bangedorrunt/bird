import Base
import ../src/scan.bend as S

# End-to-end check of the text scanning used to read X's client bundle. Bend ships
# no test framework, so the test is a program: it prints one line per case and
# dies with a nonzero exit code on the first failure.
#
#   bend tests/scan_test.bend
#
# The document here is shaped like the real bundle, recorded from
# https://abs.twimg.com/responsive-web/client-web/main.<hash>.js on 2026-10-11:
# each operation is one record, and the bearer is a bare token inside a string.
# The awkward cases are the ones the walk has to survive: a record whose name is
# missing, a name that is a prefix of another name, and a run of characters that
# begins the needle but is not it.

def ok_on(passed: Bool, +name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

# Several records, in the shape the bundle writes them, plus the two decoys.
def js() -> String:
  "{a:1},e.exports={queryId:\"TpQxQtWMTMnIAMPlMGMqNw\",operationName:\"Viewer\",operationType:\"query\"}"
  ++ ",{queryId:\"3BlMtudy4N-d78ch7zTLZQ\",operationName:\"TweetDetail\",operationType:\"query\"},"
  ++ "{queryId:\"nope\",operationType:\"query\",z:2},"
  ++ "{queryId:\"V1s1bleSearchId\",operationName:\"SearchTimeline\",operationType:\"query\"},"
  ++ "{queryId:\"CrtTweetQueryId000001\",operationName:\"CreateTweet\",operationType:\"mutation\"},"
  ++ "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA\","

def html() -> String:
  "<script defer src=\"https://abs.twimg.com/responsive-web/client-web/main.759a3196d8872caea.js\" nonce=\"x\"></script>"

def check_pairs() -> IO(Unit):
  do IO<Unit>:
    +pairs : String = S.Scan.pairs_of(js())
    ok("a record is read as name and id", String.contains(pairs, "TweetDetail=3BlMtudy4N-d78ch7zTLZQ"))
    ok("viewer comes out", String.eq(S.Scan.looked_up(pairs, "Viewer"), "TpQxQtWMTMnIAMPlMGMqNw"))
    ok("search comes out", String.eq(S.Scan.looked_up(pairs, "SearchTimeline"), "V1s1bleSearchId"))
    ok("create comes out", String.eq(S.Scan.looked_up(pairs, "CreateTweet"), "CrtTweetQueryId000001"))
    ok("a record with no name lead is dropped", Bool.not(String.contains(pairs, "nope")))
    ok("an absent name reads as nothing", String.eq(S.Scan.looked_up(pairs, "ThreadedConversation"), ""))
    # A name must be read whole: `Tweet` is the tail of `CreateTweet` and the
    # head of `TweetDetail`, and neither may answer for it. The lookup is
    # anchored on the line separator, so both are safe.
    ok("a name that is the tail of another is not confused with it", String.eq(S.Scan.looked_up(pairs, "Tweet"), ""))
    ok("a name that is the head of another is not confused with it", String.eq(S.Scan.looked_up(pairs, "TweetDetail"), "3BlMtudy4N-d78ch7zTLZQ"))
    ok("every record is emitted once", String.eq(S.Scan.looked_up(pairs, "TweetDetail"), "3BlMtudy4N-d78ch7zTLZQ"))

def check_bundle_url() -> IO(Unit):
  do IO<Unit>:
    found : Maybe<&2, String> = S.Scan.after(html(), "client-web/main.", S.Scan.quote(), 256n)
    ok("the bundle url is read out of the page", String.eq(S.Scan.token_or_nothing(found), "759a3196d8872caea.js"))
    missing : Maybe<&2, String> = S.Scan.after(html(), "client-web/vendor.", S.Scan.quote(), 256n)
    ok("a needle that is not there reads as nothing", String.eq(S.Scan.token_or_nothing(missing), ""))

def bearer() -> String:
  "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

def check_bearer() -> IO(Unit):
  do IO<Unit>:
    +tail : Maybe<&2, String> = S.Scan.after(js(), "AAAAAAAAAAAAAAAAAAAA", S.Scan.quote(), 256n)
    ok("the bearer is read as its tail", String.eq(S.Scan.token_or_nothing(tail), "ANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"))
    ok("prepending its head restores it", String.eq("AAAAAAAAAAAAAAAAAAAA" ++ S.Scan.token_or_nothing(tail), bearer()))

def check_helpers() -> IO(Unit):
  do IO<Unit>:
    ok("a derived key loses its colons", String.eq(S.Scan.uncolon("9F:E8:1A:62:7E:83:DD:33:B7:3A:9D:C7:D1:48:AA:54"), "9FE81A627E83DD33B73A9DC7D148AA54"))
    ok("a key with no colons is itself", String.eq(S.Scan.uncolon("AABB"), "AABB"))
    ok("digits are digits", S.Scan.digits("83"))
    ok("an empty count is digits", S.Scan.digits(""))
    ok("a signed count is not", Bool.not(S.Scan.digits("-1")))
    ok("the head of a string is read", S.Scan.head_is("abc", 'a'))
    ok("the head of nothing is not", Bool.not(S.Scan.head_is("", 'a')))
    ok("a token stops at its delimiter", String.eq(S.Scan.token_or_nothing(S.Scan.after("needle=ab-cd", "needle=", '-', 8n)), "ab"))
    ok("a token with no delimiter is cut at its bound", String.eq(S.Scan.token_or_nothing(S.Scan.after("needle=abcdef", "needle=", '-', 3n)), "abc"))
    ok("a delimiter right after the needle is an empty token", String.eq(S.Scan.token_or_nothing(S.Scan.after("needle=--", "needle=", '-', 8n)), ""))

# The directory part of a path, which the interpreter uses to make the directory
# a settings cache is about to be written into. The default path it is written for
# is three levels deep, and the case that matters is a path at the top level: there
# is no directory to make, so the interpreter must not try.
def check_dir_of() -> IO(Unit):
  do IO<Unit>:
    ok("the directory is everything before the last slash", String.eq(S.Scan.dir_of("/Users/x/.config/bird/settings.json", SNil{}), "/Users/x/.config/bird"))
    ok("...one level up", String.eq(S.Scan.dir_of("/tmp/settings.json", SNil{}), "/tmp"))
    ok("a path with no slash has no directory", String.eq(S.Scan.dir_of("settings.json", SNil{}), ""))
    ok("nothing has no directory", String.eq(S.Scan.dir_of(SNil{}, SNil{}), ""))
    ok("a leading slash is the directory", String.eq(S.Scan.dir_of("/settings.json", SNil{}), "/"))
    ok("a trailing slash does not name an empty directory", String.eq(S.Scan.dir_of("a/b/", SNil{}), "a/b"))
    ok("two slashes in a row keep the first", String.eq(S.Scan.dir_of("a//b", SNil{}), "a/"))
    ok("a trailing slash names the directory itself", String.eq(S.Scan.dir_of("/Users/x/.config/bird/", SNil{}), "/Users/x/.config/bird"))

def main() -> IO(Unit):
  do IO<Unit>:
    check_pairs()
    check_bundle_url()
    check_bearer()
    check_helpers()
    check_dir_of()
