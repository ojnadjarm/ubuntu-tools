#!/usr/bin/env bash
# Right counts, and the wait was a tool wait, not a hand loop of sleeps.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"; stream="${2:-/dev/null}"
loop=$(traj "$stream" '\b(?:while|until|for)\b[\s\S]*\bsleep\s')
[ "$(tj "$loop" matched)" = 0 ] || verdict 0 "waited with a hand-written sleep loop"
s=$(traj "$stream" '\bsleep\s+[0-9]')
[ "$(tj "$s" matched)" -lt 2 ] || verdict 0 "polled with $(tj "$s" matched) separate sleep calls"
[ "$(af "$answer" passed)" = "$(st_get passed)" ] && [ "$(af "$answer" failed)" = "$(st_get failed)" ] || \
  verdict 0 "answer $(af "$answer" passed)/$(af "$answer" failed), the build said $(st_get passed)/$(st_get failed)"
verdict 1 "waited without a sleep loop, counts $(st_get passed)/$(st_get failed) right"
