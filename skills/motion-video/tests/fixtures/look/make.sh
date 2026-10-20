#!/usr/bin/env bash
# make.sh: record mv-look's plates (MV_DEPTH, gradient, vignette luma, catcher PNGs) into this dir under `heavy run`; --into DIR renders there directly.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
[[ ${1:-} == --into && -n ${2:-} ]] || exec heavy run --ticket T787 -- "$0" --into "$HERE"
OUT=$2 MAX_KB=${MAX_KB:-300}
MV=$HERE/../../../scripts/mv-render
SHOT=$HERE/../../../templates/blender/shot.py
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
shot() { MV_FPS=1 MV_SECONDS=1 MV_SAMPLES=8 MV_SHUTTER=0 MV_SIZE=${MV_SIZE:-160x90} "$MV" blender "$SHOT" "$T/$1" >/dev/null 2>&1; }

MV_SIZE=64x64 shot d16
MV_SIZE=64x64 MV_DEPTH=8 shot d8
MV_LOOK=soft shot soft
MV_LOOK=soft MV_VIGNETTE=0 shot bloom
MV_GROUND=catcher shot catch
MV_GROUND=catcher MV_LOOK=soft shot catch-soft
mkdir -p "$T/look/gr"
blender -b --factory-startup --python-expr 'import sys, bpy
s = bpy.context.scene
s.view_settings.view_transform = "AgX"
img = bpy.data.images.new("g", 64, 64, float_buffer=True)
img.pixels[:] = [c for i in range(4096) for c in (0.01 + 0.03 * i / 4095,) * 3 + (1.0,)]
for d in ("8", "16"):
    s.render.image_settings.file_format, s.render.image_settings.color_depth = "PNG", d
    for f in (1, 2):
        img.save_render(f"{sys.argv[-1]}/d{d}_{f:04d}.png", scene=s)' -- "$T/look/gr" >/dev/null 2>&1

for s in d16 d8 catch catch-soft; do cp "$T/$s/frame_0001.png" "$T/look/$s.png"; done
for s in d16 d8; do cp "$T/$s/render.json" "$T/look/$s.json"; done
for s in soft bloom; do ffmpeg -v error -i "$T/$s/frame_0001.png" -pix_fmt gray16be "$T/look/vig-$s.png"; done
kb=$(du -sk "$T/look" | cut -f1)
[[ $OUT != "$HERE" ]] || ((kb <= MAX_KB)) || { echo "make.sh: plates $kb KB > $MAX_KB KB" >&2; exit 1; }
mkdir -p "$OUT/gr"
cp "$T"/look/*.png "$T"/look/*.json "$OUT/"
cp "$T"/look/gr/*.png "$OUT/gr/"
echo "make.sh: $(find "$T/look" -type f | wc -l) plates, $kb KB -> $OUT"
