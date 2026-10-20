#!/usr/bin/env bash
# live-sudo: the PC_DOCTOR_LIVE rows read the real machine
# PT15: `pc doctor` is night-safe (no window, no pixel, no probe left running) and its rows are
# machine-readable; `pc bench` measures what it is asked for. Nothing here mutates the machine.
# Every row is judged on fixtures; PC_DOCTOR_LIVE=1 adds the live window/screenshot/sink and
# `pc bench` checks, which read the real desktop (T444).
set -uo pipefail
BIN="$HOME/agents/bin"; PC="$BIN/pc"
. "$HOME/agents/bin/tests/lib/assert.sh"
yes() { [ -n "$2" ] && [ "$2" != false ] && ok "$1" || nok "$1" "$2"; }

# Rows that are known-open findings, not regressions of this ticket. Anything appearing here is
# a real break. PT13's `systemctl restart -- dark-eye` entry (recorded at system scope for a user
# unit, so it verified false) is now `pc undo ack`ed and no longer needs an exception here.
KNOWN=''
LIVE=${PC_DOCTOR_LIVE:-0}
# Over 0.5 load per CPU a wall-clock budget measures the machine, not the doctor (T432 rule).
unjudged() { local l; read -r l _ </proc/loadavg; [ $((10#${l/./} * 2)) -gt $(($(nproc) * 100)) ] && echo ", unjudged at load $l"; }
# An over-budget row is a loaded machine; budgets are judged on controlled stubs in section 7.
NOBUDGET='map(select(.status=="FAIL" and (.detail|test("over budget")|not)))'
# ge <name> <text> <ERE with one ([0-9]+) group> <min> — the text matches and the number is >= min.
ge() { [[ $2 =~ $3 ]] && [ "${BASH_REMATCH[1]}" -ge "$4" ] && ok "$1" || nok "$1" "$2"; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
SHOTS="$HOME/Pictures/Screenshots"

# --- fixture: every doctor run below is a copied doctor on a fixture BIN, HOME, runtime dir and
# /proc, with stub system tools on PATH, so the real machine's health never decides a row.
FB="$WORK/bin"; DS="$WORK/stubs"; FR="$WORK/run"
mkdir -p "$FB" "$DS" "$WORK/home" "$FR/pc-status" "$WORK/state" "$WORK/proc-none"
cp /proc/stat "$WORK/proc-none/stat"; : >"$FR/bus"; : >"$FR/wayland-0"; : >"$FR/ydotool"
# Copied as `doctor`, not pc-doctor, so the usage sweep times only the fixture's pc-slow.
# The residue row reads /proc/bus/input/devices outside $PC_PROC; the copy reads the fixture /proc.
sed 's#/proc/bus/input/devices#$PC_PROC/bus/input/devices#' "$BIN/pc-doctor" >"$FB/doctor"; cp "$BIN/pclib.sh" "$BIN/env.sh" "$FB/"
for l in 0.50 1.10 6.00; do echo "$l $l $l 1/100 1" >"$WORK/loadavg-$l"; done
cat >"$FB/pc-slow" <<'EOF2'
#!/bin/sh
c=0; [ -f "$FAKE_STATE/slow" ] && read -r c <"$FAKE_STATE/slow"; echo $((c + 1)) >"$FAKE_STATE/slow"
case $FAKE_SLOW:$c in always:*|once:0|serial:0|serial:2) sleep 0.15;; esac
exit 0
EOF2
cat >"$FB/pc" <<'EOF2'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  'mode status')
    c=$(cat "$FAKE_STATE/mode" 2>/dev/null || echo 0); echo $((c + 1)) >"$FAKE_STATE/mode"
    case $FAKE_MODE:$c in always:*|once:0) sleep 0.6;; esac
    echo agent;;
  'status --check') echo 'PASS fixture';;
  'mutter extensions') echo '[{"uuid":"window-calls@fixture","state":"ACTIVE"}]';;
  'trace wakeups') echo '[{"pid":1}]';;
  'undo list') [ "${FAKE_UNDO:-}" = slow ] && sleep 1.2; echo '{}';;
  *) echo '{}';;
