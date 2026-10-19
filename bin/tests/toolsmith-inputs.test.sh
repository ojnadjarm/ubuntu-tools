#!/usr/bin/env bash
# TS02: the toolsmith evidence collector. Fixtures only (AGENTS.md §5.6) — TOOLSMITH_ROOT points
# at bin/tests/fixtures/toolsmith and mock/*.json stands in for every live probe, so no pc verb
# and no live log is touched. Money is checked for by name: this collector reports tokens only.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$BIN/tests/fixtures/toolsmith"
CLI="$BIN/toolsmith-inputs"
fail=0
t() { printf '%-56s' "toolsmith-inputs: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }
run() { TOOLSMITH_ROOT="$FIX" HARNESS_HOME=/nonexistent "$CLI" "$@"; }

J="$(run --since 9999d --qa 2>/dev/null)"

t "exits 0 and prints JSON jq accepts"
{ [ -n "$J" ] && printf '%s' "$J" | jq -e . >/dev/null 2>&1; } && ok || no "not valid JSON"

t "all nine sections present"
missing=$(printf '%s' "$J" | jq -r '["bench_last","bench_failures","audit","guards","changes",
  "doctor","qa","idle","tokens"] - (keys) | join(",")')
[ -z "$missing" ] && ok || no "missing: $missing"

t "no money anywhere in the output"
printf '%s' "$J" | grep -qiE 'cost|usd|\$|price|spend' && no "money leaked into the output" || ok

# LAST.json's own `cost` key is deliberate fixture input: the collector must strip it.
t "no amount in the fixtures or the collector"
{ grep -rqiE 'usd|price|spend|[$][0-9]' "$FIX" || grep -qE '[$][0-9]' "$CLI"; } \
  && no "money literal in code or fixtures" || ok

t "bench_last carries the arms without the cost key"
[ "$(printf '%s' "$J" | jq -c '[.bench_last.trials,(.bench_last.arms.new|has("cost")),
  (.bench_last.arms.new.pass)]')" = '[8,false,0.75]' ] && ok || no "$(printf '%s' "$J" | jq -c .bench_last)"

t "bench_failures reads the newest run only, pass=0 rows"
[ "$(printf '%s' "$J" | jq -c '[.bench_failures.run,.bench_failures.fails,.bench_failures.trials,
  (.bench_failures.by_task.X02)]')" = '["20260102-000000-ab",2,4,2]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.bench_failures|{run,fails,trials,by_task}')"

t "each failure row keeps reason, raw_recipes_detail, tool_histogram"
[ "$(printf '%s' "$J" | jq -c '.bench_failures.rows[0]
  | [(.reason|length>0),.raw_recipes_detail.powerprofilesctl,.tool_histogram.Bash]')" = '[true,2,5]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.bench_failures.rows[0]')"

t "audit counts raw tools and pc verbs per session"
[ "$(printf '%s' "$J" | jq -c '[.audit.raw_total,.audit.pc_total,
  .audit.raw_by_tool["docker restart"],.audit.raw_by_tool["systemctl restart"],
  .audit.pc_verbs.status]')" = '[3,3,1,null,1]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.audit|{raw_total,pc_total,raw_by_tool,pc_verbs}')"

t "audit.raw_map pairs each raw tool with its class and pc verb"
[ "$(printf '%s' "$J" | jq -c '[(.audit.raw_map|length),.audit.raw_coverable,.audit.raw_gaps,
  (.audit.raw_map[]|select(.raw=="docker restart")|[.class,.pc,.count,.sessions])]')" \
  = '[3,3,[],["covered","pc docker restart",1,1]]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.audit|{raw_map,raw_coverable,raw_gaps}')"

t "audit per-session stats match agents-log --stats shape"
[ "$(printf '%s' "$J" | jq -r '.audit.sessions.aaaa1111.pc')" = 2 ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.audit.sessions')"

t "top raw offender is the session with no pc calls"
[ "$(printf '%s' "$J" | jq -c '.audit.top_raw_offenders[0]|[.session,.raw,.pc]')" = '["bbbb2222",2,0]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.audit.top_raw_offenders')"

t "guards: absent file is 0 rows, not an error"
[ "$(printf '%s' "$J" | jq -c '[.guards.present,.guards.rows]')" = '[false,0]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .guards)"

t "changes: verified / unverified / undone"
[ "$(printf '%s' "$J" | jq -c '[.changes.window,.changes.verified,.changes.unverified,
  .changes.undone,.changes.unverified_ids[0]]')" = '[3,2,1,1,"aaa000000003"]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .changes)"

t "doctor reports FAIL rows only"
[ "$(printf '%s' "$J" | jq -c '[.doctor.fail,.doctor.rows[0].name,(.doctor.rows|length)]')" \
  = '[1,"ledger",1]' ] && ok || no "$(printf '%s' "$J" | jq -c .doctor)"

t "qa compares the mock table with BASELINE-QA.tsv"
[ "$(printf '%s' "$J" | jq -c '[.qa.ran,.qa.worse,
  (.qa.modules[]|select(.module=="fleet").delta.shellcheck)]')" = '[true,["fleet"],2]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .qa)"

t "qa is opt-in: no --qa means not run"
[ "$(run --since 9999d 2>/dev/null | jq -c '[.qa.ran,(.qa|has("hint"))]')" = '[false,true]' ] &&
  ok || no "qa ran without --qa"

t "idle.live takes watts and wakers from the mocks"
[ "$(printf '%s' "$J" | jq -c '[.idle.live.package_w,.idle.live.gpu_rc6_pct,.idle.live.wakers[0].comm]')" \
  = '[4.2,98,"kworker/u64:1"]' ] && ok || no "$(printf '%s' "$J" | jq -c .idle)"

t "idle.live drops the collector's own agent@toolsmith waker"
[ "$(printf '%s' "$J" | jq -c '[([.idle.live.wakers[]|select(.unit=="agent@toolsmith.service")]|length),
  (.idle.live.wakers|length)]')" = '[0,2]' ] && ok || no "$(printf '%s' "$J" | jq -c .idle.live.wakers)"

t "idle.baseline is the last BASELINE-IDLE.tsv row"
[ "$(printf '%s' "$J" | jq -c '.idle.baseline|[.t,.package_w,.psys_w,.top_waker,.wake_s,.top_waker_unit]')" \
  = '["2026-01-11T02:00:00+01:00",4.54,5.59,"rcu_preempt",76.7,"-"]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .idle.baseline)"

t "idle.baseline carries other_rss_mb and other_top (TSP-039)"
[ "$(printf '%s' "$J" | jq -c '.idle.baseline|[.other_rss_mb,.other_top]')" = '[489.8,"agent@x.service:chrome-headless:3600:455"]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .idle.baseline)"

t "tokens: per-agent per-run in/out where the columns exist"
[ "$(printf '%s' "$J" | jq -c '[.tokens.columns_present,.tokens.agents.alpha.runs,
  .tokens.agents.alpha.in_per_run,.tokens.agents.alpha.out_per_run,
  (.tokens.agents|has("beta"))]')" = '[true,2,1000,600,false]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .tokens)"

t "tokens: cache_r, tool calls and the histogram, legacy short rows still counted"
[ "$(printf '%s' "$J" | jq -c '[.tokens.agents.alpha.cache_r_per_run,
  .tokens.agents.alpha.tool_calls,.tokens.agents.alpha.tool_histogram.Bash,
  .tokens.agents.alpha.tool_histogram.Read]')" = '[2000,8,5,3]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .tokens.agents.alpha)"

t "tokens: Workflow runs are flagged partial, not averaged in"
R="$(mktemp -d)"; mkdir -p "$R/swarm/logs"
{ printf 'start\ttokens_in\ttokens_out\thistogram\n'
  printf '%s\t10\t1000\tWorkflow=1,Bash=4\n' "$(date +%Y-%m-%dT%H:%M:%S)"
  printf '%s\t300\t5000\tBash=2\n' "$(date +%Y-%m-%dT%H:%M:%S)"; } > "$R/swarm/logs/index.tsv"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '.tokens.agents.swarm|[.runs,.partial_runs,.tokens_partial,.in_per_run,.out_per_run]')" \
  = '[2,1,true,300,5000]' ] && ok || no "$(printf '%s' "$o" | jq -c .tokens.agents.swarm)"
m="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d --md 2>/dev/null)"
t "--md marks the partial Workflow runs"
printf '%s' "$m" | grep -q 'swarm: 300 in / 5000 out.*1 Workflow run(s) partial' && ok ||
  no "$(printf '%s' "$m" | grep -A1 '^## tokens')"
rm -rf "$R"

t "the window actually filters"
[ "$(run --since 1s 2>/dev/null | jq -c '[.audit.lines,.changes.window,(.tokens.agents|length)]')" \
  = '[0,0,0]' ] && ok || no "$(run --since 1s | jq -c .audit.lines)"

t "bad --since is refused"
run --since 4days >/dev/null 2>&1 && no "accepted --since 4days" || ok

t "--md prints the section headings"
M="$(run --since 9999d --md 2>/dev/null)"
n=$(printf '%s\n' "$M" | grep -c '^## ')
{ [ "$n" -ge 5 ] && printf '%s' "$M" | grep -q 'X02/new#1'; } && ok || no "$n headings"

t "--md prints the baseline before the biased live sample"
printf '%s\n' "$M" | grep -A2 '^## idle' | sed -n '2p;3p' | tr '\n' '|' |
  grep -q '^- baseline 2026-01-11T02:00:00+01:00: package 4.54 W.*|- live (biased by this run)' &&
  ok || no "$(printf '%s\n' "$M" | grep -A3 '^## idle')"

t "--md idle baseline names the largest browser tree"
printf '%s\n' "$M" | grep -A1 '^## idle' | grep -q 'other 489.8 MB (agent@x.service:chrome-headless:3600:455)' &&
  ok || no "$(printf '%s\n' "$M" | grep -A1 '^## idle')"

t "--md carries no money either"
printf '%s' "$M" | grep -qiE 'cost|usd|\$' && no "money in --md" || ok

t "an empty root degrades instead of failing"
E="$(mktemp -d)"
o="$(TOOLSMITH_ROOT="$E" HARNESS_HOME=/nonexistent PATH=/usr/bin:/bin \
  "$CLI" --since 4d 2>/dev/null)"
rc=$?
{ [ $rc = 0 ] && printf '%s' "$o" | jq -e '.bench_last.present == false and
  .audit.lines == 0 and .doctor.present == false and .idle.baseline == null' >/dev/null; } &&
  ok || no "rc=$rc on an empty root"
rm -rf "$E"

t "audit and changes read rotated .N.gz logs too"
R="$(mktemp -d)"; mkdir -p "$R/log"
now=$(date +%s); at() { date -d "@$((now - $1 * 3600))" +%Y-%m-%dT%H:%M:%S; }
printf '{"ts":"%s","session":"s","tool":"Bash","summary":"pc status"}\n' "$(at 1)" > "$R/log/actions.jsonl"
printf '{"ts":"%s","session":"s","tool":"Bash","summary":"pc status"}\n' "$(at 30)" "$(at 40)" \
  | gzip > "$R/log/actions.jsonl.1.gz"
printf '{"ts":"%s","session":"s","tool":"Bash","summary":"pc status"}\n' "$(at 200)" \
  | gzip > "$R/log/actions.jsonl.2.gz"
printf '{"ts":"%s","id":"c1","verified":true}\n' "$(at 1)" > "$R/log/changes.jsonl"
printf '{"ts":"%s","id":"c1","target":"x","before":"a","after":"b"}\n' "$(at 30)" \
  | gzip > "$R/log/changes.jsonl.1.gz"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '[.audit.lines,.changes.window,.changes.verified]')" = '[3,1,1]' ] &&
  ok || no "$(printf '%s' "$o" | jq -c '[.audit.lines,.changes]')"
rm -rf "$R"

t "audit: raw counts key on the op, classes covered/by-design/gap"
R="$(mktemp -d)"; mkdir -p "$R/log"
now=$(date +%Y-%m-%dT%H:%M:%S)
a='{"ts":"%s","session":"s","agent":"toolsmith","tool":"Bash","op":"%s","summary":"%s"}\n'
{ printf "$a" "$now" "pc net" "pc net tailscale"; printf "$a" "$now" "grep tailscale" "grep tailscale x"
  printf "$a" "$now" "tailscale serve" "tailscale serve --bg 80"
  printf "$a" "$now" "tailscale status" "tailscale status"
  printf "$a" "$now" "tailscale status" "cd ~ && tailscale status"
  printf "$a" "$now" "nmcli device" "nmcli device wifi list"; } > "$R/log/actions.jsonl"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '[.audit.raw_total,.audit.raw_coverable,.audit.raw_by_design,
  .audit.raw_gap,.audit.raw_coverable_pct,([.audit.raw_map[]|select(.raw|startswith("tailscale"))|.count]|add),
  (.audit.raw_map|all(has("class")))]')" = '[4,2,1,1,67,3,true]' ] &&
  ok || no "$(printf '%s' "$o" | jq -c .audit.raw_map)"
