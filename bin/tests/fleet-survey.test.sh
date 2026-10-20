#!/usr/bin/env bash
# fleet-survey in a fixture HOME: stub CLIs and fixture files only, so no real pc/agents-log/guide/claims ever runs.
# shellcheck disable=SC1091,SC2015,SC2154,SC2016,SC2088  # assert.sh sets bad; stub bodies and ~ paths are literal
set -uo pipefail
. "$HOME/agents/bin/tests/lib/assert.sh"
FS="$HOME/agents/bin/fleet-survey"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FH="$W/home"; A="$FH/agents"; E="$FH/agent-work/evidence"; CALLS="$W/calls"
mkdir -p "$A/bin/tests" "$A/log/fleet-ci" "$A/state/gamedev-perf" "$A/skills/sk/scripts" "$A/skills/sk/tests" \
  "$FH/.claude/skills/own/scripts" "$E/T1" "$E/T2" "$E/T3" "$E/T4"
unjudged() { local l; read -r l _ </proc/loadavg; [ $((10#${l/./} * 2)) -gt $(($(nproc) * 100)) ] && echo ", unjudged at load $l"; }
survey() { env -u HARNESS_HOME -u AGENT_WORK HOME="$FH" CALLS="$CALLS" "$FS" "$@"; }

stub() { printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n%s\n' "$1" "$2" >"$A/bin/$1"; chmod +x "$A/bin/$1"; }
stub pc 'case "$1" in failures) echo "unit   x.service 3";; doctor) sleep 0.2; echo "pc doctor end" >>"$CALLS"; echo "WARN usage slow"; echo "PASS 17/19"; exit 1;; esac'
stub agents-log 'case "$*" in *--cluster*) echo "count sess cluster"; i=0; while [ $i -lt 30 ]; do echo "  1 1 c$i"; i=$((i+1)); done; echo "TOTAL 30 failed";; *--tokens*) echo "ticket turns"; echo "T9 12";; esac'
stub guide 'echo "2026-09-24   25d  old-guide"; echo "2026-09-25   24d  older"'
stub claims 'echo "ok 0h  T554 · x"'

printf '#!/bin/sh\n' >"$A/bin/tested-cli"; printf '#!/bin/sh\n\n\n' >"$A/bin/lonely-cli"
printf 'x\n' >"$A/bin/notexec"; chmod +x "$A/bin/tested-cli" "$A/bin/lonely-cli"
echo 'run "$B/tested-cli" pc agents-log guide claims journalctl' >"$A/bin/tests/tested-cli.test.sh"
printf '#!/bin/sh\n' >"$A/skills/sk/scripts/sk-tool"; printf '#!/bin/sh\n' >"$A/skills/sk/scripts/sk-orphan"
chmod +x "$A/skills/sk/scripts/"*; echo 'sk-tool' >"$A/skills/sk/tests/sk.test.sh"
ln -s "$A/skills/sk" "$FH/.claude/skills/sk"
printf '#!/bin/sh\n' >"$FH/.claude/skills/own/scripts/own.py"; chmod +x "$FH/.claude/skills/own/scripts/own.py"
mkdir -p "$A/lib" "$A/hooks"; printf 'x = 1\n' >"$A/lib/lonely_lib.py"; printf 'x\n' >"$A/lib/notes.txt"
printf 'x\n' >"$A/hooks/tested_hook.py"; echo 'import tested_hook' >"$A/hooks/tested_hook.test.py"

printf 'noise\nFAIL bin/tests/a.test.sh 3.0\nFAIL bin/tests/b.test.sh 0.5\nFAIL bin/tests/slow.test.sh 99.0\nFAIL bin/tests/z.test.sh 120\nok bin/tests/c.test.sh 1.0\nFAIL 109/114 files in 164 s\nci-load: contention\n✖ fleet ci red: a.test.sh\n  recheck | noise\nrecheck 11:27:28: 1/1 green (a.test.sh)\n' >"$A/log/fleet-ci/2026-10-19.txt"
printf 'PASS 114/114 files\n' >"$A/log/fleet-ci/2026-10-18.txt"; touch -d '2 days ago' "$A/log/fleet-ci/2026-10-18.txt"
printf 'a.test.sh\t1.0\t0\nb.test.sh\t9.5\t0\nc.test.sh\t3\t0\nd.test.sh\t7\t0\ne.test.sh\t2\t0\nf.test.sh\t8\t0\nbad\tx\t0\n' \
  >"$A/state/test-timings.tsv"
printf 'date,project,seconds,avg_fps\nd,w,6,90\nd,w,6,110\nd,w,6,\nd,w,6,100\n' >"$A/state/gamedev-perf/perf.csv"
echo '{"ticket":"T1","rc":0,"ok":true,"check":"true"}' >"$E/T1/check.json"
echo '{"ticket":"T2","rc":1,"ok":false,"check":"false-now","verdict":"drift"}' >"$E/T2/check.json"
echo '{"ticket":"T3","rc":1,"ok":false,"check":"false-old"}' >"$E/T3/check.json"; touch -d '3 days ago' "$E/T3/check.json"
# Journal-window CHECKs: fix = first agent-verify run (2 h ago); the stub journal's last failing line decides window or still-red.
iso() { date -d "$1" +%FT%T%:z; }
cat >"$A/bin/journalctl" <<EOS
#!/bin/sh
echo "journalctl \$*" >>"$CALLS"
case "\$*" in
  *healed.service*) echo "$(iso '5 hours ago') host x[1]: Failed with result 'exit-code'"; echo "$(iso '3 hours ago') host x[1]: Failed with result 'exit-code'" ;;
  *broken.service*) echo "$(iso '10 minutes ago') host y[1]: core-dump" ;;
  *quiet.service*) : ;;
esac
EOS
chmod +x "$A/bin/journalctl"
mkdir -p "$E/T5" "$E/T6" "$E/T7" "$E/T8"
jcheck() { printf 'test "$(journalctl --user -u %s --since -24h --no-pager | grep -c %s)" -eq 0' "$1" "$2"; }
cj() { python3 -c 'import json,sys; t,s,c,f=sys.argv[1:5]; d={"ticket":t,"rc":1,"ok":False,"started":s,"check":c}
if f: d["runs"]=[{"started":f,"rc":1,"ok":False}]
json.dump(d,open(sys.argv[5],"w"))' "$@"; }
cj T5 "$(iso '30 minutes ago')" "$(jcheck healed.service "\"Failed with result 'exit-code'\"")" "$(iso '2 hours ago')" "$E/T5/check.json"
cj T6 "$(iso '2 hours ago')" "$(jcheck broken.service "'core-dump'")" '' "$E/T6/check.json"
cj T7 "$(iso '2 hours ago')" "$(jcheck quiet.service x)" '' "$E/T7/check.json"
echo '{"ticket":"T8","rc":1,"ok":false,"check":"bash ~/agents/bin/tests/run.sh","superseded":"fleet-ci"}' >"$E/T8/check.json"
printf 'FAIL 74/114 files in 104 s\nFAIL x 1\n' >"$E/T3/fresh-suite.txt"; touch -d '2 days ago' "$E/T3/fresh-suite.txt"
printf 'FAIL 99/114 files in 90 s\n' >"$E/T4/fresh-suite-26.04.txt"; touch -d '3 hours ago' "$E/T4/fresh-suite-26.04.txt"

out=$(survey); is "rc 0" "$?" 0
n=$(grep -c '^### ' <<<"$out"); is "13 sections" "$n" 13
grep -q '^--- 12/13 sections' <<<"$out" && ok "all sections ok but flaky (no history yet)" || nok "all sections ok but flaky" "$(tail -1 <<<"$out")"
sec() { awk -v s="### $1" '$0==s{f=1;next} /^###|^---/{f=0} f' <<<"$out"; }
is "failures from the stub" "$(sec failures)" "unit   x.service 3"
is "clusters: header + top 20 + TOTAL" "$(sec clusters | wc -l)" 22
grep -q 'TOTAL 30 failed' <<<"$(sec clusters)" && ok "clusters keep TOTAL" || nok "clusters keep TOTAL" "missing"
grep -q -- '--tokens --by ticket --since 24h' "$CALLS" && ok "tokens asks --by ticket" || nok "tokens asks --by ticket" "$(cat "$CALLS")"
is "doctor rc 1 still read" "$(sec doctor | head -1)" "WARN usage slow"
is "doctor runs alone after the parallel sections" "$(tail -2 "$CALLS" | tr '\n' '|')" "pc doctor --quick --brief|pc doctor end|"
is "doctor keeps its place in the output" "$(grep '^### ' <<<"$out" | sed -n 4p)" "### doctor"
is "fleet-ci: newest log, score + reds" "$(sec fleet-ci | tr '\n' '|')" "2026-10-19.txt|FAIL 109/114 files in 164 s|ci-load: contention|✖ fleet ci red: a.test.sh|recheck 11:27:28: 1/1 green (a.test.sh)|"
u=$(sec untested)
is "untested: count" "$(head -1 <<<"$u")" "4 scripts with no test naming them"
for want in '~/agents/lib/lonely_lib.py' '~/agents/bin/lonely-cli' '~/agents/skills/sk/scripts/sk-orphan' '~/.claude/skills/own/scripts/own.py'; do
  grep -qF "$want" <<<"$u" && ok "untested lists $want" || nok "untested lists $want" "$u"
done
grep -qE 'tested-cli|sk-tool|notexec|/stub|tested_hook|notes.txt' <<<"$u" && nok "untested skips tested/non-exec" "$u" || ok "untested skips tested/non-exec"
grep -q '^     3  ~/agents/bin/lonely-cli' <<<"$u" && ok "untested: line count" || nok "untested: line count" "$u"
is "stale guides: count" "$(sec 'stale guides' | head -1)" "2 guides verified >= 14 d ago or never"
r=$(sec 'red check.json')
is "red check.json: split counts" "$(head -1 <<<"$r")" "5 red of 6 check.json in 24h: 2 still-red, 2 window, 1 superseded"
grep -q 'T2 .*false-now' <<<"$r" && ! grep -q T3 <<<"$r" && ok "red check.json: only the recent red" || nok "red check.json: only the recent red" "$r"
heal=$(date -d '3 hours ago 24 hours' '+%m-%d %H:%M')
is "window: last failure before the fix heals at last + N" "$(grep '^T5 ' <<<"$r" | grep -o '\[.*\]$')" "[window, heals $heal]"
is "red check.json: verdict shown" "$(grep '^T2 ' <<<"$r" | grep -o '\[.*\]$')" "[verdict drift]"
is "window: no failing event left heals now" "$(grep '^T7 ' <<<"$r" | grep -o '\[.*\]$')" "[window, heals now]"
grep -qE '^T6 .*core-dump.{0,10}$' <<<"$r" && ok "a failure after the fix stays still-red" || nok "a failure after the fix stays still-red" "$(grep '^T6' <<<"$r")"
is "superseded keeps its verdict" "$(grep '^T8 ' <<<"$r" | grep -o '\[.*\]$')" "[superseded: fleet-ci]"
is "order: still-red, window, superseded" "$(sed 1d <<<"$r" | awk '{print /\[window/ ? "w" : /\[superseded/ ? "x" : "s"}' | tr -d '\n')" "sswwx"
grep -qF -- "journalctl --user -u healed.service --since -24h --no-pager -o short-iso" "$CALLS" \
  && ok "selftest: the journal query hit the stub" || nok "selftest: the journal query hit the stub" "$(cat "$CALLS")"
is "red check.json: --since 5d widens" "$(survey --since 5d | grep -c 'false-old')" 1
is "slow tests: no history, top 5 of the last run" "$(sec 'slow tests' | awk '{print $NF}' | tr '\n' ' ')" "b.test.sh f.test.sh d.test.sh c.test.sh e.test.sh "
is "perf cv" "$(sec 'perf cv')" "n=3 mean=100.0 sd=10.0 cv=10.0% min=90.0 max=110.0"
is "fresh suite: newest fresh-suite*.txt by mtime, named, aged" "$(sec 'fresh suite')" \
  "FAIL 99/114 files in 90 s  (~/agent-work/evidence/T4/fresh-suite-26.04.txt, 3 h old)"
is "claims" "$(sec claims)" "ok 0h  T554 · x"

j=$(survey --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d), all(v["ok"] for k, v in d.items() if k != "flaky"), d["perf cv"]["rows"][0][:3])')
is "flaky: n/a without a history" "$(sec flaky)" "n/a: no ~/agents/state/test-timings-history.tsv"
is "--json: 13 ok sections" "$j" "13 True n=3"

hist() { local f=$1 s; shift; for s; do printf '2026-10-19T09:56:00\t%s\t%s\t0\t13.5\n' "$f" "$s"; done; }
{ hist slow.test.sh 200 40 42 44 41 43; hist spiky.test.sh 4 5 122.3 4.4 5; hist small.test.sh 1 1 8 1 1
  hist a.test.sh 10; hist b.test.sh 9 9; hist c.test.sh 2; echo 'bad	x'; } >"$A/state/test-timings-history.tsv"
st=$(survey | awk '$0=="### slow tests"{f=1;next} /^###|^---/{f=0} f')
is "slow tests: measured (n >= 3) first, then noisy" "$(grep -v '^outlier' <<<"$st" | sed 's/  */ /g' | tr '\n' '|')" \
  " 42.0 s p50 of 5 slow.test.sh| 5.0 s p50 of 5 spiky.test.sh| 1.0 s p50 of 5 small.test.sh| 10.0 s p50 of 1 a.test.sh noisy (n=1, load 14)| 9.0 s p50 of 2 b.test.sh noisy (n=2, load 14)|"
is "slow tests: outlier > 5x p50 and > 30 s" "$(grep '^outlier' <<<"$st" | sed 's/  */ /g')" \
  "outlier 122.3 s 24.5x p50 5.0 s 2026-10-19T09:56 load 13.5 spiky.test.sh"
is "slow tests: 5-column history has no top CPU block" "$(grep -c '^top CPU' <<<"$st")" 0
hist6() { local f=$1 w=$2 c; shift 2; for c; do printf '2026-10-19T09:56:00\t%s\t%s\t0\t13.5\t%s\n' "$f" "$w" "$c"; done; }
{ hist slow.test.sh 40 42; hist6 slow.test.sh 41 1.0 1.2 1.1; hist6 waity.test.sh 60 0.1 0.2 0.1
  hist6 burny.test.sh 8 50 7.0 7.5 8.0 7.2 7.1; hist6 mid.test.sh 3 2.0; } >"$A/state/test-timings-history.tsv"
st=$(survey | awk '$0=="### slow tests"{f=1;next} /^###|^---/{f=0} f')
is "slow tests: wall p50 kept with 6-column rows" "$(sed -n 1p <<<"$st" | sed 's/  */ /g')" " 60.0 s p50 of 3 waity.test.sh"
is "slow tests: top CPU by p50 cpu_s of the last 5 runs" "$(sed -n '/^top CPU$/,$p' <<<"$st" | sed 's/  */ /g' | tr '\n' '|')" \
  "top CPU| 7.2 cpu s p50 of 5 burny.test.sh| 2.0 cpu s p50 of 1 mid.test.sh| 1.1 cpu s p50 of 3 slow.test.sh| 0.1 cpu s p50 of 3 waity.test.sh|"
{ printf '2026-10-19T15:53:00\tbusy.test.sh\t84.4\t0\t33.6\t9.0\n'
  for s in 20 19 21 20 19.6; do printf '2026-10-19T09:56:00\tquiet.test.sh\t%s\t0\t2.1\t3.0\n' "$s"; done; } >"$A/state/test-timings-history.tsv"
st=$(survey | awk '$0=="### slow tests"{f=1;next} /^###|^---/{f=0} f')
is "slow tests: n=5 quiet row ranks above an n=1 load-34 row" "$(sed -n 1,2p <<<"$st" | sed 's/  */ /g' | tr '\n' '|')" \
  " 20.0 s p50 of 5 quiet.test.sh| 84.4 s p50 of 1 busy.test.sh noisy (n=1, load 34)|"
is "slow tests: top CPU ranks the noisy row by cpu_s" "$(sed -n '/^top CPU$/,$p' <<<"$st" | sed 's/  */ /g' | tr '\n' '|')" \
  "top CPU| 9.0 cpu s p50 of 1 busy.test.sh| 3.0 cpu s p50 of 5 quiet.test.sh|"

# flaky: red<->green flips in the window; an input mtime between the two runs makes the flip dev, a later one unsure.
mkdir -p "$A/skills/fsk/tests" "$A/skills/fsk/scripts" "$A/skills/gsk/tests" "$A/skills/gsk/scripts/__pycache__"
for f in bin/tests/flake.test.sh bin/flake bin/tests/devy.test.sh bin/devy bin/tests/green.test.sh skills/fsk/tests/fsk.test.sh skills/fsk/scripts/fsk-tool \
  bin/tests/neg.test.sh bin/tests/later.test.sh bin/later skills/gsk/tests/gsk.test.sh skills/gsk/scripts/gsk-tool skills/gsk/scripts/__pycache__/g.pyc; do
  echo x >"$A/$f"; touch -d '2 days ago' "$A/$f"; done
echo 'run "$B/shared-cli"' >"$A/bin/tests/refs.test.sh"; echo x >"$A/bin/shared-cli"
echo 'toolx --go' >"$A/bin/tests/refs2.test.sh"; echo '. "$B/libx.sh"' >"$A/bin/toolx"; echo x >"$A/bin/libx.sh"
touch -d '2 days ago' "$A/bin/tests/refs.test.sh" "$A/bin/tests/refs2.test.sh" "$A/bin/toolx"
touch -d '210 minutes ago' "$A/bin/devy" "$A/skills/fsk/scripts/fsk-tool" "$A/bin/shared-cli" "$A/bin/libx.sh" "$A/skills/gsk/scripts/__pycache__/g.pyc"
touch -d '1 hour ago' "$A/bin/later"
row() { printf '%s\t%s\t1.0\t%s\t%s\t0.5\n' "$(date -d "$1" +%FT%T)" "$2" "$3" "$4"; }
{ row '10 days ago' bin/tests/old.test.sh 1 9; row '10 days ago' bin/tests/old.test.sh 0 9
  row '5 hours ago' bin/tests/flake.test.sh 0 2; row '4 hours ago' bin/tests/flake.test.sh 1 25.06; row '3 hours ago' bin/tests/flake.test.sh 0 2.95
  row '4 hours ago' bin/tests/devy.test.sh 1 3; row '3 hours ago' bin/tests/devy.test.sh 0 3
  row '4 hours ago' skills/fsk/tests/fsk.test.sh 1 3; row '3 hours ago' skills/fsk/tests/fsk.test.sh 0 3
  row '4 hours ago' bin/tests/green.test.sh 0 3; row '3 hours ago' bin/tests/green.test.sh 0 3
  for t in refs refs2 later; do row '4 hours ago' "bin/tests/$t.test.sh" 1 3; row '3 hours ago' "bin/tests/$t.test.sh" 0 3; done
  row '4 hours ago' bin/tests/neg.test.sh -15 3; row '3 hours ago' bin/tests/neg.test.sh 0 3
  row '4 hours ago' skills/gsk/tests/gsk.test.sh 1 3; row '3 hours ago' skills/gsk/tests/gsk.test.sh 0 3; } >"$A/state/test-timings-history.tsv"
mkdir -p "$A/state/test-fails"; long=$(printf 'x%.0s' {1..120})
printf '## 2026-10-19T04:00:00 rc 1 load 30 wall 2.0\n  | FAIL older\n## 2026-10-20T04:00:00 rc 1 load 25 wall 2.0\n  | setup\n  | FAIL newest %s\n  | FAIL second\n' "$long" \
  >"$A/state/test-fails/bin__tests__flake.test.sh.txt"
fl=$(survey | awk '$0=="### flaky"{f=1;next} /^###|^---/{f=0} f')
is "flaky: 7d default, flaky files + dev and unsure flip counts" "$(head -1 <<<"$fl")" \
  "3 flaky, 4 dev flips (an input changed between the runs), 1 unsure (an input changed since) in 7d"
is "flaky: rc -15 counts as red; generated __pycache__ is no skill input" "$(cut -d' ' -f1 <<<"$fl" | sed -n '3,$p' | tr '\n' ' ')" \
  "bin/tests/neg.test.sh skills/gsk/tests/gsk.test.sh "
is "flaky: no edit between the runs -> flaky row" "$(sed -n 2p <<<"$fl")" \
  "bin/tests/flake.test.sh  red 1 / runs 3, flips 2, last $(date -d '3 hours ago' '+%m-%d %H:%M'), load at red 25.06  last red: $(cut -c1-100 <<<"FAIL newest $long")"
is "flaky: no state/test-fails record -> no last red" "$(grep -c 'last red' <<<"$fl")" 1
is "flaky: edited (bin tool, skill dir, bin file a test names, its lib), edited later, all-green, out-of-window absent" \
  "$(grep -cE 'devy|fsk|green|old|refs|later' <<<"$fl")" 0
is "flaky: --since narrows the window" "$(survey --since 1h | awk '$0=="### flaky"{getline; print}')" \
  "0 flaky, 0 dev flips (an input changed between the runs), 0 unsure (an input changed since) in 1h"

# --creative / --shipped: fixture stacks, evidence, drops, briefs, backlogs and history.
MV="$A/skills/motion-video"; GD="$A/skills/gamedev"; B="$FH/agent-work/briefs"; D="$FH/drop"
mkdir -p "$FH/agent-work/research/d/T80" "$MV/scripts" "$MV/tests" "$MV/templates/blender" "$GD/scripts" "$GD/tests" "$B" "$E/T40" "$E/T41" "$E/T42" "$E/T43" \
  "$D/T50" "$D/T51-x" "$D/T52" "$D/T53" "$D/T54" "$D/T55" "$D/misc" "$FH/agent-work/research/d/T60" "$FH/agent-work/research/d/T70" "$FH/agent-work/research/d/T90"
touch "$MV/scripts/mv-a" "$MV/scripts/mv-b" "$MV/tests/a.test.sh" "$MV/tests/b.test.sh" "$MV/tests/c.test.sh" "$MV/tests/README"
echo 'os.environ.get("MV_LOOK"); os.environ["MV_DEPTH"]; MV_LOOK' >"$MV/templates/blender/shot.py"
printf 'x\nstages="configure build golden"\n' >"$GD/scripts/cpp-ci"; touch "$GD/tests/g.test.sh"
# Live sources, not evidence: stale evidence decoys must lose to motion build.json, perf-cpp.csv and the cpp-ci ledger.
echo '{"mean_s":9.9,"per_frame_s":{"1":9.9}}' >"$E/T41/render.json"; echo 'gpu_ms_p50=306.0484' >"$E/T42/perf.md"
echo '{"stages":{"configure":{"status":"pass"},"sanitize":{"status":"pass"},"perf":{"status":"skip"}}}' >"$E/T43/summary.json"
MO="$FH/agent-work/motion"; mkdir -p "$MO/old/out" "$MO/new/out"
echo '{"cpu_s":1.0,"steps_cpu":{"x":1.0}}' >"$MO/old/out/build.json"; touch -d '1 day ago' "$MO/old/out/build.json"
echo '{"cpu_s":7304.8,"steps_cpu":{"beats":1.8,"composite":1263.2,"hdr10":1239.8,"plate0":1143.8}}' >"$MO/new/out/build.json"
touch -d '5 hours ago' "$MO/new/out/build.json"
printf 'date,project,gpu_ms_p50,status,post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene\n2026-10-01T00:00:00+02:00,cpp,9.9,pass,1,1,1\n%s,cpp,1.1190,pass,0.4449,0.0668,0.6018\n' \
  "$(iso '2 hours ago')" >"$A/state/gamedev-perf/perf-cpp.csv"
CC="$A/log/creative-ci"; mkdir -p "$CC" "$W/scratch/game"; export CI_SCRATCH_ROOTS="$W/scratch"
echo "{\"project\":\"$FH/proj/cpp\",\"stages\":{\"configure\":{\"status\":\"pass\"},\"perf\":{\"status\":\"pass\"}}}" >"$CC/real.json"
echo "{\"project\":\"$W/scratch/game\",\"stages\":{\"golden\":{\"status\":\"fail\"}}}" >"$CC/scratch.json"
{ printf '{"ts":"%s","tool":"cpp-ci","project":"cpp","summary":"%s"}\n' "$(iso '4 hours ago')" "$CC/real.json"
  printf '{"ts":"%s","tool":"cpp-ci","project":"game","summary":"%s"}\n' "$(iso '1 hour ago')" "$CC/scratch.json"
  printf '{"ts":"%s","tool":"mv-build","project":"demo","summary":"%s"}\n' "$(iso '30 minutes ago')" "$CC/real.json"; } >"$A/log/creative-ci.jsonl"
for t in T50 T51 T52 T53; do printf '# %s\nFiles: ~/agents/skills/motion-video/x\n## Common rules\ngamedev gamedev gamedev\n' "$t" >"$B/$t-m.md"; done
printf '# T54\nFiles: ~/agents/skills/gamedev/x\n' >"$B/T54-g.md"; printf '# T55\nmotion-video gamedev\n' >"$B/T55-tie.md"
for d in T50 T51-x T52 T53 T54 T55 misc; do touch "$D/$d/a.png"; done; touch "$D/T50/notes.md" "$D/T52/v.mp4"
touch -d '4 hours ago' "$D/T50/a.png"; touch -d '3 hours ago' "$D/T51-x/a.png"; touch -d '1 hour ago' "$D/T52/a.png"
printf '# T60 backlog: 3 tickets\n\n## 1. First thing (a)\nx\n## 2. Second thing\n## 3. Third thing\n' >"$FH/agent-work/research/d/T60/BACKLOG.md"
printf '# T70 backlog wave 2: 1 ticket\n## 1. Wave two item\n' >"$FH/agent-work/research/d/T70/BACKLOG.md"
echo "# T61 — backlog #1 (from $FH/agent-work/research/d/T60/BACKLOG.md)" >"$B/T61-a.md"
echo "# T62 — wave 1 #2 (from $FH/agent-work/research/d/T60/BACKLOG.md)" >"$B/T62-b.md"
echo "# T71 — wave-2 backlog #1 (from $FH/agent-work/research/d/T70/BACKLOG.md)" >"$B/T71-c.md"
printf '# T80 backlog wave 3: 3 tickets\n## 1. T81 Heading item\n## 2. T82 Collided item\n## 3. Tag item\n## 4. T84 Dashless item\n' >"$FH/agent-work/research/d/T80/BACKLOG.md"
echo "# T82 — client ticket, numbered by hand" >"$B/T82-client.md"
printf '# T90 BACKLOG: Moodle harness wave 3 (T91..T93)\n## T91 · Middot item\n## Notes\n## T92 Plain item\n## T93 · Open item\n' >"$FH/agent-work/research/d/T90/BACKLOG.md"
printf -- '- 2026-10-19 08:25 T61 done\n- T62 brief written: x\n- 2026-10-19 T71: y\n- 2026-10-20 T81 (wave 3 #1): z\n- 2026-10-20 T83 (w3 #3): t\n2026-10-20 09:00 T84 dash-less: u\n- 2026-10-20 T91 done\n- 2026-10-20 T92 done\nT62 started, a paragraph line\n' >"$FH/agent-work/history.md"
ln -s "$HOME/agents/bin/ticket-id" "$A/bin/ticket-id"
t0=$(date +%s%N); out=$(survey --creative --shipped-all); ms=$(( ($(date +%s%N) - t0) / 1000000 ))
u=$(unjudged); [ "$ms" -le 5000 ] || [ -n "$u" ] && ok "--creative --shipped <= 5 s on fixtures ($ms ms$u)" || nok "--creative --shipped <= 5 s" "$ms ms"
grep -q '^--- 16/16 sections' <<<"$out" && ok "flags add 3 sections" || nok "flags add 3 sections" "$(tail -1 <<<"$out")"
m=$(sec 'creative motion-video'); g=$(sec 'creative gamedev')
is "mv: counts" "$(head -1 <<<"$m")" "2 scripts, 3 tests  ~/agents/skills/motion-video"
is "mv: MV_* knobs" "$(sed -n 2p <<<"$m")" "2 MV_* knobs MV_DEPTH MV_LOOK"
is "mv: newest build.json cpu_s + top 3 steps_cpu, aged" "$(sed -n 3p <<<"$m")" \
  "build cpu_s 7304.8  steps_cpu top composite=1263.2 hdr10=1239.8 plate0=1143.8  ~/agent-work/motion/new/out/build.json, 5 h old"
is "mv: newest 3 drops of its briefs (top text only)" "$(grep '^drop' <<<"$m" | awk '{print $NF}' | tr '\n' ' ')" \
  "~/drop/T52/v.mp4 ~/drop/T53/a.png ~/drop/T51-x/a.png "
is "gd: counts" "$(head -1 <<<"$g")" "1 scripts, 1 tests  ~/agents/skills/gamedev"
is "gd: last perf-cpp.csv row, per pass, aged" "$(sed -n 2p <<<"$g")" \
  "gpu_ms_p50 1.1190 (post=0.4449 shadow=0.0668 scene=0.6018) pass  ~/agents/state/gamedev-perf/perf-cpp.csv, 2 h old"
is "gd: cpp-ci stages" "$(sed -n 3p <<<"$g")" "cpp-ci stages configure build golden"
is "gd: newest non-scratch cpp-ci ledger row, stages, aged" "$(sed -n 4p <<<"$g")" \
  "cpp-ci last cpp configure:pass perf:pass  ~/agents/log/creative-ci/real.json, 4 h old"
is "gd: drops (tie and misc skipped)" "$(grep '^drop' <<<"$g" | awk '{print $NF}')" "~/drop/T54/a.png"
sh=$(sec shipped)
is "shipped: rows" "$(tr -s ' ' <<<"$sh" | tr '\n' '|')" \
  "wave T60: 3 items, 1 shipped, 1 open, 1 unticketed|T60#1 T61 shipped First thing (a)|T60#2 T62 open Second thing|T60#3 - unticketed Third thing|wave 2 T70: 1 items, 1 shipped, 0 open, 0 unticketed|T70#1 T71 shipped Wave two item|wave 3 T80: 4 items, 3 shipped, 1 open, 0 unticketed|T80#1 T81 shipped Heading item|T80#2 T82* open Collided item|T80#3 T83 shipped Tag item|T80#4 T84 shipped Dashless item|moodle wave 3 T90: 3 items, 2 shipped, 1 open, 0 unticketed|T90#1 T91 shipped Middot item|T90#2 T92 shipped Plain item|T90#3 T93 open Open item|"
grep -qE '^T80#1 +T81 +shipped' <<<"$sh" && ok "shipped: heading id in the id column" || nok "shipped: heading id column" "$sh"
grep -qE '^T80#4 +T84 +shipped' <<<"$sh" && ok "shipped: dash-less history line ships" || nok "shipped: dash-less history line ships" "$sh"
out=$(survey --shipped)
is "--shipped: wave counts + open/unticketed rows only" "$(sec shipped | tr -s ' ' | tr '\n' '|')" \
  "wave T60: 3 items, 1 shipped, 1 open, 1 unticketed|T60#2 T62 open Second thing|T60#3 - unticketed Third thing|wave 2 T70: 1 items, 1 shipped, 0 open, 0 unticketed|wave 3 T80: 4 items, 3 shipped, 1 open, 0 unticketed|T80#2 T82* open Collided item|moodle wave 3 T90: 3 items, 2 shipped, 1 open, 0 unticketed|T90#3 T93 open Open item|"
grep -q 'wave ?' <<<"$(sec shipped)" && nok "shipped: no 'wave ?' label" "$(sec shipped)" || ok "shipped: no 'wave ?' label"
out=$(survey --shipped all); is "--shipped all = --shipped-all" "$(sec shipped)" "$sh"
grep -q '^### creative' <<<"$(survey)" && nok "no flags: no creative section" "present" || ok "no flags: no creative section"

# --measure: stub run.sh/quiet-gate, fixture tmp base, dup-def files and settings.json hooks; the real ones never run.
cat >"$A/bin/tests/run.sh" <<'EOS'
#!/bin/sh
echo "run.sh $*" >>"$CALLS"
case "$2" in
  *a.test.sh) echo "ok $2 0.2"; exit 0 ;;
  *b.test.sh) echo "FAIL $2 0.3"; exit 1 ;;
  *slow.test.sh) sleep 30; echo "ok $2 30" ;;
