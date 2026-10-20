#!/usr/bin/env bash
# mv-trailer.test.sh: mv-new --kind trailer --game on fixtures/trailer-game (a stub replaying one recorded run; MV_TRAILER_FULL=1: a throwaway cpp-vulkan game built and replayed), build.sh --draft: 3 replay windows round pickups/win as plates, game audio under the music, both aspects VMAF >= 93 and mv-review PASS (PSE), steps_cpu per timed step, in <= LIMIT s (90).
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
LIMIT=${LIMIT:-90}
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
export HARNESS_HOME=$FX/harness; unset CREATIVE_CI_LOG
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
yes() { "$@" >/dev/null 2>&1 && echo 1 || echo 0; }

if [[ ${MV_TRAILER_FULL:-0} == 1 ]]; then
  G=$FX/game EVENTS=4
  "$HERE/../../gamedev/scripts/new-cpp-game" --build "$G" >"$FX/game.log" 2>&1
  ok "$(yes test -x "$G/build/dev/game" -a -f "$G/input/trailer.json")" "throwaway game built with input/trailer.json"
else
  G=$HERE/fixtures/trailer-game EVENTS=$(grep -cE '^GAME (pickup|win) ' "$G/rec/game.log")
  ok "$(yes test -x "$G/build/dev/game" -a -f "$G/input/trailer.json")" "fixture game stub with input/trailer.json"
fi
ok "$("$HERE/../scripts/mv-new" "$FX/nogame" --kind trailer >/dev/null 2>&1 && echo 0 || echo 1)" "mv-new --kind trailer without --game refuses"
"$HERE/../scripts/mv-new" "$FX/tr" --kind trailer --game "$G" >/dev/null
P=$FX/tr
ok "$(yes grep -q "^GAME=\${GAME:-$G}" "$P/build.sh")" "build.sh GAME filled in"

t=$(date +%s.%N)
(cd "$P" && MAX_PER_CPU=${MAX_PER_CPU:-4} GATE_WAIT=${GATE_WAIT:-600} ./build.sh --draft) >"$FX/build.log" 2>&1
rc=$?
wall=$(awk -v a="$t" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b - a}')
[[ $rc == 0 ]] || tail -5 "$FX/build.log"
ok "$([[ $rc == 0 ]] && echo 1 || echo 0)" "build.sh --draft exit 0 (rc $rc)"
B=$P/out/build.json W=$P/out/windows.json
want='["beats","composite","plates","quality_16x9","quality_9x16","render_wall","review_16x9","review_9x16","sfx_mix","title_16x9","title_9x16"]'
ok "$(yes jq -e --argjson w "$want" '(.steps | keys) == $w and ([.steps[]] | all(. > 0 and . < 600))' "$B")" "build.json: 11 timed steps (one game plates step), each 0-600 s"
ok "$(yes jq -e '(.steps_cpu | keys) == (.steps | keys - ["render_wall"]) and ([.steps_cpu[]] | all(. >= 0))' "$B")" "build.json steps_cpu: CPU s per timed step $(jq -c '[.steps_cpu.title_16x9, .steps_cpu.title_9x16, .steps_cpu.composite]' "$B" 2>/dev/null)"
ok "$(yes jq -e '.review == "PASS" and ([.aspects[] | .review == "PASS" and .vmaf >= 93] | length == 2 and all)' "$B")" "mv-review PASS, VMAF >= 93: $(jq -c '[.aspects[].vmaf]' "$B" 2>/dev/null)"
ok "$(yes jq -e -s '[.[] | .pse.general_max <= 3 and .pse.red_max <= 3] | length == 2 and all' "$P"/out/tr-16x9.review.json "$P"/out/tr-9x16.review.json)" "PSE: <= 3 flashes/s on both aspects"
ok "$(yes jq -e --argjson e "$EVENTS" '(.events | length) == $e and (.frames | length) == 3 and ([.frames[] | length] | add) == 36
  and ([range(3) as $i | .starts[$i] <= .picked[$i] and .picked[$i] < .starts[$i] + .ticks[$i]] | all)
  and .starts[0] + .ticks[0] <= .starts[1] and .starts[1] + .ticks[1] <= .starts[2]' "$W")" "3 ordered windows, each holding a pickup/win tick, 36 frames: $(jq -c .starts "$W" 2>/dev/null)"
ok "$([[ $(grep -c '^out/game[0-2]\.wav@' "$P/out/sfx.list" 2>/dev/null) == 3 ]] && echo 1 || echo 0)" "game audio: 3 window stems in the mix"
ok "$(ffmpeg -hide_banner -nostats -i "$P/out/game.wav" -af volumedetect -f null - 2>&1 | awk '/max_volume/ {print ($5 > -40) ? 1 : 0}')" "game audio not silent"
probe() { ffprobe -v error -show_entries stream=codec_type,width,height:format=duration -of json "$1" | jq -c '[([.streams[] | select(.codec_type == "video") | "\(.width)x\(.height)"][0]), ([.streams[].codec_type] | index("audio") != null), (.format.duration | tonumber | . * 10 | round / 10)]'; }
ok "$([[ $(probe "$P/out/tr-16x9.mp4" 2>/dev/null) == '["320x180",true,3]' ]] && echo 1 || echo 0)" "16x9 delivery 320x180, audio, 3 s"
ok "$([[ $(probe "$P/out/tr-9x16.mp4" 2>/dev/null) == '["180x320",true,3]' ]] && echo 1 || echo 0)" "9x16 delivery 180x320, audio, 3 s"
ok "$([[ ! -e $P/out/cap && -z $(find "$P/out" -name '*.png' -o -name '*.mkv' -o -name '*.mov' | head -1) ]] && echo 1 || echo 0)" "captures and lossless intermediates deleted"
ok "$(awk -v w="$wall" -v l="$LIMIT" 'BEGIN{print (w <= l) ? 1 : 0}')" "draft chain wall ${wall} s <= ${LIMIT} s (load $(cut -d' ' -f1 /proc/loadavg))"
echo "mv-trailer: $((n - bad))/$n"
[[ $bad == 0 ]]
