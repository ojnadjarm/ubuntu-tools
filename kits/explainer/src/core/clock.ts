/** Seconds on the narration axis; every animated thing reads one of these, never wall time. */
export interface Clock { now(): number; playing(): boolean; start(from: number): void; stop(): void }

/** Audio-driven clock: the context's output time minus latency is the master. */
export class AudioClock implements Clock {
  private startAt = 0; private from = 0; private on = false;
  private ctx: AudioContext;
  constructor(ctx: AudioContext) { this.ctx = ctx; }
  private out(): number { return this.ctx.currentTime - (this.ctx.outputLatency || 0); }
  start(from: number): void { this.from = from; this.startAt = this.out(); this.on = true; }
  stop(): void { this.from = this.now(); this.on = false; }
  now(): number { return this.on ? this.from + Math.max(0, this.out() - this.startAt) : this.from; }
  playing(): boolean { return this.on; }
}

/** Clock set from outside: frozen stills (`?t=`), the recorder and tests. */
export class ManualClock implements Clock {
  t: number; private on: boolean;
  constructor(t = 0, on = true) { this.t = t; this.on = on; }
  set(t: number): void { this.t = t; }
  start(from: number): void { this.t = from; this.on = true; }
  stop(): void { this.on = false; }
  now(): number { return this.t; }
  playing(): boolean { return this.on; }
}

/** Wall-clock stand-in when there is no audio (muted runs, fps bench). */
export class PerfClock implements Clock {
  private t0 = 0; private from = 0; private on = false;
  start(from: number): void { this.from = from; this.t0 = performance.now(); this.on = true; }
  stop(): void { this.from = this.now(); this.on = false; }
  now(): number { return this.on ? this.from + (performance.now() - this.t0) / 1000 : this.from; }
  playing(): boolean { return this.on; }
}
