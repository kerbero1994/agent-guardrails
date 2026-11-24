# Worktrees

Two rules about where agents write code. Rows 1 and 4 of the table.

## One worktree per agent

**Rule.** Every agent or session that writes code works in its own git worktree. The primary checkout is shared and read-only.

**Why.** July 2026: two sessions shared one checkout. One switched branches under the other's build and mixed two tickets on one branch. Recovering took a file-by-file checkout.

**How to apply.**
- Subagents that write code are started with worktree isolation (Claude Code's agent tool offers `isolation: "worktree"`).
- A session by hand: `git worktree add .claude/worktrees/<KEY>-<slug> -b <KEY>-<slug> origin/<default-branch>`, then work and commit there.
- Before any `switch`, `checkout` or commit in the primary checkout, prove you own it: `git worktree list`, `git branch --show-current`, `git status`. A branch or change you didn't make means another session owns it.
- Remove the worktree from the repo root when done (`git worktree remove <path> && git worktree prune`), never from inside it.

**Enforced by.** Rule only. The isolation option exists, but nothing stops an agent from writing to the shared checkout.

## Real installs in worktrees

**Rule.** Install dependencies inside each worktree, and check the hooks exist before the first commit. Never symlink `node_modules` from the primary checkout.

**Why.** November 2026: three pushes went out with no hooks because dependencies were symlinked. The symlinked tree had no `.husky/_`, so commit and push ran no gate, and nothing warned.

**How to apply.**
- Run the repo's own install (`npm ci`, `pnpm i`) in the new worktree.
- Confirm the hook is there (for husky: `ls .husky/_/pre-push`) before committing.
- Python is the exception that works the other way: symlink the whole virtualenv directory, never just the interpreter binary, or `pyvenv.cfg` resolves to the wrong site-packages.

**Enforced by.** Rule only.
