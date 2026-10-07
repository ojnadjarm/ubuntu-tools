/** Render on demand: runs `tick` every frame while it reports a draw, then stops after 30 quiet frames (zero idle cost). */
export class OnDemand {
  private raf = 0;
  private idle = 0;
  private last = 0;
  private dirty = true;
  private tick: (dt: number, force: boolean) => boolean;
  /** Called with the milliseconds each drawn frame's `tick` took. */
  onFrame: (ms: number) => void = () => undefined;

  /** `tick(dt, force)` updates state and draws; it returns whether it drew. */
  constructor(tick: (dt: number, force: boolean) => boolean) { this.tick = tick; }

  /** Start (or keep) the loop; `redraw` makes the next tick's `force` true (resize, theme). */
  wake(redraw = false): void {
    if (redraw) this.dirty = true;
    this.idle = 0;
    if (this.raf) return;
    this.last = performance.now();
    const loop = (now: number): void => {
      const dt = Math.min(0.1, Math.max(0, (now - this.last) / 1000)); this.last = now;
      const t0 = performance.now(), force = this.dirty;
      this.dirty = false;
      const drew = this.tick(dt, force);
      if (drew) this.onFrame(performance.now() - t0);
      this.idle = drew ? 0 : this.idle + 1;
      this.raf = this.idle > 30 ? 0 : requestAnimationFrame(loop);
    };
    this.raf = requestAnimationFrame(loop);
  }
}

/** Snapshot key of a flat numeric state: draw only when it changes. */
export const stateKey = (s: object): string => Object.values(s).map((v) => (typeof v === 'number' ? v.toFixed(4) : '')).join();

/** `stateKey` for a state read every frame: values read by key (fast on large states), a value equal to the last call's keeps its text, and the key is joined again only when a text changed. */
export function stateKeyer(): (s: object) => string {
  const raw: unknown[] = [], txt: string[] = [];
  let key = '', stale = true;
  return (s) => {
    const ks = Object.keys(s), o = s as Record<string, unknown>;
    if (ks.length !== txt.length) { raw.length = txt.length = ks.length; stale = true; }
    for (let i = 0; i < ks.length; i++) {
      const x = o[ks[i]];
      if (x === raw[i] && txt[i] !== undefined) continue;
      raw[i] = x;
      const t = typeof x === 'number' ? x.toFixed(4) : '';
      if (t !== txt[i]) { txt[i] = t; stale = true; }
    }
    if (stale) { key = txt.join(); stale = false; }
    return key;
  };
}
