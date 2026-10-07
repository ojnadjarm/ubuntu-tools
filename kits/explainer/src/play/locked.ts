import type { Hand } from './hand';

/** A part the learner may try to move but cannot (a locked input): every try is reported, the value never changes. */
export class LockedHand implements Hand {
  enabled = false;
  grabbed = false;
  onDetent: (value: number) => void = () => undefined;
  /** A drag past the slop, or an arrow key while it is picked. */
  onTry: () => void = () => undefined;
  private v = 0;
  private area: (wx: number, wy: number) => boolean;
  constructor(area: (wx: number, wy: number) => boolean) { this.area = area; }
  hits(wx: number, wy: number): boolean { return this.area(wx, wy); }
  down(): void { this.grabbed = true; this.onTry(); }
  move(): void {}
  up(): void { this.grabbed = false; }
  turn(): void { this.onTry(); }
  snap(v: number): number { return v; }
  value(): number { return this.v; }
  settled(): boolean { return !this.grabbed; }
  place(v: number): void { this.v = v; }
  update(): number { return this.v; }
}
