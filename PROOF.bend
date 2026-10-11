import Base
import ./LAWS.bend as Laws
import ./src/domain.bend as D
import ./src/json.bend as J
import ./src/argv.bend as A
import ./src/http.bend as H

# Proofs for LAWS.bend. Each law `law x` is discharged by `def Laws.x` with the
# same binders: a proposition is a type, and a def of that type is a proof.
#
#   bend PROOF.bend            -- the gate; prints ALL PROOFS CHECK when green
#   bend PROOF.bend --verdict  -- re-checks with the kernel (no unsafe, no FFI)
#
# `{==}` proves a goal whose two sides already compute to the same term.
# `%e : P` rewrites with `e : {a == b : T}`; `P` is the goal with `_` where `b`
# was. A recursive call is the induction hypothesis, and a `case` refines the
# goal so each branch is proved on its own.

# ── engine_name_round_trip ──────────────────────────────────────────────────
# Three engines, three cases: `name` prints the very string `of_lower` reads
# back, so both sides reduce to the same constructor in every branch.
def Laws.engine_name_round_trip(e):
  match e:
    case D.EngineGraphql{}:
      {==}
    case D.EngineSweetistics{}:
      {==}
    case D.EngineAuto{}:
      {==}

# ── engine_name_spelling ───────────────────────────────
# One case per engine; each literal comparison computes, so the goal is
# `True{}` before the disjunction is even folded.
def Laws.engine_name_spelling(e):
  match e:
    case D.EngineGraphql{}:
      {==}
    case D.EngineSweetistics{}:
      {==}
    case D.EngineAuto{}:
      {==}

# ── agent_output ────────────────────────────────────────────────────────────
# Four cases, and both halves of the claim show up in them: `asked` forces the
# envelope even on a tty, and a non-tty gets it with nothing asked for.
def Laws.agent_output(tty, asked):
  match tty asked:
    case True{} True{}:
      {==}
    case True{} False{}:
      {==}
    case False{} True{}:
      {==}
    case False{} False{}:
      {==}

# ── array_items_round_trip ──────────────────────────────────────────────────
# Induction on the list. Empty: `arr_of` is `JsonArrEnd{}` and `items` reads
# nothing back. Cons: `arr_of` prepends one node, so the goal is the induction
# hypothesis under the same head. The recursion is the hypothesis; the rewrite
# records that reading the tail back gives the tail.
def Laws.array_items_round_trip(xs):
  match xs:
    case Nil{}:
      {==}
    case +h <> t:
      %Laws.array_items_round_trip(t) : {J.items(J.arr_of(h <> t)) == h <> _ : List<&2, J.Json>}
      {==}

# Every constructor named, so a verb added later fails this proof until someone
# classifies it. The two writing verbs are covered by `needs_network`'s
# catch-all; the rest answer `False` to `writes`, which makes the disjunction
# true before the right side is even read.
# ── verb_word_reaches_verb ─────────────────────────────────────────────────
# One case per verb, and every one closes by computation: the word the domain
# prints is the word the table reads, and the comparison is on names, which do
# not depend on the payloads the prototype leaves empty.
def Laws.verb_word_reaches_verb(v):
  match v:
    case D.VerbHelp{}:
      {==}
    case D.VerbSchema{}:
      {==}
    case D.VerbVersion{}:
      {==}
    case D.VerbTweet{text, media}:
      {==}
    case D.VerbReply{target, text, media}:
      {==}
    case D.VerbRead{target}:
      {==}
    case D.VerbReplies{target}:
      {==}
    case D.VerbThread{target}:
      {==}
    case D.VerbSearch{query, count}:
      {==}
    case D.VerbMentions{count}:
      {==}
    case D.VerbBookmarks{count}:
      {==}
    case D.VerbWhoami{}:
      {==}
    case D.VerbCheck{}:
      {==}
    case D.VerbLogin{}:
      {==}

# ── the_timeout_floor_is_one_second ────────────────────────────────────────
# The floor branch ignores its budget entirely, so the goal computes to `True`
# before the budget is looked at. The `seconds` binder is what makes this a
# claim about every budget rather than about one.
def Laws.the_timeout_floor_is_one_second(seconds):
  {==}

# ── media_flag_is_a_media_item / alt_flag_is_an_alt_item ───────────────────
# Nothing to case on: both sides reduce to the same item, so reflexivity is the
# whole proof. That is the point -- the mapping is one table lookup, and this
# pins it.
def Laws.media_flag_is_a_media_item(value):
  {==}

def Laws.alt_flag_is_an_alt_item(value):
  {==}

# ── writes_are_network ──────────────────────────────────────────────────────
# `login` is the one verb that writes locally -- it writes the settings cache --
# and it still needs the network, because the bundle it writes into that cache is
# fetched from X. It answers `False` to `writes` and `True` to `needs_network`, so
# the disjunction is true before the second side is read.

def Laws.writes_are_network(v):
  match v:
    case D.VerbHelp{}:
      {==}
    case D.VerbSchema{}:
      {==}
    case D.VerbVersion{}:
      {==}
    case D.VerbTweet{text, media}:
      {==}
    case D.VerbReply{target, text, media}:
      {==}
    case D.VerbRead{target}:
      {==}
    case D.VerbReplies{target}:
      {==}
    case D.VerbThread{target}:
      {==}
    case D.VerbSearch{query, count}:
      {==}
    case D.VerbMentions{count}:
      {==}
    case D.VerbBookmarks{count}:
      {==}
    case D.VerbWhoami{}:
      {==}
    case D.VerbCheck{}:
      {==}
    case D.VerbLogin{}:
      {==}
