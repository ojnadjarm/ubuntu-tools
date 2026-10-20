#!/usr/bin/env bash
# cpp-vulkan FXAA 3.11 on a throwaway copy of the template (real build, Iris Xe under headless weston): default and --aa off run with 0 validation errors, off differs, the floor/sky edge's stair-step pixels drop >= 50 %, the 1080p post zone delta (fxaa - off) stays under a 0.5 ms regression guard (gpu_timed: skipped when busy or below 90 % of max GPU clock).
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl CCACHE_BASEDIR=$T CCACHE_NOHASHDIR=1 OMP_NUM_THREADS=1
P=$T/game
# shellcheck source=SCRIPTDIR/../scripts/gpu-gate.sh
. "$G/scripts/gpu-gate.sh"
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
"$G/scripts/cpp-ci" --stages "configure build" "$P" > "$T/ci.log" 2>&1 || { echo "FAIL build"; cat "$T/ci.log" "$P"/ci/logs/*.log | tail -40; exit 1; }
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
run() {  # name game-args...: frame 60 to $T/name.png, validation on
	local name=$1; shift
	"$G/scripts/cpp-vk-run.sh" --frames 61 "$P/build/ci-release/game" --capture 60 "$T/$name.png" "$@" > "$T/$name.log" 2>&1
	local rc=$?
	[ $rc = 0 ] && grep -q '^DONE .*validation_errors=0 ' "$T/$name.log" && ok "$name: 0 validation errors" \
		|| { bad "$name: rc=$rc or validation"; grep -E '^(DONE|fatal|VALIDATION ERROR)' "$T/$name.log" | head -5; }
}
# Stair-step pixels: in each column of the floor/sky edge (1280x720 frame 60), steps above 75 % of the column's contrast.
steps() {
	python3 -I - "$1" <<'EOF'
import sys
from PIL import Image
px = Image.open(sys.argv[1]).convert("L").load()
n = 0
for x in range(5, 115):
    col = [px[x, y] / 255 for y in range(255, 325)]
    c = max(col) - min(col)
    n += sum(abs(b - a) > 0.75 * c for a, b in zip(col, col[1:])) if c > 0.3 else 0
print(n)
EOF
}

grep -q 'FXAA 3.11' "$P/shaders/post.frag" && ok "post.frag carries FXAA 3.11" || bad "no FXAA in post.frag"
# Spawn view raised 0.5 m: the frame T688 measured before T693 put the ground at y = 0 (it was drawn at -0.5).
run fxaa --camera 0,1.3,2.6,0,-0.2985
run off --aa off --camera 0,1.3,2.6,0,-0.2985
cmp -s "$T/fxaa.png" "$T/off.png" && bad "--aa off frame equals the FXAA frame" || ok "--aa off changes the frame"
on=$(steps "$T/fxaa.png") off=$(steps "$T/off.png")
awk -v a="${on:-999}" -v b="${off:-0}" 'BEGIN {exit !(b >= 50 && a <= 0.5 * b)}' \
	&& ok "stair-step pixels $off -> $on (>= 50 % fewer)" || bad "stair-step pixels $off -> $on, want >= 50 % fewer"

post() { "$G/scripts/cpp-vk-run.sh" --no-validate --size 1920x1080 --frames 600 "$P/build/ci-release/game" "$@" 2>&1 | sed -n 's/^DONE .* post_ms_p50=\([0-9.]*\).*/\1/p'; }
# Other load only adds GPU time, so the fastest of 5 runs is each variant's cost.
post_delta() {  # the device line, 5 "fxaa off" post_ms_p50 pairs, then fxaa_post_delta_ms=<fastest fxaa - fastest off>
	grep -m1 '^GAME device=' "$T/fxaa.log"
	for _ in 1 2 3 4 5; do echo "$(post) $(post --aa off)"; done | tee "$T/pairs.txt"
	awk 'NF == 2 {if (!a || $1 < a) a = $1; if (!b || $2 < b) b = $2} END {if (a && b) printf "fxaa_post_delta_ms=%.4f\n", a - b}' "$T/pairs.txt"
}
if GPU_LOG=$T/post.txt gpu_timed cpp-aa fxaa_post_delta_ms -- post_delta; then
	awk -v d="${gpu_value:-9}" 'BEGIN {exit !(d <= 0.5)}' && ok "1080p post zone fxaa - off: $gpu_value ms (fastest of 5 each, $gpu_mhz MHz)" \
		|| { bad "1080p post delta '$gpu_value' ms > 0.5"; cat "$T/post.txt"; }
fi
echo "cpp-aa.test: $fails failed"
exit $((fails > 0))
