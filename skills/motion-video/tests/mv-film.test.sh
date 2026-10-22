#!/usr/bin/env bash
# mv-film.test.sh: mv-new --kind film scaffolds, then its build.sh --draft (320x180, 3 s, 12 fps) runs the whole chain: steps timed (wall + steps_cpu), cuts on the beat grid, both aspects VMAF >= 93 and mv-review PASS, build CPU (/usr/bin/time) <= CPU_LIMIT s (75) and wall <= LIMIT s (90) checked only when quiet-gate reads quiet at the start; mv_finish ledgers the build and a red review reaches `pc failures` (HARNESS_HOME sandbox).
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
LIMIT=${LIMIT:-90} CPU_LIMIT=${CPU_LIMIT:-75}
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
export HARNESS_HOME=$FX/harness; unset CREATIVE_CI_LOG
L=$HARNESS_HOME/log/creative-ci.jsonl
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { eval "[[ $* ]]" && echo 1 || echo 0; }

"$HERE/../scripts/mv-new" "$FX/demo" --kind film >/dev/null
P=$FX/demo
ok "$(is "-x $P/build.sh && -f $P/src/Title.tsx && -f $P/logo.svg")" "mv-new film: build.sh, Title.tsx, logo.svg"
ok "$([[ $(jq -r .logo "$P/brand.json") == logo.svg ]] && echo 1 || echo 0)" "brand.json logo defaults to logo.svg"
ok "$(grep -q __NAME__ "$P/build.sh" && echo 0 || echo 1)" "build.sh name filled in"

quiet=$(quiet-gate 2>&1) && quiet=1
t=$(date +%s.%N)
(cd "$P" && MAX_PER_CPU=${MAX_PER_CPU:-4} GATE_WAIT=${GATE_WAIT:-600} /usr/bin/time -f '%U %S' -o "$FX/time" ./build.sh --draft) >"$FX/build.log" 2>&1
rc=$?
wall=$(awk -v a="$t" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b - a}')
[[ $rc == 0 ]] || tail -5 "$FX/build.log"
ok "$([[ $rc == 0 ]] && echo 1 || echo 0)" "build.sh --draft exit 0 (rc $rc)"
B=$P/out/build.json
want='["beats","composite","layout","plate0","plate1","plate2","quality_16x9","quality_9x16","render_wall","review_16x9","review_9x16","sfx_mix","title_16x9","title_9x16"]'
ok "$(jq --argjson w "$want" '(.steps | keys) == $w and ([.steps[]] | all(. > 0 and . < 600))' "$B" 2>/dev/null | grep -qx true && echo 1 || echo 0)" "build.json: 14 timed steps, each 0-600 s"
ok "$(jq '(.steps_cpu | keys) == (.steps | keys - ["render_wall"]) and ([.steps_cpu[]] | all(. >= 0))' "$B" 2>/dev/null | grep -qx true && echo 1 || echo 0)" "build.json steps_cpu: CPU s per timed step $(jq -c '[.steps_cpu.title_16x9, .steps_cpu.title_9x16, .steps_cpu.composite]' "$B" 2>/dev/null)"
ok "$(jq '.review == "PASS" and .aspects["16x9"].review == "PASS" and .aspects["9x16"].review == "PASS"' "$B" 2>/dev/null | grep -qx true && echo 1 || echo 0)" "mv-review PASS on 16x9 and 9x16"
ok "$(jq '[.aspects[].vmaf] | length == 2 and all(. >= 93)' "$B" 2>/dev/null | grep -qx true && echo 1 || echo 0)" "VMAF >= 93 vs lossless ref: $(jq -c '[.aspects[].vmaf]' "$B" 2>/dev/null)"
ok "$(python3 -I - "$B" "$P/out/beats.json" <<'PY'
import json, sys
c, b = json.load(open(sys.argv[1]))["cuts"], json.load(open(sys.argv[2]))
grid = [x["t"] for x in b[c["grid"]]] if c["grid"] != "even" else []
on = all(any(abs(t - g) <= 0.5 / 12 + 1e-6 for g in grid) for t in c["cuts"])
print(1 if len(c["frames"]) == 3 and sum(c["frames"]) == 36 and min(c["frames"]) >= 3 and on else 0)
PY
)" "3 shots, 36 frames (12 fps), cuts within half a frame of a $(jq -r .cuts.grid "$B" 2>/dev/null) time"
ok "$(jq -s 'length == 3 and all(.events | length >= 2)' "$P"/out/cues[0-2].json 2>/dev/null | grep -qx true && echo 1 || echo 0)" "mv-sfx cues: whoosh + hit from each camera dump"
probe() { ffprobe -v error -show_entries stream=codec_type,width,height:format=duration -of json "$1" | jq -c '[([.streams[] | select(.codec_type == "video") | "\(.width)x\(.height)"][0]), ([.streams[].codec_type] | index("audio") != null), (.format.duration | tonumber | . * 10 | round / 10)]'; }
ok "$([[ $(probe "$P/out/demo-16x9.mp4" 2>/dev/null) == '["320x180",true,3]' ]] && echo 1 || echo 0)" "16x9 delivery 320x180, audio, 3 s"
ok "$([[ $(probe "$P/out/demo-9x16.mp4" 2>/dev/null) == '["180x320",true,3]' ]] && echo 1 || echo 0)" "9x16 delivery 180x320, audio, 3 s"
ok "$([[ -z $(find "$P/out" -name '*.png' -o -name '*.mkv' -o -name '*.mov' | head -1) ]] && echo 1 || echo 0)" "lossless intermediates deleted"
cpu=$(tail -1 "$FX/time" 2>/dev/null | awk '{printf "%.1f", $1 + $2}')
if [[ $quiet == 1 ]]; then
  ok "$(jq -r --argjson c "${cpu:-1e9}" --argjson l "$CPU_LIMIT" '.cpu_s > 0 and $c <= $l' "$B" 2>/dev/null | grep -qx true && echo 1 || echo 0)" "draft build CPU ${cpu} s <= ${CPU_LIMIT} s (build.json cpu_s $(jq .cpu_s "$B" 2>/dev/null))"
  ok "$(awk -v w="$wall" -v l="$LIMIT" 'BEGIN{print (w <= l) ? 1 : 0}')" "draft chain wall ${wall} s <= ${LIMIT} s (load $(cut -d' ' -f1 /proc/loadavg))"
