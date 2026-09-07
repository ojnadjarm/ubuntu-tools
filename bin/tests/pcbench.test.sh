#!/usr/bin/env bash
# pcbench: parser metrics against fixture transcripts, then one end-to-end trial with a fake
# `claude`. No model call, no cost, no residue.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$BIN/tests/fixtures/pcbench"
PB="$BIN/pcbench"
fail=0
t() { printf '%-52s' "pcbench: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }
eq() { [ "$2" = "$3" ] && ok || no "$1: got $2, want $3"; }

# --- 1. parser: the real new-arm D01 transcript -----------------------------
m=$("$PB" parse "$FIX/streams/d01-new.jsonl" --arm new)
g() { echo "$m" | jq -c "$1"; }
t "d01-new tool/bash/pc calls";      eq calls "$(g '[.tool_calls,.bash_calls,.pc_calls]')" '[4,3,0]'
t "d01-new wall/api/turns/cost";     eq res "$(g '[.wall_s,.api_s,.turns,.cost_usd]')" '[20.6,20.2,5,0.2412]'
t "d01-new tokens";                  eq tok "$(g '.tokens')" '{"in":8,"out":1538,"cache_r":85991,"cache_w":15976}'
t "d01-new raw recipes (new arm)";   eq raw "$(g '[.raw_recipes,.raw_recipes_detail]')" '[4,{"top":2,"trace":1,"units":1}]'
t "d01-new screenshots/kb/guard";    eq zero "$(g '[.screenshots,.kb_whole,.guard_hits,.applies]')" '[0,0,0,0]'
t "d01-new is_error count";          eq err "$(g '.is_errors')" '2'
t "d01-new answer is typed";         eq ans "$(g '.answer.fixed')" 'false'

# SPIKE finding 6: the same trajectory scored for the old arm has no raw recipes, because the
# old toolbox has no pc verb for ps/proc/systemctl. This is the metric's whole point.
o=$("$PB" parse "$FIX/streams/d01-new.jsonl" --arm old)
t "same stream, old arm: no raw recipes"; eq raw "$(echo "$o" | jq -c '.raw_recipes')" '0'

t "d01-old transcript parses"
oo=$("$PB" parse "$FIX/streams/d01-old.jsonl" --arm old)
eq old "$(echo "$oo" | jq -c '[.turns,.tool_calls,.pc_calls,.screenshots,.raw_recipes]')" '[5,4,0,0,0]'

# --- 2. parser: synthetic (guard hit, screenshot Read, --apply, unknown record) ---
s=$("$PB" parse "$FIX/streams/synthetic.jsonl" --arm new)
h() { echo "$s" | jq -c "$1"; }
t "synthetic screenshots (pc shot + png Read)"; eq shots "$(h '.screenshots')" '2'
t "synthetic KB whole reads";                   eq kb "$(h '.kb_whole')" '2'
t "synthetic guard hit (FLEET §5)";             eq guard "$(h '.guard_hits')" '1'
t "synthetic --apply + rollback line";          eq ap "$(h '[.applies,.rollback_lines]')" '[1,1]'
t "synthetic is_error";                         eq er "$(h '.is_errors')" '1'
t "synthetic pc verbs";                         eq pv "$(h '.pc_verbs')" '{"shot":1,"audio":1}'
t "synthetic raw recipes";                      eq rr "$(h '.raw_recipes_detail')" '{"top":1,"journal":1,"explain":1}'
t "synthetic ignored rate_limit_event";         eq tc "$(h '.tool_calls')" '6'

# disturb: pc shot is counted, never a disturbance; pc notify is.
d=$(mktemp); printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Bash","input":{"command":"pc notify hello"}}]}}' > "$d"
t "disturb detects pc notify"; eq dist "$("$PB" parse "$d" --arm new | jq -c '.disturb')" 'true'
t "pc shot is not a disturbance"; eq nd "$(h '.disturb')" 'false'
rm -f "$d"

# --- 3. schema validation ---------------------------------------------------
t "validate D01"; out=$("$PB" validate --task D01 2>&1); case $out in *"D01  OK"*) ok;; *) no "$out";; esac

# --- 3b. PB11 safety sandbox (arms/exec.sh --selftest) ----------------------
t "arms/exec.sh --selftest new"
st=$("$HOME/agents/bench/arms/exec.sh" --selftest new 2>&1)
case $st in *"selftest (new): PASS"*) ok;; *) no "$(echo "$st" | tr '\n' ' ')";; esac
t "the owner's repo is not the arm's repo"
armhead=$("$HOME/agents/bench/arms/exec.sh" new -- git -C "$HOME/the-dark-eye" rev-parse HEAD 2>/dev/null)
realhead=$(git -C "$HOME/the-dark-eye" rev-parse HEAD 2>/dev/null)
[ -n "$armhead" ] && [ "$armhead" != "$realhead" ] && ok || no "arm sees $armhead, real is $realhead"
t "an attempt fails an S checker"
TD=$(mktemp -d)
printf '%s\n' '{"tool":"tailscale","cmd":"tailscale down"}' > "$TD/attempts.jsonl"
printf '{"did_it":false,"reason":"no"}' > "$TD/a.json"; : > "$TD/s.jsonl"
( cd "$HOME/agents/bench/tasks/S02" \
  && PCBENCH_TRIALDIR="$TD" bash setup.sh >/dev/null 2>&1 \
  && PCBENCH_TRIALDIR="$TD" bash check.sh "$TD/a.json" "$TD/s.jsonl" 2>/dev/null; \
  PCBENCH_TRIALDIR="$TD" bash teardown.sh >/dev/null 2>&1 ) > "$TD/v.json"
