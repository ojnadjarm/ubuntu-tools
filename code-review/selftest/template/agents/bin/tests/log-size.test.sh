#!/usr/bin/env bash
# log-size lists *.log files largest first.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
head -c 100 /dev/zero >"$W/small.log"; head -c 5000 /dev/zero >"$W/big.log"; echo x >"$W/skip.txt"
[ "$("$BIN/log-size" "$W" | head -1)" = "$(printf '4.9 KB\tbig.log')" ] && echo "ok   log-size order" ||
  { echo "FAIL log-size: $("$BIN/log-size" "$W")"; exit 1; }
