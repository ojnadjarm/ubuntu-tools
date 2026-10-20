#!/usr/bin/env bash
# Tests analyze-sound.mjs, moodle-docs sync.sh, find-polluter.sh and ctxrot on fixtures: synthetic WAVs, a local bare git repo, stub npm/python3.
set -uo pipefail
B="$HOME/agents/bin"
FX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/untested-tools"
ANALYZE="$HOME/agents/skills/ui-sound-design/tools/analyze-sound.mjs"
SYNC="$HOME/.claude/skills/moodle-docs/sync.sh"
POLLUTER="$HOME/.claude/skills/systematic-debugging/find-polluter.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
has() { case "$3" in *"$2"*) ok "$1";; *) nok "$1" "no '$2' in: ${3:0:300}";; esac; }

# analyze-sound.mjs: 3 synthetic 44.1 kHz mono WAVs, JSON keys and values within tolerance.
mkdir "$WORK/wav"
python3 - "$WORK/wav" <<'EOF'
import math, random, struct, sys, wave
sr, out = 44100, sys.argv[1]
def write(name, samples):
    with wave.open(f"{out}/{name}.wav", "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
write("sine", [0.5 * math.sin(2 * math.pi * 440 * i / sr) for i in range(sr // 2)])
write("click", [0.0] * (sr // 10) + [0.9 * math.exp(-i / 40) * (1 - 2 * (i % 2)) for i in range(sr // 100)] + [0.0] * int(sr * 0.19))
random.seed(1)
write("noise", [0.0] * (sr // 20) + [random.uniform(-0.25, 0.25) for _ in range(sr // 5)] + [0.0] * (sr // 20))
EOF
for s in sine click noise; do
  node "$ANALYZE" "$WORK/wav/$s.wav" --json >"$WORK/wav/$s.json" 2>"$WORK/wav/$s.err"; eq "analyze-sound $s: rc 0" 0 $?
done
out=$(python3 - "$WORK/wav" <<'EOF'
import json, math, sys
d = {s: json.load(open(f"{sys.argv[1]}/{s}.json")) for s in ("sine", "click", "noise")}
keys = ["durationMs", "sampleRate", "envelope", "pitch", "spectrum", "harmonics", "tonality", "evolution",
        "filter", "classification", "vocabularyMatch", "synthesisSuggestion"]
db = lambda s: 20 * math.log10(d[s]["envelope"]["peakAmplitude"])
checks = {
    "keys": all(list(d[s]) == keys for s in d),
    "sine duration 500": d["sine"]["durationMs"] == 500,
    "sine rate 44100": d["sine"]["sampleRate"] == 44100,
    "sine pitch 440+-5": abs(d["sine"]["pitch"]["fundamentalHz"] - 440) <= 5,
    "sine peak -9 dBFS+-1": abs(db("sine") + 9.03) <= 1,
    "sine tonal": d["sine"]["tonality"]["classification"] == "tonal",
    "click duration 300": d["click"]["durationMs"] == 300,
    "click onset 100+-12 ms": abs(d["click"]["envelope"]["attackMs"] - 100) <= 12,
    "click decay < 30 ms": d["click"]["envelope"]["decayMs"] < 30,
    "click peak -12 dBFS+-2": abs(db("click") + 12.1) <= 2,
    "noise duration 300": d["noise"]["durationMs"] == 300,
    "noise onset in burst": 50 <= d["noise"]["envelope"]["attackMs"] <= 250,
    "noise peak -16.5 dBFS+-1.5": abs(db("noise") + 16.5) <= 1.5,
    "noise >= 80% noise": d["noise"]["tonality"]["noisePercent"] >= 80,
    "noise flat > 0.5": d["noise"]["tonality"]["spectralFlatness"] > 0.5,
}
for k, v in checks.items():
    print(("PASS " if v else "FAIL ") + "analyze-sound " + k)
EOF
)
echo "$out"; ! grep -q '^FAIL' <<<"$out" || bad=1
node "$ANALYZE" 2>/dev/null; eq "analyze-sound no arg: rc 1" 1 $?

# sync.sh: HOME is the sandbox, the devdocs URL is rewritten to a local bare repo and only file:// is allowed.
SB="$WORK/home"; mkdir -p "$SB"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$SB/.gitconfig"
git config --global user.name fixture; git config --global user.email fixture@example.invalid
git config --global init.defaultBranch main
git config --global protocol.file.allow always
git config --global url."file://$WORK/devdocs.git".insteadOf https://github.com/moodle/devdocs.git
git init -q --bare "$WORK/devdocs.git"
git clone -q "$WORK/devdocs.git" "$WORK/src" 2>/dev/null
cp -r "$FX/devdocs/." "$WORK/src/"
git -C "$WORK/src" add -A; git -C "$WORK/src" commit -qm one; git -C "$WORK/src" push -q origin HEAD:main
export GIT_ALLOW_PROTOCOL=file
HOME="$SB" git ls-remote https://github.com/elsewhere/x.git >/dev/null 2>&1; eq "selftest: non-file URLs refused" 128 $?
eq "selftest: devdocs URL resolves to the fixture" "$(git -C "$WORK/src" rev-parse HEAD)" \
  "$(HOME="$SB" git ls-remote https://github.com/moodle/devdocs.git main | cut -f1)"
[ "$bad" -eq 0 ] || { echo "FAIL sandbox selftest; sync.sh not run"; exit 1; }
out=$(HOME="$SB" bash "$SYNC" 2>&1); eq "sync first clone: rc 0" 0 $?
M="$SB/.moodle-devdocs"
eq "sync: mirror is shallow" true "$(git -C "$M" rev-parse --is-shallow-repository)"
eq "sync: sparse set skips static/" no "$([ -e "$M/static/skip.md" ] && echo yes || echo no)"
eq "sync: versioned_docs mirrored" yes "$([ -f "$M/versioned_docs/version-4.5/apis/old.md" ] && echo yes || echo no)"
has "sync: INDEX lists the front-matter title" "docs/apis/core/dml.md — Data manipulation API" "$(cat "$M/INDEX.md" 2>/dev/null)"
has "sync: page count per section" "version-4.5" "$out"
echo dirty >>"$M/docs/guides/plugins.md"; echo stray >"$M/docs/stray.md"
printf '# New page\n' >"$WORK/src/docs/guides/new.md"
git -C "$WORK/src" add -A; git -C "$WORK/src" commit -qm two; git -C "$WORK/src" push -q origin HEAD:main
HOME="$SB" bash "$SYNC" >/dev/null 2>&1; eq "sync update: rc 0" 0 $?
eq "sync update: new upstream commit" "$(git -C "$WORK/src" rev-parse HEAD)" "$(git -C "$M" rev-parse HEAD)"
eq "sync update: dirty tracked file reset, not refused" "# Plugin guide" "$(head -1 "$M/docs/guides/plugins.md")"
eq "sync update: dirty tail gone" 0 "$(grep -c dirty "$M/docs/guides/plugins.md")"
has "sync update: INDEX has the new page" "docs/guides/new.md" "$(cat "$M/INDEX.md")"
unset GIT_ALLOW_PROTOCOL GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL

# find-polluter.sh: 3 fixture tests via a stub npm; b leaves polluted.flag.
mkdir -p "$WORK/pol/stub" "$WORK/pol/proj"
cp -r "$FX/polluter" "$WORK/pol/proj/tests"
printf '#!/usr/bin/env bash\n[ "$1" = test ] && bash "$2"\n' >"$WORK/pol/stub/npm"; chmod +x "$WORK/pol/stub/npm"
out=$(cd "$WORK/pol/proj" && PATH="$WORK/pol/stub:$PATH" bash "$POLLUTER" polluted.flag 'tests/*.test.sh' 2>&1); eq "find-polluter found: rc 1" 1 $?
has "find-polluter: counts 3 tests" "Found 3 test files" "$out"
has "find-polluter: names b" "Test: ./tests/b.test.sh" "$out"
eq "find-polluter: stops before c" 0 "$(grep -c 'c.test.sh' <<<"$out")"
rm -f "$WORK/pol/proj/polluted.flag" "$WORK/pol/proj/tests/b.test.sh"
out=$(cd "$WORK/pol/proj" && PATH="$WORK/pol/stub:$PATH" bash "$POLLUTER" polluted.flag './tests/*.test.sh' 2>&1); eq "find-polluter clean: rc 0" 0 $?
has "find-polluter clean: says so" "No polluter found" "$out"
bash "$POLLUTER" only-one >/dev/null 2>&1; eq "find-polluter usage: rc 1" 1 $?

# ctxrot: real -h, then argument pass-through to a stub python3.
"$B/ctxrot" -h >/dev/null 2>&1; eq "ctxrot -h: rc 0" 0 $?
mkdir "$WORK/py"
printf '#!/usr/bin/env bash\nprintf "%%s|" "$@"; echo; echo "PP=$PYTHONPATH"\n' >"$WORK/py/python3"; chmod +x "$WORK/py/python3"
out=$(PATH="$WORK/py:$PATH" PYTHONPATH=/x "$B/ctxrot" run "/tmp/a b" --lengths 32k); eq "ctxrot stub: rc 0" 0 $?
eq "ctxrot: args passed as-is" "-m|ctxrot|run|/tmp/a b|--lengths|32k|" "$(head -1 <<<"$out")"
eq "ctxrot: skill dir first on PYTHONPATH" "PP=$HOME/.claude/skills/context-rot:/x" "$(tail -1 <<<"$out")"

exit $bad
