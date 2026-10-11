import Base
import ./domain.bend as D
import ./json.bend as J
import ./api.bend as Api

# What the run prints, as data. Pure: a finished model in, the commands that say
# what happened out. The interpreter runs them, which is why nothing here writes
# to a terminal itself and why the whole rendering is testable without one.
#
# Two shapes, and the choice between them is `OutMode`, decided when the settings
# resolved rather than here:
#
# * `--json` puts one envelope on stdout and nothing else, because a caller that
#   branches on `error.id` should never have to parse prose or skip a log line.
# * a terminal gets the data, indented. X answers with kilobytes of nested JSON;
#   one line of it is not readable, and a reader is what a terminal is for.
#
# The exit code is part of the same contract: 0 when the run finished, and the
# error's own code when it did not, so a shell can branch without reading either
# shape.

def View.cfg_of(+m: D.Model) -> D.RunCfg:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      cfg

def View.phase_of(+m: D.Model) -> D.Phase:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      phase

def View.payload_of(+m: D.Model) -> J.Json:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      payload

def View.status_of(+m: D.Model) -> U32:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      status

def View.body_of(+m: D.Model) -> String:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      body

def View.exit_of(+m: D.Model) -> U32:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      exit_code

def View.notes_of(+m: D.Model) -> List<&2, String>:
  match m:
    case D.Model{phase, start, cfg, status, payload, body, exit_code, notes}:
      notes

def View.out_of(+cfg: D.RunCfg) -> D.OutMode:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      out

def View.verb_of(+cfg: D.RunCfg) -> D.Verb:
  match cfg:
    case D.RunCfg{verb, out, dry_run, engine, creds, op_create_tweet, op_tweet_detail, op_search, op_bookmarks, op_viewer, web_bearer, gql_features, api_base, timeout_ms, media_upload_base, gql_base, mentions_url}:
      verb

# ── the envelope ────────────────────────────────────────────────────────

# `retryable` is part of the contract, not advice: it is true for exactly
# `rate_limited`, `network` and `upstream`, so an agent that backs off and retries
# reads one boolean instead of keeping its own copy of that table. Nothing in a
# run retries by itself (see the record's non-goals); the caller decides.
def View.envelope(+m: D.Model, +e: D.Error) -> J.Json:
  match e:
    case D.Error{code, message, hint}:
      J.obj_of(J.pairs5(
        J.pair("ok", J.of_bool(False{})),
        J.pair("error", J.obj_of(J.pairs4(
          J.pair("id", J.of_str(D.ErrCode.id(code))),
          J.pair("message", J.of_str(message)),
          J.pair("hint", J.of_str(hint)),
          J.pair("retryable", J.of_bool(D.ErrCode.retryable(code)))
        ))),
        J.pair("status", J.of_u32(View.status_of(m))),
        J.pair("body", J.of_str(View.body_of(m))),
        J.pair("notes", Api.Api.strings_json(View.notes_of(m), Nil{}))
      ))

# No verb is named here: a usage error is often raised before the command line
# named one, and an envelope that guessed would be worse than one that does not
# claim to know.
def View.ok_envelope(+m: D.Model) -> J.Json:
  J.obj_of(J.pairs5(
    J.pair("ok", J.of_bool(True{})),
    J.pair("verb", J.of_str(D.Verb.name(View.verb_of(View.cfg_of(m))))),
    J.pair("status", J.of_u32(View.status_of(m))),
    J.pair("data", View.payload_of(m)),
    J.pair("notes", Api.Api.strings_json(View.notes_of(m), Nil{}))
  ))

# ── what a terminal sees ────────────────────────────────────────────────

# X wraps everything in `data`, and that member is what a reader wants: the
# envelope around it is X's business, not the user's.
def View.human_field(found: Maybe<&2, J.Json>, +j: J.Json) -> String:
  match found:
    case Some{data}:
      J.pretty(data)
    case None{}:
      J.pretty(j)

def View.human_shape(is_obj: Bool, +j: J.Json) -> String:
  match is_obj:
    case True{}:
      View.human_field(J.get(j, "data"), j)
    case False{}:
      J.pretty(j)

# The manual answers with a string rather than a document, so it is printed as
# itself instead of quoted. Everything else answers with a document and is
# indented.
def View.human_text(found: Maybe<&2, String>, +j: J.Json) -> String:
  match found:
    case Some{s}:
      s
    case None{}:
      View.human_shape(J.is_obj(j), j)

# ── a tweet, for a person ──────────────────────────────────────────────
#
# A read answers with the tweets X sent, and a list of tweets is the one payload a
# person reads at a terminal. Printing it as indented JSON answers a terminal with
# brackets and quotes around the two things the reader came for, so the tweets get
# a block each instead, and every other payload keeps the indent rendering above.
#
# What a block leaves out is as deliberate as what it holds: a field X did not
# send drops out of its line rather than rendering as an empty slot, so a line
# reads as a sentence instead of a form. What it never leaves out is a count that
# was sent: `0 likes` and no likes line at all are different answers.

