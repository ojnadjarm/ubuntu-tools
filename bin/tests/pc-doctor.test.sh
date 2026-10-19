#!/usr/bin/env bash
# PT15: `pc doctor` is night-safe (no window, no pixel, no probe left running) and its rows are
# machine-readable; `pc bench` measures what it is asked for. Nothing here mutates the machine.
# Every row is judged on fixtures; PC_DOCTOR_LIVE=1 adds the live window/screenshot/sink and
# `pc bench` checks, which read the real desktop (T444).
set -uo pipefail
BIN="$HOME/agents/bin"; PC="$BIN/pc"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
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
for l in 0.50 6.00; do echo "$l $l $l 1/100 1" >"$WORK/loadavg-$l"; done
cat >"$FB/pc-slow" <<'EOF2'
#!/bin/sh
c=0; [ -f "$FAKE_STATE/slow" ] && read -r c <"$FAKE_STATE/slow"; echo $((c + 1)) >"$FAKE_STATE/slow"
case $FAKE_SLOW:$c in always:*|once:0) sleep 0.15;; esac
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
# fdoc <doctor args…> — the fixture doctor; LEDGER= and FPROC= override the ledger and /proc.
fdoc() {
  HOME="$WORK/home" XDG_RUNTIME_DIR="$FR" WAYLAND_DISPLAY=wayland-0 YDOTOOL_SOCKET="$FR/ydotool" HARNESS_CONFIG=/dev/null \
    PC_LEDGER="${LEDGER:-$WORK/none.jsonl}" PC_PROC="${FPROC:-$WORK/proc-none}" PC_ALERT_SPOOL="$WORK/spool-none" \
    PC_ALERT_LOG="$WORK/alert-none.log" AGENT_WORK="$WORK/aw-none" FAKE_STATE="$WORK/state" FAKE_SLOW=never FAKE_MODE=never \
    PC_NPROC=4 PC_LOADAVG="$WORK/loadavg-6.00" PATH="$DS:$PATH" "$FB/doctor" "$@"
}
fdoc --quick >/dev/null 2>&1
is 'stub selftest: the fixture doctor asked no stub to mutate' "$(cat "$WORK/state/refused" 2>/dev/null | wc -l)" 0
is 'stub selftest: sudo stub refuses anything but true/ls' "$(FAKE_STATE="$WORK/state" "$DS/sudo" -n reboot; echo $?)" 99
rm -f "$WORK/state/"*
FI="$WORK/proc-input"; mkdir -p "$FI/bus/input"; cp /proc/stat "$FI/stat"; echo 'N: Name="pc-input-virtual"' >"$FI/bus/input/devices"
is 'fixture selftest: residue reads the fixture /proc input devices' \
  "$(FPROC="$FI" fdoc --quick --json 2>/dev/null | jq -r '.[]|select(.name=="residue")|.status')" FAIL

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
t0=$EPOCHREALTIME
fdoc --json >"$WORK/full.json" 2>/dev/null; rc=$?
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

# --- 5. the ledger check exempts an acked unverified entry -------------------
FLED="$WORK/ledger-acked.jsonl"
cat >"$FLED" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakeacked1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":""}
{"id":"fakeacked1","verified":false,"observed":"a"}
{"ts":"2026-01-02T00:00:00+0000","id":"fakeacked1","ack":true,"why":"known non-issue","session":"s1"}
EOF
row=$(LEDGER="$FLED" fdoc --quick --json 2>/dev/null | jq -c '.[]|select(.name=="ledger")')
is 'acked-only ledger reports OK' "$(jq -r .status <<<"$row")" OK
case "$(jq -r .detail <<<"$row")" in *'unverified, acked'*) ok 'acked-only ledger row says acked';; *) nok 'acked-only ledger row says acked' "$row";; esac

