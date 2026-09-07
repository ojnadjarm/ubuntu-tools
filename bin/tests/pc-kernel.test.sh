#!/usr/bin/env bash
# PT05: `pc kernel` against the recorded fixture (dmesg digest, modules, cgroup PSI, taint,
# cmdline) plus one live sysctl round trip on fs.inotify.max_user_instances, ledgered in a
# temp ledger and undone in the same test. No window, no sound, no unit touched.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/kernel"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
K="$BIN/pc-kernel"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
# k <args…> — pc-kernel against the fixture tree, with its own cache and ledger.
k() { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/changes.jsonl" "$K" "$@"; }

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

# 6. usage and option errors.
"$K" -h >/dev/null 2>&1;      is 'pc kernel -h exits 0' "$?" 0
"$K" --nope >/dev/null 2>&1;  is 'an unknown option exits 2' "$?" 2
"$K" bogus >/dev/null 2>&1;   is 'an unknown verb exits 2' "$?" 2
k sysctl >/dev/null 2>&1;     is 'sysctl without get/set exits 2' "$?" 2

# 7. sysctl guard: the reachability keys need --force and --why, and never mutate without them.
for g in 'kernel.sysrq 1' 'kernel.yama.ptrace_scope 0' 'net.ipv4.ip_forward 1' 'kernel.perf_event_paranoid 1'; do
  # shellcheck disable=SC2086
  out=$(k sysctl set $g --apply 2>&1); rc=$?
  is "guard refuses ${g%% *}" "$rc" 3
  case "$out" in *'--force'*'--why'*) :;; *) nok "guard says how to override ${g%% *}" "$out";; esac
done
out=$(k sysctl set kernel.sysrq 1 --apply --force 2>&1); is 'guard still refuses --force without --why' "$?" 3
out=$(k sysctl set kernel.sysrq 1 --force --why 'test only, no --apply' 2>&1); rc=$?
is '--force --why gets past the guard (dry run)' "$rc" 0
case "$out" in would:*) ok 'the override is still a dry run without --apply';; *) nok 'the override is still a dry run without --apply' "$out";; esac
is 'the guarded dry run wrote no ledger' "$( [ -e "$WORK/changes.jsonl" ] && echo yes || echo no)" no

# 8. live, read-only: sysctl get and a dry-run set of the current value.
lk() { XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/live.jsonl" "$K" "$@"; }
sw=$(sysctl -n vm.swappiness)
is 'sysctl get reads a key'      "$(lk sysctl get vm.swappiness --json | jq -r '."vm.swappiness"')" "$sw"
is 'sysctl get expands a prefix' "$(lk sysctl get fs.inotify --json | jq 'length > 1')" true
lk sysctl get no.such.key >/dev/null 2>&1; is 'an unknown key exits 1' "$?" 1
is 'sysctl set is a dry run without --apply' \
  "$(lk sysctl set vm.swappiness "$sw" | head -1)" "would: vm.swappiness $sw → $sw"

# 9. live round trip on a harmless key: set --apply → ledger → pc undo --last --apply → back.
key=fs.inotify.max_user_instances
orig=$(sysctl -n "$key")
if timeout 5 sudo -n true 2>/dev/null; then
  new=$((orig + 1))
  out=$(lk sysctl set "$key" "$new" --apply)
  is 'the applied value is live' "$(sysctl -n "$key")" "$new"
  id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
  [ -n "$id" ] && ok 'the set prints its rollback id' || nok 'the set prints its rollback id' "$out"
  is 'the ledger holds the pair' "$(wc -l <"$WORK/live.jsonl")" 2
  is 'the ledger verified the change' "$(jq -r 'select(.id=="'"$id"'" and has("verified")).observed' "$WORK/live.jsonl")" "$new"
  is 'the ledger stores the inverse' \
    "$(jq -r 'select(has("rollback")).rollback' "$WORK/live.jsonl" | grep -c "$key=$orig")" 1
  PC_LEDGER="$WORK/live.jsonl" "$BIN/pc-undo" --last --apply >/dev/null 2>&1
  is 'pc undo restores the original' "$(sysctl -n "$key")" "$orig"
  is 'the undo is ledgered too' "$(wc -l <"$WORK/live.jsonl")" 4
else
  echo 'skip sudo -n unavailable: live sysctl round trip'
fi
is 'the real ledger was never touched' "$( [ -e "$HOME/agents/log/changes.jsonl.pt05" ] && echo yes || echo no)" no

[ $bad = 0 ] && echo 'PASS pc-kernel' || echo 'FAIL pc-kernel'
exit $bad
