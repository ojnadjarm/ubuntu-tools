#!/usr/bin/env bash
# PT13: `pc units` — fixture list/timers/failed/cost --all, then live fleet/cost/guard/restart round trip.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/units"
U="$BIN/pc-units"
. "$HOME/agents/bin/tests/lib/assert.sh"
REAL_LEDGER="$HOME/agents/log/changes.jsonl"
real_rows=$(cat "$REAL_LEDGER" 2>/dev/null | wc -l)
export PC_LEDGER; PC_LEDGER=$(mktemp); trap 'rm -f "$PC_LEDGER"' EXIT

## --- fixture: list-units/list-timers, no real systemctl call --------------
is 'list --json is an array of 5 units' \
  "$(PC_FIXTURE=$FIX "$U" list --json | jq 'length')" 5
is 'list --failed --json finds the fixture failed unit' \
  "$(PC_FIXTURE=$FIX "$U" list --failed --json | jq -r '.[0].unit')" pt13-fixture.service
is 'list tags each row with its scope' \
  "$(PC_FIXTURE=$FIX "$U" list --json | jq -r '[.[]|.scope]|unique|sort|join(",")')" system,user
is 'timers --json reads the user fixture' \
  "$(PC_FIXTURE=$FIX "$U" timers --json | jq -r '.[0].unit')" sentinel-check.timer

## --- fixture: resolve_scope (no --user/--system given) --------------------
is 'resolve_scope picks user for a user-only unit' \
  "$(PC_FIXTURE=$FIX "$U" show pt13-user-only --json | jq -r .scope)" user
is 'resolve_scope picks system for a system-only unit' \
  "$(PC_FIXTURE=$FIX "$U" show pt13-system-only --json | jq -r .scope)" system
is 'resolve_scope prefers user when loaded in both and under ~/.config/systemd/user' \
  "$(PC_FIXTURE=$FIX "$U" show pt13-both --json | jq -r .scope)" user
PC_FIXTURE=$FIX "$U" show pt13-no-such-unit --json >/dev/null 2>&1
is 'show of a unit in neither scope exits 2' "$?" 2
PC_FIXTURE=$FIX "$U" stop pt13-no-such-unit >/dev/null 2>&1
is 'stop dry run of a unit in neither scope exits 2' "$?" 2

## --- fixture: fleet verdicts (T347-10) ------------------------------------
FF=$(mktemp -d); mkdir -p "$FF/bin"
cat >"$FF/bin/systemctl" <<'S'
#!/bin/sh
case "$*" in
  *list-unit-files*) echo "dark-eye-old.service enabled enabled"; echo "dark-eye.service enabled enabled"; exit 0;;
  *list-timers*) echo '[]'; exit 0;;
  *show*) ;;
  *) exit 0;;
esac
skip=0
for a in "$@"; do
  [ $skip = 1 ] && { skip=0; continue; }
  case "$a" in -p) skip=1; continue;; -*|show) continue;; esac
  case "$a" in
    agent@maintenance.service) set -- inactive dead static oneshot exit-code;;
    agent@*) set -- inactive dead static oneshot success;;
    dark-eye-old.service) set -- inactive dead enabled simple success;;
    *.timer) set -- active waiting enabled "" success;;
    *) set -- active running enabled simple success;;
  esac
  printf 'Id=%s\nActiveState=%s\nSubState=%s\nUnitFileState=%s\nType=%s\nResult=%s\n\n' "$a" "$1" "$2" "$3" "$4" "$5"
done
S
chmod +x "$FF/bin/systemctl"
fl=$(HOME="$FF" PC_FIXTURE=$FF "$U" fleet --json)
is 'fleet judges an enabled unit off the roster (dark-eye-old FAIL)' \
  "$(jq -r '.[]|select(.unit=="dark-eye-old.service")|.state' <<<"$fl")" FAIL
is 'fleet: a oneshot whose last run failed is FAIL' \
  "$(jq -r '.[]|select(.unit=="agent@maintenance.service")|.state' <<<"$fl")" FAIL
is 'fleet: an idle oneshot with Result=success is OK' \
  "$(jq -r '.[]|select(.unit=="agent@moodle-keeper.service")|.state' <<<"$fl")" OK
is 'fleet: a running enabled service is OK' \
  "$(jq -r '.[]|select(.unit=="dark-eye.service")|.state' <<<"$fl")" OK
is 'fleet: a roster unit discovered twice is listed once' \
  "$(jq '[.[]|select(.unit=="dark-eye.service")]|length' <<<"$fl")" 1
HOME="$FF" PC_FIXTURE=$FF "$U" fleet | grep -q 'dark-eye-old.service *inactive *dead *FAIL'
is 'fleet text shows the verdict column' "$?" 0
rm -rf "$FF"

## --- fixture: reset-failed (TSP-044) — stubbed systemctl on PATH, never a real unit ----
RF=$(mktemp -d); mkdir -p "$RF/bin"; echo failed >"$RF/state"
cat >"$RF/bin/systemctl" <<S
#!/bin/sh
echo "\$*" >>"$RF/argv"
case "\$*" in
  "--user show run-fixture.scope -p ActiveState --value") cat "$RF/state";;
  "--user reset-failed -- run-fixture.scope") echo inactive >"$RF/state";;
  *) exit 1;;
