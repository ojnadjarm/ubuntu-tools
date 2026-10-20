#!/usr/bin/env bash
# mv-logo.test.sh: MV_LOGO / brand.json logo of the Blender shot - in frame on all 5 camera moves, MV_LOGO_DEPTH, 3 draft frames: silhouette 15-60 %, brand primary within dE 10; ring never crosses the logo, MV_RING=0 hides it. Asserts on fixtures/plates/mv-logo (make.sh); Blender renders them on MV_BLENDER_FULL=1, Sundays or a stale/missing fixture.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
SVG=$FX/logo.svg
cat >"$SVG" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="240" height="120" viewBox="0 0 240 120">
  <path fill="#ff5a36" fill-rule="evenodd" d="M10 20 Q10 10 20 10 L100 10 Q110 10 110 20 L110 100 Q110 110 100 110 L20 110 Q10 110 10 100 Z M35 35 L35 85 L85 85 L85 35 Z"/>
  <path fill="#ff5a36" d="M130 110 L130 10 L160 10 L200 70 L200 10 L230 10 L230 110 L200 110 L160 50 L160 110 Z"/>
</svg>
SVG
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }

cat >"$FX/fit.py" <<'PY'
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
lo, hi = 1.0, 0.0
for f in range(scene.frame_start, scene.frame_end + 1):
    scene.frame_set(f)
    for c in hero.bound_box:
        p = world_to_camera_view(scene, cam, hero.matrix_world @ Vector(c))
        lo, hi = min(lo, p.x, p.y), max(hi, p.x, p.y)
bottom = min((hero.matrix_world @ Vector(c)).z for c in hero.bound_box)
print(f"FIT {lo:.3f} {hi:.3f} {bottom:.3f} {hero.dimensions.z:.3f} {len(hero.data.materials)} {scene.view_settings.view_transform}")
PY
fit() { MV_CAMERA=$1 MV_LOGO=$SVG MV_FPS=12 MV_SECONDS=1 blender -b --factory-startup -P <(sed '$d' "$SHOT"; cat "$FX/fit.py") 2>/dev/null | grep '^FIT'; }
cat >"$FX/masks.py" <<'PY'
floor.hide_render = True
scene.render.film_transparent = True
scene.render.image_settings.color_mode = "RGBA"
mid = (scene.frame_start + scene.frame_end) // 2
for f in (scene.frame_start, mid, scene.frame_end):
    scene.frame_set(f)
    for name in ("ring", "logo"):
        ring.hide_render, hero.is_holdout = name != "ring", name == "ring"
        scene.render.filepath = f"{os.environ['MASKS']}/{name}_{f:02d}.png"
        bpy.ops.render.render(write_still=True)
PY
masks() { MASKS=$FX/m-$1 MV_CAMERA=$1 MV_LOGO=$SVG MV_DRAFT=1 MV_FPS=6 MV_SECONDS=1 MV_SIZE=320x180 blender -b --factory-startup -P <(sed '$d' "$SHOT"; cat "$FX/masks.py") >/dev/null 2>&1; }
python3 -I -c 'import json, sys; b = json.load(open(sys.argv[1])); b["logo"] = "logo.svg"; json.dump(b, open(sys.argv[2], "w"))' "$HERE/../templates/brand.json" "$FX/brand.json"
. "$HERE/fixtures/plates/plates.sh"
plates mv-logo "$HERE/../templates/brand.json"
if ((BL)); then
  for m in dolly orbit crane push handheld; do fit "$m" >"$P/fit-$m.txt"; done
  MV_LOGO_DEPTH=0.8 fit dolly >"$P/fit-depth.txt"
  MV_BRAND=$FX/brand.json MV_GROUND=catcher MV_FPS=3 MV_SECONDS=1 MV_SIZE=320x180 "$MV" blender "$SHOT" "$FX/f" --draft >/dev/null 2>&1
  for f in "$FX"/f/frame_*.png; do [[ -f $f ]] && keep "$f" "$P/f/${f##*/}" RGBA; done
  for m in dolly orbit crane; do
    masks "$m"
    for f in "$FX/m-$m"/*.png; do [[ -f $f ]] && keep "$f" "$P/m-$m/${f##*/}" M; done
  done
  MV_RING=0 MV_LOGO=$SVG MV_FPS=3 MV_SECONDS=1 blender -b --factory-startup -P <(sed '$d' "$SHOT"; echo 'print("RINGS", sum(o.name.startswith("Torus") for o in scene.objects), ring)') 2>/dev/null | grep '^RINGS' >"$P/rings.txt"
