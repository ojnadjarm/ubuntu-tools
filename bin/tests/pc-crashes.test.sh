#!/usr/bin/env bash
# pc-crashes against a temp PC_CRASH_DIR, apport ignore file, backup dir, ledger and stubbed systemctl/sudo/journalctl: list, json, ignored-by-apport, dry run, archive, undo; /var/crash untouched.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

real_sum() { ls -la /var/crash 2>/dev/null | md5sum; md5sum "$HOME/agents/log/changes.jsonl" 2>/dev/null; }
before=$(real_sum)

C="$WORK/crash"; mkdir -p "$C" "$WORK/fx/bin" "$WORK/path"
export PC_APPORT_IGNORE="$WORK/none.xml" PC_CRASH_DIR="$C" PC_CRASH_BACKUP="$WORK/backup" PC_LEDGER="$WORK/changes.jsonl" PC_FIXTURE="$WORK/fx"
for s in systemctl sudo; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$s" "$WORK" >"$WORK/fx/bin/$s"; chmod +x "$WORK/fx/bin/$s"
done
cp "$WORK/fx/bin/sudo" "$WORK/path/sudo"; export PATH="$WORK/path:$PATH"
[ "$(command -v sudo)" = "$WORK/path/sudo" ] && ok 'sandbox: sudo is a stub' || nok sandbox "real sudo on PATH"

printf 'ProblemType: Crash\nExecutablePath: /usr/bin/timeout\nProcCmdline: timeout 60 qrenderdoc --python x.py\nSignal: 4\nSignalName: SIGILL\nCoreDump: base64\n eJzt\n' >"$C/_usr_bin_timeout.1000.crash"
: >"$C/_usr_bin_timeout.1000.upload"
printf 'ProblemType: Crash\nExecutablePath: /usr/libexec/ls3\nProcCmdline: /usr/libexec/ls3\nSignal: 11\n' >"$C/_usr_libexec_ls3.1000.crash"
: >"$C/_usr_libexec_ls3.1000.upload"; echo 1 >"$C/_usr_libexec_ls3.1000.uploaded"
touch -d '-3 hours' "$C/_usr_bin_timeout.1000.crash"

pc() { "$BIN/pc-crashes" "$@"; }
j=$(pc --json)
is 'json is an array of 2' "$(jq length <<<"$j")" 2
is 'fields from the queued crash' "$(jq -r '.[] | select(.name == "_usr_bin_timeout.1000") | [.exe, .signal, .signame, .cmdline, .upload, (.age_s >= 10800)] | join("|")' <<<"$j")" \
  '/usr/bin/timeout|4|SIGILL|timeout 60 qrenderdoc --python x.py|queued|true'
is 'signame falls back to kill -l, upload state uploaded' "$(jq -r '.[] | select(.name == "_usr_libexec_ls3.1000") | .signame + "|" + .upload' <<<"$j")" 'SIGSEGV|uploaded'
is 'text list has 2 rows' "$(pc | wc -l)" 2

printf '<?xml version="1.0" ?>\n<apport>\n  <ignore program="/usr/libexec/localsearch-3" mtime="1779187181"/>\n</apport>\n' >"$WORK/ign.xml"
printf '#!/bin/sh\nprintf "%%s\\n" "kernel: traps: localsearch-3[11] general protection fault ip:1" "kernel: localsearch-3[12]: segfault at 0 ip 1" "kernel: traps: localsearch[13] general protection fault"\n' >"$WORK/fx/bin/journalctl"
chmod +x "$WORK/fx/bin/journalctl"
ig=$(PC_APPORT_IGNORE="$WORK/ign.xml" pc --json)
is 'ignored program is one more json row' "$(jq length <<<"$ig")" 3
is 'ignored row: exe, upload, 24 h kernel traps' "$(jq -r '.[] | select(.upload == "ignored-by-apport") | [.name, .exe, .traps_24h] | join("|")' <<<"$ig")" \
  'localsearch-3|/usr/libexec/localsearch-3|2'
is 'text list shows the ignored-by-apport note' "$(PC_APPORT_IGNORE="$WORK/ign.xml" pc | grep -c 'ignored-by-apport *2 kernel traps')" 1

is 'dry run prints would:' "$(pc archive _usr_bin_timeout.1000.crash)" 'would: crash:_usr_bin_timeout.1000 present → archived'
[ -e "$C/_usr_bin_timeout.1000.crash" ] && [ ! -e "$PC_LEDGER" ] && ok 'dry run changes nothing' || nok 'dry run' 'files moved or ledger written'

out=$(pc archive _usr_bin_timeout.1000 --apply)
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
[ -n "$id" ] && ok 'apply prints a rollback line' || nok 'rollback line' "$out"
is 'set left the crash dir' "$(ls "$C" | grep -c _usr_bin_timeout)" 0
is 'set is in the backup dir' "$(ls "$PC_CRASH_BACKUP"/*-_usr_bin_timeout.1000/ | tr '\n' ' ')" '_usr_bin_timeout.1000.crash _usr_bin_timeout.1000.upload '
is 'apport unit reset through the stub' "$(cat "$WORK/calls")" 'systemctl reset-failed apport-autoreport.service'
is 'ledger entry is verified' "$(jq -rs --arg id "$id" '[.[] | select(.id == $id and has("verified"))][0].verified' "$PC_LEDGER")" true
is 'list now has 1' "$(pc --json | jq length)" 1

"$BIN/pc-undo" "$id" --apply >/dev/null
is 'undo restores the set' "$(ls "$C" | grep -c _usr_bin_timeout)" 2
is 'undo removes the empty backup dir' "$(ls "$PC_CRASH_BACKUP" | wc -l)" 0

pc archive nosuch --apply >/dev/null 2>&1; is 'unknown name exits 1' $? 1
pc archive >/dev/null 2>&1; is 'missing name exits 2' $? 2
is 'real /var/crash and ledger untouched' "$(real_sum)" "$before"
exit $bad
