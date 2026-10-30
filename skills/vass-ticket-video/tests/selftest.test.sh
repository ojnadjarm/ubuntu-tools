#!/usr/bin/env bash
# Offline selftest: shot list schema, narration unit, redaction, and assemble on a synthetic recording (no browser, no network).
set -u
HERE=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
S=$HERE/scripts
. "$HOME/agents/bin/tests/lib/assert.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FX=$HERE/tests/fixtures

# Schema: the fixture passes, each broken variant names its fault.
node "$S/shotlist.mjs" check "$FX/shots.json" >/dev/null 2>&1; is "fixture shot list passes" "$?" 0
bad() { # bad <name> <python edit of d> <expected text>
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); $2; json.dump(d, open(sys.argv[2],'w'))" "$FX/shots.json" "$T/bad.json"
  out=$(node "$S/shotlist.mjs" check "$T/bad.json" 2>&1); rc=$?
  [ $rc = 1 ] && grep -q -- "$3" <<<"$out" && ok "$1" || nok "$1" "rc=$rc out=$out"
}
bad "missing say rejected" "del d['steps'][0]['say']" "say: the Spanish line"
bad "ws without pick rejected" "d['steps'][1]['ws'][0].pop('pick')" "pick is required"
bad "unknown step key rejected" "d['steps'][0]['clik']='x'" "unknown key clik"
bad "bare selector rejected" "d['steps'][2]['click']='Resumen'" "must start with"
bad "bare wait selector rejected" "d['steps'][0]['wait']='Netas'" "must start with"
bad "phase must be antes|despues" "d['phase']='after'" "phase: antes|despues"
bad "front step needs a user" "d.pop('front_user')" "needs front_user"
bad "only the {hl} cue" "d['steps'][0]['say']='{x}hola'" "only cue mark"

# Unit: one edge clip per step, Alvaro.
node "$S/shotlist.mjs" unit "$FX/shots.json" > "$T/unit.json"
is "unit: engine edge, voice es" "$(python3 -c 'import json,sys;u=json.load(open(sys.argv[1]));print(u["voice"]["engine"],u["voice"]["voice"])' "$T/unit.json")" "edge es"
is "unit: clip per step" "$(python3 -c 'import json,sys;print(",".join(c["id"] for c in json.load(open(sys.argv[1]))["clips"]))' "$T/unit.json")" "s1,s2,s3"

# Step order: a ws step fetches at its place, after earlier UI steps changed the data (T1432: 9.1 shown instead of 6.5).
cat > "$T/order.mjs" <<EOF
import { runSteps } from '$S/runner.mjs';
const log = []; let t = 0; let baremo = 9.1;
const d = {
  now: () => t, wait: async (ms) => { if (ms > 0) t += ms / 1000; },
  clip: () => ({ duration: 1, marks: {} }),
  act: async (a) => { if (a.click) { log.push('click ' + a.click); baremo = 6.5; } },
  fetchWs: async (jobs) => { log.push('fetch ' + jobs[0].fn); return [{ result: { baremo } }]; },
  showWs: async (step, data) => log.push('show ' + data[0].result.baremo),
  apply: async () => {}, still: async () => {},
};
await runSteps([{ say: 'a', click: 'button:Guardar' }, { say: 'b', ws: [{ fn: 'f', user: 'u', pick: ['baremo'] }] }], d);
console.log(log.join(' | '));
EOF
is "ws step fetches after the earlier UI step" "$(node "$T/order.mjs")" "click button:Guardar | fetch f | show 6.5"
ev "vass-video makes no ws call before recording" "! grep -q 'docker exec' '$S/vass-video'"

# Redaction of Playwright errors.
r=$(node -e "import('$S/shotlist.mjs').then(m=>console.log(m.redact(new Error('GET x cookie=a eyJhbGciOi.eyJzdWIi.c2ln wstoken=0123abcd&x=1\nheaders...'))))")
ok_r=1; grep -q "eyJhbGciOi\|0123abcd\|headers" <<<"$r" && ok_r=0
truthy "redact: JWT and wstoken gone, one line" $ok_r

# Assemble a synthetic recording: 3 steps, 1.5 s clips, with stills.
W=$T/work; mkdir -p "$W/vo/audio"
ffmpeg -v error -f lavfi -i testsrc=size=1280x720:rate=25:duration=9 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 "$W/raw.webm"
for i in 1 2 3; do
  ffmpeg -v error -f lavfi -i sine=frequency=$((300 * i)):duration=1.5 -c:a aac "$W/vo/audio/s$i.m4a"
  ffmpeg -v error -f lavfi -i color=c=white:size=1280x720 -frames:v 1 "$W/still-$i-shot$i.png"
done
python3 - "$FX/shots.json" "$W" <<'PY'
import json, sys
shots = json.load(open(sys.argv[1])); clips = {}
for i, st in enumerate(shots["steps"], 1):
    toks = st["say"].replace("{hl}", "").split()
    clips[f"s{i}"] = {"duration": 1.5, "marks": {}, "words": [{"w": w, "s": 0.1 + k * 0.1, "e": 0.18 + k * 0.1} for k, w in enumerate(toks)]}
