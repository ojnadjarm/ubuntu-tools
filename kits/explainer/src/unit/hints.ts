/** The rungs of a hint, in order: point at the parts, say the rule, work the case. */
export type Rung = 'look' | 'narrow' | 'show';
const RUNGS: Rung[] = ['look', 'narrow', 'show'];

/** Hints on request only: Look, then Narrow, then Show me (which works the case and offers a new one); a new case starts over. */
export class HintLadder {
  private i = 0;
  private has: Set<Rung>;
  constructor(has: Rung[] = RUNGS) { this.has = new Set(has); }
  /** The rungs this case offers. */
  offer(has: Rung[]): void { this.has = new Set(has); this.i = 0; this.skip(); }
  reset(): void { this.i = 0; this.skip(); }
  private skip(): void { while (this.i < RUNGS.length && !this.has.has(RUNGS[this.i])) this.i++; }
  /** The rung the next request gives, or null when none is left. */
  peek(): Rung | null { return RUNGS[this.i] ?? null; }
  /** Label of the hint button now: the first rung a case offers reads Hint, a later one Another hint, the last Show me. */
  label(): string { const r = this.peek(); return !r ? '' : r === 'show' ? 'Show me' : this.used() ? 'Another hint' : 'Hint'; }
  /** Take the next rung. */
  next(): Rung | null { const r = this.peek(); if (r) { this.i++; this.skip(); } return r; }
  /** Any rung was taken on this case. */
  used(): boolean { return this.i > RUNGS.findIndex((r) => this.has.has(r)); }
}
