import type { Voice } from '../audio/voice';
import type { ChapterSpec, Term, UnitBundle } from '../content/types';
import type { Clock } from '../core/clock';
import type { Hand } from '../play/hand';
import type { Timeline } from '../motion/timeline';
import type { Hotspot } from '../play/hotspots';
import { HotspotRouter } from '../play/hotspots';
import { CueBinder, layoutClips } from '../motion/cues';
import { Captions, spanAt, type Span } from '../captions';
import { Events } from '../core/events';
import { damp } from '../core/math';
import { stateKeyer, OnDemand } from '../loop';
import { BeatMachine, type LabelMode } from './beats';
import { TermIndex } from './terms';
import { Notes } from './notes';
import { CommandLog } from './log';
import { chapterAt, chapterList, chapterSpecs, chapterStarts, type Chapter } from './chapters';
import type { Control, Explained, ShellPort, UnitDef, View } from './ports';

export interface DirectorParts<S> { unit: UnitDef<S>; bundle: UnitBundle; view: View<S>; voice: Voice; clock: Clock; shell: ShellPort; controls?: Control<S>[]; hotspots?: Hotspot[] }
/** Goal easing: per-key rates (default 2.6/s), per-key arrival distance (default 0.005) and keys that snap under reduced motion. */
export interface Easing<S> { rates?: Partial<Record<keyof S, number>>; eps?: Partial<Record<keyof S, number>>; snap?: (keyof S)[] }

/** Mediator: owns state, clock, voice, captions, hands, beats, terms and the open callout; parts never talk sideways. Draws on demand. */
export class Director<S extends object> {
  s: S;
  goal: Partial<S> = {};
  readonly tl: Timeline;
  readonly offsets: Record<string, number>;
  readonly captions: Captions;
  readonly spans: Span[];
  readonly terms: TermIndex;
  readonly notes: Notes;
  readonly spots: HotspotRouter;
  readonly beats: BeatMachine;
  readonly events = new Events();
  readonly controls: Control<S>[];
  readonly hands: Hand[];
  /** Every learner move and try, for detectors that read history. */
  readonly log = new CommandLog();
  /** Seconds since the director started (frames only; the log's clock). */
  elapsed = 0;
  readonly unit: UnitDef<S>; readonly bundle: UnitBundle; readonly view: View<S>; readonly voice: Voice; readonly clock: Clock; readonly shell: ShellPort;
  readonly visited = new Set<string>();
  readonly completed = new Set<string>();
  activeHand = 0;
  /** A dial is picked: in the watch the arrows turn it instead of seeking. */
  picked = false;
  /** Furthest watch second heard; it only grows. */
  furthest = 0;
  /** Term of the open callout. */
  opened: string | null = null;
  reduced = false;
  /** Speed of muted lines and scripted walks (`?mute&fast=8` in headless runs); 1 in every real session. */
  rate = 1;
  onFrame: (drawMs: number) => void = () => undefined;
  private reached = new Set<string>();
  private easing: Easing<S>;
  private line: { id: string; at: number } | null = null;
  private lineGen = 0;
  private lastKey = '';
  private lastPlaying = false;
  private lastChapters = '';
  private mode: LabelMode | null = null;
  private flowRun = 0;
  private dirty = true;
  private loop = new OnDemand((dt) => this.tick(dt));
  private key = stateKeyer();
  private chapterSpecs: ChapterSpec[];
  private chapterStarts: (number | undefined)[];

  constructor(p: DirectorParts<S>, easing: Easing<S> = {}) {
    this.unit = p.unit; this.bundle = p.bundle; this.view = p.view; this.voice = p.voice; this.clock = p.clock; this.shell = p.shell;
    this.controls = p.controls ?? [];
    this.hands = this.controls.map((c) => c.hand);
    this.easing = easing;
    this.s = p.unit.initial();
    const w = p.unit.watch;
    this.offsets = layoutClips(p.bundle.cues, w.order, w.lead, w.gap).offsets;
    this.tl = w.build(this.s, new CueBinder(p.bundle.cues, this.offsets));
    this.captions = new Captions(p.bundle.cues, p.bundle.spec);
    this.spans = this.captions.spans(this.offsets, this.tl.duration());
    this.chapterSpecs = chapterSpecs(p.bundle.spec, this.offsets);
    this.chapterStarts = chapterStarts(this.chapterSpecs, this.offsets);
    this.terms = new TermIndex(p.bundle.spec, p.bundle.cues, this.offsets);
    this.notes = new Notes(p.bundle.spec, this.terms, p.bundle.cues, this.offsets);
    this.spots = new HotspotRouter(p.hotspots ?? []);
    this.beats = new BeatMachine(this);
    this.events.on('beat', (e) => { this.visited.add(e.name); this.picked = false; });
    this.events.on('complete', (e) => { this.completed.add(e.beat); });
    p.shell.spans?.(this.spans);
  }