json.dump({"clips": clips}, open(f"{sys.argv[2]}/vo/cues.json", "w"))
json.dump({"s1": 1.0, "s2": 3.2, "s3": 5.4, "end": 7.6}, open(f"{sys.argv[2]}/marks.json", "w"))
PY
out=$(python3 "$S/assemble.py" "$FX/shots.json" "$W" "$T/out" --source "$FX/shots.json" --no-review 2>&1); rc=$?
is "assemble exits 0" "$rc" 0
mp4=$T/out/selftest-antes.mp4
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4" 2>/dev/null)
ev "mp4 trimmed to first line - 0.4 s .. end (7.0 s)" "python3 -c 'import sys; sys.exit(abs(float(\"${dur:-0}\") - 7.0) > 0.15)'"
is "mp4 has audio" "$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$mp4")" aac
ev "captions never overlap" "python3 - '$W/captions.srt' <<'PY'
import re, sys
t = [tuple(sum(float(x) * m for x, m in zip(re.split('[:,]', s), (3600, 60, 1, .001))) for s in l.split(' --> '))
     for l in open(sys.argv[1]) if '-->' in l]
sys.exit(not t or any(a[1] > b[0] or a[0] >= a[1] for a, b in zip(t, t[1:])))
PY"
ev "first caption starts at 0.5 s (mark 1.0 - head 0.4 + word 0.1)" "grep -q '^00:00:00,500 -->' '$W/captions.srt'"
is "stills named <phase>-NN-<slug>" "$(ls "$T/out" | grep png | tr '\n' ' ')" "antes-01-shot1.png antes-02-shot2.png antes-03-shot3.png "
is "guion has a line per step" "$(grep -c '^[0-9]\. \[' "$T/out/guion-antes.md")" 3
ev "guion strips the cue mark" "! grep -q '{hl}' '$T/out/guion-antes.md'"
ev "index links the video" "grep -q \"src='selftest-antes.mp4'\" '$T/out/index.html'"
ev "guion names its shot list" "grep -q '^Shot list: .*fixtures/shots.json' '$T/out/guion-antes.md'"

# Después: no steps -> the antes steps from guion-antes.md, new lines, optional recall, no length limit.
dsp() { python3 -c "import json,sys; d={'ticket':'selftest','phase':'despues','recall':'Antes salía otro valor.','say':['Ahora la tarjeta {hl}coincide.',None,'Objetivos igual.']}; $1; json.dump(d, open(sys.argv[1],'w'))" "$T/d.json"; }
dsp "pass"
node "$S/shotlist.mjs" resolve "$T/d.json" "$T/out" > "$T/dr.json" 2>"$T/dr.err"; is "despues resolves from guion-antes.md" "$?" 0
is "despues: antes screens reused, null step dropped" "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(len(d["steps"]),d["steps"][0]["go"],d["steps"][1]["click"],d["front_user"])' "$T/dr.json")" "2 /results/summary link:Objetivos alumno@example.invalid"
is "despues: recall first, then the new line" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["steps"][0]["say"])' "$T/dr.json")" "Antes salía otro valor. Ahora la tarjeta {hl}coincide."
is "despues: antes overlay not carried over" "$(python3 -c 'import json,sys;print("overlay" in json.load(open(sys.argv[1]))["steps"][1])' "$T/dr.json")" False
dsp "d['say']=[None,'Ahora el servicio coincide.','Objetivos igual.']"
node "$S/shotlist.mjs" resolve "$T/d.json" "$T/out" > "$T/dr.json" 2>"$T/dr.err"
is "despues: a dropped step's navigation runs silently first" "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["steps"][0]["pre"][0]["go"], "say" in d["steps"][0]["pre"][0])' "$T/dr.json")" "/results/summary False"
dsp "d['recall']='Antes ' + 'muy ' * 40 + 'mal.'"
node "$S/shotlist.mjs" resolve "$T/d.json" "$T/out" >/dev/null 2>"$T/dr.err"; is "despues: long recall accepted" "$?" 0
dsp "d['say'][0]='Ahora ' + 'muy ' * 30 + 'bien.'"
node "$S/shotlist.mjs" resolve "$T/d.json" "$T/out" >/dev/null 2>"$T/dr.err"; is "despues: longer than antes accepted" "$?" 0
dsp "d['say']=d['say'][:2]"
node "$S/shotlist.mjs" resolve "$T/d.json" "$T/out" >/dev/null 2>"$T/dr.err"; ev "despues needs one line per antes step" "[ $? = 1 ] && grep -q 'list of 3 lines' '$T/dr.err'"
dsp "pass"
node "$S/shotlist.mjs" resolve "$T/d.json" "$T/empty" >/dev/null 2>"$T/dr.err"; ev "despues without guion-antes.md explains" "[ $? = 1 ] && grep -q 'run the antes video first' '$T/dr.err'"

# Review gate: frozen and near-legal levels are expected on UI screens; anything else fails.
g=$(python3 -c "import sys; sys.path.insert(0, '$S'); import assemble as a
print(a.review_ok({'fails': ['frozen 8x', 'levels Y 10-249 brng 0.0023']})[0], a.review_ok({'fails': ['frozen 2x', 'black 3.0s']})[0])")
is "review gate: expected flags pass, black fails" "$g" "True False"

# CLI.
"$S/vass-video" >/dev/null 2>&1; is "vass-video without args: usage 64" "$?" 64
"$S/vass-video" --check "$FX/shots.json" >/dev/null 2>&1; is "vass-video --check" "$?" 0
exit $bad
