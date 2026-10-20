#!/usr/bin/env bash
# pc win list/focused/focus/verify/move/resize/close on a private dbus-run-session bus with a fake Window Calls
# service (fixtures/win). pc-win runs as a copy beside a stub pc-click, with a stub xrandr: no real window is touched.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/win"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

if ! command -v dbus-run-session >/dev/null || ! command -v gdbus >/dev/null \
   || ! python3 -c 'from gi.repository import Gio' 2>/dev/null; then
  ok 'skipped (no dbus-run-session, gdbus or python3 gi)'; exit 0
fi
mkdir -p "$WORK/bin" "$WORK/run"; chmod 700 "$WORK/run"
cp "$BIN/pc-win" "$WORK/bin/pc-win"
cp "$FIX/windows.json" "$WORK/windows.json"
printf '#!/bin/sh\necho "$@" >>"%s/clicks.log"\n' "$WORK" >"$WORK/bin/pc-click"
printf '#!/bin/sh\necho "Screen 0: minimum 16 x 16, current 1920 x 900, maximum 32767 x 32767"\n' >"$WORK/bin/xrandr"
chmod +x "$WORK/bin/"*

export -f ok nok is; export WORK FIX
export PC_REAL_BUS="unix:path=${XDG_RUNTIME_DIR:-/run/user/$UID}/bus"
XDG_RUNTIME_DIR="$WORK/run" dbus-run-session -- bash -c '
  bad=0
  export PATH="$WORK/bin:$PATH"
  { [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && [ "$DBUS_SESSION_BUS_ADDRESS" != "$PC_REAL_BUS" ] \
    && ! gdbus wait --session --timeout 1 org.gnome.Shell 2>/dev/null; } \
    || { nok "selftest: the bus is private (no org.gnome.Shell)" "$DBUS_SESSION_BUS_ADDRESS, refusing"; exit 1; }
  ok "selftest: the bus is private (no org.gnome.Shell)"
  is "selftest: pc-win copy resolves pc-click to the stub" "$(dirname "$(realpath "$WORK/bin/pc-win")")" "$WORK/bin"
  python3 "$FIX/fake-window-calls.py" "$WORK/windows.json" "$WORK/calls.log" & fake=$!; trap "kill $fake" EXIT
  gdbus wait --session --timeout 5 org.gnome.Shell || { nok "fake Window Calls up" timeout; exit 1; }
  W="$WORK/bin/pc-win"; F="$WORK/run/pc-focus-window"

  # list
  out=$("$W" list)
  is "list: header + 3 titled windows" "$(wc -l <<<"$out")" 4
  grep -qE "^202 +org.gnome.Ptyxis +0 +980x900\+1000\+50 +\* Terminal$" <<<"$out" \
    && ok "list: geometry and focus star" || nok "list: geometry and focus star" "$out"
  grep -q "^303 " <<<"$out" && nok "list: untitled popup hidden" "$out" || ok "list: untitled popup hidden"
  is "list --all shows the popup" "$("$W" list --all | grep -c "^303 ")" 1
  is "list --json merges Details" "$("$W" list --json | jq -c "[length, (.[] | select(.id==101) | [.x,.y,.width,.height])]")" "[3,[300,200,800,600]]"
  is "focused prints the focused id" "$("$W" focused)" 202

  # focus, verify
  "$W" focus files --no-click; is "focus --no-click exits 0" "$?" 0
  is "focus records the window" "$(cat "$F")" 101
  is "focus Activated the resolved id" "$(grep -c "^Activate 101$" "$WORK/calls.log")" 1
  [ -e "$WORK/clicks.log" ] && nok "--no-click does not click" "$(cat "$WORK/clicks.log")" || ok "--no-click does not click"
  "$W" verify; is "verify: recorded window still focused" "$?" 0
  "$W" focus 202; is "focus by id exits 0" "$?" 0
  is "focus clicks inside the bottom edge, clamped to the screen" "$(cat "$WORK/clicks.log")" "1490 899"
  "$W" focus files && "$W" focus 202
  is "focus clicks 8 px above the bottom edge, centred" "$(sed -n 2p "$WORK/clicks.log")" "700 792"
  gdbus call --session -d org.gnome.Shell -o /org/gnome/Shell/Extensions/Windows \
    -m org.gnome.Shell.Extensions.Windows.Activate 101 >/dev/null
  err=$("$W" verify 2>&1); is "verify: exits 1 when focus moved" "$?" 1
  is "verify: names both windows" "$err" "window 202 was focused by '\''pc win focus'\'' but 101 has focus now"
  err=$("$W" focus stuck --no-click 2>&1); is "focus: window that ignores Activate exits 1" "$?" 1
  is "focus: says it did not take focus" "$err" "pc win: '\''stuck'\'' did not take focus"

  # mutations go to the fake with the resolved id
  "$W" move ptyxis 10 20 && "$W" resize Terminal 640 480 && "$W" close nautilus && "$W" minimize 202 && "$W" maximize 101
  is "move/resize/close/minimize/maximize reach the fake" "$(grep -E "^(Move|Resize|Close|Minimize|Maximize) " "$WORK/calls.log" | tr "\n" ";")" \
    "Move 202 10 20;Resize 202 640 480;Close 101;Minimize 202;Maximize 101;"
  err=$("$W" close nosuch 2>&1); is "no match exits 1" "$?" 1
  is "no match names the selector" "$err" "pc win: no window matching '\''nosuch'\''"
  "$W" >/dev/null 2>&1; is "no args exits 2" "$?" 2
  "$W" move 202 1 >/dev/null 2>&1; is "move with too few args exits 2" "$?" 2
  "$W" -h | grep -q "^usage: pc win" && ok "-h prints usage" || nok "-h prints usage" "no usage line"
  usage=$("$W" bogus 2>&1)
  for o in -h --help help; do is "$o: text equals the usage byte for byte" "$("$W" $o)" "$usage"; done
  is "-h: json/subprocess/argparse never imported" "$(python3 -X importtime "$W" -h 2>&1 >/dev/null | grep -cE "\| +(json|subprocess|argparse)$")" 0

  # usage paths never import gi (T567: pc doctor times -h)
  mkdir -p "$WORK/nogi/gi"; echo "raise ImportError(\"gi imported\")" >"$WORK/nogi/gi/__init__.py"
  is "selftest: the shim hides gi" "$(PYTHONPATH="$WORK/nogi" python3 -c "import gi" 2>&1 | tail -1)" "ImportError: gi imported"
  PYTHONPATH="$WORK/nogi" "$W" -h | grep -q "^usage: pc win" && ok "-h works without gi" || nok "-h works without gi" "no usage line"
  PYTHONPATH="$WORK/nogi" "$W" --help >/dev/null 2>&1; is "--help without gi exits 0" "$?" 0
  PYTHONPATH="$WORK/nogi" "$W" >/dev/null 2>&1; is "no args without gi exits 2" "$?" 2
  PYTHONPATH="$WORK/nogi" "$W" move 202 1 >/dev/null 2>&1; is "arg error without gi exits 2" "$?" 2
  PYTHONPATH="$WORK/nogi" "$W" bogus >/dev/null 2>&1; is "unknown command without gi exits 2" "$?" 2
  exit $bad' || bad=1
[ $bad = 0 ] && echo 'PASS pc-win' || echo 'FAIL pc-win'
exit $bad