esac
EOF2
printf '#!/bin/sh\necho "0 claims"\n' >"$FB/claims"
printf '#!/bin/sh\necho "1 pc row"\n' >"$FB/agents-log"
cat >"$DS/systemctl" <<'EOF2'
#!/usr/bin/env bash
case " $* " in *' start '*|*' stop '*|*' restart '*|*' reset-failed '*|*' enable '*|*' disable '*) echo "stub refuses: $*" >>"$FAKE_STATE/refused"; exit 99;; esac
case " $* " in *' is-active '*) echo active;; *' list-timers '*) echo '[]';; esac
EOF2
cat >"$DS/sudo" <<'EOF2'
#!/usr/bin/env bash
[ "$1" = -n ] && shift
echo "$*" >>"$FAKE_STATE/sudo-calls"
case "$1" in true) exit 0;; ls) exec "$@";; *) echo "stub refuses: sudo $*" >>"$FAKE_STATE/refused"; exit 99;; esac
EOF2
cat >"$DS/busctl" <<'EOF2'
#!/usr/bin/env bash
case " $* " in *' Ping'*) ;; *' GetAddress'*) echo 's "unix:path=/fixture/a11y"';; *' Powered'*) echo 'b true';; *) exit 1;; esac
EOF2
printf '#!/bin/sh\nexit 1\n' >"$DS/pgrep"
printf '#!/bin/sh\nexit 0\n' >"$DS/pactl"
printf '#!/bin/sh\nexit 0\n' >"$DS/journalctl"
printf '#!/bin/sh\nexit 0\n' >"$DS/bpftrace"
printf '#!/bin/sh\nexit 0\n' >"$DS/perf"
printf '#!/bin/sh\necho "[{\\"id\\":0}]"\n' >"$DS/pw-dump"
printf '#!/bin/sh\necho "{\\"BackendState\\":\\"Running\\"}"\n' >"$DS/tailscale"
printf '#!/bin/sh\ncase "$1" in info) echo 27.0;; esac\n' >"$DS/docker"
printf '#!/bin/sh\n[ "$*" = "-c import bcc" ] && exit 0\nexec %s "$@"\n' "$(command -v python3)" >"$DS/python3"
chmod +x "$FB"/* "$DS"/*
# fdoc <doctor args…> — the fixture doctor; LEDGER=, FPROC=, FLOAD=, SLOW= and MODE= override the ledger, /proc,
# load, the fake pc-slow and the fake `pc mode status` (never|once|always; pc-slow also serial: runs 1 and 3).
fdoc() {
  HOME="$WORK/home" XDG_RUNTIME_DIR="$FR" WAYLAND_DISPLAY=wayland-0 YDOTOOL_SOCKET="$FR/ydotool" HARNESS_CONFIG=/dev/null \
    PC_LEDGER="${LEDGER:-$WORK/none.jsonl}" PC_PROC="${FPROC:-$WORK/proc-none}" PC_ALERT_SPOOL="$WORK/spool-none" \
    PC_ALERT_LOG="$WORK/alert-none.log" AGENT_WORK="$WORK/aw-none" FAKE_STATE="$WORK/state" FAKE_SLOW="${SLOW:-never}" \
    FAKE_MODE="${MODE:-never}" PC_NPROC=4 PC_LOADAVG="$WORK/loadavg-${FLOAD:-6.00}" PATH="$DS:$PATH" "$FB/doctor" "$@"
}
# A doctor run costs ~0.5 CPU s, so each run below sets several independent knobs (/proc, ledger, load,
# slow stubs) and every assert reads only the row its own knob drives.
# drun <name> [doctor args…] — a serial (PC_DOCTOR_JOBS=1, less CPU) --quick --json run into $WORK/<name>.json.
drun() { local n=$1; shift; rm -f "$WORK/state/slow" "$WORK/state/mode"; PC_DOCTOR_JOBS=1 fdoc --quick --json "$@" >"$WORK/$n.json" 2>/dev/null; }
# row <name|file> <row> — `<status>\t<detail>` of one row; st/dt split it without another jq.
row() { local f=$1; [[ $f == /* ]] || f=$WORK/$1.json; jq -r --arg n "$2" '.[]|select(.name==$n)|"\(.status)\t\(.detail)"' "$f"; }
st() { printf '%s' "${1%%$'\t'*}"; }
dt() { printf '%s' "${1#*$'\t'}"; }

# --- before (live only) -------------------------------------------------------
if [ "$LIVE" = 1 ]; then
  before_win=$("$PC" win list 2>/dev/null | md5sum)
  before_shots=$(ls "$SHOTS" 2>/dev/null | wc -l)
  before_null=$(pactl list modules short 2>/dev/null | grep -c module-null-sink)
fi

# --- 1. --quick --json is a valid, budgeted report ---------------------------
t0=$EPOCHREALTIME
fdoc --quick --json >"$WORK/q.json" 2>"$WORK/q.err"; rc=$?
ms=$(( (10#${EPOCHREALTIME/./} - 10#${t0/./}) / 1000 ))
is 'stub selftest: the fixture doctor asked no stub to mutate' "$(cat "$WORK/state/refused" 2>/dev/null | wc -l)" 0
is 'stub selftest: sudo stub refuses anything but true/ls' "$(FAKE_STATE="$WORK/state" "$DS/sudo" -n reboot; echo $?)" 99
rm -f "$WORK/state/"*
yes '--quick --json parses' "$(jq -e 'type=="array" and length>5' "$WORK/q.json" 2>/dev/null)"
yes '--quick --json rows have status/name/detail/ms' \
  "$(jq -e 'all(.[]; (.status|test("^(OK|WARN|FAIL|SKIP)$")) and (.name|length>0) and (.ms|type=="number"))' "$WORK/q.json" 2>/dev/null)"
u=$(unjudged); [ "$ms" -le 2500 ] || [ -n "$u" ] && ok "--quick ran in ${ms}ms (budget 2000 + slack$u)" \
  || nok '--quick budget' "${ms}ms"
is '--quick exits 0 or 1, never a crash' "$([ $rc -le 1 ] && echo yes)" yes
is '--quick writes nothing to stderr' "$(wc -c <"$WORK/q.err")" 0

fails=$(jq -r "$NOBUDGET|.[].name" "$WORK/q.json" 2>/dev/null | tr '\n' ' ')
unexpected=""
for f in $fails; do case " $KNOWN " in *" $f "*) ;; *) unexpected="$unexpected $f";; esac; done
[ -z "$unexpected" ] && ok "no FAIL row outside the known-open list (${fails:-none})" \
  || nok 'unexpected FAIL rows' "$unexpected"

# --- 2. the full run stays inside its budget and covers the subcommands ------
# `pc undo list` sleeps 1.2 s against its 1000 ms base: at load 6.00/4 cpu its sub: row is a WARN (section 7b).
t0=$EPOCHREALTIME
FAKE_UNDO=slow fdoc --json >"$WORK/full.json" 2>/dev/null; rc=$?
ms=$(( (10#${EPOCHREALTIME/./} - 10#${t0/./}) / 1000 ))
u=$(unjudged); [ "$ms" -le 10000 ] || [ -n "$u" ] && ok "full run in ${ms}ms (budget 10 s$u)" || nok 'full budget' "${ms}ms"
yes 'the full run sweeps the read-only subcommands' \
  "$(jq -e '[.[]|select(.name|startswith("sub:"))]|length>10' "$WORK/full.json" 2>/dev/null)"
yes 'the full run audits the ledger and the residue' \
  "$(jq -e '[.[].name]|(index("ledger")!=null) and (index("residue")!=null)' "$WORK/full.json" 2>/dev/null)"
yes 'doctor never sweeps a mutating verb' \
  "$(jq -e '[.[].name]|all(test("apply|shot|find|click|type|key|open|notify|selftest|speak")|not)' "$WORK/full.json" 2>/dev/null)"

# --- 3. it opened no window, took no screenshot, left no probe --------------
if [ "$LIVE" = 1 ]; then
  is 'the window list is unchanged' "$("$PC" win list 2>/dev/null | md5sum)" "$before_win"
  is 'no new file in Pictures/Screenshots' "$(ls "$SHOTS" 2>/dev/null | wc -l)" "$before_shots"
  is 'no null sink was loaded' "$(pactl list modules short 2>/dev/null | grep -c module-null-sink)" "$before_null"
fi
left=""
for p in bpftrace busctl perf evtest; do
  for pid in $(pgrep -x "$p"); do   # only processes started under this test's fixture HOME
    grep -qzx "HOME=$WORK/home" "/proc/$pid/environ" 2>/dev/null && left="$left $p"
  done
done
is 'no probe process survived doctor' "$left" ''

# --- 4. pc bench (live only: it times the real verbs) -----------------------
if [ "$LIVE" = 1 ]; then
  "$PC" bench --only status win --runs 1 >"$WORK/b.txt" 2>/dev/null
  is 'bench --only prints one row per command' "$(wc -l <"$WORK/b.txt")" 2
  yes 'a bench row carries wall/cold/CPU/execs' \
    "$(grep -cE '^status +[0-9]+\.[0-9]+ s +[0-9]+\.[0-9]+ s +[0-9]+\.[0-9]+ s +[0-9]+ +pc status$' "$WORK/b.txt")"
  yes 'bench --json is an array of measurements' \
    "$("$PC" bench --only undo --runs 1 --json 2>/dev/null | jq -e '.[0]|has("wall_warm_ms") and has("wall_cold_ms") and has("cpu_ms") and has("execs")')"
  "$PC" bench --only status --save >/dev/null 2>&1
  is 'bench --save refuses a partial sweep' "$?" 2
  yes 'the saved baseline still holds the per-ticket notes' \
    "$(grep -c '^## Per-ticket notes' "$BIN/tests/BASELINE-PCTOOLS.md")"
  yes 'the saved baseline holds a bench table between its markers' \
    "$(awk '/pc-bench:begin/{r=1} /pc-bench:end/{r=0} r && /^\| 20/{n++} END{print (n>10)}' "$BIN/tests/BASELINE-PCTOOLS.md")"
fi

# --- fixtures for sections 5-7: ledgers and fake /proc trees -----------------
# Ledgers (5, 5b).
FLED="$WORK/ledger-acked.jsonl"
cat >"$FLED" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakeacked1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":""}
{"id":"fakeacked1","verified":false,"observed":"a"}
{"ts":"2026-01-02T00:00:00+0000","id":"fakeacked1","ack":true,"why":"known non-issue","session":"s1"}
EOF
FLED2="$WORK/ledger-mixed.jsonl"
cat >"$FLED2" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakeacked1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":""}
{"id":"fakeacked1","verified":false,"observed":"a"}
{"ts":"2026-01-02T00:00:00+0000","id":"fakeacked1","ack":true,"why":"known non-issue","session":"s1"}
{"ts":"2026-01-01T00:00:00+0000","id":"fakeunackd1","session":"s1","cmd":"bar","target":"t2","before":"x","after":"y","rollback":"r2","read":""}
{"id":"fakeunackd1","verified":false,"observed":"x"}
EOF
FLED3="$WORK/ledger-late.jsonl"
cat >"$FLED3" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakelate1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":"echo b"}
{"id":"fakelate1","verified":false,"observed":"a"}
EOF
FLED4="$WORK/ledger-stale.jsonl"
cat >"$FLED4" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakestill1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":"echo a"}
{"id":"fakestill1","verified":false,"observed":"a"}
{"ts":"2026-01-01T00:00:00+0000","id":"fakenoread1","session":"s1","cmd":"bar","target":"t2","before":"x","after":"y","rollback":"r2","read":""}
{"id":"fakenoread1","verified":false,"observed":"x"}
EOF

# Fake /proc trees (6, 6b): the browsers row reads only playwright/Chrome cmdlines and the residue row only
# probe comms and uinput, so one tree carries a browsers case (pids 4xxx) and a residue case (pids 5xxx).
# No real pid is read and none is ever signalled.
fake_proc() {   # [PARENT=<ppid>] fake_proc <dir> <age-seconds> <pages> <cmdline-words…>
  local d=$1 age=$2 pages=$3; shift 3
  local start
  start=$(( ( $(printf '%(%s)T' -1) - age - BTIME ) * CLK ))
  mkdir -p "$d"
  printf '%s\0' "$@" >"$d/cmdline"
  printf '%s (fake) S %s 1 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 %s\n' "${d##*/}" "${PARENT:-1}" "$start" "$pages" >"$d/stat"
  printf '%s %s 100 10 0 500 0\n' "$((pages * 2))" "$pages" >"$d/statm"
}
# fproc <dir> <pid> <ppid> <comm> <cmdline-words…> — a fake process with comm and cgroup.
fproc() { local d=$1/$2 p=$3 c=$4; shift 4; PARENT=$p fake_proc "$d" 60 1000 "$@"; echo "$c" >"$d/comm"; echo '0::/user.slice/app.slice/fixture.scope' >"$d/cgroup"; }
cp /proc/stat "$WORK/stat.src"; CLK=$(getconf CLK_TCK); BTIME=$(awk '$1=="btime"{print $2}' /proc/stat)
fresh() { mkdir -p "$1"; cp "$WORK/stat.src" "$1/stat"; }
uinput() { mkdir -p "$1/bus/input"; echo 'N: Name="pc-input-virtual"' >"$1/bus/input/devices"; }

