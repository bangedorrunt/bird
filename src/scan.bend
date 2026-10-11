import Base

# Text scanning: finding a needle in a large document and reading the tokens
# around it. Used to read X's client bundle, which is over a megabyte, so the
# cost of these walks is the reason they look the way they do.
#
# Four facts about this language decide the shape of every walk below, and each
# one is why a natural-looking helper is missing:
#
#   1. `String.append` and `String.take` are not tail-recursive: each costs one
#      stack frame per character of its first argument. So a token is collected
#      by *growing a short accumulator* (never by taking a long window, never by
#      appending to a string that is already large), and each accumulator here is
#      bounded by the caller.
#   2. Mutual recursion is forbidden, so a walk is ONE self-recursive def. A
#      helper that called back into the walk would be a second def in a cycle,
#      which is why the facts a branch needs (`here`) travel as arguments, why
#      every state machine is a `Nat` argument rather than several defs, and why
#      the helpers that do exist never call a walk back.
#   3. Termination is checked on the arguments in order, so the string that
#      shrinks leads every argument list and every recursive call is on its tail.
#   4. A `match` may only scrutinise a parameter or a field of one, never a
#      computed value, so a derived fact is passed in rather than matched on.

# ── small helpers that never call a walk back ───────────────────────────

def Scan.quote() -> Char:
  '"'

def Scan.equals() -> Char:
  '='

def Scan.newline() -> Char:
  '\n'

def Scan.colon() -> Char:
  ':'

# The opening of one record in the bundle, and the lead of the name inside it.
def Scan.opening() -> String:
  "queryId:\""

def Scan.name_lead() -> String:
  ",operationName:\""

# Whether the first character is `c`.
def Scan.head_is(+s: String, +c: Char) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{h, t}:
      Char.is_eq(h, c)

# Whether `s` begins with `needle`, as a value rather than a branch: a walk needs
# the answer for the *next* position before it recurses.
def Scan.starts(+s: String, +needle: String) -> Bool:
  String.starts_with(s, needle)

def Scan.append_char(+s: String, +c: Char) -> String:
  s ++ SCon{c, SNil{}}

# One record per line, each line opened by the separator rather than ending with
# it: a lookup can then anchor on `\n<name>=` and a name that happens to be the
# tail of another name (`Tweet` inside `CreateTweet`) cannot be answered with the
# longer name's id.
def Scan.pair_out(+out: String, +name: String, +id: String) -> String:
  out ++ SCon{Scan.newline(), SNil{}} ++ name ++ SCon{Scan.equals(), SNil{}} ++ id

# ── finding a needle ────────────────────────────────────────────────────

# The suffix that begins at the first occurrence of `needle`, or nothing when the
# needle is not there.
# The string is matched before the test, because a match has to follow the order
# the binders are declared in: `here` cannot be matched before the string the
# test was taken from.
def Scan.seek(cur: String, +needle: String, +here: Bool) -> Maybe<&2, String>:
  match cur:
    case SNil{}:
      None{}
    case SCon{+h, +t}:
      match here:
        case True{}:
          Some{SCon{h, t}}
        case False{}:
          Scan.seek(t, needle, Scan.starts(t, needle))

# ── reading a token ─────────────────────────────────────────────────────

# The characters at the front of `s`, up to but not including `stop`, or the
# first `n` of them when `stop` never arrives. `n` is what stops a missing
# delimiter from walking a megabyte into the accumulator, and it is also the
# argument the termination checker watches.
def Scan.until(n: Nat, s: String, +stop: Char, +acc: String, +hit: Bool) -> String:
  match n:
    case 0n:
      acc
    case 1n+less:
      match s:
        case SNil{}:
          acc
        case SCon{+h, +t}:
          match hit:
            case True{}:
              acc
            case False{}:
              Scan.until(less, t, stop, Scan.append_char(acc, h), Scan.head_is(t, stop))

# The token that follows `needle` in `rest`: the text after it, up to the next
# `stop`. Nothing when the needle is not there.
#
# `needle` is dropped from the suffix found rather than consumed during the
# search: `String.length` of a needle of a few characters is cheap, of the
# document it is not.
# `stock` is the text the token is at the front of, and it is reusable because the
# first test and the first step both need it: entering the walk with a guessed
# false test would let a token that begins with the stop character come back with
# that character in it.
def Scan.token_at(+stock: String, +stop: Char, bound: Nat) -> Maybe<&2, String>:
  Some{Scan.until(bound, stock, stop, SNil{}, Scan.head_is(stock, stop))}

def Scan.token(rest: Maybe<&2, String>, +needle: String, +stop: Char, bound: Nat) -> Maybe<&2, String>:
  match rest:
    case None{}:
      None{}
    case Some{at}:
      Scan.token_at(String.drop(at, String.length(needle)), stop, bound)

def Scan.after(+s: String, +needle: String, +stop: Char, bound: Nat) -> Maybe<&2, String>:
  Scan.token(Scan.seek(s, needle, Scan.starts(s, needle)), needle, stop, bound)

