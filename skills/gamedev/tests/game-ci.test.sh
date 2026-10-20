#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031,SC2034  # ok() evals its single-quoted checks
# game-ci stages (.stages.<name> status/seconds, perf skip, GUT fail, T539 p99 gate) and asset-pipeline --budget (T543) on stub binaries.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
STUBS=$here/tests/fixtures/stub-bin
T=$(mktemp -d "${TMPDIR:-/tmp}/game-ci-test.XXXX"); trap 'pkill -f "$T/run" 2>/dev/null; rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
mkdir -p "$T/run" "$T/tmp" "$T/gpu-idle/a" "$T/gpu-idle/b"
export PERFGATE_GT="" PATH="$STUBS:$PATH" XDG_RUNTIME_DIR=$T/run TMPDIR=$T/tmp STUB_CALLS=$T/calls.log GLTFPACK=$STUBS/gltfpack QUIET_FDINFO=$T/gpu-idle
pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }

ok "selftest: every external binary resolves to a stub" \
	'for b in godot weston wine wineserver ffmpeg ffprobe glslang spirv-val spirv-cross wait-for blender; do [ "$(command -v $b)" = "$STUBS/$b" ] || exit 1; done'

P=$T/proj
mkdir -p "$P/addons/gut" "$P/shaders"
printf 'config_version=5\n[application]\nconfig/name="stub"\n' >"$P/project.godot"
printf '[preset.0]\nname="Linux"\nexport_path="build/game.x86_64"\n[preset.1]\nname="Windows"\nexport_path="build/game.exe"\n' >"$P/export_presets.cfg"
echo 'void main() {}' >"$P/shaders/ok.frag"

ci() { "$here/scripts/game-ci" --max-load 999 --capture-seconds 1 --perf-runs 1 "$@" "$P" >"$T/out" 2>&1; echo $? >"$T/rc"; }
rc() { cat "$T/rc"; }
st() { jq -r "[.stages[] | .status] | join(\" \")" "$1/summary.json"; }

ci --perf-max-load 999 --out "$T/ci1"
S=$T/ci1/summary.json
ok "all pass: rc 0, ok true" '[ "$(rc)" = 0 ] && jq -e ".ok == true" "$S" >/dev/null'
ok "stages in order, all pass" '[ "$(jq -r ".stages | keys_unsorted | join(\" \")" "$S")" = "import test shader perf export capture wine" ] && [ "$(st "$T/ci1")" = "pass pass pass pass pass pass pass" ]'
ok "every stage has status string + integer seconds" 'jq -e "[.stages[] | (.status | type == \"string\") and (.seconds | type == \"number\")] | all" "$S" >/dev/null'
ok "top-level keys pinned" 'jq -e "has(\"project\") and has(\"date\") and has(\"godot\") and has(\"load\") and has(\"seconds\") and has(\"ok\")" "$S" >/dev/null'
ok "stages.perf: baseline set, median_fps 120" 'jq -e ".stages.perf.rc == 0 and .stages.perf.median_fps == 120 and (.stages.perf.line | startswith(\"PERFGATE baseline set\"))" "$S" >/dev/null'
ok "T539: perf.csv ends p50,p95,p99,low1 with the stub values" 'head -1 "$T/ci1/perf.csv" | grep -q ",p50_ms,p95_ms,p99_ms,low1_fps,gpu_mhz_p50,throttle_pct,verdict$" && tail -1 "$T/ci1/perf.csv" | grep -q ",8.00,9.00,10.00,100.0,,,PASS$"'
ok "test: 3 tests, 0 failures" 'jq -e ".stages.test.tests == 3 and .stages.test.failures == 0" "$S" >/dev/null'
ok "export: Linux + Windows builds with bytes" 'jq -e "[.stages.export.builds.Linux.bytes, .stages.export.builds.Windows.bytes] | all(. > 0)" "$S" >/dev/null'
ok "capture: mp4 10 s, game line, shader gdshader_errors 0" 'jq -e ".stages.capture.duration_s == 10 and (.stages.capture.game | startswith(\"SMOKE done\")) and .stages.shader.gdshader_errors == 0 and .stages.shader.glsl_files == 1" "$S" >/dev/null'
ok "wine: stub version, game line" 'jq -e ".stages.wine.wine == \"wine-stub\" and .stages.wine.game == \"SMOKE done frames=90\"" "$S" >/dev/null'
ok "selftest: stubs were the ones called" 'for b in godot weston wine ffmpeg glslang; do grep -q "^$b " "$STUB_CALLS" || exit 1; done'

STUB_P99=40.00 ci --perf-max-load 999 --out "$T/ci1"
ok "T539: p99 x4 vs baseline -> stages.perf fail, rc 1" '[ "$(rc)" = 1 ] && jq -e ".stages.perf.status == \"fail\" and .stages.perf.rc == 1 and (.stages.perf.line | test(\"p99_ms=40.00 > ceil=\"))" "$S" >/dev/null'

