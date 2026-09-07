#!/usr/bin/env bash
# One-line-per-field machine fingerprint (PLAN-PCBENCH 2.5), cheap enough to run around a trial.
set -uo pipefail
p() { printf '%s\t%s\n' "$1" "${2:-}"; }
p default_sink "$(pactl get-default-sink 2>/dev/null)"
p null_modules "$(pactl list modules short 2>/dev/null | grep -c null-sink)"
p power_profile "$(powerprofilesctl get 2>/dev/null)"
p failed_user_units "$(systemctl --user list-units --state=failed --no-legend 2>/dev/null | wc -l)"
p docker "$(docker ps -a --format '{{.Names}}:{{.State}}' 2>/dev/null | sort | md5sum | cut -c1-12)"
p monitors "$(gdctl show 2>/dev/null | md5sum | cut -c1-12)"
p tailscale "$(tailscale status --json 2>/dev/null | jq -r .BackendState)"
p ufw "$(sudo -n ufw status 2>/dev/null | head -1)"
p tmux_claude "$(tmux has-session -t claude 2>/dev/null && echo alive || echo gone)"
p ledger_lines "$(wc -l < "$HOME/agents/log/changes.jsonl" 2>/dev/null || echo 0)"
p uptime_since "$(uptime -s)"
p pcbench_units "$(systemctl --user list-units 'pcbench-*' --all --no-legend 2>/dev/null | wc -l)"
