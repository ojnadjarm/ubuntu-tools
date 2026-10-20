#!/usr/bin/env bash
# mv-report.test.sh: one self-contained review page from mv-review + mv-quality + build.json + cues.json on a 3 s synthetic cut (mktemp, deleted on exit).
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-report-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
has() { grep -q -- "$1" "$2" && echo 1 || echo 0; }
TAG="setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709"

ffmpeg -hide_banner -loglevel error -y -threads 4 -f lavfi -i "testsrc2=s=320x180:r=30:d=3" -f lavfi -i "sine=f=440:d=3" \
  -vf "drawbox=c=white:t=fill:enable='between(t,1,2)*lt(mod(t*5,1),0.5)',format=yuv420p,$TAG" \
  -c:v libx264 -preset ultrafast -threads 4 -c:a aac -shortest "$FX/ref.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$FX/ref.mp4" -c:v libx264 -crf 38 -preset ultrafast -threads 4 -c:a copy "$FX/cut.mp4"
O=$FX/out
"$BIN/mv-review" "$FX/cut.mp4" --out "$O" >/dev/null 2>&1
"$BIN/mv-quality" "$FX/ref.mp4" "$FX/cut.mp4" --json >"$O/quality.json" 2>/dev/null
echo '{"name":"cut","seconds":3,"cuts":{"cuts":[1.0,2.0]},"steps":{"render_wall":4.2,"encode_16x9":1.1},"review":"FAIL","fails":["16x9: flash"]}' >"$O/build.json"
echo '{"clips":{"vo":{"marks":{"hit":0.5,"logo":2.4}}}}' >"$O/cues.json"

ok "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(int(d['pse']['general_per_s'][1] > 3 and len(d['loudness_curve']) >= 25 and d['sheet_cols'] == 10))" "$O/cut.review.json")" \
  "mv-review writes per-second flashes, loudness curve, sheet grid"
"$BIN/mv-report" "$O" >"$FX/r.log" 2>&1; rc=$?
H=$O/cut.report.html
ok "$([[ $rc == 0 && -s $H ]] && echo 1 || echo 0)" "mv-report OUTDIR -> cut.report.html ($(wc -c <"$H" 2>/dev/null) B)"
ok "$(grep -Eqi '(src|href)="https?:|url\(https?:|@import|<script|<link ' "$H" && echo 0 || echo 1)" "self-contained: no network fetch, no script"
ok "$(python3 -c "import re,sys; s=open(sys.argv[1]).read(); r=re.findall(r'<b class=\"(FAIL|PASS|INFO)\">', s); print(int(r and r[0] == 'FAIL' and r == sorted(r, key=['FAIL','PASS','INFO'].index)))" "$H")" "FAIL rows on top"
if [[ -x ${MV_VMAF:-$HOME/.local/opt/mv-quality/vmaf} ]]; then
  ok "$([[ $(grep -o '<svg viewBox="0 0 3' "$H" | wc -l) == 3 ]] && grep -q 'class="m"' "$H" && grep -q 'class="bar over"' "$H" && echo 1 || echo 0)" "3 lanes on one 3 s axis: LUFS M/S, flashes over limit, VMAF"
  ok "$([[ $(grep -o 'class="cut"' "$H" | wc -l) == 6 && $(grep -o 'class="cue"' "$H" | wc -l) == 6 ]] && echo 1 || echo 0)" "2 cut + 2 cue marks on each of 3 lanes"
else
  echo "SKIP needs vmaf (Netflix vmaf CLI) for the VMAF lane: 2 lane cases"
fi
ok "$([[ $(grep -o 'href="../cut.mp4#t=[0-9]*"' "$H" | wc -l) == 3 ]] && grep -q 'data:image/jpeg;base64' "$H" && echo 1 || echo 0)" "3 sheet thumbnails link to their second"
ok "$(has 'render_wall' "$H")" "build step times"
ok "$(grep -q 'class="cpu"' "$H" && echo 0 || echo 1)" "build.json without steps_cpu -> no CPU block"
python3 - "$O/build.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d['steps_cpu'] = {'beats': 1.8, 'composite': 1263.2, 'encode_16x9': 269.2, 'encode_9x16': 280.2, 'hdr10': 1239.8, 'plate0': 1143.8, 'plate1': 976.4,
                  'plate2': 973.2, 'quality_16x9': 83.1, 'quality_9x16': 63.1, 'review_16x9': 3.6, 'review_9x16': 3.6, 'sfx_mix': 6.8, 'title_16x9': 7.6, 'title_9x16': 8.6}
