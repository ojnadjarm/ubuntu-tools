#!/usr/bin/env bash
# cpp-vulkan shader hot reload on a throwaway copy (real build, Iris Xe under headless weston): --hot replay paused at frame 60, mesh.frag rewritten to solid red turns the captured frame red within 1 s, a broken mesh.frag prints file:line and leaves the frame unchanged, post.frag rewritten to green turns it green within 1 s, 0 validation errors; the release binary has no watcher.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ -x "${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}/vcpkg" ] || { echo "SKIP needs vcpkg (install.sh --gamedev)"; exit 0; }
T=$(mktemp -d); trap 'pkill -TERM -f "^$T/game/build/dev/game" 2>/dev/null; rm -rf "$T"' EXIT
A=${VCPKG_DEFAULT_BINARY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/vcpkg/archives}
[ -d "$A" ] && export VCPKG_BINARY_SOURCES="clear;files,$A,read"  # temp XDG_CACHE_HOME would hide the real vcpkg binary cache
command -v ccache >/dev/null && export CCACHE_DIR=${CCACHE_DIR:-$(ccache -k cache_dir)}  # keep the shared ccache under the temp XDG_CACHE_HOME
export VCPKG_ROOT=${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg} XDG_CACHE_HOME=$T/cache
P=$T/game C=$T/cap LOG=$T/hot.log
"$G/scripts/new-cpp-game" --build "$P" > "$T/build.log" 2>&1 || { echo "FAIL build"; tail -20 "$T/build.log"; exit 1; }
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
frag() {  # file, rgba, end of statement (default ;): a minimal fragment shader writing one colour
	printf '#version 450\nlayout(location = 0) out vec4 out_color;\nvoid main() { out_color = vec4(%s)%s }\n' "$2" "${3-;}" > "$P/shaders/$1"
}
frames() {  # t0, python condition on r g b p: "dt rgb" of the first frame saved after t0 meeting it, or nothing
	python3 -I - "$C" "$1" "$2" <<'EOF'
import glob, os, sys
from PIL import Image, ImageStat
d, t0, cond = sys.argv[1], float(sys.argv[2]), sys.argv[3]
for p in sorted(glob.glob(d + "/frame_*.png")):
    m = os.path.getmtime(p)
    if m < t0:
        continue
    r, g, b = ImageStat.Stat(Image.open(p).convert("RGB")).mean
    if eval(cond):
        print(f"{m - t0:.3f} {r:.0f},{g:.0f},{b:.0f}")
        break
EOF
}
waitlog() { timeout 20 wait-for --every 0.1 --until "grep -q '$1' '$LOG'" --job "$job" > /dev/null; }

mkdir -p "$C"; cp -r "$P/shaders" "$T/shaders.orig"
"$G/scripts/cpp-vk-run.sh" --size 320x180 --timeout 90 --frames 100000 "$P/build/dev/game" --hot \
	--replay "$G/tests/fixtures/cpp-play-input.json" --pause-at 60 --capture-every "$C" > "$LOG" 2>&1 &
job=$!
timeout 30 wait-for --every 0.1 --until "[ -f '$C/frame_00070.png' ]" --job $job > /dev/null || { bad "no paused frames"; tail -20 "$LOG"; exit 1; }
grep -q '^HOT watching ' "$LOG" && ok "--hot watches shaders/" || bad "no HOT watching line"
lim=1.0; grep -q '^GAME device="llvmpipe' "$LOG" && lim=3.0  # lavapipe compiles pipelines on the CPU
base=$(frames 0 "'00070' in p and not (r > g + 10 and r > b)")
[ -n "$base" ] || bad "paused frame 70 is already red"

t0=$(date +%s.%N); frag mesh.frag "1.0, 0.0, 0.0, 1.0"
waitlog '^HOT reload mesh.frag' && sleep 0.3
red=$(frames "$t0" "r > g + 10 and r > b")
awk -v d="${red%% *}" -v l=$lim 'BEGIN {exit !(d != "" && d <= l)}' && ok "red mesh.frag on screen after ${red%% *} s (rgb ${base#* } -> ${red#* })" \
	|| { bad "red frame: '$red' want <= $lim s"; grep '^HOT' "$LOG"; }

t1=$(date +%s.%N); frag mesh.frag "0.0, 1.0, 0.0, 1.0" ""
waitlog '^HOT error mesh.frag' && sleep 0.5
grep -Eq "mesh\.frag:[0-9]+:" "$LOG" && ok "broken shader prints $(grep -Eo 'mesh\.frag:[0-9]+:' "$LOG" | head -1)" || bad "no file:line error"
changed=$(frames "$t1" "f'{r:.0f},{g:.0f},{b:.0f}' != '${red#* }'")
[ -z "$changed" ] && kill -0 $job 2>/dev/null && ok "broken shader: old pipeline kept, frame unchanged" || bad "frame changed after broken shader: '$changed'"

t2=$(date +%s.%N); frag post.frag "0.0, 1.0, 0.0, 1.0"
waitlog '^HOT reload post.frag' && sleep 0.3
green=$(frames "$t2" "g > 200 and r < 30")
awk -v d="${green%% *}" -v l=$lim 'BEGIN {exit !(d != "" && d <= l)}' && ok "green post.frag on screen after ${green%% *} s" || bad "green frame: '$green' want <= $lim s"

pkill -TERM -f "^$P/build/dev/game"; wait $job  # SIGTERM: a background job ignores SIGINT
grep -q '^DONE .* validation_errors=0 ' "$LOG" && ok "0 validation errors" || { bad "validation"; grep -E '^(DONE|fatal|VALIDATION ERROR)' "$LOG" | head -5; }
echo "HOT $(grep -E '^HOT reload' "$LOG" | tr '\n' ' ')"

cp "$T/shaders.orig/"* "$P/shaders/"
# Release: configure, compile only main.cpp (the one GAME_HOT user); shader_watch.cpp (the "HOT watching" string) must not be a release TU.
O=CMakeFiles/game.dir/src/main.cpp.o RC=$P/build/release/compile_commands.json
(cd "$P" && cmake --preset release && cmake --build --preset release --target $O) > "$T/release.log" 2>&1 || { bad "release main.cpp.o"; tail -20 "$T/release.log"; }
n=$( (grep -c 'shader_watch\.cpp' "$RC"; nm -C "$P/build/release/$O" | grep -c ShaderWatch; grep -c 'HOT watching' "$P/build/release/$O") 2>&1 | paste -sd/)
[ "$n" = 0/0/0 ] && nm -C "$P/build/dev/$O" | grep -q ShaderWatch && grep -q 'HOT watching' "$P/build/dev/game" \
	&& ok "shader watcher: dev binary yes, release TUs/main.o 0" || bad "release has the watcher (compile_commands/ShaderWatch/string: $n)"
echo "cpp-hot.test: $fails failed"
exit $((fails > 0))