esac
S
chmod +x "$RF/bin/systemctl"
rf=$(PATH="$RF/bin:$PATH" "$U" reset-failed run-fixture.scope --user)
is 'reset-failed dry run prints would: failed → inactive' "$rf" 'would: run-fixture.scope failed → inactive'
is 'reset-failed dry run leaves the unit failed' "$(cat "$RF/state")" failed
rf=$(PATH="$RF/bin:$PATH" "$U" reset-failed run-fixture.scope --user --apply)
grep -q '^rollback: pc undo ' <<<"$rf" && ok 'reset-failed --apply prints a rollback line' || nok 'reset-failed --apply rollback line' "$rf"
is 'reset-failed --apply resets the stub unit' "$(cat "$RF/state")" inactive
rid=$(sed -n 's/^rollback: pc undo //p' <<<"$rf")
is 'reset-failed is ledgered and verified' "$(jq -s -r --arg i "$rid" 'map(select(.id==$i and .verified==true))|length' "$PC_LEDGER")" 1
is 'reset-failed ledger row has a no-op rollback' "$(jq -s -r --arg i "$rid" 'map(select(.id==$i and .rollback))[0].rollback|startswith(":")' "$PC_LEDGER")" true
PATH="$RF/bin:$PATH" "$U" reset-failed ssh.service --system --apply >/dev/null 2>&1
is 'reset-failed ssh is refused (guard)' "$?" 3
is 'selftest: the stub saw only show/reset-failed of run-fixture.scope' \
  "$(grep -cv -e '^--user show run-fixture.scope -p ActiveState --value$' -e '^--user reset-failed -- run-fixture.scope$' "$RF/argv")" 0
rm -rf "$RF"

## --- fixture: start of a oneshot (T533) — stubbed systemctl, per-unit state files ----
OS=$(mktemp -d); mkdir -p "$OS/bin"
for x in os-ok os-bad os-slow; do printf 'inactive\nsuccess\noneshot\nno\n' >"$OS/$x"; done
printf 'inactive\nsuccess\nsimple\nno\n' >"$OS/svc-simple"
cat >"$OS/bin/systemctl" <<S
#!/bin/sh
echo "\$*" >>"$OS/argv"
u=\$3; f="$OS/\$3"
case "\$2" in
  show) case "\$5" in ActiveState) n=1;; Result) n=2;; Type) n=3;; RemainAfterExit) n=4;; *) exit 1;; esac
        if [ "\$u" = os-slow ] && [ \$n = 1 ] && [ "\$(sed -n 1p "\$f")" = activating ]; then
          c=\$(( \$(cat "$OS/slow-reads" 2>/dev/null || echo 0) + 1 )); echo \$c >"$OS/slow-reads"
          [ \$c -ge 3 ] && sed -i '1s/.*/inactive/' "\$f"
        fi
        sed -n "\${n}p" "\$f";;
  start) u=\$4; f="$OS/\$4"
         case "\$u" in
           os-ok) ;;
           os-bad) sed -i '1s/.*/failed/;2s/.*/exit-code/' "\$f"; exit 3;;
           os-slow) sed -i '1s/.*/activating/' "\$f";;
           svc-simple) sed -i '1s/.*/active/' "\$f";;
         esac;;
  *) exit 1;;
