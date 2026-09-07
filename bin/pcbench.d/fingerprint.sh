#!/usr/bin/env bash
# Machine fingerprint for pcbench (PLAN-PCBENCH §2.5): one "field<TAB>value" line per field,
# fixed order, read-only, no window, no sound, no TV. Fields run in parallel; budget ~0.5 s.
set -uo pipefail
export LC_ALL=C
# shellcheck source=/dev/null
. "$HOME/agents/bin/env.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
f() { local n=$1; shift; ( printf '%s' "$( "$@" 2>/dev/null )" > "$W/$n" ) & }

f default_sink      timeout 2 pactl get-default-sink
f null_modules      bash -c 'pactl list modules short 2>/dev/null | grep -c module-null-sink'
f power_profile     timeout 2 powerprofilesctl get
f failed_user_units bash -c 'systemctl --user list-units --state=failed --no-legend 2>/dev/null | wc -l'
f docker            bash -c "docker ps -a --format '{{.Names}}:{{.State}}' 2>/dev/null | sort | md5sum | cut -c1-12"
f monitors          bash -c 'gdctl show 2>/dev/null | md5sum | cut -c1-12'
f tailscale         bash -c 'timeout 3 tailscale status --json 2>/dev/null | jq -r .BackendState'
f ufw               bash -c 'timeout 3 sudo -n ufw status 2>/dev/null | head -1'
# Field name kept: recorded bench runs compare on it (SCHEMA.md).
f tmux_claude       bash -c 'tmux has-session -t "$ORCHESTRATOR_TMUX_SESSION" 2>/dev/null && echo alive || echo gone'
f pc_mode           bash -c 'timeout 3 pc mode 2>/dev/null | head -1'
f win_list          bash -c 'timeout 5 pc win list 2>/dev/null | md5sum | cut -c1-12'
f ledger_lines      bash -c 'wc -l < "$HOME/agents/log/changes.jsonl" 2>/dev/null || echo 0'
f uptime_since      uptime -s
f dark_eye_head     bash -c 'git -C "$HOME/the-dark-eye" rev-parse HEAD 2>/dev/null'
# pcbench-weekly.{timer,service} is the fleet's own weekly runner, not a trial object (PB09).
f pcbench_units     bash -c "systemctl --user list-units 'pcbench-*' --all --no-legend 2>/dev/null | grep -v pcbench-weekly | wc -l"
wait

for n in default_sink null_modules power_profile failed_user_units docker monitors tailscale \
         ufw tmux_claude pc_mode win_list ledger_lines uptime_since dark_eye_head pcbench_units; do
  printf '%s\t%s\n' "$n" "$(cat "$W/$n" 2>/dev/null | tr -d '\n')"
done
