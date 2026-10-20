#!/usr/bin/env bash
# host-only
# T525: lists ~/.claude/skills/<name> that no git repo tracks into SKILLS_UNTRACKED_OUT; exit 1 while a fleet-owned one is untracked.
# Tracked = a symlink to a non-ignored path in a git work tree (committing is the owner's), a tracked `skills/<name>/SKILL.md`, or a SKILL.md identical to a tracked one.
# env: SKILLS_DIR (default ~/.claude/skills), SKILL_REPOS (default ~/agents ~/moodle-harness ~/the-dark-eye),
#      SKILLS_UNTRACKED_OUT (default ~/agents/state/skills-untracked.txt). Exit 3 = fixture selftest failed.
set -uo pipefail

class_of() {
  case $1 in
    finance-month|invoice) echo personal ;;
    make-lesson|explainer-engine|cutaway-style) echo ailearning ;;
    *) echo fleet ;;
  esac
}

# scan <skills_dir> <out> <repo>... : writes `<name>\t<class>` rows, returns 1 when a fleet row exists.
scan() {
  local dir=$1 out=$2 r f n p known="" fleet=0
  shift 2
  for r; do
    while IFS= read -r -d '' f; do
      [[ $f =~ (^|/)skills/([^/]+)/SKILL\.md$ ]] && known+="name ${BASH_REMATCH[2]}"$'\n'
      known+="sum $(sha256sum <"$r/$f" | cut -d' ' -f1)"$'\n'
    done < <(git -C "$r" ls-files -z -- '*SKILL.md' 2>/dev/null)
  done
  {
    echo "# skills in $dir that no repo tracks (moving them is owner-go): name<TAB>fleet|personal|ailearning"
    for p in "$dir"/*/; do
      p=${p%/}; n=${p##*/}
      [[ -f $p/SKILL.md ]] || continue
      if [[ -L $p ]] && git -C "$(readlink -f "$p")" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        && ! git -C "$(readlink -f "$p")" check-ignore -q SKILL.md; then continue; fi
      grep -qxF "name $n" <<<"$known" && continue
      grep -qxF "sum $(sha256sum <"$p/SKILL.md" | cut -d' ' -f1)" <<<"$known" && continue
      printf '%s\t%s\n' "$n" "$(class_of "$n")"
    done
  } >"$out"
  grep -q $'\tfleet$' "$out" && fleet=1
  return $fleet
}

selftest() {
  local T rc
  T=$(mktemp -d); trap 'rm -rf "$T"' RETURN
  mkdir -p "$T/repo/skills/named" "$T/repo/other" "$T/repo/linked" "$T/repo/ign" "$T/sk"
  echo named >"$T/repo/skills/named/SKILL.md"; echo copied >"$T/repo/other/SKILL.md"; echo linked >"$T/repo/linked/SKILL.md"
  git -C "$T/repo" init -q && git -C "$T/repo" add -A && echo /ign/ >"$T/repo/.gitignore"
  mkdir "$T/repo/fresh"; echo fresh >"$T/repo/fresh/SKILL.md"; echo ign >"$T/repo/ign/SKILL.md"
  for n in loose invoice make-lesson named copied; do mkdir "$T/sk/$n"; echo "$n" >"$T/sk/$n/SKILL.md"; done
  echo diverged >"$T/sk/named/SKILL.md"
  ln -s "$T/repo/linked" "$T/sk/linked"; ln -s "$T/repo/fresh" "$T/sk/fresh"; ln -s "$T/repo/ign" "$T/sk/ign"; mkdir "$T/sk/synced"
  scan "$T/sk" "$T/out" "$T/repo"; rc=$?
  [[ $rc == 1 && $(grep -v '^#' "$T/out") == $'ign\tfleet\ninvoice\tpersonal\nloose\tfleet\nmake-lesson\tailearning' ]] || { echo "selftest: fleet case rc=$rc"; cat "$T/out"; return 1; }
  rm -rf "$T/sk/loose" "$T/sk/ign"
  scan "$T/sk" "$T/out" "$T/repo" || { echo "selftest: no-fleet case did not exit 0"; return 1; }
}

selftest || exit 3
out=${SKILLS_UNTRACKED_OUT:-$HOME/agents/state/skills-untracked.txt}
# shellcheck disable=SC2086
scan "${SKILLS_DIR:-$HOME/.claude/skills}" "$out" ${SKILL_REPOS:-$HOME/agents $HOME/moodle-harness $HOME/the-dark-eye}; rc=$?
grep -v '^#' "$out" | awk -F'\t' '{c[$2]++} END {for (k in c) printf "%s=%d ", k, c[k]; print ""}'
[[ $rc == 0 ]] && { echo "ok: no fleet skill outside a repo"; exit 0; }
# Red only with SKILLS_TRACKED_STRICT=1 until the owner decides on the move (owner-todo, T525).
[[ ${SKILLS_TRACKED_STRICT:-0} == 1 ]] && { echo "FAIL: fleet skills outside a repo, see $out"; exit "$rc"; }
echo "WARN: fleet skills outside a repo, see $out (owner decision pending)"
