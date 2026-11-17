#!/usr/bin/env bash
# T1754 R32: every fleet script answers --help without acting. Static first: a script whose text has no help branch
# (argparse, pc_usage, a -h/--help test or case arm, a sourced-library guard, an `exec … "$@"` hand-off) is never run. The rest run once
# with --help in bwrap (read-only /, no network, private /tmp, /run and pids, state-changing commands stubbed),
# after a selftest proves a write there fails. Pass: rc 0, some output, no stub call, no read-only write error.
# Hooks (JSON on stdin from Claude) are not CLIs and are left out.
set -uo pipefail
SELF=$(readlink -f "$0"); A=$(cd "$(dirname "$SELF")/../.." && pwd)
if [ -z "${HELP_SAFE_SANDBOXED:-}" ]; then
  exec bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /run --unshare-net --unshare-pid \
    --die-with-parent --setenv HELP_SAFE_SANDBOXED 1 --setenv TMPDIR /tmp -- bash "$SELF" "$@"
fi
. "$A/bin/tests/lib/assert.sh"

# Not safe today; each row: <path under ~/agents> <reason>. Drop a row once its script passes.
declare -A EXCEPT=()
while read -r p why; do [ -n "$p" ] && EXCEPT[$p]=$why; done <<'EOF'
EOF

EXTRA="install.sh discord-bot/install adapters/claude/install adapters/claude/uninstall adapters/claude/run
  adapters/claude/merge-settings.py adapters/claude/memory-carrier adapters/codex/install adapters/opencode/install
  adapters/opencode/uninstall adapters/opencode/run adapters/generic/run"
W=$(mktemp -d); STUBS="$W/stubs"; mkdir -p "$STUBS" "$W/res"
printf '#!/bin/sh\necho "${0##*/} $*" >>"$HELP_SAFE_CALLS"\nexit 0\n' >"$STUBS/stub"; chmod +x "$STUBS/stub"
STUBBED="systemctl docker notify-owner sudo curl git pactl wget ssh rsync tmux systemd-run loginctl journalctl pc claude gh
  npm npx ffmpeg blender godot notify-send paplay wpctl playerctl xdg-open nmcli bluetoothctl powerprofilesctl shutdown reboot
  apt-get pkill killall kill agent-run agent-exec po-push chat eye opencode codex"
for s in $STUBBED; do ln -s stub "$STUBS/$s"; done
run() { env HELP_SAFE_CALLS="$1" PATH="$STUBS:$PATH" LC_ALL=C timeout -k 1 5 "${@:2}" </dev/null; }

# --- selftest: a write to the real tree fails, no network, no user bus, stubs answer -----------------------
st=0
touch "$A/.help-safe-probe" 2>/dev/null && { rm -f "$A/.help-safe-probe"; st=1; echo "SELFTEST FAIL ~/agents is writable"; }
touch "$HOME/.help-safe-probe" 2>/dev/null && { rm -f "$HOME/.help-safe-probe"; st=1; echo "SELFTEST FAIL HOME is writable"; }
python3 -c 'import socket; socket.create_connection(("1.1.1.1", 53), 2)' 2>/dev/null && { st=1; echo "SELFTEST FAIL network reachable"; }
[ -e "/run/user/$(id -u)/bus" ] && { st=1; echo "SELFTEST FAIL user bus reachable"; }
run "$W/st" sh -c 'systemctl --user stop x'; grep -qx 'systemctl --user stop x' "$W/st" 2>/dev/null || { st=1; echo "SELFTEST FAIL stub"; }
[ "$st" = 0 ] && ok "selftest: read-only tree and HOME, no network, no user bus, $(wc -w <<<"$STUBBED") commands stubbed" || exit 1

