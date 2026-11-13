#!/usr/bin/env bash
# idle-compact screen verdicts on captured Claude Code panes (capture-pane -peJ, 2.1.322, paths replaced by /home/fx-user).
# Fixtures in fixtures/idle-compact/: placeholder and queued panes are real captures; ghost-suggestion is the placeholder
# pane with a dim suggestion line; pulse-leftover is the box orchestrator-pulse left after one Ctrl+U (T1696).
# No tmux: tm is replaced by a reader of the fixture file.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IC="$(dirname "$here")/idle-compact"
FX="$here/fixtures/idle-compact"
. "$HOME/agents/bin/tests/lib/assert.sh"

verdict() { ( HARNESS_CONFIG=/dev/null; . "$IC"; F=$1
  tm() { case "$*" in *-peJt*) cat "$F" ;; *) perl -pe 's/\e(\[[0-9;:?]*[A-Za-z]|\][^\a\e]*(\a|\e\\))//g' "$F" ;; esac; }
  screen_reason ); }

is "ghost placeholder is an empty prompt"      "$(verdict "$FX/ghost-placeholder.pane")" ""
is "ghost suggestion is an empty prompt"       "$(verdict "$FX/ghost-suggestion.pane")" ""
is "queued message during a turn: turn"        "$(verdict "$FX/queued-busy.pane")" "turn in progress"
is "text typed under a queued message: typed"  "$(verdict "$FX/queued-typed.pane")" "prompt box not empty (len=14)"
is "pulse leftover (real typed text): typed"   "$(verdict "$FX/pulse-leftover.pane")" "prompt box not empty (len=69)"

exit $bad
