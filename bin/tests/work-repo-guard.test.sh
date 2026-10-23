#!/usr/bin/env bash
# work-repo-guard (T1251): git hooks layer + PreToolUse layer on throwaway fixture repos in a mktemp HOME; selftest: the real gitconfig and work repos stay untouched.
# Run: bash work-repo-guard.test.sh
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd); HOOK="$BIN/../hooks/sleep-loop-block.py"
REAL_HOME=$HOME; REAL_GCFG="$REAL_HOME/.gitconfig"
REAL_ROOTS=$(sed -n 's/^WORK_REPO_ROOTS=//p' "$REAL_HOME/.config/pc-harness/config.env" 2>/dev/null | tr -d "\"'")
REAL_ROOTS=${REAL_ROOTS:-~/moodle-envs/vass ~/moodle-envs/4.5}
T=$(mktemp -d /tmp/wrg-XXXXXX); trap 'rm -rf "$T"' EXIT
stamp="$T/stamp"; touch "$stamp"; sum0=$(sha256sum "$REAL_GCFG" 2>/dev/null)
MARKERS="CLAUDECODE CLAUDE_CODE_ENTRYPOINT HARNESS_AGENT OPENCODE GEMINI_CLI CODEX_SANDBOX CODEX_THREAD_ID"
for v in $MARKERS WORK_REPO_ROOTS GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES; do unset "$v"; done
export HOME="$T" GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 HARNESS_CONFIG="$T/config.env" HARNESS_HOME="$T/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
check() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
is() { [ "$1" = "$2" ]; echo $?; }

# Selftest 1: every git config and root of this run is inside the fixture, none is a real one.
case $GIT_CONFIG_GLOBAL$HARNESS_CONFIG$HARNESS_HOME in *"$REAL_HOME"*) echo "FAIL fixture path under the real HOME"; exit 1 ;; esac
printf 'WORK_REPO_ROOTS="~/work ~/work2"\n' > "$HARNESS_CONFIG"
mkdir -p "$T/work" "$T/work2" "$T/personal" "$HARNESS_HOME"
for r in $REAL_ROOTS; do r=$(readlink -m "${r/#\~/$REAL_HOME}"); case $r in "$T"*) echo "FAIL real root inside fixture"; exit 1 ;; esac; done
check "selftest: fixture HOME, gitconfig, config.env and roots under $T" 0

mk() { git init -q -b main "$1" && git -C "$1" commit -q --allow-empty -m init; }
git init -q --bare "$T/remote.git"
mk "$T/work/repo"; git -C "$T/work/repo" remote add origin "$T/remote.git"
mk "$T/personal/repo"; git -C "$T/personal/repo" remote add origin "$T/remote.git"
n() { git -C "$1" rev-list --count HEAD; }

out=$("$BIN/work-repo-guard" install); check "install without --apply only prints would: lines" "$(is "$(grep -c '^would:' <<<"$out")$(test -e "$T/.config/pc-harness/work-repo-guard.gitconfig"; echo $?)" 31)"
printf '[user]\n\tname = t\n' > "$GIT_CONFIG_GLOBAL"
"$BIN/work-repo-guard" install --apply >/dev/null; rc=$?
"$BIN/work-repo-guard" install --apply >/dev/null
check "install --apply twice: status ok, one include line per root" "$(is "$rc$(grep -c includeIf "$GIT_CONFIG_GLOBAL")" 02)"
check "backup of the fixture gitconfig written" "$(is "$(cat "$HARNESS_HOME/backups/gitconfig.T1251.bak")" "$(printf '[user]\n\tname = t')")"
check "hooksPath origin is the guard include" "$(git -C "$T/work/repo" config --show-origin core.hooksPath | grep -q work-repo-guard.gitconfig; echo $?)"
check "personal repo has no guard hooksPath" "$(git -C "$T/personal/repo" config core.hooksPath >/dev/null; is $? 1)"

