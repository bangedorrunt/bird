# A flag value that is also a verb word is refused

**What happened.** A live end-to-end case pointed the graphql base at the stand-in
server and passed `--op-create-tweet tweet`, which is a reasonable operation id.
The run stopped at exit 2:

```
{"error":{"id":"usage","message":"--op-create-tweet needs a value", …}}
```

**The cause.** `src/argv.bend` classifies each token before walking the list, and
a bare word that names a verb becomes a verb token. `tweet` is a verb, so the
token after `--op-create-tweet` was not a value: the flag was left owing one, and
that is what the error says.

**The fix.** Two, in the order they apply:

- Tests name an operation id that is not a verb word (`create-tweet`), because
  `--op-create-tweet` is documented as a query id, and X's ids are not verb words.
- The refusal is right as it stands: a flag's value that is a verb word really is
  ambiguous, and refusing it by name beats guessing which one was meant.

**The guard.** The e2e case runs the real command line, so the rule was found by
the interface a caller uses rather than by reasoning. When a flag value looks like
something else the parser recognises, expect the parser to say so.
