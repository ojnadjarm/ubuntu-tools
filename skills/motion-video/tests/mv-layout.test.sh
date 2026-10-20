#!/usr/bin/env bash
# mv-layout.test.sh: plan-level layout check on the T694 hero-film camera dumps (title over robot 0-7 s, unseen 3D title in shot 1), a clean plan, edited copies of it, and build.sh hero .glb scale tracks (synthetic squash, anim-hero.glb, no scale channel, leaf-joint IK-target translation keys, root rotation under a 0.6 y-scale armature), camera line over the on-screen frames with a shared cause/FAIL threshold.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts/mv-layout
FIX=$HERE/fixtures/layout
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
has() { grep -qE "$2" <<<"$1" && echo 1 || echo 0; }
edit() { rm -rf "$TMP/c"; cp -r "$FIX/clean" "$TMP/c"; jq "$1" "$FIX/clean/out/layout.json" >"$TMP/c/out/layout.json"; }

t0=$(date +%s.%N)
o=$("$BIN" "$FIX/hero/out" 2>&1); rc=$?
ms=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%d", (b - a) * 1000}')
ok "$([[ $rc == 1 ]] && echo 1 || echo 0)" "hero: exit 1 (got $rc)"
ok "$(has "$o" '^FAIL title title over subject 0\.00–7\.1[0-9] s \([0-9]+% overlap\)$')" "hero: 2D title over the robot 0-7 s"
ok "$(has "$o" '^FAIL shot 1 has no 3D title')" "hero: shot 1 3D title out of frame"
ok "$( [[ $(grep -c '^FAIL title' <<<"$o") == 1 ]] && echo 1 || echo 0)" "hero: lower third clear of the robot"
ok "$(has "$o" '^n/a: subject\.scale')" "hero: no scale track -> n/a line"
ok "$( ((ms < 2000)) && echo 1 || echo 0)" "hero: ${ms} ms (< 2000)"
o=$("$BIN" "$FIX/hero/out" --aspect 9x16 2>&1)
ok "$(has "$o" '^FAIL title title over subject')" "hero 9x16: title over subject in the centre crop"

o=$("$BIN" "$FIX/clean/out" 2>&1); rc=$?
ok "$([[ $rc == 0 && $o == PASS* ]] && echo 1 || echo 0)" "clean plan: exit 0, one PASS line (rc $rc)"
o=$("$BIN" "$FIX/clean/out" --aspect 9x16 2>&1); rc=$?
ok "$([[ $rc == 0 ]] && echo 1 || echo 0)" "clean plan 9x16: exit 0 (rc $rc)"

edit '.titles[0].rect = [0.4, 0.3, 0.6, 0.5]'
o=$("$BIN" "$TMP/c/out" 2>&1); rc=$?
ok "$( [[ $rc == 1 && $(has "$o" '^FAIL title title over subject 0\.00–0\.8[0-9] s \([0-9]+% overlap\)') == 1 ]] && echo 1 || echo 0)" "centre title rect -> exit 1, overlap FAIL"
edit '.title3d.min = [-0.8, -0.1, 6] | .title3d.max = [0.8, 0.1, 6.5]'
ok "$(has "$("$BIN" "$TMP/c/out" 2>&1)" '^FAIL shot 0 has no 3D title')" "3D title above the frame -> FAIL shot 0"
edit '.subject.scale = [[0, 1, 1, 1], [0.5, 1.8, 1.8, 1]]'
ok "$(has "$("$BIN" "$TMP/c/out" 2>&1)" '^FAIL subject scale x/y 1\.[0-9]+ at 0\.50 s$')" "squash key at 0.5 s -> scale FAIL"
edit '.'
jq '.frames = [.frames[] | [0, -0.6, 12]]' "$FIX/clean/out/cam0.json" >"$TMP/c/out/cam0.json"
ok "$(has "$("$BIN" "$TMP/c/out" 2>&1)" '^FAIL subject scale x/y')" "top-down camera -> foreshortening FAIL"
rm "$TMP"/c/out/cam0.json
"$BIN" "$TMP/c/out" >/dev/null 2>&1; rc=$?
ok "$([[ $rc == 2 ]] && echo 1 || echo 0)" "no cam json -> exit 2 (got $rc)"
rm -rf "$TMP/h"; cp -r "$FIX/hero" "$TMP/h"; rm "$TMP/h/out/spans.json" "$TMP/h/build.sh"
o=$("$BIN" "$TMP/h/out" 2>&1)
ok "$( [[ $(has "$o" '^n/a: spans\.json')$(has "$o" '^n/a: title3d\.shots') == 11 ]] && echo 1 || echo 0)" "missing spans/build.sh -> 2 n/a lines"

