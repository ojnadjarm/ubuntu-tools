#!/usr/bin/env bash
# cpp-tidy on planted fixtures: use-after-move + copy in a range loop give findings and rc 1; clean code rc 0; build-dir and out-of-tree TUs ignored; stub clang-tidy counts per-TU cache misses.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
TIDY=$G/scripts/cpp-tidy
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=$T/proj
mkdir -p "$P/src" "$P/build-bad" "$P/build-ok" "$T/vendor"
cp "$G/templates/cpp-vulkan/.clang-tidy" "$P/"
cat > "$P/src/bad.cpp" <<'CPP'
#include <string>
#include <utility>
#include <vector>
std::size_t use_after_move(std::string s) {
	std::string t = std::move(s);
	return s.size() + t.size();
}
std::size_t loop_copy(const std::vector<std::string>& v) {
	std::size_t n = 0;
	for (const auto x : v) n += x.size();
	return n;
}
CPP
cat > "$P/src/ok.cpp" <<'CPP'
#include <string>
#include <vector>
std::size_t total(const std::vector<std::string>& v) {
	std::size_t n = 0;
	for (const auto& x : v) n += x.size();
	return n;
}
CPP
cp "$P/src/bad.cpp" "$P/build-bad/gen.cpp"
cp "$P/src/bad.cpp" "$T/vendor/v.cpp"
db() {  # build-dir files...: CMakeCache.txt + compile_commands.json, each command carrying a module @modmap arg
	local b=$1; shift
	echo "CMAKE_HOME_DIRECTORY:INTERNAL=$P" > "$b/CMakeCache.txt"
	for f in "$@"; do jq -n --arg d "$b" --arg f "$f" '{directory: $d, file: $f, command: ("clang++ -std=c++20 @x/" + ($f | split("/") | last) + ".o.modmap -c " + $f)}'; done \
		| jq -s . > "$b/compile_commands.json"
}
db "$P/build-bad" "$P/src/bad.cpp" "$P/src/ok.cpp" "$P/build-bad/gen.cpp" "$T/vendor/v.cpp"
db "$P/build-ok" "$P/src/ok.cpp"
fails=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; fails=$((fails + 1)); }
"$TIDY" -j 2 "$P/build-bad" > "$T/bad.out" 2>&1; rc=$?
[ $rc = 1 ] && ok "planted fixture rc 1" || { ko "planted fixture rc $rc"; cat "$T/bad.out"; }
grep -q 'bad.cpp:6:.*\[bugprone-use-after-move' "$T/bad.out" && ok "use-after-move found" || ko "use-after-move"
grep -q 'bad.cpp:10:.*\[performance-for-range-copy' "$T/bad.out" && ok "range-loop copy found" || ko "range-loop copy"
n=$(sed -n 's/^TIDY findings=\([0-9]*\) files=2 .*/\1/p' "$T/bad.out")
[ "${n:-0}" -ge 2 ] && ok "findings=$n >= 2, files=2" || ko "summary line: $(tail -1 "$T/bad.out")"
grep -qE 'gen\.cpp|v\.cpp' "$T/bad.out" && ko "build-dir or vendor TU reported" || ok "build-dir and vendor TUs ignored"
"$TIDY" "$P/build-ok" > "$T/ok.out" 2>&1; rc=$?
[ $rc = 0 ] && grep -q '^TIDY findings=0 files=1 ' "$T/ok.out" && ok "clean source rc 0" || { ko "clean source rc $rc"; cat "$T/ok.out"; }
"$TIDY" "$T/nope" > /dev/null 2>&1; [ $? = 2 ] && ok "missing build dir rc 2" || ko "missing build dir"
"$TIDY" --help > /dev/null && ok "--help" || ko "--help"
S=$T/stub CALLS=$T/calls
mkdir -p "$S/src" "$S/inc" "$S/build" "$T/bin"
cat > "$T/bin/clang-tidy" <<'SH'
#!/usr/bin/env bash
case " $* " in *" --version "*) echo "stub clang-tidy 1"; exit 0 ;; *" -list-checks "*) exit 0 ;; esac
f=${!#}; echo "$f" >> "$CALLS"
[ -n "${STUB_FAIL:-}" ] && { echo "Error: stub failure" >&2; exit 1; }
echo "$f:1:1: warning: stub [stub-check]"
grep -q BAD "$f" && echo "$f:2:1: warning: planted [stub-bad]"
exit 0
SH
chmod +x "$T/bin/clang-tidy"
echo 'Checks: -*' > "$S/.clang-tidy"
printf '#include "a.hpp"\n' > "$S/src/a.cpp"
printf '#include <common.hpp>\n' > "$S/src/a.hpp"
printf '#include <common.hpp>\n// BAD\n' > "$S/src/b.cpp"
printf '#include <vector>\n' > "$S/src/c.cpp"
echo 'int common();' > "$S/inc/common.hpp"
echo "CMAKE_HOME_DIRECTORY:INTERNAL=$S" > "$S/build/CMakeCache.txt"
for f in a b c; do jq -n --arg d "$S/build" --arg f "$S/src/$f.cpp" --arg i "$S/inc" '{directory: $d, file: $f, command: ("clang++ -std=c++20 -I" + $i + " -c " + $f)}'; done \
	| jq -s . > "$S/build/compile_commands.json"
stub() {  # expected-calls label [env...]: run cpp-tidy with the stub, check stub calls and findings against the cold run
	: > "$CALLS"
	env PATH="$T/bin:$PATH" CALLS="$CALLS" "${@:3}" "$TIDY" "$S/build" > "$T/stub.out" 2>&1
	local c; c=$(grep -c . "$CALLS")
	grep -v '^TIDY ' "$T/stub.out" > "$T/stub.findings"
	[ -f "$T/cold.findings" ] || cp "$T/stub.findings" "$T/cold.findings"
	[ "$c" = "$1" ] && cmp -s "$T/stub.findings" "$T/cold.findings" && ok "$2: $c clang-tidy calls, findings identical" \
		|| { ko "$2: $c calls (want $1)"; cat "$T/stub.out"; }
}
stub 3 "cold"
grep -q 'b.cpp:2:1: warning: planted' "$T/cold.findings" && ok "cold findings" || ko "cold findings: $(cat "$T/cold.findings")"
stub 0 "warm"
grep -q '^TIDY findings=4 files=3 .* cached=3$' "$T/stub.out" && ok "warm summary cached=3" || ko "warm summary: $(tail -1 "$T/stub.out")"
echo '// edit' >> "$S/src/c.cpp"; stub 1 "one .cpp edited"
echo '// edit' >> "$S/inc/common.hpp"; stub 2 "included header edited"
echo '// edit' >> "$S/src/a.hpp"; stub 1 "quoted header edited"
echo '# edit' >> "$S/.clang-tidy"; stub 3 ".clang-tidy edited"
stub 3 "CPP_TIDY_NOCACHE=1" CPP_TIDY_NOCACHE=1
echo '// edit' >> "$S/src/c.cpp"
env PATH="$T/bin:$PATH" CALLS="$CALLS" STUB_FAIL=1 "$TIDY" "$S/build" > /dev/null 2>&1
stub 1 "failed TU not cached"
echo "cpp-tidy.test: $fails failed"
exit $((fails > 0))
