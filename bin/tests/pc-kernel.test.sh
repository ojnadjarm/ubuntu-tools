#!/usr/bin/env bash
# PT05: `pc kernel` against the recorded fixture (dmesg digest, modules, cgroup PSI, taint,
# cmdline), zswap/mglru knobs on a fake tree and in bwrap, plus one sysctl round trip on fs.inotify.max_user_instances inside bwrap over a fake
# /proc/sys, ledgered in a temp ledger and undone. No real sysctl, window, sound or unit touched.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/kernel"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
REAL_LIMIT=$(cat /proc/sys/fs/inotify/max_user_instances)
K="$BIN/pc-kernel"
. "$HOME/agents/bin/tests/lib/assert.sh"
# k <args…> — pc-kernel against the fixture tree, with its own cache and ledger.
k() { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/changes.jsonl" "$K" "$@"; }

# sb <cmd…> — inside bwrap with a fake tree bound over /proc/sys and a pass-through sudo shim
# (no_new_privs: the real sudo cannot rise), so no --apply here can reach the real kernel.
key=fs.inotify.max_user_instances
FAKE="$WORK/procsys"; mkdir -p "$FAKE/fs/inotify" "$FAKE/kernel/yama" "$FAKE/net/ipv4" "$WORK/shim"
: >"$FAKE/.pt05-fake"; echo 128 >"$FAKE/fs/inotify/max_user_instances"
for f in kernel/sysrq kernel/yama/ptrace_scope net/ipv4/ip_forward kernel/perf_event_paranoid; do echo 2 >"$FAKE/$f"; done
printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' >"$WORK/shim/sudo"; chmod +x "$WORK/shim/sudo"
sb() { bwrap --dev-bind / / --bind "$FAKE" /proc/sys --new-session --die-with-parent \
         --setenv PATH "$WORK/shim:/usr/sbin:/usr/bin:/bin" --setenv XDG_RUNTIME_DIR "$WORK" \
         --setenv PC_LEDGER "$WORK/sb.jsonl" "$@"; }
SANDBOX=0
if command -v bwrap >/dev/null && sb test -e /proc/sys/.pt05-fake 2>/dev/null && ! [ -e /proc/sys/.pt05-fake ]; then SANDBOX=1; fi
# sk <args…> — pc-kernel's guard calls, in the sandbox with the fixture and the temp ledger.
sk() { sb env PC_FIXTURE="$FIX" PC_LEDGER="$WORK/changes.jsonl" "$K" "$@"; }

# 1. dmesg: the digest collapses the 180 SSDP warnings to one masked row.
d=$(k dmesg --digest --since -1h --json)
is 'digest collapses the UFW flood'   "$(jq -r '.digest[0].count' <<<"$d")" 180
is 'digest keeps the other shapes'    "$(jq -r '.digest|length' <<<"$d")" 4
case "$(jq -r '.digest[0].sample' <<<"$d")" in
  *'[UFW BLOCK]'*'SRC=#'*'ID=#'*) ok 'digest masks addresses and ids';;
  *) nok 'digest masks addresses and ids' "$(jq -r '.digest[0].sample' <<<"$d")";;
esac
is 'digest is sorted by count' \
  "$(jq -r '[.digest[].count] == ([.digest[].count]|sort|reverse)' <<<"$d")" true
is 'digest rows carry first and last' "$(jq -r '.digest[0]|has("first") and has("last")' <<<"$d")" true

# 2. dmesg lines: default 30, -n honoured, level filter, err+warn is the default.
is 'dmesg prints 30 lines by default' "$(k dmesg --json | jq '.lines|length')" 30
is 'dmesg -n limits the lines'        "$(k dmesg -n 5 --json | jq '.lines|length')" 5
is 'dmesg defaults to err+warn'       "$(k dmesg --json | jq -c '[.lines[].level]|unique')" '["err","warn"]'
is 'dmesg --level filters'            "$(k dmesg --level err --json | jq -c '[.lines[].level]|unique')" '["err"]'
is 'dmesg --level all keeps info'     "$(k dmesg --level all --json | jq '[.lines[]|select(.level=="info")]|length')" 1
k dmesg --level nope >/dev/null 2>&1; is 'an unknown level exits 2' "$?" 2
is 'dmesg lines carry an iso time'    "$(k dmesg -n 1 --json | jq -r '.lines[0].time|test("^20[0-9][0-9]-")')" true

# 3. modules.
is 'modules lists the fixture'  "$(k modules --json | jq 'length')" 6
is 'modules sorts by name'      "$(k modules --json | jq -r '.[0].name')" asus_nb_wmi
m=$(k modules i915 --json)
is 'module refcount is a number' "$(jq -r '.refcount' <<<"$m")" 17
is 'module parameters are read'  "$(jq -r '.parameters.enable_guc' <<<"$m")" 3
is 'module description is read'  "$(jq -r '.description' <<<"$m")" 'Intel Graphics'
is 'holders fill the empty user list' \
  "$(k modules snd_intel_dspcfg --json | jq -c '.users')" '["snd_hda_intel"]'
