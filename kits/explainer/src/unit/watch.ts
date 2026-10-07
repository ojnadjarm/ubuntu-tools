import { spanAt } from '../captions';
import type { Beat, EnterOptions, LabelMode } from './beats';
import type { Director } from './director';

export interface WatchOptions<S> {
  /** Beat the call to action leads to. */
  next: string;
  cta?: string;
  label?: string;
  /** Timeline mark where the call to action appears (default `end`, else the timeline's end). */
  mark?: string;
  /** Goal the director eases toward once the watch is left. */
  exitGoal?(s: S): Partial<S>;
  /** Stop before each watch chapter after the first: the plate stays live and a call to action starts the next chapter. */
  stops?: boolean;
  /** Hands the learner may grab during the watch (default: all). */
  hands?: number[];
  /** Go on to `next` by itself when the narration plays to its end (a chooser after the explanation). */
  advance?: boolean;
}

const STOP_LEAD = 0.3;

/**
 * Watch: the narrated animation. State is a pure function of the clock. Grabbing a hand pauses with a snapshot (Memento);
 * a callout holds without one; every seek lands on a sentence start, back freely and forward up to the furthest second heard.
 */
export class WatchBeat<S extends object> implements Beat {
  readonly label: string;
  readonly pausable = true;
  readonly timed = true;
  private memento: S | null = null;
  private resumeAt: number | null = null;
  private held: number | null = null;
  private dragPlay: boolean | null = null;
  private shown: 'go' | 'resume' | 'next' | null = null;
  private span = -1;
  private last = 0;
  private d: Director<S>; private o: WatchOptions<S>;
  constructor(d: Director<S>, o: WatchOptions<S>) { this.d = d; this.o = o; this.label = o.label ?? 'Watch'; }
  enter(o: EnterOptions = {}): void {
    Object.assign(this.d.s, this.d.unit.initial());
    this.d.goal = {};
    this.d.hands.forEach((x, i) => { x.enabled = !this.o.hands || this.o.hands.includes(i); });
    this.memento = null; this.held = null; this.resumeAt = null; this.dragPlay = null; this.shown = null; this.span = -1;
    this.land(o.at === undefined ? 0 : this.start(Math.min(o.at, this.d.furthest)), true);
  }
  play(from: number): void {
    if (this.shown === 'next') { this.shown = null; this.d.shell.cta(null); }
    this.last = from;
    this.d.clock.start(from);
    this.d.voice.playWatch(this.d.offsets, from);
    this.d.shell.playing(true);
  }
  pause(): void { this.d.clock.stop(); this.d.voice.stop(); this.d.shell.playing(false); }
  /** Named while the explanation plays, up to its `end` mark; numbered from there (a seek back names them again). */
  labels(): LabelMode { return this.d.clock.now() < this.mark() ? 'named' : 'numbered'; }
  private mark(): number { return this.d.tl.marks()[this.o.mark ?? 'end'] ?? this.d.tl.duration(); }
  private start(t: number): number { const sp = this.d.spans; return sp.length ? sp[spanAt(sp, t)].s : t; }

  /** Land on the span start holding `t` (or `t` itself when `exact`), clamped to what was heard; plate and voice start there together. */
  seek(t: number, play = this.dragPlay ?? (this.d.clock.playing() || this.held !== null), exact = false): void {
    const d = this.d, from = d.clock.now();
    const c = Math.min(Math.max(0, t), Math.max(d.furthest, 0)), to = exact ? c : this.start(c);
    if (this.memento) Object.assign(d.s, this.memento);
    this.land(to, play);
    d.events.emit({ type: 'seek', from, to });
  }
  private land(to: number, play: boolean): void {
    const d = this.d;
    this.memento = null; this.held = null; this.resumeAt = null; this.dragPlay = null;
    this.frame(to);
    if (this.shown) { this.shown = null; d.shell.cta(null); }
    this.last = to;
    if (play) this.play(to); else { d.clock.start(to); d.clock.stop(); d.voice.stop(); d.shell.playing(false); }
    d.wake();
  }
  /** Silent drag: clock and voice stop, the plate and the caption follow `t`; the release is a `seek`. */
  scrub(t: number): void {
    const d = this.d;
    if (this.dragPlay === null) {
      this.dragPlay = d.clock.playing() || this.held !== null;
      if (this.memento) Object.assign(d.s, this.memento);
      this.memento = null; this.held = null; this.resumeAt = null;
      this.pause();
    }
    const to = Math.min(Math.max(0, t), d.furthest);
    this.frame(to); d.clock.start(to); d.clock.stop();
    d.wake();
  }
  /** Render the plate at `t` from the start, so every tween before it has run in order (GSAP records start values once). */
  private frame(t: number): void { this.d.tl.seek(0); this.d.tl.seek(t); this.d.placeHands(); }

