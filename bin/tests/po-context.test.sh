#!/usr/bin/env bash
# T1557-C2 po-context: `check` (layout, caps, manager-only rules) and `repo` (REPO.md from a clone, read-only).
# Fixture-only (FLEET §5.6): bwrap --unshare-net, HARNESS_HOME and AGENT_WORK in a temp dir, a fixture git repo with a
# bare remote, a fake gh; the selftest proves no route out and that the real PO folders are untouched.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${PO_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --unshare-net --setenv PO_SANDBOXED 1 -- bash "$SELF"
fi
. "$BIN/tests/lib/assert.sh"
REAL_HOME="${HARNESS_HOME:-$HOME/agents}"
real_sum() { find "$REAL_HOME"/po-*/state -maxdepth 1 -type f -printf '%p %s %T@\n' 2>/dev/null | sort | sha1sum; }
real_before=$(real_sum)

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export HARNESS_ENV_LOADED=1 HARNESS_HOME="$WORK/agents" AGENT_WORK="$WORK/agent-work" HARNESS_CONFIG=/dev/null HOME="$WORK"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@fx GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@fx
mkdir -p "$HARNESS_HOME/discord-liaison" "$AGENT_WORK/decisions" "$WORK/stubs"
cp -r "$BIN/../po-template" "$HARNESS_HOME/po-template"
printf '#!/bin/sh\n[ -e "$WORK/gh.fail" ] && exit 4\necho "$*" >"$WORK/gh.args"\ncat "$WORK/gh.out" 2>/dev/null\n' >"$WORK/stubs/gh"
chmod +x "$WORK/stubs/gh"
export PATH="$WORK/stubs:$BIN:$PATH" WORK

