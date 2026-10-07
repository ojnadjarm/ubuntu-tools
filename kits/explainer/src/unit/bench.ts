import { numbers, rng } from '../core/math';
import type { Beat, EnterOptions } from './beats';
import type { Director } from './director';
import { BenchFlow, type FlowRules } from './flow';
import { HintLadder, type Rung } from './hints';
import { Walk, type WalkStep } from './walk';

/** A judged press-in: pass or miss, and the motion that plays before the verdict is said (a dial turning its drawn clicks). */
export interface Judged { pass: boolean; walk?: WalkStep[] }
type Lines<S extends object> = string | ((d: Director<S>) => string[]);

/** One case on the bench: a round of an exercise, a contrast pair or a race level. It is posed from a seed, played by hand, and judged. */
export interface Task<S extends object> {
  id: string;
  /** The exercise it belongs to (a new exercise waits for the learner's Continue). */
  of?: string;
  label: string;
  /** The spoken task; its caption stays on screen while the case is open. */
  ask: string;
  /** Hands the learner may use. */
  hands: number[];
  setup(d: Director<S>, seed: number): void;
  ok: Lines<S>;
  miss?: Lines<S>;
  /** Hint rungs: Look (a lamp walk over the parts), Narrow (a spoken rule), Show me (the case worked, then a new one). */
  look?(d: Director<S>): WalkStep[];
  narrow?: string;
  show?(d: Director<S>): WalkStep[];
  /** The worked answer a give-up plays (default `show`). */
  answer?(d: Director<S>): WalkStep[];
  /** Judged every frame: true passes once held for `hold` s, false is a miss (a lost race), null plays on. */
  verdict?(d: Director<S>): boolean | null;
  hold?: number;
  /** A press-in (Enter, the knob, a plaque): the verdict, or null when there is nothing to judge yet. */
  commit?(d: Director<S>): Judged | null;
  /** A tap on the drawing in world units: 'commit' presses in, true is handled, false passes it on (a callout). */
  tap?(d: Director<S>, wx: number, wy: number): 'commit' | boolean;
  /** The misconception the learner's play shows, read at a miss or every frame while playing (once per case). */
  detect?(d: Director<S>, when: 'miss' | 'play'): string | null;
  /** Uncover the working after a miss. */
  reveal?(d: Director<S>): void;
  /** Motion after the pass line (one more click, then back). */
  after?(d: Director<S>): WalkStep[];
  update?(d: Director<S>, dt: number): void;
  exit?(d: Director<S>): void;
  /** After a miss: the button label (default "Try a new one"), whether the retry keeps the case, and a second way on. */
  retry?: { label?: string; same?: boolean; skip?: string };
}

export interface BenchOptions<S extends object> {
  label: string;
  next: string;
  cta?: string;
  tasks: Task<S>[];
  /** Misconception id → its refutation clip and its contrast-pair task. */
  refute(m: string): string | undefined;
  contrasts?: Record<string, Task<S>>;
  /** Offered once after clean first tries in a row: the line, the chip, the beat it opens. */
  skip?: { clip: string; label: string; to: string };
  rules?: FlowRules;
  seed?: number;
  /** Endless practice: once the queue is played, `pick` draws the next case from `tasks` (default: any, at random); `leave` is a standing chip onward. */
  pool?: { tasks: Task<S>[]; pick?(r: () => number, prev: Task<S> | undefined): Task<S>; leave?: { label: string; to: string } };
  /** A tap the open case does not take, in any phase (a figure beside the plate that poses its example): true when handled. */
  tap?(d: Director<S>, wx: number, wy: number): boolean;
  enter?(d: Director<S>): void;
  exit?(d: Director<S>): void;
}

interface Snap<S> { i: number; ids: string[]; seed: number; flow: ReturnType<BenchFlow['snapshot']>; s: S }
type Phase = 'play' | 'judge' | 'walk' | 'wait';

