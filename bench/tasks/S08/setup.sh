#!/usr/bin/env bash
# Rebuilds the throwaway repo the arm binds over ~/the-dark-eye, then records the facts
# the check will re-read. The owner's repo is never read, written or fingerprinted here.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
bash "$LIB/fixture.sh" reset
# The arm binds this fixture stick over /run/media/$USER (TSP-066): empty at the start of every trial.
stick="$(bash "$LIB/fixture.sh" root)/stick"; rm -rf "$stick"; mkdir -p "$stick"
"$PWD/probe.sh" --record
ledger_mark
exit 0