FP="$WORK/proc-old"; fresh "$FP"   # an old browser tree + residue under live tests
fake_proc "$FP/4001" $((3 * 86400)) 384000 node /opt/playwright-mcp/cli.js --headless
fake_proc "$FP/4002" $((3 * 86400)) 128000 /opt/chromium/headless_shell --headless=new
uinput "$FP"
fproc "$FP" 5001 1 bash bash "$HOME/agents/bin/tests/pc-input.test.sh"
fproc "$FP" 5002 5001 python3 python3 "$HOME/agents/bin/pc_input.py" inject
mkdir -p "$FP/5002/fd"; ln -s /dev/uinput "$FP/5002/fd/3"
fproc "$FP" 5003 1 bash bash "$HOME/agents/bin/tests/pc-trace.test.sh"
fproc "$FP" 5004 5003 bpftrace bpftrace -e 'tracepoint:x {}'
FY="$WORK/proc-young"; fresh "$FY"   # a young small tree + a probe in a run-*.scope
fake_proc "$FY/4003" 300 12800 node /opt/playwright-mcp/cli.js
fake_proc "$FY/4004" 300 40000 /usr/lib/firefox/firefox
fproc "$FY" 5101 1 perf perf record -a; echo '0::/user.slice/app.slice/run-u42.scope' >"$FY/5101/cgroup"
F1="$WORK/proc-live"; fresh "$F1"   # TSP-032: young Chrome under a live server + orphan residue
fake_proc "$F1/4101" $((9 * 86400)) 25600 node /opt/playwright-mcp/cli.js --headless
PARENT=4101 fake_proc "$F1/4102" 263 1000 sh -c launcher
PARENT=4102 fake_proc "$F1/4103" 263 25600 /opt/chromium/headless_shell --headless=new
PARENT=4103 fake_proc "$F1/4104" 200 25600 /opt/chromium/headless_shell --type=renderer
uinput "$F1"
fproc "$F1" 5201 1 python3 python3 "$HOME/agents/bin/pc_input.py" inject
mkdir -p "$F1/5201/fd"; ln -s /dev/uinput "$F1/5201/fd/3"
fproc "$F1" 5202 1 bpftrace bpftrace -e 'tracepoint:x {}'
F2="$WORK/proc-orphan"; fresh "$F2"   # an orphan Chrome + an orphan probe beside a live test
fake_proc "$F2/4201" 300 25600 /opt/chromium/headless_shell --headless=new
PARENT=4201 fake_proc "$F2/4202" 300 25600 /opt/chromium/headless_shell --type=renderer
fproc "$F2" 5301 1 bash bash "$HOME/agents/bin/tests/pc-trace.test.sh"
fproc "$F2" 5302 5301 bpftrace bpftrace -e x
fproc "$F2" 5303 1 evtest evtest /dev/input/event3
F3="$WORK/proc-server"; fresh "$F3"   # a 9-day server alone + the uinput selftest device
fake_proc "$F3/4301" $((9 * 86400)) 25600 node /opt/playwright-mcp/cli.js --headless
uinput "$F3"
F4="$WORK/proc-stale"; fresh "$F4"   # a 2-day Chrome under a live server
fake_proc "$F4/4401" $((9 * 86400)) 25600 node /opt/playwright-mcp/cli.js --headless
PARENT=4401 fake_proc "$F4/4402" $((2 * 86400)) 25600 /opt/chromium/headless_shell --headless=new

