#!/usr/bin/env bash
# Every flag the cpp-vulkan template's argument parser accepts (src/*.cpp) has a bullet in reference/cpp-vulkan.md "## Template flags", and every bullet there is still in the source; no build.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
src_flags() { grep -ho 'argv\[i\], "--[a-z0-9-]*"' "$1"/*.cpp | grep -o -- '--[a-z0-9-]*' | sort -u; }
doc_flags() { awk '/^## /{on = ($0 ~ /^## Template flags/)} on && /^- `--/' "$1" | grep -o -- '^- `--[a-z0-9-]*' | cut -c4- | sort -u; }
check() {  # src dir, doc: "missing <flag>" / "stale <flag>" lines, nothing when they agree
	comm -23 <(src_flags "$1") <(doc_flags "$2") | sed 's/^/missing /'
	comm -13 <(src_flags "$1") <(doc_flags "$2") | sed 's/^/stale /'
}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '%s\n' 'if (std::strcmp(argv[i], "--alpha") == 0) a = 1;' 'else if (std::strcmp(argv[i], "--beta") == 0) b = 1;' > "$T/main.cpp"
printf '%s\n' '# x' '- `--beta` elsewhere' '## Template flags' '- `--alpha N`: a' '- `--gone`: removed' '## Next' '- `--beta`: other section' > "$T/doc.md"
out=$(check "$T" "$T/doc.md" | tr '\n' ' ')
[ "$out" = "missing --beta stale --gone " ] && ok "fixture names missing and stale flags" || bad "fixture: got '$out'"

n=$(src_flags "$G/templates/cpp-vulkan/src" | wc -l)
[ "$n" -ge 10 ] && ok "source parser: $n flags" || bad "source parser: only $n flags found"
out=$(check "$G/templates/cpp-vulkan/src" "$G/reference/cpp-vulkan.md")
[ -z "$out" ] && ok "reference/cpp-vulkan.md documents all $n flags" || while read -r l; do bad "reference/cpp-vulkan.md $l"; done <<< "$out"
echo "cpp-flags-doc: $fails failed"
[ "$fails" -eq 0 ]
