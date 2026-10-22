#!/usr/bin/env bash
# pc-timers on a PC_FIXTURE (stub systemctl/journalctl/snap, TZ=UTC): list with CPU s, overlap found and none, free slot and none; mutants without the CI window or the intersection test go red.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
export TZ=UTC PC_FIXTURE="$R/fx" FX="$R/fx"
mkdir -p "$FX/bin"
D=$(date -u -d 2026-10-20 +%s); export PC_NOW=$(( D + 43200 ))
at() { echo $(( D + $1 )); }   # at <seconds after D 00:00>

cat >"$FX/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
sc=system; case " $* " in *" --user "*) sc=user;; esac
case " $* " in *" show "*) cat "$FX/show-$sc.txt" 2>/dev/null;; *) cat "$FX/$sc.json";; esac
EOF
printf '#!/usr/bin/env bash\ncat "$FX/journal.txt"\n' >"$FX/bin/journalctl"
printf '#!/usr/bin/env bash\ncat "$FX/snap.txt"\n' >"$FX/bin/snap"
chmod +x "$FX/bin/"*

us() { echo $(( $1 * 1000000 )); }
cat >"$FX/system.json" <<EOF
[{"unit":"e2scrub_all.timer","activates":"e2scrub_all.service","next":$(us "$(at $((7*86400+11400)))"),"last":$(us "$(at 11400)")},
 {"unit":"fstrim.timer","activates":"fstrim.service","next":null,"last":$(us "$(at 18000)")}]
EOF
cat >"$FX/user.json" <<EOF
[{"unit":"ailearning-ci-daily.timer","activates":"ailearning-ci-daily.service","next":$(us "$(at $((86400+3600)))"),"last":$(us "$(at 3600)")},
 {"unit":"fleet-ci-daily.timer","activates":"fleet-ci-daily.service","next":$(us "$(at $((86400+7800)))"),"last":$(us "$(at 7800)")},
 {"unit":"agent@maintenance.timer","activates":"agent@maintenance.service","next":$(us "$(at $((5*86400+14400)))"),"last":$(us "$(at 14410)")},
 {"unit":"sentinel-check.timer","activates":"sentinel-check.service","next":$(us "$(at 44100)"),"last":$(us "$(at 10800)")},
 {"unit":"notifier.timer","activates":"notifier.service","next":0,"last":$(us "$(at -21600)")},
 {"unit":"snap.fw-notifier.timer","activates":"snap.fw-notifier.service","next":$(us "$(at 43200)"),"last":$(us "$(at 32400)")},
 {"unit":"longjob.timer","activates":"longjob.service","next":0,"last":$(us "$(at 39600)")}]
EOF
# systemd's view: the /etc/systemd/user snap service exited after its 09:00 run; longjob is still active.
printf 'Id=snap.fw-notifier.service\nActiveState=inactive\nExecMainStartTimestamp=@%s\nExecMainExitTimestamp=@%s\n\nId=longjob.service\nActiveState=active\nExecMainStartTimestamp=@%s\nExecMainExitTimestamp=\n' \
  "$(at 32400)" "$(at 32401)" "$(at 39600)" >"$FX/show-user.txt"
printf 'timer: 04:00-05:00\nlast: today at 04:02 UTC\nnext: tomorrow at 04:00 UTC\n' >"$FX/snap.txt"
j() { printf '%s.000000 systemd[%s]: %s\n' "$(at "$1")" "$2" "$3"; }
{
  j -21600 5742 'Started notifier.service - Firmware notifier.'
  j 3600 5742 'Starting ailearning-ci-daily.service - Daily ailearning suite...'
  j 7800 5742 'Starting fleet-ci-daily.service - Nightly fleet suite...'
  for s in 9000 9900 10800; do j $s 5742 'Starting sentinel-check.service - Sentinel...'; j $((s+1)) 5742 'Finished sentinel-check.service - Sentinel.'; done
  j 11400 1 'Starting e2scrub_all.service - Online ext4 check...'
  j 11402 1 'Finished e2scrub_all.service - Online ext4 check.'
  j 12067 5742 'ailearning-ci-daily.service: Consumed 1h 56min 17.099s CPU time over 2h 21min 7.460s wall clock time, 4.8G memory peak.'
  j 13882 5742 'fleet-ci-daily.service: Main process exited, code=exited, status=1/FAILURE'
  j 13882 5742 "fleet-ci-daily.service: Failed with result 'exit-code'."
  j 13882 5742 'Failed to start fleet-ci-daily.service - Nightly fleet suite.'
  j 13882 5742 'fleet-ci-daily.service: Consumed 4min 5.531s CPU time over 1h 41min 22.520s wall clock time, 313.7M memory peak.'
  j 14410 5742 'Starting agent@maintenance.service - Persistent agent maintenance...'
  j 14500 5742 'Finished agent@maintenance.service - Persistent agent maintenance.'
  j 14500 5742 'agent@maintenance.service: Consumed 26.415s CPU time over 1min 30s wall clock time, 2.8G memory peak.'
  j 18000 1 'Starting fstrim.service - Discard unused blocks...'
  j 18040 1 'Reached target shutdown.target - System Shutdown.'
  j 28800 5742 'Started snap.fw-notifier.service - Service for snap application fw-notifier.'
  j 32400 5742 'Started snap.fw-notifier.service - Service for snap application fw-notifier.'
  j 39600 5742 'Started longjob.service - Long job.'
  j 21600 5742 'notifier.service: Consumed 4.900s CPU time over 12h wall clock time, 20M memory peak.'
} >"$FX/journal.txt"
cp "$FX/journal.txt" "$R/journal.overlap"

