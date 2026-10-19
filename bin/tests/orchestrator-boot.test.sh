#!/usr/bin/env bash
# Boot path of claude-orchestrator.service, proven without a reboot: a copy of the real unit (claude
# swapped for a dialog stub, tmux on a private -L socket) is enabled into default.target of a fresh,
# private `systemd --user` whose unit path holds only stock targets, then that manager boots.
# Fixture-only (FLEET §5.6): the real claude binary, tmux session "claude" and user manager are
# unreachable by construction, proven by the selftest before the run.
set -uo pipefail
REAL="${ORCH_UNIT_FILE:-$HOME/.config/systemd/user/claude-orchestrator.service}"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
die() { echo "orchestrator-boot.test: FAIL — $1" >&2; exit 1; }

WORK=$(mktemp -d); SOCK="orchboot-$$"; SESS="orchboot-$$"; U="$WORK/units"; RUN="$WORK/run"
mkdir -p "$U/default.target.wants" "$RUN"; chmod 700 "$RUN"
psys() { env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR="$RUN" systemctl --user "$@"; }
cleanup() {
  psys exit >/dev/null 2>&1; sleep 1
  systemctl --user stop "orchboot-$$.scope" >/dev/null 2>&1
  systemctl --user reset-failed "orchboot-$$.scope" >/dev/null 2>&1
  tmux -L "$SOCK" kill-server 2>/dev/null; chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"
}
trap cleanup EXIT

# Stub for claude: logs its argv, then shows the launch dialogs the real one shows in ~.
cat >"$WORK/fake.py" <<'EOF'
import os, sys, tty, time
DIALOGS = [
    ("Quick safety check: Is this a project you created or one you trust?", ["No, exit", "Yes, I trust this folder"], 0),
    ("WARNING: Loading development channels", ["1. I am using this for local development", "2. Exit"], 1),
]
log = open(sys.argv[1], "a", buffering=1)
fd = sys.stdin.fileno(); tty.setraw(fd)
def draw(title, opts, cur):
    out = "\033[2J\033[H" + title + "\r\n\r\n"
    for k, o in enumerate(opts):
        out += ("❯ " if k == cur else "  ") + o + "\r\n"
    os.write(1, out.encode())
for title, opts, cur in DIALOGS:
    draw(title, opts, cur)
    while True:
        b = os.read(fd, 8)
        if b.startswith(b"\x1b["):
            cur = max(0, cur - 1) if b[2:3] == b"A" else min(len(opts) - 1, cur + 1) if b[2:3] == b"B" else cur
            draw(title, opts, cur)
        elif b in (b"\r", b"\n"):
            log.write(f"picked={opts[cur]}\n")
            if opts[cur] in ("No, exit", "2. Exit"):
                sys.exit(1)
            break
os.write(1, b"\033[2J\033[H> ready\r\n")
time.sleep(600)
EOF
printf '#!/bin/sh\nprintf "argv=%%s\\n" "$*" >>%s/log\nexec python3 %s/fake.py %s/log\n' "$WORK" "$WORK" "$WORK" >"$WORK/stub"
chmod +x "$WORK/stub"

# Test copy of the real unit: same [Unit], [Install] and Exec* lines, only the targets swapped.
[ -r "$REAL" ] || die "no unit file at $REAL"
sed -e "s#%h/.local/bin/claude#$WORK/stub#g" \
    -e "s#tmux has-session -t claude #tmux -L $SOCK has-session -t $SESS #" \
    -e "s#exec tmux new-session -d -s claude #exec tmux -L $SOCK new-session -d -x 120 -y 30 -s $SESS #" \
    -e "s#/usr/bin/tmux kill-session -t claude\$#/usr/bin/tmux -L $SOCK kill-session -t $SESS#" \
    -e "s#eye-channel-accept claude\$#eye-channel-accept $SESS#" \
    -e "s#^\[Service\]\$#[Service]\nEnvironment=TMUX_SOCKET=$SOCK#" \
    "$REAL" >"$U/orch-boot-test.service"
ln -s ../orch-boot-test.service "$U/default.target.wants/orch-boot-test.service"
for t in default basic graphical-session sockets timers paths shutdown exit; do
  cp "/usr/lib/systemd/user/$t.target" "$U/"
done
cp /usr/lib/systemd/user/systemd-exit.service "$U/"

