#!/usr/bin/env bash
# pc-tmp on a fixture PC_TMP_ROOT with a fake history.md, claims board, ledger, one held fd and one held cwd: only the 4 eligible paths go; --if-over gates on a stub df; a chmod 000 dir fails loud; stub watchman daemons: gone or idle > 1 h TMPDIR under the root TERMed, fresh, default, outside and unset kept.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
R=$(mktemp -d); HOLDER=; CWDER=
trap '[ -s "$R/wm.pids" ] && kill $(cut -d" " -f1 "$R/wm.pids") 2>/dev/null; [ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; [ -n "$CWDER" ] && kill "$CWDER" 2>/dev/null; chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

case $R in /tmp/*) ok 'sandbox: fixture root under /tmp';; *) nok sandbox "$R"; exit 1;; esac
export PC_TMP_ROOT="$R/root" PC_TMP_HISTORY="$R/history.md" PC_TMP_CLAIMS="$R/claims.md" PC_LEDGER="$R/changes.jsonl"
S="$R/root/claude-$(id -u)/-home-x/sess/scratchpad"; V="$R/root/claude-$(id -u)/-home-x-moodle-envs-vass/sess/scratchpad"
for d in tmp.old tmp.new tmp.held remotion-webpack-bundle-a; do mkdir -p "$R/root/$d"; echo x >"$R/root/$d/f"; done
for d in T100 T101 T102 T103 T104-x mov young cwd.held char3d-x Char3D-y VASS-z t714int; do mkdir -p "$S/$d/sub"; echo x >"$S/$d/sub/f"; done
mkdir -p "$V/T100" "$V/mov"; echo x >"$V/T100/f"; echo x >"$V/mov/f"; echo x >"$R/root/cc1.ltrans0.o"
printf -- '- 2026-10-01 T100: done\n- 2026-10-01 T102 (w1): done\n- 2026-10-01 T103: done\n- 2026-10-01 T104: done\n- 2026-10-01 T999: see T101\n' >"$PC_TMP_HISTORY"
printf -- '- T102 · /x · 2026-10-01 10:00\n' >"$PC_TMP_CLAIMS"

age() { find "$1" -exec touch -h -d "-$2 hours" {} +; }
age "$R/root" 30
age "$R/root/tmp.new" 2; age "$R/root/cc1.ltrans0.o" 2; age "$S/T103" 2; age "$S/young" 2
touch "$S/T104-x/sub/f"
sleep 600 9<"$R/root/tmp.held/f" & HOLDER=$!
(cd "$S/cwd.held/sub" && exec sleep 600) & CWDER=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "/proc/$HOLDER/fd/9" ] && [ "$(readlink "/proc/$CWDER/cwd")" = "$S/cwd.held/sub" ] && break; sleep 0.1; done

dry=$("$BIN/pc-tmp")
is 'header' "$(head -1 <<<"$dry" | tr -s ' ')" 'KIND PATH MB AGE REASON'
is 'dry run lists the 4 eligible' "$(awk 'NR > 1 && $1 != "would:" && $1 != "kept" {print $1, $2}' <<<"$dry" | sed "s#$R/root/##" | sort | tr '\n' ';')" \
  "build remotion-webpack-bundle-a;scratch claude-$(id -u)/-home-x/sess/scratchpad/T100;scratch-idle claude-$(id -u)/-home-x/sess/scratchpad/mov;test-dir tmp.old;"
is 'held fd and cwd counted as kept' "$(grep -c '^kept (o[p]en fd/cwd): 2$' <<<"$dry")" 1
is 'dry run deletes nothing' "$(find "$R/root" -name f | wc -l)" 18
[ ! -e "$PC_LEDGER" ] && ok 'dry run writes no ledger' || nok 'dry run ledger' 'written'

mkdir -p "$R/stub"; printf '#!/bin/sh\nprintf "Used\\n%%s\\n" "$STUB_USED"\n' >"$R/stub/df"; chmod +x "$R/stub/df"
under=$(PATH="$R/stub:$PATH" STUB_USED=1073741824 "$BIN/pc-tmp" --apply --if-over 2G); rc=$?
is 'under the limit: nothing line, exit 0' "$rc|$under" '0|nothing: /tmp 1.0 GB < 2.0 GB'
is 'under the limit deletes nothing' "$(find "$R/root" -name f | wc -l)" 18
[ ! -e "$PC_LEDGER" ] && ok 'under the limit writes no ledger' || nok 'under ledger' 'written'
over=$(PATH="$R/stub:$PATH" STUB_USED=3221225472 "$BIN/pc-tmp" --if-over 2G)
is 'over the limit: the sweep lists the 4 eligible' "$(awk 'NR > 1 && $1 != "would:" && $1 != "kept" {n++} END {print n}' <<<"$over")|$(tail -1 <<<"$over" | cut -d' ' -f1)" '4|would:'
PATH="$R/stub:$PATH" STUB_USED=1 "$BIN/pc-tmp" --if-over 2X >/dev/null 2>&1; is 'bad size exits 2' "$?" 2

out=$("$BIN/pc-tmp" --apply)
is 'last line is the rollback note' "$(tail -1 <<<"$out")" 'rollback: none, scratch only'
left=$(cd "$R/root" && find . -name f -o -name '*.o' | LC_ALL=C sort | tr '\n' ' ')
is 'only the 4 eligible removed' "$left" \
  "./cc1.ltrans0.o ./claude-$(id -u)/-home-x-moodle-envs-vass/sess/scratchpad/T100/f ./claude-$(id -u)/-home-x-moodle-envs-vass/sess/scratchpad/mov/f ./claude-$(id -u)/-home-x/sess/scratchpad/Char3D-y/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/T101/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/T102/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/T103/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/T104-x/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/VASS-z/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/char3d-x/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/cwd.held/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/t714int/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/young/sub/f ./tmp.held/f ./tmp.new/f "
is 'one ledger entry' "$(jq -r '.rollback + "|" + .before' "$PC_LEDGER")" 'none, scratch only|4 paths, 4 MB'
is 'ledger after counts deleted and failed' "$(jq -r '"\(.after)|\(.verified)"' "$PC_LEDGER")" 'deleted 4, failed 0|true'

W="$R/root"; mkdir -p "$R/stubw" "$W/tmp.wgone" "$W/tmp.widle" "$W/tmp.wfresh"; age "$W/tmp.widle" 2; export WM_PIDS="$R/wm.pids"; : >"$WM_PIDS"
printf '#!/bin/bash\necho "$$ ${TMPDIR-}" >>"$WM_PIDS"; cd /; while :; do sleep 0.2; done\n' >"$R/stubw/watchman"; chmod +x "$R/stubw/watchman"
for t in "$W/tmp.wgone" "$W/tmp.widle" "$W/tmp.wfresh" "$W" "$R/outside"; do TMPDIR=$t setsid "$R/stubw/watchman" </dev/null >/dev/null 2>&1 & done
env -u TMPDIR setsid "$R/stubw/watchman" </dev/null >/dev/null 2>&1 &
for _ in $(seq 50); do [ "$(wc -l <"$WM_PIDS")" -ge 6 ] && break; sleep 0.1; done; rm -rf "$W/tmp.wgone"
pid() { awk -v t="$1" '$2 == t {print $1}' "$WM_PIDS"; }
alive() { local p; p=$(pid "$1"); [ -n "$p" ] && [ -d "/proc/$p" ] && ! grep -q '^State:.*Z' "/proc/$p/status" 2>/dev/null; }
dry=$("$BIN/pc-tmp")
is 'daemon: dry run lists the gone and idle TMPDIR watchman' "$(awk '$1 == "daemon" {print $2, $4}' <<<"$dry" | sed "s#$W/##" | sort | tr '\n' ';')" 'tmp.wgone gone;tmp.widle 2h;'
grep -q "watchman $(pid "$W/tmp.widle"), TMPDIR idle 2h > 1h" <<<"$dry" && ok 'daemon: reason names the pid' || nok reason "$dry"
alive "$W/tmp.widle" && ok 'daemon: dry run kills nothing' || nok 'dry kill' 'idle stub gone'
n=$(wc -l <"$PC_LEDGER"); out=$("$BIN/pc-tmp" --apply); rc=$?
is 'daemon: apply exits 0 and counts both' "$rc $(grep -o 'deleted [0-9]*, failed [0-9]*' <<<"$out")" '0 deleted 2, failed 0'
! alive "$W/tmp.wgone" && ! alive "$W/tmp.widle" && ok 'daemon: gone and idle TMPDIR watchman stopped' || nok stop 'still running'
k=; for t in "$W/tmp.wfresh" "$W" "$R/outside" ''; do alive "$t" && k+=1; done
is 'daemon: fresh, default, outside-root and unset TMPDIR kept' "$k" 1111
is 'daemon: one more ledger entry' "$(( $(wc -l <"$PC_LEDGER") - n ))" 1

for d in orbit-test-a run-tests.b night-probe-c t999-d tmpabc orbit-test-young keep-me; do mkdir -p "$R/root/$d"; echo x >"$R/root/$d/f"; done
echo x >"$R/root/t714-f.log"
for d in orbit-test-a run-tests.b night-probe-c t999-d tmpabc keep-me t714-f.log; do age "$R/root/$d" 30; done; age "$R/root/orbit-test-young" 2
dry=$("$BIN/pc-tmp")
is 'test-dir: dry run lists the 5 leaked test dirs' "$(awk '$1 == "test-dir" {print $2}' <<<"$dry" | sed "s#$R/root/##" | sort | tr '\n' ';')" \
  'night-probe-c;orbit-test-a;run-tests.b;t999-d;tmpabc;'
out=$("$BIN/pc-tmp" --apply); rc=$?
is 'test-dir: apply removes the 5' "$rc $(grep -o 'deleted [0-9]*, failed [0-9]*' <<<"$out")" '0 deleted 5, failed 0'
k=; for d in orbit-test-young keep-me t714-f.log; do [ -e "$R/root/$d" ] && k+=1; done
is 'test-dir: young, unmatched and plain-file entries kept' "$k" 111

L="$R/root/tmp.locked"; mkdir -p "$L/d" "$R/root/tmp.free"; echo x >"$L/d/f"; echo x >"$R/root/tmp.free/f"
age "$L" 30; age "$R/root/tmp.free" 30; chmod 000 "$L/d"
if [ -r "$L/d" ]; then ok 'skip: chmod 000 is readable (root), rm failure not testable'; else
  out=$("$BIN/pc-tmp" --apply 2>"$R/err"); rc=$?
  is 'an rm -rf that leaves a path exits 1' "$rc" 1
  is 'stdout counts deleted and failed' "$(grep -o 'deleted [0-9]*, failed [0-9]*' <<<"$out")" 'deleted 1, failed 1'
  is 'ledger after names the failure, verified false' "$(tail -1 "$PC_LEDGER" | jq -r '"\(.after)|\(.verified)"')" "deleted 1, failed 1: $L|false"
  is 'stderr names the failed path' "$(cat "$R/err")" "pc tmp: still present after rm -rf: $L"
fi

PC_TMP_ROOT=/usr "$BIN/pc-tmp" >/dev/null 2>&1; is 'root outside /tmp refused' "$?" 2
exit $bad
