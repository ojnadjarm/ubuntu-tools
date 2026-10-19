#!/usr/bin/env bash
# Fixtures for ~/agents/bin/owner-secret: a throwaway HOME and a fake value; the real ~/agents/secrets is never touched.
set -uo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
REAL_SECRETS="$HOME/agents/secrets"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"
S="$HOME/agents/secrets"
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

# Selftest: the tool must resolve to the fixture dir, never the real one.
[ "$S" != "$REAL_SECRETS" ] && [ "${S#"$WORK"/}" != "$S" ] || { echo "FAIL selftest: secrets dir is not the fixture"; exit 1; }
echo "PASS selftest: secrets dir is the fixture"

V1="fixture-value-aaa111"; V2="fixture-value-bbb222"
out="$(printf '%s\n' "$V1" | "$B/owner-secret" tok 2>&1)"; ok "write: rc 0" 0 $?
ok "write: content" "$V1" "$(cat "$S/tok")"
ok "write: file mode 600" 600 "$(stat -c %a "$S/tok")"
ok "write: dir mode 700" 700 "$(stat -c %a "$S")"
ok "write: value never printed" no "$(has "$V1" "$out")"

out="$(printf '%s\n' "$V2" | "$B/owner-secret" tok 2>&1)"; ok "exists: refused rc 1" 1 $?
ok "exists: content kept" "$V1" "$(cat "$S/tok")"
ok "exists: says --replace" yes "$(has -- "--replace" "$out")"

out="$(printf '%s\n' "$V2" | "$B/owner-secret" --replace tok 2>&1)"; ok "replace: rc 0" 0 $?
ok "replace: new content" "$V2" "$(cat "$S/tok")"
ok "replace: mode 600" 600 "$(stat -c %a "$S/tok")"
ok "replace: value never printed" no "$(has "$V2" "$out")"

for n in ../escape .hidden a/b ""; do
  printf '%s\n' "$V1" | "$B/owner-secret" "$n" >/dev/null 2>&1; ok "bad name '$n': rc 2" 2 $?
done
ok "bad names: nothing escaped" no "$([ -e "$HOME/agents/escape" ] && echo yes || echo no)"
printf '\n' | "$B/owner-secret" empty >/dev/null 2>&1; ok "empty value: rc 1" 1 $?
ok "empty value: no file" no "$([ -e "$S/empty" ] && echo yes || echo no)"
"$B/owner-secret" --bogus x </dev/null >/dev/null 2>&1; ok "bad flag: rc 2" 2 $?
ok "no temp files left" 0 "$(find "$S" -name '.*' -type f | wc -l)"

# A real pty: the typed value must not be echoed back.
if command -v script >/dev/null; then
  out="$( (sleep 0.5; printf '%s\r' "$V1") | script -qec "'$B/owner-secret' ttytok" /dev/null 2>&1)"; ok "tty: rc 0" 0 $?
  ok "tty: content" "$V1" "$(cat "$S/ttytok" 2>/dev/null)"
  ok "tty: no echo" no "$(has "$V1" "$out")"
  ok "tty: prompt shown" yes "$(has "no echo" "$out")"
fi

exit $(( bad > 0 ))