glb() {   # out path, 1 = one Squash clip with a 0.6 y-scale key at 0.5 s, 0 = a Slide clip with no scale channel, 2 = a Walk clip keying a leaf Foot joint 0.6 up in a 2-tall rig, 3 = a Spin clip turning root joint Root 90 deg about z at 0.5 s under a [1, 0.6, 1] Armature
  python3 -I - "$1" "$2" <<'PY'
import json, struct, sys
mode = sys.argv[2]
times, path = [0.0, 0.5, 1.0], ("scale", [1, 1, 1, 1, 0.6, 1, 1, 1, 1]) if mode == "1" else ("translation", [0, 0, 0, 0, 0.6 if mode == "2" else 0.2, 0, 0, 0, 0])
if mode == "3":
    path = ("rotation", [0, 0, 0, 1, 0, 0, 0.70710678, 0.70710678, 0, 0, 0, 1])
blob = struct.pack("<3f", *times) + struct.pack(f"<{len(path[1])}f", *path[1])
g = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "Root"}], "buffers": [{"byteLength": len(blob)}],
     "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 12}, {"buffer": 0, "byteOffset": 12, "byteLength": 4 * len(path[1])}],
     "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "SCALAR", "min": [0.0], "max": [1.0]},
                   {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC4" if mode == "3" else "VEC3"}],
     "animations": [{"name": {"1": "Squash", "0": "Slide", "2": "Walk", "3": "Spin"}[mode], "samplers": [{"input": 0, "output": 1}],
                     "channels": [{"sampler": 0, "target": {"node": 1 if mode in "23" else 0, "path": path[0]}}]}]}
if mode == "2":
    g["nodes"] = [{"name": "Root", "children": [1, 2]}, {"name": "Foot"}, {"name": "Head", "translation": [0, 2, 0]}]
    g["skins"] = [{"joints": [0, 1, 2]}]
if mode == "3":
    g["nodes"] = [{"name": "Armature", "scale": [1, 0.6, 1], "children": [1]}, {"name": "Root"}]
    g["skins"] = [{"joints": [1]}]
js = json.dumps(g).encode().ljust((len(json.dumps(g)) + 3) // 4 * 4, b" ")
open(sys.argv[1], "wb").write(b"glTF" + struct.pack("<II", 2, 28 + len(js) + len(blob)) + struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + blob)
PY
}
plan() { edit 'del(.subject.scale)'; printf 'HERO=${HERO:-$PWD/%s}\nCLIPS=(${CLIPS:-%s})\n  MV_MODEL=$HERO MV_MODEL_ANIM=${CLIPS[$i]} mv-render\n' "$1" "$2" >"$TMP/c/build.sh"; }
unset HERO CLIPS MV_MODEL_HEIGHT

