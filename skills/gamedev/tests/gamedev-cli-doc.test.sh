#!/usr/bin/env bash
# Every flag in each gamedev CLI's --help is documented on a doc line, or under a ## heading, naming that CLI; no build.
set -u
export LC_ALL=C
G=$(cd "$(dirname "$0")/.." && pwd -P)
A=$(cd "$G/../.." && pwd)
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
# Pass-through flags of another tool (game, quiet-gate, cmake) quoted in a CLI's help: "<cli> <flag>".
ALLOW="cpp-ci --capture
cpp-ci --crash-test
cpp-ci --gpu
cpp-ci --install
cpp-ci --strip"
help_flags() {  # --flags anywhere in --help, -x flags on its usage line; returns the --help rc
	local h rc; h=$(timeout 5 "$1" --help 2>&1); rc=$?
	{ grep -oE -- '(^|[^a-z0-9-])--[a-z0-9][a-z0-9-]*' <<<"$h"; grep '^usage:' <<<"$h" | grep -oE -- '(^|[^a-z0-9-])-[a-z0-9][a-z0-9-]*'; } |
		grep -oE -- '--?[a-z0-9-]+' | grep -vxF -- --help | sort -u
	return $rc
}
FLAGDOC="$A/bin/tests/lib/flagdoc.awk"
check() {  # path "all clis" doc...: one line for a --help rc != 0 or no flags, else one per flag not documented under its own CLI
	local c=$1 clis=$2 name fl f w; shift 2
	name=$(basename "$c")
	fl=$(help_flags "$c") || { echo "$name: --help rc $?"; return; }
	[ -n "$fl" ] || { echo "$name: no flags in --help"; return; }
	for f in $fl; do
		grep -qxF -- "$name $f" <<<"$ALLOW" && continue
		w=$(awk -v cli="$name" -v flag="$f" -v clis="$clis" -f "$FLAGDOC" "$@")
		[ "$w" = ok ] && continue
		[ -n "$w" ] && echo "$name $f documented only under another CLI ($w)" || echo "$name $f undocumented"
	done
}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '%s\n' '#!/bin/sh' 'echo "usage: fake [-j N] [--alpha N] [--alpha-beta] [--gamma] [--delta] [--epsilon] [--beta] DIR"' 'echo "  --body-only in prose"' > "$T/fake"; chmod +x "$T/fake"
printf '%s\n' '- `fake --alpha N`: a' '- `fake --gammas`: not gamma' '- `--gamma` alone names no CLI' 'run `make -j 8` first' \
	'## fake options' '- `--delta`: under its heading' '### Flags' '- `--epsilon`: under a ### of it' '## other' '- `--beta`: other only' '```' '## fake' '```' '- `--body-only`: under the other heading' > "$T/doc.md"
out=$(check "$T/fake" "fake other" "$T/doc.md" | tr '\n' ';')
[ "$out" = "fake --alpha-beta undocumented;fake --beta documented only under another CLI (other);fake --body-only documented only under another CLI (other);fake --gamma undocumented;fake -j undocumented;" ] &&
	ok "fixture: another CLI, make -j, body flag, whole word, ## and ### heading" || bad "fixture: got '$out'"
printf '%s\n' '#!/bin/sh' 'echo "usage: broken [--x]"' 'exit 2' > "$T/broken"; chmod +x "$T/broken"
out=$(check "$T/broken" "broken" "$T/doc.md")
[ "$out" = "broken: --help rc 2" ] && ok "fixture: --help rc 2" || bad "fixture rc: got '$out'"

docs=("$G/SKILL.md" "$G"/reference/*.md)
und=0
clis=(cpp-ci cpp-report new-cpp-game game-ci asset-pipeline.sh cpp-tidy cpp-vk-run.sh gamedev-perf)
for c in "$G"/scripts/{cpp-ci,cpp-report,new-cpp-game,game-ci,asset-pipeline.sh,cpp-tidy,cpp-vk-run.sh} "$A/bin/gamedev-perf"; do
	miss=$(check "$c" "${clis[*]}" "${docs[@]}")
	[ -z "$miss" ] && ok "$(basename "$c"): $(help_flags "$c" | wc -l) flags documented" ||
		while IFS= read -r l; do bad "$l"; [[ $l == *documented* ]] && und=$((und + 1)); done <<<"$miss"
done
echo "gamedev-cli-doc: undocumented $und, $fails failed"
[ "$fails" -eq 0 ]
