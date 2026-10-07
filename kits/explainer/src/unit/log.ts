/** One learner action on a hand (Command): a value change, a try on a locked part, or a press-in. */
export interface Command { hand: number; from: number; to: number; t: number; kind: 'move' | 'try' | 'commit' }

/** The history of one case: every move and try since it was posed, and the hands' values it started from. */
export class CommandLog {
  readonly list: Command[] = [];
  private start: number[] = [];
  private t0 = 0;
  /** Forget the history; `start` are the hands' values now. */
  clear(start: number[] = [], t = 0): void { this.list.length = 0; this.start = [...start]; this.t0 = t; }
  push(c: Command): void { this.list.push(c); }
  /** The last value logged for hand `i` (its start value before any move). */
  value(i: number): number {
    for (let k = this.list.length - 1; k >= 0; k--) { const c = this.list[k]; if (c.hand === i && c.kind === 'move') return c.to; }
    return this.start[i] ?? NaN;
  }
  moves(hand?: number): Command[] { return this.list.filter((c) => c.kind === 'move' && (hand === undefined || c.hand === hand)); }
  tries(hand?: number): Command[] { return this.list.filter((c) => c.kind === 'try' && (hand === undefined || c.hand === hand)); }
  /**
   * The settings the learner rested on: the hands' values after each run of moves that no move follows within `gap` seconds
   * (the last run counts once `now` is `gap` past it). The start is not a rest.
   */
  rests(gap: number, now: number): number[][] {
    const vals = [...this.start], out: number[][] = [], moves = this.moves();
    moves.forEach((c, k) => {
      vals[c.hand] = c.to;
      const next = moves[k + 1]?.t ?? now;
      if (next - c.t >= gap) out.push([...vals]);
    });
    return out;
  }
  /** Seconds since the case was posed, at `now`. */
  age(now: number): number { return now - this.t0; }
}