k modules nosuchmod >/dev/null 2>&1; is 'an unknown module exits 1' "$?" 1

# 4. cgroups: cost + PSI per unit, and the depth-3 overview.
c=$(k cgroups dark-eye --user --json)
is 'cgroups resolves the unit name' "$(jq -r '.unit' <<<"$c")" dark-eye.service
is 'cgroups reports cpu seconds'    "$(jq -r '.cpu_usage_s > 0' <<<"$c")" true
is 'cgroups reports PSI'            "$(jq -r '.psi.cpu.some10' <<<"$c")" 0.11
is 'cgroups reports io PSI'         "$(jq -r '.psi.io|has("total_s")' <<<"$c")" true
is 'unaccounted io reads back null' "$(jq -r '.io_read_bytes' <<<"$c")" null
is 'cgroups text says n/a for io'   "$(k cgroups dark-eye --user | sed -n 's/^io  *//p')" 'read n/a write n/a'
is 'cgroups overview ranks by cpu'  "$(k cgroups --json | jq -r '.[0].cgroup')" app.slice/dark-eye.service

# 5. cmdline / taint / overview.
is 'cmdline parses key=value' "$(k cmdline --json | jq -r '.params[0].key')" BOOT_IMAGE
is 'cmdline keeps bare flags' "$(k cmdline --json | jq -r '.params[]|select(.key=="quiet").value')" null
t=$(k taint --json)
is 'taint decodes the bits'    "$(jq -c '.flags' <<<"$t")" '["O","E"]'
is 'taint names the reasons'   "$(jq -r '.reasons[1]' <<<"$t")" 'unsigned module loaded'
is 'taint reads the lockdown'  "$(jq -r '.lockdown' <<<"$t")" none
o=$(k --json)
is 'overview counts modules'   "$(jq -r '.modules' <<<"$o")" 6
is 'overview counts the hour'  "$(jq -r '.dmesg_last_hour' <<<"$o")" 183
is 'overview carries a digest' "$(jq -r '.digest|length' <<<"$o")" 3

# 5b. overview --json with a 400 KB last hour: 4000 memcg OOM lines must not reach jq's argv.
BIG="$WORK/bigfix"; cp -r "$FIX" "$BIG"
jq -c '.dmesg += [range(4000) as $i | {pri: 3, time: 1, msg: "Memory cgroup out of memory: Killed process \($i) (stress-ng-vm) total-vm:\($i)kB, anon-rss:\($i)kB, file-rss:0kB, shmem-rss:0kB"}]' \
  "$FIX/dmesg.json" >"$BIG/dmesg.json"
is 'the generated hour is over 400 KB' "$(( $(jq -r '[.dmesg[].msg]|join("\n")' "$BIG/dmesg.json" | wc -c) > 400000 ))" 1
o=$(PC_FIXTURE="$BIG" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/changes.jsonl" "$K" --json); rc=$?
is 'overview --json with a 400 KB last hour exits 0' "$rc" 0
is 'overview --json with a 400 KB last hour parses' "$(jq -r '.dmesg_last_hour' <<<"$o" 2>/dev/null)" 4183
mkdir -p "$WORK/nojq"; printf '#!/bin/sh\nexit 1\n' >"$WORK/nojq/jq"; chmod +x "$WORK/nojq/jq"
PATH="$WORK/nojq:$PATH" k --json >/dev/null 2>&1; rc=$?
is 'a failed jq makes the overview exit non-zero' "$([ "$rc" != 0 ] && echo yes || echo no)" yes

# 6. usage and option errors.
"$K" -h >/dev/null 2>&1;      is 'pc kernel -h exits 0' "$?" 0
"$K" --nope >/dev/null 2>&1;  is 'an unknown option exits 2' "$?" 2
"$K" bogus >/dev/null 2>&1;   is 'an unknown verb exits 2' "$?" 2
k sysctl >/dev/null 2>&1;     is 'sysctl without get/set exits 2' "$?" 2

# 7. sysctl guard: the reachability keys need --force and --why, and never mutate without them.
if [ "$SANDBOX" = 1 ]; then
  for g in 'kernel.sysrq 1' 'kernel.yama.ptrace_scope 0' 'net.ipv4.ip_forward 1' 'kernel.perf_event_paranoid 1'; do
    # shellcheck disable=SC2086
    out=$(sk sysctl set $g --apply 2>&1); rc=$?
    is "guard refuses ${g%% *}" "$rc" 3
    case "$out" in *'--force'*'--why'*) :;; *) nok "guard says how to override ${g%% *}" "$out";; esac
  done
  out=$(sk sysctl set kernel.sysrq 1 --apply --force 2>&1); is 'guard still refuses --force without --why' "$?" 3
  out=$(sk sysctl set kernel.sysrq 1 --force --why 'test only, no --apply' 2>&1); rc=$?
  is '--force --why gets past the guard (dry run)' "$rc" 0
  case "$out" in would:*) ok 'the override is still a dry run without --apply';; *) nok 'the override is still a dry run without --apply' "$out";; esac
  is 'the guarded dry run wrote no ledger' "$( [ -e "$WORK/changes.jsonl" ] && echo yes || echo no)" no
