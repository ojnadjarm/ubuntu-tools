#!/usr/bin/env bash
# cpp-vulkan collision: a throwaway build replays a tape walking into the turntable cube (Jolt CharacterVirtual) twice; the player stops >= 0.3 m in front of it, both runs bit-identical.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ -x "${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}/vcpkg" ] || { echo "SKIP needs vcpkg (install.sh --gamedev)"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$G/scripts/new-cpp-game" --build "$T/game" > "$T/build.log" 2>&1 || { echo "FAIL build"; tail -20 "$T/build.log"; exit 1; }
ticks=60  # contact from tick ~38; by tick ~90 the turning cube slides the player off its corner
{ echo '{"tick_hz": 60, "fields": ["move_x", "move_z", "look_yaw", "look_pitch", "jump"], "ticks": ['
  for i in $(seq $ticks); do [ "$i" = $ticks ] && echo '[0, 1, 0, 0, 0]' || echo '[0, 1, 0, 0, 0],'; done
  echo ']}'; } > "$T/walk.json"
fails=0
play() { (cd "$T" && "$G/scripts/cpp-vk-run.sh" --frames 100000 "$T/game/build/dev/game" --replay "$T/walk.json") > "$1" 2>&1; }
play "$T/a.log"
play "$T/b.log"
pos=$(sed -n 's/^DONE .* pos=\(\S*\),\(\S*\),\(\S*\)$/\1 \2 \3/p' "$T/a.log")
# Gap from the player's axis to the cube (half 0.5) turned by the renderer's 0.5 rad/s turntable at the last tick.
gap=$(awk -v p="$pos" -v n=$ticks 'BEGIN { if (split(p, v) != 3) exit 1; a = 0.5 * n / 60
	x = v[1] * cos(a) - v[3] * sin(a); z = v[1] * sin(a) + v[3] * cos(a)
	dx = (x < 0 ? -x : x) - 0.5; dz = (z < 0 ? -z : z) - 0.5; dx = dx < 0 ? 0 : dx; dz = dz < 0 ? 0 : dz
	printf "%.4f", sqrt(dx * dx + dz * dz) }')
if grep -q '^MESH source=cube ' "$T/a.log" && grep -q 'validation_errors=0 ' "$T/a.log" && [ -n "$gap" ] \
	&& awk -v g="$gap" -v p="$pos" 'BEGIN { split(p, v); exit !(g >= 0.3 && v[3] > 0) }'; then
	echo "ok   walk into the cube stops in front: pos=$pos gap=$gap m"
else echo "FAIL walk into the cube: pos='$pos' gap='$gap'"; grep -E '^(MESH|GAME|DONE|fatal|RUN)' "$T/a.log"; fails=$((fails + 1)); fi
a=$(grep -E '^(GAME pose|DONE)' "$T/a.log" | sed 's/ seconds=.* pos=/ pos=/')
b=$(grep -E '^(GAME pose|DONE)' "$T/b.log" | sed 's/ seconds=.* pos=/ pos=/')
[ -n "$a" ] && [ "$a" = "$b" ] && echo "ok   two replays bit-identical" || { echo "FAIL replays differ"; diff <(echo "$a") <(echo "$b"); fails=$((fails + 1)); }
echo "cpp-collide.test: $fails failed"
exit $((fails > 0))