case $R in /tmp/*) ok 'sandbox: fixture root under /tmp';; *) nok sandbox "$R"; exit 1;; esac

# run_cases <pc-timers> — every assertion below, so a mutant can be run through the same cases.
run_cases() {
  local P=$1 out
  cp "$R/journal.overlap" "$FX/journal.txt"
  printf 'timer: 04:00-05:00\nlast: today at 04:02 UTC\nnext: tomorrow at 04:00 UTC\n' >"$FX/snap.txt"
  out=$("$P" --since 1d | tr -s ' ')
  is 'list: header' "$(head -1 <<<"$out")" 'UNIT SCOPE NEXT LAST_START LAST_END CPU_S RUNS'
  is 'list: CI run with h/min/s CPU' "$(grep '^ailearning' <<<"$out")" 'ailearning-ci-daily.timer user 10-21 01:00 10-20 01:00 10-20 03:21 6977.1 1'
  is 'list: failed run ends at Consumed' "$(grep '^fleet-ci' <<<"$out")" 'fleet-ci-daily.timer user 10-21 02:10 10-20 02:10 10-20 03:51 245.5 1'
  is 'list: shutdown closes a run' "$(grep '^fstrim' <<<"$out")" 'fstrim.timer system - 10-20 05:00 10-20 05:00 - 1'
  is 'list: exited snap unit is not running' "$(grep '^snap.fw' <<<"$out")" 'snap.fw-notifier.timer user 10-20 12:00 10-20 09:00 10-20 09:00 - 2'
  is 'list: active unit stays running' "$(grep '^longjob' <<<"$out")" 'longjob.timer user - 10-20 11:00 running - 1'
  is 'list: snapd pseudo-timer' "$(grep -c '^snapd refresh.timer (pseudo) system tomorrow at 04:00 UTC today at 04:02 UTC window 04:00-05:00' <<<"$out")" 1
  is 'list: sorted by time of day' "$(sed -n '2p;3p' <<<"$out" | cut -d' ' -f1 | tr '\n' ' ')" 'ailearning-ci-daily.timer fleet-ci-daily.timer '
  is 'list --json: pseudo window' "$("$P" --since 1d --json | jq -r '.[] | select(.window) | .window')" '04:00-05:00'

  out=$("$P" --overlap --since 1d | tr -s ' ')
  is 'overlap: CI pair with both CPU s' "$(grep '^ailearning' <<<"$out")" 'ailearning-ci-daily.timer 10-20 01:00-03:21 6977.1 fleet-ci-daily.timer 10-20 02:10-03:51 245.5 71.1'
  is 'overlap: reboot job in the snap window' "$(grep '^agent@maintenance' <<<"$out")" 'agent@maintenance.timer 10-20 04:00-04:01 26.4 snapd-refresh(04:00-05:00) 10-20 04:00-05:00 - 1.5'
  is 'overlap: 2 pairs (frequent, idle, < 30 s left out)' "$(tail -1 <<<"$out")" '2 overlapping pairs in the last 1d'
  is 'overlap --json' "$("$P" --overlap --since 1d --json | jq -c '[.[] | select(.a == "ailearning-ci-daily.timer") | .a_cpu_s, .b_cpu_s, .shared_min]')" '[6977.099,245.531,71.1]'

  out=$("$P" --free 1h --since 1d)
  is 'free: first 1h clear of jobs, CI and snap' "$out" "free: 05:01-06:01 (60m clear of every job in the last 1d, the CI window 00:50-01:50 and snapd's refresh)"
  is 'free --json' "$("$P" --free 1h --since 1d --json | jq -c .)" '{"start":"05:01","end":"06:01","minutes":60}'
  out=$("$P" --free 20h --since 1d); is 'free: none exits 1' "$?" 1
  is 'free: none line' "$out" "none: no 1200m window clear of every job, the CI window and snapd's refresh"

  grep -v 'ailearning' "$R/journal.overlap" >"$FX/journal.txt"
  printf 'timer: 05:30-06:00\n' >"$FX/snap.txt"
  is 'overlap: none' "$("$P" --overlap --since 1d)" 'nothing: no two jobs overlapped in the last 1d'
  "$P" --since 2x >/dev/null 2>&1; is 'bad --since exits 2' "$?" 2
}

T_OUT=$(run_cases "$BIN/pc-timers"); printf '%s\n' "$T_OUT"; grep -q '^FAIL' <<<"$T_OUT" && bad=1

# mutant <name> <sed-expr> — a copy of pc-timers with the edit must fail at least one case.
mutant() {
  local m="$R/mut-$1"; mkdir -p "$m"; cp "$BIN/pclib.sh" "$m/"; sed "$2" "$BIN/pc-timers" >"$m/pc-timers"; chmod +x "$m/pc-timers"
  cmp -s "$BIN/pc-timers" "$m/pc-timers" && { nok "mutant $1" 'sed changed nothing'; return; }
  (bad=0; run_cases "$m/pc-timers" >/dev/null; exit $bad) && nok "mutant $1" 'still green' || ok "mutant $1 is red"
}
mutant no-ci-window 's/split(ci, p, "-"); busy_(hm(p\[1\]), hm(p\[2\]))//'
mutant no-unit-state 's/^  \$1 == "S".*//'
mutant started-reentry-ignored 's/if (k in op \&\& ob\[k\] == "Started") { emit(k, op\[k\], op\[k\], ""); delete op\[k\] }//'
mutant no-intersection 's/if (b - a < 30) continue; //;s/; if (b <= a) continue$//'
exit $bad
