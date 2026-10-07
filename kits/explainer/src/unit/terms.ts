import type { CueSheet, Term, UnitSpec } from '../content/types';

/** Watch-axis second of a cue (`clip.mark`, or `mark` in any watch clip); Infinity when no watch clip carries it. */
export function cueTime(cue: string, cues: CueSheet, offsets: Record<string, number>): number {
  const dot = cue.indexOf('.'), clip = dot > 0 ? cue.slice(0, dot) : null, mark = dot > 0 ? cue.slice(dot + 1) : cue;
  const hit = Object.entries(offsets).find(([id]) => (!clip || id === clip) && cues.clips[id]?.marks[mark] !== undefined);
  return hit ? hit[1] + cues.clips[hit[0]].marks[mark] : Infinity;
}

/** Where each term is named: a second on the watch axis (a mark in a watch clip), or a play clip that names it when said. */
export class TermIndex {
  readonly list: Term[];
  private at = new Map<string, number>();
  private byClip = new Map<string, string[]>();
  constructor(spec: UnitSpec, cues: CueSheet, offsets: Record<string, number>) {
    this.list = spec.introduces ?? [];
    for (const t of this.list) {
      const at = cueTime(t.namedCue, cues, offsets);
      if (Number.isFinite(at)) { this.at.set(t.id, at); continue; }
      const dot = t.namedCue.indexOf('.'), said = dot > 0 ? t.namedCue.slice(0, dot) : t.namedCue;
      if (cues.clips[said]) this.byClip.set(said, [...(this.byClip.get(said) ?? []), t.id]);
    }
  }
  get(id: string): Term | undefined { return this.list.find((t) => t.id === id); }
  /** Watch-axis second the term is named at; Infinity when a play clip names it. */
  namedAt(id: string): number { return this.at.get(id) ?? Infinity; }
  /** Terms a play clip names when it is said. */
  namedBy(clip: string): string[] { return this.byClip.get(clip) ?? []; }
  /** The play clip that names a term, if any. */
  clipOf(id: string): string | undefined { return [...this.byClip].find(([, ids]) => ids.includes(id))?.[0]; }
}
