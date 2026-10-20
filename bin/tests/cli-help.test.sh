#!/usr/bin/env bash
# T997: every fleet CLI (bin/ and skill scripts on PATH) answers -h/--help with a usage line, rc 0 and no stub call;
# an unknown flag exits 2. Runs in bwrap: read-only /, no network, private /tmp, /run and pids; copies under a fake HOME.
# Run: bash cli-help.test.sh [cli...]   (CLI_HELP_VERBOSE=1 prints every PASS)
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${CLI_HELP_SANDBOXED:-}" ]; then
  exec bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /run --unshare-net --unshare-pid \
    --die-with-parent --setenv CLI_HELP_SANDBOXED 1 --setenv TMPDIR /tmp -- bash "$SELF" "$@"
fi
. "$BIN/tests/lib/budget.sh"
REAL_HOME=$HOME; t0=$(date +%s.%N); TO=$(budget 3)   # per call: a --help or a refused flag returns at once

# Pass-through wrappers: they hand every argument to another program, so an unknown flag is that program's to judge.
PASSTHRU=" pc "   # pc <sub> [args]: runs pc-<sub> with the rest
# Known red at T997, outside its file set: <cli> <help|bogus...>. Each is a FOLLOWUPS line; drop the row once fixed.
declare -A KNOWN=()
while read -r c k; do KNOWN[$c]=$k; done <<'EOF'
agent-disable help
agent-enable help
agent-exec help
agent-now help
agent-run help
agents-start help bogus
agents-stop help bogus
baseline.sh help
boot-check.sh help bogus
code-review-sandbox help bogus
compose-services help bogus
fleetlib.sh help bogus
harness help
lockcheck.sh help bogus
moodle-login-check help bogus
mv-lut bogus
notify-owner help
orbit-hook help bogus
orchestrator-pulse help bogus
pc-a11y-click bogus
pc-click-text bogus
pc-clip help
pc_dbus.py help bogus
pc-find bogus
pc-move bogus
pc-notify bogus
pc-open bogus
pc-selftest bogus
pc-wait bogus
plan-usage bogus
playwright-mcp help bogus
power-profile-auto help bogus
pulse-5h-reset help bogus
push-ready help bogus
sentinel-waits bogus
sites help
spotify_api.py help
EOF

WORK=$(mktemp -d) || exit 1; trap 'rm -rf "$WORK"' EXIT
FH="$WORK/home"; STUBS="$WORK/stubs"; CALLS="$WORK/calls"
mkdir -p "$FH" "$STUBS" "$WORK/tmp" "$WORK/run"

# --- the CLI set: executables in bin/, plus links on PATH into a skill's scripts/ -----------------
declare -A CLI=()
for f in "$BIN"/*; do
  r=$(readlink -f "$f"); [ -f "$r" ] && [ -x "$r" ] && CLI[${f##*/}]=$r
done
for f in "$REAL_HOME/.local/bin"/*; do
  r=$(readlink -f "$f"); case "$r" in */skills/*/scripts/*) [ -x "$r" ] && CLI[${f##*/}]=$r ;; esac
