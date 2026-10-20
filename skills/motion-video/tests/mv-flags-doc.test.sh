#!/usr/bin/env bash
# mv-flags-doc.test.sh: every --flag in a scripts/mv-* --help is documented on a SKILL.md or reference/*.md line, or under a ## heading, naming that CLI (T863, T912, T954).
set -uo pipefail
SKILL=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
cd "$SKILL" || exit 1
# Pass-through flags that belong to another tool, quoted in a CLI's help: "<cli> <flag>".
ALLOW="mv-beats --cues
mv-beats --sfx
mv-sfx --dump-camera
mv-sfx --cues
mv-sfx --sfx
mv-new --draft"
FLAGDOC="$SKILL/../../bin/tests/lib/flagdoc.awk"
check() {  # cli help "all clis" doc...: one FAIL line per --flag in help not documented under cli
  local cli=$1 help=$2 clis=$3 f w; shift 3
  for f in $(grep -oE -- '--[a-z][a-z0-9-]*' <<<"$help" | sort -u); do
    [[ $f == --help ]] && continue
    grep -qxF -- "$cli $f" <<<"$ALLOW" && continue
    n=$((n + 1))
    w=$(awk -v cli="$cli" -v flag="$f" -v clis="$clis" -f "$FLAGDOC" "$@")
    [[ $w == ok ]] && continue
    if [[ -n $w ]]; then echo "FAIL $cli $f documented only under another CLI ($w)"; else echo "FAIL undocumented $cli $f"; fi
  done
}
run() {  # script "all clis" doc...: one FAIL line for a --help rc != 0, else check's FAIL lines
  local s=$1 help rc; shift
  help=$(PATH="$STUB:$PATH" timeout 5 "$s" --help </dev/null 2>&1); rc=$?
  ((rc == 0)) || { echo "FAIL ${s##*/}: --help rc $rc"; return; }
  check "${s##*/}" "$help" "$@"
}
STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
printf '%s\n' '- `mv-fake --cols N`: a' '- `mv-other --rows N`: other only' '- `--loose` names no CLI' '## mv-fake knobs' '- `--deep`' '### Options' '- `--deeper`' > "$STUB/doc.md"
n=0
out=$(check mv-fake 'usage: mv-fake [--cols N] [--col] [--rows N] [--loose] [--deep] [--deeper]' "mv-fake mv-other" "$STUB/doc.md" | tr '\n' ';')
if [[ $out != "FAIL undocumented mv-fake --col;FAIL undocumented mv-fake --loose;FAIL mv-fake --rows documented only under another CLI (mv-other);" ]]; then
  echo "FAIL fixture: got '$out'"; exit 1
fi
printf '#!/bin/sh\necho "usage: mv-broken [--x]"\nexit 2\n' >"$STUB/mv-broken"; chmod +x "$STUB/mv-broken"
out=$(run "$STUB/mv-broken" "mv-broken" "$STUB/doc.md")
[[ $out == "FAIL mv-broken: --help rc 2" ]] || { echo "FAIL fixture rc: got '$out'"; exit 1; }
for t in ffmpeg ffprobe blender npx node vmaf; do printf '#!/bin/sh\nexit 1\n' >"$STUB/$t"; chmod +x "$STUB/$t"; done
clis=$(cd scripts && ls -d mv-* | tr '\n' ' ')
bad=0 n=0
for s in scripts/mv-*; do
  [[ -x $s ]] || continue
  run "$s" "$clis" SKILL.md reference/*.md >"$STUB/fails"
  cat "$STUB/fails"
  bad=$((bad + $(grep -c '^FAIL' "$STUB/fails")))
done
echo "flags $n, undocumented $bad"
((bad == 0))