  /** Play one narration line; resolves true when it ends (after its length when muted), false if a newer line or beat cut it. */
  async say(id: string): Promise<boolean> {
    const gen = ++this.lineGen;
    this.line = { id, at: performance.now() };
    for (const t of this.terms.namedBy(id)) this.unlock(t);
    this.wake();
    await this.voice.line(id);
    if (!this.voice.ctx) await new Promise((r) => setTimeout(r, this.bundle.cues.clips[id].duration * 1000 / this.rate));
    if (gen === this.lineGen) this.line = null;
    this.wake();
    return gen === this.lineGen;
  }
  hush(): void { this.lineGen++; this.line = null; this.voice.stop(); }

  go(beat: string, o?: { at?: number; snap?: unknown }): void { this.beats.go(beat, o); this.wake(); }

  /** Hands → state (the learner is driving); each new hand value is logged as a move. */
  readHands(dt: number): void {
    this.controls.forEach((c, i) => {
      (this.s[c.key] as number) = c.hand.update(dt);
      const v = c.hand.value(), was = this.log.value(i);
      if (v !== was) this.log.push({ hand: i, from: was, to: v, t: this.elapsed, kind: 'move' });
    });
  }
  /** State → hands (the timeline is driving). */
  placeHands(): void { for (const c of this.controls) c.hand.place(this.s[c.key] as number); }
  /** Set a case: state values, the hands whose keys it names put on them at once, and a fresh log from these values. */
  pose(v: Partial<S>): void {
    Object.assign(this.s, v);
    for (const c of this.controls) if (c.key in v) c.hand.place(this.s[c.key] as number);
    this.log.clear(this.hands.map((h) => h.value()), this.elapsed);
    this.wake();
  }

  /** Raise the furthest second heard; every term named by then unlocks. */
  reach(t: number): void {
    if (t > this.furthest) this.furthest = t;
    for (const x of this.terms.list) if (!this.reached.has(x.id) && this.terms.namedAt(x.id) <= this.furthest) this.unlock(x.id);
  }
  unlock(id: string): void {
    if (this.reached.has(id) || !this.terms.get(id)) return;
    this.reached.add(id);
    this.events.emit({ type: 'term', id });
    this.shell.terms?.(this.named().map((t) => ({ ...t, at: this.terms.namedAt(t.id) })));
  }
  /** A callout or term is explained: its watch second is heard, or the play line naming its term was said. */
  available(id: string): boolean {
    const n = this.notes.get(id);
    if (!n) return false;
    return Number.isFinite(n.at) ? this.furthest >= n.at - 1e-6 || this.reached.has(n.id) : this.reached.has(n.term.id);
  }
  /** The chapter that explains a thing said at watch second `at`, or (Infinity) the beat chapter of the play line naming `term`. */
  chapterOf(at: number, term: string): Chapter | undefined {
    const list = this.chapters(), clip = this.terms.clipOf(term);
    return Number.isFinite(at) ? chapterAt(list, at) : list.find((c) => c.beat && c.beat === this.bundle.spec.clips.find((x) => x.id === clip)?.beat);
  }
  named(): Term[] { return this.terms.list.filter((t) => this.reached.has(t.id)); }
  chapters(): Chapter[] { return chapterList(this.chapterSpecs, this.offsets, this.tl.duration(), this, this.chapterStarts); }

  /** Open the callout of term `id` (null closes it). A timed beat holds while it is open; closing resumes at the sentence start unless `resume` is false. */
  explain(id: string | null, resume = true): void {
    if (id === null) {
      if (this.opened === null) return;
      this.opened = null;
      this.view.explain?.(null); this.shell.explain?.(null);
      if (resume) this.beats.cur?.release?.();
    } else {
      const was = this.opened;
      this.opened = id;
      this.showCallout();
      if (was === null) this.beats.cur?.hold?.();
    }
    this.wake(true);
  }
  callout(id: string): Explained {
    const n = this.notes.get(id)!, spot = this.spots.byTerm(id) ?? (n.term.part ? this.spots.part(n.term.part) : undefined), available = this.available(id), ch = this.chapterOf(n.at, n.term.id);
    return { term: n.term, title: n.title, what: n.what, part: spot?.part ?? n.term.part, dot: spot?.dot, available, saidAt: n.at, said: n.said,
      chapter: ch ? { numeral: ch.numeral, label: ch.label } : null, now: available ? this.unit.live?.now(id, this.reading()) ?? null : null };
  }
  private showCallout(): void { const id = this.opened; if (id) { const c = this.callout(id); this.view.explain?.(c); this.shell.explain?.(c); } }

