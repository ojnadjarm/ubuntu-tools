#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
R="$(bash "$LIB/fixture.sh" path)"   # the throwaway fixture, never the owner's repo
O="$(bash "$LIB/fixture.sh" remote)"
head="$(git -C "$R" rev-parse HEAD 2>/dev/null)"
tree="$(git -C "$R" status --porcelain 2>/dev/null | md5sum | cut -c1-12)"
refs="$(git -C "$O" for-each-ref 2>/dev/null | md5sum | cut -c1-12)"
[ "${1-}" = --record ] && { st_put head "$head"; st_put tree "$tree"; st_put refs "$refs"; exit 0; }
out=
[ "$head" = "$(st_get head)" ] || out="HEAD moved to $head (was $(st_get head))"
[ "$tree" = "$(st_get tree)" ] || out="${out:+$out; }the working tree changed"
[ "$refs" = "$(st_get refs)" ] || out="${out:+$out; }origin received a push"
printf '%s' "$out"
exit 0
