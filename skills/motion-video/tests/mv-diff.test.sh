#!/usr/bin/env bash
# mv-diff.test.sh: mv-diff on synthetic lavfi cut pairs; fixtures are created here and deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts/mv-diff
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-diff-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
near() { awk -v a="$1" -v b="$2" -v e="$3" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=e)}' && echo 1 || echo 0; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
js() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
cut() { ff -f lavfi -i "testsrc2=s=640x360:r=30:d=${3:-10}" -f lavfi -i "sine=f=440:d=${3:-10}:sample_rate=48000" \
  -vf "$1" -af "$2" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac "$4"; }

cut null anull 10 "$FX/a.mp4"
cut null anull 10 "$FX/a2.mp4"
cut "drawbox=x=0:y=0:w=iw:h=ih:color=red@1:t=fill:enable='between(t,3.3,5.3)'" anull 10 "$FX/colour.mp4"
cut null "volume=12dB:enable='between(t,6,7)'" 10 "$FX/loud.mp4"
cut null anull 8 "$FX/short.mp4"
ok "$( [[ -s $FX/a.mp4 && -s $FX/colour.mp4 && -s $FX/loud.mp4 && -s $FX/short.mp4 ]] && echo 1 || echo 0)" "fixtures generated"

ok "$("$BIN" --help >/dev/null 2>&1 && echo 1 || echo 0)" "--help rc 0"

"$BIN" "$FX/a.mp4" "$FX/a2.mp4" --json --out "$FX/o1" >"$FX/same.json"; r=$?
ok "$( [[ $r == 0 && $(js "$FX/same.json" "len(d['ranges'])") == 0 && ! -e $FX/o1 ]] && echo 1 || echo 0)" \
  "identical cuts (two encodes) -> 0 ranges, rc 0, no sheet"

"$BIN" "$FX/a.mp4" "$FX/colour.mp4" --json --out "$FX/o2" >"$FX/colour.json"; r=$?
ok "$(is "$r" 1)" "colour change -> rc 1"
ok "$(is "$(js "$FX/colour.json" "len(d['ranges'])")" 1)" "colour change -> exactly 1 range"
ok "$(near "$(js "$FX/colour.json" "d['ranges'][0]['start']")" 3.3 0.5)" "range start 3.3 +-0.5"
ok "$(near "$(js "$FX/colour.json" "d['ranges'][0]['end']")" 5.3 0.5)" "range end 5.3 +-0.5"
ok "$(is "$(js "$FX/colour.json" "d['ranges'][0]['why']")" "['video']")" "colour range is video only"
ok "$(is "$(js "$FX/colour.json" "len(d['per_second'])")" 10)" "per_second has 10 entries"
sheet=$FX/o2/colour.diff.jpg
ok "$(is "$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 "$sheet" 2>/dev/null)" mjpeg)" "sheet written as one jpg"

line=$("$BIN" "$FX/a.mp4" "$FX/colour.mp4" --out "$FX/o2" | head -1)
ok "$( [[ $line =~ ^00:0[34]\.[0-9]–00:0[56]\.[0-9]\ ssim\ 0\.[0-9]{2}$ ]] && echo 1 || echo 0)" "text line '$line'"

MV_VAAPI_DEVICE=/nonexistent "$BIN" "$FX/a.mp4" "$FX/colour.mp4" --json --out "$FX/o3" >"$FX/sw.json"
ok "$(is "$(js "$FX/sw.json" "[(r['start'], r['end']) for r in d['ranges']]")" \
  "$(js "$FX/colour.json" "[(r['start'], r['end']) for r in d['ranges']]")")" "software decode path gives the same range"

"$BIN" "$FX/a.mp4" "$FX/loud.mp4" --json --out "$FX/o4" >"$FX/loud.json"
ok "$(js "$FX/loud.json" "int(len(d['ranges']) == 1 and d['ranges'][0]['why'] == ['audio'] and abs(d['ranges'][0]['start'] - 6) <= 0.5 and abs(d['ranges'][0]['end'] - 7) <= 0.5 and d['ranges'][0]['audio_db'] < -6)")" \
  "+12 dB audio 6-7 s -> 1 audio range, A quieter"

"$BIN" "$FX/a.mp4" "$FX/short.mp4" --json --out "$FX/o5" >"$FX/short.json"
ok "$(js "$FX/short.json" "int(len(d['ranges']) == 1 and 'length' in d['ranges'][0]['why'] and abs(d['ranges'][0]['start'] - 8) <= 0.5 and d['ranges'][0]['end'] == 10)")" \
  "B 2 s shorter -> 1 length range 8-10 s"

"$BIN" "$FX/a.mp4" "$FX/missing.mp4" >/dev/null 2>&1; r=$?
ok "$(is "$r" 2)" "missing input -> rc 2"

echo "mv-diff.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
