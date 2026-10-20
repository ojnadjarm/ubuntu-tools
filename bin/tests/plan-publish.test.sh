#!/usr/bin/env bash
# Fixture test for plan-publish: markdown and html pages, index.json upserts, --link, bad arguments.
# Fixture-only (FLEET §5.6): HOME is a temp dir so the real dashboard plans/ is never written; eye,
# systemctl, gsettings, tmux and etckeeper are shims on a PATH without ~/agents/bin, proven by the selftest.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plan-publish"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
SHIM="$WORK/shim"; CALLS="$WORK/calls.log"; BLOCKED="$WORK/blocked.log"; PLANS="$WORK/home/agents/dashboard/plans"
mkdir -p "$SHIM" "$WORK/home"; : >"$CALLS"
. "$HOME/agents/bin/tests/lib/assert.sh"

for c in systemctl gsettings tmux etckeeper sudo notify-owner; do
  printf '#!/bin/sh\necho "BLOCKED %s $*" >>"%s"\nexit 97\n' "$c" "$BLOCKED" >"$SHIM/$c"
done
printf '#!/bin/sh\necho "eye $*" >>"%s"\n' "$CALLS" >"$SHIM/eye"
chmod +x "$SHIM"/*

run() {
  env -i HOME="$WORK/home" PATH="$SHIM:/usr/bin:/bin" HARNESS_TAILNET_FQDN=host.test "$@"
}

# Selftest: every live-state command resolves to a shim, and a real call is refused with 97.
for c in systemctl gsettings tmux etckeeper eye; do
  [ "$(run bash -c "command -v $c")" = "$SHIM/$c" ] || { echo "selftest FAIL: $c not shimmed"; exit 1; }
done
run systemctl --user restart dark-eye-dashboard.service; r1=$?
run gsettings set org.gnome.mutter dynamic-workspaces true; r2=$?
[ "$r1" = 97 ] && [ "$r2" = 97 ] && [ "$(wc -l <"$BLOCKED")" = 2 ] || { echo "selftest FAIL: real call not blocked ($r1 $r2)"; exit 1; }
: >"$BLOCKED"; ok "selftest: shims on PATH, real systemctl/gsettings blocked, HOME is a temp dir"

D=$(date +%F)
printf '# My Plan\n\n## Step one\n\n- a\n- b\n' >"$WORK/plan.md"
out=$(run python3 "$BIN" "$WORK/plan.md" 2>&1); rc=$?
page="$PLANS/my-plan-$D/index.html"
if [ "$rc" = 0 ] && [ "$out" = "http://host.test:19998/plans/my-plan-$D/" ] && grep -q '<h2>Step one</h2>' "$page" \
   && grep -q '<span>plan</span>' "$page" && [ ! -s "$CALLS" ]; then
  ok "markdown renders into the shell page, prints the tailnet URL, no eye call"
else nok "markdown" "rc=$rc out=$out"; fi

idx() { python3 -c 'import json,sys; print(" ".join("%s:%s" % (e["slug"], e["kind"]) for e in json.load(open(sys.argv[1]))))' "$PLANS/index.json"; }
[ "$(idx)" = "my-plan-$D:plan" ] && ok "index.json has one entry" || nok "index" "$(idx)"

out=$(run python3 "$BIN" "$WORK/plan.md" --kind report --link 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(idx)" = "my-plan-$D:report" ] && ok "republish upserts, no duplicate" || nok "upsert" "rc=$rc $(idx)"
grep -qx "eye link http://host.test:19998/plans/my-plan-$D/ My Plan --to remote" "$CALLS" \
  && ok "--link hands the URL to eye" || nok "--link" "$(cat "$CALLS")"

printf '<html><body>raw page</body></html>' >"$WORK/demo.html"
out=$(run python3 "$BIN" "$WORK/demo.html" --slug "Demo Page!" --kind preview 2>&1); rc=$?
[ "$rc" = 0 ] && cmp -s "$WORK/demo.html" "$PLANS/demo-page-$D/index.html" \
  && ok "html is copied verbatim under the slugified name" || nok "html" "rc=$rc out=$out"

out=$(run python3 "$BIN" "$WORK/missing.md" 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"no such file"* ]] && ok "missing file: exit 1" || nok "missing file" "rc=$rc $out"

n=$(ls "$PLANS" | wc -l)
out=$(run python3 "$BIN" "$WORK/plan.md" --kind bogus 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"invalid choice"* ]] && [ "$(ls "$PLANS" | wc -l)" = "$n" ] \
  && ok "bad --kind: exit 2, nothing written" || nok "bad kind" "rc=$rc $out"

[ -s "$BLOCKED" ] && nok "no blocked calls" "$(head -1 "$BLOCKED")" || ok "no blocked call during the run"
[ "$bad" = 0 ] && echo "PASS plan-publish" || { echo "FAIL plan-publish"; exit 1; }
