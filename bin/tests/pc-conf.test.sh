#!/usr/bin/env bash
# pc-conf in a mktemp PC_CONF_ROOT with stub sudo/systemctl/etckeeper and a temp ledger: dry run, write → undo byte-identical, absent → undo removes, reloads, deny rules; real /etc and ledger untouched.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

real_sum() { ls -la /etc/sysctl.d /etc/systemd/journald.conf.d /etc/NetworkManager/conf.d /etc/avahi 2>/dev/null | md5sum; md5sum "$HOME/agents/log/changes.jsonl" 2>/dev/null; }
before=$(real_sum)

R="$WORK/root"; mkdir -p "$R" "$WORK/path"
export PC_CONF_ROOT="$R" PC_CONF_BACKUP="$WORK/backup" PC_LEDGER="$WORK/changes.jsonl"
printf '#!/bin/sh\necho "sudo $*" >>"%s/calls"\n[ "$1" = -n ] && shift\nexec "$@"\n' "$WORK" >"$WORK/path/sudo"
for s in systemctl etckeeper apparmor_parser nmcli; do printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$s" "$WORK" >"$WORK/path/$s"; done
K=/lib/modules/k/kernel
printf '#!/bin/sh\ncase $3 in\n iwlwifi) echo %s/drivers/net/wireless/iwlwifi.ko;; cfg80211) echo %s/net/wireless/cfg80211.ko;;\n nvme) echo %s/drivers/nvme/host/nvme.ko;; usbhid) echo %s/drivers/hid/usbhid/usbhid.ko;;\n ahci) echo %s/drivers/ata/ahci.ko;; pcspkr) echo %s/drivers/input/misc/pcspkr.ko;; btrfs) echo %s/fs/btrfs/btrfs.ko;;\n snd-hda-intel) echo %s/sound/hda/snd-hda-intel.ko;; *) exit 1;;\nesac\n' $K $K $K $K $K $K $K $K >"$WORK/path/modinfo"
chmod +x "$WORK"/path/*; export PATH="$WORK/path:$PATH"
[ "$(command -v sudo)" = "$WORK/path/sudo" ] && [ "$(command -v systemctl)" = "$WORK/path/systemctl" ] \
  && [ "$(command -v modinfo)" = "$WORK/path/modinfo" ] && ok 'sandbox: sudo, systemctl and modinfo are stubs' || { nok sandbox 'real sudo/systemctl on PATH'; exit 1; }

pc() { "$BIN/pc-conf" "$@"; }
calls() { cat "$WORK/calls" 2>/dev/null; : >"$WORK/calls"; }
F=/etc/sysctl.d/99-test.conf

out=$(pc put $F --line 'vm.swappiness=10')
is 'dry run first line' "$(head -1 <<<"$out")" "would: $F absent → sha:$(printf 'vm.swappiness=10\n' | sha256sum | cut -c1-12) (+1 -0)"
ev 'dry run shows the diff' 'grep -qx "+vm.swappiness=10" <<<"$out"'
[ ! -e "$R$F" ] && [ ! -e "$PC_LEDGER" ] && [ ! -e "$PC_CONF_BACKUP" ] && ok 'dry run writes nothing' || nok 'dry run' 'file, ledger or backup written'

# absent file → apply → undo removes it
out=$(pc put $F --line 'vm.swappiness=10' --line 'vm.dirty_ratio=5' --apply)
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
[ -n "$id" ] && ok 'apply prints a rollback line' || nok 'rollback line' "$out"
is 'file written' "$(cat "$R$F")" $'vm.swappiness=10\nvm.dirty_ratio=5'
is 'new file mode 644' "$(stat -c %a "$R$F")" 644
is 'write ran through sudo and etckeeper' "$(calls | grep -c -e '^sudo -n install' -e '^etckeeper commit pc conf: /etc/sysctl.d/99-test.conf')" 2
is 'ledger entry verified' "$(jq -rs --arg id "$id" '[.[] | select(.id == $id and has("verified"))][0].verified' "$PC_LEDGER")" true
ev 'backup marks the absence' '[ -e "$PC_CONF_BACKUP"/*-etc_sysctl.d_99-test.conf.*/absent ]'
is 'get shows the file and its ledger id' "$(pc get $F | tail -1)" "ledger: $id"
"$BIN/pc-undo" "$id" --apply >/dev/null
[ ! -e "$R$F" ] && ok 'undo removes a file that was absent' || nok 'undo absent' 'file still there'

