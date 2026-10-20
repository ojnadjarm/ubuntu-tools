#!/usr/bin/env bash
# make.sh: record the Blender plates of the seven plate tests (or the named ones) into this dir under `heavy run` (T856); --into DIR records there.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
[[ ${1:-} == --into && -n ${2:-} ]] || exec heavy run --ticket T856 -- "$0" --into "$HERE" "$@"
OUT=$2 MAX_KB=${MAX_KB:-300}
shift 2
(($#)) || set -- mv-title3d mv-logo mv-render-blender mv-model-anim mv-model mv-render-speed mv-camera
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
bad=0
for t in "$@"; do
  if ! MV_PLATES_INTO=$T/$t bash "$HERE/../../$t.test.sh" >"$T/$t.log" 2>&1; then
    echo "make.sh: $t red, not recorded: $(grep -m1 '^FAIL' "$T/$t.log")" >&2; bad=1; continue
  fi
  [[ -f $T/$t/manifest ]] || { echo "make.sh: $t made no plates: $(tail -1 "$T/$t.log")" >&2; bad=1; continue; }
  kb=$(du -sk --apparent-size "$T/$t" | cut -f1)
  ((kb <= MAX_KB)) || { echo "make.sh: $t plates $kb KB > $MAX_KB KB, not recorded" >&2; bad=1; continue; }
  [[ -f $OUT/$t/manifest ]] && find "$OUT/$t" -type f -delete
  mkdir -p "$OUT/$t"
  cp -r "$T/$t/." "$OUT/$t/"
  echo "make.sh: $t $(find "$T/$t" -type f | wc -l) files, $kb KB, $(tail -1 "$T/$t.log") -> $OUT/$t"
done
exit $bad
