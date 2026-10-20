#!/usr/bin/env bash
# mv-title3d.test.sh: MV_TITLE kinetic 3D title of the Blender shot - brand font, extrude 0.08, 40 ms stagger from MV_TITLE_CUE, 3 draft frames, title x logo silhouette = 0 px on 3 moves, every letter a separate blob at the end frame. Asserts on fixtures/plates/mv-title3d (make.sh); Blender renders them on MV_BLENDER_FULL=1, Sundays or a stale/missing fixture.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
TITLE="NORTH STAR"
LETTERS=9
cat >"$FX/logo.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="240" height="120" viewBox="0 0 240 120">
  <path fill="#ff5a36" fill-rule="evenodd" d="M10 20 Q10 10 20 10 L100 10 Q110 10 110 20 L110 100 Q110 110 100 110 L20 110 Q10 110 10 100 Z M35 35 L35 85 L85 85 L85 35 Z"/>
  <path fill="#ff5a36" d="M130 110 L130 10 L160 10 L200 70 L200 10 L230 10 L230 110 L200 110 L160 50 L160 110 Z"/>
</svg>
SVG
echo '{"clips": {"vo": {"marks": {"title": 0.25}}}}' >"$FX/cues.json"
export MV_TITLE=$TITLE MV_CUES=$FX/cues.json MV_TITLE_CUE=title MV_LOGO=$FX/logo.svg
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
shot() { blender -b --factory-startup -P <(sed '$d' "$SHOT"; cat "$1") 2>/dev/null; }
. "$HERE/fixtures/plates/plates.sh"
plates mv-title3d

cat >"$FX/probe.py" <<'PY'
from bpy_extras import anim_utils
starts = []
for o in title_letters:
    ad = o.animation_data
    starts.append(anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves[0].keyframe_points[0].co.x)
steps = {round(b - a, 4) for a, b in zip(starts, starts[1:])}
print("PROBE", len(title_letters), f"{starts[0]:.3f}", ",".join(map(str, sorted(steps))), f"{title_letters[0].dimensions.z:.3f}",
      os.path.basename(bpy.data.fonts[-1].filepath))
PY
cat >"$FX/masks.py" <<'PY'
floor.hide_render = True
if ring:
    ring.hide_render = True
scene.render.film_transparent = True
scene.render.image_settings.color_mode = "RGBA"
mid = (scene.frame_start + scene.frame_end) // 2
for f in (scene.frame_start, mid, scene.frame_end):
    scene.frame_set(f)
    for name in ("title", "logo"):
        hero.hide_render = name == "title"
        for o in title_letters:
            o.hide_render = name == "logo"
        scene.render.filepath = f"{os.environ['MASKS']}/{name}_{f:02d}.png"
        bpy.ops.render.render(write_still=True)
PY
if ((BL)); then
  MV_FPS=50 MV_SECONDS=1 shot "$FX/probe.py" | grep '^PROBE' >"$P/probe.txt"
  MV_TITLE_CUE=nope MV_FPS=3 MV_SECONDS=1 shot /dev/null >/dev/null 2>&1
  echo $? >"$P/cue-rc"
  MV_FPS=3 MV_SECONDS=1 MV_SIZE=320x180 "$MV" blender "$SHOT" "$FX/f" --draft >/dev/null 2>&1
  ls "$FX/f"/frame_*.png 2>/dev/null | wc -l >"$P/draft-frames"
  for m in dolly orbit crane; do
    MASKS=$FX/m-$m MV_CAMERA=$m MV_DRAFT=1 MV_FPS=6 MV_SECONDS=1 MV_SIZE=1280x720 shot "$FX/masks.py" >/dev/null
    for f in "$FX/m-$m"/*.png; do [[ -f $f ]] && keep "$f" "$P/m-$m/${f##*/}" M; done
  done
fi

read -r _ count start steps depth font < <(val "probe.txt")
ok "$([[ ${count:-0} == "$LETTERS" ]] && echo 1 || echo 0)" "\"$TITLE\": ${count:-0} letter objects"
ok "$([[ ${start:-} == 13.500 && ${steps:-} == 2.0 ]] && echo 1 || echo 0)" "first letter at cue 0.25 s = frame ${start:-?} at 50 fps, stagger ${steps:-?} frames (40 ms)"
ok "$(echo "${depth:-0} > 0.18 && ${depth:-0} < 0.19" | bc)" "extrude 0.08 + bevel: letter depth ${depth:-?}"
ok "$([[ ${font:-} == Inter* ]] && echo 1 || echo 0)" "brand display font: ${font:-none}"
ok "$([[ $(val cue-rc) =~ ^[1-9] ]] && echo 1 || echo 0)" "unknown MV_TITLE_CUE exits non-zero"
ok "$([[ $(val draft-frames) == 3 ]] && echo 1 || echo 0)" "3 draft frames with the title"

for m in dolly orbit crane; do
  read -r frames px blobs < <(python3 -I - "$P/m-$m" <<'PY'
import glob, sys
import numpy as np
from PIL import Image
def mask(fn):
    return np.asarray(Image.open(fn).convert("L")) > 127
def blobs(m, min_px=20):
    seen, n = np.zeros_like(m), 0
    for y, x in zip(*np.nonzero(m)):
        if seen[y, x]:
            continue
        stack, size = [(y, x)], 0
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            size += 1
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        n += size >= min_px
    return n
titles = sorted(glob.glob(f"{sys.argv[1]}/title_*.png"))
px = sum(int((mask(fn) & mask(fn.replace("title_", "logo_"))).sum()) for fn in titles)
print(len(titles), px, blobs(mask(titles[-1])) if titles else 0)
PY
)
  ok "$([[ ${frames:-0} == 3 && ${px:-1} == 0 ]] && echo 1 || echo 0)" "$m: title x logo silhouette = ${px:-?} px on ${frames:-0} draft frames"
  ok "$([[ ${blobs:-0} == "$LETTERS" ]] && echo 1 || echo 0)" "$m: ${blobs:-0} letter blobs visible at the end frame (want $LETTERS)"
done

echo "mv-title3d.test: $((n - bad))/$n passed"
exit $((bad > 0))
