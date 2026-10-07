import { numbers } from '../core/math';
import type { Beat, EnterOptions } from './beats';
import type { Director } from './director';

/** One exercise or puzzle round: set it up, let the learner act, judge it. */
export interface Round<S extends object> {
  /** Clip ids: the task, the line on a pass, the line on a miss. */
  ask: string; pass: string; fail: string;
  /** Clips said after the 1st, 2nd, … miss (before the retry), and on request (H) while the learner works. */
  hints?: string[];
  /** Hands enabled while the learner acts (default: all). */
  hands?: number[];
  /** Seconds a pass must hold before it counts (default 0.3); a miss counts at once. */
  hold?: number;
  /** Put the round in its starting position (also before each retry). */
  setup?(d: Director<S>): void;
  /** Per-frame round logic (an opponent, a timer, ghost needles). */
  update?(d: Director<S>, dt: number): void;
  /** true = solved, false = missed, null = still working. */
  verdict(d: Director<S>): boolean | null;
}

export interface ExerciseOptions<S extends object> {
  next: string;
  label: string;
  cta?: string;
  /** Retry a missed round (default true); false moves on after the miss line. */
  retry?: boolean;
  enter?(d: Director<S>): void;
  exit?(d: Director<S>): void;
}

/** Where an exercise was left: the round and every state number. */
interface Snap<S> { i: number; s: S }

/** Exercise: rounds judged by a verdict, with pass and miss lines, hints after misses and retries (success/retry flow). */
export class Exercise<S extends object> implements Beat {
  readonly label: string;
  private i = -1; private tries = 0; private heldFor = 0;
  private phase: 'ask' | 'play' | 'judge' = 'ask';
  private d: Director<S>; private name: string; private rounds: Round<S>[]; private o: ExerciseOptions<S>;
  constructor(d: Director<S>, name: string, rounds: Round<S>[], o: ExerciseOptions<S>) {
    this.d = d; this.name = name; this.rounds = rounds; this.o = o; this.label = o.label;
  }
  get round(): number { return this.i; }
  enter(o: EnterOptions = {}): void {
    const snap = o.snap as Snap<S> | undefined;
    this.o.enter?.(this.d);
    if (!snap) { this.i = -1; this.nextRound(); return; }
    Object.assign(this.d.s, snap.s);
    this.i = snap.i; this.open(false);
  }
  snapshot(): Snap<S> { return { i: this.i, s: numbers(this.d.s) }; }
  where(snap: unknown): string {
    const i = (snap as Snap<S> | undefined)?.i ?? 0;
    return i < this.rounds.length ? `${this.label.toLowerCase()} · round ${i + 1}` : this.label.toLowerCase();
  }
  private nextRound(): void { this.i++; this.open(true); }
  /** Start round `i` (fresh: emits `step start`; restored: set up and asked again, no event). */
  private open(fresh: boolean): void {
    const d = this.d; this.tries = 0;
    if (this.i >= this.rounds.length) {
      d.shell.hintable?.(false);
      if (fresh) d.events.emit({ type: 'complete', beat: this.name });
      d.shell.cta(this.o.cta ?? 'Continue', () => d.go(this.o.next));
      return;
    }
    const r = this.rounds[this.i];
    r.setup?.(d);
    this.enable(false);
    this.phase = 'ask';
    d.shell.hintable?.(!!r.hints?.length);
    if (fresh) d.events.emit({ type: 'step', beat: this.name, index: this.i, phase: 'start' });
    void d.say(r.ask).then((ok) => { if (ok) this.arm(); });
  }
  private enable(on: boolean): void {
    const r = this.rounds[this.i];
    this.d.hands.forEach((h, k) => { h.enabled = on && (!r?.hands || r.hands.includes(k)); });
    if (on && r?.hands?.length) this.d.activeHand = r.hands[0];
  }
  private arm(): void { this.phase = 'play'; this.heldFor = 0; this.enable(true); this.d.wake(); }
  /** Say the task again while the learner works. */
  back(): void { const r = this.rounds[this.i]; if (r && this.phase === 'play') { this.d.hush(); void this.d.say(r.ask); } }
  /** The next hint of the round, on request. */
  hint(): boolean {
    const r = this.rounds[this.i], h = r?.hints?.[Math.min(this.tries, (r.hints?.length ?? 1) - 1)];
    if (!h || this.phase !== 'play') return false;
    this.d.events.emit({ type: 'hint', beat: this.name, index: this.i });
    this.d.hush(); void this.d.say(h);
    return true;
  }
  update(dt: number): void {
    const d = this.d, r = this.rounds[this.i];
    d.readHands(dt);
    if (!r) return;
    r.update?.(d, dt);
    if (this.phase !== 'play') return;
    const v = r.verdict(d);
    if (v === null) { this.heldFor = 0; return; }
    if (v && (this.heldFor += dt) < (r.hold ?? 0.3)) return;
    this.phase = 'judge';
    this.enable(false);
    this.tries++;
    d.events.emit({ type: 'attempt', beat: this.name, index: this.i, pass: v, tries: this.tries });
    if (v) { d.events.emit({ type: 'step', beat: this.name, index: this.i, phase: 'done' }); void d.say(r.pass).then((ok) => { if (ok) this.nextRound(); }); return; }
    void d.say(r.fail).then(async (ok) => {
      if (!ok) return;
      if (this.o.retry === false) { this.nextRound(); return; }
      const hint = r.hints?.[Math.min(this.tries, r.hints.length) - 1];
      if (hint) { d.events.emit({ type: 'hint', beat: this.name, index: this.i }); if (!(await d.say(hint))) return; }
      r.setup?.(d);
      this.arm();
    });
  }
  exit(): void { this.d.shell.hintable?.(false); this.d.hands.forEach((h) => { h.enabled = false; }); this.o.exit?.(this.d); }
}
