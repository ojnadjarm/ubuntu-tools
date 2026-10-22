#!/usr/bin/env bash
# agent-verify on a temp HOME and AGENT_WORK: a brief's CHECK verdict, and --recheck red→green, red→red, out-of-window, green and suite-runner skipped, verdicts load/drift/real, a private TMPDIR per CHECK, --ticket picks its own section's CHECK in a multi-CHECK file, which without a T<nn> name needs --ticket, sbin dirs appended to a PATH that lacks them, a stub watchman on the CHECK's TMPDIR stopped while foreign and default ones stay.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
REAL_HOME=$HOME
WORK=$(mktemp -d); trap '[ -s "$WORK/wm.pids" ] && kill $(cut -d" " -f1 "$WORK/wm.pids") 2>/dev/null; rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

export HOME="$WORK/home" AGENT_WORK="$WORK/aw" QUIET_LOADAVG="$WORK/loadavg" QUIET_NPROC=4 QUIET_EVERY=1
echo '0.10 0.10 0.10 1/100 1' >"$QUIET_LOADAVG"
E="$AGENT_WORK/evidence"; mkdir -p "$HOME" "$WORK/cwd" "$WORK/tests" "$E"/{T1,T2,T3,T4,T5,T6,T7,T8}
[ "$HOME" != "$REAL_HOME" ] && [ "${AGENT_WORK#"$WORK"}" != "$AGENT_WORK" ] && ok 'sandbox: HOME and AGENT_WORK are temp dirs' \
  || { nok sandbox 'real HOME or AGENT_WORK'; exit 1; }
iso() { date -d "@$(( $(date +%s) - $1 ))" +%Y-%m-%dT%H:%M:%S%:z; }
rec() { jq -n --arg t "$1" --arg c "$2" --arg s "$(iso "$3")" --argjson ok "$4" --arg cwd "$WORK/cwd" \
  '{ticket:$t, brief:"/x", check:$c, cwd:$cwd, rc:(if $ok then 0 else 1 end), ok:$ok, started:$s, seconds:0}' >"$E/$1/check.json"; }

printf '# T9\nCHECK: `test -e "$AGENT_WORK/flag"`\n' >"$WORK/T9-x.md"
"$BIN/agent-verify" "$WORK/T9-x.md" >/dev/null; is 'brief: red verdict exits 1' $? 1
is 'brief: check.json written' "$(jq -r '"\(.ticket) \(.ok) \(.rc)"' "$E/T9/check.json")" 'T9 false 1'