esac
EOS
stub quiet-gate 'exit 3'
T="$W/tmpbase"; mkdir -p "$T/tmp.abc" "$T/tmp.def" "$T/claude-1000/x"
head -c 1000000 /dev/zero >"$T/tmp.abc/f"; head -c 2000000 /dev/zero >"$T/claude-1000/x/f"
touch "$T/mtest-behat-xtOw.log.1" "$T/mtest-behat-k3aN.log.2" "$T/ccfRfq.o"
printf '#!/bin/sh\nmain() { :; }\nshared() { :; }\ntwice() { :; }\n' >"$A/bin/d1"
printf 'def main():\n    pass\ndef shared():\n    pass\ndef twice():\n    pass\n' >"$A/lib/d2.py"
printf 'shared() { :; }\nmain() { :; }\n' >"$A/skills/sk/scripts/d3.sh"; chmod +x "$A/bin/d1" "$A/skills/sk/scripts/d3.sh"
printf '#!/bin/sh\necho "hook HH=$HARNESS_HOME H=$HOME $(grep -o "\\"tool_name\\": \\"[A-Za-z]*\\"")" >>"$CALLS"\nmkdir -p "$HARNESS_HOME/log"; echo "{}" >>"$HARNESS_HOME/log/actions.jsonl"\n' >"$A/bin/hook-stub"
chmod +x "$A/bin/hook-stub"
cat >"$FH/.claude/settings.json" <<'EOS'
{"hooks": {"PreToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "$HOME/agents/bin/hook-stub"}]}],
 "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/agents/bin/hook-stub", "async": true}]}],
 "Stop": [{"hooks": [{"type": "command", "command": "$HOME/agents/bin/hook-stub stop"}]}]}}