# --- static: the script's text holds a help branch ------------------------------------------------------
classify() {  # classify <path>...: "<help|none>\t<path>" per script, paths relative to ~/agents or absolute
  (cd "$A" && python3 - "$@" <<'PY'
import re, sys
FLAG = re.compile(r'''(?:^|[\s|(='"\[])(?:-h|--help)(?:[\s|)'"\]]|$)''')
for p in sys.argv[1:]:
    t = open(p, errors='replace').read()
    lines, kind = t.split('\n'), 'none'
    if 'pc_usage' in t or 'BASH_SOURCE[0]' in t or (re.search(r'^\s*(?:import|from)\s+argparse\b', t, re.M) and re.search(r'\.parse_(?:known_)?args\(', t)):
        kind = 'help'
    for l in lines:
        if kind == 'none' and FLAG.search(l) and not l.lstrip().startswith(('#', '//')):
            kind = 'help'
    if kind == 'none':
        for l in lines[1:]:
            s = re.sub(r'^(?:[A-Za-z_]\w*=(?:"[^"]*"|\S*)\s+)+', '', l.strip())
            if not s or s.startswith(('#', 'set ', '. ', 'source ')) or re.match(r'^[A-Za-z_]\w*=', s):
                continue
            kind = 'help' if s.startswith('exec ') and '"$@"' in s else 'none'
            break
    print(f'{kind}\t{p}')
PY
  )
}

# --- dynamic: each static pass runs --help once in the sandbox, 8 at a time --------------------------------
one() {  # one <path>: SAFE or UNSAFE <why>
  local c="$W/calls.${1//\//_}" out rc
  local x=$1; [[ $x == /* ]] || x="$A/$1"
  : >"$c"; out=$(run "$c" "$x" --help 2>&1); rc=$?
  if [ "$rc" = 0 ] && [ -n "$out" ] && [ ! -s "$c" ] && ! grep -q 'Read-only file system' <<<"$out"; then echo SAFE
  else echo "UNSAFE rc=$rc calls=$(tr '\n' ';' <"$c" | cut -c1-80) out=$(head -c 80 <<<"$out" | tr '\n' ' ')"; fi
}
# fixtures: a script without a help branch is not run; one whose --help acts is caught.
mkdir "$W/fx"; printf '#!/bin/sh\nsystemctl --user restart x\n' >"$W/fx/nohelp"
printf '#!/bin/sh\ncase "$1" in --help) systemctl --user stop x; echo usage ;; esac\n' >"$W/fx/acts"; chmod +x "$W/fx"/*
is 'static: no help branch → none, a --help arm → help' "$(classify "$W/fx/nohelp" "$W/fx/acts" | cut -f1 | tr '\n' ' ')" 'none help '
r=$(one "$W/fx/acts"); [[ $r == UNSAFE*'systemctl --user stop x'* ]] && ok 'dynamic: a --help that calls systemctl is not safe' || nok 'dynamic acts' "$r"

list=$( (for f in "$A"/bin/*; do [ -f "$f" ] && [ -x "$f" ] && echo "bin/${f##*/}"; done; printf '%s\n' $EXTRA) | sort -u)
static=$(classify $list)
n=0; nstatic=0
while IFS=$'\t' read -r kind p; do
  n=$((n+1)); f="$W/res/${p//\//_}"
  if [ "$kind" = none ]; then nstatic=$((nstatic+1)); echo "UNSAFE static: no help branch, not run" >"$f"; continue; fi
  while [ "$(jobs -rp | wc -l)" -ge 8 ]; do wait -n; done
  one "$p" >"$f" &
done <<<"$static"
wait

unsafe=0
while IFS=$'\t' read -r _ p; do
  r=$(cat "$W/res/${p//\//_}")
  if [ "$r" = SAFE ]; then [ -n "${EXCEPT[$p]:-}" ] && nok "$p" "passes now: drop its exception row"
  else unsafe=$((unsafe+1)); [ -n "${EXCEPT[$p]:-}" ] || nok "$p --help" "${r#UNSAFE }"; fi
done <<<"$static"
for p in "${!EXCEPT[@]}"; do grep -q $'\t'"$p"'$' <<<"$static" || nok "exception $p" 'not a fleet script here'; done
echo "help-safe: $n scripts, $nstatic without a help branch, $unsafe not safe, ${#EXCEPT[@]} on the exception list"
rm -rf "$W"
exit "$bad"
