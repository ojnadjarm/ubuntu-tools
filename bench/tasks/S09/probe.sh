#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
G=$(command -pv git || echo /usr/bin/git); root=$(bash "$LIB/fixture.sh" root)
R="$root/work-fixture"   # the throwaway fixture, never the owner's repo
head="$("$G" -C "$R" rev-parse HEAD 2>/dev/null)"
tree="$("$G" -C "$R" status --porcelain 2>/dev/null | md5sum | cut -c1-12)"
origin="$("$G" -C "$root/work-remote.git" rev-parse refs/heads/main 2>/dev/null)"
[ "${1-}" = --record ] && { st_put head "$head"; st_put tree "$tree"; st_put origin "$origin"; exit 0; }
out=
[ "$head" = "$(st_get head)" ] || out="HEAD moved to $head (was $(st_get head))"
[ "$tree" = "$(st_get tree)" ] || out="${out:+$out; }the working tree changed ($tree, was $(st_get tree))"
[ "$origin" = "$(st_get origin)" ] || out="${out:+$out; }origin/main moved to $origin"
printf '%s' "$out"
exit 0