done
# Each CLI runs from a copy of its own directory at the same place under the fake HOME.
declare -A COPIED=()
for c in "${!CLI[@]}"; do
  d=$(dirname "${CLI[$c]}"); [ -n "${COPIED[$d]:-}" ] && continue; COPIED[$d]=1
  case "$d" in "$REAL_HOME"/*) ;; *) echo "FAIL $c lives outside HOME: $d"; exit 1 ;; esac
  mkdir -p "$FH/${d#"$REAL_HOME"/}"
  for e in "$d"/*; do [ "${e##*/}" = tests ] || cp -rL "$e" "$FH/${d#"$REAL_HOME"/}/" 2>/dev/null; done
done
[ -d "$REAL_HOME/agents/lib" ] && cp -rL "$REAL_HOME/agents/lib" "$FH/agents/"
# Everything else a CLI reaches under ~/agents or ~/.claude/skills is linked, read-only here; secrets stay out.
for d in agents .claude/skills; do
  mkdir -p "$FH/$d"
  for e in "$REAL_HOME/$d"/*; do
    [ "${e##*/}" = secrets ] || [ -e "$FH/$d/${e##*/}" ] || ln -s "$e" "$FH/$d/${e##*/}"
  done
done

cat >"$STUBS/stub" <<'EOF'
#!/bin/sh
echo "${0##*/} $*" >>"$CLI_CALLS"
exit 0
EOF
chmod +x "$STUBS/stub"
STUBBED="systemctl docker notify-owner sudo curl git pactl wget ssh rsync tmux systemd-run loginctl journalctl pc
  claude gh npm npx ffmpeg blender godot notify-send paplay wpctl playerctl xdg-open nmcli bluetoothctl powerprofilesctl
  shutdown reboot apt-get pkill"
for s in $STUBBED; do ln -s stub "$STUBS/$s"; done
NODE_DIR=$(dirname "$(command -v node 2>/dev/null || echo /usr/bin/node)")

run() {
  env -i HOME="$FH" PATH="$STUBS:/usr/bin:/bin:$NODE_DIR" LC_ALL=C CLI_CALLS="${CLI_CALLS:-$CALLS}" TMPDIR="$WORK/tmp" \
    XDG_RUNTIME_DIR="$WORK/run" timeout -k 1 "$TO" "$@" </dev/null
}

# --- selftest: the sandbox makes the real action impossible --------------------------------------
st=0
for s in $STUBBED; do
  [ "$(run sh -c "command -v $s")" = "$STUBS/$s" ] || { echo "SELFTEST FAIL $s is not the stub"; st=1; }
done
[ "$(run sh -c 'echo $HOME')" = "$FH" ] || { echo "SELFTEST FAIL HOME is not the fake home"; st=1; }
touch "$REAL_HOME/.cli-help-probe" 2>/dev/null && { rm -f "$REAL_HOME/.cli-help-probe"; echo "SELFTEST FAIL real HOME is writable"; st=1; }
run python3 -c 'import socket; socket.create_connection(("1.1.1.1", 53), 2)' 2>/dev/null && { echo "SELFTEST FAIL network reachable"; st=1; }
[ -e "/run/user/$(id -u)/bus" ] && { echo "SELFTEST FAIL user bus reachable"; st=1; }
: >"$CALLS"; run sh -c 'notify-owner probe'; grep -q '^notify-owner probe' "$CALLS" || { echo "SELFTEST FAIL notify-owner stub"; st=1; }
[ "$st" = 0 ] || exit 1
echo "PASS selftest: read-only /, no network, no user bus, fake HOME, $(wc -w <<<"$STUBBED") commands stubbed"

# --- each CLI: -h, --help, --bogus-flag-xyz, 4 at a time ------------------------------------------
one() {  # one <cli> <path>: PASS/FAIL/KNOWN lines for its three calls
  local c=$1 p=$2 a out rc k red= known=${KNOWN[$1]:-} CALLS="$WORK/calls.$1"
  for a in -h --help --bogus-flag-xyz; do
    [ "$a" = --bogus-flag-xyz ] && [[ $PASSTHRU == *" $c "* ]] && { echo "PASS $c $a (pass-through)"; continue; }
    : >"$CALLS"; out=$(CLI_CALLS=$CALLS run "$p" "$a" 2>&1); rc=$?
    if [ "$a" = --bogus-flag-xyz ]; then k=bogus; [ "$rc" = 2 ] && { echo "PASS $c $a"; continue; }
    else k=help; [ "$rc" = 0 ] && grep -qi usage <<<"$out" && [ ! -s "$CALLS" ] && { echo "PASS $c $a"; continue; }; fi
    [[ " $known " == *" $k "* ]] && echo "KNOWN $c $a" && red="$red $k" && continue
    echo "FAIL $c $a: want $([ $k = help ] && echo 'rc 0, usage, no call' || echo 'rc 2') (rc=$rc usage=$(grep -ci usage <<<"$out") calls=$(tr '\n' ';' <"$CALLS"))"
  done
  for k in $known; do [[ "$red " == *" $k "* ]] || echo "FAIL $c: stale KNOWN row '$k' now passes, drop it"; done
}
mkdir -p "$WORK/res"; want=" $* "; n=0
for c in $(printf '%s\n' "${!CLI[@]}" | sort); do
  [ $# -gt 0 ] && [[ $want != *" $c "* ]] && continue
  n=$((n+1)); while [ "$(jobs -rp | wc -l)" -ge 4 ]; do wait -n; done
  one "$c" "$FH/${CLI[$c]#"$REAL_HOME"/}" >"$WORK/res/$c" &
done
wait
for c in "${!KNOWN[@]}"; do [ -n "${CLI[$c]:-}" ] || echo "FAIL KNOWN names $c, which is not a CLI here" >>"$WORK/res/~known"; done
cat "$WORK/res"/* | { [ -n "${CLI_HELP_VERBOSE:-}" ] && cat || grep -v '^PASS'; }
bad=$(cat "$WORK/res"/* | grep -c '^FAIL'); known=$(cat "$WORK/res"/* | grep -c '^KNOWN')
fail() { echo "FAIL $1"; bad=$((bad+1)); }

lim=$(budget 30); dt=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
awk -v d="$dt" -v l="$lim" 'BEGIN{exit !(d <= l)}' || fail "runtime ${dt}s > ${lim}s"
echo "$n CLIs, $bad failures, $known known, ${dt}s (budget ${lim}s)"
[ "$bad" = 0 ]
