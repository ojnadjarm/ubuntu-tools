#!/usr/bin/env bash
# PT07: pc hw against tests/fixtures/hw (lspci/lsusb/dmidecode/lscpu/lsblk/smartctl/sensors/
# fwupdmgr) — summary lines, JSON schema, the 24 h cache on dmi/pci/cpu, and a live wall budget.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/hw"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
fx() { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-hw" "$@"; }

# 1. summary: the five sanity-check tokens each on their own line, one match each.
S=$(fx summary)
is 'summary is non-empty' "$([ -n "$S" ] && echo yes)" yes
is 'summary carries the 5 sanity tokens once each' \
  "$(grep -cE 'X1503ZA|12500H|Iris|PASSED|MT7921' <<<"$S")" 5

# 2. pci: parsed from the fixture lspci -vmm -k, >5 devices, GPU driver resolved.
P=$(fx pci --json)
is 'pci device count > 5' "$([ "$(jq 'length' <<<"$P")" -gt 5 ] && echo yes)" yes
is 'gpu driver is i915' "$(jq -r '.[] | select(.class|test("VGA")) | .driver' <<<"$P")" i915

# 3. usb: parsed from the fixture lsusb.
U=$(fx usb --json)
is 'usb device count' "$(jq 'length' <<<"$U")" 5
is 'razer mouse is present' \
  "$(jq -r '[.[] | select(.id=="1532:0084")] | length' <<<"$U")" 1

# 4. dmi: system + bios fields from the fixture dmidecode.
D=$(fx dmi --json)
is 'dmi product'      "$(jq -r .product <<<"$D")" 'Vivobook_ASUSLaptop X1503ZA_X1503ZA'
is 'dmi bios version'  "$(jq -r .bios_version <<<"$D")" X1503ZA.301

# 5. cpu: model + topology from the fixture lscpu -J.
C=$(fx cpu --json)
is 'cpu model'   "$(jq -r .model <<<"$C")" '12th Gen Intel(R) Core(TM) i5-12500H'
is 'cpu cores'   "$(jq -r .cores_per_socket <<<"$C")" 12
is 'cpu threads' "$(jq -r .cpus <<<"$C")" 16

# 6. mem: both DIMMs, distinct sizes (the two-block dmidecode parse does not collide).
M=$(fx mem --json)
is 'dimm count' "$(jq '.dimms|length' <<<"$M")" 2
is 'dimm sizes are 8 GB and 32 GB' "$(jq -r '[.dimms[].size]|sort|join(",")' <<<"$M")" '32 GB,8 GB'
is 'total_kb from meminfo' "$(jq -r .total_kb <<<"$M")" 39706916

# 7. block: nvme0n1 present with its model, loop devices filtered out.
B=$(fx block --json)
is 'nvme0n1 is present' "$(jq -r '.[] | select(.name=="nvme0n1") | .model' <<<"$B")" 'INTEL SSDPEKNU512GZ'
is 'loop devices are filtered' "$(jq '[.[] | select(.type=="loop")] | length' <<<"$B")" 0

# 8. firmware: only via its own verb or `all --firmware`.
F=$(fx firmware --json)
is 'firmware device count' "$(jq 'length' <<<"$F")" 2
is 'all --json omits firmware by default' "$(fx all --json | jq '.firmware')" '[]'
is 'all --json --firmware includes it' "$(fx all --json --firmware | jq '.firmware|length')" 2

# 9. all: the ticket's success-check intent (its literal jq line has a precedence bug —
# `.pci|length>5 and (...)` pipes .pci into the whole and-expression; parenthesised it passes).
A=$(fx all --json)
is 'all carries every section' \
  "$(jq -r 'keys|sort|join(",")' <<<"$A")" 'block,cpu,dmi,firmware,mem,pci,sensors,usb'
is 'ticket success check (parenthesised)' \
  "$(jq -e '(.pci|length>5) and (.block[]|select(.name=="nvme0n1"))' <<<"$A" >/dev/null && echo true)" true

# 10. errors: unknown verb/option exit 2, -h exits 0, `pc help` lists it.
fx nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2'   "$?" 2
fx --nosuchflag >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx -h >/dev/null 2>&1; is '-h exits 0' "$?" 0
grep -q '^  pc hw ' <<<"$("$BIN/pc" help)" && ok 'pc help lists pc hw' || nok 'pc help lists pc hw' missing

# 11. cache: a second call to `pci` inside the TTL forks no lspci (only the first does).
rm -f "$WORK/pc-status/hw_pci"
strace -f -e trace=execve -o "$WORK/s1" bash -c "$(printf 'PC_FIXTURE=%q XDG_RUNTIME_DIR=%q %q pci --json' "$FIX" "$WORK" "$BIN/pc-hw")" >/dev/null
strace -f -e trace=execve -o "$WORK/s2" bash -c "$(printf 'PC_FIXTURE=%q XDG_RUNTIME_DIR=%q %q pci --json' "$FIX" "$WORK" "$BIN/pc-hw")" >/dev/null
n1=$(grep -c lspci "$WORK/s1"); n2=$(grep -c lspci "$WORK/s2")
is 'first pci call forks lspci'    "$([ "$n1" -ge 1 ] && echo yes)" yes
is 'cached pci call forks no lspci' "$n2" 0

# 12. live wall budget (real machine, not the fixture) — cold ≤ 1.5 s, warm ≤ 0.5 s.
RT=$(mktemp -d); trap 'rm -rf "$WORK" "$RT"' EXIT
cold=$(XDG_RUNTIME_DIR="$RT" /usr/bin/time -f '%e' "$BIN/pc-hw" summary --fresh 2>&1 >/dev/null | tail -1)
warm=$(XDG_RUNTIME_DIR="$RT" /usr/bin/time -f '%e' "$BIN/pc-hw" summary 2>&1 >/dev/null | tail -1)
awk -v c="$cold" 'BEGIN{exit !(c<=1.5)}' && ok "live cold <= 1.5s ($cold)" || nok 'live cold budget' "$cold"
awk -v w="$warm" 'BEGIN{exit !(w<=0.5)}' && ok "live warm <= 0.5s ($warm)" || nok 'live warm budget' "$warm"

[ $bad = 0 ] && echo 'PASS pc-hw' || echo 'FAIL pc-hw'
exit $bad
