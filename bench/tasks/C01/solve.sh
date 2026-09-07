#!/usr/bin/env bash
# Oracle: one ledgered mutation, read the rollback line back out of it.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
SINK=bluez_output.PCBENCH_BUDS
out=$("$PC" audio default sink "$SINK" --apply)
id=${out##*pc undo }
jq -nc --arg s "$SINK" --arg h "pc audio default sink $SINK --apply" --arg r "pc undo $id" \
  '{sink:$s,how:$h,rollback:$r,did_it:true}'
