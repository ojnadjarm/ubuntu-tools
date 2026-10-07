import type { UnitBundle } from '../content/types';

export type Earcon = 'detent' | 'lever' | 'engrave';
export type Bus = 'voice' | 'sfx';

/** What the director needs from a voice: schedule the watch clips, play one line or one sentence, stop, earcons, volumes. */
export interface Voice {
  readonly ctx: AudioContext | null;
  playWatch(offsets: Record<string, number>, from: number): void;
  line(id: string): Promise<void>;
  /** Play seconds `s`…`e` of clip `id` in place (one sentence). */
  segment(id: string, s: number, e: number): Promise<void>;
  stop(): void;
  speaking(): boolean;
  fx(kind: Earcon, gain?: number): void;
  /** Bus volume 0–1 (the effects bus sits 10 dB under the voice at 1). */
  volume(bus: Bus, v: number): void;
}

const FX = 0.32;

/** Web Audio voice: one context, a voice bus and an effects bus 10 dB under it. */
export class VoicePlayer implements Voice {
  readonly ctx: AudioContext;
  private voiceBus: GainNode; private fxBus: GainNode;
  private buffers = new Map<string, AudioBuffer>();
  private pending = new Map<string, Promise<void>>();
  private live = new Set<AudioBufferSourceNode>();
  private axis: { offsets: Record<string, number>; from: number; t0: number } | null = null;
  private lastFx = 0;
  /** Bumped by every stop and every new line: a start still waiting on its decode plays only while its generation is current. */
  private gen = 0;
  private bundle: UnitBundle;
  constructor(bundle: UnitBundle) {
    this.bundle = bundle;
    this.ctx = new AudioContext({ latencyHint: 'interactive' });
    this.voiceBus = new GainNode(this.ctx, { gain: 1 }); this.voiceBus.connect(this.ctx.destination);
    this.fxBus = new GainNode(this.ctx, { gain: FX }); this.fxBus.connect(this.ctx.destination);
  }
  /** Decode clips (Opus where the browser plays it, AAC otherwise); each clip is fetched once, and a watch clip joins the playing axis on arrival. */
  load(ids: string[] = Object.keys(this.bundle.cues.clips)): Promise<void> {
    return Promise.all(ids.map((id) => this.pending.get(id) ?? this.fetch(id))).then(() => undefined);
  }
  private fetch(id: string): Promise<void> {
    const ext = new Audio().canPlayType('audio/ogg; codecs=opus') ? '.opus' : '.m4a';
    const p = fetch(this.bundle.base + this.bundle.cues.clips[id].src + ext).then((r) => r.arrayBuffer()).then((b) => this.ctx.decodeAudioData(b))
      .then((buf) => { this.buffers.set(id, buf); this.join(id); });
    p.catch(() => this.pending.delete(id));
    this.pending.set(id, p);
    return p;
  }
  /** Load clips in the background in this order, `n` at a time; a failed clip is retried the next time it is needed. */
  async prefetch(ids: string[], n = 3): Promise<void> {
    const queue = ids.filter((id) => !this.pending.has(id));
    const worker = async (): Promise<void> => { for (let id = queue.shift(); id; id = queue.shift()) await this.load([id]).catch(() => undefined); };
    await Promise.all(Array.from({ length: n }, worker));
  }
  private join(id: string): void {
    const a = this.axis; if (!a || a.offsets[id] === undefined) return;
    const now = this.ctx.currentTime + 0.02;
    this.cue(id, a.offsets[id], a.from + now - a.t0, now);
  }
  private cue(id: string, at: number, from: number, now: number): void {
    const buf = this.buffers.get(id); if (!buf || from >= at + buf.duration) return;
    this.src(id, now + Math.max(0, at - from), Math.max(0, from - at));
  }
  private src(id: string, at = 0, off = 0, len?: number): AudioBufferSourceNode {
    const s = new AudioBufferSourceNode(this.ctx, { buffer: this.buffers.get(id)! });
    s.connect(this.voiceBus); this.live.add(s); s.onended = () => this.live.delete(s);
    if (len === undefined) s.start(at, off); else s.start(at, off, len);
    return s;
  }
  /** Schedule every loaded clip that is not over yet, as if the axis were at `from`; clips still loading join when they arrive. */
  playWatch(offsets: Record<string, number>, from: number): void {
    this.stop();
    const now = this.ctx.currentTime + 0.02;
    this.axis = { offsets, from, t0: now };
    for (const [id, at] of Object.entries(offsets)) this.cue(id, at, from, now);
  }
  /** One voice at a time: a new line stops whatever is playing, and it starts only if nothing newer came while its clip decoded. */
  line(id: string): Promise<void> { return this.play(id); }
  segment(id: string, s: number, e: number): Promise<void> { return this.play(id, Math.max(0, s), Math.max(0.05, e - s)); }
  private play(id: string, off = 0, len?: number): Promise<void> {
    this.stop();
    const gen = this.gen;
    return this.load([id]).then(() => new Promise<void>((res) => {
      if (gen !== this.gen) { res(); return; }
      this.src(id, 0, off, len).addEventListener('ended', () => res());
    }));
  }
  stop(): void {
    this.gen++; this.axis = null;
    this.live.forEach((s) => { s.onended = null; try { s.stop(); } catch { /* already stopped */ } });
    this.live.clear();
  }
  speaking(): boolean { return this.live.size > 0; }
  volume(bus: Bus, v: number): void {
    const g = bus === 'voice' ? this.voiceBus : this.fxBus;
    g.gain.setTargetAtTime(Math.max(0, Math.min(1, v)) * (bus === 'voice' ? 1 : FX), this.ctx.currentTime, 0.02);
  }
  /** Soft synthesized earcons: no transients (30 ms attack), low level, at most one per 35 ms. */
  fx(kind: Earcon, gain = 1): void {
    const t = this.ctx.currentTime;
    if (t - this.lastFx < 0.035) return;
    this.lastFx = t;
    const o = new OscillatorNode(this.ctx, { type: 'sine', frequency: kind === 'detent' ? 190 : kind === 'lever' ? 110 : 520 });
    const o2 = new OscillatorNode(this.ctx, { type: 'sine', frequency: kind === 'detent' ? 570 : kind === 'lever' ? 165 : 1040 });
    const g = new GainNode(this.ctx, { gain: 0 }); const g2 = new GainNode(this.ctx, { gain: 0.25 });
    const len = kind === 'engrave' ? 0.34 : kind === 'lever' ? 0.3 : 0.12;
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(0.5 * gain, t + 0.03); g.gain.exponentialRampToValueAtTime(0.0001, t + len);
    o.connect(g); o2.connect(g2).connect(g); g.connect(this.fxBus);
    o.start(t); o2.start(t); o.stop(t + len + 0.02); o2.stop(t + len + 0.02);
  }
}

/** Null Object for muted runs, frozen frames and tests: records what would play. */
export class NullVoice implements Voice {
  readonly ctx = null;
  log: { id: string; at: number; from: number; to?: number }[] = [];
  volumes: Record<Bus, number> = { voice: 1, sfx: 1 };
  playWatch(offsets: Record<string, number>, from: number): void { for (const [id, at] of Object.entries(offsets)) this.log.push({ id, at, from }); }
  line(id: string): Promise<void> { this.log.push({ id, at: -1, from: 0 }); return Promise.resolve(); }
  segment(id: string, s: number, e: number): Promise<void> { this.log.push({ id, at: -2, from: s, to: e }); return Promise.resolve(); }
  stop(): void {}
  speaking(): boolean { return false; }
  fx(): void {}
  volume(bus: Bus, v: number): void { this.volumes[bus] = v; }
}