m="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d --md 2>/dev/null)"
t "--md prints the three raw totals"
printf '%s' "$m" | grep -q 'covered 2 · by-design 1 · gap 1' && ok || no "$(printf '%s' "$m" | grep raw)"
rm -rf "$R"

t "audit: raw counts agent runs only, not interactive or bench"
R="$(mktemp -d)"; mkdir -p "$R/log"
{ printf '{"ts":"%s","session":"a","agent":"toolsmith","tool":"Bash","op":"pactl list","summary":"pactl list"}\n' "$now"
  printf '{"ts":"%s","session":"i","tool":"Bash","op":"pactl list","summary":"pactl list"}\n' "$now"
  printf '{"ts":"%s","session":"b","agent":"bench","tool":"Bash","op":"pactl list","summary":"pactl list"}\n' "$now"
  printf '{"ts":"%s","session":"c","cwd":"/h/agents/bench/runs/x/D01","tool":"Bash","op":"pactl list","summary":"pactl list"}\n' "$now"
} > "$R/log/actions.jsonl"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '[.audit.raw_kind,.audit.raw_total,.audit.lines]')" = '["agent",1,4]' ] &&
  ok || no "$(printf '%s' "$o" | jq -c '.audit|[.raw_kind,.raw_total,.lines]')"
