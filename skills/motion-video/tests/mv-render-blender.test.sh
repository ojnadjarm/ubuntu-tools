#!/usr/bin/env bash
# mv-render-blender.test.sh: draft size, resume skip time, render.json, MV_SHUTTER motion blur (EEVEE), MV_HDRI lighting and MV_GROUND=catcher (EEVEE) of mv-render blender at 160x90 in Cycles. Asserts on fixtures/plates/mv-render-blender (make.sh); Blender renders them on MV_BLENDER_FULL=1, Sundays or a stale/missing fixture.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
# One OpenMP/BLAS thread per Blender (the default pool costs ~1 cpu s per process); Cycles CPU at 4 spp skips EEVEE's GPU init, the 180° shutter pair (noise-free edges), the HDRI case (Cycles builds a costly world map) and the EEVEE-only shadow-catcher compositor keep EEVEE.
export OMP_NUM_THREADS=1 MV_ENGINE=CYCLES
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
js() { python3 -I -c 'import json, sys; r = eval(sys.argv[2], {}, json.load(open(sys.argv[1]))); print(*r if isinstance(r, tuple) else [r])' "$P/$1.json" "$2"; }
size() { ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$1"; }
render() { MV_FPS=3 MV_SECONDS=1 MV_SIZE=320x180 "$MV" blender "$SHOT" "$FX/f" "$@" >/dev/null 2>&1; }

blur() { MV_FPS=2 MV_SECONDS=1 MV_SIZE=$1 MV_SAMPLES=4 "$MV" blender "$SHOT" "$FX/$2" "${@:3}" >/dev/null 2>&1; }
. "$HERE/fixtures/plates/plates.sh"
plates mv-render-blender
if ((BL)); then
  render --draft
  ls "$FX/f"/frame_*.png 2>/dev/null | wc -l >"$P/draft-frames"
  size "$FX/f/frame_0001.png" >"$P/draft-size"
  cp "$FX/f/render.json" "$P/draft.json"
  m1=$(stat -c %Y "$FX/f/frame_0001.png")
  t=$(date +%s.%N)
  render --resume
  echo "$(date +%s.%N) - $t" | bc >"$P/resume-s"
  cp "$FX/f/render.json" "$P/resume.json"
  echo "$m1 $(stat -c %Y "$FX/f/frame_0001.png")" >"$P/mtimes"
  : >"$FX/f/frame_0002.png"
  render --resume --draft
  cp "$FX/f/render.json" "$P/redo.json"
  size "$FX/f/frame_0002.png" >"$P/redo-size"
  # The 3-frame draft in f ran at the default MV_SHUTTER=0.5; frames 1 and 3 were never re-rendered.
  MV_SHUTTER=0 MV_FPS=3 MV_SECONDS=1 MV_SIZE=320x180 "$MV" blender "$SHOT" "$FX/draft0" --draft >/dev/null 2>&1
  MV_ENGINE=EEVEE blur 160x90 on
  MV_ENGINE=EEVEE MV_SHUTTER=0 blur 160x90 zero
  python3 -I -c 'import struct, sys; sys.stdout.buffer.write(struct.pack("<6f", 1.6, 1.6, 0.25, 0.25, 4.0, 4.0))' |
    ffmpeg -v error -y -f rawvideo -pix_fmt gbrpf32le -s 2x1 -i - -c:v exr "$FX/orange.exr"
  MV_ENGINE=EEVEE MV_HDRI=$FX/orange.exr blur 320x180 hdri --draft
  MV_ENGINE=EEVEE MV_GROUND=catcher blur 320x180 catch --draft
  for f in f/frame_0001 f/frame_0003 draft0/frame_0001 draft0/frame_0003 zero/frame_0002 on/frame_0002; do keep "$FX/$f.png" "$P/$f.png" L; done
  for f in zero/frame_0001 hdri/frame_0001; do keep "$FX/$f.png" "$P/$f.png" RGB; done
  keep "$FX/catch/frame_0001.png" "$P/catch/frame_0001.png" A
fi

ok "$(is "$(val draft-frames)" 3)" "draft renders 3 frames"
ok "$(is "$(val draft-size)" 160,90)" "draft is 50 % size (160x90)"
ok "$(is "$(js draft 'rendered, len(per_frame_s), draft')" '3 3 True')" "render.json: 3 rendered, 3 per-frame times, draft"
ok "$(is "$(js draft 'p95_s == max(per_frame_s.values()) > 0')" True)" "render.json p95 (3 frames = slowest)"

secs=$(val resume-s)
if ((BL)); then
  lim=$(bash ~/agents/bin/tests/lib/budget.sh 3)
  ok "$(echo "${secs:-999} < $lim" | bc)" "resume of 3 frames on disk < $lim s (${secs%???????} s)"
else
  echo "note: resume of 3 frames on disk ${secs%???????} s recorded $(awk '$1 == "made" { print $2 }' "$P/manifest"), measured only when BL=1"
fi
ok "$(is "$(js resume 'rendered, skipped')" '0 3')" "resume renders 0, skips 3"
read -r m1 m2 < <(val mtimes)
ok "$([[ -n ${m1:-} && $m1 == "${m2:-}" ]] && echo 1 || echo 0)" "resume leaves frames untouched"

ok "$(is "$(js redo '(rendered, *per_frame_s)')" '1 2')" "resume re-renders only the empty placeholder frame 2"
ok "$(is "$(val redo-size)" 160,90)" "re-rendered frame 2 is a 160x90 PNG"

sobel() { python3 -I - "$@" <<'PY'
import sys
import numpy as np
from PIL import Image
for f in sys.argv[1:]:
    a = np.asarray(Image.open(f).convert("L"), float)
    g = np.hypot(a[1:-1, 2:] - a[1:-1, :-2], a[2:, 1:-1] - a[:-2, 1:-1])
    print(f"{g.mean():.3f} {(g > 4).mean():.4f}")
PY
}
ok "$(is "$(sobel "$P"/f/frame_000[13].png)" "$(sobel "$P"/draft0/frame_000[13].png)")" "--draft with MV_SHUTTER=0.5 matches MV_SHUTTER=0 (blur off)"
read -r m0 w0 m1 w1 < <(sobel "$P/zero/frame_0002.png" "$P/on/frame_0002.png" | tr '\n' ' ')
ok "$(echo "${w1:-0} > ${w0:-0} && ${m1:-0} < ${m0:-0}" | bc)" "180° shutter widens edges (edge band $w0 -> $w1, Sobel mean $m0 -> $m1)"

warm() { python3 -I -c 'import sys, numpy as np; from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("RGB"), float)[30:70, 40:120]
print(f"{(a[..., 0] - a[..., 2]).mean():.1f}")' "$1"; }
w0=$(warm "$P/zero/frame_0001.png") w1=$(warm "$P/hdri/frame_0001.png")
ok "$(echo "${w1:-0} > ${w0:-0} + 20" | bc)" "orange 2x1 EXR HDRI warms the blocks (mean R-B $w0 -> $w1)"
read -r under floor solid < <(python3 -I -c 'import sys, numpy as np; from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("L"), float) / 255
under = 0
for c in a.T:
    rows = np.flatnonzero(c > 0.98)
    band = c[rows[-1] + 1:rows[-1] + 7] if rows.size else c[:0]
    under += bool(((band > 0.1) & (band < 0.98)).any())
print(under, f"{a[int(len(a) * 0.8):].max():.2f}", f"{(a > 0.98).mean():.2f}")' "$P/catch/frame_0001.png")
ok "$(echo "${under:-0} >= 20 && ${floor:-1} < 0.05 && ${solid:-0} > 0.05" | bc)" "catcher: shadow alpha under $under block columns, far floor alpha $floor, objects opaque $solid"

echo "mv-render-blender.test: $((n - bad))/$n passed"
exit $((bad > 0))
