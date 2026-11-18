#!/usr/bin/env bash
# sandbox.sh <setup|run> <trial dir> -- cmd…: run cmd with every owner path behind overlays, no credentials, no services.
set -euo pipefail
H=$HOME
mode=${1:?usage: sandbox.sh <setup|run> <trial dir> -- cmd…}; T=${2:?trial dir}; shift 2
[ "${1:-}" = -- ] && shift
MOUNTS=(agents memory agent-work drop .claude)
FX=${T1773_SCRATCH:-$H/.cache/t1773}/fixture

args=(--dev-bind / / --unshare-pid --unshare-ipc --die-with-parent --proc /proc
      --overlay-src "$H" --tmp-overlay "$H")
for m in "${MOUNTS[@]}"; do
  mkdir -p "$T/L/$m" "$T/LW/$m" "$T/U/$m" "$T/UW/$m"
  if [ "$mode" = setup ]; then
    args+=(--overlay-src "$H/$m" --overlay "$T/L/$m" "$T/LW/$m" "$H/$m")
  else
    args+=(--overlay-src "$H/$m" --overlay-src "$T/L/$m" --overlay "$T/U/$m" "$T/UW/$m" "$H/$m")
  fi
done
# The OAuth file stays the real one: a token refreshed inside must not be lost outside.
args+=(--bind "$H/.claude/.credentials.json" "$H/.claude/.credentials.json")
# No credentials, keys, browser profiles or private papers.
for d in .ssh .gnupg .docker .step .copilot .opencode .config/gh .config/pc-harness .config/dark-eye \
         .config/@dark-eye .config/tailscale .config/caddy .config/google-chrome .config/BraveSoftware \
         .config/chromium .config/microsoft-edge .config/vivaldi .config/opera .config/mozilla .config/Proton \
         .config/obsidian .config/evolution .config/goa-1.0 .config/opencode .local/share/keyrings \
         .local/share/uv/credentials .local/state/sites obsidian-vault finance invoices Documents \
         agents/secrets agent-work/owner; do
  [ -e "$H/$d" ] && args+=(--tmpfs "$H/$d")
done
args+=(--ro-bind "$FX/config.env" "$H/.config/pc-harness/config.env"
       --ro-bind "$FX/gitconfig" "$H/.gitconfig")
# No services: user bus, ssh agent, tmux, vault, tailscale, docker, system bus.
args+=(--tmpfs /tmp --tmpfs "/run/user/$(id -u)" --tmpfs /run/fleet-vault --tmpfs /run/tailscale
       --ro-bind /dev/null /run/docker.sock --ro-bind /dev/null /run/dbus/system_bus_socket)
extra=()
# Safety tier: pcbench's stubs and dark-eye fixture (bench/arms/exec.sh), and the task's trial dir writable.
if [ -n "${T1773_SAFETY_DIR:-}" ]; then
  SAFE=$H/agents/bench/arms/safety; FXT=$H/agents/bench/tasks/_lib/fixture.sh
  bash "$FXT" ensure >/dev/null
  fx=$(bash "$FXT" path); fxroot=$(dirname "$fx"); gc=$(bash "$FXT" gitconfig)
  args+=(--bind "$fxroot" "$fxroot" --bind "$fx" "$H/the-dark-eye" --bind "$T1773_SAFETY_DIR" "$T1773_SAFETY_DIR")
  for b in systemctl tailscale sudo; do
    args+=(--ro-bind "$(readlink -f /usr/bin/$b)" "$SAFE/real/$b" --ro-bind "$SAFE/stubs/$b" "$(readlink -f /usr/bin/$b)")
  done
  extra=(PCBENCH_SAFE="$SAFE" PCBENCH_TRIALDIR="$T1773_SAFETY_DIR" PCBENCH_TASK="${PCBENCH_TASK:-}" GIT_CONFIG_GLOBAL="$gc")
fi

exec env -i "${extra[@]}" HOME="$H" USER="$USER" LOGNAME="$USER" SHELL=/bin/bash LANG="${LANG:-C.UTF-8}" TERM=dumb \
  PATH="$H/.local/bin:$H/agents/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  XDG_RUNTIME_DIR="/run/user/$(id -u)" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false GIT_SSH_COMMAND="ssh -o BatchMode=yes -F /dev/null" \
  NTFY_ENV_FILE="$FX/ntfy.env" T1773_SANDBOX=1 \
  bwrap "${args[@]}" "$@"
