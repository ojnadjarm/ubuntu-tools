#!/usr/bin/env bash
# mv-model-anim.test.sh: MV_MODEL_ANIM plays a glTF clip of the hero on a looping NLA strip whose loop ends on the cue (MV_MODEL_ANIM_SPEED), rest pose without the knob; draft render: the bone-bent hero differs from the static one at the bend peak, not at frame 1. Asserts on fixtures/plates/mv-model-anim (make.sh); Blender renders them on MV_BLENDER_FULL=1, Sundays or a stale/missing fixture.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
GLB=$HERE/fixtures/anim-hero.glb
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }

echo '{"clips": {"vo": {"marks": {"logo": 1.0}}}}' >"$FX/cues.json"
cat >"$FX/probe.py" <<'PY'
arm = next(o for o in hero.children_recursive if o.type == "ARMATURE")
mesh = next(o for o in hero.children_recursive if o.type == "MESH")
strips = [s for t in arm.animation_data.nla_tracks for s in t.strips]
s = strips[0] if strips else None
spans = []
for f in range(scene.frame_start, scene.frame_end + 1):
    scene.frame_set(f)
    e = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    ys = [(e.matrix_world @ v.co).y for v in e.data.vertices]
    spans.append(max(ys) - min(ys))
print("PROBE", len(strips), s.name if s else "-", f"{s.scale:.4f}" if s else 0, f"{(s.frame_end - s.frame_start) / s.repeat:.4f}" if s else 0, f"{min(spans):.3f}", f"{max(spans):.3f}")
PY
probe() { MV_MODEL=$GLB MV_FPS=12 MV_SECONDS=2 MV_CUES=$FX/cues.json "$@" nice blender -b --factory-startup -P <(sed '$d' "$SHOT"; cat "$FX/probe.py") 2>&1 | grep -E '^PROBE|^shot.py'; }

. "$HERE/fixtures/plates/plates.sh"
plates mv-model-anim "$GLB"
if ((BL)); then
  probe env >"$P/rest.txt"
  probe env MV_MODEL_ANIM=first MV_MODEL_ANIM_CUE=logo >"$P/first.txt"
  probe env MV_MODEL_ANIM=Bend MV_MODEL_ANIM_SPEED=2 MV_MODEL_ANIM_CUE=logo >"$P/speed2.txt"
  probe env MV_MODEL_ANIM=Bend MV_MODEL_ANIM_SPEED=0.8 >"$P/nocue.txt"
  probe env MV_MODEL_ANIM=Still >"$P/still.txt"
  probe env MV_MODEL_ANIM=Nope >"$P/nope.txt"
  for k in static first; do
    MV_MODEL=$GLB MV_MODEL_ANIM=$([[ $k == first ]] && echo first) MV_FPS=6 MV_SECONDS=1 MV_SIZE=640x360 nice "$MV" blender "$SHOT" "$FX/$k" --draft >/dev/null 2>&1
    ls "$FX/$k"/frame_*.png 2>/dev/null | wc -l >"$P/$k-frames"
    for f in "$FX/$k"/frame_000[14].png; do [[ -f $f ]] && keep "$f" "$P/$k/${f##*/}" RGB; done
  done
fi

read -r _ ntr _ _ _ lo hi < <(val rest.txt)
ok "$(echo "${ntr:-1} == 0 && ${hi:-1} - ${lo:-0} < 0.001" | bc)" "no knob: $ntr NLA strips, hero static (y extent $lo..$hi)"
read -r _ ntr clip scale loop lo hi < <(val first.txt)
ok "$(echo "${ntr:-0} == 1 && ${loop:-0} > 11.99 && ${loop:-0} < 12.01 && ${hi:-0} - ${lo:-0} > 0.2" | bc)" "MV_MODEL_ANIM=first: clip $clip, loop $loop frames ends on cue frame 13, bend y extent $lo..$hi"
read -r _ _ _ scale loop _ _ < <(val speed2.txt)
ok "$(echo "${loop:-0} > 5.99 && ${loop:-0} < 6.01" | bc)" "MV_MODEL_ANIM_SPEED=2: loop $loop frames (scale $scale), 2 loops end on the cue"
read -r _ _ _ scale loop _ _ < <(val nocue.txt)
ok "$(echo "${loop:-0} > 11.49 && ${loop:-0} < 11.51" | bc)" "no cue: loop $loop frames (scale $scale) ends on the shot end (frame 24)"
read -r _ ntr clip _ _ lo hi < <(val still.txt)
ok "$([[ ${clip:-} == Still ]] && echo "${hi:-1} - ${lo:-0} < 0.001" | bc || echo 0)" "MV_MODEL_ANIM=Still picks the named clip ($clip, y extent $lo..$hi)"
msg=$(val nope.txt)
ok "$([[ $msg == *"MV_MODEL_ANIM Nope not in ['Bend', 'Still']"* ]] && echo 1 || echo 0)" "unknown clip refused: $msg"

read -r d1 d4 < <(python3 -I - "$P" <<'PY'
import sys
import numpy as np
from PIL import Image
p = sys.argv[1]
try:
    diff = lambda f: np.abs(np.asarray(Image.open(f"{p}/static/{f}"), float) - np.asarray(Image.open(f"{p}/first/{f}"), float)).mean(axis=2)
    print(*(f"{(diff(f) > 25).mean():.4f}" for f in ("frame_0001.png", "frame_0004.png")))
except OSError:
    print(0, 0)
PY
)
ns=$(val static-frames) nk=$(val first-frames)
nf=$((${ns:-0} < ${nk:-0} ? ${ns:-0} : ${nk:-0}))
ok "$(echo "$nf == 6 && ${d4:-0} >= 0.01 && ${d4:-0} >= 3 * ${d1:-1}" | bc)" "draft render: $nf frames, changed pixels vs static: frame 1 $d1, frame 4 $d4 (>= 0.01 and >= 3x frame 1)"

echo "mv-model-anim.test: $((n - bad))/$n passed"
exit $((bad > 0))
