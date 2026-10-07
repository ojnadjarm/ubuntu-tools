#!/usr/bin/env bash
# bin/playwright-mcp: refuses to start a playwright-mcp without the idle timeout (TSP-026).
# Runs under a fake $HOME with a stub nvm and a stub playwright-mcp; no node, no browser.
set -uo pipefail
W="${PW_WRAPPER:-$HOME/agents/bin/playwright-mcp}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }

bin="$WORK/.nvm/versions/node/v24.20.0/bin"; mkdir -p "$bin"
printf 'nvm() { :; }\n' >"$WORK/.nvm/nvm.sh"
stub() {  # $1 = help text
  printf '#!/bin/sh\nif [ "$1" = --help ]; then printf "%%s\\n" "%s"; exit 0; fi\necho "STARTED $*"\n' "$1" >"$bin/playwright-mcp"
  chmod +x "$bin/playwright-mcp"
}

stub '  --headless  run headless'
out=$(HOME="$WORK" bash "$W" --config c.json 2>&1); rc=$?
[ "$rc" = 3 ] && ok 'old binary: exit 3' || nok 'old binary: exit 3' "rc=$rc"
grep -q 'no idle timeout' <<<"$out" && ok 'old binary: one-line reason' || nok 'old binary: one-line reason' "$out"
grep -q STARTED <<<"$out" && nok 'old binary: not started' "$out" || ok 'old binary: not started'

stub '  --idle-timeout <timeout>  close the browser after this many milliseconds'
out=$(HOME="$WORK" bash "$W" --config c.json 2>&1); rc=$?
[ "$rc" = 0 ] && ok 'new binary: exit 0' || nok 'new binary: exit 0' "rc=$rc $out"
grep -q "STARTED --headless --user-data-dir $WORK/agents/browser/profile-default --config c.json" <<<"$out" \
  && ok 'new binary: started with the usual args' || nok 'new binary: started with the usual args' "$out"

exit $bad
