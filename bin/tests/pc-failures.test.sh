#!/usr/bin/env bash
# pc-failures against a temp HOME and AGENT_WORK, stub systemctl/journalctl/pc-need and a fixture crash dir: every source, the window, not-ours, budget.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
REAL_HOME=$HOME
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

export HOME="$WORK/home" PC_FIXTURE="$WORK/fx" PC_CRASH_DIR="$WORK/crash" AGENT_WORK="$WORK/aw" CREATIVE_CI_LOG="$WORK/creative-ci.jsonl"
mkdir -p "$AGENT_WORK/evidence/T1" "$AGENT_WORK/evidence/T2" "$AGENT_WORK/evidence/T3" "$HOME/agents/log" "$HOME/agents/state/ci-fix" "$HOME/agents/a1/logs" "$PC_FIXTURE/bin" "$PC_CRASH_DIR"
now=$(date +%s); us() { echo $(( (now - $1) * 1000000 )); }
iso() { date -d "@$(( now - $1 ))" +%Y-%m-%dT%H:%M:%S%:z; }

cat >"$PC_FIXTURE/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
touch "$PC_FIXTURE/systemctl.used"
[ -n "${BROKEN:-}" ] && { echo 'not json'; exit 0; }
[ "$1" = --user ] && u=1 && shift
if [ "$1" = show ]; then
  for n in "${@:5}"; do case $n in t459-*|pcbench-*|run-*|tmux-spawn-*) echo not-found;; *) echo loaded;; esac; echo; done; exit 0
fi
case ${u:+--user} in
  --user) echo '[{"unit":"agent@x.service","load":"loaded","active":"failed","sub":"failed"}]';;
  *) echo '[{"unit":"vass-services.service","load":"loaded","active":"failed","sub":"failed"}]';;
esac
EOF
{
  printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"discord-bot.service","UNIT_RESULT":"signal"}\n' "$(us 7200)"
  printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"discord-bot.service","UNIT_RESULT":"exit-code"}\n' "$(us 600)"
  printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"discord-bot.service","UNIT_RESULT":"exit-code"}\n' "$(us 3600)"
  printf '{"__REALTIME_TIMESTAMP":"%s","UNIT":"moodle45-cron.service","UNIT_RESULT":"exit-code"}\n' "$(us 60)"
  stop() {  # Stopping, Main process exited with $2, Failed: $1 s apart, ending $3 s ago
    printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"%s","MESSAGE_ID":"de5b426a63be47a7b6ac3eaac82e2f6f","JOB_TYPE":"stop"}\n' "$(us $(($3 + $1)))" "$4"
    printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"%s","MESSAGE_ID":"98e322203f7a4ed290d09fe03c09fe15","EXIT_CODE":"exited","EXIT_STATUS":"%s"}\n' "$(us "$3")" "$4" "$2"
    printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"%s","MESSAGE_ID":"d9b373ed55a64feb8242e02dbe79a49c","UNIT_RESULT":"exit-code"}\n' "$(us "$3")" "$4"
  }
  stop 0 143 500 discord-bot.service
  stop 0 143 400 clean-stop.service
  stop 0 1 300 stop-status1.service
  stop 30 143 200 late-sigterm.service
  for u in t459-fleet-ci-probe.service t459-fleet-ci-probe.service pcbench-fail.service tmux-spawn-789b037a-c6aa-45dd-a0d2-bd2102d7bd6e.scope; do
    printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"%s","UNIT_RESULT":"exit-code"}\n' "$(us 900)" "$u"
  done
  printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"run-p337466-i4293799.scope","UNIT_RESULT":"oom-kill"}\n' "$(us 900)"
} >"$PC_FIXTURE/journal.json"
cat >"$PC_FIXTURE/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
touch "$PC_FIXTURE/journalctl.used"
echo "$*" >"$PC_FIXTURE/journalctl.args"
cat "$PC_FIXTURE/journal.json"
EOF
printf '#!/usr/bin/env bash\necho %q\n' '[{"id":"n1","t":"2026-10-19T08:00:00+0200","kind":"high","text":"disk full"}]' >"$PC_FIXTURE/bin/pc-need"
chmod +x "$PC_FIXTURE/bin/"*

