import { ManualClock as EngineClock, type CueSheet } from 'explainer-kit';

/** Narration types, clocks, the paused timeline and the cue binder are the engine's (explainer-kit). */
export { AudioClock, PerfClock, Timeline, CueBinder, layoutClips, type Clock, type CueSheet, type Clip, type Word } from 'explainer-kit';

/** Clock set from outside: frozen stills (`?t=`) and tests; stopped until started. */
export class ManualClock extends EngineClock { constructor(t = 0, on = false) { super(t, on); } }

/** Plays the narration clips at their offsets through one AudioContext (the clock's master). */
export class Narration {
  readonly ctx = new AudioContext({ latencyHint: 'interactive' });
  private buffers = new Map<string, AudioBuffer>();
  private live = new Set<AudioBufferSourceNode>();
  private cues: CueSheet; private base: string;
  constructor(cues: CueSheet, base: string) { this.cues = cues; this.base = base; }
  async load(): Promise<void> {
    const ext = new Audio().canPlayType('audio/ogg; codecs=opus') ? '.opus' : '.m4a';
    await Promise.all(Object.entries(this.cues.clips).map(async ([id, c]) => {
      const res = await fetch(this.base + c.src + ext);
      this.buffers.set(id, await this.ctx.decodeAudioData(await res.arrayBuffer()));
    }));
  }
  /** Schedule every clip that is not over yet, as if the axis were at `from`. */
  play(offsets: Record<string, number>, from: number): void {
    this.stop();
    const now = this.ctx.currentTime + 0.02;
    for (const [id, at] of Object.entries(offsets)) {
      const buf = this.buffers.get(id); if (!buf || from >= at + buf.duration) continue;
      const s = new AudioBufferSourceNode(this.ctx, { buffer: buf });
      s.connect(this.ctx.destination); this.live.add(s); s.onended = () => this.live.delete(s);
      s.start(now + Math.max(0, at - from), Math.max(0, from - at));
    }
  }
  stop(): void { this.live.forEach((s) => { s.onended = null; try { s.stop(); } catch { /* already stopped */ } }); this.live.clear(); }
}