# The separator is a parameter because one fold joins the parts of a line with a
# dot and the lines of a block with a newline.
def View.joined_together(blank_a: Bool, blank_b: Bool, +sep: String, +a: String, +b: String) -> String:
  match blank_a:
    case True{}:
      b
    case False{}:
      match blank_b:
        case True{}:
          a
        case False{}:
          a ++ sep ++ b

def View.joined(+sep: String, +a: String, +b: String) -> String:
  View.joined_together(String.is_empty(a), String.is_empty(b), sep, a, b)

def View.folded(+sep: String, +parts: List<&2, String>, +acc: String) -> String:
  match parts:
    case Nil{}:
      acc
    case +h <> rest:
      View.folded(sep, rest, View.joined(sep, acc, h))

# Conses only what there is: the parts of a line are written outermost first, so
# `kept(a, kept(b, kept(c, Nil{})))` reads as `a b c`.
def View.kept_on(+empty: Bool, +s: String, +acc: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      acc
    case False{}:
      s <> acc

def View.kept(+s: String, +acc: List<&2, String>) -> List<&2, String>:
  View.kept_on(String.is_empty(s), s, acc)

def View.at_handle_on(+blank: Bool, +handle: String) -> String:
  match blank:
    case True{}:
      ""
    case False{}:
      "@" ++ handle

def View.at_handle(+handle: String) -> String:
  View.at_handle_on(String.is_empty(handle), handle)

# `@handle name · time`, with whichever of the three X sent. The author can be
# absent -- a mention whose user is not in the map beside it -- and then the line
# is the parts that are there rather than a placeholder for the parts that are not.
def View.head_parts(+t: J.Json) -> List<&2, String>:
  +author : J.Json = J.get_or_null(t, "author")
  +handle : String = View.at_handle(J.text(J.get_or_null(author, "handle")))
  +name : String = J.text(J.get_or_null(author, "name"))
  +when : String = J.text(J.get_or_null(t, "created_at"))
  View.kept(handle, View.kept(name, View.kept(when, Nil{})))

def View.count_text(+missing: Bool, +v: J.Json, +label: String) -> String:
  match missing:
    case True{}:
      ""
    case False{}:
      label ++ " " ++ J.show(v)

def View.count_part(+m: J.Json, +key: String, +label: String) -> String:
  +v : J.Json = J.get_or_null(m, key)
  View.count_text(J.is_null(v), v, label)

# The id first, then the counts X sent, in the order a timeline shows them.
def View.info_parts(+t: J.Json) -> List<&2, String>:
  +m : J.Json = J.get_or_null(t, "metrics")
  View.kept("id " ++ J.text(J.get_or_null(t, "id")),
    View.kept(View.count_part(m, "replies", "replies"),
      View.kept(View.count_part(m, "retweets", "retweets"),
        View.kept(View.count_part(m, "likes", "likes"),
          View.kept(View.count_part(m, "quotes", "quotes"),
            View.kept(View.count_part(m, "bookmarks", "bookmarks"),
              View.kept(View.count_part(m, "views", "views"), Nil{})))))))

def View.alt_part_on(+blank: Bool, +alt: String) -> String:
  match blank:
    case True{}:
      ""
    case False{}:
      "alt: " ++ alt

def View.alt_part(+alt: String) -> String:
  View.alt_part_on(String.is_empty(alt), alt)

def View.media_line(+m: J.Json) -> String:
  +kind : String = J.text(J.get_or_null(m, "type"))
  +url : String = J.text(J.get_or_null(m, "url"))
  +alt : String = J.text(J.get_or_null(m, "alt"))
  "media " ++ View.folded(" ", View.kept(kind, View.kept(url, View.kept(View.alt_part(alt), Nil{}))), "")

def View.media_lines(+xs: List<&2, J.Json>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +h <> rest:
      View.media_lines(rest, View.media_line(h) <> acc)

def View.quote_body_on(+blank: Bool, +handle: String, +text: String) -> String:
  match blank:
    case True{}:
      text
    case False{}:
      handle ++ ": " ++ text

def View.quote_body(+handle: String, +text: String) -> String:
  View.quote_body_on(String.is_empty(handle), handle, text)

def View.quote_on(+none: Bool, +q: J.Json) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "quoting " ++ View.quote_body(View.at_handle(J.text(J.get_or_null(J.get_or_null(q, "author"), "handle"))), J.text(J.get_or_null(q, "text")))

def View.quote_line(+t: J.Json) -> String:
  +q : J.Json = J.get_or_null(t, "quoted")
  View.quote_on(J.is_null(q), q)

def View.reply_line_on(+none: Bool, +to: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "in reply to " ++ to

def View.reply_line(+t: J.Json) -> String:
  +to : String = J.text(J.get_or_null(t, "in_reply_to"))
  View.reply_line_on(String.is_empty(to), to)

# The head and the text, then one line per attachment, then the quote, the reply
# target and the line of counts. `List.append` is what puts the variable-length
# middle between the two fixed ends.
def View.tweet_lines(+t: J.Json) -> List<&2, String>:
  +head : String = View.folded(" · ", View.head_parts(t), "")
  +text : String = J.text(J.get_or_null(t, "text"))
  +media : List<&2, String> = View.media_lines(J.items(J.get_or_null(t, "media")), Nil{})
  +tail : List<&2, String> = View.kept(View.quote_line(t), View.kept(View.reply_line(t), View.kept(View.folded(" · ", View.info_parts(t), ""), Nil{})))
  List.append(&2, String, List.append(&2, String, head <> (text <> Nil{}), media), tail)

def View.blocks(+xs: List<&2, J.Json>, +acc: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      View.folded("\n\n", List.reverse(&2, String, acc), "")
    case +h <> rest:
      View.blocks(rest, View.folded("\n", View.tweet_lines(h), "") <> acc)

# A page of nothing is worth saying: an answer with no tweet in it printed as an
# empty terminal is indistinguishable from a run that failed quietly.
def View.blocks_on(+empty: Bool, +xs: List<&2, J.Json>) -> String:
  match empty:
    case True{}:
      "no tweets"
    case False{}:
      View.blocks(xs, Nil{})

def View.if_array(+yes: Bool, +xs: J.Json) -> Maybe<&2, J.Json>:
  match yes:
    case True{}:
      Some{xs}
    case False{}:
      None{}

# The fold answers a read with `{"tweets": [...]}`, and that is the one payload a
# person reads as a list. Every other payload -- a profile, a write's null, the
# envelope `--raw` asked for -- keeps the rendering above it.
def View.tweets_found(found: Maybe<&2, J.Json>, +j: J.Json) -> Maybe<&2, J.Json>:
  match found:
    case Some{+xs}:
      View.if_array(J.is_arr(xs), xs)
    case None{}:
      None{}

def View.tweets_in(+j: J.Json) -> Maybe<&2, J.Json>:
  View.tweets_found(J.get(j, "tweets"), j)

def View.tweets_or_text(found: Maybe<&2, J.Json>, +j: J.Json) -> String:
  match found:
    case Some{xs}:
      +list : List<&2, J.Json> = J.items(xs)
      View.blocks_on(List.is_empty(&2, J.Json, list), list)
    case None{}:
      View.human_text(J.text_of(j), j)

def View.human_or_tweets(+j: J.Json) -> String:
  View.tweets_or_text(View.tweets_in(j), j)

# `null` is a run that did something rather than fetched something: a write, or
# `check`. Saying so beats printing nothing and leaving the reader unsure whether
# it worked.
def View.human_null(is_null: Bool, +j: J.Json) -> String:
  match is_null:
    case True{}:
      "ok"
    case False{}:
      View.human_or_tweets(j)

def View.human_any(+j: J.Json) -> String:
  View.human_null(J.is_null(j), j)

def View.human(+m: D.Model) -> String:
  View.human_any(View.payload_of(m))

def View.with_hint_on(blank: Bool, +message: String, +hint: String) -> String:
  match blank:
    case True{}:
      "bird: " ++ message
    case False{}:
      "bird: " ++ message ++ "\n  " ++ hint

def View.with_hint(+message: String, +hint: String) -> String:
  View.with_hint_on(String.is_empty(hint), message, hint)

def View.human_error(+e: D.Error) -> String:
  match e:
    case D.Error{code, message, hint}:
      View.with_hint(message, hint)

# ── the commands ────────────────────────────────────────────────────────

# One note per line on stderr, so a warning never lands in the middle of the data
# a script is reading from stdout.
def View.note_cmds(+notes: List<&2, String>) -> List<&2, D.Cmd>:
  match notes:
    case Nil{}:
      Nil{}
    case +h <> rest:
      D.Cmd.print_err(h ++ "\n") <> View.note_cmds(rest)

def View.json_cmds(+phase: D.Phase, +m: D.Model) -> List<&2, D.Cmd>:
  match phase:
    case D.PhaseFailed{error}:
      D.Cmd.print(J.show(View.envelope(m, error)) ++ "\n") <> (D.Cmd.exit(View.exit_of(m), SNil{}) <> Nil{})
    case _:
      D.Cmd.print(J.show(View.ok_envelope(m)) ++ "\n") <> Nil{}

def View.text_cmds(+phase: D.Phase, +m: D.Model) -> List<&2, D.Cmd>:
  match phase:
    case D.PhaseFailed{error}:
      D.Cmd.print_err(View.human_error(error) ++ "\n") <> (D.Cmd.exit(View.exit_of(m), SNil{}) <> Nil{})
    case _:
      D.Cmd.print(View.human(m) ++ "\n") <> View.note_cmds(View.notes_of(m))

def View.by_mode(out: D.OutMode, +phase: D.Phase, +m: D.Model) -> List<&2, D.Cmd>:
  match out:
    case D.OutAgent{}:
      View.json_cmds(phase, m)
    case D.OutHuman{}:
      View.text_cmds(phase, m)

def View.commands(+m: D.Model) -> List<&2, D.Cmd>:
  View.by_mode(View.out_of(View.cfg_of(m)), View.phase_of(m), m)
