#!/usr/bin/env bash
# Fixture test for eye-channel-accept: a fake dialog TUI in a private tmux -L server; the real tmux `claude` is never reached.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPT="$(dirname "$here")/eye-channel-accept"
fail() { echo "eye-channel-accept.test: FAIL — $1" >&2; exit 1; }
command -v tmux >/dev/null || { echo "eye-channel-accept.test: skip (no tmux)"; exit 0; }

WORK=$(mktemp -d); SOCK="eca-test-$$"
export TMUX_SOCKET="$SOCK"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
cat >"$WORK/fake.py" <<'EOF'
import os, sys, termios, tty, time
DIALOGS = {
    "trust": ("Quick safety check: Is this a project you created or one you trust?", ["No, exit", "Yes, I trust this folder"], 0),
    "stuck": ("Quick safety check: Is this a project you created or one you trust?", ["No, exit", "Yes, I trust this folder"], 0),
    "channels": ("WARNING: Loading development channels", ["1. I am using this for local development", "2. Exit"], 1),
}
log = open(sys.argv[1], "a", buffering=1)
fd = sys.stdin.fileno(); tty.setraw(fd)
def draw(title, opts, cur):
    out = "\033[2J\033[H" + title + "\r\n\r\n"
    for k, o in enumerate(opts):
        out += ("❯ " if k == cur else "  ") + o + "\r\n"
    os.write(1, out.encode())
for name in [d for d in sys.argv[2].split(",") if d]:
    title, opts, cur = DIALOGS[name]
    draw(title, opts, cur)
    while True:
        b = os.read(fd, 8)
        if b.startswith(b"\x1b[") and name != "stuck":
            cur = max(0, cur - 1) if b[2:3] == b"A" else min(len(opts) - 1, cur + 1) if b[2:3] == b"B" else cur
            draw(title, opts, cur)
        elif b in (b"\r", b"\n"):
            log.write(f"{name}={opts[cur]}\n")
            if opts[cur] in ("No, exit", "2. Exit"):
                sys.exit(1)
            break
os.write(1, b"\033[2J\033[H> ready\r\n")
time.sleep(60)
EOF

run() {  # run <dialogs> <wait>: fresh fake session, then eye-channel-accept against it
  : >"$WORK/log"
  tmux -L "$SOCK" kill-session -t fake 2>/dev/null
  tmux -L "$SOCK" new-session -d -s fake -x 100 -y 20 "python3 $WORK/fake.py $WORK/log $1" || fail "tmux new-session"
  sleep 0.5
  out="$(ACCEPT_GRACE=2 sh "$ACCEPT" fake "$2")"; rc=$?
}

tmux -L "$SOCK" new-session -d -s probe || fail "selftest: tmux -L server"
case "$(tmux -L "$SOCK" display -p -t probe '#{socket_path}')" in */"$SOCK") ;; *) fail "selftest: fixture is not on the private socket" ;; esac
tmux -L "$SOCK" kill-session -t probe

run "trust,channels" 10
[ "$rc" = 0 ] || fail "trust+channels rc=$rc: $out"
[ "$(cat "$WORK/log")" = "trust=Yes, I trust this folder
channels=1. I am using this for local development" ] || fail "trust+channels picked: $(cat "$WORK/log")"

run "channels,trust" 10
[ "$rc" = 0 ] || fail "channels+trust rc=$rc: $out"
[ "$(cat "$WORK/log")" = "channels=1. I am using this for local development
trust=Yes, I trust this folder" ] || fail "channels+trust picked: $(cat "$WORK/log")"

run "channels" 10
[ "$rc" = 0 ] || fail "channels only rc=$rc: $out"
[ "$(cat "$WORK/log")" = "channels=1. I am using this for local development" ] || fail "channels only picked: $(cat "$WORK/log")"

run "trust" 4
[ "$rc" = 0 ] || fail "trust only rc=$rc: $out"
[ "$(cat "$WORK/log")" = "trust=Yes, I trust this folder" ] || fail "trust only picked: $(cat "$WORK/log")"
case "$out" in *"workspace trusted"*"no channels dialog"*) ;; *) fail "trust only output: $out" ;; esac

run "" 2
[ "$rc" = 0 ] || fail "no dialog rc=$rc"
[ ! -s "$WORK/log" ] || fail "no dialog but a key was chosen: $(cat "$WORK/log")"
case "$out" in *"no channels dialog in 2s"*) ;; *) fail "no dialog output: $out" ;; esac

run "stuck" 10
[ "$rc" = 1 ] || fail "stuck selector rc=$rc: $out"
[ ! -s "$WORK/log" ] || fail "Enter sent on the default 'No, exit': $(cat "$WORK/log")"

echo "eye-channel-accept.test: ok"