W="$T/work/repo"; P="$T/personal/repo"
cd "$W" && echo a > f && git add f
CLAUDECODE=1 git commit -qm agent 2>"$T/err"; rc=$?
check "agent commit refused (CLAUDECODE)" "$(is "$rc$(n "$W")" 11)"
check "refusal names the guard" "$(grep -q 'work-repo-guard (T1251)' "$T/err"; echo $?)"
CLAUDECODE=1 git commit -qm agent --no-verify 2>/dev/null; check "agent commit --no-verify refused (reference-transaction)" "$(is "$?$(n "$W")" 1281)"
HARNESS_AGENT=claude git commit -qm agent 2>/dev/null; check "agent commit refused (HARNESS_AGENT)" "$(is "$?$(n "$W")" 11)"
OPENCODE=1 git commit -qm agent 2>/dev/null; check "agent commit refused (OPENCODE)" "$(is "$?$(n "$W")" 11)"
cd "$T" && CLAUDECODE=1 git -C "$W" commit -qm agent 2>/dev/null; check "agent git -C from outside refused" "$(is "$?$(n "$W")" 11)"
CLAUDECODE=1 git -C "$W" hook run pre-commit 2>/dev/null; check "agent git hook run pre-commit refused (dry-run proof)" "$(is $? 1)"
git -C "$W" hook run pre-commit; check "human git hook run pre-commit passes" $?
git -C "$W" commit -qm human; check "human commit allowed" "$(is "$?$(n "$W")" 02)"
CLAUDECODE=1 git -C "$W" push -q origin main 2>/dev/null; check "agent push refused" "$(is "$?$(git -C "$T/remote.git" rev-parse -q --verify main >/dev/null; echo $?)" 11)"
CLAUDECODE=1 git -C "$W" push -q --no-verify origin main:agent 2>/dev/null; echo "info: agent push --no-verify rc=$? (hook layer cannot stop it; PreToolUse layer covers Claude Bash)"
git -C "$T/remote.git" update-ref -d refs/heads/agent 2>/dev/null
git -C "$W" push -q origin main; check "human push allowed" "$(is "$?$(git -C "$T/remote.git" rev-list --count main)" 02)"
CLAUDECODE=1 git -C "$W" checkout -q -b agentbranch 2>/dev/null; check "agent branch creation refused" "$(git -C "$W" rev-parse -q --verify agentbranch >/dev/null; is $? 1)"
CLAUDECODE=1 git -C "$W" log --oneline >/dev/null; check "agent read-only git allowed" $?
echo p > "$P/f"; git -C "$P" add f; CLAUDECODE=1 git -C "$P" commit -qm agent; check "agent commit in personal repo allowed" "$(is "$?$(n "$P")" 02)"
CLAUDECODE=1 git -C "$P" push -q origin main:personal; check "agent push from personal repo allowed" $?

printf '#!/bin/sh\necho ran >> "%s/own-pre-commit"\n' "$T" > "$W/.git/hooks/pre-commit"
printf '#!/bin/sh\necho "$1" >> "%s/own-commit-msg"\n' "$T" > "$W/.git/hooks/commit-msg"
printf '#!/bin/sh\ncat >> "%s/own-pre-push"\n' "$T" > "$W/.git/hooks/pre-push"
chmod +x "$W"/.git/hooks/pre-commit "$W"/.git/hooks/commit-msg "$W"/.git/hooks/pre-push
echo b >> "$W/f"; git -C "$W" commit -qam chained; git -C "$W" push -q origin main
check "repo's own pre-commit, commit-msg, pre-push chained" "$(is "$(wc -l <"$T/own-pre-commit")$(wc -l <"$T/own-commit-msg")$(grep -c refs/heads/main "$T/own-pre-push")" 111)"
printf '#!/bin/sh\nexit 1\n' > "$W/.git/hooks/pre-commit"; echo c >> "$W/f"
git -C "$W" commit -qam blocked 2>/dev/null; check "repo's own failing pre-commit still blocks the human" "$(is "$?$(n "$W")" 13)"
rm "$W/.git/hooks/pre-commit"; git -C "$W" checkout -q f

mk "$T/work2/husky"; git -C "$T/work2/husky" config core.hooksPath .husky
"$BIN/work-repo-guard" status >"$T/st"; rc=$?
check "status flags a repo-local hooksPath override (husky)" "$(is "$rc$(grep -c '^BAD .*husky: file:.git/config' "$T/st")" 11)"

ev() { python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
deny() { ev "$1" "$2" | "$HOOK" | grep -q '"permissionDecision": "deny"' && grep -q 'work-repo guard' < <(ev "$1" "$2" | "$HOOK"); }
for c in "git -C $W commit -m x" "git -C ~/work/repo commit --no-verify -m x" "cd ~/work/repo && git push --no-verify" \
         "bash -c \"git -C \$HOME/work/repo push\"" "git -c core.hooksPath=/dev/null commit -m x" "GIT_DIR=$W/.git git commit -m x" \
         "d=~/work/repo; git -C \$d push"; do
  deny "$c" "$W" || deny "$c" "$T"; check "PreToolUse denies: $c" $?
done
for c in "git -C $P commit -m x" "git commit -m x" "git -C ~/work/repo log | grep commit" "git -C ~/personal/repo push" \
         "T=\$(mktemp -d); cd \$T && git commit -qm init; ls ~/work/repo"; do
  ! deny "$c" "$P"; check "PreToolUse allows: $c" $?
done

# Selftest 2: the real gitconfig and real work repos were not written by this run.
check "selftest: real ~/.gitconfig unchanged" "$(is "$(sha256sum "$REAL_GCFG" 2>/dev/null)" "$sum0")"
touched=$(for r in $REAL_ROOTS; do r=${r/#\~/$REAL_HOME}; find "$r" -maxdepth 3 -name node_modules -prune -o -name .git -print 2>/dev/null; done |
  while read -r g; do find "$g/config" "$g/HEAD" "$g/hooks" "$g/refs/heads" -maxdepth 1 -newer "$stamp" 2>/dev/null; done)
check "selftest: no real work repo config, HEAD, hook or branch newer than the run start" "$(is "$touched" "")"
exit $fail