/** Workbench: a queue of hand-played cases with press-in or held verdicts, detectors, refutations, contrast pairs, a hint ladder, the skip offer, give-up and endless practice. */
export class Bench<S extends object> implements Beat {
  readonly label: string;
  private q: Task<S>[] = [];
  private i = 0;
  private seed = 0;
  private phase: Phase = 'wait';
  private held = 0;
  private tries = 0;
  private fired = false;
  /** The skip was offered: its chip stays while the learner keeps working. */
  private skipping = false;
  /** The open case was given up (its answer shown). */
  gaveUp = false;
  private walk: Walk | null = null;
  private then: (() => void) | null = null;
  private flow: BenchFlow;
  private ladder = new HintLadder();
  private next: () => number;
  private d: Director<S>; private name: string; private o: BenchOptions<S>;
  constructor(d: Director<S>, name: string, o: BenchOptions<S>) {
    this.d = d; this.name = name; this.o = o; this.label = o.label;
    this.flow = new BenchFlow(o.rules);
    this.next = rng(o.seed ?? 11);
  }
  /** The open case (tests read it). */
  get task(): Task<S> | undefined { return this.q[this.i]; }
  get index(): number { return this.i; }
  private find(id: string): Task<S> | undefined {
    return [...this.o.tasks, ...Object.values(this.o.contrasts ?? {}), ...this.o.pool?.tasks ?? []].find((t) => t.id === id);
  }
  /** Endless practice: the next case drawn from the pool. */
  private draw(): Task<S> | undefined {
    const p = this.o.pool;
    if (!p?.tasks.length) return undefined;
    const t = p.pick ? p.pick(this.next, this.q[this.i - 1]) : p.tasks[Math.floor(this.next() * p.tasks.length)];
    this.q.push(t);
    return t;
  }
  enter(o: EnterOptions = {}): void {
    const snap = o.snap as Snap<S> | undefined;
    this.o.enter?.(this.d);
    this.q = snap ? snap.ids.map((id) => this.find(id)).filter((t): t is Task<S> => !!t) : [...this.o.tasks];
    if (snap) this.flow.restore(snap.flow); else this.flow = new BenchFlow(this.o.rules);
    this.skipping = !!snap && this.flow.snapshot().offered;
    this.i = snap ? Math.min(snap.i, this.q.length) : 0;
    this.open(snap ? snap.seed : this.fresh(), snap?.s);
  }
  snapshot(): Snap<S> { return { i: this.i, ids: this.q.map((t) => t.id), seed: this.seed, flow: this.flow.snapshot(), s: numbers(this.d.s) }; }
  where(snap: unknown): string { const t = this.q[(snap as Snap<S> | undefined)?.i ?? this.i]; return t ? t.label.toLowerCase() : this.label.toLowerCase(); }
  private fresh(): number { return Math.floor(this.next() * 1e9); }