# ── the record pairs a client bundle writes ─────────────────────────────
#
# X writes every GraphQL operation as one record:
#
#   {queryId:"3BlMtudy4N-d78ch7zTLZQ",operationName:"TweetDetail",operationType:…}
#
# so every operation's id is findable in one pass. `Scan.pairs` does that pass
# and writes `Name=Id<newline>` per record into one small string, which
# `Scan.lookup` then reads a name out of. Reading four ids from the collected
# text costs four short scans; walking the document once per name would cost four
# passes over a megabyte.
#
# The six states are an argument rather than six defs, because Bend forbids
# mutual recursion. They are:
#
#   0  seeking `queryId:"`                 test: the suffix starts with it
#   1  skipping to the quote that opens the id      test: the head is a quote
#   2  collecting the id                            test: the head is a quote
#   3  testing for `,operationName:"`      test: the suffix starts with it
#   4  skipping to the quote that opens the name    test: the head is a quote
#   5  collecting the name                          test: the head is a quote
#
# `here` is the test for the current position under the current state, computed
# by the caller for the first step and by this def for each step after. Every
# recursive call is on `t`, one character further along.
def Scan.pairs(s: String, +mode: Nat, +id: String, +name: String, +out: String, +here: Bool) -> String:
  match s:
    case SNil{}:
      out
    case SCon{+h, +t}:
      match mode:
        case 0n:
          match here:
            case True{}:
              Scan.pairs(t, 1n, id, name, out, Scan.head_is(t, Scan.quote()))
            case False{}:
              Scan.pairs(t, 0n, id, name, out, Scan.starts(t, Scan.opening()))
        case 1n:
          match here:
            case True{}:
              Scan.pairs(t, 2n, id, name, out, Scan.head_is(t, Scan.quote()))
            case False{}:
              Scan.pairs(t, 1n, id, name, out, Scan.head_is(t, Scan.quote()))
        case 2n:
          match here:
            case True{}:
              Scan.pairs(t, 3n, id, name, out, Scan.starts(t, Scan.name_lead()))
            case False{}:
              Scan.pairs(t, 2n, Scan.append_char(id, h), name, out, Scan.head_is(t, Scan.quote()))
        case 3n:
          match here:
            case True{}:
              Scan.pairs(t, 4n, id, name, out, Scan.head_is(t, Scan.quote()))
            case False{}:
              Scan.pairs(t, 0n, SNil{}, SNil{}, out, Scan.starts(t, Scan.opening()))
        case 4n:
          match here:
            case True{}:
              Scan.pairs(t, 5n, id, name, out, Scan.head_is(t, Scan.quote()))
            case False{}:
              Scan.pairs(t, 4n, id, name, out, Scan.head_is(t, Scan.quote()))
        case _:
          match here:
            case True{}:
              Scan.pairs(t, 0n, SNil{}, SNil{}, Scan.pair_out(out, name, id), Scan.starts(t, Scan.opening()))
            case False{}:
              Scan.pairs(t, 5n, id, Scan.append_char(name, h), out, Scan.head_is(t, Scan.quote()))

def Scan.pairs_of(+js: String) -> String:
  Scan.pairs(js, 0n, SNil{}, SNil{}, SNil{}, Scan.starts(js, Scan.opening()))

# The id recorded for `+name`, or nothing when that name was not in the bundle.
def Scan.lookup(pairs: String, +name: String) -> Maybe<&2, String>:
  Scan.after(
    pairs,
    SCon{Scan.newline(), SNil{}} ++ name ++ SCon{Scan.equals(), SNil{}},
    Scan.newline(),
    256n
  )

def Scan.token_or_nothing(found: Maybe<&2, String>) -> String:
  match found:
    case None{}:
      SNil{}
    case Some{s}:
      s

def Scan.looked_up(pairs: String, +name: String) -> String:
  Scan.token_or_nothing(Scan.lookup(pairs, name))

# ── readings that are not a scan ────────────────────────────────────────

# Every character a digit. Used to read the byte counts `sqlite3`'s `writefile`
# answers with, and to refuse anything else a stand-in might print.
def Scan.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      Bool.and(Char.is_digit(h), Scan.digits(t))

# A derived key with its separators removed: `openssl kdf` prints `AA:BB:…` and
# the cipher wants `AABB…`. The value is 32 characters, so the two string
# primitives that are not tail-recursive are safe here in a way they would not be
# on the document: this is not a scan over anything large.
def Scan.uncolon(+s: String) -> String:
  String.join(String.split(s, Scan.colon()), SNil{})

# ── the directory part of a path ────────────────────────────────────────

def Scan.slash() -> Char:
  '/'

def Scan.slash_str() -> String:
  "/"

# One character of a path, kept while the rest of the path still holds a `/`: what
# survives the walk is everything before the last slash. A path is short, so
# `String.contains` over the tail is the cheap way to ask; the megabyte walks above
# are the reason the cost is worth naming at all.
def Scan.dir_step(ahead: Bool, +acc: String, +c: Char) -> String:
  match ahead:
    case True{}:
      Scan.append_char(acc, c)
    case False{}:
      acc

def Scan.dir_walk(rest: String, acc: String) -> String:
  match rest:
    case SNil{}:
      acc
    case SCon{+h, +t}:
      Scan.dir_walk(t, Scan.dir_step(String.contains(t, Scan.slash_str()), acc, h))

# A path that is a name at the root -- `/settings.json` -- walks to nothing, but its
# directory is `/` and not the empty string: an empty directory is what a run with
# no directory at all has, and the interpreter must not try to make it.
def Scan.dir_or_root(both: Bool, +got: String) -> String:
  match both:
    case True{}:
      Scan.slash_str()
    case False{}:
      got

# The directory part of a path, or nothing when it names one with no `/` in it. The
# interpreter uses this to make the directory a file is about to be written into: the
# settings cache's default path is `$HOME/.config/bird/settings.json`, and where
# `~/.config/bird` has never been made the write fails with the OS naming the file
# rather than the directory that is missing.
def Scan.dir_of(+s: String, acc: String) -> String:
  +got : String = Scan.dir_walk(s, acc)
  Scan.dir_or_root(Bool.and(String.is_empty(got), Scan.head_is(s, Scan.slash())), got)
