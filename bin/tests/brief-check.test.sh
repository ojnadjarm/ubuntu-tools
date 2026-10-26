#!/usr/bin/env bash
# T381: brief-lint flags the four rules (T396: and warns on a missing decisions ledger; T401: and on /dev/zero fed to script/tmux); agent-verify writes green/red check.json into a temp AGENT_WORK only.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/brief-check"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export AGENT_WORK="$WORK"
. "$HOME/agents/bin/tests/lib/assert.sh"

# 1. lint: green (rules via _common include) and red pass; bare misses all four.
"$BIN/brief-lint" "$FIX/T901-green.md" "$FIX/T902-red.md" >/dev/null && ok 'lint passes complete briefs' || nok 'lint complete' 'rc != 0'
out=$("$BIN/brief-lint" "$FIX/T903-bare.md"); rc=$?
[ "$rc" = 1 ] && grep -q 'missing check, claims, timebox, report-cap' <<<"$out" && ok 'lint flags 4/4 on bare brief' || nok 'lint bare' "rc=$rc $out"
[ "$("$BIN/brief-lint" --summary "$FIX"/T90*.md)" = 'pass 2/3 · check 2/3 · claims 2/3 · timebox 2/3 · report-cap 2/3' ] \
  && ok 'summary counts' || nok 'summary' "$("$BIN/brief-lint" --summary "$FIX"/T90*.md)"

# 2. verify green: rc 0, backticks stripped, json ok=true under the temp AGENT_WORK.
"$BIN/agent-verify" "$FIX/T901-green.md" >/dev/null; rc=$?
j="$WORK/evidence/T901/check.json"
[ "$rc" = 0 ] && python3 -c "import json,sys;d=json.load(open('$j'));sys.exit(not(d['ok'] and d['rc']==0 and d['check']=='echo hello && true' and d['stdout_tail']=='hello'))" \
  && ok 'green check.json' || nok 'green' "rc=$rc"

# 3. verify red: rc 1, json ok=false rc=3 with stderr.
"$BIN/agent-verify" "$FIX/T902-red.md" >/dev/null; rc=$?
j="$WORK/evidence/T902/check.json"
[ "$rc" = 1 ] && python3 -c "import json,sys;d=json.load(open('$j'));sys.exit(not(d['ok'] is False and d['rc']==3 and d['stderr_tail']=='boom'))" \
  && ok 'red check.json' || nok 'red' "rc=$rc"

