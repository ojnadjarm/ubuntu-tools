#!/usr/bin/env bash
# T1599-M12: the owner-edit flow (PLAN §6 step 1, §10). A line he edits by hand survives `memory apply`, gains an
# `owner:` commit and a ledger line, and an older note never overwrites it; an Obsidian workspace change makes no commit.
# Sandbox only (AGENTS.md §5.6): HOME, AGENT_WORK and MEMORY_HOME are temp dirs over the synthetic memory-keeper fixture.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$BIN/.." && pwd)"
FX="$BIN/tests/fixtures/memory-keeper"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")"
fail=0
t() { printf '%-92s' "memory-owner-edit: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }
fixture_in_real() { grep -rqF 'Seed photos' "$REAL_STORE" --include='*.md' --exclude-dir=.git 2>/dev/null; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
St="$T/store" CARD="domains/garden/DOMAIN.md"
OLD='- Seed photos are 800 px wide. (26-02-01) ^gd01'
HIS='- Seed photos are 1200 px wide. (26-11-10) ^gd01'
mem() { "$BIN/memory" "$@"; }
head_of() { git -C "$St" rev-parse HEAD; }
older_note() {  # a note dated before his edit that still says the old value
  printf 'source: agent\nseat: -\ndomain: garden\ndate: 2026-02-01T10:00:00+0100\nsession: -\ntext: Seed photos are 800 px wide.\n' \
    >"$St/inbox/older-800.md"
}
swap() { python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a + "\n" in s; open(p, "w").write(s.replace(a + "\n", b + "\n"))' "$@"; }
his_edit() { swap "$St/$CARD" "$OLD" "$HIS"; }
setup() {  # a fresh synthetic store (git) with the real store's Obsidian ignore line and app.json
  rm -rf "$St" "$HOME" "$AGENT_WORK" "$T/proj"
  mkdir -p "$HOME" "$AGENT_WORK" "$T/proj"/{garden,kiln,harbor}
  cp -r "$FX/store" "$St"
  sed "s#@P@#$T/proj#" "$St/domains.map.in" >"$St/domains.map" && rm "$St/domains.map.in"
  grep -x '\.obsidian/workspace\*' "$REAL_STORE/.gitignore" >>"$St/.gitignore"
  mkdir -p "$St/.obsidian" && printf '{\n  "useMarkdownLinks": true\n}\n' >"$St/.obsidian/app.json"
  git -C "$St" init -q -b main && git -C "$St" add -A && git -C "$St" commit -q -m seed
}
store_is_fixture() {
  local h; h="$(MEMORY_HOME="$1" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")"
  [ "$h" = "$St" ] && [ "$(realpath -m "$h")" != "$(realpath -m "$REAL_STORE")" ]
}

t "selftest: the guard fails on the real store, passes on the fixture"
setup
{ ! store_is_fixture "$REAL_STORE" && store_is_fixture "$St" && [ "$(git -C "$St" log --format=%s)" = seed ] \
  && grep -qxF -- "$OLD" "$St/$CARD"; } && ok || { no "the store is not the sandbox fixture"; exit 1; }

t "edit before the run: his line survives apply, the older note is filed"
his_edit; older_note
S="$(mem stage)"; mem apply "$S" >"$T/a.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && grep -qxF -- "$HIS" "$St/$CARD" && ! grep -qF '800 px' "$St/$CARD" \
  && [ -f "$St/archive/notes/older-800.md" ] && [ ! -e "$St/inbox/older-800.md" ]; } && ok || no "rc $rc: $(cat "$T/a.out")"

t "edit before the run: an owner: commit holds his page and a ledger line"
oc="$(git -C "$St" log --format=%H --grep '^owner: ' | head -1)"
{ [ -n "$oc" ] && git -C "$St" show --name-only --format= "$oc" | grep -qx "$CARD" \
  && git -C "$St" show "$oc" -- "$CARD" | grep -qxF -- "+$HIS" \
  && git -C "$St" show "$oc" -- core/ledger.md | grep -q "^+- .*owner edit.*$CARD" \
  && git -C "$St" log -1 --format=%s | grep -q '^keeper: ' && [ -z "$(git -C "$St" status --porcelain)" ]; } \
  && ok || no "$(git -C "$St" log --format=%s)"

t "edit during the run: the keeper's older line refused, exit 1, his stays"
setup; older_note
S="$(mem stage)"
swap "$S/$CARD" "$OLD" "- Seed photos are 800 px wide, says the note. (26-02-01) ^gd01"
his_edit
mem apply "$S" >"$T/b.out" 2>&1; rc=$?
{ [ "$rc" = 1 ] && grep -q 'changed in the store and in the staging copy' "$T/b.out" && grep -qxF -- "$HIS" "$St/$CARD" \
  && git -C "$St" log -1 --format=%s | grep -q '^owner: ' && [ -f "$St/inbox/older-800.md" ]; } && ok || no "rc $rc: $(cat "$T/b.out")"
rm -rf "$S" "$S.base.tsv"

t "edit during the run, the keeper leaves the page: carried in, exit 0"
setup; older_note
S="$(mem stage)"; his_edit
mem apply "$S" >"$T/c.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && grep -qxF -- "$HIS" "$St/$CARD" && git -C "$St" log --format=%s | grep -q '^owner: '; } && ok || no "rc $rc: $(cat "$T/c.out")"

t "Obsidian: a workspace.json change makes no commit and is never tracked"
setup; S="$(mem stage)"; mem apply "$S" >/dev/null 2>&1   # settle the generated views first
h0="$(head_of)"
printf '{"main":{"id":"fixture-%s"}}\n' "$RANDOM" >"$St/.obsidian/workspace.json"
printf '{"lastOpenFiles":["%s"]}\n' "$CARD" >"$St/.obsidian/workspace-mobile.json"
S="$(mem stage)"; mem apply "$S" >"$T/d.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && [ "$(head_of)" = "$h0" ] && ! git -C "$St" ls-files | grep -q 'workspace' \
  && git -C "$St" ls-files | grep -qx '.obsidian/app.json' && [ -z "$(git -C "$St" status --porcelain)" ]; } \
  && ok || no "rc $rc, head moved: $(git -C "$St" log -2 --format=%s)"

t "edit before the run, the keeper rewrites it from a note: his kept, held"
setup; his_edit; older_note
S="$(mem stage)"
swap "$S/$CARD" "$HIS" "$OLD"
mem apply "$S" >"$T/e.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && grep -qxF -- "$HIS" "$St/$CARD" && ! grep -qF '800 px' "$St/$CARD" \
  && grep -qF "$CARD ^gd01 · held: owner edit wins · keeper's line: $OLD" "$St/REVIEW.md" \
  && grep -q '^apply · green · .* 1 held' "$T/e.out" && [ -z "$(git -C "$St" status --porcelain)" ]; } \
  && ok || no "rc $rc: $(cat "$T/e.out"; cat "$St/REVIEW.md" 2>&1)"

t "edit before the run: keeper lines on other ids of the page still land"
setup; his_edit; older_note
S="$(mem stage)"
swap "$S/$CARD" "$HIS" "$OLD"
swap "$S/$CARD" '- The catalogue builds with `make seeds`. (26-02-02) ^gd02' '- The catalogue builds with `make catalogue`. (26-02-02) ^gd02'
printf -- '- Seed packets list the sowing month. (26-11-10) ^gd07\n' >>"$S/$CARD"
mem apply "$S" >"$T/f.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && grep -qxF -- "$HIS" "$St/$CARD" && grep -q 'make catalogue.*\^gd02$' "$St/$CARD" && grep -q '\^gd07$' "$St/$CARD" \
  && [ "$(grep -c 'held: owner edit wins' "$St/REVIEW.md")" = 1 ]; } && ok || no "rc $rc: $(cat "$T/f.out"; cat "$St/$CARD")"

t "page deleted by hand before the run, the keeper writes it: deleted, held"
setup; rm "$St/$CARD"
S="$(mem stage)"
printf '# Garden\n- Seed photos are 800 px wide. (26-02-01) ^gd01\n' >"$S/$CARD"
mem apply "$S" >"$T/g.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && [ ! -e "$St/$CARD" ] && grep -qF "$CARD · held: owner edit wins · page deleted by hand" "$St/REVIEW.md"; } \
  && ok || no "rc $rc: $(cat "$T/g.out")"

t "the real store holds no fixture text"
! fixture_in_real && ok || no "fixture text found under the real store"

exit "$fail"
