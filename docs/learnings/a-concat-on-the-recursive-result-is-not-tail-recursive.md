# A concat on the recursive result is not tail-recursive

`escape(s)` was `escape_ch(h) ++ escape(t)`. Each character added one stack
frame, so a string of about 100 KB or more overflowed with
`machine stack overflow?`. The short tests passed, which is why it went unseen.

The fix is an accumulator, the same shape as `items_rev` and `fields_rev`:

- reverse the input once, tail-recursively;
- walk the reversed input, prepending each escaped piece onto `acc`.

The output reads left to right again, with no frame per character.

The gotcha: a `++` whose right side is the recursive call looks harmless, but
the call is not in tail position. Put the recursion on the accumulator side.

The regression test uses 200 KB, because a 1 KB input does not reach the limit.
