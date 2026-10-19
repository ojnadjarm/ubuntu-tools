#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2088  # strings run by eval or by the container shell
# T456: install.sh, then uninstall.sh, on fresh Ubuntu containers (systemd PID 1, --network none, tracked files only).
# usage: install-fresh.sh [24.04 26.04 ...]   last line: PASS/FAIL install-fresh ...
set -uo pipefail
REAL="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
FX="$REAL/bin/tests/fixtures/install-fresh"
VERSIONS=("${@:-24.04}"); [ $# -gt 0 ] || VERSIONS=(24.04 26.04)
C="t456-install-fresh-$$"
trap 'docker rm -f "$C" >/dev/null 2>&1' EXIT
fails=0; summary=""
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails + 1)); fi; }
CU=fleet; CH="/home/$CU"
X() { docker exec -u "$CU" -e USER="$CU" -e HOME="$CH" -e XDG_RUNTIME_DIR="/run/user/$CUID" \
        -e PATH="$CH/.local/bin:/usr/local/bin:/usr/bin:/bin" -w "$CH" "$C" bash -c "$1"; }

# Host residue the run must not touch: fleet links and user units.
host_state() { find "$HOME/.local/bin" "$HOME/.config/systemd/user" -printf '%p %l %s %T@\n' 2>/dev/null | sort | md5sum; }
before="$(host_state)"

for v in "${VERSIONS[@]}"; do
  echo "== ubuntu:$v"
  docker build -q --build-arg "BASE=ubuntu:$v" -t "install-fresh:$v" "$FX" >/dev/null \
    || { echo "  FAIL image build"; fails=$((fails + 1)); continue; }
  # No --privileged, no binds: SYS_ADMIN only to remount the private cgroup namespace rw for systemd.
  docker run -d -t --name "$C" --network none --cgroupns=private --cap-add SYS_ADMIN \
    --security-opt apparmor=unconfined --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
    "install-fresh:$v" sh -c 'mount -o remount,rw /sys/fs/cgroup && exec /sbin/init' >/dev/null
  ok "sandbox: network none, no mounts, not privileged" \
    '[ "$(docker inspect -f "{{.HostConfig.NetworkMode}} {{len .Mounts}} {{.HostConfig.Privileged}}" "$C")" = "none 0 false" ]'
  CUID="$(docker exec "$C" id -u "$CU")"
  ok "systemd boots" 'docker exec "$C" timeout 60 sh -c "until systemctl is-system-running 2>/dev/null | grep -qE \"^(running|degraded)\\$\"; do sleep 1; done"'
  ok "systemd --user reachable" 'X "timeout 30 sh -c \"until systemctl --user show-environment >/dev/null 2>&1; do sleep 1; done\""'

  docker exec "$C" mkdir -p "$CH/agents" "$CH/.config/pc-harness"
  (cd "$REAL" && git ls-files -z \
    | python3 -c 'import sys,os;sys.stdout.write("\0".join(p for p in sys.stdin.read().split("\0") if p and os.path.lexists(p)))' \
    | tar --null -T - -cf -) | docker cp - "$C:$CH/agents"
  docker cp "$FX/config.env" "$C:$CH/.config/pc-harness/config.env"
  docker exec "$C" chown -R "$CU:$CU" "$CH"

  out="$(X '~/agents/install.sh 2>&1; echo "EXIT=$?"')"
  printf '%s\n' "$out" | grep -E '^ *(MISSING|could not|adapter .* exited|.*: line [0-9]+:)' | sed 's/^ */  install: /' | sort -u
  ok "install.sh exits 0" 'grep -qx "EXIT=0" <<<"$out"'
  ok "install.sh applied changes" 'grep -qE "^install.sh: [0-9]+ change\(s\) applied" <<<"$out"'
  ok "fleet units enabled" '[ "$(X "systemctl --user list-units --all --no-legend \"agent@*.timer\" | wc -l")" -gt 0 ]'
  ok "harness context" 'X "harness context" | grep -q "^Machine now:"'
  ok "pc status --json" 'X "pc status --json 2>/dev/null" | jq -e "type == \"object\"" >/dev/null'
  ok "guide wait" 'X "guide wait" | grep -q "^guide "'

  X '~/agents/uninstall.sh' >/dev/null 2>&1
  links="$(X 'find ~/.local/bin ~/.claude -type l -exec readlink -f {} \; 2>/dev/null | grep -c "^$HOME/agents/"')"
  units="$(X 'find ~/.config/systemd/user -mindepth 1 \( ! -type d -o -name "agent@*" \) 2>/dev/null | wc -l')"
  ok "uninstall: 0 fleet links (got $links)" '[ "$links" = 0 ]'
  ok "uninstall: 0 fleet units (got $units)" '[ "$units" = 0 ]'
  docker rm -f "$C" >/dev/null
  summary="$summary $v"
done

ok "host ~/.local/bin and systemd user dir untouched" '[ "$(host_state)" = "$before" ]'
[ "$fails" = 0 ] && echo "PASS install-fresh:${summary// / ubuntu:}" \
  || echo "FAIL install-fresh: $fails check(s) failed"
