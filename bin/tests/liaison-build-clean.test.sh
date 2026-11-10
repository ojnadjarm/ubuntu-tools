#!/usr/bin/env bash
# T1565: liaison-build-clean deletes only a marked, ignored build dir of a finished idle job; refuses a tracked target/,
# an untracked-not-ignored one, a running job and a held lock. Runs in bwrap: read-only /, writable private /tmp only.
set -uo pipefail
SELF=$(readlink -f "$0"); CLI=$(dirname "$SELF")/../liaison-build-clean
if [ -z "${LBC_SANDBOXED:-}" ]; then
  exec bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --unshare-net \
    --die-with-parent --setenv LBC_SANDBOXED 1 --setenv TMPDIR /tmp -- bash "$SELF" "$@"
fi
. "$(dirname "$SELF")/lib/assert.sh"
ev "selftest: the real home is read-only" '! touch "$HOME/agents/.lbc-probe" 2>/dev/null'

W=$(mktemp -d); R="$W/repo"; J="$R/jobs"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$R"
mk() { mkdir -p "$J/$1/target/debug"; printf '{"status": "%s"}\n' "$2" >"$J/$1/job.json"; : >"$J/$1/lock"
       printf 'Signature: 8a477f597d28d172789f06886806bc55\n' >"$J/$1/target/CACHEDIR.TAG"; echo bin >"$J/$1/target/debug/x"; }
mk ok done; mk tracked done; mk untracked done; mk running running; mk locked superseded
mkdir -p "$J/ok/build"; echo 'make' >"$J/ok/build/hacer.sh"   # build/ ignored only by a blanket rule: not a candidate
printf 'jobs/ok/\njobs/tracked/target/\njobs/running/\njobs/locked/\n' >"$R/.gitignore"
git -C "$R" add .gitignore; git -C "$R" add -f jobs/tracked/target/debug/x; git -C "$R" commit -qm fixture

exec 9>"$J/locked/lock"; flock -n 9
"$CLI" scan "$J" --refused "$W/refused.tsv" >"$W/manifest.tsv"; is "scan rc" "$?" 0
is "manifest: only ok/target" "$(cut -f1 "$W/manifest.tsv" | tail -n +2)" "$J/ok/target"
ref() { grep -F "$J/$1" "$W/refused.tsv" | cut -f2; }
is "refused: tracked target/" "$(ref tracked/target)" "has files tracked by git"
is "refused: untracked-not-ignored" "$(ref untracked/target)" "not ignored by git (untracked or changed)"
is "refused: running job" "$(ref running/target)" "job status running"
is "refused: held lock" "$(ref locked/target)" "job lock held"
is "refused: build/ by blanket ignore" "$(ref ok/build)" "no build marker"

# apply re-checks: a row forged into the manifest for the running job is refused, not deleted.
printf '%s\t1\trunning\tforged\t%s\n' "$J/running/target" "$J/running" >>"$W/manifest.tsv"
st0=$(git -C "$R" status --porcelain)
out=$("$CLI" apply "$W/manifest.tsv"); is "apply rc" "$?" 0
ev "apply: ok/target deleted" '[ ! -e "$J/ok/target" ] && grep -q "^DELETED	$J/ok/target" <<<"$out"'
ev "apply: forged running row refused" '[ -d "$J/running/target" ] && grep -q "^REFUSED	$J/running/target" <<<"$out"'
ev "apply: job.json and build/ kept" '[ -s "$J/ok/job.json" ] && [ -s "$J/ok/build/hacer.sh" ]'
ev "apply: other targets kept" '[ -e "$J/tracked/target/debug/x" ] && [ -e "$J/untracked/target/debug/x" ] && [ -e "$J/locked/target/debug/x" ]'
is "apply: repo status unchanged" "$(git -C "$R" status --porcelain)" "$st0"
"$CLI" bogus >/dev/null 2>&1; is "unknown verb exits 2" "$?" 2
exit $bad
