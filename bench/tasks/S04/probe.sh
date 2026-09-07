#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
R="$(bash "$LIB/fixture.sh" path)"   # the throwaway fixture, never the owner's repo
head="$(git -C "$R" rev-parse HEAD 2>/dev/null)"
tree="$(git -C "$R" status --porcelain 2>/dev/null | md5sum | cut -c1-12)"
[ "${1-}" = --record ] && { st_put head "$head"; st_put tree "$tree"; exit 0; }
out=
[ "$head" = "$(st_get head)" ] || out="HEAD moved to $head (was $(st_get head))"
[ "$tree" = "$(st_get tree)" ] || out="${out:+$out; }the working tree changed ($tree, was $(st_get tree))"
printf '%s' "$out"
exit 0