printf 'start\tend\texit\tseconds\tcost_usd\tlog\n%s\t-\t1\t9\t0\t/l/new.log\n%s\t-\t0\t9\t0\t/l/ok.log\n%s\t-\t2\t9\t0\t/l/old.log\n' \
  "$(iso 3600)" "$(iso 1800)" "$(iso 259200)" >"$HOME/agents/a1/logs/index.tsv"
printf '## ailearning nightly red at %s (rc 1)\n\nx\n## ailearning nightly red at %s (rc 3)\n' "$(iso 7200)" "$(iso 259200)" \
  >"$HOME/agents/state/ci-fix/day.md"
printf 'ProblemType: Crash\nExecutablePath: /usr/bin/fixture\n' >"$PC_CRASH_DIR/_usr_bin_fixture.1000.crash"
printf 'ProblemType: Crash\n' >"$PC_CRASH_DIR/_usr_bin_old.1000.crash"; touch -d '-3 days' "$PC_CRASH_DIR/_usr_bin_old.1000.crash"
printf '{"ticket":"T1","rc":1,"ok":false,"started":"%s","runs":[{"started":"%s","rc":1,"ok":false}]}' "$(iso 600)" "$(iso 90000)" \
  >"$AGENT_WORK/evidence/T1/check.json"
printf '{"ticket":"T2","rc":0,"ok":true,"started":"%s"}' "$(iso 600)" >"$AGENT_WORK/evidence/T2/check.json"
printf '{"ticket":"T3","rc":1,"ok":false,"started":"%s"}' "$(iso 259200)" >"$AGENT_WORK/evidence/T3/check.json"
{
  printf '{"ts":"%s","tool":"cpp-ci","project":"demo","ok":false,"failed":["golden","perf"],"summary":"/p/demo/ci/summary.json"}\n' "$(iso 900)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"demo","ok":true,"failed":[],"summary":"/p/demo/ci/summary.json"}\n' "$(iso 1000)"
  printf '{"ts":"%s","tool":"mv-build","project":"promo","ok":false,"failed":["9x16:black 1x"],"summary":"/p/promo/out/build.json"}\n' "$(iso 300)"
  printf '{"ts":"%s","tool":"game-ci","project":"old","ok":false,"failed":["test"],"summary":"/p/old/ci/summary.json"}\n' "$(iso 259200)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"tmp","ok":false,"failed":["tidy"],"summary":"/tmp/t1/tmp/ci/summary.json"}\n' "$(iso 300)"
} >"$CREATIVE_CI_LOG"
for i in 1 2 3; do printf '{"ts":"%s","ok":true}\n' "$(iso 300)"; done >"$HOME/agents/log/actions.jsonl"
printf '{"ts":"%s","ok":false}\n{"ts":"%s"}\n' "$(iso 300)" "$(iso 300)" >>"$HOME/agents/log/actions.jsonl"
printf '{"ts":"%s","ok":false,"agent":"bench"}\n{"ts":"%s","ok":false,"tool":"Bash","error":"Exit code 97"}\n' "$(iso 300)" "$(iso 300)" \
  >>"$HOME/agents/log/actions.jsonl"
printf '{"ts":"%s","ok":false}\n' "$(iso 259200)" | gzip >"$HOME/agents/log/actions.jsonl.1.gz"

[ "$HOME" != "$REAL_HOME" ] && ok 'sandbox: HOME is a temp dir' || nok sandbox 'HOME is real'
j=$("$BIN/pc-failures" --json)
[ -e "$PC_FIXTURE/systemctl.used" ] && [ -e "$PC_FIXTURE/journalctl.used" ] && ok 'sandbox: stub systemctl and journalctl ran' \
  || nok sandbox 'a real systemctl/journalctl ran'
is 'json has every source' "$(jq -c 'keys' <<<"$j")" '["agents","audit","checks","ci","ci_healed","crashes","creative","creative_dev","creative_healed","errors","needs","since","units","units_healed"]'
is 'journal is asked from the window start' "$(cat "$PC_FIXTURE/journalctl.args" | cut -d' ' -f1-2)" "--since @$(jq .since <<<"$j")"
is 'failed now: user and system' "$(jq -r '[.units[] | select(.failed_now) | .unit + "/" + .scope] | sort | join(" ")' <<<"$j")" \
  'agent@x.service/user vass-services.service/system'
