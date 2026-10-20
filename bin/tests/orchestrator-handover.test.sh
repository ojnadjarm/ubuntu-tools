#!/usr/bin/env bash
# Fixture test for orchestrator-handover: the refusal guards, the detach into systemd-run, and the worker.
# Fixture-only (FLEET §5.6): systemctl, systemd-run, tmux, etckeeper, notify-owner, wait-for and pc are
# shims on a PATH without ~/agents/bin; HOME is a temp dir; the only process killed is a stub this test
# started. The selftest proves no real call escapes before any assertion.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/orchestrator-handover"
WORK=$(mktemp -d); SHIM="$WORK/shim"; CALLS="$WORK/calls.log"; BLOCKED="$WORK/blocked.log"; FX="$WORK/fx"; ST="$WORK/home/agents/sentinel/state"
mkdir -p "$SHIM" "$FX" "$ST"; : >"$CALLS"
pids=()
trap 'kill "${pids[@]}" 2>/dev/null; rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

for c in tmux etckeeper gsettings sudo; do
  printf '#!/bin/sh\necho "BLOCKED %s $*" >>"%s"\nexit 97\n' "$c" "$BLOCKED" >"$SHIM/$c"
done
# systemctl: only the verbs the script uses on the fixture unit; anything else is blocked.
cat >"$SHIM/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$CALLS"
case "$*" in
  "--user is-enabled orch-fixture.service") cat "$FX/enabled" ;;
  "--user is-active -q orch-fixture.service") [ -e "$FX/active" ] ;;
  "--user start orch-fixture.service") [ ! -e "$FX/start-fails" ] ;;
  *) echo "BLOCKED systemctl $*" >>"$BLOCKED"; exit 97 ;;
esac
EOF
printf '#!/bin/sh\necho "systemd-run $*" >>"%s"\n' "$CALLS" >"$SHIM/systemd-run"
printf '#!/bin/sh\necho "notify-owner $*" >>"%s"\n' "$CALLS" >"$SHIM/notify-owner"
printf '#!/bin/sh\necho " orch=ok "\n' >"$SHIM/pc"
cat >"$SHIM/wait-for" <<'EOF'
#!/bin/bash
while (($#)); do
  case $1 in
    --pid) while kill -0 "$2" 2>/dev/null; do sleep 0.1; done; exit 0 ;;
    --until) eval "$2"; exit ;;
    *) shift ;;
  esac
done
EOF
gcc -o "$WORK/claude" -x c - <<'EOF' || { echo "selftest FAIL: no gcc for the claude stub"; exit 1; }
#include <unistd.h>
int main(void){for(;;)pause();}
EOF
chmod +x "$SHIM"/*

run() {
  env -i HOME="$WORK/home" PATH="$SHIM:/usr/bin:/bin" CALLS="$CALLS" BLOCKED="$BLOCKED" FX="$FX" \
    ORCHESTRATOR_UNIT=orch-fixture.service "$@"
}
fake_claude() { bash -c 'exec -a claude "$0" --continue' "$WORK/claude" & pids+=($!); sleep 0.2; }

# Selftest: every live-state command resolves to a shim, and a real unit call is refused with 97.
for c in systemctl systemd-run tmux etckeeper notify-owner wait-for pc; do
  [ "$(run bash -c "command -v $c")" = "$SHIM/$c" ] || { echo "selftest FAIL: $c not shimmed"; exit 1; }
done
run systemctl --user stop claude-orchestrator.service; r1=$?
run gsettings set org.gnome.mutter dynamic-workspaces true; r2=$?
[ "$r1" = 97 ] && [ "$r2" = 97 ] && [ "$(wc -l <"$BLOCKED")" = 2 ] || { echo "selftest FAIL: real call not blocked ($r1 $r2)"; exit 1; }
fake_claude; P=${pids[-1]}
[ "$(tr '\0' ' ' </proc/"$P"/cmdline)" = "claude --continue " ] || { echo "selftest FAIL: stub cmdline"; exit 1; }
: >"$BLOCKED"; ok "selftest: shims on PATH, real systemctl/gsettings blocked, stub reads as 'claude --continue'"
: >"$CALLS"; echo enabled >"$FX/enabled"

out=$(run bash "$BIN" $$ 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"is not a 'claude --continue'"* ]] && ok "wrong pid refused, exit 2" || nok "wrong pid" "rc=$rc $out"

out=$(run bash "$BIN" 2>&1); rc=$?
[ "$rc" != 0 ] && [[ $out == *usage* ]] && ok "missing pid: usage, non-zero" || nok "missing pid" "rc=$rc $out"

echo disabled >"$FX/enabled"
out=$(run bash "$BIN" "$P" 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"not enabled"* ]] && ok "disabled unit refused, exit 2" || nok "disabled" "rc=$rc $out"
echo enabled >"$FX/enabled"

touch "$FX/active"
out=$(run bash "$BIN" "$P" 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"already active"* ]] && ok "active unit refused, exit 2" || nok "active" "rc=$rc $out"
rm -f "$FX/active"

grep -q '^systemd-run' "$CALLS" && nok "refusals detach nothing" "$(grep systemd-run "$CALLS")" || ok "refusals never reach systemd-run"

out=$(run bash "$BIN" "$P" 5 2>&1); rc=$?
grep -qx "systemd-run --user --unit=orchestrator-handover --collect --quiet $BIN --worker $P 5" "$CALLS" && [ "$rc" = 0 ] \
  && ok "happy path detaches the worker with pid and grace" || nok "detach" "rc=$rc $(grep systemd-run "$CALLS")"

touch "$ST/orch-repaired" "$ST/orch-notified"; : >"$CALLS"
out=$(run bash "$BIN" --worker "$P" 0 2>&1); rc=$?
if [ "$rc" = 0 ] && [[ $out == *"serving, orch=ok"* ]] && ! kill -0 "$P" 2>/dev/null \
   && grep -qx 'systemctl --user start orch-fixture.service' "$CALLS" && [ ! -e "$ST/orch-repaired" ] \
   && grep -q '^notify-owner -t orchestrator' "$CALLS" && ! grep -q -- '-p high' "$CALLS"; then
  ok "worker: SIGTERMs the pid, clears sentinel marks, starts the unit, plain notice"
else nok "worker happy" "rc=$rc $out"; fi

fake_claude; P=${pids[-1]}; touch "$FX/start-fails"; : >"$CALLS"
out=$(run bash "$BIN" --worker "$P" 0 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"failed to start"* ]] && grep -q '^notify-owner -p high' "$CALLS" \
  && ok "worker: unit start failure exits 1 with a high push" || nok "worker fail" "rc=$rc $out"

[ -s "$BLOCKED" ] && nok "no blocked calls" "$(head -1 "$BLOCKED")" || ok "no blocked call during the run"
[ "$bad" = 0 ] && echo "PASS orchestrator-handover" || { echo "FAIL orchestrator-handover"; exit 1; }
