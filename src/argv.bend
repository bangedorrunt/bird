import Base
import ./domain.bend as D
# `P` rather than `Cfg`: policy.bend names its own defs `Cfg.count`, `Media.…`,
# `ErrCode.…`, so the import alias is one more level, not a replacement.
import ./policy.bend as P
import ./json.bend as J

# The command line, turned into `Item`s. Nothing here touches IO or the network:
# a token list goes in, a token list plus at most one usage error comes out, so
# every parse rule is exercisable from a test without a shell.
#
# Two Bend rules shape this file, and they are why it is not one tidy loop:
#   - a `match` may only scrutinise a parameter or a field, never a computed
#     value, so every branch on a *derived* fact is routed through a def that
#     takes that fact as its own parameter and matches on it;
#   - a def may not be called before it is defined, so the parser cannot be
#     split into mutually recursive "state machine" pieces.
# Hence: classify each token into a `Tok` up front, then walk the classified
# list in a single self-recursive def that only ever matches constructors.

# ── what a token can be, and how a flag is spelled ──────────────────────

# The arity of a flag, decided once, from the name. `FkUnknown` is how a typo
# gets caught: an unrecognised `--flag` is an error rather than an ignored
# argument, because an agent that misspells `--text-file` and gets silence has
# no way to tell that from a request that genuinely said nothing.
type FlagKind is Data:
  FkValue{}
  FkSwitch{}
  FkMedia{}
  FkAlt{}
  FkUnknown{}

# How a flag consumes its value, worked out at classification time so the walk
# can match the plan as a plain field instead of deriving it again.
type Act is Data:
  ActValue{
    value: String,
  }
  ActNextValue{}
  ActNone{}
  ActBad{
    error: D.Error,
  }

type Tok is Data:
  TokVerb{
    verb: D.Verb,
    wants_target: Bool,
  }
  TokFlag{
    kind: FlagKind,
    name: String,
    act: Act,
  }
  TokText{
    text: String,
  }

# The outcome of a parse: either the items, or the first usage error. A bad
# command line is a user error, never a network one, so it is reported before
# anything is read or sent.
type Argv is Data:
  ArgvOk{
    items: List<&2, D.Item>,
  }
  ArgvBad{
    error: D.Error,
  }

# ── errors ──────────────────────────────────────────────────────────────

def Argv.unknown_flag_error(name: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "unknown flag " ++ name,
    "run `bird help` for the flags this build accepts"
  )

def Argv.unknown_verb_error(word: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    "unknown verb or stray argument " ++ word,
    "run `bird help` for the verbs, or quote the text and pass it after --text"
  )

def Argv.missing_value_error(+name: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    name ++ " needs a value",
    "write " ++ name ++ " <value>, or " ++ name ++ "=<value>"
  )

def Argv.missing_target_error(+name: String) -> D.Error:
  D.err_hint(
    D.ErrUsage{},
    name ++ " needs an argument",
    "bird " ++ name ++ " <tweet-id-or-url>"
  )

# ── strings ─────────────────────────────────────────────────────────────

def Argv.is_flag(tok: String) -> Bool:
  String.starts_with(tok, "--")

def Argv.head_or(parts: List<&2, String>, fallback: String) -> String:
  match parts:
    case Nil{}:
      fallback
    case +h <> _:
      h

# `--engine=auto` splits to ["--engine", "auto"]; `--json` splits to ["--json"].
# Leading dashes are part of the name, so the name is the whole first part.
def Argv.name_of(+tok: String) -> String:
  Argv.head_or(String.split(tok, '='), tok)

