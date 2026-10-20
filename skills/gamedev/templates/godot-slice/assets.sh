#!/usr/bin/env bash
# Fill res://assets with CC0 assets: Poly Haven floor/crate/HDRI, Kenney sounds; crate through asset-pipeline (LOD glb + KTX2, gated by budgets.json).
set -euo pipefail
proj=$(cd "$(dirname "$0")" && pwd)
S=${GAMEDEV_SCRIPTS:-$HOME/.claude/skills/gamedev/scripts}
raw=${1:-$proj/.assets-raw}
a=$proj/assets
mkdir -p "$a/floor" "$a/audio"
"$S/cc0-fetch.sh" polyhaven forrest_ground_01 "$raw"
"$S/cc0-fetch.sh" polyhaven wooden_crate_01 "$raw"
"$S/cc0-fetch.sh" polyhaven kloofendal_48d_partly_cloudy_puresky "$raw"
"$S/cc0-fetch.sh" kenney interface-sounds "$raw"
f=$raw/polyhaven/forrest_ground_01/forrest_ground_01
for m in diff nor_gl rough ao; do cp "${f}_${m}_1k.jpg" "$a/floor/${m%_gl}.jpg"; done
cp "$raw"/polyhaven/kloofendal_48d_partly_cloudy_puresky/*_1k.hdr "$a/sky.hdr"
z=$raw/kenney/interface-sounds/kenney_interface-sounds.zip
unzip -p "$z" Audio/confirmation_001.ogg > "$a/audio/pickup.ogg"
unzip -p "$z" Audio/maximize_006.ogg > "$a/audio/win.ogg"
"$S/asset-pipeline.sh" --glb "$raw/polyhaven/wooden_crate_01/wooden_crate_01_1k.gltf" --lods "1 0.25" --budget "$proj/budgets.json" "$raw/crate"
cp "$raw/crate/model_lod0.glb" "$a/crate.glb"
cp "$raw/LICENSES.csv" "$a/LICENSES.csv"
echo "ASSETS done $(du -sh "$a" | cut -f1) in $a"
