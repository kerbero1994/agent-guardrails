#!/usr/bin/env bash
# Tests for validate-branch.sh. Plain bash, no bats dependency.
set -uo pipefail
HOOK="$(dirname "$0")/validate-branch.sh"  # SANITIZED: was the absolute path in the author's home

TMP="$(mktemp -d)"; git -C "$TMP" init -q; touch "$TMP/.sitimm-devflow"
git -C "$TMP" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
TMP_UNMARKED="$(mktemp -d)"; git -C "$TMP_UNMARKED" init -q
# A worktree of the marked repo: the marker is untracked, so it only lives in
# the primary checkout — the hook must still enforce here.
TMP_WT="$(mktemp -d)/wt"; git -C "$TMP" worktree add -q --detach "$TMP_WT"

# Legacy cases run without a Jira snapshot (existence check disabled).
export JIRA_KEYS_CACHE=/nonexistent

pass=0; fail=0
J() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
check() { # desc expected_exit json
  printf '%s' "$3" | bash "$HOOK" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$2" ]; then echo "ok: $1"; pass=$((pass+1));
  else echo "FAIL: $1 (expected $2, got $got)"; fail=$((fail+1)); fi
}

check "valid ticket branch allowed"   0 "$(J "$TMP" 'git checkout -b SITIMM-12-avatar-upload')"
check "bad name blocked"              2 "$(J "$TMP" 'git checkout -b fix-stuff')"
check "switch -c valid allowed"       0 "$(J "$TMP" 'git switch -c SITIMM-7-foo')"
check "switch -c bad blocked"         2 "$(J "$TMP" 'git switch -c wip')"
check "git branch create bad blocked" 2 "$(J "$TMP" 'git branch randomname')"
check "git branch create valid ok"    0 "$(J "$TMP" 'git branch SITIMM-9-thing')"
check "main allowlisted"              0 "$(J "$TMP" 'git checkout -b main')"
check "release/* allowlisted"         0 "$(J "$TMP" 'git checkout -b release/1.2')"
check "branch listing -a allowed"     0 "$(J "$TMP" 'git branch -a')"
check "branch delete -d allowed"      0 "$(J "$TMP" 'git branch -d oldbranch')"
check "non-branch git allowed"        0 "$(J "$TMP" 'git status')"
check "non-bash tool allowed"         0 '{"tool_name":"Read","tool_input":{}}'
check "unmarked repo not enforced"    0 "$(J "$TMP_UNMARKED" 'git checkout -b whatever')"

# --- 2026-09-28: the escape routes v1 let through ---  # SANITIZED: internal figure removed
check "git -C marked, bad name blocked"      2 "$(J "$TMP_UNMARKED" "git -C $TMP checkout -b fix-stuff")"
check "git -C marked, valid name allowed"    0 "$(J "$TMP_UNMARKED" "git -C $TMP checkout -b SITIMM-12-ok")"
check "worktree add -b bad blocked"          2 "$(J "$TMP" 'git worktree add .claude/worktrees/x -b fix-stuff origin/main')"
check "worktree add -b valid allowed"        0 "$(J "$TMP" 'git worktree add -b SITIMM-12-ok ../wt2 origin/main')"
check "git -C worktree add -b bad blocked"   2 "$(J "$TMP_UNMARKED" "git -C $TMP worktree add ../wt3 -b wip origin/main")"
check "worktree add --detach allowed"        0 "$(J "$TMP" 'git worktree add --detach ../wt4 origin/main')"
check "worktree list allowed"                0 "$(J "$TMP" 'git worktree list')"
check "inside a worktree, bad name blocked"  2 "$(J "$TMP_WT" 'git checkout -b fix-stuff')"
check "cd into marked repo then bad blocked" 2 "$(J "$TMP_UNMARKED" "cd $TMP && git checkout -b fix-stuff")"
check "second command in chain checked"      2 "$(J "$TMP" 'git status && git switch -c wip')"
check "checkout -B bad blocked"              2 "$(J "$TMP" 'git checkout -B wip')"
check "switch --create bad blocked"          2 "$(J "$TMP" 'git switch --create wip')"
check "branch -m to bad name blocked"        2 "$(J "$TMP" 'git branch -m old wip')"
check "branch -m to valid name allowed"      0 "$(J "$TMP" 'git branch -m old SITIMM-12-ok')"
check "branch -u upstream allowed"           0 "$(J "$TMP" 'git branch -u origin/main')"

# --- Jira snapshot: invented keys and closed tickets are refused ---
CACHE="$(mktemp)"
printf 'SITIMM-10\tdone\nSITIMM-11\tnew\nSITIMM-12\tindeterminate\nSITIMM-20\tnew\n' > "$CACHE"
export JIRA_KEYS_CACHE="$CACHE"
check "open ticket allowed"                  0 "$(J "$TMP" 'git checkout -b SITIMM-11-ok')"
check "in-progress ticket allowed"           0 "$(J "$TMP" 'git checkout -b SITIMM-12-ok')"
check "closed ticket blocked"                2 "$(J "$TMP" 'git checkout -b SITIMM-10-ok')"
check "invented key (gap below max) blocked" 2 "$(J "$TMP" 'git checkout -b SITIMM-15-ok')"
check "key newer than snapshot allowed"      0 "$(J "$TMP" 'git checkout -b SITIMM-21-ok')"
check "unmarked repo ignores snapshot"       0 "$(J "$TMP_UNMARKED" 'git checkout -b SITIMM-10-ok')"

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