# selftest
if curl -sS -m 3 -o /dev/null https://github.com 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
ok 'selftest: no route to github.com'
is 'selftest: gh is the fake' "$(command -v gh)" "$WORK/stubs/gh"
case "$HARNESS_HOME" in "$WORK"/*) ok 'selftest: HARNESS_HOME is the fixture';; *) nok 'selftest: HARNESS_HOME' "$HARNESS_HOME";; esac

# fixture: a manager fx (with clone), a manager nc (repo, not cloned), a router rt (no PARENT)
po-new fx "Fixture" --parent rt >/dev/null && po-new nc "No clone" --parent rt >/dev/null && po-new rt "Router" >/dev/null
touch "$AGENT_WORK/decisions/fx.md" "$AGENT_WORK/decisions/nc.md"
cat >"$HARNESS_HOME/discord-liaison/projects.json" <<'JSON'
{"router": {}, "projects": [
 {"id": "fx", "po": "po-fx", "repo": "o/fx", "clone": "~/clone"},
 {"id": "nc", "po": "po-nc", "repo": "o/nc", "clone": "~/missing"}]}
JSON
S="$HARNESS_HOME/po-fx/state"
git init -q --bare "$WORK/remote.git"
git init -q -b main "$WORK/clone" && cd "$WORK/clone" || exit 1
git commit -q --allow-empty -m one && git remote add origin "$WORK/remote.git" && git push -q -u origin main 2>/dev/null
git checkout -q -b feat && git commit -q --allow-empty -m two && git commit -q --allow-empty -m three
git checkout -q main && git branch pushed && git push -q origin pushed 2>/dev/null
git worktree add -q "$WORK/wt" feat 2>/dev/null; echo x >"$WORK/wt/dirty.txt"
git worktree add -q "$WORK/wt2" pushed 2>/dev/null
cd "$WORK" || exit 1
clone_sum() { (cd "$WORK/clone/.git" && find . -path ./logs -prune -o -type f -printf '%p %s %T@\n' | sort | sha1sum); }

# check: a fresh manager from the template misses only REPO.md (clone exists, no REPO.md yet)
out=$(po-context check fx); rc=$?
is 'check: fresh manager exits 1 without REPO.md' "$rc" 1
is 'check: the one miss is REPO.md' "$out" "miss: fx: REPO.md missing or older than 24 h (po-context repo fx)"
is 'check: fresh manager without a clone is ok' "$(po-context check nc)" "ok nc"
is 'check: router (no PARENT) is ok without HISTORY.md' "$(rm "$HARNESS_HOME/po-rt/state/HISTORY.md"; po-context check rt)" "ok rt"

# repo: REPO.md from the clone, read-only
printf '#7 Add login [feat -> main]\n' >"$WORK/gh.out"
before=$(clone_sum)
out=$(po-context repo fx); rc=$?
is 'repo: exits 0' "$rc" 0
ev 'repo: prints the file written' '[[ "$out" == "wrote $S/REPO.md ("*" lines)" ]]'
is 'repo: the clone is untouched' "$(clone_sum)" "$before"
r=$(cat "$S/REPO.md")
ev 'repo: HEAD line names branch and upstream' 'grep -qE "^HEAD: main [0-9a-f]+, ahead 0, behind 0 of origin/main$" <<<"$r"'
ev 'repo: open PR listed' 'grep -qxF -- "- #7 Add login [feat -> main]" <<<"$r" && grep -qx "## Open PRs (1)" <<<"$r"'
ev 'repo: gh asked for open PRs of the registry repo' 'grep -q -- "-R o/fx --state open" "$WORK/gh.args"'
ev 'repo: only feat has unpushed commits' 'grep -qx "## Branches with unpushed commits (1)" <<<"$r" && grep -qx -- "- feat: 2 commits on no remote" <<<"$r"'
ev 'repo: 3 worktrees, 1 dirty' 'grep -qx "## Worktrees (3, 1 dirty)" <<<"$r" && grep -qx -- "- feat (~/wt)" <<<"$r"'
ev 'repo: no temp file left' '[ ! -e "$S/.REPO.md.tmp" ]'
is 'check: ok after repo' "$(po-context check fx)" "ok fx"
touch "$WORK/gh.fail"
ev 'repo: gh failure is a line, not a stop' 'po-context repo fx >/dev/null && grep -qx "## Open PRs: unknown (gh exit 4)" "$S/REPO.md"'
rm "$WORK/gh.fail"; : >"$WORK/gh.out"
for i in $(seq 20); do git -C "$WORK/clone" branch -q "b$i" feat; done
po-context repo fx >/dev/null
ev 'repo: long lists are capped (8 + "N more")' 'grep -qx -- "- ... 13 more" "$S/REPO.md" && [ $(wc -l <"$S/REPO.md") -le 40 ]'
po-context repo nc >/dev/null
ev 'repo: no clone yet is one line' 'grep -q "is not cloned yet" "$HARNESS_HOME/po-nc/state/REPO.md"'
is 'repo: a PO without a registry repo writes nothing' "$(po-context repo rt >/dev/null; [ -e "$HARNESS_HOME/po-rt/state/REPO.md" ] && echo written || echo none)" none

# check: each cap and rule gives its own miss line
P="$S/PROJECT.md"; cp "$P" "$WORK/P.bak"
head -c 7000 /dev/zero | tr '\0' x >>"$P"
ev 'check: 7 KB PROJECT.md is a miss' 'grep -q "^miss: fx: PROJECT.md 7[0-9]* bytes > 6 KB" <<<"$(po-context check fx)"'
cp "$WORK/P.bak" "$P"; seq 90 >>"$P"
ev 'check: 90+ lines PROJECT.md is a miss' 'grep -q "^miss: fx: PROJECT.md 10[0-9] lines > 80" <<<"$(po-context check fx)"'
cp "$WORK/P.bak" "$P"; sed -i '/^## People/d' "$P"
ev 'check: a missing heading is a miss' 'grep -q "^miss: fx: PROJECT.md headings" <<<"$(po-context check fx)"'
cp "$WORK/P.bak" "$P"
for i in $(seq 31); do echo "| T$i | x | y | open |" >>"$S/BACKLOG.md"; done
ev 'check: 31 BACKLOG rows is a miss' 'grep -qx "miss: fx: BACKLOG.md 31 rows > 30 (done rows to RUNS.md)" <<<"$(po-context check fx)"'
sed -i '/^| T31 /d' "$S/BACKLOG.md"
is 'check: 30 BACKLOG rows (header not counted) is ok' "$(po-context check fx)" "ok fx"
mkdir -p "$S/refs/cards"; touch "$S/refs/cards/hero.png" "$S/refs/sheet.pdf"
echo "| sheet.pdf | maintainer | 2026-11-01 | rules |" >"$S/refs/INDEX.md"
is 'check: a file missing from refs/INDEX.md is a miss' "$(po-context check fx)" "miss: fx: refs/INDEX.md does not name refs/cards/hero.png"
echo "| cards/hero.png | owner | 2026-11-02 | hero |" >>"$S/refs/INDEX.md"
is 'check: refs covered by INDEX.md is ok' "$(po-context check fx)" "ok fx"
touch -d '2 days ago' "$S/REPO.md"
ev 'check: REPO.md older than 24 h is a miss' 'grep -q "REPO.md missing or older than 24 h" <<<"$(po-context check fx)"'
po-context repo fx >/dev/null
sed -i '/OpenRouter/d' "$HARNESS_HOME/po-fx/BRIEF.md"
ev 'check: a standing rule missing from BRIEF.md is a miss' 'grep -qx "miss: fx: BRIEF.md lacks the standing rule '"'OpenRouter'"'" <<<"$(po-context check fx)"'
rm "$AGENT_WORK/decisions/fx.md"; rm "$S/HISTORY.md"
out=$(po-context check fx); rc=$?
is 'check: misses exit 1' "$rc" 1
is 'check: one line per miss (rule, HISTORY, ledger)' "$(grep -c '^miss: fx: ' <<<"$out")" 3

# usage
po-context check nope >/dev/null 2>&1; is 'usage: unknown PO exits 2' "$?" 2
po-context frob fx >/dev/null 2>&1; is 'usage: unknown verb exits 2' "$?" 2

is 'selftest: real PO state untouched' "$(real_sum)" "$real_before"
[ "$bad" = 0 ] && echo "po-context.test: all passed" || echo "po-context.test: FAILED"
exit $bad
