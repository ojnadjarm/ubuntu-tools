#!/usr/bin/env bash
# mv-sfx.test.sh: the 4 synthesised SFX (format, -1 dBTP, seed determinism, whoosh centroid arc), camera-dump cue marks, pan/pitch/room placement on synthetic paths.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
near() { awk -v a="$1" -v b="$2" -v e="$3" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=e)}' && echo 1 || echo 0; }
tp() { ffmpeg -hide_banner -nostats -i "$1" -af ebur128=peak=true:framelog=quiet -f null - 2>&1 | awk '/True peak:/{s=1} s&&/Peak:/{print $2; exit}'; }

for k in whoosh riser hit sub-drop; do
  "$BIN/mv-sfx" "$k" --dur 1.5 --seed 7 --out "$FX/$k.wav" >/dev/null 2>&1
  fmt=$(ffprobe -v error -show_entries stream=sample_rate,codec_name,duration_ts -of csv=p=0 "$FX/$k.wav")
  ok "$(is "$fmt" "pcm_s24le,48000,72000")" "$k: 24-bit 48 kHz, 1.5 s exact ($fmt)"
  ok "$(near "$(tp "$FX/$k.wav")" -1 0.1)" "$k: true peak $(tp "$FX/$k.wav") dBTP (-1 +/- 0.1)"
done

"$BIN/mv-sfx" whoosh --dur 1.5 --seed 7 --out "$FX/again.wav" >/dev/null 2>&1
"$BIN/mv-sfx" whoosh --dur 1.5 --seed 8 --out "$FX/other.wav" >/dev/null 2>&1
a=$(sha256sum <"$FX/whoosh.wav") b=$(sha256sum <"$FX/again.wav") c=$(sha256sum <"$FX/other.wav")
ok "$(is "$a" "$b")" "same seed -> identical sha256"
ok "$([[ $a != "$c" ]] && echo 1 || echo 0)" "another seed -> different sha256"

read -r c1 c2 c3 < <(ffmpeg -hide_banner -nostats -i "$FX/whoosh.wav" -af aspectralstats=measure=centroid,ametadata=print:file=- -f null - 2>/dev/null |
  awk -F= '/centroid/{v[n++]=$2} END{for (i=0;i<n;i++) s[int(3*i/n)]+=v[i]; printf "%d %d %d\n", s[0]/(n/3), s[1]/(n/3), s[2]/(n/3)}')
ok "$( ((c2 > 2 * c1 && c2 > 2 * c3)) && echo 1 || echo 0)" "whoosh centroid rises then falls (thirds: $c1 / $c2 / $c3 Hz)"

# Push-in at 30 fps: speed ramps up to frame 20, down to a stop at frame 45, then holds to frame 59.
python3 -I - "$FX" <<'PY'
import json, sys
d = sys.argv[1]
tri = lambda x: x / 20 if x <= 20 else max(0.0, (45 - x) / 25)
y, path = -10.0, []
for k in range(60):
    path.append([0.0, round(y, 5), 1.0])
    y += 0.3 * tri(k + 0.5)
json.dump({"move": "push", "target": [0, 0, 0], "frames": path}, open(f"{d}/push.json", "w"))
json.dump({"move": "push", "target": [0, 0, 0], "frames": [[0, -10 + 0.1 * k, 1] for k in range(31)]}, open(f"{d}/linear.json", "w"))
json.dump({"move": "push", "target": [0, 0, 0], "frames": [[0, -10, 1]] * 20}, open(f"{d}/still.json", "w"))
PY
"$BIN/mv-sfx" cues "$FX/push.json" --fps 30 --out "$FX/cues.json" >"$FX/cues.log" 2>&1
ok "$(is "$(jq -r '[.events[].name] | join(",")' "$FX/cues.json")" "whoosh1,hit1")" "push-in -> one whoosh and one hit"
wf=$(jq '.events[0].frame' "$FX/cues.json") hf=$(jq '.events[1].frame' "$FX/cues.json")
ok "$(near "$wf" 20 1)" "whoosh1 at the fastest frame 20 +/- 1 (frame $wf)"
ok "$(near "$hf" 45 1)" "hit1 at the stop frame 45 +/- 1 (frame $hf)"
ok "$(near "$(jq '.clips.camera.marks.whoosh1' "$FX/cues.json")" "$(echo "$wf / 30" | bc -l)" 0.001)" "marks are seconds at --fps 30"
ok "$(grep -c 'cue:whoosh1-' "$FX/cues.log")" "prints the mv-mix line that centres the whoosh"