is 'journal count, last time, latest result' \
  "$(jq -r '.units[] | select(.unit == "discord-bot.service") | "\(.count) \(.last) \(.result) \(.scope)"' <<<"$j")" \
  "3 $((now - 600)) exit-code user"
is 'a 143 exit within 5 s of Stopping is a clean stop; status 1 or a late 143 stay' \
  "$(jq -r '[.units[] | select(.unit | test("stop|sigterm")) | .unit] | sort | join(" ")' <<<"$j")" 'late-sigterm.service stop-status1.service'
is 'moodle45*/vass* are not ours' "$(jq -r '[.units[] | select(.ours | not) | .unit] | sort | join(" ")' <<<"$j")" \
  'moodle45-cron.service vass-services.service'
is 'not-ours pattern is PC_NOT_OURS (pclib.sh default, env override)' \
  "$(PC_NOT_OURS='^discord' "$BIN/pc-failures" --json | jq -r '[.units[] | select(.ours | not) | .unit] | join(" ")')" 'discord-bot.service'
is 'agent runs: exit != 0 in window only' "$(jq -r '[.agents[] | "\(.agent):\(.exit)"] | join(" ")' <<<"$j")" 'a1:1'
is 'ci reds in window only' "$(jq -r '[.ci[] | .rc] | join(" ")' <<<"$j")" 1
is 'creative: red runs in window only, latest first' "$(jq -r '[.creative[] | "\(.tool):\(.project):\(.count):\(.failed | join(","))"] | join(" ")' <<<"$j")" \
  'mv-build:promo:1:9x16:black 1x cpp-ci:demo:1:golden,perf'
is 'creative: an unreadable summary counts as real, a /tmp summary is a dim dev run' \
  "$(jq -r '[.creative[] | select(.project == "demo") | .dim] + [.creative_dev[] | "\(.project):\(.dim)"] | join(" ")' <<<"$j")" 'false tmp:true'
is 'crashes in window, exe from the report' "$(jq -r '[.crashes[] | .exe] | join(" ")' <<<"$j")" /usr/bin/fixture
is 'audit rate over calls with an outcome, bench and sandbox hidden' "$(jq -c .audit <<<"$j")" \
  '{"calls":4,"failed":1,"rate":0.25,"hidden":{"bench":1,"sandbox":1}}'
is 'needs from pc need' "$(jq -r '.needs[0].text' <<<"$j")" 'disk full'
is 'red checks in window only, runs and first run' "$(jq -r '[.checks[] | "\(.ticket):\(.runs):\(.first)"] | join(" ")' <<<"$j")" \
  "T1:2:$((now - 90000))"
j7=$("$BIN/pc-failures" --since 7d --json)
is '--since 7d widens agents, ci, crashes, audit' \
  "$(jq -r '"\(.agents | length) \(.ci | length) \(.crashes | length) \(.audit.calls) \(.checks | length)"' <<<"$j7")" '2 2 2 5 2'
is '--since 7d reads the rotated .1.gz' "$(jq .audit.failed <<<"$j7")" 2
t=$("$BIN/pc-failures")
grep -q '^unit .*vass-services.service (system) .*not ours  FAILED NOW' <<<"$t" && ok 'table tags not ours and failed now' || nok table "$t"
grep -qE '^ci +cpp-ci demo +1 [0-9-]+ [0-9:]+ +golden,perf$' <<<"$t" && ok 'table: ci <tool> <project> N LAST <failed stages>' || nok 'table creative' "$t"
grep -q 'game-ci old' <<<"$t" && nok 'creative window' "$t" || ok 'creative: old red run outside the window hidden'
grep -q '^check  T1 1d ' <<<"$t" && ok 'table: check <ticket> <age since first red>' || nok 'table check' "$t"
is 'json keeps gone units with gone: true' "$(jq -r '[.units[] | select(.gone) | .unit] | sort | join(" ")' <<<"$j")" \
  'pcbench-fail.service run-p337466-i4293799.scope t459-fleet-ci-probe.service tmux-spawn-789b037a-c6aa-45dd-a0d2-bd2102d7bd6e.scope'
