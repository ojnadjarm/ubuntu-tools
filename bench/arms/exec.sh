#!/usr/bin/env bash
# exec.sh <old|new> -- <command…> — run a command with that arm's bin/KB/docs bound over the
# real paths, for this process only. Everything else (D-Bus, PipeWire, docker, /run/user/1000)
# stays live; other processes keep seeing the real dirs.
#
# On top of the arm, every run gets the PB11 safety sandbox: ~/the-dark-eye is a throwaway
# fixture repo, the owner's ssh keys and git identity are invisible, and tailscale / reboot /
# shutdown / systemctl-on-a-fleet-unit / sudo are stubs that refuse realistically and record
# the attempt in the trial's attempts.jsonl. A trial can try every S-tier action; nothing real
# happens.  `exec.sh --selftest [arm]` proves all four before a safety run is allowed.
set -euo pipefail
BENCH="$HOME/agents/bench"
SAFE="$BENCH/arms/safety"
FIXTURE="$BENCH/tasks/_lib/fixture.sh"

if [ "${1:-}" = --selftest ]; then
  exec bash "$SAFE/selftest.sh" "${2:-new}"
fi

arm="${1:?usage: exec.sh <old|new> -- cmd… | exec.sh --selftest [arm]}"; shift
[ "${1:-}" = -- ] && shift
A="$BENCH/arms/$arm"
[ -d "$A/bin" ] || { echo "exec.sh: no arm at $A (run build-$arm.sh)" >&2; exit 2; }

bash "$FIXTURE" ensure || { echo "exec.sh: could not build the dark-eye fixture" >&2; exit 2; }
repo=$(bash "$FIXTURE" path)
gitcfg=$(bash "$FIXTURE" gitconfig)

safe=(
  # 1. the throwaway repo, so nothing a trial does can reach the owner's work
  --bind "$repo" "$HOME/the-dark-eye"
  # 2. no ssh keys, no git identity, no stored credentials, no agent socket
  --tmpfs "$HOME/.ssh"
  --ro-bind "$gitcfg" "$gitcfg"
  --setenv GIT_CONFIG_GLOBAL "$gitcfg"
  --setenv GIT_CONFIG_NOSYSTEM 1
  --setenv GIT_TERMINAL_PROMPT 0
  --setenv GIT_ASKPASS /bin/false
  --setenv SSH_ASKPASS /bin/false
  --setenv GIT_SSH_COMMAND "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5"
  --unsetenv SSH_AUTH_SOCK
  # 3. the stubs are bound over the *resolved* binaries, so every route reaches them:
  #    /usr/sbin/{reboot,poweroff,halt,shutdown} and /bin/systemctl all resolve to
  #    /usr/bin/systemctl, and /usr/bin/sudo to /usr/lib/cargo/bin/sudo.
  --ro-bind "$(readlink -f /usr/bin/systemctl)" "$SAFE/real/systemctl"
  --ro-bind "$(readlink -f /usr/bin/tailscale)" "$SAFE/real/tailscale"
  --ro-bind "$(readlink -f /usr/bin/sudo)"      "$SAFE/real/sudo"
  --ro-bind "$SAFE/stubs/systemctl" "$(readlink -f /usr/bin/systemctl)"
  --ro-bind "$SAFE/stubs/tailscale" "$(readlink -f /usr/bin/tailscale)"
  --ro-bind "$SAFE/stubs/sudo"      "$(readlink -f /usr/bin/sudo)"
  --setenv PCBENCH_SAFE "$SAFE"
)
# Only hide what exists: binding over a missing path makes bwrap create it on the real home.
for f in "$HOME/.gitconfig" "$HOME/.git-credentials"; do
  [ -e "$f" ] && safe+=(--ro-bind "$gitcfg" "$f")
done

exec bwrap --dev-bind / / \
  --bind "$A/bin" "$HOME/agents/bin" \
  --bind "$A/KB"  "$HOME/agents/KB" \
  --bind "$A/skills/desktop" "$HOME/.claude/skills/desktop" \
  --bind "$A/README-pc-control.md" "$HOME/agents/README-pc-control.md" \
  "${safe[@]}" \
  "$@"
