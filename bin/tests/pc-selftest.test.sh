#!/usr/bin/env bash
# T472: `pc selftest` against a fake `pc` beside a copy of it, plus pc-clip/pc-open/pc-notify on stub
# wl-copy/wl-paste/xdg-open/gtk-launch/notify-send; no window, clipboard or notification is touched (selftest proves it).
set -uo pipefail
BIN=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub" FB="$WORK/bin" LOG="$WORK/calls.log"
mkdir -p "$STUB" "$FB"; : >"$LOG"
. "$HOME/agents/bin/tests/lib/assert.sh"
has() { grep -qF -- "$2" <<<"$3" && ok "$1" || nok "$1" "no '$2' in: $3"; }
st()  { PATH="$STUB:$PATH" HARNESS_CONFIG=/dev/null PCS_LOG="$LOG" PCS_WORK="$WORK" "$@"; }
# logged PATTERN — wait up to 2 s for a line in the call log (pc open backgrounds its launcher).
logged() { local _; for _ in $(seq 20); do grep -qF -- "$1" "$LOG" && return 0; sleep 0.1; done; return 1; }

# Stubs: every external the scripts reach records its call; PCS_FAIL=<name> makes that one fail.
for c in killall sleep wl-copy wl-paste xdg-open gtk-launch notify-send fakeapp; do
  cat >"$STUB/$c" <<'EOF'
#!/bin/bash
n=${0##*/}; echo "$n $*" >>"$PCS_LOG"
[ "${PCS_FAIL:-}" = "$n" ] && exit 1
case $n in
  wl-copy) cat >"$PCS_WORK/clip";;
  wl-paste) cat "$PCS_WORK/clip" 2>/dev/null;;
esac
exit 0
EOF
done
# The fake pc answers the calculator run: 7+8 copies 15 unless PCS_SUM overrides it.
cat >"$FB/pc" <<'EOF'
#!/bin/bash
echo "pc $*" >>"$PCS_LOG"
case "$1 ${2:-}" in
  "wait-for "*) echo 0.2s;;
  "see ") echo 'ui: button "7" button "8" button "+"';;
  "tree gnome-calculator") [ "$4" = 7 ] && echo '100 200' || echo '140 200';;
  "clip get") echo "${PCS_SUM:-15}";;
  "shot "*) python3 -c 'import sys;from PIL import Image;Image.new("RGB",(640,400)).save(sys.argv[1])' "$PCS_WORK/shot.png"
            echo "$PCS_WORK/shot.png 640x400";;
  "win list") echo '0x1 Text Editor 800x600+100+100';;
  "find 7") echo '100 200';;
esac
exit 0
EOF
cp "$BIN/pc-selftest" "$FB/pc-selftest"
chmod +x "$STUB"/* "$FB"/*

# 0. selftest: the stubs win on PATH and the selftest copy calls the fake pc beside it.
for c in killall sleep wl-copy wl-paste xdg-open gtk-launch notify-send; do
  is "selftest: $c resolves to the stub" "$(st bash -c "command -v $c")" "$STUB/$c"
done
is 'selftest: the copy resolves pc to the fake' "$(sed -n 's/^d=.*pc="\$d\/pc"$/ok/p' "$FB/pc-selftest")" ok

# 1. pc selftest: --help, a full pass, two failure paths.
is 'selftest -h prints usage' "$(st "$FB/pc-selftest" -h)" 'usage: pc selftest'
: >"$LOG"; out=$(st "$FB/pc-selftest"); rc=$?
is 'selftest happy path exits 0' "$rc" 0
is 'selftest happy path ends with PASS' "$(tail -1 <<<"$out")" PASS
is 'selftest happy path has no FAIL line' "$(grep -c '^FAIL ' <<<"$out")" 0
is 'selftest runs 11 checks' "$(grep -c '^OK ' <<<"$out")" 11
has 'selftest drove the calculator through the fake pc' 'pc a11y-click =' "$(cat "$LOG")"
has 'selftest killed the calculator only through the stub' 'killall gnome-calculator' "$(cat "$LOG")"
: >"$LOG"; out=$(PCS_SUM=14 st "$FB/pc-selftest"); rc=$?
is 'a wrong sum exits 1' "$rc" 1
is 'a wrong sum ends with FAIL' "$(tail -1 <<<"$out")" FAIL
has 'a wrong sum names the click check' "click by coordinates: got '14', want 15" "$out"

# 2. pc clip.
st "$BIN/pc-clip" set 'hello world'; is 'clip set exits 0' "$?" 0
is 'clip set reached wl-copy' "$(cat "$WORK/clip")" 'hello world'
is 'clip get reads it back' "$(st "$BIN/pc-clip" get)" 'hello world'
has 'clip get asks wl-paste for no newline' 'wl-paste --no-newline' "$(cat "$LOG")"
is 'clip -h exits 0' "$(st "$BIN/pc-clip" -h >/dev/null; echo $?)" 0
is 'clip with a bad verb exits 2' "$(st "$BIN/pc-clip" bogus >/dev/null; echo $?)" 2
is 'clip get with a failing wl-paste exits 1' "$(PCS_FAIL=wl-paste st "$BIN/pc-clip" get; echo $?)" 1

# 3. pc open: URLs/paths go to xdg-open, names to gtk-launch, a failing gtk-launch falls back to the binary.
is 'open --help prints usage' "$(st "$BIN/pc-open" --help)" 'usage: pc open <url|file|app>'
: >"$LOG"; st "$BIN/pc-open" https://example.invalid/x; is 'open url exits 0' "$?" 0
logged 'xdg-open https://example.invalid/x' && ok 'open url goes to xdg-open' || nok 'open url goes to xdg-open' "$(cat "$LOG")"
: >"$LOG"; st "$BIN/pc-open" org.gnome.Calculator.desktop
logged 'gtk-launch org.gnome.Calculator' && ok 'open app.desktop goes to gtk-launch without .desktop' || nok 'open app.desktop goes to gtk-launch' "$(cat "$LOG")"
: >"$LOG"; PCS_FAIL=gtk-launch st "$BIN/pc-open" fakeapp
logged 'fakeapp ' && ok 'a failing gtk-launch falls back to the binary' || nok 'a failing gtk-launch falls back to the binary' "$(cat "$LOG")"

# 4. pc notify.
is 'notify with no args prints usage' "$(st "$BIN/pc-notify")" 'usage: pc notify "msg" [title]'
: >"$LOG"; st "$BIN/pc-notify" 'hi there'
is 'notify defaults the title to Claude' "$(cat "$LOG")" 'notify-send Claude hi there'
: >"$LOG"; st "$BIN/pc-notify" body Title; is 'notify passes the title first' "$(cat "$LOG")" 'notify-send Title body'
is 'a failing notify-send exits 1' "$(PCS_FAIL=notify-send st "$BIN/pc-notify" x; echo $?)" 1

[ $bad -eq 0 ] && echo PASS || echo FAIL
exit $bad
