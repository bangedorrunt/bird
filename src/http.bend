import Base
import ./domain.bend as D
import ./policy.bend as P

# The transport, described rather than performed. One request becomes one argv
# for curl, and curl's answer is split back into a status and a body. No IO
# lives here, so every rule below is checkable from a test without a network.
#
# curl is run through `Process.run`, which takes literal arguments and starts
# the executable directly -- no shell sees these strings, so a tweet's text
# cannot turn into a command and none of it needs quoting.

# ── the answer ──────────────────────────────────────────────────────────

type Resp is Data:
  Resp{
    http_status: U32,
    body: String,
  }

# The width of the status curl appends. HTTP status codes are always three
# digits, so the split is positional: the last three bytes of stdout are the
# status and everything before them is the body. No marker string is involved,
# which is why a body cannot forge one.
def Http.status_width() -> Nat:
  3n

def Http.default_status(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{n}:
      n
    case None{}:
      0

def Http.status_of(text: String) -> U32:
  Http.default_status(U32.read(text))

# The status is the last three characters curl wrote and the body is everything
# before them. curl appends its `--write-out` output, so the split is positional,
# and done the obvious way -- `String.take` for the body -- it costs the one
# resource that runs out. `String.take` is not tail-recursive: it builds its result
# on the way back up, so a 138 KB tweet cost one stack frame per character and took
# the program down with "memory fault (machine stack overflow?)" the first time a
# real read ran. `String.drop` and `String.reverse` both recurse with an
# accumulator, so the walk below pays in heap instead of stack.
#
# `String.length` is skipped for the same reason, which is why there is no
# length check: a string too short to hold a status simply reverses to a status of
# 0 and an empty body, and 0 is already what "curl wrote no response" means.
def Http.from_reversed(+rev: String) -> Resp:
  Resp{
    Http.status_of(String.reverse(String.take(rev, Http.status_width()))),
    String.reverse(String.drop(rev, Http.status_width()))
  }

def Http.width_of(s: String, acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      Http.width_of(t, 1n+acc)

# A status of 0 means curl wrote nothing: the request failed before a response
# arrived, and the caller should read `Http.transport_error` rather than the
# status. An answer too short to hold a status is that case, and it keeps its whole
# text as the body rather than being read as a status.
#
# The count is written out here instead of calling `String.length`, which is the
# same not-tail-recursive shape as `String.take`: counting a 138 KB body that way
# is another frame per character.
def Http.reply_on(long_enough: Bool, +raw: String) -> Resp:
  match long_enough:
    case False{}:
      Resp{0, raw}
    case True{}:
      Http.from_reversed(String.reverse(raw))

def Http.reply(+raw: String) -> Resp:
  Http.reply_on(Nat.is_ge(Http.width_of(raw, 0n), Http.status_width()), raw)

# ── the request as argv ─────────────────────────────────────────────────

def Http.header_line(name: String, +value: String) -> String:
  name ++ ": " ++ value

def Http.header_args(+h: D.Header) -> List<&2, String>:
  match h:
    case D.Header{name, value}:
      "-H" <> (Http.header_line(name, value) <> Nil{})

def Http.header_appends(+hs: List<&2, D.Header>, +acc: List<&2, String>) -> List<&2, String>:
  match hs:
    case Nil{}:
      acc
    case +h <> rest:
      Http.header_appends(rest, List.append(&2, String, acc, Http.header_args(h)))

def Http.pick_secs(at_least_one: Bool, seconds: U32) -> U32:
  match at_least_one:
    case True{}:
      seconds
    case False{}:
      1

# `--max-time` counts seconds and 0 means no limit at all, which is the
# opposite of a timeout, so a sub-second budget still has to be 1.
def Http.seconds(+ms: U32) -> U32:
  Http.pick_secs(U32.is_ge(ms, 1000), U32.div(ms, 1000))

def Http.timeout_args(ms: U32) -> List<&2, String>:
  "--max-time" <> (U32.show(Http.seconds(ms)) <> Nil{})

# An empty body gets no `-d` at all: `-d ""` would turn a GET into a POST.
def Http.body_on(empty: Bool, body: String) -> List<&2, String>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      "-d" <> (body <> Nil{})

# A multipart form. `-F` does the encoding and streams a `@path` itself, so a
# file never has to fit in an argument or in this process's memory.
#
# The pair is prepended value-then-flag because the accumulator is reversed on the
# way out: writing it flag-then-value put `-F` *after* its own argument, and curl
# answered "option -F: is badly used here" on the first live upload. The offline
# tests only ever looked at the parts list, which was right either way, so only a
# real request caught it.
def Http.part_args(+parts: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +h <> rest:
      Http.part_args(rest, h <> ("-F" <> acc))

# A request carries either a literal body or a multipart form; parts win because
# a request that has them was built for them.
def Http.data_on(has_parts: Bool, +parts: List<&2, String>, +body: String) -> List<&2, String>:
  match has_parts:
    case True{}:
      Http.part_args(parts, Nil{})
    case False{}:
      Http.body_on(String.is_empty(body), body)

def Http.program() -> String:
  "curl"

# No program in here. `Process.run` takes the program as its own argument, so an
# argv list that began with "curl" handed curl a *url* of "curl": it fetched that,
# failed, and then fetched the real url as a second one, which is how a live run
# came back with a status of 000 and a body with the status glued to its head.
def Http.base_args(method: String, url: String) -> List<&2, String>:
  "-sS" <> (url <> ("-X" <> (method <> Nil{})))

# `--write-out` appends to stdout after the body, so the status is glued to the
# end of the response and split off positionally. -sS keeps the progress meter
# quiet but still reports a transport error on stderr.
def Http.wout_args() -> List<&2, String>:
  "--write-out" <> ("%{http_code}" <> Nil{})

def Http.assemble(
  method: String,
  url: String,
  headers: List<&2, D.Header>,
  +body: String,
  +parts: List<&2, String>,
  timeout_ms: U32
) -> List<&2, String>:
  List.append(&2, String,
    List.append(&2, String,
      List.append(&2, String,
        List.append(&2, String,
          Http.base_args(method, url),
          Http.header_appends(headers, Nil{})),
        Http.timeout_args(timeout_ms)),
      Http.data_on(Bool.not(List.is_empty(&2, String, parts)), parts, body)),
    Http.wout_args())

# The arguments curl is handed, without the program in front: what `Process.run`
# is given, after the program.
def Http.args(req: D.HttpReq) -> List<&2, String>:
  match req:
    case D.HttpReq{method, url, headers, body, parts, timeout_ms}:
      Http.assemble(method, url, headers, body, parts, timeout_ms)

# The same arguments with the program in front, which is what `--dry-run` prints:
# a command that can be pasted into a shell to inspect the request by hand.
def Http.argv(req: D.HttpReq) -> List<&2, String>:
  Http.program() <> Http.args(req)

# ── failures ────────────────────────────────────────────────────────────

def Http.words(+status: U32) -> String:
  match status:
    case 6:
      "curl could not resolve the host"
    case 7:
      "curl could not connect"
    case 26:
      "curl could not read the file it was told to send"
    case 28:
      "curl timed out"
    case 35:
      "curl could not complete the TLS handshake"
    case 37:
      "curl could not read the file it was told to send"
    case 52:
      "curl got an empty reply"
    case 56:
      "curl failed while receiving the response"
    case _:
      "curl failed"

# A local file curl could not read is not a network failure. The only file in any
# request this program builds is an attachment (`-F media=@path`, see
# `Api.upload_cmd`), and a path that is not there will not be there on the next
# attempt either. Reported as `network` it set `retryable`, which is an invitation
# to retry a missing file forever; the caller wrote the path, so it is a usage
# error. curl's exit 26 is a read error and 37 is a file it could not open, and
# only the upload road can produce either.
def Http.local_file_error(+curl_status: U32) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    Http.words(curl_status),
    "curl exit " ++ U32.show(curl_status) ++ ": check the --media path"
  )

# curl statuses that mean the request had already left this machine when it failed:
# the send happened and the answer never came back. 28 is the budget running out on
# a request curl had sent, 52 is a peer that accepted the request and answered with
# nothing, 56 is an answer that died part way through. 6, 7 and 35 (could not
# resolve, could not connect, handshake failed) are deliberately NOT here: nothing
# was sent, so the call can simply be made again.
def Http.lost_status(+curl_status: U32) -> Bool:
  match curl_status:
    case 28:
      True{}
    case 52:
      True{}
    case 56:
      True{}
    case _:
      False{}

# The hint for the one case where "try again" is not safe advice, so it says what is
# actually known and what to do about it. A caller that follows this checks the
# account and finds the post it was about to make a second time.
def Http.lost_hint(+curl_status: U32) -> String:
  "curl exit " ++ U32.show(curl_status) ++ ": the request was sent and the answer was lost; check the account before retrying, the post may already be there"

def Http.transport_plain(+curl_status: U32) -> D.Error:
  D.err_hint(
    D.ErrNetwork{},
    Http.words(curl_status),
    "curl exit " ++ U32.show(curl_status)
  )

def Http.transport_lost(+curl_status: U32) -> D.Error:
  D.err_unknown(D.ErrNetwork{}, Http.words(curl_status), Http.lost_hint(curl_status))

# `maybe_applied` is decided by the caller, because only the caller knows whether the
# verb writes: the same curl status is a plain retryable network failure on a read
# and an unknown outcome on a post.
def Http.transport_failed_on(maybe_applied: Bool, +curl_status: U32) -> Maybe<&2, D.Error>:
  match maybe_applied:
    case True{}:
      Some{Http.transport_lost(curl_status)}
    case False{}:
      Some{Http.transport_plain(curl_status)}

def Http.transport_failed(writes: Bool, +curl_status: U32) -> Maybe<&2, D.Error>:
  match curl_status:
    case 26:
      Some{Http.local_file_error(curl_status)}
    case 37:
      Some{Http.local_file_error(curl_status)}
    case _:
      Http.transport_failed_on(Bool.and(writes, Http.lost_status(curl_status)), curl_status)

# curl's own exit status, not the HTTP status: 0 means a response arrived and
# the HTTP status is worth reading, anything else means it did not. `writes` is the
# verb's own answer to "does this request change anything", and it is what decides
# whether a lost answer leaves the outcome unknown.
def Http.transport_error_on(writes: Bool, ok: Bool, +curl_status: U32) -> Maybe<&2, D.Error>:
  match ok:
    case True{}:
      None{}
    case False{}:
      Http.transport_failed(writes, curl_status)

def Http.transport_error(writes: Bool, +curl_status: U32) -> Maybe<&2, D.Error>:
  Http.transport_error_on(writes, U32.is_zero(curl_status), curl_status)

# An error message printed whole can be a page of JSON, so the response's own
# words are cut to something a person can read in a terminal.
def Http.excerpt(body: String) -> String:
  String.take(body, 300n)

def Http.status_hint(+status: U32) -> String:
  match status:
    case 401:
      "the session is missing or expired: check --auth-token and --ct0"
    case 403:
      "X refused the request: the account may be locked"
    case 404:
      "the tweet may be deleted, or the id may be wrong"
    case 429:
      "X is rate limiting this account: back off before retrying"
    case _:
      "the body carries X's own message"

# A response that arrived is still a failure when the status says so, and the
# code comes from the same table the rest of the program uses, so an agent sees
# one vocabulary for every failure.
def Http.status_error_on(bad: Bool, +http_status: U32, body: String) -> Maybe<&2, D.Error>:
  match bad:
    case False{}:
      None{}
    case True{}:
      Some{D.err_hint(
        P.ErrCode.of_status(http_status),
        Http.excerpt(body),
        Http.status_hint(http_status)
      )}

def Http.status_error(resp: Resp) -> Maybe<&2, D.Error>:
  match resp:
    case Resp{+http_status, body}:
      Http.status_error_on(U32.is_ge(http_status, 400), http_status, body)