esac
S
chmod +x "$OS/bin/systemctl"
row() { jq -s -c --arg i "$1" 'map(select(.id==$i)) | add' "$PC_LEDGER"; }
o=$(PATH="$OS/bin:$PATH" "$U" start os-ok --user)
is 'oneshot start dry run expects inactive success' "$o" 'would: os-ok inactive → inactive success'
o=$(PATH="$OS/bin:$PATH" "$U" start os-ok --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot ok: ledger row verified' "$(jq -r '.verified' <<<"$r")" true
is 'oneshot ok: observed inactive success' "$(jq -r '.observed' <<<"$r")" 'inactive success'
o=$(PATH="$OS/bin:$PATH" "$U" start os-bad --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot failed: ledger row unverified' "$(jq -r '.verified' <<<"$r")" false
is 'oneshot failed: observed starts with failed' "$(jq -r '.observed|startswith("failed")' <<<"$r")" true
o=$(PATH="$OS/bin:$PATH" "$U" start os-slow --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot still activating: polled until inactive, verified' "$(jq -r '.verified' <<<"$r")" true
o=$(PATH="$OS/bin:$PATH" "$U" start svc-simple --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'simple service: after stays active' "$(jq -r '.after' <<<"$r")" active
is 'simple service: verified on ActiveState alone' "$(jq -r '"\(.verified) \(.observed)"' <<<"$r")" 'true active'
is 'selftest: the oneshot stub saw only show/start of fixture units' \
  "$(grep -cvE '^--user (show (os-ok|os-bad|os-slow|svc-simple) -p [A-Za-z]+ --value|start -- (os-ok|os-bad|os-slow|svc-simple))$' "$OS/argv")" 0
rm -rf "$OS"

## --- fixture: cost --all (T1051) — stubbed journalctl/systemctl/docker, uptime 48 h ----
CA=$(mktemp -d); mkdir -p "$CA/bin" "$CA/proc"; echo '172800.00 1.00' >"$CA/proc/uptime"
D1=$(printf 'a%.0s' $(seq 64)); D2=$(printf 'b%.0s' $(seq 64)); D3=$(printf 'c%.0s' $(seq 64)); D4=$(printf 'd%.0s' $(seq 64)); D5=$(printf 'e%.0s' $(seq 64))
printf '%s\told-api-1\t2026-10-20T10:00:00\n' "${D3:0:12}" >"$CA/docker-names.tsv"
cat >"$CA/bin/journalctl" <<S
#!/bin/sh
echo "\$*" >>"$CA/argv"
cat <<'J'
1000.000001 systemd[1]: apt-daily.service: Consumed 2.500s CPU time over 3.100s wall clock time, 10M memory peak.
1000.000002 systemd[5742]: sentinel-check.service: Consumed 1min 2.500s CPU time over 1min 3s wall clock time.
1000.000003 systemd[5742]: sentinel-check.service: Consumed 500ms CPU time.
1000.000004 systemd[5742]: fleet-ci-daily.service: Consumed 1h 2min 3.000s CPU time, 2G memory peak.
1000.000010 systemd[1]: long.service: Consumed 6h 4min 30s CPU time over 4d wall clock time, 1G memory peak.
1000.000005 systemd[5742]: run-p123-i456.scope: Consumed 1min 250ms CPU time.
1000.000006 systemd[5742]: run-p789-i1011.scope: Consumed 0.750s CPU time.
1000.000007 systemd[1]: docker-$D1.scope: Consumed 10.000s CPU time.
1000.000008 systemd[1]: docker-$D2.scope: Consumed 4s CPU time.
1000.000011 systemd[1]: docker-$D3.scope: Consumed 3s CPU time.
1000.000012 systemd[1]: Started docker-$D4.scope - old-cache-1.
1000.000013 systemd[1]: docker-$D4.scope: Consumed 2s CPU time.
1000.000014 systemd[1]: docker-$D5.scope: Consumed 1s CPU time.
1000.000009 systemd[5742]: Started something else.
J
S
cat >"$CA/bin/systemctl" <<'S'
#!/bin/sh
case "$*" in
  *list-timers*) case "$*" in *--user*) echo '[{"unit":"sentinel-check.timer","activates":"sentinel-check.service"}]';; *) echo '[]';; esac;;
  "--user show"*) printf 'Id=dark-eye.service\nActiveState=active\nCPUUsageNSec=7200000000000\nActiveEnterTimestampMonotonic=0\n\n'
                  printf 'Id=fresh.service\nActiveState=active\nCPUUsageNSec=30000000000\nActiveEnterTimestampMonotonic=172740000000\n\n'
                  printf 'Id=idle.service\nActiveState=inactive\nCPUUsageNSec=5000000000\nActiveEnterTimestampMonotonic=0\n';;
  "show"*) printf 'Id=user@%s.service\nActiveState=active\nCPUUsageNSec=99000000000000\nActiveEnterTimestampMonotonic=0\n\n' "$(id -u)"
           printf 'Id=netdata.service\nActiveState=active\nCPUUsageNSec=3600000000000\nActiveEnterTimestampMonotonic=0\n';;
esac
S
cat >"$CA/bin/docker" <<S
#!/bin/sh
case "\$1" in
  ps) echo "$D1 web-1";;
  events) echo "\$*" >>"$CA/events-argv"; echo "$D1 web-1"; echo "$D2 old-db-1"; echo "$D2 old-db-1";;
esac
S
chmod +x "$CA/bin/"*
cj=$(PC_FIXTURE=$CA "$U" cost --all --json)
cr() { jq -r --arg u "$1" ".[]|select(.unit==\$u)|$2" <<<"$cj"; }
is 'cost --all: 13 rows (inactive and user@N left out)' "$(jq length <<<"$cj")" 13
is 'cost --all: Ns form' "$(cr apt-daily.service .cpu_s)" 2.5
is 'cost --all: min s + ms forms summed, 2 runs, timer kind' "$(cr sentinel-check.service '"\(.cpu_s) \(.runs) \(.kind)"')" '63 2 timer'
is 'cost --all: h min s form, s/h over 24 h' "$(cr fleet-ci-daily.service '"\(.cpu_s) \(.s_per_h)"')" '3723 155.1'
is 'cost --all: transient scopes collapse (min ms + s)' "$(cr 'run-p*-i*.scope' '"\(.cpu_s) \(.runs) \(.kind)"')" '61 2 scope'
is 'cost --all: docker scope named by container' "$(cr web-1 '"\(.kind) \(.cpu_s)"')" 'docker 10'
is 'cost --all: removed container named from docker events' "$(cr 'old-db-1 (gone)' '"\(.kind) \(.cpu_s)"')" 'docker 4'
is 'cost --all: removed container named from its scope Started line' "$(cr 'old-cache-1 (gone)' .cpu_s)" 2
is 'cost --all: removed container named from docker-names.tsv' "$(cr 'old-api-1 (gone)' '"\(.kind) \(.cpu_s)"')" 'docker 3'
is 'cost --all: removed container with no name source' "$(cr 'eeeeeeeeeeee (gone, unknown)' .cpu_s)" 1
is 'cost --all: no bare 12-hex docker rows' "$(jq '[.[]|select(.kind=="docker" and (.unit|test("^[0-9a-f]{12}$")))]|length' <<<"$cj")" 0
ea=$(awk -v b=$(( $(date +%s) - 172800 )) '{for (i=1;i<NF;i++) if ($i=="--since") d=$(i+1)-b} /--filter type=container/ && d>=-5 && d<=5 {n++} END{print n+0}' "$CA/events-argv" 2>/dev/null)
is 'selftest: one docker events call, since boot, containers only' "$ea" 1
is 'cost --all: live unit older than the window counts its window share' "$(cr dark-eye.service '"\(.cpu_s) \(.s_per_h)"')" '3600 150'
is 'cost --all: live unit younger than the window counts all of it' "$(cr fresh.service '"\(.cpu_s) \(.s_per_h)"')" '30 1.2'
is 'cost --all: system scope tagged' "$(cr netdata.service '"\(.scope) \(.s_per_h)"')" 'system 75'
is 'cost --all: a run longer than the window counts its window share (d h min s forms)' "$(cr long.service .cpu_s)" 5467.5
is 'cost --all: sorted by s/h' "$(jq -r '.[0].unit' <<<"$cj")" long.service
is 'cost --all --since 2h: window 2 h' "$(PC_FIXTURE=$CA "$U" cost --all --since 2h --json | jq -r '.[]|select(.unit=="apt-daily.service")|.s_per_h')" 1.2
ct=$(PC_FIXTURE=$CA "$U" cost --all --per-hour)
grep -qE '^fleet-ci-daily.service +user +service +1 +3723.0 +155.1 *$' <<<"$ct" && ok 'cost --all text: one row per unit with s/h' || nok 'cost --all text: one row per unit with s/h' "$ct"
PC_FIXTURE=$CA "$U" cost --all --since nonsense >/dev/null 2>&1
is 'cost --all: bad --since exits 2' "$?" 2
is 'selftest: every journalctl call got a relative --since' "$(grep -cv -- '--since -[0-9]' "$CA/argv")" 0
rm -rf "$CA"