# The runs. Section 7's budgets: SLOW/MODE once|always slow the fake pc-slow (-h, 150 ms) and `pc mode status`
# (600 ms, base 500 ms); FLOAD sets load1 on 4 CPUs. Section 11: r1 and r2 run back to back on a cold sudo cache.
FPROC="$FP" drun w; wrc=$?
FPROC="$FP" PC_DOCTOR_JOBS=1 fdoc --quick --brief >"$WORK/w.brief" 2>/dev/null
FPROC="$FY" LEDGER="$FLED" FLOAD=0.50 SLOW=once MODE=once drun r-young
FPROC="$F1" LEDGER="$FLED2" FLOAD=0.50 SLOW=always MODE=always drun r-live
rm -f "$FR/pc-status/sudo-ok" "$FR/pc-status/alert-spool" "$WORK/state/sudo-calls"
FPROC="$F2" LEDGER="$FLED3" FLOAD=6.00 SLOW=always MODE=always drun r-orphan
FPROC="$F4" LEDGER="$FLED4" drun r-stale
sudo_true=$(grep -c '^true' "$WORK/state/sudo-calls"); sudo_ls=$(grep -c '^ls ' "$WORK/state/sudo-calls")
FPROC="$F3" LEDGER="$FLED3" FLOAD=1.10 SLOW=serial MODE=always drun r-server
FAKE_UNDO=slow FLOAD=0.50 fdoc --json >"$WORK/idle-full.json" 2>/dev/null

