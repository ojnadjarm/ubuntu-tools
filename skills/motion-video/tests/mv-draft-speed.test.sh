#!/usr/bin/env bash
# mv-draft-speed.test.sh: shot.py --draft knobs (look off, 8-bit, shadow pool 16, persistent data), final knobs unchanged, render.json stage split, 12 draft frames at 320x180 mean <= 0.2 s (quiet machine).
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
knobs() { MV_DRAFT=$1 MV_LOOK=filmic MV_DEPTH=16 MV_FPS=1 MV_SECONDS=1 MV_SIZE=64x64 blender -b --factory-startup --python-expr 'import bpy
from bpy.app.handlers import persistent
@persistent
def dump(s, *_):
    e, r = s.eevee, s.render
    print("KNOBS", e.shadow_pool_size, e.shadow_resolution_scale, e.shadow_ray_count, e.shadow_step_count, e.volumetric_samples,
          r.use_persistent_data, r.image_settings.color_depth, r.resolution_percentage, s.compositing_node_group is not None, flush=True)
bpy.app.handlers.render_pre.append(dump)' -P "$SHOT" -- "$FX/k$1/frame_" 2>&1 | awk '/^KNOBS/ {$1 = ""; print substr($0, 2); exit}'; }

ok "$(is "$(knobs 0)" "512 1.0 1 6 64 False 16 100 True")" "final knobs unchanged: pool 512, shadow res 1.0, 6 steps, 64 volume samples, no persistent data, 16-bit, look on"
ok "$(is "$(knobs 1)" "16 0.25 1 1 1 True 8 50 False")" "draft knobs: pool 16, shadow res 0.25, floor samples, persistent data, 8-bit, look off"

if ! quiet-gate --max-load1 "${MAX_LOAD1:-}" --max-per-cpu "${MAX_PER_CPU:-0.25}" --gpu --wait "${GATE_WAIT:-300}" >/dev/null; then
  echo "SKIP draft speed: machine busy (load $(cut -d' ' -f1 /proc/loadavg))"
  echo "mv-draft-speed: $((n - bad))/$n passed"
  [[ $bad == 0 ]]; exit
fi
MV_LOOK=filmic MV_DEPTH=16 MV_FPS=12 MV_SECONDS=1 MV_SIZE=640x360 nice -n 10 "$MV" blender "$SHOT" "$FX/d" --draft >/dev/null 2>&1
read -r frames size bits mean f1 rs cs ws < <(python3 -I - "$FX/d" <<'PY'
import json, subprocess, sys
d = sys.argv[1]
j = json.load(open(f"{d}/render.json"))
size = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=width,height", "-of", "csv=p=0", f"{d}/frame_0001.png"], capture_output=True, text=True).stdout.strip()
print(j["rendered"], size, j["bit_depth"], j["mean_s"], j["per_frame_s"]["1"], j["render_s"], j["composite_s"], j["write_s"])
PY
)
ok "$(is "${frames:-0} ${size:-} ${bits:-}" "12 320,180 8")" "12 draft frames, 320x180, 8-bit"
ok "$(echo "${rs:-0} > 0 && ${cs:--1} >= 0 && ${ws:--1} >= 0 && ${rs:-0} + ${cs:-0} + ${ws:-0} <= ${mean:-0} + 0.01" | bc)" "render.json stage split render_s $rs composite_s $cs write_s $ws (sum <= mean)"
ok "$(echo "${mean:-9} <= 0.2" | bc)" "draft mean ${mean} s per frame <= 0.2 (frame 1 ${f1} s, load $(cut -d' ' -f1 /proc/loadavg))"

echo "mv-draft-speed: $((n - bad))/$n passed"
[[ $bad == 0 ]]
