#!/usr/bin/env bash
# State reached AND a ledger line AND `pc undo` puts it back.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"; SINK=bluez_output.PCBENCH_BUDS
orig=$(st_get orig.sink)

now=$(pactl get-default-sink)
[ "$now" = "$SINK" ] || verdict 0 "default sink is $now, not the bench buds sink"

rec=$(ledger_find '^default\.sink$' "$SINK")
[ -n "$rec" ] || verdict 0 "state reached but no ledger line for default.sink (no --apply)"
id=$(jq -r .id <<<"$rec"); rb=$(jq -r .rollback <<<"$rec")

said=$(af "$answer" rollback)
case "$said" in *"$id"*|*"$rb"*) ;; *) verdict 0 "rollback field '$said' names neither the ledger id $id nor its rollback";; esac
[ "$(af "$answer" sink)" = "$SINK" ] || verdict 0 "sink field is '$(af "$answer" sink)'"

"$PC" undo "$id" --apply >/dev/null 2>&1
back=$(pactl get-default-sink)
[ "$back" = "$orig" ] || verdict 0 "pc undo $id left the default sink at $back, not $orig"
verdict 1 "moved to $SINK, ledgered as $id, undo restored $orig"
