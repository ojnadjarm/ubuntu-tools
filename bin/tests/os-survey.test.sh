#!/usr/bin/env bash
# Fixtures for ~/agents/bin/os-survey: every section prints from stub commands (OS_SURVEY_BIN), Vass rows tagged,
# probe timeout kills grandchildren, missing command fails soft, zero-match apparmor, test-helper noise dropped,
# rg batches, footer counts probe n/a rows, --quick subset, usage exit 2; daemons/netdata/io from a fake /proc and
# cgroup tree (OS_SURVEY_PROC, OS_SURVEY_CGROUP) incl. bwrap/node args naming mcp, walk deadline, sudo and
# journal-sources from stub journalctl; five mutations go red.
set -uo pipefail
SRC="$HOME/agents/bin/os-survey"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

S="$WORK/bin"; mkdir -p "$S" "$WORK/aw/T9/out" "$WORK/ag/log/fleet-ci" "$WORK/proj/p" "$WORK/cache/big"
for c in pc agents-log systemd-analyze df journalctl rg du curl; do
  printf '#!/bin/sh\necho "stub %s $*" 42\n' "$c" >"$S/$c"; chmod +x "$S/$c"
done
cat >"$S/pc" <<'EOF'
#!/bin/sh
case "$*" in
  "status") printf '  ci_verdict       2 red                [WARN]\n  failed_units     0                    [OK]\n';;
  "docker stats"*) printf 'NAME CPU%%\nvass-services-mongo-1 1.2%%\nmoodle52-app-1 0.0%%\n';;
  *) echo "stub pc $* 42";;
esac
EOF
cat >"$S/journalctl" <<'EOF'
#!/bin/sh
case "$*" in
  *SYSLOG_IDENTIFIER=sudo*) printf 'pam_unix(sudo:session): session opened\nu :  PWD=/ ; USER=root ; COMMAND=/usr/sbin/smartctl -a /dev/nvme0\nu : PWD=/ ; USER=root ; COMMAND=/usr/sbin/smartctl -H\nu : PWD=/ ; USER=root ; COMMAND=/usr/bin/tee /x\n';;
  *--user*) printf '{"SYSLOG_IDENTIFIER":"npm"}\n{"SYSLOG_IDENTIFIER":"npm"}\n{"_COMM":"systemd"}\n';;
  *"-o json"*) printf '{"SYSLOG_IDENTIFIER":"kernel","MESSAGE":"[UFW BLOCK] x"}\n{"SYSLOG_IDENTIFIER":"kernel"}\n{"_SYSTEMD_UNIT":"init.scope"}\n';;
  *) [ -n "${NOMATCH:-}" ] && exit 1; printf 'apparmor="DENIED" profile="who"\napparmor="DENIED" profile="who"\n';;
