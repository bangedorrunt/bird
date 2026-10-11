import Base
import ./src/domain.bend as D
import ./src/json.bend as J
import ./src/argv.bend as A
import ./src/http.bend as H

# Laws, not tests. Each entry is an open claim about the code: a property that
# must hold for EVERY value of the bound variables, not for one example. The
# claims are stated here and proved in PROOF.bend; `bend PROOF.bend` is the
# gate and prints SOME PROOFS FAIL while any claim below is unproved.
#
# A law that will not prove is a bug in the code, not in the law. Fix the code.
#
# Laws are never edited down to what happens to be provable today. If one has
# to be weakened, that weakening is a deliberate spec change and the comment
# says so.

# ── transport ───────────────────────────────────────────────────────────────

# An engine name, parsed, is the engine it named. `Engine.name` is what this
# program prints and writes into config, so a name that came out of it must
# round-trip back to the same engine. Without this, `--engine graphql` on one
# run and a stored "graphql" on the next could silently resolve differently,
# and a fallback to `auto` would be indistinguishable from the real thing.
law engine_name_round_trip:
  for e: D.Engine
  {D.Engine.of_lower(D.Engine.name(e)) == e : D.Engine}

# The names themselves are API: they are what a config file stores and what
# `--engine` accepts, so the spelling is a contract rather than an internal
# detail. This is the law that catches a typo. A misspelled name still parses
# back to `auto` -- so the round trip above holds -- while every stored config
# that says "auto" silently stops meaning what it meant.
law engine_name_spelling:
  for e: D.Engine
  {Bool.or(
     String.eq(D.Engine.name(e), "graphql"),
     Bool.or(
       String.eq(D.Engine.name(e), "sweetistics"),
       String.eq(D.Engine.name(e), "auto")
     )
   ) == True{} : Bool}

# ── agent output mode ───────────────────────────────────────────────────────

# Agent mode, pinned from both sides: a machine gets one JSON envelope when no
# terminal is attached, and `--json` forces it even on a tty. So the output is
# agent-shaped exactly when the caller asked or stdout is not a terminal -- and
# never otherwise, which is what keeps a person at a terminal from being handed
# an envelope they cannot read.
law agent_output:
  for tty: Bool
  for asked: Bool
  {D.OutMode.is_agent(D.OutMode.pick(tty, asked)) == Bool.or(asked, Bool.not(tty)) : Bool}

# ── json arrays ─────────────────────────────────────────────────────────────

# Building an array and reading it back is the identity. `arr_of` is how every
# response list is assembled and `items` is how a caller walks it, so a dropped
# or duplicated element here would corrupt results in a way no later layer can
# detect. Stated over every list, not a sample.
law array_items_round_trip:
  for xs: List<&2, J.Json>
  {J.items(J.arr_of(xs)) == xs : List<&2, J.Json>}

# ── verbs ───────────────────────────────────────────────────────────────────

# Everything that writes talks to the network. A write verb that skipped the
# network would report success without having done anything, which is the one
# failure an agent cannot recover from. Reads and local verbs stay free to be
# offline.
law writes_are_network:
  for v: D.Verb
  {Bool.or(Bool.not(D.Verb.writes(v)), D.Verb.needs_network(v)) == True{} : Bool}

# ── the command line ────────────────────────────────────────────────────────

# Every verb the program can carry is reachable by typing its name. A verb added
# to the domain but not to the argv table compiles, type-checks and proves
# nothing: nothing can ask for it, and no test that spells its name would ever
# be written. This is the law that makes an unreachable verb a failure instead
# of a silent gap.
law verb_word_reaches_verb:
  for v: D.Verb
  {A.Argv.proto_name(D.Verb.name(v)) == D.Verb.name(v) : String}

# `--media` arrives as a media item, not as a setting. The media policy reads
# the item list for paths and pairs them with `--alt`, so a `--media` that
# became a plain flag would be dropped without an error -- the tweet would go
# out with no attachment and look fine.
law media_flag_is_a_media_item:
  for value: String
  {A.Argv.item_for(A.Argv.kind_of("--media"), "--media", value) == D.ItemMedia{value} : D.Item}

# Same for `--alt`: an alt with no media to sit on is an error the media policy
# can only raise if the alt arrived as an alt.
law alt_flag_is_an_alt_item:
  for value: String
  {A.Argv.item_for(A.Argv.kind_of("--alt"), "--alt", value) == D.ItemAlt{value} : D.Item}

# ── the transport ───────────────────────────────────────────────────────────

# The floor under `--timeout-ms` is one second, not zero. curl reads `--max-time
# 0` as "no limit", so a budget rounded down to zero would turn the one setting
# that stops an agent hanging into an invitation to hang forever.
law the_timeout_floor_is_one_second:
  for seconds: U32
  {U32.is_eq(H.Http.pick_secs(False{}, seconds), 1) == True{} : Bool}
