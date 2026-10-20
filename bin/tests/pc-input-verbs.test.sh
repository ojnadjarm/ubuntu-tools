#!/usr/bin/env bash
# T522: pc-shot pc-key pc-find pc-click-text pc-scroll pc-a11y-click pc-drag pc-type, each run as a byte-identical copy beside
# recording backends (fixtures/input-verbs) inside bwrap with no ydotool socket, session bus, wayland socket or /dev/uinput:
# -h exits 0, argument errors exit 2, the exact backend calls land in the shim log, the only output any verb can reach.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/input-verbs"
VERBS="pc-shot pc-key pc-find pc-click-text pc-scroll pc-a11y-click pc-drag pc-type"

if [ -z "${INPUT_VERBS_SANDBOX:-}" ]; then
  . "$BIN/tests/lib/assert.sh"
  command -v bwrap >/dev/null || { ok 'skipped (no bwrap: never run unsandboxed)'; exit 0; }
  WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/bin" "$WORK/shims" "$WORK/run"; chmod 700 "$WORK/run"
  for v in $VERBS pc-click env.sh; do cp "$BIN/$v" "$WORK/bin/"; done
  for b in portal_shot ocr_find a11y_tree rd_type; do cp "$FIX/fake_backend.py" "$WORK/bin/$b.py"; done
  cp "$FIX/shim" "$WORK/bin/pc-win"
  for s in ydotool gdbus xrandr; do cp "$FIX/shim" "$WORK/shims/$s"; done
  bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /run/user --bind "$WORK" "$WORK" \
        --unshare-net --unshare-ipc --die-with-parent \
        --setenv INPUT_VERBS_SANDBOX 1 --setenv WORK "$WORK" "$BASH" "$0"
  exit $?
fi

. "$BIN/tests/lib/assert.sh"
export PATH="$WORK/shims:$PATH" XDG_RUNTIME_DIR="$WORK/run" SHIM_LOG="$WORK/shim.log" FAKE_FIXTURES="$FIX"
: >"$SHIM_LOG"
W="$WORK/bin"
# calls <cmd...> — run the verb with a fresh log, then print the log with mktemp paths as <tmp>.
calls() { : >"$SHIM_LOG"; "$@" >"$WORK/out" 2>"$WORK/err"; echo $? >"$WORK/rc"; cat "$SHIM_LOG" >>"$WORK/all.log"
  sed -E 's#/tmp/tmp\.[A-Za-z0-9]+#<tmp>#g' "$SHIM_LOG"; }
rc() { cat "$WORK/rc"; }
nolog() { cat "$SHIM_LOG" >>"$WORK/all.log"; [ -s "$SHIM_LOG" ] && nok "$1" "backend called: $(cat "$SHIM_LOG")" || ok "$1"; }
# argerr <name> <cmd...> — exits 2 and sends no input; read-only lookups (xrandr, pc-win verify, the modal check) may run.
argerr() {
  local name="$1"; shift; : >"$SHIM_LOG"; timeout 5 "$@" >/dev/null 2>&1; is "$name exits 2" "$?" 2
  cat "$SHIM_LOG" >>"$WORK/all.log"
  is "$name sends no input" "$(grep -cvE '^(xrandr|pc-win verify|a11y_tree\.py \["--modal-check"\])' "$SHIM_LOG")" 0
}

# selftest: the sandbox makes real input impossible and every backend resolves to a recorder.
for s in /tmp/.ydotool_socket "/run/user/$UID/bus" "/run/user/$UID/wayland-0" /dev/uinput; do
  [ -e "$s" ] && { nok "selftest: $s is hidden" present; exit 1; }
done
ok 'selftest: no ydotool socket, session bus, wayland socket or /dev/uinput'
for s in ydotool gdbus xrandr; do is "selftest: $s resolves to the shim" "$(command -v "$s")" "$WORK/shims/$s"; done
is 'selftest: env.sh copy points PC_BIN at the sandbox bin' "$(. "$W/env.sh"; realpath "$PC_BIN")" "$W"
for b in portal_shot ocr_find a11y_tree rd_type; do
  cmp -s "$W/$b.py" "$FIX/fake_backend.py" && ok "selftest: $b.py is the recorder" || nok "selftest: $b.py is the recorder" differs
done
for v in $VERBS pc-click env.sh; do
  cmp -s "$W/$v" "$BIN/$v" && ok "selftest: $v copy is byte-identical" || nok "selftest: $v copy is byte-identical" differs
