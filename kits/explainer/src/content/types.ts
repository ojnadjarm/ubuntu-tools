/** Compiled unit data from `kokoro-narration`: pure types, no behaviour. */
export interface Word { w: string; s: number; e: number }
export interface Clip { src: string; duration: number; marks: Record<string, number>; words: Word[] }
export interface CueSheet { clips: Record<string, Clip>; bias: number }
/** A term the narration names: `namedCue` is a mark (`mark` or `clip.mark`) or a play clip id; `part` is the hotspot that shows it. */
export interface Term { id: string; word: string; gloss: string; namedCue: string; part?: string; formula?: { text: string; after: string }; why?: string }
/** A chapter: watch clips on the axis, or a beat (Your turn, the ending); a beat chapter's `clips` only time it. */
export interface ChapterSpec { id: string; numeral: string; title: string; clips?: string[]; beat?: string }
/** A numbered part of the drawing: the balloon number, the drawn part, its term and the callout its number opens (default the term). */
export interface PartSpec { id: string; n?: number; name: string; term: string; callout?: string }
/** A callout on one drawn number or part: title and one line; it unlocks with its term, or at its cue (`clip.mark`) when given; `said: false` marks a tool of the exercises no sentence says (its note has no Hear it). */
export interface CalloutSpec { id: string; term: string; title: string; what: string; cue?: string; said?: false }
/** A sentence: text with `{cue}` marks, or an object with the text plus the unit's own data (values, figures, `asserts`). */
type Sentence = string | { text: string; asserts?: string[]; [key: string]: unknown };
export interface ClipSpec { id: string; beat?: string; focus?: string; sentences: Sentence[] }
/** An exercise as data: its kind (a registered gesture), its answer space, the misconceptions it catches and the clips it says. */
export interface ExerciseSpec { id: string; title: string; kind: string; answerSpace: string; rounds: number; catches: string[]; clips: Record<string, string> }
/** A wrong belief the exercises listen for: the exercise that catches it, its refutation clip and its contrast-pair clip. */
export interface MisconceptionSpec { id: string; belief: string; truth: string; catcher: string; refute: string; contrast?: string }
/** The narration script (`unit.json`): one entry per clip, sentences with `{cue}` marks; chapters, terms, parts and callouts for the player; exercises and misconceptions for the bench. */
export interface UnitSpec {
  id?: string; title?: string; introduces?: Term[]; chapters?: ChapterSpec[]; parts?: PartSpec[]; callouts?: CalloutSpec[]; clips: ClipSpec[];
  exercises?: ExerciseSpec[]; misconceptions?: MisconceptionSpec[];
}
export interface UnitBundle { spec: UnitSpec; cues: CueSheet; base: string }

/** The spoken text of a sentence, marks included. */
export const textOf = (s: Sentence): string => (typeof s === 'string' ? s : s.text);
