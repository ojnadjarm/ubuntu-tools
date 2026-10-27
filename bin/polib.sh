#!/usr/bin/env bash
# polib.sh — shared helpers for the po-* CLIs (product-owner agents, T1412). Source it, never execute it.
#   po_dir <cli> <p>   print ~/agents/po-<p> (HARNESS_HOME); exit 2 with a message unless it is a PO folder
#   po_list            print every PO name, one per line
# shellcheck source=/dev/null
[ -n "${HARNESS_ENV_LOADED:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/env.sh"
: "${HARNESS_HOME:=$HOME/agents}"

po_dir() {
  local cli="$1" p="${2:-}"
  case "$p" in ''|-*|*[!a-z0-9-]*) echo "$cli: expected a PO name like mooblox, got '$p'" >&2; return 2 ;; esac
  [ -r "$HARNESS_HOME/po-$p/BRIEF.md" ] && [ -d "$HARNESS_HOME/po-$p/inbox" ] ||
    { echo "$cli: no PO '$p' ($HARNESS_HOME/po-$p); known: $(po_list | paste -sd' ' -)" >&2; return 2; }
  printf '%s\n' "$HARNESS_HOME/po-$p"
}

po_list() {
  local d
  for d in "$HARNESS_HOME"/po-*/; do
    [ -r "$d/BRIEF.md" ] && [ -d "$d/inbox" ] && basename "$d" | sed 's/^po-//'
  done
}