FLED2="$WORK/ledger-mixed.jsonl"
cat >"$FLED2" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakeacked1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":""}
{"id":"fakeacked1","verified":false,"observed":"a"}
{"ts":"2026-01-02T00:00:00+0000","id":"fakeacked1","ack":true,"why":"known non-issue","session":"s1"}
{"ts":"2026-01-01T00:00:00+0000","id":"fakeunackd1","session":"s1","cmd":"bar","target":"t2","before":"x","after":"y","rollback":"r2","read":""}
{"id":"fakeunackd1","verified":false,"observed":"x"}
EOF
row=$(LEDGER="$FLED2" fdoc --quick --json 2>/dev/null | jq -c '.[]|select(.name=="ledger")')
is 'an unacked unverified entry still fails' "$(jq -r .status <<<"$row")" FAIL
case "$(jq -r .detail <<<"$row")" in *fakeunackd1*) ok 'the FAIL row names the unacked id';; *) nok 'the FAIL row names the unacked id' "$row";; esac

# --- 5b. an unverified row whose stored read is true now is verified late (TSP-034) ----
lrow() { LEDGER="$1" fdoc --quick --json 2>/dev/null | jq -c '.[]|select(.name=="ledger")'; }
FLED3="$WORK/ledger-late.jsonl"
cat >"$FLED3" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakelate1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":"echo b"}
{"id":"fakelate1","verified":false,"observed":"a"}
EOF
row=$(lrow "$FLED3")
is 'a row true live now is OK without an ack' "$(jq -r .status <<<"$row")" OK
is 'the detail names it verified late' "$(jq -r .detail <<<"$row")" '1 changes · 0 unverified (1 verified late: fakelate1) · 0 without rollback'
is 'one late-verify row is appended' "$(jq -c 'select(.late)' "$FLED3")" '{"id":"fakelate1","verified":true,"observed":"b","late":true}'
lrow "$FLED3" >/dev/null
is 'the next run appends nothing' "$(wc -l <"$FLED3")" 3

FLED4="$WORK/ledger-stale.jsonl"
cat >"$FLED4" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakestill1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":"echo a"}
{"id":"fakestill1","verified":false,"observed":"a"}
{"ts":"2026-01-01T00:00:00+0000","id":"fakenoread1","session":"s1","cmd":"bar","target":"t2","before":"x","after":"y","rollback":"r2","read":""}
{"id":"fakenoread1","verified":false,"observed":"x"}
EOF
row=$(lrow "$FLED4")
is 'a row still false live, or with no read, still fails' "$(jq -r .status <<<"$row")" FAIL
case "$(jq -r .detail <<<"$row")" in *'2 unverified (fakestill1,fakenoread1)'*) ok 'the failing ledger row names both ids';; *) nok 'the failing ledger row names both ids' "$row";; esac
is 'a false re-read appends nothing' "$(wc -l <"$FLED4")" 4

# --- 6. the browsers row: a fixture /proc, never a real process ---------------
# TSP-020: a playwright-mcp / headless-chrome tree that outlived its task. Each case builds
# two fake pids under mktemp; no real pid is read and none is ever signalled.
fake_proc() {   # [PARENT=<ppid>] fake_proc <dir> <age-seconds> <pages> <cmdline-words…>
  local d=$1 age=$2 pages=$3; shift 3
  local btime clk start
  clk=$(getconf CLK_TCK); btime=$(awk '$1=="btime"{print $2}' /proc/stat)
  start=$(( ( $(printf '%(%s)T' -1) - age - btime ) * clk ))
  mkdir -p "$d"
  printf '%s\0' "$@" >"$d/cmdline"
  printf '%s (fake) S %s 1 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 %s\n' "${d##*/}" "${PARENT:-1}" "$start" "$pages" >"$d/stat"
  printf '%s %s 100 10 0 500 0\n' "$((pages * 2))" "$pages" >"$d/statm"
}
brow() { FPROC="$1" fdoc --quick --json 2>/dev/null | jq -c '.[]|select(.name=="browsers")'; }

FP="$WORK/proc-old"; cp /proc/stat "$WORK/stat.src"
mkdir -p "$FP"; cp "$WORK/stat.src" "$FP/stat"
fake_proc "$FP/4001" $((3 * 86400)) 384000 node /opt/playwright-mcp/cli.js --headless
fake_proc "$FP/4002" $((3 * 86400)) 128000 /opt/chromium/headless_shell --headless=new
row=$(brow "$FP")
is 'an old browser tree is a WARN row' "$(jq -r .status <<<"$row")" WARN
case "$(jq -r .detail <<<"$row")" in
  *'playwright-mcp 3.0 d 1500 MB'*) ok 'the WARN detail carries age and RSS';;
  *) nok 'the WARN detail carries age and RSS' "$row";;
