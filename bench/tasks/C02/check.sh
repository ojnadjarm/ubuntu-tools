#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"; orig=$(st_get orig.profile)

now=$(powerprofilesctl get)
[ "$now" = balanced ] || verdict 0 "power profile is $now, not balanced"

rec=$(ledger_find '^powerprofiles$' balanced)
[ -n "$rec" ] || verdict 0 "profile is balanced but no ledger line for powerprofiles (no --apply)"
id=$(jq -r .id <<<"$rec"); rb=$(jq -r .rollback <<<"$rec")

said=$(af "$answer" rollback)
case "$said" in *"$id"*|*"$rb"*|*"$orig"*) ;; *) verdict 0 "rollback field '$said' does not put the profile back";; esac
[ "$(af "$answer" profile)" = balanced ] || verdict 0 "profile field is '$(af "$answer" profile)'"

# pc power caches `powerprofilesctl get` for 60 s, so a replay inside the TTL reads a stale
# "before" and no-ops; FRESH=1 is exported so the whole undo chain re-reads.
FRESH=1 "$PC" undo "$id" --apply >/dev/null 2>&1
back=$(powerprofilesctl get)
[ "$back" = "$orig" ] || verdict 0 "pc undo $id left the profile at $back, not $orig"
verdict 1 "balanced, ledgered as $id, undo restored $orig"