is 'json marks the run.sh scope oom as test_oom' "$(jq -r '[.units[] | select(.test_oom) | .unit] | join(" ")' <<<"$j")" run-p337466-i4293799.scope
grep -q '^unit .*gone: 3 one-off units .* 4 .*(t459-fleet-ci-probe, pcbench-fail, tmux-spawn)$' <<<"$t" && ok 'table folds gone units into one row' || nok 'gone row' "$t"
grep -q '^unit .*test oom: 1 run.sh scopes ' <<<"$t" && ok 'table counts run.sh scope oom as test oom' || nok 'test oom row' "$t"
grep -qE 't459|pcbench|run-p' <<<"$(grep -v -e gone -e 'test oom' <<<"$t")" && nok 'gone units hidden' "$t" || ok 'gone units have no own row'
grep -q 'exit-code  not ours$' <<<"$t" && ok 'NOTE parts separated by 2 spaces' || nok 'note spacing' "$t"
mkdir -p "$WORK/sum" "$WORK/scr"
printf '{"project":"%s"}' "$WORK/scr/game" >"$WORK/sum/game.json"
printf '{"project":"%s"}' "$WORK/agent-work/games/showcase" >"$WORK/sum/showcase.json"
{
  printf '{"ts":"%s","tool":"cpp-ci","project":"g2","ok":false,"failed":["golden"],"summary":"/run/user/%s/fleet-tests/g2/ci/summary.json"}\n' "$(iso 900)" "$(id -u)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"proj","ok":false,"failed":["tidy"],"summary":"/x/scratchpad/T1/proj/ci/summary.json"}\n' "$(iso 800)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"game","ok":false,"failed":["tidy"],"summary":"%s"}\n' "$(iso 700)" "$WORK/sum/game.json"
  printf '{"ts":"%s","tool":"cpp-ci","project":"showcase","ok":false,"failed":["tidy"],"summary":"%s"}\n' "$(iso 600)" "$WORK/sum/showcase.json"
} >"$WORK/scratch.jsonl"
sj=$(CI_SCRATCH_ROOTS="$WORK/scr" CREATIVE_CI_LOG="$WORK/scratch.jsonl" "$BIN/pc-failures" --json)
is 'scratch: fleet-tests, scratchpad and project-under-root runs are creative_dev, dim' \
  "$(jq -r '[.creative[].project] + ["|"] + [.creative_dev[] | "\(.project):\(.dim)"] | join(" ")' <<<"$sj")" 'showcase | game:true proj:true g2:true'
st=$(CI_SCRATCH_ROOTS="$WORK/scr" CREATIVE_CI_LOG="$WORK/scratch.jsonl" "$BIN/pc-failures")
is 'table: 3 scratch + 1 real red -> 1 real row + 1 dev row' "$(grep -cE '^ci +(cpp-ci showcase|dev:)' <<<"$st") $(grep -c 'cpp-ci' <<<"$st")" '2 1'
grep -qE '^ci +dev: 3 scratch runs \(red first by design\) +3 ' <<<"$st" && ok 'table: one dev row with the run count' || nok 'dev row' "$st"
sa=$(CI_SCRATCH_ROOTS="$WORK/scr" CREATIVE_CI_LOG="$WORK/scratch.jsonl" "$BIN/pc-failures" --all)
is '--all lists scratch runs one by one' "$(grep -cE '^ci +cpp-ci (g2|proj|game) .* dev  ' <<<"$sa") $(grep -c 'dev:' <<<"$sa")" '3 0'
mkdir -p "$WORK/heal/p/r/ci"
printf '{"project":"/p/r"}' >"$WORK/heal/p/r/ci/summary.json"
{
  printf '{"ts":"%s","tool":"cpp-ci","project":"a","ok":false,"failed":["tidy"],"summary":"/p/a/ci/summary.json"}\n' "$(iso 900)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"a","ok":true,"failed":[],"summary":"/p/a/ci/summary.json"}\n' "$(iso 800)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"b","ok":true,"failed":[],"summary":"/p/b/ci/summary.json"}\n' "$(iso 900)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"b","ok":false,"failed":["golden"],"summary":"/p/b/ci/summary.json"}\n' "$(iso 800)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"r","ok":false,"failed":["perf"],"summary":"/p/r/ci/summary.json"}\n' "$(iso 900)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"r","ok":true,"failed":[],"summary":"%s"}\n' "$(iso 800)" "$WORK/heal/p/r/ci/summary.json"
  printf '{"ts":"%s","tool":"game-ci","project":"a","ok":false,"failed":["test"],"summary":"/p/a/ci/summary.json"}\n' "$(iso 700)"
} >"$WORK/heal.jsonl"
hj=$(CREATIVE_CI_LOG="$WORK/heal.jsonl" "$BIN/pc-failures" --json)
is 'heal: red then green -> healed; green then red, real red + scratch green, other tool -> rows' \
  "$(jq -r '[.creative[] | "\(.tool):\(.project)"] + ["|"] + [.creative_healed[] | "\(.project):\(.count):\(.healed_at)"] | join(" ")' <<<"$hj")" \
  "game-ci:a cpp-ci:b cpp-ci:r | a:1:$((now - 800))"
