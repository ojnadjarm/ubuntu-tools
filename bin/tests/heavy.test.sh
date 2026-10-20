#!/usr/bin/env bash
# T775: heavy against a stub systemd-run on PATH — scope argv, cwd/env, rc passthrough, summary line, ledger, nice fallback.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

mkdir -p "$WORK/stubs" "$WORK/cwd"
cat >"$WORK/stubs/systemd-run" <<'EOF'
#!/usr/bin/env bash
# Stub: the bus probe (`... true`) exits $STUB_BUS_RC; otherwise logs argv and runs what follows `--`.
[ "${*: -1}" = true ] && exit "${STUB_BUS_RC:-0}"
printf '%s\n' "$*" >>"$STUB_ARGV"
while [ "$1" != -- ]; do shift; done; shift
exec "$@"
EOF
chmod +x "$WORK/stubs/systemd-run"
export STUB_ARGV="$WORK/argv" HEAVY_LOG="$WORK/log/heavy.jsonl"
hv() { (cd "$WORK/cwd" && PATH="$WORK/stubs:$PATH" FOO=bar "$BIN/heavy" "$@"); }

# 1. scope mode: argv, cwd, env, rc passthrough, summary line, ledger row.
out=$(hv run --ticket T775 -- bash -c 'echo "$PWD $FOO"; exit 7' 2>"$WORK/err"); rc=$?
is 'rc passed through'  "$rc" 7
is 'cwd and env kept'   "$out" "$WORK/cwd bar"
is 'scope argv' "$(cat "$WORK/argv")" \
  '--user --scope -q --expand-environment=no --slice=fleet-heavy.slice -p CPUWeight=idle -p IOWeight=10 --nice=19 -- bash -c echo "$PWD $FOO"; exit 7'
tail -1 "$WORK/err" | grep -qE '^heavy: [0-9]+\.[0-9]{2}s wall, [0-9]+\.[0-9]{2}s cpu \(scope\), ticket T775$' \
  && ok 'summary is the last line' || nok 'summary is the last line' "$(tail -1 "$WORK/err")"
is 'one ledger row' "$(jq -c '[.ticket, .mode, .rc, .cmd[0], .cwd]' "$HEAVY_LOG")" "[\"T775\",\"scope\",7,\"bash\",\"$WORK/cwd\"]"

# 2. cpu is the command's: a ~0.3 s busy loop shows up.
hv run -- bash -c 'i=0; while [ $i -lt 80000 ]; do i=$((i+1)); done' 2>"$WORK/err"
cpu=$(tail -1 "$WORK/err" | sed -E 's/.* ([0-9.]+)s cpu.*/\1/')
awk -v c="$cpu" 'BEGIN{exit !(c>0.05)}' && ok "cpu counted ($cpu s)" || nok 'cpu counted' "$cpu"
tail -1 "$WORK/err" | grep -q 'ticket -$' && ok 'no ticket prints -' || nok 'no ticket prints -' "$(tail -1 "$WORK/err")"

# 3. no user bus: nice -n 19 ionice -c3 fallback, said on stderr, systemd-run not used for the command.
: >"$WORK/argv"
out=$(STUB_BUS_RC=1 hv run --ticket T775 -- bash -c 'nice; exit 4' 2>"$WORK/err"); rc=$?
is 'fallback rc passed through' "$rc" 4
is 'fallback runs at nice 19'   "$out" 19
grep -q '^heavy: no user bus, falling back to nice -n 19 ionice -c3$' "$WORK/err" && ok 'fallback said' || nok 'fallback said' "$(cat "$WORK/err")"
is 'fallback skips systemd-run' "$(wc -c <"$WORK/argv")" 0
tail -1 "$WORK/err" | grep -q 'cpu (nice), ticket T775$' && ok 'fallback summary' || nok 'fallback summary' "$(tail -1 "$WORK/err")"
is 'fallback ledger mode' "$(tail -1 "$HEAVY_LOG" | jq -r .mode)" nice

# 4. usage errors exit 2 and run nothing.
hv run --ticket T1 2>/dev/null; is 'no command exits 2' "$?" 2
hv build -- true 2>/dev/null;  is 'unknown verb exits 2' "$?" 2
is 'ledger rows: 3 runs only' "$(wc -l <"$HEAVY_LOG")" 3


