#!/usr/bin/env bash
# T607: every motion-video/gamedev script, MV_* variable of shot.py, mv-encode/mv-mix usage flag and cpp-ci stage is named in its SKILL.md or reference/*.md (T671).
# Scripts and MV_* vars match anywhere as a whole word; a flag or stage must sit on a line that names its script.
set -uo pipefail
SK=${SKILL_DOCS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills" && pwd)}
MV=$SK/motion-video GD=$SK/gamedev

# miss <doc> <kind> <name> [<line-filter>]: prints `MISSING <kind> <name> in <doc>` unless the doc names it.
miss() {
  local doc=$1 kind=$2 name=$3 line=${4:-} re
  case $kind in
    var) re="${name}([^A-Z0-9_]|\$)" ;;
    *) re="(^|[^A-Za-z0-9_-])${name}([^A-Za-z0-9_-]|\$)" ;;
  esac
  if [[ -n $line ]]; then grep -F -- "$line" "$doc" | grep -qE -- "$re"; else grep -qE -- "$re" "$doc"; fi && return 1
  echo "MISSING $kind $name in ${doc#"$SK"/}"
}

usage_flags() { sed -n '/^usage() {/,/^U$/p' "$1" | grep -oE -- '--[a-z][a-z0-9-]*' | sort -u; }

check() {  # check <mv-doc> <gd-doc>
  local f s
  for f in "$MV"/scripts/* "$GD"/scripts/*; do
    [[ -f $f && -x $f ]] || continue
    if [[ $f == "$MV"/* ]]; then miss "$1" script "${f##*/}"; else miss "$2" script "${f##*/}"; fi
  done
  for s in $(grep -oE 'MV_[A-Z_]+' "$MV/templates/blender/shot.py" | sort -u); do miss "$1" var "$s"; done
  for f in mv-encode mv-mix; do
    for s in $(usage_flags "$MV/scripts/$f"); do miss "$1" flag "$s" "$f"; done
  done
  for s in $(sed -nE 's/^stage_([a-z]+)\(\).*/\1/p' "$GD/scripts/cpp-ci"); do miss "$2" stage "$s" cpp-ci; done
}

# Selftest: an empty doc misses every name, so the extractors found something in each source.
empty=$(mktemp) mvdoc=$(mktemp --suffix=-motion-video-docs) gddoc=$(mktemp --suffix=-gamedev-docs); trap 'rm -f "$empty" "$mvdoc" "$gddoc"' EXIT
self=$(check "$empty" "$empty")
for k in script var flag stage; do
  grep -q "^MISSING $k " <<<"$self" || { echo "FAIL selftest: no $k names extracted"; exit 1; }
done

cat "$MV/SKILL.md" "$MV"/reference/*.md >"$mvdoc" 2>/dev/null
cat "$GD/SKILL.md" "$GD"/reference/*.md >"$gddoc" 2>/dev/null
out=$(check "$mvdoc" "$gddoc")
n=$(grep -c '^MISSING' <<<"$self")
[[ -z $out ]] && { echo "skill-docs: $n names, all documented"; exit 0; }
echo "$out"
echo "skill-docs: $(grep -c . <<<"$out") of $n names missing"
exit 1
