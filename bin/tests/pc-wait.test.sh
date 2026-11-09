#!/usr/bin/env bash
# pc wait beside a stub pc-shot and a stub sleep: no screenshot is taken; usage and exit codes.
set -uo pipefail
BIN="$HOME/agents/bin"
. "$BIN/tests/lib/assert.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp "$BIN/pc-wait" "$W/pc-wait"
printf '#!/bin/sh\necho "shot $*"\n' >"$W/pc-shot"
printf '#!/bin/sh\necho "sleep $*" >>"%s/log"\n' "$W" >"$W/sleep"
chmod +x "$W"/*
w() { PATH="$W:$PATH" "$W/pc-wait" "$@"; }

is 'selftest: the copy resolves pc-shot to the stub' "$(w 1)" 'shot '
is 'sleeps S then passes the rest to pc shot' "$(w 2 --win x)|$(tail -1 "$W/log")" 'shot --win x|sleep 2'
is '-h prints the usage, exit 0' "$(w -h; echo $?)" $'usage: pc wait SECONDS [shot args]\n0'
out=$(w 2>&1); is 'no args: usage, exit 2' "$?|$out" '2|usage: pc wait SECONDS [shot args]'
exit $bad