# 5. heavy at (T989): stub systemctl, mktemp XDG dirs; persistent units, list, cancel, refusals.
cat >"$WORK/stubs/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_SYSTEMCTL"
case " $* " in *" show "*) echo "${STUB_NEXT:-}";; esac
EOF
chmod +x "$WORK/stubs/systemctl"
export STUB_SYSTEMCTL="$WORK/systemctl.log" XDG_CONFIG_HOME="$WORK/cfg" XDG_RUNTIME_DIR="$WORK/run"
U="$WORK/cfg/systemd/user"
out=$(hv at '2026-10-22 03:30' --ticket T5 -- /bin/bash -lc 'echo "$HOME 50%"'); rc=$?
is 'at dry run rc 0' "$rc" 0
is 'at dry run says would' "$out" 'would: heavy-T5.timer 2026-10-22 03:30 -> /bin/bash -lc echo "$HOME 50%"'
ev 'at dry run writes nothing' '[ ! -e "$U" ] && [ ! -e "$STUB_SYSTEMCTL" ]'
out=$(hv at '2026-10-22 03:30' --ticket T5 --apply -- /bin/bash -lc 'echo "$HOME 50%"'); rc=$?
is 'at apply rc 0' "$rc" 0
is 'at apply last line is the rollback' "$(tail -1 <<<"$out")" 'rollback: heavy at --cancel T5'
ev 'timer is persistent' 'grep -qx "Persistent=true" "$U/heavy-T5.timer" && grep -qx "OnCalendar=2026-10-22 03:30" "$U/heavy-T5.timer"'
ev 'timer is wanted by timers.target' 'grep -qx "WantedBy=timers.target" "$U/heavy-T5.timer"'
is 'service wraps heavy run, escapes $ and %' "$(grep '^ExecStart=' "$U/heavy-T5.service")" \
  "ExecStart=$BIN/heavy run --ticket T5 -- \"/bin/bash\" \"-lc\" \"echo \\\"\$\$HOME 50%%\\\"\""
is 'service cancels itself after the run' "$(grep '^ExecStopPost=' "$U/heavy-T5.service")" "ExecStopPost=-$BIN/heavy at --cancel T5"
is 'apply reloads and enables' "$(head -2 "$STUB_SYSTEMCTL")" $'--user daemon-reload\n--user enable --now heavy-T5.timer'
hv at '2026-10-22 03:30' --ticket T5 --apply -- true 2>/dev/null; is 'existing unit refused' "$?" 1
mkdir -p "$WORK/run/systemd/transient"
printf '[Timer]\nOnCalendar=2026-10-21 02:10\n' >"$WORK/run/systemd/transient/heavy-T6.timer"
printf '[Service]\nExecStart=\nExecStart="/bin/bash" "-lc" "make.sh"\n' >"$WORK/run/systemd/transient/heavy-T6.service"
hv at '2026-10-22 03:30' --ticket T6 --apply -- true 2>/dev/null; is 'transient copy refused' "$?" 1
ev 'refusal writes nothing' '[ ! -e "$U/heavy-T6.timer" ]'
list=$(STUB_NEXT=@1792632600 hv at --list)
is 'list: persistent row' "$(grep '^T5 ' <<<"$list")" "T5     $(date -d @1792632600 '+%m-%d %H:%M') persistent \"/bin/bash\" \"-lc\" \"echo \\\"\$\$HOME 50%%\\\"\""
is 'list: transient row' "$(grep '^T6 ' <<<"$list")" "T6     $(date -d @1792632600 '+%m-%d %H:%M') transient  \"/bin/bash\" \"-lc\" \"make.sh\""
is 'list: no elapse prints -' "$(STUB_NEXT= hv at --list | awk '$1=="T5"{print $2}')" -
: >"$STUB_SYSTEMCTL"
hv at --cancel T5 >/dev/null; is 'cancel rc 0' "$?" 0
ev 'cancel removes both files' '[ ! -e "$U/heavy-T5.timer" ] && [ ! -e "$U/heavy-T5.service" ]'
is 'cancel stops, disables, reloads' "$(cat "$STUB_SYSTEMCTL")" $'--user disable --now --no-block heavy-T5.timer\n--user daemon-reload'
hv at --cancel T5 2>/dev/null; is 'cancel of nothing rc 1' "$?" 1
hv at 'not a time' --ticket T7 -- true 2>/dev/null; is 'bad OnCalendar rc 2' "$?" 2
hv at daily --ticket 7 -- true 2>/dev/null;       is 'bad ticket rc 2' "$?" 2
hv at daily --ticket T7 2>/dev/null;              is 'no command rc 2' "$?" 2

exit $bad