done
[ $bad = 0 ] || { echo 'FAIL pc-input-verbs (selftest)'; exit 1; }

# -h exits 0 for every verb and calls nothing.
for v in $VERBS; do : >"$SHIM_LOG"; "$W/$v" -h >/dev/null 2>&1; is "$v -h exits 0" "$?" 0; nolog "$v -h calls no backend"; done

# pc-shot
argerr 'pc-shot --scale without a value' "$W/pc-shot" "$WORK/s.png" --scale
argerr 'pc-shot an unknown option'       "$W/pc-shot" "$WORK/s.png" --bogus
is 'pc-shot: one portal call into a temp png' "$(calls "$W/pc-shot" "$WORK/a.png")" 'portal_shot.py ["<tmp>.png"]'
is 'pc-shot: prints path and size' "$(cut -d' ' -f1,2 "$WORK/out")" "$WORK/a.png 200x100"
is 'pc-shot --region --scale: one portal call' "$(calls "$W/pc-shot" "$WORK/b.png" --region 10,10,50,40 --scale 0.5)" \
  'portal_shot.py ["<tmp>.png"]'
is 'pc-shot --region --scale: crop then scale' "$(cut -d' ' -f2 "$WORK/out")" 25x20
calls "$W/pc-shot" "$WORK/c.png" >/dev/null; calls "$W/pc-shot" "$WORK/c.png" --diff --ignore 0,0,1,1 >/dev/null
is 'pc-shot --diff: same frame is unchanged' "$(tail -1 "$WORK/out")" unchanged
FAKE_SHOT_COLOR=black calls "$W/pc-shot" "$WORK/c.png" --diff --ignore 0,0,1,1 >/dev/null
is 'pc-shot --diff: new frame reports the bbox' "$(tail -1 "$WORK/out")" 'changed bbox=0,0,200,100'

# pc-key
argerr 'pc-key with no key' "$W/pc-key"
argerr 'pc-key without focus' env FAKE_FOCUS_RC=1 "$W/pc-key" Return
is 'pc-key --force Return' "$(calls "$W/pc-key" --force Return)" 'ydotool key --key-delay 30 28:1 28:0'
is 'pc-key ctrl+l: press in order, release reversed, guard first' "$(calls "$W/pc-key" ctrl+l)" \
  "$(printf '%s\n' 'pc-win verify' 'a11y_tree.py ["--modal-check"]' 'ydotool key --key-delay 30 29:1 38:1 38:0 29:0')"
is 'pc-key modal up exits 2 before any key' "$(FAKE_A11Y_TREE=$FIX/a11y-tree-modal.json calls "$W/pc-key" Return; rc)" \
  "$(printf '%s\n' 'pc-win verify' 'a11y_tree.py ["--modal-check"]' 2)"
calls "$W/pc-key" --force nosuchkey >/dev/null; is 'pc-key unknown key exits 1' "$(rc)" 1; nolog 'pc-key unknown key sends nothing'

# pc-find
argerr 'pc-find with no text' "$W/pc-find" --all
argerr 'pc-find --region without a value' "$W/pc-find" Save --region
is 'pc-find Save: shot then OCR, first hit' "$(calls "$W/pc-find" Save)" \
  "$(printf '%s\n' 'portal_shot.py ["<tmp>.png"]' 'ocr_find.py ["<tmp>.png", "Save", "0", "0", ""]')"
is 'pc-find prints the centre' "$(cat "$WORK/out")" '120 40'
is 'pc-find --all --json --region' "$(calls "$W/pc-find" Save --all --json --region 0,0,800,500)" \
  "$(printf '%s\n' 'portal_shot.py ["<tmp>.png"]' 'ocr_find.py ["<tmp>.png", "Save", "1", "1", "0,0,800,500"]')"
is 'pc-find --shot skips the portal' "$(calls "$W/pc-find" OK --shot "$WORK/a.png")" \
  'ocr_find.py ["<tmp>/a.png", "OK", "0", "0", ""]'

# pc-click-text
argerr 'pc-click-text with no text' "$W/pc-click-text" --index 1
argerr 'pc-click-text --index without a value' "$W/pc-click-text" Save --index
is 'pc-click-text Save: OCR then move and left click' "$(calls "$W/pc-click-text" Save | grep -v '^portal\|^ocr\|^xrandr')" \
  "$(printf '%s\n' 'ydotool mousemove --absolute -x 120 -y 40' 'ydotool click 0xC0')"
