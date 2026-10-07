#!/usr/bin/env bash
# disk-report sums a tree.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
head -c 2048 /dev/zero >"$W/a"; mkdir "$W/d"; head -c 1024 /dev/zero >"$W/d/b"
[ "$("$BIN/disk-report" "$W" | cut -f2)" = "3.0 KB" ] && echo "ok   disk-report 3.0 KB" ||
  { echo "FAIL disk-report: $("$BIN/disk-report" "$W")"; exit 1; }
