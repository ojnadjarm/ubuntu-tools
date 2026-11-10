#!/usr/bin/env bash
# T1591: test-changes on throwaway git repos: no change, new test files, pure additions, renames, changed test with/without a note, removed/weakened/skipped/deleted tests in 5 dialects, --ticket base, --scope, dir notes, non-repo.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
TC="$BIN/test-changes"
R="$WORK/repo"
[ "${R#"$WORK"}" != "$R" ] && ok 'sandbox: fixture repo is a temp dir' || { nok sandbox 'repo outside temp'; exit 1; }
g() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }

mkdir -p "$R/tests/behat" "$R/js" "$R/py" "$R/bin/tests"
cat >"$R/tests/calc_test.php" <<'EOF'
<?php
final class calc_test extends advanced_testcase {
    public function test_limit(): void {
        $this->assertEquals(3, calc::limit());
    }
    public function test_sum(): void {
        $this->assertSame(5, calc::sum(2, 3));
    }
}
EOF
printf 'Feature: limit\n  Scenario: see limit\n    Given I log in as "admin"\n    Then I should see "3 left"\n' >"$R/tests/behat/limit.feature"
printf "test('adds', () => {\n  expect(add(1, 2)).toBe(3);\n});\n" >"$R/js/add.test.js"
printf 'def test_add():\n    assert add(1, 2) == 3\n' >"$R/py/test_add.py"
printf '#!/usr/bin/env bash\n[ "$(x)" = 3 ] && ok "x is 3" || nok "x is 3" bad\n' >"$R/bin/tests/x.test.sh"
echo 'code' >"$R/calc.php"
g init -q && g add -A && g commit -qm 'T1: base' && g commit -q --allow-empty -m 'T2: unrelated'

out=$("$TC" --repo "$R"); is 'clean tree: exit 0' $? 0
ev 'clean tree: says no existing test changed' 'grep -q "no existing test changed" <<<"$out"'

echo 'more code' >>"$R/calc.php"
printf '<?php\nfinal class new_test extends advanced_testcase {\n    public function test_x(): void { $this->assertTrue(false); }\n}\n' >"$R/tests/new_test.php"
g add -A
out=$("$TC" --repo "$R"); is 'new test file + code: not a changed existing test, exit 0' $? 0
g commit -qm 'T3: new test'

sed -i 's/\$this->assertEquals(3, calc::limit());/$this->assertNotNull(calc::limit());/' "$R/tests/calc_test.php"
out=$("$TC" --repo "$R"); is 'changed test, no note: exit 1' $? 1
ev 'heading for the reviewer' 'grep -q "^NEEDS REVIEW: test changes" <<<"$out"'
ev 'weakened assertion detected' 'grep -q "weakened: \$this->assertEquals(3, calc::limit()); → \$this->assertNotNull(calc::limit());" <<<"$out"'
ev 'file marked NO NOTE' 'grep -q "^- tests/calc_test.php: NO NOTE" <<<"$out"'

printf '# Report\n## Test changes\n- tests/calc_test.php · test_limit · limit is now optional (REQ-2) · assertEquals(3, …) → assertNotNull(…)\n' >"$WORK/report.md"
out=$("$TC" --repo "$R" --note "$WORK/report.md"); is 'changed test with a note: exit 0' $? 0
ev 'note line printed for the reviewer' 'grep -q "note: - tests/calc_test.php · test_limit" <<<"$out"'
ev 'findings still listed when noted' 'grep -q "weakened:" <<<"$out"'
mkdir "$WORK/notes" && cp "$WORK/report.md" "$WORK/notes/"
TEST_CHANGES_NOTE="$WORK/notes" "$TC" --repo "$R" >/dev/null; is 'note from $TEST_CHANGES_NOTE dir: exit 0' $? 0
printf '## Test changes\n- tests/calc_test.php changed for REQ-2\n' >"$WORK/bad-note.md"
"$TC" --repo "$R" --note "$WORK/bad-note.md" >/dev/null; is 'note without before → after: exit 1' $? 1
printf '## Test changes\n- tests/other_test.php · t · r · a → b\n' >"$WORK/other.md"
"$TC" --repo "$R" --note "$WORK/other.md" >/dev/null; is 'note for another file: exit 1' $? 1
printf 'calc_test.php · test_limit · r · a → b\n' >"$WORK/no-head.md"
"$TC" --repo "$R" --note "$WORK/no-head.md" >/dev/null; is 'line outside a Test changes heading: exit 1' $? 1