fi

for m in dolly orbit crane push handheld; do
  read -r _ lo hi bottom depth mats vt < <(val "fit-$m.txt")
  ok "$(echo "${lo:-0} > 0.01 && ${hi:-1} < 0.99" | bc)" "$m: logo inside the frame on every frame (bbox $lo..$hi)"
done
ok "$(echo "${bottom:-1} > 0.1 && ${bottom:-1} < 0.2 && ${mats:-0} == 2" | bc)" "logo stands on the floor (bottom $bottom), 2 brand materials"
ok "$(echo "${depth:-0} > 0.34 && ${depth:-0} < 0.36" | bc)" "default depth 0.35 ($depth)"
read -r _ _ _ _ depth _ < <(val "fit-depth.txt")
ok "$(echo "${depth:-0} > 0.79 && ${depth:-0} < 0.81" | bc)" "MV_LOGO_DEPTH=0.8 ($depth)"

ok "$([[ $(ls "$P/f"/frame_*.png 2>/dev/null | wc -l) == 3 ]] && echo 1 || echo 0)" "brand.json logo (relative path): 3 draft frames"
while read -r f cov near; do
  ok "$(echo "$cov >= 0.15 && $cov <= 0.60" | bc)" "$f silhouette covers $cov of the frame (0.15-0.60)"
  ok "$(echo "$near >= 0.10" | bc)" "$f brand primary: $near of the logo within dE 10"
done < <(python3 -I - "$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["palette"]["accent"][0])' "$FX/brand.json")" "$P"/f/frame_*.png <<'PY'
import os, sys
import numpy as np
from PIL import Image
def lab(rgb):
    c = rgb / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = c @ np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]]).T / [0.95047, 1.0, 1.08883]
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)
primary = lab(np.array([int(sys.argv[1][k:k + 2], 16) for k in (1, 3, 5)], float))
for fn in sys.argv[2:]:
    a = np.asarray(Image.open(fn), float)
    m = a[..., 3] > 200
    de = np.linalg.norm(lab(a[..., :3]) - primary, axis=-1)[m]
    print(os.path.basename(fn), f"{m.mean():.3f}", f"{(de < 10).mean():.3f}")
PY
)

for m in dolly orbit crane; do
  read -r frames px < <(python3 -I - "$P/m-$m" <<'PY'
import glob, sys
import numpy as np
from PIL import Image
logos = sorted(glob.glob(f"{sys.argv[1]}/logo_*.png"))
px = sum(int(((np.asarray(Image.open(fn).convert("L")) > 127) & (np.asarray(Image.open(fn.replace("logo_", "ring_")).convert("L")) > 127)).sum()) for fn in logos)
print(len(logos), px)
PY
)
  ok "$([[ ${frames:-0} == 3 && ${px:-1} == 0 ]] && echo 1 || echo 0)" "$m: visible ring x logo silhouette = ${px:-?} px on ${frames:-0} draft frames"
done
ok "$(grep -q '^RINGS 0 None' "$P/rings.txt" 2>/dev/null && echo 1 || echo 0)" "MV_RING=0: no ring"

echo "mv-logo.test: $((n - bad))/$n passed"
exit $((bad > 0))
