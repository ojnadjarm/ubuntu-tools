#!/usr/bin/env bash
# cpp-ci package: a throwaway game with a glTF scene packs to a .tar.zst that unpacks and wins the replay on lavapipe in a ubuntu:26.04 container with only mesa-vulkan-drivers.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
FIX=$G/tests/fixtures/cpp-play-input.json
IMG=cpp-package-runtime:26.04
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

"$G/scripts/new-cpp-game" "$T/game" > "$T/new.log" 2>&1 || { echo "FAIL new-cpp-game"; cat "$T/new.log"; exit 1; }
python3 "$G/tests/fixtures/make_scene_glb.py" "$T/game/model_lod0.glb" 255,0,0 0,255,0 0,0,255 || { echo "FAIL scene fixture"; exit 1; }
nice -n 10 "$G/scripts/cpp-ci" --stages "configure build package" --out "$T/ci" "$T/game" > "$T/ci.log" 2>&1
S=$T/ci/summary.json
TB=$T/ci/game-0.1.0-linux-x86_64.tar.zst
ok "cpp-ci configure build package pass" '[ "$(jq -r "[.stages[] | .status] | join(\" \")" "$S")" = "pass pass pass" ] || { cat "$T/ci.log"; tail -20 "$T/ci/logs/package-build.log"; false; }'
ok "summary size and sha256 match the tarball" 'jq -e --arg h "$(sha256sum "$TB" | cut -d" " -f1)" --argjson s "$(stat -c %s "$TB")" ".stages.package | .sha256 == \$h and .size_bytes == \$s and .runpath == \"\$ORIGIN/lib\" and .missing_libs == 0" "$S" > /dev/null'
ok "tarball <= 60 MB" '[ "$(stat -c %s "$TB")" -le 62914560 ]'
tar --zstd -tf "$TB" > "$T/list" 2>/dev/null
ok "carries binary, 3 SPIR-V, 3 wavs, glTF scene; no build script" '(for f in game shaders/mesh.vert.spv shaders/mesh.frag.spv shaders/shadow.vert.spv assets/pickup.wav assets/step.wav assets/goal.wav model_lod0.glb; do
	grep -qx "game-0.1.0-linux-x86_64/$f" "$T/list" || { echo "  missing $f"; exit 1; }; done) && ! grep -q make-sfx.sh "$T/list"'
mkdir -p "$T/x" && tar --zstd -xf "$TB" -C "$T/x"
ok "binary stripped" 'file "$T/x/game-0.1.0-linux-x86_64/game" | grep -q ", stripped"'

docker version > "$T/docker.log" 2>&1; dv=$?
if [ $dv = 125 ] && grep -q '^run.sh: skill tests never reach the real docker' "$T/docker.log"; then
	echo "SKIP container cases: run.sh docker shim (real docker: run the file by hand)"
	echo "cpp-package.test: $fails failed"
	exit $((fails > 0))
fi
if ! docker image inspect "$IMG" > /dev/null 2>&1; then
	mkdir -p "$T/img"
	printf 'FROM ubuntu:26.04\nRUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mesa-vulkan-drivers && rm -rf /var/lib/apt/lists/*\n' > "$T/img/Dockerfile"
	nice docker build -q -t "$IMG" "$T/img" > "$T/img.log" 2>&1 || { echo "FAIL image build"; cat "$T/img.log"; exit 1; }
fi
# the host only decompresses (the image has no zstd); tar unpacks inside the container
zstd -dcq "$TB" | timeout 300 docker run --rm -i --network none -v "$FIX:/fix/input.json:ro" \
	-e SDL_VIDEO_DRIVER=offscreen -e SDL_AUDIO_DRIVER=dummy -e VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json "$IMG" bash -c '
	mkdir -p /opt/g && tar -x -C /opt/g && cd / || exit 9
	echo "TOOLS $(command -v cc c++ gcc clang cmake ninja vcpkg | wc -l)"
	echo "LDD_MISSING $(ldd /opt/g/game-0.1.0-linux-x86_64/game | grep -c "not found")"
	/opt/g/game-0.1.0-linux-x86_64/game --frames 100000 --replay /fix/input.json --audio-out /tmp/a.wav
	echo "EXIT $?"; echo "WAV $(stat -c %s /tmp/a.wav 2>/dev/null || echo 0)"' > "$T/run.log" 2>&1
ok "container has no build tools" 'grep -qx "TOOLS 0" "$T/run.log"'
ok "ldd: no missing libs" 'grep -qx "LDD_MISSING 0" "$T/run.log"'
ok "lavapipe replay: GAME win tick 355, exit 0" 'grep -q "^GAME device=\"llvmpipe" "$T/run.log" && grep -q "^GAME win t=.* tick=355$" "$T/run.log" && grep -qx "EXIT 0" "$T/run.log"'
ok "packaged glTF scene loaded" 'grep -q "^MESH source=/opt/g/game-0.1.0-linux-x86_64/model_lod0.glb " "$T/run.log" && grep -q "^SCENE .* draws_lod0=3$" "$T/run.log"'
ok "packaged wavs mixed by miniaudio" '[ "$(sed -n "s/^WAV //p" "$T/run.log")" -gt 1000000 ]'
[ $fails = 0 ] || grep -E '^(TOOLS|LDD|MESH|SCENE|GAME|DONE|EXIT|WAV|fatal)' "$T/run.log"
echo "cpp-package.test: $fails failed"
exit $((fails > 0))