esac
case "$(jq -r .detail <<<"$row")" in
  *chrome-headless*) ok 'headless chrome is counted apart from the MCP server';;
  *) nok 'headless chrome is counted apart from the MCP server' "$row";;
esac

FY="$WORK/proc-young"; mkdir -p "$FY"; cp "$WORK/stat.src" "$FY/stat"
fake_proc "$FY/4003" 300 12800 node /opt/playwright-mcp/cli.js
fake_proc "$FY/4004" 300 40000 /usr/lib/firefox/firefox
row=$(brow "$FY")
is 'a young, small tree is OK' "$(jq -r .status <<<"$row")" OK
case "$(jq -r .detail <<<"$row")" in
  *firefox*) nok 'a visible browser is not browser residue' "$row";;
  *'playwright-mcp 0.0 d 50 MB'*) ok 'a visible browser is not browser residue';;
  *) nok 'a visible browser is not browser residue' "$row";;
esac

FE="$WORK/proc-empty"; mkdir -p "$FE"; cp "$WORK/stat.src" "$FE/stat"
row=$(brow "$FE")
is 'no tree at all is OK' "$(jq -r .status <<<"$row")" OK
case "$(jq -r .detail <<<"$row")" in
  'no playwright-mcp or headless chrome tree') ok 'the empty row says so';;
  *) nok 'the empty row says so' "$row";;
esac
FPROC="$FP" fdoc --quick --json >"$WORK/w.json" 2>/dev/null; rc=$?
is 'a WARN row never fails the run' "$rc:$(jq -c "$NOBUDGET" "$WORK/w.json")" "$( [ $rc = 0 ] && echo 0 || echo 1):[]"

# T347: --brief keeps only the rows that are not OK, then the PASS/FAIL line.
brief=$(FPROC="$FP" fdoc --quick --brief 2>/dev/null)
is '--brief prints no OK row' "$(grep -c '^OK ' <<<"$brief")" 0
is '--brief keeps the WARN row' "$(grep -c '^WARN browsers ' <<<"$brief")" 1
yes '--brief ends with the PASS/FAIL line' "$(tail -1 <<<"$brief" | grep -E '^(PASS|FAIL) [0-9]+/[0-9]+ in ')"

# TSP-032: Chrome WARNs when orphaned or > 24 h; the server's own age is information only.
fresh() { mkdir -p "$1"; cp "$WORK/stat.src" "$1/stat"; }
F1="$WORK/proc-live"; fresh "$F1"
fake_proc "$F1/4101" $((9 * 86400)) 25600 node /opt/playwright-mcp/cli.js --headless
PARENT=4101 fake_proc "$F1/4102" 263 1000 sh -c launcher
PARENT=4102 fake_proc "$F1/4103" 263 25600 /opt/chromium/headless_shell --headless=new
PARENT=4103 fake_proc "$F1/4104" 200 25600 /opt/chromium/headless_shell --type=renderer
row=$(brow "$F1")
is 'a young Chrome under a live 9-day server is OK' "$(jq -r .status <<<"$row")" OK
case "$(jq -r .detail <<<"$row")" in *'orphan 0'*) ok 'the live tree reports orphan 0';; *) nok 'the live tree reports orphan 0' "$row";; esac

F2="$WORK/proc-orphan"; fresh "$F2"
fake_proc "$F2/4201" 300 25600 /opt/chromium/headless_shell --headless=new
PARENT=4201 fake_proc "$F2/4202" 300 25600 /opt/chromium/headless_shell --type=renderer
row=$(brow "$F2")
is 'an orphan Chrome is a WARN row' "$(jq -r .status <<<"$row")" WARN
case "$(jq -r .detail <<<"$row")" in *'orphan 1'*) ok 'the orphan tree counts one root';; *) nok 'the orphan tree counts one root' "$row";; esac

F3="$WORK/proc-server"; fresh "$F3"
fake_proc "$F3/4301" $((9 * 86400)) 25600 node /opt/playwright-mcp/cli.js --headless
row=$(brow "$F3")
is 'a 9-day server alone is OK' "$(jq -r .status <<<"$row")" OK
case "$(jq -r .detail <<<"$row")" in 'playwright-mcp 9.0 d 100 MB') ok 'the server row still shows age and RSS';; *) nok 'the server row still shows age and RSS' "$row";; esac

