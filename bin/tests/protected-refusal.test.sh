#!/usr/bin/env bash
# protected refusal (T2017): a fixture protected repo refuses an agent's commit and push at the git and PreToolUse layers; the real config, gitconfig and repos are never used.
set -uo pipefail
BIN="$HOME/agents/bin"; HOOK="$BIN/../hooks/sleep-loop-block.py"
REAL_HOME=$HOME; REAL_GCFG="$REAL_HOME/.gitconfig"; sum0=$(sha256sum "$REAL_GCFG" 2>/dev/null)
T=$(mktemp -d /tmp/prt-XXXXXX); trap 'rm -rf "$T"' EXIT
. "$BIN/tests/lib/assert.sh"
for v in CLAUDECODE CLAUDE_CODE_ENTRYPOINT HARNESS_AGENT OPENCODE GEMINI_CLI CODEX_SANDBOX CODEX_THREAD_ID WORK_REPO_ROOTS \
         PROTECTED_PROJECTS HARNESS_ENV_LOADED PC_NOT_OURS GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES FLEET_BACKUPS_DIR $(compgen -e PROTECTED_); do unset "$v"; done
export HOME="$T" GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 HARNESS_CONFIG="$T/config.env" HARNESS_HOME="$T/harness" AGENT_WORK="$T/agent-work"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
printf 'PROTECTED_PROJECTS="acme"\nPROTECTED_ACME_REPOS="~/work"\n' > "$HARNESS_CONFIG"
printf '[user]\n\tname = t\n' > "$GIT_CONFIG_GLOBAL"
mkdir -p "$HARNESS_HOME"
W="$T/work/repo"; P="$T/personal/repo"
mk() { git init -q -b main "$1" && git -C "$1" commit -q --allow-empty -m init && git init -q --bare "$2" &&
       git -C "$1" remote add origin "$2" && git -C "$1" push -q origin main; }
under() { local p l=$1; shift; for p in "$@"; do case $p in "$T"/*) ;; *) nok "$l" "$p outside $T"; exit 1 ;; esac; done; ok "$l"; }
case $T in "$REAL_HOME"/*) nok 'selftest: fixture root outside the real HOME' "$T"; exit 1 ;; esac
under 'selftest: config, gitconfig, repos, remotes and protected entries under the fixture' "$HARNESS_CONFIG" "$GIT_CONFIG_GLOBAL" \
      "$HARNESS_HOME" "$AGENT_WORK" "$W" "$P" "$T/work-remote.git" "$T/personal-remote.git" $("$BIN/protected" entries repo)
mk "$W" "$T/work-remote.git"; mk "$P" "$T/personal-remote.git"
"$BIN/work-repo-guard" install --apply >/dev/null
is 'selftest: the guard include points at the fixture repo root' "$(git config --global --get-regexp '^includeif\.' | grep -c "gitdir:$T/work/")" 1
is 'selftest: the fixture config names only acme' "$("$BIN/protected" projects | paste -sd' ')" acme
is 'selftest: the only protected repo entry is the fixture root' "$("$BIN/protected" entries repo | paste -sd' ')" "$T/work"

n() { git -C "$1" rev-parse HEAD; }
rmain() { git -C "$1" rev-parse main; }
echo a > "$W/f"; git -C "$W" add f; h=$(n "$W")
CLAUDECODE=1 git -C "$W" commit -qm agent 2>/dev/null; is 'agent commit in the protected repo refused' "$?:$(n "$W")" "1:$h"
git -C "$W" commit -qm human; r=$(rmain "$T/work-remote.git")
CLAUDECODE=1 git -C "$W" push -q origin main 2>/dev/null; is 'agent push from the protected repo refused' "$?:$(rmain "$T/work-remote.git")" "1:$r"
echo a > "$P/f"; git -C "$P" add f; h=$(n "$P")
CLAUDECODE=1 git -C "$P" commit -qm agent; rc=$?; ev 'control: agent commit in the personal repo passes' "[ $rc = 0 ] && [ $(n "$P") != $h ]"
CLAUDECODE=1 git -C "$P" push -q origin main; is 'control: agent push from the personal repo passes' "$?:$(rmain "$T/personal-remote.git")" "0:$(n "$P")"
is 'protected match repo names acme' "$("$BIN/protected" match repo "$W")" acme

event() { python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
deny() { event "$1" "$2" | "$HOOK" | grep -q '"permissionDecision": "deny"'; }
deny "git -C $W commit -m x" "$T"; is 'PreToolUse denies a commit in the protected repo' $? 0
deny "git -C $W push" "$T"; is 'PreToolUse denies a push from the protected repo' $? 0
deny "git -C $P commit -m x" "$T"; is 'PreToolUse allows a commit in the personal repo' $? 1
deny "git -C $P push" "$T"; is 'PreToolUse allows a push from the personal repo' $? 1

printf 'PROTECTED_PROJECTS=""\n' > "$T/none.env"
HARNESS_CONFIG="$T/none.env" "$BIN/protected" match repo "$W" >/dev/null; is 'mutation: a config with no project does not match the repo' $? 1

is 'selftest: the real ~/.gitconfig is unchanged' "$(sha256sum "$REAL_GCFG" 2>/dev/null)" "$sum0"
exit "$bad"
