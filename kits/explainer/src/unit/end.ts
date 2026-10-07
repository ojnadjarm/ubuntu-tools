import type { Beat, EnterOptions } from './beats';
import type { Director } from './director';
import type { ButtonKind } from './ports';

export interface EndOptions<S extends object> {
  enter?(d: Director<S>): void;
  /** Clip said once the end card is up (the closing thought). */
  say?: string;
  /** Beat the Replay button goes to (default `watch`). */
  replay?: string;
  /** Hands the learner may turn on the finished plate (default: all). */
  hands?: number[];
  /** A chooser instead of the chapter list: one button per way on, each opening a beat. */
  choices?: { label: string; to: string; kind?: ButtonKind }[];
  /** The chooser card's words (default: the shell's end words). */
  card?: { eyebrow?: string; title?: string; lede?: string };
  /** Arriving completes the unit (default true; false for a fork part-way through). */
  complete?: boolean;
  /** A quiet note for what comes next under the chooser (no `href`: drawn as a phantom). */
  next?: { label: string; href?: string };
}

/** An end card over a live plate (its dials turn, its parts open): the chapter list and Replay, or a chooser of where to go next; an optional closing line. */
export class EndBeat<S extends object> implements Beat {
  readonly label: string;
  private d: Director<S>; private o: EndOptions<S>;
  constructor(d: Director<S>, label: string, o: EndOptions<S> | ((d: Director<S>) => void) = {}, replay?: string) {
    this.d = d; this.label = label;
    this.o = typeof o === 'function' ? { enter: o, replay } : { replay, ...o };
  }
  /** Arriving shows the card; a return visit (`snap`) opens the finished plate with the card closed. */
  enter(o: EnterOptions = {}): void {
    const d = this.d;
    this.o.enter?.(d);
    d.placeHands();
    d.hands.forEach((h, i) => { h.enabled = !this.o.hands || this.o.hands.includes(i); });
    if (o.snap !== undefined) { if (this.o.choices) this.card(); d.shell.closeEnd?.(); return; }
    if (this.o.complete !== false) d.events.emit({ type: 'complete', beat: 'unit' });
    this.card();
    if (this.o.say) void d.say(this.o.say);
  }
  private card(): void {
    const d = this.d, c = this.o.choices;
    d.shell.end(() => d.go(this.o.replay ?? 'watch'), c && { ...this.o.card, next: this.o.next, choices: c.map((x) => ({ label: x.label, kind: x.kind, go: () => d.go(x.to) })) });
  }
  snapshot(): unknown { return 'end'; }
  /** Coming back opens the card again. */
  leaving(): EnterOptions { return {}; }
  /** How the Begin card names this place on a return visit. */
  where(): string { return this.o.complete === false ? 'the end of the explanation' : 'the end'; }
  /** The Begin card's line on a return visit. */
  resumeLine(): string {
    return this.o.complete === false ? 'You finished the explanation. Continue to choose what comes next.' : 'You finished this plate. Continue opens it to try the dials; the chapters are in the bar.';
  }
  /** Say the closing line again. */
  back(): void { if (this.o.say) { this.d.hush(); void this.d.say(this.o.say); } }
  update(dt: number): void { this.d.readHands(dt); }
  exit(): void { this.d.shell.closeEnd?.(true); this.d.hands.forEach((h) => { h.enabled = false; }); }
}