F4="$WORK/proc-stale"; fresh "$F4"
fake_proc "$F4/4401" $((9 * 86400)) 25600 node /opt/playwright-mcp/cli.js --headless
PARENT=4401 fake_proc "$F4/4402" $((2 * 86400)) 25600 /opt/chromium/headless_shell --headless=new
row=$(brow "$F4")
is 'a 2-day Chrome under a live server is a WARN row' "$(jq -r .status <<<"$row")" WARN
case "$(jq -r .detail <<<"$row")" in *'chrome-headless 2.0 d'*'orphan 0'*|*'orphan 0'*'chrome-headless 2.0 d'*) ok 'the stale row shows the Chrome age';; *) nok 'the stale row shows the Chrome age' "$row";; esac

# --- 7. budgeted rows judge the fastest of up to 3 runs (TSP-023) -------------
# The fixture BIN from the top (copied doctor + libs, a fake `pc`, a fake `pc-slow`): the real
# bin/ is not timed and no real verb runs.
frow() {   # frow <row name> <slow pc-slow> <slow mode>; LOAD=0.50|6.00 on 4 CPUs
  rm -f "$WORK/state/"*
  HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" HARNESS_CONFIG=/dev/null PC_LEDGER="$WORK/none.jsonl" \
    FAKE_STATE="$WORK/state" FAKE_SLOW="$2" FAKE_MODE="$3" PC_NPROC=4 \
    PC_LOADAVG="$WORK/loadavg-${LOAD:-0.50}" PATH="$DS:$PATH" "$FB/doctor" --quick --json 2>/dev/null | jq -c --arg n "$1" '.[]|select(.name==$n)'
}
row=$(frow usage once never)
is 'a -h slow once is a WARN usage row, not FAIL' "$(jq -r .status <<<"$row")" WARN
ge 'the WARN detail carries max/min and load' "$(jq -r .detail <<<"$row")" 'load .*SLOW ONCE: pc-slow:([0-9]+)/[0-9]+ms' 150
row=$(frow usage always never)
is 'a -h slow every run is a FAIL usage row' "$(jq -r .status <<<"$row")" FAIL
ge 'the FAIL detail names the min' "$(jq -r .detail <<<"$row")" 'BAD: pc-slow:([0-9]+)ms' 150
row=$(frow usage never never)
is 'a fast fixture BIN is an OK usage row' "$(jq -r .status <<<"$row")" OK
row=$(LOAD=6.00 frow usage always never)
is 'a -h slow every run at load 6.00/4 cpu is a WARN usage row' "$(jq -r .status <<<"$row")" WARN
ge 'the under-load WARN prints the load and the min' "$(jq -r .detail <<<"$row")" 'load 6\.00/4 cpu.*SLOW UNDER LOAD: pc-slow:([0-9]+)ms' 150
row=$(LOAD=6.00 frow usage never never)
is 'a fast fixture BIN at load 6.00 is an OK usage row' "$(jq -r .status <<<"$row")" OK
row=$(frow mode never once)
is 'a check slow once and fast after is OK' "$(jq -r .status <<<"$row")" OK
ge 'the retried row says best-of, first run and load' "$(jq -r .detail <<<"$row")" 'best of 2, first ([0-9]+)ms, load ' 600
row=$(frow mode never always)
is 'a check slow on all 3 runs is FAIL' "$(jq -r .status <<<"$row")" FAIL
case "$(jq -r .detail <<<"$row")" in *'over budget 500ms) (best of 3'*) ok 'the FAIL row says best of 3';; *) nok 'the FAIL row says best of 3' "$row";; esac