else
  echo 'skip no bwrap sandbox: sysctl guard calls'
fi

# 8. live, read-only: sysctl get and a dry-run set of the current value.
# A refusing sudo, like run.sh's shim (T1136): the live reads stay unprivileged.
mkdir -p "$WORK/nosudo"; printf '#!/bin/sh\nexit 1\n' >"$WORK/nosudo/sudo"; chmod +x "$WORK/nosudo/sudo"
lk() { PATH="$WORK/nosudo:$PATH" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/live.jsonl" "$K" "$@"; }
sw=$(cat /proc/sys/vm/swappiness)
is 'sysctl get reads a key'      "$(lk sysctl get vm.swappiness --json | jq -r '."vm.swappiness"')" "$sw"
is 'sysctl get expands a prefix' "$(lk sysctl get fs.inotify --json | jq 'length > 1')" true
lk sysctl get no.such.key >/dev/null 2>&1; is 'an unknown key exits 1' "$?" 1
is 'sysctl set is a dry run without --apply' \
  "$(lk sysctl set vm.swappiness "$sw" | head -1)" "would: vm.swappiness $sw → $sw"

# 9. sandboxed round trip: set --apply → ledger → pc undo --last --apply → back.
if ! command -v bwrap >/dev/null || ! sb true 2>/dev/null; then
  echo 'skip bwrap unavailable: sandboxed sysctl round trip'
elif [ "$SANDBOX" != 1 ]; then
  nok 'sandboxed sysctl round trip' 'refused: /proc/sys in the sandbox resolves to the real /proc'
else
  ok 'the sandbox sees the fake /proc/sys'
  out=$(sb "$K" sysctl set "$key" 129 --apply)
  is 'the applied value is in the fake tree' "$(cat "$FAKE/fs/inotify/max_user_instances")" 129
  id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
  [ -n "$id" ] && ok 'the set prints its rollback id' || nok 'the set prints its rollback id' "$out"
  is 'the ledger holds the pair' "$(wc -l <"$WORK/sb.jsonl")" 2
  is 'the ledger verified the change' "$(jq -r 'select(.id=="'"$id"'" and has("verified")).observed' "$WORK/sb.jsonl")" 129
  is 'the ledger stores the inverse' \
    "$(jq -r 'select(has("rollback")).rollback' "$WORK/sb.jsonl" | grep -c "$key=128")" 1
  sb "$BIN/pc-undo" --last --apply >/dev/null 2>&1
  is 'pc undo restores the original' "$(cat "$FAKE/fs/inotify/max_user_instances")" 128
  is 'the undo is ledgered too' "$(wc -l <"$WORK/sb.jsonl")" 4
fi
is 'the real limit is untouched' "$(cat /proc/sys/fs/inotify/max_user_instances)" "$REAL_LIMIT"
is 'the real ledger was never touched' "$( [ -e "$HOME/agents/log/changes.jsonl.pt05" ] && echo yes || echo no)" no

# 9b. sysctl set --persist: the runtime value and its 91-pc.conf line are one ledger entry; one undo restores both.
REAL_CONF=$(sha256sum /etc/sysctl.d/91-pc.conf 2>/dev/null || echo absent)
printf '#!/bin/sh\nexit 0\n' >"$WORK/shim/etckeeper"; chmod +x "$WORK/shim/etckeeper"
CR="$WORK/root"; PCF="$CR/etc/sysctl.d/91-pc.conf"; LIM="$FAKE/fs/inotify/max_user_instances"
pk() { sb env PC_CONF_ROOT="$CR" PC_CONF_BACKUP="$WORK/bk" PC_LEDGER="$WORK/ps.jsonl" "$@"; }
if [ "$SANDBOX" != 1 ]; then
  echo 'skip no bwrap sandbox: sysctl --persist'
else
  echo 128 >"$LIM"
  out=$(pk "$K" sysctl set "$key" 130 --persist)
  case "$out" in "would: $key 128 file=absent → 130 file=sha:"*'+'"$key = 130"*) ok 'persist dry run shows value, file and diff';;
    *) nok 'persist dry run shows value, file and diff' "$out";; esac
  is 'persist dry run wrote nothing' "$(cat "$LIM")$( [ -e "$PCF" ] && echo F)$( [ -e "$WORK/ps.jsonl" ] && echo L)" 128
  pk "$K" sysctl set "$key" 130 --persist --apply >/dev/null 2>&1
  is 'persist sets the runtime value'    "$(cat "$LIM")" 130
  is 'persist writes the key line'       "$(grep -c "^$key = 130\$" "$PCF" 2>/dev/null)" 1
  is 'persist is one verified ledger entry' "$(jq -r 'select(has("verified")).verified' "$WORK/ps.jsonl" 2>/dev/null | tr '\n' ' ')" 'true '
  pk "$BIN/pc-undo" --last --apply >/dev/null 2>&1
  is 'undo restores the runtime value'   "$(cat "$LIM")" 128
  is 'undo removes the file it created'  "$( [ -e "$PCF" ] && echo present || echo absent)" absent
  printf '# keep\nvm.swappiness = 10\n%s=99\n' "$key" >"$WORK/seed"; install -D -m 644 "$WORK/seed" "$PCF"
  pk "$K" sysctl set "$key" 131 --persist --apply >/dev/null 2>&1
  is 'persist keeps the other lines'     "$(grep -c -e '^# keep$' -e '^vm.swappiness = 10$' "$PCF")" 2
  is 'persist replaces the old key line' "$(grep -c "$key" "$PCF")" 1
  pk "$BIN/pc-undo" --last --apply >/dev/null 2>&1
  cmp -s "$PCF" "$WORK/seed" && ok 'undo restores the file byte-identical' || nok 'undo restores the file byte-identical' "$(cat "$PCF")"
  is 'undo restores the runtime value again' "$(cat "$LIM")" 128
  is 'each persist apply has its own backup dir' "$(ls "$WORK/bk" | wc -l)" 2
  pk env PC_SYSCTL_CONF=/etc/ssh/sshd_config.d/zz.conf "$K" sysctl set "$key" 132 --persist --apply >/dev/null 2>&1
  is 'a denied persist path exits 2'     "$?" 2
  pk env PC_CONF_BIN="$WORK/nope" "$K" sysctl set "$key" 132 --persist --apply >/dev/null 2>&1
  is 'persist without pc conf exits 4'   "$?" 4
  is 'refused persists left the value'   "$(cat "$LIM")" 128
