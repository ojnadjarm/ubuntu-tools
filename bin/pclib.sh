#!/usr/bin/env bash
# pclib.sh — shared library for the pc-* scripts. Source it (`. "$BIN/pclib.sh"`), never execute it.
#
# API — one line per function (contract: ~/the-dark-eye/PLAN-PCTOOLS.md §1):
#   pc_usage "<text>" "$@"          remember the usage text; print it and exit 0 when an arg is -h/--help
#   pc_opt "$@"                     parse --json --apply --fresh --seconds N into JSON APPLY FRESH SECONDS_; rest lands in PC_ARGS[]
#                                   declare PC_EXTRA_FLAGS=(--deep --level:) first to route the command's own
#                                   flags (':' = takes a value) into PC_EXTRA[] and, by name, PC_OPT[--level];
#                                   a short value flag also takes it attached (-n30, -n=30). Unknown exits 2,
#                                   naming PC_SUB ("pc kernel") when the caller set it
#   pc_rd <file> [default]          the file's contents, or the default when it is unreadable
#   pc_bat_health                   BAT0's energy_full as a percentage of design (0 when unknown)
#   pc_json '<filter>' [jq-args…]   jq -n with the filter last, so callers pass -c/--arg/--argjson before it
#   pc_root <cmd…>                  timeout ${PC_ROOT_TIMEOUT:-5} sudo -n <cmd…>
#   pc_cmd <name> [args…]           run $PC_FIXTURE/bin/<name> (recorded stdout) when it exists, else the real binary
#   cached <name> <ttl> <cmd…>      stdout of cmd, reused while the cache entry is younger than ttl; FRESH=1 bypasses
#   pc_guard <cmd-string…>          exit 3 with the FLEET §5 line when the command is on the deny-list
#   pc_guard_unit <unit>            exit 3 when the unit is guarded, by bare name or with any type suffix
#   pc_unit_why <unit>              the reason string for a guarded unit, empty when it is allowed
#   pc_id                           base36 id derived from date +%s%N (one fork)
#   pc_read <target>                re-read hook used by pc_apply to verify; override it, or set PC_READ_CMD
#   pc_apply <target> <before> <after> <rollback> <cmd…>   (PC_NESTED=1 in <cmd…>'s env: an inner pc_apply just runs)
#                                   without APPLY prints "would: <target> <before> → <after>"; with it appends the
#                                   ledger entry, runs the command, appends {id,verified,observed} and prints
#                                   "rollback: pc undo <id>" as the last line
# Globals: PC_SYS PC_PROC PC_BAT PC_FIXTURE PC_LEDGER PC_ROOT_TIMEOUT PC_READ_CMD PC_USAGE PC_SUB JSON APPLY FRESH
#          SECONDS_ PC_ARGS[] PC_EXTRA_FLAGS[] PC_EXTRA[] PC_OPT[]

# shellcheck disable=SC2034
# The orchestrator's tmux session and unit are config values (GH11): the guards below refuse by
# whatever they are named on this install, not by a hardcoded vendor name.
# shellcheck source=/dev/null
[ -n "${HARNESS_ENV_LOADED:-}" ] || { _pcl="$(dirname "${BASH_SOURCE[0]}")/env.sh"; [ -r "$_pcl" ] && . "$_pcl"; unset _pcl; }
: "${ORCHESTRATOR_TMUX_SESSION:=claude}" "${ORCHESTRATOR_UNIT:=claude-orchestrator.service}"
ORCHESTRATOR_UNIT_BASE="${ORCHESTRATOR_UNIT%.*}"

: "${PC_FIXTURE:=}"
[ -n "$PC_FIXTURE" ] && { PC_SYS="$PC_FIXTURE/sys"; PC_PROC="$PC_FIXTURE/proc"; }
: "${PC_SYS:=/sys}" "${PC_PROC:=/proc}" "${PC_ROOT_TIMEOUT:=5}" "${PC_USAGE:=}" "${PC_SUB:=}"
: "${PC_LEDGER:=$HOME/agents/log/changes.jsonl}"
: "${JSON:=0}" "${APPLY:=0}" "${FRESH:=0}" "${SECONDS_:=0}"
PC_EXTRA_FLAGS=("${PC_EXTRA_FLAGS[@]:-}"); [ -z "${PC_EXTRA_FLAGS[0]}" ] && PC_EXTRA_FLAGS=()
PC_EXTRA=()
declare -A PC_OPT=()

pc_usage() {
  PC_USAGE=$1; shift
  local a; for a in "$@"; do case $a in -h|--help) printf '%s\n' "$PC_USAGE"; exit 0;; esac; done
}