## --- fixture: cost --all --by ticket (T1078) — transient scopes by the first T-id in their Started line ----
BT=$(mktemp -d); mkdir -p "$BT/bin" "$BT/proc"; echo '172800.00 1.00' >"$BT/proc/uptime"
cat >"$BT/bin/journalctl" <<'S'
#!/bin/sh
cat <<'J'
1000.000001 systemd[5742]: Started run-p1-i1.scope - [systemd-run] /usr/bin/blender -b /tmp/tmp.T6tFjTYJel --out /x/research/2026-10-20/T1032/out.
1000.000002 systemd[5742]: run-p1-i1.scope: Consumed 1min 40s CPU time over 2min wall clock time.
1000.000003 systemd[5742]: Started run-p2-i2.scope - [systemd-run] /usr/bin/flock /x/evidence/T1032/render.lock blender -b.
1000.000004 systemd[5742]: run-p2-i2.scope: Consumed 50s CPU time.
1000.000005 systemd[5742]: Started run-p3-i3.scope - [systemd-run] /usr/bin/env A=1 /usr/bin/nice -n 19 /usr/bin/python3 ./probe.py 30.
1000.000006 systemd[5742]: run-p3-i3.scope: Consumed 20s CPU time.
1000.000007 systemd[5742]: Started tmux-spawn-fc614ee5-88df-49ac-b15e-82d5be0625df.scope - tmux child pane 4 launched by process 3.
1000.000008 systemd[5742]: tmux-spawn-fc614ee5-88df-49ac-b15e-82d5be0625df.scope: Consumed 10s CPU time.
1000.000009 systemd[5742]: run-p4-i4.scope: Consumed 5s CPU time.
1000.000010 systemd[1]: apt-daily.service: Consumed 2.500s CPU time.
1000.000011 systemd[1]: docker-aaaaaaaaaaaa.scope: Consumed 10s CPU time.
1000.000012 systemd[5742]: Started run-p5-i5.scope - [systemd-run] /usr/bin/env TMPDIR=/tmp/agent-verify.hwvwdwwk PATH=/tmp/x/bin:/usr/bin bash -c "exit 3".
1000.000013 systemd[5742]: run-p5-i5.scope: Consumed 4s CPU time.
1000.000014 systemd[5742]: Started run-p6-i6.scope - [systemd-run] /usr/bin/timeout -s KILL 300 "./Instant Meshes" -d -o /tmp/o.obj.
1000.000015 systemd[5742]: run-p6-i6.scope: Consumed 3s CPU time.
1000.000016 systemd[5742]: Started run-p7-i7.scope - [systemd-run] /usr/bin/sudo -u nobody /usr/bin/ffmpeg -i x.
1000.000017 systemd[5742]: run-p7-i7.scope: Consumed 2s CPU time.
2000.000001 systemd[5742]: Started run-p8-i8.scope - [systemd-run] /usr/bin/blender -b /tmp/tmp.abc/x.blend.
2000.000002 systemd[5742]: Started run-p10-i10.scope - [systemd-run] /usr/bin/blender -b /tmp/tmp.abc/y.blend.
2100.500000 systemd[5742]: run-p8-i8.scope: Consumed 7s CPU time over 1min 40s wall clock time.
2100.600000 systemd[5742]: run-p10-i10.scope: Consumed 6s CPU time over 10s wall clock time.
J
S
cat >"$BT/heavy.jsonl" <<'H'
{"ts":"1970-01-01T01:35:01+01:00","ticket":"T777","mode":"scope","cmd":["blender","-b","/tmp/tmp.abc/x.blend"],"rc":0,"wall_s":101.2,"cpu_s":7}
{"ts":"1970-01-01T00:35:01+00:00","ticket":"T778","mode":"scope","cmd":["godot","--headless"],"rc":0,"wall_s":10.1,"cpu_s":6}
{"ts":"1970-01-01T00:35:01+00:00","ticket":"-","mode":"scope","cmd":["blender"],"rc":0,"wall_s":10.1,"cpu_s":6}
not json
H
cat >"$BT/bin/systemctl" <<'S'
#!/bin/sh
case "$*" in
  *list-timers*) echo '[]';;
  "--user show"*) printf 'Id=run-p9-i9.scope\nActiveState=active\nCPUUsageNSec=30000000000\nActiveEnterTimestampMonotonic=172740000000\nDescription=[systemd-run] /usr/bin/bash -c "cd ~/agent-work/research/2026-10-21/T1078 && make"\n';;
