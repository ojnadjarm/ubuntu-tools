#!/usr/bin/env bash
# qa-metrics.sh [--baseline] [module…] — lines, duplication and lint counts per Phase D module.
# Columns: lines (wc -l), dupes (jscpd clones, --min-tokens 40), shellcheck (-S warning findings),
# ccn>15 (lizard, python only — it has no bash frontend). --baseline writes BASELINE-QA.tsv.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$(dirname "$here")"
BASELINE="$here/BASELINE-QA.tsv"

# jscpd comes from the nvm node, absent from non-login shells (KB/quirks.md "Shell scripting").
command -v jscpd >/dev/null || PATH="$HOME/.nvm/versions/node/v24.20.0/bin:$PATH"

declare -A MODULE=(
  [pclib]="pclib.sh"
  [desktop]="pc-a11y-click pc-click pc-click-text pc-drag pc-find pc-key pc-move pc-scroll pc-see pc-shot pc-tree pc-type pc-wait pc-wait-for pc-win a11y_tree.py ocr_find.py pc_input.py portal_shot.py screenshot.sh rd_type.py"
  [kernel]="pc-hw pc-io pc-kernel pc-net pc-power pc-thermal pc-top pc-trace pc_top.py"
  [session]="pc-audio pc-bt pc-dbus pc-input pc-mutter pc_dbus.py"
  [services]="pc-docker pc-journal pc-units"
  [status]="pc-doctor pc-status"
  [sentinel]="sentinel-check sentinel-runaway"
  [pcbench]="pcbench pcbench.d/fingerprint.sh"
  [fleet]="agent-disable agent-enable agent-exec agent-now agent-preflight agent-run agents-log agents-start agents-status agents-stop fleetlib.sh harness maintenance-run moodle-keep notify-owner"
)
ORDER=(pclib desktop kernel session services status sentinel pcbench fleet all)

BASE=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --baseline) BASE=1;;
    -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]}" | cut -c3-; exit 0;;
    -*) echo "qa-metrics.sh: unknown option $a" >&2; exit 2;;
    *) [ -n "${MODULE[$a]:-}" ] || [ "$a" = all ] || { echo "qa-metrics.sh: unknown module $a" >&2; exit 2; }
       ARGS+=("$a");;
  esac
done
[ ${#ARGS[@]} -gt 0 ] && ORDER=("${ARGS[@]}")

# files <module> — existing paths, one per line, sorted so two runs agree.
files() {
  if [ "$1" = all ]; then
    find "$bin" -path "$bin/tests" -prune -o -type f -print | sort
  else
    local f; for f in ${MODULE[$1]}; do printf '%s/%s\n' "$bin" "$f"; done | sort
  fi | while read -r f; do
    [ -f "$f" ] || continue
    case "$(head -c 2 "$f")$f" in '#!'*|*.sh|*.py) printf '%s\n' "$f";; esac
  done
}

is_shell() { case "$1" in *.py) return 1;; esac; head -1 "$1" | grep -q 'sh$'; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

metrics() {                       # metrics <module> -> "lines dupes shellcheck ccn"
  local m=$1 lines=0 dupes=0 sc=0 ccn=0 f n sh=() py=() all_f=()
  mapfile -t all_f < <(files "$m")
  [ ${#all_f[@]} -eq 0 ] && { echo "0 0 0 0"; return; }
  rm -rf "$tmp/src" "$tmp/out"; mkdir -p "$tmp/src" "$tmp/out"
  for f in "${all_f[@]}"; do
    n=$(wc -l <"$f"); lines=$((lines + n))
    if is_shell "$f"; then sh+=("$f"); cp "$f" "$tmp/src/${f##*/}.sh"
    else py+=("$f"); cp "$f" "$tmp/src/${f##*/}"; fi
  done
  [ ${#sh[@]} -gt 0 ] && sc=$(shellcheck -S warning -f gcc "${sh[@]}" 2>/dev/null | grep -c .)
  [ ${#py[@]} -gt 0 ] && ccn=$(lizard -w -T cyclomatic_complexity=15 "${py[@]}" 2>/dev/null | grep -c .)
  jscpd --min-tokens 40 --reporters json --output "$tmp/out" --silent --format 'bash,python' \
    "$tmp/src" >/dev/null 2>&1
  [ -r "$tmp/out/jscpd-report.json" ] && dupes=$(jq '.statistics.total.clones' "$tmp/out/jscpd-report.json")
  echo "$lines $dupes $sc $ccn"
}

out="module	lines	dupes	shellcheck	ccn>15"
for m in "${ORDER[@]}"; do
  read -r l d s c < <(metrics "$m")
  out="$out"$'\n'"$m	$l	$d	$s	$c"
done

if [ "$BASE" = 1 ]; then
  printf '%s\n' "$out" >"$BASELINE"
  echo "wrote $BASELINE"
fi
printf '%s\n' "$out" | column -t -s$'\t'
