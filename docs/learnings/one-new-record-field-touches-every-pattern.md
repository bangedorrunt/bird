# One new record field touches every pattern, in field order

**What happened.** Adding `media_upload_base`, then `gql_base` and
`mentions_url`, to `RunCfg` broke compilation in files nobody had edited: the
failures were `a domain.RunCfg pattern with 19 fields` in `src/view.bend` and in
three test files, each naming a line that had been correct a minute earlier.

**The cause, in three parts.** Bend records are positional in the way that
matters here:

1. A pattern must name **every** field. There is no `..` rest and no partial
   record pattern, so `case D.RunCfg{verb, …, timeout_ms}` stops compiling the
   moment the record grows a field.
2. The fields are bound **in declaration order**, so a field inserted in the
   wrong place does not fail to compile — it swaps two bindings and fails later
   with a type error that points at the wrong def. Inserting `media_upload_base`
   before `timeout_ms` in the patterns produced
   `media_upload_base : U32, timeout_ms : String`, which reads like nonsense
   until you know that the two were crossed.
3. Constructors are positional too: `D.mk_cfg(...)` gained two parameters and
   every caller had to grow the argument list in the same order.

Adding one field to `RunCfg` in this repo touched 22 patterns across `src/` and
`tests/`, plus `mk_cfg` and its callers.

**The fix.** Append new fields at the end of the record, append the matching
parameters at the end of the constructor, and update every pattern with a script
that rewrites the *trailing* run of fields — never a hand-edit per site.

**The guard.** `bend src/effects.bend --check-only` catches all of it, including
the order-sensitive ones, because every pattern is checked against the
declaration. The rule to carry: **append, then sweep**, and expect the sweep to
reach files you did not think you were changing.

**The other half: a field nobody reads costs the same sweep and buys nothing.**
Because every pattern names every field, dead state is not free here — it is
charged on every future field change. Four of them had accumulated: `Model.next_id`
(a counter no branch read), and `RunCfg.fixture`, `RunCfg.text_file`,
`RunCfg.config_path` (three copies of settings the fold already reads out of
`Start`, so each had two homes that could disagree). Grep the readers, not the
name: `next_id` and `RunCfg.fixture` appeared only on the left of patterns and in
constructors, which is the signature of write-only state. Removed, and the sweep
count for the next field went down with them.