esac
S
printf '#!/bin/sh\n' >"$BT/bin/docker"; chmod +x "$BT/bin/"*
bj=$(PC_FIXTURE=$BT "$U" cost --all --by ticket --json)
br() { jq -r --arg t "$1" ".[]|select(.ticket==\$t)|$2" <<<"$bj"; }
is 'by ticket: first word-bounded T-id (tmp.T6… skipped), 2 runs summed' "$(br T1032 '"\(.runs) \(.cpu_s)"')" '2 150'
is 'by ticket: live scope tagged from its Description' "$(br T1078 .cpu_s)" 30
is 'by ticket: no T-id → untagged command basename past env/nice' "$(br 'untagged python3' .cpu_s)" 20
is 'by ticket: no Started line → untagged collapsed unit' "$(br 'untagged tmux-spawn-*.scope' .cpu_s) $(br 'untagged run-p*-i*.scope' .cpu_s)" '10 5'
is 'by ticket: env assignments with a path are skipped → untagged bash' "$(br 'untagged bash' .cpu_s)" 4
is 'by ticket: a quoted command name stays whole past timeout -s SIG' "$(br 'untagged Instant Meshes' .cpu_s)" 3
is 'by ticket: sudo -u <user> skips the user name' "$(br 'untagged ffmpeg' .cpu_s)" 2
is 'by ticket: untagged scope takes the ticket of the heavy run with the same command, end and wall' "$(br T777 .cpu_s)" 7
is 'by ticket: heavy row used once; other command or no ticket never joins' "$(br 'untagged blender' .cpu_s) $(br T778 .cpu_s)" '6 '
is 'by ticket: services and docker scopes left out, 10 rows' "$(jq length <<<"$bj")" 10
bt=$(PC_FIXTURE=$BT "$U" cost --all --by ticket)
grep -qE '^T1032 +2 +150.0 +6.2 *$' <<<"$bt" && ok 'by ticket text: T<n> runs CPU_S S/H' || nok 'by ticket text: T<n> runs CPU_S S/H' "$bt"
PC_FIXTURE=$BT "$U" cost --all --by nonsense >/dev/null 2>&1
is 'by: unknown key exits 2' "$?" 2
rm -rf "$BT"

## --- fixture: disable/mask/enable/unmask (T1056) — stubbed systemctl + sudo on PATH, never a real unit ----
DM=$(mktemp -d); mkdir -p "$DM/bin" "$DM/u"
cat >"$DM/bin/sudo" <<S
#!/bin/sh
[ "\$1" = -n ] && shift
echo "sudo \$*" >>"$DM/argv"
exec "\$@"
S
cat >"$DM/bin/systemctl" <<S
#!/bin/bash
echo "systemctl \$*" >>"$DM/argv"
[ "\$1" = --user ] && shift
v=\$1; shift; [ "\$1" = --now ] && { now=1; shift; }; [ "\$1" = -- ] && shift
f="$DM/u/\${1%.service}.service"; [ -f "\$f" ] || exit 1
st() { sed -n "\${1}p" "\$f"; }; put() { sed -i "\${1}s/.*/\$2/" "\$f"; }
case \$v in
  show) case "\$3" in
          *,*) printf 'UnitFileState=%s\nActiveState=%s\n' "\$(st 1)" "\$(st 2)";;
          LoadState) echo loaded;; UnitFileState) st 1;; ActiveState) st 2;; TriggeredBy) st 3;; *) exit 1;;
        esac;;
  disable) put 1 disabled; [ -n "\${now:-}" ] && [ "\$(st 2)" != failed ] && put 2 inactive;;
  mask) cp "\$f" "\$f.orig"; put 1 masked; [ -n "\${now:-}" ] && [ "\$(st 2)" != failed ] && put 2 inactive;;
  unmask) put 1 "\$(sed -n 1p "\$f.orig")";;
  enable) put 1 enabled; [ -n "\${now:-}" ] && put 2 active;;
  start|restart) put 2 active;;
  reset-failed) put 2 inactive;;
  *) exit 1;;
esac
S
chmod +x "$DM/bin/"*
printf 'enabled\nactive\n\n' >"$DM/u/fx-enabled.service"
printf 'static\nactive\n\n' >"$DM/u/fx-static.service"
printf 'disabled\ninactive\n\n' >"$DM/u/fx-off.service"
printf 'enabled\nactive\nfx-trig.socket\n' >"$DM/u/fx-trig.service"
printf 'enabled-runtime\nactive\n\n' >"$DM/u/fx-rt.service"
printf 'enabled\nfailed\n\n' >"$DM/u/fx-failed.service"
printf 'disabled\nactive\n\n' >"$DM/u/fx-run.service"
dm() { PATH="$DM/bin:$PATH" "$U" "$@"; }
row() { jq -s -c --arg i "$1" 'map(select(.id==$i)) | add' "$PC_LEDGER"; }
for g in tailscaled ssh sshd.service ssh.socket ufw docker docker.socket containerd dark-eye dark-eye-failed \
         sentinel-check.timer agent@maintenance.service "${ORCHESTRATOR_UNIT:-claude-orchestrator.service}" netdata \
         NetworkManager.service gdm gdm3 pipewire pipewire-pulse.socket dbus dbus.socket dbus-broker \
         systemd-logind systemd-journald.socket polkit gnome-shell-wayland user@$UID.service wireplumber accounts-daemon; do
  for v in disable mask; do
    o=$(dm "$v" "$g" --system --apply 2>&1); rc=$?
    [ "$rc" = 3 ] && grep -q refused <<<"$o" && ok "$v $g refused" || nok "$v $g refused" "rc=$rc $o"
  done
