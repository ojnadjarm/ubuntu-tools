#!/usr/bin/env bash
# TSP-008: `pc status --brief`'s FAIL list is the whole verdict table, not a fixed 7-tag list —
# a forced FAIL outside the old list appears in --brief, and --brief agrees with --check.
# Fully sandboxed (FLEET §5.6): a stub PATH and a private probe cache under $WORK; no service,
# no cache and no file of the real machine is touched, proven by the selftest below.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCS="$HERE/../pc-status"
. "$HOME/agents/bin/tests/lib/assert.sh"
has() { case "$2" in *"$3"*) ok "$1";; *) nok "$1" "'$3' not in: $2";; esac; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/pc-status"
# maintenance-run's dry run is a stub everywhere (T1072): FX_GATE picks its verdict, each call is logged.
cat >"$WORK/maint-run" <<'S'
#!/bin/sh
echo "$* settle=${MAINT_GATE_SETTLE-unset}" >>"$MAINT_LOG"
case "$FX_GATE" in
  refused) echo "REBOOT REFUSED: pc-status-check(host.failed_units: 1: fx.service)";;
  *) echo "REBOOT ALLOWED: all gates passed";;
esac
S
chmod +x "$WORK/maint-run"
export PC_MAINT_RUN="$WORK/maint-run" MAINT_LOG="$WORK/maint.log" FX_GATE=allowed
# `pc kernel oom` is a stub everywhere (T1105): it prints $FX_OOM (or exits 1 without it) and logs its argv.
cat >"$WORK/kernel" <<'S'
#!/bin/sh
echo "$*" >>"$KERNEL_LOG"
[ -n "$FX_OOM" ] && [ -r "$FX_OOM" ] || exit 1
cat "$FX_OOM"
S
chmod +x "$WORK/kernel"
export PC_KERNEL="$WORK/kernel" KERNEL_LOG="$WORK/kernel.log" FX_OOM=

# --- the fixture: stub binaries + a pre-seeded probe cache -------------------
cat >"$WORK/bin/df" <<'S'
#!/bin/sh
echo "Filesystem Size Used Avail Use% Mounted on"
echo "/dev/fake 100G 99G 1G 99% /"
S
cat >"$WORK/bin/sensors" <<'S'
#!/bin/sh
echo '{"fake":{"t":{"temp1_input":99.0}}}'
S
cat >"$WORK/bin/systemctl" <<'S'
#!/bin/sh
case "$*" in
  *list-timers*) exit 0;;
  *is-active*) for a in "$@"; do case "$a" in -*|is-active) ;; *) echo inactive;; esac; done;;