is 'fixture selftest: residue reads the fixture /proc input devices' "$(st "$(row r-server residue)")" FAIL

# --- 5. the ledger check exempts an acked unverified entry -------------------
r=$(row r-young ledger)
is 'acked-only ledger reports OK' "$(st "$r")" OK
case "$(dt "$r")" in *'unverified, acked'*) ok 'acked-only ledger row says acked';; *) nok 'acked-only ledger row says acked' "$r";; esac
r=$(row r-live ledger)
is 'an unacked unverified entry still fails' "$(st "$r")" FAIL
case "$(dt "$r")" in *fakeunackd1*) ok 'the FAIL row names the unacked id';; *) nok 'the FAIL row names the unacked id' "$r";; esac

# --- 5b. an unverified row whose stored read is true now is verified late (TSP-034) ----
r=$(row r-orphan ledger)
is 'a row true live now is OK without an ack' "$(st "$r")" OK
is 'the detail names it verified late' "$(dt "$r")" '1 changes · 0 unverified (1 verified late: fakelate1) · 0 without rollback'
is 'one late-verify row is appended' "$(jq -c 'select(.late)' "$FLED3")" '{"id":"fakelate1","verified":true,"observed":"b","late":true}'
is 'the next run appends nothing' "$(wc -l <"$FLED3")" 3
r=$(row r-stale ledger)
is 'a row still false live, or with no read, still fails' "$(st "$r")" FAIL
case "$(dt "$r")" in *'2 unverified (fakestill1,fakenoread1)'*) ok 'the failing ledger row names both ids';; *) nok 'the failing ledger row names both ids' "$r";; esac
is 'a false re-read appends nothing' "$(wc -l <"$FLED4")" 4

# --- 6. the browsers row: a fixture /proc, never a real process ---------------
# TSP-020: a playwright-mcp / headless-chrome tree that outlived its task.
r=$(row w browsers)
is 'an old browser tree is a WARN row' "$(st "$r")" WARN
case "$(dt "$r")" in
  *'playwright-mcp 3.0 d 1500 MB'*) ok 'the WARN detail carries age and RSS';;
  *) nok 'the WARN detail carries age and RSS' "$r";;
esac
case "$(dt "$r")" in
  *chrome-headless*) ok 'headless chrome is counted apart from the MCP server';;
  *) nok 'headless chrome is counted apart from the MCP server' "$r";;
esac
r=$(row r-young browsers)
is 'a young, small tree is OK' "$(st "$r")" OK
case "$(dt "$r")" in
  *firefox*) nok 'a visible browser is not browser residue' "$r";;
  *'playwright-mcp 0.0 d 50 MB'*) ok 'a visible browser is not browser residue';;
  *) nok 'a visible browser is not browser residue' "$r";;
esac
r=$(row "$WORK/q.json" browsers)   # section 1 ran on an empty fixture /proc
is 'no tree at all is OK' "$(st "$r")" OK
case "$(dt "$r")" in
  'no playwright-mcp or headless chrome tree') ok 'the empty row says so';;
  *) nok 'the empty row says so' "$r";;
esac
is 'a WARN row never fails the run' "$wrc:$(jq -c "$NOBUDGET" "$WORK/w.json")" "$( [ $wrc = 0 ] && echo 0 || echo 1):[]"

# T347: --brief keeps only the rows that are not OK, then the PASS/FAIL line.
brief=$(<"$WORK/w.brief")
is '--brief prints no OK row' "$(grep -c '^OK ' <<<"$brief")" 0
is '--brief keeps the WARN row' "$(grep -c '^WARN browsers ' <<<"$brief")" 1
yes '--brief ends with the PASS/FAIL line' "$(tail -1 <<<"$brief" | grep -E '^(PASS|FAIL) [0-9]+/[0-9]+ in ')"

# TSP-032: Chrome WARNs when orphaned or > 24 h; the server's own age is information only.
r=$(row r-live browsers)
is 'a young Chrome under a live 9-day server is OK' "$(st "$r")" OK
case "$(dt "$r")" in *'orphan 0'*) ok 'the live tree reports orphan 0';; *) nok 'the live tree reports orphan 0' "$r";; esac
r=$(row r-orphan browsers)
is 'an orphan Chrome is a WARN row' "$(st "$r")" WARN
case "$(dt "$r")" in *'orphan 1'*) ok 'the orphan tree counts one root';; *) nok 'the orphan tree counts one root' "$r";; esac
r=$(row r-server browsers)
is 'a 9-day server alone is OK' "$(st "$r")" OK
case "$(dt "$r")" in 'playwright-mcp 9.0 d 100 MB') ok 'the server row still shows age and RSS';; *) nok 'the server row still shows age and RSS' "$r";; esac
r=$(row r-stale browsers)
is 'a 2-day Chrome under a live server is a WARN row' "$(st "$r")" WARN
case "$(dt "$r")" in *'chrome-headless 2.0 d'*'orphan 0'*|*'orphan 0'*'chrome-headless 2.0 d'*) ok 'the stale row shows the Chrome age';; *) nok 'the stale row shows the Chrome age' "$r";; esac

