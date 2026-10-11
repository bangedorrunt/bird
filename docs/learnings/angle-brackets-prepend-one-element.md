# `<>` prepends one element, it does not concatenate

**What happened.** Extending `Argv.schema_json` to carry eleven defaults, the
natural way to write it was refused:

```
J.obj_of(J.pairs7(…) <> J.pairs4(…))
# expected : J.JField
# observed : List<&2, J.JField>
```

**The cause.** In Bend `x <> xs` is *cons*: one element in front of a list. It is
not list concatenation, and the error above is what that mistake looks like: the
left operand of the second `<>` is a whole list, and the operator wanted an
element.

**The fix.** `List.append(&2, J.JField, left, right)` concatenates. Cons stays
what it is for, which is why the codebase reads `D.hdr(…) <> (D.hdr(…) <> Nil{})`
everywhere: a list is built element by element, and `Nil{}` is its end.

**Why it is worth a file.** The distinction is what made the `-F` multipart bug
subtle. `Http.part_args` collects `flag, value, flag, value` with cons and then
reverses the whole thing on the way out, so the *unit* prepended has to be written
in reverse too. Anyone reaching for `<>` expecting concatenation will write a
reversal that is quiet, plausible, and wrong.

**The guard.** `bend src/effects.bend --check-only` catches the type error
immediately. There is nothing to test beyond that, but a reader who knows the
operator does not have to rediscover the ordering rule.