EOS
: >"$CALLS"
t0=$(date +%s%N)
out=$(TMPDIR="$W" FLEET_SURVEY_TMP="$T" FLEET_SURVEY_QUIET_WAIT=1 FLEET_SURVEY_CI_BUDGET=3 survey --measure)
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
u=$(unjudged); [ "$ms" -le 15000 ] || [ -n "$u" ] && ok "--measure <= 15 s on fixtures ($ms ms$u)" || nok "--measure <= 15 s" "$ms ms"
grep -q '^--- 18/18 sections' <<<"$out" && ok "--measure adds 5 sections" || nok "--measure adds 5 sections" "$(tail -1 <<<"$out")"
c=$(sec 'ci reds alone')
grep -q '^4 reds in 2026-10-19.txt; quiet-gate rc 3 after <= 1 s' <<<"$c" && ok "ci reds: header" || nok "ci reds: header" "$c"
grep -qx 'quiet-gate --wait 1' "$CALLS" && ok "ci reds: quiet-gate --wait first" || nok "ci reds: quiet-gate --wait first" "$(cat "$CALLS")"
is "ci reds: shortest suite first, rc + seconds, budget" "$(sed 1d <<<"$c" | sed -E 's/ +/ /g; s/(timeout) [0-9.]+ s/\1 N s/')" \
"rc 1 0.3 s alone (suite 0.5 s) bin/tests/b.test.sh
rc 0 0.2 s alone (suite 3.0 s) bin/tests/a.test.sh
rc timeout N s alone (suite 99.0 s) bin/tests/slow.test.sh
skipped: budget 3 s bin/tests/z.test.sh"
grep -qx 'run.sh --only bin/tests/a.test.sh -j 1' "$CALLS" && ok "ci reds: run.sh --only, one file" || nok "ci reds: run.sh --only" "$(cat "$CALLS")"
pgrep -f "[s]leep 30" >/dev/null && pgrep -af "[s]leep 30" | grep -q "$W" && nok "timeout kills the group" "left" || ok "timeout kills the group"
tr=$(sec 'tmp residue')
is "tmp residue: header" "$(head -1 <<<"$tr")" "6 entries, 3 MB in $T, 4 kinds"
is "tmp residue: kinds by MB" "$(sed 1d <<<"$tr" | sed -E 's/ +/ /g' | tr '\n' '|')" \
  " 1 2.0 MB claude| 2 1.0 MB tmp.*| 2 0.0 MB mtest-behat| 1 0.0 MB (other)|"
