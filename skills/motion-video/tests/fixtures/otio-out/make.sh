#!/usr/bin/env bash
# make.sh: regenerates the mv-otio fixture out/ (3 x 1 s 160x90 plates, alpha title, music bed, one SFX, build.json with @OUT@ paths) from lavfi.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
mkdir -p edit
f=(-v error -y -threads 1)
for i in 0 1 2; do
  c=(red green blue); ffmpeg "${f[@]}" -f lavfi -i "color=c=${c[i]}:s=160x90:r=12:d=1" -c:v libx264 -pix_fmt yuv420p -crf 35 "edit/shot$i.mp4"
done
ffmpeg "${f[@]}" -f lavfi -i "color=c=white@0.5:s=160x90:r=12:d=3,format=yuva420p" -c:v libvpx-vp9 -b:v 20k -auto-alt-ref 0 edit/title-16x9.webm
ffmpeg "${f[@]}" -f lavfi -i "sine=f=220:r=8000:d=3" -ac 1 -c:a pcm_s16le edit/music.wav
ffmpeg "${f[@]}" -f lavfi -i "sine=f=880:r=8000:d=0.25" -ac 1 -c:a pcm_s16le hit.wav
jq -n '{name: "demo", draft: true, seconds: 3, fps: 12, size: "160x90",
  cuts: {grid: "even", tempo: null, cuts: [1, 2], frames: [12, 12, 12], starts: [0, 1, 2]},
  edit: {plates: [range(3) | "@OUT@/edit/shot\(.).mp4"], title: "@OUT@/edit/title-16x9.webm", music: "@OUT@/edit/music.wav", vo: null,
    sfx: [{file: "@OUT@/hit.wav", at: 1, db: -12}]}}' >build.json
