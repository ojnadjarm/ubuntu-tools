#!/usr/bin/env bash
# Every executable in bin/ (libraries aside) is named in KB/toolbox.md or KB/guides/INDEX.md (T1546-G3).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
is() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$3', got '$2'"; fail=1; fi; }

# unnamed <bindir> <doc…>: executables no doc names as a whole word; pc-<x> also counts as `pc <x>`.
unnamed() {
  local bin="$1" f b; shift
  for f in "$bin"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    b="${f##*/}"
    case "$b" in *lib.sh|*_*.py) continue ;; esac
    named "$b" "$@" && continue
    case "$b" in pc-*) named "pc ${b#pc-}" "$@" && continue ;; esac
    echo "$b"
  done
}
named() {
  local re; re="$(printf '%s' "$1" | sed 's/[.]/\\./g')"; shift
  command grep -qE "(^|[^A-Za-z0-9_-])$re([^A-Za-z0-9_-]|\$)" "$@"
}

fx="$(mktemp -d)"; trap 'rm -rf "$fx"' EXIT
mkdir -p "$fx/bin"
for c in alpha alpha-beta pc-gamma pc-delta fleetlib.sh pc_top.py data.txt; do printf '#!/bin/sh\n' >"$fx/bin/$c"; done
chmod +x "$fx/bin"/* && chmod -x "$fx/bin/data.txt"
# shellcheck disable=SC2016
printf -- '- `alpha-beta --x` does it\n- `pc gamma` reads it\n' >"$fx/toolbox.md"
printf -- '- pc-delta-ish and pc deltas are longer names\n' >"$fx/INDEX.md"
is "a CLI named only inside a longer name is reported" "$(unnamed "$fx/bin" "$fx/toolbox.md" "$fx/INDEX.md" | tr '\n' ' ')" "alpha pc-delta "
printf -- '- alpha — in the index\n- pc-delta here\n' >"$fx/INDEX.md"
is "a name in INDEX.md counts; libraries and non-executables are skipped" "$(unnamed "$fx/bin" "$fx/toolbox.md" "$fx/INDEX.md")" ""

is "live: every bin/ executable is named in toolbox.md or INDEX.md" \
  "$(unnamed "$ROOT/bin" "$ROOT/KB/toolbox.md" "$ROOT/KB/guides/INDEX.md" | tr '\n' ' ')" ""
is "live: toolbox.md holds no moving machine fact" \
  "$(command grep -cE '7\.0\.0-[0-9]+|~[0-9]+ % used|[0-9]+ GB RAM' "$ROOT/KB/toolbox.md")" "0"

if [ "$fail" = 0 ]; then echo "toolbox-index.test.sh: all green"; else echo "toolbox-index.test.sh: FAILURES"; exit 1; fi