dd=$(sec 'dup defs')
grep -q '^1 names defined in >= 3 of' <<<"$dd" && ok "dup defs: only shared (main skipped, twice x2)" || nok "dup defs: count" "$dd"
is "dup defs: row" "$(sed -n 2p <<<"$dd" | sed -E 's/ +/ /g')" " 3x shared bin/d1:3 lib/d2.py:3 skills/sk/scripts/d3.sh:1"
h=$(sec 'hooks p50')
is "hooks: per-call events only, x5 into the sandbox" "$(head -1 <<<"$h" | sed -E 's/load1 [0-9.]+/load1 L/')" \
  "2 hooks x5, load1 L; 10 audit rows landed in the sandbox"
grep -qE 'ms p50 +[0-9/]+ +rc 0 +PreToolUse:Read +~/agents/bin/hook-stub$' <<<"$h" && ok "hooks: row shape" || nok "hooks: row shape" "$h"
is "hooks: 10 calls, never Stop" "$(grep -c '^hook ' "$CALLS")" 10
grep -q '"tool_name": "Read"' "$CALLS" && grep -q '"tool_name": "Bash"' "$CALLS" && ok "hooks: matcher as tool, * as Bash" || nok "hooks: tools" "$(cat "$CALLS")"
grep '^hook ' "$CALLS" | grep -qv "HH=$W/\S*fleet-survey-hooks\.\S* H=$W/" && nok "hooks: HARNESS_HOME and HOME in a mktemp dir" "$(grep '^hook' "$CALLS")" \
  || ok "hooks: HARNESS_HOME and HOME in a mktemp dir"
