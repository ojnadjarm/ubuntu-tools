#!/usr/bin/env bash
# agent-preflight: clean fixture repo rc 0, dirty rc 1, live hand-run body rc 1, sandbox body rc 0, within a load-aware budget.
# Runs inside bwrap --unshare-net with a private /tmp; probes are PATH stubs and the repo is a throwaway fixture.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${PF_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --unshare-net --tmpfs /tmp --setenv PF_SANDBOXED 1 -- bash "$SELF"
fi
. "$BIN/tests/lib/assert.sh"
. "$BIN/tests/lib/budget.sh"
PF="$BIN/agent-preflight"

WORK=$(mktemp -d); trap 'kill ${BODY:-} 2>/dev/null; rm -rf "$WORK"' EXIT
if curl -sS -m 3 -o /dev/null https://example.com 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
ok 'selftest: the sandbox has no route out'

S="$WORK/stubs"; mkdir -p "$S"
printf '#!/bin/sh\nprintf "ActiveState=active\\nSubState=running\\nNRestarts=0\\nMainPID=4242\\n"\n' >"$S/systemctl"
printf '#!/bin/sh\necho "[eye-render] backend vulkan"; echo "eye up at 10:00"\n' >"$S/journalctl"
printf '#!/bin/sh\necho "fixture-$1"\n' >"$S/eye"
printf '#!/bin/sh\n[ "$1" = get-default-sink ] && echo fixture-sink\n:\n' >"$S/pactl"
printf '#!/bin/sh\n:\n' >"$S/pw-metadata"
printf '#!/bin/sh\n[ "$2" = eye-render ] && cat "%s/pids" 2>/dev/null\n:\n' "$WORK" >"$S/pgrep"
chmod +x "$S"/*
export PATH="$S:$PATH" DARK_EYE_DIR="$WORK/eye"
for c in systemctl journalctl eye pactl pw-metadata pgrep; do
  [ "$(command -v "$c")" = "$S/$c" ] || { echo "FAIL selftest: real $c reachable"; exit 1; }
done
ok 'selftest: every probe resolves to a stub'
git init -q "$DARK_EYE_DIR"

t0=$(date +%s.%N); out=$("$PF" 2>&1); rc=$?; t1=$(date +%s.%N)
is 'clean tree, no hand-run body: rc 0' "$rc" 0
grep -q '^TREE      0 dirty' <<<"$out" && grep -q '^HAND-RUN  none' <<<"$out" && grep -q 'fixture-health' <<<"$out" \
  && ok 'clean: TREE 0, HAND-RUN none, stubbed bridge' || nok 'clean: screen' "$out"
lim=$(budget 0.5)
awk -v a="$t0" -v b="$t1" -v l="$lim" 'BEGIN{exit !(b-a <= l)}' && ok "clean run within budget ${lim}s" \
  || nok 'budget' "$(awk -v a="$t0" -v b="$t1" 'BEGIN{print b-a}')s > ${lim}s"
out=$("$PF" --brief 2>&1); rc=$?
is '--brief: rc 0' "$rc" 0
grep -q '^RULES' <<<"$out" && nok '--brief drops RULES/COMMANDS' "$out" || ok '--brief drops RULES/COMMANDS'

touch "$DARK_EYE_DIR/half-applied.js"
out=$("$PF" --brief 2>&1); rc=$?
is 'dirty tree: rc 1' "$rc" 1
grep -q '^TREE      1 dirty.*DO NOT RESTART' <<<"$out" && ok 'dirty: TREE says DO NOT RESTART' || nok 'dirty: screen' "$out"
rm "$DARK_EYE_DIR/half-applied.js"

mkdir -p "$WORK/the-dark-eye/body"
printf '#!/bin/sh\nwhile :; do sleep 0.2; done\n' >"$WORK/the-dark-eye/body/eye-render"; chmod +x "$WORK/the-dark-eye/body/eye-render"
env -u DARK_EYE_SANDBOX "$WORK/the-dark-eye/body/eye-render" 60 & BODY=$!
echo "$BODY" >"$WORK/pids"; sleep 0.2
out=$("$PF" --brief 2>&1); rc=$?
is 'hand-run body outside the unit cgroup: rc 1' "$rc" 1
grep -q "^HAND-RUN   $BODY — outside the unit cgroup, DO NOT RESTART" <<<"$out" && ok 'hand-run: pid named' || nok 'hand-run: screen' "$out"
kill "$BODY"; wait "$BODY" 2>/dev/null

DARK_EYE_SANDBOX=t1 "$WORK/the-dark-eye/body/eye-render" 60 & BODY=$!
echo "$BODY" >"$WORK/pids"; sleep 0.2
out=$("$PF" --brief 2>&1); rc=$?
is 'sandbox body (DARK_EYE_SANDBOX): rc 0' "$rc" 0
grep -q "^HAND-RUN  none   sandbox: $BODY" <<<"$out" && ok 'sandbox: listed as sandbox, not hand-run' || nok 'sandbox: screen' "$out"
exit $bad
