#!/usr/bin/env bash
# cpp-ci crash triage on a throwaway copy of the template (real release build, Iris Xe under headless weston): game --crash-test leaves a symbolized stack.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ -x "${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}/vcpkg" ] || { echo "SKIP needs vcpkg (install.sh --gamedev)"; exit 0; }
CI=$G/scripts/cpp-ci
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
ulimit -c 0
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
"$CI" --stages "configure build run" --frames 30 --game-args --crash-test "$P" > "$T/out.log" 2>&1
ok "crash run exits 1" "[ $? = 1 ]"
S=$P/ci/summary.json
line=$(grep -n '^    \*target = 1;' "$P/src/main.cpp" | cut -d: -f1)
ok "run fails with rc 139" "jq -e '.stages.run | .status == \"fail\" and .rc == 139' '$S' > /dev/null"
ok "crash signal SIGSEGV" "jq -e '.stages.run.crash.signal == \"SIGSEGV\"' '$S' > /dev/null"
ok "top frame crash_test at main.cpp:$line" \
	"jq -e --argjson l '$line' '.stages.run.crash.frames[0] | (.fn | contains(\"crash_test\")) and (.file | endswith(\"/src/main.cpp\")) and .line == \$l' '$S' > /dev/null"
ok "caller main in frames, at most 8" "jq -e '.stages.run.crash.frames | length <= 8 and any(.fn == \"main\")' '$S' > /dev/null"
"$CI" --stages "configure build run" --frames 30 "$P" > "$T/out.log" 2>&1
ok "clean run passes without crash" "[ $? = 0 ] && jq -e '.stages.run | .status == \"pass\" and has(\"crash\") == false' '$S' > /dev/null"
[ $fails = 0 ] || { cat "$T/out.log"; jq . "$S"; }
echo "cpp-crash.test: $fails failed"
exit $((fails > 0))
