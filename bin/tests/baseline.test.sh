#!/usr/bin/env bash
# Fixtures for ~/agents/bin/baseline.sh: a mktemp HOME, context dir and output dir, a stub dconf; the real backups dir is never written.
set -uo pipefail
S="$HOME/agents/bin/baseline.sh"
REAL="$HOME/agents/backups"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

H="$W/home"; CTX="$W/ctx/harness"; OUT="$W/out"; STUB="$W/stub"
mkdir -p "$H/agents/bin" "$CTX/hooks" "$CTX/skills/s" "$OUT" "$STUB" "$H/.claude"
echo x >"$H/CLAUDE.md"; echo x >"$H/agents/bin/tool"; echo x >"$H/.claude/settings.json"
echo '{}' >"$CTX/settings.json"; echo x >"$CTX/hooks/h.sh"; echo x >"$CTX/NOTES.md"
printf '#!/bin/sh\necho "[org/x]"\n' >"$STUB/dconf"; chmod +x "$STUB/dconf"
for i in $(seq -w 1 22); do : >"$OUT/2026-01-${i}_120000.tar.gz"; done
: >"$OUT/owner.tar.gz"; : >"$OUT/2026-01-01_1200.tar.gz"
run() { env HOME="$H" BASELINE_DIR="$OUT" HARNESS_CONTEXT_DIR="$CTX" PATH="$STUB:$PATH" "$S" "$@"; }

case "$OUT" in "$W"/*) eq "selftest: output dir is inside the mktemp dir" yes yes ;; *) eq "selftest: output dir is inside the mktemp dir" yes no ;; esac
new=$(run 2>"$W/err"); eq "run: rc 0" 0 $?
eq "run: tarball written in BASELINE_DIR" "$OUT" "$(dirname "$new")"
own=$(find "$OUT" -regextype posix-extended -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}\.tar\.gz' | wc -l)
eq "prune: 20 own tarballs kept" 20 "$own"
eq "prune: owner.tar.gz untouched" yes "$([ -e "$OUT/owner.tar.gz" ] && echo yes || echo no)"
eq "prune: non-matching stamp untouched" yes "$([ -e "$OUT/2026-01-01_1200.tar.gz" ] && echo yes || echo no)"
eq "prune: newest kept" yes "$([ -e "$new" ] && echo yes || echo no)"
eq "prune: oldest two gone" no "$([ -e "$OUT/2026-01-01_120000.tar.gz" ] || [ -e "$OUT/2026-01-02_120000.tar.gz" ] && echo yes || echo no)"
list=$(tar tzf "$new")
eq "context: HARNESS_CONTEXT_DIR settings.json" 1 "$(grep -cx 'harness/settings.json' <<<"$list")"
eq "context: HARNESS_CONTEXT_DIR *.md" 1 "$(grep -cx 'harness/NOTES.md' <<<"$list")"
eq "context: HOME/.claude not used" 0 "$(grep -c '^\.claude/' <<<"$list")"
eq "home files: CLAUDE.md" 1 "$(grep -cx 'CLAUDE.md' <<<"$list")"
eq "dconf: dconf.ini included" 1 "$(grep -cx 'dconf.ini' <<<"$list")"
eq "dconf: no MANIFEST when nothing skipped" 0 "$(grep -cx 'MANIFEST' <<<"$list")"

printf '#!/bin/sh\nexit 127\n' >"$STUB/dconf"
rm -f "$OUT"/*.tar.gz
new=$(run 2>"$W/err"); eq "no dconf: rc 0" 0 $?
eq "no dconf: no dconf.ini" 0 "$(tar tzf "$new" | grep -cx 'dconf.ini')"
eq "no dconf: says why on stderr" 1 "$(grep -c 'dconf: skipped (dconf dump rc 127)' "$W/err")"
eq "no dconf: MANIFEST says why" "dconf: skipped (dconf dump rc 127)" "$(tar xzOf "$new" MANIFEST)"

eq "--help prints" 1 "$("$S" --help | grep -c 'HARNESS_CONTEXT_DIR')"
eq "selftest: no tarball written to the real backups dir" no "$(case "$new" in "$REAL"/*) echo yes;; *) echo no;; esac)"
[ "$bad" = 0 ] && echo "ALL PASS"
exit $bad
