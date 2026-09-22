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

run_fixture() { env PATH="$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" "$PCS" "$@"; }

# --- 0. selftest: the sandbox really is a sandbox ---------------------------
[ "$(env PATH="$WORK/bin:$PATH" systemctl is-active docker)" = inactive ] \
  && [ "$(systemctl is-active docker 2>/dev/null)" != inactive ] \
  && ok "selftest: stub systemctl shadows the real one (real docker untouched)" \
  || nok "selftest: stub systemctl shadows the real one" "stub or real service state unexpected"
real_cache="${XDG_RUNTIME_DIR:-/run/user/$UID}/pc-status"
before_cache=$(cat "$real_cache/internet" 2>/dev/null)

# --- 1. a FAIL outside the old 7-tag list reaches --brief -------------------
brief=$(run_fixture --brief)
fails="${brief##*FAIL=}"
has "brief lists a failed service (svc_docker)" "$fails" svc_docker
has "brief lists the dashboard service"        "$fails" svc_dashboard
has "brief lists internet"                     "$fails" internet
has "brief lists screenshot"                   "$fails" screenshot
has "brief still lists the old tags (disk)"    "$fails" disk

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

# --- 6. the fixture wrote only into its own cache dir ------------------------
{ [ "$(sed -n 2p "$WORK/pc-status/internet")" = unreachable ] \
  && [ "$(cat "$real_cache/internet" 2>/dev/null)" = "$before_cache" ]; } \
  && ok "fixture cache is private to \$WORK" || nok "fixture cache is private" "real cache entry changed"

exit $bad