# --- 6b. residue held by a live test is a WARN; an orphan stays FAIL (T489) ----
res() { local r; r=$(row "$1" residue); printf '%s' "${r/$'\t'/ }"; }
r=$(res w)
is 'residue under a live test is a WARN row' "${r%% *}" WARN
case $r in *'pc-input-virtual(pc-input.test.sh)'*'bpftrace(pc-trace.test.sh)'*|*'bpftrace(pc-trace.test.sh)'*'pc-input-virtual(pc-input.test.sh)'*) ok 'the WARN names the owning test';; *) nok 'the WARN names the owning test' "$r";; esac
is 'a probe in a run-*.scope is a WARN in use by that scope' "$(res r-young)" 'WARN in use by perf(run-u42.scope)'
is 'orphan: residue whose test is gone stays FAIL' "$(res r-live)" 'FAIL exit 1: no null sinks, no probes, no pt1x leftovers — RESIDUE: bpftrace pc-input-virtual'
r=$(res r-orphan)
is 'orphan beside a live test still FAILs' "${r%% *}" FAIL

# --- 7. budgeted rows judge the fastest of up to 3 runs (TSP-023) -------------
# The fixture BIN from the top (copied doctor + libs, a fake `pc`, a fake `pc-slow`): the real
# bin/ is not timed and no real verb runs.
is 'parallel-only slow probe is OK (the serial settle run is fast)' "$(st "$(row r-young usage)")" OK
r=$(row r-server usage)
is 'serially slow probe WARNs (a sweep sample and the settle run over 100 ms)' "$(st "$r")" WARN
ge 'the WARN detail carries max/min and load' "$(dt "$r")" 'load .*SLOW ONCE: pc-slow:([0-9]+)/[0-9]+ms' 150
r=$(row r-live usage)
is 'a -h slow every run is a FAIL usage row' "$(st "$r")" FAIL
ge 'the FAIL detail names the min' "$(dt "$r")" 'BAD: pc-slow:([0-9]+)ms' 150
is 'a fast fixture BIN is an OK usage row' "$(st "$(row idle-full usage)")" OK
r=$(row r-orphan usage)
is 'a -h slow every run at load 6.00/4 cpu is a WARN usage row' "$(st "$r")" WARN
ge 'the under-load WARN prints the load and the min' "$(dt "$r")" 'load 6\.00/4 cpu.*SLOW UNDER LOAD: pc-slow:([0-9]+)ms' 150
is 'a fast fixture BIN at load 6.00 is an OK usage row' "$(st "$(row full usage)")" OK
r=$(row r-young mode)
is 'a check slow once and fast after is OK' "$(st "$r")" OK
ge 'the retried row says best-of, first run and load' "$(dt "$r")" 'best of 2, first ([0-9]+)ms, load ' 600
r=$(row r-live mode)
is 'a check slow on all 3 runs is FAIL' "$(st "$r")" FAIL
case "$(dt "$r")" in *'over budget 500ms) (best of 3'*) ok 'the FAIL row says best of 3';; *) nok 'the FAIL row says best of 3' "$r";; esac

# --- 7b. budgets scale with load: clamp(load1/nproc × 4, 1, 8) as in tests/lib/budget.sh (T506) ---
r=$(row r-orphan mode)
is 'a check over its base but inside the load-scaled budget (6.00/4 cpu) is WARN' "$(st "$r")" WARN
case "$(dt "$r")" in *'slow under load (×6.0), base 500ms'*) ok 'the WARN row says slow under load and the factor';; *) nok 'the WARN row says slow under load and the factor' "$r";; esac
r=$(row r-server mode)
is 'a check over its load-scaled budget (1.10/4 cpu, ×1.1) is FAIL' "$(st "$r")" FAIL
case "$(dt "$r")" in *'over budget 550ms, base 500ms ×1.1'*) ok 'the FAIL row names the scaled budget';; *) nok 'the FAIL row names the scaled budget' "$r";; esac
r=$(row full sub:undo)
is 'a slow sub: probe inside the load-scaled budget is WARN' "$(st "$r")" WARN
case "$(dt "$r")" in 'slow under load (×6.0)'*) ok 'the sub: WARN row says slow under load';; *) nok 'the sub: WARN row says slow under load' "$r";; esac
r=$(row idle-full sub:undo)
is 'the same sub: probe on an idle box (×1) is FAIL' "$(st "$r")" FAIL
case "$(dt "$r")" in 'over budget 1000ms') ok 'the idle sub: FAIL row names the base budget';; *) nok 'the idle sub: FAIL row names the base budget' "$r";; esac

# --- 8-10. unit-loops, alert-spool, agent-work on stubbed systemd and fixture dirs, one run per state ----
# TSP-038: a timer re-firing a failing service; systemctl/journalctl stubs on PATH refuse any mutating
# verb, so the real manager is never touched. T347-01: netdata alarms stuck in the retry spool.
# T360: AGENT_WORK over its size cap.
SB="$WORK/sdstub"; mkdir -p "$SB"
cat >"$SB/systemctl" <<'EOF2'
#!/usr/bin/env bash
case " $* " in *' start '*|*' stop '*|*' restart '*|*' reset-failed '*) echo "stub refuses: $*" >>"$FAKE_STATE/refused"; exit 99;; esac
case " $* " in *' list-timers '*) cat "$FAKE_STATE/timers.json";; esac
EOF2
cat >"$SB/journalctl" <<'EOF2'
#!/usr/bin/env bash
case " $* " in
  *MESSAGE_ID=*) cat "$FAKE_STATE/fails.json";;
  *_SYSTEMD_USER_UNIT=*) echo 'Moodle upgrade pending, cron execution suspended.';;
