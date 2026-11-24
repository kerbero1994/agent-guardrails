# Heavy work on a shared laptop

Rows 2 and 3 of the table. The code half is [`heavy-lock/guard.sh`](../heavy-lock/guard.sh); this file is the half that is still a rule.

## Measure memory before heavy work

**Rule.** Before any heavy job (test suites, builds, browser tests, renders, a push with hooks, starting subagents), measure free memory and load. Under 40 % free or load over 20: don't run it, say so, and wait. With resources: one heavy job at a time, through the machine-wide lock.

**Why.** September and November 2026: the laptop rebooted twice under parallel pushes, test suites and a video render. In-flight work was lost.

**How to apply.**
- Wrap the job: `heavy-lock/guard.sh <command>`. It takes the lock, measures once the lock is yours, and refuses with exit 75 when it cannot run safely.
- Measure in a separate step before deciding to start, not in the same command that runs the job: a measurement that cannot stop the job is not a check.
- Exit 75 means "try later". Don't retry in a loop; report the numbers.

**Enforced by.** Partly code. `guard.sh` measures and refuses, but only for commands that go through it. Wrapping the command is the rule.

## No lock inside a lock

**Rule.** A step that runs inside a job that already holds the lock must not ask for the lock again.

**Why.** November 2026: a push run under the lock waited on its own pre-push check, which asked for the same lock, and held the machine for 8 hours.

**How to apply.**
- Nested steps go through `guard.sh` too. It sets `HEAVY_LOCK_HELD=1` for everything it runs and skips the lock when the flag is already set. It still measures.
- A repo script that takes the lock on its own (calling `lockf` directly) must check `HEAVY_LOCK_HELD` first.
- Always give the lock a timeout (`lockf -t`). A lock without one hangs instead of failing.

**Enforced by.** Partly code. Through `guard.sh` the nesting is handled. A nested step that takes the lock by itself, without the flag check, still deadlocks; it now fails after `HEAVY_LOCK_WAIT` seconds instead of hanging.