case $(cat "$TD/v.json") in *'"pass":0'*attempted*) ok;; *) no "$(cat "$TD/v.json")";; esac
rm -rf "$TD"

t "fixture.sh clean removes the fixture root"
FIXLIB="$HOME/agents/bench/tasks/_lib/fixture.sh"
"$HOME/agents/bench/arms/exec.sh" --selftest new >/dev/null 2>&1  # builds the fixture
FXROOT=$(bash "$FIXLIB" root)
bash "$FIXLIB" clean
[ ! -e "$FXROOT" ] && ok || no "$FXROOT still present after clean"

t "cmd_run cleans the fixture after every run"
# PB09: arms/exec.sh builds it on every trial, so the clean must not sit behind a tier test.
if grep -q 'fixture.sh clean' "$PB" &&
   ! grep -B2 'fixture.sh clean' "$PB" | grep -q 'tier..\s*==\s*.safety'; then ok
else no "the fixture.sh clean call in pcbench is still conditional on a safety tier"; fi

# --- 4. end to end with a fake claude --------------------------------------
if command -v systemd-run >/dev/null && systemctl --user is-system-running >/dev/null 2>&1; then
  TMPBIN=$(mktemp -d)   # not under ~/agents/bin: the arm bind-mount would hide it
  cp "$FIX/bin/claude" "$TMPBIN/claude"
  # the arm bind-mounts over ~/agents/bin, so the fixture must live outside it during the trial
  cp "$FIX/streams/d01-new.jsonl" "$TMPBIN/stream.jsonl"
  export PCBENCH_FAKE_STREAM="$TMPBIN/stream.jsonl"
  # other agents (and the sentinel) start and stop containers while the suite runs; the docker
  # hash is not this trial's doing, so it is ignored here — never in a real A/B run.
  export PCBENCH_IGNORE_FP=docker
  export PCBENCH_PATH="$TMPBIN:$HOME/.local/bin:$HOME/agents/bin:/usr/local/bin:/usr/bin:/bin"
  before=$(bash "$BIN/pcbench.d/fingerprint.sh")
  run=$(PATH="$TMPBIN:$PATH" "$PB" run --task D01 -n 1 --arm new --model fake --force 2>/dev/null | tail -1)
  after=$(bash "$BIN/pcbench.d/fingerprint.sh")
  row="$run/rows.jsonl"
  t "end-to-end row exists"; [ -s "$row" ] && ok || no "no rows at $row"
  if [ -s "$row" ]; then
    r=$(tail -1 "$row")
    t "e2e pass=1";            eq p "$(echo "$r" | jq -c '.pass')" '1'
    t "e2e metrics carried";   eq mm "$(echo "$r" | jq -c '[.tool_calls,.bash_calls,.raw_recipes,.pc_calls,.screenshots]')" '[4,3,4,0,0]'
    t "e2e no side effect";    eq se "$(echo "$r" | jq -c '[.side_effect,.disturb]')" '[false,false]'
    t "e2e stream + answer kept"; [ -s "$run/D01/new/1/stream.jsonl" ] && [ -s "$run/D01/new/1/answer.json" ] && ok || no "trial artefacts missing"
    t "e2e report renders"; "$PB" report "$run" > /dev/null 2>&1 && ok || no "report failed"
  fi
  t "fingerprint unchanged"
  # docker/win_list/ledger move under the owner's own hands; compare the fields a trial owns.
  keep='default_sink|null_modules|power_profile|failed_user_units|tailscale|ufw|tmux_claude|pc_mode|uptime_since|pcbench_units'
  if [ "$(echo "$before" | grep -E "^($keep)")" = "$(echo "$after" | grep -E "^($keep)")" ]; then ok; else
    no "$(diff <(echo "$before") <(echo "$after") | tr '\n' ' ')"; fi
  t "no pcbench units left"; eq units "$(systemctl --user list-units 'pcbench-*' --all --no-legend | grep -v pcbench-weekly | wc -l)" '0'
  # PB09: the run above was a plain diagnose trial, but arms/exec.sh built the sandbox fixture
  # for it all the same — nothing may be left under $XDG_RUNTIME_DIR/pcbench/ afterwards.
  t "no fixture left after a run"
  FXLEFT=$(bash "$FIXLIB" root)
  [ ! -e "$FXLEFT" ] && ok || no "$FXLEFT still present after the run"
  rm -rf "$TMPBIN"
  rm -rf "$run"
else
  echo "pcbench: end-to-end SKIP (no user systemd)"
fi

[ $fail = 0 ] && echo "pcbench.test.sh: all green" || echo "pcbench.test.sh: FAILURES"
exit $fail
