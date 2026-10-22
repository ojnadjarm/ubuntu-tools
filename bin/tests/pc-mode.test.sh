#!/usr/bin/env bash
# Fixture test for pc-mode: agent/human/status switching against a file-backed gsettings stub.
# Fixture-only (FLEET §5.6): gsettings, gnome-extensions, gdbus, systemctl, tmux and etckeeper are
# shims on a PATH without ~/agents/bin; HOME is a temp dir. The selftest proves no real call escapes.
set -uo pipefail
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
SHIM="$WORK/shim"; GS="$WORK/gs"; CALLS="$WORK/calls.log"; BLOCKED="$WORK/blocked.log"
mkdir -p "$SHIM" "$GS" "$WORK/home/agents/state" "$WORK/modes"; : >"$CALLS"; : >"$WORK/config.env"
EXT=tiling-assistant@ubuntu.com; MODEJSON='{ "enabledExtensions": [ "ubuntu-dock@ubuntu.com", "tiling-assistant@ubuntu.com" ] }'
echo "$MODEJSON" >"$WORK/modes/ubuntu.json"
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
  [org.gnome.desktop.wm.preferences.num-workspaces]=1 [org.gnome.shell.enabled-extensions]='@as []'
  [org.gnome.shell.disabled-extensions]='@as []' [org.gnome.shell.disable-user-extensions]=false)
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
# gnome-extensions: enable/disable edit the shell keys as GNOME Shell does; list is never expected.
cat >"$SHIM/gnome-extensions" <<'EOF'
#!/bin/sh
echo "gnome-extensions $*" >>"$CALLS"
case $1 in
  enable) echo "['$2']" >"$GS/org.gnome.shell.enabled-extensions"; echo '@as []' >"$GS/org.gnome.shell.disabled-extensions" ;;
  disable) echo '@as []' >"$GS/org.gnome.shell.enabled-extensions"; echo "['$2']" >"$GS/org.gnome.shell.disabled-extensions" ;;
  *) echo "BLOCKED gnome-extensions $*" >>"$BLOCKED"; exit 97 ;;