[ ! -e "$A/log/actions.jsonl" ] && ok "hooks: no row in the fixture's audit log" || nok "hooks: audit log" "written"
ls -d "$W"/fleet-survey-hooks.* >/dev/null 2>&1 && nok "hooks: sandbox removed" "left" || ok "hooks: sandbox removed"
cl=$(sec 'cli p50')
is "cli: header + 9 rows" "$(wc -l <<<"$cl")" 10
grep -qE 'ms p50 +[0-9]+/[0-9]+/[0-9]+ +rc 0 +claims list$' <<<"$cl" && ok "cli: x3 row" || nok "cli: x3 row" "$cl"
grep -q 'rc 3  quiet-gate$' <<<"$cl" && ok "cli: rc kept" || nok "cli: rc kept" "$cl"
grep -q "^n/a: not in ~/agents/bin  harness context --worker$" <<<"$cl" && ok "cli: missing CLI n/a" || nok "cli: missing CLI n/a" "$cl"
is "cli: 3 runs of claims list (+1 claims section)" "$(grep -cx 'claims list' "$CALLS")" 4
is "plain run: no measure section" "$(survey | grep -cE '^### (ci reds|hooks|cli|tmp|dup)')" 0

stub agents-log 'echo "agents-log: error: argument --by: invalid choice: ticket" >&2; exit 2'
t=$(survey | awk '$0=="### tokens by ticket"{getline; print}')
case "$t" in "n/a: agents-log --tokens --by ticket --since 24h rc 2: agents-log: error: argument --by: invalid choice"*) ok "failing CLI: n/a with why";; *) nok "failing CLI: n/a with why" "$t";; esac

rm -rf "$A" "$FH/agent-work" "$FH/.claude"; mkdir -p "$A/bin"
out=$(survey 2>&1); is "empty HOME: rc 0" "$?" 0
grep -q Traceback <<<"$out" && nok "empty HOME: no traceback" "$out" || ok "empty HOME: no traceback"
grep -q '^--- 2/13 sections' <<<"$out" && ok "empty HOME: 11 n/a (untested, red check.json find 0)" || nok "empty HOME: 11 n/a" "$(tail -1 <<<"$out")"
grep -q "n/a: pc not found in $A/bin" <<<"$out" && ok "never falls back to the real CLIs" || nok "never falls back to the real CLIs" "$out"

survey --since 1y >/dev/null 2>&1; is "bad --since: rc 2" "$?" 2
survey --bogus >/dev/null 2>&1; is "bad flag: rc 2" "$?" 2
survey --help >/dev/null; is "--help: rc 0" "$?" 0
exit "$bad"
