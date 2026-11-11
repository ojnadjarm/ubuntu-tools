#!/usr/bin/env bash
# shellcheck disable=SC2034  # rc and before are read inside ok's eval strings
# Fixture test for fleet-backup (T1580): fake HOME, loopback vfat images as fake sticks (udisksctl), never the real
# stick, real home or real password (FLEET.md §5.6; the selftest proves it before any assertion).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FB="$(dirname "$here")/fleet-backup"
command -v restic >/dev/null && command -v udisksctl >/dev/null && command -v strace >/dev/null ||
  { echo "SKIP restic, udisksctl or strace missing"; exit 0; }

WORK=$(mktemp -d); LOOPS=()
cleanup() {
  local d; for d in "${LOOPS[@]}"; do
    udisksctl unmount --no-user-interaction -b "$d" >/dev/null 2>&1
    timeout 20 wait-for --label "T1580 detach $d" --every 1 --until "! losetup $d >/dev/null 2>&1 || udisksctl loop-delete --no-user-interaction -b $d >/dev/null 2>&1 || sudo -n losetup -d $d 2>/dev/null" >/dev/null
  done; rm -rf "$WORK"
}
trap cleanup EXIT
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); echo "ok   $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }

# stick <label> <MB> — a vfat image mapped to a loop device and mounted by udisks; sets MP to the mount point.
stick() {
  local img="$WORK/$1.img" dev
  truncate -s "${2}M" "$img"; mkfs.vfat -n "$1" "$img" >/dev/null
  dev=$(udisksctl loop-setup --no-user-interaction -f "$img" | sed -n 's/.* as \(\/dev\/loop[0-9]*\)\.$/\1/p')
  LOOPS+=("$dev")
  udisksctl mount --no-user-interaction -b "$dev" >/dev/null 2>&1
  wait-for --label "T1580 $1" --every 1 --until "findmnt -n -o TARGET $dev >/dev/null" >/dev/null
  MP=$(findmnt -n -o TARGET "$dev")
}

H="$WORK/home"; LBL="FBT$((RANDOM % 9000 + 1000))"; FULL="FBF$((RANDOM % 9000 + 1000))"
mkdir -p "$H"/{finance,invoices,.config/pc-harness,moodle-envs/secretproj} "$H/agents"/{secrets,state,backups/moodle/{5.2,4.1}} "$H/agent-work/backups/moodle"/{5.2,sp45} \
  "$H/agent-work"/{briefs,decisions,owner,research/2026-11-01/T1,evidence/E1,big,tmp} \
  "$H/.claude"/{skills/x,projects/-p1/memory,projects/-p1/s1} "$H/.claude/projects/${H//[\/.]/-}-moodle-envs-secretproj"
