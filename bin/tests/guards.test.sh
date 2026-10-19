#!/usr/bin/env bash
# bin/guards: the FLEET.md §5 refusal guard on the headless fleet PATH.
# Nothing real is reached — the "real" binaries in these tests are stubs in a temp dir.
set -uo pipefail
BIN="$HOME/agents/bin"; G="$BIN/guards"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export HARNESS_GUARD_LOG="$WORK/guards.jsonl"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

# Stubs stand in for the real binaries the guard forwards to.
mkdir -p "$WORK/real"
for n in reboot shutdown tailscale sudo systemctl; do
  printf '#!/bin/sh\necho "REAL %s $*"\n' "$n" >"$WORK/real/$n"; chmod +x "$WORK/real/$n"
done
export PATH="$G:$WORK/real:/usr/local/bin:/usr/bin:/bin"

repo="$WORK/repo"; mkdir -p "$repo"
git -C "$repo" init -q 2>/dev/null; : >"$repo/f"; git -C "$repo" add f 2>/dev/null

# 1. git commit / push are refused, with the three-part message and exit 3.
out=$(cd "$repo" && git commit -m x 2>&1); rc=$?
is 'git commit exits 3' "$rc" 3
grep -q '^refused: FLEET.md §5.1' <<<"$out" && ok 'git commit names the rule' || nok 'git commit names the rule' "$out"
grep -q '^instead: ' <<<"$out" && ok 'git commit offers the alternative' || nok 'git commit offers the alternative' "$out"
grep -q '^who can: the owner, by hand' <<<"$out" && ok 'git commit says who can' || nok 'git commit says who can' "$out"
out=$(cd "$repo" && git push origin main 2>&1); is 'git push exits 3' "$?" 3
out=$(git -C "$repo" commit -m x 2>&1); is 'git -C … commit exits 3' "$?" 3
out=$(git -c user.name=x -C "$repo" push 2>&1); is 'git -c … push exits 3' "$?" 3

# 2. every other git verb still works.
out=$(git -C "$repo" status --porcelain 2>&1); is 'git status forwards' "$?" 0
grep -q '^A  f' <<<"$out" && ok 'git status is the real answer' || nok 'git status is the real answer' "$out"
out=$(git -C "$repo" rev-parse --is-inside-work-tree 2>&1); is 'git rev-parse forwards' "$out" true

# 3. reboot / shutdown / poweroff / halt: with the owner switch at 0 (or unset) refused at any hour;
#    with it at 1, refused outside 04-05h and forwarded inside.
for n in reboot shutdown poweroff halt; do
  out=$(MAINT_AUTO_REBOOT=0 GUARD_NOW_HOUR=4 "$n" 2>&1); rc=$?
  [ "$rc" = 3 ] && grep -q 'auto-reboot is off' <<<"$out" && ok "$n refused at 04:30 with the switch at 0" \
    || nok "$n refused at 04:30 with the switch at 0" "$rc $out"
  out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=13 "$n" 2>&1); rc=$?
  [ "$rc" = 3 ] && grep -q '§5.2' <<<"$out" && ok "$n refused at 13h with the switch at 1" || nok "$n refused at 13h with the switch at 1" "$rc $out"
done
out=$(unset MAINT_AUTO_REBOOT; GUARD_NOW_HOUR=4 reboot 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'MAINT_AUTO_REBOOT=unset' <<<"$out" && ok 'reboot refused in the window with the switch unset' \
  || nok 'reboot refused in the window with the switch unset' "$rc $out"
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=4 reboot 2>&1); is 'reboot forwards inside the window with the switch at 1' "$out" "REAL reboot "
for v in reboot poweroff halt kexec soft-reboot; do
  out=$(MAINT_AUTO_REBOOT=0 GUARD_NOW_HOUR=4 sudo systemctl "$v" 2>&1); rc=$?
  [ "$rc" = 3 ] && grep -q 'auto-reboot is off' <<<"$out" && ok "sudo systemctl $v refused with the switch at 0" \
    || nok "sudo systemctl $v refused with the switch at 0" "$rc $out"
done
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=4 sudo systemctl reboot 2>&1); is 'sudo systemctl reboot forwards inside the window with the switch at 1' "$out" "REAL sudo systemctl reboot"