"$BIN/mv-sfx" cues "$FX/linear.json" --fps 30 --out "$FX/lin.json" >/dev/null 2>&1
ok "$(is "$(jq -c '[.events[].frame]' "$FX/lin.json")" "[15,30]")" "linear push: whoosh mid-plateau, hit on the last frame"
"$BIN/mv-sfx" cues "$FX/still.json" --out "$FX/still-cues.json" >/dev/null 2>&1
ok "$(is "$(jq '.events | length' "$FX/still-cues.json")" 0)" "still camera -> no cues"

"$BIN/mv-mix" --out "$FX/mix.wav" --duration 3 --cues "$FX/cues.json" --sfx "$FX/hit.wav@cue:hit1" >/dev/null 2>&1
at=$(ffmpeg -hide_banner -nostats -i "$FX/mix.wav" -af silencedetect=n=-40dB:d=0.5 -f null - 2>&1 | awk '/silence_end/{print $5; exit}')
ok "$(near "${at:-0}" "$(jq '.clips.camera.marks.hit1' "$FX/cues.json")" 0.02)" "mv-mix --sfx @cue:hit1 lands at ${at:-none} s"

# Placement (T642): orbits 60 frames at 30 fps around the target, eased; left = angle falling, right = rising.
python3 -I - "$FX" <<'PY'
import json, math, sys
for name, sign in (("left", -1), ("right", 1)):
    fr = []
    for k in range(60):
        a = sign * math.radians(60) * (1 - math.cos(math.pi * k / 59)) / 2
        fr.append([round(10 * math.sin(a), 5), round(-10 * math.cos(a), 5), 1.6])
    json.dump({"move": "orbit", "target": [0, 0, 1], "frames": fr}, open(f"{sys.argv[1]}/orbit-{name}.json", "w"))
PY
lr() { ffmpeg -hide_banner -nostats -i "$1" -af astats=measure_perchannel=RMS_level:measure_overall=none -f null - 2>&1 |
  awk '/RMS level dB/{v[n++]=$NF} END{printf "%.2f\n", 10^((v[0]-v[1])/10)}'; }
for side in left right; do
  "$BIN/mv-sfx" cues "$FX/orbit-$side.json" --fps 30 --out "$FX/o-$side.json" >"$FX/o-$side.log" 2>&1
  pan=$(jq '.events[0].pan' "$FX/o-$side.json")
  "$BIN/mv-sfx" whoosh --dur 1 --pan "$pan" --pitch "$(jq '.events[0].pitch' "$FX/o-$side.json")" --out "$FX/o-$side.wav" >/dev/null 2>&1
  r=$(lr "$FX/o-$side.wav")
  if [[ $side == left ]]; then ok "$(awk -v r="$r" 'BEGIN{print (r > 1.5)}')" "left orbit: pan $pan, L/R energy $r > 1.5"
  else ok "$(awk -v r="$r" 'BEGIN{print (r < 0.67)}')" "right orbit: pan $pan, L/R energy $r < 0.67"; fi
done
ok "$(grep -c -- '--pan 0.8 --pitch' "$FX/o-right.log")" "cues print the whoosh line with --pan/--pitch"
pp=$(jq '.events[0].pitch' "$FX/cues.json") pn=$(jq '.events[0].pan' "$FX/cues.json")
ok "$(awk -v p="$pp" -v q="$pn" 'BEGIN{print (p > 2.5 && p <= 3 && q == 0)}')" "push-in approaches: pitch $pp % (+2.5..3), pan $pn"

cen() { ffmpeg -hide_banner -nostats -i "$1" -af aspectralstats=measure=centroid,ametadata=print:file=- -f null - 2>/dev/null |
  awk -F= '/centroid/{s+=$2; n++} END{printf "%.1f\n", s/n}'; }