head -c 200000 /dev/urandom >"$H/finance/a.bin"; echo inv >"$H/invoices/i.txt"; echo hist >"$H/agent-work/history.md"
echo brief >"$H/agent-work/briefs/b.md"; echo note >"$H/agent-work/research/2026-11-01/T1/n.md"; echo ev >"$H/agent-work/evidence/E1/e.txt"
head -c 5000000 /dev/urandom >"$H/agent-work/big/huge.bin"; echo junk >"$H/agent-work/tmp/j"
# T1603: liaison jobs ($LIAISON_PAPERS/jobs) are one tier-2 entry each, so one 14 G job folder skips alone.
mkdir -p "$H/agent-work/discord-liaison/jobs"/{j1,j2} "$H/agent-work/discord-liaison/escalations"
echo job >"$H/agent-work/discord-liaison/jobs/j1/job.json"; head -c 5000000 /dev/urandom >"$H/agent-work/discord-liaison/jobs/j2/big.bin"
echo esc >"$H/agent-work/discord-liaison/escalations/e.md"
# T1599-M10: the memory store ($MEMORY_HOME, default ~/memory) whole, its git-ignored private pages included.
mkdir -p "$H/memory/core" "$H/memory/domains/fin"; echo card >"$H/memory/core/CORE.md"; echo priv >"$H/memory/domains/fin/DOMAIN.md"
echo mem >"$H/.claude/projects/-p1/memory/m.md"; echo '{}' >"$H/.claude/projects/-p1/s1.jsonl"; echo '{}' >"$H/.claude/settings.json"
echo SECRET >"$H/moodle-envs/secretproj/x"; echo SECRET >"$H/.claude/projects/${H//[\/.]/-}-moodle-envs-secretproj/s.jsonl"
# T1597: dumps in $FLEET_BACKUPS_DIR, older ones still in the old folder (fallback read until the owner clears it).
echo old >"$H/agents/backups/moodle/5.2/2026-11-01.sql.gz"; echo new >"$H/agent-work/backups/moodle/5.2/2026-11-02.sql.gz"
echo only-old >"$H/agents/backups/moodle/4.1/2026-10-30.sql.gz"
echo SECRET >"$H/agent-work/backups/moodle/sp45/2026-11-02.sql.gz"
# Mirrors: a claims snapshot of the protected path (tier 1) and a word-named dir deep in a tier-2 ticket.
mkdir -p "$H/agent-work/claims-snap/T9/files${H}/moodle-envs/secretproj" "$H/agent-work/T9/copy/SecretProj-dump"
echo base >"$H/agent-work/claims-snap/T9/manifest.tsv"
echo SECRET >"$H/agent-work/claims-snap/T9/files${H}/moodle-envs/secretproj/x"; echo SECRET >"$H/agent-work/T9/copy/SecretProj-dump/y"
echo keep >"$H/agent-work/T9/copy/ok.txt"
# T1623: credential stores the never-back-up list must keep out (fake values), and a redactable config.env.
echo tok >"$H/agents/secrets/x.key"; echo lit >"$H/.config/pc-harness/private-values"; echo '{}' >"$H/.claude/.credentials.json"
printf 'FLEET_X=1\nAPI_TOKEN=fake-T1623\n' >"$H/.config/pc-harness/config.env"
mkdir -p "$H/agent-work/T9/prof/Default" "$H/agents/state/fleet-backup"
echo e >"$H/agent-work/T9/copy/.env"; echo k >"$H/agent-work/T9/copy/config.example.env"; echo p >"$H/agent-work/T9/copy/a.pass"; echo c >"$H/agent-work/T9/prof/Default/Cookies"
echo c >"$H/agent-work/T9/prof/Default/Login Data"; echo t >"$H/agent-work/T9/copy/leak.jsonl"
echo "$H/agent-work/T9/copy/leak.jsonl" >"$H/agents/state/fleet-backup/never.local"
cat >"$WORK/config.env" <<EOF
FLEET_BACKUP_LABEL=$LBL
FLEET_BACKUP_BUDGET_MB=6
FLEET_BACKUP_MIN_FREE_MB=1
PROTECTED_PROJECTS=fx
PROTECTED_FX_PATHS="$H/moodle-envs/secretproj"
PROTECTED_FX_CONTAINERS="sp45"
PROTECTED_FX_WORDS="secretproj"
EOF
fx() { env -i PATH="$PATH" HOME="$H" USER="$USER" XDG_RUNTIME_DIR="$WORK" HARNESS_CONFIG="$WORK/config.env" \
  HARNESS_HOME="$H/agents" AGENT_WORK="$H/agent-work" HARNESS_CONTEXT_DIR="$H/.claude" "$@"; }

