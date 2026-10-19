#!/usr/bin/env bash
# TSP-008: `pc status --brief`'s FAIL list is the whole verdict table, not a fixed 7-tag list —
# a forced FAIL outside the old list appears in --brief, and --brief agrees with --check.
# Fully sandboxed (FLEET §5.6): a stub PATH and a private probe cache under $WORK; no service,
# no cache and no file of the real machine is touched, proven by the selftest below.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCS="$HERE/../pc-status"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
has() { case "$2" in *"$3"*) ok "$1";; *) nok "$1" "'$3' not in: $2";; esac; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/pc-status"

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
chmod +x "$WORK/bin"/*

seed() { printf '%s\n%s\n' "$(date +%s)" "$2" >"$WORK/pc-status/$1"; }
seed smart "$(printf 'FAILED\t95\t5\t7')"
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
  *--failed*--user*|*--user*--failed*) echo "fx-user.service loaded failed failed fixture"; [ -z "$FX_TRANSIENT" ] || echo "run-fixture.scope loaded failed failed fixture";;
  *--failed*) echo "apport-autoreport.path loaded failed failed fixture"; echo "fx-sys.service loaded failed failed fixture"; [ -z "$FX_APPORT" ] || echo "apport-autoreport.service loaded failed failed fixture";;
  *list-timers*json*) echo '[{"activates":"fx-cron.service"}]';;
  *list-timers*) exit 0;;
  *list-unit-files*) echo "dark-eye-old.service enabled enabled";;
  *show*) printf 'Id=dark-eye-old.service\nActiveState=inactive\nSubState=dead\nType=simple\nResult=success\nUnitFileState=enabled\n';;
  *is-active*) for a in "$@"; do case "$a" in -*|is-active) ;; *) echo active;; esac; done;;
esac
exit 0
S
cat >"$WORK/fbin/journalctl" <<'S'
#!/bin/sh
case "$*" in
  *MESSAGE_ID*) i=0; while [ $i -lt 12 ]; do echo '{"USER_UNIT":"fx-cron.service"}'; i=$((i+1)); done;;
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
  for f in smart ts_pair tailscale docker docker_expected wifi mode; do cp "$WORK/pc-status/$f" "$d/pc-status/"; done
  seed_v() { printf '%s\n%s\n' "$(date +%s)" "$2" >"$d/pc-status/$1"; }
  seed_v internet reachable; seed_v screenshot 102400; seed_v lock unlocked; seed_v keepalive ''
  env PATH="$WORK/fbin:$WORK/bin:$PATH" XDG_RUNTIME_DIR="$d" HOME="$WORK/home" PC_PROC="$WORK/proc" \
    PC_REBOOT_FILE="$WORK/reboot-required" ALARMS="${ALARMS:-$WORK/alarms-crit.json}" \
    FAILED_UNITS_IGNORE="apport-autoreport.path" KEEPALIVE_UNITS="" KEEPALIVE_HTTP="" \
    SYSTEMCTL_LOG="$WORK/systemctl.log" FX_TRANSIENT="${FX_TRANSIENT:-}" FX_APPORT="${FX_APPORT:-}" \
    PC_CRASH_DIR="${CRASH_DIR:-$WORK/crash-empty}" "$PCS" "$@"
}
st() { jq -r --arg s "$2" --arg k "$3" '.sections[$s][$k].state + " " + .sections[$s][$k].value' <<<"$1"; }
j=$(run_faults --json)
has "failed units FAIL with names"        "$(st "$j" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
case "$(st "$j" host failed_units)" in *apport*) nok "ignore list drops a documented unit" "$(st "$j" host failed_units)";; *) ok "ignore list drops a documented unit";; esac
has "no transient unit is OK 0"         "$(st "$j" host failed_transient)" "OK 0"
# TSP-044: a failed transient run-* scope is listed apart and does not gate FAIL.
jt=$(FX_TRANSIENT=1 run_faults --json)
has "transient scope listed apart"        "$(st "$jt" host failed_transient)" "WARN 1: user:run-fixture.scope"
has "transient scope not in failed_units" "$(st "$jt" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
case "$(FX_TRANSIENT=1 run_faults --brief)" in *failed_transient*) nok "transient does not reach brief FAIL" "listed";; *) ok "transient does not reach brief FAIL";; esac
# T442: a failed apport upload is a WARN naming the /var/crash report; other failed units stay FAIL.
mkdir -p "$WORK/crash-empty" "$WORK/crash"
printf 'ProblemType: Crash\nDate: Mon Oct 19 08:31:46 2026\nExecutablePath: /usr/bin/fx-crasher\nCoreDump: base64\n' >"$WORK/crash/_usr_bin_fx-crasher.1000.crash"
has "no apport failure is crash_report OK" "$(st "$j" host crash_report)" "OK none"
ja=$(FX_APPORT=1 CRASH_DIR="$WORK/crash" run_faults --json)
has "apport failed is a crash_report WARN" "$(st "$ja" host crash_report)" "WARN /usr/bin/fx-crasher Mon Oct 19 08:31:46 2026"
has "apport is not in failed_units"        "$(st "$ja" host failed_units)" "FAIL 2: fx-sys.service, user:fx-user.service"
has "apport without a report still WARNs"  "$(st "$(FX_APPORT=1 run_faults --json)" host crash_report)" "WARN apport-autoreport.service failed, no report in $WORK/crash-empty"
case "$(FX_APPORT=1 CRASH_DIR="$WORK/crash" run_faults --check)" in *"FAIL host.failed_units:"*apport*) nok "apport not a --check FAIL" "listed";; *) ok "apport not a --check FAIL";; esac
bad_argv=$(grep -v -- '^--user show -p Transient --value \|^show -p Transient --value ' "$WORK/systemctl.log" 2>/dev/null | head -1)
[ -z "$bad_argv" ] && [ -s "$WORK/systemctl.log" ] && ok "selftest: stub saw only show -p Transient" || nok "selftest: stub argv" "${bad_argv:-no calls logged}"
has "swap 99% is FAIL"                    "$(st "$j" resources swap)" "FAIL 99%"
has "reboot pending 11 d is FAIL"         "$(st "$j" host reboot_required)" "FAIL 11 d (linux-image-7.0.0-38-generic linux-base)"
has "netdata CRITICAL is FAIL"            "$(st "$j" host netdata_alerts)" "FAIL 1 CRITICAL, 1 WARNING: mem.swap.used_swap"
has "sentinel 2 h old is FAIL"            "$(st "$j" agents sentinel_age)" "FAIL 120 min"
has "enabled-but-dead fleet unit is FAIL" "$(st "$j" agents fleet)" "FAIL dark-eye-old.service inactive"
has "timer unit loop is FAIL"             "$(st "$j" agents unit_loops)" "FAIL fx-cron.service 12 fails/h"
b=$(run_faults --brief); b=${b##*FAIL=}
for t in failed_units fleet netdata reboot sentinel swap unit_loops; do has "brief lists $t" "$b" "$t"; done
c=$(run_faults --check); crc=$?
{ [ "$crc" = 1 ] && grep -q '^FAIL host.reboot_required: 11 d' <<<"$c"; } \
  && ok "--check exits 1 and names the pending reboot" || nok "--check on live faults" "rc=$crc $c"
# The WARN band: 85% swap, 2-day reboot, WARNING-only alarms, a fresh sentinel tick.
printf 'MemTotal: 32000000 kB\nMemAvailable: 30000000 kB\nSwapTotal: 1000000 kB\nSwapFree: %s kB\n' 150000 >"$WORK/proc/meminfo"
touch -d '2 days ago' "$WORK/reboot-required"; touch "$WORK/home/agents/sentinel/state/last-run"
j=$(ALARMS="$WORK/alarms-warn.json" run_faults --json)
has "swap 85% is WARN"                    "$(st "$j" resources swap)" "WARN 85%"
has "reboot pending 2 d is WARN"          "$(st "$j" host reboot_required)" "WARN 2 d"
has "netdata WARNING only is WARN"        "$(st "$j" host netdata_alerts)" "WARN 1 WARNING"
has "fresh sentinel tick is OK"           "$(st "$j" agents sentinel_age)" "OK 0 min"
nf=$(jq '[.sections[][]|select(.state=="FAIL")]|length' <<<"$j")
[ "$(jq .fails <<<"$j")" = "$nf" ] && ok "WARN rows are not counted as failures" || nok "WARN not counted" "fails=$(jq .fails <<<"$j") FAIL rows=$nf"
rm -f "$WORK/reboot-required"
j=$(run_faults --json)
has "no reboot-required file is OK"       "$(st "$j" host reboot_required)" "OK no"
# T398: a reboot flag without its .pkgs list is read quietly.
printf '*** System restart required ***\n' >"$WORK/reboot-required"; mv "$WORK/reboot-required.pkgs" "$WORK/pkgs.bak"
j=$(run_faults --json 2>"$WORK/rb.err")
has "a reboot flag without .pkgs is 0 d"  "$(st "$j" host reboot_required)" "OK 0 d"
has "a missing .pkgs prints no error"     "$(grep -c 'reboot-required.pkgs' "$WORK/rb.err")" 0
rm -f "$WORK/reboot-required"; mv "$WORK/pkgs.bak" "$WORK/reboot-required.pkgs"

# --- 8. T350: SSH is up while ssh.service OR ssh.socket is active --------------
ssh_row() { seed services "$(printf '%s\n' active active "$1" active active active active "$2")"; st "$(run_fixture --json)" services ssh; }
has "ssh service inactive + socket active is OK" "$(ssh_row inactive active)" "OK active (socket)"
has "ssh service + socket inactive is FAIL"      "$(ssh_row inactive inactive)" "FAIL inactive"
rm -f "$WORK/pc-status/services"

# --- 6. the fixture wrote only into its own cache dir ------------------------
# The real timer may refresh the real entry mid-run; a leak would be the fixture's exact entry.
{ [ "$(sed -n 2p "$WORK/pc-status/internet")" = unreachable ] \
  && [ "$(cat "$real_cache/internet" 2>/dev/null)" != "$(cat "$WORK/pc-status/internet")" ]; } \
  && ok "fixture cache is private to \$WORK" || nok "fixture cache is private" "real cache holds the fixture entry"

exit $bad