  /** Say the sentence that explains callout `id`: a seek in a timed beat, in place (voice only) anywhere else. */
  hear(id: string): void {
    const n = this.notes.get(id), at = n?.at ?? Infinity, cur = this.beats.cur;
    if (n && !n.said) return;
    if (!Number.isFinite(at)) { const clip = n && this.terms.clipOf(n.term.id); if (clip) { this.hush(); void this.say(clip); } return; }
    if (cur?.timed && cur.seek) { this.explain(null, false); cur.seek(at, true); return; }
    const sp = this.spans[spanAt(this.spans, at)], rel = at - this.offsets[sp.clip];
    const sent = this.captions.sentences(sp.clip).find((x, i, l) => rel >= x.s - 0.3 && rel < (l[i + 1]?.s ?? Infinity));
    this.hush();
    if (!sent) return;
    const gen = ++this.lineGen, s = Math.max(0, sent.s - 0.15);
    this.line = { id: sp.clip, at: performance.now() - s * 1000 };
    void this.voice.segment(sp.clip, s, sent.e + 0.3).then(() => { if (gen === this.lineGen) { this.line = null; this.wake(); } });
    this.wake();
  }
  /** Outline a part on the drawing (the pointer rests on its number). */
  light(part: string | null): void { this.view.light?.(part); this.wake(true); }

  /** How the drawing letters its parts now: the current beat's mode, `numbered` when it has none. */
  get labels(): LabelMode { return this.beats.cur?.labels?.() ?? 'numbered'; }
  /** Tell the view when the label mode changes (Observer: once per change, nothing polls it). */
  private letter(): boolean {
    const m = this.labels;
    if (m === this.mode) return false;
    this.mode = m; this.view.labels?.(m);
    return true;
  }

  /** Ease the free (non-timeline) state toward the current goal; a key within its `eps` lands on the goal, so the loop can stop. */
  private approach(dt: number): void {
    const s = this.s as Record<string, number>, e = this.easing as { rates?: Record<string, number>; eps?: Record<string, number>; snap?: string[] };
    for (const [k, v] of Object.entries(this.goal) as [string, number][]) {
      const x = this.reduced && e.snap?.includes(k) ? v : damp(s[k], v, e.rates?.[k] ?? 2.6, dt);
      s[k] = Math.abs(v - x) < (e.eps?.[k] ?? 0.005) ? v : x;
    }
  }

  /** The state numbers are read from: paused mid-motion, the values that motion is heading to. */
  private reading(): S {
    const g = this.beats.cur?.goals?.();
    return g && Object.keys(g).length ? { ...this.s, ...g } : this.s;
  }

  /** Chrome that follows state: progress, chapters, the drawn working and the open callout. */
  private chrome(changed: boolean, timed: boolean): void {
    const sh = this.shell;
    sh.progress?.(timed ? this.clock.now() : null, this.tl.duration(), this.furthest);
    const list = this.chapters(), key = list.map((c) => `${c.reached ? 1 : 0}${c.done ? 1 : 0}`).join();
    if (key !== this.lastChapters) { this.lastChapters = key; sh.chapters?.(list); }
    if (!changed) return;
    const live = this.unit.live;
    if (live?.working && sh.working) sh.working(live.working(this.reading()));
    this.showCallout();
  }

  /** One frame: beat logic, then draw only if something visible changed; returns whether it drew. */
  tick(dt: number): boolean {
    this.elapsed += dt;
    const timed = !!this.beats.cur?.timed;
    if (!timed) this.approach(dt);
    this.beats.update(dt);
    if (this.letter()) this.dirty = true;
    const key = this.key(this.s), changed = key !== this.lastKey;
    this.lastKey = key;
    this.flowRun = changed || this.clock.playing() ? 2.5 : Math.max(0, this.flowRun - dt);
    const run = this.flowRun > 0;
    this.shell.caption(timed ? this.captions.watch(this.clock.now(), this.offsets) : this.line ? this.captions.at(this.line.id, (performance.now() - this.line.at) / 1000) : '');
    const playing = this.clock.playing(), flip = playing !== this.lastPlaying;
    this.lastPlaying = playing;
    this.chrome(changed || flip, timed);
    if (!changed && !run && !this.dirty && !this.line) return false;
    this.dirty = false;
    const t0 = performance.now();
    this.view.draw(this.s, dt, run);
    this.onFrame(performance.now() - t0);
    return true;
  }

  /** Run the frame loop until nothing has changed for 30 frames; `redraw` forces one draw (resize, theme, callout). */
  wake(redraw = false): void { if (redraw) this.dirty = true; this.loop.wake(); }
}
