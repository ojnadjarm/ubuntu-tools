# Shared shell-test asserts: `ok`/`nok`/`is` print `ok   <name>` / `FAIL <name>: <why>` and set bad=1 on failure.
# Source it once near the top (`. "$HOME/agents/bin/tests/lib/assert.sh"`); it resets bad=0 and the test ends with `exit $bad`.
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
# eq <name> <want> <got>; truthy <name> 0|1; ev <name> <shell-condition> (eval'd in the caller's shell).
eq()     { is "$1" "$3" "$2"; }
truthy() { [ "$2" = 1 ] && ok "$1" || nok "$1" "false"; }
ev()     { eval "$2" && ok "$1" || nok "$1" "false: $2"; }
# t <label> — prints "$T_PREFIX: <label>" padded to $T_WIDTH (default 56) for a PASS/FAIL tail on the same line.
t()   { printf "%-${T_WIDTH:-56}s" "${T_PREFIX:+$T_PREFIX: }$1"; }
