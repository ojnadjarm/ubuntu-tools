#!/usr/bin/env bash
# cpp-vulkan audio: build a throwaway copy, render the mix offline (--audio-out, no device) for the 10 s fixture and two short tapes; pickup onsets match GAME pickup ticks, stereo pan follows the pickup side.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ -x "${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}/vcpkg" ] || { echo "SKIP needs vcpkg (install.sh --gamedev)"; exit 0; }
FIX=$G/tests/fixtures/cpp-play-input.json
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$G/scripts/new-cpp-game" --build "$T/game" > "$T/build.log" 2>&1 || { echo "FAIL build"; tail -20 "$T/build.log"; exit 1; }
fails=0
play() {  # name, tape; 320x180: the mix needs no pixels (lavapipe ~5x faster)
	"$G/scripts/cpp-vk-run.sh" --size 320x180 --frames 100000 "$T/game/build/dev/game" --replay "$2" --audio-out "$T/$1.wav" > "$T/$1.log" 2>&1
}
tape() {  # name, ticks strafing (move_x), ticks walking backwards; pickup 0 sits 0.7 m behind the start pose
	python3 -c 'import json, sys; s, b = int(sys.argv[2]), int(sys.argv[3]); r = [[float(sys.argv[1]), 0, 0, 0, 0]] * abs(s) + [[0, -1, 0, 0, 0]] * b + [[0, 0, 0, 0, 0]] * 40
json.dump({"tick_hz": 60, "fields": ["move_x", "move_z", "look_yaw", "look_pitch", "jump"], "ticks": r}, open(sys.argv[4], "w"))' "$2" "$3" "$4" "$T/$1.json"
}
# analyse WAV [log]: prints "onsets=<ticks> pickups=<ticks> left=<E> right=<E>" for the band above 1.2 kHz (pickup chime only)
analyse() {
	python3 -I - "$@" <<-'PY'
	import re, sys, wave
	import numpy as np
	w = wave.open(sys.argv[1]); n = w.getnframes()
	assert w.getframerate() == 48000 and w.getnchannels() == 2
	x = np.frombuffer(w.readframes(n), np.int16).reshape(-1, 2) / 32768.0
	X = np.fft.rfft(x, axis=0); X[np.fft.rfftfreq(n, 1 / 48000) < 1200] = 0
	hi = np.fft.irfft(X, n=n, axis=0)[: n // 800 * 800]
	e = (hi ** 2).reshape(-1, 800, 2).sum(1)
	tot = e.sum(1); th = 0.05 * tot.max()
	on = [i + 1 for i in range(len(tot)) if tot[i] > th and (i == 0 or tot[i - 1] <= th)]
	picks = re.findall(r"^GAME pickup n=\d+ tick=(\d+)$", open(sys.argv[2]).read(), re.M)
	print("onsets=%s pickups=%s left=%.3f right=%.3f ticks=%d" % (",".join(map(str, on)), ",".join(picks), e[:, 0].sum(), e[:, 1].sum(), n // 800))
	PY
}
play fixture "$FIX"
r=$(analyse "$T/fixture.wav" "$T/fixture.log"); echo "     fixture $r"
python3 -c 'import sys; f = dict(kv.split("=") for kv in sys.argv[1].split()); on = [int(t) for t in f["onsets"].split(",") if t]; pk = [int(t) for t in f["pickups"].split(",") if t]
sys.exit(not (len(pk) == 3 and len(on) == 3 and all(abs(a - b) <= 1 for a, b in zip(on, pk)) and f["ticks"] == "600"))' "$r" \
	&& echo "ok   3 pickup onsets within 1 frame of GAME pickup, 600 ticks of mix" || { echo "FAIL onsets"; fails=$((fails + 1)); }
tape behind-left 1 6 14; tape behind-right -1 6 14
for side in behind-left behind-right; do play "$side" "$T/$side.json"; done
l=$(analyse "$T/behind-left.wav" "$T/behind-left.log"); r=$(analyse "$T/behind-right.wav" "$T/behind-right.log")
echo "     behind-left $l"; echo "     behind-right $r"
python3 -c 'import sys; L, R = (dict(kv.split("=") for kv in a.split()) for a in sys.argv[1:])
ok = L["pickups"] and R["pickups"] and float(L["left"]) > 2 * float(L["right"]) and float(R["right"]) > 2 * float(R["left"])
sys.exit(not ok)' "$l" "$r" && echo "ok   left/right energy flips with the pickup side (> 2x)" || { echo "FAIL pan"; fails=$((fails + 1)); }
grep -q 'validation_errors=0 ' "$T/fixture.log" && echo "ok   validation clean" || { echo "FAIL validation"; fails=$((fails + 1)); }
echo "cpp-audio.test: $fails failed"
exit $((fails > 0))
