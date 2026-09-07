#!/usr/bin/env bash
# Runs every test in ~/agents/bin/tests/.
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bad=0
for t in "$dir"/*.test.sh; do bash "$t" || bad=1; done
for t in "$dir"/*.test.py; do python3 "$t" || bad=1; done
exit $bad
