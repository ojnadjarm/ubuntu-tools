#!/usr/bin/env bash
# mv-look.test.sh: MV_DEPTH 16-bit PNG into mv-encode, vignette and catcher alpha on fixtures/look plates; MV_LOOK_FULL=1 (default on Sundays) renders them plus bloom locality and one chrome sphere.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
ENC=$HERE/../scripts/mv-encode
SHOT=$HERE/../templates/blender/shot.py
L=$HERE/fixtures/look
FULL=${MV_LOOK_FULL:-$([[ $(date +%u) == 7 ]] && echo 1 || echo 0)}
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
shot() { MV_FPS=1 MV_SECONDS=1 MV_SAMPLES=8 MV_SHUTTER=0 MV_SIZE=${MV_SIZE:-320x180} "$MV" blender "$SHOT" "$FX/$1" >/dev/null 2>&1; }
pixfmt() { ffprobe -v error -show_entries stream=pix_fmt -of csv=p=0 "$1"; }
json() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$L/$1.json" "$2"; }

if [[ $FULL != 1 ]]; then
  for f in d16.png d16.json d8.png d8.json vig-soft.png vig-bloom.png catch.png catch-soft.png gr/d{8,16}_000{1,2}.png; do
    [[ -f $L/$f ]] || { echo "fixtures missing: full path"; FULL=1; break; }
  done
fi
if [[ $FULL == 1 ]]; then
  L=$FX/look
  ok "$("$HERE/fixtures/look/make.sh" --into "$L" >/dev/null 2>&1 && echo 1 || echo 0)" "make.sh --into renders the plates"
fi

ok "$(is "$(pixfmt "$L/d16.png") $(json d16 bit_depth)" "rgba64be 16")" "MV_DEPTH default: 16-bit PNG, render.json bit_depth 16"
ok "$(is "$(pixfmt "$L/d8.png") $(json d8 bit_depth)" "rgba 8")" "MV_DEPTH=8: 8-bit PNG, render.json bit_depth 8"

mkdir -p "$FX/gr"
for d in 8 16; do "$ENC" "$L/gr/d${d}_%04d.png" "$FX/gr/e$d.mp4" --fps 2 --preset hevc-10 --finish none >/dev/null 2>&1; done
read -r l8 l16 r8 r16 < <(python3 -I - "$L/gr" "$FX/gr" <<'PY'
import subprocess, sys
import numpy as np
g, d = sys.argv[1:]
def raw(f, pf, dt, vf="null"):
    b = subprocess.check_output(["ffmpeg", "-v", "error", "-i", f, "-vf", vf, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pf, "-"])
    return np.frombuffer(b, dt)[:4096].astype(float)
ideal = raw(f"{g}/d16_0001.png", "yuv420p16le", "<u2", "scale=out_color_matrix=bt709:out_range=tv") / 64
rms = [np.sqrt(((raw(f"{d}/e{b}.mp4", "yuv420p10le", "<u2") - ideal) ** 2).mean()) for b in (8, 16)]
print(len(np.unique(raw(f"{g}/d8_0001.png", "gray", "u1"))), len(np.unique(raw(f"{g}/d16_0001.png", "gray16le", "<u2"))), *(f"{r:.3f}" for r in rms))
PY
)
ok "$(echo "$l16 >= 4 * $l8" | bc)" "64 px gradient: distinct luma levels 16-bit $l16 >= 4 x 8-bit $l8"
ok "$(echo "$r8 >= 1.8 * $r16" | bc)" "mv-encode hevc-10 keeps 16 bit: ramp RMS error 8-bit $r8 >= 1.8 x 16-bit $r16 (10-bit codes)"