else
  ok "$(jq -e '.cpu_s > 0' "$B" >/dev/null 2>&1 && echo 1 || echo 0)" "draft build CPU ${cpu} s not gated: ${quiet#quiet-gate: } (build.json cpu_s $(jq .cpu_s "$B" 2>/dev/null) > 0)"
  ok 1 "draft chain wall ${wall} s not gated: ${quiet#quiet-gate: }"
fi
ok "$(jq -se 'length == 1 and .[0].tool == "mv-build" and .[0].project == "demo" and .[0].ok and (.[0].summary | endswith("-mv-build-demo.json"))' "$L" >/dev/null 2>&1 && echo 1 || echo 0)" "build.sh logs one green creative-ci line (sandbox $([[ $L == "$FX"/* ]] && echo ok || echo LEAK))"
mkdir -p "$FX/red" && cp "$B" "$FX/red/build.json" 2>/dev/null
(source "$HERE/../scripts/mvlib.sh" && mv_finish demo "$FX/red/build.json" "16x9: mv-review black 1x") 2>/dev/null
rc=$?
ok "$([[ $rc == 1 ]] && jq -e '.review == "FAIL" and .fails == ["16x9: mv-review black 1x"]' "$FX/red/build.json" >/dev/null 2>&1 && echo 1 || echo 0)" "mv_finish red review: rc 1, build.json review FAIL + fails"
ok "$(CI_SCRATCH_ROOTS=$FX/none pc failures --since 5m --json 2>/dev/null | jq -e '[.creative[] | select(.tool == "mv-build" and .project == "demo" and .failed == ["16x9:mv-review black 1x"])] | length == 1' >/dev/null && echo 1 || echo 0)" "red film review shows in pc failures --since 5m"
echo "mv-film: $((n - bad))/$n"
[[ $bad == 0 ]]
