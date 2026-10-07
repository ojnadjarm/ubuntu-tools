import type { CueSheet, UnitBundle, UnitSpec } from './types';

/** Load `cues.json` (and `unit.json` unless the spec is passed) from the bundle folder next to the page. */
export async function loadBundle(base: string, spec?: UnitSpec): Promise<UnitBundle> {
  const [cues, s] = await Promise.all([
    fetch(base + 'cues.json').then((r) => r.json() as Promise<CueSheet>),
    spec ? Promise.resolve(spec) : fetch(base + 'unit.json').then((r) => r.json() as Promise<UnitSpec>),
  ]);
  return { spec: s, cues, base };
}