rm -rf "$R"

t "failures: ok:false rows counted by op, newest errors listed"
R="$(mktemp -d)"; mkdir -p "$R/log"
now=$(date +%Y-%m-%dT%H:%M:%S)
{ printf '{"ts":"%s","session":"s","tool":"Bash","op":"pc see","summary":"pc see","ok":true}\n' "$now"
  printf '{"ts":"%s","session":"s","tool":"Bash","op":"pc see","summary":"pc see","ok":false,"error":"Exit code 1"}\n' "$now"
  printf '{"ts":"%s","session":"s","tool":"Bash","op":"pc see","summary":"pc see","ok":false,"error":"Exit code 2"}\n' "$now"
  printf '{"ts":"%s","session":"s","tool":"Read","op":"Read x","summary":"/x","ok":false,"error":"File does not exist"}\n' "$now"
  printf '{"ts":"%s","session":"s","tool":"Bash","op":"ls","summary":"ls"}\n' "$now"; } > "$R/log/actions.jsonl"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '[.failures.rows,.failures.of,.failures.by_op["pc see"],(.failures.recent|length),.failures.recent[-1].error]')" \
  = '[3,5,2,3,"File does not exist"]' ] && ok || no "$(printf '%s' "$o" | jq -c .failures)"
t "failures: top clusters by op + first error line, with the rate"
[ "$(printf '%s' "$o" | jq -c '[.failures.rate_pct,(.failures.clusters|length),.failures.clusters[0].key,.failures.clusters[0].n]')" \
  = '[60.0,3,"pc see · exit 1",1]' ] && ok || no "$(printf '%s' "$o" | jq -c '.failures|{rate_pct,clusters}')"
