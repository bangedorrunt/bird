# Architecture decisions

One record, on purpose: the operator folded the per-decision drafts into a single
architecture record for this project. It covers the whole design in sections, so
there is nothing to cross-reference between files.

| # | Decision | Status |
|---|---|---|
| [0001](0001-design-bird.md) | Design `bird`: a provable pure core, one interpreter, a machine-first contract | accepted |

Read `0001-design-bird.md` before changing anything that spans files. It names,
per section, what is ruled out and which command proves the decision still holds.
Implementation gotchas found while building it live in `docs/learnings/`.