esac
EOF
ln -sf "$(command -v rg)" "$S/rg"
cat >"$S/curl" <<'EOF'
#!/bin/sh
echo '{"charts":{"a":{"plugin":"apps.plugin"},"b":{"plugin":"apps.plugin"},"c":{"plugin":"proc"}}}'
EOF
chmod +x "$S/pc" "$S/journalctl" "$S/curl"
P="$WORK/proc" C="$WORK/cg" HZ=$(getconf CLK_TCK)
proc() {  # <pid> <comm> <cmdline with spaces> <rss kB> <inotify watches>
  mkdir -p "$P/$1/fd" "$P/$1/fdinfo"; echo "$2" >"$P/$1/comm"; printf '%s' "$3" | tr ' ' '\0' >"$P/$1/cmdline"
  printf 'Name:\t%s\nVmRSS:\t   %s kB\n' "$2" "$4" >"$P/$1/status"
  if [ "$5" -gt 0 ]; then ln -s anon_inode:inotify "$P/$1/fd/3"; for i in $(seq "$5"); do echo "inotify wd:$i ino:1 sdev:0" >>"$P/$1/fdinfo/3"; done; fi
  ln -s /dev/null "$P/$1/fd/1"
}
proc 100 watchman 'watchman -j' 51200 3; proc 101 watchman 'watchman -j' 10240 2
proc 200 MainThread 'node /x/bin/playwright-mcp --headless' 102400 0; proc 300 node '/usr/bin/node /x/mcp-server.js' 20480 0
proc 400 claude '/x/claude --mcp-config f' 9000 0; proc 500 netdata '/usr/sbin/netdata -D' 1000 0
proc 600 bwrap '/usr/bin/bwrap --ro-bind /dev/null /h/.claude/playwright-mcp.json /bin/sh' 4000 0
proc 700 node '/usr/bin/node /x/app.js --config /x/mcp.json' 4000 0
echo '3600.00 100.00' >"$P/uptime"
task() { mkdir -p "$P/500/task/$1"; echo "$1 ($2) S 1 500 500 0 -1 0 0 0 0 0 $3 $4 0 0 20 0 1 0 0 1 1" >"$P/500/task/$1/stat"; }
task 500 netdata "$HZ" 0; task 501 'P[cglk upipc]' $((3*HZ)) $((2*HZ))
mkdir -p "$C/system.slice/netdata.service" "$C/system.slice/docker-x.scope" "$C/user.slice"
echo 500 >"$C/system.slice/netdata.service/cgroup.procs"; echo 'usage_usec 1000000' >"$C/system.slice/netdata.service/cpu.stat"
io() { echo "259:0 rbytes=9 wbytes=$2 rios=1 wios=1 dbytes=0 dios=0" >>"$C/$1/io.stat"; }
io . 99000000000; io system.slice 5000000000; io system.slice/netdata.service 1000000000
io system.slice/docker-x.scope 500000000; io system.slice/docker-x.scope 500000000; io user.slice 2000000000
head -c 3000000 /dev/zero >"$WORK/aw/T9/out/big.bin"
echo 'FAIL 300/316 files after a serial re-run' >"$WORK/ag/log/fleet-ci/2026-10-21.txt"
tu() { printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":"%s"}}]}}\n' "$1" "$2" "$3"; }
tr_() { printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"%s"}]}}\n' "$1" "$2" "$3"; }
{ tu 2026-10-18T10:00:00Z u1 'sysctl -a'; tr_ 2026-10-18T10:00:01Z u1 'Exit code 127\n/bin/bash: line 1: sysctl: command not found'
  tr_ 2026-10-20T09:00:00Z u2 'bash: sysctl: command not found\nbash: sysctl: command not found'
  tr_ 2026-10-19T09:00:00Z u3 'x\nbash: line 3: iw: command not found'
  tu 2026-10-19T09:00:00Z u4 "rg 'bash: claims: command not found' ~/.claude"; tr_ 2026-10-19T09:00:01Z u4 'bash: claims: command not found'
  tr_ 2026-10-19T09:01:00Z u5 '22:27:09  fd9  Bash  claims add  /bin/bash: line 1: claims: command not found'
  tr_ 2026-10-19T09:02:00Z u6 'ok: command not found\nbash: line 9: ok: command not found'
  tr_ 2026-10-18T09:00:00Z u7 'bash: claims: command not found'; tr_ "$(date -u -d '+1 day' +%Y-%m-%dT%H:%M:%SZ)" u8 'bash: claims: command not found'
  tr_ 2026-10-20T09:00:00Z u9 'bash: flake8: command not found'
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"bash: gh: command not found"}]}}\n'
} >"$WORK/proj/p/s.jsonl"
mkdir -p "$WORK/path"; printf '#!/bin/sh\n' >"$WORK/path/claims"; chmod +x "$WORK/path/claims"; cp "$WORK/path/claims" "$WORK/path/flake8"; touch -d 2026-01-12T09:57:00Z "$WORK/path/flake8"
export PATH="$WORK/path:$PATH"
mkdir -p "$WORK/ag/bin/tests"; printf 'ok() { :; }\n' >"$WORK/ag/bin/tests/x.test.sh"
export OS_SURVEY_BIN="$S" AGENT_WORK="$WORK/aw" HARNESS_HOME="$WORK/ag" OS_SURVEY_PROJECTS="$WORK/proj" OS_SURVEY_CACHE="$WORK/cache" \
  OS_SURVEY_PROC="$P" OS_SURVEY_CGROUP="$C" OS_SURVEY_NETDATA_WAIT=0.2

SECTIONS="status doctor failures cpu memory timers kernel journal fleet-ci agents-log boot disk network apparmor agent-work docker command-not-found caches daemons netdata sudo journal-sources io"
QUICK="status doctor failures cpu memory timers kernel journal fleet-ci agents-log boot disk network"