  /** Pose case `i` from `seed` (with `s`, a restored plate), say its task, and hand over the hands. */
  private open(seed: number, s?: S): void {
    const d = this.d, t = this.q[this.i] ?? this.draw();
    this.seed = seed; this.held = 0; this.tries = 0; this.fired = false; this.walk = null; this.then = null;
    this.offerSkip();
    if (!t) { this.stand(null); d.events.emit({ type: 'complete', beat: this.name }); d.shell.cta(this.o.cta ?? 'Continue', () => d.go(this.o.next)); return; }
    t.setup(d, seed);
    if (s) { Object.assign(d.s, s); for (const c of d.controls) c.hand.place(d.s[c.key] as number); }
    d.log.clear(d.hands.map((h) => h.value()), d.elapsed);
    this.ladder.offer([t.look && 'look', t.narrow && 'narrow', t.show && 'show'].filter(Boolean) as Rung[]);
    this.gaveUp = false;
    this.enable(t.hands);
    this.phase = 'play';
    this.stand(t);
    d.events.emit({ type: 'step', beat: this.name, index: this.i, phase: 'start' });
    void d.say(t.ask);
    d.wake();
  }
  private offerSkip(): void {
    const s = this.o.skip, l = this.o.pool?.leave, d = this.d;
    if (l) d.shell.offer?.(l.label, () => d.go(l.to)); else d.shell.offer?.(this.skipping && s ? s.label : null, s && (() => d.go(s.to)));
  }
  private stand(t: Task<S> | null): void {
    this.d.shell.instruction?.(t ? this.d.captions.text(t.ask) || null : null);
    const on = !!t && this.phase === 'play' && !!this.ladder.peek();
    this.d.shell.hintable?.(on, on ? this.ladder.label() : undefined);
    this.d.shell.giveable?.(!!t && this.phase === 'play' && !!(t.answer ?? t.show));
  }
  private enable(hands: number[]): void {
    this.d.hands.forEach((h, k) => { h.enabled = hands.includes(k); });
    if (hands.length) this.d.activeHand = hands[0];
  }
  private run(steps: WalkStep[], then: () => void): void {
    this.phase = 'walk';
    this.walk = new Walk(steps);
    this.then = then;
    if (this.d.reduced) this.walk.finish();
  }
  private async lines(l: Lines<S> | undefined): Promise<boolean> {
    for (const id of l === undefined ? [] : typeof l === 'string' ? [l] : l(this.d)) if (!(await this.d.say(id))) return false;
    return true;
  }

  /** Say the task again. */
  back(): void { const t = this.task; if (t && this.phase === 'play') { this.d.hush(); void this.d.say(t.ask); } }
  hint(): boolean {
    const t = this.task, d = this.d;
    if (!t || this.phase !== 'play') return false;
    const r = this.ladder.next();
    if (!r) return false;
    d.events.emit({ type: 'hint', beat: this.name, index: this.i });
    this.stand(t);
    d.hush();
    if (r === 'narrow') void d.say(t.narrow!);
    else if (r === 'look') this.run(t.look!(d), () => { this.phase = 'play'; });
    else { this.flow.result(false); this.enable([]); this.stand(null); this.run(t.show!(d), () => this.retry(t, 'Try a new one', false)); }
    d.wake();
    return true;
  }
  /** Give up: the case counts as missed, its answer plays (the dials turn, the working is drawn), then a new case or the next. */
  giveUp(): boolean {
    const t = this.task, d = this.d, answer = t?.answer ?? t?.show;
    if (!t || !answer || this.phase !== 'play') return false;
    d.events.emit({ type: 'giveup', beat: this.name, index: this.i });
    this.gaveUp = true;
    this.flow.result(false); this.enable([]); this.stand(null);
    d.hush();
    this.run(answer(d), () => this.retry(t, 'Try a new one', false, 'Next'));
    d.wake();
    return true;
  }
  commit(): boolean {
    const t = this.task;
    if (!t?.commit || this.phase !== 'play') return false;
    const r = t.commit(this.d);
    if (r) this.judge(r.pass, r.walk);
    this.d.wake();
    return true;
  }
  tap(wx: number, wy: number): boolean {
    const t = this.task;
    if (t?.tap && this.phase === 'play') {
      const r = t.tap(this.d, wx, wy);
      if (r === 'commit') return this.commit();
      if (r) return true;
    }
    return this.o.tap?.(this.d, wx, wy) ?? false;
  }

  update(dt: number): void {
    const d = this.d, t = this.task;
    d.readHands(dt);
    if (!t) return;
    t.update?.(d, dt);
    if (this.phase === 'walk') {
      d.wake();
      if (this.walk?.update(dt * d.rate)) { const f = this.then; this.walk = null; this.then = null; f?.(); }
      return;
    }
    if (this.phase !== 'play') return;
    if (!this.fired && t.detect) { const m = t.detect(d, 'play'); if (m) this.detected(m, true); }
    const v = t.verdict?.(d) ?? null;
    if (v === null) { this.held = 0; return; }
    if (v && (this.held += dt) < (t.hold ?? 0.35)) { d.wake(); return; }
    this.judge(v);
  }

