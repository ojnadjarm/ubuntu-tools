#!/usr/bin/env bash
# One night of the push log: a disk alert sent three times with a rising number, plus noise.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
rm -rf "$WORK"; mkdir -p "$WORK"
y=$(date -d yesterday +%F); t=$(date +%F)
{
printf '%sT23:10:02+02:00\tsent\tdefault\tMoodle 5.2 weekly backup done · moodle-keep\n' "$y"
printf '%sT00:30:11+02:00\tsent\thigh\tbattery health 72%% · power-watch\n' "$t"
printf '%sT00:31:40+02:00\tdup\thigh\tbattery health 72%% · power-watch\n' "$t"
printf '%sT01:05:00+02:00\tsent\tdefault\tdisk / at 91%% used · sentinel-check\n' "$t"
printf '%sT02:05:00+02:00\tsent\tdefault\tdisk / at 92%% used · sentinel-check\n' "$t"
printf '%sT02:40:13+02:00\tdup\thigh\tbattery health 72%% · power-watch\n' "$t"
printf '%sT03:05:00+02:00\tsent\tdefault\tdisk / at 93%% used · sentinel-check\n' "$t"
} > "$WORK/notify.log"
ledger_mark
