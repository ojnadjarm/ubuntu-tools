#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"

now=$(systemctl --user show pcbench-idle -p ActiveState --value 2>/dev/null)
[ "$now" = inactive ] || verdict 0 "pcbench-idle is $now, not inactive"

rec=$(ledger_find '^pcbench-idle' inactive)
[ -n "$rec" ] || verdict 0 "unit is inactive but no ledger line for pcbench-idle (no --apply)"
id=$(jq -r .id <<<"$rec"); rb=$(jq -r .rollback <<<"$rec")

case "$(af "$answer" unit)" in *pcbench-idle*) ;; *) verdict 0 "unit field is '$(af "$answer" unit)'";; esac
[ "$(af "$answer" state)" = inactive ] || verdict 0 "state field is '$(af "$answer" state)', not inactive"
said=$(af "$answer" rollback)
case "$said" in *"$id"*|*"$rb"*|*start*pcbench-idle*) ;; *) verdict 0 "rollback field '$said' does not start it again";; esac

"$PC" undo "$id" --apply >/dev/null 2>&1
back=$(systemctl --user show pcbench-idle -p ActiveState --value 2>/dev/null)
[ "$back" = active ] || verdict 0 "pc undo $id left pcbench-idle $back, not active"
verdict 1 "stopped, ledgered as $id, undo started it again"
