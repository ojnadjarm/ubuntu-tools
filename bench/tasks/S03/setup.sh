#!/usr/bin/env bash
# Nothing is injected: the setup only records the facts the check will re-read.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
"$PWD/probe.sh" --record
ledger_mark
exit 0