read -r corner centre < <(python3 -I - "$L" <<'PY'
import sys
import numpy as np
from PIL import Image
luma = lambda s: np.asarray(Image.open(f"{sys.argv[1]}/vig-{s}.png"), float) / 257
v = luma("soft") / np.maximum(luma("bloom"), 1 / 257)
print(f"{np.mean([v[:8, :8].mean(), v[:8, -8:].mean(), v[-8:, :8].mean(), v[-8:, -8:].mean()]):.3f}", f"{v[40:50, 75:85].mean():.3f}")
PY
)
ok "$(echo "$corner <= 0.97 && $centre >= 0.99 && $centre <= 1.01" | bc)" "vignette darkens corners x$corner, centre x$centre"

ok "$(is "$(pixfmt "$L/catch-soft.png")" rgba64be)" "catcher + look: RGBA 16-bit PNG"
da=$(python3 -I -c 'import sys, numpy as np; from PIL import Image
a, b = (np.asarray(Image.open(f).getchannel("A"), float) / 255 for f in sys.argv[1:])
print(f"{np.abs(a - b).max():.3f}")' "$L/catch.png" "$L/catch-soft.png" 2>/dev/null || echo 1)
ok "$(echo "$da <= 0.01" | bc)" "catcher + soft look keeps the catcher alpha (max diff $da)"

if [[ $FULL == 1 ]]; then
  shot none
  MV_RING=0 shot noring
  MV_LOOK=soft MV_VIGNETTE=0 shot bloom
  MV_LOOK=soft MV_VIGNETTE=0 MV_RING=0 shot bloom-noring
  MV_LOOK=filmic MV_VIGNETTE=0 shot filmic
  MV_LOOK=filmic MV_VIGNETTE=0 MV_RING=0 shot filmic-noring
  read -r bnear bfar fnear ffar < <(python3 -I - "$FX" <<'PY'
import subprocess, sys
import numpy as np
from PIL import Image, ImageFilter
d = sys.argv[1]
def luma(name):
    b = subprocess.check_output(["ffmpeg", "-v", "error", "-i", f"{d}/{name}/frame_0001.png", "-f", "rawvideo", "-pix_fmt", "gray16le", "-"])
    return np.frombuffer(b, "<u2").reshape(180, 320).astype(float) / 257
n, r = luma("none"), luma("noring")
ring = np.abs(n - r) > 8
near = np.asarray(Image.fromarray(ring.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(41))) > 0
band, far = near & ~ring, ~near
out = []
for look in ("bloom", "filmic"):
    glow = (luma(look) - luma(f"{look}-noring")) - (n - r)
    out += [f"{glow[band].mean() / n[band].mean() * 100:.2f}", f"{glow[far].mean() / n[far].mean() * 100:.2f}"]
print(*out)
PY
  )
  ok "$(echo "$bnear >= 5 && $bfar <= 1 && $bfar >= -1" | bc)" "soft bloom from the ring: +$bnear % luma within 20 px, $bfar % elsewhere (within 1 %)"
  ok "$(echo "$fnear >= 3 && $ffar <= 1 && $ffar >= -1" | bc)" "filmic fog glow from the ring: +$fnear % luma within 20 px, $ffar % elsewhere (within 1 %)"

  MV_LOOK=bogus shot bogus
  ok "$(is "$(ls "$FX/bogus"/frame_*.png 2>/dev/null | wc -l)" 0)" "MV_LOOK=bogus renders nothing"

  spheres=$(MV_FPS=1 MV_SECONDS=1 MV_SIZE=32x18 blender -b --factory-startup --python-expr 'import bpy
from bpy.app.handlers import persistent
@persistent
def pre(*_): print("chrome", sum(m.users for m in bpy.data.materials if m.name.startswith("Chrome")), flush=True)
bpy.app.handlers.render_pre.append(pre)' -P "$SHOT" -- "$FX/sph/frame_" 2>/dev/null | awk '/^chrome/ {print $2; exit}')
  ok "$(is "$spheres" 1)" "one chrome sphere without a logo (users $spheres)"
fi

echo "mv-look.test: $((n - bad))/$n passed"
exit $((bad > 0))