esac
exit 0
S
printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/ping"
# A refusing sudo, like run.sh's shim (T1136): a direct run never reads SMART or oomctl as root.
printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/sudo"
chmod +x "$WORK/bin"/*

seed() { printf '%s\n%s\n' "$(date +%s)" "$2" >"$WORK/pc-status/$1"; }
seed io_smart '{"smart_status":{"passed":false},"nvme_smart_health_information_log":{"percentage_used":95,"available_spare":5,"media_errors":7}}'
seed ts_pair "$(printf 'Stopped\t100.0.0.1')"
seed tailscale '{}'
seed docker ''
seed docker_expected ''
seed internet unreachable
seed screenshot 0
seed wifi none
seed lock unlocked
seed mode agent
seed keepalive "$(printf 'vass-frontend.service failed\nhttp-moodle45 502')"
# Info probes no case asserts (pc idle, agents-log, claude, upower, …): one fixture read every run reuses.
seed_info() { local k; for k in look_ratio: idle:5 players:none seat_logins:0 claude_sessions:0 time_to_empty: power_profile:balanced dns:; do
  printf '%s\n%s\n' "$(date +%s)" "${k#*:}" >"$1/${k%%:*}"; done
  printf '%s\n%s\n' "$(date +%s)" "1 0" >"$1/oomd"; }
seed_info "$WORK/pc-status"

run_fixture() { env PATH="$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" "$PCS" "$@"; }

# --- 0. selftest: the sandbox really is a sandbox ---------------------------
[ "$(env PATH="$WORK/bin:$PATH" systemctl is-active docker)" = inactive ] \
  && [ "$(systemctl is-active docker 2>/dev/null)" != inactive ] \
  && ok "selftest: stub systemctl shadows the real one (real docker untouched)" \
  || nok "selftest: stub systemctl shadows the real one" "stub or real service state unexpected"
real_cache="${XDG_RUNTIME_DIR:-/run/user/$UID}/pc-status"

# --- 1. a FAIL outside the old 7-tag list reaches --brief -------------------
brief=$(run_fixture --brief)
fails="${brief##*FAIL=}"
has "brief lists a failed service (svc_docker)" "$fails" svc_docker
has "brief lists the dashboard service"        "$fails" svc_dashboard
has "brief lists internet"                     "$fails" internet
has "brief lists screenshot"                   "$fails" screenshot
has "brief still lists the old tags (disk)"    "$fails" disk
has "brief lists a down keepalive unit"       "$fails" ka_vass-frontend.service
has "brief lists a keepalive site not at 200"  "$fails" ka_http-moodle45

# --- 2. the metric: how many tags can appear ---------------------------------
n=$(tr ',' '\n' <<<"$fails" | grep -c .)
[ "$n" -ge 14 ] && ok "brief FAIL list has $n tags (was 7 max)" \
                || nok "brief FAIL list size" "expected >= 14, got $n ($fails)"
case "$fails" in *smart_*) nok "smart_* rolled into smart" "$fails";; *) ok "smart_* rolled into smart";; esac

# --- 3. --brief and --check never disagree -----------------------------------
run_fixture --check >/dev/null 2>&1 && crc=0 || crc=1
{ [ "$crc" = 1 ] && [ "$fails" != none ]; } \
  && ok "--check fails and --brief says so" || nok "--check/--brief agree (fixture)" "rc=$crc FAIL=$fails"
"$PCS" --check >/dev/null 2>&1 && rrc=0 || rrc=1
rfails=$("$PCS" --brief); rfails="${rfails##*FAIL=}"
{ { [ "$rrc" = 0 ] && [ "$rfails" = none ]; } || { [ "$rrc" = 1 ] && [ "$rfails" != none ]; }; } \
  && ok "--check/--brief agree on this machine" || nok "--check/--brief agree" "rc=$rrc FAIL=$rfails"

# --- 4. no second source of truth, no dead helper ----------------------------
grep -q 'BRIEF_TAGS' "$PCS" && nok "BRIEF_TAGS removed" "still present" || ok "BRIEF_TAGS removed"
grep -q 'ok_if' "$PCS" && nok "dead ok_if removed" "still present" || ok "dead ok_if removed"

# --- 5. the brief line shape the hook and harness parse is unchanged ---------
case "$brief" in
  *" lid="*" wifi="*" ts="*" docker="*" disk="*" ram="*" load="*" temp="*" smart="*" wear="*" bhealth="*" lock="*" mode="*" tmux="*" timers="*" FAIL="*)
    ok "brief keeps its field order";;
  *) nok "brief keeps its field order" "$brief";;
esac

# --- 5b. F11: a 15-min-old look ratio is reused, not rebuilt every sentinel tick
lr_ts=$(( $(date +%s) - 900 ))
printf '%s\n%s\n' "$lr_ts" "TOTAL 1 2 0.42" >"$WORK/pc-status/look_ratio"
ratio=$(run_fixture --json | jq -r '.pc_look_ratio_24h')
{ [ "$ratio" = 0.42 ] && [ "$(head -1 "$WORK/pc-status/look_ratio")" = "$lr_ts" ]; } \
  && ok "look_ratio cache survives a 15-min tick" || nok "look_ratio cache survives a 15-min tick" "ratio=$ratio"

# --- 5c. F15: lock state comes from LockedHint alone; lockcheck.sh is not run
mkdir -p "$WORK/lockbin"
cat >"$WORK/lockbin/loginctl" <<'S'
#!/bin/sh
case "$*" in *LockedHint*) echo yes;; *show-user*) echo s1;; esac
S
printf '#!/bin/sh\ntouch "%s/gsettings.called"\n' "$WORK" >"$WORK/lockbin/gsettings"
chmod +x "$WORK/lockbin"/*
rm -f "$WORK/pc-status/lock"
lb=$(env PATH="$WORK/lockbin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" "$PCS" --brief)
[ -e "$WORK/gsettings.called" ] && nok "lock probe skips lockcheck.sh" "gsettings was called" \
                                || ok "lock probe skips lockcheck.sh"
has "lock state read from LockedHint" "$lb" " lock=locked "

# --- 7. T347-10: the live faults reach the verdict table --------------------
# A second fixture: stub systemctl/journalctl/curl, a fake /proc/meminfo, reboot-required file and
# sentinel state under a fake $HOME. Each call gets its own cache dir seeded like the first.
mkdir -p "$WORK/fbin" "$WORK/proc" "$WORK/home/agents/sentinel/state"
cat >"$WORK/fbin/systemctl" <<'S'
#!/bin/sh
case "$*" in
  *Transient*run-fixture.scope*) echo "$*" >>"$SYSTEMCTL_LOG"; echo yes;;
  *Transient*) echo "$*" >>"$SYSTEMCTL_LOG"; echo no;;
  *--failed*--user*|*--user*--failed*) [ -z "$FX_FOREIGN" ] || echo "fx-foreign-cron.service loaded failed failed fixture"; [ "$FX_FOREIGN" = only ] && exit 0
    [ -z "$FX_CI" ] || printf 'ailearning-ci-daily.service loaded failed failed fixture\nfleet-ci-daily.service loaded failed failed fixture\n'; [ "$FX_CI" = only ] && exit 0
    echo "fx-user.service loaded failed failed fixture"; [ -z "$FX_TRANSIENT" ] || echo "run-fixture.scope loaded failed failed fixture";;
  *--failed*) [ "$FX_FOREIGN" = only ] || [ "$FX_CI" = only ] && exit 0; echo "apport-autoreport.path loaded failed failed fixture"; echo "fx-sys.service loaded failed failed fixture"; [ -z "$FX_APPORT" ] || echo "apport-autoreport.service loaded failed failed fixture";;
  *list-timers*json*) echo '[{"activates":"fx-cron.service"},{"activates":"fx-foreign-cron.service"}]';;
  *list-timers*) exit 0;;
  *list-unit-files*) echo "dark-eye-old.service enabled enabled";;
  *NextElapseUSecRealtime*) echo "Sun 2026-10-25 04:00:00 CET";;
  *show*) printf 'Id=dark-eye-old.service\nActiveState=inactive\nSubState=dead\nType=simple\nResult=success\nUnitFileState=enabled\n';;
  *is-active*) for a in "$@"; do case "$a" in -*|is-active) ;; *) echo active;; esac; done;;
esac
exit 0
S
cat >"$WORK/fbin/journalctl" <<'S'
#!/bin/sh
case "$*" in
  *MESSAGE_ID*) [ "$FX_FOREIGN_LOOP" = only ] || { i=0; while [ $i -lt 12 ]; do echo '{"USER_UNIT":"fx-cron.service"}'; i=$((i+1)); done; }
    [ -z "$FX_FOREIGN_LOOP" ] || { i=0; while [ $i -lt 48 ]; do echo '{"USER_UNIT":"fx-foreign-cron.service"}'; i=$((i+1)); done; };;
  *) echo "upgrade pending";;
esac
S
cat >"$WORK/fbin/curl" <<'S'
#!/bin/sh
case "$*" in *alarms*) cat "$ALARMS";; *) printf 200;; esac
S
chmod +x "$WORK/fbin"/*
printf 'MemTotal: 32000000 kB\nMemAvailable: 30000000 kB\nSwapTotal: 1000000 kB\nSwapFree: %s kB\n' 10000 >"$WORK/proc/meminfo"
printf '{"alarms":{"mem.swap.used_swap":{"status":"CRITICAL"},"system.post_update_reboot_status.x":{"status":"WARNING"}}}' >"$WORK/alarms-crit.json"
printf '{"alarms":{"system.post_update_reboot_status.x":{"status":"WARNING"}}}' >"$WORK/alarms-warn.json"
printf '*** System restart required ***\n' >"$WORK/reboot-required"
printf 'linux-image-7.0.0-38-generic\nlinux-base\n' >"$WORK/reboot-required.pkgs"
touch -d '11 days ago' "$WORK/reboot-required"
touch -d '2 hours ago' "$WORK/home/agents/sentinel/state/last-run"
run_faults() {
  local d; d=$(mktemp -d "$WORK/v.XXXX"); mkdir -p "$d/pc-status"
  for f in io_smart ts_pair tailscale docker docker_expected wifi mode; do cp "$WORK/pc-status/$f" "$d/pc-status/"; done
  seed_v() { printf '%s\n%s\n' "$(date +%s)" "$2" >"$d/pc-status/$1"; }
  seed_v internet reachable; seed_v screenshot 102400; seed_v lock unlocked; seed_v keepalive ''; seed_info "$d/pc-status"
  env -u MAINT_GATE_VERDICT_UNITS PATH="$WORK/fbin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$d" HOME="$WORK/home" PC_PROC="$WORK/proc" \
    PC_REBOOT_FILE="${REBOOT_FILE:-$WORK/reboot-required}" ALARMS="${ALARMS:-$WORK/alarms-crit.json}" \
    FAILED_UNITS_IGNORE="apport-autoreport.path" KEEPALIVE_UNITS="" KEEPALIVE_HTTP="" \
    SYSTEMCTL_LOG="$WORK/systemctl.log" FX_TRANSIENT="${FX_TRANSIENT:-}" FX_APPORT="${FX_APPORT:-}" \
    FX_FOREIGN="${FX_FOREIGN:-}" FX_CI="${FX_CI:-}" FX_FOREIGN_LOOP="${FX_FOREIGN_LOOP:-}" PC_NOT_OURS='^fx-foreign' \
    PC_CRASH_DIR="${CRASH_DIR:-$WORK/crash-empty}" "$PCS" "$@"
}
st() { jq -r --arg s "$2" --arg k "$3" '.sections[$s][$k].state + " " + .sections[$s][$k].value' <<<"$1"; }
j=$(run_faults --json)
has "failed units FAIL with names"        "$(st "$j" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
case "$(st "$j" host failed_units)" in *apport*) nok "ignore list drops a documented unit" "$(st "$j" host failed_units)";; *) ok "ignore list drops a documented unit";; esac
has "no transient unit is OK 0"         "$(st "$j" host failed_transient)" "OK 0"
has "no foreign unit is OK 0"           "$(st "$j" host failed_foreign)" "OK 0"
# T721: a failed unit matching PC_NOT_OURS is a WARN row of its own, never a host FAIL.
jf=$(FX_FOREIGN=1 run_faults --json)
has "foreign unit listed apart"         "$(st "$jf" host failed_foreign)" "WARN 1: user:fx-foreign-cron.service (not ours)"
has "foreign unit not in failed_units"  "$(st "$jf" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
jo=$(FX_FOREIGN=only run_faults --json)
has "only foreign failed: failed_units OK 0" "$(st "$jo" host failed_units)" "OK 0"
c=$(FX_FOREIGN=only run_faults --check)
case "$c" in *failed_units*|*failed_foreign*) nok "foreign not a --check FAIL" "$c";; *) ok "foreign not a --check FAIL";; esac
# T1060: failed CI verdict units (MAINT_GATE_VERDICT_UNITS default) are a ci_verdict WARN, never failed_units.
has "no CI verdict is ci_verdict OK none" "$(st "$j" host ci_verdict)" "OK none"
jc=$(FX_CI=only run_faults --json)
has "only CI units failed: failed_units OK 0" "$(st "$jc" host failed_units)" "OK 0"
has "CI units are a ci_verdict WARN"         "$(st "$jc" host ci_verdict)" "WARN 2 red: ailearning-ci-daily, fleet-ci-daily"
c=$(FX_CI=only run_faults --check)
case "$c" in *failed_units*|*ci_verdict*) nok "CI verdict not a --check FAIL" "$c";; *) ok "CI verdict not a --check FAIL";; esac
jc=$(FX_CI=1 run_faults --json)
has "CI + other failed: FAIL names only the other" "$(st "$jc" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
mkdir -p "$WORK/mut"; ln -s "$HERE"/../*.sh "$WORK/mut/"
grep -v 'h_verdict+=' "$PCS" >"$WORK/mut/pc-status"; chmod +x "$WORK/mut/pc-status"
case "$(st "$(FX_CI=only PCS="$WORK/mut/pc-status" run_faults --json)" host failed_units)" in
  FAIL*ci-daily*) ok "mutation: without the verdict branch CI units FAIL again";; *) nok "mutation red" "mutant did not FAIL";; esac
# One run per fixture state: transient scope + apport report + no reboot flag share a run, as do
# the brief, the check and the WARN band; each assert reads only its own rows.
mkdir -p "$WORK/crash-empty" "$WORK/crash"
printf 'ProblemType: Crash\nDate: Mon Oct 19 08:31:46 2026\nExecutablePath: /usr/bin/fx-crasher\nCoreDump: base64\n' >"$WORK/crash/_usr_bin_fx-crasher.1000.crash"
# TSP-044: a failed transient run-* scope is listed apart and does not gate FAIL.
jt=$(FX_TRANSIENT=1 FX_APPORT=1 CRASH_DIR="$WORK/crash" REBOOT_FILE="$WORK/no-reboot-required" run_faults --json)
has "transient scope listed apart"        "$(st "$jt" host failed_transient)" "WARN 1: user:run-fixture.scope"
has "transient scope not in failed_units" "$(st "$jt" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
bb=$(FX_TRANSIENT=1 run_faults --brief); b=${bb##*FAIL=}
case "$bb" in *failed_transient*) nok "transient does not reach brief FAIL" "listed";; *) ok "transient does not reach brief FAIL";; esac
# T442: a failed apport upload is a WARN naming the /var/crash report; other failed units stay FAIL.
has "no apport failure is crash_report OK" "$(st "$j" host crash_report)" "OK none"
has "apport failed is a crash_report WARN" "$(st "$jt" host crash_report)" "WARN /usr/bin/fx-crasher Mon Oct 19 08:31:46 2026"
has "apport is not in failed_units"        "$(st "$jt" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
c=$(FX_APPORT=1 CRASH_DIR="$WORK/crash" run_faults --check); crc=$?
case "$c" in *"FAIL host.failed_units:"*apport*) nok "apport not a --check FAIL" "listed";; *) ok "apport not a --check FAIL";; esac
bad_argv=$(grep -v -- '^--user show -p Transient --value \|^show -p Transient --value ' "$WORK/systemctl.log" 2>/dev/null | head -1)
[ -z "$bad_argv" ] && [ -s "$WORK/systemctl.log" ] && ok "selftest: stub saw only show -p Transient" || nok "selftest: stub argv" "${bad_argv:-no calls logged}"
has "swap 99% is FAIL"                    "$(st "$j" resources swap)" "FAIL 99%"
has "reboot pending 11 d is FAIL"         "$(st "$j" host reboot_required)" "FAIL 11 d (linux-image-7.0.0-38-generic linux-base)"
has "netdata CRITICAL is FAIL"            "$(st "$j" host netdata_alerts)" "FAIL 1 CRITICAL, 1 WARNING: mem.swap.used_swap"
has "sentinel 2 h old is FAIL"            "$(st "$j" agents sentinel_age)" "FAIL 120 min"
has "enabled-but-dead fleet unit is FAIL" "$(st "$j" agents fleet)" "FAIL dark-eye-old.service inactive"
has "timer unit loop is FAIL"             "$(st "$j" agents unit_loops)" "FAIL fx-cron.service 12 fails/h"
has "no foreign unit loop is OK none"     "$(st "$j" agents unit_loops_foreign)" "OK none"
# T734: a timer loop of a unit matching PC_NOT_OURS is a WARN row of its own, never unit_loops.
jl=$(FX_FOREIGN_LOOP=1 run_faults --json)
has "foreign loop listed apart"           "$(st "$jl" agents unit_loops_foreign)" "WARN fx-foreign-cron.service 48 fails/h (not ours)"
case "$(st "$jl" agents unit_loops)" in "FAIL fx-cron.service 12 fails/h: upgrade pending") ok "foreign loop not in unit_loops";; *) nok "foreign loop not in unit_loops" "$(st "$jl" agents unit_loops)";; esac
jl=$(FX_FOREIGN_LOOP=only run_faults --json)
has "only foreign loop: unit_loops OK"    "$(st "$jl" agents unit_loops)" "OK no timer-driven unit failing >= 10/h"
has "no moodle-cron mark is OK"           "$(st "$j" agents moodle_upgrade)" "OK none pending"
for t in failed_units fleet netdata reboot sentinel swap unit_loops; do has "brief lists $t" "$b" "$t"; done
{ [ "$crc" = 1 ] && grep -q '^FAIL host.reboot_required: 11 d' <<<"$c"; } \
  && ok "--check exits 1 and names the pending reboot" || nok "--check on live faults" "rc=$crc $c"
# The WARN band: 85% swap, 2-day reboot, WARNING-only alarms, a fresh sentinel tick, a moodle-cron mark,
# an apport failure without a report.
printf 'MemTotal: 32000000 kB\nMemAvailable: 30000000 kB\nSwapTotal: 1000000 kB\nSwapFree: %s kB\n' 150000 >"$WORK/proc/meminfo"
touch -d '2 days ago' "$WORK/reboot-required"; touch "$WORK/home/agents/sentinel/state/last-run"
mkdir -p "$WORK/home/agents/state"; touch -d '2026-01-01 03:04' "$WORK/home/agents/state/moodle-cron-fx-app-1.pending"
j=$(FX_APPORT=1 ALARMS="$WORK/alarms-warn.json" run_faults --json)
rm -f "$WORK/home/agents/state/moodle-cron-fx-app-1.pending"
has "moodle-cron mark is one WARN"        "$(st "$j" agents moodle_upgrade)" "WARN pending: fx-app-1 since 03:04"
has "apport without a report still WARNs"  "$(st "$j" host crash_report)" "WARN apport-autoreport.service failed, no report in $WORK/crash-empty"
has "swap 85% is WARN"                    "$(st "$j" resources swap)" "WARN 85%"
has "reboot pending 2 d is WARN"          "$(st "$j" host reboot_required)" "WARN 2 d"
has "netdata WARNING only is WARN"        "$(st "$j" host netdata_alerts)" "WARN 1 WARNING"
has "fresh sentinel tick is OK"           "$(st "$j" agents sentinel_age)" "OK 0 min"
nf=$(jq '[.sections[][]|select(.state=="FAIL")]|length' <<<"$j")
[ "$(jq .fails <<<"$j")" = "$nf" ] && ok "WARN rows are not counted as failures" || nok "WARN not counted" "fails=$(jq .fails <<<"$j") FAIL rows=$nf"
has "no reboot-required file is OK none"  "$(st "$jt" host reboot_required)" "OK none"
# T398: a reboot flag without its .pkgs list is read quietly. T466: a fresh box (no USER, no
# KEEPALIVE_*) runs quietly and lists no keepalive row.
mkdir -p "$WORK/rb"; printf '*** System restart required ***\n' >"$WORK/rb/reboot-required"
jf=$( (unset USER; REBOOT_FILE="$WORK/rb/reboot-required" run_faults --json) 2>"$WORK/nouser.err"); frc=$?
has "a reboot flag without .pkgs is 0 d"  "$(st "$jf" host reboot_required)" "OK 0 d"
has "a missing .pkgs prints no error"     "$(grep -c 'reboot-required.pkgs' "$WORK/nouser.err")" 0
{ [ "$frc" = 0 ] && [ ! -s "$WORK/nouser.err" ]; } && ok "unset USER runs quietly" || nok "unset USER" "rc=$frc $(head -1 "$WORK/nouser.err")"
ka=$(jq -c '.sections.keepalive // {}' <<<"$jf")
[ "$ka" = '{}' ] && ok "no KEEPALIVE_* lists no keepalive row" || nok "no KEEPALIVE_* rows" "$ka"

# --- 8. T350: SSH is up while ssh.service OR ssh.socket is active --------------
ssh_row() { seed services "$(printf '%s\n' active active "$1" active active active active "$2")"; st "$(run_fixture --json)" services ssh; }
has "ssh service inactive + socket active is OK" "$(ssh_row inactive active)" "OK active (socket)"
has "ssh service + socket inactive is FAIL"      "$(ssh_row inactive inactive)" "FAIL inactive"
rm -f "$WORK/pc-status/services"

# --- 9. T517: an exited service behind an inactive profile is not a missing service
# Expected services as compose-services prints them; fxtool is profile-only, so it is not listed.
dk_row() { seed docker "$1"; seed docker_expected 'fx|app db '; st "$(run_fixture --json)" docker fx; }
has "inactive profile container exited is 2/2 OK" \
  "$(dk_row "$(printf 'fx|running|fx-app-1||app\nfx|running|fx-db-1||db\nfx|exited|fx-tool-1||tool')")" "OK 2/2 up"
has "an expected service down is still FAIL" \
  "$(dk_row "$(printf 'fx|running|fx-app-1||app\nfx|exited|fx-db-1||db\nfx|exited|fx-tool-1||tool')")" "FAIL 1/2 up"
seed docker ''; seed docker_expected ''

# --- 10. T634: SMART comes from pclib's pc_smart_json (io_smart JSON), no raw sudo
j=$(run_fixture --json)
has "smart health from io_smart"      "$(st "$j" disk smart)" "FAIL FAILED"
has "smart percent_used from io_smart" "$(st "$j" disk percent_used)" "FAIL 95%"
has "smart spare from io_smart"       "$(st "$j" disk available_spare)" "FAIL 5%"
has "smart media_errors from io_smart" "$(st "$j" disk media_errors)" " 7"
[ "$(grep -c 'sudo -n smartctl' "$PCS")" = 0 ] && ok "no raw sudo smartctl" || nok "no raw sudo smartctl" "still present"

# --- 11. T943: --fresh re-probes what the sentinel repairs, slow keys keep their TTL
mkdir -p "$WORK/frbin" "$WORK/fr/pc-status"
printf '#!/bin/sh\necho "fx|exited|fx-app-1||app"\n' >"$WORK/frbin/docker"
printf '#!/bin/sh\necho %s\n' "'{\"BackendState\":\"Running\",\"TailscaleIPs\":[\"100.0.0.9\"]}'" >"$WORK/frbin/tailscale"
chmod +x "$WORK/frbin"/*
cp "$WORK/pc-status"/* "$WORK/fr/pc-status/"
fr() { printf '%s\n%s\n' "$(( $(date +%s) - 120 ))" "$2" >"$WORK/fr/pc-status/$1"; }
fr services "$(printf 'active\n%.0s' 1 2 3 4 5 6 7 8)"; fr docker 'fx|running|fx-app-1||app'
fr look_ratio 'TOTAL 1 2 0.77'; seed_at() { printf '%s\n%s\n' "$(( $(date +%s) - 30 ))" "$2" >"$WORK/fr/pc-status/$1"; }
seed_at unit_loops 'fx-marker.service 99 fails/h'
j=$(env PATH="$WORK/frbin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK/fr" "$PCS" --json --fresh)
has "--fresh re-probes services"        "$(st "$j" services docker)" "FAIL inactive"
has "--fresh re-probes docker"          "$(st "$j" docker fx)" "FAIL 0/1 up"
has "--fresh re-probes tailscale"       "$(st "$j" network tailscale)" "OK Running"
has "--fresh serves look_ratio by TTL"  "$(jq -r .pc_look_ratio_24h <<<"$j")" "0.77"
has "--fresh serves unit_loops by TTL"  "$(st "$j" agents unit_loops)" "FAIL fx-marker.service 99 fails/h"
has "--fresh serves io_smart by TTL"    "$(st "$j" disk smart)" "FAIL FAILED"
# docker_expected keeps its 24 h entry until a compose file is newer than it.
mkdir -p "$WORK/cebin" "$WORK/envs/fx"; printf 'name: fx\n' >"$WORK/envs/fx/docker-compose.yml"
cat >"$WORK/cebin/docker" <<S
#!/bin/sh
case "\$*" in *config_files*) echo "$WORK/envs/fx/docker-compose.yml";; *compose*) printf 'app\nweb\n';;
  *) echo "fx|exited|fx-app-1||app";; esac
S
chmod +x "$WORK/cebin/docker"
ce() { env PATH="$WORK/cebin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK/fr" MOODLE_ENVS_DIR="$WORK/envs" "$PCS" --json --fresh; }
touch -d '1 hour ago' "$WORK/envs/fx/docker-compose.yml"; fr docker_expected 'fx|app '
has "--fresh serves docker_expected by TTL"     "$(st "$(ce)" docker fx)" "FAIL 0/1 up"
fr docker_expected 'fx|app '; touch "$WORK/envs/fx/docker-compose.yml"
has "an edited compose file re-reads docker_expected" "$(st "$(ce)" docker fx)" "FAIL 0/2 up"

# --- 12. T1046: systemd-oomd's monitored cgroups, WARN at 0 ---------------------
has "oomd watching 1 cgroup is OK" "$(st "$(run_fixture --json)" host oomd_monitored)" "OK 1 (pressure 1, swap 0)"
seed oomd "0 0"
has "oomd watching nothing is WARN" "$(st "$(run_fixture --json)" host oomd_monitored)" "WARN 0 (pressure 0, swap 0)"
case "$(run_fixture --brief)" in *oomd*) nok "oomd WARN stays out of brief FAIL" "listed";; *) ok "oomd WARN stays out of brief FAIL";; esac
mkdir -p "$WORK/oobin"
cat >"$WORK/oobin/sudo" <<'S'
#!/bin/sh
[ "$1 $2" = "-n oomctl" ] || exit 1
printf 'Dry Run: no\nSwap Monitored CGroups:\n\tPath: /a.slice\nMemory Pressure Monitored CGroups:\n\tPath: /user.slice/user-%s.slice/user@%s.service\n\t\tMemory Pressure Limit: 50.00%%\n\tPath: /b.service\n' "$(id -u)" "$(id -u)"
S
chmod +x "$WORK/oobin/sudo"; rm -f "$WORK/pc-status/oomd"
has "oomctl sections are counted apart" "$(st "$(env PATH="$WORK/oobin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" "$PCS" --json)" host oomd_monitored)" "OK 3 (pressure 2, swap 1)"
printf '#!/bin/sh\nexit 1\n' >"$WORK/oobin/sudo"; rm -f "$WORK/pc-status/oomd"
has "unreadable oomctl is n/a" "$(st "$(env PATH="$WORK/oobin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" "$PCS" --json)" host oomd_monitored)" "- n/a"
[ ! -s "$WORK/pc-status/oomd" ] && ok "an unreadable oomctl is not cached" || nok "unreadable oomctl not cached" "$(cat "$WORK/pc-status/oomd")"
seed oomd "1 0"

# --- 13. T1072: the reboot row carries the next window's gate verdict --------
: >"$MAINT_LOG"
row() { awk '$1=="reboot_required"' <<<"$1"; }
has "pending reboot: window allowed" "$(row "$(run_faults)")" "d (linux-image-7.0.0-38-generic linux-base) · window Sun 10-25 04:00 allowed"
has "pending reboot: window refused names the gate" "$(row "$(FX_GATE=refused run_faults)")" "window Sun 10-25 04:00 refused: pc-status-check(host.failed_units: 1: fx.service)"
has "no pending reboot: none" "$(row "$(REBOOT_FILE="$WORK/no-reboot-required" run_faults)")" "reboot_required  none"
has "the gate is a dry run that ignores the hour" "$(head -1 "$MAINT_LOG")" "--dry-run --assume-reboot --dry-run-ignore-window"
n=$(wc -l <"$MAINT_LOG"); run_faults --check >/dev/null; run_faults --brief >/dev/null
[ "$(wc -l <"$MAINT_LOG")" = "$n" ] && ok "--check and --brief never run the gate" || nok "--check/--brief ran the gate" "$(cat "$MAINT_LOG")"
: >"$MAINT_LOG"; rm -f "$WORK/pc-status/reboot_gate"
for _ in 1 2; do PC_REBOOT_FILE="$WORK/reboot-required" run_fixture --json >/dev/null; done
[ "$(wc -l <"$MAINT_LOG")" = 1 ] && ok "the gate verdict is cached (1 call for 2 runs)" || nok "gate cache" "$(wc -l <"$MAINT_LOG") calls"
# T1144: a refused verdict is cached 300 s, an allowed one 3600 s; the dry run never settles.
has "the gate dry run asks for no settle wait" "$(head -1 "$MAINT_LOG")" "settle=0"
gate_calls() { # <verdict> <age s> [pc-status] -> maintenance-run calls of one run
  printf '%s\n%s\n' "$(( $(date +%s) - $2 ))" "window Sun 10-25 04:00 $1" >"$WORK/pc-status/reboot_gate"; : >"$MAINT_LOG"
  PCS="${3:-$PCS}" PC_REBOOT_FILE="$WORK/reboot-required" run_fixture --json >/dev/null; wc -l <"$MAINT_LOG"; }
is "refused at 299 s: served from the cache" "$(gate_calls 'refused: pc-status-check(services.fx: deactivating)' 299)" 0
is "refused at 301 s: re-run" "$(gate_calls 'refused: pc-status-check(services.fx: deactivating)' 301)" 1
is "allowed at 301 s: served from the cache" "$(gate_calls allowed 301)" 0
is "allowed at 3601 s: re-run" "$(gate_calls allowed 3601)" 1
sed 's/_rbttl=300/_rbttl=3600/' "$PCS" >"$WORK/mut/pc-status"; chmod +x "$WORK/mut/pc-status"
is "mutation: a refused verdict kept 3600 s is served at 301 s" "$(gate_calls 'refused: pc-status-check(services.fx: deactivating)' 301 "$WORK/mut/pc-status")" 0

# --- 14. T1105: netdata's mem.oom_kill alarm ignores the deliberate memcg kills of run.sh tests
printf '{"alarms":{"mem.oom_kill.oom_kill":{"status":"WARNING"}}}' >"$WORK/alarms-oom.json"
printf '{"alarms":{"mem.oom_kill.oom_kill":{"status":"WARNING"},"system.post_update_reboot_status.x":{"status":"WARNING"}}}' >"$WORK/alarms-oom2.json"
printf '{"count":{"test-cap":182},"kills":[{"class":"test-cap","cmd":"python3"}]}' >"$WORK/oom-test.json"
printf '{"count":{"real":1,"test-cap":182},"kills":[{"class":"real","cmd":"chrome"},{"class":"test-cap","cmd":"python3"}]}' >"$WORK/oom-real.json"
nd_row() { st "$(ALARMS="$WORK/$1" FX_OOM="${2:+$WORK/$2}" run_faults --json)" host netdata_alerts; }
: >"$KERNEL_LOG"
has "test-cap kills only: oom_kill is OK, ignored" "$(nd_row alarms-oom.json oom-test.json)" "OK none (oom_kill: 182 test-cap, ignored)"
has "the classes come from pc kernel oom --since 40m" "$(head -1 "$KERNEL_LOG")" "oom --since 40m --json"
has "one real kill keeps WARN and names it" "$(nd_row alarms-oom.json oom-real.json)" "WARN 1 WARNING: mem.oom_kill.oom_kill (oom_kill: 1 real (chrome), 182 test-cap)"
has "another alarm + test-cap kills: WARN for the other" "$(nd_row alarms-oom2.json oom-test.json)" "WARN 1 WARNING: system.post_update_reboot_status.x (oom_kill: 182 test-cap, ignored)"
has "pc kernel oom unreadable: oom_kill stays WARN" "$(nd_row alarms-oom.json)" "WARN 1 WARNING: mem.oom_kill.oom_kill"
: >"$KERNEL_LOG"; nd_row alarms-warn.json oom-test.json >/dev/null
[ ! -s "$KERNEL_LOG" ] && ok "no oom_kill alarm: pc kernel oom is not called" || nok "pc kernel oom called without the alarm" "$(cat "$KERNEL_LOG")"
sed 's/\] && \[ -z "\$o_other" \]; then$/] \&\& false; then/' "$PCS" >"$WORK/mut/pc-status"; chmod +x "$WORK/mut/pc-status"
case "$(PCS="$WORK/mut/pc-status" nd_row alarms-oom.json oom-test.json)" in
  WARN*mem.oom_kill*) ok "mutation: without the test-cap branch oom_kill WARNs again";; *) nok "mutation red" "mutant did not WARN";; esac

# --- 15. T1114: --timing names each reader; --fresh runs the slow readers side by side
tl=$(run_fixture --timing 2>&1 >/dev/null)
grep -qE '^timing wifi [0-9]+ cached$' <<<"$tl" && ok "--timing: a served entry is 'cached'" || nok "--timing cached line" "$tl"
grep -qE '^timing total [0-9]+ cached$' <<<"$tl" && ok "--timing: a total line" || nok "--timing total line" "$tl"
[ "$(run_fixture --check 2>/dev/null)" = "$(run_fixture --check --timing 2>/dev/null)" ] && ok "--timing leaves stdout alone" || nok "--timing stdout" "differs"
[ -z "$(run_fixture 2>&1 >/dev/null)" ] && ok "no timing lines without --timing" || nok "timing without the flag" "printed"
sed 's/_hit "\$1" "\$2" && s=cached/:/' "$PCS" >"$WORK/mut/pc-status"; chmod +x "$WORK/mut/pc-status"
grep -qE '^timing wifi [0-9]+ cached$' <<<"$(PCS="$WORK/mut/pc-status" run_fixture --timing 2>&1 >/dev/null)" \
  && nok "mutation red" "mutant still says cached" || ok "mutation: without _hit every reader reads 'fresh'"
mkdir -p "$WORK/pbin" "$WORK/par/pc-status"
for c in docker nmcli; do printf '#!/bin/sh\nsleep 0.8\necho "fx|running|fx-app-1||app"\n' >"$WORK/pbin/$c"; done
printf '#!/bin/sh\nsleep 0.8\ncase "$*" in *alarms*) echo "{\\"alarms\\":{}}";; *) printf 200;; esac\n' >"$WORK/pbin/curl"
chmod +x "$WORK/pbin"/*
printf 'KEEPALIVE_UNITS=""\nKEEPALIVE_HTTP="fx=http://127.0.0.1:9/"\n' >"$WORK/par.env"
par() { cp "$WORK/pc-status"/* "$WORK/par/pc-status/"; local t=${EPOCHREALTIME/./}
  env PATH="$WORK/pbin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK/par" HARNESS_CONFIG="$WORK/par.env" \
    "${1:-$PCS}" --json --fresh --timing >"$WORK/par.json" 2>"$WORK/par.err"
  echo $(( (${EPOCHREALTIME/./} - t) / 1000 )); }
ms=$(par)
[ "$ms" -lt 2400 ] && ok "--fresh: four 0.8 s readers take < 2.4 s together ($ms ms)" || nok "readers in parallel" "$ms ms"
has "a parallel reader's value is served"   "$(st "$(cat "$WORK/par.json")" keepalive http-fx)" "OK 200"
has "a parallel docker read is served"      "$(st "$(cat "$WORK/par.json")" docker fx)" "OK 1/1 up"
grep -qE '^timing keepalive [0-9]{3,} fresh$' "$WORK/par.err" && ok "--timing: a parallel reader is timed 'fresh'" || nok "parallel timing line" "$(cat "$WORK/par.err")"
sed 's/^_spawn() {$/_spawn() { return 0/' "$PCS" >"$WORK/mut/pc-status"; chmod +x "$WORK/mut/pc-status"
ms=$(par "$WORK/mut/pc-status")
[ "$ms" -ge 2400 ] && ok "mutation: without _spawn the readers run in series ($ms ms)" || nok "mutation red" "mutant took $ms ms"

# --- 6. the fixture wrote only into its own cache dir ------------------------
# The real timer may refresh the real entry mid-run; a leak would be the fixture's exact entry.
{ [ "$(sed -n 2p "$WORK/pc-status/internet")" = unreachable ] \
  && [ "$(cat "$real_cache/internet" 2>/dev/null)" != "$(cat "$WORK/pc-status/internet")" ]; } \
  && ok "fixture cache is private to \$WORK" || nok "fixture cache is private" "real cache holds the fixture entry"

exit $bad
