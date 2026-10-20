#!/usr/bin/env bash
# mvlib.test.sh: the shared probe and colour-family table, and no-video handling in mv-review/mv-diff/mv-quality; lavfi fixtures deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SCR=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mvlib-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
py() { PYTHONPATH=$SCR python3 -c "import sys, mvlib"$'\n'"$1" "${@:2}"; }

ff -f lavfi -i testsrc2=s=320x180:r=30000/1001:d=1 -f lavfi -i sine=d=1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -colorspace bt470bg -color_range pc -c:a aac "$FX/sd.mp4"
ff -f lavfi -i testsrc2=s=180x320:r=25:d=1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p10le "$FX/raw10.mp4"
ff -f lavfi -i sine=d=1 -c:a aac "$FX/audio.m4a"
echo junk >"$FX/broken.mp4"

ok "$(is "$(py 'p = mvlib.probe(sys.argv[1]); print(sorted(p), p["fps"], p["rate"] > 29.9, p["audio"], p["matrix"], p["range"], p["untagged"])' "$FX/sd.mp4")" \
  "['audio', 'color', 'duration', 'fps', 'height', 'matrix', 'pix', 'range', 'rate', 'untagged', 'width'] 30000/1001 True True bt601 pc False")" \
  "probe: union of fields on a tagged SD clip, bt470bg -> bt601 matrix"
ok "$(is "$(py 'p = mvlib.probe(sys.argv[1]); print(p["width"], p["height"], p["pix"], p["audio"], p["matrix"], p["untagged"])' "$FX/raw10.mp4")" \
  "180 320 yuv420p10le False bt709 True")" "probe: untagged 10-bit clip without audio"
ok "$(is "$(py 'print(*map(mvlib.family, ("bt470bg", "smpte170m", "smpte2084", "arib-std-b67", "bt2020nc", "bt709")))')" \
  "bt601 bt601 bt2020 bt2020 bt2020 bt709")" "family: one table incl. PQ and HLG"
ok "$(is "$(py $'try:\n mvlib.probe(sys.argv[1])\nexcept mvlib.MvError as e:\n print(e)' "$FX/audio.m4a")" "no video stream in $FX/audio.m4a")" \
  "probe: audio-only file raises MvError"
ok "$(py $'try:\n mvlib.probe(sys.argv[1])\nexcept mvlib.MvError as e:\n print(str(e).startswith("cannot read"))' "$FX/broken.mp4" | grep -qx True && echo 1 || echo 0)" \
  "probe: unreadable file raises MvError"

"$SCR/mv-review" "$FX/audio.m4a" --out "$FX/rev" >"$FX/rev.log" 2>&1; r=$?
ok "$( [[ $r == 1 ]] && grep -qx "mv-review: no video stream in $FX/audio.m4a" "$FX/rev.log" && ! grep -q Traceback "$FX/rev.log" && echo 1 || echo 0)" \
  "mv-review: audio-only -> one FAIL line, rc 1, no traceback (rc $r)"
"$SCR/mv-diff" "$FX/sd.mp4" "$FX/audio.m4a" >"$FX/diff.log" 2>&1; r=$?
ok "$( [[ $r == 2 ]] && grep -q 'mv-diff: no video stream' "$FX/diff.log" && ! grep -q Traceback "$FX/diff.log" && echo 1 || echo 0)" \
  "mv-diff: audio-only -> rc 2, no traceback (rc $r)"
"$SCR/mv-quality" "$FX/sd.mp4" "$FX/audio.m4a" >"$FX/q.log" 2>&1; r=$?
ok "$( [[ $r == 2 ]] && ! grep -q Traceback "$FX/q.log" && echo 1 || echo 0)" "mv-quality: audio-only -> rc 2, no traceback (rc $r)"
ok "$(is "$(grep -ls '^def probe' "$SCR"/* | wc -l)" 1)" "one probe definition across scripts"

echo "mvlib.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