: >"$STUB_CALLS"
ci --perf-max-load 0 --out "$T/ci2"
S=$T/ci2/summary.json
ok "--perf-max-load 0: stages.perf skip rc 3 in <= 1 s, rc 0" '[ "$(rc)" = 0 ] && jq -e ".stages.perf.status == \"skip\" and .stages.perf.rc == 3 and .stages.perf.seconds <= 1" "$S" >/dev/null'
ok "perf skip starts no game: one weston (capture), no smoke export" '[ "$(grep -c "^weston " "$STUB_CALLS")" = 1 ] && ! grep -q "export-release Linux build/" "$STUB_CALLS"'

STUB_GUT_FAIL=1 ci --perf-max-load 0 --no-wine --out "$T/ci3"
S=$T/ci3/summary.json
ok "failing GUT: rc 1, stages.test fail with 1 failure" '[ "$(rc)" = 1 ] && jq -e ".ok == false and .stages.test.status == \"fail\" and .stages.test.failures == 1" "$S" >/dev/null'
ok "failing GUT: later stages still reported" '[ "$(st "$T/ci3")" = "pass fail pass skip pass pass skip" ]'
L=$CREATIVE_CI_LOG
ok "T635: ci_finish logs one ledger line per run (4), each <= 400 B" '[ "$(wc -l <"$L")" = 4 ] && ! awk "length > 400" "$L" | grep -q .'
ok "T635: red GUT run -> {tool game-ci, project proj, ok false, failed [test], summary}" \
	'jq -e "select(.failed == [\"test\"]) | .tool == \"game-ci\" and .project == \"proj\" and .ok == false and (.ts | length > 18)" "$L" >/dev/null'
C=$(jq -r 'select(.failed == ["test"]) | .summary' "$L"); rm -f "$T/ci3/summary.json"
ok "T684: summary deleted after the run -> ledger copy under creative-ci/<date>/ still readable" \
	'[[ $C == "$T/creative-ci/$(date +%F)/"*-game-ci-proj.json ]] && jq -e ".stages.test.status == \"fail\"" "$C" >/dev/null'
ok "T684: > 16 KB keeps stages only; copies > 30 days pruned on write" '(
	. "$here/scripts/ci-lib.sh"; K=$T/creative-ci/2000-01-01; mkdir -p "$K"; touch -d "40 days ago" "$K/old.json"
	jq -n "{stages: {a: {status: \"fail\"}}, big: (\"x\" * 20000)}" >"$T/big.json"
	ci_log game-ci big false "[\"a\"]" "$T/big.json"; c=$(tail -1 "$L" | jq -r .summary)
	[ ! -e "$K" ] && [ "$(jq -c . "$c")" = "{\"stages\":{\"a\":{\"status\":\"fail\"}}}" ])'
export CI_SCRATCH_ROOTS=$T/tmp
lg() { (unset CREATIVE_CI_LOG; export HOME=$T/home HARNESS_HOME=$T/home/agents; . "$here/scripts/ci-lib.sh"; mkdir -p "$1"; echo '{"stages": {}}' >"$1/summary.json"; ci_log game-ci "$1" false '["test"]' "$1/summary.json"); }
M=$T/home/agents/log/creative-ci.jsonl SC=$T/home/agents/log/creative-ci-scratch.jsonl
lg "$TMPDIR/game"
ok "T722: tmp project -> creative-ci-scratch.jsonl, copy under creative-ci/scratch/, main ledger untouched" \
	'[ ! -e "$M" ] && [ "$(wc -l <"$SC")" = 1 ] && [[ $(jq -r .summary "$SC") == "$T/home/agents/log/creative-ci/scratch/$(date +%F)/"*-game-ci-game.json ]]'
lg "$T/home/agent-work/game"
ok "T722: fixture-HOME agent-work project -> main ledger" '[ "$(wc -l <"$M")" = 1 ] && [ "$(wc -l <"$SC")" = 1 ] && jq -e ".project == \"game\"" "$M" >/dev/null'
(export HOME=$T/home HARNESS_HOME=$T/home/agents; unset CREATIVE_CI_LOG; . "$here/scripts/ci-lib.sh"
	b=$T/home/claude-1000/-x/u/scratchpad/T1/out; mkdir -p "$b"; echo '{}' >"$b/build.json"; ci_log mv-build demo true '[]' "$b/build.json")
