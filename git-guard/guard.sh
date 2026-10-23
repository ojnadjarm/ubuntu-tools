#!/bin/sh
# Fleet git hook for work repos (T1251): under an agent marker refuse commit, push, merge, rebase and branch/HEAD writes; always run the repo's own hook after.
name=${0##*/}
agent=
for v in CLAUDECODE HARNESS_AGENT OPENCODE GEMINI_CLI CODEX_SANDBOX CODEX_THREAD_ID; do
  eval "[ -n \"\${$v:-}\" ]" && { agent=$v; break; }
done
refuse() {
  echo "work-repo-guard (T1251): $1 refused in this work repo because $agent is set; agents never write git here, the owner does it by hand." >&2
  exit 1
}
own="$(git rev-parse --git-common-dir 2>/dev/null)/hooks/$name"
if [ "$name" = reference-transaction ]; then
  input=$(cat)
  if [ -n "$agent" ] && [ "$1" = prepared ]; then
    printf '%s\n' "$input" | while read -r old new ref; do
      case $ref in refs/heads/*|HEAD) ;; *) continue ;; esac
      case $new in ref:*|0000000000000000000000000000000000000000) continue ;; esac
      exit 1
    done || refuse "updating a branch or HEAD (commit, merge, rebase, reset, cherry-pick)"
  fi
  [ -x "$own" ] || exit 0
  printf '%s\n' "$input" | exec "$own" "$@"
fi
if [ -n "$agent" ]; then
  case $name in
    pre-commit|pre-merge-commit) refuse "git commit" ;;
    pre-push) refuse "git push" ;;
    pre-rebase) refuse "git rebase" ;;
  esac
fi
[ -x "$own" ] || exit 0
exec "$own" "$@"
