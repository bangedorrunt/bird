import Base
import ./scan.bend as S
import ./json.bend as J

# Reading X's deployment constants out of X's own client bundle.
#
# Every value here rotates on X's schedule, which is why none of them is compiled
# in and why the run can go and fetch them. The page the signed-in client loads
# names a bundle, and the bundle carries the client bearer as a string literal and
# each GraphQL operation as a record:
#
#   {queryId:"3BlMtudy4N-d78ch7zTLZQ",operationName:"TweetDetail",operationType:"query"}
#
# Both shapes were read off the live bundle on 2026-10-11, and `tests/bundle_test`
# keeps a copy of them so a change in X's shape is a failing test rather than an
# empty setting that reaches X as a refusal.
#
# Nothing here decides anything: it takes a document and answers what it found,
# and `Bundle.missing` names what it did not, so the caller refuses rather than
# sending a request built from a hole.

# ── the two documents ───────────────────────────────────────────────────

# The bundle the page loads. The page names it in full in a `src`, so the tail of
# that path -- `main.<hash>.js` -- is read out of the page and the head it is
# served from is a setting, for the same reason every other host is one: a run has
# to be pointable at a stand-in, and `tests/e2e.sh` points the whole login flow at
# its own server that way.
def Bundle.name() -> String:
  "main."

def Bundle.mark() -> String:
  "client-web/" ++ Bundle.name()

def Bundle.identify(+base: String, +html: String) -> String:
  base ++ Bundle.name() ++ S.Scan.token_or_nothing(S.Scan.after(html, Bundle.mark(), S.Scan.quote(), 256n))

def Bundle.identified(+base: String, +html: String) -> Bool:
  Bool.and(
    Bool.not(String.is_empty(Bundle.identify(base, html))),
    String.ends_with(Bundle.identify(base, html), ".js")
  )

# ── the bearer ──────────────────────────────────────────────────────────

# The client bearer is a string literal in the bundle. It identifies the client,
# not the account: the cookies name the account. The head is fixed (they all
# begin with the same run of `A`s) and the tail is what is read, so the search is
# for a distinctive needle rather than for the whole token.
def Bundle.bearer_head() -> String:
  "AAAAAAAAAAAAAAAAAAAA"

def Bundle.bearer_tail(+js: String) -> String:
  S.Scan.token_or_nothing(S.Scan.after(js, Bundle.bearer_head(), S.Scan.quote(), 256n))

# Nothing, not the bare head, when the document did not carry a token: the head
# alone is twenty `A`s that would be sent to X as a client identity and refused
# there, and `Bundle.missing` has to be able to see that it is absent.
def Bundle.join_bearer(+tail: String) -> String:
  match tail:
    case "":
      SNil{}
    case _:
      Bundle.bearer_head() ++ tail

def Bundle.bearer(+js: String) -> String:
  Bundle.join_bearer(Bundle.bearer_tail(js))

# ── the four operation ids ──────────────────────────────────────────────

def Bundle.op_viewer() -> String:
  "Viewer"

def Bundle.op_detail() -> String:
  "TweetDetail"

def Bundle.op_search() -> String:
  "SearchTimeline"

def Bundle.op_create() -> String:
  "CreateTweet"

# ── everything the bundle is read for ───────────────────────────────────

type Found is Data:
  Found{
    bearer: String,
    viewer: String,
    detail: String,
    search: String,
    create: String,
  }

# The record walk happens once, so all four ids come out of a single pass and the
# bearer out of the document itself. The caller hands the collected pairs in so
# the pass is not repeated for each name.
# Positional, in the order the record declares its fields: Bend has no
# field-named construction, which is why `Found` is built through this one def
# rather than at each call site.
def Bundle.found_at(+js: String, +pairs: String) -> Found:
  Found{
    Bundle.bearer(js),
    S.Scan.looked_up(pairs, Bundle.op_viewer()),
    S.Scan.looked_up(pairs, Bundle.op_detail()),
    S.Scan.looked_up(pairs, Bundle.op_search()),
    S.Scan.looked_up(pairs, Bundle.op_create())
  }

def Bundle.found(+js: String) -> Found:
  Bundle.found_at(js, S.Scan.pairs_of(js))

# ── what is missing, by name ────────────────────────────────────────────
#
# A bundle that answered with three of five leaves a run that looks configured
# and is not, so the first hole is named and the run stops here. `--flag` names
# are what the hint offers, because those are what a person can set by hand.

# The name of the setting that is empty, or nothing when they are all there.
def Bundle.absent(+s: String, +name: String) -> String:
  match s:
    case "":
      name
    case _:
      SNil{}

# The first hole, and only the first: an answer already found is never replaced,
# so a bundle missing two settings names the one a person would set first. The
# nesting is evaluated inside out, which is why the bearer is the innermost call.
def Bundle.hole(+s: String, +name: String, +so_far: String) -> String:
  match so_far:
    case "":
      Bundle.absent(s, name)
    case _:
      so_far

def Bundle.missing(+f: Found) -> String:
  match f:
    case Found{bearer, viewer, detail, search, create}:
      Bundle.hole(
        create,
        "--op-create-tweet",
        Bundle.hole(
          search,
          "--op-search",
          Bundle.hole(
            detail,
            "--op-tweet-detail",
            Bundle.hole(viewer, "--op-viewer", Bundle.hole(bearer, "--web-bearer", SNil{}))
          )
        )
      )

# ── the cache ───────────────────────────────────────────────────────────
#
# What a run reads back is a settings file, not a private format: an object
# whose keys are flag names, which is the same shape a config file has and the
# same resolver reads. So one setting is spelled the same way whether it came
# from `--flag`, the environment, a config file, or this cache.
#
# The session cookies ride along when the run imported them, which is what makes
# a read work with no flags at all after one `login`. That is a deliberate
# reversal of the original non-goal -- see docs/decisions/0001-design-bird.md --
# and it is why the file is written 0600.
def Bundle.cache_json(+f: Found, +at: String, +ct0: String) -> J.Json:
  match f:
    case Found{bearer, viewer, detail, search, create}:
      J.obj7(
        J.pair("--auth-token", J.of_str(at)),
        J.pair("--ct0", J.of_str(ct0)),
        J.pair("--web-bearer", J.of_str(bearer)),
        J.pair("--op-viewer", J.of_str(viewer)),
        J.pair("--op-tweet-detail", J.of_str(detail)),
        J.pair("--op-search", J.of_str(search)),
        J.pair("--op-create-tweet", J.of_str(create))
      )

def Bundle.cache_text(+f: Found, +at: String, +ct0: String) -> String:
  J.pretty(Bundle.cache_json(f, at, ct0))
