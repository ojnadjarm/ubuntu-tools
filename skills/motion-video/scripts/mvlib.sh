# shellcheck shell=bash
# Shared finish block for the motion build scripts (sourced): build.json verdict + one creative-ci.jsonl line via gamedev ci-lib's ci_log.
source "$(dirname "${BASH_SOURCE[0]}")/../../gamedev/scripts/ci-lib.sh"

mv_finish() {  # NAME BUILD_JSON FAIL...: sets build.json review PASS|FAIL + fails, + chain true when the sourcing build.sh set CHAIN=1, copies it to <project>/.builds/<UTC time>-<pid>.json (last 10 kept; a failed copy warns, rc unchanged), logs tool mv-build (failed as tag:reason), prints each FAIL; rc 1 on any
  local name=$1 b=$2 f j h t e; shift 2
  f=$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(. != ""))')
  j=$(jq --argjson f "$f" --argjson c "$([[ ${CHAIN:-0} == 1 ]] && echo true || echo false)" \
    '. + {review: (if $f == [] then "PASS" else "FAIL" end), fails: $f} + if $c then {chain: true} else {} end' "$b") && printf '%s\n' "$j" >"$b"
  h=$(dirname "$(dirname "$(readlink -f "$b")")")/.builds
  t=$h/$(date -u +%Y%m%dT%H%M%SZ)-$BASHPID.json
  e=$({ mkdir -p "$h" && cp "$b" "$t"; } 2>&1) || printf 'mv_finish: build history not kept: %s\n' "${e%%$'\n'*}" >&2
  [[ -f $t ]] && find "$h" -maxdepth 1 -name '*.json' | sort | head -n -10 | xargs -r rm -f
  ci_log mv-build "$name" "$([[ $f == '[]' ]] && echo true || echo false)" "$(jq -c 'map(sub(": +"; ":"))' <<<"$f")" "$(readlink -f "$b")"
  [[ $f == '[]' ]] && return
  printf 'build: FAIL %s\n' "$@" >&2
  return 1
}
