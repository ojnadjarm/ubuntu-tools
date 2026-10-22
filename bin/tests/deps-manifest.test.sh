#!/usr/bin/env bash
# bin/DEPS.tsv lists every external tool bin/*, the fleet tests and the motion-video + gamedev skill scripts call (scanner proven
# on a fixture first), and install.sh prints what is missing.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
SCAN="$BIN/tests/lib/deps_scan.py"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

# Fixture: stub tools zzfx-* on PATH, scripts that call some and only mention others.
mkdir -p "$WORK/stubs" "$WORK/agents/bin"
for t in a b c d e f g n1 n2 n3 n4 n5 n6 n7 n8 n9; do printf '#!/bin/sh\n' >"$WORK/stubs/zzfx-$t"; chmod +x "$WORK/stubs/zzfx-$t"; done
cat >"$WORK/agents/bin/fx-shell" <<'EOF'
#!/usr/bin/env bash
# zzfx-n1 is only named in this comment
zzfx-a --flag
x=$(echo hi | zzfx-b)
sudo -n zzfx-c >/dev/null
bash -c 'zzfx-d'
echo "run zzfx-n2 (zzfx-n3) | zzfx-n4"
cat <<USAGE
zzfx-n5 in a heredoc
USAGE
zzfx-n6() { :; }; zzfx-n6
awk '{ print | "zzfx-n7" }' /dev/null
msg='Rules, in prose; zzfx-n8 is a word here'
list=(a zzfx-n9 b)
EOF
printf '#!/usr/bin/env python3\nimport subprocess\nsubprocess.run(["zzfx-e", "-x"])\n' >"$WORK/agents/bin/fx-py"
mkdir -p "$WORK/pymods"; : >"$WORK/pymods/zzfxmod.py"
fx() { PATH="$WORK/stubs:$PATH" PYTHONPATH="$WORK/pymods" python3 "$SCAN" "$WORK/agents/bin" "$@"; }
case $WORK in "${TMPDIR:-/tmp}"/*) ok "sandbox: fixture in a temp dir";; *) nok sandbox "fixture in $WORK"; exit 1;; esac
is "scanner finds calls, skips comments, strings, heredocs, functions, awk programs, prose and array assignments" \
  "$(fx | cut -f1 | grep '^zzfx-' | tr '\n' ' ')" "zzfx-a zzfx-b zzfx-c zzfx-d zzfx-e "
printf 'zzfx-a\t-\tfx-shell\tadvisory\nzzfx-b\t-\tfx-shell\tadvisory\nzzfx-c\t-\tfx-shell\tadvisory\nzzfx-d\t-\tfx-shell\tadvisory\n' >"$WORK/DEPS.tsv"
out=$(fx --deps "$WORK/DEPS.tsv"); rc=$?
is "a tool missing from DEPS.tsv fails (rc)" "$rc" 1
is "the failure names it" "$(grep zzfx <<<"$out")" "MISSING zzfx-e - fx-py"
printf 'zzfx-e\t-\tfx-py\tadvisory\nsudo\tsudo\tfx-shell\tadvisory\n' >>"$WORK/DEPS.tsv"
fx --deps "$WORK/DEPS.tsv" >/dev/null; is "complete DEPS.tsv passes" "$?" 0
mkdir -p "$WORK/agents/bin/tests" "$WORK/skill/scripts"
printf '#!/usr/bin/env bash\nfx-shell && zzfx-f\npython3 -m zzfxmod\n' >"$WORK/agents/bin/tests/fx.test.sh"
printf '#!/usr/bin/env bash\nzzfx-g -y\n' >"$WORK/skill/scripts/fx-skill"
out=$(fx "$WORK/agents/bin/tests" "$WORK/skill/scripts" --deps "$WORK/DEPS.tsv"); rc=$?
is "a test or skill script calling a tool with no row fails (rc)" "$rc" 1
is "the failure names the test, its python3 -m module and the skill script, not the bin verb" \
  "$(grep -oE '(python3:)?zzfx[-a-z]* - .*' <<<"$out" | tr '\n' ' ')" "python3:zzfxmod - fx.test.sh zzfx-f - fx.test.sh zzfx-g - fx-skill "

# The real manifest.
D="$BIN/DEPS.tsv"
is "DEPS.tsv rows: 4 tab fields (+ optional '>= N'), level required|advisory|test|optional:media|optional:gamedev" \
  "$(grep -v '^#' "$D" | awk -F'\t' 'NF < 4 || NF > 5 || NF == 5 && $5 !~ /^>= [0-9]+$/ || $4 !~ /^(required|advisory|test|optional:(media|gamedev))$/' | head -3)" ""
is "DEPS.tsv names the test tools and the media + gamedev stack" "$(for t in python3:pytest bwrap gcc ffmpeg blender godot \
  wine weston npx manim gltfpack renderdoccmd vulkaninfo; do cut -f1 "$D" | grep -qx "$t" || printf '%s ' "$t"; done)" ""
is "DEPS.tsv tools unique" "$(grep -v '^#' "$D" | cut -f1 | sort | uniq -d | tr '\n' ' ')" ""
SK="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
paths=("$BIN" "$BIN/tests" "$BIN/../dashboard/tests")
for f in "$BIN"/../hooks/*.test.py "$BIN"/../adapters/*/hooks/*.test.py "$SK"/motion-video/scripts "$SK"/gamedev/scripts; do
  [ -e "$f" ] && paths+=("$f"); done
out=$(python3 "$SCAN" "${paths[@]}" --deps "$D"); rc=$?
is "every external tool in bin/*, the tests and the media + gamedev skill scripts is in DEPS.tsv or a base package${out:+ ($(tr '\n' ';' <<<"$out"))}" "$rc" 0

# install.sh step 1 on a PATH without jq: grouped lines, one apt line, exit 1; never runs apt.
mkdir -p "$WORK/path" "$WORK/h/bin"
for t in python3 bash wc; do ln -s "$(command -v "$t")" "$WORK/path/$t"; done
cp "$D" "$WORK/h/bin/DEPS.tsv"
sed -n '/^## 1. Prerequisites/,/^## 2\./p' "$BIN/../install.sh" >"$WORK/step1.sh"
out=$(HARNESS_DIR="$WORK/h" PATH="$WORK/path" bash "$WORK/step1.sh" 2>&1); rc=$?
is "install.sh step 1 exits 1 without a required tool" "$rc" 1
is "install.sh names the missing required tools" "$(grep -o 'MISSING required ([0-9]*):.*' <<<"$out")" \
  "MISSING required (2): jq systemctl"
is "install.sh prints one apt line with their packages" \
  "$(grep -c '^  sudo apt install ' <<<"$out") $(grep '^  sudo apt install ' <<<"$out" | grep -wc 'jq')" "1 1"
grep -q '^  missing advisory ([0-9]*): ' <<<"$out" && ok "install.sh groups advisory tools" || nok "advisory group" "$out"

[ "$bad" = 0 ] && echo "PASS deps-manifest" || { echo "FAIL deps-manifest"; exit 1; }
