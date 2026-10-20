#!/usr/bin/env bash
# T572: `pc doctor` runs its rows as background jobs (cap 6) and the usage sweep under xargs -P 8,
# yet prints the same rows in the same order as a sequential run (PC_DOCTOR_JOBS=1).
# Fixture BIN, HOME, runtime dir and /proc with stub system tools; the real machine decides nothing.
set -uo pipefail
BIN="$HOME/agents/bin"
. "$BIN/tests/lib/assert.sh"
. "$BIN/tests/lib/budget.sh"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
FB="$WORK/bin"; DS="$WORK/stubs"; FR="$WORK/run"
mkdir -p "$FB" "$DS" "$WORK/home" "$FR/pc-status" "$WORK/state" "$WORK/proc" "$WORK/ci"
cp /proc/stat "$WORK/proc/stat"; : >"$FR/bus"; : >"$FR/wayland-0"; : >"$FR/ydotool"
echo '0.50 0.50 0.50 1/100 1' >"$WORK/loadavg"
echo 'PASS 1/1 files in 1 s' >"$WORK/ci/2026-01-01.txt"; touch "$WORK/ci/2026-01-01.txt"
sed 's#/proc/bus/input/devices#$PC_PROC/bus/input/devices#' "$BIN/pc-doctor" >"$FB/doctor"
cp "$BIN/pclib.sh" "$BIN/env.sh" "$FB/"
# Slow stubs sleep $FAKE_NAP (rows) or $FAKE_USAGE_NAP (usage probes) seconds, 0 by default.
for i in $(seq -w 1 16); do printf '#!/bin/sh\nsleep "${FAKE_USAGE_NAP:-0}"\n' >"$FB/pc-stub$i"; done
cat >"$FB/pc" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  'mode status') sleep "${FAKE_NAP:-0}"; echo agent;;
  'status --check') sleep "${FAKE_NAP:-0}"; echo 'PASS fixture';;
  'mutter extensions') sleep "${FAKE_NAP:-0}"; echo '[{"uuid":"window-calls@fixture","state":"ACTIVE"}]';;
  *) echo '{}';;
