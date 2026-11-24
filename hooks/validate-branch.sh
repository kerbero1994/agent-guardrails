#!/usr/bin/env bash
# PreToolUse hook: enforce <TICKET-KEY>-<slug> branch naming, only inside
# repos marked with a .sitimm-devflow file. exit 0 = allow, exit 2 = block.
#
# v2 (2026-09-28). v1 only matched a literal `git checkout -b|switch -c|branch`
# at the start of the command and resolved the repo with --show-toplevel, so it
# missed the three forms the SITIMM rules themselves require — `git -C <path>`
# (absolute-path rule), `git worktree add -b` (worktree rule) and anything run
# inside a worktree (the untracked marker only lives in the primary checkout).
# SANITIZED: one line with an internal figure removed here.
#
# Now: every `git` in a compound command is parsed (`&&`, `;`, `|`, newlines,
# `cd <dir>` is followed), the marker is looked up in the primary checkout via
# --git-common-dir, and keys are checked against a Jira snapshot
# (KEY<TAB>statusCategory, one per line; $JIRA_KEYS_CACHE overrides the path):
# a key whose ticket is closed, or a gap below the newest known key (an
# invented key), is refused. A key newer than the snapshot passes.
set -uo pipefail
HOOK_INPUT="$(cat)" exec python3 - <<'PY'
import json, os, re, shlex, subprocess, sys
from os import path as P

try:
    data = json.loads(os.environ.get("HOOK_INPUT") or "{}")
except ValueError:
    sys.exit(0)
if data.get("tool_name") != "Bash":
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command") or ""
if "git" not in cmd:
    sys.exit(0)
cwd = data.get("cwd") or os.getcwd()

NAME_RE = re.compile(r"^[A-Z]{2,}-[0-9]+-[a-z0-9.-]+$")
ALLOW_RE = re.compile(r"^(main|master|develop|release/.+|hotfix/.+)$")
CACHE = os.environ.get("JIRA_KEYS_CACHE") or P.expanduser("~/.claude/hooks/jira-keys.tsv")
BRANCH_NO_CREATE = {"-d", "-D", "--delete", "-a", "--all", "-r", "--remotes", "-l", "--list",
                    "-v", "-vv", "--verbose", "--show-current", "--contains", "--no-contains",
                    "--merged", "--no-merged", "-u", "--set-upstream-to", "--unset-upstream",
                    "--edit-description", "--points-at", "--sort", "--format", "--column"}


def tokens(text):
    lx = shlex.shlex(text.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lx.whitespace_split = True
    try:
        return list(lx)
    except ValueError:  # unbalanced quotes: fall back to a plain split
        return text.split()


def simple_commands(toks):
    cur = []
    for t in toks:
        if t and set(t) <= set(";&|()"):
            if cur:
                yield cur
            cur = []
        else:
            cur.append(t)
    if cur:
        yield cur


def flag_values(args, flags):
    out = []
    for i, a in enumerate(args):
        if a in flags and i + 1 < len(args):
            out.append(args[i + 1])
        for f in flags:
            if f.startswith("--") and a.startswith(f + "="):
                out.append(a.split("=", 1)[1])
    return out


def parse_git(args, base):
    """Return (repo_dir, [new branch names]) for one git invocation."""
    repo, i = base, 0
    while i < len(args):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            repo = P.normpath(P.join(repo, P.expanduser(args[i + 1])))
            i += 2
        elif a in ("-c", "--git-dir", "--work-tree", "--namespace") and i + 1 < len(args):
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            break
    if i >= len(args):
        return repo, []
    sub, rest = args[i], args[i + 1:]
    if sub == "checkout":
        return repo, flag_values(rest, ("-b", "-B"))
    if sub == "switch":
        return repo, flag_values(rest, ("-c", "-C", "--create", "--force-create"))
    if sub == "worktree" and rest[:1] == ["add"]:
        return repo, flag_values(rest[1:], ("-b", "-B"))
    if sub == "branch":
        flags = [a for a in rest if a.startswith("-")]
        pos = [a for a in rest if not a.startswith("-")]
        if any(f.split("=", 1)[0] in BRANCH_NO_CREATE for f in flags):
            return repo, []
        if any(f in ("-m", "-M", "-c", "-C", "--move", "--copy") for f in flags):
            return repo, pos[-1:]  # rename/copy: the new name is last
        return repo, pos[:1]  # git branch NAME [START]
    return repo, []


def git_out(repo, *args):
    try:
        r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def marked(repo):
    """True if repo (or the primary checkout it is a worktree of) carries the marker."""
    if not P.isdir(repo):
        return False
    top = git_out(repo, "rev-parse", "--show-toplevel")
    common = git_out(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    roots = {top} if top else set()
    if common:
        roots.add(P.dirname(common.rstrip("/")) if common.rstrip("/").endswith("/.git") else common)
    return any(r and P.isfile(P.join(r, ".sitimm-devflow")) for r in roots)


def key_problem(name):
    m = re.match(r"^([A-Z]{2,})-([0-9]+)-", name)
    if not m or not P.isfile(CACHE):
        return None
    proj, num = m.group(1), int(m.group(2))
    key = f"{proj}-{num}"
    known, newest = {}, 0
    with open(CACHE, encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2 or not parts[0].startswith(proj + "-"):
                continue
            try:
                n = int(parts[0].split("-", 1)[1])
            except ValueError:
                continue
            known[parts[0]] = parts[1]
            newest = max(newest, n)
    if not known:
        return None
    if known.get(key) == "done":
        return (f"{key} está cerrado en Jira. Reábrelo (o crea un ticket nuevo) antes de abrir rama; "
                f"si ya lo reabriste, actualiza {CACHE}.")
    if key not in known and num <= newest:
        return f"{key} no existe en Jira. No inventes claves: crea el ticket primero y usa su clave real."
    return None


problems = []
here = cwd
for sc in simple_commands(tokens(cmd)):
    if sc[0] == "cd" and len(sc) > 1:
        here = P.normpath(P.join(here, P.expanduser(sc[1])))
        continue
    for i, t in enumerate(sc):
        if P.basename(t) != "git":
            continue
        repo, names = parse_git(sc[i + 1:], here)
        names = [n for n in names if n and not ALLOW_RE.match(n)]
        if not names or not marked(repo):
            continue
        for n in names:
            if not NAME_RE.match(n):
                slug = re.sub(r"[^a-z0-9.-]", "", n.lower().replace(" ", "-"))
                problems.append(f"la rama '{n}' debe seguir <TICKET-KEY>-<slug>, p. ej. SITIMM-12-avatar-upload. "
                                f"Crea primero el ticket en Jira y usa su clave: SITIMM-<N>-{slug}")
            else:
                kp = key_problem(n)
                if kp:
                    problems.append(kp)

if problems:
    print("BLOCKED by dev-workflow: " + " | ".join(problems), file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PY