def Argv.parts_tail(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      Nil{}
    case +_ <> t:
      t

def Argv.inline_parts(rest: List<&2, String>) -> Maybe<&2, String>:
  match rest:
    case Nil{}:
      None{}
    case +_ <> _:
      Some{String.join(rest, "=")}

# Everything after the first `=` is the value, `=` and all: `--text a=b` means
# the text "a=b", not "a". Rejoining the tail is what keeps that true, because
# `String.split` cuts at every separator rather than just the first.
def Argv.inline_of(tok: String) -> Maybe<&2, String>:
  Argv.inline_parts(Argv.parts_tail(String.split(tok, '=')))

# ── the flag table ──────────────────────────────────────────────────────
#
# Kept in step with what policy.bend reads. A flag that is not here is refused,
# so adding a setting means adding it in both places; `tests/argv_test.bend`
# asserts that every name policy reads parses.

def Argv.kind_of(name: String) -> FlagKind:
  match name:
    case "--media":
      FkMedia{}
    case "--alt":
      FkAlt{}
    case "--json":
      FkSwitch{}
    case "--dry-run":
      FkSwitch{}
    case "--text":
      FkValue{}
    case "--text-file":
      FkValue{}
    case "--auth-token":
      FkValue{}
    case "--ct0":
      FkValue{}
    case "--engine":
      FkValue{}
    case "--count":
      FkValue{}
    case "--timeout-ms":
      FkValue{}
    case "--fixture":
      FkValue{}
    case "--sweetistics-api-key":
      FkValue{}
    case "--sweetistics-base-url":
      FkValue{}
    case "--op-create-tweet":
      FkValue{}
    case "--op-tweet-detail":
      FkValue{}
    case "--op-search":
      FkValue{}
    case "--op-viewer":
      FkValue{}
    case "--web-bearer":
      FkValue{}
    case "--gql-features":
      FkValue{}
    case "--media-upload-base":
      FkValue{}
    case "--gql-base":
      FkValue{}
    case "--mentions-url":
      FkValue{}
    case _:
      FkUnknown{}

# The flag names, in the order `bird help` and the schema print them. One list,
# so the help text cannot advertise a flag the parser refuses.
def Argv.flag_names() -> List<&2, String>:
  "--json" <> (
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
                                        "--gql-features" <> (
                                          "--media-upload-base" <> (
                                          "--gql-base" <> (
                                            "--mentions-url" <> Nil{}
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
    )
  )
def Argv.verb_of(word: String) -> Maybe<&2, D.Verb>:
  match word:
    case "tweet":
      Some{D.VerbTweet{SNil{}, Nil{}}}
    case "reply":
      Some{D.VerbReply{SNil{}, SNil{}, Nil{}}}
    case "read":
      Some{D.VerbRead{SNil{}}}
    case "replies":
      Some{D.VerbReplies{SNil{}}}
    case "thread":
      Some{D.VerbThread{SNil{}}}
    case "search":
      Some{D.VerbSearch{SNil{}, P.Cfg.default_count()}}
    case "mentions":
      Some{D.VerbMentions{P.Cfg.default_count()}}
    case "whoami":
      Some{D.VerbWhoami{}}
    case "check":
      Some{D.VerbCheck{}}
    case "help":
      Some{D.VerbHelp{}}
    case "schema":
      Some{D.VerbSchema{}}
    case "version":
      Some{D.VerbVersion{}}
    case _:
      None{}

# The one place a word becomes a verb, so `LAWS.bend` can state that every verb
# the domain can carry is reachable by typing its name: a verb added to the
# domain but not to the table above is a verb no one can ask for.
def Argv.name_of_proto(found: Maybe<&2, D.Verb>) -> String:
  match found:
    case Some{verb}:
      D.Verb.name(verb)
    case None{}:
      SNil{}

def Argv.proto_name(word: String) -> String:
  Argv.name_of_proto(Argv.verb_of(word))

# `--help`, `-h`, `--version` and `--schema` name verbs rather than switch a
# setting, so they are classified here before the flag path sees them.
def Argv.dashed_verb(tok: String) -> Maybe<&2, D.Verb>:
  match tok:
    case "--help":
      Some{D.VerbHelp{}}
    case "-h":
      Some{D.VerbHelp{}}
    case "--version":
      Some{D.VerbVersion{}}
    case "-V":
      Some{D.VerbVersion{}}
    case "--schema":
      Some{D.VerbSchema{}}
    case _:
      None{}

def Argv.verbs() -> List<&2, String>:
  "tweet" <> (
    "reply" <> (
      "read" <> (
        "replies" <> (
          "thread" <> (
            "search" <> (
              "mentions" <> (
                "whoami" <> ("check" <> ("help" <> ("schema" <> ("version" <> Nil{})))))))))))

# Whether the verb takes one positional argument: the target of a read, the
# query of a search. Everything after it, and every positional for a verb
# without one, lands on `--text`.
def Argv.has_target(v: D.Verb) -> Bool:
  match v:
    case D.VerbRead{target}:
      True{}
    case D.VerbReplies{target}:
      True{}
    case D.VerbThread{target}:
      True{}
    case D.VerbSearch{query, count}:
      True{}
    case D.VerbReply{target, text, media}:
      True{}
    case _:
      False{}

def Argv.fill(+v: D.Verb, +target: String) -> D.Verb:
  match v:
    case D.VerbRead{old}:
      D.VerbRead{target}
    case D.VerbReplies{old}:
      D.VerbReplies{target}
    case D.VerbThread{old}:
      D.VerbThread{target}
    case D.VerbSearch{old, count}:
      D.VerbSearch{target, count}
    case D.VerbReply{old, text, media}:
      D.VerbReply{target, text, media}
    case _:
      v

# ── classifying one token ───────────────────────────────────────────────

def Argv.is_known(kind: FlagKind) -> Bool:
  match kind:
    case FkUnknown{}:
      False{}
    case _:
      True{}

def Argv.needs_value(kind: FlagKind) -> Bool:
  match kind:
    case FkSwitch{}:
      False{}
    case FkUnknown{}:
      False{}
    case _:
      True{}

# The Item a flag produces. Media and alt paths are their own constructors
# because the media policy reads them as a list, not as a named setting.
# ── how a flag consumes its value ───────────────────────────────────────
#
# `is_known` and `needs_value` are computed from the kind, and Bend will not let
# a `match` scrutinise a computed value, so each is passed in as a parameter and
# matched there instead.

def Argv.act_known(needs: Bool, inline: Maybe<&2, String>) -> Act:
  match needs:
    case False{}:
      ActNone{}
    case True{}:
      match inline:
        case Some{v}:
          ActValue{v}
        case None{}:
          ActNextValue{}

def Argv.act(known: Bool, kind: FlagKind, name: String, inline: Maybe<&2, String>) -> Act:
  match known:
    case False{}:
      ActBad{Argv.unknown_flag_error(name)}
    case True{}:
      Argv.act_known(Argv.needs_value(kind), inline)

def Argv.item_for(kind: FlagKind, name: String, value: String) -> D.Item:
  match kind:
    case FkMedia{}:
      D.ItemMedia{value}
    case FkAlt{}:
      D.ItemAlt{value}
    case _:
      D.ItemFlag{name, value}

# Whether the verb still owes a positional is decided here, once, so the walk
# can read it as a field.
def Argv.verb_tok(+verb: D.Verb) -> Tok:
  TokVerb{verb, Argv.has_target(verb)}

def Argv.by_bare_verb(found: Maybe<&2, D.Verb>, +tok: String) -> Tok:
  match found:
    case Some{verb}:
      Argv.verb_tok(verb)
    case None{}:
      TokText{tok}

def Argv.kind_tok(+kind: FlagKind, +tok: String) -> Tok:
  TokFlag{
    kind,
    Argv.name_of(tok),
    Argv.act(Argv.is_known(kind), kind, Argv.name_of(tok), Argv.inline_of(tok))
  }

def Argv.by_flag_shape(is_flag: Bool, +tok: String) -> Tok:
  match is_flag:
    case True{}:
      Argv.kind_tok(Argv.kind_of(Argv.name_of(tok)), tok)
    case False{}:
      Argv.by_bare_verb(Argv.verb_of(tok), tok)

def Argv.by_dashed_verb(found: Maybe<&2, D.Verb>, +tok: String) -> Tok:
  match found:
    case Some{verb}:
      Argv.verb_tok(verb)
    case None{}:
      Argv.by_flag_shape(Argv.is_flag(tok), tok)

def Argv.classify(+tok: String) -> Tok:
  Argv.by_dashed_verb(Argv.dashed_verb(tok), tok)

def Argv.classify_all(args: List<&2, String>) -> List<&2, Tok>:
  match args:
    case Nil{}:
      Nil{}
    case +a <> rest:
      Argv.classify(a) <> Argv.classify_all(rest)


# ── `--count` reaches the verb that carries it ──────────────────────────
#
# Search and mentions keep their limit inside the verb, and `--count` may be
# written before or after the verb, so it is applied to the finished item list
# rather than during the walk.

def Argv.set_verb_count(+v: D.Verb, +count: U32) -> D.Verb:
  match v:
    case D.VerbSearch{query, old}:
      D.VerbSearch{query, count}
    case D.VerbMentions{old}:
      D.VerbMentions{count}
    case _:
      v

def Argv.set_count_one(+it: D.Item, count: U32) -> D.Item:
  match it:
    case D.ItemVerb{verb}:
      D.ItemVerb{Argv.set_verb_count(verb, count)}
    case _:
      it

def Argv.set_count(items: List<&2, D.Item>, +count: U32) -> List<&2, D.Item>:
  match items:
    case Nil{}:
      Nil{}
    case +it <> rest:
      Argv.set_count_one(it, count) <> Argv.set_count(rest, count)

def Argv.finish(+a: Argv) -> Argv:
  match a:
    case ArgvOk{items}:
      ArgvOk{Argv.set_count(items, P.Cfg.count(items))}
    case ArgvBad{error}:
      a

# ── the walk ────────────────────────────────────────────────────────────
#
# One pass, left to right. `pend` holds a verb whose positional has not arrived
# yet, which is what turns `bird read 123` into a target and `bird read` into an
# error. `seen` separates "the first bare word must name a verb" from "this bare
# word is the text", which is what makes `bird tweet hi` mean `--text hi`.

def Argv.close(+acc: List<&2, D.Item>, pend: Maybe<&2, D.Verb>) -> Argv:
  match pend:
    case Some{v}:
      ArgvBad{Argv.missing_target_error(D.Verb.name(v))}
    case None{}:
      ArgvOk{List.reverse(&2, D.Item, acc)}

def Argv.walk(
  toks: List<&2, Tok>,
  +acc: List<&2, D.Item>,
  +pend: Maybe<&2, D.Verb>,
  +seen: Bool
) -> Argv:
  match toks:
    case Nil{}:
      Argv.close(acc, pend)
    case +t <> rest:
      match t:
        # `wants_target` is a field of the token and `pend` is a later parameter,
        # and Bend only allows matches in that order, so the "a previous verb
        # never got its target" check is written out in both branches.
        case TokVerb{verb, wants_target}:
          match wants_target:
            case True{}:
              match pend:
                case Some{waiting}:
                  ArgvBad{Argv.missing_target_error(D.Verb.name(waiting))}
                case None{}:
                  Argv.walk(rest, acc, Some{verb}, True{})
            case False{}:
              match pend:
                case Some{waiting}:
                  ArgvBad{Argv.missing_target_error(D.Verb.name(waiting))}
                case None{}:
                  Argv.walk(rest, D.ItemVerb{verb} <> acc, None{}, True{})
        case TokFlag{kind, name, act}:
          match act:
            case ActBad{error}:
              ArgvBad{error}
            case ActValue{value}:
              Argv.walk(rest, Argv.item_for(kind, name, value) <> acc, pend, seen)
            case ActNone{}:
              Argv.walk(rest, Argv.item_for(kind, name, "true") <> acc, pend, seen)
            case ActNextValue{}:
              match rest:
                case Nil{}:
                  ArgvBad{Argv.missing_value_error(name)}
                case +nt <> rest2:
                  match nt:
                    case TokText{word}:
                      Argv.walk(rest2, Argv.item_for(kind, name, word) <> acc, pend, seen)
                    case _:
                      ArgvBad{Argv.missing_value_error(name)}
        case TokText{text}:
          match pend:
            case Some{waiting}:
              Argv.walk(rest, D.ItemVerb{Argv.fill(waiting, text)} <> acc, None{}, seen)
            case None{}:
              match seen:
                case True{}:
                  Argv.walk(rest, D.ItemFlag{"--text", text} <> acc, None{}, True{})
                case False{}:
                  ArgvBad{Argv.unknown_verb_error(text)}

def Argv.parse(args: List<&2, String>) -> Argv:
  Argv.finish(Argv.walk(Argv.classify_all(args), Nil{}, None{}, False{}))

# ── help ────────────────────────────────────────────────────────────────

def Argv.usage() -> String:
  "bird <verb> [flags]"

# Written for the agent that reads it: what each verb does, which flags matter,
# and what the exit codes mean. `--json` is named first because a machine should
# never have to scrape the human rendering.
def Argv.help_text() -> String:
  "bird -- post and read X/Twitter\n\n"
  ++ "usage: " ++ Argv.usage() ++ "\n\n"
  ++ "verbs\n"
  ++ "  tweet [--text <text>] [--media <path>] [--alt <text>]   post a tweet\n"
  ++ "  reply <tweet-id|url> [--text <text>] [--media <path>]   reply to a tweet\n"
  ++ "  read <tweet-id|url>                                    one tweet\n"
  ++ "  replies <tweet-id|url>                                 replies to a tweet\n"
  ++ "  thread <tweet-id|url>                                  a whole thread\n"
  ++ "  search <query> [--count <n>]                           recent tweets\n"
  ++ "  mentions [--count <n>]                                 mentions of you\n"
  ++ "  whoami                                                 the signed-in account\n"
  ++ "  check                                                  whether credentials work\n"
  ++ "  help                                                   this text\n"
  ++ "  schema                                                 this, as json\n"
  ++ "  version                                                the build\n\n"
  ++ "settings\n"
  ++ "  --engine graphql|sweetistics|auto   which backend answers\n"
  ++ "  --auth-token <token> --ct0 <token>  X session cookies\n"
  ++ "  --sweetistics-api-key <key>         API key for the sweetistics backend\n"
  ++ "  --web-bearer <token>                client bearer for the graphql engine\n"
  ++ "  --gql-features <json>               graphql feature flags, they rotate\n"
  ++ "  --op-create-tweet and friends       graphql operation ids, they rotate\n"
  ++ "  --media-upload-base <url>           where X's media service lives\n"
  ++ "  --gql-base <url>                    where X's graphql endpoint lives\n"
  ++ "  --mentions-url <url>                X's mentions timeline endpoint\n"
  ++ "  --json                              one json envelope on stdout\n"
  ++ "  --dry-run                           describe the request, send nothing\n"
  ++ "  --timeout-ms <n>                    per-request timeout, 1000..120000\n\n"
  ++ "environment\n"
  ++ "  BIRD_JSON=1                         same as --json\n"
  ++ "  BIRD_CONFIG                         a json object of flag names and values\n"
  ++ "  BIRD_<flag>                         --auth-token is BIRD_AUTH_TOKEN, --count is BIRD_COUNT\n\n"
  ++ "exit codes\n"
  ++ "  0 ok   2 usage   3 auth   4 not found   5 rate limited\n"
  ++ "  6 network   7 upstream   1 internal\n"

# ── the schema ──────────────────────────────────────────────────────────
#
# `bird schema` prints this. It is built from the same tables the parser reads,
# so the manifest cannot advertise a flag or a verb the program refuses: the
# names come from `flag_names` and `verbs`, and the facts about each verb come
# from the verb itself rather than a second list to keep in step.

def Argv.kind_word(+kind: FlagKind) -> String:
  match kind:
    case FkValue{}:
      "value"
    case FkSwitch{}:
      "switch"
    case FkMedia{}:
      "media"
    case FkAlt{}:
      "alt"
    case FkUnknown{}:
      "unknown"

def Argv.flag_json(+name: String) -> J.Json:
  J.obj_of(J.pairs2(
    J.pair("name", J.of_str(name)),
    J.pair("kind", J.of_str(Argv.kind_word(Argv.kind_of(name))))
  ))

def Argv.flag_objs(+names: List<&2, String>, acc: List<&2, J.Json>) -> J.Json:
  match names:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Argv.flag_objs(rest, Argv.flag_json(h) <> acc)

def Argv.verb_json(+v: D.Verb) -> J.Json:
  J.obj_of(J.pairs3(
    J.pair("name", J.of_str(D.Verb.name(v))),
    J.pair("writes", J.of_bool(D.Verb.writes(v))),
    J.pair("network", J.of_bool(D.Verb.needs_network(v)))
  ))

def Argv.verb_obj(found: Maybe<&2, D.Verb>, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match found:
    case Some{v}:
      Argv.verb_json(v) <> acc
    case None{}:
      acc

def Argv.verb_objs(+names: List<&2, String>, acc: List<&2, J.Json>) -> J.Json:
  match names:
    case Nil{}:
      J.arr_of(List.reverse(&2, J.Json, acc))
    case +h <> rest:
      Argv.verb_objs(rest, Argv.verb_obj(Argv.verb_of(h), acc))

def Argv.code_json(+c: D.ErrCode) -> J.Json:
  J.obj_of(J.pairs2(
    J.pair("id", J.of_str(D.ErrCode.id(c))),
    J.pair("code", J.of_u32(D.ErrCode.exit_code(c)))
  ))

def Argv.code_list(+codes: List<&2, D.ErrCode>, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match codes:
    case Nil{}:
      List.reverse(&2, J.Json, acc)
    case +h <> rest:
      Argv.code_list(rest, Argv.code_json(h) <> acc)

# 0 is not an error code, so it is not in `ErrCode.all`; it leads the list here
# because it is what a caller checks for first.
def Argv.exit_codes() -> List<&2, J.Json>:
  J.obj_of(J.pairs2(J.pair("id", J.of_str("ok")), J.pair("code", J.of_u32(0)))) <> Argv.code_list(D.ErrCode.all(), Nil{})

def Argv.schema_json() -> J.Json:
  J.obj_of(J.pairs7(
    J.pair("name", J.of_str("bird")),
    J.pair("version", J.of_str(D.version())),
    J.pair("usage", J.of_str(Argv.usage())),
    J.pair("verbs", Argv.verb_objs(Argv.verbs(), Nil{})),
    J.pair("flags", Argv.flag_objs(Argv.flag_names(), Nil{})),
    # Every default the run has, not only the two numeric ones: an agent reading
    # the manifest has to be able to learn where a request will be sent without
    # guessing, and the hosts are the settings nobody types until they move.
    J.pair("defaults", J.obj_of(List.append(&2, J.JField,
      J.pairs7(
        J.pair("engine", J.of_str(P.Cfg.engine_name(SNil{}, SNil{}))),
        J.pair("count", J.of_u32(P.Cfg.default_count())),
        J.pair("timeout_ms", J.of_u32(P.Cfg.timeout_or(None{}))),
        J.pair("gql_features", J.of_str(P.Cfg.default_features())),
        J.pair("media_upload_base", J.of_str(P.Cfg.default_media_base())),
        J.pair("gql_base", J.of_str(P.Cfg.default_gql_base())),
        J.pair("mentions_url", J.of_str(P.Cfg.default_mentions_url()))
      ),
      J.pairs4(
        J.pair("op_create_tweet", J.of_str(P.Cfg.default_op_create_tweet())),
        J.pair("op_tweet_detail", J.of_str(P.Cfg.default_op_tweet_detail())),
        J.pair("op_search", J.of_str(P.Cfg.default_op_search())),
        J.pair("op_viewer", J.of_str(P.Cfg.default_op_viewer()))
      )
    ))),
    J.pair("exit_codes", J.arr_of(Argv.exit_codes()))
  ))
