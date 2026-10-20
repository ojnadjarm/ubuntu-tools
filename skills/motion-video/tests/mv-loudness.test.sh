#!/usr/bin/env bash
# mv-loudness.test.sh: two-pass linear loudness in mv-mix/mv-encode and loudness.json targets in mv-review, on lavfi fixtures.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
near() { awk -v a="$1" -v b="$2" -v e="$3" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=e)}' && echo 1 || echo 0; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
r128() { ffmpeg -hide_banner -nostats -i "$1" -af ebur128 -f null - 2>&1 | awk '/I:/{i=$2} /LRA:/{r=$2} END{print i, r}'; }

ff -f lavfi -i "sine=f=440:d=40:sample_rate=48000,volume='if(lt(mod(t,10),5),0.2,0.05)':eval=frame" "$FX/range.wav"
ff -f lavfi -i "sine=f=440:d=10:sample_rate=48000,volume='if(between(t,4,4.02),1,0.01)':eval=frame" "$FX/spike.wav"
read -r _ in_lra < <(r128 "$FX/range.wav")
ok "$(near "$in_lra" 12 1)" "fixture has 12 LU of range (LRA $in_lra)"

for t in web youtube broadcast podcast; do
  ti=$(jq -r --arg t "$t" '.[$t].I' "$HERE/../loudness.json")
  log=$("$BIN/mv-mix" --out "$FX/$t.wav" --duration 40 --vo "$FX/range.wav" --target "$t")
  read -r i lra < <(r128 "$FX/$t.wav")
  ok "$( [[ $log == *mode=linear* ]] && echo 1 || echo 0)" "mv-mix --target $t runs linear"
  ok "$(near "$i" "$ti" 0.5)" "mv-mix --target $t lands I $i within 0.5 LU of $ti"
  ok "$(near "$lra" "$in_lra" 1)" "mv-mix --target $t keeps LRA $lra within 1 LU of $in_lra"
done

log=$("$BIN/mv-mix" --out "$FX/spike-out.wav" --duration 10 --vo "$FX/spike.wav" --target youtube); r=$?
ok "$( [[ $r == 0 && $log == *'mode=dynamic (linear gain'*'would put true peak'* ]] && echo 1 || echo 0)" \
  "mv-mix falls back to dynamic when linear gain breaks TP, and says so"
ok "$(is "$(rc "$BIN/mv-mix" --out "$FX/x.wav" --duration 2 --vo "$FX/range.wav" --target nope)" 2)" "mv-mix unknown --target -> rc 2"

ff -f lavfi -i testsrc2=s=320x240:r=30:d=4 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$FX/clip.mp4"
ff -i "$FX/range.wav" -t 4 "$FX/a4.wav"
"$BIN/mv-encode" "$FX/clip.mp4" "$FX/b.mp4" --preset h264-web --audio "$FX/a4.wav" --target broadcast >/dev/null
read -r i _ < <(r128 "$FX/b.mp4")
ok "$(near "$i" -23 0.5)" "mv-encode --target broadcast lands $i LUFS within 0.5 of -23"
"$BIN/mv-review" "$FX/b.mp4" --out "$FX/rev" --target web >"$FX/rev.log" 2>&1; r=$?
ok "$( [[ $r == 1 ]] && grep -q 'FAIL loudness' "$FX/rev.log" && echo 1 || echo 0)" "mv-review FAILs a -23 file against --target web"
ok "$(is "$(rc "$BIN/mv-review" "$FX/b.mp4" --out "$FX/rev" --target broadcast)" 0)" "mv-review PASSes it against --target broadcast"

echo "mv-loudness.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
