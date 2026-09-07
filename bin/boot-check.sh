#!/usr/bin/env bash
# Post-boot health check: one OK/FAIL line per item, exit 1 if anything failed.
# shellcheck source=/dev/null
. "$HOME/agents/bin/env.sh"
fail=0
check() { # name, then command
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then printf 'OK   %s\n' "$name"
    else printf 'FAIL %s\n' "$name"; fail=1; fi
}
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

for c in moodle-shared-proxy-1 moodle-shared-mailhog-1 moodle-shared-selenium-1 moodle52-db-1 moodle52-app-1; do
    check "docker $c" running "$c"
done
check "moodle 5.2 http" curl -sf -o /dev/null http://localhost:8052/login/index.php
check "orchestrator tmux session" tmux has-session -t "$ORCHESTRATOR_TMUX_SESSION"
check "linger enabled" grep -qx 'Linger=yes' <(loginctl show-user "$USER" -p Linger)
check "tailscale up" tailscale status --peers=false
check "ssh service" systemctl is-active --quiet ssh
check "ydotoold service" systemctl is-active --quiet ydotoold
check "dark-eye body" systemctl --user is-active --quiet dark-eye

# The overview opens itself after every login and swallows the first click.
gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.freedesktop.DBus.Properties.Set org.gnome.Shell OverviewActive "<false>" >/dev/null 2>&1
check "desktop mode agent" test "$("$HOME/agents/bin/pc-mode" status 2>/dev/null)" = agent
exit $fail
