#!/usr/bin/env bash
# Load-aware wall budget: `budget <base_s>` prints base × clamp(max(load/nproc × K, 1 + psi/20), 1, CAP) (T465, T616).
# psi is `some avg10` of /proc/pressure/cpu: live CPU pressure, where the 1-min load trails by ~60 s; no file = load only.
# Source it from a test, or run `budget.sh <base_s>`. PC_LOADAVG, PC_PSI (files) and PC_NPROC are fixtures,
# as in pc-doctor (T432). K=4 keeps the base up to 0.25 load per CPU; CAP=8 keeps a 10× regression red.
budget() {
  local load np psi=0 psif=${PC_PSI:-/proc/pressure/cpu}
  read -r load _ <"${PC_LOADAVG:-/proc/loadavg}"; np=${PC_NPROC:-$(nproc)}
  [[ -r $psif ]] && psi=$(awk '$1=="some"{sub("avg10=","",$2); print $2}' "$psif")
  awk -v b="$1" -v l="$load" -v n="$np" -v p="${psi:-0}" \
    'BEGIN{f=l/n*4; if(1+p/20>f)f=1+p/20; if(f<1)f=1; if(f>8)f=8; printf "%.3f\n", b*f}'
}
[[ ${BASH_SOURCE[0]} == "$0" ]] && budget "${1:?usage: budget.sh <base_s>}"
true
