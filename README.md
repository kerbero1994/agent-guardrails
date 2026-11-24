# agent-guardrails

The rules I run AI coding agents under, and the code behind them. Each rule comes from an incident on a production platform where I'm the only engineer and AI agents write the code. The full story is on [kerbero94.dev/sitimm](https://kerbero94.dev/sitimm/).

This repo answers one question: **which of those rules does code enforce, and which ones are still just a rule?**

**Of the 7 guardrails, 0 are fully enforced by code, 3 partly, and 4 are rules only.**

| # | Rule | Enforced by | Where | What the code doesn't cover |
|---|---|---|---|---|
| 1 | One worktree per agent | rule only | [rules/worktrees.md](rules/worktrees.md) | Nothing stops an agent from writing to the shared checkout. |
| 2 | Measure memory before heavy work | partly code | [heavy-lock/guard.sh](heavy-lock/guard.sh) (v2), [rules/heavy-work.md](rules/heavy-work.md) | Only commands wrapped in `guard.sh` are measured. Wrapping them is the rule. |
| 3 | No lock inside a lock | partly code | [heavy-lock/guard.sh](heavy-lock/guard.sh) (v2), [rules/heavy-work.md](rules/heavy-work.md) | A nested step that takes the lock on its own, without checking the flag. |
| 4 | Real installs in worktrees | rule only | [rules/worktrees.md](rules/worktrees.md) | All of it. |
| 5 | A review's GO has a scope | rule only | [rules/reviews.md](rules/reviews.md) | All of it. |
| 6 | A fix needs a test that catches the bug | rule only | [rules/fixes.md](rules/fixes.md) | All of it. |
| 7 | Never cite a ticket you haven't checked | partly code | [hooks/validate-branch.sh](hooks/validate-branch.sh), [rules/tickets.md](rules/tickets.md) | Branch names are checked against a Jira snapshot. Keys in commits and code comments are not. |

It's not a package. Read it, copy what helps, adapt it.

## Run the tests

```sh
./test.sh
```

macOS, with bash, python3 and git. CI runs the same command on `macos-latest`, plus gitleaks over the whole history.

| Test | Cases |
|---|---|
| [hooks/test-validate-branch.sh](hooks/test-validate-branch.sh) | 34 |
| [hooks/test-lint-after-edit.sh](hooks/test-lint-after-edit.sh) | 8 |
| [hooks/test-settings-wired.sh](hooks/test-settings-wired.sh) | 1 |
| [heavy-lock/test-guard.sh](heavy-lock/test-guard.sh) | 13 |

Every barrier in the table was checked by breaking it and watching a test fail (rule 6, applied here). The commit messages list each mutation and what failed.

## What ran as-is, and what is v2

**`hooks/` ran as-is.** These are copies of the hooks in my Claude Code setup. The only differences are the lines marked `# SANITIZED:` (`grep -rn SANITIZED hooks/`), so the gap between this and what ran is auditable. The hook messages are in Spanish, the language I work in. `validate-branch.sh` only acts in repos that carry a `.sitimm-devflow` marker file; rename it freely.

**`heavy-lock/guard.sh` is v2, after the incidents.** The version that ran had three known defects. Only the fixed one is published, and each fix has a test that fails against the old one:

| What ran (v1) | v2 | Test that fails on v1 |
|---|---|---|
| The caller took the lock with `lockf`, and `lockf` without `-t` waits forever. | `guard.sh` takes the lock itself with `lockf -t`, and gives up with exit 75. | `busy lock fails fast` |
| Nested steps relied on a person setting `HEAVY_LOCK_HELD=1`. | `guard.sh` sets it for everything it runs, and skips the lock when it's already set. | `child sees the flag`, `nested guard without the flag waits on its own lock` |
| When memory or load couldn't be read, the shell printed `integer expression expected` and the command ran anyway. | It refuses with exit 75. | `unreadable memory blocks`, `unreadable load blocks` |

Usage: `heavy-lock/guard.sh <command> [args...]`. Exit 75 means "try later". `HEAVY_LOCK` sets the lock file (default `/tmp/heavy.lock`) and `HEAVY_LOCK_WAIT` the seconds to wait (default 600).

## The Jira snapshot

`validate-branch.sh` checks the key in a new branch name (`<KEY>-<N>-<slug>`) against a local snapshot: one ticket per line, `KEY<TAB>statusCategory`.

```
PROJ-1	done
PROJ-2	indeterminate
PROJ-3	new
```

A closed key (`done`) is refused, and so is a missing key below the newest one, because that key was invented. A key newer than the snapshot passes. The path is `~/.claude/hooks/jira-keys.tsv`, or `$JIRA_KEYS_CACHE`. To build it, page through `GET https://<your-site>/rest/api/3/search/jql?jql=project=PROJ&fields=status` and write each issue's `key` and `fields.status.statusCategory.key`. The tests use a small inline fixture, not a real snapshot.

## Wiring

Copy `hooks/*.sh` to `~/.claude/hooks/` and merge [hooks/settings.example.json](hooks/settings.example.json) into `~/.claude/settings.json`. `validate-branch.sh` runs before every Bash command, and `lint-after-edit.sh` after every edit.

## Also in my setup

[hooks/lint-after-edit.sh](hooks/lint-after-edit.sh) runs a fast, file-scoped check right after the agent edits a file: `py_compile` and `ruff --select F` for Python, the repo's own `eslint --quiet` for JS and TS. Undefined names and broken imports block before the agent can say "it works". It doesn't back any of the 7 rows, so it's not in the table.

## License

[MIT](LICENSE)
