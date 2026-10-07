import type { Events } from '../core/events';
import type { ShellPort } from './ports';

/** How the drawing letters its parts: named leader labels while the explanation plays, numbers only after it. */
export type LabelMode = 'named' | 'numbered';

/** How a beat is entered: from a second of the watch axis, or restored from its own snapshot. */
export interface EnterOptions { at?: number; snap?: unknown }

/** One beat of the unit (State pattern); the learner's actions, not timers, move between beats. */
export interface Beat {
  readonly label: string;
  /** The bar's pause button works in this beat. */
  readonly pausable?: boolean;
  /** State is a function of the clock (no goal easing; captions follow the watch axis). */
  readonly timed?: boolean;
  enter(o?: EnterOptions): void;
  update(dt: number): void;
  exit(): void;
  /** The learner grabbed a hand. */
  touched?(): void;
  /** The bar's pause button or K. */
  toggle?(): void;
  /** Back one sentence (watch) or say the instruction again (play). */
  back?(): void;
  /** While paused, the values the motion under way is heading to (numbers are read from these), or null. */
  goals?(): Record<string, number> | null;
  /** Hold for a callout (no snapshot) and resume at the sentence start. */
  hold?(): void;
  release?(): void;
  /** Land on the sentence span holding watch second `t`. */
  seek?(t: number, play?: boolean): void;
  /** Follow a drag on the progress bar silently; the release is a `seek`. */
  scrub?(t: number): void;
  fwd?(): void;
  /** Play the current step's hint; false when there is none. */
  hint?(): boolean;
  /** Give up on the open case: its answer is shown, then a new case or the next is offered; false when there is none. */
  giveUp?(): boolean;
  /** Press in (Enter, a press on a knob or a plaque); false when the beat has nothing to press. */
  commit?(): boolean;
  /** A tap on the drawing in world units; true when the beat used it (a callout opens otherwise). */
  tap?(wx: number, wy: number): boolean;
  /** How the drawing letters its parts in this beat now (default `numbered`). */
  labels?(): LabelMode;
  /** The learner's progress in this beat (Memento), restored by `enter({ snap })`. */
  snapshot?(): unknown;
  /** Where a snapshot returns to, for the "Back to …" button. */
  where?(snap: unknown): string;
  /** The Begin card's whole line on a return visit (default: "You stopped at <where>."). */
  resumeLine?(snap: unknown): string;
  /** How to enter this beat again where the learner left it (default `{ snap: snapshot() }`). */
  leaving?(): EnterOptions;
}

interface Port { hush(): void; shell: ShellPort; events: Events }

/** Holds the current beat, switches beats, forwards frames and touches, and keeps a stack of left beats to return to. */
export class BeatMachine {
  private beats: Record<string, Beat> = {};
  cur: Beat | null = null;
  name: string | null = null;
  /** Beats left for a re-watch, newest last, each with its snapshot. */
  readonly stack: { name: string; snap: unknown }[] = [];
  /** The beat last left and how to enter it again where the learner was (Memento). */
  left: { name: string; enter: EnterOptions } | null = null;
  private d: Port;
  constructor(d: Port) { this.d = d; }
  add(name: string, beat: Beat): this { this.beats[name] = beat; return this; }
  get(name: string): Beat | undefined { return this.beats[name]; }
  names(): string[] { return Object.keys(this.beats); }
  go(n: string, o?: EnterOptions): void {
    const b = this.beats[n];
    if (!b) throw new Error(`no beat ${n}`);
    if (this.cur && this.name) this.left = { name: this.name, enter: this.cur.leaving?.() ?? { snap: this.cur.snapshot?.() } };
    this.cur?.exit();
    this.d.hush();
    this.d.shell.cta(null);
    this.d.shell.pausable(!!b.pausable);
    this.d.shell.status(b.label);
    this.name = n; this.cur = b;
    this.d.events.emit({ type: 'beat', name: n });
    b.enter(o);
  }
  /** Leave the current beat for `to` (a re-watch) with its snapshot on the stack; one entry per beat. */
  back(to: string, at?: number): void {
    if (this.name && this.name !== to) {
      const i = this.stack.findIndex((x) => x.name === this.name);
      if (i >= 0) this.stack.splice(i, 1);
      this.stack.push({ name: this.name, snap: this.cur?.snapshot?.() });
    }
    this.go(to, { at });
  }
  /** The newest left beat as a button label and action, or null. */
  ret(): { label: string; go: () => void } | null {
    const top = this.stack.at(-1); if (!top) return null;
    const b = this.beats[top.name];
    return { label: `Back to ${b.where?.(top.snap) ?? b.label.toLowerCase()}`, go: () => this.returnTo(top.name) };
  }
  /** Re-enter a left beat (default the newest) from its snapshot; false if none is waiting. */
  returnTo(name?: string): boolean {
    const i = name ? this.stack.findIndex((x) => x.name === name) : this.stack.length - 1;
    if (i < 0) return false;
    const [top] = this.stack.splice(i, 1);
    this.go(top.name, { snap: top.snap });
    return true;
  }
  update(dt: number): void { this.cur?.update(dt); }
  touched(): void { this.cur?.touched?.(); }
  toggle(): void { this.cur?.toggle?.(); }
}
