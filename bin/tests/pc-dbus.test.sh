#!/usr/bin/env bash
# PT08: `pc dbus`. Sections 1-4 run against the recorded bus in fixtures/dbus (no bus contact);
# section 5 is live and read-only; section 6 is the one mutation (OverviewActive to its current
# value — nothing moves on screen) on a temp ledger. No window, no sound, no monitor config.
set -uo pipefail
BIN="$HOME/agents/bin"
PC="$BIN/pc-dbus"
FIX="$BIN/tests/fixtures/dbus"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
fx()  { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" "$PC" "$@"; }

# 1. shape: the description line pc help prints, -h, and the exit codes.
l=$(sed -n 2p "$PC")
case "$l" in '# pc dbus '*' — '*) ok 'line 2 is the pc help signature';; *) nok 'line 2 is the pc help signature' "$l";; esac
fx -h >/dev/null; is '-h exits 0' "$?" 0
fx --nope >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2

# 2. read verbs against the recording.
is 'list --json finds org.gnome.Shell' \
  "$(fx list --json | jq -r '[.names[].name] | index("org.gnome.Shell") != null')" true
is 'list --json carries the bus' "$(fx list --json | jq -r .bus)" user
is 'tree --json lists paths' \
  "$(fx tree org.gnome.Shell --json | jq -r '.paths | index("/org/gnome/Shell") != null')" true
i=$(fx introspect org.gnome.Shell /org/gnome/Shell --json)
is 'introspect --json reads a property value' \
  "$(jq -r '.interfaces[] | select(.name=="org.gnome.Shell") | .properties[] | select(.name=="ShellVersion") | .value' <<<"$i")" 50.1
is 'introspect --json reads write access' \
  "$(jq -r '.interfaces[] | select(.name=="org.gnome.Shell") | .properties[] | select(.name=="OverviewActive") | .access' <<<"$i")" readwrite
is 'introspect --json types a boolean' \
  "$(jq -r '.interfaces[] | select(.name=="org.gnome.Shell") | .properties[] | select(.name=="OverviewActive") | .value | type' <<<"$i")" boolean
is 'introspect --json lists methods with signatures' \
  "$(jq -r '.interfaces[] | select(.name=="org.gnome.Shell") | .methods[] | select(.name=="GrabAccelerator") | .in' <<<"$i")" suu
is 'introspect --json lists signals' \
  "$(jq -r '[.interfaces[].signals[].name] | index("AcceleratorActivated") != null' <<<"$i")" true
is 'get --json keeps busctl'\''s .data' \
  "$(fx get org.gnome.Shell /org/gnome/Shell org.gnome.Shell.ShellVersion --json | jq -r .data)" 50.1
is 'get text prints the bare value' \
  "$(fx get org.gnome.Shell /org/gnome/Shell org.gnome.Shell.ShellVersion)" 50.1
is 'call --json names what it called' \
  "$(fx call org.gnome.Shell /org/gnome/Shell/Extensions/Windows List --json | jq -r .interface)" org.gnome.Shell.Extensions.Windows

# 3. resolution: the interface off a bare member, the path when only one carries one, ambiguity.
is 'a bare member resolves its interface' \
  "$(fx introspect pc.test.Single --json | jq -r .path)" /pc/test
is 'a mutating call without --apply prints would:' \
  "$(fx call pc.test.Single Reload)" 'would: call user:pc.test.Single/pc/test pc.test.Iface.Reload() — rerun with --apply'
fx get org.gnome.Shell /org/gnome/Shell org.gnome.Shell.NoSuchProp >/dev/null 2>&1
is 'an unknown property exits 1' "$?" 1
fx get org.gnome.Shell org.gnome.Shell.Mode >/dev/null 2>&1
is 'an ambiguous path exits 2' "$?" 2

# 4. the deny-list — exit 3, and nothing connects to a bus.
deny() {
  out=$(fx "$@" --apply 2>&1); rc=$?
  [ "$rc" = 3 ] && case "$out" in *FLEET*) ok "denies: $*"; return;; esac
  nok "denies: $*" "exit $rc: $out"
}
deny call org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig ApplyMonitorsConfig
deny call org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig ApplyConfiguration
deny call org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power SetBacklight 50
deny call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend true
deny call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.HybridSleep true
deny call org.freedesktop.systemd1 /org/freedesktop/systemd1 StopUnit ssh.service replace
deny call org.freedesktop.systemd1 /org/freedesktop/systemd1 RestartUnit tailscaled.service replace
deny call org.gnome.Shell /org/gnome/Shell org.gnome.Shell.Eval 1+1
deny call org.gnome.SessionManager /org/gnome/SessionManager org.gnome.SessionManager.Logout 0
deny call org.gnome.ScreenSaver /org/gnome/ScreenSaver SetActive true
if command -v strace >/dev/null; then
  strace -f -e trace=connect -o "$WORK/st" "$PC" call org.gnome.Mutter.DisplayConfig \
    /org/gnome/Mutter/DisplayConfig ApplyMonitorsConfig --apply >/dev/null 2>&1
  is 'a denied call opens no socket' "$(grep -c 'connect(' "$WORK/st")" 0
