#!/bin/sh
# guard.sh v2, after the incidents. macOS only (lockf, memory_pressure).
#
#   guard.sh CMD [ARGS...]
#
# Runs CMD under one machine-wide lock, and only with >= 40 % free memory and
# load <= 20 (integer part of the 1-minute average), measured once the lock is
# ours. Exit 75 means "try later": the lock stayed busy, resources are low, or
# they could not be measured. Otherwise the exit code is CMD's own, except when
# CMD is killed by a signal or lockf itself fails (see lockf(1)).
#
#   HEAVY_LOCK       lock file (default /tmp/heavy.lock)
#   HEAVY_LOCK_WAIT  seconds to wait for the lock (default 600)
#   HEAVY_LOCK_HELD  set by guard.sh for CMD and its children; a nested
#                    guard.sh sees it and does not ask for the lock again
#
# What changed from the version that ran (v1):
#   - v1 left the lock to the caller, and `lockf` without -t waits forever.
#     v2 takes the lock itself with -t and gives up with 75.
#   - v1 relied on a person setting HEAVY_LOCK_HELD=1 for nested steps.
#     v2 sets it for everything it runs.
#   - v1 ran the command when the numbers could not be read
#     ("integer expression expected"). v2 refuses with 75.

if [ -z "${HEAVY_LOCK_HELD:-}" ]; then
  export HEAVY_LOCK_HELD=1
  exec lockf -k -t "${HEAVY_LOCK_WAIT:-600}" "${HEAVY_LOCK:-/tmp/heavy.lock}" /bin/sh "$0" "$@"
fi

f=$(memory_pressure | tail -1 | grep -o "[0-9]*%" | tr -d %)
l=$(sysctl -n vm.loadavg | cut -d" " -f2 | cut -d. -f1)
echo "free=$f load=$l"
case "$f" in ''|*[!0-9]*) echo SKIP_CANNOT_MEASURE; exit 75 ;; esac
case "$l" in ''|*[!0-9]*) echo SKIP_CANNOT_MEASURE; exit 75 ;; esac
if [ "$f" -lt 40 ] || [ "$l" -gt 20 ]; then echo SKIP_LOW_RESOURCES; exit 75; fi
exec "$@"
