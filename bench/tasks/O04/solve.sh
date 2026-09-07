#!/usr/bin/env bash
# O04 oracle — one status snapshot has both the used% and the SMART verdict.
# Quirk: .sections.disk.percent_used is the NVMe wear-level attribute, not filesystem
# fullness — that lives under .sections.resources.disk_root ("N% used, ...").
set -euo pipefail
pc status --fresh --json | jq -c '{
  used_pct: (.sections.resources.disk_root.value | capture("(?<p>[0-9]+)% used") | .p | tonumber),
  smart_ok: (.sections.disk.smart.value == "PASSED")
}'
