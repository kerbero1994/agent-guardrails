#!/usr/bin/env bash
# PostToolUse hook: after Edit/Write/MultiEdit, run a FAST, FILE-SCOPED linter
# to catch hallucinated symbols, broken imports and syntax errors right after
# the edit — before the model claims the change works.
#
# Contract: exit 0 = clean OR nothing to check (never blocks normal work);
#           exit 2 = problems found, details on stderr are fed back to Claude.
#
# Design notes:
#  - Linters live INSIDE the repos (node_modules/.bin, venv), not globally, so
#    we resolve per-repo and skip silently when none is available.
#  - Python: py_compile (always present) for syntax, then `ruff --select F`
#    (pyflakes: undefined names / bad imports = the hallucination signal).
#  - JS/TS: repo-local eslint --quiet (errors only). Project-wide `tsc` is too
#    slow per edit and belongs on push, not here.
#  - mypy is intentionally NOT run per-edit (slow + noisy on imports). To opt in
#    set SITIMM_HOOK_MYPY=1 and add a branch below.
set -uo pipefail

INPUT="$(cat)"
get() { printf '%s' "$INPUT" | python3 -c "import sys,json
d=json.load(sys.stdin)
k='$1'.split('.')
for part in k:
    d = d.get(part, '') if isinstance(d, dict) else ''
print(d if isinstance(d,str) else '')" 2>/dev/null || true; }

TOOL="$(get tool_name)"
case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

FILE="$(get tool_input.file_path)"
CWD="$(get cwd)"
[ -z "$CWD" ] && CWD="$PWD"
[ -z "$FILE" ] && exit 0
# Resolve relative paths against cwd.
case "$FILE" in
  /*) ;;
  *) FILE="$CWD/$FILE" ;;
esac
[ -f "$FILE" ] || exit 0

# Skip noise: dependencies, build output, caches, scratchpad.
case "$FILE" in
  */node_modules/*|*/.venv/*|*/venv/*|*/dist/*|*/build/*|*/.next/*|*/__pycache__/*|*/.git/*|*/scratchpad/*) exit 0 ;;
esac

ROOT="$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null || true)"

OUT=""
RC=0

# Run a linter (optionally from <root> so it finds its config) and BLOCK only
# when it reports findings (exit 1). Exit >=2 means a tooling/config error not
# caused by this edit -> skip silently, never false-block normal work.
run_linter() {
  local root="$1"; shift
  local out ec
  if [ -n "$root" ]; then out="$(cd "$root" && "$@" 2>&1)"; ec=$?
  else                     out="$("$@" 2>&1)"; ec=$?; fi
  if [ "$ec" -eq 1 ]; then OUT="$out"; RC=2; fi
}

case "$FILE" in
  *.py)
    # 1) Syntax — guaranteed available; any failure is a real break.
    if ! ERR="$(python3 -m py_compile "$FILE" 2>&1)"; then
      OUT="$ERR"; RC=2
    else
      # 2) Undefined names / bad imports via ruff (pyflakes F-codes) if resolvable.
      RUFF=""
      if   [ -n "$ROOT" ] && [ -x "$ROOT/.venv/bin/ruff" ]; then RUFF="$ROOT/.venv/bin/ruff"
      elif [ -n "$ROOT" ] && [ -x "$ROOT/venv/bin/ruff" ];  then RUFF="$ROOT/venv/bin/ruff"
      elif command -v ruff >/dev/null 2>&1; then RUFF="$(command -v ruff)"; fi
      [ -n "$RUFF" ] && run_linter "$ROOT" "$RUFF" check --select F "$FILE"
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    # eslint lives in the repo; run it FROM the repo root so flat config + plugins resolve.
    if [ -n "$ROOT" ] && [ -x "$ROOT/node_modules/.bin/eslint" ]; then
      run_linter "$ROOT" "$ROOT/node_modules/.bin/eslint" --quiet "$FILE"
    fi
    ;;
  *) exit 0 ;;
esac

if [ "$RC" -ne 0 ] && [ -n "$OUT" ]; then
  {
    echo "Lint/typecheck FAILED on $(basename "$FILE") after your edit."
    echo "Fix these before continuing — do NOT claim the change works until clean:"
    echo "----"
    printf '%s\n' "$OUT" | head -40
  } >&2
  exit 2
fi
exit 0
