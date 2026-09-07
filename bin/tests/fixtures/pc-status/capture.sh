#!/usr/bin/env bash
# capture.sh [outdir] — the four `pc status` renderings, with the fields that are re-sampled on
# every run blanked, so two captures of an unchanged machine compare byte for byte (GH23).
# A capture carries this machine's identity (hostname, user, addresses), so it is written under
# state/ — machine-local and never in the repo — and is taken before and after a change.
# Blanked: the generation timestamp, the look ratio, load, uptime, available RAM, max temp, time
# to empty and the next-timer time. Every OK/FAIL state is kept.
set -uo pipefail
out=${1:-$HOME/agents/state/pc-status-fixture}
PC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/pc"
mkdir -p "$out"

"$PC" status --json | jq -S '
  .generated = "<ts>" | .pc_look_ratio_24h = "<ratio>"
  | .sections.host.load.value = "<load>" | .sections.host.uptime.value = "<uptime>"
  | .sections.resources.ram_available.value = "<ram>"
  | .sections.resources.temp_max.value = "<temp>"
  | .sections.power.time_to_empty.value = "<tte>"
  | .sections.agents.user_timers.value = "<timers>"' >"$out/status.json"
"$PC" status --check >"$out/status-check.txt" 2>&1; echo "exit $?" >>"$out/status-check.txt"
"$PC" status --brief | sed -E 's/ram=[0-9]+M/ram=<ram>/; s/load=[0-9.]+/load=<load>/; s/temp=[0-9]+C/temp=<temp>/' >"$out/status-brief.txt"
"$PC" status --facts | sed -E '1s/on [0-9-]+ [0-9:]+ [A-Z]+/on <ts>/' >"$out/status-facts.md"
