#!/usr/bin/env bash
# pr-daily-branch on a throwaway fixture: local bare origin + fake gh; no network, no real repo.
set -uo pipefail
tool="$HOME/agents/bin/pr-daily-branch"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
ok() { echo "ok $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export GIT_CONFIG_GLOBAL="$t/gitconfig" GIT_CONFIG_NOSYSTEM=1 GH_PRS="$t/prs.json"
git config --file "$t/gitconfig" user.name fixture
git config --file "$t/gitconfig" user.email fixture@example.invalid
git config --file "$t/gitconfig" init.defaultBranch main
mkdir -p "$t/bin"
cat > "$t/bin/gh" <<'EOF'
#!/usr/bin/env bash
cat "$GH_PRS"
EOF
chmod +x "$t/bin/gh"
# The fixture is the sandbox (FLEET.md §5.6): the agents' git guard stays off its PATH, the fake gh goes first.
export PATH="$t/bin:$(tr ':' '\n' <<<"$PATH" | grep -vx "$HOME/agents/bin/guards" | paste -sd:)"

git init -q --bare "$t/origin.git"
git clone -q "$t/origin.git" "$t/work" 2>/dev/null
cd "$t/work" || exit 1
echo base > shared.txt; git add .; git commit -qm base; git push -q origin main
branch() { git switch -q -c "$1" main; echo "$3" > "$2"; git add .; git commit -qm "$1"; git push -q origin "$1"; git switch -q main; }
branch liaison/a a.txt a
branch liaison/b b.txt b
branch liaison/c shared.txt from-c
branch other/x x.txt x
branch liaison/diaria-2000-01-01 old.txt old
cat > "$GH_PRS" <<'EOF'
[{"number":2,"headRefName":"liaison/b","title":"B"},{"number":1,"headRefName":"liaison/a","title":"A"},
 {"number":3,"headRefName":"other/x","title":"X"},{"number":4,"headRefName":"liaison/diaria-2000-01-01","title":"old"}]
EOF

# Selftest: the fixture cannot reach a real repo or the real gh.
check "selftest: origin is the fixture" '[ "$(git remote get-url origin)" = "$t/origin.git" ]'
check "selftest: gh is the fake" '[ "$(command -v gh)" = "$t/bin/gh" ]'

out=$("$tool" "$t/work" --repo fixture/repo 2>&1); rc=$?
check "dry run lists the dev PRs oldest first" '[ $rc -eq 0 ] && grep -q "^would: liaison/diaria-[0-9-]* = origin/main + #1 liaison/a, #2 liaison/b$" <<<"$out"'
check "dry run creates nothing" '[ "$(git ls-remote --heads origin | grep -c diaria)" = 1 ] && ! ls -d "$t"/work-wt-* >/dev/null 2>&1'

out=$("$tool" "$t/work" --repo fixture/repo --name liaison/diaria-t --test 'test -f a.txt && test -f b.txt' --apply 2>&1); rc=$?
check "apply merges, tests and pushes" '[ $rc -eq 0 ] && grep -q "^pushed liaison/diaria-t [0-9a-f]*: #1 #2$" <<<"$out"'
git fetch -q origin; log=$(git log --format=%s origin/liaison/diaria-t)
check "one merge commit per PR" 'grep -q "^Rama diaria: une #1 (liaison/a)$" <<<"$log" && grep -q "^Rama diaria: une #2 (liaison/b)$" <<<"$log"'
check "other prefixes and old daily branches stay out" '! git merge-base --is-ancestor origin/other/x origin/liaison/diaria-t && ! git merge-base --is-ancestor origin/liaison/diaria-2000-01-01 origin/liaison/diaria-t'
check "the clone checkout is untouched and the worktree removed" '[ "$(git branch --show-current)" = main ] && [ -z "$(git status --porcelain)" ] && [ ! -d "$t/work-wt-liaison-diaria-t" ]'

before=$(git rev-parse origin/liaison/diaria-t)
out=$("$tool" "$t/work" --repo fixture/repo --name liaison/diaria-t --apply 2>&1); rc=$?
git fetch -q origin
check "a re-run is a no-op" '[ $rc -eq 0 ] && grep -q "^in: origin/liaison/b$" <<<"$out" && [ "$(git rev-parse origin/liaison/diaria-t)" = "$before" ]'

out=$("$tool" "$t/work" --repo fixture/repo --name liaison/diaria-red --test false --apply 2>&1); rc=$?
check "failing tests: exit 4 and no push" '[ $rc -eq 4 ] && [ -z "$(git ls-remote --heads origin liaison/diaria-red)" ]'

cat > "$GH_PRS" <<'EOF'
[{"number":1,"headRefName":"liaison/a","title":"A"},{"number":5,"headRefName":"liaison/c","title":"C"}]
EOF
git switch -q liaison/a; echo from-a > shared.txt; git commit -qam a2; git push -q origin liaison/a; git switch -q main
out=$("$tool" "$t/work" --repo fixture/repo --name liaison/diaria-c --apply 2>&1); rc=$?
wt="$t/work-wt-liaison-diaria-c"
check "conflict: exit 3, worktree kept, nothing pushed" '[ $rc -eq 3 ] && grep -q "^conflict: Rama diaria: une #5 (liaison/c): shared.txt;" <<<"$out" && [ -d "$wt" ] && [ -z "$(git ls-remote --heads origin liaison/diaria-c)" ]'
out=$("$tool" "$t/work" --repo fixture/repo --name liaison/diaria-c --apply 2>&1); rc=$?
check "re-run during an open merge refuses" '[ $rc -eq 3 ] && grep -q "merge in progress" <<<"$out"'
echo resolved > "$wt/shared.txt"; git -C "$wt" add shared.txt; git -C "$wt" commit -q --no-edit
out=$("$tool" "$t/work" --repo fixture/repo --name liaison/diaria-c --apply 2>&1); rc=$?
git fetch -q origin
check "after the fix the re-run pushes both" '[ $rc -eq 0 ] && git merge-base --is-ancestor origin/liaison/c origin/liaison/diaria-c && git merge-base --is-ancestor origin/liaison/a origin/liaison/diaria-c'
check "never a forced push" '! grep -nE -- "--force|\+refs|\"\+" "$tool"'

[ $fails -eq 0 ] && echo "PASS pr-daily-branch" || echo "FAIL pr-daily-branch ($fails)"
exit $((fails > 0))