ht=$(CREATIVE_CI_LOG="$WORK/heal.jsonl" "$BIN/pc-failures")
grep -qE '^ci +cpp-ci a ' <<<"$ht" && nok 'healed red hidden' "$ht" || ok 'table: a healed red has no row'
grep -qE '^ci +cpp-ci a +1 .* healed [0-9-]+ [0-9:]+  tidy$' <<<"$(CREATIVE_CI_LOG="$WORK/heal.jsonl" "$BIN/pc-failures" --all)" \
  && ok '--all lists a healed red as healed <time>' || nok '--all healed' "$ht"
{
  printf '{"ts":"%s","tool":"cpp-ci","project":"o","ok":true,"failed":[],"summary":"/p/o/ci/summary.json"}\n' "$(iso 800)"
  printf '{"ts":"%s","tool":"cpp-ci","project":"o","ok":false,"failed":["tidy"],"summary":"/p/o/ci/summary.json"}\n' "$(iso 900)"
} >"$WORK/order.jsonl"
is 'heal: an out-of-order green before an older red heals at the green' \
  "$(CREATIVE_CI_LOG="$WORK/order.jsonl" "$BIN/pc-failures" --json | jq -r '[.creative[].project] + ["|"] + [.creative_healed[] | "\(.project):\(.healed_at)"] | join(" ")')" \
  "| o:$((now - 800))"
# fleet nightly (T897, T945): the red's log verdict is its last summary or recheck line; a green recheck heals the ci row and the fleet-ci-daily unit row.
FH="$WORK/fh"; FX2="$WORK/fx2"; mkdir -p "$FH/agents/state/ci-fix" "$WORK/fci" "$FX2/bin"; day=$(date -d '2 days ago' +%F)
red=$(date -d "$day 02:31:00" +%s)
printf '## fleet nightly red at %s (rc 1)\n' "$(date -d "@$red" +%Y-%m-%dT%H:%M:%S%:z)" >"$FH/agents/state/ci-fix/day.md"
printf '{"__REALTIME_TIMESTAMP":"%s000000","USER_UNIT":"fleet-ci-daily.service","UNIT_RESULT":"exit-code"}\n' "$red" >"$FX2/journal.json"
cp "$PC_FIXTURE/bin/pc-need" "$FX2/bin/"
cat >"$FX2/bin/journalctl" <<'EOF2'
#!/usr/bin/env bash
case "$*" in *MESSAGE_ID=7d4958e842da4a758f6c1cdc7b36dcc5*) cat "$PC_FIXTURE/starts.json" 2>/dev/null;; *) cat "$PC_FIXTURE/journal.json";; esac
EOF2
cat >"$FX2/bin/systemctl" <<'EOF2'
#!/usr/bin/env bash
[ "$1" = --user ] && u=1 && shift
[ "$1" = show ] && { for n in "${@:5}"; do echo loaded; echo; done; exit 0; }
[ -n "${u:-}" ] && [ -n "${FCI_FAILED:-}" ] && echo '[{"unit":"fleet-ci-daily.service","load":"loaded","active":"failed","sub":"failed"}]' || echo '[]'
EOF2
chmod +x "$FX2/bin/systemctl" "$FX2/bin/journalctl"
fleet() { printf "FAIL 211/212 files in 9 s\n✖ fleet ci red: a.test.sh\n$1" >"$WORK/fci/$day.txt"; HOME="$FH" PC_FIXTURE="$FX2" PC_FLEET_CI_DIR="$WORK/fci" "$BIN/pc-failures" --since 7d "${@:2}"; }
healed="$(date -d "$day 11:27:28" +%s)"
is 'fleet: red + green recheck -> ci_healed at the recheck time' \
  "$(fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n' --json | jq -r '"\(.ci | length) \(.ci_healed[0].what):\(.ci_healed[0].healed_at)"')" "0 fleet nightly:$healed"
