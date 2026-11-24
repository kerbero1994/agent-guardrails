#!/usr/bin/env bash
# Runs every test in the repo. Exit 0 only if all of them pass.
cd "$(dirname "$0")" || exit 1
fail=0
for t in */test-*.sh; do
  echo "=== $t"
  bash "$t" || { echo "FAILED: $t"; fail=1; }
done
exit "$fail"
