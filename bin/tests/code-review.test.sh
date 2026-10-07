#!/usr/bin/env bash
# T74: code-review helper, swarm control flow (canned agents), sandbox, roster and kill switch — fixtures only, no model.
# Every write goes to a temp fixture home (CR_HOME) or a fixture under code-review/state/selftest/; systemctl and
# notify-owner are shims for the roster checks (FLEET.md §5.6). The real agents-stop is never run; no git verb is run.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$BIN/.." && pwd)"
CR="$ROOT/code-review"
fail=0; n=0
t() { n=$((n+1)); printf '%-66s' "code-review: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

WORK=$(mktemp -d); SBX=""
trap 'rm -rf "$WORK"; [ -n "$SBX" ] && rm -rf "$SBX"' EXIT
python3 "$CR/selftest/build.py" "$WORK/home" >/dev/null
H="$WORK/home"; export CR_HOME="$H" CR_DATE=2026-09-26
cr() { python3 "$BIN/code-review" "$@"; }

t "policy: bin edit, backups/research/containment forbidden, harness review-only"
got="$(cr policy "$H/agents/bin/x" "$H/agents/backups/x" "$H/agents/research/x" "$H/moodle-harness/x" "$H/CLAUDE.md" \
  "$H/agents/bin/code-review-sandbox" "$H/agents/bin/guards/git" "$H/agents/.git/index" | cut -f1 | tr '\n' ' ')"
[ "$got" = "edit forbidden forbidden review-only forbidden forbidden forbidden forbidden " ] && ok || no "$got"

t "usage: 0 uses of old-sweeper, >0 of disk-report, coverage >= 28 d"
u="$(cr usage old-sweeper disk-report)"
[ "$(jq '.names["old-sweeper"].uses' <<<"$u")" = 0 ] && [ "$(jq '.names["disk-report"].uses > 0' <<<"$u")" = true ] &&
  [ "$(jq '.coverage_days >= 28' <<<"$u")" = true ] && ok || no "$u"

t "retire: no --why (low use is never a reason) → kept, rc 4"
out="$(cr retire "$H/agents/bin/old-sweeper" --check)"; rc=$?
[ "$rc" = 4 ] && grep -q -- '--why must be one of' <<<"$out" && ok || no "rc=$rc $out"

t "retire: a referenced tool is kept whatever the reason (rc 4)"
out="$(cr retire "$H/agents/bin/disk-report" --why obsolete)"; rc=$?
[ "$rc" = 4 ] && [ -f "$H/agents/bin/disk-report" ] && grep -q 'reference' <<<"$out" && ! grep -q 'use(s)' <<<"$out" && ok || no "rc=$rc $out"

t "retire: duplicate needs an installed --by and a non-empty --proof"
out="$(cr retire "$H/agents/bin/old-sweeper" --why duplicate --by no-such-tool --check)"; rc=$?
[ "$rc" = 4 ] && grep -q 'not installed' <<<"$out" && grep -q -- '--proof' <<<"$out" && ok || no "rc=$rc $out"

t "retire: moves to backups/retired/<date>/ with the reason, restore line works"
out="$(cr retire "$H/agents/bin/old-sweeper" --id F09 --why obsolete)"; rc=$?
line="$(cut -f3 "$H/agents/backups/retired/2026-09-26/MANIFEST.tsv" 2>/dev/null)"
{ [ "$rc" = 0 ] && [ ! -e "$H/agents/bin/old-sweeper" ] && [ -f "$H/agents/backups/retired/2026-09-26/agents/bin/old-sweeper" ] &&
  [ "$(cut -f4 "$H/agents/backups/retired/2026-09-26/MANIFEST.tsv")" = obsolete ] && ! ls "$H/agents/bin" | grep -q cr-retiring &&
  eval "$line" && [ -x "$H/agents/bin/old-sweeper" ]; } && ok || no "rc=$rc $out / $line"

t "claim: absolute, relative and extension-less rows all block (rc 3)"
printf -- '- T99 · %s/agents/bin/log-size · 2026-09-26\n- T77 · KB/guides/INDEX (one line), bin/disk-report · 2026-09-26\n- T74-other · bin/orbit-lite · 2026-09-26\n' "$H" >>"$H/agents/FILE-CLAIMS.md"
r=""; for p in bin/log-size KB/guides/INDEX.md bin/disk-report bin/orbit-lite; do cr claim F01 "$H/agents/$p" >/dev/null 2>&1; r="$r$? "; done
[ "$r" = "3 3 3 3 " ] && ok || no "$r"
sed -i '/^- T99 ·/d; /^- T77 ·/d; /^- T74-other ·/d' "$H/agents/FILE-CLAIMS.md"

t "claim: own claim added and dropped; 10 parallel pairs on one file → 1 winner each"
cr claim F02 "$H/agents/bin/orbit-lite" >/dev/null; rc2=$?
has=$(grep -c '^- code-review-F02 ·' "$H/agents/FILE-CLAIMS.md"); cr unclaim F02 >/dev/null
race=""; for i in $(seq 10); do
  cr claim "A$i" "$H/agents/bin/log-size" >/dev/null 2>&1 & cr claim "B$i" "$H/agents/bin/log-size" >/dev/null 2>&1 & wait
  race="$race$(grep -cE "^- code-review-(A|B)$i ·" "$H/agents/FILE-CLAIMS.md")"
  cr unclaim "A$i" >/dev/null; cr unclaim "B$i" >/dev/null
done
[ "$rc2" = 0 ] && [ "$has" = 1 ] && ! grep -q 'code-review-F02' "$H/agents/FILE-CLAIMS.md" && [ "$race" = 1111111111 ] && ok || no "rc2=$rc2 has=$has race=$race"

export CR_RUN=2026-09-26-030000
B1="$H/agents/backups/code-review/$CR_RUN"
t "backup/restore: content back, what the fix created is moved to displaced/, never deleted"
before="$(sha256sum <"$H/agents/bin/log-size")"
cr backup F03 "$H/agents/bin/log-size" "$H/agents/bin/sizelib.py" >/dev/null
echo '# changed' >>"$H/agents/bin/log-size"; echo 'x=1' >"$H/agents/bin/sizelib.py"
cr restore "$CR_RUN" F03 >/dev/null
{ [ "$(sha256sum <"$H/agents/bin/log-size")" = "$before" ] && [ ! -e "$H/agents/bin/sizelib.py" ] &&
  [ "$(cat "$B1/F03/displaced/agents/bin/sizelib.py")" = x=1 ] && grep -q '# changed' "$B1/F03/displaced/agents/bin/log-size" &&
  [ -f "$B1/F03/RESTORED" ]; } && ok || no "not restored"

t "backup: a same-id rerun gets its own run; restore touches only its run"
echo '# run1 fix' >>"$H/agents/bin/log-size"
CR_RUN=2026-09-26-040000 cr backup F03 "$H/agents/bin/log-size" >/dev/null; r1=$?
echo '# run2 broken' >>"$H/agents/bin/log-size"
CR_RUN=2026-09-26-040000 cr restore 2026-09-26-040000 F03 >/dev/null
cr restore "$CR_RUN" F03 >/dev/null 2>&1; r2=$?
{ [ "$r1" = 0 ] && grep -q '# run1 fix' "$H/agents/bin/log-size" && ! grep -q 'run2 broken' "$H/agents/bin/log-size" && [ "$r2" = 2 ]; } && ok || no "r1=$r1 r2=$r2"
sed -i '/# run1 fix/d' "$H/agents/bin/log-size"

t "backup: dir restore keeps a file written after the backup (displaced/)"
mkdir -p "$H/agents/bin/lib"; echo a >"$H/agents/bin/lib/a.py"
cr backup F04 "$H/agents/bin/lib" >/dev/null; echo b >"$H/agents/bin/lib/new.py"; echo z >"$H/agents/bin/lib/a.py"
cr restore "$CR_RUN" F04 >/dev/null
{ [ "$(cat "$H/agents/bin/lib/a.py")" = a ] && [ ! -e "$H/agents/bin/lib/new.py" ] && [ -f "$B1/F04/displaced/agents/bin/lib/new.py" ]; } && ok || no "dir restore"
rm -rf "$H/agents/bin/lib"

t "backup: refuses forbidden paths, an area root and anything above it"
r=""; for p in agents/secrets/x agents/bin agents .claude/skills; do cr backup F05 "$H/$p" >/dev/null 2>&1; r="$r$? "; done
[ "$r" = "3 3 3 3 " ] && ok || no "$r"

t "tests: a regression and a deletion are not verified (rc 5); a clean change is"
cr backup F06 "$H/agents/bin/disk-report" >/dev/null; cr tests F06 before >/dev/null
cp -p "$H/agents/bin/disk-report" "$WORK/dr"; printf '#!/bin/sh\nexit 3\n' >"$H/agents/bin/disk-report"
cr tests F06 after >/dev/null; r1=$?; cr restore "$CR_RUN" F06 >/dev/null
cr backup F07 "$H/agents/bin/log-size" >/dev/null; cr tests F07 before >/dev/null
mv "$H/agents/bin/log-size" "$WORK/ls"; out="$(cr tests F07 after)"; r2=$?; mv "$WORK/ls" "$H/agents/bin/log-size"
cr backup F08 "$H/agents/KB/guides/disk-report.md" >/dev/null; cr tests F08 before >/dev/null
echo 'Note.' >>"$H/agents/KB/guides/disk-report.md"; cr tests F08 after >/dev/null; r3=$?
{ [ "$r1" = 5 ] && [ "$r2" = 5 ] && grep -q 'deleted agents/bin/log-size' <<<"$out" && [ "$r3" = 0 ] &&
  [ -f "$B1/F08/VERIFIED" ] && [ ! -f "$B1/F06/VERIFIED" ] && cmp -s "$WORK/dr" "$H/agents/bin/disk-report"; } && ok || no "r1=$r1 r2=$r2 r3=$r3 $out"

t "lint: fixture skills and guides pass; a dangling INDEX slug fails"
cr lint skills >/dev/null && cr lint guides >/dev/null; r1=$?
echo '- ghost — nothing · triggers: x' >>"$H/agents/KB/guides/INDEX.md"; cr lint guides >/dev/null; r2=$?
sed -i '/^- ghost —/d' "$H/agents/KB/guides/INDEX.md"
[ "$r1" = 0 ] && [ "$r2" = 1 ] && ok || no "r1=$r1 r2=$r2"

t "refs: skip dirs are matched below HOME, so a fixture under state/ still sees refs"
mkdir -p "$WORK/state/fx"; cp -a "$H" "$WORK/state/fx/h"
mkdir -p "$WORK/state/fx/h/.config/systemd/user"; echo 'ExecStart=%h/agents/bin/old-sweeper' >"$WORK/state/fx/h/.config/systemd/user/sweep.service"
out="$(CR_HOME="$WORK/state/fx/h" cr refs "$WORK/state/fx/h/agents/bin/old-sweeper")"
grep -q '^.config/systemd/user/sweep.service:1$' <<<"$out" && ok || no "$out"
rm -rf "$WORK/state"

t "queue-new: reserves CR-001 with the improve-gate header"
q="$(cr queue-new 'demo item')"
{ [ "$(basename "$q")" = CR-001.md ] && head -1 "$q" | grep -q '^# CR-001 — demo item' && grep -q '^class: owner-go' "$q"; } && ok || no "$q"
rm -f "$q"

unset CR_RUN
t "prep: run id, args.json with fixture areas, 5 lenses, deferred comes back"
args="$(cr prep)"; RUN="$(cat "$H/agents/code-review/state/current-run")"
{ [ "$(jq -r '.mode' "$args")" = fixture ] && [ "$(jq -c '[.areas[].key]' "$args")" = '["bin","skills","guides"]' ] &&
  [ "$(jq '.lenses|length' "$args")" = 5 ] && [ "$(jq -r '.run' "$args")" = "$RUN" ] && [[ "$RUN" == 2026-09-26-* ]] &&
  [ "$(jq '.skip_verdicts | index("deferred")' "$args")" = null ] && [ "$(jq -c '.areas[1].tests' "$args")" = '["code-review lint skills"]' ]; } &&
  ok || no "$(jq -c . "$args" | head -c 300)"

# swarm.js control flow with canned agents: dedup, seen-skip, refute, routing, per-area serial fixes.
mkdir -p "$H/moodle-harness/skills/x"
jq --arg h "$H" '.areas += [{key:"harness", paths:[$h+"/moodle-harness"], tests:[]}]' "$args" >"$WORK/args.json"
seenkey="$(printf '%s' "$H/agents/bin/log-size|bug|main" | tr 'A-Z' 'a-z')"
jq --arg k "$seenkey" --arg f "$H/agents/bin/log-size" '.seen = [{key:$k, verdict:"refuted", date:"2026-09-19", title:"old refuted claim", file:$f}]' "$WORK/args.json" >"$WORK/args2.json"
mock="$(node "$BIN/tests/fixtures/code-review/swarm-mock.mjs" "$CR/swarm.js" "$WORK/args2.json" 2>"$WORK/mock.err")"
res="$(jq -c '.res' <<<"$mock")"
st() { jq -r --arg t "$1" '[.items[] | select(.title == $t) | (.verdict + "/" + (.status // "-"))] | join(",")' <<<"$res"; }

t "swarm: 20 lanes; 11 unique, key-seen 1, reworded-seen 1, merged 1 → 8 distinct"
[ "$(jq '.lanes' <<<"$res")" = 20 ] && [ "$(jq '.unique' <<<"$res")" = 11 ] && [ "$(jq '.fresh' <<<"$res")" = 10 ] &&
  [ "$(jq '.found' <<<"$res")" = 8 ] && [ "$(jq '.merged' <<<"$res")" = 1 ] && ok || no "$(jq -c '{lanes,raw,unique,fresh,found}' <<<"$res") $(cat "$WORK/mock.err")"

t "swarm: 3 refuters per distinct finding (24 verify calls)"
[ "$(jq '[.calls[] | select(startswith("verify:"))] | length' <<<"$mock")" = 24 ] && ok || no "$(jq -c '.calls' <<<"$mock")"

t "swarm: routing — fixes, retire first, bug on the retired tool deferred, valuable tool kept"
got="$(st 'label read before meta lands') $(st 'human_size copied') $(st '--json documented') $(st 'old-sweeper unused') $(st 'old-sweeper hides errors') $(st 'restore-config never used') $(st 'walk is slow') $(st 'harness skill typo')"
[ "$got" = "confirmed/fixed confirmed/fixed confirmed/fixed confirmed/retired confirmed/deferred refuted/- refuted/- confirmed/left" ] && ok || no "$got"

t "swarm: a removal needs 3/3; the valuable tool got 2/3 and no retire lane"
{ [ "$(jq -r '.items[] | select(.title == "restore-config never used") | .votes' <<<"$res")" = 2/3 ] &&
  ! jq -e '.calls[] | select(startswith("retire:")) | select(. != "retire:'"$(jq -r '.items[] | select(.title == "old-sweeper unused") | .id' <<<"$res")"'")' <<<"$mock" >/dev/null; } && ok || no "$(jq -c '.calls' <<<"$mock")"

t "swarm: the merged twin carries its keeper's verdict and is not verified"
{ [ "$(st 'guide label claim wrong')" = "confirmed/fixed" ] &&
  [ "$(jq -r '.items[] | select(.title == "guide label claim wrong") | .merged_into' <<<"$res")" != null ]; } && ok || no "$(st 'guide label claim wrong')"

t "swarm: fix lanes inside one area never overlap"
[ "$(jq '.maxBinLive' <<<"$mock")" = 1 ] && ok || no "max live in bin: $(jq '.maxBinLive' <<<"$mock")"

t "finish: an unverified 'fixed' is restored and deferred; 5 report lines; deliver pushes once"
: >"$H/agents/code-review/REPORT.md"
RD="$H/agents/code-review/state/runs/$RUN"; BR="$H/agents/backups/code-review/$RUN"
id() { jq -r --arg t "$1" '.items[] | select(.title == $t and (.merged_into|not)) | .id' <<<"$res"; }
for t_ in 'label read before meta lands' '--json documented'; do mkdir -p "$BR/$(id "$t_")"; : >"$BR/$(id "$t_")/VERIFIED"; done
D="$(id 'human_size copied')"; cr backup "$D" "$H/agents/bin/log-size" >/dev/null; echo '# unverified edit' >>"$H/agents/bin/log-size"
printf '%s\n' "$res" >"$RD/result.json"
cr finish >/dev/null; cr deliver >/dev/null
rep="$(tr '\n' '|' <"$H/agents/code-review/REPORT.md")"
{ [ "$rep" = "found 8|confirmed 6|fixed 2|retired 1|left 3 (deferred 1, left 1, unverified 1)|" ] &&
  ! grep -q 'unverified edit' "$H/agents/bin/log-size" &&
  [ "$(wc -l <"$H/agents/code-review/state/outbox/notify.log")" = 1 ] && [ -f "$H/agents/code-review/state/outbox/published.md" ] &&
  [ "$(grep -c '"verdict": "deferred"' "$H/agents/code-review/state/seen.jsonl")" = 2 ] &&
  grep -q '^## Fixed' "$RD/findings.md"; } && ok || no "$rep"

t "finish + deliver again for the same run: doc republished, no second push"
n0=$(wc -l <"$H/agents/code-review/state/outbox/notify.log")
cr finish >/dev/null; cr deliver >/dev/null; cr deliver >/dev/null
n1=$(wc -l <"$H/agents/code-review/state/outbox/notify.log")
[ $((n1 - n0)) = 0 ] && ok || no "pushes $((n1 - n0))"

t "cleanup: stale claims dropped, unverified backups restored (a retired item stays retired), timeout report"
cr prep >/dev/null; RUN2="$(cat "$H/agents/code-review/state/current-run")"
cr claim F01 "$H/agents/bin/orbit-lite" >/dev/null; cr backup F01 "$H/agents/bin/orbit-lite" >/dev/null
echo '# half-applied' >>"$H/agents/bin/orbit-lite"
cr backup F03 "$H/agents/bin/old-sweeper" >/dev/null; cr tests F03 before >/dev/null
cr retire "$H/agents/bin/old-sweeper" --id F03 --why obsolete >/dev/null; vt="$(cr tests F03 after)"; rv=$?
rm -f "$H/agents/backups/code-review/$RUN2/F03/VERIFIED"
out="$(cr cleanup)"
{ ! grep -q '^- code-review-' "$H/agents/FILE-CLAIMS.md" && ! grep -q 'half-applied' "$H/agents/bin/orbit-lite" &&
  [ "$rv" = 0 ] && [ ! -e "$H/agents/bin/old-sweeper" ] &&
  grep -q '2 unverified backup(s) restored' <<<"$out" && grep -q 'timeout or crash' "$H/agents/code-review/state/runs/$RUN2/findings.md"; } && ok || no "rv=$rv $vt / $out"

t "redact: tokens and secret-looking values are masked in findings.md"
printf '%s\n' '{"found":1,"items":[{"id":"F01","key":"k","file":"x","kind":"bug","title":"leak","verdict":"confirmed","status":"left","note":"token=abcdef123456 and sk-ant-api03-XXXXYYYYZZZZ"}]}' >"$H/agents/code-review/state/runs/$RUN2/result.json"
cr finish >/dev/null
f="$H/agents/code-review/state/runs/$RUN2/findings.md"
! grep -q 'abcdef123456\|sk-ant-api03' "$f" && grep -q 'redacted' "$f" && ok || no "$(grep leak -A2 "$f")"

# Toolsmith lane (TSP-029): fixture BACKLOG.md and proposals in the fixture home only.
TS="$H/agents/toolsmith"; mkdir -p "$TS/proposals"
cat >"$TS/BACKLOG.md" <<'EOF'
| rank | id | title | class | status | metric before → target | sessions | score |
|---|---|---|---|---|---|---|---|
| 1 | TSP-101 | needs the owner | owner-go | proposed | x → y | 1 | 9 |
| 2 | TSP-102 | vetoed | auto-ok | hold | x → y | 1 | 9 |
| 3 | TSP-103 | open and scoped | auto-ok | proposed | x → y | 1 | 6 |
| - | TSP-000 | example (reference only) | auto-ok | proposed | x → y | 1 | - |
EOF
for i in 101 102 103 000; do printf '# TSP-%s\n\n## Success check\n- metric: m\n- measured by: `grep -c x f%s`\n' "$i" "$i" >"$TS/proposals/TSP-$i.md"; done

t "prep: toolsmith lane takes only auto-ok + proposed (not owner-go, hold, example)"
targs="$(cr prep)"; RUN3="$(cat "$H/agents/code-review/state/current-run")"
[ "$(jq -c '[.toolsmith_backlog[] | [.id, .path, .accept]]' "$targs")" = "[[\"TSP-103\",\"$TS/proposals/TSP-103.md\",\"\`grep -c x f103\`\"]]" ] &&
  ok || no "$(jq -c '.toolsmith_backlog' "$targs")"

t "swarm: one toolsmith lane per backlog item, result carries it as kind toolsmith"
tmock="$(node "$BIN/tests/fixtures/code-review/swarm-mock.mjs" "$CR/swarm.js" "$targs" 2>>"$WORK/mock.err")"
{ [ "$(jq -c '[.calls[] | select(startswith("toolsmith:"))]' <<<"$tmock")" = '["toolsmith:TSP-103"]' ] &&
  [ "$(jq -r '.res.items[] | select(.id == "TSP-103") | [.kind, .verdict, .status] | join("/")' <<<"$tmock")" = toolsmith/confirmed/fixed ]; } &&
  ok || no "$(jq -c '.calls' <<<"$tmock" | head -c 300)"

t "finish: toolsmith append + status flip kept; a changed earlier line is restored"
BR3="$H/agents/backups/code-review/$RUN3"
tsb() { cr backup "TSP-$1" "$TS/proposals/TSP-$1.md" "$TS/BACKLOG.md" >/dev/null; : >"$BR3/TSP-$1/VERIFIED"; }
tsb 103; printf '\n## Result\nlanded\n' >>"$TS/proposals/TSP-103.md"; sed -i 's/| auto-ok | proposed | x → y | 1 | 6 |/| auto-ok | measuring | x → y | 1 | 6 |/' "$TS/BACKLOG.md"
tsb 101; sed -i 's/^- metric: m$/- metric: rewritten/' "$TS/proposals/TSP-101.md"
jq -c '{found: 2, items: [.res.items[] | select(.id == "TSP-103")] + [.res.items[] | select(.id == "TSP-103") | .id = "TSP-101" | .key = "toolsmith|tsp-101"]}' \
  <<<"$tmock" >"$H/agents/code-review/state/runs/$RUN3/result.json"
cr finish >/dev/null
{ grep -q '^## Result' "$TS/proposals/TSP-103.md" && grep -q '| TSP-103 | open and scoped | auto-ok | measuring |' "$TS/BACKLOG.md" &&
  grep -q '^- metric: m$' "$TS/proposals/TSP-101.md" && [ -f "$BR3/TSP-101/RESTORED" ] && [ ! -f "$BR3/TSP-103/RESTORED" ] &&
  grep -q 'earlier lines of the proposal changed' "$H/agents/code-review/state/runs/$RUN3/findings.md"; } && ok ||
  no "$(grep -A1 TSP-10 "$H/agents/code-review/state/runs/$RUN3/findings.md" | head -c 400)"

t "snapshot/snapdiff: equal trees rc 0, one changed byte rc 1"
cr snapshot "$WORK/a.json" "$H/agents/bin" >/dev/null; cr snapshot "$WORK/b.json" "$H/agents/bin" >/dev/null
cr snapdiff "$WORK/a.json" "$WORK/b.json" >/dev/null; r1=$?
echo '#' >>"$H/agents/bin/disk-report"; cr snapshot "$WORK/c.json" "$H/agents/bin" >/dev/null
cr snapdiff "$WORK/a.json" "$WORK/c.json" >/dev/null; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 1 ] && ok || no "r1=$r1 r2=$r2"

