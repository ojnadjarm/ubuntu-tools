#!/usr/bin/env bash
# pc-tmp on a fixture PC_TMP_ROOT with a fake history.md, claims board, ledger and one held fd: only the 3 eligible paths go; a chmod 000 dir fails loud.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
R=$(mktemp -d); HOLDER=
trap '[ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

case $R in /tmp/*) ok 'sandbox: fixture root under /tmp';; *) nok sandbox "$R"; exit 1;; esac
export PC_TMP_ROOT="$R/root" PC_TMP_HISTORY="$R/history.md" PC_TMP_CLAIMS="$R/claims.md" PC_LEDGER="$R/changes.jsonl"
S="$R/root/claude-$(id -u)/-home-x/sess/scratchpad"; V="$R/root/claude-$(id -u)/-home-x-moodle-envs-vass/sess/scratchpad"
for d in tmp.old tmp.new tmp.held remotion-webpack-bundle-a; do mkdir -p "$R/root/$d"; echo x >"$R/root/$d/f"; done
for d in T100 T101 T102 T103 T104-x; do mkdir -p "$S/$d/sub"; echo x >"$S/$d/sub/f"; done
mkdir -p "$V/T100"; echo x >"$V/T100/f"; echo x >"$R/root/cc1.ltrans0.o"
printf -- '- 2026-10-01 T100: done\n- 2026-10-01 T102 (w1): done\n- 2026-10-01 T103: done\n- 2026-10-01 T104: done\n- 2026-10-01 T999: see T101\n' >"$PC_TMP_HISTORY"
printf -- '- T102 · /x · 2026-10-01 10:00\n' >"$PC_TMP_CLAIMS"

age() { find "$1" -exec touch -h -d "-$2 hours" {} +; }
age "$R/root" 30
age "$R/root/tmp.new" 2; age "$R/root/cc1.ltrans0.o" 2; age "$S/T103" 2
touch "$S/T104-x/sub/f"
sleep 600 9<"$R/root/tmp.held/f" & HOLDER=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "/proc/$HOLDER/fd/9" ] && break; sleep 0.1; done

dry=$("$BIN/pc-tmp")
is 'header' "$(head -1 <<<"$dry" | tr -s ' ')" 'KIND PATH MB AGE REASON'
is 'dry run lists the 3 eligible' "$(awk 'NR > 1 && $1 != "would:" && $1 != "kept" {print $1, $2}' <<<"$dry" | sed "s#$R/root/##" | sort | tr '\n' ';')" \
  "build remotion-webpack-bundle-a;scratch claude-$(id -u)/-home-x/sess/scratchpad/T100;test-dir tmp.old;"
is 'held fd counted as kept' "$(grep -c '^kept (o[p]en fd/cwd): 1$' <<<"$dry")" 1
is 'dry run deletes nothing' "$(find "$R/root" -name f | wc -l)" 10
[ ! -e "$PC_LEDGER" ] && ok 'dry run writes no ledger' || nok 'dry run ledger' 'written'

out=$("$BIN/pc-tmp" --apply)
is 'last line is the rollback note' "$(tail -1 <<<"$out")" 'rollback: none, scratch only'
left=$(cd "$R/root" && find . -name f -o -name '*.o' | LC_ALL=C sort | tr '\n' ' ')
is 'only the 3 eligible removed' "$left" \
  "./cc1.ltrans0.o ./claude-$(id -u)/-home-x-moodle-envs-vass/sess/scratchpad/T100/f ./claude-$(id -u)/-home-x/sess/scratchpad/T101/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/T102/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/T103/sub/f ./claude-$(id -u)/-home-x/sess/scratchpad/T104-x/sub/f ./tmp.held/f ./tmp.new/f "
is 'one ledger entry' "$(jq -r '.rollback + "|" + .before' "$PC_LEDGER")" 'none, scratch only|3 paths, 3 MB'
is 'ledger after counts deleted and failed' "$(jq -r '"\(.after)|\(.verified)"' "$PC_LEDGER")" 'deleted 3, failed 0|true'

L="$R/root/tmp.locked"; mkdir -p "$L/d" "$R/root/tmp.free"; echo x >"$L/d/f"; echo x >"$R/root/tmp.free/f"
age "$L" 30; age "$R/root/tmp.free" 30; chmod 000 "$L/d"
if [ -r "$L/d" ]; then ok 'skip: chmod 000 is readable (root), rm failure not testable'; else
  out=$("$BIN/pc-tmp" --apply 2>"$R/err"); rc=$?
  is 'an rm -rf that leaves a path exits 1' "$rc" 1
  is 'stdout counts deleted and failed' "$(grep -o 'deleted [0-9]*, failed [0-9]*' <<<"$out")" 'deleted 1, failed 1'
  is 'ledger after names the failure, verified false' "$(tail -1 "$PC_LEDGER" | jq -r '"\(.after)|\(.verified)"')" "deleted 1, failed 1: $L|false"
  is 'stderr names the failed path' "$(cat "$R/err")" "pc tmp: still present after rm -rf: $L"
fi

PC_TMP_ROOT=/usr "$BIN/pc-tmp" >/dev/null 2>&1; is 'root outside /tmp refused' "$?" 2
exit $bad
