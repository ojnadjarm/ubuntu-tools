#!/usr/bin/env bash
# shader-stats: counts, GROW on an extra sample (rc 1), no change (rc 0), compile error / bad extension / missing tools (rc 2), int arith, --json shape; fixtures in mktemp.
set -u
S=$(cd "$(dirname "$0")/.." && pwd)/scripts/shader-stats
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/a" "$T/b" "$T/c"
frag() {  # dir extra-line: a fragment shader with one sample, plus the extra line
	printf '%s\n' '#version 450' 'layout(location = 0) in vec2 uv;' 'layout(location = 0) out vec4 o;' \
		'layout(set = 0, binding = 0) uniform sampler2D tex;' 'void main() {' '    o = texture(tex, uv) * 2.0;' "$2" '}' > "$1/f.frag"
}
frag "$T/a" ''
frag "$T/b" '    o += texture(tex, uv * 0.5);'
frag "$T/c" '    o += undefined_name;'

out=$("$S" --write-baseline "$T/base.tsv" "$T/a/f.frag" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -qE '^f\.frag +instr [0-9]+ +arith [0-9]+ +tex 1 +branch 0 +loop 0 +barrier 0$' <<<"$out" &&
	[ "$(head -1 "$T/base.tsv")" = "$(printf 'shader\tinstr\tarith\ttex\tbranch\tloop\tbarrier')" ] && grep -qP '^f\.frag\t\d+\t\d+\t1\t0\t0\t0$' "$T/base.tsv" &&
	ok "counts: tex 1, baseline TSV written" || bad "counts: rc $rc '$out'"

out=$("$S" --baseline "$T/base.tsv" "$T/a/f.frag" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q 'tex 1 (+0)' <<<"$out" && ! grep -q GROW <<<"$out" && ok "no change: rc 0, deltas +0" || bad "no change: rc $rc '$out'"

out=$("$S" --baseline "$T/base.tsv" "$T/b/f.frag" 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q 'tex 2 (+1)' <<<"$out" && grep -qE '^GROW f\.frag tex \+100 % \(1 -> 2\)$' <<<"$out" &&
	ok "extra sample: GROW tex +100 %, rc 1" || bad "extra sample: rc $rc '$out'"

out=$("$S" "$T/a/f.frag" "$T/c/f.frag" 2>&1); rc=$?
[ $rc -eq 2 ] && grep -qE '^ERROR f\.frag: ERROR: .*undefined_name' <<<"$out" && grep -q 'tex 1' <<<"$out" &&
	ok "compile error: rc 2, the error line, other shader still counted" || bad "compile error: rc $rc '$out'"

out=$("$S" --json --baseline "$T/base.tsv" "$T/b/f.frag" 2>&1); rc=$?
[ $rc -eq 1 ] && jq -e '(.shaders | length) == 1 and .shaders[0].shader == "f.frag" and (.shaders[0].counts | keys) == ["arith","barrier","branch","instr","loop","tex"]
	and .shaders[0].delta.tex == 1 and ([.grow[] | select(.metric == "tex")] == [{shader: "f.frag", metric: "tex", pct: 100, from: 1, to: 2}]) and .errors == []' <<<"$out" >/dev/null &&
	ok "--json: shaders, counts, delta, grow, errors" || bad "--json: rc $rc '$out'"

printf '%s\n' '#version 450' 'layout(local_size_x = 64) in;' 'layout(set = 0, binding = 0) buffer B { int v[]; };' \
	'void main() { int a = v[0]; v[1] = (a < 7 ? a / 3 : a % 5) ^ (a << 2); }' > "$T/i.comp"
out=$("$S" "$T/i.comp" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -qE '^i\.comp +instr [0-9]+ +arith ([5-9]|[1-9][0-9]+) ' <<<"$out" && ok "int math (/ % < << ^ ?:) counts as arith" || bad "int arith: rc $rc '$out'"

cp "$T/a/f.frag" "$T/x.glsl"
out=$("$S" "$T/x.glsl" 2>&1); rc=$?
[ $rc -eq 2 ] && grep -qx 'ERROR x.glsl: glslang: stage not inferable from the extension .*' <<<"$out" && ok "unknown extension: rc 2, names the cause" || bad "unknown extension: rc $rc '$out'"

out=$(PATH=/nonexistent "$(command -v python3)" "$S" "$T/a/f.frag" 2>&1); rc=$?
[ $rc -eq 2 ] && grep -qx 'ERROR f.frag: glslang: No such file or directory' <<<"$out" && ok "missing glslang: rc 2, not GROW's rc 1" || bad "missing tools: rc $rc '$out'"

"$S" --baseline "$T/missing.tsv" "$T/a/f.frag" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && ok "missing baseline: rc 2" || bad "missing baseline: rc $rc"

echo "shader-stats: $fails failed"
[ "$fails" -eq 0 ]