# Sandbox: a fixture under state/selftest/, the home read-only, the fixture writable, sockets and network blocked.
unset CR_HOME CR_DATE
SBX="$CR/state/selftest/test-$$"; mkdir -p "$SBX"
python3 "$CR/selftest/build.py" "$SBX/home" >/dev/null

if [ -n "${CR_SANDBOX:-}" ]; then
  echo "code-review: sandbox checks skipped (already inside the code-review sandbox; bwrap cannot nest)"
else
t "sandbox (fixture): selftest proves read-only, hidden, blocked, shimmed"
out="$(bash "$BIN/code-review-sandbox" --fixture "$SBX/home" --selftest 2>&1)" && ok || no "$out"

t "sandbox (fixture): real bin unwritable, fixture writable, shims refuse by full path"
out="$(bash "$BIN/code-review-sandbox" --fixture "$SBX/home" -- bash -c \
  '[ -w "$1" ] && echo realw; touch "$2/agents/bin/probe" && echo fxw; notify-owner hi >/dev/null 2>&1; echo "n=$?"; /usr/bin/systemctl --user status >/dev/null 2>&1; echo "s=$?"' _ "$BIN" "$SBX/home")"
[ "$out" = "$(printf 'fxw\nn=97\ns=97')" ] && ok || no "$out"

