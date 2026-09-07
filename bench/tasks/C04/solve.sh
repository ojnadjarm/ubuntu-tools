#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
out=$("$PC" units stop pcbench-idle --user --apply)
id=${out##*pc undo }
jq -nc --arg r "pc undo $id" '{unit:"pcbench-idle.service",state:"inactive",rollback:$r,did_it:true}'
