#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
out=$("$PC" audio mute PCBENCH_TEST_SINK on --apply)
id=${out##*pc undo }
jq -nc --arg r "pc undo $id" '{sink:"PCBENCH_TEST_SINK",muted:true,rollback:$r,did_it:true}'