# 4. tailscale down / logout refused, read-only verbs forwarded.
out=$(tailscale down 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q '§5.3' <<<"$out" && ok 'tailscale down refused' || nok 'tailscale down refused' "$rc $out"
out=$(tailscale logout 2>&1); is 'tailscale logout exits 3' "$?" 3
out=$(tailscale status 2>&1); is 'tailscale status forwards' "$out" "REAL tailscale status"

# 5. sudo: the wrapped command meets the same rules (secure_path hole, TSP-001).
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=13 sudo shutdown -r +5 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q '§5.2' <<<"$out" && ok 'sudo shutdown refused at 13h' || nok 'sudo shutdown refused at 13h' "$rc $out"
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=13 sudo -n reboot 2>&1); is 'sudo -n reboot exits 3' "$?" 3
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=13 sudo -u root -E poweroff 2>&1); is 'sudo -u root -E poweroff exits 3' "$?" 3
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=13 sudo -- halt 2>&1); is 'sudo -- halt exits 3' "$?" 3
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=13 sudo /sbin/shutdown -h now 2>&1); is 'sudo /sbin/shutdown exits 3' "$?" 3
out=$(sudo tailscale down 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q '§5.3' <<<"$out" && ok 'sudo tailscale down refused' || nok 'sudo tailscale down refused' "$rc $out"
out=$(sudo systemctl stop tailscaled 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q '§5.3' <<<"$out" && ok 'sudo systemctl stop tailscaled refused' || nok 'sudo systemctl stop tailscaled refused' "$rc $out"
out=$(sudo systemctl mask docker.service 2>&1); is 'sudo systemctl mask docker.service exits 3' "$?" 3
out=$(sudo systemctl disable sentinel-check.timer 2>&1); is 'sudo systemctl disable sentinel-check exits 3' "$?" 3

out=$(MAINT_AUTO_REBOOT=0 GUARD_NOW_HOUR=4 sudo shutdown -r +5 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'auto-reboot is off' <<<"$out" && ok 'sudo shutdown refused in the window with the switch at 0' \
  || nok 'sudo shutdown refused in the window with the switch at 0' "$rc $out"

# maintenance-run's own reboot is exempt only with the owner switch at 1 and inside the window.
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=4 sudo shutdown -r +5 2>&1); is 'sudo shutdown forwards inside the window with the switch at 1' "$out" "REAL sudo shutdown -r +5"
out=$(sudo apt-get -y full-upgrade 2>&1); is 'sudo apt-get forwards' "$out" "REAL sudo apt-get -y full-upgrade"
out=$(sudo systemctl restart tailscaled 2>&1); is 'sudo systemctl restart forwards' "$out" "REAL sudo systemctl restart tailscaled"
out=$(sudo systemctl stop cups.service 2>&1); is 'sudo systemctl stop of a non-fleet unit forwards' "$out" "REAL sudo systemctl stop cups.service"
out=$(sudo -n systemctl status docker 2>&1); is 'sudo systemctl status forwards' "$out" "REAL sudo -n systemctl status docker"
out=$(sudo 2>&1); is 'bare sudo forwards' "$out" "REAL sudo "

# 5b. systemctl itself (logind lets this user reboot without sudo, T347-04): power verbs refused,
#     every other verb forwarded — agents-stop and `pc units` stop user units through it.
for v in reboot poweroff halt kexec soft-reboot; do
  out=$(MAINT_AUTO_REBOOT=0 GUARD_NOW_HOUR=4 systemctl "$v" 2>&1); rc=$?
  [ "$rc" = 3 ] && grep -q 'auto-reboot is off' <<<"$out" && ok "systemctl $v refused with the switch at 0" \
    || nok "systemctl $v refused with the switch at 0" "$rc $out"
done
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=13 systemctl -i reboot 2>&1); is 'systemctl -i reboot exits 3 at 13h' "$?" 3
out=$(MAINT_AUTO_REBOOT=1 GUARD_NOW_HOUR=4 systemctl reboot 2>&1); is 'systemctl reboot forwards inside the window with the switch at 1' "$out" "REAL systemctl reboot"
out=$(systemctl --user stop agent@alpha.service 2>&1); is 'systemctl --user stop forwards' "$out" "REAL systemctl --user stop agent@alpha.service"
out=$(systemctl --user is-active dark-eye.service 2>&1); is 'systemctl is-active forwards' "$out" "REAL systemctl --user is-active dark-eye.service"

# 5c. the Claude adapter carries the same power verbs as permissions.deny rules (every session,
#     interactive and subagent); install is idempotent and keeps the owner's own rules.
A="$HOME/agents/adapters/claude"
printf '{"permissions":{"deny":["Bash(git push:*)"]}}\n' >"$WORK/s.json"
python3 "$A/merge-settings.py" install "$WORK/s.json" "$A/settings.fragment.json" "$WORK/h" >/dev/null
for r in 'Bash(systemctl reboot:*)' 'Bash(systemctl poweroff:*)' 'Bash(systemctl halt:*)' 'Bash(systemctl kexec:*)' \
         'Bash(reboot:*)' 'Bash(shutdown:*)' 'Bash(poweroff:*)' 'Bash(halt:*)' 'Bash(sudo reboot:*)' 'Bash(sudo shutdown:*)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$WORK/s.json" >/dev/null \
    && ok "install denies $r" || nok "install denies $r" "$(jq -c .permissions "$WORK/s.json")"
done
jq -e '.permissions.deny[0] == "Bash(git push:*)"' "$WORK/s.json" >/dev/null && ok 'install keeps the existing deny rules' \
  || nok 'install keeps the existing deny rules' "$(jq -c .permissions "$WORK/s.json")"
out=$(python3 "$A/merge-settings.py" install "$WORK/s.json" "$A/settings.fragment.json" "$WORK/h"); is 'a second install changes nothing' "$out" "no changes"
python3 "$A/merge-settings.py" uninstall "$WORK/s.json" "$A/settings.fragment.json" "$WORK/h" >/dev/null
out=$(jq -c .permissions.deny "$WORK/s.json"); is 'uninstall leaves only the owner rules' "$out" '["Bash(git push:*)"]'

# 6. every refusal is one JSON line in the log.
n=$(wc -l <"$HARNESS_GUARD_LOG"); [ "$n" -ge 30 ] && ok "log has $n refusals" || nok 'log has the refusals' "$n"
jq -e -s 'all(.refused == true and (.rule|length) > 0 and (.tool|length) > 0)' "$HARNESS_GUARD_LOG" >/dev/null \
  && ok 'every log line is a complete JSON record' || nok 'every log line is a complete JSON record' "$(tail -1 "$HARNESS_GUARD_LOG")"

# 7. the guard is on the headless fleet PATH and nowhere else.
p=$(bash -c '. "$HOME/agents/bin/fleetlib.sh"; fleet_path; printf "%s" "$PATH"')
case "$p" in "$G":*) ok 'fleet_path puts guards first' ;; *) nok 'fleet_path puts guards first' "$p" ;; esac
grep -q 'bin/guards' "$HOME/.bashrc" 2>/dev/null \
  && nok 'the interactive shell is untouched' '.bashrc adds the guards dir' \
  || ok 'the interactive shell is untouched'

exit $bad
