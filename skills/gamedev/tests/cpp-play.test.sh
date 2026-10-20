#!/usr/bin/env bash
# cpp-vulkan playable scene: build a throwaway copy, replay the 10 s input fixture headless (weston, Iris Xe) twice; same win tick and pose, record round-trip.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ -x "${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}/vcpkg" ] || { echo "SKIP needs vcpkg (install.sh --gamedev)"; exit 0; }
FIX=$G/tests/fixtures/cpp-play-input.json
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$G/scripts/new-cpp-game" --build "$T/game" > "$T/build.log" 2>&1 || { echo "FAIL build"; tail -20 "$T/build.log"; exit 1; }
fails=0
play() {  # log, game args...; 320x180: the pose needs no pixels (lavapipe ~5x faster)
	local log=$1; shift
	"$G/scripts/cpp-vk-run.sh" --size 320x180 --frames 100000 "$T/game/build/dev/game" "$@" > "$log" 2>&1
}
expect() {  # name, log, want-win-tick, want "x y z yaw pitch"
	local name=$1 log=$2 want_win=$3 want=$4 pose
	pose=$(sed -n 's/^GAME pose x=\(\S*\) y=\(\S*\) z=\(\S*\) yaw=\(\S*\) pitch=\(\S*\) ticks=600 pickups=3 win_tick=\([0-9-]*\)$/\1 \2 \3 \4 \5 \6/p' "$log")
	if [ -n "$pose" ] && grep -q "^GAME win t=.* tick=$want_win\$" "$log" && grep -q 'validation_errors=0 ' "$log" \
		&& awk -v got="$pose" -v want="$want $want_win" 'BEGIN { n = split(got, g); split(want, w); if (n != 6) exit 1
			for (i = 1; i <= 6; i++) if ((g[i] - w[i]) ^ 2 > 1e-8) exit 1 }'; then echo "ok   $name"
	else echo "FAIL $name: pose '$pose'"; grep -E '^(GAME|DONE|fatal|RUN)' "$log"; fails=$((fails + 1)); fi
}
# T654: Jolt collision (wall padding 0.02 m, capsule 0.3 m) moved the win from tick 355 to 353; same tape.
want_pose="2.829538 0.800000 3.095301 -0.750901 -0.120000"
play "$T/a.log" --replay "$FIX" --record "$T/rec.json"
expect "fixture replay wins at tick 353" "$T/a.log" 353 "$want_pose"
[ "$(grep -c '^GAME pickup' "$T/a.log")" = 3 ] && echo "ok   3 pickups" || { echo "FAIL pickups"; fails=$((fails + 1)); }
play "$T/b.log" --replay "$T/rec.json"
expect "recorded tape replays identically" "$T/b.log" 353 "$(sed -n 's/^GAME pose x=\(\S*\) y=\(\S*\) z=\(\S*\) yaw=\(\S*\) pitch=\(\S*\) .*/\1 \2 \3 \4 \5/p' "$T/a.log")"
echo "cpp-play.test: $fails failed"
exit $((fails > 0))
