#!/usr/bin/env bash
# mv-render-speed.test.sh: shot.py MV_SAMPLES=auto (EEVEE 16, Cycles 32, explicit N kept) and auto stays within 0.2 % mean abs of the 32 spp picture (2 spp: 0.44 %). Asserts on fixtures/plates/mv-render-speed (make.sh: spp values, the frame-3 diff); Blender renders them on MV_BLENDER_FULL=1, Sundays or a stale/missing fixture.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
. "$HERE/fixtures/plates/plates.sh"
plates mv-render-speed
if ((BL)); then
  # The four spp probes: shot.py without its render line, run four times in one Blender process.
  SHOT=$SHOT MV_FPS=1 MV_SECONDS=1 MV_SIZE=32x32 blender -b --factory-startup --python-expr 'import os
shot = os.environ["SHOT"]
code = compile("\n".join(open(shot).read().splitlines()[:-1]), shot, "exec")
for name, env in (("unset", {}), ("auto", {"MV_SAMPLES": "auto"}), ("24", {"MV_SAMPLES": "24"}), ("cycles", {"MV_ENGINE": "CYCLES"})):
    for k in ("MV_SAMPLES", "MV_ENGINE"):
        os.environ.pop(k, None)
    os.environ.update(env)
    g = {"__file__": shot, "__name__": "__main__"}
    exec(code, g)
    s = g["scene"]
    print("SPP", name, s.cycles.samples if s.render.engine == "CYCLES" else s.eevee.taa_render_samples, flush=True)' -- "$FX/spp/frame_" 2>&1 |
    awk -v p="$P" '$1 == "SPP" { print $3 > (p "/spp-" $2) }'
  for s in 32 auto; do MV_FPS=30 MV_SECONDS=0.1 MV_SIZE=480x270 MV_SAMPLES=$s "$MV" blender "$SHOT" "$FX/s$s" >/dev/null 2>&1; done
  python3 -I - "$FX/s32/frame_0003.png" "$FX/sauto/frame_0003.png" >"$P/diff" <<'PY2'
import os, subprocess, sys
import numpy as np
def px(f):
    b = subprocess.check_output(["ffmpeg", "-v", "error", "-i", f, "-f", "rawvideo", "-pix_fmt", "rgb48le", "-"])
    return np.frombuffer(b, "<u2").astype(float) / 65535
print(f"{np.abs(px(sys.argv[1]) - px(sys.argv[2])).mean():.5f}" if all(map(os.path.isfile, sys.argv[1:])) else "nan")
PY2
fi

ok "$(is "$(val spp-unset)" 16)" "MV_SAMPLES unset: EEVEE 16 spp"
ok "$(is "$(val spp-auto)" 16)" "MV_SAMPLES=auto: EEVEE 16 spp"
ok "$(is "$(val spp-24)" 24)" "MV_SAMPLES=24 kept"
ok "$(is "$(val spp-cycles)" 32)" "MV_SAMPLES unset + Cycles: 32 spp"
diff=$(val diff)
ok "$([[ $diff =~ ^[0-9]+(\.[0-9]+)?$ ]] && echo "$diff < 0.002" | bc || echo 0)" "auto vs 32 spp, 480x270 dolly frame 3: mean abs diff $diff < 0.002"

echo "mv-render-speed: $((n - bad))/$n passed"
[[ $bad == 0 ]]
