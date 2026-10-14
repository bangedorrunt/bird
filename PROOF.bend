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
# `items` reverses an accumulator, so the proof needs reverse lemmas over Json
# lists. Each lemma is stated with the side the rewrite needs as its right side.
def Lem.app_assoc(+xs: List<&2, J.Json>, +ys: List<&2, J.Json>, +zs: List<&2, J.Json>) -> {List.append(&2, J.Json, xs, List.append(&2, J.Json, ys, zs)) == List.append(&2, J.Json, List.append(&2, J.Json, xs, ys), zs) : List<&2, J.Json>}:
  match xs:
    case Nil{}:
      {==}
    case +h <> t:
      %Lem.app_assoc(t, ys, zs) : {List.append(&2, J.Json, h <> t, List.append(&2, J.Json, ys, zs)) == h <> _ : List<&2, J.Json>}
      {==}

def Lem.rgo_app(+xs: List<&2, J.Json>, +acc: List<&2, J.Json>) -> {List.append(&2, J.Json, List.reverse.go(&2, J.Json, xs, Nil{}), acc) == List.reverse.go(&2, J.Json, xs, acc) : List<&2, J.Json>}:
  match xs:
    case Nil{}:
      {==}
    case +h <> t:
      %Lem.rgo_app(t, h <> Nil{}) : {List.append(&2, J.Json, _, acc) == List.reverse.go(&2, J.Json, h <> t, acc) : List<&2, J.Json>}
      %Lem.app_assoc(List.reverse.go(&2, J.Json, t, Nil{}), h <> Nil{}, acc) : {_ == List.reverse.go(&2, J.Json, h <> t, acc) : List<&2, J.Json>}
      %Lem.rgo_app(t, h <> acc) : {List.append(&2, J.Json, List.reverse.go(&2, J.Json, t, Nil{}), h <> acc) == _ : List<&2, J.Json>}
      {==}

def Lem.rgo_append(+ys: List<&2, J.Json>, +zs: List<&2, J.Json>, +acc: List<&2, J.Json>) -> {List.reverse.go(&2, J.Json, zs, List.reverse.go(&2, J.Json, ys, acc)) == List.reverse.go(&2, J.Json, List.append(&2, J.Json, ys, zs), acc) : List<&2, J.Json>}:
  match ys:
    case Nil{}:
      {==}
    case +h <> t:
      %Lem.rgo_append(t, zs, h <> acc) : {List.reverse.go(&2, J.Json, zs, List.reverse.go(&2, J.Json, h <> t, acc)) == _ : List<&2, J.Json>}
      {==}

def Lem.rev_rev(+xs: List<&2, J.Json>) -> {List.reverse.go(&2, J.Json, List.reverse.go(&2, J.Json, xs, Nil{}), Nil{}) == xs : List<&2, J.Json>}:
  match xs:
    case Nil{}:
      {==}
    case +h <> t:
      %Lem.rgo_app(t, h <> Nil{}) : {List.reverse.go(&2, J.Json, _, Nil{}) == h <> t : List<&2, J.Json>}
      %Lem.rgo_append(List.reverse.go(&2, J.Json, t, Nil{}), h <> Nil{}, Nil{}) : {_ == h <> t : List<&2, J.Json>}
      %Lem.rev_rev(t) : {List.reverse.go(&2, J.Json, h <> Nil{}, List.reverse.go(&2, J.Json, List.reverse.go(&2, J.Json, t, Nil{}), Nil{})) == h <> _ : List<&2, J.Json>}
      {==}

# items_rev over arr_of reads the list back in reverse, the same shape as `reverse.go`.
def Lem.rgo_arr(+xs: List<&2, J.Json>, +acc: List<&2, J.Json>) -> {List.reverse.go(&2, J.Json, xs, acc) == J.items_rev(J.arr_of(xs), acc) : List<&2, J.Json>}:
  match xs:
    case Nil{}:
      {==}
    case +h <> t:
      %Lem.rgo_arr(t, h <> acc) : {List.reverse.go(&2, J.Json, h <> t, acc) == _ : List<&2, J.Json>}
      {==}

def Lem.array_round_trip(+xs: List<&2, J.Json>) -> {J.items(J.arr_of(xs)) == xs : List<&2, J.Json>}:
  %Lem.rgo_arr(xs, Nil{}) : {List.reverse(&2, J.Json, _) == xs : List<&2, J.Json>}
  %Lem.rev_rev(xs) : {List.reverse.go(&2, J.Json, List.reverse.go(&2, J.Json, xs, Nil{}), Nil{}) == _ : List<&2, J.Json>}
  {==}

def Laws.array_items_round_trip(xs):
  Lem.array_round_trip(xs)

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
    case D.VerbBookmarks{count, cursor}:
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

# ── failed_run_ignores_messages ────────────────────────────────────────────
# `step_over` matches on the flag before it reads the message, so with `True`
# the goal reduces to `Step.only(m)` on both sides and needs no case split.
def Laws.failed_run_ignores_messages(msg, m):
  {==}

# ── unknown_error_is_not_retryable ─────────────────────────────────────────
# `unknown` is `True`, so `Bool.not` gives `False` and `Bool.and` returns
# `False` whatever `ErrCode.retryable` says. One case per code, so every
# constructor is named and a new one fails here until it is covered.
def Laws.unknown_error_is_not_retryable(c, m, h):
  match c:
    case D.ErrUsage{}:
      {==}
    case D.ErrAuth{}:
      {==}
    case D.ErrNotFound{}:
      {==}
    case D.ErrRateLimited{}:
      {==}
    case D.ErrNetwork{}:
      {==}
    case D.ErrUpstream{}:
      {==}
    case D.ErrInternal{}:
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
    case D.VerbBookmarks{count, cursor}:
      {==}
    case D.VerbWhoami{}:
      {==}
    case D.VerbCheck{}:
      {==}
    case D.VerbLogin{}:
      {==}
