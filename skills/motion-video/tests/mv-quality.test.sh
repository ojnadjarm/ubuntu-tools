#!/usr/bin/env bash
# mv-quality.test.sh: mv-quality on a 1 s 320x180 testsrc2 BT.709 master; fixtures are created here and deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts/mv-quality
ENC=$HERE/../scripts/mv-encode
VMAF=${MV_VMAF:-$HOME/.local/opt/mv-quality/vmaf}
[[ -x $VMAF ]] || { echo "SKIP needs vmaf (Netflix vmaf CLI) at $VMAF"; exit 0; }
# One vmaf thread and one BLAS thread: numpy's OpenBLAS pool alone costs ~1 cpu s per import.
export MV_VMAF_THREADS=1 OMP_NUM_THREADS=1
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-quality-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
js() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
tags=(-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv)
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
enc() { ff -i "$FX/ref.mkv" -c:v libx264 -preset medium -crf "$1" -pix_fmt yuv420p "${tags[@]}" "$FX/crf$1.mp4"; }

ff -f lavfi -i testsrc2=s=320x180:r=30:d=1 -vf scale=out_color_matrix=bt709:out_range=tv,format=yuv420p \
  "${tags[@]}" -c:v ffv1 "$FX/ref.mkv"
enc 18
enc 40
ff -f lavfi -i testsrc2=s=320x180:r=30:d=1 -vf format=yuv420p -c:v ffv1 "$FX/untagged.mkv"
ok "$( [[ -s $FX/ref.mkv && -s $FX/crf18.mp4 && -s $FX/crf40.mp4 && -s $FX/untagged.mkv ]] && echo 1 || echo 0)" "fixtures generated"

ok "$("$BIN" -h >/dev/null 2>&1 && echo 1 || echo 0)" "-h rc 0"

"$BIN" "$FX/ref.mkv" "$FX/ref.mkv" --json >"$FX/id.json"; r=$?
ok "$(js "$FX/id.json" "int(abs(d['vmaf'] - 100) <= 0.5)")" "identity vmaf $(js "$FX/id.json" "d['vmaf']") = 100 +-0.5"
ok "$(is "$r" 0)" "identity rc 0"

"$BIN" "$FX/untagged.mkv" "$FX/untagged.mkv" --json >"$FX/uid.json"
ok "$(js "$FX/uid.json" "int(abs(d['vmaf'] - 100) <= 0.5)")" "untagged identity vmaf $(js "$FX/uid.json" "d['vmaf']") = 100 +-0.5"

"$BIN" "$FX/ref.mkv" "$FX/crf18.mp4" --json >"$FX/18.json"; r=$?
ok "$(js "$FX/18.json" "int(d['vmaf'] >= 95)")" "crf 18 vmaf $(js "$FX/18.json" "d['vmaf']") >= 95"
ok "$(js "$FX/18.json" "int(d['vmaf_1pct_low'] <= d['vmaf'] and d['min_second']['vmaf'] <= d['vmaf'] and d['psnr_y'] > 40 and d['ssim'] > 0.99 and d['frames'] == 30)")" \
  "crf 18 json: 1% low, worst second, psnr-y, ssim, 30 frames"
ok "$(is "$r" 0)" "crf 18 rc 0"

"$BIN" "$FX/ref.mkv" "$FX/crf40.mp4" --json --sheet "$FX/worst.jpg" >"$FX/40.json"; r=$?
ok "$(js "$FX/40.json" "int(d['vmaf'] < 80)")" "crf 40 vmaf $(js "$FX/40.json" "d['vmaf']") < 80"
ok "$(is "$r" 1)" "crf 40 below --min-vmaf 93 -> rc 1"
ok "$(is "$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 "$FX/worst.jpg" 2>/dev/null)" mjpeg)" "worst-frame sheet is one jpg"
"$BIN" "$FX/ref.mkv" "$FX/crf40.mp4" --min-vmaf 60 >/dev/null; r=$?
ok "$(is "$r" 0)" "crf 40 with --min-vmaf 60 -> rc 0"

ok "$(js "$FX/18.json" "int(d['subsample'] == 1)")" "30 frames -> auto subsample 1"
"$BIN" "$FX/ref.mkv" "$FX/crf18.mp4" --json --subsample 3 >"$FX/18s3.json"
ok "$(python3 -c "import json; a, b = (json.load(open(f)) for f in ('$FX/18.json', '$FX/18s3.json')); print(int(b['subsample'] == 3 and b['frames'] == 10 and len(b['per_second']) == 1 and abs(a['vmaf'] - b['vmaf']) <= 1 and b['vmaf_1pct_low'] <= b['vmaf']))")" \
  "--subsample 3: 10 frames, 1 second, vmaf $(js "$FX/18s3.json" "d['vmaf']") within 1 of full"
MV_VMAF_SUBSAMPLE=5 "$BIN" "$FX/ref.mkv" "$FX/crf40.mp4" --json --sheet "$FX/w5.jpg" >"$FX/40s5.json"
ok "$(js "$FX/40s5.json" "int(d['subsample'] == 5 and d['frames'] == 6)")" "MV_VMAF_SUBSAMPLE=5: 6 frames"
ok "$(is "$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 "$FX/w5.jpg" 2>/dev/null)" mjpeg)" "subsampled worst-frame sheet is one jpg"
ok "$(python3 -c "
import sys; sys.path.insert(0, '$HERE/../scripts')
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('mvq', '$BIN').load_module()
r = lambda s, f: {'duration': s, 'rate': f}
print(int([m.subsample(None, r(10, 60)), m.subsample(None, r(30, 60)), m.subsample(None, r(30.02, 60)), m.subsample(4, r(30, 60))] == [1, 3, 4, 4]))
" 2>/dev/null)" "auto: 600 frames -> 1, 1800 -> 3, 1801 -> 4; --subsample wins"

"$BIN" "$FX/ref.mkv" "$FX/missing.mp4" >/dev/null 2>&1; r=$?
ok "$(is "$r" 2)" "missing input -> rc 2"

"$BIN" --search "$FX/ref.mkv" --preset h264-web --target 95 --json >"$FX/s.json" 2>/dev/null; r=$?
ok "$(is "$r" 0)" "search rc 0, best crf $(js "$FX/s.json" "d['best'] and d['best']['crf']")"
ok "$(js "$FX/s.json" "int(len(d['steps']) <= 5 and d['best']['vmaf'] >= 95 and d['best']['bytes'] > 0)")" "search <= 5 encodes, best meets 95, has size"
# Brute force on a 5-point sweep best-1..best+3; points the search already encoded are reused (encodes are deterministic).
best=$(js "$FX/s.json" "d['best']['crf']")
sweep=()
for c in $(seq $((best - 1)) $((best + 3))); do
  v=$(js "$FX/s.json" "next((s['vmaf'] for s in d['steps'] if s['crf'] == $c), '')")
  if [[ -z $v ]]; then
    "$ENC" "$FX/ref.mkv" "$FX/b$c.mp4" --preset h264-web --crf "$c" >/dev/null
    v=$("$BIN" "$FX/ref.mkv" "$FX/b$c.mp4" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['vmaf'])")
  fi
  sweep+=("$c:$v")
done
brute=$(printf '%s\n' "${sweep[@]}" | awk -F: '$2 >= 95 {c = $1} END {print c + 0}')
ok "$( (( brute >= best - 2 && brute <= best + 2 )) && echo 1 || echo 0)" "search crf $best within +-2 of brute force $brute (sweep ${sweep[*]})"

echo "mv-quality.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
