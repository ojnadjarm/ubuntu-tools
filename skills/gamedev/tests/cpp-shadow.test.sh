#!/usr/bin/env bash
# cpp-vulkan directional shadow on a throwaway copy of the template (real build, Iris Xe under headless weston): a ground pixel in the cube's shadow is >= 40 % darker than with --no-shadows, 0 validation errors (sync + best practices), shadow pass zone gpu_ms_p50_shadow <= 0.1 ms when the machine is quiet and the GPU holds >= 90 % of its max clock (T695: measured 0.059-0.066 ms at 750-800 MHz, 1280x720, with and without IBL).
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=SCRIPTDIR/../scripts/gpu-gate.sh
. "$G/scripts/gpu-gate.sh"
[ -x "${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}/vcpkg" ] || { echo "SKIP needs vcpkg (install.sh --gamedev)"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
"$G/scripts/cpp-ci" --stages "configure build" "$P" > "$T/ci.log" 2>&1 || { echo "FAIL build"; cat "$T/ci.log" "$P"/ci/logs/*.log | tail -40; exit 1; }
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
field() { sed -n "s/^DONE .* $2=\([0-9.]*\).*/\1/p" "$1"; }
run() {  # name game-args...: frame 60 to $T/name.png, log $T/name.log, validation on
	local name=$1; shift
	"$G/scripts/cpp-vk-run.sh" --frames 61 "$P/build/ci-release/game" --capture 60 "$T/$name.png" "$@" > "$T/$name.log" 2>&1
	if [ $? = 0 ] && [ "$(field "$T/$name.log" validation_errors)" = 0 ]; then ok "$name: 0 validation errors"
	else bad "$name: validation"; tail -15 "$T/$name.log"; fi
}
# Spawn view raised 0.5 m: the pre-T693 frame (ground drawn at -0.5, now at y = 0 with the cube lifted onto it).
run shadows --no-ibl --camera 0,1.3,2.6,0,-0.2985
run no-shadows --no-ibl --no-shadows --camera 0,1.3,2.6,0,-0.2985
# Ground left of the cube at the golden camera (frame 60), inside the cube's shadow; IBL off so only the shadow term differs.
ratio=$(python3 -I -c '
import sys
from PIL import Image
x, y = 0.328, 0.612
lum = [Image.open(p).convert("L") for p in sys.argv[1:]]
on, off = (im.getpixel((int(x * (im.width - 1)), int(y * (im.height - 1)))) for im in lum)
print(f"{1 - on / max(off, 1):.3f} {on} {off}")
' "$T/shadows.png" "$T/no-shadows.png" 2>&1)
awk -v r="${ratio%% *}" 'BEGIN {exit !(r >= 0.4)}' && ok "shadowed pixel darker by ${ratio%% *} (lum ${ratio#* })" \
	|| bad "shadowed pixel: '$ratio' want >= 0.4"
if gpu_timed cpp-shadow gpu_ms_p50_shadow -- "$G/scripts/cpp-vk-run.sh" --no-validate --frames 600 "$P/build/ci-release/game"; then
	awk -v m="${gpu_value:-99}" 'BEGIN {exit !(m <= 0.1)}' && ok "gpu_ms_p50_shadow=$gpu_value <= 0.1 ($gpu_mhz MHz)" || bad "gpu_ms_p50_shadow='$gpu_value' want <= 0.1 ($gpu_mhz MHz)"
fi
echo "cpp-shadow.test: $fails failed"
exit $((fails > 0))
