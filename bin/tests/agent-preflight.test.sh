#!/usr/bin/env bash
# agent-preflight: clean fixture repo rc 0, dirty-but-older rc 0, src newer than the body rc 1, test newer rc 0, inactive unit "not running", silent systemctl/find/cd error rc 1, deleted or renamed src file rc 1, concurrent runs agree, live hand-run body rc 1, sandbox body rc 0, within a load-aware budget.
# Runs inside bwrap --unshare-net with a private /tmp; probes are PATH stubs and the repo is a throwaway fixture.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${PF_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --unshare-net --tmpfs /tmp --setenv TMPDIR /tmp --setenv PF_SANDBOXED 1 -- bash "$SELF"
fi
. "$BIN/tests/lib/assert.sh"
. "$BIN/tests/lib/budget.sh"
PF="$BIN/agent-preflight"

WORK=$(mktemp -d); trap 'kill ${BODY:-} 2>/dev/null; rm -rf "$WORK"' EXIT
if curl -sS -m 3 -o /dev/null https://example.com 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
ok 'selftest: the sandbox has no route out'

S="$WORK/stubs"; mkdir -p "$S"
STARTED=$(( $(date +%s) - 3600 ))
printf '#!/bin/sh\n[ "$(cat %s/state 2>/dev/null)" = none ] && exit 1\nprintf "ActiveState=%%s\\nSubState=running\\nNRestarts=0\\nMainPID=4242\\nActiveEnterTimestamp=@%s\\n" "$(cat %s/state 2>/dev/null || echo active)"\n' "$WORK" "$STARTED" "$WORK" >"$S/systemctl"
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

mkdir -p "$DARK_EYE_DIR/body/src" "$DARK_EYE_DIR/body/test" "$DARK_EYE_DIR/bridge/relay/tests"
touch -d "@$((STARTED - 60))" "$DARK_EYE_DIR/body/src/main.js"
out=$("$PF" --brief 2>&1); rc=$?
is 'dirty but older than the body: rc 0' "$rc" 0
grep -q '^TREE      1 dirty, 0 newer than the running body (started .*) — a restart ships the running code' <<<"$out" \
  && ok 'dirty-older: TREE says 0 newer' || nok 'dirty-older: screen' "$out"

touch "$DARK_EYE_DIR/body/test/x.test.js" "$DARK_EYE_DIR/bridge/relay/tests/latency.test.sh" "$DARK_EYE_DIR/body/src/remote.test.js"
out=$("$PF" --brief 2>&1); rc=$?
is 'only test files newer: rc 0' "$rc" 0
grep -q '^TREE      [0-9]* dirty, 0 newer' <<<"$out" && ok 'tests-newer: not counted' || nok 'tests-newer: screen' "$out"

touch "$DARK_EYE_DIR/body/src/main.js"
out=$("$PF" --brief 2>&1); rc=$?
is 'src file newer than the body: rc 1' "$rc" 1
grep -q '^TREE      [0-9]* dirty, 1 newer than the running body .*DO NOT RESTART: body/src/main.js$' <<<"$out" \
  && ok 'src-newer: DO NOT RESTART names the file' || nok 'src-newer: screen' "$out"
echo inactive >"$WORK/state"
out=$("$PF" --brief 2>&1); rc=$?
is 'inactive unit: rc 0' "$rc" 0
grep -q '^TREE      body not running ' <<<"$out" && ok 'inactive: TREE body not running' || nok 'inactive: screen' "$out"
echo none >"$WORK/state"
out=$("$PF" --brief 2>&1); rc=$?
is 'systemctl prints nothing: rc 1' "$rc" 1
grep -q '^TREE      unknown (systemctl show dark-eye printed nothing) — do not restart$' <<<"$out" && grep -q '^UNIT      ?/?' <<<"$out" \
  && grep -q '^HAND-RUN  ' <<<"$out" && ok 'silent systemctl: UNIT ?/?, TREE unknown, full screen' || nok 'silent systemctl: screen' "$out"
rm "$WORK/state"
for i in 1 2 3 4 5; do "$PF" --brief >"$WORK/par$i" 2>&1 & done; wait
n=$(grep -l 'DO NOT RESTART: body/src/main.js$' "$WORK"/par? | wc -l)
is 'five concurrent runs all see the newer file' "$n" 5
ls -d /tmp/.pf.* /tmp/tmp.* 2>/dev/null | grep -q . && nok 'no temp residue' "$(ls -d /tmp/.pf.* /tmp/tmp.* 2>/dev/null)" || ok 'no temp residue'

mkdir -p "$DARK_EYE_DIR/body/src/locked"; chmod 000 "$DARK_EYE_DIR/body/src/locked"
out=$("$PF" --brief 2>&1); rc=$?
is 'find error: rc 1' "$rc" 1
grep -q '^TREE      unknown (find: .*Permission denied) — do not restart$' <<<"$out" && ok 'find error: TREE unknown' || nok 'find error: screen' "$out"
chmod 755 "$DARK_EYE_DIR/body/src/locked"
out=$(DARK_EYE_DIR="$WORK/missing" "$PF" --brief 2>&1); rc=$?
is 'cd error: rc 1' "$rc" 1
grep -q '^TREE      unknown (cd: .*) — do not restart$' <<<"$out" && ok 'cd error: TREE unknown' || nok 'cd error: screen' "$out"
rm -rf "$DARK_EYE_DIR/body" "$DARK_EYE_DIR/bridge"

mkdir -p "$DARK_EYE_DIR/body/src/lib"
touch -d "@$((STARTED - 60))" "$DARK_EYE_DIR/body/src/lib/gone.js"
git -C "$DARK_EYE_DIR" add body && git -C "$DARK_EYE_DIR" -c user.name=t -c user.email=t@t commit -qm fixture
rm "$DARK_EYE_DIR/body/src/lib/gone.js"
out=$("$PF" --brief 2>&1); rc=$?
is 'tracked src file deleted after the start: rc 1' "$rc" 1
grep -q '^TREE      1 dirty, 1 newer than the running body .*DO NOT RESTART: body/src/lib/gone.js$' <<<"$out" \
  && ok 'deleted: counted as newer' || nok 'deleted: screen' "$out"
touch -d "@$((STARTED - 30))" "$DARK_EYE_DIR/body/src/lib"
out=$("$PF" --brief 2>&1); rc=$?
is 'tracked src file deleted before the start: rc 0' "$rc" 0
grep -q '^TREE      1 dirty, 0 newer' <<<"$out" && ok 'deleted-before: not counted' || nok 'deleted-before: screen' "$out"
git -C "$DARK_EYE_DIR" add -A && git -C "$DARK_EYE_DIR" -c user.name=t -c user.email=t@t commit -qm gone
touch -d "@$((STARTED - 60))" "$DARK_EYE_DIR/body/src/lib/a.js"
git -C "$DARK_EYE_DIR" add body && git -C "$DARK_EYE_DIR" -c user.name=t -c user.email=t@t commit -qm a
touch -d "@$((STARTED - 30))" "$DARK_EYE_DIR/body/src/lib"
git -C "$DARK_EYE_DIR" mv body/src/lib/a.js body/src/lib/b.js
out=$("$PF" --brief 2>&1); rc=$?
is 'staged rename after the start (mtime kept): rc 1' "$rc" 1
grep -q '^TREE      1 dirty, 1 newer than the running body .*DO NOT RESTART: body/src/lib/a.js$' <<<"$out" \
  && ok 'renamed: old path counted as newer' || nok 'renamed: screen' "$out"
rm -rf "$DARK_EYE_DIR"; git init -q "$DARK_EYE_DIR"

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
