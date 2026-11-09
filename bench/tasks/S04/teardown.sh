#!/usr/bin/env bash
# The commit and push land in the throwaway fixture, which setup.sh rebuilds per trial.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
rm -rf "$STATE"
exit 0
