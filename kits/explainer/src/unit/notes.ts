import type { CueSheet, Term, UnitSpec } from '../content/types';
import { cueTime, type TermIndex } from './terms';

/** A callout as the player shows it: the term it explains, its title and line, the watch second it unlocks at (Infinity: a play line names it), and whether a sentence says it. */
interface Note { id: string; term: Term; title: string; what: string; at: number; said: boolean }

/** Callouts by id (a callout spec, else a term by its own id). */
export class Notes {
  private map = new Map<string, Note>();
  private terms: TermIndex; private cues: CueSheet; private offsets: Record<string, number>;
  constructor(spec: UnitSpec, terms: TermIndex, cues: CueSheet, offsets: Record<string, number>) {
    this.terms = terms; this.cues = cues; this.offsets = offsets;
    for (const t of terms.list) this.map.set(t.id, { id: t.id, term: t, title: t.word, what: t.gloss, at: terms.namedAt(t.id), said: true });
    for (const c of spec.callouts ?? []) {
      const term = terms.get(c.term);
      if (term) this.map.set(c.id, { id: c.id, term, title: c.title, what: c.what, at: this.when(c.cue, term.id), said: c.said !== false });
    }
  }
  get(id: string): Note | undefined { return this.map.get(id); }
  private when(cue: string | undefined, term: string): number { return cue ? cueTime(cue, this.cues, this.offsets) : this.terms.namedAt(term); }
}