out=$("$SRC" 2>&1); ok "full: rc 0" 0 $?
miss=0; for s in $SECTIONS; do grep -qx "## $s" <<<"$out" || { echo "  missing ## $s"; miss=$((miss+1)); }; done
ok "full: every section prints" 0 "$miss"
ok "full: no n/a rows from stubs" 0 "$(grep -c 'n/a' <<<"$out")"
ok "full: Vass row tagged" yes "$(has 'vass-services-mongo-1 1.2% (Vass, owner-only)' "$out")"
ok "full: non-Vass row untagged" no "$(has 'moodle52-app-1 0.0% (Vass' "$out")"
ok "status: only non-OK rows" "yes no" "$(has ci_verdict "$out") $(has failed_units "$out")"
ok "journal: unit and count only" "yes no" "$(has 'kernel 2' "$out") $(has 'UFW BLOCK' "$out")"
ok "apparmor: DENIED by profile" "yes yes" "$(has 'DENIED 24h: 2' "$out") $(has 'who 2' "$out")"
cnf=$(sed -n '/^## command-not-found/,/^## /p' <<<"$out")
ok "command-not-found: one per tool_use id, dates, test noise dropped" "yes yes no yes" "$(has 'sysctl 2 10-18..10-20' "$cnf") $(has 'iw 1 10-19..10-19' "$cnf") $(has '  ok ' "$cnf") $(has 'test helpers dropped 1' "$cnf")"
ok "command-not-found: input quoting, mid-line quote, plain text skipped" "no no" "$(has 'claims 3' "$cnf") $(has 'gh' "$cnf")"
today=$(date -u +%Y-%m-%d) tomorrow=$(date -u -d '+1 day' +%m-%d)
ok "command-not-found: on PATH now splits at install (ctime)" yes "$(has "claims 1 10-18..$tomorrow (on PATH now since $today " "$cnf")"
ok "command-not-found: old package mtime, recent install: all before" yes "$(has "flake8 0 10-20..10-20 (on PATH now since $today " "$cnf")"
ok "command-not-found: header totals" yes "$(has 'transcripts 7 d: 1 files, 4 hits (one per call), 2 before PATH install' "$cnf")"
ok "agent-work: writer dir with MB" yes "$(has 'T9/out' "$out")"
ok "fleet-ci: verdict line" yes "$(has 'FAIL 300/316' "$out")"
ok "footer: all clean" yes "$(has '--- 23/23 sections' "$out")"
ok "kernel: dmesg digest over --since" yes "$(has 'stub pc kernel dmesg --digest --since -24h' "$out")"
ok "daemons: count, RSS, inotify per kind" "yes yes yes no" "$(has 'watchman n 2, RSS 60 MB, inotify watches 5' "$out") $(has 'playwright-mcp n 1, RSS 100 MB' "$out") $(has 'node-mcp n 1, RSS 20 MB' "$out") $(has 'n 2, RSS 29' "$out")"
ok "netdata: threads s/h, charts per plugin" "yes yes yes" "$(has 'netdata/P[cglk upipc] 5.00 s/h' "$out") $(has 'netdata 1.00 s/h' "$out") $(has 'charts 3: apps.plugin 2, proc 1' "$out")"
ok "sudo: COMMAND counts by tool" "yes yes yes" "$(has 'COMMAND 24h: 3' "$out") $(has 'smartctl 2' "$out") $(has 'tee 1' "$out")"
ok "journal-sources: user + system by identifier" "yes yes yes" "$(has 'lines 1h: user 3, system 3' "$out") $(has 'npm 2 (user 2, system 0)' "$out") $(has 'kernel 2 (user 0, system 2)' "$out")"
ok "io: total, gone, leaves" "yes yes yes" "$(has 'written since boot 7.0 GB, gone cgroups 3.0 GB' "$out") $(has 'user.slice 2.0 GB' "$out") $(has 'system.slice/docker-x.scope 1.0 GB' "$out")"
f="$C/system.slice/netdata.service/cpu.stat"
( t0=$(date +%s%N); while [ -e "$f" ]; do echo "usage_usec $(( 1000000 + ($(date +%s%N) - t0) / 10000 ))" >"$f.n" && mv "$f.n" "$f"; sleep 0.05; done ) &
wp=$!; out=$(OS_SURVEY_NETDATA_WAIT=1 "$SRC" 2>&1); kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
sh=$(grep -oE 'cpu 1 s: [0-9]+ ms = [0-9.]+ s/h' <<<"$out" | awk '{print int($7)}')
ok "netdata: cgroup cpu over the wait, as s/h (~360)" yes "$([ "${sh:-0}" -ge 300 ] && [ "$sh" -le 420 ] && echo yes || echo no)"
echo 'usage_usec 1000000' >"$f"
out=$(OS_SURVEY_TIMEOUT=0 "$SRC" 2>&1)
ok "daemons + io: walk keeps the deadline" "yes yes" "$(has 'watches 0 (partial: timeout 0 s)' "$out") $(has 'gone cgroups 0.0 GB (partial: timeout 0 s)' "$out")"
mv "$P/100" "$P/100x"; mkdir "$P/100"; out=$("$SRC" 2>&1); rm -rf "$P/100"; mv "$P/100x" "$P/100"
ok "daemons: vanished pid fails soft" yes "$(has 'watchman n 1, RSS 10 MB, inotify watches 2' "$out")"
out=$(NOMATCH=1 "$SRC" 2>&1); ok "apparmor: zero matches is a count" "yes no" "$(has 'DENIED 24h: 0' "$out") $(has 'rc 1' "$out")"
mkdir -p "$WORK/many"; for i in $(seq 1001); do tr_ 2026-10-20T00:00:00Z "m$i" 'bash: iw: command not found' >"$WORK/many/$i.jsonl"; done
ok "command-not-found: rg runs in batches" yes "$(has 'iw 1001 ' "$(OS_SURVEY_PROJECTS="$WORK/many" "$SRC" 2>&1)")"

q=$("$SRC" --quick 2>&1)
ok "quick: section count" "$(wc -w <<<"$QUICK")" "$(grep -c '^## ' <<<"$q")"
ok "quick: no full-only section" 0 "$(grep -cE '^## (apparmor|agent-work|docker|command-not-found|caches)$' <<<"$q")"

printf '#!/bin/sh\nsleep 7.123 | cat\n' >"$S/systemd-analyze"
t0=$(date +%s); out=$(OS_SURVEY_TIMEOUT=1 "$SRC" --quick 2>&1); dt=$(( $(date +%s) - t0 ))
ok "timeout: row says so" yes "$(has 'n/a: timeout 1 s' "$out")"
ok "timeout: run ends in < 5 s" yes "$([ "$dt" -lt 5 ] && echo yes || echo no)"
ok "timeout: grandchild killed" 0 "$(ps -eo args | grep -cx 'sleep 7.123')"
rm "$S/systemd-analyze"
out=$("$SRC" --quick 2>&1); ok "missing command: rc 0" 0 $?
ok "missing command: n/a row" yes "$(has 'n/a: systemd-analyze not found' "$out")"
ok "footer: probe n/a row counts" yes "$(has '--- 12/13 sections' "$out")"

"$SRC" --since 3x >/dev/null 2>&1; ok "bad --since: rc 2" 2 $?
ok "no browser in the source" 0 "$(grep -iE 'chrom|firefox|playwright' "$SRC" | grep -vc '^DAEMONS = ')"

# Mutations: without the tag, the inotify count, the anchored regex, the gone remainder, the quoting skip, the line anchor, the install ctime, the per-call dedupe or the timeout the matching check goes red.
M="$WORK/mut"; sed 's/(Vass, owner-only)/(x)/' "$SRC" >"$M"; chmod +x "$M"
printf '#!/bin/sh\necho "stub $*"\n' >"$S/systemd-analyze"; chmod +x "$S/systemd-analyze"
ok "mutation: no Vass tag goes red" no "$(has '(Vass, owner-only)' "$("$M" 2>&1)")"
sed 's/startswith(.inotify.)/startswith("x")/' "$SRC" >"$M"; chmod +x "$M"
ok "mutation: no inotify count goes red" no "$(has 'inotify watches 5' "$("$M" 2>&1)")"
sed "s|('playwright-mcp', r'[^']*')|('playwright-mcp', r'playwright-mcp')|" "$SRC" >"$M"; chmod +x "$M"
ok "mutation: unanchored playwright-mcp goes red" no "$(has 'playwright-mcp n 1,' "$("$M" 2>&1)")"
sed 's/max(0, own - kids\[c\])/0/' "$SRC" >"$M"; chmod +x "$M"
ok "mutation: no gone remainder goes red" no "$(has 'gone cgroups 3.0 GB' "$("$M" 2>&1)")"
sed 's/if u in quoted:/if False:/' "$SRC" >"$M"; chmod +x "$M"
ok "mutation: counting quoting calls goes red" yes "$(has 'UTC, 2 before)' "$("$M" 2>&1)")"
sed 's/^CNF = re.compile(r.\^/CNF = re.compile(r\x27/' "$SRC" >"$M"; chmod +x "$M"
ok "mutation: unanchored match goes red" yes "$(has 'UTC, 2 before)' "$("$M" 2>&1)")"
sed 's/os.lstat(path).st_ctime/os.lstat(path).st_mtime/' "$SRC" >"$M"; chmod +x "$M"
ok "mutation: package mtime as install time goes red" yes "$(has 'flake8 1 ' "$("$M" 2>&1)")"
sed 's/hits = set()/hits = []/; s/hits.add(/hits.append(/' "$SRC" >"$M"; chmod +x "$M"
ok "mutation: no per-call dedupe goes red" no "$(has 'sysctl 2 ' "$("$M" 2>&1)")"
sed 's/timeout=TIMEOUT/timeout=None/' "$SRC" >"$M"; chmod +x "$M"
printf '#!/bin/sh\nsleep 3\n' >"$S/systemd-analyze"
ok "mutation: no timeout goes red" no "$(has 'n/a: timeout' "$(OS_SURVEY_TIMEOUT=1 "$M" --quick 2>&1)")"

echo "$bad failed"
[ "$bad" = 0 ]
