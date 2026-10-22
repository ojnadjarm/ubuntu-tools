#!/usr/bin/env bash
# T730: every skills/<name>/SKILL.md description fits the session skill listing (<= 280 chars; the listing cuts at ~300).
# env: SKILL_DESC_ROOT (default ~/agents/skills), SKILL_DESC_MAX (default 280), SKILL_DESC_PAUSED (default paused-skills.txt beside this file:
#      `<skill><TAB><why>` rows print `skip <skill> (paused)`). Exit 3 = fixture selftest failed.
set -uo pipefail
ROOT=${SKILL_DESC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills" && pwd)}
MAX=${SKILL_DESC_MAX:-280}
PAUSED=${SKILL_DESC_PAUSED:-$(dirname "${BASH_SOURCE[0]}")/paused-skills.txt}

# check <dir> <paused list>: prints `FAIL <skill> <chars>` per over-long or missing description, `skip <skill> (paused)` for a
# paused one, `ok <skill> <chars>` otherwise; exit 1 on any FAIL.
check() {
  python3 - "$1" "$MAX" "$2" <<'PY'
import glob, os, sys
root, mx, bad = sys.argv[1], int(sys.argv[2]), 0
try:
    paused = {l.split("\t")[0].strip() for l in open(sys.argv[3], encoding="utf-8") if l.strip() and not l.startswith("#")}
except OSError:
    paused = set()
for p in sorted(glob.glob(os.path.join(root, "*", "SKILL.md"))):
    lines = open(p, encoding="utf-8").read().split("\n")
    d, fold = None, False
    if lines[0] == "---":
        for l in lines[1:]:
            if l == "---":
                break
            if fold and l[:1] in (" ", "\t"):
                d = (d + " " + l.strip()).strip()
                continue
            fold = False
            if l.startswith("description:"):
                d = l[len("description:"):].strip()
                if d in (">", "|", ">-", "|-", ">+", "|+"):
                    d, fold = "", True
                elif len(d) > 1 and d[0] == d[-1] and d[0] in "\"'":
                    d = d[1:-1]
    name = os.path.basename(os.path.dirname(p))
    if name in paused:
        print(f"skip {name} (paused)")
    elif d is None or len(d) > mx:
        bad = 1
        print(f"FAIL {name} {'none' if d is None else len(d)}")
    else:
        print(f"ok {name} {len(d)}")
sys.exit(bad)
PY
}

selftest() {
  local T out
  T=$(mktemp -d); trap 'rm -rf "$T"' RETURN
  mkdir -p "$T"/{fits,long,folded,quoted,none,held}
  printf -- '---\nname: fits\ndescription: %s\n---\nbody %s\n' "$(printf 'a%.0s' $(seq "$MAX"))" "$(printf 'b%.0s' $(seq 400))" >"$T/fits/SKILL.md"
  printf -- '---\nname: long\ndescription: %s\n---\n' "$(printf 'é%.0s' $(seq $((MAX + 1))))" >"$T/long/SKILL.md"
  printf -- '---\nname: folded\ndescription: >\n  %s\n  %s\nlicense: MIT\n---\n' "$(printf 'c%.0s' $(seq 200))" "$(printf 'd%.0s' $(seq 100))" >"$T/folded/SKILL.md"
  printf -- '---\nname: quoted\ndescription: "%s"\n---\n' "$(printf 'q%.0s' $(seq "$MAX"))" >"$T/quoted/SKILL.md"
  printf -- '---\nname: none\n---\n' >"$T/none/SKILL.md"
  cp "$T/long/SKILL.md" "$T/held/SKILL.md"; printf 'held\tfixture pause\n' >"$T/paused.txt"
  out=$(check "$T" "$T/paused.txt")
  [[ $out == $'ok fits '"$MAX"$'\nFAIL folded 301\nskip held (paused)\nFAIL long '"$((MAX + 1))"$'\nFAIL none none\nok quoted '"$MAX" ]] || {
    echo "FAIL selftest:"; echo "$out"; return 1; }
}

selftest || exit 3
out=$(check "$ROOT" "$PAUSED"); rc=$?
grep -E '^(FAIL|skip)' <<<"$out"
echo "skill-desc: $(grep -c '^ok' <<<"$out") of $(grep -vc '^skip' <<<"$out") descriptions <= $MAX chars in $ROOT"
exit $rc
