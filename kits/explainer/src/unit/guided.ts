import { numbers } from '../core/math';
import type { Beat, EnterOptions } from './beats';
import type { Director } from './director';

/** A predicate over the live unit (Specification): "is this step done?". */
export type Spec<S extends object> = (d: Director<S>) => boolean;
export const all = <S extends object>(...specs: Spec<S>[]): Spec<S> => (d) => specs.every((f) => f(d));
export const settled = <S extends object>(d: Director<S>): boolean => d.hands.every((h) => h.settled());
export const handAt = <S extends object>(i: number, v: number): Spec<S> => (d) => d.hands[i].value() === v;

/** One spoken instruction answered by the learner's hand. */
export interface GuidedStep<S extends object> {
  /** Index of the hand this step lights and enables (omit to enable none). */
  hand?: number;
  /** Every hand enabled in this step, when it is more than one (the lit one is `hand`, else the first). */
  hands?: number[];
  /** Clip ids: the instruction (it stays on screen until done), and the line said once it is done. */
  ask: string; ok: string;
  done: Spec<S>;
  /** Seconds `done` must hold before it counts (default 0.35). */
  hold?: number;
  /** Clip said when the learner asks for a hint (H, the Hint button). */
  hint?: string;
  /** Opt-in: also say the hint once after this many seconds stuck (default: only on request). */
  hintAfter?: number;
  enter?(d: Director<S>): void;
  after?(d: Director<S>): void;
}

export interface GuidedOptions<S extends object> {
  next: string;
  label?: string;
  cta?: string;
  enter?(d: Director<S>): void;
}

/** Where a guided beat was left: the step and every state number (dials included). */
interface Snap<S> { i: number; s: S }

/** Guided play: spoken steps, each checked every frame by its Specification, held, then confirmed out loud. */
export class GuidedPlay<S extends object> implements Beat {
  readonly label: string;
  private i = -1; private heldFor = 0; private waited = 0; private hinted = false; private waiting = false; private t = 0;
  private d: Director<S>; private name: string; private steps: GuidedStep<S>[]; private o: GuidedOptions<S>;
  constructor(d: Director<S>, name: string, steps: GuidedStep<S>[], o: GuidedOptions<S>) {
    this.d = d; this.name = name; this.steps = steps; this.o = o; this.label = o.label ?? 'Your turn';
  }
  enter(o: EnterOptions = {}): void {
    const d = this.d, snap = o.snap as Snap<S> | undefined;
    this.o.enter?.(d);
    if (snap) Object.assign(d.s, snap.s);
    for (const c of d.controls) c.hand.place(c.hand.snap(d.s[c.key] as number));
    if (snap) { this.i = snap.i; this.open(false); return; }
    this.i = -1; this.next();
  }
  snapshot(): Snap<S> { return { i: this.i, s: numbers(this.d.s) }; }
  where(snap: unknown): string {
    const i = (snap as Snap<S> | undefined)?.i ?? 0;
    return i < this.steps.length ? `${this.label.toLowerCase()} · step ${i + 1}` : this.label.toLowerCase();
  }
  private next(): void { this.i++; this.open(true); }
  /** Start step `i` (fresh: emits `step start`; restored: says the ask again only). */
  private open(fresh: boolean): void {
    const d = this.d; this.heldFor = 0; this.waited = 0; this.hinted = false;
    if (this.i >= this.steps.length) {
      this.stand(null);
      if (fresh) d.events.emit({ type: 'complete', beat: this.name });
      d.shell.cta(this.o.cta ?? 'Continue', () => d.go(this.o.next));
      return;
    }
    const st = this.steps[this.i];
    const on = st.hands ?? (st.hand === undefined ? [] : [st.hand]);
    d.hands.forEach((x, k) => { x.enabled = on.includes(k); });
    if (on.length) d.activeHand = st.hand ?? on[0];
    if (fresh) st.enter?.(d);
    this.waiting = true;
    this.stand(st);
    if (fresh) d.events.emit({ type: 'step', beat: this.name, index: this.i, phase: 'start' });
    void d.say(st.ask);
  }
  /** The standing instruction and the Hint button follow the open step. */
  private stand(st: GuidedStep<S> | null): void {
    this.d.shell.instruction?.(st ? this.d.captions.text(st.ask) || null : null);
    this.d.shell.hintable?.(!!st?.hint);
  }
  /** Say the open step's instruction again. */
  back(): void { const st = this.steps[this.i]; if (st && this.waiting) { this.d.hush(); void this.d.say(st.ask); } }
  hint(): boolean {
    const st = this.steps[this.i];
    if (!st?.hint || !this.waiting) return false;
    this.hinted = true;
    this.d.events.emit({ type: 'hint', beat: this.name, index: this.i });
    this.d.hush(); void this.d.say(st.hint);
    return true;
  }
  update(dt: number): void {
    const d = this.d, s = d.s as Record<string, number>;
    this.t += dt;
    d.readHands(dt);
    const st = this.steps[this.i];
    const breathe = 0.55 + 0.45 * Math.sin(this.t * 2.2);
    d.controls.forEach((c, k) => { if (c.glow) s[c.glow as string] = st && this.waiting && st.hand === k ? breathe : 0; });
    if (!st || !this.waiting) return;
    this.waited += dt;
    if (st.hintAfter !== undefined && !this.hinted && this.waited >= st.hintAfter) this.hint();
    this.heldFor = st.done(d) ? this.heldFor + dt : 0;
    if (this.heldFor < (st.hold ?? 0.35)) return;
    this.waiting = false;
    this.stand(null);
    d.hands.forEach((x) => { x.enabled = false; });
    d.events.emit({ type: 'step', beat: this.name, index: this.i, phase: 'done' });
    st.after?.(d);
    void d.say(st.ok).then((ok) => { if (ok) this.next(); });
  }
  exit(): void {
    const d = this.d, s = d.s as Record<string, number>;
    this.stand(null);
    d.hands.forEach((x) => { x.enabled = false; });
    d.controls.forEach((c) => { if (c.glow) s[c.glow as string] = 0; });
  }
}