  /** More than 1 s into a sentence restarts it; within the first second goes to the one before. */
  back(): void {
    const sp = this.d.spans; if (!sp.length) return;
    const t = this.d.clock.now(), i = spanAt(sp, t);
    this.seek(t - sp[i].s > 1 ? sp[i].s : sp[Math.max(0, i - 1)].s);
  }
  /** Next sentence, if it has been heard. */
  fwd(): void {
    const sp = this.d.spans, n = sp[spanAt(sp, this.d.clock.now()) + 1];
    if (n && n.s <= this.d.furthest + 1e-6) this.seek(n.s);
  }
  /** A callout opened: stop clock and voice, remember the sentence start (nothing to hold if already paused). */
  hold(): void { if (this.d.clock.playing() && !this.memento) { this.held = this.start(this.d.clock.now()); this.pause(); } }
  release(): void { if (this.held !== null) this.seek(this.held, true); }
  goals(): Record<string, number> | null {
    const d = this.d;
    return this.memento || this.dragPlay !== null || d.clock.playing() ? null : d.tl.goals(d.s, d.clock.now());
  }

  toggle(): void {
    const d = this.d, t = d.clock.now();
    if (this.memento) { this.resume(); return; }
    if (this.held !== null) { this.release(); return; }
    if (d.clock.playing()) { this.pause(); return; }
    if (t >= d.tl.duration() - 0.05) { const last = d.chapters().filter((c) => c.t !== undefined).at(-1); this.seek(last?.t ?? 0, true); return; }
    this.play(Math.min(t, d.tl.duration()));
  }
  touched(): void {
    if (this.memento) return;
    this.memento = { ...this.d.s };
    this.resumeAt = this.held; this.held = null;
    this.pause();
    this.shown = 'resume';
    this.d.shell.cta('Resume', () => this.resume());
  }
  /** Put the lesson's dials back and play on (from the held sentence start if a callout was holding). */
  resume(): void {
    const at = this.resumeAt;
    this.seek(at ?? this.d.clock.now(), true, at === null);
  }
  update(dt: number): void {
    const d = this.d, t = d.clock.now();
    if (this.memento) { d.readHands(dt); return; }
    if (this.dragPlay !== null) return;
    d.tl.seek(t);
    d.placeHands();
    if (d.clock.playing() && this.stop(t)) return;
    if (d.clock.playing()) {
      d.reach(t);
      const i = spanAt(d.spans, t);
      if (i !== this.span && d.spans.length) { this.span = i; d.events.emit({ type: 'span', index: i, t: d.spans[i].s }); }
    }
    const ret = d.beats.ret();
    if (!this.shown && (ret || t >= this.mark())) {
      this.shown = 'go';
      d.shell.cta(ret?.label ?? this.o.cta ?? 'Your turn', ret?.go ?? (() => { d.reach(d.tl.duration()); d.go(this.o.next); }));
    }
    if (t >= d.tl.duration() && d.clock.playing()) {
      d.clock.start(d.tl.duration()); d.clock.stop(); d.shell.playing(false); d.reach(d.tl.duration());
      if (this.o.advance && !ret) d.go(this.o.next);
    }
  }
  /** Playing across the lead-in of a chapter after the first: land just before it, paused, with that chapter as the call to action. */
  private stop(t: number): boolean {
    const d = this.d, from = this.last;
    this.last = t;
    if (!this.o.stops) return false;
    const ch = d.chapters().filter((c) => c.t !== undefined && c.t > 0).find((c) => from < c.t! - STOP_LEAD && t >= c.t! - STOP_LEAD);
    if (!ch) return false;
    const at = ch.t! - STOP_LEAD;
    d.reach(at);
    this.land(at, false);
    this.shown = 'next';
    d.shell.cta(`Chapter ${ch.numeral}: ${ch.label}`, () => { d.reach(ch.t!); this.land(ch.t!, true); });
    d.events.emit({ type: 'stop', chapter: ch.id });
    return true;
  }
  /** Coming back lands on the sentence that was playing. */
  leaving(): EnterOptions { return { at: this.d.clock.now() }; }
  exit(): void {
    this.memento = null; this.held = null; this.dragPlay = null;
    this.d.clock.stop(); this.d.voice.stop(); this.d.shell.playing(false);
    this.d.goal = this.o.exitGoal?.(this.d.s) ?? {};
    this.d.hands.forEach((x) => { x.enabled = false; });
  }
}