done
is 'selftest: refusals never reached systemctl or sudo' "$(cat "$DM/argv" 2>/dev/null | wc -l)" 0
is 'disable dry run: enabled active → disabled inactive' "$(dm disable fx-enabled --system)" 'would: fx-enabled enabled active → disabled inactive'
is 'disable dry run leaves the stub unit' "$(tr '\n' ' ' <"$DM/u/fx-enabled.service")" 'enabled active  '
o=$(dm disable fx-enabled --system --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'disable --apply: stub unit disabled and stopped' "$(head -2 "$DM/u/fx-enabled.service" | tr '\n' ' ')" 'disabled inactive '
is 'disable --apply: ledgered and verified' "$(jq -r .verified <<<"$r")" true
is 'disable --apply: rollback re-enables with --now' "$(jq -r .rollback <<<"$r")" 'pc units enable fx-enabled --system --now --apply'
grep -qx 'sudo systemctl disable --now -- fx-enabled' "$DM/argv" && ok 'disable of a system unit goes through sudo -n' || nok 'system unit through sudo' "$(cat "$DM/argv")"
o=$(PATH="$DM/bin:$PATH" "$BIN/pc-undo" undo "$(jq -r .id <<<"$r")" --apply 2>&1)
is 'pc undo of disable: enabled active again' "$(head -2 "$DM/u/fx-enabled.service" | tr '\n' ' ')" 'enabled active '
o=$(dm disable fx-static --system --apply); rc=$?
grep -q '^cannot: fx-static is static' <<<"$o" && grep -q 'pc units mask fx-static' <<<"$o" && ok 'disable of a static unit says cannot and points at mask' || nok 'static disable' "$o"
is 'disable of a static unit exits 4' "$rc" 4
o=$(dm disable fx-rt --system --apply); rc=$?
grep -q '^cannot: fx-rt is enabled-runtime' <<<"$o" && [ "$rc" = 4 ] && ok 'disable of an enabled-runtime unit: cannot, exit 4' || nok 'enabled-runtime disable' "rc=$rc $o"
is 'disable of an enabled-runtime unit changes nothing' "$(head -2 "$DM/u/fx-rt.service" | tr '\n' ' ')" 'enabled-runtime active '
o=$(dm disable fx-failed --system --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'disable of a failed unit: verified disabled failed, rollback without --now' "$(jq -r '"\(.verified) \(.after) \(.rollback)"' <<<"$r")" 'true disabled failed pc units enable fx-failed --system --apply'
o=$(dm enable fx-run --system --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'enable of a running disabled unit: rollback keeps it running' "$(jq -r .rollback <<<"$r")" 'pc units disable fx-run --system --keep --apply'
o=$(PATH="$DM/bin:$PATH" "$BIN/pc-undo" undo "$(jq -r .id <<<"$r")" --apply 2>&1)
is 'pc undo of enable: disabled and still active' "$(head -2 "$DM/u/fx-run.service" | tr '\n' ' ')" 'disabled active '
is 'disable of a static unit changes nothing' "$(head -2 "$DM/u/fx-static.service" | tr '\n' ' ')" 'static active '
grep -q '^already: fx-off disabled inactive$' <<<"$(dm disable fx-off --system --apply)" && ok 'disable of a disabled unit: already' || nok 'already disabled' "$(dm disable fx-off --system)"
o=$(dm mask fx-static --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'mask --apply (user): stub unit masked and stopped' "$(head -2 "$DM/u/fx-static.service" | tr '\n' ' ')" 'masked inactive '
is 'mask --apply: ledgered, verified, before static active' "$(jq -r '"\(.verified) \(.before)"' <<<"$r")" 'true static active'
is 'mask --apply: rollback unmasks and starts' "$(jq -r .rollback <<<"$r")" 'pc units unmask fx-static --user --now --apply'
! grep -q '^sudo .*fx-static' "$DM/argv" && ok 'a user unit never goes through sudo' || nok 'user unit sudo' "$(cat "$DM/argv")"
grep -q '^already: fx-static masked inactive$' <<<"$(dm mask fx-static --user)" && ok 'mask of a masked unit: already' || nok 'already masked' "$(dm mask fx-static --user)"
o=$(PATH="$DM/bin:$PATH" "$BIN/pc-undo" undo "$(jq -r .id <<<"$r")" --apply 2>&1)
is 'pc undo of mask: static active again' "$(head -2 "$DM/u/fx-static.service" | tr '\n' ' ')" 'static active '
is 'pc undo of mask is verified' "$(jq -s -r 'map(select(.verified!=null))|last|.verified' "$PC_LEDGER")" true
grep -q '^note: fx-trig is also started by fx-trig.socket' <<<"$(dm mask fx-trig --system)" && ok 'mask names the triggering socket' || nok 'trigger note' "$(dm mask fx-trig --system)"
# T1059: start/stop/restart/reset-failed of a system unit go through sudo -n, a user unit never does.
: >"$DM/argv"
o=$(dm restart fx-enabled --system --apply)
grep -q '^rollback: pc undo ' <<<"$o" && grep -qx 'sudo systemctl restart -- fx-enabled' "$DM/argv" && ok 'restart of a system unit goes through sudo -n' || nok 'system restart sudo' "$o $(cat "$DM/argv")"
dm restart fx-run --user --apply >/dev/null
! grep -q '^sudo .*fx-run' "$DM/argv" && grep -q 'restart -- fx-run' "$DM/argv" && ok 'restart of a user unit never goes through sudo' || nok 'user restart sudo' "$(cat "$DM/argv")"
printf 'enabled\nfailed\n\n' >"$DM/u/fx-failed.service"
o=$(dm reset-failed fx-failed --system --apply)
grep -qx 'sudo systemctl reset-failed -- fx-failed' "$DM/argv" && is 'reset-failed of a system unit: through sudo, unit inactive' "$(sed -n 2p "$DM/u/fx-failed.service")" inactive || nok 'system reset-failed sudo' "$o $(cat "$DM/argv")"
is 'selftest: the stubs saw only fixture units' "$(grep -cvE ' (-- )?fx-(enabled|static|off|trig|rt|failed|run)(\.service)?( |$)' "$DM/argv")" 0
rm -rf "$DM"

## --- fixture: slow jobs (T1081) — stubbed systemctl + sudo + timeout on PATH, never a real unit ----
SX=$(mktemp -d); mkdir -p "$SX/bin" "$SX/u"
cat >"$SX/bin/sudo" <<S
#!/bin/sh
[ "\$1" = -n ] && shift
echo "sudo \$*" >>"$SX/argv"
exec "\$@"
S
cat >"$SX/bin/tmo" <<S
#!/bin/sh
echo "timeout \$1" >>"$SX/argv"
exec timeout "\$@"
S
cat >"$SX/bin/systemctl" <<S
#!/bin/bash
echo "systemctl \$*" >>"$SX/argv"
[ "\$1" = --user ] && shift
v=\$1; shift; [ "\$1" = -- ] && shift
f="$SX/u/\$1"; [ -f "\$f" ] || exit 1
st() { sed -n "\${1}p" "\$f"; }; put() { sed -i "\${1}s/.*/\$2/" "\$f"; }
case \$v in
  show) for p in \${3//,/ }; do case \$p in
          ActiveState) st 1;; Result) st 2;; Type) st 3;; RemainAfterExit) st 4;;
          TimeoutStartUSec) st 5;; TimeoutStopUSec) st 6;; LoadState) echo loaded;; *) exit 1;;
        esac; done;;
  start|restart) case \$1 in
          sx-slow) sleep 8; put 1 active;;
          sx-fail) put 1 activating; put 1 failed; put 2 exit-code; exit 3;;
          sx-long) put 1 activating; ( sleep 11; put 1 inactive ) >/dev/null 2>&1 </dev/null &;;
          *) put 1 active;;
        esac;;
  stop) put 1 inactive;;
  *) exit 1;;
