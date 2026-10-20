#!/usr/bin/env bash
# host-only: runs the-dark-eye repo's own test (owner repo outside ~/agents)
# The sandbox's own test lives with the body it isolates; run.sh picks it up here.
# T852: `SKIP unchanged` when body/ (HEAD tree + dirty content) and this wrapper match the last green; Sundays (FLEET_CI_DOW) and FLEET_CI_FULL=1 always run.
repo="${BODY_SANDBOX_REPO:-$HOME/the-dark-eye}"
stamp="${BODY_SANDBOX_STAMP:-$HOME/agents/state/body-sandbox.green}"
f="$repo/body/test/body-sandbox.test.sh"
[ -f "$f" ] || { echo "SKIP owner data absent: $f"; exit 0; }

body_key() {
  local g=(env GIT_OPTIONAL_LOCKS=0 git -C "$repo") tree st dirty
  tree=$("${g[@]}" rev-parse HEAD:body 2>/dev/null) || return 1
  st=$("${g[@]}" status --porcelain -- body 2>/dev/null) || return 1
  dirty=$( { "${g[@]}" diff HEAD --binary -- body && "${g[@]}" ls-files -o --exclude-standard -z -- body \
    | (cd "$repo" && xargs -0 -r sha1sum); } 2>/dev/null | sha1sum) || return 1
  printf '%s %s %s %s\n' "$tree" "$(printf '%s' "$st" | sha1sum)" "$dirty" "$(sha1sum < "${BASH_SOURCE[0]}")" | sha1sum | cut -c1-40
}

key=$(body_key) || key=
if [ -n "$key" ] && [ "${FLEET_CI_FULL:-0}" != 1 ] && [ "${FLEET_CI_DOW:-$(date +%u)}" != 7 ] \
  && [ "$(cut -d' ' -f1 "$stamp" 2>/dev/null)" = "$key" ]; then
  echo "SKIP unchanged body (green $(cut -d' ' -f2 "$stamp"))"; exit 0
fi
bash "$f"; rc=$?
[ "$rc" = 0 ] && [ -n "$key" ] && mkdir -p "$(dirname "$stamp")" && echo "$key $(date +%F)" > "$stamp"
exit "$rc"