ok "T722: mv_finish-style name + build.json in a Claude scratchpad -> scratch ledger" '[ "$(wc -l <"$SC")" = 2 ] && [ "$(wc -l <"$M")" = 1 ] && tail -1 "$SC" | jq -e ".project == \"demo\"" >/dev/null'
(export HOME=$T/home HARNESS_HOME=$T/home/agents; . "$here/scripts/ci-lib.sh"; mkdir -p "$TMPDIR/g2"; echo '{}' >"$TMPDIR/g2/summary.json"; ci_log game-ci "$TMPDIR/g2" true '[]' "$TMPDIR/g2/summary.json")
ok "T722: explicit CREATIVE_CI_LOG wins for a tmp project" '[ "$(tail -1 "$L" | jq -r .project)" = g2 ] && [ "$(wc -l <"$SC")" = 2 ]'
K=$T/home/agents/log/creative-ci/scratch/2000-01-01; mkdir -p "$K"; touch -d "8 days ago" "$K/old.json"; touch -d "8 days ago" "$T/home/agents/log/creative-ci/keep.json"
lg "$TMPDIR/game"
ok "T722: scratch copies > 7 days pruned, main copies kept" '[ ! -e "$K" ] && [ -e "$T/home/agents/log/creative-ci/keep.json" ]'
(unset CREATIVE_CI_LOG; export HARNESS_HOME=$T/tmp/h; . "$here/scripts/ci-lib.sh"; ci_log mv-build sbx true '[]' "$T/tmp/none.json")
ok "T722: ledger itself in scratch (HARNESS_HOME sandbox) -> its main ledger" '[ -s "$T/tmp/h/log/creative-ci.jsonl" ] && [ ! -e "$T/tmp/h/log/creative-ci-scratch.jsonl" ]'
LT=$T/long; while [ ${#LT} -lt 200 ]; do LT=$LT/deep-tmpdir-segment; done; mkdir -p "$LT"
(export CREATIVE_CI_LOG=$LT/creative-ci.jsonl; . "$here/scripts/ci-lib.sh"; echo '{"stages": {}}' >"$LT/summary.json"
	ci_log game-ci big false "$(jq -nc '[range(5) | "stage-name-\(.)-" + ("x" * 40)]')" "$LT/summary.json")
R=$(tail -1 "$LT/creative-ci.jsonl")
ok "T742: long ledger path keeps a readable summary; row <= 400 B by trimming failed names" \
	'jq -e "has(\"summary\")" <<<"$R" >/dev/null && jq -e .stages "$(jq -r .summary <<<"$R")" >/dev/null && [ ${#R} -le 400 ] && [ "$(jq ".failed | length" <<<"$R")" -lt 5 ]'
ok "T635: p99 red -> failed [perf]; green -> failed []" '[ "$(jq -c ".failed" "$L" | head -3 | paste -sd" ")" = "[] [\"perf\"] []" ]'

for snap in a:0 b:400000000; do  # another client renders 40 % of 1 s
	d=$T/gpu-busy/${snap%:*}/4242; mkdir -p "$d/fdinfo"
	printf 'Name:\tblender\nPPid:\t1\nUid:\t%s\n' "$(id -u)" >"$d/status"
	printf 'drm-client-id:\t9\ndrm-engine-render:\t%s ns\n' "${snap#*:}" >"$d/fdinfo/3"
done
QUIET_FDINFO=$T/gpu-busy ci --perf-max-load 999 --perf-wait 1 --no-wine --out "$T/ci4"
ok "--perf-wait on a busy GPU: one ci_gate waiting line" '[ "$(grep -c "^GAMECI waiting: busy, gpu 40% > 15%$" "$T/out")" = 1 ]'
ok "game-ci and cpp-ci source ci-lib.sh, no own record()" '(for f in game-ci cpp-ci; do grep -q "^\. \"\$S/ci-lib.sh\"" "$here/scripts/$f" && ! grep -q "^record()" "$here/scripts/$f" || exit 1; done)'

if command -v "${KTX:-ktx}" >/dev/null; then
	A=$T/asset
	echo glb >"$T/demo.glb"
	budget() { echo "$1" >"$T/b.json"; "$here/scripts/asset-pipeline.sh" --glb "$T/demo.glb" --lods "1 0.5" --budget "$T/b.json" "$A" >"$T/out" 2>&1; echo $? >"$T/rc"; }
	budget '{"lod0": {"tris": 5000, "texture_px": 512}, "lod1": {"tris": 5000}}'
	ok "T543: budget fits -> rc 0, budget OK line" '[ "$(rc)" = 0 ] && grep -qx "ASSET budget OK $T/b.json" "$T/out"'
	STUB_TRIS=6000 budget '{"lod0": {"tris": 5000, "texture_px": 256}, "lod1": {"tris": 9000}}'
	ok "T543: over tris + texture -> rc 1, OVER lines for lod0 only" '[ "$(rc)" = 1 ] && grep -qx "ASSET OVER lod0 tris 6000 > 5000" "$T/out" && grep -qx "ASSET OVER lod0 texture_px 512 > 256" "$T/out" && ! grep -q "OVER lod1" "$T/out"'
else
	echo "SKIP needs ktx (KTX-Software, ~/opt/gamedev): T543 budget cases"
fi

echo "game-ci.test: $pass passed, $fail failed"
[ "$fail" = 0 ]