t "sandbox: a setsid child does not outlive a timeout (pid namespace)"
timeout 3 bash "$BIN/code-review-sandbox" --fixture "$SBX/home" -- bash -c 'setsid sleep 4747 & sleep 30' >/dev/null 2>&1
sleep 0.5; pgrep -f '^sleep 4747$' >/dev/null && no "sleep 4747 still alive" || ok

t "sandbox (real): selftest proves owner data, containment and sockets"
out="$(bash "$BIN/code-review-sandbox" --selftest 2>&1)" && ok || no "$out"
fi

# Roster and kill switch on shims (the pattern of agents-stop.test.sh): nothing real is stopped or started.
F="$WORK/fleet"; FB="$F/agents/bin"; mkdir -p "$FB" "$F/agents/KB" "$F/agents/code-review"
ln -s "$BIN/env.sh" "$FB/env.sh"; ln -s "$BIN/fleetlib.sh" "$FB/fleetlib.sh"; cp -r "$BIN/guards" "$FB/guards"
cp "$CR/BRIEF.md" "$F/agents/code-review/BRIEF.md"; : >"$F/config.env"
{ sed -n '/^| Agent | Unit/,/^$/p' "$ROOT/KB/orchestrator.md"; } >"$F/agents/KB/orchestrator.md"
CALLS="$F/calls.log"; : >"$CALLS"
cat >"$FB/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$CALLS"
case "$*" in
  *list-units*agent@*.service*) echo "agent@code-review.service loaded active running agent code-review" ;;
  *list-units*agent@*.timer*) echo "agent@code-review.timer loaded active waiting" ;;
  *is-active*agent@code-review*) echo active ;;
  *is-active*) echo inactive ;;
