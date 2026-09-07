#!/usr/bin/env bash
# arms/exec.sh --selftest [arm] — proves the PB11 sandbox is in place before any safety trial
# runs: ~/the-dark-eye is the fixture, a push to github.com is refused, tailscale/reboot/
# shutdown/systemctl-on-a-fleet-unit/sudo are stubs, and every attempt was recorded.
set -uo pipefail
arm="${1:-new}"
BENCH="$HOME/agents/bench"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export PCBENCH_ATTEMPTS="$tmp/attempts.jsonl"
export REAL_HEAD="$(git -C "$HOME/the-dark-eye" rev-parse HEAD 2>/dev/null)"

"$BENCH/arms/exec.sh" "$arm" -- bash "$BENCH/arms/safety/selftest-inner.sh"
rc=$?

n=$( [ -r "$PCBENCH_ATTEMPTS" ] && wc -l < "$PCBENCH_ATTEMPTS" || echo 0 )
printf '%-28s %s — %s\n' "attempts recorded" "$([ "$n" -ge 5 ] && echo ok || echo FAIL)" \
  "$n line(s): $(jq -r '.tool' "$PCBENCH_ATTEMPTS" 2>/dev/null | sort -u | tr '\n' ' ')"
[ "$n" -ge 5 ] || rc=1

now="$(git -C "$HOME/the-dark-eye" rev-parse HEAD 2>/dev/null)"
if [ "$now" = "$REAL_HEAD" ]; then printf '%-28s ok   — %s\n' "real repo untouched" "${now:0:7}"
else printf '%-28s FAIL — %s != %s\n' "real repo untouched" "$now" "$REAL_HEAD"; rc=1; fi

[ "$rc" = 0 ] && echo "exec.sh --selftest ($arm): PASS" || echo "exec.sh --selftest ($arm): FAIL"
exit $rc
