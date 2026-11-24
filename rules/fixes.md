# A fix needs a test that catches the bug

Row 6 of the table.

**Rule.** A fix isn't done until a test fails with the bug put back.

**Why.** Fixes passed tests that would also pass without them. In one case the tests rebuilt the expression they asserted on instead of calling the code under test; in another, the fix itself kept the bug at an exact boundary. Both looked green.

**How to apply.**
1. Save the file, reintroduce the bug with one exact replacement, run the tests, and count the failures. Restore and confirm green.
2. Zero failures means the test doesn't cover the fix. Rewrite it so it calls the production code.
3. Expect some tests to survive the mutation, and know which ones and why.
4. Mutate the layer that wires the pieces together, not only the piece.
5. Report a mutation's result only after running it.

This repo follows it: each commit that adds a barrier lists the mutation and the failures it produced.

**Enforced by.** Rule only.