# 4. no CHECK line: rc 2, nothing written; timeout gives rc 124.
"$BIN/agent-verify" "$FIX/T903-bare.md" 2>/dev/null; rc=$?
[ "$rc" = 2 ] && [ ! -e "$WORK/evidence/T903" ] && ok 'no CHECK → rc 2, no evidence' || nok 'no CHECK' "rc=$rc"
printf 'CHECK: sleep 5\n' > "$WORK/T904-slow.md"
"$BIN/agent-verify" --timeout 1 "$WORK/T904-slow.md" >/dev/null; rc=$?
[ "$rc" = 1 ] && grep -q '"rc": 124' "$WORK/evidence/T904/check.json" && ok 'timeout → rc 124 recorded' || nok 'timeout' "rc=$rc"
# T412: a timeout kills the whole process group, so a backgrounded grandchild does not survive.
printf 'CHECK: sleep 300 & echo $! > %s/T905.pid; wait\n' "$WORK" > "$WORK/T905-bg.md"
"$BIN/agent-verify" --timeout 2 "$WORK/T905-bg.md" >/dev/null; rc=$?
pid=$(cat "$WORK/T905.pid" 2>/dev/null); sleep 0.2
alive=0; [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && { alive=1; kill "$pid"; }
[ "$rc" = 1 ] && [ "$alive" = 0 ] && grep -q '"rc": 124' "$WORK/evidence/T905/check.json" \
  && ok 'timeout kills the process group (0 survivors)' || nok 'timeout group' "rc=$rc survivors=$alive"

# 5. decisions ledger (T396): a brief naming a project without its ledger warns, rc stays 0; naming the ledger is quiet.
out=$("$BIN/brief-lint" "$FIX/T910-noref.md"); rc=$?
[ "$rc" = 0 ] && grep -q "^WARN .*names ailearning but not its decisions ledger $WORK/decisions/ailearning.md" <<<"$out" \
  && ok 'lint warns on a missing decisions ledger' || nok 'decisions warn' "rc=$rc $out"
out=$("$BIN/brief-lint" "$FIX/T911-ref.md"); rc=$?
[ "$rc" = 0 ] && ! grep -q WARN <<<"$out" && ok 'lint quiet when the ledger is named' || nok 'decisions quiet' "rc=$rc $out"

# 6. /dev/zero into script/tmux (T401): brief and --tests DIR warn, rc stays 0; the real tests folder is clean.
out=$("$BIN/brief-lint" "$FIX/T912-devzero.md"); rc=$?
[ "$rc" = 0 ] && grep -q "^WARN .*T912-devzero.md:2: /dev/zero feeds script/tmux" <<<"$out" \
  && ok 'lint warns on /dev/zero in a brief' || nok 'devzero brief' "rc=$rc $out"
mkdir "$WORK/tests"; z='/dev/'zero
printf 'cat %s | tmux attach -t a\nhead -c 9 %s > f\n' "$z" "$z" > "$WORK/tests/x.test.sh"
out=$("$BIN/brief-lint" --tests "$WORK/tests"); rc=$?
[ "$rc" = 0 ] && [ "$out" = "WARN $WORK/tests/x.test.sh:1: /dev/zero feeds script/tmux; use </dev/null or \`sleep inf |\`" ] \
  && ok 'lint --tests warns once, rc 0' || nok 'devzero tests' "rc=$rc $out"
out=$("$BIN/brief-lint" --tests); [ -z "$out" ] && ok 'bin/tests has no /dev/zero feed' || nok 'bin/tests devzero' "$out"

# 6b. change tiers (T1399): a CHECK at the full tier (perf gate, whole run.sh) without `Class: engine` warns, rc stays 0.
tb() { printf '# %s\nFILE-CLAIMS, time box 1 h. Report: max 5 lines.\n%sCHECK: %s\n' "$1" "$2" "$3" >"$WORK/$1.md"; "$BIN/brief-lint" "$WORK/$1.md"; }
out=$(tb T1 '' 'cd ~/m/client && npm run test:perf'); rc=$?
[ "$rc" = 0 ] && grep -q "^WARN .*T1.md: CHECK runs test:perf but the brief has no \`Class: engine\` line" <<<"$out" && ok 'tier: test:perf without Class warns' || nok 'tier perf' "rc=$rc $out"
out=$(tb T2 '' 'bash ~/agents/bin/tests/run.sh -j 8'); grep -q 'CHECK runs tests/run.sh without --only' <<<"$out" && ok 'tier: full run.sh warns' || nok 'tier run.sh' "$out"
out=$(tb T3 '' 'bash ~/agents/bin/tests/run.sh --only x.test.sh'); ! grep -q 'CHECK runs' <<<"$out" && ok 'tier: run.sh --only is quiet' || nok 'tier only' "$out"
out=$(tb T4 $'Class: engine\n' 'npm run test:all'); ! grep -q 'CHECK runs' <<<"$out" && ok 'tier: Class: engine is quiet' || nok 'tier engine' "$out"

# 7. --backlog (T913): fields, one CHECK each, consecutive ids, --min CHECKs, top-K Files disjoint, heavy calls niced.
bl() {  # bl FILE: five clean tickets T801..T805; a grep naming make.sh is not a call
  for k in 1 2 3 4 5; do
    printf '## %s. T80%s Title\n- Size S · auto-ok\n- Files: ~/x/t%s.sh (new), ~/x/d%s/ (after T80%s)\n- Success: ok\n' "$k" "$k" "$k" "$k" "$k"
    printf 'CHECK: nice -n 19 bash ~/x/t%s.sh && grep -q make.sh ~/x/t%s.sh && ci-window && blender -b\n\n' "$k" "$k"
  done > "$1"; }
B="$WORK/bl.md"; bl "$B"
out=$("$BIN/brief-lint" --backlog "$B" --min 5 --top 5); rc=$?
[ "$rc" = 0 ] && [ "$out" = 'backlog: 5 tickets, 0 problems' ] && ok 'backlog clean → rc 0' || nok 'backlog clean' "rc=$rc $out"
out=$("$BIN/brief-lint" --backlog "$B"); rc=$?
[ "$rc" = 1 ] && grep -qx 'backlog: 5 CHECKs < 20' <<<"$out" && ok 'backlog --min default 20 named' || nok 'backlog min' "rc=$rc $out"
sed -i 's#^- Files: ~/x/t5.sh (new)#- Files: ~/x/d2/f.sh#' "$B"
out=$("$BIN/brief-lint" --backlog "$B" --min 5); rc=$?
[ "$rc" = 1 ] && grep -qx "#2 T802 and #5 T805: both claim $HOME/x/d2/f.sh" <<<"$out" && ok 'backlog overlap #2/#5 (dir covers child) named' || nok 'backlog overlap' "rc=$rc $out"
"$BIN/brief-lint" --backlog "$B" --min 5 --top 4 >/dev/null && ok 'backlog overlap outside --top ignored' || nok 'backlog top' 'rc != 0'
bl "$B"; sed -i 's#^CHECK: nice -n 19 bash ~/x/t3.sh#CHECK: cd ~/x \&\& bin/tests/run.sh --only t3 | grep -q ok \&\& nice -n 19 bash ~/x/t3.sh#; s#ci-window && blender -b##' "$B"
out=$("$BIN/brief-lint" --backlog "$B" --min 5); rc=$?
[ "$rc" = 1 ] && [ "$(grep -c 'without' <<<"$out")" = 1 ] && grep -qx '#3 T803: CHECK calls run.sh without `nice -n 19` or `ci-window &&`' <<<"$out" \
  && ok 'backlog un-niced run.sh named (1 hit)' || nok 'backlog nice' "rc=$rc $out"
bl "$B"; sed -i '/^- Files: ~\/x\/t4.sh/d; s/^## 5. T805/## 5. T807/; /CHECK: nice -n 19 bash ~\/x\/t1.sh/p' "$B"
out=$("$BIN/brief-lint" --backlog "$B" --min 5); rc=$?
[ "$rc" = 1 ] && grep -qx '#4 T804: missing Files' <<<"$out" && grep -qx '#5 T807: id not consecutive after T804' <<<"$out" \
  && grep -qx '#1 T801: 2 CHECK lines, want 1' <<<"$out" && grep -qx 'backlog: 5 tickets, 3 problems' <<<"$out" \
  && ok 'backlog missing Files, id gap, 2 CHECKs named' || nok 'backlog fields' "rc=$rc $out"
bl "$B"; sed -i 's#^- Files: ~/x/t1.sh (new), .*#- Files: ~/x/a1 (after T5, T6), ~/x/av (`--recheck [--since 7d]`), ~/x/{p,q}/S.md#;
  s#^- Files: ~/x/t2.sh (new), .*#- Files: ~/x/a2 (after T5, T6), ~/x/av, ~/x/q/S.md#;
  s#^- Size S · auto-ok$#- Size S#; s#^- Success: ok#- Success: auto-ok#;
  s#^CHECK: nice -n 19 bash ~/x/t3.sh#CHECK: timeout 600 run.sh \&\& sudo blender -b \&\& nice ffmpeg -i a#; s#ci-window && blender -b##' "$B"
out=$("$BIN/brief-lint" --backlog "$B" --min 5); rc=$?
[ "$rc" = 1 ] && grep -qx "#1 T801 and #2 T802: both claim $HOME/x/av" <<<"$out" && grep -qx "#1 T801 and #2 T802: both claim $HOME/x/q/S.md" <<<"$out" \
  && ! grep -q 'T6)' <<<"$out" && [ "$(grep -c '#3 T803: CHECK calls' <<<"$out")" = 3 ] && [ "$(grep -c 'missing gate' <<<"$out")" = 5 ] \
  && grep -qx 'backlog: 5 tickets, 10 problems' <<<"$out" \
  && ok 'backlog notes/braces parsed, timeout/sudo/bare nice flagged, gate only on Size' || nok 'backlog T913 fixes' "rc=$rc $out"

[ "$bad" = 0 ] && echo "all brief-check cases pass" || echo "FAILURES"
exit "$bad"