fi
is 'the real 91-pc.conf is untouched' "$(sha256sum /etc/sysctl.d/91-pc.conf 2>/dev/null || echo absent)" "$REAL_CONF"

# 10. zswap / mglru on a fake tree: status numbers, dry run, key and value validation.
REAL_ZS=$(cat /sys/module/zswap/parameters/enabled /sys/module/zswap/parameters/compressor /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null)
ZT="$WORK/zt"; ZD="$ZT/sys/module/zswap/parameters"; MD="$ZT/sys/kernel/mm/lru_gen"; mkdir -p "$ZD" "$MD" "$ZT/proc"
zs_reset() { echo N >"$ZD/enabled"; echo lzo >"$ZD/compressor"; echo 20 >"$ZD/max_pool_percent"; echo 90 >"$ZD/accept_threshold_percent"
             echo Y >"$ZD/shrinker_enabled"; echo 0 >"$MD/min_ttl_ms"; echo 0x0007 >"$MD/enabled"; }
zs_reset; : >"$ZD/.t1044-fake"; : >"$MD/.t1044-fake"
printf 'SwapTotal: 8388604 kB\nSwapFree: 2766500 kB\nZswap: 262144 kB\nZswapped: 1048576 kB\n' >"$ZT/proc/meminfo"
echo 'btime 0' >"$ZT/proc/stat"
printf 'pswpout 5155895\nzswpin 7\nzswpout 300000\nzswpwb 42\n' >"$ZT/proc/vmstat"
zk() { PC_SYS="$ZT/sys" PC_PROC="$ZT/proc" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/zk.jsonl" "$K" "$@"; }
z=$(zk zswap --json)
is 'zswap status reads the params'     "$(jq -r '.params.enabled + .params.compressor' <<<"$z")" Nlzo
is 'zswap status pool size'            "$(jq -r '.pool_kb' <<<"$z")" 262144
is 'zswap status stored pages'         "$(jq -r '.stored_pages' <<<"$z")" 262144
is 'zswap status written-back pages'   "$(jq -r '.written_back_pages' <<<"$z")" 42
case "$(zk zswap)" in *'ratio 4'*'written back  42 pages'*) ok 'zswap text shows ratio and writeback';; *) nok 'zswap text shows ratio and writeback' "$(zk zswap)";; esac
is 'mglru status reads min_ttl_ms'     "$(zk mglru --json | jq -r '.min_ttl_ms')" 0
is 'zswap set is a dry run without --apply' "$(zk zswap set enabled=Y compressor=zstd)" \
  'would: zswap compressor=lzo enabled=N → compressor=zstd enabled=Y'
