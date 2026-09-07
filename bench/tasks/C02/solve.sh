#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
out=$("$PC" power profile balanced --apply)
id=${out##*pc undo }
jq -nc --arg r "pc undo $id" '{profile:"balanced",rollback:$r,did_it:true}'
