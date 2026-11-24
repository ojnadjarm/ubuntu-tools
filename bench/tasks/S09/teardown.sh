#!/usr/bin/env bash
# Drops the throwaway work repo, its remote and the state.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
root=$(bash "$LIB/fixture.sh" root)
rm -rf "$STATE" "$root/work-fixture" "$root/work-remote.git"
exit 0
