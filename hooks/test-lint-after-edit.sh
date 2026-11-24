#!/usr/bin/env bash
# Tests for lint-after-edit.sh. Uses the py_compile path (always available)
# so it runs anywhere, regardless of ruff/eslint being installed.
set -uo pipefail
HOOK="$(dirname "$0")/lint-after-edit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# run <json> -> sets RC and ERR
run() { ERR="$(printf '%s' "$1" | bash "$HOOK" 2>&1 >/dev/null)"; RC=$?; }
ok()  { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  PASS: $3"; else FAIL=$((FAIL+1)); echo "  FAIL: $3 (got rc=$1 want $2) ${4:-}"; fi; }

# T1: non-matching tool -> exit 0
run '{"tool_name":"Read","tool_input":{"file_path":"/x.py"},"cwd":"'"$TMP"'"}'
ok "$RC" 0 "non-matching tool (Read) ignored"

# T2: non-matching extension -> exit 0
echo "hello" > "$TMP/note.txt"
run '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP/note.txt"'"},"cwd":"'"$TMP"'"}'
ok "$RC" 0 ".txt extension ignored"

# T3: python syntax error -> exit 2, stderr mentions FAILED
printf 'def broken(:\n    pass\n' > "$TMP/bad.py"
run '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP/bad.py"'"},"cwd":"'"$TMP"'"}'
ok "$RC" 2 "python syntax error blocks"
case "$ERR" in *FAILED*) PASS=$((PASS+1)); echo "  PASS: stderr explains failure";; *) FAIL=$((FAIL+1)); echo "  FAIL: stderr should mention FAILED";; esac

# T4: clean python -> exit 0
printf 'def good():\n    return 1\n' > "$TMP/good.py"
run '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP/good.py"'"},"cwd":"'"$TMP"'"}'
ok "$RC" 0 "clean python passes"

# T5: file under node_modules -> skipped (exit 0) even if broken
mkdir -p "$TMP/node_modules"
printf 'def broken(:\n' > "$TMP/node_modules/dep.py"
run '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP/node_modules/dep.py"'"},"cwd":"'"$TMP"'"}'
ok "$RC" 0 "node_modules path skipped"

# T6: missing file -> exit 0
run '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP/ghost.py"'"},"cwd":"'"$TMP"'"}'
ok "$RC" 0 "missing file ignored"

# T7: relative path resolved against cwd
printf 'x =\n' > "$TMP/rel.py"
run '{"tool_name":"Edit","tool_input":{"file_path":"rel.py"},"cwd":"'"$TMP"'"}'
ok "$RC" 2 "relative path resolved + syntax error caught"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