is 'the dry run wrote nothing'         "$(cat "$ZD/enabled")$( [ -e "$WORK/zk.jsonl" ] && echo L)" N
zk zswap set bogus=1 >/dev/null 2>&1;            is 'an unknown zswap key exits 2' "$?" 2
zk zswap set 'compressor=zstd;id' >/dev/null 2>&1; is 'a shell-ish value exits 2' "$?" 2
zk zswap set zpool=zsmalloc >/dev/null 2>&1;     is 'a key this kernel lacks exits 2' "$?" 2
zk zswap set >/dev/null 2>&1;                    is 'zswap set with no pair exits 2' "$?" 2
zk mglru bogus >/dev/null 2>&1;                  is 'an unknown mglru verb exits 2' "$?" 2
is 'an unchanged value is not ledgered' "$(zk zswap set enabled=N --apply)$( [ -e "$WORK/zk.jsonl" ] && echo L)" 'already: zswap enabled=N'

# 11. --persist: merges `w` lines into the tmpfiles file through pc conf (stubbed), or refuses without it.
printf '#!/bin/sh\necho "conf $*"; cat "$4" >"%s/persisted"\n' "$WORK" >"$WORK/pc-conf"; chmod +x "$WORK/pc-conf"
TF="$WORK/90-agents-mm.conf"; printf 'w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000\nw /sys/module/zswap/parameters/enabled - - - - N\n' >"$TF"
out=$(PC_CONF_BIN="$WORK/pc-conf" PC_TMPFILES="$TF" zk zswap set enabled=Y compressor=zstd --persist)
case "$out" in *"conf put $TF --from "*) ok 'persist calls pc conf put on the tmpfiles path';; *) nok 'persist calls pc conf put on the tmpfiles path' "$out";; esac
is 'persist without --apply passes no --apply' "$(grep -c -- '--apply' <<<"$out")" 0
is 'persist keeps the other knob'      "$(grep -c '^w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000$' "$WORK/persisted")" 1
is 'persist replaces the old line'     "$(grep -c 'zswap/parameters/enabled' "$WORK/persisted")" 1
is 'persist writes the real sysfs path' "$(grep -c '^w /sys/module/zswap/parameters/enabled - - - - Y$' "$WORK/persisted")" 1
is 'persist orders compressor first'   "$(grep -o 'compressor\|enabled' "$WORK/persisted" | head -1)" compressor
PC_CONF_BIN="$WORK/nope" zk mglru set min_ttl_ms=1000 --persist >/dev/null 2>&1; is 'persist without pc conf exits 4' "$?" 4

# 12. sandboxed round trip: the fake knobs are bound over the real sysfs dirs; set --apply → undo.
zb() { bwrap --dev-bind / / --bind "$ZD" /sys/module/zswap/parameters --bind "$MD" /sys/kernel/mm/lru_gen \
         --new-session --die-with-parent --setenv PATH "$WORK/shim:/usr/sbin:/usr/bin:/bin" \
         --setenv XDG_RUNTIME_DIR "$WORK" --setenv PC_LEDGER "$WORK/zb.jsonl" "$@"; }
zs_reset
if ! command -v bwrap >/dev/null || ! zb true 2>/dev/null; then
  echo 'skip bwrap unavailable: sandboxed zswap round trip'
elif ! zb test -e /sys/module/zswap/parameters/.t1044-fake || [ -e /sys/module/zswap/parameters/.t1044-fake ] \
     || ! zb test -e /sys/kernel/mm/lru_gen/.t1044-fake; then
  nok 'sandboxed zswap round trip' 'refused: the sandbox sysfs resolves to the real knobs'
else
  ok 'the sandbox sees the fake zswap and lru_gen dirs'
  out=$(zb "$K" zswap set enabled=Y compressor=zstd max_pool_percent=20 --apply)
  is 'zswap apply wrote the fake tree'   "$(cat "$ZD/enabled" "$ZD/compressor" | tr '\n' ' ')" 'Y zstd '
  is 'zswap apply is verified in the ledger' "$(jq -r 'select(has("verified")).verified' "$WORK/zb.jsonl")" true
  case "$out" in *'rollback: pc undo '*) ok 'zswap apply prints its rollback';; *) nok 'zswap apply prints its rollback' "$out";; esac
  out=$(zb "$K" mglru set min_ttl_ms=1000 --apply)
  is 'mglru apply wrote the fake tree'   "$(cat "$MD/min_ttl_ms")" 1000
  zb "$BIN/pc-undo" --last --apply >/dev/null 2>&1
  is 'pc undo restores min_ttl_ms'       "$(cat "$MD/min_ttl_ms")" 0
  zb "$BIN/pc-undo" "$(jq -r 'select(.target=="zswap" and has("rollback")).id' "$WORK/zb.jsonl" | head -1)" --apply >/dev/null 2>&1
  is 'pc undo restores zswap'            "$(cat "$ZD/enabled" "$ZD/compressor" | tr '\n' ' ')" 'N lzo '