d['steps']['composite'] = 172.8; d['cpu_s'] = 7304.8
json.dump(d, open(p, 'w'))
PY
"$BIN/mv-report" "$O" >/dev/null 2>&1
ok "$([[ $(grep -o '<tr class="c">' "$H" | wc -l) == 15 ]] && grep -q '<tr class="c untimed"><th scope="row">untimed</th><td>980.8</td><td>-</td>' "$H" && grep -q '<th scope="row">composite</th><td>1263.2</td><td>172.8</td>' "$H" && echo 1 || echo 0)" \
  "T694 steps_cpu -> 15 CPU rows with wall + untimed 980.8"
ok "$(grep -q '<th scope="col">prev</th>' "$H" && echo 0 || echo 1)" "no .builds history -> no prev/delta columns"
mkdir "$FX/.builds"
echo '{"draft":false,"cpu_s":650,"steps_cpu":{"composite":100,"plate0":500,"encode_16x9":50}}' >"$FX/.builds/20261019T000000Z.json"
echo '{"draft":true,"cpu_s":20,"steps_cpu":{"composite":10,"plate0":10}}' >"$FX/.builds/20261020T000000Z.json"
python3 - "$O/build.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d['steps_cpu'] = {'composite': 200, 'plate0': 510, 'hdr10': 40}; d['cpu_s'] = 750
json.dump(d, open(p, 'w'))
PY
cp "$O/build.json" "$FX/.builds/20261021T000000Z.json"
echo '{"draft":false,"chain":true,"cpu_s":90,"steps_cpu":{"composite":80}}' >"$FX/.builds/20261020T120000Z-42.json"
"$BIN/mv-report" "$O" >"$FX/r.log" 2>&1
ok "$(grep -qx 'mv-report: prev: 20261019T000000Z.json (draft false, chain false)' "$FX/r.log" && echo 1 || echo 0)" "full build skips the newer chain build: prints prev: <file> (draft, chain)"
ok "$(python3 -c "import re,sys; s=open(sys.argv[1]).read(); r=re.findall(r'<tr class=\"c ?([a-z ]*)\"><th scope=\"row\">(\w+)</th><td>([^<]*)</td><td>([^<]*)</td><td class=\"d\">(.*?)</td>', s)
print(int([x[:4] for x in r] == [('grew', 'composite', '200', '100'), ('', 'plate0', '510', '500'), ('new', 'hdr10', '40', '-'), ('gone', 'encode_16x9', '-', '50')] and r[0][4].startswith('+100.0 ')))" "$H")" \
  "prev build: composite 100 -> 200 grew (first), hdr10 new, encode_16x9 gone; draft build and own copy skipped"