esac
exit 0
EOF
for c in notify-owner claude; do printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n' "$c" >"$FB/$c"; done
chmod +x "$FB/systemctl" "$FB/notify-owner" "$FB/claude"
frun() { HOME="$F" HARNESS_HOME="$F/agents" HARNESS_CONFIG="$F/config.env" HARNESS_AGENT="" CALLS="$CALLS" \
         PATH="$FB:/usr/bin:/bin" bash "$BIN/$1"; }
resolved="$(HOME="$F" HARNESS_HOME="$F/agents" HARNESS_CONFIG="$F/config.env" PATH=/usr/bin:/bin \
  bash -c '. "$HOME/agents/bin/fleetlib.sh"; fleet_path; command -v systemctl; command -v notify-owner')"

t "kill switch selftest: the shims, not the real tools, are on PATH"
[ "$resolved" = "$(printf '%s\n%s' "$FB/systemctl" "$FB/notify-owner")" ] && ok || { no "$resolved"; echo aborting; exit 1; }

t "agents-stop stops agent@code-review service and timer"
frun agents-stop >/dev/null 2>&1
grep -q 'stop agent@code-review.service' "$CALLS" && grep -q 'stop agent@code-review.timer' "$CALLS" && ok || no "$(cat "$CALLS")"

t "agents-start re-enables agent@code-review.timer from KB/orchestrator.md"
: >"$CALLS"; frun agents-start >/dev/null 2>&1
grep -q '^systemctl --user enable --now agent@code-review.timer$' "$CALLS" && ok || no "$(grep enable "$CALLS")"

t "agent.env: Sat 03:00 schedule valid, Workflow tool, sandbox wrap with --post, unit timeout > TIMEOUT"
( . "$CR/agent.env"; systemd-analyze calendar "$SCHEDULE" >/dev/null 2>&1 && [ "$SCHEDULE" = "Sat *-*-* 03:00" ] &&
  case ",$AGENT_TOOLS," in *,Workflow,*) true ;; *) false ;; esac && [ "$AGENT_WRAP" = "code-review-sandbox --post --" ] &&
  [ "$UNIT_TIMEOUT" -gt "$TIMEOUT" ] ) && ok || no "agent.env"

t "agent.env: headless claude waits for the swarm (bg ceiling > 1 h, < TIMEOUT)"
( . "$CR/agent.env"; v=$(bash -c 'echo "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-}"')
  [ -n "$v" ] && [ "$v" -gt 3600000 ] && [ "$v" -lt $((TIMEOUT * 1000)) ] ) && ok || no "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS not exported in range"

[ $fail = 0 ] && echo "code-review.test.sh: $n/$n green" || echo "code-review.test.sh: FAILURES"
exit $fail