esac
S
chmod +x "$SX/bin/"*
printf 'inactive\nsuccess\nsimple\nno\n1min 30s\n1min 30s\n' >"$SX/u/sx-slow"
printf 'inactive\nsuccess\noneshot\nno\ninfinity\n1min 30s\n' >"$SX/u/sx-fail"
printf 'inactive\nsuccess\noneshot\nno\ninfinity\n1min 30s\n' >"$SX/u/sx-long"
printf 'inactive\nsuccess\nsimple\nno\n10min\n2s\n' >"$SX/u/sx-cap"
printf 'inactive\nsuccess\nsimple\nno\n1min 30s\n1min 30s\n' >"$SX/u/sx-user"
sx() { PATH="$SX/bin:$PATH" PC_TIMEOUT_BIN="$SX/bin/tmo" "$U" "$@"; }
row() { jq -s -c --arg i "$1" 'map(select(.id==$i)) | add' "$PC_LEDGER"; }
: >"$SX/argv"; o=$(sx start sx-slow --system --apply); rc=$?; r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'slow start (8 s, TimeoutStartUSec 1min 30s): rc 0' "$rc" 0
is 'slow start: verified active' "$(jq -r '"\(.verified) \(.observed)"' <<<"$r")" 'true active'
grep -qx 'timeout 95' "$SX/argv" && grep -qx 'sudo systemctl start -- sx-slow' "$SX/argv" && ok 'slow start: sudo bound is TimeoutStartUSec + 5 s (95)' || nok 'slow start bound' "$(cat "$SX/argv")"
: >"$SX/argv"; sx stop sx-cap --system --apply >/dev/null; sx start sx-cap --system --apply >/dev/null
is 'bounds: stop 2 s → 7, start 10min → capped 300' "$(grep '^timeout' "$SX/argv" | paste -sd,)" 'timeout 7,timeout 300'
: >"$SX/argv"; sx restart sx-slow --system --apply >/dev/null
is 'bounds: restart sums start + stop (185)' "$(grep '^timeout' "$SX/argv")" 'timeout 185'
t0=$SECONDS; o=$(sx start sx-fail --system --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot ending failed: verified false, observed failed exit-code' "$(jq -r '"\(.verified) \(.observed)"' <<<"$r")" 'false failed exit-code'
[ $((SECONDS - t0)) -le 2 ] && ok 'oneshot ending failed: recorded at once (≤ 2 s)' || nok 'failed oneshot wait' "$((SECONDS - t0)) s"
: >"$SX/argv"; o=$(sx start sx-long --system --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot activating 11 s (infinity → 300 s bound): verified inactive success' "$(jq -r '"\(.verified) \(.observed)"' <<<"$r")" 'true inactive success'
grep -qx 'timeout 300' "$SX/argv" && ok 'oneshot with TimeoutStartUSec=infinity: sudo bound 300' || nok 'infinity bound' "$(cat "$SX/argv")"
: >"$SX/argv"; o=$(sx start sx-user --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
! grep -q '^sudo\|^timeout' "$SX/argv" && is 'user scope: no sudo, no timeout, verified' "$(jq -r .verified <<<"$r")" true || nok 'user scope' "$(cat "$SX/argv")"
M=$(mktemp -d); ln -s "$BIN/pclib.sh" "$M/pclib.sh"; [ -e "$BIN/env.sh" ] && ln -s "$BIN/env.sh" "$M/env.sh"
sed 's/PC_ROOT_TIMEOUT=\$BOUND/PC_ROOT_TIMEOUT=5/' "$U" >"$M/pc-units"; chmod +x "$M/pc-units"
printf 'inactive\nsuccess\nsimple\nno\n1min 30s\n1min 30s\n' >"$SX/u/sx-slow"
o=$(PATH="$SX/bin:$PATH" PC_TIMEOUT_BIN="$SX/bin/tmo" "$M/pc-units" start sx-slow --system --apply); rc=$?
r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
[ "$rc" != 0 ] && [ "$(jq -r .verified <<<"$r")" = false ] && ok 'mutant with the old 5 s sudo bound is red' || nok 'mutant' "rc=$rc $r"
is 'selftest: the stubs saw only fixture units' "$(grep -cvE '^timeout [0-9]+$| (-- )?sx-(slow|fail|long|cap|user)( |$)' "$SX/argv")" 0
rm -rf "${SX:?}" "${M:?}"

## --- live: fleet, cost, guard --------------------------------------------
"$U" fleet --json | jq -e 'map(.unit)|index("sentinel-check.timer")' >/dev/null
is 'fleet --json lists the roster (sentinel-check.timer present)' "$?" 0
"$U" cost dark-eye --user --json | jq -e '.mem_mb>0 and has("psi")' >/dev/null
is 'cost dark-eye --user --json has mem_mb>0 and psi' "$?" 0

"$U" restart ssh --apply >/dev/null 2>&1
is 'restart ssh --apply is refused (guard)' "$?" 3
"$U" restart ufw --apply >/dev/null 2>&1
is 'restart ufw --apply is refused (guard)' "$?" 3
"$U" restart claude-orchestrator --apply >/dev/null 2>&1
is 'restart claude-orchestrator --apply is refused (guard)' "$?" 3
"$U" restart dark-eye --apply >/dev/null 2>&1
is 'restart dark-eye --apply is refused without PC_ORCHESTRATOR' "$?" 3
before_pid=$(systemctl --user show dark-eye -p MainPID --value 2>/dev/null)
after_pid=$(systemctl --user show dark-eye -p MainPID --value 2>/dev/null)
is 'the guarded dark-eye call touched nothing (MainPID unchanged)' "$after_pid" "$before_pid"

## --- live: transient unit round trip (never a real unit) -----------------
systemctl --user reset-failed pt13-test >/dev/null 2>&1
systemd-run --user --unit pt13-test sleep 300 >/dev/null 2>&1
before_ts=$(systemctl --user show pt13-test -p ExecMainStartTimestampMonotonic --value 2>/dev/null)
out=$("$U" restart pt13-test --user --apply)
rid=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
[ -n "$rid" ] && ok 'restart pt13-test --apply prints a rollback line' \
  || nok 'restart pt13-test --apply prints a rollback line' "$out"
sleep 0.3
after_ts=$(systemctl --user show pt13-test -p ExecMainStartTimestampMonotonic --value 2>/dev/null)
[ -n "$before_ts" ] && [ "$after_ts" != "$before_ts" ] && ok 'restart gives pt13-test a new ExecMainStartTimestamp' \
  || nok 'restart gives pt13-test a new ExecMainStartTimestamp' "before=$before_ts after=$after_ts"
"$U" stop pt13-test --user --apply >/dev/null 2>&1
sleep 0.3
left=$(systemctl --user list-units 'pt13*' --no-legend 2>/dev/null | wc -l)
is 'pt13-test is gone after stop' "$left" 0
systemctl --user reset-failed pt13-test >/dev/null 2>&1
grep -q "\"id\":\"$rid\"" "${PC_LEDGER:-/dev/null}" && ok 'the rollback id is in the temp ledger' \
  || nok 'the rollback id is in the temp ledger' "${PC_LEDGER:-unset}"
is 'the real change ledger got no row from this test' \
  "$(tail -n +$((real_rows + 1)) "$REAL_LEDGER" 2>/dev/null | grep -cE 'pt13|run-fixture|os-(ok|bad|slow)|svc-simple|fx-')" 0

[ $bad = 0 ] && echo 'PASS pc-units' || echo 'FAIL pc-units'
exit $bad
