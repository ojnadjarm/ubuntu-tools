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
  .audit.pc_verbs.status]')" = '[6,3,1,1,1]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.audit|{raw_total,pc_total,raw_by_tool,pc_verbs}')"

t "audit per-session stats match agents-log --stats shape"
[ "$(printf '%s' "$J" | jq -r '.audit.sessions.aaaa1111.pc')" = 2 ] &&
  ok || no "$(printf '%s' "$J" | jq -c '.audit.sessions')"

t "top raw offender is the session with no pc calls"
[ "$(printf '%s' "$J" | jq -c '.audit.top_raw_offenders[0]|[.session,.raw,.pc]')" = '["bbbb2222",5,0]' ] &&
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

t "idle takes watts and wakers from the mocks"
[ "$(printf '%s' "$J" | jq -c '[.idle.package_w,.idle.gpu_rc6_pct,.idle.wakers[0].comm]')" \
  = '[4.2,98,"kworker/u64:1"]' ] && ok || no "$(printf '%s' "$J" | jq -c .idle)"

t "tokens: per-agent per-run in/out where the columns exist"
[ "$(printf '%s' "$J" | jq -c '[.tokens.columns_present,.tokens.agents.alpha.runs,
  .tokens.agents.alpha.in_per_run,.tokens.agents.alpha.out_per_run,
  (.tokens.agents|has("beta"))]')" = '[true,2,1000,600,false]' ] &&
  ok || no "$(printf '%s' "$J" | jq -c .tokens)"

t "the window actually filters"
[ "$(run --since 1s 2>/dev/null | jq -c '[.audit.lines,.changes.window,(.tokens.agents|length)]')" \
  = '[0,0,0]' ] && ok || no "$(run --since 1s | jq -c .audit.lines)"

t "bad --since is refused"
run --since 4days >/dev/null 2>&1 && no "accepted --since 4days" || ok

t "--md prints the section headings"
M="$(run --since 9999d --md 2>/dev/null)"
n=$(printf '%s\n' "$M" | grep -c '^## ')
{ [ "$n" -ge 5 ] && printf '%s' "$M" | grep -q 'X02/new#1'; } && ok || no "$n headings"

t "--md carries no money either"
printf '%s' "$M" | grep -qiE 'cost|usd|\$' && no "money in --md" || ok

t "an empty root degrades instead of failing"
E="$(mktemp -d)"
o="$(TOOLSMITH_ROOT="$E" HARNESS_HOME=/nonexistent PATH=/usr/bin:/bin \
  "$CLI" --since 4d 2>/dev/null)"
rc=$?
{ [ $rc = 0 ] && printf '%s' "$o" | jq -e '.bench_last.present == false and
  .audit.lines == 0 and .doctor.present == false' >/dev/null; } &&
  ok || no "rc=$rc on an empty root"
rm -rf "$E"

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
