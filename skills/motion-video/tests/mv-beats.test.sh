#!/usr/bin/env bash
# mv-beats.test.sh: tempo, beat timing, --every/--downbeats/--snap and mv-mix cue reading on ffmpeg click-track fixtures.
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
click() { ffmpeg -hide_banner -loglevel error -y -f lavfi -i "aevalsrc='if(lt(mod(t,$1),0.01),sin(2*PI*1500*t)*exp(-mod(t,$1)*300),0)':s=44100:d=$2" "$3"; }

for bpm in 120 97; do
  p=$(echo "60 / $bpm" | bc -l)
  click "$p" 60 "$FX/c$bpm.wav"
  s=$(date +%s.%N)
  "$BIN/mv-beats" "$FX/c$bpm.wav" --out "$FX/b$bpm.json" 2>/dev/null; r=$?
  secs=$(echo "$(date +%s.%N) - $s" | bc)
  ok "$(is "$r" 0)" "mv-beats $bpm BPM click track -> rc 0"
  ok "$(near "$(jq .tempo "$FX/b$bpm.json")" "$bpm" 0.5)" "$bpm BPM: tempo $(jq .tempo "$FX/b$bpm.json") within 0.5"
  worst=$(jq --argjson p "$p" '[.beats[].t | (. - ((. / $p) | round) * $p) | fabs] | max * 1000' "$FX/b$bpm.json")
  ok "$(near "$worst" 0 15)" "$bpm BPM: worst beat error ${worst} ms within 15"
  ok "$(is "$(jq '.beats | length >= 55 * '"$bpm"' / 60' "$FX/b$bpm.json")" true)" "$bpm BPM: $(jq '.beats | length' "$FX/b$bpm.json") beats cover the track"
  ok "$(near "$secs" 0 3)" "$bpm BPM: 60 s track analysed in ${secs} s (<= 3)"
done

j=$FX/b120.json
ok "$(is "$(jq -r '.beats[2].name' "$j")" beat3)" "beat names are 1-based grid indices"
ok "$(is "$(jq '[.beats[] | .t == $m[0].clips.beats.marks[.name]] | all' --slurpfile m "$j" "$j")" true)" "every beat is a mark in clips.beats.marks (cues.json shape)"
ok "$(is "$(jq '(.onsets | length) > 100 and (.downbeats | length) == 0' "$j")" true)" "onsets listed; no downbeats without --downbeats"

"$BIN/mv-beats" "$FX/c120.wav" --out "$FX/e.json" --every 4 --downbeats 2>/dev/null
ok "$(is "$(jq -r '[.beats[:2][].name] | join(",")' "$FX/e.json")" beat1,beat5)" "--every 4 keeps beat1,beat5,... with stable names"
ok "$(is "$(jq '(.downbeats | length) as $d | ($d >= 28 and $d <= 30) and ([.downbeats[1].t - .downbeats[0].t] | .[0] | . > 1.99 and . < 2.01)' "$FX/e.json")" true)" \
  "--downbeats: one per 4/4 bar, 2 s apart at 120 BPM"

snap=$("$BIN/mv-beats" "$j" --snap 3.1,10.02)
read -r c1 n1 t1 d1 <<<"$(sed -n 1p <<<"$snap")"
read -r c2 n2 t2 d2 <<<"$(sed -n 2p <<<"$snap")"
ok "$(is "$n1 $n2" "beat6 beat20")" "--snap on a beats.json picks the nearest beats ($n1 $n2)"
ok "$( [[ $(near "$t1" 3 0.015) == 1 && $d2 =~ ^-2[0-9]$ ]] && echo 1 || echo 0)" "--snap prints beat time $t1 and delta $d2 ms"

ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=f=880:d=0.05:sample_rate=48000" "$FX/hit.wav"
"$BIN/mv-mix" --out "$FX/mix.wav" --duration 6 --cues "$j" --sfx "$FX/hit.wav@cue:beat8" >/dev/null 2>&1
at=$(ffmpeg -hide_banner -nostats -i "$FX/mix.wav" -af silencedetect=n=-40dB:d=0.5 -f null - 2>&1 | awk '/silence_end/{print $5; exit}')
ok "$(near "${at:-0}" "$(jq '.clips.beats.marks.beat8' "$j")" 0.02)" "mv-mix --sfx @cue:beat8 lands at ${at:-none} s"

ok "$(is "$(rc "$BIN/mv-beats" "$FX/missing.wav")" 2)" "missing input -> rc 2"
ok "$(is "$(rc "$BIN/mv-beats" "$FX/c97.wav" --bogus)" 2)" "unknown option -> rc 2"
ok "$(is "$(MV_BEATS_VENV=$FX/none rc "$BIN/mv-beats" -h)" 3)" "no venv -> rc 3 with the install line"

echo "mv-beats.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
