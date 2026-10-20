#!/usr/bin/env bash
# mv-mix-fit.test.sh: --fit bars loops and ends a 97 BPM click+kick+pad bed on downbeats; --fit none stays the plain loop.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
# One thread everywhere: a PATH shim adds -threads 1 to every ffmpeg (here and in mv-mix), numpy/essentia get OMP 1.
mkdir "$FX/bin"
printf '#!/usr/bin/env bash\na=(); for x in "$@"; do [[ $x == -i ]] && a+=(-threads 1); a+=("$x"); done\nexec %s -filter_threads 1 -filter_complex_threads 1 "${a[@]:0:${#a[@]}-1}" -threads 1 "${a[@]: -1}"\n' "$(command -v ffmpeg)" >"$FX/bin/ffmpeg"
chmod +x "$FX/bin/ffmpeg"; export PATH=$FX/bin:$PATH OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
le() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<=b)}' && echo 1 || echo 0; }
near() { awk -v a="$1" -v b="$2" -v e="$3" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=e)}' && echo 1 || echo 0; }
bed() {
  local p bar; p=$(echo "60 / 97" | bc -l); bar=$(echo "4 * $p" | bc -l)
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i "aevalsrc='0.5*if(lt(mod(t,$p),0.01),sin(2*PI*1500*t)*exp(-mod(t,$p)*300),0)+0.6*if(lt(mod(t,$bar),0.08),sin(2*PI*55*mod(t,$bar))*exp(-mod(t,$bar)*40),0)+0.12*sin(2*PI*110*t)+0.08*sin(2*PI*165*t)':s=44100:d=$1" "$2"
}
# Prints: beat-interval worst error ms, then per seam "seam dt_ms jump_dbfs", then "end last_down_ms tail_db after_db".
probe() {
  ffmpeg -hide_banner -loglevel error -i "$1" -af 'pan=mono|c0=c0' -f f32le - |
    python3 -I -c '
import sys, numpy as np
x = np.frombuffer(sys.stdin.buffer.read(), np.float32).astype(float); sr = 48000
p = 60 / 97; seams = [float(s) for s in sys.argv[2].split(",") if s]; end = float(sys.argv[1])
d = np.abs(np.diff(x)); thr = 0.05 * d.max(); on = []
for i in np.flatnonzero(d > thr):
    if not on or i - on[-1] > 0.1 * sr: on.append(i)
on = np.array(on) / sr
low = np.convolve(x, np.ones(200) / 200, "same") ** 2
le = np.array([low[int(t * sr): int(t * sr) + 2400].mean() for t in on])
down = on[le > 0.3 * le.max()]
upto = on[(on >= 1) & (on <= end + 0.01)]
print(f"{np.abs(np.diff(upto) - p).max() * 1000:.2f}")
db = lambda v: 20 * np.log10(max(v, 1e-9))
for s in seams:
    w = d[int((s - 0.045) * sr): int((s - 0.0005) * sr)]
    print(f"{s} {(down[np.argmin(np.abs(down - s))] - s) * 1000:.2f} {db(w.max()):.1f}")
rms = lambda a, b: db(np.sqrt((x[int(a * sr): int(b * sr)] ** 2).mean()))
print(f"end {(down[-1] - end) * 1000:.2f} {rms(end + 0.1, end + 0.5):.1f} {rms(end + 1.51, len(x) / sr):.1f}")
' "$2" "$3"
}

bed 21.13 "$FX/bed.wav"
VENV=${MV_BEATS_VENV:-$HOME/.local/opt/mv-beats}
if [[ -x $VENV/bin/python ]]; then
  log=$("$BIN/mv-mix" --out "$FX/bars.wav" --duration 40 --music "$FX/bed.wav" --fit bars 2>&1); r=$?
  ok "$(is "$r" 0)" "mv-mix --fit bars on a 21.13 s 97 BPM bed -> rc 0"
  seams=$(sed -n 's/.* seams=\([^ ]*\).*/\1/p' <<<"$log"); end=$(sed -n 's/.* end=\([^ ]*\).*/\1/p' <<<"$log")
  bars=$(sed -n 's/.* bars=\([0-9]*\).*/\1/p' <<<"$log")
  ok "$( [[ $bars -ge 4 && $(tr , '\n' <<<"$seams" | wc -l) -eq 3 ]] && echo 1 || echo 0)" "loop of $bars bars, seams $seams"
  out=$(probe "$FX/bars.wav" "$end" "$seams")
  worst=$(sed -n 1p <<<"$out")
  ok "$(le "$worst" 5)" "groove unbroken to the end: worst beat interval error ${worst} ms (<= 5)"
  while read -r s dt jump; do
    ok "$(near "$dt" 0 5)" "seam $s lands ${dt} ms from a downbeat (<= 5)"
    ok "$(le "$jump" -30)" "seam $s largest sample step ${jump} dBFS (<= -30)"
  done < <(sed -n '2,/^end/p' <<<"$out" | grep -v '^end')
  read -r _ edt tail after < <(grep '^end' <<<"$out")
  ok "$(near "$edt" 0 5)" "last downbeat ${edt} ms from end=$end (<= 5)"
  ok "$( [[ $(le "$(echo "$end + 1.5" | bc)" 40) == 1 && $(le -40 "$tail") == 1 && $(le "$after" -80) == 1 ]] && echo 1 || echo 0)" \
    "release tail ${tail} dBFS after the last downbeat, ${after} dBFS after 1.5 s, ends by 40 s"
  ok "$(is "$(ffprobe -v error -show_entries stream=duration_ts -of csv=p=0 "$FX/bars.wav")" 1920000)" "mix is exactly 40 s at 48 kHz"
  i=$(ffmpeg -hide_banner -nostats -i "$FX/bars.wav" -af ebur128 -f null - 2>&1 | awk '/I:/{v=$2} END{print v}')
  ok "$(near "$i" "$(jq .web.I "$HERE/../loudness.json")" 0.5)" "--fit bars still lands the web target: I $i LUFS"
else
  echo "SKIP needs mv-beats (essentia venv at $VENV): --fit bars cases"
fi

# 25 s is enough to cross the 21.13 s loop seam; loudnorm's true-peak pass costs ~1 CPU s per 20 s of mix.
"$BIN/mv-mix" --out "$FX/none.wav" --duration 25 --music "$FX/bed.wav" --fit none >/dev/null 2>&1
"$BIN/mv-mix" --out "$FX/plain.wav" --duration 25 --music "$FX/bed.wav" >/dev/null 2>&1
ok "$(is "$(md5sum <"$FX/none.wav")" "$(md5sum <"$FX/plain.wav")")" "--fit none is byte-identical to the default mix"
nw=$(probe "$FX/none.wav" 23 21.13 | sed -n 1p)
ok "$( [[ $(le "$nw" 5) == 0 ]] && echo 1 || echo 0)" "fixture check: --fit none breaks the groove at 21.13 s (${nw} ms)"

bed 7 "$FX/short.wav"
[[ -x $VENV/bin/python ]] && ok "$(is "$(rc "$BIN/mv-mix" --out "$FX/s.wav" --duration 20 --music "$FX/short.wav" --fit bars)" 1)" "bed under 4 bars -> rc 1"
ok "$(is "$(rc "$BIN/mv-mix" --out "$FX/s.wav" --duration 20 --music "$FX/bed.wav" --fit beats)" 2)" "unknown --fit -> rc 2"

echo "mv-mix-fit.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
