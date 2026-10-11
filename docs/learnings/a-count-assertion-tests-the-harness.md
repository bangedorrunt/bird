# A count assertion tests the harness, not the behaviour

## What happened

The login wire case in `tests/e2e.sh` asserted `len(page) == 2 and len(bundle) ==
2` — two requests to the page the session travels to, two to the bundle it must
not travel with. Adding one more login case made it fail, with nothing wrong: the
extra run simply made a third request.

## Why it was a bug and not just annoying

It was green and meaningless in both directions. A fourth login case would have
failed it for no reason, which is the visible half. The invisible half is the
other direction: delete a login case and the count goes to one, or break the flow
so it sends nothing at all, and the assertion still reads as "the session arrived"
as long as *some* request reached each path. It tests how many times the harness
ran the command, which is the harness's business, and only incidentally tests
whether the session travelled.

## The guard

The case now asserts the properties over **every** row the stand-in logged:

```python
all(r["cookie"] == "auth_token=SESSION-TOKEN; ct0=CSRF-TOKEN-01" for r in page)
all(r["cookie"] is None for r in bundle)
```

`all` over an empty list is `True`, so the count check survives as `len(page) > 0`
alongside it. That pair is the assertion worth having: whenever the flow ran, the
session reached the page, and it never reached the bundle.

## The rule to carry

**Assert the property, not the tally.** A count in a test couples the assertion to
how many times the harness happens to run something; a `for all` over the recorded
rows says what actually has to be true, and stays honest when the number changes.
