#!/usr/bin/env bash
# T498: agents-status table on a fixture HOME; on-demand agents (no timer drop-in) are never probed as timers.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
t() { printf '%-64s' "agents-status: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

H="$(mktemp -d)"
trap 'rm -rf "$H"' EXIT
mkdir -p "$H/agents/tim/logs" "$H/agents/od" "$H/.config/systemd/user/agent@tim.timer.d" "$H/stub"
touch "$H/agents/tim/BRIEF.md" "$H/agents/od/BRIEF.md"
echo 'ENABLED=no' > "$H/agents/od/agent.env"
printf '[Timer]\nOnCalendar=\nOnCalendar=*-*-* 04:30\n' > "$H/.config/systemd/user/agent@tim.timer.d/schedule.conf"
printf 'start\tend\texit\tsecs\n2026-10-19T04:30:00\t2026-10-19T04:31:22\t0\t82\n' > "$H/agents/tim/logs/index.tsv"
cat > "$H/stub/systemctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$H/calls"
case "\$*" in *is-enabled*) echo enabled ;; *NextElapse*) echo 'Tue 2026-10-20 04:30:00 CEST' ;; esac
EOF
chmod +x "$H/stub/systemctl"
OUT="$(HOME="$H" PATH="$H/stub:$PATH" "$BIN/agents-status")"

t "selftest: the systemctl stub took every call"
grep -q 'agent@tim.timer' "$H/calls" 2>/dev/null && ok || no "stub not called"

t "timer agent: enabled, schedule, next, last run"
printf '%s\n' "$OUT" | grep -qE '^tim +enabled +\*-\*-\* 04:30 +10-20 04:30 +10-19 04:31 +0 +82$' && ok || no "$(printf '%s\n' "$OUT" | grep '^tim')"

t "on-demand agent: says on demand, no next run"
printf '%s\n' "$OUT" | grep -qE '^od +no +on demand +- +- +- +-$' && ok || no "$(printf '%s\n' "$OUT" | grep '^od')"

t "on-demand agent: agent@od.timer never queried"
! grep -q 'agent@od' "$H/calls" && ok || no "$(grep 'agent@od' "$H/calls")"

exit $fail
