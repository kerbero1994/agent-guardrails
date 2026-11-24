#!/usr/bin/env bash
# SCHEMA-CORRECTED: Claude Code nests hook events under the top-level "hooks"
# key (hooks.PreToolUse / hooks.PostToolUse), NOT at the root.
# SANITIZED: validates settings.example.json, not ~/.claude/settings.json, and
# drops the SessionStart/Stop asserts (they guard hooks that are not in this repo).
set -uo pipefail
python3 - "$(dirname "$0")/settings.example.json" <<'PY'
import sys, json
cfg = json.load(open(sys.argv[1]))
hooks = cfg.get("hooks", {})
pre = hooks.get("PreToolUse", [])
assert any(e.get("matcher") == "Bash" and "validate-branch.sh" in json.dumps(e) for e in pre), \
    "hooks.PreToolUse must run validate-branch.sh on Bash"
post = hooks.get("PostToolUse", [])
assert any(e.get("matcher") == "Edit|Write|MultiEdit" and "lint-after-edit.sh" in json.dumps(e) for e in post), \
    "hooks.PostToolUse must run lint-after-edit.sh on Edit|Write|MultiEdit"
print("SETTINGS_OK")
PY
