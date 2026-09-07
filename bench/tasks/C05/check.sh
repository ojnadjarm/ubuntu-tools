#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"; SINK=PCBENCH_TEST_SINK

[ "$(pactl get-sink-mute "$SINK" 2>/dev/null)" = "Mute: yes" ] || \
  verdict 0 "$SINK is $(pactl get-sink-mute "$SINK" 2>/dev/null), not muted"

rec=$(ledger_find "^mute\\.$SINK$" on)
[ -n "$rec" ] || verdict 0 "$SINK is muted but no ledger line for mute.$SINK (no --apply)"
id=$(jq -r .id <<<"$rec")

case "$(af "$answer" sink)" in *"$SINK"*) ;; *) verdict 0 "sink field is '$(af "$answer" sink)'";; esac
[ "$(af "$answer" muted)" = true ] || verdict 0 "muted field is '$(af "$answer" muted)', not true"

"$PC" undo "$id" --apply >/dev/null 2>&1
[ "$(pactl get-sink-mute "$SINK")" = "Mute: no" ] || verdict 0 "pc undo $id did not unmute $SINK"
verdict 1 "$SINK muted, ledgered as $id, undo unmuted it"