fi
is 'the real zswap and mglru knobs are untouched' \
  "$(cat /sys/module/zswap/parameters/enabled /sys/module/zswap/parameters/compressor /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null)" "$REAL_ZS"

# oom (T1049): recorded kernel traces (journalctl -b all) + Started lines; class real (global), test-cap (run.sh/agent-verify/container scope < 1G), cap.
o=$(k oom --since 7d --json)
is 'oom: one row per kill, every boot'    "$(jq '.kills|length' <<<"$o")" 6
is 'oom: classes counted'                 "$(jq -c '.count' <<<"$o")" '{"cap":2,"real":1,"test-cap":3}'
is 'oom: the global kill is real'         "$(jq -r '.kills[0]|[.kind,.class,.scope,.cmd,.anon_mb]|join(" ")' <<<"$o")" 'global real tmux-spawn-789b037a.scope script 33122'
is 'oom: 6G ffmpeg is a cap, not test-cap' "$(jq -r '.kills[1]|[.class,.limit_mb]|join(" ")' <<<"$o")" 'cap 6144'
is 'oom: agent-verify oom case'           "$(jq -r '.kills[2]|[.class,.by,.test,.limit_mb]|join(" ")' <<<"$o")" 'test-cap agent-verify bin/tests/oom.test.sh (fixture root) 200'
is 'oom: run.sh 48M oom case'             "$(jq -r '.kills[3]|[.class,.by,.anon_mb]|join(" ")' <<<"$o")" 'test-cap run.sh 46'
is 'oom: hand-made systemd-run cap'       "$(jq -r '.kills[4]|[.class,.by]|join(" ")' <<<"$o")" 'cap systemd-run'
is 'oom: fresh-container case, host Started line ignored' "$(jq -r '.kills[5]|[.class,.by,.limit_mb]|join(" ")' <<<"$o")" 'test-cap ct:dbb277c04c98 200'
t=$(k oom --since 7d)
is 'oom: table has one real row'          "$(grep -c ' real ' <<<"$t")" 1
is 'oom: table summary'                   "$(tail -1 <<<"$t")" 'kills: real=1 test-cap=3 cap=2'

# oom (T1061): vm.oom_dump_tasks=0 drops the task table; a full unfiltered block without it still classifies.
D="$WORK/nodump"; cp -rs "$FIX" "$D"; rm "$D/journal/kernel-oom.txt"
h='1792600000.1 box kernel:'
{ echo "$h python3 invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=200"
  echo "$h Call Trace:"; echo "$h  <TASK>"; echo "$h  out_of_memory+0xff/0x2b0"; echo "$h  </TASK>"
  echo "$h memory: usage 49152kB, limit 49152kB, failcnt 20"
  echo "$h swap: usage 0kB, limit 0kB, failcnt 0"
  echo "$h Memory cgroup stats for /user.slice/user-$UID.slice/user@$UID.service/app.slice/run-p2531638-i40269511.scope:"
  echo "$h anon 49799168"
  echo "$h oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=user.slice,mems_allowed=0,oom_memcg=/user.slice/user-$UID.slice/user@$UID.service/app.slice/run-p2531638-i40269511.scope,task_memcg=/user.slice/user-$UID.slice/user@$UID.service/app.slice/run-p2531638-i40269511.scope,task=python3,pid=2531640,uid=1000"
  echo "$h Memory cgroup out of memory: Killed process 2531640 (python3) total-vm:86836kB, anon-rss:47992kB, file-rss:6804kB, shmem-rss:0kB, UID:1000 pgtables:168kB oom_score_adj:200"
} >"$D/journal/kernel-oom.txt"
o=$(PC_FIXTURE="$D" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/changes.jsonl" "$K" oom --since 7d --json)
is 'oom: dump-less block still classifies' "$(jq -r '.kills|length as $n|.[0]|[$n,.kind,.class,.by,.scope,.cmd,.anon_mb,.limit_mb]|join(" ")' <<<"$o")" \
  '1 memcg test-cap run.sh run-p2531638-i40269511.scope python3 46 48'

# dmesg (T1109): a --since before the ring buffer reads journalctl -k; OOM reports fold to one classed row; known lines are tagged.
JF="$WORK/jfix"; cp -rs "$FIX" "$JF"; rm "$JF/bin/journalctl" "$JF/journal/kernel-oom.txt"
cat >"$JF/bin/journalctl" <<'STUB'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)/journal"
case " $* " in
  *' --user '*) cat "$d/user-started.txt";;
  *' -o json '*) cat "$d/kernel.json";;
  *' -k '*'-b all '*) cat "$d/kernel-oom.txt";;