# --- 8. unit-loops: a timer re-firing a failing service (TSP-038), stubbed systemd only -------
# systemctl/journalctl stubs on PATH refuse any mutating verb, so the real manager is never touched.
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
loops() {   # loops <n fails of the timer service> <n fails of a Restart= service>
  mkdir -p "$WORK/state"; rm -f "$WORK/state/refused"
  echo '[{"next":1000060000000,"last":1000000000000,"unit":"moodle45-cron.timer","activates":"moodle45-cron.service"}]' >"$WORK/state/timers.json"
  { for _ in $(seq 1 "$1"); do echo '{"USER_UNIT":"moodle45-cron.service"}'; done
    for _ in $(seq 1 "$2"); do echo '{"USER_UNIT":"restarty.service"}'; done; } >"$WORK/state/fails.json"
  HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" HARNESS_CONFIG=/dev/null PC_LEDGER="$WORK/none.jsonl" \
    FAKE_STATE="$WORK/state" FAKE_MODE=never FAKE_SLOW=never PATH="$SB:$DS:$PATH" \
    "$FB/doctor" --quick --json 2>/dev/null | jq -c '.[]|select(.name=="unit-loops")'
}
mkdir -p "$WORK/sdself"
FAKE_STATE="$WORK/sdself" "$SB/systemctl" --user reset-failed x >/dev/null 2>&1
is 'stub selftest: systemctl refuses reset-failed' "$(grep -c 'stub refuses' "$WORK/sdself/refused" 2>/dev/null)" 1
row=$(loops 10 0)
is 'a timer service failing 10/h is a FAIL unit-loops row' "$(jq -r .status <<<"$row")" FAIL
case "$(jq -r .detail <<<"$row")" in *'moodle45-cron.service 10 fails/h: Moodle upgrade pending'*) ok 'the row names unit, count and last line';; *) nok 'the row names unit, count and last line' "$row";; esac
is '2 fails/h is OK' "$(jq -r .status <<<"$(loops 2 0)")" OK
is 'a non-timer unit failing 20/h is not this row' "$(jq -r .status <<<"$(loops 0 20)")" OK
is 'the doctor never asked the stub to mutate' "$(cat "$WORK/state/refused" 2>/dev/null | wc -l)" 0

# --- 9. alert-spool: netdata alarms stuck in the retry spool (T347-01), fixture dirs only -----
spool() {
  HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" HARNESS_CONFIG=/dev/null PC_LEDGER="$WORK/none.jsonl" \
    PC_ALERT_SPOOL="$WORK/aspool" PC_ALERT_LOG="$WORK/alert.log" PATH="$SB:$DS:$PATH" FAKE_STATE="$WORK/state" \
    "$FB/doctor" --quick --json 2>/dev/null | jq -c '.[]|select(.name=="alert-spool")'
}
mkdir -p "$WORK/aspool"; printf '2026-09-05T22:31:24+02:00\tok\turgent\tprobe\n' >"$WORK/alert.log"
echo 'x is critical' >"$WORK/aspool/1-1"
row=$(spool)
is 'a non-empty retry spool is a FAIL alert-spool row' "$(jq -r .status <<<"$row")" FAIL
case "$(jq -r .detail <<<"$row")" in *'1 queued'*'2026-09-05'*) ok 'the row names the count and the last ok push';; *) nok 'the row names the count and the last ok push' "$row";; esac
rm -f "$WORK/aspool/1-1"
is 'an empty retry spool is OK' "$(jq -r .status <<<"$(spool)")" OK

# --- 10. agent-work: WARN over the size cap (T360), a fixture dir only -----------------------
aw() {
  HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" HARNESS_CONFIG=/dev/null PC_LEDGER="$WORK/none.jsonl" \
    AGENT_WORK="$WORK/aw" PC_AGENT_WORK_MAX_MB="$1" PATH="$SB:$DS:$PATH" FAKE_STATE="$WORK/state" \
    "$FB/doctor" --quick --json 2>/dev/null | jq -c '.[]|select(.name=="agent-work")'
}
mkdir -p "$WORK/aw"; head -c 3145728 /dev/urandom >"$WORK/aw/big.bin"
row=$(aw 1)
is 'a 3 MB fixture over a 1 MB cap is a WARN agent-work row' "$(jq -r .status <<<"$row")" WARN
case "$(jq -r .detail <<<"$row")" in '3 MB'*'> 1 MB'*) ok 'the row names the size and the cap';; *) nok 'the row names the size and the cap' "$row";; esac
is 'the same fixture under a 100 MB cap is OK' "$(jq -r .status <<<"$(aw 100)")" OK

[ $bad = 0 ] && echo 'PASS pc-doctor' || echo 'FAIL pc-doctor'
exit $bad
