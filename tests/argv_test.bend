import Base
import ../src/argv.bend as A
import ../src/domain.bend as D
import ../src/policy.bend as P

# End-to-end check of the command line. Real argv lists go in; what comes out is
# read back through the same path the program uses -- `Cfg.resolve`, which turns
# items into the settings a run reads. So this covers the parser, the flag table,
# the verb table and the settings policy together, and not one of them alone.
#
#   bend tests/argv_test.bend
#
# Bend ships no test framework, so the test is a program: one line per case, and
# the first failure dies with a nonzero exit code.
#
# Two Bend rules shape the file: defs are written callee first (there are no
# forward declarations), and a `match` may not scrutinise a computed value. So
# every assertion goes through a def that takes what it wants to inspect as a
# parameter and returns a plain value, and `main` only ever compares values.

# ── printing ────────────────────────────────────────────────────────────

def ok_on(passed: Bool, +name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

# ── reading a parse result ──────────────────────────────────────────────
#
# One dispatching def per question. `badness` is a count rather than a Bool so
# the table checks can total it up with arithmetic instead of branching.

def badness(+p: A.Argv) -> U32:
  match p:
    case A.ArgvOk{items}:
      0
    case A.ArgvBad{error}:
      1

def message_of(+e: D.Error) -> String:
  match e:
    case D.Error{code, message, hint}:
      message

def error_text(+p: A.Argv) -> String:
  match p:
    case A.ArgvOk{items}:
      SNil{}
    case A.ArgvBad{error}:
      message_of(error)

def items_of(+p: A.Argv) -> List<&2, D.Item>:
  match p:
    case A.ArgvOk{items}:
      items
    case A.ArgvBad{error}:
      Nil{}

# ── the settings a parse resolves to ────────────────────────────────────

def resolve_of(+items: List<&2, D.Item>, tty: Bool, config: String) -> D.RunCfg:
  P.Cfg.resolve(items, Nil{}, Nil{}, tty, config)

def verb_of(+c: D.RunCfg) -> D.Verb:
  match c:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      verb

def out_of(+c: D.RunCfg) -> D.OutMode:
  match c:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      out

def engine_of(+c: D.RunCfg) -> D.Engine:
  match c:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      engine

def timeout_of(+c: D.RunCfg) -> U32:
  match c:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      timeout_ms

# ── the verb a parse produced ───────────────────────────────────────────

def target_of(+v: D.Verb) -> String:
  match v:
    case D.VerbRead{target}:
      target
    case D.VerbReplies{target}:
      target
    case D.VerbThread{target}:
      target
    case D.VerbSearch{query, count}:
      query
    case D.VerbReply{target, text, media}:
      target
    case _:
      SNil{}

def count_of(+v: D.Verb) -> U32:
  match v:
    case D.VerbSearch{query, count}:
      count
    case D.VerbMentions{count}:
      count
    case D.VerbBookmarks{count}:
      count
    case _:
      0

def text_of(+v: D.Verb) -> String:
  match v:
    case D.VerbTweet{text, media}:
      text
    case D.VerbReply{target, text, media}:
      text
    case _:
      SNil{}

def media_of(+v: D.Verb) -> List<&2, D.Media>:
  match v:
    case D.VerbTweet{text, media}:
      media
    case D.VerbReply{target, text, media}:
      media
    case _:
      Nil{}

# Counted rather than `List.length`, which answers `Nat`.
def media_count_go(m: List<&2, D.Media>, acc: U32) -> U32:
  match m:
    case Nil{}:
      acc
    case +h <> rest:
      media_count_go(rest, U32.add(acc, 1))

def media_count(+m: List<&2, D.Media>) -> U32:
  media_count_go(m, 0)

def image_alt_ok(+med: D.Media, alt: String) -> Bool:
  match med:
    case D.Media{path, alt_actual, mime, kind}:
      Bool.and(
        String.eq(mime, "image/jpeg"),
        Bool.and(String.eq(alt_actual, alt), P.Media.kind_is_image(kind))
      )

# The whole media path: `--media` and `--alt` have to arrive as their own item
# kinds for the policy to pair them into one Media with the right alt.
def head_is_image_with_alt(+m: List<&2, D.Media>, alt: String) -> Bool:
  match m:
    case +h <> _:
      image_alt_ok(h, alt)
    case Nil{}:
      False{}

# ── the same questions, asked of a parse result ─────────────────────────

def verb_name_of(+p: A.Argv, tty: Bool) -> String:
  match p:
    case A.ArgvOk{items}:
      D.Verb.name(verb_of(resolve_of(items, tty, "cfg")))
    case A.ArgvBad{error}:
      SNil{}

def target_of_args(+p: A.Argv) -> String:
  match p:
    case A.ArgvOk{items}:
      target_of(verb_of(resolve_of(items, False{}, "cfg")))
    case A.ArgvBad{error}:
      SNil{}

def count_of_args(+p: A.Argv) -> U32:
  match p:
    case A.ArgvOk{items}:
      count_of(verb_of(resolve_of(items, False{}, "cfg")))
    case A.ArgvBad{error}:
      0

def out_agent_of(+p: A.Argv, tty: Bool) -> Bool:
  match p:
    case A.ArgvOk{items}:
      D.OutMode.is_agent(out_of(resolve_of(items, tty, "cfg")))
    case A.ArgvBad{error}:
      False{}

def engine_name_of(+p: A.Argv) -> String:
  match p:
    case A.ArgvOk{items}:
      D.Engine.name(engine_of(resolve_of(items, False{}, "cfg")))
    case A.ArgvBad{error}:
      SNil{}

def timeout_of_args(+p: A.Argv) -> U32:
  match p:
    case A.ArgvOk{items}:
      timeout_of(resolve_of(items, False{}, "cfg"))
    case A.ArgvBad{error}:
      0

def bearer_of(+c: D.RunCfg) -> String:
  match c:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      web_bearer

def features_of(+c: D.RunCfg) -> String:
  match c:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      gql_features

def bearer_of_args(+p: A.Argv) -> String:
  match p:
    case A.ArgvOk{items}:
      bearer_of(resolve_of(items, False{}, "cfg"))
    case A.ArgvBad{error}:
      SNil{}

def features_of_args(+p: A.Argv) -> String:
  match p:
    case A.ArgvOk{items}:
      features_of(resolve_of(items, False{}, "cfg"))
    case A.ArgvBad{error}:
      SNil{}

def text_of_args(+p: A.Argv) -> String:
  match p:
    case A.ArgvOk{items}:
      text_of(verb_of(resolve_of(items, False{}, "cfg")))
    case A.ArgvBad{error}:
      SNil{}

def media_count_of_args(+p: A.Argv) -> U32:
  match p:
    case A.ArgvOk{items}:
      media_count(media_of(verb_of(resolve_of(items, False{}, "cfg"))))
    case A.ArgvBad{error}:
      0

def media_alt_ok_of_args(+p: A.Argv, alt: String) -> Bool:
  match p:
    case A.ArgvOk{items}:
      head_is_image_with_alt(media_of(verb_of(resolve_of(items, False{}, "cfg"))), alt)
    case A.ArgvBad{error}:
      False{}

# ── table checks: the parser, the help and the policy must agree ────────
#
# A flag is probed by handing it to a verb that accepts everything, so the only
# way the line is refused is if the flag itself is unknown.

def probe_line(p: String) -> List<&2, String>:
  "check" <> (p <> ("v" <> Nil{}))

def check_each(+name: String, names: List<&2, String>, bad: U32) -> IO(Unit):
  match names:
    case Nil{}:
      ok(name, U32.is_eq(bad, 0))
    case +n <> rest:
      check_each(name, rest, U32.add(bad, badness(A.Argv.parse(probe_line(n)))))

def check_table(name: String, names: List<&2, String>) -> IO(Unit):
  check_each(name, names, 0)

# Every flag name policy.bend and the settings code read, written out. Adding a
# flag there without accepting it here fails this check: the parser refuses what
# the rest of the program asks for, which is the one drift that silently breaks
# a setting.
def policy_flags() -> List<&2, String>:
  "--json" <> (
    "--raw" <> (
    "--dry-run" <> (
      "--text" <> (
        "--text-file" <> (
          "--media" <> (
            "--alt" <> (
              "--engine" <> (
                "--count" <> (
                  "--timeout-ms" <> (
                    "--fixture" <> (
                      "--auth-token" <> (
                        "--ct0" <> (
                          "--sweetistics-api-key" <> (
                            "--sweetistics-base-url" <> (
                              "--op-create-tweet" <> (
                                "--op-tweet-detail" <> (
                                  "--op-search" <> (
                                    "--op-viewer" <> (
                                      "--web-bearer" <> (
                                        "--gql-features" <> Nil{}
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)
def zero_if(hit: Bool) -> U32:
  match hit:
    case True{}:
      0
    case False{}:
      1

def help_missing_for(n: String) -> U32:
  zero_if(String.contains(A.Argv.help_text(), n))

# Counts the verbs the help text forgot, so one run reports the total instead of
# stopping at the first. `names` leads so the recursion shrinks on it.
def help_missing_count(names: List<&2, String>, missing: U32) -> U32:
  match names:
    case Nil{}:
      missing
    case +n <> rest:
      help_missing_count(rest, U32.add(missing, help_missing_for(n)))

def check_help_covers_verbs(names: List<&2, String>) -> IO(Unit):
  ok("help text names every verb", U32.is_eq(help_missing_count(names, 0), 0))

# ── the cases ───────────────────────────────────────────────────────────

def main() -> IO(Unit):
  do IO<Unit>:
    # A verb word names the verb; a bare word after it is the text.
    ok("verb word is the verb", String.eq(verb_name_of(A.Argv.parse("tweet" <> ("--text" <> ("hello" <> Nil{}))), False{}), "tweet"))
    ok("a bare word after the verb is the text", String.eq(text_of_args(A.Argv.parse("tweet" <> ("hello" <> Nil{}))), "hello"))
    ok("--text and a bare word agree", String.eq(text_of_args(A.Argv.parse("tweet" <> ("hello" <> Nil{}))), text_of_args(A.Argv.parse("tweet" <> ("--text" <> ("hello" <> Nil{}))))))
    ok("read takes a positional target", String.eq(target_of_args(A.Argv.parse("read" <> ("12345" <> Nil{}))), "12345"))
    ok("a url is kept whole for the policy to parse", String.eq(target_of_args(A.Argv.parse("read" <> ("https://x.com/u/status/12345" <> Nil{}))), "https://x.com/u/status/12345"))
    ok("reply takes a positional target", String.eq(target_of_args(A.Argv.parse("reply" <> ("12345" <> Nil{}))), "12345"))
    ok("no verb at all means help", String.eq(verb_name_of(A.Argv.parse(Nil{}), False{}), "help"))
    ok("check runs the check verb", String.eq(verb_name_of(A.Argv.parse("check" <> Nil{}), False{}), "check"))
    ok("mentions is a verb", String.eq(verb_name_of(A.Argv.parse("mentions" <> Nil{}), False{}), "mentions"))
    ok("bookmarks is a verb", String.eq(verb_name_of(A.Argv.parse("bookmarks" <> Nil{}), False{}), "bookmarks"))

    # Flags may come before or after the verb.
    ok("a setting may precede the verb", String.eq(verb_name_of(A.Argv.parse("--engine" <> ("sweetistics" <> ("whoami" <> Nil{}))), False{}), "whoami"))
    ok("--json on its own is help", String.eq(verb_name_of(A.Argv.parse("--json" <> Nil{}), False{}), "help"))
    ok("--version names a verb", String.eq(verb_name_of(A.Argv.parse("--version" <> Nil{}), False{}), "version"))
    ok("--schema names a verb", String.eq(verb_name_of(A.Argv.parse("--schema" <> Nil{}), False{}), "schema"))
    ok("-h is --help", String.eq(verb_name_of(A.Argv.parse("-h" <> Nil{}), False{}), "help"))
    ok("an inline value keeps its own = signs", String.eq(text_of_args(A.Argv.parse("tweet" <> ("--text=a=b" <> Nil{}))), "a=b"))

    # Settings land where the policy reads them.
    ok("--count reaches the search verb", U32.is_eq(count_of_args(A.Argv.parse("search" <> ("rust" <> ("--count" <> ("25" <> Nil{}))))), 25))
    ok("--count works before the verb too", U32.is_eq(count_of_args(A.Argv.parse("--count" <> ("7" <> ("mentions" <> Nil{})))), 7))
    ok("--count reaches the bookmarks verb", U32.is_eq(count_of_args(A.Argv.parse("bookmarks" <> ("--count" <> ("25" <> Nil{})))), 25))
    ok("a bookmarks with no --count uses the default", U32.is_eq(count_of_args(A.Argv.parse("bookmarks" <> Nil{})), P.Cfg.default_count()))
    ok("a search with no --count uses the default", U32.is_eq(count_of_args(A.Argv.parse("search" <> ("rust" <> Nil{}))), P.Cfg.default_count()))
    ok("--engine selects the engine", String.eq(engine_name_of(A.Argv.parse("--engine" <> ("sweetistics" <> ("whoami" <> Nil{})))), "sweetistics"))
    ok("no --engine leaves the default alone", String.eq(engine_name_of(A.Argv.parse("whoami" <> Nil{})), "graphql"))
    ok("--timeout-ms is read", U32.is_eq(timeout_of_args(A.Argv.parse("--timeout-ms" <> ("3000" <> ("check" <> Nil{})))), 3000))
    ok("--timeout-ms below the floor is clamped up", U32.is_eq(timeout_of_args(A.Argv.parse("--timeout-ms" <> ("5" <> ("check" <> Nil{})))), 1000))
    ok("--timeout-ms above the ceiling is clamped down", U32.is_eq(timeout_of_args(A.Argv.parse("--timeout-ms" <> ("999999" <> ("check" <> Nil{})))), 120000))

    ok("--web-bearer reaches the transport", String.eq(bearer_of_args(A.Argv.parse("--web-bearer" <> ("tok" <> ("whoami" <> Nil{})))), "tok"))
    ok("no --web-bearer leaves it empty for the request builder to refuse", String.eq(bearer_of_args(A.Argv.parse("whoami" <> Nil{})), SNil{}))
    ok("--gql-features defaults to an empty object", String.eq(features_of_args(A.Argv.parse("whoami" <> Nil{})), "{}"))
    ok("--gql-features carries its own json through", String.eq(features_of_args(A.Argv.parse("--gql-features" <> ("{\"a\":true}" <> ("whoami" <> Nil{})))), "{\"a\":true}"))

    # Media: the two item kinds the policy pairs up.
    ok("media and alt arrive as one image with its alt", media_alt_ok_of_args(
      A.Argv.parse("tweet" <> ("--text" <> ("hi" <> ("--media" <> ("a.jpg" <> ("--alt" <> ("pic" <> Nil{}))))))),
      "pic"
    ))
    ok("one --media is one item", U32.is_eq(media_count_of_args(A.Argv.parse("tweet" <> ("--media" <> ("a.jpg" <> Nil{})))), 1))
    ok("two --media is two items", U32.is_eq(media_count_of_args(A.Argv.parse("tweet" <> ("--media" <> ("a.jpg" <> ("--media" <> ("b.png" <> Nil{})))))), 2))

    # Output mode: a terminal is human, a pipe is agent, and --json forces the
    # envelope either way. LAWS.bend states exactly this.
    ok("a tty with nothing asked is human", Bool.not(out_agent_of(A.Argv.parse("check" <> Nil{}), True{})))
    ok("a pipe with nothing asked is agent", out_agent_of(A.Argv.parse("check" <> Nil{}), False{}))
    ok("--json forces agent output on a tty", out_agent_of(A.Argv.parse("--json" <> ("check" <> Nil{})), True{}))

    # Bad lines are refused, and each says what is wrong.
    ok("an unknown flag is refused", U32.is_eq(badness(A.Argv.parse("--nope" <> Nil{})), 1))
    ok("an unknown flag is named", String.contains(error_text(A.Argv.parse("--nope" <> Nil{})), "--nope"))
    ok("a value flag with no value is refused", U32.is_eq(badness(A.Argv.parse("--text" <> Nil{})), 1))
    ok("a verb missing its target is refused", U32.is_eq(badness(A.Argv.parse("read" <> Nil{})), 1))
    ok("the missing target is named", String.contains(error_text(A.Argv.parse("read" <> Nil{})), "read"))
    ok("a stray word is refused", U32.is_eq(badness(A.Argv.parse("splunge" <> Nil{})), 1))
    ok("a second verb is refused while the first still owes a target", U32.is_eq(badness(A.Argv.parse("read" <> ("tweet" <> Nil{}))), 1))
    ok("a value flag never eats the next flag", U32.is_eq(badness(A.Argv.parse("--text" <> ("--json" <> Nil{}))), 1))

    # The tables cannot drift apart.
    check_table("every flag the parser lists parses", A.Argv.flag_names())
    check_table("every flag the policy reads parses", policy_flags())
    check_help_covers_verbs(A.Argv.verbs())

    ok("help text carries the usage line", String.contains(A.Argv.help_text(), "bird <verb> [flags]"))
    ok("help text documents --json", String.contains(A.Argv.help_text(), "--json"))
