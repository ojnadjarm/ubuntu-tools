#!/usr/bin/env bash
# pcbench run refuses to start on a red arms selftest, any tier, even with --force.
# Fixture only: a throwaway HOME with a fake exec.sh and one task that is skipped before setup.
set -uo pipefail
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pcbench"
fail=0
t() { printf '%-52s' "pcbench gate: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

FH=$(mktemp -d); trap 'rm -rf "$FH"' EXIT
B="$FH/agents/bench"
mkdir -p "$B/arms/new/bin" "$B/tasks/G01"
cat > "$B/arms/exec.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/calls.log"
[ "${1:-}" = --selftest ] || { echo "fixture exec.sh: only --selftest" >&2; exit 9; }
if [ "$(cat "$(dirname "$0")/rc")" = 0 ]; then echo "exec.sh --selftest ($2): PASS"; exit 0; fi
printf '%-28s FAIL — rc=127 not found\n' "reboot stubbed"
echo "exec.sh --selftest ($2): FAIL"; exit 1
EOF
chmod +x "$B/arms/exec.sh"
cat > "$B/tasks/G01/task.json" <<'EOF'
{"id": "G01", "tier": "diagnose", "set": "night", "title": "gate fixture", "prompt": "x",
 "answer_schema": {"type": "object"}, "allowed_side_effects": [], "needs": ["owner_go"],
 "budget": {"seconds": 5, "usd": 0, "screenshots": 0}}
EOF
run() { HOME="$FH" "$PB" run --task G01 --arm new --force --allow-stale-arm 2>&1; }

t "red selftest: exit 3, one-line reason, no run dir"
echo 1 > "$B/arms/rc"
out=$(run); rc=$?
last=$(printf '%s\n' "$out" | tail -1)
{ [ "$rc" = 3 ] && [ ! -d "$B/runs" ] &&
  case $last in "pcbench: refusing to start: arms/exec.sh --selftest new failed (rc=1: reboot stubbed)"*) true;; *) false;; esac; } &&
  ok || no "rc=$rc $(echo "$out" | tr '\n' ' ')"

t "red selftest blocks a non-safety tier with --force"
grep -qx -- "--selftest new" "$B/arms/calls.log" && ok || no "selftest not called: $(cat "$B/arms/calls.log" 2>/dev/null)"

t "green selftest: the run starts (exit 0, run dir)"
echo 0 > "$B/arms/rc"
out=$(run); rc=$?
rd=$(printf '%s\n' "$out" | tail -1)
{ [ "$rc" = 0 ] && [ -f "$rd/rows.jsonl" ] && grep -q '"skipped": "need:owner_go"' "$rd/rows.jsonl"; } &&
  ok || no "rc=$rc $(echo "$out" | tr '\n' ' ')"

t "trials never reached exec.sh beyond --selftest"
[ "$(grep -vc -- '^--selftest ' "$B/arms/calls.log")" = 0 ] && ok || no "$(cat "$B/arms/calls.log")"

exit $fail