stick "$LBL" 64; M="$MP"
# Selftest: the fixture stick is a loop device under our label, HOME and the password live in the fixture.
ok "selftest: fake stick is a loop device" '[ -n "$M" ] && findmnt -n -o SOURCE "$M" | grep -q "^/dev/loop"'
ok "selftest: password path is in the fixture" 'fx bash -c ". $(dirname "$FB")/env.sh; echo \${FLEET_BACKUP_PASSWORD_FILE:-\$HARNESS_HOME/secrets/fleet-backup.pass}" | grep -q "^$H/"'
[ "$fail" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

# absent stick
sed "s/^FLEET_BACKUP_LABEL=.*/FLEET_BACKUP_LABEL=NOSUCHFBT/" "$WORK/config.env" >"$WORK/absent.env"
fx env HARNESS_CONFIG="$WORK/absent.env" "$FB" run >/dev/null; rc=$?
ok "absent: exit 0" '[ $rc = 0 ]'
ok "absent: logged skip" 'grep -q "skip: stick absent" "$H/agents/state/fleet-backup/run.log"'
ok "absent: no snapshot recorded" '[ ! -e "$H/agents/state/fleet-backup/last-ok" ]'

# run, under strace
fx strace -f -qq -o "$WORK/trace" -e trace=%file "$FB" run >"$WORK/run.out" 2>&1; rc=$?
ok "run: exit 0" '[ $rc = 0 ] || cat "$WORK/run.out"'
ok "run: password file 600" '[ "$(stat -c %a "$H/agents/secrets/fleet-backup.pass")" = 600 ]'
ok "run: password never printed" '! grep -qF "$(cat "$H/agents/secrets/fleet-backup.pass")" "$WORK/run.out" "$H/agents/state/fleet-backup/run.log"'
ok "run: repo only in fleet-backup/" '[ "$(ls -A "$M")" = fleet-backup ]'
ok "protected: 0 syscalls name a protected path, dir or word" '[ "$(grep -v "execve(" "$WORK/trace" | grep -ciE "secretproj|sp45")" = 0 ]'
ok "protected: strace saw the run (restic opened the repo)" 'grep -q "fleet-backup/restic" "$WORK/trace"'
export RESTIC_PASSWORD_FILE="$H/agents/secrets/fleet-backup.pass" RESTIC_REPOSITORY="$M/fleet-backup/restic"
restic ls latest >"$WORK/ls" 2>/dev/null
ok "tier1: finance, memory, newest dump, settings" 'grep -q "/finance/a.bin$" "$WORK/ls" && grep -q "/memory/m.md$" "$WORK/ls" && grep -q "5.2/2026-11-02.sql.gz$" "$WORK/ls" && ! grep -q "2026-11-01.sql.gz$" "$WORK/ls" && grep -q "/.claude/settings.json$" "$WORK/ls"'
ok "tier1: an env only in the old backups folder still gets its newest dump (fallback)" 'grep -q "/agents/backups/moodle/4.1/2026-10-30.sql.gz$" "$WORK/ls"'
ok "tier1: the memory store \$MEMORY_HOME, private pages included" 'grep -q "^$H/memory/core/CORE.md$" "$WORK/ls" && grep -q "^$H/memory/domains/fin/DOMAIN.md$" "$WORK/ls"'
ok "tier1: claims snapshots from \$CLAIMS_SNAP" 'grep -q "/agent-work/claims-snap/T9/manifest.tsv$" "$WORK/ls"'
ok "tier2: research ticket and transcript in" 'grep -q "/T1/n.md$" "$WORK/ls" && grep -q "/-p1/s1.jsonl$" "$WORK/ls"'
ok "tier2: liaison jobs one entry each (small job in, big job skipped alone)" 'grep -q "/discord-liaison/jobs/j1/job.json$" "$WORK/ls" && grep -q "/discord-liaison/escalations/e.md$" "$WORK/ls" && grep -qx "$H/agent-work/discord-liaison/jobs/j2" "$H/agents/state/fleet-backup/last-skipped.txt"'
ok "budget: 5 MB tier-2 file skipped and listed" '! grep -q "huge.bin" "$WORK/ls" && grep -q "/agent-work/big$" "$H/agents/state/fleet-backup/last-skipped.txt"'
ok "mirrors: tier-2 sibling kept, both mirrors out" 'grep -q "/T9/copy/ok.txt$" "$WORK/ls" && ! grep -qi "moodle-envs/secretproj\|secretproj-dump" "$WORK/ls"'
ok "excluded: tmp and protected never in the snapshot" '! grep -qiE "secretproj|sp45|/agent-work/tmp" "$WORK/ls"'
ok "--check passes" 'fx "$FB" --check >/dev/null'

# restore byte-equal
fx "$FB" restore latest "$H/finance/a.bin" "$WORK/r" >/dev/null 2>&1
ok "restore: byte-equal" 'cmp -s "$H/finance/a.bin" "$WORK/r$H/finance/a.bin"'

# second run keeps one group (retention by tag) and lists 2 snapshots
fx "$FB" run >/dev/null 2>&1
ok "list: 2 snapshots" '[ "$(restic snapshots --json 2>/dev/null | jq length)" = 2 ]'

# T1623: never backed up, key on the stick, --check red on a hit, purge removes it from old snapshots.
restic ls latest >"$WORK/ls2" 2>/dev/null
ok "never: secrets, private-values, credentials, *.env, *.pass, browser logins, never.local all out" \
  '[ "$(grep -cE "^/.*(/agents/secrets|private-values|credentials\.json|/copy/\.env$|\.pass$|/Cookies$|/Login Data$|leak\.jsonl$)" "$WORK/ls2")" = 0 ]'
ok "never: siblings of excluded files and credential-free *.example.env stay in" 'grep -q "/T9/copy/ok.txt$" "$WORK/ls2" && grep -q "/T9/copy/config.example.env$" "$WORK/ls2" && grep -q "/finance/a.bin$" "$WORK/ls2" && grep -q "/invoices/i.txt$" "$WORK/ls2"'
ok "never: config.env goes in redacted" 'grep -q "/agents/state/fleet-backup/config-redacted.txt$" "$WORK/ls2" && grep -qx "API_TOKEN=<redacted>" "$H/agents/state/fleet-backup/config-redacted.txt" && grep -qx "FLEET_X=1" "$H/agents/state/fleet-backup/config-redacted.txt"'
ok "key: restic-key.txt equals the password, README names the restore command" 'cmp -s "$H/agents/secrets/fleet-backup.pass" "$M/fleet-backup/restic-key.txt" && [ "$(wc -l <"$M/fleet-backup/README.txt")" = 5 ] && grep -q "password-file restic-key.txt restore latest" "$M/fleet-backup/README.txt"'
mkdir -p "$WORK/empty" "$WORK/r2"
stickonly() { env -i PATH="$PATH" HOME="$WORK/empty" restic -r "$M/fleet-backup/restic" --password-file "$M/fleet-backup/restic-key.txt" "$@"; }
ok "key: stick alone (empty HOME) lists snapshots and restores a file" 'stickonly snapshots >/dev/null 2>&1 && stickonly restore latest --include "$H/invoices/i.txt" --target "$WORK/r2" >/dev/null 2>&1 && cmp -s "$H/invoices/i.txt" "$WORK/r2$H/invoices/i.txt"'
rm "$M/fleet-backup/restic-key.txt" "$M/fleet-backup/README.txt"; fx "$FB" run >/dev/null 2>&1
ok "key: run re-creates key and README when missing" '[ -s "$M/fleet-backup/restic-key.txt" ] && [ -s "$M/fleet-backup/README.txt" ]'
restic backup -q --tag nightly "$H/agents/secrets" "$H/invoices" >/dev/null 2>&1  # an old snapshot made before T1623
n_before=$(restic snapshots --json 2>/dev/null | jq length)
fx "$FB" --check >"$WORK/chk" 2>&1; rc=$?
ok "--check: red on a planted secret path in a snapshot" '[ $rc = 1 ] && grep -q "^FAIL never-back-up paths in snapshots" "$WORK/chk"'
fx "$FB" purge >"$WORK/plan" 2>&1; rc=$?
restic ls latest >"$WORK/ls3" 2>/dev/null
ok "purge: dry run prints the plan, changes nothing" '[ $rc = 0 ] && grep -q "would modify 1 snapshots" "$WORK/plan" && [ "$(restic snapshots --json 2>/dev/null | jq length)" = "$n_before" ] && grep -q "/agents/secrets/x.key$" "$WORK/ls3"'
fx "$FB" purge --apply >"$WORK/purge" 2>&1; rc=$?
restic ls latest >"$WORK/ls4" 2>/dev/null
ok "purge: rewrite removes the planted path, count same, prune ran" '[ $rc = 0 ] && grep -q "ok pruned, restic check clean" "$WORK/purge" && [ "$(restic snapshots --json 2>/dev/null | jq length)" = "$n_before" ] && [ "$(grep -c "^/.*/agents/secrets" "$WORK/ls4")" = 0 ] && grep -q "/invoices/i.txt$" "$WORK/ls4"'
ok "--check: green after the purge" 'fx "$FB" --check >/dev/null 2>&1'
ok "secrets: no fixture secret value printed" '! grep -qF "$(cat "$H/agents/secrets/fleet-backup.pass")" "$WORK/plan" "$WORK/purge" "$WORK/chk"'

# full stick: free-space gate, then ENOSPC during the backup
sed "s/^FLEET_BACKUP_MIN_FREE_MB=.*/FLEET_BACKUP_MIN_FREE_MB=999999/" "$WORK/config.env" >"$WORK/gate.env"
fx env HARNESS_CONFIG="$WORK/gate.env" "$FB" run >/dev/null 2>&1; rc=$?
ok "full (gate): exit 1, logged" '[ $rc = 1 ] && tail -1 "$H/agents/state/fleet-backup/run.log" | grep -q "FAIL: stick full"'
stick "$FULL" 4
sed "s/^FLEET_BACKUP_LABEL=.*/FLEET_BACKUP_LABEL=$FULL/; s/^FLEET_BACKUP_BUDGET_MB=.*/FLEET_BACKUP_BUDGET_MB=100/" "$WORK/config.env" >"$WORK/full.env"
before=$(cat "$H/agents/state/fleet-backup/last-ok")
fx env HARNESS_CONFIG="$WORK/full.env" "$FB" run >/dev/null 2>&1; rc=$?
ok "full (ENOSPC): exit 1, logged, last-ok unchanged" '[ $rc = 1 ] && tail -1 "$H/agents/state/fleet-backup/run.log" | grep -q "FAIL: stick full during backup" && [ "$(cat "$H/agents/state/fleet-backup/last-ok")" = "$before" ]'

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
