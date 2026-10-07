import type { Hand } from './hand';
import type { Projector } from './pointer';

/** Where a carried part can sit: its home in the tray, the seats in world units, and which seats it fits and which are taken. */
export interface Seats { home: [number, number]; at: [number, number][]; r: number; fits(i: number): boolean; taken(i: number): boolean }

/** A part carried from the tray to a seat: while held it snaps to the nearest seat it fits (or home), so its value is a seat index (−1 = the tray). */
export class SlotHand implements Hand {
  enabled = false;
  grabbed = false;
  onDetent: (value: number) => void = () => undefined;
  private v = -1; private said = -1;
  readonly seats: Seats; private proj: Projector;
  constructor(seats: Seats, proj: Projector) { this.seats = seats; this.proj = proj; }
  /** Where the part is drawn now. */
  at(): [number, number] { return this.v < 0 ? this.seats.home : this.seats.at[this.v]; }
  hits(wx: number, wy: number): boolean { const [x, y] = this.at(); return Math.hypot(wx - x, wy - y) <= this.seats.r; }
  down(): void { this.grabbed = true; }
  move(px: number, py: number): void {
    const [wx, wy] = this.proj.toWorld(px, py);
    const d = (p: [number, number]): number => Math.hypot(wx - p[0], wy - p[1]);
    this.v = this.open().reduce((best, i) => (d(this.seats.at[i]) < (best < 0 ? d(this.seats.home) : d(this.seats.at[best])) ? i : best), -1);
  }
  up(): void { this.grabbed = false; }
  /** Seats this part may take now: the ones it fits that are free, and its own. */
  open(): number[] { return this.seats.at.map((_, i) => i).filter((i) => i === this.v || (this.seats.fits(i) && !this.seats.taken(i))); }
  /** Keyboard path: through the tray and the open seats in order. */
  turn(n: number): void {
    const ring = [-1, ...this.open()], k = ring.indexOf(this.v);
    this.v = ring[(((k + n) % ring.length) + ring.length) % ring.length];
  }
  snap(v: number): number { return Math.round(v); }
  value(): number { return this.v; }
  settled(): boolean { return !this.grabbed; }
  place(v: number): void { this.v = this.said = this.snap(v); }
  update(): number {
    if (this.v !== this.said) { this.said = this.v; this.onDetent(this.v); }
    return this.v;
  }
}