pc_opt() {
  PC_ARGS=(); PC_EXTRA=(); PC_OPT=()
  local d f v
  while [ $# -gt 0 ]; do
    case $1 in
      --json) JSON=1;; --apply) APPLY=1;; --fresh) FRESH=1;;
      --seconds) SECONDS_=$2; shift;; --seconds=*) SECONDS_=${1#*=};;
      -h|--help) printf '%s\n' "$PC_USAGE"; exit 0;;
      --) shift; PC_ARGS+=("$@"); break;;
      -?*)
        f=
        for d in ${PC_EXTRA_FLAGS[@]+"${PC_EXTRA_FLAGS[@]}"}; do
          [ "$d" = "$1" ] && { f=$d; v=1; PC_EXTRA+=("$1"); break; }
          case $d in *:) d=${d%:};; *) continue;; esac
          case $1 in
            "$d")   f=$d; v=${2-}; shift; PC_EXTRA+=("$d" "$v");;
            "$d"=*) f=$d; v=${1#*=}; PC_EXTRA+=("$1");;
            # A short flag may carry its value attached: -n30, -n=30.
            "$d"*)  case $d in --*) continue;; esac
                    f=$d; v=${1#"$d"}; v=${v#=}; PC_EXTRA+=("$d" "$v");;
            *) continue;;
          esac
          break
        done
        [ -n "$f" ] || { printf '%s: unknown option %s\n' "${PC_SUB:-pc}" "$1" >&2; exit 2; }
        PC_OPT[$f]=$v
        ;;
      *) PC_ARGS+=("$1");;
    esac
    shift
  done
}

## --- sysfs reads shared by more than one subcommand -------------------------
# pc_rd <file> [default] — the file's first read, or the default when it is unreadable.
pc_rd() { [ -r "$1" ] && printf '%s' "$(<"$1")" || printf '%s' "${2-}"; }
PC_BAT="$PC_SYS/class/power_supply/BAT0"
# pc_bat_health — energy_full as a percentage of energy_full_design, 0 when either is missing.
pc_bat_health() {
  local n d; n=$(pc_rd "$PC_BAT/energy_full" 0); d=$(pc_rd "$PC_BAT/energy_full_design" 0)
  [ "${d:-0}" -gt 0 ] && printf '%d' $(( n * 100 / d )) || printf 0
}

pc_json() { local f=$1; shift; jq -n "$@" "$f"; }
pc_root() { timeout "$PC_ROOT_TIMEOUT" sudo -n "$@"; }
pc_cmd() {
  local n=$1; shift
  [ -n "$PC_FIXTURE" ] && [ -x "$PC_FIXTURE/bin/$n" ] && { "$PC_FIXTURE/bin/$n" "$@"; return; }
  "$n" "$@"
}

## --- probe cache (moved verbatim from pc-status; EF04/EF09) -----------------
# The slow probes (SMART under sudo, tailscale, docker, gsettings, a screenshot, `claude agents`)
# change on a scale of minutes; cache their *parsed* result so a warm run forks almost nothing.
# TTLs: 60 s for anything the sentinel repairs (docker, tailscale), 900 s (the sentinel's own
# tick cadence) for what it only reads (wifi, lock, mode, screenshot), longer for what moves in
# hours (SMART 1 h, DNS 1 h) or only on an edit (compose files 24 h).
# `--fresh` bypasses every entry; entries live in $XDG_RUNTIME_DIR so a reboot clears them.
CACHE="${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/pc-status}"
: "${CACHE:=/tmp/pc-status-$UID}"
[ -d "$CACHE" ] || mkdir -p "$CACHE" 2>/dev/null
printf -v NOW '%(%s)T' -1
# cached <name> <ttl-seconds> <cmd...> — stdout of cmd, reused while the entry is younger than ttl.
cached() {
  local name=$1 ttl=$2 f data ts; shift 2
  f="$CACHE/$name"
  if [ "$FRESH" = 0 ] && [ -r "$f" ]; then
    data=$(<"$f"); ts=${data%%$'\n'*}
    if [ -n "$ts" ] && [ "$ts" -le "$NOW" ] 2>/dev/null && [ $((NOW - ts)) -lt "$ttl" ]; then
      [ "$data" = "$ts" ] || printf '%s\n' "${data#*$'\n'}"
      return 0
    fi
  fi
  data=$("$@" 2>/dev/null)
  # Write straight to the cache file (no temp+mv fork) so the timestamp always advances.
  printf '%s\n%s\n' "$NOW" "$data" >"$f" 2>/dev/null
  printf '%s\n' "$data"
}

## --- guard (PLAN-PCTOOLS §1 rule 6 / FLEET §5) ------------------------------
PC_FLEET_LINE="FLEET §5: monitor config, power state, sshd/ufw/sudoers/tailscaled, the orchestrator tmux session ($ORCHESTRATOR_TMUX_SESSION), dark-eye.service and fan control are not ours to change."
# pc_unit_why <unit> — the refusal reason for a guarded unit, empty when it is allowed.
# Matched on the bare name, so "ssh", "ssh.service" and "ssh.socket" are all the same unit
# (pc_guard's command-string patterns only ever saw the spelling the caller happened to use).
pc_unit_why() {
  local u=${1##*/} base=${1##*/}
  case $u in *.service|*.socket|*.timer|*.target|*.path|*.mount|*.slice|*.scope) base=${u%.*};; esac
  case $base in
    ssh|sshd|ufw|tailscaled) printf 'a second access path';;
    "$ORCHESTRATOR_UNIT_BASE") printf '%s' "$ORCHESTRATOR_UNIT_BASE";;
    dark-eye|dark-eye-ptt|dark-eye-failed) [ "${PC_ORCHESTRATOR:-0}" = 1 ] || printf 'dark-eye.service';;
  esac
}
pc_guard_unit() {
  local why; why=$(pc_unit_why "$1")
  [ -z "$why" ] && return 0
  printf 'pc: refused (%s) — %s\n' "$why" "$PC_FLEET_LINE" >&2
  exit 3
}

