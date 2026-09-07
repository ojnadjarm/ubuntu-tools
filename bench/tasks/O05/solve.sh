#!/usr/bin/env bash
# O05 oracle — pc power already parses the sysfs charge-control threshold.
set -euo pipefail
pc power --json | jq -c '{limit_pct: .battery.charge_limit}'
