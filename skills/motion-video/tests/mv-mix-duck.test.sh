#!/usr/bin/env bash
# mv-mix-duck.test.sh: --duck-on ducks a 220 Hz bed 6-10 dB under a 4 kHz SFX hit / at most depth_db under a 3 kHz game burst and recovers; default stays --duck-on vo.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}' && echo 1 || echo 0; }
le() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<=b)}' && echo 1 || echo 0; }
gen() { ffmpeg -hide_banner -loglevel error -y -f lavfi -i "aevalsrc='$1':s=48000:d=$2" -ac 2 "$3"; }
# Prints the 220 Hz bed level in dB: before the burst (2.0-2.9 s), under it, and 0.45-0.5 s after it ends.
bed_db() {
  ffmpeg -hide_banner -loglevel error -i "$1" -af 'pan=mono|c0=c0' -f f32le - |
    python3 -I -c '
import sys, numpy as np
x = np.frombuffer(sys.stdin.buffer.read(), np.float32).astype(float); sr = 48000
a, b = float(sys.argv[1]), float(sys.argv[2])
def lvl(t0, t1):
    s = x[int(t0 * sr): int(t1 * sr)]; t = np.arange(len(s)) / sr
    amp = 2 * np.hypot((s * np.sin(2 * np.pi * 220 * t)).mean(), (s * np.cos(2 * np.pi * 220 * t)).mean())
    return 20 * np.log10(max(amp, 1e-9))
print(f"{lvl(2.0, 2.9):.2f} {lvl(a + 0.1, b - 0.05):.2f} {lvl(b + 0.45, b + 0.5):.2f}")
' "$2" "$3"
}

gen '0.5*sin(2*PI*220*t)' 6 "$FX/bed.wav"
gen '0.8*sin(2*PI*4000*t)' 0.4 "$FX/hit.wav"
gen '0.5*sin(2*PI*3000*t)*between(t,1,1.4)' 3 "$FX/burst.wav"
mix() { "$BIN/mv-mix" --out "$FX/$1.wav" --duration 8 --music "$FX/bed.wav" "${@:2}" >/dev/null 2>&1; echo $?; }

ok "$(is "$(mix flat --sfx "$FX/hit.wav@3")" 0)" "no duck: SFX hit over the bed -> rc 0"
ok "$(is "$(mix sfx --sfx "$FX/hit.wav@3" --duck-on sfx)" 0)" "--duck-on sfx -> rc 0"
read -r fb fu fr < <(bed_db "$FX/flat.wav" 3.0 3.4)
read -r db du dr < <(bed_db "$FX/sfx.wav" 3.0 3.4)
drop=$(awk -v a="$db" -v b="$du" -v c="$fb" -v d="$fu" 'BEGIN{printf "%.1f", (a - b) - (c - d)}')
ok "$(( $(ge "$drop" 6) & $(le "$drop" 10) ))" "bed under the SFX hit drops $drop dB vs no-duck (6-10)"
rec=$(awk -v a="$db" -v r="$dr" 'BEGIN{d=a-r; printf "%.2f", d<0?-d:d}')
ok "$(le "$rec" 1)" "bed back within $rec dB of its level 0.5 s after the hit (<= 1)"

ok "$(is "$(mix gm --game "$FX/burst.wav@2" --duck-on game)" 0)" "--duck-on game -> rc 0"
read -r gb gu gr < <(bed_db "$FX/gm.wav" 3.0 3.4)
gdrop=$(awk -v a="$gb" -v b="$gu" 'BEGIN{printf "%.1f", a - b}')
gd=$(jq .duck.game.depth_db "$HERE/../loudness.json")
ok "$(( $(ge "$gdrop" 4) & $(le "$gdrop" "$gd") ))" "bed under the game burst drops $gdrop dB (4-$gd, depth_db)"
ok "$(is "$(mix all --sfx "$FX/hit.wav@3" --game "$FX/burst.wav@2" --duck-on vo,sfx,game)" 0)" "--duck-on vo,sfx,game, no VO -> rc 0"

mix def --sfx "$FX/hit.wav@3" >/dev/null; mix vo --sfx "$FX/hit.wav@3" --duck-on vo >/dev/null
ok "$(cmp -s "$FX/def.wav" "$FX/vo.wav" && echo 1 || echo 0)" "default is byte-identical to --duck-on vo"
ok "$(is "$(rc "$BIN/mv-mix" --out "$FX/x.wav" --duration 8 --music "$FX/bed.wav" --duck-on drums)" 2)" "unknown --duck-on class -> rc 2"
ok "$(is "$(rc "$BIN/mv-mix" --out "$FX/x.wav" --duration 8 --music "$FX/bed.wav" --target duck)" 2)" "--target duck (the duck table) -> rc 2"
echo "mv-mix-duck.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