ok "$(has 'cpu_s 750 vs 650 (+15.4%), previous build 20261019T000000Z' "$H")" "totals line cpu_s now vs prev (+%)"
jq '. + {chain: true}' "$O/build.json" >"$FX/b.json" && cp "$FX/b.json" "$O/build.json"
"$BIN/mv-report" "$O" >"$FX/r.log" 2>&1
ok "$(grep -qx 'mv-report: prev: 20261020T120000Z-42.json (draft false, chain true)' "$FX/r.log" && grep -q 'previous build 20261020T120000Z-42' "$H" && echo 1 || echo 0)" "chain build compares only with a chain build (<UTC>-<pid> name read)"
rm "$FX/.builds/20261020T120000Z-42.json"
"$BIN/mv-report" "$O" >"$FX/r.log" 2>&1
ok "$(grep -qx 'mv-report: no comparable build' "$FX/r.log" && grep -q '<p class="notes">no comparable build</p>' "$H" && ! grep -q '<th scope="col">prev</th>' "$H" && echo 1 || echo 0)" "chain build vs full history only -> no comparable build, no delta"
jq 'del(.chain)' "$O/build.json" >"$FX/b.json" && cp "$FX/b.json" "$O/build.json"
echo '{"cpu_s":700,"steps_cpu":{"composite":150}}' >"$FX/.builds/20261022T000000Z-999.json"
echo '{"cpu_s":710,"steps_cpu":{"composite":160}}' >"$FX/.builds/20261022T000000Z-1000.json"
echo '{"cpu_s":5}' >"$FX/.builds/20261023T000000Z.json"
cp "$O/cut.review.json" "$O/cut-9x16.review.json"
"$BIN/mv-report" "$O" >"$FX/r.log" 2>&1
ok "$([[ $(grep -c 'prev:' "$FX/r.log") == 1 ]] && grep -qx 'mv-report: prev: 20261022T000000Z-1000.json (draft false, chain false)' "$FX/r.log" && echo 1 || echo 0)" \
  "history by (UTC, int pid): -1000 after -999; no-steps_cpu build skipped; prev: once for 2 aspects"
rm "$O/cut-9x16.review.json" "$O/cut-9x16.report.html"
echo '{"cpu_s":300,"steps_cpu":{"composite":100,"encode_16x9":80,"encode_9x16":80}}' >"$FX/.builds/20261024T000000Z.json"
"$BIN/mv-report" "$O" >/dev/null 2>&1
ok "$(grep -q '<tr class="c"><th scope="row">composite</th><td>200</td><td>100</td>' "$H" && grep -q '<tr class="c gone"><th scope="row">encode_9x16</th>' "$H" && ! grep -q 'class="c grew"' "$H" && echo 1 || echo 0)" \
  "encode_* absorbed by composite (200 vs 100 + 160 gone encode_*) -> gone rows, no grew"
echo '{"cpu_s":7304.8,"steps_cpu":{"composite":1263.2,"encode_16x9":269.2,"encode_9x16":280.2,"hdr10":1239.8,"plate0":1143.8}}' >"$FX/.builds/20261025T000000Z.json"
cpu() { jq --argjson c "$1" '.steps_cpu = {composite: $c, plate0: 1143.8} | .cpu_s = ($c + 1143.8)' "$O/build.json" >"$FX/b.json" && cp "$FX/b.json" "$O/build.json" && "$BIN/mv-report" "$O" >"$FX/r.log" 2>&1; }
cpu 3000
ok "$(grep -q '<tr class="c grew"><th scope="row">composite</th><td>3000</td><td>1263.2</td>' "$H" && grep -q '<tr class="c gone"><th scope="row">hdr10</th>' "$H" && echo 1 || echo 0)" \
  "composite 1263.2 -> 3000, encode_* + hdr10 gone (1789.2) -> grew vs 1263.2 + 549.4 absorbed"
cpu 1500
ok "$(grep -q '<tr class="c"><th scope="row">composite</th><td>1500</td><td>1263.2</td>' "$H" && ! grep -q 'class="c grew"' "$H" && echo 1 || echo 0)" \
  "composite 1263.2 -> 1500 absorbing encode_* -> not grew"
