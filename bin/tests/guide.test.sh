#!/usr/bin/env bash
# Fixtures for ~/agents/bin/guide: index print, ranking over guides and skills, no match, new, stale.
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
ok "skill found by its description" 1 "$("$G" drive web page | grep -c "$SKILLS_DIR/web")"
ok "a weak one-word match under a strong hit is cut" 0 "$(grep -c "$SKILLS_DIR/web" <<<"$out")"
ok "skill body and files without front matter are ignored" 1 "$("$G" kokoro | grep -c '^guide\|^skill')"
ok "folded description is searched" "skill 2/2" "$("$G" windows builds | sed -n 1p | cut -d' ' -f1,2)"
ok "folded description stops at the next key" 0 "$("$G" mit license 2>/dev/null | grep -c folded)"
ok "stem: narrated finds narration" "guide 1/1" "$("$G" narrated | sed -n 1p | cut -d' ' -f1,2)"
ok "hyphen splits: word-synced finds word" 1 "$("$G" word-synced | grep -c tts-words)"
ok "guide line names its skill" 1 "$("$G" narration | grep -c '→ invoke /speak')"
ok "skill line says invoke" 1 "$("$G" windows | grep -c '→ invoke /folded')"
ok "matches start at a word: wait does not hit await" 0 "$(printf -- '---\nname: gd\ndescription: use await for signals\n---\n' >"$SKILLS_DIR/gd.md"; mkdir -p "$SKILLS_DIR/gd"; mv "$SKILLS_DIR/gd.md" "$SKILLS_DIR/gd/SKILL.md"; "$G" wait 2>/dev/null | grep -c '/gd ')"
"$G" zzzqqq 2>/dev/null; ok "no match exits 1" 1 $?
mkdir -p "$SKILLS_DIR/lanes"; printf -- '---\nname: lanes\ndescription: research lanes\n---\n' >"$SKILLS_DIR/lanes/SKILL.md"
"$G" lan >/dev/null 2>&1; ok "a short word needs the whole word: lan misses lanes" 1 $?
ok "an inflection still hits: lane finds lanes" 1 "$("$G" lane | grep -c '^skill ')"
"$G" --new new-thing >/dev/null; ok "--new copies the template" "# T" "$(cat "$GUIDES_DIR/new-thing.md")"
"$G" --new new-thing 2>/dev/null; ok "--new refuses to overwrite" 2 $?
"$G" --new Bad_Slug 2>/dev/null; ok "--new rejects a bad slug" 2 $?
"$G" --new two words 2>/dev/null; ok "--new takes one slug" 2 $?
"$G" new kokoro >/dev/null 2>&1; ok "new <word> searches, no stub" "0 absent" "$? $([ -e "$GUIDES_DIR/kokoro.md" ] && echo made || echo absent)"
"$G" --bogus 2>/dev/null; ok "unknown option exits 2" 2 $?

S="$WORK/stale"; mkdir -p "$S"; d40=$(date -d '-40 days' +%F); d10=$(date -d '-10 days' +%F)
printf -- '- young — y · verified %s\n- old — o · verified %s\n- undated — u · triggers: x\n' "$d10" "$d40" >"$S/INDEX.md"
touch "$S"/{young,old,undated,unindexed,TEMPLATE}.md
out=$(GUIDES_DIR="$S" "$G" --stale)
ok "--stale lists oldest first" "old young" "$(awk '$1 != "no" {printf "%s%s", s, $3; s=" "}' <<<"$out")"
ok "--stale shows the age in days" "40d" "$(sed -n 1p <<<"$out" | awk '{print $2}')"
ok "--stale lists undated and unindexed guides last" "undated unindexed" "$(sed -n '3,4p' <<<"$out" | awk '{printf "%s%s", s, $3; s=" "}')"
ok "--stale skips INDEX and TEMPLATE" 4 "$(grep -c . <<<"$out")"
ok "--stale 30 keeps only the old and the undated" "old undated unindexed" "$(GUIDES_DIR="$S" "$G" --stale 30 | awk '{printf "%s%s", s, $NF; s=" "}')"
GUIDES_DIR="$S" "$G" --stale soon 2>/dev/null; ok "--stale rejects a non-number" 2 $?

[ "$bad" = 0 ] && echo "all guide fixtures pass"
exit "$bad"
