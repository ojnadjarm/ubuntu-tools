import type { SectionView } from './sections';
import type { Timeline } from '../motion/timeline';
import type { CueBinder } from '../motion/cues';
import type { Projector } from '../play/pointer';
import type { Hand } from '../play/hand';
import type { Term } from '../content/types';
import type { Span } from '../captions';
import type { Chapter } from './chapters';
import type { LabelMode } from './beats';
import type { Item } from '../place/place';
import type { Zoom } from '../play/zoom';

/** An open callout: the term, its title and line, the part and dot it is drawn from, whether it is explained yet, and how it is made right now. */
export interface Explained {
  term: Term; title: string; what: string; part?: string; dot?: [number, number];
  /** Named already (else the note says only "Explained in chapter …", with no word and no gloss). */
  available: boolean;
  /** Watch second it is explained at (Infinity when a play line names it). */
  saidAt: number;
  /** A sentence says it (false: a tool of the exercises; no Hear it). */
  said: boolean;
  chapter: { numeral: string; label: string } | null;
  /** The live line ("2 × 1.5 = 3.0"), from the unit's `live.now`. */
  now: string | null;
}

/** A named term with the watch second it is said at (Infinity when a play line names it). */
export type NamedTerm = Term & { at: number };

/** The style's side: draw a state, fit the viewport, map pointer pixels to world units. */
export interface View<S> extends Projector {
  /** Container observed for resizes. */
  readonly el: HTMLElement;
  /** Element that receives pointer input. */
  readonly canvas: HTMLElement;
  draw(s: S, dt: number, run: boolean): void;
  resize(): void;
  /** Compile shaders or warm caches before Begin. */
  prepare?(): void;
  /** Draw a callout on the drawing (dot, leader, note), or clear it. */
  explain?(c: Explained | null): void;
  /** Outline a part (the pointer rests on its number), or none. */
  light?(part: string | null): void;
  /** What of the drawn note is under screen point (px, py). */
  noteAt?(px: number, py: number): 'hear' | 'close' | 'inside' | null;
  /** Named leader labels (the explanation) or numbers only (after it); the view draws no named label in `numbered`. */
  labels?(mode: LabelMode): void;
  /** What is drawn now, in drawing units, for the layout rules (tests read it). */
  layout?(): Item[];
  /** The learner's zoom over the framed shot; with it the player adds the zoom control. */
  readonly zoom?: Zoom;
}

/** What the director needs from the page chrome; the optional part is the player (progress, chapters, callouts, transcript). */
export interface ShellPort {
  cta(label: string | null, go?: () => void): void;
  caption(text: string): void;
  playing(on: boolean): void;
  pausable(on: boolean): void;
  status(text: string): void;
  /** The end card: the chapter list and Replay, or with `card.choices` a chooser of where to go next. */
  end(onReplay: () => void, card?: EndCard): void;
  /** Close the end card if it is open (a chooser leaves a button that reopens it; `leaving` drops both); false when it was not open. */
  closeEnd?(leaving?: boolean): boolean;
  /** The Give up control of the open case is there, or not. */
  giveable?(on: boolean): void;
  /** Watch second (null outside the watch), watch length, furthest second heard. */
  progress?(t: number | null, dur: number, furthest: number): void;
  chapters?(list: Chapter[]): void;
  /** Terms named so far (caption words become links, the bar marks where each is said). */
  terms?(list: NamedTerm[]): void;
  explain?(c: Explained | null): void;
  /** The standing instruction of a play step, or none. */
  instruction?(text: string | null): void;
  /** A hint is there to ask for, and the button's label (Hint, Another hint, Show me). */
  hintable?(on: boolean, label?: string): void;
  /** A second way on beside the standing instruction (open the Challenge, next level), or none. */
  offer?(label: string | null, go?: () => void): void;
  /** The watch's sentence spans (transcript). */
  spans?(list: Span[]): void;
  /** The working the drawing carries now, as text beside it. */
  working?(blocks: Working[]): void;
  /** The section outside the chapters the learner is in (its head with tabs and the way back), or null in the lesson. */
  section?(v: SectionView | null): void;
}

/** An end card that chooses where to go next: its words and one button per way on. */
export interface EndCard { eyebrow?: string; title?: string; lede?: string; choices: { label: string; go(): void; kind?: ButtonKind }[]; next?: { label: string; href?: string } }
/** A button's rank: the one way on, another real choice, or help and exits. */
export type ButtonKind = 'primary' | 'secondary' | 'quiet';

/** A block of working drawn on the plate (a note, a figure's readouts): its title and the rows drawn so far. */
export interface Working { title: string; rows: string[] }

/** Live values for callouts (`now`, by term) and the drawn working (`working`), computed from state. */
export interface Live<S> { now(term: string, s: S): string | null; working?(s: S): Working[] }

/** The unit's side: its state, the narrated watch built on the cue sheet, and its live values. */
export interface UnitDef<S> {
  initial(): S;
  watch: { order: string[]; lead: number; gap: number; build(s: S, cue: CueBinder): Timeline };
  live?: Live<S>;
}

/** A hand that drives one state number; `glow` is the state key the style uses to light it. */
export interface Control<S> { hand: Hand; key: keyof S; glow?: keyof S }
