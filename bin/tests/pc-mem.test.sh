#!/usr/bin/env bash
# T1048, T1062, T1070, T1089, T1094, T1127: pc mem against a fake cgroupfs + /proc in a mktemp dir; growth against a synthetic mem.tsv. Nothing real is read or written.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
mkdir -p "$WORK/dstub"; printf '#!/bin/sh\necho "$*" >>"$WORK/docker.log"; cat "$WORK/dps" 2>/dev/null\n' >"$WORK/dstub/docker"; chmod +x "$WORK/dstub/docker"
export WORK PATH="$WORK/dstub:$PATH" PC_MEM_NAMES="$WORK/names.tsv"
mem() { PC_SYS="$WORK/sys" PC_PROC="$WORK/proc" PC_MEM_LOG="$WORK/mem.tsv" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-mem" "$@"; }

# cg <path> <mem> <swap> <anon> <pid…> — a cgroup dir with byte counters and its procs.
cg() {
  local d="$WORK/sys/fs/cgroup/$1"; shift
  mkdir -p "$d"; echo "$1" >"$d/memory.current"; echo "$2" >"$d/memory.swap.current"
  printf 'anon %s\nfile 4096\n' "$3" >"$d/memory.stat"; shift 3
  printf '%s\n' "$@" >"$d/cgroup.procs"
}
# pr <pid> <name> <rss_kb> <swap_kb> <argv…>
pr() {
  local d="$WORK/proc/$1"; mkdir -p "$d"
  printf 'Name:\t%s\nUmask:\t0002\nVmRSS:\t%s kB\nVmSwap:\t%s kB\n' "$2" "$3" "$4" >"$d/status"
  shift 4; printf '%s\0' "$@" >"$d/cmdline"
}
U=user.slice/user-$UID.slice/user@$UID.service
cg system.slice/ssh.service 2097152 0 1048576 10
cg system.slice/docker.service 1048576 0 1048576 11
cg system.slice/docker.service/inner.scope 1048576 0 1048576 12
cg user.slice/user-$UID.slice/session-5.scope 1048576 0 1048576
cg "$U" 0 0 0
cg "$U/app.slice/dark-eye.service" 4194304 1073741824 2097152 20 21
echo 'usage_usec 5000000' >"$WORK/sys/fs/cgroup/system.slice/ssh.service/cpu.stat"
printf 'usage_usec 7000000\nuser_usec 1\n' >"$WORK/sys/fs/cgroup/$U/app.slice/dark-eye.service/cpu.stat"
pr 10 sshd 900 0 /usr/sbin/sshd -D
pr 11 dockerd 100 0 /usr/bin/dockerd
pr 20 MainThread 96 1048576 $HOME/.nvm/node --max-old-space-size=99 $HOME/eye/voice.js
pr 21 helper 500 0 /usr/bin/helper

I1=64f0556ebef2de52687dd48acadef16685f88c9a6f4b9f97d0307f729c3612b7 I2=5e610f7e36d954a04beb097305ce9c0ed801d8cf30def32f97d3dba66147fd14
printf '%s\tmoodle52-app-1\n%s\tmoodle45-app-1\n' $I1 $I2 >"$WORK/dps"
mem sample; mem sample
row() { awk -F'\t' -v u="$1" 'NR > 1 && $2 == u { print; exit }' "$WORK/mem.tsv"; }
D=$(row dark-eye.service)

# 1. sample: one row per service/scope, user@ walked not recorded, a service's children pruned.
is 'header once, 4 units x 2 samples' "$(wc -l <"$WORK/mem.tsv")" 9
is 'header first' "$(head -1 "$WORK/mem.tsv" | cut -f1-3)" "$(printf 'ts\tunit\tscope')"
is 'user@ not a row' "$(row user@$UID.service)" ''
is 'child of a service pruned' "$(row inner.scope)" ''
is 'user manager scope' "$(cut -f3 <<<"$D")" user
is 'system manager scope' "$(row session-5.scope | cut -f3)" system
is 'mem/swap/anon in kB' "$(cut -f4-6 <<<"$D")" "$(printf '4096\t1048576\t2048')"
is 'top process is the largest rss+swap' "$(cut -f7 <<<"$D")" 20
is 'interpreter named by its script' "$(cut -f8 <<<"$D")" node:voice.js
is 'plain binary named by argv0' "$(row ssh.service | cut -f8)" sshd
is 'top rss/swap kB' "$(cut -f9,10 <<<"$D")" "$(printf '96\t1048576')"
is 'empty scope has no top' "$(row session-5.scope | cut -f7,9)" "$(printf -- '-\t0')"
C=$(sed -n 2,3p "$WORK/cpu.tsv" | cut -f2-4 | sort)
is 'cpu.tsv: header once, one row per unit with cpu.stat x 2' "$(head -1 "$WORK/cpu.tsv") $(wc -l <"$WORK/cpu.tsv")" "$(printf 'ts\tunit\tscope\tcpu_usec') 5"
is 'cpu.tsv: unit, scope, usage_usec' "$C" "$(printf 'dark-eye.service\tuser\t7000000\nssh.service\tsystem\t5000000')"
is 'sample: docker ps -a --no-trunc' "$(head -1 "$WORK/docker.log" | cut -d' ' -f1-3)" 'ps -a --no-trunc'
is 'names.tsv: id12 name first-seen, once per id' "$(cut -f1,2 "$WORK/names.tsv" | tr '\t\n' ' ,') $(cut -f3 "$WORK/names.tsv" | grep -cE '^[0-9]{10}$')" '64f0556ebef2 moodle52-app-1,5e610f7e36d9 moodle45-app-1, 2'
printf '%s\tmoodle52-app-1\n' $I1 >"$WORK/dps"
printf 'aaaaaaaaaaaa\tgone-new\t%s\nbbbbbbbbbbbb\tgone-old\t%s\n' $(( $(date +%s) - 86400 )) $(( $(date +%s) - 31 * 86400 )) >>"$WORK/names.tsv"
mem sample
is 'names.tsv: gone id kept 30 d, older one pruned, live one kept' "$(cut -f2 "$WORK/names.tsv" | sort | tr '\n' ' ')" 'gone-new moodle45-app-1 moodle52-app-1 '
cp "$WORK/names.tsv" "$WORK/names.bak"; rm "$WORK/dps"; printf '#!/bin/sh\nexit 1\n' >"$WORK/dstub/docker"
is 'docker down: sample still writes, names.tsv untouched' "$(mem sample; echo $?) $(cmp -s "$WORK/names.tsv" "$WORK/names.bak" && echo same)" '0 same'
printf '#!/bin/sh\necho "$*" >>"$WORK/docker.log"; cat "$WORK/dps" 2>/dev/null\n' >"$WORK/dstub/docker"
is 'unknown subcommand exits 2' "$(mem nope >/dev/null 2>&1; echo $?)" 2

# 2. growth: least-squares MB/day of anon+swap over the window, LEAK > 100, short spans and old rows out.
L="$WORK/g.tsv"; N=1800000000; H=3600
{ head -1 "$WORK/mem.tsv"
  for h in 0 4 8 12 16 20 24; do
    t=$((N - 24 * H + h * H))
    printf '%s\tdark-eye.service\tuser\t0\t%s\t%s\t20\tnode:voice.js\t0\t0\n' $t $((h * 200 * 1024 / 24)) 1024
    printf '%s\tflat.service\tuser\t0\t0\t51200\t1\tflat\t0\t0\n' $t
    printf '%s\tslow.service\tsystem\t0\t0\t%s\t1\tslow\t0\t0\n' $t $((h * 10 * 1024 / 24))
  done
  printf '%s\tblip.scope\tuser\t0\t0\t1024\t1\tb\t0\t0\n%s\tblip.scope\tuser\t0\t0\t99999\t1\tb\t0\t0\n' $((N - 60)) $N
  printf '%s\told.service\tuser\t0\t0\t0\t1\to\t0\t0\n%s\told.service\tuser\t0\t0\t999999\t1\to\t0\t0\n' $((N - 9 * 86400)) $((N - 8 * 86400))
  I3=$(printf 'c%.0s' {1..64})
  for m in 0 40 80 120; do t=$((N - 2 * H + m * 60)); printf '%s\tdocker-%s.scope\tsystem\t0\t0\t%s\t1\tapache2\t0\t0\n' $t $I1 $((m * 6 * 1024 / 60)) $t $I2 $((m * 1024 / 60)); done
  for h in 0 2 4 6 8; do t=$((N - 8 * H + h * H)); printf '%s\tfive.service\tuser\t0\t0\t%s\t1\tf\t0\t0\n' $t $((h * 5 * 1024)); done
  for h in 0 1 2 3 4 5 6 7 8; do t=$((N - 8 * H + h * H)); printf '%s\trise.service\tuser\t0\t0\t%s\t1\tr\t0\t0\n' $t $((h * 5 * 1024)); printf '%s\tdocker-%s.scope\tsystem\t0\t0\t0\t1\tx\t0\t0\n' $t $I3; done
} >"$L"
G=$(PC_MEM_LOG="$L" PC_MEM_NOW=$N "$BIN/pc-mem" growth --days 3)
is 'header names MB/day' "$(head -1 <<<"$G" | awk '{print $1}')" MB/day
is 'leaker ranked first' "$(sed -n 2p <<<"$G" | awk '{print $6}')" dark-eye.service
is 'leaker slope 200 MB/day' "$(sed -n 2p <<<"$G" | awk '{print $1}')" +200.0
is 'leaker flagged' "$(sed -n 2p <<<"$G" | grep -c LEAK)" 1
is 'slow grower 10 MB/day, not flagged' "$(grep slow.service <<<"$G" | awk '{print $1, NF}')" '+10.0 7'
is 'flat unit 0 MB/day' "$(grep flat.service <<<"$G" | awk '{print $1}')" +0.0
is 'young: 2 h / 4 samples rising, not a LEAK' "$(grep moodle52 <<<"$G" | awk '{print $1, $3, $4, $NF}')" '+144.0 2.0 4 young'
is 'LEAK needs n >= 6: 8 h / 5 samples is young' "$(grep five.service <<<"$G" | awk '{print $4, $NF}')" '5 young'
is 'LEAK: 8 h / 9 samples rising' "$(grep rise.service <<<"$G" | awk '{print $3, $4, $NF}')" '8.0 9 LEAK'
is 'docker scope named from names.tsv' "$(grep -c 'moodle52-app-1 (docker) ' <<<"$G")" 1
is 'Vass container keeps its owner-only tag' "$(grep -c 'moodle45-app-1 (Vass, owner-only)' <<<"$G")" 1
is 'unknown docker id stays the id' "$(grep -c "docker-$I3.scope" <<<"$G")" 1
is 'span under 1 h left out' "$(grep -c blip <<<"$G")" 0
is 'rows older than the window left out' "$(grep -c old.service <<<"$G")" 0
is 'old rows count with a wider window' "$(PC_MEM_LOG="$L" PC_MEM_NOW=$N "$BIN/pc-mem" growth --days 10 | grep -c old.service)" 1
head -12 "$L" >"$L.r.1"; { head -1 "$L"; sed -n 13,999p "$L"; } >"$L.r"
is 'growth reads the rotated <log>.1 too' "$(PC_MEM_LOG="$L.r" PC_MEM_NOW=$N "$BIN/pc-mem" growth --days 3)" "$G"
is 'no names.tsv: ids stay ids' "$(PC_MEM_NAMES="$WORK/none" PC_MEM_LOG="$L" PC_MEM_NOW=$N "$BIN/pc-mem" growth | grep -c "docker-$I1")" 1
is '-n caps the list' "$(PC_MEM_LOG="$L" PC_MEM_NOW=$N "$BIN/pc-mem" growth -n 1 | wc -l)" 2
is 'no samples exits 1' "$(PC_MEM_LOG="$WORK/none" "$BIN/pc-mem" growth >/dev/null 2>&1; echo $?)" 1
is 'nothing qualifies says so' "$(PC_MEM_LOG="$WORK/mem.tsv" "$BIN/pc-mem" growth | tail -1 | cut -c1-18)" '(no unit has two s'

# 3. swap-refresh: guards from a fixture meminfo/loadavg/clock, swapoff + swapon through a stub sudo that only logs.
mkdir -p "$WORK/stub"; cat >"$WORK/stub/sudo" <<'SH'
#!/bin/sh
[ "$1" = -n ] && shift
printf '%s\n' "$*" >>"$SUDO_LOG"
case "$*" in *"$STUB_FAIL"*) [ -n "$STUB_FAIL" ] && exit 1;; esac
exit 0
SH
chmod +x "$WORK/stub/sudo"
mi() { printf 'MemTotal: 32000000 kB\nMemAvailable: %s kB\nSwapTotal: 8388608 kB\nSwapFree: %s kB\n' "$1" "$2" >"$WORK/proc/meminfo"; echo "$3 1.00 1.00 1/100 1" >"$WORK/proc/loadavg"; }
sr() { : >"$WORK/sudo.log"; PATH="$WORK/stub:$PATH" SUDO_LOG="$WORK/sudo.log" CI_UNITS= CI_WINDOW_NOW="${NOW:-12:00}" PC_PROC="$WORK/proc" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-mem" swap-refresh "$@"; }
sw() { { printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n'; for e in "$@"; do printf '%s\t\tfile\t\t8388604\t\t24404\t\t%s\n' ${e%:*} ${e##*:}; done; } >"$WORK/proc/swaps"; }
mi 31000000 3664776 1.5   # 4613 MB used, 30273 MB available
sw /swap.img:-2
O=$(sr); is 'dry run: would line names the set' "${O%% (*}" 'would: swap 4613 MB → 0 MB on /swap.img'
is 'dry run: no sudo' "$(wc -l <"$WORK/sudo.log")" 0
O=$(sr --apply); is 'apply: that device off then back on' "$(cat "$WORK/sudo.log")" "$(printf 'nice -n 19 ionice -c3 swapoff /swap.img\nswapon /swap.img')"
is 'apply: read-back then rollback line' "$(tail -2 <<<"$O" | sed 's/, free.*//; s/undo .*/undo/')" "$(printf 'swap: used 4613 MB\nrollback: pc undo')"
is 'apply: ledgered' "$(tail -2 "$WORK/l.jsonl" | head -1 | jq -r '.target + " " + .before + " " + .after')" 'swap 4613 MB 0 MB'
is 'apply: never the fstab set' "$(grep -c -- ' -a' "$WORK/sudo.log")" 0
sw /swap.img:-2 /dev/zram0:100
O=$(sr --apply); is 'two devices: priority kept with -p, auto priority left auto' "$(grep '^swapon' "$WORK/sudo.log")" "$(printf 'swapon /swap.img\nswapon -p 100 /dev/zram0')"
O=$(STUB_FAIL='swapoff /dev/zram0' sr --apply); rc=$?
is 'swapoff fails midway: the device already off comes back, rc 1' "$(tail -2 "$WORK/sudo.log" | tr '\n' ' ')$rc" 'nice -n 19 ionice -c3 swapoff /dev/zram0 swapon /swap.img 1'
O=$(STUB_FAIL='swapon -p' sr --apply); rc=$?
is 'swapon fails: the same set retried, rc 1' "$(grep -c '^swapon -p 100 /dev/zram0' "$WORK/sudo.log") $rc" '2 1'
sw
O=$(sr --apply); rc=$?
is 'no active swap device: nothing, no sudo' "$O $rc $(wc -l <"$WORK/sudo.log")" 'nothing: no active swap in /proc/swaps 0 0'
sw /swap.img:-2
mi 12000000 3664776 1.5
O=$(sr --apply); rc=$?
is 'low memory: refused rc 1' "$(cut -c1-34 <<<"$O") $rc" 'nothing: refused, MemAvailable 117 1'
is 'low memory: no sudo' "$(wc -l <"$WORK/sudo.log")" 0
mi 31000000 3664776 4.20
O=$(sr --apply); is 'load1 >= 4: refused' "$O" 'nothing: refused, load1 4.20 >= 4'
mi 31000000 3664776 1.5
O=$(NOW=01:10 sr --apply); rc=$?
is 'CI window: refused rc 1' "${O%%;*} $rc" 'nothing: refused, in the CI window 00:50-01:50 1'
is 'CI window: no sudo' "$(wc -l <"$WORK/sudo.log")" 0
mi 31000000 8388608 1.5
O=$(sr --apply); is 'no swap used: nothing rc 0' "$O $?" 'nothing: swap used 0 MB 0'
# 4. agents: a fake /proc tree of claude sessions, their descendants and ancestors.
A="$WORK/aproc"; mkdir -p "$A"
echo '100000.00 1.00' >"$A/uptime"
printf 'MemTotal: 32000000 kB\nMemAvailable: %s kB\n' 30720000 >"$A/meminfo"   # 30000 MB
# ap <pid> <ppid> <name> <rss_kb> <swap_kb> <start_s> <cwd> <argv…> — stat (ppid, starttime ticks), status, cmdline, cwd link.
ap() {
  local d="$A/$1"; mkdir -p "$d"
  echo "$1 ($3 x) S $2 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 $(( $6 * $(getconf CLK_TCK) )) 0 0" >"$d/stat"
  printf 'Name:\t%s\nVmRSS:\t%s kB\nVmSwap:\t%s kB\n' "$3" "$4" "$5" >"$d/status"
  ln -s "$7" "$d/cwd"; shift 7; printf '%s\0' "$@" >"$d/cmdline"
}
ap 1 0 systemd 10000 0 0 / /sbin/init
ap 100 1 claude 409600 51200 99000 "$HOME" claude --continue
ap 101 100 node 102400 0 99100 "$HOME" node /x/playwright-mcp
ap 102 101 chrome 20480 0 99200 "$HOME" chrome --headless
ap 199 1 bash 4000 0 90000 /a bash $HOME/agents/bin/agent-run toolsmith
ap 198 199 timeout 1000 0 90000 /a timeout 3600 claude -p brief
ap 200 198 claude 307200 0 90000 /a/toolsmith claude -p brief --name agent-toolsmith
ap 202 200 node 10240 0 90100 /a node mcp.js
ap 201 200 claude 204800 0 90200 /a claude -p nested
ap 203 201 node 51200 0 90300 /a node mcp2.js
ap 299 1 node 30000 0 50000 /w node workflow.js
ap 300 299 claude 512000 0 50000 /w claude --print task
ag() { PC_PROC="$A" PC_SYS="$WORK/sys" "$BIN/pc-mem" agents "$@"; }
O=$(ag); arow() { awk -v p="$1" '$1 == p' <<<"$O"; }
is 'agents: header then one row per claude' "$(sed 1d <<<"$O" | grep -vc '^fit')" 4
is 'agents: rss swap children total MB' "$(arow 100 | awk '{print $3, $4, $5, $6}')" '400 50 120 570'
is 'agents: age from starttime' "$(arow 100 | awk '{print $2}')" 16m
is 'agents: age in hours' "$(arow 300 | awk '{print $2}')" 13.9h
is 'agents: interactive kind, cwd under ~' "$(arow 100 | awk '{print $7, $8}')" 'interactive ~'
is 'agents: agent-run ancestor' "$(arow 200 | awk '{print $7, $8}')" 'agent-run /a/toolsmith'
is 'agents: nested claude is its own row, not a child' "$(arow 200 | awk '{print $5}') $(arow 201 | awk '{print $5}')" '10 50'
is 'agents: -p/--print without agent-run is workflow' "$(arow 300 | awk '{print $7}')" workflow
is 'agents: sorted by total' "$(sed 1d <<<"$O" | grep -v '^fit' | awk '{print $1}' | tr '\n' ' ')" '100 300 200 201 '
is 'agents: fit line (30000 - 8192) / p90 570' "$(tail -1 <<<"$O")" 'fit 38 (avail 30000 MB − reserve 8192 MB) / p90 570 MB'
J=$(ag --json)
is 'agents --json: parses, fit and kinds' "$(jq -r '"\(.fit) \(.p90_mb) " + ([.sessions[].kind] | join(","))' <<<"$J")" '38 570 interactive,workflow,agent-run,agent-run'
is 'agents: reserve is a knob' "$(PC_MEM_RESERVE_MB=0 ag | tail -1 | awk '{print $2}')" 52
rm -rf "$A/100" "$A/200" "$A/201" "$A/300"
is 'agents: no session uses the default p90' "$(ag | tail -1)" 'fit 27 (avail 30000 MB − reserve 8192 MB) / p90 800 MB (no session: default)'

# 5. cpu: CPU s/h per hour from a synthetic cpu.tsv (6 samples at :01:56 like the timer, each delta credited to the hour holding its midpoint).
CL="$WORK/c.tsv"; M=1000000
{ printf 'ts\tunit\tscope\tcpu_usec\n'
  printf '%s\told.service\tsystem\t0\n%s\told.service\tsystem\t%s\n' $((N - 9 * 86400)) $((N - 9 * 86400 + H)) $((900 * M))
  i=0; for a in 0 36 72 792 828 864; do t=$((N - 6 * H + 116 + i * H)); b=(100 172 10 20 30 40)
    printf '%s\ta.service\tsystem\t%s\n' $t $((a * M))
    printf '%s\tb.service\tsystem\t%s\n' $t $((${b[i]} * M))
    printf '%s\tc.service\tuser\t%s\n' $t $((i * 18 * M))
    printf '%s\td.service\tsystem\t%s\n' $t $((i * M)); i=$((i + 1)); done
  printf '%s\tg.service\tsystem\t%s\n' $((N - 2 * H + 600)) 0 $((N - 2 * H + 1200)) $((6 * M)) $((N - 2 * H + 3000)) $((12 * M))
} >"$CL"
cpu() { TZ=UTC PC_MEM_CPU_LOG="${CPU_LOG:-$CL}" PC_MEM_NOW=$N "$BIN/pc-mem" cpu "$@"; }
O=$(cpu); hr() { awk -v h="$1" '$1 " " $2 == h { print $3, $4, $5 }' <<<"$O"; }
is 'cpu: header HOUR UNIT S/H' "$(head -1 <<<"$O" | awk '{print $1, $2, $3}')" 'HOUR UNIT S/H'
is 'cpu: hour 1 by s/h, d at 1 s/h kept' "$(hr '01-15 02:00' | tr '\n' ,)" 'b.service 72.0 ,a.service 36.0 ,user/c.service 18.0 ,d.service 1.0 ,'
is 'cpu: counter reset after restart is the new counter' "$(hr '01-15 03:00' | grep b.service)" 'b.service 10.0 '
is 'cpu: burst hour >= 10x median' "$(hr '01-15 04:00' | head -1)" 'a.service 720.0 BURST'
is 'cpu: only the burst hour is flagged' "$(grep -c BURST <<<"$O")" 1
is 'cpu: two samples in one hour sum to s/h' "$(hr '01-15 06:00' | grep g.service)" 'g.service 18.0 '
is 'cpu: rows older than the window left out' "$(grep -c old.service <<<"$O")" 0
is 'cpu: hours in order, 5 hours x 4 + g' "$(sed 1d <<<"$O" | awk '{print $2}' | uniq | tr '\n' ' ') $(sed 1d <<<"$O" | wc -l)" '02:00 03:00 04:00 05:00 06:00  21'
is 'cpu: --since 3h keeps 3 hours' "$(cpu --since 3h | sed 1d | awk '{print $2}' | uniq | wc -l)" 3
is 'cpu: --unit lists every hour of one unit' "$(cpu --unit d.service | sed 1d | awk '{print $3, $4}' | tr '\n' ,)" 'd.service 1.0,d.service 1.0,d.service 1.0,d.service 1.0,d.service 1.0,'
is 'cpu: 02:01:56 to 03:01:56 is filed under 02:00, not 03:00' "$(hr '01-15 02:00' | grep -c a.service) $(hr '01-15 07:00' | wc -l)" '1 0'
is 'cpu: --unit takes the printed user/<unit> name' "$(cpu --unit user/c.service | sed 1d | awk '{print $3, $4}' | sort -u)" 'user/c.service 18.0'
is 'cpu: bare --unit name does not match a user unit' "$(cpu --unit c.service | cut -c1-8)" 'nothing:'
is 'cpu: --since 10d sees the old unit' "$(cpu --since 10d | grep -c old.service)" 1
is 'cpu: bad --since exits 2' "$(cpu --since x >/dev/null 2>&1; echo $?)" 2
is 'cpu: no file says nothing:' "$(CPU_LOG="$WORK/none.tsv" cpu | cut -c1-27)" 'nothing: no cpu samples yet'
R="$WORK/rot.tsv"; head -4 "$CL" >"$R.1"; { head -1 "$CL"; sed -n 5,999p "$CL"; } >"$R"
is 'cpu: reads the rotated <log>.1 too' "$(CPU_LOG="$R" cpu)" "$O"
cp "$CL" "$R.1"; : >"$R"; is 'cpu: empty log after copytruncate still reads <log>.1' "$(CPU_LOG="$R" cpu)" "$O"
{ printf 'ts\tunit\tscope\tcpu_usec\n'; for u in $(seq 1 16) $I1 $I2; do printf '%s\tu%s.service\tsystem\t0\n%s\tu%s.service\tsystem\t%s\n' $((N - H)) $u $N $u $(( ${#u} * M )); done; } | sed "s/u$I1.service/docker-$I1.scope/; s/u$I2.service/docker-$I2.scope/" >"$WORK/many.tsv"
O=$(CPU_LOG="$WORK/many.tsv" cpu)
is 'cpu: top 15 per hour' "$(sed 1d <<<"$O" | wc -l)" 15
is 'cpu: docker scopes named, Vass tagged' "$(head -3 <<<"$O" | sed 1d | awk '{print $3, $4, $5}' | sort | tr '\n' ,)" 'moodle45-app-1 (Vass, owner-only),moodle52-app-1 (docker) 64.0,'
printf 'ts\tunit\tscope\tcpu_usec\n%s\tz.service\tsystem\t5\n' $N >"$WORK/one.tsv"
is 'cpu: one sample says nothing:' "$(CPU_LOG="$WORK/one.tsv" cpu)" 'nothing: no unit used CPU between two samples in the window'
exit $bad
