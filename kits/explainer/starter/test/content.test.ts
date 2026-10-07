import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { lintUnit, type CueSheet, type UnitSpec } from 'explainer-kit';

const read = <T>(path: string): T => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8')) as T;

test('the script passes the content lint against its cue sheet (no digits, glosses ≤ 12 words, no term before it is named)', () => {
  assert.deepEqual(lintUnit(read<UnitSpec>('../content/a02.unit.json'), read<CueSheet>('../public/bundles/a02/cues.json')), []);
});