# two puts in the same second: each gets its own backup, so undoing the second restores the first
o1=$(pc put $F --line a=1 --apply); o2=$(pc put $F --line a=2 --apply)
is 'two puts in one second get two backup dirs' "$(compgen -G "$PC_CONF_BACKUP/*-etc_sysctl.d_99-test.conf.*" | wc -l)" 3
"$BIN/pc-undo" "$(sed -n 's/^rollback: pc undo //p' <<<"$o2")" --apply >/dev/null
is 'undo of the second put restores the first' "$(cat "$R$F" 2>/dev/null)" a=1
"$BIN/pc-undo" "$(sed -n 's/^rollback: pc undo //p' <<<"$o1")" --apply >/dev/null

# existing file → apply with --from → undo restores byte-identical, mode kept
J=/etc/systemd/journald.conf.d/90-agents.conf
mkdir -p "$R${J%/*}"; printf '[Journal]\nSystemMaxUse=200M\n# no newline at end' >"$R$J"; chmod 600 "$R$J"
orig=$(md5sum <"$R$J")
printf '[Journal]\nSystemMaxUse=600M\nSystemKeepFree=20G\n' >"$WORK/new.conf"
out=$(pc put $J --from "$WORK/new.conf" --reload systemd-journald)
is 'dry run counts the diff' "$(head -1 <<<"$out" | grep -o '(+[0-9]* -[0-9]*)')" '(+2 -2)'
calls >/dev/null
out=$(pc put $J --from "$WORK/new.conf" --reload systemd-journald --apply)
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'replaced content' "$(md5sum <"$R$J")" "$(md5sum <"$WORK/new.conf")"
is 'existing mode kept' "$(stat -c %a "$R$J")" 600
ev 'reload ran as root' 'calls | grep -qx "systemctl reload-or-restart systemd-journald"'
"$BIN/pc-undo" "$id" --apply >/dev/null
is 'undo restores byte-identical' "$(md5sum <"$R$J")" "$orig"
ev 'undo reloads again' 'calls | grep -qx "systemctl reload-or-restart systemd-journald"'
is 'same content again is a no-op' "$(pc put $J --from <(cat "$R$J") --apply | cut -d' ' -f1)" 'unchanged:'

# user drop-in: no sudo, systemctl --user daemon-reload
U="$HOME/.config/systemd/user/fleet.slice.d/50-test.conf"
pc put "$U" --line '[Slice]' --line 'CPUWeight=50' --daemon-reload --apply >/dev/null
is 'user drop-in written under the root' "$(cat "$R$U" | tail -1)" 'CPUWeight=50'
c=$(calls); is 'user write: no sudo, user daemon-reload' "$(grep -c '^sudo' <<<"$c")|$(grep -c '^systemctl --user daemon-reload' <<<"$c")" '0|1'
[ ! -e "$U" ] && ok 'real ~/.config untouched' || nok 'real home' "$U exists"

# deny rules: rc 2, "refused:", nothing written
n=0
for p in /etc/ssh/sshd_config.d/zz.conf /etc/ufw/user.rules /etc/default/ufw /etc/sudoers.d/x /etc/sudoers \
  "$HOME/.claude/settings.json" /etc/systemd/system/ssh.service.d/x.conf /etc/systemd/system/sshd.socket.d/x.conf \
  /etc/systemd/system/tailscaled.service.d/x.conf /etc/systemd/system/docker.service.d/x.conf \
  /etc/systemd/system/containerd.service.d/x.conf /etc/systemd/system/dark-eye.service.d/x.conf \
  "$HOME/.config/systemd/user/dark-eye-failed.service.d/x.conf" "$HOME/.config/systemd/user/sentinel-runaway.timer.d/x.conf" \
  "$HOME/.config/systemd/user/agent@.service.d/x.conf" "$HOME/.config/systemd/user/claude-orchestrator.service.d/x.conf" \
  /etc/passwd /etc/systemd/system/foo.service /etc/sysctl.d/x.txt /etc/systemd/system/a/b.service.d/x.conf \
  "$HOME/.config/systemd/user/agent@x.timer" "$HOME/.config/systemd/user/dark-eye.service" \
  "$HOME/.config/systemd/user/a/b.timer" "$HOME/.config/systemd/user/x.socket" \
  /etc/sysctl.d/../sudoers etc/sysctl.d/x.conf /etc/systemd/system/service.d/x.conf /etc/systemd/system/socket.d/x.conf \
  /etc/systemd/system/dark-.service.d/x.conf "$HOME/.config/systemd/user/dark-.service.d/x.conf" \
  "$HOME/.config/systemd/user/claude-.service.d/x.conf" /etc/systemd/system/sshd-keygen@.service.d/x.conf \
  /etc/systemd/system/docker-.socket.d/x.conf "$HOME/.config/systemd/user/service.d/x.conf" \
  /etc/fwupd/fwupd.conf /etc/fwupd/remotes.d/lvfs.conf /var/lib/fwupd/remotes.d/x.conf \
  /var/lib/fwupd/remotes.d/../fwupd.conf /var/lib/fwupd/remotes.d/lvfs.conf/x \
  /etc/modprobe.d/blacklist.conf /etc/modprobe.d/90-agents-x.txt /etc/modprobe.d/a/90-agents-x.conf /etc/modprobe.d/90-agents-x.conf/y.conf \
  /etc/NetworkManager/conf.d/x.conf /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d/a/zz-agents-x.conf \
  /etc/NetworkManager/conf.d/zz-agents-x.txt /etc/NetworkManager/system-connections/zz-agents-x.conf; do
  o=$(pc put "$p" --line 'X=1' --apply 2>&1); rc=$?
  { [ $rc = 2 ] && grep -q '^refused: ' <<<"$o"; } || { nok "deny $p" "rc=$rc $o"; n=1; }
done
[ $n = 0 ] && ok 'every deny path refused with rc 2'
is 'refusals name their rule' "$(pc put /etc/ssh/sshd_config.d/zz.conf --line a 2>&1)|$(pc put /etc/sudoers.d/x --line a 2>&1)|$(pc put /etc/default/ufw --line a 2>&1)" \
  'refused: ssh/sshd|refused: sudoers|refused: ufw'
for u in tailscaled ssh.service docker sentinel-runaway agent@x claude-orchestrator dark-eye; do
  o=$(pc put /etc/sysctl.d/99-x.conf --line a --reload "$u" --apply 2>&1); rc=$?
  { [ $rc = 2 ] && grep -q '^refused: ' <<<"$o"; } || { nok "deny reload $u" "rc=$rc $o"; n=1; }
done
[ $n = 0 ] && ok 'every guarded reload unit refused'
ln -s /etc/hostname "$R/etc/sysctl.d/98-link.conf"
o=$(pc put /etc/sysctl.d/98-link.conf --line a --apply 2>&1); is 'symlink target refused' "$?|${o%%:*}" '2|refused'
ok_paths=(/etc/systemd/system/foo-.service.d/x.conf /etc/systemd/system/user@.service.d/x.conf /etc/systemd/oomd.conf.d/x.conf /etc/tmpfiles.d/x.conf /etc/netdata/go.d/logind.conf /etc/default/grub.d/x.cfg "$HOME/.config/systemd/user/pc-x.timer" /var/lib/fwupd/remotes.d/lvfs.conf /etc/modprobe.d/90-agents-x.conf)
for p in "${ok_paths[@]}"; do pc put "$p" --line a | grep -q '^would:' || { nok "allow $p" 'not a would: line'; n=1; }; done
[ $n = 0 ] && ok 'allowed roots dry-run'
pc put /etc/sysctl.d/x.conf >/dev/null 2>&1; is 'no content exits 2' $? 2

# apparmor local overrides: reparse the profile on write and undo; the profile itself and guarded names refused
mkdir -p "$R/etc/apparmor.d/local"; for a in who usr.sbin.sshd bwrap-userns-restrict; do echo "profile $a {}" >"$R/etc/apparmor.d/$a"; done
printf '#!/bin/sh\necho "apparmor_parser $*" >>"%s/calls"\n[ "$1" = -Q ] && grep -rq BAD "$3" && exit 1\nexit 0\n' "$WORK" >"$WORK/path/apparmor_parser"
A=/etc/apparmor.d/local/who; calls >/dev/null
out=$(pc put $A --line '  include <abstractions/nameservice-strict>' --apply)
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'apparmor local written' "$(cat "$R$A" 2>/dev/null)" '  include <abstractions/nameservice-strict>'
c=$(calls)
ev 'apparmor write reparses the profile as root' 'grep -qx "apparmor_parser -r -- $R/etc/apparmor.d/who" <<<"$c"'
ev 'apparmor write checks the profile parses first' 'grep -qx "apparmor_parser -Q -I .* -- $R/etc/apparmor.d/who" <<<"$c"'
"$BIN/pc-undo" "$id" --apply >/dev/null
[ ! -e "$R$A" ] && ok 'apparmor undo removes the override' || nok 'apparmor undo' 'file still there'
ev 'apparmor undo reparses again' 'calls | grep -qx "apparmor_parser -r -- $R/etc/apparmor.d/who"'
for p in /etc/apparmor.d/who /etc/apparmor.d/local/usr.sbin.sshd /etc/apparmor.d/local/bwrap-userns-restrict \
  /etc/apparmor.d/local/nosuch /etc/apparmor.d/local/README /etc/apparmor.d/local/a/who /etc/apparmor.d/abstractions/base; do
  o=$(pc put "$p" --line 'X=1' --apply 2>&1); rc=$?
  { [ $rc = 2 ] && grep -q '^refused: ' <<<"$o"; } || { nok "deny $p" "rc=$rc $o"; n=1; }
done
[ $n = 0 ] && ok 'apparmor profile, guarded, missing and nested paths refused'
o=$(pc put $A --line a --reload foo 2>&1); is 'apparmor path with --reload exits 2' $? 2
n0=$(wc -l <"$PC_LEDGER"); o=$(pc put $A --line BAD --apply 2>&1); rc=$?
is 'apparmor parse error: exit 1, nothing written or ledgered' "$rc|$([ -e "$R$A" ] && echo file)|$(wc -l <"$PC_LEDGER")" "1||$n0"

# modprobe.d: options and harmless blacklists pass; blacklist/install of storage, net, input or unknown modules refused
M=/etc/modprobe.d/90-agents-regdom.conf
out=$(pc put $M --line 'options cfg80211 ieee80211_regdom=XX' --line '# c' --line 'blacklist snd-hda-intel' --apply)
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'modprobe options file written' "$(head -1 "$R$M" 2>/dev/null)" 'options cfg80211 ieee80211_regdom=XX'
"$BIN/pc-undo" "$id" --apply >/dev/null
[ ! -e "$R$M" ] && ok 'modprobe undo removes the file' || nok 'modprobe undo' 'file still there'
for l in 'blacklist iwlwifi' 'blacklist cfg80211' 'install nvme /bin/false' '  blacklist usbhid' 'blacklist ahci' \
  'install pcspkr /bin/true' 'blacklist btrfs' 'blacklist nosuchmod' 'blacklist'; do
  o=$(pc put $M --line 'options cfg80211 ieee80211_regdom=XX' --line "$l" 2>&1); rc=$?
  { [ $rc = 2 ] && grep -q '^refused: ' <<<"$o" && [ ! -e "$R$M" ]; } || { nok "deny modprobe line '$l'" "rc=$rc $o"; n=1; }
done
[ $n = 0 ] && ok 'modprobe blacklist/install of storage, net, input and unknown modules refused'
printf 'options a b=1\nblacklist iwlwifi' >"$WORK/nonl.conf"
o=$(pc put $M --from "$WORK/nonl.conf" 2>&1); is 'last line without newline still checked' "$?|${o%%:*}" '2|refused'

# NetworkManager conf.d: only zz-agents-*.conf, only [keyfile] unmanaged-devices of docker-style names; always `nmcli general reload conf`
N=/etc/NetworkManager/conf.d/zz-agents-unmanaged-docker.conf; calls >/dev/null
out=$(pc put $N --line '# T1117' --line '[keyfile]' --line 'unmanaged-devices+=interface-name:veth*;interface-name:br-*;interface-name:docker0' --apply)
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'nm conf written (+= keeps earlier unmanaged specs)' "$(tail -1 "$R$N" 2>/dev/null)" 'unmanaged-devices+=interface-name:veth*;interface-name:br-*;interface-name:docker0'
ev 'nm write reloads the conf as root' 'calls | grep -qx "sudo -n nmcli general reload conf"'
"$BIN/pc-undo" "$id" --apply >/dev/null
[ ! -e "$R$N" ] && ok 'nm undo removes the file' || nok 'nm undo' 'file still there'
ev 'nm undo reloads again' 'calls | grep -qx "sudo -n nmcli general reload conf"'
for c in '[connection]|wifi.powersave=2' '[keyfile]|unmanaged-devices=*' '[keyfile]|unmanaged-devices=interface-name:wlo1' \
  '[keyfile]|unmanaged-devices=interface-name:veth*;interface-name:tailscale0' '[keyfile]|unmanaged-devices=mac:00:11:22:33:44:55' \
  '[keyfile]|path=/tmp' '[keyfile]|path=interface-name:veth*' '[keyfile]|unmanaged-devices-=interface-name:veth*' '[main]|unmanaged-devices=interface-name:veth*' 'unmanaged-devices=interface-name:veth*' \
  '[keyfile]|unmanaged-devices=interface-name:veth*|[device]|managed=0'; do
  IFS='|' read -ra L <<<"$c"; a=(); for l in "${L[@]}"; do a+=(--line "$l"); done
  o=$(pc put $N "${a[@]}" --apply 2>&1); rc=$?
  { [ $rc = 2 ] && grep -q '^refused: ' <<<"$o" && [ ! -e "$R$N" ]; } || { nok "deny nm content '$c'" "rc=$rc $o"; n=1; }
done
[ $n = 0 ] && ok 'nm keys outside [keyfile] unmanaged-devices and non-docker names refused'
o=$(pc put $N --line '[keyfile]' --line 'unmanaged-devices=interface-name:veth*' --reload foo 2>&1); is 'nm path with --reload exits 2' $? 2

# avahi-daemon.conf: only [server] allow-interfaces=/deny-interfaces= of exact names may change (avahi 0.8 has no globs)
A=/etc/avahi/avahi-daemon.conf; mkdir -p "$R/etc/avahi"
printf '[server]\nuse-ipv4=yes\n#deny-interfaces=eth1\n\n[publish]\npublish-hinfo=no\n' >"$R$A"; av=$(md5sum <"$R$A")
sed '/^use-ipv4/a allow-interfaces=eth0\ndeny-interfaces=docker0,br-1a2b' "$R$A" >"$WORK/av-ok"
out=$(pc put $A --from "$WORK/av-ok" --apply); id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'avahi [server] allow-/deny-interfaces written' "$(sed -n 3,4p "$R$A" 2>/dev/null)" $'allow-interfaces=eth0\ndeny-interfaces=docker0,br-1a2b'
"$BIN/pc-undo" "$id" --apply >/dev/null
is 'avahi undo restores the file' "$(md5sum <"$R$A")" "$av"
n=0
for e in '/^use-ipv4/a deny-interfaces=veth*' '/^use-ipv4/a deny-interfaces=' '/^use-ipv4/a deny-interfaces' \
  '/^publish-hinfo/a allow-interfaces=eth0' 's/^use-ipv4=yes/use-ipv4=no/' '/^use-ipv4/a enable-dbus=no' \
  's/^#deny-interfaces=eth1/#x/' '/^use-ipv4/a allow-interfaces=eth0;rm'; do
  sed "$e" "$R$A" >"$WORK/av-bad"
  o=$(pc put $A --from "$WORK/av-bad" 2>&1); rc=$?
  { [ $rc = 2 ] && grep -q '^refused: avahi' <<<"$o" && [ "$(md5sum <"$R$A")" = "$av" ]; } || { nok "deny avahi edit '$e'" "rc=$rc $o"; n=1; }
done
[ $n = 0 ] && ok 'avahi: globs, empty values, other keys, other sections and comments refused'

mkdir -p "$R/etc"; echo secret >"$R/etc/shadow"
o=$(pc get /etc/shadow 2>&1); is 'get refuses paths outside the roots' "$?|${o%%:*}" '2|refused'
printf 'a=1\n' >"$R/etc/sysctl.d/97-locked.conf"; chmod 000 "$R/etc/sysctl.d/97-locked.conf"
o=$(pc put /etc/sysctl.d/97-locked.conf --line b --apply 2>&1); rc=$?
chmod 644 "$R/etc/sysctl.d/97-locked.conf"
is 'unreadable existing file: exit 1, nothing written' "$rc|$(cat "$R/etc/sysctl.d/97-locked.conf")|$(compgen -G "$PC_CONF_BACKUP/*locked*" | wc -l)" '1|a=1|0'
printf 'a\n+b\n' >"$R/etc/sysctl.d/96-c.conf"
is 'counts blank and +/- lines' "$(pc put /etc/sysctl.d/96-c.conf --line '' --line '-x' --line '+y' | head -1 | grep -o '(+[0-9]* -[0-9]*)')" '(+3 -2)'

is 'real /etc and ledger untouched' "$(real_sum)" "$before"
exit $bad
