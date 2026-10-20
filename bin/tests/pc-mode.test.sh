#!/usr/bin/env bash
# Fixture test for pc-mode: agent/human/status switching against a file-backed gsettings stub.
# Fixture-only (FLEET §5.6): gsettings, gnome-extensions, gdbus, systemctl, tmux and etckeeper are
# shims on a PATH without ~/agents/bin; HOME is a temp dir. The selftest proves no real call escapes.
set -uo pipefail
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
SHIM="$WORK/shim"; GS="$WORK/gs"; CALLS="$WORK/calls.log"; BLOCKED="$WORK/blocked.log"
mkdir -p "$SHIM" "$GS" "$WORK/home/agents/state"; : >"$CALLS"; : >"$WORK/ext"; : >"$WORK/config.env"
. "$HOME/agents/bin/tests/lib/assert.sh"

for c in systemctl tmux etckeeper sudo; do
  printf '#!/bin/sh\necho "BLOCKED %s $*" >>"%s"\nexit 97\n' "$c" "$BLOCKED" >"$SHIM/$c"
done
# gsettings: values in $GS/<schema>.<key>; an unset key reads the agent value (the schema default).
cat >"$SHIM/gsettings" <<'EOF'
#!/bin/bash
echo "gsettings $*" >>"$CALLS"
declare -A DEF=([org.gnome.desktop.interface.enable-animations]=false [com.ubuntu.update-notifier.no-show-notifications]=true
  [com.ubuntu.update-notifier.regular-auto-launch-interval]=0 [org.gnome.mutter.dynamic-workspaces]=false
  [org.gnome.desktop.wm.preferences.num-workspaces]=1)
val() { [ -f "$GS/$1.$2" ] && cat "$GS/$1.$2" || echo "${DEF[$1.$2]}"; }
known() { [ -n "${DEF[$1.$2]+x}" ] || { echo "BLOCKED gsettings $*" >>"$BLOCKED"; exit 97; }; }
case $1 in
  get) known "$2" "$3"; val "$2" "$3" ;;
  set) known "$2" "$3"; [ "$3" = "${GS_IGNORE_KEY:-}" ] || echo "$4" >"$GS/$2.$3" ;;
  reset) known "$2" "$3"; rm -f "$GS/$2.$3" ;;
  list-recursively) for k in "${!DEF[@]}"; do [ "${k%.*}" = "$2" ] && echo "$2 ${k##*.} $(val "$2" "${k##*.}")"; done ;;
  *) echo "BLOCKED gsettings $*" >>"$BLOCKED"; exit 97 ;;
esac
EOF
cat >"$SHIM/gnome-extensions" <<'EOF'
#!/bin/sh
echo "gnome-extensions $*" >>"$CALLS"
case $1 in
  list) cat "$WORK/ext" ;;
  enable) echo "$2" >"$WORK/ext" ;;
  disable) : >"$WORK/ext" ;;
esac
EOF
printf '#!/bin/sh\necho "gdbus $*" >>"%s"\n' "$CALLS" >"$SHIM/gdbus"
chmod +x "$SHIM"/*

run() {
  env -i HOME="$WORK/home" PATH="$SHIM:/usr/bin:/bin" CALLS="$CALLS" BLOCKED="$BLOCKED" GS="$GS" WORK="$WORK" \
    HARNESS_CONFIG="$WORK/config.env" GS_IGNORE_KEY="${GS_IGNORE_KEY:-}" "$@"
}

# Selftest: every live-state command resolves to a shim, and a real write is refused with 97.
for c in gsettings systemctl gnome-extensions gdbus tmux etckeeper; do
  [ "$(run bash -c "command -v $c")" = "$SHIM/$c" ] || { echo "selftest FAIL: $c not shimmed"; exit 1; }
done
run gsettings set org.gnome.desktop.background picture-uri x; r1=$?
run systemctl --user stop dark-eye.service; r2=$?
[ "$r1" = 97 ] && [ "$r2" = 97 ] && [ "$(wc -l <"$BLOCKED")" = 2 ] || { echo "selftest FAIL: real call not blocked ($r1 $r2)"; exit 1; }
: >"$BLOCKED"; ok "selftest: shims on PATH, real gsettings/systemctl calls blocked"
: >"$CALLS"

out=$(run bash "$BINDIR/pc-mode" status 2>&1); rc=$?
[ "$out" = agent ] && [ "$rc" = 0 ] && ok "status on defaults = agent" || nok "status default" "rc=$rc out=$out"

out=$(run bash "$BINDIR/pc-mode" human 2>&1); rc=$?
if [ "$out" = human ] && [ "$rc" = 0 ] && [ "$(cat "$GS/org.gnome.desktop.wm.preferences.num-workspaces")" = 4 ] \
   && grep -q tiling-assistant "$WORK/ext" && [ "$(cat "$WORK/home/agents/state/pc-mode")" = human ]; then
  ok "human writes keys, enables the extension, records state"
else nok "human" "rc=$rc out=$out"; fi

out=$(run bash "$BINDIR/pc-mode" agent 2>&1); rc=$?
if [ "$out" = agent ] && [ "$rc" = 0 ] && [ -z "$(ls "$GS")" ] && [ ! -s "$WORK/ext" ] \
   && grep -q 'gdbus .*OverviewActive <false>' "$CALLS"; then
  ok "agent resets keys, disables the extension, closes the overview"
else nok "agent" "rc=$rc out=$out"; fi

echo true >"$GS/org.gnome.mutter.dynamic-workspaces"
out=$(run bash "$BINDIR/pc-mode" status 2>&1); rc=$?
[ "$out" = mixed ] && [ "$rc" = 1 ] && ok "one stray key = mixed, exit 1" || nok "mixed" "rc=$rc out=$out"
rm -f "$GS"/*

: >"$CALLS"
out=$(run bash "$BINDIR/pc-mode" bogus 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == usage:* ]] && ! grep -q 'gsettings set\|gsettings reset' "$CALLS" \
  && ok "bad argument: usage, exit 2, nothing written" || nok "bad argument" "rc=$rc out=$out"

out=$(GS_IGNORE_KEY=num-workspaces run bash "$BINDIR/pc-mode" human 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"num-workspaces = 1 (expected 4)"* ]] \
  && ok "read-back mismatch reported, exit 1" || nok "read-back" "rc=$rc out=$out"

[ -s "$BLOCKED" ] && nok "no blocked calls" "$(head -1 "$BLOCKED")" || ok "no blocked call during the run"
[ "$bad" = 0 ] && echo "PASS pc-mode" || { echo "FAIL pc-mode"; exit 1; }