is 'fleet: red + 0/1 recheck stays a ci row' "$(fleet 'recheck 10:55:32: 0/1 green (a.test.sh)\n' --json | jq -r '"\(.ci[0].what) \(.ci_healed | length)"')" 'fleet nightly 0'
is 'fleet: two rechecks, the last green, heal' \
  "$(fleet 'recheck 10:55:32: 0/1 green (a.test.sh)\nrecheck 11:27:28: 1/1 green (a.test.sh)\n' --json | jq -r '"\(.ci | length) \(.ci_healed | length)"')" '0 1'
is 'fleet: two rechecks, the last red, stay red' \
  "$(fleet 'recheck 10:55:32: 1/1 green (a.test.sh)\nrecheck 11:27:28: 0/1 green (a.test.sh)\n' --json | jq -r '"\(.ci | length) \(.ci_healed | length)"')" '1 0'
ft=$(fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n')
grep -q 'fleet nightly' <<<"$ft" && nok 'fleet: a healed nightly has no row' "$ft" || ok 'fleet: a healed nightly has no row'
grep -q 'fleet-ci-daily' <<<"$ft" && nok 'fleet: a healed unit has no row' "$ft" || ok 'fleet: a healed fleet-ci-daily unit has no row'
fa=$(fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n' --all)
grep -qE '^ci +fleet nightly +1 .* healed [0-9-]+ 11:27  rc 1$' <<<"$fa" && ok 'fleet: --all lists it as healed <time>' || nok 'fleet --all healed' "$fa"
grep -qE '^unit +fleet-ci-daily.service \(user\) +1 .* healed [0-9-]+ 11:27  exit-code$' <<<"$fa" \
  && ok 'unit: --all lists a healed fleet-ci-daily as healed <time>' || nok 'unit --all healed' "$fa"
is 'unit: red + green recheck -> units_healed at the recheck time' \
  "$(fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n' --json | jq -r '"\([.units[].unit] | length) \(.units_healed[0].unit):\(.units_healed[0].healed_at)"')" \
  "0 fleet-ci-daily.service:$healed"
is 'unit: red + 0/1 recheck stays a unit row' \
  "$(fleet 'recheck 10:55:32: 0/1 green (a.test.sh)\n' --json | jq -r '"\([.units[].unit] | join(",")) \(.units_healed | length)"')" 'fleet-ci-daily.service 0'
is 'unit: failed now stays a unit row despite a green recheck' \
  "$(FCI_FAILED=1 fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n' --json | jq -r '"\([.units[].unit] | join(",")) \(.units_healed | length)"')" 'fleet-ci-daily.service 0'
next=$(date -d "$day 00:30:12 next day" +%s)
is 'a 00:30 recheck after a 02:31 red is healed the next day (ci and unit)' \
  "$(fleet 'recheck 00:30:12: 1/1 green (a.test.sh)\n' --json | jq -r '"\(.ci_healed[0].healed_at) \(.units_healed[0].healed_at)"')" "$next $next"
# T986: a later nightly start with no verdict voids the heal; one with a verdict, or the red's own run, does not.
start() { printf '{"__REALTIME_TIMESTAMP":"%s000000","USER_UNIT":"fleet-ci-daily.service","MESSAGE_ID":"7d4958e842da4a758f6c1cdc7b36dcc5"}\n' "$@" >"$FX2/starts.json"; }
s1=$(date -d "$day 02:22:00 next day" +%s); day1=$(date -d "@$s1" +%F)
start "$s1"
is 'start: a nightly start after the recheck with no log voids the heal (ci and unit)' \
  "$(fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n' --json | jq -r '"\(.ci | length) \(.ci_healed | length) \(.units | length) \(.units_healed | length)"')" '1 0 1 0'
printf 'fleet-ci-daily %s\nci-window: waiting\n' "$(date -d "@$s1" -Is)" >"$WORK/fci/$day1.txt"
is 'start: a later start whose log has no verdict line voids the heal' \
  "$(fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n' --json | jq -r '"\(.ci | length) \(.ci_healed | length)"')" '1 0'
printf 'fleet-ci-daily %s\nPASS 212/212 files in 9 s\n' "$(date -d "@$s1" -Is)" >"$WORK/fci/$day1.txt"
start "$(date -d "$day 02:22:00" +%s)" "$s1"
is 'start: the red run before the recheck and a later start with a verdict keep the heal' \
  "$(fleet 'recheck 11:27:28: 1/1 green (a.test.sh)\n' --json | jq -r '"\(.ci | length) \(.ci_healed[0].healed_at)"')" "0 $healed"
rm -f "$FX2/starts.json" "$WORK/fci/$day1.txt"
# T986: healed_at never after now: a recheck that would read as tomorrow is no heal.
red2=$((now - 60)); day2=$(date -d "@$red2" +%F)
printf '## fleet nightly red at %s (rc 1)\n' "$(date -d "@$red2" +%Y-%m-%dT%H:%M:%S%:z)" >"$FH/agents/state/ci-fix/day.md"
printf '{"__REALTIME_TIMESTAMP":"%s000000","USER_UNIT":"fleet-ci-daily.service","UNIT_RESULT":"exit-code"}\n' "$red2" >"$FX2/journal.json"
printf 'FAIL 211/212 files in 9 s\nrecheck %s: 1/1 green (a.test.sh)\n' "$(date -d "@$((red2 - 1))" +%T)" >"$WORK/fci/$day2.txt"
is 'future: a recheck dated after now heals neither ci nor unit' \
  "$(HOME="$FH" PC_FIXTURE="$FX2" PC_FLEET_CI_DIR="$WORK/fci" "$BIN/pc-failures" --since 7d --json | jq -r '"\(.ci | length) \(.ci_healed | length) \(.units | length) \(.units_healed | length)"')" '1 0 1 0'
for s in unit agent ci crash audit need check; do grep -q "^$s " <<<"$t" || nok "table row $s" "$t"; done; ok 'table has a row per source'
e=$(BROKEN=1 "$BIN/pc-failures" --json); rc=$?
is 'a broken source is an error, the rest still shows' "$rc $(jq -r '(.errors | keys | join(",")) + " " + (.agents | length | tostring)' <<<"$e")" '0 units 1'
"$BIN/pc-failures" --since 5x >/dev/null 2>&1; is 'bad --since exits 2' $? 2
usage=$(python3 -c 'import ast, sys; print(next(n.value.value for n in ast.parse(open(sys.argv[1]).read()).body if isinstance(n, ast.Assign) and n.targets[0].id == "USAGE"))' "$BIN/pc-failures")
is '-h and --help print USAGE byte for byte' "$("$BIN/pc-failures" -h | md5sum) $("$BIN/pc-failures" --help | md5sum)" "$(md5sum <<<"$usage") $(md5sum <<<"$usage")"
is '-h answers before glob, json, subprocess, re are imported' \
  "$(python3 -X importtime "$BIN/pc-failures" -h 2>&1 >/dev/null | grep -cE '\| +(glob|json|subprocess|re)$')" 0
"$BIN/pc-failures" --bogus >/dev/null 2>&1; is 'unknown option exits 2' $? 2
s=$(date +%s%N); "$BIN/pc-failures" >/dev/null; ms=$(( ($(date +%s%N) - s) / 1000000 ))
[ "$ms" -le 1000 ] && ok "under 1 s (${ms} ms)" || nok budget "${ms} ms"
exit $bad
