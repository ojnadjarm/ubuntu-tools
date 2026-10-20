#!/usr/bin/env bash
# mv-camera.test.sh: MV_CAMERA moves, MV_CAMERA_EASE curves, MV_LENS/MV_FSTOP and --dump-camera of the Blender shot, 5 draft Cycles clips of 12 frames at 64x36. Asserts on fixtures/plates/mv-camera (make.sh: camera JSON dumps, clip time and frame count); Blender renders them on MV_BLENDER_FULL=1, Sundays or a stale/missing fixture.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
# One OpenMP/BLAS thread per Blender (the default pool costs ~1 cpu s per process); Cycles CPU at 4 spp costs half of EEVEE's GPU init for the same camera data.
export OMP_NUM_THREADS=1 MV_ENGINE=CYCLES
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
clip() { MV_CAMERA=$1 MV_FPS=12 MV_SECONDS=1 MV_SIZE=128x72 "$MV" blender "$SHOT" "$FX/$1" --draft -- --dump-camera "$FX/$1.json" >/dev/null 2>&1; }
cam() { python3 -I - "$P/$1.json" "$2" <<'PY'
import json, math, sys
d = json.load(open(sys.argv[1]))
p = d["frames"]
r = [math.dist(q, d["target"]) for q in p]
v = [math.dist(a, b) for a, b in zip(p, p[1:])]
first, mid = v[0], v[len(v) // 2]
line = [[a + (b - a) * i / (len(p) - 1) for a, b in zip(p[0], p[-1])] for i in range(len(p))]
dev = max(math.dist(a, b) for a, b in zip(p, line))
print(int(eval(sys.argv[2])))
PY
}

. "$HERE/fixtures/plates/plates.sh"
plates mv-camera ~/agents/bin/tests/lib/budget.sh
if ((BL)); then
  # The 5 renders and the handheld re-dump are independent Blender processes: run them at once.
  MV_CAMERA=handheld MV_FPS=12 MV_SECONDS=1 blender -b --factory-startup -P <(sed '$d' "$SHOT") -- --dump-camera "$FX/hh2.json" >/dev/null 2>&1 &
  t=$(date +%s.%N)
  clip dolly &
  MV_CAMERA_EASE=linear MV_LENS=85 MV_FSTOP=8 clip orbit &
  MV_CAMERA_EASE=expo clip crane &
  MV_CAMERA_EASE=linear clip push &
  clip handheld &
  wait
  echo "$(echo "$(date +%s.%N) - $t" | bc) $(bash ~/agents/bin/tests/lib/budget.sh 60)" >"$P/time"
  echo "$(ls "$FX"/*/frame_*.png 2>/dev/null | wc -l) $(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$FX/orbit/frame_0012.png")" >"$P/frames"
  for f in "$FX"/*.json; do [[ -f $f ]] && cp "$f" "$P/"; done
fi

read -r secs lim < <(val time)
if ((BL)); then
  ok "$(echo "${secs:-999} <= ${lim:-0}" | bc)" "5 draft clips in ${secs%???????} s (<= $lim s budget)"
else
  echo "note: 5 draft clips ${secs%???????} s (budget $lim s) recorded $(awk '$1 == "made" { print $2 }' "$P/manifest"), measured only when BL=1"
fi
read -r frames size < <(val frames)
ok "$([[ $frames == 60 && $size == 64,36 ]] && echo 1 || echo 0)" "60 frames of 64x36 ($frames)"

ok "$(cam dolly 'first < 0.3 * mid and len(p) == 12')" "dolly ease: first-frame speed < 30 % of mid"
ok "$(cam orbit 'max(r) / min(r) - 1 < 0.01 and dev > 1')" "orbit radius constant within 1 % on a curved path"
ok "$(cam orbit 'd["lens"] == 85 and d["fstop"] == 8 and first > 0.7 * mid')" "orbit MV_LENS=85 MV_FSTOP=8, linear speed"
ok "$(cam crane 'all(b[2] > a[2] for a, b in zip(p, p[1:])) and first < 0.3 * mid')" "crane rises every frame, expo first-frame speed < 30 % of mid"
ok "$(cam push 'all(b < a for a, b in zip(r, r[1:])) and r[-1] < 0.6 * r[0]')" "push distance to target falls every frame"
ok "$(cam push 'dev < 1e-3 and first > 0.7 * mid')" "push linear: straight line, even speed"
ok "$(cam handheld 'dev > 0.01 and p[-1] == [-2.4, -6.8, 1.9]')" "handheld shakes off the line and settles on its end key"
ok "$(cmp -s "$P/hh2.json" "$P/handheld.json" && echo 1 || echo 0)" "handheld noise is deterministic (same path twice)"

echo "mv-camera.test: $((n - bad))/$n passed"
exit $((bad > 0))
