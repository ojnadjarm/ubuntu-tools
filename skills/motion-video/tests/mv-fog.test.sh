#!/usr/bin/env bash
# mv-fog.test.sh: shot.py MV_FOG=0 pixel-identical to unset, MV_FOG haze + shaft edge in the sky band (flat without), draft fog <= 1.3 x fog-off s/frame (quiet machine).
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
export OMP_NUM_THREADS=1
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
shot() { MV_RING=0 MV_FPS=1 MV_SECONDS=1 MV_SAMPLES=8 MV_SHUTTER=0 MV_SIZE=320x180 nice -n 10 "$MV" blender "$SHOT" "$FX/$1" >/dev/null 2>"$FX/$1.err"; }
pixels() { ffmpeg -v error -i "$FX/$1/frame_0001.png" -f rawvideo -pix_fmt rgba64le - | md5sum | cut -d' ' -f1; }

command -v blender >/dev/null || { echo "SKIP mv-fog: no blender on PATH"; exit 0; }
shot unset
MV_FOG=0 shot zero
MV_FOG=0.02 shot fog
for p in unset zero fog; do
  [[ -s $FX/$p/frame_0001.png ]] && continue
  head=$(head -c 300 "$FX/$p.err" | tr '\n' ' ')
  if grep -qE 'Error (creating|enabling) GPU context|Failed to create (display|headless) GPU context|EGL Error|No active GPU context|Unable to open a display|Unable to initialize (GHOST|a Vulkan)' "$FX/$p.err"; then echo "SKIP mv-fog: Blender cannot open a GPU/EEVEE context: $head"; exit 0; fi
  echo "FAIL plate wrote no frames: $head"; exit 1
done
ok "$(is "$(pixels zero)" "$(pixels unset)")" "MV_FOG=0 pixels identical to MV_FOG unset"

read -r grad_off grad_fog lift < <(python3 -I - "$FX" <<'PY'
import subprocess, sys
import numpy as np
d = sys.argv[1]
def sky(name):
    """Luma (0-255) of the top quarter, above the hero."""
    b = subprocess.check_output(["ffmpeg", "-v", "error", "-i", f"{d}/{name}/frame_0001.png", "-f", "rawvideo", "-pix_fmt", "gray16le", "-"])
    y = np.frombuffer(b, "<u2").reshape(180, 320).astype(float) / 257
    return y[:45]
def grad(y):
    """Largest step over 16 px of the 9 px smoothed column profile."""
    p = np.convolve(y.mean(axis=0), np.ones(9) / 9, "valid")
    return np.abs(p[16:] - p[:-16]).max()
off, fog = sky("unset"), sky("fog")
print(f"{grad(off):.2f} {grad(fog):.2f} {fog.mean() - off.mean():.2f}")
PY
)
ok "$(echo "${grad_off:-99} <= 3" | bc)" "fog off: sky band flat, max 16 px luma step $grad_off <= 3"
ok "$(echo "${grad_fog:-0} >= 20" | bc)" "MV_FOG=0.02: shaft edge in the sky band, max 16 px luma step $grad_fog >= 20"
ok "$(echo "${lift:-0} >= 30" | bc)" "MV_FOG=0.02: haze lifts the sky band +$lift luma"

knobs=$(MV_FOG=0.02 MV_DRAFT=1 MV_FPS=1 MV_SECONDS=1 MV_SIZE=64x36 blender -b --factory-startup --python-expr 'import bpy
from bpy.app.handlers import persistent
@persistent
def dump(s, *_):
    spot = [o.data for o in s.objects if o.type == "LIGHT" and o.data.type == "SPOT"]
    print("KNOBS", s.world.node_tree.nodes["World Output"].inputs["Volume"].is_linked, s.eevee.volumetric_samples, s.eevee.volumetric_tile_size,
          len(spot), spot[0].diffuse_factor if spot else "-", flush=True)
bpy.app.handlers.render_pre.append(dump)' -P "$SHOT" -- "$FX/k/frame_" 2>&1 | awk '/^KNOBS/ {$1 = ""; print substr($0, 2); exit}')
ok "$(is "$knobs" "True 64 4 1 0.0")" "draft fog knobs: world volume linked, 64 volume samples, tile 4, one volume-only spot ($knobs)"

if ! quiet-gate --max-load1 "${MAX_LOAD1:-}" --max-per-cpu "${MAX_PER_CPU:-0.5}" --gpu --wait "${GATE_WAIT:-120}" >/dev/null; then
  echo "SKIP draft fog speed: machine busy (load $(cut -d' ' -f1 /proc/loadavg))"
else
  draft() { MV_FOG=$1 MV_FPS=12 MV_SECONDS=1 MV_SIZE=640x360 nice -n 10 "$MV" blender "$SHOT" "$FX/d$1-$2" --draft >/dev/null 2>&1
    python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["mean_s"])' "$FX/d$1-$2/render.json"; }
  off=() on=()
  for i in 1 2 3; do off+=("$(draft 0 "$i")"); on+=("$(draft 0.02 "$i")"); done
  moff=$(printf '%s\n' "${off[@]}" | sort -g | sed -n 2p) mon=$(printf '%s\n' "${on[@]}" | sort -g | sed -n 2p)
  ok "$(echo "${mon:-9} <= 1.3 * ${moff:-0}" | bc)" "draft median s/frame fog $mon <= 1.3 x fog-off $moff (3 interleaved pairs, load $(cut -d' ' -f1 /proc/loadavg))"
fi

echo "mv-fog.test: $((n - bad))/$n passed"
exit $((bad > 0))