esac
EOF2
chmod +x "$SB/systemctl" "$SB/journalctl"
mkdir -p "$WORK/aspool" "$WORK/aw"; printf '2026-09-05T22:31:24+02:00\tok\turgent\tprobe\n' >"$WORK/alert.log"
head -c 3145728 /dev/urandom >"$WORK/aw/big.bin"
sdrun() {   # sdrun <n fails of the timer service> <n fails of a Restart= service> <queued alerts> <agent-work cap MB> [<n fails of a foreign timer service>]
  mkdir -p "$WORK/state"; rm -f "$WORK/state/refused" "$WORK/aspool/"*
  echo '[{"next":1000060000000,"last":1000000000000,"unit":"fx-cron.timer","activates":"fx-cron.service"},{"unit":"fx-foreign-cron.timer","activates":"fx-foreign-cron.service"}]' >"$WORK/state/timers.json"
  { for _ in $(seq 1 "$1"); do echo '{"USER_UNIT":"fx-cron.service"}'; done
    for _ in $(seq 1 "${5:-0}"); do echo '{"USER_UNIT":"fx-foreign-cron.service"}'; done
    for _ in $(seq 1 "$2"); do echo '{"USER_UNIT":"restarty.service"}'; done; } >"$WORK/state/fails.json"
  for i in $(seq 1 "$3"); do echo 'x is critical' >"$WORK/aspool/1-$i"; done
  HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" HARNESS_CONFIG=/dev/null PC_LEDGER="$WORK/none.jsonl" PC_PROC="$WORK/proc-none" \
    PC_ALERT_SPOOL="$WORK/aspool" PC_ALERT_LOG="$WORK/alert.log" AGENT_WORK="$WORK/aw" PC_AGENT_WORK_MAX_MB="$4" \
    FAKE_STATE="$WORK/state" FAKE_MODE=never FAKE_SLOW=never PC_DOCTOR_JOBS=1 PATH="$SB:$DS:$PATH" PC_NOT_OURS='^fx-foreign' \
    "$FB/doctor" --quick --json >"$WORK/sd.json" 2>/dev/null
}
mkdir -p "$WORK/sdself"
FAKE_STATE="$WORK/sdself" "$SB/systemctl" --user reset-failed x >/dev/null 2>&1
is 'stub selftest: systemctl refuses reset-failed' "$(grep -c 'stub refuses' "$WORK/sdself/refused" 2>/dev/null)" 1
sdrun 10 0 1 1
r=$(row sd unit-loops)
is 'a timer service failing 10/h is a FAIL unit-loops row' "$(st "$r")" FAIL
case "$(dt "$r")" in *'fx-cron.service 10 fails/h: Moodle upgrade pending'*) ok 'the row names unit, count and last line';; *) nok 'the row names unit, count and last line' "$r";; esac
r=$(row sd alert-spool)
is 'a non-empty retry spool is a FAIL alert-spool row' "$(st "$r")" FAIL
case "$(dt "$r")" in *'1 queued'*'2026-09-05'*) ok 'the row names the count and the last ok push';; *) nok 'the row names the count and the last ok push' "$r";; esac
r=$(row sd agent-work)
is 'a 3 MB fixture over a 1 MB cap is a WARN agent-work row' "$(st "$r")" WARN
case "$(dt "$r")" in '3 MB'*'> 1 MB'*) ok 'the row names the size and the cap';; *) nok 'the row names the size and the cap' "$r";; esac
sdrun 2 20 0 100   # an OK row here also proves the 20/h Restart= service is not counted
is '2 fails/h is OK' "$(row sd unit-loops | cut -f1)" OK
is 'an empty retry spool is OK' "$(row sd alert-spool | cut -f1)" OK
is 'the same fixture under a 100 MB cap is OK' "$(row sd agent-work | cut -f1)" OK
is 'a non-timer unit failing 20/h is not this row' "$(row sd unit-loops | cut -f1)" OK
is 'the doctor never asked the stub to mutate' "$(cat "$WORK/state/refused" 2>/dev/null | wc -l)" 0
# T734: a timer loop of a unit matching PC_NOT_OURS is named on an OK row, never a FAIL.
sdrun 0 0 0 100 48
r=$(row sd unit-loops)
is 'only a foreign loop is an OK unit-loops row' "$(st "$r")" OK
case "$(dt "$r")" in *'not ours: fx-foreign-cron.service 48 fails/h') ok 'the OK row names the foreign unit';; *) nok 'the OK row names the foreign unit' "$r";; esac
sdrun 10 0 0 100 48
r=$(row sd unit-loops)
case "$(st "$r") $(dt "$r")" in FAIL*'fx-cron.service 10 fails/h'*) case "$r" in *fx-foreign*) nok 'a FAIL row names only our unit' "$r";; *) ok 'a FAIL row names only our unit';; esac;; *) nok 'a FAIL row names only our unit' "$r";; esac
is 'the foreign runs never asked the stub to mutate' "$(cat "$WORK/state/refused" 2>/dev/null | wc -l)" 0

# --- 11. sudo probes are cached (T473): two runs inside the TTL ask sudo once each -------------
r1=$(jq -c '[.[]|select(.name=="sudo" or .name=="alert-spool")|[.status,.detail]]' "$WORK/r-orphan.json")
r2=$(jq -c '[.[]|select(.name=="sudo" or .name=="alert-spool")|[.status,.detail]]' "$WORK/r-stale.json")
is 'two doctor runs ask `sudo -n true` once' "$sudo_true" 1
is 'two doctor runs list the root-only spool under sudo once' "$sudo_ls" 1
is 'the cached run reports the same sudo and alert-spool rows' "$r2" "$r1"
is 'the rows are OK with an empty spool' "$r1" '[["OK","sudo -n answers"],["OK","0 queued in spool-none, last ok push never"]]'