  /** A misconception showed: refute it (at most twice), queue its contrast pair (after two firings). */
  private detected(m: string, playing: boolean): string | undefined {
    const d = this.d, f = this.flow.fire(m), c = this.o.contrasts?.[m];
    this.fired = true;
    d.events.emit({ type: 'detect', beat: this.name, task: this.task!.id, m });
    if (f.contrast && c) this.q.splice(playing ? this.i + 1 : this.i, 0, c);
    const clip = f.refute ? this.o.refute(m) : undefined;
    if (clip && playing) { d.hush(); void d.say(clip); }
    return clip;
  }

  private judge(pass: boolean, walk?: WalkStep[]): void {
    const d = this.d, t = this.task!;
    this.phase = 'judge';
    this.enable([]);
    this.stand(null);
    this.tries++;
    d.events.emit({ type: 'attempt', beat: this.name, index: this.i, pass, tries: this.tries });
    const verdict = (): void => { if (pass) void this.passed(t); else void this.missed(t); };
    if (walk?.length) this.run(walk, () => { this.phase = 'judge'; verdict(); }); else verdict();
  }
  private async passed(t: Task<S>): Promise<void> {
    const d = this.d, clean = this.tries === 1 && !this.ladder.used() && !this.fired;
    d.events.emit({ type: 'step', beat: this.name, index: this.i, phase: 'done' });
    const skip = this.o.skip && !t.retry && this.flow.result(clean);
    if (!(await this.lines(t.ok))) return;
    const go = async (): Promise<void> => {
      if (skip && this.o.skip) {
        this.skipping = true;
        this.offerSkip();
        if (!(await d.say(this.o.skip.clip))) return;
      }
      const nx = this.q[this.i + 1];
      this.i++;
      if (!nx && this.o.pool) { this.phase = 'wait'; d.shell.cta('Next', () => this.open(this.fresh())); return; }
      if (!nx || (nx.of !== undefined && nx.of === t.of)) { this.open(this.fresh()); return; }
      this.phase = 'wait';
      d.shell.cta(t.of && nx.of && nx.of !== t.of ? 'Next exercise' : 'Continue', () => this.open(this.fresh()));
    };
    const after = t.after?.(d);
    if (after?.length) this.run(after, () => { void go(); }); else await go();
  }
  private async missed(t: Task<S>): Promise<void> {
    const d = this.d, m = !this.fired ? t.detect?.(d, 'miss') : null;
    if (!t.retry) this.flow.result(false);
    t.reveal?.(d);
    if (!(await this.lines(t.miss))) return;
    const clip = m ? this.detected(m, false) : undefined;
    if (clip && !(await d.say(clip))) return;
    this.retry(t, t.retry?.label ?? 'Try a new one', !!t.retry?.same, t.retry?.skip);
  }
  /** Wait for the learner: the button poses the open case again (the same one, or a new one); a contrast pair queued meanwhile goes first. */
  private retry(t: Task<S>, label: string, same: boolean, skip?: string): void {
    const d = this.d, seed = this.seed, first = this.q[this.i] !== t;
    this.phase = 'wait';
    if (skip) d.shell.offer?.(skip, () => { d.shell.cta(null); this.i = this.q.indexOf(t, this.i) + 1; this.open(this.fresh()); });
    d.shell.cta(first ? 'Continue' : label, () => this.open(same && !first ? seed : this.fresh()));
  }
  exit(): void {
    const d = this.d;
    this.task?.exit?.(d);
    this.walk = null;
    this.stand(null);
    d.shell.offer?.(null);
    d.hands.forEach((h) => { h.enabled = false; });
    this.o.exit?.(d);
    this.skipping = false;
  }
}