plan m.glb Squash; glb "$TMP/c/m.glb" 1
o=$("$BIN" "$TMP/c/out" 2>&1); rc=$?
ok "$( [[ $rc == 1 && $(has "$o" '^FAIL squash 0\.17-0\.67 s: sx/sy 1\.67$') == 1 ]] && echo 1 || echo 0)" "glb 0.6 y-scale key at 0.5 s -> exit 1, FAIL squash 0.17-0.67 s (rc $rc)"
ok "$(has "$o" '^scale: from .*/c/m\.glb \(3 keys\)$')" "glb: scale from the build.sh model, 3 keys"
cp "$HERE/fixtures/anim-hero.glb" "$TMP/a.glb"; plan ../a.glb Bend
o=$("$BIN" "$TMP/c/out" 2>&1); rc=$?
ok "$( [[ $rc == 0 && $(has "$o" '^scale: from .*/a\.glb \(33 keys\)$') == 1 && $o != *'FAIL squash'* ]] && echo 1 || echo 0)" "anim-hero.glb Bend: 4 scale + 2 leaf-joint translation + 27 root-chain rotation keys, no squash, exit 0 (rc $rc)"
plan m.glb Slide; glb "$TMP/c/m.glb" 0
o=$("$BIN" "$TMP/c/out" 2>&1); rc=$?
ok "$( [[ $rc == 0 && $(has "$o" '^scale: glb has no scale channel')$(has "$o" '^camera 0\.00-0\.83 s: lens 40 mm, x/y [0-9.]+-[0-9.]+, 16x9 scale x/y 1\.000: no lens/aspect cause$') == 11 ]] && echo 1 || echo 0)" "no scale channel -> camera line over the 21 on-screen frames 0-0.83 s, no cause (rc $rc)"
ok "$(has "$("$BIN" "$TMP/c/out" --aspect 9x16 --window 0.2-0.4 2>&1)" '^camera 0\.20-0\.40 s: .* 9x16 scale x/y 1\.00[0-9]: no lens/aspect cause$')" "--window 0.2-0.4 9x16: windowed camera line"
jq '.frames = [.frames[] | [0, -0.6, 12]]' "$FIX/clean/out/cam0.json" >"$TMP/c/out/cam0.json"
ok "$(has "$("$BIN" "$TMP/c/out" --window 0-1 2>&1)" '^camera 0\.00-1\.00 s: .*: cause lens/perspective x/y [0-9.]+ at 0\.00 s$')" "no scale channel + top-down camera -> lens/perspective cause named"
plan m.glb Walk; glb "$TMP/c/m.glb" 2
o=$("$BIN" "$TMP/c/out" 2>&1); rc=$?
ok "$( [[ $rc == 1 && $(has "$o" '^FAIL squash [0-9.]+-[0-9.]+ s: Foot keyed off rest by 0\.30 rig heights')$(has "$o" '^scale: from .*/c/m\.glb \(3 keys\)$') == 11 ]] && echo 1 || echo 0)" "leaf-joint Foot translation key 0.3 rig heights -> exit 1, FAIL squash (rc $rc)"
plan m.glb Spin; glb "$TMP/c/m.glb" 3
o=$("$BIN" "$TMP/c/out" 2>&1); rc=$?
ok "$( [[ $rc == 1 && $(has "$o" '^FAIL squash [0-9.]+-[0-9.]+ s: Root shear 2\.78$')$(has "$o" '^scale: from .*/c/m\.glb \(3 keys\)$') == 11 ]] && echo 1 || echo 0)" "root rotation under a 0.6 y-scale armature -> exit 1, FAIL squash Root shear 2.78 (rc $rc)"
plan m.glb Slide; glb "$TMP/c/m.glb" 0
cp "$FIX/hero/out/cam1.json" "$TMP/c/out/cam0.json"; echo '{"starts": [0.0], "frames": [153]}' >"$TMP/c/out/cuts.json"
o=$("$BIN" "$TMP/c/out" 2>&1)
ok "$( [[ $(has "$o" '^camera 0\.00-6\.33 s: .*: note lens/perspective x/y 1\.[2-5][0-9] at [0-9.]+ s$') == 1 && $o != *'cause lens'* && $o != *'FAIL subject scale'* ]] && echo 1 || echo 0)" "T694 crane dump: x/y below 1.6 -> note, not cause, no FAIL"
plan m.glb Missing; glb "$TMP/c/m.glb" 1
ok "$(has "$("$BIN" "$TMP/c/out" 2>&1)" '^n/a: MV_MODEL_ANIM Missing not in .*\(shot 0 rest pose\)$')" "unknown clip -> n/a line"
o=$("$BIN" "$FIX/hero/out" 2>&1)
ok "$( [[ $(has "$o" '^n/a: subject\.scale')$(has "$o" '^scale:') == 10 ]] && echo 1 || echo 0)" "hero fixture, unresolvable MV_MODEL -> old n/a path, no scale line"

echo "mv-layout: $((n - bad))/$n"
((bad == 0))