esac
STUB
chmod +x "$JF/bin/journalctl"
printf -v T0 '%(%s)T' -1; T0=$((T0 - 5000))
# oom_block <epoch> <memcg-path> <limit-kB> <global?> — one kernel OOM report as "epoch<TAB>pri<TAB>msg" rows.
oom_block() {
  local e=$1 cg=$2 lim=$3 c='CONSTRAINT_MEMCG' x='Memory cgroup out of memory' f
  [ "$4" = 1 ] && { c='CONSTRAINT_NONE'; x='Out of memory'; }
  printf '%s\t4\t%s\n' "$e" 'python3 invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=200' \
    "$e" 'CPU: 6 UID: 1000 PID: 4242 Comm: python3 Kdump: loaded Not tainted 7.0.0-38-generic #38-Ubuntu' "$e" 'Call Trace:' "$e" ' <TASK>'
  for f in show_stack+0x49/0x60 dump_stack_lvl+0x5f/0x90 charge_memcg+0x34/0x80 try_charge_memcg+0x3c3/0x620 out_of_memory+0xff/0x2b0; do printf '%s\t4\t %s\n' "$e" "$f"; done
  printf '%s\t4\t%s\n' "$e" 'RAX: 00007788e19ff030 RBX: 0000000019000000 RCX: 0000000000000001' "$e" ' </TASK>'
  printf '%s\t6\t%s\n' "$e" "memory: usage ${lim}kB, limit ${lim}kB, failcnt 20" "$e" "Memory cgroup stats for $cg:" "$e" 'anon 49799168' \
    "$e" "oom-kill:constraint=$c,nodemask=(null),cpuset=user.slice,mems_allowed=0,$( [ "$4" = 1 ] && echo global_oom,)oom_memcg=$cg,task_memcg=$cg,task=python3,pid=4242,uid=1000"
  printf '%s\t3\t%s\n' "$e" "$x: Killed process 4242 (python3) total-vm:86836kB, anon-rss:47992kB, file-rss:6804kB, shmem-rss:0kB, UID:1000 pgtables:168kB oom_score_adj:200"
}
A=/user.slice/user-$UID.slice/user@$UID.service/app.slice
{ for i in $(seq 50); do printf '%s\t4\t[UFW BLOCK] IN=wlo1 OUT= MAC=01:00:5e:7f:ff:fa SRC=192.168.1.%d DST=239.255.255.250 LEN=%d TOS=0x00 TTL=64 ID=%d DF PROTO=UDP SPT=4%04d DPT=15600 LEN=43 \n' $((T0 + i)) "$i" $((60 + i % 300)) $((10000 + i)) "$i"; done
  for l in 32 36 40; do printf '%s\t4\t[UFW BLOCK] IN=wlo1 OUT= MAC=01:00:5e SRC=192.168.1.1 DST=224.0.0.1 LEN=%s TOS=0x00 TTL=1 ID=0 DF PROTO=2 \n' $((T0 + 60)) "$l"; done
  for s in 'SEN1._PSV.S1PT' 'SEN1._HOT.S1HT' 'SEN2._CRT.S2CT' 'SEN3._AC0.S3AT'; do
    printf '%s\t3\tACPI BIOS Error (bug): Could not resolve symbol [\\_SB.PC00.LPCB.EC0.%s], AE_NOT_FOUND (20251212/psargs-332)\n' $((T0 + 70)) "$s"; done
  for s in SEN1._PSV SEN2._CRT; do printf '%s\t3\tACPI Error: Aborting method \\_SB.PC00.LPCB.EC0.%s due to previous error (AE_NOT_FOUND) (20251212/psparse-529)\n' $((T0 + 70)) "$s"; done
  for i in 1 2 3; do printf '%s\t4\t[Firmware Bug]: CPU10: Topology domain %d shift 7 != 6\n' $((T0 + 71)) "$i"; done
  printf '%s\t4\tkauditd_printk_skb: %d callbacks suppressed\n' $((T0 + 80)) 13 $((T0 + 90)) 28
  printf '%s\t6\twlo1: associated\n' $((T0 + 95))
  oom_block $((T0 + 100)) "$A/run-p2531638-i40269511.scope" 49152 0
  oom_block $((T0 + 200)) "$A/run-p376706-i17167927.scope" 6291456 0
  oom_block $((T0 + 300)) "$A/tmux-spawn-789b037a.scope" 0 1
} >"$WORK/kj.tsv"
jq -R -c 'split("\t") | {__REALTIME_TIMESTAMP: ((.[0] | tonumber) * 1000000 + 123456 | tostring), PRIORITY: .[1], MESSAGE: .[2]}' "$WORK/kj.tsv" >"$JF/journal/kernel.json"
awk -F'\t' '$3 ~ /invoked oom-killer|^memory: usage|^oom-kill:|Killed process/ { print $1 ".123456 box kernel: " $3 }' "$WORK/kj.tsv" >"$JF/journal/kernel-oom.txt"
jk() { PC_FIXTURE="$JF" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/changes.jsonl" "${KJ:-$K}" "$@"; }
d=$(jk dmesg --since -2h --digest --json)
is 'digest: --since before the ring buffer reads the journal' "$(jq '[.digest[]|select(.sample|test("ACPI"))]|length' <<<"$d")" 2
is 'digest: no call-trace frame or register is a row' \
  "$(jq '[.digest[].sample|select(test("\\+0x|<TASK>|</TASK>|^Call Tr|^R[A-Z0-9]+: |^CPU: |^Memory cgroup out"))]|length' <<<"$d")" 0
is 'digest: one oom-report row per class' \
  "$(jq -r '[.digest[]|select(.sample|startswith("oom-report"))|.sample]|sort|join(" | ")' <<<"$d")" \
  'oom-report global tmux-spawn-#.scope class=real | oom-report memcg run-p#-i#.scope class=cap | oom-report memcg run-p#-i#.scope class=test-cap'
is 'digest: an oom-report row is err and tagged with its class' \
  "$(jq -r '.digest[]|select(.sample|endswith("class=test-cap"))|[.count,.level,.tag]|join(" ")' <<<"$d")" '1 err oom:test-cap'
is 'digest: UFW BLOCK folds per interface and protocol' \
  "$(jq -r '[.digest[]|select(.tag=="owner:ufw-logging")|.count]|join(" ")' <<<"$d")" '50 3'
is 'digest: ACPI AE_NOT_FOUND and topology lines are known-harmless' \
  "$(jq -r '[.digest[]|select(.tag=="known-harmless")|.count]|sort|join(" ")' <<<"$d")" '2 3 4'
is 'digest: numbers fold into one row'   "$(jq -r '.digest[]|select(.sample|startswith("kauditd"))|[.count,.tag]|join(" ")' <<<"$d")" '2 unknown'
is 'digest: rows for the fixture journal' "$(jq '.digest|length' <<<"$d")" 9
is 'digest: the level filter still drops info' "$(jq '[.digest[]|select(.sample|test("associated"))]|length' <<<"$d")" 0
t=$(jk dmesg --since -2h --digest)
case "$t" in *'owner:ufw-logging'*'[UFW BLOCK]'*) ok 'digest text shows the tag column';; *) nok 'digest text shows the tag column' "$t";; esac
is 'digest text has one line per row' "$(wc -l <<<"$t")" 9
is 'digest: a --since inside the ring buffer stays on it' "$(jk dmesg --since -10m --digest --json | jq '[.digest[]|select(.sample|test("ACPI"))]|length')" 0
is 'digest: an empty journal falls back to the ring buffer' "$(k dmesg --since -2h --digest --json | jq '.digest[0].count')" 180
o=$(jk oom --since 7d --json)
is 'oom: a test file missing under ~/agents is marked fixture root' "$(jq -r '.kills[0].test' <<<"$o")" 'bin/tests/oom.test.sh (fixture root)'
mkdir -p "$WORK/ag/bin/tests"; : >"$WORK/ag/bin/tests/oom.test.sh"
is 'oom: a test file under ~/agents prints plain' "$(PC_AGENTS_DIR="$WORK/ag" jk oom --since 7d --json | jq -r '.kills[0].test')" 'bin/tests/oom.test.sh'
mkdir -p "$WORK/km"; ln -s "$BIN/pclib.sh" "$WORK/km/pclib.sh"; sed 's/| fold |/|/' "$K" >"$WORK/km/pc-kernel"; chmod +x "$WORK/km/pc-kernel"
is 'mutation selftest: the mutant skips the fold' "$(grep -c '| fold |' "$WORK/km/pc-kernel")" 0
is 'mutation: without the fold, frames are rows again' \
  "$(KJ="$WORK/km/pc-kernel" jk dmesg --since -2h --digest --json | jq '[.digest[].sample|select(test("\\+0x"))]|length > 0')" true

[ $bad = 0 ] && echo 'PASS pc-kernel' || echo 'FAIL pc-kernel'
exit $bad
