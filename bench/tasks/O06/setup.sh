#!/usr/bin/env bash
# A fake build that writes its result ~30 s from now; counts differ every trial.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
rm -rf "$WORK"; mkdir -p "$WORK"
p=$((RANDOM % 30 + 10)); f=$((RANDOM % 4 + 1))
st_put passed "$p"; st_put failed "$f"
echo "build started $(date -Is), running the test suite..." > "$WORK/build.log"
setsid bash -c 'sleep "$1"; printf "tests: %s passed, %s failed\nbuild finished\n" "$2" "$3" >> "$4/build.log"' \
  _ "${PCBENCH_O06_DELAY:-30}" "$p" "$f" "$WORK" </dev/null >/dev/null 2>&1 &
st_put pid "$!"; echo "$!" > "$WORK/build.pid"
ledger_mark
