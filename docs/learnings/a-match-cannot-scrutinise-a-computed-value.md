# A match cannot scrutinise a computed value

**What happened.** Every routing def written the natural way was refused:

```
def Update.described(+m: D.Model) -> D.Step:
  match Update.media_present(m):        # error: a parameter or field scrutinee
```

The same error met `match Update.phase_in(m)`, `match J.text_of(x)`,
`match List.head(...)`, `match H.Http.transport_error(curl_status)` and
`match Api.media_jobs(...)`.

**The cause.** Bend lets a `match` scrutinise a parameter or a field of one,
never the result of a call. It is not a heuristic that sometimes fires; it is the
rule, and a media write routes on six derived facts.

**The fix, and the shape it leaves.** Give the derived value its own def that
takes it as a *parameter*:

```
def Update.described_route(has_media: Bool, +m: D.Model) -> D.Step:
  match has_media:
    case True{}:  Update.media_described_on(Api.Api.media_gate_cfg(Update.cfg_of(m)), m)
    case False{}: Update.described_on(Api.Api.plan(Update.cfg_of(m), Update.id_request()), m)

def Update.described(+m: D.Model) -> D.Step:
  Update.described_route(Update.media_present(m), m)
```

This is why `src/update.bend` is full of `*_on` and `*_route` defs with a
one-line wrapper beneath them, and why `src/argv.bend` classifies tokens up front
rather than re-deriving a fact in each branch. It is the codebase's dominant
idiom, not noise.

**The guard.** The compiler is the guard; there is nothing to test. Write the
wrapper defs from the start — the alternative is discovering the rule once per
call site.
