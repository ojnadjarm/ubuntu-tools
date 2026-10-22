#!/usr/bin/env bash
# pc-disk on a mktemp fixture tree: dupes grouped, reclaim links/deletes/compresses only what is allowed, owner/build/claimed/undone refused, pc undo splits and decompresses; mutants go red.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
case $R in /tmp/*) ok 'sandbox: fixture root under /tmp';; *) nok sandbox "$R"; exit 1;; esac

# fixture — a fresh tree, history, claims board and ledger under $R/<name>.
fixture() {
  local F=$1 W; rm -rf "$F"; W="$F/aw/research/2026-10-01"; mkdir -p "$F"
  blob() { mkdir -p "${2%/*}"; head -c 2097152 /dev/zero | tr '\0' "$1" >"$2"; }
  blob a "$W/T100/a.bin"; blob a "$W/T100/copy/a2.bin"; blob a "$F/aw/owner/o1.bin"; blob a "$F/aw/games/g/build/b1.bin"
  blob y "$W/T100/young1.bin"; blob y "$W/T100/young2.bin"
  blob c "$W/T101/c1.bin"; blob c "$W/T101/c2.bin"; blob a "$W/T100/build/a3.bin"
  blob t "$W/T100/trace.json"; blob l "$W/T100/recent.log"; blob p "$W/T100/img.png"
  mkdir -p "$W/T100/.venv/lib/python3.12/site-packages/foo-1.0.dist-info" "$W/T102/.venv" "$W/T100/web/node_modules/x" \
    "$W/T100/new/node_modules" "$W/T100/tools/blender/lib/python3.11/venv"
  printf 'home = /usr/bin\n' | tee "$W/T100/.venv/pyvenv.cfg" >"$W/T102/.venv/pyvenv.cfg"
  printf 'Name: foo\nVersion: 1.0\n' >"$W/T100/.venv/lib/python3.12/site-packages/foo-1.0.dist-info/METADATA"
  echo '{}' >"$W/T100/web/package-lock.json"
  blob w "$W/T100/.venv/w.bin"; ln "$W/T100/.venv/w.bin" "$W/T100/.venv/w2.bin"; blob v "$W/T100/.venv/v.bin"; ln "$W/T100/.venv/v.bin" "$W/T100/keep.bin"
  for d in web/node_modules/x new/node_modules tools/blender/lib/python3.11/venv; do echo x >"$W/T100/$d/f.js"; done
  printf -- '- 2026-10-01 T100: done\n- 2026-10-01 T101: done\n- 2026-10-01 T1020: see T102\n' >"$F/history.md"
  printf -- '- T101 · %s · 2026-10-01 10:00\n' "$W/T101" >"$F/claims.md"
  find "$F/aw" -exec touch -h -d '-20 days' {} +
  touch -d '-2 hours' "$W/T100/young1.bin" "$W/T100/young2.bin"; touch -d '-3 days' "$W/T100/recent.log" "$W/T100/new/node_modules/f.js"
}

# run_cases <pc-disk> — every assertion, so a mutant runs through the same cases.
run_cases() {
  local P=$1 F="$R/case" W out dry ids id
  fixture "$F"; W="$F/aw/research/2026-10-01"
  export PC_DISK_HISTORY="$F/history.md" PC_DISK_CLAIMS="$F/claims.md" PC_LEDGER="$F/changes.jsonl" PC_DISK_MIN_MB=1 PC_DISK_ZSTD_MB=1 \
    PC_DISK_PROTECT="$F/aw/owner"

  out=$("$P" dupes "$F/aw")
  is 'dupes: header' "$(head -1 <<<"$out" | tr -s ' ')" 'MB COPIES SAVED_MB FILES'
  is 'dupes: 3 groups outside owner/ and build/' "$(tail -1 <<<"$out")" '3 groups, 3 extra copies, 6 MB'

  dry=$("$P" reclaim "$F/aw")
  is 'dry: planned actions' "$(awk '$1 ~ /^(link|delete|compress)$/ {print $1, $2}' <<<"$dry" | sed "s#$W/##" | sort | tr '\n' ';')" \
    'compress T100/trace.json;delete T100/.venv;delete T100/web/node_modules;link T100/copy/a2.bin;'
  is 'dry: owner/ refused' "$(grep -c "^skip *$F/aw/owner .*owner data" <<<"$dry")" 1
  is 'dry: games build/ refused' "$(grep -c "^skip *$F/aw/games/g/build .*rewritten nightly" <<<"$dry")" 1
  is 'dry: other build/ listed as a skip row' "$(grep -c "^skip *$W/T100/build .*not scanned" <<<"$dry")" 1
  out=$("$P" reclaim "$F")
  is 'dry: owner data refused from a root above it' "$(grep -c "^skip *$F/aw/owner .*owner data" <<<"$out") $(grep -c "^skip *$F/aw/games/g/build .*rewritten nightly" <<<"$out")" '1 1'
  "$P" reclaim "$F/aw/owner" >/dev/null 2>&1; is 'dry: root inside owner data exits 2' "$?" 2
  is 'dry: claimed path refused' "$(grep -c "^skip *$W/T101/c[12].bin .*claimed" <<<"$dry")" 1
  is 'dry: ticket without a done line refused' "$(grep -c "^skip *$W/T102/.venv .*no done line" <<<"$dry")" 1
  is 'dry: young copy refused' "$(grep -c "^skip *$W/T100/young[12].bin .*idle" <<<"$dry")" 1
  is 'dry: idle < 7 d tree refused' "$(grep -c "^skip *$W/T100/new/node_modules .*idle" <<<"$dry")" 1
  is 'dry: last line' "$(tail -1 <<<"$dry")" 'would: link 1 files 2 MB, delete 2 trees 2 MB, compress 1 files 2 MB (--apply)'
  [ ! -e "$PC_LEDGER" ] && [ ! "$W/T100/a.bin" -ef "$W/T100/copy/a2.bin" ] && [ -d "$W/T100/.venv" ] && ok 'dry: nothing changed' || nok 'dry' 'changed state'

  cp "$W/T100/trace.json" "$F/trace.orig"
  out=$("$P" reclaim "$F/aw" --apply)
  [ "$W/T100/a.bin" -ef "$W/T100/copy/a2.bin" ] && ok 'apply: dup pair hardlinked' || nok 'apply: link' 'not linked'
  [ ! "$W/T100/a.bin" -ef "$F/aw/owner/o1.bin" ] && [ ! "$W/T100/a.bin" -ef "$F/aw/games/g/build/b1.bin" ] && ok 'apply: owner/ and build/ copies untouched' || nok 'apply: refused copies' 'linked'
  [ ! "$W/T101/c1.bin" -ef "$W/T101/c2.bin" ] && ok 'apply: claimed pair not linked' || nok 'apply: claimed' 'linked'
  [ ! "$W/T100/young1.bin" -ef "$W/T100/young2.bin" ] && ok 'apply: young pair not linked' || nok 'apply: young' 'linked'
  [ ! -e "$W/T100/.venv" ] && [ ! -e "$W/T100/web/node_modules" ] && ok 'apply: done ticket trees deleted' || nok 'apply: delete' 'still there'
  is 'apply: venv freeze kept for recreate' "$(cat "$W/T100/.venv.freeze.txt" 2>/dev/null)" 'foo==1.0'
  [ -d "$W/T102/.venv" ] && [ -d "$W/T100/new/node_modules" ] && [ -f "$W/T100/tools/blender/lib/python3.11/venv/f.js" ] && ok 'apply: refused trees and stdlib venv kept' || nok 'apply: kept trees' 'deleted'
  [ -f "$W/T100/trace.json.zst" ] && [ ! -e "$W/T100/trace.json" ] && [ -f "$W/T100/recent.log" ] && [ -f "$W/T100/img.png" ] && ok 'apply: only the old json compressed' || nok 'apply: compress' 'wrong set'
  is 'apply: one ledger row per action, all verified' "$(jq -s -r '[.[] | select(has("target"))] | length' "$PC_LEDGER") $(jq -s -r '[.[] | select(has("verified") and .verified == true)] | length' "$PC_LEDGER")" '4 4'
  is 'apply: last line names the rollback' "$(tail -1 <<<"$out")" 'rollback: pc undo <id> per action (4 ids)'

  id=$(jq -r 'select(has("target")) | select(.target | endswith("a2.bin")) | .id' "$PC_LEDGER")
  "$BIN/pc-undo" "$id" --apply >/dev/null 2>&1
  [ ! "$W/T100/a.bin" -ef "$W/T100/copy/a2.bin" ] && cmp -s "$W/T100/a.bin" "$W/T100/copy/a2.bin" && ok 'undo: link split, bytes equal' || nok 'undo: split' 'still linked or differs'
  id=$(jq -r 'select(has("target")) | select(.target | endswith("trace.json")) | .id' "$PC_LEDGER")
  "$BIN/pc-undo" "$id" --apply >/dev/null 2>&1
  cmp -s "$W/T100/trace.json" "$F/trace.orig" && [ ! -e "$W/T100/trace.json.zst" ] && ok 'undo: zstd -d restores the file' || nok 'undo: decompress' 'not restored'
  id=$(jq -r 'select(has("target")) | select(.target | contains(".venv")) | .id' "$PC_LEDGER")
  out=$("$BIN/pc-undo" "$id" --apply 2>&1)
  is 'undo: deleted tree prints the recreate hint' "$(grep -c "recreate: python3 -m venv $W/T100/.venv && $W/T100/.venv/bin/pip install -r $W/T100/.venv.freeze.txt" <<<"$out")" 1

  F="$R/case2"; fixture "$F"; W="$F/aw/research/2026-10-01"
  export PC_DISK_HISTORY="$F/history.md" PC_DISK_CLAIMS="$F/claims.md" PC_LEDGER="$F/changes.jsonl" PC_DISK_PROTECT="$F/aw/owner"
  mkdir -p "$R/fakebin"; printf '#!/bin/sh\nexit 1\n' >"$R/fakebin/zstd"; chmod +x "$R/fakebin/zstd"
  out=$(PATH="$R/fakebin:$PATH" "$P" reclaim "$F/aw" --apply 2>/dev/null); rc=$?
  is 'zstd fails: run continues, rc 1' "$rc $(grep -c '^compress .*: FAILED' <<<"$out") $(grep -c ': ok, rollback' <<<"$out")" '1 1 3'
  is 'zstd fails: every ledger row has a verified row' "$(jq -s -r '[.[] | select(has("target"))] | length' "$PC_LEDGER") $(jq -s -r '[.[] | select(has("verified"))] | length' "$PC_LEDGER")" '4 4'
}
run_cases "$BIN/pc-disk"

# mutant <name> <sed-expr> — a copy of pc-disk with the edit must fail at least one case.
mutant() {
  local m="$R/m-$1"; mkdir -p "$m"; sed "$2" "$BIN/pc-disk" >"$m/pc-disk"; chmod +x "$m/pc-disk"
  cmp -s "$BIN/pc-disk" "$m/pc-disk" && { nok "mutant $1" 'sed changed nothing'; return; }
  (bad=0; run_cases "$m/pc-disk" >/dev/null 2>&1; exit $bad) && nok "mutant $1" 'still green' || ok "mutant $1 is red"
}
mutant no-claims 's/^\( *\)if claimed(.*:$/\1if False:/'
mutant no-owner 's/^\( *\)if p in PROTECT:/\1if False:/'
mutant no-root-guard 's/^\( *\)if protected(root):/\1if False:/'
mutant no-build 's/^\( *\)if BUILD_RE.search(rel):/\1if False:/'
mutant no-build-row 's/^\( *\)skips.append((p, "build output, not scanned"))/\1pass/'
mutant double-count 's/ if n >= st.st_nlink)/)/'
mutant oserror-only 's/except (OSError, subprocess.SubprocessError)/except OSError/'
mutant no-done-line 's/^\( *\)if not done(t):/\1if False:/'
mutant no-idle 's/^\( *\)elif idle_h(p) < LINK_IDLE_H.*:$/\1elif False:/'
exit $bad
