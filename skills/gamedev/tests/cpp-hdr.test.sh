#!/usr/bin/env bash
# cpp-vulkan HDR post chain on a throwaway copy of the template (real build, Iris Xe under headless weston): 0 validation errors (sync + best practices), --exposure +2 EV brighter than -2 EV, post_ms_p50 <= 0.6 ms at 1920x1080 when the machine is quiet and the GPU holds >= 90 % of its max clock (T674: B10G11R11 bloom, measured 0.49-0.54 ms at 1300 MHz).
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=SCRIPTDIR/../scripts/gpu-gate.sh
. "$G/scripts/gpu-gate.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
"$G/scripts/cpp-ci" --stages "configure build" "$P" > "$T/ci.log" 2>&1 || { echo "FAIL build"; cat "$T/ci.log" "$P"/ci/logs/*.log | tail -40; exit 1; }
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
field() { sed -n "s/^DONE .* $2=\([0-9.]*\).*/\1/p" "$1"; }
run() {  # name game-args...: frame 60 to $T/name.png, validation on
	local name=$1; shift
	"$G/scripts/cpp-vk-run.sh" --frames 61 "$P/build/ci-release/game" --capture 60 "$T/$name.png" "$@" > "$T/$name.log" 2>&1
	if [ $? = 0 ] && [ "$(field "$T/$name.log" validation_errors)" = 0 ]; then ok "$name: 0 validation errors"
	else bad "$name: validation"; tail -15 "$T/$name.log"; fi
}
run dark --exposure -2
run bright --exposure 2
lum=$(python3 -I -c '
import sys
from PIL import Image, ImageStat
print(" ".join(f"{ImageStat.Stat(Image.open(p).convert("L")).mean[0]:.1f}" for p in sys.argv[1:]))
' "$T/dark.png" "$T/bright.png" 2>&1)
awk -v a="${lum% *}" -v b="${lum#* }" 'BEGIN {exit !(b > a + 40)}' && ok "mean luma -2 EV ${lum% *} < +2 EV ${lum#* }" \
	|| bad "exposure: luma '$lum' want +2 EV > -2 EV + 40"
if gpu_timed cpp-hdr post_ms_p50 -- "$G/scripts/cpp-vk-run.sh" --no-validate --frames 600 "$P/build/ci-release/game" --size 1920x1080; then
	awk -v m="${gpu_value:-99}" 'BEGIN {exit !(m <= 0.6)}' && ok "post_ms_p50=$gpu_value <= 0.6 at 1080p ($gpu_mhz MHz)" || bad "post_ms_p50='$gpu_value' want <= 0.6 ($gpu_mhz MHz)"
fi
echo "cpp-hdr.test: $fails failed"
exit $((fails > 0))
