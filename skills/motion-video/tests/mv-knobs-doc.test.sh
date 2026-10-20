#!/usr/bin/env bash
# mv-knobs-doc.test.sh: every MV_* name read in scripts/ or templates/ is documented in SKILL.md or reference/*.md (T780).
set -uo pipefail
SKILL=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
cd "$SKILL" || exit 1
bad=0 n=0
for k in $(grep -rhoEI --exclude-dir=node_modules 'MV_[A-Z0-9_]+' scripts templates | sort -u); do
  n=$((n + 1))
  grep -qw -- "$k" SKILL.md reference/*.md && continue
  echo "FAIL undocumented $k (read by: $(grep -rlwI --exclude-dir=node_modules -- "$k" scripts templates | tr '\n' ' '))"
  bad=$((bad + 1))
done
echo "knobs $n, undocumented $bad"
((bad == 0))
