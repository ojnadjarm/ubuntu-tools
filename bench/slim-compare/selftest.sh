#!/usr/bin/env bash
# selftest.sh [ticket]: prove the sandbox cannot reach the real repos, credentials, services or units, and that each arm loads its own files.
set -uo pipefail
SC=$(cd "$(dirname "$0")" && pwd)
SCR=${T1773_SCRATCH:-$HOME/.cache/t1773}
tk=${1:-SAFETY}; fail=0
ok() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fail=1; fi; }
mark=t1773-selftest-$$
for arm in old slim; do
  T1773_SETUP_ONLY=1 "$SC/trial.sh" "$tk" "$arm" >/dev/null; ok $? "$arm: setup"
  T=$SCR/trials/$tk-$arm
  "$SC/sandbox.sh" run "$T" -- bash -c '
    A=$1 m=$2 head=$3
    t() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; fi; }
    t "no git remote in ~/agents or ~/memory" "[ -z \"\$(git -C ~/agents remote)\" ] && [ -z \"\$(git -C ~/memory remote)\" ]"
    t "git push fails" "! git -C ~/agents push origin HEAD"
    t "~/agents at the ticket commit" "[ \"\$(git -C ~/agents rev-parse HEAD)\" = $head ]"
    t "no ssh keys, gh token, fleet secrets" "[ -z \"\$(find ~/.ssh ~/.config/gh ~/agents/secrets -mindepth 1)\" ]"
    t "no password values in config.env" "! grep -qE \"PASSWORD=.+\" ~/.config/pc-harness/config.env"
    t "no user bus (units)" "! systemctl --user list-units"
    t "no system bus" "! busctl --system list"
    t "no tmux server" "! tmux ls"
    t "no docker" "! docker ps"
    t "no vault socket" "[ ! -S /run/fleet-vault/admin.sock ]"
    t "no tailscale socket" "! tailscale status"
    t "own pid namespace (no outside process visible)" "! ps -eo comm | grep -qE \"^(tmux|systemd)\$\""
    t "notify-owner aims at a dead port" "grep -q 127.0.0.1:9 \"\$NTFY_ENV_FILE\""
    t "arm AGENTS.md loaded" "cmp -s ~/agents/AGENTS.md $A/agents/AGENTS.md"
    t "arm global CLAUDE.md loaded" "cmp -s ~/.claude/CLAUDE.md $A/claude/CLAUDE.md"
    t "arm memory commit" "[ \"\$(git -C ~/memory rev-parse --short HEAD)\" = \"\$(cat $A/memory.commit)\" ]"
    t "harness context --worker runs" "harness context --worker"
    for d in agents memory agent-work drop .claude the-dark-eye .; do touch ~/$d/$m 2>/dev/null; done
  ' _ "$SCR/arms/$arm" "$mark" "$(cat "$T/setup.head")"
  [ $? = 0 ] || { echo "FAIL $arm: sandbox run"; fail=1; }
  leak=0
  for d in agents memory agent-work drop .claude the-dark-eye .; do [ -e "$HOME/$d/$mark" ] && { echo "leak: ~/$d/$mark"; leak=1; }; done
  ok $leak "$arm: no write reached a real path"
done
grep -q 'Iterate on one case' "$SCR/arms/old/agents/AGENTS.md" && ! grep -q 'Iterate on one case' "$SCR/arms/slim/agents/AGENTS.md"
ok $? "slim arm lacks a dropped row the old arm has (A21)"
exit $fail