# --- selftest: nothing real is reachable --------------------------------------
T="$U/orch-boot-test.service"
grep -q '\.local/bin/claude' "$T" && die "selftest: test unit still runs the real claude"
grep -Eq -- '-[ts] claude( |$)|accept claude$' "$T" && die "selftest: test unit still names session claude"
[ "$(grep '^Exec' "$T" | grep -o 'tmux [^ ]*' | sort -u)" = "tmux -L" ] || die "selftest: a tmux call is off the private socket"
grep -q "^Environment=TMUX_SOCKET=$SOCK\$" "$T" || die "selftest: eye-channel-accept not on the private socket"
diff <(grep -E '^(After|Wants|Requires|WantedBy|Type|ExecStartPre|TimeoutStartSec|Restart)' "$REAL") \
     <(grep -E '^(After|Wants|Requires|WantedBy|Type|ExecStartPre|TimeoutStartSec|Restart)' "$T") >/dev/null \
  || die "selftest: dependency lines differ from the real unit"
ok "selftest: stub claude, private tmux socket $SOCK, same dependency lines as $REAL"

out=$(systemd-analyze --user verify "$REAL" 2>&1 | grep -v 'spice-vdagent')
[ -z "$out" ] && ok "systemd-analyze verify: real unit clean" || nok "verify real unit" "$out"

# --- boot a private user manager ---------------------------------------------
systemd-run --user --scope --quiet --unit="orchboot-$$" -p Delegate=yes \
  env -u TMUX -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR="$RUN" SYSTEMD_UNIT_PATH="$U" \
  /usr/lib/systemd/systemd --user --log-target=null >/dev/null 2>&1 &
timeout 20 wait-for --label orchboot-mgr --every 1 --until "[ -S '$RUN/systemd/private' ]" >/dev/null \
  || die "private systemd --user did not come up"
psys list-unit-files --no-legend 2>/dev/null | grep -q claude-orchestrator \
  && die "selftest: private manager sees the real unit"
ok "private systemd --user up; unit path = $U only"

timeout 150 wait-for --label orchboot-default --every 1 \
  --until "[ \"\$(env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR='$RUN' systemctl --user is-active default.target)\" = active ]" >/dev/null
st=$(psys is-active orch-boot-test.service)
[ "$st" = active ] && ok "unit active after boot (default.target reached)" || nok "unit state" "$st; $(psys status orch-boot-test.service --no-pager 2>&1 | tail -5)"

ts() { psys show -p "$2" --value "$1"; }
u_on=$(ts orch-boot-test.service ActiveEnterTimestampMonotonic)
d_on=$(ts default.target ActiveEnterTimestampMonotonic)
b_on=$(ts basic.target ActiveEnterTimestampMonotonic)
[ "$b_on" -le "$u_on" ] && [ "$u_on" -le "$d_on" ] 2>/dev/null \
  && ok "ordering: basic.target <= unit active <= default.target" || nok "ordering" "basic=$b_on unit=$u_on default=$d_on"
[ "$(ts graphical-session.target ActiveState)" = inactive ] && ok "no graphical session needed (linger path)" \
  || nok "graphical-session" "$(ts graphical-session.target ActiveState)"

tmux -L "$SOCK" has-session -t "$SESS" 2>/dev/null && ok "tmux session $SESS created" || nok "tmux session" "missing"
grep -q -- '^argv=--continue --remote-control DarkSaddler Command Center --mcp-config .*server:eye-main --append-system-prompt-file .*/agents/ORCHESTRATOR\.md$' "$WORK/log" \
  && ok "stub ran with the real argv (--continue, Remote Control name, eye-main channel, ORCHESTRATOR.md)" || nok "stub argv" "$(cat "$WORK/log")"
[ "$(grep -c '^picked=' "$WORK/log")" = 2 ] && grep -q 'picked=Yes, I trust this folder' "$WORK/log" \
  && grep -q 'picked=1. I am using this for local development' "$WORK/log" \
  && ok "ExecStartPost answered trust + channels dialogs" || nok "dialogs" "$(grep picked "$WORK/log")"
tmux -L "$SOCK" capture-pane -pt "$SESS" | grep -q '> ready' && ok "stub serving (> ready)" || nok "pane" "$(tmux -L "$SOCK" capture-pane -pt "$SESS")"

exit "$bad"