t "--md prints the failures line"
TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d --md 2>/dev/null | grep -q '^- failures: 3 real of 5 calls (60.0%) · guarded 0 · probe 0 · red-first 0 · bench 0' &&
  ok || no "$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d --md 2>/dev/null | grep -i fail)"
rm -rf "$R"

t "failures: by-design rows classed, rate on real, bench apart"
R="$(mktemp -d)"; mkdir -p "$R/log"
a='{"ts":"%s","session":"%s","agent":"%s","tool":"Bash","op":"%s","summary":"%s","ok":false,"error":"%s"}\n'
{ printf '{"ts":"%s","session":"s","tool":"Bash","op":"ls","summary":"ls","ok":true}\n' "$now"
  printf "$a" "$now" r toolsmith "grep -rn" "grep -rn x ." 'Exit code 97\nleftover'
  printf "$a" "$now" r toolsmith "which eye-tap" "ls; which eye-tap" 'Exit code 1'
  printf "$a" "$now" i "" "bash /h/agents/bin/tests/x.test.sh" "bash /h/agents/bin/tests/x.test.sh" 'Exit code 1\nFAIL — got 3'
  printf "$a" "$now" i "" "python3 f.py" "python3 f.py" 'Exit code 1\nKeyError: x'
  printf "$a" "$now" b bench "systemctl --user" "systemctl --user is-active pcbench-idle.service" 'Exit code 3\ninactive'
  printf '{"ts":"%s","session":"s","tool":"Bash","op":"ls","summary":"ls","ok":true}\n' "$now"; } > "$R/log/actions.jsonl"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '.failures|[.rows,.of,.rate_pct,.by_class,.bench_rows,[.clusters[].key]]')" \
  = '[4,6,16.67,{"guarded":1,"probe":1,"red-first":1,"real":1},1,["exit 1 · KeyError"]]' ] &&
  ok || no "$(printf '%s' "$o" | jq -c '.failures|del(.recent)')"
