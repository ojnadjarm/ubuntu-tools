#!/usr/bin/env bash
# mv-scopes.test.sh: legal-range levels and scopes in mv-review, the limiter in mv-encode; lavfi fixtures created here and deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-scopes-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
# Every ffmpeg (here, in mv-review and in mv-encode) runs single-threaded: a PATH shim adds -threads 1 and x265 pools=1.
mkdir "$FX/bin"
printf '#!/usr/bin/env bash\na=(); for x in "$@"; do [[ $x == -i ]] && a+=(-threads 1); [[ ${p-} == -x265-params ]] && x+=:pools=1:frame-threads=1; a+=("$x"); p=$x; done\nexec %s -filter_threads 1 -filter_complex_threads 1 "${a[@]:0:${#a[@]}-1}" -threads 1 "${a[@]: -1}"\n' "$(command -v ffmpeg)" >"$FX/bin/ffmpeg"
chmod +x "$FX/bin/ffmpeg"; export PATH=$FX/bin:$PATH OMP_NUM_THREADS=1
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
js() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
yrange() { ffmpeg -hide_banner -nostats -i "$1" -vf "signalstats,metadata=print:file=-" -f null - 2>/dev/null |
  awk -F= '/YMIN/{if(mn==""||$2+0<mn)mn=$2+0} /YMAX/{if($2+0>mx)mx=$2+0} END{print mn, mx}'; }

ff -f lavfi -i "testsrc2=s=640x360:r=30:d=1" -f lavfi -i "color=c=white:s=100x360:r=30:d=1" -f lavfi -i "sine=f=440:d=1:sample_rate=48000" \
  -filter_complex "[0:v]format=yuv420p[b];[1:v]format=yuv420p,lutyuv=y=255[w];[b][w]overlay=x=0:y=0:format=yuv420,setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709[v]" \
  -map "[v]" -map 2:a -c:v libx264 -preset ultrafast -c:a aac "$FX/hot.mp4"
read -r lo hi < <(yrange "$FX/hot.mp4")
ok "$( [[ $hi -gt 235 ]] && echo 1 || echo 0)" "fixture has super-white bars (Y $lo-$hi)"

"$BIN/mv-review" "$FX/hot.mp4" --out "$FX/r0" --scopes >"$FX/r0.log" 2>&1; r=$?
J=$FX/r0/hot.review.json
ok "$( [[ $r == 1 && $(js "$J" "any(f.startswith('levels') for f in d['fails'])") == True ]] && echo 1 || echo 0)" "super-white fixture -> FAIL on levels (rc $r)"
ok "$(js "$J" "int(d['levels']['ymax'] > 235 and d['levels']['brng_max'] > 0.001)")" "review.json levels $(js "$J" "d['levels']")"
S=$FX/r0/hot.scopes.png
ok "$( [[ -s $S && $(js "$J" "d['scopes']") == "$S" ]] && echo 1 || echo 0)" "--scopes writes hot.scopes.png next to the sheet"
ok "$( [[ $(ffprobe -v error -show_entries stream=height -of csv=p=0 "$S" 2>/dev/null) -ge 256 ]] && echo 1 || echo 0)" "scopes strip holds the waveform + vectorscope (>= 256 px tall)"

"$BIN/mv-encode" "$FX/hot.mp4" "$FX/fixed.mp4" --preset h264-web --loudnorm >/dev/null 2>&1
"$BIN/mv-review" "$FX/fixed.mp4" --out "$FX/r1" >"$FX/r1.log" 2>&1; r=$?
ok "$( [[ $r == 0 ]] && echo 1 || echo 0)" "after mv-encode -> PASS ($(tail -c 300 "$FX/r1.log" | grep -o 'PASS\|FAIL[^|]*' | head -1))"
read -r lo hi < <(yrange "$FX/fixed.mp4")
ok "$( [[ $lo -ge 12 && $hi -le 240 ]] && echo 1 || echo 0)" "8-bit encode clamps Y to 16-235 +- codec ringing, unclamped bars are 255 (Y $lo-$hi)"
ok "$( [[ ! -e $FX/r1/fixed.scopes.png && $(js "$FX/r1/fixed.review.json" "'scopes' in d") == False ]] && echo 1 || echo 0)" "no scopes without --scopes"

ff -i "$FX/hot.mp4" -t 0.5 -c copy "$FX/hot05.mp4"   # x265 slow costs ~1 CPU s per 5 frames: a 15-frame cut
"$BIN/mv-encode" "$FX/hot05.mp4" "$FX/fixed10.mp4" --preset hevc-10 >/dev/null 2>&1
"$BIN/mv-review" "$FX/fixed10.mp4" --out "$FX/r2" >/dev/null 2>&1
J=$FX/r2/fixed10.review.json
ok "$(js "$J" "int(d['levels']['brng_max'] <= 0.001 and not any(f.startswith('levels') for f in d['fails']))")" "10-bit encode passes the levels check $(js "$J" "d['levels']")"
read -r lo hi < <(yrange "$FX/fixed10.mp4")
ok "$( [[ $lo -ge 56 && $hi -le 980 ]] && echo 1 || echo 0)" "10-bit encode clamps Y to 64-940 +- codec ringing, unclamped bars are 1020 (Y $lo-$hi)"

echo "mv-scopes.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
