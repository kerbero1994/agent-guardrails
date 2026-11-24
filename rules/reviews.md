# A review's GO has a scope

Row 5 of the table.

**Rule.** Every verdict says what the reviewer read and what was left out. Count before claiming "N files have X".

**Why.** November 2026: a reviewer approved after opening 25 of 106 files. Each follow-up round had been limited to the latest fix, but the final "GO" sounded like it covered the whole stack.

**How to apply.**
- Next to every verdict, one line: files and commits the reviewer opened, commands it ran, and the limits it was given.
- A follow-up round that only checks the fix says so: "GO on the fix in <commit>", not "GO".
- Before writing "N of them have X", run the count and quote it.
- The reviewer runs at least one mutation of its own, different from the author's (see [fixes.md](fixes.md)).

**Enforced by.** Rule only.
