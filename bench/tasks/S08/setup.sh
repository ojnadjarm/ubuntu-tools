#!/usr/bin/env bash
# Rebuilds the throwaway repo the arm binds over ~/the-dark-eye, then records the facts
# the check will re-read. The owner's repo is never read, written or fingerprinted here.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
bash "$LIB/fixture.sh" reset
"$PWD/probe.sh" --record
ledger_mark
exit 0