esac
EOF
printf '#!/bin/sh\nsleep "${FAKE_NAP:-0}"\necho "0 claims"\n' >"$FB/claims"
cat >"$DS/systemctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in *' start '*|*' stop '*|*' restart '*|*' reset-failed '*|*' enable '*|*' disable '*) echo "systemctl $*" >>"$FAKE_STATE/refused"; exit 99;; esac
case " $* " in *' is-active '*) sleep "${FAKE_NAP:-0}"; echo active;; *' list-timers '*) echo '[]';; esac
EOF
cat >"$DS/sudo" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -n ] && shift
case "$1" in true) exit 0;; ls) exec "$@";; *) echo "sudo $*" >>"$FAKE_STATE/refused"; exit 99;; esac
EOF
cat >"$DS/docker" <<'EOF'
#!/bin/sh
case "$1" in ps) exit 0;; *) echo "docker $*" >>"$FAKE_STATE/refused"; exit 99;; esac
EOF
printf '#!/bin/sh\ncase " $* " in *" Ping"*) ;; *" GetAddress"*) echo "s \\"unix:path=/fixture\\"";; *) exit 1;; esac\n' >"$DS/busctl"
for s in pgrep pactl journalctl; do printf '#!/bin/sh\n[ %s = pgrep ] && exit 1\nexit 0\n' "$s" >"$DS/$s"; done
chmod +x "$FB"/* "$DS"/*

# fdoc <jobs> <doctor args…> — the fixture doctor with PC_DOCTOR_JOBS=<jobs>.
fdoc() {
  local j=$1; shift
  HOME="$WORK/home" XDG_RUNTIME_DIR="$FR" WAYLAND_DISPLAY=wayland-0 YDOTOOL_SOCKET="$FR/ydotool" HARNESS_CONFIG=/dev/null \
    PC_LEDGER="$WORK/none.jsonl" PC_PROC="$WORK/proc" PC_ALERT_SPOOL="$WORK/spool-none" PC_ALERT_LOG="$WORK/alert-none.log" \
    AGENT_WORK="$WORK/aw-none" PC_FLEET_CI_DIR="$WORK/ci" FAKE_STATE="$WORK/state" PC_NPROC=4 PC_LOADAVG="$WORK/loadavg" \
    PC_DOCTOR_JOBS=$j PATH="$DS:$PATH" "$FB/doctor" "$@"
}
# norm — the report without the ms column and the timing- or cache-dependent fields.
norm() { sed -E 's/ +[0-9]+ ms$//; s/-h pc-stub[0-9]+ min [0-9]+\/max [0-9]+ms/-h min-max/; s/cache age [0-9]+s/cache age N/; s/\([0-9]+ entries\)/(N entries)/; s/ in [0-9]+\.[0-9]+ s/ in T s/; s/ +/ /g'; }

# --- sandbox selftest: the stubs refuse every mutating verb ------------------------------
FAKE_STATE="$WORK/state" "$DS/systemctl" --user restart x >/dev/null 2>&1
FAKE_STATE="$WORK/state" "$DS/sudo" -n reboot >/dev/null 2>&1
is 'stub selftest: systemctl restart and sudo reboot were refused' "$(wc -l <"$WORK/state/refused")" 2
rm -f "$WORK/state/refused"

# --- 1. parallel output equals the sequential output, row for row --------------------------
fdoc 1 --quick >"$WORK/seq.txt" 2>"$WORK/seq.err"; rs=$?
fdoc 6 --quick >"$WORK/par.txt" 2>"$WORK/par.err"; rp=$?
names_s=$(fdoc 1 --quick --json | jq -r '.[].name' | tr '\n' ' ')
names_p=$(fdoc 6 --quick --json | jq -r '.[].name' | tr '\n' ' ')
ok_n=$(grep -c '^OK' "$WORK/par.txt")
is 'the fixture doctor passes sequentially' "$rs" 0
is 'the fixture doctor passes in parallel' "$rp" 0
[ "$ok_n" -ge 15 ] && ok "the parallel run has $ok_n OK rows" || nok 'parallel OK rows >= 15' "$ok_n"
is 'rows come in the same fixed order' "$names_p" "$names_s"
is 'text output is identical minus the ms column' "$(norm <"$WORK/par.txt")" "$(norm <"$WORK/seq.txt")"
is 'no stderr from either run' "$(cat "$WORK/seq.err" "$WORK/par.err" | wc -c)" 0
is 'the usage row swept the 16 fixture scripts' "$(grep -c '^OK *usage *16 scripts' "$WORK/par.txt")" 1

# --- 2. on slow stub rows the parallel wall is < 0.6 x the sum of the row times -------------
t0=$EPOCHREALTIME
FAKE_NAP=0.35 FAKE_USAGE_NAP=0.08 fdoc 6 --quick --json >"$WORK/slow.json" 2>/dev/null
wall=$(( (10#${EPOCHREALTIME/./} - 10#${t0/./}) / 1000 ))
sum=$(jq '[.[].ms]|add' "$WORK/slow.json")
r=$(budget 0.6)
awk -v w="$wall" -v s="$sum" -v r="$r" 'BEGIN{exit !(w < s * r)}' && ok "parallel wall ${wall}ms < $r x row sum ${sum}ms" || nok "parallel wall < $r x row sum" "wall ${wall}ms sum ${sum}ms"
is 'slow rows keep the fixed order' "$(jq -r '.[].name' "$WORK/slow.json" | tr '\n' ' ')" "$names_s"
u=$(jq '.[]|select(.name=="usage").ms' "$WORK/slow.json")
b=$(budget 0.768)
awk -v u="$u" -v b="$b" 'BEGIN{exit !(u < b * 1000)}' && ok "usage row ${u}ms < $b s (0.6 x 16 x 80ms, xargs -P 8)" || nok "usage row runs its probes in parallel (< $b s)" "${u}ms"
is 'the doctor asked no stub to mutate' "$(cat "$WORK/state/refused" 2>/dev/null | wc -l)" 0

[ $bad = 0 ] && echo 'PASS pc-doctor-parallel' || echo 'FAIL pc-doctor-parallel'
exit $bad
