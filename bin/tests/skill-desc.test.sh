#!/usr/bin/env bash
# T730: every skills/<name>/SKILL.md description fits the session skill listing (<= 280 chars; the listing cuts at ~300).
# env: SKILL_DESC_ROOT (default ~/agents/skills), SKILL_DESC_MAX (default 280). Exit 3 = fixture selftest failed.
set -uo pipefail
ROOT=${SKILL_DESC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills" && pwd)}
MAX=${SKILL_DESC_MAX:-280}

# check <dir>: prints `FAIL <skill> <chars>` per over-long or missing description, `ok <skill> <chars>` otherwise; exit 1 on any FAIL.
check() {
  python3 - "$1" "$MAX" <<'PY'
import glob, os, sys
root, mx, bad = sys.argv[1], int(sys.argv[2]), 0
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
    if d is None or len(d) > mx:
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
  mkdir -p "$T"/{fits,long,folded,quoted,none}
  printf -- '---\nname: fits\ndescription: %s\n---\nbody %s\n' "$(printf 'a%.0s' $(seq "$MAX"))" "$(printf 'b%.0s' $(seq 400))" >"$T/fits/SKILL.md"
  printf -- '---\nname: long\ndescription: %s\n---\n' "$(printf 'é%.0s' $(seq $((MAX + 1))))" >"$T/long/SKILL.md"
  printf -- '---\nname: folded\ndescription: >\n  %s\n  %s\nlicense: MIT\n---\n' "$(printf 'c%.0s' $(seq 200))" "$(printf 'd%.0s' $(seq 100))" >"$T/folded/SKILL.md"
  printf -- '---\nname: quoted\ndescription: "%s"\n---\n' "$(printf 'q%.0s' $(seq "$MAX"))" >"$T/quoted/SKILL.md"
  printf -- '---\nname: none\n---\n' >"$T/none/SKILL.md"
  out=$(check "$T")
  [[ $out == $'ok fits '"$MAX"$'\nFAIL folded 301\nFAIL long '"$((MAX + 1))"$'\nFAIL none none\nok quoted '"$MAX" ]] || {
    echo "FAIL selftest:"; echo "$out"; return 1; }
}

selftest || exit 3
out=$(check "$ROOT"); rc=$?
grep '^FAIL' <<<"$out"
echo "skill-desc: $(grep -c '^ok' <<<"$out") of $(grep -c . <<<"$out") descriptions <= $MAX chars in $ROOT"
exit $rc