pc_guard() {
  local s="$*" why= w words=()
  case $s in
    *DisplayConfig.Apply*|*DisplayConfig*Apply*|*ApplyMonitorsConfig*|*ApplyConfiguration*|*SetBacklight*) why='monitor config';;
    *login1*Reboot*|*login1*PowerOff*|*login1*Suspend*|*login1*Hibernate*|*login1*HybridSleep*) why='power state';;
    *systemd1*StopUnit*ssh*|*systemd1*RestartUnit*ssh*|*systemd1*StopUnit*ufw*|*systemd1*RestartUnit*ufw*|\
    *systemd1*StopUnit*tailscaled*|*systemd1*RestartUnit*tailscaled*) why='a second access path';;
    *systemctl*ssh*|*systemctl*ufw*|*systemctl*tailscaled*) why='a second access path';;
    *org.gnome.Shell*Eval*|*Shell.Eval*) why='org.gnome.Shell.Eval (arbitrary code in the shell)';;
    *SessionManager*Logout*|*SessionManager*Reboot*|*SessionManager*Shutdown*) why='the session';;
    *ScreenSaver*SetActive*true*) why='locking the screen';;
    */etc/sudoers*|*/etc/ssh*|*/etc/ufw*) why='access configuration';;
    *tmux*kill*"$ORCHESTRATOR_TMUX_SESSION"*) why="the orchestrator's tmux session";;
    *pwm1_enable*) why='fan control';;
  esac
  # A unit-manipulating command is checked word by word as well, so a bare "dark-eye" or
  # the orchestrator unit is refused exactly like "dark-eye.service".
  if [ -z "$why" ]; then
    case $s in
      *systemctl*|*StopUnit*|*RestartUnit*|*StartUnit*|*ReloadUnit*|*KillUnit*|*"pc units"*)
        read -ra words <<<"$s"
        for w in ${words[@]+"${words[@]}"}; do
          case $w in -*|--) continue;; esac
          why=$(pc_unit_why "$w"); [ -n "$why" ] && break
        done;;
      *dark-eye.service*) [ "${PC_ORCHESTRATOR:-0}" = 1 ] || why='dark-eye.service';;
    esac
  fi
  [ -z "$why" ] && return 0
  printf 'pc: refused (%s) — %s\n' "$why" "$PC_FLEET_LINE" >&2
  exit 3
}

## --- change ledger ----------------------------------------------------------
# base36 id from the nanosecond clock — short, sortable, collision-free per machine.
pc_id() {
  local n d=0 out= digits=0123456789abcdefghijklmnopqrstuvwxyz
  n=$(date +%s%N)
  while [ "$n" -gt 0 ]; do d=$((n % 36)); out="${digits:d:1}$out"; n=$((n / 36)); done
  printf '%s\n' "$out"
}
# Default re-read hook: whatever PC_READ_CMD evaluates to. Override pc_read for anything richer.
pc_read() { [ -n "${PC_READ_CMD:-}" ] && eval "$PC_READ_CMD"; }

pc_apply() {
  local target=$1 before=$2 after=$3 rollback=$4; shift 4
  pc_guard "$@"
  # A replay (pc undo) or a verb calling another verb records once, at the outer pc_apply.
  [ "${PC_NESTED:-0}" = 1 ] && { "$@"; return $?; }
  if [ "$APPLY" != 1 ]; then
    printf 'would: %s %s → %s\n' "$target" "$before" "$after"
    return 0
  fi
  local id ts rc observed verified
  id=$(pc_id); printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  [ -d "${PC_LEDGER%/*}" ] || mkdir -p "${PC_LEDGER%/*}" 2>/dev/null
  pc_json '{ts:$ts,id:$id,session:$se,cmd:$c,target:$t,before:$b,after:$a,rollback:$r,read:$rd}' -c \
    --arg ts "$ts" --arg id "$id" --arg se "${CLAUDE_SESSION_ID:-}" --arg c "$*" \
    --arg t "$target" --arg b "$before" --arg a "$after" --arg r "$rollback" \
    --arg rd "${PC_READ_CMD:-}" >>"$PC_LEDGER"
  PC_NESTED=1 "$@"; rc=$?
  observed=$(pc_read "$target" 2>/dev/null)
  verified=false; [ "$observed" = "$after" ] && verified=true
  pc_json '{id:$id,verified:$v,observed:$o}' -c --arg id "$id" --argjson v "$verified" --arg o "$observed" >>"$PC_LEDGER"
  printf 'rollback: pc undo %s\n' "$id"
  return $rc
}