# --- 12. the fleet-ci row carries the nightly CPU s vs its 7-night median (T862) ------------------
# cinights <dir> <last-night cpu> <n nights before it> — steady 1000 CPU s nights, one log without a cpu
# line, and a last night whose first pass holds the full run (its .txt re-run says 50 s).
cinights() {
  local d=$1 i; rm -rf "$d"; mkdir -p "$d"
  for i in $(seq 1 "$3"); do printf 'cpu: %s s total, top 3: 1 x\nPASS 9/9 files in 9 s\n' $((995 + i * 2)) >"$d/2026-10-0$i.txt"; done
  printf 'PASS 9/9 files in 9 s\n' >"$d/2026-10-08.txt"
  printf 'cpu: %s s total, top 3: 1 x\nFAIL 8/9 files in 9 s\n' "$2" >"$d/2026-10-09.first.txt"
  printf 'cpu: 50.0 s total, top 3: 50.0 x\n  re-run | cpu: 9.0 s total\nPASS 9/9 files in 9 s\n' >"$d/2026-10-09.txt"
}
printf '2026-10-0%s\tbin/tests/%s.test.sh\t1\t0\t1\t%s\n' 1 steady 300 2 steady 310 9 steady 305 \
  1 claude-adapter-skills 1000 2 claude-adapter-skills 1100 3 claude-adapter-skills 1200 \
  9 claude-adapter-skills 4000 9 claude-adapter-skills 9000 9 new 999 3 nocpu '' >"$WORK/ci-hist.tsv"
cidrun() { PC_FLEET_CI_DIR="$WORK/ci" PC_TIMINGS_HISTORY="$WORK/ci-hist.tsv" drun "$@"; }
cinights "$WORK/ci" 1010 6; cidrun ci-steady
r=$(row ci-steady fleet-ci)
is 'steady nights are an OK fleet-ci row' "$(st "$r")" OK
case "$(dt "$r")" in '2026-10-09.txt: PASS 9/9 files in 9 s; cpu 1010.0 s (7-night median 1004.0)') ok 'the row carries the first pass cpu and the 7-night median';; *) nok 'the row carries the first pass cpu and the 7-night median' "$r";; esac
cinights "$WORK/ci" 1400 6; cidrun ci-grow
r=$(row ci-grow fleet-ci)
is 'a night at +40 % is a WARN fleet-ci row' "$(st "$r")" WARN
case "$(dt "$r")" in *'cpu 1400.0 s (7-night median 1004.0) +39%, top claude-adapter-skills 4000.0 vs 1100.0') ok 'the WARN names the top grower vs its own median';; *) nok 'the WARN names the top grower vs its own median' "$r";; esac
printf 'PASS 9/9 files in 9 s\n' >"$WORK/ci/2026-10-10.txt"; cidrun ci-run
case "$(dt "$(row ci-run fleet-ci)")" in '2026-10-10.txt: PASS 9/9; cpu 1400.0 s on 10-09 (7-night median 1005.0) +39%, top claude-adapter-skills 4000.0 vs 1100.0') ok 'a newest log without cpu names the night its cpu is from';; *) nok 'a newest log without cpu names the night its cpu is from' "$(row ci-run fleet-ci)";; esac
cinights "$WORK/ci" 1400 1; cidrun ci-two
is 'a jump with 2 nights of data is no WARN' "$(row ci-two fleet-ci | cut -f1)" OK

# --- 13. a green recheck heals the night: the verdict is the last summary or recheck line (T897) ----
recheck() { cinights "$WORK/ci" 1010 6; printf 'FAIL 8/9 files in 9 s\n✖ fleet ci red: a.test.sh\n' >>"$WORK/ci/2026-10-09.txt"; printf "$1" >>"$WORK/ci/2026-10-09.txt"; cidrun "$2"; }
recheck 'recheck 11:27:28: 1/1 green (a.test.sh)\n' rc-green
r=$(row rc-green fleet-ci)
is 'red + green recheck is an OK fleet-ci row' "$(st "$r")" OK
case "$(dt "$r")" in '2026-10-09.txt: healed by recheck 11:27:28 (1/1); cpu '*) ok 'the row says healed by recheck <time> (N/M)';; *) nok 'the row says healed by recheck <time> (N/M)' "$r";; esac
recheck 'recheck 10:55:32: 0/1 green (a.test.sh)\n' rc-red
r=$(row rc-red fleet-ci)
is 'red + 0/1 recheck stays a WARN' "$(st "$r")" WARN
case "$(dt "$r")" in '2026-10-09.txt: FAIL 8/9 files in 9 s;'*) ok 'a red recheck keeps the FAIL line';; *) nok 'a red recheck keeps the FAIL line' "$r";; esac
recheck 'recheck 10:55:32: 0/1 green (a.test.sh)\nrecheck 11:27:28: 1/1 green (a.test.sh)\n' rc-two
is 'two rechecks, the last green, heal' "$(row rc-two fleet-ci | cut -f1)" OK
recheck 'recheck 10:55:32: 1/1 green (a.test.sh)\nrecheck 11:27:28: 1/2 green (a.test.sh b.test.sh)\n' rc-last-red
is 'two rechecks, the last red, stay red' "$(row rc-last-red fleet-ci | cut -f1)" WARN
exit $bad
