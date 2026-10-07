import type { CueSheet } from '../content/types';

/** Clip id → start second on one axis: clips play in order with `gap` seconds between, after `lead`. */
export function layoutClips(cues: CueSheet, order: string[], lead: number, gap: number): { offsets: Record<string, number>; end: number } {
  const offsets: Record<string, number> = {};
  let t = lead;
  for (const id of order) { offsets[id] = t; t += cues.clips[id].duration + gap; }
  return { offsets, end: t };
}

/** Cue names (`{mark}` in the script) and spoken words → seconds on the watch axis. */
export class CueBinder {
  private cues: CueSheet; private offsets: Record<string, number>;
  constructor(cues: CueSheet, offsets: Record<string, number>) { this.cues = cues; this.offsets = offsets; }
  at(clip: string, mark: string): number {
    const t = this.cues.clips[clip]?.marks[mark];
    if (t === undefined) throw new Error(`missing cue ${clip}.${mark}`);
    return this.offsets[clip] + t;
  }
  /** Start of the n-th spoken occurrence of a word (lower case, letters only). */
  word(clip: string, w: string, nth = 0): number {
    const hits = this.cues.clips[clip].words.filter((x) => x.w.toLowerCase().replace(/[^a-z]/g, '') === w);
    if (!hits[nth]) throw new Error(`missing word ${clip}.${w}#${nth}`);
    return this.offsets[clip] + hits[nth].s + this.cues.bias;
  }
  start(clip: string): number { return this.offsets[clip]; }
  end(clip: string): number { return this.offsets[clip] + this.cues.clips[clip].duration; }
}