rec T1 'test -e "$AGENT_WORK/flag" && test "$PWD" = "'"$WORK/cwd"'"' 3600 false
rec T2 'exit 3' 7200 false
jq --arg s "$(iso 86400)" '.runs = [{started:$s, rc:1, ok:false, seconds:0}]' "$E/T2/check.json" >"$WORK/t" && mv "$WORK/t" "$E/T2/check.json"
rec T3 'touch "$AGENT_WORK/T3.ran"' 691200 false
rec T4 'touch "$AGENT_WORK/T4.ran"' 600 true
printf 'touch "$AGENT_WORK/suite.ran${1:+.only}"; exit 1\n' >"$WORK/tests/run.sh"
rec T5 "bash $WORK/tests/run.sh" 600 false
rec T6 "bash $WORK/tests/run.sh --only x" 600 false
echo 'FAIL 111/114 files in 73 s' >"$E/T7/fresh-suite.txt"
rec T7 'f=$(ls -t "$AGENT_WORK"/evidence/*/fresh-suite.txt | head -1); n=$(grep -oE '"'^[0-9]+/[0-9]+'"' "$f" | tail -1 | cut -d/ -f1); test "${n:-0}" -ge 100' 600 false
echo '90/114 files' >"$E/T8/out.txt"
rec T8 'n=$(grep -oE '"'^[0-9]+/[0-9]+'"' "$AGENT_WORK/evidence/T8/out.txt" | cut -d/ -f1); test "${n:-0}" -ge 100' 600 false
rm -rf "$E/T9"; touch "$AGENT_WORK/flag"
out=$("$BIN/agent-verify" --recheck); rc=$?
is 'recheck: a lasting red exits 1' $rc 1
is 'red→green: ok, rc 0, run in the recorded cwd' "$(jq -r '"\(.ok) \(.rc)"' "$E/T1/check.json")" 'true 0'
is 'red→green: the red run kept in runs[]' "$(jq -r '[.runs[] | .ok] | join(",")' "$E/T1/check.json")" false
is 'red→red: rc 3, history appended' "$(jq -r '"\(.ok) \(.rc) \(.runs | length)"' "$E/T2/check.json")" 'false 3 2'
is 'red→red: ticket and check kept' "$(jq -r '"\(.ticket) \(.check)"' "$E/T2/check.json")" 'T2 exit 3'
[ ! -e "$AGENT_WORK/T3.ran" ] && ok 'red older than 7d is not re-run' || nok window 'T3 re-ran'
[ ! -e "$AGENT_WORK/T4.ran" ] && ok 'green is not re-run' || nok green 'T4 re-ran'
[ ! -e "$AGENT_WORK/suite.ran" ] && ok 'suite runner red is not re-run' || nok suite 'T5 re-ran the suite'
is 'suite runner red: superseded by fleet-ci, history untouched' "$(jq -r '"\(.superseded) \(.ok) \(.runs // [] | length)"' "$E/T5/check.json")" 'fleet-ci false 0'
[ -e "$AGENT_WORK/suite.ran.only" ] && ok 'run.sh --only red is re-run' || nok only 'T6 not re-run'
is 'one line per re-run' "$(grep -c '→' <<<"$out")" 5
is 'red quiet: verdict real' "$(jq -r .verdict "$E/T2/check.json")" real
is 'drift: verdict, file and line recorded' "$(jq -r '"\(.verdict) \(.drift.file | sub(".*/evidence/"; "")) \(.drift.line)"' "$E/T7/check.json")" 'drift T7/fresh-suite.txt FAIL 111/114 files in 73 s'
grep -q "verdict drift: '^\[0-9\]+/\[0-9\]+' vs line 1 of .*FAIL 111/114" <<<"$out" && ok 'drift: regex and line printed' || nok drift "$out"
is 'line 1 still matches: verdict real, not drift' "$(jq -r '"\(.verdict) \(.drift)"' "$E/T8/check.json")" 'real null'
is 'green: no verdict' "$(jq -r .verdict "$E/T1/check.json")" null
is 'one superseded line' "$(grep -c 'superseded' <<<"$out")" 1
out=$("$BIN/agent-verify" --recheck --since 30d)
is 'superseded is not written again' "$(grep -c 'superseded' <<<"$out")" 0
[ -e "$AGENT_WORK/T3.ran" ] && ok '--since 30d widens the window' || nok since 'T3 not re-run'
"$BIN/agent-verify" --recheck --since 2h >/dev/null
is 'the window counts from the first run, not the last' "$(jq '.runs | length' "$E/T2/check.json")" 3
L="$WORK/aw2/evidence"; mkdir -p "$L/T10"; echo '9.00 9.00 9.00 1/100 1' >"$QUIET_LOADAVG"
mkdir -p "$E/T10"; rec T10 'read -r l _ <"$QUIET_LOADAVG"; [ "${l%.*}" -lt 1 ] || { echo "0.10 0.10 0.10 1/100 1" >"$QUIET_LOADAVG"; exit 1; }' 600 false
mv "$E/T10/check.json" "$L/T10/" && rmdir "$E/T10"
AGENT_WORK="$WORK/aw2" "$BIN/agent-verify" --recheck >/dev/null; is 'red under load, green quiet: exits 0' $? 0
is 'load: green now, the loaded red tagged in runs[]' "$(jq -r '"\(.ok) \(.verdict) \([.runs[] | .verdict] | join(","))"' "$L/T10/check.json")" 'true null ,load'
export TMPDIR="$WORK/tmp"; mkdir -p "$TMPDIR"
printf '# T11\nCHECK: d=$(mktemp -d); touch "$d/x"; echo "$TMPDIR" >"$AGENT_WORK/T11.tmpdir"; sleep 30\n' >"$WORK/T11-x.md"
"$BIN/agent-verify" --timeout 2 "$WORK/T11-x.md" >/dev/null
case "$(cat "$AGENT_WORK/T11.tmpdir")" in "$TMPDIR"/agent-verify.*) ok 'tmp: the CHECK gets a private TMPDIR';; *) nok tmp "$(cat "$AGENT_WORK/T11.tmpdir")";; esac
is 'tmp: a CHECK killed by the timeout leaves 0 dirs' "$(jq -r '"\(.rc) \(.tmp_left)"' "$E/T11/check.json") $(ls -A "$TMPDIR" | wc -l)" '124 0 0'
is 'tmp: a finished CHECK records tmp_left 0' "$(jq -r .tmp_left "$E/T1/check.json")" 0
unset TMPDIR
"$BIN/agent-verify" --recheck --since 5x >/dev/null 2>&1; is 'bad --since exits non-zero' $? 1
B="$WORK/BACKLOG.md"
printf '# wave\n## 1. T12 first\nCHECK: exit 3\n\n## 2. T13 second, after T12\n- why\nCHECK: `touch "$AGENT_WORK/T13.ran"`\n## 3. T14 no check\n' >"$B"
"$BIN/agent-verify" "$B" --ticket T13 >/dev/null; is 'section: the ticket'"'"'s own CHECK runs, not the first' "$? $(jq -r '"\(.ok) \(.section)"' "$E/T13/check.json")" '0 true ## 2. T13 second, after T12'
[ -e "$AGENT_WORK/T13.ran" ] && ok 'section: its command ran' || nok section 'T13 not run'
err=$("$BIN/agent-verify" "$B" --ticket T15 2>&1 >/dev/null); is 'section: missing section exits 2' $? 2
is 'section: missing section names the count' "$err" "agent-verify: $B has 2 CHECKs and no section for T15"
[ ! -e "$E/T15" ] && ok 'section: missing section writes no evidence' || nok section 'T15 evidence written'
err=$("$BIN/agent-verify" "$B" 2>&1 >/dev/null); is 'mis-key: several CHECKs, no T<nn> in the name, no --ticket exits 2' $? 2
is 'mis-key: names the count and the headings' "$err" "agent-verify: $B has 2 CHECKs; pass --ticket T<n> (headings: T12 T13 T14)"
[ ! -e "$E/BACKLOG" ] && ok 'mis-key: writes no evidence' || nok miskey 'evidence/BACKLOG written'
"$BIN/agent-verify" "$WORK/T9-x.md" --ticket T16 >/dev/null; is 'single CHECK: unchanged with --ticket, no section key' "$? $(jq -r '"\(.ok) \(has("section"))"' "$E/T16/check.json")" '0 true false'
mkdir -p "$WORK/sbin"; printf '#!/bin/sh\nexit 0\n' >"$WORK/sbin/t17-sbin-tool"; chmod +x "$WORK/sbin/t17-sbin-tool"
printf '# T17\nCHECK: t17-sbin-tool\n' >"$WORK/T17-x.md"
PATH=/usr/bin:/bin AGENT_VERIFY_SBIN="$WORK/sbin" "$BIN/agent-verify" "$WORK/T17-x.md" >/dev/null; is 'sbin: a CHECK finds a tool in an sbin dir missing from PATH' $? 0
printf '# T18\nCHECK: case ":$PATH:" in *:/usr/sbin:/sbin:*) exit 0;; esac; exit 1\n' >"$WORK/T18-x.md"
PATH=/usr/bin:/bin "$BIN/agent-verify" "$WORK/T18-x.md" >/dev/null; is 'sbin: /usr/sbin and /sbin appended by default' $? 0
printf '# T19\nCHECK: test "$PATH" = "/usr/sbin:/usr/bin:/bin:/usr/local/sbin:/sbin"\n' >"$WORK/T19-x.md"
PATH=/usr/sbin:/usr/bin:/bin "$BIN/agent-verify" "$WORK/T19-x.md" >/dev/null; is 'sbin: a dir already on PATH is not added twice' $? 0
ST="$WORK/stub"; mkdir -p "$ST" "$WORK/foreign"; export WM_LOG="$WORK/wm.log" WM_PIDS="$WORK/wm.pids"; : >"$WM_PIDS"
printf '#!/bin/bash\ncase " $* " in *" shutdown-server "*) echo "shutdown ${TMPDIR-}" >>"$WM_LOG"; exit 0;; esac\necho "$$ ${TMPDIR-}" >>"$WM_PIDS"; cd /; while :; do sleep 0.2; done\n' >"$ST/watchman"; chmod +x "$ST/watchman"
w='setsid watchman </dev/null >/dev/null 2>&1 &'
printf '# T20\nCHECK: %s TMPDIR=%s %s env -u TMPDIR %s for _ in $(seq 50); do [ "$(wc -l <"$WM_PIDS")" -ge 3 ] \&\& break; sleep 0.1; done\n' "$w" "$WORK/foreign" "$w" "$w" >"$WORK/T20-x.md"
PATH="$ST:$PATH" "$BIN/agent-verify" "$WORK/T20-x.md" >/dev/null; is 'watchman: the CHECK started 3 stub daemons' "$? $(wc -l <"$WM_PIDS")" '0 3'
alive() { local p; p=$(awk -v t="$1" '$2 == t {print $1}' "$WM_PIDS"); [ -n "$p" ] && [ -d "/proc/$p" ] && ! grep -q '^State:.*Z' "/proc/$p/status" 2>/dev/null; }
own=$(awk '$2 ~ /agent-verify\./ {print $2}' "$WM_PIDS")
[ -n "$own" ] && ! alive "$own" && ok 'watchman: the daemon on the private TMPDIR is stopped' || nok watchman "own $own still running"
grep -qxF "shutdown $own" "$WM_LOG" 2>/dev/null && ok 'watchman: shutdown-server asked on the private TMPDIR' || nok shutdown "$(cat "$WM_LOG" 2>&1)"
alive "$WORK/foreign" && ok 'watchman: a foreign TMPDIR daemon is kept' || nok foreign 'stopped'
alive '' && ok 'watchman: the default daemon is kept' || nok default 'stopped'
"$BIN/agent-verify" >/dev/null 2>&1; is 'no brief and no --recheck exits 2' $? 2
"$BIN/agent-verify" --help | grep -q -- --recheck && ok '--help names --recheck' || nok help 'no --recheck'
exit $bad
