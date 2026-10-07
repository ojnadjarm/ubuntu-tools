#!/usr/bin/env bash
# Fixtures for ~/agents/bin/guide: index print, ranking over guides and skills, no match, new.
set -uo pipefail
G="$HOME/agents/bin/guide"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export GUIDES_DIR="$WORK/guides" SKILLS_DIR="$WORK/skills"
mkdir -p "$GUIDES_DIR" "$SKILLS_DIR/web" "$SKILLS_DIR/nofront" "$SKILLS_DIR/folded"
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }

printf '# Guides\n\n- wait-jobs — wait on a job · triggers: sleep loop, poll · verified 2026-09-24\n- tts-words — narration with word timings; skill /speak · triggers: kokoro, tts · verified 2026-09-24\n' >"$GUIDES_DIR/INDEX.md"
printf '# T\n' >"$GUIDES_DIR/TEMPLATE.md"
printf -- '---\nname: web\ndescription: Drive a web page, poll it for text.\n---\nbody poll kokoro\n' >"$SKILLS_DIR/web/SKILL.md"
printf 'name: nofront\ndescription: kokoro\n' >"$SKILLS_DIR/nofront/SKILL.md"
printf -- '---\nname: folded\ndescription: >\n  Export a game\n  for Windows builds.\nlicense: MIT\n---\n' >"$SKILLS_DIR/folded/SKILL.md"

ok "no args prints the index" 3 "$("$G" | grep -c '^- \|^# ')"
out=$("$G" how to poll a sleep loop)
ok "guide outranks a weaker skill" "guide" "$(sed -n 1p <<<"$out" | cut -d' ' -f1)"
ok "score is shown" "3/3" "$(sed -n 1p <<<"$out" | awk '{print $2}')"
ok "skill found by its description" 1 "$(grep -c "$SKILLS_DIR/web" <<<"$out")"
ok "skill body and files without front matter are ignored" 1 "$("$G" kokoro | grep -c '^guide\|^skill')"
ok "folded description is searched" "skill 2/2" "$("$G" windows builds | sed -n 1p | cut -d' ' -f1,2)"
ok "folded description stops at the next key" 0 "$("$G" mit license 2>/dev/null | grep -c folded)"
ok "stem: narrated finds narration" "guide 1/1" "$("$G" narrated | sed -n 1p | cut -d' ' -f1,2)"
ok "hyphen splits: word-synced finds word" 1 "$("$G" word-synced | grep -c tts-words)"
ok "guide line names its skill" 1 "$("$G" narration | grep -c '→ invoke /speak')"
ok "skill line says invoke" 1 "$("$G" windows | grep -c '→ invoke /folded')"
ok "matches start at a word: wait does not hit await" 0 "$(printf -- '---\nname: gd\ndescription: use await for signals\n---\n' >"$SKILLS_DIR/gd.md"; mkdir -p "$SKILLS_DIR/gd"; mv "$SKILLS_DIR/gd.md" "$SKILLS_DIR/gd/SKILL.md"; "$G" wait 2>/dev/null | grep -c '/gd ')"
"$G" zzzqqq 2>/dev/null; ok "no match exits 1" 1 $?
"$G" new new-thing >/dev/null; ok "new copies the template" "# T" "$(cat "$GUIDES_DIR/new-thing.md")"
"$G" new new-thing 2>/dev/null; ok "new refuses to overwrite" 2 $?
"$G" new Bad_Slug 2>/dev/null; ok "new rejects a bad slug" 2 $?

[ "$bad" = 0 ] && echo "all guide fixtures pass"
exit "$bad"