esac
EOF
printf '#!/bin/sh\necho "gdbus $*" >>"%s"\n' "$CALLS" >"$SHIM/gdbus"
chmod +x "$SHIM"/*

run() {
  env -i HOME="$WORK/home" PATH="$SHIM:/usr/bin:/bin" CALLS="$CALLS" BLOCKED="$BLOCKED" GS="$GS" WORK="$WORK" \
    HARNESS_CONFIG="$WORK/config.env" GS_IGNORE_KEY="${GS_IGNORE_KEY:-}" PC_SHELL_MODES="$WORK/modes" "$@"
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
off() { echo "['$EXT']" >"$GS/org.gnome.shell.disabled-extensions"; }
off

out=$(run bash "$BINDIR/pc-mode" status 2>&1); rc=$?
[ "$out" = agent ] && [ "$rc" = 0 ] && ok "status on defaults = agent" || nok "status default" "rc=$rc out=$out"
grep -q '^gnome-extensions' "$CALLS" && nok "status asks the shell" "$(grep '^gnome-extensions' "$CALLS")" \
  || ok "status makes no gnome-extensions (D-Bus) call"

out=$(run bash "$BINDIR/pc-mode" human 2>&1); rc=$?
if [ "$out" = human ] && [ "$rc" = 0 ] && [ "$(cat "$GS/org.gnome.desktop.wm.preferences.num-workspaces")" = 4 ] \
   && grep -q "$EXT" "$GS/org.gnome.shell.enabled-extensions" && [ "$(cat "$WORK/home/agents/state/pc-mode")" = human ]; then
  ok "human writes keys, enables the extension, records state"
else nok "human" "rc=$rc out=$out"; fi

out=$(run bash "$BINDIR/pc-mode" agent 2>&1); rc=$?
if [ "$out" = agent ] && [ "$rc" = 0 ] && [ -z "$(ls "$GS" | grep -v '^org.gnome.shell\.')" ] \
   && grep -q "$EXT" "$GS/org.gnome.shell.disabled-extensions" \
   && grep -q 'gdbus .*OverviewActive <false>' "$CALLS"; then
  ok "agent resets keys, disables the extension, closes the overview"
else nok "agent" "rc=$rc out=$out"; fi

echo true >"$GS/org.gnome.mutter.dynamic-workspaces"
out=$(run bash "$BINDIR/pc-mode" status 2>&1); rc=$?
[ "$out" = mixed ] && [ "$rc" = 1 ] && ok "one stray key = mixed, exit 1" || nok "mixed" "rc=$rc out=$out"
rm -f "$GS"/*

# Matrix: 5 keys all-agent / all-human / one flipped, x extension state (GNOME Shell's enable rule).
HUMAN='org.gnome.desktop.interface.enable-animations true
com.ubuntu.update-notifier.no-show-notifications false
com.ubuntu.update-notifier.regular-auto-launch-interval 7
org.gnome.mutter.dynamic-workspaces true
org.gnome.desktop.wm.preferences.num-workspaces 4'
# ext state: name mode-json enabled disabled user-off expected-on
EXTS="mode-default 1 - - false 1
mode-disabled 1 - E false 0
mode-user-off 1 - - true 1
user-on 0 E - false 1
user-off-global 0 E - true 0
user-listed-and-disabled 0 E E false 0
absent 0 - - false 0"
fail=0; cases=0
while read -r ename inmode en dis uoff on; do
  for keys in agent human 1 2 3 4 5; do
    rm -f "$GS"/*
    [ "$inmode" = 1 ] && echo "$MODEJSON" >"$WORK/modes/ubuntu.json" || echo '{ "enabledExtensions": [] }' >"$WORK/modes/ubuntu.json"
    [ "$en" = E ] && echo "['other@x', '$EXT']" >"$GS/org.gnome.shell.enabled-extensions"
    [ "$dis" = E ] && echo "['$EXT']" >"$GS/org.gnome.shell.disabled-extensions"
    echo "$uoff" >"$GS/org.gnome.shell.disable-user-extensions"
    n_h=$on; n_a=$((1 - on)); i=0
    while read -r k v; do
      i=$((i + 1))
      if [ "$keys" = human ] || [ "$keys" = "$i" ]; then echo "$v" >"$GS/$k"; n_h=$((n_h + 1)); else n_a=$((n_a + 1)); fi
    done <<<"$HUMAN"
    if [ "$n_a" = 6 ]; then want=agent; elif [ "$n_h" = 6 ]; then want=human; else want=mixed; fi
    out=$(run bash "$BINDIR/pc-mode" status 2>/dev/null)
    cases=$((cases + 1))
    [ "$out" = "$want" ] || { fail=$((fail + 1)); echo "  matrix $ename keys=$keys: got $out want $want"; }
  done
done <<<"$EXTS"
rm -f "$GS"/*; echo "$MODEJSON" >"$WORK/modes/ubuntu.json"; off
[ "$fail" = 0 ] && ok "status matrix: $cases cases match the shell's extension rule" || nok "status matrix" "$fail of $cases wrong"

: >"$CALLS"
out=$(run bash "$BINDIR/pc-mode" bogus 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == usage:* ]] && ! grep -q 'gsettings set\|gsettings reset' "$CALLS" \
  && ok "bad argument: usage, exit 2, nothing written" || nok "bad argument" "rc=$rc out=$out"

out=$(GS_IGNORE_KEY=num-workspaces run bash "$BINDIR/pc-mode" human 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"num-workspaces = 1 (expected 4)"* ]] \
  && ok "read-back mismatch reported, exit 1" || nok "read-back" "rc=$rc out=$out"

[ -s "$BLOCKED" ] && nok "no blocked calls" "$(head -1 "$BLOCKED")" || ok "no blocked call during the run"
[ "$bad" = 0 ] && echo "PASS pc-mode" || { echo "FAIL pc-mode"; exit 1; }
