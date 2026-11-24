#!/usr/bin/env bash
# Tests for guard.sh v2. Plain bash, no bats. macOS only (real lockf).
# memory_pressure and sysctl are faked on PATH, so the numbers are set per case.
# GUARD=<path> runs the same cases against another version: that is how the
# v1 failures listed in the README were produced.
set -uo pipefail
GUARD="${GUARD:-$(cd "$(dirname "$0")" && pwd)/guard.sh}"

TMP="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_FREE}%%"\n' > "$TMP/bin/memory_pressure"
printf '#!/bin/sh\necho "{ ${FAKE_LOAD} 1.00 1.00 }"\n' > "$TMP/bin/sysctl"
chmod +x "$TMP/bin/memory_pressure" "$TMP/bin/sysctl"
export PATH="$TMP/bin:$PATH" HEAVY_LOCK="$TMP/heavy.lock" HEAVY_LOCK_WAIT=1 FAKE_FREE=50 FAKE_LOAD=3.10
unset HEAVY_LOCK_HELD

pass=0; fail=0
run() { OUT="$(env "$@" 2>&1)"; RC=$?; }  # run [VAR=val...] cmd... -> RC, OUT
check() { # desc want_rc [must_contain] [must_not_contain]
  local ok=1
  [ "$RC" = "$2" ] || ok=0
  [ -z "${3:-}" ] || case "$OUT" in *"$3"*) ;; *) ok=0 ;; esac
  [ -z "${4:-}" ] || case "$OUT" in *"$4"*) ok=0 ;; esac
  if [ "$ok" = 1 ]; then echo "ok: $1"; pass=$((pass+1))
  else echo "FAIL: $1 (rc=$RC, want $2) $(printf '%s' "$OUT" | tr '\n' ' ')"; fail=$((fail+1)); fi
}

# --- row 2: measure before heavy work ---
run sh "$GUARD" echo RAN_IT;                  check "runs with resources"        0  RAN_IT
run FAKE_FREE=30 sh "$GUARD" echo RAN_IT;     check "low memory blocks"          75 "" RAN_IT
run FAKE_LOAD=25.4 sh "$GUARD" echo RAN_IT;   check "high load blocks"           75 "" RAN_IT
run FAKE_FREE= sh "$GUARD" echo RAN_IT;       check "unreadable memory blocks"   75 SKIP_CANNOT_MEASURE RAN_IT
run FAKE_LOAD=x sh "$GUARD" echo RAN_IT;      check "unreadable load blocks"     75 "" RAN_IT
run HEAVY_LOCK_HELD=1 FAKE_FREE=30 sh "$GUARD" echo RAN_IT
check "flag already set still measures" 75 "" RAN_IT

# --- the lock: a busy lock fails fast instead of hanging ---
BUSY="$TMP/busy.lock"
lockf -k "$BUSY" sleep 6 & holder=$!
for _ in $(seq 1 25); do lockf -k -t 0 "$BUSY" true 2>/dev/null || break; sleep 0.2; done
( HEAVY_LOCK="$BUSY" sh "$GUARD" echo RAN_IT > "$TMP/busy.out" 2>&1; echo $? > "$TMP/busy.rc" ) &
for _ in $(seq 1 25); do [ -f "$TMP/busy.rc" ] && break; sleep 0.2; done
if [ -f "$TMP/busy.rc" ]; then RC="$(cat "$TMP/busy.rc")"; OUT="$(cat "$TMP/busy.out")"
else RC=hung; OUT="still waiting after 5 s"; fi
check "busy lock fails fast" 75 "" RAN_IT
kill "$holder" 2>/dev/null

# --- row 3: no lock inside a lock ---
run sh "$GUARD" sh -c 'echo "flag=$HEAVY_LOCK_HELD"'; check "child sees the flag"     0  flag=1
run sh "$GUARD" sh "$GUARD" echo INNER;               check "nested guard passes"     0  INNER
run sh "$GUARD" env -u HEAVY_LOCK_HELD sh "$GUARD" echo INNER
check "nested guard without the flag waits on its own lock" 75 "" INNER

# --- plumbing ---
run sh "$GUARD" printf '%s|' 'a b' c;  check "arguments survive"          0 "a b|c|"
run sh "$GUARD" sh -c 'exit 3';        check "exit code passes through"   3
cp "$GUARD" "$TMP/noexec.sh"; chmod 644 "$TMP/noexec.sh"
run sh "$TMP/noexec.sh" echo RAN_IT;   check "works without the exec bit" 0 RAN_IT

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