"$BIN/mv-sfx" whoosh --dur 1.5 --seed 7 --pitch 3 --out "$FX/up.wav" >/dev/null 2>&1
"$BIN/mv-sfx" whoosh --dur 1.5 --seed 7 --pitch -3 --out "$FX/down.wav" >/dev/null 2>&1
fmt=$(ffprobe -v error -show_entries stream=channels,duration_ts -of csv=p=0 "$FX/up.wav")
r=$(awk -v a="$(cen "$FX/up.wav")" -v b="$(cen "$FX/down.wav")" 'BEGIN{printf "%.3f", a/b}')
ok "$(awk -v r="$r" -v f="$fmt" 'BEGIN{print (r > 1.03 && r < 1.09 && f == "1,72000")}')" "--pitch +3 vs -3: centroid ratio $r (~1.06), mono 1.5 s ($fmt)"

"$BIN/mv-sfx" whoosh --dur 1.5 --seed 7 --room none --out "$FX/none.wav" >/dev/null 2>&1
ok "$(is "$(sha256sum <"$FX/none.wav")" "098635b9ef2500d1fcc9feda8df361992ab5293506c4a59a2f6e1a08ed4be7a1  -")" "--room none = pre-T642 bytes (sha pinned on ffmpeg 8.0.1)"
for room in small hall; do
  "$BIN/mv-sfx" whoosh --dur 1.5 --seed 7 --room "$room" --out "$FX/$room.wav" >/dev/null 2>&1
  "$BIN/mv-sfx" whoosh --dur 1.5 --seed 7 --room "$room" --out "$FX/$room-2.wav" >/dev/null 2>&1
  fmt=$(ffprobe -v error -show_entries stream=channels,duration_ts -of csv=p=0 "$FX/$room.wav")
  ok "$(is "$fmt" "2,$([[ $room == small ]] && echo 100800 || echo 206400)")" "--room $room: stereo, 1.5 s + tail ($fmt)"
  ok "$(is "$(sha256sum <"$FX/$room.wav")" "$(sha256sum <"$FX/$room-2.wav")")" "--room $room: seeded IR, same bytes twice"
  ok "$(near "$(tp "$FX/$room.wav")" -1 0.1)" "--room $room: true peak $(tp "$FX/$room.wav") dBTP"
done
tail=$(ffmpeg -hide_banner -nostats -i "$FX/hall.wav" -af atrim=start=1.55:end=2.3,astats=measure_perchannel=none:measure_overall=RMS_level -f null - 2>&1 | awk '/RMS level dB/{print $NF}')
ok "$(awk -v t="$tail" 'BEGIN{print (t > -70 && t < -30)}')" "hall tail 0.05-0.8 s after the dry ends: $tail dB RMS"
lufs() { ffmpeg -hide_banner -nostats -i "$1" -af "${2:-anull},ebur128" -f null - 2>&1 | awk '/^ +I:/{v=$2} END{print v}'; }
for f in hall small; do
  st=$(lufs "$FX/$f.wav") mo=$(lufs "$FX/$f.wav" "pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1")
  ok "$(near "$st" "$mo" 1)" "--room $f: mono fold-down $mo vs stereo $st LUFS (within 1 dB)"
done

ok "$(is "$(rc "$BIN/mv-sfx" whoosh --room cave --out "$FX/x.wav")" 2)" "--room cave -> rc 2"
ok "$(is "$(rc "$BIN/mv-sfx" whoosh --pitch 5 --out "$FX/x.wav")" 2)" "--pitch 5 -> rc 2"
ok "$(is "$(rc "$BIN/mv-sfx" whoosh --pan 1.5 --out "$FX/x.wav")" 2)" "--pan 1.5 -> rc 2"

echo '{}' >"$FX/bad.json"
ok "$(is "$(rc "$BIN/mv-sfx" cues "$FX/bad.json" --out "$FX/x.json")" 1)" "dump without frames -> rc 1"
ok "$(is "$(rc "$BIN/mv-sfx" whoosh --dur 0 --out "$FX/x.wav")" 2)" "--dur 0 -> rc 2"
ok "$(is "$(rc "$BIN/mv-sfx" boom --out "$FX/x.wav")" 2)" "unknown kind -> rc 2"

echo "mv-sfx.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