g checkout -q -- tests/calc_test.php
printf 'def test_more():\n    assert add(2, 2) == 4\n' >>"$R/py/test_add.py"
"$TC" --repo "$R" >/dev/null; is 'pure addition to an existing test file: not a changed test, exit 0' $? 0
printf '    return\n' >>"$R/py/test_add.py"
out=$("$TC" --repo "$R"); is 'added early return only: counted, exit 1' $? 1
ev 'added early return reported as a skip' 'grep -q "added skip: return" <<<"$out"'
g checkout -q -- py/test_add.py
sed -i 's/test_add/test_add_numbers/' "$R/py/test_add.py"
out=$("$TC" --repo "$R"); ev 'renamed test reported, not deleted' 'grep -q "renamed test: test_add → test_add_numbers" <<<"$out" && ! grep -q "deleted test" <<<"$out"'
g checkout -q -- py/test_add.py
python3 - "$R/tests/calc_test.php" <<'EOF'
import sys; p = sys.argv[1]; s = open(p).read()
s = s.replace("""    public function test_sum(): void {
        $this->assertSame(5, calc::sum(2, 3));
    }
""", "").replace("$this->assertEquals(3, calc::limit());", "$this->markTestSkipped('later');")
open(p, 'w').write(s)
EOF
out=$("$TC" --repo "$R"); is 'skip + deleted test: exit 1' $? 1
ev 'php: added skip' 'grep -q "added skip: \$this->markTestSkipped" <<<"$out"'
ev 'php: deleted test function' 'grep -q "deleted test: test_sum" <<<"$out"'
ev 'php: removed assertion' 'grep -q "removed assertion: \$this->assertSame(5" <<<"$out"'

sed -i 's/    Then I should see "3 left"//' "$R/tests/behat/limit.feature"
sed -i 's/test(/test.skip(/' "$R/js/add.test.js"
sed -i 's/    assert add(1, 2) == 3/    assert add(1, 2)/' "$R/py/test_add.py"
sed -i '2d' "$R/bin/tests/x.test.sh"
out=$("$TC" --repo "$R"); is '5 dialects changed: exit 1' $? 1
ev 'behat: removed Then step' 'grep -q "removed assertion: Then I should see \"3 left\"" <<<"$out"'
ev 'js: added .skip' 'grep -q "added skip: test.skip(" <<<"$out"'
ev 'pytest: weakened == to truthy' 'grep -q "weakened: assert add(1, 2) == 3 → assert add(1, 2)" <<<"$out"'
ev 'shell: removed ok/nok check and its test' 'grep -q "removed assertion: \[ \"\$(x)\" = 3 \]" <<<"$out" && grep -q "deleted test: \"x is 3\"" <<<"$out"'
ev 'all 5 files listed' '[ "$(grep -c "^- " <<<"$out")" = 5 ]'
out=$("$TC" --repo "$R" --scope js); is '--scope: only js/' "$(grep -c '^- ' <<<"$out")" 1

g checkout -q -- .
g rm -q py/test_add.py && g commit -qm 'T4: drop the add test'
out=$("$TC" --repo "$R" --ticket T4); is '--ticket: committed deletion found, exit 1' $? 1
ev '--ticket: deleted file shown' 'grep -q "^- py/test_add.py: deleted file; NO NOTE" <<<"$out"'
ev '--ticket: base is the parent of the first T4 commit' 'grep -q "base $(g rev-parse --short HEAD~1)" <<<"$out"'
sed -i 's/toBe(3)/toBeTruthy()/' "$R/js/add.test.js"
out=$("$TC" --repo "$R" --ticket T4 --committed-only); is '--committed-only: dirty js ignored' "$(grep -c '^- ' <<<"$out")" 1
out=$("$TC" --repo "$R" --ticket T4 --scope py); is '--ticket --scope py: dirty js out of scope' "$(grep -c '^- ' <<<"$out")" 1
out=$("$TC" --repo "$R" --ticket T4); is '--ticket: dirty js in' "$(grep -c '^- ' <<<"$out")" 2
"$TC" --repo "$R" --ticket T3 >/dev/null; is '--ticket T3 (new file only, js dirty): exit 1 for js' $? 1
"$TC" --repo "$R" --ticket T3 --committed-only >/dev/null; is '--ticket T3 committed only: no existing test changed' $? 0

mkdir "$WORK/plain"
"$TC" --repo "$WORK/plain" 2>/dev/null; is 'not a git repo: exit 2' $? 2
exit $bad