jq 'del(.steps_cpu)' "$O/build.json" >"$FX/b.json" && cp "$FX/b.json" "$O/build.json"
"$BIN/mv-report" "$O" >"$FX/r.log" 2>&1
ok "$(! grep -q 'prev:\|comparable' "$FX/r.log" && ! grep -q 'class="cpu"' "$H" && echo 1 || echo 0)" "no steps_cpu -> no CPU block, no prev line"
P=$FX/proj; mkdir -p "$P/out" "$P/.builds"
for i in $(seq -w 1 11); do echo '{}' >"$P/.builds/202601${i}T000000Z.json"; done
echo '{"name":"demo","cpu_s":1}' >"$P/out/build.json"
(export CREATIVE_CI_LOG=$FX/ci.jsonl; source "$BIN/mvlib.sh" && mv_finish demo "$P/out/build.json") >/dev/null 2>&1
rm -rf "$P/out"
ok "$([[ $(ls "$P/.builds" | wc -l) == 10 && ! -e $P/.builds/20260101T000000Z.json ]] && jq -e '.review == "PASS" and .cpu_s == 1' "$(ls -d "$P"/.builds/*.json | tail -1)" >/dev/null 2>&1 && echo 1 || echo 0)" \
  "mv_finish copies build.json to <project>/.builds (survives rm -rf out), keeps the last 10"
Q=$FX/q; mkdir -p "$Q/out" "$FX/bin"; printf '#!/bin/sh\necho 20261020T000000Z\n' >"$FX/bin/date"; chmod +x "$FX/bin/date"
fin() { (export CREATIVE_CI_LOG=$FX/ci.jsonl PATH=$FX/bin:$PATH; source "$BIN/mvlib.sh" && echo '{"name":"demo"}' >"$Q/out/build.json" && "$@"); }
fin mv_finish demo "$Q/out/build.json" >/dev/null 2>&1; fin mv_finish demo "$Q/out/build.json" >/dev/null 2>&1
ok "$([[ $(ls "$Q/.builds" | grep -cE '^20261020T000000Z-[0-9]+\.json$') == 2 ]] && echo 1 || echo 0)" "two finishes in one second -> 2 history files <UTC>-<pid>.json"
fin eval 'CHAIN=1; mv_finish demo "$Q/out/build.json"' >/dev/null 2>&1
ok "$(jq -e '.chain == true' "$Q/out/build.json" >/dev/null 2>&1 && echo 1 || echo 0)" "CHAIN=1 (build.sh --chain) -> build.json chain true"
rm -rf "$Q/.builds"; : >"$Q/.builds"
fin mv_finish demo "$Q/out/build.json" >/dev/null 2>"$FX/fin.err"; rc=$?
ok "$([[ $rc == 0 ]] && grep -q '^mv_finish: build history not kept: mkdir: .' "$FX/fin.err" && echo 1 || echo 0)" "unwritable .builds -> warning line on stderr, rc 0 (rc $rc)"
python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['hdr']={'kind':'pq','mastering_max':None,'mastering_min':None,'maxcll':1000,'maxfall':400}; d['fails'].append('hdr pq without mastering metadata'); json.dump(d,open(p,'w'))" "$O/cut.review.json"
"$BIN/mv-report" "$O" >/dev/null 2>&1
ok "$(grep -q '<b class="FAIL">FAIL</b><span class="what">review · HDR</span><span class="val">hdr pq without mastering' "$H" && echo 1 || echo 0)" "review.json hdr -> HDR row (FAIL on PQ without mastering)"
rm "$O/quality.json" "$O/cues.json"
"$BIN/mv-report" "$O" >/dev/null 2>&1
ok "$([[ $(grep -o '<svg viewBox' "$H" | wc -l) == 2 ]] && grep -q 'No quality.json: VMAF lane omitted' "$H" && grep -q 'No cues.json' "$H" && echo 1 || echo 0)" \
  "missing quality.json + cues.json -> lanes omitted with notes"
mkdir "$FX/empty"; "$BIN/mv-report" "$FX/empty" >/dev/null 2>&1
ok "$([[ $? == 1 ]] && echo 1 || echo 0)" "empty dir -> exit 1"

echo "mv-report.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