fi

# 5. live, read-only. Skipped when this shell has no session bus (a systemd/cron agent).
if busctl --user list --no-pager >/dev/null 2>&1; then
  is 'live list --user has org.gnome.Shell' \
    "$("$PC" list --json | jq -r '[.names[].name] | index("org.gnome.Shell") != null')" true
  is 'live get reads ShellVersion' \
    "$("$PC" get org.gnome.Shell /org/gnome/Shell org.gnome.Shell.ShellVersion --json | jq -r .data)" 50.1
  is 'live get reads the shell mode' \
    "$("$PC" get org.gnome.Shell /org/gnome/Shell org.gnome.Shell.Mode --json | jq -r .data)" ubuntu
  # window-calls List returns a JSON string; at night the list is legitimately empty.
  w=$("$PC" call org.gnome.Shell /org/gnome/Shell/Extensions/Windows List --json)
  is 'live window-calls List returns a JSON array' "$(jq -r '.data[0] | fromjson | type' <<<"$w")" array
  is 'live call passes an argument' \
    "$("$PC" call org.gnome.Shell /org/gnome/Shell GetExtensionInfo ding@rastersoft.com --json | jq -r '.data[0] | has("uuid")')" true
  XDG_RUNTIME_DIR="$WORK" "$PC" find Idletime | grep -q 'org.gnome.Mutter.IdleMonitor' \
    && ok 'live find lists the IdleMonitor path' || nok 'live find lists the IdleMonitor path' 'no match'
  is 'live find --json has the match keys' \
    "$(XDG_RUNTIME_DIR="$WORK" "$PC" find Idletime --json | jq -r '.matches[0] | has("bus") and has("path") and has("member")')" true
  XDG_RUNTIME_DIR="$WORK" "$PC" find zzz-no-such-member-zzz >/dev/null 2>&1
  is 'find exits 1 when nothing matches' "$?" 1
  t0=$(date +%s)
  "$PC" monitor --match "sender='org.gnome.Shell'" --seconds 1 --json >"$WORK/mon" 2>&1
  is 'monitor exits 0 on its timeout' "$?" 0
  [ $(( $(date +%s) - t0 )) -le 3 ] && ok 'monitor stops inside its window' || nok 'monitor stops inside its window' 'over 3 s'
  pgrep -x busctl >/dev/null && nok 'monitor leaves no busctl behind' "$(pgrep -x busctl | tr '\n' ' ')" \
    || ok 'monitor leaves no busctl behind'
  "$PC" monitor --seconds 999 >/dev/null 2>&1; is 'monitor caps --seconds at 120' "$?" 2

  # 6. the one mutation: OverviewActive set to the value it already has, then rolled back.
  before=$("$PC" get org.gnome.Shell /org/gnome/Shell org.gnome.Shell.OverviewActive)
  out=$(PC_LEDGER="$WORK/changes.jsonl" "$PC" set org.gnome.Shell /org/gnome/Shell \
        org.gnome.Shell.OverviewActive "$before" --apply)
  id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
  [ -n "$id" ] && ok 'set --apply prints the rollback line' || nok 'set --apply prints the rollback line' "$out"
  is 'the ledger verified the write' "$(PC_LEDGER="$WORK/changes.jsonl" "$BIN/pc-undo" show "$id" --json | jq -r .verified)" true
  PC_LEDGER="$WORK/changes.jsonl" "$BIN/pc-undo" --last --apply >/dev/null 2>&1
  is 'undo restores the property' "$("$PC" get org.gnome.Shell /org/gnome/Shell org.gnome.Shell.OverviewActive)" "$before"
else
  ok 'live checks skipped (no session bus in this shell)'
fi

[ $bad = 0 ] && echo 'PASS pc-dbus' || echo 'FAIL pc-dbus'
exit $bad
