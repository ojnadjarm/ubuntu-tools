#!/usr/bin/env bash
# run.sh <off|on> <outdir> | --oracle | --selftest: one headless Task RAM trial on the seeded fixture, then its score.
set -uo pipefail
H=$(cd "$(dirname "$0")" && pwd)
SEED=1839
# T1844: 32 stages of 3 modules, each opened by the gate when the previous one is green (Opus handled a stage in one
# call at 16 stages: T1844 run 2). Window 100,000: Claude Code rejects a CLAUDE_CODE_AUTO_COMPACT_WINDOW under 100k
# (80,000 ran on the default window, run 1). RAM_FLAT=1: T1840's grown fixture (36/12); RAM_SMALL=1: its first one.
SIZE=(--stages 32); WINDOW=100000; U=(1000 4000); P=(45000 65000)
[ -n "${RAM_FLAT:-}" ] && SIZE=(--modules 36 --bugs 12) && WINDOW=100000 && U=(18000 30000) && P=(18000 30000)
[ -n "${RAM_SMALL:-}" ] && SIZE=(--modules 24 --bugs 8) && WINDOW=100000 && U=(12000 20000) && P=(12000 20000)

# Refuse a trial folder outside /tmp or inside a git work tree, or an AGENT_WORK that is the real one.
guard() {
  local t aw real d
  t=$(realpath -m "$1"); aw=$(realpath -m "$2"); real=$(realpath -m "$HOME/agent-work")
  case "$t" in /tmp/?*) ;; *) echo "run.sh: refused: trial $t is not under /tmp" >&2; return 3 ;; esac
  d=$t; while [ ! -d "$d" ]; do d=$(dirname "$d"); done
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "run.sh: refused: trial $t is inside a git work tree" >&2; return 3
  fi
  case "$aw/" in "$real"/*) echo "run.sh: refused: AGENT_WORK $2 resolves to the real $real" >&2; return 3 ;; esac
}

# score <fixture> <key> <outdir>: suite green or red, answers right of 6, tests untouched -> <outdir>/score.json.
score() {
  (cd "$1" && python3 -B -m unittest discover -s tests > "$3/suite.txt" 2>&1)
  local rc=$?
  python3 - "$1" "$2" "$3" "$rc" "$H/make-fixture.py" <<'EOF'
import importlib.machinery, json, os, sys
fx, key, out, rc, mf = sys.argv[1:]
mk = importlib.machinery.SourceFileLoader("mf", mf).load_module()
k = json.load(open(key))
try:
    got = json.load(open(os.path.join(fx, "ANSWERS.json")))
except (OSError, ValueError):
    got = {}
norm = lambda s: str(s).strip().strip("`'\" .").lower().removeprefix("ledgerkit.").removesuffix(".py")
right = sum(1 for q, a in k["answers"].items() if norm(got.get(q, "")) == norm(a))
done = "stages" not in k or os.path.exists(os.path.join(fx, "QUESTIONS.md"))   # staged: every stage opened
s = {"suite": "green" if rc == "0" and done else "red", "answers": right, "of": len(k["answers"]),
     "tests_untouched": mk.tree_hash(os.path.join(fx, "tests")) == k["tests_sha256"],
     "suite_chars": len(open(os.path.join(out, "suite.txt")).read())}
json.dump(s, open(os.path.join(out, "score.json"), "w"))
print(json.dumps(s))
EOF
}

# fixture <trial>: generate the seeded fixture in <trial>/fixture, the key in its own temp folder; prints the key path.
fixture() {
  local kd
  kd=$(mktemp -d /tmp/ram-key.XXXXXX)
  "$H/make-fixture.py" --seed "$SEED" "$1/fixture" --key "$kd/key.json" "${SIZE[@]}" || { rm -rf "$kd"; return 1; }
  echo "$kd/key.json"
}

oracle() {
  local T K O s ok=0
  T=$(mktemp -d /tmp/ram-oracle.XXXXXX); guard "$T" "$T/agent-work" || return 3
  K=$(fixture "$T") || { rm -rf "$T"; return 1; }
  O=$T/out; mkdir -p "$O"
  s=$(score "$T/fixture" "$K" "$O"); echo "unpatched: $s"
  python3 -c 'import json,sys; s=json.loads(sys.argv[1]); sys.exit(not (s["suite"] == "red" and int(sys.argv[2]) <= s["suite_chars"] <= int(sys.argv[3])))' "$s" "${U[@]}" || ok=1
  if [ "${SIZE[0]}" = --stages ]; then  # staged: each stage's patch, then the gate opens the next
    for n in $(seq 1 "${SIZE[1]}"); do
      python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["patches"][sys.argv[2]], end="")' "$K" "$n" | patch -s -p1 -d "$T/fixture" || ok=1
      (cd "$T/fixture" && python3 gate.py >/dev/null 2>&1) || { echo "gate red after stage $n's patch"; ok=1; }
    done
  else
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["patch"], end="")' "$K" | patch -s -p1 -d "$T/fixture" || ok=1
  fi
  python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))["answers"], open(sys.argv[2], "w"))' "$K" "$T/fixture/ANSWERS.json"
  s=$(score "$T/fixture" "$K" "$O"); echo "patched: $s"
  python3 -c 'import json,sys; s=json.loads(sys.argv[1]); sys.exit(not (s["suite"] == "green" and s["answers"] == 6 and s["tests_untouched"] and int(sys.argv[2]) <= s["suite_chars"] <= int(sys.argv[3])))' "$s" "${P[@]}" || ok=1
  rm -rf "$T" "$(dirname "$K")"
  [ $ok = 0 ] && echo "oracle: ok" || echo "oracle: FAIL"
  return $ok
}

selftest() {
  local S fail=0 stub out
  S=$(mktemp -d /tmp/ram-selftest.XXXXXX)
  mkdir -p "$S/bin" "$S/repo/trial"; git init -q "$S/repo"
  stub=$S/bin/claude
  printf '#!/bin/sh\ntouch %s/launched\nexit 1\n' "$S" > "$stub"; chmod +x "$stub"
  ln -s "$HOME/agent-work" "$S/aw-link"
  expect() {  # expect <refused|accepted> <what> <RAM_TRIAL> <RAM_AGENT_WORK>
    PATH=$S/bin:$PATH RAM_TRIAL=$3 RAM_AGENT_WORK=$4 RAM_GUARD_ONLY=1 "$H/run.sh" off "$S/out" 2>"$S/err"
    local rc=$?
    if { [ "$1" = refused ] && [ $rc = 3 ]; } || { [ "$1" = accepted ] && [ $rc = 0 ]; }; then
      echo "selftest: ok   $2"
    else
      echo "selftest: FAIL $2 (rc=$rc: $(cat "$S/err"))"; fail=1
    fi
  }
  expect refused "trial outside /tmp" "$HOME/ram-trial-never" "$S/aw"
  expect refused "trial resolving outside /tmp" "/tmp/../$HOME/ram-trial-never" "$S/aw"
  expect refused "trial inside a git work tree" "$S/repo/trial" "$S/aw"
  expect refused "AGENT_WORK is the real one" "$S/t1" "$HOME/agent-work"
  expect refused "AGENT_WORK under the real one" "$S/t1" "$HOME/agent-work/evidence"
  expect refused "AGENT_WORK links to the real one" "$S/t1" "$S/aw-link"
  expect accepted "a temp trial with its own AGENT_WORK" "$S/t1" "$S/t1/agent-work"
  # A refused run never reaches the model, and leaves no trial behind.
  PATH=$S/bin:$PATH RAM_TRIAL=$S/repo/trial "$H/run.sh" off "$S/out" 2>/dev/null
  if [ -e "$S/launched" ] || [ -e "$S/repo/trial/fixture" ]; then echo "selftest: FAIL refused run went on"; fail=1
  else echo "selftest: ok   refused run launches nothing"; fi
  rm -rf "$S"
  [ $fail = 0 ] && echo "selftest: ok" || echo "selftest: FAIL"
  return $fail
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --oracle) oracle; exit $? ;;
  off|on) ;;
  *) echo "usage: run.sh <off|on> <outdir> | --oracle | --selftest" >&2; exit 2 ;;
esac
arm=$1; out=${2:?outdir}
T=${RAM_TRIAL:-$(mktemp -d /tmp/ram-trial.XXXXXX)}
AW=${RAM_AGENT_WORK:-$T/agent-work}
guard "$T" "$AW" || exit 3
[ -n "${RAM_GUARD_ONLY:-}" ] && exit 0
mkdir -p "$out" "$AW"; out=$(realpath "$out")
K=$(fixture "$T") || exit 1
ramenv=(TASK_RAM=off); [ "$arm" = on ] && ramenv=(TASK_RAM=on RAM_TICKET=F1)
# Launch flags from pcbench build_cmd (SPIKE §2): bypassPermissions, no Agent tool, user settings only, stream-json, < /dev/null.
cmd=(env "${ramenv[@]}" AGENT_WORK="$AW" CLAUDE_CODE_AUTO_COMPACT_WINDOW=$WINDOW
     timeout "${RAM_TRIAL_S:-5400}" claude -p "Read TASK.md in the current folder and do it." --model opus --effort high
     --permission-mode bypassPermissions --disallowedTools Agent --setting-sources user
     --output-format stream-json --verbose --name "ram-$arm")
printf '%q ' "${cmd[@]}" > "$out/cmd.sh"; echo >> "$out/cmd.sh"
date -Is > "$out/start"
(cd "$T/fixture" && "${cmd[@]}" < /dev/null > "$out/stream.jsonl" 2> "$out/stderr.log")
echo $? > "$out/exit"; date -Is > "$out/end"
sid=$(head -1 "$out/stream.jsonl" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("session_id",""))' 2>/dev/null)
tr=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)
[ -n "$sid" ] && [ -n "$tr" ] && cp "$tr" "$out/transcript.jsonl"
cp -f "$T/fixture/ANSWERS.json" "$out/" 2>/dev/null
score "$T/fixture" "$K" "$out"
[ -s "$out/transcript.jsonl" ] && "$H/count.py" --header "$out/transcript.jsonl" "$arm" | tee "$out/row.md"
[ -z "${RAM_TRIAL:-}" ] && rm -rf "$T"; rm -rf "$(dirname "$K")"