t "--md prints the four buckets"
TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d --md 2>/dev/null |
  grep -q '^- failures: 1 real of 6 calls (16.7%) · guarded 1 · probe 1 · red-first 1 · bench 1' &&
  ok || no "$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d --md 2>/dev/null | grep -i fail)"
rm -rf "$R"

t "bench_failures: skipped rows out, new arm first, old C no --apply expected"
R="$(mktemp -d)"; mkdir -p "$R/bench/runs/20260103-000000-ab"
{ echo '{"task":"S01","arm":"new","i":1,"pass":0,"skipped":"need:owner_go","reason":"gated: needs owner_go, not granted"}'
  echo '{"task":"C01","arm":"old","i":1,"pass":0,"reason":"state reached but no ledger line (no --apply)"}'
  echo '{"task":"D01","arm":"new","i":1,"pass":0,"reason":"killed the burner"}'
  echo '{"task":"O01","arm":"new","i":1,"pass":1,"reason":""}'; } > "$R/bench/runs/20260103-000000-ab/rows.jsonl"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '.bench_failures|[.fails,.trials,.skipped,.expected,(.rows[0]|[.task,.arm])]')" \
  = '[2,3,1,1,["D01","new"]]' ] && ok || no "$(printf '%s' "$o" | jq -c '.bench_failures|del(.rows)')"
rm -rf "$R"

t "guards: by_reason counts the rule field _guard writes"
R="$(mktemp -d)"; mkdir -p "$R/log"
g='{"ts":"%s","tool":"git","rule":"no push","argv":"push","agent":"a","refused":true}\n'
printf "$g$g" "$(date +%Y-%m-%dT%H:%M:%S)" "$(date +%Y-%m-%dT%H:%M:%S)" > "$R/log/guards.jsonl"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
[ "$(printf '%s' "$o" | jq -c '[.guards.rows,.guards.by_reason["no push"]]')" = '[2,2]' ] &&
  ok || no "$(printf '%s' "$o" | jq -c .guards)"
rm -rf "$R"

t "hold: --check flags a re-queued row"
R="$(mktemp -d)"; mkdir -p "$R/toolsmith/state"
hdr='| rank | id | title | class | status | metric | sessions | score |\n|---|---|---|---|---|---|---|---|\n'
printf "$hdr| 1 | TSP-101 | open | auto-ok | proposed | a | 1 | 9 |\n| 2 | TSP-102 | vetoed | auto-ok | hold | x | 1 | 9 |\n" \
  > "$R/toolsmith/BACKLOG.md"
o="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --since 4d 2>/dev/null)"
printf '%s' "$o" | jq '{hold: .hold.rows}' > "$R/toolsmith/state/last-seen.json"
printf "$hdr| 1 | TSP-102 | vetoed | auto-ok | hold | x | 1 | 9 |\n| 2 | TSP-101 | open | auto-ok | proposed | a | 1 | 9 |\n" \
  > "$R/toolsmith/BACKLOG.md"
TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --check >/dev/null 2>&1; rc1=$?
printf "$hdr| 1 | TSP-102 | vetoed | auto-ok | proposed | x | 1 | 9 |\n" > "$R/toolsmith/BACKLOG.md"
c="$(TOOLSMITH_ROOT="$R" HARNESS_HOME=/nonexistent "$CLI" --check 2>&1)"; rc2=$?
[ "$(printf '%s' "$o" | jq -c '.hold.rows|keys')" = '["TSP-102"]' ] && [ $rc1 = 0 ] && [ $rc2 = 1 ] &&
  printf '%s' "$c" | grep -q TSP-102 && ok || no "keys $(printf '%s' "$o" | jq -c '.hold') rc $rc1/$rc2 $c"
rm -rf "$R"

t "no live probe: the fixture run never calls pc"
grep -q "mock" "$CLI" && [ ! -x "$FIX/bin/pc" ] && ok || no "probe would fall through to live pc"

t "warm run under 5 s"
s=$(date +%s%N); run --since 4d >/dev/null 2>&1; e=$(date +%s%N)
ms=$(( (e - s) / 1000000 ))
[ "$ms" -lt 5000 ] && ok || no "${ms}ms"

t "-h documents the flags"
"$CLI" -h 2>&1 | grep -q -- --since && ok || no "no usage"

[ $fail = 0 ] && echo "toolsmith-inputs.test.sh: all green" || echo "toolsmith-inputs.test.sh: FAILURES"
exit $fail
