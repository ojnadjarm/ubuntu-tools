#!/usr/bin/env bash
# PT15: `pc doctor` is night-safe (no window, no pixel, no probe left running) and its rows are
# machine-readable; `pc bench` measures what it is asked for. Nothing here mutates the machine.
set -uo pipefail
BIN="$HOME/agents/bin"; PC="$BIN/pc"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
yes() { [ -n "$2" ] && [ "$2" != false ] && ok "$1" || nok "$1" "$2"; }

# Rows that are known-open findings, not regressions of this ticket. Anything appearing here is
# a real break. PT13's `systemctl restart -- dark-eye` entry (recorded at system scope for a user
# unit, so it verified false) is now `pc undo ack`ed and no longer needs an exception here.
KNOWN=''

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
SHOTS="$HOME/Pictures/Screenshots"

# --- before ------------------------------------------------------------------
before_win=$("$PC" win list 2>/dev/null | md5sum)
before_shots=$(ls "$SHOTS" 2>/dev/null | wc -l)
before_null=$(pactl list modules short 2>/dev/null | grep -c module-null-sink)

# --- 1. --quick --json is a valid, budgeted report ---------------------------
t0=$EPOCHREALTIME
"$PC" doctor --quick --json >"$WORK/q.json" 2>"$WORK/q.err"; rc=$?
ms=$(( (10#${EPOCHREALTIME/./} - 10#${t0/./}) / 1000 ))
yes '--quick --json parses' "$(jq -e 'type=="array" and length>5' "$WORK/q.json" 2>/dev/null)"
yes '--quick --json rows have status/name/detail/ms' \
  "$(jq -e 'all(.[]; (.status|test("^(OK|FAIL|SKIP)$")) and (.name|length>0) and (.ms|type=="number"))' "$WORK/q.json" 2>/dev/null)"
[ "$ms" -le 2500 ] && ok "--quick ran in ${ms}ms (budget 2000 + slack)" || nok '--quick budget' "${ms}ms"
is '--quick exits 0 or 1, never a crash' "$([ $rc -le 1 ] && echo yes)" yes
is '--quick writes nothing to stderr' "$(wc -c <"$WORK/q.err")" 0

fails=$(jq -r 'map(select(.status=="FAIL"))|.[].name' "$WORK/q.json" 2>/dev/null | tr '\n' ' ')
unexpected=""
for f in $fails; do case " $KNOWN " in *" $f "*) ;; *) unexpected="$unexpected $f";; esac; done
[ -z "$unexpected" ] && ok "no FAIL row outside the known-open list (${fails:-none})" \
  || nok 'unexpected FAIL rows' "$unexpected"

# --- 2. the full run stays inside its budget and covers the subcommands ------
t0=$EPOCHREALTIME
"$PC" doctor --json >"$WORK/full.json" 2>/dev/null; rc=$?
ms=$(( (10#${EPOCHREALTIME/./} - 10#${t0/./}) / 1000 ))
[ "$ms" -le 10000 ] && ok "full run in ${ms}ms (budget 10 s)" || nok 'full budget' "${ms}ms"
yes 'the full run sweeps the read-only subcommands' \
  "$(jq -e '[.[]|select(.name|startswith("sub:"))]|length>10' "$WORK/full.json" 2>/dev/null)"
yes 'the full run audits the ledger and the residue' \
  "$(jq -e '[.[].name]|(index("ledger")!=null) and (index("residue")!=null)' "$WORK/full.json" 2>/dev/null)"
yes 'doctor never sweeps a mutating verb' \
  "$(jq -e '[.[].name]|all(test("apply|shot|find|click|type|key|open|notify|selftest|speak")|not)' "$WORK/full.json" 2>/dev/null)"

# --- 3. it opened no window, took no screenshot, left no probe --------------
is 'the window list is unchanged' "$("$PC" win list 2>/dev/null | md5sum)" "$before_win"
is 'no new file in Pictures/Screenshots' "$(ls "$SHOTS" 2>/dev/null | wc -l)" "$before_shots"
is 'no null sink was loaded' "$(pactl list modules short 2>/dev/null | grep -c module-null-sink)" "$before_null"
left=""
for p in bpftrace busctl perf evtest; do pgrep -x "$p" >/dev/null 2>&1 && left="$left $p"; done
is 'no probe process survived doctor' "$left" ''

# --- 4. pc bench ------------------------------------------------------------
"$PC" bench --only status win --runs 1 >"$WORK/b.txt" 2>/dev/null
is 'bench --only prints one row per command' "$(wc -l <"$WORK/b.txt")" 2
yes 'a bench row carries wall/cold/CPU/execs' \
  "$(grep -cE '^status +[0-9]+\.[0-9]+ s +[0-9]+\.[0-9]+ s +[0-9]+\.[0-9]+ s +[0-9]+ +pc status$' "$WORK/b.txt")"
yes 'bench --json is an array of measurements' \
  "$("$PC" bench --only undo --runs 1 --json 2>/dev/null | jq -e '.[0]|has("wall_warm_ms") and has("wall_cold_ms") and has("cpu_ms") and has("execs")')"
"$PC" bench --only status --save >/dev/null 2>&1
is 'bench --save refuses a partial sweep' "$?" 2
yes 'the saved baseline still holds the per-ticket notes' \
  "$(grep -c '^## Per-ticket notes' "$BIN/tests/BASELINE-PCTOOLS.md")"
yes 'the saved baseline holds a bench table between its markers' \
  "$(awk '/pc-bench:begin/{r=1} /pc-bench:end/{r=0} r && /^\| 20/{n++} END{print (n>10)}' "$BIN/tests/BASELINE-PCTOOLS.md")"

# --- 5. the ledger check exempts an acked unverified entry -------------------
FLED="$WORK/ledger-acked.jsonl"
cat >"$FLED" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakeacked1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":""}
{"id":"fakeacked1","verified":false,"observed":"a"}
{"ts":"2026-01-02T00:00:00+0000","id":"fakeacked1","ack":true,"why":"known non-issue","session":"s1"}
EOF
row=$(PC_LEDGER="$FLED" "$PC" doctor --quick --json 2>/dev/null | jq -c '.[]|select(.name=="ledger")')
is 'acked-only ledger reports OK' "$(jq -r .status <<<"$row")" OK
case "$(jq -r .detail <<<"$row")" in *'unverified, acked'*) ok 'acked-only ledger row says acked';; *) nok 'acked-only ledger row says acked' "$row";; esac

FLED2="$WORK/ledger-mixed.jsonl"
cat >"$FLED2" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakeacked1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":""}
{"id":"fakeacked1","verified":false,"observed":"a"}
{"ts":"2026-01-02T00:00:00+0000","id":"fakeacked1","ack":true,"why":"known non-issue","session":"s1"}
{"ts":"2026-01-01T00:00:00+0000","id":"fakeunackd1","session":"s1","cmd":"bar","target":"t2","before":"x","after":"y","rollback":"r2","read":""}
{"id":"fakeunackd1","verified":false,"observed":"x"}
EOF
row=$(PC_LEDGER="$FLED2" "$PC" doctor --quick --json 2>/dev/null | jq -c '.[]|select(.name=="ledger")')
is 'an unacked unverified entry still fails' "$(jq -r .status <<<"$row")" FAIL
case "$(jq -r .detail <<<"$row")" in *fakeunackd1*) ok 'the FAIL row names the unacked id';; *) nok 'the FAIL row names the unacked id' "$row";; esac

[ $bad = 0 ] && echo 'PASS pc-doctor' || echo 'FAIL pc-doctor'
exit $bad