is 'pc-click-text reports the point' "$(cat "$WORK/out")" "clicked 'Save' at 120 40"
is 'pc-click-text --index 1 right --double' \
  "$(calls "$W/pc-click-text" Save --index 1 right --double | grep -v '^portal\|^ocr\|^xrandr')" \
  "$(printf '%s\n' 'ydotool mousemove --absolute -x 600 -y 410' 'ydotool click --repeat 2 --next-delay 40 0xC1')"
is 'pc-click-text not found exits 1, no click' "$(calls "$W/pc-click-text" Nope | grep -c '^ydotool'; rc)" "$(printf '0\n1')"

# pc-scroll
argerr 'pc-scroll with no direction' "$W/pc-scroll" 5
argerr 'pc-scroll --at outside the screen' "$W/pc-scroll" down --at 2000 100
is 'pc-scroll down 5' "$(calls "$W/pc-scroll" down 5)" 'ydotool mousemove -w -x 0 -y -5'
is 'pc-scroll up --at: move, then 3 up' "$(calls "$W/pc-scroll" up --at 100 200 | grep -v '^xrandr')" \
  "$(printf '%s\n' 'ydotool mousemove --absolute -x 100 -y 200' 'ydotool mousemove -w -x 0 -y 3')"

# pc-a11y-click
argerr 'pc-a11y-click with no name' "$W/pc-a11y-click" --app firefox
argerr 'pc-a11y-click --role without a value' "$W/pc-a11y-click" OK --role
is 'pc-a11y-click OK: tree lookup then click' "$(calls "$W/pc-a11y-click" OK | grep -v '^xrandr')" \
  "$(printf '%s\n' 'a11y_tree.py ["", "--click", "--find", "OK"]' 'ydotool mousemove --absolute -x 500 -y 300' 'ydotool click 0xC0')"
is 'pc-a11y-click --role --app: the action path sends no input' \
  "$(calls "$W/pc-a11y-click" Close --role 'push button' --app firefox; rc)" \
  "$(printf '%s\n' 'a11y_tree.py ["firefox", "--click", "--find", "Close", "--role", "push button"]' 0)"
is 'pc-a11y-click missing element exits 1' "$(calls "$W/pc-a11y-click" Nope | grep -c '^ydotool'; rc)" "$(printf '0\n1')"

# pc-drag
argerr 'pc-drag with three numbers' "$W/pc-drag" 10 20 300
argerr 'pc-drag non-integer point' "$W/pc-drag" 10 20 x 400
argerr 'pc-drag the hot corner' "$W/pc-drag" 0 0 300 400
is 'pc-drag 10 20 300 400: press, move, release' "$(calls "$W/pc-drag" 10 20 300 400 | grep -v '^xrandr')" \
  "$(printf '%s\n' 'ydotool mousemove --absolute -x 10 -y 20' 'ydotool click 0x40' \
                   'ydotool mousemove --absolute -x 300 -y 400' 'ydotool click 0x80')"
is 'pc-drag 1365 767 1 1' "$(calls "$W/pc-drag" 1365 767 1 1 | grep -v '^xrandr')" \
  "$(printf '%s\n' 'ydotool mousemove --absolute -x 1365 -y 767' 'ydotool click 0x40' \
                   'ydotool mousemove --absolute -x 1 -y 1' 'ydotool click 0x80')"

# pc-type
argerr 'pc-type with no text' "$W/pc-type" --force
argerr 'pc-type without focus' env FAKE_FOCUS_RC=1 "$W/pc-type" hi
is 'pc-type --force: escapes expanded' "$(calls "$W/pc-type" --force 'hi\tthere\n')" 'rd_type.py ["hi\tthere\n"]'
is 'pc-type: guard, then words joined' "$(calls "$W/pc-type" two words)" \
  "$(printf '%s\n' 'pc-win verify' 'a11y_tree.py ["--modal-check"]' 'rd_type.py ["two words"]')"

# Every recorded call came from a shim; nothing else was reachable.
is 'no gdbus call from any verb' "$(grep -c '^gdbus' "$WORK/all.log")" 0
is 'every recorded call is a shim or recorder' \
  "$(grep -vcE '^(ydotool|gdbus|xrandr|pc-win|portal_shot\.py|ocr_find\.py|a11y_tree\.py|rd_type\.py) ' "$WORK/all.log")" 0

[ $bad = 0 ] && echo 'PASS pc-input-verbs' || echo 'FAIL pc-input-verbs'
exit $bad
